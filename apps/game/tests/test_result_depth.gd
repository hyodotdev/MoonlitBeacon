extends Node

## Past the win the result screen names the Depth next to the closing story line.
##
## The HUD counts Depth from cycle 9, so the result says the same thing: the
## epitaph shares its full-width line with `HUD_DEPTH`, only when
## `Expedition.depth()` is above zero. The Waves row keeps its points; the
## depth caption scores nothing and the breakdown stays five lines.

const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_panel.tscn")
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	get_tree().root.size = Vector2i(808, 360)
	get_tree().root.content_scale_size = Vector2i(808, 360)
	var original_locale: String = TranslationServer.get_locale()

	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		await _check_win_at_eight(locale)
		await _check_win_past_eight(locale)
		await _check_lose_past_eight(locale)
		await _check_lose_at_eight(locale)
		await _check_escape(locale)
		_check_score_untouched(locale)

	TranslationServer.set_locale(original_locale)
	if _failed > 0:
		printerr("result-depth test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("result-depth test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _check_win_at_eight(locale: String) -> void:
	var panel: Control = await _show_panel(true, 8)
	var epitaph: Label = panel.get_node("Epitaph") as Label
	_expect_true(
		epitaph.text == tr("STORY_EPITAPH_WIN"),
		"%s cycle-8 win shows the story line alone" % locale)
	_expect_true(
		epitaph.get_line_count() == 1,
		"%s cycle-8 win keeps one epitaph line" % locale)
	_expect_fits(epitaph, "%s cycle-8 win story line" % locale)
	await _free_panel(panel)


func _check_win_past_eight(locale: String) -> void:
	var panel: Control = await _show_panel(true, 9)
	var epitaph: Label = panel.get_node("Epitaph") as Label
	_expect_true(
		epitaph.text == tr("STORY_EPITAPH_WIN") + " · " + tr("HUD_DEPTH") % 1,
		"%s cycle-9 win shows Depth 1 next to the story line" % locale)
	_expect_fits(epitaph, "%s cycle-9 win story line with depth" % locale)
	await _free_panel(panel)


func _check_lose_past_eight(locale: String) -> void:
	var panel: Control = await _show_panel(false, 12)
	var epitaph: Label = panel.get_node("Epitaph") as Label
	_expect_true(
		epitaph.text == tr("STORY_EPITAPH_LOSE") + " · " + tr("HUD_DEPTH") % 4,
		"%s cycle-12 loss shows Depth 4 next to the story line" % locale)
	_expect_fits(epitaph, "%s cycle-12 loss story line with depth" % locale)
	await _free_panel(panel)


func _check_lose_at_eight(locale: String) -> void:
	var panel: Control = await _show_panel(false, 8)
	var epitaph: Label = panel.get_node("Epitaph") as Label
	_expect_true(
		epitaph.text == tr("STORY_EPITAPH_LOSE"),
		"%s cycle-8 loss shows the story line alone" % locale)
	await _free_panel(panel)


func _check_escape(locale: String) -> void:
	var panel: Control = await _show_panel(true, 1)
	var epitaph: Label = panel.get_node("Epitaph") as Label
	_expect_true(
		epitaph.text == tr("STORY_EPITAPH_ESCAPE"),
		"%s early return shows the story line alone" % locale)
	await _free_panel(panel)


## The depth line is a caption, not a score row: five breakdown lines and the
## same total the arithmetic always gave.
func _check_score_untouched(locale: String) -> void:
	var score := Score.new()
	score.cycles = 9
	score.beacons = 2
	score.survived = 191.0
	score.level = 20
	var expected: int = 9 * Score.PER_CYCLE + 2 * Score.PER_BEACON \
		+ 191 * Score.PER_SECOND + 19 * Score.PER_LEVEL
	_expect_true(
		score.total() == expected,
		"%s cycle-9 total has no depth points (%d)" % [locale, score.total()])
	_expect_true(
		score.lines().size() == 5,
		"%s breakdown stays five lines" % locale)


func _show_panel(won: bool, cycles: int) -> Control:
	var panel: Control = RESULT_SCENE.instantiate() as Control
	add_child(panel)
	var score := Score.new()
	score.cycles = cycles
	panel.show_result(won, score, false)
	await get_tree().process_frame
	return panel


func _free_panel(panel: Control) -> void:
	panel.queue_free()
	await get_tree().process_frame


func _expect_fits(epitaph: Label, label: String) -> void:
	var minimum: Vector2 = epitaph.get_combined_minimum_size()
	_expect_true(
		minimum.x <= epitaph.size.x + 0.5 and minimum.y <= epitaph.size.y + 0.5,
		"%s (%s / %s)" % [label, minimum, epitaph.size])


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if value:
		return
	_failed += 1
	printerr("  failed: ", label)
