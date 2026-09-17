class_name AnalyticsConsentPanel
extends Control

## Prompt where the player chooses whether to send anonymous game metrics.
##
## Opening and closing alone do not change settings. A save is attempted only
## when SHARE or NOT_NOW is freshly pressed, and `decided` fires only after
## the permanent write finishes. On failure the prompt stays open so it cannot
## look like success, and the same choice can be retried immediately.

signal decided(granted: bool)
## Closed without a choice, as with Esc/back. The owner can unlock the UI behind it.
signal dismissed

const EXTERNAL_LINKS: Script = preload("res://scripts/ui/external_links.gd")
const TITLE_FONT_MAX: int = 22
const TITLE_FONT_MIN: int = 15
const TITLE_AVAILABLE_WIDTH: float = 552.0
const ACTION_FONT_MAX: int = 14
const ACTION_FONT_MIN: int = 10
const ACTION_AVAILABLE_WIDTH: float = 248.0

@onready var _title: Label = $Center/Frame/Content/Rows/Title
@onready var _body: Label = $Center/Frame/Content/Rows/Body
@onready var _privacy: Button = $Center/Frame/Content/Rows/Privacy
@onready var _link_status: Label = $Center/Frame/Content/Rows/LinkStatus
@onready var _share: Button = $Center/Frame/Content/Rows/Actions/Share
@onready var _not_now: Button = $Center/Frame/Content/Rows/Actions/NotNow

var _active_touches: Dictionary = {}
var _mouse_left_down: bool = false
var _choice_armed: bool = false
var _open_generation: int = 0
var _paused_before_open: bool = false
var _privacy_url: String = ""
var _open_tween: Tween
var _save_failed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	visible = false
	_share.pressed.connect(_choose.bind(true))
	_not_now.pressed.connect(_choose.bind(false))
	_privacy.pressed.connect(_open_privacy)
	_set_actions_enabled(false)


func _input(event: InputEvent) -> void:
	# Remember pressed pointers even while hidden. A prompt that opens mid-combat
	# must not treat a movement finger's release as a choice.
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


## Open waiting for a choice. This call itself does not change Settings.
func open() -> void:
	# With no shipping config, never show the consent choice in UNKNOWN or a
	# leftover GRANTED. If config is added later, do not reuse a prior build's
	# pre-selection.
	if not Analytics.configured():
		if visible:
			close_without_choice()
		return
	if not visible:
		_paused_before_open = get_tree().paused
	_open_generation += 1
	var generation: int = _open_generation
	_choice_armed = false
	_save_failed = false
	_mouse_left_down = _mouse_left_down \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_refresh_copy()
	_refresh_privacy_link()
	_set_actions_enabled(false)
	visible = true
	modulate.a = 0.0
	get_tree().paused = true
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_open_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_open_tween.tween_property(self, "modulate:a", 1.0, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_arm_after_release(generation)


## Close with no signal when leaving without a decision, such as a scene change or back.
func close_without_choice() -> void:
	if not visible:
		return
	_close(false, false)
	dismissed.emit()


func _arm_after_release(generation: int) -> void:
	await get_tree().process_frame
	while visible and generation == _open_generation \
			and (not _active_touches.is_empty() or _mouse_left_down):
		await get_tree().process_frame
	if not visible or generation != _open_generation:
		return
	_choice_armed = true
	_set_actions_enabled(true)
	_share.grab_focus()


func _choose(granted: bool) -> void:
	if not visible or not _choice_armed:
		return
	# Static config never changes after open, but re-check the same boundary
	# just before SHARE so GRANTED is not saved on a bypass call or a future
	# dynamic config change.
	if granted and not Analytics.configured():
		close_without_choice()
		return
	_save_failed = false
	_refresh_status()
	var persisted: bool = Settings.set_analytics_consent(
		Settings.AnalyticsConsent.GRANTED if granted \
		else Settings.AnalyticsConsent.DENIED)
	if not persisted:
		_save_failed = true
		_refresh_status()
		_set_actions_enabled(true)
		(_share if granted else _not_now).grab_focus()
		return
	_close(true, granted)


func _close(emit_decision: bool, granted: bool) -> void:
	_choice_armed = false
	_open_generation += 1
	_set_actions_enabled(false)
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	visible = false
	modulate.a = 1.0
	get_tree().paused = _paused_before_open
	if emit_decision:
		decided.emit(granted)


func _set_actions_enabled(enabled: bool) -> void:
	_share.disabled = not enabled
	_not_now.disabled = not enabled
	_privacy.disabled = not enabled or _privacy_url.is_empty()


func _refresh_copy() -> void:
	_title.text = tr("ANALYTICS_CONSENT_TITLE")
	_body.text = tr("ANALYTICS_CONSENT_BODY")
	_privacy.text = tr("ANALYTICS_CONSENT_PRIVACY")
	_share.text = tr("ANALYTICS_CONSENT_SHARE")
	_not_now.text = tr("ANALYTICS_CONSENT_NOT_NOW")
	_fit_single_line(_title, TITLE_FONT_MAX, TITLE_FONT_MIN, TITLE_AVAILABLE_WIDTH)
	_fit_button(_share)
	_fit_button(_not_now)


func _refresh_privacy_link() -> void:
	_privacy_url = EXTERNAL_LINKS.privacy_policy_url()
	_privacy.visible = not _privacy_url.is_empty()
	_refresh_status()


func _open_privacy() -> void:
	if not _choice_armed or _privacy_url.is_empty():
		return
	var error: Error = EXTERNAL_LINKS.open_external_url(_privacy_url)
	_save_failed = false
	_link_status.visible = error != OK
	if error != OK:
		_link_status.text = tr("SETTINGS_LINK_FAILED")


func _refresh_status() -> void:
	_link_status.visible = _save_failed
	if _save_failed:
		_link_status.text = tr("SETTINGS_SAVE_FAILED")


func _fit_button(button: Button) -> void:
	var font: Font = button.get_theme_font("font")
	var font_size: int = ACTION_FONT_MAX
	while font_size > ACTION_FONT_MIN and font.get_string_size(
			button.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x \
			> ACTION_AVAILABLE_WIDTH:
		font_size -= 1
	button.add_theme_font_size_override("font_size", font_size)


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
		_refresh_privacy_link()
		_set_actions_enabled(_choice_armed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close_without_choice()


func _exit_tree() -> void:
	if visible and get_tree() != null:
		get_tree().paused = _paused_before_open
