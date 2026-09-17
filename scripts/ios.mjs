// Export and install onto a physical iOS device.
//
// The flow has three steps, so this script ties them together:
//   1. Godot writes an Xcode project (preset export_project_only=true)
//   2. xcodebuild builds and signs it for arm64 devices
//   3. devicectl installs and launches it on the device
//
// Usage
//   node scripts/ios.mjs devices          list connected devices
//   node scripts/ios.mjs export           write the Xcode project only
//   node scripts/ios.mjs build [udid]     build and sign (generic if no udid)
//   node scripts/ios.mjs run [udid]       export → build → install → launch
//   node scripts/ios.mjs archive          App Store Release xcarchive
//   node scripts/ios.mjs export-appstore  archive → distribution-signed IPA
//   node scripts/ios.mjs validate --dry-run|run
//   node scripts/ios.mjs upload --dry-run|--confirm-upload
//
// :: Simulators are not supported ::
// Godot's iOS template has no arm64 simulator slice (x86_64 only), OpenGL ES
// on Apple Silicon simulators is broken in runtimes after iOS 15.4, and Godot
// strips Metal/Vulkan at compile time for simulator builds so there is no
// renderer besides gl_compatibility. Together those walls leave a blank
// screen. Use a physical device until upstream godotengine/godot#118161 lands.

import './lib/load-env.mjs';

import { spawnSync } from 'node:child_process';
import {
  cpSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  cleanupStaleGeneratedIapKitConfig,
  recoverDirectIapKitConfig,
  removeStagedIapKitConfig,
  stageIapKitConfigForStore,
} from './lib/iapkit-config.mjs';
import { runGodotExportPreflight } from './lib/godot-export-preflight.mjs';
import {
  cleanupIncompleteIosExportDirectory,
  cleanupStaleIosWorkflowExportDirectory,
  configureGeneratedIosInfoPlistLocalizations,
  devicectlResultContainsBundle,
  formatIosWorkflowError,
  installIosDevelopmentFallbackIcon,
  iosDebugAppPath,
  iosDebugBuildArguments,
  iosDevelopmentLegacyIconFiles,
  IOS_UNUSED_PRIVACY_DESCRIPTION_KEYS,
  parseUsbMuxDeviceIds,
  prepareIosExportDirectory,
  runCoreDeviceInstallFlow,
  runIosDebugBuildWithFallback,
  runIosInstallWithFallback,
  runUsbMuxInstallFlow,
  shouldUseIosAssetFallback,
  spawnSyncInIosProcessGroup,
  usbMuxInstallArguments,
  usbMuxLaunchArguments,
  usbMuxListArguments,
  verifyInstallableIosApp,
} from './lib/ios-build.mjs';
import {
  appStoreAltoolArguments,
  appStoreExportOptionsPlist,
  assertArchiveMetadata,
  assertArtifactFresh,
  assertArtifactNotOlderThan,
  assertDistributionEntitlements,
  assertDistributionProfile,
  assertDistributionSignatureDetails,
  assertProfileContainsSigningCertificate,
  assertSigningCertificateValid,
  codeSigningCertificateArguments,
  extractPlistDataValues,
  assertIosReleaseMetadata,
  assertIpaMetadata,
  assertMatchingReleasePayload,
  assertSafeIpaEntries,
  IOS_RELEASE_BUILD_CHAIN_INPUTS,
  iosReleaseExcludedPaths,
  parseIosCommandArguments,
  redactSensitiveValues,
  readAppStoreCredentials,
  readIosReleaseMetadata,
  runExclusiveIosWorkflow,
  runWithStableReleaseSources,
  xcodebuildAuthenticationArguments,
} from './lib/ios-distribution.mjs';
import { credentialFreeChildEnvironment } from './lib/release-environment.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SCHEME = 'MoonlitBeacon'; // = export path basename; Godot chooses that name.
const BUNDLE = 'com.crossplatformkorea.moonlitbeacon';
const ISOLATED_CAPTURE_BUNDLE = `${BUNDLE}.storecapture`;
const TEAM = 'PRDQGB267K';
const DEVICE_DISCOVERY_TIMEOUT_MS = 15 * 1000;
const DEVICE_INFO_TIMEOUT_MS = 30 * 1000;
const DEVICE_INSTALL_TIMEOUT_MS = 2 * 60 * 1000;
const DEVICE_LAUNCH_TIMEOUT_MS = 30 * 1000;
const IOS_DEBUG_BUILD_TIMEOUT_MS = 5 * 60 * 1000;
const IDEVICE_ID = process.env.MOONLIT_IDEVICE_ID_BIN ?? 'idevice_id';
const IDEVICEINSTALLER = process.env.MOONLIT_IDEVICEINSTALLER_BIN
  ?? 'ideviceinstaller';
const IDEVICEDEBUG = process.env.MOONLIT_IDEVICEDEBUG_BIN ?? 'idevicedebug';

const PROJ_DIR = join(ROOT, 'builds/ios');
const PROJ = join(PROJ_DIR, `${SCHEME}.xcodeproj`);
// Keep DerivedData outside builds/ios.
// The preset's delete_old_export_files_unconditionally=true wipes everything
// inside builds/ios on each export.
const DD = join(ROOT, 'builds/ios-dd');
// Separate artifact used only when the local Xcode/CoreSimulator runtime is broken.
// Never use this path or the asset-catalog bypass for an App Store archive.
const DEV_FALLBACK_DD = join(ROOT, 'builds/ios-dev-no-appicon-dd');
const ARCHIVE_DD = join(ROOT, 'builds/ios-archive-dd');
const ARCHIVE = join(ROOT, 'builds/ios-archive', `${SCHEME}.xcarchive`);
const ARCHIVE_INFO = join(ARCHIVE, 'Info.plist');
const APP_STORE_EXPORT_DIR = join(ROOT, 'builds/ios-app-store');
const APP_STORE_EXPORT_OPTIONS = join(
  APP_STORE_EXPORT_DIR,
  'ExportOptions.plist',
);
const APP_STORE_IPA = join(APP_STORE_EXPORT_DIR, `${SCHEME}.ipa`);
const APP_STORE_EXPORT_TIMEOUT_MS = 15 * 60 * 1000;
const APP_STORE_OPERATION_TIMEOUT_MS = 30 * 60 * 1000;
// export/build/run/archive all share the same generated Xcode project,
// DerivedData, or xcarchive. Even after one process drops the export lock,
// keep other iOS workflows from changing those artifacts until xcodebuild ends.
const IOS_WORKFLOW_LOCK = join(ROOT, 'builds/.ios-workflow.lock');
const IOS_WORKFLOW_LOCK_GUARD = join(
  ROOT,
  'builds/.ios-workflow-acquire.lock',
);
// Leaving the iOS-only GDExtension under res:// makes macOS/Windows/Linux
// editors ERROR while looking for their own platform libraries. Keep the
// source outside the project and stage it into the official addon path only
// while an iOS export is running.
const IAP_IOS_SOURCE = join(ROOT, 'vendor/godot-iap-ios/bin');
const IAP_ADDON = join(ROOT, 'apps/game/addons/godot-iap');
const IAP_IOS_STAGE = join(IAP_ADDON, 'bin');
const IAP_ANDROID_SOURCE = join(IAP_ADDON, 'android');
const IAP_ANDROID_STAGE = join(ROOT, 'builds/.godot-iap-android-stage');
const IAP_PLUGIN_CONFIG_SOURCE = join(IAP_ADDON, 'plugin.cfg');
const IAP_PLUGIN_CONFIG_STAGE = join(ROOT, 'builds/.godot-iap-plugin.cfg-stage');
// Android direct export also moves descriptor/AAR files in the same addon
// folder. Use a shared lock so both platforms cannot stage at once.
const IAP_EXPORT_LOCK = join(ROOT, 'builds/.godot-iap-export.lock');
const IAP_EXPORT_LOCK_GUARD = join(
  ROOT,
  'builds/.godot-iap-export-acquire.lock',
);
const IAP_FIXER = join(IAP_ADDON, 'scripts/fix_ios_embed.sh');
const IAP_EXTENSION_CACHE = join(ROOT, 'apps/game/.godot/extension_list.cfg');
const IOS_APP_ICON_SET = join(
  PROJ_DIR,
  SCHEME,
  'Images.xcassets/AppIcon.appiconset',
);
const CHILD_ENV = credentialFreeChildEnvironment(process.env);
// Do not pass the publishable key into child processes outside the export
// steps that need it. Pass App Store Connect credentials only as the
// xcodebuild/altool arguments that require them. Keep them out of ordinary
// Godot/device-tool environments and failure logs. iOS tooling never needs
// Android keystore values.

function run(cmd, args, opts = {}) {
  const {
    captureOutput = false,
    isolatedProcessGroup = false,
    printCapturedOutput = true,
    sensitiveValues = [],
    ...spawnOptions
  } = opts;
  const runChild = isolatedProcessGroup
    ? spawnSyncInIosProcessGroup
    : spawnSync;
  const r = runChild(cmd, args, {
    stdio: captureOutput ? ['inherit', 'pipe', 'pipe'] : 'inherit',
    encoding: captureOutput ? 'utf8' : undefined,
    maxBuffer: captureOutput ? 64 * 1024 * 1024 : undefined,
    cwd: ROOT,
    env: CHILD_ENV,
    ...spawnOptions,
  });
  const safeStdout = captureOutput
    ? redactSensitiveValues(r.stdout, sensitiveValues)
    : r.stdout;
  const safeStderr = captureOutput
    ? redactSensitiveValues(r.stderr, sensitiveValues)
    : r.stderr;
  if (captureOutput && printCapturedOutput) {
    if (safeStdout) process.stdout.write(safeStdout);
    if (safeStderr) process.stderr.write(safeStderr);
  }
  if (r.status !== 0) {
    const error = new Error(
      r.error?.code === 'ETIMEDOUT'
        ? `${cmd} timed out`
        : `${cmd} failed`,
    );
    error.exitCode = r.status ?? 1;
    error.code = r.error?.code;
    // Keep only for fallback detection or diagnostics. Calls that use auth
    // arguments redact via sensitiveValues first, so real values never land
    // in the error object or the terminal.
    error.output = captureOutput
      ? `${safeStdout ?? ''}\n${safeStderr ?? ''}`
      : '';
    throw error;
  }
  return captureOutput
    ? { ...r, stdout: safeStdout, stderr: safeStderr }
    : r;
}

// Godot writes unused privacy-description keys into Info.plist as empty
// strings. Empty strings make xcodebuild warn and become a rejection reason
// in review. This game does not use camera, microphone, or photo library, so
// delete the keys entirely (better than declaring unused permissions with
// empty values). They come back on every export, so strip them right after.
function stripUnusedPrivacyKeys() {
  const plist = join(PROJ_DIR, SCHEME, `${SCHEME}-Info.plist`);
  if (!existsSync(plist)) return;
  for (const key of IOS_UNUSED_PRIVACY_DESCRIPTION_KEYS) {
    // plutil exits 1 when the key is already absent; that is fine.
    spawnSync('plutil', ['-remove', key, plist], {
      env: CHILD_ENV,
      stdio: 'ignore',
    });
  }
  console.log(
    `Removed ${IOS_UNUSED_PRIVACY_DESCRIPTION_KEYS.length} unused privacy `
    + `description keys from Info.plist.`,
  );
}

// On Xcode 26.6, compiling Godot's old Launch Screen.storyboard with ibtool
// can hang IBAgent-iOS. Showing the same SplashImage via the supported
// UILaunchScreen dictionary keeps a static store launch screen without going
// through Interface Builder.
function configureStoryboardFreeLaunchScreen() {
  const plist = join(PROJ_DIR, SCHEME, `${SCHEME}-Info.plist`);
  const pbxproj = join(PROJ, 'project.pbxproj');
  if (!existsSync(plist) || !existsSync(pbxproj)) {
    throw new Error('generated project file for the iOS launch screen fix is missing.');
  }

  run('plutil', ['-remove', 'UILaunchStoryboardName', plist]);
  run('plutil', [
    '-insert',
    'UILaunchScreen',
    '-xml',
    '<dict><key>UIImageName</key><string>SplashImage</string>'
      + '<key>UIImageRespectsSafeAreaInsets</key><false/></dict>',
    plist,
  ]);

  const source = readFileSync(pbxproj, 'utf8');
  const lines = source.split('\n');
  const filtered = lines.filter((line) => !line.includes('Launch Screen.storyboard'));
  const removed = lines.length - filtered.length;
  if (removed !== 4) {
    throw new Error(`Launch Screen.storyboard references are not exactly 4: found ${removed}`);
  }
  writeFileSync(pbxproj, filtered.join('\n'));
  console.log('Switched the iOS launch screen to storyboard-free UILaunchScreen.');
}

// Godot 4.7.1 writes an Apple Distribution identity into Release while leaving
// ProvisioningStyle Automatic. Xcode 26 rejects that combination. Remove only
// the manual Release identity from the generated project so automatic signing
// builds the archive and Organizer re-signs for distribution.
function configureAutomaticReleaseSigning() {
  const pbxproj = join(PROJ, 'project.pbxproj');
  const source = readFileSync(pbxproj, 'utf8');
  const lines = source.split('\n');
  const filtered = lines.filter(
    (line) => !line.includes('CODE_SIGN_IDENTITY = "Apple Distribution";'),
  );
  const removed = lines.length - filtered.length;
  if (removed !== 2) {
    throw new Error(`Apple Distribution manual identity entries are not exactly 2: found ${removed}`);
  }
  writeFileSync(pbxproj, filtered.join('\n'));
}

let stagedIapIos = false;
let stagedIapKitConfig = false;
let ownsIapIosLock = false;
let ownsIapIosLockGuard = false;
let ownsIosWorkflowLock = false;
let ownsIosWorkflowLockGuard = false;

function processIsAlive(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    // Treat as alive even when the process belongs to another user and we lack signal rights.
    return error?.code === 'EPERM';
  }
}

function readLockPid(lockPath) {
  try {
    return Number.parseInt(readFileSync(lockPath, 'utf8').trim(), 10);
  } catch {
    return 0;
  }
}

function acquireIosWorkflowLockGuard() {
  try {
    writeFileSync(IOS_WORKFLOW_LOCK_GUARD, `${process.pid}\n`, {
      encoding: 'utf8',
      flag: 'wx',
    });
    ownsIosWorkflowLockGuard = true;
  } catch (error) {
    if (error?.code !== 'EEXIST') throw error;
    const ownerPid = readLockPid(IOS_WORKFLOW_LOCK_GUARD);
    if (processIsAlive(ownerPid)) {
      throw new Error(`another iOS job is preparing the lock (PID ${ownerPid}).`);
    }
    throw new Error(
      `stale iOS workflow lock-prepare file remains. Confirm no job is running, `
      + `then delete ${IOS_WORKFLOW_LOCK_GUARD}.`,
    );
  }
}

function releaseIosWorkflowLockGuard() {
  if (ownsIosWorkflowLockGuard) {
    rmSync(IOS_WORKFLOW_LOCK_GUARD, { force: true });
  }
  ownsIosWorkflowLockGuard = false;
}

function acquireIosWorkflowLock() {
  mkdirSync(dirname(IOS_WORKFLOW_LOCK), { recursive: true });
  acquireIosWorkflowLockGuard();
  let recoveredStaleLock = false;
  try {
    try {
      writeFileSync(IOS_WORKFLOW_LOCK, `${process.pid}\n`, {
        encoding: 'utf8',
        flag: 'wx',
      });
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      const ownerPid = readLockPid(IOS_WORKFLOW_LOCK);
      if (processIsAlive(ownerPid)) {
        throw new Error(`another iOS job is running (PID ${ownerPid}).`);
      }
      rmSync(IOS_WORKFLOW_LOCK, { force: true });
      writeFileSync(IOS_WORKFLOW_LOCK, `${process.pid}\n`, {
        encoding: 'utf8',
        flag: 'wx',
      });
      recoveredStaleLock = true;
    }
    ownsIosWorkflowLock = true;
    if (recoveredStaleLock) {
      // A hard kill skips doExport()'s finally. Discard only the exact generated
      // path so the next `ios:build` does not trust a partial Xcode project.
      cleanupStaleIosWorkflowExportDirectory(PROJ_DIR, true);
      console.log('Recovered a stale previous iOS workflow lock.');
    }
  } finally {
    releaseIosWorkflowLockGuard();
  }
}

function releaseIosWorkflowLock() {
  if (ownsIosWorkflowLock) rmSync(IOS_WORKFLOW_LOCK, { force: true });
  ownsIosWorkflowLock = false;
}

function acquireIapIosLockGuard() {
  try {
    writeFileSync(IAP_EXPORT_LOCK_GUARD, `${process.pid}\n`, {
      encoding: 'utf8',
      flag: 'wx',
    });
    ownsIapIosLockGuard = true;
  } catch (error) {
    if (error?.code !== 'EEXIST') throw error;
    const ownerPid = readLockPid(IAP_EXPORT_LOCK_GUARD);
    if (processIsAlive(ownerPid)) {
      throw new Error(`another IAP export is preparing the lock (PID ${ownerPid}).`);
    }
    throw new Error(
      `stale IAP lock-prepare file remains. Confirm no export is running, `
      + `then delete ${IAP_EXPORT_LOCK_GUARD}.`,
    );
  }
}

function releaseIapIosLockGuard() {
  if (ownsIapIosLockGuard) rmSync(IAP_EXPORT_LOCK_GUARD, { force: true });
  ownsIapIosLockGuard = false;
}

function acquireIapIosLock() {
  mkdirSync(dirname(IAP_EXPORT_LOCK), { recursive: true });
  acquireIapIosLockGuard();
  let recoveredStaleLock = false;
  try {
    try {
      writeFileSync(IAP_EXPORT_LOCK, `${process.pid}\n`, {
        encoding: 'utf8',
        flag: 'wx',
      });
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      const ownerPid = readLockPid(IAP_EXPORT_LOCK);
      if (processIsAlive(ownerPid)) {
        throw new Error(`another IAP export is running (PID ${ownerPid}).`);
      }
      rmSync(IAP_EXPORT_LOCK, { force: true });
      writeFileSync(IAP_EXPORT_LOCK, `${process.pid}\n`, {
        encoding: 'utf8',
        flag: 'wx',
      });
      recoveredStaleLock = true;
    }
    ownsIapIosLock = true;
    try {
      if (existsSync(IAP_ANDROID_STAGE)) {
        if (existsSync(IAP_ANDROID_SOURCE)) {
          throw new Error('IAP Android source and temp path both exist');
        }
        renameSync(IAP_ANDROID_STAGE, IAP_ANDROID_SOURCE);
      }
      if (existsSync(IAP_PLUGIN_CONFIG_STAGE)) {
        if (existsSync(IAP_PLUGIN_CONFIG_SOURCE)) {
          throw new Error('IAP plugin.cfg source and temp path both exist');
        }
        renameSync(IAP_PLUGIN_CONFIG_STAGE, IAP_PLUGIN_CONFIG_SOURCE);
      }
      recoverDirectIapKitConfig(ROOT);
      cleanupStaleGeneratedIapKitConfig(ROOT);
      if (existsSync(IAP_IOS_STAGE) && IAP_IOS_STAGE.startsWith(IAP_ADDON + '/')) {
        rmSync(IAP_IOS_STAGE, { recursive: true, force: true });
      }
      // Even if a prior unstage was killed right after deleting bin and only
      // cache remains, always regenerate under the shared lock so preflight
      // never reads a stale iOS descriptor.
      if (existsSync(IAP_EXTENSION_CACHE)) rmSync(IAP_EXTENSION_CACHE);
    } catch (error) {
      rmSync(IAP_EXPORT_LOCK, { force: true });
      ownsIapIosLock = false;
      throw error;
    }
    if (recoveredStaleLock) {
      console.log('Cleaned up stale IAP temp files from a previous iOS export.');
    }
  } finally {
    releaseIapIosLockGuard();
  }
}

function stageIapIos() {
  if (!existsSync(IAP_IOS_SOURCE)) {
    throw new Error(`iOS IAP source is missing: ${IAP_IOS_SOURCE}`);
  }
  if (!ownsIapIosLock) acquireIapIosLock();
  // Even if copy fails mid-way, the caller finally must still be able to remove the partial copy.
  stagedIapIos = true;
  cpSync(IAP_IOS_SOURCE, IAP_IOS_STAGE, { recursive: true });
  stageIapKitConfigForStore(ROOT);
  stagedIapKitConfig = true;
}

function unstageIapIos() {
  let cleanupError;
  if (ownsIapIosLock && stagedIapKitConfig) {
    try {
      removeStagedIapKitConfig(ROOT);
    } catch (error) {
      cleanupError = error;
    }
  }
  if (ownsIapIosLock && stagedIapIos && IAP_IOS_STAGE.startsWith(IAP_ADDON + '/')) {
    try {
      rmSync(IAP_IOS_STAGE, { recursive: true, force: true });
    } catch (error) {
      cleanupError ??= error;
    }
  }
  if (ownsIapIosLock) {
    // A competing process that never got the lock must not wipe this export's
    // cache. Finish cache cleanup under the lock so new-export files stay.
    try {
      if (existsSync(IAP_EXTENSION_CACHE)) rmSync(IAP_EXTENSION_CACHE);
    } catch (error) {
      cleanupError ??= error;
    }
    try {
      rmSync(IAP_EXPORT_LOCK, { force: true });
    } catch (error) {
      cleanupError ??= error;
    }
  }
  stagedIapIos = false;
  stagedIapKitConfig = false;
  ownsIapIosLock = false;
  if (cleanupError) throw cleanupError;
}

function fixIapIosEmbedding() {
  run('bash', [IAP_FIXER], {
    env: {
      ...CHILD_ENV,
      // The official post-process script only needs python3. Run the macOS
      // system tool so results do not depend on pyenv/Homebrew shims.
      PATH: ['/usr/bin', '/bin', '/usr/sbin', '/sbin', process.env.PATH]
        .filter(Boolean)
        .join(':'),
      IOS_EXPORT_DIR: PROJ_DIR,
      GODOT_IAP_ADDON_DIR: IAP_ADDON,
      XCODEPROJ: PROJ,
    },
  });
}

function verifyAppStoreExportOptions() {
  const options = join(PROJ_DIR, SCHEME, 'export_options.plist');
  if (!existsSync(options)) {
    throw new Error(`iOS Release export options are missing: ${options}`);
  }
  const result = spawnSync(
    'plutil',
    ['-extract', 'method', 'raw', options],
    { encoding: 'utf8', cwd: ROOT, env: CHILD_ENV },
  );
  const method = result.status === 0 ? result.stdout.trim() : '';
  if (!['app-store', 'app-store-connect'].includes(method)) {
    throw new Error(`iOS Release distribution method is not App Store: ${method || 'none'}`);
  }
}

function doExport(release = false) {
  // Even if key resolution or framework staging fails, discard only this
  // attempt's exact artifacts first so the next build does not mistake an old
  // Xcode project for a fresh export.
  prepareIosExportDirectory(PROJ_DIR);
  let exportStepsComplete = false;
  let exportComplete = false;
  try {
    // Godot export can print a script parse error and still exit 0. Validate
    // the main scene and every script in a separate run before touching shared staging.
    acquireIapIosLock();
    runGodotExportPreflight({
      root: ROOT,
      env: CHILD_ENV,
    });
    stageIapIos();
    run('node', [
      'scripts/godot.mjs',
      '--headless',
      '--path',
      'apps/game',
      release ? '--export-release' : '--export-debug',
      'iOS',
      // Relative paths are rooted at --path. Climb two levels from apps/game.
      '../../builds/ios/MoonlitBeacon.ipa',
    ]);
    stripUnusedPrivacyKeys();
    const localizedNameCount = configureGeneratedIosInfoPlistLocalizations(
      PROJ_DIR,
      SCHEME,
    );
    console.log(`Configured ${localizedNameCount} iOS home-screen display names.`);
    fixIapIosEmbedding();
    configureStoryboardFreeLaunchScreen();
    if (release) {
      configureAutomaticReleaseSigning();
      verifyAppStoreExportOptions();
    }
    exportStepsComplete = true;
  } finally {
    try {
      unstageIapIos();
      // Source staging cleanup must succeed before a separate `ios:build` can
      // trust this project as a complete export.
      exportComplete = exportStepsComplete;
    } finally {
      cleanupIncompleteIosExportDirectory(PROJ_DIR, exportComplete);
    }
  }
}

function doBuild(udid, bundleIdentifier = BUNDLE) {
  if (!existsSync(PROJ)) {
    throw new Error(
      `${PROJ} is missing. Run first: node scripts/ios.mjs export`,
    );
  }
  const destination = udid ? `platform=iOS,id=${udid}` : 'generic/platform=iOS';
  let app = iosDebugAppPath(DD, SCHEME);
  if (process.env.MOONLIT_IOS_DEV_ASSET_FALLBACK === '1') {
    console.warn(
      'Explicitly using the no-asset-catalog iOS build for development. '
      + 'It cannot be used for App Store submission.',
    );
    rmSync(DEV_FALLBACK_DD, { recursive: true, force: true });
    run('xcodebuild', iosDebugBuildArguments({
      project: PROJ,
      scheme: SCHEME,
      destination,
      derivedDataPath: DEV_FALLBACK_DD,
      team: TEAM,
      bundleIdentifier,
      useAssetFallback: true,
    }), {
      isolatedProcessGroup: true,
      timeout: IOS_DEBUG_BUILD_TIMEOUT_MS,
      killSignal: 'SIGTERM',
    });
    app = iosDebugAppPath(DEV_FALLBACK_DD, SCHEME);
    installIosFallbackIcon(app);
    verifyDebugIosApp(app, 'after successful Debug development build', bundleIdentifier);
    return app;
  }
  const usedFallback = runIosDebugBuildWithFallback(
    () => run(
      'xcodebuild',
      iosDebugBuildArguments({
        project: PROJ,
        scheme: SCHEME,
        destination,
        derivedDataPath: DD,
        team: TEAM,
        bundleIdentifier,
      }),
      {
        captureOutput: true,
        isolatedProcessGroup: true,
        timeout: IOS_DEBUG_BUILD_TIMEOUT_MS,
        killSignal: 'SIGTERM',
      },
    ),
    () => {
      console.warn(
        'Normal iOS Debug build failed. Retrying once with the no-asset-catalog '
        + 'development build.',
      );
      console.warn(
        'This bypass artifact is for attached-device play only and cannot be used for App Store submission.',
      );
      rmSync(DEV_FALLBACK_DD, { recursive: true, force: true });
      run('xcodebuild', iosDebugBuildArguments({
        project: PROJ,
        scheme: SCHEME,
        destination,
        derivedDataPath: DEV_FALLBACK_DD,
        team: TEAM,
        bundleIdentifier,
        useAssetFallback: true,
      }), {
        isolatedProcessGroup: true,
        timeout: IOS_DEBUG_BUILD_TIMEOUT_MS,
        killSignal: 'SIGTERM',
      });
    },
    shouldUseIosAssetFallback,
  );
  if (usedFallback) {
    app = iosDebugAppPath(DEV_FALLBACK_DD, SCHEME);
    installIosFallbackIcon(app);
  }
  verifyDebugIosApp(app, 'after successful Debug build', bundleIdentifier);
  return app;
}

function installIosFallbackIcon(app) {
  const iconFiles = installIosDevelopmentFallbackIcon(
    app,
    IOS_APP_ICON_SET,
    { env: CHILD_ENV },
  );
  console.log(
    `Added ${iconFiles.length} home-screen legacy icon PNGs to the development `
    + 'fallback and re-signed.',
  );
}

function verifyIosApp(
  app,
  moment,
  expectedAppIconName,
  expectedLegacyAppIconFiles = [],
  expectedBundleId = BUNDLE,
) {
  const developmentWithoutAssets = app === iosDebugAppPath(
    DEV_FALLBACK_DD,
    SCHEME,
  );
  verifyInstallableIosApp(app, {
    expectedBundleId,
    expectedAppIconName,
    expectedLegacyAppIconFiles,
    verifyLocalizedDisplayNames: true,
    expectedAssetNames: developmentWithoutAssets ? [] : ['SplashImage'],
    scheme: SCHEME,
    env: CHILD_ENV,
  });
  console.log(
    developmentWithoutAssets
      ? `${moment}: arm64 · bundle ID · code signing · legacy app icon · `
        + `IAPKit pk-only · release resource boundary checks passed `
        + `(development asset catalog excluded)`
      : `${moment}: arm64 · bundle ID · code signing · asset catalog · `
        + `IAPKit pk-only · release resource boundary checks passed`,
  );
}

function verifyDebugIosApp(app, moment, expectedBundleId = BUNDLE) {
  const fallbackApp = iosDebugAppPath(DEV_FALLBACK_DD, SCHEME);
  const isFallback = app === fallbackApp;
  const expectedLegacyAppIconFiles = isFallback
    ? iosDevelopmentLegacyIconFiles(IOS_APP_ICON_SET)
      .map((icon) => icon.bundleFileName)
    : [];
  verifyIosApp(
    app,
    moment,
    isFallback ? undefined : 'AppIcon',
    expectedLegacyAppIconFiles,
    expectedBundleId,
  );
}

function verifyInstalledBundle(udid) {
  const output = join(ROOT, 'builds', `.ios-installed-app-${process.pid}.json`);
  rmSync(output, { force: true });
  try {
    run('xcrun', [
      'devicectl', 'device', 'info', 'apps',
      '--device', udid,
      '--bundle-id', BUNDLE,
      '--json-output', output,
    ], { timeout: DEVICE_INFO_TIMEOUT_MS, killSignal: 'SIGTERM' });
    if (!existsSync(output)) {
      throw new Error('installed iOS app query returned no result.');
    }
    const payload = JSON.parse(readFileSync(output, 'utf8'));
    if (!devicectlResultContainsBundle(payload, BUNDLE)) {
      throw new Error('could not confirm the installed Moonlit Beacon bundle ID on the device.');
    }
  } finally {
    rmSync(output, { force: true });
  }
  console.log('Confirmed the installed Moonlit Beacon bundle ID on the device.');
}

function installAndLaunchWithDevicectl(udid, app) {
  const result = runCoreDeviceInstallFlow({
    install: () => run('xcrun', [
      'devicectl', 'device', 'install', 'app',
      '--device', udid, app,
    ], { timeout: DEVICE_INSTALL_TIMEOUT_MS, killSignal: 'SIGTERM' }),
    verifyApp: () => verifyDebugIosApp(app, 'after successful install'),
    verifyInstalled: () => verifyInstalledBundle(udid),
    launch: () => run('xcrun', [
      'devicectl', 'device', 'process', 'launch',
      '--device', udid, BUNDLE,
    ], { timeout: DEVICE_LAUNCH_TIMEOUT_MS, killSignal: 'SIGTERM' }),
  });
  if (result.launched) {
    console.log('Confirmed iPad install and auto-launch via CoreDevice.');
  } else {
    console.warn(
      'CoreDevice install finished, but auto-launch failed. '
      + 'If the iPad is locked, unlock it and tap the Moonlit Beacon icon.',
    );
  }
  return result;
}

function firstUsbMuxDevice() {
  const result = spawnSync(IDEVICE_ID, ['-l'], {
    encoding: 'utf8',
    env: CHILD_ENV,
    timeout: DEVICE_DISCOVERY_TIMEOUT_MS,
    killSignal: 'SIGTERM',
  });
  if (result.status !== 0) return null;
  const devices = parseUsbMuxDeviceIds(result.stdout);
  if (devices.length > 1) {
    throw new Error(
      `Found ${devices.length} USB iOS devices. Connect only one and retry.`,
    );
  }
  return devices[0] ?? null;
}

function usbMuxInstalledBundleOutput(udid) {
  return run(
    IDEVICEINSTALLER,
    usbMuxListArguments(udid, BUNDLE),
    {
      captureOutput: true,
      printCapturedOutput: false,
      timeout: DEVICE_INFO_TIMEOUT_MS,
      killSignal: 'SIGTERM',
    },
  ).stdout ?? '';
}

function installAndLaunchWithUsbMux(udid, app) {
  let result;
  try {
    result = runUsbMuxInstallFlow({
      bundleId: BUNDLE,
      listInstalled: () => usbMuxInstalledBundleOutput(udid),
      install: (mode) => run(
        IDEVICEINSTALLER,
        usbMuxInstallArguments(udid, app, mode === 'upgrade'),
        {
          timeout: DEVICE_INSTALL_TIMEOUT_MS,
          killSignal: 'SIGTERM',
        },
      ),
      verifyApp: () => verifyDebugIosApp(app, 'after successful USB install'),
      launch: () => run(
        IDEVICEDEBUG,
        usbMuxLaunchArguments(udid, BUNDLE),
        {
          timeout: DEVICE_LAUNCH_TIMEOUT_MS,
          killSignal: 'SIGTERM',
        },
      ),
    });
  } catch (error) {
    if (error.code === 'ENOENT') {
      throw new Error(
        'ideviceinstaller is required for CoreDevice-bypass install. '
        + 'Run `brew install ideviceinstaller` and retry.',
      );
    }
    throw error;
  }
  console.log('Finished USB iPad install and bundle ID confirmation.');
  if (result.launched) {
    console.log('Confirmed iPad auto-launch over USB.');
  } else {
    console.warn(
      'Install finished, but USB auto-launch failed. '
      + 'Tap the Moonlit Beacon icon on the iPad to launch.',
    );
  }
}

function readPlistJson(plist, label, keyPath) {
  const args = keyPath
    ? ['-extract', keyPath, 'json', '-o', '-', plist]
    : ['-convert', 'json', '-o', '-', plist];
  const result = run(
    'plutil',
    args,
    {
      captureOutput: true,
      printCapturedOutput: false,
    },
  );
  try {
    return JSON.parse(result.stdout);
  } catch {
    throw new Error(`could not parse ${label} plist as JSON.`);
  }
}

function readOptionalPlistValue(plist, keyPath, format) {
  const result = spawnSync(
    'plutil',
    ['-extract', keyPath, format, '-o', '-', plist],
    {
      encoding: 'utf8',
      cwd: ROOT,
      env: CHILD_ENV,
    },
  );
  if (result.status !== 0) return undefined;
  if (format === 'json') {
    try {
      return JSON.parse(result.stdout);
    } catch {
      throw new Error(`could not parse ${keyPath} plist value.`);
    }
  }
  return result.stdout.trim();
}

function expectedIosReleaseMetadata() {
  const metadata = readIosReleaseMetadata(
    readFileSync(join(ROOT, 'apps/game/project.godot'), 'utf8'),
    readFileSync(join(ROOT, 'apps/game/export_presets.cfg'), 'utf8'),
  );
  assertIosReleaseMetadata(metadata, {
    expectedBundleId: BUNDLE,
    expectedTeamId: TEAM,
  });
  return metadata;
}

function iosReleaseInputPaths() {
  return IOS_RELEASE_BUILD_CHAIN_INPUTS.map((path) => join(ROOT, path));
}

function archivedAppPath() {
  return join(
    ARCHIVE,
    'Products/Applications',
    `${SCHEME}.app`,
  );
}

function verifyDistributionArchiveUnlocked() {
  if (!existsSync(ARCHIVE_INFO)) {
    throw new Error(
      `App Store archive is missing. Run first: pnpm ios:archive`,
    );
  }
  const expected = expectedIosReleaseMetadata();
  const archiveProperties = readPlistJson(
    ARCHIVE_INFO,
    'xcarchive ApplicationProperties',
    'ApplicationProperties',
  );
  assertArchiveMetadata(archiveProperties, expected);
  assertArtifactFresh({
    artifactPath: ARCHIVE_INFO,
    excludePaths: iosReleaseExcludedPaths(ROOT),
    inputPaths: iosReleaseInputPaths(),
  });
  const app = archivedAppPath();
  if (!existsSync(app)) {
    throw new Error(`archive has no app: ${app}`);
  }
  // The xcarchive itself may be signed with Apple Development. Strictly
  // confirm App Store distribution signing separately on the IPA from exportArchive.
  verifyIosApp(app, 'App Store archive verification', 'AppIcon');
  console.log(
    `xcarchive freshness · arm64 · bundle ${expected.bundleId} · `
    + `version ${expected.shortVersion} (${expected.buildVersion}) checks passed`,
  );
  return expected;
}

function verifyDistributionArchive() {
  return runWithStableReleaseSources({
    alreadyLocked: ownsIapIosLock,
    acquire: acquireIapIosLock,
    execute: verifyDistributionArchiveUnlocked,
    release: unstageIapIos,
  });
}

function readCodeSigningEntitlements(app, scratch) {
  const result = run(
    'codesign',
    ['-d', '--entitlements', ':-', app],
    {
      captureOutput: true,
      printCapturedOutput: false,
    },
  );
  const plist = join(scratch, 'codesign-entitlements.plist');
  writeFileSync(plist, result.stdout, { mode: 0o600 });
  return readPlistJson(plist, 'code signing entitlement');
}

function readPlistDataArray(plist, keyPath, label) {
  const result = run(
    'plutil',
    ['-extract', keyPath, 'xml1', '-o', '-', plist],
    {
      captureOutput: true,
      printCapturedOutput: false,
    },
  );
  return extractPlistDataValues(result.stdout, label);
}

function readProvisioningProfile(app, scratch) {
  const profile = join(app, 'embedded.mobileprovision');
  if (!existsSync(profile)) {
    throw new Error('IPA has no embedded.mobileprovision.');
  }
  const result = run(
    'security',
    ['cms', '-D', '-i', profile],
    {
      captureOutput: true,
      printCapturedOutput: false,
    },
  );
  const plist = join(scratch, 'distribution-profile.plist');
  writeFileSync(plist, result.stdout, { mode: 0o600 });
  const expirationDate = readOptionalPlistValue(
    plist,
    'ExpirationDate',
    'raw',
  );
  const entitlements = readOptionalPlistValue(
    plist,
    'Entitlements',
    'json',
  );
  if (!expirationDate || !entitlements) {
    throw new Error('could not read required distribution provisioning profile values.');
  }
  return {
    DeveloperCertificates: readPlistDataArray(
      plist,
      'DeveloperCertificates',
      'distribution provisioning profile',
    ),
    ExpirationDate: expirationDate,
    Entitlements: entitlements,
    ProvisionsAllDevices: readOptionalPlistValue(
      plist,
      'ProvisionsAllDevices',
      'raw',
    ) === 'true',
    ProvisionedDevices: readOptionalPlistValue(
      plist,
      'ProvisionedDevices',
      'json',
    ),
  };
}

function readCodeSigningCertificate(app, scratch) {
  const prefix = join(scratch, 'signing-certificate-');
  run(
    'codesign',
    codeSigningCertificateArguments(prefix, app),
    {
      captureOutput: true,
      printCapturedOutput: false,
    },
  );
  const certificate = `${prefix}0`;
  if (!existsSync(certificate)) {
    throw new Error('could not extract the IPA signer certificate.');
  }
  return readFileSync(certificate);
}

function extractedAppPath(scratch) {
  const listing = run(
    'unzip',
    ['-Z1', APP_STORE_IPA],
    {
      captureOutput: true,
      printCapturedOutput: false,
    },
  ).stdout;
  const appRoot = assertSafeIpaEntries(listing);
  run('ditto', ['-x', '-k', APP_STORE_IPA, scratch]);
  const app = join(scratch, ...appRoot.split('/'));
  if (!existsSync(app)) {
    throw new Error(`could not find the app bundle in the IPA: ${appRoot}`);
  }
  return app;
}

function verifyAppStoreIpa() {
  const expected = verifyDistributionArchive();
  assertArtifactNotOlderThan({
    artifactPath: APP_STORE_IPA,
    prerequisitePath: ARCHIVE_INFO,
  });

  const scratch = mkdtempSync(join(tmpdir(), 'moonlit-app-store-ipa-'));
  try {
    const app = extractedAppPath(scratch);
    verifyIosApp(app, 'App Store IPA verification', 'AppIcon');
    assertMatchingReleasePayload(
      join(archivedAppPath(), `${SCHEME}.pck`),
      join(app, `${SCHEME}.pck`),
    );
    assertIpaMetadata(
      readPlistJson(join(app, 'Info.plist'), 'IPA Info'),
      expected,
    );

    const signature = run(
      'codesign',
      ['-dv', '--verbose=4', app],
      {
        captureOutput: true,
        printCapturedOutput: false,
      },
    );
    assertDistributionSignatureDetails(
      `${signature.stdout ?? ''}\n${signature.stderr ?? ''}`,
      expected,
    );
    assertDistributionEntitlements(
      readCodeSigningEntitlements(app, scratch),
      expected,
    );
    const profile = readProvisioningProfile(app, scratch);
    assertDistributionProfile(profile, expected);
    const signingCertificate = readCodeSigningCertificate(app, scratch);
    assertSigningCertificateValid(signingCertificate);
    assertProfileContainsSigningCertificate(profile, signingCertificate);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }

  console.log(
    `App Store IPA: ${APP_STORE_IPA}`,
  );
  console.log(
    `distribution signing · provisioning profile · entitlement · bundle/version `
    + `${expected.shortVersion} (${expected.buildVersion}) checks passed`,
  );
  return expected;
}

function doExportAppStore() {
  // After taking the workflow lock, discard any previous IPA first. Even if
  // archive or credential checks fail, an old success must not look like this export.
  rmSync(APP_STORE_EXPORT_DIR, { recursive: true, force: true });
  let exportComplete = false;
  try {
    const expected = verifyDistributionArchive();
    const credentials = readAppStoreCredentials({
      env: process.env,
      root: ROOT,
    });
    mkdirSync(APP_STORE_EXPORT_DIR, { recursive: true });
    writeFileSync(
      APP_STORE_EXPORT_OPTIONS,
      appStoreExportOptionsPlist(expected),
      { encoding: 'utf8', mode: 0o600 },
    );
    run('xcodebuild', [
      '-exportArchive',
      '-archivePath', ARCHIVE,
      '-exportPath', APP_STORE_EXPORT_DIR,
      '-exportOptionsPlist', APP_STORE_EXPORT_OPTIONS,
      '-allowProvisioningUpdates',
      ...xcodebuildAuthenticationArguments(credentials),
    ], {
      captureOutput: true,
      isolatedProcessGroup: true,
      sensitiveValues: Object.values(credentials),
      timeout: APP_STORE_EXPORT_TIMEOUT_MS,
      killSignal: 'SIGTERM',
    });
    if (!existsSync(APP_STORE_IPA)) {
      const ipaNames = readdirSync(APP_STORE_EXPORT_DIR)
        .filter((name) => name.endsWith('.ipa'));
      throw new Error(
        `App Store IPA name differs from expectation: `
        + `${ipaNames.join(', ') || 'no IPA'}`,
      );
    }
    verifyAppStoreIpa();
    exportComplete = true;
  } finally {
    if (!exportComplete) {
      rmSync(APP_STORE_EXPORT_DIR, { recursive: true, force: true });
    }
  }
}

function doAppStoreOperation(operation, parsedCommand) {
  const { dryRun } = parsedCommand;
  const expected = verifyAppStoreIpa();
  const credentials = readAppStoreCredentials({
    env: process.env,
    root: ROOT,
  });
  if (dryRun) {
    console.log(
      `App Store ${operation} dry-run complete: no network transfer · `
      + `${expected.shortVersion} (${expected.buildVersion})`,
    );
    return;
  }

  run(
    'xcrun',
    appStoreAltoolArguments(operation, APP_STORE_IPA, credentials),
    {
      captureOutput: true,
      sensitiveValues: Object.values(credentials),
      timeout: APP_STORE_OPERATION_TIMEOUT_MS,
      killSignal: 'SIGTERM',
    },
  );
  console.log(
    operation === 'validate'
      ? 'App Store Connect remote Validate passed.'
      : 'TestFlight upload request finished. Check processing status in App Store Connect.',
  );
}

function doArchive() {
  mkdirSync(dirname(ARCHIVE), { recursive: true });
  rmSync(ARCHIVE, { recursive: true, force: true });
  doExport(true);
  let archiveComplete = false;
  try {
    run('xcodebuild', [
      '-project', PROJ,
      '-scheme', SCHEME,
      '-configuration', 'Release',
      '-destination', 'generic/platform=iOS',
      '-derivedDataPath', ARCHIVE_DD,
      '-archivePath', ARCHIVE,
      `DEVELOPMENT_TEAM=${TEAM}`,
      'CODE_SIGN_STYLE=Automatic',
      '-allowProvisioningUpdates',
      'archive',
    ], {
      isolatedProcessGroup: true,
      timeout: 15 * 60 * 1000,
      killSignal: 'SIGTERM',
    });
    const archivedApp = archivedAppPath();
    if (!existsSync(archivedApp)) {
      throw new Error(`archive has no app: ${archivedApp}`);
    }
    verifyDistributionArchive();
    archiveComplete = true;
  } finally {
    if (!archiveComplete) rmSync(ARCHIVE, { recursive: true, force: true });
  }
  console.log(`App Store Release archive: ${ARCHIVE}`);
  console.log('Next step: pnpm ios:export-appstore');
}

// Pick one actually attached device from the devicectl list.
function firstDevice() {
  const r = spawnSync('xcrun', ['devicectl', 'list', 'devices'], {
    encoding: 'utf8',
    env: CHILD_ENV,
    timeout: DEVICE_DISCOVERY_TIMEOUT_MS,
    killSignal: 'SIGTERM',
  });
  if (r.error?.code === 'ETIMEDOUT') {
    console.warn('CoreDevice device discovery did not respond; checking the USB path.');
    return null;
  }
  const line = (r.stdout ?? '')
    .split('\n')
    .find((l) => /\bavailable\b/.test(l) && !/unavailable/.test(l));
  if (!line) return null;
  const m = line.match(/([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})/i);
  return m ? m[1] : null;
}

const [rawCommand, ...rawCommandArgs] = process.argv.slice(2);
let parsedCommand;

function executeIosCommand() {
  switch (parsedCommand.command) {
    case 'devices':
      try {
        run(
          'xcrun',
          ['devicectl', 'list', 'devices'],
          {
            timeout: DEVICE_DISCOVERY_TIMEOUT_MS,
            killSignal: 'SIGTERM',
          },
        );
      } catch (error) {
        const usbDevice = firstUsbMuxDevice();
        if (!usbDevice) throw error;
        console.log(`USB iOS device: ${usbDevice}`);
      }
      break;

    case 'export':
      doExport();
      break;

    case 'build':
      console.log(`iOS Debug app: ${doBuild(parsedCommand.deviceId)}`);
      break;

    case 'capture-build': {
      // Capture evidence must not let another iOS workflow change the generated
      // Xcode project between export and build. Finish both steps under this
      // command's exclusive lock; the caller installs separately from the preservation ZIP.
      doExport();
      console.log(`iOS capture Debug app: ${doBuild(parsedCommand.deviceId)}`);
      break;
    }

    case 'capture-build-isolated': {
      // Xcode Devices handoff captures use a disposable development identity.
      // The freshly exported PCK is unchanged, while the production app and
      // its appDataContainer are never installed over or opened.
      doExport();
      console.log(
        `iOS isolated capture Debug app: ${doBuild(
          parsedCommand.deviceId,
          ISOLATED_CAPTURE_BUNDLE,
        )}`,
      );
      break;
    }

    case 'run': {
      const coreDeviceUdid = parsedCommand.deviceId ?? firstDevice();
      const usbMuxUdid = coreDeviceUdid ? null : firstUsbMuxDevice();
      if (!coreDeviceUdid && !usbMuxUdid) {
        throw new Error(
          'No connected device. Check with `node scripts/ios.mjs devices` and '
          + 'enable Developer Mode on the device.',
        );
      }
      doExport();
      // Try a normal build with AppIcon first. Only when local CoreSimulator
      // runtime Apple library signing is blocked by system policy does doBuild
      // make a no-asset-catalog development artifact in separate DerivedData
      // and then attach legacy icons.
      const app = doBuild();
      verifyDebugIosApp(app, 'immediately before install');
      runIosInstallWithFallback({
        coreDeviceId: coreDeviceUdid,
        usbDeviceId: usbMuxUdid,
        discoverUsbDevice: firstUsbMuxDevice,
        installCoreDevice: (udid) => installAndLaunchWithDevicectl(udid, app),
        installUsbDevice: (udid) => installAndLaunchWithUsbMux(udid, app),
        onFallback: () => console.warn(
          'CoreDevice install failed; switching to USB install that preserves saves.',
        ),
      });
      break;
    }

    case 'archive':
      doArchive();
      break;

    case 'export-appstore':
      doExportAppStore();
      break;

    case 'validate':
      doAppStoreOperation('validate', parsedCommand);
      break;

    case 'upload':
      doAppStoreOperation('upload', parsedCommand);
      break;

    default:
      throw new Error(`unrecognized iOS command: ${parsedCommand.command}`);
  }
}

try {
  // Reject bad arguments before taking locks or deleting artifacts.
  parsedCommand = parseIosCommandArguments(rawCommand, rawCommandArgs);
  runExclusiveIosWorkflow(parsedCommand.command, {
    acquire: acquireIosWorkflowLock,
    execute: executeIosCommand,
    release: releaseIosWorkflowLock,
  });
} catch (error) {
  console.error(formatIosWorkflowError(error));
  process.exitCode = error.exitCode ?? 1;
}
