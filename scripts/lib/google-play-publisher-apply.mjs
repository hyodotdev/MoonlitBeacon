import {
  accessSync,
  constants as fsConstants,
  closeSync,
  existsSync,
  fsyncSync,
  fstatSync,
  linkSync,
  lstatSync,
  openSync,
  readFileSync,
  realpathSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import {
  createHash,
  createPrivateKey,
  randomUUID,
  sign,
} from 'node:crypto';
import {
  dirname,
  isAbsolute,
  relative,
  resolve,
  sep,
} from 'node:path';
import {
  inspectGoogleServiceAccount,
  PLAY_CONSUMABLE_PRODUCT_IDS,
  PLAY_LOCALES,
  PLAY_PACKAGE_NAME,
  PLAY_PRODUCT_IDS,
  PLAY_SCREENSHOT_NAMES,
  PLAY_SCREENSHOT_TARGETS,
  verifyPlayReleasePackage,
} from './play-release-package.mjs';

export const GOOGLE_PLAY_APPLY_CONFIG =
  'notes/release/google-play-remote-apply.json';
export const GOOGLE_PLAY_PACKAGE = 'builds/release/google-play-upload';
export const GOOGLE_PLAY_RECEIPT = 'builds/release/google-play-apply-receipt.json';
export const GOOGLE_PLAY_PROMOTION_RECEIPT =
  'builds/release/google-play-promotion-receipt.json';
export const GOOGLE_PLAY_REVIEW_RECEIPT =
  'builds/release/google-play-review-receipt.json';
export const GOOGLE_PLAY_SCOPE =
  'https://www.googleapis.com/auth/androidpublisher';
const GOOGLE_TOKEN_URI = 'https://oauth2.googleapis.com/token';
const PUBLISHER_ORIGIN = 'https://androidpublisher.googleapis.com';
const MAX_JSON_RESPONSE_BYTES = 2 * 1024 * 1024;
const PRODUCT_PURCHASE_OPTION_ID = 'buy';
const PRODUCT_AVAILABILITY = 'AVAILABLE';
const PRODUCT_NEW_REGIONS_DISABLED = 'NO_LONGER_AVAILABLE';
const LEGACY_PRODUCT_ID = `${PLAY_PACKAGE_NAME}.hero_bundle`;
// Promotion moves an already-committed versionCode from the applied track to
// public production. It never uploads an AAB, listing, image, or product, so
// the source track contract in the apply config stays exactly `internal`.
const PROMOTION_SOURCE_TRACK = 'internal';
const PROMOTION_TARGET_TRACK = 'production';
const COMMITTED_RELEASE_LIFECYCLE_STATES = Object.freeze([
  'RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW',
  'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
  'RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED',
  'RELEASE_LIFECYCLE_STATE_PUBLISHED',
]);
const NEW_REGIONS_MIGRATION_PRODUCT_IDS = new Set([
  `${PLAY_PACKAGE_NAME}.supporter`,
  `${PLAY_PACKAGE_NAME}.lantern_colors`,
]);
const committedReleaseReceipts = new WeakMap();
const preparedProductSyncs = new WeakMap();
const adoptedReleaseReceipts = new WeakMap();
const validatedResumeReceipts = new WeakMap();

function sha256(contents) {
  return createHash('sha256').update(contents).digest('hex');
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

function assertPlainObject(value, label) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} must be a JSON object.`);
  }
}

function assertExactKeys(value, keys, label) {
  assertPlainObject(value, label);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label} key contract differs.`);
  }
}

function assertRelativePath(value, label) {
  if (
    typeof value !== 'string'
    || value === ''
    || value.includes('\0')
    || isAbsolute(value)
    || value.split(/[\\/]/u).some((part) => part === '' || part === '..')
  ) {
    throw new Error(`${label} must be a safe repository-relative path.`);
  }
}

function resolveRepoPath(root, relativePath, label, { directory = false } = {}) {
  if (typeof root !== 'string' || !isAbsolute(root) || !existsSync(root)) {
    throw new Error('Repository root must be an existing absolute path.');
  }
  assertRelativePath(relativePath, label);
  const rootReal = realpathSync(root);
  const absolutePath = resolve(rootReal, relativePath);
  if (!isInside(rootReal, absolutePath) || !existsSync(absolutePath)) {
    throw new Error(`${label} is missing or points outside the repository: ${relativePath}`);
  }
  const relation = relative(rootReal, absolutePath);
  let current = rootReal;
  for (const part of relation.split(sep).filter(Boolean)) {
    current = resolve(current, part);
    if (lstatSync(current).isSymbolicLink()) {
      throw new Error(`${label} contains a symbolic link.`);
    }
  }
  const info = lstatSync(absolutePath);
  if (directory ? !info.isDirectory() : !info.isFile()) {
    throw new Error(`${label} is not a ${directory ? 'directory' : 'regular file'}.`);
  }
  return absolutePath;
}

function resolveRepoOutputPath(root, relativePath, label) {
  if (typeof root !== 'string' || !isAbsolute(root) || !existsSync(root)) {
    throw new Error('Repository root must be an existing absolute path.');
  }
  assertRelativePath(relativePath, label);
  const rootReal = realpathSync(root);
  const absolutePath = resolve(rootReal, relativePath);
  if (!isInside(rootReal, absolutePath)) {
    throw new Error(`${label} points outside the repository.`);
  }
  const parent = dirname(absolutePath);
  if (!existsSync(parent) || !lstatSync(parent).isDirectory()) {
    throw new Error(`${label} parent directory is missing.`);
  }
  const relation = relative(rootReal, parent);
  let current = rootReal;
  for (const part of relation.split(sep).filter(Boolean)) {
    current = resolve(current, part);
    if (lstatSync(current).isSymbolicLink()) {
      throw new Error(`${label} parent path contains a symbolic link.`);
    }
  }
  if (existsSync(absolutePath) && lstatSync(absolutePath).isSymbolicLink()) {
    throw new Error(`${label} is a symbolic link.`);
  }
  return absolutePath;
}

function readJsonFile(path, label) {
  const source = readFileSync(path, 'utf8');
  let parsed;
  try {
    parsed = JSON.parse(source);
  } catch {
    throw new Error(`${label} JSON is invalid.`);
  }
  return { parsed, source };
}

function readStableFile(path, label) {
  let descriptor;
  try {
    descriptor = openSync(path, fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0));
    const before = fstatSync(descriptor);
    if (!before.isFile()) throw new Error(`${label} is not a regular file.`);
    const contents = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    if (
      before.dev !== after.dev
      || before.ino !== after.ino
      || before.size !== after.size
      || before.mtimeMs !== after.mtimeMs
    ) {
      throw new Error(`${label} changed while being read.`);
    }
    return contents;
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function parseJsonBuffer(contents, label) {
  try {
    return JSON.parse(contents.toString('utf8'));
  } catch {
    throw new Error(`${label} JSON is invalid.`);
  }
}

function resolvePackagePayloadPath(outputPath, relativePath, label) {
  assertRelativePath(relativePath, label);
  const outputReal = realpathSync(outputPath);
  const absolutePath = resolve(outputReal, relativePath);
  if (!isInside(outputReal, absolutePath) || !existsSync(absolutePath)) {
    throw new Error(`${label} is not in the package.`);
  }
  let current = outputReal;
  for (const part of relativePath.split('/')) {
    current = resolve(current, part);
    if (lstatSync(current).isSymbolicLink()) {
      throw new Error(`${label} contains a symbolic link.`);
    }
  }
  return absolutePath;
}

function manifestFileRecord(manifest, relativePath, label) {
  if (!Array.isArray(manifest?.files)) {
    throw new Error('Google Play manifest file record is missing.');
  }
  const matches = manifest.files.filter((file) => file?.path === relativePath);
  if (matches.length !== 1) {
    throw new Error(`${label} manifest file record is missing or duplicated.`);
  }
  const record = matches[0];
  if (
    !Number.isSafeInteger(record.bytes)
    || record.bytes < 1
    || typeof record.sha256 !== 'string'
    || !/^[0-9a-f]{64}$/u.test(record.sha256)
  ) {
    throw new Error(`${label} manifest file record is invalid.`);
  }
  return record;
}

function readManifestBoundPayload(outputPath, manifest, relativePath, label) {
  const record = manifestFileRecord(manifest, relativePath, label);
  const path = resolvePackagePayloadPath(outputPath, relativePath, label);
  const contents = readStableFile(path, label);
  if (contents.length !== record.bytes || sha256(contents) !== record.sha256) {
    throw new Error(`${label} differs from the manifest snapshot.`);
  }
  return { contents, record };
}

function readManifestBoundJson(outputPath, manifest, relativePath, label) {
  const { contents } = readManifestBoundPayload(
    outputPath,
    manifest,
    relativePath,
    label,
  );
  return parseJsonBuffer(contents, label);
}

function deepFreeze(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) deepFreeze(child);
  }
  return value;
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => (
      `${JSON.stringify(key)}:${canonicalJson(value[key])}`
    )).join(',')}}`;
  }
  return JSON.stringify(value);
}

function money(currencyCode, units, nanos = 0) {
  return { currencyCode, nanos, units: String(units) };
}

const EXPECTED_PRODUCT_POLICY = deepFreeze({
  excludedRegions: ['CN'],
  legacyProductId: LEGACY_PRODUCT_ID,
  newRegionsAutomaticallyAvailable: false,
  products: [
    {
      basePrice: money('KRW', 3300),
      expectedAnchor: {
        price: money('KRW', 3300),
        regionCode: 'KR',
        taxAmount: money('KRW', 0),
      },
      productId: `${PLAY_PACKAGE_NAME}.supporter`,
    },
    {
      basePrice: money('USD', 4, 990_000_000),
      expectedAnchor: {
        price: money('USD', 4, 990_000_000),
        regionCode: 'US',
        taxAmount: null,
      },
      productId: `${PLAY_PACKAGE_NAME}.hero_dancer`,
    },
    {
      basePrice: money('USD', 9, 990_000_000),
      expectedAnchor: {
        price: money('USD', 9, 990_000_000),
        regionCode: 'US',
        taxAmount: null,
      },
      productId: `${PLAY_PACKAGE_NAME}.hero_keeper`,
    },
    {
      basePrice: money('USD', 14, 990_000_000),
      expectedAnchor: {
        price: money('USD', 14, 990_000_000),
        regionCode: 'US',
        taxAmount: null,
      },
      productId: `${PLAY_PACKAGE_NAME}.hero_knight`,
    },
    {
      basePrice: money('USD', 19, 990_000_000),
      expectedAnchor: {
        price: money('USD', 19, 990_000_000),
        regionCode: 'US',
        taxAmount: null,
      },
      productId: `${PLAY_PACKAGE_NAME}.hero_eclipse`,
    },
    {
      basePrice: money('USD', 24, 990_000_000),
      expectedAnchor: {
        price: money('USD', 24, 990_000_000),
        regionCode: 'US',
        taxAmount: null,
      },
      productId: `${PLAY_PACKAGE_NAME}.hero_sage`,
    },
    {
      basePrice: money('KRW', 1100),
      expectedAnchor: {
        price: money('KRW', 1100),
        regionCode: 'KR',
        taxAmount: money('KRW', 0),
      },
      productId: `${PLAY_PACKAGE_NAME}.lantern_colors`,
    },
  ],
  purchaseOptionId: PRODUCT_PURCHASE_OPTION_ID,
  regionalAvailability: PRODUCT_AVAILABILITY,
});

function assertMoney(value, label) {
  assertExactKeys(value, ['currencyCode', 'nanos', 'units'], label);
  if (
    typeof value.currencyCode !== 'string'
    || !/^[A-Z]{3}$/u.test(value.currencyCode)
    || typeof value.units !== 'string'
    || !/^(?:0|-?[1-9][0-9]*)$/u.test(value.units)
    || !Number.isSafeInteger(Number(value.units))
    || !Number.isInteger(value.nanos)
    || value.nanos < -999_999_999
    || value.nanos > 999_999_999
    || (Number(value.units) > 0 && value.nanos < 0)
    || (Number(value.units) < 0 && value.nanos > 0)
  ) {
    throw new Error(`${label} Money contract is invalid.`);
  }
  return value;
}

function assertProductPolicy(value) {
  assertExactKeys(value, [
    'excludedRegions',
    'legacyProductId',
    'newRegionsAutomaticallyAvailable',
    'products',
    'purchaseOptionId',
    'regionalAvailability',
  ], 'Google Play one-time product policy');
  if (canonicalJson(value) !== canonicalJson(EXPECTED_PRODUCT_POLICY)) {
    throw new Error(
      'Google Play one-time product policy differs from the owner-confirmed price/region contract.',
    );
  }
  for (const [index, product] of value.products.entries()) {
    assertMoney(product.basePrice, `product ${index + 1} pretax base price`);
    assertMoney(product.expectedAnchor.price, `product ${index + 1} base-region final price`);
    if (product.expectedAnchor.taxAmount !== null) {
      assertMoney(product.expectedAnchor.taxAmount, `product ${index + 1} base-region tax`);
    }
  }
  return value;
}

export function parseGooglePlayApplyArguments(args) {
  const result = {
    adoptCommittedRelease: false,
    apply: false,
    check: false,
    config: GOOGLE_PLAY_APPLY_CONFIG,
    confirmation: null,
    productsConfirmation: null,
    help: false,
    includeProducts: false,
    json: false,
    package: GOOGLE_PLAY_PACKAGE,
    promoteProduction: false,
    promotionConfirmation: null,
    receipt: GOOGLE_PLAY_RECEIPT,
    resumeProducts: false,
    reviewConfirmation: null,
    submitProductionReview: false,
  };
  const seen = new Set();
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (seen.has(argument) && argument.startsWith('--')) {
      throw new Error(`Duplicate option: ${argument}`);
    }
    seen.add(argument);
    if (argument === '--help' || argument === '-h') {
      result.help = true;
    } else if (argument === '--check') {
      result.check = true;
    } else if (argument === '--apply') {
      result.apply = true;
    } else if (argument === '--resume-products') {
      result.resumeProducts = true;
    } else if (argument === '--adopt-committed-release') {
      result.adoptCommittedRelease = true;
    } else if (argument === '--promote-production') {
      result.promoteProduction = true;
    } else if (argument === '--submit-production-review') {
      result.submitProductionReview = true;
    } else if (argument === '--json') {
      result.json = true;
    } else if (argument === '--include-products') {
      result.includeProducts = true;
    } else if (
      argument === '--package'
      || argument === '--config'
    ) {
      const value = args[index + 1];
      if (!value || value.startsWith('--')) {
        throw new Error(`${argument} requires a repository-relative path after it.`);
      }
      result[argument.slice(2)] = value;
      index += 1;
    } else if (argument === '--confirm-remote-apply') {
      const value = args[index + 1];
      if (!value || value.startsWith('--')) {
        throw new Error('--confirm-remote-apply requires the token --check printed.');
      }
      result.confirmation = value;
      index += 1;
    } else if (argument === '--confirm-products') {
      const value = args[index + 1];
      if (!value || value.startsWith('--')) {
        throw new Error('--confirm-products requires the product token --check printed.');
      }
      result.productsConfirmation = value;
      index += 1;
    } else if (argument === '--confirm-promotion') {
      const value = args[index + 1];
      if (!value || value.startsWith('--')) {
        throw new Error('--confirm-promotion requires the promotion token --check printed.');
      }
      result.promotionConfirmation = value;
      index += 1;
    } else if (argument === '--confirm-production-review') {
      const value = args[index + 1];
      if (!value || value.startsWith('--')) {
        throw new Error('--confirm-production-review requires the review token --check printed.');
      }
      result.reviewConfirmation = value;
      index += 1;
    } else {
      throw new Error(`unsupported option: ${argument}`);
    }
  }
  if (result.help) return result;
  const modeCount = [
    result.check,
    result.apply,
    result.resumeProducts,
    result.adoptCommittedRelease,
    result.promoteProduction,
    result.submitProductionReview,
  ]
    .filter(Boolean).length;
  if (modeCount !== 1) {
    throw new Error(
      '--check, --apply, --resume-products, --adopt-committed-release, '
      + 'exactly one of --promote-production, --submit-production-review is required.',
    );
  }
  if (result.submitProductionReview) {
    if (result.includeProducts) {
      throw new Error('--submit-production-review does not touch products.');
    }
    if (
      result.confirmation !== null
      || result.productsConfirmation !== null
      || result.promotionConfirmation !== null
    ) {
      throw new Error(
        '--submit-production-review uses only the --confirm-production-review token.',
      );
    }
    if (result.reviewConfirmation === null) {
      throw new Error(
        '--submit-production-review requires the --check-printed '
        + '--confirm-production-review token.',
      );
    }
  } else if (result.reviewConfirmation !== null) {
    throw new Error(
      '--confirm-production-review can only be used with --submit-production-review.',
    );
  }
  if (result.promoteProduction) {
    if (result.includeProducts) {
      throw new Error('--promote-production does not touch products.');
    }
    if (result.confirmation !== null || result.productsConfirmation !== null) {
      throw new Error(
        '--promote-production uses only the --confirm-promotion token.',
      );
    }
    if (result.promotionConfirmation === null) {
      throw new Error(
        '--promote-production requires the --check-printed --confirm-promotion token.',
      );
    }
  } else if (result.promotionConfirmation !== null) {
    throw new Error('--confirm-promotion can only be used with --promote-production.');
  }
  if (result.resumeProducts || result.adoptCommittedRelease) {
    result.includeProducts = true;
  }
  if (result.check && result.confirmation !== null) {
    throw new Error('--confirm-remote-apply can only be used in remote mode.');
  }
  if (result.check && result.productsConfirmation !== null) {
    throw new Error('--confirm-products can only be used in remote mode.');
  }
  if (
    (result.apply || result.resumeProducts || result.adoptCommittedRelease)
    && result.confirmation === null
  ) {
    throw new Error(
      'Remote mode requires the --check-printed --confirm-remote-apply token.',
    );
  }
  if (result.productsConfirmation !== null && !result.includeProducts) {
    throw new Error('--confirm-products must be used with --include-products.');
  }
  if (
    (result.apply || result.resumeProducts || result.adoptCommittedRelease)
    && result.includeProducts
    && result.productsConfirmation === null
  ) {
    throw new Error(
      '--include-products requires the --check-printed --confirm-products token.',
    );
  }
  return result;
}

export function loadGooglePlayApplyConfig(root, relativePath = GOOGLE_PLAY_APPLY_CONFIG) {
  const path = resolveRepoPath(root, relativePath, 'Google Play apply config');
  const { parsed } = readJsonFile(path, 'Google Play apply config');
  assertExactKeys(parsed, [
    'changesInReviewBehavior',
    'legalDeclarations',
    'oneTimeProducts',
    'packageName',
    'releaseStatus',
    'schemaVersion',
    'sendChangesForReview',
    'track',
  ], 'Google Play apply config');
  assertExactKeys(parsed.legalDeclarations, [
    'googlePlayDeveloperProgramPoliciesAccepted',
    'recordedFrom',
    'unitedStatesExportLawsAccepted',
  ], 'Google Play legal declarations');
  if (
    parsed.schemaVersion !== 2
    || parsed.packageName !== PLAY_PACKAGE_NAME
    || parsed.track !== 'internal'
    || parsed.releaseStatus !== 'completed'
    || parsed.changesInReviewBehavior !== 'ERROR_IF_IN_REVIEW'
    || parsed.sendChangesForReview !== true
    || parsed.legalDeclarations.googlePlayDeveloperProgramPoliciesAccepted
      !== true
    || parsed.legalDeclarations.unitedStatesExportLawsAccepted !== true
    || parsed.legalDeclarations.recordedFrom !== 'account_owner_explicit_approval'
  ) {
    throw new Error(
      'Google Play apply config must satisfy account-owner approval, internal completed, and '
      + 'the ERROR_IF_IN_REVIEW contract.',
    );
  }
  assertProductPolicy(parsed.oneTimeProducts);
  return parsed;
}

export function verifyManifestInputsAreCurrent(root, manifest) {
  if (!Array.isArray(manifest?.inputs) || manifest.inputs.length === 0) {
    throw new Error('Google Play manifest input record is missing.');
  }
  for (const input of manifest.inputs) {
    assertExactKeys(input, ['bytes', 'path', 'sha256'], 'manifest input record');
    if (
      !Number.isSafeInteger(input.bytes)
      || input.bytes < 1
      || typeof input.sha256 !== 'string'
      || !/^[0-9a-f]{64}$/u.test(input.sha256)
    ) {
      throw new Error(`manifest input record is invalid: ${input.path ?? ''}`);
    }
    const path = resolveRepoPath(root, input.path, 'manifest input');
    const contents = readFileSync(path);
    if (contents.length !== input.bytes || sha256(contents) !== input.sha256) {
      throw new Error(
        `Google Play package differs from current input: ${input.path}. `
        + 'Re-run prepare-play-release.',
      );
    }
  }
  return true;
}

function validateHistoricManifestGates(manifest) {
  assertExactKeys(manifest.gates, [
    'googlePlayLegalDeclarations',
    'googleServiceAccount',
    'oneTimeProductSetup',
    'publicContact',
    'remoteActionsReady',
  ], 'Google Play manifest gates');
  if (
    manifest.gates.publicContact?.ready !== true
    || manifest.release?.finalSubmissionAab !== true
  ) {
    throw new Error('Google Play AAB is not the final bundle with public privacy and support URLs applied.');
  }
  if (manifest.gates.googleServiceAccount?.credentialMaterialIncluded !== false) {
    throw new Error('Google Play package shows traces of credential material.');
  }
  const product = manifest.gates.oneTimeProductSetup;
  if (
    product?.localizationPayloadsReady !== true
    || product?.ready !== false
    || product?.regionsVersionConfigured !== false
    || product?.purchaseOptionsConfigured !== false
    || product?.pricingAndAvailabilityConfigured !== false
  ) {
    throw new Error('Google Play manifest product gate differs from the known fail-closed contract.');
  }
  if (
    manifest.apiApplication?.implemented !== false
    || manifest.apiApplication?.remoteApplyAllowed !== false
    || manifest.gates.remoteActionsReady !== false
  ) {
    throw new Error('Google Play manifest remote gate differs from the known local package contract.');
  }
}

export function inspectOneTimeProductApplyReadiness(productPlan) {
  assertPlainObject(productPlan, 'Google Play one-time product plan');
  const ready = (
    productPlan.remoteApplyAllowed === false
    && productPlan.creationPayloadIncluded === false
    && productPlan.pricingAndAvailabilityIncluded === false
    && productPlan.purchaseOptionsIncluded === false
    && productPlan.regionsVersionIncluded === false
    && Array.isArray(productPlan.operations)
    && productPlan.operations.length === PLAY_PRODUCT_IDS.length
    && productPlan.operations.every((operation, index) => (
      operation.allowMissing === false
      && operation.productId === PLAY_PRODUCT_IDS[index]
      && operation.regionsVersion === null
      && operation.mode === 'existing_product_localization_update_only'
      && operation.updateMask === 'listings'
    ))
  );
  return {
    blocker: ready
      ? null
      : 'Google Play product localization package differs from the known fail-closed contract.',
    ready,
  };
}

function expectedImageCounts() {
  return {
    resets: PLAY_LOCALES.length * (2 + PLAY_SCREENSHOT_TARGETS.length),
    uploads: PLAY_LOCALES.length
      * (2 + PLAY_SCREENSHOT_TARGETS.length * PLAY_SCREENSHOT_NAMES.length),
  };
}

function validateApplyOperations(outputPath, manifest) {
  const listings = PLAY_LOCALES.map((locale) => {
    const relativePath = `publisher-api/edits.listings.update/${locale}.json`;
    const operation = readManifestBoundJson(
      outputPath,
      manifest,
      relativePath,
      `${locale} listing`,
    );
    if (
      operation.apiBoundary !== 'edits.listings.update'
      || operation.method !== 'PUT'
      || operation.remoteApplyAllowed !== false
      || operation.body?.language !== locale
    ) {
      throw new Error(`${locale} listing apply contract differs.`);
    }
    return { body: operation.body, language: locale };
  });
  const images = readManifestBoundJson(
    outputPath,
    manifest,
    'publisher-api/edits.images.upload/operations.json',
    'Google Play image operation plan',
  );
  const counts = expectedImageCounts();
  if (
    images.apiBoundary !== 'edits.images.upload'
    || images.remoteApplyAllowed !== false
    || !Array.isArray(images.resetBeforeUpload)
    || images.resetBeforeUpload.length !== counts.resets
    || !Array.isArray(images.uploadOperations)
    || images.uploadOperations.length !== counts.uploads
  ) {
    throw new Error('Google Play image apply operation-count contract differs.');
  }
  for (const operation of images.resetBeforeUpload) {
    if (
      operation.method !== 'DELETE'
      || operation.remoteApplyAllowed !== false
      || !PLAY_LOCALES.includes(operation.language)
      || !['icon', 'featureGraphic', ...PLAY_SCREENSHOT_TARGETS.map(
        ({ imageType }) => imageType,
      )].includes(operation.imageType)
    ) {
      throw new Error('Google Play image reset operation contract differs.');
    }
  }
  for (const operation of images.uploadOperations) {
    if (
      operation.method !== 'POST'
      || operation.remoteApplyAllowed !== false
      || !PLAY_LOCALES.includes(operation.language)
      || typeof operation.sha256 !== 'string'
      || !/^[0-9a-f]{64}$/u.test(operation.sha256)
    ) {
      throw new Error('Google Play image upload operation contract differs.');
    }
    const mediaRecord = manifestFileRecord(
      manifest,
      operation.mediaPath,
      `Google Play ${operation.language}/${operation.imageType} image`,
    );
    if (mediaRecord.sha256 !== operation.sha256) {
      throw new Error('Google Play image operation and manifest file hash differ.');
    }
  }
  const notes = readManifestBoundJson(
    outputPath,
    manifest,
    'publisher-api/edits.tracks.update/release-notes.json',
    'Google Play track release notes',
  );
  const releaseNotes = notes.futureTrackReleaseFragment?.releaseNotes;
  if (
    notes.apiBoundary !== 'edits.tracks.update'
    || notes.remoteApplyAllowed !== false
    || !Array.isArray(releaseNotes)
    || releaseNotes.length !== PLAY_LOCALES.length
    || releaseNotes.some((note, index) => note.language !== PLAY_LOCALES[index])
  ) {
    throw new Error('Google Play track release-note contract differs.');
  }
  const products = readManifestBoundJson(
    outputPath,
    manifest,
    'publisher-api/monetization.onetimeproducts/operations.json',
    'Google Play one-time product plan',
  );
  const productReadiness = inspectOneTimeProductApplyReadiness(products);
  if (!productReadiness.ready) throw new Error(productReadiness.blocker);
  const productListings = products.operations.map((operation, index) => {
    if (
      operation.file
        !== `publisher-api/monetization.onetimeproducts/`
          + `${PLAY_PRODUCT_IDS[index].slice(`${PLAY_PACKAGE_NAME}.`.length)}.patch.json`
    ) {
      throw new Error(`${operation.productId ?? 'product'} localization file contract differs.`);
    }
    const patch = readManifestBoundJson(
      outputPath,
      manifest,
      operation.file,
      `${operation.productId} localization patch`,
    );
    const listingsForProduct = patch.body?.listings;
    if (
      patch.apiBoundary !== 'monetization.onetimeproducts.patch'
      || patch.method !== 'PATCH'
      || patch.remoteApplyAllowed !== false
      || patch.body?.packageName !== PLAY_PACKAGE_NAME
      || patch.body?.productId !== operation.productId
      || !Array.isArray(listingsForProduct)
      || listingsForProduct.length !== PLAY_LOCALES.length
      || listingsForProduct.some((listing, listingIndex) => (
        listing?.languageCode !== PLAY_LOCALES[listingIndex]
        || typeof listing.title !== 'string'
        || listing.title.trim() === ''
        || typeof listing.description !== 'string'
        || listing.description.trim() === ''
      ))
      || patch.body.purchaseOptions !== undefined
    ) {
      throw new Error(`${operation.productId} localization payload contract differs.`);
    }
    return {
      listings: listingsForProduct,
      productId: operation.productId,
    };
  });
  if (
    manifest.counts?.listingPayloads !== listings.length
    || manifest.counts?.imageDeleteAllOperations !== counts.resets
    || manifest.counts?.imageOperations !== counts.uploads
  ) {
    throw new Error('Google Play manifest and apply operation counts differ.');
  }
  return { images, listings, productListings, products, releaseNotes };
}

function confirmationToken(manifestDigest, manifest, config) {
  return [
    'google-play',
    manifest.packageName,
    manifest.release.versionCode,
    config.track,
    manifestDigest.slice(0, 16),
  ].join(':');
}

// The promotion token carries the target track so an apply token can never be
// replayed as a promotion, and vice versa.
function promotionConfirmationToken(manifestDigest, manifest, targetTrack) {
  return [
    'google-play-promotion',
    manifest.packageName,
    manifest.release.versionCode,
    targetTrack,
    manifestDigest.slice(0, 16),
  ].join(':');
}

// Review submission cancels an in-review change, so never mix tokens with promotion or apply.
function reviewSubmissionToken(manifestDigest, manifest, track) {
  return [
    'google-play-review',
    manifest.packageName,
    manifest.release.versionCode,
    track,
    manifestDigest.slice(0, 16),
  ].join(':');
}

function productsConfirmationToken(manifestDigest, productPolicy, productListings) {
  const policyDigest = sha256(canonicalJson({ productListings, productPolicy }));
  return [
    'google-play-products',
    PLAY_PACKAGE_NAME,
    manifestDigest.slice(0, 16),
    policyDigest.slice(0, 16),
  ].join(':');
}

export function createGooglePlayApplyPlan({
  configRelative = GOOGLE_PLAY_APPLY_CONFIG,
  env = process.env,
  inspectServiceAccount = inspectGoogleServiceAccount,
  outputRelative = GOOGLE_PLAY_PACKAGE,
  promotionReceiptRelative = GOOGLE_PLAY_PROMOTION_RECEIPT,
  receiptRelative = GOOGLE_PLAY_RECEIPT,
  reviewReceiptRelative = GOOGLE_PLAY_REVIEW_RECEIPT,
  root,
  verifyPackage = verifyPlayReleasePackage,
} = {}) {
  const outputPath = resolveRepoPath(root, outputRelative, 'Google Play package', {
    directory: true,
  });
  const verifiedManifest = verifyPackage(outputPath, { env, root });
  const manifestPath = resolvePackagePayloadPath(
    outputPath,
    'manifest.json',
    'Google Play manifest',
  );
  const manifestContents = readStableFile(manifestPath, 'Google Play manifest');
  const manifest = parseJsonBuffer(manifestContents, 'Google Play manifest');
  if (canonicalJson(manifest) !== canonicalJson(verifiedManifest)) {
    throw new Error('Google Play manifest changed after package verification.');
  }
  validateHistoricManifestGates(manifest);
  verifyManifestInputsAreCurrent(root, manifest);
  const config = loadGooglePlayApplyConfig(root, configRelative);
  if (manifest.packageName !== config.packageName) {
    throw new Error('Google Play package name and apply config differ.');
  }
  const operations = validateApplyOperations(outputPath, manifest);
  const credentialGate = inspectServiceAccount({ env, root });
  const blockers = [];
  if (!credentialGate.ready) {
    blockers.push(
      `Google service account blocked: ${credentialGate.reason}. `
      + 'Set GOOGLE_APPLICATION_CREDENTIALS to a mode-0600 service-account JSON outside the repository.',
    );
  }
  const manifestDigest = sha256(manifestContents);
  const bundleRecord = manifest.release?.bundle;
  if (
    typeof bundleRecord?.path !== 'string'
    || typeof bundleRecord?.sha256 !== 'string'
    || !/^[0-9a-f]{64}$/u.test(bundleRecord.sha256)
  ) {
    throw new Error('Google Play manifest AAB payload record is missing.');
  }
  const bundleFileRecord = manifestFileRecord(
    manifest,
    bundleRecord.path,
    'Google Play AAB',
  );
  if (bundleFileRecord.sha256 !== bundleRecord.sha256) {
    throw new Error('Google Play AAB release record and manifest file hash differ.');
  }
  const productBindingDigest = sha256(canonicalJson({
    productListings: operations.productListings,
    productPolicy: config.oneTimeProducts,
  }));
  const plan = {
    blockers,
    bundle: {
      path: bundleRecord.path,
      sha256: bundleRecord.sha256,
    },
    confirmationToken: confirmationToken(manifestDigest, manifest, config),
    credential: {
      configured: credentialGate.configured,
      ready: credentialGate.ready,
      reason: credentialGate.reason,
    },
    images: operations.images,
    includeProductsAllowed: true,
    listings: operations.listings,
    manifestDigest,
    outputPath,
    packageName: manifest.packageName,
    products: {
      bindingDigest: productBindingDigest,
      confirmationToken: productsConfirmationToken(
        manifestDigest,
        config.oneTimeProducts,
        operations.productListings,
      ),
      listings: operations.productListings,
      policy: config.oneTimeProducts,
    },
    promotion: {
      confirmationToken: promotionConfirmationToken(
        manifestDigest,
        manifest,
        PROMOTION_TARGET_TRACK,
      ),
      receiptPath: resolveRepoOutputPath(
        root,
        promotionReceiptRelative,
        'Google Play promotion receipt',
      ),
      sourceTrack: PROMOTION_SOURCE_TRACK,
      targetTrack: PROMOTION_TARGET_TRACK,
    },
    ready: blockers.length === 0,
    receiptPath: resolveRepoOutputPath(root, receiptRelative, 'Google Play apply receipt'),
    reviewSubmission: {
      confirmationToken: reviewSubmissionToken(
        manifestDigest,
        manifest,
        PROMOTION_TARGET_TRACK,
      ),
      receiptPath: resolveRepoOutputPath(
        root,
        reviewReceiptRelative,
        'Google Play review receipt',
      ),
      track: PROMOTION_TARGET_TRACK,
    },
    release: {
      name: `Moonlit Beacon ${manifest.release.versionName}`,
      releaseNotes: operations.releaseNotes,
      status: config.releaseStatus,
      track: config.track,
      versionCode: String(manifest.release.versionCode),
      versionName: manifest.release.versionName,
    },
    review: {
      changesInReviewBehavior: config.changesInReviewBehavior,
      changesNotSentForReview: !config.sendChangesForReview,
    },
  };
  return deepFreeze(plan);
}

function readServiceAccountFile({ env = process.env, root }) {
  const configuredPath = env.GOOGLE_APPLICATION_CREDENTIALS?.trim() ?? '';
  const gate = inspectGoogleServiceAccount({ env, root });
  if (!gate.ready) {
    throw new Error(`Google service account auth blocked: ${gate.reason}`);
  }
  let descriptor;
  try {
    descriptor = openSync(
      configuredPath,
      fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
    );
    const before = fstatSync(descriptor);
    if (!before.isFile() || (before.mode & 0o077) !== 0) {
      throw new Error('Google service account file mode or format changed.');
    }
    const contents = readFileSync(descriptor, 'utf8');
    const after = fstatSync(descriptor);
    if (
      before.dev !== after.dev
      || before.ino !== after.ino
      || before.size !== after.size
      || before.mtimeMs !== after.mtimeMs
    ) {
      throw new Error('Google service account file changed while being read.');
    }
    const parsed = JSON.parse(contents);
    const privateKey = createPrivateKey(parsed.private_key);
    if (
      parsed.type !== 'service_account'
      || parsed.token_uri !== GOOGLE_TOKEN_URI
      || typeof parsed.client_email !== 'string'
      || typeof parsed.private_key_id !== 'string'
      || privateKey.asymmetricKeyType !== 'rsa'
      || (privateKey.asymmetricKeyDetails?.modulusLength ?? 0) < 2048
    ) {
      throw new Error('Google service account JSON contract differs.');
    }
    return {
      clientEmail: parsed.client_email,
      privateKey,
      privateKeyId: parsed.private_key_id,
    };
  } catch (error) {
    throw new Error(`Failed to read the Google service account file safely: ${error.message}`);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function base64url(contents) {
  return Buffer.from(contents).toString('base64url');
}

export function createServiceAccountAssertion(credentials, {
  nowSeconds = Math.floor(Date.now() / 1000),
} = {}) {
  if (!Number.isSafeInteger(nowSeconds) || nowSeconds < 1) {
    throw new Error('JWT issued-at time is invalid.');
  }
  const header = base64url(JSON.stringify({
    alg: 'RS256',
    kid: credentials.privateKeyId,
    typ: 'JWT',
  }));
  const claims = base64url(JSON.stringify({
    aud: GOOGLE_TOKEN_URI,
    exp: nowSeconds + 3600,
    iat: nowSeconds,
    iss: credentials.clientEmail,
    scope: GOOGLE_PLAY_SCOPE,
  }));
  const signingInput = `${header}.${claims}`;
  const signature = sign('RSA-SHA256', Buffer.from(signingInput), credentials.privateKey);
  return `${signingInput}.${signature.toString('base64url')}`;
}

async function responseJson(response, label) {
  const declared = Number(response.headers?.get?.('content-length') ?? 0);
  if (Number.isFinite(declared) && declared > MAX_JSON_RESPONSE_BYTES) {
    throw new Error(`${label} response exceeds the allowed size.`);
  }
  const text = await response.text();
  if (Buffer.byteLength(text) > MAX_JSON_RESPONSE_BYTES) {
    throw new Error(`${label} response exceeds the allowed size.`);
  }
  let body = {};
  if (text !== '') {
    try {
      body = JSON.parse(text);
    } catch {
      throw new Error(`${label} response JSON is invalid.`);
    }
  }
  if (!response.ok) {
    const status = typeof body?.error?.status === 'string'
      ? body.error.status.replace(/[^A-Z0-9_]/gu, '').slice(0, 80)
      : 'HTTP_ERROR';
    const reason = body?.error?.details?.find(
      (detail) => typeof detail?.reason === 'string',
    )?.reason?.replace(/[^A-Z0-9_]/gu, '').slice(0, 80);
    throw new Error(
      `${label} failed: HTTP ${response.status} ${status}`
      + (reason ? ` (${reason})` : ''),
    );
  }
  return body;
}

async function fetchBounded(fetchImpl, url, options, label, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetchImpl(url, { ...options, signal: controller.signal });
  } catch (error) {
    throw new Error(`${label} network request failed: ${error.name ?? 'Error'}`);
  } finally {
    clearTimeout(timer);
  }
}

export async function requestGoogleAccessToken(credentials, {
  fetchImpl = globalThis.fetch,
  nowSeconds,
} = {}) {
  if (typeof fetchImpl !== 'function') throw new Error('fetch implementation is missing.');
  const assertion = createServiceAccountAssertion(credentials, { nowSeconds });
  const response = await fetchBounded(fetchImpl, GOOGLE_TOKEN_URI, {
    body: new URLSearchParams({
      assertion,
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    }),
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    method: 'POST',
  }, 'Google OAuth token', 30_000);
  const body = await responseJson(response, 'Google OAuth token');
  if (
    typeof body.access_token !== 'string'
    || body.access_token.length < 20
    || body.token_type !== 'Bearer'
    || !Number.isFinite(body.expires_in)
    || body.expires_in < 60
  ) {
    throw new Error('Google OAuth token response contract differs.');
  }
  return body.access_token;
}

function segment(value, label) {
  if (
    typeof value !== 'string'
    || value === ''
    || value.includes('\0')
    || /[\u0000-\u001f\u007f]/u.test(value)
  ) {
    throw new Error(`${label} URL segment is invalid.`);
  }
  return encodeURIComponent(value);
}

function publisherUrl(path, query = {}) {
  if (!path.startsWith('/androidpublisher/v3/')) {
    throw new Error('Google Play API path is outside the allowlist.');
  }
  const url = new URL(path, PUBLISHER_ORIGIN);
  for (const [name, value] of Object.entries(query)) {
    if (Array.isArray(value)) {
      for (const item of value) url.searchParams.append(name, String(item));
    } else if (value !== undefined && value !== null) {
      url.searchParams.set(name, String(value));
    }
  }
  return url;
}

function uploadUrl(path, query = {}) {
  if (!path.startsWith('/upload/androidpublisher/v3/')) {
    throw new Error('Google Play upload path is outside the allowlist.');
  }
  const url = new URL(path, PUBLISHER_ORIGIN);
  for (const [name, value] of Object.entries(query)) {
    if (value !== undefined && value !== null) url.searchParams.set(name, String(value));
  }
  return url;
}

function assertUploadSessionUrl(value) {
  const url = new URL(value);
  if (
    url.protocol !== 'https:'
    || url.username !== ''
    || url.password !== ''
    || !(
      url.hostname === 'androidpublisher.googleapis.com'
      || url.hostname.endsWith('.googleapis.com')
    )
  ) {
    throw new Error('Google Play resumable upload Location is outside the allowlist.');
  }
  return url;
}

export async function createGooglePlayPublisherClient({
  env = process.env,
  fetchImpl = globalThis.fetch,
  root,
} = {}) {
  const credentials = readServiceAccountFile({ env, root });
  const token = await requestGoogleAccessToken(credentials, { fetchImpl });
  const authorized = async (url, options, label, timeoutMs = 60_000) => {
    const headers = new Headers(options.headers ?? {});
    headers.set('authorization', `Bearer ${token}`);
    headers.set('accept', 'application/json');
    return fetchBounded(fetchImpl, url, { ...options, headers }, label, timeoutMs);
  };
  const jsonRequest = async (method, path, {
    body,
    label,
    query,
  } = {}) => {
    const headers = {};
    const options = { headers, method };
    if (body !== undefined) {
      headers['content-type'] = 'application/json; charset=utf-8';
      options.body = JSON.stringify(body);
    }
    const response = await authorized(
      publisherUrl(path, query),
      options,
      label ?? `Google Play ${method}`,
    );
    return responseJson(response, label ?? `Google Play ${method}`);
  };
  return {
    async batchGetOneTimeProducts(packageName, productIds) {
      return jsonRequest('GET',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + '/oneTimeProducts:batchGet', {
          label: 'Google Play one-time products batch get',
          query: { productIds },
        });
    },
    async batchUpdateOneTimeProducts(packageName, body) {
      return jsonRequest('POST',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + '/oneTimeProducts:batchUpdate', {
          body,
          label: 'Google Play one-time products batch update',
        });
    },
    async batchUpdatePurchaseOptionStates(packageName, body) {
      return jsonRequest('POST',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + '/oneTimeProducts/-/purchaseOptions:batchUpdateStates', {
          body,
          label: 'Google Play purchase-option states batch update',
        });
    },
    async commitEdit(packageName, editId, review) {
      return jsonRequest('POST',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + `/edits/${segment(editId, 'editId')}:commit`, {
          label: 'Google Play edit commit',
          query: {
            changesInReviewBehavior: review.changesInReviewBehavior,
            changesNotSentForReview: review.changesNotSentForReview,
          },
        });
    },
    async convertRegionPrices(packageName, price) {
      return jsonRequest('POST',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + '/pricing:convertRegionPrices', {
          body: { price },
          label: `Google Play ${price.currencyCode} regional price conversion`,
        });
    },
    async deleteAllImages(packageName, editId, language, imageType) {
      return jsonRequest('DELETE',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + `/edits/${segment(editId, 'editId')}/listings/`
        + `${segment(language, 'language')}/${segment(imageType, 'imageType')}`, {
          label: `Google Play ${language}/${imageType} image reset`,
        });
    },
    async discardEdit(packageName, editId) {
      return jsonRequest('DELETE',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + `/edits/${segment(editId, 'editId')}`, {
          label: 'Google Play edit discard',
        });
    },
    async insertEdit(packageName) {
      return jsonRequest('POST',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}/edits`, {
          body: {},
          label: 'Google Play edit insert',
        });
    },
    async listOneTimeProducts(packageName, pageToken) {
      return jsonRequest('GET',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + '/oneTimeProducts', {
          label: 'Google Play one-time products list',
          query: {
            pageSize: 1000,
            pageToken,
          },
        });
    },
    async listTrackReleases(packageName, track) {
      return jsonRequest('GET',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + `/tracks/${segment(track, 'track')}/releases`, {
          label: `Google Play ${track} committed releases list`,
        });
    },
    async updateListing(packageName, editId, language, body) {
      return jsonRequest('PUT',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + `/edits/${segment(editId, 'editId')}/listings/${segment(language, 'language')}`, {
          body,
          label: `Google Play ${language} listing update`,
        });
    },
    async updateTrack(packageName, editId, track, body) {
      return jsonRequest('PUT',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + `/edits/${segment(editId, 'editId')}/tracks/${segment(track, 'track')}`, {
          body,
          label: `Google Play ${track} track update`,
        });
    },
    async uploadBundle(packageName, editId, contents) {
      const initial = await authorized(uploadUrl(
        `/upload/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + `/edits/${segment(editId, 'editId')}/bundles`,
        { uploadType: 'resumable' },
      ), {
        body: '{}',
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'x-upload-content-length': String(contents.length),
          'x-upload-content-type': 'application/octet-stream',
        },
        method: 'POST',
      }, 'Google Play AAB upload session', 60_000);
      if (!initial.ok) await responseJson(initial, 'Google Play AAB upload session');
      const location = initial.headers.get('location');
      if (!location) throw new Error('Google Play AAB upload session Location is missing.');
      const response = await authorized(assertUploadSessionUrl(location), {
        body: contents,
        headers: {
          'content-length': String(contents.length),
          'content-type': 'application/octet-stream',
        },
        method: 'PUT',
      }, 'Google Play AAB upload', 5 * 60_000);
      return responseJson(response, 'Google Play AAB upload');
    },
    async uploadImage(packageName, editId, operation, contents) {
      const response = await authorized(uploadUrl(
        `/upload/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + `/edits/${segment(editId, 'editId')}/listings/`
        + `${segment(operation.language, 'language')}/`
        + `${segment(operation.imageType, 'imageType')}`,
        { uploadType: 'media' },
      ), {
        body: contents,
        headers: {
          'content-length': String(contents.length),
          'content-type': 'image/png',
        },
        method: 'POST',
      }, `Google Play ${operation.language}/${operation.imageType} image upload`);
      return responseJson(response, 'Google Play image upload');
    },
    async validateEdit(packageName, editId) {
      return jsonRequest('POST',
        `/androidpublisher/v3/applications/${segment(packageName, 'packageName')}`
        + `/edits/${segment(editId, 'editId')}:validate`, {
          label: 'Google Play edit validate',
        });
    },
  };
}

function normalizeApiMoney(value, label) {
  assertPlainObject(value, label);
  const normalized = {
    currencyCode: value.currencyCode,
    nanos: value.nanos ?? 0,
    units: value.units ?? '0',
  };
  assertMoney(normalized, label);
  return normalized;
}

function moneyMatches(actual, expected, label) {
  const normalized = normalizeApiMoney(actual, label);
  if (canonicalJson(normalized) !== canonicalJson(expected)) {
    throw new Error(
      `${label} differs from the owner-confirmed ${expected.currencyCode} `
      + `${expected.units}/${expected.nanos}.`,
    );
  }
  return normalized;
}

function validateConvertedRegionPrices(response, contract) {
  assertPlainObject(response, `${contract.productId} price conversion response`);
  const version = response.regionVersion?.version;
  if (
    typeof version !== 'string'
    || version === ''
    || version.length > 128
    || /[\u0000-\u001f\u007f]/u.test(version)
  ) {
    throw new Error(`${contract.productId} price conversion regionsVersion is missing.`);
  }
  assertPlainObject(
    response.convertedRegionPrices,
    `${contract.productId} convertedRegionPrices`,
  );
  const regionCodes = Object.keys(response.convertedRegionPrices).sort();
  if (regionCodes.length === 0) {
    throw new Error(`${contract.productId} converted regions are empty.`);
  }
  if (regionCodes.includes('CN')) {
    throw new Error(`${contract.productId} converted prices include excluded region CN.`);
  }
  assertPlainObject(
    response.convertedOtherRegionsPrice,
    `${contract.productId} convertedOtherRegionsPrice`,
  );
  const otherUsd = normalizeApiMoney(
    response.convertedOtherRegionsPrice.usdPrice,
    `${contract.productId} new-region USD reference price`,
  );
  const otherEur = normalizeApiMoney(
    response.convertedOtherRegionsPrice.eurPrice,
    `${contract.productId} new-region EUR reference price`,
  );
  if (otherUsd.currencyCode !== 'USD' || otherEur.currencyCode !== 'EUR') {
    throw new Error(`${contract.productId} new-region reference currency contract differs.`);
  }
  const regions = regionCodes.map((regionCode) => {
    if (!/^[A-Z]{2}$/u.test(regionCode)) {
      throw new Error(`${contract.productId} region code is invalid: ${regionCode}`);
    }
    const converted = response.convertedRegionPrices[regionCode];
    assertPlainObject(converted, `${contract.productId}/${regionCode} converted price`);
    if (converted.regionCode !== regionCode) {
      throw new Error(
        `${contract.productId} converted price map key and regionCode differ: ${regionCode}`,
      );
    }
    const price = normalizeApiMoney(
      converted.price,
      `${contract.productId}/${regionCode} final price`,
    );
    if (converted.taxAmount !== undefined) {
      normalizeApiMoney(converted.taxAmount, `${contract.productId}/${regionCode} tax`);
    }
    return { price, regionCode };
  });
  const anchor = response.convertedRegionPrices[contract.expectedAnchor.regionCode];
  if (!anchor) {
    throw new Error(
      `${contract.productId} price conversion is missing base region `
      + `${contract.expectedAnchor.regionCode}.`,
    );
  }
  moneyMatches(
    anchor.price,
    contract.expectedAnchor.price,
    `${contract.productId}/${contract.expectedAnchor.regionCode} base final price`,
  );
  if (contract.expectedAnchor.taxAmount !== null) {
    moneyMatches(
      anchor.taxAmount,
      contract.expectedAnchor.taxAmount,
      `${contract.productId}/${contract.expectedAnchor.regionCode} VAT`,
    );
  }
  return { regionCodes, regions, version };
}

function assertProductListings(listings, expected, productId) {
  if (!Array.isArray(listings) || listings.length !== PLAY_LOCALES.length) {
    throw new Error(`${productId} listing count differs from the 5-language contract.`);
  }
  const byLanguage = new Map();
  for (const listing of listings) {
    if (
      !PLAY_LOCALES.includes(listing?.languageCode)
      || byLanguage.has(listing.languageCode)
    ) {
      throw new Error(`${productId} listing language contract differs.`);
    }
    byLanguage.set(listing.languageCode, listing);
  }
  for (const expectedListing of expected) {
    const actual = byLanguage.get(expectedListing.languageCode);
    if (
      actual?.title !== expectedListing.title
      || actual?.description !== expectedListing.description
    ) {
      throw new Error(
        `${productId}/${expectedListing.languageCode} listing readback differs.`,
      );
    }
  }
}

function regionalConfigMap(configs, productId) {
  if (!Array.isArray(configs) || configs.length === 0) {
    throw new Error(`${productId} regional prices/availability are empty.`);
  }
  const result = new Map();
  for (const config of configs) {
    const regionCode = config?.regionCode;
    if (!/^[A-Z]{2}$/u.test(regionCode ?? '') || result.has(regionCode)) {
      throw new Error(`${productId} regional prices have duplicate or invalid regions.`);
    }
    if (regionCode === 'CN') {
      throw new Error(`${productId} regional prices include excluded region CN.`);
    }
    if (config.availability !== PRODUCT_AVAILABILITY) {
      throw new Error(`${productId}/${regionCode} availability is not AVAILABLE.`);
    }
    result.set(regionCode, normalizeApiMoney(
      config.price,
      `${productId}/${regionCode} price`,
    ));
  }
  return result;
}

function normalizeNewRegionsConfig(config, productId, {
  allowedAvailabilities,
} = {}) {
  assertPlainObject(config, `${productId} new-region config`);
  if (!allowedAvailabilities?.has(config.availability)) {
    throw new Error(`${productId} new-region availability differs from expected.`);
  }
  const usdPrice = normalizeApiMoney(
    config.usdPrice,
    `${productId} new-region USD price`,
  );
  const eurPrice = normalizeApiMoney(
    config.eurPrice,
    `${productId} new-region EUR price`,
  );
  if (usdPrice.currencyCode !== 'USD' || eurPrice.currencyCode !== 'EUR') {
    throw new Error(`${productId} new-region price currency differs from expected.`);
  }
  return {
    availability: config.availability,
    eurPrice,
    usdPrice,
  };
}

function assertBuyOptionShape(option, productId, {
  allowNewRegionsMigration = false,
} = {}) {
  let newRegionsMigration;
  if (option?.purchaseOptionId !== PRODUCT_PURCHASE_OPTION_ID) {
    throw new Error(`${productId} has an unexpected purchase option.`);
  }
  if (
    option.buyOption?.legacyCompatible !== true
    || (option.buyOption?.multiQuantityEnabled ?? false) !== false
  ) {
    throw new Error(`${productId} buy option flag contract differs.`);
  }
  if (option.newRegionsConfig !== undefined && option.newRegionsConfig !== null) {
    if (!allowNewRegionsMigration) {
      throw new Error(`${productId} includes new-region auto-activate config.`);
    }
    newRegionsMigration = normalizeNewRegionsConfig(
      option.newRegionsConfig,
      productId,
      {
        allowedAvailabilities: new Set([
          PRODUCT_AVAILABILITY,
          PRODUCT_NEW_REGIONS_DISABLED,
        ]),
      },
    );
  }
  if (option.rentOption !== undefined && option.rentOption !== null) {
    throw new Error(`${productId} buy option has unexpected rent config.`);
  }
  if (Array.isArray(option.offerTags) && option.offerTags.length > 0) {
    throw new Error(`${productId} buy option has an unexpected offer tag.`);
  }
  if (
    option.taxAndComplianceSettings !== undefined
    && option.taxAndComplianceSettings !== null
    && canonicalJson(option.taxAndComplianceSettings) !== '{}'
    && canonicalJson(option.taxAndComplianceSettings)
      !== canonicalJson({ withdrawalRightType: 'WITHDRAWAL_RIGHT_DIGITAL_CONTENT' })
  ) {
    throw new Error(`${productId} buy option has unexpected tax config.`);
  }
  return newRegionsMigration;
}

function attachNewRegionsMigrations(syncPlan, migrations) {
  if (migrations.size === 0) return syncPlan;
  for (const productId of migrations.keys()) {
    if (
      !NEW_REGIONS_MIGRATION_PRODUCT_IDS.has(productId)
      || !syncPlan.productIds.includes(productId)
    ) {
      throw new Error(`new-region migration target is invalid: ${productId}`);
    }
  }
  const products = syncPlan.products.map((product) => {
    const migration = migrations.get(product.productId);
    if (!migration) return product;
    const migrated = structuredClone(product);
    migrated.purchaseOptions[0].newRegionsConfig = {
      ...migration,
      availability: PRODUCT_NEW_REGIONS_DISABLED,
    };
    return migrated;
  });
  return deepFreeze({
    ...syncPlan,
    batchUpdateBody: {
      requests: syncPlan.batchUpdateBody.requests.map((request, index) => ({
        ...request,
        oneTimeProduct: products[index],
      })),
    },
    products,
  });
}

export function buildGooglePlayProductSyncPlan(plan, conversionResponses) {
  if (!plan?.products || !Array.isArray(conversionResponses)) {
    throw new Error('Google Play product sync input is missing.');
  }
  const { listings, policy } = plan.products;
  if (
    conversionResponses.length !== policy.products.length
    || listings.length !== policy.products.length
  ) {
    throw new Error('Google Play product price-conversion/listing count differs from the 7-product contract.');
  }
  const conversions = policy.products.map((contract, index) => (
    validateConvertedRegionPrices(conversionResponses[index], contract)
  ));
  const first = conversions[0];
  for (const conversion of conversions.slice(1)) {
    if (
      conversion.version !== first.version
      || canonicalJson(conversion.regionCodes) !== canonicalJson(first.regionCodes)
    ) {
      throw new Error('Google price conversion regionsVersion or supported-region set differs.');
    }
  }
  const products = policy.products.map((contract, index) => {
    const localization = listings[index];
    if (localization.productId !== contract.productId) {
      throw new Error('Google product price/listing order contract differs.');
    }
    return {
      listings: localization.listings,
      packageName: plan.packageName,
      productId: contract.productId,
      purchaseOptions: [{
        buyOption: {
          legacyCompatible: true,
          multiQuantityEnabled: false,
        },
        purchaseOptionId: PRODUCT_PURCHASE_OPTION_ID,
        regionalPricingAndAvailabilityConfigs: conversions[index].regions.map(
          ({ price, regionCode }) => ({
            availability: PRODUCT_AVAILABILITY,
            price,
            regionCode,
          }),
        ),
      }],
    };
  });
  return deepFreeze({
    activationBody: {
      requests: products.map(({ productId }) => ({
        activatePurchaseOptionRequest: {
          packageName: plan.packageName,
          productId,
          purchaseOptionId: PRODUCT_PURCHASE_OPTION_ID,
        },
      })),
    },
    batchUpdateBody: {
      requests: products.map((oneTimeProduct) => ({
        allowMissing: true,
        oneTimeProduct,
        regionsVersion: { version: first.version },
        updateMask: 'listings,purchaseOptions',
      })),
    },
    productIds: products.map(({ productId }) => productId),
    products,
    regionCodes: first.regionCodes,
    regionsVersion: first.version,
  });
}

async function listAllOneTimeProducts(client, packageName) {
  const products = [];
  const seenTokens = new Set();
  let pageToken;
  for (let page = 0; page < 100; page += 1) {
    const response = await client.listOneTimeProducts(packageName, pageToken);
    if (
      response.oneTimeProducts !== undefined
      && !Array.isArray(response.oneTimeProducts)
    ) {
      throw new Error('Google Play product list response contract differs.');
    }
    products.push(...(response.oneTimeProducts ?? []));
    const next = response.nextPageToken;
    if (next === undefined || next === '') return products;
    if (typeof next !== 'string' || seenTokens.has(next)) {
      throw new Error('Google Play product list pagination contract differs.');
    }
    seenTokens.add(next);
    pageToken = next;
  }
  throw new Error('Google Play product list exceeded the 100-page limit.');
}

function productMap(products, label) {
  if (!Array.isArray(products)) throw new Error(`${label} product list is not an array.`);
  const result = new Map();
  for (const product of products) {
    if (
      typeof product?.productId !== 'string'
      || product.productId === ''
      || result.has(product.productId)
    ) {
      throw new Error(`${label} product ID is missing or duplicated.`);
    }
    result.set(product.productId, product);
  }
  return result;
}

function assertLegacyProductSafe(product, label) {
  if (product === undefined) {
    throw new Error(`${label} legacy hero_bundle is missing.`);
  }
  if (
    product.packageName !== PLAY_PACKAGE_NAME
    || !Array.isArray(product.purchaseOptions)
    || product.purchaseOptions.length !== 1
    || product.purchaseOptions[0]?.purchaseOptionId !== PRODUCT_PURCHASE_OPTION_ID
    || product.purchaseOptions[0]?.buyOption === null
    || typeof product.purchaseOptions[0]?.buyOption !== 'object'
    || product.purchaseOptions[0]?.rentOption !== undefined
    || !['INACTIVE', 'INACTIVE_PUBLISHED'].includes(
      product.purchaseOptions[0]?.state,
    )
  ) {
    throw new Error(
      `${label} legacy hero_bundle is not in a safe unsold buy state.`,
    );
  }
}

function productSnapshot(product) {
  if (product === undefined) return undefined;
  const normalized = structuredClone(product);
  if (Array.isArray(normalized.listings)) {
    normalized.listings.sort((left, right) => (
      String(left?.languageCode).localeCompare(String(right?.languageCode))
    ));
  }
  if (Array.isArray(normalized.offerTags)) {
    normalized.offerTags.sort((left, right) => (
      canonicalJson(left).localeCompare(canonicalJson(right))
    ));
  }
  if (Array.isArray(normalized.purchaseOptions)) {
    normalized.purchaseOptions.sort((left, right) => (
      String(left?.purchaseOptionId).localeCompare(String(right?.purchaseOptionId))
    ));
    for (const option of normalized.purchaseOptions) {
      if (Array.isArray(option.regionalPricingAndAvailabilityConfigs)) {
        option.regionalPricingAndAvailabilityConfigs.sort((left, right) => (
          String(left?.regionCode).localeCompare(String(right?.regionCode))
        ));
      }
      if (Array.isArray(option.offerTags)) {
        option.offerTags.sort((left, right) => (
          canonicalJson(left).localeCompare(canonicalJson(right))
        ));
      }
    }
  }
  return canonicalJson(normalized);
}

function assertExistingExpectedProduct(product, desired, contract) {
  if (product === undefined) return undefined;
  if (product.packageName !== PLAY_PACKAGE_NAME) {
    throw new Error(`${desired.productId} packageName differs.`);
  }
  if (!Array.isArray(product.purchaseOptions) || product.purchaseOptions.length !== 1) {
    throw new Error(`${desired.productId} has an unexpected purchase option.`);
  }
  const option = product.purchaseOptions[0];
  const existingNewRegions = assertBuyOptionShape(option, desired.productId, {
    allowNewRegionsMigration:
      NEW_REGIONS_MIGRATION_PRODUCT_IDS.has(desired.productId),
  });
  if (!['ACTIVE', 'DRAFT', 'INACTIVE'].includes(option.state)) {
    throw new Error(`${desired.productId} buy option state is invalid.`);
  }
  const currentRegions = regionalConfigMap(
    option.regionalPricingAndAvailabilityConfigs,
    desired.productId,
  );
  const anchorPrice = currentRegions.get(contract.expectedAnchor.regionCode);
  if (!anchorPrice) {
    throw new Error(
      `${desired.productId} existing product is missing base region `
      + `${contract.expectedAnchor.regionCode}.`,
    );
  }
  moneyMatches(
    anchorPrice,
    contract.expectedAnchor.price,
    `${desired.productId} existing base-region price`,
  );
  return existingNewRegions;
}

function assertRemotePreflight(products, syncPlan, policy) {
  const current = productMap(products, 'preflight');
  const allowed = new Set([
    ...syncPlan.productIds,
    ...PLAY_CONSUMABLE_PRODUCT_IDS,
    policy.legacyProductId,
  ]);
  for (const productId of current.keys()) {
    if (!allowed.has(productId)) {
      throw new Error(`Unexpected Google Play one-time product: ${productId}`);
    }
  }
  const legacyBefore = current.get(policy.legacyProductId);
  assertLegacyProductSafe(legacyBefore, 'preflight');
  const consumablesBefore = new Map(PLAY_CONSUMABLE_PRODUCT_IDS.map(
    (productId) => [productId, productSnapshot(current.get(productId))],
  ));
  const newRegionsMigrations = new Map();
  syncPlan.products.forEach((desired, index) => {
    const migration = assertExistingExpectedProduct(
      current.get(desired.productId),
      desired,
      policy.products[index],
    );
    if (migration !== undefined) {
      newRegionsMigrations.set(desired.productId, migration);
    }
  });
  return { consumablesBefore, legacyBefore, newRegionsMigrations };
}

function assertExactNewRegionsReadback(actualOption, desiredOption, productId) {
  const actualConfig = actualOption.newRegionsConfig;
  const desiredConfig = desiredOption.newRegionsConfig;
  if (desiredConfig === undefined) {
    if (actualConfig !== undefined && actualConfig !== null) {
      throw new Error(`${productId} readback has unexpected new-region config.`);
    }
    return;
  }
  const expected = normalizeNewRegionsConfig(desiredConfig, productId, {
    allowedAvailabilities: new Set([PRODUCT_NEW_REGIONS_DISABLED]),
  });
  const actual = normalizeNewRegionsConfig(actualConfig, productId, {
    allowedAvailabilities: new Set([PRODUCT_NEW_REGIONS_DISABLED]),
  });
  if (canonicalJson(actual) !== canonicalJson(expected)) {
    throw new Error(`${productId} new-region USD/EUR price readback differs.`);
  }
}

function assertExactProductReadback(product, desired, { requireActive = true } = {}) {
  if (
    product?.packageName !== desired.packageName
    || product?.productId !== desired.productId
  ) {
    throw new Error(`${desired.productId} readback identity differs.`);
  }
  assertProductListings(product.listings, desired.listings, desired.productId);
  if (!Array.isArray(product.purchaseOptions) || product.purchaseOptions.length !== 1) {
    throw new Error(`${desired.productId} readback purchase option count differs.`);
  }
  const actualOption = product.purchaseOptions[0];
  const desiredOption = desired.purchaseOptions[0];
  assertBuyOptionShape(actualOption, desired.productId, {
    allowNewRegionsMigration:
      NEW_REGIONS_MIGRATION_PRODUCT_IDS.has(desired.productId),
  });
  assertExactNewRegionsReadback(actualOption, desiredOption, desired.productId);
  if (requireActive && actualOption.state !== 'ACTIVE') {
    throw new Error(`${desired.productId} buy option is not ACTIVE.`);
  }
  const actualRegions = regionalConfigMap(
    actualOption.regionalPricingAndAvailabilityConfigs,
    desired.productId,
  );
  const desiredRegions = regionalConfigMap(
    desiredOption.regionalPricingAndAvailabilityConfigs,
    desired.productId,
  );
  if (
    actualRegions.size !== desiredRegions.size
    || [...desiredRegions.entries()].some(([regionCode, price]) => (
      canonicalJson(actualRegions.get(regionCode)) !== canonicalJson(price)
    ))
  ) {
    throw new Error(`${desired.productId} region/price readback differs from same-day conversion.`);
  }
}

function assertProductResponseList(response, desiredProducts, {
  requireActive = false,
} = {}) {
  const products = response?.oneTimeProducts;
  if (
    !Array.isArray(products)
    || products.length !== desiredProducts.length
    || products.some((product, index) => (
      product?.productId !== desiredProducts[index].productId
    ))
  ) {
    throw new Error('Google Play product batch response order or count differs.');
  }
  products.forEach((product, index) => {
    assertExactProductReadback(product, desiredProducts[index], { requireActive });
  });
  return products;
}

function assertProductBatchResponse(response, syncPlan, options) {
  return assertProductResponseList(response, syncPlan.products, options);
}

function assertActivationResponse(response, desiredProducts) {
  assertProductResponseList(response, desiredProducts, { requireActive: true });
}

function assertFinalProductList(
  products,
  syncPlan,
  policy,
  legacyBefore,
  consumablesBefore,
) {
  const final = productMap(products, 'final readback');
  const allowed = new Set([
    ...syncPlan.productIds,
    ...PLAY_CONSUMABLE_PRODUCT_IDS,
    policy.legacyProductId,
  ]);
  for (const productId of final.keys()) {
    if (!allowed.has(productId)) {
      throw new Error(`final readback has an unexpected product: ${productId}`);
    }
  }
  for (const desired of syncPlan.products) {
    const product = final.get(desired.productId);
    if (!product) throw new Error(`${desired.productId} final readback is missing.`);
    assertExactProductReadback(product, desired);
  }
  const legacyAfter = final.get(policy.legacyProductId);
  assertLegacyProductSafe(legacyAfter, 'final readback');
  if (productSnapshot(legacyAfter) !== productSnapshot(legacyBefore)) {
    throw new Error('legacy hero_bundle changed during product sync.');
  }
  for (const productId of PLAY_CONSUMABLE_PRODUCT_IDS) {
    if (
      canonicalJson(productSnapshot(final.get(productId)))
      !== canonicalJson(consumablesBefore.get(productId))
    ) {
      throw new Error(`${productId} consumable changed during product sync.`);
    }
  }
}

function assertProductClient(client, { mutation = false, resume = false } = {}) {
  const requiredMethods = [
    'convertRegionPrices',
    'listOneTimeProducts',
    ...(mutation ? [
      'batchGetOneTimeProducts',
      'batchUpdateOneTimeProducts',
      'batchUpdatePurchaseOptionStates',
    ] : []),
    ...(resume ? ['listTrackReleases'] : []),
  ];
  if (!client || requiredMethods.some((method) => typeof client[method] !== 'function')) {
    throw new Error('Google Play product sync client contract differs.');
  }
}

export async function prepareGooglePlayProductSync(plan, {
  client,
  productsConfirmation,
} = {}) {
  if (productsConfirmation !== plan.products?.confirmationToken) {
    throw new Error('Google Play product confirmation token differs from the current manifest and price policy.');
  }
  // Also confirm every mutation method exists before creating the edit. Actual calls happen only after
  // app commit, but this avoids first failing after commit because the client is incomplete.
  assertProductClient(client, { mutation: true });
  const before = await listAllOneTimeProducts(client, plan.packageName);
  const conversions = [];
  for (const contract of plan.products.policy.products) {
    conversions.push(await client.convertRegionPrices(
      plan.packageName,
      contract.basePrice,
    ));
  }
  const baseSyncPlan = buildGooglePlayProductSyncPlan(plan, conversions);
  const { consumablesBefore, legacyBefore, newRegionsMigrations } = assertRemotePreflight(
    before,
    baseSyncPlan,
    plan.products.policy,
  );
  const syncPlan = attachNewRegionsMigrations(
    baseSyncPlan,
    newRegionsMigrations,
  );
  const preparation = deepFreeze({
    legacyProductState: legacyBefore.purchaseOptions[0].state,
    prepared: true,
    productCount: syncPlan.productIds.length,
    regionCount: syncPlan.regionCodes.length,
    regionsVersion: syncPlan.regionsVersion,
  });
  preparedProductSyncs.set(preparation, {
    client,
    consumablesBefore,
    legacyBefore,
    plan,
    syncPlan,
  });
  return preparation;
}

function receiptTimestamp(now, label) {
  const value = now();
  if (!(value instanceof Date) || Number.isNaN(value.valueOf())) {
    throw new Error(`${label} time provider is invalid.`);
  }
  return value.toISOString();
}

function assertReceiptPath(path) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new Error('Google Play apply receipt path is not absolute.');
  }
  const parent = dirname(path);
  if (!existsSync(parent) || !lstatSync(parent).isDirectory()) {
    throw new Error('Google Play apply receipt parent directory is missing.');
  }
  if (lstatSync(parent).isSymbolicLink()) {
    throw new Error('Google Play apply receipt parent directory is a symbolic link.');
  }
  if (existsSync(path)) {
    const info = lstatSync(path);
    if (
      !info.isFile()
      || info.isSymbolicLink()
      || (info.mode & 0o077) !== 0
    ) {
      throw new Error(
        'Google Play apply receipt is not an owner-only regular file.',
      );
    }
  }
  accessSync(parent, fsConstants.W_OK);
}

function atomicWriteReceipt(path, value) {
  assertReceiptPath(path);
  const temporary = `${path}.${process.pid}.${randomUUID()}.tmp`;
  let descriptor;
  let directoryDescriptor;
  try {
    descriptor = openSync(
      temporary,
      fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY,
      0o600,
    );
    writeFileSync(descriptor, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
    fsyncSync(descriptor);
    closeSync(descriptor);
    descriptor = undefined;
    renameSync(temporary, path);
    directoryDescriptor = openSync(dirname(path), fsConstants.O_RDONLY);
    fsyncSync(directoryDescriptor);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
    if (directoryDescriptor !== undefined) closeSync(directoryDescriptor);
    if (existsSync(temporary)) unlinkSync(temporary);
  }
}

/**
 * Create the first receipt without ever replacing another process' receipt.
 * A hard link publishes fully-written bytes atomically and fails with EEXIST
 * if another operator won the race between the last readback and publication.
 */
function atomicCreateReceipt(path, value) {
  assertReceiptPath(path);
  if (existsSync(path)) {
    throw new Error('Google Play apply receipt already exists. Keeping the existing receipt.');
  }
  const temporary = `${path}.${process.pid}.${randomUUID()}.tmp`;
  let descriptor;
  let directoryDescriptor;
  try {
    descriptor = openSync(
      temporary,
      fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY,
      0o600,
    );
    writeFileSync(descriptor, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
    fsyncSync(descriptor);
    closeSync(descriptor);
    descriptor = undefined;

    // link(2) has create-if-absent semantics; unlike rename it cannot clobber
    // a receipt created concurrently after the existsSync check above.
    linkSync(temporary, path);
    directoryDescriptor = openSync(dirname(path), fsConstants.O_RDONLY);
    fsyncSync(directoryDescriptor);
    unlinkSync(temporary);
    fsyncSync(directoryDescriptor);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
    if (directoryDescriptor !== undefined) closeSync(directoryDescriptor);
    if (existsSync(temporary)) unlinkSync(temporary);
  }
}

function assertIsoTimestamp(value, label, { nullable = false } = {}) {
  if (nullable && value === null) return;
  if (
    typeof value !== 'string'
    || Number.isNaN(Date.parse(value))
    || new Date(value).toISOString() !== value
  ) {
    throw new Error(`Google Play apply receipt ${label} time is invalid.`);
  }
}

function receiptCommitState(receipt) {
  return receipt.schemaVersion === 1 ? 'COMMITTED' : receipt.appCommit.state;
}

function validateReceipt(plan, receipt) {
  assertExactKeys(receipt, [
    'appCommit',
    'bundleSha256',
    'manifestDigest',
    'packageName',
    'productBindingDigest',
    'products',
    'schemaVersion',
    'track',
    'versionCode',
  ], 'Google Play apply receipt');
  if (![1, 2].includes(receipt.schemaVersion)) {
    throw new Error('Google Play apply receipt schemaVersion is not supported.');
  }
  assertExactKeys(
    receipt.appCommit,
    receipt.schemaVersion === 1
      ? ['committed', 'committedAt', 'editId']
      : [
        'committed',
        'committedAt',
        'editId',
        'intentCreatedAt',
        'proof',
        'state',
      ],
    'Google Play apply receipt appCommit',
  );
  assertExactKeys(receipt.products, [
    'appliedAt',
    'regionsVersion',
    'status',
  ], 'Google Play apply receipt products');
  if (
    receipt.packageName !== plan.packageName
    || receipt.track !== plan.release.track
    || typeof receipt.versionCode !== 'string'
    || receipt.versionCode !== plan.release.versionCode
    || receipt.manifestDigest !== plan.manifestDigest
    || receipt.bundleSha256 !== plan.bundle.sha256
    || receipt.productBindingDigest !== plan.products.bindingDigest
    || !['PENDING', 'APPLIED'].includes(receipt.products.status)
  ) {
    throw new Error('Google Play apply receipt differs from the current manifest and product policy.');
  }
  if (receipt.schemaVersion === 1) {
    if (
      receipt.appCommit.committed !== true
      || typeof receipt.appCommit.editId !== 'string'
      || receipt.appCommit.editId === ''
    ) {
      throw new Error('Google Play apply receipt v1 commit contract differs.');
    }
    assertIsoTimestamp(receipt.appCommit.committedAt, 'app commit');
  } else {
    assertIsoTimestamp(receipt.appCommit.intentCreatedAt, 'commit intent');
    if (receipt.appCommit.state === 'COMMITTING') {
      if (
        receipt.appCommit.committed !== false
        || receipt.appCommit.committedAt !== null
        || (
          receipt.appCommit.editId !== null
          && (
            typeof receipt.appCommit.editId !== 'string'
            || receipt.appCommit.editId === ''
          )
        )
        || receipt.appCommit.proof !== null
        || receipt.products.status !== 'PENDING'
      ) {
        throw new Error('Google Play apply receipt commit intent contract differs.');
      }
    } else if (receipt.appCommit.state === 'COMMITTED') {
      if (
        receipt.appCommit.committed !== true
        || !['COMMIT_RESPONSE', 'TRACK_RELEASE'].includes(receipt.appCommit.proof)
        || (
          receipt.appCommit.editId !== null
          && (
            typeof receipt.appCommit.editId !== 'string'
            || receipt.appCommit.editId === ''
          )
        )
      ) {
        throw new Error('Google Play apply receipt committed contract differs.');
      }
      assertIsoTimestamp(receipt.appCommit.committedAt, 'app commit');
    } else {
      throw new Error('Google Play apply receipt app commit state differs.');
    }
  }
  assertIsoTimestamp(receipt.products.appliedAt, 'product apply', {
    nullable: true,
  });
  if (
    (receipt.products.status === 'PENDING'
      && (receipt.products.appliedAt !== null || receipt.products.regionsVersion !== null))
    || (receipt.products.status === 'APPLIED'
      && (
        receipt.products.appliedAt === null
        || typeof receipt.products.regionsVersion !== 'string'
        || receipt.products.regionsVersion === ''
      ))
  ) {
    throw new Error('Google Play apply receipt product state contract differs.');
  }
  return receipt;
}

export function readGooglePlayApplyReceipt(plan) {
  assertReceiptPath(plan.receiptPath);
  if (!existsSync(plan.receiptPath)) {
    throw new Error('Google Play apply receipt is missing. Finish app apply first.');
  }
  const contents = readStableFile(plan.receiptPath, 'Google Play apply receipt');
  return validateReceipt(
    plan,
    parseJsonBuffer(contents, 'Google Play apply receipt'),
  );
}

function writeValidatedReceipt(plan, receipt, writeReceipt) {
  validateReceipt(plan, receipt);
  writeReceipt(plan.receiptPath, receipt);
  const persisted = readGooglePlayApplyReceipt(plan);
  if (canonicalJson(persisted) !== canonicalJson(receipt)) {
    throw new Error('Google Play apply receipt durable readback differs.');
  }
  return persisted;
}

function persistCommitIntentReceipt(plan, {
  now = () => new Date(),
  writeReceipt = atomicWriteReceipt,
} = {}) {
  const receipt = {
    appCommit: {
      committed: false,
      committedAt: null,
      editId: null,
      intentCreatedAt: receiptTimestamp(now, 'commit intent'),
      proof: null,
      state: 'COMMITTING',
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
    schemaVersion: 2,
    track: plan.release.track,
    versionCode: plan.release.versionCode,
  };
  return writeValidatedReceipt(plan, receipt, writeReceipt);
}

function persistIntentEditId(plan, receipt, editId, {
  writeReceipt = atomicWriteReceipt,
} = {}) {
  if (
    receipt.schemaVersion !== 2
    || receiptCommitState(receipt) !== 'COMMITTING'
    || typeof editId !== 'string'
    || editId === ''
  ) {
    throw new Error('Google Play commit intent edit id input is invalid.');
  }
  return writeValidatedReceipt(plan, {
    ...receipt,
    appCommit: {
      ...receipt.appCommit,
      editId,
    },
  }, writeReceipt);
}

function persistCommittedReceipt(plan, receipt, result, {
  now = () => new Date(),
  proof = 'COMMIT_RESPONSE',
  writeReceipt = atomicWriteReceipt,
} = {}) {
  if (
    receipt.schemaVersion !== 2
    || receiptCommitState(receipt) !== 'COMMITTING'
    || !['COMMIT_RESPONSE', 'TRACK_RELEASE'].includes(proof)
  ) {
    throw new Error('Google Play commit intent promotion input is invalid.');
  }
  const editId = result?.editId ?? receipt.appCommit.editId;
  const committed = {
    ...receipt,
    appCommit: {
      ...receipt.appCommit,
      committed: true,
      committedAt: receiptTimestamp(now, 'app commit'),
      editId: editId ?? null,
      proof,
      state: 'COMMITTED',
    },
  };
  return writeValidatedReceipt(plan, committed, writeReceipt);
}

function persistAdoptedCommittedReceipt(plan, {
  now = () => new Date(),
  writeReceipt = atomicCreateReceipt,
} = {}) {
  assertFreshReceiptDestination(plan);
  const verifiedAt = receiptTimestamp(now, 'committed release adoption');
  return writeValidatedReceipt(plan, {
    appCommit: {
      committed: true,
      committedAt: verifiedAt,
      editId: null,
      intentCreatedAt: verifiedAt,
      proof: 'TRACK_RELEASE',
      state: 'COMMITTED',
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
    schemaVersion: 2,
    track: plan.release.track,
    versionCode: plan.release.versionCode,
  }, writeReceipt);
}

function persistAppliedReceipt(plan, receipt, regionsVersion, {
  now = () => new Date(),
  writeReceipt = atomicWriteReceipt,
} = {}) {
  const applied = {
    ...receipt,
    products: {
      appliedAt: receiptTimestamp(now, 'product apply'),
      regionsVersion,
      status: 'APPLIED',
    },
  };
  return writeValidatedReceipt(plan, applied, writeReceipt);
}

function assertFreshReceiptDestination(plan) {
  assertReceiptPath(plan.receiptPath);
  if (existsSync(plan.receiptPath)) {
    let detail = 'Check the existing receipt state.';
    try {
      const receipt = readGooglePlayApplyReceipt(plan);
      if (receipt.products.status === 'APPLIED') {
        detail = 'Product apply for the current manifest is already complete.';
      } else if (receiptCommitState(receipt) === 'COMMITTING') {
        detail = 'Re-verify from the remote app commit with --resume-products.';
      } else {
        detail = 'Resume product apply only with --resume-products.';
      }
    } catch {
      detail = 'Existing receipt differs from the current manifest. Manual review is required.';
    }
    throw new Error(`Google Play apply receipt already exists. ${detail}`);
  }
}

/**
 * Read back exactly one committed release for `track` that carries this plan's
 * release name and versionCode as its single active artifact. Anything else —
 * zero matches, several matches, an unexpected lifecycle, a second artifact —
 * is treated as an unsafe remote state and blocks every mutation downstream.
 */
async function findExactCommittedRelease(plan, client, track, { onFailure }) {
  const response = await client.listTrackReleases(plan.packageName, track);
  if (!Array.isArray(response?.releases)) {
    throw new Error('Google Play committed release list response contract differs.');
  }
  const allowedStates = new Set(COMMITTED_RELEASE_LIFECYCLE_STATES);
  const matchingReleases = response.releases.filter((candidate) => (
    candidate?.track === track
    && candidate?.releaseName === plan.release.name
    && allowedStates.has(candidate?.releaseLifecycleState)
    && Array.isArray(candidate.activeArtifacts)
    && candidate.activeArtifacts.length === 1
    && String(candidate.activeArtifacts[0]?.versionCode ?? '')
      === plan.release.versionCode
  ));
  if (matchingReleases.length !== 1) {
    throw new Error(
      `Google Play ${track} versionCode `
      + `${plan.release.versionCode} committed release could not be re-verified. `
      + `${onFailure} exact release is not one, or lifecycle, `
      + 'release name, or single active artifact contract differs.',
    );
  }
  return matchingReleases[0];
}

async function verifyExactCommittedProductRelease(plan, client) {
  if (plan.release.track !== PROMOTION_SOURCE_TRACK) {
    throw new Error('Product release adoption is allowed only on the internal track.');
  }
  return findExactCommittedRelease(plan, client, plan.release.track, {
    onFailure: 'product mutation is forbidden.',
  });
}

const PROMOTION_STATES = Object.freeze(['COMMITTING', 'COMMITTED', 'APPLIED']);

function validatePromotionReceipt(plan, receipt) {
  assertExactKeys(receipt, [
    'manifestDigest',
    'packageName',
    'promotion',
    'schemaVersion',
    'sourceTrack',
    'targetTrack',
    'versionCode',
  ], 'Google Play promotion receipt');
  assertExactKeys(receipt.promotion, [
    'appliedAt',
    'committedAt',
    'editId',
    'intentCreatedAt',
    'proof',
    'state',
  ], 'Google Play promotion state');
  if (
    receipt.schemaVersion !== 1
    || receipt.packageName !== plan.packageName
    || receipt.manifestDigest !== plan.manifestDigest
    || receipt.versionCode !== plan.release.versionCode
    || receipt.sourceTrack !== plan.promotion.sourceTrack
    || receipt.targetTrack !== plan.promotion.targetTrack
  ) {
    throw new Error(
      'Google Play promotion receipt differs from the current manifest, version, and track.',
    );
  }
  if (!PROMOTION_STATES.includes(receipt.promotion.state)) {
    throw new Error('Google Play promotion receipt state is unknown.');
  }
  if (
    receipt.promotion.editId !== null
    && (typeof receipt.promotion.editId !== 'string' || receipt.promotion.editId === '')
  ) {
    throw new Error('Google Play promotion receipt edit id is invalid.');
  }
  if (
    receipt.promotion.proof !== null
    && receipt.promotion.proof !== 'COMMIT_RESPONSE'
    && receipt.promotion.proof !== 'TRACK_RELEASE'
  ) {
    throw new Error('Google Play promotion receipt proof kind is invalid.');
  }
  assertIsoTimestamp(receipt.promotion.intentCreatedAt, 'promotion intent');
  assertIsoTimestamp(receipt.promotion.committedAt, 'promotion commit', {
    nullable: true,
  });
  assertIsoTimestamp(receipt.promotion.appliedAt, 'promotion apply', {
    nullable: true,
  });
  return receipt;
}

export function readGooglePlayPromotionReceipt(plan) {
  const { parsed } = readJsonFile(plan.promotion.receiptPath, 'Google Play promotion receipt');
  return validatePromotionReceipt(plan, parsed);
}

function writeValidatedPromotionReceipt(plan, receipt, write) {
  const validated = validatePromotionReceipt(plan, receipt);
  write(plan.promotion.receiptPath, validated);
  const durable = readGooglePlayPromotionReceipt(plan);
  if (canonicalJson(durable) !== canonicalJson(validated)) {
    throw new Error('Google Play promotion receipt durable readback differs.');
  }
  return durable;
}

export function assertGooglePlayPromotionAuthorization(plan, { confirmation } = {}) {
  if (!plan.ready) {
    throw new Error(`Google Play production promotion is blocked: ${plan.blockers.join(' | ')}`);
  }
  if (confirmation !== plan.promotion.confirmationToken) {
    throw new Error(
      'Google Play production promotion confirmation token differs from the current manifest. '
      + 'Re-run --check.',
    );
  }
  return true;
}

/**
 * Move an already-committed versionCode from the internal track to production.
 *
 * This never uploads an AAB, listing, image, or product. It re-reads the exact
 * committed internal release, refuses to run when production already carries
 * the same versionCode, records a crash-safe intent before the first mutation,
 * and only reports success after a GET readback of the production track.
 */
export async function promoteGooglePlayReleaseToProduction(plan, {
  client,
  confirmation,
  createReceipt = atomicCreateReceipt,
  now = () => new Date(),
  writeReceipt = atomicWriteReceipt,
} = {}) {
  assertGooglePlayPromotionAuthorization(plan, { confirmation });
  if (!client || typeof client.insertEdit !== 'function') {
    throw new Error('Google Play Publisher client is missing.');
  }
  if (typeof client.listTrackReleases !== 'function') {
    throw new Error('Google Play track release lookup client is missing.');
  }
  const { sourceTrack, targetTrack } = plan.promotion;

  // A leftover receipt means an earlier promotion already reached the remote
  // API. Never start a second one from a clean slate. The receipt may belong to
  // this exact version or to an earlier one that was never archived; both block,
  // but the operator needs to be told which.
  if (existsSync(plan.promotion.receiptPath)) {
    let detail;
    try {
      const existing = readGooglePlayPromotionReceipt(plan);
      detail = `Promotion for this version is already ${existing.promotion.state}.`;
    } catch {
      detail =
        'Leftover receipt differs from the current manifest and version. If it is a previous-version receipt, '
        + 'confirm remote state and archive it separately.';
    }
    throw new Error(
      `Google Play promotion receipt already exists. ${detail} `
      + `First check ${targetTrack} versionCode ${plan.release.versionCode} status `
      + 'in Play Console.',
    );
  }

  await findExactCommittedRelease(plan, client, sourceTrack, {
    onFailure: 'production promotion is forbidden.',
  });

  const targetBefore = await client.listTrackReleases(plan.packageName, targetTrack);
  if (!Array.isArray(targetBefore?.releases)) {
    throw new Error('Google Play committed release list response contract differs.');
  }
  const alreadyPromoted = targetBefore.releases.some((candidate) => (
    Array.isArray(candidate?.activeArtifacts)
    && candidate.activeArtifacts.some((artifact) => (
      String(artifact?.versionCode ?? '') === plan.release.versionCode
    ))
  ));
  if (alreadyPromoted) {
    throw new Error(
      `Google Play ${targetTrack} already has versionCode ${plan.release.versionCode}. `
      + 'Not attempting a duplicate promotion.',
    );
  }

  let receipt = writeValidatedPromotionReceipt(plan, {
    manifestDigest: plan.manifestDigest,
    packageName: plan.packageName,
    promotion: {
      appliedAt: null,
      committedAt: null,
      editId: null,
      intentCreatedAt: receiptTimestamp(now, 'promotion intent'),
      proof: null,
      state: 'COMMITTING',
    },
    schemaVersion: 1,
    sourceTrack,
    targetTrack,
    versionCode: plan.release.versionCode,
  }, createReceipt);

  let editId = null;
  let committed = false;
  try {
    const edit = await client.insertEdit(plan.packageName);
    if (typeof edit?.id !== 'string' || edit.id === '') {
      throw new Error('Google Play edit insert response has no edit id.');
    }
    editId = edit.id;
    receipt = writeValidatedPromotionReceipt(plan, {
      ...receipt,
      promotion: { ...receipt.promotion, editId },
    }, writeReceipt);

    const track = {
      releases: [{
        name: plan.release.name,
        releaseNotes: plan.release.releaseNotes,
        status: plan.release.status,
        versionCodes: [plan.release.versionCode],
      }],
      track: targetTrack,
    };
    const updatedTrack = await client.updateTrack(
      plan.packageName,
      editId,
      targetTrack,
      track,
    );
    if (
      updatedTrack?.track !== targetTrack
      || !Array.isArray(updatedTrack.releases)
      || !updatedTrack.releases.some((release) => (
        release?.status === plan.release.status
        && Array.isArray(release.versionCodes)
        && release.versionCodes.map(String).includes(plan.release.versionCode)
      ))
    ) {
      throw new Error(`Google Play ${targetTrack} track response differs from the plan.`);
    }
    const validatedEdit = await client.validateEdit(plan.packageName, editId);
    if (validatedEdit?.id !== editId) {
      throw new Error('Google Play edit validate response id differs.');
    }
    let committedEdit;
    try {
      committedEdit = await client.commitEdit(plan.packageName, editId, plan.review);
      if (committedEdit?.id !== editId) {
        throw new Error('commit response id differs.');
      }
    } catch (error) {
      const uncertain = new Error(
        'Google Play production promotion commit result is uncertain. Do not rerun until you confirm '
        + `versionCode ${plan.release.versionCode} status in Play Console. `
        + `Cause: ${error.message}`,
      );
      uncertain.promotionCommitStatus = 'uncertain';
      throw uncertain;
    }
    committed = true;
    receipt = writeValidatedPromotionReceipt(plan, {
      ...receipt,
      promotion: {
        ...receipt.promotion,
        committedAt: receiptTimestamp(now, 'promotion commit'),
        editId: committedEdit?.id ?? editId,
        proof: 'COMMIT_RESPONSE',
        state: 'COMMITTED',
      },
    }, writeReceipt);

    const promoted = await findExactCommittedRelease(plan, client, targetTrack, {
      onFailure: 'Promotion result readback failed.',
    });
    receipt = writeValidatedPromotionReceipt(plan, {
      ...receipt,
      promotion: {
        ...receipt.promotion,
        appliedAt: receiptTimestamp(now, 'promotion apply'),
        proof: 'TRACK_RELEASE',
        state: 'APPLIED',
      },
    }, writeReceipt);
    return {
      editId: receipt.promotion.editId,
      lifecycleState: promoted.releaseLifecycleState,
      packageName: plan.packageName,
      promoted: true,
      sourceTrack,
      targetTrack,
      versionCode: plan.release.versionCode,
    };
  } catch (error) {
    if (editId !== null && !committed && typeof client.discardEdit === 'function') {
      try {
        await client.discardEdit(plan.packageName, editId);
      } catch {
        // The original failure is more actionable; an uncommitted edit expires.
      }
    }
    const status = error.promotionCommitStatus ?? (committed ? 'true' : 'false');
    throw new Error(
      `production promotion commit succeeded=${status}, versionCode=${plan.release.versionCode}. `
      + error.message,
    );
  }
}

function validateReviewReceipt(plan, receipt) {
  assertExactKeys(receipt, [
    'cancelledReleases',
    'manifestDigest',
    'packageName',
    'review',
    'schemaVersion',
    'track',
    'versionCode',
  ], 'Google Play review receipt');
  assertExactKeys(receipt.review, [
    'appliedAt',
    'committedAt',
    'editId',
    'intentCreatedAt',
    'proof',
    'state',
  ], 'Google Play review state');
  if (
    receipt.schemaVersion !== 1
    || receipt.packageName !== plan.packageName
    || receipt.manifestDigest !== plan.manifestDigest
    || receipt.versionCode !== plan.release.versionCode
    || receipt.track !== plan.reviewSubmission.track
  ) {
    throw new Error(
      'Google Play review receipt differs from the current manifest, version, and track.',
    );
  }
  if (!PROMOTION_STATES.includes(receipt.review.state)) {
    throw new Error('Google Play review receipt state is unknown.');
  }
  if (!Array.isArray(receipt.cancelledReleases)) {
    throw new Error('Google Play review receipt canceled-target list is missing.');
  }
  if (
    receipt.review.editId !== null
    && (typeof receipt.review.editId !== 'string' || receipt.review.editId === '')
  ) {
    throw new Error('Google Play review receipt edit id is invalid.');
  }
  if (
    receipt.review.proof !== null
    && receipt.review.proof !== 'COMMIT_RESPONSE'
    && receipt.review.proof !== 'TRACK_RELEASE'
  ) {
    throw new Error('Google Play review receipt proof kind is invalid.');
  }
  assertIsoTimestamp(receipt.review.intentCreatedAt, 'review intent');
  assertIsoTimestamp(receipt.review.committedAt, 'review commit', { nullable: true });
  assertIsoTimestamp(receipt.review.appliedAt, 'review apply', { nullable: true });
  return receipt;
}

export function readGooglePlayReviewReceipt(plan) {
  const { parsed } = readJsonFile(
    plan.reviewSubmission.receiptPath,
    'Google Play review receipt',
  );
  return validateReviewReceipt(plan, parsed);
}

function writeValidatedReviewReceipt(plan, receipt, write) {
  const validated = validateReviewReceipt(plan, receipt);
  write(plan.reviewSubmission.receiptPath, validated);
  const durable = readGooglePlayReviewReceipt(plan);
  if (canonicalJson(durable) !== canonicalJson(validated)) {
    throw new Error('Google Play review receipt durable readback differs.');
  }
  return durable;
}

export function assertGooglePlayReviewSubmissionAuthorization(plan, {
  confirmation,
} = {}) {
  if (!plan.ready) {
    throw new Error(`Google Play review submission is blocked: ${plan.blockers.join(' | ')}`);
  }
  if (confirmation !== plan.reviewSubmission.confirmationToken) {
    throw new Error(
      'Google Play review submission confirmation token differs from the current manifest. '
      + 'Re-run --check.',
    );
  }
  return true;
}

/**
 * Send an already-staged production release for review.
 *
 * Unlike every other path in this module this one commits with
 * `CANCEL_IN_REVIEW_AND_SUBMIT`, which tells Google Play to CANCEL whatever is
 * currently in review and replace it. That is destructive, so it is a mode of
 * its own with its own token, it refuses unless the target versionCode is
 * already staged on the track as NOT_SENT_FOR_REVIEW, and it records exactly
 * which releases it is about to cancel before the first mutation.
 */
export async function submitGooglePlayProductionReview(plan, {
  client,
  confirmation,
  createReceipt = atomicCreateReceipt,
  now = () => new Date(),
  readbackAttempts = 6,
  readbackDelayMs = 5_000,
  sleepImpl = (milliseconds) => new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  }),
  writeReceipt = atomicWriteReceipt,
} = {}) {
  assertGooglePlayReviewSubmissionAuthorization(plan, { confirmation });
  if (!client || typeof client.insertEdit !== 'function') {
    throw new Error('Google Play Publisher client is missing.');
  }
  if (typeof client.listTrackReleases !== 'function') {
    throw new Error('Google Play track release lookup client is missing.');
  }
  const { track } = plan.reviewSubmission;

  if (existsSync(plan.reviewSubmission.receiptPath)) {
    let detail;
    try {
      const existing = readGooglePlayReviewReceipt(plan);
      detail = `Review submission for this version is already ${existing.review.state}.`;
    } catch {
      detail =
        'Leftover receipt differs from the current manifest and version. If it is a previous-version receipt, '
        + 'confirm remote state and archive it separately.';
    }
    throw new Error(
      `Google Play review receipt already exists. ${detail} `
      + `First check ${track} versionCode ${plan.release.versionCode} status `
      + 'in Play Console.',
    );
  }

  const before = await client.listTrackReleases(plan.packageName, track);
  if (!Array.isArray(before?.releases)) {
    throw new Error('Google Play committed release list response contract differs.');
  }
  const staged = before.releases.filter((candidate) => (
    candidate?.releaseName === plan.release.name
    && candidate?.releaseLifecycleState === 'RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW'
    && Array.isArray(candidate.activeArtifacts)
    && candidate.activeArtifacts.length === 1
    && String(candidate.activeArtifacts[0]?.versionCode ?? '') === plan.release.versionCode
  ));
  if (staged.length > 1) {
    throw new Error(
      `Google Play ${track} has several versionCode ${plan.release.versionCode} `
      + 'NOT_SENT_FOR_REVIEW releases. Aborting review submission.',
    );
  }
  if (staged.length === 0) {
    // Normal case: it is not on the track yet. If a previous version is in review,
    // ERROR_IF_IN_REVIEW already blocks promotion, so staging is impossible.
    // Re-verify the original internal release first so unverified output cannot ship
    // to production.
    const published = before.releases.filter((candidate) => (
      (candidate.activeArtifacts ?? [])
        .some((a) => String(a?.versionCode ?? '') === plan.release.versionCode)
    ));
    if (published.length > 0) {
      throw new Error(
        `Google Play ${track} already has versionCode ${plan.release.versionCode}. `
        + 'Not attempting a duplicate review submission.',
      );
    }
    await findExactCommittedRelease(plan, client, plan.promotion.sourceTrack, {
      onFailure: 'review submission is forbidden.',
    });
  }
  // Committing with CANCEL_IN_REVIEW_AND_SUBMIT cancels review of the releases below.
  const cancelledReleases = before.releases
    .filter((candidate) => (
      candidate?.releaseLifecycleState === 'RELEASE_LIFECYCLE_STATE_IN_REVIEW'
    ))
    .map((candidate) => ({
      releaseName: String(candidate.releaseName ?? ''),
      versionCodes: (candidate.activeArtifacts ?? []).map((a) => String(a?.versionCode ?? '')),
    }));

  let receipt = writeValidatedReviewReceipt(plan, {
    cancelledReleases,
    manifestDigest: plan.manifestDigest,
    packageName: plan.packageName,
    review: {
      appliedAt: null,
      committedAt: null,
      editId: null,
      intentCreatedAt: receiptTimestamp(now, 'review intent'),
      proof: null,
      state: 'COMMITTING',
    },
    schemaVersion: 1,
    track,
    versionCode: plan.release.versionCode,
  }, createReceipt);

  let editId = null;
  let committed = false;
  try {
    const edit = await client.insertEdit(plan.packageName);
    if (typeof edit?.id !== 'string' || edit.id === '') {
      throw new Error('Google Play edit insert response has no edit id.');
    }
    editId = edit.id;
    receipt = writeValidatedReviewReceipt(plan, {
      ...receipt,
      review: { ...receipt.review, editId },
    }, writeReceipt);

    const body = {
      releases: [{
        name: plan.release.name,
        releaseNotes: plan.release.releaseNotes,
        status: plan.release.status,
        versionCodes: [plan.release.versionCode],
      }],
      track,
    };
    const updatedTrack = await client.updateTrack(plan.packageName, editId, track, body);
    if (
      updatedTrack?.track !== track
      || !Array.isArray(updatedTrack.releases)
      || !updatedTrack.releases.some((release) => (
        release?.status === plan.release.status
        && Array.isArray(release.versionCodes)
        && release.versionCodes.map(String).includes(plan.release.versionCode)
      ))
    ) {
      throw new Error(`Google Play ${track} track response differs from the plan.`);
    }
    const validatedEdit = await client.validateEdit(plan.packageName, editId);
    if (validatedEdit?.id !== editId) {
      throw new Error('Google Play edit validate response id differs.');
    }
    let committedEdit;
    try {
      committedEdit = await client.commitEdit(plan.packageName, editId, {
        // Official enum is CANCEL_IN_REVIEW_AND_SUBMIT. Cancel the in-review change
        // and submit this edit instead.
        changesInReviewBehavior: 'CANCEL_IN_REVIEW_AND_SUBMIT',
        changesNotSentForReview: false,
      });
      if (committedEdit?.id !== editId) {
        throw new Error('commit response id differs.');
      }
    } catch (error) {
      const uncertain = new Error(
        'Google Play review submission commit result is uncertain. Do not rerun until you confirm '
        + `versionCode ${plan.release.versionCode} status in Play Console. `
        + `Cause: ${error.message}`,
      );
      uncertain.reviewCommitStatus = 'uncertain';
      throw uncertain;
    }
    committed = true;
    receipt = writeValidatedReviewReceipt(plan, {
      ...receipt,
      review: {
        ...receipt.review,
        committedAt: receiptTimestamp(now, 'review commit'),
        editId: committedEdit?.id ?? editId,
        proof: 'COMMIT_RESPONSE',
        state: 'COMMITTED',
      },
    }, writeReceipt);

    // Play does not immediately reflect the new state in the track release list after commit.
    // A single failed read would leave the receipt at COMMITTED even when submission actually finished.
    // That happened in measurement, so reread with a short backoff.
    let submitted = [];
    for (let attempt = 0; attempt < readbackAttempts; attempt += 1) {
      if (attempt > 0) await sleepImpl(readbackDelayMs * attempt);
      const after = await client.listTrackReleases(plan.packageName, track);
      submitted = (after?.releases ?? []).filter((candidate) => (
        candidate?.releaseName === plan.release.name
        && candidate?.releaseLifecycleState === 'RELEASE_LIFECYCLE_STATE_IN_REVIEW'
        && (candidate.activeArtifacts ?? [])
          .some((a) => String(a?.versionCode ?? '') === plan.release.versionCode)
      ));
      if (submitted.length === 1) break;
    }
    if (submitted.length !== 1) {
      throw new Error(
        `Google Play ${track} readback did not see an IN_REVIEW release for versionCode ${plan.release.versionCode} `
        + `after ${readbackAttempts} lookups. `
        + 'commit succeeded, so check status in Play Console.',
      );
    }
    receipt = writeValidatedReviewReceipt(plan, {
      ...receipt,
      review: {
        ...receipt.review,
        appliedAt: receiptTimestamp(now, 'review apply'),
        proof: 'TRACK_RELEASE',
        state: 'APPLIED',
      },
    }, writeReceipt);
    return {
      cancelledReleases,
      editId: receipt.review.editId,
      packageName: plan.packageName,
      submitted: true,
      track,
      versionCode: plan.release.versionCode,
    };
  } catch (error) {
    if (editId !== null && !committed && typeof client.discardEdit === 'function') {
      try {
        await client.discardEdit(plan.packageName, editId);
      } catch {
        // The original failure is more actionable; an uncommitted edit expires.
      }
    }
    const status = error.reviewCommitStatus ?? (committed ? 'true' : 'false');
    throw new Error(
      `review submission commit succeeded=${status}, versionCode=${plan.release.versionCode}. `
      + error.message,
    );
  }
}

export async function authorizeGooglePlayProductAdoption(plan, {
  client,
  confirmation,
  now,
  productPreparation,
  productsConfirmation,
  writeReceipt = atomicCreateReceipt,
} = {}) {
  assertGooglePlayApplyAuthorization(plan, {
    confirmation,
    includeProducts: true,
    productsConfirmation,
  });
  const preparation = preparedProductSyncs.get(productPreparation);
  if (
    !preparation
    || preparation.plan !== plan
    || preparation.client !== client
  ) {
    throw new Error(
      'Same-client read-only preflight is required before product release adoption.',
    );
  }
  assertProductClient(client, { resume: true });
  // Avoid remote reads when another operation already owns this release. The
  // second check inside persistAdoptedCommittedReceipt closes the normal
  // readback window, and atomicCreateReceipt closes the cross-process race.
  assertFreshReceiptDestination(plan);
  const release = await verifyExactCommittedProductRelease(plan, client);
  const receipt = persistAdoptedCommittedReceipt(plan, {
    now,
    writeReceipt,
  });
  const authorization = deepFreeze({
    adopted: true,
    appCommitVerified: true,
    lifecycleState: release.releaseLifecycleState,
    resumed: false,
    versionCode: plan.release.versionCode,
  });
  adoptedReleaseReceipts.set(authorization, {
    client,
    plan,
    receipt,
  });
  return authorization;
}

export async function authorizeGooglePlayProductResume(plan, {
  client,
  now,
  productsConfirmation,
  writeReceipt = atomicWriteReceipt,
} = {}) {
  if (productsConfirmation !== plan.products?.confirmationToken) {
    throw new Error('Google Play product confirmation token differs from the current manifest and price policy.');
  }
  assertProductClient(client, { resume: true });
  const receipt = readGooglePlayApplyReceipt(plan);
  if (receipt.products.status === 'APPLIED') {
    throw new Error('Google Play product receipt is already APPLIED. Nothing to resume.');
  }
  const release = await verifyExactCommittedProductRelease(plan, client);
  const verifiedReceipt = receiptCommitState(receipt) === 'COMMITTING'
    ? persistCommittedReceipt(plan, receipt, null, {
      now,
      proof: 'TRACK_RELEASE',
      writeReceipt,
    })
    : receipt;
  const authorization = deepFreeze({
    appCommitVerified: true,
    lifecycleState: release.releaseLifecycleState,
    resumed: true,
    versionCode: plan.release.versionCode,
  });
  validatedResumeReceipts.set(authorization, {
    client,
    plan,
    receipt: verifiedReceipt,
  });
  return authorization;
}

export async function synchronizeGooglePlayOneTimeProducts(plan, {
  adoptionAuthorization,
  client,
  now,
  productPreparation,
  productsConfirmation,
  releaseResult,
  resumeAuthorization,
  writeReceipt = atomicWriteReceipt,
} = {}) {
  const preparation = preparedProductSyncs.get(productPreparation);
  if (
    !preparation
    || preparation.plan !== plan
    || preparation.client !== client
  ) {
    throw new Error('Product read-only preflight completed before the app edit is required.');
  }
  const committed = committedReleaseReceipts.get(releaseResult);
  const resumed = validatedResumeReceipts.get(resumeAuthorization);
  const adopted = adoptedReleaseReceipts.get(adoptionAuthorization);
  const proofs = [committed, resumed, adopted].filter(Boolean);
  const proof = proofs[0];
  if (
    proofs.length !== 1
    || proof.plan !== plan
    || proof.client !== client
    || (committed && committed.includeProducts !== true)
  ) {
    throw new Error(
      "Need one of this run's app commit receipt, a remotely re-verified resume receipt, or "
      + 'an adoption receipt for the exact existing release.',
    );
  }
  if (productsConfirmation !== plan.products?.confirmationToken) {
    throw new Error('Google Play product confirmation token differs from the current manifest and price policy.');
  }
  assertProductClient(client, { mutation: true });
  const { consumablesBefore, legacyBefore, syncPlan } = preparation;
  try {
    const updated = await client.batchUpdateOneTimeProducts(
      plan.packageName,
      syncPlan.batchUpdateBody,
    );
    const updatedProducts = assertProductBatchResponse(updated, syncPlan);
    const activationIndexes = updatedProducts.flatMap((product, index) => {
      const state = product.purchaseOptions[0].state;
      if (state === 'ACTIVE') return [];
      if (!['DRAFT', 'INACTIVE'].includes(state)) {
        throw new Error(
          `${product.productId} is in unexpected non-activatable state ${state ?? ''}.`,
        );
      }
      return [index];
    });
    if (activationIndexes.length > 0) {
      const activationBody = {
        requests: activationIndexes.map(
          (index) => syncPlan.activationBody.requests[index],
        ),
      };
      const activated = await client.batchUpdatePurchaseOptionStates(
        plan.packageName,
        activationBody,
      );
      assertActivationResponse(
        activated,
        activationIndexes.map((index) => syncPlan.products[index]),
      );
    }
    const batchReadback = await client.batchGetOneTimeProducts(
      plan.packageName,
      syncPlan.productIds,
    );
    assertProductBatchResponse(batchReadback, syncPlan, { requireActive: true });
    const final = await listAllOneTimeProducts(client, plan.packageName);
    assertFinalProductList(
      final,
      syncPlan,
      plan.products.policy,
      legacyBefore,
      consumablesBefore,
    );
    persistAppliedReceipt(
      plan,
      proof.receipt,
      syncPlan.regionsVersion,
      { now, writeReceipt },
    );
    return deepFreeze({
      activatedProductCount: activationIndexes.length,
      legacyProductState: `${legacyBefore.purchaseOptions[0].state}_UNCHANGED`,
      adopted: adopted !== undefined,
      productIds: syncPlan.productIds,
      productsApplied: true,
      regionCount: syncPlan.regionCodes.length,
      regionsVersion: syncPlan.regionsVersion,
      resumed: resumed !== undefined,
    });
  } catch (error) {
    throw new Error(
      `app commit succeeded=true, versionCode=${plan.release.versionCode}. `
      + 'Google Play product mutation/readback result is uncertain. Read the 7 non-consumables and legacy '
      + 'hero_bundle state, then use --resume-products only. '
      + `Cause: ${error.message}`,
    );
  }
}

function readVerifiedPackagePayload(plan, relativePath, expectedSha256) {
  assertRelativePath(relativePath, 'Google Play payload');
  const outputInfo = lstatSync(plan.outputPath);
  if (!outputInfo.isDirectory() || outputInfo.isSymbolicLink()) {
    throw new Error('Google Play package directory changed immediately before apply.');
  }
  const outputReal = realpathSync(plan.outputPath);
  const path = resolve(outputReal, relativePath);
  if (!isInside(outputReal, path)) {
    throw new Error('Google Play payload points outside the package.');
  }
  let current = outputReal;
  for (const part of relativePath.split('/')) {
    current = resolve(current, part);
    const info = lstatSync(current);
    if (info.isSymbolicLink()) {
      throw new Error(`Google Play payload gained a symbolic link: ${relativePath}`);
    }
  }
  let descriptor;
  let contents;
  try {
    descriptor = openSync(path, fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0));
    const before = fstatSync(descriptor);
    if (!before.isFile()) {
      throw new Error(`Google Play payload is not a regular file: ${relativePath}`);
    }
    contents = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    if (
      before.dev !== after.dev
      || before.ino !== after.ino
      || before.size !== after.size
      || before.mtimeMs !== after.mtimeMs
    ) {
      throw new Error(`Google Play payload changed while being read: ${relativePath}`);
    }
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
  if (sha256(contents) !== expectedSha256) {
    throw new Error(`Google Play payload hash changed immediately before apply: ${relativePath}`);
  }
  return contents;
}

export async function applyGooglePlayReleasePlan(plan, {
  client,
  confirmation,
  includeProducts = false,
  now,
  productPreparation,
  productsConfirmation,
  writeReceipt = atomicWriteReceipt,
} = {}) {
  assertGooglePlayApplyAuthorization(plan, {
    confirmation,
    includeProducts,
    productsConfirmation,
  });
  let bundle;
  let durableReceipt = null;
  try {
    if (!client || typeof client.insertEdit !== 'function') {
      throw new Error('Google Play Publisher client is missing.');
    }
    if (includeProducts) {
      const preparation = preparedProductSyncs.get(productPreparation);
      if (
        !preparation
        || preparation.plan !== plan
        || preparation.client !== client
      ) {
        throw new Error('Product read-only preflight completed before the app edit is required.');
      }
      assertFreshReceiptDestination(plan);
    }
    bundle = readVerifiedPackagePayload(
      plan,
      plan.bundle.path,
      plan.bundle.sha256,
    );
    if (includeProducts) {
      durableReceipt = persistCommitIntentReceipt(plan, {
        now,
        writeReceipt,
      });
    }
  } catch (error) {
    throw new Error(
      `app commit succeeded=false, versionCode=${plan.release.versionCode}. ${error.message}`,
    );
  }
  let editId = null;
  let committed = false;
  try {
    const edit = await client.insertEdit(plan.packageName);
    if (typeof edit?.id !== 'string' || edit.id === '') {
      throw new Error('Google Play edit insert response has no edit id.');
    }
    editId = edit.id;
    if (includeProducts) {
      durableReceipt = persistIntentEditId(plan, durableReceipt, editId, {
        writeReceipt,
      });
    }
    const uploaded = await client.uploadBundle(plan.packageName, editId, bundle);
    if (
      String(uploaded?.versionCode ?? '') !== plan.release.versionCode
      || typeof uploaded?.sha256 !== 'string'
      || !/^[0-9a-f]{64}$/u.test(uploaded.sha256)
      || uploaded.sha256 !== plan.bundle.sha256
    ) {
      throw new Error(
        'Google Play uploaded AAB versionCode or official hex sha256 differs from the plan.',
      );
    }
    for (const listing of plan.listings) {
      const updatedListing = await client.updateListing(
        plan.packageName,
        editId,
        listing.language,
        listing.body,
      );
      if (
        updatedListing?.language !== listing.language
        || updatedListing?.title !== listing.body.title
        || updatedListing?.shortDescription !== listing.body.shortDescription
        || updatedListing?.fullDescription !== listing.body.fullDescription
      ) {
        throw new Error(
          `Google Play ${listing.language} listing response differs from the plan.`,
        );
      }
    }
    for (const operation of plan.images.resetBeforeUpload) {
      await client.deleteAllImages(
        plan.packageName,
        editId,
        operation.language,
        operation.imageType,
      );
    }
    for (const operation of plan.images.uploadOperations) {
      const contents = readVerifiedPackagePayload(
        plan,
        operation.mediaPath,
        operation.sha256,
      );
      const uploadedImage = await client.uploadImage(
        plan.packageName,
        editId,
        operation,
        contents,
      );
      if (typeof uploadedImage?.image?.id !== 'string' || uploadedImage.image.id === '') {
        throw new Error(
          `Google Play ${operation.language}/${operation.imageType} `
          + 'image upload response has no image id.',
        );
      }
    }
    const track = {
      releases: [{
        name: plan.release.name,
        releaseNotes: plan.release.releaseNotes,
        status: plan.release.status,
        versionCodes: [plan.release.versionCode],
      }],
      track: plan.release.track,
    };
    const updatedTrack = await client.updateTrack(
      plan.packageName,
      editId,
      plan.release.track,
      track,
    );
    if (
      updatedTrack?.track !== plan.release.track
      || !Array.isArray(updatedTrack.releases)
      || !updatedTrack.releases.some((release) => (
        release?.status === plan.release.status
        && Array.isArray(release.versionCodes)
        && release.versionCodes.map(String).includes(plan.release.versionCode)
      ))
    ) {
      throw new Error('Google Play internal track response differs from the plan.');
    }
    const validatedEdit = await client.validateEdit(plan.packageName, editId);
    if (validatedEdit?.id !== editId) {
      throw new Error('Google Play edit validate response id differs.');
    }
    let committedEdit;
    try {
      committedEdit = await client.commitEdit(
        plan.packageName,
        editId,
        plan.review,
      );
      if (committedEdit?.id !== editId) {
        throw new Error('commit response id differs.');
      }
    } catch (error) {
      const uncertain = new Error(
        'Google Play edit commit result is uncertain. Do not rerun until you confirm '
        + `versionCode ${plan.release.versionCode} status in Play Console. `
        + `Cause: ${error.message}`,
      );
      uncertain.appCommitStatus = 'uncertain';
      throw uncertain;
    }
    committed = true;
    const result = {
      committed: true,
      editId: committedEdit?.id ?? editId,
      packageName: plan.packageName,
      productsApplied: false,
      track: plan.release.track,
      versionCode: plan.release.versionCode,
    };
    if (includeProducts) {
      try {
        durableReceipt = persistCommittedReceipt(
          plan,
          durableReceipt,
          result,
          { now, writeReceipt },
        );
      } catch (error) {
        throw new Error(
          `app commit succeeded=true, versionCode=${plan.release.versionCode}. `
          + 'Could not confirm PENDING on the durable receipt. Read the receipt and '
          + 're-verify the remote release with --resume-products. '
          + `Cause: ${error.message}`,
        );
      }
    }
    committedReleaseReceipts.set(result, {
      client,
      includeProducts,
      plan,
      receipt: durableReceipt,
    });
    return result;
  } catch (error) {
    if (editId !== null && !committed && typeof client.discardEdit === 'function') {
      try {
        await client.discardEdit(plan.packageName, editId);
      } catch {
        // The original failure is more actionable; an uncommitted edit expires.
      }
    }
    if (/^app commit succeeded=/u.test(error.message)) throw error;
    const status = error.appCommitStatus ?? (committed ? 'true' : 'false');
    throw new Error(
      `app commit succeeded=${status}, versionCode=${plan.release.versionCode}. `
      + error.message
      + (includeProducts
        ? ' If a COMMITTING receipt remains, re-verify the remote release with --resume-products.'
        : ''),
    );
  }
}

export function assertGooglePlayApplyAuthorization(plan, {
  confirmation,
  includeProducts = false,
  productsConfirmation,
} = {}) {
  if (!plan.ready) {
    throw new Error(`Google Play remote apply is blocked: ${plan.blockers.join(' | ')}`);
  }
  if (confirmation !== plan.confirmationToken) {
    throw new Error(
      'Google Play remote confirmation token differs from the current manifest. Re-run --check.',
    );
  }
  if (includeProducts) {
    if (plan.includeProductsAllowed !== true || !plan.products) {
      throw new Error('Google Play one-time product local contract is not ready.');
    }
    if (productsConfirmation !== plan.products.confirmationToken) {
      throw new Error(
        'Google Play product confirmation token differs from the current manifest and price policy. '
        + 'Re-run --check.',
      );
    }
  } else if (productsConfirmation !== undefined && productsConfirmation !== null) {
    throw new Error('Product confirmation token can only be used with --include-products.');
  }
  return true;
}

export function formatGooglePlayApplyReport(plan, { mode = 'check' } = {}) {
  const status = plan.ready ? 'ready' : 'blocked';
  return [
    `Google Play remote apply ${mode === 'check' ? 'local check' : 'result'}: ${status}`,
    `Package: ${plan.packageName}`,
    `Version/track: ${plan.release.versionName} (${plan.release.versionCode}) / ${plan.release.track}`,
    `Listings/images: ${plan.listings.length}/${plan.images.uploadOperations.length}`,
    `Products: ready (7, separate confirmation token required)`,
    `Product policy: convertRegionPrices all supported regions / CN excluded / no new-region auto-activate`,
    ...(plan.blockers.length > 0
      ? plan.blockers.map((blocker) => `Blocked: ${blocker}`)
      : [
        `App apply confirmation: --confirm-remote-apply ${plan.confirmationToken}`,
        `Product apply confirmation: --confirm-products ${plan.products.confirmationToken}`,
        `${plan.promotion.targetTrack} promotion confirmation: --confirm-promotion `
        + `${plan.promotion.confirmationToken}`,
        `${plan.reviewSubmission.track} review submission confirmation: --confirm-production-review `
        + `${plan.reviewSubmission.confirmationToken}`,
      ]),
  ].join('\n');
}
