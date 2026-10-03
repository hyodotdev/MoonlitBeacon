// Build the combined Firestore ruleset (legacy + 4.0.0 cloud addition).
//
// The implementer may not edit firestore.rules, so the addition lives in
// firestore.cloud.addition.rules and this helper splices the two for the
// rules emulator and for director review. Source-only: it proves the splice
// is mechanical, not that the rules enforce anything. Enforcement is proven
// by cloud-rules.test.mjs against the real emulator.
//
// Usage:
//   node tests/cloud-rules/build-combined-rules.mjs --check
//   node tests/cloud-rules/build-combined-rules.mjs --out /tmp/combined.rules

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const legacyPath = resolve(repository, 'firestore.rules');
const additionPath = resolve(repository, 'firestore.cloud.addition.rules');

const LEGACY_SENTINELS = [
  'match /scores/{scoreId} {',
  'match /analytics_events_v1/{eventId} {',
  'match /{document=**} {',
];
const CATCH_ALL = '    match /{document=**} {';
const ADDITION_SENTINELS = [
  'match /mb_profiles_v1/{uid} {',
  'match /mb_reservations_v1/{publicId} {',
  'match /mb_checkpoints_v1/{uid} {',
  'match /mb_hall_v1/{publicId} {',
];

export function buildCombinedRules() {
  const legacy = readFileSync(legacyPath, 'utf8');
  const addition = readFileSync(additionPath, 'utf8');
  for (const sentinel of LEGACY_SENTINELS) {
    if (!legacy.includes(sentinel)) {
      throw new Error(`legacy rules missing sentinel: ${sentinel}`);
    }
  }
  for (const sentinel of ADDITION_SENTINELS) {
    if (!addition.includes(sentinel)) {
      throw new Error(`addition missing block: ${sentinel}`);
    }
  }
  const catchAllIndex = legacy.indexOf(CATCH_ALL);
  if (catchAllIndex < 0) {
    throw new Error('legacy catch-all block not found for splice point');
  }
  const head = legacy.slice(0, catchAllIndex);
  const tail = legacy.slice(catchAllIndex);
  const indented = addition
    .split('\n')
    .map((line) => (line.trim() === '' ? '' : `    ${line}`))
    .join('\n');
  const combined = `${head}    // ---- 4.0.0 owned cloud (from firestore.cloud.addition.rules) ----\n${indented}\n\n${tail}`;
  // Single pass per line: `//` inside a 'string' (res:// paths) is not a
  // comment, and an apostrophe inside a comment (caller's) is not a string.
  const codeOnly = combined
    .split('\n')
    .map((line) => {
      let out = '';
      let inString = false;
      for (let i = 0; i < line.length; i += 1) {
        const ch = line[i];
        if (inString) {
          if (ch === '\\') i += 1;
          else if (ch === "'") inString = false;
          continue;
        }
        if (ch === "'") {
          inString = true;
          continue;
        }
        if (ch === '/' && line[i + 1] === '/') break;
        out += ch;
      }
      return out;
    })
    .join('\n');
  const open = (codeOnly.match(/\{/g) ?? []).length;
  const close = (codeOnly.match(/\}/g) ?? []).length;
  if (open !== close) {
    throw new Error(`unbalanced code braces in combined rules: ${open} vs ${close}`);
  }
  return { combined, legacy, addition };
}

const args = process.argv.slice(2);
if (args.includes('--check') || args.includes('--out')) {
  const { combined } = buildCombinedRules();
  const outIndex = args.indexOf('--out');
  if (outIndex >= 0 && args[outIndex + 1]) {
    writeFileSync(args[outIndex + 1], combined);
    console.log(`combined rules written to ${args[outIndex + 1]}`);
  } else {
    console.log(
      `combined rules splice ok — ${combined.split('\n').length} lines`,
    );
  }
}
