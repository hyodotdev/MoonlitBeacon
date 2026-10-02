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
  createGooglePlayPublisherClient,
} from './lib/google-play-publisher-apply.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));

function usage() {
  return [
    'Usage:',
    '  node scripts/apply-play-binary-only-update.mjs [--check] [--json]',
    '  node scripts/apply-play-binary-only-update.mjs --apply \\',
    '    --confirm-binary-only <binary token> [--json]',
    '',
    'Options:',
    '  --package PATH       retained google-play-upload package to reuse',
    '  --bundle PATH        new AAB that replaces only the binary',
    '  --config PATH        account-owner approval and internal track config',
    '  --receipt PATH       binary-only update receipt to write',
    '',
    'Default with no options is a local check only and uses no network at all.',
    '--apply is the only path that authenticates with GOOGLE_APPLICATION_CREDENTIALS.',
    'It re-verifies the committed internal release and every retained listing and',
    'ordered image hash immediately before mutation, then uploads only the AAB,',
    'updates only the internal track, validates, and commits with ERROR_IF_IN_REVIEW.',
    'It never touches metadata, images, prices, products, production, or reviews.',
    'Reuse of the committed gallery is explicit in the mode and token; it is not',
    'fresh capture evidence and not native purchase evidence.',
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
        ready: plan.ready,
        release: plan.release,
        retained: plan.retained,
        reuse: plan.reuse,
      }, null, 2));
    } else {
      console.log(formatPlayBinaryOnlyReport(plan));
    }
    if (!plan.ready) process.exitCode = 2;
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
