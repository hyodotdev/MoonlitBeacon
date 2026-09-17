#!/usr/bin/env node
// Check that the translation table and keys actually used stay in sync.
//
// Keys like `RESULT_WIN` showing on screen only show up at runtime.
// Catch what we can without launching the game.
//
//   1. Every row in the table has both (all) languages filled
//   2. Keys called from scenes and scripts exist in the table
//   3. project.godot points at the translation files
//
// This cannot tell whether import actually ran. CI's game run checks that.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, sep } from 'node:path';
import { createHash } from 'node:crypto';

const GAME = 'apps/game';
const CSV = join(GAME, 'localization', 'moonlit.csv');
const rel = (p) => p.split(sep).join('/');

const problems = [];

// --- 1. Translation table ---------------------------------------------------
const lines = readFileSync(CSV, 'utf8').trim().split('\n');
const header = lines[0].split(',');
if (header[0] !== 'keys') problems.push(`${rel(CSV)}: first column is not "keys"`);
const locales = header.slice(1);
const EXPECTED_LOCALES = ["ko", "en", "ja", "zh_CN", "zh_TW"];
if (JSON.stringify(locales) !== JSON.stringify(EXPECTED_LOCALES)) {
  problems.push(
    `${rel(CSV)}: locale columns must be ${EXPECTED_LOCALES.join(" ")} in that order ` +
      `(got ${locales.join(" ")})`,
  );
}

const table = new Map();
lines.slice(1).forEach((line, i) => {
  const cells = line.split(',');
  const key = cells[0];
  const where = `${rel(CSV)}:${i + 2}`;
  if (cells.length !== header.length) {
    problems.push(`${where}: ${cells.length} cell(s) (expected ${header.length}) — do not put commas in translations`);
    return;
  }
  if (table.has(key)) problems.push(`${where}: key ${key} is duplicated`);
  cells.slice(1).forEach((value, c) => {
    if (value.trim() === '') problems.push(`${where}: ${key}'s ${locales[c]} is empty`);
  });
  const placeholders = cells.slice(1).map((value) => value.match(/%(?:%|s|d)/g) ?? []);
  for (let c = 1; c < placeholders.length; c += 1) {
    if (JSON.stringify(placeholders[c]) !== JSON.stringify(placeholders[0])) {
      problems.push(
        `${where}: ${key} format-argument order differs between ${locales[0]} and ${locales[c]} ` +
          `(${placeholders[0].join(" ")} / ${placeholders[c].join(" ")})`,
      );
    }
  }
  table.set(key, cells.slice(1));
});

// --- 2. Keys actually used --------------------------------------------------
// Keys are uppercase, digits, and underscores only, so they stand out from body copy.
const KEY = /\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\b/g;

// Looks like a key but is not. Engine constants and node names.
const NOT_KEYS = /^(?:[A-Z]+_[A-Z0-9_]*(?:MODE|FILTER|PRESET|DIRECTION|ALIGNMENT|MASK|LAYER)|SUB_RESOURCE|EXT_RESOURCE|GD_SCENE|PACKED[A-Z0-9]*ARRAY|STYLE_BOX[A-Z_]*|NODE_PATH)$/;

const walk = (dir) => readdirSync(dir).flatMap((name) => {
  if (name === '.godot' || name === 'assets') return [];
  const full = join(dir, name);
  return statSync(full).isDirectory() ? walk(full) : [full];
});

const used = new Map();
for (const file of walk(GAME)) {
  // Also inspect Resources (`.tres`) that hold translation keys directly.
  // Keys passed at runtime as `tr(resource_field)` — relic names and
  // descriptions — would let a typo through CI if they were skipped here.
  if (!/\.(tscn|tres|gd)$/.test(file)) continue;
  const text = readFileSync(file, 'utf8');
  text.split('\n').forEach((line, i) => {
    // Scenes use `text = "KEY"`; code uses uppercase strings in quotes.
    //
    // Looking only at `tr("KEY")` misses keys that are **stored in a table
    // and called later**, as in `credits_panel.gd`. That actually slipped
    // through. Strip comments before scanning.
    const code = /\.gd$/.test(file) ? line.split('#')[0] : line;
    const scene = line.match(/^text = "([A-Z][A-Z0-9_]*)"$/);
    const literals = [...code.matchAll(/"([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)"/g)].map((m) => m[1]);
    const found = scene ? [scene[1], ...literals] : literals;
    for (const key of found) {
      if (NOT_KEYS.test(key) || !KEY.test(key)) continue;
      KEY.lastIndex = 0;
      if (!used.has(key)) used.set(key, `${rel(file)}:${i + 1}`);
    }
  });
}

for (const [key, where] of used) {
  if (!table.has(key)) problems.push(`${where}: ${key} is not in the translation table — the key will show on screen`);
}

const unused = [...table.keys()].filter((key) => !used.has(key));

// --- 3. project.godot --------------------------------------------------------
const project = readFileSync(join(GAME, 'project.godot'), 'utf8');
for (const locale of locales) {
  const path = `res://localization/moonlit.${locale}.translation`;
  if (!project.includes(path)) problems.push(`project.godot is missing ${path}`);
}

// --- 4. Bundled CJK font ----------------------------------------------------
// Keep the full Noto original. A partial subset can pass fixed UI and still
// fail Korean, Chinese, and Japanese names that players type on the leaderboard.
const notoPath = join(
  GAME,
  'assets',
  'third_party',
  'fonts',
  'NotoSansCJKsc-Regular.otf',
);
const notoHash = createHash('sha256')
  .update(readFileSync(notoPath))
  .digest('hex');
const EXPECTED_NOTO_HASH =
  '2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b';
if (notoHash !== EXPECTED_NOTO_HASH) {
  problems.push(
    `${rel(notoPath)}: official Noto Sans CJK SC original hash changed (${notoHash})`,
  );
}
for (const resourceName of [
  'Galmuri11-Multilingual.tres',
  'NotoSansCJKsc-SyntheticBold.tres',
  'Galmuri11-Bold-Multilingual.tres',
]) {
  const resourcePath = join(
    GAME,
    'assets',
    'third_party',
    'fonts',
    resourceName,
  );
  const resource = readFileSync(resourcePath, 'utf8');
  if (!resource.includes('NotoSansCJKsc-')) {
    problems.push(`${rel(resourcePath)}: bundled CJK fallback is not wired`);
  }
}
// Body typeface switched from the pixel font (Galmuri) to Nexon Maplestory
// in the 2026-08 art refresh. The rule that stops a different device font
// from leaking through is unchanged.
for (const importName of [
  'MaplestoryLight.ttf.import',
  'MaplestoryBold.ttf.import',
]) {
  const importPath = join(
    GAME,
    'assets',
    'third_party',
    'fonts',
    importName,
  );
  if (!readFileSync(importPath, 'utf8').includes('allow_system_fallback=false')) {
    problems.push(`${rel(importPath)}: per-device system fallback is not turned off`);
  }
}
const notoImportPath = join(
  GAME,
  'assets',
  'third_party',
  'fonts',
  'NotoSansCJKsc-Regular.otf.import',
);
if (!readFileSync(notoImportPath, 'utf8').includes('allow_system_fallback=true')) {
  problems.push(
    `${rel(notoImportPath)}: system fallback for extra characters in player names is not turned on`,
  );
}

// --- Result -----------------------------------------------------------------
if (problems.length > 0) {
  for (const problem of problems) console.error(`  ${problem}`);
  console.error(`locale check failed — ${problems.length} problem(s)`);
  process.exit(1);
}

console.log(`translations ${table.size} · locales ${locales.join(' ')} · keys in use ${used.size} — ok`);
if (unused.length > 0) console.log(`  ${unused.length} unused key(s): ${unused.join(' ')}`);
