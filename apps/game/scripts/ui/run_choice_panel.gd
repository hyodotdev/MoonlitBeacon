class_name RunChoicePanel
extends Control

## Shared choice modal that splits a run into two paths.
##
## Beacon and end-of-cycle choices share the same input safety and visual
## language. The panel lives in the scene from the start and must receive
## `_input` even while hidden, so a movement finger's release cannot pick a
## freshly opened button.

enum Mode { BEACON, CYCLE }
enum Choice { LEFT, RIGHT }

signal chosen(mode: Mode, choice: Choice, context: Variant)

const MAP_BEYOND_CYCLE: int = 8
const TITLE_FONT_MAX: int = 22
const TITLE_FONT_MIN: int = 15
const TITLE_AVAILABLE_WIDTH: float = 596.0
const CHOICE_TITLE_FONT_MAX: int = 15
const CHOICE_TITLE_FONT_MIN: int = 10
const CHOICE_TITLE_AVAILABLE_WIDTH: float = 252.0

@onready var _frame: PanelContainer = $Center/Frame
@onready var _title: Label = $Center/Frame/Content/Rows/Title
@onready var _subtitle: Label = $Center/Frame/Content/Rows/Subtitle
@onready var _left_button: Button = $Center/Frame/Content/Rows/Choices/Left
@onready var _right_button: Button = $Center/Frame/Content/Rows/Choices/Right
@onready var _left_title: Label = \
	$Center/Frame/Content/Rows/Choices/Left/Copy/Rows/Title
@onready var _left_desc: Label = \
	$Center/Frame/Content/Rows/Choices/Left/Copy/Rows/Description
@onready var _right_title: Label = \
	$Center/Frame/Content/Rows/Choices/Right/Copy/Rows/Title
@onready var _right_desc: Label = \
	$Center/Frame/Content/Rows/Choices/Right/Copy/Rows/Description

var _mode: Mode = Mode.BEACON
var _context: Variant = null
var _completed_overcharges: int = 0
var _completed_cycle: int = 0
var _beacon_core_available: bool = true
var _active_touches: Dictionary = {}
var _mouse_left_down: bool = false
var _choice_armed: bool = false
var _open_generation: int = 0
var _paused_before_open: bool = false
var _open_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	visible = false
	_left_button.pressed.connect(_choose.bind(Choice.LEFT))
	_right_button.pressed.connect(_choose.bind(Choice.RIGHT))
	_set_buttons_enabled(false)


func _input(event: InputEvent) -> void:
	# Remember currently pressed pointers even while hidden. Keep it in the
	# arena scene from the start instead of spawning it dynamically, so a
	# press from before open can still be observed.
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_active_touches[touch.index] = true
		else:
			_active_touches.erase(touch.index)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_mouse_left_down = mouse.pressed


## At a fully charged beacon, pick safe lighting or overcharge.
##
## `context` carries the waiting beacon node as-is. After the signal, the
## caller still checks that beacon is valid and starts the actual lighting or
## overcharge.
func open_beacon(
		beacon: Node, completed_overcharges: int, core_available: bool = true) -> void:
	_mode = Mode.BEACON
	_context = beacon
	_completed_overcharges = clampi(completed_overcharges, 0, 3)
	_beacon_core_available = core_available
	_refresh_copy()
	_open()


## After the guardian falls, pick return or the next cycle.
##
## `context` carries the cycle number just completed. From cycle 8 on, copy
## matches the endless map.
func open_cycle(completed_cycle: int) -> void:
	_mode = Mode.CYCLE
	_context = completed_cycle
	_completed_cycle = maxi(completed_cycle, 0)
	_refresh_copy()
	_open()


## Close with no signal when the choice itself is void, such as a scene change or death.
func close_without_choice() -> void:
	if not visible:
		return
	_close(false, Choice.LEFT)


func _open() -> void:
	if not visible:
		_paused_before_open = get_tree().paused
	_open_generation += 1
	var generation: int = _open_generation
	_choice_armed = false
	_set_buttons_enabled(false)
	# Catch the mouse press that opened the window even if `_input` has not seen it yet.
	_mouse_left_down = _mouse_left_down \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	visible = true
	modulate.a = 0.0
	get_tree().paused = true
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_open_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_open_tween.tween_property(self, "modulate:a", 1.0, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_arm_after_release(generation)


func _arm_after_release(generation: int) -> void:
	# After receiving even the input that opened the modal this frame, wait
	# until every existing pointer is up. On the release frame the buttons are
	# still disabled, so there is no mis-pick.
	await get_tree().process_frame
	while visible and generation == _open_generation \
			and (not _active_touches.is_empty() or _mouse_left_down):
		await get_tree().process_frame
	if not visible or generation != _open_generation:
		return
	_choice_armed = true
	_set_buttons_enabled(true)
	# A required choice must also proceed immediately from keyboard or gamepad,
	# not only touch. Default focus is the safe left option, not the dangerous
	# overcharge/continue.
	_left_button.grab_focus()


func _choose(choice: Choice) -> void:
	if not visible or not _choice_armed:
		return
	_close(true, choice)


func _close(emit_choice: bool, choice: Choice) -> void:
	# Lock first so a second pressed in the same frame and a signal callback cannot re-enter.
	_choice_armed = false
	_open_generation += 1
	_set_buttons_enabled(false)
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	visible = false
	modulate.a = 1.0
	get_tree().paused = _paused_before_open

	var selected_mode: Mode = _mode
	var selected_context: Variant = _context
	_context = null
	if emit_choice:
		chosen.emit(selected_mode, choice, selected_context)


func _set_buttons_enabled(enabled: bool) -> void:
	_left_button.disabled = not enabled
	_right_button.disabled = not enabled


func _refresh_copy() -> void:
	if _mode == Mode.BEACON:
		_set_copy(
			tr("BEACON_CHOICE_TITLE"),
			_translated_int("BEACON_CHOICE_SUBTITLE", _completed_overcharges),
			"BEACON_CHOICE_LEFT_TITLE",
			"BEACON_CHOICE_LEFT_DESC",
			"BEACON_CHOICE_RIGHT_TITLE",
			"BEACON_CHOICE_RIGHT_DESC" if _beacon_core_available \
			else "BEACON_CHOICE_RIGHT_DESC_MAX")
		return

	if _completed_cycle >= MAP_BEYOND_CYCLE:
		_set_copy(
			tr("CYCLE_CHOICE_MAP_BEYOND_TITLE"),
			tr("CYCLE_CHOICE_MAP_BEYOND_SUBTITLE"),
			"CYCLE_CHOICE_MAP_BEYOND_LEFT_TITLE",
			"CYCLE_CHOICE_MAP_BEYOND_LEFT_DESC",
			"CYCLE_CHOICE_MAP_BEYOND_RIGHT_TITLE",
			"CYCLE_CHOICE_MAP_BEYOND_RIGHT_DESC")
		return
	_set_copy(
		_translated_int("CYCLE_CHOICE_TITLE", _completed_cycle),
		tr("CYCLE_CHOICE_SUBTITLE"),
		"CYCLE_CHOICE_LEFT_TITLE",
		"CYCLE_CHOICE_LEFT_DESC",
		"CYCLE_CHOICE_RIGHT_TITLE",
		"CYCLE_CHOICE_RIGHT_DESC")


func _set_copy(
		title_text: String,
		subtitle_text: String,
		left_title_key: String,
		left_desc_key: String,
		right_title_key: String,
		right_desc_key: String) -> void:
	_title.text = title_text
	_subtitle.text = subtitle_text
	_left_title.text = tr(left_title_key)
	_left_desc.text = tr(left_desc_key)
	_right_title.text = tr(right_title_key)
	_right_desc.text = tr(right_desc_key)
	_left_button.tooltip_text = "%s\n%s" % [_left_title.text, _left_desc.text]
	_right_button.tooltip_text = "%s\n%s" % [_right_title.text, _right_desc.text]
	_fit_single_line(_title, TITLE_FONT_MAX, TITLE_FONT_MIN, TITLE_AVAILABLE_WIDTH)
	_fit_single_line(
		_left_title,
		CHOICE_TITLE_FONT_MAX,
		CHOICE_TITLE_FONT_MIN,
		CHOICE_TITLE_AVAILABLE_WIDTH)
	_fit_single_line(
		_right_title,
		CHOICE_TITLE_FONT_MAX,
		CHOICE_TITLE_FONT_MIN,
		CHOICE_TITLE_AVAILABLE_WIDTH)


func _translated_int(key: String, value: int) -> String:
	# Before a new locale is imported, `tr()` returns the key itself. Even in
	# that short window the modal must not break on a `%` error, while a real
	# translation's single `%d` still applies.
	var translated: String = tr(key)
	return translated % value if translated.contains("%d") else translated


func _fit_single_line(label: Label, maximum: int, minimum: int, width: float) -> void:
	var font: Font = label.get_theme_font("font")
	var font_size: int = maximum
	while font_size > minimum and font.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > width:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and visible:
		_refresh_copy()


func _exit_tree() -> void:
	# If the parent scene is swapped while this is open, do not leave the next scene paused.
	if visible and get_tree() != null:
		get_tree().paused = _paused_before_open
