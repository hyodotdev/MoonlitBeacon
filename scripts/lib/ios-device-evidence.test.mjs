import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  chmodSync,
  existsSync,
  lstatSync,
  mkdtempSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  symlinkSync,
  utimesSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';
import {
  assertByteExactRestoration,
  assertCompletePng,
  assertCompleteIosCaptureManifest,
  assertFrozenIosInstallArtifact,
  assertInstalledIosApp,
  assertPrivateXcodeScreenshotInbox,
  assertPhysicalIosDevice,
  assertPhysicalIosSafeLayout,
  assertRsdIosDeviceIdentity,
  assertStableIosArenaCaptureState,
  assertStableIosPersistentSnapshots,
  coreDeviceRsdPortCandidates,
  createDeferredCancellation,
  ensurePrivateDirectory,
  iosAppTreeSha256,
  isDevicectlReportedTimeout,
  IOS_CODE_PERSISTENT_FILES,
  IOS_XCODE_HANDOFF_CAPTURE_METHOD,
  pngSize,
  publishXcodeScreenshotHandoff,
  removeXcodeScreenshotHandoffEntries,
  sealPrivateRegularFile,
  settleWithMandatoryCleanup,
  withEphemeralFilesystemPath,
  withImmutableFilesystemPath,
  waitForXcodeScreenshotHandoff,
  waitForPendingHostSignalHandlers,
  writePrivateFileExclusive,
} from './ios-device-evidence.mjs';

const HASH = (value) => createHash('sha256').update(value).digest('hex');
const RSD_NULL_XCODE_EVIDENCE = Object.freeze(Object.fromEntries([
  'xcode_handoff_nonce',
  'xcode_handoff_expected_filename',
  'xcode_handoff_requested_at',
  'xcode_handoff_requested_at_unix_ms',
  'xcode_handoff_birthtime_unix_ms',
  'xcode_handoff_mtime_unix_ms',
  'xcode_handoff_accepted_at',
  'xcode_handoff_stable_observations',
  'xcode_handoff_complete_png_decoded',
  'xcode_handoff_receipt',
  'xcode_handoff_receipt_sha256',
  'xcode_activation_process_id',
  'xcode_activation_launch_path',
  'xcode_activation_launch_sha256',
  'xcode_activation_processes_path',
  'xcode_activation_processes_sha256',
  'xcode_handoff_process_id',
  'xcode_handoff_device_details_before_path',
  'xcode_handoff_device_details_before_sha256',
  'xcode_handoff_processes_before_path',
  'xcode_handoff_processes_before_sha256',
  'xcode_handoff_device_details_after_path',
  'xcode_handoff_device_details_after_sha256',
  'xcode_handoff_processes_after_path',
  'xcode_handoff_processes_after_sha256',
].map((field) => [field, null])));
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

function gdscriptFiles(root) {
  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = join(root, entry.name);
    if (entry.isDirectory()) return gdscriptFiles(path);
    return entry.isFile() && entry.name.endsWith('.gd') ? [path] : [];
  });
}

function png(width, height, {
  trailingCompressedData = false,
  forbiddenGrayscalePalette = false,
  indexedPixel = null,
} = {}) {
  const crc32 = (bytes) => {
    let crc = 0xffffffff;
    for (const byte of bytes) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit += 1) {
        crc = (crc >>> 1) ^ ((crc & 1) === 1 ? 0xedb88320 : 0);
      }
    }
    return (crc ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const typeBytes = Buffer.from(type, 'ascii');
    const result = Buffer.alloc(data.length + 12);
    result.writeUInt32BE(data.length, 0);
    typeBytes.copy(result, 4);
    data.copy(result, 8);
    result.writeUInt32BE(crc32(Buffer.concat([typeBytes, data])), data.length + 8);
    return result;
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 1;
  ihdr[9] = indexedPixel === null ? 0 : 3;
  const rowBytes = Math.ceil(width / 8);
  const raw = Buffer.alloc(height * (rowBytes + 1));
  if (indexedPixel !== null) {
    for (let row = 0; row < height; row += 1) {
      raw[(row * (rowBytes + 1)) + 1] = indexedPixel << 7;
    }
  }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    ...(forbiddenGrayscalePalette
      ? [chunk('PLTE', Buffer.from([0, 0, 0]))]
      : []),
    ...(indexedPixel !== null
      ? [chunk('PLTE', Buffer.from([0, 0, 0]))]
      : []),
    chunk('IDAT', Buffer.concat([
      deflateSync(raw),
      ...(trailingCompressedData ? [Buffer.from('junk')] : []),
    ])),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function withTemporaryDirectory(prefix, operation) {
  const root = mkdtempSync(join(tmpdir(), prefix));
  try {
    return operation(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

async function withTemporaryDirectoryAsync(prefix, operation) {
  const root = mkdtempSync(join(tmpdir(), prefix));
  try {
    return await operation(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function arenaReadyState(overrides = {}) {
  return {
    schema: 1,
    nonce: 'a'.repeat(64),
    observation: 1,
    kind: 'arena_ready',
    game_locale: 'ko',
    viewport_rect: [0, 0, 808, 360],
    safe_rect: [14, 14, 780, 332],
    safe_area_inside_viewport: true,
    safe_ui_ready: true,
    hud_left_rect: [20, 14, 178, 110],
    hud_left_inside_safe_area: true,
    hud_right_rect: [624, 14, 164, 48],
    hud_right_inside_safe_area: true,
    pause_button_rect: [754, 44, 26, 24],
    pause_button_inside_safe_area: true,
    dash_rect: [728, 284, 52, 52],
    dash_inside_safe_area: true,
    move_stick_rect: [14, 14, 780, 332],
    move_stick_inside_safe_area: true,
    boss_rect: [254, 314, 300, 24],
    boss_inside_safe_area: true,
    banner_rect: [184, 142, 440, 30],
    banner_inside_safe_area: true,
    scene: 'arena',
    ready: true,
    over: false,
    ...overrides,
  };
}

function devicePayload(overrides = {}) {
  return {
    result: {
      identifier: '77322685-379D-50CE-894E-FCB3C2A27163',
      hardwareProperties: {
        reality: 'physical',
        deviceType: 'iPad',
        productType: 'iPad16,1',
        udid: '00008130-001929642642001C',
        marketingName: 'iPad mini (A17 Pro)',
      },
      deviceProperties: {
        bootState: 'booted',
        developerModeStatus: 'enabled',
        name: "Hyo's iPad",
        osVersionNumber: '26.5.2',
        osBuildUpdate: '23F84',
      },
      connectionProperties: {
        pairingState: 'paired',
        transportType: 'wired',
        tunnelState: 'connected',
        tunnelIPAddress: 'fd3b:a284:cdf6::1',
      },
      ...overrides,
    },
  };
}

function rsdPayload(overrides = {}) {
  return {
    MessageType: 'Handshake',
    Properties: {
      UniqueDeviceID: '00008130-001929642642001C',
      ProductType: 'iPad16,1',
      OSVersion: '26.5.2',
      BuildVersion: '23F84',
      IsVirtualDevice: false,
      SerialNumber: 'must-not-enter-evidence',
      ...overrides,
    },
  };
}

test('reads native PNG size and rejects non-PNG', () => {
  const bytes = png(2266, 1488);
  assert.deepEqual(pngSize(bytes), { width: 2266, height: 1488 });
  assert.deepEqual(assertCompletePng(bytes), { width: 2266, height: 1488 });
  assert.throws(() => pngSize(Buffer.from('fake')), /is not a PNG/u);
  const corrupt = Buffer.from(bytes);
  corrupt[50] ^= 0x01;
  assert.throws(() => assertCompletePng(corrupt), /CRC|decode/u);
  assert.throws(() => assertCompletePng(bytes.subarray(0, -1)), /IEND|chunk/u);
  assert.throws(
    () => assertCompletePng(png(32, 16, { trailingCompressedData: true })),
    /after the PNG IDAT zlib stream/u,
  );
  assert.throws(
    () => assertCompletePng(png(32, 16, { forbiddenGrayscalePalette: true })),
    /PLTE/u,
  );
  assert.deepEqual(
    assertCompletePng(png(1, 1, { indexedPixel: 0 })),
    { width: 1, height: 1 },
  );
  assert.throws(
    () => assertCompletePng(png(1, 1, { indexedPixel: 1 })),
    /indexed pixel/u,
  );
});

test('Xcode handoff accepts only a new 0600 iPad PNG in an external 0700 inbox', async () => {
  await withTemporaryDirectoryAsync('moonlit-xcode-valid-', async (root) => {
    const inboxPath = join(root, 'inbox');
    mkdirSync(inboxPath, { mode: 0o700 });
    const inbox = assertPrivateXcodeScreenshotInbox(inboxPath, REPO_ROOT);
    const nonce = '1'.repeat(64);
    const expectedFilename = `moonlit-${nonce}.png`;
    const requestedAtMs = Date.now();
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
    const bytes = png(2266, 1488);
    const source = join(root, 'xcode.png');
    writeFileSync(source, bytes);
    publishXcodeScreenshotHandoff({
      inbox,
      sourcePath: source,
      expectedFilename,
      nonce,
      requestedAtMs,
    });

    const accepted = await waitForXcodeScreenshotHandoff({
      inbox,
      expectedFilename,
      nonce,
      requestedAtMs,
      forbiddenSha256: new Set(),
      // CRC/zlib checks for a 2266x1488 PNG can take longer than 0.5s on a shared
      // CI runner. The file is already published, so a generous success wait still
      // finishes immediately, while the missing/tampered timeout cases keep a short limit.
      timeoutMs: 5_000,
      pollIntervalMs: 5,
    });
    assert.deepEqual(accepted.size, { width: 2266, height: 1488 });
    assert.equal(accepted.sha256, HASH(bytes));
    assert.ok(accepted.birthtimeMs >= requestedAtMs);
    assert.ok(accepted.mtimeMs >= requestedAtMs);
    assert.equal(accepted.receipt.file_fsync_before_rename, true);
    removeXcodeScreenshotHandoffEntries({ inbox, expectedFilename, nonce });
  });
});

test('Xcode handoff rejects direct final writes and tampered mtimes', async () => {
  await withTemporaryDirectoryAsync('moonlit-xcode-stale-', async (root) => {
    const inboxPath = join(root, 'inbox');
    mkdirSync(inboxPath, { mode: 0o700 });
    const inbox = assertPrivateXcodeScreenshotInbox(inboxPath, REPO_ROOT);
    const staleNonce = '2'.repeat(64);
    const staleName = `moonlit-${staleNonce}.png`;
    writeFileSync(join(inboxPath, staleName), png(2266, 1488), { mode: 0o600 });
    await assert.rejects(
      waitForXcodeScreenshotHandoff({
        inbox,
        expectedFilename: staleName,
        nonce: staleNonce,
        requestedAtMs: Date.now(),
        forbiddenSha256: new Set(),
        timeoutMs: 30,
        pollIntervalMs: 5,
      }),
      /Did not receive Xcode screenshot handoff within/u,
    );
    removeXcodeScreenshotHandoffEntries({ inbox, expectedFilename: staleName, nonce: staleNonce });

    const timestampNonce = '3'.repeat(64);
    const timestampName = `moonlit-${timestampNonce}.png`;
    const timestampRequest = Date.now();
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
    const timestampPath = join(inboxPath, timestampName);
    const source = join(root, 'timestamp.png');
    writeFileSync(source, png(2266, 1488));
    publishXcodeScreenshotHandoff({
      inbox,
      sourcePath: source,
      expectedFilename: timestampName,
      nonce: timestampNonce,
      requestedAtMs: timestampRequest,
    });
    const oldTime = new Date(timestampRequest - 1_000);
    utimesSync(timestampPath, oldTime, oldTime);
    await assert.rejects(
      waitForXcodeScreenshotHandoff({
        inbox,
        expectedFilename: timestampName,
        nonce: timestampNonce,
        requestedAtMs: timestampRequest,
        forbiddenSha256: new Set(),
        timeoutMs: 500,
        pollIntervalMs: 5,
      }),
      /receipt/u,
    );
    removeXcodeScreenshotHandoffEntries({
      inbox,
      expectedFilename: timestampName,
      nonce: timestampNonce,
    });
  });
});

test('Xcode handoff rejects receipt byte rewrites between stable observations', async () => {
  await withTemporaryDirectoryAsync('moonlit-xcode-receipt-rewrite-', async (root) => {
    const inboxPath = join(root, 'inbox');
    mkdirSync(inboxPath, { mode: 0o700 });
    const inbox = assertPrivateXcodeScreenshotInbox(inboxPath, REPO_ROOT);
    const nonce = 'a'.repeat(64);
    const expectedFilename = `moonlit-${nonce}.png`;
    const requestedAtMs = Date.now();
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
    const source = join(root, 'receipt-rewrite.png');
    writeFileSync(source, png(2266, 1488));
    const published = publishXcodeScreenshotHandoff({
      inbox,
      sourcePath: source,
      expectedFilename,
      nonce,
      requestedAtMs,
    });
    const originalReceipt = readFileSync(published.receiptPath);
    const originalStat = lstatSync(published.receiptPath);
    const reversedReceipt = Buffer.from(`${JSON.stringify(Object.fromEntries(
      Object.entries(JSON.parse(originalReceipt.toString('utf8'))).reverse(),
    ))}\n`, 'utf8');
    assert.equal(reversedReceipt.length, originalReceipt.length);
    const tamper = setTimeout(() => {
      writeFileSync(published.receiptPath, reversedReceipt, { mode: 0o600 });
      utimesSync(
        published.receiptPath,
        new Date(originalStat.atimeMs),
        new Date(originalStat.mtimeMs),
      );
    }, 10);
    try {
      await assert.rejects(
        waitForXcodeScreenshotHandoff({
          inbox,
          expectedFilename,
          nonce,
          requestedAtMs,
          forbiddenSha256: new Set(),
          // On shared CI, large PNG verification can exceed 0.5s under parallel load.
          timeoutMs: 5_000,
          pollIntervalMs: 50,
        }),
        /changed between stable observations/u,
      );
    } finally {
      clearTimeout(tamper);
      removeXcodeScreenshotHandoffEntries({ inbox, expectedFilename, nonce });
    }
  });
});

test('Xcode handoff rejects symlinks and reused PNG hashes', async () => {
  await withTemporaryDirectoryAsync('moonlit-xcode-reject-', async (root) => {
    const inboxPath = join(root, 'inbox');
    mkdirSync(inboxPath, { mode: 0o700 });
    const inbox = assertPrivateXcodeScreenshotInbox(inboxPath, REPO_ROOT);
    const target = join(root, 'source.png');
    writeFileSync(target, png(2266, 1488), { mode: 0o600 });
    const symlinkNonce = '4'.repeat(64);
    const symlinkName = `moonlit-${symlinkNonce}.png`;
    symlinkSync(target, join(inboxPath, symlinkName));
    writeFileSync(
      join(inboxPath, `${symlinkName}.receipt.json`),
      '{}\n',
      { mode: 0o600 },
    );
    await assert.rejects(
      waitForXcodeScreenshotHandoff({
        inbox,
        expectedFilename: symlinkName,
        nonce: symlinkNonce,
        requestedAtMs: Date.now() - 1,
        forbiddenSha256: new Set(),
        timeoutMs: 500,
        pollIntervalMs: 5,
      }),
      /is not a real regular file/u,
    );
    removeXcodeScreenshotHandoffEntries({
      inbox,
      expectedFilename: symlinkName,
      nonce: symlinkNonce,
    });

    const reusedNonce = '5'.repeat(64);
    const reusedName = `moonlit-${reusedNonce}.png`;
    const requestedAtMs = Date.now();
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
    const bytes = png(2266, 1488);
    const reusedSource = join(root, 'reused.png');
    writeFileSync(reusedSource, bytes);
    publishXcodeScreenshotHandoff({
      inbox,
      sourcePath: reusedSource,
      expectedFilename: reusedName,
      nonce: reusedNonce,
      requestedAtMs,
    });
    await assert.rejects(
      waitForXcodeScreenshotHandoff({
        inbox,
        expectedFilename: reusedName,
        nonce: reusedNonce,
        requestedAtMs,
        forbiddenSha256: new Set([HASH(bytes)]),
        timeoutMs: 500,
        pollIntervalMs: 5,
      }),
      /PNG hash duplicates a previous capture/u,
    );
    removeXcodeScreenshotHandoffEntries({
      inbox,
      expectedFilename: reusedName,
      nonce: reusedNonce,
    });
  });
});

test('Xcode handoff fails after the timeout when no file arrives', async () => {
  await withTemporaryDirectoryAsync('moonlit-xcode-timeout-', async (root) => {
    const inboxPath = join(root, 'inbox');
    mkdirSync(inboxPath, { mode: 0o700 });
    const inbox = assertPrivateXcodeScreenshotInbox(inboxPath, REPO_ROOT);
    const nonce = '6'.repeat(64);
    await assert.rejects(
      waitForXcodeScreenshotHandoff({
        inbox,
        expectedFilename: `moonlit-${nonce}.png`,
        nonce,
        requestedAtMs: Date.now(),
        forbiddenSha256: new Set(),
        timeoutMs: 20,
        pollIntervalMs: 5,
      }),
      /Did not receive Xcode screenshot handoff within 0\.02s/u,
    );
  });
});

test('Xcode handoff cancel probe fully stops the polling work', async () => {
  await withTemporaryDirectoryAsync('moonlit-xcode-cancel-', async (root) => {
    const inboxPath = join(root, 'inbox');
    mkdirSync(inboxPath, { mode: 0o700 });
    const inbox = assertPrivateXcodeScreenshotInbox(inboxPath, REPO_ROOT);
    const nonce = 'a'.repeat(64);
    const cancellation = createDeferredCancellation();
    let probes = 0;
    await assert.rejects(
      waitForXcodeScreenshotHandoff({
        inbox,
        expectedFilename: `moonlit-${nonce}.png`,
        nonce,
        requestedAtMs: Date.now(),
        forbiddenSha256: new Set(),
        timeoutMs: 5_000,
        pollIntervalMs: 1,
        cancellationProbe: () => {
          probes += 1;
          if (probes === 2) cancellation.request('SIGINT');
          cancellation.throwIfRequested();
        },
      }),
      (error) => error.code === 'ECANCELED' && error.signal === 'SIGINT',
    );
    assert.equal(probes, 2);
  });
});

test('Xcode handoff failure cleanup deletes only exact nonce entries and never directories', () => {
  withTemporaryDirectory('moonlit-xcode-cleanup-', (root) => {
    const inboxPath = join(root, 'inbox');
    mkdirSync(inboxPath, { mode: 0o700 });
    const inbox = assertPrivateXcodeScreenshotInbox(inboxPath, REPO_ROOT);
    const nonce = '8'.repeat(64);
    const expectedFilename = `moonlit-${nonce}.png`;
    const unrelated = join(inboxPath, 'keep.txt');
    writeFileSync(unrelated, 'keep', { mode: 0o600 });
    writeFileSync(join(inboxPath, expectedFilename), 'invalid', { mode: 0o644 });
    writeFileSync(join(inboxPath, `${expectedFilename}.receipt.json`), '{}\n', { mode: 0o600 });
    removeXcodeScreenshotHandoffEntries({ inbox, expectedFilename, nonce });
    assert.equal(existsSync(join(inboxPath, expectedFilename)), false);
    assert.equal(existsSync(join(inboxPath, `${expectedFilename}.receipt.json`)), false);
    assert.equal(readFileSync(unrelated, 'utf8'), 'keep');

    const finalPath = join(inboxPath, expectedFilename);
    const partialPath = join(inboxPath, `.${expectedFilename}.partial-${nonce}`);
    const receiptPath = join(inboxPath, `${expectedFilename}.receipt.json`);
    const receiptPartialPath = join(
      inboxPath,
      `.${expectedFilename}.receipt.json.partial-${nonce}`,
    );
    mkdirSync(finalPath);
    writeFileSync(partialPath, 'partial', { mode: 0o600 });
    writeFileSync(receiptPath, '{}\n', { mode: 0o600 });
    writeFileSync(receiptPartialPath, 'partial receipt', { mode: 0o600 });
    assert.throws(
      () => removeXcodeScreenshotHandoffEntries({ inbox, expectedFilename, nonce }),
      /Cannot delete directory/u,
    );
    assert.equal(lstatSync(finalPath).isDirectory(), true);
    assert.equal(existsSync(partialPath), false);
    assert.equal(existsSync(receiptPath), false);
    assert.equal(existsSync(receiptPartialPath), false);
    assert.equal(readFileSync(unrelated, 'utf8'), 'keep');
  });
});

test('Xcode handoff immediately rejects device/process continuity failures while waiting', async () => {
  await withTemporaryDirectoryAsync('moonlit-xcode-continuity-', async (root) => {
    const inboxPath = join(root, 'inbox');
    mkdirSync(inboxPath, { mode: 0o700 });
    const inbox = assertPrivateXcodeScreenshotInbox(inboxPath, REPO_ROOT);
    let probes = 0;
    const nonce = '7'.repeat(64);
    await assert.rejects(
      waitForXcodeScreenshotHandoff({
        inbox,
        expectedFilename: `moonlit-${nonce}.png`,
        nonce,
        requestedAtMs: Date.now(),
        forbiddenSha256: new Set(),
        timeoutMs: 100,
        pollIntervalMs: 2,
        continuityProbeIntervalMs: 1,
        continuityProbe: ({ remainingMs, deadlineMs }) => {
          assert.ok(remainingMs > 0 && deadlineMs > Date.now());
          probes += 1;
          throw new Error('foreground game process PID mismatch');
        },
      }),
      /process PID mismatch/u,
    );
    assert.equal(probes, 1);
  });
});

test('Xcode handoff rechecks the hard deadline after the continuity probe', async () => {
  await withTemporaryDirectoryAsync('moonlit-xcode-hard-deadline-', async (root) => {
    const inboxPath = join(root, 'inbox');
    mkdirSync(inboxPath, { mode: 0o700 });
    const inbox = assertPrivateXcodeScreenshotInbox(inboxPath, REPO_ROOT);
    const nonce = '9'.repeat(64);
    let receivedBudget = null;
    await assert.rejects(
      waitForXcodeScreenshotHandoff({
        inbox,
        expectedFilename: `moonlit-${nonce}.png`,
        nonce,
        requestedAtMs: Date.now(),
        forbiddenSha256: new Set(),
        timeoutMs: 20,
        pollIntervalMs: 2,
        continuityProbeIntervalMs: 1,
        continuityProbe: ({ remainingMs }) => {
          receivedBudget = remainingMs;
          const stopAt = Date.now() + 25;
          while (Date.now() < stopAt) {
            // Model a bounded synchronous CoreDevice child consuming its budget.
          }
        },
      }),
      /Did not receive Xcode screenshot handoff within/u,
    );
    assert.ok(receivedBudget > 0 && receivedBudget <= 20);
  });
});

test('iOS missile proof pins the store asset locale to match the report', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  const captureStart = source.indexOf('async function captureMissileCore(');
  const captureEnd = source.indexOf('\nasync function captureLocale(', captureStart);
  assert.ok(captureStart >= 0 && captureEnd > captureStart);
  const captureSource = source.slice(captureStart, captureEnd);
  const missileReady = captureSource.indexOf('if (missileBefore === null)');
  const cleanUiReady = captureSource.indexOf("await waitCleanUi('combat')");
  const runtimeBefore = captureSource.indexOf(
    'let runtimeBefore = await waitRuntimeState(',
  );
  const screenshot = captureSource.indexOf('const screenshot = captureMethod');
  assert.ok(missileReady >= 0);
  assert.ok(cleanUiReady > missileReady);
  assert.ok(runtimeBefore > cleanUiReady);
  assert.ok(screenshot > runtimeBefore);
  assert.match(
    captureSource,
    /const missileBeforeProof = \{[\s\S]*?\.\.\.missileBefore,[\s\S]*?asset_locale: locale\.asset,/u,
  );
  assert.match(
    captureSource,
    /const missileAfterProof = \{[\s\S]*?\.\.\.missileAfter,[\s\S]*?asset_locale: locale\.asset,/u,
  );
  assert.match(captureSource, /before: missileBeforeProof/u);
  assert.match(captureSource, /after: missileAfterProof/u);
  assert.match(captureSource, /missile_before: missileBeforeProof/u);
  assert.match(captureSource, /missile_after: missileAfterProof/u);
});

test('Xcode device capture uses VFX 0.2 and Guardian transition 1.0 time scales', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  const launchStart = source.indexOf('function launchApp(');
  const launchEnd = source.indexOf('\nfunction runningGameProcesses(', launchStart);
  const launchSource = source.slice(launchStart, launchEnd);
  assert.match(
    launchSource,
    /captureMethod === IOS_XCODE_HANDOFF_CAPTURE_METHOD/u,
  );
  assert.match(
    launchSource,
    /label\.endsWith\('-guardian'\) \? '1\.0' : '0\.2'/u,
  );
  assert.match(
    launchSource,
    /launchArguments\.push\('--time-scale', xcodeTimeScale\)/u,
  );
  assert.equal(
    (launchSource.match(/launchArguments\.push\('--time-scale'/gu) ?? []).length,
    1,
  );
  assert.match(
    launchSource,
    /payload\?\.result\?\.launchOptions\?\.arguments/u,
  );
  assert.match(
    launchSource,
    /JSON\.stringify\(actualRuntimeArguments\)\s*!==\s*JSON\.stringify\(expectedRuntimeArguments\)/u,
  );
  assert.match(
    launchSource,
    /receiptArguments\.indexOf\(ACTIVE_BUNDLE_ID\)/u,
  );
  assert.match(
    launchSource,
    /JSON\.stringify\(receiptRuntimeArguments\)\s*!==\s*JSON\.stringify\(expectedRuntimeArguments\)/u,
  );
  assert.match(launchSource, /payload\?\.result\?\.deviceIdentifier !== options\.deviceId/u);
  assert.match(launchSource, /commandType !== 'devicectl\.device\.process\.launch'/u);
  assert.match(launchSource, /activatedWhenStarted !== true/u);
  assert.match(launchSource, /terminateExistingInstances !== true/u);
  assert.match(launchSource, /startStopped !== false/u);
  const bundleIndex = launchSource.indexOf('ACTIVE_BUNDLE_ID,');
  const timeScaleIndex = launchSource.indexOf("launchArguments.push('--time-scale'");
  const runIndex = launchSource.indexOf('runDevicectlJson(');
  assert.ok(bundleIndex >= 0 && timeScaleIndex > bundleIndex && runIndex > timeScaleIndex);
});

test('every isolated iOS process proof filters by the install receipt exact executable', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  assert.match(
    source,
    /captureExecutableUrl = installEvidence\.executableUrl;/u,
  );
  const exactStart = source.indexOf('function exactExecutableProcesses(');
  const exactEnd = source.indexOf('\nfunction quiesceProductionApp(', exactStart);
  assert.ok(exactStart >= 0 && exactEnd > exactStart);
  const exactSource = source.slice(exactStart, exactEnd);
  assert.match(
    exactSource,
    /`executable\.absoluteString == '\$\{executableUrl\}'`/u,
  );
  const start = source.indexOf('function runningGameProcesses(');
  const end = source.indexOf('\nfunction terminateGameProcess(', start);
  const processSource = source.slice(start, end);
  assert.doesNotMatch(processSource, /captureMethod ===/u);
  assert.match(
    processSource,
    /return exactExecutableProcesses\(captureExecutableUrl, label, timeout\);/u,
  );
  assert.match(processSource, /return allRunningGameProcesses\(label, timeout\);/u);
  const continuityStart = source.indexOf('function assertXcodeHandoffContinuity(');
  const continuityEnd = source.indexOf('\nasync function nativeScreenshot(', continuityStart);
  assert.match(
    source.slice(continuityStart, continuityEnd),
    /allRunningGameProcesses\(`\$\{label\}-processes`, remainingMs\)/u,
  );
});

test('Xcode capture reactivates the same PID before SIGSTOP and broadly blocks competing apps', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  const reactivateStart = source.indexOf('function reactivateCaptureProcess(');
  const reactivateEnd = source.indexOf('\nfunction allRunningGameProcesses(', reactivateStart);
  const reactivate = source.slice(reactivateStart, reactivateEnd);
  assert.match(reactivate, /quiesceProductionApp\(/u);
  assert.match(reactivate, /reactivatedPid !== pid/u);
  assert.match(reactivate, /activatedWhenStarted !== true/u);
  assert.match(reactivate, /terminateExistingInstances !== false/u);
  assert.match(reactivate, /allRunningGameProcesses\(/u);

  const runtimeStart = source.indexOf('async function captureRuntime(');
  const runtimeEnd = source.indexOf('\nfunction discardUnpublishedCapture(', runtimeStart);
  const runtime = source.slice(runtimeStart, runtimeEnd);
  const activate = runtime.indexOf('activation = reactivateCaptureProcess(');
  const advancingFrame = runtime.indexOf('const foregroundState = await waitRuntimeState(');
  const suspend = runtime.indexOf('await withSuspendedGameProcess(');
  assert.ok(activate >= 0 && advancingFrame > activate && suspend > advancingFrame);

  const mainStart = source.indexOf('async function main()');
  const main = source.slice(mainStart);
  const beforeBuild = main.indexOf("quiesceProductionApp(productionAppBefore, 'production-quiesce-before-build')");
  const build = main.indexOf('build = buildFreshDebugApp();');
  const afterBuild = main.indexOf("quiesceProductionApp(productionAppBefore, 'production-quiesce-after-build')");
  assert.ok(beforeBuild >= 0 && build > beforeBuild && afterBuild > build);
  assert.match(main, /finalProcess\?\.executable !== captureExecutableUrl/u);
  assert.match(main, /!launchedGamePids\.has\(finalProcess\?\.processIdentifier\)/u);
});

test('iOS guardian prep then stops only the exact PID to freeze the native frame', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  const start = source.indexOf('async function captureGuardian(');
  const end = source.indexOf('\nasync function captureMissileCore(', start);
  assert.ok(start >= 0 && end > start);
  const guardianSource = source.slice(start, end);
  const terminate = guardianSource.indexOf('terminateGame();');
  const cleanUiArm = guardianSource.indexOf("armCleanUi('combat');");
  const launch = guardianSource.indexOf('const launched = launchApp(');
  const processCheck = guardianSource.indexOf('const processBefore = runningGameProcesses(');
  const cleanUiReady = guardianSource.indexOf("await waitCleanUi('combat')");
  const guardianReady = guardianSource.indexOf('const before = await waitRuntimeState(');
  const publish = guardianSource.indexOf('await captureRuntime(');
  assert.ok(terminate >= 0 && cleanUiArm > terminate);
  assert.ok(launch > cleanUiArm && processCheck > launch);
  assert.ok(cleanUiReady > processCheck && guardianReady > cleanUiReady);
  assert.ok(publish > guardianReady);
  assert.match(
    guardianSource,
    /processBefore\[0\]\.processIdentifier !== launched\.pid/u,
  );
  assert.match(guardianSource, /suspendDuringScreenshot: true/u);
  assert.match(guardianSource, /discardUnpublishedCapture\(SCREENSHOTS\.guardian, locale\)/u);
  assert.doesNotMatch(guardianSource, /attempt <=|for \(let attempt/u);
  assert.match(source, /await captureGuardian\(locale\);/u);
});

test('guardian SIGSTOP has finally SIGCONT plus top-level resume/terminate safety nets', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  assert.match(source, /const IOS_SIGSTOP = 17;/u);
  assert.match(source, /const IOS_SIGCONT = 19;/u);
  const suspendStart = source.indexOf('async function withSuspendedGameProcess(');
  const suspendEnd = source.indexOf('\nfunction assertXcodeHandoffContinuity(', suspendStart);
  assert.ok(suspendStart >= 0 && suspendEnd > suspendStart);
  const suspendSource = source.slice(suspendStart, suspendEnd);
  assert.match(suspendSource, /suspendGameProcess\(pid, label, signalTimeout\);/u);
  assert.match(suspendSource, /settleWithMandatoryCleanup\(/u);
  assert.match(
    suspendSource,
    /async \(\) => resumeGameProcess\(pid, label, signalTimeout\)/u,
  );
  const stopStart = source.indexOf('function suspendGameProcess(');
  const stopEnd = source.indexOf('\nfunction resumeGameProcess(', stopStart);
  const stopSource = source.slice(stopStart, stopEnd);
  assert.match(stopSource, /sigcont-after-failed-sigstop/u);
  assert.match(stopSource, /suspendedGamePid = null;/u);
  assert.match(stopSource, /best-effort SIGCONT failed/u);
  const runtimeStart = source.indexOf('async function captureRuntime(');
  const runtimeEnd = source.indexOf('\nfunction discardUnpublishedCapture(', runtimeStart);
  const runtimeSource = source.slice(runtimeStart, runtimeEnd);
  const suspendedShot = runtimeSource.indexOf('await withSuspendedGameProcess(');
  const after = runtimeSource.indexOf('const after = await waitRuntimeState(');
  assert.ok(suspendedShot >= 0 && after > suspendedShot);
  assert.match(runtimeSource, /prepared\?\.suspendDuringScreenshot === true/u);
  assert.match(
    runtimeSource,
    /processAfter\[0\]\.processIdentifier !== processBefore\[0\]\.processIdentifier/u,
  );
  const cleanupStart = source.indexOf(
    'cleanupInProgress = true;',
    source.indexOf('async function main()'),
  );
  const cleanupEnd = source.indexOf('\n    },\n  );', cleanupStart);
  const cleanupSource = source.slice(cleanupStart, cleanupEnd);
  const cleanupResume = cleanupSource.indexOf(
    "resumeGameProcess(possiblyStoppedPid, 'top-level-cleanup')",
  );
  const emergencyTerminate = cleanupSource.indexOf(
    "terminateGameProcess(possiblyStoppedPid, 'emergency-terminate')",
  );
  const cleanupTerminate = cleanupSource.indexOf('terminateGame();');
  assert.ok(cleanupResume >= 0 && emergencyTerminate > cleanupResume);
  assert.ok(cleanupTerminate > emergencyTerminate);
});

test('Xcode handoff request pins the PID between the before proof and after advancing proof', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  assert.match(
    source,
    /--xcode-screenshot-inbox and --rsd-host\/--rsd-port cannot be used together/u,
  );
  assert.match(
    source,
    /options\.xcodeScreenshotInbox === null && !existsSync\(PYMOBILEDEVICE3\)/u,
  );
  const nativeStart = source.indexOf('async function nativeScreenshot(');
  const nativeEnd = source.indexOf('\nfunction screenshotTransportEvidence(', nativeStart);
  assert.ok(nativeStart >= 0 && nativeEnd > nativeStart);
  const nativeSource = source.slice(nativeStart, nativeEnd);
  const continuityBefore = nativeSource.indexOf('assertXcodeHandoffContinuity(');
  const request = nativeSource.indexOf("event: 'xcode_screenshot_requested'");
  const wait = nativeSource.indexOf('await waitForXcodeScreenshotHandoff({');
  const continuityAfter = nativeSource.indexOf(
    'assertXcodeHandoffContinuity(',
    continuityBefore + 1,
  );
  assert.ok(continuityBefore >= 0 && request > continuityBefore);
  assert.ok(wait > request && continuityAfter > wait);
  assert.match(nativeSource, /expected_path: expectedPath/u);
  assert.match(nativeSource, /required_mode: '0600'/u);
  assert.match(
    nativeSource,
    /required_delivery: 'publisher-script-fsync-partial-atomic-rename-receipt'/u,
  );
  assert.match(nativeSource, /removeXcodeScreenshotHandoffEntries\(\{/u);
  assert.match(nativeSource, /const handoffDeadlineMs = Date\.now\(\) \+ XCODE_HANDOFF_DEADLINE_MS/u);
  assert.match(nativeSource, /timeout_seconds: Math\.ceil\(handoffWaitTimeoutMs \/ 1_000\)/u);
  assert.match(nativeSource, /timeoutMs: handoffWaitTimeoutMs/u);
  assert.match(
    nativeSource,
    /xcode-handoff-after`,\s+remainingHandoffBudget\(`/u,
  );

  const runtimeStart = source.indexOf('async function captureRuntime(');
  const runtimeEnd = source.indexOf('\nfunction discardUnpublishedCapture(', runtimeStart);
  const runtime = source.slice(runtimeStart, runtimeEnd);
  const before = runtime.indexOf('before = await waitRuntimeState(');
  const screenshot = runtime.indexOf('const screenshot = suspendDuringScreenshot');
  const after = runtime.indexOf('const after = await waitRuntimeState(');
  assert.ok(before >= 0 && screenshot > before && after > screenshot);
  assert.match(
    runtime,
    /captureMethod === IOS_XCODE_HANDOFF_CAPTURE_METHOD/u,
  );
});

test('iOS capture does not bake author-machine pymobiledevice3 or device ids', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  assert.match(source, /function resolvePymobiledevice3Bin\(\)/u);
  assert.match(source, /MOONLIT_PYMOBILEDEVICE3_BIN/u);
  assert.match(source, /for \(const required of \['device-id', 'usb-udid'\]\)/u);
  assert.match(source, /fail\(`--\$\{required\} is required`\)/u);
  assert.doesNotMatch(source, /DEFAULT_IPAD_COREDEVICE_ID/u);
  assert.doesNotMatch(source, /DEFAULT_IPAD_USB_UDID/u);
  assert.equal(source.includes(['/Users', 'hyo'].join('/')), false);
});

test('CoreDevice continuity keeps the 5s minimum devicectl timeout and full handoff budget', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  assert.match(source, /const DEVICECTL_MIN_TIMEOUT_MS = 5_000;/u);
  assert.match(source, /const XCODE_HANDOFF_DEADLINE_MS = 300_000;/u);

  const runnerStart = source.indexOf('function runDevicectlJson(');
  const runnerEnd = source.indexOf('\nfunction queryInstalledApp(', runnerStart);
  const runnerSource = source.slice(runnerStart, runnerEnd);
  assert.match(
    runnerSource,
    /timeout < DEVICECTL_MIN_TIMEOUT_MS/u,
  );
  assert.match(
    runnerSource,
    /Math\.max\(5, Math\.floor\(timeout \/ 1000\)\)/u,
  );
  assert.match(runnerSource, /\{ timeout \}\);/u);

  const continuityStart = source.indexOf('function assertXcodeHandoffContinuity(');
  const continuityEnd = source.indexOf('\nasync function nativeScreenshot(', continuityStart);
  const continuitySource = source.slice(continuityStart, continuityEnd);
  assert.match(
    continuitySource,
    /timeoutMs < DEVICECTL_MIN_TIMEOUT_MS \* 2/u,
  );
  assert.match(
    continuitySource,
    /const detailsBudget = Math\.max\(\s*DEVICECTL_MIN_TIMEOUT_MS,/u,
  );
  assert.match(
    continuitySource,
    /allRunningGameProcesses\(`\$\{label\}-processes`, remainingMs\)/u,
  );

  const nativeStart = source.indexOf('async function nativeScreenshot(');
  const nativeEnd = source.indexOf('\nfunction screenshotTransportEvidence(', nativeStart);
  const nativeSource = source.slice(nativeStart, nativeEnd);
  assert.match(
    nativeSource,
    /remainingMs < DEVICECTL_MIN_TIMEOUT_MS \* 2\s*\? null/u,
  );
  assert.match(
    nativeSource,
    /const handoffDeadlineMs = Date\.now\(\) \+ XCODE_HANDOFF_DEADLINE_MS/u,
  );
});

test('devicectl timeout classification requires the last line to be the exact diagnostic', () => {
  const diagnostic = 'ERROR: Command timeout of 9.0 seconds exceeded. '
    + 'Assuming command got stuck and aborting.';
  assert.equal(isDevicectlReportedTimeout(new Error(`command failed\n${diagnostic}`)), true);
  assert.equal(isDevicectlReportedTimeout(new Error(`${diagnostic}\n`)), true);
  assert.equal(
    isDevicectlReportedTimeout(new Error(`${diagnostic}\nERROR: device disconnected permanently`)),
    false,
  );
  assert.equal(
    isDevicectlReportedTimeout(new Error(`ERROR: device disconnected permanently\n${diagnostic}`)),
    false,
  );
  assert.equal(isDevicectlReportedTimeout(new Error(`prefix ${diagnostic}`)), false);
  assert.equal(isDevicectlReportedTimeout({ message: diagnostic }), false);
});

test('CoreDevice poll retries only ETIMEDOUT inside the read deadline', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  assert.match(
    source,
    /const DEVICECTL_REMOTE_READ_MIN_TIMEOUT_MS = DEVICECTL_MIN_TIMEOUT_MS \* 2;/u,
  );
  assert.match(
    source,
    /const DEVICECTL_POLL_TIMEOUT_MS = DEVICECTL_REMOTE_READ_MIN_TIMEOUT_MS;/u,
  );
  assert.match(source, /const DEVICECTL_STABLE_READ_TIMEOUT_MS = \(/u);
  assert.match(source, /const DEVICECTL_STABLE_READ_OVERHEAD_MS = 2_000;/u);

  const runnerStart = source.indexOf('function runDevicectlJson(');
  const runnerEnd = source.indexOf('\nfunction queryInstalledApp(', runnerStart);
  const runnerSource = source.slice(runnerStart, runnerEnd);
  assert.match(runnerSource, /if \(isDevicectlReportedTimeout\(error\)\)/u);
  assert.match(runnerSource, /timeoutError\.code = 'ETIMEDOUT'/u);
  assert.match(runnerSource, /throw error;/u);

  const readStart = source.indexOf('function readRemote(');
  const readEnd = source.indexOf('\nfunction readRemoteJson(', readStart);
  assert.ok(readStart >= 0 && readEnd > readStart);
  const readSource = source.slice(readStart, readEnd);
  assert.match(readSource, /const deadline = Date\.now\(\) \+ timeout;/u);
  assert.match(readSource, /Math\.floor\(timeout \/ 2\)/u);
  assert.match(readSource, /const copyTimeout = deadline - Date\.now\(\);/u);
  assert.match(readSource, /copyTimeout < DEVICECTL_MIN_TIMEOUT_MS/u);
  assert.match(readSource, /if \(Date\.now\(\) >= deadline\)/u);
  assert.match(readSource, /`pull-\$\{String\(\+\+remoteSequence\)/u);

  const retryStart = source.indexOf('function isRetryableCoreDeviceTimeout(');
  const retryEnd = source.indexOf('\nasync function waitFor(', retryStart);
  assert.ok(retryStart >= 0 && retryEnd > retryStart);
  const retrySource = source.slice(retryStart, retryEnd);
  assert.match(retrySource, /error\.code === 'ETIMEDOUT'/u);
  assert.doesNotMatch(retrySource, /error\.message|includes|test\(/u);

  const waitStart = source.indexOf('async function waitFor(');
  const waitEnd = source.indexOf('\nfunction armRuntime(', waitStart);
  assert.ok(waitStart >= 0 && waitEnd > waitStart);
  const waitSource = source.slice(waitStart, waitEnd);
  assert.match(waitSource, /if \(Date\.now\(\) >= deadline\) break;/u);
  assert.match(waitSource, /if \(!retryError\(error\)\) throw error;/u);

  const runtimeStart = source.indexOf('async function waitRuntimeState(');
  const runtimeEnd = source.indexOf('\nfunction armCleanUi(', runtimeStart);
  assert.ok(runtimeStart >= 0 && runtimeEnd > runtimeStart);
  const runtimeSource = source.slice(runtimeStart, runtimeEnd);
  assert.match(runtimeSource, /if \(remainingMs < minimumReadBudget\) break;/u);
  assert.match(
    runtimeSource,
    /DEVICECTL_STABLE_READ_TIMEOUT_MS \+ DEVICECTL_STABLE_READ_OVERHEAD_MS/u,
  );
  assert.match(
    runtimeSource,
    /if \(!isRetryableCoreDeviceTimeout\(error\)\) throw error;/u,
  );
  assert.match(
    runtimeSource,
    /stableProcessId === null[\s\S]*?withSuspendedGameProcess\([\s\S]*?stableProcessId/u,
  );
  assert.match(
    runtimeSource,
    /async \(\) => readState\(\),\s+DEVICECTL_MIN_TIMEOUT_MS,/u,
  );
  assert.match(runtimeSource, /if \(Date\.now\(\) >= deadline\) break;/u);

  const captureStart = source.indexOf('async function captureRuntime(');
  const captureEnd = source.indexOf('\nfunction discardUnpublishedCapture(', captureStart);
  const captureSource = source.slice(captureStart, captureEnd);
  assert.match(
    captureSource,
    /before\.raw\.observation,[\s\S]*?processBefore\[0\]\.processIdentifier/u,
  );

  const writeStart = source.indexOf('function writeRemote(');
  const writeEnd = source.indexOf('\nfunction disarmFiles(', writeStart);
  assert.ok(writeStart >= 0 && writeEnd > writeStart);
  assert.doesNotMatch(
    source.slice(writeStart, writeEnd),
    /DEVICECTL_POLL_TIMEOUT_MS|isRetryableCoreDeviceTimeout/u,
  );
});

test('iOS native screenshot allows only safe HUD resize and pins anchor/state', () => {
  const expected = { kind: 'arena_ready', gameLocale: 'ko' };
  const before = arenaReadyState();
  const stable = assertStableIosArenaCaptureState(
    before,
    arenaReadyState({ observation: 2, hud_left_rect: [20, 14, 165, 110] }),
    expected,
  );
  assert.equal(stable.observation_after, 2);
  assert.throws(
    () => assertStableIosArenaCaptureState(
      before,
      arenaReadyState({ observation: 2, hud_left_rect: [21, 14, 165, 110] }),
      expected,
    ),
    /anchor/u,
  );
  assert.throws(
    () => assertStableIosArenaCaptureState(
      before,
      arenaReadyState({ observation: 2, over: true }),
      expected,
    ),
    /finished combat/u,
  );
});

test('pins physical iPad identity and the wired CoreDevice tunnel', () => {
  const identity = assertPhysicalIosDevice(devicePayload(), {
    target: 'ipad-13',
    coreDeviceIdentifier: '77322685-379D-50CE-894E-FCB3C2A27163',
    usbUdid: '00008130-001929642642001C',
  });
  assert.equal(identity.model_identifier, 'iPad16,1');
  assert.equal(identity.physical_device, true);
  assert.equal(identity.simulator, false);
  assert.throws(
    () => assertPhysicalIosDevice(devicePayload({
      hardwareProperties: {
        ...devicePayload().result.hardwareProperties,
        reality: 'simulator',
      },
    }), {
      target: 'ipad-13',
      coreDeviceIdentifier: '77322685-379D-50CE-894E-FCB3C2A27163',
      usbUdid: '00008130-001929642642001C',
    }),
    /physical iPad/u,
  );
});

test('allows a paired localNetwork tunnel on the physical iPad and rejects other transports', () => {
  const localNetworkPayload = devicePayload({
    connectionProperties: {
      ...devicePayload().result.connectionProperties,
      transportType: 'localNetwork',
    },
  });
  const expected = {
    target: 'ipad-13',
    coreDeviceIdentifier: '77322685-379D-50CE-894E-FCB3C2A27163',
    usbUdid: '00008130-001929642642001C',
  };
  assert.equal(
    assertPhysicalIosDevice(localNetworkPayload, expected).transport,
    'localNetwork',
  );
  for (const connectionOverride of [
    { transportType: 'bluetooth' },
    { transportType: 'localNetwork', pairingState: 'unpaired' },
    { transportType: 'localNetwork', tunnelState: 'disconnected' },
  ]) {
    assert.throws(() => assertPhysicalIosDevice(devicePayload({
      connectionProperties: {
        ...devicePayload().result.connectionProperties,
        ...connectionOverride,
      },
    }), expected), /differs from the connected physical iPad contract/u);
  }
});

test('binds the RSD endpoint to CoreDevice identity and returns only a non-sensitive subset', () => {
  const coreIdentity = assertPhysicalIosDevice(devicePayload(), {
    target: 'ipad-13',
    coreDeviceIdentifier: '77322685-379D-50CE-894E-FCB3C2A27163',
    usbUdid: '00008130-001929642642001C',
  });
  const identity = assertRsdIosDeviceIdentity(rsdPayload(), coreIdentity);
  assert.deepEqual(identity, {
    physical_device: true,
    simulator: false,
    model_identifier: 'iPad16,1',
    os_version: '26.5.2',
    os_build: '23F84',
  });
  assert.equal(JSON.stringify(identity).includes('00008130'), false);
  assert.equal(JSON.stringify(identity).includes('must-not-enter-evidence'), false);
});

test('RSD endpoint requires UDID, model, OS, build, and physical flags to all match', () => {
  const coreIdentity = assertPhysicalIosDevice(devicePayload(), {
    target: 'ipad-13',
    coreDeviceIdentifier: '77322685-379D-50CE-894E-FCB3C2A27163',
    usbUdid: '00008130-001929642642001C',
  });
  for (const mismatch of [
    { UniqueDeviceID: '00008130-001929642642FFFF' },
    { ProductType: 'iPhone17,1' },
    { OSVersion: '26.5.1' },
    { BuildVersion: '23F77' },
    { IsVirtualDevice: true },
  ]) {
    assert.throws(
      () => assertRsdIosDeviceIdentity(rsdPayload(mismatch), coreIdentity),
      /differs from the verified physical CoreDevice identity/u,
    );
  }
});

test('installed app identity requires matching bundle, version, and build', () => {
  const payload = {
    result: {
      deviceIdentifier: 'core-id',
      matchingBundleIdentifier: 'com.crossplatformkorea.moonlitbeacon',
      apps: [{
        bundleIdentifier: 'com.crossplatformkorea.moonlitbeacon',
        bundleVersion: '2',
        version: '1.0.1',
        builtByDeveloper: true,
        removable: true,
        url: 'file:///private/MoonlitBeacon.app/',
      }],
    },
  };
  const expected = {
    bundleId: 'com.crossplatformkorea.moonlitbeacon',
    shortVersion: '1.0.1',
    buildVersion: '2',
    coreDeviceIdentifier: 'core-id',
  };
  assert.equal(assertInstalledIosApp(payload, expected).bundleVersion, '2');
  payload.result.apps[0].bundleVersion = '1';
  assert.throws(() => assertInstalledIosApp(payload, expected), /version, build/u);
});

test('iOS frozen install pins the attested ZIP and exact app tree together', () => {
  const expected = {
    artifactSha256: HASH('artifact'),
    currentArtifactSha256: HASH('artifact'),
    appTreeSha256: HASH('app-tree'),
    currentAppTreeSha256: HASH('app-tree'),
  };
  assert.equal(assertFrozenIosInstallArtifact(expected), true);
  assert.throws(
    () => assertFrozenIosInstallArtifact({
      ...expected,
      currentArtifactSha256: HASH('replaced-artifact'),
    }),
    /preservation ZIP changed/u,
  );
  assert.throws(
    () => assertFrozenIosInstallArtifact({
      ...expected,
      currentAppTreeSha256: HASH('replaced-app-tree'),
    }),
    /\.app tree differs/u,
  );
  assert.throws(
    () => assertFrozenIosInstallArtifact({
      ...expected,
      artifactSha256: 'not-a-digest',
    }),
    /is not a valid SHA-256/u,
  );
});

test('iOS app tree hash distinguishes empty directories from file and symlink types', () => {
  withTemporaryDirectory('moonlit-ios-tree-', (root) => {
    const baseline = join(root, 'baseline.app');
    const withEmptyDirectory = join(root, 'empty-directory.app');
    const regularFile = join(root, 'regular-file.app');
    const symbolicLink = join(root, 'symbolic-link.app');
    for (const path of [baseline, withEmptyDirectory, regularFile, symbolicLink]) {
      mkdirSync(path);
    }
    mkdirSync(join(withEmptyDirectory, 'Empty'));
    symlinkSync('target', join(symbolicLink, 'entry'));
    const symlinkMode = lstatSync(join(symbolicLink, 'entry')).mode & 0o7777;
    writeFileSync(join(regularFile, 'entry'), 'target');
    chmodSync(join(regularFile, 'entry'), symlinkMode);

    assert.notEqual(
      iosAppTreeSha256(baseline),
      iosAppTreeSha256(withEmptyDirectory),
      'an empty directory is still part of the app tree meaning',
    );
    assert.notEqual(
      iosAppTreeSha256(regularFile),
      iosAppTreeSha256(symbolicLink),
      'file and symlink must differ even with the same mode and bytes',
    );
  });
});

test('immutable install tree blocks pathname replacement and in-place file rewrites', {
  skip: process.platform !== 'darwin',
}, () => {
  withTemporaryDirectory('moonlit-ios-open-dir-', (root) => {
    const installRoot = join(root, 'install');
    const movedRoot = join(root, 'attested');
    const app = join(installRoot, 'MoonlitBeacon.app');
    mkdirSync(app, { recursive: true });
    writeFileSync(join(app, 'marker'), 'attested');

    const observed = withImmutableFilesystemPath(
      installRoot,
      () => {
        assert.throws(() => renameSync(installRoot, movedRoot), (error) => (
          error?.code === 'EPERM'
        ));
        assert.throws(
          () => writeFileSync(join(app, 'marker'), 'replacement'),
          (error) => error?.code === 'EPERM',
        );
        return readFileSync(join(app, 'marker'), 'utf8');
      },
      (path, immutable) => {
        const result = spawnSync(
          '/usr/bin/chflags',
          ['-R', immutable ? 'uchg' : 'nouchg', path],
          { encoding: 'utf8' },
        );
        assert.equal(result.status, 0, result.stderr);
      },
    );

    assert.equal(observed, 'attested');
    renameSync(installRoot, movedRoot);
    assert.equal(
      readFileSync(join(movedRoot, 'MoonlitBeacon.app', 'marker'), 'utf8'),
      'attested',
    );
  });
});

test('immutable flag setup and operation failures both still run unseal cleanup', () => {
  const sealEvents = [];
  assert.throws(
    () => withImmutableFilesystemPath('/private/install', () => {
      assert.fail('must not run the operation after seal failure');
    }, (_path, immutable) => {
      sealEvents.push(immutable);
      if (immutable) throw new Error('partial seal');
    }),
    /partial seal/u,
  );
  assert.deepEqual(sealEvents, [true, false]);

  const operationEvents = [];
  assert.throws(
    () => withImmutableFilesystemPath('/private/install', () => {
      operationEvents.push('operation');
      throw new Error('install failed');
    }, (_path, immutable) => operationEvents.push(immutable ? 'seal' : 'unseal')),
    /install failed/u,
  );
  assert.deepEqual(operationEvents, ['seal', 'operation', 'unseal']);
});

test('iOS private work enforces directory 0700 and regular file 0600', () => {
  withTemporaryDirectory('moonlit-ios-private-', (root) => {
    const work = join(root, 'work');
    ensurePrivateDirectory(work);
    assert.equal(lstatSync(work).mode & 0o777, 0o700);
    const secret = join(work, 'iap_entitlements.cfg');
    writePrivateFileExclusive(secret, 'jws=secret');
    assert.equal(lstatSync(secret).mode & 0o777, 0o600);
    chmodSync(secret, 0o644);
    sealPrivateRegularFile(secret);
    assert.equal(lstatSync(secret).mode & 0o777, 0o600);

    const symlink = join(work, 'receipt-link');
    symlinkSync(secret, symlink);
    assert.throws(
      () => sealPrivateRegularFile(symlink),
      /is not a real regular file/u,
    );
  });
});

test('iOS install installs only the attested ZIP immutable private app and rechecks before/after', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  const buildStart = source.indexOf('function buildFreshDebugApp()');
  const buildEnd = source.indexOf('\nfunction installFreshApp(', buildStart);
  assert.ok(buildStart >= 0 && buildEnd > buildStart);
  const buildSource = source.slice(buildStart, buildEnd);
  assert.match(buildSource, /'-x', '-k', artifact, frozenRoot/u);
  assert.match(buildSource, /const frozenApp = join\(frozenRoot/u);
  assert.match(buildSource, /assertFrozenIosInstallArtifact\(\{/u);
  assert.match(buildSource, /return \{\s*frozenApp,/u);

  const installStart = source.indexOf('function installFreshApp(');
  const installEnd = source.indexOf('\nfunction launchApp(', installStart);
  assert.ok(installStart >= 0 && installEnd > installStart);
  const installSource = source.slice(installStart, installEnd);
  const firstVerification = installSource.indexOf('assertFrozenIosInstallArtifact({');
  const immutable = installSource.indexOf('withImmutableFilesystemPath(');
  const immutableVerification = installSource.indexOf(
    'assertFrozenIosInstallArtifact({',
    firstVerification + 1,
  );
  const installation = installSource.indexOf('runDevicectlJson([');
  const postInstallVerification = installSource.indexOf(
    'assertFrozenIosInstallArtifact({',
    immutableVerification + 1,
  );
  assert.ok(firstVerification >= 0 && immutable > firstVerification);
  assert.ok(immutableVerification > immutable && installation > immutableVerification);
  assert.ok(postInstallVerification > installation);
  assert.match(installSource, /iosAppTreeSha256\(build\.frozenApp\)/u);
  assert.match(installSource, /const installApp = join\(installRoot/u);
  assert.match(
    installSource,
    /run\('\/usr\/bin\/chflags', \['-R', immutable \? 'uchg' : 'nouchg', path\]\)/u,
  );
});

test('iOS capture export and build run as one exclusive workflow command', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  const buildStart = source.indexOf('function buildFreshDebugApp()');
  const buildEnd = source.indexOf('\nfunction installFreshApp(', buildStart);
  const buildSource = source.slice(buildStart, buildEnd);
  assert.match(
    buildSource,
    /\[\s*'scripts\/ios\.mjs',\s*'capture-build-isolated',/u,
  );
  assert.doesNotMatch(buildSource, /\['scripts\/ios\.mjs', 'export'\]/u);
  assert.doesNotMatch(buildSource, /\['scripts\/ios\.mjs', 'build'/u);
});

test('every iOS screenshot transport removes only the disposable bundle, never production', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  assert.match(
    source,
    /const ISOLATED_CAPTURE_BUNDLE_ID = `\$\{PRODUCTION_BUNDLE_ID\}\.storecapture`;/u,
  );
  assert.match(
    source,
    /const ACTIVE_BUNDLE_ID = ISOLATED_CAPTURE_BUNDLE_ID;/u,
  );
  const mainStart = source.indexOf('async function main()');
  const cleanupStart = source.indexOf('cleanupInProgress = true;', mainStart);
  const cleanupCall = source.indexOf("uninstallIsolatedCaptureApp('isolated-capture-cleanup')", cleanupStart);
  const productionAfter = source.indexOf("'production-app-after'", cleanupStart);
  assert.ok(cleanupStart >= 0 && cleanupCall > cleanupStart && productionAfter > cleanupCall);
  assert.match(
    source.slice(mainStart),
    /productionAppBefore = installedAppIdentity\([\s\S]*?JSON\.stringify\(productionAppAfter\) !== JSON\.stringify\(productionAppBefore\)/u,
  );
  assert.match(
    source,
    /if \(ACTIVE_BUNDLE_ID !== ISOLATED_CAPTURE_BUNDLE_ID\)[\s\S]*?cannot uninstall the production bundle/u,
  );
  assert.doesNotMatch(source, /'apps', 'rm',[\s\S]{0,120}'--udid'/u);
});

test('iOS safe-area computes PNG physical insets instead of logical booleans', () => {
  const safe = {
    viewport_rect: [0, 0, 808, 531],
    safe_rect: [14, 14, 780, 503],
  };
  const proof = assertPhysicalIosSafeLayout(safe, { width: 2266, height: 1488 });
  assert.ok(proof.physical_insets.left > 34);
  assert.throws(
    () => assertPhysicalIosSafeLayout({
      viewport_rect: [0, 0, 808, 531],
      safe_rect: [1, 14, 806, 503],
    }, { width: 2266, height: 1488 }),
    /left physical safe-area inset is below 34px/u,
  );
});

test('CoreDevice lsof returns only RSD candidates for that IPv6 host', () => {
  const output = [
    'CoreDevic 1 hyo 9u IPv6 TCP [fd3b:a284:cdf6::2]:57661->[fd3b:a284:cdf6::1]:65197 (ESTABLISHED)',
    'CoreDevic 1 hyo 10u IPv6 TCP [fd3b:a284:cdf6::2]:57662->[fd3b:a284:cdf6::1]:65197 (ESTABLISHED)',
    'CoreDevic 1 hyo 11u IPv6 TCP [fd00::2]:1->[fd00::1]:60000 (ESTABLISHED)',
  ].join('\n');
  assert.deepEqual(coreDeviceRsdPortCandidates(output, 'fd3b:a284:cdf6::1'), [65197]);
});

test('explicit and automatic RSD candidates share the same identity check before screenshot', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  const resolveStart = source.indexOf('function resolveRsdEndpoint(');
  const resolveEnd = source.indexOf('\nfunction captureRect(', resolveStart);
  assert.ok(resolveStart >= 0 && resolveEnd > resolveStart);
  const resolver = source.slice(resolveStart, resolveEnd);
  assert.doesNotMatch(resolver, /host !== identity\.rsd_host/u);
  assert.match(resolver, /const host = options\.rsdHost \?\? identity\.rsd_host/u);
  const identityProbe = resolver.indexOf('probeRsdIdentity(host, port, identity)');
  const screenshotProbe = resolver.indexOf('captureWithRsd(host, port, path');
  assert.ok(identityProbe >= 0 && screenshotProbe > identityProbe);
  assert.match(resolver, /identity_verified: false/u);
  assert.match(resolver, /identity_verified: true/u);
  assert.match(resolver, /raw_json_sha256: identityProbe\.rawJsonSha256/u);
  const screenshotProbePath = resolver.indexOf('const path = join(workRoot, `rsd-probe-');
  const protectedRegion = resolver.indexOf('try {', screenshotProbePath);
  const privateDelete = resolver.indexOf('rmSync(path, { force: true });', protectedRegion);
  const finallyRegion = resolver.lastIndexOf('finally {', privateDelete);
  assert.ok(screenshotProbePath >= 0 && protectedRegion > screenshotProbePath);
  assert.ok(finallyRegion > protectedRegion && privateDelete > finallyRegion);
});

test('settings and persistent data must be byte-exact including presence', () => {
  assert.equal(assertByteExactRestoration(null, null, 'settings.cfg'), true);
  assert.equal(
    assertByteExactRestoration(Buffer.from('same'), Buffer.from('same'), 'vault.cfg'),
    true,
  );
  assert.throws(
    () => assertByteExactRestoration(null, Buffer.alloc(0), 'settings.cfg'),
    /presence changed/u,
  );
  assert.throws(
    () => assertByteExactRestoration(Buffer.from('a'), Buffer.from('b'), 'records.cfg'),
    /byte-exact/u,
  );
});

test('iOS persistent data requires matching file lists and bytes across both snapshots', () => {
  const stable = {
    'settings.cfg': Buffer.from('locale=ko'),
    'vault.cfg': null,
  };
  assert.equal(assertStableIosPersistentSnapshots(stable, {
    'settings.cfg': Buffer.from('locale=ko'),
    'vault.cfg': null,
  }), true);
  assert.throws(
    () => assertStableIosPersistentSnapshots(stable, {
      'settings.cfg': Buffer.from('locale=en'),
      'vault.cfg': null,
    }),
    /byte-exact/u,
  );
  assert.throws(
    () => assertStableIosPersistentSnapshots(stable, {
      ...stable,
      'records.cfg': Buffer.from('{}'),
    }),
    /file list changed/u,
  );
});

test('keeps the production user save-file inventory and captures only the isolated container', () => {
  assert.deepEqual(IOS_CODE_PERSISTENT_FILES, [
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

  const scriptRoot = join(REPO_ROOT, 'apps/game/scripts');
  const literals = new Set();
  for (const path of gdscriptFiles(scriptRoot)) {
    const source = readFileSync(path, 'utf8');
    for (const match of source.matchAll(/"user:\/\/([^"\n]+)"/gu)) {
      literals.add(match[1]);
    }
  }
  const captureControls = new Set([
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
    'test_hero.request',
  ]);
  const persistentBases = new Set([
    'analytics.json',
    'analytics.json.tmp',
    'analytics_consent.revoked',
    'iap_entitlements.cfg',
    'ladder.json',
    'ladder.json.tmp',
    'records.cfg',
    'records.cfg.tmp',
    'settings.cfg',
    'settings.cfg.tmp',
    'vault.cfg',
  ]);
  assert.deepEqual(
    [...literals].filter((name) => (
      !captureControls.has(name) && !persistentBases.has(name)
    )),
    [],
    'new production user:// literals must be classified as preserved or capture-control',
  );
  for (const base of persistentBases) {
    assert.ok(literals.has(base), `${base} production literal must exist`);
  }

  const producer = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  assert.match(producer, /const TEST_HERO_REQUEST = 'test_hero\.request';/u);
  const controlsStart = producer.indexOf('const CONTROL_FILES = Object.freeze([');
  const controlsEnd = producer.indexOf('\n]);', controlsStart);
  assert.ok(controlsStart >= 0 && controlsEnd > controlsStart);
  assert.equal(
    producer.slice(controlsStart, controlsEnd).includes('TEST_HERO_REQUEST'),
    false,
  );
  const build = producer.indexOf('build = buildFreshDebugApp();');
  const snapshot = producer.indexOf('const persistentBefore = stablePersistentSnapshot(');
  const immediateProcessCheck = producer.indexOf(
    "assertGameNotRunning('processes-immediately-before-install');",
    snapshot,
  );
  const install = producer.indexOf('installFreshApp(build);', snapshot);
  const testHeroDisarm = producer.indexOf(
    'disarmPersistentTestHero(persistentBefore);', snapshot,
  );
  const firstDisarm = producer.indexOf('disarmAllControls();', testHeroDisarm);
  const firstCapture = producer.indexOf('for (const locale of selectedLocales)', snapshot);
  const isolatedRestore = producer.indexOf('restore = {', firstCapture);
  assert.ok(build >= 0 && snapshot > build);
  assert.ok(immediateProcessCheck > snapshot && install > immediateProcessCheck);
  assert.ok(testHeroDisarm > snapshot && testHeroDisarm < firstDisarm);
  assert.ok(firstDisarm < firstCapture);
  assert.ok(isolatedRestore > firstCapture);
  assert.doesNotMatch(producer.slice(producer.indexOf('async function main()')), /restorePersistentFiles\(/u);
  assert.match(producer, /production_container_accessed: false/u);
  assert.match(
    producer,
    /function disarmPersistentTestHero\(original\)[\s\S]*?snapshotValue\(original, TEST_HERO_REQUEST\) !== null[\s\S]*?writeRemote\(TEST_HERO_REQUEST, '\{\}\\n'\);/u,
  );
  assert.match(
    producer,
    /function stablePersistentSnapshot\(appInstalled\)[\s\S]*?processes-before-persistent-snapshot-a[\s\S]*?const first = persistentSnapshot\(appInstalled\);[\s\S]*?processes-between-persistent-snapshots[\s\S]*?const second = persistentSnapshot\(appInstalled\);[\s\S]*?processes-after-persistent-snapshot-b[\s\S]*?assertStableIosPersistentSnapshots\(first, second\);/u,
  );
});

test('device receipt temporary plaintext is wiped immediately on success and failure', () => {
  const successRoot = mkdtempSync(join(tmpdir(), 'moonlit-ios-secret-success-'));
  const successPath = join(successRoot, 'iap_entitlements.cfg');
  assert.equal(withEphemeralFilesystemPath(successRoot, () => {
    writeFileSync(successPath, 'purchaseToken=must-not-survive');
    return readFileSync(successPath, 'utf8');
  }), 'purchaseToken=must-not-survive');
  assert.equal(existsSync(successRoot), false);

  const failureRoot = mkdtempSync(join(tmpdir(), 'moonlit-ios-secret-failure-'));
  const failurePath = join(failureRoot, 'iap_entitlements.cfg');
  assert.throws(
    () => withEphemeralFilesystemPath(failureRoot, () => {
      writeFileSync(failurePath, 'jws=must-not-survive');
      throw new Error('synthetic copy failure');
    }),
    /synthetic copy failure/u,
  );
  assert.equal(existsSync(failureRoot), false);
});

test('iOS cleanup still completes on install/handshake failure counterexamples', async () => {
  const events = [];
  const installFailure = new Error('synthetic install failure');
  const failed = await settleWithMandatoryCleanup(async () => {
    events.push('snapshot');
    events.push('install');
    throw installFailure;
  }, async () => {
    events.push('terminate');
    events.push('disarm');
    events.push('restore');
    return 'byte-exact';
  });
  assert.deepEqual(events, [
    'snapshot', 'install', 'terminate', 'disarm', 'restore',
  ]);
  assert.equal(failed.operationFailure, installFailure);
  assert.equal(failed.cleanupFailure, null);
  assert.equal(failed.cleanupValue, 'byte-exact');

  const cleanupFailure = new Error('synthetic restoration failure');
  const doubleFailure = await settleWithMandatoryCleanup(
    async () => { throw new Error('synthetic handshake failure'); },
    async () => { throw cleanupFailure; },
  );
  assert.match(doubleFailure.operationFailure.message, /handshake/u);
  assert.equal(doubleFailure.cleanupFailure, cleanupFailure);
});

test('host signal cancel still runs mandatory cleanup then returns failure', async () => {
  const cancellation = createDeferredCancellation();
  const events = [];
  const pending = new Promise(() => {});
  const settlementPromise = settleWithMandatoryCleanup(
    async () => {
      events.push('operation');
      return cancellation.race(pending);
    },
    async () => {
      events.push('cleanup');
    },
  );
  const requested = cancellation.request('SIGTERM');
  const settlement = await settlementPromise;
  assert.deepEqual(events, ['operation', 'cleanup']);
  assert.equal(settlement.operationFailure, requested);
  assert.equal(settlement.operationFailure.code, 'ECANCELED');
  assert.equal(settlement.operationFailure.signal, 'SIGTERM');
  assert.equal(settlement.cleanupFailure, null);
  assert.throws(() => cancellation.throwIfRequested(), /SIGTERM/u);

  const alreadyRequested = createDeferredCancellation();
  alreadyRequested.request('SIGHUP');
  await assert.rejects(alreadyRequested.race(Promise.resolve('late')), (error) => (
    error.code === 'ECANCELED' && error.signal === 'SIGHUP'
  ));
});

test('a real SIGTERM during spawnSync cleanup is not mistaken for success after the host turn', {
  skip: process.platform === 'win32',
}, () => {
  const moduleUrl = new URL('./ios-device-evidence.mjs', import.meta.url).href;
  const probe = `
    import { spawnSync } from 'node:child_process';
    import {
      createDeferredCancellation,
      settleWithMandatoryCleanup,
      waitForPendingHostSignalHandlers,
    } from ${JSON.stringify(moduleUrl)};
    const cancellation = createDeferredCancellation();
    const events = [];
    process.on('SIGTERM', () => cancellation.request('SIGTERM'));
    const settlement = await settleWithMandatoryCleanup(
      async () => events.push('operation'),
      async () => {
        events.push('cleanup-start');
        const signaler = spawnSync(process.execPath, [
          '-e', "process.kill(process.ppid, 'SIGTERM')",
        ]);
        if (signaler.status !== 0) throw new Error('signaler failed');
        events.push('cleanup-end');
      },
    );
    await waitForPendingHostSignalHandlers();
    let cancellationError = null;
    try {
      cancellation.throwIfRequested();
    } catch (error) {
      cancellationError = { code: error.code, signal: error.signal };
    }
    process.stdout.write(JSON.stringify({
      events,
      cleanupFailure: settlement.cleanupFailure?.message ?? null,
      cancellationError,
    }));
  `;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', probe], {
    encoding: 'utf8',
    timeout: 10_000,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), {
    events: ['operation', 'cleanup-start', 'cleanup-end'],
    cleanupFailure: null,
    cancellationError: { code: 'ECANCELED', signal: 'SIGTERM' },
  });
});

test('iOS capture signal handlers defer exit until device cleanup finishes', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  assert.match(source, /for \(const signal of \['SIGINT', 'SIGTERM', 'SIGHUP'\]\)/u);
  assert.match(source, /process\.on\(signal, \(\) => deferredCancellation\.request\(signal\)\)/u);
  const mainStart = source.indexOf('async function main()');
  const cleanupStart = source.indexOf('cleanupInProgress = true;', mainStart);
  const cleanupEnd = source.indexOf('cleanupInProgress = false;', cleanupStart);
  assert.ok(cleanupStart >= 0 && cleanupEnd > cleanupStart);
  assert.match(
    source,
    /cancellationProbe: \(\) => deferredCancellation\.throwIfRequested\(\)/u,
  );
  assert.match(source, /await waitForPendingHostSignalHandlers\(\);/u);
});

test('sync build/install/launch place a signal checkpoint before the next device mutation', () => {
  const source = readFileSync(
    new URL('../capture-ios-device-evidence.mjs', import.meta.url),
    'utf8',
  );
  const main = source.slice(source.indexOf('async function main()'));
  const build = main.indexOf('build = buildFreshDebugApp();');
  const buildCheckpoint = main.indexOf('await cancellationCheckpoint();', build);
  const postBuildQuiesce = main.indexOf(
    "quiesceProductionApp(productionAppBefore, 'production-quiesce-after-build')",
    build,
  );
  assert.ok(build >= 0 && buildCheckpoint > build && postBuildQuiesce > buildCheckpoint);

  const install = main.indexOf('installEvidence = installFreshApp(build);');
  const installCheckpoint = main.indexOf('await cancellationCheckpoint();', install);
  const captureWrites = main.indexOf('disarmPersistentTestHero(persistentBefore);', install);
  assert.ok(install >= 0 && installCheckpoint > install && captureWrites > installCheckpoint);

  const localeStart = source.indexOf('async function captureLocale(locale)');
  const localeEnd = source.indexOf('\nasync function main()', localeStart);
  const localeSource = source.slice(localeStart, localeEnd);
  for (const label of ['title', 'barrage', 'missile']) {
    const launch = localeSource.indexOf(`launchApp(\`\${locale.asset}-${label}\`)`);
    const checkpoint = localeSource.indexOf('await cancellationCheckpoint();', launch);
    assert.ok(launch >= 0 && checkpoint > launch, `${label} launch checkpoint is required`);
  }
});

test('only a 5-locale x 6 native iPad manifest counts as a complete set', () => {
  const locales = ['en-US', 'ko-KR', 'ja-JP', 'zh-Hans', 'zh-Hant'];
  const filenames = ['01.png', '02.png', '03.png', '04.png', '05.png', '06.png'];
  const artifactSha256 = HASH('app');
  const captures = locales.flatMap((locale) => filenames.map((filename) => ({
    asset_locale: locale,
    filename,
    sha256: HASH(`${locale}/${filename}`),
    width: 2266,
    height: 1488,
    native_device_framebuffer: true,
    capture_method: 'pymobiledevice3-dvt-rsd',
    rsd_host: 'fe80::1',
    rsd_port: 62078,
    ...RSD_NULL_XCODE_EVIDENCE,
    installed_artifact_sha256: artifactSha256,
    runtime_before: {},
    runtime_after: {},
    clean_ui_proof: 'hidden',
    safe_layout: {},
    physical_safe_layout: {},
    proof_path: 'builds/evidence/proof.json',
    evidence_path: 'builds/evidence/frame.png',
  })));
  assert.deepEqual(assertCompleteIosCaptureManifest({
    captures,
    locales,
    filenames,
    artifactSha256,
  }), { capture_count: 30, screenshot_size: '2266x1488' });
  captures[1].sha256 = captures[0].sha256;
  assert.throws(
    () => assertCompleteIosCaptureManifest({
      captures, locales, filenames, artifactSha256,
    }),
    /duplicated or its hash is wrong/u,
  );
});

test('Xcode handoff manifest requires exact 2266x1488, nonce, and a fresh timestamp', () => {
  const artifactSha256 = HASH('xcode-app');
  const nonce = 'a'.repeat(64);
  const frameSha256 = HASH('xcode-frame');
  const receipt = {
    schema: 1,
    protocol: 'moonlit-xcode-screenshot-handoff-v1',
    nonce,
    expected_filename: `moonlit-${nonce}.png`,
    partial_filename: `.moonlit-${nonce}.png.partial-${nonce}`,
    png_sha256: frameSha256,
    png_size: 1234,
    source_birthtime_ms: 100,
    source_mtime_ms: 100,
    final_dev: '42',
    final_ino: '9001',
    final_birthtime_ms: 101,
    final_mtime_ms: 102,
    file_fsync_before_rename: true,
    directory_fsync_after_rename: true,
    published_at_ms: 103,
  };
  const capture = {
    asset_locale: 'en-US',
    filename: '01.png',
    sha256: frameSha256,
    width: 2266,
    height: 1488,
    native_device_framebuffer: true,
    capture_method: IOS_XCODE_HANDOFF_CAPTURE_METHOD,
    rsd_host: null,
    rsd_port: null,
    xcode_handoff_nonce: nonce,
    xcode_handoff_expected_filename: `moonlit-${nonce}.png`,
    xcode_handoff_requested_at: new Date(100).toISOString(),
    xcode_handoff_requested_at_unix_ms: 100,
    xcode_handoff_birthtime_unix_ms: 101,
    xcode_handoff_mtime_unix_ms: 102,
    xcode_handoff_accepted_at: new Date(103).toISOString(),
    xcode_handoff_stable_observations: 2,
    xcode_handoff_complete_png_decoded: true,
    xcode_handoff_receipt: receipt,
    xcode_handoff_process_id: 4242,
    xcode_activation_process_id: 4242,
    xcode_activation_launch_path:
      'builds/ios-device-evidence/ipad-13/run-id/work/001-reactivate.json',
    xcode_activation_launch_sha256: HASH('activation-launch'),
    xcode_activation_processes_path:
      'builds/ios-device-evidence/ipad-13/run-id/work/002-reactivate-processes.json',
    xcode_activation_processes_sha256: HASH('activation-processes'),
    xcode_handoff_device_details_before_path:
      'builds/ios-device-evidence/ipad-13/run-id/work/003-details-before.json',
    xcode_handoff_device_details_before_sha256: HASH('details-before'),
    xcode_handoff_processes_before_path:
      'builds/ios-device-evidence/ipad-13/run-id/work/004-processes-before.json',
    xcode_handoff_processes_before_sha256: HASH('processes-before'),
    xcode_handoff_device_details_after_path:
      'builds/ios-device-evidence/ipad-13/run-id/work/005-details-after.json',
    xcode_handoff_device_details_after_sha256: HASH('details-after'),
    xcode_handoff_processes_after_path:
      'builds/ios-device-evidence/ipad-13/run-id/work/006-processes-after.json',
    xcode_handoff_processes_after_sha256: HASH('processes-after'),
    xcode_handoff_receipt_sha256: HASH(`${JSON.stringify(
      Object.fromEntries(Object.entries(receipt).sort(([left], [right]) => (
        left < right ? -1 : (left > right ? 1 : 0)
      ))),
    )}\n`),
    installed_artifact_sha256: artifactSha256,
    runtime_before: {},
    runtime_after: {},
    clean_ui_proof: 'hidden',
    safe_layout: {},
    physical_safe_layout: {},
    proof_path: 'builds/evidence/proof.json',
    evidence_path: 'builds/evidence/frame.png',
  };
  assert.deepEqual(assertCompleteIosCaptureManifest({
    captures: [capture],
    locales: ['en-US'],
    filenames: ['01.png'],
    artifactSha256,
    captureMethod: IOS_XCODE_HANDOFF_CAPTURE_METHOD,
  }), { capture_count: 1, screenshot_size: '2266x1488' });
  assert.throws(
    () => assertCompleteIosCaptureManifest({
      captures: [{ ...capture, xcode_handoff_mtime_unix_ms: 100 }],
      locales: ['en-US'],
      filenames: ['01.png'],
      artifactSha256,
      captureMethod: IOS_XCODE_HANDOFF_CAPTURE_METHOD,
    }),
    /Xcode screenshot handoff proof is invalid/u,
  );
  assert.throws(
    () => assertCompleteIosCaptureManifest({
      captures: [{ ...capture, xcode_activation_process_id: 4243 }],
      locales: ['en-US'],
      filenames: ['01.png'],
      artifactSha256,
      captureMethod: IOS_XCODE_HANDOFF_CAPTURE_METHOD,
    }),
    /Xcode screenshot handoff proof is invalid/u,
  );
});
