extends Node

## Check that the result screen six-line score and purchase goal do not overlap at 808×360.

const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_panel.tscn")
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
		var panel: Control = RESULT_SCENE.instantiate() as Control
		add_child(panel)
		var score := Score.new()
		score.cycles = 123
		score.beacons = 3
		score.survived = 3599.0
		score.level = 40
		score.kills = 99999
		score.shards = 999
		panel.show_result(false, score, true)
		await get_tree().process_frame
		panel.call("_skip_reveal")
		await get_tree().create_timer(0.3).timeout
		_check_locale(panel, locale)
		panel.queue_free()
		await get_tree().process_frame

		var win_panel: Control = RESULT_SCENE.instantiate() as Control
		add_child(win_panel)
		score.cycles = 1
		win_panel.show_result(true, score, false)
		await get_tree().process_frame
		var win_continue: Button = win_panel.get_node("Actions/Continue") as Button
		_expect_true(not win_continue.visible, "%s hides Continue on a normal settlement" % locale)
		_expect_true(
			(win_panel.get_node("Title") as Label).text == tr("RESULT_ESCAPE"),
			"%s pre-cycle-8 settlement uses the safe-return title" % locale)
		_expect_fits(win_panel.get_node("Title") as Label, "%s safe-return title" % locale)
		_expect_true(
			(win_panel.get_node("Epitaph") as Label).text == tr("STORY_EPITAPH_ESCAPE"),
			"%s safe return shows the ember-keeping epitaph" % locale)
		_expect_fits(
			win_panel.get_node("Epitaph") as Label, "%s safe-return epitaph" % locale)
		win_panel.queue_free()
		await get_tree().process_frame

		var legend_panel: Control = RESULT_SCENE.instantiate() as Control
		add_child(legend_panel)
		score.cycles = 8
		legend_panel.show_result(true, score, false)
		await get_tree().process_frame
		_expect_true(
			(legend_panel.get_node("Title") as Label).text == tr("RESULT_WIN"),
			"%s cycle-8 settlement uses the victory title" % locale)
		_expect_true(
			(legend_panel.get_node("Epitaph") as Label).text == tr("STORY_EPITAPH_WIN"),
			"%s cycle-8 settlement shows the line-joined epitaph" % locale)
		_expect_fits(
			legend_panel.get_node("Epitaph") as Label, "%s victory epitaph" % locale)
		legend_panel.queue_free()
		await get_tree().process_frame

	TranslationServer.set_locale(original_locale)
	if _failed > 0:
		printerr("result-layout test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("result-layout test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _check_locale(panel: Control, locale: String) -> void:
	var title: Label = panel.get_node("Title") as Label
	var epitaph: Label = panel.get_node("Epitaph") as Label
	var detail: Label = panel.get_node("Detail") as Label
	var stamp: Label = panel.get_node("Stamp") as Label
	var hint: Label = panel.get_node("Hint") as Label
	var goal: Label = panel.get_node("Goal") as Label
	var actions: HBoxContainer = panel.get_node("Actions") as HBoxContainer
	var continue_button: Button = panel.get_node("Actions/Continue") as Button
	var retry: Button = panel.get_node("Actions/Retry") as Button
	var shrine: Button = panel.get_node("Actions/Shrine") as Button

	_expect_fits(title, "%s title" % locale)
	_expect_fits(epitaph, "%s closing story line" % locale)
	_expect_true(
		epitaph.text == tr("STORY_EPITAPH_LOSE"),
		"%s defeat shows the debt-passing epitaph" % locale)
	_expect_fits(detail, "%s score table" % locale)
	_expect_fits(hint, "%s record and shards" % locale)
	_expect_fits(goal, "%s purchase goal" % locale)
	_expect_fits(continue_button, "%s Continue button" % locale)
	_expect_fits(retry, "%s Retry button" % locale)
	_expect_fits(shrine, "%s Shrine button" % locale)

	var title_rect: Rect2 = title.get_global_rect()
	var epitaph_rect: Rect2 = epitaph.get_global_rect()
	var detail_rect: Rect2 = detail.get_global_rect()
	var stamp_rect: Rect2 = stamp.get_global_rect()
	var hint_rect: Rect2 = hint.get_global_rect()
	var goal_rect: Rect2 = goal.get_global_rect()
	var actions_rect: Rect2 = actions.get_global_rect()
	_expect_true(
		title_rect.end.y + SAFE_GAP <= detail_rect.position.y,
		"%s gap between title and score table" % locale)
	_expect_true(
		title_rect.end.y <= epitaph_rect.position.y
		and epitaph_rect.end.y <= detail_rect.position.y,
		"%s closing line sits between title and score table" % locale)
	_expect_true(
		detail_rect.end.x + SAFE_GAP <= stamp_rect.position.x,
		"%s gap between score table and rank (%s / %s)" % [
			locale, detail_rect, stamp_rect])
	_expect_true(
		maxf(detail_rect.end.y, stamp_rect.end.y) + SAFE_GAP <= hint_rect.position.y,
		"%s gap between score/rank and record line (%s / %s / %s)" % [
			locale, detail_rect, stamp_rect, hint_rect])
	_expect_true(
		hint_rect.end.y <= goal_rect.position.y,
		"%s record then purchase-goal order" % locale)
	_expect_true(
		goal_rect.end.y + SAFE_GAP <= actions_rect.position.y,
		"%s gap between purchase goal and buttons" % locale)
	_expect_true(
		actions_rect.position.x >= panel.get_global_rect().position.x + SAFE_GAP
		and actions_rect.end.x <= panel.get_global_rect().end.x - SAFE_GAP,
		"%s button row stays inside left/right screen" % locale)
	_expect_true(
		actions_rect.end.y <= panel.get_global_rect().end.y - SAFE_GAP,
		"%s buttons stay on screen" % locale)


func _expect_fits(control: Control, label: String) -> void:
	var minimum: Vector2 = control.get_combined_minimum_size()
	_expect_true(
		minimum.x <= control.size.x + 0.5 and minimum.y <= control.size.y + 0.5,
		"%s (%s / %s)" % [label, minimum, control.size])


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if value:
		return
	_failed += 1
	printerr("  failed: ", label)
