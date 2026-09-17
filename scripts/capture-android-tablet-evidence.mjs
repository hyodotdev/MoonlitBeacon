#!/usr/bin/env node

// Capture first-party Android tablet evidence without reusing Pixel phone PNGs.
//
// The caller creates and boots the requested AVD, then passes its exact serial,
// AVD name and target label. Every run writes to a new timestamped directory so
// an earlier proof is never overwritten or silently accepted as current.

import './lib/load-env.mjs';

import { createHash, randomBytes } from 'node:crypto';
import {
  constants,
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  writeFileSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  assertCaptureBuildAttestationCurrent,
  assertMissileCoreCaptureState,
  assertStableMissileCoreCaptureState,
  assertStableStoreCaptureState,
  assertStoreCaptureState,
  foregroundSignalsShowPackage,
  launcherWaitOutputShowsExpectedActivity,
} from './lib/capture-run-state.mjs';
import {
  assertAndroidAvdCaptureContract,
  assertCompleteTabletCaptureManifest,
  assertPhysicalSafeLayout,
  shouldRetryTabletGuardianColdStall,
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
const CAPTURE_CHILD_ENV = credentialFreeChildEnvironment(process.env);
const DEFAULT_BUILD_APK = join(REPO_ROOT, 'builds/android/MoonlitBeacon.apk');
const PACKAGE = 'com.crossplatformkorea.moonlitbeacon';
const LAUNCHER = `${PACKAGE}/com.godot.game.GodotAppLauncher`;
const HERO_PATH = 'res://resources/heroes/keeper.tres';
const BOOT_REQUEST = 'store_capture_boot.request.json';
const RUNTIME_REQUEST = 'store_capture_runtime.request.json';
const RUNTIME_STATE = 'store_capture_runtime.state.json';
const RUNTIME_TEMP = 'store_capture_runtime.state.tmp';
const MISSILE_REQUEST = 'store_capture_missile_core.request';
const MISSILE_STATE = 'store_capture_state.json';
const MISSILE_TEMP = 'store_capture_state.tmp';
const TITLE_READY = 'store_capture_title_runtime.ready';
const SETTINGS_FILE = 'settings.cfg';
const TEST_HERO_REQUEST = 'test_hero.request';
const LOCALES = Object.freeze([
  Object.freeze({ asset: 'en-US', game: 'en' }),
  Object.freeze({ asset: 'ko-KR', game: 'ko' }),
  Object.freeze({ asset: 'ja-JP', game: 'ja' }),
  Object.freeze({ asset: 'zh-Hans', game: 'zh_CN' }),
  Object.freeze({ asset: 'zh-Hant', game: 'zh_TW' }),
]);
const SCREENSHOTS = Object.freeze({
  barrage: '01-moonlight-barrage.png',
  guardian: '02-field-guardian.png',
  missile: '03-missile-core-drop.png',
  title: '04-title.png',
  shrine: '05-moonlit-shrine.png',
  hero: '06-hero-preview.png',
});
const CLEAN_UI = Object.freeze({
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
const PRIVATE_CAPTURE_FILES = Object.freeze([
  BOOT_REQUEST,
  RUNTIME_REQUEST,
  RUNTIME_STATE,
  RUNTIME_TEMP,
  MISSILE_REQUEST,
  MISSILE_STATE,
  MISSILE_TEMP,
  TITLE_READY,
  // Snapshot/restore owns its original bytes; capture cleanup only disarms it
  // so a stale manual hero-selection probe cannot alter the first battle.
  TEST_HERO_REQUEST,
  ...Object.values(CLEAN_UI).flatMap(({ request, ready }) => [request, ready]),
]);

function fail(message) {
  throw new Error(message);
}

class RuntimeStateTimeoutError extends Error {
  constructor(message, {
    afterObservation,
    lastState,
    sawRejectedState,
    sawStateFile,
  }) {
    super(message);
    this.name = 'RuntimeStateTimeoutError';
    this.afterObservation = afterObservation;
    this.lastState = lastState;
    this.sawRejectedState = sawRejectedState;
    this.sawStateFile = sawStateFile;
  }
}

function parseArguments(argv) {
  if (argv.includes('--help')) return { help: true };
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (key === '--all-locales' || key === '--fresh-build') {
      result[key === '--all-locales' ? 'allLocales' : 'freshBuild'] = true;
      continue;
    }
    if (!key.startsWith('--') || index + 1 >= argv.length) {
      fail(`invalid argument: ${key}`);
    }
    result[key.slice(2)] = argv[index + 1];
    index += 1;
  }
  for (const required of ['serial', 'avd', 'target', 'apk']) {
    if (typeof result[required] !== 'string' || result[required].trim() === '') {
      fail(`--${required} is required`);
    }
  }
  if (!/^emulator-[0-9]+$/u.test(result.serial)) {
    fail(`Android emulator serial format is invalid: ${result.serial}`);
  }
  if (!/^[A-Za-z0-9._-]+$/u.test(result.avd)) {
    fail(`AVD name format is not safe: ${result.avd}`);
  }
  if (!/^(?:seven|ten)-inch-tablet$/u.test(result.target)) {
    fail(`unsupported tablet target: ${result.target}`);
  }
  result.locale ??= 'en-US';
  if (!LOCALES.some(({ asset }) => asset === result.locale)) {
    fail(`unsupported asset locale: ${result.locale}`);
  }
  if (result.allLocales && argv.includes('--locale')) {
    fail('--all-locales and --locale cannot be used together');
  }
  result.apk = resolve(REPO_ROOT, result.apk);
  if (!result.freshBuild && !existsSync(result.apk)) {
    fail(`debug APK is missing: ${result.apk}`);
  }
  if (Boolean(result.freshBuild) === Boolean(result.attestation)) {
    fail('either --fresh-build or --attestation PATH is required');
  }
  if (typeof result.attestation === 'string') {
    result.attestation = resolve(REPO_ROOT, result.attestation);
    if (!existsSync(result.attestation)) {
      fail(`build attestation is missing: ${result.attestation}`);
    }
  }
  return result;
}

const options = parseArguments(process.argv.slice(2));
if (options.help) {
  console.log(
    'usage: capture-android-tablet-evidence.mjs '
      + '--serial emulator-N --avd NAME '
      + '--target seven-inch-tablet|ten-inch-tablet --apk PATH '
      + '(--fresh-build | --attestation PATH) '
      + '[--all-locales | --locale en-US|ko-KR|ja-JP|zh-Hans|zh-Hant]',
  );
  process.exit(0);
}
const sdkRoot = process.env.ANDROID_SDK_ROOT
  || process.env.ANDROID_HOME
  || join(homedir(), 'Library/Android/sdk');
const adbPath = join(sdkRoot, 'platform-tools/adb');
if (!existsSync(adbPath)) fail(`adb not found: ${adbPath}`);

function run(command, args, {
  binary = false,
  input = undefined,
  allowFailure = false,
  inherit = false,
  redactOutput = false,
} = {}) {
  const result = spawnSync(command, args, {
    cwd: REPO_ROOT,
    encoding: binary ? null : 'utf8',
    input,
    maxBuffer: 32 * 1024 * 1024,
    env: CAPTURE_CHILD_ENV,
    stdio: inherit ? 'inherit' : 'pipe',
  });
  if (result.error) throw result.error;
  if (!allowFailure && result.status !== 0) {
    const stdout = Buffer.from(result.stdout ?? '').toString('utf8').trim();
    const stderr = Buffer.from(result.stderr ?? '').toString('utf8').trim();
    fail(
      `${command} ${args.join(' ')} failed (${result.status})`
        + (redactOutput ? '\nomitting sensitive output' : `\n${stderr || stdout}`),
    );
  }
  return result;
}

function adb(args, settings = {}) {
  const result = run(adbPath, ['-s', options.serial, ...args], settings);
  return settings.binary
    ? Buffer.from(result.stdout ?? '')
    : String(result.stdout ?? '').trim();
}

function sleep(milliseconds) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

const SOURCE_INPUT_PATHS = Object.freeze([
  'package.json',
  'scripts/capture-android-tablet-evidence.mjs',
  'scripts/android-build.mjs',
  'scripts/godot.mjs',
  'scripts/lib/android-capture-persistence.mjs',
  'scripts/lib/android-capture-signing.mjs',
  'scripts/lib/android-build.mjs',
  'scripts/lib/android-release-signing.mjs',
  'scripts/lib/android-tablet-evidence.mjs',
  'scripts/lib/capture-run-state.mjs',
  'scripts/lib/godot-export-preflight.mjs',
  'scripts/lib/iapkit-config.mjs',
  'scripts/lib/release-environment.mjs',
  'apps/game/project.godot',
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
  'apps/game/scripts/util/screen.gd',
  'apps/game/scripts/dev/store_capture_boot.gd',
  'apps/game/scripts/dev/store_capture_clean_ui.gd',
  'apps/game/scripts/dev/store_capture_probe.gd',
  'apps/game/scripts/dev/test_launcher.gd',
  'apps/game/scripts/dev/arena_tools.gd',
  'apps/game/scripts/ui/title_menu.gd',
  'apps/game/scripts/ui/shrine_panel.gd',
  'apps/game/scripts/ui/hero_preview_panel.gd',
  'apps/game/scripts/gameplay/arena.gd',
  'apps/game/scripts/gameplay/missile_progression.gd',
  'apps/game/scripts/actors/moon_missile.gd',
]);

function sourceInputSha256() {
  return Object.fromEntries(SOURCE_INPUT_PATHS.map((relativePath) => {
    const path = join(REPO_ROOT, relativePath);
    if (!existsSync(path)) fail(`capture source input is missing: ${relativePath}`);
    return [relativePath, sha256(readFileSync(path))];
  }));
}

function runtimeSha256() {
  const gameRoot = join(REPO_ROOT, 'apps/game');
  const excludedRoots = new Set(['.godot', 'android', 'docs', 'ios', 'tests', 'tools']);
  const excludedFiles = new Set(['export_presets.cfg', 'iapkit.cfg']);
  const files = [];
  function visit(directory, relativeDirectory = '') {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const relativePath = relativeDirectory
        ? `${relativeDirectory}/${entry.name}`
        : entry.name;
      if (excludedRoots.has(relativePath.split('/')[0])) continue;
      if (entry.isDirectory()) visit(join(directory, entry.name), relativePath);
      else if (entry.isFile() && !excludedFiles.has(relativePath)) files.push(relativePath);
    }
  }
  visit(gameRoot);
  files.sort();
  const hash = createHash('sha256');
  for (const relativePath of files) {
    hash.update(relativePath, 'utf8');
    hash.update('\0');
    hash.update(readFileSync(join(gameRoot, relativePath)));
    hash.update('\0');
  }
  return hash.digest('hex');
}

function currentSourceSnapshot() {
  return {
    runtime_sha256: runtimeSha256(),
    source_input_sha256: sourceInputSha256(),
  };
}

function readBuildAttestation(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (error) {
    fail(`failed to read build attestation: ${path} (${error.message})`);
  }
}

function normalizedBuildAttestation(attestation) {
  return {
    schema: 1,
    apk_sha256: attestation.apk_sha256,
    runtime_sha256: attestation.runtime_sha256,
    input_sha256: attestation.input_sha256,
  };
}

function assertBuildAttestationCurrent(attestation, apkPath, source) {
  assertCaptureBuildAttestationCurrent(attestation, {
    apkSha256: sha256(readFileSync(apkPath)),
    runtimeSha256: source.runtime_sha256,
    inputSha256: source.source_input_sha256,
  });
}

function pngSize(bytes) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (bytes.length < 24 || !bytes.subarray(0, 8).equals(signature)) {
    fail('screencap result is not a PNG');
  }
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
  };
}

function captureRect(state, key, { optional = false } = {}) {
  const value = state?.[key];
  if (
    !Array.isArray(value)
    || value.length !== 4
    || value.some((component) => typeof component !== 'number' || !Number.isFinite(component))
  ) {
    fail(`${key} is not a finite [x,y,width,height] Rect`);
  }
  const [x, y, width, height] = value;
  if (!optional && (width <= 0 || height <= 0)) fail(`${key} has no area`);
  if (optional && (width <= 0 || height <= 0)) return null;
  return { x, y, width, height, endX: x + width, endY: y + height };
}

function rectContains(outer, inner, tolerance = 0.5) {
  return inner.x >= outer.x - tolerance
    && inner.y >= outer.y - tolerance
    && inner.endX <= outer.endX + tolerance
    && inner.endY <= outer.endY + tolerance;
}

function assertSafeUiGeometry(state, kind) {
  const viewport = captureRect(state, 'viewport_rect');
  const safe = captureRect(state, 'safe_rect');
  if (!rectContains(viewport, safe)) fail(`${kind} safe_rect is outside the viewport`);
  const logicalInsets = {
    left: safe.x - viewport.x,
    top: safe.y - viewport.y,
    right: viewport.endX - safe.endX,
    bottom: viewport.endY - safe.endY,
  };

  let required;
  if (kind === 'title') {
    required = [
      ['title_rect', 'title_inside_safe_area'],
      ['subtitle_rect', 'subtitle_inside_safe_area'],
      ['version_rect', 'version_inside_safe_area'],
      ['tap_prompt_rect', 'tap_prompt_inside_safe_area'],
      ['settings_button_rect', 'settings_button_inside_safe_area'],
      ['shrine_button_rect', 'shrine_button_inside_safe_area'],
      ['ladder_button_rect', 'ladder_button_inside_safe_area'],
    ];
  } else if (kind === 'shrine') {
    required = [['shrine_frame_rect', 'shrine_frame_inside_safe_area']];
  } else if (kind === 'hero_preview') {
    required = [
      ['shrine_frame_rect', 'shrine_frame_inside_safe_area'],
      ['preview_frame_rect', 'preview_frame_inside_safe_area'],
      ['close_rect', 'close_inside_safe_area'],
    ];
  } else {
    required = [
      ['hud_left_rect', 'hud_left_inside_safe_area'],
      ['hud_right_rect', 'hud_right_inside_safe_area'],
      ['pause_button_rect', 'pause_button_inside_safe_area'],
      ['dash_rect', 'dash_inside_safe_area'],
      ['move_stick_rect', 'move_stick_inside_safe_area'],
      ['boss_rect', 'boss_inside_safe_area'],
      ['banner_rect', 'banner_inside_safe_area'],
    ];
  }
  const controls = {};
  for (const [rectKey, booleanKey] of required) {
    const rect = captureRect(state, rectKey);
    if (state[booleanKey] !== true || !rectContains(safe, rect)) {
      fail(`${kind} ${rectKey} is not inside the actual safe_rect`);
    }
    controls[rectKey] = [rect.x, rect.y, rect.width, rect.height];
  }
  return {
    viewport_rect: [viewport.x, viewport.y, viewport.width, viewport.height],
    safe_rect: [safe.x, safe.y, safe.width, safe.height],
    logical_insets: logicalInsets,
    controls,
  };
}

function privatePath(name) {
  if (!/^[a-z0-9._-]+$/u.test(name)) fail(`unsafe private file name: ${name}`);
  return `files/${name}`;
}

function writePrivate(name, contents) {
  adb(
    ['shell', 'run-as', PACKAGE, 'tee', privatePath(name)],
    {
      input: Buffer.isBuffer(contents) ? contents : Buffer.from(contents, 'utf8'),
      redactOutput: true,
    },
  );
}

function readPrivate(name, optional = false) {
  let lastError = '';
  // adb exec-out can return host exit 0 and an error string on stdout even when
  // remote cat fails. Preserve the remote shell status and move bytes as Base64.
  // Bound-retry only atomic replace races on state files; reject permission, ADB,
  // and I/O errors.
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const existence = run(
      adbPath,
      [
        '-s', options.serial, 'shell', 'run-as', PACKAGE,
        'test', '-e', privatePath(name),
      ],
      { allowFailure: true },
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
    const result = run(
      adbPath,
      ['-s', options.serial, 'shell', 'run-as', PACKAGE, 'base64', privatePath(name)],
      { binary: true, allowFailure: true },
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
      // The runtime proof can be replaced between test -e and base64. Only
      // this exact missing-file race is safe to retry or treat as absent.
      lastError = stderr;
      if (attempt === 2) return null;
      continue;
    }
    lastError = stderr || `base64 status ${result.status}`;
    break;
  }
  fail(
    `failed to read ${privatePath(name)} from the debug APK. `
      + 'ADB, permission, and I/O failures other than a missing file are not treated as absence.'
      + (lastError ? ` (${lastError})` : ''),
  );
}

function readPrivateJson(name) {
  const bytes = readPrivate(name, true);
  if (bytes === null) return null;
  try {
    return JSON.parse(bytes.toString('utf8'));
  } catch {
    return null;
  }
}

function removePrivate(names) {
  adb(['shell', 'run-as', PACKAGE, 'rm', '-f', ...names.map(privatePath)]);
}

function clearCaptureHandshakes() {
  removePrivate(PRIVATE_CAPTURE_FILES);
}

function settingsBytesForLocale(locale) {
  return Buffer.from(
    `[settings]\n\nlocale="${locale.game}"\nmusic=4\nsfx=4\n`,
    'utf8',
  );
}

function setGameLocale(locale) {
  adb(['shell', 'am', 'force-stop', PACKAGE]);
  const expected = settingsBytesForLocale(locale);
  writePrivate(SETTINGS_FILE, expected);
  const actual = readPrivate(SETTINGS_FILE);
  if (!actual.equals(expected)) fail(`${locale.asset} settings.cfg write differs`);
}

function restoreSettings(original) {
  adb(['shell', 'am', 'force-stop', PACKAGE]);
  if (original === null) {
    removePrivate([SETTINGS_FILE]);
    if (readPrivate(SETTINGS_FILE, true) !== null) {
      fail('failed to restore the pre-capture missing settings.cfg state');
    }
    return;
  }
  writePrivate(SETTINGS_FILE, original);
  const restored = readPrivate(SETTINGS_FILE);
  if (!restored.equals(original)) fail('failed to restore pre-capture settings.cfg byte-exactly');
}

function capturePersistentFilesBeforeFirstLaunch() {
  adb(['shell', 'am', 'force-stop', PACKAGE]);
  return captureAndroidPersistentSnapshot(
    (name) => readPrivate(name, true),
  );
}

function restorePersistentFiles(original) {
  adb(['shell', 'am', 'force-stop', PACKAGE]);
  return restoreAndroidPersistentSnapshot(original, {
    readFile: (name) => readPrivate(name, true),
    writeFile: (name, value) => writePrivate(name, value),
    removeFile: (name) => removePrivate([name]),
  });
}

function foregroundOutput() {
  return adb(['shell', 'dumpsys', 'window']);
}

function isForeground() {
  return foregroundSignalsShowPackage(foregroundOutput(), PACKAGE);
}

async function waitFor(predicate, label, timeoutMilliseconds) {
  const deadline = Date.now() + timeoutMilliseconds;
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const value = predicate();
      if (value) return value;
    } catch (error) {
      lastError = error;
    }
    await sleep(100);
  }
  fail(`did not confirm ${label} within ${timeoutMilliseconds / 1000}s${
    lastError ? ` (${lastError.message})` : ''}`);
}

async function waitDeviceOnline(label) {
  await waitFor(() => {
    const result = run(
      adbPath,
      ['-s', options.serial, 'get-state'],
      { allowFailure: true },
    );
    return result.status === 0 && String(result.stdout).trim() === 'device';
  }, `emulator online again before ${label}`, 90_000);
}

async function launch() {
  adb(['shell', 'am', 'force-stop', PACKAGE]);
  const output = adb(['shell', 'am', 'start', '-W', '-n', LAUNCHER]);
  if (!launcherWaitOutputShowsExpectedActivity(output, PACKAGE)) {
    fail(`no exact launcher Activity start proof\n${output}`);
  }
  await waitFor(isForeground, 'game foreground', 90_000);
  await waitFor(() => {
    const bytes = adb(['exec-out', 'screencap', '-p'], { binary: true });
    const size = pngSize(bytes);
    return size.width > size.height ? size : null;
  }, 'landscape game surface', 90_000);
}

function armRuntime(kind, extra = {}) {
  const nonce = randomBytes(32).toString('hex');
  removePrivate([RUNTIME_REQUEST, RUNTIME_STATE, RUNTIME_TEMP]);
  writePrivate(RUNTIME_REQUEST, `${JSON.stringify({ nonce, kind, ...extra })}\n`);
  return nonce;
}

function armBoot(kind, nonce) {
  removePrivate([BOOT_REQUEST]);
  writePrivate(BOOT_REQUEST, `${JSON.stringify({ schema: 1, nonce, kind })}\n`);
}

async function waitRuntimeState(nonce, expected, afterObservation = 0) {
  let lastState = null;
  let lastError = null;
  let sawRejectedState = false;
  let sawStateFile = false;
  // launch() can show foreground and a landscape Surface before the Godot main
  // loop. Wait through intermittent API 36 tablet AVD cold starts until
  // first-party state is ready, while keeping the success and stability checks
  // below unchanged.
  const timeout = 90_000;
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    await sleep(80);
    const bytes = readPrivate(RUNTIME_STATE, true);
    if (bytes === null) continue;
    sawStateFile = true;
    let state;
    try {
      state = JSON.parse(bytes.toString('utf8'));
    } catch {
      sawRejectedState = true;
      continue;
    }
    if (
      state === null
      || typeof state !== 'object'
      || Array.isArray(state)
      || state.nonce !== nonce
      || !Number.isSafeInteger(state.observation)
      || state.observation <= afterObservation
    ) {
      sawRejectedState = true;
      continue;
    }
    lastState = state;
    try {
      const normalized = expected.kind === 'direct_distribution'
        ? assertAndroidDirectDistributionRuntimeState(state)
        : assertStoreCaptureState(state, expected);
      const safeLayout = [
        'title',
        'shrine',
        'hero_preview',
        'arena_ready',
        'moonlight_barrage',
        'field_guardian',
      ]
        .includes(expected.kind)
        ? assertSafeUiGeometry(state, expected.kind)
        : null;
      return {
        raw: state,
        normalized,
        safeLayout,
      };
    } catch (error) {
      lastError = error;
    }
  }
  throw new RuntimeStateTimeoutError(
    `${expected.kind} runtime state was not proven`
      + (lastError ? ` (${lastError.message})` : '')
      + (lastState ? ` last_state=${JSON.stringify(lastState)}` : ''),
    {
      afterObservation,
      lastState,
      sawRejectedState,
      sawStateFile,
    },
  );
}

async function verifyInstalledDirectDistributionRuntime(expectedApkSha256) {
  clearCaptureHandshakes();
  const nonce = armRuntime('direct_distribution');
  try {
    await launch();
    const { normalized } = await waitRuntimeState(
      nonce,
      { kind: 'direct_distribution' },
    );
    const installedAfterProbe = installedApkSha256();
    if (installedAfterProbe !== expectedApkSha256) {
      fail('installed APK changed during the direct-distribution runtime probe');
    }
    console.log(
      'verified installed direct-distribution runtime: '
        + `${normalized.productId}, storefront=false, cached owns=false, title store hidden`,
    );
    return normalized;
  } finally {
    clearCaptureHandshakes();
  }
}

function armCleanUi(kind) {
  const handshake = CLEAN_UI[kind];
  removePrivate([handshake.request, handshake.ready]);
  adb(['shell', 'run-as', PACKAGE, 'touch', privatePath(handshake.request)]);
}

async function waitCleanUi(kind) {
  const handshake = CLEAN_UI[kind];
  return waitFor(() => {
    const proof = readPrivate(handshake.ready, true)?.toString('utf8').trim();
    return proof === handshake.proof ? proof : null;
  }, `${kind} debug UI hidden`, 5_000);
}

function assertCleanUiStillReady(kind, expectedProof) {
  const handshake = CLEAN_UI[kind];
  const proof = readPrivate(handshake.ready, true)?.toString('utf8').trim() ?? '';
  if (proof !== expectedProof) fail(`${kind} debug UI hide proof was invalidated during capture`);
}

function installedApkSha256() {
  const rows = adb(['shell', 'pm', 'path', PACKAGE]).split(/\r?\n/u);
  const base = rows.find((row) => row.startsWith('package:') && row.endsWith('/base.apk'));
  if (!base) fail('installed base.apk path was not found');
  const output = adb(['shell', 'sha256sum', base.slice('package:'.length)]);
  const match = output.match(/^([0-9a-f]{64})\s/u);
  if (!match) fail('failed to read the installed base.apk hash');
  return match[1];
}

const runId = new Date().toISOString().replace(/[:.]/gu, '-');
const outputRoot = join(
  REPO_ROOT,
  'builds/tablet-evidence',
  options.target,
  `${options.avd}-${runId}`,
);
mkdirSync(outputRoot, { recursive: true });
const captures = [];

async function captureRuntime(filename, locale, nonce, expected, cleanKind) {
  const name = filename.replace(/\.png$/u, '');
  const before = await waitRuntimeState(nonce, expected);
  armCleanUi(cleanKind);
  const cleanUiProof = await waitCleanUi(cleanKind);
  if (!isForeground()) fail(`${name} game is not foreground immediately before capture`);
  const installedBefore = installedApkSha256();
  const bytes = adb(['exec-out', 'screencap', '-p'], { binary: true });
  await sleep(60);
  assertCleanUiStillReady(cleanKind, cleanUiProof);
  const after = await waitRuntimeState(nonce, expected, before.raw.observation);
  assertStableStoreCaptureState(before.raw, after.raw, expected);
  const installedAfter = installedApkSha256();
  if (installedBefore !== installedAfter) fail(`${name} installed APK changed during capture`);
  if (!isForeground()) fail(`${name} game is not foreground immediately after capture`);
  const size = pngSize(bytes);
  if (size.width <= size.height) fail(`${name} capture is not landscape`);
  const physicalSafeLayout = assertPhysicalSafeLayout(before.safeLayout, size);
  const localeRoot = join(outputRoot, locale.asset);
  mkdirSync(localeRoot, { recursive: true });
  const path = join(localeRoot, filename);
  writeFileSync(path, bytes, { flag: 'wx' });
  const proofPath = join(localeRoot, `${name}.proof.json`);
  writeFileSync(proofPath, `${JSON.stringify({
    before: before.raw,
    after: after.raw,
    normalized: before.normalized,
  }, null, 2)}\n`, { flag: 'wx' });
  captures.push({
    name,
    filename,
    asset_locale: locale.asset,
    game_locale: locale.game,
    path: path.slice(REPO_ROOT.length + 1),
    proof_path: proofPath.slice(REPO_ROOT.length + 1),
    kind: expected.kind,
    boot_kind: expected.bootKind ?? null,
    runtime_nonce: nonce,
    clean_ui_proof: cleanUiProof,
    width: size.width,
    height: size.height,
    sha256: sha256(bytes),
    installed_apk_sha256: installedAfter,
    runtime_before: before.raw,
    runtime_after: after.raw,
    safe_layout: before.safeLayout,
    physical_safe_layout: physicalSafeLayout,
  });
  removePrivate([
    RUNTIME_REQUEST,
    RUNTIME_STATE,
    RUNTIME_TEMP,
    CLEAN_UI[cleanKind].request,
    CLEAN_UI[cleanKind].ready,
  ]);
}

async function captureMissileCore(filename, locale, bootNonce, runtimeNonce) {
  const name = filename.replace(/\.png$/u, '');
  const runtimeExpected = { kind: 'arena_ready', gameLocale: locale.game };
  let state = null;
  let lastError = null;
  // launch() only proves foreground and a landscape Surface. On a slow AVD the
  // Godot main loop plus the real hit and deferred core attach can take more
  // than 45s. Semantic checks stay with the first-party state below, so only
  // the start budget is generous.
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    await sleep(80);
    const candidate = readPrivateJson(MISSILE_STATE);
    if (candidate === null) continue;
    try {
      assertMissileCoreCaptureState(candidate, { gameLocale: locale.game });
      state = candidate;
      break;
    } catch (error) {
      lastError = error;
    }
  }
  if (state === null) {
    fail(`missile_core state was not proven${
      lastError ? ` (${lastError.message})` : ''}`);
  }
  armCleanUi('combat');
  const cleanUiProof = await waitCleanUi('combat');
  // Use the scene after the real core detach and banner lock as the pre-capture
  // baseline, not the moment arena_ready appears. On a slow tablet that can take
  // several seconds, so comparing the initial HUD with the post-capture HUD
  // would fail on normal level/recovery UI changes.
  const runtimeBefore = await waitRuntimeState(runtimeNonce, runtimeExpected);
  if (!isForeground()) fail('missile_core game is not foreground immediately before capture');
  const installedBefore = installedApkSha256();
  const bytes = adb(['exec-out', 'screencap', '-p'], { binary: true });
  await sleep(100);
  assertCleanUiStillReady('combat', cleanUiProof);
  const after = readPrivateJson(MISSILE_STATE);
  assertStableMissileCoreCaptureState(state, after, { gameLocale: locale.game });
  // Godot proves the in-game locale while the capture harness owns the store
  // asset locale. Bind both pieces of provenance into the exact missile-state
  // objects published in the proof and canonical report.
  const missileBefore = { ...state, asset_locale: locale.asset };
  const missileAfter = { ...after, asset_locale: locale.asset };
  const runtimeAfter = await waitRuntimeState(
    runtimeNonce,
    runtimeExpected,
    runtimeBefore.raw.observation,
  );
  assertStableStoreCaptureState(runtimeBefore.raw, runtimeAfter.raw, runtimeExpected);
  const installedAfter = installedApkSha256();
  if (installedBefore !== installedAfter) fail('missile_core installed APK changed during capture');
  if (!isForeground()) fail('missile_core game is not foreground immediately after capture');
  const size = pngSize(bytes);
  if (size.width <= size.height) fail('missile_core capture is not landscape');
  const physicalSafeLayout = assertPhysicalSafeLayout(runtimeBefore.safeLayout, size);
  const localeRoot = join(outputRoot, locale.asset);
  mkdirSync(localeRoot, { recursive: true });
  const path = join(localeRoot, filename);
  writeFileSync(path, bytes, { flag: 'wx' });
  const proofPath = join(localeRoot, `${name}.proof.json`);
  writeFileSync(proofPath, `${JSON.stringify({
    before: missileBefore,
    after: missileAfter,
    runtime_before: runtimeBefore.raw,
    runtime_after: runtimeAfter.raw,
  }, null, 2)}\n`, {
    flag: 'wx',
  });
  captures.push({
    name,
    filename,
    asset_locale: locale.asset,
    game_locale: locale.game,
    path: path.slice(REPO_ROOT.length + 1),
    proof_path: proofPath.slice(REPO_ROOT.length + 1),
    kind: 'missile_core_recovery',
    boot_kind: 'missile_core',
    boot_nonce: bootNonce,
    runtime_nonce: runtimeNonce,
    clean_ui_proof: cleanUiProof,
    width: size.width,
    height: size.height,
    sha256: sha256(bytes),
    installed_apk_sha256: installedAfter,
    runtime_before: runtimeBefore.raw,
    runtime_after: runtimeAfter.raw,
    safe_layout: runtimeBefore.safeLayout,
    physical_safe_layout: physicalSafeLayout,
    missile_before: missileBefore,
    missile_after: missileAfter,
  });
  removePrivate([
    RUNTIME_REQUEST,
    RUNTIME_STATE,
    RUNTIME_TEMP,
    MISSILE_REQUEST,
    MISSILE_STATE,
    MISSILE_TEMP,
    CLEAN_UI.combat.request,
    CLEAN_UI.combat.ready,
  ]);
}

async function captureFieldGuardian(locale) {
  let lastError = null;
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    // Prevent a previous missile/guardian process from consuming the new nonce first.
    adb(['shell', 'am', 'force-stop', PACKAGE]);
    clearCaptureHandshakes();
    const guardianNonce = armRuntime('field_guardian');
    armBoot('field_guardian', guardianNonce);
    await launch();
    try {
      await captureRuntime(
        SCREENSHOTS.guardian,
        locale,
        guardianNonce,
        {
          kind: 'field_guardian',
          gameLocale: locale.game,
          bootKind: 'field_guardian',
        },
        'combat',
      );
      return;
    } catch (error) {
      lastError = error;
      // The API 36 host GPU rarely stalls the Godot main loop after the first four
      // frames. Failures where semantic state keeps updating, post-capture
      // stability fails, or file/foreground checks fail must not be hidden by a
      // retry. Only a cold stall frozen at first observation <= 5 for 90s is
      // re-proven exactly once with a new nonce and process.
      const retryColdStall = error instanceof RuntimeStateTimeoutError
        && shouldRetryTabletGuardianColdStall({
          afterObservation: error.afterObservation,
          attempt,
          lastObservation: error.lastState?.observation ?? null,
          sawRejectedState: error.sawRejectedState,
          sawStateFile: error.sawStateFile,
        });
      if (!retryColdStall) throw error;
      adb(['shell', 'am', 'force-stop', PACKAGE]);
      clearCaptureHandshakes();
      console.warn(
        `${locale.asset} field_guardian cold main-loop stall; fresh retry 1/1`,
      );
    }
  }
  throw lastError;
}

function prepareAttestedCaptureApk() {
  const sourceBeforeBuild = currentSourceSnapshot();
  let sourceAfterBuild = sourceBeforeBuild;
  let attestation;
  let attestationOrigin = null;
  if (options.freshBuild) {
    if (options.apk !== DEFAULT_BUILD_APK) {
      fail(`--fresh-build APK path must be ${DEFAULT_BUILD_APK}`);
    }
    console.log('building a fresh Android debug APK for tablet evidence');
    run('pnpm', ['android:build'], { inherit: true });
    if (!existsSync(options.apk)) fail(`fresh debug APK was not created: ${options.apk}`);
    sourceAfterBuild = currentSourceSnapshot();
    if (!sameSourceSnapshot(sourceBeforeBuild, sourceAfterBuild)) {
      fail('runtime or capture inputs changed while building the Android debug APK');
    }
    attestation = {
      schema: 1,
      apk_sha256: sha256(readFileSync(options.apk)),
      runtime_sha256: sourceAfterBuild.runtime_sha256,
      input_sha256: sourceAfterBuild.source_input_sha256,
    };
  } else {
    attestationOrigin = options.attestation;
    attestation = readBuildAttestation(options.attestation);
  }
  assertBuildAttestationCurrent(attestation, options.apk, sourceAfterBuild);
  attestation = normalizedBuildAttestation(attestation);

  const evidenceApkPath = join(outputRoot, 'capture-debug.apk');
  copyFileSync(options.apk, evidenceApkPath, constants.COPYFILE_EXCL);
  if (sha256(readFileSync(evidenceApkPath)) !== attestation.apk_sha256) {
    fail('evidence debug APK copy differs from the build attestation');
  }
  assertBuildAttestationCurrent(attestation, evidenceApkPath, sourceAfterBuild);
  const attestationPath = join(outputRoot, 'build-attestation.json');
  writeFileSync(
    attestationPath,
    `${JSON.stringify(attestation, null, 2)}\n`,
    { flag: 'wx' },
  );
  return {
    apk_path: evidenceApkPath,
    attestation,
    attestation_path: attestationPath,
    attestation_origin: attestationOrigin,
    source_before_build: sourceBeforeBuild,
    source_after_build: sourceAfterBuild,
  };
}

async function captureLocale(locale) {
  setGameLocale(locale);
  clearCaptureHandshakes();

  const titleNonce = armRuntime('title');
  await launch();
  await captureRuntime(
    SCREENSHOTS.title,
    locale,
    titleNonce,
    { kind: 'title', gameLocale: locale.game, directDistribution: true },
    'title',
  );

  const shrineNonce = armRuntime('shrine');
  await captureRuntime(
    SCREENSHOTS.shrine,
    locale,
    shrineNonce,
    { kind: 'shrine', gameLocale: locale.game },
    'title',
  );

  const heroNonce = armRuntime('hero_preview', { hero_path: HERO_PATH });
  await captureRuntime(
    SCREENSHOTS.hero,
    locale,
    heroNonce,
    { kind: 'hero_preview', gameLocale: locale.game, heroPath: HERO_PATH },
    'title',
  );

  clearCaptureHandshakes();
  const barrageNonce = armRuntime('moonlight_barrage');
  armBoot('moonlight_barrage', barrageNonce);
  await launch();
  await captureRuntime(
    SCREENSHOTS.barrage,
    locale,
    barrageNonce,
    {
      kind: 'moonlight_barrage',
      gameLocale: locale.game,
      bootKind: 'moonlight_barrage',
    },
    'combat',
  );

  clearCaptureHandshakes();
  const missileRuntimeNonce = armRuntime('arena_ready');
  const missileBootNonce = randomBytes(32).toString('hex');
  armBoot('missile_core', missileBootNonce);
  adb(['shell', 'run-as', PACKAGE, 'touch', privatePath(MISSILE_REQUEST)]);
  await launch();
  await captureMissileCore(
    SCREENSHOTS.missile,
    locale,
    missileBootNonce,
    missileRuntimeNonce,
  );

  await captureFieldGuardian(locale);
}

function parsedWmSize(raw) {
  const matches = [...raw.matchAll(/(?:Physical|Override) size:\s*(\d+)x(\d+)/gu)];
  const match = matches.at(-1);
  if (!match) fail(`failed to read physical screen size: ${raw}`);
  return { width: Number(match[1]), height: Number(match[2]), raw };
}

function parsedWmDensity(raw) {
  const matches = [...raw.matchAll(/(?:Physical|Override) density:\s*(\d+)/gu)];
  const match = matches.at(-1);
  if (!match) fail(`failed to read physical screen density: ${raw}`);
  return { dpi: Number(match[1]), raw };
}

function assertCaptureFilesCurrent() {
  for (const capture of captures) {
    const bytes = readFileSync(join(REPO_ROOT, capture.path));
    const size = pngSize(bytes);
    if (
      sha256(bytes) !== capture.sha256
      || size.width !== capture.width
      || size.height !== capture.height
    ) {
      fail(`timestamped capture changed after recording: ${capture.path}`);
    }
  }
}

function sameSourceSnapshot(before, after) {
  return before.runtime_sha256 === after.runtime_sha256
    && JSON.stringify(before.source_input_sha256)
      === JSON.stringify(after.source_input_sha256);
}

function canonicalCapturePath(capture) {
  return `builds/shots/store-platform/android/${options.target}`
    + `/${capture.asset_locale}/${capture.filename}`;
}

function publishCanonicalAtomically(report) {
  const parent = join(REPO_ROOT, 'builds/shots/store-platform/android');
  const canonicalRoot = join(parent, options.target);
  const stagingRoot = join(parent, `.${options.target}-staging-${runId}`);
  if (existsSync(canonicalRoot)) {
    fail(`refusing to overwrite existing canonical tablet assets: ${canonicalRoot}`);
  }
  if (existsSync(stagingRoot)) fail(`canonical staging path already exists: ${stagingRoot}`);
  mkdirSync(stagingRoot, { recursive: true });
  for (const capture of captures) {
    const localeRoot = join(stagingRoot, capture.asset_locale);
    mkdirSync(localeRoot, { recursive: true });
    const destination = join(localeRoot, capture.filename);
    copyFileSync(
      join(REPO_ROOT, capture.path),
      destination,
      constants.COPYFILE_EXCL,
    );
    if (sha256(readFileSync(destination)) !== capture.sha256) {
      fail(`canonical staging copy hash differs: ${capture.filename}`);
    }
  }
  const stagedReport = join(stagingRoot, 'capture-report.json');
  writeFileSync(stagedReport, `${JSON.stringify(report, null, 2)}\n`, { flag: 'wx' });
  renameSync(stagingRoot, canonicalRoot);
  for (const capture of captures) {
    const published = join(canonicalRoot, capture.asset_locale, capture.filename);
    if (sha256(readFileSync(published)) !== capture.sha256) {
      fail(`canonical PNG hash differs after atomic publish: ${published}`);
    }
  }
  return join(canonicalRoot, 'capture-report.json');
}

async function main() {
  const state = adb(['get-state']);
  if (state !== 'device') fail(`${options.serial} state is not device: ${state}`);
  const avdName = adb(['emu', 'avd', 'name']).split(/\r?\n/u)[0].trim();
  if (avdName !== options.avd) fail(`AVD differs: expected ${options.avd}, got ${avdName}`);
  const sdk = adb(['shell', 'getprop', 'ro.build.version.sdk']);
  if (sdk !== '36') fail(`not an Android API 36 AVD: API ${sdk}`);
  const physicalSize = parsedWmSize(adb(['shell', 'wm', 'size']));
  const density = parsedWmDensity(adb(['shell', 'wm', 'density']));
  const avdConfigSourcePath = join(
    homedir(),
    '.android/avd',
    `${options.avd}.avd`,
    'config.ini',
  );
  if (!existsSync(avdConfigSourcePath)) {
    fail(`AVD config.ini source is missing: ${avdConfigSourcePath}`);
  }
  const avdConfigBytes = readFileSync(avdConfigSourcePath);
  const avdConfigProof = assertAndroidAvdCaptureContract({
    target: options.target,
    avdName,
    apiLevel: Number(sdk),
    configBytes: avdConfigBytes,
    physicalSize,
    density: density.dpi,
  });
  const avdConfigEvidencePath = join(outputRoot, 'avd-config.ini');
  writeFileSync(avdConfigEvidencePath, avdConfigBytes, { flag: 'wx' });
  if (sha256(readFileSync(avdConfigEvidencePath)) !== avdConfigProof.source_sha256) {
    fail('preserved AVD config.ini differs from source bytes.');
  }
  // A fresh AVD otherwise pauses Godot under Android's one-time "Viewing full
  // screen" dialog. Treating the dimmed app below it as evidence would be a
  // false positive, so suppress that system tutorial before the first launch.
  adb(['shell', 'settings', 'put', 'secure', 'immersive_mode_confirmations', 'confirmed']);

  const build = prepareAttestedCaptureApk();
  const sourceBefore = build.source_after_build;
  const apkBytes = readFileSync(build.apk_path);
  const apkSha256 = sha256(apkBytes);
  await waitDeviceOnline('APK install');
  const install = run(
    adbPath,
    ['-s', options.serial, 'install', '-r', '-t', build.apk_path],
  );
  if (!String(install.stdout).includes('Success')) fail('debug APK install success string is missing');
  adb(['shell', 'run-as', PACKAGE, 'mkdir', '-p', 'files']);
  const installedSha256 = installedApkSha256();
  if (installedSha256 !== apkSha256) {
    fail(`installed APK (${installedSha256}) differs from input APK (${apkSha256})`);
  }
  // Freeze save files after install -r before any app code runs. The first
  // direct frame can recover a past Play IAP provenance into Vault, so a
  // snapshot after the runtime probe would treat already-changed values as the
  // original.
  const persistentBefore = capturePersistentFilesBeforeFirstLaunch();
  const originalSettings = persistentBefore[SETTINGS_FILE];
  const selectedLocales = options.allLocales
    ? LOCALES
    : [LOCALES.find(({ asset }) => asset === options.locale)];
  let captureFailure = null;
  let windowDump = '';
  let foregroundVerified = false;
  let persistenceRestore = null;
  try {
    await verifyInstalledDirectDistributionRuntime(apkSha256);
    for (const locale of selectedLocales) await captureLocale(locale);
    windowDump = foregroundOutput();
    foregroundVerified = foregroundSignalsShowPackage(windowDump, PACKAGE);
    if (!foregroundVerified) fail('game is not foreground immediately after the final capture');
  } catch (error) {
    captureFailure = error;
  }

  const restorationErrors = [];
  try {
    clearCaptureHandshakes();
  } catch (error) {
    restorationErrors.push(`handshake: ${error.message}`);
  }
  try {
    persistenceRestore = restorePersistentFiles(persistentBefore);
  } catch (error) {
    restorationErrors.push(`persistent: ${error.message}`);
  }
  if (captureFailure !== null) {
    if (restorationErrors.length > 0) {
      captureFailure.message += `; restore failed: ${restorationErrors.join(' | ')}`;
    }
    throw captureFailure;
  }
  if (restorationErrors.length > 0) fail(`post-capture restore failed: ${restorationErrors.join(' | ')}`);

  const persistenceEvidence = buildAndroidPersistentEvidence(
    persistentBefore,
    persistenceRestore,
  );
  const persistenceAnchorPath = join(outputRoot, 'persistence-evidence.json');
  const persistenceAnchor = buildAndroidPersistenceAnchor(
    persistenceEvidence,
    persistentBefore,
    persistenceRestore,
    {
      captureId: randomBytes(32).toString('hex'),
      path: relative(REPO_ROOT, persistenceAnchorPath),
    },
  );
  writeFileSync(persistenceAnchorPath, persistenceAnchor.bytes, { flag: 'wx' });
  const restoredSettings = readPrivate(SETTINGS_FILE, true);
  if (
    (originalSettings === null) !== (restoredSettings === null)
    || (
      originalSettings !== null
      && restoredSettings !== null
      && !originalSettings.equals(restoredSettings)
    )
  ) {
    fail('final settings.cfg restore check failed');
  }
  const installedAfterCapture = installedApkSha256();
  if (installedAfterCapture !== apkSha256) fail('installed APK changed during the full capture');
  const sourceAfter = currentSourceSnapshot();
  if (!sameSourceSnapshot(sourceBefore, sourceAfter)) {
    fail('game runtime or capture inputs changed during device capture');
  }
  assertBuildAttestationCurrent(build.attestation, build.apk_path, sourceAfter);
  assertCaptureFilesCurrent();
  const manifest = assertCompleteTabletCaptureManifest({
    captures,
    locales: selectedLocales.map(({ asset }) => asset),
    filenames: Object.values(SCREENSHOTS),
    apkSha256,
    installedApkSha256: installedAfterCapture,
  });

  const expectedLandscape = `${Math.max(physicalSize.width, physicalSize.height)}x${
    Math.min(physicalSize.width, physicalSize.height)}`;
  if (manifest.screenshot_size !== expectedLandscape) {
    fail(`PNG ${manifest.screenshot_size} differs from physical landscape ${expectedLandscape}`);
  }

  const windowDumpPath = join(outputRoot, 'window-displays.txt');
  const windowDumpBytes = Buffer.from(`${windowDump}\n`, 'utf8');
  writeFileSync(windowDumpPath, windowDumpBytes, { flag: 'wx' });
  const gestureLines = [...new Set(windowDump.split(/\r?\n/u)
    .map((line) => line.trim())
    .filter((line) => /type=(?:systemGestures|mandatorySystemGestures)/u.test(line)))];
  const canonicalEligible = options.allLocales && captures.length === 30;
  const reportCaptures = captures.map(({ path, ...capture }) => ({
    ...capture,
    evidence_path: path,
    source: canonicalEligible ? canonicalCapturePath(capture) : null,
  }));
  const report = {
    schema: 2,
    captured_at: new Date().toISOString(),
    platform: 'android',
    target: options.target,
    serial: options.serial,
    avd_name: avdName,
    avd_config: {
      ...avdConfigProof,
      evidence_path: relative(REPO_ROOT, avdConfigEvidencePath),
    },
    api_level: Number(sdk),
    build_fingerprint: adb(['shell', 'getprop', 'ro.build.fingerprint']),
    model: adb(['shell', 'getprop', 'ro.product.model']),
    device: adb(['shell', 'getprop', 'ro.product.device']),
    system_locale: adb(['shell', 'getprop', 'persist.sys.locale']),
    asset_locales: selectedLocales.map(({ asset }) => asset),
    game_locales: selectedLocales.map(({ game }) => game),
    physical_size: physicalSize,
    density,
    screenshot_size: manifest.screenshot_size,
    foreground_verified_at_capture_end: foregroundVerified,
    window_dump_path: relative(REPO_ROOT, windowDumpPath),
    window_dump_sha256: sha256(windowDumpBytes),
    window_gesture_insets: gestureLines,
    package: PACKAGE,
    launcher_component: LAUNCHER,
    apk_path: relative(REPO_ROOT, build.apk_path),
    apk_origin_path: relative(REPO_ROOT, options.apk),
    apk_sha256: apkSha256,
    installed_apk_sha256: installedAfterCapture,
    build_attestation_path: relative(REPO_ROOT, build.attestation_path),
    build_attestation_origin: build.attestation_origin === null
      ? null
      : relative(REPO_ROOT, build.attestation_origin),
    build_attestation_sha256: sha256(readFileSync(build.attestation_path)),
    build_attestation: build.attestation,
    build_mode: options.freshBuild ? 'fresh-build' : 'verified-attestation',
    source_before_build: build.source_before_build,
    source_after_build: build.source_after_build,
    source_before: sourceBefore,
    source_after: sourceAfter,
    source_byte_equivalent: true,
    ...persistenceEvidence,
    persistence_anchor: persistenceAnchor.anchor,
    canonical_publish_eligible: canonicalEligible,
    canonical_root: canonicalEligible
      ? `builds/shots/store-platform/android/${options.target}`
      : null,
    publication: canonicalEligible ? 'timestamp-staging-then-atomic-directory-rename' : 'none',
    captures: reportCaptures,
  };
  assertAndroidPersistentReportEvidence(report, {
    anchorBytes: readFileSync(persistenceAnchorPath),
  });
  const persistenceSignaturePath = join(
    outputRoot,
    ANDROID_CAPTURE_SIGNATURE_FILENAME,
  );
  const signedPersistence = createSignedAndroidCaptureEvidence({
    report,
    anchorBytes: readFileSync(persistenceAnchorPath),
    outputPath: persistenceSignaturePath,
    evidencePath: relative(REPO_ROOT, persistenceSignaturePath),
    repositoryRoot: REPO_ROOT,
  });
  report.persistence_signature = signedPersistence.descriptor;
  verifySignedAndroidCaptureEvidence(report, {
    anchorBytes: readFileSync(persistenceAnchorPath),
    signatureBytes: signedPersistence.signatureBytes,
  });
  const reportPath = join(outputRoot, 'report.json');
  writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, { flag: 'wx' });
  if (canonicalEligible) {
    const canonicalReport = publishCanonicalAtomically(report);
    console.log(canonicalReport);
  }
  console.log(reportPath);
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exitCode = 1;
});
