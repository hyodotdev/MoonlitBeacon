extends Node

## Five-language layout and mobile-input safety contract for the two-way choice modal.

const PANEL_SCENE: PackedScene = preload("res://scenes/ui/run_choice_panel.tscn")
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const SAFE_GAP: float = 4.0
const MODE_BEACON: int = 0
const MODE_CYCLE: int = 1
const CHOICE_LEFT: int = 0
const CHOICE_RIGHT: int = 1

var _failed: int = 0
var _checked: int = 0
var _emissions: Array[Dictionary] = []
var _panel: Control


func _ready() -> void:
	# The test coroutine must keep going even while the panel pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	get_tree().root.size = Vector2i(808, 360)
	get_tree().root.content_scale_size = Vector2i(808, 360)

	_panel = PANEL_SCENE.instantiate() as Control
	add_child(_panel)
	_panel.connect("chosen", _on_chosen)
	await get_tree().process_frame
	await get_tree().process_frame

	var original_locale: String = TranslationServer.get_locale()
	await _test_layout_all_locales()
	TranslationServer.set_locale(original_locale)
	await _test_held_touch_release()
	await _test_held_mouse_release()
	await _test_keyboard_and_gamepad_focus()
	await _test_double_press()
	await _test_close_and_pause_restore()

	get_tree().paused = false
	if _failed > 0:
		printerr("run-choice modal test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("run-choice modal test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _test_layout_all_locales() -> void:
	var beacon: Node = Node.new()
	add_child(beacon)
	for locale in LOCALES:
		TranslationServer.set_locale(locale)

		_panel.call("open_beacon", beacon, 2)
		await _settle_layout()
		_expect_equal(
			_label("Title").text,
			tr("BEACON_CHOICE_TITLE"),
			"%s beacon title translation" % locale)
		_expect_equal(
			_label("Subtitle").text,
			_translated_int("BEACON_CHOICE_SUBTITLE", 2),
			"%s beacon overcharge numbers" % locale)
		_check_layout("%s beacon" % locale)
		_panel.call("close_without_choice")

		_panel.call("open_beacon", beacon, 2, false)
		await _settle_layout()
		_expect_equal(
			_choice_label("Right", "Description").text,
			tr("BEACON_CHOICE_RIGHT_DESC_MAX"),
			"%s max-power overcharge description" % locale)
		_check_layout("%s max-power beacon" % locale)
		_panel.call("close_without_choice")

		_panel.call("open_cycle", 7)
		await _settle_layout()
		_expect_equal(
			_label("Title").text,
			_translated_int("CYCLE_CHOICE_TITLE", 7),
			"%s cycle number" % locale)
		_check_layout("%s cycle" % locale)
		_panel.call("close_without_choice")

		_panel.call("open_cycle", 8)
		await _settle_layout()
		_expect_equal(
			_label("Title").text,
			tr("CYCLE_CHOICE_MAP_BEYOND_TITLE"),
			"%s beyond-the-map title" % locale)
		_expect_equal(
			_label("Subtitle").text,
			tr("CYCLE_CHOICE_MAP_BEYOND_SUBTITLE"),
			"%s beyond-the-map subtitle" % locale)
		_expect_equal(
			_choice_label("Left", "Title").text,
			tr("CYCLE_CHOICE_MAP_BEYOND_LEFT_TITLE"),
			"%s beyond-the-map left" % locale)
		_expect_equal(
			_choice_label("Right", "Description").text,
			tr("CYCLE_CHOICE_MAP_BEYOND_RIGHT_DESC"),
			"%s beyond-the-map right description" % locale)
		_check_layout("%s beyond the map" % locale)
		_panel.call("close_without_choice")

	beacon.queue_free()
	await get_tree().process_frame


func _test_held_touch_release() -> void:
	var before: int = _emissions.size()
	var beacon: Node = Node.new()
	add_child(beacon)
	var center: Vector2 = _button("Left").get_global_rect().get_center()
	_push_touch(3, center, true)
	await get_tree().process_frame
	_panel.call("open_beacon", beacon, 1)
	await get_tree().process_frame
	_expect_true(get_tree().paused, "modal pauses the tree during in-flight touch")
	_expect_true(_button("Left").disabled, "left locked during in-flight touch")
	_expect_true(_button("Right").disabled, "right locked during in-flight touch")

	_push_touch(3, center, false)
	await get_tree().process_frame
	_expect_equal(_emissions.size(), before, "an in-flight touch release does not choose")
	await get_tree().process_frame
	_expect_true(not _button("Left").disabled, "left enables the frame after touch release")
	_expect_true(not _button("Right").disabled, "right enables the frame after touch release")
	_panel.call("close_without_choice")
	beacon.queue_free()
	await get_tree().process_frame


func _test_held_mouse_release() -> void:
	var before: int = _emissions.size()
	var center: Vector2 = _button("Right").get_global_rect().get_center()
	_push_mouse(center, true)
	await get_tree().process_frame
	_panel.call("open_cycle", 3)
	await get_tree().process_frame
	_expect_true(_button("Left").disabled, "left locked during in-flight mouse")
	_expect_true(_button("Right").disabled, "right locked during in-flight mouse")

	_push_mouse(center, false)
	await get_tree().process_frame
	_expect_equal(_emissions.size(), before, "an in-flight mouse release does not choose")
	await get_tree().process_frame
	_expect_true(not _button("Left").disabled, "left enables the frame after mouse release")
	_expect_true(not _button("Right").disabled, "right enables the frame after mouse release")
	_panel.call("close_without_choice")
	await get_tree().process_frame


func _test_keyboard_and_gamepad_focus() -> void:
	var before: int = _emissions.size()
	_panel.call("open_cycle", 3)
	await _settle_layout()
	_expect_true(
		get_viewport().gui_get_focus_owner() == _button("Left"),
		"keyboard/gamepad default focus is the safe left choice")

	var accept: InputEventKey = InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	await get_tree().process_frame
	accept.pressed = false
	Input.parse_input_event(accept)
	await get_tree().process_frame
	_expect_equal(_emissions.size(), before + 1, "ui_accept advances the required choice")
	if _emissions.size() <= before:
		_panel.call("close_without_choice")
		return
	var emission: Dictionary = _emissions.back()
	_expect_equal(int(emission["mode"]), MODE_CYCLE, "ui_accept passes cycle mode")
	_expect_equal(int(emission["choice"]), CHOICE_LEFT, "ui_accept passes the safe choice")
	_expect_true(not _panel.visible, "modal closes after ui_accept")


func _test_double_press() -> void:
	var before: int = _emissions.size()
	_panel.call("open_cycle", 4)
	await _settle_layout()
	_button("Right").emit_signal(&"pressed")
	_button("Right").emit_signal(&"pressed")
	_expect_equal(_emissions.size(), before + 1, "held pressed chooses only once")
	var emission: Dictionary = _emissions.back()
	_expect_equal(int(emission["mode"]), MODE_CYCLE, "passes cycle mode")
	_expect_equal(int(emission["choice"]), CHOICE_RIGHT, "passes the right choice")
	_expect_equal(int(emission["context"]), 4, "passes completed-cycle context")
	_expect_true(not _panel.visible, "modal closes right after the choice")
	_expect_true(not get_tree().paused, "tree unpauses right after the choice")

	var beacon: Node = Node.new()
	add_child(beacon)
	before = _emissions.size()
	_panel.call("open_beacon", beacon, 0)
	await _settle_layout()
	_button("Left").emit_signal(&"pressed")
	_expect_equal(_emissions.size(), before + 1, "beacon choice emitted once")
	emission = _emissions.back()
	_expect_equal(int(emission["mode"]), MODE_BEACON, "passes beacon mode")
	_expect_equal(int(emission["choice"]), CHOICE_LEFT, "passes the left choice")
	_expect_true(emission["context"] == beacon, "passes the beacon Node as context")
	beacon.queue_free()
	await get_tree().process_frame


func _test_close_and_pause_restore() -> void:
	var before: int = _emissions.size()
	_panel.call("open_cycle", 1)
	await get_tree().process_frame
	_expect_true(get_tree().paused, "opening pauses the tree")
	_panel.call("close_without_choice")
	_expect_true(not get_tree().paused, "closing without a choice restores the previous run state")
	_expect_equal(_emissions.size(), before, "closing without a choice emits no signal")

	get_tree().paused = true
	_panel.call("open_cycle", 2)
	await get_tree().process_frame
	_panel.call("close_without_choice")
	_expect_true(get_tree().paused, "a tree that was already paused stays paused when closed")
	_expect_equal(_emissions.size(), before, "restoring prior pause also emits no signal")
	get_tree().paused = false


func _check_layout(label: String) -> void:
	var panel_rect: Rect2 = _panel.get_global_rect()
	var frame: Control = _panel.get_node("Center/Frame") as Control
	var frame_rect: Rect2 = frame.get_global_rect()
	var title: Label = _label("Title")
	var subtitle: Label = _label("Subtitle")
	var rule: Control = _panel.get_node("Center/Frame/Content/Rows/Rule") as Control
	var choices: HBoxContainer = _panel.get_node(
		"Center/Frame/Content/Rows/Choices") as HBoxContainer
	var left: Button = _button("Left")
	var right: Button = _button("Right")

	_expect_true(_inside(frame_rect, panel_rect), "%s frame inside 808x360" % label)
	_expect_true(
		title.get_global_rect().end.y + SAFE_GAP <= subtitle.get_global_rect().position.y,
		"%s gap between title and subtitle" % label)
	_expect_true(
		subtitle.get_global_rect().end.y <= rule.get_global_rect().position.y,
		"%s subtitle then divider order" % label)
	_expect_true(
		rule.get_global_rect().end.y <= choices.get_global_rect().position.y,
		"%s divider then choices order" % label)
	_expect_true(
		left.get_global_rect().end.x + SAFE_GAP <= right.get_global_rect().position.x,
		"%s gap between the two choices" % label)
	_expect_true(_inside(left.get_global_rect(), frame_rect), "%s left card inside frame" % label)
	_expect_true(_inside(right.get_global_rect(), frame_rect), "%s right card inside frame" % label)

	for text_label in [
		title,
		subtitle,
		_choice_label("Left", "Title"),
		_choice_label("Left", "Description"),
		_choice_label("Right", "Title"),
		_choice_label("Right", "Description"),
	]:
		_expect_true(
			text_label.get_line_count() <= text_label.get_visible_line_count(),
			"%s copy not clipped: %s" % [label, text_label.text])


func _settle_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _label(name: String) -> Label:
	return _panel.get_node("Center/Frame/Content/Rows/" + name) as Label


func _button(side: String) -> Button:
	return _panel.get_node("Center/Frame/Content/Rows/Choices/" + side) as Button


func _choice_label(side: String, name: String) -> Label:
	return _panel.get_node(
		"Center/Frame/Content/Rows/Choices/%s/Copy/Rows/%s" % [side, name]) as Label


func _push_touch(index: int, position: Vector2, pressed: bool) -> void:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = index
	touch.position = position
	touch.pressed = pressed
	get_viewport().push_input(touch)


func _push_mouse(position: Vector2, pressed: bool) -> void:
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = position
	mouse.pressed = pressed
	get_viewport().push_input(mouse)


func _on_chosen(mode: int, choice: int, context: Variant) -> void:
	_emissions.append({"mode": mode, "choice": choice, "context": context})


func _translated_int(key: String, value: int) -> String:
	var translated: String = tr(key)
	return translated % value if translated.contains("%d") else translated


func _inside(rect: Rect2, boundary: Rect2) -> bool:
	const EPSILON: float = 0.01
	return rect.has_area() \
		and rect.position.x >= boundary.position.x - EPSILON \
		and rect.position.y >= boundary.position.y - EPSILON \
		and rect.end.x <= boundary.end.x + EPSILON \
		and rect.end.y <= boundary.end.y + EPSILON


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected=", expected, " actual=", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)
