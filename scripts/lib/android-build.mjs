import { spawnSync } from 'node:child_process';
import {
  createHash,
  X509Certificate,
} from 'node:crypto';
import {
  copyFileSync,
  existsSync,
  renameSync,
  readdirSync,
  rmSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

export const ANDROID_ARCHIVE_TOOL_TIMEOUT_MS = 5 * 60 * 1000;
export const ANDROID_PLAY_SIGNING_MINIMUM_VALID_TO_MS = Date.parse(
  '2033-10-22T00:00:00Z',
);
export const ANDROID_APP_PACKAGE = 'com.crossplatformkorea.moonlitbeacon';
export const ANDROID_LOCALIZED_APP_NAMES = Object.freeze([
  ['en-US', 'en', 'Moonlit Beacon'],
  ['ko-KR', 'ko', '달빛 봉화'],
  ['ja-JP', 'ja', '月明かりの烽火'],
  ['zh-CN', 'zh', '月光烽火'],
  ['zh-TW', 'zh_TW', '月光烽火'],
].map(([storeLocale, projectLocale, displayName]) => Object.freeze({
  storeLocale,
  projectLocale,
  resourceLocale: projectLocale.replaceAll('_', '-'),
  displayName,
})));

export function resolveAndroidJavaToolInvocation(
  tool,
  {
    env = process.env,
    platform = process.platform,
  } = {},
) {
  if (!['jarsigner', 'keytool'].includes(tool)) {
    throw new Error(`Unsupported Android Java tool: ${tool}`);
  }
  const javaHome = env.JAVA_HOME?.trim();
  if (platform !== 'darwin' || !javaHome) {
    return { command: tool, prefixArgs: [] };
  }
  return {
    // Even if an old Homebrew JDK launcher on PATH stalls under dyld system policy,
    // use the exact JDK 17 tools that android-build detected.
    command: join(javaHome, 'bin', tool),
    prefixArgs: [],
  };
}

export function parseAndroidBuildFlags(args) {
  if (!Array.isArray(args) || args.some((arg) => typeof arg !== 'string')) {
    throw new Error('Failed to read Android build options.');
  }
  const allowed = new Set(['--bundle', '--debug', '--release']);
  const invalid = args.filter((arg) => !allowed.has(arg));
  if (invalid.length > 0) {
    throw new Error(`Unsupported Android build option: ${invalid.join(', ')}`);
  }
  const flags = {
    bundle: args.includes('--bundle'),
    debug: args.includes('--debug'),
    release: args.includes('--release'),
  };
  if (flags.debug && flags.release) {
    throw new Error('--debug and --release cannot be used together');
  }
  return flags;
}

function readQuotedSetting(source, key) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(
    new RegExp(`^${escaped}=(\"(?:[^\"\\\\]|\\\\.)*\")\\s*$`, 'm'),
  );
  if (!match) throw new Error(`Android release setting ${key} was not found.`);
  try {
    return JSON.parse(match[1]);
  } catch {
    throw new Error(`Android release setting ${key} string format is invalid.`);
  }
}

function readDictionarySetting(source, key) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const matches = [...source.matchAll(
    new RegExp(`^${escaped}=(\\{[\\s\\S]*?^\\})\\s*$`, 'gm'),
  )];
  if (matches.length !== 1) {
    throw new Error(`Android release setting ${key} must appear exactly once.`);
  }
  let value;
  try {
    value = JSON.parse(matches[0][1]);
  } catch {
    throw new Error(`Android release setting ${key} dictionary format is invalid.`);
  }
  if (
    !value
    || Array.isArray(value)
    || typeof value !== 'object'
    || Object.values(value).some((entry) => typeof entry !== 'string')
  ) {
    throw new Error(`Android release setting ${key} must be a string dictionary.`);
  }
  return value;
}

function androidPresetSection(exportPresets, name) {
  const section = exportPresets
    .split(/\n(?=\[preset\.\d+\]\n)/)
    .find((value) => value.includes(`name="${name}"\n`));
  if (!section) throw new Error(`Android release preset ${name} was not found.`);
  return section;
}

function readAndroidPresetMetadata(exportPresets, name) {
  const section = androidPresetSection(exportPresets, name);
  const code = section.match(/^version\/code=([0-9]+)\s*$/m)?.[1];
  if (!code) {
    throw new Error(`Android release setting ${name} version/code was not found.`);
  }
  return {
    packageName: readQuotedSetting(section, 'package/unique_name'),
    versionCode: Number.parseInt(code, 10),
    versionName: readQuotedSetting(section, 'version/name'),
  };
}

export function readAndroidReleaseMetadata(projectGodot, exportPresets) {
  return {
    projectVersion: readQuotedSetting(projectGodot, 'config/version'),
    localizedAppNames: readDictionarySetting(
      projectGodot,
      'config/name_localized',
    ),
    direct: readAndroidPresetMetadata(exportPresets, 'Android'),
    play: readAndroidPresetMetadata(exportPresets, 'Android Play'),
  };
}

export function assertAndroidDistributionFeatureContract(exportPresets) {
  const expected = [
    ['Android', ['direct_distribution'], false],
    ['Android Play', ['iap_store'], true],
  ];
  for (const [name, expectedFeatures, expectedPlugin] of expected) {
    const section = androidPresetSection(exportPresets, name);
    const features = readQuotedSetting(section, 'custom_features')
      .split(',')
      .map((feature) => feature.trim())
      .filter(Boolean);
    const plugin = section.match(/^plugins\/GodotIap=(true|false)\s*$/m)?.[1];
    if (JSON.stringify(features) !== JSON.stringify(expectedFeatures)) {
      throw new Error(
        `${name} custom_features must be exactly ${expectedFeatures.join(',')}.`,
      );
    }
    if (plugin !== String(expectedPlugin)) {
      throw new Error(`${name} plugins/GodotIap must be ${expectedPlugin}.`);
    }
  }
  return true;
}

export function assertAndroidReleaseMetadata(
  metadata,
  { expectedPackageName },
) {
  if (!/^[0-9]+(?:\.[0-9]+){1,2}$/.test(metadata?.projectVersion ?? '')) {
    throw new Error('Android project version format is invalid.');
  }
  for (const { projectLocale, displayName } of ANDROID_LOCALIZED_APP_NAMES) {
    if (metadata?.localizedAppNames?.[projectLocale] !== displayName) {
      throw new Error(
        `Android ${projectLocale} home-screen name does not match store localization.`,
      );
    }
  }
  for (const [label, preset] of [
    ['Android', metadata?.direct],
    ['Android Play', metadata?.play],
  ]) {
    if (preset?.packageName !== expectedPackageName) {
      throw new Error(`${label} package name does not match the release setting.`);
    }
    if (preset.versionName !== metadata.projectVersion) {
      throw new Error(
        `${label} version name ${preset.versionName || 'missing'} and project version `
        + `${metadata.projectVersion || 'missing'} differ.`,
      );
    }
    if (
      !Number.isSafeInteger(preset.versionCode)
      || preset.versionCode < 1
      || preset.versionCode > 2_100_000_000
    ) {
      throw new Error(
        `${label} version/code is outside the Google Play allowed range.`,
      );
    }
  }
  if (metadata.direct.versionCode !== metadata.play.versionCode) {
    throw new Error('Android and Android Play version/code differ.');
  }
  return true;
}

export function assertAndroidDirectDistributionRuntimeState(
  state,
  {
    expectedProductId = `${ANDROID_APP_PACKAGE}.hero_dancer`,
    expectedHeroPath = 'res://resources/heroes/dancer.tres',
  } = {},
) {
  if (state === null || typeof state !== 'object' || Array.isArray(state)) {
    throw new Error('Direct-distribution Android runtime proof is missing.');
  }
  const requiredTrue = [
    ['ready', 'direct-distribution runtime ready'],
    ['direct_distribution_feature', 'direct_distribution feature'],
    ['store_state_unavailable', 'direct-distribution store unavailable state'],
    ['cached_paid_entitlement_fixture_present', 'cached paid-entitlement fixture'],
    ['cached_paid_entitlement_ignored', 'cached paid entitlement blocked'],
    ['cached_paid_entitlements_restored', 'runtime probe restored'],
    ['title_screen_visible', 'normal title screen'],
    ['title_store_button_present', 'title store button node'],
    ['title_store_button_hidden', 'direct-distribution title store button hidden'],
  ];
  if (state.kind !== 'direct_distribution') {
    throw new Error('Direct-distribution Android runtime proof kinds differ.');
  }
  for (const [key, label] of requiredTrue) {
    if (state[key] !== true) {
      throw new Error(`${label} was not proven on the actually installed APK.`);
    }
  }
  if (state.storefront_enabled !== false) {
    throw new Error('storefront_enabled is not false on the direct-distribution APK.');
  }
  if (state.cached_paid_entitlement_owned !== false) {
    throw new Error('Direct-distribution APK treated a cached paid entitlement as owns.');
  }
  if (
    state.title_store_button_self_visible !== false
    || state.title_store_button_visible_in_tree !== false
    || state.title_store_button_enabled !== false
  ) {
    throw new Error('Normal title store button on the direct-distribution APK is not hidden and disabled.');
  }
  if (state.cached_paid_entitlement_product_id !== expectedProductId) {
    throw new Error('Direct-distribution paid-entitlement probe product IDs differ.');
  }
  if (state.cached_paid_entitlement_hero_path !== expectedHeroPath) {
    throw new Error('Direct-distribution paid-entitlement probe hero paths differ.');
  }
  return Object.freeze({
    productId: expectedProductId,
    heroPath: expectedHeroPath,
    storefrontEnabled: false,
    cachedEntitlementOwned: false,
    titleStoreButtonVisible: false,
  });
}

function certificateDerFromPem(output) {
  const certificates = [...String(output).matchAll(
    /-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----/g,
  )];
  if (certificates.length !== 1) return null;
  const base64 = certificates[0][1].replace(/\s/g, '');
  const decoded = Buffer.from(base64, 'base64');
  return decoded.length > 0 && decoded.toString('base64') === base64
    ? decoded
    : null;
}

function certificateSha256FromPem(output) {
  const certificate = certificateDerFromPem(output);
  return certificate
    ? createHash('sha256').update(certificate).digest('hex')
    : '';
}

export function assertAndroidSigningCertificateValid(
  signingCertificate,
  {
    now = new Date(),
    parse = (value) => new X509Certificate(value),
  } = {},
) {
  if (!Buffer.isBuffer(signingCertificate) || signingCertificate.length === 0) {
    throw new Error('Failed to read the Android release signer certificate.');
  }
  let certificate;
  try {
    certificate = parse(signingCertificate);
  } catch {
    throw new Error('Android release signer certificate format is invalid.');
  }
  const validFrom = new Date(certificate.validFrom);
  const validTo = new Date(certificate.validTo);
  if (
    !Number.isFinite(validFrom.getTime())
    || !Number.isFinite(validTo.getTime())
    || validFrom > now
    || validTo <= now
  ) {
    throw new Error('Android release signer certificate is not yet valid or has expired.');
  }
  if (validTo.getTime() <= ANDROID_PLAY_SIGNING_MINIMUM_VALID_TO_MS) {
    throw new Error(
      'Android release signer certificate must remain valid through Google Play\'s required date '
      + '2033-10-22 and beyond.',
    );
  }
  return true;
}

function apkSignerCertificateSha256(output) {
  const matches = [...String(output).matchAll(
    /^Signer #\d+ certificate SHA-256 digest: ([0-9a-f]{64})$/gim,
  )];
  return matches.length === 1 ? matches[0][1].toLowerCase() : '';
}

export function resolveAndroidApkSignerPath({
  env = process.env,
  exists = existsSync,
  home = homedir(),
  readDir = readdirSync,
} = {}) {
  const explicit = env.MOONLIT_APKSIGNER_BIN?.trim();
  if (explicit) {
    if (!exists(explicit)) {
      throw new Error('apksigner from MOONLIT_APKSIGNER_BIN was not found.');
    }
    return explicit;
  }
  const sdkRoot = env.ANDROID_HOME?.trim()
    || env.ANDROID_SDK_ROOT?.trim()
    || join(home, 'Library', 'Android', 'sdk');
  const buildTools = join(sdkRoot, 'build-tools');
  let versions;
  try {
    versions = readDir(buildTools)
      .sort((left, right) => right.localeCompare(left, undefined, {
        numeric: true,
      }));
  } catch {
    versions = [];
  }
  const candidate = versions
    .map((version) => join(buildTools, version, 'apksigner'))
    .find((path) => exists(path));
  if (!candidate) {
    throw new Error('apksigner from Android SDK build-tools was not found.');
  }
  return candidate;
}

export function resolveAndroidAapt2Path({
  env = process.env,
  exists = existsSync,
  home = homedir(),
  platform = process.platform,
  readDir = readdirSync,
} = {}) {
  const explicit = env.MOONLIT_AAPT2_BIN?.trim();
  if (explicit) {
    if (!exists(explicit)) {
      throw new Error('aapt2 from MOONLIT_AAPT2_BIN was not found.');
    }
    return explicit;
  }
  const sdkRoot = env.ANDROID_HOME?.trim()
    || env.ANDROID_SDK_ROOT?.trim()
    || join(home, 'Library', 'Android', 'sdk');
  const buildTools = join(sdkRoot, 'build-tools');
  let versions;
  try {
    versions = readDir(buildTools)
      .sort((left, right) => right.localeCompare(left, undefined, {
        numeric: true,
      }));
  } catch {
    versions = [];
  }
  const executable = platform === 'win32' ? 'aapt2.exe' : 'aapt2';
  const candidate = versions
    .map((version) => join(buildTools, version, executable))
    .find((path) => exists(path));
  if (!candidate) {
    throw new Error('aapt2 from Android SDK build-tools was not found.');
  }
  return candidate;
}

function readProtobufVarint(buffer, start) {
  let value = 0n;
  let shift = 0n;
  let offset = start;
  while (offset < buffer.length && shift <= 63n) {
    const byte = buffer[offset];
    offset += 1;
    value |= BigInt(byte & 0x7f) << shift;
    if ((byte & 0x80) === 0) return { offset, value };
    shift += 7n;
  }
  throw new Error('Android resources protobuf varint is invalid.');
}

function protobufFields(buffer) {
  if (!Buffer.isBuffer(buffer)) {
    throw new Error('Android resources protobuf message is not a byte buffer.');
  }
  const fields = [];
  let offset = 0;
  while (offset < buffer.length) {
    const tag = readProtobufVarint(buffer, offset);
    offset = tag.offset;
    const field = Number(tag.value >> 3n);
    const wire = Number(tag.value & 0x07n);
    if (field < 1) {
      throw new Error('Android resources protobuf field is malformed.');
    }
    if (wire === 0) {
      const parsed = readProtobufVarint(buffer, offset);
      offset = parsed.offset;
      fields.push({ field, value: parsed.value, wire });
      continue;
    }
    if (wire === 2) {
      const parsed = readProtobufVarint(buffer, offset);
      offset = parsed.offset;
      if (parsed.value > BigInt(Number.MAX_SAFE_INTEGER)) {
        throw new Error('Android resources protobuf length is too large.');
      }
      const size = Number(parsed.value);
      if (size < 0 || offset + size > buffer.length) {
        throw new Error('Android resources protobuf data is truncated.');
      }
      fields.push({
        field,
        value: buffer.subarray(offset, offset + size),
        wire,
      });
      offset += size;
      continue;
    }
    const fixedSize = wire === 1 ? 8 : wire === 5 ? 4 : 0;
    if (fixedSize === 0 || offset + fixedSize > buffer.length) {
      throw new Error(`Unsupported Android resources wire type: ${wire}`);
    }
    fields.push({
      field,
      value: buffer.subarray(offset, offset + fixedSize),
      wire,
    });
    offset += fixedSize;
  }
  return fields;
}

function protobufBytes(fields, number) {
  return fields
    .filter((candidate) => candidate.field === number && candidate.wire === 2)
    .map((candidate) => candidate.value);
}

function protobufString(fields, number) {
  const values = protobufBytes(fields, number);
  return values.length === 1 ? values[0].toString('utf8') : null;
}

function uniqueProtobufMessage(fields, number, label) {
  const values = protobufBytes(fields, number);
  if (values.length !== 1) {
    throw new Error(`Android resources ${label} must appear exactly once.`);
  }
  return protobufFields(values[0]);
}

export function parseAndroidBundleLocalizedAppNames(
  resources,
  { expectedPackageName = ANDROID_APP_PACKAGE } = {},
) {
  if (!Buffer.isBuffer(resources) || resources.length < 8) {
    throw new Error('Failed to read AAB resources.pb.');
  }
  const packages = protobufBytes(protobufFields(resources), 2)
    .map((value) => protobufFields(value))
    .filter((value) => protobufString(value, 2) === expectedPackageName);
  if (packages.length !== 1) {
    throw new Error('Did not find exactly one app package resource table in the AAB.');
  }
  const stringTypes = protobufBytes(packages[0], 3)
    .map((value) => protobufFields(value))
    .filter((value) => protobufString(value, 2) === 'string');
  if (stringTypes.length !== 1) {
    throw new Error('Did not find exactly one AAB string resource type.');
  }
  const nameEntries = protobufBytes(stringTypes[0], 3)
    .map((value) => protobufFields(value))
    .filter((value) => protobufString(value, 2) === 'godot_project_name_string');
  if (nameEntries.length !== 1) {
    throw new Error('Did not find exactly one AAB home-screen name resource.');
  }

  const localizedNames = {};
  for (const encodedConfigValue of protobufBytes(nameEntries[0], 6)) {
    const configValue = protobufFields(encodedConfigValue);
    const config = uniqueProtobufMessage(configValue, 1, 'name configuration');
    const locale = protobufString(config, 3) ?? '';
    const value = uniqueProtobufMessage(configValue, 2, 'name value');
    const item = uniqueProtobufMessage(value, 4, 'name item');
    const stringValue = uniqueProtobufMessage(item, 2, 'name string');
    const displayName = protobufString(stringValue, 1);
    if (displayName === null || Object.hasOwn(localizedNames, locale)) {
      throw new Error(`AAB ${locale || 'default'} home-screen name is ambiguous.`);
    }
    localizedNames[locale] = displayName;
  }
  return localizedNames;
}

export function parseAndroidApkLocalizedAppNames(badging) {
  const localizedNames = {};
  for (const match of String(badging).matchAll(
    /^application-label(?:-([^:]+))?:'(.*)'\s*$/gm,
  )) {
    const locale = match[1] ?? '';
    if (Object.hasOwn(localizedNames, locale)) {
      throw new Error(`APK ${locale || 'default'} home-screen name is duplicated.`);
    }
    localizedNames[locale] = match[2];
  }
  return localizedNames;
}

export function verifyAndroidLocalizedAppNames(
  archivePath,
  {
    archiveType,
    env = process.env,
    resolveAapt2 = resolveAndroidAapt2Path,
    spawn = spawnSync,
    timeoutMs = ANDROID_ARCHIVE_TOOL_TIMEOUT_MS,
  } = {},
) {
  if (!['aab', 'apk'].includes(archiveType)) {
    throw new Error('Android home-screen name verification format is invalid.');
  }
  let localizedNames;
  if (archiveType === 'aab') {
    const result = spawn(
      'unzip',
      ['-p', archivePath, 'base/resources.pb'],
      {
        encoding: null,
        env,
        killSignal: 'SIGTERM',
        maxBuffer: 16 * 1024 * 1024,
        stdio: ['ignore', 'pipe', 'pipe'],
        timeout: timeoutMs,
      },
    );
    if (result.status !== 0 || !Buffer.isBuffer(result.stdout)) {
      throw new Error('Failed to extract AAB resources.pb.');
    }
    localizedNames = parseAndroidBundleLocalizedAppNames(result.stdout);
  } else {
    const aapt2 = resolveAapt2({ env });
    const result = spawn(aapt2, ['dump', 'badging', archivePath], {
      encoding: 'utf8',
      env,
      killSignal: 'SIGTERM',
      maxBuffer: 16 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: timeoutMs,
    });
    if (result.status !== 0) {
      throw new Error('Failed to read the APK resource table.');
    }
    localizedNames = parseAndroidApkLocalizedAppNames(result.stdout);
  }

  if (localizedNames[''] !== 'Moonlit Beacon') {
    throw new Error('Android default home-screen name is not Moonlit Beacon.');
  }
  for (const { resourceLocale, displayName } of ANDROID_LOCALIZED_APP_NAMES) {
    if (localizedNames[resourceLocale] !== displayName) {
      throw new Error(
        `Android ${resourceLocale} home-screen name does not match store localization.`,
      );
    }
  }
  return true;
}

export function androidArchiveExcludesDevelopmentResources(listing) {
  const text = typeof listing === 'string' ? listing : '';
  return !/(?:^|\/)assets\/(?:tests|tools)\//m.test(text);
}

export function verifyAndroidArchiveResourceBoundary(
  archivePath,
  {
    env = process.env,
    spawn = spawnSync,
    timeoutMs = ANDROID_ARCHIVE_TOOL_TIMEOUT_MS,
  } = {},
) {
  if (typeof archivePath !== 'string' || archivePath.length === 0) {
    throw new Error('Android export output path is empty.');
  }
  const result = spawn('jar', ['tf', archivePath], {
    encoding: 'utf8',
    env,
    killSignal: 'SIGTERM',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: timeoutMs,
  });
  if (
    result.status !== 0
    || !androidArchiveExcludesDevelopmentResources(result.stdout)
  ) {
    throw new Error(
      result.status === 0
        ? 'The Android app contains test or production-tool resources.'
        : 'Could not read the Android app package resource listing.',
    );
  }
  return true;
}

function androidArchiveIapKitEntries(listing) {
  return String(listing)
    .split(/\r?\n/)
    .filter((entry) => /(?:^|\/)iapkit\.cfg$/.test(entry));
}

function androidArchiveHasSafeIapKitConfig(contents) {
  const text = typeof contents === 'string' ? contents : '';
  const sections = [...text.matchAll(/^\[iapkit\][ \t]*$/gm)];
  const assignments = [...text.matchAll(/^[ \t]*api_key[ \t]*=/gm)];
  const exact = text.match(
    /^\[iapkit\][ \t]*\r?\n[ \t]*api_key[ \t]*=[ \t]*"(openiap-kit_pk_[A-Za-z0-9_-]{32,})"[ \t]*$/m,
  );
  return sections.length === 1
    && assignments.length === 1
    && Boolean(exact)
    && !text.includes('openiap-kit_sk_');
}

export function verifyAndroidArchiveIapBoundary(
  archivePath,
  {
    env = process.env,
    spawn = spawnSync,
    store,
    timeoutMs = ANDROID_ARCHIVE_TOOL_TIMEOUT_MS,
  } = {},
) {
  if (typeof archivePath !== 'string' || archivePath.length === 0) {
    throw new Error('Android export output path is empty.');
  }
  if (typeof store !== 'boolean') {
    throw new Error('Android IAP distribution channel was not specified.');
  }
  const listing = spawn('jar', ['tf', archivePath], {
    encoding: 'utf8',
    env,
    killSignal: 'SIGTERM',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: timeoutMs,
  });
  if (listing.status !== 0) {
    throw new Error('Could not read the Android app IAPKit resource listing.');
  }
  const entries = androidArchiveIapKitEntries(listing.stdout);
  if (!store) {
    if (entries.length !== 0) {
      throw new Error('Direct-distribution Android app contains IAPKit config.');
    }
    return true;
  }
  if (entries.length !== 1) {
    throw new Error('Play AAB IAPKit config count is not 1.');
  }
  const config = spawn('unzip', ['-p', archivePath, entries[0]], {
    encoding: 'utf8',
    env,
    killSignal: 'SIGTERM',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: timeoutMs,
  });
  if (
    config.status !== 0
    || !androidArchiveHasSafeIapKitConfig(config.stdout)
  ) {
    throw new Error('Play AAB IAPKit publishable config is not safe.');
  }
  return true;
}

function archiveBufferContainsText(contents, text) {
  if (!Buffer.isBuffer(contents)) return false;
  return contents.includes(Buffer.from(text, 'utf8'))
    || contents.includes(Buffer.from(text, 'utf16le'));
}

export function verifyAndroidArchiveBillingBoundary(
  archivePath,
  {
    env = process.env,
    spawn = spawnSync,
    store,
    timeoutMs = ANDROID_ARCHIVE_TOOL_TIMEOUT_MS,
  } = {},
) {
  if (typeof archivePath !== 'string' || archivePath.length === 0) {
    throw new Error('Android export output path is empty.');
  }
  if (typeof store !== 'boolean') {
    throw new Error('Android Billing distribution channel was not specified.');
  }
  const listing = spawn('jar', ['tf', archivePath], {
    encoding: 'utf8',
    env,
    killSignal: 'SIGTERM',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: timeoutMs,
  });
  if (listing.status !== 0) {
    throw new Error('Could not read the Android app Billing resource listing.');
  }
  const entries = String(listing.stdout).split(/\r?\n/);
  const manifestEntry = store
    ? 'base/manifest/AndroidManifest.xml'
    : 'AndroidManifest.xml';
  const dexEntries = entries.filter(
    (entry) => /(?:^|\/)classes\d*\.dex$/.test(entry),
  );
  if (!entries.includes(manifestEntry) || dexEntries.length === 0) {
    throw new Error('Did not find the Android app manifest or DEX.');
  }
  const readEntry = (entry) => spawn(
    'unzip',
    ['-p', archivePath, entry],
    {
      encoding: null,
      env,
      killSignal: 'SIGTERM',
      maxBuffer: 128 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: timeoutMs,
    },
  );
  const manifest = readEntry(manifestEntry);
  if (manifest.status !== 0 || !Buffer.isBuffer(manifest.stdout)) {
    throw new Error('Could not read the Android app manifest.');
  }
  const hasBillingPermission = archiveBufferContainsText(
    manifest.stdout,
    'com.android.vending.BILLING',
  );
  let hasBillingClient = false;
  for (const entry of dexEntries) {
    const dex = readEntry(entry);
    if (dex.status !== 0 || !Buffer.isBuffer(dex.stdout)) {
      throw new Error('Could not read the Android app DEX.');
    }
    hasBillingClient ||= archiveBufferContainsText(
      dex.stdout,
      'com/android/billingclient',
    );
  }
  if (store && (!hasBillingPermission || !hasBillingClient)) {
    throw new Error('Play AAB has no Billing permission or client code.');
  }
  if (!store && (hasBillingPermission || hasBillingClient)) {
    throw new Error('Direct-distribution Android app contains the Billing SDK.');
  }
  return true;
}

export function invalidateAndroidBuildOutput(
  outputPath,
  lockAcquired,
) {
  if (!lockAcquired) return false;
  if (typeof outputPath !== 'string' || outputPath.length === 0) {
    throw new Error('Android export output path is empty.');
  }
  rmSync(outputPath, { force: true });
  return true;
}

export function androidReleasePartialPath(outputPath) {
  if (typeof outputPath !== 'string' || outputPath.length === 0) {
    throw new Error('Android release copy destination path is empty.');
  }
  return `${outputPath}.partial`;
}

export function androidV4SignatureSidecarPath(outputPath) {
  if (typeof outputPath !== 'string' || outputPath.length === 0) {
    throw new Error('Android v4 signature destination path is empty.');
  }
  return `${outputPath}.idsig`;
}

export function publishAndroidReleaseCopy(
  sourcePath,
  outputPath,
  lockAcquired,
  {
    copy = copyFileSync,
    rename = renameSync,
    remove = rmSync,
  } = {},
) {
  if (!lockAcquired) {
    throw new Error('Cannot create a release file without the Android build lock.');
  }
  const partial = androidReleasePartialPath(outputPath);
  remove(outputPath, { force: true });
  remove(partial, { force: true });
  try {
    copy(sourcePath, partial);
    rename(partial, outputPath);
  } catch (error) {
    remove(partial, { force: true });
    remove(outputPath, { force: true });
    throw error;
  }
  return true;
}

export function publishAndroidBuildOutput(
  candidatePath,
  outputPath,
  lockAcquired,
  {
    rename = renameSync,
    remove = rmSync,
  } = {},
) {
  if (!lockAcquired) {
    throw new Error('Cannot publish verified output without the Android build lock.');
  }
  remove(outputPath, { force: true });
  try {
    rename(candidatePath, outputPath);
  } catch (error) {
    remove(candidatePath, { force: true });
    remove(outputPath, { force: true });
    throw error;
  }
  return true;
}

export function aabVerificationIsSigned(result) {
  const output = `${result?.stdout ?? ''}\n${result?.stderr ?? ''}`;
  return result?.status === 0
    && /(?:^|\r?\n)jar verified\.(?:\r?\n|$)/.test(output)
    // `jar verified.` also appears on a partly unsigned JAR that had a file appended after signing.
    // Also require that every AAB payload was integrity-checked.
    && !/\bunsigned\b/i.test(output);
}

export function verifySignedAndroidBundle(
  bundlePath,
  {
    env = process.env,
    platform = process.platform,
    spawn = spawnSync,
    timeoutMs = ANDROID_ARCHIVE_TOOL_TIMEOUT_MS,
  } = {},
) {
  if (typeof bundlePath !== 'string' || bundlePath.length === 0) {
    throw new Error('Android App Bundle path is empty.');
  }
  const tool = resolveAndroidJavaToolInvocation('jarsigner', {
    env,
    platform,
  });
  const result = spawn(tool.command, [
    ...tool.prefixArgs,
    '-verify',
    bundlePath,
  ], {
    encoding: 'utf8',
    env: {
      ...env,
      LANG: 'C',
      LC_ALL: 'C',
    },
    killSignal: 'SIGTERM',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: timeoutMs,
  });
  // jarsigner also returns exit code 0 for an unsigned JAR. Require the exact
  // cryptographic verification success phrase, not just status.
  if (!aabVerificationIsSigned(result)) {
    throw new Error('Android App Bundle signature is missing or invalid.');
  }
  return true;
}

export function verifyAndroidReleaseSigner(
  archivePath,
  {
    alias,
    apksignerPath,
    archiveType,
    env = process.env,
    keystorePath,
    password,
    platform = process.platform,
    spawn = spawnSync,
    timeoutMs = ANDROID_ARCHIVE_TOOL_TIMEOUT_MS,
    validateCertificate = assertAndroidSigningCertificateValid,
  } = {},
) {
  if (!['aab', 'apk'].includes(archiveType)) {
    throw new Error('Android release output format is invalid.');
  }
  if (
    typeof alias !== 'string'
    || alias.length === 0
    || typeof keystorePath !== 'string'
    || keystorePath.length === 0
    || typeof password !== 'string'
    || password.length === 0
  ) {
    throw new Error('Android release signer verification config is empty.');
  }

  const childEnv = { ...env };
  delete childEnv.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD;
  const keytool = resolveAndroidJavaToolInvocation('keytool', {
    env: childEnv,
    platform,
  });
  const expected = spawn(
    keytool.command,
    [
      ...keytool.prefixArgs,
      '-exportcert',
      '-rfc',
      '-alias', alias,
      '-keystore', keystorePath,
    ],
    {
      encoding: 'utf8',
      env: childEnv,
      input: `${password}\n`,
      killSignal: 'SIGTERM',
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: timeoutMs,
    },
  );
  const expectedCertificate = expected.status === 0
    ? certificateDerFromPem(expected.stdout)
    : null;
  if (!expectedCertificate) {
    throw new Error('Failed to read the signer certificate from the Android release keystore.');
  }
  validateCertificate(expectedCertificate);
  const expectedDigest = createHash('sha256')
    .update(expectedCertificate)
    .digest('hex');

  let actualDigest = '';
  if (archiveType === 'aab') {
    verifySignedAndroidBundle(archivePath, {
      env: childEnv,
      platform,
      spawn,
      timeoutMs,
    });
    const actual = spawn(
      keytool.command,
      [
        ...keytool.prefixArgs,
        '-printcert',
        '-rfc',
        '-jarfile',
        archivePath,
      ],
      {
        encoding: 'utf8',
        env: childEnv,
        killSignal: 'SIGTERM',
        stdio: ['ignore', 'pipe', 'pipe'],
        timeout: timeoutMs,
      },
    );
    if (actual.status === 0) {
      actualDigest = certificateSha256FromPem(actual.stdout);
    }
  } else {
    if (typeof apksignerPath !== 'string' || apksignerPath.length === 0) {
      throw new Error('No apksigner path available to verify the release APK.');
    }
    const actual = spawn(
      apksignerPath,
      ['verify', '--verbose', '--print-certs', archivePath],
      {
        encoding: 'utf8',
        env: childEnv,
        killSignal: 'SIGTERM',
        stdio: ['ignore', 'pipe', 'pipe'],
        timeout: timeoutMs,
      },
    );
    if (actual.status === 0) {
      actualDigest = apkSignerCertificateSha256(
        `${actual.stdout ?? ''}\n${actual.stderr ?? ''}`,
      );
    }
  }
  if (!actualDigest || actualDigest !== expectedDigest) {
    throw new Error(
      'Android release output signer does not match the specified keystore.',
    );
  }
  return true;
}

export function signDebugAndroidBundle(
  bundlePath,
  {
    alias = 'androiddebugkey',
    env = process.env,
    exists = existsSync,
    keyPassword = 'android',
    keystorePath,
    platform = process.platform,
    spawn = spawnSync,
    storePassword = 'android',
    timeoutMs = ANDROID_ARCHIVE_TOOL_TIMEOUT_MS,
  } = {},
) {
  if (
    typeof keystorePath !== 'string'
    || keystorePath.length === 0
    || !exists(keystorePath)
  ) {
    throw new Error('Android debug keystore was not found.');
  }
  const tool = resolveAndroidJavaToolInvocation('jarsigner', {
    env,
    platform,
  });
  const result = spawn(tool.command, [
    ...tool.prefixArgs,
    '-keystore', keystorePath,
    '-storepass', storePassword,
    '-keypass', keyPassword,
    '-sigalg', 'SHA256withRSA',
    '-digestalg', 'SHA-256',
    bundlePath,
    alias,
  ], {
    encoding: 'utf8',
    env,
    killSignal: 'SIGTERM',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: timeoutMs,
  });
  if (result.status !== 0) {
    throw new Error('Android debug App Bundle signing failed.');
  }
  return verifySignedAndroidBundle(bundlePath, {
    env,
    platform,
    spawn,
    timeoutMs,
  });
}
