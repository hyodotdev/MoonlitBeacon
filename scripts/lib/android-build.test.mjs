import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  ANDROID_APP_PACKAGE,
  ANDROID_LOCALIZED_APP_NAMES,
  androidArchiveExcludesDevelopmentResources,
  androidReleasePartialPath,
  androidV4SignatureSidecarPath,
  aabVerificationIsSigned,
  assertAndroidDirectDistributionRuntimeState,
  assertAndroidDistributionFeatureContract,
  assertAndroidReleaseMetadata,
  assertAndroidSigningCertificateValid,
  invalidateAndroidBuildOutput,
  parseAndroidApkLocalizedAppNames,
  parseAndroidBuildFlags,
  parseAndroidBundleLocalizedAppNames,
  publishAndroidBuildOutput,
  publishAndroidReleaseCopy,
  readAndroidReleaseMetadata,
  resolveAndroidAapt2Path,
  resolveAndroidApkSignerPath,
  resolveAndroidJavaToolInvocation,
  signDebugAndroidBundle,
  verifyAndroidArchiveBillingBoundary,
  verifyAndroidArchiveIapBoundary,
  verifyAndroidArchiveResourceBoundary,
  verifyAndroidLocalizedAppNames,
  verifyAndroidReleaseSigner,
  verifySignedAndroidBundle,
} from './android-build.mjs';
import { parseCsv } from './app-store-release.mjs';

const REPO_ROOT = fileURLToPath(new URL('../..', import.meta.url));
const LOCALIZED_APP_NAMES = Object.fromEntries(
  ANDROID_LOCALIZED_APP_NAMES.map(({ projectLocale, displayName }) => [
    projectLocale,
    displayName,
  ]),
);

const CERTIFICATE_A = [
  '-----BEGIN CERTIFICATE-----',
  'QUJD',
  '-----END CERTIFICATE-----',
].join('\n');
const CERTIFICATE_B = [
  '-----BEGIN CERTIFICATE-----',
  'REVG',
  '-----END CERTIFICATE-----',
].join('\n');
const CERTIFICATE_A_SHA256 = createHash('sha256')
  .update(Buffer.from('QUJD', 'base64'))
  .digest('hex');

test('rejects Android build option typos and conflicting signing modes', () => {
  assert.deepEqual(parseAndroidBuildFlags(['--bundle', '--release']), {
    bundle: true,
    debug: false,
    release: true,
  });
  assert.throws(
    () => parseAndroidBuildFlags(['--relase']),
    /Unsupported Android build option/,
  );
  assert.throws(
    () => parseAndroidBuildFlags(['--debug', '--release']),
    /cannot be used together/,
  );
});

test('verifies package and version contracts for both Android distribution channels at once', () => {
  const project = [
    'config/version="1.2.3"',
    'config/name_localized={',
    '"en": "Moonlit Beacon",',
    '"ja": "月明かりの烽火",',
    '"ko": "달빛 봉화",',
    '"zh": "月光烽火",',
    '"zh_TW": "月光烽火"',
    '}',
    '',
  ].join('\n');
  const presets = [
    '[preset.0]',
    'name="Android"',
    'custom_features="direct_distribution"',
    '[preset.0.options]',
    'plugins/GodotIap=false',
    'version/code=7',
    'version/name="1.2.3"',
    'package/unique_name="com.example.game"',
    '[preset.1]',
    'name="Android Play"',
    'custom_features="iap_store"',
    '[preset.1.options]',
    'plugins/GodotIap=true',
    'version/code=7',
    'version/name="1.2.3"',
    'package/unique_name="com.example.game"',
  ].join('\n');
  const metadata = readAndroidReleaseMetadata(project, presets);
  assert.deepEqual(metadata, {
    projectVersion: '1.2.3',
    localizedAppNames: LOCALIZED_APP_NAMES,
    direct: {
      packageName: 'com.example.game',
      versionCode: 7,
      versionName: '1.2.3',
    },
    play: {
      packageName: 'com.example.game',
      versionCode: 7,
      versionName: '1.2.3',
    },
  });
  assert.equal(
    assertAndroidReleaseMetadata(metadata, {
      expectedPackageName: 'com.example.game',
    }),
    true,
  );
  assert.throws(
    () => assertAndroidReleaseMetadata({
      ...metadata,
      play: { ...metadata.play, versionCode: 8 },
    }, {
      expectedPackageName: 'com.example.game',
    }),
    /version\/code differ/,
  );
  assert.throws(
    () => assertAndroidReleaseMetadata({
      ...metadata,
      direct: { ...metadata.direct, versionName: '1.2.2' },
    }, {
      expectedPackageName: 'com.example.game',
    }),
    /project version/,
  );
  assert.throws(
    () => assertAndroidReleaseMetadata({
      ...metadata,
      direct: { ...metadata.direct, versionCode: 2_100_000_001 },
      play: { ...metadata.play, versionCode: 2_100_000_001 },
    }, {
      expectedPackageName: 'com.example.game',
    }),
    /allowed range/,
  );
  assert.throws(
    () => assertAndroidReleaseMetadata({
      ...metadata,
      localizedAppNames: {
        ...metadata.localizedAppNames,
        ko: 'Moonlit Beacon',
      },
    }, {
      expectedPackageName: 'com.example.game',
    }),
    /ko home-screen name does not match store localization/,
  );
  assert.throws(
    () => assertAndroidDistributionFeatureContract(
      presets.replace('custom_features="direct_distribution"', 'custom_features=""'),
    ),
    /direct_distribution/u,
  );
  assert.throws(
    () => assertAndroidDistributionFeatureContract(
      presets.replace('plugins/GodotIap=false', 'plugins/GodotIap=true'),
    ),
    /plugins\/GodotIap must be false/u,
  );
  assert.throws(
    () => assertAndroidDistributionFeatureContract(
      presets.replace('custom_features="iap_store"', 'custom_features="direct_distribution"'),
    ),
    /Android Play custom_features/u,
  );
});

test('repository Android presets split direct distribution from the Play IAP feature', () => {
  const project = readFileSync(
    join(REPO_ROOT, 'apps/game/project.godot'),
    'utf8',
  );
  const presets = readFileSync(
    join(REPO_ROOT, 'apps/game/export_presets.cfg'),
    'utf8',
  );
  assert.equal(
    assertAndroidDistributionFeatureContract(presets),
    true,
  );
  assert.equal(
    assertAndroidReleaseMetadata(
      readAndroidReleaseMetadata(project, presets),
      { expectedPackageName: ANDROID_APP_PACKAGE },
    ),
    true,
  );
  const buildScript = readFileSync(
    join(REPO_ROOT, 'scripts/android-build.mjs'),
    'utf8',
  );
  assert.match(buildScript, /assertAndroidDistributionFeatureContract\(exportPresetsSource\)/u);
});

test('installed direct-distribution APK proof blocks storefront, cached entitlements, and the title store together', () => {
  const valid = {
    kind: 'direct_distribution',
    ready: true,
    direct_distribution_feature: true,
    storefront_enabled: false,
    store_state_unavailable: true,
    cached_paid_entitlement_product_id:
      'com.crossplatformkorea.moonlitbeacon.hero_dancer',
    cached_paid_entitlement_hero_path:
      'res://resources/heroes/dancer.tres',
    cached_paid_entitlement_fixture_present: true,
    cached_paid_entitlement_owned: false,
    cached_paid_entitlement_ignored: true,
    cached_paid_entitlements_restored: true,
    title_screen_visible: true,
    title_store_button_present: true,
    title_store_button_self_visible: false,
    title_store_button_visible_in_tree: false,
    title_store_button_enabled: false,
    title_store_button_hidden: true,
  };
  assert.deepEqual(
    assertAndroidDirectDistributionRuntimeState(valid),
    {
      productId: 'com.crossplatformkorea.moonlitbeacon.hero_dancer',
      heroPath: 'res://resources/heroes/dancer.tres',
      storefrontEnabled: false,
      cachedEntitlementOwned: false,
      titleStoreButtonVisible: false,
    },
  );
  for (const [field, value, pattern] of [
    ['direct_distribution_feature', false, /direct_distribution feature/u],
    ['storefront_enabled', true, /storefront_enabled/u],
    ['cached_paid_entitlement_owned', true, /owns/u],
    ['cached_paid_entitlement_ignored', false, /paid entitlement blocked/u],
    ['cached_paid_entitlements_restored', false, /probe restored/u],
    ['title_store_button_self_visible', true, /hidden and disabled/u],
    ['title_store_button_visible_in_tree', true, /hidden and disabled/u],
    ['title_store_button_enabled', true, /hidden and disabled/u],
  ]) {
    assert.throws(
      () => assertAndroidDirectDistributionRuntimeState({
        ...valid,
        [field]: value,
      }),
      pattern,
    );
  }
});

test('Android phone and tablet capture must run the exported direct runtime probe', () => {
  const probe = readFileSync(
    join(REPO_ROOT, 'apps/game/scripts/dev/store_capture_probe.gd'),
    'utf8',
  );
  assert.match(probe, /"direct_distribution"/u);
  assert.match(
    probe,
    /kind != "direct_distribution"[\s\S]*debug_prepare_store_capture/u,
    'must not run screenshot prepare when inspecting the normal title',
  );
  assert.match(probe, /store\.call\("storefront_enabled"\)/u);
  assert.match(probe, /store\.call\("owns", DIRECT_PROBE_PRODUCT_ID\)/u);
  assert.match(probe, /store\.set\("entitlements", entitlements_before\)/u);
  assert.match(probe, /not store_button\.disabled/u);

  for (const relativePath of [
    'scripts/capture-store-screenshots.mjs',
    'scripts/capture-android-tablet-evidence.mjs',
  ]) {
    const source = readFileSync(join(REPO_ROOT, relativePath), 'utf8');
    assert.match(source, /assertAndroidDirectDistributionRuntimeState/u);
    assert.match(source, /verifyInstalledDirectDistributionRuntime/u);
    assert.match(source, /kind: 'direct_distribution'/u);
    assert.match(source, /installedApkSha256/u);
  }
});

test('Android home-screen name baseline matches the five Google Play CSV languages', () => {
  const [header, ...body] = parseCsv(readFileSync(
    join(REPO_ROOT, 'notes/release/store-localizations.csv'),
    'utf8',
  ));
  const rows = body.map((values) => Object.fromEntries(
    header.map((column, index) => [column, values[index]]),
  ));
  const storeNames = rows
    .filter((row) => row.record_type === 'app' && row.platform === 'google')
    .map((row) => ({
      storeLocale: row.locale,
      displayName: row.display_name,
    }));
  const canonicalNames = ANDROID_LOCALIZED_APP_NAMES.map(
    ({ storeLocale, displayName }) => ({ storeLocale, displayName }),
  );
  assert.deepEqual(storeNames, canonicalNames);
  assert.deepEqual(
    ANDROID_LOCALIZED_APP_NAMES.map(({ resourceLocale }) => resourceLocale),
    ['en', 'ko', 'ja', 'zh', 'zh-TW'],
  );
});

test('verifies the Android release signer certificate is currently valid', () => {
  const certificate = Buffer.from('certificate');
  assert.equal(
    assertAndroidSigningCertificateValid(certificate, {
      now: new Date('2026-07-30T00:00:00Z'),
      parse: () => ({
        validFrom: '2026-01-01T00:00:00Z',
        validTo: '2040-01-01T00:00:00Z',
      }),
    }),
    true,
  );
  assert.throws(
    () => assertAndroidSigningCertificateValid(certificate, {
      now: new Date('2040-01-01T00:00:00Z'),
      parse: () => ({
        validFrom: '2026-01-01T00:00:00Z',
        validTo: '2040-01-01T00:00:00Z',
      }),
    }),
    /expired/,
  );
  assert.throws(
    () => assertAndroidSigningCertificateValid(certificate, {
      now: new Date('2026-07-30T00:00:00Z'),
      parse: () => ({
        validFrom: '2026-01-01T00:00:00Z',
        validTo: '2033-10-22T00:00:00Z',
      }),
    }),
    /2033-10-22 and beyond/,
  );
});

test('on macOS uses signing tools from the detected JDK 17 instead of PATH', () => {
  assert.deepEqual(
    resolveAndroidJavaToolInvocation('keytool', {
      env: { JAVA_HOME: '/jdk17' },
      platform: 'darwin',
    }),
    {
      command: '/jdk17/bin/keytool',
      prefixArgs: [],
    },
  );
  assert.deepEqual(
    resolveAndroidJavaToolInvocation('jarsigner', {
      env: {},
      platform: 'linux',
    }),
    { command: 'jarsigner', prefixArgs: [] },
  );
});

function encodeVarint(value) {
  let remaining = BigInt(value);
  const bytes = [];
  do {
    let byte = Number(remaining & 0x7fn);
    remaining >>= 7n;
    if (remaining > 0n) byte |= 0x80;
    bytes.push(byte);
  } while (remaining > 0n);
  return Buffer.from(bytes);
}

function protobufBytes(field, value) {
  return Buffer.concat([
    encodeVarint((field << 3) | 2),
    encodeVarint(value.length),
    value,
  ]);
}

function protobufString(field, value) {
  return protobufBytes(field, Buffer.from(value, 'utf8'));
}

function localizedNameResourceTable(overrides = {}) {
  const names = {
    '': 'Moonlit Beacon',
    ...Object.fromEntries(
      ANDROID_LOCALIZED_APP_NAMES.map(({ resourceLocale, displayName }) => [
        resourceLocale,
        displayName,
      ]),
    ),
    ...overrides,
  };
  const configValues = Object.entries(names).map(([locale, displayName]) => {
    const config = locale ? protobufString(3, locale) : Buffer.alloc(0);
    const stringValue = protobufString(1, displayName);
    const item = protobufBytes(2, stringValue);
    const value = protobufBytes(4, item);
    return protobufBytes(
      6,
      Buffer.concat([
        protobufBytes(1, config),
        protobufBytes(2, value),
      ]),
    );
  });
  const entry = Buffer.concat([
    protobufString(2, 'godot_project_name_string'),
    ...configValues,
  ]);
  const type = Buffer.concat([
    protobufString(2, 'string'),
    protobufBytes(3, entry),
  ]);
  const resourcePackage = Buffer.concat([
    protobufString(2, ANDROID_APP_PACKAGE),
    protobufBytes(3, type),
  ]);
  return protobufBytes(2, resourcePackage);
}

function localizedNameBadging(overrides = {}) {
  const names = {
    '': 'Moonlit Beacon',
    ...Object.fromEntries(
      ANDROID_LOCALIZED_APP_NAMES.map(({ resourceLocale, displayName }) => [
        resourceLocale,
        displayName,
      ]),
    ),
    ...overrides,
  };
  return Object.entries(names)
    .map(([locale, displayName]) =>
      `application-label${locale ? `-${locale}` : ''}:'${displayName}'`)
    .join('\n') + '\n';
}

test('directly verifies five home-screen names from APK and AAB resource tables', () => {
  const expected = {
    '': 'Moonlit Beacon',
    en: 'Moonlit Beacon',
    ko: '달빛 봉화',
    ja: '月明かりの烽火',
    zh: '月光烽火',
    'zh-TW': '月光烽火',
  };
  assert.deepEqual(
    parseAndroidBundleLocalizedAppNames(localizedNameResourceTable()),
    expected,
  );
  assert.deepEqual(
    parseAndroidApkLocalizedAppNames(localizedNameBadging()),
    expected,
  );
  assert.equal(
    verifyAndroidLocalizedAppNames('/tmp/release.aab', {
      archiveType: 'aab',
      spawn: (command, args, options) => {
        assert.equal(command, 'unzip');
        assert.deepEqual(args, [
          '-p',
          '/tmp/release.aab',
          'base/resources.pb',
        ]);
        assert.equal(options.encoding, null);
        return { status: 0, stdout: localizedNameResourceTable() };
      },
    }),
    true,
  );
  assert.equal(
    verifyAndroidLocalizedAppNames('/tmp/release.apk', {
      archiveType: 'apk',
      resolveAapt2: () => '/sdk/aapt2',
      spawn: (command, args, options) => {
        assert.equal(command, '/sdk/aapt2');
        assert.deepEqual(args, ['dump', 'badging', '/tmp/release.apk']);
        assert.equal(options.encoding, 'utf8');
        return { status: 0, stdout: localizedNameBadging() };
      },
    }),
    true,
  );
  assert.throws(
    () => verifyAndroidLocalizedAppNames('/tmp/release.aab', {
      archiveType: 'aab',
      spawn: () => ({
        status: 0,
        stdout: localizedNameResourceTable({ ko: 'Moonlit Beacon' }),
      }),
    }),
    /ko home-screen name does not match store localization/,
  );
  assert.throws(
    () => verifyAndroidLocalizedAppNames('/tmp/release.apk', {
      archiveType: 'apk',
      resolveAapt2: () => '/sdk/aapt2',
      spawn: () => ({
        status: 0,
        stdout: localizedNameBadging({ ja: 'Moonlit Beacon' }),
      }),
    }),
    /ja home-screen name does not match store localization/,
  );
});

test('verifies the test and production-tool boundary in the Android package', () => {
  assert.equal(
    androidArchiveExcludesDevelopmentResources(
      'assets/scripts/dev/test_launcher.gdc\nassets/scenes/menus/title_menu.scn\n',
    ),
    true,
  );
  assert.equal(
    androidArchiveExcludesDevelopmentResources(
      'assetPackInstallTime/assets/tests/test_vault.gdc\n',
    ),
    false,
  );
  assert.equal(
    androidArchiveExcludesDevelopmentResources(
      'assets/tools/check_scripts.gdc\n',
    ),
    false,
  );
  assert.equal(
    verifyAndroidArchiveResourceBoundary('/tmp/release.aab', {
      spawn: (command, args, options) => {
        assert.equal(command, 'jar');
        assert.deepEqual(args, ['tf', '/tmp/release.aab']);
        assert.ok(options.timeout > 0);
        assert.equal(options.killSignal, 'SIGTERM');
        return {
          status: 0,
          stdout: 'assetPackInstallTime/assets/scripts/ui/title_menu.gdc\n',
        };
      },
    }),
    true,
  );
  assert.throws(
    () => verifyAndroidArchiveResourceBoundary('/tmp/release.aab', {
      spawn: () => ({
        status: 0,
        stdout: 'assetPackInstallTime/assets/tests/test_vault.gdc\n',
      }),
    }),
    /test or production-tool/,
  );
});

test('verifies IAPKit config count and pk-only contents per Android distribution channel', () => {
  const storeSpawn = (command, args) => {
    if (command === 'jar') {
      return {
        status: 0,
        stdout: 'assetPackInstallTime/assets/iapkit.cfg\n',
      };
    }
    assert.equal(command, 'unzip');
    assert.deepEqual(args, [
      '-p',
      '/tmp/release.aab',
      'assetPackInstallTime/assets/iapkit.cfg',
    ]);
    return {
      status: 0,
      stdout: '[iapkit]\n'
        + `api_key="openiap-kit_pk_${'a'.repeat(32)}"\n`,
    };
  };
  assert.equal(
    verifyAndroidArchiveIapBoundary('/tmp/release.aab', {
      spawn: storeSpawn,
      store: true,
    }),
    true,
  );
  assert.equal(
    verifyAndroidArchiveIapBoundary('/tmp/direct.apk', {
      spawn: () => ({ status: 0, stdout: 'assets/game.pck\n' }),
      store: false,
    }),
    true,
  );
  assert.throws(
    () => verifyAndroidArchiveIapBoundary('/tmp/direct.apk', {
      spawn: () => ({ status: 0, stdout: 'assets/iapkit.cfg\n' }),
      store: false,
    }),
    /Direct-distribution/,
  );
  assert.throws(
    () => verifyAndroidArchiveIapBoundary('/tmp/release.aab', {
      spawn: (command) => command === 'jar'
        ? {
          status: 0,
          stdout: 'assetPackInstallTime/assets/iapkit.cfg\n',
        }
        : {
          status: 0,
          stdout: '[iapkit]\n'
            + `api_key="openiap-kit_sk_${'a'.repeat(32)}"\n`,
        },
      store: true,
    }),
    /is not safe/,
  );
  assert.throws(
    () => verifyAndroidArchiveIapBoundary('/tmp/release.aab', {
      spawn: (command) => command === 'jar'
        ? {
          status: 0,
          stdout: 'assetPackInstallTime/assets/iapkit.cfg\n',
        }
        : {
          status: 0,
          stdout: '[iapkit]\n'
            + `api_key="openiap-kit_pk_${'a'.repeat(32)}"\n`
            + 'api_key="unexpected"\n',
        },
      store: true,
    }),
    /is not safe/,
  );
  assert.throws(
    () => verifyAndroidArchiveIapBoundary('/tmp/release.aab', {
      spawn: () => ({ status: 0, stdout: 'assets/game.pck\n' }),
      store: true,
    }),
    /config count is not 1/,
  );
});

test('verifies Billing permission and DEX code together per Android distribution channel', () => {
  const billingPermission = Buffer.from('com.android.vending.BILLING');
  const billingClient = Buffer.from('Lcom/android/billingclient/api/Client;');
  const storeSpawn = (command, args) => {
    if (command === 'jar') {
      return {
        status: 0,
        stdout: [
          'base/manifest/AndroidManifest.xml',
          'base/dex/classes.dex',
        ].join('\n'),
      };
    }
    assert.equal(command, 'unzip');
    return {
      status: 0,
      stdout: args[2].includes('manifest')
        ? billingPermission
        : billingClient,
    };
  };
  assert.equal(
    verifyAndroidArchiveBillingBoundary('/tmp/release.aab', {
      spawn: storeSpawn,
      store: true,
    }),
    true,
  );
  assert.equal(
    verifyAndroidArchiveBillingBoundary('/tmp/direct.apk', {
      spawn: (command, args) => command === 'jar'
        ? {
          status: 0,
          stdout: 'AndroidManifest.xml\nclasses.dex\n',
        }
        : { status: 0, stdout: Buffer.from(`safe ${args[2]}`) },
      store: false,
    }),
    true,
  );
  assert.throws(
    () => verifyAndroidArchiveBillingBoundary('/tmp/direct.apk', {
      spawn: (command, args) => command === 'jar'
        ? {
          status: 0,
          stdout: 'AndroidManifest.xml\nclasses.dex\n',
        }
        : {
          status: 0,
          stdout: args[2] === 'AndroidManifest.xml'
            ? Buffer.from('safe')
            : billingClient,
        },
      store: false,
    }),
    /Direct-distribution/,
  );
  assert.throws(
    () => verifyAndroidArchiveBillingBoundary('/tmp/release.aab', {
      spawn: (command, args) => command === 'jar'
        ? {
          status: 0,
          stdout: [
            'base/manifest/AndroidManifest.xml',
            'base/dex/classes.dex',
          ].join('\n'),
        }
        : {
          status: 0,
          stdout: args[2].includes('manifest')
            ? billingPermission
            : Buffer.from('safe'),
        },
      store: true,
    }),
    /no Billing permission or client code/,
  );
});

test('invalidates only this run\'s exact output after taking the Android lock', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-android-output-'));
  const apk = join(root, 'MoonlitBeacon.apk');
  const aab = join(root, 'MoonlitBeacon.aab');
  try {
    writeFileSync(apk, 'previous apk');
    writeFileSync(aab, 'previous aab');

    assert.equal(invalidateAndroidBuildOutput(apk, true), true);
    assert.equal(existsSync(apk), false);
    assert.equal(existsSync(aab), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('APK v4 signature sidecar shares the same lifetime as the main APK', () => {
  assert.equal(
    androidV4SignatureSidecarPath('/tmp/MoonlitBeacon.apk'),
    '/tmp/MoonlitBeacon.apk.idsig',
  );
  assert.throws(
    () => androidV4SignatureSidecarPath(''),
    /destination path is empty/,
  );
});

test('publishes a verified versioned APK atomically from a partial file', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-android-release-copy-'));
  try {
    const source = join(root, 'MoonlitBeacon.apk');
    const output = join(root, 'MoonlitBeacon-1.2.3.apk');
    writeFileSync(source, 'verified release');
    writeFileSync(output, 'stale release');

    assert.equal(publishAndroidReleaseCopy(source, output, true), true);
    assert.equal(readFileSync(output, 'utf8'), 'verified release');
    assert.equal(existsSync(androidReleasePartialPath(output)), false);

    writeFileSync(output, 'stale again');
    assert.throws(
      () => publishAndroidReleaseCopy(source, output, true, {
        copy: (_source, partial) => {
          writeFileSync(partial, 'incomplete');
          throw new Error('copy interrupted');
        },
      }),
      /copy interrupted/,
    );
    assert.equal(existsSync(output), false);
    assert.equal(existsSync(androidReleasePartialPath(output)), false);

    writeFileSync(output, 'preserve without lock');
    assert.throws(
      () => publishAndroidReleaseCopy(source, output, false),
      /without the Android build lock/,
    );
    assert.equal(readFileSync(output, 'utf8'), 'preserve without lock');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('Android canonical output is visible only after renaming the verified candidate', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-android-publish-'));
  try {
    const candidate = join(root, '.MoonlitBeacon-partial.apk');
    const output = join(root, 'MoonlitBeacon.apk');
    writeFileSync(candidate, 'verified candidate');
    writeFileSync(output, 'stale canonical');
    assert.equal(
      publishAndroidBuildOutput(candidate, output, true),
      true,
    );
    assert.equal(readFileSync(output, 'utf8'), 'verified candidate');
    assert.equal(existsSync(candidate), false);

    writeFileSync(candidate, 'second candidate');
    assert.throws(
      () => publishAndroidBuildOutput(candidate, output, true, {
        rename: () => {
          throw new Error('rename interrupted');
        },
      }),
      /rename interrupted/,
    );
    assert.equal(existsSync(candidate), false);
    assert.equal(existsSync(output), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('preserves existing output when an active Android lock conflicts', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-android-lock-'));
  const output = join(root, 'MoonlitBeacon.aab');
  try {
    writeFileSync(output, 'active build output');

    assert.equal(invalidateAndroidBuildOutput(output, false), false);
    assert.equal(existsSync(output), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('rejects an unsigned AAB even when jarsigner exit code is 0', () => {
  assert.equal(aabVerificationIsSigned({
    status: 0,
    stdout: 'no manifest.\n\njar is unsigned.\n',
    stderr: '',
  }), false);
  assert.throws(
    () => verifySignedAndroidBundle('/tmp/unsigned.aab', {
      platform: 'linux',
      spawn: () => ({
        status: 0,
        stdout: 'no manifest.\n\njar is unsigned.\n',
        stderr: '',
      }),
    }),
    /signature is missing or invalid/,
  );
});

test('rejects an AAB with some unsigned entries regardless of the jar verified phrase', () => {
  assert.equal(aabVerificationIsSigned({
    status: 0,
    stdout: [
      '',
      'jar verified.',
      '',
      'Warning:',
      'This jar contains unsigned entries which have not been integrity-checked.',
    ].join('\n'),
    stderr: '',
  }), false);
});

test('accepts an AAB only when the cryptographic verification phrase is present', () => {
  assert.equal(aabVerificationIsSigned({
    status: 0,
    stdout: '\njar verified.\n',
    stderr: 'self-signed warning',
  }), true);
  assert.equal(
    verifySignedAndroidBundle('/tmp/signed.aab', {
      platform: 'linux',
      spawn: (_command, _args, options) => {
        assert.equal(options.env.LANG, 'C');
        assert.equal(options.env.LC_ALL, 'C');
        return {
          status: 0,
          stdout: '\njar verified.\n',
          stderr: '',
        };
      },
    }),
    true,
  );
});

test('signs a debug AAB with the designated keystore and verifies it again', () => {
  const calls = [];
  assert.equal(
    signDebugAndroidBundle('/tmp/debug.aab', {
      keystorePath: '/tmp/debug.keystore',
      exists: () => true,
      platform: 'linux',
      spawn: (command, args) => {
        calls.push({ command, args });
        if (args[0] === '-verify') {
          return {
            status: 0,
            stdout: '\njar verified.\n',
            stderr: '',
          };
        }
        return { status: 0, stdout: '', stderr: '' };
      },
    }),
    true,
  );
  assert.equal(calls.length, 2);
  assert.equal(calls[0].command, 'jarsigner');
  assert.deepEqual(calls[0].args.slice(0, 2), [
    '-keystore',
    '/tmp/debug.keystore',
  ]);
  assert.deepEqual(calls[1].args, ['-verify', '/tmp/debug.aab']);
});

test('picks apksigner from the newest Android build-tools', () => {
  assert.equal(
    resolveAndroidApkSignerPath({
      env: { ANDROID_HOME: '/sdk' },
      exists: (path) => path === '/sdk/build-tools/36.0.0/apksigner',
      readDir: () => ['35.0.1', '36.0.0', '9.0.0'],
    }),
    '/sdk/build-tools/36.0.0/apksigner',
  );
  assert.throws(
    () => resolveAndroidApkSignerPath({
      env: { MOONLIT_APKSIGNER_BIN: '/missing/apksigner' },
      exists: () => false,
    }),
    /was not found/,
  );
});

test('picks aapt2 from the newest Android build-tools', () => {
  assert.equal(
    resolveAndroidAapt2Path({
      env: { ANDROID_HOME: '/sdk' },
      exists: (path) => path === '/sdk/build-tools/36.0.0/aapt2',
      platform: 'linux',
      readDir: () => ['35.0.1', '36.0.0', '9.0.0'],
    }),
    '/sdk/build-tools/36.0.0/aapt2',
  );
  assert.throws(
    () => resolveAndroidAapt2Path({
      env: { MOONLIT_AAPT2_BIN: '/missing/aapt2' },
      exists: () => false,
    }),
    /was not found/,
  );
});

test('release AAB signer matches the specified keystore and password is not in args or env', () => {
  const calls = [];
  assert.equal(
    verifyAndroidReleaseSigner('/tmp/release.aab', {
      alias: 'upload',
      archiveType: 'aab',
      env: {
        PATH: '/usr/bin',
        GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: 'must-not-leak',
      },
      keystorePath: '/secure/upload.jks',
      password: 'must-not-leak',
      platform: 'linux',
      validateCertificate: (certificate) => {
        assert.deepEqual(certificate, Buffer.from('ABC'));
      },
      spawn: (command, args, options) => {
        calls.push({ command, args, options });
        assert.equal(args.includes('must-not-leak'), false);
        assert.equal(
          options.env.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD,
          undefined,
        );
        assert.ok(options.timeout > 0);
        assert.equal(options.killSignal, 'SIGTERM');
        if (command === 'jarsigner') {
          return { status: 0, stdout: '\njar verified.\n', stderr: '' };
        }
        if (args[0] === '-exportcert') {
          assert.equal(options.input, 'must-not-leak\n');
          return { status: 0, stdout: CERTIFICATE_A, stderr: '' };
        }
        return { status: 0, stdout: CERTIFICATE_A, stderr: '' };
      },
    }),
    true,
  );
  assert.deepEqual(
    calls.map(({ command, args }) => [command, args[0]]),
    [
      ['keytool', '-exportcert'],
      ['jarsigner', '-verify'],
      ['keytool', '-printcert'],
    ],
  );
});

test('verifies the release APK signer with apksigner and rejects a different certificate', () => {
  const verify = (actualCertificate) => verifyAndroidReleaseSigner(
    '/tmp/release.apk',
    {
      alias: 'upload',
      apksignerPath: '/sdk/apksigner',
      archiveType: 'apk',
      env: { PATH: '/usr/bin' },
      keystorePath: '/secure/upload.jks',
      password: 'secret',
      platform: 'linux',
      validateCertificate: () => true,
      spawn: (command, args) => {
        if (command === 'keytool') {
          return { status: 0, stdout: CERTIFICATE_A, stderr: '' };
        }
        assert.equal(command, '/sdk/apksigner');
        assert.deepEqual(args, [
          'verify',
          '--verbose',
          '--print-certs',
          '/tmp/release.apk',
        ]);
        const digest = createHash('sha256')
          .update(Buffer.from(
            actualCertificate === CERTIFICATE_A ? 'QUJD' : 'REVG',
            'base64',
          ))
          .digest('hex');
        return {
          status: 0,
          stdout: `Signer #1 certificate SHA-256 digest: ${digest}\n`,
          stderr: '',
        };
      },
    },
  );
  assert.equal(verify(CERTIFICATE_A), true);
  assert.equal(CERTIFICATE_A_SHA256.length, 64);
  assert.throws(() => verify(CERTIFICATE_B), /does not match the specified keystore/);
});

test('rejects a release keystore that yields more than one signer certificate', () => {
  assert.throws(
    () => verifyAndroidReleaseSigner('/tmp/release.apk', {
      alias: 'upload',
      apksignerPath: '/sdk/apksigner',
      archiveType: 'apk',
      env: { PATH: '/usr/bin' },
      keystorePath: '/secure/upload.jks',
      password: 'secret',
      platform: 'linux',
      spawn: (command) => {
        assert.equal(command, 'keytool');
        return {
          status: 0,
          stdout: `${CERTIFICATE_A}\n${CERTIFICATE_B}`,
          stderr: '',
        };
      },
      validateCertificate: () => true,
    }),
    /Failed to read the signer certificate/,
  );
});
