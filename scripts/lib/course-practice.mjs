// Scaffolding logic for course practice projects: lesson layers plus the
// assets each lesson introduced, copied into a fresh output folder.
// Refuses destructive targets before touching the filesystem.
import { copyFileSync, lstatSync, mkdirSync, readdirSync, realpathSync, statSync } from 'node:fs';
import { basename, dirname, join, resolve, sep } from 'node:path';

export const MIN_LESSON = 1;
export const MAX_LESSON = 16;

// Learner, reference, and shipping identities must stay three distinct
// namespaces; the reference checkpoints use the middle one so a generated
// project can never share user:// or an install slot with the other two.
export const LEARNER_APP_NAME = 'Moonlit Course';
export const REFERENCE_APP_NAME = 'Moonlit Course Reference';
export const SHIPPING_APP_NAME = 'Moonlit Beacon';
export const LEARNER_PACKAGE = 'com.example.moonlitcourse';
export const REFERENCE_PACKAGE = 'com.example.moonlitcourse.ref';
export const SHIPPING_PACKAGE = 'com.crossplatformkorea.moonlitbeacon';

const USAGE = `Create a standalone course practice project.

Usage:
  node scripts/course-create.mjs --lesson N [--out DIR]
  node scripts/course-create.mjs --list
  node scripts/course-create.mjs --help

Options:
  --lesson N   End state to build (1-16, required unless --list/--help).
  --out DIR    Target folder. Defaults to builds/course/lesson-NN.
               Must be new or an empty directory. Existing work,
               source folders, and symlinked paths are refused.
  --list       Print the lessons and their introduced assets.
  --help       Print this help.
`;

export function printHelp() {
  process.stdout.write(USAGE);
}

export function parseCreateArgs(argv) {
  const args = { lesson: null, out: null, list: false, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      args.help = true;
    } else if (arg === '--list') {
      args.list = true;
    } else if (arg === '--lesson') {
      const value = argv[i + 1];
      if (value === undefined) throw new Error('--lesson needs a value 1-16.');
      args.lesson = value;
      i += 1;
    } else if (arg === '--out') {
      const value = argv[i + 1];
      if (value === undefined) throw new Error('--out needs a directory.');
      args.out = value;
      i += 1;
    } else {
      throw new Error(`Unknown argument: ${arg}. See --help.`);
    }
  }
  if (!args.help && !args.list) {
    const lesson = Number(args.lesson);
    if (!Number.isInteger(lesson) || lesson < MIN_LESSON || lesson > MAX_LESSON) {
      throw new Error(`--lesson needs an integer ${MIN_LESSON}-${MAX_LESSON}. See --help.`);
    }
    args.lesson = lesson;
  }
  return args;
}

export function lessonDirName(lesson) {
  return `lesson-${String(lesson).padStart(2, '0')}`;
}

function isWithinDirectory(root, candidate) {
  const relative = candidate.startsWith(root + sep) ? candidate.slice(root.length + 1) : null;
  return relative !== null && relative !== '';
}

// Every path the manifest or the layer walk hands us must stay inside its
// root after resolution: no `..` escapes, no absolute entries.
export function safeJoin(root, entry) {
  if (entry === '' || entry.includes('\0')) throw new Error(`Refusing unsafe path: ${entry}`);
  const resolved = resolve(root, entry);
  if (resolved !== root && !isWithinDirectory(root, resolved)) {
    throw new Error(`Refusing path escape: ${entry}`);
  }
  return resolved;
}

function strictlyWithinAny(roots, candidate) {
  return roots.some((root) => candidate !== root && isWithinDirectory(root, candidate));
}

// The target itself must never be a symlink, and no component between the
// target and the repository/working root may be one either. Components above
// those roots (system paths such as /tmp) are the platform's business.
function hasSuspiciousSymlink(target, stopRoots) {
  try {
    if (lstatSync(target).isSymbolicLink()) return true;
  } catch {
    // Absent target: fall through to the parent scan.
  }
  let current = resolve(target, '..');
  while (strictlyWithinAny(stopRoots, current)) {
    try {
      if (lstatSync(current).isSymbolicLink()) return true;
    } catch {
      // Missing components cannot be symlinks; keep climbing.
    }
    current = resolve(current, '..');
  }
  return false;
}

// Canonicalize through the nearest existing ancestor: a NEW target under an
// external symlink (a sibling dir pointing back at repo sources) resolves to
// its real location, so the guarded-root checks below see where bytes would
// actually land. Both sides go through realpath, so legitimate platform
// aliases (/tmp on macOS) compare equal and keep working.
export function canonicalTarget(target) {
  const absolute = resolve(target);
  let ancestor = absolute;
  while (true) {
    try {
      lstatSync(ancestor);
      break;
    } catch {
      const parent = resolve(ancestor, '..');
      if (parent === ancestor) break;
      ancestor = parent;
    }
  }
  const rest = absolute.slice(ancestor.length);
  return join(realpathSync(ancestor), rest);
}

function canonicalRoot(root) {
  try {
    return realpathSync(root);
  } catch {
    return resolve(root);
  }
}

function refuseGuardedTarget(canonical, canonicalRepo, display) {
  if (canonical === canonicalRepo) {
    throw new Error('Refusing the repository root as output.');
  }
  for (const guarded of ['examples', 'apps', 'scripts', 'notes', '.git', '.github']) {
    const root = join(canonicalRepo, guarded);
    if (canonical === root || isWithinDirectory(root, canonical)) {
      throw new Error(`Refusing output inside ${guarded}/ (source folder): ${display}`);
    }
  }
}

// A source root must resolve where the repository says it is: per-file
// containment compares against the canonical root itself, so a symlinked
// src or src/assets would otherwise bless its own external tree. Both
// sides go through realpath, so legitimate platform aliases above the
// repository (/tmp on macOS) compare equal. Missing roots keep their
// specific missing-layer/asset errors downstream.
function assertSourceBoundary(path, expectedCanonical, label) {
  try {
    lstatSync(path);
  } catch {
    return;
  }
  let canonical;
  try {
    canonical = realpathSync(path);
  } catch {
    throw new Error(`Refusing unreadable source root (${label}): ${path}`);
  }
  if (canonical !== expectedCanonical) {
    throw new Error(`Refusing source root outside the repository (${label}): ${path}`);
  }
}

export function planCreation({ repoRoot, lesson, out, manifest }) {
  const sources = join(repoRoot, 'examples', 'course', 'src');
  const assetsRoot = join(sources, 'assets');
  const canonicalRepo = canonicalRoot(repoRoot);
  const expectedSources = join(canonicalRepo, 'examples', 'course', 'src');
  assertSourceBoundary(sources, expectedSources, 'lesson sources');
  assertSourceBoundary(assetsRoot, join(expectedSources, 'assets'), 'asset sources');
  const fallback = join(repoRoot, 'builds', 'course', lessonDirName(lesson));
  const target = resolve(repoRoot, out ?? fallback);
  refuseGuardedTarget(canonicalTarget(target), canonicalRepo, target);
  if (hasSuspiciousSymlink(target, [repoRoot, process.cwd()])) {
    throw new Error(`Refusing symlinked output path: ${target}`);
  }
  let existing = null;
  try {
    existing = statSync(target);
  } catch {
    existing = null;
  }
  if (existing !== null) {
    if (!existing.isDirectory()) throw new Error(`Refusing existing file as output: ${target}`);
    if (readdirSync(target).length > 0) {
      throw new Error(`Refusing non-empty directory (existing learner work): ${target}`);
    }
  }
  const steps = [];
  for (let n = MIN_LESSON; n <= lesson; n += 1) {
    const layer = join(sources, lessonDirName(n));
    try {
      if (lstatSync(layer).isSymbolicLink()) {
        throw new Error(`Refusing symlinked lesson layer: ${layer}`);
      }
    } catch (error) {
      if (error.code === 'ENOENT') throw new Error(`Missing lesson layer: ${layer}`);
      throw error;
    }
    steps.push({ kind: 'layer', from: layer, root: sources, lesson: n });
    const entry = manifest.lessons[String(n)];
    if (!entry) throw new Error(`Missing manifest entry for lesson ${n}.`);
    for (const asset of entry.assets) {
      const from = safeJoin(assetsRoot, asset);
      const destination = manifest.assetDestinations[asset];
      if (!destination) throw new Error(`Missing destination for asset: ${asset}`);
      steps.push({ kind: 'asset', from, to: safeJoin(target, destination), root: assetsRoot, lesson: n });
    }
  }
  return { target, steps };
}

// Generated caches, version control, environment files, and signing material
// are never packaged: opening a source layer in the editor must not smuggle
// its .godot/ cache or a stray keystore into a learner's output later.
const EXCLUDED_DIR_NAMES = new Set(['.godot', '.git']);
const EXCLUDED_FILE_NAMES = new Set(['.env', 'export_credentials.cfg']);
const KEY_FILE_PATTERN = /\.(keystore|jks|key|p12|pfx|mobileprovision|p8|pem)$/i;

export function isExcludedSource(name) {
  if (EXCLUDED_FILE_NAMES.has(name)) return true;
  if (name === '.env' || name.startsWith('.env.')) return true;
  return KEY_FILE_PATTERN.test(name);
}

export function collectLayerFiles(root) {
  const found = [];
  const stack = [root];
  while (stack.length > 0) {
    const current = stack.pop();
    for (const entry of readdirSync(current, { withFileTypes: true }).sort((a, b) =>
      (a.name < b.name ? -1 : 1))) {
      const full = join(current, entry.name);
      if (entry.isSymbolicLink()) throw new Error(`Refusing symlinked source: ${full}`);
      if (entry.isDirectory()) {
        if (!EXCLUDED_DIR_NAMES.has(entry.name)) stack.push(full);
      } else if (entry.isFile()) {
        if (!isExcludedSource(entry.name)) found.push(full);
      }
    }
  }
  return found.sort();
}

// A source path is only safe when its fully resolved location lands inside
// its root: lstat sees the final component, so a symlinked parent (assets/art
// -> an external folder) would otherwise smuggle outside bytes in through a
// regular-looking file. Both sides go through realpath, so legitimate
// platform aliases above the roots (/tmp on macOS) compare equal.
function assertContained(root, path, label) {
  let canonicalRoot;
  try {
    canonicalRoot = realpathSync(root);
  } catch {
    throw new Error(`Missing source root for ${label}: ${root}`);
  }
  let canonical;
  try {
    canonical = realpathSync(path);
  } catch {
    throw new Error(`Missing source for ${label}: ${path}`);
  }
  if (canonical !== canonicalRoot && !isWithinDirectory(canonicalRoot, canonical)) {
    throw new Error(`Refusing source outside its root (${label}): ${path}`);
  }
}

// Validate every source (symlinks, escapes, exclusions, containment) before
// the output directory is created, so a refusal leaves no partial project
// behind.
function collectCopies(plan) {
  const copies = [];
  for (const step of plan.steps) {
    if (step.kind === 'layer') {
      if (step.root !== undefined) assertContained(step.root, step.from, 'lesson layer');
      for (const from of collectLayerFiles(step.from)) {
        assertContained(step.from, from, 'layer file');
        const relative = from.slice(step.from.length + 1);
        copies.push({ from, to: safeJoin(plan.target, relative) });
      }
    } else {
      if (!lstatSync(step.from).isFile()) {
        throw new Error(`Refusing non-file asset source: ${step.from}`);
      }
      if (isExcludedSource(basename(step.from))) {
        throw new Error(`Refusing excluded asset source: ${step.from}`);
      }
      if (step.root !== undefined) assertContained(step.root, step.from, 'asset');
      copies.push({ from: step.from, to: step.to });
    }
  }
  return copies;
}

// Copies layers 1..N over each other, then the selected assets. Deterministic:
// sorted order, fixed contents, no caches or generated files involved.
export function executePlan(plan) {
  const copies = collectCopies(plan);
  mkdirSync(plan.target, { recursive: true });
  if (lstatSync(plan.target).isSymbolicLink()) {
    throw new Error(`Refusing symlinked output path: ${plan.target}`);
  }
  let files = 0;
  for (const { from, to } of copies) {
    mkdirSync(dirname(to), { recursive: true });
    copyFileSync(from, to);
    files += 1;
  }
  return { target: plan.target, files };
}
