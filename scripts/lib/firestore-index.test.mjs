import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

function readJson(path) {
  return JSON.parse(readFileSync(resolve(repository, path), 'utf8'));
}

test('Firebase config deploys the global leaderboard composite index', () => {
  const firebase = readJson('firebase.json');
  assert.equal(firebase.firestore?.indexes, 'firestore.indexes.json');

  const specification = readJson(firebase.firestore.indexes);
  assert.ok(
    specification.indexes?.some((index) => (
      index.collectionGroup === 'scores'
      && index.queryScope === 'COLLECTION'
      && index.fields?.length === 2
      && index.fields[0]?.fieldPath === 'version'
      && index.fields[0]?.order === 'ASCENDING'
      && index.fields[1]?.fieldPath === 'score'
      && index.fields[1]?.order === 'DESCENDING'
    )),
    'scores(version ASC, score DESC) COLLECTION index is required',
  );
});

test('anonymous analytics source expires after 90 days and does not index ephemeral IDs', () => {
  const firebase = readJson('firebase.json');
  assert.equal(firebase.firestore?.rules, 'firestore.rules');
  const specification = readJson(firebase.firestore.indexes);
  const overrides = specification.fieldOverrides ?? [];
  assert.ok(overrides.some((entry) => (
    entry.collectionGroup === 'analytics_events_v1'
    && entry.fieldPath === 'expires_at'
    && entry.ttl === true
    && Array.isArray(entry.indexes)
    && entry.indexes.length === 0
  )));
  for (const fieldPath of ['session_id', 'run_id']) {
    assert.ok(overrides.some((entry) => (
      entry.collectionGroup === 'analytics_events_v1'
      && entry.fieldPath === fieldPath
      && Array.isArray(entry.indexes)
      && entry.indexes.length === 0
    )), `${fieldPath} single-field index must be disabled`);
  }
});
