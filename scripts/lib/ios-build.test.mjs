import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  cleanupIncompleteIosExportDirectory,
  cleanupStaleIosWorkflowExportDirectory,
  configureGeneratedIosInfoPlistLocalizations,
  devicectlResultContainsBundle,
  formatIosWorkflowError,
  ideviceInstallerResultContainsBundle,
  IOS_DEV_ASSET_FALLBACK_SETTINGS,
  IOS_DEV_LEGACY_ICON_PREFIX,
  IOS_IAP_FRAMEWORK_NAMES,
  IOS_LOCALIZED_DISPLAY_NAMES,
  IOS_PROCESS_GROUP_TERM_GRACE_MS,
  IOS_UNUSED_PRIVACY_DESCRIPTION_KEYS,
  installIosDevelopmentFallbackIcon,
  isAssetCatalogSimulatorPolicyFailure,
  iosDebugAppPath,
  iosDebugBuildArguments,
  iosDevelopmentLegacyIconFiles,
  jsonContainsExactString,
  parseUsbMuxDeviceIds,
  pckExcludesDevelopmentResources,
  pckHasSafeIapKitConfig,
  prepareIosExportDirectory,
  runCoreDeviceInstallFlow,
  runIosDebugBuildWithFallback,
  runIosInstallWithFallback,
  runUsbMuxInstallFlow,
  shouldUseIosAssetFallback,
  spawnSyncInIosProcessGroup,
  terminateIosProcessGroup,
  usbMuxInstallArguments,
  usbMuxLaunchArguments,
  usbMuxListArguments,
  verifyIosLocalizedDisplayNames,
  verifyInstallableIosApp,
} from './ios-build.mjs';
import { parseCsv } from './app-store-release.mjs';

const SCHEME = 'MoonlitBeacon';
const BUNDLE = 'com.crossplatformkorea.moonlitbeacon';
const FAKE_USBMUX_UDID = 'DEADBEEF-0000000000000001';
const FAKE_PUBLISHABLE_KEY = `openiap-kit_pk_${'A'.repeat(64)}`;
const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const IAP_EMBED_FIXER = join(
  REPO_ROOT,
  'apps/game/addons/godot-iap/scripts/fix_ios_embed.sh',
);
const STORE_LOCALIZATIONS_CSV = join(
  REPO_ROOT,
  'notes/release/store-localizations.csv',
);

test('xcodebuild failure TERM then KILL only its own process group', () => {
  const spawnCalls = [];
  const signals = [];
  const pauses = [];
  const result = spawnSyncInIosProcessGroup(
    'xcodebuild',
    ['archive'],
    { timeout: 1000 },
    {
      spawn: (command, args, options) => {
        spawnCalls.push({ command, args, options });
        return {
          error: Object.assign(new Error('timed out'), {
            code: 'ETIMEDOUT',
          }),
          pid: 4321,
          status: null,
        };
      },
      kill: (pid, signal) => {
        signals.push([pid, signal]);
      },
      pause: (milliseconds) => pauses.push(milliseconds),
    },
  );

  assert.equal(result.error.code, 'ETIMEDOUT');
  assert.equal(spawnCalls.length, 1);
  assert.equal(spawnCalls[0].command, 'xcodebuild');
  assert.deepEqual(spawnCalls[0].args, ['archive']);
  assert.equal(spawnCalls[0].options.detached, true);
  assert.equal(spawnCalls[0].options.timeout, 1000);
  assert.deepEqual(signals, [
    [-4321, 'SIGTERM'],
    [-4321, 0],
    [-4321, 'SIGKILL'],
  ]);
  assert.deepEqual(pauses, [IOS_PROCESS_GROUP_TERM_GRACE_MS]);
});

test('successful xcodebuild does not signal the process group', () => {
  const signals = [];
  const result = spawnSyncInIosProcessGroup(
    'xcodebuild',
    ['build'],
    {},
    {
      spawn: () => ({ pid: 8765, status: 0 }),
      kill: (...args) => signals.push(args),
      pause: () => assert.fail('must not wait on a successful exit'),
    },
  );

  assert.equal(result.status, 0);
  assert.deepEqual(signals, []);
});

test('abnormal xcodebuild exit also cleans its own process group', () => {
  const signals = [];
  const result = spawnSyncInIosProcessGroup(
    'xcodebuild',
    ['-exportArchive'],
    {},
    {
      spawn: () => ({ pid: 1357, status: 65 }),
      kill: (pid, signal) => {
        signals.push([pid, signal]);
        if (signal === 0) {
          throw Object.assign(new Error('gone'), { code: 'ESRCH' });
        }
      },
      pause: () => {},
    },
  );

  assert.equal(result.status, 65);
  assert.deepEqual(signals, [
    [-1357, 'SIGTERM'],
    [-1357, 0],
  ]);
});

test('does not send KILL to a process group that already exited from TERM', () => {
  const signals = [];
  const pauses = [];
  const result = terminateIosProcessGroup(2468, {
    kill: (pid, signal) => {
      signals.push([pid, signal]);
      if (signal === 0) {
        throw Object.assign(new Error('gone'), { code: 'ESRCH' });
      }
    },
    pause: (milliseconds) => pauses.push(milliseconds),
  });

  assert.deepEqual(result, {
    processGroupId: -2468,
    termSent: true,
    killSent: false,
  });
  assert.deepEqual(signals, [
    [-2468, 'SIGTERM'],
    [-2468, 0],
  ]);
  assert.deepEqual(pauses, [IOS_PROCESS_GROUP_TERM_GRACE_MS]);
});

function installedBundleOutput(bundleId = BUNDLE) {
  return [
    '<key>CFBundleIdentifier</key>',
    `<string>${bundleId}</string>`,
  ].join('');
}

function buildArgs(useAssetFallback) {
  return iosDebugBuildArguments({
    project: '/tmp/MoonlitBeacon.xcodeproj',
    scheme: SCHEME,
    destination: 'generic/platform=iOS',
    derivedDataPath: '/tmp/ios-dd',
    team: 'TEAM123',
    useAssetFallback,
  });
}

function withFakeApp(run) {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-ios-build-'));
  const app = iosDebugAppPath(root, SCHEME);
  try {
    mkdirSync(app, { recursive: true });
    writeFileSync(join(app, SCHEME), 'arm64 executable');
    writeFileSync(join(app, 'Info.plist'), 'fake plist');
    writeFileSync(join(app, 'Assets.car'), 'fake asset catalog');
    for (const framework of IOS_IAP_FRAMEWORK_NAMES) {
      const frameworkDir = join(
        app,
        'Frameworks',
        `${framework}.framework`,
      );
      mkdirSync(frameworkDir, { recursive: true });
      writeFileSync(join(frameworkDir, framework), 'arm64 framework');
    }
    writeFileSync(
      join(app, `${SCHEME}.pck`),
      `[iapkit]\napi_key="${FAKE_PUBLISHABLE_KEY}"\n`,
    );
    run(app);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function withFakeAppIconSet(run) {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-ios-appicon-'));
  const iconSet = join(root, 'AppIcon.appiconset');
  try {
    mkdirSync(iconSet, { recursive: true });
    writeFileSync(join(iconSet, 'Icon-120.png'), '120px icon');
    writeFileSync(join(iconSet, 'Icon-152.png'), '152px icon');
    writeFileSync(join(iconSet, 'Icon-1024.png'), 'marketing icon');
    writeFileSync(
      join(iconSet, 'Contents.json'),
      JSON.stringify({
        images: [
          {
            idiom: 'universal',
            platform: 'ios',
            size: '60x60',
            scale: '2x',
            filename: 'Icon-120.png',
          },
          {
            idiom: 'universal',
            platform: 'ios',
            size: '76x76',
            scale: '2x',
            filename: 'Icon-152.png',
          },
          {
            idiom: 'universal',
            platform: 'ios',
            size: '1024x1024',
            filename: 'Icon-1024.png',
          },
        ],
      }),
    );
    run(iconSet);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function successfulTool(command, args = []) {
  if (command === 'lipo') return { status: 0, stdout: 'arm64\n', stderr: '' };
  if (command === 'xcrun' && args[0] === 'assetutil') {
    return {
      status: 0,
      stdout: JSON.stringify([
        { Name: 'AppIcon' },
        { Name: 'SplashImage' },
      ]),
      stderr: '',
    };
  }
  if (command === 'plutil') {
    const value = args.includes(
      'CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName',
    )
      ? 'AppIcon'
      : BUNDLE;
    return { status: 0, stdout: `${value}\n`, stderr: '' };
  }
  return { status: 0, stdout: '', stderr: '' };
}

function withFakeLocalizedInfoPlists(run) {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-ios-localized-info-'));
  const bundle = join(root, SCHEME);
  try {
    for (const localization of IOS_LOCALIZED_DISPLAY_NAMES) {
      const directory = join(bundle, `${localization.bundleLocale}.lproj`);
      mkdirSync(directory, { recursive: true });
      writeFileSync(
        join(directory, 'InfoPlist.strings'),
        '"CFBundleDisplayName" = "Moonlit Beacon";\n'
          + '"NSCameraUsageDescription" = "";\n',
      );
    }
    run({ root, bundle });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function localizedInfoPlistTool({ names = {}, privacyKey } = {}) {
  return (command, args) => {
    assert.equal(`${command} ${args.slice(0, 4).join(' ')}`, 'plutil -convert json -o -');
    const bundleLocale = basename(dirname(args.at(-1))).replace(/\.lproj$/, '');
    const localization = IOS_LOCALIZED_DISPLAY_NAMES.find(
      (entry) => entry.bundleLocale === bundleLocale,
    );
    const values = {
      CFBundleDisplayName: names[bundleLocale] ?? localization.displayName,
    };
    if (privacyKey && bundleLocale === 'en') values[privacyKey] = '';
    return { status: 0, stdout: JSON.stringify(values), stderr: '' };
  };
}

test('iOS home-screen name baseline matches the five App Store CSV languages exactly', () => {
  const [header, ...body] = parseCsv(
    readFileSync(STORE_LOCALIZATIONS_CSV, 'utf8'),
  );
  const rows = body.map((values) => Object.fromEntries(
    header.map((column, index) => [column, values[index]]),
  ));
  const metadataNames = rows
    .filter((row) => row.record_type === 'app' && row.platform === 'apple')
    .map((row) => ({
      storeLocale: row.locale,
      displayName: row.display_name,
    }));
  const canonicalNames = IOS_LOCALIZED_DISPLAY_NAMES.map(
    ({ storeLocale, displayName }) => ({ storeLocale, displayName }),
  );

  assert.deepEqual(metadataNames, canonicalNames);
  assert.deepEqual(
    IOS_LOCALIZED_DISPLAY_NAMES.map(({ bundleLocale }) => bundleLocale),
    ['en', 'ko', 'ja', 'zh_CN', 'zh_TW'],
  );
});

test('iOS export writes five display names deterministically and strips empty permission strings', () => {
  withFakeLocalizedInfoPlists(({ root, bundle }) => {
    assert.equal(configureGeneratedIosInfoPlistLocalizations(root, SCHEME), 5);
    for (const localization of IOS_LOCALIZED_DISPLAY_NAMES) {
      const contents = readFileSync(
        join(bundle, `${localization.bundleLocale}.lproj/InfoPlist.strings`),
        'utf8',
      );
      assert.equal(
        contents,
        `"CFBundleDisplayName" = "${localization.displayName}";\n`,
      );
      for (const key of IOS_UNUSED_PRIVACY_DESCRIPTION_KEYS) {
        assert.equal(contents.includes(key), false);
      }
    }
  });
  withFakeLocalizedInfoPlists(({ root, bundle }) => {
    const english = join(bundle, 'en.lproj/InfoPlist.strings');
    rmSync(join(bundle, 'zh_TW.lproj/InfoPlist.strings'));
    assert.throws(
      () => configureGeneratedIosInfoPlistLocalizations(root, SCHEME),
      /zh-Hant InfoPlist\.strings is missing/,
    );
    assert.match(readFileSync(english, 'utf8'), /NSCameraUsageDescription/);
  });
});

test('iOS app verification rejects missing and mismatched display names among the five', () => {
  withFakeLocalizedInfoPlists(({ bundle }) => {
    assert.equal(
      verifyIosLocalizedDisplayNames(bundle, {
        spawn: localizedInfoPlistTool(),
      }),
      true,
    );
    assert.throws(
      () => verifyIosLocalizedDisplayNames(bundle, {
        spawn: localizedInfoPlistTool({
          privacyKey: 'NSCameraUsageDescription',
        }),
      }),
      /still has unused NSCameraUsageDescription string/,
    );
    assert.throws(
      () => verifyIosLocalizedDisplayNames(bundle, {
        spawn: localizedInfoPlistTool({ names: { ko: 'Moonlit Beacon' } }),
      }),
      /ko home-screen name does not match store localization/,
    );

    rmSync(join(bundle, 'ja.lproj/InfoPlist.strings'));
    assert.throws(
      () => verifyIosLocalizedDisplayNames(bundle, {
        spawn: localizedInfoPlistTool(),
      }),
      /ja InfoPlist\.strings is missing/,
    );
  });
});

test('a new export discards the previous Xcode project', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-ios-export-'));
  const projectDir = join(root, 'ios');
  const staleProject = join(projectDir, `${SCHEME}.xcodeproj`);
  try {
    mkdirSync(staleProject, { recursive: true });
    writeFileSync(join(staleProject, 'sentinel'), 'stale');

    prepareIosExportDirectory(projectDir);

    assert.equal(existsSync(projectDir), true);
    assert.equal(existsSync(staleProject), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('discards only a partial Xcode project from a failed export', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-ios-partial-export-'));
  const projectDir = join(root, 'ios');
  const partialProject = join(projectDir, `${SCHEME}.xcodeproj`);
  try {
    mkdirSync(partialProject, { recursive: true });
    writeFileSync(join(partialProject, 'project.pbxproj'), 'partial');

    assert.equal(
      cleanupIncompleteIosExportDirectory(projectDir, false),
      true,
    );
    assert.equal(existsSync(projectDir), false);

    mkdirSync(partialProject, { recursive: true });
    writeFileSync(join(partialProject, 'project.pbxproj'), 'complete');
    assert.equal(
      cleanupIncompleteIosExportDirectory(projectDir, true),
      false,
    );
    assert.equal(existsSync(partialProject), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('discards the generated project only when recovering a stale iOS workflow lock', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-ios-stale-workflow-'));
  const projectDir = join(root, 'ios');
  const partialProject = join(projectDir, `${SCHEME}.xcodeproj`);
  try {
    mkdirSync(partialProject, { recursive: true });
    writeFileSync(join(partialProject, 'project.pbxproj'), 'partial');

    assert.equal(
      cleanupStaleIosWorkflowExportDirectory(projectDir, false),
      false,
    );
    assert.equal(existsSync(partialProject), true);

    assert.equal(
      cleanupStaleIosWorkflowExportDirectory(projectDir, true),
      true,
    );
    assert.equal(existsSync(projectDir), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a normal Debug build does not use AppIcon workaround settings', () => {
  const args = buildArgs(false);
  for (const setting of IOS_DEV_ASSET_FALLBACK_SETTINGS) {
    assert.equal(args.includes(setting), false);
  }
  assert.equal(args.at(-1), 'build');
  assert.equal(args.includes('-configuration'), true);
  assert.equal(args.includes('Debug'), true);
});

test('an isolated iOS screenshot build overrides only PRODUCT_BUNDLE_IDENTIFIER exactly', () => {
  const bundleIdentifier = `${BUNDLE}.storecapture`;
  const args = iosDebugBuildArguments({
    project: '/tmp/MoonlitBeacon.xcodeproj',
    scheme: SCHEME,
    destination: 'platform=iOS,id=DEVICE',
    derivedDataPath: '/tmp/ios-dd',
    team: 'TEAM123',
    bundleIdentifier,
  });
  assert.equal(
    args.filter((value) => value === `PRODUCT_BUNDLE_IDENTIFIER=${bundleIdentifier}`).length,
    1,
  );
  assert.throws(
    () => iosDebugBuildArguments({
      project: '/tmp/MoonlitBeacon.xcodeproj',
      scheme: SCHEME,
      destination: 'generic/platform=iOS',
      derivedDataPath: '/tmp/ios-dd',
      team: 'TEAM123',
      bundleIdentifier: 'invalid shell=value',
    }),
    /bundle ID/u,
  );
});

test('only the development fallback disables asset catalog compilation', () => {
  const args = buildArgs(true);
  for (const setting of IOS_DEV_ASSET_FALLBACK_SETTINGS) {
    assert.equal(args.includes(setting), true);
  }
  assert.equal(args.includes('archive'), false);
});

test('development legacy icons pick only runtime PNGs under a safe bundle name', () => {
  withFakeAppIconSet((iconSet) => {
    assert.deepEqual(
      iosDevelopmentLegacyIconFiles(iconSet),
      [
        {
          sourcePath: join(iconSet, 'Icon-120.png'),
          bundleFileName: `${IOS_DEV_LEGACY_ICON_PREFIX}Icon-120.png`,
        },
        {
          sourcePath: join(iconSet, 'Icon-152.png'),
          bundleFileName: `${IOS_DEV_LEGACY_ICON_PREFIX}Icon-152.png`,
        },
      ],
    );
  });
});

test('puts a legacy icon on the development fallback and re-signs with the existing development signature', () => {
  withFakeApp((app) => {
    withFakeAppIconSet((iconSet) => {
      const calls = [];
      const plistValues = new Map();
      const spawn = (command, args) => {
        calls.push([command, args]);
        if (
          command === 'codesign'
          && args.includes('--display')
        ) {
          return {
            status: 0,
            stdout: '',
            stderr: [
              `Executable=${join(app, SCHEME)}`,
              'Authority=Apple Development: Test Developer (TEAM123)',
              'Authority=Apple Worldwide Developer Relations Certification Authority',
            ].join('\n'),
          };
        }
        if (command === 'plutil') {
          const operation = args[0];
          const keyPath = args[1];
          if (operation === '-replace' && keyPath === 'CFBundleIconFiles') {
            return { status: 1, stdout: '', stderr: 'missing key' };
          }
          if (operation === '-replace' || operation === '-insert') {
            plistValues.set(keyPath, JSON.parse(args[3]));
          }
        }
        return { status: 0, stdout: '', stderr: '' };
      };

      const iconFiles = installIosDevelopmentFallbackIcon(
        app,
        iconSet,
        { spawn },
      );
      assert.deepEqual(iconFiles, [
        `${IOS_DEV_LEGACY_ICON_PREFIX}Icon-120.png`,
        `${IOS_DEV_LEGACY_ICON_PREFIX}Icon-152.png`,
      ]);
      for (const iconFile of iconFiles) {
        assert.equal(existsSync(join(app, iconFile)), true);
      }
      assert.deepEqual(
        plistValues.get('CFBundleIconFiles'),
        iconFiles,
      );
      for (const keyPath of ['CFBundleIcons', 'CFBundleIcons~ipad']) {
        assert.deepEqual(
          plistValues.get(keyPath),
          {
            CFBundlePrimaryIcon: {
              CFBundleIconFiles: iconFiles,
              UIPrerenderedIcon: true,
            },
          },
        );
      }

      const signingCall = calls.find(([command, args]) =>
        command === 'codesign' && args.includes('--force'));
      assert.deepEqual(
        signingCall?.[1],
        [
          '--force',
          '--sign',
          'Apple Development: Test Developer (TEAM123)',
          '--preserve-metadata=identifier,entitlements,requirements,flags,runtime',
          '--timestamp=none',
          app,
        ],
      );
      assert.equal(
        calls.some(([command, args]) =>
          command === 'codesign'
          && args.includes('--verify')
          && args.includes('--deep')
          && args.includes('--strict')),
        true,
      );
    });
  });
});

test('does not modify the development fallback without an Apple Development signature', () => {
  withFakeApp((app) => {
    withFakeAppIconSet((iconSet) => {
      assert.throws(
        () => installIosDevelopmentFallbackIcon(app, iconSet, {
          spawn: () => ({
            status: 0,
            stdout: '',
            stderr: 'Authority=Apple Distribution: Test Developer',
          }),
        }),
        /Apple Development signature/,
      );
      assert.equal(
        existsSync(
          join(app, `${IOS_DEV_LEGACY_ICON_PREFIX}Icon-120.png`),
        ),
        false,
      );
    });
  });
});

test('does not run fallback when the normal build succeeds', () => {
  const calls = [];
  const usedFallback = runIosDebugBuildWithFallback(
    () => calls.push('normal'),
    () => calls.push('fallback'),
    () => true,
  );
  assert.equal(usedFallback, false);
  assert.deepEqual(calls, ['normal']);
});

test('runs fallback once only after the normal build fails', () => {
  const calls = [];
  const usedFallback = runIosDebugBuildWithFallback(
    () => {
      calls.push('normal');
      throw Object.assign(new Error('normal failed'), {
        output: [
          'library load denied by system policy',
          'Failed to launch AssetCatalogSimulatorAgent via CoreSimulator spawn',
        ].join('\n'),
      });
    },
    () => calls.push('fallback'),
    (error) => isAssetCatalogSimulatorPolicyFailure(error.output),
  );
  assert.equal(usedFallback, true);
  assert.deepEqual(calls, ['normal', 'fallback']);
});

test('falls back only on an AssetCatalogSimulatorAgent system-policy error', () => {
  assert.equal(
    isAssetCatalogSimulatorPolicyFailure(
      'Failed to launch AssetCatalogSimulatorAgent via CoreSimulator spawn',
    ),
    true,
  );
  assert.equal(
    isAssetCatalogSimulatorPolicyFailure(
      'AssetCatalogSimulatorAgent: library load denied by system policy',
    ),
    true,
  );
  assert.equal(
    isAssetCatalogSimulatorPolicyFailure(
      'library load denied by system policy',
    ),
    false,
  );
  assert.equal(
    isAssetCatalogSimulatorPolicyFailure(
      'AssetCatalogSimulatorAgent: malformed app icon source',
    ),
    false,
  );
  assert.equal(
    isAssetCatalogSimulatorPolicyFailure(
      'CodeSign error: provisioning profile is missing',
    ),
    false,
  );

  const calls = [];
  assert.throws(
    () => runIosDebugBuildWithFallback(
      () => {
        calls.push('normal');
        throw Object.assign(new Error('signing failed'), {
          output: 'CodeSign error: provisioning profile is missing',
        });
      },
      () => calls.push('fallback'),
      (error) => isAssetCatalogSimulatorPolicyFailure(error.output),
    ),
    /signing failed/,
  );
  assert.deepEqual(calls, ['normal']);
});

test('falls back only on a timeout stalled in asset catalog', () => {
  assert.equal(
    shouldUseIosAssetFallback({
      code: 'ETIMEDOUT',
      output: [
        'CompileAssetCatalogVariant thinned /tmp/MoonlitBeacon.app',
        '/Applications/Xcode.app/usr/bin/actool /tmp/Images.xcassets',
      ].join('\n'),
    }),
    true,
  );
  assert.equal(
    shouldUseIosAssetFallback({
      code: 'ETIMEDOUT',
      output: [
        'CompileAssetCatalogVariant thinned /tmp/MoonlitBeacon.app',
        '/Applications/Xcode.app/usr/bin/actool /tmp/Images.xcassets',
        'Ld /tmp/MoonlitBeacon normal',
        'linker waiting on unrelated input',
      ].join('\n') + 'x'.repeat(13 * 1024),
    }),
    false,
  );
  assert.equal(
    shouldUseIosAssetFallback({
      code: 'ETIMEDOUT',
      output: 'CodeSign /tmp/MoonlitBeacon.app',
    }),
    false,
  );
  assert.equal(
    shouldUseIosAssetFallback({
      output: [
        'AssetCatalogSimulatorAgent',
        'library load denied by system policy',
      ].join(': '),
    }),
    true,
  );
});

test('verifies signature, arm64, bundle ID, and publishable PCK together', () => {
  withFakeApp((app) => {
    assert.equal(
      verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        expectedAppIconName: 'AppIcon',
        expectedAssetNames: ['SplashImage'],
        scheme: SCHEME,
        spawn: successfulTool,
      }),
      true,
    );
  });
});

test('rejects a missing iOS IAP framework or an arm64 mismatch', () => {
  withFakeApp((app) => {
    const missingFramework = IOS_IAP_FRAMEWORK_NAMES[0];
    rmSync(
      join(
        app,
        'Frameworks',
        `${missingFramework}.framework`,
        missingFramework,
      ),
      { force: true },
    );
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        scheme: SCHEME,
        spawn: successfulTool,
      }),
      /Output required/,
    );
  });

  withFakeApp((app) => {
    const wrongArchitecture = IOS_IAP_FRAMEWORK_NAMES[1];
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        scheme: SCHEME,
        spawn: (command, args) => (
          command === 'lipo'
          && args[1].endsWith(`/${wrongArchitecture}`)
        )
          ? { status: 0, stdout: 'x86_64\n', stderr: '' }
          : successfulTool(command, args),
      }),
      new RegExp(`arm64.*${wrongArchitecture}`),
    );
  });
});

test(
  'iOS embed fixer fails when a required framework reference is missing',
  { skip: process.platform === 'win32' },
  () => {
    const root = mkdtempSync(join(tmpdir(), 'moonlit-ios-fixer-'));
    const project = join(root, `${SCHEME}.xcodeproj`);
    try {
      mkdirSync(project, { recursive: true });
      writeFileSync(join(project, 'project.pbxproj'), '// missing frameworks\n');
      const result = spawnSync('bash', [IAP_EMBED_FIXER], {
        cwd: REPO_ROOT,
        encoding: 'utf8',
        env: {
          ...process.env,
          IOS_EXPORT_DIR: root,
          XCODEPROJ: project,
          GODOT_IAP_ADDON_DIR: join(
            REPO_ROOT,
            'apps/game/addons/godot-iap',
          ),
        },
      });

      assert.notEqual(result.status, 0);
      assert.match(
        result.stderr,
        /framework references not found in Xcode project/,
      );
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  },
);

test('rejects a PCK with a secret key or without a publishable key', () => {
  const secret = `openiap-kit_sk_${'S'.repeat(64)}`;
  assert.equal(
    pckHasSafeIapKitConfig(
      `[iapkit]\napi_key="${FAKE_PUBLISHABLE_KEY}"\n`,
    ),
    true,
  );
  assert.equal(
    pckHasSafeIapKitConfig(`[iapkit]\napi_key="${secret}"\n`),
    false,
  );
  assert.equal(pckHasSafeIapKitConfig('[iapkit]\napi_key=""\n'), false);
  assert.equal(
    pckHasSafeIapKitConfig(
      `[iapkit]\nother=true\napi_key="${FAKE_PUBLISHABLE_KEY}"\n`,
    ),
    false,
  );
  assert.equal(
    pckHasSafeIapKitConfig(
      `[other]\napi_key="${FAKE_PUBLISHABLE_KEY}"\n[iapkit]\nother=true\n`,
    ),
    false,
  );
  assert.equal(
    pckHasSafeIapKitConfig(
      `[iapkit]\napi_key=${FAKE_PUBLISHABLE_KEY}\n`,
    ),
    false,
  );
});

test('verifies the test and production-tool boundary in the iOS PCK', () => {
  assert.equal(
    pckExcludesDevelopmentResources(
      Buffer.from('res://scripts/dev/test_launcher.gdc'),
    ),
    true,
  );
  assert.equal(
    pckExcludesDevelopmentResources(
      Buffer.from('res://tests/test_vault.gdc'),
    ),
    false,
  );
  assert.equal(
    pckExcludesDevelopmentResources(
      Buffer.from('res://tools/check_scripts.gdc'),
    ),
    false,
  );

  withFakeApp((app) => {
    writeFileSync(
      join(app, `${SCHEME}.pck`),
      `[iapkit]\napi_key="${FAKE_PUBLISHABLE_KEY}"\n`
        + '\0res://tests/test_vault.gdc\0',
    );
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        scheme: SCHEME,
        spawn: successfulTool,
      }),
      /test or production-tool/,
    );
  });
});

test('rejects signature, architecture, and bundle ID mismatches separately', () => {
  withFakeApp((app) => {
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        scheme: SCHEME,
        spawn: (command) => command === 'codesign'
          ? { status: 1, stdout: '', stderr: '' }
          : successfulTool(command),
      }),
      /code signature/,
    );
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        scheme: SCHEME,
        spawn: (command) => command === 'lipo'
          ? { status: 0, stdout: 'x86_64\n', stderr: '' }
          : successfulTool(command),
      }),
      /arm64/,
    );
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        scheme: SCHEME,
        spawn: (command) => command === 'plutil'
          ? { status: 0, stdout: 'wrong.bundle\n', stderr: '' }
          : successfulTool(command),
      }),
      /bundle ID/,
    );
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        expectedAppIconName: 'AppIcon',
        scheme: SCHEME,
        spawn: (command, args) => (
          command === 'plutil'
          && args.includes(
            'CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName',
          )
        )
          ? { status: 1, stdout: '', stderr: '' }
          : successfulTool(command, args),
      }),
      /app icon/,
    );
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        expectedAppIconName: 'AppIcon',
        expectedAssetNames: ['SplashImage'],
        scheme: SCHEME,
        spawn: (command, args) => (
          command === 'xcrun' && args[0] === 'assetutil'
        )
          ? {
            status: 0,
            stdout: JSON.stringify([{ Name: 'SplashImage' }]),
            stderr: '',
          }
          : successfulTool(command, args),
      }),
      /asset catalog/,
    );
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        expectedAssetNames: ['SplashImage'],
        scheme: SCHEME,
        exists: (path) => !path.endsWith('Assets.car'),
        spawn: successfulTool,
      }),
      /Assets\.car/,
    );
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        expectedAssetNames: ['SplashImage'],
        scheme: SCHEME,
        spawn: (command, args) => (
          command === 'xcrun' && args[0] === 'assetutil'
        )
          ? { status: 0, stdout: '[]', stderr: '' }
          : successfulTool(command, args),
      }),
      /asset catalog/,
    );
  });
});

test('fallback can skip a stalled asset catalog entirely', () => {
  withFakeApp((app) => {
    let appIconRead = false;
    let assetCatalogRead = false;
    rmSync(join(app, 'Assets.car'), { force: true });
    assert.equal(
      verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        scheme: SCHEME,
        spawn: (command, args) => {
          if (
            command === 'plutil'
            && args.includes(
              'CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName',
            )
          ) {
            appIconRead = true;
          }
          if (command === 'xcrun' && args[0] === 'assetutil') {
            assetCatalogRead = true;
          }
          return successfulTool(command, args);
        },
      }),
      true,
    );
    assert.equal(appIconRead, false);
    assert.equal(assetCatalogRead, false);
  });
});

test('fallback verifies legacy PNG and both device metadata without Assets.car', () => {
  withFakeApp((app) => {
    const iconFiles = [
      `${IOS_DEV_LEGACY_ICON_PREFIX}Icon-120.png`,
      `${IOS_DEV_LEGACY_ICON_PREFIX}Icon-152.png`,
    ];
    for (const iconFile of iconFiles) {
      writeFileSync(join(app, iconFile), 'legacy icon');
    }
    rmSync(join(app, 'Assets.car'), { force: true });
    let assetCatalogRead = false;
    assert.equal(
      verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        expectedLegacyAppIconFiles: iconFiles,
        scheme: SCHEME,
        spawn: (command, args) => {
          if (command === 'xcrun' && args[0] === 'assetutil') {
            assetCatalogRead = true;
          }
          if (
            command === 'plutil'
            && args[0] === '-extract'
            && args[2] === 'json'
          ) {
            return {
              status: 0,
              stdout: JSON.stringify(iconFiles),
              stderr: '',
            };
          }
          return successfulTool(command, args);
        },
      }),
      true,
    );
    assert.equal(assetCatalogRead, false);
  });
});

test('fallback rejects missing legacy icon files or metadata', () => {
  withFakeApp((app) => {
    const iconFiles = [
      `${IOS_DEV_LEGACY_ICON_PREFIX}Icon-120.png`,
      `${IOS_DEV_LEGACY_ICON_PREFIX}Icon-152.png`,
    ];
    writeFileSync(join(app, iconFiles[0]), 'legacy icon');
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        expectedLegacyAppIconFiles: iconFiles,
        scheme: SCHEME,
        spawn: successfulTool,
      }),
      /legacy app icon PNG/,
    );

    writeFileSync(join(app, iconFiles[1]), 'legacy icon');
    assert.throws(
      () => verifyInstallableIosApp(app, {
        expectedBundleId: BUNDLE,
        expectedLegacyAppIconFiles: iconFiles,
        scheme: SCHEME,
        spawn: (command, args) => {
          if (
            command === 'plutil'
            && args[0] === '-extract'
            && args[2] === 'json'
          ) {
            return {
              status: 0,
              stdout: JSON.stringify([iconFiles[0], iconFiles[0]]),
              stderr: '',
            };
          }
          return successfulTool(command, args);
        },
      }),
      /legacy app icon metadata/,
    );
  });
});

test('finds only the exact installed bundle ID in devicectl output', () => {
  const payload = {
    info: {
      arguments: ['--bundle-id', `${BUNDLE}.lookalike`],
    },
    result: {
      apps: [
        { bundleIdentifier: BUNDLE },
      ],
    },
  };
  assert.equal(devicectlResultContainsBundle(payload, BUNDLE), true);
  assert.equal(
    devicectlResultContainsBundle(payload, `${BUNDLE}.lookalike`),
    false,
  );
  assert.equal(
    devicectlResultContainsBundle({
      info: { arguments: ['--bundle-id', BUNDLE] },
    }, BUNDLE),
    false,
  );
  assert.equal(jsonContainsExactString(payload.result, BUNDLE), true);
});

test('picks USBMux device IDs without duplicates', () => {
  assert.deepEqual(
    parseUsbMuxDeviceIds([
      FAKE_USBMUX_UDID,
      FAKE_USBMUX_UDID,
      '0123456789abcdef0123456789abcdef01234567',
      '11111111-2222-4333-8444-555555555555',
      'available iPad 11111111-2222-4333-8444-555555555555',
      '',
    ].join('\n')),
    [
      FAKE_USBMUX_UDID,
      '0123456789abcdef0123456789abcdef01234567',
    ],
  );
});

test('finds only the exact bundle ID in an ideviceinstaller plist', () => {
  const output = `<?xml version="1.0"?>
<plist version="1.0"><array><dict>
<key>CFBundleIdentifier</key>
<string>${BUNDLE}</string>
</dict></array></plist>`;
  assert.equal(ideviceInstallerResultContainsBundle(output, BUNDLE), true);
  assert.equal(
    ideviceInstallerResultContainsBundle(output, `${BUNDLE}.lookalike`),
    false,
  );
  assert.equal(
    ideviceInstallerResultContainsBundle(
      `<key>note</key><string>${BUNDLE}</string>`,
      BUNDLE,
    ),
    false,
  );
});

test('USBMux install does not create an uninstall path that would wipe saves', () => {
  const udid = FAKE_USBMUX_UDID;
  const app = '/tmp/MoonlitBeacon.app';
  assert.deepEqual(
    usbMuxInstallArguments(udid, app, false),
    ['-u', udid, '-w', 'install', app],
  );
  assert.deepEqual(
    usbMuxInstallArguments(udid, app, true),
    ['-u', udid, '-w', 'upgrade', app],
  );
  assert.equal(usbMuxInstallArguments(udid, app, true).includes('uninstall'), false);
  assert.deepEqual(
    usbMuxListArguments(udid, BUNDLE),
    [
      '-u', udid,
      'list', '--user', '--xml',
      '-b', BUNDLE,
      '-a', 'CFBundleIdentifier',
    ],
  );
  assert.deepEqual(
    usbMuxLaunchArguments(udid, BUNDLE),
    ['-u', udid, '--detach', 'run', BUNDLE],
  );
});

test('does not touch USB fallback when CoreDevice succeeds', () => {
  const calls = [];
  const result = runIosInstallWithFallback({
    coreDeviceId: 'CORE-DEVICE',
    usbDeviceId: null,
    discoverUsbDevice: () => calls.push('discover-usb'),
    installCoreDevice: (deviceId) => calls.push(`core:${deviceId}`),
    installUsbDevice: (deviceId) => calls.push(`usb:${deviceId}`),
  });
  assert.deepEqual(calls, ['core:CORE-DEVICE']);
  assert.equal(result.transport, 'coredevice');
  assert.equal(result.coreError, null);
});

test('preserves the original CoreDevice error when no USB device is present', () => {
  const coreError = new Error('core install failed');
  assert.throws(
    () => runIosInstallWithFallback({
      coreDeviceId: 'CORE-DEVICE',
      usbDeviceId: null,
      discoverUsbDevice: () => null,
      installCoreDevice: () => {
        throw coreError;
      },
      installUsbDevice: () => assert.fail('USB install must not run.'),
    }),
    (error) => error === coreError,
  );
});

test('preserves causes for USB success and double failure after CoreDevice failure', () => {
  const coreError = new Error('core install failed');
  const calls = [];
  const result = runIosInstallWithFallback({
    coreDeviceId: 'CORE-DEVICE',
    usbDeviceId: null,
    discoverUsbDevice: () => {
      calls.push('discover-usb');
      return FAKE_USBMUX_UDID;
    },
    installCoreDevice: () => {
      calls.push('core');
      throw coreError;
    },
    installUsbDevice: (deviceId) => {
      calls.push(`usb:${deviceId}`);
      return 'installed';
    },
    onFallback: () => calls.push('fallback'),
  });
  assert.deepEqual(calls, [
    'core',
    'discover-usb',
    'fallback',
    `usb:${FAKE_USBMUX_UDID}`,
  ]);
  assert.equal(result.transport, 'usbmux');
  assert.equal(result.result, 'installed');
  assert.equal(result.coreError, coreError);

  const usbError = new Error('usb install failed');
  assert.throws(
    () => runIosInstallWithFallback({
      coreDeviceId: 'CORE-DEVICE',
      usbDeviceId: FAKE_USBMUX_UDID,
      discoverUsbDevice: () => assert.fail('USB device is already found.'),
      installCoreDevice: () => {
        throw coreError;
      },
      installUsbDevice: () => {
        throw usbError;
      },
    }),
    (error) => error instanceof AggregateError
      && error.cause === coreError
      && error.errors[0] === coreError
      && error.errors[1] === usbError,
  );
});

test('iOS CLI errors show nested causes and action text together', () => {
  const coreError = new Error('CoreDevice install timed out');
  const usbError = new Error(
    'ideviceinstaller is required: brew install ideviceinstaller',
  );
  const error = new AggregateError(
    [coreError, usbError],
    'Both CoreDevice and USB install failed.',
    { cause: coreError },
  );
  assert.equal(
    formatIosWorkflowError(error),
    [
      'Both CoreDevice and USB install failed.',
      '  - CoreDevice install timed out',
      '  - ideviceinstaller is required: brew install ideviceinstaller',
    ].join('\n'),
  );
});

test('USB upgrade re-queries and treats only launch failure as non-fatal', () => {
  const launchError = new Error('developer disk image missing');
  const calls = [];
  const outputs = [
    installedBundleOutput(),
    installedBundleOutput(),
  ];
  const result = runUsbMuxInstallFlow({
    bundleId: BUNDLE,
    listInstalled: () => {
      calls.push('list');
      return outputs.shift();
    },
    install: (mode) => calls.push(mode),
    verifyApp: () => calls.push('verify'),
    launch: () => {
      calls.push('launch');
      throw launchError;
    },
  });
  assert.deepEqual(calls, [
    'list',
    'upgrade',
    'verify',
    'list',
    'launch',
  ]);
  assert.equal(calls.includes('uninstall'), false);
  assert.equal(result.mode, 'upgrade');
  assert.equal(result.launched, false);
  assert.equal(result.launchError, launchError);
});

test('CoreDevice also treats only launch failure after install verification as non-fatal', () => {
  const launchError = new Error('The device was locked');
  const calls = [];
  const result = runCoreDeviceInstallFlow({
    install: () => calls.push('install'),
    verifyApp: () => calls.push('verify-app'),
    verifyInstalled: () => calls.push('verify-installed'),
    launch: () => {
      calls.push('launch');
      throw launchError;
    },
  });
  assert.deepEqual(calls, [
    'install',
    'verify-app',
    'verify-installed',
    'launch',
  ]);
  assert.equal(result.launched, false);
  assert.equal(result.launchError, launchError);
});

test('CoreDevice install or install-verification failure stays a fallback candidate', () => {
  const installError = new Error('install failed');
  const installCalls = [];
  assert.throws(
    () => runCoreDeviceInstallFlow({
      install: () => {
        installCalls.push('install');
        throw installError;
      },
      verifyApp: () => installCalls.push('verify-app'),
      verifyInstalled: () => installCalls.push('verify-installed'),
      launch: () => installCalls.push('launch'),
    }),
    (error) => error === installError,
  );
  assert.deepEqual(installCalls, ['install']);

  const verifyError = new Error('installed bundle missing');
  const verifyCalls = [];
  assert.throws(
    () => runCoreDeviceInstallFlow({
      install: () => verifyCalls.push('install'),
      verifyApp: () => verifyCalls.push('verify-app'),
      verifyInstalled: () => {
        verifyCalls.push('verify-installed');
        throw verifyError;
      },
      launch: () => verifyCalls.push('launch'),
    }),
    (error) => error === verifyError,
  );
  assert.deepEqual(verifyCalls, [
    'install',
    'verify-app',
    'verify-installed',
  ]);
});

test('fails before launch if the exact bundle is missing after USB install', () => {
  const calls = [];
  const outputs = [
    installedBundleOutput(`${BUNDLE}.lookalike`),
    installedBundleOutput(`${BUNDLE}.lookalike`),
  ];
  assert.throws(
    () => runUsbMuxInstallFlow({
      bundleId: BUNDLE,
      listInstalled: () => {
        calls.push('list');
        return outputs.shift();
      },
      install: (mode) => calls.push(mode),
      verifyApp: () => calls.push('verify'),
      launch: () => calls.push('launch'),
    }),
    /target bundle ID/
  );
  assert.deepEqual(calls, ['list', 'install', 'verify', 'list']);
});
