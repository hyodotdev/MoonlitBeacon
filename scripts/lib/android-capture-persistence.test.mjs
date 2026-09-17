import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';
import {
  ANDROID_CAPTURE_PERSISTENT_FILES,
  androidPersistentHashes,
  assertAndroidPersistentReportEvidence,
  buildAndroidPersistenceAnchor,
  buildAndroidPersistentEvidence,
  captureAndroidPersistentSnapshot,
  decodeAndroidPrivateFileBase64,
  isAndroidPrivateFileMissingBase64Error,
  restoreAndroidPersistentSnapshot,
} from './android-capture-persistence.mjs';

function fixture(initial = {}) {
  const files = new Map(Object.entries(initial).map(([name, value]) => [
    name,
    Buffer.from(value),
  ]));
  return {
    files,
    readFile: (name) => files.has(name) ? Buffer.from(files.get(name)) : null,
    writeFile: (name, value) => files.set(name, Buffer.from(value)),
    removeFile: (name) => files.delete(name),
  };
}

test('snapshot before first launch preserves every production replica as bytes', () => {
  const device = fixture(Object.fromEntries(
    ANDROID_CAPTURE_PERSISTENT_FILES.map((name) => [name, `before:${name}`]),
  ));
  const snapshot = captureAndroidPersistentSnapshot(device.readFile);
  for (const name of ANDROID_CAPTURE_PERSISTENT_FILES) {
    device.files.set(name, Buffer.from(`after:${name}`));
    assert.equal(snapshot[name].toString(), `before:${name}`);
  }
  assert.equal(
    Object.keys(androidPersistentHashes(snapshot)).length,
    ANDROID_CAPTURE_PERSISTENT_FILES.length,
  );
  assert.equal(
    snapshot['test_hero.request'].toString(),
    'before:test_hero.request',
  );
});

test('ADB shell Base64 reader preserves binary and 0-byte files and rejects error text', () => {
  const binary = Buffer.from([0, 1, 10, 13, 127, 128, 255]);
  const wrapped = `${binary.toString('base64').slice(0, 4)}\r\n${
    binary.toString('base64').slice(4)}\n`;
  assert.deepEqual(
    decodeAndroidPrivateFileBase64(wrapped, 'vault.cfg'),
    binary,
  );
  assert.deepEqual(
    decodeAndroidPrivateFileBase64('', 'settings.cfg'),
    Buffer.alloc(0),
  );
  assert.throws(
    () => decodeAndroidPrivateFileBase64(
      'cat: files/settings.cfg: No such file or directory',
      'settings.cfg',
    ),
    /Base64/u,
  );
  assert.throws(
    () => decodeAndroidPrivateFileBase64('YQ', 'settings.cfg'),
    /Base64/u,
  );
});

test('optional Base64 reader classifies only ENOENT of the exact same file as a race', () => {
  assert.equal(
    isAndroidPrivateFileMissingBase64Error(
      'base64: files/store_capture_runtime.state.json: No such file or directory\r\n',
      'store_capture_runtime.state.json',
    ),
    true,
  );
  assert.equal(
    isAndroidPrivateFileMissingBase64Error(
      Buffer.from('base64: files/settings.cfg: Permission denied\n'),
      'settings.cfg',
    ),
    false,
  );
  assert.equal(
    isAndroidPrivateFileMissingBase64Error(
      'base64: files/other.state.json: No such file or directory',
      'store_capture_runtime.state.json',
    ),
    false,
  );
  assert.equal(
    isAndroidPrivateFileMissingBase64Error(
      'warning: base64: files/settings.cfg: No such file or directory',
      'settings.cfg',
    ),
    false,
  );
});

test('restores first-launch mutations and new files byte-exact on success and failure paths', () => {
  const device = fixture({
    'vault.cfg': 'paid hero source',
    'iap_entitlements.cfg': 'owned product',
    'settings.cfg': 'locale=ko',
    'ladder.json': '',
    'test_hero.request': 'res://resources/heroes/sage.tres\n',
  });
  const original = captureAndroidPersistentSnapshot(device.readFile);
  device.files.set('vault.cfg', Buffer.from('revoked by direct launch'));
  device.files.delete('iap_entitlements.cfg');
  device.files.delete('test_hero.request');
  device.files.set('records.cfg', Buffer.from('created during capture'));
  const result = restoreAndroidPersistentSnapshot(original, device);
  assert.equal(result.mutated, true);
  assert.equal(device.files.get('vault.cfg').toString(), 'paid hero source');
  assert.equal(device.files.get('iap_entitlements.cfg').toString(), 'owned product');
  assert.equal(
    device.files.get('test_hero.request').toString(),
    'res://resources/heroes/sage.tres\n',
  );
  assert.equal(device.files.has('ladder.json'), true);
  assert.equal(device.files.get('ladder.json').length, 0);
  assert.equal(device.files.has('records.cfg'), false);
  assert.deepEqual(
    androidPersistentHashes(result.restored),
    androidPersistentHashes(original),
  );
});

test('fails closed on restore callback failure and an incomplete snapshot', () => {
  const device = fixture({ 'vault.cfg': 'before' });
  const original = captureAndroidPersistentSnapshot(device.readFile);
  device.files.set('vault.cfg', Buffer.from('after'));
  assert.throws(
    () => restoreAndroidPersistentSnapshot(original, {
      ...device,
      writeFile: () => {},
    }),
    /is not complete/u,
  );
  const incomplete = { ...original };
  delete incomplete['vault.cfg'];
  assert.throws(() => androidPersistentHashes(incomplete), /snapshot/u);
});

test('still restores remaining production files after one replica restore throws', () => {
  const device = fixture({
    'iap_entitlements.cfg': 'owned',
    'settings.cfg': 'locale=ko',
    'vault.cfg': 'paid hero source',
  });
  const original = captureAndroidPersistentSnapshot(device.readFile);
  for (const name of device.files.keys()) {
    device.files.set(name, Buffer.from(`mutated:${name}`));
  }
  assert.throws(
    () => restoreAndroidPersistentSnapshot(original, {
      ...device,
      writeFile: (name, value) => {
        if (name === 'iap_entitlements.cfg') throw new Error('injected IO failure');
        device.writeFile(name, value);
      },
    }),
    /is not complete/u,
  );
  assert.equal(device.files.get('settings.cfg').toString(), 'locale=ko');
  assert.equal(device.files.get('vault.cfg').toString(), 'paid hero source');
  assert.equal(
    device.files.get('iap_entitlements.cfg').toString(),
    'mutated:iap_entitlements.cfg',
  );
});

test('shared phone/tablet report proof is built only from actual before/restored bytes', () => {
  const device = fixture({
    'settings.cfg': 'locale=ko',
    'vault.cfg': 'owned=true',
  });
  const original = captureAndroidPersistentSnapshot(device.readFile);
  device.files.set('settings.cfg', Buffer.from('locale=en'));
  const restored = restoreAndroidPersistentSnapshot(original, device);
  const evidence = buildAndroidPersistentEvidence(original, restored);
  const anchored = buildAndroidPersistenceAnchor(
    evidence,
    original,
    restored,
    { captureId: '1'.repeat(64), path: 'builds/evidence/persistence.json' },
  );
  const report = { ...evidence, persistence_anchor: anchored.anchor };
  assert.equal(evidence.persistent_data_mutated_during_capture, true);
  assert.equal(evidence.persistent_data_restored_byte_exact, true);
  assert.deepEqual(
    evidence.persistent_data_sha256_before,
    evidence.persistent_data_sha256_restored,
  );
  assert.equal(
    evidence.settings_restore.original_sha256,
    evidence.settings_restore.restored_sha256,
  );
  assert.equal(assertAndroidPersistentReportEvidence(report, {
    anchorBytes: anchored.bytes,
  }), true);
  const tamperedAnchor = Buffer.concat([anchored.bytes, Buffer.from('tampered')]);
  assert.throws(
    () => assertAndroidPersistentReportEvidence(report, {
      anchorBytes: tamperedAnchor,
    }),
    /anchor source hash/u,
  );
});

test('shared persistence gate fails closed on missing, extra, false flags, and hash mismatch', () => {
  const device = fixture({ 'settings.cfg': 'locale=ko' });
  const original = captureAndroidPersistentSnapshot(device.readFile);
  const restoreResult = restoreAndroidPersistentSnapshot(original, device);
  const evidence = buildAndroidPersistentEvidence(original, restoreResult);
  const anchored = buildAndroidPersistenceAnchor(
    evidence,
    original,
    restoreResult,
    { captureId: '2'.repeat(64), path: 'builds/evidence/persistence.json' },
  );
  const report = { ...evidence, persistence_anchor: anchored.anchor };
  const mutations = [
    (value) => { delete value.persistent_data_files; },
    (value) => { value.persistent_data_files.push('unexpected.cfg'); },
    (value) => { value.persistent_data_restored_byte_exact = false; },
    (value) => {
      value.persistent_data_mutated_during_capture =
        !value.persistent_data_mutated_during_capture;
    },
    (value) => { delete value.persistent_data_sha256_before['vault.cfg']; },
    (value) => { value.persistent_data_sha256_restored['settings.cfg'] = 'a'.repeat(64); },
    (value) => { value.settings_restore.byte_exact = false; },
    (value) => { value.settings_restore.unexpected = true; },
    (value) => { value.settings_restore.restored_sha256 = 'b'.repeat(64); },
    (value) => { delete value.persistence_anchor; },
    (value) => {
      for (const field of [
        'persistent_data_sha256_before',
        'persistent_data_sha256_observed',
        'persistent_data_sha256_restored',
      ]) {
        for (const name of ANDROID_CAPTURE_PERSISTENT_FILES) value[field][name] = null;
      }
      value.persistent_data_mutated_during_capture = false;
      value.settings_restore = {
        original_present: false,
        original_sha256: null,
        observed_sha256: null,
        restored_sha256: null,
        byte_exact: true,
      };
    },
  ];
  for (const mutate of mutations) {
    const counterexample = structuredClone(report);
    mutate(counterexample);
    assert.throws(
      () => assertAndroidPersistentReportEvidence(counterexample),
      /Android|persistent|restore|settings|hash/u,
    );
  }
});

test('shared persistence builder rejects a mismatch in actual restored bytes', () => {
  const device = fixture({ 'vault.cfg': 'before' });
  const original = captureAndroidPersistentSnapshot(device.readFile);
  const observed = captureAndroidPersistentSnapshot(device.readFile);
  const wrong = captureAndroidPersistentSnapshot(device.readFile);
  wrong['vault.cfg'] = Buffer.from('after');
  assert.throws(() => buildAndroidPersistentEvidence(original, {
    files: [...ANDROID_CAPTURE_PERSISTENT_FILES],
    observed,
    restored: wrong,
    mutated: false,
  }), /before\/restored bytes/u);
});

test('phone and tablet snapshot before the first direct launch and restore after failure', () => {
  for (const relativePath of [
    'scripts/capture-store-screenshots.mjs',
    'scripts/capture-android-tablet-evidence.mjs',
  ]) {
    const source = readFileSync(resolve(relativePath), 'utf8');
    const main = source.slice(source.indexOf('async function main()'));
    const snapshot = main.indexOf(
      'const persistentBefore = capturePersistentFilesBeforeFirstLaunch()',
    );
    const launch = main.indexOf('await verifyInstalledDirectDistributionRuntime');
    const restore = main.indexOf('restorePersistentFiles(persistentBefore)');
    assert.ok(snapshot >= 0, `${relativePath} pre-launch snapshot`);
    if (relativePath.includes('tablet')) {
      const verifyStart = source.indexOf(
        'async function verifyInstalledDirectDistributionRuntime(',
      );
      const verifyEnd = source.indexOf('\nfunction ', verifyStart + 1);
      const verifier = source.slice(verifyStart, verifyEnd);
      const clear = verifier.indexOf('clearCaptureHandshakes()');
      const firstLaunch = verifier.indexOf('await launch()');
      assert.ok(
        clear >= 0 && firstLaunch > clear,
        `${relativePath} stale hero request is disabled before launch`,
      );
    } else {
      const staleHeroCleanup = main.indexOf(
        'clearStoreCaptureBootHandshake()',
        snapshot,
      );
      assert.ok(
        staleHeroCleanup > snapshot && staleHeroCleanup < launch,
        `${relativePath} stale hero request is disabled after snapshot and before launch`,
      );
    }
    assert.ok(launch > snapshot, `${relativePath} snapshot precedes first launch`);
    assert.ok(restore > launch, `${relativePath} restore follows launch/capture`);
    assert.match(
      source,
      /['"]scripts\/lib\/android-capture-persistence\.mjs['"]/u,
      `${relativePath} attestation fingerprints persistence helper`,
    );
  }
  const graphics = readFileSync(
    resolve('apps/game/tools/build_store_graphics.py'),
    'utf8',
  );
  assert.match(
    graphics,
    /"scripts\/lib\/android-capture-persistence\.mjs"/u,
    'store graphics freshness fingerprints persistence helper',
  );
  const tablet = readFileSync(
    resolve('scripts/capture-android-tablet-evidence.mjs'),
    'utf8',
  );
  assert.match(tablet, /credentialFreeChildEnvironment\(process\.env\)/u);
  assert.match(tablet, /env: CAPTURE_CHILD_ENV/u);
  assert.doesNotMatch(tablet, /env: process\.env/u);
  assert.match(tablet, /redactOutput: true/u);
  assert.match(tablet, /redactOutput \? '\\nomitting sensitive output'/u);
  assert.match(tablet, /const TEST_HERO_REQUEST = 'test_hero\.request'/u);
  const phone = readFileSync(
    resolve('scripts/capture-store-screenshots.mjs'),
    'utf8',
  );
  assert.match(phone, /const TEST_HERO_REQUEST_FILE = 'test_hero\.request'/u);
});

test('optional private read retries only atomic-replace races and rejects real errors', () => {
  for (const relativePath of [
    'scripts/capture-store-screenshots.mjs',
    'scripts/capture-android-tablet-evidence.mjs',
  ]) {
    const source = readFileSync(resolve(relativePath), 'utf8');
    const readStart = source.indexOf(
      relativePath.includes('tablet')
        ? 'function readPrivate(name, optional = false)'
        : 'function readPrivateFile(name, optional = false)',
    );
    const readEnd = source.indexOf('\nfunction ', readStart + 1);
    const reader = source.slice(readStart, readEnd);
    assert.match(reader, /attempt < 3/u, `${relativePath} bounded retry`);
    assert.match(reader, /existence\.status === 1 && existenceError === ''/u,
      `${relativePath} only confirmed absence becomes null`);
    assert.match(reader, /existence\.status !== 0 \|\| existenceError !== ''/u,
      `${relativePath} ADB and permission errors fail closed`);
    assert.match(reader, /lastError/u, `${relativePath} retains diagnostic error`);
    assert.match(
      reader,
      /optional\s*&&\s*result\.status === 1\s*&&\s*isAndroidPrivateFileMissingBase64Error\(stderr, name\)/u,
      `${relativePath} only exact optional base64 ENOENT is retried`,
    );
    assert.match(
      reader,
      /if \(attempt === 2\) return null;\s*continue;/u,
      `${relativePath} bounded ENOENT race becomes optional absence`,
    );
    assert.match(
      reader,
      /lastError = stderr \|\| `base64 status \$\{result\.status\}`;\s*break;/u,
      `${relativePath} other base64 failures remain fail closed`,
    );
    assert.match(reader, /'shell', 'run-as', PACKAGE, 'base64'/u,
      `${relativePath} preserves remote exit status and binary bytes`);
    assert.doesNotMatch(reader, /'exec-out'.*?'cat'/su,
      `${relativePath} does not accept cat errors as file bytes`);
  }
});
