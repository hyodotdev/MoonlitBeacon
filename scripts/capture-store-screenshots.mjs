#!/usr/bin/env node

// Capture store originals from real Godot UI on the Pixel_10 AVD across five
// locales.
//
// Coordinates are recorded in the 808x360 internal resolution and scaled to the
// current 2424x1080 screen. After tapping a language button, do not trust screen
// color alone — reread settings.cfg from the debug APK and confirm the saved
// locale. The generator rechecks source hashes and locale proofs in
// capture-report.json, so copying another language's image cannot fill a slot.

import './lib/load-env.mjs';

import { createHash, randomBytes } from 'node:crypto';
import {
  constants,
  copyFileSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  assertCaptureBuildAttestationCurrent,
  assertInstalledCaptureApkCurrent,
  assertMissileCoreCaptureProofs,
  assertMissileCoreCaptureState,
  assertSafeCaptureOutputPath,
  assertStableMissileCoreCaptureState,
  assertStableStoreCaptureState,
  assertStoreCaptureProofs,
  assertStoreCaptureState,
  captureProcessExitCode,
  foregroundSignalsShowPackage,
  launcherWaitOutputShowsExpectedActivity,
  publishCaptureDirectoryAtomically,
} from './lib/capture-run-state.mjs';
import {
  assertAndroidAvdCaptureContract,
  assertPhysicalSafeLayout,
} from './lib/android-tablet-evidence.mjs';
import {
  assertAndroidDirectDistributionRuntimeState,
} from './lib/android-build.mjs';
import {
  assertAndroidPersistentReportEvidence,
  buildAndroidPersistenceAnchor,
  buildAndroidPersistentEvidence,
  captureAndroidPersistentSnapshot,
  decodeAndroidPrivateFileBase64,
  isAndroidPrivateFileMissingBase64Error,
  restoreAndroidPersistentSnapshot,
} from './lib/android-capture-persistence.mjs';
import {
  ANDROID_CAPTURE_SIGNATURE_FILENAME,
  createSignedAndroidCaptureEvidence,
  verifySignedAndroidCaptureEvidence,
} from './lib/android-capture-signing.mjs';
import {
  credentialFreeChildEnvironment,
} from './lib/release-environment.mjs';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PACKAGE = 'com.crossplatformkorea.moonlitbeacon';
const LAUNCHER_COMPONENT = `${PACKAGE}/com.godot.game.GodotAppLauncher`;
const INTERNAL_SIZE = { width: 808, height: 360 };
const SOURCE_SIZE = { width: 2424, height: 1080 };
const SHOT_ROOT = join(REPO_ROOT, 'builds/shots/store-localized');
const REPORT_PATH = join(SHOT_ROOT, 'capture-report.json');
const CAPTURE_WORK_ROOT = join(REPO_ROOT, 'builds/phone-capture-work');
const PARTIAL_ROOT = join(CAPTURE_WORK_ROOT, 'capture-partials');
const CAPTURE_RUN_ID = new Date().toISOString().replace(/[:.]/gu, '-');
const CAPTURE_STAGING_ROOT = join(
  dirname(SHOT_ROOT),
  `.store-localized-staging-${CAPTURE_RUN_ID}`,
);
const APK_PATH = join(REPO_ROOT, 'builds/android/MoonlitBeacon.apk');
const CAPTURE_APK_PATH = join(CAPTURE_WORK_ROOT, 'capture-debug.apk');
const CAPTURE_BUILD_ATTESTATION_PATH = join(
  CAPTURE_WORK_ROOT,
  'capture-build-attestation.json',
);
const CANONICAL_CAPTURE_APK_PATH = join(SHOT_ROOT, 'capture-debug.apk');
const CANONICAL_CAPTURE_BUILD_ATTESTATION_PATH = join(
  SHOT_ROOT,
  'capture-build-attestation.json',
);
const CANONICAL_AVD_CONFIG_PATH = join(SHOT_ROOT, 'avd-config.ini');
const CANONICAL_PERSISTENCE_ANCHOR_PATH = join(
  SHOT_ROOT,
  'persistence-evidence.json',
);
const WORK_PERSISTENCE_ANCHOR_PATH = join(
  CAPTURE_WORK_ROOT,
  'persistence-evidence.json',
);
const CANONICAL_PERSISTENCE_SIGNATURE_PATH = join(
  SHOT_ROOT,
  ANDROID_CAPTURE_SIGNATURE_FILENAME,
);
const WORK_PERSISTENCE_SIGNATURE_PATH = join(
  CAPTURE_WORK_ROOT,
  ANDROID_CAPTURE_SIGNATURE_FILENAME,
);
const SCREENSHOT_CONTRACT_PATH = join(
  REPO_ROOT,
  'notes/release/store-assets/screenshots.json',
);
const CAPTURE_CHILD_ENV = credentialFreeChildEnvironment(process.env);
const MISSILE_CAPTURE_REQUEST_FILE = 'store_capture_missile_core.request';
const MISSILE_CAPTURE_STATE_FILE = 'store_capture_state.json';
const MISSILE_CAPTURE_TEMP_FILE = 'store_capture_state.tmp';
const TITLE_RUNTIME_READY_FILE = 'store_capture_title_runtime.ready';
const TITLE_RUNTIME_READY_PROOF = 'title-ready';
const STORE_CAPTURE_RUNTIME_REQUEST_FILE = 'store_capture_runtime.request.json';
const STORE_CAPTURE_RUNTIME_STATE_FILE = 'store_capture_runtime.state.json';
const STORE_CAPTURE_RUNTIME_TEMP_FILE = 'store_capture_runtime.state.tmp';
const STORE_CAPTURE_BOOT_REQUEST_FILE = 'store_capture_boot.request.json';
const TEST_HERO_REQUEST_FILE = 'test_hero.request';
const HERO_PREVIEW_PATH = 'res://resources/heroes/keeper.tres';
const CLEAN_UI_FILES = Object.freeze({
  title: Object.freeze({
    request: 'store_capture_clean_title.request',
    ready: 'store_capture_clean_title.ready',
    proof: 'title-hidden',
  }),
  combat: Object.freeze({
    request: 'store_capture_clean_combat.request',
    ready: 'store_capture_clean_combat.ready',
    proof: 'combat-hidden',
  }),
});

const LOCALES = [
  { asset: 'en-US', game: 'en', button: [348, 122], heroPath: HERO_PREVIEW_PATH },
  { asset: 'ko-KR', game: 'ko', button: [292, 122], heroPath: HERO_PREVIEW_PATH },
  { asset: 'ja-JP', game: 'ja', button: [404, 122], heroPath: HERO_PREVIEW_PATH },
  { asset: 'zh-Hans', game: 'zh_CN', button: [460, 122], heroPath: HERO_PREVIEW_PATH },
  { asset: 'zh-Hant', game: 'zh_TW', button: [516, 122], heroPath: HERO_PREVIEW_PATH },
];

const EXPECTED_IAP_REVIEW_PRODUCT_IDS = [
  `${PACKAGE}.hero_dancer`,
  `${PACKAGE}.hero_keeper`,
  `${PACKAGE}.hero_knight`,
  `${PACKAGE}.hero_eclipse`,
  `${PACKAGE}.hero_sage`,
  `${PACKAGE}.supporter`,
  `${PACKAGE}.lantern_colors`,
  `${PACKAGE}.continue_coin`,
  `${PACKAGE}.continue_coin_5`,
  `${PACKAGE}.continue_coin_10`,
];

function loadIapReviewContract() {
  const manifest = JSON.parse(readFileSync(SCREENSHOT_CONTRACT_PATH, 'utf8'));
  const products = manifest.iap_review;
  if (!Array.isArray(products)
      || products.length !== EXPECTED_IAP_REVIEW_PRODUCT_IDS.length) {
    fail(`IAP review capture contract must list ${EXPECTED_IAP_REVIEW_PRODUCT_IDS.length} sale SKUs`);
  }
  const ids = products.map((product) => product?.product_id);
  if (JSON.stringify(ids) !== JSON.stringify(EXPECTED_IAP_REVIEW_PRODUCT_IDS)) {
    fail(
      'IAP review capture must include only the 7 non-consumables and 3 coins on sale, in order',
    );
  }
  const outputNames = new Set();
  for (const product of products) {
    if (
      typeof product.output !== 'string'
      || product.output.length === 0
      || product.output.includes('/')
      || product.output.includes('\\')
      || !product.output.endsWith('.png')
      || outputNames.has(product.output)
    ) {
      fail(`IAP review capture filename is invalid: ${product.output}`);
    }
    outputNames.add(product.output);
  }
  return Object.freeze(products.map((product) => Object.freeze({ ...product })));
}

const IAP_REVIEW_PRODUCTS = loadIapReviewContract();

const CAPTURE_INPUTS = [
  'package.json',
  'scripts/capture-store-screenshots.mjs',
  'scripts/android-build.mjs',
  'scripts/godot.mjs',
  'scripts/python.mjs',
  'scripts/lib/android-capture-persistence.mjs',
  'scripts/lib/android-capture-signing.mjs',
  'scripts/lib/android-build.mjs',
  'scripts/lib/android-release-signing.mjs',
  'scripts/lib/android-tablet-evidence.mjs',
  'scripts/lib/capture-run-state.mjs',
  'scripts/lib/godot-export-preflight.mjs',
  'scripts/lib/iapkit-config.mjs',
  'scripts/lib/release-environment.mjs',
  'notes/release/store-assets/screenshots.json',
  'apps/game/tools/build_store_graphics.py',
  'apps/game/export_presets.cfg',
  'apps/game/android/.build_version',
  'apps/game/android/build/build.gradle',
  'apps/game/android/build/config.gradle',
  'apps/game/android/build/gradle.properties',
  'apps/game/android/build/settings.gradle',
  'apps/game/android/build/gradlew',
  'apps/game/android/build/gradle/wrapper/gradle-wrapper.jar',
  'apps/game/android/build/gradle/wrapper/gradle-wrapper.properties',
  'apps/game/android/build/libs/debug/godot-lib.template_debug.aar',
  'apps/game/android/build/res/values/themes.xml',
  'apps/game/android/build/src/debug/AndroidManifest.xml',
  'apps/game/android/build/src/main/AndroidManifest.xml',
  'apps/game/android/build/src/main/java/com/godot/game/GodotApp.java',
  'apps/game/android/build/src/release/AndroidManifest.xml',
  'apps/game/localization/moonlit.csv',
  'apps/game/assets/third_party/fonts/Galmuri11-Multilingual.tres',
  'apps/game/assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres',
  'apps/game/assets/third_party/fonts/NotoSansCJKsc-Regular.otf',
  'apps/game/scenes/menus/title_menu.tscn',
  'apps/game/scenes/gameplay/arena.tscn',
  'apps/game/scenes/ui/hud.tscn',
  'apps/game/scenes/ui/shrine_panel.tscn',
  'apps/game/scenes/ui/hero_preview_panel.tscn',
  'apps/game/scenes/ui/iap_shop_panel.tscn',
  'apps/game/scripts/gameplay/settings.gd',
  'apps/game/scripts/gameplay/arena.gd',
  'apps/game/scripts/dev/store_capture_clean_ui.gd',
  'apps/game/scripts/dev/store_capture_boot.gd',
  'apps/game/scripts/dev/store_capture_probe.gd',
  'apps/game/scripts/dev/test_launcher.gd',
  'apps/game/scripts/dev/arena_tools.gd',
  'apps/game/scripts/ui/hud.gd',
  'apps/game/scripts/ui/title_menu.gd',
  'apps/game/scripts/ui/shrine_panel.gd',
  'apps/game/scripts/ui/hero_preview_panel.gd',
  'apps/game/scripts/ui/iap_shop_panel.gd',
];

const POINTS = {
  settings: [764, 25],
};

function fail(message) {
  throw new Error(message);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: REPO_ROOT,
    encoding: options.binary ? null : 'utf8',
    maxBuffer: 128 * 1024 * 1024,
    stdio: options.inherit ? 'inherit' : 'pipe',
    env: CAPTURE_CHILD_ENV,
    input: options.input,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const stderr = options.binary
      ? Buffer.from(result.stderr ?? '').toString('utf8')
      : String(result.stderr ?? '');
    fail(
      `${command} ${args.join(' ')} failed (exit ${result.status})` +
        (stderr.trim() ? `\n${stderr.trim()}` : ''),
    );
  }
  return result.stdout;
}

function findAndroidSdk() {
  const candidates = [
    process.env.ANDROID_HOME,
    process.env.ANDROID_SDK_ROOT,
    join(homedir(), 'Library/Android/sdk'),
    join(homedir(), 'Android/Sdk'),
  ].filter(Boolean);
  for (const candidate of candidates) {
    const adb = join(candidate, 'platform-tools/adb');
    if (existsSync(adb)) return { sdk: candidate, adb };
  }
  fail('Android SDK/adb was not found');
}

const { adb } = findAndroidSdk();
let serial = '';

function adbRun(args, options = {}) {
  return run(adb, serial ? ['-s', serial, ...args] : args, options);
}

function sleep(milliseconds) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));
}

async function waitForCaptureDeviceOnline(label, timeoutMilliseconds = 30_000) {
  const deadline = Date.now() + timeoutMilliseconds;
  let lastState = 'unknown';
  let reconnectAttempted = false;
  while (Date.now() < deadline) {
    try {
      lastState = String(adbRun(['get-state'])).trim();
    } catch (error) {
      lastState = String(error?.message ?? error).trim();
    }
    if (lastState === 'device') return;
    if (!reconnectAttempted && lastState.includes('offline')) {
      reconnectAttempted = true;
      try {
        // Reconnect only this capture transport; leave other emulators/devices alone.
        run(adb, ['-s', serial, 'reconnect']);
      } catch {
        // The next get-state decides whether recovery actually succeeded.
      }
    }
    await sleep(500);
  }
  fail(`Android device did not return to device state before ${label}: ${lastState}`);
}

function sha256(data) {
  return createHash('sha256').update(data).digest('hex');
}

function fileSha256(path) {
  return sha256(readFileSync(path));
}

function parsedWmSize(raw) {
  const text = String(raw).trim();
  const matches = [...text.matchAll(/(?:Physical|Override) size:\s*(\d+)x(\d+)/gu)];
  const match = matches.at(-1);
  if (!match) fail(`failed to read Pixel physical screen size: ${text}`);
  return { width: Number(match[1]), height: Number(match[2]), raw: text };
}

function parsedWmDensity(raw) {
  const text = String(raw).trim();
  const matches = [...text.matchAll(/(?:Physical|Override) density:\s*(\d+)/gu)];
  const match = matches.at(-1);
  if (!match) fail(`failed to read Pixel physical density: ${text}`);
  return { dpi: Number(match[1]), raw: text };
}

function assertSafeCapturePath(path) {
  let lastError = null;
  for (const captureRoot of [SHOT_ROOT, CAPTURE_WORK_ROOT, CAPTURE_STAGING_ROOT]) {
    try {
      return assertSafeCaptureOutputPath(path, {
        repositoryRoot: REPO_ROOT,
        captureRoot,
      });
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

function temporaryCapturePath(path) {
  return `${path}.tmp-${process.pid}`;
}

function writeCaptureFileAtomic(path, contents) {
  assertSafeCapturePath(path);
  mkdirSync(dirname(path), { recursive: true });
  assertSafeCapturePath(path);
  const temporary = temporaryCapturePath(path);
  assertSafeCapturePath(temporary);
  try {
    writeFileSync(temporary, contents, { flag: 'wx' });
    renameSync(temporary, path);
  } finally {
    rmSync(temporary, { force: true });
  }
}

function copyCaptureFileAtomic(source, path) {
  assertSafeCapturePath(path);
  mkdirSync(dirname(path), { recursive: true });
  assertSafeCapturePath(path);
  const temporary = temporaryCapturePath(path);
  assertSafeCapturePath(temporary);
  try {
    copyFileSync(source, temporary, constants.COPYFILE_EXCL);
    renameSync(temporary, path);
  } finally {
    rmSync(temporary, { force: true });
  }
}

function writeJsonAtomic(path, value) {
  writeCaptureFileAtomic(path, `${JSON.stringify(value, null, 2)}\n`);
}

function canonicalStagingPath(absolutePath) {
  const remainder = relative(SHOT_ROOT, absolutePath);
  if (
    remainder === ''
    || remainder === '..'
    || remainder.startsWith(`..${sep}`)
    || isAbsolute(remainder)
  ) {
    fail(`canonical staging input is outside store-localized: ${absolutePath}`);
  }
  return join(CAPTURE_STAGING_ROOT, remainder);
}

function exchangeCaptureDirectories(first, second) {
  const modulePath = join(
    REPO_ROOT,
    'apps/game/tools/build_store_graphics.py',
  );
  const pythonBridge = [
    'import importlib.util, pathlib, sys',
    'spec = importlib.util.spec_from_file_location("moonlit_store_graphics", sys.argv[1])',
    'module = importlib.util.module_from_spec(spec)',
    'spec.loader.exec_module(module)',
    'module._atomic_exchange_directories(pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]))',
  ].join('; ');
  run(process.execPath, [
    join(REPO_ROOT, 'scripts/python.mjs'),
    '-B',
    '-c',
    pythonBridge,
    modulePath,
    first,
    second,
  ]);
}

function publishFullCaptureGeneration({
  pendingFiles,
  evidence,
  avdConfigBytes,
  persistenceAnchorBytes,
  persistenceSignatureBytes,
}) {
  const expectedRelativeFiles = new Set(evidence.captures.flatMap(
    (captureEntry) => [captureEntry.source, captureEntry.proof_path],
  ));
  const actualRelativeFiles = new Set(pendingFiles.map((pendingFile) =>
    relative(REPO_ROOT, pendingFile.absolute)));
  if (
    evidence.captures.length !== LOCALES.length * 6 + IAP_REVIEW_PRODUCTS.length
    || pendingFiles.length !== expectedRelativeFiles.size
    || JSON.stringify([...actualRelativeFiles].sort())
      !== JSON.stringify([...expectedRelativeFiles].sort())
  ) {
    fail('tried to publish before the full Pixel PNG+proof set was complete');
  }
  if (existsSync(CAPTURE_STAGING_ROOT)) {
    fail(`Pixel canonical staging path already exists: ${CAPTURE_STAGING_ROOT}`);
  }
  if (existsSync(SHOT_ROOT)) {
    const canonicalStat = lstatSync(SHOT_ROOT);
    if (canonicalStat.isSymbolicLink() || !canonicalStat.isDirectory()) {
      fail(`Pixel canonical root is not a regular directory: ${SHOT_ROOT}`);
    }
    assertSafeCapturePath(SHOT_ROOT);
  }
  assertSafeCapturePath(CAPTURE_STAGING_ROOT);
  mkdirSync(dirname(CAPTURE_STAGING_ROOT), { recursive: true });
  mkdirSync(CAPTURE_STAGING_ROOT, { recursive: false });
  let published = false;
  let publicationAttempted = false;
  let stagedReportBytes = null;
  try {
    for (const pendingFile of pendingFiles) {
      const destination = canonicalStagingPath(pendingFile.absolute);
      mkdirSync(dirname(destination), { recursive: true });
      writeFileSync(destination, pendingFile.bytes, { flag: 'wx' });
      if (!readFileSync(destination).equals(pendingFile.bytes)) {
        fail(`Pixel staging bytes differ from the in-memory original: ${destination}`);
      }
    }
    copyFileSync(
      CAPTURE_APK_PATH,
      join(CAPTURE_STAGING_ROOT, 'capture-debug.apk'),
      constants.COPYFILE_EXCL,
    );
    copyFileSync(
      CAPTURE_BUILD_ATTESTATION_PATH,
      join(CAPTURE_STAGING_ROOT, 'capture-build-attestation.json'),
      constants.COPYFILE_EXCL,
    );
    writeFileSync(
      join(CAPTURE_STAGING_ROOT, 'avd-config.ini'),
      avdConfigBytes,
      { flag: 'wx' },
    );
    writeFileSync(
      join(CAPTURE_STAGING_ROOT, 'persistence-evidence.json'),
      persistenceAnchorBytes,
      { flag: 'wx' },
    );
    writeFileSync(
      join(CAPTURE_STAGING_ROOT, ANDROID_CAPTURE_SIGNATURE_FILENAME),
      persistenceSignatureBytes,
      { flag: 'wx' },
    );
    if (
      fileSha256(join(CAPTURE_STAGING_ROOT, 'capture-debug.apk'))
        !== evidence.apk_sha256
      || fileSha256(join(
        CAPTURE_STAGING_ROOT,
        'capture-build-attestation.json',
      )) !== evidence.build_attestation_sha256
      || fileSha256(join(CAPTURE_STAGING_ROOT, 'avd-config.ini'))
        !== evidence.avd_config.source_sha256
      || fileSha256(join(CAPTURE_STAGING_ROOT, 'persistence-evidence.json'))
        !== evidence.persistence_anchor.sha256
      || fileSha256(join(
        CAPTURE_STAGING_ROOT,
        ANDROID_CAPTURE_SIGNATURE_FILENAME,
      )) !== evidence.persistence_signature.sha256
    ) {
      fail('Pixel staging APK, AVD config, or persistence evidence differs from the report');
    }
    verifySignedAndroidCaptureEvidence(evidence, {
      anchorBytes: persistenceAnchorBytes,
      signatureBytes: persistenceSignatureBytes,
    });
    for (const captureEntry of evidence.captures) {
      const image = join(CAPTURE_STAGING_ROOT, relative(SHOT_ROOT, join(
        REPO_ROOT,
        captureEntry.source,
      )));
      const proof = join(CAPTURE_STAGING_ROOT, relative(SHOT_ROOT, join(
        REPO_ROOT,
        captureEntry.proof_path,
      )));
      if (!existsSync(image) || fileSha256(image) !== captureEntry.sha256) {
        fail(`Pixel staging PNG differs from the report: ${captureEntry.source}`);
      }
      const proofValue = JSON.parse(readFileSync(proof, 'utf8'));
      if (
        proofValue.source !== captureEntry.source
        || JSON.stringify(proofValue.state_guard)
          !== JSON.stringify(captureEntry.state_guard ?? null)
        || JSON.stringify(proofValue.capture_guard)
          !== JSON.stringify(captureEntry.capture_guard ?? null)
      ) {
        fail(`Pixel staging state proof differs from the report: ${captureEntry.source}`);
      }
    }
    stagedReportBytes = Buffer.from(`${JSON.stringify(evidence, null, 2)}\n`);
    writeFileSync(
      join(CAPTURE_STAGING_ROOT, 'capture-report.json'),
      stagedReportBytes,
      { flag: 'wx' },
    );
    const isStagedGenerationAt = (root) => {
      const reportPath = join(root, 'capture-report.json');
      return existsSync(reportPath)
        && readFileSync(reportPath).equals(stagedReportBytes);
    };
    publicationAttempted = true;
    publishCaptureDirectoryAtomically({
      stagingRoot: CAPTURE_STAGING_ROOT,
      canonicalRoot: SHOT_ROOT,
      canonicalExists: existsSync(SHOT_ROOT),
      exchangeDirectories: exchangeCaptureDirectories,
      isStagedGenerationAt,
      renameDirectory: renameSync,
      removeOldGeneration: (oldRoot) => rmSync(oldRoot, {
        recursive: true,
        force: false,
      }),
    });
    published = true;
  } finally {
    if (!published && existsSync(CAPTURE_STAGING_ROOT)) {
      // Before publication starts this path can only be the incomplete new
      // staging tree. After an attempted exchange it may instead name the old
      // canonical generation, so remove it only when exact report bytes prove
      // the swap did not happen. Ambiguous states are deliberately retained.
      const canonicalReport = join(SHOT_ROOT, 'capture-report.json');
      const stagingReport = join(CAPTURE_STAGING_ROOT, 'capture-report.json');
      const canonicalHasNew = stagedReportBytes !== null
        && existsSync(canonicalReport)
        && readFileSync(canonicalReport).equals(stagedReportBytes);
      const stagingHasNew = stagedReportBytes !== null
        && existsSync(stagingReport)
        && readFileSync(stagingReport).equals(stagedReportBytes);
      if (!publicationAttempted || (stagingHasNew && !canonicalHasNew)) {
        rmSync(CAPTURE_STAGING_ROOT, { recursive: true, force: true });
      }
    }
  }
  console.log(`capture report: ${relative(REPO_ROOT, REPORT_PATH)}`);
}

function runtimeFingerprint() {
  const gameRoot = join(REPO_ROOT, 'apps/game');
  const excludedRoots = new Set([
    '.godot',
    'android',
    'docs',
    'ios',
    'tests',
    'tools',
  ]);
  const excludedFiles = new Set(['export_presets.cfg', 'iapkit.cfg']);
  const files = [];

  function visit(directory, relativeDirectory = '') {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const relativePath = relativeDirectory
        ? `${relativeDirectory}/${entry.name}`
        : entry.name;
      const root = relativePath.split('/')[0];
      if (excludedRoots.has(root)) continue;
      if (entry.isDirectory()) {
        visit(join(directory, entry.name), relativePath);
      } else if (entry.isFile() && !excludedFiles.has(relativePath)) {
        files.push(relativePath);
      }
    }
  }

  visit(gameRoot);
  files.sort();
  const hash = createHash('sha256');
  for (const path of files) {
    hash.update(path, 'utf8');
    hash.update('\0');
    hash.update(readFileSync(join(gameRoot, path)));
    hash.update('\0');
  }
  return hash.digest('hex');
}

function pngSize(bytes, label) {
  if (
    bytes.length < 24 ||
    !bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
  ) {
    fail(`${label} is not a PNG`);
  }
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
  };
}

function discoverEmulator(requestedSerial = '') {
  if (requestedSerial !== '') {
    if (!/^emulator-[0-9]+$/u.test(requestedSerial)) {
      fail(`capture serial format is invalid: ${requestedSerial}`);
    }
    const state = String(run(adb, ['-s', requestedSerial, 'get-state'])).trim();
    if (state !== 'device') {
      fail(`${requestedSerial} is not an available Android device: ${state}`);
    }
    const avdName = String(
      run(adb, ['-s', requestedSerial, 'emu', 'avd', 'name']),
    ).split('\n')[0].trim();
    if (avdName !== 'Pixel_10') {
      fail(`${requestedSerial} AVD is not Pixel_10: ${avdName}`);
    }
    serial = requestedSerial;
    return;
  }
  const rows = String(run(adb, ['devices'], {}))
    .split('\n')
    .slice(1)
    .map((row) => row.trim().split(/\s+/))
    .filter(([id, state]) => id && state === 'device' && id.startsWith('emulator-'));
  const pixelTenRows = rows.filter(([id]) => {
    const avdName = String(run(adb, ['-s', id, 'emu', 'avd', 'name']))
      .split('\n')[0]
      .trim();
    return avdName === 'Pixel_10';
  });
  if (pixelTenRows.length !== 1) {
    fail(
      'capture requires exactly one Pixel_10 AVD in device state '
      + `(emulators ${rows.length} total, Pixel_10 ${pixelTenRows.length})`,
    );
  }
  serial = pixelTenRows[0][0];
}

function installedApkSha256() {
  const packageRows = String(adbRun(['shell', 'pm', 'path', PACKAGE]))
    .split('\n')
    .map((row) => row.trim())
    .filter(Boolean);
  const baseRow = packageRows.find((row) => row.startsWith('package:') && row.endsWith('/base.apk'));
  if (!baseRow) fail(`installed ${PACKAGE} base.apk path was not found`);
  const remotePath = baseRow.slice('package:'.length);
  const output = String(adbRun(['shell', 'sha256sum', remotePath])).trim();
  const match = output.match(/^([0-9a-f]{64})\s/);
  if (!match) fail('failed to read SHA-256 of the installed base.apk');
  return match[1];
}

function assertInstalledCaptureApk() {
  return assertInstalledCaptureApkCurrent(
    fileSha256(CAPTURE_APK_PATH),
    installedApkSha256(),
  );
}

function foregroundIsGame() {
  const output = String(adbRun(['shell', 'dumpsys', 'window']));
  return foregroundSignalsShowPackage(output, PACKAGE);
}

function internalTap([x, y]) {
  const deviceX = Math.round((x / INTERNAL_SIZE.width) * SOURCE_SIZE.width);
  const deviceY = Math.round((y / INTERNAL_SIZE.height) * SOURCE_SIZE.height);
  adbRun(['shell', 'input', 'tap', String(deviceX), String(deviceY)]);
}

function startGameLauncher() {
  let launched = false;
  let launchOutput = '';
  // GodotApp itself is exported=false, but GodotAppLauncher is the real exported
  // LAUNCHER activity in the manifest. Start it once first so monkey retries do
  // not kill a slow cold start midway.
  try {
    launchOutput = String(adbRun([
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      LAUNCHER_COMPONENT,
    ])).trim();
    // `am start -W` can still exit 0 when the Activity did not start. Direct
    // launch succeeds only when the exact package Activity and Status: ok both
    // appear.
    launched = launcherWaitOutputShowsExpectedActivity(launchOutput, PACKAGE);
  } catch (error) {
    launchOutput = String(error?.message ?? error);
  }
  // Only when an older Android image rejects an explicit exported-launcher start
  // send the package LAUNCHER intent once. Readiness proof decides final success.
  if (!launched) {
    const result = spawnSync(
      adb,
      [
        '-s',
        serial,
        'shell',
        'monkey',
        '-p',
        PACKAGE,
        '-c',
        'android.intent.category.LAUNCHER',
        '1',
      ],
      {
        cwd: REPO_ROOT,
        encoding: 'utf8',
        env: CAPTURE_CHILD_ENV,
        maxBuffer: 4 * 1024 * 1024,
      },
    );
    launchOutput = [
      launchOutput,
      `${result.stdout ?? ''}${result.stderr ?? ''}`.trim(),
    ].filter(Boolean).join('\n');
    launched = result.status === 0;
  }
  if (!launched) {
    fail(`failed to launch the title with the explicit launcher and monkey\n${launchOutput}`);
  }
}

async function restartTitle() {
  adbRun(['shell', 'am', 'force-stop', PACKAGE]);
  clearTitleRuntimeReady();
  clearStoreCaptureRuntimeHandshake();
  clearStoreCaptureBootHandshake();
  startGameLauncher();
  // A cold start that first loads Noto CJK can leave the Godot splash up for more
  // than 3s. PNG byte size swings with background compression alone, so it is not
  // a readiness signal. Require the debug TestLauncher _ready() proof, landscape
  // resolution, and real foreground together, and allow up to 90s only for a slow
  // first run.
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    await sleep(500);
    const ready = readPrivateFile(TITLE_RUNTIME_READY_FILE, true);
    if (
      ready?.toString('utf8').trim() === TITLE_RUNTIME_READY_PROOF
      && foregroundIsGame()
    ) {
      const frame = Buffer.from(
        adbRun(['exec-out', 'screencap', '-p'], { binary: true }),
      );
      const size = pngSize(frame, 'title readiness frame');
      if (size.width !== SOURCE_SIZE.width || size.height !== SOURCE_SIZE.height) {
        continue;
      }
      await sleep(350);
      return;
    }
  }
  fail('did not confirm debug title-ready proof and real title foreground within 90s');
}

async function waitForArena(label, locale) {
  // Art compression or load time does not prove scene identity. Accept only the
  // nonce proof ArenaTools publishes after confirming the current SceneTree arena
  // and player/HUD readiness.
  await waitForStoreCaptureRuntimeState(
    locale,
    { kind: 'arena_ready' },
    `${label} arena readiness`,
  );
}

function readPrivateFile(name, optional = false) {
  if (!/^[a-z0-9._-]+$/u.test(name)) {
    fail(`debug private file name is not safe: ${name}`);
  }
  let lastError = '';
  // adb exec-out can hide a remote cat failure behind host status 0 and mix an
  // error string into stdout. Preserve the remote shell status and move bytes as
  // Base64. Bound-retry only state atomic-replace races; fail closed on real errors.
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const existence = spawnSync(
      adb,
      ['-s', serial, 'shell', 'run-as', PACKAGE, 'test', '-e', `files/${name}`],
      {
        cwd: REPO_ROOT,
        encoding: 'utf8',
        env: CAPTURE_CHILD_ENV,
      },
    );
    const existenceError = String(existence.stderr ?? '').trim();
    if (existence.status === 1 && existenceError === '') {
      if (optional) return null;
      lastError = 'file is missing';
      break;
    }
    if (existence.status !== 0 || existenceError !== '') {
      lastError = existenceError || `test -e status ${existence.status}`;
      break;
    }
    const result = spawnSync(
      adb,
      ['-s', serial, 'shell', 'run-as', PACKAGE, 'base64', `files/${name}`],
      {
        cwd: REPO_ROOT,
        encoding: null,
        env: CAPTURE_CHILD_ENV,
        maxBuffer: 16 * 1024 * 1024,
      },
    );
    const stderr = Buffer.from(result.stderr ?? '').toString('utf8').trim();
    if (result.status === 0 && stderr === '') {
      return decodeAndroidPrivateFileBase64(result.stdout, name);
    }
    if (
      optional
      && result.status === 1
      && isAndroidPrivateFileMissingBase64Error(stderr, name)
    ) {
      // Godot replaces frequently-polled debug state atomically. A file that
      // vanished after the successful test -e is the only read failure that
      // an optional probe may retry or ultimately treat as absent.
      lastError = stderr;
      if (attempt === 2) return null;
      continue;
    }
    lastError = stderr || `base64 status ${result.status}`;
    break;
  }
  fail(
    `failed to read files/${name} from the debug APK. ` +
      'ADB, permission, and I/O failures other than a missing file are not treated as absence.' +
      (lastError ? ` (${lastError})` : ''),
  );
}

function savedLocale() {
  const settingsBytes = readPrivateFile('settings.cfg', true);
  if (settingsBytes === null) return null;
  const settings = settingsBytes.toString('utf8');
  const match = settings.match(/^locale="([^"]+)"$/m);
  if (!match) fail('could not confirm the saved locale from settings.cfg');
  return match[1];
}

function clearMissileCoreCaptureHandshake() {
  adbRun([
    'shell',
    'run-as',
    PACKAGE,
    'rm',
    '-f',
    `files/${MISSILE_CAPTURE_REQUEST_FILE}`,
    `files/${MISSILE_CAPTURE_STATE_FILE}`,
    `files/${MISSILE_CAPTURE_TEMP_FILE}`,
  ]);
}

function clearCleanUiCaptureHandshake() {
  adbRun([
    'shell',
    'run-as',
    PACKAGE,
    'rm',
    '-f',
    ...Object.values(CLEAN_UI_FILES).flatMap(({ request, ready }) => [
      `files/${request}`,
      `files/${ready}`,
    ]),
  ]);
}

function clearTitleRuntimeReady() {
  adbRun([
    'shell',
    'run-as',
    PACKAGE,
    'rm',
    '-f',
    `files/${TITLE_RUNTIME_READY_FILE}`,
  ]);
}

function clearStoreCaptureRuntimeHandshake() {
  adbRun([
    'shell',
    'run-as',
    PACKAGE,
    'rm',
    '-f',
    `files/${STORE_CAPTURE_RUNTIME_REQUEST_FILE}`,
    `files/${STORE_CAPTURE_RUNTIME_STATE_FILE}`,
    `files/${STORE_CAPTURE_RUNTIME_TEMP_FILE}`,
  ]);
}

function clearStoreCaptureBootHandshake() {
  // test_hero.request is an independently armed one-shot debug selector. Its
  // original bytes were snapshotted before this cleanup and are restored after
  // capture; leaving it active here would silently change the first combat hero.
  adbRun([
    'shell',
    'run-as',
    PACKAGE,
    'rm',
    '-f',
    `files/${STORE_CAPTURE_BOOT_REQUEST_FILE}`,
    `files/${TEST_HERO_REQUEST_FILE}`,
  ]);
}

function writePrivateFile(name, contents) {
  if (!/^[a-z0-9._-]+$/u.test(name)) {
    fail(`debug private file name is not safe: ${name}`);
  }
  run(
    adb,
    [
      '-s',
      serial,
      'shell',
      'run-as',
      PACKAGE,
      'tee',
      `files/${name}`,
    ],
    { input: Buffer.isBuffer(contents) ? Buffer.from(contents) : Buffer.from(contents, 'utf8') },
  );
}

function armStoreCaptureBoot(kind) {
  const nonce = randomBytes(32).toString('hex');
  clearStoreCaptureBootHandshake();
  writePrivateFile(
    STORE_CAPTURE_BOOT_REQUEST_FILE,
    `${JSON.stringify({ schema: 1, nonce, kind })}\n`,
  );
  return nonce;
}

async function launchCaptureArena(kind, locale, label, beforeLaunch = null) {
  adbRun(['shell', 'am', 'force-stop', PACKAGE]);
  clearTitleRuntimeReady();
  clearStoreCaptureRuntimeHandshake();
  armStoreCaptureBoot(kind);
  if (beforeLaunch !== null) beforeLaunch();
  startGameLauncher();
  // arena_ready can appear before ArenaTools' deferred boot request. Clearing the
  // file here can open the default Lv1 board depending on device speed, so keep
  // the request until the target scene's first-party proof finishes; the next
  // launch or final cleanup removes it.
  await waitForArena(label, locale);
}

function capturePersistentFilesBeforeFirstLaunch() {
  adbRun(['shell', 'am', 'force-stop', PACKAGE]);
  return captureAndroidPersistentSnapshot(
    (name) => readPrivateFile(name, true),
  );
}

function restorePersistentFiles(original) {
  adbRun(['shell', 'am', 'force-stop', PACKAGE]);
  return restoreAndroidPersistentSnapshot(original, {
    readFile: (name) => readPrivateFile(name, true),
    writeFile: (name, value) => writePrivateFile(name, value),
    removeFile: (name) => adbRun([
      'shell', 'run-as', PACKAGE, 'rm', '-f', `files/${name}`,
    ]),
  });
}

function armStoreCaptureRuntimeState(expected) {
  const nonce = randomBytes(32).toString('hex');
  clearStoreCaptureRuntimeHandshake();
  const request = {
    nonce,
    kind: expected.kind,
    ...(expected.heroPath ? { hero_path: expected.heroPath } : {}),
    ...(expected.productId ? { product_id: expected.productId } : {}),
  };
  writePrivateFile(
    STORE_CAPTURE_RUNTIME_REQUEST_FILE,
    `${JSON.stringify(request)}\n`,
  );
  return nonce;
}

function readStoreCaptureRuntimeState() {
  const bytes = readPrivateFile(STORE_CAPTURE_RUNTIME_STATE_FILE, true);
  if (bytes === null) return null;
  try {
    return JSON.parse(bytes.toString('utf8'));
  } catch {
    return null;
  }
}

async function waitForStoreCaptureRuntimeState(locale, expected, label) {
  const nonce = armStoreCaptureRuntimeState(expected);
  return waitForStoreCaptureRuntimeObservation(locale, expected, label, {
    nonce,
    afterObservation: 0,
  });
}

async function waitForStoreCaptureRuntimeObservation(
  locale,
  expected,
  label,
  { nonce, afterObservation },
) {
  if (
    typeof nonce !== 'string'
    || !/^[0-9a-f]{64}$/u.test(nonce)
    || !Number.isSafeInteger(afterObservation)
    || afterObservation < 0
  ) {
    fail(`${label} observation session bounds are invalid`);
  }
  // A new arena process can spend more than 30s on cold OpenGL/Godot init even on
  // a Metal-accelerated AVD, and the guardian walks three beacons and two terrain
  // transitions through the real state machine. Give only those two paths a
  // generous start budget; success still comes from the first-party state below.
  const timeoutMs = ['arena_ready', 'field_guardian'].includes(expected.kind)
    ? 90_000
    : 30_000;
  const deadline = Date.now() + timeoutMs;
  let lastFailure = null;
  let lastState = null;
  while (Date.now() < deadline) {
    await sleep(40);
    const state = readStoreCaptureRuntimeState();
    if (
      state === null
      || state.nonce !== nonce
      || !Number.isSafeInteger(state.observation)
      || state.observation <= afterObservation
    ) continue;
    lastState = state;
    try {
      if (expected.kind === 'direct_distribution') {
        return assertAndroidDirectDistributionRuntimeState(state);
      }
      return assertStoreCaptureState(state, {
        ...expected,
        gameLocale: locale.game,
      });
    } catch (error) {
      lastFailure = error;
    }
  }
  fail(
    `${label} did not prove real game state within ${timeoutMs / 1_000}s`
      + (lastFailure ? ` (${lastFailure.message})` : '')
      + (lastState ? ` last_state=${JSON.stringify(lastState)}` : ''),
  );
}

async function verifyInstalledDirectDistributionRuntime() {
  const expectedApkSha256 = assertInstalledCaptureApk();
  try {
    await restartTitle();
    const proof = await waitForStoreCaptureRuntimeState(
      LOCALES[0],
      { kind: 'direct_distribution' },
      'direct-distribution Android runtime boundary',
    );
    const installedAfterProbe = assertInstalledCaptureApk();
    if (installedAfterProbe !== expectedApkSha256) {
      fail('installed APK changed during the direct-distribution runtime probe');
    }
    console.log(
      'verified installed direct-distribution runtime: '
        + `${proof.productId}, storefront=false, cached owns=false, title store hidden`,
    );
    return proof;
  } finally {
    clearStoreCaptureRuntimeHandshake();
  }
}

function armCleanUiCapture(kind) {
  const handshake = CLEAN_UI_FILES[kind];
  if (!handshake) fail(`unsupported clean UI capture kind: ${kind}`);
  clearCleanUiCaptureHandshake();
  adbRun([
    'shell',
    'run-as',
    PACKAGE,
    'touch',
    `files/${handshake.request}`,
  ]);
  adbRun([
    'shell',
    'run-as',
    PACKAGE,
    'ls',
    `files/${handshake.request}`,
  ]);
}

async function waitForCleanUiCapture(kind) {
  const handshake = CLEAN_UI_FILES[kind];
  if (!handshake) fail(`unsupported clean UI capture kind: ${kind}`);
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    await sleep(40);
    if (cleanUiCaptureProof(kind) === handshake.proof) {
      // Start screencap only after visible=false lands in a real render frame.
      await sleep(100);
      return handshake.proof;
    }
  }
  fail(`${kind} debug UI did not prove hide completion within 5s`);
}

function cleanUiCaptureProof(kind) {
  const handshake = CLEAN_UI_FILES[kind];
  if (!handshake) fail(`unsupported clean UI capture kind: ${kind}`);
  return readPrivateFile(handshake.ready, true)?.toString('utf8').trim() ?? '';
}

function assertCleanUiCaptureReady(kind, label) {
  const handshake = CLEAN_UI_FILES[kind];
  if (!handshake) fail(`unsupported clean UI capture kind: ${kind}`);
  const actual = cleanUiCaptureProof(kind);
  if (actual !== handshake.proof) {
    fail(`${label}: ${kind} debug UI hide proof was invalidated`);
  }
  return handshake.proof;
}

function armMissileCoreCapture() {
  clearMissileCoreCaptureHandshake();
  adbRun([
    'shell',
    'run-as',
    PACKAGE,
    'touch',
    `files/${MISSILE_CAPTURE_REQUEST_FILE}`,
  ]);
  // Confirm the handshake with the binary reader that distinguishes a 0-byte
  // request from absence.
  const request = readPrivateFile(MISSILE_CAPTURE_REQUEST_FILE, true);
  if (request === null || request.length !== 0) {
    fail('could not confirm the missile-core 0-byte request file');
  }
}

function readMissileCoreCaptureState() {
  const bytes = readPrivateFile(MISSILE_CAPTURE_STATE_FILE, true);
  if (bytes === null) return null;
  try {
    return JSON.parse(bytes.toString('utf8'));
  } catch {
    return null;
  }
}

async function waitForMissileCoreCaptureState(locale) {
  // `arena_ready` is the Arena's first state observation; the boot preset then
  // performs the real hit, deferred core attach, and on-screen checks. Wait long
  // enough for that semantic work on a slow device/AVD without relaxing the
  // structural and visual proofs below.
  const timeoutMs = 30_000;
  const deadline = Date.now() + timeoutMs;
  let lastFailure = null;
  while (Date.now() < deadline) {
    await sleep(40);
    const state = readMissileCoreCaptureState();
    if (state === null) continue;
    try {
      return assertMissileCoreCaptureState(state, {
        gameLocale: locale.game,
      });
    } catch (error) {
      lastFailure = error;
    }
  }
  fail(
    `${locale.asset} did not prove missile-core recovery state within ${timeoutMs / 1_000}s`
      + (lastFailure ? ` (${lastFailure.message})` : ''),
  );
}

async function switchLocale(locale) {
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    await restartTitle();
    internalTap(POINTS.settings);
    await sleep(700);

    const before = savedLocale();
    if (before === locale.game) {
      adbRun(['shell', 'input', 'keyevent', '4']);
      await sleep(650);
      return before;
    }

    // The first run has no settings.cfg. If the system default language already
    // matches the target, tapping the same button early-returns and never writes
    // the file, so route through another language once and back to create a real
    // save proof.
    if (before === null) {
      let primed = false;
      for (const alternate of LOCALES.filter(
        (entry) => entry.game !== locale.game,
      )) {
        internalTap(alternate.button);
        await sleep(550);
        if (savedLocale() === alternate.game) {
          primed = true;
          break;
        }
      }
      if (!primed) continue;
    }

    internalTap(locale.button);
    await sleep(550);
    const actual = savedLocale();
    if (actual === locale.game) {
      adbRun(['shell', 'input', 'keyevent', '4']);
      await sleep(650);
      return actual;
    }
  }
  fail(`${locale.asset} switch failed: expected ${locale.game}, saved ${savedLocale()}`);
}

async function capture(
  relativePath,
  locale,
  kind,
  captures,
  pendingFiles,
  {
    captureGuard = null,
    cleanUiKind = '',
    productId = '',
    stateExpected = null,
  } = {},
) {
  // A different APK of the same package installed mid-automation is invisible to
  // a foreground check alone. Confirm the real base.apk on both sides of the
  // screenshot so the report cannot prove a hash for a binary it did not capture
  // (TOCTOU).
  assertInstalledCaptureApk();
  let stateBefore = null;
  let preparedState = null;
  if (stateExpected !== null) {
    preparedState = await waitForStoreCaptureRuntimeState(
      locale,
      stateExpected,
      `${relativePath} prepare`,
    );
  }
  let guardBefore = null;
  if (captureGuard !== null) {
    const current = readMissileCoreCaptureState();
    if (current === null) {
      fail(`missile-core capture state vanished immediately before ${relativePath}`);
    }
    guardBefore = assertStableMissileCoreCaptureState(
      captureGuard,
      current,
      { gameLocale: locale.game },
    );
  }
  let cleanUiProof = '';
  if (cleanUiKind !== '') {
    // Arming hide before terrain transition/panel open finishes can reuse the
    // previous scene's proof on the new scene. Hide debug UI only after semantic
    // state is ready, then use the next pure runtime observation as the
    // pre-capture baseline.
    armCleanUiCapture(cleanUiKind);
    cleanUiProof = await waitForCleanUiCapture(cleanUiKind);
  }
  // The APK/state checks above are each an ADB round-trip, so leave the
  // foreground check as the last external probe right against the real screencap.
  if (!foregroundIsGame()) {
    fail(`${relativePath} focus is not on the real game immediately before capture`);
  }
  // Keep the same prepared nonce and take the next live observation. From here
  // the probe must not call prepare again, so it cannot restore guardian position
  // or IAP scroll after capture and create a false positive.
  if (preparedState !== null) {
    stateBefore = await waitForStoreCaptureRuntimeObservation(
      locale,
      stateExpected,
      `${relativePath} pure observation before`,
      {
        nonce: preparedState.nonce,
        afterObservation: preparedState.observation,
      },
    );
  }
  if (cleanUiKind !== '') {
    assertCleanUiCaptureReady(cleanUiKind, `${relativePath} before`);
  }
  if (!foregroundIsGame()) {
    fail(`${relativePath} focus left the real game after state/UI observation`);
  }
  const bytes = Buffer.from(adbRun(['exec-out', 'screencap', '-p'], { binary: true }));
  if (cleanUiKind !== '') {
    // If UI reappears in the capture frame, the next process clears ready. Do not
    // let that one frame record a stale proof as proof of the real PNG.
    await sleep(60);
    assertCleanUiCaptureReady(cleanUiKind, `${relativePath} after`);
  }
  if (!foregroundIsGame()) {
    fail(`${relativePath} focus left the real game immediately after capture`);
  }
  assertInstalledCaptureApk();
  let stableState = null;
  if (stateBefore !== null) {
    const stateAfter = await waitForStoreCaptureRuntimeObservation(
      locale,
      stateExpected,
      `${relativePath} pure observation after`,
      {
        nonce: stateBefore.nonce,
        afterObservation: stateBefore.observation,
      },
    );
    stableState = assertStableStoreCaptureState(
      stateBefore,
      stateAfter,
      { ...stateExpected, gameLocale: locale.game },
    );
    clearStoreCaptureRuntimeHandshake();
  }
  let stableGuard = null;
  if (guardBefore !== null) {
    const current = readMissileCoreCaptureState();
    if (current === null) {
      fail(`missile-core capture state vanished immediately after ${relativePath}`);
    }
    stableGuard = assertStableMissileCoreCaptureState(
      guardBefore,
      current,
      { gameLocale: locale.game },
    );
  }
  const size = pngSize(bytes, relativePath);
  if (size.width !== SOURCE_SIZE.width || size.height !== SOURCE_SIZE.height) {
    fail(
      `${relativePath} is ${size.width}x${size.height} ` +
        `(contract ${SOURCE_SIZE.width}x${SOURCE_SIZE.height})`,
    );
  }
  // Combat shots need an arena/guardian proof or a locked missile-core proof, not
  // PNG byte size. More complex art that changes compression must not regress the
  // check.
  if (kind === 'combat' && stableState === null && stableGuard === null) {
    fail(`${relativePath} has no real combat runtime proof`);
  }
  if (stableState === null) {
    fail(`${relativePath} has no runtime proof to compute the physical safe area`);
  }
  const physicalSafeLayout = assertCapturePhysicalSafeLayout({
    width: size.width,
    height: size.height,
    state_guard: stableState,
  });
  const absolute = join(REPO_ROOT, relativePath);
  pendingFiles.push({ absolute, bytes });
  const proofRelativePath = relativePath.replace(/\.png$/u, '.proof.json');
  const captureEntry = {
    source: relativePath,
    proof_path: proofRelativePath,
    asset_locale: locale.asset,
    game_locale: locale.game,
    kind,
    width: size.width,
    height: size.height,
    sha256: sha256(bytes),
    physical_safe_layout: physicalSafeLayout,
    ...(cleanUiProof === '' ? {} : { clean_ui_proof: cleanUiProof }),
    ...(productId === '' ? {} : { product_id: productId }),
    ...(stableState === null ? {} : {
      state_guard: {
        ...stableState,
        asset_locale: locale.asset,
      },
    }),
    ...(stableGuard === null ? {} : {
      capture_guard: {
        ...stableGuard,
        asset_locale: locale.asset,
      },
    }),
  };
  pendingFiles.push({
    absolute: join(REPO_ROOT, proofRelativePath),
    bytes: Buffer.from(`${JSON.stringify({
      schema: 1,
      source: relativePath,
      state_guard: captureEntry.state_guard ?? null,
      capture_guard: captureEntry.capture_guard ?? null,
      physical_safe_layout: captureEntry.physical_safe_layout,
      clean_ui_proof: captureEntry.clean_ui_proof ?? null,
      product_id: captureEntry.product_id ?? null,
    }, null, 2)}\n`, 'utf8'),
  });
  captures.push(captureEntry);
  console.log(`captured ${locale.asset} ${kind}: ${relativePath}`);
}

async function captureWithCleanUi(
  relativePath,
  locale,
  kind,
  captures,
  pendingFiles,
  options = {},
) {
  try {
    await capture(
      relativePath,
      locale,
      kind,
      captures,
      pendingFiles,
      { ...options, cleanUiKind: kind },
    );
  } finally {
    clearCleanUiCaptureHandshake();
  }
}

async function captureLocale(locale, captures, pendingFiles) {
  const actual = await switchLocale(locale);
  if (actual !== locale.game) fail(`${locale.asset} locale proof does not match`);

  const localeRoot = `builds/shots/store-localized/${locale.asset}`;
  await captureWithCleanUi(
    `${localeRoot}/04-title.png`,
    locale,
    'title',
    captures,
    pendingFiles,
    { stateExpected: { kind: 'title', directDistribution: true } },
  );

  await capture(
    `${localeRoot}/05-moonlit-shrine.png`,
    locale,
    'shrine',
    captures,
    pendingFiles,
    { stateExpected: { kind: 'shrine' } },
  );

  await capture(
    `${localeRoot}/06-hero-preview.png`,
    locale,
    'hero-preview',
    captures,
    pendingFiles,
    {
      stateExpected: {
        kind: 'hero_preview',
        heroPath: HERO_PREVIEW_PATH,
      },
    },
  );

  if (savedLocale() !== locale.game) {
    fail(`${locale.asset} saved locale changed before entering combat`);
  }
  await launchCaptureArena(
    'moonlight_barrage', locale, `${locale.asset} moonlight barrage`,
  );
  await sleep(2400);
  await captureWithCleanUi(
    `${localeRoot}/01-moonlight-barrage.png`,
    locale,
    'combat',
    captures,
    pendingFiles,
    { stateExpected: { kind: 'moonlight_barrage' } },
  );

  // Shoot core detach on a separate cycle-1 board. Reusing the same cycle-3 camp
  // as 01 makes all six store shots look like one map. Cycle 1 starts in forest
  // night, so one frame proves the missile growth/hit loop and terrain variety.
  if (savedLocale() !== locale.game) {
    fail(`${locale.asset} saved locale changed before entering core detach`);
  }
  try {
    await launchCaptureArena(
      'missile_core',
      locale,
      `${locale.asset} core drop`,
      armMissileCoreCapture,
    );
    const readyState = await waitForMissileCoreCaptureState(locale);
    await captureWithCleanUi(
      `${localeRoot}/03-missile-core-drop.png`,
      locale,
      'combat',
      captures,
      pendingFiles,
      {
        captureGuard: readyState,
        stateExpected: { kind: 'arena_ready' },
      },
    );
  } finally {
    clearMissileCoreCaptureHandshake();
  }

  // The guardian re-enters cycle 3 and walks the real three-beacon transition
  // state machine. That path produces open field daytime, distinct from
  // 01=camp/night and 03=forest/night.
  if (savedLocale() !== locale.game) {
    fail(`${locale.asset} saved locale changed before entering the guardian`);
  }
  await launchCaptureArena(
    'field_guardian', locale, `${locale.asset} field guardian`,
  );
  // Do not guess terrain-transition time with a fixed sleep. Prepare clean UI
  // immediately, then wait for field_guardian first-party state so
  // debug_prepare_store_capture() can place the body on screen and prove it from
  // the real spawn frame. Even on a slow device, do not burn boss lifetime on the
  // wait itself.
  await captureWithCleanUi(
    `${localeRoot}/02-field-guardian.png`,
    locale,
    'combat',
    captures,
    pendingFiles,
    { stateExpected: { kind: 'field_guardian' } },
  );
}

async function captureIapReviews(captures, pendingFiles) {
  const locale = LOCALES.find((entry) => entry.game === 'ko');
  if (!locale) fail('Korean capture locale definition is missing');
  await switchLocale(locale);
  for (const product of IAP_REVIEW_PRODUCTS) {
    // The debug probe centers the card for the real product ID and publishes the
    // nonce proof only when the full card, product name, portrait/art, buy, and
    // restore buttons are all visible.
    await capture(
      `builds/shots/store-localized/ko-KR/iap-review/${product.output}`,
      locale,
      'iap-review',
      captures,
      pendingFiles,
      {
        productId: product.product_id,
        stateExpected: {
          kind: 'iap_review',
          productId: product.product_id,
        },
      },
    );
  }
}

function inputFingerprints() {
  const fingerprints = {};
  for (const input of CAPTURE_INPUTS) {
    const absolute = join(REPO_ROOT, input);
    if (!existsSync(absolute)) fail(`capture input file is missing: ${input}`);
    fingerprints[input] = fileSha256(absolute);
  }
  return fingerprints;
}

function currentCaptureBuildState(apkPath) {
  if (!existsSync(apkPath)) fail(`capture APK is missing: ${apkPath}`);
  return {
    apkSha256: fileSha256(apkPath),
    runtimeSha256: runtimeFingerprint(),
    inputSha256: inputFingerprints(),
  };
}

function captureBuildAttestation(state) {
  return {
    schema: 1,
    apk_sha256: state.apkSha256,
    runtime_sha256: state.runtimeSha256,
    input_sha256: state.inputSha256,
  };
}

function readCaptureBuildAttestation() {
  assertSafeCapturePath(CAPTURE_BUILD_ATTESTATION_PATH);
  if (!existsSync(CAPTURE_BUILD_ATTESTATION_PATH)) {
    fail(
      'capture APK build attestation is missing; build once without --skip-build',
    );
  }
  try {
    return JSON.parse(readFileSync(CAPTURE_BUILD_ATTESTATION_PATH, 'utf8'));
  } catch {
    fail('failed to read the capture APK build attestation');
  }
}

function assertCurrentCaptureBuild(apkPath) {
  const attestation = readCaptureBuildAttestation();
  assertCaptureBuildAttestationCurrent(
    attestation,
    currentCaptureBuildState(apkPath),
  );
  return attestation;
}

function captureEvidence(
  captures,
  { verifyInstalled = false, avdEvidence = null } = {},
) {
  if (avdEvidence === null || typeof avdEvidence !== 'object') {
    fail('Pixel_10 AVD hardware/config proof is missing');
  }
  assertPhysicalSafeCaptures(captures);
  const attestation = assertCurrentCaptureBuild(CAPTURE_APK_PATH);
  const installedSha256 = verifyInstalled
    ? assertInstalledCaptureApk()
    : attestation.apk_sha256;
  return {
    schema: 1,
    package: PACKAGE,
    device: serial,
    captured_at: new Date().toISOString(),
    avd_name: 'Pixel_10',
    api_level: 34,
    physical_size: avdEvidence.physical_size,
    density: avdEvidence.density,
    avd_config: avdEvidence.avd_config,
    source_size: SOURCE_SIZE,
    locale_check: true,
    apk_path: relative(REPO_ROOT, CANONICAL_CAPTURE_APK_PATH),
    build_attestation_path: relative(
      REPO_ROOT,
      CANONICAL_CAPTURE_BUILD_ATTESTATION_PATH,
    ),
    build_attestation_sha256: fileSha256(CAPTURE_BUILD_ATTESTATION_PATH),
    build_attestation: attestation,
    apk_sha256: attestation.apk_sha256,
    installed_apk_sha256: installedSha256,
    runtime_sha256: attestation.runtime_sha256,
    input_sha256: attestation.input_sha256,
    canonical_publish_eligible: false,
    canonical_root: relative(REPO_ROOT, SHOT_ROOT),
    publication: 'none',
    captures,
  };
}

function assertCapturePhysicalSafeLayout(captureEntry) {
  const state = captureEntry?.state_guard;
  if (state === null || typeof state !== 'object' || Array.isArray(state)) {
    fail(`${captureEntry?.source ?? 'capture'} is missing a safe-area state_guard`);
  }
  const viewportRect = state.viewport_rect ?? state.screen_rect;
  return assertPhysicalSafeLayout(
    {
      viewport_rect: viewportRect,
      safe_rect: state.safe_rect,
    },
    {
      width: captureEntry.width,
      height: captureEntry.height,
    },
  );
}

function assertPhysicalSafeCaptures(captures) {
  for (const captureEntry of captures) {
    const expected = assertCapturePhysicalSafeLayout(captureEntry);
    if (
      JSON.stringify(captureEntry.physical_safe_layout)
      !== JSON.stringify(expected)
    ) {
      fail(`${captureEntry.source} physical safe-area proof differs from current coordinates`);
    }
  }
}

function assertCompleteCaptures(captures) {
  const expectedCount = LOCALES.length * 6 + IAP_REVIEW_PRODUCTS.length;
  if (captures.length !== expectedCount) {
    fail(`capture count is ${captures.length} (contract ${expectedCount})`);
  }
  const hashes = new Set(captures.map((entry) => entry.sha256));
  if (hashes.size !== captures.length) {
    fail('the same PNG was reused across different scenes or locales');
  }
  assertMissileCoreCaptureProofs(captures, LOCALES);
  assertStoreCaptureProofs(captures, LOCALES, IAP_REVIEW_PRODUCTS);
  assertPhysicalSafeCaptures(captures);
  assertIapReviewCaptures(captures);
  assertCleanUiCaptures(captures);
}

function assertCleanUiCaptures(captures) {
  for (const captureEntry of captures) {
    const handshake = CLEAN_UI_FILES[captureEntry.kind];
    if (handshake) {
      if (captureEntry.clean_ui_proof !== handshake.proof) {
        fail(`${captureEntry.source} is missing debug UI hide proof`);
      }
    } else if (captureEntry.clean_ui_proof !== undefined) {
      fail(`${captureEntry.source} has unexpected clean UI proof`);
    }
  }
}

function assertIapReviewCaptures(captures) {
  const reviews = captures.filter((entry) => entry.kind === 'iap-review');
  if (reviews.length !== IAP_REVIEW_PRODUCTS.length) {
    fail(
      `IAP review capture count is ${reviews.length} `
      + `(contract ${IAP_REVIEW_PRODUCTS.length})`,
    );
  }
  for (const product of IAP_REVIEW_PRODUCTS) {
    const expectedSource =
      `builds/shots/store-localized/ko-KR/iap-review/${product.output}`;
    const matches = reviews.filter((entry) => (
      entry.source === expectedSource
      && entry.product_id === product.product_id
      && entry.asset_locale === 'ko-KR'
      && entry.game_locale === 'ko'
    ));
    if (matches.length !== 1) {
      fail(`${product.product_id} IAP review capture proof is not exactly 1 shot`);
    }
  }
}

function expectedLocaleCaptureSources(locale) {
  const root = `builds/shots/store-localized/${locale.asset}`;
  return [
    `${root}/01-moonlight-barrage.png`,
    `${root}/02-field-guardian.png`,
    `${root}/03-missile-core-drop.png`,
    `${root}/04-title.png`,
    `${root}/05-moonlit-shrine.png`,
    `${root}/06-hero-preview.png`,
  ];
}

function expectedIapCaptureSources() {
  return IAP_REVIEW_PRODUCTS.map(
    (product) => `builds/shots/store-localized/ko-KR/iap-review/${product.output}`,
  );
}

function finalizePartialCaptures() {
  fail(
    'partial capture merging cannot prove one byte-exact restore/AVD generation. '
      + 'capture all 5 locales in one run without --only/--iap-only',
  );
  if (!existsSync(CAPTURE_APK_PATH)) {
    fail('capture-evidence debug APK is missing');
  }
  const expectedEvidence = captureEvidence([]);
  const captures = [];
  let evidenceDevice = '';
  const partials = [
    ...LOCALES.map((locale) => ({
      id: locale.asset,
      path: join(PARTIAL_ROOT, `${locale.asset}.json`),
      count: 6,
      expectedSources: expectedLocaleCaptureSources(locale),
    })),
    {
      id: 'iap-review',
      path: join(PARTIAL_ROOT, 'iap-review.json'),
      count: IAP_REVIEW_PRODUCTS.length,
      expectedSources: expectedIapCaptureSources(),
    },
  ];

  for (const partial of partials) {
    if (!existsSync(partial.path)) {
      fail(`per-locale capture proof is missing: ${relative(REPO_ROOT, partial.path)}`);
    }
    const evidence = JSON.parse(readFileSync(partial.path, 'utf8'));
    if (typeof evidence.device !== 'string' || evidence.device.length === 0) {
      fail(`${partial.id} capture proof has no device identity`);
    }
    if (evidenceDevice === '') {
      evidenceDevice = evidence.device;
    } else if (evidence.device !== evidenceDevice) {
      fail(`${partial.id} capture proof device differs from other locales`);
    }
    for (const key of [
      'schema',
      'package',
      'source_size',
      'locale_check',
      'apk_path',
      'apk_sha256',
      'installed_apk_sha256',
      'runtime_sha256',
      'input_sha256',
    ]) {
      if (
        JSON.stringify(evidence[key]) !==
        JSON.stringify(expectedEvidence[key])
      ) {
        fail(`${partial.id} capture proof ${key} differs from current inputs`);
      }
    }
    if (!Array.isArray(evidence.captures) || evidence.captures.length !== partial.count) {
      fail(`${partial.id} capture proof image count is not ${partial.count}`);
    }
    const expectedSources = new Set(partial.expectedSources);
    const seenSources = new Set();
    for (const captureEntry of evidence.captures) {
      const sourceName = String(captureEntry.source);
      if (!expectedSources.has(sourceName) || seenSources.has(sourceName)) {
        fail(`${partial.id} capture proof source path differs from the contract: ${sourceName}`);
      }
      seenSources.add(sourceName);
      const source = assertSafeCapturePath(resolve(REPO_ROOT, sourceName));
      if (
        !existsSync(source) ||
        fileSha256(source) !== captureEntry.sha256
      ) {
        fail(`${partial.id} source image and capture proof hash differ`);
      }
      captures.push(captureEntry);
    }
    if (seenSources.size !== expectedSources.size) {
      fail(`${partial.id} capture proof is missing a contract source`);
    }
  }

  assertCompleteCaptures(captures);
  const report = { ...expectedEvidence, device: evidenceDevice, captures };
  writeJsonAtomic(REPORT_PATH, report);
  console.log(`capture report: ${relative(REPO_ROOT, REPORT_PATH)}`);
}

async function main() {
  const skipBuild = process.argv.includes('--skip-build');
  const freshInstall = process.argv.includes('--fresh');
  const reuseInstall = process.argv.includes('--reuse-install');
  if (freshInstall && reuseInstall) {
    fail('--fresh and --reuse-install cannot be used together');
  }
  const onlyArgument = process.argv.find((arg) => arg.startsWith('--only='));
  const serialArguments = process.argv.filter((arg) => arg.startsWith('--serial='));
  if (serialArguments.length > 1) fail('--serial may be specified only once');
  const serialArgument = serialArguments[0];
  const requestedSerial = serialArgument?.slice('--serial='.length) ?? '';
  const onlyAsset = onlyArgument?.slice('--only='.length) ?? '';
  const iapOnly = process.argv.includes('--iap-only');
  const finalizeOnly = process.argv.includes('--finalize');
  const modeCount = Number(onlyAsset !== '') + Number(iapOnly) + Number(finalizeOnly);
  if (modeCount > 1) {
    fail('--only, --iap-only, and --finalize are mutually exclusive');
  }
  if (modeCount > 0) {
    fail(
      'the canonical Pixel set must atomically publish 5 locales × 6 shots plus IAP '
        + 'proof from one staging tree; partial/merge modes are not supported',
    );
  }
  const onlyLocale =
    onlyAsset === '' ? null : LOCALES.find((locale) => locale.asset === onlyAsset);
  if (onlyAsset !== '' && !onlyLocale) {
    fail(`unsupported capture locale: ${onlyAsset}`);
  }
  const unknown = process.argv
    .slice(2)
    .filter(
      (arg) =>
        arg !== '--skip-build' &&
        arg !== '--fresh' &&
        arg !== '--reuse-install' &&
        arg !== '--iap-only' &&
        arg !== '--finalize' &&
        !arg.startsWith('--only=') &&
        !arg.startsWith('--serial=') &&
        arg !== '--',
    );
  if (unknown.length > 0) fail(`unknown arguments: ${unknown.join(', ')}`);

  run('pnpm', ['check:locale'], { inherit: true });
  if (finalizeOnly) {
    finalizePartialCaptures();
    return;
  }

  discoverEmulator(requestedSerial);
  const apiLevel = Number(String(adbRun([
    'shell', 'getprop', 'ro.build.version.sdk',
  ])).trim());
  const physicalSize = parsedWmSize(adbRun(['shell', 'wm', 'size']));
  const density = parsedWmDensity(adbRun(['shell', 'wm', 'density']));
  const avdConfigSourcePath = join(
    homedir(),
    '.android/avd/Pixel_10.avd/config.ini',
  );
  if (!existsSync(avdConfigSourcePath)) {
    fail(`Pixel_10 config.ini source is missing: ${avdConfigSourcePath}`);
  }
  const avdConfigBytes = readFileSync(avdConfigSourcePath);
  const avdConfigProof = assertAndroidAvdCaptureContract({
    target: 'pixel-phone',
    avdName: 'Pixel_10',
    apiLevel,
    configBytes: avdConfigBytes,
    physicalSize,
    density: density.dpi,
  });
  const avdEvidence = {
    physical_size: physicalSize,
    density,
    avd_config: {
      ...avdConfigProof,
      evidence_path: relative(REPO_ROOT, CANONICAL_AVD_CONFIG_PATH),
    },
  };
  const sourceBeforeBuild = {
    runtimeSha256: runtimeFingerprint(),
    inputSha256: inputFingerprints(),
  };
  if (!skipBuild) {
    assertSafeCapturePath(CAPTURE_BUILD_ATTESTATION_PATH);
    rmSync(CAPTURE_BUILD_ATTESTATION_PATH, { force: true });
    run('pnpm', ['android:build'], { inherit: true });
  }
  if (!existsSync(APK_PATH)) fail(`debug APK is missing: ${APK_PATH}`);
  const sourceAfterBuild = {
    runtimeSha256: runtimeFingerprint(),
    inputSha256: inputFingerprints(),
  };
  if (
    !skipBuild
    && JSON.stringify(sourceBeforeBuild) !== JSON.stringify(sourceAfterBuild)
  ) {
    fail('game runtime or capture inputs changed during the Android capture build');
  }
  if (skipBuild) {
    assertCurrentCaptureBuild(APK_PATH);
  }
  assertSafeCapturePath(CAPTURE_WORK_ROOT);
  mkdirSync(CAPTURE_WORK_ROOT, { recursive: true });
  copyCaptureFileAtomic(APK_PATH, CAPTURE_APK_PATH);
  if (fileSha256(APK_PATH) !== fileSha256(CAPTURE_APK_PATH)) {
    fail('capture-evidence debug APK is not byte-identical to the build APK');
  }
  if (skipBuild) {
    assertCurrentCaptureBuild(CAPTURE_APK_PATH);
  } else {
    const capturedBuildState = currentCaptureBuildState(CAPTURE_APK_PATH);
    if (
      capturedBuildState.runtimeSha256 !== sourceAfterBuild.runtimeSha256
      || JSON.stringify(capturedBuildState.inputSha256)
        !== JSON.stringify(sourceAfterBuild.inputSha256)
    ) {
      fail('game runtime or capture inputs changed while copying the capture APK');
    }
    writeJsonAtomic(
      CAPTURE_BUILD_ATTESTATION_PATH,
      captureBuildAttestation(capturedBuildState),
    );
    assertCurrentCaptureBuild(CAPTURE_APK_PATH);
  }
  // A long Gradle/Godot export can restart the ADB daemon and leave the previously
  // discovered emulator briefly offline. Before install, confirm the same serial
  // is back in real device state.
  await waitForCaptureDeviceOnline('APK install');
  if (freshInstall) {
    const uninstall = spawnSync(adb, ['-s', serial, 'uninstall', PACKAGE], {
      cwd: REPO_ROOT,
      encoding: 'utf8',
      env: CAPTURE_CHILD_ENV,
    });
    if (uninstall.status !== 0 && !String(uninstall.stdout).includes('Unknown package')) {
      fail(`app uninstall for fresh install failed: ${uninstall.stderr || uninstall.stdout}`);
    }
  }
  if (reuseInstall) {
    const expectedApkSha = fileSha256(CAPTURE_APK_PATH);
    const actualApkSha = installedApkSha256();
    if (actualApkSha !== expectedApkSha) {
      fail(
        `installed base.apk (${actualApkSha}) differs from capture-evidence APK (${expectedApkSha})`,
      );
    }
    console.log(`reusing byte-identical installed APK: ${actualApkSha}`);
  } else {
    // Even if a later android:release overwrites the canonical MoonlitBeacon.apk,
    // keep the debug APK evidence that was actually installed and captured on a
    // dedicated path.
    adbRun(['install', '-r', CAPTURE_APK_PATH], { inherit: true });
    const installedSha = installedApkSha256();
    if (installedSha !== fileSha256(CAPTURE_APK_PATH)) {
      fail('installed base.apk differs from the capture-evidence debug APK');
    }
  }

  // install -r does not run the app. The first frame of a direct APK can recover
  // past Play IAP provenance from Vault, so freeze existence and bytes of every
  // production save file before any handshake/launch.
  const persistentBefore = capturePersistentFilesBeforeFirstLaunch();
  const originalSettings = persistentBefore['settings.cfg'];
  const originalLocale = savedLocale();
  const captures = [];
  const pendingFiles = [];
  let pendingEvidence = null;
  let succeeded = false;
  let restorationFailures = 0;
  let persistenceRestore = null;
  let persistenceAnchorBytes = null;
  let persistenceSignatureBytes = null;

  try {
    // A leftover request from a previous aborted run can hide the new title's
    // debug tools at start, so clear handshakes before the first app interaction.
    clearCleanUiCaptureHandshake();
    clearStoreCaptureRuntimeHandshake();
    clearStoreCaptureBootHandshake();
    clearMissileCoreCaptureHandshake();
    await verifyInstalledDirectDistributionRuntime();
    if (
      originalSettings !== null
      && !LOCALES.some((locale) => locale.game === originalLocale)
    ) {
      fail(
        `cannot safely restore the original settings.cfg locale: `
        + `${originalLocale}`,
      );
    }
    const selectedLocales = onlyLocale ? [onlyLocale] : iapOnly ? [] : LOCALES;
    for (const locale of selectedLocales) {
      await captureLocale(locale, captures, pendingFiles);
    }
    if (!onlyLocale) {
      await captureIapReviews(captures, pendingFiles);
    }

    const evidence = captureEvidence(captures, {
      verifyInstalled: true,
      avdEvidence,
    });
    if (onlyLocale) {
      if (captures.length !== 6) {
        fail(`${onlyLocale.asset} capture count is not 6`);
      }
      assertMissileCoreCaptureProofs(captures, [onlyLocale]);
      assertCleanUiCaptures(captures);
      const partialPath = join(PARTIAL_ROOT, `${onlyLocale.asset}.json`);
      pendingEvidence = {
        path: partialPath,
        value: evidence,
        message: `partial evidence: ${relative(REPO_ROOT, partialPath)}`,
      };
    } else if (iapOnly) {
      assertIapReviewCaptures(captures);
      assertCleanUiCaptures(captures);
      const partialPath = join(PARTIAL_ROOT, 'iap-review.json');
      pendingEvidence = {
        path: partialPath,
        value: evidence,
        message: `partial evidence: ${relative(REPO_ROOT, partialPath)}`,
      };
    } else {
      assertCompleteCaptures(captures);
      pendingEvidence = {
        path: REPORT_PATH,
        value: evidence,
        message: `capture report: ${relative(REPO_ROOT, REPORT_PATH)}`,
      };
    }
    succeeded = true;
  } finally {
    try {
      clearCleanUiCaptureHandshake();
    } catch (error) {
      console.error(`clean UI handshake restore failed: ${error.message}`);
      restorationFailures += 1;
    }
    try {
      clearStoreCaptureRuntimeHandshake();
    } catch (error) {
      console.error(`runtime state handshake restore failed: ${error.message}`);
      restorationFailures += 1;
    }
    try {
      clearStoreCaptureBootHandshake();
    } catch (error) {
      console.error(`boot handshake restore failed: ${error.message}`);
      restorationFailures += 1;
    }
    try {
      clearMissileCoreCaptureHandshake();
    } catch (error) {
      console.error(`missile handshake restore failed: ${error.message}`);
      restorationFailures += 1;
    }
    try {
      persistenceRestore = restorePersistentFiles(persistentBefore);
    } catch (error) {
      console.error(`persistent save-data restore failed: ${error.message}`);
      restorationFailures += 1;
    }
  }

  if (pendingEvidence !== null && persistenceRestore !== null) {
    const persistenceEvidence = buildAndroidPersistentEvidence(
      persistentBefore,
      persistenceRestore,
    );
    const persistenceAnchor = buildAndroidPersistenceAnchor(
      persistenceEvidence,
      persistentBefore,
      persistenceRestore,
      {
        captureId: randomBytes(32).toString('hex'),
        path: relative(REPO_ROOT, CANONICAL_PERSISTENCE_ANCHOR_PATH),
      },
    );
    persistenceAnchorBytes = persistenceAnchor.bytes;
    writeCaptureFileAtomic(
      WORK_PERSISTENCE_ANCHOR_PATH,
      persistenceAnchorBytes,
    );
    Object.assign(
      pendingEvidence.value,
      persistenceEvidence,
      { persistence_anchor: persistenceAnchor.anchor },
    );
    if (!onlyLocale && !iapOnly) {
      Object.assign(pendingEvidence.value, {
        canonical_publish_eligible: true,
        publication: 'full-staging-then-atomic-directory-exchange',
      });
    }
    assertAndroidPersistentReportEvidence(pendingEvidence.value, {
      anchorBytes: persistenceAnchorBytes,
    });
    const signedPersistence = createSignedAndroidCaptureEvidence({
      report: pendingEvidence.value,
      anchorBytes: persistenceAnchorBytes,
      outputPath: WORK_PERSISTENCE_SIGNATURE_PATH,
      evidencePath: relative(
        REPO_ROOT,
        CANONICAL_PERSISTENCE_SIGNATURE_PATH,
      ),
      repositoryRoot: REPO_ROOT,
    });
    persistenceSignatureBytes = signedPersistence.signatureBytes;
    pendingEvidence.value.persistence_signature = signedPersistence.descriptor;
    verifySignedAndroidCaptureEvidence(pendingEvidence.value, {
      anchorBytes: persistenceAnchorBytes,
      signatureBytes: persistenceSignatureBytes,
    });
  }

  const exitCode = captureProcessExitCode({
    captureSucceeded: succeeded,
    restorationFailures,
  });
  if (exitCode === 0) {
    if (pendingEvidence === null) fail('no Pixel capture report ready to publish');
    publishFullCaptureGeneration({
      pendingFiles,
      evidence: pendingEvidence.value,
      avdConfigBytes,
      persistenceAnchorBytes,
      persistenceSignatureBytes,
    });
  }
  process.exitCode = exitCode;
}

await main();
