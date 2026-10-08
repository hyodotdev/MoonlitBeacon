#!/usr/bin/env node

import './lib/load-env.mjs';

import { fileURLToPath } from 'node:url';
import {
  applyPlayBinaryOnlyUpdatePlan,
  assertPlayBinaryOnlyAuthorization,
  createPlayBinaryOnlyUpdatePlan,
  formatPlayBinaryOnlyReport,
  parsePlayBinaryOnlyArguments,
} from './lib/play-binary-only-update.mjs';
import {
  assertPlayBinaryOnlyPromotionAuthorization,
  assertPlayBinaryOnlyReviewSubmissionAuthorization,
  createPlayBinaryOnlyPostApplyPlan,
  promotePlayBinaryOnlyReleaseToProduction,
  submitPlayBinaryOnlyProductionReview,
} from './lib/play-binary-only-promotion.mjs';
import {
  createGooglePlayPublisherClient,
} from './lib/google-play-publisher-apply.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));

function usage() {
  return [
    'Usage:',
    '  node scripts/apply-play-binary-only-update.mjs [--check] [--json]',
    '  node scripts/apply-play-binary-only-update.mjs --apply \\',
    '    --confirm-binary-only <binary token> [--json]',
    '  node scripts/apply-play-binary-only-update.mjs --promote-production \\',
    '    --confirm-binary-only-promotion <promotion token> [--json]',
    '  node scripts/apply-play-binary-only-update.mjs --submit-production-review \\',
    '    --confirm-binary-only-review <review token> [--json]',
    '',
    'Options:',
    '  --package PATH       retained google-play-upload package to reuse',
    '  --bundle PATH        new AAB that replaces only the binary',
    '  --config PATH        account-owner approval and internal track config',
    '  --receipt PATH       binary-only update receipt to write and re-verify',
    '  --promotion-receipt PATH  binary-only promotion receipt to write',
    '  --review-receipt PATH     binary-only review receipt to write',
    '',
    'Default with no options is a local check only and uses no network at all.',
    '--apply authenticates with GOOGLE_APPLICATION_CREDENTIALS.',
    'It re-verifies the committed internal release and every retained listing and',
    'ordered image hash immediately before mutation, then uploads only the AAB,',
    'updates only the internal track, validates, and commits with ERROR_IF_IN_REVIEW.',
    'A strictly newer display version carries the current five-language release',
    'notes; a same-version replacement keeps the retained notes. It never touches',
    'listings, images, prices, products, production, or reviews.',
    'Reuse of the committed gallery is explicit in the mode and token; it is not',
    'fresh capture evidence and not native purchase evidence.',
    '--promote-production moves only the successfully applied binary-only',
    'versionCode from internal to production. Both rebuild the binary-only',
    'plan, require its APPLIED receipt, take only their own confirmation',
    'token, and never upload an AAB or mutate listings, images, prices, or',
    'products. Re-run --check after --apply to print their tokens.',
    '--submit-production-review is conditional: use it only when the new',
    'version still needs review (NOT_SENT_FOR_REVIEW readback, or the',
    'supported not-on-production fallback). A promotion readback already',
    'IN_REVIEW or PUBLISHED is success: record it and do not submit again.',
  ].join('\n');
}

async function main() {
  const options = parsePlayBinaryOnlyArguments(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }
  const plan = createPlayBinaryOnlyUpdatePlan({
    bundleRelative: options.bundle,
    configRelative: options.config,
    env: process.env,
    outputRelative: options.package,
    receiptRelative: options.receipt,
    root,
  });
  if (options.check) {
    let postApply = null;
    let postApplyBlocked = null;
    try {
      postApply = createPlayBinaryOnlyPostApplyPlan({
        binaryPlan: plan,
        promotionReceiptRelative: options.promotionReceipt,
        reviewReceiptRelative: options.reviewReceipt,
      });
    } catch (error) {
      postApplyBlocked = error.message;
    }
    if (options.json) {
      console.log(JSON.stringify({
        blockers: plan.blockers,
        bundleSha256: plan.bundle.sha256,
        confirmationToken: plan.ready ? plan.confirmationToken : null,
        credential: plan.credential,
        galleryDigest: plan.galleryDigest,
        manifestDigest: plan.manifestDigest,
        mode: plan.mode,
        packageName: plan.packageName,
        postApplyBlocked,
        promotion: {
          confirmationToken: postApply?.ready
            ? postApply.promotion.confirmationToken
            : null,
          sourceTrack: postApply?.promotion.sourceTrack ?? 'internal',
          targetTrack: postApply?.promotion.targetTrack ?? 'production',
        },
        ready: plan.ready,
        release: plan.release,
        retained: plan.retained,
        reuse: plan.reuse,
        review: {
          confirmationToken: postApply?.ready
            ? postApply.reviewSubmission.confirmationToken
            : null,
          track: postApply?.reviewSubmission.track ?? 'production',
        },
      }, null, 2));
    } else {
      const lines = [formatPlayBinaryOnlyReport(plan)];
      if (postApply?.ready) {
        lines.push(
          `Binary-only promotion confirmation: --confirm-binary-only-promotion ${postApply.promotion.confirmationToken}`,
          `Binary-only review confirmation: --confirm-binary-only-review ${postApply.reviewSubmission.confirmationToken}`,
        );
      } else {
        lines.push(
          `Binary-only promotion/review: blocked (${postApplyBlocked ?? plan.blockers.join(' | ')})`,
        );
      }
      console.log(lines.join('\n'));
    }
    if (!plan.ready) process.exitCode = 2;
    return;
  }
  if (options.promoteProduction) {
    // The APPLIED receipt, the plan contract, and the promotion token are
    // all re-verified before any credential use or network request.
    const postApply = createPlayBinaryOnlyPostApplyPlan({
      binaryPlan: plan,
      promotionReceiptRelative: options.promotionReceipt,
      reviewReceiptRelative: options.reviewReceipt,
    });
    assertPlayBinaryOnlyPromotionAuthorization(postApply, {
      confirmation: options.promotionConfirmation,
    });
    const client = await createGooglePlayPublisherClient({
      env: process.env,
      root,
    });
    const promotion = await promotePlayBinaryOnlyReleaseToProduction(postApply, {
      client,
      confirmation: options.promotionConfirmation,
    });
    if (options.json) {
      console.log(JSON.stringify({
        mode: 'REMOTE_BINARY_ONLY_PROMOTION',
        versionName: postApply.release.versionName,
        ...promotion,
      }, null, 2));
    } else {
      console.log([
        'Google Play binary-only production promotion: done',
        `Package: ${promotion.packageName}`,
        `Version: ${postApply.release.versionName} (${promotion.versionCode})`,
        `Track: ${promotion.sourceTrack} → ${promotion.targetTrack}`,
        `Release lifecycle: ${promotion.lifecycleState}`,
        `edit: ${promotion.editId}`,
      ].join('\n'));
    }
    return;
  }
  if (options.submitProductionReview) {
    // Same local gates as promotion, with the review-only token.
    const postApply = createPlayBinaryOnlyPostApplyPlan({
      binaryPlan: plan,
      promotionReceiptRelative: options.promotionReceipt,
      reviewReceiptRelative: options.reviewReceipt,
    });
    assertPlayBinaryOnlyReviewSubmissionAuthorization(postApply, {
      confirmation: options.reviewConfirmation,
    });
    const client = await createGooglePlayPublisherClient({
      env: process.env,
      root,
    });
    const review = await submitPlayBinaryOnlyProductionReview(postApply, {
      client,
      confirmation: options.reviewConfirmation,
    });
    if (options.json) {
      console.log(JSON.stringify({
        mode: 'REMOTE_BINARY_ONLY_REVIEW',
        versionName: postApply.release.versionName,
        ...review,
      }, null, 2));
    } else {
      console.log([
        'Google Play binary-only review submission: done',
        `Package: ${review.packageName}`,
        `Version: ${postApply.release.versionName} (${review.versionCode})`,
        `Track: ${review.track}`,
        `edit: ${review.editId}`,
        ...(review.cancelledReleases.length > 0
          ? review.cancelledReleases.map((cancelled) => (
            `Canceled review: ${cancelled.releaseName} `
            + `(versionCode ${cancelled.versionCodes.join(', ')})`
          ))
          : ['Canceled review: none']),
      ].join('\n'));
    }
    return;
  }
  // Exchanging an OAuth token is also a remote request. Verify the
  // confirmation token bound to the current binary and retained gallery and
  // every local gate first so a bad approval never hits the network.
  assertPlayBinaryOnlyAuthorization(plan, {
    confirmation: options.confirmation,
  });
  let result;
  try {
    const client = await createGooglePlayPublisherClient({
      env: process.env,
      root,
    });
    result = await applyPlayBinaryOnlyUpdatePlan(plan, {
      client,
      confirmation: options.confirmation,
    });
  } catch (error) {
    if (/^binary-only app commit succeeded=/u.test(error.message)) throw error;
    throw new Error(
      `binary-only app commit succeeded=false, versionCode=${plan.release.versionCode}. `
      + error.message,
    );
  }
  if (options.json) {
    console.log(JSON.stringify({
      mode: 'REMOTE_BINARY_ONLY_INTERNAL',
      ...result,
    }, null, 2));
  } else {
    console.log([
      'Finished the binary-only internal update via the Google Play Publisher API.',
      `Package: ${result.packageName}`,
      `Version: ${result.retainedVersionCode} → ${result.versionCode} / ${result.track}`,
      `edit commit: ${result.editId}`,
      'Listings/images: reused committed gallery, unchanged',
      'Metadata, images, prices, products, production, reviews: untouched',
    ].join('\n'));
  }
}

main().catch((error) => {
  console.error(`Google Play binary-only update failed: ${error.message}`);
  process.exitCode = 1;
});
