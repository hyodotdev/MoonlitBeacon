#!/usr/bin/env node

// Capture first-party iPhone/iPad store evidence from a physical CoreDevice.
//
// Apple CoreDevice owns app installation and appDataContainer I/O. Screenshots
// come either from a verified pymobiledevice3 DVT/RSD endpoint or from Apple's
// Xcode Devices UI through a nonce-bound owner-only handoff inbox. Every
// accepted PNG is bracketed by two fresh in-game state proofs.

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
  rmSync,
  statSync,
} from 'node:fs';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  assertMissileCoreCaptureState,
  assertStableMissileCoreCaptureState,
  assertStableStoreCaptureState,
  assertStoreCaptureState,
} from './lib/capture-run-state.mjs';
import {
  assertByteExactRestoration,
  assertCompleteIosCaptureManifest,
  assertFrozenIosInstallArtifact,
  assertInstalledIosApp,
  assertPrivateXcodeScreenshotInbox,
  assertPhysicalIosDevice,
  assertPhysicalIosSafeLayout,
  assertRsdIosDeviceIdentity,
  assertStableIosPersistentSnapshots,
  assertStableIosArenaCaptureState,
  coreDeviceRsdPortCandidates,
  createDeferredCancellation,
  ensurePrivateDirectory,
  iosAppTreeSha256,
  isDevicectlReportedTimeout,
  IOS_CODE_PERSISTENT_FILES,
  IOS_RSD_CAPTURE_METHOD,
  IOS_XCODE_HANDOFF_CAPTURE_METHOD,
  IOS_XCODE_IPAD_LANDSCAPE_SIZE,
  pngSize,
  removeXcodeScreenshotHandoffEntries,
  sealPrivateRegularFile,
  settleWithMandatoryCleanup,
  withEphemeralFilesystemPath,
  withImmutableFilesystemPath,
  waitForXcodeScreenshotHandoff,
  waitForPendingHostSignalHandlers,
  writePrivateFileExclusive,
} from './lib/ios-device-evidence.mjs';
import { credentialFreeChildEnvironment } from './lib/release-environment.mjs';

function resolvePymobiledevice3Bin() {
  const configured = process.env.MOONLIT_PYMOBILEDEVICE3_BIN?.trim();
  if (configured) return configured;
  const result = spawnSync('which', ['pymobiledevice3'], { encoding: 'utf8' });
  if (result.status === 0) {
    const found = result.stdout.trim().split('\n')[0];
    if (found) return found;
  }
  return 'pymobiledevice3';
}

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PRODUCTION_BUNDLE_ID = 'com.crossplatformkorea.moonlitbeacon';
const ISOLATED_CAPTURE_BUNDLE_ID = `${PRODUCTION_BUNDLE_ID}.storecapture`;
const APP_NAME = 'MoonlitBeacon';
const HERO_PATH = 'res://resources/heroes/keeper.tres';
const PYMOBILEDEVICE3 = resolvePymobiledevice3Bin();
const CHILD_ENV = credentialFreeChildEnvironment(process.env);
const APP_CANDIDATES = Object.freeze([
  join(REPO_ROOT, 'builds/ios-dd/Build/Products/Debug-iphoneos/MoonlitBeacon.app'),
  join(REPO_ROOT, 'builds/ios-dev-no-appicon-dd/Build/Products/Debug-iphoneos/MoonlitBeacon.app'),
]);
const BOOT_REQUEST = 'store_capture_boot.request.json';
const RUNTIME_REQUEST = 'store_capture_runtime.request.json';
const RUNTIME_STATE = 'store_capture_runtime.state.json';
const RUNTIME_TEMP = 'store_capture_runtime.state.tmp';
const MISSILE_REQUEST = 'store_capture_missile_core.request';
const MISSILE_STATE = 'store_capture_state.json';
const MISSILE_TEMP = 'store_capture_state.tmp';
const TITLE_READY = 'store_capture_title_runtime.ready';
const TEST_HERO_REQUEST = 'test_hero.request';
// Darwin/iOS signal numbers. Names are kept here so no caller can accidentally
// use the host platform's signal table or suspend any capture except guardian.
const IOS_SIGSTOP = 17;
const IOS_SIGCONT = 19;
const DEVICECTL_MIN_TIMEOUT_MS = 5_000;
const DEVICECTL_REMOTE_READ_MIN_TIMEOUT_MS = DEVICECTL_MIN_TIMEOUT_MS * 2;
const DEVICECTL_POLL_TIMEOUT_MS = DEVICECTL_REMOTE_READ_MIN_TIMEOUT_MS;
const DEVICECTL_STABLE_READ_TIMEOUT_MS = (
  DEVICECTL_MIN_TIMEOUT_MS
  + DEVICECTL_POLL_TIMEOUT_MS
  + DEVICECTL_MIN_TIMEOUT_MS
);
const DEVICECTL_STABLE_READ_OVERHEAD_MS = 2_000;
const XCODE_HANDOFF_DEADLINE_MS = 300_000;
const PERSISTENT_FILES = IOS_CODE_PERSISTENT_FILES;
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
const CONTROL_FILES = Object.freeze([
  BOOT_REQUEST,
  RUNTIME_REQUEST,
  RUNTIME_STATE,
  RUNTIME_TEMP,
  MISSILE_REQUEST,
  MISSILE_STATE,
  MISSILE_TEMP,
  TITLE_READY,
  ...Object.values(CLEAN_UI).flatMap(({ request, ready }) => [request, ready]),
]);
const CONTROL_FILE_SET = new Set(CONTROL_FILES);
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

// Keep this byte-for-byte path list aligned with build_store_graphics.py's
// IOS_DEVICE_CAPTURE_SOURCE_INPUTS.  The consumer compares the whole map.
const SOURCE_INPUT_PATHS = Object.freeze([
  'package.json',
  'scripts/capture-ios-device-evidence.mjs',
  'scripts/publish-xcode-screenshot-handoff.mjs',
  'scripts/ios.mjs',
  'scripts/godot.mjs',
  'scripts/lib/capture-run-state.mjs',
  'scripts/lib/godot-export-preflight.mjs',
  'scripts/lib/iapkit-config.mjs',
  'scripts/lib/ios-build.mjs',
  'scripts/lib/ios-device-evidence.mjs',
  'scripts/lib/ios-distribution.mjs',
  'scripts/lib/release-environment.mjs',
  'notes/release/store-assets/screenshots.json',
  'apps/game/project.godot',
  'apps/game/export_presets.cfg',
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

function fail(message) {
  throw new Error(message);
}

function parseArguments(argv) {
  if (argv.includes('--help')) return { help: true };
  const valueArguments = new Set([
    '--target',
    '--device-id',
    '--usb-udid',
    '--rsd-host',
    '--rsd-port',
    '--xcode-screenshot-inbox',
    '--locale',
  ]);
  const values = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (key === '--all-locales') {
      values.allLocales = true;
      continue;
    }
    if (!valueArguments.has(key)) fail(`unsupported argument: ${key}`);
    if (!key.startsWith('--') || index + 1 >= argv.length) {
      fail(`invalid argument: ${key}`);
    }
    if (Object.hasOwn(values, key.slice(2))) fail(`duplicate argument: ${key}`);
    values[key.slice(2)] = argv[index + 1];
    index += 1;
  }
  values.target ??= 'ipad-13';
  if (!['ipad-13', 'iphone-6.5'].includes(values.target)) {
    fail(`unsupported iOS capture target: ${values.target}`);
  }
  for (const required of ['device-id', 'usb-udid']) {
    if (typeof values[required] !== 'string' || values[required].trim() === '') {
      fail(`--${required} is required`);
    }
  }
  if (!/^[0-9A-F-]{36}$/iu.test(values['device-id'])) {
    fail(`CoreDevice identifier format is invalid: ${values['device-id']}`);
  }
  if (!/^[0-9A-F-]{20,40}$/iu.test(values['usb-udid'])) {
    fail(`USB UDID format is invalid: ${values['usb-udid']}`);
  }
  values.locale ??= 'en-US';
  if (!LOCALES.some(({ asset }) => asset === values.locale)) {
    fail(`unsupported asset locale: ${values.locale}`);
  }
  if (values.allLocales && argv.includes('--locale')) {
    fail('--all-locales and --locale cannot be used together');
  }
  const hasRsdHost = typeof values['rsd-host'] === 'string';
  const hasRsdPort = typeof values['rsd-port'] === 'string';
  if (hasRsdHost !== hasRsdPort) fail('--rsd-host and --rsd-port must be set together');
  const hasXcodeInbox = typeof values['xcode-screenshot-inbox'] === 'string';
  if (hasXcodeInbox && (hasRsdHost || hasRsdPort)) {
    fail('--xcode-screenshot-inbox and --rsd-host/--rsd-port cannot be used together');
  }
  if (hasXcodeInbox && values.target !== 'ipad-13') {
    fail('Xcode screenshot handoff is only supported on verified 2266x1488 ipad-13');
  }
  if (hasRsdPort) {
    const port = Number(values['rsd-port']);
    if (!Number.isSafeInteger(port) || port <= 0 || port > 65_535) {
      fail(`RSD port is invalid: ${values['rsd-port']}`);
    }
    values.rsdPort = port;
  }
  values.deviceId = values['device-id'];
  values.usbUdid = values['usb-udid'];
  values.rsdHost = values['rsd-host'] ?? null;
  values.xcodeScreenshotInbox = values['xcode-screenshot-inbox'] ?? null;
  return values;
}

const options = parseArguments(process.argv.slice(2));
if (options.help) {
  console.log(
    'usage: capture-ios-device-evidence.mjs '
      + '[--target ipad-13|iphone-6.5] [--device-id COREDEVICE_UUID] '
      + '[--usb-udid USB_UDID] [--rsd-host IPV6 --rsd-port PORT] '
      + '[--xcode-screenshot-inbox /ABSOLUTE/PRIVATE/INBOX] '
      + '[--all-locales | --locale en-US|ko-KR|ja-JP|zh-Hans|zh-Hant]',
  );
  process.exit(0);
}
if (options.xcodeScreenshotInbox === null && !existsSync(PYMOBILEDEVICE3)) {
  fail(`pymobiledevice3 not found: ${PYMOBILEDEVICE3}`);
}
const captureMethod = options.xcodeScreenshotInbox === null
  ? IOS_RSD_CAPTURE_METHOD
  : IOS_XCODE_HANDOFF_CAPTURE_METHOD;
// Every capture transport uses a disposable bundle. RSD is only a framebuffer
// transport; it must never justify replacing or opening the production app.
const ACTIVE_BUNDLE_ID = ISOLATED_CAPTURE_BUNDLE_ID;
const deferredCancellation = createDeferredCancellation();
let cleanupInProgress = false;
for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => deferredCancellation.request(signal));
}

function throwIfCancellationRequested() {
  if (!cleanupInProgress) deferredCancellation.throwIfRequested();
}

function cancellable(operation) {
  return cleanupInProgress
    ? Promise.resolve(operation)
    : deferredCancellation.race(operation);
}

async function cancellationCheckpoint() {
  if (cleanupInProgress) return;
  await waitForPendingHostSignalHandlers();
  deferredCancellation.throwIfRequested();
}

function run(command, args, {
  allowFailure = false,
  binary = false,
  cwd = REPO_ROOT,
  timeout = 60_000,
} = {}) {
  throwIfCancellationRequested();
  const result = spawnSync(command, args, {
    cwd,
    encoding: binary ? null : 'utf8',
    env: CHILD_ENV,
    maxBuffer: 128 * 1024 * 1024,
    timeout,
    killSignal: 'SIGTERM',
  });
  throwIfCancellationRequested();
  if (result.error && !allowFailure) throw result.error;
  if (!allowFailure && result.status !== 0) {
    const stdout = Buffer.from(result.stdout ?? '').toString('utf8').trim();
    const stderr = Buffer.from(result.stderr ?? '').toString('utf8').trim();
    fail(`${command} ${args.join(' ')} failed (${result.status})\n${stderr || stdout}`);
  }
  return result;
}

function sleep(milliseconds) {
  return cancellable(new Promise(
    (resolvePromise) => setTimeout(resolvePromise, milliseconds),
  ));
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function fileSha256(path) {
  return sha256(readFileSync(path));
}

function writeJson(path, value) {
  writePrivateFileExclusive(path, `${JSON.stringify(value, null, 2)}\n`);
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

function sourceInputSha256() {
  return Object.fromEntries(SOURCE_INPUT_PATHS.map((relativePath) => {
    const path = join(REPO_ROOT, relativePath);
    if (!existsSync(path)) fail(`iOS capture source input is missing: ${relativePath}`);
    return [relativePath, fileSha256(path)];
  }));
}

function currentSourceSnapshot() {
  return {
    runtime_sha256: runtimeSha256(),
    source_input_sha256: sourceInputSha256(),
  };
}

function sameSourceSnapshot(before, after) {
  return before.runtime_sha256 === after.runtime_sha256
    && JSON.stringify(before.source_input_sha256)
      === JSON.stringify(after.source_input_sha256);
}

const xcodeScreenshotInbox = options.xcodeScreenshotInbox === null
  ? null
  : assertPrivateXcodeScreenshotInbox(options.xcodeScreenshotInbox, REPO_ROOT);
const runId = new Date().toISOString().replace(/[:.]/gu, '-');
const outputRoot = join(
  REPO_ROOT,
  'builds/ios-device-evidence',
  options.target,
  `${options.deviceId}-${runId}`,
);
const workRoot = join(outputRoot, 'work');
ensurePrivateDirectory(outputRoot);
ensurePrivateDirectory(workRoot);
let jsonSequence = 0;
let remoteSequence = 0;

function runDevicectlJson(args, label, destination = null, timeout = 30_000) {
  if (!Number.isSafeInteger(timeout) || timeout < DEVICECTL_MIN_TIMEOUT_MS) {
    fail(`${label} CoreDevice timeout budget is missing`);
  }
  const path = destination ?? join(
    workRoot,
    `${String(++jsonSequence).padStart(4, '0')}-${label}.json`,
  );
  if (existsSync(path)) fail(`CoreDevice JSON output already exists: ${path}`);
  try {
    run('xcrun', ['devicectl', ...args, '--json-output', path, '--timeout', String(
      Math.max(5, Math.floor(timeout / 1000)),
    )], { timeout });
  } catch (error) {
    if (isDevicectlReportedTimeout(error)) {
      const timeoutError = new Error(`${label} CoreDevice command timeout`, { cause: error });
      timeoutError.code = 'ETIMEDOUT';
      throw timeoutError;
    }
    throw error;
  }
  sealPrivateRegularFile(path);
  const payload = JSON.parse(readFileSync(path, 'utf8'));
  if (payload?.info?.outcome !== 'success') fail(`${label} CoreDevice result is not success`);
  return { path, payload };
}

function queryInstalledApp(label, destination = null, bundleId = ACTIVE_BUNDLE_ID, timeout = 30_000) {
  const evidence = runDevicectlJson([
    'device', 'info', 'apps',
    '--device', options.deviceId,
    '--bundle-id', bundleId,
  ], label, destination, timeout);
  if (
    evidence.payload?.result?.deviceIdentifier !== options.deviceId
    || evidence.payload?.result?.matchingBundleIdentifier !== bundleId
    || !Array.isArray(evidence.payload?.result?.apps)
  ) {
    fail(`${label} CoreDevice app query identity differs`);
  }
  return evidence;
}

function installedAppOrNull(payload, bundleId = ACTIVE_BUNDLE_ID) {
  const matches = (payload?.result?.apps ?? [])
    .filter((app) => app?.bundleIdentifier === bundleId);
  if (matches.length > 1) fail('more than one iOS app with the same bundle ID was returned');
  return matches[0] ?? null;
}

function installedAppIdentity(payload, bundleId) {
  const app = installedAppOrNull(payload, bundleId);
  if (app === null) return null;
  return {
    bundleIdentifier: app.bundleIdentifier,
    bundleVersion: app.bundleVersion ?? null,
    version: app.version ?? null,
    url: app.url ?? null,
  };
}

function installedAppIdentitySha256(app) {
  return sha256(Buffer.from(JSON.stringify({
    bundleIdentifier: app.bundleIdentifier,
    bundleVersion: app.bundleVersion,
    version: app.version,
    url: app.url,
  }), 'utf8'));
}

function installedAppExecutableUrl(app, label) {
  const executableUrl = `${app?.url ?? ''}${APP_NAME}`;
  if (!/^file:\/\/\/private\/var\/containers\/Bundle\/Application\/[0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12}\/MoonlitBeacon\.app\/MoonlitBeacon$/u.test(
    executableUrl,
  )) {
    fail(`${label} iOS executable URL is not the expected container path`);
  }
  return executableUrl;
}

function exactExecutableProcesses(executableUrl, label, timeout = 30_000) {
  const { payload, path } = runDevicectlJson([
    'device', 'info', 'processes', '--device', options.deviceId,
    '--filter', `executable.absoluteString == '${executableUrl}'`,
  ], label, null, timeout);
  const runningProcesses = payload?.result?.runningProcesses;
  if (
    payload?.info?.commandType !== 'devicectl.device.info.processes'
    || payload?.result?.deviceIdentifier !== options.deviceId
    || !Array.isArray(runningProcesses)
  ) {
    fail(`${label} CoreDevice process query identity differs`);
  }
  const processes = runningProcesses.filter(
    (process) => process?.executable === executableUrl,
  );
  if (processes.length !== runningProcesses.length) {
    fail(`${label} exact executable predicate returned a different process`);
  }
  return { processes, path };
}

function quiesceProductionApp(app, label) {
  if (app === null) return;
  const executableUrl = installedAppExecutableUrl(app, label);
  const before = exactExecutableProcesses(executableUrl, `${label}-before`);
  if (before.processes.length > 1) {
    fail(`${label} more than one production process is running`);
  }
  if (before.processes.length === 1) {
    terminateGameProcess(before.processes[0].processIdentifier, label);
  }
  const after = exactExecutableProcesses(executableUrl, `${label}-after`);
  if (after.processes.length !== 0) {
    fail(`${label} could not confirm production process exit`);
  }
}

function documentFileNames(timeout = 30_000) {
  const { payload } = runDevicectlJson([
    'device', 'info', 'files',
    '--device', options.deviceId,
    '--domain-type', 'appDataContainer',
    '--domain-identifier', ACTIVE_BUNDLE_ID,
    '--subdirectory', 'Documents',
    '--no-recurse',
  ], 'document-files', null, timeout);
  return new Set((payload?.result?.files ?? [])
    .filter((entry) => entry?.resources?.isDirectory === false)
    .map((entry) => entry.relativePath));
}

function safeRemoteName(name) {
  if (
    typeof name !== 'string'
    || name.length === 0
    || name === '.'
    || name === '..'
    || basename(name) !== name
    || name.includes('\\')
    || name.includes('\0')
  ) {
    fail(`unsafe iOS Documents filename: ${name}`);
  }
  return name;
}

function readRemote(name, optional = false, timeout = 30_000) {
  safeRemoteName(name);
  if (
    !Number.isSafeInteger(timeout)
    || timeout < DEVICECTL_REMOTE_READ_MIN_TIMEOUT_MS
  ) {
    fail(`iOS Documents/${name} read timeout budget is insufficient`);
  }
  const deadline = Date.now() + timeout;
  const listingTimeout = Math.max(
    DEVICECTL_MIN_TIMEOUT_MS,
    Math.floor(timeout / 2),
  );
  const files = documentFileNames(listingTimeout);
  if (!files.has(name)) {
    if (optional) return null;
    fail(`iOS Documents/${name} is missing`);
  }
  const copyTimeout = deadline - Date.now();
  if (copyTimeout < DEVICECTL_MIN_TIMEOUT_MS) {
    fail(`iOS Documents/${name} copy timeout budget is insufficient`);
  }
  const local = join(workRoot, `pull-${String(++remoteSequence).padStart(4, '0')}-${name}`);
  return withEphemeralFilesystemPath(local, () => {
    runDevicectlJson([
      'device', 'copy', 'from',
      '--device', options.deviceId,
      '--domain-type', 'appDataContainer',
      '--domain-identifier', ACTIVE_BUNDLE_ID,
      '--source', `Documents/${name}`,
      '--destination', local,
    ], `pull-${name}`, null, copyTimeout);
    if (Date.now() >= deadline) {
      fail(`iOS Documents/${name} read deadline expired`);
    }
    sealPrivateRegularFile(local);
    return readFileSync(local);
  });
}

function readRemoteJson(name, timeout = 30_000) {
  const bytes = readRemote(name, true, timeout);
  if (bytes === null) return null;
  try {
    return JSON.parse(bytes.toString('utf8'));
  } catch {
    return null;
  }
}

function writeRemote(name, value) {
  safeRemoteName(name);
  const directory = join(workRoot, `push-${String(++remoteSequence).padStart(4, '0')}`);
  ensurePrivateDirectory(directory);
  return withEphemeralFilesystemPath(directory, () => {
    const source = join(directory, name);
    const bytes = Buffer.isBuffer(value) ? value : Buffer.from(value, 'utf8');
    writePrivateFileExclusive(source, bytes);
    runDevicectlJson([
      'device', 'copy', 'to',
      '--device', options.deviceId,
      '--domain-type', 'appDataContainer',
      '--domain-identifier', ACTIVE_BUNDLE_ID,
      '--source', source,
      '--destination', `Documents/${name}`,
    ], `push-${name}`);
    const actual = readRemote(name);
    if (!actual.equals(bytes)) fail(`iOS Documents/${name} write is not byte-exact`);
  });
}

function disarmFiles(names) {
  for (const name of names) writeRemote(name, '{}\n');
}

function disarmAllControls() {
  disarmFiles(CONTROL_FILES);
}

function disarmPersistentTestHero(original) {
  // Do not create a file that was originally absent: pymobiledevice3's
  // HouseArrest delete path is unavailable for this development install on
  // iOS 26. A pre-existing request is safe to overwrite because cleanup can
  // restore its original bytes with CoreDevice copy even if capture fails.
  if (snapshotValue(original, TEST_HERO_REQUEST) !== null) {
    writeRemote(TEST_HERO_REQUEST, '{}\n');
  }
}

function persistentSnapshot(appInstalled) {
  if (!appInstalled) {
    return Object.fromEntries(PERSISTENT_FILES.map((name) => [name, null]));
  }
  // Preserve every pre-existing non-control root file, including future game
  // saves not yet known to this producer. The explicit list above guarantees
  // known files still get an absent-state assertion on a new installation.
  const names = new Set(PERSISTENT_FILES);
  for (const name of documentFileNames()) {
    if (!CONTROL_FILE_SET.has(name)) names.add(name);
  }
  return Object.fromEntries([...names].sort().map((name) => [
    name,
    readRemote(name, true),
  ]));
}

function assertGameNotRunning(label) {
  const evidence = runningGameProcesses(label);
  if (evidence.processes.length !== 0) {
    fail(
      'the game was running during the iOS persistent-data snapshot. Quit the app '
      + 'and retry to avoid a save race.',
    );
  }
  return evidence;
}

function stablePersistentSnapshot(appInstalled) {
  assertGameNotRunning('processes-before-persistent-snapshot-a');
  const first = persistentSnapshot(appInstalled);
  assertGameNotRunning('processes-between-persistent-snapshots');
  const second = persistentSnapshot(appInstalled);
  assertGameNotRunning('processes-after-persistent-snapshot-b');
  assertStableIosPersistentSnapshots(first, second);
  return second;
}

function persistentHashes(snapshot, names = Object.keys(snapshot)) {
  return Object.fromEntries(names.map((name) => {
    const bytes = snapshotValue(snapshot, name);
    return [
      name,
      bytes === null ? null : sha256(bytes),
    ];
  }));
}

function snapshotValue(snapshot, name) {
  return Object.hasOwn(snapshot, name) ? snapshot[name] : null;
}

function freshestBuiltApp(buildStartedAt) {
  const candidates = APP_CANDIDATES.filter((app) => {
    const pck = join(app, `${APP_NAME}.pck`);
    return existsSync(pck) && statSync(pck).mtimeMs >= buildStartedAt - 2_000;
  });
  if (candidates.length !== 1) {
    fail(`could not select exactly one fresh iOS Debug .app: ${candidates.join(', ')}`);
  }
  return candidates[0];
}

function appPlist(app) {
  const result = run('plutil', [
    '-convert', 'json', '-o', '-', join(app, 'Info.plist'),
  ]);
  return JSON.parse(String(result.stdout));
}

function buildFreshDebugApp() {
  const sourceBeforeBuild = currentSourceSnapshot();
  const buildStartedAt = Date.now();
  const buildResult = run(
    process.execPath,
    [
      'scripts/ios.mjs',
      'capture-build-isolated',
      options.deviceId,
    ],
    { timeout: 20 * 60_000 },
  );
  writePrivateFileExclusive(
    join(outputRoot, 'ios-capture-build.log'),
    `${buildResult.stdout ?? ''}${buildResult.stderr ?? ''}`,
  );
  const sourceAfterBuild = currentSourceSnapshot();
  if (!sameSourceSnapshot(sourceBeforeBuild, sourceAfterBuild)) {
    fail('iOS Debug build runtime or capture inputs changed during the build');
  }
  const app = freshestBuiltApp(buildStartedAt);
  const sourceAppTreeSha256 = iosAppTreeSha256(app);
  const buildRoot = join(outputRoot, 'build');
  ensurePrivateDirectory(buildRoot);
  const artifact = join(buildRoot, `${APP_NAME}.app.zip`);
  run('/usr/bin/ditto', [
    '-c', '-k', '--sequesterRsrc', '--keepParent', app, artifact,
  ], { timeout: 2 * 60_000 });
  run('/usr/bin/unzip', ['-tqq', artifact], { timeout: 60_000 });
  const artifactSha256 = fileSha256(artifact);
  const frozenRoot = join(buildRoot, 'frozen');
  ensurePrivateDirectory(frozenRoot);
  run('/usr/bin/ditto', [
    '-x', '-k', artifact, frozenRoot,
  ], { timeout: 2 * 60_000 });
  const frozenApp = join(frozenRoot, `${APP_NAME}.app`);
  if (!existsSync(frozenApp) || !statSync(frozenApp).isDirectory()) {
    fail('could not extract the frozen .app from the iOS preservation ZIP');
  }
  const appTreeSha256 = iosAppTreeSha256(frozenApp);
  assertFrozenIosInstallArtifact({
    artifactSha256,
    currentArtifactSha256: fileSha256(artifact),
    appTreeSha256: sourceAppTreeSha256,
    currentAppTreeSha256: appTreeSha256,
  });
  const plist = appPlist(frozenApp);
  if (
    plist.CFBundleIdentifier !== ACTIVE_BUNDLE_ID
    || typeof plist.CFBundleShortVersionString !== 'string'
    || typeof plist.CFBundleVersion !== 'string'
    || plist.CFBundleExecutable !== APP_NAME
  ) {
    fail('fresh iOS Debug frozen .app Info.plist identity is invalid');
  }
  const executableSha256 = fileSha256(join(frozenApp, APP_NAME));
  const pckSha256 = fileSha256(join(frozenApp, `${APP_NAME}.pck`));
  const exportedPckSha256 = fileSha256(
    join(REPO_ROOT, 'builds', 'ios', `${APP_NAME}.pck`),
  );
  if (pckSha256 !== exportedPckSha256) {
    fail('isolated iOS app PCK differs from the fresh Godot export');
  }
  const attestation = {
    schema: 2,
    production_bundle_id: PRODUCTION_BUNDLE_ID,
    installed_bundle_id: ACTIVE_BUNDLE_ID,
    isolated_capture_bundle: true,
    content_equivalence: 'same-fresh-exported-pck-production-runtime',
    artifact_sha256: artifactSha256,
    app_tree_sha256: appTreeSha256,
    executable_sha256: executableSha256,
    pck_sha256: pckSha256,
    exported_pck_sha256: exportedPckSha256,
    runtime_sha256: sourceAfterBuild.runtime_sha256,
    input_sha256: sourceAfterBuild.source_input_sha256,
  };
  const attestationPath = join(outputRoot, 'build-attestation.json');
  writeJson(attestationPath, attestation);
  return {
    frozenApp,
    plist,
    artifact,
    artifactSha256,
    appTreeSha256,
    executableSha256,
    pckSha256,
    exportedPckSha256,
    attestation,
    attestationPath,
    sourceBeforeBuild,
    sourceAfterBuild,
    buildStartedAt: new Date(buildStartedAt).toISOString(),
  };
}

function installFreshApp(build) {
  const installPath = join(outputRoot, 'install.json');
  const installRoot = join(
    workRoot,
    `install-${randomBytes(16).toString('hex')}`,
  );
  const installResult = withEphemeralFilesystemPath(installRoot, () => {
    ensurePrivateDirectory(installRoot);
    assertFrozenIosInstallArtifact({
      artifactSha256: build.artifactSha256,
      currentArtifactSha256: fileSha256(build.artifact),
      appTreeSha256: build.appTreeSha256,
      currentAppTreeSha256: iosAppTreeSha256(build.frozenApp),
    });
    run('/usr/bin/ditto', [
      '-x', '-k', build.artifact, installRoot,
    ], { timeout: 2 * 60_000 });

    return withImmutableFilesystemPath(installRoot, () => {
      const installApp = join(installRoot, `${APP_NAME}.app`);
      assertFrozenIosInstallArtifact({
        artifactSha256: build.artifactSha256,
        currentArtifactSha256: fileSha256(build.artifact),
        appTreeSha256: build.appTreeSha256,
        currentAppTreeSha256: iosAppTreeSha256(installApp),
      });
      // BSD user-immutable flags cover the private root and every descendant,
      // so neither a pathname swap nor an in-tree rewrite can race CoreDevice.
      const result = runDevicectlJson([
        'device', 'install', 'app',
        '--device', options.deviceId,
        installApp,
      ], 'install', installPath, 2 * 60_000);
      assertFrozenIosInstallArtifact({
        artifactSha256: build.artifactSha256,
        currentArtifactSha256: fileSha256(build.artifact),
        appTreeSha256: build.appTreeSha256,
        currentAppTreeSha256: iosAppTreeSha256(installApp),
      });
      return result;
    }, (path, immutable) => {
      run('/usr/bin/chflags', ['-R', immutable ? 'uchg' : 'nouchg', path]);
    });
  });
  const installedApplications = installResult.payload?.result?.installedApplications;
  if (
    installResult.payload?.result?.deviceIdentifier !== options.deviceId
    || !Array.isArray(installedApplications)
    || installedApplications.length !== 1
    || installedApplications[0]?.bundleID !== ACTIVE_BUNDLE_ID
  ) {
    fail('CoreDevice did not install the exact iOS bundle on the verified device');
  }
  const installedPath = join(outputRoot, 'installed-app.json');
  const installed = queryInstalledApp('installed-app', installedPath);
  const app = assertInstalledIosApp(installed.payload, {
    bundleId: ACTIVE_BUNDLE_ID,
    shortVersion: build.plist.CFBundleShortVersionString,
    buildVersion: build.plist.CFBundleVersion,
    coreDeviceIdentifier: options.deviceId,
  });
  const executableUrl = installedAppExecutableUrl(app, 'installed capture app');
  return { installPath, installedPath, app, executableUrl };
}

function launchApp(label) {
  const launchArguments = [
    'device', 'process', 'launch',
    '--device', options.deviceId,
    '--terminate-existing',
    ACTIVE_BUNDLE_ID,
  ];
  // Xcode's operator-mediated screenshot takes long enough for short-lived
  // missiles to leave the framebuffer between SIGCONT and the post-frame
  // proof. Slow only this disposable debug process so one newer observation
  // can be sampled without recreating or falsifying the captured volley.
  const xcodeTimeScale = label.endsWith('-guardian') ? '1.0' : '0.2';
  if (captureMethod === IOS_XCODE_HANDOFF_CAPTURE_METHOD) {
    launchArguments.push('--time-scale', xcodeTimeScale);
  }
  const { payload, path } = runDevicectlJson(
    launchArguments,
    `launch-${label}`,
    null,
    45_000,
  );
  const pid = payload?.result?.process?.processIdentifier
    ?? payload?.result?.processIdentifier;
  const expectedRuntimeArguments = captureMethod === IOS_XCODE_HANDOFF_CAPTURE_METHOD
    ? ['--time-scale', xcodeTimeScale]
    : [];
  const actualRuntimeArguments = payload?.result?.launchOptions?.arguments;
  const launchOptions = payload?.result?.launchOptions;
  const receiptArguments = payload?.info?.arguments;
  const bundleArgumentIndex = Array.isArray(receiptArguments)
    ? receiptArguments.indexOf(ACTIVE_BUNDLE_ID)
    : -1;
  const receiptRuntimeArguments = bundleArgumentIndex >= 0
    ? receiptArguments.slice(
      bundleArgumentIndex + 1,
      bundleArgumentIndex + 1 + expectedRuntimeArguments.length,
    )
    : null;
  const launchedExecutableUrl = payload?.result?.process?.executable;
  if (
    !Number.isSafeInteger(pid)
    || pid <= 0
    || captureExecutableUrl === null
    || launchedExecutableUrl !== captureExecutableUrl
    || payload?.result?.deviceIdentifier !== options.deviceId
    || payload?.info?.commandType !== 'devicectl.device.process.launch'
    || launchOptions?.activatedWhenStarted !== true
    || launchOptions?.terminateExistingInstances !== true
    || launchOptions?.startStopped !== false
    || !Array.isArray(actualRuntimeArguments)
    || JSON.stringify(actualRuntimeArguments) !== JSON.stringify(expectedRuntimeArguments)
    || JSON.stringify(receiptRuntimeArguments) !== JSON.stringify(expectedRuntimeArguments)
  ) {
    fail(`${label} launch did not confirm an iOS processIdentifier`);
  }
  launchedGamePids.add(pid);
  return { pid, path };
}

function reactivateCaptureProcess(pid, label) {
  if (captureMethod !== IOS_XCODE_HANDOFF_CAPTURE_METHOD) return null;
  if (
    !Number.isSafeInteger(pid)
    || pid <= 0
    || captureExecutableUrl === null
  ) {
    fail(`${label} capture reactivation target is invalid`);
  }
  quiesceProductionApp(productionAppForCapture, `${label}-production-quiesce`);
  const { payload, path } = runDevicectlJson([
    'device', 'process', 'launch',
    '--device', options.deviceId,
    ACTIVE_BUNDLE_ID,
  ], `${label}-reactivate`, null, 45_000);
  const launchOptions = payload?.result?.launchOptions;
  const reactivatedPid = payload?.result?.process?.processIdentifier
    ?? payload?.result?.processIdentifier;
  if (
    reactivatedPid !== pid
    || payload?.result?.process?.executable !== captureExecutableUrl
    || payload?.result?.deviceIdentifier !== options.deviceId
    || payload?.info?.commandType !== 'devicectl.device.process.launch'
    || launchOptions?.activatedWhenStarted !== true
    || launchOptions?.terminateExistingInstances !== false
    || launchOptions?.startStopped !== false
    || !Array.isArray(launchOptions?.arguments)
    || launchOptions.arguments.length !== 0
  ) {
    fail(`${label} could not bring the capture app back to the foreground on the same PID`);
  }
  const broad = allRunningGameProcesses(`${label}-reactivate-processes`);
  if (
    broad.processes.length !== 1
    || broad.processes[0].processIdentifier !== pid
    || broad.processes[0].executable !== captureExecutableUrl
  ) {
    fail(`${label} a competing MoonlitBeacon process exists after reactivation`);
  }
  return {
    pid,
    launchPath: path,
    launchSha256: fileSha256(path),
    processesPath: broad.path,
    processesSha256: fileSha256(broad.path),
  };
}

function allRunningGameProcesses(label = 'processes', timeout = 30_000) {
  const { payload, path } = runDevicectlJson([
    'device', 'info', 'processes', '--device', options.deviceId,
  ], label, null, timeout);
  const runningProcesses = payload?.result?.runningProcesses;
  if (
    payload?.info?.commandType !== 'devicectl.device.info.processes'
    || payload?.result?.deviceIdentifier !== options.deviceId
    || !Array.isArray(runningProcesses)
  ) {
    fail(`${label} CoreDevice process query identity differs`);
  }
  const processes = runningProcesses.filter((process) => (
    typeof process?.executable === 'string'
    && process.executable.endsWith(`/${APP_NAME}.app/${APP_NAME}`)
  ));
  return { processes, path };
}

function runningGameProcesses(label = 'processes', timeout = 30_000) {
  // The production and isolated capture bundles intentionally share the same
  // executable name. Once the isolated install receipt is known, ask
  // CoreDevice itself to emit evidence for that exact app-container path.
  // Pre-install save snapshots still query every same-named process.
  if (captureExecutableUrl !== null) {
    return exactExecutableProcesses(captureExecutableUrl, label, timeout);
  }
  return allRunningGameProcesses(label, timeout);
}

function terminateGameProcess(pid, label = 'terminate') {
  if (!Number.isSafeInteger(pid) || pid <= 0) {
    fail(`${label} iOS processIdentifier is invalid`);
  }
  return runDevicectlJson([
    'device', 'process', 'terminate',
    '--device', options.deviceId,
    '--pid', String(pid),
  ], `${label}-${pid}`);
}

function terminateGame() {
  const { processes } = runningGameProcesses('processes-before-cleanup');
  for (const process of processes) {
    if (launchedGamePids.has(process.processIdentifier)) {
      terminateGameProcess(process.processIdentifier);
      launchedGamePids.delete(process.processIdentifier);
    }
  }
}

function uninstallIsolatedCaptureApp(label) {
  if (ACTIVE_BUNDLE_ID !== ISOLATED_CAPTURE_BUNDLE_ID) {
    fail(`${label} cannot uninstall the production bundle`);
  }
  const result = runDevicectlJson([
    'device', 'uninstall', 'app',
    '--device', options.deviceId,
    ISOLATED_CAPTURE_BUNDLE_ID,
  ], label, null, 45_000);
  const query = queryInstalledApp(`${label}-verify-absent`);
  if (installedAppOrNull(query.payload, ISOLATED_CAPTURE_BUNDLE_ID) !== null) {
    fail(`${label}: isolated capture bundle still remains`);
  }
  return { resultPath: result.path, verificationPath: query.path };
}

function signalGameProcess(pid, signal, label, timeout = 15_000) {
  if (!Number.isSafeInteger(pid) || pid <= 0) {
    fail(`${label} iOS processIdentifier is invalid`);
  }
  if (![IOS_SIGSTOP, IOS_SIGCONT].includes(signal)) {
    fail(`${label} disallowed iOS process signal: ${signal}`);
  }
  return runDevicectlJson([
    'device', 'process', 'signal',
    '--device', options.deviceId,
    '--pid', String(pid),
    '--signal', String(signal),
  ], `${label}-${pid}`, null, timeout);
}

function captureWithRsd(host, port, output, timeout = 20_000) {
  const result = run(PYMOBILEDEVICE3, [
    'developer', 'dvt', 'screenshot',
    output,
    '--rsd', host, String(port),
  ], { allowFailure: true, timeout });
  if (result.error || result.status !== 0 || !existsSync(output)) {
    rmSync(output, { force: true });
    return {
      ok: false,
      error: result.error?.message
        ?? Buffer.from(result.stderr ?? result.stdout ?? '').toString('utf8').slice(-2_000),
    };
  }
  try {
    const bytes = readFileSync(output);
    const size = pngSize(bytes, `RSD ${host}:${port} screenshot`);
    if (size.width <= size.height) fail('RSD screenshot is not landscape');
    return { ok: true, bytes, size };
  } catch (error) {
    rmSync(output, { force: true });
    return { ok: false, error: error.message };
  }
}

function probeRsdIdentity(host, port, coreDeviceIdentity) {
  const result = run(PYMOBILEDEVICE3, [
    'remote', 'rsd-info',
    '--rsd', host, String(port),
  ], { allowFailure: true, binary: true, timeout: 8_000 });
  if (result.error || result.status !== 0) {
    return {
      ok: false,
      error: result.error?.message ?? `rsd-info exit ${result.status}`,
    };
  }

  const rawJson = Buffer.from(result.stdout ?? Buffer.alloc(0));
  let payload;
  try {
    payload = JSON.parse(rawJson.toString('utf8'));
  } catch {
    // JSON.parse diagnostics can quote arbitrary input. Keep the raw RSD
    // handshake (including serials) out of persisted attempts and logs.
    return { ok: false, error: 'rsd-info JSON parse failed' };
  }
  try {
    return {
      ok: true,
      identity: assertRsdIosDeviceIdentity(payload, coreDeviceIdentity),
      rawJsonSha256: sha256(rawJson),
    };
  } catch (error) {
    return { ok: false, error: error.message };
  }
}

function resolveRsdEndpoint(identity) {
  const host = options.rsdHost ?? identity.rsd_host;
  let candidates;
  if (options.rsdPort) {
    candidates = [options.rsdPort];
  } else {
    const lsof = run('/usr/sbin/lsof', ['-n', '-P', '-iTCP'], {
      allowFailure: true,
      timeout: 15_000,
    });
    candidates = coreDeviceRsdPortCandidates(String(lsof.stdout ?? ''), host);
  }
  if (candidates.length === 0) {
    fail(
      'no CoreDevice RSD port candidates. Keep the Xcode Devices connection and '
      + 'pass the current endpoint with --rsd-host/--rsd-port.',
    );
  }
  const attempts = [];
  for (const port of candidates) {
    const identityProbe = probeRsdIdentity(host, port, identity);
    if (!identityProbe.ok) {
      attempts.push({
        port,
        identity_verified: false,
        screenshot_ok: false,
        error: identityProbe.error,
      });
      continue;
    }
    const path = join(workRoot, `rsd-probe-${port}.png`);
    const attempt = captureWithRsd(host, port, path, 8_000);
    try {
      attempts.push({
        port,
        identity_verified: true,
        screenshot_ok: attempt.ok,
        error: attempt.ok ? null : attempt.error,
      });
      if (!attempt.ok) continue;
      const attemptsPath = join(outputRoot, 'rsd-attempts.json');
      writeJson(attemptsPath, attempts);
      const identityProofPath = join(outputRoot, 'rsd-identity-proof.json');
      writeJson(identityProofPath, {
        schema: 1,
        coredevice_identity_matched: true,
        identity: identityProbe.identity,
        raw_json_sha256: identityProbe.rawJsonSha256,
      });
      return {
        host,
        port,
        preflightSha256: sha256(attempt.bytes),
        preflightSize: attempt.size,
        attemptsPath,
        identity: identityProbe.identity,
        identityRawJsonSha256: identityProbe.rawJsonSha256,
        identityProofPath,
      };
    } finally {
      // This preflight runs before the game is launched and can contain a
      // private home/foreground screen. Delete it even if writing either
      // evidence JSON throws; only its hash and dimensions may survive.
      rmSync(path, { force: true });
    }
  }
  writeJson(join(outputRoot, 'rsd-attempts.json'), attempts);
  fail(
    `could not get a DVT PNG from CoreDevice RSD candidates: ${JSON.stringify(attempts)}. `
      + 'end any leftover pymobiledevice3 sessions and recheck the current endpoint.',
  );
}

function captureRect(state, key, optional = false) {
  const value = state?.[key];
  if (
    !Array.isArray(value)
    || value.length !== 4
    || value.some((component) => typeof component !== 'number' || !Number.isFinite(component))
  ) {
    fail(`${key} is not a finite [x,y,width,height] Rect`);
  }
  const [x, y, width, height] = value;
  if (width <= 0 || height <= 0) {
    if (optional) return null;
    fail(`${key} has no area`);
  }
  return { x, y, width, height, endX: x + width, endY: y + height };
}

function rectContains(outer, inner, tolerance = 0.5) {
  return inner.x >= outer.x - tolerance
    && inner.y >= outer.y - tolerance
    && inner.endX <= outer.endX + tolerance
    && inner.endY <= outer.endY + tolerance;
}

function safeUiGeometry(state, kind) {
  const viewport = captureRect(state, 'viewport_rect');
  const safe = captureRect(state, 'safe_rect');
  if (!rectContains(viewport, safe)) fail(`${kind} safe_rect is outside the viewport`);
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
      ['store_button_rect', 'store_button_inside_safe_area'],
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
  for (const [rectKey, boolKey] of required) {
    const rect = captureRect(state, rectKey);
    if (state[boolKey] !== true || !rectContains(safe, rect)) {
      fail(`${kind} ${rectKey} is not inside the actual safe_rect`);
    }
    controls[rectKey] = [rect.x, rect.y, rect.width, rect.height];
  }
  return {
    viewport_rect: [viewport.x, viewport.y, viewport.width, viewport.height],
    safe_rect: [safe.x, safe.y, safe.width, safe.height],
    logical_insets: {
      left: safe.x - viewport.x,
      top: safe.y - viewport.y,
      right: viewport.endX - safe.endX,
      bottom: viewport.endY - safe.endY,
    },
    controls,
  };
}

function isRetryableCoreDeviceTimeout(error) {
  return error !== null
    && typeof error === 'object'
    && error.code === 'ETIMEDOUT';
}

async function waitFor(
  probe,
  label,
  timeoutMilliseconds,
  retryError = () => false,
) {
  const deadline = Date.now() + timeoutMilliseconds;
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const remainingMs = deadline - Date.now();
      const value = probe({ remainingMs, deadlineMs: deadline });
      if (Date.now() >= deadline) break;
      if (value) return value;
    } catch (error) {
      if (!retryError(error)) throw error;
      lastError = error;
    }
    await sleep(120);
  }
  fail(`${label} was not confirmed within ${timeoutMilliseconds / 1000}s${
    lastError ? ` (${lastError.message})` : ''}`);
}

function armRuntime(locale, kind, extra = {}) {
  disarmFiles([RUNTIME_REQUEST]);
  disarmFiles([RUNTIME_STATE, RUNTIME_TEMP]);
  const nonce = randomBytes(32).toString('hex');
  writeRemote(RUNTIME_REQUEST, `${JSON.stringify({
    nonce,
    kind,
    game_locale: locale.game,
    ...extra,
  })}\n`);
  return nonce;
}

function armBoot(kind, nonce) {
  disarmFiles([BOOT_REQUEST]);
  writeRemote(BOOT_REQUEST, `${JSON.stringify({ schema: 1, nonce, kind })}\n`);
}

async function waitRuntimeState(
  nonce,
  expected,
  afterObservation = 0,
  stableProcessId = null,
) {
  let lastState = null;
  let lastError = null;
  let lastTransportError = null;
  // moonlight_barrage must catch the moment moonlight awakening turns off. On a
  // fast device, kills keep extending awakening so the off window is rare and
  // short — six 45s windows in a row were all still awakened. One suspend poll
  // takes 3–5s, so samples are sparse; widen the window.
  const timeout = expected.kind === 'field_guardian' ? 75_000
    : expected.kind === 'moonlight_barrage' ? 240_000 : 45_000;
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    await sleep(120);
    const remainingMs = deadline - Date.now();
    const minimumReadBudget = stableProcessId === null
      ? DEVICECTL_REMOTE_READ_MIN_TIMEOUT_MS
      : DEVICECTL_STABLE_READ_TIMEOUT_MS + DEVICECTL_STABLE_READ_OVERHEAD_MS;
    if (remainingMs < minimumReadBudget) break;
    let state = null;
    try {
      const readState = () => readRemoteJson(
        RUNTIME_STATE,
        DEVICECTL_POLL_TIMEOUT_MS,
      );
      state = stableProcessId === null
        ? readState()
        : await withSuspendedGameProcess(
          stableProcessId,
          `${expected.kind}-runtime-state-read`,
          async () => readState(),
          DEVICECTL_MIN_TIMEOUT_MS,
        );
    } catch (error) {
      if (!isRetryableCoreDeviceTimeout(error)) throw error;
      lastTransportError = error;
      continue;
    }
    if (Date.now() >= deadline) break;
    if (
      state === null
      || state.nonce !== nonce
      || !Number.isSafeInteger(state.observation)
      || state.observation <= afterObservation
    ) continue;
    lastState = state;
    try {
      const normalized = assertStoreCaptureState(state, expected);
      const safeLayout = safeUiGeometry(state, expected.kind);
      return { raw: state, normalized, safeLayout };
    } catch (error) {
      lastError = error;
    }
    // Once a failed guardian attempt has already advanced into the next
    // cycle, this nonce can never become the requested cycle-3 field scene.
    // Return control to the bounded relaunch loop instead of burning 75s.
    if (
      expected.kind === 'field_guardian'
      && (state.over === true || (Number.isSafeInteger(state.cycle) && state.cycle > 3))
    ) break;
  }
  fail(`${expected.kind} iOS runtime state was not proven${
    lastError ? ` (${lastError.message})` : ''}${
    lastTransportError ? ` (CoreDevice: ${lastTransportError.message})` : ''}${
    lastState ? ` last_state=${JSON.stringify(lastState)}` : ''}`);
}

function armCleanUi(kind) {
  const handshake = CLEAN_UI[kind];
  disarmFiles([handshake.request, handshake.ready]);
  writeRemote(handshake.request, 'armed\n');
}

async function waitCleanUi(kind) {
  const handshake = CLEAN_UI[kind];
  return waitFor(({ remainingMs }) => {
    if (remainingMs < DEVICECTL_REMOTE_READ_MIN_TIMEOUT_MS) return null;
    const proof = readRemote(
      handshake.ready,
      true,
      Math.min(DEVICECTL_POLL_TIMEOUT_MS, remainingMs),
    )?.toString('utf8').trim();
    return proof === handshake.proof ? proof : null;
  }, `${kind} iOS debug UI hide`, 30_000, isRetryableCoreDeviceTimeout);
}

async function assertCleanUi(kind, expectedProof) {
  await waitFor(({ remainingMs }) => {
    if (remainingMs < DEVICECTL_REMOTE_READ_MIN_TIMEOUT_MS) return null;
    const proof = readRemote(
      CLEAN_UI[kind].ready,
      true,
      Math.min(DEVICECTL_POLL_TIMEOUT_MS, remainingMs),
    )?.toString('utf8').trim();
    return proof === expectedProof ? proof : null;
  }, `${kind} clean UI screenshot after proof`, 30_000, isRetryableCoreDeviceTimeout);
}

function assertAppStillInstalled(build, label) {
  const { payload } = queryInstalledApp(label);
  const app = assertInstalledIosApp(payload, {
    bundleId: ACTIVE_BUNDLE_ID,
    shortVersion: build.plist.CFBundleShortVersionString,
    buildVersion: build.plist.CFBundleVersion,
    coreDeviceIdentifier: options.deviceId,
  });
  if (fileSha256(build.artifact) !== build.artifactSha256) {
    fail(`${label}: preserved iOS build artifact changed`);
  }
  return installedAppIdentitySha256(app);
}

const captures = [];
const acceptedScreenshotHashes = new Set();
const launchedGamePids = new Set();
let rsd = null;
let build = null;
let deviceIdentity = null;
let captureExecutableUrl = null;
let productionAppForCapture = null;
// Set before SIGSTOP is sent because a command can fail after the device has
// already acted. Top-level cleanup treats a non-null PID as possibly stopped.
let suspendedGamePid = null;

function suspendGameProcess(pid, label, signalTimeout = 15_000) {
  if (suspendedGamePid !== null) {
    fail(`${label}: an iOS process is already under suspend tracking`);
  }
  if (!Number.isSafeInteger(pid) || pid <= 0) {
    fail(`${label} SIGSTOP target is invalid`);
  }
  suspendedGamePid = pid;
  try {
    signalGameProcess(pid, IOS_SIGSTOP, `${label}-sigstop`, signalTimeout);
  } catch (operationFailure) {
    let cleanupFailure = null;
    try {
      signalGameProcess(
        pid,
        IOS_SIGCONT,
        `${label}-sigcont-after-failed-sigstop`,
        DEVICECTL_MIN_TIMEOUT_MS,
      );
      suspendedGamePid = null;
    } catch (error) {
      cleanupFailure = error;
    }
    const cleanupMessage = cleanupFailure === null
      ? ''
      : `; best-effort SIGCONT failed: ${cleanupFailure.message}`;
    throw new Error(
      `${label} could not confirm SIGSTOP result; aborting the run: ${operationFailure.message}`
        + cleanupMessage,
      { cause: cleanupFailure ?? operationFailure },
    );
  }
}

function resumeGameProcess(pid, label, signalTimeout = 15_000) {
  if (suspendedGamePid !== pid) {
    fail(`${label} SIGCONT target differs from the tracked iOS process`);
  }
  signalGameProcess(pid, IOS_SIGCONT, `${label}-sigcont`, signalTimeout);
  suspendedGamePid = null;
}

async function withSuspendedGameProcess(
  pid,
  label,
  operation,
  signalTimeout = 15_000,
) {
  if (typeof operation !== 'function') fail(`${label} suspend-window operation is not a function`);
  suspendGameProcess(pid, label, signalTimeout);
  const settlement = await settleWithMandatoryCleanup(
    operation,
    async () => resumeGameProcess(pid, label, signalTimeout),
  );
  if (settlement.cleanupFailure !== null) {
    const operationMessage = settlement.operationFailure === null
      ? ''
      : `; original operation failed: ${settlement.operationFailure.message}`;
    throw new Error(
      `${label} SIGCONT failed afterward: ${settlement.cleanupFailure.message}`
        + operationMessage,
      { cause: settlement.cleanupFailure },
    );
  }
  if (settlement.operationFailure !== null) throw settlement.operationFailure;
  return settlement.value;
}

function assertXcodeHandoffContinuity(processId, label, timeoutMs = 30_000) {
  if (deviceIdentity === null) fail('verified CoreDevice identity is missing');
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < DEVICECTL_MIN_TIMEOUT_MS * 2) {
    fail(`${label} continuity probe timeout budget is insufficient`);
  }
  const deadline = Date.now() + timeoutMs;
  const detailsBudget = Math.max(
    DEVICECTL_MIN_TIMEOUT_MS,
    Math.min(10_000, Math.floor(timeoutMs / 2)),
  );
  const details = runDevicectlJson([
    'device', 'info', 'details', '--device', options.deviceId,
  ], `${label}-device-details`, null, detailsBudget);
  const currentIdentity = assertPhysicalIosDevice(details.payload, {
    target: options.target,
    coreDeviceIdentifier: options.deviceId,
    usbUdid: options.usbUdid,
  });
  if (JSON.stringify(currentIdentity) !== JSON.stringify(deviceIdentity)) {
    fail(`${label}: CoreDevice identity changed`);
  }
  const remainingMs = deadline - Date.now();
  if (remainingMs <= 0) fail(`${label} continuity probe deadline expired`);
  // This broad proof intentionally includes both the production and isolated
  // bundles. The exact capture filter used by ordinary state polling must not
  // hide a second MoonlitBeacon that could compete for the framebuffer.
  const processes = allRunningGameProcesses(`${label}-processes`, remainingMs);
  if (
    processes.processes.length !== 1
    || processes.processes[0].processIdentifier !== processId
  ) {
    fail(`${label}: foreground game process PID changed`);
  }
  return {
    processId,
    deviceDetailsPath: details.path,
    deviceDetailsSha256: fileSha256(details.path),
    processesPath: processes.path,
    processesSha256: fileSha256(processes.path),
  };
}

async function nativeScreenshot(path, {
  assetLocale,
  captureName,
  processId,
  activation = null,
}) {
  if (captureMethod === IOS_RSD_CAPTURE_METHOD) {
    if (rsd === null) fail('verified RSD endpoint is missing');
    const temporary = `${path}.partial-${process.pid}`;
    const result = captureWithRsd(rsd.host, rsd.port, temporary, 30_000);
    if (!result.ok) fail(`DVT native screenshot failed: ${result.error}`);
    renameSync(temporary, path);
    sealPrivateRegularFile(path);
    return result;
  }
  if (xcodeScreenshotInbox === null) fail('verified Xcode screenshot inbox is missing');
  if (activation === null || activation.pid !== processId) {
    fail('missing proof that the capture app was foreground-reactivated before the Xcode screenshot');
  }
  if (!Number.isSafeInteger(processId) || processId <= 0) {
    fail('Xcode screenshot handoff game process PID is invalid');
  }

  // This deadline covers both CoreDevice continuity proofs as well as the
  // operator handoff. Because the caller holds the game under SIGSTOP for this
  // operation, no child command may get a fresh timeout beyond this budget.
  const handoffDeadlineMs = Date.now() + XCODE_HANDOFF_DEADLINE_MS;
  const remainingHandoffBudget = (label) => {
    const remainingMs = handoffDeadlineMs - Date.now();
    if (remainingMs < 200) fail(`${label} Xcode screenshot hard deadline expired`);
    return remainingMs;
  };
  const continuityBefore = assertXcodeHandoffContinuity(
    processId,
    `${captureName}-xcode-handoff-before`,
    remainingHandoffBudget(`${captureName}-xcode-handoff-before`),
  );
  const nonce = randomBytes(32).toString('hex');
  const expectedFilename = `moonlit-${nonce}.png`;
  const requestedAtMs = Date.now();
  const handoffWaitTimeoutMs = remainingHandoffBudget(
    `${captureName}-xcode-handoff-request`,
  );
  const expectedPath = join(xcodeScreenshotInbox.path, expectedFilename);
  const receiptPath = `${expectedPath}.receipt.json`;
  process.stdout.write(`${JSON.stringify({
    schema: 1,
    event: 'xcode_screenshot_requested',
    capture_method: IOS_XCODE_HANDOFF_CAPTURE_METHOD,
    nonce,
    target: options.target,
    asset_locale: assetLocale,
    capture_name: captureName,
    expected_filename: expectedFilename,
    expected_path: expectedPath,
    receipt_path: receiptPath,
    expected_width: IOS_XCODE_IPAD_LANDSCAPE_SIZE.width,
    expected_height: IOS_XCODE_IPAD_LANDSCAPE_SIZE.height,
    required_mode: '0600',
    required_delivery: 'publisher-script-fsync-partial-atomic-rename-receipt',
    publisher_argv: [
      process.execPath,
      'scripts/publish-xcode-screenshot-handoff.mjs',
      '--source', '<XCODE_SCREENSHOT_PNG>',
      '--inbox', xcodeScreenshotInbox.path,
      '--expected-filename', expectedFilename,
      '--nonce', nonce,
      '--requested-at-ms', String(requestedAtMs),
    ],
    requested_at: new Date(requestedAtMs).toISOString(),
    timeout_seconds: Math.ceil(handoffWaitTimeoutMs / 1_000),
  })}\n`);

  let handoff = null;
  try {
    handoff = await waitForXcodeScreenshotHandoff({
      inbox: xcodeScreenshotInbox,
      expectedFilename,
      nonce,
      requestedAtMs,
      forbiddenSha256: acceptedScreenshotHashes,
      timeoutMs: handoffWaitTimeoutMs,
      continuityProbe: ({ remainingMs }) => (
        remainingMs < DEVICECTL_MIN_TIMEOUT_MS * 2
          ? null
          : assertXcodeHandoffContinuity(
            processId,
            `${captureName}-xcode-handoff-wait`,
            remainingMs,
          )
      ),
      cancellationProbe: () => deferredCancellation.throwIfRequested(),
    });
    const continuityAfter = assertXcodeHandoffContinuity(
      processId,
      `${captureName}-xcode-handoff-after`,
      remainingHandoffBudget(`${captureName}-xcode-handoff-after`),
    );
    writePrivateFileExclusive(path, handoff.bytes);
    if (fileSha256(path) !== handoff.sha256) {
      fail('could not byte-exact copy the Xcode screenshot handoff into private evidence');
    }
    remainingHandoffBudget(`${captureName}-xcode-handoff-copy`);
    acceptedScreenshotHashes.add(handoff.sha256);
    return {
      ok: true,
      bytes: handoff.bytes,
      size: handoff.size,
      handoff: {
        nonce,
        expectedFilename,
        requestedAtMs,
        birthtimeMs: handoff.birthtimeMs,
        mtimeMs: handoff.mtimeMs,
        acceptedAtMs: Date.now(),
        stable_observations: 2,
        complete_png_decoded: true,
        receipt: handoff.receipt,
        receipt_sha256: sha256(handoff.receiptBytes),
        activation,
        continuityBefore,
        continuityAfter,
      },
    };
  } finally {
    removeXcodeScreenshotHandoffEntries({
      inbox: xcodeScreenshotInbox,
      expectedFilename,
      nonce,
    });
  }
}

function screenshotTransportEvidence(screenshot) {
  if (captureMethod === IOS_RSD_CAPTURE_METHOD) {
    return {
      capture_method: IOS_RSD_CAPTURE_METHOD,
      rsd_host: rsd.host,
      rsd_port: rsd.port,
      xcode_handoff_nonce: null,
      xcode_handoff_expected_filename: null,
      xcode_handoff_requested_at: null,
      xcode_handoff_requested_at_unix_ms: null,
      xcode_handoff_birthtime_unix_ms: null,
      xcode_handoff_mtime_unix_ms: null,
      xcode_handoff_accepted_at: null,
      xcode_handoff_stable_observations: null,
      xcode_handoff_complete_png_decoded: null,
      xcode_handoff_receipt: null,
      xcode_handoff_receipt_sha256: null,
      xcode_activation_process_id: null,
      xcode_activation_launch_path: null,
      xcode_activation_launch_sha256: null,
      xcode_activation_processes_path: null,
      xcode_activation_processes_sha256: null,
      xcode_handoff_process_id: null,
      xcode_handoff_device_details_before_path: null,
      xcode_handoff_device_details_before_sha256: null,
      xcode_handoff_processes_before_path: null,
      xcode_handoff_processes_before_sha256: null,
      xcode_handoff_device_details_after_path: null,
      xcode_handoff_device_details_after_sha256: null,
      xcode_handoff_processes_after_path: null,
      xcode_handoff_processes_after_sha256: null,
    };
  }
  const handoff = screenshot.handoff;
  if (handoff === null || typeof handoff !== 'object') {
    fail('Xcode screenshot handoff proof is missing');
  }
  return {
    capture_method: IOS_XCODE_HANDOFF_CAPTURE_METHOD,
    rsd_host: null,
    rsd_port: null,
    xcode_handoff_nonce: handoff.nonce,
    xcode_handoff_expected_filename: handoff.expectedFilename,
    xcode_handoff_requested_at: new Date(handoff.requestedAtMs).toISOString(),
    xcode_handoff_requested_at_unix_ms: handoff.requestedAtMs,
    xcode_handoff_birthtime_unix_ms: handoff.birthtimeMs,
    xcode_handoff_mtime_unix_ms: handoff.mtimeMs,
    xcode_handoff_accepted_at: new Date(handoff.acceptedAtMs).toISOString(),
    xcode_handoff_stable_observations: handoff.stable_observations,
    xcode_handoff_complete_png_decoded: handoff.complete_png_decoded,
    xcode_handoff_receipt: handoff.receipt,
    xcode_handoff_receipt_sha256: handoff.receipt_sha256,
    xcode_activation_process_id: handoff.activation.pid,
    xcode_activation_launch_path: relative(
      REPO_ROOT,
      handoff.activation.launchPath,
    ),
    xcode_activation_launch_sha256: handoff.activation.launchSha256,
    xcode_activation_processes_path: relative(
      REPO_ROOT,
      handoff.activation.processesPath,
    ),
    xcode_activation_processes_sha256: handoff.activation.processesSha256,
    xcode_handoff_process_id: handoff.continuityBefore.processId,
    xcode_handoff_device_details_before_path: relative(
      REPO_ROOT,
      handoff.continuityBefore.deviceDetailsPath,
    ),
    xcode_handoff_device_details_before_sha256:
      handoff.continuityBefore.deviceDetailsSha256,
    xcode_handoff_processes_before_path: relative(
      REPO_ROOT,
      handoff.continuityBefore.processesPath,
    ),
    xcode_handoff_processes_before_sha256:
      handoff.continuityBefore.processesSha256,
    xcode_handoff_device_details_after_path: relative(
      REPO_ROOT,
      handoff.continuityAfter.deviceDetailsPath,
    ),
    xcode_handoff_device_details_after_sha256:
      handoff.continuityAfter.deviceDetailsSha256,
    xcode_handoff_processes_after_path: relative(
      REPO_ROOT,
      handoff.continuityAfter.processesPath,
    ),
    xcode_handoff_processes_after_sha256:
      handoff.continuityAfter.processesSha256,
  };
}

async function captureRuntime(
  filename,
  locale,
  nonce,
  expected,
  cleanKind,
  prepared = null,
) {
  const name = filename.replace(/\.png$/u, '');
  let before;
  let cleanUiProof;
  let processBefore;
  let installedBefore;
  if (prepared === null) {
    processBefore = runningGameProcesses(`${name}-process-before`).processes;
    if (processBefore.length !== 1) {
      fail(`${name} does not have exactly one game process beforehand`);
    }
    before = await waitRuntimeState(
      nonce,
      expected,
      0,
      processBefore[0].processIdentifier,
    );
    armCleanUi(cleanKind);
    cleanUiProof = await waitCleanUi(cleanKind);
    installedBefore = assertAppStillInstalled(build, `${name}-installed-before`);
  } else {
    ({
      before,
      cleanUiProof,
      processBefore,
      installedBefore,
    } = prepared);
  }
  if (processBefore.length !== 1) fail(`${name} does not have exactly one game process beforehand`);
  const localeRoot = join(outputRoot, 'captures', locale.asset);
  ensurePrivateDirectory(localeRoot);
  const path = join(localeRoot, filename);
  const suspendDuringScreenshot = prepared?.suspendDuringScreenshot === true
    || captureMethod === IOS_XCODE_HANDOFF_CAPTURE_METHOD;
  let activation = null;
  if (captureMethod === IOS_XCODE_HANDOFF_CAPTURE_METHOD) {
    activation = reactivateCaptureProcess(
      processBefore[0].processIdentifier,
      `${name}-foreground`,
    );
    const activationBaseline = await waitRuntimeState(
      nonce,
      expected,
      0,
      processBefore[0].processIdentifier,
    );
    const foregroundState = await waitRuntimeState(
      nonce,
      expected,
      activationBaseline.raw.observation,
      processBefore[0].processIdentifier,
    );
    assertStableStoreCaptureState(
      activationBaseline.raw,
      foregroundState.raw,
      expected,
    );
    before = foregroundState;
  }
  const screenshot = suspendDuringScreenshot
    ? await withSuspendedGameProcess(
      processBefore[0].processIdentifier,
      `${name}-native-screenshot`,
      async () => nativeScreenshot(path, {
        assetLocale: locale.asset,
        captureName: name,
        processId: processBefore[0].processIdentifier,
        activation,
      }),
    )
    : await nativeScreenshot(path, {
      assetLocale: locale.asset,
      captureName: name,
      processId: processBefore[0].processIdentifier,
      activation,
    });
  const after = await waitRuntimeState(
    nonce,
    expected,
    before.raw.observation,
    processBefore[0].processIdentifier,
  );
  await assertCleanUi(cleanKind, cleanUiProof);
  assertStableStoreCaptureState(before.raw, after.raw, expected);
  const processAfter = runningGameProcesses(`${name}-process-after`).processes;
  if (
    processAfter.length !== 1
    || processAfter[0].processIdentifier !== processBefore[0].processIdentifier
  ) {
    fail(`${name} game process PID was not preserved across the screenshot`);
  }
  const installedAfter = assertAppStillInstalled(build, `${name}-installed-after`);
  if (installedBefore !== installedAfter) fail(`${name} installed app identity changed during the screenshot`);
  const physicalSafeLayout = assertPhysicalIosSafeLayout(
    before.safeLayout,
    screenshot.size,
  );
  const proofPath = join(localeRoot, `${name}.proof.json`);
  writeJson(proofPath, { before: before.raw, after: after.raw });
  captures.push({
    name,
    filename,
    asset_locale: locale.asset,
    game_locale: locale.game,
    evidence_path: relative(REPO_ROOT, path),
    proof_path: relative(REPO_ROOT, proofPath),
    kind: expected.kind,
    boot_kind: expected.bootKind ?? null,
    runtime_nonce: nonce,
    clean_ui_proof: cleanUiProof,
    width: screenshot.size.width,
    height: screenshot.size.height,
    sha256: sha256(screenshot.bytes),
    native_device_framebuffer: true,
    ...screenshotTransportEvidence(screenshot),
    installed_artifact_sha256: build.artifactSha256,
    installed_identity_sha256: installedAfter,
    runtime_before: before.raw,
    runtime_after: after.raw,
    safe_layout: before.safeLayout,
    physical_safe_layout: physicalSafeLayout,
    captured_at: new Date().toISOString(),
  });
  disarmFiles([
    RUNTIME_REQUEST,
    RUNTIME_STATE,
    RUNTIME_TEMP,
    CLEAN_UI[cleanKind].request,
    CLEAN_UI[cleanKind].ready,
  ]);
}

function discardUnpublishedCapture(filename, locale) {
  const name = filename.replace(/\.png$/u, '');
  const localeRoot = join(outputRoot, 'captures', locale.asset);
  for (const path of [
    join(localeRoot, filename),
    join(localeRoot, `${filename}.partial-${process.pid}`),
    join(localeRoot, `${name}.proof.json`),
  ]) rmSync(path, { force: true });
}

async function captureGuardian(locale) {
  const expected = {
    kind: 'field_guardian',
    gameLocale: locale.game,
    bootKind: 'field_guardian',
  };
  // No old process may consume the pre-armed clean-UI handshake. Prepare every
  // slow CoreDevice check before waiting for the short-lived Lv20 guardian,
  // then freeze only that exact PID while DVT obtains the native framebuffer.
  terminateGame();
  disarmAllControls();
  armCleanUi('combat');
  const nonce = armRuntime(locale, 'field_guardian');
  armBoot('field_guardian', nonce);
  await cancellationCheckpoint();
  const installedBefore = assertAppStillInstalled(
    build,
    `${SCREENSHOTS.guardian}-installed-before-launch`,
  );
  const launched = launchApp(`${locale.asset}-guardian`);
  await cancellationCheckpoint();
  const processBefore = runningGameProcesses(
    `${SCREENSHOTS.guardian}-process-before-ready`,
  ).processes;
  if (
    processBefore.length !== 1
    || processBefore[0].processIdentifier !== launched.pid
  ) {
    fail('field_guardian launch PID differs from the foreground game process');
  }
  const cleanUiProof = await waitCleanUi('combat');
  const before = await waitRuntimeState(nonce, expected, 0, launched.pid);
  try {
    await captureRuntime(
      SCREENSHOTS.guardian,
      locale,
      nonce,
      expected,
      'combat',
      {
        before,
        cleanUiProof,
        processBefore,
        installedBefore,
        suspendDuringScreenshot: true,
      },
    );
  } catch (error) {
    discardUnpublishedCapture(SCREENSHOTS.guardian, locale);
    throw error;
  }
}

async function captureMissileCore(filename, locale, bootNonce, runtimeNonce) {
  const name = filename.replace(/\.png$/u, '');
  const runtimeExpected = { kind: 'arena_ready', gameLocale: locale.game };
  const processBefore = runningGameProcesses(`${name}-process-before`).processes;
  if (processBefore.length !== 1) {
    fail('missile_core does not have exactly one game process beforehand');
  }
  let missileBefore = null;
  let lastError = null;
  let lastTransportError = null;
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    await sleep(120);
    const remainingMs = deadline - Date.now();
    if (remainingMs < DEVICECTL_REMOTE_READ_MIN_TIMEOUT_MS) break;
    let candidate = null;
    try {
      candidate = readRemoteJson(
        MISSILE_STATE,
        Math.min(DEVICECTL_POLL_TIMEOUT_MS, remainingMs),
      );
    } catch (error) {
      if (!isRetryableCoreDeviceTimeout(error)) throw error;
      lastTransportError = error;
      continue;
    }
    if (Date.now() >= deadline) break;
    if (candidate === null) continue;
    try {
      assertMissileCoreCaptureState(candidate, { gameLocale: locale.game });
      missileBefore = candidate;
      break;
    } catch (error) {
      lastError = error;
    }
  }
  if (missileBefore === null) {
    fail(`missile_core iOS state was not proven${
      lastError ? ` (${lastError.message})` : ''}${
      lastTransportError ? ` (CoreDevice: ${lastTransportError.message})` : ''}`);
  }
  armCleanUi('combat');
  const cleanUiProof = await waitCleanUi('combat');
  // Bind the before-state to the already staged core ejection and settled HUD.
  // Capturing it at initial arena readiness races the level/banner layout that
  // the missile event intentionally changes on slower physical devices.
  let runtimeBefore = await waitRuntimeState(
    runtimeNonce,
    runtimeExpected,
    0,
    processBefore[0].processIdentifier,
  );
  const installedBefore = assertAppStillInstalled(build, `${name}-installed-before`);
  const localeRoot = join(outputRoot, 'captures', locale.asset);
  ensurePrivateDirectory(localeRoot);
  const path = join(localeRoot, filename);
  let activation = null;
  if (captureMethod === IOS_XCODE_HANDOFF_CAPTURE_METHOD) {
    activation = reactivateCaptureProcess(
      processBefore[0].processIdentifier,
      `${name}-foreground`,
    );
    const activationBaseline = await waitRuntimeState(
      runtimeNonce,
      runtimeExpected,
      0,
      processBefore[0].processIdentifier,
    );
    const foregroundState = await waitRuntimeState(
      runtimeNonce,
      runtimeExpected,
      activationBaseline.raw.observation,
      processBefore[0].processIdentifier,
    );
    assertStableIosArenaCaptureState(
      activationBaseline.raw,
      foregroundState.raw,
      runtimeExpected,
    );
    runtimeBefore = foregroundState;
  }
  const screenshotOperation = async () => nativeScreenshot(path, {
    assetLocale: locale.asset,
    captureName: name,
    processId: processBefore[0].processIdentifier,
    activation,
  });
  const screenshot = captureMethod === IOS_XCODE_HANDOFF_CAPTURE_METHOD
    ? await withSuspendedGameProcess(
      processBefore[0].processIdentifier,
      `${name}-native-screenshot`,
      screenshotOperation,
    )
    : await screenshotOperation();
  await assertCleanUi('combat', cleanUiProof);
  const missileAfter = await waitFor(
    ({ remainingMs }) => (
      remainingMs < DEVICECTL_REMOTE_READ_MIN_TIMEOUT_MS
        ? null
        : readRemoteJson(
          MISSILE_STATE,
          Math.min(DEVICECTL_POLL_TIMEOUT_MS, remainingMs),
        )
    ),
    'missile_core iOS screenshot after state',
    30_000,
    isRetryableCoreDeviceTimeout,
  );
  assertStableMissileCoreCaptureState(
    missileBefore,
    missileAfter,
    { gameLocale: locale.game },
  );
  // Godot proves the in-game locale while the capture harness owns the store
  // asset locale. Publish one combined object in both the proof and report so
  // downstream validation can bind the native frame to its localized listing.
  const missileBeforeProof = {
    ...missileBefore,
    asset_locale: locale.asset,
  };
  const missileAfterProof = {
    ...missileAfter,
    asset_locale: locale.asset,
  };
  const runtimeAfter = await waitRuntimeState(
    runtimeNonce,
    runtimeExpected,
    runtimeBefore.raw.observation,
    processBefore[0].processIdentifier,
  );
  assertStableIosArenaCaptureState(
    runtimeBefore.raw,
    runtimeAfter.raw,
    runtimeExpected,
  );
  const processAfter = runningGameProcesses(`${name}-process-after`).processes;
  if (
    processAfter.length !== 1
    || processAfter[0].processIdentifier !== processBefore[0].processIdentifier
  ) {
    fail('missile_core game process PID was not preserved across the screenshot');
  }
  const installedAfter = assertAppStillInstalled(build, `${name}-installed-after`);
  if (installedBefore !== installedAfter) {
    fail('missile_core installed app identity changed during the screenshot');
  }
  const physicalSafeLayout = assertPhysicalIosSafeLayout(
    runtimeBefore.safeLayout,
    screenshot.size,
  );
  const proofPath = join(localeRoot, `${name}.proof.json`);
  writeJson(proofPath, {
    before: missileBeforeProof,
    after: missileAfterProof,
    runtime_before: runtimeBefore.raw,
    runtime_after: runtimeAfter.raw,
  });
  captures.push({
    name,
    filename,
    asset_locale: locale.asset,
    game_locale: locale.game,
    evidence_path: relative(REPO_ROOT, path),
    proof_path: relative(REPO_ROOT, proofPath),
    kind: 'missile_core_recovery',
    boot_kind: 'missile_core',
    boot_nonce: bootNonce,
    runtime_nonce: runtimeNonce,
    clean_ui_proof: cleanUiProof,
    width: screenshot.size.width,
    height: screenshot.size.height,
    sha256: sha256(screenshot.bytes),
    native_device_framebuffer: true,
    ...screenshotTransportEvidence(screenshot),
    installed_artifact_sha256: build.artifactSha256,
    installed_identity_sha256: installedAfter,
    runtime_before: runtimeBefore.raw,
    runtime_after: runtimeAfter.raw,
    safe_layout: runtimeBefore.safeLayout,
    physical_safe_layout: physicalSafeLayout,
    missile_before: missileBeforeProof,
    missile_after: missileAfterProof,
    captured_at: new Date().toISOString(),
  });
  disarmFiles([
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

async function captureLocale(locale) {
  disarmAllControls();
  const titleNonce = armRuntime(locale, 'title');
  await cancellationCheckpoint();
  launchApp(`${locale.asset}-title`);
  await cancellationCheckpoint();
  await captureRuntime(
    SCREENSHOTS.title,
    locale,
    titleNonce,
    { kind: 'title', gameLocale: locale.game, directDistribution: false },
    'title',
  );

  const shrineNonce = armRuntime(locale, 'shrine');
  await captureRuntime(
    SCREENSHOTS.shrine,
    locale,
    shrineNonce,
    { kind: 'shrine', gameLocale: locale.game },
    'title',
  );

  const heroNonce = armRuntime(locale, 'hero_preview', { hero_path: HERO_PATH });
  await captureRuntime(
    SCREENSHOTS.hero,
    locale,
    heroNonce,
    { kind: 'hero_preview', gameLocale: locale.game, heroPath: HERO_PATH },
    'title',
  );

  disarmAllControls();
  const barrageNonce = armRuntime(locale, 'moonlight_barrage');
  armBoot('moonlight_barrage', barrageNonce);
  await cancellationCheckpoint();
  launchApp(`${locale.asset}-barrage`);
  await cancellationCheckpoint();
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

  disarmAllControls();
  const missileRuntimeNonce = armRuntime(locale, 'arena_ready');
  const missileBootNonce = randomBytes(32).toString('hex');
  armBoot('missile_core', missileBootNonce);
  writeRemote(MISSILE_REQUEST, 'armed\n');
  await cancellationCheckpoint();
  launchApp(`${locale.asset}-missile`);
  await cancellationCheckpoint();
  await captureMissileCore(
    SCREENSHOTS.missile,
    locale,
    missileBootNonce,
    missileRuntimeNonce,
  );

  await captureGuardian(locale);
}

function restorePersistentFiles(original) {
  const observed = persistentSnapshot(true);
  const mutated = [];
  const names = new Set([
    ...PERSISTENT_FILES,
    ...Object.keys(original),
    ...Object.keys(observed),
  ]);
  for (const name of [...names].sort()) {
    const originalBytes = snapshotValue(original, name);
    const observedBytes = snapshotValue(observed, name);
    try {
      assertByteExactRestoration(originalBytes, observedBytes, name);
    } catch {
      mutated.push(name);
      if (originalBytes === null) {
        if (!existsSync(PYMOBILEDEVICE3)) {
          fail(`${name}: pymobiledevice3 for restoring the absent state was not found`);
        }
        if (rsd === null) {
          fail('production save delete restoration is only allowed for verified RSD capture');
        }
        const result = run(PYMOBILEDEVICE3, [
          'apps', 'rm',
          '--rsd', rsd.host, String(rsd.port),
          '--documents',
          ACTIVE_BUNDLE_ID,
          name,
        ], { allowFailure: true, timeout: 20_000 });
        if (result.status !== 0) fail(`${name} could not restore the absent state`);
      } else {
        writeRemote(name, originalBytes);
      }
    }
  }
  const restored = persistentSnapshot(true);
  for (const name of [...names].sort()) {
    assertByteExactRestoration(
      snapshotValue(original, name),
      snapshotValue(restored, name),
      name,
    );
  }
  return { observed, restored, mutated, files: [...names].sort() };
}

function captureFilesAreCurrent() {
  for (const capture of captures) {
    const path = join(REPO_ROOT, capture.evidence_path);
    const bytes = readFileSync(path);
    const size = pngSize(bytes, capture.evidence_path);
    if (
      sha256(bytes) !== capture.sha256
      || size.width !== capture.width
      || size.height !== capture.height
    ) {
      fail(`timestamp iOS capture changed after recording: ${capture.evidence_path}`);
    }
  }
}

function canonicalCapturePath(capture) {
  return `builds/shots/store-platform/ios/${options.target}`
    + `/${capture.asset_locale}/${capture.filename}`;
}

function publishCanonicalAtomically(report) {
  const parent = join(REPO_ROOT, 'builds/shots/store-platform/ios');
  const canonicalRoot = join(parent, options.target);
  const stagingRoot = join(parent, `.${options.target}-staging-${runId}`);
  if (existsSync(canonicalRoot)) {
    fail(`cannot overwrite existing canonical iOS device assets: ${canonicalRoot}`);
  }
  if (existsSync(stagingRoot)) fail(`iOS canonical staging already exists: ${stagingRoot}`);
  mkdirSync(stagingRoot, { recursive: true });
  for (const capture of captures) {
    const localeRoot = join(stagingRoot, capture.asset_locale);
    mkdirSync(localeRoot, { recursive: true });
    const destination = join(localeRoot, capture.filename);
    copyFileSync(
      join(REPO_ROOT, capture.evidence_path),
      destination,
      constants.COPYFILE_EXCL,
    );
    if (fileSha256(destination) !== capture.sha256) {
      fail(`iOS canonical staging PNG hash differs: ${capture.filename}`);
    }
  }
  writeJson(join(stagingRoot, 'capture-report.json'), report);
  renameSync(stagingRoot, canonicalRoot);
  for (const capture of captures) {
    const published = join(canonicalRoot, capture.asset_locale, capture.filename);
    if (fileSha256(published) !== capture.sha256) {
      fail(`iOS canonical PNG hash differs after atomic publish: ${published}`);
    }
  }
  return join(canonicalRoot, 'capture-report.json');
}

async function main() {
  const canonicalRoot = join(
    REPO_ROOT,
    'builds/shots/store-platform/ios',
    options.target,
  );
  if (options.allLocales && existsSync(canonicalRoot)) {
    fail(`review and archive the existing canonical iOS captures first: ${canonicalRoot}`);
  }

  const deviceDetailsPath = join(outputRoot, 'device-details.json');
  const details = runDevicectlJson([
    'device', 'info', 'details', '--device', options.deviceId,
  ], 'device-details', deviceDetailsPath);
  const identity = assertPhysicalIosDevice(details.payload, {
    target: options.target,
    coreDeviceIdentifier: options.deviceId,
    usbUdid: options.usbUdid,
  });
  deviceIdentity = identity;
  await cancellationCheckpoint();

  if (captureMethod === IOS_RSD_CAPTURE_METHOD) {
    // Prove the deletion/screenshot transport before install or launch can
    // touch the app container. The temporary framebuffer is deleted in
    // resolveRsdEndpoint because it can show a private foreground screen.
    rsd = resolveRsdEndpoint(identity);
    await cancellationCheckpoint();
  }

  let productionAppBefore = null;
  let productionAppAfter = null;
  let productionAppBeforePath = null;
  let productionAppAfterPath = null;
  let isolatedCaptureBundleRemoved = false;
  productionAppBeforePath = join(outputRoot, 'production-app-before.json');
  const productionBeforeQuery = queryInstalledApp(
    'production-app-before',
    productionAppBeforePath,
    PRODUCTION_BUNDLE_ID,
  );
  productionAppBefore = installedAppIdentity(
    productionBeforeQuery.payload,
    PRODUCTION_BUNDLE_ID,
  );
  productionAppForCapture = productionAppBefore;
  await cancellationCheckpoint();
  quiesceProductionApp(productionAppBefore, 'production-quiesce-before-build');
  await cancellationCheckpoint();
  const staleCaptureQuery = queryInstalledApp('isolated-capture-before-preclean');
  await cancellationCheckpoint();
  if (installedAppOrNull(staleCaptureQuery.payload) !== null) {
    uninstallIsolatedCaptureApp('isolated-capture-preclean');
    await cancellationCheckpoint();
  }
  assertGameNotRunning('processes-before-local-build');
  await cancellationCheckpoint();
  // Build work can take minutes but does not touch the device. Finish it before
  // taking the two stable save snapshots so user data cannot go stale while
  // Xcode is still running.
  build = buildFreshDebugApp();
  await cancellationCheckpoint();
  quiesceProductionApp(productionAppBefore, 'production-quiesce-after-build');
  await cancellationCheckpoint();
  const beforeInstallPath = join(outputRoot, 'installed-before.json');
  const installedBeforeQuery = queryInstalledApp('installed-before', beforeInstallPath);
  await cancellationCheckpoint();
  const appInstalledBefore = installedAppOrNull(installedBeforeQuery.payload) !== null;
  if (appInstalledBefore) {
    fail('isolated iOS capture bundle still remains after preclean');
  }
  const persistentBefore = stablePersistentSnapshot(appInstalledBefore);
  await cancellationCheckpoint();

  const selectedLocales = options.allLocales
    ? LOCALES
    : [LOCALES.find(({ asset }) => asset === options.locale)];
  let finalProcessEvidence = null;
  let deviceMutationStarted = false;
  let installEvidence = null;
  let restore = null;
  const restorationErrors = [];
  const settlement = await settleWithMandatoryCleanup(
    async () => {
      assertGameNotRunning('processes-immediately-before-install');
      await cancellationCheckpoint();
      // The install command can mutate the device even when its verification
      // later throws, so arm the cleanup boundary before invoking it.
      deviceMutationStarted = true;
      installEvidence = installFreshApp(build);
      await cancellationCheckpoint();
      captureExecutableUrl = installEvidence.executableUrl;
      disarmPersistentTestHero(persistentBefore);
      disarmAllControls();
      await cancellationCheckpoint();
      for (const locale of selectedLocales) await captureLocale(locale);
      quiesceProductionApp(
        productionAppForCapture,
        'production-quiesce-at-capture-end',
      );
      finalProcessEvidence = allRunningGameProcesses('processes-at-capture-end');
      const finalProcess = finalProcessEvidence.processes[0];
      if (
        finalProcessEvidence.processes.length !== 1
        || finalProcess?.executable !== captureExecutableUrl
        || !launchedGamePids.has(finalProcess?.processIdentifier)
      ) {
        fail('there is not exactly one game process right after the final iOS capture');
      }
    },
    async () => {
      cleanupInProgress = true;
      try {
        if (!deviceMutationStarted) return;
        // withSuspendedGameProcess already resumes in finally. This is the
        // second safety net for a CoreDevice command that failed after SIGSTOP
        // reached the device. If resume itself fails, terminate that exact PID
        // without depending on a separate app-container query.
        if (suspendedGamePid !== null) {
          const possiblyStoppedPid = suspendedGamePid;
          try {
            resumeGameProcess(possiblyStoppedPid, 'top-level-cleanup');
          } catch (error) {
            restorationErrors.push(`resume: ${error.message}`);
            try {
              terminateGameProcess(possiblyStoppedPid, 'emergency-terminate');
              suspendedGamePid = null;
            } catch (terminateError) {
              restorationErrors.push(`emergency-terminate: ${terminateError.message}`);
            }
          }
        }
        let appAvailableForCleanup = false;
        let appCleanupQueryFailed = false;
        try {
          const cleanupQuery = queryInstalledApp('installed-before-cleanup');
          appAvailableForCleanup = installedAppOrNull(cleanupQuery.payload) !== null;
          if (!appAvailableForCleanup && appInstalledBefore) {
            restorationErrors.push('app: existing iOS app disappeared after install failure');
          }
        } catch (error) {
          appCleanupQueryFailed = true;
          restorationErrors.push(`app-query: ${error.message}`);
        }
        try {
          terminateGame();
          suspendedGamePid = null;
        } catch (error) {
          restorationErrors.push(`process: ${error.message}`);
        }
        if (appAvailableForCleanup || appCleanupQueryFailed) {
          try {
            uninstallIsolatedCaptureApp('isolated-capture-cleanup');
            isolatedCaptureBundleRemoved = true;
          } catch (error) {
            restorationErrors.push(`isolated-uninstall: ${error.message}`);
          }
        } else {
          isolatedCaptureBundleRemoved = true;
        }
        restore = {
          observed: persistentBefore,
          restored: persistentBefore,
          mutated: [],
          files: Object.keys(persistentBefore).sort(),
        };
        try {
          productionAppAfterPath = join(outputRoot, 'production-app-after.json');
          const productionAfterQuery = queryInstalledApp(
            'production-app-after',
            productionAppAfterPath,
            PRODUCTION_BUNDLE_ID,
          );
          productionAppAfter = installedAppIdentity(
            productionAfterQuery.payload,
            PRODUCTION_BUNDLE_ID,
          );
          if (JSON.stringify(productionAppAfter) !== JSON.stringify(productionAppBefore)) {
            restorationErrors.push('production-app: app identity differs before/after capture');
          }
        } catch (error) {
          restorationErrors.push(`production-app-query: ${error.message}`);
        }
      } finally {
        cleanupInProgress = false;
      }
    },
  );
  // Darwin may deliver a signal callback only after a spawnSync cleanup child
  // has returned. Drain that host turn before declaring the run successful.
  await waitForPendingHostSignalHandlers();
  let operationFailure = settlement.operationFailure;
  try {
    throwIfCancellationRequested();
  } catch (error) {
    operationFailure ??= error;
  }
  if (settlement.cleanupFailure !== null) {
    restorationErrors.push(`cleanup: ${settlement.cleanupFailure.message}`);
  }
  if (restore !== null && restore.mutated.length > 0 && operationFailure === null) {
    operationFailure = new Error(
      `restored user persistent data that changed during capture: ${restore.mutated.join(', ')}`,
    );
  }
  if (operationFailure !== null || restorationErrors.length > 0) {
    const failure = operationFailure ?? new Error('iOS post-capture restoration failed');
    if (restorationErrors.length > 0) {
      failure.message += `; restoration failed: ${restorationErrors.join(' | ')}`;
    }
    writeJson(join(outputRoot, 'failure.json'), {
      failed_at: new Date().toISOString(),
      message: failure.message,
      captures_completed: captures.length,
      restoration_errors: restorationErrors,
    });
    throw failure;
  }
  if (restore === null) {
    fail('missing proof of persistent-data restoration after iOS capture');
  }

  const sourceAfter = currentSourceSnapshot();
  if (!sameSourceSnapshot(build.sourceAfterBuild, sourceAfter)) {
    fail('game runtime or capture inputs changed during iOS device capture');
  }
  assertFrozenIosInstallArtifact({
    artifactSha256: build.artifactSha256,
    currentArtifactSha256: fileSha256(build.artifact),
    appTreeSha256: build.appTreeSha256,
    currentAppTreeSha256: iosAppTreeSha256(build.frozenApp),
  });
  captureFilesAreCurrent();
  const manifest = assertCompleteIosCaptureManifest({
    captures,
    locales: selectedLocales.map(({ asset }) => asset),
    filenames: Object.values(SCREENSHOTS),
    artifactSha256: build.artifactSha256,
    captureMethod,
  });
  const canonicalEligible = options.allLocales && captures.length === 30;
  const reportCaptures = captures.map((capture) => ({
    ...capture,
    source: canonicalEligible ? canonicalCapturePath(capture) : null,
  }));
  const pmdVersion = captureMethod === IOS_RSD_CAPTURE_METHOD
    ? run(PYMOBILEDEVICE3, ['version']).stdout.trim()
    : null;
  const report = {
    schema: 2,
    captured_at: new Date().toISOString(),
    platform: 'ios',
    target: options.target,
    bundle_id: PRODUCTION_BUNDLE_ID,
    installed_capture_bundle_id: ACTIVE_BUNDLE_ID,
    physical_device: identity.physical_device,
    simulator: identity.simulator,
    device_udid: identity.device_udid,
    coredevice_identifier: identity.coredevice_identifier,
    device_name: identity.device_name,
    marketing_name: identity.marketing_name,
    model_identifier: identity.model_identifier,
    os_version: identity.os_version,
    os_build: identity.os_build,
    transport: identity.transport,
    asset_locales: selectedLocales.map(({ asset }) => asset),
    game_locales: selectedLocales.map(({ game }) => game),
    screenshot_size: manifest.screenshot_size,
    foreground_verified_at_capture_end: true,
    foreground_evidence: 'activated CoreDevice launch plus advancing in-game observation',
    final_processes_path: relative(REPO_ROOT, finalProcessEvidence.path),
    final_processes_sha256: fileSha256(finalProcessEvidence.path),
    final_process_id: finalProcessEvidence.processes[0].processIdentifier,
    final_process_executable: finalProcessEvidence.processes[0].executable,
    capture_method: captureMethod,
    pymobiledevice3_version: pmdVersion,
    coredevice_device_details_path: relative(REPO_ROOT, deviceDetailsPath),
    coredevice_device_details_sha256: fileSha256(deviceDetailsPath),
    rsd_host: rsd?.host ?? null,
    rsd_port: rsd?.port ?? null,
    rsd_endpoint_ephemeral: rsd !== null,
    rsd_preflight_path: null,
    rsd_preflight_image_retained: false,
    rsd_preflight_sha256: rsd?.preflightSha256 ?? null,
    rsd_preflight_size: rsd?.preflightSize ?? null,
    rsd_identity: rsd?.identity ?? null,
    rsd_info_raw_sha256: rsd?.identityRawJsonSha256 ?? null,
    rsd_identity_proof_path: rsd === null
      ? null
      : relative(REPO_ROOT, rsd.identityProofPath),
    xcode_screenshot_handoff: captureMethod === IOS_XCODE_HANDOFF_CAPTURE_METHOD
      ? {
        schema: 2,
        first_party_tool: 'Xcode Devices and Simulators',
        capture_method: IOS_XCODE_HANDOFF_CAPTURE_METHOD,
        operator_mediated: true,
        inbox_path_persisted: false,
        atomic_rename_required: true,
        publisher_script: 'scripts/publish-xcode-screenshot-handoff.mjs',
        complete_png_decode_required: true,
        stable_observations_required: 2,
        fsync_receipt_required: true,
        request_timeout_seconds: XCODE_HANDOFF_DEADLINE_MS / 1_000,
        expected_framebuffer: IOS_XCODE_IPAD_LANDSCAPE_SIZE,
      }
      : null,
    isolated_capture_bundle: true,
    production_container_accessed: false,
    isolated_capture_bundle_removed: isolatedCaptureBundleRemoved,
    production_app_identity_before: productionAppBefore,
    production_app_identity_after: productionAppAfter,
    production_app_identity_unchanged:
      JSON.stringify(productionAppBefore) === JSON.stringify(productionAppAfter),
    production_app_before_path: relative(REPO_ROOT, productionAppBeforePath),
    production_app_before_sha256: fileSha256(productionAppBeforePath),
    production_app_after_path: relative(REPO_ROOT, productionAppAfterPath),
    production_app_after_sha256: fileSha256(productionAppAfterPath),
    build_mode: 'fresh-build',
    build_artifact_path: relative(REPO_ROOT, build.artifact),
    build_artifact_sha256: build.artifactSha256,
    installed_artifact_sha256: build.artifactSha256,
    install_result_path: relative(REPO_ROOT, installEvidence.installPath),
    install_result_sha256: fileSha256(installEvidence.installPath),
    installed_app_path: relative(REPO_ROOT, installEvidence.installedPath),
    installed_app_sha256: fileSha256(installEvidence.installedPath),
    installed_identity_sha256: installedAppIdentitySha256(installEvidence.app),
    app_tree_sha256: build.appTreeSha256,
    executable_sha256: build.executableSha256,
    pck_sha256: build.pckSha256,
    exported_pck_sha256: build.exportedPckSha256,
    short_version: build.plist.CFBundleShortVersionString,
    build_version: build.plist.CFBundleVersion,
    build_started_at: build.buildStartedAt,
    build_attestation_path: relative(REPO_ROOT, build.attestationPath),
    build_attestation_sha256: fileSha256(build.attestationPath),
    build_attestation: build.attestation,
    source_before_build: build.sourceBeforeBuild,
    source_after_build: build.sourceAfterBuild,
    source_before: build.sourceAfterBuild,
    source_after: sourceAfter,
    source_byte_equivalent: true,
    settings_restore: {
      original_present: persistentBefore['settings.cfg'] !== null,
      original_sha256: persistentHashes(persistentBefore)['settings.cfg'],
      observed_sha256: persistentHashes(restore.observed)['settings.cfg'],
      restored_sha256: persistentHashes(restore.restored)['settings.cfg'],
      byte_exact: true,
    },
    persistent_data_sha256_before: persistentHashes(persistentBefore, restore.files),
    persistent_data_sha256_after: persistentHashes(restore.observed, restore.files),
    persistent_data_sha256_restored: persistentHashes(restore.restored, restore.files),
    persistent_data_files: restore.files,
    persistent_data_mutated_during_capture: restore.mutated,
    persistent_data_restored_byte_exact: true,
    persistent_data_unchanged: true,
    control_files_disarmed: true,
    iphone_capture_claimed: options.target === 'iphone-6.5',
    canonical_publish_eligible: canonicalEligible,
    canonical_root: canonicalEligible
      ? `builds/shots/store-platform/ios/${options.target}`
      : null,
    publication: canonicalEligible
      ? 'timestamp-staging-then-atomic-directory-rename'
      : 'none',
    captures: reportCaptures,
  };
  const reportPath = join(outputRoot, 'report.json');
  writeJson(reportPath, report);
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
