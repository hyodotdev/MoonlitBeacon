#!/usr/bin/env python3
"""Build Moonlit Beacon store graphics deterministically from existing custom art.

Tracked production files:

    notes/release/store-assets/play/icon-512.png
    notes/release/store-assets/play/feature-graphic-1024x500.png
    notes/release/store-assets/iap/moonlit-supporter-512.png
    notes/release/store-assets/iap/hero-bundle-512.png
    notes/release/store-assets/iap/lantern-colors-512.png
    notes/release/store-assets/iap/hero-{dancer,keeper,knight,eclipse,sage}-512.png

Device screenshots are built for Google Play and the App Store with
``--screenshots``, and for Google Play only from Android device proofs with
``--play-screenshots``.
Do not stretch the original game screen or overlay shapes on debug UI. Crop
only the specified bottom region and place it on a per-store night-sky
marketing canvas while keeping aspect ratio.
Play feature graphics and every screenshot are 24-bit RGB PNGs with no alpha.
App and IAP icons are RGBA PNGs with no transparent pixels.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import ctypes
import hashlib
import importlib.util
import io
import json
import math
import os
import plistlib
import posixpath
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unicodedata
import zipfile
import zlib
from pathlib import Path
from types import ModuleType
from typing import Iterable


GAME_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
STORE_ROOT = REPO_ROOT / "notes/release/store-assets"
SCREENSHOT_MANIFEST = STORE_ROOT / "screenshots.json"
SCREENSHOT_CAPTURE_REPORT = (
    REPO_ROOT / "builds/shots/store-localized/capture-report.json"
)
DEVICE_CAPTURE_ROOT = REPO_ROOT / "builds/shots/store-platform"
PLAY_SCREENSHOT_OUTPUT = REPO_ROOT / "builds/release/play"
STALE_PLAY_SCREENSHOT_OUTPUT = PLAY_SCREENSHOT_OUTPUT / "screenshots"
APP_STORE_SCREENSHOT_OUTPUT = REPO_ROOT / "builds/release/app-store"
APP_STORE_SCREENSHOT_PROVENANCE_NAME = "screenshot-provenance.json"
APP_STORE_SCREENSHOT_PROVENANCE_CONTRACT = (
    "moonlit-app-store-screenshot-provenance-v1"
)
APP_STORE_IPHONE_SOURCE_PHYSICAL = "physical-ios"
APP_STORE_IPHONE_SOURCE_ANDROID_AVD = "android-pixel-avd"
APP_STORE_IPHONE_SOURCE_MODES = (
    APP_STORE_IPHONE_SOURCE_PHYSICAL,
    APP_STORE_IPHONE_SOURCE_ANDROID_AVD,
)
IAP_REVIEW_SOURCE_ROOT = (
    REPO_ROOT / "builds/shots/store-localized/ko-KR/iap-review"
)
IAP_REVIEW_OUTPUT_ROOT = APP_STORE_SCREENSHOT_OUTPUT / "iap-review"
STALE_IAP_REVIEW_SOURCE = (
    REPO_ROOT / "builds/shots/store-localized/ko-KR/iap-review.png"
)
STALE_IAP_REVIEW_OUTPUT = APP_STORE_SCREENSHOT_OUTPUT / "iap-review.png"
RELEASE_OUTPUT_ROOT = REPO_ROOT / "builds/release"
SCREENSHOT_SOURCE_SIZE = (2424, 1080)
SCREENSHOT_LOCALES = ("en-US", "ko-KR", "ja-JP", "zh-Hans", "zh-Hant")
GAME_LOCALES = {
    "en-US": "en",
    "ko-KR": "ko",
    "ja-JP": "ja",
    "zh-Hans": "zh_CN",
    "zh-Hant": "zh_TW",
}
MARKETING_TEXT_LANGUAGES = {
    "en-US": "en",
    "ko-KR": "ko",
    "ja-JP": "ja",
    "zh-Hans": "zh-cn",
    "zh-Hant": "zh-tw",
}
MARKETING_SHAPING_PROBE = "骨直返令"
PLAY_LOCALES = {
    "en-US": "en-US",
    "ko-KR": "ko-KR",
    "ja-JP": "ja-JP",
    "zh-Hans": "zh-CN",
    "zh-Hant": "zh-TW",
}
APP_STORE_LOCALES = {
    "en-US": "en-US",
    "ko-KR": "ko",
    "ja-JP": "ja",
    "zh-Hans": "zh-Hans",
    "zh-Hant": "zh-Hant",
}
STALE_APP_STORE_LOCALES = ("ko-KR", "ja-JP")
SCENE_CROP_BOTTOM = {
    "combat": 180,
    "title": 90,
    "shrine": 0,
    "hero-preview": 0,
}
MARKETING_FONT = (
    GAME_ROOT / "assets/third_party/fonts/NotoSansCJKsc-Regular.otf"
)
CAPTURE_DEBUG_APK = (
    REPO_ROOT / "builds/shots/store-localized/capture-debug.apk"
)
BRAND_LABELS = {
    "en-US": "MOONLIT BEACON",
    "ko-KR": "Moonlit Beacon",
    "ja-JP": "月明かりの烽火",
    "zh-Hans": "月光烽火",
    "zh-Hant": "月光烽火",
}
APP_STORE_FORMATS = {
    "iphone-6.5": {
        "display_type": "APP_IPHONE_65",
        "size": (2778, 1284),
        "header": 160,
        "footer": 70,
        "margin": 24,
        "font_size": 52,
        "brand_size": 28,
        "border": 6,
    },
    "ipad-13": {
        "display_type": "APP_IPAD_PRO_3GEN_129",
        "size": (2732, 2048),
        "header": 230,
        "footer": 120,
        "margin": 32,
        "font_size": 66,
        "brand_size": 36,
        "border": 8,
    },
}
PLAY_TABLET_FORMATS = {
    "seven-inch-tablet": {
        "size": (1920, 1080),
    },
    "ten-inch-tablet": {
        "size": (2560, 1440),
    },
}
IAP_REVIEW_PRODUCT_IDS = (
    "com.crossplatformkorea.moonlitbeacon.hero_dancer",
    "com.crossplatformkorea.moonlitbeacon.hero_keeper",
    "com.crossplatformkorea.moonlitbeacon.hero_knight",
    "com.crossplatformkorea.moonlitbeacon.hero_eclipse",
    "com.crossplatformkorea.moonlitbeacon.hero_sage",
    "com.crossplatformkorea.moonlitbeacon.supporter",
    "com.crossplatformkorea.moonlitbeacon.lantern_colors",
    "com.crossplatformkorea.moonlitbeacon.continue_coin",
    "com.crossplatformkorea.moonlitbeacon.continue_coin_5",
    "com.crossplatformkorea.moonlitbeacon.continue_coin_10",
)
IAP_REVIEW_OUTPUT_BY_PRODUCT = {
    "com.crossplatformkorea.moonlitbeacon.hero_dancer": "hero-dancer.png",
    "com.crossplatformkorea.moonlitbeacon.hero_keeper": "hero-keeper.png",
    "com.crossplatformkorea.moonlitbeacon.hero_knight": "hero-knight.png",
    "com.crossplatformkorea.moonlitbeacon.hero_eclipse": "hero-eclipse.png",
    "com.crossplatformkorea.moonlitbeacon.hero_sage": "hero-sage.png",
    "com.crossplatformkorea.moonlitbeacon.supporter": "supporter.png",
    "com.crossplatformkorea.moonlitbeacon.lantern_colors": "lantern-colors.png",
    "com.crossplatformkorea.moonlitbeacon.continue_coin": "continue-coin.png",
    "com.crossplatformkorea.moonlitbeacon.continue_coin_5": "continue-coin-5.png",
    "com.crossplatformkorea.moonlitbeacon.continue_coin_10": "continue-coin-10.png",
}
IAP_REVIEW_TITLE_BY_PRODUCT = {
    "com.crossplatformkorea.moonlitbeacon.supporter": "달빛 후원자",
    "com.crossplatformkorea.moonlitbeacon.hero_dancer": "그림자 무희",
    "com.crossplatformkorea.moonlitbeacon.hero_keeper": "봉화지기",
    "com.crossplatformkorea.moonlitbeacon.hero_knight": "백월 기사",
    "com.crossplatformkorea.moonlitbeacon.hero_eclipse": "월식 마도사",
    "com.crossplatformkorea.moonlitbeacon.hero_sage": "성좌 현자",
    "com.crossplatformkorea.moonlitbeacon.lantern_colors": "봉화 색상 꾸러미",
    "com.crossplatformkorea.moonlitbeacon.continue_coin": "이어하기 코인",
    "com.crossplatformkorea.moonlitbeacon.continue_coin_5": "이어하기 코인 5개",
    "com.crossplatformkorea.moonlitbeacon.continue_coin_10": "이어하기 코인 10개",
}
IAP_REVIEW_FALLBACK_PRICE_TEXT = "기기 스토어 전용"
IAP_REVIEW_FALLBACK_STATUS_TEXT = (
    "실제 가격과 구매는 App Store·Google Play에서 확인할 수 있습니다"
)
IAP_REVIEW_BUY_TEXT = "구매"
IAP_REVIEW_RESTORE_TEXT = "구매 복원"
SCREENSHOT_CONTRACTS = {
    "01-moonlight-barrage.png": {
        "scene": "combat", "crop_bottom": 180,
        "labels": {
            "en-US": "UNLEASH A STORM OF HOMING MOONLIGHT",
            "ko-KR": "추적하는 달빛 탄막을 펼치세요",
            "ja-JP": "追尾する月光の弾幕を解き放て",
            "zh-Hans": "释放追踪敌人的月光弹幕",
            "zh-Hant": "釋放追蹤敵人的月光彈幕",
        },
    },
    "02-field-guardian.png": {
        "scene": "combat", "crop_bottom": 180,
        "labels": {
            "en-US": "THREE BEACONS • A DIFFERENT GUARDIAN",
            "ko-KR": "봉화 셋 뒤에는 지형별 수호자",
            "ja-JP": "3つの烽火・地形ごとの守護者",
            "zh-Hans": "点燃三座烽火，挑战地形守护者",
            "zh-Hant": "點燃三座烽火，挑戰地形守護者",
        },
    },
    "03-missile-core-drop.png": {
        "scene": "combat", "crop_bottom": 180,
        "labels": {
            "en-US": "TAKE A HIT • RECLAIM YOUR MISSILE CORE",
            "ko-KR": "피격하면 떨어진 미사일 코어를 되찾으세요",
            "ja-JP": "被弾で落としたミサイルコアを取り戻せ",
            "zh-Hans": "受伤后，夺回掉落的导弹核心",
            "zh-Hant": "受傷後，奪回掉落的飛彈核心",
        },
    },
    "04-title.png": {
        "scene": "title", "crop_bottom": 90,
        "labels": {
            "en-US": "LIGHT THE BEACONS • OUTLAST THE NIGHT",
            "ko-KR": "봉화를 밝히고 밤을 버티세요",
            "ja-JP": "烽火を灯し、夜を生き抜け",
            "zh-Hans": "点燃烽火，熬过长夜",
            "zh-Hant": "點燃烽火，撐過長夜",
        },
    },
    "05-moonlit-shrine.png": {
        "scene": "shrine", "crop_bottom": 0,
        "labels": {
            "en-US": "CHOOSE YOUR MOONLIT HERO",
            "ko-KR": "나만의 달빛 영웅을 선택하세요",
            "ja-JP": "月明かりの英雄を選ぼう",
            "zh-Hans": "选择你的月光英雄",
            "zh-Hant": "選擇你的月光英雄",
        },
    },
    "06-hero-preview.png": {
        "scene": "hero-preview", "crop_bottom": 0,
        "labels": {
            "en-US": "PREVIEW EACH HERO BEFORE YOU CHOOSE",
            "ko-KR": "선택 전에 영웅 모습을 확인하세요",
            "ja-JP": "選ぶ前に英雄をプレビュー",
            "zh-Hans": "选择前预览每位英雄",
            "zh-Hant": "選擇前預覽每位英雄",
        },
    },
}
STORE_CAPTURE_HERO_PATH = "res://resources/heroes/keeper.tres"
# Detail screen places both images at integer multiples of their native size. Header icon slot
# (48x48) uses a 2x scale of the idle sheet's 24x24 crop; large slot (96x96) uses the 96x96 portrait
# 1:1. Previously this was inverted, so the large image was 4x upscaled and the small one 0.5x downscaled.
STORE_CAPTURE_HERO_PORTRAIT_PATH = (
    "res://assets/custom/actors/heroes/keeper/idle.png"
)
STORE_CAPTURE_HERO_BODY_PATH = (
    "res://assets/custom/actors/heroes/keeper/portrait.png"
)
STORE_CAPTURE_HERO_NAME_SOURCE_KEY = "HERO_KEEPER_NAME"
STORE_CAPTURE_HERO_DESCRIPTION_SOURCE_KEY = "HERO_KEEPER_DESC"
STORE_CAPTURE_HERO_STATE_SOURCE_KEYS = (
    "SHRINE_SELECTED",
    "SHRINE_OWNED",
    "HERO_PREVIEW_IAP_LOCKED",
)
STORE_CAPTURE_HERO_COPY = {
    "ko": {
        "name": "봉화지기",
        "description": (
            "하트 6칸 · 이속 -15% · 피해 +25% · 대시 쿨 +30% · "
            "달빛 파문·질긴 목숨"
        ),
        "states": {
            "SHRINE_SELECTED": "선택 중",
            "SHRINE_OWNED": "해금됨",
            "HERO_PREVIEW_IAP_LOCKED": "잠김 · 기기 스토어에서 구매",
        },
    },
    "en": {
        "name": "Beacon Keeper",
        "description": (
            "6 hearts · move -15% · dmg +25% · dash CD +30% · "
            "Moonlit Ripple/Tenacious Life"
        ),
        "states": {
            "SHRINE_SELECTED": "Selected",
            "SHRINE_OWNED": "Unlocked",
            "HERO_PREVIEW_IAP_LOCKED": (
                "Locked · purchase in device store"
            ),
        },
    },
    "ja": {
        "name": "烽火の守り人",
        "description": (
            "ハート6 · 移速 -15% · ダメージ +25% · ダッシュCD +30% · "
            "月光の波紋・不屈の命"
        ),
        "states": {
            "SHRINE_SELECTED": "選択中",
            "SHRINE_OWNED": "解放済み",
            "HERO_PREVIEW_IAP_LOCKED": "未購入 · 端末ストアで購入",
        },
    },
    "zh_CN": {
        "name": "烽火守护者",
        "description": (
            "6颗心 · 移速 -15% · 伤害 +25% · 冲刺冷却 +30% · "
            "月光波纹·坚韧生命"
        ),
        "states": {
            "SHRINE_SELECTED": "已选择",
            "SHRINE_OWNED": "已解锁",
            "HERO_PREVIEW_IAP_LOCKED": "未购买 · 在设备商店购买",
        },
    },
    "zh_TW": {
        "name": "烽火守護者",
        "description": (
            "6顆心 · 移速 -15% · 傷害 +25% · 衝刺冷卻 +30% · "
            "月光波紋·堅韌生命"
        ),
        "states": {
            "SHRINE_SELECTED": "已選擇",
            "SHRINE_OWNED": "已解鎖",
            "HERO_PREVIEW_IAP_LOCKED": "未購買 · 在裝置商店購買",
        },
    },
}
STORE_CAPTURE_CAMP_TERRAIN_PATH = "res://resources/rooms/camp.tres"
STORE_CAPTURE_FIELD_TERRAIN_PATH = "res://resources/rooms/field.tres"
# Allow both the base form and the evolved storm form. Capture Settings cycle 3 times, so the shot
# actually shows the storm form; this gate blocks a guardian from a **different world** appearing
# in the field cut, not a stronger form of the same field guardian.
STORE_CAPTURE_FIELD_GUARDIAN_PATHS = (
    "res://resources/guardian_field.tres",
    "res://resources/guardian_field_storm.tres",
)
STORE_CAPTURE_FIELD_GUARDIAN_TEXTURE_PATHS = (
    "res://assets/custom/actors/guardians/field.png",
    "res://assets/custom/actors/guardians/field_windup_cross.png",
    "res://assets/custom/actors/guardians/field_windup_radial.png",
    "res://assets/custom/actors/guardians/field_recover.png",
    "res://assets/custom/actors/guardians/field_storm.png",
    "res://assets/custom/actors/guardians/field_storm_windup_cross.png",
    "res://assets/custom/actors/guardians/field_storm_windup_radial.png",
    "res://assets/custom/actors/guardians/field_storm_recover.png",
)
STORE_CAPTURE_TITLE_COPY = {
    "ko": {
        "title": "달빛 봉화", "subtitle": "밤을 밝히는 마지막 불빛",
        "tap": "화면을 탭하여 시작", "settings": "설정",
        "shrine": "제단", "ladder": "순위", "store": "상점",
    },
    "en": {
        "title": "MOONLIT BEACON", "subtitle": "OUTLAST THE NIGHT",
        "tap": "Tap to start", "settings": "Settings",
        "shrine": "Shrine", "ladder": "Ranks", "store": "Store",
    },
    "ja": {
        "title": "月明かりの烽火", "subtitle": "夜を照らす最後の灯",
        "tap": "画面をタップして開始", "settings": "設定",
        "shrine": "祭壇", "ladder": "順位", "store": "ストア",
    },
    "zh_CN": {
        "title": "月光烽火", "subtitle": "照亮长夜的最后火光",
        "tap": "点击屏幕开始", "settings": "设置",
        "shrine": "祭坛", "ladder": "排名", "store": "商店",
    },
    "zh_TW": {
        "title": "月光烽火", "subtitle": "照亮長夜的最後火光",
        "tap": "點擊畫面開始", "settings": "設定",
        "shrine": "祭壇", "ladder": "排名", "store": "商店",
    },
}
STORE_CAPTURE_TITLE_FOREST_SCENE_PATH = (
    "res://scenes/gameplay/night_forest.tscn"
)
STORE_CAPTURE_TITLE_FOREST_GROUND_PATH = (
    "res://assets/custom/world/terrain/forest_floor.png"
)
STORE_CAPTURE_TITLE_VIGNETTE_NODE_CLASS = "Sprite2D"
STORE_CAPTURE_TITLE_VIGNETTE_TEXTURE_CLASS = "GradientTexture2D"
STORE_CAPTURE_TITLE_VIGNETTE_TEXTURE_UNIQUE_ID = "GradientTexture2D_vignette"
STORE_CAPTURE_TITLE_BEACON_SCENE_PATH = "res://scenes/objectives/beacon.tscn"
STORE_CAPTURE_TITLE_BEACON_CLEARING_PATH = (
    "res://assets/custom/world/beacon/clearing.png"
)
STORE_CAPTURE_IAP_HERO_VISUALS = {
    "com.crossplatformkorea.moonlitbeacon.hero_dancer": (
        "res://resources/heroes/dancer.tres",
        "res://assets/custom/actors/heroes/dancer/portrait.png",
    ),
    "com.crossplatformkorea.moonlitbeacon.hero_keeper": (
        "res://resources/heroes/keeper.tres",
        "res://assets/custom/actors/heroes/keeper/portrait.png",
    ),
    "com.crossplatformkorea.moonlitbeacon.hero_knight": (
        "res://resources/heroes/knight.tres",
        "res://assets/custom/actors/heroes/knight/portrait.png",
    ),
    "com.crossplatformkorea.moonlitbeacon.hero_eclipse": (
        "res://resources/heroes/eclipse.tres",
        "res://assets/custom/actors/heroes/eclipse/portrait.png",
    ),
    "com.crossplatformkorea.moonlitbeacon.hero_sage": (
        "res://resources/heroes/sage.tres",
        "res://assets/custom/actors/heroes/sage/portrait.png",
    ),
}
STORE_CAPTURE_NIGHT_TONE = [1.0, 1.0, 1.0, 1.0]
STORE_CAPTURE_DAY_TONE = [1.55, 1.38, 1.12, 1.0]
STORE_CAPTURE_COLOR_COMPONENT_TOLERANCE = 1e-6
STORE_CAPTURE_RECT_TOLERANCE = 0.51
STORE_CAPTURE_GUARDIAN_FOCUS_POSITION = (0.22, 0.24)
STORE_CAPTURE_GUARDIAN_FOCUS_SIZE = (0.56, 0.64)
STORE_CAPTURE_GUARDIAN_MIN_PLAYER_SEPARATION = 72.0
JAVASCRIPT_MAX_SAFE_INTEGER = 9_007_199_254_740_991
STORE_CAPTURE_TITLE_SAFE_CONTROLS = (
    "title",
    "subtitle",
    "version",
    "tap_prompt",
    "settings_button",
    "shrine_button",
    "ladder_button",
    "store_button",
)
STORE_CAPTURE_TITLE_DIRECT_SAFE_CONTROLS = tuple(
    control for control in STORE_CAPTURE_TITLE_SAFE_CONTROLS
    if control != "store_button"
)
STORE_CAPTURE_ARENA_SAFE_CONTROLS = (
    "hud_left",
    "hud_right",
    "pause_button",
    "dash",
    "move_stick",
    "boss",
    "banner",
)
DEVICE_CAPTURE_SCREENSHOT_KINDS = {
    "01-moonlight-barrage.png": "moonlight_barrage",
    "02-field-guardian.png": "field_guardian",
    "03-missile-core-drop.png": "missile_core_recovery",
    "04-title.png": "title",
    "05-moonlit-shrine.png": "shrine",
    "06-hero-preview.png": "hero_preview",
}
DEVICE_CAPTURE_TARGETS = {
    "seven-inch-tablet": {
        "platform": "android",
        "avd_name": "Moonlit_7_API36",
        "source_size": (1024, 600),
        "density_dpi": 160,
        "api_level": 36,
        "abi_type": "arm64-v8a",
        "image_sysdir": (
            "system-images/android-36/google_apis_playstore/arm64-v8a/"
        ),
        "hw_device_name": "7in WSVGA (Tablet)",
        "config_size": (1024, 600),
    },
    "ten-inch-tablet": {
        "platform": "android",
        "avd_name": "Moonlit_10_API36",
        "source_size": (1280, 800),
        "density_dpi": 160,
        "api_level": 36,
        "abi_type": "arm64-v8a",
        "image_sysdir": (
            "system-images/android-36/google_apis_playstore/arm64-v8a/"
        ),
        "hw_device_name": "10.1in WXGA (Tablet)",
        "config_size": (1280, 800),
    },
    "iphone-6.5": {
        "platform": "ios",
        "model_prefix": "iPhone",
    },
    "ipad-13": {
        "platform": "ios",
        "model_prefix": "iPad",
    },
}
ANDROID_PHONE_CAPTURE_CONTRACT = {
    "platform": "android",
    "avd_name": "Pixel_10",
    "source_size": SCREENSHOT_SOURCE_SIZE,
    "density_dpi": 420,
    "api_level": 34,
    "abi_type": "arm64-v8a",
    "image_sysdir": (
        "system-images/android-34/google_apis_playstore/arm64-v8a/"
    ),
    "hw_device_name": "pixel_9",
    "config_size": (1080, 2424),
}
ANDROID_CAPTURE_PERSISTENT_FILES = (
    "analytics.json",
    "analytics.json.tmp",
    "analytics_consent.revoked",
    "iap_entitlements.cfg",
    "iap_entitlements.cfg.bak",
    "iap_entitlements.cfg.bak.tmp",
    "iap_entitlements.cfg.tmp",
    "ladder.json",
    "ladder.json.tmp",
    "records.cfg",
    "records.cfg.tmp",
    "settings.cfg",
    "settings.cfg.tmp",
    "test_hero.request",
    "vault.cfg",
    "vault.cfg.bak",
    "vault.cfg.bak.tmp",
    "vault.cfg.tmp",
)
IOS_CAPTURE_PERSISTENT_FILES = ANDROID_CAPTURE_PERSISTENT_FILES
IOS_PRODUCTION_BUNDLE_ID = "com.crossplatformkorea.moonlitbeacon"
IOS_ISOLATED_CAPTURE_BUNDLE_ID = (
    "com.crossplatformkorea.moonlitbeacon.storecapture"
)
IOS_CAPTURE_EXECUTABLE_NAME = "MoonlitBeacon"
ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256 = (
    "9c5cd1cf2822a31e66a1ddacdd4566bae14db2af929ed8d8f20e7c1d74765138"
)
ANDROID_CAPTURE_SIGNATURE_FILENAME = "persistence-signature.jar"
ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY = "capture-report.unsigned.json"
ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY = "persistence-evidence.json"
ANDROID_DEVICE_CAPTURE_SOURCE_INPUTS = (
    "package.json",
    "scripts/capture-android-tablet-evidence.mjs",
    "scripts/android-build.mjs",
    "scripts/godot.mjs",
    "scripts/lib/android-capture-persistence.mjs",
    "scripts/lib/android-capture-signing.mjs",
    "scripts/lib/android-build.mjs",
    "scripts/lib/android-release-signing.mjs",
    "scripts/lib/android-tablet-evidence.mjs",
    "scripts/lib/capture-run-state.mjs",
    "scripts/lib/godot-export-preflight.mjs",
    "scripts/lib/iapkit-config.mjs",
    "scripts/lib/release-environment.mjs",
    "apps/game/project.godot",
    "apps/game/export_presets.cfg",
    "apps/game/android/.build_version",
    "apps/game/android/build/build.gradle",
    "apps/game/android/build/config.gradle",
    "apps/game/android/build/gradle.properties",
    "apps/game/android/build/settings.gradle",
    "apps/game/android/build/gradlew",
    "apps/game/android/build/gradle/wrapper/gradle-wrapper.jar",
    "apps/game/android/build/gradle/wrapper/gradle-wrapper.properties",
    "apps/game/android/build/libs/debug/godot-lib.template_debug.aar",
    "apps/game/android/build/res/values/themes.xml",
    "apps/game/android/build/src/debug/AndroidManifest.xml",
    "apps/game/android/build/src/main/AndroidManifest.xml",
    "apps/game/android/build/src/main/java/com/godot/game/GodotApp.java",
    "apps/game/android/build/src/release/AndroidManifest.xml",
    "apps/game/localization/moonlit.csv",
    "apps/game/scripts/util/screen.gd",
    "apps/game/scripts/dev/store_capture_boot.gd",
    "apps/game/scripts/dev/store_capture_clean_ui.gd",
    "apps/game/scripts/dev/store_capture_probe.gd",
    "apps/game/scripts/dev/test_launcher.gd",
    "apps/game/scripts/dev/arena_tools.gd",
    "apps/game/scripts/ui/title_menu.gd",
    "apps/game/scripts/ui/shrine_panel.gd",
    "apps/game/scripts/ui/hero_preview_panel.gd",
    "apps/game/scripts/gameplay/arena.gd",
    "apps/game/scripts/gameplay/missile_progression.gd",
    "apps/game/scripts/actors/moon_missile.gd",
)
IOS_DEVICE_CAPTURE_SOURCE_INPUTS = (
    "package.json",
    "scripts/capture-ios-device-evidence.mjs",
    "scripts/publish-xcode-screenshot-handoff.mjs",
    "scripts/ios.mjs",
    "scripts/godot.mjs",
    "scripts/lib/capture-run-state.mjs",
    "scripts/lib/godot-export-preflight.mjs",
    "scripts/lib/iapkit-config.mjs",
    "scripts/lib/ios-build.mjs",
    "scripts/lib/ios-device-evidence.mjs",
    "scripts/lib/ios-distribution.mjs",
    "scripts/lib/release-environment.mjs",
    "notes/release/store-assets/screenshots.json",
    "apps/game/project.godot",
    "apps/game/export_presets.cfg",
    "apps/game/localization/moonlit.csv",
    "apps/game/scripts/util/screen.gd",
    "apps/game/scripts/dev/store_capture_boot.gd",
    "apps/game/scripts/dev/store_capture_clean_ui.gd",
    "apps/game/scripts/dev/store_capture_probe.gd",
    "apps/game/scripts/dev/test_launcher.gd",
    "apps/game/scripts/dev/arena_tools.gd",
    "apps/game/scripts/ui/title_menu.gd",
    "apps/game/scripts/ui/shrine_panel.gd",
    "apps/game/scripts/ui/hero_preview_panel.gd",
    "apps/game/scripts/gameplay/arena.gd",
    "apps/game/scripts/gameplay/missile_progression.gd",
    "apps/game/scripts/actors/moon_missile.gd",
)
ANDROID_DEBUG_CAPTURE_INPUTS = (
    "apps/game/android/build/gradlew",
    "apps/game/android/build/gradle/wrapper/gradle-wrapper.jar",
    "apps/game/android/build/gradle/wrapper/gradle-wrapper.properties",
    "apps/game/android/build/libs/debug/godot-lib.template_debug.aar",
    "apps/game/android/build/res/values/themes.xml",
)

RGBA = tuple[int, int, int, int]

NIGHT: RGBA = (11, 14, 28, 255)
NIGHT_MID: RGBA = (18, 25, 50, 255)
NIGHT_LIGHT: RGBA = (29, 40, 78, 255)
OUTLINE: RGBA = (29, 36, 64, 255)
MOON: RGBA = (214, 243, 255, 255)
MOON_MID: RGBA = (117, 207, 224, 255)
MOON_CORE: RGBA = (255, 248, 220, 255)
GOLD: RGBA = (245, 200, 75, 255)
EMBER: RGBA = (238, 124, 70, 255)
VIOLET: RGBA = (188, 131, 238, 255)
JADE: RGBA = (116, 218, 159, 255)

IAP_HERO_ART: dict[str, dict[str, object]] = {
    "dancer": {
        "portrait": "assets/custom/actors/heroes/dancer/portrait.png",
        "panel": (75, 34, 78, 255),
        "accent": (239, 157, 182, 255),
        "secondary": (147, 231, 198, 255),
        "motif": "ribbons",
    },
    "keeper": {
        "portrait": "assets/custom/actors/heroes/keeper/portrait.png",
        "panel": (28, 62, 51, 255),
        "accent": (245, 166, 71, 255),
        "secondary": (255, 224, 138, 255),
        "motif": "lantern",
    },
    "knight": {
        "portrait": "assets/custom/actors/heroes/knight/portrait.png",
        "panel": (61, 76, 107, 255),
        "accent": (195, 232, 255, 255),
        "secondary": (239, 243, 239, 255),
        "motif": "crescent",
    },
    "eclipse": {
        "portrait": "assets/custom/actors/heroes/eclipse/portrait.png",
        "panel": (44, 14, 29, 255),
        "accent": (255, 53, 52, 255),
        "secondary": (255, 126, 72, 255),
        "motif": "eclipse",
    },
    "sage": {
        "portrait": "assets/custom/actors/heroes/sage/portrait.png",
        "panel": (8, 70, 79, 255),
        "accent": (245, 187, 55, 255),
        "secondary": (55, 205, 185, 255),
        "motif": "star",
    },
}


def _assert_safe_repository_path(
    path: Path,
    allowed_root: Path,
    label: str,
) -> None:
    repository = REPO_ROOT.absolute()
    allowed = allowed_root.absolute()
    target = path.absolute()
    try:
        allowed.relative_to(repository)
        target.relative_to(allowed)
        relative_target = target.relative_to(repository)
    except ValueError as error:
        raise RuntimeError(
            f"{label} path is outside the allowed repository scope: {path}"
        ) from error

    current = repository
    for component in (Path(), *relative_target.parts):
        if component != Path():
            current /= component
        if current.is_symlink():
            raise RuntimeError(
                f"{label} path contains a symbolic link: {path}"
            )


def _load_icon_builder() -> ModuleType:
    path = GAME_ROOT / "tools/build_app_icon_assets.py"
    spec = importlib.util.spec_from_file_location("moonlit_app_icon_builder", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot read app icon generator: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


ICON = _load_icon_builder()
Canvas = ICON.Canvas


FONT: dict[str, tuple[str, ...]] = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01111", "10000", "10000", "10000", "10000", "10000", "01111"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "G": ("01111", "10000", "10000", "10111", "10001", "10001", "01111"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("11111", "00100", "00100", "00100", "00100", "00100", "11111"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "11011", "10001"),
    ".": ("00000", "00000", "00000", "00000", "00000", "00110", "00110"),
}


def _rect(canvas: Canvas, x: int, y: int, width: int, height: int, color: RGBA) -> None:
    if width > 0 and height > 0:
        canvas.rect(x, y, x + width - 1, y + height - 1, color)


def _circle(canvas: Canvas, center_x: int, center_y: int, radius: int, color: RGBA) -> None:
    radius_squared = radius * radius
    for y in range(center_y - radius, center_y + radius + 1):
        for x in range(center_x - radius, center_x + radius + 1):
            if (x - center_x) ** 2 + (y - center_y) ** 2 <= radius_squared:
                canvas.pixel(x, y, color)


def _diamond(
    canvas: Canvas,
    center_x: int,
    center_y: int,
    half_width: int,
    half_height: int,
    color: RGBA,
) -> None:
    canvas.polygon(
        (
            (center_x, center_y - half_height),
            (center_x + half_width, center_y),
            (center_x, center_y + half_height),
            (center_x - half_width, center_y),
        ),
        color,
    )


def _border(canvas: Canvas, x: int, y: int, width: int, height: int, color: RGBA, size: int) -> None:
    _rect(canvas, x, y, width, size, color)
    _rect(canvas, x, y + height - size, width, size, color)
    _rect(canvas, x, y, size, height, color)
    _rect(canvas, x + width - size, y, size, height, color)


def _draw_text(
    canvas: Canvas,
    text: str,
    x: int,
    y: int,
    scale: int,
    color: RGBA,
    shadow: RGBA | None = None,
) -> None:
    def draw_at(origin_x: int, origin_y: int, ink: RGBA) -> None:
        cursor = origin_x
        for character in text:
            if character == " ":
                cursor += 4 * scale
                continue
            glyph = FONT.get(character)
            if glyph is None:
                raise RuntimeError(f"character missing from store-graphics bitmap font: {character!r}")
            for row, bits in enumerate(glyph):
                for column, bit in enumerate(bits):
                    if bit == "1":
                        _rect(
                            canvas,
                            cursor + column * scale,
                            origin_y + row * scale,
                            scale,
                            scale,
                            ink,
                        )
            cursor += 6 * scale

    if shadow is not None:
        draw_at(x + max(scale // 2, 2), y + max(scale // 2, 2), shadow)
    draw_at(x, y, color)


def _read_png_rgba(path: Path) -> Canvas:
    data = path.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError(f"not a PNG: {path}")

    offset = 8
    width = 0
    height = 0
    compressed = bytearray()
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        offset += 12 + length
        if kind == b"IHDR":
            width, height, depth, color_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
            if (depth, color_type, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                raise RuntimeError(
                    f"unsupported PNG format: {path} "
                    f"(depth={depth}, color={color_type}, interlace={interlace})"
                )
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break

    raw = zlib.decompress(bytes(compressed))
    stride = width * 4
    rows: list[bytearray] = []
    cursor = 0
    for _ in range(height):
        filter_kind = raw[cursor]
        cursor += 1
        row = bytearray(raw[cursor : cursor + stride])
        cursor += stride
        previous = rows[-1] if rows else bytearray(stride)
        for index in range(stride):
            left = row[index - 4] if index >= 4 else 0
            above = previous[index]
            upper_left = previous[index - 4] if index >= 4 else 0
            if filter_kind == 1:
                row[index] = (row[index] + left) & 0xFF
            elif filter_kind == 2:
                row[index] = (row[index] + above) & 0xFF
            elif filter_kind == 3:
                row[index] = (row[index] + ((left + above) // 2)) & 0xFF
            elif filter_kind == 4:
                predictor = left + above - upper_left
                distance_left = abs(predictor - left)
                distance_above = abs(predictor - above)
                distance_upper_left = abs(predictor - upper_left)
                nearest = (
                    left
                    if distance_left <= distance_above
                    and distance_left <= distance_upper_left
                    else above
                    if distance_above <= distance_upper_left
                    else upper_left
                )
                row[index] = (row[index] + nearest) & 0xFF
            elif filter_kind != 0:
                raise RuntimeError(f"unsupported PNG filter: {filter_kind} ({path})")
        rows.append(row)

    canvas = Canvas(width, height)
    canvas.pixels = bytearray().join(rows)
    return canvas


def _branded_background(width: int, height: int, accent: RGBA) -> Canvas:
    canvas = Canvas(width, height, NIGHT)
    band_height = max(height // 9, 1)
    for index in range(1, 6):
        inset = index * width // 24
        _rect(
            canvas,
            inset,
            index * band_height // 2,
            width - inset * 2,
            height - index * band_height,
            NIGHT_MID if index % 2 else NIGHT_LIGHT,
        )
    for x, y, size in (
        (38, 46, 4),
        (width - 64, 54, 3),
        (72, height - 72, 3),
        (width - 92, height - 88, 4),
        (width // 2, 30, 2),
    ):
        _rect(canvas, x, y, size, size, MOON)
    _border(canvas, 12, 12, width - 24, height - 24, accent, max(width // 128, 3))
    return canvas


def _build_play_icon(main_icon: Canvas) -> Canvas:
    return main_icon.resized_bilinear(512, 512)


def _build_feature_graphic(foreground: Canvas) -> Canvas:
    canvas = _branded_background(1024, 500, GOLD)
    _circle(canvas, 824, 244, 202, OUTLINE)
    _circle(canvas, 824, 244, 184, NIGHT_LIGHT)
    _circle(canvas, 824, 244, 166, (47, 68, 112, 255))
    _circle(canvas, 824, 244, 140, (79, 105, 154, 255))
    for x, y in ((702, 72), (934, 102), (965, 332), (678, 382), (902, 432)):
        _diamond(canvas, x, y, 5, 7, MOON)

    hero = foreground.resized_nearest(430, 430)
    canvas.composite(hero, 609, 32)

    _draw_text(canvas, "MOONLIT", 62, 118, 10, MOON_CORE, OUTLINE)
    _draw_text(canvas, "BEACON", 62, 226, 10, GOLD, OUTLINE)
    _rect(canvas, 64, 324, 432, 5, MOON_MID)
    _draw_text(canvas, "LIGHT. GROW. SURVIVE.", 64, 354, 4, MOON, OUTLINE)
    return canvas


def _build_supporter_icon(foreground: Canvas) -> Canvas:
    canvas = _branded_background(512, 512, GOLD)
    _circle(canvas, 256, 246, 190, OUTLINE)
    _circle(canvas, 256, 246, 174, (48, 62, 102, 255))
    for x, y in ((74, 126), (438, 126), (64, 360), (448, 360), (256, 48)):
        _diamond(canvas, x, y, 7, 10, GOLD)
    canvas.composite(foreground.resized_nearest(400, 400), 56, 42)
    canvas.polygon(
        ((256, 444), (222, 414), (188, 382), (204, 352), (238, 360), (256, 382)),
        EMBER,
    )
    canvas.polygon(
        ((256, 444), (290, 414), (324, 382), (308, 352), (274, 360), (256, 382)),
        EMBER,
    )
    _diamond(canvas, 256, 392, 18, 24, MOON_CORE)
    return canvas


def _build_hero_bundle_icon() -> Canvas:
    canvas = _branded_background(512, 512, MOON_MID)
    portraits = (
        GAME_ROOT / "assets/custom/actors/heroes/dancer/portrait.png",
        GAME_ROOT / "assets/custom/actors/heroes/keeper/portrait.png",
    )
    panel_colors = ((75, 58, 119, 255), (48, 77, 93, 255))
    accents = (VIOLET, GOLD)
    for index, (path, panel, accent) in enumerate(zip(portraits, panel_colors, accents)):
        x = 63 + index * 214
        _rect(canvas, x, 88, 172, 324, OUTLINE)
        _rect(canvas, x + 7, 95, 158, 310, panel)
        _border(canvas, x + 7, 95, 158, 310, accent, 5)
        portrait = _read_png_rgba(path).resized_nearest(168, 168)
        canvas.composite(portrait, x + 2, 164)
        _diamond(canvas, x + 86, 362, 21, 28, accent)
    _rect(canvas, 128, 438, 256, 6, GOLD)
    _diamond(canvas, 256, 441, 18, 18, MOON_CORE)
    return canvas


def _draw_individual_hero_vfx(
    canvas: Canvas,
    motif: str,
    panel: RGBA,
    accent: RGBA,
    secondary: RGBA,
) -> None:
    """Draw each hero's combat fantasy as a readable one-liner under the portrait."""
    if motif == "ribbons":
        # Facing moonlight ribbons. Leave the center open so it does not read as a sword or horns.
        _circle(canvas, 198, 408, 50, accent)
        _circle(canvas, 216, 404, 40, panel)
        _circle(canvas, 314, 408, 50, secondary)
        _circle(canvas, 296, 404, 40, panel)
        for x, y in ((158, 376), (354, 376), (180, 458), (332, 458)):
            _diamond(canvas, x, y, 6, 9, MOON_CORE)
    elif motif == "lantern":
        _circle(canvas, 256, 408, 76, (91, 65, 42, 255))
        _rect(canvas, 220, 342, 72, 12, accent)
        _rect(canvas, 226, 354, 60, 92, OUTLINE)
        _rect(canvas, 234, 362, 44, 76, accent)
        canvas.polygon(
            ((256, 424), (234, 402), (238, 382),
             (256, 394), (274, 382), (278, 402)),
            secondary,
        )
        _rect(canvas, 238, 446, 36, 12, accent)
    elif motif == "crescent":
        _circle(canvas, 256, 408, 70, secondary)
        _circle(canvas, 278, 394, 62, panel)
        _circle(canvas, 244, 420, 12, MOON_CORE)
        for x, y in ((176, 380), (346, 372), (180, 452), (332, 462)):
            _diamond(canvas, x, y, 5, 8, accent)
    elif motif == "eclipse":
        _circle(canvas, 256, 408, 76, accent)
        _circle(canvas, 256, 408, 60, secondary)
        _circle(canvas, 256, 408, 48, (16, 13, 28, 255))
        for x, y in ((256, 332), (256, 476), (180, 408), (332, 408)):
            _diamond(canvas, x, y, 7, 12, accent)
        _diamond(canvas, 256, 408, 8, 12, MOON_CORE)
    else:
        # Thin teal orbit and gold eight-point star. One strong center that still reads at 512px.
        canvas.line((162, 408), (350, 408), secondary)
        canvas.line((184, 370), (328, 446), secondary)
        canvas.line((184, 446), (328, 370), secondary)
        _diamond(canvas, 256, 408, 66, 20, accent)
        _diamond(canvas, 256, 408, 22, 66, accent)
        _diamond(canvas, 256, 408, 28, 28, secondary)
        _diamond(canvas, 256, 408, 12, 12, MOON_CORE)
        for x, y in ((166, 354), (346, 354), (176, 468), (336, 468)):
            _diamond(canvas, x, y, 5, 8, secondary)


def _build_individual_hero_icon(hero_name: str) -> Canvas:
    raw = IAP_HERO_ART[hero_name]
    portrait_path = GAME_ROOT / str(raw["portrait"])
    panel = raw["panel"]
    accent = raw["accent"]
    secondary = raw["secondary"]
    motif = str(raw["motif"])
    if not isinstance(panel, tuple) or not isinstance(accent, tuple) \
            or not isinstance(secondary, tuple):
        raise RuntimeError(f"{hero_name} IAP palette is not an RGBA tuple")
    if not portrait_path.is_file():
        raise RuntimeError(f"{hero_name} IAP portrait is missing: {portrait_path}")

    canvas = _branded_background(512, 512, accent)
    _circle(canvas, 256, 220, 198, OUTLINE)
    _circle(canvas, 256, 220, 184, panel)
    _circle(canvas, 256, 220, 164, NIGHT_LIGHT)
    _circle(canvas, 256, 220, 148, panel)

    # Small VFX stars remain visible behind the portrait so card lists show color at a glance.
    for x, y, color in (
        (84, 126, accent),
        (424, 126, secondary),
        (72, 294, secondary),
        (440, 294, accent),
        (256, 42, MOON_CORE),
    ):
        _diamond(canvas, x, y, 7, 10, color)

    portrait = _read_png_rgba(portrait_path).resized_nearest(320, 320)
    canvas.composite(portrait, 96, 54)
    _draw_individual_hero_vfx(canvas, motif, panel, accent, secondary)
    _border(canvas, 24, 24, 464, 464, secondary, 4)
    return canvas


def _draw_lantern(canvas: Canvas, center_x: int, center_y: int, color: RGBA) -> None:
    glow = tuple((channel + NIGHT_MID[index] * 3) // 4 for index, channel in enumerate(color[:3])) + (255,)
    _circle(canvas, center_x, center_y, 72, glow)
    _diamond(canvas, center_x, center_y, 54, 68, OUTLINE)
    _diamond(canvas, center_x, center_y, 46, 58, color)
    _diamond(canvas, center_x, center_y, 24, 34, MOON_CORE)
    _rect(canvas, center_x - 38, center_y - 78, 76, 12, GOLD)
    _rect(canvas, center_x - 28, center_y + 66, 56, 14, GOLD)
    _rect(canvas, center_x - 15, center_y + 80, 30, 18, OUTLINE)


def _build_lantern_icon() -> Canvas:
    canvas = _branded_background(512, 512, VIOLET)
    _draw_lantern(canvas, 142, 158, EMBER)
    _draw_lantern(canvas, 370, 158, MOON_MID)
    _draw_lantern(canvas, 142, 354, VIOLET)
    _draw_lantern(canvas, 370, 354, JADE)
    _diamond(canvas, 256, 256, 30, 42, GOLD)
    _diamond(canvas, 256, 256, 15, 23, MOON_CORE)
    return canvas


def _alpha_mode(canvas: Canvas) -> str:
    alpha_levels = set(canvas.pixels[3::4])
    if alpha_levels == {255}:
        return "opaque"
    if any(0 < alpha < 255 for alpha in alpha_levels):
        return "graded"
    return "binary"


def _validate_canvas(label: str, canvas: Canvas, width: int, height: int) -> None:
    if (canvas.width, canvas.height) != (width, height):
        raise RuntimeError(
            f"{label} size is {canvas.width}x{canvas.height} "
            f"(contract {width}x{height})"
        )
    if _alpha_mode(canvas) != "opaque":
        raise RuntimeError(f"{label} must be opaque with no transparent pixels")


def _png_chunk(kind: bytes, data: bytes) -> bytes:
    checksum = zlib.crc32(kind + data) & 0xFFFFFFFF
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", checksum)
    )


def _to_rgb_png(canvas: Canvas) -> bytes:
    """Encode without an alpha channel to match Google Play's 24-bit PNG contract."""
    rgba_stride = canvas.width * 4
    scanlines = bytearray()
    for y in range(canvas.height):
        row = canvas.pixels[y * rgba_stride : (y + 1) * rgba_stride]
        rgb = bytearray(canvas.width * 3)
        rgb[0::3] = row[0::4]
        rgb[1::3] = row[1::4]
        rgb[2::3] = row[2::4]
        scanlines.extend(b"\x00")
        scanlines.extend(rgb)

    payload = bytearray(b"\x89PNG\r\n\x1a\n")
    payload += _png_chunk(
        b"IHDR",
        struct.pack(
            ">IIBBBBB",
            canvas.width,
            canvas.height,
            8,
            2,
            0,
            0,
            0,
        ),
    )
    payload += _png_chunk(b"IDAT", zlib.compress(bytes(scanlines), level=9))
    payload += _png_chunk(b"IEND", b"")
    return bytes(payload)


def _validate_rgb24_png(label: str, path: Path) -> None:
    data = path.read_bytes()
    if len(data) < 45 or not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError(f"not a PNG: {path}")

    offset = 8
    header: tuple[int, int, int, int, int, int, int] | None = None
    compressed = bytearray()
    saw_end = False
    while offset < len(data):
        if offset + 12 > len(data):
            raise RuntimeError(f"{label} PNG chunk header is truncated: {path}")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_end = offset + 12 + length
        if chunk_end > len(data):
            raise RuntimeError(f"{label} PNG chunk data is truncated: {path}")
        kind = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        expected_crc = struct.unpack(
            ">I", data[offset + 8 + length : chunk_end]
        )[0]
        actual_crc = zlib.crc32(kind)
        actual_crc = zlib.crc32(payload, actual_crc) & 0xFFFFFFFF
        if expected_crc != actual_crc:
            raise RuntimeError(
                f"{label} PNG {kind.decode('ascii', errors='replace')} CRC is "
                f"invalid: {path}"
            )
        if kind == b"IHDR":
            if offset != 8 or length != 13 or header is not None:
                raise RuntimeError(f"{label} PNG IHDR layout is invalid: {path}")
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            if header is None or saw_end:
                raise RuntimeError(f"{label} PNG IDAT order is invalid: {path}")
            compressed.extend(payload)
        elif kind == b"IEND":
            if length != 0 or saw_end or chunk_end != len(data):
                raise RuntimeError(f"{label} PNG IEND layout is invalid: {path}")
            saw_end = True
        offset = chunk_end
        if saw_end:
            break

    if header is None or not compressed or not saw_end:
        raise RuntimeError(
            f"{label} PNG requires IHDR, IDAT, and IEND: {path}"
        )
    width, height, bit_depth, color_type, compression, filtering, interlace = header
    if (
        (bit_depth, color_type, compression, filtering, interlace)
        != (8, 2, 0, 0, 0)
    ):
        raise RuntimeError(
            f"{label} must be a Google Play 24-bit RGB PNG "
            f"(bit depth={bit_depth}, color type={color_type}, "
            f"interlace={interlace})"
        )
    expected_size = height * (1 + width * 3)
    try:
        raw = zlib.decompress(bytes(compressed))
    except zlib.error as error:
        raise RuntimeError(
            f"{label} PNG IDAT could not be decompressed: {path}"
        ) from error
    if len(raw) != expected_size:
        raise RuntimeError(
            f"{label} PNG decompressed size differs: {path} "
            f"({len(raw)} / {expected_size})"
        )
    row_size = 1 + width * 3
    for row in range(height):
        if raw[row * row_size] > 4:
            raise RuntimeError(
                f"{label} PNG scanline filter is invalid: {path}"
            )


def _production_outputs(*, play_only: bool = False) -> dict[Path, bytes]:
    main_icon = _read_png_rgba(
        GAME_ROOT / "assets/custom/ui/app_icon_master.png"
    )
    # Keep feature graphic and supporter product images as the prior submission. The new master
    # is used only for the app icon; the old vector foreground stays in those two assets' determinism.
    _, foreground, _ = ICON.build_outputs()
    outputs = {
        STORE_ROOT / "play/icon-512.png": _build_play_icon(main_icon),
        STORE_ROOT / "play/feature-graphic-1024x500.png": _build_feature_graphic(foreground),
    }
    if not play_only:
        outputs.update({
            STORE_ROOT / "iap/moonlit-supporter-512.png": (
                _build_supporter_icon(foreground)
            ),
            STORE_ROOT / "iap/hero-bundle-512.png": _build_hero_bundle_icon(),
            STORE_ROOT / "iap/lantern-colors-512.png": _build_lantern_icon(),
        })
        for hero_name in IAP_HERO_ART:
            outputs[STORE_ROOT / f"iap/hero-{hero_name}-512.png"] = (
                _build_individual_hero_icon(hero_name)
            )
    expected = {
        "icon-512.png": (512, 512),
        "feature-graphic-1024x500.png": (1024, 500),
    }
    if not play_only:
        expected.update({
            "moonlit-supporter-512.png": (512, 512),
            "hero-bundle-512.png": (512, 512),
            "lantern-colors-512.png": (512, 512),
        })
        for hero_name in IAP_HERO_ART:
            expected[f"hero-{hero_name}-512.png"] = (512, 512)
    encoded: dict[Path, bytes] = {}
    for path, canvas in outputs.items():
        width, height = expected[path.name]
        _validate_canvas(path.name, canvas, width, height)
        if path.name == "feature-graphic-1024x500.png":
            encoded[path] = _to_rgb_png(canvas)
        else:
            encoded[path] = canvas.to_png()
    return encoded


def _png_size(path: Path) -> tuple[int, int]:
    header = path.read_bytes()[:24]
    if len(header) != 24 or not header.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError(f"not a PNG: {path}")
    return struct.unpack(">II", header[16:24])


def _validate_source_path(source: object, output: str) -> None:
    source_path = Path(source) if isinstance(source, str) else None
    if (
        source_path is None
        or source_path.is_absolute()
        or ".." in source_path.parts
        or source_path.parts[:2] != ("builds", "shots")
    ):
        raise RuntimeError(
            f"screenshot sources must be under builds/shots: {output} ({source!r})"
        )


def _source_fingerprints() -> dict[str, str]:
    paths = (
        "package.json",
        "scripts/capture-store-screenshots.mjs",
        "scripts/android-build.mjs",
        "scripts/godot.mjs",
        "scripts/python.mjs",
        "scripts/lib/android-capture-persistence.mjs",
        "scripts/lib/android-capture-signing.mjs",
        "scripts/lib/android-build.mjs",
        "scripts/lib/android-release-signing.mjs",
        "scripts/lib/android-tablet-evidence.mjs",
        "scripts/lib/capture-run-state.mjs",
        "scripts/lib/godot-export-preflight.mjs",
        "scripts/lib/iapkit-config.mjs",
        "scripts/lib/release-environment.mjs",
        "notes/release/store-assets/screenshots.json",
        "apps/game/tools/build_store_graphics.py",
        "apps/game/export_presets.cfg",
        "apps/game/android/.build_version",
        "apps/game/android/build/build.gradle",
        "apps/game/android/build/config.gradle",
        "apps/game/android/build/gradle.properties",
        "apps/game/android/build/settings.gradle",
        *ANDROID_DEBUG_CAPTURE_INPUTS,
        "apps/game/android/build/src/debug/AndroidManifest.xml",
        "apps/game/android/build/src/main/AndroidManifest.xml",
        "apps/game/android/build/src/main/java/com/godot/game/GodotApp.java",
        "apps/game/android/build/src/release/AndroidManifest.xml",
        "apps/game/localization/moonlit.csv",
        "apps/game/assets/third_party/fonts/Galmuri11-Multilingual.tres",
        "apps/game/assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres",
        "apps/game/assets/third_party/fonts/NotoSansCJKsc-Regular.otf",
        "apps/game/scenes/menus/title_menu.tscn",
        "apps/game/scenes/gameplay/arena.tscn",
        "apps/game/scenes/ui/hud.tscn",
        "apps/game/scenes/ui/shrine_panel.tscn",
        "apps/game/scenes/ui/hero_preview_panel.tscn",
        "apps/game/scenes/ui/iap_shop_panel.tscn",
        "apps/game/scripts/gameplay/settings.gd",
        "apps/game/scripts/gameplay/arena.gd",
        "apps/game/scripts/dev/store_capture_clean_ui.gd",
        "apps/game/scripts/dev/store_capture_boot.gd",
        "apps/game/scripts/dev/store_capture_probe.gd",
        "apps/game/scripts/dev/test_launcher.gd",
        "apps/game/scripts/dev/arena_tools.gd",
        "apps/game/scripts/ui/hud.gd",
        "apps/game/scripts/ui/title_menu.gd",
        "apps/game/scripts/ui/shrine_panel.gd",
        "apps/game/scripts/ui/hero_preview_panel.gd",
        "apps/game/scripts/ui/iap_shop_panel.gd",
    )
    fingerprints: dict[str, str] = {}
    for path in paths:
        absolute = REPO_ROOT / path
        _assert_safe_repository_path(
            absolute,
            REPO_ROOT,
            f"capture fingerprint input {path}",
        )
        fingerprints[path] = hashlib.sha256(absolute.read_bytes()).hexdigest()
    return fingerprints


def _fingerprint_map_sha256(value: object, label: str) -> str:
    if not isinstance(value, dict) \
            or not value \
            or any(
                not isinstance(path, str)
                or not path
                or re.fullmatch(r"[0-9a-f]{64}", digest) is None
                for path, digest in value.items()
            ):
        raise RuntimeError(f"{label} fingerprint map is invalid")
    canonical = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def _runtime_fingerprint() -> str:
    excluded_roots = {
        ".godot",
        "android",
        "docs",
        "ios",
        "tests",
        "tools",
    }
    excluded_files = {"export_presets.cfg", "iapkit.cfg"}
    files = sorted(
        path
        for path in GAME_ROOT.rglob("*")
        if path.is_file()
        and path.relative_to(GAME_ROOT).parts[0] not in excluded_roots
        and path.relative_to(GAME_ROOT).as_posix() not in excluded_files
    )
    digest = hashlib.sha256()
    for path in files:
        relative_path = path.relative_to(GAME_ROOT).as_posix()
        digest.update(relative_path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def _screenshot_entries() -> list[dict[str, object]]:
    expected_locales = ("en-US", "ko-KR", "ja-JP", "zh-Hans", "zh-Hant")
    if SCREENSHOT_LOCALES != expected_locales \
            or GAME_LOCALES != {
                "en-US": "en", "ko-KR": "ko", "ja-JP": "ja",
                "zh-Hans": "zh_CN", "zh-Hant": "zh_TW",
            } \
            or PLAY_LOCALES != {
                "en-US": "en-US", "ko-KR": "ko-KR", "ja-JP": "ja-JP",
                "zh-Hans": "zh-CN", "zh-Hant": "zh-TW",
            } \
            or APP_STORE_LOCALES != {
                "en-US": "en-US", "ko-KR": "ko", "ja-JP": "ja",
                "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant",
            } \
            or MARKETING_TEXT_LANGUAGES != {
                "en-US": "en", "ko-KR": "ko", "ja-JP": "ja",
                "zh-Hans": "zh-cn", "zh-Hant": "zh-tw",
            } \
            or BRAND_LABELS != {
                "en-US": "MOONLIT BEACON", "ko-KR": "Moonlit Beacon",
                "ja-JP": "月明かりの烽火", "zh-Hans": "月光烽火",
                "zh-Hant": "月光烽火",
            }:
        raise RuntimeError("store locale/language/brand literal contract differs")
    manifest = json.loads(SCREENSHOT_MANIFEST.read_text(encoding="utf-8"))
    entries = manifest.get("screenshots", [])
    if not isinstance(entries, list) or len(entries) != 6:
        raise RuntimeError("Play and App Store screenshots must be exactly 6")
    output_names: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise RuntimeError("screenshot entry must be a JSON object")
        output = entry.get("output")
        localized_sources = entry.get("localized_sources", {})
        labels = entry.get("labels")
        scene = entry.get("scene")
        crop_bottom = entry.get("crop_bottom", 0)
        if not isinstance(output, str) or Path(output).name != output or not output.endswith(".png"):
            raise RuntimeError(f"invalid screenshot output filename: {output!r}")
        if output in output_names:
            raise RuntimeError(f"duplicate screenshot output filename: {output}")
        output_names.add(output)
        contract = SCREENSHOT_CONTRACTS.get(output)
        if contract is None:
            raise RuntimeError(f"missing screenshot output literal contract: {output}")
        if not isinstance(localized_sources, dict) \
                or set(localized_sources) != set(SCREENSHOT_LOCALES):
            raise RuntimeError(
                f"localized_sources must include real UI sources for all of "
                f"{', '.join(SCREENSHOT_LOCALES)}: {output}"
            )
        for locale, localized_source in localized_sources.items():
            _validate_source_path(localized_source, output)
            expected_source = (
                f"builds/shots/store-localized/{locale}/{output}"
            )
            if localized_source != expected_source:
                raise RuntimeError(
                    f"{output} ({locale}) real UI source must be "
                    f"{expected_source}"
                )
        if scene not in SCENE_CROP_BOTTOM:
            raise RuntimeError(
                f"invalid screenshot scene contract: {output} ({scene!r})"
            )
        if not isinstance(labels, dict) or set(labels) != set(SCREENSHOT_LOCALES):
            raise RuntimeError(
                f"screenshot labels must include all of {', '.join(SCREENSHOT_LOCALES)}: "
                f"{output}"
            )
        for locale, label in labels.items():
            if not isinstance(label, str) or not label.strip():
                raise RuntimeError(f"empty screenshot label: {output} ({locale})")
        if scene != contract["scene"] \
                or crop_bottom != contract["crop_bottom"] \
                or labels != contract["labels"]:
            raise RuntimeError(
                f"{output} scene/crop/locale copy differs from the literal contract"
            )
        required_crop = SCENE_CROP_BOTTOM[str(scene)]
        if crop_bottom != required_crop:
            raise RuntimeError(
                f"{output} crop_bottom must be {required_crop} "
                f"(got {crop_bottom!r}). Arbitrary values that hide debug UI are not allowed"
            )

    if output_names != set(SCREENSHOT_CONTRACTS):
        raise RuntimeError("screenshot output set of 6 differs from the literal contract")

    all_sources = [
        str(source)
        for entry in entries
        for source in dict(entry["localized_sources"]).values()
    ]
    if len(set(all_sources)) != len(all_sources):
        raise RuntimeError("each scene/locale needs a unique real UI source file")
    return entries


def _iap_review_entries() -> list[dict[str, object]]:
    manifest = json.loads(SCREENSHOT_MANIFEST.read_text(encoding="utf-8"))
    entries = manifest.get("iap_review", [])
    if not isinstance(entries, list) \
            or len(entries) != len(IAP_REVIEW_PRODUCT_IDS):
        raise RuntimeError(
            "App Store IAP review images must be exactly "
            f"{len(IAP_REVIEW_PRODUCT_IDS)} per sold SKU"
        )
    product_ids = [
        entry.get("product_id") if isinstance(entry, dict) else None
        for entry in entries
    ]
    if tuple(product_ids) != IAP_REVIEW_PRODUCT_IDS:
        raise RuntimeError(
            "IAP review images must include only the 7 non-consumables and 3 coin SKUs "
            "currently for sale, in the fixed order"
        )
    output_names: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise RuntimeError("IAP review image entry must be a JSON object")
        output = entry.get("output")
        if not isinstance(output, str) \
                or Path(output).name != output \
                or not output.endswith(".png") \
                or output in output_names:
            raise RuntimeError(f"invalid IAP review image filename: {output!r}")
        output_names.add(output)
        product_id = str(entry.get("product_id", ""))
        expected_output = IAP_REVIEW_OUTPUT_BY_PRODUCT.get(product_id)
        if output != expected_output:
            raise RuntimeError(
                f"IAP SKU {product_id} review file must be "
                f"{expected_output}: {output!r}"
            )
    return entries


def _marketing_text_tools() -> tuple[str, str]:
    hb_shape = shutil.which("hb-shape")
    if hb_shape is None:
        raise RuntimeError(
            "CJK marketing label checks require HarfBuzz hb-shape. "
            "macOS: brew install harfbuzz, "
            "Ubuntu: sudo apt-get install libharfbuzz-bin"
        )
    hb_view = shutil.which("hb-view")
    if hb_view is None:
        raise RuntimeError(
            "Per-locale marketing text rendering requires HarfBuzz hb-view. "
            "macOS: brew install harfbuzz, "
            "Ubuntu: sudo apt-get install libharfbuzz-bin"
        )
    if not MARKETING_FONT.is_file():
        raise RuntimeError(f"CJK marketing font is missing: {MARKETING_FONT}")
    return hb_shape, hb_view


def _shape_marketing_text(hb_shape: str, text: str, language: str) -> str:
    return subprocess.run(
        (
            hb_shape,
            f"--language={language}",
            str(MARKETING_FONT),
            text,
        ),
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def _validate_marketing_glyphs(
    entries: list[dict[str, object]],
) -> tuple[str, str]:
    hb_shape, hb_view = _marketing_text_tools()
    for entry in entries:
        labels = dict(entry["labels"])
        for locale in SCREENSHOT_LOCALES:
            text = f"{labels[locale]} {BRAND_LABELS[locale]}"
            shaped = _shape_marketing_text(
                hb_shape,
                text,
                MARKETING_TEXT_LANGUAGES[locale],
            )
            if "gid0" in shaped:
                raise RuntimeError(
                    f"marketing label has missing glyphs: "
                    f"{entry['output']} ({locale})"
                )
    probe_shapes = {
        language: _shape_marketing_text(
            hb_shape,
            MARKETING_SHAPING_PROBE,
            language,
        )
        for language in ("ja", "zh-cn", "zh-tw")
    }
    if len(set(probe_shapes.values())) != len(probe_shapes):
        raise RuntimeError(
            "marketing font does not distinguish regional locl glyphs for "
            f"Japanese, Simplified, and Traditional Chinese: {MARKETING_SHAPING_PROBE}"
        )
    return hb_shape, hb_view


def _validate_missile_core_capture_guard(
    capture: dict[str, object],
    source: str,
    locale: str,
    game_locale: str,
) -> None:
    is_core_drop = source.endswith("/03-missile-core-drop.png")
    guard = capture.get("capture_guard")
    if not is_core_drop:
        if guard is not None:
            raise RuntimeError(
                f"missile-core state proof is attached to the wrong scene: {source}"
            )
        return
    if not isinstance(guard, dict):
        raise RuntimeError(
            f"missile-core reclaim scene is missing capture state proof: {source}"
        )
    _require_store_capture_color(
        guard, "time_tone", STORE_CAPTURE_NIGHT_TONE, source
    )
    _require_store_capture_color(
        guard, "applied_time_tone", STORE_CAPTURE_NIGHT_TONE, source
    )
    _require_store_capture_values(
        guard,
        {
            "scene": "arena",
            "over": False,
            "level": 10,
            "cycle": 1,
            "zone_index": 0,
            "terrain_path": "res://resources/rooms/forest.tres",
            "world_key": "WORLD_FOREST",
            "lit_beacons": 0,
            "transitioning": False,
            "escape_active": False,
            "time_key": "TIME_NIGHT",
            "time_tone_applied": True,
        },
        source,
    )
    expected_text = guard.get("expected_banner_text")
    actual_text = guard.get("actual_banner_text")
    before = guard.get("missile_power_before")
    after = guard.get("missile_power_after")
    outstanding = guard.get("ejected_cores_outstanding")
    core_alpha = guard.get("core_effective_alpha")
    if type(guard.get("schema")) is not int \
            or guard.get("schema") != 1 \
            or guard.get("kind") != "missile_core_recovery" \
            or guard.get("asset_locale") != locale \
            or guard.get("game_locale") != game_locale \
            or guard.get("banner_key") != "MISSILE_DROPPED" \
            or not isinstance(expected_text, str) \
            or not expected_text.strip() \
            or actual_text != expected_text \
            or guard.get("banner_visible") is not True \
            or guard.get("banner_locked") is not True \
            or type(before) is not int \
            or type(after) is not int \
            or before < 1 \
            or after < 0 \
            or before != after + 1 \
            or type(outstanding) is not int \
            or outstanding < 1 \
            or guard.get("core_capture_paused") is not True \
            or type(guard.get("ejected_core_count")) is not int \
            or guard.get("ejected_core_count") != 1 \
            or guard.get("core_visible_in_tree") is not True \
            or type(core_alpha) not in (int, float) \
            or not math.isfinite(core_alpha) \
            or core_alpha < 0.99 \
            or guard.get("core_opaque") is not True \
            or guard.get("core_onscreen") is not True \
            or guard.get("core_texture_path") \
                != "res://assets/custom/items/pickups/power_gem.png" \
            or guard.get("core_texture_matches") is not True \
            or guard.get("core_visible_draw_rect_positive") is not True:
        raise RuntimeError(
            "missile-core reclaim scene locale/banner/output/physical-core proof "
            f"is invalid: {source}"
        )


def _is_javascript_safe_integer(value: object, minimum: int | None = None) -> bool:
    if type(value) is not int or abs(value) > JAVASCRIPT_MAX_SAFE_INTEGER:
        return False
    return minimum is None or value >= minimum


def _require_store_capture_values(
    guard: dict[str, object],
    expected: dict[str, object],
    source: str,
) -> None:
    for field, expected_value in expected.items():
        actual = guard.get(field)
        if type(actual) is not type(expected_value) or actual != expected_value:
            raise RuntimeError(
                f"store capture state {field} proof is invalid: {source}"
            )


def _require_store_capture_color(
    guard: dict[str, object],
    field: str,
    expected: list[float],
    source: str,
) -> None:
    actual = guard.get(field)
    if not isinstance(actual, list) or len(actual) != len(expected) \
            or any(
                type(component) not in (int, float)
                or not math.isfinite(component)
                or abs(component - expected[index])
                    > STORE_CAPTURE_COLOR_COMPONENT_TOLERANCE
                for index, component in enumerate(actual)
            ):
        raise RuntimeError(
            f"store capture state {field} color proof is invalid: {source}"
        )


def _require_store_capture_rect(
    guard: dict[str, object],
    field: str,
    source: str,
) -> list[int | float]:
    actual = guard.get(field)
    if not isinstance(actual, list) or len(actual) != 4 \
            or any(
                type(component) not in (int, float)
                or not math.isfinite(component)
                for component in actual
            ) \
            or actual[2] <= 0 \
            or actual[3] <= 0:
        raise RuntimeError(
            f"store capture state {field} coordinates are invalid: {source}"
        )
    return actual


def _store_capture_rect_fully_inside(
    inner: list[int | float],
    outer: list[int | float],
) -> bool:
    return inner[0] >= outer[0] - STORE_CAPTURE_RECT_TOLERANCE \
        and inner[1] >= outer[1] - STORE_CAPTURE_RECT_TOLERANCE \
        and inner[0] + inner[2] \
            <= outer[0] + outer[2] + STORE_CAPTURE_RECT_TOLERANCE \
        and inner[1] + inner[3] \
            <= outer[1] + outer[3] + STORE_CAPTURE_RECT_TOLERANCE


def _validate_guardian_capture_composition(
    guard: dict[str, object],
    source: str,
) -> None:
    viewport = _require_store_capture_rect(
        guard, "viewport_rect", source
    )
    draw_rect = _require_store_capture_rect(
        guard, "guardian_draw_rect", source
    )
    focus_rect = _require_store_capture_rect(
        guard, "guardian_focus_rect", source
    )
    expected_focus = [
        viewport[0]
        + viewport[2] * STORE_CAPTURE_GUARDIAN_FOCUS_POSITION[0],
        viewport[1]
        + viewport[3] * STORE_CAPTURE_GUARDIAN_FOCUS_POSITION[1],
        viewport[2] * STORE_CAPTURE_GUARDIAN_FOCUS_SIZE[0],
        viewport[3] * STORE_CAPTURE_GUARDIAN_FOCUS_SIZE[1],
    ]
    if any(
        abs(component - expected_focus[index])
            > STORE_CAPTURE_RECT_TOLERANCE
        for index, component in enumerate(focus_rect)
    ):
        raise RuntimeError(
            f"guardian center focus differs from the fixed framing contract: {source}"
        )
    if not _store_capture_rect_fully_inside(draw_rect, viewport):
        raise RuntimeError(
            f"guardian real frame is not fully on screen: {source}"
        )
    if not _store_capture_rect_fully_inside(draw_rect, focus_rect):
        raise RuntimeError(
            f"guardian real frame is outside the screen-center focus: {source}"
        )
    center = (
        draw_rect[0] + draw_rect[2] * 0.5,
        draw_rect[1] + draw_rect[3] * 0.5,
    )
    if center[0] < focus_rect[0] - STORE_CAPTURE_RECT_TOLERANCE \
            or center[1] < focus_rect[1] - STORE_CAPTURE_RECT_TOLERANCE \
            or center[0] > focus_rect[0] + focus_rect[2] \
                + STORE_CAPTURE_RECT_TOLERANCE \
            or center[1] > focus_rect[1] + focus_rect[3] \
                + STORE_CAPTURE_RECT_TOLERANCE:
        raise RuntimeError(
            f"guardian center point is not inside the screen-center focus: {source}"
        )
    player_distance = guard.get("guardian_player_canvas_distance")
    if type(player_distance) not in (int, float) \
            or not math.isfinite(player_distance) \
            or player_distance < STORE_CAPTURE_GUARDIAN_MIN_PLAYER_SEPARATION:
        raise RuntimeError(
            f"guardian and player silhouettes are not separated enough: {source}"
        )
    if not _is_javascript_safe_integer(
        guard.get("friendly_projectile_count"), 0
    ) or guard.get("friendly_projectile_count") != 0:
        raise RuntimeError(
            f"guardian capture still has allied projectiles: {source}"
        )
    _require_store_capture_values(
        guard,
        {
            "guardian_capture_active": True,
            "guardian_draw_rect_fully_inside_viewport": True,
            "guardian_draw_rect_inside_focus": True,
            "guardian_draw_center_inside_focus": True,
            "guardian_separated_from_player": True,
            "guardian_central_composition": True,
        },
        source,
    )


def _validate_store_capture_safe_layout(
    guard: dict[str, object],
    source: str,
    controls: tuple[str, ...],
    *,
    viewport_field: str = "viewport_rect",
    ready_fields: tuple[str, ...] = ("safe_ui_ready",),
) -> None:
    """Inspect whether real UI rects sit inside the safe area, separate from boolean proofs."""
    viewport = _require_store_capture_rect(guard, viewport_field, source)
    safe_rect = _require_store_capture_rect(guard, "safe_rect", source)
    if not _store_capture_rect_fully_inside(safe_rect, viewport):
        raise RuntimeError(
            f"OS safe area extends outside the real capture screen: {source}"
        )
    expected_ready = {"safe_area_inside_viewport": True}
    expected_ready.update({field: True for field in ready_fields})
    _require_store_capture_values(guard, expected_ready, source)
    for control in controls:
        rect_field = f"{control}_rect"
        inside_field = f"{control}_inside_safe_area"
        control_rect = _require_store_capture_rect(guard, rect_field, source)
        if not _store_capture_rect_fully_inside(control_rect, safe_rect):
            raise RuntimeError(
                f"store capture UI invades the OS safe area: "
                f"{rect_field} ({source})"
            )
        _require_store_capture_values(
            guard,
            {inside_field: True},
            source,
        )


def _validate_store_capture_state_guard(
    capture: dict[str, object],
    source: str,
    game_locale: str,
    state_kind: str,
    product_id: str | None = None,
    expected_direct_distribution: bool | None = None,
) -> None:
    """Inspect the same first-party state contract as JS assertStoreCaptureProofs."""
    guard = capture.get("state_guard")
    if not isinstance(guard, dict):
        raise RuntimeError(f"game runtime state_guard is missing: {source}")
    nonce = guard.get("nonce")
    observation = guard.get("observation")
    observation_after = guard.get("observation_after")
    if type(guard.get("schema")) is not int or guard.get("schema") != 1:
        raise RuntimeError(f"store capture-state schema is invalid: {source}")
    if not isinstance(nonce, str) \
            or len(nonce) != 64 \
            or any(character not in "0123456789abcdef" for character in nonce):
        raise RuntimeError(f"store capture state nonce is invalid: {source}")
    if not _is_javascript_safe_integer(observation, 1):
        raise RuntimeError(f"store capture state observation number is invalid: {source}")
    if not _is_javascript_safe_integer(observation_after, 1) \
            or observation_after <= observation:
        raise RuntimeError(
            f"missing new runtime observation proof after screencap: {source}"
        )
    _require_store_capture_values(
        guard,
        {
            "kind": state_kind,
            "game_locale": game_locale,
        },
        source,
    )

    if state_kind == "title":
        if expected_direct_distribution is None:
            expected_direct_distribution = True
        _validate_store_capture_safe_layout(
            guard,
            source,
            STORE_CAPTURE_TITLE_DIRECT_SAFE_CONTROLS
            if expected_direct_distribution
            else STORE_CAPTURE_TITLE_SAFE_CONTROLS,
        )
    elif state_kind in (
        "arena_ready",
        "moonlight_barrage",
        "field_guardian",
    ):
        _validate_store_capture_safe_layout(
            guard,
            source,
            STORE_CAPTURE_ARENA_SAFE_CONTROLS,
        )
    elif state_kind == "shrine":
        _validate_store_capture_safe_layout(
            guard,
            source,
            ("shrine_frame",),
            ready_fields=("shrine_safe_ui_ready",),
        )
    elif state_kind == "hero_preview":
        _validate_store_capture_safe_layout(
            guard,
            source,
            ("shrine_frame", "preview_frame", "close"),
            ready_fields=("shrine_safe_ui_ready", "preview_safe_ui_ready"),
        )
    elif state_kind == "iap_review":
        _validate_store_capture_safe_layout(
            guard,
            source,
            ("shop_frame", "card"),
            viewport_field="screen_rect",
            ready_fields=("iap_safe_ui_ready",),
        )

    if state_kind == "title":
        storefront_enabled = not bool(expected_direct_distribution)
        version_text = guard.get("version_text")
        if not isinstance(version_text, str) or re.fullmatch(
            r"v\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?",
            version_text,
        ) is None:
            raise RuntimeError(
                f"title app version string is invalid: {source}"
            )
        title_copy = STORE_CAPTURE_TITLE_COPY[game_locale]
        for alpha_field in (
            "night_forest_effective_alpha",
            "night_forest_drawable_effective_alpha",
            "vignette_effective_alpha",
            "beacon_effective_alpha",
            "beacon_drawable_effective_alpha",
        ):
            alpha = guard.get(alpha_field)
            if type(alpha) not in (int, float) \
                    or not math.isfinite(alpha) \
                    or alpha < 0.99:
                raise RuntimeError(
                    f"title art {alpha_field} proof is invalid: "
                    f"{source}"
                )
        tap_prompt_effective_alpha = guard.get(
            "tap_prompt_effective_alpha"
        )
        if type(tap_prompt_effective_alpha) not in (int, float) \
                or not math.isfinite(tap_prompt_effective_alpha) \
                or abs(tap_prompt_effective_alpha - 1.0) \
                    > STORE_CAPTURE_COLOR_COMPONENT_TOLERANCE:
            raise RuntimeError(
                f"start prompt actual alpha is not 1: {source}"
            )
        _require_store_capture_values(
            guard,
            {
                "scene": "title",
                "ready": True,
                "screen_visible": True,
                "title_visible": True,
                "subtitle_visible": True,
                "title_source_key": "TITLE_NAME",
                "subtitle_source_key": "TITLE_SUBTITLE",
                "title_auto_translate": True,
                "subtitle_auto_translate": True,
                "title_translation_text": title_copy["title"],
                "subtitle_translation_text": title_copy["subtitle"],
                "title_text_nonempty": True,
                "title_characters_visible": True,
                "title_font_size_positive": True,
                "title_font_alpha_readable": True,
                "title_rendered_text_ready": True,
                "subtitle_text_nonempty": True,
                "subtitle_characters_visible": True,
                "subtitle_font_size_positive": True,
                "subtitle_font_alpha_readable": True,
                "subtitle_rendered_text_ready": True,
                "title_inside_viewport": True,
                "subtitle_inside_viewport": True,
                "title_opaque": True,
                "subtitle_opaque": True,
                "version_visible": True,
                "version_text_nonempty": True,
                "version_characters_visible": True,
                "version_font_size_positive": True,
                "version_font_alpha_readable": True,
                "version_rendered_text_ready": True,
                "version_inside_viewport": True,
                "version_opaque": True,
                "tap_prompt_visible": True,
                "tap_prompt_source_key": "TAP_TO_START",
                "tap_prompt_auto_translate": True,
                "tap_prompt_translation_text": title_copy["tap"],
                "tap_prompt_text_nonempty": True,
                "tap_prompt_characters_visible": True,
                "tap_prompt_font_size_positive": True,
                "tap_prompt_font_alpha_readable": True,
                "tap_prompt_rendered_text_ready": True,
                "tap_prompt_inside_viewport": True,
                "tap_prompt_readable_alpha": True,
                "tap_prompt_full_alpha": True,
                "tap_prompt_blink_stopped": True,
                "tap_prompt_modulate_white": True,
                "tap_prompt_capture_locked": True,
                "settings_button_visible": True,
                "settings_button_enabled": True,
                "settings_button_source_key": "SETTINGS_TITLE",
                "settings_button_auto_translate": True,
                "settings_button_translation_text": title_copy["settings"],
                "settings_button_inside_viewport": True,
                "settings_button_copy_valid": True,
                "settings_button_text_nonempty": True,
                "settings_button_font_size_positive": True,
                "settings_button_font_alpha_readable": True,
                "settings_button_rendered_text_ready": True,
                "settings_button_opaque": True,
                "shrine_button_visible": True,
                "shrine_button_enabled": True,
                "shrine_button_source_key": "SHRINE_OPEN",
                "shrine_button_auto_translate": True,
                "shrine_button_translation_text": title_copy["shrine"],
                "shrine_button_inside_viewport": True,
                "shrine_button_copy_valid": True,
                "shrine_button_text_nonempty": True,
                "shrine_button_font_size_positive": True,
                "shrine_button_font_alpha_readable": True,
                "shrine_button_rendered_text_ready": True,
                "shrine_button_opaque": True,
                "ladder_button_visible": True,
                "ladder_button_enabled": True,
                "ladder_button_source_key": "LADDER_OPEN",
                "ladder_button_auto_translate": True,
                "ladder_button_translation_text": title_copy["ladder"],
                "ladder_button_inside_viewport": True,
                "ladder_button_copy_valid": True,
                "ladder_button_text_nonempty": True,
                "ladder_button_font_size_positive": True,
                "ladder_button_font_alpha_readable": True,
                "ladder_button_rendered_text_ready": True,
                "ladder_button_opaque": True,
                "direct_distribution": expected_direct_distribution,
                "storefront_enabled": storefront_enabled,
                "storefront_feature_matches": True,
                "store_button_visible": storefront_enabled,
                "store_button_enabled": storefront_enabled,
                "store_button_visibility_matches_storefront": True,
                "store_button_enabled_matches_storefront": True,
                "store_button_source_key": "IAP_OPEN",
                "store_button_auto_translate": True,
                "store_button_translation_text": title_copy["store"],
                "store_button_inside_viewport": True,
                "store_button_copy_valid": True,
                "store_button_text_nonempty": True,
                "store_button_font_size_positive": True,
                "store_button_font_alpha_readable": True,
                "store_button_rendered_text_ready": storefront_enabled,
                "store_button_opaque": storefront_enabled,
                "night_forest_node_present": True,
                "night_forest_scene_path": (
                    STORE_CAPTURE_TITLE_FOREST_SCENE_PATH
                ),
                "night_forest_expected_scene_path": (
                    STORE_CAPTURE_TITLE_FOREST_SCENE_PATH
                ),
                "night_forest_scene_matches": True,
                "night_forest_visible_in_tree": True,
                "night_forest_opaque": True,
                "night_forest_ground_resource_path": (
                    STORE_CAPTURE_TITLE_FOREST_GROUND_PATH
                ),
                "night_forest_expected_ground_resource_path": (
                    STORE_CAPTURE_TITLE_FOREST_GROUND_PATH
                ),
                "night_forest_ground_resource_matches": True,
                "night_forest_drawable_visible_in_tree": True,
                "night_forest_drawable_opaque": True,
                "night_forest_draw_rect_positive": True,
                "night_forest_draw_rect_intersects_viewport": True,
                "night_forest_visual_ready": True,
                "vignette_node_present": True,
                "vignette_node_class": (
                    STORE_CAPTURE_TITLE_VIGNETTE_NODE_CLASS
                ),
                "vignette_texture_class": (
                    STORE_CAPTURE_TITLE_VIGNETTE_TEXTURE_CLASS
                ),
                "vignette_expected_texture_class": (
                    STORE_CAPTURE_TITLE_VIGNETTE_TEXTURE_CLASS
                ),
                "vignette_texture_unique_id": (
                    STORE_CAPTURE_TITLE_VIGNETTE_TEXTURE_UNIQUE_ID
                ),
                "vignette_expected_texture_unique_id": (
                    STORE_CAPTURE_TITLE_VIGNETTE_TEXTURE_UNIQUE_ID
                ),
                "vignette_texture_dimensions_match": True,
                "vignette_texture_matches": True,
                "vignette_visible_in_tree": True,
                "vignette_opaque": True,
                "vignette_draw_rect_positive": True,
                "vignette_draw_rect_intersects_viewport": True,
                "vignette_visual_ready": True,
                "beacon_node_present": True,
                "beacon_scene_path": STORE_CAPTURE_TITLE_BEACON_SCENE_PATH,
                "beacon_expected_scene_path": (
                    STORE_CAPTURE_TITLE_BEACON_SCENE_PATH
                ),
                "beacon_scene_matches": True,
                "beacon_visible_in_tree": True,
                "beacon_opaque": True,
                "beacon_clearing_resource_path": (
                    STORE_CAPTURE_TITLE_BEACON_CLEARING_PATH
                ),
                "beacon_expected_clearing_resource_path": (
                    STORE_CAPTURE_TITLE_BEACON_CLEARING_PATH
                ),
                "beacon_clearing_resource_matches": True,
                "beacon_drawable_visible_in_tree": True,
                "beacon_drawable_opaque": True,
                "beacon_draw_rect_positive": True,
                "beacon_draw_rect_intersects_viewport": True,
                "beacon_visual_ready": True,
                "panels_closed": True,
                "accepting_input": True,
                "screen_inside_viewport": True,
                "drawn_after_ready": True,
            },
            source,
        )
        return
    if state_kind == "arena_ready":
        _require_store_capture_values(
            guard,
            {
                "scene": "arena",
                "ready": True,
                "over": False,
            },
            source,
        )
        return
    if state_kind == "moonlight_barrage":
        probe_count = guard.get("missile_visual_probe_count")
        missile_alpha = guard.get("missile_effective_alpha")
        visible_enemy_sprite_count = guard.get("visible_enemy_sprite_count")
        if not _is_javascript_safe_integer(probe_count, 1) \
                or type(missile_alpha) not in (int, float) \
                or not math.isfinite(missile_alpha) \
                or missile_alpha < 0.99 \
                or not _is_javascript_safe_integer(
                    visible_enemy_sprite_count, 3
                ):
            raise RuntimeError(
                f"moonlight barrage physical missile proof is invalid: {source}"
            )
        _require_store_capture_color(
            guard, "time_tone", STORE_CAPTURE_NIGHT_TONE, source
        )
        _require_store_capture_color(
            guard, "applied_time_tone", STORE_CAPTURE_NIGHT_TONE, source
        )
        _require_store_capture_values(
            guard,
            {
                "scene": "arena",
                "ready": True,
                "over": False,
                "level": 20,
                "cycle": 3,
                "zone_index": 0,
                "terrain_path": STORE_CAPTURE_CAMP_TERRAIN_PATH,
                "world_key": "WORLD_CAMP",
                "lit_beacons": 0,
                "transitioning": False,
                "escape_active": False,
                "time_key": "TIME_NIGHT",
                "time_tone_applied": True,
                "missile_power": 8,
                "missile_max": 8,
                "missile_volley": 8,
                "homing_active": True,
                "missile_visible_in_tree": True,
                "missile_opaque": True,
                "missile_draw_after_launch": True,
                "missile_head_geometry_ready": True,
                "missile_trail_geometry_ready": True,
                "enemy_formation_visible": True,
                "max_volley_live": True,
                "barrage_visible": True,
            },
            source,
        )
        return
    if state_kind == "shrine":
        _require_store_capture_values(
            guard,
            {
                "shrine_visible": True,
                "preview_visible": False,
                "hero_card_count": 6,
                "hero_cards_visible_rect_count": 6,
                "shrine_opaque": True,
                "shrine_frame_inside_viewport": True,
                "shrine_drawn_after_open": True,
            },
            source,
        )
        return
    if state_kind == "hero_preview":
        hero_copy = STORE_CAPTURE_HERO_COPY.get(game_locale)
        state_source_key = guard.get("state_source_key")
        if hero_copy is None:
            raise RuntimeError(
                f"hero detail capture is missing an independent multilingual copy contract: {source}"
            )
        if not isinstance(state_source_key, str) \
                or state_source_key not in STORE_CAPTURE_HERO_STATE_SOURCE_KEYS:
            raise RuntimeError(
                f"hero detail state translation source key is invalid: {source}"
            )
        state_text = hero_copy["states"][state_source_key]
        _require_store_capture_values(
            guard,
            {
                "shrine_visible": True,
                "shrine_opaque": True,
                "shrine_frame_inside_viewport": True,
                "shrine_drawn_after_open": True,
                "preview_visible": True,
                "hero_path": STORE_CAPTURE_HERO_PATH,
                "portrait_visible": True,
                "portrait_texture_ready": True,
                "portrait_resource_path": STORE_CAPTURE_HERO_PORTRAIT_PATH,
                "portrait_expected_resource_path": (
                    STORE_CAPTURE_HERO_PORTRAIT_PATH
                ),
                "portrait_resource_matches": True,
                "portrait_visible_rect_ready": True,
                "portrait_opaque": True,
                "body_visible": True,
                "body_texture_ready": True,
                "body_resource_path": STORE_CAPTURE_HERO_BODY_PATH,
                "body_expected_resource_path": STORE_CAPTURE_HERO_BODY_PATH,
                "body_resource_matches": True,
                "body_visible_rect_ready": True,
                "body_opaque": True,
                "copy_locale": game_locale,
                "name_source_key": STORE_CAPTURE_HERO_NAME_SOURCE_KEY,
                "name_expected_source_key": (
                    STORE_CAPTURE_HERO_NAME_SOURCE_KEY
                ),
                "name_source_matches": True,
                "name_text": hero_copy["name"],
                "name_expected_text": hero_copy["name"],
                "name_copy_valid": True,
                "name_text_nonempty": True,
                "name_characters_visible": True,
                "name_font_size_positive": True,
                "name_font_alpha_readable": True,
                "name_visible_rect_ready": True,
                "name_opaque": True,
                "name_rendered_text_ready": True,
                "state_expected_source_key": state_source_key,
                "state_source_matches": True,
                "state_text": state_text,
                "state_expected_text": state_text,
                "state_copy_valid": True,
                "state_text_nonempty": True,
                "state_characters_visible": True,
                "state_font_size_positive": True,
                "state_font_alpha_readable": True,
                "state_visible_rect_ready": True,
                "state_opaque": True,
                "state_rendered_text_ready": True,
                "description_source_key": (
                    STORE_CAPTURE_HERO_DESCRIPTION_SOURCE_KEY
                ),
                "description_expected_source_key": (
                    STORE_CAPTURE_HERO_DESCRIPTION_SOURCE_KEY
                ),
                "description_source_matches": True,
                "description_text": hero_copy["description"],
                "description_expected_text": hero_copy["description"],
                "description_copy_valid": True,
                "description_text_nonempty": True,
                "description_characters_visible": True,
                "description_font_size_positive": True,
                "description_font_alpha_readable": True,
                "description_visible_rect_ready": True,
                "description_opaque": True,
                "description_rendered_text_ready": True,
                "close_visible": True,
                "close_inside_viewport": True,
                "close_opaque": True,
                "preview_opaque": True,
                "preview_frame_inside_viewport": True,
                "preview_drawn_after_open": True,
            },
            source,
        )
        return
    if state_kind == "field_guardian":
        cycle = guard.get("cycle")
        guardian_name = guard.get("guardian_name")
        root_alpha = guard.get("guardian_root_effective_alpha")
        sprite_alpha = guard.get("guardian_sprite_effective_alpha")
        current_animation = guard.get("guardian_current_animation")
        current_frame = guard.get("guardian_current_frame")
        frame_texture_path = guard.get("guardian_frame_texture_path")
        if not _is_javascript_safe_integer(cycle, 1):
            raise RuntimeError(f"guardian capture cycle count is invalid: {source}")
        if not isinstance(guardian_name, str) or not guardian_name.strip():
            raise RuntimeError(f"guardian capture name is empty: {source}")
        if type(root_alpha) not in (int, float) \
                or not math.isfinite(root_alpha) \
                or root_alpha < 0.99 \
                or type(sprite_alpha) not in (int, float) \
                or not math.isfinite(sprite_alpha) \
                or sprite_alpha < 0.99:
            raise RuntimeError(
                f"guardian real sprite is transparent: {source}"
            )
        if not isinstance(current_animation, str) \
                or not current_animation.strip():
            raise RuntimeError(
                f"guardian current animation is empty: {source}"
            )
        if not _is_javascript_safe_integer(current_frame, 0):
            raise RuntimeError(
                f"guardian current animation frame is invalid: {source}"
            )
        if frame_texture_path not in STORE_CAPTURE_FIELD_GUARDIAN_TEXTURE_PATHS:
            raise RuntimeError(
                f"guardian current frame is not a field-guardian asset: {source}"
            )
        if guard.get("guardian_kind_path") \
                not in STORE_CAPTURE_FIELD_GUARDIAN_PATHS:
            raise RuntimeError(
                f"guardian body is not the field guardian: {source}"
            )
        _validate_guardian_capture_composition(guard, source)
        _require_store_capture_color(
            guard, "time_tone", STORE_CAPTURE_DAY_TONE, source
        )
        _require_store_capture_color(
            guard, "applied_time_tone", STORE_CAPTURE_DAY_TONE, source
        )
        _require_store_capture_values(
            guard,
            {
                "scene": "arena",
                "ready": True,
                "over": False,
                "level": 20,
                "cycle": 3,
                "zone_index": 2,
                "terrain_path": STORE_CAPTURE_FIELD_TERRAIN_PATH,
                "terrain_encounter": 1,
                "world_key": "WORLD_FIELD",
                "time_key": "TIME_DAY",
                "time_tone_applied": True,
                "lit_beacons": 3,
                "total_beacons": 3,
                "transitioning": False,
                "escape_active": False,
                "guardian_alive": True,
                "guardian_visible": True,
                "guardian_on_screen": True,
                "hud_boss_visible": True,
                "guardian_visual_node_present": True,
                "guardian_visual_node_class": "AnimatedSprite2D",
                "guardian_root_visible_in_tree": True,
                "guardian_sprite_visible_in_tree": True,
                "guardian_root_opaque": True,
                "guardian_sprite_opaque": True,
                "guardian_frame_texture_present": True,
                "guardian_frame_texture_matches_field": True,
                "guardian_draw_rect_positive": True,
                "guardian_draw_rect_intersects_viewport": True,
                "guardian_visual_ready": True,
            },
            source,
        )
        return
    if state_kind == "iap_review":
        if not isinstance(product_id, str) or not product_id:
            raise RuntimeError(f"IAP review capture product contract is missing: {source}")
        _require_store_capture_values(
            guard,
            {
                "shop_visible": True,
                "shop_opaque": True,
                "shop_drawn_after_open": True,
                "shop_frame_inside_viewport": True,
                "preview_visible": False,
                "product_id": product_id,
                "card_visible": True,
                "card_visible_rect_ready": True,
                "card_opaque": True,
                "title_visible": True,
                "title_visible_rect_ready": True,
                "title_opaque": True,
                "title_text_nonempty": True,
                "title_copy_valid": True,
                "title_characters_visible": True,
                "title_font_size_positive": True,
                "title_font_alpha_readable": True,
                "title_rendered_text_ready": True,
                "review_fallback_verified": True,
                "review_status_visible": True,
                "review_status_copy_valid": True,
                "review_status_rendered_text_ready": True,
                "review_status_visible_rect_ready": True,
                "review_status_opaque": True,
                "price_visible": True,
                "price_copy_valid": True,
                "price_rendered_text_ready": True,
                "price_visible_rect_ready": True,
                "price_opaque": True,
                "action_visible": True,
                "action_enabled": False,
                "action_visible_rect_ready": True,
                "action_opaque": True,
                "action_text_nonempty": True,
                "action_copy_valid": True,
                "action_font_size_positive": True,
                "action_font_alpha_readable": True,
                "action_rendered_text_ready": True,
                "restore_visible": True,
                "restore_enabled": False,
                "restore_visible_rect_ready": True,
                "restore_opaque": True,
                "restore_text_nonempty": True,
                "restore_copy_valid": True,
                "restore_font_size_positive": True,
                "restore_font_alpha_readable": True,
                "restore_rendered_text_ready": True,
                "card_fully_inside_viewport": True,
                "card_inside_screen": True,
            },
            source,
        )
        title_text = guard.get("title_text")
        expected_title_text = guard.get("title_expected_text")
        review_title = IAP_REVIEW_TITLE_BY_PRODUCT.get(product_id)
        price_text = guard.get("price_text")
        expected_price_text = guard.get("price_expected_text")
        review_status_text = guard.get("review_status_text")
        expected_review_status_text = guard.get("review_status_expected_text")
        action_text = guard.get("action_text")
        expected_action_text = guard.get("action_expected_text")
        restore_text = guard.get("restore_text")
        expected_restore_text = guard.get("restore_expected_text")
        if not isinstance(review_title, str) \
                or title_text != review_title \
                or expected_title_text != review_title:
            raise RuntimeError(
                f"IAP submission Korean product title is invalid: {source}"
            )
        if price_text != IAP_REVIEW_FALLBACK_PRICE_TEXT \
                or expected_price_text != IAP_REVIEW_FALLBACK_PRICE_TEXT:
            raise RuntimeError(
                f"IAP direct-distribution price fallback is invalid: {source}"
            )
        if review_status_text != IAP_REVIEW_FALLBACK_STATUS_TEXT \
                or expected_review_status_text != IAP_REVIEW_FALLBACK_STATUS_TEXT:
            raise RuntimeError(
                f"IAP direct-distribution status copy is invalid: {source}"
            )
        if action_text != IAP_REVIEW_BUY_TEXT \
                or expected_action_text != IAP_REVIEW_BUY_TEXT:
            raise RuntimeError(
                f"IAP Buy button copy is invalid: {source}"
            )
        if restore_text != IAP_REVIEW_RESTORE_TEXT \
                or expected_restore_text != IAP_REVIEW_RESTORE_TEXT:
            raise RuntimeError(
                f"IAP Restore button copy is invalid: {source}"
            )
        if product_id.endswith(".supporter"):
            visual = {
                "artwork_visible": True,
                "artwork_kind": "supporter_app_icon",
                "artwork_item_count": 1,
                "artwork_node_present": True,
                "artwork_expected_kind": "supporter_app_icon",
                "artwork_expected_item_count": 1,
                "artwork_textures_ready": True,
                "artwork_visible_rect_ready": True,
                "artwork_opaque": True,
                "artwork_product_specific": True,
            }
        elif product_id.endswith(".lantern_colors"):
            visual = {
                "artwork_visible": True,
                "artwork_kind": "lantern_palette_flames",
                "artwork_item_count": 4,
                "artwork_node_present": True,
                "artwork_expected_kind": "lantern_palette_flames",
                "artwork_expected_item_count": 4,
                "artwork_textures_ready": True,
                "artwork_visible_rect_ready": True,
                "artwork_opaque": True,
                "artwork_product_specific": True,
            }
        elif ".continue_coin" in product_id:
            # Continue coin is a text-only card. Having no art is intentional, so
            # lock "none" as the contract — if any image sneaks in later,
            # the review image would change silently.
            visual = {
                "artwork_visible": False,
                "artwork_node_present": False,
                "portrait_visible": False,
            }
        else:
            hero_visual = STORE_CAPTURE_IAP_HERO_VISUALS.get(product_id)
            if hero_visual is None:
                raise RuntimeError(f"IAP hero SKU resource contract is missing: {source}")
            hero_path, portrait_path = hero_visual
            visual = {
                "portrait_visible": True,
                "portrait_visible_rect_ready": True,
                "portrait_opaque": True,
                "hero_resource_path": hero_path,
                "hero_expected_resource_path": hero_path,
                "portrait_resource_path": portrait_path,
                "portrait_expected_resource_path": portrait_path,
                "portrait_product_specific": True,
            }
        _require_store_capture_values(guard, visual, source)
        return
    raise RuntimeError(f"unsupported store capture state kind: {state_kind}")


def _store_capture_state_kind(source: str) -> str | None:
    if "/iap-review/" in source:
        return "iap_review"
    return {
        "01-moonlight-barrage.png": "moonlight_barrage",
        "02-field-guardian.png": "field_guardian",
        "04-title.png": "title",
        "05-moonlit-shrine.png": "shrine",
        "06-hero-preview.png": "hero_preview",
    }.get(Path(source).name)


def _validate_capture_report(
    entries: list[dict[str, object]],
) -> dict[str, object]:
    _assert_safe_repository_path(
        SCREENSHOT_CAPTURE_REPORT,
        REPO_ROOT / "builds/shots",
        "device capture proof",
    )
    if not SCREENSHOT_CAPTURE_REPORT.is_file():
        raise RuntimeError(
            "device capture proof file is missing. Run pnpm store:capture-screenshots "
            "first"
        )
    report = json.loads(SCREENSHOT_CAPTURE_REPORT.read_text(encoding="utf-8"))
    if report.get("schema") != 1 \
            or report.get("package") != "com.crossplatformkorea.moonlitbeacon" \
            or not isinstance(report.get("device"), str) \
            or not report.get("device") \
            or report.get("source_size") != {
                "width": SCREENSHOT_SOURCE_SIZE[0],
                "height": SCREENSHOT_SOURCE_SIZE[1],
            } \
            or report.get("locale_check") is not True:
        raise RuntimeError("device capture proof format/package/resolution contract is wrong")
    if report.get("canonical_publish_eligible") is not True \
            or report.get("canonical_root") \
                != str(SCREENSHOT_CAPTURE_REPORT.parent.relative_to(REPO_ROOT)) \
            or report.get("publication") \
                != "full-staging-then-atomic-directory-exchange" \
            or re.fullmatch(r"emulator-[0-9]+", str(report.get("device"))) \
                is None:
        raise RuntimeError("Pixel canonical atomic publish proof is invalid")
    _validate_android_capture_persistence(
        report,
        "Pixel phone",
        SCREENSHOT_CAPTURE_REPORT.parent,
    )
    _validate_android_avd_capture_evidence(
        report,
        "pixel-phone",
        ANDROID_PHONE_CAPTURE_CONTRACT,
        "Pixel phone",
        SCREENSHOT_CAPTURE_REPORT.parent,
    )
    if report.get("input_sha256") != _source_fingerprints():
        raise RuntimeError(
            "game UI/translations/fonts changed after capture. Recapture all 5 locales"
        )
    if report.get("runtime_sha256") != _runtime_fingerprint():
        raise RuntimeError(
            "character/terrain/runtime resources changed after capture. "
            "Recapture all 5 locales"
        )
    _assert_safe_repository_path(
        CAPTURE_DEBUG_APK,
        REPO_ROOT / "builds/shots",
        "capture debug APK",
    )
    if report.get("apk_path") != str(CAPTURE_DEBUG_APK.relative_to(REPO_ROOT)) \
            or not CAPTURE_DEBUG_APK.is_file() \
            or report.get("apk_sha256") != hashlib.sha256(
                CAPTURE_DEBUG_APK.read_bytes()).hexdigest() \
            or report.get("installed_apk_sha256") != report.get("apk_sha256"):
        raise RuntimeError(
            "preserved debug APK differs from the APK installed for device capture. "
            "Run pnpm store:capture-screenshots again"
        )
    attestation_path = _device_capture_repository_file(
        report.get("build_attestation_path"),
        "Pixel capture build attestation",
        allowed_root=SCREENSHOT_CAPTURE_REPORT.parent,
    )
    attestation_bytes = attestation_path.read_bytes()
    if report.get("build_attestation_sha256") \
            != hashlib.sha256(attestation_bytes).hexdigest() \
            or _read_device_capture_json(
                attestation_path,
                "Pixel capture build attestation",
            ) != report.get("build_attestation") \
            or report.get("build_attestation") != {
                "schema": 1,
                "apk_sha256": report.get("apk_sha256"),
                "runtime_sha256": report.get("runtime_sha256"),
                "input_sha256": report.get("input_sha256"),
            }:
        raise RuntimeError("Pixel capture build attestation source differs")

    expected: dict[
        str,
        tuple[str, str, str, str | None, str | None],
    ] = {}
    for entry in entries:
        sources = dict(entry["localized_sources"])
        scene = str(entry.get("scene", ""))
        clean_ui_proof = {
            "title": "title-hidden",
            "combat": "combat-hidden",
        }.get(scene)
        for locale, source in sources.items():
            expected[str(source)] = (
                locale,
                GAME_LOCALES[locale],
                scene,
                None,
                clean_ui_proof,
            )
    for review in _iap_review_entries():
        source = IAP_REVIEW_SOURCE_ROOT / str(review["output"])
        expected[str(source.relative_to(REPO_ROOT))] = (
            "ko-KR",
            "ko",
            "iap-review",
            str(review["product_id"]),
            None,
        )

    captures = report.get("captures")
    if not isinstance(captures, list):
        raise RuntimeError("device capture proof is missing a captures array")
    actual: dict[str, dict[str, object]] = {}
    hashes: set[str] = set()
    for capture in captures:
        if not isinstance(capture, dict) or not isinstance(capture.get("source"), str):
            raise RuntimeError("device capture proof entry is invalid")
        source = str(capture["source"])
        if source in actual:
            raise RuntimeError(f"device capture proof has a duplicate source: {source}")
        actual[source] = capture
        digest = str(capture.get("sha256", ""))
        if not digest or digest in hashes:
            raise RuntimeError(
                f"identical image reused across scene/locale: {source}"
            )
        hashes.add(digest)
    if set(actual) != set(expected):
        raise RuntimeError(
            "device capture proof and screenshots.json source lists differ "
            f"(missing={sorted(set(expected) - set(actual))}, "
            f"stale={sorted(set(actual) - set(expected))})"
        )

    for source, (
        locale,
        game_locale,
        capture_kind,
        product_id,
        clean_ui_proof,
    ) in expected.items():
        path = REPO_ROOT / source
        _assert_safe_repository_path(
            path,
            REPO_ROOT / "builds/shots",
            f"device capture {source}",
        )
        if not path.is_file():
            raise RuntimeError(f"device capture is missing: {path}")
        if _png_size(path) != SCREENSHOT_SOURCE_SIZE:
            raise RuntimeError(
                f"device capture is not Pixel 10 landscape {SCREENSHOT_SOURCE_SIZE[0]}x"
                f"{SCREENSHOT_SOURCE_SIZE[1]}: {path}"
            )
        capture = actual[source]
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if capture.get("asset_locale") != locale \
                or capture.get("game_locale") != game_locale \
                or capture.get("kind") != capture_kind \
                or capture.get("product_id") != product_id \
                or capture.get("clean_ui_proof") != clean_ui_proof \
                or capture.get("width") != SCREENSHOT_SOURCE_SIZE[0] \
                or capture.get("height") != SCREENSHOT_SOURCE_SIZE[1] \
                or capture.get("sha256") != digest:
            raise RuntimeError(
                "device capture saved locale/debug-UI-hidden or hash proof "
                f"is wrong: {source}"
            )
        expected_proof_path = str(Path(source).with_suffix(".proof.json"))
        if capture.get("proof_path") != expected_proof_path:
            raise RuntimeError(f"device capture proof path differs from contract: {source}")
        proof_path = _device_capture_repository_file(
            capture.get("proof_path"),
            f"Pixel capture proof {source}",
            allowed_root=SCREENSHOT_CAPTURE_REPORT.parent,
        )
        proof = _read_device_capture_json(proof_path, f"Pixel capture proof {source}")
        expected_proof = {
            "schema": 1,
            "source": source,
            "state_guard": capture.get("state_guard"),
            "capture_guard": capture.get("capture_guard"),
            "physical_safe_layout": capture.get("physical_safe_layout"),
            "clean_ui_proof": capture.get("clean_ui_proof"),
            "product_id": capture.get("product_id"),
        }
        if proof != expected_proof:
            raise RuntimeError(f"device capture proof bytes differ from report: {source}")
        _validate_missile_core_capture_guard(
            capture, source, locale, game_locale
        )
        state_kind = _store_capture_state_kind(source)
        if source.endswith("/03-missile-core-drop.png"):
            state_kind = "arena_ready"
        if state_kind is not None:
            _validate_store_capture_state_guard(
                capture,
                source,
                game_locale,
                state_kind,
                product_id,
            )
            state_guard = capture.get("state_guard")
            if not isinstance(state_guard, dict):
                raise RuntimeError(
                    f"device capture physical safe-area state_guard is missing: {source}"
                )
            _validate_capture_physical_safe_layout(
                capture,
                state_guard,
                SCREENSHOT_SOURCE_SIZE[0],
                SCREENSHOT_SOURCE_SIZE[1],
                source,
                viewport_field="screen_rect"
                if state_kind == "iap_review" else "viewport_rect",
            )
    expected_generation_files = {
        "capture-report.json",
        "capture-debug.apk",
        "capture-build-attestation.json",
        "avd-config.ini",
        "persistence-evidence.json",
        ANDROID_CAPTURE_SIGNATURE_FILENAME,
    }
    for source in expected:
        relative_source = Path(source).relative_to(
            SCREENSHOT_CAPTURE_REPORT.parent.relative_to(REPO_ROOT)
        )
        expected_generation_files.add(str(relative_source))
        expected_generation_files.add(str(relative_source.with_suffix(".proof.json")))
    actual_generation_files: set[str] = set()
    for path in SCREENSHOT_CAPTURE_REPORT.parent.rglob("*"):
        _assert_safe_repository_path(
            path,
            SCREENSHOT_CAPTURE_REPORT.parent,
            "Pixel canonical generation",
        )
        if path.is_file():
            actual_generation_files.add(
                str(path.relative_to(SCREENSHOT_CAPTURE_REPORT.parent))
            )
    if actual_generation_files != expected_generation_files:
        raise RuntimeError(
            "Pixel canonical generation file set differs from the full staging contract "
            f"(missing={sorted(expected_generation_files - actual_generation_files)}, "
            f"stale={sorted(actual_generation_files - expected_generation_files)})"
        )
    if _read_device_capture_json(
            SCREENSHOT_CAPTURE_REPORT, "Pixel canonical capture report") != report:
        raise RuntimeError("Pixel canonical capture report changed during validation")
    return report


def _is_sha256(value: object) -> bool:
    return isinstance(value, str) \
        and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def _validate_android_capture_persistence(
    report: dict[str, object],
    source: str,
    allowed_root: Path,
) -> None:
    if report.get("persistent_data_files") \
            != list(ANDROID_CAPTURE_PERSISTENT_FILES):
        raise RuntimeError(f"{source} permanent file list differs from the fixed contract")
    hash_maps: dict[str, dict[str, object]] = {}
    for field in (
        "persistent_data_sha256_before",
        "persistent_data_sha256_observed",
        "persistent_data_sha256_restored",
    ):
        value = report.get(field)
        if not isinstance(value, dict) \
                or set(value) != set(ANDROID_CAPTURE_PERSISTENT_FILES):
            raise RuntimeError(f"{source} {field} file list differs")
        if any(
            digest is not None and not _is_sha256(digest)
            for digest in value.values()
        ):
            raise RuntimeError(f"{source} {field} SHA-256 is invalid")
        hash_maps[field] = value
    before = hash_maps["persistent_data_sha256_before"]
    observed = hash_maps["persistent_data_sha256_observed"]
    restored = hash_maps["persistent_data_sha256_restored"]
    if before != restored:
        raise RuntimeError(f"{source} permanent file before/restored hashes differ")
    if report.get("persistent_data_mutated_during_capture") \
            is not (before != observed) \
            or report.get("persistent_data_restored_byte_exact") is not True \
            or report.get("persistent_data_unchanged") is not True:
        raise RuntimeError(f"{source} permanent file byte-exact restore flag is missing")
    settings = report.get("settings_restore")
    expected_setting_keys = {
        "original_present",
        "original_sha256",
        "observed_sha256",
        "restored_sha256",
        "byte_exact",
    }
    if not isinstance(settings, dict) or set(settings) != expected_setting_keys \
            or type(settings.get("original_present")) is not bool \
            or settings.get("byte_exact") is not True \
            or settings.get("original_sha256") != before["settings.cfg"] \
            or settings.get("observed_sha256") != observed["settings.cfg"] \
            or settings.get("restored_sha256") != restored["settings.cfg"] \
            or settings.get("original_present") \
                is not (before["settings.cfg"] is not None):
        raise RuntimeError(f"{source} settings.cfg byte-exact restore proof differs")
    if observed["settings.cfg"] is None:
        raise RuntimeError(f"{source} post-capture settings.cfg physical proof is missing")

    anchor = report.get("persistence_anchor")
    expected_anchor_keys = {"schema", "capture_id", "path", "sha256"}
    if not isinstance(anchor, dict) or set(anchor) != expected_anchor_keys \
            or anchor.get("schema") != 1 \
            or re.fullmatch(r"[0-9a-f]{64}", str(anchor.get("capture_id"))) \
                is None \
            or not _is_sha256(anchor.get("sha256")):
        raise RuntimeError(f"{source} persistence anchor format differs")
    anchor_path = _device_capture_repository_file(
        anchor.get("path"),
        f"{source} persistence anchor",
        allowed_root=allowed_root,
    )
    anchor_bytes = anchor_path.read_bytes()
    if hashlib.sha256(anchor_bytes).hexdigest() != anchor["sha256"]:
        raise RuntimeError(f"{source} persistence anchor source hash differs")
    try:
        transcript = json.loads(anchor_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(
            f"{source} persistence anchor JSON is invalid"
        ) from error
    expected_transcript_keys = {
        "schema",
        "capture_id",
        "persistent_data_files",
        "persistent_data_sha256_before",
        "persistent_data_sha256_observed",
        "persistent_data_sha256_restored",
        "settings_bytes",
    }
    if not isinstance(transcript, dict) \
            or set(transcript) != expected_transcript_keys \
            or transcript.get("schema") != 1 \
            or transcript.get("capture_id") != anchor["capture_id"] \
            or transcript.get("persistent_data_files") \
                != report["persistent_data_files"] \
            or transcript.get("persistent_data_sha256_before") != before \
            or transcript.get("persistent_data_sha256_observed") != observed \
            or transcript.get("persistent_data_sha256_restored") != restored:
        raise RuntimeError(f"{source} persistence anchor differs from report")
    settings_bytes = transcript.get("settings_bytes")
    expected_settings_bytes_keys = {
        "original_base64", "observed_base64", "restored_base64",
    }
    if not isinstance(settings_bytes, dict) \
            or set(settings_bytes) != expected_settings_bytes_keys:
        raise RuntimeError(f"{source} persistence settings anchor differs")

    def anchored_hash(field: str, *, required: bool = False) -> str | None:
        encoded = settings_bytes.get(field)
        if encoded is None:
            if required:
                raise RuntimeError(
                    f"{source} persistence {field} physical bytes are missing"
                )
            return None
        if not isinstance(encoded, str):
            raise RuntimeError(f"{source} persistence {field} is not Base64")
        try:
            decoded = base64.b64decode(encoded, validate=True)
        except (ValueError, binascii.Error) as error:
            raise RuntimeError(
                f"{source} persistence {field} Base64 is invalid"
            ) from error
        if base64.b64encode(decoded).decode("ascii") != encoded:
            raise RuntimeError(
                f"{source} persistence {field} Base64 is not canonical"
            )
        return hashlib.sha256(decoded).hexdigest()

    if anchored_hash("original_base64") != before["settings.cfg"] \
            or anchored_hash("observed_base64", required=True) \
                != observed["settings.cfg"] \
            or anchored_hash("restored_base64") != restored["settings.cfg"]:
        raise RuntimeError(f"{source} persistence settings bytes hash differs")

    _validate_android_capture_persistence_signature(
        report,
        source,
        allowed_root,
        anchor_bytes,
    )


def _android_capture_java_tools() -> tuple[Path, Path, dict[str, str]]:
    """Resolve trusted JDK tools without forwarding release credentials."""
    java_home = os.environ.get("JAVA_HOME", "").strip()
    if sys.platform == "darwin":
        discovery = subprocess.run(
            ["/usr/libexec/java_home", "-v", "17"],
            capture_output=True,
            check=False,
            env={
                "LANG": "C",
                "LC_ALL": "C",
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            },
            text=True,
            timeout=15,
        )
        if discovery.returncode == 0:
            java_home = discovery.stdout.strip()
    candidates: list[tuple[Path, Path]] = []
    if java_home:
        candidates.append((
            Path(java_home) / "bin" / "jarsigner",
            Path(java_home) / "bin" / "keytool",
        ))
    path_jarsigner = shutil.which("jarsigner")
    path_keytool = shutil.which("keytool")
    if path_jarsigner and path_keytool:
        candidates.append((Path(path_jarsigner), Path(path_keytool)))
    for jarsigner, keytool in candidates:
        if jarsigner.is_file() and keytool.is_file():
            child_env = {
                "LANG": "C",
                "LC_ALL": "C",
                "PATH": str(jarsigner.parent),
            }
            if java_home:
                child_env["JAVA_HOME"] = java_home
            return jarsigner, keytool, child_env
    raise RuntimeError("JDK 17 tools required to verify Android capture signatures are missing")


def _run_android_capture_java_tool(
    command: Path,
    arguments: list[str],
    child_env: dict[str, str],
    source: str,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            [str(command), *arguments],
            capture_output=True,
            check=False,
            env=child_env,
            text=True,
            timeout=300,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(
            f"{source} Android capture signature verification tool failed"
        ) from error


def _android_capture_jarsigner_output_is_signed(
    returncode: int,
    output: str,
) -> bool:
    return returncode == 0 \
        and re.search(
            r"(?:^|\r?\n)jar verified\.(?:\r?\n|$)",
            output,
        ) is not None \
        and re.search(
            r"(?:jar is unsigned|contains unsigned entries)",
            output,
            re.I,
        ) is None


def _verified_android_capture_signature_payloads(
    signature_path: Path,
    source: str,
) -> tuple[dict[str, bytes], str]:
    jarsigner, keytool, child_env = _android_capture_java_tools()
    verification = _run_android_capture_java_tool(
        jarsigner,
        # Do not use verbose listing here: the intentionally named signed
        # payload `capture-report.unsigned.json` would make a broad unsigned
        # warning detector mistake the filename for an unsigned ZIP entry.
        ["-verify", str(signature_path)],
        child_env,
        source,
    )
    verification_output = f"{verification.stdout}\n{verification.stderr}"
    if not _android_capture_jarsigner_output_is_signed(
        verification.returncode,
        verification_output,
    ):
        raise RuntimeError(
            f"{source} persistence signature JAR signature is invalid"
        )

    certificate_result = _run_android_capture_java_tool(
        keytool,
        ["-printcert", "-rfc", "-jarfile", str(signature_path)],
        child_env,
        source,
    )
    certificate_matches = re.findall(
        r"-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----",
        certificate_result.stdout,
    )
    if certificate_result.returncode != 0 or len(certificate_matches) != 1:
        raise RuntimeError(
            f"{source} could not read persistence signature certificate"
        )
    encoded_certificate = re.sub(r"\s", "", certificate_matches[0])
    try:
        certificate = base64.b64decode(encoded_certificate, validate=True)
    except (ValueError, binascii.Error) as error:
        raise RuntimeError(
            f"{source} persistence signature certificate is invalid"
        ) from error
    certificate_sha256 = hashlib.sha256(certificate).hexdigest()
    if certificate_sha256 != ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256:
        raise RuntimeError(
            f"{source} persistence signature signer differs from the upload key"
        )

    expected_entries = {
        "META-INF/",
        "META-INF/MANIFEST.MF",
        "META-INF/MOONLIT.SF",
        "META-INF/MOONLIT.RSA",
        ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY,
        ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY,
    }
    if signature_path.stat().st_size > 8 * 1024 * 1024:
        raise RuntimeError(f"{source} persistence signature JAR is too large")
    try:
        with zipfile.ZipFile(signature_path) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)) or set(names) != expected_entries:
                raise RuntimeError(
                    f"{source} persistence signature JAR entry differs"
                )
            if archive.testzip() is not None:
                raise RuntimeError(
                    f"{source} persistence signature JAR CRC is corrupt"
                )
            payloads = {
                ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY: archive.read(
                    ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY
                ),
                ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY: archive.read(
                    ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY
                ),
            }
    except (OSError, zipfile.BadZipFile, KeyError) as error:
        raise RuntimeError(
            f"{source} could not read persistence signature JAR payload"
        ) from error
    return payloads, certificate_sha256


def _validate_android_capture_persistence_signature(
    report: dict[str, object],
    source: str,
    allowed_root: Path,
    anchor_bytes: bytes,
) -> None:
    descriptor = report.get("persistence_signature")
    expected_keys = {
        "anchor_entry",
        "anchor_sha256",
        "capture_id",
        "certificate_sha256",
        "digest_algorithm",
        "format",
        "path",
        "report_entry",
        "report_sha256",
        "schema",
        "sha256",
        "signature_algorithm",
    }
    anchor = report.get("persistence_anchor")
    if not isinstance(descriptor, dict) or set(descriptor) != expected_keys \
            or descriptor.get("schema") != 1 \
            or descriptor.get("format") != "jar" \
            or descriptor.get("signature_algorithm") != "SHA256withRSA" \
            or descriptor.get("digest_algorithm") != "SHA-256" \
            or descriptor.get("certificate_sha256") \
                != ANDROID_CAPTURE_UPLOAD_CERTIFICATE_SHA256 \
            or descriptor.get("report_entry") \
                != ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY \
            or descriptor.get("anchor_entry") \
                != ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY \
            or not _is_sha256(descriptor.get("sha256")) \
            or not _is_sha256(descriptor.get("report_sha256")) \
            or not isinstance(anchor, dict) \
            or descriptor.get("anchor_sha256") != anchor.get("sha256") \
            or descriptor.get("capture_id") != anchor.get("capture_id"):
        raise RuntimeError(
            f"{source} persistence signature descriptor is invalid"
        )
    signature_path = _device_capture_repository_file(
        descriptor.get("path"),
        f"{source} persistence signature",
        allowed_root=allowed_root,
    )
    signature_bytes = signature_path.read_bytes()
    if hashlib.sha256(signature_bytes).hexdigest() != descriptor["sha256"]:
        raise RuntimeError(
            f"{source} persistence signature JAR source hash differs"
        )
    # Verify exactly the bytes hashed above. Reopening the mutable evidence path
    # for jarsigner, keytool and ZipFile would allow a same-user path-swap race
    # to present different archives to each verifier.
    with tempfile.TemporaryDirectory(
            prefix="moonlit-persistence-signature-") as temporary:
        temporary_root = Path(temporary)
        temporary_root.chmod(0o700)
        immutable_signature = temporary_root / ANDROID_CAPTURE_SIGNATURE_FILENAME
        with immutable_signature.open("xb") as output:
            output.write(signature_bytes)
        immutable_signature.chmod(0o600)
        payloads, certificate_sha256 = \
            _verified_android_capture_signature_payloads(
                immutable_signature,
                source,
            )
        if immutable_signature.read_bytes() != signature_bytes:
            raise RuntimeError(
                f"{source} persistence signature bytes changed during verification"
            )
    report_bytes = payloads[ANDROID_CAPTURE_SIGNATURE_REPORT_ENTRY]
    signed_anchor_bytes = payloads[ANDROID_CAPTURE_SIGNATURE_ANCHOR_ENTRY]
    if certificate_sha256 != descriptor["certificate_sha256"] \
            or hashlib.sha256(report_bytes).hexdigest() \
                != descriptor["report_sha256"] \
            or signed_anchor_bytes != anchor_bytes:
        raise RuntimeError(
            f"{source} persistence signature payload differs from report"
        )
    try:
        signed_report = json.loads(report_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(
            f"{source} persistence signed report JSON is invalid"
        ) from error
    unsigned_report = {
        key: value for key, value in report.items()
        if key != "persistence_signature"
    }
    if not isinstance(signed_report, dict) or signed_report != unsigned_report:
        raise RuntimeError(
            f"{source} persistence signed report differs from the final report"
        )


def _parse_android_avd_config(
    config_bytes: bytes,
    source: str,
) -> dict[str, object]:
    try:
        text = config_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError(f"{source} AVD config.ini is not UTF-8") from error
    required = {
        "abi.type": "abi_type",
        "hw.device.name": "hw_device_name",
        "hw.lcd.width": "hw_lcd_width",
        "hw.lcd.height": "hw_lcd_height",
        "hw.lcd.density": "hw_lcd_density",
        "image.sysdir.1": "image_sysdir",
    }
    values: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = (component.strip() for component in line.split("=", 1))
        if key not in required:
            continue
        if key in values:
            raise RuntimeError(f"{source} AVD config.ini {key} is duplicated")
        if not value:
            raise RuntimeError(f"{source} AVD config.ini {key} is empty")
        values[key] = value
    if set(values) != set(required):
        raise RuntimeError(f"{source} AVD config.ini required subset is missing")
    image_sysdir = values["image.sysdir.1"]
    api_match = re.fullmatch(
        r"system-images/android-([1-9][0-9]*)/(?:[^/]+/)+",
        image_sysdir,
    )
    if api_match is None:
        raise RuntimeError(f"{source} could not read AVD system image API")

    def positive_integer(key: str) -> int:
        value = values[key]
        if re.fullmatch(r"[1-9][0-9]*", value) is None:
            raise RuntimeError(f"{source} AVD config.ini {key} is not an integer")
        return int(value)

    return {
        "abi_type": values["abi.type"],
        "api_level": int(api_match.group(1)),
        "hw_device_name": values["hw.device.name"],
        "hw_lcd_width": positive_integer("hw.lcd.width"),
        "hw_lcd_height": positive_integer("hw.lcd.height"),
        "hw_lcd_density": positive_integer("hw.lcd.density"),
        "image_sysdir": image_sysdir,
    }


def _validate_android_avd_capture_evidence(
    report: dict[str, object],
    target: str,
    contract: dict[str, object],
    source: str,
    allowed_root: Path,
) -> Path:
    # ``wm size`` and config.ini describe the AVD's native display orientation.
    # Pixel_10 is 1080x2424 there, while the game screenshot is rotated to the
    # landscape ``source_size`` of 2424x1080.  Tablet targets happen to use the
    # same orientation for both, so using source_size here hid this distinction.
    expected_width, expected_height = contract["config_size"]
    physical_size = report.get("physical_size")
    density = report.get("density")
    if not isinstance(physical_size, dict) \
            or physical_size.get("width") != expected_width \
            or physical_size.get("height") != expected_height \
            or not isinstance(physical_size.get("raw"), str):
        raise RuntimeError(f"{source} Android physical screen size proof differs")
    physical_matches = re.findall(
        r"(?:Physical|Override) size:\s*(\d+)x(\d+)",
        str(physical_size["raw"]),
    )
    if not physical_matches \
            or tuple(map(int, physical_matches[-1])) \
                != (expected_width, expected_height):
        raise RuntimeError(f"{source} Android wm size raw text differs from reported value")
    expected_density = int(contract["density_dpi"])
    if not isinstance(density, dict) \
            or density.get("dpi") != expected_density \
            or not isinstance(density.get("raw"), str):
        raise RuntimeError(f"{source} Android density proof differs")
    density_matches = re.findall(
        r"(?:Physical|Override) density:\s*(\d+)",
        str(density["raw"]),
    )
    if not density_matches or int(density_matches[-1]) != expected_density:
        raise RuntimeError(f"{source} Android wm density raw text differs from reported value")
    if report.get("api_level") != contract["api_level"] \
            or report.get("avd_name") != contract["avd_name"]:
        raise RuntimeError(f"{source} Android API/AVD contract differs")

    proof = report.get("avd_config")
    expected_proof_keys = {
        "schema", "target", "avd_name", "normalized",
        "source_sha256", "normalized_sha256", "evidence_path",
    }
    if not isinstance(proof, dict) or set(proof) != expected_proof_keys \
            or proof.get("schema") != 1 \
            or proof.get("target") != target \
            or proof.get("avd_name") != contract["avd_name"] \
            or not _is_sha256(proof.get("source_sha256")) \
            or not _is_sha256(proof.get("normalized_sha256")):
        raise RuntimeError(f"{source} AVD config proof format is invalid")
    config_path = _device_capture_repository_file(
        proof.get("evidence_path"),
        f"{source} AVD config source",
        allowed_root=allowed_root,
    )
    if config_path.name != "avd-config.ini":
        raise RuntimeError(f"{source} AVD config evidence filename differs")
    config_bytes = config_path.read_bytes()
    if hashlib.sha256(config_bytes).hexdigest() != proof["source_sha256"]:
        raise RuntimeError(f"{source} AVD config source bytes hash differs")
    normalized = _parse_android_avd_config(config_bytes, source)
    config_width, config_height = contract["config_size"]
    expected_normalized = {
        "abi_type": contract["abi_type"],
        "api_level": contract["api_level"],
        "hw_device_name": contract["hw_device_name"],
        "hw_lcd_width": config_width,
        "hw_lcd_height": config_height,
        "hw_lcd_density": expected_density,
        "image_sysdir": contract["image_sysdir"],
    }
    if normalized != expected_normalized or proof.get("normalized") != normalized:
        raise RuntimeError(f"{source} AVD config normalized subset differs from contract")
    normalized_bytes = (
        json.dumps(
            normalized,
            ensure_ascii=False,
            separators=(",", ":"),
        ) + "\n"
    ).encode("utf-8")
    if hashlib.sha256(normalized_bytes).hexdigest() \
            != proof["normalized_sha256"]:
        raise RuntimeError(f"{source} AVD normalized subset hash differs")
    return config_path


def _device_capture_source_fingerprints(platform: str) -> dict[str, str]:
    if platform == "android":
        relative_paths = ANDROID_DEVICE_CAPTURE_SOURCE_INPUTS
    elif platform == "ios":
        relative_paths = IOS_DEVICE_CAPTURE_SOURCE_INPUTS
    else:
        raise RuntimeError(f"unsupported device capture platform: {platform}")
    fingerprints: dict[str, str] = {}
    for relative_path in relative_paths:
        path = REPO_ROOT / relative_path
        _assert_safe_repository_path(
            path,
            REPO_ROOT,
            f"{platform} device capture source input {relative_path}",
        )
        if not path.is_file():
            raise RuntimeError(
                f"{platform} device capture source input is missing: {relative_path}"
            )
        fingerprints[relative_path] = hashlib.sha256(
            path.read_bytes()
        ).hexdigest()
    return fingerprints


def _device_capture_repository_file(
    value: object,
    label: str,
    *,
    allowed_root: Path | None = None,
) -> Path:
    relative_path = Path(value) if isinstance(value, str) else None
    if relative_path is None \
            or relative_path.is_absolute() \
            or ".." in relative_path.parts:
        raise RuntimeError(f"{label} relative path is invalid: {value!r}")
    path = REPO_ROOT / relative_path
    _assert_safe_repository_path(
        path,
        allowed_root or REPO_ROOT / "builds",
        label,
    )
    if not path.is_file():
        raise RuntimeError(f"{label} file is missing: {path}")
    return path


def _read_device_capture_json_bytes(
    contents: bytes,
    label: str,
) -> dict[str, object]:
    try:
        value = json.loads(contents.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{label} could not read JSON") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"{label} JSON is not an object")
    return value


def _read_device_capture_json(path: Path, label: str) -> dict[str, object]:
    try:
        contents = path.read_bytes()
    except OSError as error:
        raise RuntimeError(f"{label} could not read JSON: {path}") from error
    return _read_device_capture_json_bytes(contents, f"{label}: {path}")


def _device_capture_current_snapshot(platform: str) -> dict[str, object]:
    return {
        "runtime_sha256": _runtime_fingerprint(),
        "source_input_sha256": _device_capture_source_fingerprints(platform),
    }


def _ios_app_archive_identity(
    artifact_bytes: bytes,
    source: str,
) -> dict[str, object]:
    """Recompute the installed .app identity directly from the frozen ZIP."""
    app_root = "MoonlitBeacon.app"
    maximum_entries = 100_000
    maximum_uncompressed_bytes = 512 * 1024 * 1024
    maximum_entry_bytes = 256 * 1024 * 1024

    def invalid(detail: str) -> RuntimeError:
        return RuntimeError(f"{source} iOS preserved ZIP {detail}")

    try:
        archive = zipfile.ZipFile(io.BytesIO(artifact_bytes), "r")
    except (OSError, zipfile.BadZipFile) as error:
        raise invalid("cannot be opened") from error

    with archive:
        infos = archive.infolist()
        if not infos or len(infos) > maximum_entries:
            raise invalid("entry count is outside the allowed range")
        total_size = 0
        archive_names: set[str] = set()
        portable_names: set[str] = set()
        # relative path -> (kind, permission mode, ZipInfo)
        entries: dict[str, tuple[str, int, zipfile.ZipInfo]] = {}
        for info in infos:
            raw_name = info.filename
            is_directory_marker = raw_name.endswith("/")
            canonical_name = raw_name[:-1] if is_directory_marker else raw_name
            parts = canonical_name.split("/")
            if not canonical_name \
                    or raw_name.startswith("/") \
                    or "\\" in raw_name \
                    or "\x00" in raw_name \
                    or any(part in ("", ".", "..") for part in parts) \
                    or canonical_name in archive_names \
                    or info.flag_bits & 0x1:
                raise invalid(f"entry path/encryption is invalid: {raw_name!r}")
            try:
                canonical_name.encode("utf-8", errors="strict")
            except UnicodeEncodeError as error:
                raise invalid(f"entry path is not UTF-8: {raw_name!r}") from error
            archive_names.add(canonical_name)
            portable_name = unicodedata.normalize(
                "NFC", canonical_name
            ).casefold()
            if portable_name in portable_names:
                raise invalid(f"NFC/casefold path collides: {raw_name!r}")
            portable_names.add(portable_name)
            total_size += info.file_size
            if info.file_size > maximum_entry_bytes \
                    or total_size > maximum_uncompressed_bytes:
                raise invalid("uncompressed size is outside the allowed range")
            if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                raise invalid(f"unsupported compression method: {raw_name}")
            if parts[0] == "__MACOSX":
                continue
            if parts[0] != app_root:
                raise invalid(f"unexpected top-level entry: {raw_name}")

            relative_path = "." if len(parts) == 1 else "/".join(parts[1:])
            unix_mode = (info.external_attr >> 16) & 0xffff
            file_type = stat.S_IFMT(unix_mode)
            if is_directory_marker:
                if info.file_size != 0 or file_type not in (0, stat.S_IFDIR):
                    raise invalid(f"directory type is invalid: {raw_name}")
                kind = "directory"
            elif file_type == stat.S_IFLNK:
                kind = "symlink"
            elif file_type in (0, stat.S_IFREG):
                kind = "file"
            else:
                raise invalid(f"unsupported entry type: {raw_name}")
            entries[relative_path] = (kind, unix_mode & 0o7777, info)

        try:
            corrupt = archive.testzip()
        except (OSError, RuntimeError, zipfile.BadZipFile) as error:
            raise invalid("CRC/compression stream check failed") from error
        if corrupt is not None:
            raise invalid(f"CRC is wrong: {corrupt}")
        if entries.get(".", (None, 0, None))[0] != "directory":
            raise invalid(f"{app_root} root directory is missing")

        children: dict[str, list[str]] = {
            path: [] for path, (kind, _, _) in entries.items()
            if kind == "directory"
        }
        for path in entries:
            if path == ".":
                continue
            parent, _, name = path.rpartition("/")
            parent = parent or "."
            if parent not in children:
                raise invalid(f"explicit parent directory is missing: {path}")
            children[parent].append(name)

        digest = hashlib.sha256()

        def update_length_prefixed(value: bytes) -> None:
            digest.update(len(value).to_bytes(8, "big"))
            digest.update(value)

        def read_payload(info: zipfile.ZipInfo, label: str) -> bytes:
            try:
                payload = archive.read(info)
            except (OSError, RuntimeError, zipfile.BadZipFile) as error:
                raise invalid(f"could not read {label} bytes") from error
            if len(payload) != info.file_size:
                raise invalid(f"{label} size differs from ZIP metadata")
            return payload

        def visit(path: str) -> None:
            kind, mode, info = entries[path]
            payload = b"" if kind == "directory" else read_payload(info, path)
            if kind == "symlink":
                try:
                    target = payload.decode("utf-8", errors="strict")
                except UnicodeDecodeError as error:
                    raise invalid(f"symlink target is not UTF-8: {path}") from error
                resolved_target = posixpath.normpath(posixpath.join(
                    posixpath.dirname(path), target
                ))
                if not target \
                        or target.startswith("/") \
                        or "\\" in target \
                        or "\x00" in target \
                        or resolved_target == ".." \
                        or resolved_target.startswith("../"):
                    raise invalid(f"symlink target is outside the .app root: {path}")
            for value in (
                kind.encode("utf-8"),
                path.encode("utf-8"),
                str(mode).encode("utf-8"),
                payload,
            ):
                update_length_prefixed(value)
            if kind == "directory":
                # JavaScript Array.sort compares UTF-16 code units.
                for name in sorted(
                    children[path],
                    key=lambda value: value.encode("utf-16-be"),
                ):
                    visit(name if path == "." else f"{path}/{name}")

        visit(".")

        required_files = {
            "Info.plist": "Info.plist",
            "executable": "MoonlitBeacon",
            "pck": "MoonlitBeacon.pck",
        }
        payloads: dict[str, bytes] = {}
        for label, path in required_files.items():
            entry = entries.get(path)
            if entry is None or entry[0] != "file":
                raise invalid(f"{path} regular file is missing")
            payloads[label] = read_payload(entry[2], path)
        if entries["MoonlitBeacon"][1] & 0o111 == 0:
            raise invalid("executable is missing the execute bit")
        try:
            plist = plistlib.loads(payloads["Info.plist"])
        except (plistlib.InvalidFileException, ValueError) as error:
            raise invalid("could not read Info.plist") from error
        if not isinstance(plist, dict):
            raise invalid("Info.plist is not a dictionary")
        return {
            "bundle_id": plist.get("CFBundleIdentifier"),
            "executable_name": plist.get("CFBundleExecutable"),
            "short_version": plist.get("CFBundleShortVersionString"),
            "build_version": plist.get("CFBundleVersion"),
            "app_tree_sha256": digest.hexdigest(),
            "executable_sha256": hashlib.sha256(
                payloads["executable"]
            ).hexdigest(),
            "pck_sha256": hashlib.sha256(payloads["pck"]).hexdigest(),
        }


def _validate_ios_install_receipts(
    report: dict[str, object],
    source: str,
    expected_run_root: Path,
) -> None:
    evidence_root = REPO_ROOT / "builds/ios-device-evidence" / source
    install_path = _device_capture_repository_file(
        report.get("install_result_path"),
        f"{source} iOS install receipt",
        allowed_root=evidence_root,
    )
    installed_path = _device_capture_repository_file(
        report.get("installed_app_path"),
        f"{source} iOS installed-app receipt",
        allowed_root=evidence_root,
    )
    if install_path.name != "install.json" \
            or installed_path.name != "installed-app.json" \
            or install_path.parent != expected_run_root \
            or installed_path.parent != expected_run_root:
        raise RuntimeError(f"{source} iOS install receipt run root differs")
    install_bytes = install_path.read_bytes()
    installed_bytes = installed_path.read_bytes()
    if not _is_sha256(report.get("install_result_sha256")) \
            or hashlib.sha256(install_bytes).hexdigest() \
                != report["install_result_sha256"] \
            or not _is_sha256(report.get("installed_app_sha256")) \
            or hashlib.sha256(installed_bytes).hexdigest() \
                != report["installed_app_sha256"]:
        raise RuntimeError(f"{source} iOS install receipt hash differs")
    install = _read_device_capture_json_bytes(
        install_bytes, f"{source} install receipt"
    )
    installed = _read_device_capture_json_bytes(
        installed_bytes, f"{source} installed-app receipt"
    )
    install_info = install.get("info")
    install_result = install.get("result")
    installed_info = installed.get("info")
    installed_result = installed.get("result")
    applications = install_result.get("installedApplications") \
        if isinstance(install_result, dict) else None
    queried_apps = installed_result.get("apps") \
        if isinstance(installed_result, dict) else None
    bundle_id = report.get("installed_capture_bundle_id")
    if not isinstance(install_info, dict) \
            or install_info.get("outcome") != "success" \
            or install_info.get("commandType") != "devicectl.device.install.app" \
            or not isinstance(install_result, dict) \
            or install_result.get("deviceIdentifier") \
                != report.get("coredevice_identifier") \
            or not isinstance(applications, list) \
            or len(applications) != 1 \
            or not isinstance(applications[0], dict) \
            or applications[0].get("bundleID") != bundle_id \
            or not isinstance(applications[0].get("installationURL"), str) \
            or not applications[0]["installationURL"].endswith(
                "/MoonlitBeacon.app/"
            ):
        raise RuntimeError(f"{source} CoreDevice install receipt is invalid")
    matches = [
        app for app in queried_apps
        if isinstance(app, dict) and app.get("bundleIdentifier") == bundle_id
    ] if isinstance(queried_apps, list) else []
    if not isinstance(installed_info, dict) \
            or installed_info.get("outcome") != "success" \
            or installed_info.get("commandType") \
                != "devicectl.device.info.apps" \
            or not isinstance(installed_result, dict) \
            or installed_result.get("deviceIdentifier") \
                != report.get("coredevice_identifier") \
            or installed_result.get("matchingBundleIdentifier") != bundle_id \
            or len(matches) != 1:
        raise RuntimeError(f"{source} CoreDevice installed-app receipt is invalid")
    app = matches[0]
    if app.get("version") != report.get("short_version") \
            or app.get("bundleVersion") != report.get("build_version") \
            or app.get("builtByDeveloper") is not True \
            or app.get("removable") is not True \
            or app.get("url") != applications[0]["installationURL"]:
        raise RuntimeError(f"{source} installed iOS app identity differs")
    identity_bytes = json.dumps(
        {
            "bundleIdentifier": app.get("bundleIdentifier"),
            "bundleVersion": app.get("bundleVersion"),
            "version": app.get("version"),
            "url": app.get("url"),
        },
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    if not _is_sha256(report.get("installed_identity_sha256")) \
            or hashlib.sha256(identity_bytes).hexdigest() \
                != report["installed_identity_sha256"]:
        raise RuntimeError(f"{source} installed iOS identity hash differs")


def _validate_device_capture_build(
    report: dict[str, object],
    platform: str,
    source: str,
) -> str:
    current = _device_capture_current_snapshot(platform)
    for field in (
        "source_before_build",
        "source_after_build",
        "source_before",
        "source_after",
    ):
        if report.get(field) != current:
            raise RuntimeError(
                f"{source} {field} differs from the current source. Recreate the "
                "device capture"
            )
    if report.get("source_byte_equivalent") is not True:
        raise RuntimeError(f"{source} source byte-equivalent proof is missing")

    if platform == "android":
        artifact_path_field = "apk_path"
        artifact_hash_field = "apk_sha256"
        installed_hash_field = "installed_apk_sha256"
        attestation_hash_field = "apk_sha256"
    else:
        artifact_path_field = "build_artifact_path"
        artifact_hash_field = "build_artifact_sha256"
        installed_hash_field = "installed_artifact_sha256"
        attestation_hash_field = "artifact_sha256"
    artifact_hash = report.get(artifact_hash_field)
    if not _is_sha256(artifact_hash) \
            or report.get(installed_hash_field) != artifact_hash:
        raise RuntimeError(
            f"{source} capture build and install build hashes differ"
        )
    artifact_path = _device_capture_repository_file(
        report.get(artifact_path_field),
        f"{source} preserved build",
    )
    artifact_bytes = artifact_path.read_bytes()
    if hashlib.sha256(artifact_bytes).hexdigest() != artifact_hash:
        raise RuntimeError(f"{source} preserved build was tampered with after the report")

    attestation = report.get("build_attestation")
    if not isinstance(attestation, dict) \
            or type(attestation.get("schema")) is not int \
            or attestation.get(attestation_hash_field) != artifact_hash \
            or attestation.get("runtime_sha256") != current["runtime_sha256"] \
            or attestation.get("input_sha256") \
                != current["source_input_sha256"]:
        raise RuntimeError(f"{source} build attestation differs from the current build")
    if platform == "android":
        if attestation.get("schema") != 1:
            raise RuntimeError(f"{source} Android build attestation schema differs")
    elif attestation.get("schema") != 2 \
            or attestation.get("production_bundle_id") \
                != "com.crossplatformkorea.moonlitbeacon" \
            or attestation.get("installed_bundle_id") \
                != report.get("installed_capture_bundle_id") \
            or attestation.get("isolated_capture_bundle") \
                is not report.get("isolated_capture_bundle") \
            or attestation.get("content_equivalence") \
                != "same-fresh-exported-pck-production-runtime" \
            or not _is_sha256(attestation.get("app_tree_sha256")) \
            or attestation.get("app_tree_sha256") \
                != report.get("app_tree_sha256") \
            or not _is_sha256(attestation.get("executable_sha256")) \
            or attestation.get("executable_sha256") \
                != report.get("executable_sha256") \
            or not _is_sha256(attestation.get("pck_sha256")) \
            or attestation.get("pck_sha256") != report.get("pck_sha256") \
            or attestation.get("exported_pck_sha256") \
                != attestation.get("pck_sha256") \
            or report.get("exported_pck_sha256") \
                != attestation.get("pck_sha256"):
        raise RuntimeError(f"{source} iOS capture content identity attestation differs")
    if platform == "ios":
        if artifact_path.name != "MoonlitBeacon.app.zip":
            raise RuntimeError(f"{source} iOS preserved build filename differs")
        archive_identity = _ios_app_archive_identity(artifact_bytes, source)
        if archive_identity != {
            "bundle_id": report.get("installed_capture_bundle_id"),
            "executable_name": "MoonlitBeacon",
            "short_version": report.get("short_version"),
            "build_version": report.get("build_version"),
            "app_tree_sha256": report.get("app_tree_sha256"),
            "executable_sha256": report.get("executable_sha256"),
            "pck_sha256": report.get("pck_sha256"),
        }:
            raise RuntimeError(
                f"{source} iOS preserved ZIP internal identity/content differs from the report"
            )
    attestation_path = _device_capture_repository_file(
        report.get("build_attestation_path"),
        f"{source} build attestation",
    )
    if platform == "ios":
        run_root = artifact_path.parent.parent
        if artifact_path.parent.name != "build" \
                or attestation_path.parent != run_root:
            raise RuntimeError(f"{source} iOS build/attestation run root differs")
        _validate_ios_install_receipts(report, source, run_root)
    attestation_bytes = attestation_path.read_bytes()
    if report.get("build_attestation_sha256") \
            != hashlib.sha256(attestation_bytes).hexdigest() \
            or _read_device_capture_json_bytes(
                attestation_bytes,
                f"{source} build attestation",
            ) != attestation:
        raise RuntimeError(
            f"{source} preserved build attestation differs from the report"
        )
    return str(artifact_hash)


def _device_capture_controls(
    state_kind: str,
    expected_direct_distribution: bool = True,
) -> tuple[str, ...]:
    if state_kind == "title":
        return STORE_CAPTURE_TITLE_DIRECT_SAFE_CONTROLS \
            if expected_direct_distribution \
            else STORE_CAPTURE_TITLE_SAFE_CONTROLS
    if state_kind == "shrine":
        return ("shrine_frame",)
    if state_kind == "hero_preview":
        return ("shrine_frame", "preview_frame", "close")
    return STORE_CAPTURE_ARENA_SAFE_CONTROLS


def _require_close_number(
    actual: object,
    expected: float,
    source: str,
    field: str,
    tolerance: float = 0.05,
) -> None:
    if type(actual) not in (int, float) \
            or not math.isfinite(actual) \
            or abs(actual - expected) > tolerance:
        raise RuntimeError(
            f"{source} {field} numeric proof differs from actual coordinates"
        )


def _validate_capture_physical_safe_layout(
    capture: dict[str, object],
    runtime_state: dict[str, object],
    width: int,
    height: int,
    source: str,
    *,
    viewport_field: str = "viewport_rect",
) -> None:
    viewport = _require_store_capture_rect(
        runtime_state, viewport_field, source
    )
    safe_rect = _require_store_capture_rect(runtime_state, "safe_rect", source)
    if not _store_capture_rect_fully_inside(safe_rect, viewport):
        raise RuntimeError(f"{source} safe_rect is outside the viewport")
    expected_logical_insets = {
        "left": safe_rect[0] - viewport[0],
        "top": safe_rect[1] - viewport[1],
        "right": viewport[0] + viewport[2] - safe_rect[0] - safe_rect[2],
        "bottom": viewport[1] + viewport[3] - safe_rect[1] - safe_rect[3],
    }
    scale_x = width / viewport[2]
    scale_y = height / viewport[3]
    if abs(scale_x - scale_y) / max(scale_x, scale_y) > 0.02:
        raise RuntimeError(f"{source} PNG and Godot viewport scale differ")
    physical_insets = {
        "left": expected_logical_insets["left"] * scale_x,
        "top": expected_logical_insets["top"] * scale_y,
        "right": expected_logical_insets["right"] * scale_x,
        "bottom": expected_logical_insets["bottom"] * scale_y,
    }
    for edge, inset in physical_insets.items():
        if inset + 0.05 < 34.0:
            raise RuntimeError(
                f"{source} {edge} physical safe-area inset is below 34px"
            )
    physical = capture.get("physical_safe_layout")
    if not isinstance(physical, dict) \
            or physical.get("png_size") != [width, height] \
            or physical.get("minimum_physical_inset") != 34:
        raise RuntimeError(f"{source} physical safe-area proof is invalid")
    viewport_scale = physical.get("viewport_scale")
    reported_insets = physical.get("physical_insets")
    if not isinstance(viewport_scale, dict) or not isinstance(reported_insets, dict):
        raise RuntimeError(f"{source} physical safe-area coordinates are missing")
    _require_close_number(
        viewport_scale.get("x"), scale_x, source, "viewport_scale.x"
    )
    _require_close_number(
        viewport_scale.get("y"), scale_y, source, "viewport_scale.y"
    )
    for edge, expected in physical_insets.items():
        _require_close_number(
            reported_insets.get(edge),
            expected,
            source,
            f"physical_insets.{edge}",
        )


def _validate_device_capture_safe_proof(
    capture: dict[str, object],
    runtime_state: dict[str, object],
    state_kind: str,
    width: int,
    height: int,
    source: str,
    expected_direct_distribution: bool,
) -> None:
    viewport = _require_store_capture_rect(
        runtime_state, "viewport_rect", source
    )
    safe_rect = _require_store_capture_rect(runtime_state, "safe_rect", source)
    safe_layout = capture.get("safe_layout")
    if not isinstance(safe_layout, dict) \
            or safe_layout.get("viewport_rect") != viewport \
            or safe_layout.get("safe_rect") != safe_rect:
        raise RuntimeError(
            f"{source} capture safe-area proof differs from runtime coordinates"
        )
    logical_insets = safe_layout.get("logical_insets")
    expected_logical_insets = {
        "left": safe_rect[0] - viewport[0],
        "top": safe_rect[1] - viewport[1],
        "right": viewport[0] + viewport[2] - safe_rect[0] - safe_rect[2],
        "bottom": viewport[1] + viewport[3] - safe_rect[1] - safe_rect[3],
    }
    if not isinstance(logical_insets, dict):
        raise RuntimeError(f"{source} logical safe-area inset is missing")
    for edge, expected in expected_logical_insets.items():
        _require_close_number(
            logical_insets.get(edge), expected, source, f"logical_insets.{edge}"
        )
    controls = safe_layout.get("controls")
    expected_controls = _device_capture_controls(
        state_kind, expected_direct_distribution
    )
    if not isinstance(controls, dict) \
            or set(controls) != {f"{name}_rect" for name in expected_controls}:
        raise RuntimeError(f"{source} safe-area UI list is invalid")
    for control in expected_controls:
        rect_field = f"{control}_rect"
        if controls.get(rect_field) \
                != _require_store_capture_rect(runtime_state, rect_field, source):
            raise RuntimeError(
                f"{source} {rect_field} proof differs from runtime coordinates"
            )
    _validate_capture_physical_safe_layout(
        capture,
        runtime_state,
        width,
        height,
        source,
    )


def _validate_device_capture_runtime_proof(
    capture: dict[str, object],
    source: str,
    game_locale: str,
    capture_kind: str,
    expected_direct_distribution: bool,
) -> None:
    runtime_before = capture.get("runtime_before")
    runtime_after = capture.get("runtime_after")
    if not isinstance(runtime_before, dict) or not isinstance(runtime_after, dict):
        raise RuntimeError(f"{source} pre/post screenshot runtime proof is missing")
    before_observation = runtime_before.get("observation")
    after_observation = runtime_after.get("observation")
    if not _is_javascript_safe_integer(before_observation, 1) \
            or not _is_javascript_safe_integer(after_observation, 1) \
            or after_observation <= before_observation \
            or runtime_before.get("nonce") != runtime_after.get("nonce") \
            or capture.get("runtime_nonce") != runtime_before.get("nonce"):
        raise RuntimeError(f"{source} pre/post screenshot observation proof is unstable")
    state_kind = "arena_ready" \
        if capture_kind == "missile_core_recovery" else capture_kind
    before_guard = dict(runtime_before)
    before_guard["observation_after"] = after_observation
    _validate_store_capture_state_guard(
        {"state_guard": before_guard},
        source,
        game_locale,
        state_kind,
        expected_direct_distribution=expected_direct_distribution,
    )
    after_guard = dict(runtime_after)
    after_guard["observation"] = before_observation
    after_guard["observation_after"] = after_observation
    _validate_store_capture_state_guard(
        {"state_guard": after_guard},
        source,
        game_locale,
        state_kind,
        expected_direct_distribution=expected_direct_distribution,
    )

    if capture_kind == "missile_core_recovery":
        missile_before = capture.get("missile_before")
        missile_after = capture.get("missile_after")
        if not isinstance(missile_before, dict) \
                or not isinstance(missile_after, dict):
            raise RuntimeError(f"{source} missile-core before/after proof is missing")
        _validate_missile_core_capture_guard(
            {"capture_guard": missile_before},
            source,
            str(capture.get("asset_locale")),
            game_locale,
        )
        _validate_missile_core_capture_guard(
            {"capture_guard": missile_after},
            source,
            str(capture.get("asset_locale")),
            game_locale,
        )

    proof_path = _device_capture_repository_file(
        capture.get("proof_path"),
        f"{source} state proof",
    )
    proof = _read_device_capture_json(proof_path, f"{source} state proof")
    if capture_kind == "missile_core_recovery":
        expected_proof = {
            "before": capture.get("missile_before"),
            "after": capture.get("missile_after"),
            "runtime_before": runtime_before,
            "runtime_after": runtime_after,
        }
    else:
        expected_proof = {
            "before": runtime_before,
            "after": runtime_after,
        }
    if any(proof.get(field) != value for field, value in expected_proof.items()):
        raise RuntimeError(f"{source} preserved state proof differs from the report")


def _validate_android_tablet_device_proof(
    report: dict[str, object],
    device: str,
    contract: dict[str, object],
) -> None:
    expected_width, expected_height = contract["source_size"]
    avd_config_evidence_path = _validate_android_avd_capture_evidence(
        report,
        device,
        contract,
        device,
        REPO_ROOT / "builds/tablet-evidence" / device,
    )

    window_dump_path = _device_capture_repository_file(
        report.get("window_dump_path"),
        f"{device} Android window dump",
        allowed_root=REPO_ROOT / "builds/tablet-evidence" / device,
    )
    if avd_config_evidence_path.parent != window_dump_path.parent:
        raise RuntimeError(
            f"{device} AVD config and window dump are not from the same capture run"
        )
    window_dump_bytes = window_dump_path.read_bytes()
    if report.get("window_dump_sha256") \
            != hashlib.sha256(window_dump_bytes).hexdigest():
        raise RuntimeError(f"{device} Android window dump hash differs")
    try:
        window_dump = window_dump_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError(
            f"{device} Android window dump is not UTF-8"
        ) from error
    gesture_lines = list(dict.fromkeys(
        line.strip()
        for line in window_dump.splitlines()
        if re.search(
            r"type=(?:systemGestures|mandatorySystemGestures)", line
        )
    ))
    if not gesture_lines or report.get("window_gesture_insets") != gesture_lines:
        raise RuntimeError(f"{device} Android gesture inset list differs")
    required_frames = {
        "LEFT": (0, 0, 30, expected_height),
        "TOP": (0, 0, expected_width, 24),
        "RIGHT": (
            expected_width - 30, 0, expected_width, expected_height,
        ),
        "BOTTOM": (
            0, expected_height - 32, expected_width, expected_height,
        ),
    }
    for side, (x1, y1, x2, y2) in required_frames.items():
        pattern = re.compile(
            rf"type=(?:systemGestures|mandatorySystemGestures).*"
            rf"frame=\[{x1},{y1}\]\[{x2},{y2}\].*sideHint={side}"
        )
        if not any(pattern.search(line) for line in gesture_lines):
            raise RuntimeError(
                f"{device} Android {side} gesture inset proof is missing"
            )


def _validate_ios_coredevice_details(
    report: dict[str, object],
    device: str,
    path_value: object,
    hash_value: object,
    label: str,
) -> Path:
    path = _device_capture_repository_file(
        path_value,
        f"{device} {label}",
        allowed_root=REPO_ROOT / "builds/ios-device-evidence" / device,
    )
    contents = path.read_bytes()
    if not _is_sha256(hash_value) \
            or hashlib.sha256(contents).hexdigest() != hash_value:
        raise RuntimeError(f"{device} {label} hash differs")
    try:
        payload = json.loads(contents)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{device} {label} JSON is invalid") from error
    result = payload.get("result") if isinstance(payload, dict) else None
    info = payload.get("info") if isinstance(payload, dict) else None
    hardware = result.get("hardwareProperties") \
        if isinstance(result, dict) else None
    properties = result.get("deviceProperties") \
        if isinstance(result, dict) else None
    connection = result.get("connectionProperties") \
        if isinstance(result, dict) else None
    if not isinstance(info, dict) or info.get("outcome") != "success" \
            or not isinstance(hardware, dict) \
            or not isinstance(properties, dict) \
            or not isinstance(connection, dict) \
            or result.get("identifier") != report.get("coredevice_identifier") \
            or hardware.get("reality") != "physical" \
            or hardware.get("udid") != report.get("device_udid") \
            or hardware.get("productType") != report.get("model_identifier") \
            or properties.get("name") != report.get("device_name") \
            or properties.get("osVersionNumber") != report.get("os_version") \
            or properties.get("osBuildUpdate") != report.get("os_build") \
            or properties.get("bootState") != "booted" \
            or properties.get("developerModeStatus") != "enabled" \
            or connection.get("pairingState") != "paired" \
            or connection.get("transportType") != report.get("transport") \
            or connection.get("transportType") not in ("wired", "localNetwork") \
            or connection.get("tunnelState") != "connected" \
            or not isinstance(connection.get("tunnelIPAddress"), str) \
            or not connection["tunnelIPAddress"]:
        raise RuntimeError(f"{device} {label} identity differs from the report")
    return path


def _validate_ios_process_proof(
    report: dict[str, object],
    device: str,
    path_value: object,
    hash_value: object,
    process_id: int,
    executable: str,
    label: str,
) -> Path:
    path = _device_capture_repository_file(
        path_value,
        f"{device} {label}",
        allowed_root=REPO_ROOT / "builds/ios-device-evidence" / device,
    )
    contents = path.read_bytes()
    if not _is_sha256(hash_value) \
            or hashlib.sha256(contents).hexdigest() != hash_value:
        raise RuntimeError(f"{device} {label} hash differs")
    payload = _read_device_capture_json_bytes(contents, f"{device} {label}")
    info = payload.get("info")
    result = payload.get("result")
    processes = result.get("runningProcesses") \
        if isinstance(result, dict) else None
    matches = [
        process for process in processes
        if isinstance(process, dict)
        and isinstance(process.get("executable"), str)
        and process["executable"].endswith(
            f"/{IOS_CAPTURE_EXECUTABLE_NAME}.app/"
            f"{IOS_CAPTURE_EXECUTABLE_NAME}"
        )
    ] if isinstance(processes, list) else []
    if not isinstance(info, dict) or info.get("outcome") != "success" \
            or info.get("commandType") \
                != "devicectl.device.info.processes" \
            or not isinstance(result, dict) \
            or result.get("deviceIdentifier") \
                != report.get("coredevice_identifier") \
            or len(matches) != 1 \
            or matches[0].get("processIdentifier") != process_id \
            or matches[0].get("executable") != executable:
        raise RuntimeError(f"{device} {label} game PID proof differs")
    return path


def _ios_installed_capture_executable(
    report: dict[str, object],
    device: str,
) -> str:
    path = _device_capture_repository_file(
        report.get("installed_app_path"),
        f"{device} installed capture app receipt",
        allowed_root=REPO_ROOT / "builds/ios-device-evidence" / device,
    )
    contents = path.read_bytes()
    if not _is_sha256(report.get("installed_app_sha256")) \
            or hashlib.sha256(contents).hexdigest() \
                != report.get("installed_app_sha256"):
        raise RuntimeError(
            f"{device} installed capture app receipt hash differs"
        )
    payload = _read_device_capture_json_bytes(
        contents, f"{device} installed capture app receipt"
    )
    info = payload.get("info")
    result = payload.get("result")
    apps = result.get("apps") if isinstance(result, dict) else None
    bundle_id = report.get("installed_capture_bundle_id")
    matches = [
        app for app in apps
        if isinstance(app, dict) and app.get("bundleIdentifier") == bundle_id
    ] if isinstance(apps, list) else []
    if not isinstance(info, dict) or info.get("outcome") != "success" \
            or info.get("commandType") != "devicectl.device.info.apps" \
            or not isinstance(result, dict) \
            or result.get("deviceIdentifier") \
                != report.get("coredevice_identifier") \
            or result.get("matchingBundleIdentifier") != bundle_id \
            or len(matches) != 1 \
            or not isinstance(matches[0].get("url"), str):
        raise RuntimeError(f"{device} installed capture executable is missing")
    executable = f"{matches[0]['url']}{IOS_CAPTURE_EXECUTABLE_NAME}"
    if not executable.endswith(
        f"/{IOS_CAPTURE_EXECUTABLE_NAME}.app/{IOS_CAPTURE_EXECUTABLE_NAME}"
    ):
        raise RuntimeError(
            f"{device} installed capture executable path is invalid"
        )
    return executable


def _validate_ios_xcode_activation_proof(
    report: dict[str, object],
    device: str,
    capture: dict[str, object],
    handoff_process_id: int,
    executable: str,
    label: str,
) -> None:
    activation_process_id = capture.get("xcode_activation_process_id")
    if activation_process_id != handoff_process_id:
        raise RuntimeError(f"{device} {label} activation PID differs")
    launch_path = _device_capture_repository_file(
        capture.get("xcode_activation_launch_path"),
        f"{device} {label} activation launch receipt",
        allowed_root=REPO_ROOT / "builds/ios-device-evidence" / device,
    )
    launch_bytes = launch_path.read_bytes()
    launch_hash = capture.get("xcode_activation_launch_sha256")
    if not _is_sha256(launch_hash) \
            or hashlib.sha256(launch_bytes).hexdigest() != launch_hash:
        raise RuntimeError(
            f"{device} {label} activation launch receipt hash differs"
        )
    launch = _read_device_capture_json_bytes(
        launch_bytes, f"{device} {label} activation launch receipt"
    )
    info = launch.get("info")
    result = launch.get("result")
    process = result.get("process") if isinstance(result, dict) else None
    options = result.get("launchOptions") if isinstance(result, dict) else None
    receipt_process_id = process.get("processIdentifier") \
        if isinstance(process, dict) else None
    if receipt_process_id is None and isinstance(result, dict):
        receipt_process_id = result.get("processIdentifier")
    if not isinstance(info, dict) or info.get("outcome") != "success" \
            or info.get("commandType") \
                != "devicectl.device.process.launch" \
            or not isinstance(result, dict) \
            or result.get("deviceIdentifier") \
                != report.get("coredevice_identifier") \
            or not isinstance(process, dict) \
            or receipt_process_id != activation_process_id \
            or process.get("executable") != executable \
            or not isinstance(options, dict) \
            or options.get("activatedWhenStarted") is not True \
            or options.get("terminateExistingInstances") is not False \
            or options.get("startStopped") is not False \
            or options.get("arguments") != []:
        raise RuntimeError(
            f"{device} {label} activation launch receipt differs"
        )
    _validate_ios_process_proof(
        report,
        device,
        capture.get("xcode_activation_processes_path"),
        capture.get("xcode_activation_processes_sha256"),
        activation_process_id,
        executable,
        f"{label} activation process",
    )


def _validate_ios_app_listing_identity(
    report: dict[str, object],
    device: str,
    path_field: str,
    hash_field: str,
    identity_field: str,
    label: str,
) -> None:
    path = _device_capture_repository_file(
        report.get(path_field),
        f"{device} {label}",
        allowed_root=REPO_ROOT / "builds/ios-device-evidence" / device,
    )
    contents = path.read_bytes()
    if not _is_sha256(report.get(hash_field)) \
            or hashlib.sha256(contents).hexdigest() != report[hash_field]:
        raise RuntimeError(f"{device} {label} hash differs")
    payload = _read_device_capture_json_bytes(contents, f"{device} {label}")
    info = payload.get("info")
    result = payload.get("result")
    apps = result.get("apps") if isinstance(result, dict) else None
    production_bundle = IOS_PRODUCTION_BUNDLE_ID
    matches = [
        app for app in apps
        if isinstance(app, dict)
        and app.get("bundleIdentifier") == production_bundle
    ] if isinstance(apps, list) else []
    if not isinstance(info, dict) or info.get("outcome") != "success" \
            or info.get("commandType") != "devicectl.device.info.apps" \
            or not isinstance(result, dict) \
            or result.get("deviceIdentifier") \
                != report.get("coredevice_identifier") \
            or result.get("matchingBundleIdentifier") != production_bundle \
            or not isinstance(apps, list) \
            or len(matches) > 1 \
            or len(apps) != len(matches):
        raise RuntimeError(f"{device} {label} CoreDevice result is invalid")
    expected_identity = None if not matches else {
        "bundleIdentifier": matches[0].get("bundleIdentifier"),
        "bundleVersion": matches[0].get("bundleVersion"),
        "version": matches[0].get("version"),
        "url": matches[0].get("url"),
    }
    if report.get(identity_field) != expected_identity:
        raise RuntimeError(f"{device} {label} production app identity differs")


def _validate_ios_capture_persistence(
    report: dict[str, object],
    device: str,
    capture_method: object,
) -> None:
    files = report.get("persistent_data_files")
    if not isinstance(files, list) \
            or files != sorted(files) \
            or len(files) != len(set(files)) \
            or not set(IOS_CAPTURE_PERSISTENT_FILES).issubset(files) \
            or any(
                not isinstance(name, str)
                or re.fullmatch(r"[^/\\\x00]+", name) is None
                or name in (".", "..")
                for name in files
            ):
        raise RuntimeError(f"{device} iOS permanent file list differs from the fixed contract")
    hashes: dict[str, dict[str, object]] = {}
    for field in (
        "persistent_data_sha256_before",
        "persistent_data_sha256_after",
        "persistent_data_sha256_restored",
    ):
        value = report.get(field)
        if not isinstance(value, dict) or list(value) != files \
                or any(
                    digest is not None and not _is_sha256(digest)
                    for digest in value.values()
                ):
            raise RuntimeError(f"{device} iOS {field} hash is invalid")
        hashes[field] = value
    before = hashes["persistent_data_sha256_before"]
    after = hashes["persistent_data_sha256_after"]
    restored = hashes["persistent_data_sha256_restored"]
    if before != after or before != restored \
            or report.get("persistent_data_mutated_during_capture") != [] \
            or report.get("persistent_data_restored_byte_exact") is not True \
            or report.get("persistent_data_unchanged") is not True \
            or report.get("control_files_disarmed") is not True:
        raise RuntimeError(f"{device} iOS permanent data before/after/restored differs")
    settings = report.get("settings_restore")
    if not isinstance(settings, dict) \
            or set(settings) != {
                "original_present",
                "original_sha256",
                "observed_sha256",
                "restored_sha256",
                "byte_exact",
            } \
            or type(settings.get("original_present")) is not bool \
            or settings.get("original_present") \
                is not (before["settings.cfg"] is not None) \
            or settings.get("original_sha256") != before["settings.cfg"] \
            or settings.get("observed_sha256") != after["settings.cfg"] \
            or settings.get("restored_sha256") != restored["settings.cfg"] \
            or settings.get("byte_exact") is not True:
        raise RuntimeError(f"{device} iOS settings.cfg restore proof differs")

    if capture_method not in (
        "xcode-devices-take-screenshot-handoff",
        "pymobiledevice3-dvt-rsd",
    ) \
            or files != sorted(IOS_CAPTURE_PERSISTENT_FILES) \
            or any(value is not None for value in before.values()) \
            or report.get("installed_capture_bundle_id") \
                != IOS_ISOLATED_CAPTURE_BUNDLE_ID \
            or report.get("isolated_capture_bundle") is not True \
            or report.get("production_container_accessed") is not False \
            or report.get("isolated_capture_bundle_removed") is not True \
            or report.get("production_app_identity_unchanged") is not True \
            or report.get("production_app_identity_before") \
                != report.get("production_app_identity_after"):
        raise RuntimeError(f"{device} iOS isolated capture bundle cleanup proof is missing")
    _validate_ios_app_listing_identity(
        report,
        device,
        "production_app_before_path",
        "production_app_before_sha256",
        "production_app_identity_before",
        "production app before",
    )
    _validate_ios_app_listing_identity(
        report,
        device,
        "production_app_after_path",
        "production_app_after_sha256",
        "production_app_identity_after",
        "production app after",
    )


def _validate_device_capture_report(
    entries: list[dict[str, object]],
    device: str,
) -> dict[str, object]:
    contract = DEVICE_CAPTURE_TARGETS[device]
    platform = str(contract["platform"])
    root = DEVICE_CAPTURE_ROOT / platform / device
    _assert_safe_repository_path(root, DEVICE_CAPTURE_ROOT, f"{device} capture root")
    report_path = root / "capture-report.json"
    if not report_path.is_file():
        raise RuntimeError(
            f"{device} device capture-report.json is missing: {report_path}"
        )
    report = _read_device_capture_json(report_path, f"{device} device capture report")
    expected_root = str(root.relative_to(REPO_ROOT))
    if type(report.get("schema")) is not int \
            or report.get("schema") != 2 \
            or report.get("platform") != platform \
            or report.get("target") != device \
            or report.get("canonical_publish_eligible") is not True \
            or report.get("canonical_root") != expected_root \
            or report.get("publication") \
                != "timestamp-staging-then-atomic-directory-rename" \
            or report.get("asset_locales") != list(SCREENSHOT_LOCALES) \
            or report.get("game_locales") \
                != [GAME_LOCALES[locale] for locale in SCREENSHOT_LOCALES] \
            or report.get("foreground_verified_at_capture_end") is not True:
        raise RuntimeError(f"{device} device capture report contract is invalid")
    if platform == "android":
        if report.get("package") != "com.crossplatformkorea.moonlitbeacon" \
                or report.get("api_level") != contract["api_level"] \
                or report.get("avd_name") != contract["avd_name"] \
                or not isinstance(report.get("serial"), str) \
                or re.fullmatch(r"emulator-[0-9]+", str(report["serial"])) is None:
            raise RuntimeError(f"{device} Android device proof is invalid")
        for field in ("model", "device", "build_fingerprint"):
            if not isinstance(report.get(field), str) or not report[field]:
                raise RuntimeError(f"{device} Android {field} proof is missing")
        _validate_android_capture_persistence(
            report,
            device,
            REPO_ROOT / "builds/tablet-evidence" / device,
        )
        _validate_android_tablet_device_proof(report, device, contract)
    else:
        model_identifier = report.get("model_identifier")
        if report.get("bundle_id") \
                != "com.crossplatformkorea.moonlitbeacon" \
                or report.get("physical_device") is not True \
                or report.get("simulator") is not False \
                or not isinstance(model_identifier, str) \
                or not model_identifier.startswith(str(contract["model_prefix"])):
            raise RuntimeError(f"{device} iOS physical-device proof is invalid")
        for field in (
            "device_udid",
            "coredevice_identifier",
            "device_name",
            "os_version",
            "os_build",
            "transport",
        ):
            if not isinstance(report.get(field), str) or not report[field]:
                raise RuntimeError(f"{device} iOS {field} proof is missing")
        _validate_ios_coredevice_details(
            report,
            device,
            report.get("coredevice_device_details_path"),
            report.get("coredevice_device_details_sha256"),
            "CoreDevice device details",
        )
        capture_method = report.get("capture_method")
        expected_rsd_identity = {
            "physical_device": True,
            "simulator": False,
            "model_identifier": model_identifier,
            "os_version": report.get("os_version"),
            "os_build": report.get("os_build"),
        }
        if capture_method == "pymobiledevice3-dvt-rsd":
            rsd_identity = report.get("rsd_identity")
            rsd_info_hash = report.get("rsd_info_raw_sha256")
            rsd_preflight_size = report.get("rsd_preflight_size")
            if rsd_identity != expected_rsd_identity \
                    or not _is_sha256(rsd_info_hash) \
                    or not isinstance(report.get("pymobiledevice3_version"), str) \
                    or not report["pymobiledevice3_version"] \
                    or not isinstance(report.get("rsd_host"), str) \
                    or not report["rsd_host"] \
                    or type(report.get("rsd_port")) is not int \
                    or not 0 < report["rsd_port"] <= 65_535 \
                    or report.get("rsd_endpoint_ephemeral") is not True \
                    or report.get("rsd_preflight_path") is not None \
                    or report.get("rsd_preflight_image_retained") is not False \
                    or not _is_sha256(report.get("rsd_preflight_sha256")) \
                    or not isinstance(rsd_preflight_size, dict) \
                    or type(rsd_preflight_size.get("width")) is not int \
                    or type(rsd_preflight_size.get("height")) is not int \
                    or rsd_preflight_size["width"] \
                        <= rsd_preflight_size["height"] \
                    or report.get("xcode_screenshot_handoff") is not None:
                raise RuntimeError(
                    f"{device} iOS RSD physical-device proof is invalid"
                )
            rsd_proof_path = _device_capture_repository_file(
                report.get("rsd_identity_proof_path"),
                f"{device} RSD identity proof",
                allowed_root=REPO_ROOT / "builds/ios-device-evidence" / device,
            )
            rsd_proof = _read_device_capture_json(
                rsd_proof_path, f"{device} RSD identity proof"
            )
            if rsd_proof != {
                "schema": 1,
                "coredevice_identity_matched": True,
                "identity": expected_rsd_identity,
                "raw_json_sha256": rsd_info_hash,
            }:
                raise RuntimeError(
                    f"{device} RSD identity proof differs from the report"
                )
        elif capture_method == "xcode-devices-take-screenshot-handoff":
            expected_handoff = {
                "schema": 2,
                "first_party_tool": "Xcode Devices and Simulators",
                "capture_method": capture_method,
                "operator_mediated": True,
                "inbox_path_persisted": False,
                "atomic_rename_required": True,
                "publisher_script": (
                    "scripts/publish-xcode-screenshot-handoff.mjs"
                ),
                "complete_png_decode_required": True,
                "stable_observations_required": 2,
                "fsync_receipt_required": True,
                "request_timeout_seconds": 300,
                "expected_framebuffer": {"width": 2266, "height": 1488},
            }
            if device != "ipad-13" \
                    or report.get("xcode_screenshot_handoff") != expected_handoff \
                    or report.get("pymobiledevice3_version") is not None \
                    or report.get("rsd_host") is not None \
                    or report.get("rsd_port") is not None \
                    or report.get("rsd_endpoint_ephemeral") is not False \
                    or report.get("rsd_preflight_path") is not None \
                    or report.get("rsd_preflight_image_retained") is not False \
                    or report.get("rsd_preflight_sha256") is not None \
                    or report.get("rsd_preflight_size") is not None \
                    or report.get("rsd_identity") is not None \
                    or report.get("rsd_info_raw_sha256") is not None \
                    or report.get("rsd_identity_proof_path") is not None:
                raise RuntimeError(
                    f"{device} iOS Xcode handoff proof is invalid"
                )
        else:
            raise RuntimeError(f"{device} iOS capture method is invalid")
        _validate_ios_capture_persistence(report, device, capture_method)

    artifact_hash = _validate_device_capture_build(report, platform, device)
    ios_capture_executable = _ios_installed_capture_executable(report, device) \
        if platform == "ios" else None
    captures = report.get("captures")
    if not isinstance(captures, list):
        raise RuntimeError(f"{device} device capture list is missing")
    expected: dict[str, tuple[str, str, str]] = {}
    for locale in SCREENSHOT_LOCALES:
        for entry in entries:
            filename = str(entry["output"])
            capture_kind = DEVICE_CAPTURE_SCREENSHOT_KINDS.get(filename)
            if capture_kind is None:
                raise RuntimeError(f"device capture state contract is missing: {filename}")
            source_path = root / locale / filename
            expected[str(source_path.relative_to(REPO_ROOT))] = (
                locale,
                GAME_LOCALES[locale],
                capture_kind,
            )
    actual: dict[str, dict[str, object]] = {}
    for capture in captures:
        if not isinstance(capture, dict) or not isinstance(capture.get("source"), str):
            raise RuntimeError(f"{device} device capture entry is invalid")
        source = str(capture["source"])
        if source in actual:
            raise RuntimeError(f"{device} device capture source is duplicated: {source}")
        actual[source] = capture
    if set(actual) != set(expected):
        raise RuntimeError(
            f"{device} device capture list differs from the exact device/locale paths"
        )

    hashes: dict[str, str] = {}
    xcode_handoff_nonces: set[str] = set()
    xcode_handoff_requested_ats: set[int | float] = set()
    last_xcode_handoff_process_id: int | None = None
    last_xcode_handoff_requested_at: int | float | None = None
    screenshot_size: tuple[int, int] | None = None
    for source, (locale, game_locale, capture_kind) in expected.items():
        capture = actual[source]
        path = _device_capture_repository_file(
            source,
            f"{device} canonical PNG",
            allowed_root=root,
        )
        width, height = _png_size(path)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if platform == "android" \
                and (width, height) != tuple(contract["source_size"]):
            raise RuntimeError(
                f"{source} differs from {device} physical screen size"
            )
        if width <= height \
                or capture.get("asset_locale") != locale \
                or capture.get("game_locale") != game_locale \
                or capture.get("filename") != path.name \
                or capture.get("kind") != capture_kind \
                or capture.get("width") != width \
                or capture.get("height") != height \
                or capture.get("sha256") != digest:
            raise RuntimeError(
                f"{source} device/locale/state/PNG hash proof is invalid"
            )
        if platform == "android":
            if capture.get("installed_apk_sha256") != artifact_hash:
                raise RuntimeError(f"{source} installed APK changed during capture")
        elif capture.get("installed_artifact_sha256") != artifact_hash \
                or capture.get("installed_identity_sha256") \
                    != report.get("installed_identity_sha256"):
            raise RuntimeError(
                f"{source} installed iOS build/identity changed during capture"
            )
        if platform == "ios":
            if capture.get("native_device_framebuffer") is not True \
                    or capture.get("capture_method") != capture_method:
                raise RuntimeError(f"{source} iOS native capture method differs")
            if capture_method == "pymobiledevice3-dvt-rsd":
                if capture.get("rsd_host") != report.get("rsd_host") \
                        or capture.get("rsd_port") != report.get("rsd_port") \
                        or capture.get("xcode_handoff_nonce") is not None \
                        or capture.get("xcode_handoff_expected_filename") \
                            is not None \
                        or capture.get("xcode_handoff_requested_at") is not None \
                        or capture.get("xcode_handoff_requested_at_unix_ms") \
                            is not None \
                        or capture.get("xcode_handoff_birthtime_unix_ms") \
                            is not None \
                        or capture.get("xcode_handoff_mtime_unix_ms") is not None \
                        or capture.get("xcode_handoff_accepted_at") is not None \
                        or capture.get("xcode_handoff_stable_observations") \
                            is not None \
                        or capture.get("xcode_handoff_complete_png_decoded") \
                            is not None \
                        or capture.get("xcode_handoff_receipt") is not None \
                        or capture.get("xcode_handoff_receipt_sha256") is not None \
                        or capture.get("xcode_activation_process_id") is not None \
                        or capture.get("xcode_activation_launch_path") is not None \
                        or capture.get("xcode_activation_launch_sha256") \
                            is not None \
                        or capture.get("xcode_activation_processes_path") \
                            is not None \
                        or capture.get("xcode_activation_processes_sha256") \
                            is not None \
                        or capture.get("xcode_handoff_process_id") is not None \
                        or capture.get("xcode_handoff_device_details_before_path") \
                            is not None \
                        or capture.get("xcode_handoff_device_details_before_sha256") \
                            is not None \
                        or capture.get("xcode_handoff_processes_before_path") \
                            is not None \
                        or capture.get("xcode_handoff_processes_before_sha256") \
                            is not None \
                        or capture.get("xcode_handoff_device_details_after_path") \
                            is not None \
                        or capture.get("xcode_handoff_device_details_after_sha256") \
                            is not None \
                        or capture.get("xcode_handoff_processes_after_path") \
                            is not None \
                        or capture.get("xcode_handoff_processes_after_sha256") \
                            is not None:
                    raise RuntimeError(f"{source} iOS RSD capture proof differs")
            else:
                nonce = capture.get("xcode_handoff_nonce")
                requested = capture.get("xcode_handoff_requested_at_unix_ms")
                birthtime = capture.get("xcode_handoff_birthtime_unix_ms")
                mtime = capture.get("xcode_handoff_mtime_unix_ms")
                process_id = capture.get("xcode_handoff_process_id")
                if (width, height) != (2266, 1488) \
                        or capture.get("rsd_host") is not None \
                        or capture.get("rsd_port") is not None \
                        or not isinstance(nonce, str) \
                        or re.fullmatch(r"[0-9a-f]{64}", nonce) is None \
                        or nonce in xcode_handoff_nonces \
                        or capture.get("xcode_handoff_expected_filename") \
                            != f"moonlit-{nonce}.png" \
                        or not isinstance(
                            capture.get("xcode_handoff_requested_at"), str
                        ) \
                        or not isinstance(
                            capture.get("xcode_handoff_accepted_at"), str
                        ) \
                        or type(requested) not in (int, float) \
                        or type(birthtime) not in (int, float) \
                        or type(mtime) not in (int, float) \
                        or birthtime <= requested \
                        or mtime <= requested \
                        or type(process_id) is not int \
                        or process_id <= 0:
                    raise RuntimeError(
                        f"{source} iOS Xcode handoff capture proof differs"
                    )
                receipt = capture.get("xcode_handoff_receipt")
                expected_receipt_keys = {
                    "schema",
                    "protocol",
                    "nonce",
                    "expected_filename",
                    "partial_filename",
                    "png_sha256",
                    "png_size",
                    "source_birthtime_ms",
                    "source_mtime_ms",
                    "final_dev",
                    "final_ino",
                    "final_birthtime_ms",
                    "final_mtime_ms",
                    "file_fsync_before_rename",
                    "directory_fsync_after_rename",
                    "published_at_ms",
                }
                receipt_bytes = (
                    json.dumps(
                        receipt,
                        ensure_ascii=False,
                        separators=(",", ":"),
                        sort_keys=True,
                    ) + "\n"
                ).encode("utf-8") if isinstance(receipt, dict) else b""
                if not isinstance(receipt, dict) \
                        or set(receipt) != expected_receipt_keys \
                        or receipt.get("schema") != 1 \
                        or receipt.get("protocol") \
                            != "moonlit-xcode-screenshot-handoff-v1" \
                        or receipt.get("nonce") != nonce \
                        or receipt.get("expected_filename") \
                            != f"moonlit-{nonce}.png" \
                        or receipt.get("partial_filename") \
                            != f".moonlit-{nonce}.png.partial-{nonce}" \
                        or receipt.get("png_sha256") != digest \
                        or receipt.get("png_size") != len(path.read_bytes()) \
                        or type(receipt.get("source_birthtime_ms")) \
                            not in (int, float) \
                        or type(receipt.get("source_mtime_ms")) \
                            not in (int, float) \
                        or receipt["source_birthtime_ms"] < requested \
                        or receipt["source_mtime_ms"] < requested \
                        or re.fullmatch(
                            r"[0-9]+", str(receipt.get("final_dev"))
                        ) is None \
                        or re.fullmatch(
                            r"[0-9]+", str(receipt.get("final_ino"))
                        ) is None \
                        or receipt.get("final_birthtime_ms") != birthtime \
                        or receipt.get("final_mtime_ms") != mtime \
                        or receipt.get("file_fsync_before_rename") is not True \
                        or receipt.get("directory_fsync_after_rename") \
                            is not True \
                        or type(receipt.get("published_at_ms")) \
                            not in (int, float) \
                        or receipt["published_at_ms"] < requested \
                        or capture.get("xcode_handoff_stable_observations") \
                            != 2 \
                        or capture.get("xcode_handoff_complete_png_decoded") \
                            is not True \
                        or not _is_sha256(
                            capture.get("xcode_handoff_receipt_sha256")
                        ) \
                        or hashlib.sha256(receipt_bytes).hexdigest() \
                            != capture.get("xcode_handoff_receipt_sha256"):
                    raise RuntimeError(
                        f"{source} iOS Xcode atomic handoff receipt differs"
                    )
                if requested in xcode_handoff_requested_ats:
                    raise RuntimeError(
                        f"{device} Xcode handoff request timestamp is duplicated"
                    )
                xcode_handoff_requested_ats.add(requested)
                xcode_handoff_nonces.add(nonce)
                if ios_capture_executable is None:
                    raise RuntimeError(
                        f"{source} installed capture executable is missing"
                    )
                _validate_ios_xcode_activation_proof(
                    report,
                    device,
                    capture,
                    process_id,
                    ios_capture_executable,
                    f"{source} Xcode handoff",
                )
                for moment, label in (("before", "before"), ("after", "after")):
                    _validate_ios_coredevice_details(
                        report,
                        device,
                        capture.get(
                            f"xcode_handoff_device_details_{moment}_path"
                        ),
                        capture.get(
                            f"xcode_handoff_device_details_{moment}_sha256"
                        ),
                        f"Xcode handoff {label} CoreDevice details",
                    )
                    _validate_ios_process_proof(
                        report,
                        device,
                        capture.get(f"xcode_handoff_processes_{moment}_path"),
                        capture.get(
                            f"xcode_handoff_processes_{moment}_sha256"
                        ),
                        process_id,
                        ios_capture_executable,
                        f"Xcode handoff {label} process",
                    )
                if last_xcode_handoff_requested_at is None \
                        or requested > last_xcode_handoff_requested_at:
                    last_xcode_handoff_requested_at = requested
                    last_xcode_handoff_process_id = process_id
        expected_clean_ui = "title-hidden" \
            if capture_kind in ("title", "shrine", "hero_preview") \
            else "combat-hidden"
        if capture.get("clean_ui_proof") != expected_clean_ui:
            raise RuntimeError(f"{source} clean UI proof is invalid")
        evidence_path = _device_capture_repository_file(
            capture.get("evidence_path"),
            f"{source} timestamp source",
        )
        evidence_relative = evidence_path.relative_to(REPO_ROOT).as_posix()
        if evidence_relative.startswith("builds/shots/store-localized/") \
                or evidence_relative.startswith("builds/shots/store-platform/") \
                or hashlib.sha256(evidence_path.read_bytes()).hexdigest() != digest:
            raise RuntimeError(
                f"{source} does not match the independent timestamp device source"
            )
        expected_direct_distribution = platform == "android"
        _validate_device_capture_runtime_proof(
            capture,
            source,
            game_locale,
            capture_kind,
            expected_direct_distribution,
        )
        runtime_before = capture["runtime_before"]
        if not isinstance(runtime_before, dict):
            raise RuntimeError(f"{source} runtime proof is missing")
        _validate_device_capture_safe_proof(
            capture,
            runtime_before,
            "arena_ready" if capture_kind == "missile_core_recovery"
            else capture_kind,
            width,
            height,
            source,
            expected_direct_distribution,
        )
        if screenshot_size is None:
            screenshot_size = (width, height)
        elif screenshot_size != (width, height):
            raise RuntimeError(f"{device} device capture resolution differs across scenes")
        if digest in hashes:
            raise RuntimeError(
                f"{device} reused the same PNG across scene/locale: "
                f"{source}, {hashes[digest]}"
            )
        hashes[digest] = source
    if platform == "ios":
        final_process_id = report.get("final_process_id")
        if type(final_process_id) is not int or final_process_id <= 0 \
                or ios_capture_executable is None \
                or report.get("final_process_executable") \
                    != ios_capture_executable:
            raise RuntimeError(f"{device} final iOS capture PID is invalid")
        _validate_ios_process_proof(
            report,
            device,
            report.get("final_processes_path"),
            report.get("final_processes_sha256"),
            final_process_id,
            ios_capture_executable,
            "final capture process",
        )
        if capture_method == "xcode-devices-take-screenshot-handoff" \
                and final_process_id != last_xcode_handoff_process_id:
            raise RuntimeError(
                f"{device} final PID differs from the last Xcode capture PID"
            )
    if screenshot_size is None \
            or report.get("screenshot_size") \
                != f"{screenshot_size[0]}x{screenshot_size[1]}":
        raise RuntimeError(f"{device} report actual PNG resolution proof differs")
    report_bytes = report_path.read_bytes()
    try:
        stable_report = json.loads(report_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(
            f"{device} device capture report was corrupted during validation"
        ) from error
    if stable_report != report:
        raise RuntimeError(f"{device} device capture report changed during validation")
    return {
        "hashes": hashes,
        "report": report,
        "report_path": report_path,
        "report_sha256": hashlib.sha256(report_bytes).hexdigest(),
    }


def _validate_device_capture_reports_for_targets(
    entries: list[dict[str, object]],
    devices: Iterable[str],
) -> dict[str, dict[str, object]]:
    selected_devices = tuple(devices)
    if not selected_devices \
            or len(selected_devices) != len(set(selected_devices)) \
            or any(device not in DEVICE_CAPTURE_TARGETS
                   for device in selected_devices):
        raise RuntimeError("device capture validation target device list is invalid")
    phone_hashes: dict[str, str] = {}
    for entry in entries:
        localized_sources = entry.get("localized_sources")
        if not isinstance(localized_sources, dict):
            raise RuntimeError(f"{entry.get('output')} is missing a phone source contract")
        for locale in SCREENSHOT_LOCALES:
            phone_path = _device_capture_repository_file(
                localized_sources.get(locale),
                f"{locale} Pixel phone source",
                allowed_root=REPO_ROOT / "builds/shots",
            )
            phone_hashes[
                hashlib.sha256(phone_path.read_bytes()).hexdigest()
            ] = str(phone_path.relative_to(REPO_ROOT))

    device_hashes: dict[str, str] = {}
    validated: dict[str, dict[str, object]] = {}
    for device in selected_devices:
        context = _validate_device_capture_report(entries, device)
        hashes = context.get("hashes")
        if not isinstance(hashes, dict):
            raise RuntimeError(f"{device} device capture hash result is invalid")
        for digest, source in hashes.items():
            if digest in phone_hashes:
                raise RuntimeError(
                    f"{source} reused Pixel phone source {phone_hashes[digest]} "
                    "again"
                )
            if digest in device_hashes:
                raise RuntimeError(
                    f"canonical PNG reused across different devices: "
                    f"{source}, {device_hashes[digest]}"
                )
            device_hashes[digest] = source
        validated[device] = context
    return validated


def _validate_play_device_capture_reports(
    entries: list[dict[str, object]],
) -> None:
    expected_devices = ("seven-inch-tablet", "ten-inch-tablet")
    if tuple(PLAY_TABLET_FORMATS) != expected_devices \
            or any(
                DEVICE_CAPTURE_TARGETS[device].get("platform") != "android"
                for device in expected_devices
            ):
        raise RuntimeError("Play-only validation targets must be Android 7-inch and 10-inch")
    _validate_device_capture_reports_for_targets(
        entries,
        expected_devices,
    )


def _validate_device_capture_reports(
    entries: list[dict[str, object]],
) -> None:
    _validate_device_capture_reports_for_targets(
        entries,
        DEVICE_CAPTURE_TARGETS,
    )


def _fit_dimensions(
    source_width: int,
    source_height: int,
    maximum_width: int,
    maximum_height: int,
) -> tuple[int, int]:
    scaled_width = maximum_width
    scaled_height = round(source_height * maximum_width / source_width)
    if scaled_height > maximum_height:
        scaled_width = round(source_width * maximum_height / source_height)
        scaled_height = maximum_height
    scaled_width = max(scaled_width - scaled_width % 2, 2)
    scaled_height = max(scaled_height - scaled_height % 2, 2)
    return scaled_width, scaled_height


def _entry_source(
    entry: dict[str, object],
    locale: str,
    device: str | None = None,
) -> Path:
    if device is not None:
        if device in PLAY_TABLET_FORMATS:
            platform = "android"
        elif device in APP_STORE_FORMATS:
            platform = "ios"
        else:
            raise RuntimeError(f"unsupported device capture device: {device}")
        # Default contract is a canonical source shot directly on each tablet/iPad/iPhone
        # target. The Android-origin iPhone marketing exception does not spoof this helper;
        # it is selected only via an explicit mode in ``_app_store_entry_source``.
        return (
            DEVICE_CAPTURE_ROOT
            / platform
            / device
            / locale
            / str(entry["output"])
        )
    localized_sources = entry.get("localized_sources", {})
    if not isinstance(localized_sources, dict) or locale not in localized_sources:
        raise RuntimeError(
            f"{entry.get('output')} is missing a {locale} real UI source"
        )
    source = localized_sources[locale]
    return REPO_ROOT / str(source)


def _app_store_entry_source(
    entry: dict[str, object],
    locale: str,
    device: str,
    iphone_source_mode: str,
) -> Path:
    if iphone_source_mode not in APP_STORE_IPHONE_SOURCE_MODES:
        raise RuntimeError(
            f"unsupported App Store iPhone source mode: "
            f"{iphone_source_mode}"
        )
    if device == "iphone-6.5" \
            and iphone_source_mode == APP_STORE_IPHONE_SOURCE_ANDROID_AVD:
        # App Store submission slot is iPhone 6.5-inch, but the capture origin is the Android
        # Pixel_10 AVD. Do not copy into an iOS canonical path or describe it as a native
        # capture; return the real Android source path as-is.
        return _entry_source(entry, locale)
    return _entry_source(entry, locale, device)


def _run_screenshot_render(
    ffmpeg: str,
    source: Path,
    output: Path,
    filter_graph: str,
) -> None:
    _assert_safe_repository_path(output, RELEASE_OUTPUT_ROOT, "store screenshot output")
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        (
            ffmpeg,
            "-y",
            "-loglevel",
            "error",
            "-i",
            str(source),
            "-vf",
            filter_graph,
            "-frames:v",
            "1",
            "-compression_level",
            "9",
            str(output),
        ),
        check=True,
    )


def _run_screenshot_composite(
    ffmpeg: str,
    sources: tuple[Path, ...],
    output: Path,
    filter_graph: str,
) -> None:
    _assert_safe_repository_path(output, RELEASE_OUTPUT_ROOT, "store screenshot output")
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        ffmpeg,
        "-y",
        "-loglevel",
        "error",
    ]
    for source in sources:
        command.extend(("-i", str(source)))
    command.extend(
        (
            "-filter_complex",
            filter_graph,
            "-map",
            "[out]",
            "-frames:v",
            "1",
            "-compression_level",
            "9",
            str(output),
        )
    )
    subprocess.run(command, check=True)


def _render_marketing_text(
    hb_view: str,
    font: Path,
    text: str,
    locale: str,
    font_size: int,
    color: str,
    output: Path,
) -> tuple[int, int]:
    language = MARKETING_TEXT_LANGUAGES[locale]
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        (
            hb_view,
            f"--output-file={output}",
            "--output-format=png",
            "--background=none",
            f"--foreground={color}ff",
            f"--font-size={font_size}",
            "--margin=0",
            "--ink",
            f"--language={language}",
            str(font),
            text,
        ),
        check=True,
    )
    if not output.is_file():
        raise RuntimeError(
            f"failed to create marketing text PNG: {output}"
        )
    canvas = _read_png_rgba(output)
    alpha_levels = set(canvas.pixels[3::4])
    if not alpha_levels or alpha_levels == {0} or alpha_levels == {255}:
        raise RuntimeError(
            f"marketing text must be an RGBA PNG with a transparent background: {output}"
        )
    return canvas.width, canvas.height


def _render_play_screenshot(
    ffmpeg: str,
    hb_view: str,
    font: Path,
    entry: dict[str, object],
    index: int,
    locale: str,
    temporary_path: Path,
    output_root: Path | None = None,
) -> Path:
    source = _entry_source(entry, locale)
    if not source.is_file():
        raise RuntimeError(f"device capture is missing: {source}")
    width, height = _png_size(source)
    crop_bottom = int(entry.get("crop_bottom", 0))
    if crop_bottom >= height:
        raise RuntimeError(f"invalid crop_bottom: {source} ({crop_bottom})")
    crop_height = height - crop_bottom
    scaled_width, scaled_height = _fit_dimensions(width, crop_height, 1920, 1080)
    offset_x = (1920 - scaled_width) // 2
    offset_y = (1080 - scaled_height) // 2

    labels = entry["labels"]
    if not isinstance(labels, dict):
        raise RuntimeError(f"invalid screenshot label: {entry['output']}")
    label_path = temporary_path / f"play-{locale}-label-{index}.png"
    _, label_height = _render_marketing_text(
        hb_view,
        font,
        str(labels[locale]),
        locale,
        36,
        "d6f3ff",
        label_path,
    )
    output = (
        (output_root or PLAY_SCREENSHOT_OUTPUT)
        / PLAY_LOCALES[locale]
        / "screenshots"
        / str(entry["output"])
    )
    brand_path = temporary_path / f"play-{locale}-brand-{index}.png"
    _, brand_height = _render_marketing_text(
        hb_view,
        font,
        BRAND_LABELS[locale],
        locale,
        24,
        "758bb6",
        brand_path,
    )
    label_y = max((offset_y - label_height) // 2, 6)
    brand_y = min(
        offset_y + scaled_height + 28,
        1080 - brand_height - 10,
    )
    filter_graph = (
        f"[0:v]crop={width}:{crop_height}:0:0,"
        f"scale={scaled_width}:{scaled_height}:flags=lanczos,"
        f"pad=1920:1080:{offset_x}:{offset_y}:color=0x0b0e1c,"
        f"drawbox=x={offset_x}:y={offset_y}:w={scaled_width}:h={scaled_height}:"
        "color=0xf5c84b@0.85:t=4[base];"
        f"[base][1:v]overlay=x=(W-w)/2:y={label_y}[labeled];"
        f"[labeled][2:v]overlay=x=(W-w)/2:y={brand_y},"
        "format=rgb24[out]"
    )
    _run_screenshot_composite(
        ffmpeg,
        (source, label_path, brand_path),
        output,
        filter_graph,
    )
    _validate_screenshot_file(
        f"Play {PLAY_LOCALES[locale]}", output, (1920, 1080))
    return output


def _render_play_tablet_screenshot(
    ffmpeg: str,
    _hb_view: str,
    _font: Path,
    entry: dict[str, object],
    _index: int,
    locale: str,
    device: str,
    spec: dict[str, object],
    _temporary_path: Path,
    output_root: Path | None = None,
) -> Path:
    """Place the full real Android UI on a 16:9 canvas with no distortion or crop."""
    source = _entry_source(entry, locale, device)
    if not source.is_file():
        raise RuntimeError(f"device capture is missing: {source}")
    source_width, source_height = _png_size(source)
    target_width, target_height = spec["size"]
    scaled_width, scaled_height = _fit_dimensions(
        source_width,
        source_height,
        target_width,
        target_height,
    )
    offset_x = (target_width - scaled_width) // 2
    offset_y = (target_height - scaled_height) // 2

    play_locale = PLAY_LOCALES[locale]
    output = (
        (output_root or PLAY_SCREENSHOT_OUTPUT)
        / play_locale
        / device
        / str(entry["output"])
    )
    # Play large-screen spec is landscape 16:9. Keep the full real Android capture centered
    # at its native aspect ratio, and fill empty regions only with a neutral dark extension
    # of the same Android source. No iPad output, crop, device frame, or marketing copy.
    filter_graph = (
        "split=2[background][foreground];"
        f"[background]scale={target_width}:{target_height}:"
        "force_original_aspect_ratio=increase:flags=lanczos,"
        f"crop={target_width}:{target_height},"
        "gblur=sigma=32:steps=3,"
        "eq=brightness=-0.04:saturation=0.22:contrast=0.72[backdrop];"
        f"[foreground]scale={scaled_width}:{scaled_height}:flags=lanczos[game];"
        f"[backdrop][game]overlay={offset_x}:{offset_y},format=rgb24"
    )
    _run_screenshot_render(
        ffmpeg,
        source,
        output,
        filter_graph,
    )
    _validate_screenshot_file(
        f"Play {play_locale} {device}", output, spec["size"])
    return output


def _app_store_transform(
    source_width: int,
    source_height: int,
    spec: dict[str, object],
) -> dict[str, object]:
    target_width, target_height = spec["size"]
    header = int(spec["header"])
    footer = int(spec["footer"])
    margin = int(spec["margin"])
    available_width = target_width - margin * 2
    available_height = target_height - header - footer - margin * 2
    scaled_width, scaled_height = _fit_dimensions(
        source_width,
        source_height,
        available_width,
        available_height,
    )
    return {
        "kind": "marketing-composite",
        "crop_bottom": 0,
        "stretch": False,
        "target_width": target_width,
        "target_height": target_height,
        "scaled_width": scaled_width,
        "scaled_height": scaled_height,
        "offset_x": (target_width - scaled_width) // 2,
        "offset_y": (
            header + margin + (available_height - scaled_height) // 2
        ),
        "header": header,
        "footer": footer,
        "margin": margin,
    }


def _render_app_store_screenshot(
    ffmpeg: str,
    hb_view: str,
    font: Path,
    entry: dict[str, object],
    index: int,
    locale: str,
    device: str,
    spec: dict[str, object],
    temporary_path: Path,
    output_root: Path | None = None,
    iphone_source_mode: str = APP_STORE_IPHONE_SOURCE_PHYSICAL,
) -> Path:
    source = _app_store_entry_source(
        entry, locale, device, iphone_source_mode
    )
    if not source.is_file():
        raise RuntimeError(f"device capture is missing: {source}")
    source_width, source_height = _png_size(source)
    # App Store marketing composite keeps the full source screen. Both physical iOS and the
    # explicit Android Pixel_10 AVD exception preserve aspect ratio with no crop.
    transform = _app_store_transform(source_width, source_height, spec)
    crop_bottom = int(transform["crop_bottom"])
    if crop_bottom >= source_height:
        raise RuntimeError(f"invalid crop_bottom: {source} ({crop_bottom})")
    crop_height = source_height - crop_bottom

    target_width = int(transform["target_width"])
    target_height = int(transform["target_height"])
    header = int(transform["header"])
    footer = int(transform["footer"])
    margin = int(spec["margin"])
    scaled_width = int(transform["scaled_width"])
    scaled_height = int(transform["scaled_height"])
    offset_x = int(transform["offset_x"])
    offset_y = int(transform["offset_y"])

    labels = entry["labels"]
    if not isinstance(labels, dict):
        raise RuntimeError(f"invalid screenshot label: {entry['output']}")
    app_store_locale = APP_STORE_LOCALES[locale]
    output = (
        (output_root or APP_STORE_SCREENSHOT_OUTPUT)
        / app_store_locale
        / device
        / str(entry["output"])
    )
    font_size = int(spec["font_size"])
    brand_size = int(spec["brand_size"])
    border = int(spec["border"])
    label_path = temporary_path / f"apple-{locale}-{device}-{index}-label.png"
    _, label_height = _render_marketing_text(
        hb_view,
        font,
        str(labels[locale]),
        locale,
        font_size,
        "d6f3ff",
        label_path,
    )
    brand_path = temporary_path / f"apple-{locale}-{device}-{index}-brand.png"
    _, brand_height = _render_marketing_text(
        hb_view,
        font,
        BRAND_LABELS[locale],
        locale,
        brand_size,
        "758bb6",
        brand_path,
    )
    label_y = (header - label_height) // 2
    brand_y = target_height - footer + (footer - brand_height) // 2
    decoration = (
        f"drawbox=x=0:y=0:w={target_width}:h={header}:color=0x121932@1:t=fill,"
        f"drawbox=x=0:y={target_height - footer}:w={target_width}:h={footer}:"
        "color=0x121932@1:t=fill,"
        f"drawbox=x={offset_x}:y={offset_y}:w={scaled_width}:h={scaled_height}:"
        f"color=0xf5c84b@0.9:t={border},"
        f"drawbox=x={margin // 2}:y={margin // 2}:"
        f"w={target_width - margin}:h={target_height - margin}:"
        f"color=0x758bb6@0.7:t={max(border // 2, 2)}"
    )
    if device == "ipad-13":
        # iPad is much squarer than the game's 808:360 landscape screen. Without cropping or
        # stretching the full UI, reuse the same device capture as a darkened blurred backdrop
        # to fill the large vertical margins as a marketing frame. The sharp front screen is the only UI.
        filter_graph = (
            f"[0:v]crop={source_width}:{crop_height}:0:0,"
            "split=2[background][foreground];"
            f"[background]scale={target_width}:{target_height}:"
            "force_original_aspect_ratio=increase:flags=lanczos,"
            f"crop={target_width}:{target_height},"
            "gblur=sigma=32:steps=3,eq=brightness=-0.18:saturation=0.65[backdrop];"
            f"[foreground]scale={scaled_width}:{scaled_height}:flags=lanczos[game];"
            f"[backdrop][game]overlay={offset_x}:{offset_y},"
            + decoration
            + "[base];"
            f"[base][1:v]overlay=x=(W-w)/2:y={label_y}[labeled];"
            f"[labeled][2:v]overlay=x=(W-w)/2:y={brand_y},"
            "format=rgb24[out]"
        )
    else:
        filter_graph = (
            f"[0:v]crop={source_width}:{crop_height}:0:0,"
            f"scale={scaled_width}:{scaled_height}:flags=lanczos,"
            f"pad={target_width}:{target_height}:{offset_x}:{offset_y}:color=0x0b0e1c,"
            + decoration
            + "[base];"
            f"[base][1:v]overlay=x=(W-w)/2:y={label_y}[labeled];"
            f"[labeled][2:v]overlay=x=(W-w)/2:y={brand_y},"
            "format=rgb24[out]"
        )
    _run_screenshot_composite(
        ffmpeg,
        (source, label_path, brand_path),
        output,
        filter_graph,
    )
    _validate_screenshot_file(
        f"App Store {app_store_locale} {device}", output, spec["size"])
    return output


def _render_iap_review_screenshot(
    ffmpeg: str,
    review: dict[str, object],
    output_root: Path | None = None,
) -> Path:
    source = IAP_REVIEW_SOURCE_ROOT / str(review["output"])
    output = (output_root or IAP_REVIEW_OUTPUT_ROOT) / str(review["output"])
    if not source.is_file():
        raise RuntimeError(f"IAP review device capture is missing: {source}")
    source_width, source_height = _png_size(source)
    target_size = (2778, 1284)
    scaled_width, scaled_height = _fit_dimensions(
        source_width,
        source_height,
        target_size[0],
        target_size[1],
    )
    offset_x = (target_size[0] - scaled_width) // 2
    offset_y = (target_size[1] - scaled_height) // 2
    filter_graph = (
        f"scale={scaled_width}:{scaled_height}:flags=lanczos,"
        f"pad={target_size[0]}:{target_size[1]}:{offset_x}:{offset_y}:color=0x0b0e1c,"
        f"drawbox=x={offset_x}:y={offset_y}:w={scaled_width}:h={scaled_height}:"
        "color=0xf5c84b@0.85:t=4,"
        "format=rgb24"
    )
    _run_screenshot_render(
        ffmpeg,
        source,
        output,
        filter_graph,
    )
    _validate_screenshot_file(
        f"App Store IAP review {review['product_id']}",
        output,
        target_size,
    )
    return output


def _assert_no_stale_iap_review_source() -> None:
    _assert_safe_repository_path(
        STALE_IAP_REVIEW_SOURCE,
        REPO_ROOT / "builds/shots",
        "legacy shared IAP review source",
    )
    if STALE_IAP_REVIEW_SOURCE.exists():
        raise RuntimeError(
            "legacy shared IAP review source ko-KR/iap-review.png remains "
            "and would confuse per-product sources. "
            "Run pnpm store:screenshots to clean the dedicated stale file"
        )


def _remove_stale_iap_review_source() -> None:
    _assert_safe_repository_path(
        STALE_IAP_REVIEW_SOURCE,
        REPO_ROOT / "builds/shots",
        "legacy shared IAP review source cleanup path",
    )
    if not STALE_IAP_REVIEW_SOURCE.exists():
        return
    if not STALE_IAP_REVIEW_SOURCE.is_file():
        raise RuntimeError(
            "legacy shared IAP review source path is not a regular file: "
            f"{STALE_IAP_REVIEW_SOURCE}"
        )
    STALE_IAP_REVIEW_SOURCE.unlink()


def _remove_stale_screenshots(output_directory: Path, expected_names: set[str]) -> None:
    _assert_safe_repository_path(
        output_directory,
        RELEASE_OUTPUT_ROOT,
        "store screenshot cleanup path",
    )
    output_directory.mkdir(parents=True, exist_ok=True)
    for stale in output_directory.glob("*.png"):
        if stale.name not in expected_names:
            stale.unlink()


def _validate_screenshot_file(
    label: str,
    output: Path,
    expected_size: tuple[int, int],
) -> None:
    if not output.is_file():
        raise RuntimeError(f"{label} screenshot is missing: {output}")
    if _png_size(output) != expected_size:
        raise RuntimeError(
            f"{label} screenshot size contract is wrong: {output} "
            f"({_png_size(output)[0]}x{_png_size(output)[1]})"
        )
    _validate_rgb24_png(f"{label} screenshot {output.name}", output)


def _render_play_screenshot_outputs(
    entries: list[dict[str, object]],
    ffmpeg: str,
    hb_view: str,
    font: Path,
    temporary_path: Path,
    play_output_root: Path,
) -> list[Path]:
    outputs: list[Path] = []
    for index, entry in enumerate(entries, start=1):
        for locale in SCREENSHOT_LOCALES:
            outputs.append(
                _render_play_screenshot(
                    ffmpeg,
                    hb_view,
                    font,
                    entry,
                    index,
                    locale,
                    temporary_path,
                    play_output_root,
                )
            )
            for device, spec in PLAY_TABLET_FORMATS.items():
                outputs.append(
                    _render_play_tablet_screenshot(
                        ffmpeg,
                        hb_view,
                        font,
                        entry,
                        index,
                        locale,
                        device,
                        spec,
                        temporary_path,
                        play_output_root,
                    )
                )
    return outputs


def _render_app_store_screenshot_outputs(
    entries: list[dict[str, object]],
    iap_reviews: list[dict[str, object]],
    ffmpeg: str,
    hb_view: str,
    font: Path,
    temporary_path: Path,
    app_store_output_root: Path,
    iphone_source_mode: str,
) -> list[Path]:
    outputs: list[Path] = []
    for index, entry in enumerate(entries, start=1):
        for locale in SCREENSHOT_LOCALES:
            for device, spec in APP_STORE_FORMATS.items():
                outputs.append(
                    _render_app_store_screenshot(
                        ffmpeg,
                        hb_view,
                        font,
                        entry,
                        index,
                        locale,
                        device,
                        spec,
                        temporary_path,
                        app_store_output_root,
                        iphone_source_mode,
                    )
                )
    for review in iap_reviews:
        outputs.append(
            _render_iap_review_screenshot(
                ffmpeg,
                review,
                app_store_output_root / "iap-review",
            )
        )
    return outputs


def _render_all_screenshot_outputs(
    entries: list[dict[str, object]],
    iap_reviews: list[dict[str, object]],
    ffmpeg: str,
    hb_view: str,
    font: Path,
    temporary_path: Path,
    play_output_root: Path,
    app_store_output_root: Path,
    iap_output_root: Path,
    iphone_source_mode: str = APP_STORE_IPHONE_SOURCE_PHYSICAL,
) -> list[Path]:
    outputs = _render_play_screenshot_outputs(
        entries,
        ffmpeg,
        hb_view,
        font,
        temporary_path,
        play_output_root,
    )
    outputs.extend(_render_app_store_screenshot_outputs(
        entries,
        iap_reviews,
        ffmpeg,
        hb_view,
        font,
        temporary_path,
        app_store_output_root,
        iphone_source_mode,
    ))
    # Callers historically passed the IAP root separately. Fail closed if it
    # no longer belongs to the same App Store generation.
    if iap_output_root != app_store_output_root / "iap-review":
        raise RuntimeError("App Store IAP outputs are not the same staging generation")
    return outputs


def _assert_generated_screenshot_hashes(
    outputs: Iterable[Path],
    expected_outputs: Iterable[Path],
    expected_root: Path,
    actual_root: Path | None = None,
) -> None:
    generated_root = actual_root or RELEASE_OUTPUT_ROOT
    _assert_safe_repository_path(
        expected_root,
        RELEASE_OUTPUT_ROOT,
        "temporary deterministic screenshots",
    )
    _assert_safe_repository_path(
        generated_root,
        RELEASE_OUTPUT_ROOT,
        "derived store screenshot roots to check",
    )
    actual_by_path: dict[Path, Path] = {}
    for output in outputs:
        _assert_safe_repository_path(
            output,
            generated_root,
            "derived store screenshots",
        )
        actual_by_path[output.relative_to(generated_root)] = output
    expected_by_path: dict[Path, Path] = {}
    for output in expected_outputs:
        _assert_safe_repository_path(
            output,
            expected_root,
            "temporary deterministic screenshots",
        )
        expected_by_path[output.relative_to(expected_root)] = output
    if set(actual_by_path) != set(expected_by_path):
        raise RuntimeError(
            "derived store screenshots and temporary deterministic regeneration lists differ"
        )
    for relative_path, output in actual_by_path.items():
        expected = expected_by_path[relative_path]
        actual_sha256 = hashlib.sha256(output.read_bytes()).hexdigest()
        expected_sha256 = hashlib.sha256(expected.read_bytes()).hexdigest()
        if actual_sha256 != expected_sha256:
            raise RuntimeError(
                "derived store screenshot differs from deterministic regeneration of the "
                f"current sources/contract: {output}. Run pnpm store:screenshots again"
            )


def _assert_generated_screenshots_deterministic(
    entries: list[dict[str, object]],
    iap_reviews: list[dict[str, object]],
    outputs: Iterable[Path],
    ffmpeg: str,
    hb_view: str,
) -> None:
    _assert_safe_repository_path(
        RELEASE_OUTPUT_ROOT,
        REPO_ROOT / "builds",
        "store screenshot temporary regeneration root",
    )
    if not RELEASE_OUTPUT_ROOT.is_dir():
        raise RuntimeError(
            f"store screenshot output root is missing: {RELEASE_OUTPUT_ROOT}"
        )
    with tempfile.TemporaryDirectory(
        prefix=".moonlit-store-verify-",
        dir=RELEASE_OUTPUT_ROOT,
    ) as temporary:
        expected_root = Path(temporary)
        work = expected_root / "work"
        work.mkdir()
        expected_outputs = _render_all_screenshot_outputs(
            entries,
            iap_reviews,
            ffmpeg,
            hb_view,
            MARKETING_FONT,
            work,
            expected_root / "play",
            expected_root / "app-store",
            expected_root / "app-store/iap-review",
        )
        _assert_generated_screenshot_hashes(
            outputs,
            expected_outputs,
            expected_root,
        )


def _assert_generated_play_screenshots_deterministic(
    entries: list[dict[str, object]],
    outputs: Iterable[Path],
    ffmpeg: str,
    hb_view: str,
    play_output_root: Path | None = None,
) -> None:
    actual_play_root = play_output_root or PLAY_SCREENSHOT_OUTPUT
    _assert_safe_repository_path(
        RELEASE_OUTPUT_ROOT,
        REPO_ROOT / "builds",
        "Play screenshot temporary regeneration root",
    )
    if not RELEASE_OUTPUT_ROOT.is_dir():
        raise RuntimeError(
            f"store screenshot output root is missing: {RELEASE_OUTPUT_ROOT}"
        )
    with tempfile.TemporaryDirectory(
        prefix=".moonlit-play-verify-",
        dir=RELEASE_OUTPUT_ROOT,
    ) as temporary:
        expected_root = Path(temporary)
        work = expected_root / "work"
        work.mkdir()
        expected_outputs = _render_play_screenshot_outputs(
            entries,
            ffmpeg,
            hb_view,
            MARKETING_FONT,
            work,
            expected_root / "play",
        )
        _assert_generated_screenshot_hashes(
            outputs,
            expected_outputs,
            expected_root / "play",
            actual_play_root,
        )


def _app_store_provenance_path(output_root: Path) -> Path:
    return output_root / APP_STORE_SCREENSHOT_PROVENANCE_NAME


def _capture_report_artifact(path: Path, label: str) -> dict[str, object]:
    _assert_safe_repository_path(path, REPO_ROOT / "builds", label)
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"{label} must be a regular file: {path}")
    contents = path.read_bytes()
    return {
        "path": path.relative_to(REPO_ROOT).as_posix(),
        "file_size": len(contents),
        "sha256": hashlib.sha256(contents).hexdigest(),
    }


def _iphone_native_capture_files() -> list[Path]:
    root = DEVICE_CAPTURE_ROOT / "ios" / "iphone-6.5"
    _assert_safe_repository_path(root, DEVICE_CAPTURE_ROOT, "iPhone capture root")
    if not root.exists():
        return []
    if root.is_symlink() or not root.is_dir():
        raise RuntimeError("iPhone capture root is not a regular directory")
    return sorted(path for path in root.rglob("*") if path.is_file())


def _validate_app_store_capture_sources(
    entries: list[dict[str, object]],
    iphone_source_mode: str,
) -> dict[str, object]:
    if iphone_source_mode not in APP_STORE_IPHONE_SOURCE_MODES:
        raise RuntimeError(
            f"App Store iPhone source mode is invalid: "
            f"{iphone_source_mode}"
        )
    pixel_report = _validate_capture_report(entries)
    native_iphone_files = _iphone_native_capture_files()
    if iphone_source_mode == APP_STORE_IPHONE_SOURCE_ANDROID_AVD:
        if native_iphone_files:
            raise RuntimeError(
                "Android AVD iPhone marketing mode and physical iPhone evidence both "
                "exist. Make the capture origin unambiguous"
            )
        selected_devices = ("ipad-13",)
    else:
        selected_devices = ("iphone-6.5", "ipad-13")
    device_contexts = _validate_device_capture_reports_for_targets(
        entries,
        selected_devices,
    )
    if set(device_contexts) != set(selected_devices):
        raise RuntimeError("App Store device capture validation result differs from the selected mode")
    return {
        "iphone_source_mode": iphone_source_mode,
        "pixel_report": pixel_report,
        "device_contexts": device_contexts,
    }


def _capture_origin_for_app_store_target(
    device: str,
    capture_context: dict[str, object],
) -> tuple[dict[str, object], dict[str, dict[str, object]]]:
    mode = str(capture_context["iphone_source_mode"])
    if device == "iphone-6.5" \
            and mode == APP_STORE_IPHONE_SOURCE_ANDROID_AVD:
        report = capture_context["pixel_report"]
        if not isinstance(report, dict):
            raise RuntimeError("Pixel capture report is missing")
        report_artifact = _capture_report_artifact(
            SCREENSHOT_CAPTURE_REPORT,
            "Pixel canonical capture report",
        )
        anchor = report.get("persistence_anchor")
        if not isinstance(anchor, dict):
            raise RuntimeError("Pixel capture generation ID is missing")
        captures = report.get("captures")
        if not isinstance(captures, list):
            raise RuntimeError("Pixel capture list is missing")
        capture_map = {
            str(capture["source"]): capture
            for capture in captures
            if isinstance(capture, dict) and isinstance(capture.get("source"), str)
        }
        return ({
            "platform": "ANDROID",
            "environment": "AVD",
            "native_ios_capture": False,
            "avd_name": report.get("avd_name"),
            "api_level": report.get("api_level"),
            "capture_id": anchor.get("capture_id"),
            "captured_at": report.get("captured_at"),
            "capture_report_path": report_artifact["path"],
            "capture_report_sha256": report_artifact["sha256"],
            "runtime_sha256": report.get("runtime_sha256"),
            "input_sha256": _fingerprint_map_sha256(
                report.get("input_sha256"),
                "Pixel canonical capture input",
            ),
            "build_artifact_path": report.get("apk_path"),
            "build_artifact_sha256": report.get("apk_sha256"),
        }, capture_map)

    contexts = capture_context.get("device_contexts")
    context = contexts.get(device) if isinstance(contexts, dict) else None
    if not isinstance(context, dict):
        raise RuntimeError(f"{device} physical iOS capture context is missing")
    report = context.get("report")
    report_path = context.get("report_path")
    if not isinstance(report, dict) or not isinstance(report_path, Path):
        raise RuntimeError(f"{device} physical iOS capture report is missing")
    report_artifact = _capture_report_artifact(
        report_path,
        f"{device} physical iOS capture report",
    )
    source_snapshot = report.get("source_before")
    if not isinstance(source_snapshot, dict):
        raise RuntimeError(f"{device} iOS source snapshot is missing")
    captures = report.get("captures")
    if not isinstance(captures, list):
        raise RuntimeError(f"{device} iOS capture list is missing")
    capture_map = {
        str(capture["source"]): capture
        for capture in captures
        if isinstance(capture, dict) and isinstance(capture.get("source"), str)
    }
    return ({
        "platform": "IOS",
        "environment": "PHYSICAL_DEVICE",
        "native_ios_capture": True,
        "model_identifier": report.get("model_identifier"),
        "captured_at": report.get("captured_at"),
        "capture_report_path": report_artifact["path"],
        "capture_report_sha256": report_artifact["sha256"],
        "runtime_sha256": source_snapshot.get("runtime_sha256"),
        "input_sha256": _fingerprint_map_sha256(
            source_snapshot.get("source_input_sha256"),
            f"{device} physical iOS capture input",
        ),
        "build_artifact_path": report.get("build_artifact_path"),
        "build_artifact_sha256": report.get("build_artifact_sha256"),
    }, capture_map)


def _app_store_provenance_set(
    entries: list[dict[str, object]],
    output_root: Path,
    device: str,
    capture_context: dict[str, object],
) -> dict[str, object]:
    spec = APP_STORE_FORMATS[device]
    origin, capture_map = _capture_origin_for_app_store_target(
        device,
        capture_context,
    )
    mode = str(capture_context["iphone_source_mode"])
    mappings: list[dict[str, object]] = []
    source_hashes: set[str] = set()
    output_hashes: set[str] = set()
    transform: dict[str, object] | None = None
    for locale in SCREENSHOT_LOCALES:
        for entry in entries:
            source = _app_store_entry_source(entry, locale, device, mode)
            _assert_safe_repository_path(
                source,
                REPO_ROOT / "builds/shots",
                f"{device} provenance source",
            )
            source_relative = source.relative_to(REPO_ROOT).as_posix()
            capture = capture_map.get(source_relative)
            if not isinstance(capture, dict):
                raise RuntimeError(
                    f"{device} provenance source is missing from the verified capture report: "
                    f"{source_relative}"
                )
            source_bytes = source.read_bytes()
            source_sha256 = hashlib.sha256(source_bytes).hexdigest()
            if capture.get("sha256") != source_sha256:
                raise RuntimeError(
                    f"{device} provenance source hash differs from the capture report: "
                    f"{source_relative}"
                )
            if source_sha256 in source_hashes:
                raise RuntimeError(
                    f"{device} provenance reused the same raw PNG"
                )
            source_hashes.add(source_sha256)
            source_width, source_height = _png_size(source)
            current_transform = _app_store_transform(
                source_width,
                source_height,
                spec,
            )
            if transform is None:
                transform = current_transform
            elif transform != current_transform:
                raise RuntimeError(
                    f"{device} provenance source resolution/transform differs across scenes"
                )
            proof_path = _device_capture_repository_file(
                capture.get("proof_path"),
                f"{device} provenance proof",
            )
            output = (
                output_root
                / APP_STORE_LOCALES[locale]
                / device
                / str(entry["output"])
            )
            _assert_safe_repository_path(
                output,
                output_root,
                f"{device} provenance output",
            )
            _validate_screenshot_file(
                f"App Store {APP_STORE_LOCALES[locale]} {device}",
                output,
                spec["size"],
            )
            output_sha256 = hashlib.sha256(output.read_bytes()).hexdigest()
            if output_sha256 in output_hashes:
                raise RuntimeError(
                    f"{device} provenance reused the same output PNG"
                )
            output_hashes.add(output_sha256)
            mappings.append({
                "asset_locale": locale,
                "store_locale": APP_STORE_LOCALES[locale],
                "game_locale": GAME_LOCALES[locale],
                "kind": capture.get("kind"),
                "source_path": source_relative,
                "source_sha256": source_sha256,
                "source_width": source_width,
                "source_height": source_height,
                "proof_path": proof_path.relative_to(REPO_ROOT).as_posix(),
                "proof_sha256": hashlib.sha256(
                    proof_path.read_bytes()
                ).hexdigest(),
                "output_path": (
                    APP_STORE_SCREENSHOT_OUTPUT
                    / APP_STORE_LOCALES[locale]
                    / device
                    / str(entry["output"])
                ).relative_to(REPO_ROOT).as_posix(),
                "output_sha256": output_sha256,
                "output_width": int(spec["size"][0]),
                "output_height": int(spec["size"][1]),
            })
    if len(mappings) != len(SCREENSHOT_LOCALES) * len(entries) \
            or transform is None:
        raise RuntimeError(f"{device} provenance mapping is not exactly 30 images")
    renderer_path = Path(__file__).resolve()
    transform = {
        **transform,
        "renderer_path": renderer_path.relative_to(REPO_ROOT).as_posix(),
        "renderer_sha256": hashlib.sha256(
            renderer_path.read_bytes()
        ).hexdigest(),
        "direct_native_device_representation": (
            origin["native_ios_capture"] is True
        ),
    }
    target_width, target_height = spec["size"]
    return {
        "id": device,
        "submission_target": {
            "platform": "IOS",
            "device_class": device,
            "display_type": spec["display_type"],
            "width": target_width,
            "height": target_height,
        },
        "capture_origin": origin,
        "transform": transform,
        "mappings": mappings,
    }


def _build_app_store_screenshot_provenance(
    entries: list[dict[str, object]],
    output_root: Path,
    capture_context: dict[str, object],
) -> dict[str, object]:
    pixel_artifact = _capture_report_artifact(
        SCREENSHOT_CAPTURE_REPORT,
        "Pixel canonical capture report",
    )
    return {
        "schema_version": 1,
        "contract": APP_STORE_SCREENSHOT_PROVENANCE_CONTRACT,
        "iphone_source_mode": capture_context["iphone_source_mode"],
        "capture_report": pixel_artifact,
        "sets": [
            _app_store_provenance_set(
                entries, output_root, device, capture_context
            )
            for device in APP_STORE_FORMATS
        ],
    }


def _write_app_store_screenshot_provenance(
    output_root: Path,
    provenance: dict[str, object],
) -> Path:
    path = _app_store_provenance_path(output_root)
    _assert_safe_repository_path(path, output_root, "App Store provenance output")
    path.parent.mkdir(parents=True, exist_ok=True)
    contents = (
        json.dumps(
            provenance,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ) + "\n"
    ).encode("utf-8")
    temporary = path.with_name(f".{path.name}.tmp")
    _assert_safe_repository_path(
        temporary,
        output_root,
        "App Store provenance temporary output",
    )
    if temporary.exists():
        if temporary.is_symlink() or not temporary.is_file():
            raise RuntimeError("App Store provenance temporary path is unsafe")
        temporary.unlink()
    with temporary.open("xb") as output:
        output.write(contents)
        output.flush()
        os.fsync(output.fileno())
    temporary.replace(path)
    return path


def _validate_app_store_screenshot_provenance(
    entries: list[dict[str, object]],
    output_root: Path | None = None,
) -> tuple[dict[str, object], dict[str, object]]:
    root = output_root or APP_STORE_SCREENSHOT_OUTPUT
    path = _app_store_provenance_path(root)
    _assert_safe_repository_path(path, root, "App Store screenshot provenance")
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"App Store screenshot provenance is missing: {path}")
    try:
        provenance = json.loads(path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError("App Store screenshot provenance JSON is invalid") \
            from error
    if not isinstance(provenance, dict) \
            or provenance.get("schema_version") != 1 \
            or provenance.get("contract") \
                != APP_STORE_SCREENSHOT_PROVENANCE_CONTRACT \
            or provenance.get("iphone_source_mode") \
                not in APP_STORE_IPHONE_SOURCE_MODES:
        raise RuntimeError("App Store screenshot provenance contract is invalid")
    mode = str(provenance["iphone_source_mode"])
    capture_context = _validate_app_store_capture_sources(entries, mode)
    expected = _build_app_store_screenshot_provenance(
        entries,
        root,
        capture_context,
    )
    if provenance != expected:
        raise RuntimeError(
            "App Store screenshot provenance differs from the current capture report/sources/outputs. "
            "Rebuild the App Store screenshots"
        )
    return provenance, capture_context


def _play_screenshot_output_sets(
    output_root: Path | None = None,
) -> list[tuple[str, Path, tuple[int, int]]]:
    root = output_root or PLAY_SCREENSHOT_OUTPUT
    output_sets: list[tuple[str, Path, tuple[int, int]]] = []
    for locale in SCREENSHOT_LOCALES:
        play_locale = PLAY_LOCALES[locale]
        output_sets.append(
            (
                f"Play {play_locale}",
                root / play_locale / "screenshots",
                (1920, 1080),
            )
        )
        for device, spec in PLAY_TABLET_FORMATS.items():
            output_sets.append(
                (
                    f"Play {play_locale} {device}",
                    root / play_locale / device,
                    spec["size"],
                )
            )
    return output_sets


def _validate_play_screenshot_outputs(
    entries: list[dict[str, object]],
    output_root: Path | None = None,
) -> list[Path]:
    play_output_root = output_root or PLAY_SCREENSHOT_OUTPUT
    expected_names = {str(entry["output"]) for entry in entries}
    _assert_safe_repository_path(
        play_output_root,
        RELEASE_OUTPUT_ROOT,
        "Play screenshot root",
    )
    if not play_output_root.is_dir():
        raise RuntimeError(
            f"Play screenshot root is missing: {play_output_root}"
        )
    expected_locales = set(PLAY_LOCALES.values())
    actual_locales = {path.name for path in play_output_root.iterdir()}
    if actual_locales != expected_locales:
        raise RuntimeError(
            "Play screenshot locale tree differs from the exact set of 5 "
            f"(missing={sorted(expected_locales - actual_locales)}, "
            f"stale={sorted(actual_locales - expected_locales)})"
        )
    expected_targets = {"screenshots", *PLAY_TABLET_FORMATS}
    for play_locale in expected_locales:
        locale_root = play_output_root / play_locale
        _assert_safe_repository_path(
            locale_root,
            play_output_root,
            f"Play {play_locale} locale root",
        )
        if not locale_root.is_dir():
            raise RuntimeError(
                f"Play {play_locale} locale path is not a directory"
            )
        actual_targets = {path.name for path in locale_root.iterdir()}
        if actual_targets != expected_targets:
            raise RuntimeError(
                f"Play {play_locale} device tree differs from the exact set of 3 "
                f"(missing={sorted(expected_targets - actual_targets)}, "
                f"stale={sorted(actual_targets - expected_targets)})"
            )
    outputs: list[Path] = []
    for label, directory, size in _play_screenshot_output_sets(play_output_root):
        _assert_safe_repository_path(
            directory,
            play_output_root,
            f"{label} screenshot check path",
        )
        if not directory.is_dir():
            raise RuntimeError(f"{label} screenshot path is not a directory")
        actual_names = {path.name for path in directory.iterdir()}
        if actual_names != expected_names:
            missing = sorted(expected_names - actual_names)
            stale = sorted(actual_names - expected_names)
            raise RuntimeError(
                f"{label} screenshot set differs from the manifest "
                f"(missing={missing}, stale={stale})"
            )
        for name in sorted(expected_names):
            output = directory / name
            _assert_safe_repository_path(
                output,
                play_output_root,
                f"{label} screenshot file",
            )
            _validate_screenshot_file(label, output, size)
            outputs.append(output)
    return outputs


def _validate_generated_play_screenshots(
    entries: list[dict[str, object]],
    output_root: Path | None = None,
) -> list[Path]:
    play_output_root = output_root or PLAY_SCREENSHOT_OUTPUT
    _validate_capture_report(entries)
    _validate_play_device_capture_reports(entries)
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("Play screenshot validation requires ffmpeg")
    _, hb_view = _validate_marketing_glyphs(entries)
    stale_play_output = play_output_root / "screenshots"
    _assert_safe_repository_path(
        stale_play_output,
        RELEASE_OUTPUT_ROOT,
        "legacy Play screenshot check path",
    )
    if stale_play_output.exists():
        raise RuntimeError(
            "legacy Play locale path remains and would confuse upload targets: "
            f"{stale_play_output}. Rebuild the Play screenshots"
        )
    outputs = _validate_play_screenshot_outputs(entries, play_output_root)
    _assert_generated_play_screenshots_deterministic(
        entries,
        outputs,
        ffmpeg,
        hb_view,
        play_output_root,
    )
    return outputs


def _validate_app_store_screenshot_outputs(
    entries: list[dict[str, object]],
    output_root: Path | None = None,
) -> list[Path]:
    root = output_root or APP_STORE_SCREENSHOT_OUTPUT
    _assert_safe_repository_path(root, RELEASE_OUTPUT_ROOT, "App Store output root")
    if root.is_symlink() or not root.is_dir():
        raise RuntimeError(f"App Store screenshot root is missing: {root}")
    expected_root_entries = {
        *APP_STORE_LOCALES.values(),
        "iap-review",
        APP_STORE_SCREENSHOT_PROVENANCE_NAME,
    }
    actual_root_entries = {path.name for path in root.iterdir()}
    if actual_root_entries != expected_root_entries:
        raise RuntimeError(
            "App Store screenshot generation file set differs "
            f"(missing={sorted(expected_root_entries - actual_root_entries)}, "
            f"stale={sorted(actual_root_entries - expected_root_entries)})"
        )
    expected_names = {str(entry["output"]) for entry in entries}
    outputs: list[Path] = []
    for locale in SCREENSHOT_LOCALES:
        app_store_locale = APP_STORE_LOCALES[locale]
        locale_root = root / app_store_locale
        _assert_safe_repository_path(
            locale_root,
            root,
            f"App Store {app_store_locale} locale root",
        )
        if locale_root.is_symlink() or not locale_root.is_dir():
            raise RuntimeError(
                f"App Store {app_store_locale} locale root is invalid"
            )
        actual_targets = {path.name for path in locale_root.iterdir()}
        if actual_targets != set(APP_STORE_FORMATS):
            raise RuntimeError(
                f"App Store {app_store_locale} target tree differs"
            )
        for device, spec in APP_STORE_FORMATS.items():
            directory = locale_root / device
            _assert_safe_repository_path(
                directory,
                root,
                f"App Store {app_store_locale}/{device}",
            )
            if directory.is_symlink() or not directory.is_dir():
                raise RuntimeError(
                    f"App Store {app_store_locale}/{device} path is invalid"
                )
            actual_names = {path.name for path in directory.iterdir()}
            if actual_names != expected_names:
                raise RuntimeError(
                    f"App Store {app_store_locale}/{device} PNG set differs"
                )
            for name in sorted(expected_names):
                output = directory / name
                _validate_screenshot_file(
                    f"App Store {app_store_locale} {device}",
                    output,
                    spec["size"],
                )
                outputs.append(output)

    iap_reviews = _iap_review_entries()
    expected_iap_names = {str(review["output"]) for review in iap_reviews}
    iap_root = root / "iap-review"
    _assert_safe_repository_path(iap_root, root, "App Store IAP review root")
    if iap_root.is_symlink() or not iap_root.is_dir():
        raise RuntimeError("App Store IAP review root is invalid")
    actual_iap_names = {path.name for path in iap_root.iterdir()}
    if actual_iap_names != expected_iap_names:
        raise RuntimeError(
            "App Store per-product IAP review images differ from the contract "
            f"(missing={sorted(expected_iap_names - actual_iap_names)}, "
            f"stale={sorted(actual_iap_names - expected_iap_names)})"
        )
    for review in iap_reviews:
        output = iap_root / str(review["output"])
        _validate_screenshot_file(
            f"App Store IAP review {review['product_id']}",
            output,
            (2778, 1284),
        )
        outputs.append(output)
    return outputs


def _assert_generated_app_store_screenshots_deterministic(
    entries: list[dict[str, object]],
    outputs: Iterable[Path],
    ffmpeg: str,
    hb_view: str,
    iphone_source_mode: str,
    output_root: Path | None = None,
) -> None:
    actual_root = output_root or APP_STORE_SCREENSHOT_OUTPUT
    with tempfile.TemporaryDirectory(
        prefix=".moonlit-app-store-verify-",
        dir=RELEASE_OUTPUT_ROOT,
    ) as temporary:
        expected_root = Path(temporary)
        work = expected_root / "work"
        work.mkdir()
        expected_app_store_root = expected_root / "app-store"
        expected_outputs = _render_app_store_screenshot_outputs(
            entries,
            _iap_review_entries(),
            ffmpeg,
            hb_view,
            MARKETING_FONT,
            work,
            expected_app_store_root,
            iphone_source_mode,
        )
        _assert_generated_screenshot_hashes(
            outputs,
            expected_outputs,
            expected_app_store_root,
            actual_root,
        )


def _validate_generated_app_store_screenshots(
    entries: list[dict[str, object]],
    output_root: Path | None = None,
) -> list[Path]:
    root = output_root or APP_STORE_SCREENSHOT_OUTPUT
    _assert_no_stale_iap_review_source()
    provenance, _ = _validate_app_store_screenshot_provenance(entries, root)
    outputs = _validate_app_store_screenshot_outputs(entries, root)
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("App Store screenshot validation requires ffmpeg")
    _, hb_view = _validate_marketing_glyphs(entries)
    _assert_generated_app_store_screenshots_deterministic(
        entries,
        outputs,
        ffmpeg,
        hb_view,
        str(provenance["iphone_source_mode"]),
        root,
    )
    return outputs


def _validate_generated_screenshots(entries: list[dict[str, object]]) -> list[Path]:
    _assert_no_stale_iap_review_source()
    play_outputs = _validate_generated_play_screenshots(entries)
    app_store_outputs = _validate_generated_app_store_screenshots(entries)
    return [*play_outputs, *app_store_outputs]


def _atomic_exchange_directories(first: Path, second: Path) -> None:
    """Atomically exchanges two same-filesystem directories or fails closed."""
    libc = ctypes.CDLL(None, use_errno=True)
    first_bytes = os.fsencode(first)
    second_bytes = os.fsencode(second)
    if sys.platform == "darwin":
        renamex_np = getattr(libc, "renamex_np", None)
        if renamex_np is None:
            raise RuntimeError(
                "this macOS runtime does not support atomic directory exchange"
            )
        renamex_np.argtypes = [
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        renamex_np.restype = ctypes.c_int
        result = renamex_np(first_bytes, second_bytes, 0x00000002)
    elif sys.platform.startswith("linux"):
        renameat2 = getattr(libc, "renameat2", None)
        if renameat2 is None:
            raise RuntimeError(
                "this Linux runtime does not support atomic directory exchange"
            )
        renameat2.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        renameat2.restype = ctypes.c_int
        result = renameat2(-100, first_bytes, -100, second_bytes, 0x00000002)
    else:
        raise RuntimeError(
            f"{sys.platform} does not support atomic directory exchange"
        )
    if result != 0:
        error_number = ctypes.get_errno()
        raise OSError(
            error_number,
            os.strerror(error_number),
            f"{first} <-> {second}",
        )


def _publish_play_screenshot_root(staged_root: Path) -> None:
    _assert_safe_repository_path(
        staged_root,
        RELEASE_OUTPUT_ROOT,
        "Play screenshot staging root",
    )
    _assert_safe_repository_path(
        PLAY_SCREENSHOT_OUTPUT,
        RELEASE_OUTPUT_ROOT,
        "Play screenshot publish root",
    )
    if not staged_root.is_dir():
        raise RuntimeError(f"Play screenshot staging root is missing: {staged_root}")
    had_previous = PLAY_SCREENSHOT_OUTPUT.exists()
    if had_previous:
        if PLAY_SCREENSHOT_OUTPUT.is_symlink() \
                or not PLAY_SCREENSHOT_OUTPUT.is_dir():
            raise RuntimeError(
                "Play screenshot publish path is not a regular directory"
            )
        _atomic_exchange_directories(staged_root, PLAY_SCREENSHOT_OUTPUT)
        # After exchange, staged_root holds the previous canonical tree. Canonical is
        # already fully replaced in one syscall, so only clean up the old generation now.
        try:
            shutil.rmtree(staged_root)
        except OSError as error:
            # Publication already finished atomically. Turning a cleanup error into a publish
            # failure would report failure with the new canonical already installed, so leave
            # only the temporary old generation and rely on best-effort cleanup of the parent temp folder.
            print(
                f"warning: failed to remove previous Play screenshot temporary generation: "
                f"{error}",
                file=sys.stderr,
            )
    else:
        staged_root.rename(PLAY_SCREENSHOT_OUTPUT)


def _publish_app_store_screenshot_root(staged_root: Path) -> None:
    _assert_safe_repository_path(
        staged_root,
        RELEASE_OUTPUT_ROOT,
        "App Store screenshot staging root",
    )
    _assert_safe_repository_path(
        APP_STORE_SCREENSHOT_OUTPUT,
        RELEASE_OUTPUT_ROOT,
        "App Store screenshot publish root",
    )
    if staged_root.is_symlink() or not staged_root.is_dir():
        raise RuntimeError(
            f"App Store screenshot staging root is missing: {staged_root}"
        )
    if APP_STORE_SCREENSHOT_OUTPUT.exists():
        if APP_STORE_SCREENSHOT_OUTPUT.is_symlink() \
                or not APP_STORE_SCREENSHOT_OUTPUT.is_dir():
            raise RuntimeError(
                "App Store screenshot publish path is not a regular directory"
            )
        _atomic_exchange_directories(staged_root, APP_STORE_SCREENSHOT_OUTPUT)
        try:
            shutil.rmtree(staged_root)
        except OSError as error:
            print(
                "warning: failed to remove previous App Store screenshot temporary "
                f"generation: {error}",
                file=sys.stderr,
            )
    else:
        staged_root.rename(APP_STORE_SCREENSHOT_OUTPUT)


def _build_play_screenshots() -> list[Path]:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("Play screenshot assembly requires ffmpeg")
    entries = _screenshot_entries()
    _validate_capture_report(entries)
    _validate_play_device_capture_reports(entries)
    _, hb_view = _validate_marketing_glyphs(entries)
    _assert_safe_repository_path(
        RELEASE_OUTPUT_ROOT,
        REPO_ROOT / "builds",
        "Play screenshot staging parent path",
    )
    RELEASE_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)

    temporary_path = Path(tempfile.mkdtemp(
        prefix=".moonlit-play-store-",
        dir=RELEASE_OUTPUT_ROOT,
    ))
    try:
        staging_root = temporary_path / "play"
        _render_play_screenshot_outputs(
            entries,
            ffmpeg,
            hb_view,
            MARKETING_FONT,
            temporary_path,
            staging_root,
        )
        staged_outputs = _validate_generated_play_screenshots(
            entries,
            staging_root,
        )
        relative_outputs = [
            output.relative_to(staging_root) for output in staged_outputs
        ]
        _publish_play_screenshot_root(staging_root)
    finally:
        shutil.rmtree(temporary_path, ignore_errors=True)
    return [PLAY_SCREENSHOT_OUTPUT / path for path in relative_outputs]


def _build_app_store_screenshots(
    iphone_source_mode: str = APP_STORE_IPHONE_SOURCE_PHYSICAL,
) -> list[Path]:
    _remove_stale_iap_review_source()
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("App Store screenshot assembly requires ffmpeg")
    entries = _screenshot_entries()
    capture_context = _validate_app_store_capture_sources(
        entries,
        iphone_source_mode,
    )
    _, hb_view = _validate_marketing_glyphs(entries)
    _assert_safe_repository_path(
        RELEASE_OUTPUT_ROOT,
        REPO_ROOT / "builds",
        "App Store screenshot staging parent path",
    )
    RELEASE_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    iap_reviews = _iap_review_entries()

    temporary_path = Path(tempfile.mkdtemp(
        prefix=".moonlit-app-store-",
        dir=RELEASE_OUTPUT_ROOT,
    ))
    try:
        staging_root = temporary_path / "app-store"
        _render_app_store_screenshot_outputs(
            entries,
            iap_reviews,
            ffmpeg,
            hb_view,
            MARKETING_FONT,
            temporary_path,
            staging_root,
            iphone_source_mode,
        )
        provenance = _build_app_store_screenshot_provenance(
            entries,
            staging_root,
            capture_context,
        )
        _write_app_store_screenshot_provenance(staging_root, provenance)
        staged_outputs = _validate_generated_app_store_screenshots(
            entries,
            staging_root,
        )
        relative_outputs = [
            output.relative_to(staging_root) for output in staged_outputs
        ]
        _publish_app_store_screenshot_root(staging_root)
    finally:
        shutil.rmtree(temporary_path, ignore_errors=True)
    return [APP_STORE_SCREENSHOT_OUTPUT / path for path in relative_outputs]


def _build_screenshots(
    iphone_source_mode: str = APP_STORE_IPHONE_SOURCE_PHYSICAL,
) -> list[Path]:
    # Legacy shared IAP source cleanup must happen before either staged build so
    # an early failure cannot leave a misleading input alongside the new tree.
    _remove_stale_iap_review_source()
    play_outputs = _build_play_screenshots()
    app_store_outputs = _build_app_store_screenshots(iphone_source_mode)
    return [*play_outputs, *app_store_outputs]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="only check that tracked production graphics match the deterministic result",
    )
    parser.add_argument(
        "--screenshots",
        action="store_true",
        help="assemble curated device captures for Play and App Store",
    )
    parser.add_argument(
        "--check-screenshots",
        action="store_true",
        help=(
            "check generated screenshot state proofs/specs and deterministic "
            "regeneration SHA-256 against the current sources"
        ),
    )
    parser.add_argument(
        "--play-screenshots",
        action="store_true",
        help=(
            "validate only Android phone/7-inch/10-inch device captures and "
            "assemble 90 Google Play images"
        ),
    )
    parser.add_argument(
        "--check-play-screenshots",
        action="store_true",
        help=(
            "check only the Android state proofs/specs and deterministic "
            "regeneration SHA-256 for the 90 Google Play images"
        ),
    )
    parser.add_argument(
        "--app-store-screenshots",
        action="store_true",
        help=(
            "validate iPhone/iPad provenance and assemble 60 App Store images "
            "plus 10 IAP review images"
        ),
    )
    parser.add_argument(
        "--check-app-store-screenshots",
        action="store_true",
        help=(
            "check only the App Store 60 + IAP 10 provenance origin/hash/"
            "deterministic-regeneration contract against saved capture provenance"
        ),
    )
    parser.add_argument(
        "--app-store-iphone-source",
        choices=APP_STORE_IPHONE_SOURCE_MODES,
        default=None,
        help=(
            "source for App Store iPhone creation. Default is physical-ios; "
            "Android Pixel AVD marketing composites must explicitly pass "
            "android-pixel-avd at create time"
        ),
    )
    args = parser.parse_args()
    screenshot_actions = (
        args.screenshots,
        args.check_screenshots,
        args.play_screenshots,
        args.check_play_screenshots,
        args.app_store_screenshots,
        args.check_app_store_screenshots,
    )
    if sum(bool(action) for action in screenshot_actions) > 1:
        parser.error("choose only one screenshot create or check mode")
    screenshot_generation = args.screenshots or args.app_store_screenshots
    if args.app_store_iphone_source is not None and not screenshot_generation:
        parser.error(
            "--app-store-iphone-source can only be used with --screenshots or "
            "--app-store-screenshots"
        )
    iphone_source_mode = (
        args.app_store_iphone_source or APP_STORE_IPHONE_SOURCE_PHYSICAL
    )
    play_screenshot_mode = args.play_screenshots or args.check_play_screenshots

    production = _production_outputs(play_only=play_screenshot_mode)
    entries = _screenshot_entries()
    if args.check \
            or args.check_screenshots \
            or args.check_play_screenshots \
            or args.check_app_store_screenshots:
        for path, expected in production.items():
            _assert_safe_repository_path(
                path,
                STORE_ROOT,
                "tracked store graphics",
            )
            if not path.is_file():
                raise RuntimeError(f"production store graphic is missing: {path}")
            if path.read_bytes() != expected:
                raise RuntimeError(
                    f"store graphic differs from the deterministic create result: {path}. "
                    "Run build_store_graphics.py again"
                )
            if path.name == "feature-graphic-1024x500.png":
                _validate_rgb24_png("Play feature graphic", path)
    else:
        for path, data in production.items():
            _assert_safe_repository_path(
                path,
                STORE_ROOT,
                "tracked store graphics output",
            )
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    screenshot_outputs: Iterable[Path] = ()
    if args.screenshots:
        screenshot_outputs = _build_screenshots(iphone_source_mode)
    elif args.check_screenshots:
        screenshot_outputs = _validate_generated_screenshots(entries)
    elif args.play_screenshots:
        screenshot_outputs = _build_play_screenshots()
    elif args.check_play_screenshots:
        screenshot_outputs = _validate_generated_play_screenshots(entries)
    elif args.app_store_screenshots:
        screenshot_outputs = _build_app_store_screenshots(iphone_source_mode)
    elif args.check_app_store_screenshots:
        screenshot_outputs = _validate_generated_app_store_screenshots(entries)

    print("Play icon: 512x512 opaque")
    print("Play feature graphic: 1024x500 opaque")
    if not play_screenshot_mode:
        print("IAP artwork: 8 x 512x512 opaque")
    if args.check:
        print("check: tracked store graphics are deterministic")
    if args.check_screenshots:
        print(
            "check: generated store screenshots match semantic, size, RGB24, "
            "and deterministic SHA-256 contracts"
        )
    if args.check_play_screenshots:
        print(
            "check: generated Play screenshots match Android semantic, size, "
            "RGB24, and deterministic SHA-256 contracts"
        )
    if args.check_app_store_screenshots:
        print(
            "check: generated App Store screenshots match capture provenance, "
            "size, RGB24, and deterministic SHA-256 contracts"
        )
    for output in screenshot_outputs:
        width, height = _png_size(output)
        print(
            f"Store screenshot: {output.relative_to(REPO_ROOT)} "
            f"({width}x{height}, RGB24)"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
