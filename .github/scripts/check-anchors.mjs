// Confirm internal anchors (#...) in built HTML resolve to real heading ids.
//
// Docusaurus's onBrokenAnchors default is 'warn', so the build still passes.
// A TOC item that goes nowhere can then ship silently.
// Non-ASCII headings come out percent-encoded, so we decode before comparing.

import { readFileSync } from 'node:fs';
import { readdir } from 'node:fs/promises';
import { join, relative } from 'node:path';

const ROOT = 'apps/docs/build';

async function htmlFiles(dir) {
  const out = [];
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...(await htmlFiles(p)));
    else if (e.name.endsWith('.html')) out.push(p);
  }
  return out;
}

// Routing ids, not heading ids
const IGNORE = new Set(['', '__docusaurus_skipToContent_fallback']);

let dead = 0;
for (const file of await htmlFiles(ROOT)) {
  const html = readFileSync(file, 'utf8');
  const ids = new Set([...html.matchAll(/id="([^"]+)"/g)].map((m) => m[1]));
  const hrefs = new Set([...html.matchAll(/href="#([^"]+)"/g)].map((m) => m[1]));

  for (const a of hrefs) {
    if (IGNORE.has(a)) continue;
    if (ids.has(a)) continue;
    let decoded = a;
    try {
      decoded = decodeURIComponent(a);
    } catch {
      // Bad encoding: compare against the original string
    }
    if (ids.has(decoded)) continue;

    dead += 1;
    // Invisible characters are often the cause, so print code points too
    const cps = [...a].map((c) => 'U+' + c.codePointAt(0).toString(16).toUpperCase().padStart(4, '0')).join(' ');
    console.log(`::error file=${relative('.', file)}::broken anchor #${a}`);
    console.log(`    ${cps}`);
  }
}

if (dead > 0) {
  console.log(`\n${dead} broken internal anchor(s)`);
  process.exit(1);
}
console.log('internal anchors ok');
