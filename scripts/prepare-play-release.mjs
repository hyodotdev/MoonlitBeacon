#!/usr/bin/env node

import './lib/load-env.mjs';

import { fileURLToPath } from 'node:url';
import {
  DEFAULT_PLAY_RELEASE_INPUTS,
  preparePlayReleasePackage,
} from './lib/play-release-package.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));

function usage() {
  return [
    'Usage: node scripts/prepare-play-release.mjs [--output <relative path>]',
    '',
    'Build the Google Play upload input tree locally only.',
    'Does not touch Play Console, the Publisher API, legal declarations, or upload.',
  ].join('\n');
}

function parseArgs(args) {
  let outputRelative = DEFAULT_PLAY_RELEASE_INPUTS.output;
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === '--help') return { help: true, outputRelative };
    if (argument === '--output') {
      const value = args[index + 1];
      if (!value || value.startsWith('--')) {
        throw new Error('--output requires a repository-relative path.');
      }
      outputRelative = value;
      index += 1;
      continue;
    }
    throw new Error(`unsupported option: ${argument}`);
  }
  return { help: false, outputRelative };
}

try {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    process.exitCode = 0;
  } else {
    const manifest = preparePlayReleasePackage({
      outputRelative: options.outputRelative,
      root,
    });
    process.stdout.write([
      'Verified the local Google Play upload package.',
      `Output: ${options.outputRelative}`,
      `Package: ${manifest.packageName}`,
      `Version: ${manifest.release.versionName} (${manifest.release.versionCode})`,
      `Locales/phone/7-inch/10-inch/IAP: ${manifest.counts.localeCount}/`
        + `${manifest.counts.phoneScreenshots}/`
        + `${manifest.counts.sevenInchScreenshots}/`
        + `${manifest.counts.tenInchScreenshots}/`
        + `${manifest.counts.oneTimeProductPayloads}`,
      `Remote apply ready: ${manifest.gates.remoteActionsReady ? 'ready' : 'blocked'}`,
      'Did not call the Publisher API or change Play Console.',
    ].join('\n') + '\n');
  }
} catch (error) {
  process.stderr.write(
    `Failed to create the local Google Play upload package: ${error.message}\n`,
  );
  process.exitCode = 1;
}
