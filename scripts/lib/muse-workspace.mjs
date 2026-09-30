// The implementer never works in the real checkout. It gets a copy: every file the repo would publish
// (tracked, or untracked and not ignored) plus the Godot import cache, and **nothing that is a secret**.
// The copy is its own git repository with one `baseline` commit and no remote, so it cannot push, and
// whatever it changes is exactly `git diff baseline`. The director reads that diff, tests it, and only
// then applies it to the real tree (`accept`). Nothing the implementer does lands until then.
//
// Why a copy and not a git worktree: the working tree holds a great deal of uncommitted work that a
// worktree of HEAD would not have, and a worktree shares the real repository's remotes and hooks.

import { execFileSync, spawnSync } from 'node:child_process';
import {
  constants,
  copyFileSync,
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { basename, dirname, join, relative, resolve, sep } from 'node:path';

/** Where the implementer leaves its message to the director. The CLI keeps a `.muse/` folder of its own in a
 * workspace and refuses writes there in a headless run, so the report is a plain file at the root of the copy. It is
 * excluded from git, so it never becomes part of the change. */
export const REPORT_FILE = 'IMPLEMENTER_REPORT.md';

/** Godot's import cache: needed so headless runs need not re-import every texture. `export_credentials.cfg`
 * (the signing password) lives next to it and is never copied. */
const GODOT_CACHE = ['imported', 'shader_cache', 'global_script_class_cache.cfg', 'uid_cache.bin', 'scene_groups_cache.cfg', '.gdignore'];

/** Directories whose contents are cloned as a whole when they exist (no secrets live in them). */
const CLONED_DIRECTORIES = ['node_modules', 'apps/docs/node_modules'];

const SECRET_EXTENSIONS = /\.(p8|p12|jks|keystore|pem|key|mobileprovision)$/i;
/** Directory names left out wherever they appear in a path. */
const NEVER_COPIED_SEGMENTS = new Set(['.git', '.godot', 'node_modules', '.playwright-mcp', '.secrets', '.pnpm-store']);
/** Folders left out when they are at the top of the repo, and what else is left out by prefix. */
const NEVER_COPIED_TOP = ['builds', '_downloads', '_asset_sources', '.claude/worktrees'];

/** A path that must not leave the real checkout, whoever asks. */
export function isSecretPath(path) {
  const name = path.split('/').pop();
  if (name === '.env' || (name.startsWith('.env.') && name !== '.env.example')) return true;
  if (SECRET_EXTENSIONS.test(name)) return true;
  if (/service-account.*\.json$/i.test(name)) return true;
  if (name === 'iapkit.cfg' || name === 'firebase.cfg') return true;
  if (path.includes('export_credentials')) return true;
  if (path === '.claude/allow-pr' || path === '.claude/settings.local.json') return true;
  return path.split('/').includes('.secrets');
}

export function isCopied(path) {
  if (isSecretPath(path)) return false;
  if (path.split('/').some((segment) => NEVER_COPIED_SEGMENTS.has(segment))) return false;
  return !NEVER_COPIED_TOP.some((directory) => path === directory || path.startsWith(`${directory}/`));
}

/** Files of the working tree that a commit could publish: tracked, or untracked and not ignored. */
export function listCopiedFiles(repoRoot) {
  const output = execFileSync('git', ['ls-files', '-co', '--exclude-standard', '-z'], {
    cwd: repoRoot,
    maxBuffer: 256 * 1024 * 1024,
  });
  return output
    .toString('utf8')
    .split('\0')
    .filter((path) => path !== '' && isCopied(path))
    .filter((path) => {
      try {
        lstatSync(join(repoRoot, path));
        return true;
      } catch {
        return false; // tracked but deleted in the working tree
      }
    });
}

function copyOne(source, target) {
  mkdirSync(dirname(target), { recursive: true });
  const info = lstatSync(source);
  if (info.isSymbolicLink()) {
    symlinkSync(readlinkSync(source), target);
  } else if (info.isFile()) {
    copyFileSync(source, target, constants.COPYFILE_FICLONE);
  }
}

function cloneDirectory(source, target) {
  mkdirSync(dirname(target), { recursive: true });
  const attempts = process.platform === 'darwin'
    ? [['-Rc', source, target], ['-R', source, target]]
    : [['-R', '--reflink=auto', source, target], ['-R', source, target]];
  for (const args of attempts) {
    if (spawnSync('cp', args, { stdio: 'ignore' }).status === 0) return true;
  }
  return false;
}

const git = (cwd, args, options = {}) => execFileSync('git', args, {
  cwd,
  encoding: 'utf8',
  maxBuffer: 256 * 1024 * 1024,
  ...options,
});

/**
 * Build the implementer's workspace at `destination` (which must not exist) and return `{ baseline, files }`.
 * `withDependencies: false` skips the cloned node_modules, for tests.
 */
export function createSnapshot({ repoRoot, destination, withDependencies = true }) {
  if (existsSync(destination)) throw new Error(`${destination} already exists`);
  const files = listCopiedFiles(repoRoot);
  for (const path of files) copyOne(join(repoRoot, path), join(destination, path));

  // Generated translation tables are ignored by git but the game loads them; the import would only recreate them.
  const translations = 'apps/game/localization';
  for (const language of ['en', 'ja', 'ko', 'zh_CN', 'zh_TW']) {
    const path = `${translations}/moonlit.${language}.translation`;
    if (existsSync(join(repoRoot, path))) copyOne(join(repoRoot, path), join(destination, path));
  }

  const cache = join(repoRoot, 'apps/game/.godot');
  for (const name of GODOT_CACHE) {
    const source = join(cache, name);
    if (!existsSync(source)) continue;
    const target = join(destination, 'apps/game/.godot', name);
    mkdirSync(dirname(target), { recursive: true });
    cpSync(source, target, { recursive: true, mode: constants.COPYFILE_FICLONE });
  }

  if (withDependencies) {
    for (const directory of CLONED_DIRECTORIES) {
      if (existsSync(join(repoRoot, directory))) cloneDirectory(join(repoRoot, directory), join(destination, directory));
    }
  }

  git(destination, ['init', '-q', '-b', 'snapshot']);
  for (const [key, value] of [
    ['user.name', 'director-baseline'],
    ['user.email', 'baseline@localhost'],
    ['commit.gpgsign', 'false'],
    ['core.autocrlf', 'false'],
    ['core.hooksPath', '/dev/null'],
  ]) git(destination, ['config', key, value]);
  writeFileSync(join(destination, '.git', 'info', 'exclude'), `${REPORT_FILE}\n.muse/\n`);
  git(destination, ['add', '-A']);
  git(destination, ['commit', '-q', '-m', 'baseline', '--no-verify', '--allow-empty']);
  const baseline = git(destination, ['rev-parse', 'HEAD']).trim();
  // The standing orders say `git diff baseline`: make that a name that exists.
  git(destination, ['tag', 'baseline', baseline]);
  return { baseline, files: files.length };
}

/** Paths the implementer may not change without the director saying so: the rules it works under, the guard that
 * protects the user, secrets, the version lock and what a deploy reads. */
const PROTECTED = [
  [/^(AGENTS|CLAUDE)\.md$/, 'the rules the implementer works under'],
  [/^\.claude\//, 'agent commands, skills and hooks'],
  [/^\.agents\//, 'the skill mirror'],
  [/^\.github\//, 'CI'],
  [/^\.gitignore$/, 'what stays out of the repo'],
  [/^scripts\/guard-pull-request\.mjs$/, 'the pull-request guard'],
  [/^scripts\/lib\/pr-guard/, 'the pull-request guard'],
  [/^scripts\/muse/, 'the implementer runner'],
  [/^scripts\/lib\/muse-/, 'the implementer runner'],
  [/^notes\/workflow\/muse\//, 'the standing orders and briefs'],
  [/^apps\/game\/export_presets\.cfg$/, 'the version and build numbers are locked'],
  [/^(firestore\.rules|firestore\.indexes\.json|firebase\.json)$/, 'what a deploy reads'],
];

/** Paths that are allowed but that the director reads twice. */
const WATCHED = [
  [/^package\.json$/, 'scripts and dependencies'],
  [/^pnpm-lock\.yaml$/, 'dependencies'],
  [/^apps\/game\/project\.godot$/, 'locked engine values'],
  [/^stores\//, 'store listing files'],
  [/^notes\/release\//, 'release records'],
  [/^apps\/game\/tools\/custom_asset_contracts\.json$/, 'asset contracts'],
  [/^apps\/docs\/docs\/assets\/manifest\.md$/, 'the asset manifest'],
];

export function classifyChange(path) {
  if (isSecretPath(path)) return { level: 'protected', why: 'a secret' };
  for (const [pattern, why] of PROTECTED) if (pattern.test(path)) return { level: 'protected', why };
  for (const [pattern, why] of WATCHED) if (pattern.test(path)) return { level: 'watched', why };
  return { level: 'free', why: '' };
}

const gitRead = (cwd, args) => git(cwd, ['--no-optional-locks', ...args]);

/**
 * Everything the implementer changed against the baseline: tracked files that differ, plus files that are new.
 * It only reads (no staging, no index write), so it is safe to ask while the implementer is still working in the
 * copy and running its own git commands.
 */
export function changedFiles(work, baseline) {
  const changes = new Map();
  const tracked = gitRead(work, ['diff', '--name-status', '--no-renames', '-z', baseline]).split('\0').filter((part) => part !== '');
  for (let index = 0; index + 1 < tracked.length; index += 2) changes.set(tracked[index + 1], tracked[index]);
  const fresh = gitRead(work, ['ls-files', '--others', '--exclude-standard', '-z']).split('\0').filter((path) => path !== '');
  for (const path of fresh) if (!changes.has(path)) changes.set(path, 'A');
  return [...changes]
    .map(([path, status]) => ({ status, path }))
    .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}

function countLines(file) {
  try {
    if (lstatSync(file).size > 5 * 1024 * 1024) return 'big';
    const bytes = readFileSync(file);
    if (bytes.includes(0)) return 'bin';
    let lines = 0;
    for (const byte of bytes) if (byte === 10) lines += 1;
    return bytes.length > 0 && bytes[bytes.length - 1] !== 10 ? lines + 1 : lines;
  } catch {
    return 'bin';
  }
}

/** `+added -deleted  path` for every change, read-only like `changedFiles`. */
export function diffStat(work, baseline) {
  const rows = [];
  for (const line of gitRead(work, ['diff', '--numstat', '--no-renames', baseline]).split('\n')) {
    if (line === '') continue;
    const [added, deleted, ...path] = line.split('\t');
    rows.push({ path: path.join('\t'), added, deleted });
  }
  const known = new Set(rows.map((row) => row.path));
  for (const { path } of changedFiles(work, baseline)) {
    if (!known.has(path)) rows.push({ path, added: countLines(join(work, path)), deleted: 0 });
  }
  rows.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  const lines = rows.map((row) => `${String(`+${row.added}`).padStart(8)} ${String(`-${row.deleted}`).padStart(7)}  ${row.path}`);
  return `${lines.join('\n')}${lines.length > 0 ? '\n' : ''}${rows.length} file(s)\n`;
}

/** The full change as text (`diff --cached` after staging), for a reader. Stages the copy, so not while it is in use. */
export function fullDiff(work, baseline) {
  git(work, ['add', '-A']);
  return git(work, ['diff', '--cached', '--no-renames', baseline]);
}

/** Write the change as a binary-safe patch to `patchFile`. Stages the copy, so only after the implementer has finished. */
export function writePatch(work, baseline, patchFile) {
  git(work, ['add', '-A']);
  git(work, ['diff', '--cached', '--binary', '--full-index', '--no-renames', `--output=${patchFile}`, baseline]);
}

/** Does the patch apply to the real tree, exactly as it is now? Returns `{ ok, message }`. */
export function checkPatch(repoRoot, patchFile) {
  const run = spawnSync('git', ['apply', '--check', '--binary', patchFile], { cwd: repoRoot, encoding: 'utf8' });
  return { ok: run.status === 0, message: `${run.stdout ?? ''}${run.stderr ?? ''}`.trim() };
}

export function applyPatch(repoRoot, patchFile) {
  const run = spawnSync('git', ['apply', '--binary', patchFile], { cwd: repoRoot, encoding: 'utf8' });
  return { ok: run.status === 0, message: `${run.stdout ?? ''}${run.stderr ?? ''}`.trim() };
}

/** The real path of `path`, or of its nearest existing ancestor with the rest put back (a deleted folder still resolves). */
function realish(path) {
  const absolute = resolve(path);
  let existing = absolute;
  const tail = [];
  while (!existsSync(existing) && dirname(existing) !== existing) {
    tail.unshift(basename(existing));
    existing = dirname(existing);
  }
  return join(realpathSync(existing), ...tail);
}

/** `child` is inside `parent` and is not `parent` itself: the guard before anything is deleted. */
export function isInside(parent, child) {
  const relation = relative(realish(parent), realish(child));
  return relation !== '' && relation !== '.' && !relation.startsWith('..') && !relation.startsWith(sep);
}
