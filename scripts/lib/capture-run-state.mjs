import { lstatSync } from 'node:fs';
import {
  dirname,
  isAbsolute,
  relative,
  resolve,
  sep,
} from 'node:path';

export function launcherWaitOutputShowsExpectedActivity(output, packageName) {
  if (typeof output !== 'string' || typeof packageName !== 'string'
    || packageName.trim() === '') {
    throw new TypeError('Launcher output and the exact package name are required.');
  }
  const lines = output.split(/\r?\n/u).map((line) => line.trim());
  const statusOk = lines.some((line) => line === 'Status: ok');
  const expectedActivity = lines.some((line) =>
    line.startsWith(`Activity: ${packageName}/`));
  return statusOk && expectedActivity;
}

export function captureProcessExitCode({
  captureSucceeded,
  restorationFailures,
} = {}) {
  if (
    typeof captureSucceeded !== 'boolean'
    || !Number.isSafeInteger(restorationFailures)
    || restorationFailures < 0
  ) {
    throw new TypeError('Capture success and settings-restore failure count are required.');
  }
  return captureSucceeded && restorationFailures === 0 ? 0 : 1;
}

export function commitCaptureArtifacts({
  captureSucceeded,
  restorationFailures,
  pendingFiles,
  evidence,
  commitFile,
  commitEvidence,
} = {}) {
  if (captureProcessExitCode({
    captureSucceeded,
    restorationFailures,
  }) !== 0) {
    return false;
  }
  if (
    !Array.isArray(pendingFiles)
    || pendingFiles.length === 0
    || evidence === null
    || typeof evidence !== 'object'
    || Array.isArray(evidence)
    || typeof commitFile !== 'function'
    || typeof commitEvidence !== 'function'
  ) {
    throw new TypeError('Capture files and proofs to publish after restore are required.');
  }
  for (const pendingFile of pendingFiles) {
    commitFile(pendingFile);
  }
  // Publish proofs last. If a file commit fails halfway, previous evidence must not
  // flip into a state that approves the new image set.
  commitEvidence(evidence);
  return true;
}

/**
 * Publish one fully staged capture generation. When a canonical generation
 * already exists, exchangeDirectories must provide a single-syscall atomic
 * exchange (the phone pipeline delegates to build_store_graphics.py's proven
 * Darwin/Linux helper). The exact staged-generation probe resolves a helper
 * process that dies after the syscall but before reporting success.
 */
export function publishCaptureDirectoryAtomically({
  stagingRoot,
  canonicalRoot,
  canonicalExists,
  exchangeDirectories,
  isStagedGenerationAt,
  renameDirectory,
  removeOldGeneration,
} = {}) {
  if (
    typeof stagingRoot !== 'string'
    || stagingRoot === ''
    || typeof canonicalRoot !== 'string'
    || canonicalRoot === ''
    || typeof canonicalExists !== 'boolean'
    || typeof exchangeDirectories !== 'function'
    || typeof isStagedGenerationAt !== 'function'
    || typeof renameDirectory !== 'function'
    || typeof removeOldGeneration !== 'function'
  ) {
    throw new TypeError('staging/canonical directory publish contract is incomplete.');
  }
  if (stagingRoot === canonicalRoot) {
    throw new Error('staging and canonical capture directories are the same.');
  }
  if (canonicalExists) {
    try {
      exchangeDirectories(stagingRoot, canonicalRoot);
    } catch (error) {
      // The exchange itself is atomic, but it runs in a short-lived helper
      // process. That process can be interrupted after the syscall succeeds
      // and before its exit status reaches Node. Resolve that ambiguity from
      // the staged generation's exact report bytes instead of deleting the
      // directory currently named stagingRoot (which may now be the old,
      // previously valid canonical generation).
      let canonicalHasStagedGeneration;
      let stagingHasStagedGeneration;
      try {
        canonicalHasStagedGeneration = isStagedGenerationAt(canonicalRoot);
        stagingHasStagedGeneration = isStagedGenerationAt(stagingRoot);
      } catch (probeError) {
        throw new AggregateError(
          [error, probeError],
          'Could not safely tell the atomic exchange result',
        );
      }
      if (canonicalHasStagedGeneration && !stagingHasStagedGeneration) {
        try {
          removeOldGeneration(stagingRoot);
        } catch {
          // Publication is complete; retaining the old generation is safe.
        }
        return 'exchange-recovered';
      }
      if (!canonicalHasStagedGeneration && stagingHasStagedGeneration) {
        throw error;
      }
      throw new AggregateError(
        [error],
        'generation location after atomic exchange is ambiguous; keeping both directories',
      );
    }
    // stagingRoot now names the old canonical generation. Cleanup is not part
    // of publication correctness and must not turn a completed exchange into
    // a reported publish failure.
    try {
      removeOldGeneration(stagingRoot);
    } catch {
      // Best effort only; the old generation is still recoverable at staging.
    }
    return 'exchange';
  }
  renameDirectory(stagingRoot, canonicalRoot);
  return 'rename';
}

function pathIsWithin(root, candidate) {
  const remainder = relative(root, candidate);
  return remainder === ''
    || (!remainder.startsWith(`..${sep}`)
      && remainder !== '..'
      && !isAbsolute(remainder));
}

export function assertSafeCaptureOutputPath(
  targetPath,
  { repositoryRoot, captureRoot } = {},
) {
  if (
    typeof targetPath !== 'string'
    || typeof repositoryRoot !== 'string'
    || typeof captureRoot !== 'string'
  ) {
    throw new TypeError('Capture output and repository/capture root paths are required.');
  }
  const repository = resolve(repositoryRoot);
  const allowed = resolve(captureRoot);
  const target = resolve(targetPath);
  if (
    !pathIsWithin(repository, allowed)
    || !pathIsWithin(allowed, target)
  ) {
    throw new Error(`Capture output is outside the repository dedicated path: ${target}`);
  }

  let current = target;
  while (current !== repository) {
    try {
      if (lstatSync(current).isSymbolicLink()) {
        throw new Error(`Capture output path contains a symbolic link: ${current}`);
      }
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error;
    }
    const parent = dirname(current);
    if (parent === current) {
      throw new Error(`Could not verify the capture output boundary: ${target}`);
    }
    current = parent;
  }
  return target;
}

const SHA256_PATTERN = /^[0-9a-f]{64}$/u;

function assertSha256(value, label) {
  if (typeof value !== 'string' || !SHA256_PATTERN.test(value)) {
    throw new TypeError(`${label} SHA-256 is invalid.`);
  }
}

function normalizedInputFingerprints(value, label) {
  if (
    value === null
    || typeof value !== 'object'
    || Array.isArray(value)
  ) {
    throw new TypeError(`${label} input fingerprint is invalid.`);
  }
  const entries = Object.entries(value).sort(([left], [right]) =>
    left.localeCompare(right, 'en'));
  if (entries.length === 0) {
    throw new TypeError(`${label} input fingerprint is empty.`);
  }
  for (const [path, hash] of entries) {
    if (
      path === ''
      || path.startsWith('/')
      || path.includes('\\')
      || path.split('/').some(
        (component) => component === '' || component === '.' || component === '..',
      )
    ) {
      throw new TypeError(`${label} input path is invalid.`);
    }
    assertSha256(hash, `${label} ${path}`);
  }
  return Object.fromEntries(entries);
}

export function assertCaptureBuildAttestationCurrent(
  attestation,
  {
    apkSha256,
    runtimeSha256,
    inputSha256,
  } = {},
) {
  if (
    attestation === null
    || typeof attestation !== 'object'
    || Array.isArray(attestation)
    || attestation.schema !== 1
  ) {
    throw new TypeError('Capture APK build attestation schema is invalid.');
  }
  assertSha256(attestation.apk_sha256, 'capture APK build attestation');
  assertSha256(attestation.runtime_sha256, 'capture runtime build attestation');
  assertSha256(apkSha256, 'current capture APK');
  assertSha256(runtimeSha256, 'current capture runtime');
  const attestedInputs = normalizedInputFingerprints(
    attestation.input_sha256,
    'capture APK build attestation',
  );
  const currentInputs = normalizedInputFingerprints(
    inputSha256,
    'current capture',
  );
  if (attestation.apk_sha256 !== apkSha256) {
    throw new Error('Capture APK differs from the build-attestation APK.');
  }
  if (attestation.runtime_sha256 !== runtimeSha256) {
    throw new Error('Current game runtime differs from the source that built the capture APK.');
  }
  if (JSON.stringify(attestedInputs) !== JSON.stringify(currentInputs)) {
    throw new Error('Current capture inputs differ from the inputs that built the capture APK.');
  }
  return true;
}

export function assertInstalledCaptureApkCurrent(
  expectedSha256,
  installedSha256,
) {
  assertSha256(expectedSha256, 'capture evidence APK');
  assertSha256(installedSha256, 'installed capture APK');
  if (installedSha256 !== expectedSha256) {
    throw new Error(
      'Installed base.apk differs from the capture evidence APK.',
    );
  }
  return installedSha256;
}

const FOREGROUND_SIGNAL_GROUPS = Object.freeze([
  Object.freeze(['mCurrentFocus']),
  Object.freeze(['topResumedActivity', 'mResumedActivity']),
  Object.freeze(['mFocusedApp']),
]);

function androidPackagePattern(packageName) {
  const escaped = packageName.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  return new RegExp(`(?:^|[\\s{])${escaped}(?=[/\\s}]|$)`, 'u');
}

export function foregroundSignalsShowPackage(output, packageName) {
  if (
    typeof output !== 'string'
    || typeof packageName !== 'string'
    || packageName.trim() === ''
  ) {
    throw new TypeError('Android foreground output and package name are required.');
  }

  const lines = output.split(/\r?\n/u);
  for (const signalNames of FOREGROUND_SIGNAL_GROUPS) {
    const candidates = lines.filter((line) => signalNames.some(
      (signal) => line.includes(`${signal}=`),
    )).filter((line) => {
      const value = line.slice(line.indexOf('=') + 1).trim();
      return value !== '' && !/^(?:null|none)$/iu.test(value);
    });
    const current = candidates.at(-1);
    if (current) {
      return androidPackagePattern(packageName).test(current);
    }
  }
  return false;
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

const STORE_CAPTURE_NONCE_PATTERN = /^[0-9a-f]{64}$/u;
const STORE_CAPTURE_KINDS = new Set([
  'arena_ready',
  'title',
  'moonlight_barrage',
  'shrine',
  'hero_preview',
  'field_guardian',
  'iap_review',
]);
const TITLE_COPY_BY_GAME_LOCALE = Object.freeze({
  ko: Object.freeze({
    title: '달빛 봉화', subtitle: '밤을 밝히는 마지막 불빛', tap: '화면을 탭하여 시작',
    settings: '설정', shrine: '제단', ladder: '순위', store: '상점',
  }),
  en: Object.freeze({
    title: 'MOONLIT BEACON', subtitle: 'OUTLAST THE NIGHT', tap: 'Tap to start',
    settings: 'Settings', shrine: 'Shrine', ladder: 'Ranks', store: 'Store',
  }),
  ja: Object.freeze({
    title: '月明かりの烽火', subtitle: '夜を照らす最後の灯', tap: '画面をタップして開始',
    settings: '設定', shrine: '祭壇', ladder: '順位', store: 'ストア',
  }),
  zh_CN: Object.freeze({
    title: '月光烽火', subtitle: '照亮长夜的最后火光', tap: '点击屏幕开始',
    settings: '设置', shrine: '祭坛', ladder: '排名', store: '商店',
  }),
  zh_TW: Object.freeze({
    title: '月光烽火', subtitle: '照亮長夜的最後火光', tap: '點擊畫面開始',
    settings: '設定', shrine: '祭壇', ladder: '排名', store: '商店',
  }),
});
const TITLE_NIGHT_FOREST_SCENE_PATH = 'res://scenes/gameplay/night_forest.tscn';
const TITLE_NIGHT_FOREST_GROUND_PATH =
  'res://assets/custom/world/terrain/forest_floor.png';
const TITLE_VIGNETTE_NODE_CLASS = 'Sprite2D';
const TITLE_VIGNETTE_TEXTURE_CLASS = 'GradientTexture2D';
const TITLE_VIGNETTE_TEXTURE_UNIQUE_ID = 'GradientTexture2D_vignette';
const TITLE_BEACON_SCENE_PATH = 'res://scenes/objectives/beacon.tscn';
const TITLE_BEACON_CLEARING_PATH =
  'res://assets/custom/world/beacon/clearing.png';
const IAP_HERO_VISUAL_BY_PRODUCT = Object.freeze({
  'com.crossplatformkorea.moonlitbeacon.hero_dancer': Object.freeze({
    hero: 'res://resources/heroes/dancer.tres',
    portrait: 'res://assets/custom/actors/heroes/dancer/portrait.png',
  }),
  'com.crossplatformkorea.moonlitbeacon.hero_keeper': Object.freeze({
    hero: 'res://resources/heroes/keeper.tres',
    portrait: 'res://assets/custom/actors/heroes/keeper/portrait.png',
  }),
  'com.crossplatformkorea.moonlitbeacon.hero_knight': Object.freeze({
    hero: 'res://resources/heroes/knight.tres',
    portrait: 'res://assets/custom/actors/heroes/knight/portrait.png',
  }),
  'com.crossplatformkorea.moonlitbeacon.hero_eclipse': Object.freeze({
    hero: 'res://resources/heroes/eclipse.tres',
    portrait: 'res://assets/custom/actors/heroes/eclipse/portrait.png',
  }),
  'com.crossplatformkorea.moonlitbeacon.hero_sage': Object.freeze({
    hero: 'res://resources/heroes/sage.tres',
    portrait: 'res://assets/custom/actors/heroes/sage/portrait.png',
  }),
});
const IAP_REVIEW_OUTPUT_BY_PRODUCT = Object.freeze({
  'com.crossplatformkorea.moonlitbeacon.hero_dancer': 'hero-dancer.png',
  'com.crossplatformkorea.moonlitbeacon.hero_keeper': 'hero-keeper.png',
  'com.crossplatformkorea.moonlitbeacon.hero_knight': 'hero-knight.png',
  'com.crossplatformkorea.moonlitbeacon.hero_eclipse': 'hero-eclipse.png',
  'com.crossplatformkorea.moonlitbeacon.hero_sage': 'hero-sage.png',
  'com.crossplatformkorea.moonlitbeacon.supporter': 'supporter.png',
  'com.crossplatformkorea.moonlitbeacon.lantern_colors': 'lantern-colors.png',
  'com.crossplatformkorea.moonlitbeacon.continue_coin': 'continue-coin.png',
  'com.crossplatformkorea.moonlitbeacon.continue_coin_5': 'continue-coin-5.png',
  'com.crossplatformkorea.moonlitbeacon.continue_coin_10': 'continue-coin-10.png',
});
const IAP_REVIEW_TITLE_BY_PRODUCT = Object.freeze({
  'com.crossplatformkorea.moonlitbeacon.supporter': '달빛 후원자',
  'com.crossplatformkorea.moonlitbeacon.hero_dancer': '그림자 무희',
  'com.crossplatformkorea.moonlitbeacon.hero_keeper': '봉화지기',
  'com.crossplatformkorea.moonlitbeacon.hero_knight': '백월 기사',
  'com.crossplatformkorea.moonlitbeacon.hero_eclipse': '월식 마도사',
  'com.crossplatformkorea.moonlitbeacon.hero_sage': '성좌 현자',
  'com.crossplatformkorea.moonlitbeacon.lantern_colors': '봉화 색상 꾸러미',
  'com.crossplatformkorea.moonlitbeacon.continue_coin': '이어하기 코인',
  'com.crossplatformkorea.moonlitbeacon.continue_coin_5': '이어하기 코인 5개',
  'com.crossplatformkorea.moonlitbeacon.continue_coin_10': '이어하기 코인 10개',
});
const IAP_REVIEW_FALLBACK_PRICE_TEXT = '기기 스토어 전용';
const IAP_REVIEW_FALLBACK_STATUS_TEXT =
  '실제 가격과 구매는 App Store·Google Play에서 확인할 수 있습니다';
const IAP_REVIEW_BUY_TEXT = '구매';
const IAP_REVIEW_RESTORE_TEXT = '구매 복원';
// Detail screen hangs both images at integer multiples of their source size. The large slot (96x96)
// gets the 96x96 portrait 1:1; the header icon slot (48x48) gets a 24x24 idle-sheet crop at 2x.
// It used to be the other way around, so the large image was 4x and the small one 0.5x.
const HERO_PREVIEW_VISUAL_BY_HERO_PATH = Object.freeze({
  'res://resources/heroes/keeper.tres': Object.freeze({
    portrait: 'res://assets/custom/actors/heroes/keeper/idle.png',
    body: 'res://assets/custom/actors/heroes/keeper/portrait.png',
  }),
});
const HERO_PREVIEW_NAME_SOURCE_KEY = 'HERO_KEEPER_NAME';
const HERO_PREVIEW_DESCRIPTION_SOURCE_KEY = 'HERO_KEEPER_DESC';
const HERO_PREVIEW_STATE_SOURCE_KEYS = new Set([
  'SHRINE_SELECTED',
  'SHRINE_OWNED',
  'HERO_PREVIEW_IAP_LOCKED',
]);
const HERO_PREVIEW_COPY_BY_GAME_LOCALE = Object.freeze({
  ko: Object.freeze({
    name: '봉화지기',
    description: '하트 6칸 · 이속 -15% · 피해 +25% · 대시 쿨 +30% · 달빛 파문·질긴 목숨',
    states: Object.freeze({
      SHRINE_SELECTED: '선택 중',
      SHRINE_OWNED: '해금됨',
      HERO_PREVIEW_IAP_LOCKED: '잠김 · 기기 스토어에서 구매',
    }),
  }),
  en: Object.freeze({
    name: 'Beacon Keeper',
    description: '6 hearts · move -15% · dmg +25% · dash CD +30% · Moonlit Ripple/Tenacious Life',
    states: Object.freeze({
      SHRINE_SELECTED: 'Selected',
      SHRINE_OWNED: 'Unlocked',
      HERO_PREVIEW_IAP_LOCKED: 'Locked · purchase in device store',
    }),
  }),
  ja: Object.freeze({
    name: '烽火の守り人',
    description: 'ハート6 · 移速 -15% · ダメージ +25% · ダッシュCD +30% · 月光の波紋・不屈の命',
    states: Object.freeze({
      SHRINE_SELECTED: '選択中',
      SHRINE_OWNED: '解放済み',
      HERO_PREVIEW_IAP_LOCKED: '未購入 · 端末ストアで購入',
    }),
  }),
  zh_CN: Object.freeze({
    name: '烽火守护者',
    description: '6颗心 · 移速 -15% · 伤害 +25% · 冲刺冷却 +30% · 月光波纹·坚韧生命',
    states: Object.freeze({
      SHRINE_SELECTED: '已选择',
      SHRINE_OWNED: '已解锁',
      HERO_PREVIEW_IAP_LOCKED: '未购买 · 在设备商店购买',
    }),
  }),
  zh_TW: Object.freeze({
    name: '烽火守護者',
    description: '6顆心 · 移速 -15% · 傷害 +25% · 衝刺冷卻 +30% · 月光波紋·堅韌生命',
    states: Object.freeze({
      SHRINE_SELECTED: '已選擇',
      SHRINE_OWNED: '已解鎖',
      HERO_PREVIEW_IAP_LOCKED: '未購買 · 在裝置商店購買',
    }),
  }),
});
// This gate blocks a **Guardian from another world** appearing in the field cut.
// As cycle rises the same field Guardian evolves into the storm form, and because capture is set
// to cycle 3 the storm form is what actually appears. World and banner copy are the same, so as
// advertising it is the same subject — the flashier one, even.
const FIELD_GUARDIAN_CAPTURE_TEXTURES = new Set([
  'res://assets/custom/actors/guardians/field.png',
  'res://assets/custom/actors/guardians/field_windup_cross.png',
  'res://assets/custom/actors/guardians/field_windup_radial.png',
  'res://assets/custom/actors/guardians/field_recover.png',
  'res://assets/custom/actors/guardians/field_storm.png',
  'res://assets/custom/actors/guardians/field_storm_windup_cross.png',
  'res://assets/custom/actors/guardians/field_storm_windup_radial.png',
  'res://assets/custom/actors/guardians/field_storm_recover.png',
]);
const FIELD_GUARDIAN_CAPTURE_KINDS = new Set([
  'res://resources/guardian_field.tres',
  'res://resources/guardian_field_storm.tres',
]);
const NIGHT_TONE = Object.freeze([1, 1, 1, 1]);
const DAY_TONE = Object.freeze([1.55, 1.38, 1.12, 1]);
const COLOR_COMPONENT_TOLERANCE = 1e-6;

function assertStoreCaptureExpected(expected) {
  if (
    !isRecord(expected)
    || !STORE_CAPTURE_KINDS.has(expected.kind)
    || typeof expected.gameLocale !== 'string'
    || expected.gameLocale.trim() === ''
  ) {
    throw new TypeError('Store capture kind and expected game locale are required.');
  }
  if (
    expected.kind === 'hero_preview'
    && (typeof expected.heroPath !== 'string' || expected.heroPath.trim() === '')
  ) {
    throw new TypeError('Hero-preview capture expected hero path is required.');
  }
  if (
    expected.kind === 'iap_review'
    && (typeof expected.productId !== 'string' || expected.productId.trim() === '')
  ) {
    throw new TypeError('IAP review capture expected product ID is required.');
  }

  if (
    expected.kind === 'title'
    && typeof expected.directDistribution !== 'boolean'
  ) {
    throw new TypeError('Title capture expected distribution feature is required.');
  }
}

function requireStoreCaptureValue(state, field, expected, message) {
  if (state[field] !== expected) throw new Error(message);
  return expected;
}

// Pin an allowlist, not a single value. Use it when **several forms of the same subject** can
// legitimately appear, like an evolving Guardian. Keep the list narrow so anything does not pass.
function requireStoreCaptureMember(state, field, allowed, message) {
  const actual = state[field];
  if (!allowed.has(actual)) throw new Error(message);
  return actual;
}

function requirePinnedCaptureBanner(state, key, label) {
  if (state.banner_key !== key) {
    throw new Error(`${label} banner key is invalid.`);
  }
  if (
    typeof state.expected_banner_text !== 'string'
    || state.expected_banner_text.trim() === ''
    || typeof state.actual_banner_text !== 'string'
    || state.actual_banner_text !== state.expected_banner_text
  ) {
    throw new Error(`${label} live banner copy differs from the translation expected value.`);
  }
  if (state.banner_visible !== true || state.banner_locked !== true) {
    throw new Error(`${label} banner is not in a visible frozen state.`);
  }
  return {
    banner_key: key,
    expected_banner_text: state.expected_banner_text,
    actual_banner_text: state.actual_banner_text,
    banner_visible: true,
    banner_locked: true,
  };
}

function requireStoreCaptureArray(state, field, expected, message) {
  if (
    !Array.isArray(state[field])
    || state[field].length !== expected.length
    || state[field].some((value, index) =>
      typeof value !== 'number'
      || !Number.isFinite(value)
      || Math.abs(value - expected[index]) > COLOR_COMPONENT_TOLERANCE)
  ) {
    throw new Error(message);
  }
  return [...expected];
}

function requireStoreCaptureOpaqueAlpha(state, field, message) {
  const value = state[field];
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0.99) {
    throw new Error(message);
  }
  return value;
}

function requireStoreCaptureFullAlpha(state, field, message) {
  const value = state[field];
  if (typeof value !== 'number' || !Number.isFinite(value) || Math.abs(value - 1) > 1e-6) {
    throw new Error(message);
  }
  return value;
}

const CAPTURE_RECT_TOLERANCE = 0.51;
const GUARDIAN_CAPTURE_FOCUS_POSITION = Object.freeze([0.22, 0.24]);
const GUARDIAN_CAPTURE_FOCUS_SIZE = Object.freeze([0.56, 0.64]);
const GUARDIAN_CAPTURE_MIN_PLAYER_SEPARATION = 72;

function requireStoreCaptureRect(state, field, message) {
  const value = state[field];
  if (
    !Array.isArray(value)
    || value.length !== 4
    || value.some((component) =>
      typeof component !== 'number' || !Number.isFinite(component))
    || value[2] <= 0
    || value[3] <= 0
  ) {
    throw new Error(message);
  }
  return [...value];
}

function rectFullyInside(inner, outer) {
  return inner[0] >= outer[0] - CAPTURE_RECT_TOLERANCE
    && inner[1] >= outer[1] - CAPTURE_RECT_TOLERANCE
    && inner[0] + inner[2] <= outer[0] + outer[2] + CAPTURE_RECT_TOLERANCE
    && inner[1] + inner[3] <= outer[1] + outer[3] + CAPTURE_RECT_TOLERANCE;
}

function assertGuardianCaptureComposition(state, viewport) {
  const drawRect = requireStoreCaptureRect(
    state,
    'guardian_draw_rect',
    'Guardian live canvas rect is invalid.',
  );
  const focusRect = requireStoreCaptureRect(
    state,
    'guardian_focus_rect',
    'Guardian center-focus rect is invalid.',
  );
  const expectedFocus = [
    viewport[0] + viewport[2] * GUARDIAN_CAPTURE_FOCUS_POSITION[0],
    viewport[1] + viewport[3] * GUARDIAN_CAPTURE_FOCUS_POSITION[1],
    viewport[2] * GUARDIAN_CAPTURE_FOCUS_SIZE[0],
    viewport[3] * GUARDIAN_CAPTURE_FOCUS_SIZE[1],
  ];
  if (focusRect.some((component, index) =>
    Math.abs(component - expectedFocus[index]) > CAPTURE_RECT_TOLERANCE)) {
    throw new Error('Guardian center focus differs from the frozen composition contract.');
  }
  if (!rectFullyInside(drawRect, viewport)) {
    throw new Error('Guardian live frame is not entirely on screen.');
  }
  if (!rectFullyInside(drawRect, focusRect)) {
    throw new Error('Guardian live frame is outside the screen center focus.');
  }
  const center = [drawRect[0] + drawRect[2] * 0.5, drawRect[1] + drawRect[3] * 0.5];
  if (
    center[0] < focusRect[0] - CAPTURE_RECT_TOLERANCE
    || center[1] < focusRect[1] - CAPTURE_RECT_TOLERANCE
    || center[0] > focusRect[0] + focusRect[2] + CAPTURE_RECT_TOLERANCE
    || center[1] > focusRect[1] + focusRect[3] + CAPTURE_RECT_TOLERANCE
  ) {
    throw new Error('Guardian center point is not inside the screen center focus.');
  }
  const playerDistance = state.guardian_player_canvas_distance;
  if (
    typeof playerDistance !== 'number'
    || !Number.isFinite(playerDistance)
    || playerDistance < GUARDIAN_CAPTURE_MIN_PLAYER_SEPARATION
  ) {
    throw new Error('Guardian and player silhouettes are not separated enough.');
  }
  if (!Number.isSafeInteger(state.friendly_projectile_count)
    || state.friendly_projectile_count !== 0) {
    throw new Error('Guardian capture still has allied projectiles.');
  }
  return {
    guardian_capture_active: requireStoreCaptureValue(
      state, 'guardian_capture_active', true, 'Guardian center-composition freeze is not active.',
    ),
    friendly_projectile_count: 0,
    guardian_draw_rect: drawRect,
    guardian_focus_rect: focusRect,
    guardian_draw_rect_fully_inside_viewport: requireStoreCaptureValue(
      state, 'guardian_draw_rect_fully_inside_viewport', true,
      'Game proof that the Guardian live frame is entirely on screen failed.',
    ),
    guardian_draw_rect_inside_focus: requireStoreCaptureValue(
      state, 'guardian_draw_rect_inside_focus', true,
      'Game proof that the Guardian live frame is inside center focus failed.',
    ),
    guardian_draw_center_inside_focus: requireStoreCaptureValue(
      state, 'guardian_draw_center_inside_focus', true,
      'Game proof that the Guardian center point is inside center focus failed.',
    ),
    guardian_player_canvas_distance: playerDistance,
    guardian_separated_from_player: requireStoreCaptureValue(
      state, 'guardian_separated_from_player', true,
      'Guardian and player silhouette-separation proof failed.',
    ),
    guardian_central_composition: requireStoreCaptureValue(
      state, 'guardian_central_composition', true,
      'Guardian center-composition proof is not complete.',
    ),
  };
}

function assertSafeCaptureLayout(
  state,
  {
    viewportField = 'viewport_rect',
    readyFields = ['safe_ui_ready'],
    controls,
  },
) {
  const viewport = requireStoreCaptureRect(
    state,
    viewportField,
    'Capture screen coordinates are not a finite positive rect.',
  );
  const safe = requireStoreCaptureRect(
    state,
    'safe_rect',
    'OS safe-area coordinates are not a finite positive rect.',
  );
  if (!rectFullyInside(safe, viewport)) {
    throw new Error('OS safe area is outside the actual capture screen.');
  }
  const normalized = {
    [viewportField]: viewport,
    safe_rect: safe,
    safe_area_inside_viewport: requireStoreCaptureValue(
      state,
      'safe_area_inside_viewport',
      true,
      'Game could not judge the OS safe area as inside the screen.',
    ),
  };
  for (const readyField of readyFields) {
    normalized[readyField] = requireStoreCaptureValue(
      state,
      readyField,
      true,
      `Safe-area ready proof failed: ${readyField}`,
    );
  }
  for (const { rectField, insideField } of controls) {
    const rect = requireStoreCaptureRect(
      state,
      rectField,
      `Safe-area target coordinates are invalid: ${rectField}`,
    );
    if (!rectFullyInside(rect, safe)) {
      throw new Error(`UI intrudes on the OS gesture safe area: ${rectField}`);
    }
    normalized[rectField] = rect;
    normalized[insideField] = requireStoreCaptureValue(
      state,
      insideField,
      true,
      `Game safe-area verdict failed: ${insideField}`,
    );
  }
  return normalized;
}

const TITLE_SAFE_CONTROLS = Object.freeze([
  'title',
  'subtitle',
  'version',
  'tap_prompt',
  'settings_button',
  'shrine_button',
  'ladder_button',
  'store_button',
].map((name) => Object.freeze({
  rectField: `${name}_rect`,
  insideField: `${name}_inside_safe_area`,
})));

const ARENA_SAFE_CONTROLS = Object.freeze([
  'hud_left',
  'hud_right',
  'pause_button',
  'dash',
  'move_stick',
  'boss',
  'banner',
].map((name) => Object.freeze({
  rectField: `${name}_rect`,
  insideField: `${name}_inside_safe_area`,
})));

function assertArenaSafeCaptureLayout(state) {
  return assertSafeCaptureLayout(state, { controls: ARENA_SAFE_CONTROLS });
}

function assertTitleButtonState(state, name, sourceKey, translatedText) {
  const field = `${name}_button`;
  return {
    [`${field}_visible`]: requireStoreCaptureValue(
      state, `${field}_visible`, true, `Title ${name} button is not visible.`,
    ),
    [`${field}_enabled`]: requireStoreCaptureValue(
      state, `${field}_enabled`, true, `Title ${name} button is disabled.`,
    ),
    [`${field}_source_key`]: requireStoreCaptureValue(
      state, `${field}_source_key`, sourceKey, `Title ${name} button translation source key differs.`,
    ),
    [`${field}_auto_translate`]: requireStoreCaptureValue(
      state, `${field}_auto_translate`, true, `Title ${name} button auto-translate is off.`,
    ),
    [`${field}_translation_text`]: requireStoreCaptureValue(
      state, `${field}_translation_text`, translatedText,
      `Title ${name} button live translation differs from the current locale.`,
    ),
    [`${field}_inside_viewport`]: requireStoreCaptureValue(
      state, `${field}_inside_viewport`, true, `Title ${name} button is not on screen.`,
    ),
    [`${field}_copy_valid`]: requireStoreCaptureValue(
      state, `${field}_copy_valid`, true, `Title ${name} button translation contract does not match.`,
    ),
    [`${field}_text_nonempty`]: requireStoreCaptureValue(
      state, `${field}_text_nonempty`, true, `Title ${name} button copy is empty.`,
    ),
    [`${field}_font_size_positive`]: requireStoreCaptureValue(
      state, `${field}_font_size_positive`, true, `Title ${name} button font size is 0.`,
    ),
    [`${field}_font_alpha_readable`]: requireStoreCaptureValue(
      state, `${field}_font_alpha_readable`, true, `Title ${name} button glyphs are transparent.`,
    ),
    [`${field}_rendered_text_ready`]: requireStoreCaptureValue(
      state, `${field}_rendered_text_ready`, true, `Title ${name} button glyphs are not actually drawn.`,
    ),
    [`${field}_opaque`]: requireStoreCaptureValue(
      state, `${field}_opaque`, true, `Title ${name} button is transparent.`,
    ),
  };
}

function assertTitleStoreButtonState(state, translatedText, directDistribution) {
  const storefrontEnabled = !directDistribution;
  return {
    direct_distribution: requireStoreCaptureValue(
      state, 'direct_distribution', directDistribution,
      'Title direct_distribution feature differs from the capture build.',
    ),
    storefront_enabled: requireStoreCaptureValue(
      state, 'storefront_enabled', storefrontEnabled,
      'Title storefront state differs from the distribution feature.',
    ),
    storefront_feature_matches: requireStoreCaptureValue(
      state, 'storefront_feature_matches', true,
      'Title storefront verdict does not match the distribution feature.',
    ),
    store_button_visible: requireStoreCaptureValue(
      state, 'store_button_visible', storefrontEnabled,
      storefrontEnabled
        ? 'Title store button is not visible.'
        : 'A store button was composited visible on a direct-distribution title.',
    ),
    store_button_enabled: requireStoreCaptureValue(
      state, 'store_button_enabled', storefrontEnabled,
      storefrontEnabled
        ? 'Title store button is disabled.'
        : 'The hidden store button on a direct-distribution title is enabled.',
    ),
    store_button_visibility_matches_storefront: requireStoreCaptureValue(
      state, 'store_button_visibility_matches_storefront', true,
      'Title store button visibility differs from storefront state.',
    ),
    store_button_enabled_matches_storefront: requireStoreCaptureValue(
      state, 'store_button_enabled_matches_storefront', true,
      'Title store button enabled state differs from storefront state.',
    ),
    store_button_source_key: requireStoreCaptureValue(
      state, 'store_button_source_key', 'IAP_OPEN',
      'Title store button translation source key differs.',
    ),
    store_button_auto_translate: requireStoreCaptureValue(
      state, 'store_button_auto_translate', true,
      'Title store button auto-translate is off.',
    ),
    store_button_translation_text: requireStoreCaptureValue(
      state, 'store_button_translation_text', translatedText,
      'Title store button live translation differs from the current locale.',
    ),
    store_button_inside_viewport: requireStoreCaptureValue(
      state, 'store_button_inside_viewport', true,
      'Title store button product placement is not on screen.',
    ),
    store_button_copy_valid: requireStoreCaptureValue(
      state, 'store_button_copy_valid', true,
      'Title store button translation contract does not match.',
    ),
    store_button_text_nonempty: requireStoreCaptureValue(
      state, 'store_button_text_nonempty', true,
      'Title store button copy is empty.',
    ),
    store_button_font_size_positive: requireStoreCaptureValue(
      state, 'store_button_font_size_positive', true,
      'Title store button font size is 0.',
    ),
    store_button_font_alpha_readable: requireStoreCaptureValue(
      state, 'store_button_font_alpha_readable', true,
      'Title store button glyphs are transparent.',
    ),
    store_button_rendered_text_ready: requireStoreCaptureValue(
      state, 'store_button_rendered_text_ready', storefrontEnabled,
      'Title store button live render state differs from storefront.',
    ),
    store_button_opaque: requireStoreCaptureValue(
      state, 'store_button_opaque', storefrontEnabled,
      'Title store button live opaque state differs from storefront.',
    ),
  };
}

/**
 * Normalize the debug game's first-party proof for one store screenshot.
 * Coordinates, PNG sizes, and caller-provided product labels are deliberately
 * insufficient: the live panel or arena must describe what it actually drew.
 */
export function assertStoreCaptureState(state, expected) {
  assertStoreCaptureExpected(expected);
  if (!isRecord(state) || state.schema !== 1) {
    throw new TypeError('Store capture state schema is invalid.');
  }
  if (
    typeof state.nonce !== 'string'
    || !STORE_CAPTURE_NONCE_PATTERN.test(state.nonce)
  ) {
    throw new TypeError('Store capture state nonce is invalid.');
  }
  if (!Number.isSafeInteger(state.observation) || state.observation < 1) {
    throw new TypeError('Store capture state observation number is invalid.');
  }
  if (state.kind !== expected.kind) {
    throw new Error('Store capture state kind differs from the expected screen.');
  }
  if (state.game_locale !== expected.gameLocale) {
    throw new Error('Store capture state game locale differs.');
  }

  const common = {
    schema: 1,
    nonce: state.nonce,
    observation: state.observation,
    kind: expected.kind,
    game_locale: expected.gameLocale,
  };
  switch (expected.kind) {
    case 'title':
      if (
        typeof state.version_text !== 'string'
        || !/^v\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/u.test(state.version_text)
      ) {
        throw new Error('Title app version string is invalid.');
      }
      if (!(expected.gameLocale in TITLE_COPY_BY_GAME_LOCALE)) {
        throw new Error('Title translation-copy contract is missing.');
      }

      const titleSafeControls = expected.directDistribution
        ? TITLE_SAFE_CONTROLS.filter(
          ({ rectField }) => rectField !== 'store_button_rect',
        )
        : TITLE_SAFE_CONTROLS;
      return {
        ...common,
        ...assertSafeCaptureLayout(state, { controls: titleSafeControls }),
        scene: requireStoreCaptureValue(
          state, 'scene', 'title', 'Title capture is not the actual title scene.',
        ),
        ready: requireStoreCaptureValue(
          state, 'ready', true, 'Title screen is not capture-ready.',
        ),
        screen_visible: requireStoreCaptureValue(
          state, 'screen_visible', true, 'Title default screen is not visible.',
        ),
        title_visible: requireStoreCaptureValue(
          state, 'title_visible', true, 'Game title for the current language is not visible.',
        ),
        subtitle_visible: requireStoreCaptureValue(
          state, 'subtitle_visible', true, 'Subtitle for the current language is not visible.',
        ),
        title_source_key: requireStoreCaptureValue(
          state, 'title_source_key', 'TITLE_NAME', 'Title Label auto-translate source key differs.',
        ),
        subtitle_source_key: requireStoreCaptureValue(
          state,
          'subtitle_source_key',
          'TITLE_SUBTITLE',
          'Subtitle Label auto-translate source key differs.',
        ),
        title_auto_translate: requireStoreCaptureValue(
          state, 'title_auto_translate', true, 'Title Label auto-translate is off.',
        ),
        subtitle_auto_translate: requireStoreCaptureValue(
          state, 'subtitle_auto_translate', true, 'Subtitle Label auto-translate is off.',
        ),
        title_translation_text: requireStoreCaptureValue(
          state,
          'title_translation_text',
          TITLE_COPY_BY_GAME_LOCALE[expected.gameLocale].title,
          'Title live translation differs from the current locale.',
        ),
        subtitle_translation_text: requireStoreCaptureValue(
          state,
          'subtitle_translation_text',
          TITLE_COPY_BY_GAME_LOCALE[expected.gameLocale].subtitle,
          'Subtitle live translation differs from the current locale.',
        ),
        title_text_nonempty: requireStoreCaptureValue(
          state, 'title_text_nonempty', true, 'Title heading copy is empty.',
        ),
        title_characters_visible: requireStoreCaptureValue(
          state, 'title_characters_visible', true, 'Title heading glyphs are hidden.',
        ),
        title_font_size_positive: requireStoreCaptureValue(
          state, 'title_font_size_positive', true, 'Title heading font size is 0.',
        ),
        title_font_alpha_readable: requireStoreCaptureValue(
          state, 'title_font_alpha_readable', true, 'Title heading glyphs are transparent.',
        ),
        title_rendered_text_ready: requireStoreCaptureValue(
          state, 'title_rendered_text_ready', true, 'Title heading is not actually drawn.',
        ),
        subtitle_text_nonempty: requireStoreCaptureValue(
          state, 'subtitle_text_nonempty', true, 'Title subtitle copy is empty.',
        ),
        subtitle_characters_visible: requireStoreCaptureValue(
          state, 'subtitle_characters_visible', true, 'Title subtitle glyphs are hidden.',
        ),
        subtitle_font_size_positive: requireStoreCaptureValue(
          state, 'subtitle_font_size_positive', true, 'Title subtitle font size is 0.',
        ),
        subtitle_font_alpha_readable: requireStoreCaptureValue(
          state, 'subtitle_font_alpha_readable', true, 'Title subtitle glyphs are transparent.',
        ),
        subtitle_rendered_text_ready: requireStoreCaptureValue(
          state, 'subtitle_rendered_text_ready', true, 'Title subtitle is not actually drawn.',
        ),
        title_inside_viewport: requireStoreCaptureValue(
          state, 'title_inside_viewport', true, 'Title heading was not laid out on screen.',
        ),
        subtitle_inside_viewport: requireStoreCaptureValue(
          state, 'subtitle_inside_viewport', true, 'Title subtitle was not laid out on screen.',
        ),
        title_opaque: requireStoreCaptureValue(
          state, 'title_opaque', true, 'Title heading is transparent.',
        ),
        subtitle_opaque: requireStoreCaptureValue(
          state, 'subtitle_opaque', true, 'Title subtitle is transparent.',
        ),
        version_visible: requireStoreCaptureValue(
          state, 'version_visible', true, 'Current app version is not visible on the title.',
        ),
        version_text: state.version_text,
        version_text_nonempty: requireStoreCaptureValue(
          state, 'version_text_nonempty', true, 'App version copy is empty.',
        ),
        version_characters_visible: requireStoreCaptureValue(
          state, 'version_characters_visible', true, 'App version glyphs are hidden.',
        ),
        version_font_size_positive: requireStoreCaptureValue(
          state, 'version_font_size_positive', true, 'App version font size is 0.',
        ),
        version_font_alpha_readable: requireStoreCaptureValue(
          state, 'version_font_alpha_readable', true, 'App version glyphs are transparent.',
        ),
        version_rendered_text_ready: requireStoreCaptureValue(
          state, 'version_rendered_text_ready', true, 'App version is not actually drawn.',
        ),
        version_inside_viewport: requireStoreCaptureValue(
          state, 'version_inside_viewport', true, 'App version was not laid out on screen.',
        ),
        version_opaque: requireStoreCaptureValue(
          state, 'version_opaque', true, 'App version label is transparent.',
        ),
        tap_prompt_visible: requireStoreCaptureValue(
          state, 'tap_prompt_visible', true, 'Start prompt is not visible.',
        ),
        tap_prompt_source_key: requireStoreCaptureValue(
          state, 'tap_prompt_source_key', 'TAP_TO_START', 'Start prompt auto-translate source key differs.',
        ),
        tap_prompt_auto_translate: requireStoreCaptureValue(
          state, 'tap_prompt_auto_translate', true, 'Start prompt auto-translate is off.',
        ),
        tap_prompt_translation_text: requireStoreCaptureValue(
          state, 'tap_prompt_translation_text', TITLE_COPY_BY_GAME_LOCALE[expected.gameLocale].tap,
          'Start prompt live translation differs from the current locale.',
        ),
        tap_prompt_text_nonempty: requireStoreCaptureValue(
          state, 'tap_prompt_text_nonempty', true, 'Start prompt copy is empty.',
        ),
        tap_prompt_characters_visible: requireStoreCaptureValue(
          state, 'tap_prompt_characters_visible', true, 'Start prompt glyphs are hidden.',
        ),
        tap_prompt_font_size_positive: requireStoreCaptureValue(
          state, 'tap_prompt_font_size_positive', true, 'Start prompt font size is 0.',
        ),
        tap_prompt_font_alpha_readable: requireStoreCaptureValue(
          state, 'tap_prompt_font_alpha_readable', true, 'Start prompt glyphs are transparent.',
        ),
        tap_prompt_rendered_text_ready: requireStoreCaptureValue(
          state, 'tap_prompt_rendered_text_ready', true, 'Start prompt is not actually drawn.',
        ),
        tap_prompt_inside_viewport: requireStoreCaptureValue(
          state, 'tap_prompt_inside_viewport', true, 'Start prompt was not laid out on screen.',
        ),
        tap_prompt_readable_alpha: requireStoreCaptureValue(
          state, 'tap_prompt_readable_alpha', true, 'Start prompt is not fully opaque.',
        ),
        tap_prompt_effective_alpha: requireStoreCaptureFullAlpha(
          state, 'tap_prompt_effective_alpha', 'Start prompt live alpha is not 1.',
        ),
        tap_prompt_full_alpha: requireStoreCaptureValue(
          state, 'tap_prompt_full_alpha', true, 'Start prompt full-opaque proof failed.',
        ),
        tap_prompt_blink_stopped: requireStoreCaptureValue(
          state, 'tap_prompt_blink_stopped', true, 'Start prompt blink did not stop.',
        ),
        tap_prompt_modulate_white: requireStoreCaptureValue(
          state, 'tap_prompt_modulate_white', true, 'Start prompt was not frozen to full white.',
        ),
        tap_prompt_capture_locked: requireStoreCaptureValue(
          state, 'tap_prompt_capture_locked', true, 'Start prompt capture freeze is not active.',
        ),
        ...assertTitleButtonState(state, 'settings', 'SETTINGS_TITLE',
          TITLE_COPY_BY_GAME_LOCALE[expected.gameLocale].settings),
        ...assertTitleButtonState(state, 'shrine', 'SHRINE_OPEN',
          TITLE_COPY_BY_GAME_LOCALE[expected.gameLocale].shrine),
        ...assertTitleButtonState(state, 'ladder', 'LADDER_OPEN',
          TITLE_COPY_BY_GAME_LOCALE[expected.gameLocale].ladder),
        ...assertTitleStoreButtonState(
          state,
          TITLE_COPY_BY_GAME_LOCALE[expected.gameLocale].store,
          expected.directDistribution,
        ),
        night_forest_node_present: requireStoreCaptureValue(
          state, 'night_forest_node_present', true, 'Title live NightForest node is missing.',
        ),
        night_forest_scene_path: requireStoreCaptureValue(
          state, 'night_forest_scene_path', TITLE_NIGHT_FOREST_SCENE_PATH,
          'Title forest live scene path differs from the release contract.',
        ),
        night_forest_expected_scene_path: requireStoreCaptureValue(
          state, 'night_forest_expected_scene_path', TITLE_NIGHT_FOREST_SCENE_PATH,
          'Title forest expected scene path differs from the release contract.',
        ),
        night_forest_scene_matches: requireStoreCaptureValue(
          state, 'night_forest_scene_matches', true, 'Title forest scene does not match the pinned asset.',
        ),
        night_forest_visible_in_tree: requireStoreCaptureValue(
          state, 'night_forest_visible_in_tree', true, 'Title forest is not visible in the live tree.',
        ),
        night_forest_effective_alpha: requireStoreCaptureOpaqueAlpha(
          state, 'night_forest_effective_alpha', 'Title forest root is transparent.',
        ),
        night_forest_opaque: requireStoreCaptureValue(
          state, 'night_forest_opaque', true, 'Title forest root is not opaque.',
        ),
        night_forest_ground_resource_path: requireStoreCaptureValue(
          state, 'night_forest_ground_resource_path', TITLE_NIGHT_FOREST_GROUND_PATH,
          'Title forest floor live resource path differs from the release contract.',
        ),
        night_forest_expected_ground_resource_path: requireStoreCaptureValue(
          state, 'night_forest_expected_ground_resource_path', TITLE_NIGHT_FOREST_GROUND_PATH,
          'Title forest floor expected resource path differs from the release contract.',
        ),
        night_forest_ground_resource_matches: requireStoreCaptureValue(
          state, 'night_forest_ground_resource_matches', true,
          'Title forest floor does not match the pinned asset.',
        ),
        night_forest_drawable_visible_in_tree: requireStoreCaptureValue(
          state, 'night_forest_drawable_visible_in_tree', true,
          'Title forest live drawable is not visible.',
        ),
        night_forest_drawable_effective_alpha: requireStoreCaptureOpaqueAlpha(
          state, 'night_forest_drawable_effective_alpha',
          'Title forest live drawable is transparent.',
        ),
        night_forest_drawable_opaque: requireStoreCaptureValue(
          state, 'night_forest_drawable_opaque', true,
          'Title forest live drawable is not opaque.',
        ),
        night_forest_draw_rect_positive: requireStoreCaptureValue(
          state, 'night_forest_draw_rect_positive', true,
          'Title forest live draw rect is not a meaningful size.',
        ),
        night_forest_draw_rect_intersects_viewport: requireStoreCaptureValue(
          state, 'night_forest_draw_rect_intersects_viewport', true,
          'Title forest live draw rect does not intersect the screen.',
        ),
        night_forest_visual_ready: requireStoreCaptureValue(
          state, 'night_forest_visual_ready', true, 'Title forest art is not live-render-ready.',
        ),
        vignette_node_present: requireStoreCaptureValue(
          state, 'vignette_node_present', true, 'Title live Vignette node is missing.',
        ),
        vignette_node_class: requireStoreCaptureValue(
          state, 'vignette_node_class', TITLE_VIGNETTE_NODE_CLASS,
          'Title vignette live node type is not Sprite2D.',
        ),
        vignette_texture_class: requireStoreCaptureValue(
          state, 'vignette_texture_class', TITLE_VIGNETTE_TEXTURE_CLASS,
          'Title vignette live texture type differs from the release contract.',
        ),
        vignette_expected_texture_class: requireStoreCaptureValue(
          state, 'vignette_expected_texture_class', TITLE_VIGNETTE_TEXTURE_CLASS,
          'Title vignette expected texture type differs from the release contract.',
        ),
        vignette_texture_unique_id: requireStoreCaptureValue(
          state, 'vignette_texture_unique_id', TITLE_VIGNETTE_TEXTURE_UNIQUE_ID,
          'Title vignette live texture unique id differs from the release contract.',
        ),
        vignette_expected_texture_unique_id: requireStoreCaptureValue(
          state, 'vignette_expected_texture_unique_id', TITLE_VIGNETTE_TEXTURE_UNIQUE_ID,
          'Title vignette expected texture unique id differs from the release contract.',
        ),
        vignette_texture_dimensions_match: requireStoreCaptureValue(
          state, 'vignette_texture_dimensions_match', true,
          'Title vignette texture size differs from the release contract.',
        ),
        vignette_texture_matches: requireStoreCaptureValue(
          state, 'vignette_texture_matches', true, 'Title vignette does not match the pinned asset.',
        ),
        vignette_visible_in_tree: requireStoreCaptureValue(
          state, 'vignette_visible_in_tree', true, 'Title vignette is not visible in the live tree.',
        ),
        vignette_effective_alpha: requireStoreCaptureOpaqueAlpha(
          state, 'vignette_effective_alpha', 'Title vignette is transparent.',
        ),
        vignette_opaque: requireStoreCaptureValue(
          state, 'vignette_opaque', true, 'Title vignette is not opaque.',
        ),
        vignette_draw_rect_positive: requireStoreCaptureValue(
          state, 'vignette_draw_rect_positive', true,
          'Title vignette live draw rect is not a meaningful size.',
        ),
        vignette_draw_rect_intersects_viewport: requireStoreCaptureValue(
          state, 'vignette_draw_rect_intersects_viewport', true,
          'Title vignette live draw rect does not intersect the screen.',
        ),
        vignette_visual_ready: requireStoreCaptureValue(
          state, 'vignette_visual_ready', true,
          'Title vignette art is not live-render-ready.',
        ),
        beacon_node_present: requireStoreCaptureValue(
          state, 'beacon_node_present', true, 'Title live Beacon node is missing.',
        ),
        beacon_scene_path: requireStoreCaptureValue(
          state, 'beacon_scene_path', TITLE_BEACON_SCENE_PATH,
          'Title beacon live scene path differs from the release contract.',
        ),
        beacon_expected_scene_path: requireStoreCaptureValue(
          state, 'beacon_expected_scene_path', TITLE_BEACON_SCENE_PATH,
          'Title beacon expected scene path differs from the release contract.',
        ),
        beacon_scene_matches: requireStoreCaptureValue(
          state, 'beacon_scene_matches', true, 'Title beacon scene does not match the pinned asset.',
        ),
        beacon_visible_in_tree: requireStoreCaptureValue(
          state, 'beacon_visible_in_tree', true, 'Title beacon is not visible in the live tree.',
        ),
        beacon_effective_alpha: requireStoreCaptureOpaqueAlpha(
          state, 'beacon_effective_alpha', 'Title beacon root is transparent.',
        ),
        beacon_opaque: requireStoreCaptureValue(
          state, 'beacon_opaque', true, 'Title beacon root is not opaque.',
        ),
        beacon_clearing_resource_path: requireStoreCaptureValue(
          state, 'beacon_clearing_resource_path', TITLE_BEACON_CLEARING_PATH,
          'Title beacon floor live resource path differs from the release contract.',
        ),
        beacon_expected_clearing_resource_path: requireStoreCaptureValue(
          state, 'beacon_expected_clearing_resource_path', TITLE_BEACON_CLEARING_PATH,
          'Title beacon floor expected resource path differs from the release contract.',
        ),
        beacon_clearing_resource_matches: requireStoreCaptureValue(
          state, 'beacon_clearing_resource_matches', true,
          'Title beacon floor does not match the pinned asset.',
        ),
        beacon_drawable_visible_in_tree: requireStoreCaptureValue(
          state, 'beacon_drawable_visible_in_tree', true,
          'Title beacon live drawable is not visible.',
        ),
        beacon_drawable_effective_alpha: requireStoreCaptureOpaqueAlpha(
          state, 'beacon_drawable_effective_alpha',
          'Title beacon live drawable is transparent.',
        ),
        beacon_drawable_opaque: requireStoreCaptureValue(
          state, 'beacon_drawable_opaque', true,
          'Title beacon live drawable is not opaque.',
        ),
        beacon_draw_rect_positive: requireStoreCaptureValue(
          state, 'beacon_draw_rect_positive', true,
          'Title beacon live draw rect is not a meaningful size.',
        ),
        beacon_draw_rect_intersects_viewport: requireStoreCaptureValue(
          state, 'beacon_draw_rect_intersects_viewport', true,
          'Title beacon live draw rect does not intersect the screen.',
        ),
        beacon_visual_ready: requireStoreCaptureValue(
          state, 'beacon_visual_ready', true, 'Title beacon art is not live-render-ready.',
        ),
        panels_closed: requireStoreCaptureValue(
          state, 'panels_closed', true, 'Another panel is open over the title.',
        ),
        accepting_input: requireStoreCaptureValue(
          state, 'accepting_input', true, 'Title cannot accept start input.',
        ),
        screen_inside_viewport: requireStoreCaptureValue(
          state, 'screen_inside_viewport', true, 'Title UI was not laid out on screen.',
        ),
        drawn_after_ready: requireStoreCaptureValue(
          state, 'drawn_after_ready', true, 'Title has no render frame after ready.',
        ),
      };
    case 'arena_ready':
      return {
        ...common,
        ...assertArenaSafeCaptureLayout(state),
        scene: requireStoreCaptureValue(
          state,
          'scene',
          'arena',
          'Combat ready state is not the actual arena scene.',
        ),
        ready: requireStoreCaptureValue(
          state,
          'ready',
          true,
          'Combat scene is not capture-ready.',
        ),
        over: requireStoreCaptureValue(
          state,
          'over',
          false,
          'A finished combat scene cannot be used as a ready proof.',
        ),
      };
    case 'moonlight_barrage':
      if (
        !Number.isSafeInteger(state.missile_visual_probe_count)
        || state.missile_visual_probe_count < 1
      ) {
        throw new Error('Moonlight barrage live missile visual probe is missing.');
      }
      if (
        typeof state.missile_effective_alpha !== 'number'
        || !Number.isFinite(state.missile_effective_alpha)
        || state.missile_effective_alpha < 0.99
      ) {
        throw new Error('Moonlight barrage live missile is transparent.');
      }
      if (
        !Number.isSafeInteger(state.visible_enemy_sprite_count)
        || state.visible_enemy_sprite_count < 3
      ) {
        throw new Error('Moonlight barrage has fewer than 3 actually visible enemy sprites.');
      }
      const barrageBanner = requirePinnedCaptureBanner(
        state, 'MISSILE_COMPLETE', 'Moonlight barrage',
      );
      return {
        ...common,
        ...assertArenaSafeCaptureLayout(state),
        ...barrageBanner,
        scene: requireStoreCaptureValue(
          state, 'scene', 'arena', 'Moonlight barrage capture is not the actual arena scene.',
        ),
        ready: requireStoreCaptureValue(
          state, 'ready', true, 'Moonlight barrage scene is not capture-ready.',
        ),
        over: requireStoreCaptureValue(
          state, 'over', false, 'A finished combat cannot be used as Moonlight barrage proof.',
        ),
        level: requireStoreCaptureValue(
          state, 'level', 20, 'Moonlight barrage capture is not level 20.',
        ),
        cycle: requireStoreCaptureValue(
          state, 'cycle', 3, 'Moonlight barrage capture is not cycle 3.',
        ),
        zone_index: requireStoreCaptureValue(
          state, 'zone_index', 0, 'Moonlight barrage capture is not the cycle-3 starting biome.',
        ),
        terrain_path: requireStoreCaptureValue(
          state,
          'terrain_path',
          'res://resources/rooms/camp.tres',
          'Moonlight barrage capture biome is not abandoned camp.',
        ),
        world_key: requireStoreCaptureValue(
          state, 'world_key', 'WORLD_CAMP', 'Moonlight barrage biome cycle key is not camp.',
        ),
        lit_beacons: requireStoreCaptureValue(
          state, 'lit_beacons', 0, 'Moonlight barrage is not an unlit night state.',
        ),
        transitioning: requireStoreCaptureValue(
          state, 'transitioning', false, 'Moonlight barrage is mid biome transition.',
        ),
        escape_active: requireStoreCaptureValue(
          state, 'escape_active', false, 'Moonlight barrage has the escape gate open.',
        ),
        time_key: requireStoreCaptureValue(
          state, 'time_key', 'TIME_NIGHT', 'Moonlight barrage time of day is not night.',
        ),
        time_tone: requireStoreCaptureArray(
          state, 'time_tone', NIGHT_TONE, 'Moonlight barrage night-tone contract differs.',
        ),
        applied_time_tone: requireStoreCaptureArray(
          state, 'applied_time_tone', NIGHT_TONE, 'Night tone was not applied to the Moonlight barrage background.',
        ),
        time_tone_applied: requireStoreCaptureValue(
          state, 'time_tone_applied', true, 'Moonlight barrage background tone differs from the time of day.',
        ),
        missile_power: requireStoreCaptureValue(
          state, 'missile_power', 8, 'Moonlight barrage missile power is not 8.',
        ),
        missile_max: requireStoreCaptureValue(
          state, 'missile_max', 8, 'Moonlight barrage max missile power is not 8.',
        ),
        missile_volley: requireStoreCaptureValue(
          state, 'missile_volley', 8, 'Moonlight barrage is not an 8-shot volley.',
        ),
        homing_active: requireStoreCaptureValue(
          state, 'homing_active', true, 'Moonlight barrage homing is not enabled.',
        ),
        moonfire_active: requireStoreCaptureValue(
          state,
          'moonfire_active',
          false,
          'Cannot show an extinguished moon-ember preset as an awakening screen.',
        ),
        missile_visual_probe_count: state.missile_visual_probe_count,
        missile_visible_in_tree: requireStoreCaptureValue(
          state, 'missile_visible_in_tree', true, 'Moonlight barrage missiles are not visible in the live tree.',
        ),
        missile_effective_alpha: state.missile_effective_alpha,
        missile_opaque: requireStoreCaptureValue(
          state, 'missile_opaque', true, 'Moonlight barrage missiles are not opaque.',
        ),
        missile_draw_after_launch: requireStoreCaptureValue(
          state, 'missile_draw_after_launch', true, 'Moonlight barrage was not actually drawn after launch.',
        ),
        missile_head_geometry_ready: requireStoreCaptureValue(
          state, 'missile_head_geometry_ready', true, 'Moonlight barrage live warhead geometry is missing.',
        ),
        missile_trail_geometry_ready: requireStoreCaptureValue(
          state, 'missile_trail_geometry_ready', true, 'Moonlight barrage live trail geometry is missing.',
        ),
        visible_enemy_sprite_count: state.visible_enemy_sprite_count,
        enemy_formation_visible: requireStoreCaptureValue(
          state, 'enemy_formation_visible', true, 'The enemy formation to face is not visible on screen.',
        ),
        max_volley_live: requireStoreCaptureValue(
          state, 'max_volley_live', true, 'There is no live 8-shot volley.',
        ),
        barrage_visible: requireStoreCaptureValue(
          state, 'barrage_visible', true, 'Moonlight missile barrage is not visible on screen.',
        ),
      };
    case 'shrine':
      return {
        ...common,
        ...assertSafeCaptureLayout(state, {
          readyFields: ['shrine_safe_ui_ready'],
          controls: [{
            rectField: 'shrine_frame_rect',
            insideField: 'shrine_frame_inside_safe_area',
          }],
        }),
        shrine_visible: requireStoreCaptureValue(
          state,
          'shrine_visible',
          true,
          'Shrine panel is not visible.',
        ),
        preview_visible: requireStoreCaptureValue(
          state,
          'preview_visible',
          false,
          'Hero detail is open over the shrine list.',
        ),
        hero_card_count: requireStoreCaptureValue(
          state,
          'hero_card_count',
          6,
          'Not all 6 shrine hero cards are visible.',
        ),
        hero_cards_visible_rect_count: requireStoreCaptureValue(
          state,
          'hero_cards_visible_rect_count',
          6,
          'Live visible rects for the 6 shrine hero cards are not ready.',
        ),
        shrine_opaque: requireStoreCaptureValue(
          state,
          'shrine_opaque',
          true,
          'Shrine panel open transition has not finished.',
        ),
        shrine_frame_inside_viewport: requireStoreCaptureValue(
          state,
          'shrine_frame_inside_viewport',
          true,
          'Shrine panel was not laid out on screen.',
        ),
        shrine_drawn_after_open: requireStoreCaptureValue(
          state,
          'shrine_drawn_after_open',
          true,
          'No render frame after opening the shrine panel.',
        ),
      };
    case 'hero_preview': {
      const previewVisual = HERO_PREVIEW_VISUAL_BY_HERO_PATH[expected.heroPath];
      if (previewVisual === undefined) {
        throw new Error('Hero-preview capture independent asset contract is missing.');
      }
      const previewCopy = HERO_PREVIEW_COPY_BY_GAME_LOCALE[expected.gameLocale];
      if (previewCopy === undefined) {
        throw new Error('Hero-preview capture independent localized-copy contract is missing.');
      }
      const stateSourceKey = state.state_source_key;
      if (
        typeof stateSourceKey !== 'string'
        || !HERO_PREVIEW_STATE_SOURCE_KEYS.has(stateSourceKey)
      ) {
        throw new Error('Hero-preview state translation source key is not an allowed state.');
      }
      const stateText = previewCopy.states[stateSourceKey];
      return {
        ...common,
        ...assertSafeCaptureLayout(state, {
          readyFields: ['shrine_safe_ui_ready', 'preview_safe_ui_ready'],
          controls: [
            {
              rectField: 'shrine_frame_rect',
              insideField: 'shrine_frame_inside_safe_area',
            },
            {
              rectField: 'preview_frame_rect',
              insideField: 'preview_frame_inside_safe_area',
            },
            {
              rectField: 'close_rect',
              insideField: 'close_inside_safe_area',
            },
          ],
        }),
        shrine_visible: requireStoreCaptureValue(
          state,
          'shrine_visible',
          true,
          'Shrine panel behind hero detail is not visible.',
        ),
        shrine_opaque: requireStoreCaptureValue(
          state,
          'shrine_opaque',
          true,
          'Shrine open transition behind hero detail has not finished.',
        ),
        shrine_frame_inside_viewport: requireStoreCaptureValue(
          state,
          'shrine_frame_inside_viewport',
          true,
          'Shrine behind hero detail was not laid out on screen.',
        ),
        shrine_drawn_after_open: requireStoreCaptureValue(
          state,
          'shrine_drawn_after_open',
          true,
          'No render frame after opening the shrine behind hero detail.',
        ),
        preview_visible: requireStoreCaptureValue(
          state,
          'preview_visible',
          true,
          'Hero-preview panel is not visible.',
        ),
        hero_path: requireStoreCaptureValue(
          state,
          'hero_path',
          expected.heroPath,
          'Hero-preview panel hero path differs from expected.',
        ),
        portrait_visible: requireStoreCaptureValue(
          state,
          'portrait_visible',
          true,
          'Hero-preview portrait is not visible.',
        ),
        portrait_texture_ready: requireStoreCaptureValue(
          state, 'portrait_texture_ready', true, 'Hero-preview portrait texture differs from the hero resource.',
        ),
        portrait_resource_path: requireStoreCaptureValue(
          state, 'portrait_resource_path', previewVisual.portrait,
          'Hero-preview live portrait resource differs from the ad contract.',
        ),
        portrait_expected_resource_path: requireStoreCaptureValue(
          state, 'portrait_expected_resource_path', previewVisual.portrait,
          'Hero-preview expected portrait resource contract differs.',
        ),
        portrait_resource_matches: requireStoreCaptureValue(
          state, 'portrait_resource_matches', true,
          'Hero-preview portrait is not the target hero pinned asset.',
        ),
        portrait_visible_rect_ready: requireStoreCaptureValue(
          state, 'portrait_visible_rect_ready', true, 'Hero-preview portrait live visible area is missing.',
        ),
        portrait_opaque: requireStoreCaptureValue(
          state, 'portrait_opaque', true, 'Hero-preview portrait is transparent.',
        ),
        body_visible: requireStoreCaptureValue(
          state,
          'body_visible',
          true,
          'Hero-preview full-body image is not visible.',
        ),
        body_texture_ready: requireStoreCaptureValue(
          state, 'body_texture_ready', true, 'Hero-preview full-body texture differs from the hero resource.',
        ),
        body_resource_path: requireStoreCaptureValue(
          state, 'body_resource_path', previewVisual.body,
          'Hero-preview live full-body resource differs from the ad contract.',
        ),
        body_expected_resource_path: requireStoreCaptureValue(
          state, 'body_expected_resource_path', previewVisual.body,
          'Hero-preview expected full-body resource contract differs.',
        ),
        body_resource_matches: requireStoreCaptureValue(
          state, 'body_resource_matches', true,
          'Hero-preview full-body is not the target hero pinned asset.',
        ),
        body_visible_rect_ready: requireStoreCaptureValue(
          state, 'body_visible_rect_ready', true, 'Hero-preview full-body live visible area is missing.',
        ),
        body_opaque: requireStoreCaptureValue(
          state, 'body_opaque', true, 'Hero-preview full-body is transparent.',
        ),
        copy_locale: requireStoreCaptureValue(
          state, 'copy_locale', expected.gameLocale,
          'Hero-preview copy locale differs from the capture locale.',
        ),
        name_source_key: requireStoreCaptureValue(
          state, 'name_source_key', HERO_PREVIEW_NAME_SOURCE_KEY,
          'Hero-preview name live translation source key differs from the Keeper contract.',
        ),
        name_expected_source_key: requireStoreCaptureValue(
          state, 'name_expected_source_key', HERO_PREVIEW_NAME_SOURCE_KEY,
          'Hero-preview name expected translation source key differs from the Keeper contract.',
        ),
        name_source_matches: requireStoreCaptureValue(
          state, 'name_source_matches', true,
          'Hero-preview name translation source key does not match the pinned Keeper key.',
        ),
        name_text: requireStoreCaptureValue(
          state, 'name_text', previewCopy.name,
          'Hero-preview live name differs from current-locale Keeper copy.',
        ),
        name_expected_text: requireStoreCaptureValue(
          state, 'name_expected_text', previewCopy.name,
          'Hero-preview expected name differs from the independent Keeper copy contract.',
        ),
        name_copy_valid: requireStoreCaptureValue(
          state, 'name_copy_valid', true, 'Hero-preview name copy contract failed.',
        ),
        name_text_nonempty: requireStoreCaptureValue(
          state, 'name_text_nonempty', true, 'Hero-preview name is empty.',
        ),
        name_characters_visible: requireStoreCaptureValue(
          state, 'name_characters_visible', true, 'Hero-preview name glyphs are hidden.',
        ),
        name_font_size_positive: requireStoreCaptureValue(
          state, 'name_font_size_positive', true, 'Hero-preview name font size is 0.',
        ),
        name_font_alpha_readable: requireStoreCaptureValue(
          state, 'name_font_alpha_readable', true, 'Hero-preview name glyphs are transparent.',
        ),
        name_visible_rect_ready: requireStoreCaptureValue(
          state, 'name_visible_rect_ready', true,
          'Hero-preview name live visible area is not on screen.',
        ),
        name_opaque: requireStoreCaptureValue(
          state, 'name_opaque', true, 'Hero-preview name label is transparent.',
        ),
        name_rendered_text_ready: requireStoreCaptureValue(
          state, 'name_rendered_text_ready', true,
          'Hero-preview name is not actually renderable.',
        ),
        state_source_key: stateSourceKey,
        state_expected_source_key: requireStoreCaptureValue(
          state, 'state_expected_source_key', stateSourceKey,
          'Hero-preview state expected translation source key differs from the live state.',
        ),
        state_source_matches: requireStoreCaptureValue(
          state, 'state_source_matches', true,
          'Hero-preview state translation source key does not match the current state.',
        ),
        state_text: requireStoreCaptureValue(
          state, 'state_text', stateText,
          'Hero-preview live state copy differs from the current locale.',
        ),
        state_expected_text: requireStoreCaptureValue(
          state, 'state_expected_text', stateText,
          'Hero-preview expected state copy differs from the independent localization contract.',
        ),
        state_copy_valid: requireStoreCaptureValue(
          state, 'state_copy_valid', true, 'Hero-preview state copy contract failed.',
        ),
        state_text_nonempty: requireStoreCaptureValue(
          state, 'state_text_nonempty', true, 'Hero-preview state copy is empty.',
        ),
        state_characters_visible: requireStoreCaptureValue(
          state, 'state_characters_visible', true, 'Hero-preview state glyphs are hidden.',
        ),
        state_font_size_positive: requireStoreCaptureValue(
          state, 'state_font_size_positive', true, 'Hero-preview state font size is 0.',
        ),
        state_font_alpha_readable: requireStoreCaptureValue(
          state, 'state_font_alpha_readable', true, 'Hero-preview state glyphs are transparent.',
        ),
        state_visible_rect_ready: requireStoreCaptureValue(
          state, 'state_visible_rect_ready', true,
          'Hero-preview state live visible area is not on screen.',
        ),
        state_opaque: requireStoreCaptureValue(
          state, 'state_opaque', true, 'Hero-preview state label is transparent.',
        ),
        state_rendered_text_ready: requireStoreCaptureValue(
          state, 'state_rendered_text_ready', true,
          'Hero-preview state is not actually renderable.',
        ),
        description_source_key: requireStoreCaptureValue(
          state, 'description_source_key', HERO_PREVIEW_DESCRIPTION_SOURCE_KEY,
          'Hero-preview description live translation source key differs from the Keeper contract.',
        ),
        description_expected_source_key: requireStoreCaptureValue(
          state, 'description_expected_source_key', HERO_PREVIEW_DESCRIPTION_SOURCE_KEY,
          'Hero-preview description expected translation source key differs from the Keeper contract.',
        ),
        description_source_matches: requireStoreCaptureValue(
          state, 'description_source_matches', true,
          'Hero-preview description translation source key does not match the pinned Keeper key.',
        ),
        description_text: requireStoreCaptureValue(
          state, 'description_text', previewCopy.description,
          'Hero-preview live description differs from current-locale Keeper copy.',
        ),
        description_expected_text: requireStoreCaptureValue(
          state, 'description_expected_text', previewCopy.description,
          'Hero-preview expected description differs from the independent Keeper copy contract.',
        ),
        description_copy_valid: requireStoreCaptureValue(
          state, 'description_copy_valid', true, 'Hero-preview description copy contract failed.',
        ),
        description_text_nonempty: requireStoreCaptureValue(
          state, 'description_text_nonempty', true, 'Hero-preview description is empty.',
        ),
        description_characters_visible: requireStoreCaptureValue(
          state, 'description_characters_visible', true,
          'Hero-preview description glyphs are hidden.',
        ),
        description_font_size_positive: requireStoreCaptureValue(
          state, 'description_font_size_positive', true, 'Hero-preview description font size is 0.',
        ),
        description_font_alpha_readable: requireStoreCaptureValue(
          state, 'description_font_alpha_readable', true, 'Hero-preview description glyphs are transparent.',
        ),
        description_visible_rect_ready: requireStoreCaptureValue(
          state, 'description_visible_rect_ready', true,
          'Hero-preview description live visible area is not on screen.',
        ),
        description_opaque: requireStoreCaptureValue(
          state, 'description_opaque', true, 'Hero-preview description label is transparent.',
        ),
        description_rendered_text_ready: requireStoreCaptureValue(
          state, 'description_rendered_text_ready', true,
          'Hero-preview description is not actually renderable.',
        ),
        close_visible: requireStoreCaptureValue(
          state,
          'close_visible',
          true,
          'Hero-preview close button is not visible.',
        ),
        close_inside_viewport: requireStoreCaptureValue(
          state, 'close_inside_viewport', true, 'Hero-preview close button was not laid out on screen.',
        ),
        close_opaque: requireStoreCaptureValue(
          state, 'close_opaque', true, 'Hero-preview close button is transparent.',
        ),
        preview_opaque: requireStoreCaptureValue(
          state,
          'preview_opaque',
          true,
          'Hero-preview open transition has not finished.',
        ),
        preview_frame_inside_viewport: requireStoreCaptureValue(
          state,
          'preview_frame_inside_viewport',
          true,
          'Hero preview was not laid out on screen.',
        ),
        preview_drawn_after_open: requireStoreCaptureValue(
          state,
          'preview_drawn_after_open',
          true,
          'No render frame after opening hero preview.',
        ),
      };
    }
    case 'field_guardian': {
      if (!Number.isSafeInteger(state.cycle) || state.cycle < 1) {
        throw new Error('Guardian capture cycle count is invalid.');
      }
      if (typeof state.guardian_name !== 'string' || state.guardian_name.trim() === '') {
        throw new Error('Guardian capture name is empty.');
      }
      if (
        typeof state.guardian_root_effective_alpha !== 'number'
        || !Number.isFinite(state.guardian_root_effective_alpha)
        || state.guardian_root_effective_alpha < 0.99
        || typeof state.guardian_sprite_effective_alpha !== 'number'
        || !Number.isFinite(state.guardian_sprite_effective_alpha)
        || state.guardian_sprite_effective_alpha < 0.99
      ) {
        throw new Error('Guardian live sprite is transparent.');
      }
      if (!Number.isSafeInteger(state.guardian_current_frame)
        || state.guardian_current_frame < 0) {
        throw new Error('Guardian current animation frame is invalid.');
      }
      if (typeof state.guardian_current_animation !== 'string'
        || state.guardian_current_animation.trim() === '') {
        throw new Error('Guardian current animation is empty.');
      }
      if (typeof state.guardian_frame_texture_path !== 'string'
        || !FIELD_GUARDIAN_CAPTURE_TEXTURES.has(state.guardian_frame_texture_path)) {
        throw new Error('Guardian current frame is not a field-Guardian asset.');
      }
      const guardianBanner = requirePinnedCaptureBanner(
        state, 'GUARDIAN_INTRO', 'Guardian',
      );
      const arenaLayout = assertArenaSafeCaptureLayout(state);
      const guardianComposition = assertGuardianCaptureComposition(
        state, arenaLayout.viewport_rect,
      );
      return {
        ...common,
        ...arenaLayout,
        ...guardianComposition,
        ...guardianBanner,
        scene: requireStoreCaptureValue(
          state,
          'scene',
          'arena',
          'Guardian capture is not the actual arena scene.',
        ),
        over: requireStoreCaptureValue(
          state, 'over', false, 'A finished combat cannot be used as Guardian proof.',
        ),
        level: requireStoreCaptureValue(
          state, 'level', 20, 'Guardian capture is not the Lv20 preset.',
        ),
        cycle: requireStoreCaptureValue(
          state, 'cycle', 3, 'Guardian capture is not the cycle-3 preset.',
        ),
        zone_index: requireStoreCaptureValue(
          state,
          'zone_index',
          2,
          'Guardian capture is not on the third field biome.',
        ),
        terrain_path: requireStoreCaptureValue(
          state,
          'terrain_path',
          'res://resources/rooms/field.tres',
          'Guardian capture biome resource is not moonlit field.',
        ),
        terrain_encounter: requireStoreCaptureValue(
          state,
          'terrain_encounter',
          1,
          'Guardian capture biome rule is not field crossfire.',
        ),
        world_key: requireStoreCaptureValue(
          state, 'world_key', 'WORLD_FIELD', 'Guardian capture biome cycle key is not field.',
        ),
        time_key: requireStoreCaptureValue(
          state, 'time_key', 'TIME_DAY', 'Guardian capture time of day is not day.',
        ),
        time_tone: requireStoreCaptureArray(
          state, 'time_tone', DAY_TONE, 'Guardian capture day-tone contract differs.',
        ),
        applied_time_tone: requireStoreCaptureArray(
          state, 'applied_time_tone', DAY_TONE, 'Day tone was not applied to the Guardian background.',
        ),
        time_tone_applied: requireStoreCaptureValue(
          state, 'time_tone_applied', true, 'Guardian background tone differs from the time of day.',
        ),
        lit_beacons: requireStoreCaptureValue(
          state,
          'lit_beacons',
          3,
          'Not all three beacons are lit in the Guardian capture.',
        ),
        total_beacons: requireStoreCaptureValue(
          state,
          'total_beacons',
          3,
          'Guardian capture total beacon count is not 3.',
        ),
        transitioning: requireStoreCaptureValue(
          state,
          'transitioning',
          false,
          'A screen mid biome transition cannot be used as Guardian proof.',
        ),
        escape_active: requireStoreCaptureValue(
          state,
          'escape_active',
          false,
          'A screen with the escape gate open cannot be used as Guardian proof.',
        ),
        guardian_alive: requireStoreCaptureValue(
          state,
          'guardian_alive',
          true,
          'There is no living Guardian.',
        ),
        guardian_visible: requireStoreCaptureValue(
          state,
          'guardian_visible',
          true,
          'Guardian body is not visible.',
        ),
        guardian_on_screen: requireStoreCaptureValue(
          state,
          'guardian_on_screen',
          true,
          'Guardian is not on screen.',
        ),
        hud_boss_visible: requireStoreCaptureValue(
          state,
          'hud_boss_visible',
          true,
          'Guardian boss HUD is not visible.',
        ),
        guardian_name: state.guardian_name,
        guardian_kind_path: requireStoreCaptureMember(
          state,
          'guardian_kind_path',
          FIELD_GUARDIAN_CAPTURE_KINDS,
          'Guardian capture body is not the field Guardian.',
        ),
        guardian_visual_node_present: requireStoreCaptureValue(
          state, 'guardian_visual_node_present', true, 'Guardian AnimatedSprite2D physical node is missing.',
        ),
        guardian_visual_node_class: requireStoreCaptureValue(
          state, 'guardian_visual_node_class', 'AnimatedSprite2D',
          'Guardian live node is not an AnimatedSprite2D.',
        ),
        guardian_root_visible_in_tree: requireStoreCaptureValue(
          state, 'guardian_root_visible_in_tree', true, 'Guardian root is not visible in the live tree.',
        ),
        guardian_sprite_visible_in_tree: requireStoreCaptureValue(
          state, 'guardian_sprite_visible_in_tree', true, 'Guardian sprite is not visible in the live tree.',
        ),
        guardian_root_effective_alpha: state.guardian_root_effective_alpha,
        guardian_sprite_effective_alpha: state.guardian_sprite_effective_alpha,
        guardian_root_opaque: requireStoreCaptureValue(
          state, 'guardian_root_opaque', true, 'Guardian root is transparent.',
        ),
        guardian_sprite_opaque: requireStoreCaptureValue(
          state, 'guardian_sprite_opaque', true, 'Guardian sprite is transparent.',
        ),
        guardian_current_animation: state.guardian_current_animation,
        guardian_current_frame: state.guardian_current_frame,
        guardian_frame_texture_present: requireStoreCaptureValue(
          state, 'guardian_frame_texture_present', true, 'Guardian current frame texture is missing.',
        ),
        guardian_frame_texture_path: state.guardian_frame_texture_path,
        guardian_frame_texture_matches_field: requireStoreCaptureValue(
          state, 'guardian_frame_texture_matches_field', true,
          'Guardian current frame differs from the field Guardian asset.',
        ),
        guardian_draw_rect_positive: requireStoreCaptureValue(
          state, 'guardian_draw_rect_positive', true, 'Guardian sprite draw rect is empty.',
        ),
        guardian_draw_rect_intersects_viewport: requireStoreCaptureValue(
          state, 'guardian_draw_rect_intersects_viewport', true,
          'Guardian sprite draw rect is off screen.',
        ),
        guardian_visual_ready: requireStoreCaptureValue(
          state, 'guardian_visual_ready', true, 'Guardian physical render proof is not complete.',
        ),
        ready: requireStoreCaptureValue(
          state,
          'ready',
          true,
          'Guardian scene is not capture-ready.',
        ),
      };
    }
    case 'iap_review': {
      const productId = requireStoreCaptureValue(
        state,
        'product_id',
        expected.productId,
        'IAP panel shown product ID differs from expected.',
      );
      const isArtworkProduct = productId.endsWith('.supporter')
        || productId.endsWith('.lantern_colors');
      const isConsumableProduct = productId.endsWith('.continue_coin')
        || productId.endsWith('.continue_coin_5')
        || productId.endsWith('.continue_coin_10');
      const heroVisual = IAP_HERO_VISUAL_BY_PRODUCT[productId];
      if (!isArtworkProduct && !isConsumableProduct && heroVisual === undefined) {
        throw new Error('IAP hero SKU resource contract is missing.');
      }
      const visual = isConsumableProduct
        ? {
            portrait_visible: requireStoreCaptureValue(
              state,
              'portrait_visible',
              false,
              'IAP coin card shows an unexpected hero portrait.',
            ),
            artwork_visible: requireStoreCaptureValue(
              state,
              'artwork_visible',
              false,
              'IAP coin card shows unexpected non-consumable artwork.',
            ),
            artwork_node_present: requireStoreCaptureValue(
              state,
              'artwork_node_present',
              false,
              'IAP coin card has an unexpected Artwork node.',
            ),
          }
        : isArtworkProduct
        ? {
            artwork_visible: requireStoreCaptureValue(
              state,
              'artwork_visible',
              true,
              'IAP non-hero product artwork is not visible.',
            ),
            artwork_kind: requireStoreCaptureValue(
              state,
              'artwork_kind',
              productId.endsWith('.supporter')
                ? 'supporter_app_icon'
                : 'lantern_palette_flames',
              'IAP non-hero product artwork kind differs from the product.',
            ),
            artwork_item_count: requireStoreCaptureValue(
              state,
              'artwork_item_count',
              productId.endsWith('.supporter') ? 1 : 4,
              'IAP non-hero product artwork item count is invalid.',
            ),
            artwork_node_present: requireStoreCaptureValue(
              state,
              'artwork_node_present',
              true,
              'IAP non-hero product live Artwork node is missing.',
            ),
            artwork_expected_kind: requireStoreCaptureValue(
              state,
              'artwork_expected_kind',
              productId.endsWith('.supporter')
                ? 'supporter_app_icon'
                : 'lantern_palette_flames',
              'IAP non-hero product expected artwork kind is invalid.',
            ),
            artwork_expected_item_count: requireStoreCaptureValue(
              state,
              'artwork_expected_item_count',
              productId.endsWith('.supporter') ? 1 : 4,
              'IAP non-hero product expected artwork item count is invalid.',
            ),
            artwork_textures_ready: requireStoreCaptureValue(
              state,
              'artwork_textures_ready',
              true,
              'IAP non-hero product live texture is not ready.',
            ),
            artwork_visible_rect_ready: requireStoreCaptureValue(
              state,
              'artwork_visible_rect_ready',
              true,
              'IAP non-hero product texture visible area is missing.',
            ),
            artwork_opaque: requireStoreCaptureValue(
              state, 'artwork_opaque', true, 'IAP non-hero product artwork is transparent.',
            ),
            artwork_product_specific: requireStoreCaptureValue(
              state,
              'artwork_product_specific',
              true,
              'IAP non-hero product artwork is not exclusive to that product.',
            ),
          }
        : {
            portrait_visible: requireStoreCaptureValue(
              state,
              'portrait_visible',
              true,
              'IAP hero product portrait is not visible.',
            ),
            portrait_visible_rect_ready: requireStoreCaptureValue(
              state, 'portrait_visible_rect_ready', true,
              'IAP hero product portrait live visible area is missing.',
            ),
            portrait_opaque: requireStoreCaptureValue(
              state, 'portrait_opaque', true, 'IAP hero product portrait is transparent.',
            ),
            hero_resource_path: requireStoreCaptureValue(
              state, 'hero_resource_path', heroVisual.hero,
              'IAP hero SKU is linked to the wrong hero resource.',
            ),
            hero_expected_resource_path: requireStoreCaptureValue(
              state, 'hero_expected_resource_path', heroVisual.hero,
              'IAP hero SKU expected resource contract differs.',
            ),
            portrait_resource_path: requireStoreCaptureValue(
              state, 'portrait_resource_path', heroVisual.portrait,
              'IAP hero SKU is linked to the wrong portrait resource.',
            ),
            portrait_expected_resource_path: requireStoreCaptureValue(
              state, 'portrait_expected_resource_path', heroVisual.portrait,
              'IAP hero SKU expected portrait contract differs.',
            ),
            portrait_product_specific: requireStoreCaptureValue(
              state, 'portrait_product_specific', true,
              'IAP hero SKU portrait is not exclusive to that product.',
            ),
          };
      const reviewTitle = IAP_REVIEW_TITLE_BY_PRODUCT[productId];
      if (typeof reviewTitle !== 'string'
        || state.title_text !== reviewTitle
        || state.title_expected_text !== reviewTitle) {
        throw new Error('IAP product name differs from the Korean submission product-name contract.');
      }
      if (state.price_text !== IAP_REVIEW_FALLBACK_PRICE_TEXT
        || state.price_expected_text !== IAP_REVIEW_FALLBACK_PRICE_TEXT) {
        throw new Error('IAP price differs from the direct-distribution fallback contract.');
      }
      if (state.review_status_text !== IAP_REVIEW_FALLBACK_STATUS_TEXT
        || state.review_status_expected_text !== IAP_REVIEW_FALLBACK_STATUS_TEXT) {
        throw new Error('IAP direct-distribution help copy is invalid.');
      }
      if (state.action_text !== IAP_REVIEW_BUY_TEXT
        || state.action_expected_text !== IAP_REVIEW_BUY_TEXT) {
        throw new Error('IAP buy-button copy differs from the submission contract.');
      }
      if (state.restore_text !== IAP_REVIEW_RESTORE_TEXT
        || state.restore_expected_text !== IAP_REVIEW_RESTORE_TEXT) {
        throw new Error('IAP restore-button copy differs from the submission contract.');
      }
      return {
        ...common,
        ...assertSafeCaptureLayout(state, {
          viewportField: 'screen_rect',
          readyFields: ['iap_safe_ui_ready'],
          controls: [
            {
              rectField: 'shop_frame_rect',
              insideField: 'shop_frame_inside_safe_area',
            },
            {
              rectField: 'card_rect',
              insideField: 'card_inside_safe_area',
            },
          ],
        }),
        shop_visible: requireStoreCaptureValue(
          state,
          'shop_visible',
          true,
          'IAP store panel is not visible.',
        ),
        shop_opaque: requireStoreCaptureValue(
          state, 'shop_opaque', true, 'IAP store panel open transition has not finished.',
        ),
        shop_drawn_after_open: requireStoreCaptureValue(
          state, 'shop_drawn_after_open', true, 'No render frame after opening the IAP store.',
        ),
        shop_frame_inside_viewport: requireStoreCaptureValue(
          state, 'shop_frame_inside_viewport', true, 'IAP store frame is outside the live screen.',
        ),
        preview_visible: requireStoreCaptureValue(
          state,
          'preview_visible',
          false,
          'A detail panel is open over the IAP product card.',
        ),
        product_id: productId,
        card_visible: requireStoreCaptureValue(
          state,
          'card_visible',
          true,
          'IAP product card is not visible.',
        ),
        card_visible_rect_ready: requireStoreCaptureValue(
          state, 'card_visible_rect_ready', true, 'IAP product card live visible area is missing.',
        ),
        card_opaque: requireStoreCaptureValue(
          state, 'card_opaque', true, 'IAP product card is transparent.',
        ),
        title_visible: requireStoreCaptureValue(
          state,
          'title_visible',
          true,
          'IAP product name is not visible.',
        ),
        title_visible_rect_ready: requireStoreCaptureValue(
          state, 'title_visible_rect_ready', true, 'IAP product name live visible area is missing.',
        ),
        title_opaque: requireStoreCaptureValue(
          state, 'title_opaque', true, 'IAP product name is transparent.',
        ),
        title_text: state.title_text,
        title_expected_text: state.title_expected_text,
        title_text_nonempty: requireStoreCaptureValue(
          state, 'title_text_nonempty', true, 'IAP product name copy is empty.',
        ),
        title_copy_valid: requireStoreCaptureValue(
          state, 'title_copy_valid', true, 'IAP product name differs from the current product.',
        ),
        title_characters_visible: requireStoreCaptureValue(
          state, 'title_characters_visible', true, 'IAP product name glyphs are hidden.',
        ),
        title_font_size_positive: requireStoreCaptureValue(
          state, 'title_font_size_positive', true, 'IAP product name font size is 0.',
        ),
        title_font_alpha_readable: requireStoreCaptureValue(
          state, 'title_font_alpha_readable', true, 'IAP product name glyphs are transparent.',
        ),
        title_rendered_text_ready: requireStoreCaptureValue(
          state, 'title_rendered_text_ready', true, 'IAP product name is not actually drawn.',
        ),
        review_fallback_verified: requireStoreCaptureValue(
          state, 'review_fallback_verified', true,
          'IAP direct-distribution fallback state was not proven.',
        ),
        review_status_visible: requireStoreCaptureValue(
          state, 'review_status_visible', true,
          'IAP direct-distribution help copy is not visible.',
        ),
        review_status_text: state.review_status_text,
        review_status_expected_text: state.review_status_expected_text,
        review_status_copy_valid: requireStoreCaptureValue(
          state, 'review_status_copy_valid', true,
          'IAP direct-distribution help copy differs from the current state.',
        ),
        review_status_rendered_text_ready: requireStoreCaptureValue(
          state, 'review_status_rendered_text_ready', true,
          'IAP direct-distribution help copy is not actually drawn.',
        ),
        review_status_visible_rect_ready: requireStoreCaptureValue(
          state, 'review_status_visible_rect_ready', true,
          'IAP direct-distribution help copy live visible area is missing.',
        ),
        review_status_opaque: requireStoreCaptureValue(
          state, 'review_status_opaque', true,
          'IAP direct-distribution help copy is transparent.',
        ),
        price_visible: requireStoreCaptureValue(
          state, 'price_visible', true, 'IAP direct-distribution price fallback is not visible.',
        ),
        price_text: state.price_text,
        price_expected_text: state.price_expected_text,
        price_copy_valid: requireStoreCaptureValue(
          state, 'price_copy_valid', true,
          'IAP direct-distribution price fallback differs from the current state.',
        ),
        price_rendered_text_ready: requireStoreCaptureValue(
          state, 'price_rendered_text_ready', true,
          'IAP direct-distribution price fallback is not actually drawn.',
        ),
        price_visible_rect_ready: requireStoreCaptureValue(
          state, 'price_visible_rect_ready', true,
          'IAP direct-distribution price fallback live visible area is missing.',
        ),
        price_opaque: requireStoreCaptureValue(
          state, 'price_opaque', true, 'IAP direct-distribution price fallback is transparent.',
        ),
        ...visual,
        action_visible: requireStoreCaptureValue(
          state,
          'action_visible',
          true,
          'IAP buy action button is not visible.',
        ),
        action_visible_rect_ready: requireStoreCaptureValue(
          state, 'action_visible_rect_ready', true, 'IAP buy button live visible area is missing.',
        ),
        action_opaque: requireStoreCaptureValue(
          state, 'action_opaque', true, 'IAP buy button is transparent.',
        ),
        action_enabled: requireStoreCaptureValue(
          state, 'action_enabled', false, 'IAP direct-distribution buy button is enabled.',
        ),
        action_text: state.action_text,
        action_expected_text: state.action_expected_text,
        action_text_nonempty: requireStoreCaptureValue(
          state, 'action_text_nonempty', true, 'IAP buy button copy is empty.',
        ),
        action_copy_valid: requireStoreCaptureValue(
          state, 'action_copy_valid', true, 'IAP buy button copy differs from the current state.',
        ),
        action_font_size_positive: requireStoreCaptureValue(
          state, 'action_font_size_positive', true, 'IAP buy button font size is 0.',
        ),
        action_font_alpha_readable: requireStoreCaptureValue(
          state, 'action_font_alpha_readable', true, 'IAP buy button glyphs are transparent.',
        ),
        action_rendered_text_ready: requireStoreCaptureValue(
          state, 'action_rendered_text_ready', true, 'IAP buy button glyphs are not actually drawn.',
        ),
        restore_visible: requireStoreCaptureValue(
          state,
          'restore_visible',
          true,
          'IAP purchase-restore button is not visible.',
        ),
        restore_visible_rect_ready: requireStoreCaptureValue(
          state, 'restore_visible_rect_ready', true, 'IAP restore button live visible area is missing.',
        ),
        restore_opaque: requireStoreCaptureValue(
          state, 'restore_opaque', true, 'IAP restore button is transparent.',
        ),
        restore_enabled: requireStoreCaptureValue(
          state, 'restore_enabled', false, 'IAP direct-distribution restore button is enabled.',
        ),
        restore_text: state.restore_text,
        restore_expected_text: state.restore_expected_text,
        restore_text_nonempty: requireStoreCaptureValue(
          state, 'restore_text_nonempty', true, 'IAP restore button copy is empty.',
        ),
        restore_copy_valid: requireStoreCaptureValue(
          state, 'restore_copy_valid', true, 'IAP restore button copy differs from the current state.',
        ),
        restore_font_size_positive: requireStoreCaptureValue(
          state, 'restore_font_size_positive', true, 'IAP restore button font size is 0.',
        ),
        restore_font_alpha_readable: requireStoreCaptureValue(
          state, 'restore_font_alpha_readable', true, 'IAP restore button glyphs are transparent.',
        ),
        restore_rendered_text_ready: requireStoreCaptureValue(
          state, 'restore_rendered_text_ready', true, 'IAP restore button glyphs are not actually drawn.',
        ),
        card_fully_inside_viewport: requireStoreCaptureValue(
          state,
          'card_fully_inside_viewport',
          true,
          'IAP product card is not fully inside the screen.',
        ),
        card_inside_screen: requireStoreCaptureValue(
          state, 'card_inside_screen', true, 'IAP product card is outside the live screen.',
        ),
      };
    }
    default:
      throw new TypeError('Unsupported store capture state kind.');
  }
}

export function assertStableStoreCaptureState(before, after, expected) {
  const normalizedBefore = assertStoreCaptureState(before, expected);
  const normalizedAfter = assertStoreCaptureState(after, expected);
  if (normalizedBefore.nonce !== normalizedAfter.nonce) {
    throw new Error('Store capture nonce changed across the screenshot.');
  }
  if (normalizedAfter.observation <= normalizedBefore.observation) {
    throw new Error('No new runtime observation sample after the screenshot.');
  }
  const {
    nonce: _beforeNonce,
    observation: _beforeObservation,
    ...comparableBefore
  } = normalizedBefore;
  const {
    nonce: _afterNonce,
    observation: _afterObservation,
    ...comparableAfter
  } = normalizedAfter;
  // Active volley node count and above-threshold alpha can naturally differ across
  // physics frames on either side of the screenshot. Both samples already passed the strict
  // visual threshold, so exclude only these numbers from equality comparison.
  const stableBefore = { ...comparableBefore };
  const stableAfter = { ...comparableAfter };
  if (expected.kind === 'moonlight_barrage') {
    delete stableBefore.missile_visual_probe_count;
    delete stableAfter.missile_visual_probe_count;
    delete stableBefore.missile_effective_alpha;
    delete stableAfter.missile_effective_alpha;
    delete stableBefore.visible_enemy_sprite_count;
    delete stableAfter.visible_enemy_sprite_count;
  }
  if (expected.kind === 'field_guardian') {
    for (const field of [
      'guardian_root_effective_alpha',
      'guardian_sprite_effective_alpha',
      'guardian_current_animation',
      'guardian_current_frame',
      'guardian_frame_texture_path',
      'guardian_draw_rect',
      'guardian_player_canvas_distance',
    ]) {
      delete stableBefore[field];
      delete stableAfter[field];
    }
  }
  if (JSON.stringify(stableBefore) !== JSON.stringify(stableAfter)) {
    const changedFields = Object.keys(stableBefore).filter(
      (field) => JSON.stringify(stableBefore[field])
        !== JSON.stringify(stableAfter[field]),
    );
    const changes = Object.fromEntries(changedFields.map((field) => [
      field,
      {
        before: stableBefore[field],
        after: stableAfter[field],
      },
    ]));
    throw new Error(
      `Store capture state changed across the screenshot: ${JSON.stringify(changes)}`,
    );
  }
  return {
    ...normalizedBefore,
    observation_after: normalizedAfter.observation,
  };
}

/**
 * Normalize the debug game's first-party proof that the exact recovery banner
 * is pinned while an ejected missile core exists.  The screenshot automation
 * deliberately trusts no timeout or pixel heuristic for this state.
 */
export function assertMissileCoreCaptureState(
  state,
  { gameLocale } = {},
) {
  if (!isRecord(state) || state.schema !== 1) {
    throw new TypeError('Missile-core capture state schema is invalid.');
  }
  if (state.kind !== 'missile_core_recovery') {
    throw new Error('Missile-core capture state kind is invalid.');
  }
  requireStoreCaptureValue(
    state, 'scene', 'arena', 'Missile-core capture is not the actual arena scene.',
  );
  requireStoreCaptureValue(
    state, 'over', false, 'A finished combat cannot be used as missile-core proof.',
  );
  requireStoreCaptureValue(
    state, 'level', 10, 'Missile-core capture is not the Lv10 preset.',
  );
  requireStoreCaptureValue(
    state, 'cycle', 1, 'Missile-core capture is not cycle 1.',
  );
  requireStoreCaptureValue(
    state, 'zone_index', 0, 'Missile-core capture is not the first biome.',
  );
  requireStoreCaptureValue(
    state,
    'terrain_path',
    'res://resources/rooms/forest.tres',
    'Missile-core capture biome is not night forest.',
  );
  requireStoreCaptureValue(
    state, 'world_key', 'WORLD_FOREST', 'Missile-core biome cycle key is not forest.',
  );
  requireStoreCaptureValue(
    state, 'lit_beacons', 0, 'Missile-core capture is not unlit night.',
  );
  requireStoreCaptureValue(
    state, 'transitioning', false, 'Missile-core capture is mid biome transition.',
  );
  requireStoreCaptureValue(
    state, 'escape_active', false, 'Missile-core capture has the escape gate open.',
  );
  requireStoreCaptureValue(
    state, 'time_key', 'TIME_NIGHT', 'Missile-core capture time of day is not night.',
  );
  requireStoreCaptureArray(
    state, 'time_tone', NIGHT_TONE, 'Missile-core capture night-tone contract differs.',
  );
  requireStoreCaptureArray(
    state, 'applied_time_tone', NIGHT_TONE, 'Night tone was not applied to the missile-core background.',
  );
  requireStoreCaptureValue(
    state, 'time_tone_applied', true, 'Missile-core background tone differs from the time of day.',
  );
  if (
    typeof gameLocale !== 'string'
    || gameLocale.trim() === ''
    || state.game_locale !== gameLocale
  ) {
    throw new Error('Missile-core capture state game locale differs.');
  }
  if (state.banner_key !== 'MISSILE_DROPPED') {
    throw new Error('Missile-core capture banner key is invalid.');
  }
  if (
    typeof state.expected_banner_text !== 'string'
    || state.expected_banner_text.trim() === ''
    || typeof state.actual_banner_text !== 'string'
    || state.actual_banner_text !== state.expected_banner_text
  ) {
    throw new Error('Missile-core capture live banner copy differs from the translation expected value.');
  }
  if (state.banner_visible !== true || state.banner_locked !== true) {
    throw new Error('Missile-core capture banner is not in a visible frozen state.');
  }
  if (
    !Number.isSafeInteger(state.missile_power_before)
    || !Number.isSafeInteger(state.missile_power_after)
    || state.missile_power_before < 1
    || state.missile_power_after < 0
    || state.missile_power_before !== state.missile_power_after + 1
  ) {
    throw new Error('No proof that missile power dropped by exactly one step.');
  }
  if (
    !Number.isSafeInteger(state.ejected_cores_outstanding)
    || state.ejected_cores_outstanding < 1
  ) {
    throw new Error('No proof that a stray missile core to reclaim exists.');
  }
  if (state.core_capture_paused !== true) {
    throw new Error('The stray missile core was not paused during capture.');
  }
  if (state.ejected_core_count !== 1) {
    throw new Error('Live stray missile cores to capture is not exactly one.');
  }
  if (state.core_visible_in_tree !== true) {
    throw new Error('Stray missile core is not visible in the live tree.');
  }
  if (
    typeof state.core_effective_alpha !== 'number'
    || !Number.isFinite(state.core_effective_alpha)
    || state.core_effective_alpha < 0.99
  ) {
    throw new Error('Stray missile core is transparent.');
  }
  requireStoreCaptureValue(
    state, 'core_opaque', true, 'Stray missile core is not opaque.',
  );
  requireStoreCaptureValue(
    state, 'core_onscreen', true, 'Stray missile core is not inside the live screen.',
  );
  requireStoreCaptureValue(
    state,
    'core_texture_path',
    'res://assets/custom/items/pickups/power_gem.png',
    'Stray missile core is not the power_gem-only texture.',
  );
  requireStoreCaptureValue(
    state, 'core_texture_matches', true, 'Stray missile core texture identity differs.',
  );
  requireStoreCaptureValue(
    state,
    'core_visible_draw_rect_positive',
    true,
    'Stray missile core Sprite live visible draw rect is missing.',
  );
  return {
    schema: 1,
    kind: 'missile_core_recovery',
    scene: 'arena',
    over: false,
    game_locale: state.game_locale,
    level: 10,
    cycle: 1,
    zone_index: 0,
    terrain_path: 'res://resources/rooms/forest.tres',
    world_key: 'WORLD_FOREST',
    lit_beacons: 0,
    transitioning: false,
    escape_active: false,
    time_key: 'TIME_NIGHT',
    time_tone: [...NIGHT_TONE],
    applied_time_tone: [...NIGHT_TONE],
    time_tone_applied: true,
    banner_key: 'MISSILE_DROPPED',
    expected_banner_text: state.expected_banner_text,
    actual_banner_text: state.actual_banner_text,
    banner_visible: true,
    banner_locked: true,
    missile_power_before: state.missile_power_before,
    missile_power_after: state.missile_power_after,
    ejected_cores_outstanding: state.ejected_cores_outstanding,
    core_capture_paused: true,
    ejected_core_count: 1,
    core_visible_in_tree: true,
    core_effective_alpha: state.core_effective_alpha,
    core_opaque: true,
    core_onscreen: true,
    core_texture_path: 'res://assets/custom/items/pickups/power_gem.png',
    core_texture_matches: true,
    core_visible_draw_rect_positive: true,
  };
}

export function assertStableMissileCoreCaptureState(
  before,
  after,
  expected,
) {
  const normalizedBefore = assertMissileCoreCaptureState(before, expected);
  const normalizedAfter = assertMissileCoreCaptureState(after, expected);
  if (JSON.stringify(normalizedBefore) !== JSON.stringify(normalizedAfter)) {
    throw new Error('Missile-core capture state changed across the screenshot.');
  }
  return normalizedBefore;
}

export function assertMissileCoreCaptureProofs(captures, expectedLocales) {
  if (!Array.isArray(captures) || !Array.isArray(expectedLocales)) {
    throw new TypeError('Capture list and expected locale list are required.');
  }
  const localeKeys = new Set();
  for (const locale of expectedLocales) {
    if (
      !isRecord(locale)
      || typeof locale.asset !== 'string'
      || locale.asset.trim() === ''
      || typeof locale.game !== 'string'
      || locale.game.trim() === ''
      || localeKeys.has(locale.asset)
    ) {
      throw new TypeError('Missile-core capture expected locale is invalid.');
    }
    localeKeys.add(locale.asset);
  }

  const coreCaptures = captures.filter(
    (capture) => isRecord(capture)
      && typeof capture.source === 'string'
      && capture.source.endsWith('/03-missile-core-drop.png'),
  );
  if (coreCaptures.length !== expectedLocales.length) {
    throw new Error('Per-locale missile-core reclaim capture proof count differs.');
  }

  for (const locale of expectedLocales) {
    const matching = coreCaptures.filter(
      (capture) => capture.asset_locale === locale.asset,
    );
    if (
      matching.length !== 1
      || matching[0].game_locale !== locale.game
      || matching[0].kind !== 'combat'
    ) {
      throw new Error(`${locale.asset} missile-core reclaim capture is invalid.`);
    }
    const guard = matching[0].capture_guard;
    if (!isRecord(guard) || guard.asset_locale !== locale.asset) {
      throw new Error(`${locale.asset} missile-core capture locale proof is missing.`);
    }
    assertMissileCoreCaptureState(guard, { gameLocale: locale.game });
  }
  return true;
}

function assertStoreCaptureProof(
  captures,
  {
    source,
    assetLocale,
    gameLocale,
    captureKind,
    stateExpected,
    productId = '',
  },
) {
  const matching = captures.filter(
    (capture) => isRecord(capture) && capture.source === source,
  );
  if (matching.length !== 1) {
    throw new Error(`${source} store-state proofs are not exactly 1 image.`);
  }
  const capture = matching[0];
  if (
    capture.asset_locale !== assetLocale
    || capture.game_locale !== gameLocale
    || capture.kind !== captureKind
    || (productId !== '' && capture.product_id !== productId)
  ) {
    throw new Error(`${source} store capture metadata is invalid.`);
  }
  if (!isRecord(capture.state_guard)) {
    throw new Error(`${source} has no game-runtime state_guard.`);
  }
  const normalized = assertStoreCaptureState(capture.state_guard, stateExpected);
  if (
    !Number.isSafeInteger(capture.state_guard.observation_after)
    || capture.state_guard.observation_after <= normalized.observation
  ) {
    throw new Error(`${source} has no new runtime observation proof after screencap.`);
  }
}

/**
 * Require first-party semantic state for every screenshot whose meaning cannot
 * be proven by path, locale, or unique image bytes alone.
 */
export function assertStoreCaptureProofs(captures, locales, iapProducts) {
  if (!Array.isArray(captures) || !Array.isArray(locales) || !Array.isArray(iapProducts)) {
    throw new TypeError('Capture list and locale/IAP product contracts are required.');
  }
  if (locales.length === 0) {
    throw new TypeError('Store capture expected locale is empty.');
  }
  const localeAssets = new Set();
  const localeGames = new Set();
  for (const locale of locales) {
    if (
      !isRecord(locale)
      || typeof locale.asset !== 'string'
      || locale.asset.trim() === ''
      || typeof locale.game !== 'string'
      || locale.game.trim() === ''
      || typeof locale.heroPath !== 'string'
      || locale.heroPath.trim() === ''
      || localeAssets.has(locale.asset)
      || localeGames.has(locale.game)
    ) {
      throw new TypeError('Store capture expected locale contract is invalid.');
    }
    localeAssets.add(locale.asset);
    localeGames.add(locale.game);
  }
  if (iapProducts.length !== Object.keys(IAP_REVIEW_OUTPUT_BY_PRODUCT).length) {
    throw new TypeError(
      `IAP review state proofs need ${Object.keys(IAP_REVIEW_OUTPUT_BY_PRODUCT).length} sale products.`,
    );
  }
  const productIds = new Set();
  const productOutputs = new Set();
  for (const product of iapProducts) {
    if (
      !isRecord(product)
      || typeof product.product_id !== 'string'
      || product.product_id.trim() === ''
      || typeof product.output !== 'string'
      || product.output.trim() === ''
      || product.output.includes('/')
      || product.output.includes('\\')
      || !product.output.endsWith('.png')
      || IAP_REVIEW_OUTPUT_BY_PRODUCT[product.product_id] !== product.output
      || productIds.has(product.product_id)
      || productOutputs.has(product.output)
    ) {
      throw new TypeError('IAP review state proof product contract is invalid.');
    }
    productIds.add(product.product_id);
    productOutputs.add(product.output);
  }

  for (const locale of locales) {
    const root = `builds/shots/store-localized/${locale.asset}`;
    assertStoreCaptureProof(captures, {
      source: `${root}/04-title.png`,
      assetLocale: locale.asset,
      gameLocale: locale.game,
      captureKind: 'title',
      stateExpected: {
        kind: 'title',
        gameLocale: locale.game,
        directDistribution: true,
      },
    });
    assertStoreCaptureProof(captures, {
      source: `${root}/01-moonlight-barrage.png`,
      assetLocale: locale.asset,
      gameLocale: locale.game,
      captureKind: 'combat',
      stateExpected: { kind: 'moonlight_barrage', gameLocale: locale.game },
    });
    assertStoreCaptureProof(captures, {
      source: `${root}/05-moonlit-shrine.png`,
      assetLocale: locale.asset,
      gameLocale: locale.game,
      captureKind: 'shrine',
      stateExpected: { kind: 'shrine', gameLocale: locale.game },
    });
    assertStoreCaptureProof(captures, {
      source: `${root}/06-hero-preview.png`,
      assetLocale: locale.asset,
      gameLocale: locale.game,
      captureKind: 'hero-preview',
      stateExpected: {
        kind: 'hero_preview',
        gameLocale: locale.game,
        heroPath: locale.heroPath,
      },
    });
    assertStoreCaptureProof(captures, {
      source: `${root}/02-field-guardian.png`,
      assetLocale: locale.asset,
      gameLocale: locale.game,
      captureKind: 'combat',
      stateExpected: { kind: 'field_guardian', gameLocale: locale.game },
    });
  }

  const koreanLocales = locales.filter((locale) => locale.game === 'ko');
  if (koreanLocales.length !== 1) {
    throw new TypeError('IAP review state proofs require one Korean capture locale.');
  }
  const korean = koreanLocales[0];
  for (const product of iapProducts) {
    assertStoreCaptureProof(captures, {
      source: `builds/shots/store-localized/${korean.asset}/iap-review/${product.output}`,
      assetLocale: korean.asset,
      gameLocale: korean.game,
      captureKind: 'iap-review',
      productId: product.product_id,
      stateExpected: {
        kind: 'iap_review',
        gameLocale: korean.game,
        productId: product.product_id,
      },
    });
  }
  return true;
}
