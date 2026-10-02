import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  APP_STORE_CAPTURE_REPORT_RELATIVE_PATH,
  APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
  IAP_PRODUCT_IDS,
} from './app-store-release.mjs';
import {
  applyPlanEntry,
  auditVersionedIapLocalizations,
  formatAppStoreApplyReport,
  isReviewableIapVersionState,
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

function versionResource(id, attributes) {
  return { id, attributes, type: 'inAppPurchaseVersions' };
}

function approvedTenProductFixture() {
  const products = IAP_PRODUCT_IDS.map((productId) => ({
    localizations: [{
      description: `${productId} description`,
      locale: 'en-US',
      name: `${productId} name`,
    }],
    productId,
  }));
  const remoteIdByProduct = Object.fromEntries(IAP_PRODUCT_IDS.map(
    (productId, index) => [productId, `iap-approved-${index}`],
  ));
  const approvedIdByProduct = Object.fromEntries(IAP_PRODUCT_IDS.map(
    (productId, index) => [productId, `approved-v1-${index}`],
  ));
  const baseAudit = {
    plan: IAP_PRODUCT_IDS.map((productId) => ({
      action: 'none',
      identifier: productId,
      remoteId: remoteIdByProduct[productId],
      target: 'inAppPurchase',
    })),
  };
  return {
    approvedIdByProduct,
    baseAudit,
    products,
    remoteIdByProduct,
  };
}

function remoteIdFromVersionsPath(path) {
  const match = path.match(/inAppPurchases\/([^/]+)\/versions/u);
  assert.ok(match);
  return decodeURIComponent(match[1]);
}

test('approved-only numeric version-1 history for all ten products plans create version 2', async () => {
  assert.equal(IAP_PRODUCT_IDS.length, 10);
  assert.equal(isReviewableIapVersionState('APPROVED'), false);
  const fixture = approvedTenProductFixture();
  const productByRemoteId = Object.fromEntries(IAP_PRODUCT_IDS.map((productId) => (
    [fixture.remoteIdByProduct[productId], productId]
  )));
  const result = await auditVersionedIapLocalizations({
    inAppPurchases: { products: fixture.products },
  }, {
    async getAll(path) {
      assert.match(path, /\/versions\?/u);
      assert.doesNotMatch(path, /\/localizations/u);
      const remoteId = remoteIdFromVersionsPath(path);
      const productId = productByRemoteId[remoteId];
      assert.ok(productId);
      return [versionResource(fixture.approvedIdByProduct[productId], {
        state: 'APPROVED',
        version: 1,
      })];
    },
  }, fixture.baseAudit);
  assert.equal(result.plan.length, 10);
  assert.ok(result.plan.every((entry) => (
    entry.action === 'create'
    && entry.target === 'inAppPurchaseVersion'
    && entry.desired.version === 2
    && entry.capturesCurrentReviewImage === true
    && entry.prerequisites.includes(`inAppPurchase:${entry.identifier}`)
    && entry.prerequisites.includes(`inAppPurchaseReviewImage:${entry.identifier}`)
  )));
  assert.deepEqual(
    result.plan.map((entry) => entry.identifier).sort(),
    [...IAP_PRODUCT_IDS].sort(),
  );
  assert.deepEqual(result.versionIds, {});
  assert.deepEqual(result.versionStates, {});
  assert.equal(result.plan.some((entry) => entry.action === 'unresolved'), false);

  const versionsByRemote = new Map(IAP_PRODUCT_IDS.map((productId) => ([
    fixture.remoteIdByProduct[productId],
    [versionResource(fixture.approvedIdByProduct[productId], {
      state: 'APPROVED',
      version: 1,
    })],
  ])));
  const draftIdByProduct = Object.fromEntries(IAP_PRODUCT_IDS.map(
    (productId, index) => [productId, `draft-v2-${index}`],
  ));
  let posts = 0;
  for (const entry of result.plan) {
    const remoteId = fixture.remoteIdByProduct[entry.identifier];
    assert.equal(entry.parentId, remoteId);
    const before = versionsByRemote.get(remoteId);
    const after = [
      ...before,
      versionResource(draftIdByProduct[entry.identifier], {
        state: 'PREPARE_FOR_SUBMISSION',
        version: 2,
      }),
    ];
    let reads = 0;
    await applyPlanEntry({
      client: {
        async post(path, body) {
          posts += 1;
          assert.equal(path, '/v1/inAppPurchaseVersions');
          assert.equal(Object.hasOwn(body.data, 'attributes'), false);
          assert.equal(body.data.relationships.inAppPurchase.data.id, remoteId);
          versionsByRemote.set(remoteId, after);
          return { data: after[1] };
        },
      },
      entry,
      getClient: {
        async getAll(path) {
          reads += 1;
          assert.match(path, /\/versions\?/u);
          return reads === 1 ? before : after;
        },
      },
      payload: { inAppPurchases: { products: fixture.products } },
    });
    assert.equal(reads, 2);
  }
  assert.equal(posts, 10);

  const localizationPaths = [];
  const converged = await auditVersionedIapLocalizations({
    inAppPurchases: { products: fixture.products },
  }, {
    async getAll(path) {
      if (path.includes('/versions?')) {
        return versionsByRemote.get(remoteIdFromVersionsPath(path));
      }
      localizationPaths.push(path);
      return [];
    },
  }, fixture.baseAudit);
  assert.deepEqual(
    Object.keys(converged.versionIds).sort(),
    [...IAP_PRODUCT_IDS].sort(),
  );
  assert.deepEqual(
    Object.keys(converged.versionStates).sort(),
    [...IAP_PRODUCT_IDS].sort(),
  );
  assert.deepEqual(converged.versionIds, draftIdByProduct);
  assert.ok(Object.values(converged.versionStates).every((state) => (
    state === 'PREPARE_FOR_SUBMISSION' && isReviewableIapVersionState(state)
  )));
  assert.equal(new Set(Object.values(converged.versionIds)).size, 10);
  const approvedIds = new Set(Object.values(fixture.approvedIdByProduct));
  assert.ok(Object.values(converged.versionIds).every((id) => !approvedIds.has(id)));
  const localizationCreates = converged.plan.filter((entry) => (
    entry.target === 'inAppPurchaseVersionLocalization'
  ));
  assert.equal(localizationCreates.length, 10);
  assert.ok(localizationCreates.every((entry) => (
    entry.action === 'create'
    && !approvedIds.has(entry.parentId)
    && Object.values(draftIdByProduct).includes(entry.parentId)
  )));
  assert.equal(converged.plan.some((entry) => entry.action === 'unresolved'), false);
  assert.equal(localizationPaths.length, 10);
  assert.ok(localizationPaths.every((path) => (
    Object.values(draftIdByProduct).some((id) => path.includes(id))
    && ![...approvedIds].some((id) => path.includes(id))
  )));
});

test('mixed or in-flight IAP histories stay unresolved before any mutation', async () => {
  const productId = IAP_PRODUCT_IDS[0];
  const payload = {
    inAppPurchases: { products: [{ localizations: [], productId }] },
  };
  const baseAudit = {
    plan: [{
      action: 'none',
      identifier: productId,
      remoteId: 'iap-mixed',
      target: 'inAppPurchase',
    }],
  };
  const histories = [
    [versionResource('approved-1', { state: 'APPROVED', version: 1 })],
    [versionResource('waiting-1', { state: 'WAITING_FOR_REVIEW', version: 1 })],
    [
      versionResource('approved-1', { state: 'APPROVED', version: 1 }),
      versionResource('waiting-2', { state: 'WAITING_FOR_REVIEW', version: 2 }),
    ],
    [
      versionResource('approved-1', { state: 'APPROVED', version: 1 }),
      versionResource('in-review-2', { state: 'IN_REVIEW', version: 2 }),
    ],
    [
      versionResource('approved-1', { state: 'APPROVED', version: 1 }),
      versionResource('unknown-2', { state: 'SOMETHING_NEW', version: 2 }),
    ],
    [
      versionResource('approved-1', { state: 'APPROVED', version: 1 }),
      versionResource('missing-state-2', { version: 2 }),
    ],
  ];
  const approvedOnly = histories[0];
  const unsupported = histories.slice(1);
  const approvedResult = await auditVersionedIapLocalizations(payload, {
    async getAll(path) {
      assert.match(path, /\/versions\?/u);
      return approvedOnly;
    },
  }, baseAudit);
  assert.equal(approvedResult.plan[0].action, 'create');
  assert.equal(approvedResult.plan[0].desired.version, 2);
  for (const versions of unsupported) {
    let posts = 0;
    const result = await auditVersionedIapLocalizations(payload, {
      async getAll(path) {
        assert.match(path, /\/versions\?/u);
        return versions;
      },
      async post() {
        posts += 1;
        throw new Error('mutation must not run for unsupported history');
      },
    }, baseAudit);
    assert.ok(result.plan.some((entry) => (
      entry.action === 'unresolved'
      && entry.code === 'ASC_IAP_VERSION_STATE_UNSUPPORTED'
      && entry.remoteMutationPlanned === false
    )));
    assert.deepEqual(result.versionIds, {});
    assert.deepEqual(result.versionStates, {});
    assert.equal(result.plan.some((entry) => ['create', 'update'].includes(entry.action)), false);
    assert.equal(posts, 0);
  }
});

test('duplicate or invalid approved-history version numbers stop before a mutation', async () => {
  const productId = IAP_PRODUCT_IDS[1];
  const payload = {
    inAppPurchases: { products: [{ localizations: [], productId }] },
  };
  const baseAudit = {
    plan: [{
      action: 'none',
      identifier: productId,
      remoteId: 'iap-numbering',
      target: 'inAppPurchase',
    }],
  };
  const duplicateHistories = [
    [
      versionResource('approved-a', { state: 'APPROVED', version: 1 }),
      versionResource('approved-b', { state: 'APPROVED', version: 1 }),
    ],
    [
      versionResource('approved-a', { state: 'APPROVED', version: '1' }),
      versionResource('approved-b', { state: 'APPROVED', version: 1 }),
    ],
  ];
  for (const versions of duplicateHistories) {
    await assert.rejects(
      auditVersionedIapLocalizations(payload, {
        async getAll() {
          return versions;
        },
      }, baseAudit),
      /ASC_IAP_VERSION_NUMBER_DUPLICATE/u,
    );
  }
  const invalidHistories = [
    [versionResource('approved-zero', { state: 'APPROVED', version: 0 })],
    [versionResource('approved-zero-text', { state: 'APPROVED', version: '0' })],
    [versionResource('approved-text', { state: 'APPROVED', version: 'abc' })],
    [versionResource('approved-missing', { state: 'APPROVED' })],
    [versionResource('approved-float', { state: 'APPROVED', version: 1.5 })],
  ];
  for (const versions of invalidHistories) {
    await assert.rejects(
      auditVersionedIapLocalizations(payload, {
        async getAll() {
          return versions;
        },
      }, baseAudit),
      /ASC_IAP_VERSION_NUMBER_INVALID/u,
    );
  }
});
