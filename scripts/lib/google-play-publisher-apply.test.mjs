import assert from 'node:assert/strict';
import {
  createHash,
  generateKeyPairSync,
  verify,
} from 'node:crypto';
import {
  chmodSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import test from 'node:test';
import {
  applyGooglePlayReleasePlan,
  authorizeGooglePlayProductAdoption,
  authorizeGooglePlayProductResume,
  buildGooglePlayProductSyncPlan,
  createGooglePlayApplyPlan,
  createGooglePlayPublisherClient,
  createServiceAccountAssertion,
  inspectOneTimeProductApplyReadiness,
  parseGooglePlayApplyArguments,
  prepareGooglePlayProductSync,
  promoteGooglePlayReleaseToProduction,
  readGooglePlayReviewReceipt,
  submitGooglePlayProductionReview,
  readGooglePlayApplyReceipt,
  readGooglePlayPromotionReceipt,
  requestGoogleAccessToken,
  synchronizeGooglePlayOneTimeProducts,
  verifyManifestInputsAreCurrent,
} from './google-play-publisher-apply.mjs';
import {
  PLAY_CONSUMABLE_PRODUCT_IDS,
  PLAY_LOCALES,
  PLAY_PACKAGE_NAME,
  PLAY_PRODUCT_IDS,
  PLAY_SCREENSHOT_NAMES,
  PLAY_SCREENSHOT_TARGETS,
} from './play-release-package.mjs';

function sha256(contents) {
  return createHash('sha256').update(contents).digest('hex');
}

function withTempRoot(callback) {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-play-apply-'));
  return Promise.resolve()
    .then(() => callback(root))
    .finally(() => rmSync(root, { recursive: true, force: true }));
}

function writeJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function writeOwnerOnlyJson(path, value) {
  writeJson(path, value);
  chmodSync(path, 0o600);
}

function packageFileRecords(root, directory = root) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return packageFileRecords(root, path);
    const contents = readFileSync(path);
    return [{
      bytes: contents.length,
      path: relative(root, path).replaceAll('\\', '/'),
      sha256: sha256(contents),
    }];
  }).sort((left, right) => left.path.localeCompare(right.path));
}

function response(body, {
  headers = {},
  ok = true,
  status = 200,
} = {}) {
  return {
    headers: new Headers(headers),
    ok,
    status,
    text: async () => body === null ? '' : JSON.stringify(body),
  };
}

function configFixture() {
  return {
    changesInReviewBehavior: 'ERROR_IF_IN_REVIEW',
    legalDeclarations: {
      googlePlayDeveloperProgramPoliciesAccepted: true,
      recordedFrom: 'account_owner_explicit_approval',
      unitedStatesExportLawsAccepted: true,
    },
    oneTimeProducts: productPolicyFixture(),
    packageName: PLAY_PACKAGE_NAME,
    releaseStatus: 'completed',
    schemaVersion: 2,
    sendChangesForReview: true,
    track: 'internal',
  };
}

function money(currencyCode, units, nanos = 0) {
  return { currencyCode, nanos, units: String(units) };
}

function productPolicyFixture() {
  const products = [
    [`${PLAY_PACKAGE_NAME}.supporter`, money('KRW', 3300), 'KR', money('KRW', 3300), money('KRW', 0)],
    [`${PLAY_PACKAGE_NAME}.hero_dancer`, money('USD', 4, 990_000_000), 'US', money('USD', 4, 990_000_000), null],
    [`${PLAY_PACKAGE_NAME}.hero_keeper`, money('USD', 9, 990_000_000), 'US', money('USD', 9, 990_000_000), null],
    [`${PLAY_PACKAGE_NAME}.hero_knight`, money('USD', 14, 990_000_000), 'US', money('USD', 14, 990_000_000), null],
    [`${PLAY_PACKAGE_NAME}.hero_eclipse`, money('USD', 19, 990_000_000), 'US', money('USD', 19, 990_000_000), null],
    [`${PLAY_PACKAGE_NAME}.hero_sage`, money('USD', 24, 990_000_000), 'US', money('USD', 24, 990_000_000), null],
    [`${PLAY_PACKAGE_NAME}.lantern_colors`, money('KRW', 1100), 'KR', money('KRW', 1100), money('KRW', 0)],
  ].map(([productId, basePrice, regionCode, price, taxAmount]) => ({
    basePrice,
    expectedAnchor: { price, regionCode, taxAmount },
    productId,
  }));
  return {
    excludedRegions: ['CN'],
    legacyProductId: `${PLAY_PACKAGE_NAME}.hero_bundle`,
    newRegionsAutomaticallyAvailable: false,
    products,
    purchaseOptionId: 'buy',
    regionalAvailability: 'AVAILABLE',
  };
}

function historicGates() {
  return {
    googlePlayLegalDeclarations: {
      ready: false,
    },
    googleServiceAccount: {
      credentialMaterialIncluded: false,
    },
    oneTimeProductSetup: {
      localizationPayloadsReady: true,
      pricingAndAvailabilityConfigured: false,
      purchaseOptionsConfigured: false,
      ready: false,
      regionsVersionConfigured: false,
    },
    publicContact: {
      ready: true,
    },
    remoteActionsReady: false,
  };
}

function writePlanFixture(root) {
  const output = join(root, 'builds/release/google-play-upload');
  mkdirSync(output, { recursive: true });
  writeFileSync(join(root, 'input.txt'), 'current-input\n');
  writeJson(join(root, 'notes/release/google-play-remote-apply.json'), configFixture());
  for (const language of PLAY_LOCALES) {
    writeJson(
      join(output, `publisher-api/edits.listings.update/${language}.json`),
      {
        apiBoundary: 'edits.listings.update',
        body: {
          fullDescription: `Full ${language}`,
          language,
          shortDescription: `Short ${language}`,
          title: `Title ${language}`,
        },
        method: 'PUT',
        remoteApplyAllowed: false,
      },
    );
  }
  const imageTypes = [
    'icon',
    'featureGraphic',
    ...PLAY_SCREENSHOT_TARGETS.map(({ imageType }) => imageType),
  ];
  const resetBeforeUpload = PLAY_LOCALES.flatMap((language) =>
    imageTypes.map((imageType) => ({
      imageType,
      language,
      method: 'DELETE',
      remoteApplyAllowed: false,
    })));
  const mediaOperation = (language, imageType, mediaPath) => {
    const contents = Buffer.from(`${language}:${imageType}:${mediaPath}`);
    mkdirSync(dirname(join(output, mediaPath)), { recursive: true });
    writeFileSync(join(output, mediaPath), contents);
    return {
      imageType,
      language,
      mediaPath,
      method: 'POST',
      remoteApplyAllowed: false,
      sha256: sha256(contents),
    };
  };
  const uploadOperations = PLAY_LOCALES.flatMap((language) => [
    ...['icon', 'featureGraphic'].map((imageType) => mediaOperation(
      language,
      imageType,
      `media/${language}/${imageType}.png`,
    )),
    ...PLAY_SCREENSHOT_TARGETS.flatMap(({ imageType }) =>
      PLAY_SCREENSHOT_NAMES.map((name) => mediaOperation(
        language,
        imageType,
        `media/${language}/${imageType}/${name}`,
      ))),
  ]);
  writeJson(
    join(output, 'publisher-api/edits.images.upload/operations.json'),
    {
      apiBoundary: 'edits.images.upload',
      remoteApplyAllowed: false,
      resetBeforeUpload,
      uploadOperations,
    },
  );
  writeJson(
    join(output, 'publisher-api/edits.tracks.update/release-notes.json'),
    {
      apiBoundary: 'edits.tracks.update',
      futureTrackReleaseFragment: {
        releaseNotes: PLAY_LOCALES.map((language) => ({
          language,
          text: `Release ${language}`,
        })),
      },
      remoteApplyAllowed: false,
    },
  );
  const productOperations = PLAY_PRODUCT_IDS.map((productId) => {
    const suffix = productId.slice(`${PLAY_PACKAGE_NAME}.`.length);
    const file = `publisher-api/monetization.onetimeproducts/${suffix}.patch.json`;
    const listings = PLAY_LOCALES.map((languageCode) => ({
      description: `Description ${productId} ${languageCode}`,
      languageCode,
      title: `Title ${productId} ${languageCode}`,
    }));
    writeJson(join(output, file), {
      apiBoundary: 'monetization.onetimeproducts.patch',
      body: {
        listings,
        packageName: PLAY_PACKAGE_NAME,
        productId,
      },
      method: 'PATCH',
      remoteApplyAllowed: false,
    });
    return {
      allowMissing: false,
      file,
      mode: 'existing_product_localization_update_only',
      productId,
      regionsVersion: null,
      updateMask: 'listings',
    };
  });
  writeJson(
    join(output, 'publisher-api/monetization.onetimeproducts/operations.json'),
    {
      apiBoundary: 'monetization.onetimeproducts',
      creationPayloadIncluded: false,
      operations: productOperations,
      pricingAndAvailabilityIncluded: false,
      purchaseOptionsIncluded: false,
      regionsVersionIncluded: false,
      remoteApplyAllowed: false,
    },
  );
  const input = readFileSync(join(root, 'input.txt'));
  const bundlePath = 'publisher-api/edits.bundles.upload/MoonlitBeacon.aab';
  const bundle = Buffer.from('signed-aab-fixture');
  mkdirSync(dirname(join(output, bundlePath)), { recursive: true });
  writeFileSync(join(output, bundlePath), bundle);
  const manifest = {
    apiApplication: {
      implemented: false,
      remoteApplyAllowed: false,
    },
    counts: {
      imageDeleteAllOperations: resetBeforeUpload.length,
      imageOperations: uploadOperations.length,
      listingPayloads: PLAY_LOCALES.length,
    },
    gates: historicGates(),
    files: packageFileRecords(output),
    inputs: [{
      bytes: input.length,
      path: 'input.txt',
      sha256: sha256(input),
    }],
    packageName: PLAY_PACKAGE_NAME,
    release: {
      bundle: {
        path: bundlePath,
        sha256: sha256(bundle),
      },
      finalSubmissionAab: true,
      versionCode: 2,
      versionName: '1.0.1',
    },
  };
  writeJson(join(output, 'manifest.json'), manifest);
  return { manifest, output };
}

test('CLI requires an explicit check or confirmed apply mode', () => {
  assert.deepEqual(parseGooglePlayApplyArguments(['--check']), {
    adoptCommittedRelease: false,
    apply: false,
    check: true,
    config: 'notes/release/google-play-remote-apply.json',
    confirmation: null,
    help: false,
    includeProducts: false,
    json: false,
    package: 'builds/release/google-play-upload',
    productsConfirmation: null,
    promoteProduction: false,
    promotionConfirmation: null,
    receipt: 'builds/release/google-play-apply-receipt.json',
    resumeProducts: false,
    reviewConfirmation: null,
    submitProductionReview: false,
  });
  assert.equal(
    parseGooglePlayApplyArguments([
      '--apply',
      '--confirm-remote-apply',
      'google-play:confirmation',
    ]).confirmation,
    'google-play:confirmation',
  );
  assert.throws(
    () => parseGooglePlayApplyArguments([]),
    /exactly one/u,
  );
  assert.throws(
    () => parseGooglePlayApplyArguments(['--apply']),
    /confirm-remote-apply/u,
  );
  assert.throws(
    () => parseGooglePlayApplyArguments(['--check', '--apply']),
    /exactly one/u,
  );
  assert.throws(
    () => parseGooglePlayApplyArguments([
      '--apply',
      '--confirm-remote-apply',
      'app-token',
      '--include-products',
    ]),
    /confirm-products/u,
  );
  assert.equal(parseGooglePlayApplyArguments([
    '--apply',
    '--confirm-remote-apply',
    'app-token',
    '--include-products',
    '--confirm-products',
    'product-token',
  ]).productsConfirmation, 'product-token');
  const resume = parseGooglePlayApplyArguments([
    '--resume-products',
    '--confirm-remote-apply',
    'app-token',
    '--confirm-products',
    'product-token',
  ]);
  assert.equal(resume.resumeProducts, true);
  assert.equal(resume.includeProducts, true);
  assert.equal(resume.receipt, 'builds/release/google-play-apply-receipt.json');
  const adoption = parseGooglePlayApplyArguments([
    '--adopt-committed-release',
    '--confirm-remote-apply',
    'app-token',
    '--confirm-products',
    'product-token',
  ]);
  assert.equal(adoption.adoptCommittedRelease, true);
  assert.equal(adoption.includeProducts, true);
  assert.equal(adoption.confirmation, 'app-token');
  assert.equal(adoption.productsConfirmation, 'product-token');
  assert.throws(
    () => parseGooglePlayApplyArguments([
      '--adopt-committed-release',
      '--confirm-remote-apply',
      'app-token',
    ]),
    /confirm-products/u,
  );
  assert.throws(
    () => parseGooglePlayApplyArguments([
      '--check',
      '--receipt',
      'builds/release/alternate-receipt.json',
    ]),
    /unsupported option/u,
  );
  assert.throws(
    () => parseGooglePlayApplyArguments([
      '--apply',
      '--resume-products',
      '--confirm-remote-apply',
      'app-token',
      '--confirm-products',
      'product-token',
    ]),
    /exactly one/u,
  );
  assert.throws(
    () => parseGooglePlayApplyArguments([
      '--resume-products',
      '--adopt-committed-release',
      '--confirm-remote-apply',
      'app-token',
      '--confirm-products',
      'product-token',
    ]),
    /exactly one/u,
  );
});

test('manifest input verification fails closed when a source changes', () =>
  withTempRoot((root) => {
    writeFileSync(join(root, 'source.txt'), 'before');
    const manifest = {
      inputs: [{
        bytes: 6,
        path: 'source.txt',
        sha256: sha256('before'),
      }],
    };
    assert.equal(verifyManifestInputsAreCurrent(root, manifest), true);
    writeFileSync(join(root, 'source.txt'), 'after!');
    assert.throws(
      () => verifyManifestInputsAreCurrent(root, manifest),
      /differs from current input/u,
    );
  }));

test('apply plan binds app and seven-product confirmations to verified inputs', () =>
  withTempRoot((root) => {
    const { manifest } = writePlanFixture(root);
    const plan = createGooglePlayApplyPlan({
      inspectServiceAccount: () => ({
        configured: true,
        ready: true,
        reason: 'credential_validated_locally',
      }),
      root,
      verifyPackage: () => manifest,
    });
    assert.equal(plan.ready, true);
    assert.equal(plan.release.track, 'internal');
    assert.equal(plan.release.status, 'completed');
    assert.equal(plan.review.changesInReviewBehavior, 'ERROR_IF_IN_REVIEW');
    assert.equal(plan.listings.length, 5);
    assert.equal(plan.images.resetBeforeUpload.length, 25);
    assert.equal(plan.images.uploadOperations.length, 100);
    assert.equal(plan.includeProductsAllowed, true);
    assert.equal(plan.products.listings.length, 7);
    assert.match(plan.products.confirmationToken, /^google-play-products:/u);
    assert.match(plan.confirmationToken, /^google-play:/u);
    const supporter = plan.products.policy.products[0];
    const lantern = plan.products.policy.products[6];
    assert.deepEqual(supporter.basePrice, money('KRW', 3300));
    assert.deepEqual(supporter.expectedAnchor.taxAmount, money('KRW', 0));
    assert.deepEqual(lantern.basePrice, money('KRW', 1100));
    assert.deepEqual(lantern.expectedAnchor.taxAmount, money('KRW', 0));
    assert.equal(Object.isFrozen(plan), true);
    assert.equal(Object.isFrozen(plan.images.uploadOperations), true);
  }));

test('manifest-bound listing, image plan, and release notes reject post-verify changes', async () => {
  const scenarios = [
    'publisher-api/edits.listings.update/en-US.json',
    'publisher-api/edits.images.upload/operations.json',
    'publisher-api/edits.tracks.update/release-notes.json',
  ];
  for (const relativePath of scenarios) {
    await withTempRoot((root) => {
      const { manifest, output } = writePlanFixture(root);
      assert.throws(
        () => createGooglePlayApplyPlan({
          inspectServiceAccount: () => ({
            configured: true,
            ready: true,
            reason: 'credential_validated_locally',
          }),
          root,
          verifyPackage: () => {
            writeJson(join(output, relativePath), { changedAfterVerify: true });
            return manifest;
          },
        }),
        /differs from the manifest snapshot/u,
        relativePath,
      );
    });
  }
});

test('apply plan keeps operation JSON as an immutable verified snapshot', () =>
  withTempRoot((root) => {
    const { manifest, output } = writePlanFixture(root);
    const plan = createGooglePlayApplyPlan({
      inspectServiceAccount: () => ({
        configured: true,
        ready: true,
        reason: 'credential_validated_locally',
      }),
      root,
      verifyPackage: () => manifest,
    });
    const snapshot = structuredClone({
      images: plan.images,
      listings: plan.listings,
      releaseNotes: plan.release.releaseNotes,
    });
    writeJson(
      join(output, 'publisher-api/edits.listings.update/en-US.json'),
      { changedAfterPlan: true },
    );
    writeJson(
      join(output, 'publisher-api/edits.images.upload/operations.json'),
      { changedAfterPlan: true },
    );
    writeJson(
      join(output, 'publisher-api/edits.tracks.update/release-notes.json'),
      { changedAfterPlan: true },
    );
    assert.deepEqual({
      images: plan.images,
      listings: plan.listings,
      releaseNotes: plan.release.releaseNotes,
    }, snapshot);
    assert.throws(() => {
      plan.listings[0].body.title = 'forged';
    }, TypeError);
  }));

test('packaged one-time product localizations remain fail-closed inputs', () => {
  const blocked = inspectOneTimeProductApplyReadiness({
    creationPayloadIncluded: false,
    operations: [],
    pricingAndAvailabilityIncluded: false,
    purchaseOptionsIncluded: false,
    regionsVersionIncluded: false,
    remoteApplyAllowed: false,
  });
  assert.equal(blocked.ready, false);
  assert.match(blocked.blocker, /fail-closed/u);

  const ready = inspectOneTimeProductApplyReadiness({
    creationPayloadIncluded: false,
    operations: PLAY_PRODUCT_IDS.map((productId) => ({
      allowMissing: false,
      mode: 'existing_product_localization_update_only',
      productId,
      regionsVersion: null,
      updateMask: 'listings',
    })),
    pricingAndAvailabilityIncluded: false,
    purchaseOptionsIncluded: false,
    regionsVersionIncluded: false,
    remoteApplyAllowed: false,
  });
  assert.equal(ready.ready, true);
  assert.equal(ready.blocker, null);
});

test('service-account assertion uses the documented RS256 one-hour claims', () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
  });
  const assertion = createServiceAccountAssertion({
    clientEmail: 'publisher@example.iam.gserviceaccount.com',
    privateKey,
    privateKeyId: 'a'.repeat(40),
  }, { nowSeconds: 1_800_000_000 });
  const [header, claims, signature] = assertion.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), {
    alg: 'RS256',
    kid: 'a'.repeat(40),
    typ: 'JWT',
  });
  assert.deepEqual(JSON.parse(Buffer.from(claims, 'base64url')), {
    aud: 'https://oauth2.googleapis.com/token',
    exp: 1_800_003_600,
    iat: 1_800_000_000,
    iss: 'publisher@example.iam.gserviceaccount.com',
    scope: 'https://www.googleapis.com/auth/androidpublisher',
  });
  assert.equal(verify(
    'RSA-SHA256',
    Buffer.from(`${header}.${claims}`),
    publicKey,
    Buffer.from(signature, 'base64url'),
  ), true);
});

test('OAuth exchange sends credentials only in the request body', async () => {
  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const calls = [];
  const token = await requestGoogleAccessToken({
    clientEmail: 'publisher@example.iam.gserviceaccount.com',
    privateKey,
    privateKeyId: 'b'.repeat(40),
  }, {
    fetchImpl: async (url, options) => {
      calls.push({ options, url: String(url) });
      return response({
        access_token: 'token-with-at-least-twenty-characters',
        expires_in: 3600,
        token_type: 'Bearer',
      });
    },
    nowSeconds: 1_800_000_000,
  });
  assert.equal(token, 'token-with-at-least-twenty-characters');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://oauth2.googleapis.com/token');
  assert.equal(calls[0].url.includes('assertion='), false);
  assert.match(String(calls[0].options.body), /assertion=/u);
});

test('publisher client uses resumable AAB upload and allowlisted endpoints', () =>
  withTempRoot(async (root) => {
    const credentialRoot = mkdtempSync(join(tmpdir(), 'moonlit-google-credential-'));
    try {
      const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
      const credentialPath = join(credentialRoot, 'service-account.json');
      writeJson(credentialPath, {
        client_email: 'publisher@example.iam.gserviceaccount.com',
        private_key: privateKey.export({ format: 'pem', type: 'pkcs8' }),
        private_key_id: 'c'.repeat(40),
        project_id: 'moonlit-publisher-123',
        token_uri: 'https://oauth2.googleapis.com/token',
        type: 'service_account',
      });
      chmodSync(credentialPath, 0o600);
      const calls = [];
      const fetchImpl = async (url, options) => {
        calls.push({ options, url: String(url) });
        if (calls.length === 1) {
          return response({
            access_token: 'token-with-at-least-twenty-characters',
            expires_in: 3600,
            token_type: 'Bearer',
          });
        }
        if (calls.length === 2) {
          return response(null, {
            headers: {
              location: 'https://androidpublisher.googleapis.com/upload-session/abc',
            },
          });
        }
        return response({ versionCode: 2 });
      };
      const client = await createGooglePlayPublisherClient({
        env: { GOOGLE_APPLICATION_CREDENTIALS: credentialPath },
        fetchImpl,
        root,
      });
      const result = await client.uploadBundle(PLAY_PACKAGE_NAME, 'edit-1', Buffer.from('aab'));
      assert.equal(result.versionCode, 2);
      assert.match(calls[1].url, /uploadType=resumable/u);
      assert.equal(calls[1].options.method, 'POST');
      assert.equal(calls[2].url, 'https://androidpublisher.googleapis.com/upload-session/abc');
      assert.equal(calls[2].options.method, 'PUT');
      assert.match(calls[2].options.headers.get('authorization'), /^Bearer /u);
      await client.convertRegionPrices(PLAY_PACKAGE_NAME, money('USD', 4, 990_000_000));
      await client.listOneTimeProducts(PLAY_PACKAGE_NAME, 'page-2');
      await client.batchGetOneTimeProducts(
        PLAY_PACKAGE_NAME,
        PLAY_PRODUCT_IDS.slice(0, 2),
      );
      await client.batchUpdateOneTimeProducts(PLAY_PACKAGE_NAME, { requests: [] });
      await client.batchUpdatePurchaseOptionStates(
        PLAY_PACKAGE_NAME,
        { requests: [] },
      );
      await client.listTrackReleases(PLAY_PACKAGE_NAME, 'internal');
      assert.match(calls[3].url, /\/pricing:convertRegionPrices$/u);
      assert.deepEqual(JSON.parse(calls[3].options.body), {
        price: money('USD', 4, 990_000_000),
      });
      assert.match(calls[4].url, /\/oneTimeProducts\?pageSize=1000&pageToken=page-2$/u);
      const batchGetUrl = new URL(calls[5].url);
      assert.match(batchGetUrl.pathname, /\/oneTimeProducts:batchGet$/u);
      assert.deepEqual(
        batchGetUrl.searchParams.getAll('productIds'),
        PLAY_PRODUCT_IDS.slice(0, 2),
      );
      assert.match(calls[6].url, /\/oneTimeProducts:batchUpdate$/u);
      assert.match(
        calls[7].url,
        /\/oneTimeProducts\/-\/purchaseOptions:batchUpdateStates$/u,
      );
      assert.match(
        calls[8].url,
        /\/tracks\/internal\/releases$/u,
      );
    } finally {
      rmSync(credentialRoot, { recursive: true, force: true });
    }
  }));

function applyFixture(root) {
  const outputPath = join(root, 'package');
  mkdirSync(outputPath, { recursive: true });
  const bundle = Buffer.from('signed-aab-fixture');
  const image = Buffer.from('png-fixture');
  writeFileSync(join(outputPath, 'bundle.aab'), bundle);
  writeFileSync(join(outputPath, 'image.png'), image);
  writeJson(join(outputPath, 'manifest.json'), {
    release: {
      bundle: {
        path: 'bundle.aab',
        sha256: sha256(bundle),
      },
    },
  });
  return {
    blockers: [],
    bundle: {
      path: 'bundle.aab',
      sha256: sha256(bundle),
    },
    confirmationToken: 'confirmation',
    images: {
      resetBeforeUpload: [{ imageType: 'icon', language: 'en-US' }],
      uploadOperations: [{
        imageType: 'icon',
        language: 'en-US',
        mediaPath: 'image.png',
        sha256: sha256(image),
      }],
    },
    listings: [{
      body: { language: 'en-US', title: 'Moonlit Beacon' },
      language: 'en-US',
    }],
    manifestDigest: 'd'.repeat(64),
    outputPath,
    packageName: PLAY_PACKAGE_NAME,
    productBlocker: 'product blocker',
    ready: true,
    receiptPath: join(root, 'google-play-apply-receipt.json'),
    release: {
      name: 'Moonlit Beacon 1.0.1',
      releaseNotes: [{ language: 'en-US', text: 'Release' }],
      status: 'completed',
      track: 'internal',
      versionCode: '2',
      versionName: '1.0.1',
    },
    review: {
      changesInReviewBehavior: 'ERROR_IF_IN_REVIEW',
      changesNotSentForReview: false,
    },
  };
}

function productReadyApplyFixture(root) {
  const plan = applyFixture(root);
  const policy = productPolicyFixture();
  plan.includeProductsAllowed = true;
  plan.products = {
    bindingDigest: 'e'.repeat(64),
    confirmationToken: 'products-confirmation',
    listings: PLAY_PRODUCT_IDS.map((productId) => ({
      listings: PLAY_LOCALES.map((languageCode) => ({
        description: `Description ${productId} ${languageCode}`,
        languageCode,
        title: `Title ${productId} ${languageCode}`,
      })),
      productId,
    })),
    policy,
  };
  return plan;
}

function supportedRegionCodesFixture(count = 173) {
  const result = ['JP', 'KR', 'US'];
  for (let first = 65; first <= 90 && result.length < count; first += 1) {
    for (let second = 65; second <= 90 && result.length < count; second += 1) {
      const regionCode = String.fromCharCode(first, second);
      if (regionCode !== 'CN' && !result.includes(regionCode)) result.push(regionCode);
    }
  }
  assert.equal(result.length, count);
  return result;
}

function conversionFixtures(
  policy = productPolicyFixture(),
  regionCodes = ['JP', 'KR', 'US'],
) {
  return policy.products.map((contract) => {
    const convertedRegionPrices = Object.fromEntries(regionCodes.map(
      (regionCode, index) => {
        let price = money('USD', 1 + (index % 25), 990_000_000);
        let taxAmount = money('USD', 0);
        if (regionCode === 'JP') {
          price = money(
            'JPY',
            contract.basePrice.currencyCode === 'KRW' ? 350 : 700,
          );
          taxAmount = money('JPY', 0);
        } else if (regionCode === 'KR') {
          price = contract.expectedAnchor.regionCode === 'KR'
            ? contract.expectedAnchor.price
            : money('KRW', 7000);
          taxAmount = contract.expectedAnchor.regionCode === 'KR'
            ? contract.expectedAnchor.taxAmount
            : money('KRW', 636);
        } else if (regionCode === 'US') {
          price = contract.expectedAnchor.regionCode === 'US'
            ? contract.expectedAnchor.price
            : money('USD', 2, 990_000_000);
          taxAmount = money('USD', 0);
        }
        return [regionCode, { price, regionCode, taxAmount }];
      },
    ));
    return {
      convertedOtherRegionsPrice: {
        eurPrice: money('EUR', 2, 490_000_000),
        usdPrice: money('USD', 2, 990_000_000),
      },
      convertedRegionPrices,
      regionVersion: { version: '2026/08' },
    };
  });
}

function returnedProduct(product, state = 'ACTIVE') {
  const result = structuredClone(product);
  result.purchaseOptions[0].state = state;
  return result;
}

function existingRemoteProducts(syncPlan, policy, legacyState = 'INACTIVE') {
  const products = syncPlan.products.map((desired, index) => {
    const contract = policy.products[index];
    const anchor = desired.purchaseOptions[0]
      .regionalPricingAndAvailabilityConfigs.find(
        ({ regionCode }) => regionCode === contract.expectedAnchor.regionCode,
      );
    const existing = returnedProduct(desired);
    existing.listings = existing.listings.slice(0, 1);
    existing.purchaseOptions[0].regionalPricingAndAvailabilityConfigs = [anchor];
    if ([0, 6].includes(index)) {
      const priceOffset = index === 0 ? 3 : 1;
      existing.purchaseOptions[0].newRegionsConfig = {
        availability: 'AVAILABLE',
        eurPrice: money('EUR', priceOffset, 190_000_000),
        usdPrice: money('USD', priceOffset, 790_000_000),
      };
    }
    return existing;
  });
  products.push({
    listings: [],
    packageName: PLAY_PACKAGE_NAME,
    productId: policy.legacyProductId,
    purchaseOptions: [{
      buyOption: {
        legacyCompatible: true,
        multiQuantityEnabled: false,
      },
      newRegionsConfig: {
        availability: 'AVAILABLE',
        eurPrice: money('EUR', 9, 990_000_000),
        usdPrice: money('USD', 9, 990_000_000),
      },
      purchaseOptionId: 'buy',
      state: legacyState,
    }],
  });
  return products;
}

function migratedSyncPlanFixture(syncPlan, before) {
  const migrated = structuredClone(syncPlan);
  for (const [index, product] of migrated.products.entries()) {
    const existing = before.find(({ productId }) => productId === product.productId);
    const existingConfig = existing?.purchaseOptions?.[0]?.newRegionsConfig;
    if (existingConfig === undefined) continue;
    const newRegionsConfig = {
      ...structuredClone(existingConfig),
      availability: 'NO_LONGER_AVAILABLE',
    };
    product.purchaseOptions[0].newRegionsConfig = newRegionsConfig;
    migrated.batchUpdateBody.requests[index]
      .oneTimeProduct.purchaseOptions[0].newRegionsConfig = newRegionsConfig;
  }
  return migrated;
}

function productRemoteFixture(plan, {
  events = [],
  failBatchUpdate = false,
  legacyState = 'INACTIVE',
  preservedProducts = [],
  regionCodes = ['JP', 'KR', 'US'],
  releaseLifecycleState = 'RELEASE_LIFECYCLE_STATE_PUBLISHED',
  releaseVersionCode = plan.release.versionCode,
} = {}) {
  const conversions = conversionFixtures(plan.products.policy, regionCodes);
  const baseSyncPlan = buildGooglePlayProductSyncPlan(plan, conversions);
  const managedBefore = existingRemoteProducts(
    baseSyncPlan,
    plan.products.policy,
    legacyState,
  );
  const before = [...managedBefore, ...structuredClone(preservedProducts)];
  const syncPlan = migratedSyncPlanFixture(baseSyncPlan, before);
  const legacy = structuredClone(managedBefore.at(-1));
  const finalProducts = [
    ...syncPlan.products.map((product) => returnedProduct(product)),
    legacy,
    ...structuredClone(preservedProducts),
  ];
  const batchUpdateBodies = [];
  let listCalls = 0;
  const client = {
    ...successfulAppClient(events),
    batchGetOneTimeProducts: async () => ({
      oneTimeProducts: finalProducts.slice(0, 7),
    }),
    batchUpdateOneTimeProducts: async (_packageName, body) => {
      events.push('products-batch-update');
      batchUpdateBodies.push(structuredClone(body));
      if (failBatchUpdate) throw new Error('simulated product transport failure');
      return { oneTimeProducts: finalProducts.slice(0, 7) };
    },
    batchUpdatePurchaseOptionStates: async () => {
      throw new Error('must not re-activate an already-active product.');
    },
    convertRegionPrices: async (_packageName, price) => {
      const index = plan.products.policy.products.findIndex(
        ({ basePrice }) => JSON.stringify(basePrice) === JSON.stringify(price),
      );
      events.push(`convert-${index}`);
      return conversions[index];
    },
    listOneTimeProducts: async () => {
      listCalls += 1;
      events.push(listCalls === 1 ? 'products-preflight' : 'products-final-list');
      return { oneTimeProducts: listCalls === 1 ? before : finalProducts };
    },
    listTrackReleases: async () => {
      events.push('track-releases');
      return {
        releases: [{
          activeArtifacts: [{ versionCode: releaseVersionCode }],
          releaseLifecycleState,
          releaseName: plan.release.name,
          track: plan.release.track,
        }],
      };
    },
  };
  return {
    batchUpdateBodies,
    before,
    client,
    finalProducts,
    syncPlan,
  };
}

function successfulAppClient(events = []) {
  return {
    commitEdit: async () => {
      events.push('commit');
      return { id: 'edit-1' };
    },
    deleteAllImages: async () => events.push('reset-image'),
    discardEdit: async () => events.push('discard'),
    insertEdit: async () => {
      events.push('insert');
      return { id: 'edit-1' };
    },
    updateListing: async (_packageName, _editId, _language, body) => {
      events.push('listing');
      return body;
    },
    updateTrack: async (_packageName, _editId, _track, body) => {
      events.push('track');
      return body;
    },
    uploadBundle: async () => {
      events.push('bundle');
      return {
        sha256: sha256(Buffer.from('signed-aab-fixture')),
        versionCode: '2',
      };
    },
    uploadImage: async () => {
      events.push('image');
      return { image: { id: 'image-1' } };
    },
    validateEdit: async () => {
      events.push('validate');
      return { id: 'edit-1' };
    },
  };
}

test('regional conversion builds seven deterministic all-region buy options', () =>
  withTempRoot((root) => {
    const plan = productReadyApplyFixture(root);
    const conversions = conversionFixtures(plan.products.policy);
    const syncPlan = buildGooglePlayProductSyncPlan(plan, conversions);
    assert.equal(plan.products.policy.newRegionsAutomaticallyAvailable, false);
    assert.equal(syncPlan.products.length, 7);
    assert.equal(syncPlan.regionsVersion, '2026/08');
    assert.deepEqual(syncPlan.regionCodes, ['JP', 'KR', 'US']);
    assert.equal(syncPlan.batchUpdateBody.requests.length, 7);
    assert.equal(syncPlan.activationBody.requests.length, 7);
    for (const [index, request] of syncPlan.batchUpdateBody.requests.entries()) {
      assert.equal(request.allowMissing, true);
      assert.deepEqual(request.regionsVersion, { version: '2026/08' });
      assert.equal(request.updateMask, 'listings,purchaseOptions');
      assert.equal(request.oneTimeProduct.listings.length, 5);
      const option = request.oneTimeProduct.purchaseOptions[0];
      assert.equal(option.purchaseOptionId, 'buy');
      assert.deepEqual(option.buyOption, {
        legacyCompatible: true,
        multiQuantityEnabled: false,
      });
      assert.equal(Object.hasOwn(option, 'newRegionsConfig'), false);
      assert.equal(
        option.regionalPricingAndAvailabilityConfigs.every(
          ({ availability, regionCode }) => (
            availability === 'AVAILABLE' && regionCode !== 'CN'
          ),
        ),
        true,
      );
      assert.equal(
        syncPlan.activationBody.requests[index]
          .activatePurchaseOptionRequest.productId,
        request.oneTimeProduct.productId,
      );
    }

    const wrongVat = structuredClone(conversions);
    wrongVat[0].convertedRegionPrices.KR.taxAmount = money('KRW', 1);
    assert.throws(
      () => buildGooglePlayProductSyncPlan(plan, wrongVat),
      /VAT/u,
    );
    const includesChina = structuredClone(conversions);
    includesChina[0].convertedRegionPrices.CN = {
      price: money('CNY', 10),
      regionCode: 'CN',
      taxAmount: money('CNY', 0),
    };
    assert.throws(
      () => buildGooglePlayProductSyncPlan(plan, includesChina),
      /CN/u,
    );
    const differentVersion = structuredClone(conversions);
    differentVersion[6].regionVersion.version = '2026/09';
    assert.throws(
      () => buildGooglePlayProductSyncPlan(plan, differentVersion),
      /regionsVersion/u,
    );
  }));

test('current 173-region conversion yields seven five-locale product payloads', () =>
  withTempRoot((root) => {
    const plan = productReadyApplyFixture(root);
    const regionCodes = supportedRegionCodesFixture();
    const syncPlan = buildGooglePlayProductSyncPlan(
      plan,
      conversionFixtures(plan.products.policy, regionCodes),
    );
    assert.equal(syncPlan.products.length, 7);
    assert.equal(syncPlan.regionCodes.length, 173);
    assert.equal(syncPlan.regionCodes.includes('CN'), false);
    for (const product of syncPlan.products) {
      assert.equal(product.listings.length, 5);
      assert.deepEqual(
        product.listings.map(({ languageCode }) => languageCode),
        PLAY_LOCALES,
      );
      assert.equal(
        product.purchaseOptions[0].regionalPricingAndAvailabilityConfigs.length,
        173,
      );
    }
  }));

test('apply performs one edit, validates it, and commits last', () =>
  withTempRoot(async (root) => {
    const events = [];
    const client = {
      commitEdit: async () => {
        events.push('commit');
        return { id: 'edit-1' };
      },
      deleteAllImages: async () => events.push('reset-image'),
      discardEdit: async () => events.push('discard'),
      insertEdit: async () => {
        events.push('insert');
        return { id: 'edit-1' };
      },
      updateListing: async (_packageName, _editId, _language, body) => {
        events.push('listing');
        return body;
      },
      updateTrack: async (_packageName, _editId, _track, body) => {
        events.push('track');
        return body;
      },
      uploadBundle: async () => {
        events.push('bundle');
        return {
          sha256: sha256(Buffer.from('signed-aab-fixture')),
          versionCode: '2',
        };
      },
      uploadImage: async () => {
        events.push('image');
        return { image: { id: 'image-1' } };
      },
      validateEdit: async () => {
        events.push('validate');
        return { id: 'edit-1' };
      },
    };
    const result = await applyGooglePlayReleasePlan(applyFixture(root), {
      client,
      confirmation: 'confirmation',
    });
    assert.equal(result.committed, true);
    assert.deepEqual(events, [
      'insert',
      'bundle',
      'listing',
      'reset-image',
      'image',
      'track',
      'validate',
      'commit',
    ]);
  }));

test('apply rejects missing, mismatched, or non-lowercase official bundle sha256', async () => {
  for (const uploadedSha256 of [
    undefined,
    'f'.repeat(64),
    sha256(Buffer.from('signed-aab-fixture')).toUpperCase(),
  ]) {
    await withTempRoot(async (root) => {
      const plan = applyFixture(root);
      const events = [];
      const client = {
        discardEdit: async () => events.push('discard'),
        insertEdit: async () => {
          events.push('insert');
          return { id: 'edit-1' };
        },
        uploadBundle: async () => {
          events.push('bundle');
          return { sha256: uploadedSha256, versionCode: '2' };
        },
      };
      await assert.rejects(
        applyGooglePlayReleasePlan(plan, {
          client,
          confirmation: 'confirmation',
        }),
        /official hex sha256/u,
      );
      assert.deepEqual(events, ['insert', 'bundle', 'discard']);
    });
  }
});

test('product preflight finishes before edit and sync preserves inactive legacy product', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const conversions = conversionFixtures(plan.products.policy);
    const baseSyncPlan = buildGooglePlayProductSyncPlan(plan, conversions);
    const before = existingRemoteProducts(baseSyncPlan, plan.products.policy);
    const syncPlan = migratedSyncPlanFixture(baseSyncPlan, before);
    const legacy = structuredClone(before.at(-1));
    const finalProducts = [
      ...syncPlan.products.map((product) => returnedProduct(product)),
      legacy,
    ];
    const events = [];
    let listCalls = 0;
    const client = {
      ...successfulAppClient(events),
      batchGetOneTimeProducts: async (_packageName, productIds) => {
        events.push('products-batch-get');
        assert.deepEqual(productIds, PLAY_PRODUCT_IDS);
        return { oneTimeProducts: finalProducts.slice(0, 7) };
      },
      batchUpdateOneTimeProducts: async (_packageName, body) => {
        events.push('products-batch-update');
        assert.deepEqual(body, syncPlan.batchUpdateBody);
        assert.equal(JSON.stringify(body).includes('hero_bundle'), false);
        for (const [index, request] of body.requests.entries()) {
          const option = request.oneTimeProduct.purchaseOptions[0];
          if ([0, 6].includes(index)) {
            const existingConfig = before[index].purchaseOptions[0].newRegionsConfig;
            assert.deepEqual(option.newRegionsConfig, {
              ...existingConfig,
              availability: 'NO_LONGER_AVAILABLE',
            });
            assert.notDeepEqual(
              option.newRegionsConfig.usdPrice,
              conversions[index].convertedOtherRegionsPrice.usdPrice,
            );
            assert.notDeepEqual(
              option.newRegionsConfig.eurPrice,
              conversions[index].convertedOtherRegionsPrice.eurPrice,
            );
          } else {
            assert.equal(Object.hasOwn(option, 'newRegionsConfig'), false);
          }
        }
        return {
          oneTimeProducts: syncPlan.products.map((product, index) => (
            returnedProduct(product, index === 6 ? 'DRAFT' : 'ACTIVE')
          )),
        };
      },
      batchUpdatePurchaseOptionStates: async (_packageName, body) => {
        events.push('products-activate');
        assert.deepEqual(body, {
          requests: [syncPlan.activationBody.requests[6]],
        });
        assert.equal(JSON.stringify(body).includes('hero_bundle'), false);
        return {
          oneTimeProducts: [returnedProduct(syncPlan.products[6])],
        };
      },
      convertRegionPrices: async (_packageName, price) => {
        const index = plan.products.policy.products.findIndex(
          ({ basePrice }) => JSON.stringify(basePrice) === JSON.stringify(price),
        );
        events.push(`convert-${index}`);
        return conversions[index];
      },
      listOneTimeProducts: async () => {
        listCalls += 1;
        events.push(listCalls === 1 ? 'products-preflight' : 'products-final-list');
        return {
          oneTimeProducts: listCalls === 1 ? before : finalProducts,
        };
      },
    };

    let productReads = 0;
    await assert.rejects(
      synchronizeGooglePlayOneTimeProducts(plan, {
        client: new Proxy(client, {
          get(target, key) {
            if (String(key).includes('OneTime') || key === 'convertRegionPrices') {
              productReads += 1;
            }
            return target[key];
          },
        }),
        productsConfirmation: 'products-confirmation',
        releaseResult: { committed: true },
      }),
      /read-only preflight/u,
    );
    assert.equal(productReads, 0);

    const productPreparation = await prepareGooglePlayProductSync(plan, {
      client,
      productsConfirmation: 'products-confirmation',
    });
    assert.equal(events.includes('insert'), false);
    assert.equal(events[0], 'products-preflight');
    assert.deepEqual(
      events.slice(1),
      Array.from({ length: 7 }, (_value, index) => `convert-${index}`),
    );
    const releaseResult = await applyGooglePlayReleasePlan(plan, {
      client,
      confirmation: 'confirmation',
      includeProducts: true,
      productPreparation,
      productsConfirmation: 'products-confirmation',
    });
    const committedReceipt = readGooglePlayApplyReceipt(plan);
    assert.equal(committedReceipt.schemaVersion, 2);
    assert.equal(committedReceipt.appCommit.state, 'COMMITTED');
    assert.equal(committedReceipt.appCommit.proof, 'COMMIT_RESPONSE');
    assert.equal(committedReceipt.products.status, 'PENDING');
    const productResult = await synchronizeGooglePlayOneTimeProducts(plan, {
      client,
      productPreparation,
      productsConfirmation: 'products-confirmation',
      releaseResult,
    });
    assert.equal(productResult.productsApplied, true);
    assert.equal(productResult.regionCount, 3);
    assert.equal(productResult.activatedProductCount, 1);
    assert.equal(productResult.legacyProductState, 'INACTIVE_UNCHANGED');
    assert.ok(events.indexOf('products-preflight') < events.indexOf('insert'));
    assert.ok(events.indexOf('convert-6') < events.indexOf('insert'));
    assert.ok(events.indexOf('commit') < events.indexOf('products-batch-update'));
    assert.ok(events.indexOf('products-batch-update') < events.indexOf('products-activate'));
    assert.ok(events.indexOf('products-activate') < events.indexOf('products-batch-get'));
    assert.equal(listCalls, 2);
    const receipt = readGooglePlayApplyReceipt(plan);
    assert.equal(receipt.products.status, 'APPLIED');
    assert.equal(receipt.products.regionsVersion, '2026/08');
  }));

test('legacy INACTIVE_PUBLISHED is accepted and preserved byte-for-byte', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const events = [];
    const { client } = productRemoteFixture(plan, {
      events,
      legacyState: 'INACTIVE_PUBLISHED',
    });
    const productPreparation = await prepareGooglePlayProductSync(plan, {
      client,
      productsConfirmation: 'products-confirmation',
    });
    const releaseResult = await applyGooglePlayReleasePlan(plan, {
      client,
      confirmation: 'confirmation',
      includeProducts: true,
      productPreparation,
      productsConfirmation: 'products-confirmation',
    });
    const result = await synchronizeGooglePlayOneTimeProducts(plan, {
      client,
      productPreparation,
      productsConfirmation: 'products-confirmation',
      releaseResult,
    });
    assert.equal(
      result.legacyProductState,
      'INACTIVE_PUBLISHED_UNCHANGED',
    );
    assert.equal(events.filter((event) => event === 'products-batch-update').length, 1);
    assert.equal(readGooglePlayApplyReceipt(plan).products.status, 'APPLIED');
  }));

test('durable COMMITTING intent exists before the first app edit request', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const events = [];
    const remote = productRemoteFixture(plan, {
      events,
      releaseVersionCode: '999',
    });
    const preparation = await prepareGooglePlayProductSync(plan, {
      client: remote.client,
      productsConfirmation: 'products-confirmation',
    });
    remote.client.insertEdit = async () => {
      events.push('insert');
      const intent = readGooglePlayApplyReceipt(plan);
      assert.equal(intent.schemaVersion, 2);
      assert.equal(intent.appCommit.state, 'COMMITTING');
      assert.equal(intent.appCommit.committed, false);
      assert.equal(intent.appCommit.editId, null);
      assert.equal(intent.products.status, 'PENDING');
      assert.equal(lstatSync(plan.receiptPath).mode & 0o077, 0);
      throw new Error('simulated crash before commit');
    };
    await assert.rejects(
      applyGooglePlayReleasePlan(plan, {
        client: remote.client,
        confirmation: 'confirmation',
        includeProducts: true,
        productPreparation: preparation,
        productsConfirmation: 'products-confirmation',
      }),
      /app commit succeeded=false, versionCode=2/u,
    );
    assert.equal(readGooglePlayApplyReceipt(plan).appCommit.state, 'COMMITTING');
    await assert.rejects(
      authorizeGooglePlayProductResume(plan, {
        client: remote.client,
        productsConfirmation: 'products-confirmation',
      }),
      /product mutation is forbidden/u,
    );
    assert.equal(events.includes('products-batch-update'), false);
  }));

test('initial intent write failure prevents every app edit request', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const events = [];
    const remote = productRemoteFixture(plan, { events });
    const preparation = await prepareGooglePlayProductSync(plan, {
      client: remote.client,
      productsConfirmation: 'products-confirmation',
    });
    await assert.rejects(
      applyGooglePlayReleasePlan(plan, {
        client: remote.client,
        confirmation: 'confirmation',
        includeProducts: true,
        productPreparation: preparation,
        productsConfirmation: 'products-confirmation',
        writeReceipt: () => {
          throw new Error('simulated fsync failure');
        },
      }),
      /app commit succeeded=false, versionCode=2.*fsync failure/u,
    );
    assert.equal(events.includes('insert'), false);
    assert.equal(existsSync(plan.receiptPath), false);
  }));

test('commit-to-PENDING write failure resumes from COMMITTING exact release proof', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const appEvents = [];
    const appRemote = productRemoteFixture(plan, { events: appEvents });
    const preparation = await prepareGooglePlayProductSync(plan, {
      client: appRemote.client,
      productsConfirmation: 'products-confirmation',
    });
    let receiptWrites = 0;
    const failThirdWrite = (path, value) => {
      receiptWrites += 1;
      if (receiptWrites === 3) {
        throw new Error('simulated post-commit receipt fsync failure');
      }
      writeOwnerOnlyJson(path, value);
    };
    await assert.rejects(
      applyGooglePlayReleasePlan(plan, {
        client: appRemote.client,
        confirmation: 'confirmation',
        includeProducts: true,
        productPreparation: preparation,
        productsConfirmation: 'products-confirmation',
        writeReceipt: failThirdWrite,
      }),
      /app commit succeeded=true, versionCode=2.*--resume-products/u,
    );
    assert.equal(receiptWrites, 3);
    assert.ok(appEvents.includes('commit'));
    assert.equal(appEvents.includes('discard'), false);
    const intent = readGooglePlayApplyReceipt(plan);
    assert.equal(intent.appCommit.state, 'COMMITTING');
    assert.equal(intent.appCommit.editId, 'edit-1');

    const resumeEvents = [];
    const resumeRemote = productRemoteFixture(plan, { events: resumeEvents });
    const resumeAuthorization = await authorizeGooglePlayProductResume(plan, {
      client: resumeRemote.client,
      productsConfirmation: 'products-confirmation',
    });
    const promoted = readGooglePlayApplyReceipt(plan);
    assert.equal(promoted.appCommit.state, 'COMMITTED');
    assert.equal(promoted.appCommit.proof, 'TRACK_RELEASE');
    assert.equal(promoted.products.status, 'PENDING');
    const resumedPreparation = await prepareGooglePlayProductSync(plan, {
      client: resumeRemote.client,
      productsConfirmation: 'products-confirmation',
    });
    const result = await synchronizeGooglePlayOneTimeProducts(plan, {
      client: resumeRemote.client,
      productPreparation: resumedPreparation,
      productsConfirmation: 'products-confirmation',
      resumeAuthorization,
    });
    assert.equal(result.resumed, true);
    assert.equal(resumeEvents.includes('insert'), false);
    assert.equal(readGooglePlayApplyReceipt(plan).products.status, 'APPLIED');
  }));

test('schema v1 PENDING receipt remains resumable and upgrades products in place', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    writeOwnerOnlyJson(plan.receiptPath, {
      appCommit: {
        committed: true,
        committedAt: '2026-08-03T00:00:00.000Z',
        editId: 'legacy-edit-1',
      },
      bundleSha256: plan.bundle.sha256,
      manifestDigest: plan.manifestDigest,
      packageName: plan.packageName,
      productBindingDigest: plan.products.bindingDigest,
      products: {
        appliedAt: null,
        regionsVersion: null,
        status: 'PENDING',
      },
      schemaVersion: 1,
      track: plan.release.track,
      versionCode: plan.release.versionCode,
    });
    const remote = productRemoteFixture(plan);
    const resumeAuthorization = await authorizeGooglePlayProductResume(plan, {
      client: remote.client,
      productsConfirmation: 'products-confirmation',
    });
    assert.equal(readGooglePlayApplyReceipt(plan).schemaVersion, 1);
    const preparation = await prepareGooglePlayProductSync(plan, {
      client: remote.client,
      productsConfirmation: 'products-confirmation',
    });
    await synchronizeGooglePlayOneTimeProducts(plan, {
      client: remote.client,
      productPreparation: preparation,
      productsConfirmation: 'products-confirmation',
      resumeAuthorization,
    });
    const applied = readGooglePlayApplyReceipt(plan);
    assert.equal(applied.schemaVersion, 1);
    assert.equal(applied.products.status, 'APPLIED');
  }));

test('pending durable receipt resumes products only after remote track revalidation', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const firstEvents = [];
    const firstRemote = productRemoteFixture(plan, {
      events: firstEvents,
      failBatchUpdate: true,
    });
    const firstPreparation = await prepareGooglePlayProductSync(plan, {
      client: firstRemote.client,
      productsConfirmation: 'products-confirmation',
    });
    const releaseResult = await applyGooglePlayReleasePlan(plan, {
      client: firstRemote.client,
      confirmation: 'confirmation',
      includeProducts: true,
      productPreparation: firstPreparation,
      productsConfirmation: 'products-confirmation',
    });
    await assert.rejects(
      synchronizeGooglePlayOneTimeProducts(plan, {
        client: firstRemote.client,
        productPreparation: firstPreparation,
        productsConfirmation: 'products-confirmation',
        releaseResult,
      }),
      /app commit succeeded=true, versionCode=2.*--resume-products/u,
    );
    assert.equal(readGooglePlayApplyReceipt(plan).products.status, 'PENDING');
    const retryPreparation = await prepareGooglePlayProductSync(plan, {
      client: firstRemote.client,
      productsConfirmation: 'products-confirmation',
    });
    const insertCountBeforeRetry = firstEvents.filter(
      (event) => event === 'insert',
    ).length;
    await assert.rejects(
      applyGooglePlayReleasePlan(plan, {
        client: firstRemote.client,
        confirmation: 'confirmation',
        includeProducts: true,
        productPreparation: retryPreparation,
        productsConfirmation: 'products-confirmation',
      }),
      /--resume-products/u,
    );
    assert.equal(
      firstEvents.filter((event) => event === 'insert').length,
      insertCountBeforeRetry,
    );

    const resumeEvents = [];
    const resumedRemote = productRemoteFixture(plan, { events: resumeEvents });
    resumedRemote.before[0].purchaseOptions[0]
      .newRegionsConfig.availability = 'NO_LONGER_AVAILABLE';
    const resumeAuthorization = await authorizeGooglePlayProductResume(plan, {
      client: resumedRemote.client,
      productsConfirmation: 'products-confirmation',
    });
    const resumedPreparation = await prepareGooglePlayProductSync(plan, {
      client: resumedRemote.client,
      productsConfirmation: 'products-confirmation',
    });
    const result = await synchronizeGooglePlayOneTimeProducts(plan, {
      client: resumedRemote.client,
      productPreparation: resumedPreparation,
      productsConfirmation: 'products-confirmation',
      resumeAuthorization,
    });
    assert.equal(result.resumed, true);
    assert.equal(resumeEvents[0], 'track-releases');
    assert.ok(resumeEvents.indexOf('track-releases') < resumeEvents.indexOf('products-preflight'));
    assert.equal(resumeEvents.includes('insert'), false);
    assert.equal(resumeEvents.includes('commit'), false);
    assert.equal(resumedRemote.batchUpdateBodies.length, 1);
    for (const index of [0, 6]) {
      assert.deepEqual(
        resumedRemote.batchUpdateBodies[0].requests[index]
          .oneTimeProduct.purchaseOptions[0].newRegionsConfig,
        {
          ...resumedRemote.before[index].purchaseOptions[0].newRegionsConfig,
          availability: 'NO_LONGER_AVAILABLE',
        },
      );
    }
    assert.equal(readGooglePlayApplyReceipt(plan).products.status, 'APPLIED');
  }));

test('product-only adoption proves the exact release before a 7x173 sync', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const events = [];
    const remote = productRemoteFixture(plan, {
      events,
      regionCodes: supportedRegionCodesFixture(),
    });
    const productPreparation = await prepareGooglePlayProductSync(plan, {
      client: remote.client,
      productsConfirmation: 'products-confirmation',
    });
    assert.equal(events[0], 'products-preflight');
    assert.equal(events.at(-1), 'convert-6');
    assert.equal(existsSync(plan.receiptPath), false);

    const adoptionAuthorization = await authorizeGooglePlayProductAdoption(plan, {
      client: remote.client,
      confirmation: 'confirmation',
      productPreparation,
      productsConfirmation: 'products-confirmation',
    });
    assert.equal(adoptionAuthorization.adopted, true);
    assert.equal(adoptionAuthorization.resumed, false);
    assert.equal(events.at(-1), 'track-releases');
    const pending = readGooglePlayApplyReceipt(plan);
    assert.equal(pending.schemaVersion, 2);
    assert.equal(pending.appCommit.state, 'COMMITTED');
    assert.equal(pending.appCommit.proof, 'TRACK_RELEASE');
    assert.equal(pending.appCommit.editId, null);
    assert.equal(pending.products.status, 'PENDING');
    assert.equal(lstatSync(plan.receiptPath).mode & 0o077, 0);

    assert.equal(remote.syncPlan.products.length, 7);
    assert.equal(remote.syncPlan.regionCodes.length, 173);
    assert.equal(remote.syncPlan.regionCodes.includes('CN'), false);
    assert.equal(remote.syncPlan.products.every((product) => (
      product.listings.length === 5
      && product.purchaseOptions[0]
        .regionalPricingAndAvailabilityConfigs.length === 173
    )), true);

    const result = await synchronizeGooglePlayOneTimeProducts(plan, {
      adoptionAuthorization,
      client: remote.client,
      productPreparation,
      productsConfirmation: 'products-confirmation',
    });
    assert.equal(result.productsApplied, true);
    assert.equal(result.adopted, true);
    assert.equal(result.resumed, false);
    assert.equal(result.regionCount, 173);
    assert.ok(events.indexOf('track-releases') < events.indexOf('products-batch-update'));
    assert.equal(events.includes('insert'), false);
    assert.equal(events.includes('bundle'), false);
    assert.equal(events.includes('commit'), false);
    assert.equal(readGooglePlayApplyReceipt(plan).products.status, 'APPLIED');
  }));

test('product sync preserves IAPKit-owned consumables byte-for-byte', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const preservedProducts = PLAY_CONSUMABLE_PRODUCT_IDS.map((productId) => ({
      listings: [{ languageCode: 'ko-KR', title: productId.split('.').at(-1) }],
      packageName: PLAY_PACKAGE_NAME,
      productId,
      purchaseOptions: [{
        buyOption: { legacyPrice: money('KRW', 700) },
        purchaseOptionId: 'buy',
        state: 'ACTIVE',
      }],
    }));
    const remote = productRemoteFixture(plan, {
      preservedProducts,
      regionCodes: supportedRegionCodesFixture(),
    });
    const productPreparation = await prepareGooglePlayProductSync(plan, {
      client: remote.client,
      productsConfirmation: 'products-confirmation',
    });
    const adoptionAuthorization = await authorizeGooglePlayProductAdoption(plan, {
      client: remote.client,
      confirmation: 'confirmation',
      productPreparation,
      productsConfirmation: 'products-confirmation',
    });
    const result = await synchronizeGooglePlayOneTimeProducts(plan, {
      adoptionAuthorization,
      client: remote.client,
      productPreparation,
      productsConfirmation: 'products-confirmation',
    });
    assert.equal(result.productsApplied, true);
    assert.deepEqual(
      remote.finalProducts.slice(-PLAY_CONSUMABLE_PRODUCT_IDS.length),
      preservedProducts,
    );
  }));

test('final list requires disabled new regions with preserved USD and EUR', async () => {
  const cases = [
    {
      expected: /new-region availability/u,
      mutate: (config) => { config.availability = 'AVAILABLE'; },
    },
    {
      expected: /new-region USD\/EUR price readback/u,
      mutate: (config) => { config.usdPrice = money('USD', 99); },
    },
    {
      expected: /new-region USD\/EUR price readback/u,
      mutate: (config) => { config.eurPrice = money('EUR', 99); },
    },
  ];
  for (const scenario of cases) {
    await withTempRoot(async (root) => {
      const plan = productReadyApplyFixture(root);
      const remote = productRemoteFixture(plan);
      const preparation = await prepareGooglePlayProductSync(plan, {
        client: remote.client,
        productsConfirmation: 'products-confirmation',
      });
      const authorization = await authorizeGooglePlayProductAdoption(plan, {
        client: remote.client,
        confirmation: 'confirmation',
        productPreparation: preparation,
        productsConfirmation: 'products-confirmation',
      });
      const correctProducts = remote.syncPlan.products.map((product) => (
        returnedProduct(product)
      ));
      remote.client.batchUpdateOneTimeProducts = async () => ({
        oneTimeProducts: correctProducts,
      });
      remote.client.batchGetOneTimeProducts = async () => ({
        oneTimeProducts: correctProducts,
      });
      scenario.mutate(
        remote.finalProducts[0].purchaseOptions[0].newRegionsConfig,
      );
      await assert.rejects(
        synchronizeGooglePlayOneTimeProducts(plan, {
          adoptionAuthorization: authorization,
          client: remote.client,
          productPreparation: preparation,
          productsConfirmation: 'products-confirmation',
        }),
        scenario.expected,
      );
      assert.equal(readGooglePlayApplyReceipt(plan).products.status, 'PENDING');
    });
  }
});

test('product-only adoption requires both current tokens and its own preflight', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const events = [];
    const remote = productRemoteFixture(plan, { events });
    await assert.rejects(
      prepareGooglePlayProductSync(plan, {
        client: remote.client,
        productsConfirmation: 'stale-products-token',
      }),
      /product confirmation token/u,
    );
    assert.deepEqual(events, []);

    const preparation = await prepareGooglePlayProductSync(plan, {
      client: remote.client,
      productsConfirmation: 'products-confirmation',
    });
    const eventsBeforeAuthorization = [...events];
    await assert.rejects(
      authorizeGooglePlayProductAdoption(plan, {
        client: remote.client,
        confirmation: 'stale-app-token',
        productPreparation: preparation,
        productsConfirmation: 'products-confirmation',
      }),
      /remote confirmation token/u,
    );
    await assert.rejects(
      authorizeGooglePlayProductAdoption(plan, {
        client: remote.client,
        confirmation: 'confirmation',
        productPreparation: preparation,
        productsConfirmation: 'stale-products-token',
      }),
      /product confirmation token/u,
    );
    await assert.rejects(
      authorizeGooglePlayProductAdoption(plan, {
        client: remote.client,
        confirmation: 'confirmation',
        productPreparation: { prepared: true },
        productsConfirmation: 'products-confirmation',
      }),
      /read-only preflight/u,
    );
    assert.deepEqual(events, eventsBeforeAuthorization);
    assert.equal(existsSync(plan.receiptPath), false);
    assert.equal(events.includes('products-batch-update'), false);
  }));

test('product-only adoption preserves any existing receipt without remote proof reads', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const events = [];
    const remote = productRemoteFixture(plan, { events });
    const preparation = await prepareGooglePlayProductSync(plan, {
      client: remote.client,
      productsConfirmation: 'products-confirmation',
    });
    writeOwnerOnlyJson(plan.receiptPath, { existingOperatorReceipt: true });
    const existing = readFileSync(plan.receiptPath);
    await assert.rejects(
      authorizeGooglePlayProductAdoption(plan, {
        client: remote.client,
        confirmation: 'confirmation',
        productPreparation: preparation,
        productsConfirmation: 'products-confirmation',
      }),
      /receipt already exists/u,
    );
    assert.deepEqual(readFileSync(plan.receiptPath), existing);
    assert.equal(events.includes('track-releases'), false);
    assert.equal(events.includes('products-batch-update'), false);
  }));

test('concurrent product-only adoption atomically publishes exactly one receipt', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const events = [];
    const remote = productRemoteFixture(plan, { events });
    const preparation = await prepareGooglePlayProductSync(plan, {
      client: remote.client,
      productsConfirmation: 'products-confirmation',
    });
    const authorization = () => authorizeGooglePlayProductAdoption(plan, {
      client: remote.client,
      confirmation: 'confirmation',
      productPreparation: preparation,
      productsConfirmation: 'products-confirmation',
    });
    const attempts = await Promise.allSettled([authorization(), authorization()]);
    assert.equal(attempts.filter(({ status }) => status === 'fulfilled').length, 1);
    assert.equal(attempts.filter(({ status }) => status === 'rejected').length, 1);
    assert.match(
      attempts.find(({ status }) => status === 'rejected').reason.message,
      /receipt already exists/u,
    );
    const receipt = readGooglePlayApplyReceipt(plan);
    assert.equal(receipt.appCommit.state, 'COMMITTED');
    assert.equal(receipt.appCommit.proof, 'TRACK_RELEASE');
    assert.equal(receipt.products.status, 'PENDING');
    assert.equal(events.filter((event) => event === 'track-releases').length, 2);
    assert.equal(events.includes('products-batch-update'), false);
  }));

test('product-only adoption rejects missing or ambiguous release proof before mutation', async () => {
  const scenarios = [
    {
      label: 'missing release',
      releases: [],
    },
    {
      label: 'wrong lifecycle',
      releases: [{
        activeArtifacts: [{ versionCode: '2' }],
        releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_DRAFT',
        releaseName: 'Moonlit Beacon 1.0.1',
        track: 'internal',
      }],
    },
    {
      label: 'multiple active artifacts',
      releases: [{
        activeArtifacts: [{ versionCode: '2' }, { versionCode: '3' }],
        releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_PUBLISHED',
        releaseName: 'Moonlit Beacon 1.0.1',
        track: 'internal',
      }],
    },
    {
      label: 'duplicate exact releases',
      releases: [0, 1].map(() => ({
        activeArtifacts: [{ versionCode: '2' }],
        releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_PUBLISHED',
        releaseName: 'Moonlit Beacon 1.0.1',
        track: 'internal',
      })),
    },
  ];
  for (const scenario of scenarios) {
    await withTempRoot(async (root) => {
      const plan = productReadyApplyFixture(root);
      const events = [];
      const remote = productRemoteFixture(plan, { events });
      remote.client.listTrackReleases = async () => {
        events.push('track-releases');
        return { releases: scenario.releases };
      };
      const preparation = await prepareGooglePlayProductSync(plan, {
        client: remote.client,
        productsConfirmation: 'products-confirmation',
      });
      await assert.rejects(
        authorizeGooglePlayProductAdoption(plan, {
          client: remote.client,
          confirmation: 'confirmation',
          productPreparation: preparation,
          productsConfirmation: 'products-confirmation',
        }),
        /committed release could not be re-verified/u,
        scenario.label,
      );
      assert.equal(events.filter((event) => event === 'track-releases').length, 1);
      assert.equal(events.includes('products-batch-update'), false);
      assert.equal(existsSync(plan.receiptPath), false);
    });
  }
});

test('product-only adoption receipt failure leaves every product mutation untouched', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const events = [];
    const remote = productRemoteFixture(plan, { events });
    const preparation = await prepareGooglePlayProductSync(plan, {
      client: remote.client,
      productsConfirmation: 'products-confirmation',
    });
    await assert.rejects(
      authorizeGooglePlayProductAdoption(plan, {
        client: remote.client,
        confirmation: 'confirmation',
        productPreparation: preparation,
        productsConfirmation: 'products-confirmation',
        writeReceipt: () => {
          throw new Error('simulated atomic receipt failure');
        },
      }),
      /atomic receipt failure/u,
    );
    assert.equal(events.at(-1), 'track-releases');
    assert.equal(events.includes('products-batch-update'), false);
    assert.equal(events.includes('products-activate'), false);
    assert.equal(existsSync(plan.receiptPath), false);
  }));

test('resume refuses missing receipt and the wrong remote version or lifecycle', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const missingEvents = [];
    const missingRemote = productRemoteFixture(plan, { events: missingEvents });
    await assert.rejects(
      authorizeGooglePlayProductResume(plan, {
        client: missingRemote.client,
        productsConfirmation: 'products-confirmation',
      }),
      /receipt is missing/u,
    );
    assert.equal(missingEvents.includes('track-releases'), false);
    writeJson(plan.receiptPath, { forged: true });
    chmodSync(plan.receiptPath, 0o600);
    await assert.rejects(
      authorizeGooglePlayProductResume(plan, {
        client: missingRemote.client,
        productsConfirmation: 'products-confirmation',
      }),
      /receipt.*key contract/u,
    );
    assert.equal(missingEvents.includes('track-releases'), false);
    rmSync(plan.receiptPath);

    const initialRemote = productRemoteFixture(plan);
    const preparation = await prepareGooglePlayProductSync(plan, {
      client: initialRemote.client,
      productsConfirmation: 'products-confirmation',
    });
    await applyGooglePlayReleasePlan(plan, {
      client: initialRemote.client,
      confirmation: 'confirmation',
      includeProducts: true,
      productPreparation: preparation,
      productsConfirmation: 'products-confirmation',
    });
    assert.equal(readGooglePlayApplyReceipt(plan).products.status, 'PENDING');

    const wrongVersion = productRemoteFixture(plan, {
      releaseVersionCode: '999',
    });
    await assert.rejects(
      authorizeGooglePlayProductResume(plan, {
        client: wrongVersion.client,
        productsConfirmation: 'products-confirmation',
      }),
      /versionCode 2 committed release/u,
    );
    const wrongLifecycle = productRemoteFixture(plan, {
      releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_DRAFT',
    });
    await assert.rejects(
      authorizeGooglePlayProductResume(plan, {
        client: wrongLifecycle.client,
        productsConfirmation: 'products-confirmation',
      }),
      /versionCode 2 committed release/u,
    );
    const multipleArtifacts = productRemoteFixture(plan);
    multipleArtifacts.client.listTrackReleases = async () => ({
      releases: [{
        activeArtifacts: [{ versionCode: '2' }, { versionCode: '3' }],
        releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_PUBLISHED',
        releaseName: plan.release.name,
        track: plan.release.track,
      }],
    });
    await assert.rejects(
      authorizeGooglePlayProductResume(plan, {
        client: multipleArtifacts.client,
        productsConfirmation: 'products-confirmation',
      }),
      /versionCode 2 committed release/u,
    );
  }));

test('product preflight hard-fails before app edit or product mutation', () =>
  withTempRoot(async (root) => {
    const plan = productReadyApplyFixture(root);
    const conversions = conversionFixtures(plan.products.policy);
    const syncPlan = buildGooglePlayProductSyncPlan(plan, conversions);
    const expected = existingRemoteProducts(syncPlan, plan.products.policy);
    let current = expected;
    let mutations = 0;
    let appEdits = 0;
    const client = {
      ...successfulAppClient(),
      batchGetOneTimeProducts: async () => ({ oneTimeProducts: [] }),
      batchUpdateOneTimeProducts: async () => {
        mutations += 1;
        return {};
      },
      batchUpdatePurchaseOptionStates: async () => {
        mutations += 1;
        return {};
      },
      convertRegionPrices: async (_packageName, price) => {
        const index = plan.products.policy.products.findIndex(
          ({ basePrice }) => JSON.stringify(basePrice) === JSON.stringify(price),
        );
        return conversions[index];
      },
      listOneTimeProducts: async () => ({ oneTimeProducts: current }),
      insertEdit: async () => {
        appEdits += 1;
        return { id: 'edit-1' };
      },
    };
    const prepare = () => prepareGooglePlayProductSync(plan, {
      client,
      productsConfirmation: 'products-confirmation',
    });

    current = [...expected, {
      packageName: PLAY_PACKAGE_NAME,
      productId: `${PLAY_PACKAGE_NAME}.unexpected`,
      purchaseOptions: [],
    }];
    await assert.rejects(prepare(), /Unexpected.*product/u);

    current = expected.slice(0, -1);
    await assert.rejects(prepare(), /legacy hero_bundle is missing/u);

    current = structuredClone(expected);
    current[0].purchaseOptions.push({
      purchaseOptionId: 'rent',
      state: 'ACTIVE',
    });
    await assert.rejects(prepare(), /purchase option/u);

    current = structuredClone(expected);
    current[1].purchaseOptions[0].newRegionsConfig = {
      availability: 'AVAILABLE',
      eurPrice: money('EUR', 4, 490_000_000),
      usdPrice: money('USD', 4, 990_000_000),
    };
    await assert.rejects(prepare(), /new-region auto-activate/u);

    current = structuredClone(expected);
    current[0].purchaseOptions[0]
      .regionalPricingAndAvailabilityConfigs[0].price = money('KRW', 3299);
    await assert.rejects(prepare(), /existing base-region price/u);
    assert.equal(mutations, 0);
    assert.equal(appEdits, 0);
  }));

test('apply discards an uncommitted edit and never attempts incomplete products', () =>
  withTempRoot(async (root) => {
    const plan = applyFixture(root);
    let inserted = false;
    await assert.rejects(
      applyGooglePlayReleasePlan(plan, {
        client: { insertEdit: async () => { inserted = true; } },
        confirmation: 'confirmation',
        includeProducts: true,
      }),
      /product local contract/u,
    );
    assert.equal(inserted, false);

    const events = [];
    const client = {
      discardEdit: async () => events.push('discard'),
      insertEdit: async () => ({ id: 'edit-1' }),
      uploadBundle: async () => {
        throw new Error('upload failed');
      },
    };
    await assert.rejects(
      applyGooglePlayReleasePlan(plan, {
        client,
        confirmation: 'confirmation',
      }),
      /upload failed/u,
    );
    assert.deepEqual(events, ['discard']);
  }));

test('commit transport failure is reported as an ambiguous remote state', () =>
  withTempRoot(async (root) => {
    const plan = applyFixture(root);
    const client = {
      commitEdit: async () => {
        throw new Error('AbortError');
      },
      deleteAllImages: async () => ({}),
      discardEdit: async () => ({}),
      insertEdit: async () => ({ id: 'edit-1' }),
      updateListing: async (_packageName, _editId, _language, body) => body,
      updateTrack: async (_packageName, _editId, _track, body) => body,
      uploadBundle: async () => ({
        sha256: sha256(Buffer.from('signed-aab-fixture')),
        versionCode: '2',
      }),
      uploadImage: async () => ({ image: { id: 'image-1' } }),
      validateEdit: async () => ({ id: 'edit-1' }),
    };
    await assert.rejects(
      applyGooglePlayReleasePlan(plan, {
        client,
        confirmation: 'confirmation',
      }),
      /app commit succeeded=uncertain, versionCode=2.*commit result is uncertain.*Do not rerun/u,
    );
  }));

function promotionFixture(root) {
  const plan = applyFixture(root);
  plan.promotion = {
    confirmationToken: 'promotion-confirmation',
    receiptPath: join(root, 'google-play-promotion-receipt.json'),
    sourceTrack: 'internal',
    targetTrack: 'production',
  };
  return plan;
}

function promotionClient(plan, events = [], {
  internalReleases,
  productionBefore = [],
  failCommit = false,
} = {}) {
  const committedRelease = {
    activeArtifacts: [{ versionCode: plan.release.versionCode }],
    releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED',
    releaseName: plan.release.name,
    track: 'internal',
  };
  let committed = false;
  return {
    commitEdit: async () => {
      events.push('commit');
      if (failCommit) throw new Error('simulated commit transport failure');
      committed = true;
      return { id: 'edit-1' };
    },
    deleteAllImages: async () => events.push('reset-image'),
    discardEdit: async () => events.push('discard'),
    insertEdit: async () => {
      events.push('insert');
      return { id: 'edit-1' };
    },
    listTrackReleases: async (_packageName, track) => {
      events.push(`list-${track}`);
      if (track === 'internal') {
        return { releases: internalReleases ?? [committedRelease] };
      }
      if (!committed) return { releases: productionBefore };
      return {
        releases: [{
          ...committedRelease,
          releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
          track: 'production',
        }],
      };
    },
    updateListing: async () => events.push('listing'),
    updateTrack: async (_packageName, _editId, track, body) => {
      events.push(`track-${track}`);
      return body;
    },
    uploadBundle: async () => events.push('bundle'),
    uploadImage: async () => events.push('image'),
    validateEdit: async () => {
      events.push('validate');
      return { id: 'edit-1' };
    },
  };
}

test('production promotion moves only the committed versionCode', () =>
  withTempRoot(async (root) => {
    const plan = promotionFixture(root);
    const events = [];
    const client = promotionClient(plan, events);
    const result = await promoteGooglePlayReleaseToProduction(plan, {
      client,
      confirmation: 'promotion-confirmation',
    });
    assert.deepEqual(result, {
      editId: 'edit-1',
      lifecycleState: 'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
      packageName: PLAY_PACKAGE_NAME,
      promoted: true,
      sourceTrack: 'internal',
      targetTrack: 'production',
      versionCode: '2',
    });
    assert.deepEqual(events, [
      'list-internal',
      'list-production',
      'insert',
      'track-production',
      'validate',
      'commit',
      'list-production',
    ]);
    // A promotion never re-uploads or re-describes the release.
    for (const forbidden of ['bundle', 'image', 'listing', 'reset-image']) {
      assert.equal(events.includes(forbidden), false);
    }
    const receipt = readGooglePlayPromotionReceipt(plan);
    assert.equal(receipt.promotion.state, 'APPLIED');
    assert.equal(receipt.promotion.proof, 'TRACK_RELEASE');
    assert.equal(receipt.targetTrack, 'production');
    assert.equal(receipt.versionCode, '2');
    assert.equal((lstatSync(plan.promotion.receiptPath).mode & 0o077), 0);
  }));

test('production promotion refuses a token that is not bound to this manifest', () =>
  withTempRoot(async (root) => {
    const plan = promotionFixture(root);
    const events = [];
    const client = promotionClient(plan, events);
    await assert.rejects(
      () => promoteGooglePlayReleaseToProduction(plan, {
        client,
        confirmation: 'google-play:confirmation',
      }),
      /promotion confirmation token differs from the current manifest/u,
    );
    assert.deepEqual(events, []);
    assert.equal(existsSync(plan.promotion.receiptPath), false);
  }));

test('production promotion stops when the internal release is missing or ambiguous', () =>
  withTempRoot(async (root) => {
    const plan = promotionFixture(root);
    for (const internalReleases of [
      [],
      [{
        activeArtifacts: [{ versionCode: '2' }, { versionCode: '3' }],
        releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
        releaseName: plan.release.name,
        track: 'internal',
      }],
      [{
        activeArtifacts: [{ versionCode: '2' }],
        releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_DRAFT',
        releaseName: plan.release.name,
        track: 'internal',
      }],
    ]) {
      const events = [];
      const client = promotionClient(plan, events, { internalReleases });
      await assert.rejects(
        () => promoteGooglePlayReleaseToProduction(plan, {
          client,
          confirmation: 'promotion-confirmation',
        }),
        /production promotion is forbidden/u,
      );
      assert.deepEqual(events, ['list-internal']);
      assert.equal(existsSync(plan.promotion.receiptPath), false);
    }
  }));

test('production promotion refuses a versionCode production already carries', () =>
  withTempRoot(async (root) => {
    const plan = promotionFixture(root);
    const events = [];
    const client = promotionClient(plan, events, {
      productionBefore: [{
        activeArtifacts: [{ versionCode: '2' }],
        releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_PUBLISHED',
        releaseName: plan.release.name,
        track: 'production',
      }],
    });
    await assert.rejects(
      () => promoteGooglePlayReleaseToProduction(plan, {
        client,
        confirmation: 'promotion-confirmation',
      }),
      /already has versionCode 2. Not attempting a duplicate promotion/u,
    );
    assert.deepEqual(events, ['list-internal', 'list-production']);
    assert.equal(existsSync(plan.promotion.receiptPath), false);
  }));

test('production promotion never starts twice from an existing receipt', () =>
  withTempRoot(async (root) => {
    const plan = promotionFixture(root);
    await promoteGooglePlayReleaseToProduction(plan, {
      client: promotionClient(plan),
      confirmation: 'promotion-confirmation',
    });
    const events = [];
    await assert.rejects(
      () => promoteGooglePlayReleaseToProduction(plan, {
        client: promotionClient(plan, events),
        confirmation: 'promotion-confirmation',
      }),
      /promotion receipt already exists. Promotion for this version is already APPLIED/u,
    );
    assert.deepEqual(events, []);
  }));

test('production promotion tells an unarchived earlier receipt apart from this one', () =>
  withTempRoot(async (root) => {
    const plan = promotionFixture(root);
    // Promoting a later version without archiving the previous version's promotion receipt.
    writeOwnerOnlyJson(plan.promotion.receiptPath, {
      manifestDigest: 'a'.repeat(64),
      packageName: PLAY_PACKAGE_NAME,
      promotion: {
        appliedAt: '2026-08-01T00:00:00.000Z',
        committedAt: '2026-08-01T00:00:00.000Z',
        editId: 'edit-old',
        intentCreatedAt: '2026-08-01T00:00:00.000Z',
        proof: 'TRACK_RELEASE',
        state: 'APPLIED',
      },
      schemaVersion: 1,
      sourceTrack: 'internal',
      targetTrack: 'production',
      versionCode: '1',
    });
    const events = [];
    await assert.rejects(
      () => promoteGooglePlayReleaseToProduction(plan, {
        client: promotionClient(plan, events),
        confirmation: 'promotion-confirmation',
      }),
      /If it is a previous-version receipt, confirm remote state and archive it separately/u,
    );
    assert.deepEqual(events, []);
  }));

test('production promotion reports an ambiguous commit and keeps the intent', () =>
  withTempRoot(async (root) => {
    const plan = promotionFixture(root);
    const events = [];
    const client = promotionClient(plan, events, { failCommit: true });
    await assert.rejects(
      () => promoteGooglePlayReleaseToProduction(plan, {
        client,
        confirmation: 'promotion-confirmation',
      }),
      /promotion commit succeeded=uncertain, versionCode=2.*Do not rerun/u,
    );
    const receipt = readGooglePlayPromotionReceipt(plan);
    assert.equal(receipt.promotion.state, 'COMMITTING');
    assert.equal(receipt.promotion.editId, 'edit-1');
    assert.equal(receipt.promotion.committedAt, null);
  }));

function reviewFixture(root) {
  const plan = applyFixture(root);
  plan.reviewSubmission = {
    confirmationToken: 'review-confirmation',
    receiptPath: join(root, 'google-play-review-receipt.json'),
    track: 'production',
  };
  return plan;
}

function reviewClient(plan, events = [], { stagedLifecycle, inReview = true } = {}) {
  const stagedRelease = {
    activeArtifacts: [{ versionCode: plan.release.versionCode }],
    releaseLifecycleState:
      stagedLifecycle ?? 'RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW',
    releaseName: plan.release.name,
    track: 'production',
  };
  const oldRelease = {
    activeArtifacts: [{ versionCode: '1' }],
    releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
    releaseName: 'Moonlit Beacon 1.0.0 (1)',
    track: 'production',
  };
  let committed = false;
  return {
    commitEdit: async (_packageName, _editId, review) => {
      events.push(`commit:${review.changesInReviewBehavior}:${review.changesNotSentForReview}`);
      committed = true;
      return { id: 'edit-1' };
    },
    discardEdit: async () => events.push('discard'),
    insertEdit: async () => {
      events.push('insert');
      return { id: 'edit-1' };
    },
    listTrackReleases: async (_packageName, track) => {
      events.push(`list-${track}`);
      if (!committed) {
        return { releases: inReview ? [stagedRelease, oldRelease] : [stagedRelease] };
      }
      return {
        releases: [{
          ...stagedRelease,
          releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
        }],
      };
    },
    updateTrack: async (_packageName, _editId, track, body) => {
      events.push(`track-${track}`);
      return body;
    },
    uploadBundle: async () => events.push('bundle'),
    validateEdit: async () => {
      events.push('validate');
      return { id: 'edit-1' };
    },
  };
}

test('production review submission cancels in-review releases and records them', () =>
  withTempRoot(async (root) => {
    const plan = reviewFixture(root);
    const events = [];
    const result = await submitGooglePlayProductionReview(plan, {
      client: reviewClient(plan, events),
      confirmation: 'review-confirmation',
    });
    assert.equal(result.submitted, true);
    assert.equal(result.track, 'production');
    assert.equal(result.versionCode, '2');
    assert.deepEqual(result.cancelledReleases, [
      { releaseName: 'Moonlit Beacon 1.0.0 (1)', versionCodes: ['1'] },
    ]);
    // Only this path uses CANCEL_IN_REVIEW_AND_SUBMIT and commits with review submission on.
    assert.ok(events.includes('commit:CANCEL_IN_REVIEW_AND_SUBMIT:false'));
    assert.equal(events.includes('bundle'), false);
    const receipt = readGooglePlayReviewReceipt(plan);
    assert.equal(receipt.review.state, 'APPLIED');
    assert.equal(receipt.review.proof, 'TRACK_RELEASE');
    assert.deepEqual(receipt.cancelledReleases, result.cancelledReleases);
  }));

test('production review submission refuses a version that is not staged', () =>
  withTempRoot(async (root) => {
    const plan = reviewFixture(root);
    for (const stagedLifecycle of [
      'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
      'RELEASE_LIFECYCLE_STATE_PUBLISHED',
      'RELEASE_LIFECYCLE_STATE_DRAFT',
    ]) {
      const events = [];
      await assert.rejects(
        () => submitGooglePlayProductionReview(plan, {
          client: reviewClient(plan, events, { stagedLifecycle }),
          confirmation: 'review-confirmation',
        }),
        // This versionCode is already on production, so duplicate submission is blocked.
        /already has versionCode 2. Not attempting a duplicate review submission/u,
      );
      assert.deepEqual(events, ['list-production']);
      assert.equal(existsSync(plan.reviewSubmission.receiptPath), false);
    }
  }));

test('production review submission rejects a token bound to another operation', () =>
  withTempRoot(async (root) => {
    const plan = reviewFixture(root);
    const events = [];
    await assert.rejects(
      () => submitGooglePlayProductionReview(plan, {
        client: reviewClient(plan, events),
        confirmation: 'promotion-confirmation',
      }),
      /review submission confirmation token differs from the current manifest/u,
    );
    assert.deepEqual(events, []);
  }));

test('production review submission records an empty cancel list when nothing is in review', () =>
  withTempRoot(async (root) => {
    const plan = reviewFixture(root);
    const result = await submitGooglePlayProductionReview(plan, {
      client: reviewClient(plan, [], { inReview: false }),
      confirmation: 'review-confirmation',
    });
    assert.deepEqual(result.cancelledReleases, []);
  }));

test('production review submission stages a verified internal release when the track has none', () =>
  withTempRoot(async (root) => {
    const plan = reviewFixture(root);
    plan.promotion = {
      confirmationToken: 'promotion-confirmation',
      receiptPath: join(root, 'google-play-promotion-receipt.json'),
      sourceTrack: 'internal',
      targetTrack: 'production',
    };
    const events = [];
    let committed = false;
    const internalRelease = {
      activeArtifacts: [{ versionCode: plan.release.versionCode }],
      releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_PUBLISHED',
      releaseName: plan.release.name,
      track: 'internal',
    };
    const oldProduction = {
      activeArtifacts: [{ versionCode: '1' }],
      releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
      releaseName: 'Moonlit Beacon 1.0.1',
      track: 'production',
    };
    const client = {
      commitEdit: async (_p, _e, review) => {
        events.push(`commit:${review.changesInReviewBehavior}`);
        committed = true;
        return { id: 'edit-1' };
      },
      discardEdit: async () => events.push('discard'),
      insertEdit: async () => {
        events.push('insert');
        return { id: 'edit-1' };
      },
      listTrackReleases: async (_p, track) => {
        events.push(`list-${track}`);
        if (track === 'internal') return { releases: [internalRelease] };
        if (!committed) return { releases: [oldProduction] };
        return {
          releases: [{
            ...internalRelease,
            releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
            track: 'production',
          }],
        };
      },
      updateTrack: async (_p, _e, track, body) => {
        events.push(`track-${track}`);
        return body;
      },
      validateEdit: async () => {
        events.push('validate');
        return { id: 'edit-1' };
      },
    };
    const result = await submitGooglePlayProductionReview(plan, {
      client,
      confirmation: 'review-confirmation',
    });
    assert.equal(result.submitted, true);
    // When it is not on the track, always re-verify the original internal release first.
    assert.ok(events.indexOf('list-internal') < events.indexOf('insert'));
    assert.ok(events.includes('commit:CANCEL_IN_REVIEW_AND_SUBMIT'));
    assert.deepEqual(result.cancelledReleases, [
      { releaseName: 'Moonlit Beacon 1.0.1', versionCodes: ['1'] },
    ]);
  }));

test('production review submission refuses when internal has no matching release', () =>
  withTempRoot(async (root) => {
    const plan = reviewFixture(root);
    plan.promotion = {
      confirmationToken: 'promotion-confirmation',
      receiptPath: join(root, 'google-play-promotion-receipt.json'),
      sourceTrack: 'internal',
      targetTrack: 'production',
    };
    const events = [];
    const client = {
      insertEdit: async () => {
        events.push('insert');
        return { id: 'edit-1' };
      },
      listTrackReleases: async (_p, track) => {
        events.push(`list-${track}`);
        return { releases: [] };
      },
    };
    await assert.rejects(
      () => submitGooglePlayProductionReview(plan, {
        client,
        confirmation: 'review-confirmation',
      }),
      /review submission is forbidden/u,
    );
    assert.equal(events.includes('insert'), false);
  }));

test('production review submission retries the readback before giving up', () =>
  withTempRoot(async (root) => {
    const plan = reviewFixture(root);
    let listCalls = 0;
    let committed = false;
    const staged = {
      activeArtifacts: [{ versionCode: plan.release.versionCode }],
      releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW',
      releaseName: plan.release.name,
      track: 'production',
    };
    const client = {
      commitEdit: async () => { committed = true; return { id: 'edit-1' }; },
      discardEdit: async () => {},
      insertEdit: async () => ({ id: 'edit-1' }),
      listTrackReleases: async () => {
        listCalls += 1;
        if (!committed) return { releases: [staged] };
        // Play returns the old state twice before it shows IN_REVIEW.
        if (listCalls < 4) return { releases: [staged] };
        return {
          releases: [{
            ...staged,
            releaseLifecycleState: 'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
          }],
        };
      },
      updateTrack: async (_p, _e, _t, body) => body,
      validateEdit: async () => ({ id: 'edit-1' }),
    };
    const result = await submitGooglePlayProductionReview(plan, {
      client,
      confirmation: 'review-confirmation',
      readbackDelayMs: 0,
      sleepImpl: async () => {},
    });
    assert.equal(result.submitted, true);
    assert.ok(listCalls >= 4);
    assert.equal(readGooglePlayReviewReceipt(plan).review.state, 'APPLIED');
  }));
