#!/usr/bin/env node
// Strip NUL bytes from built HTML.
//
// Why this exists
// ---------------
// Docusaurus builds HTML with React's `renderToPipeableStream`.
// Multibyte characters on that path leak encoding-buffer padding into the
// output string: a CJK syllable can become `X\0\0Y` in the middle of a word.
//
//   - not in the source (.mdx)
//   - not in webpack JS chunks
//   - still happens with `--no-minify`
//   - same content → same locations and counts (not a race)
//   - also happens on Linux CI (not a local-machine bug)
//
// A comment in Docusaurus `client/renderToHtml.js` already links the
// upstream React issue. This is a known upstream bug.
//
// The visible symptom is table-of-contents links. Heading ids are fine, but
// a NUL inside the TOC `href` makes that item go nowhere.
//
// HTML has no legitimate place for a NUL byte. Stripping restores the
// intended characters.
//
// Usage
//   node scripts/strip-nul.mjs            strip from the build output
//   node scripts/strip-nul.mjs --check    do not strip; fail if any remain

import {readdir, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath} from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const BUILD_DIR = path.join(ROOT, 'apps', 'docs', 'build');
const checkOnly = process.argv.includes('--check');

// Touch only what SSR emits.
//
// Walking every extension would also strip legitimate 0x00 bytes from
// mp4, jpg, and png, **corrupting shipped video and images.** The first
// version of this script did that and broke eight clips. If this set ever
// grows, remember that.
const TEXT_EXTENSIONS = new Set(['.html', '.htm']);

async function* walk(dir) {
  let entries;
  try {
    entries = await readdir(dir, {withFileTypes: true});
  } catch (error) {
    if (error.code === 'ENOENT') {
      return;
    }
    throw error;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      yield* walk(full);
    } else if (entry.isFile()) {
      yield full;
    }
  }
}

let scanned = 0;
let dirty = 0;
let removed = 0;
const dirtyFiles = [];

for await (const file of walk(BUILD_DIR)) {
  if (!TEXT_EXTENSIONS.has(path.extname(file).toLowerCase())) {
    continue;
  }
  scanned += 1;
  const buf = await readFile(file);
  let count = 0;
  for (const byte of buf) {
    if (byte === 0) {
      count += 1;
    }
  }
  if (count === 0) {
    continue;
  }
  dirty += 1;
  removed += count;
  // GitHub annotations only understand `/` paths. A Windows `\` path is
  // ignored and the annotation never attaches to the file.
  dirtyFiles.push(`${path.relative(ROOT, file).split(path.sep).join('/')} (${count})`);
  if (!checkOnly) {
    await writeFile(file, buf.filter((byte) => byte !== 0));
  }
}

if (scanned === 0) {
  console.error(
    `No built HTML at ${path.relative(ROOT, BUILD_DIR)}\n` +
      'Run `pnpm docs:build` first.',
  );
  process.exit(1);
}

if (checkOnly) {
  if (dirty > 0) {
    for (const line of dirtyFiles) {
      console.error(`::error file=${line.split(' (')[0]}::NUL bytes remain`);
    }
    console.error(
      `\n${removed} NUL byte(s) remain in ${dirty} file(s). ` +
        'Confirm `scripts/strip-nul.mjs` ran after the build.',
    );
    process.exit(1);
  }
  console.log(`Checked ${scanned} file(s) — no NUL bytes`);
} else if (dirty > 0) {
  console.log(
    `Removed ${removed} NUL byte(s) from ${dirty} file(s) (scanned ${scanned}).`,
  );
  for (const line of dirtyFiles) {
    console.log(`  ${line}`);
  }
} else {
  console.log(`Scanned ${scanned} file(s) — no NUL bytes`);
}
