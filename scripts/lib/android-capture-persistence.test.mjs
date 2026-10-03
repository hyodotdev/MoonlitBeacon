import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import test from 'node:test';
import {
  ANDROID_CAPTURE_PERSISTENT_FILES,
  ANDROID_CAPTURE_PERSISTENT_DYNAMIC_PATTERN,
  androidPersistentDynamicFiles,
  androidPersistentDynamicHashes,
  androidPersistentHashes,
  assertAndroidPersistentReportEvidence,
  buildAndroidPersistenceAnchor,
  buildAndroidPersistentEvidence,
  captureAndroidPersistentSnapshot,
  decodeAndroidPrivateFileBase64,
  isAndroidPersistentDynamicFile,
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
    listFiles: () => [...files.keys()],
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
    dynamicFiles: [],
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
    const captureStart = source.indexOf(
      'function capturePersistentFilesBeforeFirstLaunch()',
    );
    const captureBody = source.slice(
      captureStart,
      source.indexOf('\nfunction ', captureStart + 1),
    );
    assert.match(
      captureBody,
      /listFiles/u,
      `${relativePath} enumerates account partitions at capture`,
    );
    const restoreStart = source.indexOf('function restorePersistentFiles(original)');
    const restoreBody = source.slice(
      restoreStart,
      source.indexOf('\nfunction ', restoreStart + 1),
    );
    assert.match(
      restoreBody,
      /listFiles/u,
      `${relativePath} enumerates account partitions at restore`,
    );
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

const DYNAMIC_PUBLIC_ID = 'MB-0123456789abcdef0123456789abcdef';
const DYNAMIC_UID = 'firebaseUid_123-ABC';

test('dynamic pattern accepts every partition kind and rejects lookalikes', () => {
  assert.match(
    ANDROID_CAPTURE_PERSISTENT_DYNAMIC_PATTERN,
    /^\^.*\$$/u,
    'pattern is anchored at both ends',
  );
  for (const name of [
    `journey.${DYNAMIC_PUBLIC_ID}.json`,
    `journey.${DYNAMIC_PUBLIC_ID}.json.tmp`,
    `journey.${DYNAMIC_PUBLIC_ID}.json.bak`,
    `journey.${DYNAMIC_PUBLIC_ID}.json.bak.tmp`,
    `journey.${DYNAMIC_PUBLIC_ID}.rev.json`,
    `journey.${DYNAMIC_PUBLIC_ID}.rev.json.tmp`,
    `journey.${DYNAMIC_PUBLIC_ID}.rejected-local.json`,
    `journey.${DYNAMIC_PUBLIC_ID}.rejected-local.json.tmp`,
    `journey.${DYNAMIC_PUBLIC_ID}.rejected-remote.json`,
    `journey.${DYNAMIC_PUBLIC_ID}.rejected-remote.json.tmp`,
    `cloud_journey.${DYNAMIC_UID}.json`,
    `cloud_journey.${DYNAMIC_UID}.json.tmp`,
    'journey.empty.json',
    `journey.h_${'a'.repeat(32)}.json`,
    `cloud_journey.h_${'b'.repeat(32)}.json.tmp`,
  ]) {
    assert.equal(isAndroidPersistentDynamicFile(name), true, name);
  }
  for (const name of [
    'journey.json',
    'journey.json.tmp',
    'journey.json.bak',
    'cloud_journey.json',
    'journey..json',
    'journey.MB-1.json.bak.tmp.extra',
    `journey.${'a'.repeat(65)}.json`,
    'journey.MB-1.rev.json.bak',
    'journey.MB-1.rejected-sideways.json',
    'journey.MB-1.JSON',
    'JOURNEY.MB-1.json',
    'journey.MB 1.json',
    'journey.MB/1.json',
    'journey.MB-1.json\n',
    '../journey.MB-1.json',
    'journey.MB-1.json/.',
    '.',
    '..',
    '',
    'vault.cfg',
    'unexpected.cfg',
    'store_capture_state.json',
  ]) {
    assert.equal(isAndroidPersistentDynamicFile(name), false, name);
  }
  for (const notString of [null, undefined, 123, {}, []]) {
    assert.equal(isAndroidPersistentDynamicFile(notString), false, String(notString));
  }
});

test('capture enumerates account partitions and skips control files', () => {
  const partition = `journey.${DYNAMIC_PUBLIC_ID}.json`;
  const baseline = `journey.${DYNAMIC_PUBLIC_ID}.rev.json`;
  const cloud = `cloud_journey.${DYNAMIC_UID}.json`;
  const device = fixture({
    'settings.cfg': 'locale=ko',
    [partition]: '{"cycle":3}',
    [baseline]: '{"acked_revision":9}',
    [cloud]: '{"revision":9}',
    'store_capture_state.json': '{"nonce":"control"}',
  });
  const snapshot = captureAndroidPersistentSnapshot(device.readFile, {
    listFiles: device.listFiles,
  });
  assert.deepEqual(
    androidPersistentDynamicFiles(snapshot),
    [partition, baseline, cloud].sort(),
  );
  assert.equal(snapshot[partition].toString(), '{"cycle":3}');
  assert.equal(Object.hasOwn(snapshot, 'store_capture_state.json'), false);
  assert.equal(
    androidPersistentDynamicHashes(snapshot)[partition],
    createHash('sha256').update('{"cycle":3}').digest('hex'),
  );
  // Without a lister the same device reads fixed files only.
  const fixedOnly = captureAndroidPersistentSnapshot(device.readFile);
  assert.deepEqual(androidPersistentDynamicFiles(fixedOnly), []);
  assert.throws(
    () => captureAndroidPersistentSnapshot(device.readFile, { listFiles: () => ({}) }),
    /did not return an array/u,
  );
  assert.throws(
    () => captureAndroidPersistentSnapshot(device.readFile, { listFiles: () => [null] }),
    /non-string entry/u,
  );
});

test('restore repairs mutated partitions and removes capture-created ones', () => {
  const partition = `journey.${DYNAMIC_PUBLIC_ID}.json`;
  const backup = `${partition}.bak`;
  const device = fixture({
    'settings.cfg': 'locale=ko',
    [partition]: 'before-partition',
    [backup]: 'before-backup',
  });
  const original = captureAndroidPersistentSnapshot(device.readFile, {
    listFiles: device.listFiles,
  });
  device.files.set(partition, Buffer.from('mutated-partition'));
  device.files.delete(backup);
  const created = `cloud_journey.${DYNAMIC_UID}.json`;
  device.files.set(created, Buffer.from('capture-created'));
  const result = restoreAndroidPersistentSnapshot(original, device);
  assert.equal(result.mutated, true);
  assert.deepEqual(result.dynamicFiles, [backup, partition].sort());
  assert.equal(device.files.get(partition).toString(), 'before-partition');
  assert.equal(device.files.get(backup).toString(), 'before-backup');
  assert.equal(device.files.has(created), false);
  const evidence = buildAndroidPersistentEvidence(original, result);
  assert.equal(evidence.persistent_data_dynamic_mutated_during_capture, true);
  assert.equal(evidence.persistent_data_mutated_during_capture, true);
  assert.equal(evidence.persistent_data_dynamic_restored_byte_exact, true);
  assert.deepEqual(
    evidence.persistent_data_dynamic_sha256_before,
    evidence.persistent_data_dynamic_sha256_restored,
  );
  assert.ok(Object.hasOwn(
    evidence.persistent_data_dynamic_sha256_observed,
    created,
  ));
  const anchored = buildAndroidPersistenceAnchor(
    evidence,
    original,
    result,
    { captureId: '3'.repeat(64), path: 'builds/evidence/persistence.json' },
  );
  assert.equal(assertAndroidPersistentReportEvidence({
    ...evidence,
    persistence_anchor: anchored.anchor,
  }, { anchorBytes: anchored.bytes }), true);
});

test('shared persistence gate fails closed on dynamic fragment tampering', () => {
  const partition = `journey.${DYNAMIC_PUBLIC_ID}.json`;
  const backup = `${partition}.bak`;
  const device = fixture({
    'settings.cfg': 'locale=ko',
    [partition]: 'partition-bytes',
    [backup]: 'backup-bytes',
  });
  const original = captureAndroidPersistentSnapshot(device.readFile, {
    listFiles: device.listFiles,
  });
  const restoreResult = restoreAndroidPersistentSnapshot(original, device);
  const evidence = buildAndroidPersistentEvidence(original, restoreResult);
  const anchored = buildAndroidPersistenceAnchor(
    evidence,
    original,
    restoreResult,
    { captureId: '4'.repeat(64), path: 'builds/evidence/persistence.json' },
  );
  const report = { ...evidence, persistence_anchor: anchored.anchor };
  assert.equal(
    report.persistent_data_dynamic_files.length,
    2,
    'fixture carries two partitions',
  );
  const mutations = [
    (value) => { delete value.persistent_data_dynamic_files; },
    (value) => { value.persistent_data_dynamic_files.push('unexpected.cfg'); },
    (value) => {
      value.persistent_data_dynamic_files.push(`journey.${DYNAMIC_PUBLIC_ID}.json`);
    },
    (value) => { value.persistent_data_dynamic_files.reverse(); },
    (value) => { delete value.persistent_data_dynamic_sha256_before[partition]; },
    (value) => {
      value.persistent_data_dynamic_sha256_restored[partition] = 'c'.repeat(64);
    },
    (value) => {
      value.persistent_data_dynamic_sha256_observed['unexpected.cfg'] = 'd'.repeat(64);
    },
    (value) => {
      value.persistent_data_dynamic_mutated_during_capture =
        !value.persistent_data_dynamic_mutated_during_capture;
    },
    (value) => { value.persistent_data_dynamic_restored_byte_exact = false; },
  ];
  for (const mutate of mutations) {
    const counterexample = structuredClone(report);
    mutate(counterexample);
    assert.throws(
      () => assertAndroidPersistentReportEvidence(counterexample),
      /dynamic|persistent|restore|hash/u,
    );
  }
});

test('every production user:// save is covered by the fixed list or the dynamic pattern', () => {
  const scriptsRoot = resolve('apps/game/scripts');
  const gdFiles = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (entry.name.endsWith('.gd')) gdFiles.push(path);
    }
  };
  walk(scriptsRoot);
  assert.ok(gdFiles.length > 50, 'production scripts found');
  // Capture-owned handshakes are armed and cleaned by the capture scripts
  // themselves, never preserved as user data.
  const handshakeFiles = new Set([
    'store_capture_boot.request.json',
    'store_capture_clean_combat.ready',
    'store_capture_clean_combat.request',
    'store_capture_clean_title.ready',
    'store_capture_clean_title.request',
    'store_capture_missile_core.request',
    'store_capture_runtime.request.json',
    'store_capture_runtime.state.json',
    'store_capture_runtime.state.tmp',
    'store_capture_state.json',
    'store_capture_state.tmp',
    'store_capture_title_runtime.ready',
  ]);
  // Dynamic path builders emit a prefix plus a validated account token;
  // the pattern (not a literal) covers every name they produce.
  const dynamicPrefixes = new Set(['journey.', 'cloud_journey.']);
  const fixed = new Set(ANDROID_CAPTURE_PERSISTENT_FILES);
  const uncovered = [];
  for (const file of gdFiles) {
    const text = readFileSync(file, 'utf8');
    for (const match of text.matchAll(/user:\/\/([A-Za-z0-9_.-]*)/gu)) {
      const name = match[1];
      if (name === '') continue;
      if (fixed.has(name) || handshakeFiles.has(name) || dynamicPrefixes.has(name)) continue;
      uncovered.push(`${file}: user://${name}`);
    }
  }
  assert.deepEqual(uncovered, []);
  // Every fixed name must still be produced by the game, so a removed save
  // fails loudly instead of lingering as a dead contract entry.
  const allText = gdFiles.map((file) => readFileSync(file, 'utf8')).join('\n');
  for (const name of ANDROID_CAPTURE_PERSISTENT_FILES) {
    const stem = name.replace(/\.tmp$/, '').replace(/\.bak$/, '');
    assert.ok(allText.includes(stem), `${name} is still produced by the game`);
  }
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

test('native Base64 readers accept precisely validated dynamic partitions', () => {
  const syntheticZero = 'MB-00000000000000000000000000000000';
  const valid = [
    `journey.${syntheticZero}.json`,
    `journey.${DYNAMIC_PUBLIC_ID}.json`,
    `journey.${DYNAMIC_PUBLIC_ID}.json.bak`,
    `journey.${DYNAMIC_PUBLIC_ID}.json.bak.tmp`,
    `journey.${DYNAMIC_PUBLIC_ID}.rev.json`,
    `journey.${DYNAMIC_PUBLIC_ID}.rev.json.tmp`,
    `journey.${DYNAMIC_PUBLIC_ID}.rejected-local.json`,
    `journey.${DYNAMIC_PUBLIC_ID}.rejected-remote.json.tmp`,
    `journey.${DYNAMIC_UID}.json`,
    `cloud_journey.${DYNAMIC_UID}.json`,
    `cloud_journey.${DYNAMIC_UID}.json.tmp`,
  ];
  const binary = Buffer.from([0, 1, 10, 13, 127, 128, 255]);
  for (const name of valid) {
    assert.equal(isAndroidPersistentDynamicFile(name), true, name);
    // Production passes adb stdout as a Buffer; wrapped lines must survive.
    const encoded = binary.toString('base64');
    const wrapped = `${encoded.slice(0, 4)}\r\n${encoded.slice(4)}\n`;
    assert.deepEqual(
      decodeAndroidPrivateFileBase64(Buffer.from(wrapped, 'ascii'), name),
      binary,
      name,
    );
    assert.deepEqual(
      decodeAndroidPrivateFileBase64('', name),
      Buffer.alloc(0),
      name,
    );
    const stderr = `base64: files/${name}: No such file or directory`;
    assert.equal(
      isAndroidPrivateFileMissingBase64Error(stderr, name),
      true,
      name,
    );
    assert.equal(
      isAndroidPrivateFileMissingBase64Error(Buffer.from(`${stderr}\n`), name),
      true,
      name,
    );
    // Same-name match only: wrong file and real errors stay false, not absent.
    assert.equal(
      isAndroidPrivateFileMissingBase64Error(
        'base64: files/other.json: No such file or directory',
        name,
      ),
      false,
      name,
    );
    assert.equal(
      isAndroidPrivateFileMissingBase64Error(
        `base64: files/${name}: Permission denied`,
        name,
      ),
      false,
      name,
    );
    // Filename passes, payload still fails closed on shell error text.
    assert.throws(
      () => decodeAndroidPrivateFileBase64(
        `cat: files/${name}: No such file or directory`,
        name,
      ),
      /Base64/u,
      name,
    );
  }
  // Uppercase lookalikes fail; the fix must not accept every uppercase name.
  const rejected = [
    'journey.MB-1.JSON',
    'JOURNEY.MB-1.json',
    'journey.MB-1.rejected-sideways.json',
    'journey.MB 1.json',
    'journey.MB/1.json',
    'journey.MB-1.json\n',
    'journey:MB-1.json',
    '../journey.MB-1.json',
    'journey.MB-1.json/../vault.cfg',
    'journey.$(id).json',
    'journey.a;b.json',
    'journey.a|b.json',
    `journey.${'A'.repeat(65)}.json`,
    'journey.MB-1.json.bak.tmp.extra',
    'journey.MB-1.rev.json.bak',
    'cloud_journey.MB-1.json.bak',
    'cloud_journey.MB-1.rev.json',
    '',
  ];
  for (const name of rejected) {
    assert.equal(isAndroidPersistentDynamicFile(name), false, name);
    assert.throws(
      () => decodeAndroidPrivateFileBase64(Buffer.from('aGk='), name),
      /Unsafe/u,
      name,
    );
    assert.throws(
      () => isAndroidPrivateFileMissingBase64Error(
        `base64: files/${name}: No such file or directory`,
        name,
      ),
      /Unsafe/u,
      name,
    );
  }
  // Lowercase charset contract is preserved even for non-dynamic names.
  for (const name of [
    'store_capture_runtime.state.json',
    'unexpected.cfg',
    'journey..json',
    `journey.${'a'.repeat(65)}.json`,
  ]) {
    assert.equal(isAndroidPersistentDynamicFile(name), false, name);
    assert.deepEqual(
      decodeAndroidPrivateFileBase64('aGk=', name),
      Buffer.from('hi'),
      name,
    );
    assert.equal(
      isAndroidPrivateFileMissingBase64Error(
        `base64: files/${name}: No such file or directory`,
        name,
      ),
      true,
      name,
    );
  }
});

test('dynamic snapshot/read/restore round-trips through the production Base64 boundary', () => {
  const syntheticZero = 'MB-00000000000000000000000000000000';
  const valid = [
    `journey.${syntheticZero}.json`,
    `journey.${DYNAMIC_PUBLIC_ID}.json.bak`,
    `journey.${DYNAMIC_PUBLIC_ID}.json.bak.tmp`,
    `journey.${DYNAMIC_PUBLIC_ID}.rev.json`,
    `journey.${DYNAMIC_PUBLIC_ID}.rev.json.tmp`,
    `journey.${DYNAMIC_PUBLIC_ID}.rejected-local.json`,
    `journey.${DYNAMIC_PUBLIC_ID}.rejected-remote.json.tmp`,
    `journey.${DYNAMIC_UID}.json`,
    `cloud_journey.${DYNAMIC_UID}.json`,
    `cloud_journey.${DYNAMIC_UID}.json.tmp`,
  ];
  const ignored = [
    'store_capture_state.json',
    'journey..json',
    `journey.${'a'.repeat(65)}.json`,
    'journey.MB-1.JSON',
    'JOURNEY.MB-1.json',
    'journey.MB 1.json',
    'journey.MB/1.json',
    '../journey.MB-1.json',
    'journey.$(id).json',
    'journey.a;b.json',
    'journey.MB-1.json.bak.tmp.extra',
    'journey.MB-1.rev.json.bak',
    'cloud_journey.MB-1.json.bak',
  ];
  for (const name of valid) {
    assert.equal(isAndroidPersistentDynamicFile(name), true, name);
  }
  for (const name of ignored) {
    assert.equal(isAndroidPersistentDynamicFile(name), false, name);
  }
  const binaryPartition = `journey.${DYNAMIC_UID}.json`;
  const emptyPartition = `cloud_journey.${DYNAMIC_UID}.json`;
  const files = new Map();
  files.set('settings.cfg', Buffer.from('locale=ko'));
  files.set('vault.cfg', Buffer.from('paid hero source'));
  for (const name of valid) {
    if (name === binaryPartition) {
      files.set(name, Buffer.from([0, 1, 10, 13, 127, 128, 255]));
    } else if (name === emptyPartition) {
      files.set(name, Buffer.alloc(0));
    } else {
      files.set(name, Buffer.from(`payload:${name}`));
    }
  }
  for (const name of ignored) files.set(name, Buffer.from(`ignored:${name}`));
  // Production moves bytes as Base64 stdout (Buffer) and classifies the
  // atomic-replace race by the exact base64 stderr line.
  const readFile = (name) => {
    if (!files.has(name)) {
      const stderr = `base64: files/${name}: No such file or directory`;
      if (!isAndroidPrivateFileMissingBase64Error(stderr, name)) {
        throw new Error(`missing helper rejected absence: ${name}`);
      }
      return null;
    }
    const encoded = files.get(name).toString('base64');
    const wrapped = encoded.length > 4
      ? `${encoded.slice(0, 4)}\r\n${encoded.slice(4)}\n`
      : encoded;
    return decodeAndroidPrivateFileBase64(
      Buffer.from(wrapped, 'ascii'),
      name,
    );
  };
  const device = {
    files,
    readFile,
    writeFile: (name, value) => files.set(name, Buffer.from(value)),
    removeFile: (name) => files.delete(name),
    listFiles: () => [...files.keys()],
  };
  const original = captureAndroidPersistentSnapshot(readFile, {
    listFiles: device.listFiles,
  });
  assert.deepEqual(
    androidPersistentDynamicFiles(original),
    [...valid].sort(),
  );
  for (const name of ignored) {
    assert.equal(Object.hasOwn(original, name), false, name);
  }
  for (const name of valid) {
    assert.ok(original[name].equals(files.get(name)), name);
  }
  assert.deepEqual(
    original[binaryPartition],
    Buffer.from([0, 1, 10, 13, 127, 128, 255]),
  );
  assert.equal(original[emptyPartition].length, 0);
  // An absent valid partition reads as null through the missing-file helper.
  const absentDynamic = `journey.${syntheticZero}.rev.json`;
  assert.equal(isAndroidPersistentDynamicFile(absentDynamic), true);
  assert.equal(readFile(absentDynamic), null);
  const mutatedName = valid[0];
  const deletedName = valid[1];
  const createdName = 'cloud_journey.CaptureCreated-ABCxyz.json';
  assert.equal(isAndroidPersistentDynamicFile(createdName), true);
  files.set(mutatedName, Buffer.from('mutated-partition'));
  files.delete(deletedName);
  files.set(createdName, Buffer.from('capture-created'));
  files.set('settings.cfg', Buffer.from('locale=en'));
  files.set('store_capture_state.json', Buffer.from('mutated-control'));
  const result = restoreAndroidPersistentSnapshot(original, device);
  assert.equal(result.mutated, true);
  assert.deepEqual(result.dynamicFiles, [...valid].sort());
  for (const name of valid) {
    assert.ok(files.get(name).equals(original[name]), name);
  }
  assert.equal(files.has(createdName), false);
  assert.equal(
    files.get('store_capture_state.json').toString(),
    'mutated-control',
  );
  assert.equal(files.get('settings.cfg').toString(), 'locale=ko');
  const evidence = buildAndroidPersistentEvidence(original, result);
  assert.equal(evidence.persistent_data_dynamic_mutated_during_capture, true);
  assert.equal(evidence.persistent_data_mutated_during_capture, true);
  assert.equal(evidence.persistent_data_dynamic_restored_byte_exact, true);
  assert.deepEqual(
    evidence.persistent_data_dynamic_sha256_before,
    evidence.persistent_data_dynamic_sha256_restored,
  );
  assert.ok(Object.hasOwn(
    evidence.persistent_data_dynamic_sha256_observed,
    createdName,
  ));
  assert.equal(
    evidence.persistent_data_dynamic_sha256_observed[deletedName],
    null,
  );
  const anchored = buildAndroidPersistenceAnchor(
    evidence,
    original,
    result,
    { captureId: '5'.repeat(64), path: 'builds/evidence/persistence.json' },
  );
  assert.equal(assertAndroidPersistentReportEvidence({
    ...evidence,
    persistence_anchor: anchored.anchor,
  }, { anchorBytes: anchored.bytes }), true);
});
