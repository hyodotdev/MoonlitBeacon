// Combined Firebase Hosting composer: player-care files at the root, the
// Docusaurus build under MoonlitBeacon/. No dependencies.
//
//   node apps/player-care/hosting-build.mjs             # compose builds/hosting
//   node apps/player-care/hosting-build.mjs --out DIR   # compose DIR instead
//
// The supported entrypoint is `pnpm hosting:build` from the repo root, which
// builds both inputs fresh before invoking this composer. Direct invocation
// still refuses a stale care dist and requires the docs build to exist.
//
// Composition copies bytes only: no HTML rewriting, no timestamps, sorted
// file order, so the same inputs always produce the same output.
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { build as buildCare, compareTrees, expectedOutputs } from './build.mjs';
import { DOCS_PREFIX } from './content/shared.mjs';

const APP_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(APP_DIR, '..', '..');
export const CARE_DIST_DIR = join(APP_DIR, 'dist');
export const DOCS_BUILD_DIR = join(REPO_ROOT, 'apps', 'docs', 'build');
export const HOSTING_OUT_DIR = join(REPO_ROOT, 'builds', 'hosting');

function byName(a, b) {
  if (a.name < b.name) return -1;
  if (a.name > b.name) return 1;
  return 0;
}

// Sorted dist-relative file list. Symlinks are rejected, never followed.
export function listInputFiles(root, kind) {
  const resolved = resolve(root);
  let stat;
  try {
    stat = lstatSync(resolved);
  } catch {
    throw new Error(`${kind} input is missing: ${resolved}`);
  }
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    throw new Error(`${kind} input is not a real directory: ${resolved}`);
  }
  const files = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true }).sort(byName)) {
      const full = join(dir, entry.name);
      const rel = relative(resolved, full).split(sep).join('/');
      if (entry.isSymbolicLink()) {
        throw new Error(`${kind} input contains a symlink, refusing to compose: ${rel}`);
      }
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile()) {
        files.push(rel);
      } else {
        throw new Error(`${kind} input has a non-file entry, refusing to compose: ${rel}`);
      }
    }
  };
  walk(resolved);
  return files;
}

// Bounds the destructive cleanup. The output must not be an input, a source
// tree, or an ancestor of either; inputs must not sit inside it; symlinks
// are rejected. A non-empty directory is cleaned only when it is the known
// generated output — anything else is refused with nothing deleted.
export function resolveOutputDir(outDir, { careDir, docsDir }) {
  if (typeof outDir !== 'string' || outDir.trim() === '') {
    throw new Error('hosting output needs a directory');
  }
  const resolved = resolve(outDir);
  const care = resolve(careDir);
  const docs = resolve(docsDir);
  const inside = (child, parent) => child === parent || child.startsWith(`${parent}${sep}`);
  for (const [label, other] of [['care input', care], ['docs input', docs], ['player-care app', resolve(APP_DIR)], ['repo root', resolve(REPO_ROOT)]]) {
    if (resolved === other) {
      throw new Error(`hosting output must not be ${label}: ${resolved}`);
    }
  }
  if (inside(care, resolved) || inside(docs, resolved)) {
    throw new Error(`hosting output must not contain its inputs: ${resolved}`);
  }
  if (inside(resolved, care) || inside(resolved, docs)) {
    throw new Error(`hosting output must not sit inside its inputs: ${resolved}`);
  }
  if (!existsSync(resolved)) return resolved;
  const stat = lstatSync(resolved);
  if (stat.isSymbolicLink()) {
    throw new Error(`hosting output must not be a symlink: ${resolved}`);
  }
  if (!stat.isDirectory()) {
    throw new Error(`hosting output is not a directory: ${resolved}`);
  }
  if (readdirSync(resolved).length > 0 && resolved !== resolve(HOSTING_OUT_DIR)) {
    throw new Error(
      `refusing to clean a non-empty unexpected directory (nothing deleted): ${resolved}\n`
      + `compose into an empty directory, or the generated ${relative(REPO_ROOT, HOSTING_OUT_DIR)}`,
    );
  }
  return resolved;
}

export function composeHosting({ careDir, docsDir, outDir }) {
  const target = resolveOutputDir(outDir, { careDir, docsDir });
  const careFiles = listInputFiles(careDir, 'care');
  const docsFiles = listInputFiles(docsDir, 'docs');
  if (careFiles.length === 0) throw new Error(`care input has no files: ${resolve(careDir)}`);
  if (docsFiles.length === 0) throw new Error(`docs input has no files: ${resolve(docsDir)}`);
  rmSync(target, { recursive: true, force: true });
  mkdirSync(target, { recursive: true });
  const careRoot = resolve(careDir);
  for (const rel of careFiles) {
    const dest = join(target, rel);
    mkdirSync(dirname(dest), { recursive: true });
    copyFileSync(join(careRoot, rel), dest);
  }
  const docsRoot = resolve(docsDir);
  for (const rel of docsFiles) {
    const dest = join(target, DOCS_PREFIX, rel);
    mkdirSync(dirname(dest), { recursive: true });
    copyFileSync(join(docsRoot, rel), dest);
  }
  return { outDir: target, careFiles: careFiles.length, docsFiles: docsFiles.length };
}

async function main(args) {
  const outIndex = args.indexOf('--out');
  const outDir = outIndex >= 0 ? args[outIndex + 1] : HOSTING_OUT_DIR;
  if (outIndex >= 0 && !outDir) throw new Error('--out needs a directory');
  const fresh = mkdtempSync(join(tmpdir(), 'hosting-care-'));
  try {
    const pages = await buildCare(fresh);
    const mismatches = compareTrees(fresh, CARE_DIST_DIR, expectedOutputs(pages));
    if (mismatches.length > 0) {
      throw new Error(`care dist/ is stale — run pnpm player-care:build first:\n${mismatches.map((line) => `  ${line}`).join('\n')}`);
    }
  } finally {
    rmSync(fresh, { recursive: true, force: true });
  }
  if (!existsSync(DOCS_BUILD_DIR) || !statSync(DOCS_BUILD_DIR).isDirectory()) {
    throw new Error(`docs build is missing — run pnpm docs:build first: ${relative(REPO_ROOT, DOCS_BUILD_DIR)}`);
  }
  const summary = composeHosting({ careDir: CARE_DIST_DIR, docsDir: DOCS_BUILD_DIR, outDir });
  process.stdout.write(`hosting build ok — ${summary.careFiles} care + ${summary.docsFiles} docs files -> ${relative(REPO_ROOT, summary.outDir)}\n`);
}

const invokedAsScript = process.argv[1] !== undefined
  && pathToFileURL(process.argv[1]).href === import.meta.url;

if (invokedAsScript) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
