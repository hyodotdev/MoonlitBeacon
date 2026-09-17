#!/usr/bin/env node

// Copy generator output into the submission asset folder with a byte check.
//
//     pnpm store:sync-play          # builds/release/play → stores/google-play
//     pnpm store:sync-app-store     # builds/release/app-store → stores/app-store
//
// The checklist asks to "commit submission assets under stores/ (verify
// bytes match the builds originals)", but there was no command that did
// that copy, so every recapture was done by hand. Noticing that stores/
// still has last version's art is not a process — this script owns that
// step.
//
// Fail if stores/ still has a file that is not in the source. That keeps
// leftover art from a previous cut from being committed as store assets.

import './lib/load-env.mjs';

import { createHash } from 'node:crypto';
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
} from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const TARGETS = {
  play: ['builds/release/play', 'stores/google-play'],
  'app-store': ['builds/release/app-store', 'stores/app-store'],
};
const which = process.argv[2] ?? 'play';
if (!(which in TARGETS)) {
  console.error(`Unknown target: ${which} (${Object.keys(TARGETS).join(' | ')})`);
  process.exit(1);
}
const SOURCE = resolve(root, TARGETS[which][0]);
const TARGET = resolve(root, TARGETS[which][1]);

function fail(message) {
  console.error(`Asset sync failed: ${message}`);
  process.exit(1);
}

function walkPngs(base) {
  const found = [];
  const visit = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) visit(path);
      else if (entry.isFile() && entry.name.endsWith('.png')) {
        found.push(relative(base, path));
      }
    }
  };
  visit(base);
  return found.sort();
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

if (!existsSync(SOURCE)) {
  fail(`Source is missing: ${relative(root, SOURCE)} — run the generator first`);
}

const sources = walkPngs(SOURCE);
if (sources.length === 0) fail('Source PNG count is 0.');

let changed = 0;
for (const relativePath of sources) {
  const from = join(SOURCE, relativePath);
  const to = join(TARGET, relativePath);
  mkdirSync(join(to, '..'), { recursive: true });
  const before = existsSync(to) ? sha256(to) : null;
  copyFileSync(from, to);
  const after = sha256(to);
  if (after !== sha256(from)) fail(`copy hash mismatch: ${relativePath}`);
  if (before !== after) changed += 1;
}

const leftovers = existsSync(TARGET)
  ? walkPngs(TARGET).filter((path) => !sources.includes(path))
  : [];
if (leftovers.length > 0) {
  fail(`stores/ still has files that are not in the source (${leftovers.length}): `
    + leftovers.slice(0, 5).join(', '));
}

console.log(`${which} asset sync done — ${sources.length} file(s), updated ${changed}, leftovers 0`);
