extends SceneTree

## Confirm the store-capture handshake hides only live debug UI and leaves complete proof.
## The release-disabled boundary is pinned separately by export-resource-filter.test.mjs source guards.

const CLEAN_UI_SCRIPT: Script = preload("res://scripts/dev/store_capture_clean_ui.gd")
const BOOT_SCRIPT: Script = preload("res://scripts/dev/store_capture_boot.gd")
const PROBE_SCRIPT: Script = preload("res://scripts/dev/store_capture_probe.gd")
const TITLE_REQUEST: String = "user://store_capture_clean_title.request"
const TITLE_READY: String = "user://store_capture_clean_title.ready"
const COMBAT_REQUEST: String = "user://store_capture_clean_combat.request"
const COMBAT_READY: String = "user://store_capture_clean_combat.ready"
const HIDDEN_DRAW_FRAME_META: StringName = &"store_capture_clean_ui_hidden_draw_frame"

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	await _test_title_tools()
	await _test_combat_tools()
	_test_boot_request()
	_test_capture_locale_override()
	_cleanup()
	if _failed > 0:
		printerr("store clean-UI test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("store clean-UI test passed — ", _checked, " case(s)")
	quit(0)


func _test_title_tools() -> void:
	var launcher: Control = Control.new()
	_expect_true(launcher.visible, "TestLauncher shown before the request")
	_write_request(TITLE_REQUEST)
	_expect_true(CLEAN_UI_SCRIPT.hide_title(launcher), "title handshake consumed")
	_expect_true(not launcher.visible, "TestLauncher hidden after the request")
	_expect_equal(_read_text(TITLE_READY), "", "title-complete is not published on the same hidden draw")
	# The dummy headless renderer does not bump a draw counter, so model the previous draw serial
	# Product code records only the actual nonnegative serial at the hide moment.
	launcher.set_meta(HIDDEN_DRAW_FRAME_META, -1)
	_expect_true(CLEAN_UI_SCRIPT.hide_title(launcher), "confirms a follow-up title draw")
	_expect_equal(_read_text(TITLE_READY), "title-hidden", "title hide-complete proof")
	launcher.visible = true
	_expect_true(CLEAN_UI_SCRIPT.hide_title(launcher), "detects title re-shown")
	_expect_true(not launcher.visible, "re-shown TestLauncher is hidden again immediately")
	_expect_equal(_read_text(TITLE_READY), "", "title re-show invalidates the old complete proof")
	_expect_true(
		not FileAccess.file_exists(TITLE_REQUEST),
		"title re-show also drops the same request to block ABA republish")
	_expect_true(
		not CLEAN_UI_SCRIPT.hide_title(launcher),
		"title does not republish hide proof before a new arm")
	_expect_equal(_read_text(TITLE_READY), "", "title does not republish proof for the same request")
	_write_request(TITLE_REQUEST)
	_expect_true(CLEAN_UI_SCRIPT.hide_title(launcher), "title re-arms a new request")
	launcher.set_meta(HIDDEN_DRAW_FRAME_META, -1)
	_expect_true(CLEAN_UI_SCRIPT.hide_title(launcher), "confirms a new draw after title re-show")
	_expect_equal(_read_text(TITLE_READY), "title-hidden", "title new-request hide-complete proof")
	_write_json(TITLE_REQUEST, {})
	launcher.visible = true
	_expect_true(
		not CLEAN_UI_SCRIPT.hide_title(launcher),
		"CoreDevice {} overwrite clears the title clean-UI request")
	_expect_true(launcher.visible, "a cleared clean-UI request does not hide title tools")
	launcher.free()
	_cleanup()


func _test_combat_tools() -> void:
	var frame_meter: Label = Label.new()
	var tools: Control = Control.new()
	_expect_true(tools.visible, "ArenaTools shown before the request")
	_expect_true(frame_meter.visible, "FrameMeter shown before the request")
	_write_request(COMBAT_REQUEST)
	_expect_true(
		CLEAN_UI_SCRIPT.hide_combat(tools, frame_meter),
		"combat handshake consumed")
	_expect_true(not tools.visible, "ArenaTools hidden after the request")
	_expect_true(not frame_meter.visible, "FrameMeter hidden after the request")
	_expect_equal(_read_text(COMBAT_READY), "", "combat-complete is not published on the same hidden draw")
	tools.set_meta(HIDDEN_DRAW_FRAME_META, -1)
	_expect_true(
		CLEAN_UI_SCRIPT.hide_combat(tools, frame_meter),
		"confirms a follow-up combat draw")
	_expect_equal(_read_text(COMBAT_READY), "combat-hidden", "combat hide-complete proof")
	tools.visible = true
	frame_meter.visible = true
	_expect_true(
		CLEAN_UI_SCRIPT.hide_combat(tools, frame_meter),
		"detects combat debug UI re-shown")
	_expect_true(not tools.visible, "re-shown ArenaTools is hidden again immediately")
	_expect_true(not frame_meter.visible, "re-shown FrameMeter is hidden again immediately")
	_expect_equal(_read_text(COMBAT_READY), "", "combat re-show invalidates the old complete proof")
	_expect_true(
		not FileAccess.file_exists(COMBAT_REQUEST),
		"combat re-show also drops the same request to block ABA republish")
	_expect_true(
		not CLEAN_UI_SCRIPT.hide_combat(tools, frame_meter),
		"combat does not republish hide proof before a new arm")
	_expect_equal(_read_text(COMBAT_READY), "", "combat does not republish proof for the same request")
	_write_request(COMBAT_REQUEST)
	_expect_true(
		CLEAN_UI_SCRIPT.hide_combat(tools, frame_meter),
		"combat re-arms a new request")
	tools.set_meta(HIDDEN_DRAW_FRAME_META, -1)
	_expect_true(
		CLEAN_UI_SCRIPT.hide_combat(tools, frame_meter),
		"confirms a new draw after combat re-show")
	_expect_equal(_read_text(COMBAT_READY), "combat-hidden", "combat new-request hide-complete proof")
	_write_json(COMBAT_REQUEST, {})
	tools.visible = true
	frame_meter.visible = true
	_expect_true(
		not CLEAN_UI_SCRIPT.hide_combat(tools, frame_meter),
		"CoreDevice {} overwrite clears the combat clean-UI request")
	_expect_true(tools.visible and frame_meter.visible, "a cleared request does not hide combat tools")
	tools.free()
	frame_meter.free()
	_cleanup()


func _test_boot_request() -> void:
	var path: String = str(BOOT_SCRIPT.REQUEST_PATH)
	_write_json(path, {
		"schema": 1,
		"nonce": "a".repeat(64),
		"kind": "field_guardian",
	})
	_expect_equal(BOOT_SCRIPT.read_request(false), {}, "release does not read boot requests")
	_expect_equal(
		BOOT_SCRIPT.read_request(true),
		{"schema": 1, "nonce": "a".repeat(64), "kind": "field_guardian"},
		"debug tablet guardian boot request")
	for invalid in [
		{"schema": 1, "nonce": "short", "kind": "field_guardian"},
		{"schema": 1, "nonce": "b".repeat(64), "kind": "not-a-scene"},
		["not", "a", "dictionary"],
	]:
		_write_json(path, invalid)
		_expect_equal(BOOT_SCRIPT.read_request(true), {}, "rejects a bad boot request")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_capture_locale_override() -> void:
	_expect_true(
		"hero_direction" in PROBE_SCRIPT.ALLOWED_KINDS,
		"allows the hero-direction matrix runtime request")
	_expect_true(
		"hero_direction" not in BOOT_SCRIPT.ALLOWED_KINDS,
		"hero-direction matrix is rejected as a boost boot request")
	for locale in ["ko", "en", "ja", "zh_CN", "zh_TW"]:
		_expect_equal(
			PROBE_SCRIPT.capture_locale({"game_locale": locale}),
			locale,
			"device-capture temporary locale " + locale)
	for invalid in ["", "en-US", "zh-Hans", "fr", 7]:
		_expect_equal(
			PROBE_SCRIPT.capture_locale({"game_locale": invalid}),
			"",
			"rejects an unsupported capture temporary locale")


func _write_request(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect_true(file != null, path + " created")
	if file != null:
		file.store_string("request\n")


func _write_json(path: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect_true(file != null, path + " JSON created")
	if file != null:
		file.store_string(JSON.stringify(value))


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()


func _cleanup() -> void:
	for path in [
		TITLE_REQUEST,
		TITLE_READY,
		COMBAT_REQUEST,
		COMBAT_READY,
		str(BOOT_SCRIPT.REQUEST_PATH),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("FAIL: ", label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		_failed += 1
		printerr("FAIL: ", label, " — expected=", expected, " actual=", actual)
