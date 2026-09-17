import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  assertCaptureBuildAttestationCurrent,
  assertInstalledCaptureApkCurrent,
  assertMissileCoreCaptureProofs,
  assertMissileCoreCaptureState,
  assertSafeCaptureOutputPath,
  assertStableMissileCoreCaptureState,
  assertStableStoreCaptureState,
  assertStoreCaptureProofs,
  assertStoreCaptureState,
  commitCaptureArtifacts,
  captureProcessExitCode,
  foregroundSignalsShowPackage,
  launcherWaitOutputShowsExpectedActivity,
  publishCaptureDirectoryAtomically,
} from './capture-run-state.mjs';

const HASH_A = 'a'.repeat(64);
const HASH_B = 'b'.repeat(64);
const HASH_C = 'c'.repeat(64);
const NONCE_A = '1'.repeat(64);
const NONCE_B = '2'.repeat(64);
const KEEPER = 'res://resources/heroes/keeper.tres';
// Header icon is the idle crop at 2x; the large slot is the 96x96 portrait 1:1. It used to be reversed.
const KEEPER_PORTRAIT = 'res://assets/custom/actors/heroes/keeper/idle.png';
const KEEPER_BODY = 'res://assets/custom/actors/heroes/keeper/portrait.png';
const FIELD_GUARDIAN_FRAME = 'res://assets/custom/actors/guardians/field.png';
const TITLE_FOREST_SCENE = 'res://scenes/gameplay/night_forest.tscn';
const TITLE_FOREST_GROUND = 'res://assets/custom/world/terrain/forest_floor.png';
const TITLE_BEACON_SCENE = 'res://scenes/objectives/beacon.tscn';
const TITLE_BEACON_CLEARING = 'res://assets/custom/world/beacon/clearing.png';
const TITLE_COPY = {
  ko: ['달빛 봉화', '밤을 밝히는 마지막 불빛', '화면을 탭하여 시작', '설정', '제단', '순위', '상점'],
  en: ['MOONLIT BEACON', 'OUTLAST THE NIGHT', 'Tap to start', 'Settings', 'Shrine', 'Ranks', 'Store'],
  ja: ['月明かりの烽火', '夜を照らす最後の灯', '画面をタップして開始', '設定', '祭壇', '順位', 'ストア'],
  zh_CN: ['月光烽火', '照亮长夜的最后火光', '点击屏幕开始', '设置', '祭坛', '排名', '商店'],
  zh_TW: ['月光烽火', '照亮長夜的最後火光', '點擊畫面開始', '設定', '祭壇', '排名', '商店'],
};
const CAPTURE_VIEWPORT_RECT = Object.freeze([0, 0, 808, 360]);
const CAPTURE_SAFE_RECT = Object.freeze([12, 8, 784, 344]);

function titleSafeState() {
  return {
    viewport_rect: [...CAPTURE_VIEWPORT_RECT],
    safe_rect: [...CAPTURE_SAFE_RECT],
    safe_area_inside_viewport: true,
    safe_ui_ready: true,
    title_rect: [160, 60, 488, 68],
    title_inside_safe_area: true,
    subtitle_rect: [200, 134, 408, 24],
    subtitle_inside_safe_area: true,
    version_rect: [688, 330, 100, 16],
    version_inside_safe_area: true,
    tap_prompt_rect: [200, 280, 408, 26],
    tap_prompt_inside_safe_area: true,
    settings_button_rect: [718, 20, 68, 26],
    settings_button_inside_safe_area: true,
    shrine_button_rect: [718, 52, 68, 26],
    shrine_button_inside_safe_area: true,
    ladder_button_rect: [718, 84, 68, 26],
    ladder_button_inside_safe_area: true,
    store_button_rect: [718, 116, 68, 26],
    store_button_inside_safe_area: true,
  };
}

function arenaSafeState() {
  return {
    viewport_rect: [...CAPTURE_VIEWPORT_RECT],
    safe_rect: [...CAPTURE_SAFE_RECT],
    safe_area_inside_viewport: true,
    safe_ui_ready: true,
    hud_left_rect: [20, 14, 82, 100],
    hud_left_inside_safe_area: true,
    hud_right_rect: [624, 14, 164, 48],
    hud_right_inside_safe_area: true,
    pause_button_rect: [754, 44, 26, 24],
    pause_button_inside_safe_area: true,
    dash_rect: [728, 284, 52, 52],
    dash_inside_safe_area: true,
    move_stick_rect: [...CAPTURE_SAFE_RECT],
    move_stick_inside_safe_area: true,
    boss_rect: [254, 70, 300, 24],
    boss_inside_safe_area: true,
    banner_rect: [184, 104, 440, 30],
    banner_inside_safe_area: true,
  };
}

function shrineSafeState({ preview = false } = {}) {
  return {
    viewport_rect: [...CAPTURE_VIEWPORT_RECT],
    safe_rect: [...CAPTURE_SAFE_RECT],
    safe_area_inside_viewport: true,
    shrine_safe_ui_ready: true,
    shrine_frame_rect: [38, 16, 732, 328],
    shrine_frame_inside_safe_area: true,
    ...(preview ? {
      preview_safe_ui_ready: true,
      preview_frame_rect: [134, 54, 540, 252],
      preview_frame_inside_safe_area: true,
      close_rect: [330, 288, 148, 28],
      close_inside_safe_area: true,
    } : {}),
  };
}

function iapSafeState() {
  return {
    screen_rect: [...CAPTURE_VIEWPORT_RECT],
    safe_rect: [...CAPTURE_SAFE_RECT],
    safe_area_inside_viewport: true,
    iap_safe_ui_ready: true,
    shop_frame_rect: [38, 16, 732, 328],
    shop_frame_inside_safe_area: true,
    card_rect: [280, 90, 248, 180],
    card_inside_safe_area: true,
  };
}

test('store capture entry files are actually parseable by Node', () => {
  const capturePath = fileURLToPath(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
  );
  const result = spawnSync(process.execPath, ['--check', capturePath], {
    encoding: 'utf8',
  });
  assert.equal(
    result.status,
    0,
    `${result.stdout ?? ''}${result.stderr ?? ''}`,
  );
});

test('Play and App Store release CLIs parse and run help bounds', () => {
  for (const script of [
    '../prepare-play-release.mjs',
    '../app-store-release.mjs',
  ]) {
    const scriptPath = fileURLToPath(new URL(script, import.meta.url));
    for (const args of [['--check', scriptPath], [scriptPath, '--help']]) {
      const result = spawnSync(process.execPath, args, { encoding: 'utf8' });
      assert.equal(
        result.status,
        0,
        `${script} ${args.at(-1)}\n${result.stdout ?? ''}${result.stderr ?? ''}`,
      );
    }
  }
});

test('launcher wait output accepts only when the exact app Activity actually started', () => {
  const packageName = 'com.crossplatformkorea.moonlitbeacon';
  assert.equal(
    launcherWaitOutputShowsExpectedActivity(
      `Starting: Intent { cmp=${packageName}/com.godot.game.GodotAppLauncher }\n`
      + 'Status: ok\n'
      + `Activity: ${packageName}/com.godot.game.GodotApp\n`
      + 'Complete\n',
      packageName,
    ),
    true,
  );
  for (const output of [
    `Status: timeout\nActivity: ${packageName}/com.godot.game.GodotApp\n`,
    'Status: ok\nWarning: Activity not started\n',
    'Status: ok\nActivity: com.example.other/.MainActivity\n',
    `Activity: ${packageName}/com.godot.game.GodotApp\n`,
  ]) {
    assert.equal(
      launcherWaitOutputShowsExpectedActivity(output, packageName),
      false,
    );
  }
});
const HERO_PREVIEW_COPY = Object.freeze({
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
const HERO_VISUALS = Object.fromEntries(
  ['dancer', 'keeper', 'knight', 'eclipse', 'sage'].map((hero) => [
    `com.crossplatformkorea.moonlitbeacon.hero_${hero}`,
    {
      hero: `res://resources/heroes/${hero}.tres`,
      portrait: `res://assets/custom/actors/heroes/${hero}/portrait.png`,
    },
  ]),
);
const IAP_PRODUCTS = [
  ['hero_dancer', 'hero-dancer.png'],
  ['hero_keeper', 'hero-keeper.png'],
  ['hero_knight', 'hero-knight.png'],
  ['hero_eclipse', 'hero-eclipse.png'],
  ['hero_sage', 'hero-sage.png'],
  ['supporter', 'supporter.png'],
  ['lantern_colors', 'lantern-colors.png'],
  ['continue_coin', 'continue-coin.png'],
  ['continue_coin_5', 'continue-coin-5.png'],
  ['continue_coin_10', 'continue-coin-10.png'],
].map(([suffix, output]) => ({
  product_id: `com.crossplatformkorea.moonlitbeacon.${suffix}`,
  output,
}));
const IAP_REVIEW_TITLE_BY_SUFFIX = Object.freeze({
  supporter: '달빛 후원자',
  hero_dancer: '그림자 무희',
  hero_keeper: '봉화지기',
  hero_knight: '백월 기사',
  hero_eclipse: '월식 마도사',
  hero_sage: '성좌 현자',
  lantern_colors: '봉화 색상 꾸러미',
  continue_coin: '이어하기 코인',
  continue_coin_5: '이어하기 코인 5개',
  continue_coin_10: '이어하기 코인 10개',
});
const IAP_REVIEW_FALLBACK_PRICE_TEXT = '기기 스토어 전용';
const IAP_REVIEW_FALLBACK_STATUS_TEXT =
  '실제 가격과 구매는 App Store·Google Play에서 확인할 수 있습니다';
const CAPTURE_BUILD_INPUTS = [
  'package.json',
  'scripts/android-build.mjs',
  'scripts/godot.mjs',
  'scripts/lib/android-build.mjs',
  'scripts/lib/android-release-signing.mjs',
  'scripts/lib/android-tablet-evidence.mjs',
  'scripts/lib/godot-export-preflight.mjs',
  'scripts/lib/iapkit-config.mjs',
  'scripts/lib/release-environment.mjs',
  'apps/game/export_presets.cfg',
  'apps/game/android/.build_version',
  'apps/game/android/build/build.gradle',
  'apps/game/android/build/config.gradle',
  'apps/game/android/build/gradle.properties',
  'apps/game/android/build/settings.gradle',
  'apps/game/android/build/gradlew',
  'apps/game/android/build/gradle/wrapper/gradle-wrapper.jar',
  'apps/game/android/build/gradle/wrapper/gradle-wrapper.properties',
  'apps/game/android/build/libs/debug/godot-lib.template_debug.aar',
  'apps/game/android/build/res/values/themes.xml',
  'apps/game/android/build/src/debug/AndroidManifest.xml',
  'apps/game/android/build/src/main/AndroidManifest.xml',
  'apps/game/android/build/src/main/java/com/godot/game/GodotApp.java',
  'apps/game/android/build/src/release/AndroidManifest.xml',
  'apps/game/scripts/dev/store_capture_boot.gd',
  'apps/game/scripts/ui/hud.gd',
];

function missileCoreState(overrides = {}) {
  return {
    schema: 1,
    kind: 'missile_core_recovery',
    scene: 'arena',
    over: false,
    game_locale: 'ko',
    level: 10,
    cycle: 1,
    zone_index: 0,
    terrain_path: 'res://resources/rooms/forest.tres',
    world_key: 'WORLD_FOREST',
    lit_beacons: 0,
    transitioning: false,
    escape_active: false,
    time_key: 'TIME_NIGHT',
    time_tone: [1, 1, 1, 1],
    applied_time_tone: [1, 1, 1, 1],
    time_tone_applied: true,
    banner_key: 'MISSILE_DROPPED',
    expected_banner_text: '미사일 출력 8→7 · 9초 안에 회수',
    actual_banner_text: '미사일 출력 8→7 · 9초 안에 회수',
    banner_visible: true,
    banner_locked: true,
    missile_power_before: 8,
    missile_power_after: 7,
    ejected_cores_outstanding: 1,
    core_capture_paused: true,
    ejected_core_count: 1,
    core_visible_in_tree: true,
    core_effective_alpha: 1,
    core_opaque: true,
    core_onscreen: true,
    core_texture_path: 'res://assets/custom/items/pickups/power_gem.png',
    core_texture_matches: true,
    core_visible_draw_rect_positive: true,
    ...overrides,
  };
}

function storeCaptureState(kind, overrides = {}) {
  const iapProduct = overrides.product_id ?? IAP_PRODUCTS[0].product_id;
  const iapHero = HERO_VISUALS[iapProduct];
  const iapSuffix = iapProduct.split('.').at(-1);
  const iapTitle = IAP_REVIEW_TITLE_BY_SUFFIX[iapSuffix] ?? '';
  const previewLocale = overrides.game_locale ?? 'ko';
  const previewCopy = HERO_PREVIEW_COPY[previewLocale] ?? HERO_PREVIEW_COPY.ko;
  const previewStateSourceKey = 'HERO_PREVIEW_IAP_LOCKED';
  const previewStateText = previewCopy.states[previewStateSourceKey];
  const directDistribution = overrides.direct_distribution ?? true;
  const storefrontEnabled = !directDistribution;
  const common = {
    schema: 1,
    nonce: NONCE_A,
    observation: 1,
    kind,
    game_locale: 'ko',
  };
  const states = {
    title: {
      ...titleSafeState(),
      scene: 'title',
      ready: true,
      screen_visible: true,
      title_visible: true,
      subtitle_visible: true,
      title_source_key: 'TITLE_NAME',
      subtitle_source_key: 'TITLE_SUBTITLE',
      title_auto_translate: true,
      subtitle_auto_translate: true,
      title_translation_text: TITLE_COPY[overrides.game_locale ?? 'ko']?.[0] ?? '달빛 봉화',
      subtitle_translation_text: TITLE_COPY[overrides.game_locale ?? 'ko']?.[1]
        ?? '밤을 밝히는 마지막 불빛',
      title_text_nonempty: true,
      title_characters_visible: true,
      title_font_size_positive: true,
      title_font_alpha_readable: true,
      title_rendered_text_ready: true,
      subtitle_text_nonempty: true,
      subtitle_characters_visible: true,
      subtitle_font_size_positive: true,
      subtitle_font_alpha_readable: true,
      subtitle_rendered_text_ready: true,
      title_inside_viewport: true,
      subtitle_inside_viewport: true,
      title_opaque: true,
      subtitle_opaque: true,
      version_visible: true,
      version_text: 'v1.0.1',
      version_text_nonempty: true,
      version_characters_visible: true,
      version_font_size_positive: true,
      version_font_alpha_readable: true,
      version_rendered_text_ready: true,
      version_inside_viewport: true,
      version_opaque: true,
      tap_prompt_visible: true,
      tap_prompt_source_key: 'TAP_TO_START',
      tap_prompt_auto_translate: true,
      tap_prompt_translation_text: TITLE_COPY[overrides.game_locale ?? 'ko']?.[2]
        ?? '화면을 탭하여 시작',
      tap_prompt_text_nonempty: true,
      tap_prompt_characters_visible: true,
      tap_prompt_font_size_positive: true,
      tap_prompt_font_alpha_readable: true,
      tap_prompt_rendered_text_ready: true,
      tap_prompt_inside_viewport: true,
      tap_prompt_readable_alpha: true,
      tap_prompt_effective_alpha: 1,
      tap_prompt_full_alpha: true,
      tap_prompt_blink_stopped: true,
      tap_prompt_modulate_white: true,
      tap_prompt_capture_locked: true,
      settings_button_visible: true,
      settings_button_enabled: true,
      settings_button_source_key: 'SETTINGS_TITLE',
      settings_button_auto_translate: true,
      settings_button_translation_text: TITLE_COPY[overrides.game_locale ?? 'ko']?.[3] ?? '설정',
      settings_button_inside_viewport: true,
      settings_button_copy_valid: true,
      settings_button_text_nonempty: true,
      settings_button_font_size_positive: true,
      settings_button_font_alpha_readable: true,
      settings_button_rendered_text_ready: true,
      settings_button_opaque: true,
      shrine_button_visible: true,
      shrine_button_enabled: true,
      shrine_button_source_key: 'SHRINE_OPEN',
      shrine_button_auto_translate: true,
      shrine_button_translation_text: TITLE_COPY[overrides.game_locale ?? 'ko']?.[4] ?? '제단',
      shrine_button_inside_viewport: true,
      shrine_button_copy_valid: true,
      shrine_button_text_nonempty: true,
      shrine_button_font_size_positive: true,
      shrine_button_font_alpha_readable: true,
      shrine_button_rendered_text_ready: true,
      shrine_button_opaque: true,
      ladder_button_visible: true,
      ladder_button_enabled: true,
      ladder_button_source_key: 'LADDER_OPEN',
      ladder_button_auto_translate: true,
      ladder_button_translation_text: TITLE_COPY[overrides.game_locale ?? 'ko']?.[5] ?? '순위',
      ladder_button_inside_viewport: true,
      ladder_button_copy_valid: true,
      ladder_button_text_nonempty: true,
      ladder_button_font_size_positive: true,
      ladder_button_font_alpha_readable: true,
      ladder_button_rendered_text_ready: true,
      ladder_button_opaque: true,
      direct_distribution: directDistribution,
      storefront_enabled: storefrontEnabled,
      storefront_feature_matches: true,
      store_button_visible: storefrontEnabled,
      store_button_enabled: storefrontEnabled,
      store_button_visibility_matches_storefront: true,
      store_button_enabled_matches_storefront: true,
      store_button_source_key: 'IAP_OPEN',
      store_button_auto_translate: true,
      store_button_translation_text: TITLE_COPY[overrides.game_locale ?? 'ko']?.[6] ?? '상점',
      store_button_inside_viewport: true,
      store_button_copy_valid: true,
      store_button_text_nonempty: true,
      store_button_font_size_positive: true,
      store_button_font_alpha_readable: true,
      store_button_rendered_text_ready: storefrontEnabled,
      store_button_opaque: storefrontEnabled,
      night_forest_node_present: true,
      night_forest_scene_path: TITLE_FOREST_SCENE,
      night_forest_expected_scene_path: TITLE_FOREST_SCENE,
      night_forest_scene_matches: true,
      night_forest_visible_in_tree: true,
      night_forest_effective_alpha: 1,
      night_forest_opaque: true,
      night_forest_ground_resource_path: TITLE_FOREST_GROUND,
      night_forest_expected_ground_resource_path: TITLE_FOREST_GROUND,
      night_forest_ground_resource_matches: true,
      night_forest_drawable_visible_in_tree: true,
      night_forest_drawable_effective_alpha: 1,
      night_forest_drawable_opaque: true,
      night_forest_draw_rect_positive: true,
      night_forest_draw_rect_intersects_viewport: true,
      night_forest_visual_ready: true,
      vignette_node_present: true,
      vignette_node_class: 'Sprite2D',
      vignette_texture_class: 'GradientTexture2D',
      vignette_expected_texture_class: 'GradientTexture2D',
      vignette_texture_unique_id: 'GradientTexture2D_vignette',
      vignette_expected_texture_unique_id: 'GradientTexture2D_vignette',
      vignette_texture_dimensions_match: true,
      vignette_texture_matches: true,
      vignette_visible_in_tree: true,
      vignette_effective_alpha: 1,
      vignette_opaque: true,
      vignette_draw_rect_positive: true,
      vignette_draw_rect_intersects_viewport: true,
      vignette_visual_ready: true,
      beacon_node_present: true,
      beacon_scene_path: TITLE_BEACON_SCENE,
      beacon_expected_scene_path: TITLE_BEACON_SCENE,
      beacon_scene_matches: true,
      beacon_visible_in_tree: true,
      beacon_effective_alpha: 1,
      beacon_opaque: true,
      beacon_clearing_resource_path: TITLE_BEACON_CLEARING,
      beacon_expected_clearing_resource_path: TITLE_BEACON_CLEARING,
      beacon_clearing_resource_matches: true,
      beacon_drawable_visible_in_tree: true,
      beacon_drawable_effective_alpha: 1,
      beacon_drawable_opaque: true,
      beacon_draw_rect_positive: true,
      beacon_draw_rect_intersects_viewport: true,
      beacon_visual_ready: true,
      panels_closed: true,
      accepting_input: true,
      screen_inside_viewport: true,
      drawn_after_ready: true,
    },
    arena_ready: {
      ...arenaSafeState(),
      scene: 'arena',
      ready: true,
      over: false,
    },
    moonlight_barrage: {
      ...arenaSafeState(),
      scene: 'arena',
      ready: true,
      over: false,
      level: 20,
      cycle: 3,
      zone_index: 0,
      terrain_path: 'res://resources/rooms/camp.tres',
      world_key: 'WORLD_CAMP',
      lit_beacons: 0,
      transitioning: false,
      escape_active: false,
      time_key: 'TIME_NIGHT',
      time_tone: [1, 1, 1, 1],
      applied_time_tone: [1, 1, 1, 1],
      time_tone_applied: true,
      missile_power: 8,
      missile_max: 8,
      missile_volley: 8,
      homing_active: true,
      moonfire_active: false,
      banner_key: 'MISSILE_COMPLETE',
      expected_banner_text: '미사일 편대 완성 · 출력 8/8',
      actual_banner_text: '미사일 편대 완성 · 출력 8/8',
      banner_visible: true,
      banner_locked: true,
      missile_visual_probe_count: 1,
      missile_visible_in_tree: true,
      missile_effective_alpha: 1,
      missile_opaque: true,
      missile_draw_after_launch: true,
      missile_head_geometry_ready: true,
      missile_trail_geometry_ready: true,
      visible_enemy_sprite_count: 3,
      enemy_formation_visible: true,
      max_volley_live: true,
      barrage_visible: true,
    },
    shrine: {
      ...shrineSafeState(),
      shrine_visible: true,
      preview_visible: false,
      hero_card_count: 6,
      hero_cards_visible_rect_count: 6,
      shrine_opaque: true,
      shrine_frame_inside_viewport: true,
      shrine_drawn_after_open: true,
    },
    hero_preview: {
      ...shrineSafeState({ preview: true }),
      shrine_visible: true,
      preview_visible: true,
      hero_path: KEEPER,
      portrait_visible: true,
      portrait_texture_ready: true,
      portrait_resource_path: KEEPER_PORTRAIT,
      portrait_expected_resource_path: KEEPER_PORTRAIT,
      portrait_resource_matches: true,
      portrait_visible_rect_ready: true,
      portrait_opaque: true,
      body_visible: true,
      body_texture_ready: true,
      body_resource_path: KEEPER_BODY,
      body_expected_resource_path: KEEPER_BODY,
      body_resource_matches: true,
      body_visible_rect_ready: true,
      body_opaque: true,
      copy_locale: previewLocale,
      name_source_key: 'HERO_KEEPER_NAME',
      name_expected_source_key: 'HERO_KEEPER_NAME',
      name_source_matches: true,
      name_text: previewCopy.name,
      name_expected_text: previewCopy.name,
      name_copy_valid: true,
      name_text_nonempty: true,
      name_characters_visible: true,
      name_font_size_positive: true,
      name_font_alpha_readable: true,
      name_visible_rect_ready: true,
      name_opaque: true,
      name_rendered_text_ready: true,
      state_source_key: previewStateSourceKey,
      state_expected_source_key: previewStateSourceKey,
      state_source_matches: true,
      state_text: previewStateText,
      state_expected_text: previewStateText,
      state_copy_valid: true,
      state_text_nonempty: true,
      state_characters_visible: true,
      state_font_size_positive: true,
      state_font_alpha_readable: true,
      state_visible_rect_ready: true,
      state_opaque: true,
      state_rendered_text_ready: true,
      description_source_key: 'HERO_KEEPER_DESC',
      description_expected_source_key: 'HERO_KEEPER_DESC',
      description_source_matches: true,
      description_text: previewCopy.description,
      description_expected_text: previewCopy.description,
      description_copy_valid: true,
      description_text_nonempty: true,
      description_characters_visible: true,
      description_font_size_positive: true,
      description_font_alpha_readable: true,
      description_visible_rect_ready: true,
      description_opaque: true,
      description_rendered_text_ready: true,
      close_visible: true,
      close_inside_viewport: true,
      close_opaque: true,
      shrine_opaque: true,
      shrine_frame_inside_viewport: true,
      shrine_drawn_after_open: true,
      preview_opaque: true,
      preview_frame_inside_viewport: true,
      preview_drawn_after_open: true,
    },
    field_guardian: {
      ...arenaSafeState(),
      scene: 'arena',
      ready: true,
      over: false,
      level: 20,
      cycle: 3,
      zone_index: 2,
      terrain_path: 'res://resources/rooms/field.tres',
      terrain_encounter: 1,
      world_key: 'WORLD_FIELD',
      time_key: 'TIME_DAY',
      time_tone: [1.55, 1.38, 1.12, 1],
      applied_time_tone: [1.55, 1.38, 1.12, 1],
      time_tone_applied: true,
      lit_beacons: 3,
      total_beacons: 3,
      transitioning: false,
      escape_active: false,
      guardian_alive: true,
      guardian_visible: true,
      guardian_on_screen: true,
      hud_boss_visible: true,
      guardian_name: '설원 수호자',
      guardian_kind_path: 'res://resources/guardian_field.tres',
      banner_key: 'GUARDIAN_INTRO',
      expected_banner_text: '푸른 들판의 날개 출현 · 교차 탄막의 빈 길을 선점하라',
      actual_banner_text: '푸른 들판의 날개 출현 · 교차 탄막의 빈 길을 선점하라',
      banner_visible: true,
      banner_locked: true,
      guardian_visual_node_present: true,
      guardian_visual_node_class: 'AnimatedSprite2D',
      guardian_root_visible_in_tree: true,
      guardian_sprite_visible_in_tree: true,
      guardian_root_effective_alpha: 1,
      guardian_sprite_effective_alpha: 1,
      guardian_root_opaque: true,
      guardian_sprite_opaque: true,
      guardian_current_animation: 'move',
      guardian_current_frame: 0,
      guardian_frame_texture_present: true,
      guardian_frame_texture_path: FIELD_GUARDIAN_FRAME,
      guardian_frame_texture_matches_field: true,
      guardian_draw_rect_positive: true,
      guardian_draw_rect_intersects_viewport: true,
      guardian_capture_active: true,
      friendly_projectile_count: 0,
      guardian_draw_rect: [470, 164, 60, 60],
      guardian_focus_rect: [177.76, 86.4, 452.48, 230.4],
      guardian_draw_rect_fully_inside_viewport: true,
      guardian_draw_rect_inside_focus: true,
      guardian_draw_center_inside_focus: true,
      guardian_player_canvas_distance: 100,
      guardian_separated_from_player: true,
      guardian_central_composition: true,
      guardian_visual_ready: true,
    },
    iap_review: {
      ...iapSafeState(),
      shop_visible: true,
      shop_opaque: true,
      shop_drawn_after_open: true,
      shop_frame_inside_viewport: true,
      preview_visible: false,
      product_id: IAP_PRODUCTS[0].product_id,
      card_visible: true,
      card_visible_rect_ready: true,
      card_opaque: true,
      title_visible: true,
      title_text: iapTitle,
      title_expected_text: iapTitle,
      title_text_nonempty: true,
      title_copy_valid: true,
      title_characters_visible: true,
      title_font_size_positive: true,
      title_font_alpha_readable: true,
      title_rendered_text_ready: true,
      title_visible_rect_ready: true,
      title_opaque: true,
      review_fallback_verified: true,
      review_status_visible: true,
      review_status_text: IAP_REVIEW_FALLBACK_STATUS_TEXT,
      review_status_expected_text: IAP_REVIEW_FALLBACK_STATUS_TEXT,
      review_status_copy_valid: true,
      review_status_rendered_text_ready: true,
      review_status_visible_rect_ready: true,
      review_status_opaque: true,
      price_visible: true,
      price_text: IAP_REVIEW_FALLBACK_PRICE_TEXT,
      price_expected_text: IAP_REVIEW_FALLBACK_PRICE_TEXT,
      price_copy_valid: true,
      price_rendered_text_ready: true,
      price_visible_rect_ready: true,
      price_opaque: true,
      portrait_visible: true,
      portrait_visible_rect_ready: true,
      portrait_opaque: true,
      hero_resource_path: iapHero?.hero ?? '',
      hero_expected_resource_path: iapHero?.hero ?? '',
      portrait_resource_path: iapHero?.portrait ?? '',
      portrait_expected_resource_path: iapHero?.portrait ?? '',
      portrait_product_specific: iapHero !== undefined,
      action_visible: true,
      action_enabled: false,
      action_text: '구매',
      action_expected_text: '구매',
      action_text_nonempty: true,
      action_copy_valid: true,
      action_font_size_positive: true,
      action_font_alpha_readable: true,
      action_rendered_text_ready: true,
      action_visible_rect_ready: true,
      action_opaque: true,
      restore_visible: true,
      restore_enabled: false,
      restore_text: '구매 복원',
      restore_expected_text: '구매 복원',
      restore_text_nonempty: true,
      restore_copy_valid: true,
      restore_font_size_positive: true,
      restore_font_alpha_readable: true,
      restore_rendered_text_ready: true,
      restore_visible_rect_ready: true,
      restore_opaque: true,
      card_fully_inside_viewport: true,
      card_inside_screen: true,
    },
  };
  assert.ok(states[kind], `unknown fixture kind: ${kind}`);
  return { ...common, ...states[kind], ...overrides };
}

test('shared store capture state pins schema, nonce, kind, and locale', () => {
  const expected = { kind: 'arena_ready', gameLocale: 'ko' };
  assert.deepEqual(
    assertStoreCaptureState(storeCaptureState('arena_ready'), expected),
    storeCaptureState('arena_ready'),
  );
  for (const [overrides, pattern] of [
    [{ schema: 2 }, /schema/u],
    [{ nonce: 'short' }, /nonce/u],
    [{ nonce: 'A'.repeat(64) }, /nonce/u],
    [{ observation: 0 }, /observation number/u],
    [{ observation: 1.5 }, /observation number/u],
    [{ kind: 'shrine' }, /kind/u],
    [{ game_locale: 'en' }, /locale/u],
  ]) {
    assert.throws(
      () => assertStoreCaptureState(
        storeCaptureState('arena_ready', overrides),
        expected,
      ),
      pattern,
    );
  }
  assert.throws(
    () => assertStoreCaptureState(storeCaptureState('arena_ready'), {}),
    /kind and expected game locale/u,
  );
  assert.throws(
    () => assertStoreCaptureState(
      storeCaptureState('hero_preview'),
      { kind: 'hero_preview', gameLocale: 'ko' },
    ),
    /expected hero path/u,
  );
  assert.throws(
    () => assertStoreCaptureState(
      storeCaptureState('iap_review'),
      { kind: 'iap_review', gameLocale: 'ko' },
    ),
    /expected product ID/u,
  );
});

test('combat, shrine, and hero-preview state verify every required screen-meaning condition', () => {
  const arenaExpected = { kind: 'arena_ready', gameLocale: 'ko' };
  for (const [overrides, pattern] of [
    [{ scene: 'title' }, /arena/u],
    [{ ready: false }, /ready/u],
    [{ over: true }, /finished combat/u],
  ]) {
    assert.throws(
      () => assertStoreCaptureState(
        storeCaptureState('arena_ready', overrides),
        arenaExpected,
      ),
      pattern,
    );
  }

  const shrineExpected = { kind: 'shrine', gameLocale: 'ko' };
  assert.equal(
    assertStoreCaptureState(
      storeCaptureState('shrine'),
      shrineExpected,
    ).hero_card_count,
    6,
  );
  for (const [overrides, pattern] of [
    [{ shrine_visible: false }, /Shrine panel/u],
    [{ preview_visible: true }, /Hero detail/u],
    [{ hero_card_count: 5 }, /6 shrine hero cards/u],
    [{ hero_cards_visible_rect_count: 5 }, /visible rects/u],
    [{ shrine_opaque: false }, /transition/u],
    [{ shrine_frame_inside_viewport: false }, /on screen/u],
    [{ shrine_drawn_after_open: false }, /render frame/u],
  ]) {
    assert.throws(
      () => assertStoreCaptureState(
        storeCaptureState('shrine', overrides),
        shrineExpected,
      ),
      pattern,
    );
  }

  const previewExpected = {
    kind: 'hero_preview',
    gameLocale: 'ko',
    heroPath: KEEPER,
  };
  assert.equal(
    assertStoreCaptureState(
      storeCaptureState('hero_preview'),
      previewExpected,
    ).hero_path,
    KEEPER,
  );
  for (const [gameLocale, copy] of Object.entries(HERO_PREVIEW_COPY)) {
    for (const [stateSourceKey, stateText] of Object.entries(copy.states)) {
      const localized = assertStoreCaptureState(
        storeCaptureState('hero_preview', {
          game_locale: gameLocale,
          copy_locale: gameLocale,
          state_source_key: stateSourceKey,
          state_expected_source_key: stateSourceKey,
          state_text: stateText,
          state_expected_text: stateText,
        }),
        { ...previewExpected, gameLocale },
      );
      assert.equal(localized.name_text, copy.name);
      assert.equal(localized.state_source_key, stateSourceKey);
      assert.equal(localized.state_text, stateText);
      assert.equal(localized.description_text, copy.description);
    }
  }
  for (const [overrides, pattern] of [
    [{ shrine_visible: false }, /Shrine panel/u],
    [{ preview_visible: false }, /Hero-preview panel is not visible/u],
    [{ hero_path: 'res://resources/heroes/dancer.tres' }, /hero path/u],
    [{ portrait_visible: false }, /portrait/u],
    [{ portrait_texture_ready: false }, /portrait texture/u],
    [{ portrait_resource_path: 'res://assets/custom/actors/heroes/dancer/portrait.png' }, /live portrait resource/u],
    [{ portrait_expected_resource_path: 'res://assets/custom/actors/heroes/dancer/portrait.png' }, /expected portrait resource/u],
    [{ portrait_resource_matches: false }, /pinned asset/u],
    [{ portrait_visible_rect_ready: false }, /portrait live/u],
    [{ portrait_opaque: false }, /portrait is transparent/u],
    [{ body_visible: false }, /full-body/u],
    [{ body_texture_ready: false }, /full-body texture/u],
    [{ body_resource_path: 'res://assets/custom/actors/heroes/dancer/idle.png' }, /live full-body resource/u],
    [{ body_expected_resource_path: 'res://assets/custom/actors/heroes/dancer/idle.png' }, /expected full-body resource/u],
    [{ body_resource_matches: false }, /pinned asset/u],
    [{ body_visible_rect_ready: false }, /full-body live/u],
    [{ body_opaque: false }, /full-body is transparent/u],
    [{ copy_locale: 'en' }, /copy locale/u],
    [{ name_source_key: 'HERO_KEEPER_DESC' }, /name live translation source/u],
    [{ name_expected_source_key: 'HERO_KEEPER_DESC' }, /name expected translation source/u],
    [{ name_source_matches: false }, /name translation source/u],
    [{ name_text: '' }, /live name/u],
    [{ name_expected_text: '' }, /expected name/u],
    [{ name_copy_valid: false }, /name copy contract/u],
    [{ name_text_nonempty: false }, /name is empty/u],
    [{ name_characters_visible: false }, /name glyphs are hidden/u],
    [{ name_font_size_positive: false }, /name font size/u],
    [{ name_font_alpha_readable: false }, /name glyphs are transparent/u],
    [{ name_visible_rect_ready: false }, /name live visible area/u],
    [{ name_opaque: false }, /name label is transparent/u],
    [{ name_rendered_text_ready: false }, /name is not actually renderable/u],
    [{ state_source_key: 'HERO_KEEPER_NAME' }, /allowed state/u],
    [{ state_expected_source_key: 'SHRINE_OWNED' }, /expected translation source/u],
    [{ state_source_matches: false }, /state translation source/u],
    [{ state_text: '' }, /live state copy/u],
    [{ state_expected_text: '' }, /expected state copy/u],
    [{ state_copy_valid: false }, /state copy contract/u],
    [{ state_text_nonempty: false }, /state copy is empty/u],
    [{ state_characters_visible: false }, /state glyphs are hidden/u],
    [{ state_font_size_positive: false }, /state font size/u],
    [{ state_font_alpha_readable: false }, /state glyphs are transparent/u],
    [{ state_visible_rect_ready: false }, /state live visible area/u],
    [{ state_opaque: false }, /state label is transparent/u],
    [{ state_rendered_text_ready: false }, /state is not actually renderable/u],
    [{ description_source_key: 'HERO_KEEPER_NAME' }, /description live translation source/u],
    [{ description_expected_source_key: 'HERO_KEEPER_NAME' }, /description expected translation source/u],
    [{ description_source_matches: false }, /description translation source/u],
    [{ description_text: '' }, /live description/u],
    [{ description_expected_text: '' }, /expected description/u],
    [{ description_copy_valid: false }, /description copy contract/u],
    [{ description_text_nonempty: false }, /description is empty/u],
    [{ description_characters_visible: false }, /description glyphs are hidden/u],
    [{ description_font_size_positive: false }, /description font size/u],
    [{ description_font_alpha_readable: false }, /description glyphs are transparent/u],
    [{ description_visible_rect_ready: false }, /description live visible area/u],
    [{ description_opaque: false }, /description label is transparent/u],
    [{ description_rendered_text_ready: false }, /description is not actually renderable/u],
    [{ close_visible: false }, /close button/u],
    [{ close_inside_viewport: false }, /close button was not laid out/u],
    [{ close_opaque: false }, /close button is transparent/u],
    [{ preview_opaque: false }, /transition/u],
    [{ preview_frame_inside_viewport: false }, /on screen/u],
    [{ preview_drawn_after_open: false }, /render frame/u],
  ]) {
    assert.throws(
      () => assertStoreCaptureState(
        storeCaptureState('hero_preview', overrides),
        previewExpected,
      ),
      pattern,
    );
  }
  for (const sameWrong of [
    {
      name_text: 'same wrong name',
      name_expected_text: 'same wrong name',
    },
    {
      description_text: 'same wrong description',
      description_expected_text: 'same wrong description',
    },
    {
      name_source_key: 'HERO_KEEPER_DESC',
      name_expected_source_key: 'HERO_KEEPER_DESC',
    },
    {
      description_source_key: 'HERO_KEEPER_NAME',
      description_expected_source_key: 'HERO_KEEPER_NAME',
    },
    {
      state_source_key: 'HERO_KEEPER_NAME',
      state_expected_source_key: 'HERO_KEEPER_NAME',
      state_text: '봉화지기',
      state_expected_text: '봉화지기',
    },
  ]) {
    assert.throws(
      () => assertStoreCaptureState(
        storeCaptureState('hero_preview', sameWrong),
        previewExpected,
      ),
      /Hero-preview/u,
    );
  }
});

test('store capture safe area recomputes coordinates independent of game booleans', () => {
  const cases = [
    ['title', { settings_button_rect: [780, 20, 40, 26] }],
    ['arena_ready', { dash_rect: [780, 284, 52, 52] }],
    ['moonlight_barrage', { hud_left_rect: [-4, 14, 82, 100] }],
    ['shrine', { shrine_frame_rect: [4, 16, 732, 328] }],
    ['hero_preview', { close_rect: [790, 288, 148, 28] }],
    ['field_guardian', { boss_rect: [254, 344, 300, 24] }],
    ['iap_review', { card_rect: [790, 90, 248, 180] }],
  ];
  for (const [kind, overrides] of cases) {
    assert.throws(
      () => assertStoreCaptureState(
        storeCaptureState(kind, overrides),
        {
          kind,
          gameLocale: 'ko',
          ...(kind === 'title' ? { directDistribution: true } : {}),
          ...(kind === 'hero_preview' ? { heroPath: KEEPER } : {}),
          ...(kind === 'iap_review'
            ? { productId: IAP_PRODUCTS[0].product_id }
            : {}),
        },
      ),
      /intrudes on the OS gesture safe area/u,
      kind,
    );
  }
  assert.throws(
    () => assertStoreCaptureState(
      storeCaptureState('title', { safe_rect: [0, 0, Number.NaN, 360] }),
      { kind: 'title', gameLocale: 'ko', directDistribution: true },
    ),
    /safe-area coordinates/u,
  );
  assert.throws(
    () => assertStoreCaptureState(
      storeCaptureState('arena_ready', { safe_rect: [-20, 0, 828, 360] }),
      { kind: 'arena_ready', gameLocale: 'ko' },
    ),
    /outside the actual capture screen/u,
  );
});

test('title and max Moonlight barrage prove actual ad-scene meaning', () => {
  const titleExpected = {
    kind: 'title',
    gameLocale: 'ko',
    directDistribution: true,
  };
  assert.equal(
    assertStoreCaptureState(storeCaptureState('title'), titleExpected).version_text,
    'v1.0.1',
  );
  assert.throws(
    () => assertStoreCaptureState(
      storeCaptureState('title'),
      { kind: 'title', gameLocale: 'ko' },
    ),
    /distribution feature/u,
  );
  const storefrontTitle = storeCaptureState('title', {
    direct_distribution: false,
  });
  assert.equal(
    assertStoreCaptureState(storefrontTitle, {
      kind: 'title',
      gameLocale: 'ko',
      directDistribution: false,
    }).store_button_visible,
    true,
  );
  assert.throws(
    () => assertStoreCaptureState(
      storeCaptureState('title', {
        direct_distribution: false,
        store_button_rect: [780, 116, 68, 26],
      }),
      {
        kind: 'title',
        gameLocale: 'ko',
        directDistribution: false,
      },
    ),
    /intrudes on the OS gesture safe area/u,
  );
  for (const [overrides, pattern] of [
    [{ scene: 'arena' }, /title/u],
    [{ title_visible: false }, /Game title/u],
    [{ subtitle_visible: false }, /Subtitle/u],
    [{ title_source_key: '달빛 봉화' }, /source key/u],
    [{ subtitle_auto_translate: false }, /auto-translate/u],
    [{ title_translation_text: 'TITLE_NAME' }, /live translation/u],
    [{ subtitle_translation_text: 'TITLE_SUBTITLE' }, /live translation/u],
    [{ title_text_nonempty: false }, /heading copy/u],
    [{ title_characters_visible: false }, /heading glyphs are hidden/u],
    [{ title_font_size_positive: false }, /heading font size/u],
    [{ title_font_alpha_readable: false }, /heading glyphs are transparent/u],
    [{ title_rendered_text_ready: false }, /heading is not actually drawn/u],
    [{ subtitle_text_nonempty: false }, /subtitle copy/u],
    [{ subtitle_characters_visible: false }, /subtitle glyphs are hidden/u],
    [{ subtitle_font_size_positive: false }, /subtitle font size/u],
    [{ subtitle_font_alpha_readable: false }, /subtitle glyphs are transparent/u],
    [{ subtitle_rendered_text_ready: false }, /subtitle is not actually drawn/u],
    [{ title_inside_viewport: false }, /heading was not laid out/u],
    [{ subtitle_inside_viewport: false }, /subtitle was not laid out/u],
    [{ title_opaque: false }, /heading is transparent/u],
    [{ subtitle_opaque: false }, /subtitle is transparent/u],
    [{ version_visible: false }, /app version/u],
    [{ version_text: 'Moonlit' }, /version string/u],
    [{ version_text_nonempty: false }, /version copy/u],
    [{ version_characters_visible: false }, /version glyphs are hidden/u],
    [{ version_font_size_positive: false }, /version font size/u],
    [{ version_font_alpha_readable: false }, /version glyphs are transparent/u],
    [{ version_rendered_text_ready: false }, /version is not actually drawn/u],
    [{ version_inside_viewport: false }, /App version was not laid out/u],
    [{ version_opaque: false }, /version label is transparent/u],
    [{ tap_prompt_visible: false }, /Start prompt/u],
    [{ tap_prompt_source_key: '화면을 탭하여 시작' }, /source key/u],
    [{ tap_prompt_translation_text: 'Tap to start' }, /current locale/u],
    [{ tap_prompt_text_nonempty: false }, /Start prompt copy/u],
    [{ tap_prompt_characters_visible: false }, /Start prompt glyphs are hidden/u],
    [{ tap_prompt_font_size_positive: false }, /Start prompt font size/u],
    [{ tap_prompt_font_alpha_readable: false }, /Start prompt glyphs are transparent/u],
    [{ tap_prompt_rendered_text_ready: false }, /Start prompt is not actually drawn/u],
    [{ tap_prompt_inside_viewport: false }, /Start prompt was not laid out/u],
    [{ tap_prompt_readable_alpha: false }, /fully opaque/u],
    [{ tap_prompt_effective_alpha: 0.5 }, /live alpha/u],
    [{ tap_prompt_effective_alpha: Number.NaN }, /live alpha/u],
    [{ tap_prompt_full_alpha: false }, /full-opaque proof/u],
    [{ tap_prompt_blink_stopped: false }, /blink did not stop/u],
    [{ tap_prompt_modulate_white: false }, /full white/u],
    [{ tap_prompt_capture_locked: false }, /capture freeze/u],
    [{ settings_button_enabled: false }, /settings button is disabled/u],
    [{ settings_button_translation_text: 'Settings' }, /current locale/u],
    [{ settings_button_text_nonempty: false }, /settings button copy/u],
    [{ settings_button_font_size_positive: false }, /settings button font size/u],
    [{ settings_button_font_alpha_readable: false }, /settings button glyphs are transparent/u],
    [{ settings_button_rendered_text_ready: false }, /settings button glyphs are not actually drawn/u],
    [{ shrine_button_inside_viewport: false }, /shrine button is not on screen/u],
    [{ shrine_button_text_nonempty: false }, /shrine button copy/u],
    [{ shrine_button_font_size_positive: false }, /shrine button font size/u],
    [{ shrine_button_font_alpha_readable: false }, /shrine button glyphs are transparent/u],
    [{ shrine_button_rendered_text_ready: false }, /shrine button glyphs are not actually drawn/u],
    [{ ladder_button_opaque: false }, /ladder button is transparent/u],
    [{ ladder_button_text_nonempty: false }, /ladder button copy/u],
    [{ ladder_button_font_size_positive: false }, /ladder button font size/u],
    [{ ladder_button_font_alpha_readable: false }, /ladder button glyphs are transparent/u],
    [{ ladder_button_rendered_text_ready: false }, /ladder button glyphs are not actually drawn/u],
    [{ direct_distribution: false }, /direct_distribution/u],
    [{ storefront_enabled: true }, /storefront state/u],
    [{ storefront_feature_matches: false }, /storefront verdict/u],
    [{ store_button_visible: true }, /composited visible/u],
    [{ store_button_enabled: true }, /hidden store button.*is enabled/u],
    [{ store_button_visibility_matches_storefront: false }, /visibility differs from storefront/u],
    [{ store_button_enabled_matches_storefront: false }, /enabled state differs from storefront/u],
    [{ store_button_source_key: 'STORE' }, /store button translation source/u],
    [{ store_button_auto_translate: false }, /store button auto-translate/u],
    [{ store_button_translation_text: 'Store' }, /store button live translation/u],
    [{ store_button_inside_viewport: false }, /store button.*on screen/u],
    [{ store_button_copy_valid: false }, /store button translation contract/u],
    [{ store_button_text_nonempty: false }, /store button copy/u],
    [{ store_button_font_size_positive: false }, /store button font size/u],
    [{ store_button_font_alpha_readable: false }, /store button glyphs are transparent/u],
    [{ store_button_rendered_text_ready: true }, /live render state/u],
    [{ store_button_opaque: true }, /live opaque state/u],
    [{ night_forest_node_present: false }, /NightForest node/u],
    [{ night_forest_scene_path: 'res://scenes/gameplay/arena.tscn' }, /forest live scene path/u],
    [{ night_forest_expected_scene_path: 'res://scenes/gameplay/arena.tscn' }, /forest expected scene path/u],
    [{ night_forest_scene_matches: false }, /forest scene does not match the pinned asset/u],
    [{ night_forest_visible_in_tree: false }, /forest is not visible in the live tree/u],
    [{ night_forest_effective_alpha: 0.98 }, /forest root is transparent/u],
    [{ night_forest_effective_alpha: Number.POSITIVE_INFINITY }, /forest root is transparent/u],
    [{ night_forest_opaque: false }, /forest root is not opaque/u],
    [{ night_forest_ground_resource_path: TITLE_BEACON_CLEARING }, /forest floor live resource/u],
    [{ night_forest_expected_ground_resource_path: TITLE_BEACON_CLEARING }, /forest floor expected resource/u],
    [{ night_forest_ground_resource_matches: false }, /forest floor does not match the pinned asset/u],
    [{ night_forest_drawable_visible_in_tree: false }, /forest live drawable is not visible/u],
    [{ night_forest_drawable_effective_alpha: 0 }, /forest live drawable is transparent/u],
    [{ night_forest_drawable_effective_alpha: Number.POSITIVE_INFINITY }, /forest live drawable is transparent/u],
    [{ night_forest_drawable_opaque: false }, /forest live drawable is not opaque/u],
    [{ night_forest_draw_rect_positive: false }, /forest live draw rect/u],
    [{ night_forest_draw_rect_intersects_viewport: false }, /forest live draw rect does not intersect/u],
    [{ night_forest_visual_ready: false }, /forest art is not live-render-ready/u],
    [{ vignette_node_present: false }, /Vignette node/u],
    [{ vignette_node_class: 'Node2D' }, /vignette live node type/u],
    [{ vignette_texture_class: 'CompressedTexture2D' }, /vignette live texture type/u],
    [{ vignette_expected_texture_class: 'CompressedTexture2D' }, /vignette expected texture type/u],
    [{ vignette_texture_unique_id: 'wrong_vignette' }, /vignette live texture unique id/u],
    [{ vignette_expected_texture_unique_id: 'wrong_vignette' }, /vignette expected texture unique id/u],
    [{ vignette_texture_dimensions_match: false }, /vignette texture size/u],
    [{ vignette_texture_matches: false }, /vignette does not match the pinned asset/u],
    [{ vignette_visible_in_tree: false }, /vignette is not visible in the live tree/u],
    [{ vignette_effective_alpha: 0 }, /vignette is transparent/u],
    [{ vignette_effective_alpha: Number.POSITIVE_INFINITY }, /vignette is transparent/u],
    [{ vignette_opaque: false }, /vignette is not opaque/u],
    [{ vignette_draw_rect_positive: false }, /vignette live draw rect/u],
    [{ vignette_draw_rect_intersects_viewport: false }, /vignette live draw rect does not intersect/u],
    [{ vignette_visual_ready: false }, /vignette art is not live-render-ready/u],
    [{ beacon_node_present: false }, /Beacon node/u],
    [{ beacon_scene_path: TITLE_FOREST_SCENE }, /beacon live scene path/u],
    [{ beacon_expected_scene_path: TITLE_FOREST_SCENE }, /beacon expected scene path/u],
    [{ beacon_scene_matches: false }, /beacon scene does not match the pinned asset/u],
    [{ beacon_visible_in_tree: false }, /beacon is not visible in the live tree/u],
    [{ beacon_effective_alpha: 0 }, /beacon root is transparent/u],
    [{ beacon_effective_alpha: Number.POSITIVE_INFINITY }, /beacon root is transparent/u],
    [{ beacon_opaque: false }, /beacon root is not opaque/u],
    [{ beacon_clearing_resource_path: TITLE_FOREST_GROUND }, /beacon floor live resource/u],
    [{ beacon_expected_clearing_resource_path: TITLE_FOREST_GROUND }, /beacon floor expected resource/u],
    [{ beacon_clearing_resource_matches: false }, /beacon floor does not match the pinned asset/u],
    [{ beacon_drawable_visible_in_tree: false }, /beacon live drawable is not visible/u],
    [{ beacon_drawable_effective_alpha: 0 }, /beacon live drawable is transparent/u],
    [{ beacon_drawable_effective_alpha: Number.POSITIVE_INFINITY }, /beacon live drawable is transparent/u],
    [{ beacon_drawable_opaque: false }, /beacon live drawable is not opaque/u],
    [{ beacon_draw_rect_positive: false }, /beacon live draw rect/u],
    [{ beacon_draw_rect_intersects_viewport: false }, /beacon live draw rect does not intersect/u],
    [{ beacon_visual_ready: false }, /beacon art is not live-render-ready/u],
    [{
      night_forest_scene_path: 'res://same-wrong/forest.tscn',
      night_forest_expected_scene_path: 'res://same-wrong/forest.tscn',
    }, /forest live scene path/u],
    [{
      night_forest_ground_resource_path: 'res://same-wrong/ground.png',
      night_forest_expected_ground_resource_path: 'res://same-wrong/ground.png',
    }, /forest floor live resource/u],
    [{
      vignette_texture_class: 'SameWrongTexture2D',
      vignette_expected_texture_class: 'SameWrongTexture2D',
    }, /vignette live texture type/u],
    [{
      vignette_texture_unique_id: 'same_wrong_vignette',
      vignette_expected_texture_unique_id: 'same_wrong_vignette',
    }, /vignette live texture unique id/u],
    [{
      beacon_scene_path: 'res://same-wrong/beacon.tscn',
      beacon_expected_scene_path: 'res://same-wrong/beacon.tscn',
    }, /beacon live scene path/u],
    [{
      beacon_clearing_resource_path: 'res://same-wrong/clearing.png',
      beacon_expected_clearing_resource_path: 'res://same-wrong/clearing.png',
    }, /beacon floor live resource/u],
    [{ panels_closed: false }, /Another panel/u],
    [{ accepting_input: false }, /start input/u],
    [{ drawn_after_ready: false }, /render frame/u],
  ]) {
    assert.throws(
      () => assertStoreCaptureState(storeCaptureState('title', overrides), titleExpected),
      pattern,
    );
  }

  const barrageExpected = { kind: 'moonlight_barrage', gameLocale: 'ko' };
  assert.equal(
    assertStoreCaptureState(
      storeCaptureState('moonlight_barrage'),
      barrageExpected,
    ).missile_volley,
    8,
  );
  for (const [overrides, pattern] of [
    [{ level: 19 }, /level 20/u],
    [{ cycle: 2 }, /cycle 3/u],
    [{ terrain_path: 'res://resources/rooms/forest.tres' }, /camp/u],
    [{ world_key: 'WORLD_FOREST' }, /biome cycle/u],
    [{ lit_beacons: 1 }, /unlit night/u],
    [{ time_key: 'TIME_DAY' }, /time of day/u],
    [{ applied_time_tone: [1.55, 1.38, 1.12, 1] }, /Night tone/u],
    [{ time_tone_applied: false }, /background tone/u],
    [{ missile_power: 7 }, /power/u],
    [{ missile_volley: 2 }, /8-shot/u],
    [{ homing_active: false }, /homing/u],
    [{ moonfire_active: true }, /awakening screen/u],
    [{ banner_key: 'MOONFIRE_AWAKENED' }, /banner key/u],
    [{ actual_banner_text: 'Moon ember awaken' }, /live banner copy/u],
    [{ banner_visible: false }, /visible frozen state/u],
    [{ missile_visual_probe_count: 0 }, /visual probe/u],
    [{ missile_visible_in_tree: false }, /live tree/u],
    [{ missile_effective_alpha: 0 }, /transparent/u],
    [{ missile_opaque: false }, /opaque/u],
    [{ missile_draw_after_launch: false }, /after launch/u],
    [{ missile_head_geometry_ready: false }, /warhead geometry/u],
    [{ missile_trail_geometry_ready: false }, /trail geometry/u],
    [{ visible_enemy_sprite_count: 2 }, /enemy sprites/u],
    [{ visible_enemy_sprite_count: 3.5 }, /enemy sprites/u],
    [{ enemy_formation_visible: false }, /enemy formation/u],
    [{ max_volley_live: false }, /live 8-shot/u],
    [{ barrage_visible: false }, /on screen/u],
  ]) {
    assert.throws(
      () => assertStoreCaptureState(
        storeCaptureState('moonlight_barrage', overrides),
        barrageExpected,
      ),
      pattern,
    );
  }
});

test('Guardian state requires completed beacons, a stable scene, body, and HUD together', () => {
  const expected = { kind: 'field_guardian', gameLocale: 'ko' };
  assert.equal(
    assertStoreCaptureState(
      storeCaptureState('field_guardian'),
      expected,
    ).guardian_name,
    '설원 수호자',
  );
  const float32DayTone = [
    1.54999995231628,
    1.37999999523163,
    1.12000000476837,
    1,
  ];
  assert.doesNotThrow(() => assertStoreCaptureState(
    storeCaptureState('field_guardian', {
      time_tone: float32DayTone,
      applied_time_tone: float32DayTone,
    }),
    expected,
  ));
  for (const [overrides, pattern] of [
    [{ scene: 'title' }, /arena/u],
    [{ ready: false }, /ready/u],
    [{ cycle: 0 }, /cycle/u],
    [{ cycle: 1.5 }, /cycle/u],
    [{ cycle: 2 }, /cycle-3/u],
    [{ level: 10 }, /Lv20/u],
    [{ zone_index: 1 }, /third field/u],
    [{ terrain_path: 'res://resources/rooms/forest.tres' }, /moonlit field/u],
    [{ terrain_encounter: 0 }, /crossfire/u],
    [{ world_key: 'WORLD_CAMP' }, /biome cycle/u],
    [{ time_key: 'TIME_NIGHT' }, /time of day/u],
    [{ applied_time_tone: [1, 1, 1, 1] }, /Day tone/u],
    [{ applied_time_tone: [1.55001, 1.38, 1.12, 1] }, /Day tone/u],
    [{ applied_time_tone: [Number.NaN, 1.38, 1.12, 1] }, /Day tone/u],
    [{ applied_time_tone: ['1.55', 1.38, 1.12, 1] }, /Day tone/u],
    [{ lit_beacons: 2 }, /three beacons/u],
    [{ total_beacons: 4 }, /total beacon/u],
    [{ transitioning: true }, /transition/u],
    [{ escape_active: true }, /escape gate/u],
    [{ guardian_alive: false }, /living/u],
    [{ guardian_visible: false }, /body/u],
    [{ guardian_on_screen: false }, /on screen/u],
    [{ hud_boss_visible: false }, /boss HUD/u],
    [{ guardian_name: '  ' }, /name/u],
    [{ guardian_kind_path: '' }, /field Guardian/u],
    [{ guardian_kind_path: 'res://resources/guardian_forest.tres' }, /field Guardian/u],
    [{ banner_key: 'GUARDIAN_APPEARS' }, /banner key/u],
    [{ actual_banner_text: 'Guardian appears' }, /live banner copy/u],
    [{ banner_locked: false }, /visible frozen state/u],
    [{ guardian_visual_node_present: false }, /AnimatedSprite2D physical/u],
    [{ guardian_visual_node_class: 'Sprite2D' }, /AnimatedSprite2D/u],
    [{ guardian_root_visible_in_tree: false }, /root is not visible in the live tree/u],
    [{ guardian_sprite_visible_in_tree: false }, /sprite is not visible in the live tree/u],
    [{ guardian_root_effective_alpha: 0.98 }, /live sprite is transparent/u],
    [{ guardian_root_effective_alpha: Number.NaN }, /live sprite is transparent/u],
    [{ guardian_sprite_effective_alpha: 0.98 }, /live sprite is transparent/u],
    [{ guardian_sprite_effective_alpha: '1' }, /live sprite is transparent/u],
    [{ guardian_root_opaque: false }, /root is transparent/u],
    [{ guardian_sprite_opaque: false }, /sprite is transparent/u],
    [{ guardian_current_animation: '   ' }, /animation is empty/u],
    [{ guardian_current_frame: -1 }, /frame is invalid/u],
    [{ guardian_current_frame: 0.5 }, /frame is invalid/u],
    [{ guardian_frame_texture_present: false }, /frame texture/u],
    [{ guardian_frame_texture_path: 'res://assets/custom/actors/guardians/wisp.png' }, /field-Guardian asset/u],
    [{ guardian_frame_texture_matches_field: false }, /differs from the field Guardian asset/u],
    [{ guardian_draw_rect_positive: false }, /draw rect is empty/u],
    [{ guardian_draw_rect_intersects_viewport: false }, /draw rect is off screen/u],
    [{ guardian_capture_active: false }, /center-composition freeze/u],
    [{ friendly_projectile_count: 1 }, /allied projectiles/u],
    [{ friendly_projectile_count: 0.5 }, /allied projectiles/u],
    [{ guardian_draw_rect: [20, 164, 60, 60] }, /outside the screen center focus/u],
    [{ guardian_draw_rect: [470, 164, Number.NaN, 60] }, /canvas rect/u],
    [{ guardian_focus_rect: [0, 0, 808, 360] }, /frozen composition contract/u],
    [{ guardian_draw_rect_fully_inside_viewport: false }, /entirely on screen/u],
    [{ guardian_draw_rect_inside_focus: false }, /inside center focus/u],
    [{ guardian_draw_center_inside_focus: false }, /center point is inside center focus/u],
    [{ guardian_player_canvas_distance: 71.9 }, /silhouettes are not separated/u],
    [{ guardian_player_canvas_distance: Number.POSITIVE_INFINITY }, /silhouettes are not separated/u],
    [{ guardian_separated_from_player: false }, /silhouette-separation proof/u],
    [{ guardian_central_composition: false }, /center-composition proof/u],
    [{ guardian_visual_ready: false }, /physical render proof/u],
  ]) {
    assert.throws(
      () => assertStoreCaptureState(
        storeCaptureState('field_guardian', overrides),
        expected,
      ),
      pattern,
    );
  }
});

test('IAP state proves live direct-distribution fallback and fully on-screen product UI', () => {
  const hero = IAP_PRODUCTS[0].product_id;
  const heroExpected = {
    kind: 'iap_review',
    gameLocale: 'ko',
    productId: hero,
  };
  assert.equal(
    assertStoreCaptureState(storeCaptureState('iap_review'), heroExpected).product_id,
    hero,
  );
  for (const [overrides, pattern] of [
    [{ shop_visible: false }, /store panel/u],
    [{ shop_opaque: false }, /open transition/u],
    [{ shop_drawn_after_open: false }, /render frame/u],
    [{ shop_frame_inside_viewport: false }, /outside the live screen/u],
    [{ preview_visible: true }, /detail panel/u],
    [{ product_id: IAP_PRODUCTS[1].product_id }, /product ID/u],
    [{ card_visible: false }, /product card/u],
    [{ card_visible_rect_ready: false }, /card live/u],
    [{ card_opaque: false }, /card is transparent/u],
    [{ title_visible: false }, /product name/u],
    [{ title_text: '   ' }, /Korean submission product-name/u],
    [{ title_expected_text: 'other product' }, /Korean submission product-name/u],
    [{ title_text: 'same wrong name', title_expected_text: 'same wrong name' }, /Korean submission product-name/u],
    [{ title_text_nonempty: false }, /product name copy is empty/u],
    [{ title_copy_valid: false }, /product name differs from the current product/u],
    [{ title_characters_visible: false }, /product name glyphs are hidden/u],
    [{ title_font_size_positive: false }, /product name font size/u],
    [{ title_font_alpha_readable: false }, /product name glyphs are transparent/u],
    [{ title_rendered_text_ready: false }, /product name is not actually drawn/u],
    [{ title_visible_rect_ready: false }, /product name live/u],
    [{ title_opaque: false }, /product name is transparent/u],
    [{ review_fallback_verified: false }, /fallback state/u],
    [{ review_status_visible: false }, /direct-distribution help copy is not visible/u],
    [{ review_status_text: 'Could not load products' }, /direct-distribution help copy/u],
    [{ review_status_expected_text: 'Could not load products' }, /direct-distribution help copy/u],
    [{
      review_status_text: 'same wrong help',
      review_status_expected_text: 'same wrong help',
    }, /direct-distribution help copy/u],
    [{ review_status_copy_valid: false }, /direct-distribution help copy differs from the current/u],
    [{ review_status_rendered_text_ready: false }, /direct-distribution help copy is not actually drawn/u],
    [{ review_status_visible_rect_ready: false }, /direct-distribution help copy live/u],
    [{ review_status_opaque: false }, /direct-distribution help copy is transparent/u],
    [{ price_visible: false }, /price fallback is not visible/u],
    [{ price_text: '$4.99' }, /direct-distribution fallback/u],
    [{ price_expected_text: '$4.99' }, /direct-distribution fallback/u],
    [{
      price_text: '$4.99',
      price_expected_text: '$4.99',
    }, /direct-distribution fallback/u],
    [{ price_copy_valid: false }, /price fallback differs from the current/u],
    [{ price_rendered_text_ready: false }, /price fallback is not actually drawn/u],
    [{ price_visible_rect_ready: false }, /price fallback live/u],
    [{ price_opaque: false }, /price fallback is transparent/u],
    [{ portrait_visible: false }, /portrait/u],
    [{ portrait_visible_rect_ready: false }, /portrait live/u],
    [{ portrait_opaque: false }, /portrait is transparent/u],
    [{ hero_resource_path: 'res://resources/heroes/keeper.tres' }, /hero resource/u],
    [{ portrait_resource_path: 'res://assets/custom/actors/heroes/keeper/portrait.png' }, /portrait resource/u],
    [{ portrait_product_specific: false }, /exclusive to that product/u],
    [{ action_visible: false }, /action button/u],
    [{ action_enabled: true }, /buy button is enabled/u],
    [{ action_text: 'Equip' }, /buy-button copy/u],
    [{ action_expected_text: 'Equip' }, /buy-button copy/u],
    [{ action_text: 'Equip', action_expected_text: 'Equip' }, /buy-button copy/u],
    [{ action_text_nonempty: false }, /buy button copy is empty/u],
    [{ action_copy_valid: false }, /buy button copy differs from the current/u],
    [{ action_font_size_positive: false }, /buy button font size/u],
    [{ action_font_alpha_readable: false }, /buy button glyphs are transparent/u],
    [{ action_rendered_text_ready: false }, /buy button glyphs are not actually drawn/u],
    [{ action_visible_rect_ready: false }, /buy button live/u],
    [{ action_opaque: false }, /buy button is transparent/u],
    [{ restore_visible: false }, /restore button/u],
    [{ restore_enabled: true }, /restore button is enabled/u],
    [{ restore_text: 'Restoring' }, /restore-button copy/u],
    [{ restore_expected_text: 'Restoring' }, /restore-button copy/u],
    [{
      restore_text: 'Restoring',
      restore_expected_text: 'Restoring',
    }, /restore-button copy/u],
    [{ restore_text_nonempty: false }, /restore button copy is empty/u],
    [{ restore_copy_valid: false }, /restore button copy differs from the current/u],
    [{ restore_font_size_positive: false }, /restore button font size/u],
    [{ restore_font_alpha_readable: false }, /restore button glyphs are transparent/u],
    [{ restore_rendered_text_ready: false }, /restore button glyphs are not actually drawn/u],
    [{ restore_visible_rect_ready: false }, /restore button live/u],
    [{ restore_opaque: false }, /restore button is transparent/u],
    [{ card_fully_inside_viewport: false }, /fully/u],
    [{ card_inside_screen: false }, /outside the live screen/u],
  ]) {
    assert.throws(
      () => assertStoreCaptureState(
        storeCaptureState('iap_review', overrides),
        heroExpected,
      ),
      pattern,
    );
  }

  for (const product of IAP_PRODUCTS.filter(({ product_id: productId }) => (
    productId.endsWith('.supporter') || productId.endsWith('.lantern_colors')
  ))) {
    const supporter = product.product_id.endsWith('.supporter');
    const reviewTitle = supporter ? '달빛 후원자' : '봉화 색상 꾸러미';
    const artworkKind = supporter
      ? 'supporter_app_icon'
      : 'lantern_palette_flames';
    const artworkCount = supporter ? 1 : 4;
    const state = storeCaptureState('iap_review', {
      product_id: product.product_id,
      title_text: reviewTitle,
      title_expected_text: reviewTitle,
      portrait_visible: false,
      artwork_visible: true,
      artwork_node_present: true,
      artwork_kind: artworkKind,
      artwork_expected_kind: artworkKind,
      artwork_item_count: artworkCount,
      artwork_expected_item_count: artworkCount,
      artwork_textures_ready: true,
      artwork_visible_rect_ready: true,
      artwork_opaque: true,
      artwork_product_specific: true,
    });
    const expected = {
      kind: 'iap_review',
      gameLocale: 'ko',
      productId: product.product_id,
    };
    assert.equal(assertStoreCaptureState(state, expected).artwork_visible, true);
    assert.throws(
      () => assertStoreCaptureState(
        { ...state, artwork_visible: false },
        expected,
      ),
      /artwork/u,
    );
    for (const [field, value] of [
      ['artwork_node_present', false],
      ['artwork_kind', 'description_label'],
      ['artwork_item_count', 0],
      ['artwork_textures_ready', false],
      ['artwork_visible_rect_ready', false],
      ['artwork_opaque', false],
      ['artwork_product_specific', false],
    ]) {
      assert.throws(
        () => assertStoreCaptureState({ ...state, [field]: value }, expected),
        /artwork|Artwork|texture|area/u,
      );
    }
  }

  for (const product of IAP_PRODUCTS.filter(({ product_id: productId }) => (
    productId.includes('.continue_coin')
  ))) {
    const suffix = product.product_id.split('.').at(-1);
    const reviewTitle = IAP_REVIEW_TITLE_BY_SUFFIX[suffix];
    const state = storeCaptureState('iap_review', {
      product_id: product.product_id,
      title_text: reviewTitle,
      title_expected_text: reviewTitle,
      portrait_visible: false,
      artwork_visible: false,
      artwork_node_present: false,
    });
    const expected = {
      kind: 'iap_review',
      gameLocale: 'ko',
      productId: product.product_id,
    };
    assert.equal(assertStoreCaptureState(state, expected).product_id, product.product_id);
    assert.throws(
      () => assertStoreCaptureState(
        { ...state, artwork_visible: true },
        expected,
      ),
      /coin card/u,
    );
  }
});

test('store-state before/after stability allows only a newer observation of the same nonce', () => {
  const expected = { kind: 'field_guardian', gameLocale: 'ko' };
  const before = storeCaptureState('field_guardian');
  const stable = assertStableStoreCaptureState(
    before,
    { ...before, observation: 2 },
    expected,
  );
  assert.equal(stable.nonce, NONCE_A);
  assert.equal(stable.observation, 1);
  assert.equal(stable.observation_after, 2);
  const animatedStable = assertStableStoreCaptureState(
    before,
    {
      ...before,
      observation: 2,
      guardian_root_effective_alpha: 0.995,
      guardian_sprite_effective_alpha: 0.999,
      guardian_current_animation: 'windup_cross',
      guardian_current_frame: 1,
      guardian_frame_texture_path:
        'res://assets/custom/actors/guardians/field_windup_cross.png',
    },
    expected,
  );
  assert.equal(animatedStable.guardian_current_animation, 'move');
  assert.equal(animatedStable.guardian_current_frame, 0);
  assert.equal(animatedStable.observation_after, 2);
  assert.throws(
    () => assertStableStoreCaptureState(
      before,
      { ...before, nonce: NONCE_B, observation: 2 },
      expected,
    ),
    /nonce/u,
  );
  assert.throws(
    () => assertStableStoreCaptureState(
      before,
      { ...before, observation: 1 },
      expected,
    ),
    /new runtime observation/u,
  );
  assert.throws(
    () => assertStableStoreCaptureState(
      before,
      { ...before, observation: 2, guardian_name: 'changed Guardian' },
      expected,
    ),
    /across the screenshot/u,
  );

  const barrageExpected = { kind: 'moonlight_barrage', gameLocale: 'ko' };
  const barrageBefore = storeCaptureState('moonlight_barrage');
  const barrageStable = assertStableStoreCaptureState(
    barrageBefore,
    {
      ...barrageBefore,
      observation: 2,
      missile_visual_probe_count: 2,
      missile_effective_alpha: 0.995,
      visible_enemy_sprite_count: 4,
    },
    barrageExpected,
  );
  assert.equal(barrageStable.missile_visual_probe_count, 1);
  assert.equal(barrageStable.visible_enemy_sprite_count, 3);
  assert.equal(barrageStable.observation_after, 2);
});

test('published evidence requires per-locale 05/06/02 and 10 sale IAP state_guards', () => {
  const locales = [
    { asset: 'ko-KR', game: 'ko', heroPath: KEEPER },
    { asset: 'en-US', game: 'en', heroPath: KEEPER },
  ];
  const captures = [];
  for (const [index, locale] of locales.entries()) {
    const localeState = {
      game_locale: locale.game,
      nonce: String(index + 1).padStart(64, '0'),
      observation_after: 2,
    };
    const root = `builds/shots/store-localized/${locale.asset}`;
    captures.push(
      {
        source: `${root}/04-title.png`,
        asset_locale: locale.asset,
        game_locale: locale.game,
        kind: 'title',
        state_guard: storeCaptureState('title', localeState),
      },
      {
        source: `${root}/01-moonlight-barrage.png`,
        asset_locale: locale.asset,
        game_locale: locale.game,
        kind: 'combat',
        state_guard: storeCaptureState('moonlight_barrage', localeState),
      },
      {
        source: `${root}/05-moonlit-shrine.png`,
        asset_locale: locale.asset,
        game_locale: locale.game,
        kind: 'shrine',
        state_guard: storeCaptureState('shrine', localeState),
      },
      {
        source: `${root}/06-hero-preview.png`,
        asset_locale: locale.asset,
        game_locale: locale.game,
        kind: 'hero-preview',
        state_guard: storeCaptureState('hero_preview', localeState),
      },
      {
        source: `${root}/02-field-guardian.png`,
        asset_locale: locale.asset,
        game_locale: locale.game,
        kind: 'combat',
        state_guard: storeCaptureState('field_guardian', localeState),
      },
    );
  }
  for (const [index, product] of IAP_PRODUCTS.entries()) {
    const artwork = product.product_id.endsWith('.supporter')
      || product.product_id.endsWith('.lantern_colors');
    const consumable = product.product_id.includes('.continue_coin');
    captures.push({
      source: `builds/shots/store-localized/ko-KR/iap-review/${product.output}`,
      asset_locale: 'ko-KR',
      game_locale: 'ko',
      kind: 'iap-review',
      product_id: product.product_id,
      state_guard: storeCaptureState('iap_review', {
        nonce: (index + 10).toString(16).padStart(64, '0'),
        observation_after: 2,
        product_id: product.product_id,
        portrait_visible: !artwork && !consumable,
        artwork_visible: artwork,
        ...(consumable ? { artwork_node_present: false } : {}),
        ...(artwork ? {
          artwork_node_present: true,
          artwork_kind: product.product_id.endsWith('.supporter')
            ? 'supporter_app_icon'
            : 'lantern_palette_flames',
          artwork_expected_kind: product.product_id.endsWith('.supporter')
            ? 'supporter_app_icon'
            : 'lantern_palette_flames',
          artwork_item_count: product.product_id.endsWith('.supporter') ? 1 : 4,
          artwork_expected_item_count: product.product_id.endsWith('.supporter') ? 1 : 4,
          artwork_textures_ready: true,
          artwork_visible_rect_ready: true,
          artwork_opaque: true,
          artwork_product_specific: true,
        } : {}),
      }),
    });
  }

  assert.equal(assertStoreCaptureProofs(captures, locales, IAP_PRODUCTS), true);
  assert.throws(
    () => assertStoreCaptureProofs(captures.slice(1), locales, IAP_PRODUCTS),
    /exactly 1 image/u,
  );
  assert.throws(
    () => assertStoreCaptureProofs(captures, locales, IAP_PRODUCTS.slice(0, 6)),
    /10 sale products/u,
  );
  const swappedProducts = IAP_PRODUCTS.map((product) => ({ ...product }));
  [swappedProducts[0].output, swappedProducts[1].output] = [
    swappedProducts[1].output,
    swappedProducts[0].output,
  ];
  assert.throws(
    () => assertStoreCaptureProofs(captures, locales, swappedProducts),
    /product contract/u,
  );

  const previewIndex = captures.findIndex(
    (capture) => capture.source.endsWith('/06-hero-preview.png'),
  );
  const wrongPreview = captures.map((capture, index) => index === previewIndex
    ? {
        ...capture,
        state_guard: {
          ...capture.state_guard,
          hero_path: 'res://resources/heroes/dancer.tres',
        },
      }
    : capture);
  assert.throws(
    () => assertStoreCaptureProofs(wrongPreview, locales, IAP_PRODUCTS),
    /hero path/u,
  );

  const eclipse = IAP_PRODUCTS.find((product) => product.product_id.endsWith('.hero_eclipse'));
  const eclipseIndex = captures.findIndex(
    (capture) => capture.product_id === eclipse.product_id,
  );
  const clippedIap = captures.map((capture, index) => index === eclipseIndex
    ? {
        ...capture,
        state_guard: {
          ...capture.state_guard,
          card_fully_inside_viewport: false,
        },
      }
    : capture);
  assert.throws(
    () => assertStoreCaptureProofs(clippedIap, locales, IAP_PRODUCTS),
    /fully/u,
  );

  const mislabeledIap = captures.map((capture, index) => index === eclipseIndex
    ? {
        ...capture,
        state_guard: {
          ...capture.state_guard,
          product_id: IAP_PRODUCTS[0].product_id,
        },
      }
    : capture);
  assert.throws(
    () => assertStoreCaptureProofs(mislabeledIap, locales, IAP_PRODUCTS),
    /product ID/u,
  );
});

test('returns exit 0 only when capture and settings restore both succeed', () => {
  assert.equal(captureProcessExitCode({
    captureSucceeded: true,
    restorationFailures: 0,
  }), 0);
  assert.equal(captureProcessExitCode({
    captureSucceeded: false,
    restorationFailures: 0,
  }), 1);
  assert.equal(captureProcessExitCode({
    captureSucceeded: true,
    restorationFailures: 1,
  }), 1);
  assert.equal(captureProcessExitCode({
    captureSucceeded: false,
    restorationFailures: 2,
  }), 1);
  assert.throws(
    () => captureProcessExitCode({
      captureSucceeded: true,
      restorationFailures: -1,
    }),
    /restore failure count/u,
  );
});

test('publishes capture files and evidence last only after restore also succeeds', () => {
  const blockedEvents = [];
  assert.equal(commitCaptureArtifacts({
    captureSucceeded: true,
    restorationFailures: 1,
    pendingFiles: [{ path: 'new.png' }],
    evidence: { path: 'partial.json' },
    commitFile: (entry) => blockedEvents.push(`file:${entry.path}`),
    commitEvidence: (entry) => blockedEvents.push(`evidence:${entry.path}`),
  }), false);
  assert.deepEqual(blockedEvents, []);

  const events = [];
  assert.equal(commitCaptureArtifacts({
    captureSucceeded: true,
    restorationFailures: 0,
    pendingFiles: [{ path: 'one.png' }, { path: 'two.png' }],
    evidence: { path: 'partial.json' },
    commitFile: (entry) => events.push(`file:${entry.path}`),
    commitEvidence: (entry) => events.push(`evidence:${entry.path}`),
  }), true);
  assert.deepEqual(events, [
    'file:one.png',
    'file:two.png',
    'evidence:partial.json',
  ]);

  const failedCommitEvents = [];
  assert.throws(
    () => commitCaptureArtifacts({
      captureSucceeded: true,
      restorationFailures: 0,
      pendingFiles: [{ path: 'broken.png' }],
      evidence: { path: 'must-not-publish.json' },
      commitFile: () => {
        failedCommitEvents.push('file');
        throw new Error('disk full');
      },
      commitEvidence: () => failedCommitEvents.push('evidence'),
    }),
    /disk full/u,
  );
  assert.deepEqual(failedCommitEvents, ['file']);
});

test('on directory exchange failure keeps the previous canonical generation byte-exact', () => {
  const oldCanonical = Buffer.from('old-valid-phone-generation');
  let canonical = Buffer.from(oldCanonical);
  let staging = Buffer.from('new-complete-phone-generation');
  assert.throws(() => publishCaptureDirectoryAtomically({
    stagingRoot: '/captures/.staging-new',
    canonicalRoot: '/captures/store-localized',
    canonicalExists: true,
    exchangeDirectories: () => {
      throw new Error('injected atomic exchange failure');
    },
    isStagedGenerationAt: (root) => root === '/captures/.staging-new',
    renameDirectory: () => assert.fail('rename must not run'),
    removeOldGeneration: () => assert.fail('cleanup must not run'),
  }), /exchange failure/u);
  assert.deepEqual(canonical, oldCanonical);
  assert.equal(staging.toString(), 'new-complete-phone-generation');

  assert.equal(publishCaptureDirectoryAtomically({
    stagingRoot: '/captures/.staging-new',
    canonicalRoot: '/captures/store-localized',
    canonicalExists: true,
    exchangeDirectories: () => {
      [staging, canonical] = [canonical, staging];
    },
    isStagedGenerationAt: (root) => (
      root === '/captures/store-localized'
        ? canonical.toString() === 'new-complete-phone-generation'
        : staging?.toString() === 'new-complete-phone-generation'
    ),
    renameDirectory: () => assert.fail('rename must not run'),
    removeOldGeneration: () => { staging = null; },
  }), 'exchange');
  assert.equal(canonical.toString(), 'new-complete-phone-generation');
  assert.equal(staging, null);
});

test('helper-exit error after exchange confirms the new canonical and recovers', () => {
  let canonical = Buffer.from('old-valid-phone-generation');
  let staging = Buffer.from('new-complete-phone-generation');
  const result = publishCaptureDirectoryAtomically({
    stagingRoot: '/captures/.staging-new',
    canonicalRoot: '/captures/store-localized',
    canonicalExists: true,
    exchangeDirectories: () => {
      [staging, canonical] = [canonical, staging];
      throw new Error('helper interrupted after atomic syscall');
    },
    isStagedGenerationAt: (root) => (
      root === '/captures/store-localized'
        ? canonical.toString() === 'new-complete-phone-generation'
        : staging?.toString() === 'new-complete-phone-generation'
    ),
    renameDirectory: () => assert.fail('rename must not run'),
    removeOldGeneration: () => { staging = null; },
  });
  assert.equal(result, 'exchange-recovered');
  assert.equal(canonical.toString(), 'new-complete-phone-generation');
  assert.equal(staging, null);
});

test('staging I/O failure does not call directory publish, keeping canonical', () => {
  const canonical = Buffer.from('old-valid-phone-generation');
  let publishCalls = 0;
  assert.throws(() => {
    throw new Error('injected staging disk full');
  }, /disk full/u);
  assert.equal(publishCalls, 0);
  assert.equal(canonical.toString(), 'old-valid-phone-generation');
});

test('skips stale null focus and picks the last valid foreground', () => {
  const packageName = 'com.crossplatformkorea.moonlitbeacon';
  const output = [
    '  mCurrentFocus=null',
    `  mFocusedApp=ActivityRecord{old u0 ${packageName}/Old t402}`,
    `  mCurrentFocus=Window{live u0 ${packageName}/GodotAppLauncher}`,
    `  mFocusedApp=ActivityRecord{new u0 ${packageName}/GodotAppLauncher t403}`,
  ].join('\n');
  assert.equal(foregroundSignalsShowPackage(output, packageName), true);
});

test('prefers current focus over resumed/focused fallback', () => {
  const packageName = 'com.crossplatformkorea.moonlitbeacon';
  assert.equal(foregroundSignalsShowPackage([
    `mFocusedApp=ActivityRecord{old u0 ${packageName}/GodotAppLauncher}`,
    `topResumedActivity=ActivityRecord{old u0 ${packageName}/GodotAppLauncher}`,
    'mCurrentFocus=Window{live u0 com.android.settings/.Settings}',
  ].join('\n'), packageName), false);
  assert.equal(foregroundSignalsShowPackage([
    'mCurrentFocus=null',
    `mResumedActivity=ActivityRecord{live u0 ${packageName}/GodotAppLauncher}`,
  ].join('\n'), packageName), true);
});

test('rejects similar package names and empty foreground signals', () => {
  const packageName = 'com.crossplatformkorea.moonlitbeacon';
  assert.equal(foregroundSignalsShowPackage(
    `mCurrentFocus=Window{u0 ${packageName}.preview/GodotAppLauncher}`,
    packageName,
  ), false);
  assert.equal(foregroundSignalsShowPackage(
    'mCurrentFocus=null\nmFocusedApp=none',
    packageName,
  ), false);
});

test('capture output rejects paths outside the dedicated tree and symbolic links', () => {
  const root = mkdtempSync(join(tmpdir(), 'moonlit-capture-boundary-'));
  try {
    const repository = join(root, 'repo');
    const captureRoot = join(repository, 'builds/shots/store-localized');
    const outside = join(root, 'outside');
    mkdirSync(join(repository, 'builds/shots'), { recursive: true });
    mkdirSync(outside);
    assert.equal(
      assertSafeCaptureOutputPath(
        join(captureRoot, 'en-US/title.png'),
        { repositoryRoot: repository, captureRoot },
      ),
      join(captureRoot, 'en-US/title.png'),
    );
    writeFileSync(join(outside, 'victim.png'), 'external victim');
    symlinkSync(outside, captureRoot);

    assert.throws(
      () => assertSafeCaptureOutputPath(
        join(captureRoot, 'victim.png'),
        { repositoryRoot: repository, captureRoot },
      ),
      /symbolic link/u,
    );
    assert.throws(
      () => assertSafeCaptureOutputPath(
        join(repository, 'builds/shots/other.png'),
        { repositoryRoot: repository, captureRoot },
      ),
      /outside the repository dedicated path/u,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('capture APK build attestation binds APK, runtime, and inputs together', () => {
  const attestation = {
    schema: 1,
    apk_sha256: HASH_A,
    runtime_sha256: HASH_B,
    input_sha256: {
      'apps/game/project.godot': HASH_C,
      'scripts/capture-store-screenshots.mjs': HASH_A,
    },
  };
  const current = {
    apkSha256: HASH_A,
    runtimeSha256: HASH_B,
    inputSha256: {
      'scripts/capture-store-screenshots.mjs': HASH_A,
      'apps/game/project.godot': HASH_C,
    },
  };
  assert.equal(
    assertCaptureBuildAttestationCurrent(attestation, current),
    true,
  );
  for (const [field, value, pattern] of [
    ['apkSha256', HASH_C, /APK/u],
    ['runtimeSha256', HASH_C, /runtime/u],
    [
      'inputSha256',
      { ...current.inputSha256, 'apps/game/scenes/new.tscn': HASH_B },
      /input/u,
    ],
  ]) {
    assert.throws(
      () => assertCaptureBuildAttestationCurrent(
        attestation,
        { ...current, [field]: value },
      ),
      pattern,
    );
  }
});

test('capture and derived generator bind Android debug APK build inputs together', () => {
  const captureSource = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const generatorSource = readFileSync(
    new URL(
      '../../apps/game/tools/build_store_graphics.py',
      import.meta.url,
    ),
    'utf8',
  );
  for (const input of CAPTURE_BUILD_INPUTS) {
    const quoted = `'${input}'`;
    const pythonQuoted = `"${input}"`;
    assert.match(captureSource, new RegExp(
      quoted.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&'),
      'u',
    ), `capture attestation requires ${input}`);
    assert.match(generatorSource, new RegExp(
      pythonQuoted.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&'),
      'u',
    ), `derived generator fingerprint requires ${input}`);
  }
  assert.match(
    captureSource,
    /const CAPTURE_CHILD_ENV = credentialFreeChildEnvironment\(process\.env\);/u,
  );
  assert.equal(
    [...captureSource.matchAll(/env: CAPTURE_CHILD_ENV/g)].length,
    5,
    'the shared run and all four direct adb spawns must use a credential-free environment',
  );
  assert.equal(
    captureSource.includes('env: process.env'),
    false,
    'must not pass the full parent environment to capture child processes',
  );
});

test('Pixel capture and Python gate fingerprint file sets match both ways', () => {
  const captureSource = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const captureBlock = captureSource.match(
    /const CAPTURE_INPUTS = \[([\s\S]*?)\n\];/u,
  );
  assert.ok(captureBlock, 'must be able to find the Pixel CAPTURE_INPUTS array');
  const captureInputs = [...captureBlock[1].matchAll(
    /^\s*'([^']+)',\s*$/gmu,
  )].map((match) => match[1]).sort();
  assert.ok(captureInputs.includes('scripts/lib/android-capture-signing.mjs'));

  const pythonRunner = fileURLToPath(
    new URL('../python.mjs', import.meta.url),
  );
  const generator = fileURLToPath(
    new URL('../../apps/game/tools/build_store_graphics.py', import.meta.url),
  );
  const probe = [
    'import importlib.util, json, sys',
    'from unittest.mock import patch',
    'spec = importlib.util.spec_from_file_location("store_graphics", sys.argv[1])',
    'module = importlib.util.module_from_spec(spec)',
    'spec.loader.exec_module(module)',
    // This check compares only the input *set* of the two implementations. Requiring files
    // the build generates, like .build_version, would fail a clean CI checkout.
    'with patch("pathlib.Path.read_bytes", return_value=b"fingerprint-input"):',
    '    print(json.dumps(sorted(module._source_fingerprints())))',
  ].join('\n');
  const result = spawnSync(
    process.execPath,
    [pythonRunner, '-B', '-c', probe, generator],
    { encoding: 'utf8' },
  );
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.deepEqual(JSON.parse(result.stdout), captureInputs);
});

test('uses the explicit Godot launcher once and falls back to monkey only on failure', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const launcherStart = source.indexOf('function startGameLauncher()');
  const restartStart = source.indexOf('async function restartTitle()', launcherStart);
  const launcherSource = source.slice(launcherStart, restartStart);
  const restartEnd = source.indexOf('async function waitForArena(', restartStart);
  const restartSource = source.slice(restartStart, restartEnd);
  const explicit = launcherSource.indexOf('LAUNCHER_COMPONENT');
  const monkey = launcherSource.indexOf("'monkey'", explicit);
  const failure = launcherSource.indexOf(
    'failed to launch the title with the explicit launcher and monkey',
    monkey,
  );
  const startCall = restartSource.indexOf('startGameLauncher();');
  const foreground = restartSource.indexOf('foregroundIsGame()', startCall);
  assert.ok(
    explicit >= 0 && monkey > explicit && failure > monkey
      && startCall >= 0 && foreground > startCall,
    'must use monkey only after explicit launcher failure and re-prove live foreground',
  );
  assert.equal(
    [...launcherSource.matchAll(/'monkey'/gu)].length,
    1,
    'must not kill a slow cold start by relaunching',
  );
  assert.match(
    source,
    /com\.godot\.game\.GodotAppLauncher/u,
    'must name the actual Godot export launcher activity',
  );
});

test('installs the APK only after the emulator is online again after a long build', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const build = source.indexOf("run('pnpm', ['android:build']");
  const wait = source.indexOf("await waitForCaptureDeviceOnline('APK install')", build);
  const install = source.indexOf("adbRun(['install', '-r', CAPTURE_APK_PATH]", wait);
  assert.ok(
    build >= 0 && wait > build && install > wait,
    'must re-check live device state after Godot export, then install',
  );
  assert.match(
    source,
    /run\(adb, \['-s', serial, 'reconnect'\]\)/u,
    'must reconnect only the chosen offline transport and not touch other devices',
  );
  assert.equal(source.includes("['reconnect', 'offline']"), false);
});

test('title ready is judged by live UI runtime proof, not PNG size', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const restartStart = source.indexOf('async function restartTitle()');
  const restartEnd = source.indexOf('async function waitForArena(', restartStart);
  const restartSource = source.slice(restartStart, restartEnd);
  assert.match(restartSource, /TITLE_RUNTIME_READY_PROOF/u);
  assert.match(restartSource, /foregroundIsGame\(\)/u);
  assert.match(restartSource, /pngSize\(frame, 'title readiness frame'\)/u);
  assert.equal(
    /frame\.length\s*[<>]=?\s*[0-9_]+/u.test(restartSource),
    false,
    'must not use PNG byte size, which varies with art compression, as readiness',
  );

  const launcherSource = readFileSync(
    new URL('../../apps/game/scripts/dev/test_launcher.gd', import.meta.url),
    'utf8',
  );
  assert.match(launcherSource, /store_capture_title_runtime\.ready/u);
  assert.match(launcherSource, /ready\.store_string\("title-ready\\n"\)/u);
  const frameLoop = launcherSource.indexOf('for _frame in range(4):');
  const insideTreeGuard = launcherSource.indexOf(
    'if not is_inside_tree():', frameLoop,
  );
  const treeSnapshot = launcherSource.indexOf(
    'var tree: SceneTree = get_tree()', frameLoop,
  );
  const treeLifetimeGuard = launcherSource.indexOf('if tree == null:', treeSnapshot);
  const frameWait = launcherSource.indexOf('await tree.process_frame', treeLifetimeGuard);
  const screenCheck = launcherSource.indexOf('screen.is_visible_in_tree()', frameLoop);
  const versionCheck = launcherSource.indexOf('version.text != expected_version', frameLoop);
  const proofWrite = launcherSource.indexOf('ready.store_string("title-ready\\n")');
  assert.ok(
    frameLoop >= 0
      && insideTreeGuard > frameLoop
      && treeSnapshot > insideTreeGuard
      && treeLifetimeGuard > treeSnapshot
      && frameWait > treeLifetimeGuard
      && screenCheck > frameLoop
      && versionCheck > screenCheck
      && proofWrite > versionCheck,
    'must confirm live title UI and version after four game-loop frames',
  );
  assert.equal(
    launcherSource.includes('await RenderingServer.frame_post_draw'),
    false,
    'must not bring back the frame_post_draw await that rarely stalls on Android',
  );
  const releaseGuard = launcherSource.indexOf('if not OS.is_debug_build():');
  const signal = launcherSource.indexOf('_signal_store_capture_title_ready()', releaseGuard);
  assert.ok(releaseGuard >= 0 && signal > releaseGuard, 'must use proof only after the release guard');
});

test('arena ready and meaning capture use nonce runtime proof instead of PNG size', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const arenaStart = source.indexOf('async function waitForArena(');
  const arenaEnd = source.indexOf('function readPrivateFile(', arenaStart);
  const arenaSource = source.slice(arenaStart, arenaEnd);
  assert.match(arenaSource, /waitForStoreCaptureRuntimeState/u);
  assert.match(arenaSource, /kind: 'arena_ready'/u);
  assert.equal(arenaSource.includes('screencap'), false);
  assert.equal(arenaSource.includes('frame.length'), false);
  assert.match(
    source,
    /\['arena_ready', 'field_guardian'\]\.includes\(expected\.kind\)[\s\S]*\? 90_000[\s\S]*: 30_000/u,
    'must budget enough time for cold arena start and low-FPS Guardian state proof',
  );
  assert.equal(source.includes("? 30_000 : 8_000"), false);

  const captureStart = source.indexOf('async function capture(');
  const captureEnd = source.indexOf('async function captureWithCleanUi(', captureStart);
  const captureSource = source.slice(captureStart, captureEnd);
  assert.match(captureSource, /assertStableStoreCaptureState/u);
  const prepareState = captureSource.indexOf('waitForStoreCaptureRuntimeState(');
  const armCleanUi = captureSource.indexOf('armCleanUiCapture(cleanUiKind);');
  const waitCleanUi = captureSource.indexOf('waitForCleanUiCapture(cleanUiKind);', armCleanUi);
  const screencap = captureSource.indexOf("adbRun(['exec-out', 'screencap', '-p']");
  const preObservation = captureSource.lastIndexOf(
    'waitForStoreCaptureRuntimeObservation(', screencap,
  );
  const postObservation = captureSource.indexOf(
    'waitForStoreCaptureRuntimeObservation(', screencap,
  );
  assert.ok(preObservation >= 0 && postObservation > screencap);
  assert.ok(
    prepareState >= 0
      && armCleanUi > prepareState
      && waitCleanUi > armCleanUi
      && preObservation > waitCleanUi
      && screencap > preObservation,
    'must hide UI after the meaning scene is ready, take a new observation, then capture',
  );
  assert.match(
    captureSource.slice(screencap, postObservation + 450),
    /nonce: stateBefore\.nonce[\s\S]*afterObservation: stateBefore\.observation/u,
  );
  assert.equal(
    captureSource.slice(screencap, postObservation).includes(
      'waitForStoreCaptureRuntimeState(',
    ),
    false,
    'must not create a new prepare/nonce session after screencap',
  );
  assert.match(captureSource, /state_guard/u);
  assert.equal(/bytes\.length\s*[<>]/u.test(captureSource), false);
});

test('phone combat presets start from a boot handshake instead of screen coordinates', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const launchStart = source.indexOf('async function launchCaptureArena(');
  const launchEnd = source.indexOf('\nfunction capturePersistentFilesBeforeFirstLaunch(', launchStart);
  const launchSource = source.slice(launchStart, launchEnd);
  const stop = launchSource.indexOf("'force-stop'");
  const arm = launchSource.indexOf('armStoreCaptureBoot(kind);', stop);
  const start = launchSource.indexOf('startGameLauncher();', arm);
  const ready = launchSource.indexOf('await waitForArena(label, locale);', start);
  assert.ok(stop >= 0 && arm > stop && start > arm && ready > start);
  assert.equal(
    launchSource.indexOf('clearStoreCaptureBootHandshake();', ready),
    -1,
    'must not clear the deferred boot request right after arena_ready',
  );
  assert.match(source, /store_capture_boot\.request\.json/u);
  assert.match(source, /JSON\.stringify\(\{ schema: 1, nonce, kind \}\)/u);
  const mainFinally = source.indexOf('} finally {', source.indexOf('async function main()'));
  assert.ok(
    source.indexOf('clearStoreCaptureBootHandshake();', mainFinally) > mainFinally,
    'top-level cleanup must clear the boot request idempotently',
  );
});

test('shrine, hero, Guardian, and IAP save only after proving live screen state', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const localeStart = source.indexOf('async function captureLocale(');
  const iapStart = source.indexOf('async function captureIapReviews(', localeStart);
  const localeSource = source.slice(localeStart, iapStart);
  for (const kind of [
    'title',
    'shrine',
    'hero_preview',
    'moonlight_barrage',
    'field_guardian',
  ]) {
    assert.match(localeSource, new RegExp(`kind: '${kind}'`, 'u'));
  }
  assert.match(localeSource, /heroPath: HERO_PREVIEW_PATH/u);
  assert.equal(localeSource.includes('keeperHeroCard'), false);
  assert.match(
    localeSource,
    /launchCaptureArena\(\s*'moonlight_barrage'/u,
    'max barrage must open via boot handshake, not coordinates',
  );
  assert.match(
    localeSource,
    /launchCaptureArena\(\s*'field_guardian'/u,
    'Guardian must open via boot handshake, not coordinates',
  );
  assert.doesNotMatch(
    localeSource,
    /POINTS\.(?:level20Cycle3|level10Cycle1|shield|lightThreeBeacons|takeHit)/u,
    'must not bring back combat debug coordinates that break on device aspect',
  );
  const guardianLaunch = localeSource.lastIndexOf("'field_guardian'");
  const guardianProof = localeSource.indexOf(
    "{ stateExpected: { kind: 'field_guardian' } }",
    guardianLaunch,
  );
  const guardianRoute = localeSource.slice(guardianLaunch, guardianProof);
  assert.ok(guardianRoute.length > 0, 'must find the field Guardian capture route');
  assert.equal(
    guardianRoute.includes('sleep('),
    false,
    'must not spend Guardian alive-time on a fixed wait',
  );
  assert.equal(
    guardianRoute.includes('stageGuardian'),
    false,
    'first-party ready state must place the Guardian instead of a manual coordinate tap',
  );

  const iapEnd = source.indexOf('function inputFingerprints(', iapStart);
  const iapSource = source.slice(iapStart, iapEnd);
  assert.match(iapSource, /kind: 'iap_review'/u);
  assert.match(iapSource, /productId: product\.product_id/u);
  assert.equal(iapSource.includes('internalSwipe'), false);
  assert.equal(iapSource.includes('scroll_by'), false);
  assert.match(source, /assertStoreCaptureProofs\(captures, LOCALES, IAP_REVIEW_PRODUCTS\)/u);
});

test('runtime probe and per-screen debug state are not enabled in release', () => {
  const probe = readFileSync(
    new URL('../../apps/game/scripts/dev/store_capture_probe.gd', import.meta.url),
    'utf8',
  );
  assert.match(probe, /if not OS\.is_debug_build\(\)/u);
  assert.match(probe, /store_capture_runtime\.request\.json/u);
  assert.match(probe, /store_capture_runtime\.state\.json/u);
  assert.match(
    probe,
    /ALLOWED_KINDS[\s\S]*"hero_direction"/u,
    'hero facing matrix must be a runtime probe request, not a boot boost',
  );
  assert.match(probe, /state\["nonce"\] = nonce/u);
  assert.match(probe, /state\["observation"\] = _observation/u);
  assert.match(
    probe,
    /if (?:kind != "direct_distribution" and )?not _ready_latched \\\s+and scene\.has_method\("debug_prepare_store_capture"\)/u,
    'after first ready, only observe without prepare',
  );
  assert.match(probe, /if bool\(state\.get\("ready", false\)\):\s*_ready_latched = true/u);
  assert.equal(
    probe.includes('DirAccess.remove_absolute(ProjectSettings.globalize_path(REQUEST_PATH))'),
    false,
    'must keep the same request until the host receives the post-screencap observation',
  );
  const writeStateStart = probe.indexOf('static func _write_state(');
  const writeState = probe.slice(writeStateStart);
  assert.ok(writeStateStart >= 0, 'must find the runtime probe state writer');
  assert.match(writeState, /DirAccess\.rename_absolute\(/u);
  assert.doesNotMatch(
    writeState,
    /DirAccess\.remove_absolute\(ProjectSettings\.globalize_path\(STATE_PATH\)\)/u,
    'must not delete the destination immediately before atomic rename and create an unobservable gap',
  );

  const arena = readFileSync(
    new URL('../../apps/game/scripts/gameplay/arena.gd', import.meta.url),
    'utf8',
  );
  const prepareStart = arena.indexOf('func debug_prepare_store_capture(');
  const prepareEnd = arena.indexOf('func debug_store_capture_state(', prepareStart);
  const prepare = arena.slice(prepareStart, prepareEnd);
  assert.match(prepare, /OS\.is_debug_build\(\)/u);
  assert.match(prepare, /kind == "hero_direction"/u);
  assert.match(prepare, /_debug_hold_hero_direction_capture\(\)/u);
  assert.match(prepare, /field_guardian/u);
  assert.match(prepare, /debug_stage_guardian\(\)/u);

  const player = readFileSync(
    new URL('../../apps/game/scripts/actors/player.gd', import.meta.url),
    'utf8',
  );
  const playerCaptureStart = player.indexOf(
    'func debug_set_direction_capture_vfx_suppressed(',
  );
  const playerCaptureEnd = player.indexOf('\nfunc ', playerCaptureStart + 1);
  const playerCapture = player.slice(playerCaptureStart, playerCaptureEnd);
  assert.match(playerCapture, /if not OS\.is_debug_build\(\):\s*return/u);
  assert.match(player, /func dash\([\s\S]*_debug_direction_capture_vfx_suppressed/u);

  const shop = readFileSync(
    new URL('../../apps/game/scripts/ui/iap_shop_panel.gd', import.meta.url),
    'utf8',
  );
  const shopPrepareStart = shop.indexOf('func debug_prepare_store_capture(');
  const shopPrepareEnd = shop.indexOf('func debug_store_capture_state(', shopPrepareStart);
  const shopPrepare = shop.slice(shopPrepareStart, shopPrepareEnd);
  assert.match(shopPrepare, /_capture_selected_product_id = product_id/u);
  assert.match(shopPrepare, /_coins_scroll[\s\S]+IapStore\.is_consumable/u);
  assert.match(shopPrepare, /scroll\.scroll_horizontal =/u);
  assert.equal(
    /(?:price|action|_restore|_status)\.(?:text|disabled)\s*=/u.test(shopPrepare),
    false,
    'IAP capture prepare must not overwrite live price, status, or purchasability',
  );

  const summonStart = arena.indexOf('func _summon_guardian(');
  const summonEnd = arena.indexOf('\nfunc ', summonStart + 1);
  const summon = arena.slice(summonStart, summonEnd);
  assert.match(summon, /var guardian_path: String = _guardian_resource_path\(\)/u);
  const guardianPathStart = arena.indexOf('func _guardian_resource_path(');
  const guardianPathEnd = arena.indexOf('\nfunc ', guardianPathStart + 1);
  const guardianPath = arena.slice(guardianPathStart, guardianPathEnd);
  assert.ok(guardianPathStart >= 0, 'must find the Guardian path-selection helper');
  assert.match(
    guardianPath,
    /var step: Dictionary = _world_step\(\)/u,
    'Guardian selection must come from the biome world step',
  );
  assert.match(
    guardianPath,
    /str\(step\["guardian"\]\)/u,
    'without a promotion roster it must fall back to the biome default Guardian',
  );
  assert.match(
    summon,
    /_guardian\.set_meta\(GUARDIAN_KIND_SOURCE_PATH_META, guardian_path\)/u,
    'must bind the chosen Guardian source path to the live Guardian node before cloning',
  );

  for (const path of [
    '../../apps/game/scripts/dev/test_launcher.gd',
    '../../apps/game/scripts/dev/arena_tools.gd',
  ]) {
    const script = readFileSync(new URL(path, import.meta.url), 'utf8');
    const guard = script.indexOf('if not OS.is_debug_build():');
    const poll = script.indexOf('STORE_CAPTURE_PROBE.poll');
    assert.ok(guard >= 0 && poll > guard, `${path} probe must sit after the debug guard`);
  }
});

test('auto device discovery still picks only Pixel_10 when other-project AVDs exist', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const discoverStart = source.indexOf('function discoverEmulator(');
  const discoverEnd = source.indexOf('function installedApkSha256(', discoverStart);
  const discoverSource = source.slice(discoverStart, discoverEnd);
  assert.match(discoverSource, /emu', 'avd', 'name'/u);
  assert.match(discoverSource, /avdName === 'Pixel_10'/u);
  assert.match(discoverSource, /pixelTenRows\.length !== 1/u);
  assert.equal(
    discoverSource.includes('rows.length !== 1'),
    false,
    'must not fail only because another project emulator is also running',
  );
});

test('missile-core capture state proves translation, banner, power, and the physical core together', () => {
  const valid = missileCoreState();
  assert.deepEqual(
    assertMissileCoreCaptureState(valid, { gameLocale: 'ko' }),
    valid,
  );
  for (const [overrides, pattern] of [
    [{ schema: 2 }, /schema/u],
    [{ kind: 'moon_ember' }, /kind/u],
    [{ scene: 'title' }, /arena/u],
    [{ level: 20 }, /Lv10/u],
    [{ cycle: 3 }, /cycle 1/u],
    [{ zone_index: 2 }, /first biome/u],
    [{ terrain_path: 'res://resources/rooms/camp.tres' }, /night forest/u],
    [{ world_key: 'WORLD_CAMP' }, /biome cycle/u],
    [{ time_key: 'TIME_DAY' }, /time of day/u],
    [{ applied_time_tone: [1.55, 1.38, 1.12, 1] }, /Night tone/u],
    [{ time_tone_applied: false }, /background tone/u],
    [{ game_locale: 'en' }, /locale/u],
    [{ banner_key: 'EMBER_COLLECTED' }, /banner key/u],
    [{ actual_banner_text: 'Moon ember 1\/10' }, /banner copy/u],
    [{ banner_visible: false }, /visible frozen state/u],
    [{ banner_locked: false }, /visible frozen state/u],
    [{ missile_power_after: 6 }, /one step/u],
    [{ ejected_cores_outstanding: 0 }, /stray missile core/u],
    [{ core_capture_paused: false }, /paused/u],
    [{ ejected_core_count: 2 }, /exactly one/u],
    [{ core_visible_in_tree: false }, /live tree/u],
    [{ core_effective_alpha: 0 }, /transparent/u],
    [{ core_opaque: false }, /opaque/u],
    [{ core_onscreen: false }, /live screen/u],
    [{ core_texture_path: 'res://icon.svg' }, /power_gem/u],
    [{ core_texture_matches: false }, /identity/u],
    [{ core_visible_draw_rect_positive: false }, /draw rect/u],
  ]) {
    assert.throws(
      () => assertMissileCoreCaptureState(
        missileCoreState(overrides),
        { gameLocale: 'ko' },
      ),
      pattern,
    );
  }
});

test('pins missile-core evidence only when both sides of the screenshot match', () => {
  const before = missileCoreState();
  assert.deepEqual(
    assertStableMissileCoreCaptureState(before, { ...before }, { gameLocale: 'ko' }),
    before,
  );
  assert.throws(
    () => assertStableMissileCoreCaptureState(
      before,
      missileCoreState({ missile_power_before: 7, missile_power_after: 6 }),
      { gameLocale: 'ko' },
    ),
    /across the screenshot/u,
  );
});

test('published evidence requires 03 state proofs for every requested locale', () => {
  const locales = [
    { asset: 'ko-KR', game: 'ko' },
    { asset: 'en-US', game: 'en' },
  ];
  const captures = locales.map((locale) => ({
    source: `builds/shots/store-localized/${locale.asset}/03-missile-core-drop.png`,
    asset_locale: locale.asset,
    game_locale: locale.game,
    kind: 'combat',
    capture_guard: {
      ...missileCoreState({ game_locale: locale.game }),
      asset_locale: locale.asset,
    },
  }));
  assert.equal(assertMissileCoreCaptureProofs(captures, locales), true);
  assert.throws(
    () => assertMissileCoreCaptureProofs(captures.slice(0, 1), locales),
    /proof count/u,
  );
  assert.throws(
    () => assertMissileCoreCaptureProofs([
      captures[0],
      {
        ...captures[1],
        capture_guard: {
          ...captures[1].capture_guard,
          actual_banner_text: 'Embers 1/10',
        },
      },
    ], locales),
    /banner copy/u,
  );
});

test('core-drop capture waits on game state and before/after stability instead of a fixed delay', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const coreDrop = source.indexOf('`${locale.asset} core drop`');
  const boot = source.lastIndexOf("'missile_core'", coreDrop);
  const armed = source.indexOf('armMissileCoreCapture,', boot);
  const ready = source.indexOf('await waitForMissileCoreCaptureState(', armed);
  const capture = source.indexOf('/03-missile-core-drop.png', ready);
  const coreDropEnd = source.indexOf('// Guardian is cycle 3 again', capture);
  assert.ok(
    coreDrop >= 0
      && boot >= 0
      && armed > coreDrop
      && ready > armed
      && capture > ready,
    'boot handshake must prove live missile-core reclaim state before shooting',
  );
  const coreDropSource = source.slice(coreDrop, coreDropEnd);
  assert.equal(coreDropSource.includes('await sleep(4200);'), false);
  assert.equal(coreDropSource.includes('await sleep(260);'), false);
  assert.equal(coreDropSource.includes('internalTap(POINTS.takeHit)'), false);
  assert.match(coreDropSource, /captureGuard: readyState/u);
  assert.match(source, /assertStableMissileCoreCaptureState/u);
  assert.match(
    source,
    /async function waitForMissileCoreCaptureState[\s\S]*const timeoutMs = 30_000/u,
    'must wait after arena ready through a live hit and deferred core attach',
  );
  const tryStart = source.lastIndexOf('try {', armed);
  assert.ok(
    tryStart >= 0 && tryStart < boot,
    'missile handshake arm itself must sit inside finally cleanup even if it fails',
  );
  const mainFinally = source.indexOf('} finally {', source.indexOf('async function main()'));
  assert.ok(
    mainFinally > 0
      && source.indexOf('clearMissileCoreCaptureHandshake();', mainFinally) > mainFinally,
    'top-level restore must also clear the missile handshake idempotently',
  );
});

test('partial finalizer joins only the exact contract original and paths inside the capture root', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const start = source.indexOf('function expectedLocaleCaptureSources(');
  const end = source.indexOf('async function main()', start);
  const finalizer = source.slice(start, end);
  for (const file of [
    '01-moonlight-barrage.png',
    '02-field-guardian.png',
    '03-missile-core-drop.png',
    '04-title.png',
    '05-moonlit-shrine.png',
    '06-hero-preview.png',
  ]) {
    assert.match(finalizer, new RegExp(file.replace('.', '\\.'), 'u'));
  }
  assert.match(finalizer, /expectedSources\.has\(sourceName\)/u);
  assert.match(finalizer, /seenSources\.has\(sourceName\)/u);
  assert.match(
    finalizer,
    /assertSafeCapturePath\(resolve\(REPO_ROOT, sourceName\)\)/u,
  );
});

test('every screencap checks live game foreground immediately before and after', () => {
  const source = readFileSync(
    new URL('../capture-store-screenshots.mjs', import.meta.url),
    'utf8',
  );
  const captureStart = source.indexOf('function capture(');
  const captureEnd = source.indexOf('async function captureLocale(', captureStart);
  const captureSource = source.slice(captureStart, captureEnd);
  const screencap = captureSource.indexOf("adbRun(['exec-out', 'screencap', '-p']");
  const foregroundChecks = [
    ...captureSource.matchAll(/foregroundIsGame\(\)/gu),
  ].map((match) => match.index);
  assert.equal(foregroundChecks.length, 3);
  assert.ok(
    foregroundChecks[1] < screencap && foregroundChecks[2] > screencap,
    'must check foreground on both sides of the actual screencap',
  );
  const preGateEnd = captureSource.indexOf('\n    }', foregroundChecks[1]) + 6;
  assert.ok(preGateEnd >= 4, 'must find the end of the immediate-before-foreground check block');
  const beforeScreencap = captureSource.slice(preGateEnd, screencap);
  assert.equal(
    /(?:adbRun|await |readPrivateFile|assertInstalledCaptureApk)/u.test(beforeScreencap),
    false,
    'must have no other external calls between the immediate-before-foreground check and screencap',
  );
});

test('capture APK build attestation rejects weak hashes and escaped paths', () => {
  const current = {
    apkSha256: HASH_A,
    runtimeSha256: HASH_B,
    inputSha256: { 'apps/game/project.godot': HASH_C },
  };
  assert.throws(
    () => assertCaptureBuildAttestationCurrent(
      {
        schema: 1,
        apk_sha256: 'short',
        runtime_sha256: HASH_B,
        input_sha256: current.inputSha256,
      },
      current,
    ),
    /SHA-256/u,
  );
  assert.throws(
    () => assertCaptureBuildAttestationCurrent(
      {
        schema: 1,
        apk_sha256: HASH_A,
        runtime_sha256: HASH_B,
        input_sha256: { '../outside': HASH_C },
      },
      current,
    ),
    /input path/u,
  );
});

test('installed APK proof must match live base.apk hashes immediately before and after capture', () => {
  assert.equal(
    assertInstalledCaptureApkCurrent(HASH_A, HASH_A),
    HASH_A,
  );
  assert.throws(
    () => assertInstalledCaptureApkCurrent(HASH_A, HASH_B),
    /Installed base\.apk/u,
  );
  assert.throws(
    () => assertInstalledCaptureApkCurrent(HASH_A, 'weak'),
    /SHA-256/u,
  );
});
