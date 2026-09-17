extends Node

## Title lower-right version label and localized-layout regression.

const TITLE_SCENE: PackedScene = preload("res://scenes/menus/title_menu.tscn")
const FOREST_FLOOR_TEXTURE: Texture2D = preload(
	"res://assets/custom/world/terrain/forest_floor.png")
const BEACON_CLEARING_TEXTURE: Texture2D = preload(
	"res://assets/custom/world/beacon/clearing.png")
const RELEASE_LOCALES: PackedStringArray = ["en", "ja", "ko", "zh_CN", "zh_TW"]
const BUTTON_FONT_COLOR_NAMES: Array[StringName] = [
	&"font_color",
	&"font_pressed_color",
	&"font_hover_color",
	&"font_disabled_color",
	&"font_hover_pressed_color",
	&"font_focus_color",
]
const TITLE_CAPTURE_COPY: Dictionary = {
	"ko": ["달빛 봉화", "밤을 밝히는 마지막 불빛", "화면을 탭하여 시작", "설정", "제단", "순위", "상점"],
	"en": ["MOONLIT BEACON", "OUTLAST THE NIGHT", "Tap to start", "Settings", "Shrine", "Ranks", "Store"],
	"ja": ["月明かりの烽火", "夜を照らす最後の灯", "画面をタップして開始", "設定", "祭壇", "順位", "ストア"],
	"zh_CN": ["月光烽火", "照亮长夜的最后火光", "点击屏幕开始", "设置", "祭坛", "排名", "商店"],
	"zh_TW": ["月光烽火", "照亮長夜的最後火光", "點擊畫面開始", "設定", "祭壇", "排名", "商店"],
}

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return

	await _test_version_in_every_locale()
	if _failed > 0:
		printerr("title-version test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("title-version test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("title-version test aborted: user:// path is not isolated — ", user_root)
	return safe


func _test_version_in_every_locale() -> void:
	_test_safe_area_math()
	var previous_locale: String = TranslationServer.get_locale()
	var project_version: String = str(ProjectSettings.get_setting(
		"application/config/version", "0.0.0"))
	var expected_text: String = "v" + project_version
	var splash_path: String = str(ProjectSettings.get_setting(
		"application/boot_splash/image", ""))
	_expect_true(
		bool(ProjectSettings.get_setting("application/boot_splash/show_image", false)),
		"shows the custom boot splash instead of the Godot default logo")
	_expect_equal(
		splash_path,
		"res://assets/custom/ui/boot_splash.png",
		"ship boot-splash path")
	_expect_true(ResourceLoader.exists(splash_path), "custom boot-splash resource exists")
	_expect_true(
		int(ProjectSettings.get_setting(
			"application/boot_splash/minimum_display_time", 0)) <= 700,
		"boot splash does not block play for long")

	for locale in RELEASE_LOCALES:
		TranslationServer.set_locale(locale)
		var title: Control = TITLE_SCENE.instantiate() as Control
		add_child(title)
		await get_tree().process_frame
		_test_modal_safe_content(title, locale)

		var label: Label = title.get_node("Ui/Screen/Version") as Label
		var label_rect: Rect2 = label.get_global_rect()
		var viewport_rect: Rect2 = title.get_viewport_rect()
		_expect_equal(label.text, expected_text, locale + " project version label")
		_expect_true(label.is_visible_in_tree(), locale + " version label shown")
		_expect_true(
			label_rect.position.x >= viewport_rect.size.x * 0.75,
			locale + " version label on the right")
		_expect_true(
			label_rect.position.y >= viewport_rect.size.y * 0.8,
			locale + " version label at the bottom")
		_expect_true(
			label_rect.end.x <= viewport_rect.end.x + 0.01
				and label_rect.end.y <= viewport_rect.end.y + 0.01,
			locale + " version label inside the screen")
		await _test_title_capture_contract(title, locale)

		title.queue_free()
		await get_tree().process_frame

	TranslationServer.set_locale(previous_locale)


func _test_safe_area_math() -> void:
	var full: Rect2 = Rect2(0.0, 0.0, 808.0, 360.0)
	var platform: Rect2 = Rect2(12.0, 20.0, 784.0, 320.0)
	var safe: Rect2 = Screen.safe_rect(full, platform, 28.0)
	_expect_true(
		safe.is_equal_approx(Rect2(28.0, 28.0, 752.0, 304.0)),
		"OS safe area intersects mobile edge margin")
	var ignored_bad_platform: Rect2 = Screen.safe_rect(
		full, Rect2(400.0, 170.0, 8.0, 8.0), 28.0)
	_expect_true(
		ignored_bad_platform.is_equal_approx(
			Rect2(28.0, 28.0, 752.0, 304.0)),
		"rejects an abnormally small OS safe-area report")
	var mobile_three_x: Rect2 = Screen.safe_rect(
		full, Rect2(), Screen.MOBILE_EDGE_INSET_PIXELS / 3.0)
	_expect_true(
		mobile_three_x.is_equal_approx(Rect2(
			34.0 / 3.0, 34.0 / 3.0,
			808.0 - 68.0 / 3.0, 360.0 - 68.0 / 3.0)),
		"iOS/Android 3× screens still keep a physical 34px minimum margin")

	var full_control: Control = Control.new()
	full_control.anchor_right = 1.0
	full_control.anchor_bottom = 1.0
	Screen.apply_safe_area(full_control, safe, full)
	_expect_true(
		Vector4(
			full_control.offset_left, full_control.offset_top,
			full_control.offset_right, full_control.offset_bottom
		).is_equal_approx(Vector4(28.0, 28.0, -28.0, -28.0)),
		"shrinks fullscreen UI to the safe area")

	var dash: Control = Control.new()
	dash.anchor_left = 1.0
	dash.anchor_top = 1.0
	dash.anchor_right = 1.0
	dash.anchor_bottom = 1.0
	dash.offset_left = -66.0
	dash.offset_top = -66.0
	dash.offset_right = -14.0
	dash.offset_bottom = -14.0
	Screen.apply_safe_area(dash, safe, full)
	var first_offsets: Vector4 = Vector4(
		dash.offset_left, dash.offset_top, dash.offset_right, dash.offset_bottom)
	_expect_true(
		first_offsets.is_equal_approx(Vector4(-94.0, -94.0, -42.0, -42.0)),
		"moves the lower-right dash button inside the gesture region")
	Screen.apply_safe_area(dash, safe, full)
	_expect_true(
		Vector4(
			dash.offset_left, dash.offset_top,
			dash.offset_right, dash.offset_bottom
		).is_equal_approx(first_offsets),
		"safe-area offset is not cumulative when the screen size is recomputed")
	full_control.free()
	dash.free()


func _test_modal_safe_content(title: Control, locale: String) -> void:
	var full: Rect2 = title.get_viewport().get_visible_rect()
	# Converted from a 1024×600 Android tablet's real 34px gesture inset into internal coords,
	# a bit tighter than that, so a 1px overflow on a small screen is caught.
	var safe: Rect2 = full.grow(-12.0)
	for path in [
		"Ui/Settings", "Ui/Credits", "Ui/Quit", "Ui/Shrine",
		"Ui/Ladder", "Ui/IapShop",
	]:
		var modal: Control = title.get_node(path) as Control
		Screen.apply_safe_content(modal, safe, full)
		_expect_true(
			modal.get_global_rect().is_equal_approx(full),
			locale + " " + path + " modal root stays fullscreen")
		var dim: Control = modal.get_node("Dim") as Control
		_expect_true(
			dim.get_global_rect().is_equal_approx(full),
			locale + " " + path + " dim background stays fullscreen")

	var settings: Control = title.get_node("Ui/Settings") as Control
	for node: Node in settings.get_children():
		if node is Control and node.name != &"Dim":
			_expect_true(
				_rect_fully_inside((node as Control).get_global_rect(), safe),
				locale + " settings content safe area " + str(node.name))
	var credits: Control = title.get_node("Ui/Credits") as Control
	for node: Node in credits.get_children():
		if node is Control and node.name != &"Dim":
			_expect_true(
				_rect_fully_inside((node as Control).get_global_rect(), safe),
				locale + " credits content safe area " + str(node.name))

	for path in [
		"Ui/Shrine/Frame", "Ui/Shrine/HeroPreview/Frame",
		"Ui/IapShop/Frame", "Ui/IapShop/HeroPreview/Frame",
	]:
		var content: Control = title.get_node(path) as Control
		_expect_true(
			_rect_fully_inside(content.get_global_rect(), safe),
			locale + " modal frame safe area " + path)

	# Later capture-contract checks run after restoring the live runtime safe area.
	title.call("_recenter_diorama")


func _rect_fully_inside(rect: Rect2, boundary: Rect2) -> bool:
	const EPSILON: float = 0.01
	return rect.has_area() \
		and rect.position.x >= boundary.position.x - EPSILON \
		and rect.position.y >= boundary.position.y - EPSILON \
		and rect.end.x <= boundary.end.x + EPSILON \
		and rect.end.y <= boundary.end.y + EPSILON


func _test_title_capture_contract(title: Control, locale: String) -> void:
	var prepared_store: Button = title.get_node("Ui/Screen/StoreButton") as Button
	var prompt: Label = title.get_node("Ui/Screen/TapPrompt") as Label
	var prompt_player: AnimationPlayer = title.get_node(
		"Ui/Screen/PromptBlink") as AnimationPlayer
	var expected_direct_distribution: bool = OS.has_feature("direct_distribution")
	var expected_storefront: bool = IapStore.storefront_enabled()
	_expect_true(prompt_player.is_playing(), locale + " normal title start-hint blink")
	_expect_equal(
		prompt_player.current_animation, "blink",
		locale + " normal title blink animation")
	_expect_equal(
		prepared_store.visible, expected_storefront,
		locale + " shop button shown for product feature")
	_expect_equal(
		not prepared_store.disabled, expected_storefront,
		locale + " shop button enabled for product feature")
	# Confirm capture prep does not synthesize hidden buttons by injecting the opposite state, then
	# Restore the live product state.
	prepared_store.visible = not expected_storefront
	prepared_store.disabled = expected_storefront
	title.call("debug_prepare_store_capture", {"kind": "title"})
	_expect_equal(
		prepared_store.visible, not expected_storefront,
		locale + " capture prep does not change shop visibility")
	_expect_equal(
		prepared_store.disabled, expected_storefront,
		locale + " capture prep does not change shop enabled state")
	prepared_store.visible = expected_storefront
	prepared_store.disabled = not expected_storefront
	title.call("debug_prepare_store_capture", {"kind": "title"})
	_expect_equal(
		prepared_store.visible, expected_storefront,
		locale + " real shop stays shown after capture prep")
	_expect_equal(
		not prepared_store.disabled, expected_storefront,
		locale + " real shop stays enabled after capture prep")
	_expect_true(
		not prompt_player.is_playing(),
		locale + " capture prep stops start-hint blink")
	_expect_true(
		prompt.modulate.is_equal_approx(Color.WHITE),
		locale + " capture prep locks start hint to opaque white")
	# The dummy headless renderer has no draw counter, so model the previous draw serial as -1.
	# Product runtime records only the real Engine draw serial in _ready.
	title.set("_ready_draw_frame", -1)
	var state: Dictionary = title.call(
		"debug_store_capture_state", {"kind": "title"})
	for _frame in range(8):
		if bool(state.get("drawn_after_ready", false)):
			break
		await get_tree().process_frame
		state = title.call("debug_store_capture_state", {"kind": "title"})
	var copy: Array = TITLE_CAPTURE_COPY[locale]
	_expect_true(bool(state.get("ready", false)), locale + " title capture ready")
	_expect_equal(state.get("title_translation_text"), copy[0], locale + " title real translation")
	_expect_equal(state.get("subtitle_translation_text"), copy[1], locale + " subtitle real translation")
	_expect_equal(state.get("tap_prompt_translation_text"), copy[2], locale + " start hint real translation")
	_expect_equal(state.get("settings_button_translation_text"), copy[3], locale + " settings real translation")
	_expect_equal(state.get("shrine_button_translation_text"), copy[4], locale + " shrine real translation")
	_expect_equal(state.get("ladder_button_translation_text"), copy[5], locale + " ladder real translation")
	_expect_equal(state.get("store_button_translation_text"), copy[6], locale + " shop real translation")
	_expect_equal(
		state.get("direct_distribution"), expected_direct_distribution,
		locale + " direct-distribute feature proof")
	_expect_equal(
		state.get("storefront_enabled"), expected_storefront,
		locale + " storefront feature proof")
	_expect_equal(
		state.get("store_button_visible"), expected_storefront,
		locale + " actual shop-button visibility proof")
	_expect_equal(
		state.get("store_button_enabled"), expected_storefront,
		locale + " actual shop-button enabled proof")
	for field in [
		"safe_area_inside_viewport", "safe_ui_ready",
		"storefront_feature_matches",
		"store_button_visibility_matches_storefront",
		"store_button_enabled_matches_storefront",
		"title_text_nonempty", "title_characters_visible",
		"title_font_size_positive", "title_font_alpha_readable",
		"title_rendered_text_ready",
		"subtitle_text_nonempty", "subtitle_characters_visible",
		"subtitle_font_size_positive", "subtitle_font_alpha_readable",
		"subtitle_rendered_text_ready",
		"version_text_nonempty", "version_characters_visible",
		"version_font_size_positive", "version_font_alpha_readable",
		"version_rendered_text_ready",
		"tap_prompt_text_nonempty", "tap_prompt_characters_visible",
		"tap_prompt_font_size_positive", "tap_prompt_font_alpha_readable",
		"tap_prompt_rendered_text_ready", "tap_prompt_blink_stopped",
		"tap_prompt_full_alpha", "tap_prompt_modulate_white",
		"tap_prompt_capture_locked",
		"settings_button_text_nonempty", "settings_button_font_size_positive",
		"settings_button_font_alpha_readable",
		"settings_button_rendered_text_ready",
		"shrine_button_text_nonempty", "shrine_button_font_size_positive",
		"shrine_button_font_alpha_readable",
		"shrine_button_rendered_text_ready",
		"ladder_button_text_nonempty", "ladder_button_font_size_positive",
		"ladder_button_font_alpha_readable",
		"ladder_button_rendered_text_ready",
		"store_button_text_nonempty", "store_button_font_size_positive",
		"store_button_font_alpha_readable",
		"title_inside_viewport", "subtitle_inside_viewport", "version_inside_viewport",
		"title_inside_safe_area", "subtitle_inside_safe_area",
		"version_inside_safe_area", "tap_prompt_inside_safe_area",
		"settings_button_inside_safe_area", "shrine_button_inside_safe_area",
		"ladder_button_inside_safe_area", "store_button_inside_safe_area",
		"title_opaque", "subtitle_opaque", "version_opaque",
		"tap_prompt_inside_viewport", "tap_prompt_readable_alpha",
		"settings_button_inside_viewport", "settings_button_opaque",
		"shrine_button_inside_viewport", "shrine_button_opaque",
		"ladder_button_inside_viewport", "ladder_button_opaque",
		"store_button_inside_viewport", "store_button_copy_valid",
		"night_forest_node_present", "night_forest_scene_matches",
		"night_forest_visible_in_tree",
		"night_forest_opaque", "night_forest_ground_resource_matches",
		"night_forest_drawable_visible_in_tree", "night_forest_drawable_opaque",
		"night_forest_draw_rect_positive",
		"night_forest_draw_rect_intersects_viewport", "night_forest_visual_ready",
		"vignette_node_present", "vignette_texture_dimensions_match",
		"vignette_texture_matches",
		"vignette_visible_in_tree", "vignette_opaque",
		"vignette_draw_rect_positive", "vignette_draw_rect_intersects_viewport",
		"vignette_visual_ready",
		"beacon_node_present", "beacon_scene_matches",
		"beacon_visible_in_tree", "beacon_opaque",
		"beacon_clearing_resource_matches", "beacon_drawable_visible_in_tree",
		"beacon_drawable_opaque", "beacon_draw_rect_positive",
		"beacon_draw_rect_intersects_viewport", "beacon_visual_ready",
	]:
		_expect_true(bool(state.get(field, false)), locale + " " + field)
	_expect_equal(
		state.get("store_button_rendered_text_ready"), expected_storefront,
		locale + " actual shop-button render proof")
	_expect_equal(
		state.get("store_button_opaque"), expected_storefront,
		locale + " actual shop-button opaque proof")
	for rect_field in [
		"viewport_rect", "safe_rect", "title_rect", "subtitle_rect",
		"version_rect", "tap_prompt_rect", "settings_button_rect",
		"shrine_button_rect", "ladder_button_rect", "store_button_rect",
	]:
		var values: Array = state.get(rect_field, []) as Array
		_expect_equal(values.size(), 4, locale + " " + rect_field + " coordinate proof")
	_expect_true(
		float(state.get("night_forest_effective_alpha", 0.0)) >= 0.99,
		locale + " forest root valid alpha")
	_expect_true(
		float(state.get("night_forest_drawable_effective_alpha", 0.0)) >= 0.99,
		locale + " forest drawable valid alpha")
	_expect_true(
		float(state.get("vignette_effective_alpha", 0.0)) >= 0.99,
		locale + " vignette valid alpha")
	_expect_true(
		float(state.get("beacon_effective_alpha", 0.0)) >= 0.99,
		locale + " beacon root valid alpha")
	_expect_true(
		float(state.get("beacon_drawable_effective_alpha", 0.0)) >= 0.99,
		locale + " beacon drawable valid alpha")
	_expect_equal(
		state.get("night_forest_scene_path"),
		"res://scenes/gameplay/night_forest.tscn",
		locale + " forest scene resource")
	_expect_equal(
		state.get("night_forest_ground_resource_path"),
		"res://assets/custom/world/terrain/forest_floor.png",
		locale + " forest floor resource")
	_expect_equal(
		state.get("vignette_node_class"), "Sprite2D", locale + " vignette node type")
	_expect_equal(
		state.get("vignette_texture_class"),
		"GradientTexture2D",
		locale + " vignette texture type")
	_expect_equal(
		state.get("vignette_texture_unique_id"),
		"GradientTexture2D_vignette",
		locale + " vignette texture unique ID")
	_expect_equal(
		state.get("beacon_scene_path"),
		"res://scenes/objectives/beacon.tscn",
		locale + " beacon scene resource")
	_expect_equal(
		state.get("beacon_clearing_resource_path"),
		"res://assets/custom/world/beacon/clearing.png",
		locale + " beacon floor resource")
	_expect_true(
		is_equal_approx(
			float(state.get("tap_prompt_effective_alpha", 0.0)), 1.0),
		locale + " start hint capture alpha 1")

	var title_label: Label = title.get_node("Ui/Screen/Title") as Label
	var subtitle: Label = title.get_node("Ui/Screen/Subtitle") as Label
	var version: Label = title.get_node("Ui/Screen/Version") as Label
	var settings: Button = title.get_node("Ui/Screen/SettingsButton") as Button
	var shrine: Button = title.get_node("Ui/Screen/ShrineButton") as Button
	var ladder: Button = title.get_node("Ui/Screen/LadderButton") as Button
	var store: Button = title.get_node("Ui/Screen/StoreButton") as Button
	var original_title_position: Vector2 = title_label.position
	title_label.position += Vector2(2000.0, 0.0)
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(not bool(state.get("title_inside_viewport", true)), locale + " rejects off-screen title")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for off-screen title")
	title_label.position = original_title_position

	var original_subtitle_text: String = subtitle.text
	subtitle.text = "TITLE_NAME"
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(not bool(state.get("subtitle_visible", true)), locale + " rejects wrong subtitle key")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for wrong subtitle key")
	subtitle.text = original_subtitle_text

	var original_auto_translate: int = title_label.auto_translate_mode
	title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(not bool(state.get("title_auto_translate", true)), locale + " rejects title auto-translate off")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready with title auto-translate off")
	title_label.auto_translate_mode = original_auto_translate

	var original_prompt_modulate: Color = prompt.modulate
	# The old 0.35 readability threshold would pass, but explicitly reject store-source-dim alpha 0.5.
	# Capture prep requires exactly 1.0.
	prompt.modulate.a = 0.5
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("tap_prompt_readable_alpha", true)),
		locale + " rejects translucent start hint")
	_expect_true(
		not bool(state.get("tap_prompt_modulate_white", true)),
		locale + " rejects translucent start-hint white-lock proof")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for translucent start hint")
	prompt.modulate = original_prompt_modulate

	# After capture emits ready once, even if AnimationPlayer resumes, the next process
	# must immediately stop again and restore white alpha 1 so before/after screenshots are the same scene.
	prompt_player.play(&"blink")
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("tap_prompt_blink_stopped", true)),
		locale + " rejects resumed start-hint blink proof")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready after blink resumes")
	# This contract checks the work TitleMenu._process itself must do every frame.
	# Waiting for process_frame right after resuming AnimationPlayer in headless can hang
	# the low-power main loop forever, so run the same callback once directly.
	title.call("_process", 0.0)
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		bool(state.get("tap_prompt_capture_locked", false)),
		locale + " start hint re-locked during capture watch")
	_expect_true(not prompt_player.is_playing(), locale + " blink stays stopped during capture watch")
	_expect_true(
		prompt.modulate.is_equal_approx(Color.WHITE),
		locale + " white alpha 1 held during capture watch")

	var original_settings_disabled: bool = settings.disabled
	settings.disabled = true
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(not bool(state.get("settings_button_enabled", true)), locale + " rejects disabled settings button")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for disabled settings button")
	settings.disabled = original_settings_disabled

	var original_store_visible: bool = store.visible
	store.visible = false
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("store_button_visible", true)),
		locale + " rejects hidden shop button")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for hidden shop button")
	store.visible = original_store_visible

	var original_store_disabled: bool = store.disabled
	store.disabled = true
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("store_button_enabled", true)),
		locale + " rejects disabled shop button")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for disabled shop button")
	store.disabled = original_store_disabled

	var original_store_text: String = store.text
	store.text = "SETTINGS_TITLE"
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("store_button_copy_valid", true)),
		locale + " rejects wrong shop copy")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for wrong shop copy")
	store.text = original_store_text

	var original_title_characters: int = title_label.visible_characters
	title_label.visible_characters = 0
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("title_characters_visible", true)),
		locale + " rejects title with visible_characters=0")
	_expect_true(
		not bool(state.get("title_rendered_text_ready", true)),
		locale + " rejects hidden-character title render")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for hidden-character title")
	title_label.visible_characters = original_title_characters

	var original_subtitle_characters: int = subtitle.visible_characters
	var original_subtitle_ratio: float = subtitle.visible_ratio
	subtitle.visible_ratio = 0.0
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("subtitle_characters_visible", true)),
		locale + " rejects subtitle with visible_ratio=0")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for hidden-character subtitle")
	_restore_label_visibility(
		subtitle, original_subtitle_characters, original_subtitle_ratio)

	var original_prompt_characters: int = prompt.visible_characters
	prompt.visible_characters = 0
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("tap_prompt_characters_visible", true)),
		locale + " rejects start hint with visible_characters=0")
	_expect_true(
		not bool(state.get("ready", true)),
		locale + " rejects ready for hidden-character start hint")
	prompt.visible_characters = original_prompt_characters

	for pair in [
		[version, "version_font_alpha_readable", "version"],
		[settings, "settings_button_font_alpha_readable", "Settings button"],
		[shrine, "shrine_button_font_alpha_readable", "Shrine button"],
		[ladder, "ladder_button_font_alpha_readable", "Ladder button"],
		[store, "store_button_font_alpha_readable", "Shop button"],
	]:
		var target: Control = pair[0] as Control
		var field: String = str(pair[1])
		var color_names: Array[StringName] = []
		if target is Label:
			color_names.append(&"font_color")
		else:
			color_names.assign(BUTTON_FONT_COLOR_NAMES)
		var snapshots: Array[Dictionary] = _make_font_transparent(
			target, color_names)
		state = title.call("debug_store_capture_state", {"kind": "title"})
		_expect_true(
			not bool(state.get(field, true)),
			locale + " font alpha=0 " + str(pair[2]) + " rejected")
		_expect_true(
			not bool(state.get("ready", true)),
			locale + " transparent glyphs " + str(pair[2]) + " ready rejected")
		_restore_font_colors(target, snapshots)

	var forest: Node2D = title.get_node("NightForest") as Node2D
	var forest_ground: Sprite2D = title.get_node("NightForest/Ground") as Sprite2D
	var vignette: Sprite2D = title.get_node("NightForest/Vignette") as Sprite2D
	var beacon: Node2D = title.get_node("Beacon") as Node2D
	var beacon_clearing: Sprite2D = title.get_node("Beacon/Clearing") as Sprite2D
	var art_viewport_rect: Rect2 = title.get_viewport().get_visible_rect()

	forest.visible = false
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("night_forest_visible_in_tree", true)),
		locale + " rejects hidden forest art")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for hidden forest art")
	forest.visible = true

	var original_forest_modulate: Color = forest.modulate
	forest.modulate.a = 0.0
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("night_forest_opaque", true)),
		locale + " rejects transparent forest art")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for transparent forest art")
	forest.modulate = original_forest_modulate

	var original_forest_texture: Texture2D = forest_ground.texture
	forest_ground.texture = BEACON_CLEARING_TEXTURE
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("night_forest_ground_resource_matches", true)),
		locale + " rejects wrong forest art resource")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for wrong forest art")
	forest_ground.texture = original_forest_texture

	var original_forest_ground_position: Vector2 = forest_ground.position
	var forest_draw_rect: Rect2 = title.call(
		"_debug_sprite_draw_rect", forest_ground) as Rect2
	forest_ground.position.x += art_viewport_rect.end.x \
		- forest_draw_rect.position.x - 0.5
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		bool(state.get("night_forest_draw_rect_positive", false)),
		locale + " forest edge sliver still has positive source draw size")
	_expect_true(
		not bool(state.get("night_forest_draw_rect_intersects_viewport", true)),
		locale + " rejects a sub-1px forest edge sliver")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for forest edge sliver")
	forest_ground.position = original_forest_ground_position

	vignette.visible = false
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("vignette_visible_in_tree", true)),
		locale + " rejects hidden vignette")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for hidden vignette")
	vignette.visible = true

	var original_vignette_modulate: Color = vignette.modulate
	vignette.modulate.a = 0.0
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("vignette_opaque", true)),
		locale + " rejects transparent vignette")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for transparent vignette")
	vignette.modulate = original_vignette_modulate

	var original_vignette_texture: Texture2D = vignette.texture
	vignette.texture = FOREST_FLOOR_TEXTURE
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("vignette_texture_matches", true)),
		locale + " rejects wrong vignette resource")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for wrong vignette")
	vignette.texture = original_vignette_texture

	var original_vignette_position: Vector2 = vignette.position
	var vignette_draw_rect: Rect2 = title.call(
		"_debug_sprite_draw_rect", vignette) as Rect2
	vignette.position.x += art_viewport_rect.end.x \
		- vignette_draw_rect.position.x - 0.5
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		bool(state.get("vignette_draw_rect_positive", false)),
		locale + " vignette edge sliver still has positive source draw size")
	_expect_true(
		not bool(state.get("vignette_draw_rect_intersects_viewport", true)),
		locale + " rejects a sub-1px vignette edge sliver")
	_expect_true(
		not bool(state.get("ready", true)),
		locale + " rejects ready for vignette edge sliver")
	vignette.position = original_vignette_position

	beacon.visible = false
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("beacon_visible_in_tree", true)),
		locale + " rejects hidden beacon art")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for hidden beacon")
	beacon.visible = true

	var original_beacon_modulate: Color = beacon.modulate
	beacon.modulate.a = 0.0
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("beacon_opaque", true)),
		locale + " rejects transparent beacon art")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for transparent beacon")
	beacon.modulate = original_beacon_modulate

	var original_beacon_texture: Texture2D = beacon_clearing.texture
	beacon_clearing.texture = FOREST_FLOOR_TEXTURE
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		not bool(state.get("beacon_clearing_resource_matches", true)),
		locale + " rejects wrong beacon art resource")
	_expect_true(not bool(state.get("ready", true)), locale + " rejects ready for wrong beacon art")
	beacon_clearing.texture = original_beacon_texture

	var original_beacon_clearing_position: Vector2 = beacon_clearing.position
	var beacon_draw_rect: Rect2 = title.call(
		"_debug_sprite_draw_rect", beacon_clearing) as Rect2
	beacon_clearing.position.x += art_viewport_rect.end.x \
		- beacon_draw_rect.position.x - 0.5
	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(
		bool(state.get("beacon_draw_rect_positive", false)),
		locale + " beacon edge sliver still has positive source draw size")
	_expect_true(
		not bool(state.get("beacon_draw_rect_intersects_viewport", true)),
		locale + " rejects a sub-1px beacon edge sliver")
	_expect_true(
		not bool(state.get("ready", true)),
		locale + " rejects ready for beacon edge sliver")
	beacon_clearing.position = original_beacon_clearing_position

	state = title.call("debug_store_capture_state", {"kind": "title"})
	_expect_true(bool(state.get("ready", false)), locale + " title counterexample then restore state")


func _restore_label_visibility(
		label: Label, characters: int, ratio: float) -> void:
	label.visible_characters = characters
	if characters >= 0:
		label.visible_ratio = ratio


func _make_font_transparent(
		control: Control, color_names: Array[StringName]) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for color_name in color_names:
		var color: Color = control.get_theme_color(color_name)
		snapshots.append({
			"name": color_name,
			"overridden": control.has_theme_color_override(color_name),
			"color": color,
		})
		color.a = 0.0
		control.add_theme_color_override(color_name, color)
	return snapshots


func _restore_font_colors(
		control: Control, snapshots: Array[Dictionary]) -> void:
	for snapshot in snapshots:
		var color_name: StringName = snapshot["name"]
		var color: Color = snapshot["color"]
		if bool(snapshot["overridden"]):
			control.add_theme_color_override(color_name, color)
		else:
			control.remove_theme_color_override(color_name)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
