// Combined hosting composition/check regressions. Uses the real care render
// plus a small fixture docs tree shaped like the real Docusaurus routes, all
// under temp dirs; never touches the committed dist/ or hosting-dist/.
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import test from 'node:test';
import { build as buildCare } from './build.mjs';
import { composeHosting } from './hosting-build.mjs';
import { checkHosting, resolveCombinedLink, ROOT_CONFIG_PATH } from './hosting-check.mjs';

function docsPage(title, body) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${title}</title>
</head>
<body>
${body}
</body>
</html>
`;
}

// Fixture docs tree with the real route shapes: extensionless course and
// nested chapter routes, a docs page, one asset, and a cross-mount link back
// to the care pages.
function writeFixtureDocs(docsDir) {
  mkdirSync(join(docsDir, 'course'), { recursive: true });
  mkdirSync(join(docsDir, 'docs'), { recursive: true });
  mkdirSync(join(docsDir, 'assets'), { recursive: true });
  writeFileSync(join(docsDir, 'index.html'), docsPage('Docs home',
    '<a href="course">Course guide</a><a href="/MoonlitBeacon/docs/intro">Intro</a>'
    + '<a href="/en/privacy">Privacy</a><script src="assets/app.js"></script>'
    + '<a href="https://github.com/hyodotdev/MoonlitBeacon">GitHub</a>'));
  writeFileSync(join(docsDir, 'course.html'), docsPage('Course guide',
    '<a href="course/chapter-01">Lesson 1</a>'));
  writeFileSync(join(docsDir, 'course', 'chapter-01.html'), docsPage('Lesson 1', '<p>Setup.</p>'));
  writeFileSync(join(docsDir, 'docs', 'intro.html'), docsPage('Intro', '<p>Start.</p>'));
  writeFileSync(join(docsDir, 'assets', 'app.js'), 'console.log("fixture");\n');
  writeFileSync(join(docsDir, '404.html'), docsPage('Not found', '<p>Missing.</p>'));
}

function writeHostingConfig(dir, outDir, hostingExtra = {}) {
  const path = join(dir, 'firebase.hosting.json');
  writeFileSync(path, JSON.stringify({
    hosting: {
      site: 'moonlitbeacon-778ee', public: outDir, cleanUrls: true, trailingSlash: false, ...hostingExtra,
    },
  }));
  return path;
}

async function freshFixture() {
  const root = mkdtempSync(join(tmpdir(), 'hosting-test-'));
  const careDir = join(root, 'care');
  const docsDir = join(root, 'docs');
  const outDir = join(root, 'out');
  await buildCare(careDir);
  writeFixtureDocs(docsDir);
  const hostingConfigPath = writeHostingConfig(root, outDir);
  return {
    root, careDir, docsDir, outDir, hostingConfigPath,
    options: { outDir, careDir, docsDir, hostingConfigPath, rootConfigPath: ROOT_CONFIG_PATH },
  };
}

function cleanup(root) {
  rmSync(root, { recursive: true, force: true });
}

test('composes care files at root and docs files under the mount', async () => {
  const fixture = await freshFixture();
  try {
    const composed = composeHosting(fixture);
    assert.equal(composed.careFiles, 49);
    assert.equal(composed.docsFiles, 6);
    assert.equal(
      readFileSync(join(fixture.outDir, 'ko', 'privacy.html'), 'utf8'),
      readFileSync(join(fixture.careDir, 'ko', 'privacy.html'), 'utf8'),
    );
    assert.equal(
      readFileSync(join(fixture.outDir, 'MoonlitBeacon', 'course', 'chapter-01.html'), 'utf8'),
      readFileSync(join(fixture.docsDir, 'course', 'chapter-01.html'), 'utf8'),
    );
    assert.ok(!existsSync(join(fixture.outDir, 'course.html')), 'docs files stay under the mount');
    const summary = await checkHosting(fixture.options);
    assert.equal(summary.careFiles, 49);
    assert.equal(summary.docsFiles, 6);
    assert.equal(summary.docsPages, 5);
    assert.ok(summary.linksChecked > 100, `links resolved: ${summary.linksChecked}`);
  } finally {
    cleanup(fixture.root);
  }
});

test('checker fails when a referenced docs asset is omitted', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    rmSync(join(fixture.outDir, 'MoonlitBeacon', 'assets', 'app.js'));
    await assert.rejects(() => checkHosting(fixture.options), /assets\/app\.js/);
  } finally {
    cleanup(fixture.root);
  }
});

test('checker fails when a care page is corrupted', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    const target = join(fixture.outDir, 'ko', 'privacy.html');
    writeFileSync(target, `${readFileSync(target, 'utf8')} `);
    await assert.rejects(() => checkHosting(fixture.options), /bytes differ: ko\/privacy\.html/);
  } finally {
    cleanup(fixture.root);
  }
});

test('checker fails when a course route is missing', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    rmSync(join(fixture.outDir, 'MoonlitBeacon', 'course.html'));
    await assert.rejects(() => checkHosting(fixture.options), /key route missing: \/MoonlitBeacon\/course/);
  } finally {
    cleanup(fixture.root);
  }
});

test('checker fails when a docs source goes stale', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    const source = join(fixture.docsDir, 'docs', 'intro.html');
    writeFileSync(source, `${readFileSync(source, 'utf8')}\n`);
    await assert.rejects(() => checkHosting(fixture.options), /bytes differ: MoonlitBeacon\/docs\/intro\.html/);
  } finally {
    cleanup(fixture.root);
  }
});

test('checker fails when the care input goes stale', async () => {
  const fixture = await freshFixture();
  try {
    const target = join(fixture.careDir, 'en', 'support.html');
    writeFileSync(target, `${readFileSync(target, 'utf8')} `);
    composeHosting(fixture);
    await assert.rejects(() => checkHosting(fixture.options), /care input is stale/);
  } finally {
    cleanup(fixture.root);
  }
});

test('checker fails on a broken cross-mount link', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    const target = join(fixture.outDir, 'en', 'privacy.html');
    writeFileSync(target, readFileSync(target, 'utf8').replace('/MoonlitBeacon/', '/MoonlitBeacon/no-such-page'));
    await assert.rejects(() => checkHosting(fixture.options), /no-such-page/);
  } finally {
    cleanup(fixture.root);
  }
});

test('checker fails on a NUL byte in composed HTML', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    const target = join(fixture.outDir, 'MoonlitBeacon', 'docs', 'intro.html');
    const body = readFileSync(target);
    body.writeUInt8(0, 20);
    writeFileSync(target, body);
    await assert.rejects(() => checkHosting(fixture.options), /NUL byte/);
  } finally {
    cleanup(fixture.root);
  }
});

test('checker fails on author notes in the output', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    mkdirSync(join(fixture.outDir, 'notes'), { recursive: true });
    writeFileSync(join(fixture.outDir, 'notes', 'draft.md'), '# draft\n');
    await assert.rejects(() => checkHosting(fixture.options), /author notes/);
  } finally {
    cleanup(fixture.root);
  }
});

test('composer rejects a symlink in the docs input', async () => {
  const fixture = await freshFixture();
  try {
    symlinkSync(join(fixture.docsDir, 'index.html'), join(fixture.docsDir, 'alias.html'));
    assert.throws(() => composeHosting(fixture), /symlink/);
    assert.ok(!existsSync(fixture.outDir), 'nothing composed');
  } finally {
    cleanup(fixture.root);
  }
});

test('composer rejects a symlink in the care input', async () => {
  const fixture = await freshFixture();
  try {
    symlinkSync(join(fixture.careDir, 'index.html'), join(fixture.careDir, 'alias.html'));
    assert.throws(() => composeHosting(fixture), /symlink/);
    assert.ok(!existsSync(fixture.outDir), 'nothing composed');
  } finally {
    cleanup(fixture.root);
  }
});

test('composer refuses a non-empty unexpected output without deleting', async () => {
  const fixture = await freshFixture();
  try {
    const precious = join(fixture.root, 'precious');
    mkdirSync(precious, { recursive: true });
    writeFileSync(join(precious, 'keep.txt'), 'do not delete\n');
    assert.throws(
      () => composeHosting({ ...fixture, outDir: precious }),
      /refusing to clean/,
    );
    assert.equal(readFileSync(join(precious, 'keep.txt'), 'utf8'), 'do not delete\n');
  } finally {
    cleanup(fixture.root);
  }
});

test('composer refuses an output that would swallow its inputs', async () => {
  const fixture = await freshFixture();
  try {
    assert.throws(
      () => composeHosting({ ...fixture, outDir: fixture.root }),
      /must not contain its inputs/,
    );
    assert.ok(existsSync(join(fixture.careDir, 'index.html')), 'care input intact');
    assert.ok(existsSync(join(fixture.docsDir, 'index.html')), 'docs input intact');
  } finally {
    cleanup(fixture.root);
  }
});

test('composer refuses a symlink output', async () => {
  const fixture = await freshFixture();
  try {
    const real = join(fixture.root, 'real');
    mkdirSync(real, { recursive: true });
    const link = join(fixture.root, 'linked-out');
    symlinkSync(real, link);
    assert.throws(() => composeHosting({ ...fixture, outDir: link }), /must not be a symlink/);
  } finally {
    cleanup(fixture.root);
  }
});

test('composer accepts an empty existing directory', async () => {
  const fixture = await freshFixture();
  try {
    mkdirSync(fixture.outDir, { recursive: true });
    const composed = composeHosting(fixture);
    assert.equal(composed.careFiles, 49);
    await checkHosting(fixture.options);
  } finally {
    cleanup(fixture.root);
  }
});

test('checker rejects a hosting config with a catch-all rewrite', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    const configPath = writeHostingConfig(fixture.root, fixture.outDir, {
      rewrites: [{ source: '**', destination: '/index.html' }],
    });
    await assert.rejects(
      () => checkHosting({ ...fixture.options, hostingConfigPath: configPath }),
      /must not set rewrites/,
    );
  } finally {
    cleanup(fixture.root);
  }
});

test('checker rejects a hosting config pointed at another directory', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    const configPath = writeHostingConfig(fixture.root, join(fixture.root, 'elsewhere'));
    await assert.rejects(
      () => checkHosting({ ...fixture.options, hostingConfigPath: configPath }),
      /must resolve to the generated output/,
    );
  } finally {
    cleanup(fixture.root);
  }
});

test('checker rejects public outside its Firebase project directory even when it matches outDir', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    const projectDir = join(fixture.root, 'project');
    mkdirSync(projectDir, { recursive: true });
    const outsidePublic = relative(projectDir, fixture.outDir);
    const configPath = writeHostingConfig(projectDir, outsidePublic);
    await assert.rejects(
      () => checkHosting({ ...fixture.options, hostingConfigPath: configPath }),
      /must stay inside the Firebase project directory/,
    );
  } finally {
    cleanup(fixture.root);
  }
});

test('checker rejects a hosting config on the wrong site', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    const configPath = writeHostingConfig(fixture.root, fixture.outDir, { site: 'other-site' });
    await assert.rejects(
      () => checkHosting({ ...fixture.options, hostingConfigPath: configPath }),
      /site must be moonlitbeacon-778ee/,
    );
  } finally {
    cleanup(fixture.root);
  }
});

test('checker rejects a root config carrying a hosting key', async () => {
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    const rootPath = join(fixture.root, 'firebase.json');
    writeFileSync(rootPath, JSON.stringify({ firestore: { rules: 'firestore.rules' }, hosting: { public: 'x' } }));
    await assert.rejects(
      () => checkHosting({ ...fixture.options, rootConfigPath: rootPath }),
      /stay Firestore-only/,
    );
  } finally {
    cleanup(fixture.root);
  }
});

test('extensionless docs links resolve like cleanUrls', () => {
  assert.deepEqual(resolveCombinedLink('index.html', '/MoonlitBeacon/course'), {
    candidates: ['MoonlitBeacon/course', 'MoonlitBeacon/course.html', 'MoonlitBeacon/course/index.html'],
  });
  assert.deepEqual(resolveCombinedLink('index.html', '/MoonlitBeacon/'), {
    candidates: ['MoonlitBeacon/index.html'],
  });
  assert.deepEqual(resolveCombinedLink('MoonlitBeacon/course.html', 'course/chapter-01'), {
    candidates: [
      'MoonlitBeacon/course/chapter-01',
      'MoonlitBeacon/course/chapter-01.html',
      'MoonlitBeacon/course/chapter-01/index.html',
    ],
  });
  assert.deepEqual(resolveCombinedLink('ko/privacy.html', '../../escape'), { escapes: true });
  assert.deepEqual(resolveCombinedLink('index.html', '#toc'), { skipped: true });
});
