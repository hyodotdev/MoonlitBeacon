extends Control

## Title screen.
##
## Tap the screen and the beacon flares once, then `start_requested` fires.
## That signal is what goes to the arena.

signal start_requested

## Where a tap goes next.
## One path line here so moving the arena file is one edit.
const ARENA_SCENE: String = "res://scenes/gameplay/arena.tscn"
## One-shot mark consumed when the arena result picked the shrine.
const OPEN_SHRINE_META: StringName = &"moonlit_open_shrine"
const OPEN_STORE_META: StringName = &"moonlit_open_store"
const CAPTURE_DRAW_FRAME_UNSET: int = -2
const CAPTURE_TEXT_READABLE_ALPHA: float = 0.35
const CAPTURE_ART_OPAQUE_ALPHA: float = 0.99
const CAPTURE_ART_MIN_DRAW_SIZE: float = 32.0
const CAPTURE_ART_MIN_VISIBLE_EDGE: float = 12.0
const CAPTURE_ART_MIN_VISIBLE_FRACTION: float = 0.35
const CAPTURE_NIGHT_FOREST_SCENE: String = \
	"res://scenes/gameplay/night_forest.tscn"
const CAPTURE_FOREST_GROUND_TEXTURE: String = \
	"res://assets/custom/world/terrain/forest_floor.png"
const CAPTURE_BEACON_SCENE: String = "res://scenes/objectives/beacon.tscn"
const CAPTURE_BEACON_CLEARING_TEXTURE: String = \
	"res://assets/custom/world/beacon/clearing.png"
const CAPTURE_VIGNETTE_TEXTURE_CLASS: String = "GradientTexture2D"
const CAPTURE_VIGNETTE_TEXTURE_UNIQUE_ID: String = "GradientTexture2D_vignette"
const CAPTURE_VIGNETTE_TEXTURE_WIDTH: int = 512
const CAPTURE_VIGNETTE_TEXTURE_HEIGHT: int = 512

## Label auto-translation draws the translated string on screen but keeps the
## source key in the `text` property. Store-capture proof does not mix those
## two meanings: it checks the key, auto-translate on, and the current
## locale's real translation separately.
const CAPTURE_TITLE_COPY_BY_LOCALE: Dictionary = {
	"ko": {
		"title": "달빛 봉화",
		"subtitle": "밤을 밝히는 마지막 불빛",
		"tap": "화면을 탭하여 시작",
		"settings": "설정",
		"shrine": "제단",
		"ladder": "순위",
		"store": "상점",
	},
	"en": {
		"title": "MOONLIT BEACON",
		"subtitle": "OUTLAST THE NIGHT",
		"tap": "Tap to start",
		"settings": "Settings",
		"shrine": "Shrine",
		"ladder": "Ranks",
		"store": "Store",
	},
	"ja": {
		"title": "月明かりの烽火",
		"subtitle": "夜を照らす最後の灯",
		"tap": "画面をタップして開始",
		"settings": "設定",
		"shrine": "祭壇",
		"ladder": "順位",
		"store": "ストア",
	},
	"zh_CN": {
		"title": "月光烽火",
		"subtitle": "照亮长夜的最后火光",
		"tap": "点击屏幕开始",
		"settings": "设置",
		"shrine": "祭坛",
		"ladder": "排名",
		"store": "商店",
	},
	"zh_TW": {
		"title": "月光烽火",
		"subtitle": "照亮長夜的最後火光",
		"tap": "點擊畫面開始",
		"settings": "設定",
		"shrine": "祭壇",
		"ladder": "排名",
		"store": "商店",
	},
}

## Length of the beacon flare. Matched to the "flare" Animation length.
const FLARE_SECONDS: float = 0.85

## BGM rises from silence. Half a beat of rest so music does not slam in the
## instant the screen appears.
##
## First pass waited 0.35s then rose over 2.4s. Elegant, but **tap start
## before it fills and they never know there is music** — people actually
## said maybe a little BGM on the title would be nice. It was already there
## and inaudible. Keep the target volume; only bring the entrance forward.
const BGM_VOLUME_DB: float = -9.0
const BGM_SILENCE_DB: float = -60.0
const BGM_START_DELAY_SECONDS: float = 0.15
const BGM_FADE_IN_SECONDS: float = 0.9

## Where the beacon stands. Coords inside the base resolution (`Screen.BASE_SIZE`).
## Centering math is the same as the arena, so it lives in `Screen`.
const BEACON_POSITION: Vector2 = Vector2(404, 250)

## Time for music to fade after a tap. Finish shorter than the beacon flare
## (0.85s) so the audio thread has a mix. Then swapping scenes does not stall
## the screen.
const BGM_FADE_OUT_SECONDS: float = 0.55

@onready var _forest: Node2D = $NightForest
@onready var _vignette: Sprite2D = $NightForest/Vignette
@onready var _beacon: Node2D = $Beacon
@onready var _beacon_player: AnimationPlayer = $BeaconFx
@onready var _screen: Control = $Ui/Screen
@onready var _prompt: Label = $Ui/Screen/TapPrompt
@onready var _prompt_player: AnimationPlayer = $Ui/Screen/PromptBlink
@onready var _version: Label = $Ui/Screen/Version
@onready var _bgm: AudioStreamPlayer = $Bgm
@onready var _sfx: AudioStreamPlayer = $Sfx
@onready var _settings: Control = $Ui/Settings
@onready var _credits: Control = $Ui/Credits
@onready var _quit: Control = $Ui/Quit
@onready var _shrine: Control = $Ui/Shrine
@onready var _ladder: Control = $Ui/Ladder
@onready var _iap_shop: Control = $Ui/IapShop
@onready var _shrine_badge: Label = $Ui/Screen/ShrineButton/PurchaseBadge

var _accepting: bool = true
var _ready_draw_frame: int = CAPTURE_DRAW_FRAME_UNSET
## Store masters must not change with whichever blink brightness the host
## stops on. Turn this on only after a debug capture request actually arrives;
## the normal title's blink autoplay stays.
var _debug_title_capture_active: bool = false


func _ready() -> void:
	_ready_draw_frame = Engine.get_frames_drawn()
	# Version string is managed in project.godot only.
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_version.text = "v" + version

	get_viewport().size_changed.connect(_recenter_diorama)
	_recenter_diorama()

	start_requested.connect(_enter_arena)

	$Ui/Screen/SettingsButton.pressed.connect(_open_settings)
	$Ui/Screen/ShrineButton.pressed.connect(_open_shrine)
	_shrine.closed.connect(_on_panel_closed)
	$Ui/Screen/LadderButton.pressed.connect(_open_ladder)
	_ladder.closed.connect(_on_panel_closed)
	var store_button: Button = $Ui/Screen/StoreButton
	var storefront_enabled: bool = IapStore.storefront_enabled()
	store_button.visible = storefront_enabled
	store_button.disabled = not storefront_enabled
	if store_button.visible:
		store_button.pressed.connect(_open_iap_shop)
	_iap_shop.closed.connect(_on_panel_closed)
	_settings.credits_requested.connect(_open_credits)
	_settings.closed.connect(_on_panel_closed)
	_credits.closed.connect(_on_credits_closed)
	_quit.cancelled.connect(_on_panel_closed)
	Vault.changed.connect(_refresh_shrine_badge)

	_refresh_shrine_badge()
	_fade_in_music()
	if _take_open_store_request():
		_open_iap_shop()
	elif _take_open_shrine_request():
		_open_shrine()


func _process(_delta: float) -> void:
	if _debug_title_capture_active:
		_debug_hold_title_capture_prompt()


## While settings are open, tapping the screen does not start the game.
##
## A window is up and tapping behind it would start a run while they were
## still in settings.
func _open_settings() -> void:
	_accepting = false
	# Hide the logo and prompt. A dim cover alone lets title type overlap
	# settings rows and look messy. Learned by actually rendering it.
	$Ui/Screen.visible = false
	_settings.open()


## Open the shrine. Same rule as settings — tapping behind must not start a run.
func _open_shrine() -> void:
	_accepting = false
	$Ui/Screen.visible = false
	_shrine.open()


## View the leaderboard. Same rule as the shrine.
func _open_ladder() -> void:
	_accepting = false
	$Ui/Screen.visible = false
	_ladder.view()


## Real-money shop is separate from the shrine. Mix moon shards and cash
## prices on one screen and shards look like paid currency.
func _open_iap_shop() -> void:
	_accepting = false
	$Ui/Screen.visible = false
	_iap_shop.open()


## Direct-distribution debug APKs still check the real App Store review panel.
##
## The public shop button's storefront check is untouched. Release removes
## the caller TestLauncher from the tree, and this function is a no-op unless
## debug, so a direct-distribution build does not grow a payment path.
func debug_open_iap_store() -> void:
	if OS.is_debug_build():
		_open_iap_shop()


func debug_prepare_store_capture(request: Dictionary) -> void:
	if not OS.is_debug_build():
		return
	var kind: String = str(request.get("kind", ""))
	# Keep the title's real UI and shop feature; only freeze auto-blink on a
	# deterministic white frame. After a capture request, re-pin every
	# process frame so AnimationPlayer cannot resume or alpha drop in the
	# pre/post-screenshot observation window.
	if kind == "title":
		_debug_title_capture_active = true
		_debug_hold_title_capture_prompt()
	elif kind in ["shrine", "hero_preview"]:
		if not _shrine.visible:
			_open_shrine()
		_shrine.debug_prepare_store_capture(request)
	elif kind == "iap_review":
		if not _iap_shop.visible:
			_open_iap_shop()
		_iap_shop.debug_prepare_store_capture(request)


func _debug_hold_title_capture_prompt() -> void:
	if not OS.is_debug_build() or not _debug_title_capture_active:
		return
	if _prompt_player.is_playing():
		_prompt_player.stop()
	if not _prompt.modulate.is_equal_approx(Color.WHITE):
		_prompt.modulate = Color.WHITE


func debug_store_capture_state(request: Dictionary) -> Dictionary:
	if not OS.is_debug_build():
		return {}
	var kind: String = str(request.get("kind", ""))
	if kind == "title":
		var screen: Control = $Ui/Screen
		var title: Label = $Ui/Screen/Title
		var subtitle: Label = $Ui/Screen/Subtitle
		var settings_button: Button = $Ui/Screen/SettingsButton
		var shrine_button: Button = $Ui/Screen/ShrineButton
		var ladder_button: Button = $Ui/Screen/LadderButton
		var store_button: Button = $Ui/Screen/StoreButton
		var direct_distribution: bool = OS.has_feature("direct_distribution")
		var storefront_enabled: bool = IapStore.storefront_enabled()
		var store_button_visible: bool = store_button.is_visible_in_tree()
		var store_button_enabled: bool = not store_button.disabled
		var storefront_feature_matches: bool = storefront_enabled \
			== not direct_distribution
		var store_visibility_matches_storefront: bool = store_button_visible \
			== storefront_enabled
		var store_enabled_matches_storefront: bool = store_button_enabled \
			== storefront_enabled
		var locale: String = TranslationServer.get_locale()
		var expected_copy: Dictionary = CAPTURE_TITLE_COPY_BY_LOCALE.get(locale, {})
		var title_translation: String = tr("TITLE_NAME").strip_edges()
		var subtitle_translation: String = tr("TITLE_SUBTITLE").strip_edges()
		var tap_translation: String = tr("TAP_TO_START").strip_edges()
		var settings_translation: String = tr("SETTINGS_TITLE").strip_edges()
		var shrine_translation: String = tr("SHRINE_OPEN").strip_edges()
		var ladder_translation: String = tr("LADDER_OPEN").strip_edges()
		var store_translation: String = tr("IAP_OPEN").strip_edges()
		var title_auto_translate: bool = title.auto_translate_mode \
			!= Node.AUTO_TRANSLATE_MODE_DISABLED
		var subtitle_auto_translate: bool = subtitle.auto_translate_mode \
			!= Node.AUTO_TRANSLATE_MODE_DISABLED
		var tap_auto_translate: bool = _prompt.auto_translate_mode \
			!= Node.AUTO_TRANSLATE_MODE_DISABLED
		var settings_auto_translate: bool = settings_button.auto_translate_mode \
			!= Node.AUTO_TRANSLATE_MODE_DISABLED
		var shrine_auto_translate: bool = shrine_button.auto_translate_mode \
			!= Node.AUTO_TRANSLATE_MODE_DISABLED
		var ladder_auto_translate: bool = ladder_button.auto_translate_mode \
			!= Node.AUTO_TRANSLATE_MODE_DISABLED
		var store_auto_translate: bool = store_button.auto_translate_mode \
			!= Node.AUTO_TRANSLATE_MODE_DISABLED
		var title_copy_valid: bool = not expected_copy.is_empty() \
			and title.text == "TITLE_NAME" and title_auto_translate \
			and title_translation == str(expected_copy.get("title", "")) \
			and not title_translation.is_empty()
		var subtitle_copy_valid: bool = not expected_copy.is_empty() \
			and subtitle.text == "TITLE_SUBTITLE" and subtitle_auto_translate \
			and subtitle_translation == str(expected_copy.get("subtitle", "")) \
			and not subtitle_translation.is_empty()
		var expected_version: String = "v" + str(ProjectSettings.get_setting(
			"application/config/version", "0.0.0"))
		var screen_rect: Rect2 = screen.get_global_rect()
		var viewport_rect: Rect2 = get_viewport().get_visible_rect()
		var safe_rect: Rect2 = Screen.viewport_safe_rect(get_viewport())
		var title_inside: bool = _debug_rect_fully_inside(
			title.get_global_rect(), viewport_rect)
		var subtitle_inside: bool = _debug_rect_fully_inside(
			subtitle.get_global_rect(), viewport_rect)
		var version_inside: bool = _debug_rect_fully_inside(
			_version.get_global_rect(), viewport_rect)
		var tap_inside: bool = _debug_rect_fully_inside(
			_prompt.get_global_rect(), viewport_rect)
		var settings_inside: bool = _debug_rect_fully_inside(
			settings_button.get_global_rect(), viewport_rect)
		var shrine_inside: bool = _debug_rect_fully_inside(
			shrine_button.get_global_rect(), viewport_rect)
		var ladder_inside: bool = _debug_rect_fully_inside(
			ladder_button.get_global_rect(), viewport_rect)
		var store_inside: bool = _debug_rect_fully_inside(
			store_button.get_global_rect(), viewport_rect)
		var title_safe: bool = _debug_rect_fully_inside(
			title.get_global_rect(), safe_rect)
		var subtitle_safe: bool = _debug_rect_fully_inside(
			subtitle.get_global_rect(), safe_rect)
		var version_safe: bool = _debug_rect_fully_inside(
			_version.get_global_rect(), safe_rect)
		var tap_safe: bool = _debug_rect_fully_inside(
			_prompt.get_global_rect(), safe_rect)
		var settings_safe: bool = _debug_rect_fully_inside(
			settings_button.get_global_rect(), safe_rect)
		var shrine_safe: bool = _debug_rect_fully_inside(
			shrine_button.get_global_rect(), safe_rect)
		var ladder_safe: bool = _debug_rect_fully_inside(
			ladder_button.get_global_rect(), safe_rect)
		var store_safe: bool = _debug_rect_fully_inside(
			store_button.get_global_rect(), safe_rect)
		var safe_ui_ready: bool = title_safe and subtitle_safe \
			and version_safe and tap_safe and settings_safe \
			and shrine_safe and ladder_safe \
			and (not storefront_enabled or store_safe)
		var tap_copy_valid: bool = _prompt.text == "TAP_TO_START" \
			and tap_auto_translate \
			and tap_translation == str(expected_copy.get("tap", "")) \
			and not tap_translation.is_empty()
		var settings_copy_valid: bool = settings_button.text == "SETTINGS_TITLE" \
			and settings_auto_translate \
			and settings_translation == str(expected_copy.get("settings", "")) \
			and not settings_translation.is_empty()
		var shrine_copy_valid: bool = shrine_button.text == "SHRINE_OPEN" \
			and shrine_auto_translate \
			and shrine_translation == str(expected_copy.get("shrine", "")) \
			and not shrine_translation.is_empty()
		var ladder_copy_valid: bool = ladder_button.text == "LADDER_OPEN" \
			and ladder_auto_translate \
			and ladder_translation == str(expected_copy.get("ladder", "")) \
			and not ladder_translation.is_empty()
		var store_copy_valid: bool = store_button.text == "IAP_OPEN" \
			and store_auto_translate \
			and store_translation == str(expected_copy.get("store", "")) \
			and not store_translation.is_empty()
		var title_text_nonempty: bool = title_copy_valid \
			and not title_translation.is_empty()
		var subtitle_text_nonempty: bool = subtitle_copy_valid \
			and not subtitle_translation.is_empty()
		var version_text_nonempty: bool = _version.text == expected_version \
			and not _version.text.strip_edges().is_empty()
		var tap_text_nonempty: bool = tap_copy_valid \
			and not tap_translation.is_empty()
		var settings_text_nonempty: bool = settings_copy_valid \
			and not settings_translation.is_empty()
		var shrine_text_nonempty: bool = shrine_copy_valid \
			and not shrine_translation.is_empty()
		var ladder_text_nonempty: bool = ladder_copy_valid \
			and not ladder_translation.is_empty()
		var store_text_nonempty: bool = store_copy_valid \
			and not store_translation.is_empty()
		var title_characters_visible: bool = _debug_label_characters_visible(title)
		var subtitle_characters_visible: bool = _debug_label_characters_visible(
			subtitle)
		var version_characters_visible: bool = _debug_label_characters_visible(
			_version)
		var tap_characters_visible: bool = _debug_label_characters_visible(_prompt)
		var title_font_size_positive: bool = _debug_font_size_positive(title)
		var subtitle_font_size_positive: bool = _debug_font_size_positive(subtitle)
		var version_font_size_positive: bool = _debug_font_size_positive(_version)
		var tap_font_size_positive: bool = _debug_font_size_positive(_prompt)
		var settings_font_size_positive: bool = _debug_font_size_positive(
			settings_button)
		var shrine_font_size_positive: bool = _debug_font_size_positive(shrine_button)
		var ladder_font_size_positive: bool = _debug_font_size_positive(ladder_button)
		var store_font_size_positive: bool = _debug_font_size_positive(store_button)
		var title_font_alpha_readable: bool = _debug_label_effective_font_alpha(
			title) >= CAPTURE_TEXT_READABLE_ALPHA
		var subtitle_font_alpha_readable: bool = _debug_label_effective_font_alpha(
			subtitle) >= CAPTURE_TEXT_READABLE_ALPHA
		var version_font_alpha_readable: bool = _debug_label_effective_font_alpha(
			_version) >= CAPTURE_TEXT_READABLE_ALPHA
		var tap_font_alpha_readable: bool = _debug_label_effective_font_alpha(
			_prompt) >= CAPTURE_TEXT_READABLE_ALPHA
		var settings_font_alpha_readable: bool = _debug_button_effective_font_alpha(
			settings_button) >= CAPTURE_TEXT_READABLE_ALPHA
		var shrine_font_alpha_readable: bool = _debug_button_effective_font_alpha(
			shrine_button) >= CAPTURE_TEXT_READABLE_ALPHA
		var ladder_font_alpha_readable: bool = _debug_button_effective_font_alpha(
			ladder_button) >= CAPTURE_TEXT_READABLE_ALPHA
		var store_font_alpha_readable: bool = _debug_button_effective_font_alpha(
			store_button) >= CAPTURE_TEXT_READABLE_ALPHA
		var title_rendered_text_ready: bool = title_text_nonempty \
			and title_characters_visible and title_font_size_positive \
			and title_font_alpha_readable
		var subtitle_rendered_text_ready: bool = subtitle_text_nonempty \
			and subtitle_characters_visible and subtitle_font_size_positive \
			and subtitle_font_alpha_readable
		var version_rendered_text_ready: bool = version_text_nonempty \
			and version_characters_visible and version_font_size_positive \
			and version_font_alpha_readable
		var tap_rendered_text_ready: bool = tap_text_nonempty \
			and tap_characters_visible and tap_font_size_positive \
			and tap_font_alpha_readable
		var settings_rendered_text_ready: bool = settings_text_nonempty \
			and settings_font_size_positive and settings_font_alpha_readable
		var shrine_rendered_text_ready: bool = shrine_text_nonempty \
			and shrine_font_size_positive and shrine_font_alpha_readable
		var ladder_rendered_text_ready: bool = ladder_text_nonempty \
			and ladder_font_size_positive and ladder_font_alpha_readable
		var store_rendered_text_ready: bool = store_button_visible \
			and store_text_nonempty \
			and store_font_size_positive and store_font_alpha_readable
		var store_opaque: bool = store_button_visible \
			and _debug_effective_alpha(store_button) >= 0.99
		var tap_prompt_effective_alpha: float = _debug_effective_alpha(_prompt)
		var tap_prompt_full_alpha: bool = is_equal_approx(
			tap_prompt_effective_alpha, 1.0)
		var tap_prompt_blink_stopped: bool = not _prompt_player.is_playing()
		var tap_prompt_modulate_white: bool = _prompt.modulate.is_equal_approx(
			Color.WHITE)
		var tap_prompt_capture_locked: bool = _debug_title_capture_active \
			and tap_prompt_blink_stopped and tap_prompt_modulate_white \
			and tap_prompt_full_alpha
		var forest_ground: Sprite2D = _forest.get_node_or_null("Ground") as Sprite2D
		var forest_ground_path: String = ""
		var forest_ground_visible: bool = false
		var forest_ground_alpha: float = 0.0
		var forest_draw_rect: Rect2 = Rect2()
		if forest_ground != null:
			forest_ground_visible = forest_ground.is_visible_in_tree()
			forest_ground_alpha = _debug_effective_alpha(forest_ground)
			forest_draw_rect = _debug_sprite_draw_rect(forest_ground)
			if forest_ground.texture != null:
				forest_ground_path = forest_ground.texture.resource_path
		var forest_scene_matches: bool = _forest.scene_file_path \
			== CAPTURE_NIGHT_FOREST_SCENE
		var forest_ground_matches: bool = forest_ground_path \
			== CAPTURE_FOREST_GROUND_TEXTURE
		var forest_visible: bool = _forest.is_visible_in_tree()
		var forest_alpha: float = _debug_effective_alpha(_forest)
		var forest_draw_rect_positive: bool = _debug_rect_meaningful(
			forest_draw_rect)
		var forest_draw_rect_intersects: bool = \
			_debug_rect_meaningfully_intersects_viewport(
				forest_draw_rect, viewport_rect)
		var forest_visual_ready: bool = forest_scene_matches \
			and forest_ground_matches and forest_visible and forest_ground_visible \
			and forest_alpha >= CAPTURE_ART_OPAQUE_ALPHA \
			and forest_ground_alpha >= CAPTURE_ART_OPAQUE_ALPHA \
			and forest_draw_rect_positive and forest_draw_rect_intersects

		var vignette_texture: Texture2D = _vignette.texture
		var vignette_texture_class: String = ""
		var vignette_texture_unique_id: String = ""
		var vignette_dimensions_match: bool = false
		if vignette_texture != null:
			vignette_texture_class = vignette_texture.get_class()
			vignette_texture_unique_id = vignette_texture.resource_scene_unique_id
			if vignette_texture is GradientTexture2D:
				var gradient_texture: GradientTexture2D = \
					vignette_texture as GradientTexture2D
				vignette_dimensions_match = gradient_texture.width \
					== CAPTURE_VIGNETTE_TEXTURE_WIDTH \
					and gradient_texture.height == CAPTURE_VIGNETTE_TEXTURE_HEIGHT
		var vignette_texture_matches: bool = vignette_texture_class \
			== CAPTURE_VIGNETTE_TEXTURE_CLASS \
			and vignette_texture_unique_id == CAPTURE_VIGNETTE_TEXTURE_UNIQUE_ID \
			and vignette_dimensions_match
		var vignette_visible: bool = _vignette.is_visible_in_tree()
		var vignette_alpha: float = _debug_effective_alpha(_vignette)
		var vignette_draw_rect: Rect2 = _debug_sprite_draw_rect(_vignette)
		var vignette_draw_rect_positive: bool = _debug_rect_meaningful(
			vignette_draw_rect)
		var vignette_draw_rect_intersects: bool = \
			_debug_rect_meaningfully_intersects_viewport(
				vignette_draw_rect, viewport_rect)
		var vignette_visual_ready: bool = forest_scene_matches \
			and vignette_texture_matches and vignette_visible \
			and vignette_alpha >= CAPTURE_ART_OPAQUE_ALPHA \
			and vignette_draw_rect_positive and vignette_draw_rect_intersects

		var beacon_clearing: Sprite2D = _beacon.get_node_or_null(
			"Clearing") as Sprite2D
		var beacon_clearing_path: String = ""
		var beacon_clearing_visible: bool = false
		var beacon_clearing_alpha: float = 0.0
		var beacon_draw_rect: Rect2 = Rect2()
		if beacon_clearing != null:
			beacon_clearing_visible = beacon_clearing.is_visible_in_tree()
			beacon_clearing_alpha = _debug_effective_alpha(beacon_clearing)
			beacon_draw_rect = _debug_sprite_draw_rect(beacon_clearing)
			if beacon_clearing.texture != null:
				beacon_clearing_path = beacon_clearing.texture.resource_path
		var beacon_scene_matches: bool = _beacon.scene_file_path \
			== CAPTURE_BEACON_SCENE
		var beacon_clearing_matches: bool = beacon_clearing_path \
			== CAPTURE_BEACON_CLEARING_TEXTURE
		var beacon_visible: bool = _beacon.is_visible_in_tree()
		var beacon_alpha: float = _debug_effective_alpha(_beacon)
		var beacon_draw_rect_positive: bool = _debug_rect_meaningful(beacon_draw_rect)
		var beacon_draw_rect_intersects: bool = \
			_debug_rect_meaningfully_intersects_viewport(
				beacon_draw_rect, viewport_rect)
		var beacon_visual_ready: bool = beacon_scene_matches \
			and beacon_clearing_matches and beacon_visible \
			and beacon_clearing_visible \
			and beacon_alpha >= CAPTURE_ART_OPAQUE_ALPHA \
			and beacon_clearing_alpha >= CAPTURE_ART_OPAQUE_ALPHA \
			and beacon_draw_rect_positive and beacon_draw_rect_intersects
		var panels_closed: bool = not _settings.visible \
			and not _credits.visible and not _quit.visible \
			and not _shrine.visible and not _ladder.visible \
			and not _iap_shop.visible
		var title_state: Dictionary = {
			"scene": "title",
			"viewport_rect": _debug_rect_values(viewport_rect),
			"safe_rect": _debug_rect_values(safe_rect),
			"safe_area_inside_viewport": _debug_rect_fully_inside(
				safe_rect, viewport_rect),
			"safe_ui_ready": safe_ui_ready,
			"screen_visible": screen.is_visible_in_tree(),
			"title_visible": title.is_visible_in_tree() and title_copy_valid,
			"subtitle_visible": subtitle.is_visible_in_tree() and subtitle_copy_valid,
			"title_source_key": title.text,
			"subtitle_source_key": subtitle.text,
			"title_auto_translate": title_auto_translate,
			"subtitle_auto_translate": subtitle_auto_translate,
			"title_translation_text": title_translation,
			"subtitle_translation_text": subtitle_translation,
			"title_text_nonempty": title_text_nonempty,
			"subtitle_text_nonempty": subtitle_text_nonempty,
			"title_characters_visible": title_characters_visible,
			"subtitle_characters_visible": subtitle_characters_visible,
			"title_font_size_positive": title_font_size_positive,
			"subtitle_font_size_positive": subtitle_font_size_positive,
			"title_font_alpha_readable": title_font_alpha_readable,
			"subtitle_font_alpha_readable": subtitle_font_alpha_readable,
			"title_rendered_text_ready": title_rendered_text_ready,
			"subtitle_rendered_text_ready": subtitle_rendered_text_ready,
			"title_inside_viewport": title_inside,
			"subtitle_inside_viewport": subtitle_inside,
			"title_inside_safe_area": title_safe,
			"subtitle_inside_safe_area": subtitle_safe,
			"title_rect": _debug_rect_values(title.get_global_rect()),
			"subtitle_rect": _debug_rect_values(subtitle.get_global_rect()),
			"title_opaque": _debug_effective_alpha(title) >= 0.99,
			"subtitle_opaque": _debug_effective_alpha(subtitle) >= 0.99,
			"version_visible": _version.is_visible_in_tree() \
				and _version.text == expected_version,
			"version_text": _version.text,
			"version_text_nonempty": version_text_nonempty,
			"version_characters_visible": version_characters_visible,
			"version_font_size_positive": version_font_size_positive,
			"version_font_alpha_readable": version_font_alpha_readable,
			"version_rendered_text_ready": version_rendered_text_ready,
			"version_inside_viewport": version_inside,
			"version_inside_safe_area": version_safe,
			"version_rect": _debug_rect_values(_version.get_global_rect()),
			"version_opaque": _debug_effective_alpha(_version) >= 0.99,
			"tap_prompt_visible": _prompt.is_visible_in_tree() and tap_copy_valid,
			"tap_prompt_source_key": _prompt.text,
			"tap_prompt_auto_translate": tap_auto_translate,
			"tap_prompt_translation_text": tap_translation,
			"tap_prompt_text_nonempty": tap_text_nonempty,
			"tap_prompt_characters_visible": tap_characters_visible,
			"tap_prompt_font_size_positive": tap_font_size_positive,
			"tap_prompt_font_alpha_readable": tap_font_alpha_readable,
			"tap_prompt_rendered_text_ready": tap_rendered_text_ready,
			"tap_prompt_inside_viewport": tap_inside,
			"tap_prompt_inside_safe_area": tap_safe,
			"tap_prompt_rect": _debug_rect_values(_prompt.get_global_rect()),
			"tap_prompt_effective_alpha": tap_prompt_effective_alpha,
			"tap_prompt_full_alpha": tap_prompt_full_alpha,
			"tap_prompt_blink_stopped": tap_prompt_blink_stopped,
			"tap_prompt_modulate_white": tap_prompt_modulate_white,
			"tap_prompt_capture_locked": tap_prompt_capture_locked,
			"tap_prompt_readable_alpha": tap_prompt_full_alpha,
			"settings_button_visible": settings_button.is_visible_in_tree(),
			"settings_button_enabled": not settings_button.disabled,
			"settings_button_source_key": settings_button.text,
			"settings_button_auto_translate": settings_auto_translate,
			"settings_button_translation_text": settings_translation,
			"settings_button_inside_viewport": settings_inside,
			"settings_button_inside_safe_area": settings_safe,
			"settings_button_rect": _debug_rect_values(
				settings_button.get_global_rect()),
			"settings_button_copy_valid": settings_copy_valid,
			"settings_button_text_nonempty": settings_text_nonempty,
			"settings_button_font_size_positive": settings_font_size_positive,
			"settings_button_font_alpha_readable": settings_font_alpha_readable,
			"settings_button_rendered_text_ready": settings_rendered_text_ready,
			"settings_button_opaque": _debug_effective_alpha(settings_button) >= 0.99,
			"shrine_button_visible": shrine_button.is_visible_in_tree(),
			"shrine_button_enabled": not shrine_button.disabled,
			"shrine_button_source_key": shrine_button.text,
			"shrine_button_auto_translate": shrine_auto_translate,
			"shrine_button_translation_text": shrine_translation,
			"shrine_button_inside_viewport": shrine_inside,
			"shrine_button_inside_safe_area": shrine_safe,
			"shrine_button_rect": _debug_rect_values(
				shrine_button.get_global_rect()),
			"shrine_button_copy_valid": shrine_copy_valid,
			"shrine_button_text_nonempty": shrine_text_nonempty,
			"shrine_button_font_size_positive": shrine_font_size_positive,
			"shrine_button_font_alpha_readable": shrine_font_alpha_readable,
			"shrine_button_rendered_text_ready": shrine_rendered_text_ready,
			"shrine_button_opaque": _debug_effective_alpha(shrine_button) >= 0.99,
			"ladder_button_visible": ladder_button.is_visible_in_tree(),
			"ladder_button_enabled": not ladder_button.disabled,
			"ladder_button_source_key": ladder_button.text,
			"ladder_button_auto_translate": ladder_auto_translate,
			"ladder_button_translation_text": ladder_translation,
			"ladder_button_inside_viewport": ladder_inside,
			"ladder_button_inside_safe_area": ladder_safe,
			"ladder_button_rect": _debug_rect_values(
				ladder_button.get_global_rect()),
			"ladder_button_copy_valid": ladder_copy_valid,
			"ladder_button_text_nonempty": ladder_text_nonempty,
			"ladder_button_font_size_positive": ladder_font_size_positive,
			"ladder_button_font_alpha_readable": ladder_font_alpha_readable,
			"ladder_button_rendered_text_ready": ladder_rendered_text_ready,
			"ladder_button_opaque": _debug_effective_alpha(ladder_button) >= 0.99,
			"direct_distribution": direct_distribution,
			"storefront_enabled": storefront_enabled,
			"storefront_feature_matches": storefront_feature_matches,
			"store_button_visible": store_button_visible,
			"store_button_enabled": store_button_enabled,
			"store_button_visibility_matches_storefront": \
				store_visibility_matches_storefront,
			"store_button_enabled_matches_storefront": \
				store_enabled_matches_storefront,
			"store_button_source_key": store_button.text,
			"store_button_auto_translate": store_auto_translate,
			"store_button_translation_text": store_translation,
			"store_button_inside_viewport": store_inside,
			"store_button_inside_safe_area": store_safe,
			"store_button_rect": _debug_rect_values(
				store_button.get_global_rect()),
			"store_button_copy_valid": store_copy_valid,
			"store_button_text_nonempty": store_text_nonempty,
			"store_button_font_size_positive": store_font_size_positive,
			"store_button_font_alpha_readable": store_font_alpha_readable,
			"store_button_rendered_text_ready": store_rendered_text_ready,
			"store_button_opaque": store_opaque,
			"night_forest_node_present": _forest != null,
			"night_forest_scene_path": _forest.scene_file_path,
			"night_forest_expected_scene_path": CAPTURE_NIGHT_FOREST_SCENE,
			"night_forest_scene_matches": forest_scene_matches,
			"night_forest_visible_in_tree": forest_visible,
			"night_forest_effective_alpha": forest_alpha,
			"night_forest_opaque": forest_alpha >= CAPTURE_ART_OPAQUE_ALPHA,
			"night_forest_ground_resource_path": forest_ground_path,
			"night_forest_expected_ground_resource_path": \
				CAPTURE_FOREST_GROUND_TEXTURE,
			"night_forest_ground_resource_matches": forest_ground_matches,
			"night_forest_drawable_visible_in_tree": forest_ground_visible,
			"night_forest_drawable_effective_alpha": forest_ground_alpha,
			"night_forest_drawable_opaque": forest_ground_alpha \
				>= CAPTURE_ART_OPAQUE_ALPHA,
			"night_forest_draw_rect_positive": forest_draw_rect_positive,
			"night_forest_draw_rect_intersects_viewport": \
				forest_draw_rect_intersects,
			"night_forest_visual_ready": forest_visual_ready,
			"vignette_node_present": _vignette != null,
			"vignette_node_class": _vignette.get_class(),
			"vignette_texture_class": vignette_texture_class,
			"vignette_expected_texture_class": CAPTURE_VIGNETTE_TEXTURE_CLASS,
			"vignette_texture_unique_id": vignette_texture_unique_id,
			"vignette_expected_texture_unique_id": \
				CAPTURE_VIGNETTE_TEXTURE_UNIQUE_ID,
			"vignette_texture_dimensions_match": vignette_dimensions_match,
			"vignette_texture_matches": vignette_texture_matches,
			"vignette_visible_in_tree": vignette_visible,
			"vignette_effective_alpha": vignette_alpha,
			"vignette_opaque": vignette_alpha >= CAPTURE_ART_OPAQUE_ALPHA,
			"vignette_draw_rect_positive": vignette_draw_rect_positive,
			"vignette_draw_rect_intersects_viewport": \
				vignette_draw_rect_intersects,
			"vignette_visual_ready": vignette_visual_ready,
			"beacon_node_present": _beacon != null,
			"beacon_scene_path": _beacon.scene_file_path,
			"beacon_expected_scene_path": CAPTURE_BEACON_SCENE,
			"beacon_scene_matches": beacon_scene_matches,
			"beacon_visible_in_tree": beacon_visible,
			"beacon_effective_alpha": beacon_alpha,
			"beacon_opaque": beacon_alpha >= CAPTURE_ART_OPAQUE_ALPHA,
			"beacon_clearing_resource_path": beacon_clearing_path,
			"beacon_expected_clearing_resource_path": \
				CAPTURE_BEACON_CLEARING_TEXTURE,
			"beacon_clearing_resource_matches": beacon_clearing_matches,
			"beacon_drawable_visible_in_tree": beacon_clearing_visible,
			"beacon_drawable_effective_alpha": beacon_clearing_alpha,
			"beacon_drawable_opaque": beacon_clearing_alpha \
				>= CAPTURE_ART_OPAQUE_ALPHA,
			"beacon_draw_rect_positive": beacon_draw_rect_positive,
			"beacon_draw_rect_intersects_viewport": beacon_draw_rect_intersects,
			"beacon_visual_ready": beacon_visual_ready,
			"panels_closed": panels_closed,
			"accepting_input": _accepting,
			"screen_inside_viewport": screen_rect.size.x > 0.0 \
				and screen_rect.size.y > 0.0 \
				and viewport_rect.intersects(screen_rect),
			"drawn_after_ready": _ready_draw_frame != CAPTURE_DRAW_FRAME_UNSET \
				and Engine.get_frames_drawn() > _ready_draw_frame,
		}
		title_state["ready"] = bool(title_state["screen_visible"]) \
			and bool(title_state["title_visible"]) \
			and bool(title_state["subtitle_visible"]) \
			and bool(title_state["version_visible"]) \
			and title_rendered_text_ready and subtitle_rendered_text_ready \
			and version_rendered_text_ready \
			and title_inside and subtitle_inside and version_inside \
			and bool(title_state["title_opaque"]) \
			and bool(title_state["subtitle_opaque"]) \
			and bool(title_state["version_opaque"]) \
			and bool(title_state["tap_prompt_visible"]) \
			and tap_rendered_text_ready \
			and tap_inside and bool(title_state["tap_prompt_readable_alpha"]) \
			and bool(title_state["tap_prompt_capture_locked"]) \
			and bool(title_state["settings_button_visible"]) \
			and bool(title_state["settings_button_enabled"]) \
			and settings_inside and settings_copy_valid \
			and settings_rendered_text_ready \
			and bool(title_state["settings_button_opaque"]) \
			and bool(title_state["shrine_button_visible"]) \
			and bool(title_state["shrine_button_enabled"]) \
			and shrine_inside and shrine_copy_valid \
			and shrine_rendered_text_ready \
			and bool(title_state["shrine_button_opaque"]) \
			and bool(title_state["ladder_button_visible"]) \
			and bool(title_state["ladder_button_enabled"]) \
			and ladder_inside and ladder_copy_valid \
			and ladder_rendered_text_ready \
			and bool(title_state["ladder_button_opaque"]) \
			and storefront_feature_matches \
			and store_visibility_matches_storefront \
			and store_enabled_matches_storefront \
			and (not storefront_enabled or (store_inside and store_copy_valid \
				and store_rendered_text_ready and store_opaque)) \
			and bool(title_state["night_forest_node_present"]) \
			and forest_visual_ready \
			and bool(title_state["vignette_node_present"]) \
			and vignette_visual_ready \
			and bool(title_state["beacon_node_present"]) \
			and beacon_visual_ready \
			and bool(title_state["panels_closed"]) \
			and bool(title_state["accepting_input"]) \
			and bool(title_state["screen_inside_viewport"]) \
			and bool(title_state["safe_area_inside_viewport"]) \
			and bool(title_state["safe_ui_ready"]) \
			and bool(title_state["drawn_after_ready"])
		return title_state
	if kind in ["shrine", "hero_preview"]:
		return _shrine.debug_store_capture_state(request)
	if kind == "iap_review":
		return _iap_shop.debug_store_capture_state(request)
	return {}


func _debug_rect_fully_inside(inner: Rect2, outer: Rect2) -> bool:
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return false
	return inner.position.x >= outer.position.x - 0.5 \
		and inner.position.y >= outer.position.y - 0.5 \
		and inner.end.x <= outer.end.x + 0.5 \
		and inner.end.y <= outer.end.y + 0.5


func _debug_rect_values(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _debug_rect_meaningful(rect: Rect2) -> bool:
	return rect.size.x >= CAPTURE_ART_MIN_DRAW_SIZE \
		and rect.size.y >= CAPTURE_ART_MIN_DRAW_SIZE


func _debug_rect_meaningfully_intersects_viewport(
		draw_rect: Rect2, viewport_rect: Rect2) -> bool:
	if not _debug_rect_meaningful(draw_rect) or not viewport_rect.has_area():
		return false
	var visible_rect: Rect2 = draw_rect.intersection(viewport_rect)
	var reference_area: float = minf(
		draw_rect.get_area(), viewport_rect.get_area())
	var visible_fraction: float = visible_rect.get_area() / reference_area \
		if reference_area > 0.0 else 0.0
	return visible_rect.size.x >= CAPTURE_ART_MIN_VISIBLE_EDGE \
		and visible_rect.size.y >= CAPTURE_ART_MIN_VISIBLE_EDGE \
		and visible_fraction >= CAPTURE_ART_MIN_VISIBLE_FRACTION


func _debug_sprite_draw_rect(sprite: Sprite2D) -> Rect2:
	if sprite.texture == null:
		return Rect2()
	var local_rect: Rect2 = sprite.get_rect()
	if local_rect.size.x <= 0.0 or local_rect.size.y <= 0.0:
		return Rect2()
	var transform: Transform2D = sprite.get_global_transform_with_canvas()
	var corners: PackedVector2Array = PackedVector2Array([
		transform * local_rect.position,
		transform * Vector2(local_rect.end.x, local_rect.position.y),
		transform * local_rect.end,
		transform * Vector2(local_rect.position.x, local_rect.end.y),
	])
	var minimum: Vector2 = corners[0]
	var maximum: Vector2 = corners[0]
	for corner in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


func _debug_effective_alpha(item: CanvasItem) -> float:
	var alpha: float = 1.0
	var current: Node = item
	var own_item: bool = true
	while current != null:
		if current is CanvasItem:
			var canvas_item: CanvasItem = current as CanvasItem
			alpha *= canvas_item.modulate.a
			if own_item:
				alpha *= canvas_item.self_modulate.a
			own_item = false
		current = current.get_parent()
	return alpha


func _debug_label_characters_visible(label: Label) -> bool:
	return label.visible_characters != 0 and label.visible_ratio >= 0.999


func _debug_font_size_positive(control: Control) -> bool:
	return control.get_theme_font_size(&"font_size") > 0


func _debug_label_effective_font_alpha(label: Label) -> float:
	return _debug_effective_alpha(label) \
		* label.get_theme_color(&"font_color").a


func _debug_button_effective_font_alpha(button: Button) -> float:
	var color_name: StringName = &"font_color"
	var draw_mode: int = button.get_draw_mode()
	match draw_mode:
		BaseButton.DRAW_PRESSED:
			color_name = &"font_pressed_color"
		BaseButton.DRAW_HOVER:
			color_name = &"font_hover_color"
		BaseButton.DRAW_DISABLED:
			color_name = &"font_disabled_color"
		BaseButton.DRAW_HOVER_PRESSED:
			color_name = &"font_hover_pressed_color"
	if draw_mode == BaseButton.DRAW_NORMAL and button.has_focus():
		color_name = &"font_focus_color"
	return _debug_effective_alpha(button) \
		* button.get_theme_color(color_name).a


func _open_credits() -> void:
	_settings.visible = false
	_credits.open()


func _on_credits_closed() -> void:
	_settings.open()                             # closing credits returns to settings


func _on_panel_closed() -> void:
	$Ui/Screen.visible = true
	_accepting = true
	_refresh_shrine_badge()


## Show a number on the title shrine button only when something can be bought.
func _refresh_shrine_badge() -> void:
	var count: int = Vault.affordable_purchase_count()
	_shrine_badge.text = str(count)
	_shrine_badge.visible = count > 0


## A request that survives scene changes is deleted as soon as it is read so
## it does not linger until the next title. Used when they confirmed a
## no-balance prompt on the result screen, ended the run, then came here.
func _take_open_store_request() -> bool:
	var root: Window = get_tree().root
	if not root.has_meta(OPEN_STORE_META):
		return false
	var requested: bool = bool(root.get_meta(OPEN_STORE_META, false))
	root.remove_meta(OPEN_STORE_META)
	return requested and IapStore.storefront_enabled()


func _take_open_shrine_request() -> bool:
	var root: Window = get_tree().root
	if not root.has_meta(OPEN_SHRINE_META):
		return false
	var requested: bool = bool(root.get_meta(OPEN_SHRINE_META, false))
	root.remove_meta(OPEN_SHRINE_META)
	return requested


## Android back.
##
## `application/config/quit_on_go_back` is off, so we decide. Leave it on
## and **the app quits from any screen.** Even from settings.
##
## If a window is up, close that first. Only with nothing open do we ask
## whether to quit. Unwinding one screen at a time is what Android expects.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _credits.visible:
		_credits.close()
	elif _settings.visible:
		if not _settings.close_nested_overlay():
			_settings.close()
	# **Android back does not arrive as `ui_cancel`.** Both panels watch
	# `ui_cancel` in `_unhandled_input`, but that path does not run on device
	# (a trap already noted in `settings_panel.gd` comments).
	#
	# Miss this and back falls to `else`, **the quit dialog stacks on the
	# shrine**, and cancel makes `_on_panel_closed()` restore title UI too,
	# overlaying one screen.
	elif _shrine.visible:
		_shrine.close()
	elif _ladder.visible:
		_ladder.close()
	elif _iap_shop.visible:
		_iap_shop.close()
	elif _quit.visible:
		_quit.close()
	else:
		_accepting = false
		$Ui/Screen.visible = false
		_quit.open()


func _recenter_diorama() -> void:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var viewport_size: Vector2 = viewport_rect.size
	var offset: Vector2 = Screen.center_offset(viewport_size)
	_forest.position = offset
	_beacon.position = BEACON_POSITION + offset
	_vignette.scale = Screen.vignette_scale(viewport_size)
	var safe_rect: Rect2 = Screen.viewport_safe_rect(get_viewport())
	Screen.apply_safe_area(_screen, safe_rect, viewport_rect)
	for modal: Control in [
		_settings, _credits, _quit, _shrine, _ladder, _iap_shop,
	]:
		Screen.apply_safe_content(modal, safe_rect, viewport_rect)


func _fade_in_music() -> void:
	_bgm.volume_db = BGM_SILENCE_DB
	await get_tree().create_timer(BGM_START_DELAY_SECONDS).timeout
	if not is_inside_tree():
		return
	_bgm.play()
	var fade: Tween = create_tween()
	fade.tween_property(_bgm, "volume_db", BGM_VOLUME_DB, BGM_FADE_IN_SECONDS)


func _unhandled_input(event: InputEvent) -> void:
	if not _accepting:
		return
	if _is_start_press(event):
		request_start()


## Touch, mouse, keyboard, and gamepad all count as start.
func _is_start_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		return key.pressed and not key.echo
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false


func request_start() -> void:
	if not _accepting:
		return
	_accepting = false
	get_viewport().set_input_as_handled()

	_sfx.play()

	# Fade music first. Sound is fully down before the beacon flare ends, so
	# `music_player.gd`'s wait does not stall a scene swap.
	_fade_out_music()

	# Stop the blink and pin the prompt sharp.
	_prompt_player.stop()
	_prompt.modulate = Color.WHITE

	# The beacon flares once.
	# Wobble is still run by `beacon.tscn`'s own AnimationPlayer.
	# This overwrites it briefly; when playback ends it returns on its own.
	# `BeaconFx` sits later than the beacon in the tree, so this wins while they overlap.
	_beacon_player.play(&"flare")

	await get_tree().create_timer(FLARE_SECONDS).timeout
	# During the 0.85s wait this scene may leave the tree. Emit anyway and
	# you touch a freed instance. `_fade_in_music()` is gated for the same reason.
	if not is_inside_tree():
		return
	start_requested.emit()


func _fade_out_music() -> void:
	var fade: Tween = create_tween()
	fade.tween_property(_bgm, "volume_db", BGM_SILENCE_DB, BGM_FADE_OUT_SECONDS)
	await fade.finished
	if not is_inside_tree():
		return
	_bgm.release()
	_sfx.release()


func _enter_arena() -> void:
	# Emitter and receiver are split on purpose. Same file, so a direct
	# function call would work, but then the title would know the arena comes
	# next. Chapter 9 gave that job to the arena; the title keeps this one
	# line. Tell the arena this run was started by a person. The story
	# dialogue that opens a run appears only then.
	RunEntry.mark_from_title()
	get_tree().change_scene_to_file(ARENA_SCENE)
