import { createHash } from 'node:crypto';
import {
  closeSync,
  constants,
  fchmodSync,
  fstatSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  readlinkSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import {
  basename,
  isAbsolute,
  join,
  relative,
  sep,
} from 'node:path';
import { inflateSync } from 'node:zlib';
import {
  assertStableStoreCaptureState,
  assertStoreCaptureState,
} from './capture-run-state.mjs';

const SHA256_PATTERN = /^[0-9a-f]{64}$/u;
const IOS_EVIDENCE_JSON_PATH_PATTERN =
  /^builds\/ios-device-evidence\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\/work\/[A-Za-z0-9._-]+\.json$/u;
const XCODE_CAPTURE_ONLY_FIELDS = Object.freeze([
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
]);
export const IOS_RSD_CAPTURE_METHOD = 'pymobiledevice3-dvt-rsd';
export const IOS_XCODE_HANDOFF_CAPTURE_METHOD = 'xcode-devices-take-screenshot-handoff';
export const IOS_XCODE_IPAD_LANDSCAPE_SIZE = Object.freeze({
  width: 2266,
  height: 1488,
});
const MAX_XCODE_SCREENSHOT_BYTES = 64 * 1024 * 1024;
const XCODE_HANDOFF_PROTOCOL = 'moonlit-xcode-screenshot-handoff-v1';
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

// Every production file rooted in Godot's user:// namespace. Capture controls
// are intentionally excluded: the producer owns and disarms those handshakes.
// Replicas and temporary replicas are included because an interrupted write may
// legitimately leave one behind, so its presence is user data too.
export const IOS_CODE_PERSISTENT_FILES = Object.freeze([
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

/** Match only devicectl's terminal timeout diagnostic, never mixed failures. */
export function isDevicectlReportedTimeout(error) {
  if (!(error instanceof Error)) return false;
  const lines = error.message.trimEnd().split(/\r?\n/u);
  const terminalLine = lines.pop() ?? '';
  return !lines.some((line) => /^ERROR:/u.test(line))
    && /^ERROR: Command timeout of [0-9]+(?:\.[0-9]+)? seconds exceeded\. Assuming command got stuck and aborting\.$/u
      .test(terminalLine);
}

function finiteRect(value, label) {
  if (
    !Array.isArray(value)
    || value.length !== 4
    || value.some((component) => (
      typeof component !== 'number' || !Number.isFinite(component)
    ))
    || value[2] <= 0
    || value[3] <= 0
  ) {
    fail(`${label} is not a finite [x,y,width,height] Rect`);
  }
  return value;
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/** Keep device receipts and private capture work inaccessible to other users. */
export function ensurePrivateDirectory(path) {
  if (typeof path !== 'string' || path.length === 0) {
    fail('iOS private directory path is missing');
  }
  mkdirSync(path, { recursive: true, mode: 0o700 });
  const before = lstatSync(path);
  if (!before.isDirectory() || before.isSymbolicLink()) {
    fail(`iOS private directory is not a real directory: ${path}`);
  }
  const descriptor = openSync(
    path,
    constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW,
  );
  try {
    fchmodSync(descriptor, 0o700);
    if (!fstatSync(descriptor).isDirectory() || (fstatSync(descriptor).mode & 0o777) !== 0o700) {
      fail(`Failed to pin iOS private directory mode to 0700: ${path}`);
    }
  } finally {
    closeSync(descriptor);
  }
  return path;
}

export function writePrivateFileExclusive(path, value) {
  if (typeof path !== 'string' || path.length === 0) {
    fail('iOS private file path is missing');
  }
  writeFileSync(path, value, { flag: 'wx', mode: 0o600 });
  return sealPrivateRegularFile(path);
}

export function sealPrivateRegularFile(path) {
  const before = lstatSync(path);
  if (!before.isFile() || before.isSymbolicLink()) {
    fail(`iOS private file is not a real regular file: ${path}`);
  }
  const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    fchmodSync(descriptor, 0o600);
    if (!fstatSync(descriptor).isFile() || (fstatSync(descriptor).mode & 0o777) !== 0o600) {
      fail(`Failed to pin iOS private file mode to 0600: ${path}`);
    }
  } finally {
    closeSync(descriptor);
  }
  return path;
}

function updateLengthPrefixed(hash, value) {
  const bytes = Buffer.isBuffer(value) ? value : Buffer.from(value, 'utf8');
  const size = Buffer.allocUnsafe(8);
  size.writeBigUInt64BE(BigInt(bytes.length));
  hash.update(size);
  hash.update(bytes);
}

function sameFilesystemEntry(before, after) {
  return before.dev === after.dev
    && before.ino === after.ino
    && before.mode === after.mode
    && before.size === after.size
    && before.mtimeMs === after.mtimeMs
    && before.ctimeMs === after.ctimeMs;
}

function isPathInside(root, candidate) {
  const child = relative(root, candidate);
  return child === '' || (
    child !== '..'
    && !child.startsWith(`..${sep}`)
    && !isAbsolute(child)
  );
}

function assertCurrentXcodeScreenshotInbox(inbox) {
  if (!isRecord(inbox) || typeof inbox.path !== 'string') {
    fail('Xcode screenshot inbox proof is invalid');
  }
  const before = lstatSync(inbox.path);
  if (
    !before.isDirectory()
    || before.isSymbolicLink()
    || before.dev !== inbox.dev
    || before.ino !== inbox.ino
    || (before.mode & 0o777) !== 0o700
  ) {
    fail('Xcode screenshot inbox changed after verification');
  }
  const descriptor = openSync(
    inbox.path,
    constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW,
  );
  try {
    const opened = fstatSync(descriptor);
    if (
      !opened.isDirectory()
      || opened.dev !== inbox.dev
      || opened.ino !== inbox.ino
      || (opened.mode & 0o777) !== 0o700
    ) {
      fail('Xcode screenshot inbox pathname identity changed');
    }
  } finally {
    closeSync(descriptor);
  }
}

/**
 * Pin an external, owner-only directory used for human-mediated Xcode frames.
 * The canonical path is kept outside the repository so an inbox image can
 * never become source input or be published without the evidence gate.
 */
export function assertPrivateXcodeScreenshotInbox(path, repositoryRoot) {
  if (
    typeof path !== 'string'
    || path.length === 0
    || !isAbsolute(path)
    || typeof repositoryRoot !== 'string'
    || repositoryRoot.length === 0
    || !isAbsolute(repositoryRoot)
  ) {
    fail('Xcode screenshot inbox and repository root must be absolute paths');
  }
  const repository = realpathSync(repositoryRoot);
  const canonical = realpathSync(path);
  if (isPathInside(repository, canonical)) {
    fail('Xcode screenshot inbox must be outside the repository');
  }
  const before = lstatSync(path);
  if (!before.isDirectory() || before.isSymbolicLink()) {
    fail('Xcode screenshot inbox is not a real directory');
  }
  if ((before.mode & 0o777) !== 0o700) {
    fail('Xcode screenshot inbox mode must be exactly 0700');
  }
  if (typeof process.getuid === 'function' && before.uid !== process.getuid()) {
    fail('Xcode screenshot inbox owner differs from the current user');
  }
  const inbox = Object.freeze({
    path: canonical,
    dev: before.dev,
    ino: before.ino,
  });
  assertCurrentXcodeScreenshotInbox(inbox);
  return inbox;
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ ((crc & 1) === 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

/** Parse, CRC-check, inflate, and unfilter a complete non-interlaced PNG. */
export function assertCompletePng(bytes, label = 'PNG') {
  if (!Buffer.isBuffer(bytes) || bytes.length < 45 || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
    fail(`${label} is not a complete PNG`);
  }
  let offset = 8;
  let ihdr = null;
  let sawIend = false;
  let sawIdat = false;
  let idatEnded = false;
  let sawPalette = false;
  let paletteEntries = 0;
  const compressed = [];
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) fail(`${label} PNG chunk header is truncated`);
    const length = bytes.readUInt32BE(offset);
    const end = offset + 12 + length;
    if (end > bytes.length) fail(`${label} PNG chunk payload is truncated`);
    const typeBytes = bytes.subarray(offset + 4, offset + 8);
    const type = typeBytes.toString('ascii');
    if (!/^[A-Za-z]{4}$/u.test(type)) fail(`${label} PNG chunk type is invalid`);
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    const expectedCrc = bytes.readUInt32BE(offset + 8 + length);
    if (crc32(Buffer.concat([typeBytes, data])) !== expectedCrc) {
      fail(`${label} PNG ${type} CRC is wrong`);
    }
    if (ihdr === null) {
      if (type !== 'IHDR' || length !== 13) fail(`${label} PNG IHDR is invalid`);
      ihdr = {
        width: data.readUInt32BE(0),
        height: data.readUInt32BE(4),
        bitDepth: data[8],
        colorType: data[9],
        compression: data[10],
        filter: data[11],
        interlace: data[12],
      };
    } else if (type === 'IHDR') {
      fail(`${label} PNG IHDR is duplicated`);
    } else if (type === 'PLTE') {
      if (
        sawIdat
        || sawPalette
        || [0, 4].includes(ihdr.colorType)
        || length === 0
        || length % 3 !== 0
        || length > 768
        || (ihdr.colorType === 3 && length / 3 > 2 ** ihdr.bitDepth)
      ) {
        fail(`${label} PNG PLTE is invalid`);
      }
      sawPalette = true;
      paletteEntries = length / 3;
    } else if (type === 'IDAT') {
      if (idatEnded) fail(`${label} PNG IDAT chunks are not contiguous`);
      sawIdat = true;
      compressed.push(data);
    } else {
      if (sawIdat && type !== 'IEND') idatEnded = true;
      if (type === 'IEND') {
        if (length !== 0 || sawIend || end !== bytes.length) {
          fail(`${label} has data after PNG IEND`);
        }
        sawIend = true;
      } else if ((typeBytes[0] & 0x20) === 0) {
        fail(`${label} PNG has unknown critical chunk ${type}`);
      }
    }
    offset = end;
  }
  if (ihdr === null || !sawIdat || !sawIend || offset !== bytes.length) {
    fail(`${label} PNG chunk stream is incomplete`);
  }
  const channelsByColorType = new Map([[0, 1], [2, 3], [3, 1], [4, 2], [6, 4]]);
  const bitDepthsByColorType = new Map([
    [0, new Set([1, 2, 4, 8, 16])],
    [2, new Set([8, 16])],
    [3, new Set([1, 2, 4, 8])],
    [4, new Set([8, 16])],
    [6, new Set([8, 16])],
  ]);
  if (
    ihdr.width <= 0
    || ihdr.height <= 0
    || !channelsByColorType.has(ihdr.colorType)
    || !bitDepthsByColorType.get(ihdr.colorType).has(ihdr.bitDepth)
    || ihdr.compression !== 0
    || ihdr.filter !== 0
    || ihdr.interlace !== 0
    || (ihdr.colorType === 3 && !sawPalette)
  ) {
    fail(`${label} PNG IHDR encoding is unsupported`);
  }
  const channels = channelsByColorType.get(ihdr.colorType);
  const rowBytes = Math.ceil((ihdr.width * channels * ihdr.bitDepth) / 8);
  const bytesPerPixel = Math.max(1, Math.ceil((channels * ihdr.bitDepth) / 8));
  const decodedLength = ihdr.height * (rowBytes + 1);
  if (!Number.isSafeInteger(decodedLength) || decodedLength > MAX_XCODE_SCREENSHOT_BYTES * 4) {
    fail(`${label} PNG decoded size is outside the allowed range`);
  }
  const compressedBytes = Buffer.concat(compressed);
  let inflated;
  try {
    inflated = inflateSync(compressedBytes, {
      info: true,
      maxOutputLength: decodedLength + 1,
    });
  } catch (error) {
    fail(`${label} PNG IDAT decode failed: ${error.message}`);
  }
  if (inflated.engine.bytesWritten !== compressedBytes.length) {
    fail(`${label} has data after the PNG IDAT zlib stream`);
  }
  const raw = inflated.buffer;
  if (raw.length !== decodedLength) fail(`${label} PNG decoded scanline length is wrong`);
  let previous = Buffer.alloc(rowBytes);
  let cursor = 0;
  for (let row = 0; row < ihdr.height; row += 1) {
    const filter = raw[cursor];
    if (filter > 4) fail(`${label} PNG scanline filter is invalid`);
    cursor += 1;
    const current = Buffer.allocUnsafe(rowBytes);
    for (let index = 0; index < rowBytes; index += 1) {
      const encoded = raw[cursor + index];
      const left = index >= bytesPerPixel ? current[index - bytesPerPixel] : 0;
      const up = previous[index];
      const upperLeft = index >= bytesPerPixel ? previous[index - bytesPerPixel] : 0;
      let predictor = 0;
      if (filter === 1) predictor = left;
      else if (filter === 2) predictor = up;
      else if (filter === 3) predictor = Math.floor((left + up) / 2);
      else if (filter === 4) {
        const p = left + up - upperLeft;
        const pa = Math.abs(p - left);
        const pb = Math.abs(p - up);
        const pc = Math.abs(p - upperLeft);
        predictor = pa <= pb && pa <= pc ? left : (pb <= pc ? up : upperLeft);
      }
      current[index] = (encoded + predictor) & 0xff;
    }
    cursor += rowBytes;
    if (ihdr.colorType === 3) {
      const mask = (1 << ihdr.bitDepth) - 1;
      for (let column = 0; column < ihdr.width; column += 1) {
        const bitOffset = column * ihdr.bitDepth;
        const paletteIndex = ihdr.bitDepth === 8
          ? current[column]
          : (current[Math.floor(bitOffset / 8)] >> (8 - ihdr.bitDepth - (bitOffset % 8))) & mask;
        if (paletteIndex >= paletteEntries) {
          fail(`${label} PNG indexed pixel is outside the PLTE range`);
        }
      }
    }
    previous = current;
  }
  return Object.freeze({ width: ihdr.width, height: ihdr.height });
}

function assertXcodeHandoffRequest(expectedFilename, nonce, requestedAtMs) {
  if (
    typeof expectedFilename !== 'string'
    || basename(expectedFilename) !== expectedFilename
    || !/^moonlit-[0-9a-f]{64}\.png$/u.test(expectedFilename)
    || typeof nonce !== 'string'
    || !/^[0-9a-f]{64}$/u.test(nonce)
    || expectedFilename !== `moonlit-${nonce}.png`
    || !Number.isFinite(requestedAtMs)
    || requestedAtMs <= 0
  ) {
    fail('Xcode screenshot handoff nonce request is invalid');
  }
}

export function xcodeScreenshotHandoffPaths(inbox, expectedFilename, nonce) {
  assertCurrentXcodeScreenshotInbox(inbox);
  assertXcodeHandoffRequest(expectedFilename, nonce, 1);
  const receiptFilename = `${expectedFilename}.receipt.json`;
  return Object.freeze({
    finalPath: join(inbox.path, expectedFilename),
    partialPath: join(inbox.path, `.${expectedFilename}.partial-${nonce}`),
    receiptPath: join(inbox.path, receiptFilename),
    receiptPartialPath: join(inbox.path, `.${receiptFilename}.partial-${nonce}`),
    receiptFilename,
  });
}

function lstatOrNull(path) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
}

function fsyncDirectory(path) {
  const descriptor = openSync(path, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  try {
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
}

/** Remove only the four exact nonce-bound handoff entries; never recurse. */
export function removeXcodeScreenshotHandoffEntries({ inbox, expectedFilename, nonce }) {
  const paths = xcodeScreenshotHandoffPaths(inbox, expectedFilename, nonce);
  const failures = [];
  for (const path of [
    paths.finalPath,
    paths.partialPath,
    paths.receiptPath,
    paths.receiptPartialPath,
  ]) {
    const entry = lstatOrNull(path);
    if (entry === null) continue;
    if (entry.isDirectory() && !entry.isSymbolicLink()) {
      failures.push(`Cannot delete directory: ${path}`);
      continue;
    }
    try {
      rmSync(path, { force: true });
      assertCurrentXcodeScreenshotInbox(inbox);
    } catch (error) {
      failures.push(`${path}: ${error.message}`);
      // If the pinned inbox itself changed, further pathname cleanup is not
      // safe. Otherwise keep clearing every remaining exact nonce entry.
      try {
        assertCurrentXcodeScreenshotInbox(inbox);
      } catch {
        break;
      }
    }
  }
  if (failures.length > 0) {
    fail(`Xcode screenshot handoff cleanup did not finish: ${failures.join(' | ')}`);
  }
}

function readStableOwnerFile(inbox, path, label, maximumBytes) {
  assertCurrentXcodeScreenshotInbox(inbox);
  const before = lstatOrNull(path);
  if (before === null) return null;
  if (!before.isFile() || before.isSymbolicLink()) fail(`${label} is not a real regular file`);
  if ((before.mode & 0o777) !== 0o600) fail(`${label} mode must be exactly 0600`);
  if (typeof process.getuid === 'function' && before.uid !== process.getuid()) {
    fail(`${label} owner differs from the current user`);
  }
  if (before.size <= 0 || before.size > maximumBytes) fail(`${label} size is outside the allowed range`);
  assertCurrentXcodeScreenshotInbox(inbox);
  const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  let opened;
  let bytes;
  let after;
  try {
    opened = fstatSync(descriptor);
    if (!opened.isFile() || !sameFilesystemEntry(before, opened)) fail(`${label} changed before open`);
    bytes = readFileSync(descriptor);
    after = fstatSync(descriptor);
    if (!sameFilesystemEntry(opened, after)) fail(`${label} changed while being read`);
  } finally {
    closeSync(descriptor);
  }
  assertCurrentXcodeScreenshotInbox(inbox);
  const final = lstatSync(path);
  if (!sameFilesystemEntry(after, final) || final.birthtimeMs !== before.birthtimeMs) {
    fail(`${label} pathname changed while being read`);
  }
  assertCurrentXcodeScreenshotInbox(inbox);
  return { bytes, stat: final };
}

function writeFsyncedExclusive(path, bytes) {
  const descriptor = openSync(path, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  try {
    writeFileSync(descriptor, bytes);
    fchmodSync(descriptor, 0o600);
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
  return lstatSync(path);
}

function canonicalFlatJsonBytes(value) {
  const sorted = Object.fromEntries(
    Object.keys(value).sort().map((key) => [key, value[key]]),
  );
  return {
    value: sorted,
    bytes: Buffer.from(`${JSON.stringify(sorted)}\n`, 'utf8'),
  };
}

/** Publish a screenshot using the only accepted .partial -> rename protocol. */
export function publishXcodeScreenshotHandoff({
  inbox,
  sourcePath,
  expectedFilename,
  nonce,
  requestedAtMs,
  expectedWidth = IOS_XCODE_IPAD_LANDSCAPE_SIZE.width,
  expectedHeight = IOS_XCODE_IPAD_LANDSCAPE_SIZE.height,
}) {
  assertXcodeHandoffRequest(expectedFilename, nonce, requestedAtMs);
  const paths = xcodeScreenshotHandoffPaths(inbox, expectedFilename, nonce);
  if (typeof sourcePath !== 'string' || sourcePath.length === 0) fail('Xcode screenshot source is missing');
  for (const path of Object.values(paths).filter((value) => typeof value === 'string' && isAbsolute(value))) {
    if (lstatOrNull(path) !== null) fail(`Xcode screenshot handoff target already exists: ${path}`);
  }
  let published = false;
  try {
    const sourceBefore = lstatSync(sourcePath);
    if (!sourceBefore.isFile() || sourceBefore.isSymbolicLink() || sourceBefore.size > MAX_XCODE_SCREENSHOT_BYTES) {
      fail('Xcode screenshot source is not an allowed regular file');
    }
    if (sourceBefore.birthtimeMs < requestedAtMs || sourceBefore.mtimeMs < requestedAtMs) {
      fail('Xcode screenshot source was not newly created after the screenshot request');
    }
    const sourceDescriptor = openSync(sourcePath, constants.O_RDONLY | constants.O_NOFOLLOW);
    let bytes;
    try {
      if (!sameFilesystemEntry(sourceBefore, fstatSync(sourceDescriptor))) fail('Xcode screenshot source changed before open');
      bytes = readFileSync(sourceDescriptor);
      if (!sameFilesystemEntry(sourceBefore, fstatSync(sourceDescriptor))) fail('Xcode screenshot source changed while being read');
    } finally {
      closeSync(sourceDescriptor);
    }
    const size = assertCompletePng(bytes, 'Xcode screenshot source');
    if (size.width !== expectedWidth || size.height !== expectedHeight) {
      fail(`Xcode screenshot source is not ${expectedWidth}x${expectedHeight}`);
    }
    const partial = writeFsyncedExclusive(paths.partialPath, bytes);
    assertCurrentXcodeScreenshotInbox(inbox);
    renameSync(paths.partialPath, paths.finalPath);
    fsyncDirectory(inbox.path);
    const final = lstatSync(paths.finalPath);
    if (partial.dev !== final.dev || partial.ino !== final.ino) fail('Xcode screenshot atomic rename inode differs');
    const digest = createHash('sha256').update(bytes).digest('hex');
    const receiptValue = {
      schema: 1,
      protocol: XCODE_HANDOFF_PROTOCOL,
      nonce,
      expected_filename: expectedFilename,
      partial_filename: basename(paths.partialPath),
      png_sha256: digest,
      png_size: bytes.length,
      source_birthtime_ms: sourceBefore.birthtimeMs,
      source_mtime_ms: sourceBefore.mtimeMs,
      final_dev: String(final.dev),
      final_ino: String(final.ino),
      final_birthtime_ms: final.birthtimeMs,
      final_mtime_ms: final.mtimeMs,
      file_fsync_before_rename: true,
      directory_fsync_after_rename: true,
      published_at_ms: Date.now(),
    };
    const { value: receipt, bytes: receiptBytes } = canonicalFlatJsonBytes(receiptValue);
    writeFsyncedExclusive(paths.receiptPartialPath, receiptBytes);
    renameSync(paths.receiptPartialPath, paths.receiptPath);
    fsyncDirectory(inbox.path);
    published = true;
    return { ...paths, receipt, sha256: digest, size };
  } finally {
    if (!published) removeXcodeScreenshotHandoffEntries({ inbox, expectedFilename, nonce });
  }
}

function validateXcodeScreenshotCandidate({
  inbox,
  expectedFilename,
  nonce,
  requestedAtMs,
  forbiddenSha256,
  expectedWidth,
  expectedHeight,
}) {
  assertXcodeHandoffRequest(expectedFilename, nonce, requestedAtMs);
  if (!(forbiddenSha256 instanceof Set)) fail('Xcode screenshot duplicate-hash set is invalid');
  const paths = xcodeScreenshotHandoffPaths(inbox, expectedFilename, nonce);
  const finalEntry = lstatOrNull(paths.finalPath);
  const receiptEntry = lstatOrNull(paths.receiptPath);
  if (finalEntry === null || receiptEntry === null) return null;
  if (lstatOrNull(paths.partialPath) !== null || lstatOrNull(paths.receiptPartialPath) !== null) {
    fail('Xcode screenshot handoff partial remains after atomic publish');
  }
  const receiptFile = readStableOwnerFile(inbox, paths.receiptPath, 'Xcode screenshot handoff receipt', 64 * 1024);
  let receipt;
  try {
    receipt = JSON.parse(receiptFile.bytes.toString('utf8'));
  } catch {
    fail('Xcode screenshot handoff receipt JSON is invalid');
  }
  const pngFile = readStableOwnerFile(inbox, paths.finalPath, 'Xcode screenshot handoff PNG', MAX_XCODE_SCREENSHOT_BYTES);
  const size = assertCompletePng(pngFile.bytes, 'Xcode Devices screenshot handoff');
  const digest = createHash('sha256').update(pngFile.bytes).digest('hex');
  if (
    !isRecord(receipt)
    || receipt.schema !== 1
    || receipt.protocol !== XCODE_HANDOFF_PROTOCOL
    || receipt.nonce !== nonce
    || receipt.expected_filename !== expectedFilename
    || receipt.partial_filename !== basename(paths.partialPath)
    || receipt.png_sha256 !== digest
    || receipt.png_size !== pngFile.bytes.length
    || !Number.isFinite(receipt.source_birthtime_ms)
    || !Number.isFinite(receipt.source_mtime_ms)
    || receipt.source_birthtime_ms < requestedAtMs
    || receipt.source_mtime_ms < requestedAtMs
    || receipt.final_dev !== String(pngFile.stat.dev)
    || receipt.final_ino !== String(pngFile.stat.ino)
    || receipt.final_birthtime_ms !== pngFile.stat.birthtimeMs
    || receipt.final_mtime_ms !== pngFile.stat.mtimeMs
    || receipt.file_fsync_before_rename !== true
    || receipt.directory_fsync_after_rename !== true
    || !Number.isFinite(receipt.published_at_ms)
    || receipt.published_at_ms < requestedAtMs
    || pngFile.stat.birthtimeMs < requestedAtMs
    || pngFile.stat.mtimeMs < requestedAtMs
  ) {
    fail('Xcode screenshot handoff receipt does not prove PNG atomic publish');
  }
  if (size.width !== expectedWidth || size.height !== expectedHeight) {
    fail(`Xcode screenshot handoff is not ${expectedWidth}x${expectedHeight}: ${size.width}x${size.height}`);
  }
  if (forbiddenSha256.has(digest)) fail('Xcode screenshot handoff PNG hash duplicates a previous capture');
  return {
    path: paths.finalPath,
    receiptPath: paths.receiptPath,
    bytes: pngFile.bytes,
    receiptBytes: receiptFile.bytes,
    receipt,
    size,
    sha256: digest,
    birthtimeMs: pngFile.stat.birthtimeMs,
    mtimeMs: pngFile.stat.mtimeMs,
    observationKey: JSON.stringify({
      png: [
        pngFile.stat.dev,
        pngFile.stat.ino,
        pngFile.stat.mode,
        pngFile.stat.size,
        pngFile.stat.birthtimeMs,
        pngFile.stat.mtimeMs,
        pngFile.stat.ctimeMs,
        digest,
      ],
      receipt: [
        receiptFile.stat.dev,
        receiptFile.stat.ino,
        receiptFile.stat.mode,
        receiptFile.stat.size,
        receiptFile.stat.birthtimeMs,
        receiptFile.stat.mtimeMs,
        receiptFile.stat.ctimeMs,
        createHash('sha256').update(receiptFile.bytes).digest('hex'),
      ],
    }),
  };
}

/** Wait for two stable observations of one atomically published Xcode frame. */
export async function waitForXcodeScreenshotHandoff({
  inbox,
  expectedFilename,
  nonce,
  requestedAtMs,
  forbiddenSha256,
  expectedWidth = IOS_XCODE_IPAD_LANDSCAPE_SIZE.width,
  expectedHeight = IOS_XCODE_IPAD_LANDSCAPE_SIZE.height,
  timeoutMs = 120_000,
  pollIntervalMs = 120,
  continuityProbe = null,
  continuityProbeIntervalMs = 2_000,
  cancellationProbe = null,
}) {
  if (
    !Number.isSafeInteger(expectedWidth)
    || !Number.isSafeInteger(expectedHeight)
    || expectedWidth <= expectedHeight
    || !Number.isSafeInteger(timeoutMs)
    || timeoutMs <= 0
    || !Number.isSafeInteger(pollIntervalMs)
    || pollIntervalMs <= 0
    || (continuityProbe !== null && typeof continuityProbe !== 'function')
    || !Number.isSafeInteger(continuityProbeIntervalMs)
    || continuityProbeIntervalMs <= 0
    || (cancellationProbe !== null && typeof cancellationProbe !== 'function')
  ) {
    fail('Xcode screenshot handoff wait contract is invalid');
  }
  assertXcodeHandoffRequest(expectedFilename, nonce, requestedAtMs);
  const deadline = requestedAtMs + timeoutMs;
  let nextContinuityProbe = Date.now() + continuityProbeIntervalMs;
  let firstObservation = null;
  while (true) {
    if (cancellationProbe !== null) cancellationProbe();
    const now = Date.now();
    if (now >= deadline) fail(`Did not receive Xcode screenshot handoff within ${timeoutMs / 1000}s`);
    if (continuityProbe !== null && now >= nextContinuityProbe) {
      const remainingMs = deadline - now;
      const result = continuityProbe({ deadlineMs: deadline, remainingMs });
      if (result !== null && typeof result === 'object' && typeof result.then === 'function') {
        fail('Xcode screenshot handoff continuity probe must be synchronous');
      }
      if (Date.now() >= deadline) fail(`Did not receive Xcode screenshot handoff within ${timeoutMs / 1000}s`);
      nextContinuityProbe = Date.now() + continuityProbeIntervalMs;
    }
    const candidate = validateXcodeScreenshotCandidate({
      inbox,
      expectedFilename,
      nonce,
      requestedAtMs,
      forbiddenSha256,
      expectedWidth,
      expectedHeight,
    });
    if (Date.now() >= deadline) {
      fail(`Did not receive Xcode screenshot handoff within ${timeoutMs / 1000}s`);
    }
    if (candidate !== null) {
      if (firstObservation !== null) {
        if (candidate.observationKey !== firstObservation.observationKey) {
          fail('Xcode screenshot handoff changed between stable observations');
        }
        return candidate;
      }
      firstObservation = candidate;
    }
    const remaining = deadline - Date.now();
    if (remaining <= 0) fail(`Did not receive Xcode screenshot handoff within ${timeoutMs / 1000}s`);
    await new Promise((resolvePromise) => {
      setTimeout(resolvePromise, Math.min(pollIntervalMs, remaining));
    });
    if (cancellationProbe !== null) cancellationProbe();
  }
}

/**
 * Hash the complete app-tree structure with domain-separated entry types.
 * Directories (including empty ones), regular files, modes, and symlink targets
 * all contribute independently, so a file cannot impersonate a symlink.
 */
export function iosAppTreeSha256(root) {
  if (typeof root !== 'string' || root.length === 0) {
    fail('iOS app tree path is missing');
  }
  const rootStat = lstatSync(root);
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) {
    fail('iOS app tree root is not a real directory');
  }
  const hash = createHash('sha256');

  function record(type, relativePath, mode, payload = Buffer.alloc(0)) {
    updateLengthPrefixed(hash, type);
    updateLengthPrefixed(hash, relativePath);
    updateLengthPrefixed(hash, String(mode & 0o7777));
    updateLengthPrefixed(hash, payload);
  }

  function visit(path, relativePath) {
    const before = lstatSync(path);
    if (before.isDirectory() && !before.isSymbolicLink()) {
      record('directory', relativePath, before.mode);
      for (const name of readdirSync(path).sort()) {
        visit(join(path, name), relativePath === '.' ? name : `${relativePath}/${name}`);
      }
    } else if (before.isSymbolicLink()) {
      record('symlink', relativePath, before.mode, Buffer.from(readlinkSync(path), 'utf8'));
    } else if (before.isFile()) {
      const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
      let bytes;
      try {
        const opened = fstatSync(descriptor);
        if (!opened.isFile() || !sameFilesystemEntry(before, opened)) {
          fail(`iOS app tree entry changed while hashing: ${relativePath}`);
        }
        bytes = readFileSync(descriptor);
        if (!sameFilesystemEntry(opened, fstatSync(descriptor))) {
          fail(`iOS app tree file changed while hashing: ${relativePath}`);
        }
      } finally {
        closeSync(descriptor);
      }
      record('file', relativePath, before.mode, bytes);
    } else {
      fail(`Unsupported .app entry: ${relativePath}`);
    }
    if (!sameFilesystemEntry(before, lstatSync(path))) {
      fail(`iOS app tree entry changed during traversal: ${relativePath}`);
    }
  }

  visit(root, '.');
  return hash.digest('hex');
}

/**
 * Native DVT screenshots can take several seconds while localized live HUD
 * counters keep changing their minimum size. Both observations must still pass
 * the full safe-area contract and keep the same anchor; only that content-driven
 * width/height is normalized before the ordinary semantic stability check.
 */
export function assertStableIosArenaCaptureState(before, after, expected) {
  if (!isRecord(expected) || expected.kind !== 'arena_ready') {
    fail('iOS arena stability check kind is invalid');
  }
  const normalizedBefore = assertStoreCaptureState(before, expected);
  const normalizedAfter = assertStoreCaptureState(after, expected);
  const beforeRect = normalizedBefore.hud_left_rect;
  const afterRect = normalizedAfter.hud_left_rect;
  if (beforeRect[0] !== afterRect[0] || beforeRect[1] !== afterRect[1]) {
    fail('Left HUD anchor changed during iOS screenshot');
  }
  return assertStableStoreCaptureState(
    before,
    { ...after, hud_left_rect: [...before.hud_left_rect] },
    expected,
  );
}

/**
 * Keep purchase receipts and other device-only secrets out of build evidence.
 * The callback is deliberately synchronous: CoreDevice copies are synchronous
 * in the producer, so the path can be removed before the function returns or
 * rethrows.
 */
export function withEphemeralFilesystemPath(path, operation) {
  if (typeof path !== 'string' || path.length === 0) {
    fail('Sensitive temp path is missing');
  }
  if (typeof operation !== 'function') fail('Sensitive temp path operation is not a function');
  try {
    const value = operation();
    if (value !== null && typeof value === 'object' && typeof value.then === 'function') {
      fail('Sensitive temp path operation must be synchronous');
    }
    return value;
  } finally {
    rmSync(path, { force: true, recursive: true });
  }
}

/**
 * Keep a synchronous install tree filesystem-immutable for the entire
 * operation, while guaranteeing that cleanup can remove it afterward.
 */
export function withImmutableFilesystemPath(path, operation, changeImmutable) {
  if (typeof path !== 'string' || path.length === 0) {
    fail('iOS immutable path is missing');
  }
  if (typeof operation !== 'function' || typeof changeImmutable !== 'function') {
    fail('iOS immutable path operation is not a function');
  }
  try {
    changeImmutable(path, true);
  } catch (sealFailure) {
    try {
      // A recursive flag operation may fail after changing only part of the
      // tree. Always attempt to make the private copy removable again.
      changeImmutable(path, false);
    } catch (cleanupFailure) {
      throw new Error(
        `Both iOS immutable path set and restore failed: `
        + `${sealFailure.message}; restore failed: ${cleanupFailure.message}`,
        { cause: cleanupFailure },
      );
    }
    throw sealFailure;
  }
  let value;
  let operationFailure = null;
  let cleanupFailure = null;
  try {
    value = operation();
    if (value !== null && typeof value === 'object' && typeof value.then === 'function') {
      fail('iOS immutable path operation must be synchronous');
    }
  } catch (error) {
    operationFailure = error;
  } finally {
    try {
      changeImmutable(path, false);
    } catch (error) {
      cleanupFailure = error;
    }
  }
  if (cleanupFailure !== null) {
    const original = operationFailure === null
      ? ''
      : `; original operation failed: ${operationFailure.message}`;
    throw new Error(
      `iOS immutable path unseal failed: ${cleanupFailure.message}${original}`,
      { cause: cleanupFailure },
    );
  }
  if (operationFailure !== null) throw operationFailure;
  return value;
}

/** Convert asynchronous host signals into a rejection that callers can route
 * through mandatory device cleanup instead of letting Node exit immediately. */
export function createDeferredCancellation() {
  let requestedError = null;
  let rejectCancellation;
  const cancellation = new Promise((_resolvePromise, rejectPromise) => {
    rejectCancellation = rejectPromise;
  });
  // A signal can arrive before the first operation is raced. Keep Node from
  // reporting that deliberate deferred rejection as unhandled.
  cancellation.catch(() => {});
  return Object.freeze({
    request(signal) {
      if (requestedError === null) {
        requestedError = new Error(`iOS capture was canceled by ${signal} signal`);
        requestedError.code = 'ECANCELED';
        requestedError.signal = signal;
        rejectCancellation(requestedError);
      }
      return requestedError;
    },
    throwIfRequested() {
      if (requestedError !== null) throw requestedError;
    },
    race(operation) {
      if (requestedError !== null) return Promise.reject(requestedError);
      return Promise.race([Promise.resolve(operation), cancellation]);
    },
  });
}

/** Let callbacks for signals delivered during a synchronous child command run
 * before a completed cleanup is allowed to become a successful report. */
export async function waitForPendingHostSignalHandlers() {
  // Signals delivered during spawnSync are processed in the poll phase.
  // setImmediate (check phase) can finish first on macOS, and a single 0ms
  // timer is still racy there. Drain check + poll twice, with a 1ms timer so
  // libuv actually waits for pending signals.
  await new Promise((resolvePromise) => setImmediate(resolvePromise));
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 1));
  await new Promise((resolvePromise) => setImmediate(resolvePromise));
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 1));
}

/**
 * Settle an operation without ever skipping its cleanup. Both failures are
 * returned so callers can write one evidence-safe failure report after device
 * restoration has finished.
 */
export async function settleWithMandatoryCleanup(operation, cleanup) {
  if (typeof operation !== 'function' || typeof cleanup !== 'function') {
    fail('iOS operation/cleanup must be functions');
  }
  let value;
  let operationFailure = null;
  let cleanupValue;
  let cleanupFailure = null;
  try {
    try {
      value = await operation();
    } catch (error) {
      operationFailure = error;
    }
  } finally {
    try {
      cleanupValue = await cleanup();
    } catch (error) {
      cleanupFailure = error;
    }
  }
  return { value, operationFailure, cleanupValue, cleanupFailure };
}

export function pngSize(bytes, label = 'iOS screenshot') {
  const value = Buffer.from(bytes);
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (value.length < 24 || !value.subarray(0, 8).equals(signature)) {
    fail(`${label} is not a PNG`);
  }
  return {
    width: value.readUInt32BE(16),
    height: value.readUInt32BE(20),
  };
}

/**
 * Godot reports safe geometry in stretched viewport coordinates while DVT
 * returns the physical iOS framebuffer.  Verify the scale and every edge in
 * physical pixels so an iPad screenshot cannot pass on logical booleans alone.
 */
export function assertPhysicalIosSafeLayout(
  safeLayout,
  png,
  { minimumPhysicalInset = 34 } = {},
) {
  if (!isRecord(safeLayout)) fail('iOS device safe-area layout proof is missing');
  const viewport = finiteRect(safeLayout.viewport_rect, 'viewport_rect');
  const safe = finiteRect(safeLayout.safe_rect, 'safe_rect');
  if (
    !isRecord(png)
    || !Number.isSafeInteger(png.width)
    || !Number.isSafeInteger(png.height)
    || png.width <= 0
    || png.height <= 0
  ) {
    fail('iOS PNG physical size is invalid');
  }
  if (!Number.isFinite(minimumPhysicalInset) || minimumPhysicalInset <= 0) {
    fail('iOS minimum physical safe-area inset is invalid');
  }

  const viewportEndX = viewport[0] + viewport[2];
  const viewportEndY = viewport[1] + viewport[3];
  const safeEndX = safe[0] + safe[2];
  const safeEndY = safe[1] + safe[3];
  if (
    safe[0] < viewport[0] - 0.5
    || safe[1] < viewport[1] - 0.5
    || safeEndX > viewportEndX + 0.5
    || safeEndY > viewportEndY + 0.5
  ) {
    fail('iOS safe_rect is outside the viewport');
  }

  const scaleX = png.width / viewport[2];
  const scaleY = png.height / viewport[3];
  const relativeScaleDelta = Math.abs(scaleX - scaleY) / Math.max(scaleX, scaleY);
  if (!Number.isFinite(scaleX) || !Number.isFinite(scaleY) || relativeScaleDelta > 0.02) {
    fail(`iOS PNG and Godot viewport scale differ: ${scaleX}x${scaleY}`);
  }
  const insets = {
    left: (safe[0] - viewport[0]) * scaleX,
    top: (safe[1] - viewport[1]) * scaleY,
    right: (viewportEndX - safeEndX) * scaleX,
    bottom: (viewportEndY - safeEndY) * scaleY,
  };
  for (const [edge, inset] of Object.entries(insets)) {
    if (!Number.isFinite(inset) || inset + 0.05 < minimumPhysicalInset) {
      fail(`iOS ${edge} physical safe-area inset is below ${minimumPhysicalInset}px: ${inset}`);
    }
  }
  return {
    png_size: [png.width, png.height],
    viewport_scale: { x: scaleX, y: scaleY },
    minimum_physical_inset: minimumPhysicalInset,
    physical_insets: insets,
  };
}

export function assertPhysicalIosDevice(
  payload,
  {
    target,
    coreDeviceIdentifier,
    usbUdid,
  },
) {
  if (!isRecord(payload) || !isRecord(payload.result)) {
    fail('CoreDevice physical-device detail JSON is invalid');
  }
  const result = payload.result;
  const hardware = result.hardwareProperties;
  const device = result.deviceProperties;
  const connection = result.connectionProperties;
  if (!isRecord(hardware) || !isRecord(device) || !isRecord(connection)) {
    fail('CoreDevice physical-device hardware/device/connection proof is missing');
  }
  const expectedType = target === 'ipad-13' ? 'iPad' : 'iPhone';
  if (
    !['ipad-13', 'iphone-6.5'].includes(target)
    || result.identifier !== coreDeviceIdentifier
    || hardware.reality !== 'physical'
    || hardware.deviceType !== expectedType
    || typeof hardware.productType !== 'string'
    || !hardware.productType.startsWith(expectedType)
    || hardware.udid !== usbUdid
    || device.bootState !== 'booted'
    || device.developerModeStatus !== 'enabled'
    || typeof device.name !== 'string'
    || device.name.trim() === ''
    || typeof device.osVersionNumber !== 'string'
    || device.osVersionNumber.trim() === ''
    || connection.pairingState !== 'paired'
    || !['wired', 'localNetwork'].includes(connection.transportType)
    || connection.tunnelState !== 'connected'
    || typeof connection.tunnelIPAddress !== 'string'
    || connection.tunnelIPAddress.trim() === ''
  ) {
    fail(`${target} CoreDevice differs from the connected physical ${expectedType} contract`);
  }
  return {
    physical_device: true,
    simulator: false,
    device_udid: usbUdid,
    coredevice_identifier: coreDeviceIdentifier,
    device_name: device.name,
    marketing_name: hardware.marketingName,
    model_identifier: hardware.productType,
    os_version: device.osVersionNumber,
    os_build: device.osBuildUpdate,
    transport: connection.transportType,
    rsd_host: connection.tunnelIPAddress,
  };
}

/**
 * Bind a RemoteServiceDiscovery endpoint to the already verified CoreDevice.
 * The RSD handshake contains stable serials and other private hardware data,
 * so only return the non-sensitive fields needed by downstream evidence.
 */
export function assertRsdIosDeviceIdentity(payload, coreDeviceIdentity) {
  if (!isRecord(payload) || !isRecord(payload.Properties)) {
    fail('RSD device info JSON is invalid');
  }
  if (
    !isRecord(coreDeviceIdentity)
    || coreDeviceIdentity.physical_device !== true
    || coreDeviceIdentity.simulator !== false
    || typeof coreDeviceIdentity.device_udid !== 'string'
    || coreDeviceIdentity.device_udid.length === 0
    || typeof coreDeviceIdentity.model_identifier !== 'string'
    || coreDeviceIdentity.model_identifier.length === 0
    || typeof coreDeviceIdentity.os_version !== 'string'
    || coreDeviceIdentity.os_version.length === 0
    || typeof coreDeviceIdentity.os_build !== 'string'
    || coreDeviceIdentity.os_build.length === 0
  ) {
    fail('Verified CoreDevice identity is invalid');
  }

  const properties = payload.Properties;
  if (
    properties.UniqueDeviceID !== coreDeviceIdentity.device_udid
    || properties.ProductType !== coreDeviceIdentity.model_identifier
    || properties.OSVersion !== coreDeviceIdentity.os_version
    || properties.BuildVersion !== coreDeviceIdentity.os_build
    || properties.IsVirtualDevice !== false
  ) {
    fail('RSD endpoint differs from the verified physical CoreDevice identity');
  }

  return {
    physical_device: true,
    simulator: false,
    model_identifier: properties.ProductType,
    os_version: properties.OSVersion,
    os_build: properties.BuildVersion,
  };
}

export function assertInstalledIosApp(
  payload,
  {
    bundleId,
    shortVersion,
    buildVersion,
    coreDeviceIdentifier,
  },
) {
  const result = payload?.result;
  if (!isRecord(result) || !Array.isArray(result.apps)) {
    fail('Installed iOS app JSON is invalid');
  }
  const matches = result.apps.filter((app) => app?.bundleIdentifier === bundleId);
  if (
    matches.length !== 1
    || result.deviceIdentifier !== coreDeviceIdentifier
    || result.matchingBundleIdentifier !== bundleId
  ) {
    fail('Installed target bundle ID on the device is not exactly one');
  }
  const app = matches[0];
  if (
    app.version !== shortVersion
    || app.bundleVersion !== buildVersion
    || app.builtByDeveloper !== true
    || app.removable !== true
    || typeof app.url !== 'string'
    || !app.url.endsWith('.app/')
  ) {
    fail('Installed iOS app version, build, or development signing identity differs');
  }
  return app;
}

/**
 * Bind the app handed to CoreDevice to the preserved, attested ZIP. The
 * producer calls this after extracting its private install copy and again
 * immediately around installation, so a later writer cannot silently replace
 * either the archive or the exact app tree while the report keeps old hashes.
 */
export function assertFrozenIosInstallArtifact({
  artifactSha256,
  currentArtifactSha256,
  appTreeSha256,
  currentAppTreeSha256,
}) {
  for (const [label, value] of Object.entries({
    artifactSha256,
    currentArtifactSha256,
    appTreeSha256,
    currentAppTreeSha256,
  })) {
    if (typeof value !== 'string' || !SHA256_PATTERN.test(value)) {
      fail(`iOS frozen install ${label} is not a valid SHA-256`);
    }
  }
  if (currentArtifactSha256 !== artifactSha256) {
    fail('iOS frozen install preservation ZIP changed after attestation');
  }
  if (currentAppTreeSha256 !== appTreeSha256) {
    fail('iOS frozen install .app tree differs from the preservation ZIP contract');
  }
  return true;
}

export function coreDeviceRsdPortCandidates(lsofOutput, rsdHost) {
  if (typeof lsofOutput !== 'string' || typeof rsdHost !== 'string' || !rsdHost) {
    fail('CoreDevice socket list and RSD host are required');
  }
  const escaped = rsdHost.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const pattern = new RegExp(`->\\[${escaped}\\]:(\\d+)`, 'gu');
  return [...new Set(
    [...lsofOutput.matchAll(pattern)]
      .map((match) => Number(match[1]))
      .filter((port) => Number.isSafeInteger(port) && port > 0 && port <= 65_535),
  )];
}

export function assertByteExactRestoration(before, after, label) {
  if (before === null || after === null) {
    if (before !== after) fail(`${label} presence changed across the capture`);
    return true;
  }
  if (!Buffer.from(before).equals(Buffer.from(after))) {
    fail(`${label} is not byte-exact across the capture`);
  }
  return true;
}

/** Reject a save snapshot unless two independently copied views are identical. */
export function assertStableIosPersistentSnapshots(before, after) {
  if (!isRecord(before) || !isRecord(after)) {
    fail('iOS persistent data snapshot is not an object');
  }
  const beforeNames = Object.keys(before).sort();
  const afterNames = Object.keys(after).sort();
  if (
    beforeNames.length !== afterNames.length
    || beforeNames.some((name, index) => name !== afterNames[index])
  ) {
    fail('iOS persistent data file list changed during snapshot');
  }
  for (const name of beforeNames) {
    assertByteExactRestoration(before[name], after[name], name);
  }
  return true;
}

export function assertCompleteIosCaptureManifest({
  captures,
  locales,
  filenames,
  artifactSha256,
  captureMethod = IOS_RSD_CAPTURE_METHOD,
}) {
  if (!Array.isArray(captures) || !Array.isArray(locales) || !Array.isArray(filenames)) {
    fail('iOS device capture manifest contract is invalid');
  }
  if (!SHA256_PATTERN.test(artifactSha256)) {
    fail('iOS capture build artifact SHA-256 is invalid');
  }
  if (![IOS_RSD_CAPTURE_METHOD, IOS_XCODE_HANDOFF_CAPTURE_METHOD].includes(captureMethod)) {
    fail('iOS capture method contract is invalid');
  }
  const expected = new Set();
  for (const locale of locales) {
    if (typeof locale !== 'string' || locale.trim() === '') fail('iOS locale contract is invalid');
    for (const filename of filenames) {
      if (typeof filename !== 'string' || !filename.endsWith('.png')) {
        fail('iOS screenshot filename contract is invalid');
      }
      expected.add(`${locale}/${filename}`);
    }
  }
  if (captures.length !== expected.size) {
    fail(`iOS device capture has ${captures.length} image(s) (contract ${expected.size})`);
  }

  const actual = new Set();
  const hashes = new Set();
  const xcodeHandoffNonces = new Set();
  const sizes = new Set();
  for (const capture of captures) {
    if (!isRecord(capture)) fail('iOS capture manifest entry is invalid');
    const key = `${capture.asset_locale}/${capture.filename}`;
    if (!expected.has(key) || actual.has(key)) fail(`Duplicate or unexpected iOS capture: ${key}`);
    actual.add(key);
    if (!SHA256_PATTERN.test(capture.sha256) || hashes.has(capture.sha256)) {
      fail(`iOS capture PNG is duplicated or its hash is wrong: ${key}`);
    }
    hashes.add(capture.sha256);
    if (
      !Number.isSafeInteger(capture.width)
      || !Number.isSafeInteger(capture.height)
      || capture.width <= capture.height
      || capture.native_device_framebuffer !== true
      || capture.capture_method !== captureMethod
    ) {
      fail(`iOS capture is not a valid native landscape PNG: ${key}`);
    }
    if (
      captureMethod === IOS_RSD_CAPTURE_METHOD
      && (
        typeof capture.rsd_host !== 'string'
        || capture.rsd_host.length === 0
        || !Number.isSafeInteger(capture.rsd_port)
        || capture.rsd_port <= 0
        || XCODE_CAPTURE_ONLY_FIELDS.some((field) => capture[field] !== null)
      )
    ) {
      fail(`iOS RSD capture transport-only proof is invalid: ${key}`);
    }
    if (
      captureMethod === IOS_XCODE_HANDOFF_CAPTURE_METHOD
      && (
        capture.rsd_host !== null
        || capture.rsd_port !== null
        || !isRecord(capture.xcode_handoff_receipt)
        || typeof capture.xcode_handoff_requested_at !== 'string'
        || !Number.isFinite(Date.parse(capture.xcode_handoff_requested_at))
        || typeof capture.xcode_handoff_accepted_at !== 'string'
        || !Number.isFinite(Date.parse(capture.xcode_handoff_accepted_at))
        || capture.width !== IOS_XCODE_IPAD_LANDSCAPE_SIZE.width
        || capture.height !== IOS_XCODE_IPAD_LANDSCAPE_SIZE.height
        || typeof capture.xcode_handoff_nonce !== 'string'
        || !/^[0-9a-f]{64}$/u.test(capture.xcode_handoff_nonce)
        || capture.xcode_handoff_expected_filename
          !== `moonlit-${capture.xcode_handoff_nonce}.png`
        || xcodeHandoffNonces.has(capture.xcode_handoff_nonce)
        || !Number.isFinite(capture.xcode_handoff_requested_at_unix_ms)
        || !Number.isFinite(capture.xcode_handoff_birthtime_unix_ms)
        || !Number.isFinite(capture.xcode_handoff_mtime_unix_ms)
        || capture.xcode_handoff_birthtime_unix_ms
          <= capture.xcode_handoff_requested_at_unix_ms
        || capture.xcode_handoff_mtime_unix_ms
          <= capture.xcode_handoff_requested_at_unix_ms
        || capture.xcode_handoff_stable_observations !== 2
        || capture.xcode_handoff_complete_png_decoded !== true
        || capture.xcode_handoff_receipt.schema !== 1
        || capture.xcode_handoff_receipt.protocol !== XCODE_HANDOFF_PROTOCOL
        || capture.xcode_handoff_receipt.nonce !== capture.xcode_handoff_nonce
        || capture.xcode_handoff_receipt.expected_filename
          !== capture.xcode_handoff_expected_filename
        || capture.xcode_handoff_receipt.partial_filename
          !== `.${capture.xcode_handoff_expected_filename}.partial-${capture.xcode_handoff_nonce}`
        || capture.xcode_handoff_receipt.png_sha256 !== capture.sha256
        || !Number.isFinite(capture.xcode_handoff_receipt.source_birthtime_ms)
        || !Number.isFinite(capture.xcode_handoff_receipt.source_mtime_ms)
        || capture.xcode_handoff_receipt.source_birthtime_ms
          < capture.xcode_handoff_requested_at_unix_ms
        || capture.xcode_handoff_receipt.source_mtime_ms
          < capture.xcode_handoff_requested_at_unix_ms
        || capture.xcode_handoff_receipt.final_birthtime_ms
          !== capture.xcode_handoff_birthtime_unix_ms
        || capture.xcode_handoff_receipt.final_mtime_ms
          !== capture.xcode_handoff_mtime_unix_ms
        || capture.xcode_handoff_receipt.file_fsync_before_rename !== true
        || capture.xcode_handoff_receipt.directory_fsync_after_rename !== true
        || !SHA256_PATTERN.test(capture.xcode_handoff_receipt_sha256)
        || !Number.isSafeInteger(capture.xcode_handoff_process_id)
        || capture.xcode_handoff_process_id <= 0
        || capture.xcode_activation_process_id !== capture.xcode_handoff_process_id
        || !IOS_EVIDENCE_JSON_PATH_PATTERN.test(
          capture.xcode_activation_launch_path,
        )
        || !SHA256_PATTERN.test(capture.xcode_activation_launch_sha256)
        || !IOS_EVIDENCE_JSON_PATH_PATTERN.test(
          capture.xcode_activation_processes_path,
        )
        || !SHA256_PATTERN.test(capture.xcode_activation_processes_sha256)
        || !IOS_EVIDENCE_JSON_PATH_PATTERN.test(
          capture.xcode_handoff_device_details_before_path,
        )
        || !SHA256_PATTERN.test(capture.xcode_handoff_device_details_before_sha256)
        || !IOS_EVIDENCE_JSON_PATH_PATTERN.test(
          capture.xcode_handoff_processes_before_path,
        )
        || !SHA256_PATTERN.test(capture.xcode_handoff_processes_before_sha256)
        || !IOS_EVIDENCE_JSON_PATH_PATTERN.test(
          capture.xcode_handoff_device_details_after_path,
        )
        || !SHA256_PATTERN.test(capture.xcode_handoff_device_details_after_sha256)
        || !IOS_EVIDENCE_JSON_PATH_PATTERN.test(
          capture.xcode_handoff_processes_after_path,
        )
        || !SHA256_PATTERN.test(capture.xcode_handoff_processes_after_sha256)
        || createHash('sha256')
          .update(canonicalFlatJsonBytes(capture.xcode_handoff_receipt).bytes)
          .digest('hex') !== capture.xcode_handoff_receipt_sha256
      )
    ) {
      fail(`iOS Xcode screenshot handoff proof is invalid: ${key}`);
    }
    if (captureMethod === IOS_XCODE_HANDOFF_CAPTURE_METHOD) {
      xcodeHandoffNonces.add(capture.xcode_handoff_nonce);
    }
    sizes.add(`${capture.width}x${capture.height}`);
    if (capture.installed_artifact_sha256 !== artifactSha256) {
      fail(`Installed build changed during iOS capture: ${key}`);
    }
    if (
      !isRecord(capture.runtime_before)
      || !isRecord(capture.runtime_after)
      || typeof capture.clean_ui_proof !== 'string'
      || capture.clean_ui_proof === ''
      || !isRecord(capture.safe_layout)
      || !isRecord(capture.physical_safe_layout)
      || typeof capture.proof_path !== 'string'
      || capture.proof_path === ''
      || typeof capture.evidence_path !== 'string'
      || capture.evidence_path === ''
    ) {
      fail(`iOS before/after, clean UI, safe-area, or source proof is missing: ${key}`);
    }
  }
  if (actual.size !== expected.size || sizes.size !== 1) {
    fail('iOS capture set is incomplete or the resolution changed');
  }
  return { capture_count: actual.size, screenshot_size: [...sizes][0] };
}
