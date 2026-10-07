import assert from 'node:assert/strict';
import {
  createHash,
  generateKeyPairSync,
} from 'node:crypto';
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';
import test from 'node:test';
import {
  readAndroidReleaseMetadata,
} from './android-build.mjs';
import {
  readIosReleaseMetadata,
} from './ios-distribution.mjs';
import {
  ADOPTABLE_APP_VERSION_STATES,
  APPLE_LOCALES,
  APP_STORE_CAPTURE_REPORT_RELATIVE_PATH,
  APP_STORE_FRESH_CAPTURE_EVIDENCE,
  APP_STORE_REUSE_COMMITTED_GALLERY_EVIDENCE,
  APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
  APP_STORE_VERSION_RELEASE_TYPE,
  DEFAULT_MANIFEST_RELATIVE_PATH,
  APP_AVAILABILITY_REQUIREMENTS,
  IAP_BASE_PRICES,
  IAP_PRODUCT_IDS,
  IAP_PRODUCT_TYPE_BY_ID,
  IAP_REVIEW_FILE_BY_PRODUCT_ID,
  READ_ONLY_REVIEW_APP_VERSION_STATES,
  SCREENSHOT_FILE_NAMES,
  SCREENSHOT_TARGETS,
  auditAppStoreConnectRelease,
  appVersionState,
  buildAppStoreReviewNotes,
  buildAppStoreReleasePayload,
  canCreateNewAppStoreVersion,
  canonicalJson,
  contactPlanFromEnvironment,
  csvRowsAsObjects,
  createAppStoreConnectToken,
  createAppStoreReleaseManifest,
  createGetOnlyAppStoreConnectClient,
  formatAppStoreReleaseReport,
  iapStateReadinessPlan,
  isAdoptableAppVersionState,
  isReadOnlyReviewAppVersionState,
  normalizeAppVersionState,
  parseAppStoreReleaseArguments,
  readAndVerifyAppStoreReleaseManifest,
  resolveAppStoreCaptureEvidence,
  resolveManifestOutputPath,
  runAppStoreScreenshotValidation,
  selectAppInfoForVersion,
  iapReviewImageMatches,
  validateAppleIapText,
  validateAppleWhatsNew,
  verifyAppStoreReleaseManifest,
  writeAppStoreReleaseManifest,
} from './app-store-release.mjs';
import {
  APP_STORE_REUSE_GALLERY_APPLY_PURPOSE,
  APP_STORE_REUSE_GALLERY_IMAGE_DIFFERS,
  APP_STORE_REUSE_GALLERY_REVIEW_PURPOSE,
  applyAppStoreConnectRelease,
  appStoreApplyCheckSummary,
  appStoreConfirmationToken,
  applyPlanEntry,
  applyReuseCommittedGalleryImageGate,
  assertEditableAppStoreVersionState,
  assertAppStoreApplyAuthorization,
  auditAppAvailability,
  auditAppStoreConnectApplyReadiness,
  auditBuildAssociation,
  auditIapPricing,
  auditInternalBetaGroup,
  auditVersionedIapLocalizations,
  createAppStoreConnectMutationClient,
  createRotatingAppStoreConnectTokenProvider,
  formatAppStoreApplyReport,
  isReviewableIapVersionState,
  pollAppStoreReviewSubmission,
  submitAppStoreConnectReview,
  uploadScreenshotSet,
  verifySubmittedRelease,
} from './app-store-connect-apply.mjs';

function withTempRoot(callback) {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-app-store-release-'));
  return Promise.resolve()
    .then(() => callback(root))
    .finally(() => rmSync(root, { recursive: true, force: true }));
}

function csvQuote(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

function fixtureCsv() {
  const header = [
    'record_type',
    'platform',
    'locale',
    'product_id',
    'product_type',
    'reference_name',
    'display_name',
    'short_description',
    'subtitle',
    'promotional_text',
    'keywords',
    'description',
    'review_notes',
  ];
  const rows = [];
  for (const locale of APPLE_LOCALES) {
    rows.push([
      'app',
      'apple',
      locale,
      '',
      '',
      '',
      `Name ${locale}`,
      '',
      `Subtitle ${locale}`,
      `Promotional text ${locale}`,
      `action,beacon,${locale}`,
      '',
      '',
    ]);
  }
  for (const productId of IAP_PRODUCT_IDS) {
    const short = productId.split('.').at(-1);
    const productType = IAP_PRODUCT_TYPE_BY_ID[productId] === 'CONSUMABLE'
      ? 'consumable'
      : 'non_consumable';
    for (const locale of APPLE_LOCALES) {
      rows.push([
        'iap',
        'apple',
        locale,
        productId,
        productType,
        `Reference ${short}`,
        `${short} ${locale}`,
        '',
        '',
        '',
        '',
        `Description ${locale}`,
        `Review note ${short} ${locale}`,
      ]);
    }
  }
  return [
    header.map(csvQuote).join(','),
    ...rows.map((row) => row.map(csvQuote).join(',')),
    '',
  ].join('\n');
}

function fixtureStorePage({ version = '1.0.0' } = {}) {
  const headings = {
    'en-US': '## English description',
    ko: '## Korean description',
    ja: '## Japanese description',
    'zh-Hans': '## Simplified Chinese description',
    'zh-Hant': '## Traditional Chinese description',
  };
  const whatsNewHeadings = {
    'en-US': '## Google Play release notes — English (`en-US`)',
    ko: '## Google Play release notes — Korean (`ko-KR`)',
    ja: '## Google Play release notes — Japanese (`ja-JP`)',
    'zh-Hans': '## Google Play release notes — Simplified Chinese (`zh-CN`)',
    'zh-Hant': '## Google Play release notes — Traditional Chinese (`zh-TW`)',
  };
  return [
    '# Store page',
    '',
    '| Item | Value |',
    '| --- | --- |',
    `| Version | ${version} |`,
    '',
    '- [x] App Store copyright — `2026 Hyo Jang`',
    '',
    ...APPLE_LOCALES.flatMap((locale) => [
      headings[locale],
      '',
      '```text',
      `Long description ${locale}`,
      '```',
      '',
    ]),
    '## Screenshots',
    '',
    '| File | What |',
    '| --- | --- |',
    ...SCREENSHOT_FILE_NAMES.map(
      (name) => `| \`${name}\` | fixture |`,
    ),
    '',
    ...APPLE_LOCALES.flatMap((locale) => [
      whatsNewHeadings[locale],
      '',
      '```text',
      `Release notes ${locale}`,
      '```',
      '',
    ]),
  ].join('\n');
}

function fixtureProjectGodot({ contacts = false, version = '1.0.0' } = {}) {
  return [
    'config_version=5',
    '',
    '[application]',
    '',
    `config/version="${version}"`,
    contacts
      ? 'config/privacy_policy_url="https://support.example.com/{locale}/privacy"'
      : 'config/privacy_policy_url=""',
    contacts
      ? 'config/support_contact="https://support.example.com/{locale}/support"'
      : 'config/support_contact=""',
    '',
  ].join('\n');
}

function fixtureExportPresets({ version = '1.0.0', build = '1' } = {}) {
  return [
    '[preset.0]',
    'name="iOS"',
    'platform="iOS"',
    `application/bundle_identifier="com.crossplatformkorea.moonlitbeacon"`,
    `application/short_version="${version}"`,
    `application/version="${build}"`,
    'application/app_store_team_id="PRDQGB267K"',
    '',
  ].join('\n');
}

const TEST_PNG_CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let value = 0; value < table.length; value += 1) {
    let crc = value;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) === 1
        ? 0xedb88320 ^ (crc >>> 1)
        : crc >>> 1;
    }
    table[value] = crc >>> 0;
  }
  return table;
})();
const TEST_PNG_CACHE = new Map();

function testPngCrc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc = TEST_PNG_CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBuffer = Buffer.from(type, 'ascii');
  const output = Buffer.alloc(12 + data.length);
  output.writeUInt32BE(data.length, 0);
  typeBuffer.copy(output, 4);
  data.copy(output, 8);
  output.writeUInt32BE(
    testPngCrc32(Buffer.concat([typeBuffer, data])),
    8 + data.length,
  );
  return output;
}

function fakeRgbPng(width, height, unique = 0, colorType = 2) {
  const cacheKey = `${width}x${height}:${colorType}:${unique}`;
  if (TEST_PNG_CACHE.has(cacheKey)) {
    return Buffer.from(TEST_PNG_CACHE.get(cacheKey));
  }
  const bytesPerPixel = colorType === 2 ? 3 : 1;
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = colorType;
  const raw = Buffer.alloc((width * bytesPerPixel + 1) * height);
  Buffer.from(String(unique), 'utf8').copy(
    raw,
    1,
    0,
    Math.min(bytesPerPixel, Buffer.byteLength(String(unique), 'utf8')),
  );
  const output = Buffer.concat([
    Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    ]),
    pngChunk('IHDR', header),
    pngChunk('IDAT', deflateSync(raw, { level: 1 })),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
  TEST_PNG_CACHE.set(cacheKey, output);
  return Buffer.from(output);
}

function testSha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function writeFixtureScreenshotProvenance(root) {
  const capturePath = join(root, APP_STORE_CAPTURE_REPORT_RELATIVE_PATH);
  mkdirSync(dirname(capturePath), { recursive: true });
  const captureContents = Buffer.from(JSON.stringify({
    capture_id: 'fixture-capture',
    schema_version: 4,
  }, null, 2) + '\n');
  writeFileSync(capturePath, captureContents);
  const captureSha256 = testSha256(captureContents);

  const sets = SCREENSHOT_TARGETS.map((target) => {
    const isIphone = target.directory === 'iphone-6.5';
    const reportPath = isIphone
      ? APP_STORE_CAPTURE_REPORT_RELATIVE_PATH
      : 'builds/shots/store-platform/ios/ipad-13/capture-report.json';
    const reportSha256 = isIphone ? captureSha256 : 'b'.repeat(64);
    const mappings = [];
    for (const locale of APPLE_LOCALES) {
      for (const fileName of SCREENSHOT_FILE_NAMES) {
        const outputPath = [
          'builds/release/app-store',
          locale,
          target.directory,
          fileName,
        ].join('/');
        const outputContents = readFileSync(join(root, outputPath));
        const sourcePath = [
          'builds/shots/store-platform',
          isIphone ? 'android/pixel-phone' : 'ios/ipad-13',
          locale,
          fileName,
        ].join('/');
        const proofPath = `${sourcePath}.proof.json`;
        mappings.push({
          asset_locale: locale,
          game_locale: locale,
          kind: fileName.replace(/^[0-9]+-|\.png$/gu, ''),
          output_height: target.height,
          output_path: outputPath,
          output_sha256: testSha256(outputContents),
          output_width: target.width,
          proof_path: proofPath,
          proof_sha256: testSha256(proofPath),
          source_height: isIphone ? 1080 : 2048,
          source_path: sourcePath,
          source_sha256: testSha256(sourcePath),
          source_width: isIphone ? 2424 : 2732,
          store_locale: locale,
        });
      }
    }
    return {
      capture_origin: {
        build_artifact_path: isIphone
          ? 'builds/shots/store-localized/capture-debug.apk'
          : 'builds/ios-device/MoonlitBeacon.app',
        build_artifact_sha256: isIphone ? 'c'.repeat(64) : 'd'.repeat(64),
        capture_report_path: reportPath,
        capture_report_sha256: reportSha256,
        environment: isIphone ? 'AVD' : 'PHYSICAL_DEVICE',
        input_sha256: isIphone ? 'e'.repeat(64) : 'f'.repeat(64),
        native_ios_capture: !isIphone,
        platform: isIphone ? 'ANDROID' : 'IOS',
        runtime_sha256: isIphone ? '1'.repeat(64) : '2'.repeat(64),
      },
      id: target.directory,
      mappings,
      submission_target: {
        device_class: target.directory,
        display_type: target.displayType,
        height: target.height,
        platform: 'IOS',
        width: target.width,
      },
      transform: {
        crop_bottom: 0,
        kind: 'marketing-composite',
        offset_x: 0,
        offset_y: 0,
        renderer_path: 'apps/game/tools/build_store_graphics.py',
        renderer_sha256: '3'.repeat(64),
        scaled_height: target.height,
        scaled_width: target.width,
        stretch: false,
      },
    };
  });
  const provenance = {
    capture_report: {
      file_size: captureContents.length,
      path: APP_STORE_CAPTURE_REPORT_RELATIVE_PATH,
      sha256: captureSha256,
    },
    contract: 'moonlit-app-store-screenshot-provenance-v1',
    iphone_source_mode: 'android-pixel-avd',
    schema_version: 1,
    sets,
  };
  const provenancePath = join(
    root,
    APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
  );
  writeFileSync(provenancePath, JSON.stringify(provenance, null, 2) + '\n');
}

function writeFixture(root, { version = '1.0.0', build = '1' } = {}) {
  const releaseNotes = join(root, 'notes/release');
  const appStore = join(root, 'builds/release/app-store');
  mkdirSync(releaseNotes, { recursive: true });
  mkdirSync(appStore, { recursive: true });
  writeFileSync(
    join(releaseNotes, 'store-localizations.csv'),
    fixtureCsv(),
  );
  writeFileSync(
    join(releaseNotes, 'store-page.md'),
    fixtureStorePage({ version }),
  );
  mkdirSync(join(root, 'apps/game'), { recursive: true });
  writeFileSync(
    join(root, 'apps/game/project.godot'),
    fixtureProjectGodot({ version }),
  );
  writeFileSync(
    join(root, 'apps/game/export_presets.cfg'),
    fixtureExportPresets({ version, build }),
  );
  let unique = 1;
  for (const locale of APPLE_LOCALES) {
    for (const target of SCREENSHOT_TARGETS) {
      const directory = join(appStore, locale, target.directory);
      mkdirSync(directory, { recursive: true });
      for (const name of SCREENSHOT_FILE_NAMES) {
        writeFileSync(
          join(directory, name),
          fakeRgbPng(target.width, target.height, unique),
        );
        unique += 1;
      }
    }
  }
  mkdirSync(join(appStore, 'iap-review'), { recursive: true });
  for (const productId of IAP_PRODUCT_IDS) {
    writeFileSync(
      join(appStore, 'iap-review', IAP_REVIEW_FILE_BY_PRODUCT_ID[productId]),
      fakeRgbPng(2778, 1284, unique),
    );
    unique += 1;
  }
  writeFixtureScreenshotProvenance(root);
}

function fixturePayload(root, options) {
  writeFixture(root, options);
  return buildAppStoreReleasePayload({ repoRoot: root });
}

test('App Store release runs dedicated screenshot validation, not Play', () => {
  let invocation = null;
  assert.equal(runAppStoreScreenshotValidation('/fixture', {
    env: { HOME: '/home/fixture', SECRET: 'do-not-forward' },
    spawn(command, args, options) {
      invocation = { args, command, options };
      return { error: null, status: 0 };
    },
  }), true);
  assert.equal(invocation.command, process.execPath);
  assert.deepEqual(invocation.args, [
    'scripts/python.mjs',
    '-B',
    'apps/game/tools/build_store_graphics.py',
    '--check-app-store-screenshots',
  ]);
  assert.equal(invocation.options.cwd, '/fixture');
  assert.deepEqual(invocation.options.env, { HOME: '/home/fixture' });
  assert.throws(() => runAppStoreScreenshotValidation('/fixture', {
    spawn() {
      return { error: null, status: 2 };
    },
  }), /--check-app-store-screenshots/u);
});

test('5-locale · 60-shot · 50-IAP fixture manifest is deterministic', () =>
  withTempRoot((root) => {
    const first = fixturePayload(root);
    const second = buildAppStoreReleasePayload({ repoRoot: root });
    assert.equal(canonicalJson(first), canonicalJson(second));
    assert.deepEqual(first.counts, {
      appLocalizations: 5,
      screenshots: 60,
      iapProducts: 10,
      iapLocalizations: 50,
      iapReviewImages: 10,
    });
    assert.equal(first.release.version, '1.0.0');
    assert.equal(first.release.buildNumber, '1');
    assert.equal(first.release.appId, '6796293839');
    assert.deepEqual(first.release.availability, APP_AVAILABILITY_REQUIREMENTS);
    assert.equal(first.contact.status, 'unresolved');
    for (const localization of first.appLocalizations) {
      assert.equal(
        localization.version.whatsNew,
        `Release notes ${localization.locale}`,
      );
    }
    const manifest = createAppStoreReleaseManifest(first);
    assert.equal(manifest.schemaVersion, 2);
    assert.equal(verifyAppStoreReleaseManifest(manifest, second), true);
    assert.match(manifest.payloadChecksums.sha256, /^[a-f0-9]{64}$/u);
    assert.match(manifest.payloadChecksums.md5, /^[a-f0-9]{32}$/u);
    for (const localization of first.appLocalizations) {
      for (const set of localization.screenshots) {
        assert.equal(set.provenanceSetId, set.device);
        for (const file of set.files) {
          assert.equal(file.path.startsWith('/'), false);
          assert.equal(file.path.includes('\\'), false);
          assert.match(file.sha256, /^[a-f0-9]{64}$/u);
          assert.match(file.md5, /^[a-f0-9]{32}$/u);
        }
      }
    }
    assert.equal(first.inAppPurchases.reviewImages.length, 10);
    assert.equal(
      new Set(first.inAppPurchases.reviewImages.map(({ sha256 }) => sha256)).size,
      10,
    );
    for (const product of first.inAppPurchases.products) {
      assert.equal(product.type, IAP_PRODUCT_TYPE_BY_ID[product.productId]);
      assert.match(product.reviewNote, /Review note/u);
      assert.deepEqual(product.pricing, {
        strategy: 'VERIFY_EXISTING_MANUAL_BASE_PRICE',
        ...IAP_BASE_PRICES[product.productId],
      });
      assert.equal(
        product.reviewImage.fileName,
        IAP_REVIEW_FILE_BY_PRODUCT_ID[product.productId],
      );
      assert.equal(product.productId.endsWith('.hero_bundle'), false);
    }
    assert.equal(
      first.appStoreReview.notes,
      buildAppStoreReviewNotes(first.inAppPurchases.products),
    );
    assert.ok(IAP_PRODUCT_IDS.every((productId) => (
      first.appStoreReview.notes.includes(productId)
    )));
    assert.match(first.appStoreReview.notes, /Restore purchases/u);
    assert.match(first.appStoreReview.notes, /Tap to start/u);
    assert.match(first.appStoreReview.notes, /Continue as guest/u);
    assert.match(first.appStoreReview.notes, /permanent player ID/u);
    assert.match(first.appStoreReview.notes, /does not go straight to the Arena/u);
    assert.match(first.appStoreReview.notes, /gate lodge/u);
    assert.match(first.appStoreReview.notes, /Lumi/u);
    assert.match(first.appStoreReview.notes, /unique adventurer name/u);
    assert.match(first.appStoreReview.notes, /walk and dash/u);
    assert.match(first.appStoreReview.notes, /moon gate to depart/u);
    assert.match(first.appStoreReview.notes, /cached on the device/u);
    assert.match(first.appStoreReview.notes, /completed guide lesson/u);
    assert.match(first.appStoreReview.notes, /returns to the lodge/u);
    assert.match(first.appStoreReview.notes, /living saved checkpoint/u);
    assert.match(first.appStoreReview.notes, /sealed and never resumes/u);
    assert.match(first.appStoreReview.notes, /rolling twelve hours/u);
    assert.match(first.appStoreReview.notes, /optional local reminder/u);
    assert.match(first.appStoreReview.notes, /never grants coins by itself/u);
    assert.doesNotMatch(
      first.appStoreReview.notes,
      /From that card,\s+tap New expedition to play/u,
    );
    assert.match(first.appStoreReview.notes, /New expedition/u);
    assert.match(first.appStoreReview.notes, /Resume the gate/u);
    assert.match(first.appStoreReview.notes, /Sign in with Google/u);
    assert.match(first.appStoreReview.notes, /Sign in with Apple/u);
    assert.match(
      first.appStoreReview.notes,
      /No developer demo account or password/u,
    );
    assert.doesNotMatch(
      first.appStoreReview.notes,
      /No app account or demo login is required/u,
    );
    assert.match(first.appStoreReview.notes, /Store > Moonlit Supporter/u);
    assert.match(first.appStoreReview.notes, /exactly 1, 5, or 10 coins/u);
    assert.match(first.appStoreReview.notes, /Buy them in advance/u);
    assert.match(
      first.appStoreReview.notes,
      /spend exactly one coin and resume that run at the fall point/u,
    );
    assert.match(
      first.appStoreReview.notes,
      /With zero coins, the button ends the current run and moves to the title-screen Store; no purchase occurs on the result screen/u,
    );
    assert.doesNotMatch(
      first.appStoreReview.notes,
      /With no coin, the Store opens/u,
    );
    assert.match(first.appStoreReview.notes, /seven verified non-consumables/u);
    assert.match(first.appStoreReview.notes, /hero_bundle product is not offered/u);
    assert.ok([...first.appStoreReview.notes].length <= 4000);
    assert.ok(Buffer.byteLength(first.appStoreReview.notes, 'utf8') <= 4000);
    const productsWithVerboseIndividualNotes = first.inAppPurchases.products.map(
      (product) => ({
        ...product,
        reviewNote: `Product-specific path ${'x'.repeat(3000)}`,
      }),
    );
    assert.equal(
      buildAppStoreReviewNotes(productsWithVerboseIndividualNotes),
      first.appStoreReview.notes,
    );

    const missingWhatsNew = structuredClone(first);
    delete missingWhatsNew.appLocalizations[0].version.whatsNew;
    assert.throws(
      () => verifyAppStoreReleaseManifest(
        createAppStoreReleaseManifest(missingWhatsNew),
      ),
      /What's New/u,
    );

    const staleReviewNotes = structuredClone(first);
    staleReviewNotes.appStoreReview.notes = 'Three products and Hero Bundle';
    assert.throws(
      () => verifyAppStoreReleaseManifest(
        createAppStoreReleaseManifest(staleReviewNotes),
      ),
      /10-IAP test\/restore guidance/u,
    );

    const tampered = structuredClone(first);
    tampered.inAppPurchases.products[1].reviewImage = {
      ...tampered.inAppPurchases.products[0].reviewImage,
    };
    tampered.inAppPurchases.reviewImages[1] = {
      productId: tampered.inAppPurchases.products[1].productId,
      ...tampered.inAppPurchases.products[0].reviewImage,
    };
    assert.throws(
      () => verifyAppStoreReleaseManifest(
        createAppStoreReleaseManifest(tampered),
      ),
      /review image mapping/u,
    );

    const wrongConsumableType = structuredClone(first);
    const coin = wrongConsumableType.inAppPurchases.products.find((product) => (
      product.productId.endsWith('.continue_coin')
    ));
    coin.type = 'NON_CONSUMABLE';
    assert.throws(
      () => verifyAppStoreReleaseManifest(
        createAppStoreReleaseManifest(wrongConsumableType),
      ),
      /review image mapping/u,
    );
  }));

test('App Review notes lead a fresh guest through the name room before the Arena', () =>
  withTempRoot((root) => {
    const payload = fixturePayload(root);
    const notes = buildAppStoreReviewNotes(payload.inAppPurchases.products);
    assert.equal(notes, payload.appStoreReview.notes);
    for (const fragment of [
      'does not go straight to the Arena',
      'gate lodge',
      'Lumi',
      'unique adventurer name',
      'needs a connection and cannot be renamed',
      'walk and dash',
      'moon gate to depart',
      'cached on the device',
      'identifies the account when offline',
      'verified name plus a completed guide lesson',
      'returns to the lodge',
      'living saved checkpoint',
      'sealed and never resumes',
      'one-coin revive',
      'rolling twelve hours',
      'at most once per twelve hours',
      'optional local reminder',
      'never grants coins by itself',
      'No developer demo account or password',
    ]) {
      assert.ok(notes.includes(fragment), `review notes mention: ${fragment}`);
    }
    assert.ok(!notes.includes('From that card, tap New expedition to play'));
    assert.ok(IAP_PRODUCT_IDS.every((productId) => notes.includes(productId)));
    assert.ok(notes.includes('Restore purchases'));
    assert.ok([...notes].length <= 4000);
    assert.ok(Buffer.byteLength(notes, 'utf8') <= 4000);
  }));

test('release identities agree across project, presets, and store page', () => {
  const repoRoot = fileURLToPath(new URL('../..', import.meta.url));
  const project = readFileSync(join(repoRoot, 'apps/game/project.godot'), 'utf8');
  const presets = readFileSync(join(repoRoot, 'apps/game/export_presets.cfg'), 'utf8');
  const storePage = readFileSync(join(repoRoot, 'notes/release/store-page.md'), 'utf8');
  const ios = readIosReleaseMetadata(project, presets);
  const android = readAndroidReleaseMetadata(project, presets);
  assert.equal(android.direct.versionName, ios.projectVersion);
  assert.equal(android.play.versionName, ios.projectVersion);
  assert.equal(android.direct.versionCode, android.play.versionCode);
  assert.ok(android.direct.versionCode >= 1);
  assert.match(ios.buildVersion, /^[0-9]+$/u);
  const versionRow = storePage.match(
    /^\|\s*Version\s*\|\s*([0-9]+(?:\.[0-9]+){1,2})\s*\|$/mu,
  )?.[1];
  assert.equal(versionRow, ios.projectVersion);
  assert.ok(storePage.includes(`MoonlitBeacon-${ios.projectVersion}.apk`));
});

test('manifest save/check requires matching current payload and hashes', () =>
  withTempRoot((root) => {
    const payload = fixturePayload(root);
    const manifest = createAppStoreReleaseManifest(payload);
    const output = resolveManifestOutputPath(
      root,
      DEFAULT_MANIFEST_RELATIVE_PATH,
    );
    writeAppStoreReleaseManifest(output, manifest);
    const checked = readAndVerifyAppStoreReleaseManifest(output, payload);
    assert.equal(canonicalJson(checked), canonicalJson(manifest));

    const tampered = JSON.parse(readFileSync(output, 'utf8'));
    tampered.payload.release.version = '9.9.9';
    writeFileSync(output, canonicalJson(tampered));
    assert.throws(
      () => readAndVerifyAppStoreReleaseManifest(output, payload),
      /sha256 verification/,
    );
  }));

test('provenance links exactly to 5-locale screenshot outputs by SHA-256', () =>
  withTempRoot((root) => {
    writeFixture(root);
    const path = join(root, APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH);
    const provenance = JSON.parse(readFileSync(path, 'utf8'));
    provenance.sets[0].mappings[0].output_sha256 = '0'.repeat(64);
    writeFileSync(path, JSON.stringify(provenance, null, 2) + '\n');
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /output mapping differs from the actual PNG/u,
    );
  }));

test('provenance changes invalidate the current manifest and change the confirmation token', () =>
  withTempRoot((root) => {
    const originalPayload = fixturePayload(root);
    const originalManifest = createAppStoreReleaseManifest(originalPayload);
    const output = resolveManifestOutputPath(
      root,
      DEFAULT_MANIFEST_RELATIVE_PATH,
    );
    writeAppStoreReleaseManifest(output, originalManifest);

    const path = join(root, APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH);
    const provenance = JSON.parse(readFileSync(path, 'utf8'));
    provenance.generated_note = 'new verified generation';
    writeFileSync(path, JSON.stringify(provenance, null, 2) + '\n');
    const currentPayload = buildAppStoreReleasePayload({ repoRoot: root });
    const currentManifest = createAppStoreReleaseManifest(currentPayload);
    assert.throws(
      () => readAndVerifyAppStoreReleaseManifest(output, currentPayload),
      /differs from current metadata\/images/u,
    );
    assert.notEqual(
      appStoreConfirmationToken(originalManifest, 'apply'),
      appStoreConfirmationToken(currentManifest, 'apply'),
    );
  }));

test('remote apply blocks both GET and mutation at 0 when provenance is tampered', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root);
    payload.release.version = '2.1.0';
    payload.release.buildNumber = '9';
    const manifest = createAppStoreReleaseManifest(payload);
    const confirmation = appStoreConfirmationToken(manifest, 'apply');
    const provenancePath = join(
      root,
      APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
    );
    writeFileSync(
      provenancePath,
      `${readFileSync(provenancePath, 'utf8')}\n`,
    );
    let remoteCalls = 0;
    const failIfCalled = async () => {
      remoteCalls += 1;
      throw new Error('remote call must not execute');
    };
    await assert.rejects(
      applyAppStoreConnectRelease({
        client: {
          delete: failIfCalled,
          patch: failIfCalled,
          post: failIfCalled,
        },
        confirmation,
        getClient: {
          get: failIfCalled,
          getAll: failIfCalled,
        },
        manifest,
        payload,
        repoRoot: root,
      }),
      /ASC_ASSET_CHANGED/u,
    );
    assert.equal(remoteCalls, 0);
  }));

test('rejects missing/unexpected PNG, size, and RGB24 screenshot errors', () =>
  withTempRoot((root) => {
    fixturePayload(root);
    const directory = join(
      root,
      'builds/release/app-store/en-US/iphone-6.5',
    );
    const first = join(directory, SCREENSHOT_FILE_NAMES[0]);
    unlinkSync(first);
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /missing: 01-moonlight-barrage\.png/u,
    );

    writeFileSync(first, fakeRgbPng(2778, 1284, 90));
    writeFileSync(join(directory, '07-unexpected.png'), fakeRgbPng(
      2778,
      1284,
      91,
    ));
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /unexpected: 07-unexpected\.png/u,
    );
    unlinkSync(join(directory, '07-unexpected.png'));

    writeFileSync(first, fakeRgbPng(1, 1, 92));
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /size differs/u,
    );
    const indexed = fakeRgbPng(2778, 1284, 93, 3);
    writeFileSync(first, indexed);
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /RGB24 PNG/u,
    );

    const valid = fakeRgbPng(2778, 1284);
    writeFileSync(first, valid.subarray(0, 33));
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /PNG signature or length is invalid|IHDR, IDAT, and IEND/u,
    );

    const corrupt = Buffer.from(valid);
    corrupt[corrupt.length - 1] ^= 0xff;
    writeFileSync(first, corrupt);
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /CRC/u,
    );
  }));

test('IAP review images are 1:1 with the 10 sale products and reject legacy/shared/duplicates', () =>
  withTempRoot((root) => {
    fixturePayload(root);
    const directory = join(root, 'builds/release/app-store/iap-review');
    const dancer = join(directory, 'hero-dancer.png');
    const keeper = join(directory, 'hero-keeper.png');

    writeFileSync(
      join(directory, 'hero-bundle.png'),
      fakeRgbPng(2778, 1284, 'legacy'),
    );
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /unexpected: hero-bundle\.png/u,
    );
    unlinkSync(join(directory, 'hero-bundle.png'));

    writeFileSync(
      join(root, 'builds/release/app-store/iap-review.png'),
      fakeRgbPng(2778, 1284, 'old-common'),
    );
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /legacy shared iap-review\.png/u,
    );
    unlinkSync(join(root, 'builds/release/app-store/iap-review.png'));

    writeFileSync(keeper, readFileSync(dancer));
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /distinct real store-location/u,
    );
  }));

test('screenshot/manifest inputs and outputs reject symbolic links and path escapes', () =>
  withTempRoot((root) => {
    fixturePayload(root);
    const real = join(
      root,
      'builds/release/app-store/en-US/iphone-6.5',
      SCREENSHOT_FILE_NAMES[0],
    );
    const outside = join(root, 'outside.png');
    writeFileSync(outside, readFileSync(real));
    unlinkSync(real);
    symlinkSync(outside, real);
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /regular file|symbolic link/u,
    );
    unlinkSync(real);
    writeFileSync(real, readFileSync(outside));

    const appStoreRoot = join(root, 'builds/release/app-store');
    const externalAppStoreRoot = `${root}-external-app-store`;
    renameSync(appStoreRoot, externalAppStoreRoot);
    try {
      symlinkSync(externalAppStoreRoot, appStoreRoot, 'dir');
      assert.throws(
        () => buildAppStoreReleasePayload({ repoRoot: root }),
        /symbolic link/u,
      );
    } finally {
      unlinkSync(appStoreRoot);
      renameSync(externalAppStoreRoot, appStoreRoot);
    }

    assert.throws(
      () => resolveManifestOutputPath(root, '../manifest.json'),
      /builds\/release/u,
    );
    assert.throws(
      () => resolveManifestOutputPath(
        root,
        'builds/release/app-store/manifest.json',
      ),
      /screenshot input/u,
    );
    const internalOutputDirectory = join(root, 'builds/release/manifest-target');
    mkdirSync(internalOutputDirectory);
    symlinkSync(
      internalOutputDirectory,
      join(root, 'builds/release/manifest-link'),
      'dir',
    );
    assert.throws(
      () => resolveManifestOutputPath(
        root,
        'builds/release/manifest-link/release.json',
      ),
      /symbolic link/u,
    );

    const externalReleaseRoot = `${root}-external-release-root`;
    mkdirSync(externalReleaseRoot);
    try {
      rmSync(join(root, 'builds/release'), { recursive: true });
      symlinkSync(externalReleaseRoot, join(root, 'builds/release'), 'dir');
      assert.throws(
        () => resolveManifestOutputPath(
          root,
          'builds/release/app-store-release-manifest.json',
        ),
        /outside builds\/release|symbolic link/u,
      );
    } finally {
      rmSync(externalReleaseRoot, { recursive: true, force: true });
    }
  }));

test('CLI remote apply and review submission each require an explicit confirmation token', () => {
  assert.deepEqual(parseAppStoreReleaseArguments([]), {
    apply: false,
    check: false,
    confirmation: null,
    reviewConfirmation: null,
    remoteAudit: false,
    reuseCommittedGallery: false,
    submitReview: false,
    json: false,
    help: false,
    output: DEFAULT_MANIFEST_RELATIVE_PATH,
  });
  assert.deepEqual(
    parseAppStoreReleaseArguments([
      '--dry-run',
      '--check',
      '--remote-audit',
      '--json',
      '--output',
      'builds/release/custom.json',
    ]),
    {
      apply: false,
      check: true,
      confirmation: null,
      reviewConfirmation: null,
      remoteAudit: true,
      reuseCommittedGallery: false,
      submitReview: false,
      json: true,
      help: false,
      output: 'builds/release/custom.json',
    },
  );
  for (const args of [
    ['--apply'],
    ['--upload'],
    ['--method', 'POST'],
    ['--output'],
    ['--remote-audit', '--remote-audit'],
    ['--reuse-committed-gallery', '--reuse-committed-gallery'],
  ]) {
    assert.throws(
      () => parseAppStoreReleaseArguments(args),
      (error) => error.exitCode === 2
        && /unsupported|requires|duplicate/u.test(error.message),
    );
  }
  assert.deepEqual(parseAppStoreReleaseArguments([
    '--check',
    '--remote-audit',
    '--apply',
    '--confirm-remote-apply',
    'app-store:apply:6796293839:1.0.1:2:digest',
    '--submit-review',
    '--confirm-review-submission',
    'app-store:review:6796293839:1.0.1:2:digest',
  ]), {
    apply: true,
    check: true,
    confirmation: 'app-store:apply:6796293839:1.0.1:2:digest',
    help: false,
    json: false,
    output: DEFAULT_MANIFEST_RELATIVE_PATH,
    remoteAudit: true,
    reuseCommittedGallery: false,
    reviewConfirmation: 'app-store:review:6796293839:1.0.1:2:digest',
    submitReview: true,
  });
  for (const args of [
    ['--dry-run', '--check', '--remote-audit', '--apply',
      '--confirm-remote-apply', 'token'],
    ['--confirm-remote-apply', 'token'],
    ['--submit-review'],
    ['--confirm-review-submission', 'token'],
  ]) {
    assert.throws(
      () => parseAppStoreReleaseArguments(args),
      (error) => error.exitCode === 2,
    );
  }
});

test('public contact env validates both together and builds 5-locale URLs', () => {
  assert.equal(contactPlanFromEnvironment({}), null);
  assert.throws(
    () => contactPlanFromEnvironment({
      MOONLIT_PUBLIC_SITE_URL: 'https://support.example.com',
    }),
    (error) => error.exitCode === 2 && /together/u.test(error.message),
  );
  const plan = contactPlanFromEnvironment({
    MOONLIT_PUBLIC_SITE_URL: 'https://support.example.com/',
    MOONLIT_SUPPORT_EMAIL: 'support+moonlit@example.com',
  });
  assert.deepEqual(plan.appStore.ja, {
    privacyPolicyUrl: 'https://support.example.com/ja/privacy',
    supportUrl: 'https://support.example.com/ja/support',
  });
  assert.throws(
    () => contactPlanFromEnvironment({
      MOONLIT_PUBLIC_SITE_URL: 'https://support.example.com/path',
      MOONLIT_SUPPORT_EMAIL: 'support@example.com',
    }),
    /HTTPS origin/u,
  );
});

test('App Store manifest must match project version and in-app public links', () =>
  withTempRoot((root) => {
    writeFixture(root);
    const contactPlan = contactPlanFromEnvironment({
      MOONLIT_PUBLIC_SITE_URL: 'https://support.example.com',
      MOONLIT_SUPPORT_EMAIL: 'support@example.com',
    });
    assert.throws(
      () => buildAppStoreReleasePayload({
        repoRoot: root,
        contactPlan,
      }),
      /differs from in-app links in project\.godot/u,
    );

    writeFileSync(
      join(root, 'apps/game/project.godot'),
      fixtureProjectGodot({ contacts: true }),
    );
    const payload = buildAppStoreReleasePayload({
      repoRoot: root,
      contactPlan,
    });
    assert.equal(payload.contact.status, 'resolved');
    assert.equal(payload.release.version, '1.0.0');
    assert.equal(
      payload.release.bundleId,
      'com.crossplatformkorea.moonlitbeacon',
    );
    assert.deepEqual(
      payload.sources.map((source) => source.path),
      [
        'notes/release/store-localizations.csv',
        'notes/release/store-page.md',
        'apps/game/project.godot',
        'apps/game/export_presets.cfg',
        APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
        APP_STORE_CAPTURE_REPORT_RELATIVE_PATH,
      ],
    );

    writeFileSync(
      join(root, 'apps/game/project.godot'),
      fixtureProjectGodot({ contacts: true, version: '1.0.1' }),
    );
    writeFileSync(
      join(root, 'apps/game/export_presets.cfg'),
      fixtureExportPresets({ version: '1.0.1' }),
    );
    assert.throws(
      () => buildAppStoreReleasePayload({
        repoRoot: root,
        contactPlan,
      }),
      /store-page\.md release version 1\.0\.0 differs from iOS display version 1\.0\.1/u,
    );
  }));

test('enforces Apple IAP text limits before submit', () => {
  const valid = {
    referenceName: 'Hero Bundle',
    name: 'Hero Bundle',
    description: 'Unlock two heroes permanently.',
    reviewNote: 'Open the shop and choose Hero Bundle.',
  };
  assert.doesNotThrow(() => validateAppleIapText(valid));
  for (const [field, value, pattern] of [
    ['referenceName', 'r'.repeat(65), /64 characters/u],
    ['name', 'x', /2–30 characters/u],
    ['name', 'x'.repeat(31), /2–30 characters/u],
    ['description', 'd'.repeat(46), /45 characters/u],
    ['reviewNote', 'n'.repeat(4001), /4,000 characters/u],
  ]) {
    assert.throws(
      () => validateAppleIapText({ ...valid, [field]: value }),
      pattern,
    );
  }
});

test('Continue Coin 3-product × 5-locale App Review notes match the anti-pressure result flow', () => {
  const rows = csvRowsAsObjects(readFileSync(
    join(process.cwd(), 'notes/release/store-localizations.csv'),
    'utf8',
  ));
  const productIds = IAP_PRODUCT_IDS.slice(-3);
  const coinRows = rows.filter((row) => (
    row.record_type === 'iap'
    && row.platform === 'apple'
    && productIds.includes(row.product_id)
  ));
  assert.equal(coinRows.length, productIds.length * APPLE_LOCALES.length);
  for (const productId of productIds) {
    assert.deepEqual(
      coinRows
        .filter((row) => row.product_id === productId)
        .map((row) => row.locale),
      APPLE_LOCALES,
    );
  }
  const contractPatterns = {
    'en-US': [
      /in advance/u,
      /spend exactly one coin/u,
      /With zero coins.*ends the current run.*title-screen Store.*no purchase occurs/su,
    ],
    ko: [
      /미리 구매/u,
      /정확히 1개를 사용/u,
      /코인이 0개.*현재 판을 끝내고.*타이틀 상점.*구매가 일어나지/su,
    ],
    ja: [
      /事前に購入/u,
      /ちょうど1枚を消費/u,
      /所持数が0.*現在のランを終了.*タイトル画面のストア.*購入されません/su,
    ],
    'zh-Hans': [
      /提前.*购买/u,
      /恰好消耗一枚/u,
      /余额为零.*结束当前对局.*标题商店.*不会发生购买/su,
    ],
    'zh-Hant': [
      /提前.*購買/u,
      /恰好消耗一枚/u,
      /餘額為零.*結束目前對局.*標題商店.*不會發生購買/su,
    ],
  };
  for (const row of coinRows) {
    for (const pattern of contractPatterns[row.locale]) {
      assert.match(row.review_notes, pattern);
    }
    assert.doesNotMatch(
      row.review_notes,
      /With no coin.*opens|코인이 없으면 상점이 열리고|コインがない場合はストアが開き|若没有金币，将打开商店|若沒有金幣，將開啟商店/su,
    );
  }
});

test("App Store What's New is required and capped at 4,000 characters", () => {
  assert.equal(validateAppleWhatsNew('새 기능'), '새 기능');
  assert.doesNotThrow(() => validateAppleWhatsNew('가'.repeat(4000)));
  assert.throws(
    () => validateAppleWhatsNew('가'.repeat(4001)),
    /4,000 characters/u,
  );
  assert.throws(() => validateAppleWhatsNew('  '), /is empty/u);
});

test("App Store What's New requires exactly the 5 Play release-note sections from store-page", () =>
  withTempRoot((root) => {
    writeFixture(root);
    const path = join(root, 'notes/release/store-page.md');
    writeFileSync(
      path,
      readFileSync(path, 'utf8').replace(
        '## Google Play release notes — Japanese (`ja-JP`)',
        '## Japanese release notes',
      ),
    );
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /Google Play release notes.*Japanese.*found 0/u,
    );
  }));

test('ASC client only GETs the same origin and follows pagination', async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url: String(url), options });
    assert.equal(options.method, 'GET');
    assert.equal('body' in options, false);
    assert.equal(options.headers.Authorization, 'Bearer test.jwt.value');
    const page = new URL(url).searchParams.get('page');
    return new Response(JSON.stringify({
      data: [{ id: page ?? 'one' }],
      links: page
        ? {}
        : {
          next:
            'https://api.appstoreconnect.apple.com/v1/apps?page=two',
        },
    }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };
  const client = createGetOnlyAppStoreConnectClient({
    fetchImpl,
    token: 'test.jwt.value',
  });
  const resources = await client.getAll('/v1/apps?limit=1');
  assert.deepEqual(resources.map((entry) => entry.id), ['one', 'two']);
  assert.equal(calls.length, 2);
  assert.deepEqual(
    client.requests.map((request) => request.method),
    ['GET', 'GET'],
  );
  await assert.rejects(
    client.get('https://example.com/v1/apps'),
    /origin/u,
  );
  await assert.rejects(
    client.get('https://user@api.appstoreconnect.apple.com/v1/apps'),
    /credentials or a fragment/u,
  );
  assert.equal('post' in client, false);
});

test('ASC JWT is ES256 P-256 and does not put key material in the result payload', () => {
  const { privateKey } = generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
  });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const token = createAppStoreConnectToken({
    keyId: 'C7KU9KLW58',
    issuerId: 'ac827025-9ee1-4af5-b113-db52ba4c65c2',
    privateKey: pem,
    now: Date.parse('2026-07-31T00:00:00Z'),
  });
  const [headerPart, payloadPart, signaturePart] = token.split('.');
  const header = JSON.parse(Buffer.from(headerPart, 'base64url'));
  const payload = JSON.parse(Buffer.from(payloadPart, 'base64url'));
  assert.deepEqual(header, {
    alg: 'ES256',
    kid: 'C7KU9KLW58',
    typ: 'JWT',
  });
  assert.equal(payload.aud, 'appstoreconnect-v1');
  assert.equal(payload.exp - payload.iat, 1199);
  assert.equal(Buffer.from(signaturePart, 'base64url').length, 64);
  assert.equal(token.includes('PRIVATE KEY'), false);
});

test('ASC tokenProvider refreshes JWT during a 20-minute job with a safety margin', () => {
  const { privateKey } = generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
  });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const startedAt = Date.parse('2026-08-03T00:00:00Z');
  let now = startedAt;
  const tokenProvider = createRotatingAppStoreConnectTokenProvider({
    issuerId: 'ac827025-9ee1-4af5-b113-db52ba4c65c2',
    keyId: 'C7KU9KLW58',
    now: () => now,
    privateKey: pem,
  });
  const first = tokenProvider();
  now += 17 * 60 * 1000;
  assert.equal(tokenProvider(), first);
  now = startedAt + 20 * 60 * 1000;
  const rotated = tokenProvider();
  assert.notEqual(rotated, first);
  const firstPayload = JSON.parse(Buffer.from(first.split('.')[1], 'base64url'));
  const rotatedPayload = JSON.parse(Buffer.from(rotated.split('.')[1], 'base64url'));
  assert.equal(rotatedPayload.iat - firstPayload.iat, 20 * 60);
  assert.equal(rotatedPayload.exp - rotatedPayload.iat, 1199);
});

test('ASC GET/mutation client re-reads tokenProvider on every authenticated request', async () => {
  let token = 'token-one';
  const headers = [];
  const fetchImpl = async (url, options) => {
    headers.push(options.headers.Authorization);
    return new Response(JSON.stringify({ data: [] }), { status: 200 });
  };
  const tokenProvider = () => token;
  const getClient = createGetOnlyAppStoreConnectClient({
    fetchImpl,
    tokenProvider,
  });
  await getClient.get('/v1/apps');
  token = 'token-two';
  const mutationClient = createAppStoreConnectMutationClient({
    fetchImpl,
    tokenProvider,
  });
  await mutationClient.post('/v1/reviewSubmissions', { data: {} });
  assert.deepEqual(headers, ['Bearer token-one', 'Bearer token-two']);
});

test('App Info is chosen by release version state, not opaque ID', () => {
  const draft = {
    id: 'z-draft',
    attributes: { appStoreState: 'PREPARE_FOR_SUBMISSION' },
  };
  const live = {
    id: 'a-live',
    attributes: { appStoreState: 'READY_FOR_SALE' },
  };
  assert.equal(
    selectAppInfoForVersion(
      [live, draft],
      { attributes: { appStoreState: 'PREPARE_FOR_SUBMISSION' } },
    ),
    draft,
  );
  assert.throws(
    () => selectAppInfoForVersion(
      [live],
      { attributes: { appStoreState: 'PREPARE_FOR_SUBMISSION' } },
    ),
    /exactly one/u,
  );
  assert.equal(selectAppInfoForVersion([live], null), null);
  assert.equal(selectAppInfoForVersion([live, draft], null), draft);
});

test('IAP remote state is a release gate including price and availability', () => {
  assert.equal(
    iapStateReadinessPlan(
      'com.example.ready',
      { id: 'ready', attributes: { state: 'READY_TO_SUBMIT' } },
    ),
    null,
  );
  assert.deepEqual(
    iapStateReadinessPlan(
      'com.example.missing',
      { id: 'missing', attributes: { state: 'MISSING_METADATA' } },
    ),
    {
      action: 'unresolved',
      target: 'inAppPurchaseReadiness',
      identifier: 'com.example.missing',
      remoteId: 'missing',
      code: 'IAP_REMOTE_STATE_NOT_RELEASE_READY',
      remoteState: 'MISSING_METADATA',
      reason:
        'IAP remote state is not READY_TO_SUBMIT or APPROVED. '
        + 'The owner must confirm price, availability, metadata, and review state.',
      remoteMutationPlanned: false,
    },
  );
});

test('does not select live App Info as the edit target before a new version', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root);
    const paths = [];
    const client = {
      requests: [],
      async get(path) {
        paths.push(path);
        if (path.startsWith('/v1/apps/6796293839?')) {
          return {
            data: resource('6796293839', {
              bundleId: payload.release.bundleId,
            }),
          };
        }
        throw new Error(`unexpected GET ${path}`);
      },
      async getAll(path) {
        paths.push(path);
        if (path.startsWith('/v1/apps/6796293839/appStoreVersions?')) {
          return [];
        }
        if (path.startsWith('/v1/apps/6796293839/appInfos?')) {
          return [{
            id: 'a-live',
            attributes: { appStoreState: 'READY_FOR_SALE' },
          }];
        }
        if (path.startsWith('/v1/apps/6796293839/inAppPurchasesV2?')) {
          return [];
        }
        throw new Error(`unexpected GET ${path}`);
      },
    };
    const audit = await auditAppStoreConnectRelease({ payload, client });
    assert.equal(audit.remote.appInfoId, null);
    assert.ok(audit.plan.some((entry) => (
      entry.target === 'appStoreVersion'
      && entry.action === 'create'
      && entry.desired.copyright === '2026 Hyo Jang'
    )));
    assert.ok(audit.plan.some((entry) => (
      entry.target === 'appInfoLocalization'
      && entry.identifier === 'en-US'
      && entry.action === 'create'
      && entry.prerequisites.includes('appStoreVersion:1.0.0')
    )));
    assert.equal(
      paths.some((path) => path.includes('/appInfos/a-live/')),
      false,
    );
  }));

function jsonResponse(data, status = 200) {
  return new Response(
    data === null ? '' : JSON.stringify(data),
    {
      status,
      headers: { 'content-type': 'application/json' },
    },
  );
}

function resource(id, attributes, type = 'fixture') {
  return { type, id, attributes };
}

function minimalReleasePayload() {
  return {
    release: {
      appId: '6796293839',
      bundleId: 'com.crossplatformkorea.moonlitbeacon',
      copyright: '2026 Hyo Jang',
      version: '1.0.1',
    },
    appStoreReview: { notes: 'current seven-product restore instructions' },
    appLocalizations: [],
    contact: { gates: [], status: 'resolved' },
    inAppPurchases: { products: [] },
  };
}

function versionAuditClient({
  allVersions = [],
  exactVersions = [],
  reviewDetail = resource('review-detail-1', {
    contactEmail: 'sensitive-contact@example.invalid',
    contactPhone: '+10000000000',
    demoAccountName: 'sensitive-demo',
    demoAccountPassword: 'sensitive-password',
    demoAccountRequired: false,
    notes: 'stale review instructions',
  }),
} = {}) {
  const paths = [];
  return {
    paths,
    requests: [],
    async get(path) {
      paths.push(path);
      const pathname = new URL(path, 'https://example.invalid').pathname;
      if (pathname === '/v1/apps/6796293839') {
        return {
          data: resource('6796293839', {
            bundleId: 'com.crossplatformkorea.moonlitbeacon',
          }),
        };
      }
      if (pathname.endsWith('/appStoreReviewDetail')) {
        return {
          data: typeof reviewDetail === 'function'
            ? reviewDetail()
            : reviewDetail,
        };
      }
      throw new Error(`unexpected GET ${path}`);
    },
    async getAll(path) {
      paths.push(path);
      const url = new URL(path, 'https://example.invalid');
      if (url.pathname.endsWith('/appStoreVersions')) {
        return url.searchParams.has('filter[versionString]')
          ? exactVersions
          : allVersions;
      }
      if (url.pathname.endsWith('/appInfos')) {
        return [resource('app-info-1', {})];
      }
      if (
        url.pathname.endsWith('/appInfoLocalizations')
        || url.pathname.endsWith('/appStoreVersionLocalizations')
        || url.pathname.endsWith('/inAppPurchasesV2')
      ) {
        return [];
      }
      throw new Error(`unexpected GET ALL ${path}`);
    },
  };
}

test('ASC version state normalize/reuse/create proofs are fail-closed', () => {
  assert.equal(normalizeAppVersionState('READY_FOR_SALE'), 'READY_FOR_DISTRIBUTION');
  assert.equal(
    normalizeAppVersionState('PROCESSING_FOR_APP_STORE'),
    'PROCESSING_FOR_DISTRIBUTION',
  );
  assert.equal(isAdoptableAppVersionState('PREPARE_FOR_SUBMISSION'), true);
  assert.equal(isAdoptableAppVersionState('DEVELOPER_REJECTED'), true);
  assert.equal(isAdoptableAppVersionState('WAITING_FOR_REVIEW'), false);
  assert.equal(
    appVersionState(resource('legacy-live', { appStoreState: 'READY_FOR_SALE' })),
    'READY_FOR_DISTRIBUTION',
  );
  assert.equal(canCreateNewAppStoreVersion([]), true);
  assert.equal(canCreateNewAppStoreVersion([
    resource('live', { appStoreState: 'READY_FOR_SALE' }),
  ]), true);
  assert.equal(canCreateNewAppStoreVersion([
    resource('live', { appVersionState: 'READY_FOR_DISTRIBUTION' }),
    resource('old', { appVersionState: 'REPLACED_WITH_NEW_VERSION' }),
  ]), true);
  assert.equal(canCreateNewAppStoreVersion([
    resource('waiting', { appVersionState: 'WAITING_FOR_REVIEW' }),
  ]), false);
  assert.equal(canCreateNewAppStoreVersion([
    resource('live-a', { appVersionState: 'READY_FOR_DISTRIBUTION' }),
    resource('live-b', { appVersionState: 'READY_FOR_DISTRIBUTION' }),
  ]), false);
  assert.equal(assertEditableAppStoreVersionState('DEVELOPER_REJECTED'), 'DEVELOPER_REJECTED');
  assert.throws(
    () => assertEditableAppStoreVersionState('WAITING_FOR_REVIEW'),
    /ASC_VERSION_NOT_EDITABLE/u,
  );
});

function releasedIosVersion(id, versionString, stateAttributes) {
  return {
    type: 'appStoreVersions',
    id,
    attributes: {
      copyright: '2026 Hyo Jang',
      platform: 'IOS',
      versionString,
      ...stateAttributes,
    },
  };
}

function realReleasedHistory() {
  return [
    releasedIosVersion('asc-version-2-1-0', '2.1.0', {
      appStoreState: 'READY_FOR_SALE',
      appVersionState: 'READY_FOR_DISTRIBUTION',
    }),
    releasedIosVersion('asc-version-2-0-0', '2.0.0', {
      appStoreState: 'READY_FOR_SALE',
      appVersionState: 'READY_FOR_DISTRIBUTION',
    }),
  ];
}

test('released-only 2.1.0/2.0.0 history with distinct iOS identity can create', () => {
  const history = realReleasedHistory();
  assert.equal(canCreateNewAppStoreVersion(history), true);
  assert.equal(canCreateNewAppStoreVersion([...history].reverse()), true);
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-2-1-0', '2.1.0', {
      appStoreState: 'READY_FOR_SALE',
    }),
    releasedIosVersion('asc-version-2-0-0', '2.0.0', {
      appStoreState: 'READY_FOR_SALE',
    }),
  ]), true);
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-2-1-0', '2.1.0', {
      appVersionState: 'READY_FOR_DISTRIBUTION',
    }),
    releasedIosVersion('asc-version-2-0-0', '2.0.0', {
      appVersionState: 'READY_FOR_DISTRIBUTION',
    }),
  ]), true);
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-2-1-0', '2.1.0', {
      appStoreState: 'READY_FOR_SALE',
    }),
    releasedIosVersion('asc-version-2-0-0', '2.0.0', {
      appVersionState: 'READY_FOR_DISTRIBUTION',
    }),
  ]), true);
});

test('multiple-live history stays fail-closed without distinct iOS identity', () => {
  const live = { appVersionState: 'READY_FOR_DISTRIBUTION' };
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-a', '2.1.0', live),
    releasedIosVersion('asc-version-b', '2.1.0', live),
  ]), false);
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-same', '2.1.0', live),
    releasedIosVersion('asc-version-same', '2.0.0', live),
  ]), false);
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-2-1-0', '2.1.0', live),
    {
      type: 'appStoreVersions',
      attributes: {
        appVersionState: 'READY_FOR_DISTRIBUTION',
        platform: 'IOS',
        versionString: '2.0.0',
      },
    },
  ]), false);
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-2-1-0', '2.1.0', live),
    releasedIosVersion('   ', '2.0.0', live),
  ]), false);
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-2-1-0', '2.1.0', live),
    {
      type: 'appStoreVersions',
      id: 'asc-version-2-0-0',
      attributes: { appVersionState: 'READY_FOR_DISTRIBUTION', platform: 'IOS' },
    },
  ]), false);
  for (const versionString of ['v2.1.0', '2.1.0.0', '', '  ', '2..1']) {
    assert.equal(canCreateNewAppStoreVersion([
      releasedIosVersion('asc-version-2-1-0', '2.1.0', live),
      releasedIosVersion('asc-version-2-0-0', versionString, live),
    ]), false);
  }
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-2-1-0', '2.1.0', live),
    releasedIosVersion('asc-version-2-0-0', '2.0.0', live),
    resource('old', { appVersionState: 'REPLACED_WITH_NEW_VERSION' }),
  ]), false);
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-2-1-0', '2.1.0', live),
    {
      type: 'appStoreVersions',
      id: 'asc-version-2-0-0',
      attributes: {
        appVersionState: 'READY_FOR_DISTRIBUTION',
        versionString: '2.0.0',
      },
    },
  ]), false);
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-2-1-0', '2.1.0', live),
    {
      type: 'appStoreVersions',
      id: 'asc-version-2-0-0',
      attributes: {
        appVersionState: 'READY_FOR_DISTRIBUTION',
        platform: 'MAC_OS',
        versionString: '2.0.0',
      },
    },
  ]), false);
  for (const appVersionState of [
    'WAITING_FOR_REVIEW',
    'IN_REVIEW',
    'PREPARE_FOR_SUBMISSION',
    'DEVELOPER_REJECTED',
  ]) {
    assert.equal(canCreateNewAppStoreVersion([
      ...realReleasedHistory(),
      releasedIosVersion('asc-version-next', '3.0.0', { appVersionState }),
    ]), false);
  }
  assert.equal(canCreateNewAppStoreVersion([
    ...realReleasedHistory(),
    {
      type: 'appStoreVersions',
      id: 'asc-version-unknown',
      attributes: { platform: 'IOS', versionString: '1.0.0' },
    },
  ]), false);
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-2-1-0', '2.1.0', live),
    {
      type: 'appStoreVersions',
      id: 'asc-version-unknown',
      attributes: { platform: 'IOS', versionString: '2.0.0' },
    },
  ]), false);
  assert.equal(canCreateNewAppStoreVersion([
    releasedIosVersion('asc-version-2-1-0', '2.1.0', {
      appVersionState: 'REPLACED_WITH_NEW_VERSION',
    }),
    releasedIosVersion('asc-version-2-0-0', '2.0.0', {
      appVersionState: 'REPLACED_WITH_NEW_VERSION',
    }),
  ]), false);
});

test('remote audit creates from released-only 2.1.0/2.0.0 history regardless of order', async () => {
  const payload = minimalReleasePayload();
  const history = realReleasedHistory();
  for (const allVersions of [history, [...history].reverse()]) {
    const audit = await auditAppStoreConnectRelease({
      payload,
      client: versionAuditClient({ allVersions }),
    });
    const createEntry = audit.plan.find((entry) => (
      entry.target === 'appStoreVersion' && entry.action === 'create'
    ));
    assert.deepEqual(createEntry.desired, {
      copyright: payload.release.copyright,
      platform: 'IOS',
      versionString: payload.release.version,
      releaseType: APP_STORE_VERSION_RELEASE_TYPE,
    });
    assert.equal(audit.plan.some((entry) => (
      entry.code === 'ASC_APP_STORE_VERSION_CREATE_UNSAFE'
    )), false);
    assert.equal(audit.remote.versionId, null);
  }
});

test('remote audit keeps competing/duplicate/unidentified released history unresolved', async () => {
  const payload = minimalReleasePayload();
  const live = { appVersionState: 'READY_FOR_DISTRIBUTION' };
  const histories = {
    'duplicate versionString': [
      releasedIosVersion('asc-version-a', '2.1.0', live),
      releasedIosVersion('asc-version-b', '2.1.0', live),
    ],
    'duplicate id': [
      releasedIosVersion('asc-version-same', '2.1.0', live),
      releasedIosVersion('asc-version-same', '2.0.0', live),
    ],
    'missing identity evidence': [
      resource('live-a', { appVersionState: 'READY_FOR_DISTRIBUTION' }),
      resource('live-b', { appVersionState: 'READY_FOR_DISTRIBUTION' }),
    ],
    'missing platform': [
      releasedIosVersion('asc-version-2-1-0', '2.1.0', live),
      {
        type: 'appStoreVersions',
        id: 'asc-version-2-0-0',
        attributes: {
          appVersionState: 'READY_FOR_DISTRIBUTION',
          versionString: '2.0.0',
        },
      },
    ],
    'malformed versionString': [
      releasedIosVersion('asc-version-2-1-0', '2.1.0', live),
      releasedIosVersion('asc-version-2-0-0', '2.1.0-beta', live),
    ],
    'competing waiting version': [
      ...realReleasedHistory(),
      releasedIosVersion('asc-version-next', '3.0.0', {
        appVersionState: 'WAITING_FOR_REVIEW',
      }),
    ],
    'competing in-review version': [
      ...realReleasedHistory(),
      releasedIosVersion('asc-version-next', '3.0.0', {
        appVersionState: 'IN_REVIEW',
      }),
    ],
    'unknown state': [
      ...realReleasedHistory(),
      {
        type: 'appStoreVersions',
        id: 'asc-version-unknown',
        attributes: { platform: 'IOS', versionString: '1.0.0' },
      },
    ],
  };
  for (const [label, allVersions] of Object.entries(histories)) {
    const audit = await auditAppStoreConnectRelease({
      payload,
      client: versionAuditClient({ allVersions }),
    });
    assert.equal(audit.plan.some((entry) => (
      entry.code === 'ASC_APP_STORE_VERSION_CREATE_UNSAFE'
      && entry.action === 'unresolved'
    )), true, label);
    assert.equal(audit.plan.some((entry) => (
      entry.target === 'appStoreVersion' && entry.action === 'create'
    )), false, label);
  }
});

test('remote audit still adopts the single pre-release beside released history', async () => {
  const payload = minimalReleasePayload();
  const audit = await auditAppStoreConnectRelease({
    payload,
    client: versionAuditClient({
      allVersions: [
        ...realReleasedHistory(),
        releasedIosVersion('asc-version-draft', '3.0.0', {
          appVersionState: 'PREPARE_FOR_SUBMISSION',
        }),
      ],
    }),
  });
  assert.equal(audit.remote.versionId, 'asc-version-draft');
  assert.equal(audit.remote.versionState, 'PREPARE_FOR_SUBMISSION');
  assert.equal(audit.plan.some((entry) => (
    entry.target === 'appStoreVersion' && entry.action === 'update'
  )), true);
  assert.equal(audit.plan.some((entry) => (
    entry.target === 'appStoreVersion' && entry.action === 'create'
  )), false);
  assert.equal(audit.plan.some((entry) => (
    entry.code === 'ASC_APP_STORE_VERSION_CREATE_UNSAFE'
    || entry.code === 'ASC_APP_STORE_VERSION_ADOPTION_AMBIGUOUS'
  )), false);
});

test('DEVELOPER_REJECTED iOS version updates versionString/copyright on the same ID', async () => {
  const payload = minimalReleasePayload();
  const client = versionAuditClient({
    allVersions: [resource('rejected-version', {
      appVersionState: 'DEVELOPER_REJECTED',
      copyright: '2025 Hyo Jang',
      platform: 'IOS',
      versionString: '1.0.0',
    })],
  });
  const audit = await auditAppStoreConnectRelease({ payload, client });
  const entry = audit.plan.find((candidate) => (
    candidate.target === 'appStoreVersion'
  ));
  assert.equal(audit.remote.versionId, 'rejected-version');
  assert.equal(audit.remote.versionState, 'DEVELOPER_REJECTED');
  assert.equal(entry.action, 'update');
  assert.equal(entry.remoteId, 'rejected-version');
  assert.deepEqual(entry.changes, {
    versionString: { current: '1.0.0', desired: '1.0.1' },
    copyright: { current: '2025 Hyo Jang', desired: '2026 Hyo Jang' },
    releaseType: { current: null, desired: APP_STORE_VERSION_RELEASE_TYPE },
  });
  assert.equal(audit.plan.some((candidate) => (
    candidate.target === 'appStoreVersion' && candidate.action === 'create'
  )), false);
  const versionQueries = client.paths.filter((path) => (
    path.includes('/appStoreVersions?')
  ));
  assert.equal(versionQueries.length, 2);
  assert.match(versionQueries[0], /filter%5BversionString%5D=1\.0\.1/u);
  assert.doesNotMatch(versionQueries[1], /filter%5BversionString%5D/u);

  const patches = [];
  await applyPlanEntry({
    client: {
      async patch(path, body) {
        patches.push({ body, path });
      },
    },
    entry,
    payload,
  });
  assert.equal(patches[0].path, '/v1/appStoreVersions/rejected-version');
  assert.deepEqual(patches[0].body.data.attributes, {
    copyright: '2026 Hyo Jang',
    versionString: '1.0.1',
    releaseType: APP_STORE_VERSION_RELEASE_TYPE,
  });
  assert.equal(Object.hasOwn(patches[0].body.data.attributes, 'platform'), false);
  await assert.rejects(applyPlanEntry({
    client: { async patch() { assert.fail('unsafe PATCH must not run'); } },
    entry: {
      action: 'update',
      changes: { platform: { current: 'IOS', desired: 'IOS' } },
      remoteId: 'rejected-version',
      target: 'appStoreVersion',
    },
    payload,
  }), /ASC_APP_STORE_VERSION_PLATFORM_IMMUTABLE/u);
});

test('version selection prefers exact lookup and does not create when ambiguous/active', async () => {
  const payload = minimalReleasePayload();
  const exactClient = versionAuditClient({
    exactVersions: [resource('exact-version', {
      appVersionState: 'PREPARE_FOR_SUBMISSION',
      copyright: payload.release.copyright,
      platform: 'IOS',
      versionString: payload.release.version,
    })],
  });
  await auditAppStoreConnectRelease({ payload, client: exactClient });
  assert.equal(
    exactClient.paths.filter((path) => path.includes('/appStoreVersions?')).length,
    1,
  );

  const unsafeAudit = await auditAppStoreConnectRelease({
    payload,
    client: versionAuditClient({
      allVersions: [resource('waiting-version', {
        appVersionState: 'WAITING_FOR_REVIEW',
        platform: 'IOS',
        versionString: '1.0.0',
      })],
    }),
  });
  assert.ok(unsafeAudit.plan.some((entry) => (
    entry.code === 'ASC_APP_STORE_VERSION_CREATE_UNSAFE'
    && entry.action === 'unresolved'
  )));
  assert.equal(unsafeAudit.plan.some((entry) => (
    entry.target === 'appStoreVersion' && entry.action === 'create'
  )), false);

  const exactActiveAudit = await auditAppStoreConnectRelease({
    payload,
    client: versionAuditClient({
      exactVersions: [resource('exact-active-version', {
        appVersionState: 'WAITING_FOR_REVIEW',
        platform: 'IOS',
        versionString: payload.release.version,
      })],
    }),
  });
  assert.ok(exactActiveAudit.plan.some((entry) => (
    entry.code === 'ASC_APP_STORE_VERSION_NOT_ADOPTABLE'
    && entry.action === 'unresolved'
  )));
  assert.equal(exactActiveAudit.plan.some((entry) => (
    entry.target === 'appStoreVersion'
    && ['create', 'update'].includes(entry.action)
  )), false);

  const ambiguousAudit = await auditAppStoreConnectRelease({
    payload,
    client: versionAuditClient({
      allVersions: [
        resource('draft-a', {
          appVersionState: 'PREPARE_FOR_SUBMISSION',
          versionString: '1.0.0',
        }),
        resource('draft-b', {
          appVersionState: 'DEVELOPER_REJECTED',
          versionString: '0.9.9',
        }),
      ],
    }),
  });
  assert.ok(ambiguousAudit.plan.some((entry) => (
    entry.code === 'ASC_APP_STORE_VERSION_ADOPTION_AMBIGUOUS'
  )));

  for (const allVersions of [
    [],
    [resource('live-version', {
      appStoreState: 'READY_FOR_SALE',
      platform: 'IOS',
      versionString: '1.0.0',
    })],
  ]) {
    const createAudit = await auditAppStoreConnectRelease({
      payload,
      client: versionAuditClient({ allVersions }),
    });
    const createEntry = createAudit.plan.find((entry) => (
      entry.target === 'appStoreVersion' && entry.action === 'create'
    ));
    assert.deepEqual(createEntry.desired, {
      copyright: payload.release.copyright,
      platform: 'IOS',
      versionString: payload.release.version,
      releaseType: APP_STORE_VERSION_RELEASE_TYPE,
    });
  }
});

test('App Review Detail converges notes only on readback without exposing contact/demo fields', async () => {
  const payload = minimalReleasePayload();
  let remoteNotes = 'remote-secret-password-marker';
  const reviewDetail = () => resource('review-detail-existing', {
    contactEmail: 'sensitive-contact@example.invalid',
    contactFirstName: 'Sensitive',
    contactLastName: 'Contact',
    contactPhone: '+10000000000',
    demoAccountName: 'sensitive-demo',
    demoAccountPassword: 'sensitive-password',
    demoAccountRequired: false,
    notes: remoteNotes,
  });
  const options = {
    exactVersions: [resource('exact-version', {
      appVersionState: 'DEVELOPER_REJECTED',
      copyright: payload.release.copyright,
      platform: 'IOS',
      versionString: payload.release.version,
    })],
    reviewDetail,
  };
  const firstClient = versionAuditClient(options);
  const first = await auditAppStoreConnectRelease({
    payload,
    client: firstClient,
  });
  const entry = first.plan.find((candidate) => (
    candidate.target === 'appStoreReviewDetail'
  ));
  assert.equal(entry.action, 'update');
  assert.deepEqual(entry.desired, { notes: payload.appStoreReview.notes });
  const reviewGetPath = firstClient.paths.find((path) => (
    path.includes('/appStoreReviewDetail?')
  ));
  assert.match(reviewGetPath, /fields%5BappStoreReviewDetails%5D=notes/u);
  assert.doesNotMatch(reviewGetPath, /contact|demoAccount/u);
  const serialized = canonicalJson(first);
  for (const sensitive of [
    'sensitive-contact@example.invalid',
    '+10000000000',
    'sensitive-demo',
    'sensitive-password',
    'remote-secret-password-marker',
  ]) {
    assert.equal(serialized.includes(sensitive), false);
  }
  let patch = null;
  await applyPlanEntry({
    client: {
      async patch(path, body) {
        patch = { body, path };
        remoteNotes = body.data.attributes.notes;
      },
    },
    entry,
    payload,
  });
  assert.equal(
    patch.path,
    '/v1/appStoreReviewDetails/review-detail-existing',
  );
  assert.deepEqual(patch.body.data.attributes, {
    notes: payload.appStoreReview.notes,
  });
  await assert.rejects(applyPlanEntry({
    client: { async patch() { assert.fail('unsafe review PATCH must not run'); } },
    entry: {
      action: 'update',
      desired: {
        contactEmail: 'must-not-change@example.invalid',
        notes: payload.appStoreReview.notes,
      },
      remoteId: 'review-detail-existing',
      target: 'appStoreReviewDetail',
    },
    payload,
  }), /ASC_APP_STORE_REVIEW_DETAIL_PATCH_UNSAFE/u);
  await assert.rejects(applyPlanEntry({
    client: { async post() { assert.fail('unsafe review POST must not run'); } },
    entry: {
      action: 'create',
      desired: { notes: payload.appStoreReview.notes },
      target: 'appStoreReviewDetail',
    },
    payload,
  }), /ASC_APP_STORE_REVIEW_DETAIL_CREATE_UNSAFE/u);
  const second = await auditAppStoreConnectRelease({
    payload,
    client: versionAuditClient(options),
  });
  assert.ok(second.plan.some((candidate) => (
    candidate.target === 'appStoreReviewDetail'
    && candidate.remoteId === 'review-detail-existing'
    && candidate.action === 'none'
  )));

  const missing = await auditAppStoreConnectRelease({
    payload,
    client: versionAuditClient({ ...options, reviewDetail: null }),
  });
  assert.ok(missing.plan.some((candidate) => (
    candidate.code === 'ASC_APP_STORE_REVIEW_DETAIL_MISSING'
    && candidate.action === 'unresolved'
    && candidate.remoteMutationPlanned === false
  )));
});

test('remote audit plans app-info/version locale pairs and asset replacement GET-only', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root);
    const appByLocale = Object.fromEntries(
      payload.appLocalizations.map((entry) => [entry.locale, entry]),
    );
    const productOne = payload.inAppPurchases.products[0];
    const productThree = payload.inAppPurchases.products[2];
    const remoteAppInfos = [
      resource('info-en', {
        locale: 'en-US',
        name: appByLocale['en-US'].appInfo.name,
        subtitle: appByLocale['en-US'].appInfo.subtitle,
      }),
      resource('info-ko', {
        locale: 'ko',
        name: appByLocale.ko.appInfo.name,
        subtitle: 'old subtitle',
      }),
    ];
    const remoteVersions = [
      resource('version-en', {
        locale: 'en-US',
        ...appByLocale['en-US'].version,
      }),
      resource('version-ko', {
        locale: 'ko',
        ...appByLocale.ko.version,
        description: 'old description',
        whatsNew: 'old release notes',
      }),
    ];

    const router = async (url, options) => {
      assert.equal(options.method, 'GET');
      const pathname = new URL(url).pathname;
      if (pathname === '/v1/apps/6796293839') {
        return jsonResponse({
          data: resource('6796293839', {
            bundleId: payload.release.bundleId,
          }),
        });
      }
      if (pathname === '/v1/apps/6796293839/appStoreVersions') {
        return jsonResponse({
          data: [resource('version-1', {
            versionString: '1.0.0',
            platform: 'IOS',
            appStoreState: 'PREPARE_FOR_SUBMISSION',
          })],
        });
      }
      if (pathname === '/v1/apps/6796293839/appInfos') {
        return jsonResponse({ data: [resource('app-info-1', {})] });
      }
      if (
        pathname
        === '/v1/appInfos/app-info-1/appInfoLocalizations'
      ) {
        return jsonResponse({ data: remoteAppInfos });
      }
      if (
        pathname
        === '/v1/appStoreVersions/version-1/appStoreVersionLocalizations'
      ) {
        return jsonResponse({ data: remoteVersions });
      }
      if (
        pathname
        === '/v1/appStoreVersions/version-1/appStoreReviewDetail'
      ) {
        return jsonResponse({
          data: resource('review-detail-1', {
            contactEmail: 'reviewer-contact@example.invalid',
            contactFirstName: 'Private',
            contactLastName: 'Contact',
            contactPhone: '+10000000000',
            demoAccountName: 'private-demo-name',
            demoAccountPassword: 'private-demo-password',
            demoAccountRequired: false,
            notes: 'old three-product review instructions',
          }),
        });
      }
      if (
        pathname
        === '/v1/appStoreVersionLocalizations/version-en/appScreenshotSets'
      ) {
        return jsonResponse({
          data: [
            resource('set-en-phone', {
              screenshotDisplayType: 'APP_IPHONE_65',
            }),
            resource('set-en-pad', {
              screenshotDisplayType: 'APP_IPAD_PRO_3GEN_129',
            }),
          ],
        });
      }
      if (
        pathname
        === '/v1/appStoreVersionLocalizations/version-ko/appScreenshotSets'
      ) {
        return jsonResponse({
          data: [
            resource('set-ko-phone', {
              screenshotDisplayType: 'APP_IPHONE_65',
            }),
          ],
        });
      }
      if (pathname === '/v1/appScreenshotSets/set-en-phone/appScreenshots') {
        return jsonResponse({
          data: appByLocale['en-US'].screenshots[0].files.map(
            (file, index) => resource(`en-phone-${index}`, {
              fileName: file.fileName,
              fileSize: file.size,
              sourceFileChecksum: file.md5,
              assetDeliveryState: { state: 'COMPLETE' },
            }),
          ),
        });
      }
      if (pathname === '/v1/appScreenshotSets/set-en-pad/appScreenshots') {
        return jsonResponse({
          data: appByLocale['en-US'].screenshots[1].files.map(
            (file, index) => resource(`en-pad-${index}`, {
              fileName: file.fileName,
              fileSize: file.size,
              sourceFileChecksum: index === 0
                ? '00000000000000000000000000000000'
                : file.md5,
              assetDeliveryState: { state: 'COMPLETE' },
            }),
          ),
        });
      }
      if (pathname === '/v1/appScreenshotSets/set-ko-phone/appScreenshots') {
        return jsonResponse({ data: [] });
      }
      if (pathname === '/v1/apps/6796293839/inAppPurchasesV2') {
        return jsonResponse({
          data: [
            resource('iap-one', {
              productId: productOne.productId,
              name: productOne.referenceName,
              inAppPurchaseType: productOne.type,
              reviewNote: productOne.reviewNote,
              state: 'READY_TO_SUBMIT',
            }),
            resource('iap-three', {
              productId: productThree.productId,
              name: productThree.referenceName,
              inAppPurchaseType: 'CONSUMABLE',
              reviewNote: productThree.reviewNote,
              state: 'READY_TO_SUBMIT',
            }),
          ],
        });
      }
      if (
        pathname
        === '/v2/inAppPurchases/iap-one/inAppPurchaseLocalizations'
      ) {
        return jsonResponse({
          data: [
            resource('iap-one-en', {
              locale: 'en-US',
              name: productOne.localizations[0].name,
              description: productOne.localizations[0].description,
            }),
          ],
        });
      }
      if (
        pathname
        === '/v2/inAppPurchases/iap-three/inAppPurchaseLocalizations'
      ) {
        return jsonResponse({
          data: [
            resource('iap-three-en', {
              locale: 'en-US',
              name: 'old name',
              description: 'old description',
            }),
          ],
        });
      }
      if (
        pathname
        === '/v2/inAppPurchases/iap-one/appStoreReviewScreenshot'
      ) {
        return jsonResponse(null, 404);
      }
      if (
        pathname
        === '/v2/inAppPurchases/iap-three/appStoreReviewScreenshot'
      ) {
        const image = productThree.reviewImage;
        return jsonResponse({
          data: resource('review-three', {
            fileName: image.fileName,
            fileSize: image.size,
            sourceFileChecksum: image.md5,
            assetDeliveryState: { state: 'COMPLETE' },
          }),
        });
      }
      throw new Error(`unexpected GET ${pathname}`);
    };
    const client = createGetOnlyAppStoreConnectClient({
      fetchImpl: router,
      token: 'test.jwt.value',
    });
    const audit = await auditAppStoreConnectRelease({ payload, client });
    assert.equal(audit.mode, 'GET_ONLY_REMOTE_AUDIT');
    assert.equal(audit.remoteMutationImplemented, false);
    assert.ok(audit.summary.create > 0);
    assert.ok(audit.summary.update > 0);
    assert.ok(audit.summary.replace > 0);
    assert.ok(audit.summary.none > 0);
    assert.equal(audit.summary.unresolved, 3);
    assert.ok(audit.plan.some((entry) => (
      entry.target === 'appStoreVersion'
      && entry.identifier === 'IOS/1.0.0'
      && entry.action === 'update'
      && entry.changes.copyright.desired === '2026 Hyo Jang'
    )));
    assert.ok(audit.plan.some((entry) => (
      entry.target === 'appInfoLocalization'
      && entry.identifier === 'ja'
      && entry.action === 'create'
      && !Object.hasOwn(entry.desired, 'privacyPolicyUrl')
      && entry.prerequisites.includes(
        'publicContactUrl:privacyPolicyUrl',
      )
    )));
    assert.ok(audit.plan.some((entry) => (
      entry.target === 'appStoreVersionLocalization'
      && entry.identifier === '1.0.0/ja'
      && entry.prerequisites.includes('appInfoLocalization:ja')
      && entry.desired.whatsNew === appByLocale.ja.version.whatsNew
      && !Object.hasOwn(entry.desired, 'supportUrl')
      && entry.prerequisites.includes('publicContactUrl:supportUrl')
    )));
    const versionLocalizationRequest = audit.requests.find((request) => (
      request.path.includes('/appStoreVersionLocalizations?')
    ));
    assert.match(
      decodeURIComponent(versionLocalizationRequest.path),
      /fields\[appStoreVersionLocalizations\]=locale,description,keywords,promotionalText,supportUrl,whatsNew/u,
    );
    const createVersionLocalization = audit.plan.find((entry) => (
      entry.target === 'appStoreVersionLocalization'
      && entry.identifier === '1.0.0/ja'
    ));
    let createdVersionLocalization = null;
    await applyPlanEntry({
      client: {
        async post(path, body) {
          createdVersionLocalization = { body, path };
        },
      },
      entry: createVersionLocalization,
      payload,
    });
    assert.equal(
      createdVersionLocalization.path,
      '/v1/appStoreVersionLocalizations',
    );
    assert.equal(
      createdVersionLocalization.body.data.attributes.whatsNew,
      appByLocale.ja.version.whatsNew,
    );
    const updateVersionLocalization = audit.plan.find((entry) => (
      entry.target === 'appStoreVersionLocalization'
      && entry.identifier === '1.0.0/ko'
    ));
    assert.equal(
      updateVersionLocalization.changes.whatsNew.desired,
      appByLocale.ko.version.whatsNew,
    );
    let updatedVersionLocalization = null;
    await applyPlanEntry({
      client: {
        async patch(path, body) {
          updatedVersionLocalization = { body, path };
        },
      },
      entry: updateVersionLocalization,
      payload,
    });
    assert.equal(
      updatedVersionLocalization.path,
      '/v1/appStoreVersionLocalizations/version-ko',
    );
    assert.equal(
      updatedVersionLocalization.body.data.attributes.whatsNew,
      appByLocale.ko.version.whatsNew,
    );
    assert.ok(audit.plan.some((entry) => (
      entry.target === 'appScreenshotSet'
      && entry.identifier === 'en-US/APP_IPAD_PRO_3GEN_129'
      && entry.action === 'replace'
      && /reservation.*PUT.*commit.*GET/u.test(entry.assetWorkflow)
    )));
    assert.ok(audit.plan.some((entry) => (
      entry.target === 'inAppPurchase'
      && entry.identifier === productThree.productId
      && entry.action === 'unresolved'
      && entry.code === 'IAP_TYPE_IMMUTABLE_NEW_PRODUCT_ID_REQUIRED'
      && entry.remoteMutationPlanned === false
    )));
    assert.equal(
      audit.plan.some((entry) => (
        entry.identifier.startsWith(`${productThree.productId}/`)
      )),
      false,
    );
    assert.deepEqual(
      audit.requests.map((request) => request.method),
      Array(audit.requests.length).fill('GET'),
    );
    assert.equal(
      canonicalJson(audit).includes('test.jwt.value'),
      false,
    );
    for (const sensitive of [
      'reviewer-contact@example.invalid',
      '+10000000000',
      'private-demo-name',
      'private-demo-password',
    ]) {
      assert.equal(canonicalJson(audit).includes(sensitive), false);
    }
  }));

test('remote audit requires App Apple ID to point at the local bundleId', async () => {
  const payload = {
    release: {
      appId: '6796293839',
      bundleId: 'com.crossplatformkorea.moonlitbeacon',
      version: '1.0.0',
    },
    contact: {
      status: 'resolved',
      gates: [],
    },
  };
  const client = {
    requests: [],
    async get(path) {
      assert.match(path, /^\/v1\/apps\/6796293839\?/u);
      return {
        data: resource('6796293839', {
          bundleId: 'com.example.anotherapp',
        }),
      };
    },
    async getAll() {
      assert.fail('must not fetch remote child resources after a bundleId mismatch');
    },
  };
  await assert.rejects(
    auditAppStoreConnectRelease({ payload, client }),
    /bundleId differs from the local release settings/u,
  );
});

test('remote apply confirmation token is bound to the current 2.1.0(9) manifest and review purpose', () =>
  withTempRoot((root) => {
    const payload = fixturePayload(root);
    payload.release.version = '2.1.0';
    payload.release.buildNumber = '9';
    const manifest = createAppStoreReleaseManifest(payload);
    const confirmation = appStoreConfirmationToken(manifest, 'apply');
    const reviewConfirmation = appStoreConfirmationToken(manifest, 'review');
    const changedLocalizationPayload = structuredClone(payload);
    changedLocalizationPayload.inAppPurchases.products.at(-1)
      .localizations.at(-1).description += ' changed';
    assert.notEqual(
      appStoreConfirmationToken(
        createAppStoreReleaseManifest(changedLocalizationPayload),
        'apply',
      ),
      confirmation,
    );
    assert.equal(assertAppStoreApplyAuthorization({
      confirmation,
      manifest,
      payload,
      reviewConfirmation,
      submitReview: true,
    }), true);
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation,
      manifest,
      payload: {
        ...payload,
        release: { ...payload.release, buildNumber: '2' },
      },
    }), /current metadata|manifest/u);
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation,
      manifest,
      payload,
      reviewConfirmation: confirmation,
      submitReview: true,
    }), /review-submission-only/u);
  }));

test('remote apply authorizes the current 3.0.0(10) manifest and a regenerated 3.0.0(11) payload', () =>
  withTempRoot((root) => {
    const payload10 = fixturePayload(root, { version: '3.0.0', build: '10' });
    assert.equal(payload10.release.version, '3.0.0');
    assert.equal(payload10.release.buildNumber, '10');
    const manifest10 = createAppStoreReleaseManifest(payload10);
    const confirmation10 = appStoreConfirmationToken(manifest10, 'apply');
    assert.equal(assertAppStoreApplyAuthorization({
      confirmation: confirmation10,
      manifest: manifest10,
      payload: payload10,
      reviewConfirmation: appStoreConfirmationToken(manifest10, 'review'),
      submitReview: true,
    }), true);

    // A new upload regenerates the payload from the edited export presets.
    writeFileSync(
      join(root, 'apps/game/export_presets.cfg'),
      fixtureExportPresets({ version: '3.0.0', build: '11' }),
    );
    const payload11 = buildAppStoreReleasePayload({ repoRoot: root });
    assert.equal(payload11.release.version, '3.0.0');
    assert.equal(payload11.release.buildNumber, '11');
    const manifest11 = createAppStoreReleaseManifest(payload11);
    const confirmation11 = appStoreConfirmationToken(manifest11, 'apply');
    assert.notEqual(confirmation11, confirmation10);
    assert.equal(assertAppStoreApplyAuthorization({
      confirmation: confirmation11,
      manifest: manifest11,
      payload: payload11,
      reviewConfirmation: appStoreConfirmationToken(manifest11, 'review'),
      submitReview: true,
    }), true);

    // The old build's token cannot authorize the new build, and a stale
    // payload no longer matches its manifest.
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation: confirmation10,
      manifest: manifest11,
      payload: payload11,
    }), /remote-apply token/u);
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation: confirmation11,
      manifest: manifest11,
      payload: payload10,
    }), /differs from current metadata/u);
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation: confirmation10,
      manifest: manifest10,
      payload: payload11,
    }), /differs from current metadata/u);
  }));

test('remote apply still rejects tampered, malformed, and mis-purposed current-release confirmations', () =>
  withTempRoot((root) => {
    const payload = fixturePayload(root, { version: '3.0.0', build: '11' });
    const manifest = createAppStoreReleaseManifest(payload);
    const confirmation = appStoreConfirmationToken(manifest, 'apply');
    const reviewConfirmation = appStoreConfirmationToken(manifest, 'review');

    const retargeted = structuredClone(manifest);
    retargeted.payload.release.buildNumber = '10';
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation,
      manifest: retargeted,
      payload,
    }), /sha256 verification/u);

    const editedCopy = structuredClone(manifest);
    editedCopy.payload.inAppPurchases.products[0]
      .localizations[0].description += ' tampered';
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation,
      manifest: editedCopy,
      payload,
    }), /sha256 verification/u);

    for (const mutate of [
      (release) => { release.buildNumber = ''; },
      (release) => { release.buildNumber = '11a'; },
      (release) => { release.version = '3.0.0.0.0'; },
      (release) => { release.appId = ''; },
      (release) => { release.bundleId = '   '; },
      (release) => { release.platform = 'ANDROID'; },
    ]) {
      const malformedPayload = structuredClone(payload);
      mutate(malformedPayload.release);
      const malformedManifest = createAppStoreReleaseManifest(malformedPayload);
      assert.throws(() => assertAppStoreApplyAuthorization({
        confirmation: appStoreConfirmationToken(malformedManifest, 'apply'),
        manifest: malformedManifest,
        payload: malformedPayload,
      }), /ASC_TARGET_RELEASE_MISMATCH/u);
    }
    // A missing release never reaches the target check: manifest
    // verification already rejects it at the availability gate.
    const missingPayload = structuredClone(payload);
    delete missingPayload.release;
    const missingManifest = createAppStoreReleaseManifest(missingPayload);
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation: 'app-store:apply:missing',
      manifest: missingManifest,
      payload: missingPayload,
    }), /availability-country gate/u);

    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation,
      manifest,
      payload,
      reviewConfirmation: confirmation,
      submitReview: true,
    }), /review-submission-only/u);
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation: reviewConfirmation,
      manifest,
      payload,
    }), /remote-apply token/u);
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation,
      manifest,
      payload,
      reviewConfirmation,
    }), /without submitting for review/u);
  }));

test('IAP prices read the 10 sale products manual base prices exactly and do not change them', async () => {
  const products = IAP_PRODUCT_IDS.map((productId, index) => ({
    productId,
    pricing: {
      strategy: 'VERIFY_EXISTING_MANUAL_BASE_PRICE',
      ...IAP_BASE_PRICES[productId],
    },
    remoteId: `iap-${index}`,
  }));
  const byRemoteId = new Map(products.map((product) => (
    [product.remoteId, product]
  )));
  let mismatchedProduct = null;
  const client = {
    async get(path) {
      const match = path.match(/inAppPurchasePriceSchedules\/([^/]+)\//u);
      const product = byRemoteId.get(decodeURIComponent(match[1]));
      if (path.includes('/baseTerritory?')) {
        return {
          data: resource(product.pricing.territory, {
            currency: product.pricing.currency,
          }),
        };
      }
      const pricePointId = `point-${product.remoteId}`;
      const customerPrice = product.productId === mismatchedProduct
        ? '999.99'
        : product.pricing.customerPrice;
      return {
        data: [{
          id: `price-${product.remoteId}`,
          type: 'inAppPurchasePrices',
          attributes: { endDate: null, manual: true, startDate: null },
          relationships: {
            inAppPurchasePricePoint: {
              data: { id: pricePointId, type: 'inAppPurchasePricePoints' },
            },
            territory: {
              data: { id: product.pricing.territory, type: 'territories' },
            },
          },
        }],
        included: [
          {
            id: pricePointId,
            type: 'inAppPurchasePricePoints',
            attributes: { customerPrice },
          },
          {
            id: product.pricing.territory,
            type: 'territories',
            attributes: { currency: product.pricing.currency },
          },
        ],
        links: {},
      };
    },
  };
  const payload = { inAppPurchases: { products } };
  const baseAudit = {
    plan: products.map((product) => ({
      action: 'none',
      identifier: product.productId,
      remoteId: product.remoteId,
      target: 'inAppPurchase',
    })),
  };
  const exact = await auditIapPricing(payload, client, baseAudit);
  assert.equal(exact.length, 10);
  assert.ok(exact.every((entry) => (
    entry.action === 'none' && entry.target === 'inAppPurchasePricing'
  )));
  mismatchedProduct = IAP_PRODUCT_IDS[1];
  const mismatch = await auditIapPricing(payload, client, baseAudit);
  assert.ok(mismatch.some((entry) => (
    entry.identifier === mismatchedProduct
    && entry.action === 'unresolved'
    && entry.code === 'ASC_IAP_PRICE_SCHEDULE_MISMATCH'
    && entry.remoteMutationPlanned === false
  )));
});

test('even with an APPROVED parent, preserves PREPARE IAP draft ID/state as the review target', async () => {
  const productId = IAP_PRODUCT_IDS[0];
  const result = await auditVersionedIapLocalizations({
    inAppPurchases: {
      products: [{ localizations: [], productId }],
    },
  }, {
    async getAll(path) {
      if (path.includes('/versions?')) {
        return [resource('draft-approved-parent', {
          state: 'PREPARE_FOR_SUBMISSION',
          version: '1',
        })];
      }
      assert.match(path, /inAppPurchaseVersions\/draft-approved-parent\/localizations/u);
      return [];
    },
  }, {
    plan: [{
      action: 'none',
      identifier: productId,
      remoteId: 'iap-approved-parent',
      remoteState: 'APPROVED',
      target: 'inAppPurchase',
    }],
  });
  assert.equal(result.versionIds[productId], 'draft-approved-parent');
  assert.equal(result.versionStates[productId], 'PREPARE_FOR_SUBMISSION');
});

test('DEVELOPER_REJECTED IAP version is reused when identical and creates the next when different', async () => {
  const products = [IAP_PRODUCT_IDS[0], IAP_PRODUCT_IDS[6]].map(
    (productId, index) => ({
      localizations: [{
        description: `Description ${index}`,
        locale: 'en-US',
        name: `Product ${index}`,
      }],
      productId,
    }),
  );
  const baseAudit = {
    plan: products.map((product, index) => ({
      action: 'none',
      identifier: product.productId,
      remoteId: `iap-${index}`,
      target: 'inAppPurchase',
    })),
  };
  const rejected = await auditVersionedIapLocalizations({
    inAppPurchases: { products },
  }, {
    async getAll(path) {
      const versionMatch = path.match(/inAppPurchases\/(iap-[01])\/versions/u);
      if (versionMatch) {
        return [resource(`version-${versionMatch[1]}`, {
          state: 'DEVELOPER_REJECTED',
          version: '1',
        })];
      }
      const localizationMatch = path.match(
        /inAppPurchaseVersions\/version-iap-([01])\/localizations/u,
      );
      const index = Number(localizationMatch?.[1]);
      assert.ok(Number.isInteger(index));
      return [resource(`localization-${index}`, {
        description: `Description ${index}`,
        locale: 'en-US',
        name: `Product ${index}`,
      })];
    },
  }, baseAudit);
  assert.equal(isReviewableIapVersionState('DEVELOPER_REJECTED'), true);
  assert.equal(isReviewableIapVersionState('WAITING_FOR_REVIEW'), false);
  assert.deepEqual(rejected.versionStates, {
    [IAP_PRODUCT_IDS[0]]: 'DEVELOPER_REJECTED',
    [IAP_PRODUCT_IDS[6]]: 'DEVELOPER_REJECTED',
  });
  assert.ok(rejected.plan.some((entry) => (
    entry.identifier === `${IAP_PRODUCT_IDS[0]}/en-US`
    && entry.action === 'none'
  )));
  assert.ok(rejected.plan.some((entry) => (
    entry.identifier === `${IAP_PRODUCT_IDS[6]}/en-US`
    && entry.action === 'none'
  )));

  const rejectedMismatch = await auditVersionedIapLocalizations({
    inAppPurchases: { products: [products[0]] },
  }, {
    async getAll(path) {
      if (path.includes('/versions?')) {
        return [resource('rejected-stale', {
          state: 'DEVELOPER_REJECTED',
          version: '1',
        })];
      }
      return [resource('rejected-stale-en', {
        description: 'old description',
        locale: 'en-US',
        name: products[0].localizations[0].name,
      })];
    },
  }, { plan: [baseAudit.plan[0]] });
  const createAfterRejected = rejectedMismatch.plan.find((entry) => (
    entry.target === 'inAppPurchaseVersion'
  ));
  assert.deepEqual(createAfterRejected, {
    action: 'create',
    capturesCurrentReviewImage: true,
    desired: { version: 2 },
    identifier: IAP_PRODUCT_IDS[0],
    localizationChanges: [{
      action: 'update',
      identifier: `${IAP_PRODUCT_IDS[0]}/en-US`,
    }],
    parentId: 'iap-0',
    prerequisites: [
      `inAppPurchase:${IAP_PRODUCT_IDS[0]}`,
      `inAppPurchaseReviewImage:${IAP_PRODUCT_IDS[0]}`,
    ],
    rejectedVersionId: 'rejected-stale',
    target: 'inAppPurchaseVersion',
  });
  assert.deepEqual(rejectedMismatch.versionIds, {});
  assert.deepEqual(rejectedMismatch.versionStates, {});
  assert.equal(rejectedMismatch.plan.some((entry) => (
    entry.action === 'unresolved'
  )), false);

  let versions = [resource('rejected-stale', {
    state: 'DEVELOPER_REJECTED',
    version: '1',
  })];
  let createCalls = 0;
  await applyPlanEntry({
    client: {
      async post(path, body) {
        createCalls += 1;
        assert.equal(path, '/v1/inAppPurchaseVersions');
        assert.equal(Object.hasOwn(body.data, 'attributes'), false);
        assert.equal(
          body.data.relationships.inAppPurchase.data.id,
          'iap-0',
        );
        const created = resource('draft-2', {
          state: 'PREPARE_FOR_SUBMISSION',
          version: 2,
        });
        versions = [...versions, created];
        return { data: created };
      },
    },
    entry: createAfterRejected,
    getClient: {
      async getAll(path) {
        assert.match(path, /inAppPurchases\/iap-0\/versions/u);
        return versions;
      },
    },
    payload: { inAppPurchases: { products: [products[0]] } },
  });
  assert.equal(createCalls, 1);

  const draftNeedsLocalization = await auditVersionedIapLocalizations({
    inAppPurchases: { products: [products[0]] },
  }, {
    async getAll(path) {
      if (path.includes('/versions?')) return versions;
      assert.match(path, /inAppPurchaseVersions\/draft-2\/localizations/u);
      return [];
    },
  }, { plan: [baseAudit.plan[0]] });
  assert.equal(
    draftNeedsLocalization.versionIds[IAP_PRODUCT_IDS[0]],
    'draft-2',
  );
  const newLocalization = draftNeedsLocalization.plan.find((entry) => (
    entry.target === 'inAppPurchaseVersionLocalization'
  ));
  assert.equal(newLocalization.action, 'create');
  assert.equal(newLocalization.parentId, 'draft-2');
  let localizationCreate = null;
  await applyPlanEntry({
    client: {
      async post(path, body) {
        localizationCreate = { body, path };
      },
    },
    entry: newLocalization,
    payload: { inAppPurchases: { products: [products[0]] } },
  });
  assert.equal(localizationCreate.path, '/v2/inAppPurchaseLocalizations');
  assert.equal(
    localizationCreate.body.data.relationships.version.data.id,
    'draft-2',
  );

  const convergedDraft = await auditVersionedIapLocalizations({
    inAppPurchases: { products: [products[0]] },
  }, {
    async getAll(path) {
      if (path.includes('/versions?')) return versions;
      return [resource('draft-2-en', {
        description: products[0].localizations[0].description,
        locale: 'en-US',
        name: products[0].localizations[0].name,
      })];
    },
  }, { plan: [baseAudit.plan[0]] });
  assert.equal(convergedDraft.plan[0].action, 'none');
  assert.equal(
    convergedDraft.versionIds[IAP_PRODUCT_IDS[0]],
    'draft-2',
  );

  const currentWins = await auditVersionedIapLocalizations({
    inAppPurchases: { products: [{ ...products[0], localizations: [] }] },
  }, {
    async getAll(path) {
      if (path.includes('/versions?')) {
        return [
          resource('rejected-history', { state: 'DEVELOPER_REJECTED' }),
          resource('current-draft', { state: 'PREPARE_FOR_SUBMISSION' }),
        ];
      }
      assert.match(path, /current-draft\/localizations/u);
      return [];
    },
  }, { plan: [baseAudit.plan[0]] });
  assert.equal(currentWins.versionIds[IAP_PRODUCT_IDS[0]], 'current-draft');

  const ambiguousRejected = await auditVersionedIapLocalizations({
    inAppPurchases: { products: [{ ...products[0], localizations: [] }] },
  }, {
    async getAll(path) {
      assert.match(path, /\/versions\?/u);
      return [
        resource('rejected-a', { state: 'DEVELOPER_REJECTED' }),
        resource('rejected-b', { state: 'DEVELOPER_REJECTED' }),
      ];
    },
  }, { plan: [baseAudit.plan[0]] });
  assert.ok(ambiguousRejected.plan.some((entry) => (
    entry.code === 'ASC_IAP_REJECTED_VERSION_AMBIGUOUS'
    && entry.action === 'unresolved'
  )));

  const unsupported = await auditVersionedIapLocalizations({
    inAppPurchases: { products: [products[0]] },
  }, {
    async getAll(path) {
      assert.match(path, /\/versions\?/u);
      return [resource('waiting-version', { state: 'WAITING_FOR_REVIEW' })];
    },
  }, { plan: [baseAudit.plan[0]] });
  assert.deepEqual(unsupported.versionIds, {});
  assert.ok(unsupported.plan.some((entry) => (
    entry.code === 'ASC_IAP_VERSION_STATE_UNSUPPORTED'
    && entry.action === 'unresolved'
  )));
});

test('7 localization diffs across 3 rejected Continue Coin products each plan a new version 2', async () => {
  const productIds = IAP_PRODUCT_IDS.slice(-3);
  const products = productIds.map((productId) => ({
    localizations: APPLE_LOCALES.map((locale) => ({
      description: `${productId.split('.').at(-1)} description ${locale}`,
      locale,
      name: `${productId.split('.').at(-1)} ${locale}`,
    })),
    productId,
  }));
  const remoteIdByProduct = Object.fromEntries(productIds.map(
    (productId, index) => [productId, `coin-${index}`],
  ));
  const productByRemoteId = Object.fromEntries(products.map((product) => (
    [remoteIdByProduct[product.productId], product]
  )));
  const baseAudit = {
    plan: products.map((product) => ({
      action: 'none',
      identifier: product.productId,
      remoteId: remoteIdByProduct[product.productId],
      target: 'inAppPurchase',
    })),
  };
  const result = await auditVersionedIapLocalizations({
    inAppPurchases: { products },
  }, {
    async getAll(path) {
      const versionMatch = path.match(/inAppPurchases\/(coin-[0-2])\/versions/u);
      if (versionMatch) {
        return [resource(`rejected-${versionMatch[1]}`, {
          state: 'DEVELOPER_REJECTED',
          version: '1',
        })];
      }
      const localizationMatch = path.match(
        /inAppPurchaseVersions\/rejected-(coin-[0-2])\/localizations/u,
      );
      const product = productByRemoteId[localizationMatch?.[1]];
      assert.ok(product);
      const desired = product.localizations;
      const remote = product.productId.endsWith('.continue_coin')
        ? desired
        : desired.slice(0, 2);
      return remote.map((localization, index) => resource(
        `${localizationMatch[1]}-${index}`,
        {
          ...localization,
          description: product.productId.endsWith('.continue_coin')
            && localization.locale === 'en-US'
            ? 'old English description'
            : localization.description,
        },
      ));
    },
  }, baseAudit);
  const creates = result.plan.filter((entry) => (
    entry.target === 'inAppPurchaseVersion'
    && entry.action === 'create'
  ));
  assert.equal(creates.length, 3);
  assert.ok(creates.every((entry) => (
    entry.desired.version === 2
    && entry.capturesCurrentReviewImage === true
    && entry.prerequisites.includes(
      `inAppPurchaseReviewImage:${entry.identifier}`,
    )
  )));
  assert.equal(
    creates.reduce(
      (sum, entry) => sum + entry.localizationChanges.length,
      0,
    ),
    7,
  );
  assert.deepEqual(result.versionIds, {});
  assert.deepEqual(result.versionStates, {});
  assert.equal(result.plan.some((entry) => (
    entry.action === 'unresolved'
  )), false);

  const drafts = await auditVersionedIapLocalizations({
    inAppPurchases: { products },
  }, {
    async getAll(path) {
      const versionMatch = path.match(/inAppPurchases\/(coin-[0-2])\/versions/u);
      if (versionMatch) {
        return [
          resource(`rejected-${versionMatch[1]}`, {
            state: 'DEVELOPER_REJECTED',
            version: 1,
          }),
          resource(`draft-${versionMatch[1]}`, {
            state: 'PREPARE_FOR_SUBMISSION',
            version: 2,
          }),
        ];
      }
      assert.match(path, /inAppPurchaseVersions\/draft-coin-[0-2]\/localizations/u);
      return [];
    },
  }, baseAudit);
  const localizationCreates = drafts.plan.filter((entry) => (
    entry.target === 'inAppPurchaseVersionLocalization'
    && entry.action === 'create'
  ));
  assert.equal(localizationCreates.length, 15);
  assert.ok(localizationCreates.every((entry) => (
    entry.parentId.startsWith('draft-coin-')
  )));
  assert.equal(new Set(localizationCreates.map((entry) => (
    entry.identifier.split('/').at(-1)
  ))).size, APPLE_LOCALES.length);
});

test('IAP new-version create blocks active-draft races, duplicate numbers, and readback mismatches', async () => {
  const productId = IAP_PRODUCT_IDS.at(-1);
  const entry = {
    action: 'create',
    desired: { version: 2 },
    identifier: productId,
    parentId: 'coin-remote',
    rejectedVersionId: 'rejected-1',
    target: 'inAppPurchaseVersion',
  };
  const rejected = resource('rejected-1', {
    state: 'DEVELOPER_REJECTED',
    version: '1',
  });
  let posts = 0;
  await assert.rejects(
    applyPlanEntry({
      client: { async post() { posts += 1; } },
      entry,
      getClient: {
        async getAll() {
          return [
            rejected,
            resource('draft-race', {
              state: 'PREPARE_FOR_SUBMISSION',
              version: 2,
            }),
          ];
        },
      },
      payload: { inAppPurchases: { products: [] } },
    }),
    /ASC_IAP_VERSION_CREATE_RACE/u,
  );
  assert.equal(posts, 0);

  await assert.rejects(
    applyPlanEntry({
      client: { async post() { posts += 1; } },
      entry,
      getClient: {
        async getAll() {
          return [
            rejected,
            resource('approved-duplicate', {
              state: 'APPROVED',
              version: '1',
            }),
          ];
        },
      },
      payload: { inAppPurchases: { products: [] } },
    }),
    /ASC_IAP_VERSION_NUMBER_DUPLICATE/u,
  );
  assert.equal(posts, 0);

  let readbacks = 0;
  await assert.rejects(
    applyPlanEntry({
      client: {
        async post() {
          posts += 1;
          return {
            data: resource('created-2', {
              state: 'PREPARE_FOR_SUBMISSION',
              version: '2',
            }),
          };
        },
      },
      entry,
      getClient: {
        async getAll() {
          readbacks += 1;
          return readbacks === 1
            ? [rejected]
            : [
              rejected,
              resource('created-2', {
                state: 'READY_FOR_REVIEW',
                version: 2,
              }),
            ];
        },
      },
      payload: { inAppPurchases: { products: [] } },
    }),
    /ASC_IAP_VERSION_CREATE_READBACK_FAILED/u,
  );
  assert.equal(posts, 1);
});

test('verifies mainland China exclusion, major-country inclusion, and internal TestFlight groups only', async () => {
  const territoryIds = ['CHN', 'KOR', 'USA', 'JPN', 'TWN'];
  let partialAvailability = false;
  const availabilityClient = {
    async get(path) {
      if (path.startsWith('/v1/territories?')) {
        return {
          data: territoryIds.map((territory) => resource(territory, {
            currency: territory === 'KOR' ? 'KRW' : 'USD',
          })),
          links: {},
          meta: { paging: { total: territoryIds.length } },
        };
      }
      if (path.includes('/appAvailabilityV2?')) {
        return {
          data: resource('6796293839', { availableInNewTerritories: true }),
        };
      }
      assert.match(path, /^\/v2\/appAvailabilities\/6796293839\/territoryAvailabilities\?/u);
      assert.match(path, /include=territory/u);
      const availableIds = partialAvailability
        ? territoryIds.slice(0, -1)
        : territoryIds;
      return {
        data: availableIds.map((territory) => ({
          ...resource(`availability-${territory}`, {
            available: territory !== 'CHN',
          }),
          relationships: {
            territory: { data: { id: territory, type: 'territories' } },
          },
        })),
        links: {},
        meta: { paging: { total: availableIds.length } },
      };
    },
  };
  const availability = await auditAppAvailability({
    release: {
      appId: '6796293839',
      availability: APP_AVAILABILITY_REQUIREMENTS,
    },
  }, availabilityClient);
  assert.equal(availability.action, 'none');
  assert.deepEqual(availability.verified.excludedTerritories, ['CHN']);
  partialAvailability = true;
  await assert.rejects(
    auditAppAvailability({
      release: {
        appId: '6796293839',
        availability: APP_AVAILABILITY_REQUIREMENTS,
      },
    }, availabilityClient),
    /ASC_APP_AVAILABILITY_INCOMPLETE/u,
  );
  partialAvailability = false;

  let external = false;
  const betaClient = {
    async getAll(path) {
      if (path.includes('/apps/')) {
        return [
          resource('internal-group', {
            isInternalGroup: true,
            name: 'Moonlit Beacon Internal',
          }),
          resource('external-group', {
            isInternalGroup: false,
            name: 'External',
          }),
        ];
      }
      assert.match(path, /^\/v1\/betaGroups\/(?:internal|external)-group\/builds\?/u);
      return external && path.includes('/external-group/')
        ? [resource('build-2', { version: '2' })]
        : [];
    },
  };
  const beta = await auditInternalBetaGroup({
    release: { appId: '6796293839' },
  }, betaClient, { buildId: 'build-2' });
  assert.deepEqual(beta, {
    action: 'update',
    buildId: 'build-2',
    identifier: 'Moonlit Beacon Internal',
    remoteId: 'internal-group',
    target: 'internalBetaGroupAssignment',
  });
  external = true;
  const blocked = await auditInternalBetaGroup({
    release: { appId: '6796293839' },
  }, betaClient, { buildId: 'build-2' });
  assert.equal(blocked.code, 'ASC_EXTERNAL_BETA_GROUP_PRESENT');
  assert.equal(blocked.remoteMutationPlanned, false);
});

test('mutation client uses only allowlisted ASC paths and rejects generic POST', async () => {
  const calls = [];
  const client = createAppStoreConnectMutationClient({
    fetchImpl: async (url, options) => {
      calls.push({ options, url: String(url) });
      return new Response(JSON.stringify({ data: resource('result', {}) }), {
        status: 200,
      });
    },
    token: 'test.jwt.value',
  });
  await client.post('/v1/betaGroups/internal/relationships/builds', {
    data: [{ id: 'build-2', type: 'builds' }],
  });
  await client.patch('/v1/appStoreReviewDetails/review-detail-1', {
    data: {
      attributes: { notes: 'verified notes only' },
      id: 'review-detail-1',
      type: 'appStoreReviewDetails',
    },
  });
  assert.equal(calls.length, 2);
  assert.equal(calls[0].options.method, 'POST');
  assert.equal(calls[1].options.method, 'PATCH');
  assert.match(calls[1].url, /\/v1\/appStoreReviewDetails\/review-detail-1$/u);
  await assert.rejects(
    client.post('/v1/apps', { data: {} }),
    /allowlist/u,
  );
  await assert.rejects(
    client.post('/v1/inAppPurchasePriceSchedules', { data: {} }),
    /allowlist/u,
  );
  await assert.rejects(
    client.uploadOperations([{
      length: 1,
      method: 'PUT',
      offset: 0,
      requestHeaders: [],
      url: 'https://example.com/stolen-upload',
    }], Buffer.from('x')),
    /blobstore/u,
  );
  assert.equal(calls.length, 2);
});

test('selects only the exact VALID 1.0.1(3) build as the version attachment target', async () => {
  let preReleasePlatform = 'IOS';
  const exactBuild = resource('build-3', {
    buildAudienceType: 'APP_STORE_ELIGIBLE',
    expired: false,
    processingState: 'VALID',
    version: '3',
  });
  exactBuild.relationships = {
    preReleaseVersion: {
      data: { id: 'pre-101-ios', type: 'preReleaseVersions' },
    },
  };
  const client = {
    async get(path) {
      if (path.startsWith('/v1/builds?')) {
        assert.match(path, /filter%5BpreReleaseVersion.version%5D=1.0.1/u);
        assert.match(path, /filter%5BpreReleaseVersion.platform%5D=IOS/u);
        return {
          data: [exactBuild],
          included: [resource('pre-101-ios', {
            platform: preReleasePlatform,
            version: '1.0.1',
          }, 'preReleaseVersions')],
          links: {},
        };
      }
      assert.match(path, /^\/v1\/appStoreVersions\/version-101\/build\?/u);
      return { data: exactBuild };
    },
  };
  const plan = await auditBuildAssociation({
    release: { appId: '6796293839', buildNumber: '3', version: '1.0.1' },
  }, client, { remote: { versionId: 'version-101' } });
  assert.equal(plan.action, 'none');
  assert.equal(plan.buildId, 'build-3');
  assert.equal(plan.remoteId, 'version-101');
  preReleasePlatform = 'MAC_OS';
  await assert.rejects(
    auditBuildAssociation({
      release: { appId: '6796293839', buildNumber: '3', version: '1.0.1' },
    }, client, { remote: { versionId: 'version-101' } }),
    /ASC_EXACT_BUILD_NOT_ELIGIBLE/u,
  );
  preReleasePlatform = 'IOS';
  exactBuild.attributes.buildAudienceType = 'INTERNAL_ONLY';
  await assert.rejects(
    auditBuildAssociation({
      release: { appId: '6796293839', buildNumber: '3', version: '1.0.1' },
    }, client, { remote: { versionId: 'version-101' } }),
    /ASC_EXACT_BUILD_NOT_ELIGIBLE/u,
  );
});

test('review submission GET-revalidates the app version and 10 IAPs excluding hero_bundle', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root);
    payload.release.version = '1.0.1';
    payload.release.buildNumber = '3';
    const manifest = createAppStoreReleaseManifest(payload);
    const iapVersionIds = Object.fromEntries(IAP_PRODUCT_IDS.map((productId, index) => (
      [productId, `iap-version-${index}`]
    )));
    const iapVersionStates = Object.fromEntries(IAP_PRODUCT_IDS.map((productId) => (
      [productId, [IAP_PRODUCT_IDS[0], IAP_PRODUCT_IDS[6]].includes(productId)
        ? 'DEVELOPER_REJECTED'
        : 'PREPARE_FOR_SUBMISSION']
    )));
    const audit = {
      appId: payload.release.appId,
      mode: 'GET_ONLY_REMOTE_APPLY_PREFLIGHT',
      plan: [
        ...IAP_PRODUCT_IDS.map((productId, index) => ({
          action: 'none',
          identifier: productId,
          remoteState: index === 0 ? 'APPROVED' : 'READY_TO_SUBMIT',
          target: 'inAppPurchase',
        })),
        {
          action: 'none',
          buildId: 'build-3',
          identifier: 'IOS/1.0.1(3)',
          target: 'buildAssociation',
        },
      ],
      remote: {
        iapVersionIds,
        iapVersionStates,
        versionId: 'version-101',
        versionReleaseType: APP_STORE_VERSION_RELEASE_TYPE,
      },
    };
    const items = [];
    const calls = [];
    const getClient = {
      async get(path) {
        if (path.includes('/reviewSubmissions/submission-1?')) {
          return {
            data: resource('submission-1', { state: 'WAITING_FOR_REVIEW' }),
          };
        }
        if (path.includes('/appStoreVersions/version-101/build?')) {
          return { data: resource('build-3', { version: '3' }) };
        }
        assert.fail(`unexpected GET: ${path}`);
      },
      async getAll(path) {
        if (path.includes('/reviewSubmissions?')) return [];
        if (path.includes('/reviewSubmissions/submission-1/items?')) {
          return items.map((item, index) => ({
            id: `item-${index}`,
            relationships: item.relationships,
          }));
        }
        assert.fail(`unexpected GET: ${path}`);
      },
    };
    const client = {
      async post(path, body) {
        calls.push({ body, method: 'POST', path });
        if (path === '/v1/reviewSubmissions') {
          return {
            data: resource('submission-1', { state: 'READY_FOR_REVIEW' }),
          };
        }
        items.push(body.data);
        return { data: resource(`item-${items.length}`, {}) };
      },
      async patch(path, body) {
        calls.push({ body, method: 'PATCH', path });
        return { data: resource('submission-1', { state: 'WAITING_FOR_REVIEW' }) };
      },
    };
    const result = await submitAppStoreConnectReview({
      audit,
      client,
      getClient,
      manifest,
      reviewConfirmation: appStoreConfirmationToken(manifest, 'review'),
    });
    assert.equal(result.submitted, true);
    assert.equal(result.buildId, 'build-3');
    assert.equal(result.reviewItemCount, IAP_PRODUCT_IDS.length + 1);
    assert.equal(items.length, IAP_PRODUCT_IDS.length + 1);
    assert.equal(canonicalJson(items).includes('hero_bundle'), false);
    assert.equal(calls.at(-1).method, 'PATCH');
    assert.deepEqual(calls.at(-1).body.data.attributes, { submitted: true });

    const incompleteAudit = structuredClone(audit);
    delete incompleteAudit.remote.iapVersionStates[IAP_PRODUCT_IDS[0]];
    await assert.rejects(
      submitAppStoreConnectReview({
        audit: incompleteAudit,
        client,
        getClient,
        manifest,
        reviewConfirmation: appStoreConfirmationToken(manifest, 'review'),
      }),
      /ASC_REVIEW_IAP_VERSION_SET_INVALID/u,
    );
  }));

test('review submission poll does not hide READY timeout or UNRESOLVED as success', async () => {
  let state = 'READY_FOR_REVIEW';
  let reads = 0;
  const getClient = {
    async get(path) {
      assert.match(path, /^\/v1\/reviewSubmissions\/submission-1\?/u);
      reads += 1;
      return { data: resource('submission-1', { state }) };
    },
  };
  await assert.rejects(
    pollAppStoreReviewSubmission({
      attempts: 2,
      delayMs: 0,
      getClient,
      sleepImpl: async () => {},
      submissionId: 'submission-1',
    }),
    /ASC_REVIEW_SUBMISSION_TIMEOUT/u,
  );
  assert.equal(reads, 2);
  state = 'UNRESOLVED_ISSUES';
  await assert.rejects(
    pollAppStoreReviewSubmission({
      attempts: 2,
      delayMs: 0,
      getClient,
      sleepImpl: async () => {},
      submissionId: 'submission-1',
    }),
    /ASC_REVIEW_UNRESOLVED_ISSUES/u,
  );
});

test('review submission completion readback rejects attached build ID mismatches', async () => {
  const expectedTargets = new Set(['appStoreVersions:version-101']);
  const getClient = {
    async get() {
      return { data: resource('wrong-build', { version: '9' }) };
    },
    async getAll() {
      return [{
        id: 'review-item-1',
        relationships: {
          appStoreVersion: {
            data: { id: 'version-101', type: 'appStoreVersions' },
          },
        },
      }];
    },
  };
  await assert.rejects(
    verifySubmittedRelease({
      audit: {
        plan: [{
          action: 'none',
          buildId: 'build-2',
          target: 'buildAssociation',
        }],
      },
      expectedTargets,
      getClient,
      submissionId: 'submission-1',
      versionId: 'version-101',
    }),
    /ASC_REVIEW_BUILD_NOT_VERIFIED/u,
  );
});

test('review submission items require the linkage include and keep the exact eleven-target guards', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root);
    payload.release.version = '1.0.1';
    payload.release.buildNumber = '3';
    const manifest = createAppStoreReleaseManifest(payload);
    assert.equal(IAP_PRODUCT_IDS.length, 10);
    const iapVersionIds = Object.fromEntries(IAP_PRODUCT_IDS.map((productId, index) => (
      [productId, `iap-version-${index}`]
    )));
    const iapVersionStates = Object.fromEntries(IAP_PRODUCT_IDS.map((productId) => (
      [productId, 'PREPARE_FOR_SUBMISSION']
    )));
    const audit = {
      appId: payload.release.appId,
      mode: 'GET_ONLY_REMOTE_APPLY_PREFLIGHT',
      plan: [
        ...IAP_PRODUCT_IDS.map((productId) => ({
          action: 'none',
          identifier: productId,
          remoteState: 'READY_TO_SUBMIT',
          target: 'inAppPurchase',
        })),
        {
          action: 'none',
          buildId: 'build-3',
          identifier: 'IOS/1.0.1(3)',
          target: 'buildAssociation',
        },
      ],
      remote: {
        iapVersionIds,
        iapVersionStates,
        versionId: 'version-101',
        versionReleaseType: APP_STORE_VERSION_RELEASE_TYPE,
      },
    };
    const reviewConfirmation = appStoreConfirmationToken(manifest, 'review');
    const expectedTargets = new Set([
      'appStoreVersions:version-101',
      ...IAP_PRODUCT_IDS.map((productId) => `inAppPurchaseVersions:${iapVersionIds[productId]}`),
    ]);
    assert.equal(expectedTargets.size, IAP_PRODUCT_IDS.length + 1);

    // Authoritative eleven-item target set, as returned with the linkage include.
    const linkedItems = [
      {
        attributes: { state: 'READY_FOR_REVIEW' },
        id: 'item-app',
        relationships: {
          appStoreVersion: { data: { id: 'version-101', type: 'appStoreVersions' } },
        },
        type: 'reviewSubmissionItems',
      },
      ...IAP_PRODUCT_IDS.map((productId, index) => ({
        attributes: { state: 'READY_FOR_REVIEW' },
        id: `item-iap-${index}`,
        relationships: {
          inAppPurchaseVersion: {
            data: { id: iapVersionIds[productId], type: 'inAppPurchaseVersions' },
          },
        },
        type: 'reviewSubmissionItems',
      })),
    ];
    // Real sparse-fields response shape without the include: ids/state only,
    // with no relationships at all.
    const sparseItems = linkedItems.map(({ attributes, id, type }) => ({
      attributes,
      id,
      type,
    }));

    const itemReads = [];
    function readItems(path, linked) {
      const url = new URL(path, 'https://example.invalid');
      itemReads.push(path);
      assert.equal(
        url.searchParams.get('fields[reviewSubmissionItems]'),
        'state,appStoreVersion,inAppPurchaseVersion',
      );
      assert.equal(url.searchParams.get('limit'), '200');
      if (url.searchParams.get('include') !== 'appStoreVersion,inAppPurchaseVersion') {
        return sparseItems.slice(0, linked.length);
      }
      return linked;
    }

    function statusGet(state) {
      return async (path) => {
        if (path.includes('/reviewSubmissions/submission-1?')) {
          return { data: resource('submission-1', { state }) };
        }
        if (path.includes('/appStoreVersions/version-101/build?')) {
          return { data: resource('build-3', { version: '3' }) };
        }
        assert.fail(`unexpected GET: ${path}`);
      };
    }

    // Normal submit: items start empty and each POSTed target re-reads linked.
    const posted = [];
    const submitGetClient = {
      get: statusGet('WAITING_FOR_REVIEW'),
      async getAll(path) {
        if (path.includes('/reviewSubmissions?')) return [];
        if (path.includes('/items?')) {
          return readItems(path, posted.map((entry, index) => ({
            attributes: { state: 'READY_FOR_REVIEW' },
            id: `item-${index}`,
            relationships: Object.fromEntries(Object.entries(entry.relationships)
              .filter(([name]) => name !== 'reviewSubmission')),
            type: 'reviewSubmissionItems',
          })));
        }
        assert.fail(`unexpected GET: ${path}`);
      },
    };
    const submitClient = {
      async post(path, body) {
        if (path === '/v1/reviewSubmissions') {
          return { data: resource('submission-1', { state: 'READY_FOR_REVIEW' }) };
        }
        posted.push(body.data);
        return { data: resource(`item-${posted.length}`, {}) };
      },
      async patch() {
        return { data: resource('submission-1', { state: 'WAITING_FOR_REVIEW' }) };
      },
    };
    const submitted = await submitAppStoreConnectReview({
      audit,
      client: submitClient,
      getClient: submitGetClient,
      manifest,
      reviewConfirmation,
    });
    assert.equal(submitted.submitted, true);
    assert.equal(submitted.idempotent, false);
    assert.equal(submitted.buildId, 'build-3');
    assert.equal(submitted.reviewItemCount, IAP_PRODUCT_IDS.length + 1);
    assert.equal(posted.length, IAP_PRODUCT_IDS.length + 1);
    assert.ok(itemReads.length >= 3);
    assert.ok(itemReads.every((path) => (
      new URL(path, 'https://example.invalid').searchParams.get('include')
        === 'appStoreVersion,inAppPurchaseVersion'
    )));

    // Submitted readback: an already-submitted eleven-item submission is idempotent.
    const idempotentGetClient = {
      get: statusGet('WAITING_FOR_REVIEW'),
      async getAll(path) {
        if (path.includes('/reviewSubmissions?')) {
          return [resource('submission-1', { platform: 'IOS', state: 'WAITING_FOR_REVIEW' })];
        }
        if (path.includes('/items?')) return readItems(path, linkedItems);
        assert.fail(`unexpected GET: ${path}`);
      },
    };
    const idempotent = await submitAppStoreConnectReview({
      audit,
      client: { async post() { assert.fail('idempotent readback must not mutate'); } },
      getClient: idempotentGetClient,
      manifest,
      reviewConfirmation,
    });
    assert.deepEqual(
      { id: idempotent.id, idempotent: idempotent.idempotent, submitted: idempotent.submitted },
      { id: 'submission-1', idempotent: true, submitted: true },
    );

    // The sparse-fields shape without linkage still fails closed at the unchanged guard.
    const sparseGetClient = {
      get: statusGet('READY_FOR_REVIEW'),
      async getAll(path) {
        if (path.includes('/reviewSubmissions?')) {
          return [resource('submission-1', { platform: 'IOS', state: 'READY_FOR_REVIEW' })];
        }
        if (path.includes('/items?')) return sparseItems;
        assert.fail(`unexpected GET: ${path}`);
      },
    };
    await assert.rejects(
      submitAppStoreConnectReview({
        audit,
        client: submitClient,
        getClient: sparseGetClient,
        manifest,
        reviewConfirmation,
      }),
      /ASC_REVIEW_SUBMISSION_ITEM_UNSUPPORTED/u,
    );

    // Unexpected, duplicated, and missing targets still fail closed.
    async function rejectsForItems(linked, code, { exact }) {
      const itemsGetClient = {
        get: statusGet('READY_FOR_REVIEW'),
        async getAll(path) {
          if (path.includes('/reviewSubmissions?')) {
            return [resource('submission-1', { platform: 'IOS', state: 'READY_FOR_REVIEW' })];
          }
          if (path.includes('/items?')) return readItems(path, linked);
          assert.fail(`unexpected GET: ${path}`);
        },
      };
      if (exact) {
        await assert.rejects(
          verifySubmittedRelease({
            audit,
            expectedTargets,
            getClient: itemsGetClient,
            submissionId: 'submission-1',
            versionId: 'version-101',
          }),
          code,
        );
        return;
      }
      await assert.rejects(
        submitAppStoreConnectReview({
          audit,
          client: submitClient,
          getClient: itemsGetClient,
          manifest,
          reviewConfirmation,
        }),
        code,
      );
    }
    await rejectsForItems([...linkedItems, {
      attributes: { state: 'READY_FOR_REVIEW' },
      id: 'item-extra',
      relationships: {
        inAppPurchaseVersion: {
          data: { id: 'iap-version-unknown', type: 'inAppPurchaseVersions' },
        },
      },
      type: 'reviewSubmissionItems',
    }], /ASC_REVIEW_SUBMISSION_HAS_UNEXPECTED_ITEMS/u, { exact: false });
    await rejectsForItems(
      [...linkedItems, linkedItems[0]],
      /ASC_REVIEW_SUBMISSION_ITEMS_DUPLICATE/u,
      { exact: false },
    );
    await rejectsForItems(
      linkedItems.slice(1),
      /ASC_REVIEW_ITEMS_NOT_VERIFIED/u,
      { exact: true },
    );
  }));

test('screenshot replacement deletes existing assets only after the new asset is COMPLETE', () =>
  withTempRoot(async (root) => {
    const contents = Buffer.from('verified screenshot bytes');
    const relativePath = 'builds/release/app-store/replacement.png';
    const path = join(root, relativePath);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, contents);
    const events = [];
    const artifact = {
      fileName: 'replacement.png',
      md5: createHash('md5').update(contents).digest('hex'),
      path: relativePath,
      sha256: createHash('sha256').update(contents).digest('hex'),
      size: contents.length,
    };
    const client = {
      async delete(pathname) {
        events.push(`delete:${pathname}`);
      },
      async patch(pathname) {
        events.push(`patch:${pathname}`);
      },
      async post(pathname) {
        events.push(`reserve:${pathname}`);
        return {
          data: resource('new-shot', {
            fileSize: contents.length,
            uploadOperations: [{
              length: contents.length,
              method: 'PUT',
              offset: 0,
              requestHeaders: [],
              url: 'https://upload.blobstore.apple.com/signed?secret=redacted',
            }],
          }),
        };
      },
      async uploadOperations(operations, bytes) {
        assert.equal(operations.length, 1);
        assert.deepEqual(bytes, contents);
        events.push('upload');
      },
    };
    const getClient = {
      async get() {
        events.push('complete');
        return {
          data: resource('new-shot', {
            assetDeliveryState: { state: 'COMPLETE' },
          }),
        };
      },
    };
    await uploadScreenshotSet({
      client,
      getClient,
      remoteFiles: [{
        assetDeliveryState: 'COMPLETE',
        fileName: 'old.png',
        fileSize: 3,
        id: 'old-shot',
        sourceFileChecksum: 'old',
      }],
      repoRoot: root,
      screenshotSet: { files: [artifact] },
      setId: 'set-1',
      sleepImpl: async () => {},
    });
    assert.ok(events.indexOf('complete') < events.indexOf(
      'delete:/v1/appScreenshots/old-shot',
    ));
    assert.equal(events.at(-1),
      'patch:/v1/appScreenshotSets/set-1/relationships/appScreenshots');
  }));

test('IAP review image replacement uploads the same verified Buffer before DELETE', () =>
  withTempRoot(async (root) => {
    const original = Buffer.from('original verified IAP review image');
    const changed = Buffer.from('changed after remote delete');
    const relativePath = 'builds/release/app-store/iap-review/frozen.png';
    const path = join(root, relativePath);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, original);
    const reviewImage = {
      fileName: 'frozen.png',
      md5: createHash('md5').update(original).digest('hex'),
      path: relativePath,
      sha256: createHash('sha256').update(original).digest('hex'),
      size: original.length,
    };
    let uploaded = null;
    const client = {
      async delete() {
        writeFileSync(path, changed);
      },
      async patch() {},
      async post() {
        return {
          data: resource('new-review-shot', {
            fileSize: original.length,
            uploadOperations: [{
              length: original.length,
              method: 'PUT',
              offset: 0,
              requestHeaders: [],
              url: 'https://upload.blobstore.apple.com/signed',
            }],
          }),
        };
      },
      async uploadOperations(operations, bytes) {
        assert.equal(operations.length, 1);
        uploaded = Buffer.from(bytes);
      },
    };
    const getClient = {
      async get() {
        return {
          data: resource('new-review-shot', {
            assetDeliveryState: { state: 'COMPLETE' },
          }),
        };
      },
    };
    await applyPlanEntry({
      client,
      entry: {
        action: 'replace',
        identifier: IAP_PRODUCT_IDS[0],
        parentId: 'iap-remote-0',
        remoteId: 'old-review-shot',
        target: 'inAppPurchaseReviewImage',
      },
      getClient,
      payload: {
        inAppPurchases: {
          products: [{ productId: IAP_PRODUCT_IDS[0], reviewImage }],
        },
      },
      repoRoot: root,
      sleepImpl: async () => {},
    });
    assert.deepEqual(uploaded, original);
    assert.notDeepEqual(readFileSync(path), original);
  }));

test('IAP review images still count as converged when Apple rewrites fileName to SOURCE', () => {
  const local = {
    fileName: 'hero-dancer.png',
    md5: 'b131b707bd7997bd223a98e8d5c65051',
    sha256: 'f'.repeat(64),
    size: 473947,
  };
  const converged = {
    attributes: {
      fileName: 'SOURCE',
      fileSize: 473947,
      sourceFileChecksum: 'B131B707BD7997BD223A98E8D5C65051',
      assetDeliveryState: { state: 'COMPLETE' },
    },
  };
  assert.equal(iapReviewImageMatches(local, converged), true);
  // Even if the name is SOURCE, different bytes still require replacement.
  const differentBytes = structuredClone(converged);
  differentBytes.attributes.sourceFileChecksum = 'a'.repeat(32);
  assert.equal(iapReviewImageMatches(local, differentBytes), false);
  // Still processing means not converged yet.
  const processing = structuredClone(converged);
  processing.attributes.assetDeliveryState = { state: 'PROCESSING' };
  assert.equal(iapReviewImageMatches(local, processing), false);
});

test('versioned apply preflight skips deprecated unscoped IAP audit for mixed APPROVED plus PREPARE history', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root, { version: '3.0.0', build: '11' });
    assert.equal(payload.release.version, '3.0.0');
    assert.equal(payload.release.buildNumber, '11');
    assert.equal(payload.inAppPurchases.products.length, 10);
    payload.contact = { status: 'resolved', gates: [] };

    const remoteIdByProduct = Object.fromEntries(IAP_PRODUCT_IDS.map(
      (productId, index) => [productId, `iap-remote-${index}`],
    ));
    const v1IdByProduct = Object.fromEntries(IAP_PRODUCT_IDS.map(
      (productId, index) => [productId, `iap-v1-${index}`],
    ));
    const v2IdByProduct = Object.fromEntries(IAP_PRODUCT_IDS.map(
      (productId, index) => [productId, `iap-v2-${index}`],
    ));
    const productById = Object.fromEntries(
      payload.inAppPurchases.products.map((product) => [product.productId, product]),
    );
    const productByRemoteId = Object.fromEntries(IAP_PRODUCT_IDS.map(
      (productId) => [remoteIdByProduct[productId], productId],
    ));
    const productByV1Id = Object.fromEntries(IAP_PRODUCT_IDS.map(
      (productId) => [v1IdByProduct[productId], productId],
    ));
    const productByV2Id = Object.fromEntries(IAP_PRODUCT_IDS.map(
      (productId) => [v2IdByProduct[productId], productId],
    ));
    const v1Ids = new Set(Object.values(v1IdByProduct));
    const v2Ids = new Set(Object.values(v2IdByProduct));

    function createMixedHistoryClient() {
      const requests = [];
      const unscopedPaths = [];
      const scopedV1Paths = [];
      const scopedV2Paths = [];
      const territoryIds = ['CHN', 'KOR', 'USA', 'JPN', 'TWN'];
      const buildId = 'build-300-11';
      const versionId = 'version-300';
      const exactBuild = {
        ...resource(buildId, {
          buildAudienceType: 'APP_STORE_ELIGIBLE',
          expired: false,
          processingState: 'VALID',
          version: '11',
        }, 'builds'),
        relationships: {
          preReleaseVersion: {
            data: { id: 'pre-300-ios', type: 'preReleaseVersions' },
          },
        },
      };

      function remoteIndex(remoteId) {
        const match = String(remoteId).match(/^iap-remote-(\d+)$/u);
        assert.ok(match);
        return Number(match[1]);
      }

      const client = {
        requests,
        async get(path) {
          requests.push({ method: 'GET', path });
          const pathname = new URL(path, 'https://example.invalid').pathname;
          if (pathname === '/v1/apps/6796293839') {
            return {
              data: resource('6796293839', {
                bundleId: payload.release.bundleId,
              }),
            };
          }
          if (pathname.endsWith('/appStoreReviewDetail')) {
            return {
              data: resource('review-detail-1', {
                notes: payload.appStoreReview.notes,
              }),
            };
          }
          if (pathname.includes('/appStoreReviewScreenshot')) {
            const match = path.match(/inAppPurchases\/([^/]+)\/appStoreReviewScreenshot/u);
            const productId = productByRemoteId[decodeURIComponent(match[1])];
            const image = productById[productId].reviewImage;
            return {
              data: resource(`review-${remoteIndex(match[1])}`, {
                assetDeliveryState: { state: 'COMPLETE' },
                fileName: image.fileName,
                fileSize: image.size,
                sourceFileChecksum: image.md5,
              }),
            };
          }
          if (pathname === '/v1/builds') {
            return {
              data: [exactBuild],
              included: [resource('pre-300-ios', {
                platform: 'IOS',
                version: '3.0.0',
              }, 'preReleaseVersions')],
              links: {},
            };
          }
          if (pathname === `/v1/appStoreVersions/${versionId}/build`) {
            return { data: exactBuild };
          }
          if (pathname.includes('/baseTerritory')) {
            const match = path.match(/inAppPurchasePriceSchedules\/([^/]+)\/baseTerritory/u);
            const productId = productByRemoteId[decodeURIComponent(match[1])];
            const expected = productById[productId].pricing;
            return {
              data: resource(expected.territory, {
                currency: expected.currency,
              }, 'territories'),
            };
          }
          if (pathname.includes('/manualPrices')) {
            const match = path.match(/inAppPurchasePriceSchedules\/([^/]+)\/manualPrices/u);
            const remoteId = decodeURIComponent(match[1]);
            const productId = productByRemoteId[remoteId];
            const expected = productById[productId].pricing;
            const pricePointId = `point-${remoteId}`;
            return {
              data: [{
                id: `price-${remoteId}`,
                type: 'inAppPurchasePrices',
                attributes: { endDate: null, manual: true, startDate: null },
                relationships: {
                  inAppPurchasePricePoint: {
                    data: { id: pricePointId, type: 'inAppPurchasePricePoints' },
                  },
                  territory: {
                    data: { id: expected.territory, type: 'territories' },
                  },
                },
              }],
              included: [
                {
                  id: pricePointId,
                  type: 'inAppPurchasePricePoints',
                  attributes: { customerPrice: expected.customerPrice },
                },
                {
                  id: expected.territory,
                  type: 'territories',
                  attributes: { currency: expected.currency },
                },
              ],
              links: {},
            };
          }
          if (pathname === '/v1/territories') {
            return {
              data: territoryIds.map((territory) => resource(territory, {
                currency: territory === 'KOR' ? 'KRW' : 'USD',
              }, 'territories')),
              links: {},
              meta: { paging: { total: territoryIds.length } },
            };
          }
          if (pathname.includes('/appAvailabilityV2')) {
            return {
              data: resource('avail-1', { availableInNewTerritories: true }),
            };
          }
          if (pathname.includes('/territoryAvailabilities')) {
            return {
              data: territoryIds.map((territory) => ({
                ...resource(`availability-${territory}`, {
                  available: territory !== 'CHN',
                }),
                relationships: {
                  territory: { data: { id: territory, type: 'territories' } },
                },
              })),
              links: {},
              meta: { paging: { total: territoryIds.length } },
            };
          }
          throw new Error(`unexpected GET ${path}`);
        },
        async getAll(path) {
          requests.push({ method: 'GET', path });
          if (path.includes('/appStoreVersions?')) {
            return [resource(versionId, {
              appStoreState: 'PREPARE_FOR_SUBMISSION',
              copyright: payload.release.copyright,
              platform: 'IOS',
              versionString: '3.0.0',
            })];
          }
          if (path.includes('/appInfos?')) {
            return [resource('app-info-1', {})];
          }
          if (
            path.includes('/appInfoLocalizations?')
            || path.includes('/appStoreVersionLocalizations?')
          ) {
            return [];
          }
          if (path.includes('/inAppPurchasesV2?')) {
            return IAP_PRODUCT_IDS.map((productId) => {
              const product = productById[productId];
              return resource(remoteIdByProduct[productId], {
                inAppPurchaseType: product.type,
                name: product.referenceName,
                productId,
                reviewNote: product.reviewNote,
                state: 'APPROVED',
              });
            });
          }
          if (
            path.includes('/inAppPurchases/')
            && path.includes('/inAppPurchaseLocalizations?')
          ) {
            unscopedPaths.push(path);
            const match = path.match(
              /inAppPurchases\/([^/]+)\/inAppPurchaseLocalizations/u,
            );
            const productId = productByRemoteId[decodeURIComponent(match[1])];
            const desired = productById[productId].localizations;
            return desired.flatMap((localization, localeIndex) => ([
              resource(`unscoped-${remoteIndex(match[1])}-${localeIndex}-approved`, {
                description: localization.description,
                locale: localization.locale,
                name: localization.name,
                state: 'APPROVED',
              }),
              resource(`unscoped-${remoteIndex(match[1])}-${localeIndex}-prepare`, {
                description: localization.description,
                locale: localization.locale,
                name: localization.name,
                state: 'PREPARE_FOR_SUBMISSION',
              }),
            ]));
          }
          if (
            path.includes('/inAppPurchases/')
            && path.includes('/versions?')
          ) {
            const match = path.match(/inAppPurchases\/([^/]+)\/versions/u);
            const productId = productByRemoteId[decodeURIComponent(match[1])];
            return [
              resource(v1IdByProduct[productId], {
                state: 'APPROVED',
                version: 1,
              }),
              resource(v2IdByProduct[productId], {
                state: 'PREPARE_FOR_SUBMISSION',
                version: 2,
              }),
            ];
          }
          if (
            path.includes('/inAppPurchaseVersions/')
            && path.includes('/localizations?')
          ) {
            const match = path.match(
              /inAppPurchaseVersions\/([^/]+)\/localizations/u,
            );
            const versionIdParam = decodeURIComponent(match[1]);
            if (productByV1Id[versionIdParam]) {
              scopedV1Paths.push(path);
              const desired = productById[productByV1Id[versionIdParam]].localizations;
              return desired.map((localization, localeIndex) => resource(
                `v1loc-${versionIdParam}-${localeIndex}`,
                { ...localization },
              ));
            }
            const productId = productByV2Id[versionIdParam];
            assert.ok(productId);
            scopedV2Paths.push(path);
            const desired = productById[productId].localizations;
            return desired.map((localization, localeIndex) => resource(
              `v2loc-${versionIdParam}-${localeIndex}`,
              {
                description: localization.description,
                locale: localization.locale,
                name: localization.name,
              },
            ));
          }
          if (path.includes('/apps/') && path.includes('/betaGroups?')) {
            return [
              resource('internal-group', {
                isInternalGroup: true,
                name: 'Moonlit Beacon Internal',
              }),
              resource('external-group', {
                isInternalGroup: false,
                name: 'External',
              }),
            ];
          }
          if (path.includes('/betaGroups/') && path.includes('/builds?')) {
            return path.includes('/internal-group/')
              ? [resource(buildId, { version: '11' })]
              : [];
          }
          throw new Error(`unexpected GET ALL ${path}`);
        },
      };
      return {
        client, requests, scopedV1Paths, scopedV2Paths, unscopedPaths,
      };
    }

    const mixed = createMixedHistoryClient();
    const audit = await auditAppStoreConnectApplyReadiness({
      client: mixed.client,
      payload,
    });
    assert.equal(audit.mode, 'GET_ONLY_REMOTE_APPLY_PREFLIGHT');
    assert.equal(audit.remote.versionId, 'version-300');
    assert.deepEqual(
      Object.keys(audit.remote.iapVersionIds).sort(),
      [...IAP_PRODUCT_IDS].sort(),
    );
    assert.deepEqual(audit.remote.iapVersionIds, v2IdByProduct);
    assert.ok(Object.values(audit.remote.iapVersionStates).every(
      (state) => state === 'PREPARE_FOR_SUBMISSION',
    ));
    assert.equal(new Set(Object.values(audit.remote.iapVersionIds)).size, 10);
    assert.equal(mixed.unscopedPaths.length, 0);
    assert.equal(
      mixed.requests.some((request) => request.path.includes('/inAppPurchaseLocalizations?')
        && request.path.includes('/v2/inAppPurchases/')),
      false,
    );
    assert.equal(mixed.scopedV1Paths.length, 0);
    assert.equal(mixed.scopedV2Paths.length, 10);
    assert.equal(
      audit.plan.some((entry) => entry.target === 'inAppPurchaseLocalization'),
      false,
    );
    const versionLocalizations = audit.plan.filter(
      (entry) => entry.target === 'inAppPurchaseVersionLocalization',
    );
    assert.equal(versionLocalizations.length, 50);
    assert.ok(versionLocalizations.every((entry) => entry.action === 'none'));
    assert.ok(versionLocalizations.every((entry) => v2Ids.has(entry.parentId)));
    assert.ok(versionLocalizations.every((entry) => !v1Ids.has(entry.parentId)));
    assert.ok(audit.plan.every((entry) => (
      !v1Ids.has(entry.parentId)
      && !v1Ids.has(entry.remoteId)
      && !v1Ids.has(entry.rejectedVersionId)
    )));
    assert.ok(Object.values(audit.remote.iapVersionIds).every(
      (id) => !v1Ids.has(id),
    ));
    const pricing = audit.plan.filter(
      (entry) => entry.target === 'inAppPurchasePricing',
    );
    assert.equal(pricing.length, 10);
    assert.ok(pricing.every((entry) => entry.action === 'none'));
    assert.equal(
      audit.plan.find((entry) => entry.target === 'appAvailability').action,
      'none',
    );
    assert.equal(
      audit.plan.find((entry) => entry.target === 'buildAssociation').action,
      'none',
    );
    assert.equal(
      audit.plan.find((entry) => entry.target === 'internalBetaGroupAssignment').action,
      'none',
    );

    const standalone = createMixedHistoryClient();
    await assert.rejects(
      auditAppStoreConnectRelease({ payload, client: standalone.client }),
      /localization is duplicated: en-US/u,
    );
    assert.ok(standalone.unscopedPaths.length > 0);

    const skipped = createMixedHistoryClient();
    const skippedAudit = await auditAppStoreConnectRelease({
      client: skipped.client,
      payload,
      skipUnscopedIapLocalizations: true,
    });
    assert.equal(skipped.unscopedPaths.length, 0);
    assert.equal(
      skippedAudit.plan.some((entry) => entry.target === 'inAppPurchaseLocalization'),
      false,
    );
  }));

test('chosen-draft duplicate locale still rejects in the version-scoped audit', async () => {
  const productId = 'com.crossplatformkorea.moonlitbeacon.continue_coin';
  const payload = {
    inAppPurchases: {
      products: [{
        localizations: [{
          description: 'Continue Coin description',
          locale: 'en-US',
          name: 'Continue Coin',
        }],
        productId,
      }],
    },
  };
  const baseAudit = {
    plan: [{
      action: 'none',
      identifier: productId,
      remoteId: 'iap-coin',
      remoteState: 'APPROVED',
      target: 'inAppPurchase',
    }],
  };
  await assert.rejects(
    auditVersionedIapLocalizations(payload, {
      async getAll(path) {
        if (path.includes('/versions?')) {
          return [
            resource('coin-v1', { state: 'APPROVED', version: 1 }),
            resource('coin-v2', { state: 'PREPARE_FOR_SUBMISSION', version: 2 }),
          ];
        }
        assert.match(path, /inAppPurchaseVersions\/coin-v2\/localizations/u);
        return [
          resource('coin-v2-en-a', {
            description: 'Continue Coin description',
            locale: 'en-US',
            name: 'Continue Coin',
          }),
          resource('coin-v2-en-b', {
            description: 'Continue Coin description',
            locale: 'en-US',
            name: 'Continue Coin',
          }),
        ];
      },
    }, baseAudit),
    /ASC_REMOTE_DUPLICATE/u,
  );
});

test('differing draft text still corrects when the approved text matches', async () => {
  const productId = 'com.crossplatformkorea.moonlitbeacon.continue_coin';
  const desired = {
    description: 'New Continue Coin description',
    locale: 'en-US',
    name: 'Continue Coin',
  };
  const payload = {
    inAppPurchases: {
      products: [{ localizations: [desired], productId }],
    },
  };
  const baseAudit = {
    plan: [{
      action: 'none',
      identifier: productId,
      remoteId: 'iap-coin',
      remoteState: 'APPROVED',
      target: 'inAppPurchase',
    }],
  };
  let approvedScopeFetches = 0;
  const result = await auditVersionedIapLocalizations(payload, {
    async getAll(path) {
      if (path.includes('/versions?')) {
        return [
          resource('coin-v1-approved', { state: 'APPROVED', version: 1 }),
          resource('coin-v2-draft', { state: 'PREPARE_FOR_SUBMISSION', version: 2 }),
        ];
      }
      if (path.includes('/inAppPurchaseVersions/coin-v1-approved/localizations')) {
        approvedScopeFetches += 1;
        return [resource('coin-v1-en', { ...desired })];
      }
      assert.match(path, /inAppPurchaseVersions\/coin-v2-draft\/localizations/u);
      return [resource('coin-v2-en', {
        description: 'Old approved-era description',
        locale: 'en-US',
        name: desired.name,
      })];
    },
  }, baseAudit);
  assert.equal(approvedScopeFetches, 0);
  assert.equal(result.versionIds[productId], 'coin-v2-draft');
  assert.equal(result.versionStates[productId], 'PREPARE_FOR_SUBMISSION');
  const entry = result.plan.find(
    (candidate) => candidate.identifier === `${productId}/en-US`,
  );
  assert.equal(entry.target, 'inAppPurchaseVersionLocalization');
  assert.equal(entry.action, 'update');
  assert.equal(entry.parentId, 'coin-v2-draft');
  assert.equal(entry.changes.description.desired, desired.description);
  assert.equal(entry.changes.description.current, 'Old approved-era description');
});

function reviewTransitionMaps(payload) {
  const appByLocale = Object.fromEntries(
    payload.appLocalizations.map((entry) => [entry.locale, entry]),
  );
  const productById = Object.fromEntries(
    payload.inAppPurchases.products.map((product) => [product.productId, product]),
  );
  const remoteIdByProduct = Object.fromEntries(IAP_PRODUCT_IDS.map(
    (productId, index) => [productId, `iap-remote-${index}`],
  ));
  const v1IdByProduct = Object.fromEntries(IAP_PRODUCT_IDS.map(
    (productId, index) => [productId, `iap-v1-${index}`],
  ));
  const v2IdByProduct = Object.fromEntries(IAP_PRODUCT_IDS.map(
    (productId, index) => [productId, `iap-v2-${index}`],
  ));
  const productByRemoteId = Object.fromEntries(IAP_PRODUCT_IDS.map(
    (productId) => [remoteIdByProduct[productId], productId],
  ));
  const productByV2Id = Object.fromEntries(IAP_PRODUCT_IDS.map(
    (productId) => [v2IdByProduct[productId], productId],
  ));
  return {
    appByLocale,
    productById,
    productByRemoteId,
    productByV2Id,
    remoteIdByProduct,
    v1IdByProduct,
    v2IdByProduct,
  };
}

function createReviewTransitionClient(payload, {
  versionState = 'PREPARE_FOR_SUBMISSION',
  appInfoState = null,
  iapDraftState = 'PREPARE_FOR_SUBMISSION',
  mismatchVersionLocale = null,
  mismatchScreenshot = false,
  mismatchBuild = false,
  appInfosOverride = null,
  exactVersionsOverride = null,
  allVersionsOverride = null,
} = {}) {
  const maps = reviewTransitionMaps(payload);
  const versionId = 'version-300';
  const appInfoCurrentId = 'app-info-current';
  const appInfoLiveId = 'app-info-live';
  const currentAppInfoState = appInfoState ?? versionState;
  const buildId = 'build-300-10';
  const requests = [];
  const appInfoFetches = [];
  const versionLocalizationFetches = [];

  function versionResource(id, state) {
    return resource(id, {
      appStoreState: state,
      appVersionState: state,
      copyright: payload.release.copyright,
      platform: 'IOS',
      versionString: payload.release.version,
      releaseType: APP_STORE_VERSION_RELEASE_TYPE,
    }, 'appStoreVersions');
  }

  const client = {
    appInfoFetches,
    requests,
    versionLocalizationFetches,
    async get(path) {
      requests.push({ method: 'GET', path });
      const pathname = new URL(path, 'https://example.invalid').pathname;
      if (pathname === `/v1/apps/${payload.release.appId}`) {
        return {
          data: resource(payload.release.appId, {
            bundleId: payload.release.bundleId,
          }),
        };
      }
      if (pathname.endsWith('/appStoreReviewDetail')) {
        return {
          data: resource('review-detail-1', {
            notes: payload.appStoreReview.notes,
          }),
        };
      }
      if (pathname.includes('/appStoreReviewScreenshot')) {
        const match = path.match(/inAppPurchases\/([^/]+)\/appStoreReviewScreenshot/u);
        const productId = maps.productByRemoteId[decodeURIComponent(match[1])];
        const image = maps.productById[productId].reviewImage;
        return {
          data: resource(`review-${match[1]}`, {
            assetDeliveryState: { state: 'COMPLETE' },
            fileName: image.fileName,
            fileSize: image.size,
            sourceFileChecksum: image.md5,
          }),
        };
      }
      if (pathname === '/v1/builds') {
        const exactBuild = {
          ...resource(buildId, {
            buildAudienceType: 'APP_STORE_ELIGIBLE',
            expired: false,
            processingState: 'VALID',
            version: payload.release.buildNumber,
          }, 'builds'),
          relationships: {
            preReleaseVersion: {
              data: { id: 'pre-300-ios', type: 'preReleaseVersions' },
            },
          },
        };
        return {
          data: [exactBuild],
          included: [resource('pre-300-ios', {
            platform: 'IOS',
            version: payload.release.version,
          }, 'preReleaseVersions')],
          links: {},
        };
      }
      if (pathname === `/v1/appStoreVersions/${versionId}/build`) {
        if (mismatchBuild) {
          return { data: resource('build-old', { version: '9' }) };
        }
        return { data: resource(buildId, { version: payload.release.buildNumber }) };
      }
      if (pathname.includes('/baseTerritory')) {
        const match = path.match(/inAppPurchasePriceSchedules\/([^/]+)\/baseTerritory/u);
        const productId = maps.productByRemoteId[decodeURIComponent(match[1])];
        const expected = maps.productById[productId].pricing;
        return {
          data: resource(expected.territory, {
            currency: expected.currency,
          }, 'territories'),
        };
      }
      if (pathname.includes('/manualPrices')) {
        const match = path.match(/inAppPurchasePriceSchedules\/([^/]+)\/manualPrices/u);
        const remoteId = decodeURIComponent(match[1]);
        const productId = maps.productByRemoteId[remoteId];
        const expected = maps.productById[productId].pricing;
        const pricePointId = `point-${remoteId}`;
        return {
          data: [{
            id: `price-${remoteId}`,
            type: 'inAppPurchasePrices',
            attributes: { endDate: null, manual: true, startDate: null },
            relationships: {
              inAppPurchasePricePoint: {
                data: { id: pricePointId, type: 'inAppPurchasePricePoints' },
              },
              territory: {
                data: { id: expected.territory, type: 'territories' },
              },
            },
          }],
          included: [
            {
              id: pricePointId,
              type: 'inAppPurchasePricePoints',
              attributes: { customerPrice: expected.customerPrice },
            },
            {
              id: expected.territory,
              type: 'territories',
              attributes: { currency: expected.currency },
            },
          ],
          links: {},
        };
      }
      if (pathname === '/v1/territories') {
        const territoryIds = ['CHN', 'KOR', 'USA', 'JPN', 'TWN'];
        return {
          data: territoryIds.map((territory) => resource(territory, {
            currency: territory === 'KOR' ? 'KRW' : 'USD',
          }, 'territories')),
          links: {},
          meta: { paging: { total: territoryIds.length } },
        };
      }
      if (pathname.includes('/appAvailabilityV2')) {
        return {
          data: resource('avail-1', { availableInNewTerritories: true }),
        };
      }
      if (pathname.includes('/territoryAvailabilities')) {
        const territoryIds = ['CHN', 'KOR', 'USA', 'JPN', 'TWN'];
        return {
          data: territoryIds.map((territory) => ({
            ...resource(`availability-${territory}`, {
              available: territory !== 'CHN',
            }),
            relationships: {
              territory: { data: { id: territory, type: 'territories' } },
            },
          })),
          links: {},
          meta: { paging: { total: territoryIds.length } },
        };
      }
      throw new Error(`unexpected GET ${path}`);
    },
    async getAll(path) {
      requests.push({ method: 'GET', path });
      const url = new URL(path, 'https://example.invalid');
      if (url.pathname.endsWith('/appStoreVersions')) {
        if (url.searchParams.has('filter[versionString]')) {
          if (exactVersionsOverride !== null) return exactVersionsOverride;
          return [versionResource(versionId, versionState)];
        }
        if (allVersionsOverride !== null) return allVersionsOverride;
        return [versionResource(versionId, versionState)];
      }
      if (url.pathname.endsWith('/appInfos')) {
        if (appInfosOverride !== null) return appInfosOverride;
        return [
          resource(appInfoLiveId, { appStoreState: 'READY_FOR_SALE' }),
          resource(appInfoCurrentId, { appStoreState: currentAppInfoState }),
        ];
      }
      if (url.pathname.includes('/appInfoLocalizations')) {
        const match = path.match(/appInfos\/([^/]+)\/appInfoLocalizations/u);
        const appInfoId = decodeURIComponent(match[1]);
        appInfoFetches.push(appInfoId);
        return payload.appLocalizations.map((entry, index) => resource(
          `appinfo-loc-${index}`,
          {
            locale: entry.locale,
            name: entry.appInfo.name,
            subtitle: entry.appInfo.subtitle,
          },
        ));
      }
      if (
        url.pathname.includes('/appStoreVersions/')
        && url.pathname.endsWith('/appStoreVersionLocalizations')
      ) {
        versionLocalizationFetches.push(path);
        return payload.appLocalizations.map((entry, index) => {
          const desired = maps.appByLocale[entry.locale].version;
          return resource(`version-loc-${index}`, {
            locale: entry.locale,
            description: mismatchVersionLocale === entry.locale
              ? 'old description'
              : desired.description,
            keywords: desired.keywords,
            promotionalText: desired.promotionalText,
            whatsNew: desired.whatsNew,
          });
        });
      }
      if (url.pathname.includes('/appScreenshotSets')
        && url.pathname.endsWith('/appScreenshotSets')) {
        const match = path.match(/appStoreVersionLocalizations\/([^/]+)\/appScreenshotSets/u);
        const localizationIndex = Number(
          decodeURIComponent(match[1]).replace('version-loc-', ''),
        );
        const locale = payload.appLocalizations[localizationIndex].locale;
        return maps.appByLocale[locale].screenshots.map((set, setIndex) => resource(
          `set-${localizationIndex}-${setIndex}`,
          { screenshotDisplayType: set.displayType },
        ));
      }
      if (url.pathname.includes('/appScreenshots')) {
        const match = path.match(/appScreenshotSets\/([^/]+)\/appScreenshots/u);
        const [localizationIndex, setIndex] = decodeURIComponent(match[1])
          .replace('set-', '').split('-').map(Number);
        const locale = payload.appLocalizations[localizationIndex].locale;
        const files = maps.appByLocale[locale].screenshots[setIndex].files;
        return files.map((file, fileIndex) => resource(
          `shot-${localizationIndex}-${setIndex}-${fileIndex}`,
          {
            assetDeliveryState: { state: 'COMPLETE' },
            fileName: file.fileName,
            fileSize: file.size,
            sourceFileChecksum: mismatchScreenshot && fileIndex === 0
              ? '00000000000000000000000000000000'
              : file.md5,
          },
        ));
      }
      if (url.pathname.endsWith('/inAppPurchasesV2')) {
        return IAP_PRODUCT_IDS.map((productId) => {
          const product = maps.productById[productId];
          return resource(maps.remoteIdByProduct[productId], {
            inAppPurchaseType: product.type,
            name: product.referenceName,
            productId,
            reviewNote: product.reviewNote,
            state: 'APPROVED',
          });
        });
      }
      if (url.pathname.includes('/inAppPurchases/')
        && url.pathname.endsWith('/versions')) {
        const match = path.match(/inAppPurchases\/([^/]+)\/versions/u);
        const productId = maps.productByRemoteId[decodeURIComponent(match[1])];
        return [
          resource(maps.v1IdByProduct[productId], {
            state: 'APPROVED',
            version: 1,
          }),
          resource(maps.v2IdByProduct[productId], {
            state: iapDraftState,
            version: 2,
          }),
        ];
      }
      if (url.pathname.includes('/inAppPurchaseVersions/')
        && url.pathname.includes('/localizations')) {
        const match = path.match(/inAppPurchaseVersions\/([^/]+)\/localizations/u);
        const productId = maps.productByV2Id[decodeURIComponent(match[1])];
        assert.ok(productId);
        return maps.productById[productId].localizations.map(
          (localization, localeIndex) => resource(
            `v2loc-${match[1]}-${localeIndex}`,
            {
              description: localization.description,
              locale: localization.locale,
              name: localization.name,
            },
          ),
        );
      }
      if (url.pathname.endsWith('/betaGroups')) {
        return [
          resource('internal-group', {
            isInternalGroup: true,
            name: 'Moonlit Beacon Internal',
          }),
          resource('external-group', {
            isInternalGroup: false,
            name: 'External',
          }),
        ];
      }
      if (url.pathname.includes('/betaGroups/') && url.pathname.endsWith('/builds')) {
        return url.pathname.includes('/internal-group/')
          ? [resource(buildId, { version: payload.release.buildNumber })]
          : [];
      }
      throw new Error(`unexpected GET ALL ${path}`);
    },
  };
  return client;
}

test('review-ready read-only preflight verifies exact 3.0.0 after add-for-review and submitted readback', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root, { version: '3.0.0', build: '10' });
    payload.contact = { status: 'resolved', gates: [] };
    const maps = reviewTransitionMaps(payload);
    assert.deepEqual(
      READ_ONLY_REVIEW_APP_VERSION_STATES,
      ['READY_FOR_REVIEW', 'WAITING_FOR_REVIEW', 'IN_REVIEW', 'COMPLETING'],
    );
    for (const state of READ_ONLY_REVIEW_APP_VERSION_STATES) {
      assert.equal(ADOPTABLE_APP_VERSION_STATES.includes(state), false);
      assert.equal(isAdoptableAppVersionState(state), false);
      assert.equal(isReadOnlyReviewAppVersionState(state), true);
      assert.throws(
        () => assertEditableAppStoreVersionState(state),
        /ASC_VERSION_NOT_EDITABLE/u,
      );
    }

    const prepareClient = createReviewTransitionClient(payload, {
      appInfoState: 'PREPARE_FOR_SUBMISSION',
      iapDraftState: 'PREPARE_FOR_SUBMISSION',
      versionState: 'PREPARE_FOR_SUBMISSION',
    });
    const prepare = await auditAppStoreConnectApplyReadiness({
      client: prepareClient,
      payload,
    });
    assert.equal(prepare.mode, 'GET_ONLY_REMOTE_APPLY_PREFLIGHT');
    assert.equal(prepare.remote.versionId, 'version-300');
    assert.equal(prepare.remote.versionState, 'PREPARE_FOR_SUBMISSION');
    assert.equal(prepare.remote.appInfoId, 'app-info-current');
    assert.deepEqual(prepare.remote.iapVersionIds, maps.v2IdByProduct);
    assert.ok(prepare.plan.every((entry) => entry.action === 'none'));
    assert.equal(prepare.summary.unresolved, 0);

    const standaloneReady = await auditAppStoreConnectRelease({
      client: createReviewTransitionClient(payload, {
        appInfoState: 'READY_FOR_REVIEW',
        iapDraftState: 'READY_FOR_REVIEW',
        versionState: 'READY_FOR_REVIEW',
      }),
      payload,
      skipUnscopedIapLocalizations: true,
    });
    assert.ok(standaloneReady.plan.some((entry) => (
      entry.code === 'ASC_APP_STORE_VERSION_NOT_ADOPTABLE'
      && entry.action === 'unresolved'
    )));
    assert.equal(standaloneReady.remote.appInfoId, null);
    assert.equal(
      standaloneReady.plan.filter((entry) => entry.action === 'create').length,
      20,
    );

    const readyClient = createReviewTransitionClient(payload, {
      appInfoState: 'READY_FOR_REVIEW',
      iapDraftState: 'READY_FOR_REVIEW',
      versionState: 'READY_FOR_REVIEW',
    });
    const ready = await auditAppStoreConnectApplyReadiness({
      client: readyClient,
      payload,
    });
    assert.equal(ready.mode, 'GET_ONLY_REMOTE_APPLY_PREFLIGHT');
    assert.equal(ready.remote.versionId, 'version-300');
    assert.equal(ready.remote.versionState, 'READY_FOR_REVIEW');
    assert.equal(ready.remote.appInfoId, 'app-info-current');
    assert.deepEqual(ready.remote.iapVersionIds, maps.v2IdByProduct);
    assert.ok(Object.values(ready.remote.iapVersionStates).every(
      (state) => state === 'READY_FOR_REVIEW',
    ));
    assert.ok(ready.plan.every((entry) => entry.action === 'none'));
    assert.equal(ready.summary.unresolved, 0);
    assert.deepEqual(readyClient.appInfoFetches, ['app-info-current']);
    assert.equal(readyClient.versionLocalizationFetches.length, 1);
    assert.ok(ready.requests.some((request) => (
      request.path.includes('/appStoreReviewDetail?')
    )));
    assert.ok(ready.requests.some((request) => (
      request.path.includes('/appScreenshotSets/')
      && request.path.includes('/appScreenshots?')
    )));

    const manifest = createAppStoreReleaseManifest(payload);
    const reviewConfirmation = appStoreConfirmationToken(manifest, 'review');
    const posted = [];
    const submitGetClient = {
      async get(path) {
        if (path.includes('/reviewSubmissions/submission-1?')) {
          return { data: resource('submission-1', { state: 'WAITING_FOR_REVIEW' }) };
        }
        if (path.includes('/appStoreVersions/version-300/build?')) {
          return { data: resource('build-300-10', { version: '10' }) };
        }
        assert.fail(`unexpected GET: ${path}`);
      },
      async getAll(path) {
        if (path.includes('/reviewSubmissions?') && !path.includes('/items?')) return [];
        if (path.includes('/items?')) {
          return posted.map((entry, index) => ({
            id: `item-${index}`,
            relationships: Object.fromEntries(Object.entries(entry.relationships)
              .filter(([name]) => name !== 'reviewSubmission')),
            type: 'reviewSubmissionItems',
          }));
        }
        assert.fail(`unexpected GET: ${path}`);
      },
    };
    const submitted = await submitAppStoreConnectReview({
      audit: ready,
      client: {
        async patch(path, body) {
          assert.equal(path, '/v1/reviewSubmissions/submission-1');
          assert.deepEqual(body.data.attributes, { submitted: true });
          return { data: resource('submission-1', { state: 'WAITING_FOR_REVIEW' }) };
        },
        async post(path, body) {
          if (path === '/v1/reviewSubmissions') {
            return { data: resource('submission-1', { state: 'READY_FOR_REVIEW' }) };
          }
          posted.push(body.data);
          return { data: resource(`item-${posted.length}`, {}) };
        },
      },
      getClient: submitGetClient,
      manifest,
      reviewConfirmation,
    });
    assert.equal(submitted.submitted, true);
    assert.equal(submitted.idempotent, false);
    assert.equal(submitted.reviewItemCount, IAP_PRODUCT_IDS.length + 1);
    assert.equal(posted.length, IAP_PRODUCT_IDS.length + 1);

    for (const submittedState of ['WAITING_FOR_REVIEW', 'IN_REVIEW', 'COMPLETING']) {
      const submittedClient = createReviewTransitionClient(payload, {
        appInfoState: submittedState,
        iapDraftState: 'READY_FOR_REVIEW',
        versionState: submittedState,
      });
      const submittedAudit = await auditAppStoreConnectApplyReadiness({
        client: submittedClient,
        payload,
      });
      assert.equal(submittedAudit.remote.versionState, submittedState);
      assert.equal(submittedAudit.remote.appInfoId, 'app-info-current');
      assert.ok(submittedAudit.plan.every((entry) => entry.action === 'none'));
    }

    const waitingClient = createReviewTransitionClient(payload, {
      appInfoState: 'WAITING_FOR_REVIEW',
      iapDraftState: 'READY_FOR_REVIEW',
      versionState: 'WAITING_FOR_REVIEW',
    });
    const waiting = await auditAppStoreConnectApplyReadiness({
      client: waitingClient,
      payload,
    });
    const linkedItems = [
      {
        id: 'item-app',
        relationships: {
          appStoreVersion: { data: { id: 'version-300', type: 'appStoreVersions' } },
        },
        type: 'reviewSubmissionItems',
      },
      ...IAP_PRODUCT_IDS.map((productId, index) => ({
        id: `item-iap-${index}`,
        relationships: {
          inAppPurchaseVersion: {
            data: { id: maps.v2IdByProduct[productId], type: 'inAppPurchaseVersions' },
          },
        },
        type: 'reviewSubmissionItems',
      })),
    ];
    const idempotent = await submitAppStoreConnectReview({
      audit: waiting,
      client: {
        async patch() { assert.fail('submitted readback must not PATCH'); },
        async post() { assert.fail('submitted readback must not POST'); },
      },
      getClient: {
        async get(path) {
          if (path.includes('/appStoreVersions/version-300/build?')) {
            return { data: resource('build-300-10', { version: '10' }) };
          }
          assert.fail(`unexpected GET: ${path}`);
        },
        async getAll(path) {
          if (path.includes('/reviewSubmissions?') && !path.includes('/items?')) {
            return [resource('submission-1', { platform: 'IOS', state: 'WAITING_FOR_REVIEW' })];
          }
          if (path.includes('/items?')) return linkedItems;
          assert.fail(`unexpected GET: ${path}`);
        },
      },
      manifest,
      reviewConfirmation,
    });
    assert.deepEqual(
      { id: idempotent.id, idempotent: idempotent.idempotent, submitted: idempotent.submitted },
      { id: 'submission-1', idempotent: true, submitted: true },
    );
  }));

test('review-state mismatch cannot mutate and unsupported/duplicate review states stay blocked', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root, { version: '3.0.0', build: '10' });
    payload.contact = { status: 'resolved', gates: [] };
    const manifest = createAppStoreReleaseManifest(payload);
    const confirmation = appStoreConfirmationToken(manifest, 'apply');

    const mismatchAudit = await auditAppStoreConnectApplyReadiness({
      client: createReviewTransitionClient(payload, {
        appInfoState: 'READY_FOR_REVIEW',
        iapDraftState: 'READY_FOR_REVIEW',
        mismatchVersionLocale: 'ko',
        versionState: 'READY_FOR_REVIEW',
      }),
      payload,
    });
    const mismatchEntry = mismatchAudit.plan.find((entry) => (
      entry.target === 'appStoreVersionLocalization'
      && entry.identifier === '3.0.0/ko'
    ));
    assert.equal(mismatchEntry.action, 'update');
    assert.equal(mismatchEntry.changes.description.current, 'old description');
    assert.equal(
      mismatchAudit.plan.some((entry) => (
        entry.code === 'ASC_APP_STORE_VERSION_NOT_ADOPTABLE'
      )),
      false,
    );
    let mutations = 0;
    const failOnMutation = async () => {
      mutations += 1;
      assert.fail('review-state mismatch must not reach a network write');
    };
    await assert.rejects(
      applyAppStoreConnectRelease({
        client: {
          delete: failOnMutation,
          patch: failOnMutation,
          post: failOnMutation,
        },
        confirmation,
        getClient: createReviewTransitionClient(payload, {
          appInfoState: 'READY_FOR_REVIEW',
          iapDraftState: 'READY_FOR_REVIEW',
          mismatchVersionLocale: 'ko',
          versionState: 'READY_FOR_REVIEW',
        }),
        manifest,
        payload,
        repoRoot: root,
      }),
      /ASC_VERSION_NOT_EDITABLE/u,
    );
    assert.equal(mutations, 0);

    const buildMismatch = await auditAppStoreConnectApplyReadiness({
      client: createReviewTransitionClient(payload, {
        appInfoState: 'READY_FOR_REVIEW',
        iapDraftState: 'READY_FOR_REVIEW',
        mismatchBuild: true,
        versionState: 'READY_FOR_REVIEW',
      }),
      payload,
    });
    assert.equal(
      buildMismatch.plan.find((entry) => entry.target === 'buildAssociation').action,
      'update',
    );
    await assert.rejects(
      applyAppStoreConnectRelease({
        client: {
          delete: failOnMutation,
          patch: failOnMutation,
          post: failOnMutation,
        },
        confirmation,
        getClient: createReviewTransitionClient(payload, {
          appInfoState: 'READY_FOR_REVIEW',
          iapDraftState: 'READY_FOR_REVIEW',
          mismatchBuild: true,
          versionState: 'READY_FOR_REVIEW',
        }),
        manifest,
        payload,
        repoRoot: root,
      }),
      /ASC_VERSION_NOT_EDITABLE/u,
    );
    assert.equal(mutations, 0);

    for (const unsupported of ['SOMETHING_NEW', null, 'REJECTED']) {
      const blocked = await auditAppStoreConnectApplyReadiness({
        client: createReviewTransitionClient(payload, {
          appInfoState: 'READY_FOR_REVIEW',
          iapDraftState: 'READY_FOR_REVIEW',
          versionState: unsupported,
        }),
        payload,
      });
      assert.ok(blocked.plan.some((entry) => (
        entry.code === 'ASC_APP_STORE_VERSION_NOT_ADOPTABLE'
        && entry.action === 'unresolved'
      )));
    }

    await assert.rejects(
      auditAppStoreConnectApplyReadiness({
        client: createReviewTransitionClient(payload, {
          exactVersionsOverride: [
            resource('version-a', {
              appVersionState: 'READY_FOR_REVIEW',
              platform: 'IOS',
              versionString: '3.0.0',
            }),
            resource('version-b', {
              appVersionState: 'READY_FOR_REVIEW',
              platform: 'IOS',
              versionString: '3.0.0',
            }),
          ],
        }),
        payload,
      }),
      /remote iOS 3\.0\.0 version is duplicated/u,
    );

    await assert.rejects(
      auditAppStoreConnectApplyReadiness({
        client: createReviewTransitionClient(payload, {
          appInfoState: 'READY_FOR_REVIEW',
          appInfosOverride: [
            resource('app-info-live', { appStoreState: 'READY_FOR_SALE' }),
            resource('app-info-a', { appStoreState: 'READY_FOR_REVIEW' }),
            resource('app-info-b', { appStoreState: 'READY_FOR_REVIEW' }),
          ],
          iapDraftState: 'READY_FOR_REVIEW',
          versionState: 'READY_FOR_REVIEW',
        }),
        payload,
      }),
      /exactly one remote App Info/u,
    );

    const differentReview = await auditAppStoreConnectApplyReadiness({
      client: createReviewTransitionClient(payload, {
        allVersionsOverride: [
          resource('version-other', {
            appVersionState: 'READY_FOR_REVIEW',
            copyright: payload.release.copyright,
            platform: 'IOS',
            versionString: '3.0.1',
          }),
          resource('asc-version-2-1-0', {
            appVersionState: 'READY_FOR_DISTRIBUTION',
            platform: 'IOS',
            versionString: '2.1.0',
          }),
        ],
        exactVersionsOverride: [],
      }),
      payload,
    });
    assert.equal(differentReview.remote.versionId, null);
    assert.ok(differentReview.plan.some((entry) => (
      entry.code === 'ASC_APP_STORE_VERSION_CREATE_UNSAFE'
      && entry.action === 'unresolved'
    )));
  }));

function isImageMutationPath(path) {
  return path.includes('appScreenshot')
    || path.includes('AppStoreReviewScreenshot');
}

function recordingMutationClient(calls, { onPatch = null } = {}) {
  return {
    async delete(path) {
      calls.push({ method: 'DELETE', path });
      throw new Error(`unexpected DELETE ${path}`);
    },
    async patch(path, body) {
      calls.push({ method: 'PATCH', path });
      if (onPatch) return onPatch(path, body);
      throw new Error(`unexpected PATCH ${path}`);
    },
    async post(path) {
      calls.push({ method: 'POST', path });
      throw new Error(`unexpected POST ${path}`);
    },
    async uploadOperations() {
      calls.push({ method: 'PUT', path: 'asset-upload' });
      throw new Error('unexpected asset upload');
    },
  };
}

test('reuse-committed-gallery flag is explicit at each CLI invocation shape', () => {
  assert.equal(
    parseAppStoreReleaseArguments([]).reuseCommittedGallery,
    false,
  );
  for (const args of [
    ['--reuse-committed-gallery', '--check'],
    ['--reuse-committed-gallery', '--check', '--remote-audit'],
    [
      '--reuse-committed-gallery',
      '--check',
      '--remote-audit',
      '--apply',
      '--confirm-remote-apply',
      'app-store:apply-reuse-committed-gallery:6796293839:4.0.0:13:digest',
    ],
    [
      '--reuse-committed-gallery',
      '--check',
      '--remote-audit',
      '--apply',
      '--confirm-remote-apply',
      'reuse-apply-token',
      '--submit-review',
      '--confirm-review-submission',
      'reuse-review-token',
    ],
  ]) {
    assert.equal(
      parseAppStoreReleaseArguments(args).reuseCommittedGallery,
      true,
    );
  }
  const composed = parseAppStoreReleaseArguments([
    '--reuse-committed-gallery',
    '--dry-run',
    '--json',
    '--output',
    'builds/release/reuse.json',
  ]);
  assert.equal(composed.reuseCommittedGallery, true);
  assert.equal(composed.json, true);
  assert.equal(composed.output, 'builds/release/reuse.json');
  assert.throws(
    () => parseAppStoreReleaseArguments([
      '--reuse-committed-gallery',
      '--reuse-committed-gallery',
    ]),
    (error) => error.exitCode === 2
      && /duplicate --reuse-committed-gallery/u.test(error.message),
  );
});

test('capture evidence stays strict normally and honestly retained in reuse mode', () => {
  let spawns = 0;
  const spawn = () => {
    spawns += 1;
    return { error: null, status: 0 };
  };
  assert.deepEqual(
    resolveAppStoreCaptureEvidence({ repoRoot: '/fixture', spawn }),
    { evidence: APP_STORE_FRESH_CAPTURE_EVIDENCE, freshCapture: true },
  );
  assert.equal(spawns, 1);
  assert.throws(
    () => resolveAppStoreCaptureEvidence({
      repoRoot: '/fixture',
      spawn: () => ({ error: null, status: 2 }),
    }),
    /screenshot validation failed/u,
  );
  assert.deepEqual(
    resolveAppStoreCaptureEvidence({
      repoRoot: '/fixture',
      reuseCommittedGallery: true,
      spawn,
    }),
    {
      evidence: APP_STORE_REUSE_COMMITTED_GALLERY_EVIDENCE,
      freshCapture: false,
    },
  );
  assert.equal(spawns, 1);
});

test('reuse mode never relabels stale capture evidence and keeps local integrity checks', () =>
  withTempRoot((root) => {
    const payload = fixturePayload(root);
    const manifest = createAppStoreReleaseManifest(payload);
    const provenancePath = join(
      root,
      APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
    );
    const capturePath = join(root, APP_STORE_CAPTURE_REPORT_RELATIVE_PATH);
    const provenanceBefore = readFileSync(provenancePath);
    const captureBefore = readFileSync(capturePath);
    const reusePayload = buildAppStoreReleasePayload({ repoRoot: root });
    assert.equal(canonicalJson(reusePayload), canonicalJson(payload));
    assert.equal(
      canonicalJson(createAppStoreReleaseManifest(reusePayload)),
      canonicalJson(manifest),
    );
    assert.deepEqual(readFileSync(provenancePath), provenanceBefore);
    assert.deepEqual(readFileSync(capturePath), captureBefore);
    const report = formatAppStoreReleaseReport({
      manifestPath: 'builds/release/app-store-release-manifest.json',
      manifest,
      check: true,
      reuseCommittedGallery: true,
    });
    assert.match(report, /reuse committed gallery/u);
    assert.match(
      report,
      /RETAINED_EXISTING_UPLOADS_NOT_FRESH_CAPTURE/u,
    );
    assert.match(report, /retained existing uploads, not fresh capture/u);
    assert.doesNotMatch(report, /FRESH_CAPTURE_CHECK_PASSED/u);
    const normalReport = formatAppStoreReleaseReport({
      manifestPath: 'builds/release/app-store-release-manifest.json',
      manifest,
      check: true,
    });
    assert.doesNotMatch(
      normalReport,
      /RETAINED_EXISTING_UPLOADS_NOT_FRESH_CAPTURE/u,
    );
    assert.doesNotMatch(normalReport, /reuse committed gallery/u);
    const first = join(
      root,
      'builds/release/app-store/en-US/iphone-6.5',
      SCREENSHOT_FILE_NAMES[0],
    );
    writeFileSync(first, fakeRgbPng(2778, 1284, 4242));
    assert.throws(
      () => buildAppStoreReleasePayload({ repoRoot: root }),
      /output mapping differs from the actual PNG/u,
    );
  }));

test('reuse confirmation tokens authorize only reuse mode, in both directions', () =>
  withTempRoot((root) => {
    const payload = fixturePayload(root, { version: '4.0.0', build: '13' });
    const manifest = createAppStoreReleaseManifest(payload);
    const applyToken = appStoreConfirmationToken(manifest, 'apply');
    const reviewToken = appStoreConfirmationToken(manifest, 'review');
    const reuseApply = appStoreConfirmationToken(
      manifest,
      APP_STORE_REUSE_GALLERY_APPLY_PURPOSE,
    );
    const reuseReview = appStoreConfirmationToken(
      manifest,
      APP_STORE_REUSE_GALLERY_REVIEW_PURPOSE,
    );
    assert.match(
      reuseApply,
      /^app-store:apply-reuse-committed-gallery:6796293839:4\.0\.0:13:/u,
    );
    assert.match(
      reuseReview,
      /^app-store:review-reuse-committed-gallery:6796293839:4\.0\.0:13:/u,
    );
    assert.notEqual(reuseApply, applyToken);
    assert.notEqual(reuseReview, reviewToken);
    assert.equal(assertAppStoreApplyAuthorization({
      confirmation: reuseApply,
      manifest,
      payload,
      reuseCommittedGallery: true,
      reviewConfirmation: reuseReview,
      submitReview: true,
    }), true);
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation: applyToken,
      manifest,
      payload,
      reuseCommittedGallery: true,
    }), /ASC_APPLY_CONFIRMATION_MISMATCH/u);
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation: reuseApply,
      manifest,
      payload,
    }), /ASC_APPLY_CONFIRMATION_MISMATCH/u);
    assert.throws(() => assertAppStoreApplyAuthorization({
      confirmation: reuseApply,
      manifest,
      payload,
      reuseCommittedGallery: true,
      reviewConfirmation: reviewToken,
      submitReview: true,
    }), /ASC_REVIEW_CONFIRMATION_MISMATCH/u);
    const summary = appStoreApplyCheckSummary(manifest, {
      reuseCommittedGallery: true,
    });
    assert.equal(summary.applyConfirmation, reuseApply);
    assert.equal(summary.reviewConfirmation, reuseReview);
    const normal = appStoreApplyCheckSummary(manifest);
    assert.equal(normal.applyConfirmation, applyToken);
    assert.equal(normal.reviewConfirmation, reviewToken);
    assert.throws(
      () => appStoreConfirmationToken(manifest, 'apply-reuse'),
      /ASC_CONFIRMATION_PURPOSE_INVALID/u,
    );
  }));

test('reuse image gate refuses every non-none image plan and keeps other entries', () => {
  const plan = [
    {
      action: 'none',
      identifier: 'en-US/APP_IPHONE_65',
      target: 'appScreenshotSet',
    },
    {
      action: 'replace',
      identifier: 'ko/APP_IPHONE_65',
      remoteId: 'set-1',
      target: 'appScreenshotSet',
    },
    {
      action: 'create',
      identifier: 'ko/APP_IPAD_PRO_3GEN_129',
      target: 'appScreenshotSet',
    },
    {
      action: 'none',
      identifier: 'product.a',
      target: 'inAppPurchaseReviewImage',
    },
    {
      action: 'replace',
      identifier: 'product.b',
      remoteId: 'img-1',
      target: 'inAppPurchaseReviewImage',
    },
    {
      action: 'unresolved',
      code: 'SOME_CODE',
      identifier: 'product.c',
      target: 'inAppPurchaseReviewImage',
    },
    {
      action: 'update',
      identifier: '4.0.0/ko',
      target: 'appStoreVersionLocalization',
    },
    {
      action: 'unresolved',
      code: 'IAP_REMOTE_STATE_NOT_RELEASE_READY',
      identifier: 'product.d',
      target: 'inAppPurchaseReadiness',
    },
  ];
  const gated = applyReuseCommittedGalleryImageGate(plan);
  assert.equal(gated.verifiedImageTargets, 2);
  assert.deepEqual(gated.refusedImageTargets, [
    {
      identifier: 'ko/APP_IPHONE_65',
      refusedAction: 'replace',
      target: 'appScreenshotSet',
    },
    {
      identifier: 'ko/APP_IPAD_PRO_3GEN_129',
      refusedAction: 'create',
      target: 'appScreenshotSet',
    },
    {
      identifier: 'product.b',
      refusedAction: 'replace',
      target: 'inAppPurchaseReviewImage',
    },
    {
      identifier: 'product.c',
      refusedAction: 'unresolved',
      target: 'inAppPurchaseReviewImage',
    },
  ]);
  const converted = gated.plan.filter((entry) => (
    entry.code === APP_STORE_REUSE_GALLERY_IMAGE_DIFFERS
  ));
  assert.equal(converted.length, 3);
  for (const entry of converted) {
    assert.equal(entry.action, 'unresolved');
    assert.equal(entry.remoteMutationPlanned, false);
    assert.match(
      entry.reason,
      /must exactly match the retained manifest uploads/u,
    );
  }
  assert.equal(
    gated.plan.find((entry) => entry.identifier === 'product.c').code,
    'SOME_CODE',
  );
  assert.equal(
    gated.plan.find((entry) => entry.identifier === '4.0.0/ko').action,
    'update',
  );
  assert.equal(
    gated.plan.find((entry) => entry.identifier === 'product.d').code,
    'IAP_REMOTE_STATE_NOT_RELEASE_READY',
  );
  assert.throws(
    () => applyReuseCommittedGalleryImageGate(null),
    /remote plan must be an array/u,
  );
});

test('reuse preflight verifies the identical retained gallery and reports it honestly', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root, { version: '4.0.0', build: '13' });
    payload.contact = { status: 'resolved', gates: [] };
    const reuse = await auditAppStoreConnectApplyReadiness({
      client: createReviewTransitionClient(payload, {
        versionState: 'DEVELOPER_REJECTED',
      }),
      payload,
      reuseCommittedGallery: true,
    });
    assert.equal(reuse.mode, 'GET_ONLY_REMOTE_APPLY_PREFLIGHT');
    assert.equal(reuse.remote.versionState, 'DEVELOPER_REJECTED');
    assert.equal(reuse.summary.unresolved, 0);
    assert.ok(reuse.plan.every((entry) => entry.action === 'none'));
    assert.deepEqual(reuse.reuse, {
      decision: 'REUSE_COMMITTED_GALLERY',
      freshCaptureEvidence: false,
      galleryEvidence: 'RETAINED_EXISTING_UPLOADS_NOT_FRESH_CAPTURE',
      gallerySource: 'retained-manifest-pinned-uploads',
      refusedImageTargets: [],
      verifiedImageTargets: 20,
    });
    const normal = await auditAppStoreConnectApplyReadiness({
      client: createReviewTransitionClient(payload, {
        versionState: 'DEVELOPER_REJECTED',
      }),
      payload,
    });
    assert.equal(normal.reuse, undefined);
    assert.equal(normal.summary.unresolved, 0);
  }));

test('reuse preflight refuses changed, missing, and reordered images as hard blockers', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root, { version: '4.0.0', build: '13' });
    payload.contact = { status: 'resolved', gates: [] };
    const normal = await auditAppStoreConnectApplyReadiness({
      client: createReviewTransitionClient(payload, {
        mismatchScreenshot: true,
      }),
      payload,
    });
    assert.ok(normal.plan.some((entry) => (
      entry.target === 'appScreenshotSet' && entry.action === 'replace'
    )));
    const changed = await auditAppStoreConnectApplyReadiness({
      client: createReviewTransitionClient(payload, {
        mismatchScreenshot: true,
      }),
      payload,
      reuseCommittedGallery: true,
    });
    const refusedSets = changed.plan.filter((entry) => (
      entry.code === APP_STORE_REUSE_GALLERY_IMAGE_DIFFERS
    ));
    assert.equal(refusedSets.length, 10);
    assert.ok(refusedSets.every((entry) => (
      entry.action === 'unresolved' && entry.refusedAction === 'replace'
    )));
    assert.equal(changed.reuse.verifiedImageTargets, 10);
    assert.equal(changed.reuse.refusedImageTargets.length, 10);

    const base = createReviewTransitionClient(payload);
    const wrapped = {
      ...base,
      requests: base.requests,
      async get(path) {
        if (path.includes(
          '/inAppPurchases/iap-remote-0/appStoreReviewScreenshot',
        )) {
          return null;
        }
        return base.get(path);
      },
      async getAll(path) {
        const pathname = new URL(path, 'https://example.invalid').pathname;
        if (pathname
          === '/v1/appStoreVersionLocalizations/version-loc-1/appScreenshotSets') {
          const sets = await base.getAll(path);
          return sets.slice(0, 1);
        }
        if (pathname === '/v1/appScreenshotSets/set-2-0/appScreenshots') {
          const files = await base.getAll(path);
          return [...files].reverse();
        }
        return base.getAll(path);
      },
    };
    const normalWrapped = await auditAppStoreConnectApplyReadiness({
      client: wrapped,
      payload,
    });
    assert.equal(normalWrapped.plan.find((entry) => (
      entry.target === 'appScreenshotSet'
      && entry.identifier === 'ko/APP_IPAD_PRO_3GEN_129'
    )).action, 'create');
    assert.equal(normalWrapped.plan.find((entry) => (
      entry.target === 'appScreenshotSet'
      && entry.identifier === 'ja/APP_IPHONE_65'
    )).action, 'replace');
    const refused = await auditAppStoreConnectApplyReadiness({
      client: wrapped,
      payload,
      reuseCommittedGallery: true,
    });
    const refusedEntries = refused.plan.filter((entry) => (
      entry.code === APP_STORE_REUSE_GALLERY_IMAGE_DIFFERS
    ));
    assert.deepEqual(
      refusedEntries
        .map((entry) => (
          `${entry.target} ${entry.identifier} ${entry.refusedAction}`
        ))
        .sort(),
      [
        'appScreenshotSet ja/APP_IPHONE_65 replace',
        'appScreenshotSet ko/APP_IPAD_PRO_3GEN_129 create',
        `inAppPurchaseReviewImage ${IAP_PRODUCT_IDS[0]} create`,
      ],
    );
    assert.ok(refusedEntries.every((entry) => (
      entry.remoteMutationPlanned === false
    )));
    const manifest = createAppStoreReleaseManifest(payload);
    const report = formatAppStoreReleaseReport({
      manifestPath: 'builds/release/app-store-release-manifest.json',
      manifest,
      check: true,
      remoteAudit: refused,
      reuseCommittedGallery: true,
    });
    assert.match(
      report,
      /UNRESOLVED appScreenshotSet ja\/APP_IPHONE_65 ASC_REUSE_GALLERY_IMAGE_DIFFERS/u,
    );
    assert.match(
      report,
      /UNRESOLVED inAppPurchaseReviewImage com\.crossplatformkorea\.moonlitbeacon\.supporter ASC_REUSE_GALLERY_IMAGE_DIFFERS/u,
    );
  }));

test('reuse apply converges a replacement build with zero image mutations', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root, { version: '4.0.0', build: '13' });
    payload.contact = { status: 'resolved', gates: [] };
    const manifest = createAppStoreReleaseManifest(payload);
    const confirmation = appStoreConfirmationToken(
      manifest,
      APP_STORE_REUSE_GALLERY_APPLY_PURPOSE,
    );
    const quietMutations = [];
    const quiet = await applyAppStoreConnectRelease({
      client: recordingMutationClient(quietMutations),
      confirmation,
      getClient: createReviewTransitionClient(payload, {
        versionState: 'DEVELOPER_REJECTED',
      }),
      manifest,
      payload,
      repoRoot: root,
      reuseCommittedGallery: true,
    });
    assert.equal(quiet.complete, true);
    assert.deepEqual(quiet.applied, []);
    assert.equal(quietMutations.length, 0);
    assert.equal(
      quiet.reuse.galleryEvidence,
      'RETAINED_EXISTING_UPLOADS_NOT_FRESH_CAPTURE',
    );
    assert.equal(quiet.reuse.verifiedImageTargets, 20);
    const quietReport = formatAppStoreApplyReport(quiet);
    assert.match(quietReport, /converged through GET revalidation/u);
    assert.match(quietReport, /RETAINED_EXISTING_UPLOADS_NOT_FRESH_CAPTURE/u);

    let attachedBuildId = 'build-old';
    const base = createReviewTransitionClient(payload, {
      versionState: 'DEVELOPER_REJECTED',
    });
    const statefulGet = {
      ...base,
      requests: base.requests,
      async get(path) {
        if (path.includes('/appStoreVersions/version-300/build?')) {
          base.requests.push({ method: 'GET', path });
          return {
            data: resource(attachedBuildId, {
              version: attachedBuildId === 'build-300-10' ? '13' : '12',
            }),
          };
        }
        return base.get(path);
      },
    };
    const mutations = [];
    const result = await applyAppStoreConnectRelease({
      client: recordingMutationClient(mutations, {
        onPatch(path, body) {
          assert.equal(
            path,
            '/v1/appStoreVersions/version-300/relationships/build',
          );
          attachedBuildId = body.data.id;
          return { data: {} };
        },
      }),
      confirmation,
      getClient: statefulGet,
      manifest,
      payload,
      repoRoot: root,
      reuseCommittedGallery: true,
    });
    assert.equal(result.complete, true);
    assert.deepEqual(result.applied, [{
      action: 'update',
      identifier: 'IOS/4.0.0(13)',
      target: 'buildAssociation',
    }]);
    assert.deepEqual(mutations, [{
      method: 'PATCH',
      path: '/v1/appStoreVersions/version-300/relationships/build',
    }]);
    assert.ok(mutations.every((mutation) => (
      !isImageMutationPath(mutation.path)
    )));
  }));

test('reuse apply aborts before the first mutation when the gallery differs', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root, { version: '4.0.0', build: '13' });
    payload.contact = { status: 'resolved', gates: [] };
    const manifest = createAppStoreReleaseManifest(payload);
    const confirmation = appStoreConfirmationToken(
      manifest,
      APP_STORE_REUSE_GALLERY_APPLY_PURPOSE,
    );
    const mutations = [];
    const result = await applyAppStoreConnectRelease({
      client: recordingMutationClient(mutations),
      confirmation,
      getClient: createReviewTransitionClient(payload, {
        mismatchScreenshot: true,
        versionState: 'DEVELOPER_REJECTED',
      }),
      manifest,
      payload,
      repoRoot: root,
      reuseCommittedGallery: true,
    });
    assert.equal(result.complete, false);
    assert.deepEqual(result.applied, []);
    assert.equal(mutations.length, 0);
    assert.equal(result.blockers.filter((blocker) => (
      blocker.code === APP_STORE_REUSE_GALLERY_IMAGE_DIFFERS
    )).length, 10);
    assert.equal(result.reuse.refusedImageTargets.length, 10);
    const report = formatAppStoreApplyReport(result);
    assert.match(report, /stopped at a safety gate/u);
    assert.match(report, /RETAINED_EXISTING_UPLOADS_NOT_FRESH_CAPTURE/u);
  }));

test('reuse apply refuses an image mutation race with zero requests', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root, { version: '4.0.0', build: '13' });
    const mutations = [];
    const client = recordingMutationClient(mutations);
    const getClient = {
      async get() {
        return {};
      },
      async getAll() {
        return [];
      },
    };
    for (const entry of [
      {
        action: 'replace',
        identifier: 'ko/APP_IPHONE_65',
        remoteFiles: [],
        remoteId: 'set-1',
        target: 'appScreenshotSet',
      },
      {
        action: 'create',
        identifier: 'ko/APP_IPAD_PRO_3GEN_129',
        parentId: 'loc-1',
        target: 'appScreenshotSet',
      },
      {
        action: 'replace',
        identifier: IAP_PRODUCT_IDS[0],
        parentId: 'iap-0',
        remoteId: 'img-1',
        target: 'inAppPurchaseReviewImage',
      },
    ]) {
      await assert.rejects(
        applyPlanEntry({
          client,
          entry,
          getClient,
          payload,
          repoRoot: root,
          reuseCommittedGallery: true,
        }),
        /ASC_REUSE_GALLERY_MUTATION_REFUSED/u,
      );
    }
    assert.equal(mutations.length, 0);
    await applyPlanEntry({
      client: {
        async patch(path) {
          mutations.push({ method: 'PATCH', path });
          assert.equal(path, '/v1/appInfoLocalizations/info-1');
          return {};
        },
      },
      entry: {
        action: 'update',
        changes: { subtitle: { current: 'old', desired: 'new' } },
        identifier: 'ko',
        remoteId: 'info-1',
        target: 'appInfoLocalization',
      },
      getClient,
      payload,
      repoRoot: root,
      reuseCommittedGallery: true,
    });
    assert.deepEqual(mutations, [{
      method: 'PATCH',
      path: '/v1/appInfoLocalizations/info-1',
    }]);
    await assert.rejects(
      applyPlanEntry({
        client,
        entry: {
          action: 'none',
          identifier: 'ko/APP_IPHONE_65',
          target: 'appScreenshotSet',
        },
        getClient,
        payload,
        repoRoot: root,
      }),
      /ASC_PLAN_ACTION_NOT_MUTABLE/u,
    );
  }));

test('reuse apply fails wrong confirmation and artifact drift before any network', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root, { version: '4.0.0', build: '13' });
    payload.contact = { status: 'resolved', gates: [] };
    const manifest = createAppStoreReleaseManifest(payload);
    const reuseApply = appStoreConfirmationToken(
      manifest,
      APP_STORE_REUSE_GALLERY_APPLY_PURPOSE,
    );
    const normalApply = appStoreConfirmationToken(manifest, 'apply');
    let remoteCalls = 0;
    const failIfCalled = async () => {
      remoteCalls += 1;
      throw new Error('must not reach network');
    };
    const clients = {
      client: {
        delete: failIfCalled,
        patch: failIfCalled,
        post: failIfCalled,
      },
      getClient: {
        get: failIfCalled,
        getAll: failIfCalled,
      },
    };
    await assert.rejects(
      applyAppStoreConnectRelease({
        ...clients,
        confirmation: normalApply,
        manifest,
        payload,
        repoRoot: root,
        reuseCommittedGallery: true,
      }),
      /ASC_APPLY_CONFIRMATION_MISMATCH/u,
    );
    const provenancePath = join(
      root,
      APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
    );
    writeFileSync(
      provenancePath,
      `${readFileSync(provenancePath, 'utf8')}\n`,
    );
    await assert.rejects(
      applyAppStoreConnectRelease({
        ...clients,
        confirmation: reuseApply,
        manifest,
        payload,
        repoRoot: root,
        reuseCommittedGallery: true,
      }),
      /ASC_ASSET_CHANGED/u,
    );
    assert.equal(remoteCalls, 0);
  }));

test('reuse review submission keeps the 11-target and linked-build readback', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root);
    payload.release.version = '4.0.0';
    payload.release.buildNumber = '13';
    const manifest = createAppStoreReleaseManifest(payload);
    const iapVersionIds = Object.fromEntries(IAP_PRODUCT_IDS.map(
      (productId, index) => [productId, `iap-version-${index}`],
    ));
    const iapVersionStates = Object.fromEntries(IAP_PRODUCT_IDS.map(
      (productId) => [productId, 'PREPARE_FOR_SUBMISSION'],
    ));
    const audit = {
      appId: payload.release.appId,
      mode: 'GET_ONLY_REMOTE_APPLY_PREFLIGHT',
      plan: [
        ...IAP_PRODUCT_IDS.map((productId) => ({
          action: 'none',
          identifier: productId,
          remoteState: 'READY_TO_SUBMIT',
          target: 'inAppPurchase',
        })),
        {
          action: 'none',
          buildId: 'build-13',
          identifier: 'IOS/4.0.0(13)',
          target: 'buildAssociation',
        },
      ],
      remote: {
        iapVersionIds,
        iapVersionStates,
        versionId: 'version-400',
        versionReleaseType: APP_STORE_VERSION_RELEASE_TYPE,
      },
    };
    const items = [];
    const calls = [];
    const getClient = {
      async get(path) {
        if (path.includes('/reviewSubmissions/submission-1?')) {
          return {
            data: resource('submission-1', { state: 'WAITING_FOR_REVIEW' }),
          };
        }
        if (path.includes('/appStoreVersions/version-400/build?')) {
          return { data: resource('build-13', { version: '13' }) };
        }
        assert.fail(`unexpected GET: ${path}`);
      },
      async getAll(path) {
        if (path.includes('/reviewSubmissions?')) return [];
        if (path.includes('/reviewSubmissions/submission-1/items?')) {
          return items.map((item, index) => ({
            id: `item-${index}`,
            relationships: item.relationships,
          }));
        }
        assert.fail(`unexpected GET: ${path}`);
      },
    };
    const client = {
      async post(path, body) {
        calls.push({ body, method: 'POST', path });
        if (path === '/v1/reviewSubmissions') {
          return {
            data: resource('submission-1', { state: 'READY_FOR_REVIEW' }),
          };
        }
        items.push(body.data);
        return { data: resource(`item-${items.length}`, {}) };
      },
      async patch(path, body) {
        calls.push({ body, method: 'PATCH', path });
        return {
          data: resource('submission-1', { state: 'WAITING_FOR_REVIEW' }),
        };
      },
    };
    await assert.rejects(
      submitAppStoreConnectReview({
        audit,
        client,
        getClient,
        manifest,
        reuseCommittedGallery: true,
        reviewConfirmation: appStoreConfirmationToken(manifest, 'review'),
      }),
      /ASC_REVIEW_CONFIRMATION_MISMATCH/u,
    );
    assert.equal(calls.length, 0);
    const result = await submitAppStoreConnectReview({
      audit,
      client,
      getClient,
      manifest,
      reuseCommittedGallery: true,
      reviewConfirmation: appStoreConfirmationToken(
        manifest,
        APP_STORE_REUSE_GALLERY_REVIEW_PURPOSE,
      ),
    });
    assert.equal(result.submitted, true);
    assert.equal(result.buildId, 'build-13');
    assert.equal(result.reviewItemCount, IAP_PRODUCT_IDS.length + 1);
    assert.equal(items.length, IAP_PRODUCT_IDS.length + 1);
    assert.ok(calls.every((call) => !isImageMutationPath(call.path)));
    assert.equal(calls.at(-1).method, 'PATCH');
    assert.deepEqual(calls.at(-1).body.data.attributes, { submitted: true });
  }));

test('bare local-only reuse preparation parses and reports zero remote work', () =>
  withTempRoot((root) => {
    const options = parseAppStoreReleaseArguments([
      '--reuse-committed-gallery',
    ]);
    assert.equal(options.reuseCommittedGallery, true);
    assert.equal(options.check, false);
    assert.equal(options.remoteAudit, false);
    assert.equal(options.apply, false);
    assert.equal(options.confirmation, null);
    const payload = fixturePayload(root, { version: '4.0.0', build: '13' });
    const manifest = createAppStoreReleaseManifest(payload);
    const report = formatAppStoreReleaseReport({
      manifestPath: 'builds/release/app-store-release-manifest.json',
      manifest,
      check: false,
      reuseCommittedGallery: true,
    });
    assert.match(
      report,
      /local-only dry-run passed \(reuse committed gallery\)/u,
    );
    assert.match(
      report,
      /RETAINED_EXISTING_UPLOADS_NOT_FRESH_CAPTURE/u,
    );
    assert.match(
      report,
      /remote requests: 0 \(default command is local-only\)/u,
    );
  }));

test('future iOS releases default to AFTER_APPROVAL without a scheduled date', async () => {
  await withTempRoot(async (root) => {
    const payload = fixturePayload(root);
    assert.equal(APP_STORE_VERSION_RELEASE_TYPE, 'AFTER_APPROVAL');
    assert.equal(payload.release.releaseType, 'AFTER_APPROVAL');
    const manifest = createAppStoreReleaseManifest(payload);
    assert.equal(verifyAppStoreReleaseManifest(manifest, payload), true);
    for (const bad of ['MANUAL', 'SCHEDULED', null, undefined, '']) {
      const tampered = structuredClone(payload);
      tampered.release.releaseType = bad;
      assert.throws(
        () => verifyAppStoreReleaseManifest(
          createAppStoreReleaseManifest(tampered),
        ),
        /release type must be AFTER_APPROVAL/u,
      );
    }
  });

  const createPayload = minimalReleasePayload();
  const createClient = versionAuditClient({
    allVersions: realReleasedHistory(),
  });
  const createAudit = await auditAppStoreConnectRelease({
    payload: createPayload,
    client: createClient,
  });
  const createEntry = createAudit.plan.find((entry) => (
    entry.target === 'appStoreVersion' && entry.action === 'create'
  ));
  assert.deepEqual(createEntry.desired, {
    copyright: createPayload.release.copyright,
    platform: 'IOS',
    versionString: createPayload.release.version,
    releaseType: 'AFTER_APPROVAL',
  });
  assert.equal(
    Object.hasOwn(createEntry.desired, 'earliestReleaseDate'),
    false,
  );
  const versionQueries = createClient.paths.filter((path) => (
    path.includes('/appStoreVersions?')
  ));
  assert.ok(versionQueries.length >= 1);
  for (const query of versionQueries) {
    assert.match(
      decodeURIComponent(query),
      /fields\[appStoreVersions\][^]*releaseType/u,
    );
  }

  for (const [state, remoteType] of [
    ['PREPARE_FOR_SUBMISSION', 'MANUAL'],
    ['DEVELOPER_REJECTED', 'SCHEDULED'],
  ]) {
    const payload = minimalReleasePayload();
    const client = versionAuditClient({
      exactVersions: [resource('editable-version', {
        appVersionState: state,
        copyright: payload.release.copyright,
        platform: 'IOS',
        versionString: payload.release.version,
        releaseType: remoteType,
      })],
    });
    const audit = await auditAppStoreConnectRelease({ payload, client });
    assert.equal(audit.remote.versionReleaseType, remoteType);
    const entry = audit.plan.find((candidate) => (
      candidate.target === 'appStoreVersion'
    ));
    assert.equal(entry.action, 'update');
    assert.deepEqual(entry.changes.releaseType, {
      current: remoteType,
      desired: 'AFTER_APPROVAL',
    });
    assert.equal(Object.hasOwn(entry.changes, 'earliestReleaseDate'), false);
    const patches = [];
    await applyPlanEntry({
      client: {
        async patch(path, body) {
          patches.push({ body, path });
        },
      },
      entry,
      payload,
    });
    assert.equal(patches[0].path, '/v1/appStoreVersions/editable-version');
    assert.equal(
      patches[0].body.data.attributes.releaseType,
      'AFTER_APPROVAL',
    );
    assert.equal(
      Object.hasOwn(patches[0].body.data.attributes, 'earliestReleaseDate'),
      false,
    );
  }

  const idemPayload = minimalReleasePayload();
  const idemAudit = await auditAppStoreConnectRelease({
    payload: idemPayload,
    client: versionAuditClient({
      exactVersions: [resource('matching-version', {
        appVersionState: 'PREPARE_FOR_SUBMISSION',
        copyright: idemPayload.release.copyright,
        platform: 'IOS',
        versionString: idemPayload.release.version,
        releaseType: 'AFTER_APPROVAL',
      })],
    }),
  });
  const idemEntry = idemAudit.plan.find((candidate) => (
    candidate.target === 'appStoreVersion'
  ));
  assert.equal(idemEntry.action, 'none');
  assert.equal(idemAudit.remote.versionReleaseType, 'AFTER_APPROVAL');
});

test('automatic-release readback blocks review submission on mismatch', () =>
  withTempRoot(async (root) => {
    const payload = fixturePayload(root);
    payload.release.version = '1.0.1';
    payload.release.buildNumber = '3';
    const manifest = createAppStoreReleaseManifest(payload);
    const reviewConfirmation = appStoreConfirmationToken(manifest, 'review');
    const iapVersionIds = Object.fromEntries(IAP_PRODUCT_IDS.map(
      (productId, index) => [productId, `iap-version-${index}`],
    ));
    const iapVersionStates = Object.fromEntries(IAP_PRODUCT_IDS.map(
      (productId) => [productId, 'PREPARE_FOR_SUBMISSION'],
    ));
    function convergedAuditWithReleaseType(releaseType) {
      return {
        appId: payload.release.appId,
        mode: 'GET_ONLY_REMOTE_APPLY_PREFLIGHT',
        plan: [
          ...IAP_PRODUCT_IDS.map((productId) => ({
            action: 'none',
            identifier: productId,
            remoteState: 'READY_TO_SUBMIT',
            target: 'inAppPurchase',
          })),
          {
            action: 'none',
            buildId: 'build-3',
            identifier: 'IOS/1.0.1(3)',
            target: 'buildAssociation',
          },
        ],
        remote: {
          iapVersionIds,
          iapVersionStates,
          versionId: 'version-101',
          ...(releaseType === undefined ? {} : {
            versionReleaseType: releaseType,
          }),
        },
      };
    }

    const items = [];
    const good = await submitAppStoreConnectReview({
      audit: convergedAuditWithReleaseType('AFTER_APPROVAL'),
      client: {
        async post(path, body) {
          if (path === '/v1/reviewSubmissions') {
            return {
              data: resource('submission-1', { state: 'READY_FOR_REVIEW' }),
            };
          }
          items.push(body.data);
          return { data: resource(`item-${items.length}`, {}) };
        },
        async patch(path, body) {
          assert.equal(path, '/v1/reviewSubmissions/submission-1');
          assert.deepEqual(body.data.attributes, { submitted: true });
          return {
            data: resource('submission-1', { state: 'WAITING_FOR_REVIEW' }),
          };
        },
      },
      getClient: {
        async get(path) {
          if (path.includes('/reviewSubmissions/submission-1?')) {
            return {
              data: resource('submission-1', { state: 'WAITING_FOR_REVIEW' }),
            };
          }
          if (path.includes('/appStoreVersions/version-101/build?')) {
            return { data: resource('build-3', { version: '3' }) };
          }
          assert.fail(`unexpected GET: ${path}`);
        },
        async getAll(path) {
          if (path.includes('/reviewSubmissions?')) return [];
          if (path.includes('/reviewSubmissions/submission-1/items?')) {
            return items.map((item, index) => ({
              id: `item-${index}`,
              relationships: item.relationships,
            }));
          }
          assert.fail(`unexpected GET: ${path}`);
        },
      },
      manifest,
      reviewConfirmation,
    });
    assert.equal(good.submitted, true);
    assert.equal(items.length, IAP_PRODUCT_IDS.length + 1);

    for (const bad of ['MANUAL', 'SCHEDULED', null, undefined, 'UNKNOWN', '']) {
      let posts = 0;
      let patches = 0;
      await assert.rejects(
        submitAppStoreConnectReview({
          audit: convergedAuditWithReleaseType(bad),
          client: {
            async post() {
              posts += 1;
              throw new Error('must not POST on bad automatic-release readback');
            },
            async patch() {
              patches += 1;
              throw new Error('must not PATCH on bad automatic-release readback');
            },
          },
          getClient: {
            async get() {
              assert.fail('must not read beyond the automatic-release guard');
            },
            async getAll() {
              assert.fail('must not read beyond the automatic-release guard');
            },
          },
          manifest,
          reviewConfirmation,
        }),
        /ASC_AUTOMATIC_RELEASE_NOT_VERIFIED/u,
      );
      assert.equal(posts, 0);
      assert.equal(patches, 0);
    }
  }));

test('read-only review and published versions refuse releaseType mutation', async () => {
  const payload = minimalReleasePayload();
  for (const state of READ_ONLY_REVIEW_APP_VERSION_STATES) {
    const versionAttributes = {
      appVersionState: state,
      copyright: payload.release.copyright,
      platform: 'IOS',
      versionString: payload.release.version,
      releaseType: 'MANUAL',
    };
    const blocked = await auditAppStoreConnectRelease({
      payload,
      client: versionAuditClient({
        exactVersions: [resource('review-version', versionAttributes)],
      }),
    });
    assert.ok(blocked.plan.some((entry) => (
      entry.code === 'ASC_APP_STORE_VERSION_NOT_ADOPTABLE'
      && entry.action === 'unresolved'
    )), state);
    assert.equal(blocked.plan.some((entry) => (
      entry.target === 'appStoreVersion'
      && ['create', 'update'].includes(entry.action)
    )), false, state);

    const allowed = await auditAppStoreConnectRelease({
      payload,
      client: versionAuditClient({
        exactVersions: [resource('review-version', versionAttributes)],
      }),
      allowReadOnlyReviewVersion: true,
    });
    const entry = allowed.plan.find((candidate) => (
      candidate.target === 'appStoreVersion'
    ));
    assert.equal(entry.action, 'update', state);
    assert.deepEqual(entry.changes.releaseType, {
      current: 'MANUAL',
      desired: 'AFTER_APPROVAL',
    }, state);
    assert.throws(
      () => assertEditableAppStoreVersionState(state),
      /ASC_VERSION_NOT_EDITABLE/u,
    );
  }

  for (const state of ['READY_FOR_DISTRIBUTION', 'REPLACED_WITH_NEW_VERSION']) {
    const audit = await auditAppStoreConnectRelease({
      payload,
      client: versionAuditClient({
        exactVersions: [resource('published-version', {
          appVersionState: state,
          platform: 'IOS',
          versionString: payload.release.version,
          releaseType: 'MANUAL',
        })],
      }),
      allowReadOnlyReviewVersion: true,
    });
    assert.ok(audit.plan.some((entry) => (
      entry.code === 'ASC_APP_STORE_VERSION_NOT_ADOPTABLE'
      && entry.action === 'unresolved'
    )), state);
    assert.equal(audit.plan.some((entry) => (
      entry.target === 'appStoreVersion'
      && ['create', 'update'].includes(entry.action)
    )), false, state);
    assert.throws(
      () => assertEditableAppStoreVersionState(state),
      /ASC_VERSION_NOT_EDITABLE/u,
    );
  }
});
