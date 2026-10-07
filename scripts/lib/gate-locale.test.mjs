import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, sep } from 'node:path';
import test from 'node:test';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const GAME = join(REPO_ROOT, 'apps/game');
const CSV = join(GAME, 'localization', 'gate_entry.csv');
const IMPORT = join(GAME, 'localization', 'gate_entry.csv.import');
const LOADER = join(GAME, 'scripts/ui/gate_entry_strings.gd');
const EXPORTED_TEST = join(GAME, 'tests/test_gate_entry_exported_locales.gd');
const PROJECT = join(GAME, 'project.godot');
const EXPECTED_LOCALES = ['ko', 'en', 'ja', 'zh_CN', 'zh_TW'];

const rel = (p) => p.split(sep).join('/');

function readCsvTable() {
  const lines = readFileSync(CSV, 'utf8').trim().split('\n');
  const header = lines[0].split(',');
  const rows = lines.slice(1).map((line) => line.split(','));
  return { header, rows };
}

test('gate table keeps its locale columns, cells, and key shape', () => {
  const { header, rows } = readCsvTable();
  assert.equal(header[0], 'keys');
  assert.deepEqual(header.slice(1), EXPECTED_LOCALES);
  const seen = new Set();
  rows.forEach((cells, index) => {
    const where = `${rel(CSV)}:${index + 2}`;
    assert.equal(
      cells.length,
      header.length,
      `${where}: ${cells.length} cell(s) (expected ${header.length}) — do not put commas in translations`,
    );
    const [key, ...values] = cells;
    assert.match(key, /^gate\.[a-z0-9_.]+$/u, `${where}: key shape`);
    assert.ok(!seen.has(key), `${where}: key ${key} is duplicated`);
    seen.add(key);
    values.forEach((value, column) => {
      assert.notEqual(
        value.trim(),
        '',
        `${where}: ${key}'s ${EXPECTED_LOCALES[column]} is empty`,
      );
    });
  });
  assert.ok(seen.size > 0, 'gate table ships keys');
});

// Complete keys only: the bare "gate." prefix and trailing-dot namespace
// prefixes ("gate.lodge.") in begins_with guards are filters, not keys.
function completeGateKeys(code) {
  return [...code.matchAll(/"((?:gate\.[a-z0-9_]+[a-z0-9_.]*))"/gu)]
    .map((match) => match[1])
    .filter((key) => !key.endsWith('.'));
}

test('every gate key used in code and scenes exists in the table', () => {
  const { rows } = readCsvTable();
  const table = new Set(rows.map((cells) => cells[0]));
  // The vendored godot-iap addon never uses the game's keys.
  const vendored = join(GAME, 'addons', 'godot-iap');
  const walk = (dir) => readdirSync(dir).flatMap((name) => {
    if (name === '.godot' || name === 'assets') return [];
    const full = join(dir, name);
    if (full === vendored) return [];
    return statSync(full).isDirectory() ? walk(full) : [full];
  });
  const used = new Map();
  for (const file of walk(GAME)) {
    if (!/\.(tscn|tres|gd)$/.test(file)) continue;
    const text = readFileSync(file, 'utf8');
    text.split('\n').forEach((line, index) => {
      // Strip GDScript comments; the loader's own doc comment names the
      // table path, not a key.
      const code = /\.gd$/.test(file) ? line.split('#')[0] : line;
      for (const key of completeGateKeys(code)) {
        if (!used.has(key)) used.set(key, `${rel(file)}:${index + 1}`);
      }
    });
  }
  assert.ok(used.size > 0, 'gate keys are in use');
  for (const [key, where] of used) {
    assert.ok(
      table.has(key),
      `${where}: ${key} is not in the gate table — the key will show on screen`,
    );
  }
});

test('complete-key recognition ignores namespace prefixes but keeps misspellings', () => {
  assert.deepEqual(
    completeGateKeys('if not str(cells[0]).begins_with("gate.lodge."):'),
    [],
    'trailing-dot namespace prefix is a filter, not a key',
  );
  assert.deepEqual(
    completeGateKeys('if not text_value.begins_with("gate."):'),
    [],
    'bare gate prefix is a filter, not a key',
  );
  assert.deepEqual(
    completeGateKeys('GateEntryStrings.text("gate.lodge.named_ok")'),
    ['gate.lodge.named_ok'],
    'complete used key stays checked',
  );
  assert.deepEqual(
    completeGateKeys('GateEntryStrings.text("gate.lodg.named_ok")'),
    ['gate.lodg.named_ok'],
    'misspelled complete key stays checked so the table test rejects it',
  );
});

test('project.godot registers every gate translation resource', () => {
  const project = readFileSync(PROJECT, 'utf8');
  for (const locale of EXPECTED_LOCALES) {
    const path = `res://localization/gate_entry.${locale}.translation`;
    assert.ok(
      project.includes(path),
      `project.godot is missing ${path} — the export will not auto-load it`,
    );
  }
});

test('gate import stays uncompressed so resources enumerate their keys', () => {
  // The loader builds its English fallback and key count from the
  // resource's own message list; compressed translations return none.
  // The five files are small (single-digit kilobytes each).
  const settings = readFileSync(IMPORT, 'utf8');
  assert.match(settings, /^compress=false$/mu);
  for (const locale of EXPECTED_LOCALES) {
    assert.ok(
      settings.includes(`gate_entry.${locale}.translation`),
      `${rel(IMPORT)} is missing the ${locale} output`,
    );
  }
});

test('loader and exported-resource test never read the source CSV', () => {
  // The CSV does not ship; anything that parses it only works on desktop.
  for (const file of [LOADER, EXPORTED_TEST]) {
    const code = readFileSync(file, 'utf8')
      .split('\n')
      .map((line) => line.split('##')[0].split('#')[0])
      .join('\n');
    assert.equal(
      code.includes('gate_entry.csv'),
      false,
      `${rel(file)} reads the source CSV, which never ships`,
    );
    assert.equal(
      code.includes('FileAccess'),
      false,
      `${rel(file)} uses FileAccess instead of Translation resources`,
    );
  }
  const loader = readFileSync(LOADER, 'utf8');
  assert.match(
    loader,
    /gate_entry\.%s\.translation/u,
    'loader loads one Translation resource per locale',
  );
});
