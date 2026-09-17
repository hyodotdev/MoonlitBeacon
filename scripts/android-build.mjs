// Install the Gradle Android template if missing, then export an APK or Play AAB.
//
// Play AAB IAP AAR and Maven deps do not go through Godot's built-in exporter.
// Direct-distribution APK uses the same Gradle path so both channels differ by one preset.
// Android = direct distribution without a billing SDK; Android Play = Play AAB with IAP.

import './lib/load-env.mjs';

import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { delimiter, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  cleanupGeneratedIapKitConfigFile,
  cleanupStaleGeneratedIapKitConfig,
  recoverDirectIapKitConfig,
  removeStagedIapKitConfig,
  restoreIapKitConfigAfterDirect,
  stageIapKitConfigForDirect,
  stageIapKitConfigForStore,
} from './lib/iapkit-config.mjs';
import {
  androidReleasePartialPath,
  androidV4SignatureSidecarPath,
  assertAndroidDistributionFeatureContract,
  assertAndroidReleaseMetadata,
  invalidateAndroidBuildOutput,
  parseAndroidBuildFlags,
  publishAndroidBuildOutput,
  publishAndroidReleaseCopy,
  readAndroidReleaseMetadata,
  resolveAndroidApkSignerPath,
  signDebugAndroidBundle,
  verifyAndroidArchiveBillingBoundary,
  verifyAndroidArchiveIapBoundary,
  verifyAndroidArchiveResourceBoundary,
  verifyAndroidLocalizedAppNames,
  verifyAndroidReleaseSigner,
} from './lib/android-build.mjs';
import { ensureGodotAgpCompatibleAndroidx } from './lib/android-gradle-compat.mjs';
import { resolveAndroidReleaseSigning } from './lib/android-release-signing.mjs';
import { runGodotExportPreflight } from './lib/godot-export-preflight.mjs';
import { credentialFreeChildEnvironment } from './lib/release-environment.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const ANDROID_GRADLE_CLEAN_TIMEOUT_MS = 10 * 60 * 1000;
const ANDROID_EXPORT_TIMEOUT_MS = 20 * 60 * 1000;
const templateMarker = join(root, 'apps/game/android/build/.gdignore');
const gradleProject = join(root, 'apps/game/android/build');
const gradleWrapper = join(
  gradleProject,
  process.platform === 'win32' ? 'gradlew.bat' : 'gradlew',
);
const iapKitGradleConfig = join(
  gradleProject,
  'assetPackInstallTime/src/main/assets/iapkit.cfg',
);
const args = process.argv.slice(2);
const { bundle, debug, release } = parseAndroidBuildFlags(args);
const outputName = bundle ? 'MoonlitBeacon.aab' : 'MoonlitBeacon.apk';
const output = join(root, 'builds/android', outputName);
const candidateOutputName = bundle
  ? '.MoonlitBeacon-partial.aab'
  : '.MoonlitBeacon-partial.apk';
const candidateOutput = join(root, 'builds/android', candidateOutputName);
const preset = bundle ? 'Android Play' : 'Android';
const packageName = 'com.crossplatformkorea.moonlitbeacon';
// Play AAB defaults to release; direct APK defaults to debug for the dev loop.
// Formal itch.io APKs also take --release so they go through this script's staging/clean.
const exportMode = release || (bundle && !debug) ? '--export-release' : '--export-debug';
let versionedReleaseOutput = null;
const iapAndroidSource = join(root, 'apps/game/addons/godot-iap/android');
const iapAndroidStage = join(root, 'builds/.godot-iap-android-stage');
const iapPluginConfigSource = join(root, 'apps/game/addons/godot-iap/plugin.cfg');
const iapPluginConfigStage = join(root, 'builds/.godot-iap-plugin.cfg-stage');
const iapIosStage = join(root, 'apps/game/addons/godot-iap/bin');
const iapExtensionCache = join(root, 'apps/game/.godot/extension_list.cfg');
// iOS export copies a temporary framework into the same addon folder. Separate
// per-platform locks would let concurrent exports package each other's staging, so one global lock.
const buildLock = join(root, 'builds/.godot-iap-export.lock');
// Also serialize the short window that recovers a stale main lock. Without this helper lock
// two processes can read the same stale PID and then delete each other's new lock.
const buildLockGuard = join(root, 'builds/.godot-iap-export-acquire.lock');
const releaseSigningSourceEnv = { ...process.env };
let buildEnv = credentialFreeChildEnvironment(releaseSigningSourceEnv);
let godotExportEnv = buildEnv;
// IAPKit keys reach Godot only through a generated res:// config file. App Store Connect
// values that Android export does not need are not inherited by Gradle or child Node
// processes either.
let ownsBuildLock = false;
let ownsBuildLockGuard = false;

// Prefer the JDK 17 registered on macOS. Gradle clean/export must not stall at start if
// the shell Homebrew JAVA_HOME is mid-update or broken.
if (process.platform === 'darwin') {
  const javaHome = spawnSync('/usr/libexec/java_home', ['-v', '17'], {
    encoding: 'utf8',
    env: buildEnv,
    killSignal: 'SIGTERM',
    timeout: 15 * 1000,
  });
  const detected = javaHome.status === 0 ? javaHome.stdout.trim() : '';
  if (detected) {
    buildEnv.JAVA_HOME = detected;
    buildEnv.PATH = `${join(detected, 'bin')}${delimiter}${buildEnv.PATH ?? ''}`;
  }
}

mkdirSync(dirname(output), { recursive: true });

function processIsAlive(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error?.code === 'EPERM';
  }
}

function restoreStagedPlugin() {
  if (existsSync(iapAndroidStage)) {
    if (existsSync(iapAndroidSource)) {
      throw new Error('IAP Android source and staging path both exist');
    }
    renameSync(iapAndroidStage, iapAndroidSource);
  }
  if (existsSync(iapPluginConfigStage)) {
    if (existsSync(iapPluginConfigSource)) {
      throw new Error('IAP plugin.cfg source and staging path both exist');
    }
    renameSync(iapPluginConfigStage, iapPluginConfigSource);
  }
}

function cleanupGradleIapKitConfig() {
  if (!existsSync(iapKitGradleConfig)) return false;
  if (!cleanupGeneratedIapKitConfigFile(iapKitGradleConfig)) {
    throw new Error(
      `Did not auto-delete unknown Gradle IAPKit config: ${iapKitGradleConfig}`,
    );
  }
  return true;
}

function readLockPid(lockPath) {
  try {
    return Number.parseInt(readFileSync(lockPath, 'utf8').trim(), 10);
  } catch {
    return 0;
  }
}

function acquireBuildLockGuard() {
  try {
    writeFileSync(buildLockGuard, `${process.pid}\n`, {
      encoding: 'utf8',
      flag: 'wx',
    });
    ownsBuildLockGuard = true;
  } catch (error) {
    if (error?.code !== 'EEXIST') throw error;
    const ownerPid = readLockPid(buildLockGuard);
    if (processIsAlive(ownerPid)) {
      throw new Error(`Another IAP export is preparing the lock (PID ${ownerPid}).`);
    }
    // Auto-deleting a stale helper lock recreates the same TOCTOU.
    // This file exists only for the few milliseconds spent reading and replacing the
    // main lock, so it remains only after an abnormal exit. Guide to the exact file instead of auto-recovery.
    throw new Error(
      `A leftover IAP lock-prepare file remains. Confirm no export is running, `
      + `then delete ${buildLockGuard}.`,
    );
  }
}

function releaseBuildLockGuard() {
  if (ownsBuildLockGuard) rmSync(buildLockGuard, { force: true });
  ownsBuildLockGuard = false;
}

function acquireBuildLock() {
  mkdirSync(dirname(buildLock), { recursive: true });
  acquireBuildLockGuard();
  let recoveredStaleLock = false;
  try {
    try {
      writeFileSync(buildLock, `${process.pid}\n`, {
        encoding: 'utf8',
        flag: 'wx',
      });
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      const ownerPid = readLockPid(buildLock);
      if (processIsAlive(ownerPid)) {
        throw new Error(`Another IAP export is running (PID ${ownerPid}).`);
      }
      // Every new export takes the helper lock, so this stale-replace window has no competitor.
      rmSync(buildLock, { force: true });
      writeFileSync(buildLock, `${process.pid}\n`, {
        encoding: 'utf8',
        flag: 'wx',
      });
      recoveredStaleLock = true;
    }
    ownsBuildLock = true;
    try {
      // An active export never reaches here, so keep the existing file.
      // Once the lock is held, delete the exact APK/AAB this command owns first so a later
      // stale-staging cleanup failure cannot treat the previous success as this run's output.
      invalidateAndroidBuildOutput(output, ownsBuildLock);
      invalidateAndroidBuildOutput(
        androidV4SignatureSidecarPath(output),
        ownsBuildLock,
      );
      // Godot writes only the candidate and renames after verification. Even a hard kill
      // leaves no partial APK/AAB on the canonical path.
      invalidateAndroidBuildOutput(candidateOutput, ownsBuildLock);
      invalidateAndroidBuildOutput(
        androidV4SignatureSidecarPath(candidateOutput),
        ownsBuildLock,
      );
      // Staging left from before the lock, or from a hard kill, is recovered only by the process that holds the lock.
      restoreStagedPlugin();
      recoverDirectIapKitConfig(root);
      cleanupStaleGeneratedIapKitConfig(root);
      cleanupGradleIapKitConfig();
      if (existsSync(iapIosStage)) {
        rmSync(iapIosStage, { recursive: true, force: true });
      }
      // If iOS unstage is killed right after deleting bin, only cache may remain.
      // Under the shared lock there is no race with a new export, so always regenerate.
      if (existsSync(iapExtensionCache)) rmSync(iapExtensionCache);
    } catch (error) {
      releaseBuildLock();
      throw error;
    }
    if (recoveredStaleLock) {
      console.log('Recovered leftover IAP staging files from an interrupted Android export.');
    }
  } finally {
    releaseBuildLockGuard();
  }
}

function releaseBuildLock() {
  if (ownsBuildLock) rmSync(buildLock, { force: true });
  ownsBuildLock = false;
}

const godotArgs = [
  'scripts/godot.mjs',
  '--headless',
  '--path',
  'apps/game',
];
if (!existsSync(templateMarker)) {
  godotArgs.push('--install-android-build-template');
}
godotArgs.push(
  exportMode,
  preset,
  `../../builds/android/${candidateOutputName}`,
);

let stagedDirectPlugin = false;
let stagedDirectIapKitConfig = false;
let stagedStoreIapKitConfig = false;
let result = { status: 1 };
acquireBuildLock();
try {
  const projectSource = readFileSync(
    join(root, 'apps/game/project.godot'),
    'utf8',
  );
  const projectVersion = projectSource
    .match(/^config\/version="([0-9A-Za-z.-]+)"$/m)?.[1];
  if (release && !bundle) {
    if (!projectVersion) {
      throw new Error('Could not find the project version for the Android release filename.');
    }
    versionedReleaseOutput = join(
      root,
      'builds/android',
      `MoonlitBeacon-${projectVersion}.apk`,
    );
    invalidateAndroidBuildOutput(versionedReleaseOutput, ownsBuildLock);
    invalidateAndroidBuildOutput(
      androidV4SignatureSidecarPath(versionedReleaseOutput),
      ownsBuildLock,
    );
    invalidateAndroidBuildOutput(
      androidReleasePartialPath(versionedReleaseOutput),
      ownsBuildLock,
    );
  }
  const exportPresetsSource = readFileSync(
    join(root, 'apps/game/export_presets.cfg'),
    'utf8',
  );
  assertAndroidDistributionFeatureContract(exportPresetsSource);
  assertAndroidReleaseMetadata(
    readAndroidReleaseMetadata(
      projectSource,
      exportPresetsSource,
    ),
    { expectedPackageName: packageName },
  );
  // Read secrets only after holding the lock and invalidating previous output. A Keychain
  // or keystore lookup failure then cannot treat the previous success as this release.
  if (exportMode === '--export-release') {
    godotExportEnv = {
      ...buildEnv,
      ...resolveAndroidReleaseSigning({
        env: releaseSigningSourceEnv,
        root,
      }),
    };
  }
  runGodotExportPreflight({
    root,
    env: buildEnv,
  });
  if (bundle) {
    stageIapKitConfigForStore(root);
    stagedStoreIapKitConfig = true;
  }
  // Alternating direct APK and Play AAB on the same Gradle template can leave the previous
  // channel's manifest and DEX in incremental output, so clean before every export.
  if (existsSync(templateMarker)) {
    // Play AAB pulls openiap-google:3.5.2 / androidx.core 1.18.0.
    // Godot 4.7.1's template still pins AGP 8.6.1; bump it to 8.9.1.
    ensureGodotAgpCompatibleAndroidx(gradleProject);
  }
  if (existsSync(templateMarker) && existsSync(gradleWrapper)) {
    result = spawnSync(gradleWrapper, ['clean', '--no-daemon'], {
      cwd: gradleProject,
      stdio: 'inherit',
      env: buildEnv,
      killSignal: 'SIGTERM',
      timeout: ANDROID_GRADLE_CLEAN_TIMEOUT_MS,
    });
  }
  if (result.status === 0 || !existsSync(templateMarker) || !existsSync(gradleWrapper)) {
    // Godot 4.7 Gradle export sometimes re-merges metadata from a disabled plugin.
    // Direct APK moves the descriptor/AAR itself out of the project.
    if (!bundle) {
      renameSync(iapAndroidSource, iapAndroidStage);
      stagedDirectPlugin = true;
      renameSync(iapPluginConfigSource, iapPluginConfigStage);
      stagedDirectIapKitConfig = stageIapKitConfigForDirect(root);
    }
    result = spawnSync(process.execPath, godotArgs, {
      cwd: root,
      stdio: 'inherit',
      // Give the release password only to the actual Godot/Gradle export process.
      // Preflight, clean, signature checks, and resource checks use a secret-free buildEnv.
      env: godotExportEnv,
      killSignal: 'SIGTERM',
      timeout: ANDROID_EXPORT_TIMEOUT_MS,
    });
    if (result.status === 0) {
      try {
        if (exportMode === '--export-release') {
          verifyAndroidReleaseSigner(candidateOutput, {
            alias: godotExportEnv.GODOT_ANDROID_KEYSTORE_RELEASE_USER,
            apksignerPath: bundle
              ? undefined
              : resolveAndroidApkSignerPath({ env: buildEnv }),
            archiveType: bundle ? 'aab' : 'apk',
            env: buildEnv,
            keystorePath:
              godotExportEnv.GODOT_ANDROID_KEYSTORE_RELEASE_PATH,
            password:
              godotExportEnv.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD,
          });
        } else if (bundle) {
          if (debug) {
            const debugKeystore = (
              process.env.GODOT_ANDROID_KEYSTORE_DEBUG_PATH ?? ''
            ).trim() || join(homedir(), '.android', 'debug.keystore');
            signDebugAndroidBundle(candidateOutput, {
              env: buildEnv,
              keystorePath: debugKeystore,
            });
          }
        }
        verifyAndroidArchiveResourceBoundary(candidateOutput, {
          env: buildEnv,
        });
        verifyAndroidLocalizedAppNames(candidateOutput, {
          archiveType: bundle ? 'aab' : 'apk',
          env: buildEnv,
        });
        verifyAndroidArchiveIapBoundary(candidateOutput, {
          env: buildEnv,
          store: bundle,
        });
        verifyAndroidArchiveBillingBoundary(candidateOutput, {
          env: buildEnv,
          store: bundle,
        });
        publishAndroidBuildOutput(
          candidateOutput,
          output,
          ownsBuildLock,
        );
        if (versionedReleaseOutput) {
          // The file a person picks for itch.io is made only from bytes that already passed
          // every check. Rename the intermediate so a hard kill cannot present a partial as a release.
          publishAndroidReleaseCopy(
            output,
            versionedReleaseOutput,
            ownsBuildLock,
          );
        }
      } catch (error) {
        result = { status: 1 };
        throw error;
      }
    }
  }
} finally {
  let cleanupError;
  try {
    if (stagedStoreIapKitConfig) removeStagedIapKitConfig(root);
  } catch (error) {
    cleanupError = error;
  }
  try {
    cleanupGradleIapKitConfig();
  } catch (error) {
    cleanupError ??= error;
  }
  try {
    if (stagedDirectIapKitConfig) restoreIapKitConfigAfterDirect(root);
  } catch (error) {
    cleanupError ??= error;
  }
  try {
    if (stagedDirectPlugin) restoreStagedPlugin();
  } catch (error) {
    cleanupError ??= error;
  }
  if (versionedReleaseOutput) {
    try {
      rmSync(androidReleasePartialPath(versionedReleaseOutput), {
        force: true,
      });
    } catch (error) {
      cleanupError ??= error;
    }
  }
  try {
    rmSync(candidateOutput, { force: true });
  } catch (error) {
    cleanupError ??= error;
  }
  try {
    rmSync(androidV4SignatureSidecarPath(candidateOutput), { force: true });
  } catch (error) {
    cleanupError ??= error;
  }
  const removePublishedOutputs = () => {
    try {
      rmSync(output, { force: true });
    } catch (error) {
      cleanupError ??= error;
    }
    try {
      rmSync(androidV4SignatureSidecarPath(output), { force: true });
    } catch (error) {
      cleanupError ??= error;
    }
    if (versionedReleaseOutput) {
      try {
        rmSync(versionedReleaseOutput, { force: true });
      } catch (error) {
        cleanupError ??= error;
      }
      try {
        rmSync(androidV4SignatureSidecarPath(versionedReleaseOutput), {
          force: true,
        });
      } catch (error) {
        cleanupError ??= error;
      }
    }
  };
  if ((result.status ?? 1) !== 0 || cleanupError) {
    // On ordinary failure, discard while still holding the lock so the next export's new output is untouched.
    removePublishedOutputs();
  }
  try {
    releaseBuildLock();
  } catch (error) {
    // A lock-delete failure is also a cleanup failure. Leaving a verified file would leave the
    // caller unsure whether to trust exit code 1 or the leftover release file, so discard both.
    cleanupError ??= error;
    removePublishedOutputs();
  }
  if (cleanupError) throw cleanupError;
}
process.exit(result.status ?? 1);
