import './lib/load-env.mjs';

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  buildStoreContactPlan,
  configureProjectContactSource,
} from './lib/store-contact-config.mjs';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));
const projectPath = path.join(repoRoot, 'apps', 'game', 'project.godot');
const usage = [
  'Usage:',
  '  node scripts/configure-store-contact.mjs',
  '    --site-url https://<public-site>',
  '    --support-email <public-email>',
  '    [--apply --confirm-public-contact]',
].join(' ');

function parseArguments(args) {
  const parsed = {
    siteBaseUrl: '',
    supportEmail: '',
    apply: false,
    confirmPublicContact: false,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--site-url' || arg === '--support-email') {
      const value = args[index + 1];
      if (!value || value.startsWith('--')) throw new Error(usage);
      if (arg === '--site-url') parsed.siteBaseUrl = value;
      else parsed.supportEmail = value;
      index += 1;
    } else if (arg === '--apply') {
      parsed.apply = true;
    } else if (arg === '--confirm-public-contact') {
      parsed.confirmPublicContact = true;
    } else {
      throw new Error(`${usage}\nunsupported option: ${arg}`);
    }
  }
  if (parsed.apply && !parsed.confirmPublicContact) {
    throw new Error(
      '--apply requires --confirm-public-contact as owner confirmation.',
    );
  }
  if (!parsed.apply && parsed.confirmPublicContact) {
    throw new Error('--confirm-public-contact must be used with --apply.');
  }
  return parsed;
}

try {
  const args = parseArguments(process.argv.slice(2));
  const plan = buildStoreContactPlan(args);
  const source = readFileSync(projectPath, 'utf8');
  const configured = configureProjectContactSource(source, plan);
  if (args.apply) {
    writeFileSync(projectPath, configured, 'utf8');
  }
  process.stdout.write(`${JSON.stringify({
    mode: args.apply ? 'applied' : 'dry-run',
    projectChanged: source !== configured,
    ...plan,
  }, null, 2)}\n`);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 2;
}
