import {
  createHash,
  createPrivateKey,
  sign,
} from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import {
  dirname,
  extname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from 'node:path';
import { inflateSync } from 'node:zlib';
import {
  assertIosReleaseMetadata,
  readAppStoreCredentials,
  readIosReleaseMetadata,
} from './ios-distribution.mjs';
import {
  buildStoreContactPlan,
  projectContactMatches,
} from './store-contact-config.mjs';

export const APPLE_LOCALES = Object.freeze([
  'en-US',
  'ko',
  'ja',
  'zh-Hans',
  'zh-Hant',
]);

export const ADOPTABLE_APP_VERSION_STATES = Object.freeze([
  'PREPARE_FOR_SUBMISSION',
  'DEVELOPER_REJECTED',
]);

const RELEASED_APP_VERSION_STATES = new Set([
  'READY_FOR_DISTRIBUTION',
  'REPLACED_WITH_NEW_VERSION',
]);

export function normalizeAppVersionState(state) {
  if (state === 'READY_FOR_SALE') return 'READY_FOR_DISTRIBUTION';
  if (state === 'PROCESSING_FOR_APP_STORE') {
    return 'PROCESSING_FOR_DISTRIBUTION';
  }
  return typeof state === 'string' && state.length > 0 ? state : null;
}

export function appVersionState(resource) {
  const resourceAttributes = attributes(resource);
  return normalizeAppVersionState(
    resourceAttributes.appVersionState
      ?? resourceAttributes.appStoreState
      ?? null,
  );
}

export function isAdoptableAppVersionState(state) {
  return ADOPTABLE_APP_VERSION_STATES.includes(
    normalizeAppVersionState(state),
  );
}

export function canCreateNewAppStoreVersion(versionResources) {
  if (!Array.isArray(versionResources)) {
    throw new TypeError('remote App Store version list must be an array.');
  }
  if (versionResources.length === 0) return true;
  const states = versionResources.map(appVersionState);
  return states.filter((state) => state === 'READY_FOR_DISTRIBUTION').length === 1
    && states.every((state) => RELEASED_APP_VERSION_STATES.has(state));
}

export const IAP_PRODUCT_IDS = Object.freeze([
  'com.crossplatformkorea.moonlitbeacon.supporter',
  'com.crossplatformkorea.moonlitbeacon.hero_dancer',
  'com.crossplatformkorea.moonlitbeacon.hero_keeper',
  'com.crossplatformkorea.moonlitbeacon.hero_knight',
  'com.crossplatformkorea.moonlitbeacon.hero_eclipse',
  'com.crossplatformkorea.moonlitbeacon.hero_sage',
  'com.crossplatformkorea.moonlitbeacon.lantern_colors',
  'com.crossplatformkorea.moonlitbeacon.continue_coin',
  'com.crossplatformkorea.moonlitbeacon.continue_coin_5',
  'com.crossplatformkorea.moonlitbeacon.continue_coin_10',
]);

export const IAP_PRODUCT_TYPE_BY_ID = Object.freeze(Object.fromEntries(
  IAP_PRODUCT_IDS.map((productId) => [
    productId,
    productId.includes('.continue_coin') ? 'CONSUMABLE' : 'NON_CONSUMABLE',
  ]),
));

export const IAP_BASE_PRICES = Object.freeze({
  'com.crossplatformkorea.moonlitbeacon.supporter': Object.freeze({
    territory: 'KOR',
    currency: 'KRW',
    customerPrice: '3300',
  }),
  'com.crossplatformkorea.moonlitbeacon.hero_dancer': Object.freeze({
    territory: 'USA',
    currency: 'USD',
    customerPrice: '4.99',
  }),
  'com.crossplatformkorea.moonlitbeacon.hero_keeper': Object.freeze({
    territory: 'USA',
    currency: 'USD',
    customerPrice: '9.99',
  }),
  'com.crossplatformkorea.moonlitbeacon.hero_knight': Object.freeze({
    territory: 'USA',
    currency: 'USD',
    customerPrice: '14.99',
  }),
  'com.crossplatformkorea.moonlitbeacon.hero_eclipse': Object.freeze({
    territory: 'USA',
    currency: 'USD',
    customerPrice: '19.99',
  }),
  'com.crossplatformkorea.moonlitbeacon.hero_sage': Object.freeze({
    territory: 'USA',
    currency: 'USD',
    customerPrice: '24.99',
  }),
  'com.crossplatformkorea.moonlitbeacon.lantern_colors': Object.freeze({
    territory: 'KOR',
    currency: 'KRW',
    customerPrice: '1100',
  }),
  'com.crossplatformkorea.moonlitbeacon.continue_coin': Object.freeze({
    territory: 'USA',
    currency: 'USD',
    customerPrice: '0.49',
  }),
  'com.crossplatformkorea.moonlitbeacon.continue_coin_5': Object.freeze({
    territory: 'USA',
    currency: 'USD',
    customerPrice: '1.99',
  }),
  'com.crossplatformkorea.moonlitbeacon.continue_coin_10': Object.freeze({
    territory: 'USA',
    currency: 'USD',
    customerPrice: '3.49',
  }),
});

export const APP_AVAILABILITY_REQUIREMENTS = Object.freeze({
  availableInNewTerritories: true,
  excludedTerritories: Object.freeze(['CHN']),
  requiredIncludedTerritories: Object.freeze(['KOR', 'USA', 'JPN', 'TWN']),
});

export const IAP_REVIEW_FILE_BY_PRODUCT_ID = Object.freeze({
  'com.crossplatformkorea.moonlitbeacon.hero_dancer': 'hero-dancer.png',
  'com.crossplatformkorea.moonlitbeacon.hero_keeper': 'hero-keeper.png',
  'com.crossplatformkorea.moonlitbeacon.hero_knight': 'hero-knight.png',
  'com.crossplatformkorea.moonlitbeacon.hero_eclipse': 'hero-eclipse.png',
  'com.crossplatformkorea.moonlitbeacon.hero_sage': 'hero-sage.png',
  'com.crossplatformkorea.moonlitbeacon.supporter': 'supporter.png',
  'com.crossplatformkorea.moonlitbeacon.lantern_colors': 'lantern-colors.png',
  'com.crossplatformkorea.moonlitbeacon.continue_coin': 'continue-coin.png',
  'com.crossplatformkorea.moonlitbeacon.continue_coin_5': 'continue-coin-5.png',
  'com.crossplatformkorea.moonlitbeacon.continue_coin_10': 'continue-coin-10.png',
});

export const SCREENSHOT_FILE_NAMES = Object.freeze([
  '01-moonlight-barrage.png',
  '02-field-guardian.png',
  '03-missile-core-drop.png',
  '04-title.png',
  '05-moonlit-shrine.png',
  '06-hero-preview.png',
]);

export const SCREENSHOT_TARGETS = Object.freeze([
  Object.freeze({
    directory: 'iphone-6.5',
    displayType: 'APP_IPHONE_65',
    width: 2778,
    height: 1284,
  }),
  Object.freeze({
    directory: 'ipad-13',
    displayType: 'APP_IPAD_PRO_3GEN_129',
    width: 2732,
    height: 2048,
  }),
]);

export const DEFAULT_APP_STORE_APP_ID = '6796293839';
export const DEFAULT_MANIFEST_RELATIVE_PATH =
  'builds/release/app-store-release-manifest.json';
export const APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH =
  'builds/release/app-store/screenshot-provenance.json';
export const APP_STORE_CAPTURE_REPORT_RELATIVE_PATH =
  'builds/shots/store-localized/capture-report.json';
const APP_STORE_BUNDLE_ID = 'com.crossplatformkorea.moonlitbeacon';
const APP_STORE_TEAM_ID = 'PRDQGB267K';
const SCREENSHOT_PROVENANCE_CONTRACT =
  'moonlit-app-store-screenshot-provenance-v1';
const SCREENSHOT_PROVENANCE_SCHEMA_VERSION = 1;
const SCREENSHOT_MAPPINGS_PER_SET =
  APPLE_LOCALES.length * SCREENSHOT_FILE_NAMES.length;

const DESCRIPTION_HEADINGS = Object.freeze({
  'en-US': '## English description',
  ko: '## Korean description',
  ja: '## Japanese description',
  'zh-Hans': '## Simplified Chinese description',
  'zh-Hant': '## Traditional Chinese description',
});

const WHATS_NEW_HEADINGS = Object.freeze({
  'en-US': '## Google Play release notes — English (`en-US`)',
  ko: '## Google Play release notes — Korean (`ko-KR`)',
  ja: '## Google Play release notes — Japanese (`ja-JP`)',
  'zh-Hans': '## Google Play release notes — Simplified Chinese (`zh-CN`)',
  'zh-Hant': '## Google Play release notes — Traditional Chinese (`zh-TW`)',
});

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
const APP_STORE_ORIGIN = 'https://api.appstoreconnect.apple.com';
const APP_STORE_MAX_JSON_BYTES = 2 * 1024 * 1024;
const READY_IAP_STATES = new Set([
  'READY_TO_SUBMIT',
  'APPROVED',
]);
const EXPECTED_SCREENSHOT_COUNT =
  APPLE_LOCALES.length * SCREENSHOT_TARGETS.length
  * SCREENSHOT_FILE_NAMES.length;

function cliError(message) {
  return Object.assign(new Error(message), { exitCode: 2 });
}

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function normalizeRelativePath(value) {
  return value.split(sep).join('/');
}

function pathIsInside(parent, child) {
  const relation = relative(resolve(parent), resolve(child));
  return relation === ''
    || (
      relation !== '..'
      && !relation.startsWith(`..${sep}`)
      && !isAbsolute(relation)
    );
}

function assertNoSymbolicLinkComponents(root, path, label) {
  const base = resolve(root);
  const target = resolve(path);
  if (!pathIsInside(base, target)) {
    throw new Error(`${label} path points outside the allowed root: ${path}`);
  }
  let current = base;
  const components = [
    current,
    ...relative(base, target)
      .split(sep)
      .filter(Boolean)
      .map((component) => {
        current = join(current, component);
        return current;
      }),
  ];
  for (const component of components) {
    if (existsSync(component) && lstatSync(component).isSymbolicLink()) {
      throw new Error(`${label} path contains a symbolic link: ${path}`);
    }
  }
}

function assertRegularFile(path, root, label) {
  assertNoSymbolicLinkComponents(root, path, label);
  if (!existsSync(path)) {
    throw new Error(`${label} file is missing: ${path}`);
  }
  const entry = lstatSync(path);
  if (!entry.isFile() || entry.isSymbolicLink()) {
    throw new Error(`${label} must be a regular file: ${path}`);
  }
  if (!pathIsInside(realpathSync(root), realpathSync(path))) {
    throw new Error(`${label} path points outside the allowed root: ${path}`);
  }
  return entry;
}

function digest(buffer, algorithm) {
  return createHash(algorithm).update(buffer).digest('hex');
}

function fileChecksums(buffer) {
  return {
    sha256: digest(buffer, 'sha256'),
    md5: digest(buffer, 'md5'),
  };
}

function fileArtifact(path, repoRoot, allowedRoot, label) {
  assertNoSymbolicLinkComponents(repoRoot, path, label);
  const entry = assertRegularFile(path, allowedRoot, label);
  const buffer = readFileSync(path);
  return {
    path: normalizeRelativePath(relative(repoRoot, path)),
    fileName: path.split(sep).at(-1),
    size: entry.size,
    ...fileChecksums(buffer),
  };
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
      row.push(field.replace(/\r$/u, ''));
      rows.push(row);
      row = [];
      field = '';
    } else {
      field += character;
    }
  }

  if (quoted) throw new Error('CSV has an unclosed quote.');
  if (field !== '' || row.length > 0) {
    row.push(field.replace(/\r$/u, ''));
    rows.push(row);
  }
  return rows.filter((entry) => entry.some((value) => value !== ''));
}

export function csvRowsAsObjects(source) {
  const [header, ...body] = parseCsv(source);
  if (!header) throw new Error('store localization CSV header is missing.');
  if (new Set(header).size !== header.length) {
    throw new Error('store localization CSV header is duplicated.');
  }
  return body.map((row, index) => {
    if (row.length !== header.length) {
      throw new Error(
        `store localization CSV row ${index + 2} has a different column count: `
        + `${row.length} (expected ${header.length})`,
      );
    }
    return Object.fromEntries(
      header.map((key, column) => [key, row[column]]),
    );
  });
}

export function extractMarkdownTextBlock(markdown, heading) {
  const escaped = heading.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const headingMatches = [...markdown.matchAll(
    new RegExp(`^${escaped}\\s*$`, 'gmu'),
  )];
  if (headingMatches.length !== 1) {
    throw new Error(
      `${heading} heading must appear exactly once: `
      + `found ${headingMatches.length}`,
    );
  }
  const headingIndex = headingMatches[0].index;
  const fenceStart = markdown.indexOf('```text\n', headingIndex);
  if (fenceStart < 0) {
    throw new Error(`${heading} has no text code block below it.`);
  }
  const nextHeading = markdown.indexOf('\n## ', headingIndex + heading.length);
  if (nextHeading >= 0 && fenceStart > nextHeading) {
    throw new Error(`${heading} has no text code block immediately below it.`);
  }
  const contentStart = fenceStart + '```text\n'.length;
  const fenceEnd = markdown.indexOf('\n```', contentStart);
  if (fenceEnd < 0) {
    throw new Error(`${heading} text code block is not closed.`);
  }
  const value = markdown.slice(contentStart, fenceEnd);
  if (value.trim() === '') {
    throw new Error(`${heading} description is empty.`);
  }
  return value;
}

export function validateAppleWhatsNew(
  value,
  label = "App Store What's New",
) {
  const normalized = requireNonempty(value, label);
  if ([...normalized].length > 4000) {
    throw new Error(`${label} text exceeds 4,000 characters.`);
  }
  return normalized;
}

export function extractScreenshotFileNames(markdown) {
  const sectionStart = markdown.indexOf('## Screenshots');
  if (sectionStart < 0) {
    throw new Error('could not find the Screenshots section in store-page.md.');
  }
  const sectionEnd = markdown.indexOf('\n## ', sectionStart + 1);
  const section = markdown.slice(
    sectionStart,
    sectionEnd < 0 ? markdown.length : sectionEnd,
  );
  const names = [...section.matchAll(
    /^\|\s*`([0-9]{2}-[a-z0-9-]+\.png)`\s*\|/gmu,
  )].map((match) => match[1]);
  if (names.length !== SCREENSHOT_FILE_NAMES.length) {
    throw new Error(
      'store-page.md App Store screenshot files must be exactly '
      + `${SCREENSHOT_FILE_NAMES.length}; found ${names.length}`,
    );
  }
  if (new Set(names).size !== names.length) {
    throw new Error('store-page.md screenshot filenames are duplicated.');
  }
  if (JSON.stringify(names) !== JSON.stringify(SCREENSHOT_FILE_NAMES)) {
    throw new Error(
      'store-page.md screenshot file order differs from the release contract.',
    );
  }
  return names;
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
    const actualCrc = pngCrc32(Buffer.concat([typeBuffer, data]));
    if (actualCrc !== expectedCrc) {
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
      if (length !== 0 || sawEnd) {
        throw new Error(`${label} PNG IEND layout is invalid.`);
      }
      sawEnd = true;
      if (chunkEnd !== buffer.length) {
        throw new Error(`${label} unexpected data after PNG IEND.`);
      }
    }
    offset = chunkEnd;
    if (sawEnd) break;
  }
  if (!header || imageData.length === 0 || !sawEnd) {
    throw new Error(`${label} PNG requires IHDR, IDAT, and IEND.`);
  }
  const width = header.readUInt32BE(0);
  const height = header.readUInt32BE(4);
  const bitDepth = header[8];
  const colorType = header[9];
  const compression = header[10];
  const filter = header[11];
  const interlace = header[12];
  if (width < 1 || height < 1) {
    throw new Error(`${label} PNG dimensions cannot be 0.`);
  }
  if (bitDepth !== 8 || colorType !== 2) {
    throw new Error(
      `${label} must be an RGB24 PNG: bitDepth=${bitDepth}, `
      + `colorType=${colorType}`,
    );
  }
  if (compression !== 0 || filter !== 0 || interlace !== 0) {
    throw new Error(
      `${label} PNG must use standard compression/filter and be non-interlaced.`,
    );
  }
  const rowSize = width * 3 + 1;
  const expectedInflatedSize = rowSize * height;
  if (!Number.isSafeInteger(expectedInflatedSize)) {
    throw new Error(`${label} PNG inflated size exceeds the safe range.`);
  }
  let inflated;
  try {
    inflated = inflateSync(
      Buffer.concat(imageData),
      { maxOutputLength: expectedInflatedSize + 1 },
    );
  } catch {
    throw new Error(`${label} could not inflate PNG IDAT compressed data.`);
  }
  if (inflated.length !== expectedInflatedSize) {
    throw new Error(
      `${label} PNG inflated size differs: ${inflated.length} `
      + `(expected ${expectedInflatedSize})`,
    );
  }
  for (let row = 0; row < height; row += 1) {
    if (inflated[row * rowSize] > 4) {
      throw new Error(`${label} PNG scanline filter is invalid.`);
    }
  }
  return { width, height, bitDepth, colorType };
}

function pngArtifact(
  path,
  repoRoot,
  allowedRoot,
  expectedWidth,
  expectedHeight,
  label,
) {
  const artifact = fileArtifact(path, repoRoot, allowedRoot, label);
  const metadata = readPngMetadata(readFileSync(path), label);
  if (
    metadata.width !== expectedWidth
    || metadata.height !== expectedHeight
  ) {
    throw new Error(
      `${label} size differs: ${metadata.width}x${metadata.height} `
      + `(expected ${expectedWidth}x${expectedHeight})`,
    );
  }
  return {
    ...artifact,
    width: metadata.width,
    height: metadata.height,
    format: 'RGB24_PNG',
  };
}

function requireNonempty(value, label) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`${label} value is empty.`);
  }
  return value;
}

export function validateAppleIapText({
  referenceName,
  name,
  description,
  reviewNote,
}, label = 'Apple IAP') {
  const normalizedReferenceName = requireNonempty(
    referenceName,
    `${label} reference name`,
  );
  const normalizedName = requireNonempty(name, `${label} display name`);
  const normalizedDescription = requireNonempty(
    description,
    `${label} description`,
  );
  const normalizedReviewNote = requireNonempty(
    reviewNote,
    `${label} review note`,
  );
  if ([...normalizedReferenceName].length > 64) {
    throw new Error(`${label} reference name exceeds 64 characters.`);
  }
  if (
    [...normalizedName].length < 2
    || [...normalizedName].length > 30
  ) {
    throw new Error(`${label} display name must be 2–30 characters.`);
  }
  if ([...normalizedDescription].length > 45) {
    throw new Error(`${label} description exceeds 45 characters.`);
  }
  if ([...normalizedReviewNote].length > 4000) {
    throw new Error(`${label} review note exceeds 4,000 characters.`);
  }
}

export function buildAppStoreReviewNotes(products) {
  if (!Array.isArray(products)) {
    throw new TypeError('App Review notes require an IAP product array.');
  }
  const productIds = products.map((product) => product?.productId);
  if (
    productIds.length !== IAP_PRODUCT_IDS.length
    || new Set(productIds).size !== IAP_PRODUCT_IDS.length
    || IAP_PRODUCT_IDS.some((productId) => !productIds.includes(productId))
  ) {
    throw new Error(
      'App Review notes must match exactly the 10 sale IAPs excluding hero_bundle.',
    );
  }
  const productList = IAP_PRODUCT_IDS.map((productId) => {
    const product = products.find((candidate) => (
      candidate.productId === productId
    ));
    const english = product.localizations?.find((localization) => (
      localization.locale === 'en-US'
    ));
    const name = requireNonempty(
      english?.name,
      `${productId} App Review display name`,
    );
    requireNonempty(
      product.reviewNote,
      `${productId} App Review test guidance`,
    );
    return `- ${name}: ${productId}`;
  });
  const notes = [
    'App Review test instructions — 7 non-consumables and 3 consumables',
    '',
    'No app account or demo login is required. Launch the app and tap Store '
      + 'on the title screen. This submission contains exactly these ten '
      + 'optional in-app purchases:',
    ...productList,
    '',
    'Heroes: In Store, swipe to a paid hero and tap its portrait to preview '
      + 'the full character art and attack effects. Purchase unlocks that hero '
      + 'in Moon Shrine. All five are balanced cosmetic sidegrades; the free '
      + 'Moonlit Warden can complete the full game.',
    '',
    'Moonlit Supporter: Open Store > Moonlit Supporter. Purchase adds the '
      + 'current local high-score name and a supporter mark in Settings > '
      + 'Credits (or Nameless if no name exists). It has no combat effect.',
    '',
    'Lantern Colors: Open Store > Lantern Colors. Purchase unlocks Moon, '
      + 'Violet, and Jade for selection in the same panel. It has no combat '
      + 'effect.',
    '',
    'Continue Coins: Buy them in advance from Store on the title screen. After '
      + 'defeat, if at least one coin is held, tap Continue to spend exactly '
      + 'one coin and resume that run at the fall point with score, level, and '
      + 'relics preserved. With zero coins, the button ends the current run and '
      + 'moves to the title-screen Store; no purchase occurs on the result '
      + 'screen. The three products grant exactly 1, 5, or 10 coins; coins '
      + 'stack and each product can be bought again.',
    '',
    'Restoration: Tap Restore purchases at the bottom of Store after reinstall '
      + 'or on another device. It idempotently restores the seven verified '
      + 'non-consumables. Continue Coins are consumables and are not restored.',
    '',
    'The legacy hero_bundle product is not offered for sale and is excluded from '
      + 'this submission. Restore purchases only preserves entitlements for '
      + 'customers who bought it previously.',
  ].join('\n');
  if ([...notes].length > 4000) {
    throw new Error('App Review notes exceed 4,000 characters.');
  }
  return notes;
}

function findUniqueRow(rows, predicate, label) {
  const matches = rows.filter(predicate);
  if (matches.length !== 1) {
    throw new Error(`${label} row must appear exactly once: found ${matches.length}`);
  }
  return matches[0];
}

function parseVersion(markdown) {
  const matches = [...markdown.matchAll(
    /^\|\s*Version\s*\|\s*([0-9]+(?:\.[0-9]+){1,2})\s*\|$/gmu,
  )];
  if (matches.length !== 1) {
    throw new Error(
      `store-page.md release version must appear exactly once: `
      + `found ${matches.length}`,
    );
  }
  return matches[0][1];
}

function parseCopyright(markdown) {
  const match = markdown.match(
    /App Store copyright\s*—\s*`([^`]+)`/u,
  );
  if (!match) {
    throw new Error('could not find App Store copyright in store-page.md.');
  }
  return match[1];
}

function sourceArtifact(path, repoRoot, label) {
  return fileArtifact(path, repoRoot, repoRoot, label);
}

function safeRelativeArtifactPath(value, label) {
  requireNonempty(value, label);
  if (
    isAbsolute(value)
    || value.includes('\\')
    || value.split('/').some((part) => part === '' || part === '.' || part === '..')
  ) {
    throw new Error(`${label} path is not a safe repository-relative path.`);
  }
  return value;
}

function requireSha256(value, label) {
  if (typeof value !== 'string' || !/^[a-f0-9]{64}$/u.test(value)) {
    throw new Error(`${label} SHA-256 format is invalid.`);
  }
  return value;
}

function parseJsonArtifact(path, repoRoot, allowedRoot, label) {
  assertNoSymbolicLinkComponents(repoRoot, path, label);
  const entry = assertRegularFile(path, allowedRoot, label);
  if (entry.size > APP_STORE_MAX_JSON_BYTES) {
    throw new Error(`${label} JSON exceeds the allowed size.`);
  }
  const contents = readFileSync(path);
  const artifact = {
    path: normalizeRelativePath(relative(repoRoot, path)),
    fileName: path.split(sep).at(-1),
    size: entry.size,
    ...fileChecksums(contents),
  };
  let value;
  try {
    value = JSON.parse(contents.toString('utf8'));
  } catch {
    throw new Error(`${label} could not read JSON.`);
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} JSON top-level value must be an object.`);
  }
  return { artifact, value };
}

function validateCaptureOrigin(origin, target, iphoneSourceMode) {
  if (!origin || typeof origin !== 'object' || Array.isArray(origin)) {
    throw new Error(`${target.directory} capture_origin is invalid.`);
  }
  const expectedOrigin = target.directory === 'iphone-6.5'
    && iphoneSourceMode === 'android-pixel-avd'
    ? {
      environment: 'AVD',
      nativeIosCapture: false,
      platform: 'ANDROID',
    }
    : {
      environment: 'PHYSICAL_DEVICE',
      nativeIosCapture: true,
      platform: 'IOS',
    };
  if (
    origin.platform !== expectedOrigin.platform
    || origin.environment !== expectedOrigin.environment
    || origin.native_ios_capture !== expectedOrigin.nativeIosCapture
  ) {
    throw new Error(
      `${target.directory} capture_origin differs from the ${iphoneSourceMode} source.`,
    );
  }
  safeRelativeArtifactPath(
    origin.capture_report_path,
    `${target.directory} capture report`,
  );
  requireSha256(
    origin.capture_report_sha256,
    `${target.directory} capture report`,
  );
  requireSha256(origin.runtime_sha256, `${target.directory} runtime`);
  requireSha256(origin.input_sha256, `${target.directory} input`);
  safeRelativeArtifactPath(
    origin.build_artifact_path,
    `${target.directory} build artifact`,
  );
  requireSha256(
    origin.build_artifact_sha256,
    `${target.directory} build artifact`,
  );
}

function validateScreenshotTransform(transform, target) {
  if (
    !transform
    || transform.kind !== 'marketing-composite'
    || transform.stretch !== false
    || !Number.isInteger(transform.crop_bottom)
    || transform.crop_bottom < 0
    || !Number.isInteger(transform.scaled_width)
    || transform.scaled_width < 1
    || !Number.isInteger(transform.scaled_height)
    || transform.scaled_height < 1
    || !Number.isInteger(transform.offset_x)
    || !Number.isInteger(transform.offset_y)
  ) {
    throw new Error(`${target.directory} marketing transform is invalid.`);
  }
  safeRelativeArtifactPath(
    transform.renderer_path,
    `${target.directory} renderer`,
  );
  requireSha256(transform.renderer_sha256, `${target.directory} renderer`);
}

function validateScreenshotProvenance({
  appLocalizations,
  captureReportArtifact,
  provenance,
}) {
  if (
    provenance.schema_version !== SCREENSHOT_PROVENANCE_SCHEMA_VERSION
    || provenance.contract !== SCREENSHOT_PROVENANCE_CONTRACT
    || !['physical-ios', 'android-pixel-avd'].includes(
      provenance.iphone_source_mode,
    )
  ) {
    throw new Error('App Store screenshot provenance contract is invalid.');
  }
  const captureReport = provenance.capture_report;
  if (
    !captureReport
    || captureReport.path !== APP_STORE_CAPTURE_REPORT_RELATIVE_PATH
    || captureReport.file_size !== captureReportArtifact.size
    || captureReport.sha256 !== captureReportArtifact.sha256
  ) {
    throw new Error(
      'App Store provenance canonical capture report differs from the current file.',
    );
  }
  if (!Array.isArray(provenance.sets)) {
    throw new Error('App Store provenance sets is not an array.');
  }
  const setIds = provenance.sets.map((set) => set?.id);
  const expectedSetIds = SCREENSHOT_TARGETS.map((target) => target.directory);
  if (
    provenance.sets.length !== SCREENSHOT_TARGETS.length
    || new Set(setIds).size !== SCREENSHOT_TARGETS.length
    || canonicalJson([...setIds].sort())
      !== canonicalJson([...expectedSetIds].sort())
  ) {
    throw new Error('App Store provenance screenshot set layout differs.');
  }

  for (const target of SCREENSHOT_TARGETS) {
    const set = provenance.sets.find((candidate) => (
      candidate?.id === target.directory
    ));
    const submission = set?.submission_target;
    if (
      submission?.platform !== 'IOS'
      || submission.device_class !== target.directory
      || submission.display_type !== target.displayType
      || submission.width !== target.width
      || submission.height !== target.height
    ) {
      throw new Error(
        `${target.directory} App Store submission target is invalid.`,
      );
    }
    validateCaptureOrigin(
      set.capture_origin,
      target,
      provenance.iphone_source_mode,
    );
    if (
      target.directory === 'iphone-6.5'
      && provenance.iphone_source_mode === 'android-pixel-avd'
      && (
        set.capture_origin.capture_report_path !== captureReport.path
        || set.capture_origin.capture_report_sha256 !== captureReport.sha256
      )
    ) {
      throw new Error(
        'iPhone marketing provenance is not linked to the canonical Android '
        + 'capture report.',
      );
    }
    validateScreenshotTransform(set.transform, target);
    if (
      !Array.isArray(set.mappings)
      || set.mappings.length !== SCREENSHOT_MAPPINGS_PER_SET
    ) {
      throw new Error(
        `${target.directory} provenance mapping must have `
        + `${SCREENSHOT_MAPPINGS_PER_SET} entries.`,
      );
    }

    const expectedOutputs = new Map();
    for (const localization of appLocalizations) {
      const screenshotSet = localization.screenshots.find((candidate) => (
        candidate.device === target.directory
      ));
      for (const artifact of screenshotSet.files) {
        expectedOutputs.set(artifact.path, {
          artifact,
          locale: localization.locale,
        });
      }
    }
    const seenOutputs = new Set();
    for (const mapping of set.mappings) {
      const outputPath = safeRelativeArtifactPath(
        mapping?.output_path,
        `${target.directory} provenance output`,
      );
      const expected = expectedOutputs.get(outputPath);
      if (
        !expected
        || seenOutputs.has(outputPath)
        || mapping.store_locale !== expected.locale
        || mapping.output_sha256 !== expected.artifact.sha256
        || mapping.output_width !== target.width
        || mapping.output_height !== target.height
      ) {
        throw new Error(
          `${target.directory} provenance output mapping differs from the actual PNG: `
          + outputPath,
        );
      }
      requireNonempty(mapping.asset_locale, `${outputPath} asset locale`);
      requireNonempty(mapping.game_locale, `${outputPath} game locale`);
      requireNonempty(mapping.kind, `${outputPath} kind`);
      safeRelativeArtifactPath(mapping.source_path, `${outputPath} source`);
      requireSha256(mapping.source_sha256, `${outputPath} source`);
      safeRelativeArtifactPath(mapping.proof_path, `${outputPath} proof`);
      requireSha256(mapping.proof_sha256, `${outputPath} proof`);
      if (
        !Number.isInteger(mapping.source_width)
        || mapping.source_width < 1
        || !Number.isInteger(mapping.source_height)
        || mapping.source_height < 1
      ) {
        throw new Error(`${outputPath} provenance source size is invalid.`);
      }
      seenOutputs.add(outputPath);
    }
    if (seenOutputs.size !== expectedOutputs.size) {
      throw new Error(`${target.directory} provenance output mapping is missing.`);
    }
  }
  return {
    captureReportPath: APP_STORE_CAPTURE_REPORT_RELATIVE_PATH,
    contract: SCREENSHOT_PROVENANCE_CONTRACT,
    iphoneSourceMode: provenance.iphone_source_mode,
    provenancePath: APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
    setIds: expectedSetIds,
  };
}

function screenshotDirectoryFiles(repoRoot, directory, label) {
  assertNoSymbolicLinkComponents(repoRoot, directory, label);
  if (!existsSync(directory)) {
    throw new Error(`${label} directory is missing: ${directory}`);
  }
  const entry = lstatSync(directory);
  if (!entry.isDirectory() || entry.isSymbolicLink()) {
    throw new Error(`${label} must be a regular directory: ${directory}`);
  }
  const pngs = readdirSync(directory)
    .filter((name) => extname(name).toLowerCase() === '.png')
    .sort();
  const expected = [...SCREENSHOT_FILE_NAMES].sort();
  if (JSON.stringify(pngs) !== JSON.stringify(expected)) {
    const missing = expected.filter((name) => !pngs.includes(name));
    const unexpected = pngs.filter((name) => !expected.includes(name));
    throw new Error(
      `${label} PNG set differs. `
      + `missing: ${missing.join(', ') || 'none'}; `
      + `unexpected: ${unexpected.join(', ') || 'none'}`,
    );
  }
}

function buildScreenshotSets(repoRoot, appStoreRoot, locale) {
  return SCREENSHOT_TARGETS.map((target) => {
    const directory = join(appStoreRoot, locale, target.directory);
    const label = `App Store ${locale}/${target.directory}`;
    screenshotDirectoryFiles(repoRoot, directory, label);
    const files = SCREENSHOT_FILE_NAMES.map((fileName) => pngArtifact(
      join(directory, fileName),
      repoRoot,
      appStoreRoot,
      target.width,
      target.height,
      `${label}/${fileName}`,
    ));
    return {
      device: target.directory,
      displayType: target.displayType,
      width: target.width,
      height: target.height,
      files,
    };
  });
}

function assertIapReviewDirectory(repoRoot, directory) {
  const label = 'App Store per-product IAP review images';
  assertNoSymbolicLinkComponents(repoRoot, directory, label);
  if (!existsSync(directory)) {
    throw new Error(`${label} directory is missing: ${directory}`);
  }
  const entry = lstatSync(directory);
  if (!entry.isDirectory() || entry.isSymbolicLink()) {
    throw new Error(`${label} must be a regular directory: ${directory}`);
  }
  const actual = readdirSync(directory)
    .filter((name) => extname(name).toLowerCase() === '.png')
    .sort();
  const expected = Object.values(IAP_REVIEW_FILE_BY_PRODUCT_ID).sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    const missing = expected.filter((name) => !actual.includes(name));
    const unexpected = actual.filter((name) => !expected.includes(name));
    throw new Error(
      `${label} PNG set differs. `
      + `missing: ${missing.join(', ') || 'none'}; `
      + `unexpected: ${unexpected.join(', ') || 'none'}`,
    );
  }
}

function buildContactState(contactPlan) {
  if (!contactPlan) {
    return {
      status: 'unresolved',
      localizations: Object.fromEntries(
        APPLE_LOCALES.map((locale) => [
          locale,
          {
            privacyPolicyUrl: null,
            supportUrl: null,
          },
        ]),
      ),
      gates: [
        {
          code: 'PUBLIC_PRIVACY_POLICY_URL_REQUIRED',
          field: 'privacyPolicyUrl',
          reason:
            'public support-site base URL and public approval are not confirmed yet.',
        },
        {
          code: 'PUBLIC_SUPPORT_URL_REQUIRED',
          field: 'supportUrl',
          reason:
            'public support-site base URL and public approval are not confirmed yet.',
        },
      ],
    };
  }
  for (const locale of APPLE_LOCALES) {
    const localization = contactPlan.appStore?.[locale];
    invariant(
      localization
      && typeof localization.privacyPolicyUrl === 'string'
      && typeof localization.supportUrl === 'string',
      `public contact plan is missing the ${locale} URL.`,
    );
  }
  return {
    status: 'resolved',
    localizations: Object.fromEntries(
      APPLE_LOCALES.map((locale) => [
        locale,
        {
          privacyPolicyUrl:
            contactPlan.appStore[locale].privacyPolicyUrl,
          supportUrl: contactPlan.appStore[locale].supportUrl,
        },
      ]),
    ),
    gates: [],
  };
}

export function runAppStoreScreenshotValidation(repoRoot, {
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
      '--check-app-store-screenshots',
    ],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: childEnv,
      killSignal: 'SIGTERM',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 10 * 60 * 1000,
    },
  );
  if (result.status !== 0 || result.error) {
    throw new Error(
      'App Store screenshot validation failed. '
      + 'Pass build_store_graphics.py --check-app-store-screenshots '
      + 'first.',
    );
  }
  return true;
}

export function buildAppStoreReleasePayload({
  repoRoot,
  appId = DEFAULT_APP_STORE_APP_ID,
  contactPlan = null,
} = {}) {
  requireNonempty(repoRoot, 'repository root');
  if (!/^[0-9]+$/u.test(appId)) {
    throw new Error(`App Apple ID format is invalid: ${appId}`);
  }
  const root = resolve(repoRoot);
  const csvPath = join(root, 'notes/release/store-localizations.csv');
  const storePagePath = join(root, 'notes/release/store-page.md');
  const projectPath = join(root, 'apps/game/project.godot');
  const exportPresetsPath = join(root, 'apps/game/export_presets.cfg');
  const appStoreRoot = join(root, 'builds/release/app-store');

  assertRegularFile(csvPath, root, 'store localization CSV');
  assertRegularFile(storePagePath, root, 'store page document');
  assertRegularFile(projectPath, root, 'Godot project settings');
  assertRegularFile(exportPresetsPath, root, 'Godot export preset');
  const csvSource = readFileSync(csvPath, 'utf8');
  const markdown = readFileSync(storePagePath, 'utf8');
  const projectSource = readFileSync(projectPath, 'utf8');
  const exportPresetsSource = readFileSync(exportPresetsPath, 'utf8');
  const rows = csvRowsAsObjects(csvSource);
  extractScreenshotFileNames(markdown);
  const releaseMetadata = readIosReleaseMetadata(
    projectSource,
    exportPresetsSource,
  );
  assertIosReleaseMetadata(releaseMetadata, {
    expectedBundleId: APP_STORE_BUNDLE_ID,
    expectedTeamId: APP_STORE_TEAM_ID,
  });
  const storeVersion = parseVersion(markdown);
  if (storeVersion !== releaseMetadata.shortVersion) {
    throw new Error(
      `store-page.md release version ${storeVersion} differs from iOS display version `
      + `${releaseMetadata.shortVersion}.`,
    );
  }
  if (contactPlan && !projectContactMatches(projectSource, contactPlan)) {
    throw new Error(
      'public contact environment differs from in-app links in project.godot. '
      + 'Run configure-store-contact --apply, then rebuild the iOS archive.',
    );
  }

  const descriptions = Object.fromEntries(
    APPLE_LOCALES.map((locale) => [
      locale,
      extractMarkdownTextBlock(markdown, DESCRIPTION_HEADINGS[locale]),
    ]),
  );
  const whatsNewByLocale = Object.fromEntries(
    APPLE_LOCALES.map((locale) => [
      locale,
      validateAppleWhatsNew(
        extractMarkdownTextBlock(markdown, WHATS_NEW_HEADINGS[locale]),
        `${locale} App Store What's New`,
      ),
    ]),
  );
  const contact = buildContactState(contactPlan);

  let appLocalizations = APPLE_LOCALES.map((locale) => {
    const row = findUniqueRow(
      rows,
      (candidate) => (
        candidate.record_type === 'app'
        && candidate.platform === 'apple'
        && candidate.locale === locale
        && candidate.product_id === ''
      ),
      `Apple app ${locale}`,
    );
    const name = requireNonempty(row.display_name, `${locale} app name`);
    const subtitle = requireNonempty(row.subtitle, `${locale} app subtitle`);
    const promotionalText = requireNonempty(
      row.promotional_text,
      `${locale} promotional text`,
    );
    const keywords = requireNonempty(row.keywords, `${locale} keywords`);
    const description = descriptions[locale];
    if ([...name].length > 30 || [...subtitle].length > 30) {
      throw new Error(`${locale} app name or subtitle exceeds 30 characters.`);
    }
    if ([...promotionalText].length > 170) {
      throw new Error(`${locale} promotional text exceeds 170 characters.`);
    }
    if (Buffer.byteLength(keywords, 'utf8') > 100) {
      throw new Error(`${locale} App Store keywords exceed 100 bytes.`);
    }
    if ([...description].length > 4000) {
      throw new Error(`${locale} App Store description exceeds 4,000 characters.`);
    }
    return {
      locale,
      appInfo: {
        name,
        subtitle,
        privacyPolicyUrl: contact.localizations[locale].privacyPolicyUrl,
      },
      version: {
        description,
        keywords,
        promotionalText,
        supportUrl: contact.localizations[locale].supportUrl,
        whatsNew: whatsNewByLocale[locale],
      },
      screenshots: buildScreenshotSets(root, appStoreRoot, locale),
    };
  });

  const captureReportPath = join(
    root,
    APP_STORE_CAPTURE_REPORT_RELATIVE_PATH,
  );
  const provenancePath = join(
    root,
    APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH,
  );
  const captureReportRoot = join(root, 'builds/shots/store-localized');
  const { artifact: captureReportArtifact } = parseJsonArtifact(
    captureReportPath,
    root,
    captureReportRoot,
    'canonical Android capture report',
  );
  const {
    artifact: screenshotProvenanceArtifact,
    value: screenshotProvenanceSource,
  } = parseJsonArtifact(
    provenancePath,
    root,
    appStoreRoot,
    'App Store screenshot provenance',
  );
  const screenshotProvenance = validateScreenshotProvenance({
    appLocalizations,
    captureReportArtifact,
    provenance: screenshotProvenanceSource,
  });
  appLocalizations = appLocalizations.map((localization) => ({
    ...localization,
    screenshots: localization.screenshots.map((set) => ({
      ...set,
      provenanceSetId: set.device,
    })),
  }));

  const reviewImageRoot = join(appStoreRoot, 'iap-review');
  if (existsSync(join(appStoreRoot, 'iap-review.png'))) {
    throw new Error(
      'legacy shared iap-review.png cannot be used as a per-product review image.',
    );
  }
  assertIapReviewDirectory(root, reviewImageRoot);

  const iapProducts = IAP_PRODUCT_IDS.map((productId) => {
    const reviewFileName = IAP_REVIEW_FILE_BY_PRODUCT_ID[productId];
    invariant(
      typeof reviewFileName === 'string' && reviewFileName.length > 0,
      `${productId} per-product IAP review image mapping is missing.`,
    );
    const reviewImage = pngArtifact(
      join(reviewImageRoot, reviewFileName),
      root,
      appStoreRoot,
      2778,
      1284,
      `App Store IAP review image ${productId}`,
    );
    const localizedRows = APPLE_LOCALES.map((locale) => findUniqueRow(
      rows,
      (candidate) => (
        candidate.record_type === 'iap'
        && candidate.platform === 'apple'
        && candidate.locale === locale
        && candidate.product_id === productId
      ),
      `Apple IAP ${productId}/${locale}`,
    ));
    const productType = IAP_PRODUCT_TYPE_BY_ID[productId];
    const csvProductType = productType === 'CONSUMABLE'
      ? 'consumable'
      : 'non_consumable';
    for (const [index, row] of localizedRows.entries()) {
      const label = `${productId}/${APPLE_LOCALES[index]}`;
      if (row.product_type !== csvProductType) {
        throw new Error(
          `${label} type must be ${csvProductType}.`,
        );
      }
      validateAppleIapText({
        referenceName: row.reference_name,
        name: row.display_name,
        description: row.description,
        reviewNote: row.review_notes,
      }, label);
    }
    const referenceNames = new Set(
      localizedRows.map((row) => row.reference_name),
    );
    if (referenceNames.size !== 1 || ![...referenceNames][0]) {
      throw new Error(`${productId} reference name differs across locales.`);
    }
    const english = localizedRows[0];
    return {
      productId,
      type: productType,
      referenceName: english.reference_name,
      reviewNote: english.review_notes,
      pricing: {
        strategy: 'VERIFY_EXISTING_MANUAL_BASE_PRICE',
        ...IAP_BASE_PRICES[productId],
      },
      reviewImage,
      reviewImagePath: reviewImage.path,
      localizations: localizedRows.map((row, index) => ({
        locale: APPLE_LOCALES[index],
        name: row.display_name,
        description: row.description,
        operatorReviewNote: row.review_notes,
      })),
    };
  });

  const screenshotCount = appLocalizations.reduce(
    (sum, localization) => sum + localization.screenshots.reduce(
      (inner, screenshotSet) => inner + screenshotSet.files.length,
      0,
    ),
    0,
  );
  const iapLocalizationCount = iapProducts.reduce(
    (sum, product) => sum + product.localizations.length,
    0,
  );
  const reviewImageHashes = new Set(
    iapProducts.map((product) => product.reviewImage.sha256),
  );
  invariant(
    screenshotCount === EXPECTED_SCREENSHOT_COUNT,
    `App Store screenshots must total ${EXPECTED_SCREENSHOT_COUNT}.`,
  );
  invariant(
    reviewImageHashes.size === IAP_PRODUCT_IDS.length,
    "App Store's 10 IAPs each need a distinct real store-location review image.",
  );
  invariant(
    iapLocalizationCount
      === IAP_PRODUCT_IDS.length * APPLE_LOCALES.length,
    `App Store IAP localizations must be ${IAP_PRODUCT_IDS.length} products × `
      + `${APPLE_LOCALES.length} languages.`,
  );

  return {
    release: {
      platform: 'IOS',
      appId,
      bundleId: releaseMetadata.bundleId,
      version: storeVersion,
      buildNumber: releaseMetadata.buildVersion,
      copyright: parseCopyright(markdown),
      availability: APP_AVAILABILITY_REQUIREMENTS,
    },
    sources: [
      sourceArtifact(csvPath, root, 'store localization CSV'),
      sourceArtifact(storePagePath, root, 'store page document'),
      sourceArtifact(projectPath, root, 'Godot project settings'),
      sourceArtifact(exportPresetsPath, root, 'Godot export preset'),
      screenshotProvenanceArtifact,
      captureReportArtifact,
    ],
    contact,
    appStoreReview: {
      notes: buildAppStoreReviewNotes(iapProducts),
    },
    screenshotProvenance,
    appLocalizations,
    inAppPurchases: {
      reviewImages: iapProducts.map((product) => ({
        productId: product.productId,
        ...product.reviewImage,
      })),
      products: iapProducts,
    },
    counts: {
      appLocalizations: appLocalizations.length,
      screenshots: screenshotCount,
      iapProducts: iapProducts.length,
      iapLocalizations: iapLocalizationCount,
      iapReviewImages: iapProducts.length,
    },
  };
}

export function canonicalJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function payloadChecksums(payload) {
  return fileChecksums(Buffer.from(canonicalJson(payload), 'utf8'));
}

export function createAppStoreReleaseManifest(payload) {
  return {
    schemaVersion: 2,
    payload,
    payloadChecksums: payloadChecksums(payload),
  };
}

export function verifyAppStoreReleaseManifest(
  manifest,
  expectedPayload = null,
) {
  if (!manifest || manifest.schemaVersion !== 2 || !manifest.payload) {
    throw new Error('App Store release manifest schema is invalid.');
  }
  const expectedChecksums = payloadChecksums(manifest.payload);
  for (const algorithm of ['sha256', 'md5']) {
    if (
      manifest.payloadChecksums?.[algorithm]
      !== expectedChecksums[algorithm]
    ) {
      throw new Error(
        `App Store release manifest ${algorithm} verification failed.`,
      );
    }
  }
  if (
    expectedPayload
    && canonicalJson(manifest.payload) !== canonicalJson(expectedPayload)
  ) {
    throw new Error(
      'App Store release manifest differs from current metadata/images.',
    );
  }
  const counts = manifest.payload.counts;
  const exactCounts = {
    appLocalizations: APPLE_LOCALES.length,
    screenshots: EXPECTED_SCREENSHOT_COUNT,
    iapProducts: IAP_PRODUCT_IDS.length,
    iapLocalizations: IAP_PRODUCT_IDS.length * APPLE_LOCALES.length,
    iapReviewImages: IAP_PRODUCT_IDS.length,
  };
  if (canonicalJson(counts) !== canonicalJson(exactCounts)) {
    throw new Error('App Store release manifest asset count differs.');
  }
  const expectedReviewNotes = buildAppStoreReviewNotes(
    manifest.payload.inAppPurchases?.products,
  );
  if (manifest.payload.appStoreReview?.notes !== expectedReviewNotes) {
    throw new Error(
      'App Store version review notes differ from the current 10-IAP test/restore guidance.',
    );
  }
  const sourcePaths = manifest.payload.sources?.map((source) => source.path);
  if (
    !Array.isArray(sourcePaths)
    || sourcePaths.filter((path) => (
      path === APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH
    )).length !== 1
    || sourcePaths.filter((path) => (
      path === APP_STORE_CAPTURE_REPORT_RELATIVE_PATH
    )).length !== 1
  ) {
    throw new Error(
      'App Store release manifest requires provenance and a capture report.',
    );
  }
  const screenshotProvenance = manifest.payload.screenshotProvenance;
  const expectedProvenanceSetIds = SCREENSHOT_TARGETS.map(
    (target) => target.directory,
  );
  if (
    screenshotProvenance?.contract !== SCREENSHOT_PROVENANCE_CONTRACT
    || screenshotProvenance.provenancePath
      !== APP_STORE_SCREENSHOT_PROVENANCE_RELATIVE_PATH
    || screenshotProvenance.captureReportPath
      !== APP_STORE_CAPTURE_REPORT_RELATIVE_PATH
    || !['physical-ios', 'android-pixel-avd'].includes(
      screenshotProvenance.iphoneSourceMode,
    )
    || canonicalJson(screenshotProvenance.setIds)
      !== canonicalJson(expectedProvenanceSetIds)
  ) {
    throw new Error('App Store release manifest provenance summary is invalid.');
  }
  const appLocalizations = manifest.payload.appLocalizations;
  if (
    !Array.isArray(appLocalizations)
    || appLocalizations.length !== APPLE_LOCALES.length
    || new Set(appLocalizations.map((entry) => entry?.locale)).size
      !== APPLE_LOCALES.length
  ) {
    throw new Error('App Store release manifest app localization set differs.');
  }
  for (const locale of APPLE_LOCALES) {
    const localization = appLocalizations.find((entry) => (
      entry?.locale === locale
    ));
    validateAppleWhatsNew(
      localization?.version?.whatsNew,
      `${locale} App Store What's New`,
    );
    if (
      !localization
      || !Array.isArray(localization.screenshots)
      || localization.screenshots.length !== SCREENSHOT_TARGETS.length
    ) {
      throw new Error(`App Store ${locale} screenshot set layout differs.`);
    }
    for (const target of SCREENSHOT_TARGETS) {
      const set = localization.screenshots.find((candidate) => (
        candidate?.device === target.directory
      ));
      if (
        set?.provenanceSetId !== target.directory
        || set.displayType !== target.displayType
        || !Array.isArray(set.files)
        || set.files.length !== SCREENSHOT_FILE_NAMES.length
      ) {
        throw new Error(
          `App Store ${locale}/${target.directory} provenance set link `
          + 'is invalid.',
        );
      }
    }
  }
  const products = manifest.payload.inAppPurchases?.products;
  const reviewImages = manifest.payload.inAppPurchases?.reviewImages;
  if (
    !Array.isArray(products)
    || !Array.isArray(reviewImages)
    || products.length !== IAP_PRODUCT_IDS.length
    || reviewImages.length !== IAP_PRODUCT_IDS.length
  ) {
    throw new Error('App Store per-product IAP review image list is invalid.');
  }
  const reviewHashes = new Set();
  for (const [index, productId] of IAP_PRODUCT_IDS.entries()) {
    const product = products[index];
    const reviewImage = reviewImages.find((entry) => (
      entry.productId === productId
    ));
    if (
      product?.productId !== productId
      || productId.endsWith('.hero_bundle')
      || product.type !== IAP_PRODUCT_TYPE_BY_ID[productId]
      || canonicalJson(product.pricing) !== canonicalJson({
        strategy: 'VERIFY_EXISTING_MANUAL_BASE_PRICE',
        ...IAP_BASE_PRICES[productId],
      })
      || !reviewImage
      || reviewImage.fileName !== IAP_REVIEW_FILE_BY_PRODUCT_ID[productId]
      || product.reviewImage?.path !== reviewImage.path
      || product.reviewImage?.sha256 !== reviewImage.sha256
      || reviewHashes.has(reviewImage.sha256)
    ) {
      throw new Error(
        `App Store IAP ${productId} review image mapping is invalid.`,
      );
    }
    reviewHashes.add(reviewImage.sha256);
  }
  if (
    canonicalJson(manifest.payload.release?.availability)
    !== canonicalJson(APP_AVAILABILITY_REQUIREMENTS)
  ) {
    throw new Error('App Store availability-country gate is invalid.');
  }
  return true;
}

export function resolveManifestOutputPath(repoRoot, requestedPath) {
  const root = resolve(repoRoot);
  const output = isAbsolute(requestedPath)
    ? resolve(requestedPath)
    : resolve(root, requestedPath);
  const releaseRoot = resolve(root, 'builds/release');
  if (
    !pathIsInside(releaseRoot, output)
    || output === releaseRoot
    || extname(output).toLowerCase() !== '.json'
  ) {
    throw new Error(
      'App Store release manifest must be JSON under builds/release.',
    );
  }
  const screenshotRoot = resolve(root, 'builds/release/app-store');
  if (pathIsInside(screenshotRoot, output)) {
    throw new Error(
      'App Store release manifest cannot overwrite the screenshot input directory.',
    );
  }
  assertNoSymbolicLinkComponents(root, output, 'App Store release manifest output');
  let existingAncestor = dirname(output);
  while (!existsSync(existingAncestor)) {
    const parent = dirname(existingAncestor);
    if (parent === existingAncestor) break;
    existingAncestor = parent;
  }
  if (
    !existsSync(releaseRoot)
    || !pathIsInside(realpathSync(root), realpathSync(releaseRoot))
    || !pathIsInside(realpathSync(releaseRoot), realpathSync(existingAncestor))
  ) {
    throw new Error(
      'App Store release manifest output path resolves outside builds/release.',
    );
  }
  if (existsSync(output)) {
    const entry = lstatSync(output);
    if (!entry.isFile() || entry.isSymbolicLink()) {
      throw new Error(
        'App Store release manifest output must be a regular file.',
      );
    }
  }
  return output;
}

export function writeAppStoreReleaseManifest(outputPath, manifest) {
  verifyAppStoreReleaseManifest(manifest);
  mkdirSync(dirname(outputPath), { recursive: true });
  const temporary = `${outputPath}.tmp-${process.pid}-${Date.now()}`;
  try {
    writeFileSync(temporary, canonicalJson(manifest), {
      encoding: 'utf8',
      mode: 0o644,
      flag: 'wx',
    });
    renameSync(temporary, outputPath);
  } finally {
    rmSync(temporary, { force: true });
  }
  return outputPath;
}

export function readAndVerifyAppStoreReleaseManifest(
  outputPath,
  expectedPayload,
) {
  if (!existsSync(outputPath)) {
    throw new Error(
      `App Store release manifest is missing: ${outputPath}. `
      + 'Run the default dry-run first.',
    );
  }
  if (lstatSync(outputPath).isSymbolicLink()) {
    throw new Error('App Store release manifest cannot be a symbolic link.');
  }
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(outputPath, 'utf8'));
  } catch {
    throw new Error('could not read App Store release manifest JSON.');
  }
  verifyAppStoreReleaseManifest(manifest, expectedPayload);
  return manifest;
}

export function parseAppStoreReleaseArguments(args = []) {
  if (!Array.isArray(args)) {
    throw new TypeError('App Store release CLI arguments must be an array.');
  }
  const result = {
    apply: false,
    check: false,
    confirmation: null,
    reviewConfirmation: null,
    remoteAudit: false,
    submitReview: false,
    json: false,
    help: false,
    output: DEFAULT_MANIFEST_RELATIVE_PATH,
  };
  const seen = new Set();
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === '--dry-run') {
      if (seen.has(argument)) throw cliError('duplicate --dry-run flag.');
      seen.add(argument);
      continue;
    }
    if (argument === '--check') {
      if (seen.has(argument)) throw cliError('duplicate --check flag.');
      seen.add(argument);
      result.check = true;
      continue;
    }
    if (argument === '--apply') {
      if (seen.has(argument)) throw cliError('duplicate --apply flag.');
      seen.add(argument);
      result.apply = true;
      continue;
    }
    if (argument === '--remote-audit') {
      if (seen.has(argument)) {
        throw cliError('duplicate --remote-audit flag.');
      }
      seen.add(argument);
      result.remoteAudit = true;
      continue;
    }
    if (argument === '--json') {
      if (seen.has(argument)) throw cliError('duplicate --json flag.');
      seen.add(argument);
      result.json = true;
      continue;
    }
    if (argument === '--submit-review') {
      if (seen.has(argument)) {
        throw cliError('duplicate --submit-review flag.');
      }
      seen.add(argument);
      result.submitReview = true;
      continue;
    }
    if (argument === '--help' || argument === '-h') {
      result.help = true;
      continue;
    }
    if (argument === '--output') {
      if (seen.has(argument)) throw cliError('duplicate --output flag.');
      seen.add(argument);
      const value = args[index + 1];
      if (!value || value.startsWith('--')) {
        throw cliError('--output requires a JSON path after it.');
      }
      result.output = value;
      index += 1;
      continue;
    }
    if (
      argument === '--confirm-remote-apply'
      || argument === '--confirm-review-submission'
    ) {
      if (seen.has(argument)) throw cliError(`duplicate ${argument} flag.`);
      seen.add(argument);
      const value = args[index + 1];
      if (!value || value.startsWith('--')) {
        throw cliError(`${argument} requires the token printed by --check.`);
      }
      if (argument === '--confirm-remote-apply') {
        result.confirmation = value;
      } else {
        result.reviewConfirmation = value;
      }
      index += 1;
      continue;
    }
    throw cliError(
      `unsupported App Store release option: ${argument}. `
      + 'Use only the allowed options.',
    );
  }
  if (result.help) return result;
  if (result.apply) {
    if (seen.has('--dry-run')) {
      throw cliError('cannot combine --dry-run and --apply.');
    }
    if (!result.check || !result.remoteAudit || !result.confirmation) {
      throw cliError(
        '--apply requires --check, --remote-audit, and '
        + '--confirm-remote-apply <token>.',
      );
    }
  } else if (result.confirmation !== null) {
    throw cliError('--confirm-remote-apply can only be used with --apply.');
  }
  if (result.submitReview) {
    if (!result.apply || !result.reviewConfirmation) {
      throw cliError(
        '--submit-review requires --apply and '
        + '--confirm-review-submission <token>.',
      );
    }
  } else if (result.reviewConfirmation !== null) {
    throw cliError(
      '--confirm-review-submission can only be used with --submit-review.',
    );
  }
  return result;
}

export function contactPlanFromEnvironment(environment = {}) {
  const siteBaseUrl =
    typeof environment.MOONLIT_PUBLIC_SITE_URL === 'string'
      ? environment.MOONLIT_PUBLIC_SITE_URL.trim()
      : '';
  const supportEmail =
    typeof environment.MOONLIT_SUPPORT_EMAIL === 'string'
      ? environment.MOONLIT_SUPPORT_EMAIL.trim()
      : '';
  if (siteBaseUrl === '' && supportEmail === '') return null;
  if (siteBaseUrl === '' || supportEmail === '') {
    throw cliError(
      'MOONLIT_PUBLIC_SITE_URL and MOONLIT_SUPPORT_EMAIL must be set '
      + 'together.',
    );
  }
  return buildStoreContactPlan({ siteBaseUrl, supportEmail });
}

function base64Url(value) {
  return Buffer.from(value).toString('base64url');
}

export function createAppStoreConnectToken({
  keyId,
  issuerId,
  privateKey,
  now = Date.now(),
}) {
  if (!/^[A-Z0-9]{10}$/u.test(keyId)) {
    throw new Error('App Store Connect Key ID format is invalid.');
  }
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu
      .test(issuerId)
  ) {
    throw new Error('App Store Connect Issuer ID format is invalid.');
  }
  const key = createPrivateKey(privateKey);
  if (
    key.asymmetricKeyType !== 'ec'
    || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1'
  ) {
    throw new Error('App Store Connect JWT requires a P-256 EC private key.');
  }
  const issuedAt = Math.floor(now / 1000);
  const header = base64Url(JSON.stringify({
    alg: 'ES256',
    kid: keyId,
    typ: 'JWT',
  }));
  const payload = base64Url(JSON.stringify({
    iss: issuerId,
    iat: issuedAt,
    exp: issuedAt + 1199,
    aud: 'appstoreconnect-v1',
  }));
  const signingInput = `${header}.${payload}`;
  const signature = sign(
    'sha256',
    Buffer.from(signingInput),
    { key, dsaEncoding: 'ieee-p1363' },
  ).toString('base64url');
  return `${signingInput}.${signature}`;
}

function normalizeApiUrl(pathOrUrl) {
  const url = new URL(pathOrUrl, APP_STORE_ORIGIN);
  if (url.origin !== APP_STORE_ORIGIN) {
    throw new Error('App Store Connect GET page has a disallowed origin.');
  }
  if (url.username || url.password || url.hash) {
    throw new Error(
      'App Store Connect GET URL cannot include credentials or a fragment.',
    );
  }
  if (!url.pathname.startsWith('/v1/') && !url.pathname.startsWith('/v2/')) {
    throw new Error('App Store Connect GET path is not a v1/v2 API path.');
  }
  return url;
}

export function createGetOnlyAppStoreConnectClient({
  fetchImpl = globalThis.fetch,
  timeoutMs = 60_000,
  token,
  tokenProvider = null,
} = {}) {
  if (typeof fetchImpl !== 'function') {
    throw new TypeError('App Store Connect GET requires a fetch function.');
  }
  if (tokenProvider !== null && typeof tokenProvider !== 'function') {
    throw new TypeError('App Store Connect tokenProvider must be a function.');
  }
  if (!tokenProvider) requireNonempty(token, 'App Store Connect JWT');
  const provideToken = tokenProvider ?? (() => token);
  const requests = [];

  async function get(pathOrUrl, { allowNotFound = false } = {}) {
    const url = normalizeApiUrl(pathOrUrl);
    const request = {
      method: 'GET',
      path: `${url.pathname}${url.search}`,
    };
    requests.push(request);
    const requestToken = await provideToken();
    requireNonempty(requestToken, 'App Store Connect JWT');
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let response;
    try {
      response = await fetchImpl(url, {
        method: 'GET',
        headers: {
          Accept: 'application/json',
          Authorization: `Bearer ${requestToken}`,
        },
        redirect: 'error',
        signal: controller.signal,
      });
    } catch (error) {
      throw new Error(
        `App Store Connect GET network failure: ${error.name ?? 'Error'} `
        + `${url.pathname}`,
      );
    } finally {
      clearTimeout(timer);
    }
    if (allowNotFound && response.status === 404) return null;
    if (!response.ok) {
      throw new Error(
        `App Store Connect GET failed: HTTP ${response.status} `
        + `${url.pathname}`,
      );
    }
    const declared = Number(response.headers?.get?.('content-length') ?? 0);
    if (Number.isFinite(declared) && declared > APP_STORE_MAX_JSON_BYTES) {
      throw new Error(
        `App Store Connect GET response is too large: ${url.pathname}`,
      );
    }
    const text = await response.text();
    if (Buffer.byteLength(text) > APP_STORE_MAX_JSON_BYTES) {
      throw new Error(
        `App Store Connect GET response is too large: ${url.pathname}`,
      );
    }
    try {
      return JSON.parse(text);
    } catch {
      throw new Error(
        `App Store Connect GET response is not JSON: ${url.pathname}`,
      );
    }
  }

  async function getAll(pathOrUrl) {
    const data = [];
    let next = pathOrUrl;
    let pages = 0;
    while (next) {
      pages += 1;
      if (pages > 50) {
        throw new Error('App Store Connect GET exceeded 50 pages.');
      }
      const response = await get(next);
      if (!Array.isArray(response.data)) {
        throw new Error('App Store Connect list response data is not an array.');
      }
      data.push(...response.data);
      next = response.links?.next ?? null;
    }
    return data;
  }

  return Object.freeze({
    get,
    getAll,
    get requests() {
      return requests.map((request) => ({ ...request }));
    },
  });
}

function queryPath(pathname, entries) {
  const query = new URLSearchParams(entries);
  return `${pathname}?${query.toString()}`;
}

function attributes(resource) {
  return resource?.attributes ?? {};
}

export function selectAppInfoForVersion(appInfos, versionResource = null) {
  if (!Array.isArray(appInfos)) {
    throw new TypeError('remote App Info list must be an array.');
  }
  if (!versionResource) {
    const draftCandidates = appInfos.filter((resource) => {
      const resourceAttributes = attributes(resource);
      return normalizeAppVersionState(
        resourceAttributes.state ?? resourceAttributes.appStoreState,
      ) === 'PREPARE_FOR_SUBMISSION';
    });
    if (draftCandidates.length > 1) {
      throw new Error(
        'remote PREPARE_FOR_SUBMISSION App Info is duplicated.',
      );
    }
    return draftCandidates[0] ?? null;
  }
  if (appInfos.length === 0) {
    throw new Error('remote App Info resource was not found.');
  }
  const targetState = appVersionState(versionResource)
    ?? 'PREPARE_FOR_SUBMISSION';
  const candidates = appInfos.filter((resource) => {
    const resourceAttributes = attributes(resource);
    return normalizeAppVersionState(
      resourceAttributes.state ?? resourceAttributes.appStoreState,
    ) === targetState;
  });
  if (candidates.length === 1) return candidates[0];
  if (
    appInfos.length === 1
    && attributes(appInfos[0]).appStoreState === undefined
    && attributes(appInfos[0]).state === undefined
  ) {
    return appInfos[0];
  }
  const states = appInfos.map((resource) => (
    attributes(resource).appStoreState
    ?? attributes(resource).state
    ?? 'UNKNOWN'
  ));
  throw new Error(
    `could not select exactly one remote App Info in state ${targetState}: `
    + `${states.join(', ')}`,
  );
}

export function iapStateReadinessPlan(productId, remoteProduct) {
  requireNonempty(productId, 'IAP product ID');
  const state = attributes(remoteProduct).state ?? 'UNKNOWN';
  if (READY_IAP_STATES.has(state)) return null;
  return {
    action: 'unresolved',
    target: 'inAppPurchaseReadiness',
    identifier: productId,
    remoteId: remoteProduct?.id ?? null,
    code: 'IAP_REMOTE_STATE_NOT_RELEASE_READY',
    remoteState: state,
    reason:
      'IAP remote state is not READY_TO_SUBMIT or APPROVED. '
      + 'The owner must confirm price, availability, metadata, and review state.',
    remoteMutationPlanned: false,
  };
}

function uniqueByAttribute(resources, key, value, label) {
  const matches = resources.filter(
    (resource) => attributes(resource)[key] === value,
  );
  if (matches.length > 1) {
    throw new Error(`remote ${label} is duplicated: ${value}`);
  }
  return matches[0] ?? null;
}

function changesBetween(desired, actual) {
  return Object.fromEntries(
    Object.entries(desired)
      .filter(([, value]) => value !== null && value !== undefined)
      .filter(([key, value]) => actual?.[key] !== value)
      .map(([key, value]) => [
        key,
        {
          current: actual?.[key] ?? null,
          desired: value,
        },
      ]),
  );
}

function addMetadataPlan(
  plan,
  target,
  identifier,
  desired,
  remoteResource,
  prerequisites = [],
) {
  const definedDesired = Object.fromEntries(
    Object.entries(desired).filter(
      ([, value]) => value !== null && value !== undefined,
    ),
  );
  if (!remoteResource) {
    plan.push({
      action: 'create',
      target,
      identifier,
      desired: definedDesired,
      prerequisites,
    });
    return;
  }
  const changes = changesBetween(definedDesired, attributes(remoteResource));
  plan.push({
    action: Object.keys(changes).length === 0 ? 'none' : 'update',
    target,
    identifier,
    remoteId: remoteResource.id,
    changes,
    prerequisites,
  });
}

function addAppStoreReviewNotesPlan(
  plan,
  identifier,
  desiredNotes,
  remoteResource,
  prerequisites = [],
) {
  const matches = attributes(remoteResource).notes === desiredNotes;
  plan.push({
    action: matches ? 'none' : 'update',
    target: 'appStoreReviewDetail',
    identifier,
    remoteId: remoteResource.id,
    ...(matches ? {} : { desired: { notes: desiredNotes } }),
    prerequisites,
  });
}

function normalizeChecksum(value) {
  return typeof value === 'string' ? value.toLowerCase() : null;
}

function screenshotFilesMatch(localFiles, remoteFiles) {
  if (localFiles.length !== remoteFiles.length) return false;
  return localFiles.every((localFile, index) => {
    const remote = attributes(remoteFiles[index]);
    return remote.fileName === localFile.fileName
      && Number(remote.fileSize) === localFile.size
      && normalizeChecksum(remote.sourceFileChecksum) === localFile.md5
      && (
        remote.assetDeliveryState?.state === undefined
        || remote.assetDeliveryState?.state === 'COMPLETE'
      );
  });
}

// After Apple accepts an IAP review screenshot it rewrites fileName to the
// literal 'SOURCE' (confirmed after ~40 hero_dancer uploads). Unlike app
// screenshots the original name is not preserved, so the name check also
// allows SOURCE. Still require byte identity via size/MD5 and completion via
// assetDeliveryState.
export function iapReviewImageMatches(localFile, remoteResource) {
  const remote = attributes(remoteResource);
  const nameMatches = remote.fileName === localFile.fileName
    || remote.fileName === 'SOURCE';
  return nameMatches
    && Number(remote.fileSize) === localFile.size
    && normalizeChecksum(remote.sourceFileChecksum) === localFile.md5
    && (
      remote.assetDeliveryState?.state === undefined
      || remote.assetDeliveryState?.state === 'COMPLETE'
    );
}

function unresolvedContactPlans(payload) {
  if (payload.contact.status === 'resolved') return [];
  return payload.contact.gates.map((gate) => ({
    action: 'unresolved',
    target: 'publicContactUrl',
    identifier: gate.field,
    code: gate.code,
    reason: gate.reason,
    remoteMutationPlanned: false,
  }));
}

export function summarizeRemotePlan(plan) {
  const summary = {
    create: 0,
    update: 0,
    replace: 0,
    none: 0,
    unresolved: 0,
  };
  for (const entry of plan) {
    if (!(entry.action in summary)) summary[entry.action] = 0;
    summary[entry.action] += 1;
  }
  return summary;
}

export async function auditAppStoreConnectRelease({
  payload,
  client,
} = {}) {
  if (!payload?.release || !client?.get || !client?.getAll) {
    throw new TypeError('local release payload and a GET-only ASC client are required.');
  }
  const { appId, version } = payload.release;
  const plan = [...unresolvedContactPlans(payload)];
  const appResponse = await client.get(queryPath(
    `/v1/apps/${appId}`,
    [['fields[apps]', 'bundleId']],
  ));
  const remoteApp = appResponse?.data;
  if (
    !remoteApp
    || attributes(remoteApp).bundleId !== payload.release.bundleId
  ) {
    throw new Error(
      `remote App Apple ID ${appId} bundleId differs from the local release settings.`,
    );
  }
  const appStoreReviewNotes = requireNonempty(
    payload.appStoreReview?.notes,
    'App Store version review notes',
  );

  const exactVersionResources = await client.getAll(queryPath(
    `/v1/apps/${appId}/appStoreVersions`,
    [
      ['filter[platform]', 'IOS'],
      ['filter[versionString]', version],
      ['fields[appStoreVersions]',
        'platform,versionString,appStoreState,appVersionState,copyright'],
      ['limit', '2'],
    ],
  ));
  if (exactVersionResources.length > 1) {
    throw new Error(`remote iOS ${version} version is duplicated.`);
  }
  let allVersionResources = exactVersionResources;
  let versionResource = exactVersionResources[0] ?? null;
  let versionSelectionBlocker = null;
  if (
    versionResource
    && !isAdoptableAppVersionState(appVersionState(versionResource))
  ) {
    versionSelectionBlocker = {
      action: 'unresolved',
      target: 'appStoreVersion',
      identifier: `IOS/${version}`,
      code: 'ASC_APP_STORE_VERSION_NOT_ADOPTABLE',
      reason:
        `remote iOS ${version} version state `
        + `${appVersionState(versionResource) ?? 'UNKNOWN'} cannot be changed automatically.`,
      remoteMutationPlanned: false,
    };
  }
  if (!versionResource) {
    allVersionResources = await client.getAll(queryPath(
      `/v1/apps/${appId}/appStoreVersions`,
      [
        ['filter[platform]', 'IOS'],
        ['fields[appStoreVersions]',
          'platform,versionString,appStoreState,appVersionState,copyright'],
        ['limit', '200'],
      ],
    ));
    const desiredVersions = allVersionResources.filter((resource) => (
      attributes(resource).versionString === version
    ));
    if (desiredVersions.length > 1) {
      throw new Error(`remote iOS ${version} version is duplicated.`);
    }
    const adoptableVersions = allVersionResources.filter((resource) => (
      isAdoptableAppVersionState(appVersionState(resource))
    ));
    const desiredVersionId = desiredVersions[0]?.id ?? null;
    const competingAdoptableVersions = adoptableVersions.filter((resource) => (
      resource.id !== desiredVersionId
    ));
    if (desiredVersions.length === 1) {
      [versionResource] = desiredVersions;
      if (!isAdoptableAppVersionState(appVersionState(versionResource))) {
        versionSelectionBlocker = {
          action: 'unresolved',
          target: 'appStoreVersion',
          identifier: `IOS/${version}`,
          code: 'ASC_APP_STORE_VERSION_NOT_ADOPTABLE',
          reason:
            `remote iOS ${version} version state `
            + `${appVersionState(versionResource) ?? 'UNKNOWN'} cannot be changed automatically.`,
          remoteMutationPlanned: false,
        };
      } else if (competingAdoptableVersions.length > 0) {
        versionSelectionBlocker = {
          action: 'unresolved',
          target: 'appStoreVersion',
          identifier: `IOS/${version}`,
          code: 'ASC_APP_STORE_VERSION_ADOPTION_AMBIGUOUS',
          reason:
            'a reusable iOS pre-release version exists besides the requested version, '
            + 'so the version is not selected automatically.',
          remoteMutationPlanned: false,
        };
      }
    } else if (adoptableVersions.length > 1) {
      versionSelectionBlocker = {
        action: 'unresolved',
        target: 'appStoreVersion',
        identifier: `IOS/${version}`,
        code: 'ASC_APP_STORE_VERSION_ADOPTION_AMBIGUOUS',
        reason:
          'more than one reusable iOS pre-release version exists, so the version '
          + 'is not selected automatically.',
        remoteMutationPlanned: false,
      };
    } else if (adoptableVersions.length === 1) {
      [versionResource] = adoptableVersions;
    } else if (!canCreateNewAppStoreVersion(allVersionResources)) {
      versionSelectionBlocker = {
        action: 'unresolved',
        target: 'appStoreVersion',
        identifier: `IOS/${version}`,
        code: 'ASC_APP_STORE_VERSION_CREATE_UNSAFE',
        reason:
          'cannot prove the current iOS version is Ready for Distribution, and no '
          + 'pre-release version is safe to reuse.',
        remoteMutationPlanned: false,
      };
    }
  }

  const appInfos = await client.getAll(queryPath(
    `/v1/apps/${appId}/appInfos`,
    [
      ['fields[appInfos]', 'appStoreState,state'],
      ['limit', '50'],
    ],
  ));
  const appInfo = versionSelectionBlocker
    ? null
    : selectAppInfoForVersion(appInfos, versionResource);
  const appInfoLocalizations = appInfo
    ? await client.getAll(queryPath(
      `/v1/appInfos/${appInfo.id}/appInfoLocalizations`,
      [
        ['fields[appInfoLocalizations]',
          'locale,name,subtitle,privacyPolicyUrl'],
        ['limit', '200'],
      ],
    ))
    : [];

  let versionLocalizations = [];
  if (versionResource) {
    if (versionSelectionBlocker) {
      plan.push(versionSelectionBlocker);
    } else {
      addMetadataPlan(
        plan,
        'appStoreVersion',
        `IOS/${version}`,
        {
          versionString: version,
          copyright: payload.release.copyright,
        },
        versionResource,
      );
      const reviewResponse = await client.get(queryPath(
        `/v1/appStoreVersions/${versionResource.id}/appStoreReviewDetail`,
        [['fields[appStoreReviewDetails]', 'notes']],
      ), { allowNotFound: true });
      const reviewDetail = reviewResponse?.data ?? null;
      if (!reviewDetail) {
        plan.push({
          action: 'unresolved',
          target: 'appStoreReviewDetail',
          identifier: `IOS/${version}`,
          code: 'ASC_APP_STORE_REVIEW_DETAIL_MISSING',
          reason:
            'no existing App Review Detail preserves required contact/demo settings, '
            + 'so it is not created automatically.',
          remoteMutationPlanned: false,
        });
      } else {
        addAppStoreReviewNotesPlan(
          plan,
          `IOS/${version}`,
          appStoreReviewNotes,
          reviewDetail,
          [`appStoreVersion:${version}`],
        );
      }
    }
    if (!versionSelectionBlocker) {
      versionLocalizations = await client.getAll(queryPath(
        `/v1/appStoreVersions/${versionResource.id}/appStoreVersionLocalizations`,
        [
          ['fields[appStoreVersionLocalizations]',
            'locale,description,keywords,promotionalText,supportUrl,whatsNew'],
          ['limit', '200'],
        ],
      ));
    }
  } else if (versionSelectionBlocker) {
    plan.push(versionSelectionBlocker);
  } else {
    plan.push({
      action: 'create',
      target: 'appStoreVersion',
      identifier: `IOS/${version}`,
      desired: {
        platform: 'IOS',
        versionString: version,
        copyright: payload.release.copyright,
      },
      prerequisites: [],
    });
  }

  for (const localization of payload.appLocalizations) {
    const locale = localization.locale;
    const contactPrerequisites = payload.contact.status === 'resolved'
      ? []
      : [
        'publicContactUrl:privacyPolicyUrl',
        'publicContactUrl:supportUrl',
      ];
    const remoteAppInfo = uniqueByAttribute(
      appInfoLocalizations,
      'locale',
      locale,
      'App Info localization',
    );
    const desiredAppInfo = {
      name: localization.appInfo.name,
      subtitle: localization.appInfo.subtitle,
      privacyPolicyUrl: localization.appInfo.privacyPolicyUrl,
    };
    addMetadataPlan(
      plan,
      'appInfoLocalization',
      locale,
      desiredAppInfo,
      remoteAppInfo,
      [
        ...(appInfo ? [] : [`appStoreVersion:${version}`]),
        ...contactPrerequisites,
      ],
    );
    plan.at(-1).parentId = appInfo?.id ?? null;

    const remoteVersionLocalization = uniqueByAttribute(
      versionLocalizations,
      'locale',
      locale,
      'version localization',
    );
    const desiredVersion = {
      description: localization.version.description,
      keywords: localization.version.keywords,
      promotionalText: localization.version.promotionalText,
      supportUrl: localization.version.supportUrl,
      whatsNew: localization.version.whatsNew,
    };
    addMetadataPlan(
      plan,
      'appStoreVersionLocalization',
      `${version}/${locale}`,
      desiredVersion,
      remoteVersionLocalization,
      [
        `appInfoLocalization:${locale}`,
        `appStoreVersion:${version}`,
        ...contactPrerequisites,
      ],
    );
    plan.at(-1).parentId = versionResource?.id ?? null;

    let screenshotSets = [];
    if (remoteVersionLocalization) {
      screenshotSets = await client.getAll(queryPath(
        `/v1/appStoreVersionLocalizations/`
        + `${remoteVersionLocalization.id}/appScreenshotSets`,
        [
          ['fields[appScreenshotSets]', 'screenshotDisplayType'],
          ['limit', '50'],
        ],
      ));
    }
    for (const localSet of localization.screenshots) {
      const remoteSets = screenshotSets.filter(
        (set) => attributes(set).screenshotDisplayType
          === localSet.displayType,
      );
      if (remoteSets.length > 1) {
        throw new Error(
          `remote ${locale}/${localSet.displayType} screenshot set is `
          + 'duplicated.',
        );
      }
      const remoteSet = remoteSets[0] ?? null;
      if (!remoteSet) {
        plan.push({
          action: 'create',
          target: 'appScreenshotSet',
          identifier: `${locale}/${localSet.displayType}`,
          desired: {
            displayType: localSet.displayType,
            files: localSet.files.map((file) => ({
              fileName: file.fileName,
              md5: file.md5,
              sha256: file.sha256,
              size: file.size,
            })),
          },
          prerequisites: [
            `appInfoLocalization:${locale}`,
            `appStoreVersionLocalization:${version}/${locale}`,
          ],
          parentId: remoteVersionLocalization?.id ?? null,
          assetWorkflow:
            'reservation -> uploadOperations PUT -> commit -> processing GET',
        });
        continue;
      }
      const remoteFiles = await client.getAll(queryPath(
        `/v1/appScreenshotSets/${remoteSet.id}/appScreenshots`,
        [
          ['fields[appScreenshots]',
            'fileName,fileSize,sourceFileChecksum,assetDeliveryState'],
          ['limit', '200'],
        ],
      ));
      const matches = screenshotFilesMatch(localSet.files, remoteFiles);
      plan.push({
        action: matches ? 'none' : 'replace',
        target: 'appScreenshotSet',
        identifier: `${locale}/${localSet.displayType}`,
        remoteId: remoteSet.id,
        localFiles: localSet.files.map((file) => ({
          fileName: file.fileName,
          md5: file.md5,
          sha256: file.sha256,
          size: file.size,
        })),
        remoteFiles: remoteFiles.map((file) => ({
          id: file.id,
          assetDeliveryState:
            attributes(file).assetDeliveryState?.state ?? null,
          fileName: attributes(file).fileName ?? null,
          sourceFileChecksum:
            normalizeChecksum(attributes(file).sourceFileChecksum),
          fileSize: Number(attributes(file).fileSize ?? 0),
        })),
        prerequisites: [
          `appInfoLocalization:${locale}`,
          `appStoreVersionLocalization:${version}/${locale}`,
        ],
        parentId: remoteVersionLocalization.id,
        assetWorkflow:
          'reservation -> uploadOperations PUT -> commit -> processing GET',
      });
    }
  }

  const remoteProducts = await client.getAll(queryPath(
    `/v1/apps/${appId}/inAppPurchasesV2`,
    [
      ['fields[inAppPurchases]',
        'name,productId,inAppPurchaseType,state,reviewNote'],
      ['limit', '200'],
    ],
  ));
  for (const product of payload.inAppPurchases.products) {
    const remoteProduct = uniqueByAttribute(
      remoteProducts,
      'productId',
      product.productId,
      'IAP product',
    );
    if (!remoteProduct) {
      plan.push({
        action: 'create',
        target: 'inAppPurchase',
        identifier: product.productId,
        desired: {
          name: product.referenceName,
          productId: product.productId,
          inAppPurchaseType: product.type,
          reviewNote: product.reviewNote,
        },
        prerequisites: [],
      });
      for (const localization of product.localizations) {
        plan.push({
          action: 'create',
          target: 'inAppPurchaseLocalization',
          identifier: `${product.productId}/${localization.locale}`,
          desired: {
            locale: localization.locale,
            name: localization.name,
            description: localization.description,
          },
          prerequisites: [`inAppPurchase:${product.productId}`],
        });
      }
      plan.push({
        action: 'create',
        target: 'inAppPurchaseReviewImage',
        identifier: product.productId,
        desired: product.reviewImage,
        prerequisites: [`inAppPurchase:${product.productId}`],
        assetWorkflow:
          'reservation -> uploadOperations PUT -> commit -> processing GET',
      });
      continue;
    }

    const desiredProduct = {
      name: product.referenceName,
      inAppPurchaseType: product.type,
      reviewNote: product.reviewNote,
    };
    const productChanges = changesBetween(
      desiredProduct,
      attributes(remoteProduct),
    );
    const typeMismatch = Object.hasOwn(
      productChanges,
      'inAppPurchaseType',
    );
    if (typeMismatch) {
      plan.push({
        action: 'unresolved',
        target: 'inAppPurchase',
        identifier: product.productId,
        remoteId: remoteProduct.id,
        code: 'IAP_TYPE_IMMUTABLE_NEW_PRODUCT_ID_REQUIRED',
        currentType: attributes(remoteProduct).inAppPurchaseType ?? null,
        desiredType: product.type,
        reason:
          'Apple IAP product type cannot change and the same product ID cannot be '
          + 'reused, so an owner decision is required for a new product ID.',
        remoteMutationPlanned: false,
      });
      continue;
    }
    const stateGate = iapStateReadinessPlan(
      product.productId,
      remoteProduct,
    );
    if (stateGate) plan.push(stateGate);
    plan.push({
      action: Object.keys(productChanges).length === 0 ? 'none' : 'update',
      target: 'inAppPurchase',
      identifier: product.productId,
      remoteId: remoteProduct.id,
      remoteState: attributes(remoteProduct).state ?? null,
      changes: productChanges,
      prerequisites: [],
    });

    const remoteLocalizations = await client.getAll(queryPath(
      `/v2/inAppPurchases/${remoteProduct.id}/inAppPurchaseLocalizations`,
      [
        ['fields[inAppPurchaseLocalizations]',
          'name,locale,description,state'],
        ['limit', '200'],
      ],
    ));
    for (const localization of product.localizations) {
      const remoteLocalization = uniqueByAttribute(
        remoteLocalizations,
        'locale',
        localization.locale,
        `IAP ${product.productId} localization`,
      );
      addMetadataPlan(
        plan,
        'inAppPurchaseLocalization',
        `${product.productId}/${localization.locale}`,
        {
          name: localization.name,
          description: localization.description,
        },
        remoteLocalization,
        [`inAppPurchase:${product.productId}`],
      );
      plan.at(-1).parentId = remoteProduct.id;
    }

    const remoteReviewImage = await client.get(
      queryPath(
        `/v2/inAppPurchases/${remoteProduct.id}/appStoreReviewScreenshot`,
        [
          ['fields[inAppPurchaseAppStoreReviewScreenshots]',
            'fileName,fileSize,sourceFileChecksum,assetDeliveryState'],
        ],
      ),
      { allowNotFound: true },
    );
    const remoteImageData = remoteReviewImage?.data ?? null;
    const localImage = product.reviewImage;
    const imageMatches = remoteImageData
      && iapReviewImageMatches(localImage, remoteImageData);
    plan.push({
      action: imageMatches
        ? 'none'
        : remoteImageData ? 'replace' : 'create',
      target: 'inAppPurchaseReviewImage',
      identifier: product.productId,
      remoteId: remoteImageData?.id ?? null,
      localFile: {
        fileName: localImage.fileName,
        md5: localImage.md5,
        sha256: localImage.sha256,
        size: localImage.size,
      },
      prerequisites: [`inAppPurchase:${product.productId}`],
      parentId: remoteProduct.id,
      assetWorkflow:
        'reservation -> uploadOperations PUT -> commit -> processing GET',
    });
  }

  return {
    mode: 'GET_ONLY_REMOTE_AUDIT',
    appId,
    version,
    remote: {
      appInfoId: appInfo?.id ?? null,
      versionId: versionResource?.id ?? null,
      versionState: versionResource ? appVersionState(versionResource) : null,
      versionString: attributes(versionResource).versionString ?? null,
      iapProductIds: Object.fromEntries(remoteProducts
        .filter((product) => IAP_PRODUCT_IDS.includes(attributes(product).productId))
        .map((product) => [attributes(product).productId, product.id])),
      excludedIapProducts: remoteProducts
        .filter((product) => attributes(product).productId?.endsWith('.hero_bundle'))
        .map((product) => ({
          productId: attributes(product).productId,
          remoteId: product.id,
        })),
    },
    plan,
    summary: summarizeRemotePlan(plan),
    requests: client.requests,
    remoteMutationImplemented: false,
  };
}

export async function createAuthenticatedRemoteAudit({
  repoRoot,
  payload,
  env = process.env,
  fetchImpl = globalThis.fetch,
  now = Date.now(),
} = {}) {
  const credentials = readAppStoreCredentials({
    env,
    root: resolve(repoRoot),
  });
  const privateKey = readFileSync(credentials.privateKeyPath);
  const token = createAppStoreConnectToken({
    keyId: credentials.keyId,
    issuerId: credentials.issuerId,
    privateKey,
    now,
  });
  const client = createGetOnlyAppStoreConnectClient({
    fetchImpl,
    token,
  });
  return auditAppStoreConnectRelease({ payload, client });
}

export function localReleaseSummary(manifest) {
  verifyAppStoreReleaseManifest(manifest);
  return {
    version: manifest.payload.release.version,
    appId: manifest.payload.release.appId,
    payloadSha256: manifest.payloadChecksums.sha256,
    payloadMd5: manifest.payloadChecksums.md5,
    counts: manifest.payload.counts,
    contactStatus: manifest.payload.contact.status,
    remoteRequests: 0,
    remoteMutationImplemented: false,
  };
}

export function formatAppStoreReleaseReport({
  manifestPath,
  manifest,
  check,
  remoteAudit = null,
}) {
  const summary = localReleaseSummary(manifest);
  const lines = [
    `App Store release ${check ? 'manifest verification' : 'local-only dry-run'} passed`,
    `manifest: ${manifestPath}`,
    `version: ${summary.version} / App Apple ID: ${summary.appId}`,
    `payload SHA-256: ${summary.payloadSha256}`,
    `payload MD5: ${summary.payloadMd5}`,
    `localizations: app ${summary.counts.appLocalizations}, `
      + `IAP ${summary.counts.iapLocalizations}`,
    `assets: screenshots ${summary.counts.screenshots}, `
      + `IAP review ${summary.counts.iapReviewImages}`,
    `contact URLs: ${summary.contactStatus}`,
  ];
  if (!remoteAudit) {
    lines.push('remote requests: 0 (default command is local-only)');
  } else {
    lines.push(
      `remote audit: GET ${remoteAudit.requests.length} / `
      + 'mutation 0',
    );
    lines.push(
      `plan: create ${remoteAudit.summary.create}, `
      + `update ${remoteAudit.summary.update}, `
      + `replace ${remoteAudit.summary.replace}, `
      + `none ${remoteAudit.summary.none}, `
      + `unresolved ${remoteAudit.summary.unresolved}`,
    );
    for (const entry of remoteAudit.plan) {
      if (entry.action !== 'none') {
        lines.push(
          `- ${entry.action.toUpperCase()} ${entry.target} `
          + `${entry.identifier}`,
        );
      }
    }
  }
  lines.push(
    'remote apply is a separate --apply path that requires the verified '
    + 'manifest confirmation token and GET preflight.',
  );
  return lines.join('\n');
}
