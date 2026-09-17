#!/usr/bin/env node

import './lib/load-env.mjs';

import { fileURLToPath } from 'node:url';
import {
  applyGooglePlayReleasePlan,
  assertGooglePlayApplyAuthorization,
  assertGooglePlayPromotionAuthorization,
  assertGooglePlayReviewSubmissionAuthorization,
  authorizeGooglePlayProductAdoption,
  authorizeGooglePlayProductResume,
  createGooglePlayApplyPlan,
  createGooglePlayPublisherClient,
  formatGooglePlayApplyReport,
  parseGooglePlayApplyArguments,
  prepareGooglePlayProductSync,
  promoteGooglePlayReleaseToProduction,
  submitGooglePlayProductionReview,
  synchronizeGooglePlayOneTimeProducts,
} from './lib/google-play-publisher-apply.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));

function usage() {
  return [
    'Usage:',
    '  node scripts/apply-play-release.mjs --check [--json]',
    '  node scripts/apply-play-release.mjs --apply \\',
    '    --confirm-remote-apply <app token> [--json]',
    '  node scripts/apply-play-release.mjs --apply --include-products \\',
    '    --confirm-remote-apply <app token> --confirm-products <product token>',
    '  node scripts/apply-play-release.mjs --resume-products \\',
    '    --confirm-remote-apply <app token> --confirm-products <product token>',
    '  node scripts/apply-play-release.mjs --adopt-committed-release \\',
    '    --confirm-remote-apply <app token> --confirm-products <product token>',
    '  node scripts/apply-play-release.mjs --promote-production \\',
    '    --confirm-promotion <promotion token>',
    '  node scripts/apply-play-release.mjs --submit-production-review \\',
    '    --confirm-production-review <review token>',
    '',
    'Options:',
    '  --package PATH       google-play-upload package to verify',
    '  --config PATH        account-owner approval and internal track config',
    '  --include-products   also sync the 7 non-consumable products after app commit',
    '',
    '--check uses no network at all.',
    '--apply is the only path that authenticates with GOOGLE_APPLICATION_CREDENTIALS,',
    'applies the AAB, 5 listings, and phone/7-inch/10-inch images in one edit, then',
    'validates and commits the internal track. It fails instead of canceling an in-review change.',
    'With product options it finishes same-day price conversion and read-only preflight before',
    'the edit, records a COMMITTING intent at a fixed path, then applies the 7 non-consumables after app commit.',
    '--resume-products re-verifies the receipt and remote internal version, then resumes products only.',
    '--adopt-committed-release is only for after an app-only apply with no products. It re-verifies product '
      + 'preflight and the exact internal release, atomically creates a new receipt, then '
      + 'applies products only.',
    '--promote-production only moves a versionCode already committed on internal to production. '
      + 'It does not touch AAB, listings, images, or products. It first looks up the original internal release and '
      + 'whether production already has it, then writes a dedicated receipt.',
    '--submit-production-review sends the production release for review. Only this path '
      + 'commits with CANCEL_IN_REVIEW_AND_SUBMIT, so a previous in-review change is canceled. '
      + 'What will be canceled is recorded in the receipt before running and printed in the result.',
    'Do not delete a COMMITTING receipt or bypass it on another path before remote confirmation.',
  ].join('\n');
}

async function main() {
  const options = parseGooglePlayApplyArguments(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }
  const plan = createGooglePlayApplyPlan({
    configRelative: options.config,
    env: process.env,
    outputRelative: options.package,
    receiptRelative: options.receipt,
    root,
  });
  if (options.check) {
    if (options.json) {
      console.log(JSON.stringify({
        blockers: plan.blockers,
        confirmationToken: plan.ready ? plan.confirmationToken : null,
        credential: plan.credential,
        manifestDigest: plan.manifestDigest,
        mode: 'LOCAL_ONLY_CHECK',
        packageName: plan.packageName,
        products: {
          confirmationToken: plan.products.confirmationToken,
          excludedRegions: plan.products.policy.excludedRegions,
          newRegionsAutomaticallyAvailable:
            plan.products.policy.newRegionsAutomaticallyAvailable,
          productIds: plan.products.policy.products.map(({ productId }) => productId),
          ready: plan.includeProductsAllowed,
        },
        promotion: {
          confirmationToken: plan.ready ? plan.promotion.confirmationToken : null,
          sourceTrack: plan.promotion.sourceTrack,
          targetTrack: plan.promotion.targetTrack,
        },
        ready: plan.ready,
        release: plan.release,
      }, null, 2));
    } else {
      console.log(formatGooglePlayApplyReport(plan));
    }
    if (!plan.ready) process.exitCode = 2;
    return;
  }
  if (options.submitProductionReview) {
    // Only this path commits with CANCEL_IN_REVIEW_AND_SUBMIT. In-review changes are canceled,
    // so it takes a dedicated token and prints exactly what was canceled after running.
    assertGooglePlayReviewSubmissionAuthorization(plan, {
      confirmation: options.reviewConfirmation,
    });
    const client = await createGooglePlayPublisherClient({
      env: process.env,
      root,
    });
    const review = await submitGooglePlayProductionReview(plan, {
      client,
      confirmation: options.reviewConfirmation,
    });
    if (options.json) {
      console.log(JSON.stringify({
        mode: 'SUBMIT_PRODUCTION_REVIEW',
        versionName: plan.release.versionName,
        ...review,
      }, null, 2));
    } else {
      console.log([
        'Google Play review submission: done',
        `Package: ${review.packageName}`,
        `Version: ${plan.release.versionName} (${review.versionCode})`,
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
  if (options.promoteProduction) {
    // Promotion is a separate boundary that does not touch AAB, listings, images, or products.
    // Take only the dedicated token and pass local gates before any remote request.
    assertGooglePlayPromotionAuthorization(plan, {
      confirmation: options.promotionConfirmation,
    });
    const client = await createGooglePlayPublisherClient({
      env: process.env,
      root,
    });
    const promotion = await promoteGooglePlayReleaseToProduction(plan, {
      client,
      confirmation: options.promotionConfirmation,
    });
    if (options.json) {
      console.log(JSON.stringify({
        mode: 'PROMOTE_PRODUCTION',
        versionName: plan.release.versionName,
        ...promotion,
      }, null, 2));
    } else {
      console.log([
        'Google Play production promotion: done',
        `Package: ${promotion.packageName}`,
        `Version: ${plan.release.versionName} (${promotion.versionCode})`,
        `Track: ${promotion.sourceTrack} → ${promotion.targetTrack}`,
        `Release lifecycle: ${promotion.lifecycleState}`,
        `edit: ${promotion.editId}`,
      ].join('\n'));
    }
    return;
  }
  // Exchanging an OAuth token is also a remote request. Verify the confirmation token bound
  // to the current manifest and every local gate first so a bad approval never hits the network.
  assertGooglePlayApplyAuthorization(plan, {
    confirmation: options.confirmation,
    includeProducts: options.includeProducts,
    productsConfirmation: options.productsConfirmation,
  });
  let appCommitStatus = (
    options.resumeProducts || options.adoptCommittedRelease
  ) ? 'uncertain' : 'false';
  let result;
  let productResult = null;
  try {
    const client = await createGooglePlayPublisherClient({
      env: process.env,
      root,
    });
    if (options.adoptCommittedRelease) {
      const productPreparation = await prepareGooglePlayProductSync(plan, {
        client,
        productsConfirmation: options.productsConfirmation,
      });
      const adoptionAuthorization = await authorizeGooglePlayProductAdoption(plan, {
        client,
        confirmation: options.confirmation,
        productPreparation,
        productsConfirmation: options.productsConfirmation,
      });
      appCommitStatus = 'true';
      productResult = await synchronizeGooglePlayOneTimeProducts(plan, {
        adoptionAuthorization,
        client,
        productPreparation,
        productsConfirmation: options.productsConfirmation,
      });
      result = {
        adopted: true,
        committed: true,
        editId: null,
        packageName: plan.packageName,
        productsApplied: true,
        resumed: false,
        track: plan.release.track,
        versionCode: plan.release.versionCode,
      };
    } else if (options.resumeProducts) {
      const resumeAuthorization = await authorizeGooglePlayProductResume(plan, {
        client,
        productsConfirmation: options.productsConfirmation,
      });
      appCommitStatus = 'true';
      const productPreparation = await prepareGooglePlayProductSync(plan, {
        client,
        productsConfirmation: options.productsConfirmation,
      });
      productResult = await synchronizeGooglePlayOneTimeProducts(plan, {
        client,
        productPreparation,
        productsConfirmation: options.productsConfirmation,
        resumeAuthorization,
      });
      result = {
        committed: true,
        editId: null,
        packageName: plan.packageName,
        productsApplied: true,
        resumed: true,
        track: plan.release.track,
        versionCode: plan.release.versionCode,
      };
    } else {
      const productPreparation = options.includeProducts
        ? await prepareGooglePlayProductSync(plan, {
          client,
          productsConfirmation: options.productsConfirmation,
        })
        : null;
      result = await applyGooglePlayReleasePlan(plan, {
        client,
        confirmation: options.confirmation,
        includeProducts: options.includeProducts,
        productPreparation,
        productsConfirmation: options.productsConfirmation,
      });
      appCommitStatus = 'true';
      productResult = options.includeProducts
        ? await synchronizeGooglePlayOneTimeProducts(plan, {
          client,
          productPreparation,
          productsConfirmation: options.productsConfirmation,
          releaseResult: result,
        })
        : null;
    }
  } catch (error) {
    if (/app commit succeeded=/u.test(error.message)) throw error;
    throw new Error(
      `app commit succeeded=${appCommitStatus}, versionCode=${plan.release.versionCode}. `
      + error.message,
    );
  }
  if (options.json) {
    console.log(JSON.stringify({
      mode: options.adoptCommittedRelease
        ? 'REMOTE_PRODUCT_ADOPTION'
        : options.resumeProducts
          ? 'REMOTE_PRODUCT_RESUME'
          : 'REMOTE_APPLY',
      ...result,
      productResult,
      productsApplied: productResult?.productsApplied ?? false,
    }, null, 2));
  } else {
    console.log([
      'Finished applying via the Google Play Publisher API.',
      `Package: ${result.packageName}`,
      `Version/track: ${result.versionCode} / ${result.track}`,
      `edit commit: ${result.editId ?? 'not created (re-verified existing release)'}`,
      ...(productResult === null
        ? ['One-time products: not applied']
        : [
          `One-time products: applied 7 (${productResult.regionsVersion})`,
          `Product region count: ${productResult.regionCount} (CN excluded)`,
          `Newly activated buy options: ${productResult.activatedProductCount}`,
          `Legacy hero_bundle: ${productResult.legacyProductState}`,
        ]),
    ].join('\n'));
  }
}

main().catch((error) => {
  console.error(`Google Play remote apply failed: ${error.message}`);
  process.exitCode = 1;
});
