#!/usr/bin/env node

// Run the repo's deterministic asset checker with the same Python lookup.

// On macOS, Homebrew framework Python can stall loading extension modules
// when spawned as a Node child. Prefer Xcode's system Python, and on other
// platforms search python3/python/py in the usual order.

import './lib/load-env.mjs';

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';

const forwarded = process.argv.slice(2);
const configured = process.env.MOONLIT_PYTHON?.trim();
const candidates = [];

if (configured) candidates.push([configured, []]);
if (process.platform === 'darwin' && existsSync('/usr/bin/python3')) {
  candidates.push(['/usr/bin/python3', []]);
}
if (process.platform === 'win32') candidates.push(['py', ['-3']]);
candidates.push(['python3', []], ['python', []]);

let lastError;
for (const [command, prefix] of candidates) {
  const result = spawnSync(command, [...prefix, ...forwarded], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      PYTHONDONTWRITEBYTECODE: '1',
    },
    stdio: 'inherit',
    shell: false,
  });
  if (result.error?.code === 'ENOENT') {
    lastError = result.error;
    continue;
  }
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
  process.exit();
}

console.error(
  `Could not find a Python 3 binary${lastError ? `: ${lastError.message}` : ''}`,
);
process.exitCode = 127;
