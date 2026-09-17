import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const PRESETS = readFileSync(
  join(REPO_ROOT, 'apps/game/export_presets.cfg'),
  'utf8',
);
const CAPTURE_SCRIPT = readFileSync(
  join(REPO_ROOT, 'scripts/capture-store-screenshots.mjs'),
  'utf8',
);
const TEST_LAUNCHER = readFileSync(
  join(REPO_ROOT, 'apps/game/scripts/dev/test_launcher.gd'),
  'utf8',
);
const ARENA_TOOLS = readFileSync(
  join(REPO_ROOT, 'apps/game/scripts/dev/arena_tools.gd'),
  'utf8',
);
const STORE_CAPTURE_CLEAN_UI = readFileSync(
  join(REPO_ROOT, 'apps/game/scripts/dev/store_capture_clean_ui.gd'),
  'utf8',
);
const DEVICE_WORKFLOW = readFileSync(
  join(REPO_ROOT, '.claude/commands/device.md'),
  'utf8',
);
const ANDROID_SCRIPT = readFileSync(
  join(REPO_ROOT, 'scripts/android.mjs'),
  'utf8',
);
const MOON_MISSILE = readFileSync(
  join(REPO_ROOT, 'apps/game/scripts/actors/moon_missile.gd'),
  'utf8',
);
const REQUIRED_DEV_EXCLUDES = ['tests/*', 'tools/*'];

function presetSection(name) {
  const section = PRESETS
    .split(/\n(?=\[preset\.\d+\]\n)/)
    .find((value) => value.includes(`name="${name}"\n`));
  assert.ok(section, `${name} export preset is missing`);
  return section;
}

function setting(section, key) {
  const line = section
    .split('\n')
    .find((value) => value.startsWith(`${key}=`));
  assert.ok(line, `${key} setting is missing`);
  return line.slice(key.length + 1).replace(/^"|"$/g, '');
}

function assertReleaseResourceContract(name) {
  const section = presetSection(name);
  assert.equal(setting(section, 'export_filter'), 'all_resources');
  assert.deepEqual(
    setting(section, 'exclude_filter')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
    REQUIRED_DEV_EXCLUDES,
    `${name} must exclude only tests and production tools from export`,
  );
}

test('Android Play export does not package tests or production tools', () => {
  assertReleaseResourceContract('Android Play');
});

test('iOS export does not package tests or production tools', () => {
  assertReleaseResourceContract('iOS');
});

test('direct-distribution Android keeps the same resource boundary', () => {
  assertReleaseResourceContract('Android');
});

test('debug scripts that are not excluded are direct dependencies of the current runtime scene', () => {
  const title = readFileSync(
    join(REPO_ROOT, 'apps/game/scenes/menus/title_menu.tscn'),
    'utf8',
  );
  const arena = readFileSync(
    join(REPO_ROOT, 'apps/game/scenes/gameplay/arena.tscn'),
    'utf8',
  );

  assert.match(title, /res:\/\/scripts\/dev\/test_launcher\.gd/);
  assert.match(arena, /res:\/\/scripts\/dev\/frame_meter\.gd/);
  assert.match(arena, /res:\/\/scripts\/dev\/arena_tools\.gd/);
});

test('store clean UI handshake hides debug nodes only and is inactive in release', () => {
  const releaseGuard =
    /if not OS\.is_debug_build\(\):\s+set_process\(false\)\s+queue_free\(\)\s+return/u;
  for (const source of [TEST_LAUNCHER, ARENA_TOOLS]) {
    assert.match(source, releaseGuard);
    assert.match(source, /store_capture_clean_ui\.gd/u);
  }
  assert.match(STORE_CAPTURE_CLEAN_UI, /if not OS\.is_debug_build\(\)/u);
  assert.equal(
    (STORE_CAPTURE_CLEAN_UI.match(
      /user:\/\/store_capture_clean_[a-z]+\.(?:request|ready)/gu,
    ) ?? []).length,
    4,
  );
  assert.match(STORE_CAPTURE_CLEAN_UI, /owner\.visible = false/u);
  assert.match(STORE_CAPTURE_CLEAN_UI, /extra\.visible = false/u);
  assert.match(
    STORE_CAPTURE_CLEAN_UI,
    /remove_absolute\(ProjectSettings\.globalize_path\(request_path\)\)/u,
  );
  assert.match(ARENA_TOOLS, /Ui\/FrameMeter/u);
  assert.match(ARENA_TOOLS, /hide_combat\(self, frame_meter\)/u);
  assert.match(TEST_LAUNCHER, /hide_title\(self\)/u);

  assert.match(CAPTURE_SCRIPT, /await waitForCleanUiCapture\(cleanUiKind\)/u);
  const captureStart = CAPTURE_SCRIPT.indexOf('async function capture(');
  const captureEnd = CAPTURE_SCRIPT.indexOf(
    'async function captureWithCleanUi(', captureStart,
  );
  const captureSource = CAPTURE_SCRIPT.slice(captureStart, captureEnd);
  const screencap = captureSource.indexOf(
    "adbRun(['exec-out', 'screencap', '-p']",
  );
  const cleanUiBefore = captureSource.lastIndexOf(
    'assertCleanUiCaptureReady(', screencap,
  );
  const cleanUiAfter = captureSource.indexOf(
    'assertCleanUiCaptureReady(', screencap,
  );
  assert.ok(
    cleanUiBefore >= 0 && cleanUiAfter > screencap,
    'must re-verify a stale clean UI proof on both sides of screencap',
  );
  assert.match(
    captureSource.slice(screencap, cleanUiAfter),
    /await sleep\(60\)/u,
  );
  assert.match(
    CAPTURE_SCRIPT,
    /finally \{\s+clearCleanUiCaptureHandshake\(\);\s+\}/u,
  );
  assert.match(
    CAPTURE_SCRIPT,
    /await captureWithCleanUi\([\s\S]+?'title'/u,
  );
  assert.ok(
    (CAPTURE_SCRIPT.match(/await captureWithCleanUi\(/gu) ?? []).length >= 4,
    'must capture the 1 title shot and 3 combat shots only after clean UI completes',
  );
  assert.match(CAPTURE_SCRIPT, /cleanUiKind: kind/u);
  assert.match(CAPTURE_SCRIPT, /--serial may be specified only once/u);
  assert.match(CAPTURE_SCRIPT, /run\(adb, \['-s', requestedSerial, 'get-state'\]\)/u);
  assert.match(CAPTURE_SCRIPT, /'emu', 'avd', 'name'/u);
  assert.match(CAPTURE_SCRIPT, /avdName !== 'Pixel_10'/u);
});

test('Pixel device capture takes the screen only after title and combat debug UI proof', () => {
  const screenshotStart = DEVICE_WORKFLOW.indexOf('## 3. Screenshot');
  const screenshotEnd = DEVICE_WORKFLOW.indexOf('## 4. Screen recording', screenshotStart);
  const section = DEVICE_WORKFLOW.slice(screenshotStart, screenshotEnd);
  const titleRequest = section.indexOf('store_capture_clean_title.request');
  const request = section.indexOf('store_capture_clean_combat.request', titleRequest);
  const titleReady = section.indexOf('store_capture_clean_title.ready', titleRequest);
  const ready = section.indexOf('store_capture_clean_combat.ready', request);
  const proof = section.indexOf('combat-hidden', Math.max(titleReady, ready));
  const screencap = section.indexOf('adb shell screencap', proof);
  const cleanup = section.lastIndexOf(
    'store_capture_clean_combat.request',
  );

  assert.ok(titleRequest >= 0 && request > titleRequest,
    'both title and combat debug UI hide requests are required');
  assert.ok(titleReady > titleRequest && ready > request,
    'must not trust each stale ready before its matching request');
  assert.ok(proof > ready, 'must confirm draw-complete proof after hide');
  assert.ok(screencap > proof, 'must screencap only after clean UI proof');
  assert.ok(cleanup > screencap, 'must clear the temporary handshake after capture');
  assert.match(section, /title-hidden or combat-hidden/u);
  assert.match(section, /strips those nodes/u);

  assert.match(ANDROID_SCRIPT, /function armCleanUiHandshake\(\)/u);
  assert.match(ANDROID_SCRIPT, /function waitForCleanUiProof\(timeoutMs = 8000\)/u);
  const androidShot = ANDROID_SCRIPT.slice(ANDROID_SCRIPT.indexOf("case 'shot':"));
  const arm = androidShot.indexOf('armCleanUiHandshake()');
  const wait = androidShot.indexOf('waitForCleanUiProof()');
  const capture = androidShot.indexOf("['exec-out', 'screencap', '-p']");
  const clear = androidShot.indexOf('clearCleanUiHandshake();', capture);
  assert.ok(arm >= 0 && wait > arm && capture > wait && clear > capture,
    'android:shot must follow arm → proof → capture → cleanup');
  assert.match(androidShot, /const raw = rest\.includes\('--raw'\)/u);
});

test('Pixel recording keeps both scene-switch clean requests until the end and then clears them', () => {
  const recordStart = DEVICE_WORKFLOW.indexOf('## 4. Screen recording');
  const recordEnd = DEVICE_WORKFLOW.indexOf('## 5. Visual check', recordStart);
  const section = DEVICE_WORKFLOW.slice(recordStart, recordEnd);
  const arm = section.indexOf('node scripts/android.mjs clean-ui arm');
  const proof = section.indexOf('node scripts/android.mjs clean-ui wait', arm);
  const record = section.indexOf('adb shell screenrecord', proof);
  const cleanup = section.indexOf('node scripts/android.mjs clean-ui clear', record);
  assert.ok(arm >= 0, 'must arm title and combat clean requests together before recording');
  assert.ok(proof > arm, 'must wait for the current screen clean proof before recording');
  assert.ok(record > proof, 'must start recording after clean proof');
  assert.ok(cleanup > record, 'must clear both requests after recording');
  assert.match(ANDROID_SCRIPT, /case 'clean-ui':/u);
  assert.match(ANDROID_SCRIPT, /action === 'wait'[\s\S]+?waitForCleanUiProof\(\)/u);
});

test('store missile physical diagnostics add render cost only in debug builds', () => {
  assert.match(
    MOON_MISSILE,
    /var capture_diagnostics: bool = OS\.is_debug_build\(\)/u,
  );
  assert.match(
    MOON_MISSILE,
    /if capture_diagnostics and _debug_lane_trail_geometry\(i\)/u,
  );
  assert.match(
    MOON_MISSILE,
    /if capture_diagnostics \\\s+and _debug_segments_have_geometry/u,
  );
  assert.equal(
    (MOON_MISSILE.match(
      /if OS\.is_debug_build\(\):\s+_capture_launch_draw_serial = _capture_draw_serial/gu,
    ) ?? []).length,
    2,
  );
});
