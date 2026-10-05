import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';

import {
  applyPatch,
  changedFiles,
  checkPatch,
  classifyChange,
  createSnapshot,
  diffStat,
  isCopied,
  isInside,
  isSecretPath,
  writePatch,
} from './muse-workspace.mjs';

const git = (cwd, ...args) => execFileSync('git', args, { cwd, encoding: 'utf8' });

function put(root, path, text) {
  mkdirSync(dirname(join(root, path)), { recursive: true });
  writeFileSync(join(root, path), text);
}

/** A small stand-in for the real checkout: tracked and untracked files, ignored ones, and every kind of secret. */
function makeCheckout(t) {
  const root = mkdtempSync(join(tmpdir(), 'muse-workspace-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  git(root, 'init', '-q', '-b', 'main');
  git(root, 'config', 'user.email', 'test@example.com');
  git(root, 'config', 'user.name', 'test');
  put(root, '.gitignore', 'ignored.txt\nbuilds/\n.godot/\nnode_modules/\n.env\n.env.*\n!.env.example\n*.p8\n');
  put(root, 'apps/game/scripts/player.gd', 'extends Node\n');
  put(root, 'apps/game/scripts/gone.gd', 'extends Node\n');
  put(root, 'AGENTS.md', '# rules\n');
  put(root, '.env.example', 'NAME=\n');
  git(root, 'add', '-A');
  git(root, 'commit', '-q', '-m', 'init');
  // After the commit: an untracked file, a tracked one deleted, ignored files and secrets.
  put(root, 'apps/game/scripts/new_untracked.gd', 'extends Node\n');
  rmSync(join(root, 'apps/game/scripts/gone.gd'));
  put(root, 'ignored.txt', 'x');
  put(root, '.env', 'SECRET=1\n');
  put(root, 'keys/AuthKey.p8', 'PRIVATE');
  put(root, 'apps/game/.godot/imported/a.ctex', 'cache');
  put(root, 'apps/game/.godot/export_credentials.cfg', 'PASSWORD');
  put(root, 'apps/game/.godot/editor/x.cfg', 'editor');
  put(root, 'builds/out.txt', 'out');
  put(root, '.playwright-mcp/shot.png', 'png');
  put(root, '.claude/settings.local.json', '{"permissions":{}}');
  return root;
}

test('what is a secret, and what is copied', () => {
  for (const path of ['.env', '.env.local', 'apps/x/.env.production', 'keys/AuthKey_ABC.p8', 'a/b.keystore', 'my.jks',
    'apps/game/.godot/export_credentials.cfg', 'svc-service-account-1.json', 'apps/game/iapkit.cfg', 'apps/game/firebase.cfg',
    '.claude/settings.local.json', '.secrets/x']) {
    assert.ok(isSecretPath(path), `${path} should be a secret`);
    assert.ok(!isCopied(path), `${path} should not be copied`);
  }
  for (const path of ['.env.example', 'apps/game/scripts/a.gd', 'notes/secrets-policy.md']) {
    assert.ok(!isSecretPath(path), `${path} is not a secret`);
  }
  for (const path of ['builds/x', '.godot/x', 'apps/docs/node_modules/x', '.playwright-mcp/a', '_downloads/z', '.git/config']) {
    assert.ok(!isCopied(path), `${path} should not be copied`);
  }
});

test('the copy has the publishable files and the import cache, and no secret or remote', (t) => {
  const root = makeCheckout(t);
  const destination = join(mkdtempSync(join(tmpdir(), 'muse-workspace-dest-')), 'work');
  t.after(() => rmSync(join(destination, '..'), { recursive: true, force: true }));
  const { baseline, files } = createSnapshot({ repoRoot: root, destination, withDependencies: false });

  for (const path of ['apps/game/scripts/player.gd', 'apps/game/scripts/new_untracked.gd', 'AGENTS.md', '.env.example',
    'apps/game/.godot/imported/a.ctex']) {
    assert.ok(existsSync(join(destination, path)), `${path} should be in the copy`);
  }
  for (const path of ['.env', 'keys/AuthKey.p8', 'apps/game/.godot/export_credentials.cfg', 'apps/game/.godot/editor/x.cfg',
    'builds/out.txt', '.playwright-mcp/shot.png', '.claude/settings.local.json', 'ignored.txt', 'apps/game/scripts/gone.gd']) {
    assert.ok(!existsSync(join(destination, path)), `${path} must not be in the copy`);
  }
  assert.ok(files >= 4);
  assert.equal(git(destination, 'remote').trim(), '', 'the copy has no remote');
  assert.equal(git(destination, 'rev-list', '--count', 'HEAD').trim(), '1');
  assert.equal(git(destination, 'rev-parse', 'HEAD').trim(), baseline);
  assert.equal(git(destination, 'rev-parse', 'baseline').trim(), baseline, 'the tag the standing orders name exists');
  assert.equal(git(destination, 'status', '--porcelain').trim(), '', 'a fresh copy has no changes, and .muse is not one');
  // The credentials never reach the copy's object store either.
  assert.equal(git(destination, 'log', '--all', '--format=%H', '-S', 'PASSWORD').trim(), '');
});

test('the change is a patch that applies to the real tree, and comes out again', (t) => {
  const root = makeCheckout(t);
  const destination = join(mkdtempSync(join(tmpdir(), 'muse-workspace-dest-')), 'work');
  t.after(() => rmSync(join(destination, '..'), { recursive: true, force: true }));
  const { baseline } = createSnapshot({ repoRoot: root, destination, withDependencies: false });

  writeFileSync(join(destination, 'apps/game/scripts/player.gd'), 'extends Node\nvar changed := true\n');
  put(destination, 'apps/game/scripts/added.gd', 'extends Node\n');
  writeFileSync(join(destination, 'apps/game/scripts/bin.png'), Buffer.from([0, 1, 2, 3, 255, 0, 9]));
  rmSync(join(destination, 'apps/game/scripts/new_untracked.gd'));
  put(destination, 'IMPLEMENTER_REPORT.md', 'not part of the change');
  put(destination, '.muse/notes.md', 'not part of the change either');

  const changes = changedFiles(destination, baseline);
  assert.equal(git(destination, 'diff', '--cached', '--name-only').trim(), '', 'listing the changes stages nothing');
  assert.match(diffStat(destination, baseline), /\+2 +-0 +apps\/game\/scripts\/added\.gd|\+1 +-0 +apps\/game\/scripts\/added\.gd/);
  assert.equal(git(destination, 'diff', '--cached', '--name-only').trim(), '', 'so does the stat');
  const byPath = Object.fromEntries(changes.map((change) => [change.path, change.status]));
  assert.deepEqual(byPath, {
    'apps/game/scripts/added.gd': 'A',
    'apps/game/scripts/bin.png': 'A',
    'apps/game/scripts/new_untracked.gd': 'D',
    'apps/game/scripts/player.gd': 'M',
  });

  const patch = join(destination, '..', 'changes.patch');
  writePatch(destination, baseline, patch);
  const check = checkPatch(root, patch);
  assert.equal(check.ok, true, check.message);
  assert.equal(applyPatch(root, patch).ok, true);
  assert.equal(readFileSync(join(root, 'apps/game/scripts/player.gd'), 'utf8'), 'extends Node\nvar changed := true\n');
  assert.ok(existsSync(join(root, 'apps/game/scripts/added.gd')));
  assert.deepEqual([...readFileSync(join(root, 'apps/game/scripts/bin.png'))], [0, 1, 2, 3, 255, 0, 9]);
  assert.ok(!existsSync(join(root, 'apps/game/scripts/new_untracked.gd')));

  // Taking it back leaves the tree as it was.
  execFileSync('git', ['apply', '-R', '--binary', patch], { cwd: root });
  assert.equal(readFileSync(join(root, 'apps/game/scripts/player.gd'), 'utf8'), 'extends Node\n');
  assert.ok(!existsSync(join(root, 'apps/game/scripts/added.gd')));
  assert.ok(existsSync(join(root, 'apps/game/scripts/new_untracked.gd')));
});

test('a real tree that moved on since the copy was made refuses the patch', (t) => {
  const root = makeCheckout(t);
  const destination = join(mkdtempSync(join(tmpdir(), 'muse-workspace-dest-')), 'work');
  t.after(() => rmSync(join(destination, '..'), { recursive: true, force: true }));
  const { baseline } = createSnapshot({ repoRoot: root, destination, withDependencies: false });
  writeFileSync(join(destination, 'apps/game/scripts/player.gd'), 'extends Node\nvar theirs := 1\n');
  const patch = join(destination, '..', 'changes.patch');
  writePatch(destination, baseline, patch);
  writeFileSync(join(root, 'apps/game/scripts/player.gd'), 'extends Node2D\nvar mine := 2\n');
  const check = checkPatch(root, patch);
  assert.equal(check.ok, false);
  assert.match(check.message, /player\.gd/);
});

test('the paths an implementer may not change are protected, the ones to read twice are watched', () => {
  const protectedPaths = ['AGENTS.md', '.claude/commands/muse.md', '.agents/skills/x/SKILL.md', '.github/workflows/ci.yml',
    '.gitignore', 'scripts/muse.mjs', 'scripts/muse.config.json',
    'scripts/lib/muse-run.mjs', 'notes/workflow/muse/standing-orders.md', 'apps/game/export_presets.cfg', 'firestore.rules',
    '.env', 'x/AuthKey.p8'];
  for (const path of protectedPaths) assert.equal(classifyChange(path).level, 'protected', path);
  for (const path of ['package.json', 'pnpm-lock.yaml', 'apps/game/project.godot', 'stores/google-play/x.txt', 'notes/release/checklist.md']) {
    assert.equal(classifyChange(path).level, 'watched', path);
  }
  for (const path of ['apps/game/scripts/actors/spirit.gd', 'apps/docs/docs/game.md', 'notes/plans/3-0-0-build-log.md', 'README.md']) {
    assert.equal(classifyChange(path).level, 'free', path);
  }
});

test('deleting is only allowed strictly inside the runs folder', (t) => {
  const parent = mkdtempSync(join(tmpdir(), 'muse-inside-test-'));
  t.after(() => rmSync(parent, { recursive: true, force: true }));
  mkdirSync(join(parent, 'a', 'b'), { recursive: true });
  assert.equal(isInside(parent, join(parent, 'a')), true);
  assert.equal(isInside(parent, join(parent, 'a', 'b')), true);
  assert.equal(isInside(parent, parent), false);
  assert.equal(isInside(parent, join(parent, '..')), false);
  assert.equal(isInside(parent, join(parent, '..', 'elsewhere')), false);
});
