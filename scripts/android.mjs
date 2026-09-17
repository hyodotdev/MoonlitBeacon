// Find Android SDK tools and run them.
//
// Same idea as `scripts/godot.mjs`. This Mac has neither `adb` nor
// `emulator` on PATH, and `ANDROID_HOME` is empty. The SDK still lives in
// the same place, so look it up.
//
// Search order
//   1. ANDROID_HOME / ANDROID_SDK_ROOT
//   2. Walk up from PATH's adb
//   3. Common per-platform install locations
//
// Usage
//   node scripts/android.mjs sdk                  print SDK path only
//   node scripts/android.mjs emu [avd]            start emulator (default Pixel_10)
//   node scripts/android.mjs wait                 wait until boot finishes
//   node scripts/android.mjs adb <args...>        forward args to adb
//   node scripts/android.mjs shot <file>          save a screenshot

import './lib/load-env.mjs';

import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { homedir, platform } from 'node:os';

const DEFAULT_AVD = 'Pixel_10';
const tried = [];

function findSdk() {
  for (const key of ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    const v = process.env[key];
    tried.push(`${key}=${v ?? '(missing)'}`);
    if (v && existsSync(join(v, 'platform-tools'))) return v;
  }

  // If adb is on PATH, two parents up is the SDK root.
  const which = spawnSync(platform() === 'win32' ? 'where' : 'which', ['adb'], {
    encoding: 'utf8',
  });
  if (which.status === 0) {
    const root = dirname(dirname(which.stdout.trim().split('\n')[0]));
    tried.push(`PATH adb → ${root}`);
    if (existsSync(join(root, 'platform-tools'))) return root;
  }

  const candidates =
    platform() === 'win32'
      ? [join(homedir(), 'AppData/Local/Android/Sdk')]
      : [
          join(homedir(), 'Library/Android/sdk'),
          join(homedir(), 'Android/Sdk'),
          '/usr/local/share/android-sdk',
        ];

  for (const c of candidates) {
    tried.push(c);
    if (existsSync(join(c, 'platform-tools'))) return c;
  }
  return null;
}

const sdk = findSdk();

if (!sdk) {
  console.error('Could not find the Android SDK. Searched:');
  for (const t of tried) console.error('  ' + t);
  console.error('');
  console.error('Set ANDROID_HOME to the SDK path:');
  console.error('  export ANDROID_HOME=$HOME/Library/Android/sdk');
  process.exit(127);
}

const adb = join(sdk, 'platform-tools', 'adb');
const emulator = join(sdk, 'emulator', 'emulator');
const GAME_PACKAGE = 'com.crossplatformkorea.moonlitbeacon';
const CLEAN_UI_CHANNELS = [
  {
    request: 'files/store_capture_clean_title.request',
    ready: 'files/store_capture_clean_title.ready',
    proof: 'title-hidden',
  },
  {
    request: 'files/store_capture_clean_combat.request',
    ready: 'files/store_capture_clean_combat.ready',
    proof: 'combat-hidden',
  },
];
const CLEAN_UI_WAIT = new Int32Array(new SharedArrayBuffer(4));

const [cmd, ...rest] = process.argv.slice(2);

function runAs(args, options = {}) {
  return spawnSync(adb, ['shell', 'run-as', GAME_PACKAGE, ...args], options);
}

function clearCleanUiHandshake() {
  return runAs([
    'rm', '-f',
    ...CLEAN_UI_CHANNELS.flatMap(({ request, ready }) => [request, ready]),
  ]).status === 0;
}

function armCleanUiHandshake() {
  if (!clearCleanUiHandshake()) return false;
  return runAs([
    'touch', ...CLEAN_UI_CHANNELS.map(({ request }) => request),
  ]).status === 0;
}

function waitForCleanUiProof(timeoutMs = 8000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    for (const channel of CLEAN_UI_CHANNELS) {
      const result = runAs(['cat', channel.ready], { encoding: 'utf8' });
      if (result.status === 0 && result.stdout.trim() === channel.proof) {
        return channel.proof;
      }
    }
    Atomics.wait(CLEAN_UI_WAIT, 0, 0, 100);
  }
  return '';
}

// Wait until the emulator attaches, then until boot finishes.
// `adb wait-for-device` returns as soon as the device is visible, so boot
// completion is checked separately.
function waitForBoot() {
  const wait = spawnSync(adb, ['wait-for-device'], { stdio: 'inherit' });
  if (wait.status !== 0) return wait.status ?? 1;
  // sleep runs in the device shell. It does not block the host.
  const boot = spawnSync(
    adb,
    ['shell', 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done'],
    { stdio: 'inherit' },
  );
  return boot.status ?? 1;
}

switch (cmd) {
  case 'sdk':
    console.log(sdk);
    break;

  case 'emu': {
    const avd = rest[0] ?? DEFAULT_AVD;
    const list = spawnSync(emulator, ['-list-avds'], { encoding: 'utf8' });
    const avds = (list.stdout ?? '').trim().split('\n').filter(Boolean);
    if (!avds.includes(avd)) {
      console.error(`AVD '${avd}' is missing. Present: ${avds.join(', ') || '(none)'}`);
      console.error('');
      console.error('To create an AVD matched to Pixel 10:');
      console.error(
        `  ${join(sdk, 'cmdline-tools/latest/bin/avdmanager')} create avd -n ${DEFAULT_AVD} \\`,
      );
      console.error('    -k "system-images;android-34;google_apis_playstore;arm64-v8a" -d pixel_9');
      process.exit(1);
    }
    // Always pass -gpu host. On Apple Silicon GLES3 is accelerated via
    // ANGLE→Metal.
    //
    // Always pass -no-metrics too. After one abnormal emulator exit, the
    // next launch **shows a crash-report consent dialog and waits for a
    // click.** The log has one line, "Showing crashdialog to get consent",
    // then silence, so it looks like graphics init died. That misread led
    // to trying -gpu swiftshader and even resetting the AVD.
    // Without this, rendering falls back to software and people conclude
    // "Godot is slow on the emulator".
    const child = spawn(emulator, ['-avd', avd, '-gpu', 'host', '-no-boot-anim', '-no-metrics', ...rest.slice(1)], {
      stdio: 'inherit',
      detached: true,
    });
    child.unref();
    console.log(`${avd} starting — waiting for boot.`);
    process.exit(waitForBoot());
  }

  case 'wait':
    process.exit(waitForBoot());

  case 'adb':
    process.exit(spawnSync(adb, rest, { stdio: 'inherit' }).status ?? 1);

  case 'shot': {
    const raw = rest.includes('--raw');
    const requestedOutput = rest.find((argument) => (
      argument !== '--' && !argument.startsWith('--')
    ));
    const out = resolve(requestedOutput ?? 'builds/shots/android.png');
    mkdirSync(dirname(out), { recursive: true });
    let cleanProof = '';
    if (!raw) {
      if (!armCleanUiHandshake()) {
        console.error('Product-screen hide request failed. Check the debug APK and run-as.');
        process.exit(1);
      }
      cleanProof = waitForCleanUiProof();
      if (!cleanProof) {
        clearCleanUiHandshake();
        console.error('Product-screen hide proof timed out. Confirm title or combat is showing.');
        process.exit(1);
      }
    }
    // On Mac, exec-out redirection is safe. It does not corrupt like PowerShell.
    const shot = spawnSync(adb, ['exec-out', 'screencap', '-p'], { maxBuffer: 64 * 1024 * 1024 });
    if (!raw) clearCleanUiHandshake();
    if (shot.status !== 0 || !shot.stdout?.length) {
      console.error('Screenshot failed. Confirm a device is attached.');
      process.exit(1);
    }
    writeFileSync(out, shot.stdout);
    if (cleanProof) console.log(`clean UI proof: ${cleanProof}`);
    console.log(out);
    break;
  }

  case 'clean-ui': {
    const action = rest.find((argument) => argument !== '--') ?? '';
    if (action === 'arm') {
      if (!armCleanUiHandshake()) {
        console.error('Product-screen hide request failed. Check the debug APK and run-as.');
        process.exit(1);
      }
      console.log('clean UI armed: title + combat');
      break;
    }
    if (action === 'wait') {
      const proof = waitForCleanUiProof();
      if (!proof) {
        console.error('Product-screen hide proof timed out. Confirm title or combat is showing.');
        process.exit(1);
      }
      console.log(`clean UI proof: ${proof}`);
      break;
    }
    if (action === 'clear') {
      if (!clearCleanUiHandshake()) {
        console.error('Failed to clear the product-screen hide request.');
        process.exit(1);
      }
      console.log('clean UI cleared: title + combat');
      break;
    }
    console.error('Usage: node scripts/android.mjs clean-ui <arm|wait|clear>');
    process.exit(2);
    break;
  }

  default:
    console.error('Usage: node scripts/android.mjs <sdk|emu|wait|adb|shot|clean-ui> [args...]');
    process.exit(2);
}
