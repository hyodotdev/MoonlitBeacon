#!/usr/bin/env node
// One Godot run against apps/game with nothing of the developer's in reach.
//
//   pnpm godot:isolated [--timeout 150] res://tests/test_x.tscn
//   pnpm godot:isolated --timeout 150 --script res://tests/test_x.gd
//   pnpm godot:isolated --timeout 3300 res://tools/play_bot.tscn -- tag=first runs=10 seed=3 speed=3 loops=2
//   pnpm godot:isolated --windowed res://tools/shot_ui.tscn        (windowed harnesses run in the foreground)
//   pnpm godot:isolated --import                                     (editor import, with the real HOME)
//
// Arguments before the first Godot argument belong to this wrapper (--timeout, --windowed, --import,
// --filter-noise). See `apps/game/tools/play_bot.gd` for what the bot takes and `apps/game/tools/play_report.py`
// for reading what it wrote.

import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { reportGodotNotFound, resolveGodot } from './godot.mjs';
import { buildGodotArguments, isNoise, isolatedEnvironment, parseGodotRun } from './lib/godot-run.mjs';

const repository = resolve(fileURLToPath(new URL('..', import.meta.url)));
const gameDirectory = join(repository, 'apps', 'game');

let parsed;
try {
  parsed = parseGodotRun(process.argv.slice(2));
} catch (error) {
  console.error(`godot-run: ${error.message}`);
  process.exit(2);
}
const search = resolveGodot();
if (!search.bin) {
  reportGodotNotFound(search);
  process.exit(127);
}

const home = mkdtempSync(join(tmpdir(), 'moonlit-godot-run-'));
const started = Date.now();
const child = spawn(
  search.bin,
  buildGodotArguments(parsed, gameDirectory),
  {
    cwd: repository,
    env: isolatedEnvironment(process.env, home, { realHome: parsed.options.realHome }),
    stdio: ['ignore', 'pipe', 'pipe'],
  },
);

let timedOut = false;
const timer = setTimeout(() => {
  timedOut = true;
  console.error(`godot-run: no exit after ${parsed.options.timeoutSeconds} s; killing it`);
  child.kill('SIGKILL');
}, parsed.options.timeoutSeconds * 1000);

const forward = (stream, sink) => {
  let pending = '';
  stream.on('data', (chunk) => {
    pending += chunk.toString('utf8');
    const lines = pending.split('\n');
    pending = lines.pop() ?? '';
    for (const line of lines) {
      if (!(parsed.options.filterNoise && isNoise(line))) sink.write(`${line}\n`);
    }
  });
  stream.on('end', () => {
    if (pending !== '' && !(parsed.options.filterNoise && isNoise(pending))) sink.write(`${pending}\n`);
  });
};
forward(child.stdout, process.stdout);
forward(child.stderr, process.stderr);

const code = await new Promise((done) => {
  child.on('error', () => done(127));
  child.on('close', (status, signal) => done(status ?? (signal ? 137 : 1)));
});
clearTimeout(timer);
// Delete only the directory created above.
if (home.startsWith(join(tmpdir(), 'moonlit-godot-run-'))) rmSync(home, { recursive: true, force: true });
console.error(`godot-run: exit ${code} after ${((Date.now() - started) / 1000).toFixed(1)} s${timedOut ? ' (timed out)' : ''}`);
process.exit(timedOut ? 124 : code);
