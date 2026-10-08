extends Control

## Settings window. Title and pause share the same scene.
##
## It does not hold the values itself. They live in `Settings`, and this redraws
## when `Settings` changes. That is why two copies of the scene cannot drift.

signal closed
signal credits_requested

const EXTERNAL_LINKS: Script = preload("res://scripts/ui/external_links.gd")

## Size of one volume cell.
const CELL_SIZE: Vector2 = Vector2(12, 14)

## On cell and off cell.
const CELL_ON: Color = Color(1, 0.86, 0.55, 1)
const CELL_OFF: Color = Color(0.28, 0.3, 0.4, 1)

## The picked language button is sharp; the unpicked ones dim including the wood plate.
##
## Dim only the text color and it pops *more* on a bright wood plate. That is
## what it actually looked like.
const PICKED: Color = Color(1, 1, 1, 1)
const UNPICKED: Color = Color(0.5, 0.52, 0.62, 1)
const ANALYTICS_FONT_MAX: int = 13
const ANALYTICS_FONT_MIN: int = 9
const ANALYTICS_AVAILABLE_WIDTH: float = 196.0
## Reminder label fit: the column is 128px (-172 to -44) with an 8px
## allocated gap to the button at -36. English is 164px at 15 and
## 119px at 11, so the fit lands on 11 there and stays 15 in the
## other four locales; 11 matches the locale buttons, never tiny.
const REMINDER_LABEL_FONT_MAX: int = 15
const REMINDER_LABEL_FONT_MIN: int = 11
const REMINDER_LABEL_AVAILABLE_WIDTH: float = 128.0

@onready var _title: Label = $Title
@onready var _music_bar: HBoxContainer = $MusicBar
@onready var _sfx_bar: HBoxContainer = $SfxBar
@onready var _analytics_label: Label = $AnalyticsLabel
@onready var _analytics: Button = $Analytics
## Reminder row, built lazily on first open: two fewer dormant nodes
## in the combat tree (late-game node budget), exactly like the beads
## below. Null until open(); every touch guards or ensures first.
var _reminder_label: Label = null
var _reminder: Button = null
@onready var _analytics_consent: AnalyticsConsentPanel = $Dim/AnalyticsConsent
@onready var _external_links: HBoxContainer = $ExternalLinks
@onready var _privacy: Button = $ExternalLinks/Privacy
@onready var _support: Button = $ExternalLinks/Support
@onready var _link_status: Label = $LinkStatus

var _music_cells: Array[ColorRect] = []
var _sfx_cells: Array[ColorRect] = []
var _locale_buttons: Dictionary = {}
var _privacy_url: String = ""
var _support_url: String = ""
var _link_failed: bool = false
var _beads_hung: bool = false


func _flank_bead(anchor: float, from: float, to: float) -> void:
	var bead: TextureRect = WorldChrome.bead()
	bead.anchor_left = anchor
	bead.anchor_top = 0.5
	bead.anchor_right = anchor
	bead.anchor_bottom = 0.5
	bead.offset_left = from
	bead.offset_top = -6.0
	bead.offset_right = to
	bead.offset_bottom = 6.0
	_title.add_child(bead)


func _ready() -> void:
	_music_cells = _build_cells(_music_bar)
	_sfx_cells = _build_cells(_sfx_bar)

	_locale_buttons = {
		"ko": $LocaleKo,
		"en": $LocaleEn,
		"ja": $LocaleJa,
		"zh_CN": $LocaleZhCn,
		"zh_TW": $LocaleZhTw,
	}
	for locale_code: String in _locale_buttons:
		var button: Button = _locale_buttons[locale_code] as Button
		button.pressed.connect(Settings.set_locale_to.bind(locale_code))
	$MusicDown.pressed.connect(func() -> void: Settings.set_music(Settings.music - 1))
	$MusicUp.pressed.connect(func() -> void: Settings.set_music(Settings.music + 1))
	$SfxDown.pressed.connect(func() -> void: Settings.set_sfx(Settings.sfx - 1))
	$SfxUp.pressed.connect(func() -> void: Settings.set_sfx(Settings.sfx + 1))
	_analytics.pressed.connect(_open_analytics_consent)
	_analytics_consent.decided.connect(_on_analytics_decided)
	_analytics_consent.dismissed.connect(_restore_analytics_focus)
	$Credits.pressed.connect(credits_requested.emit)
	_privacy.pressed.connect(_open_external.bind(true))
	_support.pressed.connect(_open_external.bind(false))
	$Close.pressed.connect(close)

	Settings.changed.connect(_settings_changed)
	_configure_external_links()
	_redraw()


## Build the cells in code. Change `MAX_STEP` and the screen follows.
func _build_cells(bar: HBoxContainer) -> Array[ColorRect]:
	var cells: Array[ColorRect] = []
	for i in Settings.MAX_STEP:
		var cell: ColorRect = ColorRect.new()
		cell.custom_minimum_size = CELL_SIZE
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(cell)
		cells.append(cell)
	return cells


func _redraw() -> void:
	for locale_code: String in _locale_buttons:
		var button: Button = _locale_buttons[locale_code] as Button
		button.modulate = PICKED if Settings.locale == locale_code else UNPICKED
	_fill(_music_cells, Settings.music)
	_fill(_sfx_cells, Settings.sfx)
	_redraw_reminder()
	var analytics_available: bool = Analytics.configured()
	_analytics_label.visible = analytics_available
	_analytics.visible = analytics_available
	_analytics.disabled = not analytics_available
	if not analytics_available:
		_analytics.tooltip_text = ""
		_analytics_consent.close_without_choice()
		if _link_failed:
			_link_status.text = tr("SETTINGS_LINK_FAILED")
		return
	var analytics_key: String = "SETTINGS_ANALYTICS_UNKNOWN"
	if Settings.analytics_consent == Settings.AnalyticsConsent.GRANTED:
		analytics_key = "SETTINGS_ANALYTICS_ON"
	elif Settings.analytics_consent == Settings.AnalyticsConsent.DENIED:
		analytics_key = "SETTINGS_ANALYTICS_OFF"
	_analytics.text = tr(analytics_key)
	_analytics.tooltip_text = "%s — %s" % [tr("SETTINGS_ANALYTICS"), _analytics.text]
	_fit_status_button(_analytics)
	if _link_failed:
		_link_status.text = tr("SETTINGS_LINK_FAILED")


## Reminder row, always rendered once opened: it never depends on
## analytics availability or consent. Statuses: on, off, OS-denied
## (tap disables; tap again from off opens OS settings), unknown
## (tap mirrors denied; an undetermined OS state never shows as on),
## or unsupported on builds without a native side (tapping does
## nothing). No-op before first open, when the row does not exist.
func _redraw_reminder() -> void:
	if _reminder == null or _reminder_label == null:
		return
	_reminder_label.text = tr("SETTINGS_REMINDERS")
	_fit_reminder_label()
	var key: String = "SETTINGS_REMINDERS_OFF"
	_reminder.disabled = false
	if Settings.reminder_os_state == "unsupported":
		key = "SETTINGS_REMINDERS_UNSUPPORTED"
		_reminder.disabled = true
	elif Settings.reminders_enabled \
			and Settings.reminder_os_state == "denied":
		key = "SETTINGS_REMINDERS_DENIED"
	elif Settings.reminders_enabled \
			and Settings.reminder_os_state == "unknown":
		key = "SETTINGS_REMINDERS_UNKNOWN"
	elif Settings.reminders_enabled:
		key = "SETTINGS_REMINDERS_ON"
	_reminder.text = tr(key)
	_reminder.tooltip_text = "%s — %s" % [
		tr("SETTINGS_REMINDERS"), _reminder.text]
	_fit_status_button(_reminder)


## Build the reminder row on first open, replicating the scene's old
## layout, fonts, and colors exactly (same anchors, offsets, theme,
## and steel button kind). Appended after the scene children, which is
## invisible: the rows never overlap.
func _ensure_reminder_row() -> void:
	if _reminder != null and _reminder_label != null:
		return
	var font: Font = _analytics_label.get_theme_font("font")
	_reminder_label = Label.new()
	_reminder_label.name = &"ReminderLabel"
	_reminder_label.set_anchors_preset(Control.PRESET_CENTER)
	_reminder_label.anchor_left = 0.5
	_reminder_label.anchor_top = 0.5
	_reminder_label.anchor_right = 0.5
	_reminder_label.anchor_bottom = 0.5
	_reminder_label.offset_left = -172.0
	_reminder_label.offset_top = 49.0
	_reminder_label.offset_right = -44.0
	_reminder_label.offset_bottom = 83.0
	_reminder_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reminder_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_reminder_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reminder_label.add_theme_color_override("font_color",
		Color(0.85, 0.88, 0.96, 1))
	_reminder_label.add_theme_font_override("font", font)
	_reminder_label.add_theme_font_size_override("font_size", 15)
	_reminder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reminder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_reminder_label)
	_reminder = WorldButton.new()
	_reminder.name = &"Reminder"
	_reminder.kind = "steel"
	_reminder.set_anchors_preset(Control.PRESET_CENTER)
	_reminder.anchor_left = 0.5
	_reminder.anchor_top = 0.5
	_reminder.anchor_right = 0.5
	_reminder.anchor_bottom = 0.5
	_reminder.offset_left = -36.0
	_reminder.offset_top = 49.0
	_reminder.offset_right = 172.0
	_reminder.offset_bottom = 83.0
	_reminder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reminder.grow_vertical = Control.GROW_DIRECTION_BOTH
	_reminder.add_theme_color_override("font_color",
		Color(0.92, 0.9, 0.98, 1))
	_reminder.add_theme_font_override("font", font)
	_reminder.add_theme_font_size_override("font_size", 13)
	_reminder.pressed.connect(_on_reminder_pressed)
	add_child(_reminder)


func _on_reminder_pressed() -> void:
	if _reminder == null or _reminder.disabled:
		return
	var controller: Node = _reminder_controller()
	if controller == null:
		# No host in this tree (bare panel exercise): persist the
		# intent flip directly; the next launch converges it.
		Settings.set_reminders_enabled(
			not Settings.reminders_enabled)
		return
	controller.call("user_toggle")


func _reminder_controller() -> Node:
	var host: Node = get_node_or_null("/root/ProductionHost")
	if host == null or not host.has_method("reminder_controller"):
		return null
	var controller: Variant = host.call("reminder_controller")
	if controller is Node and is_instance_valid(controller):
		return controller
	return null


func _open_analytics_consent() -> void:
	# Even a code-emitted pressed signal from an invisible Button must not open
	# the prompt. Only a build with real shipping config may ask for consent.
	if not Analytics.configured():
		return
	_analytics_consent.open()


func _settings_changed() -> void:
	# After a language change, the open panel's external links must point at the
	# new locale path. Volume uses the same signal, so do not clear a prior
	# open-failed state.
	_refresh_external_link_urls()
	_redraw()


func _configure_external_links() -> void:
	_refresh_external_link_urls()
	_link_failed = false
	_link_status.visible = false


func _refresh_external_link_urls() -> void:
	_privacy_url = EXTERNAL_LINKS.privacy_policy_url()
	_support_url = EXTERNAL_LINKS.support_url()
	_privacy.visible = not _privacy_url.is_empty()
	_support.visible = not _support_url.is_empty()
	_external_links.visible = _privacy.visible or _support.visible


func _open_external(is_privacy: bool) -> void:
	var url: String = _privacy_url if is_privacy else _support_url
	var error: Error = EXTERNAL_LINKS.open_external_url(url)
	_link_failed = error != OK
	_link_status.visible = _link_failed
	if _link_failed:
		_link_status.text = tr("SETTINGS_LINK_FAILED")


func _on_analytics_decided(_granted: bool) -> void:
	# AnalyticsConsentPanel emits this only after an atomic save succeeds.
	# The settings window does not save again; pad focus returns to the button
	# that opened it.
	_redraw()
	_restore_analytics_focus()


func _restore_analytics_focus() -> void:
	if visible and _analytics.visible and not _analytics.disabled \
			and not _analytics_consent.visible:
		_analytics.grab_focus()


func _fit_status_button(target: Button) -> void:
	var font: Font = target.get_theme_font("font")
	var font_size: int = ANALYTICS_FONT_MAX
	while font_size > ANALYTICS_FONT_MIN and font.get_string_size(
			target.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x \
			> ANALYTICS_AVAILABLE_WIDTH:
		font_size -= 1
	target.add_theme_font_size_override("font_size", font_size)


## Shrink the reminder label until its text fits the 128px column.
## Runs on every redraw, so locale changes and repeated opens
## recompute from the max instead of sticking at a stale size.
func _fit_reminder_label() -> void:
	var font: Font = _reminder_label.get_theme_font("font")
	var font_size: int = REMINDER_LABEL_FONT_MAX
	while font_size > REMINDER_LABEL_FONT_MIN and font.get_string_size(
			_reminder_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			float(font_size)).x > REMINDER_LABEL_AVAILABLE_WIDTH:
		font_size -= 1
	_reminder_label.add_theme_font_size_override("font_size", font_size)


func _fill(cells: Array[ColorRect], step: int) -> void:
	for i in cells.size():
		cells[i].color = CELL_ON if i < step else CELL_OFF


func open() -> void:
	# Moon beads flanking the journal title; the 140px label carries short
	# titles in every locale, so they float over the dim, never on glyphs.
	# Hung on first open, never in `_ready` (arena node budget).
	if not _beads_hung:
		_beads_hung = true
		_flank_bead(0.0, -20.0, -8.0)
		_flank_bead(1.0, 8.0, 20.0)
	_ensure_reminder_row()
	visible = true
	_configure_external_links()
	var controller: Node = _reminder_controller()
	if controller != null \
			and controller.has_method("refresh_permission"):
		controller.call("refresh_permission")
	_redraw()
	$Close.grab_focus()


func close() -> void:
	_analytics_consent.close_without_choice()
	visible = false
	closed.emit()


## Whether a nested prompt is open on settings. The parent scene's Android back branch asks first.
func has_nested_overlay() -> bool:
	return _analytics_consent.visible


## Keep settings itself and close only the innermost prompt. True if something closed.
##
## Android WM back never hits this Control's `_unhandled_input`, so title and
## Arena must call this first to unwind one step, matching PC Esc.
func close_nested_overlay() -> bool:
	if not has_nested_overlay():
		return false
	_analytics_consent.close_without_choice()
	return true


## Close with `Esc` on desktop.
##
## Android back does not arrive as `ui_cancel`. It is a separate
## `NOTIFICATION_WM_GO_BACK_REQUEST`, so the parent scene calls
## `close_nested_overlay()` first.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if close_nested_overlay():
			return
		close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_redraw()
