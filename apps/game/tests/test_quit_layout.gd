extends Node

## Check that the five-language quit title fits its card with real padding.
##
## The Japanese title is 266 px at font 26, wider than the old 260 px card, and
## its Label spanned the whole viewport instead of the card. Every locale must
## fit inside the card with 12 px padding each side, Cancel keeps default focus,
## and both buttons stay wired to their behaviors.

const QUIT_SCENE: PackedScene = preload("res://scenes/ui/quit_panel.tscn")
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const SIDE_PADDING: float = 12.0

var _failed: int = 0
var _checked: int = 0
var _cancelled: int = 0


func _ready() -> void:
	get_tree().root.size = Vector2i(808, 360)
	get_tree().root.content_scale_size = Vector2i(808, 360)
	var original_locale: String = TranslationServer.get_locale()
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		var quit: Control = QUIT_SCENE.instantiate() as Control
		add_child(quit)
		quit.open()
		await get_tree().process_frame
		await get_tree().process_frame
		_check_locale(quit, locale)
		quit.queue_free()
		await get_tree().process_frame
	TranslationServer.set_locale(original_locale)

	await _check_behaviors()

	if _failed > 0:
		printerr("quit-layout test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("quit-layout test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _check_locale(quit: Control, locale: String) -> void:
	var card: Panel = quit.get_node("Card") as Panel
	var title: Label = quit.get_node("Title") as Label
	var card_rect: Rect2 = card.get_global_rect()
	var title_rect: Rect2 = title.get_global_rect()
	_expect_true(
		title_rect.position.x >= card_rect.position.x + SIDE_PADDING - 0.5
		and title_rect.end.x <= card_rect.end.x - SIDE_PADDING + 0.5,
		"%s title stays inside the card with padding (%s / %s)" % [
			locale, title_rect, card_rect])
	_expect_true(
		tr("QUIT_TITLE") != "QUIT_TITLE",
		"%s quit title resolves" % locale)
	# Auto-translate may replace the key or translate at draw time; measure
	# what the player reads either way.
	var shown: String = title.text
	if shown == "QUIT_TITLE":
		shown = tr("QUIT_TITLE")
	var font: Font = title.get_theme_font("font")
	var font_size: int = title.get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(
		shown, HORIZONTAL_ALIGNMENT_LEFT, -1.0, float(font_size)).x
	_expect_true(
		text_width <= title_rect.size.x + 0.5,
		"%s title text fits its label (%s / %s)" % [
			locale, text_width, title_rect.size.x])
	_expect_true(
		title.get_line_count() <= 1,
		"%s title keeps one line" % locale)


func _check_behaviors() -> void:
	var quit: Control = QUIT_SCENE.instantiate() as Control
	add_child(quit)
	quit.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var no_button: Button = quit.get_node("No") as Button
	var yes_button: Button = quit.get_node("Yes") as Button
	_expect_true(
		get_viewport().gui_get_focus_owner() == no_button,
		"Cancel keeps default focus")
	_expect_true(
		yes_button.is_connected("pressed", Callable(quit, "_quit")),
		"Quit stays wired to save-and-quit")
	_cancelled = 0
	quit.cancelled.connect(_on_cancelled)
	no_button.pressed.emit()
	_expect_equal(_cancelled, 1, "Cancel emits cancelled")
	_expect_true(not quit.visible, "Cancel closes the panel")
	quit.queue_free()
	await get_tree().process_frame


func _on_cancelled() -> void:
	_cancelled += 1


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)
