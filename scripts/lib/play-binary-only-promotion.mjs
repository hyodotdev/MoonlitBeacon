import {
  createHash,
} from 'node:crypto';
import {
  PLAY_BINARY_ONLY_GALLERY_EVIDENCE,
  PLAY_BINARY_ONLY_MODE,
  PLAY_BINARY_ONLY_PROMOTION_RECEIPT,
  PLAY_BINARY_ONLY_REVIEW_RECEIPT,
  PLAY_BINARY_ONLY_TRACK,
  createPlayBinaryOnlyUpdatePlan,
  readPlayBinaryOnlyReceipt,
  resolveRepoOutput,
} from './play-binary-only-update.mjs';
import {
  promoteGooglePlayReleaseToProduction,
  submitGooglePlayProductionReview,
} from './google-play-publisher-apply.mjs';
import {
  PLAY_PACKAGE_NAME,
} from './play-release-package.mjs';

// Promotion and review for the exact successfully applied binary-only
// replacement. The full apply path rebuilds a fresh package and selects the
// retained versionCode from its manifest; that would promote the old build
// here, and the retained package intentionally records it. This path instead
// rebuilds the current binary-only plan, requires its mode-0600 APPLIED
// receipt, and delegates the track mutations to the existing production
// functions, which keep their crash-safe receipts, exact remote identity
// checks, ERROR_IF_IN_REVIEW promotion behavior, and review readback. It
// never uploads an AAB and never mutates listings, images, prices, or
// products. Reuse of the committed gallery stays explicit in the mode, the
// tokens, and the receipt marker below; it is not fresh capture evidence.
export {
  PLAY_BINARY_ONLY_PROMOTION_RECEIPT,
  PLAY_BINARY_ONLY_REVIEW_RECEIPT,
};
export const PLAY_BINARY_ONLY_PROMOTION_SOURCE_TRACK = PLAY_BINARY_ONLY_TRACK;
export const PLAY_BINARY_ONLY_PROMOTION_TARGET_TRACK = 'production';

function sha256(contents) {
  return createHash('sha256').update(contents).digest('hex');
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

function deepFreeze(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) deepFreeze(child);
  }
  return value;
}

function postApplyConfirmationToken(operation, prefix, {
  bundleSha256,
  galleryDigest,
  manifestDigest,
  releaseNotes,
  versionCode,
  versionName,
}) {
  const binding = sha256(canonicalJson({
    bundleSha256,
    galleryDigest,
    manifestDigest,
    mode: PLAY_BINARY_ONLY_MODE,
    operation,
    releaseNotes,
    track: PLAY_BINARY_ONLY_PROMOTION_TARGET_TRACK,
    versionCode,
    versionName,
  }));
  return [
    prefix,
    PLAY_PACKAGE_NAME,
    versionCode,
    PLAY_BINARY_ONLY_PROMOTION_TARGET_TRACK,
    binding.slice(0, 16),
  ].join(':');
}

function promotionConfirmationToken(fields) {
  return postApplyConfirmationToken(
    'PROMOTE_PRODUCTION',
    'google-play-binary-only-promotion',
    fields,
  );
}

function reviewConfirmationToken(fields) {
  return postApplyConfirmationToken(
    'SUBMIT_PRODUCTION_REVIEW',
    'google-play-binary-only-review',
    fields,
  );
}

function binaryReceiptView(plan) {
  return {
    bundle: plan.bundle,
    currencyExclusions: plan.currencyExclusions,
    galleryDigest: plan.galleryDigest,
    manifestDigest: plan.manifestDigest,
    packageName: plan.packageName,
    receiptPath: plan.binaryOnly.receiptPath,
    release: {
      versionCode: plan.release.versionCode,
      versionName: plan.release.versionName,
    },
    retained: {
      versionCode: plan.retained.versionCode,
    },
  };
}

function staleReceiptGuidance() {
  return 'If the receipt belongs to a previous binary, confirm the remote '
    + 'internal track state in Play Console and archive the receipt '
    + 'separately; never delete a receipt automatically.';
}

function readAppliedBinaryReceipt(binaryPlan) {
  let receipt;
  try {
    receipt = readPlayBinaryOnlyReceipt(binaryPlan);
  } catch (error) {
    if (/binary-only update receipt is missing\./u.test(error.message)) {
      throw new Error(
        'binary-only promotion and review need the APPLIED update receipt. '
        + 'Finish the binary-only --apply first, then re-run --check.',
      );
    }
    throw new Error(`${error.message} ${staleReceiptGuidance()}`);
  }
  if (receipt.update.state !== 'APPLIED') {
    throw new Error(
      `binary-only update receipt is ${receipt.update.state}, not APPLIED. `
      + 'Confirm the internal track state in Play Console before promoting; '
      + 'only a successfully applied binary-only replacement can move to '
      + 'production. '
      + staleReceiptGuidance(),
    );
  }
  return receipt;
}

export function createPlayBinaryOnlyPostApplyPlan({
  binaryPlan = null,
  binaryPlanOptions = {},
  promotionReceiptRelative = PLAY_BINARY_ONLY_PROMOTION_RECEIPT,
  reviewReceiptRelative = PLAY_BINARY_ONLY_REVIEW_RECEIPT,
  root = null,
} = {}) {
  const verified = binaryPlan
    ?? createPlayBinaryOnlyUpdatePlan({ root, ...binaryPlanOptions });
  if (
    verified?.mode !== PLAY_BINARY_ONLY_MODE
    || verified?.release?.track !== PLAY_BINARY_ONLY_TRACK
    || verified?.packageName !== PLAY_PACKAGE_NAME
  ) {
    throw new Error('binary-only post-apply plan needs the current binary-only update plan.');
  }
  const appliedReceipt = readAppliedBinaryReceipt(verified);
  const tokenFields = {
    bundleSha256: verified.bundle.sha256,
    galleryDigest: verified.galleryDigest,
    manifestDigest: verified.manifestDigest,
    releaseNotes: verified.release.releaseNotes,
    versionCode: verified.release.versionCode,
    versionName: verified.release.versionName,
  };
  const plan = {
    binaryOnly: {
      appliedReceipt,
      galleryEvidence: PLAY_BINARY_ONLY_GALLERY_EVIDENCE,
      mode: PLAY_BINARY_ONLY_MODE,
      receiptPath: verified.receiptPath,
    },
    blockers: [...verified.blockers],
    bundle: { ...verified.bundle },
    currencyExclusions: [...verified.currencyExclusions],
    galleryDigest: verified.galleryDigest,
    manifestDigest: verified.manifestDigest,
    packageName: verified.packageName,
    promotion: {
      confirmationToken: promotionConfirmationToken(tokenFields),
      receiptPath: resolveRepoOutput(
        verified.root,
        promotionReceiptRelative,
        'binary-only promotion receipt',
      ),
      sourceTrack: PLAY_BINARY_ONLY_PROMOTION_SOURCE_TRACK,
      targetTrack: PLAY_BINARY_ONLY_PROMOTION_TARGET_TRACK,
    },
    ready: verified.blockers.length === 0,
    release: {
      name: verified.release.name,
      releaseNotes: verified.release.releaseNotes,
      status: verified.release.status,
      track: verified.release.track,
      versionCode: verified.release.versionCode,
      versionName: verified.release.versionName,
    },
    retained: { ...verified.retained },
    reuse: { ...verified.reuse },
    review: { ...verified.review },
    reviewSubmission: {
      confirmationToken: reviewConfirmationToken(tokenFields),
      receiptPath: resolveRepoOutput(
        verified.root,
        reviewReceiptRelative,
        'binary-only review receipt',
      ),
      track: PLAY_BINARY_ONLY_PROMOTION_TARGET_TRACK,
    },
    root: verified.root,
  };
  return deepFreeze(plan);
}

function reverifyAppliedReceipt(plan) {
  let receipt;
  try {
    receipt = readPlayBinaryOnlyReceipt(binaryReceiptView(plan));
  } catch (error) {
    if (/binary-only update receipt is missing\./u.test(error.message)) {
      throw new Error(
        'binary-only APPLIED receipt is missing. Finish the binary-only '
        + '--apply first, then re-run --check.',
      );
    }
    throw new Error(`${error.message} ${staleReceiptGuidance()}`);
  }
  if (receipt.update.state !== 'APPLIED') {
    throw new Error(
      `binary-only update receipt is ${receipt.update.state}, not APPLIED. `
      + 'Only a successfully applied binary-only replacement can move to '
      + `production. ${staleReceiptGuidance()}`,
    );
  }
  if (canonicalJson(receipt) !== canonicalJson(plan.binaryOnly.appliedReceipt)) {
    throw new Error(
      'binary-only APPLIED receipt changed since the local check. Re-run '
      + `--check. ${staleReceiptGuidance()}`,
    );
  }
  return receipt;
}

function assertPostApplyPlanShape(plan, operation) {
  if (
    plan?.packageName !== PLAY_PACKAGE_NAME
    || plan?.binaryOnly?.mode !== PLAY_BINARY_ONLY_MODE
    || plan?.binaryOnly?.galleryEvidence !== PLAY_BINARY_ONLY_GALLERY_EVIDENCE
    || plan?.reuse?.galleryEvidence !== PLAY_BINARY_ONLY_GALLERY_EVIDENCE
    || plan?.promotion?.sourceTrack !== PLAY_BINARY_ONLY_PROMOTION_SOURCE_TRACK
    || plan?.promotion?.targetTrack !== PLAY_BINARY_ONLY_PROMOTION_TARGET_TRACK
    || plan?.reviewSubmission?.track !== PLAY_BINARY_ONLY_PROMOTION_TARGET_TRACK
    || plan?.review?.changesInReviewBehavior !== 'ERROR_IF_IN_REVIEW'
  ) {
    throw new Error(`binary-only ${operation} plan contract differs.`);
  }
}

export function assertPlayBinaryOnlyPromotionAuthorization(plan, { confirmation } = {}) {
  assertPostApplyPlanShape(plan, 'promotion');
  if (!plan.ready) {
    const detail = plan.blockers.length > 0
      ? plan.blockers.join(' | ')
      : 'local check did not pass.';
    throw new Error(`binary-only production promotion is blocked: ${detail}`);
  }
  if (confirmation !== plan.promotion.confirmationToken) {
    throw new Error(
      'binary-only production promotion confirmation token differs from the '
      + 'current binary and retained gallery. Re-run --check.',
    );
  }
  return true;
}

export function assertPlayBinaryOnlyReviewSubmissionAuthorization(plan, { confirmation } = {}) {
  assertPostApplyPlanShape(plan, 'review submission');
  if (!plan.ready) {
    const detail = plan.blockers.length > 0
      ? plan.blockers.join(' | ')
      : 'local check did not pass.';
    throw new Error(`binary-only review submission is blocked: ${detail}`);
  }
  if (confirmation !== plan.reviewSubmission.confirmationToken) {
    throw new Error(
      'binary-only review submission confirmation token differs from the '
      + 'current binary and retained gallery. Re-run --check.',
    );
  }
  return true;
}

export async function promotePlayBinaryOnlyReleaseToProduction(plan, {
  client,
  confirmation,
} = {}) {
  // Local gates first: the APPLIED receipt, the plan contract, and the
  // promotion token are all re-verified before the delegated function may
  // touch the network. An existing promotion receipt stays the delegated
  // function's own refusal: it tells a same-version receipt apart from an
  // unarchived earlier one and never deletes either.
  reverifyAppliedReceipt(plan);
  assertPlayBinaryOnlyPromotionAuthorization(plan, { confirmation });
  return promoteGooglePlayReleaseToProduction(plan, {
    client,
    confirmation,
  });
}

export async function submitPlayBinaryOnlyProductionReview(plan, {
  client,
  confirmation,
  readbackAttempts,
  readbackDelayMs,
  sleepImpl,
} = {}) {
  // Local gates first, same as promotion: no network until the APPLIED
  // receipt, the plan contract, and the review token all verify. An
  // existing review receipt stays the delegated function's own refusal.
  reverifyAppliedReceipt(plan);
  assertPlayBinaryOnlyReviewSubmissionAuthorization(plan, { confirmation });
  const options = { client, confirmation };
  if (readbackAttempts !== undefined) options.readbackAttempts = readbackAttempts;
  if (readbackDelayMs !== undefined) options.readbackDelayMs = readbackDelayMs;
  if (sleepImpl !== undefined) options.sleepImpl = sleepImpl;
  return submitGooglePlayProductionReview(plan, options);
}
