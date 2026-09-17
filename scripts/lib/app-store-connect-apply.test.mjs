import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  APP_STORE_CAPTURE_REPORT_RELATIVE_PATH,
  APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
} from './app-store-release.mjs';
import {
  formatAppStoreApplyReport,
  verifyAppStoreReleaseSourceArtifacts,
} from './app-store-connect-apply.mjs';

// Covers the pure seams the client-injected suites cannot reach without a
// live App Store Connect session. appStoreApplyCheckSummary stays out: it is
// a field pluck over two covered functions and needs a full manifest.

function withTempRoot(callback) {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-asc-apply-'));
  try {
    return callback(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function artifactEntry(root, relativePath, contents) {
  const absolute = join(root, relativePath);
  mkdirSync(join(absolute, '..'), { recursive: true });
  const bytes = Buffer.from(contents, 'utf8');
  writeFileSync(absolute, bytes);
  return {
    path: relativePath,
    size: bytes.length,
    sha256: createHash('sha256').update(bytes).digest('hex'),
    md5: createHash('md5').update(bytes).digest('hex'),
  };
}

function sourcesPayload(root) {
  return {
    sources: [
      artifactEntry(root, APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH, '{"shots":[]}'),
      artifactEntry(root, APP_STORE_CAPTURE_REPORT_RELATIVE_PATH, '{"report":true}'),
    ],
  };
}

test('source artifacts verify when both provenance files match the manifest', () => {
  withTempRoot((root) => {
    assert.equal(
      verifyAppStoreReleaseSourceArtifacts({ payload: sourcesPayload(root), repoRoot: root }),
      true,
    );
  });
});

test('source artifacts reject a missing list or a missing entry', () => {
  withTempRoot((root) => {
    assert.throws(
      () => verifyAppStoreReleaseSourceArtifacts({ payload: {}, repoRoot: root }),
      /ASC_RELEASE_SOURCES_INVALID/,
    );
    const payload = sourcesPayload(root);
    payload.sources.pop();
    assert.throws(
      () => verifyAppStoreReleaseSourceArtifacts({ payload, repoRoot: root }),
      /ASC_RELEASE_SOURCE_MISSING/,
    );
  });
});

test('source artifacts reject a duplicated provenance entry', () => {
  withTempRoot((root) => {
    const payload = sourcesPayload(root);
    payload.sources.push({ ...payload.sources[0] });
    assert.throws(
      () => verifyAppStoreReleaseSourceArtifacts({ payload, repoRoot: root }),
      /ASC_RELEASE_SOURCE_MISSING/,
    );
  });
});

test('source artifacts reject size and checksum drift', () => {
  withTempRoot((root) => {
    const payload = sourcesPayload(root);
    writeFileSync(
      join(root, APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH),
      '{"shots":[]}trailing-byte',
    );
    assert.throws(
      () => verifyAppStoreReleaseSourceArtifacts({ payload, repoRoot: root }),
      /ASC_ASSET_CHANGED/,
    );
  });
});

test('source artifacts reject a renamed provenance entry as missing', () => {
  withTempRoot((root) => {
    for (const path of ['/etc/hostname', 'builds/release/app-store/../../outside.json']) {
      const payload = sourcesPayload(root);
      payload.sources[0] = { ...payload.sources[0], path };
      assert.throws(
        () => verifyAppStoreReleaseSourceArtifacts({ payload, repoRoot: root }),
        /ASC_RELEASE_SOURCE_MISSING/,
      );
    }
  });
});

test('source artifacts reject a symlinked provenance file', () => {
  withTempRoot((root) => {
    sourcesPayload(root);
    const target = join(root, APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH);
    const outside = join(root, 'outside.json');
    writeFileSync(outside, '{"shots":[]}');
    rmSync(target);
    symlinkSync(outside, target);
    const payload = {
      sources: [
        {
          path: APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
          size: 14,
          sha256: 'x',
          md5: 'y',
        },
        artifactEntry(root, APP_STORE_CAPTURE_REPORT_RELATIVE_PATH, '{"report":true}'),
      ],
    };
    assert.throws(
      () => verifyAppStoreReleaseSourceArtifacts({ payload, repoRoot: root }),
      /ASC_ASSET_SYMLINK_REJECTED/,
    );
  });
});

test('apply report renders the converged and gated shapes', () => {
  assert.equal(
    formatAppStoreApplyReport({
      complete: true,
      applied: [{}, {}, {}],
      reviewSubmitted: true,
      blockers: [],
    }),
    [
      'App Store Connect remote apply converged through GET revalidation.',
      'applied mutations: 3',
      'review submitted: yes',
    ].join('\n'),
  );
  assert.equal(
    formatAppStoreApplyReport({
      complete: false,
      applied: [{}],
      reviewSubmitted: false,
      blockers: [
        { code: 'ASC_PLAN_PAYLOAD_MISMATCH', target: 'screenshot', identifier: 'ko/iphone' },
        { target: 'iap', identifier: 'hero_dancer' },
      ],
    }),
    [
      'App Store Connect remote apply stopped at a safety gate.',
      'applied mutations: 1',
      'review submitted: no',
      '- ASC_PLAN_PAYLOAD_MISMATCH screenshot ko/iphone',
      '- UNRESOLVED iap hero_dancer',
    ].join('\n'),
  );
});
