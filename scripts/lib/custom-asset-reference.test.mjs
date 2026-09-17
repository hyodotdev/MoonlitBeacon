import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const PYTHON_WRAPPER = join(REPO_ROOT, 'scripts/python.mjs');
const CHECKER = join(REPO_ROOT, 'apps/game/tools/check_custom_assets.py');

function makeFixture(reference) {
  const projectRoot = mkdtempSync(join(tmpdir(), 'moonlit-assets-'));
  const contracts = join(projectRoot, 'contracts.json');
  const script = join(projectRoot, 'scripts/reference.gd');
  mkdirSync(dirname(script), { recursive: true });
  writeFileSync(
    contracts,
    JSON.stringify({
      version: 1,
      asset_root: 'assets/custom',
      defaults: {
        status: 'planned',
        format: 'rgba8',
        require_visible: true,
        max_alpha_levels: 5,
      },
      assets: [],
    }),
  );
  writeFileSync(script, `const VISUAL = preload("${reference}")\n`);
  return { contracts, projectRoot };
}

function runChecker(reference) {
  const fixture = makeFixture(reference);
  try {
    return spawnSync(
      process.execPath,
      [
        PYTHON_WRAPPER,
        '-B',
        CHECKER,
        '--project-root',
        fixture.projectRoot,
        '--contracts',
        fixture.contracts,
      ],
      { cwd: REPO_ROOT, encoding: 'utf8' },
    );
  } finally {
    rmSync(fixture.projectRoot, { recursive: true, force: true });
  }
}

test('rejects every active Ninja Adventure PNG reference', () => {
  const result = runChecker(
    'res://assets/third_party/ninja_adventure/new_pack/future_visual.png',
  );
  assert.equal(result.status, 1);
  assert.match(result.stdout, /unreplaced free or derived visual reference/);
});

test('rejects new derived title PNG names without an allowlist update', () => {
  const result = runChecker('res://assets/derived/title/future_visual.png');
  assert.equal(result.status, 1);
  assert.match(result.stdout, /future_visual\.png/);
});

test('allows intentionally retained Ninja Adventure audio', () => {
  const result = runChecker(
    'res://assets/third_party/ninja_adventure/audio/music/arena_theme.ogg',
  );
  assert.equal(result.status, 0, result.stdout + result.stderr);
});
