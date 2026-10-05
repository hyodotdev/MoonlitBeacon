extends Node

## Production title capture: the entry forwards the visible title's proof.
##
## Boots the real production entry (original Title plus Gate) behind a
## logged-out stub host. The entry's title state must be the Title child's
## full state — version text, layout, live copy and art proofs — plus
## namespaced gate context, and an open card, loader or gate panel must
## reject `ready` instead of claiming a clean title underneath. Covers the
## fields the Node title consumer requires, prompt freeze across
## observations, locale copy, actual version mismatch and occlusion.

const PRODUCTION_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")
const ARENA_PATH: String = "res://scenes/gameplay/arena.tscn"
const TITLE_CAPTURE_COPY: Dictionary = {
	"ko": ["달빛 봉화", "밤을 밝히는 마지막 불빛", "화면을 탭하여 시작", "설정", "제단", "순위", "상점"],
	"en": ["MOONLIT BEACON", "OUTLAST THE NIGHT", "Tap to start", "Settings", "Shrine", "Ranks", "Store"],
	"ja": ["月明かりの烽火", "夜を照らす最後の灯", "画面をタップして開始", "設定", "祭壇", "順位", "ストア"],
	"zh_CN": ["月光烽火", "照亮长夜的最后火光", "点击屏幕开始", "设置", "祭坛", "排名", "商店"],
	"zh_TW": ["月光烽火", "照亮長夜的最後火光", "點擊畫面開始", "設定", "祭壇", "排名", "商店"],
}
const CHECK_LOCALES: PackedStringArray = ["en", "ko"]

var _failed: int = 0
var _checked: int = 0


## Logged-out stub with a controllable host-ready flag, so the test can
## prove the host flag never overwrites the title's own `ready`.
class StubCaptureHost extends Node:
	signal production_changed(state: Dictionary)
	signal production_conflict(local: Dictionary, cloud: Dictionary)
	signal production_error(error: Dictionary)

	var host_ready: bool = false

	func startup() -> void:
		pass

	func providers_for_entry() -> Array:
		return []

	func identity_for_entry() -> Dictionary:
		return {"stable_id": ""}

	func account_state() -> Dictionary:
		return {"offline": false}

	func saved_gate_summary() -> Dictionary:
		return {"has_save": false}

	func provider_label(provider_id: String) -> String:
		return provider_id

	func note_first_paint() -> void:
		pass

	func release_entry_hold() -> void:
		pass

	func cancel_entry_plan() -> void:
		pass

	func debug_production_state() -> Dictionary:
		return {"started": true, "ready": host_ready, "source": "stub"}


func _ready() -> void:
	get_tree().root.size = Vector2i(808, 360)
	_run.call_deferred()


func _run() -> void:
	var previous_locale: String = TranslationServer.get_locale()
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubCaptureHost.new()
	add_child(stub)
	production.set_host_override(stub)
	add_child(production)
	await _frames(4)
	var title: Control = production.get_node("Title") as Control
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	_expect_true(gate.is_title_rest(), "first: gate parked for the title")
	_expect_true(not gate.is_selection_open(), "first: no selection")
	# The dummy headless renderer has no draw counter, so model the
	# previous draw serial as -1 like the title suite does.
	title.set("_ready_draw_frame", -1)
	_check_clean_forwards(production, title, gate, stub)
	_check_prompt_freeze(production, title)
	_check_host_ready_not_overwriting(production, stub)
	await _check_locales(production, title)
	_check_version_mismatch(production, title)
	await _check_gate_panel_occlusion(production, gate)
	await _check_selection_occlusion(production, gate)
	await _check_loader_occlusion(production, gate)
	TranslationServer.set_locale(previous_locale)
	production.queue_free()
	stub.queue_free()
	await _frames(2)
	if _failed > 0:
		printerr("production-title-capture test failed — ",
			_failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("production-title-capture test passed — ", _checked, " case(s)")
	get_tree().quit(0)


## A clean entry reports the Title child's full state plus namespaced gate
## context, with every field the Node title consumer requires present.
func _check_clean_forwards(production: ProductionEntry, title: Control,
		gate: GateEntry, stub: StubCaptureHost) -> void:
	production.debug_prepare_store_capture({"kind": "title"})
	var prompt_player: AnimationPlayer = title.get_node(
		"Ui/Screen/PromptBlink") as AnimationPlayer
	var prompt: Label = title.get_node("Ui/Screen/TapPrompt") as Label
	_expect_true(not prompt_player.is_playing(),
		"clean: entry prepare stops the title blink")
	_expect_true(prompt.modulate.is_equal_approx(Color.WHITE),
		"clean: entry prepare locks the prompt white")
	var state: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	var direct: Dictionary = (title as Variant).debug_store_capture_state(
		{"kind": "title"})
	var expected_version: String = "v" + str(ProjectSettings.get_setting(
		"application/config/version", "0.0.0"))
	var version_label: Label = title.get_node(
		"Ui/Screen/Version") as Label
	_expect_equal(state.get("version_text"), version_label.text,
		"clean: version_text is the actual label")
	_expect_equal(state.get("version_text"), expected_version,
		"clean: actual version matches the project version")
	_expect_true(_version_string_valid(str(state.get("version_text", ""))),
		"clean: version_text matches the consumer shape")
	_expect_equal(state.get("expected_version"), expected_version,
		"clean: expected version retained as context")
	_expect_equal(state.get("scene"), "title", "clean: title scene")
	_expect_true(bool(state.get("ready", false)), "clean: ready")
	for field in [
		"screen_visible", "title_visible", "subtitle_visible",
		"title_auto_translate", "subtitle_auto_translate",
		"title_text_nonempty", "title_characters_visible",
		"title_font_size_positive", "title_font_alpha_readable",
		"title_rendered_text_ready",
		"subtitle_text_nonempty", "subtitle_characters_visible",
		"subtitle_font_size_positive", "subtitle_font_alpha_readable",
		"subtitle_rendered_text_ready",
		"title_inside_viewport", "subtitle_inside_viewport",
		"title_opaque", "subtitle_opaque",
		"version_visible", "version_text_nonempty",
		"version_characters_visible", "version_font_size_positive",
		"version_font_alpha_readable", "version_rendered_text_ready",
		"version_inside_viewport", "version_opaque",
		"tap_prompt_visible", "tap_prompt_auto_translate",
		"tap_prompt_text_nonempty", "tap_prompt_characters_visible",
		"tap_prompt_font_size_positive", "tap_prompt_font_alpha_readable",
		"tap_prompt_rendered_text_ready", "tap_prompt_inside_viewport",
		"tap_prompt_readable_alpha", "tap_prompt_full_alpha",
		"tap_prompt_blink_stopped", "tap_prompt_modulate_white",
		"tap_prompt_capture_locked",
		"settings_button_visible", "settings_button_enabled",
		"settings_button_copy_valid", "settings_button_text_nonempty",
		"settings_button_font_size_positive",
		"settings_button_font_alpha_readable",
		"settings_button_rendered_text_ready", "settings_button_opaque",
		"settings_button_inside_viewport",
		"shrine_button_visible", "shrine_button_enabled",
		"shrine_button_copy_valid", "shrine_button_text_nonempty",
		"shrine_button_font_size_positive",
		"shrine_button_font_alpha_readable",
		"shrine_button_rendered_text_ready", "shrine_button_opaque",
		"shrine_button_inside_viewport",
		"ladder_button_visible", "ladder_button_enabled",
		"ladder_button_copy_valid", "ladder_button_text_nonempty",
		"ladder_button_font_size_positive",
		"ladder_button_font_alpha_readable",
		"ladder_button_rendered_text_ready", "ladder_button_opaque",
		"ladder_button_inside_viewport",
		"storefront_feature_matches",
		"store_button_visibility_matches_storefront",
		"store_button_enabled_matches_storefront",
		"store_button_copy_valid", "store_button_text_nonempty",
		"store_button_font_size_positive",
		"store_button_font_alpha_readable",
		"store_button_inside_viewport",
		"night_forest_node_present", "night_forest_scene_matches",
		"night_forest_visible_in_tree", "night_forest_opaque",
		"night_forest_ground_resource_matches",
		"night_forest_drawable_visible_in_tree",
		"night_forest_drawable_opaque", "night_forest_draw_rect_positive",
		"night_forest_draw_rect_intersects_viewport",
		"night_forest_visual_ready",
		"vignette_node_present", "vignette_texture_dimensions_match",
		"vignette_texture_matches", "vignette_visible_in_tree",
		"vignette_opaque", "vignette_draw_rect_positive",
		"vignette_draw_rect_intersects_viewport", "vignette_visual_ready",
		"beacon_node_present", "beacon_scene_matches",
		"beacon_visible_in_tree", "beacon_opaque",
		"beacon_clearing_resource_matches",
		"beacon_drawable_visible_in_tree", "beacon_drawable_opaque",
		"beacon_draw_rect_positive",
		"beacon_draw_rect_intersects_viewport", "beacon_visual_ready",
		"panels_closed", "accepting_input", "screen_inside_viewport",
		"drawn_after_ready", "safe_area_inside_viewport", "safe_ui_ready",
		"title_inside_safe_area", "subtitle_inside_safe_area",
		"version_inside_safe_area", "tap_prompt_inside_safe_area",
		"settings_button_inside_safe_area", "shrine_button_inside_safe_area",
		"ladder_button_inside_safe_area",
	]:
		_expect_true(bool(state.get(field, false)), "clean: " + field)
	var storefront_enabled: bool = Shop.storefront_enabled()
	_expect_equal(state.get("store_button_visible"), storefront_enabled,
		"clean: actual shop visibility")
	_expect_equal(state.get("store_button_enabled"), storefront_enabled,
		"clean: actual shop enabled")
	_expect_equal(state.get("store_button_rendered_text_ready"),
		storefront_enabled, "clean: actual shop render proof")
	_expect_equal(state.get("store_button_opaque"), storefront_enabled,
		"clean: actual shop opaque proof")
	if storefront_enabled:
		_expect_true(bool(state.get("store_button_inside_safe_area", false)),
			"clean: store_button_inside_safe_area")
	for rect_field in [
		"viewport_rect", "safe_rect", "title_rect", "subtitle_rect",
		"version_rect", "tap_prompt_rect", "settings_button_rect",
		"shrine_button_rect", "ladder_button_rect", "store_button_rect",
	]:
		var values: Array = state.get(rect_field, []) as Array
		_expect_equal(values.size(), 4, "clean: " + rect_field)
	_expect_true(is_equal_approx(
		float(state.get("tap_prompt_effective_alpha", 0.0)), 1.0),
		"clean: prompt alpha exactly 1")
	# Forwarded fields equal the Title child's own state; gate context
	# lives under its own names and never overwrites title proof.
	for field in [
		"scene", "ready", "screen_visible", "title_visible",
		"subtitle_visible", "version_visible", "version_text",
		"tap_prompt_visible", "tap_prompt_capture_locked",
		"panels_closed", "accepting_input", "drawn_after_ready",
		"night_forest_visual_ready", "vignette_visual_ready",
		"beacon_visual_ready",
	]:
		_expect_equal(state.get(field), direct.get(field),
			"clean: forwards " + field)
	_expect_true(bool(state.get("production_gate_visible", false)),
		"clean: gate context visible")
	_expect_true(bool(state.get("production_title_node_visible", false)),
		"clean: title node context visible")
	_expect_equal(state.get("production_selection_open"), false,
		"clean: no selection context")
	_expect_equal(state.get("production_title_rest"), true,
		"clean: title rest context")
	_expect_equal(state.get("production_loader_visible"), false,
		"clean: no loader context")
	_expect_equal(state.get("production_loader_active"), false,
		"clean: loader idle context")
	_expect_equal(state.get("production_gate_panel_open"), false,
		"clean: no gate panel context")
	_expect_equal(state.get("production_confirm_visible"), false,
		"clean: no confirm context")
	_expect_true(bool(state.get("production_started", false)),
		"clean: host started context kept")
	_expect_equal(state.get("production_ready"), stub.host_ready,
		"clean: host ready kept under its own name")
	_expect_true(not gate.is_selection_open(),
		"clean: entry prepare leaves no selection")


## The prompt freeze holds across observations: a resumed blink is
## rejected until the title watch re-locks it.
func _check_prompt_freeze(production: ProductionEntry,
		title: Control) -> void:
	var prompt_player: AnimationPlayer = title.get_node(
		"Ui/Screen/PromptBlink") as AnimationPlayer
	var prompt: Label = title.get_node("Ui/Screen/TapPrompt") as Label
	var first: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	(title as Variant)._process(0.0)
	var second: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(bool(first.get("tap_prompt_capture_locked", false)),
		"freeze: first observation locked")
	_expect_true(bool(second.get("tap_prompt_capture_locked", false)),
		"freeze: second observation locked")
	_expect_equal(second.get("tap_prompt_effective_alpha"),
		first.get("tap_prompt_effective_alpha"),
		"freeze: alpha stable across observations")
	prompt_player.play(&"blink")
	var resumed: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(not bool(resumed.get("tap_prompt_blink_stopped", true)),
		"freeze: resumed blink observed")
	_expect_true(not bool(resumed.get("ready", true)),
		"freeze: resumed blink rejects ready")
	(title as Variant)._process(0.0)
	var relocked: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(bool(relocked.get("tap_prompt_capture_locked", false)),
		"freeze: watch re-locks the prompt")
	_expect_true(not prompt_player.is_playing(),
		"freeze: blink stays stopped")
	_expect_true(prompt.modulate.is_equal_approx(Color.WHITE),
		"freeze: white held")
	_expect_true(bool(relocked.get("ready", false)),
		"freeze: ready returns after re-lock")


## Host readiness never decides the title's own `ready`: the flag is
## kept under its own name in both directions.
func _check_host_ready_not_overwriting(production: ProductionEntry,
		stub: StubCaptureHost) -> void:
	stub.host_ready = false
	var unready_host: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(bool(unready_host.get("ready", false)),
		"host: title ready while host unready")
	_expect_equal(unready_host.get("production_ready"), false,
		"host: unready flag kept separately")
	stub.host_ready = true
	var ready_host: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(bool(ready_host.get("ready", false)),
		"host: title ready while host ready")
	_expect_equal(ready_host.get("production_ready"), true,
		"host: ready flag kept separately")
	stub.host_ready = false


## Live copy follows the locale on the real entry, in the same contract
## the Node consumer checks per game locale.
func _check_locales(production: ProductionEntry,
		_title: Control) -> void:
	for locale in CHECK_LOCALES:
		TranslationServer.set_locale(locale)
		await _frames(2)
		production.debug_prepare_store_capture({"kind": "title"})
		var state: Dictionary = production.debug_store_capture_state(
			{"kind": "title"})
		var copy: Array = TITLE_CAPTURE_COPY[locale]
		_expect_equal(state.get("title_translation_text"), copy[0],
			locale + ": title live copy")
		_expect_equal(state.get("subtitle_translation_text"), copy[1],
			locale + ": subtitle live copy")
		_expect_equal(state.get("tap_prompt_translation_text"), copy[2],
			locale + ": prompt live copy")
		_expect_equal(state.get("settings_button_translation_text"), copy[3],
			locale + ": settings live copy")
		_expect_equal(state.get("shrine_button_translation_text"), copy[4],
			locale + ": shrine live copy")
		_expect_equal(state.get("ladder_button_translation_text"), copy[5],
			locale + ": ladder live copy")
		_expect_equal(state.get("store_button_translation_text"), copy[6],
			locale + ": shop live copy")
		_expect_true(bool(state.get("ready", false)),
			locale + ": ready in locale")


## A wrong label is reported as-is and rejects ready; the expected
## version is context, never the actual proof.
func _check_version_mismatch(production: ProductionEntry,
		title: Control) -> void:
	var version_label: Label = title.get_node(
		"Ui/Screen/Version") as Label
	var original: String = version_label.text
	version_label.text = "v0.0.0-wrong"
	var state: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_equal(state.get("version_text"), "v0.0.0-wrong",
		"version: actual wrong text reported")
	_expect_true(not bool(state.get("version_visible", true)),
		"version: wrong text not visible-proof")
	_expect_true(not bool(state.get("version_text_nonempty", true)),
		"version: wrong text not nonempty-proof")
	_expect_true(not bool(state.get("ready", true)),
		"version: wrong version rejects ready")
	version_label.text = original
	var restored: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(bool(restored.get("ready", false)),
		"version: ready returns after restore")


## An open gate panel rejects ready while version and node proofs stay
## actual; closing restores the clean title.
func _check_gate_panel_occlusion(production: ProductionEntry,
		gate: GateEntry) -> void:
	gate.open_exit()
	await _frames(2)
	var exit_panel: Control = gate.get_node("GateExitPanel") as Control
	_expect_true(exit_panel.visible, "panel: exit open")
	var state: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(bool(state.get("production_gate_panel_open", false)),
		"panel: occlusion flagged")
	_expect_true(not bool(state.get("ready", true)),
		"panel: open panel rejects ready")
	_expect_true(_version_string_valid(str(state.get("version_text", ""))),
		"panel: actual version still reported")
	gate.close_panels()
	production.debug_prepare_store_capture({"kind": "title"})
	await _frames(2)
	var restored: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(bool(restored.get("ready", false)),
		"panel: ready returns after close")


## An open selection rejects ready instead of claiming the title beneath.
func _check_selection_occlusion(production: ProductionEntry,
		gate: GateEntry) -> void:
	gate.show_logged_out()
	await _frames(2)
	_expect_true(gate.is_selection_open(), "selection: open")
	var state: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(bool(state.get("production_selection_open", false)),
		"selection: occlusion flagged")
	_expect_true(not bool(state.get("ready", true)),
		"selection: open selection rejects ready")
	production.debug_prepare_store_capture({"kind": "title"})
	await _frames(2)
	var restored: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(bool(restored.get("ready", false)),
		"selection: ready returns after prepare")
	_expect_true(gate.is_title_rest(), "selection: rest restored")


## A visible loader rejects ready; hiding it restores the clean title.
func _check_loader_occlusion(production: ProductionEntry,
		gate: GateEntry) -> void:
	var loader: GateLoadingOverlay = gate.get_loader()
	var token: int = gate.load_scene(ARENA_PATH, "TEST entering the arena")
	_expect_true(token > 0, "loader: begin takes a token")
	_expect_true(loader.visible, "loader: veil visible at once")
	var state: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(bool(state.get("production_loader_visible", false)),
		"loader: visibility flagged")
	_expect_true(bool(state.get("production_loader_active", false)),
		"loader: activity flagged")
	_expect_true(not bool(state.get("ready", true)),
		"loader: visible loader rejects ready")
	loader.cancel()
	loader._on_back()
	await _frames(2)
	production.debug_prepare_store_capture({"kind": "title"})
	var restored: Dictionary = production.debug_store_capture_state(
		{"kind": "title"})
	_expect_true(bool(restored.get("ready", false)),
		"loader: ready returns after hide")


func _version_string_valid(text: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^v\\d+\\.\\d+\\.\\d+(?:[-+][0-9A-Za-z.-]+)?$")
	return pattern.search(text) != null


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
