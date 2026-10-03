// Combined hosting checker: exact composition, link health, and config scope.
// No dependencies.
//
//   node apps/player-care/hosting-check.mjs             # check builds/hosting
//   node apps/player-care/hosting-check.mjs --out DIR   # check DIR instead
//
// Verifies the composed output against both inputs: every care file at the
// root and every docs-build file under MoonlitBeacon/ must match byte for
// byte in both directions, every local href/src in every page must resolve
// (extensionless Docusaurus routes included), and the hosting config must
// stay a narrow hosting-only deploy of this generated directory. Care-page
// content rules (structure, forbidden copy, outbound allowlist, mailto) are
// enforced by player-care:check on a fresh render and inherited through byte
// parity, so they are not re-implemented here. Outbound https links on the
// docs side are counted, not fetched: this checker is offline.
import { existsSync, lstatSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { build as buildCare, checkBuilt, compareTrees, expectedOutputs } from './build.mjs';
import { DOCS_PREFIX, SITE_BASE } from './content/shared.mjs';

const APP_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(APP_DIR, '..', '..');
export const CARE_DIST_DIR = join(APP_DIR, 'dist');
export const DOCS_BUILD_DIR = join(REPO_ROOT, 'apps', 'docs', 'build');
export const HOSTING_OUT_DIR = join(REPO_ROOT, 'builds', 'hosting');
export const HOSTING_CONFIG_PATH = join(APP_DIR, 'firebase.hosting.json');
export const ROOT_CONFIG_PATH = join(REPO_ROOT, 'firebase.json');

export const SITE_ID = 'moonlitbeacon-778ee';

export const KEY_ROUTES = [
  '/',
  '/ko/privacy',
  '/ko/support',
  `/${DOCS_PREFIX}`,
  `/${DOCS_PREFIX}course`,
  `/${DOCS_PREFIX}course/chapter-01`,
  `/${DOCS_PREFIX}docs/intro`,
];

const SECRET_BASENAMES = [
  [/^\.env(\..*)?$/u, 'environment file'],
  [/\.p8$/u, 'signing key'],
  [/\.jks$/u, 'signing keystore'],
  [/\.keystore$/u, 'signing keystore'],
  [/service-account.*\.json$/u, 'service-account key'],
];

function byName(a, b) {
  if (a.name < b.name) return -1;
  if (a.name > b.name) return 1;
  return 0;
}

// Maps a link to the candidate files that would serve it, mirroring Hosting
// cleanUrls: a trailing slash serves index.html, an extensionless path tries
// the file itself, then .html, then index.html underneath.
export function resolveCombinedLink(fromFile, href) {
  if (href === '' || href.startsWith('#')) return { skipped: true };
  const path = href.split('#')[0].split('?')[0];
  if (path === '') return { skipped: true };
  let target;
  if (path.startsWith('/')) {
    target = path.slice(1);
  } else {
    const fromDir = dirname(fromFile);
    target = fromDir === '.' ? path : `${fromDir}/${path}`;
  }
  const parts = [];
  for (const segment of target.split('/')) {
    if (segment === '' || segment === '.') continue;
    if (segment === '..') {
      if (parts.length === 0) return { escapes: true };
      parts.pop();
    } else {
      parts.push(segment);
    }
  }
  const normalized = parts.join('/');
  if (normalized === '') return { candidates: ['index.html'] };
  if (path.endsWith('/')) return { candidates: [`${normalized}/index.html`] };
  if (parts[parts.length - 1].includes('.')) return { candidates: [normalized] };
  return { candidates: [normalized, `${normalized}.html`, `${normalized}/index.html`] };
}

function isFile(root, candidate) {
  const full = join(root, candidate);
  return existsSync(full) && statSync(full).isFile();
}

function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

export function checkHostingConfig(hostingConfigPath, outDir) {
  const problems = [];
  const where = relative(REPO_ROOT, resolve(hostingConfigPath));
  if (!existsSync(hostingConfigPath)) {
    return [`hosting config is missing: ${where}`];
  }
  let hosting = null;
  try {
    hosting = readJson(hostingConfigPath);
  } catch {
    return [`hosting config is not valid JSON: ${where}`];
  }
  const topKeys = Object.keys(hosting);
  if (topKeys.length !== 1 || topKeys[0] !== 'hosting') {
    problems.push(`hosting config must be hosting-only, found keys: ${topKeys.join(',')}`);
  }
  const config = hosting.hosting ?? {};
  if (config.site !== SITE_ID) {
    problems.push(`hosting config site must be ${SITE_ID}`);
  }
  const publicDir = typeof config.public === 'string'
    ? resolve(dirname(resolve(hostingConfigPath)), config.public)
    : null;
  if (publicDir !== resolve(outDir)) {
    problems.push(`hosting config public must resolve to the generated output (${relative(REPO_ROOT, resolve(outDir))}), found: ${config.public}`);
  }
  if (config.cleanUrls !== true) {
    problems.push('hosting config cleanUrls must be true');
  }
  for (const key of ['rewrites', 'redirects']) {
    if (key in config) {
      problems.push(`hosting config must not set ${key} (no catch-all; 404.html serves missing pages)`);
    }
  }
  for (const key of Object.keys(config)) {
    if (!['site', 'public', 'ignore', 'cleanUrls', 'trailingSlash'].includes(key)) {
      problems.push(`hosting config key not allowed: ${key}`);
    }
  }
  return problems;
}

export function checkRootConfig(rootConfigPath) {
  const where = relative(REPO_ROOT, resolve(rootConfigPath));
  if (!existsSync(rootConfigPath)) return [`root firebase config is missing: ${where}`];
  let root = null;
  try {
    root = readJson(rootConfigPath);
  } catch {
    return [`root firebase config is not valid JSON: ${where}`];
  }
  const problems = [];
  if (!('firestore' in root)) {
    problems.push('root firebase config must keep its firestore section');
  }
  if ('hosting' in root) {
    problems.push('root firebase config must stay Firestore-only (no hosting key)');
  }
  return problems;
}

function walkOutput(outDir, problems) {
  const files = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true }).sort(byName)) {
      const full = join(dir, entry.name);
      const rel = relative(outDir, full).split(sep).join('/');
      if (entry.isSymbolicLink()) {
        problems.push(`symlink in hosting output: ${rel}`);
        continue;
      }
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile()) {
        files.push(rel);
      } else {
        problems.push(`non-file entry in hosting output: ${rel}`);
      }
    }
  };
  walk(outDir);
  return files.sort();
}

function sameBytes(a, b) {
  return readFileSync(a).equals(readFileSync(b));
}

export async function checkHosting(options = {}) {
  const problems = [];
  const outDir = resolve(options.outDir ?? HOSTING_OUT_DIR);
  const careDir = resolve(options.careDir ?? CARE_DIST_DIR);
  const docsDir = resolve(options.docsDir ?? DOCS_BUILD_DIR);
  const hostingConfigPath = options.hostingConfigPath ?? HOSTING_CONFIG_PATH;
  const rootConfigPath = options.rootConfigPath ?? ROOT_CONFIG_PATH;

  problems.push(...checkHostingConfig(hostingConfigPath, outDir));
  problems.push(...checkRootConfig(rootConfigPath));

  let ready = true;
  for (const [label, dir] of [['combined output', outDir], ['care input', careDir], ['docs input', docsDir]]) {
    if (!existsSync(dir) || !statSync(dir).isDirectory()) {
      problems.push(`${label} is missing or not a directory: ${relative(REPO_ROOT, dir)}`);
      ready = false;
    }
  }
  if (!ready) {
    throw new Error(`hosting check failed — ${problems.length} problem(s):\n${problems.map((problem) => `  ${problem}`).join('\n')}`);
  }

  // 1. The care input must itself be fresh and pass its own content checks.
  const fresh = mkdtempSync(join(tmpdir(), 'hosting-care-'));
  try {
    const pages = await buildCare(fresh);
    try {
      await checkBuilt(fresh);
    } catch (error) {
      problems.push(`fresh care render fails player-care:check: ${error instanceof Error ? error.message.split('\n')[0] : String(error)}`);
    }
    for (const line of compareTrees(fresh, careDir, expectedOutputs(pages))) {
      problems.push(`care input is stale: ${line}`);
    }
  } finally {
    rmSync(fresh, { recursive: true, force: true });
  }

  // 2. Exact bidirectional parity: care files at the root, docs files under
  // the mount. Either direction failing means a changed, missing, or stale file.
  const outputFiles = walkOutput(outDir, problems);
  const rootFiles = outputFiles.filter((file) => !file.startsWith(DOCS_PREFIX));
  const mountedFiles = outputFiles
    .filter((file) => file.startsWith(DOCS_PREFIX))
    .map((file) => file.slice(DOCS_PREFIX.length));
  const careFiles = walkOutput(careDir, problems);
  const docsFiles = walkOutput(docsDir, problems);
  const compare = (label, expected, actual, expectedRoot, actualRoot, prefix) => {
    const want = new Set(expected);
    const have = new Set(actual);
    for (const file of [...want].sort()) {
      if (!have.has(file)) {
        problems.push(`${label} missing in output: ${prefix}${file}`);
      } else if (!sameBytes(join(expectedRoot, file), join(actualRoot, `${prefix}${file}`))) {
        problems.push(`${label} bytes differ: ${prefix}${file}`);
      }
    }
    for (const file of [...have].sort()) {
      if (!want.has(file)) problems.push(`unexpected file in output: ${prefix}${file}`);
    }
  };
  compare('care file', careFiles, rootFiles, careDir, outDir, '');
  compare('docs file', docsFiles, mountedFiles, docsDir, outDir, DOCS_PREFIX);

  // 3. Nothing unpublished may ride along: author notes, secrets, tooling.
  for (const file of outputFiles) {
    const segments = file.split('/');
    if (segments.includes('notes')) {
      problems.push(`author notes in hosting output: ${file}`);
    }
    if (segments.includes('.git') || segments.includes('node_modules')) {
      problems.push(`tooling directory in hosting output: ${file}`);
    }
    const base = segments[segments.length - 1];
    for (const [pattern, label] of SECRET_BASENAMES) {
      if (pattern.test(base)) problems.push(`${label} in hosting output: ${file}`);
    }
  }

  // 4. No NUL bytes in served HTML (docs SSR padding leak; see strip-nul).
  const htmlFiles = outputFiles.filter((file) => file.endsWith('.html') || file.endsWith('.htm'));
  for (const file of htmlFiles) {
    if (readFileSync(join(outDir, file)).indexOf(0) !== -1) {
      problems.push(`NUL byte in hosting output: ${file}`);
    }
  }

  // 5. A real missing page: the care 404, byte-identical, with no catch-all
  // rewrite to hide behind (rewrites are rejected with the config above).
  const care404 = join(careDir, '404.html');
  const out404 = join(outDir, '404.html');
  if (!existsSync(care404)) {
    problems.push('care input has no 404.html');
  } else if (!existsSync(out404)) {
    problems.push('hosting output has no 404.html');
  } else if (!sameBytes(care404, out404)) {
    problems.push('hosting 404.html differs from the care 404.html');
  }

  // 6. Key routes resolve through the same candidates links use.
  for (const route of KEY_ROUTES) {
    const resolved = resolveCombinedLink('index.html', route);
    const hit = 'candidates' in resolved && resolved.candidates.some((candidate) => isFile(outDir, candidate));
    if (!hit) problems.push(`key route missing: ${route}`);
  }

  // 7. Every local href/src in every page resolves. Same-origin absolute
  // links resolve locally; outbound https is counted, not fetched.
  let linksChecked = 0;
  let outboundCount = 0;
  for (const file of htmlFiles) {
    const text = readFileSync(join(outDir, file), 'utf8');
    for (const match of text.matchAll(/(?:href|src)="([^"]+)"/gu)) {
      const href = match[1];
      if (href === '' || href.startsWith('#')) continue;
      if (href.startsWith('mailto:') || href.startsWith('data:') || href.startsWith('blob:') || href.startsWith('tel:')) continue;
      if (href.startsWith('javascript:')) {
        problems.push(`${file}: script URL: ${href}`);
        continue;
      }
      if (href.startsWith('http://')) {
        problems.push(`${file}: insecure link: ${href}`);
        continue;
      }
      if (href.startsWith(SITE_BASE)) {
        const local = href.slice(SITE_BASE.length) || '/';
        const resolved = resolveCombinedLink(file, local);
        linksChecked += 1;
        if (!('candidates' in resolved) || !resolved.candidates.some((candidate) => isFile(outDir, candidate))) {
          problems.push(`${file}: same-origin link target missing: ${href}`);
        }
        continue;
      }
      if (href.startsWith('https://')) {
        outboundCount += 1;
        continue;
      }
      const resolved = resolveCombinedLink(file, href);
      linksChecked += 1;
      if ('escapes' in resolved) {
        problems.push(`${file}: link escapes output: ${href}`);
      } else if (!resolved.candidates.some((candidate) => isFile(outDir, candidate))) {
        problems.push(`${file}: local link target missing: ${href} -> tried ${resolved.candidates.join(', ')}`);
      }
    }
  }

  if (problems.length > 0) {
    throw new Error(`hosting check failed — ${problems.length} problem(s):\n${problems.map((problem) => `  ${problem}`).join('\n')}`);
  }
  const docsPages = mountedFiles.filter((file) => file.endsWith('.html')).length;
  return {
    outDir, careFiles: rootFiles.length, docsFiles: mountedFiles.length, docsPages, htmlFiles: htmlFiles.length, linksChecked, outboundCount,
  };
}

async function main(args) {
  const outIndex = args.indexOf('--out');
  const outDir = outIndex >= 0 ? args[outIndex + 1] : HOSTING_OUT_DIR;
  if (outIndex >= 0 && !outDir) throw new Error('--out needs a directory');
  const summary = await checkHosting({ outDir });
  process.stdout.write(
    `hosting check ok — ${summary.careFiles} care + ${summary.docsFiles} docs files`
    + ` (${summary.docsPages} docs pages), ${summary.linksChecked} local links, ${summary.outboundCount} outbound\n`,
  );
}

const invokedAsScript = process.argv[1] !== undefined
  && pathToFileURL(process.argv[1]).href === import.meta.url;

if (invokedAsScript) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
