import { spawnSync } from 'node:child_process';
import {
  createPrivateKey,
  createHash,
  randomUUID,
  X509Certificate,
} from 'node:crypto';
import {
  chmodSync,
  copyFileSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  utimesSync,
  writeFileSync,
} from 'node:fs';
import { isIP } from 'node:net';
import {
  delimiter,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { inflateSync } from 'node:zlib';
import {
  assertAndroidReleaseMetadata,
  assertAndroidSigningCertificateValid,
  readAndroidReleaseMetadata,
  resolveAndroidJavaToolInvocation,
  verifyAndroidArchiveBillingBoundary,
  verifyAndroidArchiveIapBoundary,
  verifyAndroidArchiveResourceBoundary,
  verifyAndroidLocalizedAppNames,
  verifyAndroidReleaseSigner,
} from './android-build.mjs';
import {
  resolveAndroidReleaseSigning,
} from './android-release-signing.mjs';
import {
  credentialFreeChildEnvironment,
} from './release-environment.mjs';

export const PLAY_PACKAGE_NAME = 'com.crossplatformkorea.moonlitbeacon';
export const PLAY_LOCALES = Object.freeze([
  'en-US',
  'ko-KR',
  'ja-JP',
  'zh-CN',
  'zh-TW',
]);
export const PLAY_PRODUCT_IDS = Object.freeze([
  `${PLAY_PACKAGE_NAME}.supporter`,
  `${PLAY_PACKAGE_NAME}.hero_dancer`,
  `${PLAY_PACKAGE_NAME}.hero_keeper`,
  `${PLAY_PACKAGE_NAME}.hero_knight`,
  `${PLAY_PACKAGE_NAME}.hero_eclipse`,
  `${PLAY_PACKAGE_NAME}.hero_sage`,
  `${PLAY_PACKAGE_NAME}.lantern_colors`,
]);
// Continue coins are consumables owned by IAPKit sync. This package neither creates
// nor edits those products, but the localization CSV still has coin rows, so this list
// exists only so they are not treated as stale rows. Without it the whole app-upload path
// used to stall because of a single coin row.
export const PLAY_CONSUMABLE_PRODUCT_IDS = Object.freeze([
  `${PLAY_PACKAGE_NAME}.continue_coin`,
  `${PLAY_PACKAGE_NAME}.continue_coin_5`,
  `${PLAY_PACKAGE_NAME}.continue_coin_10`,
]);
export const PLAY_SCREENSHOT_NAMES = Object.freeze([
  '01-moonlight-barrage.png',
  '02-field-guardian.png',
  '03-missile-core-drop.png',
  '04-title.png',
  '05-moonlit-shrine.png',
  '06-hero-preview.png',
]);
export const PLAY_SCREENSHOT_TARGETS = Object.freeze([
  Object.freeze({
    countKey: 'phoneScreenshots',
    directory: 'screenshots',
    height: 1080,
    imageType: 'phoneScreenshots',
    role: 'phone-screenshot',
    width: 1920,
  }),
  Object.freeze({
    countKey: 'sevenInchScreenshots',
    directory: 'seven-inch-tablet',
    height: 1080,
    imageType: 'sevenInchScreenshots',
    role: 'seven-inch-tablet-screenshot',
    width: 1920,
  }),
  Object.freeze({
    countKey: 'tenInchScreenshots',
    directory: 'ten-inch-tablet',
    height: 1440,
    imageType: 'tenInchScreenshots',
    role: 'ten-inch-tablet-screenshot',
    width: 2560,
  }),
]);

const DESCRIPTION_HEADINGS = Object.freeze({
  'en-US': '## English description',
  'ko-KR': '## Korean description',
  'ja-JP': '## Japanese description',
  'zh-CN': '## Simplified Chinese description',
  'zh-TW': '## Traditional Chinese description',
});
const RELEASE_NOTE_HEADINGS = Object.freeze({
  'en-US': '## Google Play release notes — English (`en-US`)',
  'ko-KR': '## Google Play release notes — Korean (`ko-KR`)',
  'ja-JP': '## Google Play release notes — Japanese (`ja-JP`)',
  'zh-CN': '## Google Play release notes — Simplified Chinese (`zh-CN`)',
  'zh-TW': '## Google Play release notes — Traditional Chinese (`zh-TW`)',
});
export const PLAY_RELEASE_NOTE_MAX_CHARACTERS = 500;
const FIXED_OUTPUT_TIME = new Date('2000-01-01T00:00:00.000Z');
const MANIFEST_NAME = 'manifest.json';
const OUTPUT_SCHEMA_VERSION = 1;
const GOOGLE_CREDENTIAL_ENV = 'GOOGLE_APPLICATION_CREDENTIALS';
const OUTPUT_OWNERSHIP_MARKER = '.moonlit-play-release-package';
const OUTPUT_OWNERSHIP_MARKER_CONTENT =
  'moonlit-beacon-google-play-release-package-v1\n';
const OUTPUT_RELATIVE_PATTERN =
  /^builds\/release\/google-play-upload(?:-[a-z0-9][a-z0-9-]*)?$/;
const PNG_SIGNATURE = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
]);
const PNG_CRC_TABLE = (() => {
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
const PNG_METADATA_BY_SHA256 = new Map();

export const DEFAULT_PLAY_RELEASE_INPUTS = Object.freeze({
  bundle: 'builds/android/MoonlitBeacon.aab',
  csv: 'notes/release/store-localizations.csv',
  exportPresets: 'apps/game/export_presets.cfg',
  featureGraphic:
    'notes/release/store-assets/play/feature-graphic-1024x500.png',
  icon: 'notes/release/store-assets/play/icon-512.png',
  output: 'builds/release/google-play-upload',
  playScreenshots: 'builds/release/play',
  projectGodot: 'apps/game/project.godot',
  storePage: 'notes/release/store-page.md',
});

export const DEFAULT_FRESHNESS_DEPENDENCIES = Object.freeze({
  bundle: Object.freeze([
    'package.json',
    'apps/game/project.godot',
    'apps/game/export_presets.cfg',
    'apps/game/addons',
    'apps/game/assets',
    'apps/game/default_bus_layout.tres',
    'apps/game/icon.svg',
    'apps/game/icon.svg.import',
    'apps/game/localization',
    'apps/game/resources',
    'apps/game/scenes',
    'apps/game/scripts',
    'scripts/android-build.mjs',
    'scripts/godot.mjs',
    'scripts/lib/android-build.mjs',
    'scripts/lib/android-release-signing.mjs',
    'scripts/lib/godot-export-preflight.mjs',
    'scripts/lib/iapkit-config.mjs',
    'scripts/lib/release-environment.mjs',
  ]),
  graphics: Object.freeze([
    'apps/game/tools/build_store_graphics.py',
    'apps/game/tools/build_app_icon_assets.py',
    'apps/game/assets/custom/ui/app_icon_master.png',
    'apps/game/assets/custom/ui/app_icon_background.png',
    'apps/game/assets/custom/ui/app_icon_foreground.png',
    'apps/game/assets/custom/ui/app_icon_main.png',
  ]),
  screenshots: Object.freeze([
    'apps/game/tools/build_store_graphics.py',
    'notes/release/store-assets/screenshots.json',
    'builds/shots/store-localized/capture-report.json',
  ]),
  screenshotRuntime: Object.freeze([
    'apps/game/addons',
    'apps/game/assets',
    'apps/game/default_bus_layout.tres',
    'apps/game/icon.svg',
    'apps/game/icon.svg.import',
    'apps/game/project.godot',
    'apps/game/localization',
    'apps/game/resources',
    'apps/game/scenes',
    'apps/game/scripts',
  ]),
});

function sha256(data) {
  return createHash('sha256').update(data).digest('hex');
}

function json(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function isInside(parent, child) {
  const relation = relative(resolve(parent), resolve(child));
  return relation === ''
    || (
      relation !== '..'
      && !relation.startsWith(`..${sep}`)
      && !isAbsolute(relation)
    );
}

function assertRelativePath(value, label) {
  if (
    typeof value !== 'string'
    || value.length === 0
    || value.includes('\0')
    || isAbsolute(value)
  ) {
    throw new Error(`${label} must be a repository-relative path.`);
  }
  const segments = value.split(/[\\/]/);
  if (segments.some((segment) => segment === '' || segment === '..')) {
    throw new Error(`${label} has a path-escape component.`);
  }
}

function assertNoSymlinkComponents(root, absolutePath, label) {
  const relation = relative(resolve(root), resolve(absolutePath));
  if (!isInside(root, absolutePath)) {
    throw new Error(`${label} points outside the repository.`);
  }
  let current = resolve(root);
  for (const segment of relation.split(sep).filter(Boolean)) {
    current = join(current, segment);
    if (existsSync(current) && lstatSync(current).isSymbolicLink()) {
      throw new Error(`${label} contains a symbolic link.`);
    }
  }
}

function safeRepoPath(root, relativePath, label, { required = true } = {}) {
  assertRelativePath(relativePath, label);
  const absolutePath = resolve(root, relativePath);
  assertNoSymlinkComponents(root, absolutePath, label);
  if (required && !existsSync(absolutePath)) {
    throw new Error(`${label} input is missing: ${relativePath}`);
  }
  if (required && !isInside(realpathSync(root), realpathSync(absolutePath))) {
    throw new Error(`${label} real path points outside the repository.`);
  }
  return absolutePath;
}

function assertRegularInput(root, relativePath, label) {
  const absolutePath = safeRepoPath(root, relativePath, label);
  const info = lstatSync(absolutePath);
  if (!info.isFile() || info.isSymbolicLink()) {
    throw new Error(`${label} must be a regular file.`);
  }
  return absolutePath;
}

function sortedDirectoryNames(root, relativePath, label) {
  const absolutePath = safeRepoPath(root, relativePath, label);
  if (!lstatSync(absolutePath).isDirectory()) {
    throw new Error(`${label} must be a directory.`);
  }
  return readdirSync(absolutePath).sort((left, right) =>
    left.localeCompare(right, 'en'));
}

function walkRegularFiles(root, relativePath, label) {
  const absolutePath = safeRepoPath(root, relativePath, label);
  const info = lstatSync(absolutePath);
  if (info.isSymbolicLink()) {
    throw new Error(`${label} contains a symbolic link.`);
  }
  if (info.isFile()) return [absolutePath];
  if (!info.isDirectory()) {
    throw new Error(`${label} must be a regular file or directory.`);
  }

  const files = [];
  for (const name of readdirSync(absolutePath).sort((left, right) =>
    left.localeCompare(right, 'en'))) {
    const childRelative = relative(root, join(absolutePath, name));
    files.push(...walkRegularFiles(root, childRelative, label));
  }
  return files;
}

function newestDependency(root, dependencies, label) {
  const files = dependencies.flatMap((relativePath) =>
    walkRegularFiles(root, relativePath, `${label} freshness dependency`));
  if (files.length === 0) {
    throw new Error(`${label} freshness dependency is empty.`);
  }
  return files.reduce((newest, filePath) => {
    const mtimeMs = statSync(filePath).mtimeMs;
    return mtimeMs > newest.mtimeMs
      ? { filePath, mtimeMs }
      : newest;
  }, { filePath: '', mtimeMs: Number.NEGATIVE_INFINITY });
}

function assertNotStale(root, artifacts, dependencies, label) {
  const newest = newestDependency(root, dependencies, label);
  for (const artifact of artifacts) {
    const mtimeMs = statSync(artifact).mtimeMs;
    if (mtimeMs + 1 < newest.mtimeMs) {
      throw new Error(
        `${label} input is stale. `
        + `newer than ${relative(root, artifact)}: `
        + `${relative(root, newest.filePath)} is newer.`,
      );
    }
  }
}

export function parseCsv(source) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (quoted) {
      if (character === '"' && source[index + 1] === '"') {
        field += '"';
        index += 1;
      } else if (character === '"') {
        quoted = false;
      } else {
        field += character;
      }
      continue;
    }
    if (character === '"') {
      quoted = true;
    } else if (character === ',') {
      row.push(field);
      field = '';
    } else if (character === '\n') {
      row.push(field.replace(/\r$/, ''));
      rows.push(row);
      row = [];
      field = '';
    } else {
      field += character;
    }
  }
  if (quoted) throw new Error('Unclosed CSV quote.');
  if (field !== '' || row.length > 0) {
    row.push(field.replace(/\r$/, ''));
    rows.push(row);
  }
  return rows.filter((values) => values.some((value) => value !== ''));
}

export function rowsAsObjects(source) {
  const [header, ...body] = parseCsv(source);
  if (!header || header.length === 0) {
    throw new Error('Store localization CSV header is missing.');
  }
  if (new Set(header).size !== header.length) {
    throw new Error('Store localization CSV header is duplicated.');
  }
  return body.map((row, index) => {
    if (row.length !== header.length) {
      throw new Error(
        `Store localization CSV row ${index + 2} column count is invalid.`,
      );
    }
    return Object.fromEntries(
      header.map((name, column) => [name, row[column]]),
    );
  });
}

function findUniqueRow(rows, predicate, label) {
  const matches = rows.filter(predicate);
  if (matches.length !== 1) {
    throw new Error(`${label} row must appear exactly once.`);
  }
  return matches[0];
}

function characterLength(value) {
  return [...value].length;
}

function assertText(value, maximum, label) {
  const length = characterLength(value ?? '');
  if (length < 1 || length > maximum) {
    throw new Error(`${label} length must be 1~${maximum} characters.`);
  }
  if (/TODO|https?:\/\/example\.com/iu.test(value)) {
    throw new Error(`${label} has unfinished copy.`);
  }
}

function scanMarkdownStructure(markdown) {
  const blocks = [];
  const headings = [];
  const rawH2Headings = [];
  let activeFence = null;
  let offset = 0;

  while (offset < markdown.length) {
    const newline = markdown.indexOf('\n', offset);
    const nextOffset = newline < 0 ? markdown.length : newline + 1;
    const rawLine = markdown.slice(
      offset,
      newline < 0 ? markdown.length : newline,
    );
    const line = rawLine.endsWith('\r') ? rawLine.slice(0, -1) : rawLine;
    if (line.startsWith('## ')) {
      rawH2Headings.push({ line, start: offset });
    }

    if (activeFence !== null) {
      const closing = line.match(/^ {0,3}(`{3,}|~{3,})[\t ]*$/u);
      if (
        closing !== null
        && closing[1][0] === activeFence.marker
        && closing[1].length >= activeFence.length
      ) {
        blocks.push({
          ...activeFence,
          closed: true,
          contentEnd: offset,
        });
        activeFence = null;
      }
    } else {
      const opening = line.match(/^ {0,3}(`{3,}|~{3,})(.*)$/u);
      const validOpening = opening !== null
        && (opening[1][0] !== '`' || !opening[2].includes('`'));
      if (validOpening) {
        activeFence = {
          contentStart: nextOffset,
          info: opening[2].trim(),
          length: opening[1].length,
          marker: opening[1][0],
          start: offset,
        };
      } else if (/^#{1,6} /u.test(line)) {
        headings.push({ line, start: offset });
      }
    }

    if (newline < 0) break;
    offset = nextOffset;
  }

  if (activeFence !== null) {
    blocks.push({
      ...activeFence,
      closed: false,
      contentEnd: markdown.length,
    });
  }
  return { blocks, headings, rawH2Headings };
}

export function extractMarkdownTextBlock(markdown, heading) {
  const structure = scanMarkdownStructure(markdown);
  const headingMatches = structure.headings.filter(
    (candidate) => candidate.line === heading,
  );
  if (headingMatches.length < 1) {
    throw new Error(`${heading} heading is missing.`);
  }
  if (headingMatches.length > 1) {
    throw new Error(`${heading} heading is duplicated.`);
  }
  const headingStart = headingMatches[0].start;
  const nextRenderedHeading = structure.headings.find(
    (candidate) => candidate.start > headingStart,
  );
  // Use a raw H2 as a backup boundary so an unclosed fence cannot swallow the next real H2
  // past the current section. H3-like text inside a normal fence is not a boundary.
  const nextRawH2Heading = structure.rawH2Headings.find(
    (candidate) => candidate.start > headingStart,
  );
  const sectionEnd = Math.min(
    nextRenderedHeading?.start ?? markdown.length,
    nextRawH2Heading?.start ?? markdown.length,
  );
  const sectionBlocks = structure.blocks.filter(
    (block) => block.start > headingStart && block.start < sectionEnd,
  );
  const unclosed = sectionBlocks.find(
    (block) => !block.closed || block.contentEnd > sectionEnd,
  );
  if (unclosed !== undefined) {
    const label = unclosed.info === 'text' ? 'text block' : 'code block';
    throw new Error(`${heading} ${label} is not closed.`);
  }
  const textBlocks = sectionBlocks.filter((block) => block.info === 'text');
  if (textBlocks.length < 1) {
    throw new Error(`${heading} text block is missing.`);
  }
  if (textBlocks.length > 1) {
    throw new Error(`${heading} text block is duplicated.`);
  }
  const block = textBlocks[0];
  const value = markdown.slice(block.contentStart, block.contentEnd).trim();
  assertText(value, 4_000, `${heading} full description`);
  return value;
}

export function collectGooglePlayMetadata(csvSource, storePageSource) {
  const rows = rowsAsObjects(csvSource);
  const appRows = [];
  const productRows = [];

  for (const locale of PLAY_LOCALES) {
    const app = findUniqueRow(
      rows,
      (row) =>
        row.record_type === 'app'
        && row.platform === 'google'
        && row.locale === locale
        && row.product_id === '',
      `Google Play ${locale} app localization`,
    );
    assertText(app.display_name, 30, `${locale} app title`);
    assertText(app.short_description, 80, `${locale} short description`);
    const fullDescription = extractMarkdownTextBlock(
      storePageSource,
      DESCRIPTION_HEADINGS[locale],
    );
    const releaseNote = extractMarkdownTextBlock(
      storePageSource,
      RELEASE_NOTE_HEADINGS[locale],
    );
    assertText(
      releaseNote,
      PLAY_RELEASE_NOTE_MAX_CHARACTERS,
      `${locale} Google Play release notes`,
    );
    appRows.push({
      fullDescription,
      language: locale,
      releaseNote,
      shortDescription: app.short_description,
      title: app.display_name,
    });

    for (const productId of PLAY_PRODUCT_IDS) {
      const product = findUniqueRow(
        rows,
        (row) =>
          row.record_type === 'iap'
          && row.platform === 'google'
          && row.locale === locale
          && row.product_id === productId,
        `Google Play ${locale}/${productId} product localization`,
      );
      if (product.product_type !== 'non_consumable') {
        throw new Error(`${locale}/${productId} must be non_consumable.`);
      }
      assertText(product.display_name, 55, `${locale}/${productId} title`);
      assertText(product.description, 200, `${locale}/${productId} description`);
      productRows.push({
        description: product.description,
        languageCode: locale,
        productId,
        title: product.display_name,
      });
    }

    // Do not put coins in productRows — mixing them into this package's sync payload would
    // edit an IAPKit-owned product from two places. If present, only check they are marked
    // consumable and console length limits; do not fail if they are absent.
    for (const productId of PLAY_CONSUMABLE_PRODUCT_IDS) {
      const coin = rows.find(
        (row) =>
          row.record_type === 'iap'
          && row.platform === 'google'
          && row.locale === locale
          && row.product_id === productId,
      );
      if (coin === undefined) {
        continue;
      }
      if (coin.product_type !== 'consumable') {
        throw new Error(`${locale}/${productId} must be consumable.`);
      }
      assertText(coin.display_name, 55, `${locale}/${productId} title`);
      assertText(coin.description, 200, `${locale}/${productId} description`);
    }
  }

  // The app and 7 non-consumables must exist. IAPKit-owned coin rows may be present or absent.
  // Any other row is treated as a stale SKU and blocked.
  const requiredGoogleKeys = new Set([
    ...PLAY_LOCALES.map((locale) => `app|${locale}|`),
    ...PLAY_LOCALES.flatMap((locale) =>
      PLAY_PRODUCT_IDS.map((productId) => `iap|${locale}|${productId}`)),
  ]);
  const allowedGoogleKeys = new Set([
    ...requiredGoogleKeys,
    ...PLAY_LOCALES.flatMap((locale) =>
      PLAY_CONSUMABLE_PRODUCT_IDS.map(
        (productId) => `iap|${locale}|${productId}`,
      )),
  ]);
  const actualGoogleKeys = rows
    .filter((row) => row.platform === 'google')
    .map((row) => `${row.record_type}|${row.locale}|${row.product_id}`);
  if (
    new Set(actualGoogleKeys).size !== actualGoogleKeys.length
    || actualGoogleKeys.some((key) => !allowedGoogleKeys.has(key))
    || [...requiredGoogleKeys].some((key) => !actualGoogleKeys.includes(key))
  ) {
    throw new Error('Google Play localization CSV has missing, duplicate, or stale rows.');
  }

  return { appRows, productRows };
}

function readVarint(buffer, start) {
  let value = 0n;
  let shift = 0n;
  let offset = start;
  while (offset < buffer.length && shift <= 63n) {
    const byte = buffer[offset];
    offset += 1;
    value |= BigInt(byte & 0x7f) << shift;
    if ((byte & 0x80) === 0) return { offset, value };
    shift += 7n;
  }
  throw new Error('Android manifest protobuf varint is invalid.');
}

function protobufFields(buffer) {
  const fields = [];
  let offset = 0;
  while (offset < buffer.length) {
    const tag = readVarint(buffer, offset);
    offset = tag.offset;
    const field = Number(tag.value >> 3n);
    const wire = Number(tag.value & 0x07n);
    if (field < 1) throw new Error('Android manifest protobuf field is malformed.');
    if (wire === 0) {
      const parsed = readVarint(buffer, offset);
      offset = parsed.offset;
      fields.push({ field, value: parsed.value, wire });
    } else if (wire === 2) {
      const parsed = readVarint(buffer, offset);
      offset = parsed.offset;
      const size = Number(parsed.value);
      if (!Number.isSafeInteger(size) || size < 0 || offset + size > buffer.length) {
        throw new Error('Android manifest protobuf length is invalid.');
      }
      fields.push({
        field,
        value: buffer.subarray(offset, offset + size),
        wire,
      });
      offset += size;
    } else if (wire === 1) {
      if (offset + 8 > buffer.length) {
        throw new Error('Android manifest protobuf fixed64 is truncated.');
      }
      fields.push({ field, value: buffer.subarray(offset, offset + 8), wire });
      offset += 8;
    } else if (wire === 5) {
      if (offset + 4 > buffer.length) {
        throw new Error('Android manifest protobuf fixed32 is truncated.');
      }
      fields.push({ field, value: buffer.subarray(offset, offset + 4), wire });
      offset += 4;
    } else {
      throw new Error(`Unsupported Android manifest wire type: ${wire}`);
    }
  }
  return fields;
}

function protobufString(fields, number) {
  const field = fields.find((candidate) =>
    candidate.field === number && candidate.wire === 2);
  return field ? field.value.toString('utf8') : '';
}

export function parseAndroidBundleManifest(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 16) {
    throw new Error('Failed to read the Android App Bundle manifest.');
  }
  const root = protobufFields(buffer);
  const elementField = root.find((field) => field.field === 1 && field.wire === 2);
  if (!elementField) throw new Error('Android manifest root element is missing.');
  const element = protobufFields(elementField.value);
  if (protobufString(element, 3) !== 'manifest') {
    throw new Error('Android manifest root name is invalid.');
  }
  const attributes = new Map();
  for (const field of element.filter((candidate) =>
    candidate.field === 4 && candidate.wire === 2)) {
    const attribute = protobufFields(field.value);
    const name = protobufString(attribute, 2);
    const value = protobufString(attribute, 3);
    if (name) attributes.set(name, value);
  }
  const packageName = attributes.get('package') ?? '';
  const versionName = attributes.get('versionName') ?? '';
  const versionCodeText = attributes.get('versionCode') ?? '';
  if (!/^[0-9]+$/.test(versionCodeText)) {
    throw new Error('Failed to read AAB manifest versionCode.');
  }
  const versionCode = Number.parseInt(versionCodeText, 10);
  if (!Number.isSafeInteger(versionCode) || versionCode < 1) {
    throw new Error('AAB manifest versionCode is invalid.');
  }
  if (!packageName || !versionName) {
    throw new Error('AAB manifest package name or version name is missing.');
  }
  return { packageName, versionCode, versionName };
}

function spawnChecked(command, args, options, label, spawn = spawnSync) {
  const result = spawn(command, args, {
    encoding: options.encoding,
    env: options.env,
    killSignal: 'SIGTERM',
    maxBuffer: options.maxBuffer,
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: options.timeout,
  });
  if (result.status !== 0 || result.error) {
    throw new Error(`${label} execution failed.`);
  }
  return result.stdout;
}

function readBundleManifest(bundlePath, { env, spawn = spawnSync } = {}) {
  const output = spawnChecked(
    'unzip',
    ['-p', bundlePath, 'base/manifest/AndroidManifest.xml'],
    {
      encoding: null,
      env,
      maxBuffer: 8 * 1024 * 1024,
      timeout: 30_000,
    },
    'AAB manifest extract',
    spawn,
  );
  return Buffer.isBuffer(output) ? output : Buffer.from(output);
}

function readBundleSigner(bundlePath, {
  env,
  platform = process.platform,
  spawn = spawnSync,
} = {}) {
  const tool = resolveAndroidJavaToolInvocation('keytool', { env, platform });
  const output = spawnChecked(
    tool.command,
    [...tool.prefixArgs, '-printcert', '-rfc', '-jarfile', bundlePath],
    {
      encoding: 'utf8',
      env,
      maxBuffer: 2 * 1024 * 1024,
      timeout: 30_000,
    },
    'AAB signer certificate check',
    spawn,
  );
  const certificates = [...output.matchAll(
    /-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----/g,
  )];
  if (certificates.length !== 1) {
    throw new Error('AAB signer certificate must be exactly one.');
  }
  const raw = Buffer.from(certificates[0][1].replace(/\s/g, ''), 'base64');
  assertAndroidSigningCertificateValid(raw);
  const certificate = new X509Certificate(raw);
  return {
    certificateSha256: sha256(raw),
    issuer: certificate.issuer,
    publicKeyType: certificate.publicKey.asymmetricKeyType ?? 'unknown',
    signatureScheme: 'JAR',
    subject: certificate.subject,
    validFrom: new Date(certificate.validFrom).toISOString(),
    validTo: new Date(certificate.validTo).toISOString(),
    verified: true,
  };
}

export function resolvePlayReleaseJavaEnvironment({
  env = process.env,
  exists = existsSync,
  platform = process.platform,
  spawn = spawnSync,
} = {}) {
  const childEnv = credentialFreeChildEnvironment(env);
  if (platform !== 'darwin') return childEnv;

  const detected = spawn('/usr/libexec/java_home', ['-v', '17'], {
    encoding: 'utf8',
    env: childEnv,
    killSignal: 'SIGTERM',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: 15_000,
  });
  const javaHome = detected.status === 0 && !detected.error
    ? detected.stdout.trim()
    : '';
  if (
    !javaHome
    || !isAbsolute(javaHome)
    || javaHome.includes('\0')
    || !exists(join(javaHome, 'bin', 'keytool'))
    || !exists(join(javaHome, 'bin', 'jarsigner'))
  ) {
    throw new Error('Could not find the JDK 17 signing tools registered on macOS.');
  }

  childEnv.JAVA_HOME = javaHome;
  childEnv.PATH = `${join(javaHome, 'bin')}${delimiter}${childEnv.PATH ?? ''}`;
  return childEnv;
}

export function inspectAndroidBundle(bundlePath, {
  env = process.env,
  parseManifest = parseAndroidBundleManifest,
  platform = process.platform,
  readManifest = readBundleManifest,
  readSigner = readBundleSigner,
  resolveJavaEnvironment = resolvePlayReleaseJavaEnvironment,
  root,
  spawn = spawnSync,
  verifyRuntimeBoundaries = verifyPlayBundleRuntimeBoundaries,
  verifySignerPin = verifyBundleSignerPin,
} = {}) {
  const childEnv = credentialFreeChildEnvironment(env);
  const javaEnv = resolveJavaEnvironment({
    env: childEnv,
    platform,
    spawn,
  });
  verifySignerPin(bundlePath, {
    childEnv: javaEnv,
    env,
    platform,
    root,
    spawn,
  });
  verifyRuntimeBoundaries(bundlePath, {
    env: javaEnv,
    spawn,
  });
  const signing = readSigner(bundlePath, {
    env: javaEnv,
    platform,
    spawn,
  });
  return {
    manifest: parseManifest(
      readManifest(bundlePath, { env: javaEnv, spawn }),
    ),
    signing: {
      ...signing,
      pinnedToConfiguredReleaseKey: true,
    },
  };
}

export function verifyPlayBundleRuntimeBoundaries(bundlePath, {
  env = process.env,
  spawn = spawnSync,
  verifyBilling = verifyAndroidArchiveBillingBoundary,
  verifyIap = verifyAndroidArchiveIapBoundary,
  verifyLocalizedNames = verifyAndroidLocalizedAppNames,
  verifyResources = verifyAndroidArchiveResourceBoundary,
} = {}) {
  verifyResources(bundlePath, { env, spawn });
  verifyLocalizedNames(bundlePath, {
    archiveType: 'aab',
    env,
    spawn,
  });
  verifyIap(bundlePath, { env, spawn, store: true });
  verifyBilling(bundlePath, { env, spawn, store: true });
  return true;
}

export function verifyBundleSignerPin(bundlePath, {
  env = process.env,
  childEnv = credentialFreeChildEnvironment(env),
  platform = process.platform,
  resolveSigning = resolveAndroidReleaseSigning,
  root,
  spawn = spawnSync,
  verifyReleaseSigner = verifyAndroidReleaseSigner,
} = {}) {
  if (typeof root !== 'string' || !isAbsolute(root)) {
    throw new Error('Pinned AAB signer verification requires an absolute repository path.');
  }
  const signing = resolveSigning({
    env,
    platform,
    root,
    spawn,
  });
  verifyReleaseSigner(bundlePath, {
    alias: signing.GODOT_ANDROID_KEYSTORE_RELEASE_USER,
    archiveType: 'aab',
    env: childEnv,
    keystorePath: signing.GODOT_ANDROID_KEYSTORE_RELEASE_PATH,
    password: signing.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD,
    platform,
    spawn,
  });
  return true;
}

function reasonedCredentialGate(state, reason) {
  return {
    configured: state !== 'missing',
    credentialMaterialIncluded: false,
    env: GOOGLE_CREDENTIAL_ENV,
    ready: state === 'ready',
    reason,
    state,
  };
}

export function inspectGoogleServiceAccount({
  env = process.env,
  root,
} = {}) {
  const configuredPath = (
    typeof env[GOOGLE_CREDENTIAL_ENV] === 'string'
      ? env[GOOGLE_CREDENTIAL_ENV].trim()
      : ''
  );
  if (!configuredPath) {
    return reasonedCredentialGate(
      'missing',
      'google_application_credentials_not_configured',
    );
  }
  if (!isAbsolute(configuredPath) || configuredPath.includes('\0')) {
    return reasonedCredentialGate('invalid', 'credential_path_not_absolute');
  }

  try {
    const info = lstatSync(configuredPath);
    if (!info.isFile() || info.isSymbolicLink()) {
      return reasonedCredentialGate('invalid', 'credential_not_regular_file');
    }
    if ((info.mode & 0o077) !== 0) {
      return reasonedCredentialGate(
        'invalid',
        'credential_permissions_exceed_0600',
      );
    }
    if (root && isInside(realpathSync(root), realpathSync(configuredPath))) {
      return reasonedCredentialGate(
        'invalid',
        'credential_must_be_outside_repository',
      );
    }
    const parsed = JSON.parse(readFileSync(configuredPath, 'utf8'));
    if (
      parsed?.type !== 'service_account'
      || typeof parsed.project_id !== 'string'
      || !/^[a-z][a-z0-9-]{4,61}[a-z0-9]$/u.test(parsed.project_id)
      || typeof parsed.private_key_id !== 'string'
      || !/^[0-9a-f]{20,64}$/iu.test(parsed.private_key_id)
      || typeof parsed.client_email !== 'string'
      || !/^[a-z0-9][a-z0-9.-]*@[a-z0-9][a-z0-9.-]*\.iam\.gserviceaccount\.com$/iu
        .test(parsed.client_email)
      || parsed.token_uri !== 'https://oauth2.googleapis.com/token'
      || typeof parsed.private_key !== 'string'
      || !/^-----BEGIN PRIVATE KEY-----[\s\S]+-----END PRIVATE KEY-----\s*$/u
        .test(parsed.private_key)
    ) {
      return reasonedCredentialGate(
        'invalid',
        'credential_json_missing_required_service_account_fields',
      );
    }
    const privateKey = createPrivateKey(parsed.private_key);
    if (
      privateKey.asymmetricKeyType !== 'rsa'
      || (privateKey.asymmetricKeyDetails?.modulusLength ?? 0) < 2_048
    ) {
      return reasonedCredentialGate(
        'invalid',
        'credential_private_key_not_rsa_2048_or_stronger',
      );
    }
    return reasonedCredentialGate('ready', 'credential_validated_locally');
  } catch {
    return reasonedCredentialGate('invalid', 'credential_unreadable_or_invalid_json');
  }
}

function quotedProjectSetting(source, key) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(
    new RegExp(`^${escaped}=(\"(?:[^\"\\\\]|\\\\.)*\")\\s*$`, 'm'),
  );
  if (!match) throw new Error(`Project setting ${key} was not found.`);
  try {
    return JSON.parse(match[1]);
  } catch {
    throw new Error(`Project setting ${key} format is invalid.`);
  }
}

function validPublicHttpsUrl(value) {
  try {
    const withoutSupportedPlaceholder = value.replaceAll('{locale}', '');
    if (
      /[{}]/u.test(withoutSupportedPlaceholder)
      || /[\u0000-\u001f\u007f]/u.test(value)
    ) {
      return false;
    }
    const parsed = new URL(value.replaceAll('{locale}', 'en'));
    const hostname = parsed.hostname.toLowerCase();
    const reservedHostname = (
      hostname === 'localhost'
      || hostname.endsWith('.localhost')
      || hostname.endsWith('.local')
      || hostname.endsWith('.internal')
      || hostname.endsWith('.invalid')
      || hostname.endsWith('.test')
      || hostname === 'example'
      || hostname.endsWith('.example')
    );
    return parsed.protocol === 'https:'
      && parsed.username === ''
      && parsed.password === ''
      && parsed.search === ''
      && parsed.hash === ''
      && (parsed.port === '' || parsed.port === '443')
      && hostname.includes('.')
      && isIP(hostname.replace(/^\[|\]$/gu, '')) === 0
      && !reservedHostname;
  } catch {
    return false;
  }
}

function parsePublicContactTemplate(value, route) {
  if (
    typeof value !== 'string'
    || value.split('{locale}').length !== 2
    || !validPublicHttpsUrl(value)
  ) {
    return null;
  }
  try {
    const parsed = new URL(value.replace('{locale}', 'en'));
    return parsed.pathname === `/en/${route}` ? parsed : null;
  } catch {
    return null;
  }
}

export function inspectPublicContactSettings(projectSource) {
  const privacyPolicy = quotedProjectSetting(
    projectSource,
    'config/privacy_policy_url',
  ).trim();
  const supportContact = quotedProjectSetting(
    projectSource,
    'config/support_contact',
  ).trim();
  const privacyPolicyUrl = parsePublicContactTemplate(
    privacyPolicy,
    'privacy',
  );
  const supportContactUrl = parsePublicContactTemplate(
    supportContact,
    'support',
  );
  const privacyPolicyConfigured = privacyPolicyUrl !== null;
  const supportContactConfigured = supportContactUrl !== null;
  const ready = privacyPolicyConfigured
    && supportContactConfigured
    && privacyPolicyUrl.origin === supportContactUrl.origin;
  return {
    aabRebuildRequiredAfterConfiguration: !ready,
    privacyPolicyConfigured,
    ready,
    reason: ready
      ? 'public_privacy_and_support_urls_configured'
      : 'public_privacy_or_support_url_missing',
    state: ready ? 'ready' : 'missing',
    supportContactConfigured,
    valuesIncluded: false,
  };
}

function pngCrc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc = PNG_CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

export function readPngMetadata(buffer, label = 'PNG') {
  if (
    !Buffer.isBuffer(buffer)
    || buffer.length < 45
    || !buffer.subarray(0, 8).equals(PNG_SIGNATURE)
  ) {
    throw new Error(`${label} file PNG signature or length is invalid.`);
  }
  let offset = 8;
  let header = null;
  const imageData = [];
  let sawEnd = false;
  while (offset < buffer.length) {
    if (offset + 12 > buffer.length) {
      throw new Error(`${label} PNG chunk header is truncated.`);
    }
    const length = buffer.readUInt32BE(offset);
    const chunkEnd = offset + 12 + length;
    if (chunkEnd > buffer.length) {
      throw new Error(`${label} PNG chunk data is truncated.`);
    }
    const typeBuffer = buffer.subarray(offset + 4, offset + 8);
    const type = typeBuffer.toString('ascii');
    if (!/^[A-Za-z]{4}$/u.test(type)) {
      throw new Error(`${label} PNG chunk type is invalid.`);
    }
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    const expectedCrc = buffer.readUInt32BE(offset + 8 + length);
    if (pngCrc32(Buffer.concat([typeBuffer, data])) !== expectedCrc) {
      throw new Error(`${label} PNG ${type} CRC is invalid.`);
    }
    if (type === 'IHDR') {
      if (offset !== 8 || length !== 13 || header) {
        throw new Error(`${label} PNG IHDR layout is invalid.`);
      }
      header = Buffer.from(data);
    } else if (type === 'IDAT') {
      if (!header || sawEnd) {
        throw new Error(`${label} PNG IDAT order is invalid.`);
      }
      imageData.push(Buffer.from(data));
    } else if (type === 'IEND') {
      if (length !== 0 || sawEnd || chunkEnd !== buffer.length) {
        throw new Error(`${label} PNG IEND layout is invalid.`);
      }
      sawEnd = true;
    }
    offset = chunkEnd;
    if (sawEnd) break;
  }
  if (!header || imageData.length === 0 || !sawEnd) {
    throw new Error(`${label} PNG needs IHDR, IDAT, and IEND.`);
  }
  const width = header.readUInt32BE(0);
  const height = header.readUInt32BE(4);
  const bitDepth = header[8];
  const colorType = header[9];
  const compression = header[10];
  const filter = header[11];
  const interlace = header[12];
  if (width < 1 || height < 1) {
    throw new Error(`${label} PNG size cannot be 0.`);
  }
  if (bitDepth !== 8 || ![2, 6].includes(colorType)) {
    throw new Error(
      `${label} must be an RGB24 or RGBA32 PNG: `
      + `bitDepth=${bitDepth}, colorType=${colorType}`,
    );
  }
  if (compression !== 0 || filter !== 0 || interlace !== 0) {
    throw new Error(
      `${label} PNG must use standard compression/filter and non-interlaced format.`,
    );
  }
  const channels = colorType === 2 ? 3 : 4;
  const rowSize = width * channels + 1;
  const expectedInflatedSize = rowSize * height;
  if (
    !Number.isSafeInteger(expectedInflatedSize)
    || expectedInflatedSize > 256 * 1024 * 1024
  ) {
    throw new Error(`${label} PNG decoded size exceeds the safe range.`);
  }
  let inflated;
  try {
    inflated = inflateSync(
      Buffer.concat(imageData),
      { maxOutputLength: expectedInflatedSize + 1 },
    );
  } catch {
    throw new Error(`${label} failed to inflate PNG IDAT compressed data.`);
  }
  if (inflated.length !== expectedInflatedSize) {
    throw new Error(
      `${label} PNG decoded size differs: ${inflated.length} `
      + `(expected ${expectedInflatedSize})`,
    );
  }
  for (let row = 0; row < height; row += 1) {
    if (inflated[row * rowSize] > 4) {
      throw new Error(`${label} PNG scanline filter is invalid.`);
    }
  }
  return {
    bitDepth,
    colorType,
    height,
    width,
  };
}

function assertPng(path, expected, label) {
  const contents = readFileSync(path);
  const digest = sha256(contents);
  let metadata = PNG_METADATA_BY_SHA256.get(digest);
  if (metadata === undefined) {
    metadata = readPngMetadata(contents, label);
    PNG_METADATA_BY_SHA256.set(digest, metadata);
  }
  for (const [field, value] of Object.entries(expected)) {
    if (metadata[field] !== value) {
      throw new Error(
        `${label} ${field}=${metadata[field]}; expected ${value}`,
      );
    }
  }
}

function assertPngContents(contents, expected, label) {
  const digest = sha256(contents);
  let metadata = PNG_METADATA_BY_SHA256.get(digest);
  if (metadata === undefined) {
    metadata = readPngMetadata(contents, label);
    PNG_METADATA_BY_SHA256.set(digest, metadata);
  }
  for (const [field, value] of Object.entries(expected)) {
    if (metadata[field] !== value) {
      throw new Error(
        `${label} ${field}=${metadata[field]}; expected ${value}`,
      );
    }
  }
  return metadata;
}

function assertExactSemanticPayload(actual, expected, label) {
  if (!isDeepStrictEqual(actual, expected)) {
    throw new Error(`${label} semantic payload contract differs.`);
  }
}

function parseCanonicalJsonPayload(contents, label) {
  let value;
  try {
    value = JSON.parse(contents.toString('utf8'));
  } catch (error) {
    throw new Error(`${label} JSON is invalid.`, { cause: error });
  }
  if (!contents.equals(Buffer.from(json(value)))) {
    throw new Error(`${label} JSON differs from the deterministic representation.`);
  }
  return value;
}

function decodeUtf8Payload(contents, label) {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(contents);
  } catch (error) {
    throw new Error(`${label} is not UTF-8.`, { cause: error });
  }
}

function assertOwnedOutputDirectory(path, label) {
  if (!existsSync(path)) return;
  const info = lstatSync(path);
  if (!info.isDirectory() || info.isSymbolicLink()) {
    throw new Error(`${label} is not an owned regular directory.`);
  }
  const marker = join(path, OUTPUT_OWNERSHIP_MARKER);
  if (
    !existsSync(marker)
    || !lstatSync(marker).isFile()
    || lstatSync(marker).isSymbolicLink()
    || readFileSync(marker, 'utf8') !== OUTPUT_OWNERSHIP_MARKER_CONTENT
  ) {
    throw new Error(
      `${label} has no dedicated ownership marker; keeping it.`,
    );
  }
}

function removeOwnedOutputDirectory(path, label) {
  if (!existsSync(path)) return;
  assertOwnedOutputDirectory(path, label);
  rmSync(path, { force: true, recursive: true });
}

function acquireGenerationLock(root, outputRelative) {
  assertRelativePath(outputRelative, 'Google Play output path');
  if (!OUTPUT_RELATIVE_PATTERN.test(outputRelative)) {
    throw new Error(
      'Google Play output allows only builds/release/google-play-upload'
      + ' or a safe -suffix path.',
    );
  }
  const output = safeRepoPath(
    root,
    outputRelative,
    'Google Play output path',
    { required: false },
  );
  const parent = dirname(output);
  assertNoSymlinkComponents(root, parent, 'Google Play output parent path');
  mkdirSync(parent, { recursive: true, mode: 0o755 });
  const lockPath = `${output}.generation.lock`;
  if (!isInside(root, lockPath)) {
    throw new Error('Google Play generate lock path is outside the repository.');
  }
  const lockContents = [
    'moonlit-beacon-google-play-generation-v1',
    String(process.pid),
    randomUUID(),
    '',
  ].join('\n');
  try {
    writeFileSync(lockPath, lockContents, {
      encoding: 'utf8',
      flag: 'wx',
      mode: 0o600,
    });
  } catch (error) {
    if (error?.code !== 'EEXIST') throw error;
    throw new Error(
      `Another Google Play package is being generated. Lock: ${lockPath}`,
    );
  }
  let owned = true;
  return () => {
    if (!owned) return;
    if (
      !existsSync(lockPath)
      || lstatSync(lockPath).isSymbolicLink()
      || !lstatSync(lockPath).isFile()
      || readFileSync(lockPath, 'utf8') !== lockContents
    ) {
      throw new Error('Lost Google Play generate lock ownership.');
    }
    rmSync(lockPath);
    owned = false;
  };
}

function prepareOutputPaths(root, outputRelative) {
  assertRelativePath(outputRelative, 'Google Play output path');
  if (!OUTPUT_RELATIVE_PATTERN.test(outputRelative)) {
    throw new Error(
      'Google Play output allows only builds/release/google-play-upload'
      + ' or a safe -suffix path.',
    );
  }
  const output = safeRepoPath(
    root,
    outputRelative,
    'Google Play output path',
    { required: false },
  );
  const parent = dirname(output);
  assertNoSymlinkComponents(root, parent, 'Google Play output parent path');
  mkdirSync(parent, { recursive: true, mode: 0o755 });
  const legacyStaging = `${output}.partial`;
  const stagingPrefix = `${output}.partial-`;
  if (
    !isInside(root, legacyStaging)
    || !isInside(root, stagingPrefix)
  ) {
    throw new Error('Google Play temporary output path is outside the repository.');
  }
  // Under the full generate lock, confirm ownership of both before deleting either.
  // Do not allow a sequence that deletes one, then hits a marker error on the other,
  // leaving only part of the existing data gone.
  assertOwnedOutputDirectory(output, 'existing Google Play output');
  assertOwnedOutputDirectory(legacyStaging, 'existing Google Play temporary output');
  removeOwnedOutputDirectory(output, 'existing Google Play output');
  removeOwnedOutputDirectory(legacyStaging, 'existing Google Play temporary output');
  return { output, stagingPrefix };
}

function normalizeOutputRelative(value) {
  return value.split(sep).join('/');
}

function writeDeterministicFile(staging, relativePath, contents) {
  assertRelativePath(relativePath, 'Google Play payload path');
  const destination = resolve(staging, relativePath);
  if (!isInside(staging, destination)) {
    throw new Error('Google Play payload escaped the output path.');
  }
  mkdirSync(dirname(destination), { recursive: true, mode: 0o755 });
  writeFileSync(destination, contents, { mode: 0o644 });
  chmodSync(destination, 0o644);
  utimesSync(destination, FIXED_OUTPUT_TIME, FIXED_OUTPUT_TIME);
  return destination;
}

function copyDeterministicFile(staging, relativePath, source) {
  assertRelativePath(relativePath, 'Google Play media path');
  const destination = resolve(staging, relativePath);
  if (!isInside(staging, destination)) {
    throw new Error('Google Play media escaped the output path.');
  }
  mkdirSync(dirname(destination), { recursive: true, mode: 0o755 });
  copyFileSync(source, destination);
  chmodSync(destination, 0o644);
  utimesSync(destination, FIXED_OUTPUT_TIME, FIXED_OUTPUT_TIME);
  return destination;
}

function payloadRecord(staging, relativePath, role, extra = {}) {
  const absolutePath = resolve(staging, relativePath);
  const contents = readFileSync(absolutePath);
  return {
    ...extra,
    bytes: contents.length,
    path: normalizeOutputRelative(relativePath),
    role,
    sha256: sha256(contents),
  };
}

function productFileName(productId) {
  if (!PLAY_PRODUCT_IDS.includes(productId)) {
    throw new Error('Unsupported Google Play product ID.');
  }
  return `${productId.slice(PLAY_PACKAGE_NAME.length + 1)}.patch.json`;
}

function makeListingPayload(app) {
  return {
    apiBoundary: 'edits.listings.update',
    body: {
      fullDescription: app.fullDescription,
      language: app.language,
      shortDescription: app.shortDescription,
      title: app.title,
    },
    method: 'PUT',
    pathTemplate:
      '/androidpublisher/v3/applications/{packageName}/edits/{editId}'
      + '/listings/{language}',
    remoteApplyAllowed: false,
  };
}

function makeReleaseNotesPlan(releaseNotes) {
  return {
    apiBoundary: 'edits.tracks.update',
    futureTrackReleaseFragment: {
      releaseNotes: releaseNotes.map(({ language, text }) => ({
        language,
        text,
      })),
    },
    method: 'PUT',
    pathTemplate:
      '/androidpublisher/v3/applications/{packageName}/edits/{editId}'
      + '/tracks/{track}',
    remoteApplyAllowed: false,
    requestCompleteness: {
      complete: false,
      missing: ['track', 'status', 'versionCodes'],
      mode: 'release_notes_only',
    },
    track: null,
  };
}

function makeOneTimeProductPayload(productId, productRows) {
  return {
    apiBoundary: 'monetization.onetimeproducts.patch',
    body: {
      listings: productRows
        .filter((row) => row.productId === productId)
        .map(({ description, languageCode, title }) => ({
          description,
          languageCode,
          title,
        })),
      packageName: PLAY_PACKAGE_NAME,
      productId,
    },
    method: 'PATCH',
    pathTemplate:
      '/androidpublisher/v3/applications/{packageName}'
      + '/onetimeproducts/{productId}',
    query: {
      allowMissing: false,
      regionsVersion: null,
      updateMask: 'listings',
    },
    requestCompleteness: {
      complete: false,
      missing: ['regionsVersion'],
      mode: 'existing_product_localization_update_only',
    },
    remoteApplyAllowed: false,
  };
}

function validateBundleAgainstProject(bundle, projectSource, presetsSource) {
  const expected = readAndroidReleaseMetadata(projectSource, presetsSource);
  assertAndroidReleaseMetadata(expected, {
    expectedPackageName: PLAY_PACKAGE_NAME,
  });
  const actual = bundle.manifest;
  const play = expected.play;
  if (
    actual.packageName !== play.packageName
    || actual.versionCode !== play.versionCode
    || actual.versionName !== play.versionName
  ) {
    throw new Error(
      'AAB manifest package name, versionCode, and versionName '
      + 'differ from the Android Play preset.',
    );
  }
  if (bundle.signing?.verified !== true) {
    throw new Error('AAB signature verification evidence is missing.');
  }
  if (bundle.signing?.pinnedToConfiguredReleaseKey !== true) {
    throw new Error(
      'AAB signer is not pinned to the specified release keystore certificate.',
    );
  }
  return {
    packageName: actual.packageName,
    projectVersion: expected.projectVersion,
    versionCode: actual.versionCode,
    versionName: actual.versionName,
  };
}

export function verifyPlayReleasePackage(outputPath, {
  env = process.env,
  inspectBundle = inspectAndroidBundle,
  root = resolve(outputPath, '../../..'),
} = {}) {
  assertOwnedOutputDirectory(outputPath, 'Google Play output');
  if (typeof inspectBundle !== 'function') {
    throw new Error('Google Play AAB standalone re-verifier is missing.');
  }
  if (typeof root !== 'string' || !isAbsolute(root) || !existsSync(root)) {
    throw new Error('Google Play AAB re-verify repository root is invalid.');
  }
  const manifestPath = join(outputPath, MANIFEST_NAME);
  if (!existsSync(manifestPath)) {
    throw new Error('Google Play manifest.json is missing.');
  }
  const manifest = parseCanonicalJsonPayload(
    readFileSync(manifestPath),
    'Google Play manifest',
  );
  if (!isDeepStrictEqual(Object.keys(manifest).sort(), [
    'apiApplication',
    'apiBoundaries',
    'counts',
    'files',
    'gates',
    'inputFingerprint',
    'inputs',
    'locales',
    'packageName',
    'release',
    'releaseNotes',
    'schemaVersion',
  ])) {
    throw new Error('Google Play manifest top-level contract differs.');
  }
  if (!Array.isArray(manifest.files)) {
    throw new Error('Google Play manifest files list is missing.');
  }
  const expectedPayloads = new Map();
  const addExpectedPayload = (path, role, extra = {}) => {
    expectedPayloads.set(path, { path, role, ...extra });
  };
  addExpectedPayload(OUTPUT_OWNERSHIP_MARKER, 'ownership-marker');
  addExpectedPayload(
    'publisher-api/edits.bundles.upload/MoonlitBeacon.aab',
    'android-app-bundle',
    { apiBoundary: 'edits.bundles.upload' },
  );
  addExpectedPayload(
    'publisher-api/edits.bundles.upload/operation.json',
    'bundle-upload-operation',
    { apiBoundary: 'edits.bundles.upload' },
  );
  for (const locale of PLAY_LOCALES) {
    addExpectedPayload(
      `publisher-api/edits.listings.update/${locale}.json`,
      'localized-store-listing',
      { apiBoundary: 'edits.listings.update', locale },
    );
    addExpectedPayload(
      `copy/release-notes/${locale}.txt`,
      'localized-release-note',
      { locale, maximumCharacters: PLAY_RELEASE_NOTE_MAX_CHARACTERS },
    );
    for (const graphic of [
      { imageType: 'icon', name: 'icon.png' },
      { imageType: 'featureGraphic', name: 'feature-graphic.png' },
    ]) {
      addExpectedPayload(
        `publisher-api/edits.images.upload/${locale}/`
          + `${graphic.imageType}/${graphic.name}`,
        'store-graphic',
        {
          apiBoundary: 'edits.images.upload',
          imageType: graphic.imageType,
          locale,
        },
      );
    }
    for (const target of PLAY_SCREENSHOT_TARGETS) {
      for (const [index, name] of PLAY_SCREENSHOT_NAMES.entries()) {
        addExpectedPayload(
          `publisher-api/edits.images.upload/${locale}/`
            + `${target.imageType}/${name}`,
          target.role,
          {
            apiBoundary: 'edits.images.upload',
            imageType: target.imageType,
            locale,
            sequence: index + 1,
          },
        );
      }
    }
  }
  addExpectedPayload(
    'publisher-api/edits.tracks.update/release-notes.json',
    'release-notes-track-fragment',
    { apiBoundary: 'edits.tracks.update' },
  );
  addExpectedPayload(
    'publisher-api/edits.images.upload/operations.json',
    'image-upload-plan',
    { apiBoundary: 'edits.images.upload' },
  );
  for (const productId of PLAY_PRODUCT_IDS) {
    addExpectedPayload(
      'publisher-api/monetization.onetimeproducts/'
        + productFileName(productId),
      'one-time-product-listings',
      { apiBoundary: 'monetization.onetimeproducts.patch', productId },
    );
  }
  addExpectedPayload(
    'publisher-api/monetization.onetimeproducts/operations.json',
    'one-time-product-plan',
    { apiBoundary: 'monetization.onetimeproducts' },
  );

  const expectedCounts = {
    bundleFiles: 1,
    imageDeleteAllOperations: PLAY_LOCALES.length * 5,
    imageOperations: PLAY_LOCALES.length
      * (2 + PLAY_SCREENSHOT_TARGETS.length * PLAY_SCREENSHOT_NAMES.length),
    listingPayloads: PLAY_LOCALES.length,
    localeCount: PLAY_LOCALES.length,
    oneTimeProductLocalizations: PLAY_LOCALES.length * PLAY_PRODUCT_IDS.length,
    oneTimeProductPayloads: PLAY_PRODUCT_IDS.length,
    payloadFiles: expectedPayloads.size,
    phoneScreenshots: PLAY_LOCALES.length * PLAY_SCREENSHOT_NAMES.length,
    releaseNoteLocalizations: PLAY_LOCALES.length,
    sevenInchScreenshots: PLAY_LOCALES.length * PLAY_SCREENSHOT_NAMES.length,
    storeGraphics: PLAY_LOCALES.length * 2,
    tenInchScreenshots: PLAY_LOCALES.length * PLAY_SCREENSHOT_NAMES.length,
  };
  if (
    manifest.schemaVersion !== OUTPUT_SCHEMA_VERSION
    || manifest.packageName !== PLAY_PACKAGE_NAME
    || JSON.stringify(manifest.locales) !== JSON.stringify(PLAY_LOCALES)
    || JSON.stringify(Object.keys(manifest.counts ?? {}).sort())
      !== JSON.stringify(Object.keys(expectedCounts).sort())
    || Object.entries(expectedCounts).some(
      ([key, value]) => manifest.counts?.[key] !== value,
    )
  ) {
    throw new Error('Google Play manifest schema, package, locale, or count contract differs.');
  }
  if (manifest.files.length !== expectedPayloads.size) {
    throw new Error('Google Play manifest payload file count differs from the exact contract.');
  }
  if (
    !Array.isArray(manifest.inputs)
    || manifest.inputFingerprint !== sha256(json(manifest.inputs))
  ) {
    throw new Error('Google Play manifest input fingerprint is invalid.');
  }
  const inputPaths = new Set();
  for (const input of manifest.inputs) {
    if (
      input === null
      || typeof input !== 'object'
      || Array.isArray(input)
      || !isDeepStrictEqual(Object.keys(input).sort(), [
        'bytes', 'path', 'sha256',
      ])
      || !Number.isSafeInteger(input.bytes)
      || input.bytes < 0
      || typeof input.path !== 'string'
      || !/^[0-9a-f]{64}$/u.test(input.sha256)
      || inputPaths.has(input.path)
    ) {
      throw new Error('Google Play manifest input record contract differs.');
    }
    assertRelativePath(input.path, 'manifest input path');
    inputPaths.add(input.path);
  }
  const manifestInputOrder = manifest.inputs.map((input) => input.path);
  if (!isDeepStrictEqual(
    manifestInputOrder,
    [...manifestInputOrder].sort((left, right) => left.localeCompare(right, 'en')),
  )) {
    throw new Error('Google Play manifest input path sort contract differs.');
  }
  const expectedPaths = new Set([MANIFEST_NAME]);
  const fileRecords = new Map();
  const payloadContents = new Map();
  for (const file of manifest.files) {
    assertRelativePath(file.path, 'manifest payload path');
    if (expectedPaths.has(file.path)) {
      throw new Error(`manifest payload path is duplicated: ${file.path}`);
    }
    const expectedPayload = expectedPayloads.get(file.path);
    if (
      !expectedPayload
      || Object.entries(expectedPayload).some(
        ([key, value]) => file[key] !== value,
      )
    ) {
      throw new Error(`manifest payload contract differs: ${file.path}`);
    }
    expectedPaths.add(file.path);
    fileRecords.set(file.path, file);
    const absolutePath = resolve(outputPath, file.path);
    if (!isInside(outputPath, absolutePath)) {
      throw new Error('manifest payload path escaped the output folder.');
    }
    const info = lstatSync(absolutePath);
    if (!info.isFile() || info.isSymbolicLink()) {
      throw new Error(`manifest payload is not a regular file: ${file.path}`);
    }
    const contents = readFileSync(absolutePath);
    if (contents.length !== file.bytes || sha256(contents) !== file.sha256) {
      throw new Error(`manifest payload hash differs: ${file.path}`);
    }
    const expectedRecord = {
      ...expectedPayload,
      bytes: contents.length,
      sha256: sha256(contents),
    };
    if (file.role === 'localized-release-note') {
      const raw = decodeUtf8Payload(contents, `${file.locale} release notes`);
      if (!raw.endsWith('\n') || raw.slice(0, -1).endsWith('\n')) {
        throw new Error(`${file.locale} release notes LF contract differs.`);
      }
      expectedRecord.characters = characterLength(raw.slice(0, -1));
    }
    if (!isDeepStrictEqual(file, expectedRecord)) {
      throw new Error(`manifest payload record differs from the exact contract: ${file.path}`);
    }
    payloadContents.set(file.path, contents);
  }
  const manifestFileOrder = manifest.files.map((file) => file.path);
  if (!isDeepStrictEqual(
    manifestFileOrder,
    [...manifestFileOrder].sort((left, right) => left.localeCompare(right, 'en')),
  )) {
    throw new Error('Google Play manifest payload path sort contract differs.');
  }
  const actualFiles = walkRegularFiles(outputPath, '.', 'Google Play output')
    .map((filePath) => normalizeOutputRelative(relative(outputPath, filePath)));
  if (
    actualFiles.length !== expectedPaths.size
    || actualFiles.some((filePath) => !expectedPaths.has(filePath))
  ) {
    throw new Error('Google Play output tree has a file not registered in the manifest.');
  }

  if (!payloadContents.get(OUTPUT_OWNERSHIP_MARKER).equals(
    Buffer.from(OUTPUT_OWNERSHIP_MARKER_CONTENT),
  )) {
    throw new Error('Google Play ownership marker payload differs.');
  }
  assertExactSemanticPayload(manifest.apiApplication, {
    implemented: false,
    remoteApplyAllowed: false,
  }, 'Google Play apiApplication');
  assertExactSemanticPayload(manifest.apiBoundaries, {
    bundle: 'edits.bundles.upload',
    imageReset: 'edits.images.deleteall',
    images: 'edits.images.upload',
    listings: 'edits.listings.update',
    oneTimeProducts: 'monetization.onetimeproducts',
    tracks: 'edits.tracks.update',
  }, 'Google Play API boundary');

  const bundlePath =
    'publisher-api/edits.bundles.upload/MoonlitBeacon.aab';
  const bundleOperationPath =
    'publisher-api/edits.bundles.upload/operation.json';
  assertExactSemanticPayload(
    parseCanonicalJsonPayload(
      payloadContents.get(bundleOperationPath),
      'Google Play bundle upload operation',
    ),
    {
      apiBoundary: 'edits.bundles.upload',
      mediaPath: bundlePath,
      method: 'POST',
      pathTemplate:
        '/upload/androidpublisher/v3/applications/{packageName}'
        + '/edits/{editId}/bundles',
      remoteApplyAllowed: false,
    },
    'Google Play bundle upload operation',
  );
  const packagedBundleInspection = inspectBundle(join(outputPath, bundlePath), {
    env,
    root,
  });
  const packagedManifest = packagedBundleInspection?.manifest;
  const packagedSigning = packagedBundleInspection?.signing;
  if (
    packagedManifest?.packageName !== PLAY_PACKAGE_NAME
    || !Number.isSafeInteger(packagedManifest.versionCode)
    || packagedManifest.versionCode < 1
    || typeof packagedManifest.versionName !== 'string'
    || packagedManifest.versionName === ''
    || packagedSigning?.verified !== true
    || packagedSigning?.pinnedToConfiguredReleaseKey !== true
  ) {
    throw new Error('Google Play packaged AAB package, version, signature, or runtime verification failed.');
  }
  const bundleRecord = fileRecords.get(bundlePath);
  if (
    manifest.release === null
    || typeof manifest.release !== 'object'
    || Array.isArray(manifest.release)
    || typeof manifest.release.projectVersion !== 'string'
    || manifest.release.projectVersion === ''
    || manifest.release.projectVersion !== packagedManifest.versionName
  ) {
    throw new Error('Google Play manifest release contract is missing.');
  }
  assertExactSemanticPayload(manifest.release, {
    projectVersion: manifest.release.projectVersion,
    packageName: packagedManifest.packageName,
    versionCode: packagedManifest.versionCode,
    versionName: packagedManifest.versionName,
    bundle: bundleRecord,
    finalSubmissionAab: manifest.gates?.publicContact?.ready === true,
    signing: packagedSigning,
  }, 'Google Play manifest release');

  for (const locale of PLAY_LOCALES) {
    const listingPath =
      `publisher-api/edits.listings.update/${locale}.json`;
    const listing = parseCanonicalJsonPayload(
      payloadContents.get(listingPath),
      `${locale} Google Play listing`,
    );
    const body = listing?.body;
    if (body === null || typeof body !== 'object' || Array.isArray(body)) {
      throw new Error(`${locale} Google Play listing body is missing.`);
    }
    assertText(body.title, 30, `${locale} app title`);
    assertText(body.shortDescription, 80, `${locale} short description`);
    assertText(body.fullDescription, 4_000, `${locale} full description`);
    if (body.language !== locale) {
      throw new Error(`${locale} Google Play listing language differs.`);
    }
    assertExactSemanticPayload(listing, makeListingPayload({
      fullDescription: body.fullDescription,
      language: locale,
      shortDescription: body.shortDescription,
      title: body.title,
    }), `${locale} Google Play listing`);
  }

  const releaseNotes = [];
  for (const locale of PLAY_LOCALES) {
    const notePath = `copy/release-notes/${locale}.txt`;
    const raw = decodeUtf8Payload(
      payloadContents.get(notePath),
      `${locale} Google Play release notes`,
    );
    if (!raw.endsWith('\n') || raw.slice(0, -1).endsWith('\n')) {
      throw new Error(`${locale} Google Play release notes LF contract differs.`);
    }
    const text = raw.slice(0, -1);
    assertText(
      text,
      PLAY_RELEASE_NOTE_MAX_CHARACTERS,
      `${locale} Google Play release notes`,
    );
    releaseNotes.push({ language: locale, path: notePath, text });
  }
  const releaseNotesPlanPath =
    'publisher-api/edits.tracks.update/release-notes.json';
  assertExactSemanticPayload(
    parseCanonicalJsonPayload(
      payloadContents.get(releaseNotesPlanPath),
      'Google Play release-note track fragment',
    ),
    makeReleaseNotesPlan(releaseNotes),
    'Google Play release-note track fragment',
  );
  assertExactSemanticPayload(manifest.releaseNotes, {
    localizations: releaseNotes.map((note) => ({
      characters: characterLength(note.text),
      language: note.language,
      path: note.path,
    })),
    maximumCharacters: PLAY_RELEASE_NOTE_MAX_CHARACTERS,
    remoteApplyAllowed: false,
    trackSelected: false,
  }, 'Google Play manifest release notes');

  const imagePlanPath =
    'publisher-api/edits.images.upload/operations.json';
  const expectedResetOperations = [];
  const expectedUploadOperations = [];
  const screenshotHashes = new Set();
  const graphicHashes = new Map([
    ['icon', new Set()],
    ['featureGraphic', new Set()],
  ]);
  for (const locale of PLAY_LOCALES) {
    for (const imageType of [
      'icon',
      'featureGraphic',
      ...PLAY_SCREENSHOT_TARGETS.map((target) => target.imageType),
    ]) {
      expectedResetOperations.push({
        apiBoundary: 'edits.images.deleteall',
        imageType,
        language: locale,
        method: 'DELETE',
        pathTemplate:
          '/androidpublisher/v3/applications/{packageName}'
          + '/edits/{editId}/listings/{language}/{imageType}',
        remoteApplyAllowed: false,
      });
    }
    for (const graphic of [
      {
        expected: { bitDepth: 8, height: 512, width: 512 },
        imageType: 'icon',
        name: 'icon.png',
      },
      {
        expected: {
          bitDepth: 8, colorType: 2, height: 500, width: 1024,
        },
        imageType: 'featureGraphic',
        name: 'feature-graphic.png',
      },
    ]) {
      const mediaPath = `publisher-api/edits.images.upload/${locale}/`
        + `${graphic.imageType}/${graphic.name}`;
      const contents = payloadContents.get(mediaPath);
      assertPngContents(contents, graphic.expected, `${locale} ${graphic.imageType}`);
      const digest = sha256(contents);
      graphicHashes.get(graphic.imageType).add(digest);
      expectedUploadOperations.push({
        imageType: graphic.imageType,
        language: locale,
        mediaPath,
        method: 'POST',
        pathTemplate:
          '/upload/androidpublisher/v3/applications/{packageName}'
          + '/edits/{editId}/listings/{language}/{imageType}',
        remoteApplyAllowed: false,
        sha256: digest,
      });
    }
    for (const target of PLAY_SCREENSHOT_TARGETS) {
      for (const [index, name] of PLAY_SCREENSHOT_NAMES.entries()) {
        const mediaPath = `publisher-api/edits.images.upload/${locale}/`
          + `${target.imageType}/${name}`;
        const contents = payloadContents.get(mediaPath);
        assertPngContents(contents, {
          bitDepth: 8,
          colorType: 2,
          height: target.height,
          width: target.width,
        }, `${locale}/${target.imageType}/${name}`);
        const digest = sha256(contents);
        if (screenshotHashes.has(digest)) {
          throw new Error(
            `Google Play package screenshot is duplicated: `
            + `${locale}/${target.imageType}/${name}`,
          );
        }
        screenshotHashes.add(digest);
        expectedUploadOperations.push({
          imageType: target.imageType,
          language: locale,
          mediaPath,
          method: 'POST',
          pathTemplate:
            '/upload/androidpublisher/v3/applications/{packageName}'
            + '/edits/{editId}/listings/{language}/{imageType}',
          remoteApplyAllowed: false,
          sequence: index + 1,
          sha256: digest,
        });
      }
    }
  }
  if ([...graphicHashes.values()].some((hashes) => hashes.size !== 1)) {
    throw new Error('Google Play per-locale icon/feature graphic bytes differ.');
  }
  assertExactSemanticPayload(
    parseCanonicalJsonPayload(
      payloadContents.get(imagePlanPath),
      'Google Play image operation plan',
    ),
    {
      apiBoundary: 'edits.images.upload',
      resetBeforeUpload: expectedResetOperations,
      remoteApplyAllowed: false,
      uploadOperations: expectedUploadOperations,
    },
    'Google Play image operation plan',
  );

  for (const productId of PLAY_PRODUCT_IDS) {
    const productPath = 'publisher-api/monetization.onetimeproducts/'
      + productFileName(productId);
    const product = parseCanonicalJsonPayload(
      payloadContents.get(productPath),
      `${productId} Google Play one-time product patch`,
    );
    const listings = product?.body?.listings;
    if (
      product?.body?.packageName !== PLAY_PACKAGE_NAME
      || product?.body?.productId !== productId
      || !Array.isArray(listings)
      || listings.length !== PLAY_LOCALES.length
      || listings.some((listing, index) => (
        listing?.languageCode !== PLAY_LOCALES[index]
      ))
    ) {
      throw new Error(`${productId} Google Play product locale/ID contract differs.`);
    }
    for (const listing of listings) {
      assertText(listing.title, 55, `${listing.languageCode}/${productId} title`);
      assertText(
        listing.description,
        200,
        `${listing.languageCode}/${productId} description`,
      );
    }
    assertExactSemanticPayload(
      product,
      makeOneTimeProductPayload(
        productId,
        listings.map((listing) => ({ ...listing, productId })),
      ),
      `${productId} Google Play one-time product patch`,
    );
  }
  const productPlanPath =
    'publisher-api/monetization.onetimeproducts/operations.json';
  assertExactSemanticPayload(
    parseCanonicalJsonPayload(
      payloadContents.get(productPlanPath),
      'Google Play one-time product operation plan',
    ),
    {
      apiBoundary: 'monetization.onetimeproducts',
      creationPayloadIncluded: false,
      operations: PLAY_PRODUCT_IDS.map((productId) => ({
        allowMissing: false,
        file: 'publisher-api/monetization.onetimeproducts/'
          + productFileName(productId),
        mode: 'existing_product_localization_update_only',
        productId,
        regionsVersion: null,
        updateMask: 'listings',
      })),
      pricingAndAvailabilityIncluded: false,
      purchaseOptionsIncluded: false,
      regionsVersionIncluded: false,
      remoteApplyAllowed: false,
    },
    'Google Play one-time product operation plan',
  );
  return manifest;
}

export function runStoreScreenshotValidation(root, {
  env = process.env,
  spawn = spawnSync,
} = {}) {
  const childEnv = {};
  for (const name of [
    'HOME',
    'LANG',
    'LC_ALL',
    'MOONLIT_PYTHON',
    'PATH',
    'SYSTEMROOT',
    'TMPDIR',
    'WINDIR',
  ]) {
    if (typeof env[name] === 'string') childEnv[name] = env[name];
  }
  const result = spawn(
    process.execPath,
    [
      'scripts/python.mjs',
      '-B',
      'apps/game/tools/build_store_graphics.py',
      '--check-play-screenshots',
    ],
    {
      cwd: root,
      encoding: 'utf8',
      env: childEnv,
      killSignal: 'SIGTERM',
      stdio: ['ignore', 'pipe', 'pipe'],
      // Five locales across Android phone, 7-inch, and 10-inch targets require
      // rendering and hashing 90 large PNGs. Keep a finite process bound while
      // leaving headroom for slower CI hosts.
      timeout: 10 * 60 * 1000,
    },
  );
  if (result.status !== 0 || result.error) {
    throw new Error(
      'Official screenshot verification failed. '
      + 'Pass pnpm check:store-screenshots:play first.',
    );
  }
  return true;
}

function preparePlayReleasePackageUnlocked({
  env = process.env,
  freshnessDependencies = DEFAULT_FRESHNESS_DEPENDENCIES,
  inputs = DEFAULT_PLAY_RELEASE_INPUTS,
  inspectBundle = inspectAndroidBundle,
  inspectServiceAccount = inspectGoogleServiceAccount,
  outputRelative = inputs.output,
  publishOutput = renameSync,
  root,
  validateScreenshots = runStoreScreenshotValidation,
} = {}) {
  if (typeof root !== 'string' || !isAbsolute(root) || !existsSync(root)) {
    throw new Error('Repository root must be an existing absolute path.');
  }
  const canonicalRoot = realpathSync(root);
  const paths = prepareOutputPaths(canonicalRoot, outputRelative);

  const csvPath = assertRegularInput(
    canonicalRoot,
    inputs.csv,
    'store localization CSV',
  );
  const storePagePath = assertRegularInput(
    canonicalRoot,
    inputs.storePage,
    'store page description',
  );
  const projectPath = assertRegularInput(
    canonicalRoot,
    inputs.projectGodot,
    'Godot project settings',
  );
  const presetsPath = assertRegularInput(
    canonicalRoot,
    inputs.exportPresets,
    'Godot export preset',
  );
  const bundlePath = assertRegularInput(
    canonicalRoot,
    inputs.bundle,
    'Android App Bundle',
  );
  const iconPath = assertRegularInput(
    canonicalRoot,
    inputs.icon,
    'Google Play app icon',
  );
  const featurePath = assertRegularInput(
    canonicalRoot,
    inputs.featureGraphic,
    'Google Play feature graphic',
  );
  const projectSource = readFileSync(projectPath, 'utf8');
  const presetsSource = readFileSync(presetsPath, 'utf8');
  const metadata = collectGooglePlayMetadata(
    readFileSync(csvPath, 'utf8'),
    readFileSync(storePagePath, 'utf8'),
  );

  assertPng(
    iconPath,
    { bitDepth: 8, height: 512, width: 512 },
    'Google Play app icon',
  );
  assertPng(
    featurePath,
    { bitDepth: 8, colorType: 2, height: 500, width: 1024 },
    'Google Play feature graphic',
  );

  const screenshotPaths = [];
  const screenshotHashes = new Set();
  const localeDirectories = sortedDirectoryNames(
    canonicalRoot,
    inputs.playScreenshots,
    'Google Play screenshot root',
  );
  if (
    localeDirectories.length !== PLAY_LOCALES.length
    || localeDirectories.some((value, index) => value !== [...PLAY_LOCALES]
      .sort((left, right) => left.localeCompare(right, 'en'))[index])
  ) {
    throw new Error('Google Play screenshot locale folders must be exactly 5.');
  }
  for (const locale of PLAY_LOCALES) {
    for (const target of PLAY_SCREENSHOT_TARGETS) {
      const screenshotRelative =
        `${inputs.playScreenshots}/${locale}/${target.directory}`;
      const names = sortedDirectoryNames(
        canonicalRoot,
        screenshotRelative,
        `${locale} Google Play ${target.imageType}`,
      );
      const expectedNames = [...PLAY_SCREENSHOT_NAMES].sort((left, right) =>
        left.localeCompare(right, 'en'));
      if (
        names.length !== expectedNames.length
        || names.some((value, index) => value !== expectedNames[index])
      ) {
        throw new Error(
          `${locale} ${target.imageType} must have exactly the contracted 6 images.`,
        );
      }
      for (const name of PLAY_SCREENSHOT_NAMES) {
        const source = assertRegularInput(
          canonicalRoot,
          `${screenshotRelative}/${name}`,
          `${locale}/${target.imageType}/${name} screenshot`,
        );
        assertPng(
          source,
          {
            bitDepth: 8,
            colorType: 2,
            height: target.height,
            width: target.width,
          },
          `${locale}/${target.imageType}/${name}`,
        );
        const hash = sha256(readFileSync(source));
        if (screenshotHashes.has(hash)) {
          throw new Error(
            `Screenshot is duplicated across another locale, device, or scene: `
            + `${locale}/${target.imageType}/${name}`,
          );
        }
        screenshotHashes.add(hash);
        screenshotPaths.push({ locale, name, source, target });
      }
    }
  }

  assertNotStale(
    canonicalRoot,
    [bundlePath],
    freshnessDependencies.bundle,
    'Android App Bundle',
  );
  assertNotStale(
    canonicalRoot,
    [iconPath, featurePath],
    freshnessDependencies.graphics,
    'Google Play graphics',
  );
  assertNotStale(
    canonicalRoot,
    screenshotPaths.map(({ source }) => source),
    freshnessDependencies.screenshots,
    'Google Play screenshots',
  );
  for (const runtimePath of freshnessDependencies.screenshotRuntime ?? []) {
    walkRegularFiles(
      canonicalRoot,
      runtimePath,
      'Google Play screenshot runtime freshness',
    );
  }
  // Godot export can refresh project.godot mtime with no content change, so runtime source
  // is compared by the capture-report content fingerprint through the official checker, not mtime.
  // The list above names export inputs including resources so missing files and symlinks
  // are rejected separately.
  validateScreenshots(canonicalRoot, {
    env,
    runtimePaths: freshnessDependencies.screenshotRuntime ?? [],
  });

  const bundleInspection = inspectBundle(bundlePath, {
    env,
    root: canonicalRoot,
  });
  const release = validateBundleAgainstProject(
    bundleInspection,
    projectSource,
    presetsSource,
  );
  const serviceAccount = inspectServiceAccount({
    env,
    root: canonicalRoot,
  });
  const publicContact = inspectPublicContactSettings(projectSource);
  const files = [];

  // Use per-run staging so two overlapping generators cannot overwrite the same file.
  // Verify the finished tree in staging first, then publish with a single rename.
  paths.staging = mkdtempSync(paths.stagingPrefix);
  try {
    writeDeterministicFile(
      paths.staging,
      OUTPUT_OWNERSHIP_MARKER,
      OUTPUT_OWNERSHIP_MARKER_CONTENT,
    );
    files.push(payloadRecord(
      paths.staging,
      OUTPUT_OWNERSHIP_MARKER,
      'ownership-marker',
    ));
    const bundleOutputRelative =
      'publisher-api/edits.bundles.upload/MoonlitBeacon.aab';
    copyDeterministicFile(paths.staging, bundleOutputRelative, bundlePath);
    files.push(payloadRecord(
      paths.staging,
      bundleOutputRelative,
      'android-app-bundle',
      { apiBoundary: 'edits.bundles.upload' },
    ));
    const bundleOperationRelative =
      'publisher-api/edits.bundles.upload/operation.json';
    writeDeterministicFile(paths.staging, bundleOperationRelative, json({
      apiBoundary: 'edits.bundles.upload',
      mediaPath: bundleOutputRelative,
      method: 'POST',
      pathTemplate:
        '/upload/androidpublisher/v3/applications/{packageName}'
        + '/edits/{editId}/bundles',
      remoteApplyAllowed: false,
    }));
    files.push(payloadRecord(
      paths.staging,
      bundleOperationRelative,
      'bundle-upload-operation',
      { apiBoundary: 'edits.bundles.upload' },
    ));

    for (const app of metadata.appRows) {
      const listingRelative =
        `publisher-api/edits.listings.update/${app.language}.json`;
      writeDeterministicFile(
        paths.staging,
        listingRelative,
        json(makeListingPayload(app)),
      );
      files.push(payloadRecord(
        paths.staging,
        listingRelative,
        'localized-store-listing',
        { apiBoundary: 'edits.listings.update', locale: app.language },
      ));
    }

    const releaseNotes = metadata.appRows.map(({ language, releaseNote }) => ({
      characters: characterLength(releaseNote),
      language,
      path: `copy/release-notes/${language}.txt`,
      text: releaseNote,
    }));
    for (const note of releaseNotes) {
      writeDeterministicFile(
        paths.staging,
        note.path,
        `${note.text}\n`,
      );
      files.push(payloadRecord(
        paths.staging,
        note.path,
        'localized-release-note',
        {
          characters: note.characters,
          locale: note.language,
          maximumCharacters: PLAY_RELEASE_NOTE_MAX_CHARACTERS,
        },
      ));
    }
    const releaseNotesPlanRelative =
      'publisher-api/edits.tracks.update/release-notes.json';
    writeDeterministicFile(
      paths.staging,
      releaseNotesPlanRelative,
      json(makeReleaseNotesPlan(releaseNotes)),
    );
    files.push(payloadRecord(
      paths.staging,
      releaseNotesPlanRelative,
      'release-notes-track-fragment',
      { apiBoundary: 'edits.tracks.update' },
    ));

    const imageOperations = [];
    const imageResetOperations = [];
    for (const locale of PLAY_LOCALES) {
      for (const imageType of [
        'icon',
        'featureGraphic',
        ...PLAY_SCREENSHOT_TARGETS.map((target) => target.imageType),
      ]) {
        imageResetOperations.push({
          apiBoundary: 'edits.images.deleteall',
          imageType,
          language: locale,
          method: 'DELETE',
          pathTemplate:
            '/androidpublisher/v3/applications/{packageName}'
            + '/edits/{editId}/listings/{language}/{imageType}',
          remoteApplyAllowed: false,
        });
      }
      for (const graphic of [
        {
          imageType: 'icon',
          name: 'icon.png',
          source: iconPath,
        },
        {
          imageType: 'featureGraphic',
          name: 'feature-graphic.png',
          source: featurePath,
        },
      ]) {
        const mediaRelative =
          `publisher-api/edits.images.upload/${locale}/`
          + `${graphic.imageType}/${graphic.name}`;
        copyDeterministicFile(paths.staging, mediaRelative, graphic.source);
        const record = payloadRecord(
          paths.staging,
          mediaRelative,
          'store-graphic',
          {
            apiBoundary: 'edits.images.upload',
            imageType: graphic.imageType,
            locale,
          },
        );
        files.push(record);
        imageOperations.push({
          imageType: graphic.imageType,
          language: locale,
          mediaPath: mediaRelative,
          method: 'POST',
          pathTemplate:
            '/upload/androidpublisher/v3/applications/{packageName}'
            + '/edits/{editId}/listings/{language}/{imageType}',
          remoteApplyAllowed: false,
          sha256: record.sha256,
        });
      }
      for (const screenshot of screenshotPaths.filter((item) =>
        item.locale === locale)) {
        const mediaRelative =
          `publisher-api/edits.images.upload/${locale}/`
          + `${screenshot.target.imageType}/`
          + screenshot.name;
        copyDeterministicFile(paths.staging, mediaRelative, screenshot.source);
        const record = payloadRecord(
          paths.staging,
          mediaRelative,
          screenshot.target.role,
          {
            apiBoundary: 'edits.images.upload',
            imageType: screenshot.target.imageType,
            locale,
            sequence: PLAY_SCREENSHOT_NAMES.indexOf(screenshot.name) + 1,
          },
        );
        files.push(record);
        imageOperations.push({
          imageType: screenshot.target.imageType,
          language: locale,
          mediaPath: mediaRelative,
          method: 'POST',
          pathTemplate:
            '/upload/androidpublisher/v3/applications/{packageName}'
            + '/edits/{editId}/listings/{language}/{imageType}',
          remoteApplyAllowed: false,
          sequence: PLAY_SCREENSHOT_NAMES.indexOf(screenshot.name) + 1,
          sha256: record.sha256,
        });
      }
    }
    const imagePlanRelative =
      'publisher-api/edits.images.upload/operations.json';
    writeDeterministicFile(paths.staging, imagePlanRelative, json({
      apiBoundary: 'edits.images.upload',
      resetBeforeUpload: imageResetOperations,
      remoteApplyAllowed: false,
      uploadOperations: imageOperations,
    }));
    files.push(payloadRecord(
      paths.staging,
      imagePlanRelative,
      'image-upload-plan',
      { apiBoundary: 'edits.images.upload' },
    ));

    for (const productId of PLAY_PRODUCT_IDS) {
      const productRelative =
        'publisher-api/monetization.onetimeproducts/'
        + productFileName(productId);
      writeDeterministicFile(
        paths.staging,
        productRelative,
        json(makeOneTimeProductPayload(productId, metadata.productRows)),
      );
      files.push(payloadRecord(
        paths.staging,
        productRelative,
        'one-time-product-listings',
        {
          apiBoundary: 'monetization.onetimeproducts.patch',
          productId,
        },
      ));
    }
    const productPlanRelative =
      'publisher-api/monetization.onetimeproducts/operations.json';
    writeDeterministicFile(paths.staging, productPlanRelative, json({
      apiBoundary: 'monetization.onetimeproducts',
      creationPayloadIncluded: false,
      operations: PLAY_PRODUCT_IDS.map((productId) => ({
        allowMissing: false,
        file:
          'publisher-api/monetization.onetimeproducts/'
          + productFileName(productId),
        mode: 'existing_product_localization_update_only',
        productId,
        regionsVersion: null,
        updateMask: 'listings',
      })),
      pricingAndAvailabilityIncluded: false,
      purchaseOptionsIncluded: false,
      regionsVersionIncluded: false,
      remoteApplyAllowed: false,
    }));
    files.push(payloadRecord(
      paths.staging,
      productPlanRelative,
      'one-time-product-plan',
      { apiBoundary: 'monetization.onetimeproducts' },
    ));

    files.sort((left, right) => left.path.localeCompare(right.path, 'en'));
    const inputSources = [
      inputs.bundle,
      inputs.csv,
      inputs.exportPresets,
      inputs.featureGraphic,
      inputs.icon,
      inputs.projectGodot,
      inputs.storePage,
      'scripts/lib/play-release-package.mjs',
      'scripts/prepare-play-release.mjs',
      ...screenshotPaths.map(({ locale, name, target }) =>
        `${inputs.playScreenshots}/${locale}/${target.directory}/${name}`),
    ].map((relativePath) => {
      const absolutePath = assertRegularInput(
        canonicalRoot,
        relativePath,
        'Google Play manifest input',
      );
      const contents = readFileSync(absolutePath);
      return {
        bytes: contents.length,
        path: normalizeOutputRelative(relativePath),
        sha256: sha256(contents),
      };
    }).sort((left, right) => left.path.localeCompare(right.path, 'en'));

    const legalDeclarations = {
      ready: false,
      reason: 'account_owner_attestation_not_recorded',
      requiredDeclarations: [
        'google_play_developer_program_policies',
        'united_states_export_laws',
      ],
      state: 'not_recorded',
    };
    const oneTimeProductSetup = {
      creationPayloadsReady: false,
      localizationPayloadsReady: true,
      pricingAndAvailabilityConfigured: false,
      purchaseOptionsConfigured: false,
      ready: false,
      reason: 'regions_version_purchase_options_and_prices_not_configured',
      regionsVersionConfigured: false,
      requiredOwnerInputs: [
        'google_play_regions_version',
        'seven_product_regional_prices_and_availability',
        'seven_product_buy_purchase_options',
      ],
      state: 'owner_input_required',
    };
    const remoteReady = legalDeclarations.ready
      && serviceAccount.ready
      && publicContact.ready
      && oneTimeProductSetup.ready;
    const manifest = {
      apiApplication: {
        implemented: false,
        remoteApplyAllowed: false,
      },
      apiBoundaries: {
        bundle: 'edits.bundles.upload',
        imageReset: 'edits.images.deleteall',
        images: 'edits.images.upload',
        listings: 'edits.listings.update',
        oneTimeProducts: 'monetization.onetimeproducts',
        tracks: 'edits.tracks.update',
      },
      counts: {
        bundleFiles: 1,
        imageDeleteAllOperations: imageResetOperations.length,
        imageOperations: imageOperations.length,
        localeCount: PLAY_LOCALES.length,
        listingPayloads: metadata.appRows.length,
        oneTimeProductLocalizations: metadata.productRows.length,
        oneTimeProductPayloads: PLAY_PRODUCT_IDS.length,
        payloadFiles: files.length,
        ...Object.fromEntries(PLAY_SCREENSHOT_TARGETS.map((target) => [
          target.countKey,
          screenshotPaths.filter((item) => (
            item.target.imageType === target.imageType
          )).length,
        ])),
        releaseNoteLocalizations: releaseNotes.length,
        storeGraphics: PLAY_LOCALES.length * 2,
      },
      files,
      gates: {
        googlePlayLegalDeclarations: legalDeclarations,
        googleServiceAccount: serviceAccount,
        oneTimeProductSetup,
        publicContact,
        remoteActionsReady: remoteReady,
      },
      inputFingerprint: sha256(json(inputSources)),
      inputs: inputSources,
      locales: PLAY_LOCALES,
      packageName: PLAY_PACKAGE_NAME,
      release: {
        ...release,
        bundle: files.find((file) => file.role === 'android-app-bundle'),
        finalSubmissionAab: publicContact.ready,
        signing: bundleInspection.signing,
      },
      releaseNotes: {
        localizations: releaseNotes.map((note) => ({
          characters: note.characters,
          language: note.language,
          path: note.path,
        })),
        maximumCharacters: PLAY_RELEASE_NOTE_MAX_CHARACTERS,
        remoteApplyAllowed: false,
        trackSelected: false,
      },
      schemaVersion: OUTPUT_SCHEMA_VERSION,
    };
    writeDeterministicFile(
      paths.staging,
      MANIFEST_NAME,
      json(manifest),
    );
    const verificationOptions = {
      env,
      inspectBundle,
      root: canonicalRoot,
    };
    verifyPlayReleasePackage(paths.staging, verificationOptions);
    assertOwnedOutputDirectory(paths.output, 'Google Play output to replace');
    publishOutput(paths.staging, paths.output);
    return verifyPlayReleasePackage(paths.output, verificationOptions);
  } catch (error) {
    try {
      removeOwnedOutputDirectory(
        paths.staging,
        'failed Google Play temporary output',
      );
    } catch {
      // If ownership was lost, not deleting beats the original error.
    }
    try {
      removeOwnedOutputDirectory(paths.output, 'failed Google Play output');
    } catch {
      // Keep a path that was replaced with other data.
    }
    throw error;
  }
}

export function preparePlayReleasePackage(options = {}) {
  const {
    inputs = DEFAULT_PLAY_RELEASE_INPUTS,
    outputRelative = inputs.output,
    root,
  } = options;
  if (typeof root !== 'string' || !isAbsolute(root) || !existsSync(root)) {
    throw new Error('Repository root must be an existing absolute path.');
  }
  const canonicalRoot = realpathSync(root);
  const releaseGenerationLock = acquireGenerationLock(
    canonicalRoot,
    outputRelative,
  );
  try {
    return preparePlayReleasePackageUnlocked({
      ...options,
      inputs,
      outputRelative,
      root: canonicalRoot,
    });
  } finally {
    releaseGenerationLock();
  }
}
