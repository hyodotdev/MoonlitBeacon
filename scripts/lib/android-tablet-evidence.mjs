import { createHash } from 'node:crypto';

const SHA256_PATTERN = /^[0-9a-f]{64}$/u;

export const ANDROID_CAPTURE_DEVICE_CONTRACTS = Object.freeze({
  'pixel-phone': Object.freeze({
    avd_name: 'Pixel_10',
    api_level: 34,
    abi_type: 'arm64-v8a',
    image_sysdir: 'system-images/android-34/google_apis_playstore/arm64-v8a/',
    hw_device_name: 'pixel_9',
    hw_lcd_width: 1080,
    hw_lcd_height: 2424,
    hw_lcd_density: 420,
  }),
  'seven-inch-tablet': Object.freeze({
    avd_name: 'Moonlit_7_API36',
    api_level: 36,
    abi_type: 'arm64-v8a',
    image_sysdir: 'system-images/android-36/google_apis_playstore/arm64-v8a/',
    hw_device_name: '7in WSVGA (Tablet)',
    hw_lcd_width: 1024,
    hw_lcd_height: 600,
    hw_lcd_density: 160,
  }),
  'ten-inch-tablet': Object.freeze({
    avd_name: 'Moonlit_10_API36',
    api_level: 36,
    abi_type: 'arm64-v8a',
    image_sysdir: 'system-images/android-36/google_apis_playstore/arm64-v8a/',
    hw_device_name: '10.1in WXGA (Tablet)',
    hw_lcd_width: 1280,
    hw_lcd_height: 800,
    hw_lcd_density: 160,
  }),
});

const AVD_REQUIRED_KEYS = Object.freeze({
  'abi.type': 'abi_type',
  'hw.device.name': 'hw_device_name',
  'hw.lcd.width': 'hw_lcd_width',
  'hw.lcd.height': 'hw_lcd_height',
  'hw.lcd.density': 'hw_lcd_density',
  'image.sysdir.1': 'image_sysdir',
});

function fail(message) {
  throw new Error(message);
}

export function shouldRetryTabletGuardianColdStall({
  afterObservation,
  attempt,
  lastObservation,
  sawRejectedState,
  sawStateFile,
} = {}) {
  if (
    attempt !== 1
    || afterObservation !== 0
    || typeof sawRejectedState !== 'boolean'
    || typeof sawStateFile !== 'boolean'
    || sawRejectedState
  ) return false;
  if (!sawStateFile) return lastObservation === null;
  return Number.isSafeInteger(lastObservation)
    && lastObservation >= 1
    && lastObservation <= 5;
}

function hashBytes(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function parsePositiveInteger(value, label) {
  if (!/^[1-9][0-9]*$/u.test(value)) fail(`${label} value is not a positive integer.`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) fail(`${label} value is not a safe integer.`);
  return parsed;
}

export function parseAndroidAvdConfig(configBytes) {
  if (!Buffer.isBuffer(configBytes) || configBytes.length === 0) {
    fail('AVD config.ini source bytes are missing.');
  }
  const text = configBytes.toString('utf8');
  if (!Buffer.from(text, 'utf8').equals(configBytes)) {
    fail('AVD config.ini is not valid UTF-8.');
  }
  const values = new Map();
  for (const rawLine of text.split(/\r?\n/u)) {
    const line = rawLine.trim();
    if (line === '' || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator < 1) continue;
    const key = line.slice(0, separator).trim();
    if (!Object.hasOwn(AVD_REQUIRED_KEYS, key)) continue;
    if (values.has(key)) fail(`AVD config.ini required key is duplicated: ${key}`);
    const value = line.slice(separator + 1).trim();
    if (value === '') fail(`AVD config.ini required value is empty: ${key}`);
    values.set(key, value);
  }
  for (const key of Object.keys(AVD_REQUIRED_KEYS)) {
    if (!values.has(key)) fail(`AVD config.ini required key is missing: ${key}`);
  }
  const imageSysdir = values.get('image.sysdir.1');
  const apiMatch = imageSysdir.match(/^system-images\/android-([1-9][0-9]*)\//u);
  if (!apiMatch) fail('Failed to read API level from the AVD system image.');
  return Object.freeze({
    abi_type: values.get('abi.type'),
    api_level: Number(apiMatch[1]),
    hw_device_name: values.get('hw.device.name'),
    hw_lcd_width: parsePositiveInteger(values.get('hw.lcd.width'), 'hw.lcd.width'),
    hw_lcd_height: parsePositiveInteger(values.get('hw.lcd.height'), 'hw.lcd.height'),
    hw_lcd_density: parsePositiveInteger(values.get('hw.lcd.density'), 'hw.lcd.density'),
    image_sysdir: imageSysdir,
  });
}

/**
 * Prove the booted Android target and exact on-disk AVD config match the
 * canonical capture contract before any screenshot can become eligible.
 */
export function assertAndroidAvdCaptureContract({
  target,
  avdName,
  apiLevel,
  configBytes,
  physicalSize,
  density,
}) {
  const contract = ANDROID_CAPTURE_DEVICE_CONTRACTS[target];
  if (!contract) fail(`Unsupported Android capture target: ${String(target)}`);
  if (avdName !== contract.avd_name) {
    fail(`AVD name is not ${contract.avd_name}: ${String(avdName)}`);
  }
  if (apiLevel !== contract.api_level) {
    fail(`Android API is not ${contract.api_level}: ${String(apiLevel)}`);
  }
  const normalized = parseAndroidAvdConfig(configBytes);
  for (const key of [
    'api_level',
    'abi_type',
    'image_sysdir',
    'hw_device_name',
    'hw_lcd_width',
    'hw_lcd_height',
    'hw_lcd_density',
  ]) {
    if (normalized[key] !== contract[key]) {
      fail(`AVD config.ini ${key} does not match the target contract.`);
    }
  }
  if (
    physicalSize === null
    || typeof physicalSize !== 'object'
    || !Number.isSafeInteger(physicalSize.width)
    || !Number.isSafeInteger(physicalSize.height)
  ) {
    fail('Android physical screen size proof is invalid.');
  }
  const actualDimensions = [physicalSize.width, physicalSize.height].sort((a, b) => a - b);
  const expectedDimensions = [contract.hw_lcd_width, contract.hw_lcd_height]
    .sort((a, b) => a - b);
  if (JSON.stringify(actualDimensions) !== JSON.stringify(expectedDimensions)) {
    fail('Booted Android physical screen size does not match the AVD target contract.');
  }
  if (density !== contract.hw_lcd_density) {
    fail('Booted Android density does not match the AVD target contract.');
  }
  const normalizedBytes = Buffer.from(`${JSON.stringify(normalized)}\n`, 'utf8');
  return Object.freeze({
    schema: 1,
    target,
    avd_name: avdName,
    normalized,
    source_sha256: hashBytes(configBytes),
    normalized_sha256: hashBytes(normalizedBytes),
  });
}

function finiteRect(value, label) {
  if (
    !Array.isArray(value)
    || value.length !== 4
    || value.some((component) => typeof component !== 'number' || !Number.isFinite(component))
    || value[2] <= 0
    || value[3] <= 0
  ) {
    fail(`${label} is not a finite [x,y,width,height] Rect`);
  }
  return value;
}

/**
 * Godot state is expressed in stretched viewport coordinates while Android's
 * PNG is expressed in physical pixels. Store evidence must protect the latter:
 * a fixed logical inset can be too small or needlessly large across devices.
 */
export function assertPhysicalSafeLayout(
  safeLayout,
  png,
  { minimumPhysicalInset = 34 } = {},
) {
  if (safeLayout === null || typeof safeLayout !== 'object' || Array.isArray(safeLayout)) {
    fail('Physical-device safe-area layout proof is missing');
  }
  const viewport = finiteRect(safeLayout.viewport_rect, 'viewport_rect');
  const safe = finiteRect(safeLayout.safe_rect, 'safe_rect');
  if (
    png === null
    || typeof png !== 'object'
    || !Number.isSafeInteger(png.width)
    || !Number.isSafeInteger(png.height)
    || png.width <= 0
    || png.height <= 0
  ) {
    fail('PNG physical size is invalid');
  }
  if (!Number.isFinite(minimumPhysicalInset) || minimumPhysicalInset <= 0) {
    fail('Minimum physical safe-area inset is invalid');
  }

  const scaleX = png.width / viewport[2];
  const scaleY = png.height / viewport[3];
  const relativeScaleDelta = Math.abs(scaleX - scaleY) / Math.max(scaleX, scaleY);
  if (!Number.isFinite(scaleX) || !Number.isFinite(scaleY) || relativeScaleDelta > 0.02) {
    fail(`PNG and Godot viewport scale differ: ${scaleX}x${scaleY}`);
  }

  const insets = {
    left: (safe[0] - viewport[0]) * scaleX,
    top: (safe[1] - viewport[1]) * scaleY,
    right: (viewport[0] + viewport[2] - safe[0] - safe[2]) * scaleX,
    bottom: (viewport[1] + viewport[3] - safe[1] - safe[3]) * scaleY,
  };
  for (const [edge, inset] of Object.entries(insets)) {
    if (!Number.isFinite(inset) || inset + 0.05 < minimumPhysicalInset) {
      fail(`Android ${edge} physical gesture inset is below ${minimumPhysicalInset}px: ${inset}`);
    }
  }
  return {
    png_size: [png.width, png.height],
    viewport_scale: { x: scaleX, y: scaleY },
    minimum_physical_inset: minimumPhysicalInset,
    physical_insets: insets,
  };
}

/** Validate the metadata gate that must pass before an atomic canonical rename. */
export function assertCompleteTabletCaptureManifest({
  captures,
  locales,
  filenames,
  apkSha256,
  installedApkSha256,
}) {
  if (!Array.isArray(captures) || !Array.isArray(locales) || !Array.isArray(filenames)) {
    fail('Tablet capture manifest contract is invalid');
  }
  if (!SHA256_PATTERN.test(apkSha256) || installedApkSha256 !== apkSha256) {
    fail('Installed APK hash and capture APK hash differ');
  }
  const expected = new Set();
  for (const locale of locales) {
    if (typeof locale !== 'string' || locale.trim() === '') fail('Locale contract is invalid');
    for (const filename of filenames) {
      if (typeof filename !== 'string' || !filename.endsWith('.png')) {
        fail('Screenshot filename contract is invalid');
      }
      expected.add(`${locale}/${filename}`);
    }
  }
  if (captures.length !== expected.size) {
    fail(`Tablet capture has ${captures.length} image(s) (contract ${expected.size})`);
  }

  const actual = new Set();
  const hashes = new Set();
  const sizes = new Set();
  for (const capture of captures) {
    if (capture === null || typeof capture !== 'object' || Array.isArray(capture)) {
      fail('Capture manifest entry is invalid');
    }
    const key = `${capture.asset_locale}/${capture.filename}`;
    if (!expected.has(key) || actual.has(key)) fail(`Duplicate or unexpected capture: ${key}`);
    actual.add(key);
    if (!SHA256_PATTERN.test(capture.sha256) || hashes.has(capture.sha256)) {
      fail(`Capture PNG is duplicated or its hash is wrong: ${key}`);
    }
    hashes.add(capture.sha256);
    if (
      !Number.isSafeInteger(capture.width)
      || !Number.isSafeInteger(capture.height)
      || capture.width <= capture.height
    ) {
      fail(`Capture is not a valid landscape PNG: ${key}`);
    }
    sizes.add(`${capture.width}x${capture.height}`);
    if (capture.installed_apk_sha256 !== apkSha256) {
      fail(`Installed APK changed during capture: ${key}`);
    }
    if (
      capture.runtime_before === null
      || typeof capture.runtime_before !== 'object'
      || capture.runtime_after === null
      || typeof capture.runtime_after !== 'object'
      || typeof capture.clean_ui_proof !== 'string'
      || capture.clean_ui_proof === ''
      || capture.physical_safe_layout === null
      || typeof capture.physical_safe_layout !== 'object'
    ) {
      fail(`Before/after, clean UI, or safe-area proof is missing: ${key}`);
    }
  }
  if (actual.size !== expected.size || sizes.size !== 1) {
    fail('Capture set is incomplete or the resolution changed');
  }
  return { capture_count: actual.size, screenshot_size: [...sizes][0] };
}
