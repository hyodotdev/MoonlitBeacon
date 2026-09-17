#!/usr/bin/env node

import './lib/load-env.mjs';

import { fileURLToPath } from 'node:url';
import {
  buildAppStoreReleasePayload,
  canonicalJson,
  createAppStoreReleaseManifest,
  contactPlanFromEnvironment,
  formatAppStoreReleaseReport,
  parseAppStoreReleaseArguments,
  readAndVerifyAppStoreReleaseManifest,
  resolveManifestOutputPath,
  runAppStoreScreenshotValidation,
  writeAppStoreReleaseManifest,
} from './lib/app-store-release.mjs';
import {
  appStoreApplyCheckSummary,
  createAuthenticatedAppStoreApply,
  createAuthenticatedAppStoreApplyAudit,
  formatAppStoreApplyReport,
} from './lib/app-store-connect-apply.mjs';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));

function usage() {
  return [
    'Usage: node scripts/app-store-release.mjs [options]',
    '',
    'The default command validates local inputs only and writes a deterministic manifest.',
    '',
    '  --dry-run       make the default action explicit (no remote requests)',
    '  --check         re-verify an existing manifest against current inputs',
    '  --remote-audit  GET App Store Connect only and build a change plan',
    '  --apply         apply after --check, --remote-audit, and the manifest confirmation token',
    '  --confirm-remote-apply TOKEN  apply confirmation token printed by --check',
    '  --submit-review  submit for review after apply converges, with a separate confirmation',
    '  --confirm-review-submission TOKEN  review-submission confirmation token',
    '  --output PATH   manifest JSON path under builds/release',
    '  --json          print the report as JSON',
    '  --help, -h      print this help',
    '',
    'To include public URLs, set both MOONLIT_PUBLIC_SITE_URL and',
    'MOONLIT_SUPPORT_EMAIL.',
    'Remote work uses MOONLIT_ASC_KEY_ID, MOONLIT_ASC_ISSUER_ID, and',
    'MOONLIT_ASC_PRIVATE_KEY as an absolute path outside the repo.',
    '',
    'apply re-runs GET preflight immediately before every change and refreshes the JWT.',
    'Review submission does not succeed until GET readback of status, 11 items, and the linked build.',
  ].join('\n');
}

async function main() {
  const options = parseAppStoreReleaseArguments(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }

  const manifestPath = resolveManifestOutputPath(repoRoot, options.output);
  const contactPlan = contactPlanFromEnvironment(process.env);
  // PNG hashes in the App Store manifest only prove integrity. Hashing a
  // stale capture after game, translation, or hero resources changed is
  // caught only by re-checking the capture report runtime fingerprint.
  runAppStoreScreenshotValidation(repoRoot, { env: process.env });
  const payload = buildAppStoreReleasePayload({
    repoRoot,
    appId:
      process.env.MOONLIT_ASC_APP_ID?.trim()
      || undefined,
    contactPlan,
  });
  let manifest;
  if (options.check) {
    manifest = readAndVerifyAppStoreReleaseManifest(manifestPath, payload);
  } else {
    manifest = createAppStoreReleaseManifest(payload);
    writeAppStoreReleaseManifest(manifestPath, manifest);
  }

  const applyCheck = options.check
    ? appStoreApplyCheckSummary(manifest)
    : null;
  if (options.apply) {
    const result = await createAuthenticatedAppStoreApply({
      confirmation: options.confirmation,
      manifest,
      payload,
      repoRoot,
      reviewConfirmation: options.reviewConfirmation,
      submitReview: options.submitReview,
    });
    if (options.json) {
      console.log(canonicalJson({ mode: 'REMOTE_APPLY', result }).trimEnd());
    } else {
      console.log(formatAppStoreApplyReport(result));
    }
    if (!result.complete) process.exitCode = 2;
    return;
  }
  const remoteAudit = options.remoteAudit
    ? await createAuthenticatedAppStoreApplyAudit({ repoRoot, payload })
    : null;
  if (options.json) {
    console.log(canonicalJson({
      applyCheck,
      mode: options.remoteAudit
        ? 'GET_ONLY_REMOTE_AUDIT'
        : options.check ? 'LOCAL_MANIFEST_CHECK' : 'LOCAL_ONLY_DRY_RUN',
      manifestPath,
      manifest,
      remoteAudit,
      remoteMutationExecuted: false,
      remoteMutationImplemented: true,
    }).trimEnd());
  } else {
    const report = formatAppStoreReleaseReport({
      manifestPath,
      manifest,
      check: options.check,
      remoteAudit,
    });
    console.log([
      report,
      ...(applyCheck ? [
        `apply confirmation: ${applyCheck.applyConfirmation}`,
        `review confirmation: ${applyCheck.reviewConfirmation}`,
      ] : []),
    ].join('\n'));
  }
}

main().catch((error) => {
  console.error(`App Store release preparation failed: ${error.message}`);
  process.exitCode = error.exitCode ?? 1;
});
