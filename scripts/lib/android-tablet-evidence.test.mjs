import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {
  ANDROID_CAPTURE_DEVICE_CONTRACTS,
  assertAndroidAvdCaptureContract,
  assertCompleteTabletCaptureManifest,
  assertPhysicalSafeLayout,
  parseAndroidAvdConfig,
  shouldRetryTabletGuardianColdStall,
} from './android-tablet-evidence.mjs';

const LOCALES = ['en-US', 'ko-KR', 'ja-JP', 'zh-Hans', 'zh-Hant'];
const FILES = [
  '01-moonlight-barrage.png',
  '02-field-guardian.png',
  '03-missile-core-drop.png',
  '04-title.png',
  '05-moonlit-shrine.png',
  '06-hero-preview.png',
];
const APK_HASH = 'a'.repeat(64);

function avdConfig(target) {
  const contract = ANDROID_CAPTURE_DEVICE_CONTRACTS[target];
  return Buffer.from([
    `abi.type = ${contract.abi_type}`,
    `hw.device.name = ${contract.hw_device_name}`,
    `hw.lcd.density = ${contract.hw_lcd_density}`,
    `hw.lcd.height = ${contract.hw_lcd_height}`,
    `hw.lcd.width = ${contract.hw_lcd_width}`,
    `image.sysdir.1 = ${contract.image_sysdir}`,
    'disk.dataPartition.size = 6G',
    '',
  ].join('\n'));
}

test('tablet capture CLI refuses an APK without a build attestation', () => {
  const result = spawnSync(process.execPath, [
    'scripts/capture-android-tablet-evidence.mjs',
    '--serial', 'emulator-5558',
    '--avd', 'Moonlit_7_API36',
    '--target', 'seven-inch-tablet',
    '--apk', 'package.json',
  ], { encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /--fresh-build .* --attestation PATH/u);
});

test('tablet capture CLI accepts exactly one build provenance mode', () => {
  const result = spawnSync(process.execPath, [
    'scripts/capture-android-tablet-evidence.mjs',
    '--serial', 'emulator-5558',
    '--avd', 'Moonlit_7_API36',
    '--target', 'seven-inch-tablet',
    '--apk', 'builds/android/MoonlitBeacon.apk',
    '--fresh-build',
    '--attestation', 'package.json',
  ], { encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /--fresh-build .* --attestation PATH/u);
});

function captures() {
  let index = 1;
  return LOCALES.flatMap((assetLocale) => FILES.map((filename) => ({
    asset_locale: assetLocale,
    filename,
    width: 1024,
    height: 600,
    sha256: (index++).toString(16).padStart(64, '0'),
    installed_apk_sha256: APK_HASH,
    runtime_before: { observation: 1 },
    runtime_after: { observation: 2 },
    clean_ui_proof: 'hidden',
    physical_safe_layout: { physical_insets: { left: 34 } },
  })));
}

test('physical safe area is measured in PNG pixels', () => {
  const proof = assertPhysicalSafeLayout({
    viewport_rect: [0, 0, 808, 360],
    safe_rect: [12, 12, 784, 336],
  }, { width: 2424, height: 1080 });
  assert.equal(proof.viewport_scale.x, 3);
  assert.equal(proof.physical_insets.left, 36);
  assert.equal(proof.physical_insets.bottom, 36);
});

test('physical safe area rejects a logical inset that scales below 34px', () => {
  assert.throws(() => assertPhysicalSafeLayout({
    viewport_rect: [0, 0, 808, 360],
    safe_rect: [11, 11, 786, 338],
  }, { width: 2424, height: 1080 }), /34px/u);
});

test('physical safe area rejects a full-viewport safe rect', () => {
  assert.throws(() => assertPhysicalSafeLayout({
    viewport_rect: [0, 0, 808, 360],
    safe_rect: [0, 0, 808, 360],
  }, { width: 2424, height: 1080 }), /34px/u);
});

test('physical safe area rejects anisotropic PNG-to-viewport scaling', () => {
  assert.throws(() => assertPhysicalSafeLayout({
    viewport_rect: [0, 0, 808, 360],
    safe_rect: [12, 12, 784, 336],
  }, { width: 2424, height: 1000 }), /scale differ/u);
});

test('proves the live config subset and display contract for the phone and both tablet AVDs', () => {
  for (const target of Object.keys(ANDROID_CAPTURE_DEVICE_CONTRACTS)) {
    const contract = ANDROID_CAPTURE_DEVICE_CONTRACTS[target];
    const proof = assertAndroidAvdCaptureContract({
      target,
      avdName: contract.avd_name,
      apiLevel: contract.api_level,
      configBytes: avdConfig(target),
      physicalSize: {
        width: Math.max(contract.hw_lcd_width, contract.hw_lcd_height),
        height: Math.min(contract.hw_lcd_width, contract.hw_lcd_height),
      },
      density: contract.hw_lcd_density,
    });
    assert.equal(proof.schema, 1);
    assert.equal(proof.normalized.hw_device_name, contract.hw_device_name);
    assert.match(proof.source_sha256, /^[0-9a-f]{64}$/u);
    assert.match(proof.normalized_sha256, /^[0-9a-f]{64}$/u);
    assert.deepEqual(parseAndroidAvdConfig(avdConfig(target)), proof.normalized);
  }
});

test('AVD gate rejects every size, density, API, ABI, image, and device counterexample', () => {
  const target = 'pixel-phone';
  const contract = ANDROID_CAPTURE_DEVICE_CONTRACTS[target];
  const base = {
    target,
    avdName: contract.avd_name,
    apiLevel: contract.api_level,
    configBytes: avdConfig(target),
    physicalSize: { width: 2424, height: 1080 },
    density: contract.hw_lcd_density,
  };
  const cases = [
    { ...base, physicalSize: { width: 2400, height: 1080 } },
    { ...base, density: 440 },
    { ...base, apiLevel: 35 },
    { ...base, configBytes: Buffer.from(avdConfig(target).toString().replace('arm64-v8a', 'x86_64')) },
    { ...base, configBytes: Buffer.from(avdConfig(target).toString().replace('google_apis_playstore', 'google_apis')) },
    { ...base, configBytes: Buffer.from(avdConfig(target).toString().replace('pixel_9', 'pixel_8')) },
  ];
  for (const counterexample of cases) {
    assert.throws(
      () => assertAndroidAvdCaptureContract(counterexample),
      /contract|API|density/u,
    );
  }
});

test('AVD config parser rejects missing required keys and duplicates', () => {
  const source = avdConfig('seven-inch-tablet').toString();
  assert.throws(
    () => parseAndroidAvdConfig(Buffer.from(source.replace(/^abi\.type.*\n/mu, ''))),
    /required key/u,
  );
  assert.throws(
    () => parseAndroidAvdConfig(Buffer.from(`${source}hw.lcd.width = 1024\n`)),
    /duplicated/u,
  );
});

test('Pixel phone capture stores the independently computed physical safe proof', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const captureStart = source.indexOf('async function capture(');
  const captureEnd = source.indexOf(
    'async function captureWithCleanUi(',
    captureStart,
  );
  const captureSource = source.slice(captureStart, captureEnd);
  assert.match(captureSource, /assertCapturePhysicalSafeLayout\(\{/u);
  assert.match(captureSource, /physical_safe_layout: physicalSafeLayout/u);
  assert.match(
    source,
    /captureGuard: readyState,[\s\S]*?stateExpected: \{ kind: 'arena_ready' \}/u,
  );
  assert.match(source, /assertPhysicalSafeCaptures\(captures\);/u);
});

test('Pixel phone stages every PNG, proof, and report then directory-exchanges', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const publishStart = source.indexOf('function publishFullCaptureGeneration(');
  const publishEnd = source.indexOf('\nfunction runtimeFingerprint(', publishStart);
  assert.ok(publishStart >= 0 && publishEnd > publishStart);
  const publisher = source.slice(publishStart, publishEnd);
  const stageFiles = publisher.indexOf('for (const pendingFile of pendingFiles)');
  const stageReport = publisher.indexOf("'capture-report.json'");
  const directoryPublish = publisher.indexOf('publishCaptureDirectoryAtomically({');
  assert.ok(stageFiles >= 0);
  assert.ok(stageReport > stageFiles);
  assert.ok(directoryPublish > stageReport);
  assert.match(publisher, /evidence\.captures\.length !== LOCALES\.length \* 6/u);
  assert.match(publisher, /capture-build-attestation\.json/u);
  assert.match(publisher, /avd-config\.ini/u);
  assert.match(source, /module\._atomic_exchange_directories/u);
  const main = source.slice(source.indexOf('async function main()'));
  assert.doesNotMatch(main, /writeCaptureFileAtomic\(absolute, bytes\)/u);
});

test('tablet missile-core stability starts after the staged event is ready', () => {
  const source = readFileSync(
    new URL('../capture-android-tablet-evidence.mjs', import.meta.url),
    'utf8',
  );
  const captureStart = source.indexOf('async function captureMissileCore(');
  const captureEnd = source.indexOf('\nasync function captureLocale(', captureStart);
  assert.ok(captureStart >= 0 && captureEnd > captureStart);
  const captureSource = source.slice(captureStart, captureEnd);
  assert.match(
    source,
    /async function waitRuntimeState[\s\S]*const timeout = 90_000/u,
    'must wait in every state for a cold Godot main loop that can lag the foreground',
  );
  const stateReady = captureSource.indexOf('if (state === null)');
  const cleanUiReady = captureSource.indexOf("await waitCleanUi('combat')");
  const runtimeBefore = captureSource.indexOf(
    'const runtimeBefore = await waitRuntimeState(runtimeNonce, runtimeExpected)',
  );
  const screencap = captureSource.indexOf("adb(['exec-out', 'screencap', '-p']");
  assert.ok(stateReady >= 0);
  assert.ok(cleanUiReady > stateReady);
  assert.ok(runtimeBefore > cleanUiReady);
  assert.ok(screencap > runtimeBefore);
  assert.match(
    captureSource,
    /const deadline = Date\.now\(\) \+ 90_000/u,
    'must budget enough start time for the cold main loop and a real hit plus core attach',
  );
  assert.match(
    captureSource,
    /runtime_nonce: runtimeNonce/u,
    'missile-core report must bind its runtime observations to the armed nonce',
  );
  assert.match(
    captureSource,
    /const missileBefore = \{ \.\.\.state, asset_locale: locale\.asset \};/u,
    'missile-core before proof must bind the store asset locale',
  );
  assert.match(
    captureSource,
    /const missileAfter = \{ \.\.\.after, asset_locale: locale\.asset \};/u,
    'missile-core after proof must bind the store asset locale',
  );
  assert.match(captureSource, /before: missileBefore/u);
  assert.match(captureSource, /after: missileAfter/u);
  assert.match(captureSource, /missile_before: missileBefore/u);
  assert.match(captureSource, /missile_after: missileAfter/u);
});

test('tablet guardian cold-stall retry predicate is fail-closed', () => {
  const absent = {
    afterObservation: 0,
    attempt: 1,
    lastObservation: null,
    sawRejectedState: false,
    sawStateFile: false,
  };
  assert.equal(shouldRetryTabletGuardianColdStall(absent), true);
  assert.equal(shouldRetryTabletGuardianColdStall({
    ...absent,
    lastObservation: 4,
    sawStateFile: true,
  }), true);
  assert.equal(shouldRetryTabletGuardianColdStall({
    ...absent,
    lastObservation: 5,
    sawStateFile: true,
  }), true);
  for (const rejected of [
    { ...absent, attempt: 2 },
    { ...absent, afterObservation: 1 },
    { ...absent, lastObservation: 6, sawStateFile: true },
    { ...absent, lastObservation: -1, sawStateFile: true },
    { ...absent, lastObservation: 1.5, sawStateFile: true },
    { ...absent, sawRejectedState: true },
    { ...absent, sawRejectedState: true, sawStateFile: true },
    { ...absent, sawStateFile: true },
  ]) assert.equal(shouldRetryTabletGuardianColdStall(rejected), false);
});

test('tablet guardian retry kills the old process before each fresh nonce', () => {
  const source = readFileSync(
    new URL('../capture-android-tablet-evidence.mjs', import.meta.url),
    'utf8',
  );
  const retryStart = source.indexOf('async function captureFieldGuardian(');
  const retryEnd = source.indexOf('\nasync function captureLocale(', retryStart);
  const retry = source.slice(retryStart, retryEnd);
  assert.ok(retryStart >= 0 && retryEnd > retryStart);
  assert.match(retry, /attempt <= 2/u);
  assert.match(retry, /error instanceof RuntimeStateTimeoutError/u);
  assert.match(retry, /shouldRetryTabletGuardianColdStall/u);
  const loop = retry.indexOf('for (let attempt');
  const stop = retry.indexOf("'force-stop'", loop);
  const clear = retry.indexOf('clearCaptureHandshakes();', stop);
  const nonce = retry.indexOf("armRuntime('field_guardian')", clear);
  const launch = retry.indexOf('await launch();', nonce);
  assert.ok(loop >= 0 && stop > loop && clear > stop && nonce > clear && launch > nonce,
    'every attempt must stop the existing process, then clean, mint a new nonce, and launch');
  assert.equal(
    retry.includes('captureRuntime(') && retry.includes('fresh retry 1/1'),
    true,
  );
});

test('tablet window dump report hashes the exact persisted bytes', () => {
  const source = readFileSync(
    new URL('../capture-android-tablet-evidence.mjs', import.meta.url),
    'utf8',
  );
  assert.match(
    source,
    /const windowDumpBytes = Buffer\.from\(`\$\{windowDump\}\\n`, 'utf8'\);/u,
  );
  assert.match(
    source,
    /writeFileSync\(windowDumpPath, windowDumpBytes, \{ flag: 'wx' \}\);/u,
  );
  assert.match(source, /window_dump_sha256: sha256\(windowDumpBytes\)/u);
  assert.doesNotMatch(source, /window_dump_sha256: sha256\(windowDump\)/u);
});

test('complete tablet manifest requires five locales by six unique PNGs', () => {
  assert.deepEqual(assertCompleteTabletCaptureManifest({
    captures: captures(),
    locales: LOCALES,
    filenames: FILES,
    apkSha256: APK_HASH,
    installedApkSha256: APK_HASH,
  }), { capture_count: 30, screenshot_size: '1024x600' });
});

test('complete tablet manifest rejects a missing or reused PNG', () => {
  const missing = captures().slice(1);
  assert.throws(() => assertCompleteTabletCaptureManifest({
    captures: missing,
    locales: LOCALES,
    filenames: FILES,
    apkSha256: APK_HASH,
    installedApkSha256: APK_HASH,
  }), /29 image/u);

  const reused = captures();
  reused[1].sha256 = reused[0].sha256;
  assert.throws(() => assertCompleteTabletCaptureManifest({
    captures: reused,
    locales: LOCALES,
    filenames: FILES,
    apkSha256: APK_HASH,
    installedApkSha256: APK_HASH,
  }), /duplicated or its hash is wrong/u);
});
