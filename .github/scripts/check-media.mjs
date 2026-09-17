// Check that videos and posters referenced by lesson prose actually exist.
//
// A typo in `<Video src="video/x.mp4" poster="img/x.jpg" />` still lets
// Docusaurus build. The static folder is copied as-is, so a missing file
// is not blocked by anyone. It only breaks on the student's screen.
//
// The other way around, files that sit in static and are used nowhere are
// also reported. Clips cost repo size, so do not leave orphans.

import { readFileSync, existsSync } from 'node:fs';
import { readdirSync } from 'node:fs';
import { join } from 'node:path';

const COURSE = 'apps/docs/course';
const STATIC = 'apps/docs/static';

const pages = readdirSync(COURSE).filter((f) => f.endsWith('.mdx') || f.endsWith('.md'));
const referenced = new Set();
let fail = 0;

for (const page of pages) {
  const body = readFileSync(join(COURSE, page), 'utf8');
  for (const m of body.matchAll(/\b(?:src|poster)=["']([^"']+)["']/g)) {
    const rel = m[1].replace(/^\//, '');
    if (/^https?:/.test(rel)) continue;
    referenced.add(rel);
    if (!existsSync(join(STATIC, rel))) {
      console.error(`::error file=${COURSE}/${page}::referenced file is missing — ${rel}`);
      fail = 1;
    }
  }
}

const onDisk = [];
for (const dir of ['video', 'img']) {
  const full = join(STATIC, dir);
  if (!existsSync(full)) continue;
  for (const f of readdirSync(full)) onDisk.push(`${dir}/${f}`);
}

// Skip things used by site config rather than lesson prose, such as logo,
// favicon, and social card. `docusaurus.config.ts` points at them, so they
// never appear in lesson bodies.
const SITE_OWNED = /^img\/(logo|favicon|social-card)\./;
const orphans = onDisk.filter((f) => !referenced.has(f) && !SITE_OWNED.test(f));

console.log(`${referenced.size} media file(s) referenced by the body — all exist`);
if (orphans.length > 0) {
  console.log(`${orphans.length} file(s) unused by any lesson:`);
  for (const f of orphans) console.log(`  ${f}`);
}
process.exit(fail);
