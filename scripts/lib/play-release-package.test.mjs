import assert from 'node:assert/strict';
import {
  createHash,
  generateKeyPairSync,
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
  symlinkSync,
  utimesSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import { deflateSync } from 'node:zlib';
import test from 'node:test';
import './google-play-publisher-apply.test.mjs';
import {
  collectGooglePlayMetadata,
  DEFAULT_FRESHNESS_DEPENDENCIES,
  inspectAndroidBundle,
  inspectGoogleServiceAccount,
  inspectPublicContactSettings,
  parseAndroidBundleManifest,
  PLAY_LOCALES,
  PLAY_PACKAGE_NAME,
  PLAY_PRODUCT_IDS,
  PLAY_RELEASE_NOTE_MAX_CHARACTERS,
  PLAY_SCREENSHOT_NAMES,
  PLAY_SCREENSHOT_TARGETS,
  preparePlayReleasePackage,
  readPngMetadata,
  resolvePlayReleaseJavaEnvironment,
  runStoreScreenshotValidation,
  verifyBundleSignerPin,
  verifyPlayBundleRuntimeBoundaries,
  verifyPlayReleasePackage,
} from './play-release-package.mjs';

const OLD_TIME = new Date('2026-01-01T00:00:00.000Z');
const NEW_TIME = new Date('2026-01-02T00:00:00.000Z');
const FIXED_OUTPUT_TIME = Date.parse('2000-01-01T00:00:00.000Z');
const FRESHNESS = {
  bundle: ['deps/bundle.txt'],
  graphics: ['deps/graphics.txt'],
  screenshots: ['deps/screenshots.txt'],
};

test('official Play verification uses Android-only bounds and enough time', () => {
  let invocation = null;
  assert.equal(runStoreScreenshotValidation('/fixture', {
    env: { PATH: '/bin' },
    spawn: (...args) => {
      invocation = args;
      return { status: 0 };
    },
  }), true);
  assert.equal(invocation[0], process.execPath);
  assert.deepEqual(invocation[1], [
    'scripts/python.mjs',
    '-B',
    'apps/game/tools/build_store_graphics.py',
    '--check-play-screenshots',
  ]);
  assert.equal(invocation[1].includes('--check-screenshots'), false);
  assert.equal(invocation[2].timeout, 10 * 60 * 1000);
  assert.equal(invocation[2].killSignal, 'SIGTERM');
});

function sha256(contents) {
  return createHash('sha256').update(contents).digest('hex');
}

function write(root, relativePath, contents, time = OLD_TIME) {
  const destination = join(root, relativePath);
  mkdirSync(dirname(destination), { recursive: true });
  writeFileSync(destination, contents);
  utimesSync(destination, time, time);
  return destination;
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

function png(width, height, colorType, unique) {
  const cacheKey = `${width}x${height}:${colorType}:${unique}`;
  if (TEST_PNG_CACHE.has(cacheKey)) {
    return Buffer.from(TEST_PNG_CACHE.get(cacheKey));
  }
  const channels = colorType === 2 ? 3 : 4;
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = colorType;
  const raw = Buffer.alloc((width * channels + 1) * height);
  createHash('sha256').update(String(unique)).digest().copy(raw, 1, 0, channels);
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

function csvEscape(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

function csvRow(values) {
  return values.map(csvEscape).join(',');
}

function localizationCsv() {
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
  const rows = [csvRow(header)];
  for (const locale of PLAY_LOCALES) {
    rows.push(csvRow([
      'app',
      'google',
      locale,
      '',
      '',
      '',
      `Moonlit ${locale}`,
      `Short description ${locale}`,
      '',
      '',
      '',
      '',
      '',
    ]));
  }
  for (const locale of PLAY_LOCALES) {
    for (const productId of PLAY_PRODUCT_IDS) {
      const suffix = productId.slice(PLAY_PACKAGE_NAME.length + 1);
      rows.push(csvRow([
        'iap',
        'google',
        locale,
        productId,
        'non_consumable',
        suffix,
        `${suffix} ${locale}`,
        '',
        '',
        '',
        '',
        `${suffix} description ${locale}`,
        '',
      ]));
    }
  }
  return `${rows.join('\n')}\n`;
}

function storePage() {
  return [
    '# Store',
    '',
    '## Korean description',
    '',
    '```text',
    'Korean full description.',
    '```',
    '',
    '## English description',
    '',
    '```text',
    'English full description.',
    '```',
    '',
    '## Japanese description',
    '',
    '```text',
    '日本語の完全な説明です。',
    '```',
    '',
    '## Simplified Chinese description',
    '',
    '```text',
    '这是简体中文完整说明。',
    '```',
    '',
    '## Traditional Chinese description',
    '',
    '```text',
    '這是繁體中文完整說明。',
    '```',
    '',
    '### itch.io copy-paste block',
    '',
    '```text',
    'This nested section block is not part of the full description.',
    '```',
    '',
    '## Google Play release notes — English (`en-US`)',
    '',
    '```text',
    'English release notes.',
    '```',
    '',
    '## Google Play release notes — Korean (`ko-KR`)',
    '',
    '```text',
    'Korean release notes.',
    '```',
    '',
    '## Google Play release notes — Japanese (`ja-JP`)',
    '',
    '```text',
    '日本語のリリースノートです。',
    '```',
    '',
    '## Google Play release notes — Simplified Chinese (`zh-CN`)',
    '',
    '```text',
    '这是简体中文发布说明。',
    '```',
    '',
    '## Google Play release notes — Traditional Chinese (`zh-TW`)',
    '',
    '```text',
    '這是繁體中文發佈說明。',
    '```',
    '',
  ].join('\n');
}

function projectGodot({ contacts = false } = {}) {
  return [
    'config_version=5',
    '',
    '[application]',
    '',
    'config/version="1.0.0"',
    'config/name_localized={',
    '"en": "Moonlit Beacon",',
    '"ja": "月明かりの烽火",',
    '"ko": "달빛 봉화",',
    '"zh": "月光烽火",',
    '"zh_TW": "月光烽火"',
    '}',
    contacts
      ? 'config/privacy_policy_url="https://support.example.com/{locale}/privacy"'
      : 'config/privacy_policy_url=""',
    contacts
      ? 'config/support_contact="https://support.example.com/{locale}/support"'
      : 'config/support_contact=""',
    '',
  ].join('\n');
}

function exportPresets() {
  return [
    '[preset.0]',
    'name="Android"',
    'version/code=1',
    'version/name="1.0.0"',
    `package/unique_name="${PLAY_PACKAGE_NAME}"`,
    '',
    '[preset.1]',
    'name="Android Play"',
    'version/code=1',
    'version/name="1.0.0"',
    `package/unique_name="${PLAY_PACKAGE_NAME}"`,
    '',
  ].join('\n');
}

function bundleInspection() {
  return {
    manifest: {
      packageName: PLAY_PACKAGE_NAME,
      versionCode: 1,
      versionName: '1.0.0',
    },
    signing: {
      certificateSha256: 'a'.repeat(64),
      signatureScheme: 'JAR',
      subject: 'CN=Moonlit Beacon Upload',
      validTo: '2053-12-15T00:00:00.000Z',
      pinnedToConfiguredReleaseKey: true,
      verified: true,
    },
  };
}

function fixture({ contacts = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-play-package-'));
  write(root, 'deps/bundle.txt', 'bundle dependency');
  write(root, 'deps/graphics.txt', 'graphics dependency');
  write(root, 'deps/screenshots.txt', 'screenshot dependency');
  write(root, 'scripts/lib/play-release-package.mjs', 'package generator');
  write(root, 'scripts/prepare-play-release.mjs', 'package cli');
  write(
    root,
    'notes/release/store-localizations.csv',
    localizationCsv(),
    NEW_TIME,
  );
  write(root, 'notes/release/store-page.md', storePage(), NEW_TIME);
  write(
    root,
    'apps/game/project.godot',
    projectGodot({ contacts }),
    NEW_TIME,
  );
  write(
    root,
    'apps/game/export_presets.cfg',
    exportPresets(),
    NEW_TIME,
  );
  write(root, 'builds/android/MoonlitBeacon.aab', 'signed-aab', NEW_TIME);
  write(
    root,
    'notes/release/store-assets/play/icon-512.png',
    png(512, 512, 6, 'icon'),
    NEW_TIME,
  );
  write(
    root,
    'notes/release/store-assets/play/feature-graphic-1024x500.png',
    png(1024, 500, 2, 'feature'),
    NEW_TIME,
  );
  for (const locale of PLAY_LOCALES) {
    for (const target of PLAY_SCREENSHOT_TARGETS) {
      for (const [index, name] of PLAY_SCREENSHOT_NAMES.entries()) {
        write(
          root,
          `builds/release/play/${locale}/${target.directory}/${name}`,
          png(
            target.width,
            target.height,
            2,
            `${locale}-${target.imageType}-${index}`,
          ),
          NEW_TIME,
        );
      }
    }
  }
  return root;
}

function prepare(root, options = {}) {
  return preparePlayReleasePackage({
    env: {},
    freshnessDependencies: FRESHNESS,
    inspectBundle: () => bundleInspection(),
    root,
    validateScreenshots: () => true,
    ...options,
  });
}

function verify(root, output = join(root, 'builds/release/google-play-upload'), options = {}) {
  return verifyPlayReleasePackage(output, {
    env: {},
    inspectBundle: () => bundleInspection(),
    root,
    ...options,
  });
}

function replaceH2Section(source, heading, replacement) {
  const start = source.indexOf(heading);
  assert.notEqual(start, -1, `${heading} fixture heading`);
  const next = source.indexOf('\n## ', start + heading.length);
  const end = next < 0 ? source.length : next;
  return `${source.slice(0, start)}${replacement}${source.slice(end)}`;
}

function allFiles(root) {
  const files = new Map();
  function visit(directory) {
    for (const name of readdirSync(directory).sort()) {
      const absolutePath = join(directory, name);
      const info = lstatSync(absolutePath);
      if (info.isDirectory()) {
        visit(absolutePath);
      } else {
        files.set(relative(root, absolutePath), {
          contents: readFileSync(absolutePath),
          mode: info.mode & 0o777,
          mtimeMs: info.mtimeMs,
        });
      }
    }
  }
  visit(root);
  return files;
}

function encodeVarint(value) {
  const bytes = [];
  let remaining = BigInt(value);
  do {
    let byte = Number(remaining & 0x7fn);
    remaining >>= 7n;
    if (remaining > 0n) byte |= 0x80;
    bytes.push(byte);
  } while (remaining > 0n);
  return Buffer.from(bytes);
}

function protoField(number, value) {
  const contents = Buffer.isBuffer(value) ? value : Buffer.from(value);
  return Buffer.concat([
    encodeVarint((number << 3) | 2),
    encodeVarint(contents.length),
    contents,
  ]);
}

function manifestAttribute(name, value) {
  return protoField(4, Buffer.concat([
    protoField(2, name),
    protoField(3, value),
  ]));
}

function manifestProto({ packageName, versionCode, versionName }) {
  const element = Buffer.concat([
    protoField(3, 'manifest'),
    manifestAttribute('package', packageName),
    manifestAttribute('versionCode', String(versionCode)),
    manifestAttribute('versionName', versionName),
  ]);
  return Buffer.concat([protoField(1, element), protoField(3, Buffer.from([8, 2]))]);
}

test('builds 5 locales, 90 phone/7-inch/10-inch shots, AAB, and 35 IAP payloads per API boundary', () => {
  assert.deepEqual(
    PLAY_SCREENSHOT_TARGETS.map(({ imageType, width, height }) => ({
      imageType,
      width,
      height,
    })),
    [
      { imageType: 'phoneScreenshots', width: 1920, height: 1080 },
      { imageType: 'sevenInchScreenshots', width: 1920, height: 1080 },
      { imageType: 'tenInchScreenshots', width: 2560, height: 1440 },
    ],
  );
  const root = fixture();
  try {
    const manifest = prepare(root);
    const output = join(root, 'builds/release/google-play-upload');

    assert.equal(manifest.packageName, PLAY_PACKAGE_NAME);
    assert.equal(manifest.release.versionName, '1.0.0');
    assert.equal(manifest.release.versionCode, 1);
    assert.equal(manifest.release.signing.verified, true);
    assert.equal(manifest.counts.localeCount, 5);
    assert.equal(manifest.counts.listingPayloads, 5);
    assert.equal(manifest.counts.phoneScreenshots, 30);
    assert.equal(manifest.counts.sevenInchScreenshots, 30);
    assert.equal(manifest.counts.tenInchScreenshots, 30);
    assert.equal(manifest.counts.storeGraphics, 10);
    assert.equal(manifest.counts.imageDeleteAllOperations, 25);
    assert.equal(manifest.counts.imageOperations, 100);
    assert.equal(manifest.counts.oneTimeProductPayloads, 7);
    assert.equal(manifest.counts.oneTimeProductLocalizations, 35);
    assert.equal(manifest.counts.releaseNoteLocalizations, 5);
    assert.equal(manifest.counts.payloadFiles, 123);
    assert.equal(manifest.files.length, 123);
    assert.equal(
      readFileSync(
        join(output, '.moonlit-play-release-package'),
        'utf8',
      ),
      'moonlit-beacon-google-play-release-package-v1\n',
    );

    const listing = JSON.parse(readFileSync(
      join(
        output,
        'publisher-api/edits.listings.update/ko-KR.json',
      ),
      'utf8',
    ));
    assert.equal(listing.apiBoundary, 'edits.listings.update');
    assert.equal(listing.method, 'PUT');
    assert.equal(listing.body.language, 'ko-KR');
    assert.match(listing.body.fullDescription, /Korean/);
    assert.equal(listing.remoteApplyAllowed, false);

    const releaseNotes = JSON.parse(readFileSync(
      join(
        output,
        'publisher-api/edits.tracks.update/release-notes.json',
      ),
      'utf8',
    ));
    assert.equal(releaseNotes.apiBoundary, 'edits.tracks.update');
    assert.equal(releaseNotes.track, null);
    assert.equal(releaseNotes.requestCompleteness.complete, false);
    assert.deepEqual(
      releaseNotes.futureTrackReleaseFragment.releaseNotes.map(
        ({ language }) => language,
      ),
      PLAY_LOCALES,
    );
    assert.ok(releaseNotes.futureTrackReleaseFragment.releaseNotes.every(
      ({ text }) => [...text].length <= PLAY_RELEASE_NOTE_MAX_CHARACTERS,
    ));
    assert.equal(releaseNotes.remoteApplyAllowed, false);
    assert.equal(
      readFileSync(join(output, 'copy/release-notes/ko-KR.txt'), 'utf8'),
      'Korean release notes.\n',
    );
    assert.deepEqual(
      manifest.releaseNotes.localizations.map(({ language }) => language),
      PLAY_LOCALES,
    );
    assert.equal(manifest.releaseNotes.remoteApplyAllowed, false);
    assert.equal(manifest.releaseNotes.trackSelected, false);

    const images = JSON.parse(readFileSync(
      join(
        output,
        'publisher-api/edits.images.upload/operations.json',
      ),
      'utf8',
    ));
    assert.equal(images.resetBeforeUpload.length, 25);
    assert.ok(images.resetBeforeUpload.every((operation) =>
      operation.apiBoundary === 'edits.images.deleteall'
      && operation.remoteApplyAllowed === false));
    assert.equal(images.uploadOperations.length, 100);
    assert.equal(
      images.uploadOperations.filter((operation) =>
        operation.imageType === 'phoneScreenshots').length,
      30,
    );
    assert.equal(
      images.uploadOperations.filter((operation) =>
        operation.imageType === 'sevenInchScreenshots').length,
      30,
    );
    assert.equal(
      images.uploadOperations.filter((operation) =>
        operation.imageType === 'tenInchScreenshots').length,
      30,
    );
    assert.ok(images.uploadOperations.every((operation) =>
      operation.remoteApplyAllowed === false));

    for (const productId of PLAY_PRODUCT_IDS) {
      const suffix = productId.slice(PLAY_PACKAGE_NAME.length + 1);
      const product = JSON.parse(readFileSync(
        join(
          output,
          `publisher-api/monetization.onetimeproducts/${suffix}.patch.json`,
        ),
        'utf8',
      ));
      assert.equal(
        product.apiBoundary,
        'monetization.onetimeproducts.patch',
      );
      assert.equal(product.query.updateMask, 'listings');
      assert.equal(product.query.allowMissing, false);
      assert.equal(product.query.regionsVersion, null);
      assert.equal(product.requestCompleteness.complete, false);
      assert.equal(product.body.productId, productId);
      assert.equal(product.body.listings.length, 5);
      assert.deepEqual(
        product.body.listings.map(({ languageCode }) => languageCode),
        PLAY_LOCALES,
      );
      assert.equal(product.remoteApplyAllowed, false);
    }

    assert.equal(manifest.gates.googlePlayLegalDeclarations.ready, false);
    assert.equal(manifest.gates.googleServiceAccount.state, 'missing');
    assert.equal(manifest.gates.publicContact.ready, false);
    assert.equal(manifest.gates.oneTimeProductSetup.ready, false);
    assert.equal(
      manifest.gates.oneTimeProductSetup.regionsVersionConfigured,
      false,
    );
    assert.equal(
      manifest.gates.oneTimeProductSetup.pricingAndAvailabilityConfigured,
      false,
    );
    assert.equal(
      manifest.gates.publicContact.aabRebuildRequiredAfterConfiguration,
      true,
    );
    assert.equal(manifest.gates.remoteActionsReady, false);
    assert.equal(manifest.release.finalSubmissionAab, false);
    assert.equal(manifest.apiApplication.implemented, false);
    assert.equal(manifest.apiApplication.remoteApplyAllowed, false);
    for (const path of [
      'scripts/lib/play-release-package.mjs',
      'scripts/prepare-play-release.mjs',
    ]) {
      const input = manifest.inputs.find((candidate) => candidate.path === path);
      assert.ok(input, path);
      assert.equal(input.sha256, sha256(readFileSync(join(root, path))));
    }
    assert.deepEqual(verify(root, output), manifest);
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test('Google Play release notes enforce structure, TODO, and a 500 Unicode-char limit', () => {
  const root = fixture();
  try {
    const storePagePath = join(root, 'notes/release/store-page.md');
    const source = readFileSync(storePagePath, 'utf8');
    writeFileSync(
      storePagePath,
      source.replace('English release notes.', '🌙'.repeat(501)),
    );
    assert.throws(
      () => prepare(root),
      /en-US Google Play release notes length must be 1~500/,
    );

    writeFileSync(
      storePagePath,
      source.replace('English release notes.', '🌙'.repeat(500)),
    );
    const exactLimit = prepare(root);
    assert.equal(exactLimit.releaseNotes.localizations[0].characters, 500);

    writeFileSync(
      storePagePath,
      source.replace(
        '## Google Play release notes — Traditional Chinese (`zh-TW`)',
        '## Missing release notes',
      ),
    );
    assert.throws(
      () => prepare(root),
      /zh-TW.+heading is missing/,
    );

    const englishHeading =
      '## Google Play release notes — English (`en-US`)';
    writeFileSync(
      storePagePath,
      `${source}\n${englishHeading}\n\n\`\`\`text\nduplicate copy\n\`\`\`\n`,
    );
    assert.throws(
      () => prepare(root),
      /en-US.+heading is duplicated/,
    );

    writeFileSync(
      storePagePath,
      source.replace(
        'English release notes.\n```',
        'English release notes.\nUnclosed block',
      ),
    );
    assert.throws(
      () => prepare(root),
      /en-US.+text block is not closed/,
    );

    writeFileSync(
      storePagePath,
      source.replace('English release notes.', 'TODO release notes'),
    );
    assert.throws(
      () => prepare(root),
      /en-US.+unfinished copy/,
    );
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test('release notes parser does not accept a fenced heading or a bad fence', () => {
  const csv = localizationCsv();
  const source = storePage();
  const heading = '## Google Play release notes — English (`en-US`)';

  const fencedSample = [
    '## Sample',
    '',
    '```text',
    heading,
    '```',
    '',
    source,
  ].join('\n');
  assert.doesNotThrow(() => collectGooglePlayMetadata(csv, fencedSample));

  const fakeHeadingOnly = replaceH2Section(source, heading, [
    '## Unrelated example',
    '',
    '```text',
    heading,
    '```',
    '',
    '```text',
    'Wrongly selected copy',
    '```',
  ].join('\n'));
  assert.throws(
    () => collectGooglePlayMetadata(csv, fakeHeadingOnly),
    /en-US.+heading is missing/,
  );

  for (const malformed of [
    [heading, '', '````text', 'Malformed copy', '```', ''].join('\n'),
    [
      heading,
      '',
      '```text',
      'Looks-clean prefix',
      '```suffix',
      'TODO hidden',
      '',
    ].join('\n'),
  ]) {
    assert.throws(
      () => collectGooglePlayMetadata(
        csv,
        replaceH2Section(source, heading, malformed),
      ),
      /en-US.+text block is not closed/,
    );
  }

  const duplicateBlocks = replaceH2Section(source, heading, [
    heading,
    '',
    '```text',
    'Old copy',
    '```',
    '',
    '```text',
    'New copy',
    '```',
  ].join('\n'));
  assert.throws(
    () => collectGooglePlayMetadata(csv, duplicateBlocks),
    /en-US.+text block is duplicated/,
  );
});

test('manifest hash pins every payload and rejects tampering', () => {
  const root = fixture();
  try {
    let manifest = prepare(root);
    const output = join(root, 'builds/release/google-play-upload');
    let bundle = manifest.files.find((file) =>
      file.role === 'android-app-bundle');
    assert.equal(bundle.sha256, sha256(Buffer.from('signed-aab')));
    assert.equal(
      sha256(readFileSync(join(output, bundle.path))),
      bundle.sha256,
    );

    writeFileSync(join(output, bundle.path), 'tampered');
    assert.throws(
      () => verify(root, output),
      /hash differs/,
    );

    manifest = prepare(root);
    bundle = manifest.files.find((file) =>
      file.role === 'android-app-bundle');
    bundle.sha256 = '0'.repeat(64);
    writeFileSync(
      join(output, 'manifest.json'),
      `${JSON.stringify(manifest, null, 2)}\n`,
    );
    assert.throws(
      () => verify(root, output),
      /hash differs/,
    );

    manifest = prepare(root);
    manifest.counts.payloadFiles += 1;
    writeFileSync(
      join(output, 'manifest.json'),
      `${JSON.stringify(manifest, null, 2)}\n`,
    );
    assert.throws(
      () => verify(root, output),
      /schema, package, locale, or count contract differs/,
    );

    manifest = prepare(root);
    rmSync(join(output, '.moonlit-play-release-package'));
    manifest.files = manifest.files.filter(
      (file) => file.role !== 'ownership-marker',
    );
    manifest.counts.payloadFiles = manifest.files.length;
    writeFileSync(
      join(output, 'manifest.json'),
      `${JSON.stringify(manifest, null, 2)}\n`,
    );
    assert.throws(
      () => verify(root, output),
      /no dedicated ownership marker; keeping it/,
    );
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test('verifier rejects a self-consistent shrunk manifest and a bad role/work plan', () => {
  const root = fixture();
  const output = join(root, 'builds/release/google-play-upload');
  const writeManifest = (manifest) => writeFileSync(
    join(output, 'manifest.json'),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
  const rewritePayload = (manifest, payloadPath, contents) => {
    const bytes = Buffer.isBuffer(contents) ? contents : Buffer.from(contents);
    writeFileSync(join(output, payloadPath), bytes);
    const record = manifest.files.find((file) => file.path === payloadPath);
    assert.ok(record, payloadPath);
    record.bytes = bytes.length;
    record.sha256 = sha256(bytes);
    writeManifest(manifest);
  };
  const rewriteJsonPayload = (manifest, payloadPath, mutate) => {
    const payload = JSON.parse(readFileSync(join(output, payloadPath), 'utf8'));
    mutate(payload);
    rewritePayload(
      manifest,
      payloadPath,
      `${JSON.stringify(payload, null, 2)}\n`,
    );
  };
  try {
    for (const mutate of [
      (manifest) => { manifest.schemaVersion += 1; },
      (manifest) => { manifest.packageName = 'com.example.forged'; },
      (manifest) => { manifest.locales = manifest.locales.slice(0, -1); },
      (manifest) => { manifest.counts.sevenInchScreenshots = 29; },
    ]) {
      const manifest = prepare(root);
      mutate(manifest);
      writeManifest(manifest);
      assert.throws(
        () => verify(root, output),
        /schema, package, locale, or count contract differs/,
      );
    }

    let manifest = prepare(root);
    const removed = manifest.files.find(
      (file) => file.role === 'phone-screenshot',
    );
    assert.ok(removed);
    rmSync(join(output, removed.path));
    manifest.files = manifest.files.filter((file) => file !== removed);
    manifest.counts.payloadFiles = manifest.files.length;
    manifest.counts.phoneScreenshots -= 1;
    writeManifest(manifest);
    assert.throws(
      () => verify(root, output),
      /schema, package, locale, or count contract differs/,
    );

    manifest = prepare(root);
    const roleRecord = manifest.files.find(
      (file) => file.role === 'ten-inch-tablet-screenshot',
    );
    assert.ok(roleRecord);
    roleRecord.role = 'phone-screenshot';
    writeManifest(manifest);
    assert.throws(
      () => verify(root, output),
      /manifest payload contract differs/,
    );

    manifest = prepare(root);
    const planPath = join(
      output,
      'publisher-api/edits.images.upload/operations.json',
    );
    const plan = JSON.parse(readFileSync(planPath, 'utf8'));
    plan.uploadOperations.pop();
    const planBytes = Buffer.from(`${JSON.stringify(plan, null, 2)}\n`);
    writeFileSync(planPath, planBytes);
    const planRecord = manifest.files.find(
      (file) => file.role === 'image-upload-plan',
    );
    assert.ok(planRecord);
    planRecord.bytes = planBytes.length;
    planRecord.sha256 = sha256(planBytes);
    writeManifest(manifest);
    assert.throws(
      () => verify(root, output),
      /image operation plan semantic payload contract differs/,
    );

    for (const scenario of [
      {
        error: /bundle upload operation semantic payload/,
        mutate: (payload) => { payload.pathTemplate = '/wrong/bundle'; },
        path: 'publisher-api/edits.bundles.upload/operation.json',
      },
      {
        error: /en-US Google Play listing semantic payload/,
        mutate: (payload) => { payload.method = 'POST'; },
        path: 'publisher-api/edits.listings.update/en-US.json',
      },
      {
        error: /release-note track fragment semantic payload/,
        mutate: (payload) => { payload.track = 'production'; },
        path: 'publisher-api/edits.tracks.update/release-notes.json',
      },
      {
        error: /hero_dancer.+one-time product patch semantic payload/,
        mutate: (payload) => { payload.query.allowMissing = true; },
        path: 'publisher-api/monetization.onetimeproducts/hero_dancer.patch.json',
      },
      {
        error: /one-time product operation plan semantic payload/,
        mutate: (payload) => { payload.operations[0].updateMask = '*'; },
        path: 'publisher-api/monetization.onetimeproducts/operations.json',
      },
      {
        error: /image operation plan semantic payload/,
        mutate: (payload) => {
          payload.uploadOperations[0].pathTemplate = '/wrong/image-upload';
        },
        path: 'publisher-api/edits.images.upload/operations.json',
      },
    ]) {
      manifest = prepare(root);
      rewriteJsonPayload(manifest, scenario.path, scenario.mutate);
      assert.throws(() => verify(root, output), scenario.error);
    }

    const screenshotPath =
      'publisher-api/edits.images.upload/en-US/'
      + 'phoneScreenshots/01-moonlight-barrage.png';
    manifest = prepare(root);
    rewritePayload(manifest, screenshotPath, Buffer.from('not-a-png'));
    assert.throws(
      () => verify(root, output),
      /PNG signature or length is invalid/,
    );

    manifest = prepare(root);
    rewritePayload(
      manifest,
      screenshotPath,
      png(1280, 720, 2, 'wrong-package-dimensions'),
    );
    assert.throws(
      () => verify(root, output),
      /(?:width=1280; expected 1920|height=720; expected 1080)/,
    );

    manifest = prepare(root);
    const duplicateSource =
      'publisher-api/edits.images.upload/en-US/'
      + 'phoneScreenshots/02-field-guardian.png';
    rewritePayload(
      manifest,
      screenshotPath,
      readFileSync(join(output, duplicateSource)),
    );
    assert.throws(
      () => verify(root, output),
      /package screenshot is duplicated/,
    );

    manifest = prepare(root);
    assert.throws(
      () => verify(root, output, {
        inspectBundle: () => ({
          ...bundleInspection(),
          manifest: {
            ...bundleInspection().manifest,
            versionCode: 2,
          },
        }),
      }),
      /manifest release semantic payload contract differs/,
    );
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test('rejects missing locale screenshots and does not leave previous output', () => {
  const root = fixture();
  try {
    const missing = join(
      root,
      'builds/release/play/ja-JP/screenshots/04-title.png',
    );
    rmSync(missing);
    assert.throws(
      () => prepare(root),
      /phoneScreenshots must have exactly the contracted 6 images/,
    );
    assert.equal(
      readdirSync(join(root, 'builds/release/play/ja-JP/screenshots')).length,
      5,
    );
    assert.throws(
      () => lstatSync(join(root, 'builds/release/google-play-upload')),
      { code: 'ENOENT' },
    );
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test('does not accept a truncated PNG, CRC tamper, or IDAT damage as a release image', () => {
  const valid = png(512, 512, 6, 'valid-icon');
  assert.deepEqual(readPngMetadata(valid), {
    bitDepth: 8,
    colorType: 6,
    height: 512,
    width: 512,
  });
  assert.throws(
    () => readPngMetadata(valid.subarray(0, 33)),
    /signature or length|IHDR, IDAT, and IEND/u,
  );

  const crcCorrupt = Buffer.from(valid);
  crcCorrupt[crcCorrupt.length - 1] ^= 0xff;
  assert.throws(() => readPngMetadata(crcCorrupt), /CRC/u);

  const idatCorrupt = Buffer.from(valid);
  const idatOffset = idatCorrupt.indexOf(Buffer.from('IDAT', 'ascii'));
  idatCorrupt[idatOffset + 8] ^= 0xff;
  const typeAndDataStart = idatOffset;
  const dataLength = idatCorrupt.readUInt32BE(idatOffset - 4);
  const typeAndData = idatCorrupt.subarray(
    typeAndDataStart,
    typeAndDataStart + 4 + dataLength,
  );
  idatCorrupt.writeUInt32BE(
    testPngCrc32(typeAndData),
    typeAndDataStart + 4 + dataLength,
  );
  assert.throws(() => readPngMetadata(idatCorrupt), /inflate PNG IDAT/u);
});

test('rejects an AAB, graphic, or screenshot older than its dependencies separately', () => {
  for (const scenario of [
    {
      artifact: 'builds/android/MoonlitBeacon.aab',
      dependency: 'deps/bundle.txt',
      message: /Android App Bundle input is stale/,
    },
    {
      artifact: 'notes/release/store-assets/play/icon-512.png',
      dependency: 'deps/graphics.txt',
      message: /Google Play graphics input is stale/,
    },
    {
      artifact:
        'builds/release/play/zh-TW/screenshots/06-hero-preview.png',
      dependency: 'deps/screenshots.txt',
      message: /Google Play screenshots input is stale/,
    },
  ]) {
    const root = fixture();
    try {
      utimesSync(join(root, scenario.artifact), OLD_TIME, OLD_TIME);
      utimesSync(
        join(root, scenario.dependency),
        NEW_TIME,
        NEW_TIME,
      );
      assert.throws(() => prepare(root), scenario.message);
    } finally {
      rmSync(root, { force: true, recursive: true });
    }
  }
});

test('invalidates the previous upload tree on stale or official screenshot verification failure', () => {
  const root = fixture();
  const output = join(root, 'builds/release/google-play-upload');
  try {
    prepare(root);
    assert.ok(lstatSync(output).isDirectory());
    utimesSync(
      join(root, 'deps/bundle.txt'),
      new Date('2026-01-03T00:00:00.000Z'),
      new Date('2026-01-03T00:00:00.000Z'),
    );
    assert.throws(() => prepare(root), /input is stale/);
    assert.throws(() => lstatSync(output), { code: 'ENOENT' });

    utimesSync(join(root, 'deps/bundle.txt'), OLD_TIME, OLD_TIME);
    prepare(root);
    assert.throws(
      () => prepare(root, {
        validateScreenshots: () => {
          throw new Error('official screenshot validator failed');
        },
      }),
      /official screenshot validator failed/,
    );
    assert.throws(() => lstatSync(output), { code: 'ENOENT' });
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test('rejects output path traversal and symbolic-link inputs', () => {
  const root = fixture();
  const outside = write(
    dirname(root),
    `${root.split('/').at(-1)}-outside.png`,
    png(1920, 1080, 2, 'outside'),
    NEW_TIME,
  );
  try {
    assert.throws(
      () => prepare(root, { outputRelative: '../escaped-output' }),
      /path-escape/,
    );
    assert.throws(
      () => lstatSync(join(dirname(root), 'escaped-output')),
      { code: 'ENOENT' },
    );

    const screenshot = join(
      root,
      'builds/release/play/en-US/screenshots/01-moonlight-barrage.png',
    );
    rmSync(screenshot);
    symlinkSync(outside, screenshot);
    assert.throws(
      () => prepare(root),
      /symbolic link/,
    );
  } finally {
    rmSync(outside, { force: true });
    rmSync(root, { force: true, recursive: true });
  }
});

test('keeps paths outside the dedicated prefix and existing folders without an ownership marker', () => {
  const root = fixture();
  try {
    const victim = write(root, 'victim/keep.txt', 'do not delete');
    assert.throws(
      () => prepare(root, { outputRelative: 'victim' }),
      /builds\/release\/google-play-upload/,
    );
    assert.equal(readFileSync(victim, 'utf8'), 'do not delete');

    const unowned = write(
      root,
      'builds/release/google-play-upload-unowned/keep.txt',
      'still here',
    );
    assert.throws(
      () => prepare(root, {
        outputRelative: 'builds/release/google-play-upload-unowned',
      }),
      /no dedicated ownership marker; keeping/,
    );
    assert.equal(readFileSync(unowned, 'utf8'), 'still here');
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test('publish also keeps unowned output that appeared late during verification', () => {
  const root = fixture();
  const output = join(root, 'builds/release/google-play-upload');
  try {
    assert.throws(
      () => prepare(root, {
        inspectServiceAccount: () => {
          write(root, 'builds/release/google-play-upload/keep.txt', 'keep');
          return { ready: false, state: 'missing' };
        },
      }),
      /no dedicated ownership marker; keeping/,
    );
    assert.equal(readFileSync(join(output, 'keep.txt'), 'utf8'), 'keep');
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test('an active generation lock does not touch output', () => {
  const root = fixture({ contacts: true });
  const output = join(root, 'builds/release/google-play-upload');
  const lock = `${output}.generation.lock`;
  try {
    const first = prepare(root);
    writeFileSync(lock, 'active generator\n');
    assert.throws(
      () => prepare(root),
      (error) => {
        assert.match(error.message, /Another Google Play package is being generated/u);
        assert.ok(error.message.includes(lock));
        return true;
      },
    );
    assert.deepEqual(verify(root, output), first);
    assert.equal(readFileSync(lock, 'utf8'), 'active generator\n');
    assert.equal(
      readdirSync(join(root, 'builds/release')).filter((name) =>
        name.startsWith('google-play-upload.partial-')).length,
      0,
    );
  } finally {
    rmSync(lock, { force: true });
    rmSync(root, { force: true, recursive: true });
  }
});

test('publish failure invalidates output and cleans the lock and staging', () => {
  const root = fixture({ contacts: true });
  const output = join(root, 'builds/release/google-play-upload');
  try {
    prepare(root);
    assert.throws(
      () => prepare(root, {
        publishOutput: () => {
          throw new Error('publish interrupted');
        },
      }),
      /publish interrupted/,
    );
    assert.equal(existsSync(output), false);
    assert.equal(existsSync(`${output}.generation.lock`), false);
    assert.equal(
      readdirSync(join(root, 'builds/release')).filter((name) =>
        name.startsWith('google-play-upload.partial-')).length,
      0,
    );
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test('same inputs are byte-identical regardless of output path and run time', () => {
  const root = fixture({ contacts: true });
  try {
    prepare(root, {
      outputRelative: 'builds/release/google-play-upload-a',
    });
    const first = allFiles(
      join(root, 'builds/release/google-play-upload-a'),
    );
    prepare(root, {
      outputRelative: 'builds/release/google-play-upload-b',
    });
    const second = allFiles(
      join(root, 'builds/release/google-play-upload-b'),
    );

    assert.deepEqual([...first.keys()], [...second.keys()]);
    for (const [path, firstFile] of first) {
      const secondFile = second.get(path);
      assert.deepEqual(firstFile.contents, secondFile.contents, path);
      assert.equal(firstFile.mode, 0o644, path);
      assert.equal(secondFile.mode, 0o644, path);
      assert.equal(firstFile.mtimeMs, FIXED_OUTPUT_TIME, path);
      assert.equal(secondFile.mtimeMs, FIXED_OUTPUT_TIME, path);
    }
    const manifest = JSON.parse(first.get('manifest.json').contents);
    assert.equal(manifest.gates.publicContact.ready, true);
    assert.equal(manifest.release.finalSubmissionAab, true);
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test('service account gates only a mode-0600 regular file outside the repo, without the secret', () => {
  const container = mkdtempSync(join(tmpdir(), 'moonlit-play-credential-'));
  const root = join(container, 'repo');
  mkdirSync(root);
  const credential = join(container, 'service-account.json');
  const generated = generateKeyPairSync('rsa', { modulusLength: 2_048 });
  const privateKey = generated.privateKey.export({
    format: 'pem',
    type: 'pkcs8',
  }).toString();
  const serviceAccount = {
    client_email:
      'publisher@moonlit-beacon-test.iam.gserviceaccount.com',
    private_key: privateKey,
    private_key_id: 'a'.repeat(40),
    project_id: 'moonlit-beacon-test',
    token_uri: 'https://oauth2.googleapis.com/token',
    type: 'service_account',
  };
  writeFileSync(credential, JSON.stringify(serviceAccount));
  chmodSync(credential, 0o600);

  try {
    const ready = inspectGoogleServiceAccount({
      env: { GOOGLE_APPLICATION_CREDENTIALS: credential },
      root,
    });
    assert.equal(ready.state, 'ready');
    assert.equal(ready.ready, true);
    assert.equal(ready.credentialMaterialIncluded, false);
    assert.doesNotMatch(
      JSON.stringify(ready),
      /BEGIN PRIVATE KEY|publisher@/,
    );

    chmodSync(credential, 0o644);
    const broad = inspectGoogleServiceAccount({
      env: { GOOGLE_APPLICATION_CREDENTIALS: credential },
      root,
    });
    assert.equal(broad.state, 'invalid');
    assert.equal(broad.reason, 'credential_permissions_exceed_0600');

    chmodSync(credential, 0o600);
    writeFileSync(credential, JSON.stringify({
      ...serviceAccount,
      private_key: [
        '-----BEGIN PRIVATE KEY-----',
        'not-a-real-private-key',
        '-----END PRIVATE KEY-----',
      ].join('\n'),
    }));
    const fakePem = inspectGoogleServiceAccount({
      env: { GOOGLE_APPLICATION_CREDENTIALS: credential },
      root,
    });
    assert.equal(fakePem.state, 'invalid');
    assert.equal(fakePem.ready, false);

    const inside = join(root, 'service-account.json');
    writeFileSync(inside, JSON.stringify(serviceAccount));
    chmodSync(inside, 0o600);
    const repositoryCredential = inspectGoogleServiceAccount({
      env: { GOOGLE_APPLICATION_CREDENTIALS: inside },
      root,
    });
    assert.equal(repositoryCredential.state, 'invalid');
    assert.equal(
      repositoryCredential.reason,
      'credential_must_be_outside_repository',
    );
  } finally {
    rmSync(container, { force: true, recursive: true });
  }
});

test('public contact allows only supported locale placeholders and a public HTTPS host', () => {
  const ready = inspectPublicContactSettings(projectGodot({ contacts: true }));
  assert.equal(ready.ready, true);

  const privateAddress = projectGodot({ contacts: true }).replace(
    'https://support.example.com/{locale}/privacy',
    'https://10.0.0.1/{locale}/privacy',
  );
  assert.equal(
    inspectPublicContactSettings(privateAddress).privacyPolicyConfigured,
    false,
  );

  const wrongPlaceholder = projectGodot({ contacts: true }).replace(
    'https://support.example.com/{locale}/support',
    'https://support.example.com/{language}/support',
  );
  assert.equal(
    inspectPublicContactSettings(wrongPlaceholder).supportContactConfigured,
    false,
  );

  for (const invalidSupport of [
    'https://support.example.com/support/{locale}',
    'https://support.example.com/en/support',
    'https://support.example.com/{locale}/support?draft=1',
    'https://other.example.com/{locale}/support',
  ]) {
    const source = projectGodot({ contacts: true }).replace(
      'https://support.example.com/{locale}/support',
      invalidSupport,
    );
    assert.equal(inspectPublicContactSettings(source).ready, false);
  }
});

test('AAB signer is compared against the pinned release keystore certificate', () => {
  let verified = false;
  const signing = {
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: 'secret',
    GODOT_ANDROID_KEYSTORE_RELEASE_PATH: '/secure/upload.jks',
    GODOT_ANDROID_KEYSTORE_RELEASE_USER: 'upload',
  };
  const credentialEnv = {
    PATH: '/usr/bin',
    GOOGLE_APPLICATION_CREDENTIALS: '/secure/google.json',
    IAPKIT_API_KEY: 'openiap-kit_pk_fixture',
    MOONLIT_ASC_PRIVATE_KEY: '/secure/AuthKey.p8',
  };
  assert.equal(verifyBundleSignerPin('/tmp/release.aab', {
    env: credentialEnv,
    platform: 'linux',
    resolveSigning: (options) => {
      assert.equal(options.root, '/repo');
      return signing;
    },
    root: '/repo',
    verifyReleaseSigner: (archivePath, options) => {
      verified = true;
      assert.equal(archivePath, '/tmp/release.aab');
      assert.equal(options.alias, 'upload');
      assert.equal(options.archiveType, 'aab');
      assert.equal(options.keystorePath, '/secure/upload.jks');
      assert.equal(options.password, 'secret');
      assert.deepEqual(options.env, { PATH: '/usr/bin' });
    },
  }), true);
  assert.equal(verified, true);

  const root = fixture();
  try {
    assert.throws(
      () => prepare(root, {
        inspectBundle: () => ({
          ...bundleInspection(),
          signing: {
            ...bundleInspection().signing,
            pinnedToConfiguredReleaseKey: false,
          },
        }),
      }),
      /specified release keystore/,
    );
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test('Play AAB checker child tools do not inherit release credentials', () => {
  const credentialEnv = {
    PATH: '/usr/bin',
    GOOGLE_APPLICATION_CREDENTIALS: '/secure/google.json',
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: 'secret',
    GODOT_ANDROID_KEYSTORE_RELEASE_PATH: '/secure/upload.jks',
    GODOT_ANDROID_KEYSTORE_RELEASE_USER: 'upload',
    IAPKIT_API_KEY: 'openiap-kit_pk_fixture',
    MOONLIT_ASC_ISSUER_ID: 'issuer',
    MOONLIT_ASC_KEY_ID: 'key',
    MOONLIT_ASC_PRIVATE_KEY: '/secure/AuthKey.p8',
  };
  const expectedChildEnv = { PATH: '/usr/bin' };
  let signerPinChecked = false;
  const result = inspectAndroidBundle('/tmp/release.aab', {
    env: credentialEnv,
    parseManifest: () => ({
      packageName: PLAY_PACKAGE_NAME,
      versionCode: 1,
      versionName: '1.0.0',
    }),
    platform: 'linux',
    readManifest: (path, options) => {
      assert.equal(path, '/tmp/release.aab');
      assert.deepEqual(options.env, expectedChildEnv);
      return Buffer.from('manifest');
    },
    readSigner: (path, options) => {
      assert.equal(path, '/tmp/release.aab');
      assert.deepEqual(options.env, expectedChildEnv);
      return { verified: true };
    },
    resolveJavaEnvironment: (options) => {
      assert.deepEqual(options.env, expectedChildEnv);
      return options.env;
    },
    root: '/repo',
    verifyRuntimeBoundaries: (path, options) => {
      assert.equal(path, '/tmp/release.aab');
      assert.deepEqual(options.env, expectedChildEnv);
    },
    verifySignerPin: (path, options) => {
      signerPinChecked = true;
      assert.equal(path, '/tmp/release.aab');
      assert.equal(options.env, credentialEnv);
      assert.deepEqual(options.childEnv, expectedChildEnv);
    },
  });
  assert.equal(signerPinChecked, true);
  assert.equal(result.signing.pinnedToConfiguredReleaseKey, true);
});

test('re-verifies AAB resource, IAP, and Billing boundaries immediately before Play upload', () => {
  const calls = [];
  const options = {
    env: { PATH: '/usr/bin' },
    spawn: () => {
      throw new Error('must not run real tools from the fixture.');
    },
    verifyResources: (path, received) => {
      calls.push(['resources', path, received]);
    },
    verifyLocalizedNames: (path, received) => {
      calls.push(['localized-names', path, received]);
    },
    verifyIap: (path, received) => {
      calls.push(['iap', path, received]);
    },
    verifyBilling: (path, received) => {
      calls.push(['billing', path, received]);
    },
  };
  assert.equal(
    verifyPlayBundleRuntimeBoundaries('/tmp/release.aab', options),
    true,
  );
  assert.deepEqual(
    calls.map(([name, path, received]) => [
      name,
      path,
      received.store ?? null,
      received.archiveType ?? null,
      received.env,
      received.spawn,
    ]),
    [
      ['resources', '/tmp/release.aab', null, null, options.env, options.spawn],
      [
        'localized-names',
        '/tmp/release.aab',
        null,
        'aab',
        options.env,
        options.spawn,
      ],
      ['iap', '/tmp/release.aab', true, null, options.env, options.spawn],
      ['billing', '/tmp/release.aab', true, null, options.env, options.spawn],
    ],
  );
});

test('Play release signer uses only the JDK 17 tools registered on macOS', () => {
  const source = {
    GOOGLE_APPLICATION_CREDENTIALS: '/secure/google.json',
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: 'secret',
    IAPKIT_API_KEY: 'openiap-kit_pk_fixture',
    JAVA_HOME: '/opt/homebrew/opt/openjdk@17',
    MOONLIT_ASC_PRIVATE_KEY: '/secure/AuthKey.p8',
    PATH: '/opt/homebrew/bin:/usr/bin',
  };
  const resolved = resolvePlayReleaseJavaEnvironment({
    env: source,
    exists: (path) => [
      '/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home/bin/keytool',
      '/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home/bin/jarsigner',
    ].includes(path),
    platform: 'darwin',
    spawn: (command, args, options) => {
      assert.equal(command, '/usr/libexec/java_home');
      assert.deepEqual(args, ['-v', '17']);
      assert.equal(options.timeout, 15_000);
      assert.equal('GOOGLE_APPLICATION_CREDENTIALS' in options.env, false);
      assert.equal(
        'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD' in options.env,
        false,
      );
      assert.equal('IAPKIT_API_KEY' in options.env, false);
      assert.equal('MOONLIT_ASC_PRIVATE_KEY' in options.env, false);
      return {
        error: undefined,
        status: 0,
        stdout:
          '/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home\n',
      };
    },
  });
  assert.equal(
    resolved.JAVA_HOME,
    '/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home',
  );
  assert.match(
    resolved.PATH,
    /^\/Library\/Java\/JavaVirtualMachines\/zulu-17\.jdk\/Contents\/Home\/bin:/,
  );
  assert.equal('GOOGLE_APPLICATION_CREDENTIALS' in resolved, false);
  assert.equal('GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD' in resolved, false);
  assert.equal('IAPKIT_API_KEY' in resolved, false);
  assert.equal('MOONLIT_ASC_PRIVATE_KEY' in resolved, false);
  assert.equal(
    source.JAVA_HOME,
    '/opt/homebrew/opt/openjdk@17',
    'does not mutate the caller environment',
  );

  assert.throws(
    () => resolvePlayReleaseJavaEnvironment({
      env: source,
      exists: () => false,
      platform: 'darwin',
      spawn: () => ({
        error: undefined,
        status: 0,
        stdout: '/missing/jdk17\n',
      }),
    }),
    /JDK 17 signing tools/,
  );
});

test('bundle freshness includes the full Android build chain and exported resources', () => {
  for (const dependency of [
    'package.json',
    'apps/game/default_bus_layout.tres',
    'apps/game/export_presets.cfg',
    'apps/game/icon.svg',
    'apps/game/icon.svg.import',
    'apps/game/resources',
    'scripts/android-build.mjs',
    'scripts/godot.mjs',
    'scripts/lib/android-build.mjs',
    'scripts/lib/android-release-signing.mjs',
    'scripts/lib/godot-export-preflight.mjs',
    'scripts/lib/iapkit-config.mjs',
    'scripts/lib/release-environment.mjs',
  ]) {
    assert.ok(
      DEFAULT_FRESHNESS_DEPENDENCIES.bundle.includes(dependency),
      `bundle freshness requires ${dependency}`,
    );
  }
  assert.ok(
    DEFAULT_FRESHNESS_DEPENDENCIES.screenshotRuntime.includes(
      'apps/game/resources',
    ),
  );
  assert.ok(
    DEFAULT_FRESHNESS_DEPENDENCIES.graphics.includes(
      'apps/game/assets/custom/ui/app_icon_master.png',
    ),
    'Play icon freshness requires the shared iOS/Play master',
  );
});

test('reads real package and version metadata from the AAB protobuf manifest', () => {
  const expected = {
    packageName: PLAY_PACKAGE_NAME,
    versionCode: 104,
    versionName: '1.2.3',
  };
  assert.deepEqual(parseAndroidBundleManifest(manifestProto(expected)), expected);
  assert.throws(
    () => parseAndroidBundleManifest(manifestProto({
      ...expected,
      versionCode: 'not-a-number',
    })),
    /versionCode/,
  );
});
