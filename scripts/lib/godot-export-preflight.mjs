import { spawnSync } from 'node:child_process';

export const GODOT_EXPORT_PREFLIGHTS = [
  {
    label: 'game boot check',
    args: [
      'scripts/godot.mjs',
      '--headless',
      '--path',
      'apps/game',
      '--quit',
    ],
  },
  {
    label: 'compile all scripts',
    args: [
      'scripts/godot.mjs',
      '--headless',
      '--path',
      'apps/game',
      'res://tools/check_scripts.tscn',
    ],
  },
];

export function runGodotExportPreflight({
  root,
  env = process.env,
  node = process.execPath,
  spawn = spawnSync,
} = {}) {
  if (typeof root !== 'string' || root.length === 0) {
    throw new Error('Godot export preflight path is empty.');
  }
  for (const check of GODOT_EXPORT_PREFLIGHTS) {
    const result = spawn(node, check.args, {
      cwd: root,
      env,
      stdio: 'inherit',
    });
    if (result.status !== 0) {
      const error = new Error(
        `${check.label} failed — refusing to export an invalid game.`,
      );
      error.exitCode = result.status ?? 1;
      throw error;
    }
  }
  return true;
}
