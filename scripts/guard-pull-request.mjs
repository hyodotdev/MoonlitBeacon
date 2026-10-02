#!/usr/bin/env node
// PreToolUse hook: no pull request is opened unless the user allowed it.
//
// Wired in `.claude/settings.json`. Claude Code sends the pending tool call as
// JSON on stdin; this refuses the ones that would open a PR (see
// `lib/pr-guard.mjs` for what counts) and lets everything else through.
//
// To allow ONE pull request, the user creates an empty `.claude/allow-pr`. The
// guard deletes the file the moment it lets a call through, so an approval is
// spent on exactly one PR and never lingers. The file is gitignored.
//
// An agent must never create that file, edit this guard, or edit the settings
// that wire it in (AGENTS.md says so too). The file is the user's signal.

import { existsSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';

import { findPullRequestCreation } from './lib/pr-guard.mjs';

const ALLOW_FILE = '.claude/allow-pr';

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8');
}

let input;
try {
  input = JSON.parse(await readStdin());
} catch {
  // The harness always sends JSON. If it did not, blocking every tool call would
  // be worse than letting one through, so say so and step aside.
  process.stderr.write('guard-pull-request: unreadable hook input, not checking this call\n');
  process.exit(0);
}

const hit = findPullRequestCreation(input.tool_name, input.tool_input);
if (!hit) process.exit(0);

const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
const allow = join(root, ALLOW_FILE);
if (existsSync(allow)) {
  unlinkSync(allow);
  process.exit(0);
}

const reason = [
  `Blocked: this would open a pull request (${hit}). This repo does not let an agent open one on its own.`,
  '',
  'Do not retry, and do not look for another way in (gh api, curl, an MCP tool, the GitHub web page).',
  `Do not create ${ALLOW_FILE} yourself, and do not edit this guard or its settings.`,
  '',
  'Stop and tell the user which PR you would open: base branch, head branch, title and the files it carries.',
  `If they want it, they allow exactly one by running \`touch ${ALLOW_FILE}\` themselves; the guard spends the file on the next PR.`,
].join('\n');

process.stdout.write(`${JSON.stringify({
  hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: 'deny',
    permissionDecisionReason: reason,
  },
})}\n`);
