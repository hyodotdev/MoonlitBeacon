import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  CONFIG_FILE,
  REPO_ROOT,
  catalogProblems,
  configProblems,
  loadConfig,
  modelMentions,
  parseConfig,
  readCatalog,
  whoLine,
} from './muse-config.mjs';

const good = {
  implementer: { name: 'Muse', command: 'muse', model: 'muse-spark-9.9-test', reasoningEffort: 'max' },
  timeoutMinutes: 120,
};

test('the shipped config is valid and names one implementer', () => {
  const { config, problems } = loadConfig(REPO_ROOT);
  assert.deepEqual(problems, []);
  assert.ok(config.model.length > 0);
  assert.ok(config.timeoutMinutes >= 5);
  assert.match(whoLine(config), new RegExp(`^${config.name} \\(${config.model}, ${config.reasoningEffort} effort\\)$`));
});

test('a well-formed config parses, and bad ones say what is wrong', () => {
  assert.equal(parseConfig(JSON.stringify(good)).config.model, 'muse-spark-9.9-test');
  assert.notDeepEqual(parseConfig('{nope').problems, []);
  assert.notDeepEqual(configProblems({}), []);
  assert.ok(configProblems({ ...good, implementer: { ...good.implementer, reasoningEffort: 'ludicrous' } })
    .some((problem) => problem.includes('reasoningEffort')));
  assert.ok(configProblems({ ...good, timeoutMinutes: 1 }).some((problem) => problem.includes('timeoutMinutes')));
  assert.ok(configProblems({ ...good, implementer: { ...good.implementer, command: 'muse; rm' } })
    .some((problem) => problem.includes('command')));
});

test('a model id cannot smuggle a flag into the command line', () => {
  for (const model of ['--yolo', '-x', 'a b', 'model;ls', '']) {
    assert.ok(
      configProblems({ ...good, implementer: { ...good.implementer, model } }).some((problem) => problem.includes('model')),
      `should reject ${JSON.stringify(model)}`,
    );
  }
});

test('the catalog is read from where the CLI keeps it and compared with the config', (t) => {
  const home = mkdtempSync(join(tmpdir(), 'muse-catalog-test-'));
  t.after(() => rmSync(home, { recursive: true, force: true }));
  const directory = join(home, '.local', 'share', 'muse', 'model-catalog');
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(directory, 'a.json'), JSON.stringify({
    rows: [
      { model_id: 'muse-spark-9.9-test', release_date: '2030-01-01', is_current: true, description: 'a note',
        reasoning_effort_variants: [{ tier: 'low' }, { tier: 'max' }] },
      { model_id: 'muse-spark-9.8-test', reasoning_effort_variants: [{ tier: 'low' }] },
    ],
  }));
  writeFileSync(join(directory, 'broken.json'), '{ not json');
  const rows = readCatalog(home);
  assert.deepEqual(rows.map((row) => row.id), ['muse-spark-9.9-test', 'muse-spark-9.8-test']);
  assert.deepEqual(catalogProblems(good.implementer, rows), []);
  assert.ok(catalogProblems({ ...good.implementer, model: 'nope' }, rows)[0].includes('not in the CLI'));
  assert.ok(catalogProblems({ ...good.implementer, model: 'muse-spark-9.8-test' }, rows)[0].includes('does not offer'));
  assert.deepEqual(catalogProblems(good.implementer, []), [], 'no catalog is not an error');
  assert.deepEqual(readCatalog(join(home, 'nowhere')), []);
});

test('only the config may name a model of the implementer family', () => {
  const files = [
    { path: CONFIG_FILE, text: '{"model": "muse-spark-1.3-x"}' },
    { path: 'AGENTS.md', text: 'The implementer is set in scripts/muse.config.json.' },
    { path: 'notes/a.md', text: 'line one\nran with muse-spark-1.3-contributor at max' },
    { path: 'notes/b.md', text: 'see also muse-spark-2.0 and muse-spark-1.2-contributor' },
    { path: 'exempt.md', text: 'muse-spark-1.3' },
  ];
  const found = modelMentions(files, ['exempt.md']);
  assert.equal(found.length, 3);
  assert.ok(found[0].startsWith('notes/a.md:2:'));
  assert.ok(found.every((entry) => !entry.startsWith('AGENTS.md') && !entry.startsWith(CONFIG_FILE)));
});
