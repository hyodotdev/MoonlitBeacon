#!/usr/bin/env node

// Replace only Google Play listing images (icon, feature graphic, three screenshot sets).
//
//     node scripts/apply-play-listing-images.mjs --check
//     node scripts/apply-play-listing-images.mjs --apply \
//       --confirm-listing-images <token>
//
// `apply-play-release.mjs --apply` bundles AAB, listing, and images in one edit.
// Using that path just to change screenshots also ships a new versionCode to internal —
// that actually happened when we only wanted to fix art, so this path was split out
// (the 2.0.0 first cut shipped with the hero buried under speech bubbles and banners).
//
// Validation reuses the existing release package plan. If the package is older than
// source, plan creation refuses, so this path cannot quietly upload stale images either.
// Bundle upload, track changes, and product sync do not exist in this script.

import './lib/load-env.mjs';

import { createHash } from 'node:crypto';
import {
  existsSync,
  lstatSync,
  readFileSync,
  realpathSync,
  renameSync,
  writeFileSync,
} from 'node:fs';
import { isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  createGooglePlayApplyPlan,
  createGooglePlayPublisherClient,
} from './lib/google-play-publisher-apply.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const RECEIPT = resolve(root, 'builds/release/google-play-images-receipt.json');

function fail(message) {
  console.error(`Google Play image apply failed: ${message}`);
  process.exit(1);
}

function confirmationToken(plan) {
  return `google-play-images:${plan.packageName}:${plan.manifestDigest.slice(0, 16)}`;
}

function isInside(parent, child) {
  const relation = relative(parent, child);
  return relation === ''
    || (!relation.startsWith(`..${sep}`) && relation !== '..' && !isAbsolute(relation));
}

// `readVerifiedPackagePayload` is a library-internal function, so it is restated here.
// Same meaning — reject paths outside the package and symlinks; sha256 must match the plan.
function readVerifiedPayload(plan, relativePath, expectedSha256) {
  const outputReal = realpathSync(plan.outputPath);
  const path = resolve(outputReal, relativePath);
  if (!isInside(outputReal, path)) fail(`payload points outside the package: ${relativePath}`);
  let current = outputReal;
  for (const part of relativePath.split('/')) {
    current = resolve(current, part);
    if (lstatSync(current).isSymbolicLink()) {
      fail(`payload contains a symbolic link: ${relativePath}`);
    }
  }
  const contents = readFileSync(path);
  const digest = createHash('sha256').update(contents).digest('hex');
  if (digest !== expectedSha256) fail(`payload sha256 does not match the plan: ${relativePath}`);
  return contents;
}

function summarize(plan) {
  const counts = {};
  for (const operation of plan.images.uploadOperations) {
    counts[operation.imageType] = (counts[operation.imageType] ?? 0) + 1;
  }
  return Object.entries(counts).map(([type, n]) => `${type} ${n}`).join(' · ');
}

async function main() {
  const args = process.argv.slice(2);
  const check = args.includes('--check');
  const apply = args.includes('--apply');
  if (check === apply) fail('Specify exactly one of --check or --apply.');

  const plan = createGooglePlayApplyPlan({ root });
  if (!plan.credential?.ready) {
    fail(`Service account is not ready: ${plan.credential?.reason ?? 'unknown'}`);
  }
  const token = confirmationToken(plan);

  if (check) {
    console.log('Google Play image-only apply check: ready');
    console.log(`Package: ${plan.packageName}`);
    console.log(`Images: ${summarize(plan)} (reset ${plan.images.resetBeforeUpload.length} type(s))`);
    console.log('Bundle, track, products: untouched');
    console.log(`Apply confirmation: --confirm-listing-images ${token}`);
    return;
  }

  const supplied = args[args.indexOf('--confirm-listing-images') + 1];
  if (!args.includes('--confirm-listing-images') || supplied !== token) {
    fail(`Confirmation token is missing or different. Use the token --check printed as-is.`);
  }
  if (existsSync(RECEIPT)) {
    const previous = JSON.parse(readFileSync(RECEIPT, 'utf8'));
    if (previous?.manifestDigest === plan.manifestDigest) {
      fail('An image-apply receipt for this package already exists. Confirm whether a rerun is needed.');
    }
    const archived = RECEIPT.replace(/\.json$/, `.${previous?.appliedAt ?? 'unknown'}.json`)
      .replaceAll(':', '-');
    renameSync(RECEIPT, archived);
    console.log(`Archived previous receipt: ${archived}`);
  }

  const client = await createGooglePlayPublisherClient({ env: process.env, root });
  const edit = await client.insertEdit(plan.packageName);
  const editId = edit?.id;
  if (typeof editId !== 'string' || editId === '') fail('edit create response has no id.');

  for (const operation of plan.images.resetBeforeUpload) {
    await client.deleteAllImages(
      plan.packageName, editId, operation.language, operation.imageType);
  }
  for (const operation of plan.images.uploadOperations) {
    const contents = readVerifiedPayload(plan, operation.mediaPath, operation.sha256);
    const uploaded = await client.uploadImage(plan.packageName, editId, operation, contents);
    if (typeof uploaded?.image?.id !== 'string' || uploaded.image.id === '') {
      fail(`${operation.language}/${operation.imageType} upload response has no image id.`);
    }
  }

  const validated = await client.validateEdit(plan.packageName, editId);
  if (validated?.id !== editId) fail('edit validate response does not match.');
  const committed = await client.commitEdit(plan.packageName, editId, plan.review);
  if (committed?.id !== editId) fail('edit commit response does not match.');

  writeFileSync(RECEIPT, `${JSON.stringify({
    schemaVersion: 1,
    packageName: plan.packageName,
    manifestDigest: plan.manifestDigest,
    editId,
    uploads: plan.images.uploadOperations.length,
    appliedAt: new Date().toISOString(),
  }, null, 2)}\n`, { flag: 'wx' });

  console.log('Google Play image apply: done');
  console.log(`Package: ${plan.packageName}`);
  console.log(`Images: ${summarize(plan)}`);
  console.log(`edit commit: ${editId}`);
  console.log('Bundle, track, products: untouched');
}

await main();
