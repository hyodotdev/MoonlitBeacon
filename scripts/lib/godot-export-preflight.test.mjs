import assert from 'node:assert/strict';
import test from 'node:test';
import {
  GODOT_EXPORT_PREFLIGHTS,
  runGodotExportPreflight,
} from './godot-export-preflight.mjs';

test('runs game boot and full script compile before export', () => {
  const calls = [];
  const env = { TEST_EXPORT_ENV: 'yes' };
  assert.equal(
    runGodotExportPreflight({
      root: '/repo',
      env,
      node: '/node',
      spawn: (command, args, options) => {
        calls.push({ command, args, options });
        return { status: 0 };
      },
    }),
    true,
  );
  assert.deepEqual(
    calls.map(({ command, args }) => ({ command, args })),
    GODOT_EXPORT_PREFLIGHTS.map(({ args }) => ({
      command: '/node',
      args,
    })),
  );
  for (const call of calls) {
    assert.equal(call.options.cwd, '/repo');
    assert.equal(call.options.env, env);
    assert.equal(call.options.stdio, 'inherit');
  }
});

test('stops later checks and export if any preflight fails', () => {
  const calls = [];
  assert.throws(
    () => runGodotExportPreflight({
      root: '/repo',
      node: '/node',
      spawn: (_command, args) => {
        calls.push(args);
        return { status: 1 };
      },
    }),
    /refusing to export an invalid game/,
  );
  assert.deepEqual(calls, [GODOT_EXPORT_PREFLIGHTS[0].args]);
});
