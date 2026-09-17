// Find the Godot binary and forward every argument unchanged.
//
// `godot` is often missing from PATH. A winget install names the binary
// `Godot_v4.7.1-stable_win64.exe`, so a bare `godot` lookup fails.
// package.json scripts therefore go through this wrapper.
//
// Search order
//   1. GODOT_BIN environment variable (explicit path)
//   2. PATH entries godot / godot4
//   3. Common per-platform install locations
//
// If nothing matches, print every place that was searched and exit.

import './lib/load-env.mjs';

import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { homedir, platform } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

function onPath(name, isWin) {
  const probe = spawnSync(name, ['--version'], { stdio: 'ignore', shell: isWin });
  return probe.status === 0;
}

// Look for matching binaries in a directory. Prefer `_console.exe` so
// headless stdout is complete.
function findIn(dir, re) {
  if (!existsSync(dir)) return null;
  let names;
  try {
    names = readdirSync(dir);
  } catch {
    return null;
  }
  const hits = names.filter((n) => re.test(n));
  hits.sort((a, b) => Number(b.includes('console')) - Number(a.includes('console')));
  return hits.length ? join(dir, hits[0]) : null;
}

function findGodot(isWin, tried) {
  if (process.env.GODOT_BIN) {
    tried.push(`GODOT_BIN=${process.env.GODOT_BIN}`);
    if (existsSync(process.env.GODOT_BIN)) return process.env.GODOT_BIN;
  }

  for (const name of ['godot', 'godot4']) {
    tried.push(`PATH ${name}`);
    if (onPath(name, isWin)) return name;
  }

  const candidates = isWin
    ? [
        join(homedir(), 'AppData/Local/Microsoft/WinGet/Packages'),
        'C:/Program Files/Godot',
        join(homedir(), 'scoop/apps/godot/current'),
      ]
    : [
        '/Applications/Godot.app/Contents/MacOS',
        '/usr/local/bin',
        '/opt/godot',
        join(homedir(), '.local/bin'),
      ];

  const re = isWin ? /^Godot.*\.exe$/i : /^Godot/;
  for (const base of candidates) {
    tried.push(base);
    const direct = findIn(base, re);
    if (direct) return direct;
    // winget nests one extra folder per package
    if (existsSync(base)) {
      for (const sub of readdirSync(base)) {
        if (!/godot/i.test(sub)) continue;
        const nested = findIn(join(base, sub), re);
        if (nested) return nested;
      }
    }
  }
  return null;
}

// Other launchers reuse the same per-platform lookup. Callers can resolve
// the real binary before they overwrite HOME for isolation.
export function resolveGodot() {
  const isWin = platform() === 'win32';
  const tried = [];
  return {
    bin: findGodot(isWin, tried),
    isWin,
    tried,
  };
}

export function reportGodotNotFound({ isWin, tried }) {
  console.error('Could not find a Godot binary. Searched:');
  for (const t of tried) console.error('  ' + t);
  console.error('');
  console.error('Set GODOT_BIN to the full path:');
  console.error(
    isWin
      ? '  set GODOT_BIN=C:\\...\\Godot_v4.7.1-stable_win64_console.exe'
      : '  export GODOT_BIN=/path/to/godot',
  );
}

function main() {
  const search = resolveGodot();
  if (!search.bin) {
    reportGodotNotFound(search);
    process.exitCode = 127;
    return;
  }

  const run = spawnSync(search.bin, process.argv.slice(2), {
    stdio: 'inherit',
    shell: false,
  });
  process.exitCode = run.status ?? 1;
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : '';
if (import.meta.url === invokedPath) {
  main();
}
