import assert from 'node:assert/strict';
import test from 'node:test';

import { buildGodotArguments, isNoise, isolatedEnvironment, parseGodotRun } from './godot-run.mjs';

test('wrapper options come first and everything else is for Godot', () => {
  const parsed = parseGodotRun(['--timeout', '150', 'res://tools/play_bot.tscn', '--', 'tag=x', 'runs=3']);
  assert.equal(parsed.options.timeoutSeconds, 150);
  assert.deepEqual(parsed.godotArguments, ['res://tools/play_bot.tscn', '--', 'tag=x', 'runs=3']);
  assert.deepEqual(parseGodotRun(['--script', 'res://tests/t.gd']).godotArguments, ['--script', 'res://tests/t.gd']);
  assert.equal(parseGodotRun([]).options.timeoutSeconds, 900);
  assert.throws(() => parseGodotRun(['--timeout', 'soon']), /seconds/);
  assert.throws(() => parseGodotRun(['--timeout', '0']), /seconds/);
});

test('runs are headless against apps/game unless windowed, and import is the editor quit', () => {
  const game = '/repo/apps/game';
  assert.deepEqual(buildGodotArguments(parseGodotRun(['--script', 'res://t.gd']), game),
    ['--headless', '--path', game, '--script', 'res://t.gd']);
  assert.deepEqual(buildGodotArguments(parseGodotRun(['--windowed', 'res://tools/shot_ui.tscn']), game),
    ['--path', game, 'res://tools/shot_ui.tscn']);
  const imported = parseGodotRun(['--import']);
  assert.deepEqual(buildGodotArguments(imported, game), ['--headless', '--path', game, '--editor', '--quit']);
  assert.equal(imported.options.realHome, true);
});

test('a run sees a throwaway user directory and none of the developer\'s secrets', () => {
  const source = { PATH: '/bin', HOME: '/real/home', LANG: 'C', GH_TOKEN: 'x', MOONLIT_KEYSTORE_PASSWORD: 'x', IAPKIT_API_KEY: 'x' };
  const environment = isolatedEnvironment(source, '/tmp/throwaway');
  assert.equal(environment.HOME, '/tmp/throwaway');
  assert.equal(environment.MOONLIT_VAULT_TEST_ROOT, '/tmp/throwaway');
  assert.ok(environment.XDG_DATA_HOME.startsWith('/tmp/throwaway'));
  assert.ok(environment.APPDATA.startsWith('/tmp/throwaway'));
  assert.equal(environment.PATH, '/bin');
  assert.ok(!('GH_TOKEN' in environment) && !('MOONLIT_KEYSTORE_PASSWORD' in environment) && !('IAPKIT_API_KEY' in environment));
  // The import is the one run that uses the real HOME, and it still carries no vault switch.
  const real = isolatedEnvironment(source, '/tmp/throwaway', { realHome: true });
  assert.equal(real.HOME, '/real/home');
  assert.ok(!('MOONLIT_VAULT_TEST_ROOT' in real));
});

test('only the known engine noise is filtered', () => {
  assert.ok(isNoise('[GodotIap] Initializing native plugin...'));
  assert.ok(isNoise('   GDScript backtrace (most recent call first):'));
  assert.ok(!isNoise('ERROR: Failed to load resource'));
  assert.ok(!isNoise('bullet-field test passed — 46 case(s)'));
});
