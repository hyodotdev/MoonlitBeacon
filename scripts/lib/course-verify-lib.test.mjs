// Gate and user-data tests for course verification. The defect fixtures are
// real Godot 4.7.2 output lines captured on this host; the parse-error run
// below exited 0, which is exactly the hole the gate closes.
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import {
  collectDefects,
  diffSnapshots,
  isFirstScanTranslationNoise,
  realUserDataRoots,
  snapshotUserData,
} from './course-verify-lib.mjs';

const PARSE_ERROR_ZERO_EXIT = `Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

SCRIPT ERROR: Parse Error: Expected parameter name.
          at: GDScript::reload (res://bad.gd:3)
ERROR: Failed to load script "res://bad.gd" with error "Parse error".
   at: load (modules/gdscript/gdscript_resource_format.cpp:46)
`;

const RUNTIME_ERROR = `SCRIPT ERROR: Invalid access to property or key 'loop_begin' on a base object of type 'AudioStreamOggVorbis'.
          at: _init (res://ask.gd:7)
          GDScript backtrace (most recent call first):
              [0] _init (res://ask.gd:7)
`;

const EXIT_LEAKS = `WARNING: 4 ObjectDB instances were leaked at exit
   at: cleanup (core/object/object.cpp:2536)
ERROR: 2 resources still in use at exit
WARNING: 1 RID of type "CanvasItem" was leaked.
   at: _free_rids (servers/rendering/renderer_canvas_cull.cpp:2733)
`;

const MACOS_SANDBOX_NOISE = `ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
`;

const NOERR_PARSE_ERROR = `SCRIPT ERROR: Parse Error: Identifier noErr is not declared in the current scope.
          at: GDScript::reload (res://ask.gd:7)
`;

const CLEAN_BOOT = `Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

READY_OK
`;

test('gate rejects parse errors even when the exit status is 0', () => {
  const defects = collectDefects(PARSE_ERROR_ZERO_EXIT);
  assert.equal(defects.length, 2);
  assert.match(defects[0], /Parse Error/);
  assert.match(defects[0], /GDScript::reload/);
  assert.match(defects[1], /Failed to load script/);
});

test('gate rejects runtime script errors with backtrace context', () => {
  const defects = collectDefects(RUNTIME_ERROR);
  assert.equal(defects.length, 1);
  assert.match(defects[0], /Invalid access/);
});

test('gate rejects exit-time leaks and resources still in use', () => {
  const defects = collectDefects(EXIT_LEAKS);
  assert.equal(defects.length, 3);
  assert.ok(defects.some((entry) => entry.includes('leaked at exit')));
  assert.ok(defects.some((entry) => entry.includes('still in use at exit')));
  assert.ok(defects.some((entry) => entry.includes('RID')));
});

test('gate passes clean output and narrow macOS sandbox noise', () => {
  assert.deepEqual(collectDefects(CLEAN_BOOT), []);
  assert.deepEqual(collectDefects(MACOS_SANDBOX_NOISE), []);
  assert.deepEqual(collectDefects(`${CLEAN_BOOT}\n${MACOS_SANDBOX_NOISE}`), []);
});

test('gate still reports a script error that merely mentions noErr', () => {
  // The environment exclusion matches the observed native condition text
  // only; a parse error naming an identifier noErr must stay visible.
  const defects = collectDefects(NOERR_PARSE_ERROR);
  assert.equal(defects.length, 1);
  assert.match(defects[0], /Identifier noErr is not declared/);
});

test('user-data snapshots detect any creation, change, or removal', () => {
  const root = mkdtempSync(join(tmpdir(), 'course-userdata-'));
  try {
    const save = join(root, 'app_userdata', 'Moonlit Course');
    mkdirSync(save, { recursive: true });
    writeFileSync(join(save, 'records.cfg'), 'best=10\n');
    const before = snapshotUserData([save, join(root, 'missing')]);
    assert.deepEqual(diffSnapshots(before, snapshotUserData([save, join(root, 'missing')])), []);
    writeFileSync(join(save, 'records.cfg'), 'best=11\n');
    assert.deepEqual(diffSnapshots(before, snapshotUserData([save, join(root, 'missing')])), [save]);
    rmSync(join(save, 'records.cfg'));
    assert.deepEqual(diffSnapshots(before, snapshotUserData([save, join(root, 'missing')])), [save]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('real user-data roots cover the learner and reference names', () => {
  const roots = realUserDataRoots({ HOME: '/fake/home', USERPROFILE: '/fake/home' });
  assert.equal(roots.length, 2);
  assert.ok(roots.some((root) => root.endsWith('Moonlit Course')));
  assert.ok(roots.some((root) => root.endsWith('Moonlit Course Reference')));
});

test('first-scan filter keeps only missing-translation loader lines', () => {
  assert.equal(
    isFirstScanTranslationNoise("ERROR: Cannot open file 'res://localization/moonlit.en.translation'."),
    true,
  );
  assert.equal(
    isFirstScanTranslationNoise('ERROR: Failed loading resource: res://localization/moonlit.ko.translation.'),
    true,
  );
  assert.equal(isFirstScanTranslationNoise('SCRIPT ERROR: Parse Error: nope.'), false);
  assert.equal(isFirstScanTranslationNoise("ERROR: Cannot open file 'res://scenes/gone.tscn'."), false);
});
