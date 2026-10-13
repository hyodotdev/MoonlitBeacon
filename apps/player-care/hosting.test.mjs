// Combined hosting composition/check regressions. Uses the real care render
// plus a small fixture docs tree shaped like the real Docusaurus routes, all
// under temp dirs; never touches the committed dist/ or hosting-dist/.
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { build as buildCare } from './build.mjs';
import { composeHosting } from './hosting-build.mjs';
import { canonicalRouteBase, checkHosting, resolveCanonicalLink, resolveCombinedLink, ROOT_CONFIG_PATH } from './hosting-check.mjs';

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
    '<a href="/MoonlitBeacon/course">Course guide</a><a href="/MoonlitBeacon/docs/intro">Intro</a>'
    + '<a href="/en/privacy">Privacy</a><script src="/MoonlitBeacon/assets/app.js"></script>'
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

test('checker resolves cross-page fragments against rendered ids', async () => {
  // Shape of the course guide -> homepage play-section link: the target id
  // is server-rendered by a TSX page, so only built-HTML ids can prove it.
  const fixture = await freshFixture();
  try {
    writeFileSync(join(fixture.docsDir, 'course.html'), docsPage('Course guide',
      '<a href="/MoonlitBeacon/#play">Play</a>'));
    writeFileSync(join(fixture.docsDir, 'index.html'), docsPage('Docs home',
      '<section id="play"><a href="/MoonlitBeacon/course">Course guide</a></section>'));
    composeHosting(fixture);
    await checkHosting(fixture.options);
    const noId = docsPage('Docs home',
      '<section><a href="/MoonlitBeacon/course">Course guide</a></section>');
    writeFileSync(join(fixture.docsDir, 'index.html'), noId);
    writeFileSync(join(fixture.outDir, 'MoonlitBeacon', 'index.html'), noId);
    await assert.rejects(() => checkHosting(fixture.options), /fragment missing/);
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

test('checker fails on a relative asset under a nested index route', async () => {
  // Live incident shape: the file exists next to the page, so file-directory
  // resolution passes, but the browser asks one level higher from /MoonlitBeacon.
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    const target = join(fixture.outDir, 'MoonlitBeacon', 'index.html');
    writeFileSync(
      target,
      readFileSync(target, 'utf8').replace(
        '<script src="/MoonlitBeacon/assets/app.js"></script>',
        '<script src="assets/app.js"></script>',
      ),
    );
    await assert.rejects(
      () => checkHosting(fixture.options),
      /relative link breaks from the canonical route: assets\/app\.js/,
    );
  } finally {
    cleanup(fixture.root);
  }
});

test('checker passes a relative link that holds from its canonical route', async () => {
  // course.html serves at /MoonlitBeacon/course, whose base is the same
  // directory the file lives in — relative links there are genuinely fine.
  const fixture = await freshFixture();
  try {
    composeHosting(fixture);
    const summary = await checkHosting(fixture.options);
    assert.equal(summary.canonicalChecked, 0, 'no relative refs left on nested index routes');
  } finally {
    cleanup(fixture.root);
  }
});

test('canonical route bases resolve like the browser', () => {
  assert.equal(canonicalRouteBase('MoonlitBeacon/index.html'), '');
  assert.equal(canonicalRouteBase('MoonlitBeacon/course/index.html'), 'MoonlitBeacon');
  assert.equal(canonicalRouteBase('index.html'), null);
  assert.equal(canonicalRouteBase('MoonlitBeacon/course.html'), null);
  assert.equal(canonicalRouteBase('ko/privacy.html'), null);
  assert.deepEqual(resolveCanonicalLink('MoonlitBeacon/index.html', 'img/home-hero.jpg'), {
    candidates: ['img/home-hero.jpg'],
  });
  assert.deepEqual(resolveCanonicalLink('MoonlitBeacon/course/index.html', 'chapter-01'), {
    candidates: [
      'MoonlitBeacon/chapter-01',
      'MoonlitBeacon/chapter-01.html',
      'MoonlitBeacon/chapter-01/index.html',
    ],
  });
  assert.equal(resolveCanonicalLink('MoonlitBeacon/index.html', '/MoonlitBeacon/img/home-hero.jpg'), null);
  assert.equal(resolveCanonicalLink('MoonlitBeacon/index.html', '#toc'), null);
  assert.equal(resolveCanonicalLink('MoonlitBeacon/course.html', 'course/chapter-01'), null);
});

// Public entry/action identities: exact store parameters, optional contact,
// and privacy-sensitive regressions on the docs entry pages. Asserts on the
// page sources (built HTML inherits them byte for byte through composition),
// never on layout.
const DOCS_SRC = join(dirname(fileURLToPath(import.meta.url)), '..', 'docs', 'src');

test('public entry pages carry the exact store, contact, and privacy identities', () => {
  const docsSrc = DOCS_SRC;
  const links = readFileSync(join(docsSrc, 'storeLinks.ts'), 'utf8');
  assert.ok(
    links.includes('https://play.google.com/store/apps/details?id=com.crossplatformkorea.moonlitbeacon'),
    'play product identity',
  );
  assert.ok(links.includes('utm_source=moonlit_course'), 'play utm_source');
  assert.ok(links.includes('utm_medium=referral'), 'play utm_medium');
  assert.ok(links.includes('utm_campaign=course_first_play_20261013'), 'play utm_campaign');
  assert.ok(
    links.includes('https://apps.apple.com/app/id6796293839'),
    'app store identity without attribution',
  );
  assert.ok(!links.includes('id6796293839?'), 'no fabricated apple campaign attribution');
  assert.ok(links.includes("SUPPORT_EMAIL = 'hyo@hyo.dev'"), 'existing public support email');
  assert.ok(
    links.includes('https://moonlitbeacon.hyo.dev/en/privacy#support-requests'),
    'support privacy section link',
  );
  for (const page of ['pages/index.tsx', 'pages/first-play.tsx']) {
    const source = readFileSync(join(docsSrc, page), 'utf8');
    assert.ok(source.includes('../storeLinks'), `${page} uses the shared link module`);
  }
});

test('public entry pages add no trackers, storage, or data collection', () => {
  const docsSrc = DOCS_SRC;
  const sources = ['storeLinks.ts', 'pages/index.tsx', 'pages/first-play.tsx']
    .map((name) => [name, readFileSync(join(docsSrc, name), 'utf8')]);
  const forbidden = [
    'googletag', 'gtag', 'fbevent', 'facebook.net/tr', 'hotjar', 'amplitude',
    'mixpanel', 'sendBeacon', 'localStorage', 'sessionStorage', 'document.cookie',
    '<form', '<input', '<textarea',
  ];
  for (const [name, source] of sources) {
    for (const token of forbidden) {
      assert.ok(!source.includes(token), `${name} must not contain ${token}`);
    }
  }
  const [home] = sources.filter(([name]) => name === 'pages/index.tsx').map(([, source]) => source);
  assert.ok(!home.includes('src="img/'), 'hero uses the base-url helper, not a raw relative path');
  assert.ok(home.includes('useBaseUrl('), 'hero resolves against the site base');
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
