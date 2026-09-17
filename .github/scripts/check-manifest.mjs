// Check that assets under res:// and the asset manifest stay in sync.
//
// The manifest is the source-and-license record of "files actually copied
// into the project". Add a file and skip the record, and you have to
// rediscover the license later. A record with no file means the docs lie.
//
// A manifest `Project path:` may be a folder or a file, so a real file
// under that path is treated as covered.

import { readFileSync } from 'node:fs';
import { readdir } from 'node:fs/promises';
import { join, posix } from 'node:path';

const GAME = 'apps/game';
const MANIFEST = 'apps/docs/docs/assets/manifest.md';

// res:// paths the manifest claims to cover
const md = readFileSync(MANIFEST, 'utf8');
const declared = [
  ...md.matchAll(/Project path:\s*(.+)/g),
].flatMap((m) =>
  m[1]
    .split(/[,\s]+/)
    .map((s) => s.trim().replace(/^res:\/\//, '').replace(/[`*]/g, ''))
    .filter((s) => s.length > 0),
);

async function walk(dir, base = dir) {
  const out = [];
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...(await walk(p, base)));
    else out.push(posix.relative(base.split('\\').join('/'), p.split('\\').join('/')));
  }
  return out;
}

// .import is produced by Godot; .gitkeep keeps the folder. Neither is recorded.
const actual = (await walk(join(GAME, 'assets'), GAME)).filter(
  (f) => !f.endsWith('.import') && !f.endsWith('.gitkeep'),
);

const covered = (f) => declared.some((d) => f === d || f.startsWith(d.endsWith('/') ? d : d + '/'));

const missing = actual.filter((f) => !covered(f));

if (missing.length) {
  console.log(`::error file=${MANIFEST}::${missing.length} asset(s) missing from the manifest`);
  for (const f of missing) console.log(`    res://${f}`);
  console.log('');
  console.log('If you added a file, record its source and license in the manifest.');
  process.exit(1);
}

console.log(`${actual.length} asset(s), all covered by the manifest`);
