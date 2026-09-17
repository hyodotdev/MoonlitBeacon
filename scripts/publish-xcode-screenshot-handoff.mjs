#!/usr/bin/env node

// Publish an Xcode Devices screenshot into the capture producer's private
// nonce-bound inbox. This is the only supported delivery path: it validates a
// complete decoded PNG, fsyncs a sibling partial, atomically renames it, and
// emits a matching fsynced receipt.

import './lib/load-env.mjs';

import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  assertPrivateXcodeScreenshotInbox,
  publishXcodeScreenshotHandoff,
} from './lib/ios-device-evidence.mjs';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const names = new Set([
  '--source',
  '--inbox',
  '--expected-filename',
  '--nonce',
  '--requested-at-ms',
]);
const options = {};
const args = process.argv.slice(2);
for (let index = 0; index < args.length; index += 2) {
  const name = args[index];
  const value = args[index + 1];
  if (!names.has(name) || typeof value !== 'string' || value.length === 0) {
    throw new Error(
      'Usage: node scripts/publish-xcode-screenshot-handoff.mjs '
      + '--source <png> --inbox <dir> --expected-filename <name> '
      + '--nonce <hex> --requested-at-ms <epoch-ms>',
    );
  }
  if (Object.hasOwn(options, name)) throw new Error(`duplicate option: ${name}`);
  options[name] = value;
}
if (Object.keys(options).length !== names.size) throw new Error('required screenshot handoff options are missing');

const requestedAtMs = Number(options['--requested-at-ms']);
const inbox = assertPrivateXcodeScreenshotInbox(
  resolve(options['--inbox']),
  REPO_ROOT,
);
const result = publishXcodeScreenshotHandoff({
  inbox,
  sourcePath: resolve(options['--source']),
  expectedFilename: options['--expected-filename'],
  nonce: options['--nonce'],
  requestedAtMs,
});
process.stdout.write(`${JSON.stringify({
  schema: 1,
  published: true,
  expected_filename: options['--expected-filename'],
  receipt_filename: result.receiptFilename,
  sha256: result.sha256,
  width: result.size.width,
  height: result.size.height,
})}\n`);
