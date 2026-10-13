// Safety and determinism tests for course practice scaffolding. Writes go
// to throwaway temp dirs only; the real examples/ tree is read, never written.
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  LEARNER_APP_NAME,
  LEARNER_PACKAGE,
  REFERENCE_APP_NAME,
  REFERENCE_PACKAGE,
  SHIPPING_APP_NAME,
  SHIPPING_PACKAGE,
  collectLayerFiles,
  executePlan,
  lessonDirName,
  parseCreateArgs,
  planCreation,
  safeJoin,
} from './course-practice.mjs';

const REPOSITORY = dirname(dirname(dirname(fileURLToPath(import.meta.url))));

function loadManifest() {
  return JSON.parse(
    readFileSync(join(REPOSITORY, 'examples', 'course', 'src', 'manifest.json'), 'utf8'),
  );
}

function makeTemp() {
  return mkdtempSync(join(tmpdir(), 'course-practice-'));
}

test('parses scaffold arguments', () => {
  assert.deepEqual(parseCreateArgs(['--lesson', '3']), { lesson: 3, out: null, list: false, help: false });
  assert.deepEqual(parseCreateArgs(['--lesson', '8', '--out', 'builds/x']), {
    lesson: 8, out: 'builds/x', list: false, help: false,
  });
  assert.equal(parseCreateArgs(['--list']).list, true);
  assert.equal(parseCreateArgs(['--help']).help, true);
  assert.throws(() => parseCreateArgs([]), /--lesson needs an integer/);
  assert.equal(parseCreateArgs(['--lesson', '16']).lesson, 16);
  assert.throws(() => parseCreateArgs(['--lesson', '17']), /--lesson needs an integer/);
  assert.throws(() => parseCreateArgs(['--lesson', 'x']), /--lesson needs an integer/);
  assert.throws(() => parseCreateArgs(['--lesson', '2', '--bogus']), /Unknown argument/);
  assert.throws(() => parseCreateArgs(['--lesson']), /needs a value/);
});

test('builds lesson directory names', () => {
  assert.equal(lessonDirName(1), 'lesson-01');
  assert.equal(lessonDirName(8), 'lesson-08');
});

test('safeJoin refuses escapes', () => {
  const root = makeTemp();
  try {
    assert.equal(safeJoin(root, 'a/b.txt'), join(root, 'a', 'b.txt'));
    assert.throws(() => safeJoin(root, '../escape.txt'), /Refusing path escape/);
    assert.throws(() => safeJoin(root, '/abs.txt'), /Refusing path escape/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('plan refuses destructive and source targets', () => {
  const manifest = loadManifest();
  const root = makeTemp();
  try {
    const busy = join(root, 'busy');
    mkdirSync(busy);
    writeFileSync(join(busy, 'work.txt'), 'learner work');
    assert.throws(
      () => planCreation({ repoRoot: REPOSITORY, lesson: 1, out: busy, manifest }),
      /non-empty directory/,
    );
    const file = join(root, 'file.txt');
    writeFileSync(file, 'x');
    assert.throws(
      () => planCreation({ repoRoot: REPOSITORY, lesson: 1, out: file, manifest }),
      /existing file/,
    );
    assert.throws(
      () => planCreation({ repoRoot: REPOSITORY, lesson: 1, out: 'examples/course/src/x', manifest }),
      /source folder/,
    );
    assert.throws(
      () => planCreation({ repoRoot: REPOSITORY, lesson: 1, out: 'apps/game/x', manifest }),
      /source folder/,
    );
    const link = join(root, 'link');
    symlinkSync(root, link);
    assert.throws(
      () => planCreation({ repoRoot: REPOSITORY, lesson: 1, out: link, manifest }),
      /symlinked output/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('plan refuses a symlinked parent below the repository', () => {
  const manifest = loadManifest();
  const root = makeTemp();
  // outside/out/… is NOT under the repo: only the target itself is checked.
  const outside = join(root, 'outside');
  mkdirSync(outside, { recursive: true });
  const plan = planCreation({ repoRoot: REPOSITORY, lesson: 1, out: outside, manifest });
  assert.equal(plan.target, outside);
  rmSync(root, { recursive: true, force: true });
});

test('scaffolds lesson 1 with exactly its introduced files', () => {
  const manifest = loadManifest();
  const root = makeTemp();
  try {
    const out = join(root, 'lesson-01');
    const plan = planCreation({ repoRoot: REPOSITORY, lesson: 1, out, manifest });
    const result = executePlan(plan);
    assert.equal(result.target, out);
    const walked = [];
    const stack = [out];
    while (stack.length > 0) {
      const current = stack.pop();
      for (const entry of readdirSync(current, { withFileTypes: true })) {
        const full = join(current, entry.name);
        if (entry.isDirectory()) stack.push(full);
        else walked.push(full.slice(out.length + 1));
      }
    }
    walked.sort();
    assert.ok(walked.includes('project.godot'), 'project file');
    assert.ok(walked.includes(join('scenes', 'menus', 'title_menu.tscn')), 'title scene');
    assert.ok(
      walked.includes(join('assets', 'third_party', 'ninja_adventure', 'tilesets', 'tileset_camp.png')),
      'camp tileset',
    );
    assert.ok(
      !walked.some((name) => name.endsWith('.import') || name.split('/').includes('.godot')),
      'no caches or import sidecars',
    );
    assert.ok(
      !walked.some((name) => name.includes('ninja_walk') || name.includes('arena_theme')),
      'no later-lesson assets',
    );
    assert.ok(statSync(join(out, 'project.godot')).size > 100, 'project file has content');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('plan refuses a NEW target under an external symlink to sources', () => {
  // Regression: hasSuspiciousSymlink only climbs inside repo/process roots, so
  // root/ext/link -> root/repo/apps used to pass. Canonical resolution sees
  // through the alias. Everything lives in a fake temp repo; real sources
  // are never written.
  const root = makeTemp();
  try {
    const repo = join(root, 'repo');
    const layer = join(repo, 'examples', 'course', 'src', 'lesson-01');
    mkdirSync(layer, { recursive: true });
    writeFileSync(join(layer, 'project.godot'), 'config_version=5\n');
    mkdirSync(join(repo, 'apps'), { recursive: true });
    const manifest = { lessons: { 1: { assets: [] } }, assetDestinations: {} };
    const ext = join(root, 'ext');
    mkdirSync(ext, { recursive: true });
    symlinkSync(join(repo, 'apps'), join(ext, 'link'));
    assert.throws(
      () => planCreation({ repoRoot: repo, lesson: 1, out: join(ext, 'link', 'evil'), manifest }),
      /source folder/,
    );
    // A plain sibling directory outside the repo stays allowed.
    const plain = join(ext, 'plain');
    const plan = planCreation({ repoRoot: repo, lesson: 1, out: plain, manifest });
    assert.equal(plan.target, plain);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('layer collection excludes caches, control, env, and key material', () => {
  const root = makeTemp();
  try {
    const layer = join(root, 'layer');
    mkdirSync(join(layer, '.godot', 'imported'), { recursive: true });
    writeFileSync(join(layer, '.godot', 'export_credentials.cfg'), 'SYNTHETIC-NOT-A-SECRET');
    mkdirSync(join(layer, '.git', 'objects'), { recursive: true });
    writeFileSync(join(layer, '.git', 'HEAD'), 'ref: refs/heads/main');
    writeFileSync(join(layer, '.env'), 'KEY=SYNTHETIC');
    writeFileSync(join(layer, '.env.local'), 'KEY=SYNTHETIC');
    writeFileSync(join(layer, 'game.keystore'), 'SYNTHETIC');
    writeFileSync(join(layer, 'signing.jks'), 'SYNTHETIC');
    writeFileSync(join(layer, 'synthetic-signing.p8'), 'SYNTHETIC-NOT-A-KEY');
    writeFileSync(join(layer, 'synthetic-certificate.pem'), 'SYNTHETIC-NOT-A-CERTIFICATE');
    writeFileSync(join(layer, 'project.godot'), 'config_version=5\n');
    mkdirSync(join(layer, 'scripts'), { recursive: true });
    writeFileSync(join(layer, 'scripts', 'ok.gd'), 'extends Node\n');
    const names = collectLayerFiles(layer).map((full) => full.slice(layer.length + 1)).sort();
    assert.deepEqual(names, [join('scripts', 'ok.gd'), 'project.godot'].sort());
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a symlinked source refuses before the output directory exists', () => {
  const root = makeTemp();
  try {
    const layer = join(root, 'layer');
    mkdirSync(layer, { recursive: true });
    writeFileSync(join(layer, 'project.godot'), 'config_version=5\n');
    symlinkSync(join(layer, 'project.godot'), join(layer, 'alias.gd'));
    const target = join(root, 'output');
    assert.throws(
      () => executePlan({ target, steps: [{ kind: 'layer', from: layer, lesson: 1 }] }),
      /symlinked source/,
    );
    assert.throws(() => statSync(target), /ENOENT/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a symlinked asset parent cannot smuggle outside bytes in', () => {
  // Regression: assets/art -> external used to pass because lstat saw the
  // final marker.png as a regular file. Fake repo + fake external folder;
  // the marker is synthetic and must never land in an output.
  const root = makeTemp();
  try {
    const repo = join(root, 'repo');
    const layer = join(repo, 'examples', 'course', 'src', 'lesson-01');
    mkdirSync(layer, { recursive: true });
    writeFileSync(join(layer, 'project.godot'), 'config_version=5\n');
    const assets = join(repo, 'examples', 'course', 'src', 'assets');
    mkdirSync(assets, { recursive: true });
    const ext = join(root, 'ext');
    mkdirSync(ext, { recursive: true });
    writeFileSync(join(ext, 'marker.png'), 'SYNTHETIC-NOT-ART');
    symlinkSync(ext, join(assets, 'art'));
    const manifest = {
      lessons: { 1: { assets: ['art/marker.png'] } },
      assetDestinations: { 'art/marker.png': 'assets/marker.png' },
    };
    const target = join(root, 'output');
    assert.throws(
      () => executePlan(planCreation({ repoRoot: repo, lesson: 1, out: target, manifest })),
      /outside its root/,
    );
    assert.throws(() => statSync(target), /ENOENT/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a symlinked layer parent refuses before the output directory exists', () => {
  // Mirror case inside a layer: lesson-01/scripts -> external. The walk
  // refuses the alias itself; nothing is copied and no output is made.
  const root = makeTemp();
  try {
    const layer = join(root, 'layer');
    mkdirSync(layer, { recursive: true });
    writeFileSync(join(layer, 'project.godot'), 'config_version=5\n');
    const ext = join(root, 'ext');
    mkdirSync(ext, { recursive: true });
    writeFileSync(join(ext, 'marker.gd'), 'extends Node\n');
    symlinkSync(ext, join(layer, 'scripts'));
    const target = join(root, 'output');
    assert.throws(
      () => executePlan({ target, steps: [{ kind: 'layer', from: layer, root, lesson: 1 }] }),
      /symlinked source/,
    );
    assert.throws(() => statSync(target), /ENOENT/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a symlinked src/assets root refuses against the repository boundary', () => {
  // Regression: per-file containment compared against the canonical
  // alias-root itself, so assets -> external blessed its own tree.
  // Fake repo + fake external folder; the marker is synthetic.
  const root = makeTemp();
  try {
    const repo = join(root, 'repo');
    const layer = join(repo, 'examples', 'course', 'src', 'lesson-01');
    mkdirSync(layer, { recursive: true });
    writeFileSync(join(layer, 'project.godot'), 'config_version=5\n');
    const ext = join(root, 'ext');
    mkdirSync(ext, { recursive: true });
    writeFileSync(join(ext, 'marker.png'), 'SYNTHETIC-NOT-ART');
    symlinkSync(ext, join(repo, 'examples', 'course', 'src', 'assets'));
    const manifest = {
      lessons: { 1: { assets: ['marker.png'] } },
      assetDestinations: { 'marker.png': 'assets/marker.png' },
    };
    const target = join(root, 'output');
    assert.throws(
      () => executePlan(planCreation({ repoRoot: repo, lesson: 1, out: target, manifest })),
      /outside the repository/,
    );
    assert.throws(() => statSync(target), /ENOENT/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a symlinked src root refuses against the repository boundary', () => {
  // Mirror case one level up: src -> an external tree carrying its own
  // lesson-01. The layer check would pass textually; the boundary
  // comparison sees the real location. Nothing is created.
  const root = makeTemp();
  try {
    const repo = join(root, 'repo');
    mkdirSync(join(repo, 'examples', 'course'), { recursive: true });
    const ext = join(root, 'ext');
    mkdirSync(join(ext, 'lesson-01'), { recursive: true });
    writeFileSync(join(ext, 'lesson-01', 'marker.txt'), 'SYNTHETIC-NOT-SOURCE');
    symlinkSync(ext, join(repo, 'examples', 'course', 'src'));
    const manifest = { lessons: { 1: { assets: [] } }, assetDestinations: {} };
    const target = join(root, 'output');
    assert.throws(
      () => executePlan(planCreation({ repoRoot: repo, lesson: 1, out: target, manifest })),
      /outside the repository/,
    );
    assert.throws(() => statSync(target), /ENOENT/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('an excluded asset name refuses instead of copying', () => {
  // Key material stays out on the asset path too: a manifest entry naming
  // it is a manifest bug, so creation refuses rather than skipping.
  const root = makeTemp();
  try {
    const assets = join(root, 'assets');
    mkdirSync(assets, { recursive: true });
    writeFileSync(join(assets, 'synthetic-signing.p8'), 'SYNTHETIC-NOT-A-KEY');
    const target = join(root, 'output');
    assert.throws(
      () => executePlan({
        target,
        steps: [{
          kind: 'asset',
          from: join(assets, 'synthetic-signing.p8'),
          to: join(target, 'synthetic-signing.p8'),
          root: assets,
          lesson: 1,
        }],
      }),
      /excluded asset/,
    );
    assert.throws(() => statSync(target), /ENOENT/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('generated projects use the reference identity, not learner or shipping', () => {
  assert.notEqual(REFERENCE_APP_NAME, LEARNER_APP_NAME);
  assert.notEqual(REFERENCE_APP_NAME, SHIPPING_APP_NAME);
  assert.notEqual(REFERENCE_PACKAGE, LEARNER_PACKAGE);
  assert.notEqual(REFERENCE_PACKAGE, SHIPPING_PACKAGE);
  const manifest = loadManifest();
  const root = makeTemp();
  try {
    const out = join(root, 'lesson-01');
    executePlan(planCreation({ repoRoot: REPOSITORY, lesson: 1, out, manifest }));
    const project = readFileSync(join(out, 'project.godot'), 'utf8');
    assert.ok(project.includes(`config/name="${REFERENCE_APP_NAME}"`), 'reference app name');
    assert.ok(!project.includes(`config/name="${LEARNER_APP_NAME}"`), 'not the learner name');
    assert.ok(!project.includes(SHIPPING_PACKAGE), 'not the shipping package');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('later lessons overlay earlier layers cumulatively', () => {
  const manifest = loadManifest();
  const root = makeTemp();
  try {
    const one = join(root, 'one');
    executePlan(planCreation({ repoRoot: REPOSITORY, lesson: 1, out: one, manifest }));
    const eight = join(root, 'eight');
    executePlan(planCreation({ repoRoot: REPOSITORY, lesson: 8, out: eight, manifest }));
    const count = (dir) => {
      let total = 0;
      const stack = [dir];
      while (stack.length > 0) {
        const current = stack.pop();
        for (const entry of readdirSync(current, { withFileTypes: true })) {
          const full = join(current, entry.name);
          if (entry.isDirectory()) stack.push(full);
          else total += 1;
        }
      }
      return total;
    };
    assert.ok(count(eight) > count(one), 'lesson 8 output is larger than lesson 1');
    assert.ok(
      readFileSync(join(eight, 'scenes', 'gameplay', 'arena.tscn'), 'utf8').includes('Spirit'),
      'lesson 8 arena carries the spirit',
    );
    assert.ok(
      !readFileSync(join(one, 'scenes', 'menus', 'title_menu.tscn'), 'utf8').includes('title_menu.gd'),
      'lesson 1 title has no script yet',
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
