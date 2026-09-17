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

@onready var _music_bar: HBoxContainer = $MusicBar
@onready var _sfx_bar: HBoxContainer = $SfxBar
@onready var _analytics_label: Label = $AnalyticsLabel
@onready var _analytics: Button = $Analytics
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
	_fit_analytics_button()
	if _link_failed:
		_link_status.text = tr("SETTINGS_LINK_FAILED")


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


func _fit_analytics_button() -> void:
	var font: Font = _analytics.get_theme_font("font")
	var font_size: int = ANALYTICS_FONT_MAX
	while font_size > ANALYTICS_FONT_MIN and font.get_string_size(
			_analytics.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x \
			> ANALYTICS_AVAILABLE_WIDTH:
		font_size -= 1
	_analytics.add_theme_font_size_override("font_size", font_size)


func _fill(cells: Array[ColorRect], step: int) -> void:
	for i in cells.size():
		cells[i].color = CELL_ON if i < step else CELL_OFF


func open() -> void:
	visible = true
	_configure_external_links()
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
