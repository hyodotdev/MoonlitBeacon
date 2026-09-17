extends Node

## Check that five-language credits, including the Noto CJK notice and IAP supporter, fit 808×360.

const CREDITS_SCENE: PackedScene = preload("res://scenes/ui/credits_panel.tscn")
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const SAFE_GAP: float = 4.0

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	get_tree().root.size = Vector2i(808, 360)
	get_tree().root.content_scale_size = Vector2i(808, 360)
	var original_locale: String = TranslationServer.get_locale()
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		var credits: Control = CREDITS_SCENE.instantiate() as Control
		add_child(credits)
		credits.open()
		await get_tree().process_frame
		await get_tree().process_frame
		await _check_locale(credits, locale)
		credits.queue_free()
		await get_tree().process_frame
	TranslationServer.set_locale(original_locale)

	if _failed > 0:
		printerr("credits layout test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("credits layout test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _check_locale(credits: Control, locale: String) -> void:
	var roles: Label = credits.get_node("Roles") as Label
	var names: Label = credits.get_node("Names") as Label
	var back: Button = credits.get_node("Back") as Button
	# Reproduce the extra line credits_panel.gd actually appends after a supporter purchase.
	roles.text += "\n" + tr("CREDITS_SUPPORTER")
	names.text += "\n★ MoonlitTester"
	await get_tree().process_frame
	await get_tree().process_frame

	var panel_rect: Rect2 = credits.get_global_rect()
	var back_rect: Rect2 = back.get_global_rect()
	var button_limit: float = back_rect.position.y - SAFE_GAP
	var roles_content_end: float = (
		roles.get_global_rect().position.y + roles.get_minimum_size().y
	)
	var names_content_end: float = (
		names.get_global_rect().position.y + names.get_minimum_size().y
	)
	_expect_true(
		roles.get_minimum_size().y <= roles.size.y,
		"%s role-column height with supporter" % locale)
	_expect_true(
		names.get_minimum_size().y <= names.size.y,
		"%s name-column height with supporter" % locale)
	_expect_true(
		roles_content_end <= button_limit,
		"%s gap between role column and Back (%s / %s)" % [
			locale, roles_content_end, button_limit])
	_expect_true(
		names_content_end <= button_limit,
		"%s gap between name column and Back (%s / %s)" % [
			locale, names_content_end, button_limit])
	_expect_true(
		back_rect.end.y <= panel_rect.end.y - SAFE_GAP,
		"%s Back stays on screen (%s / %s)" % [
			locale, back_rect, panel_rect])


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if value:
		return
	_failed += 1
	printerr("  failed: ", label)
