import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { basename, join } from 'node:path';
import { spawnSync } from 'node:child_process';

export const IOS_DEV_ASSET_FALLBACK_SETTINGS = [
  // In a dev environment where Xcode 26's AssetCatalogSimulatorAgent itself stalls,
  // clearing only the AppIcon name still re-runs actool because of SplashImage.
  // This workaround is only for Debug builds used to play on a connected device.
  'EXCLUDED_SOURCE_FILE_NAMES=Images.xcassets',
  'ASSETCATALOG_COMPILER_APPICON_NAME=',
  'ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS=NO',
];
export const IOS_IAP_FRAMEWORK_NAMES = [
  'GodotIap',
  'SwiftGodotRuntime',
];
export const IOS_DEV_LEGACY_ICON_PREFIX = 'MoonlitDevIcon-';
export const GODOT_RELEASE_EXCLUDED_RESOURCE_PREFIXES = [
  'res://tests/',
  'res://tools/',
];
export const IOS_PROCESS_GROUP_TERM_GRACE_MS = 250;
export const IOS_UNUSED_PRIVACY_DESCRIPTION_KEYS = Object.freeze([
  'NSCameraUsageDescription',
  'NSMicrophoneUsageDescription',
  'NSPhotoLibraryUsageDescription',
]);
export const IOS_LOCALIZED_DISPLAY_NAMES = Object.freeze([
  ['en-US', 'en', 'Moonlit Beacon'],
  ['ko', 'ko', '달빛 봉화'],
  ['ja', 'ja', '月明かりの烽火'],
  ['zh-Hans', 'zh_CN', '月光烽火'],
  ['zh-Hant', 'zh_TW', '月光烽火'],
].map(([storeLocale, bundleLocale, displayName]) => Object.freeze({
  storeLocale, bundleLocale, displayName,
})));

function waitSynchronously(milliseconds) {
  const signal = new Int32Array(
    new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT),
  );
  Atomics.wait(signal, 0, 0, milliseconds);
}

function signalProcessGroup(kill, processGroupId, signal) {
  try {
    kill(processGroupId, signal);
    return true;
  } catch (error) {
    if (error?.code === 'ESRCH') return false;
    throw error;
  }
}

export function terminateIosProcessGroup(
  pid,
  {
    kill = process.kill,
    pause = waitSynchronously,
    graceMs = IOS_PROCESS_GROUP_TERM_GRACE_MS,
  } = {},
) {
  if (!Number.isSafeInteger(pid) || pid <= 0) {
    throw new Error('iOS process group PID is invalid.');
  }
  const processGroupId = -pid;
  if (!signalProcessGroup(kill, processGroupId, 'SIGTERM')) {
    return { processGroupId, termSent: false, killSent: false };
  }
  pause(graceMs);
  const stillRunning = signalProcessGroup(kill, processGroupId, 0);
  const killSent = stillRunning
    && signalProcessGroup(kill, processGroupId, 'SIGKILL');
  return {
    processGroupId,
    termSent: true,
    killSent,
  };
}

export function spawnSyncInIosProcessGroup(
  command,
  args,
  options = {},
  {
    spawn = spawnSync,
    kill = process.kill,
    pause = waitSynchronously,
  } = {},
) {
  // detached makes the child PID the new process group ID on macOS/POSIX.
  // Failure cleanup therefore signals only -PID and does not touch other Xcode builds.
  const result = spawn(command, args, {
    ...options,
    detached: true,
  });
  if (
    (result?.error || result?.status !== 0)
    && Number.isSafeInteger(result?.pid)
    && result.pid > 0
  ) {
    terminateIosProcessGroup(result.pid, { kill, pause });
  }
  return result;
}

function assertIosExportDirectory(projectDir) {
  if (typeof projectDir !== 'string' || projectDir.length === 0) {
    throw new Error('iOS export path is empty.');
  }
}

export function prepareIosExportDirectory(projectDir) {
  assertIosExportDirectory(projectDir);
  rmSync(projectDir, { recursive: true, force: true });
  mkdirSync(projectDir, { recursive: true });
}

export function cleanupIncompleteIosExportDirectory(
  projectDir,
  exportComplete,
) {
  if (exportComplete) return false;
  assertIosExportDirectory(projectDir);
  rmSync(projectDir, { recursive: true, force: true });
  return true;
}

export function cleanupStaleIosWorkflowExportDirectory(
  projectDir,
  recoveredStaleLock,
) {
  if (!recoveredStaleLock) return false;
  return cleanupIncompleteIosExportDirectory(projectDir, false);
}

export function iosDebugAppPath(derivedDataPath, scheme) {
  return join(
    derivedDataPath,
    'Build/Products/Debug-iphoneos',
    `${scheme}.app`,
  );
}

export function iosDebugBuildArguments({
  project,
  scheme,
  destination,
  derivedDataPath,
  team,
  bundleIdentifier = null,
  useAssetFallback = false,
}) {
  const args = [
    '-project', project,
    '-scheme', scheme,
    '-configuration', 'Debug',
    '-destination', destination,
    '-derivedDataPath', derivedDataPath,
    `DEVELOPMENT_TEAM=${team}`,
    'CODE_SIGN_STYLE=Automatic',
    '-allowProvisioningUpdates',
  ];
  if (bundleIdentifier !== null) {
    if (
      typeof bundleIdentifier !== 'string'
      || !/^[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+$/u.test(bundleIdentifier)
    ) {
      throw new Error('iOS Debug override bundle ID is invalid');
    }
    args.push(`PRODUCT_BUNDLE_IDENTIFIER=${bundleIdentifier}`);
  }
  if (useAssetFallback) args.push(...IOS_DEV_ASSET_FALLBACK_SETTINGS);
  args.push('build');
  return args;
}

export function isAssetCatalogSimulatorPolicyFailure(output) {
  const text = typeof output === 'string' ? output : '';
  return text.includes('AssetCatalogSimulatorAgent')
    && (
      /Failed to launch AssetCatalogSimulatorAgent via CoreSimulator spawn/i
        .test(text)
      || /library load denied by system policy/i.test(text)
    );
}

export function shouldUseIosAssetFallback(error) {
  const output = typeof error?.output === 'string' ? error.output : '';
  if (isAssetCatalogSimulatorPolicyFailure(output)) return true;
  if (error?.code !== 'ETIMEDOUT') return false;
  // Do not misread a later-stage timeout just because asset catalog appeared once in the full log.
  // Look only at the actool window that was the last output when it stalled.
  const tail = output.slice(-12 * 1024);
  return tail.includes('CompileAssetCatalog')
    && tail.includes('Images.xcassets')
    && tail.includes('/actool');
}

export function runIosDebugBuildWithFallback(
  normalBuild,
  fallbackBuild,
  shouldFallback = () => false,
) {
  try {
    normalBuild();
    return false;
  } catch (error) {
    if (!shouldFallback(error)) throw error;
    fallbackBuild();
    return true;
  }
}

function localizedInfoPlistPath(bundlePath, bundleLocale) {
  return join(bundlePath, `${bundleLocale}.lproj`, 'InfoPlist.strings');
}

export function configureGeneratedIosInfoPlistLocalizations(
  projectDir,
  scheme,
) {
  assertIosExportDirectory(projectDir);
  if (typeof scheme !== 'string' || scheme.length === 0) {
    throw new Error('iOS scheme name is empty.');
  }
  const bundlePath = join(projectDir, scheme);
  const targets = IOS_LOCALIZED_DISPLAY_NAMES.map((localization) => ({
    ...localization,
    path: localizedInfoPlistPath(bundlePath, localization.bundleLocale),
  }));

  // Overwrite only files Godot registered on the Xcode project. If any is missing,
  // fail the whole export instead of applying a subset of languages, so a template change is visible.
  for (const target of targets) {
    if (!existsSync(target.path)) {
      throw new Error(
        `iOS ${target.storeLocale} InfoPlist.strings is missing: ${target.path}`,
      );
    }
  }
  for (const target of targets) {
    writeFileSync(
      target.path,
      `"CFBundleDisplayName" = ${JSON.stringify(target.displayName)};\n`,
      { encoding: 'utf8' },
    );
  }
  return targets.length;
}

export function verifyIosLocalizedDisplayNames(
  bundlePath,
  {
    env = process.env,
    spawn = spawnSync,
    exists = existsSync,
  } = {},
) {
  for (const localization of IOS_LOCALIZED_DISPLAY_NAMES) {
    const plist = localizedInfoPlistPath(
      bundlePath,
      localization.bundleLocale,
    );
    if (!exists(plist)) {
      throw new Error(
        `iOS ${localization.storeLocale} InfoPlist.strings is missing.`,
      );
    }
    const result = commandSucceeded(
      spawn,
      'plutil',
      ['-convert', 'json', '-o', '-', plist],
      env,
    );
    let values;
    try {
      values = result.status === 0 ? JSON.parse(result.stdout) : null;
    } catch {
      values = null;
    }
    if (
      values?.CFBundleDisplayName !== localization.displayName
    ) {
      throw new Error(
        `iOS ${localization.storeLocale} home-screen name does not match store localization.`,
      );
    }
    const unusedKey = IOS_UNUSED_PRIVACY_DESCRIPTION_KEYS.find(
      (key) => Object.hasOwn(values, key),
    );
    if (unusedKey) {
      throw new Error(
        `iOS ${localization.storeLocale} still has unused ${unusedKey} string.`,
      );
    }
  }
  return true;
}

export function pckHasSafeIapKitConfig(contents) {
  const text = Buffer.isBuffer(contents)
    ? contents.toString('latin1')
    : String(contents);
  const exactConfig = /(?:^|[\x00\r\n])\[iapkit\][ \t]*\r?\n[ \t]*api_key[ \t]*=[ \t]*"(openiap-kit_pk_[A-Za-z0-9_-]{32,})"[ \t]*(?=\r?\n|\x00|$)/;
  return exactConfig.test(text) && !text.includes('openiap-kit_sk_');
}

export function pckExcludesDevelopmentResources(contents) {
  const data = Buffer.isBuffer(contents)
    ? contents
    : Buffer.from(String(contents), 'latin1');
  return GODOT_RELEASE_EXCLUDED_RESOURCE_PREFIXES.every(
    (prefix) => !data.includes(Buffer.from(prefix, 'utf8')),
  );
}

function commandSucceeded(spawn, command, args, env) {
  return spawn(command, args, {
    encoding: 'utf8',
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function assertSuccessfulCommand(result, message) {
  if (result?.status !== 0) throw new Error(message);
  return result;
}

function appIconContentsPath(appIconSetPath) {
  return join(appIconSetPath, 'Contents.json');
}

export function iosDevelopmentLegacyIconFiles(
  appIconSetPath,
  {
    exists = existsSync,
    read = readFileSync,
  } = {},
) {
  const contentsPath = appIconContentsPath(appIconSetPath);
  if (!exists(contentsPath)) {
    throw new Error('iOS development legacy icon Contents.json is missing.');
  }

  let contents;
  try {
    contents = JSON.parse(read(contentsPath, 'utf8'));
  } catch {
    throw new Error('Could not read iOS AppIcon Contents.json.');
  }
  if (!Array.isArray(contents?.images)) {
    throw new Error('iOS AppIcon Contents.json has no images array.');
  }

  const sourceFileNames = contents.images
    // A 1024px marketing icon without scale is not a device launcher resource.
    .filter((image) => typeof image?.scale === 'string')
    .map((image) => image?.filename)
    .filter((filename) => typeof filename === 'string');
  const uniqueSourceFileNames = [...new Set(sourceFileNames)];
  if (uniqueSourceFileNames.length === 0) {
    throw new Error('iOS development legacy runtime icon is missing.');
  }

  return uniqueSourceFileNames.map((sourceFileName) => {
    if (
      basename(sourceFileName) !== sourceFileName
      || !/^[A-Za-z0-9._-]+\.png$/.test(sourceFileName)
    ) {
      throw new Error('iOS AppIcon file name is not safe.');
    }
    const sourcePath = join(appIconSetPath, sourceFileName);
    if (!exists(sourcePath)) {
      throw new Error(`iOS AppIcon PNG is missing: ${sourceFileName}`);
    }
    return {
      sourcePath,
      bundleFileName: `${IOS_DEV_LEGACY_ICON_PREFIX}${sourceFileName}`,
    };
  });
}

function developmentSigningAuthority(appPath, spawn, env) {
  const result = assertSuccessfulCommand(
    commandSucceeded(
      spawn,
      'codesign',
      ['--display', '--verbose=4', appPath],
      env,
    ),
    'Could not read the existing code signature of the iOS development fallback.',
  );
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  const authority = output
    .split(/\r?\n/)
    .map((line) => line.match(/^Authority=(Apple Development: [^\r\n]+)$/)?.[1])
    .find(Boolean);
  if (!authority) {
    throw new Error('iOS development fallback has no Apple Development signature.');
  }
  return authority;
}

function setPlistJsonValue(plist, keyPath, value, spawn, env) {
  const encoded = JSON.stringify(value);
  let result = commandSucceeded(
    spawn,
    'plutil',
    ['-replace', keyPath, '-json', encoded, plist],
    env,
  );
  if (result.status !== 0) {
    result = commandSucceeded(
      spawn,
      'plutil',
      ['-insert', keyPath, '-json', encoded, plist],
      env,
    );
  }
  assertSuccessfulCommand(
    result,
    `Failed to set ${keyPath} on the iOS development fallback Info.plist.`,
  );
}

export function installIosDevelopmentFallbackIcon(
  appPath,
  appIconSetPath,
  {
    env = process.env,
    spawn = spawnSync,
    exists = existsSync,
    read = readFileSync,
    copy = copyFileSync,
  } = {},
) {
  const plist = join(appPath, 'Info.plist');
  if (!exists(appPath) || !exists(plist)) {
    throw new Error('No app to put the iOS development fallback icon into.');
  }

  // Capture a valid development signing identity Xcode already made before changing
  // files or Info.plist. After that, keep existing entitlements and requirements as-is.
  const signingAuthority = developmentSigningAuthority(appPath, spawn, env);
  const icons = iosDevelopmentLegacyIconFiles(appIconSetPath, {
    exists,
    read,
  });
  for (const icon of icons) {
    copy(icon.sourcePath, join(appPath, icon.bundleFileName));
  }

  const bundleFileNames = icons.map((icon) => icon.bundleFileName);
  const primaryIcon = {
    CFBundleIconFiles: bundleFileNames,
    UIPrerenderedIcon: true,
  };
  setPlistJsonValue(
    plist,
    'CFBundleIcons',
    { CFBundlePrimaryIcon: primaryIcon },
    spawn,
    env,
  );
  setPlistJsonValue(
    plist,
    'CFBundleIcons~ipad',
    { CFBundlePrimaryIcon: primaryIcon },
    spawn,
    env,
  );
  // Also set the top-level compatibility key so tools that do not read CFBundleIcons,
  // such as Configurator or MDM, can use the same file.
  setPlistJsonValue(
    plist,
    'CFBundleIconFiles',
    bundleFileNames,
    spawn,
    env,
  );

  assertSuccessfulCommand(
    commandSucceeded(
      spawn,
      'codesign',
      [
        '--force',
        '--sign',
        signingAuthority,
        '--preserve-metadata=identifier,entitlements,requirements,flags,runtime',
        '--timestamp=none',
        appPath,
      ],
      env,
    ),
    'Failed to re-sign the iOS development fallback after inserting the legacy icon.',
  );
  assertSuccessfulCommand(
    commandSucceeded(
      spawn,
      'codesign',
      ['--verify', '--deep', '--strict', '--verbose=2', appPath],
      env,
    ),
    'Signature of the iOS development fallback with the legacy icon is invalid.',
  );
  return bundleFileNames;
}

function plistJsonValue(plist, keyPath, spawn, env) {
  const result = commandSucceeded(
    spawn,
    'plutil',
    ['-extract', keyPath, 'json', '-o', '-', plist],
    env,
  );
  if (result.status !== 0) return undefined;
  try {
    return JSON.parse(result.stdout);
  } catch {
    return undefined;
  }
}

function containsExactlyTheSameStrings(actual, expected) {
  if (!Array.isArray(actual) || actual.length !== expected.length) {
    return false;
  }
  const actualSet = new Set(actual);
  const expectedSet = new Set(expected);
  return actualSet.size === actual.length
    && expectedSet.size === expected.length
    && actual.every((value) =>
      typeof value === 'string' && expectedSet.has(value));
}

export function verifyInstallableIosApp(
  appPath,
  {
    expectedBundleId,
    expectedAppIconName,
    expectedLegacyAppIconFiles = [],
    verifyLocalizedDisplayNames = false,
    expectedAssetNames = [],
    expectedFrameworkNames = IOS_IAP_FRAMEWORK_NAMES,
    scheme,
    env = process.env,
    spawn = spawnSync,
    exists = existsSync,
    read = readFileSync,
  },
) {
  if (expectedAppIconName && expectedLegacyAppIconFiles.length > 0) {
    throw new Error('Cannot verify asset catalog and legacy iOS app icons at the same time.');
  }
  for (const fileName of expectedLegacyAppIconFiles) {
    if (
      typeof fileName !== 'string'
      || basename(fileName) !== fileName
      || !fileName.endsWith('.png')
    ) {
      throw new Error('iOS legacy app icon file name is not safe.');
    }
  }
  const requiredAssetNames = [
    ...new Set([
      ...expectedAssetNames,
      ...(expectedAppIconName ? [expectedAppIconName] : []),
    ]),
  ];
  const executable = join(appPath, scheme);
  const plist = join(appPath, 'Info.plist');
  const pck = join(appPath, `${scheme}.pck`);
  const frameworkExecutables = expectedFrameworkNames.map((name) =>
    join(appPath, 'Frameworks', `${name}.framework`, name));
  for (const path of [
    appPath,
    executable,
    plist,
    pck,
    ...frameworkExecutables,
  ]) {
    if (!exists(path)) {
      throw new Error('Output required to verify the iOS app is missing.');
    }
  }

  const signature = commandSucceeded(
    spawn,
    'codesign',
    ['--verify', '--deep', '--strict', '--verbose=2', appPath],
    env,
  );
  if (signature.status !== 0) {
    throw new Error('iOS app code signature is invalid.');
  }

  const architectures = commandSucceeded(
    spawn,
    'lipo',
    ['-archs', executable],
    env,
  );
  if (
    architectures.status !== 0
    || !architectures.stdout.split(/\s+/).includes('arm64')
  ) {
    throw new Error('iOS app executable has no arm64 architecture.');
  }
  for (let index = 0; index < frameworkExecutables.length; index += 1) {
    const frameworkArchitectures = commandSucceeded(
      spawn,
      'lipo',
      ['-archs', frameworkExecutables[index]],
      env,
    );
    if (
      frameworkArchitectures.status !== 0
      || !frameworkArchitectures.stdout.split(/\s+/).includes('arm64')
    ) {
      throw new Error(
        `iOS IAP framework has no arm64 architecture: `
        + expectedFrameworkNames[index],
      );
    }
  }

  const bundle = commandSucceeded(
    spawn,
    'plutil',
    ['-extract', 'CFBundleIdentifier', 'raw', plist],
    env,
  );
  if (bundle.status !== 0 || bundle.stdout.trim() !== expectedBundleId) {
    throw new Error('iOS app bundle ID does not match the expected value.');
  }

  if (verifyLocalizedDisplayNames) {
    verifyIosLocalizedDisplayNames(appPath, {
      env,
      spawn,
      exists,
    });
  }

  if (expectedAppIconName) {
    const appIcon = commandSucceeded(
      spawn,
      'plutil',
      [
        '-extract',
        'CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName',
        'raw',
        plist,
      ],
      env,
    );
    if (
      appIcon.status !== 0
      || appIcon.stdout.trim() !== expectedAppIconName
    ) {
      throw new Error('iOS App Store app icon metadata is missing.');
    }
  }

  if (expectedLegacyAppIconFiles.length > 0) {
    for (const fileName of expectedLegacyAppIconFiles) {
      if (!exists(join(appPath, fileName))) {
        throw new Error('iOS development legacy app icon PNG is missing.');
      }
    }
    const legacyIconKeyPaths = [
      'CFBundleIconFiles',
      'CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles',
      'CFBundleIcons~ipad.CFBundlePrimaryIcon.CFBundleIconFiles',
    ];
    for (const keyPath of legacyIconKeyPaths) {
      const files = plistJsonValue(plist, keyPath, spawn, env);
      if (!containsExactlyTheSameStrings(files, expectedLegacyAppIconFiles)) {
        throw new Error('iOS development legacy app icon metadata is missing.');
      }
    }
  }

  if (requiredAssetNames.length > 0) {
    const assets = join(appPath, 'Assets.car');
    if (!exists(assets)) {
      throw new Error('iOS app Assets.car is missing.');
    }
    const assetInfo = commandSucceeded(
      spawn,
      'xcrun',
      ['assetutil', '--info', assets],
      env,
    );
    let payload;
    try {
      payload = assetInfo.status === 0
        ? JSON.parse(assetInfo.stdout)
        : null;
    } catch {
      payload = null;
    }
    for (const name of requiredAssetNames) {
      if (!jsonContainsExactString(payload, name)) {
        throw new Error('A required iOS app asset catalog item is missing.');
      }
    }
  }

  const pckContents = read(pck);
  if (!pckHasSafeIapKitConfig(pckContents)) {
    throw new Error(
      'iOS app IAPKit config is missing or does not satisfy the publishable-key-only condition.',
    );
  }
  if (!pckExcludesDevelopmentResources(pckContents)) {
    throw new Error('The iOS app contains test or production-tool resources.');
  }
  return true;
}

export function jsonContainsExactString(value, expected) {
  if (value === expected) return true;
  if (Array.isArray(value)) {
    return value.some((entry) => jsonContainsExactString(entry, expected));
  }
  if (value && typeof value === 'object') {
    return Object.values(value).some(
      (entry) => jsonContainsExactString(entry, expected),
    );
  }
  return false;
}

export function devicectlResultContainsBundle(payload, bundleId) {
  return Boolean(payload && typeof payload === 'object' && payload.result)
    && jsonContainsExactString(payload.result, bundleId);
}

export function parseUsbMuxDeviceIds(output) {
  const text = typeof output === 'string' ? output : '';
  const ids = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) =>
      /^[0-9A-F]{40}$/i.test(line)
      || /^[0-9A-F]{8}-[0-9A-F]{16}$/i.test(line),
    );
  return [...new Set(ids)];
}

export function ideviceInstallerResultContainsBundle(output, bundleId) {
  if (
    typeof output !== 'string'
    || typeof bundleId !== 'string'
    || !/^[A-Za-z0-9.-]+$/.test(bundleId)
  ) {
    return false;
  }
  const escapedBundle = bundleId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(
    `<key>CFBundleIdentifier</key>\\s*<string>${escapedBundle}</string>`,
  ).test(output);
}

export function usbMuxListArguments(udid, bundleId) {
  return [
    '-u', udid,
    'list', '--user', '--xml',
    '-b', bundleId,
    '-a', 'CFBundleIdentifier',
  ];
}

export function usbMuxInstallArguments(udid, appPath, alreadyInstalled) {
  return [
    '-u', udid,
    '-w',
    alreadyInstalled ? 'upgrade' : 'install',
    appPath,
  ];
}

export function usbMuxLaunchArguments(udid, bundleId) {
  return ['-u', udid, '--detach', 'run', bundleId];
}

export function runUsbMuxInstallFlow({
  bundleId,
  listInstalled,
  install,
  verifyApp,
  launch,
}) {
  const before = listInstalled();
  const mode = ideviceInstallerResultContainsBundle(before, bundleId)
    ? 'upgrade'
    : 'install';
  install(mode);
  verifyApp();

  const after = listInstalled();
  if (!ideviceInstallerResultContainsBundle(after, bundleId)) {
    throw new Error('Did not find the target bundle ID on the iPad after USB install.');
  }

  try {
    launch();
    return { mode, launched: true, launchError: null };
  } catch (launchError) {
    return { mode, launched: false, launchError };
  }
}

export function runCoreDeviceInstallFlow({
  install,
  verifyApp,
  verifyInstalled,
  launch,
}) {
  // Only errors before install and verification finishes are transport-fallback candidates.
  // If the device is locked and only launch is refused, do not overwrite the already-installed app over USB again.
  install();
  verifyApp();
  verifyInstalled();
  try {
    launch();
    return { launched: true, launchError: null };
  } catch (launchError) {
    return { launched: false, launchError };
  }
}

export function runIosInstallWithFallback({
  coreDeviceId,
  usbDeviceId,
  discoverUsbDevice,
  installCoreDevice,
  installUsbDevice,
  onFallback = () => {},
}) {
  if (!coreDeviceId) {
    const discoveredUsbDevice = usbDeviceId ?? discoverUsbDevice();
    if (!discoveredUsbDevice) {
      throw new Error('No connected USB iOS device.');
    }
    return {
      transport: 'usbmux',
      deviceId: discoveredUsbDevice,
      result: installUsbDevice(discoveredUsbDevice),
      coreError: null,
    };
  }

  try {
    return {
      transport: 'coredevice',
      deviceId: coreDeviceId,
      result: installCoreDevice(coreDeviceId),
      coreError: null,
    };
  } catch (coreError) {
    let discoveredUsbDevice = usbDeviceId;
    try {
      discoveredUsbDevice ??= discoverUsbDevice();
    } catch (discoveryError) {
      throw new AggregateError(
        [coreError, discoveryError],
        'USB device search also failed after CoreDevice failure.',
        { cause: coreError },
      );
    }
    if (!discoveredUsbDevice) throw coreError;

    onFallback(coreError, discoveredUsbDevice);
    try {
      return {
        transport: 'usbmux',
        deviceId: discoveredUsbDevice,
        result: installUsbDevice(discoveredUsbDevice),
        coreError,
      };
    } catch (usbError) {
      throw new AggregateError(
        [coreError, usbError],
        'Both CoreDevice and USB install failed.',
        { cause: coreError },
      );
    }
  }
}

export function formatIosWorkflowError(error) {
  const messages = [];
  const visited = new Set();
  const collect = (current) => {
    if (current && typeof current === 'object') {
      if (visited.has(current)) return;
      visited.add(current);
    }
    const message = typeof current?.message === 'string'
      ? current.message
      : String(current);
    if (message && !messages.includes(message)) messages.push(message);

    const nested = Array.isArray(current?.errors) ? current.errors : [];
    for (const nestedError of nested) collect(nestedError);
    if (current?.cause && !nested.includes(current.cause)) {
      collect(current.cause);
    }
  };
  collect(error);
  return messages
    .map((message, index) => index === 0 ? message : `  - ${message}`)
    .join('\n');
}
