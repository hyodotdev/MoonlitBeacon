import { createHash } from 'node:crypto';

// Production files that a direct-distribution launch can read or rewrite, plus
// the externally armed one-shot hero selector. Capture-owned handshakes are
// excluded and cleaned separately, but a pre-existing test_hero.request must be
// disabled during capture and restored byte-for-byte afterward.
export const ANDROID_CAPTURE_PERSISTENT_FILES = Object.freeze([
  'analytics.json',
  'analytics.json.tmp',
  'analytics_consent.revoked',
  'iap_entitlements.cfg',
  'iap_entitlements.cfg.bak',
  'iap_entitlements.cfg.bak.tmp',
  'iap_entitlements.cfg.tmp',
  'ladder.json',
  'ladder.json.tmp',
  'records.cfg',
  'records.cfg.tmp',
  'settings.cfg',
  'settings.cfg.tmp',
  'test_hero.request',
  'vault.cfg',
  'vault.cfg.bak',
  'vault.cfg.bak.tmp',
  'vault.cfg.tmp',
]);

function fail(message) {
  throw new Error(message);
}

function assertFileName(name) {
  if (typeof name !== 'string' || !/^[a-z0-9._-]+$/u.test(name)) {
    fail(`Unsafe Android persistent filename: ${String(name)}`);
  }
  return name;
}

export function decodeAndroidPrivateFileBase64(encoded, name) {
  assertFileName(name);
  const text = Buffer.isBuffer(encoded)
    ? encoded.toString('ascii')
    : String(encoded ?? '');
  const compact = text.replace(/\s/gu, '');
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u
    .test(compact)) {
    fail(`Android private file Base64 is invalid: ${name}`);
  }
  const decoded = Buffer.from(compact, 'base64');
  if (decoded.toString('base64') !== compact) {
    fail(`Android private file Base64 is not canonical: ${name}`);
  }
  return decoded;
}

export function isAndroidPrivateFileMissingBase64Error(stderr, name) {
  assertFileName(name);
  const text = Buffer.isBuffer(stderr)
    ? stderr.toString('utf8').trim()
    : String(stderr ?? '').trim();
  return text === `base64: files/${name}: No such file or directory`;
}

function snapshotValue(snapshot, name) {
  if (!Object.hasOwn(snapshot, name)) {
    fail(`Android persistent file snapshot is missing ${name}.`);
  }
  const value = snapshot[name];
  if (value !== null && !Buffer.isBuffer(value)) {
    fail(`Android persistent file snapshot value is not Buffer/null: ${name}`);
  }
  return value;
}

function assertSnapshotShape(snapshot, label) {
  if (snapshot === null || typeof snapshot !== 'object' || Array.isArray(snapshot)) {
    fail(`${label} Android persistent file snapshot is not an object.`);
  }
  const actual = Object.keys(snapshot).sort();
  const expected = [...ANDROID_CAPTURE_PERSISTENT_FILES].sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    fail(`${label} Android persistent file snapshot list does not match the fixed contract.`);
  }
  for (const name of ANDROID_CAPTURE_PERSISTENT_FILES) snapshotValue(snapshot, name);
  return snapshot;
}

export function captureAndroidPersistentSnapshot(readFile) {
  if (typeof readFile !== 'function') fail('Android persistent file reader is missing.');
  return Object.fromEntries(ANDROID_CAPTURE_PERSISTENT_FILES.map((name) => {
    const value = readFile(assertFileName(name));
    if (value !== null && !Buffer.isBuffer(value)) {
      fail(`Android persistent file reader did not return Buffer/null: ${name}`);
    }
    return [name, value === null ? null : Buffer.from(value)];
  }));
}

export function androidPersistentHashes(snapshot) {
  assertSnapshotShape(snapshot, 'hash');
  return Object.fromEntries(ANDROID_CAPTURE_PERSISTENT_FILES.map((name) => {
    const value = snapshotValue(snapshot, name);
    return [
      name,
      value === null ? null : createHash('sha256').update(value).digest('hex'),
    ];
  }));
}

export function androidPersistentSnapshotsEqual(left, right) {
  assertSnapshotShape(left, 'left');
  assertSnapshotShape(right, 'right');
  return ANDROID_CAPTURE_PERSISTENT_FILES.every((name) => {
    const leftValue = snapshotValue(left, name);
    const rightValue = snapshotValue(right, name);
    if (leftValue === null || rightValue === null) return leftValue === rightValue;
    return leftValue.equals(rightValue);
  });
}

export function restoreAndroidPersistentSnapshot(
  original,
  { readFile, writeFile, removeFile },
) {
  if (
    typeof readFile !== 'function'
    || typeof writeFile !== 'function'
    || typeof removeFile !== 'function'
  ) {
    fail('Android persistent file restore callback is incomplete.');
  }
  // Validate the entire source snapshot before changing any device file.
  const originalValues = new Map(ANDROID_CAPTURE_PERSISTENT_FILES.map((name) => [
    name,
    snapshotValue(original, name),
  ]));
  const errors = [];
  let observed = null;
  try {
    observed = captureAndroidPersistentSnapshot(readFile);
  } catch (error) {
    errors.push(new Error(`pre-restore state check failed: ${error.message}`));
  }
  // A failure on one replica must not strand every later Vault/settings file in
  // its capture-mutated state. Attempt every fixed target, then verify and fail.
  for (const [name, value] of originalValues) {
    try {
      if (value === null) removeFile(name);
      else writeFile(name, Buffer.from(value));
    } catch (error) {
      errors.push(new Error(`${name} restore failed: ${error.message}`));
    }
  }
  let restored = null;
  try {
    restored = captureAndroidPersistentSnapshot(readFile);
    if (!androidPersistentSnapshotsEqual(original, restored)) {
      errors.push(new Error('post-restore byte-exact verification mismatch'));
    }
  } catch (error) {
    errors.push(new Error(`post-restore state check failed: ${error.message}`));
  }
  if (errors.length > 0) {
    throw new AggregateError(
      errors,
      `Android persistent file restore is not complete (${errors.length} error(s)).`,
    );
  }
  return Object.freeze({
    files: [...ANDROID_CAPTURE_PERSISTENT_FILES],
    observed,
    restored,
    mutated: !androidPersistentSnapshotsEqual(original, observed),
  });
}

function assertHashMap(value, label) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    fail(`${label} hash map is not an object.`);
  }
  const actual = Object.keys(value).sort();
  const expected = [...ANDROID_CAPTURE_PERSISTENT_FILES].sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    fail(`${label} hash file list does not match the fixed contract.`);
  }
  for (const name of ANDROID_CAPTURE_PERSISTENT_FILES) {
    const hash = value[name];
    if (hash !== null && (typeof hash !== 'string' || !/^[0-9a-f]{64}$/u.test(hash))) {
      fail(`${label} ${name} SHA-256 is invalid.`);
    }
  }
  return value;
}

/**
 * Turn the byte snapshots into the single fail-closed report contract used by
 * both Android phone and tablet capture. The booleans below are derived only
 * after comparing the restored bytes; callers cannot merely claim success.
 */
export function buildAndroidPersistentEvidence(original, restoreResult) {
  assertSnapshotShape(original, 'original');
  if (
    restoreResult === null
    || typeof restoreResult !== 'object'
    || Array.isArray(restoreResult)
    || !Array.isArray(restoreResult.files)
    || JSON.stringify(restoreResult.files) !== JSON.stringify(ANDROID_CAPTURE_PERSISTENT_FILES)
  ) {
    fail('Android persistent file restore result file list does not match the fixed contract.');
  }
  assertSnapshotShape(restoreResult.observed, 'observed');
  assertSnapshotShape(restoreResult.restored, 'restored');
  if (!androidPersistentSnapshotsEqual(original, restoreResult.restored)) {
    fail('Android persistent file before/restored bytes do not match.');
  }
  const before = androidPersistentHashes(original);
  const observed = androidPersistentHashes(restoreResult.observed);
  const restored = androidPersistentHashes(restoreResult.restored);
  const mutated = !androidPersistentSnapshotsEqual(original, restoreResult.observed);
  if (restoreResult.mutated !== mutated) {
    fail('Android persistent file restore mutated value does not match observed bytes.');
  }
  const settingsName = 'settings.cfg';
  const evidence = {
    persistent_data_files: [...ANDROID_CAPTURE_PERSISTENT_FILES],
    persistent_data_sha256_before: before,
    persistent_data_sha256_observed: observed,
    persistent_data_sha256_restored: restored,
    persistent_data_mutated_during_capture: mutated,
    persistent_data_restored_byte_exact: true,
    persistent_data_unchanged: true,
    settings_restore: {
      original_present: original[settingsName] !== null,
      original_sha256: before[settingsName],
      observed_sha256: observed[settingsName],
      restored_sha256: restored[settingsName],
      byte_exact: true,
    },
  };
  return Object.freeze(evidence);
}

/**
 * Persist a separate, non-sensitive anchor for the three capture stages.
 * Hashes cover every production file; only settings.cfg bytes are retained so
 * the release gate can independently recompute at least one real device file
 * instead of accepting a self-consistent all-null report. Purchase, score and
 * vault contents are never copied into the build evidence.
 */
export function buildAndroidPersistenceAnchor(
  evidence,
  original,
  restoreResult,
  { captureId, path } = {},
) {
  if (typeof captureId !== 'string' || !/^[0-9a-f]{64}$/u.test(captureId)) {
    fail('Android persistence anchor capture ID is invalid.');
  }
  if (typeof path !== 'string' || path.trim() === '') {
    fail('Android persistence anchor path is missing.');
  }
  assertSnapshotShape(original, 'anchor original');
  assertSnapshotShape(restoreResult?.observed, 'anchor observed');
  assertSnapshotShape(restoreResult?.restored, 'anchor restored');
  const settings = {
    original_base64: original['settings.cfg']?.toString('base64') ?? null,
    observed_base64:
      restoreResult.observed['settings.cfg']?.toString('base64') ?? null,
    restored_base64:
      restoreResult.restored['settings.cfg']?.toString('base64') ?? null,
  };
  if (settings.observed_base64 === null) {
    fail('settings.cfg physical anchor is missing after the full Android capture.');
  }
  const transcript = {
    schema: 1,
    capture_id: captureId,
    persistent_data_files: [...ANDROID_CAPTURE_PERSISTENT_FILES],
    persistent_data_sha256_before: evidence.persistent_data_sha256_before,
    persistent_data_sha256_observed: evidence.persistent_data_sha256_observed,
    persistent_data_sha256_restored: evidence.persistent_data_sha256_restored,
    settings_bytes: settings,
  };
  const bytes = Buffer.from(`${JSON.stringify(transcript, null, 2)}\n`, 'utf8');
  return Object.freeze({
    anchor: Object.freeze({
      schema: 1,
      capture_id: captureId,
      path,
      sha256: createHash('sha256').update(bytes).digest('hex'),
    }),
    bytes,
  });
}

function decodeCanonicalAnchorBase64(value, label) {
  if (value === null) return null;
  if (typeof value !== 'string' || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u
    .test(value)) {
    fail(`Android persistence anchor ${label} Base64 is invalid.`);
  }
  const bytes = Buffer.from(value, 'base64');
  if (bytes.toString('base64') !== value) {
    fail(`Android persistence anchor ${label} Base64 is not canonical.`);
  }
  return bytes;
}

/** Validate serialized persistence evidence before it is written/published. */
export function assertAndroidPersistentReportEvidence(
  report,
  { anchorBytes = null } = {},
) {
  if (report === null || typeof report !== 'object' || Array.isArray(report)) {
    fail('Android capture report is not an object.');
  }
  if (
    !Array.isArray(report.persistent_data_files)
    || JSON.stringify(report.persistent_data_files)
      !== JSON.stringify(ANDROID_CAPTURE_PERSISTENT_FILES)
  ) {
    fail('Android capture report persistent file list does not match the fixed contract.');
  }
  const before = assertHashMap(
    report.persistent_data_sha256_before,
    'persistent_data_sha256_before',
  );
  assertHashMap(
    report.persistent_data_sha256_observed,
    'persistent_data_sha256_observed',
  );
  const restored = assertHashMap(
    report.persistent_data_sha256_restored,
    'persistent_data_sha256_restored',
  );
  if (JSON.stringify(before) !== JSON.stringify(restored)) {
    fail('Android capture report before/restored hashes differ.');
  }
  if (
    report.persistent_data_mutated_during_capture
      !== (JSON.stringify(before) !== JSON.stringify(
        report.persistent_data_sha256_observed,
      ))
    || report.persistent_data_restored_byte_exact !== true
    || report.persistent_data_unchanged !== true
  ) {
    fail('Android capture report byte-exact restore flags are invalid.');
  }
  const settings = report.settings_restore;
  const expectedSettingsKeys = [
    'byte_exact',
    'observed_sha256',
    'original_present',
    'original_sha256',
    'restored_sha256',
  ];
  if (
    settings === null
    || typeof settings !== 'object'
    || Array.isArray(settings)
    || JSON.stringify(Object.keys(settings).sort())
      !== JSON.stringify(expectedSettingsKeys)
    || typeof settings.original_present !== 'boolean'
    || settings.byte_exact !== true
    || settings.original_sha256 !== before['settings.cfg']
    || settings.restored_sha256 !== restored['settings.cfg']
    || settings.observed_sha256
      !== report.persistent_data_sha256_observed['settings.cfg']
    || settings.observed_sha256 === null
    || settings.original_present !== (settings.original_sha256 !== null)
  ) {
    fail('Android capture report settings.cfg restore proof is invalid.');
  }
  const anchor = report.persistence_anchor;
  if (
    anchor === null
    || typeof anchor !== 'object'
    || Array.isArray(anchor)
    || JSON.stringify(Object.keys(anchor).sort())
      !== JSON.stringify(['capture_id', 'path', 'schema', 'sha256'])
    || anchor.schema !== 1
    || typeof anchor.capture_id !== 'string'
    || !/^[0-9a-f]{64}$/u.test(anchor.capture_id)
    || typeof anchor.path !== 'string'
    || anchor.path.trim() === ''
    || typeof anchor.sha256 !== 'string'
    || !/^[0-9a-f]{64}$/u.test(anchor.sha256)
  ) {
    fail('Android capture report persistence anchor is invalid.');
  }
  if (anchorBytes !== null) {
    if (!Buffer.isBuffer(anchorBytes)) {
      fail('Android persistence anchor source bytes is not a Buffer.');
    }
    if (createHash('sha256').update(anchorBytes).digest('hex') !== anchor.sha256) {
      fail('Android persistence anchor source hash does not match the report.');
    }
    let transcript;
    try {
      transcript = JSON.parse(anchorBytes.toString('utf8'));
    } catch (error) {
      fail(`Android persistence anchor JSON is invalid: ${error.message}`);
    }
    const expectedTranscriptKeys = [
      'capture_id',
      'persistent_data_files',
      'persistent_data_sha256_before',
      'persistent_data_sha256_observed',
      'persistent_data_sha256_restored',
      'schema',
      'settings_bytes',
    ];
    if (
      transcript === null
      || typeof transcript !== 'object'
      || Array.isArray(transcript)
      || JSON.stringify(Object.keys(transcript).sort())
        !== JSON.stringify(expectedTranscriptKeys)
      || transcript.schema !== 1
      || transcript.capture_id !== anchor.capture_id
      || JSON.stringify(transcript.persistent_data_files)
        !== JSON.stringify(report.persistent_data_files)
      || JSON.stringify(transcript.persistent_data_sha256_before)
        !== JSON.stringify(before)
      || JSON.stringify(transcript.persistent_data_sha256_observed)
        !== JSON.stringify(report.persistent_data_sha256_observed)
      || JSON.stringify(transcript.persistent_data_sha256_restored)
        !== JSON.stringify(restored)
    ) {
      fail('Android persistence anchor transcript does not match the report.');
    }
    const anchoredSettings = transcript.settings_bytes;
    if (
      anchoredSettings === null
      || typeof anchoredSettings !== 'object'
      || Array.isArray(anchoredSettings)
      || JSON.stringify(Object.keys(anchoredSettings).sort())
        !== JSON.stringify([
          'observed_base64', 'original_base64', 'restored_base64',
        ])
    ) {
      fail('Android persistence anchor settings bytes are invalid.');
    }
    const anchoredValues = {
      original: decodeCanonicalAnchorBase64(
        anchoredSettings.original_base64,
        'original settings',
      ),
      observed: decodeCanonicalAnchorBase64(
        anchoredSettings.observed_base64,
        'observed settings',
      ),
      restored: decodeCanonicalAnchorBase64(
        anchoredSettings.restored_base64,
        'restored settings',
      ),
    };
    const anchoredHashes = Object.fromEntries(Object.entries(anchoredValues).map(
      ([stage, value]) => [
        stage,
        value === null ? null : createHash('sha256').update(value).digest('hex'),
      ],
    ));
    if (
      anchoredValues.observed === null
      || anchoredHashes.original !== before['settings.cfg']
      || anchoredHashes.observed
        !== report.persistent_data_sha256_observed['settings.cfg']
      || anchoredHashes.restored !== restored['settings.cfg']
    ) {
      fail('Android persistence anchor settings bytes hash does not match the report.');
    }
  }
  return true;
}
