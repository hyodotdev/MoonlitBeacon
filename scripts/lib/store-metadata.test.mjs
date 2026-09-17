import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  copyFileSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../..', import.meta.url));
const checkerPath = path.join(repoRoot, 'scripts', 'check-store-metadata.mjs');
const sourcePaths = {
  csv: path.join(repoRoot, 'notes', 'release', 'store-localizations.csv'),
  storePage: path.join(repoRoot, 'notes', 'release', 'store-page.md'),
  iapSetup: path.join(repoRoot, 'notes', 'release', 'iap-store-setup.md'),
};

function runFixture(mutate = () => {}) {
  const fixtureRoot = mkdtempSync(path.join(tmpdir(), 'moonlit-store-metadata-'));
  const fixturePaths = {
    csv: path.join(fixtureRoot, 'store-localizations.csv'),
    storePage: path.join(fixtureRoot, 'store-page.md'),
    iapSetup: path.join(fixtureRoot, 'iap-store-setup.md'),
  };
  try {
    for (const key of Object.keys(fixturePaths)) {
      copyFileSync(sourcePaths[key], fixturePaths[key]);
    }
    mutate(fixturePaths);
    return spawnSync(process.execPath, [checkerPath], {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        MOONLIT_STORE_METADATA_TEST_MODE: '1',
        MOONLIT_STORE_LOCALIZATIONS_PATH: fixturePaths.csv,
        MOONLIT_STORE_PAGE_PATH: fixturePaths.storePage,
        MOONLIT_IAP_STORE_SETUP_PATH: fixturePaths.iapSetup,
      },
    });
  } finally {
    rmSync(fixtureRoot, { force: true, recursive: true });
  }
}

function replaceRequired(filePath, before, after) {
  const source = readFileSync(filePath, 'utf8');
  assert.ok(source.includes(before), `fixture source is missing: ${before}`);
  writeFileSync(filePath, source.replace(before, after));
}

function assertPlaceholderRejected(result) {
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /unresolved placeholder/u);
}

test('accepts historical TODO prose outside submission fields', () => {
  const result = runFixture(({ storePage }) => {
    const source = readFileSync(storePage, 'utf8');
    writeFileSync(
      storePage,
      `${source}\n## Verification notes\n\nHistorically the checker passed even when a TODO marker remained.\n`,
    );
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

test('rejects fixture path overrides outside explicit test mode', () => {
  const env = { ...process.env };
  delete env.MOONLIT_STORE_METADATA_TEST_MODE;
  env.MOONLIT_STORE_PAGE_PATH = sourcePaths.storePage;
  const result = spawnSync(process.execPath, [checkerPath], {
    cwd: repoRoot,
    encoding: 'utf8',
    env,
  });
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /explicit test mode/u);
});

test('rejects TODO in console localization CSV fields', () => {
  const result = runFixture(({ csv }) => {
    replaceRequired(csv, 'Moonlit Beacon', 'TODO: app name');
  });
  assertPlaceholderRejected(result);
});

test('rejects placeholders in full store descriptions', () => {
  const result = runFixture(({ storePage }) => {
    replaceRequired(
      storePage,
      'The moon is hidden and every beacon across three lands has gone out.',
      'TODO: fill in the Korean full description.',
    );
  });
  assertPlaceholderRejected(result);
});

test('rejects placeholders in required release metadata', () => {
  const result = runFixture(({ storePage }) => {
    replaceRequired(storePage, 'non-trader', '<DSA status>');
  });
  assertPlaceholderRejected(result);
});

test('rejects placeholders in App Review copy blocks', () => {
  const result = runFixture(({ iapSetup }) => {
    replaceRequired(iapSetup, 'Launch the app', 'TBD Launch the app');
  });
  assertPlaceholderRejected(result);
});

test('rejects the retired hero bundle from the sale catalog', () => {
  const result = runFixture(({ csv }) => {
    replaceRequired(csv, '.hero_dancer"', '.hero_bundle"');
  });
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /unsupported or stale localization row/u);
});

test('requires every one of the ten products in every locale', () => {
  const result = runFixture(({ csv }) => {
    const source = readFileSync(csv, 'utf8');
    const lines = source.split('\n');
    const index = lines.findIndex((line) =>
      line.includes('"iap","apple","zh-Hant"')
      && line.includes('.hero_sage"'));
    assert.notEqual(index, -1);
    lines.splice(index, 1);
    writeFileSync(csv, lines.join('\n'));
  });
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /missing IAP localization/u);
});
