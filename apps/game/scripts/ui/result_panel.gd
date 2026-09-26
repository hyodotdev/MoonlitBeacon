extends Control

## Panel that appears when a run ends. Win or lose, the same one.
##
## Only the copy changes. Win is yellow light, lose is red.
## Chapter 14: score lines count up one by one, then the rank stamp lands.

signal restart_requested
signal shrine_requested
## Spend a coin and continue in place.
signal continue_requested
## No coins: end this run and go to the shop to buy coins for the next one.
signal continue_purchase_requested
## Want to leave a name on the board. The button shows only for a ranking score.
signal record_requested
## Score total and rank stamp are both revealed. Follow-up copy opens only after this.
signal reveal_finished

const WIN_COLOR: Color = Color(1, 0.95, 0.82, 1)
const LOSE_COLOR: Color = Color(1, 0.78, 0.74, 1)
## Return before cycle eight is a safe settlement; from cycle eight it is a kept-promise win.
const LEGEND_CYCLE: int = 8

## Color differs per rank. S is gold, D is ash.
const RANK_COLORS: Dictionary = {
	"S": Color(1, 0.86, 0.5, 1),
	"A": Color(0.86, 0.93, 1, 1),
	"B": Color(0.76, 0.86, 0.78, 1),
	"C": Color(0.8, 0.78, 0.72, 1),
	"D": Color(0.62, 0.62, 0.66, 1),
}

## Time for one line to count from 0 to its value.
const ROW_SECONDS: float = 0.28
## Pause before moving to the next line.
const ROW_GAP: float = 0.08
## The total counts up a little more slowly.
const SUM_SECONDS: float = 0.42

@onready var _title: Label = $Title
@onready var _epitaph: Label = $Epitaph
@onready var _detail: Label = $Detail
@onready var _stamp: Label = $Stamp
@onready var _hint: Label = $Hint
@onready var _goal: Label = $Goal
@onready var _actions: HBoxContainer = $Actions
@onready var _continue: Button = $Actions/Continue
@onready var _retry: Button = $Actions/Retry
@onready var _shrine: Button = $Actions/Shrine
@onready var _record: Button = $Actions/Record

var _accepting: bool = false

## Numbers currently on screen. The tween edits these and `_redraw()` draws.
var _rows: Array = []
var _shown: Array[int] = []
var _sum_shown: int = 0
var _score: Score = null
var _is_best: bool = false
var _reveal: Tween = null
var _reveal_finished: bool = false
var _overlay_blocked: bool = false


func _ready() -> void:
	visible = false
	_continue.pressed.connect(_request_continue)
	_retry.pressed.connect(_request_restart)
	_shrine.pressed.connect(_request_shrine)
	_record.pressed.connect(_request_record)


func show_result(
	won: bool, score: Score, is_best: bool, can_record: bool = false
) -> void:
	_accepting = false
	_reveal_finished = false
	_overlay_blocked = false
	_set_actions_enabled(false)
	_score = score
	_is_best = is_best
	# Submit button shows only for a ranking score. Submit is optional —
	# asking for a name when they pressed play-again is just annoying.
	_record.visible = can_record
	# A run they returned from and settled is already over. Showing paid
	# continue then treats a win like a death, so it is only on a loss.
	_continue.visible = not won
	_title.text = tr("RESULT_WIN") \
		if won and score.cycles >= LEGEND_CYCLE \
		else (tr("RESULT_ESCAPE") if won else tr("RESULT_LOSE"))
	_title.add_theme_color_override("font_color", WIN_COLOR if won else LOSE_COLOR)
	# One closing story line under the title. Same outcome split as the title:
	# kept-promise win, safe early return, or a debt passed to the next night.
	_epitaph.text = tr("STORY_EPITAPH_WIN") \
		if won and score.cycles >= LEGEND_CYCLE \
		else (tr("STORY_EPITAPH_ESCAPE") if won else tr("STORY_EPITAPH_LOSE"))

	# Every line holds its place from the start; only the numbers count from 0.
	#
	# **Adding** lines one by one grows label height and overlaps other things.
	# That was only seen after rendering a fully filled screen, so fill from the start here.
	_rows = score.lines()
	_shown = []
	_shown.resize(_rows.size())
	_sum_shown = 0
	_redraw()

	_stamp.text = score.rank()
	_stamp.add_theme_color_override("font_color", RANK_COLORS.get(score.rank(), LOSE_COLOR))
	_stamp.visible = false

	_refresh_persistence_summary()
	_refresh_purchase_goal()
	_refresh_continue()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.5)

	_reveal = create_tween()
	_reveal.tween_interval(0.35)                 # hold still while the panel appears
	for i in _rows.size():
		_reveal.tween_method(_set_row.bind(i), 0, int(_rows[i][1]), ROW_SECONDS)
		_reveal.tween_interval(ROW_GAP)
	_reveal.tween_method(_set_sum, 0, score.total(), SUM_SECONDS)
	_reveal.tween_callback(_finish_reveal)

	# A finger already down when the panel appears would restart immediately.
	# Wait one beat, then accept.
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree():
		return
	_accepting = true


## After reveal, if storage recovers and shard/new-record settlement finishes,
## fix only the numbers. Calling `show_result()` again would replay the reveal
## and the input delay.
func refresh_persistence(is_best: bool, run_shards: int) -> void:
	if _score == null:
		return
	_is_best = _is_best or is_best
	_score.shards = maxi(run_shards, 0)
	_refresh_persistence_summary()
	_refresh_purchase_goal()


func _refresh_persistence_summary() -> void:
	if _score == null:
		return
	var best: String = tr("RESULT_BEST_NEW") \
		if _is_best else tr("RESULT_BEST") % [Records.best_score, Records.best_rank]
	# Show shards earned too. **Unseen means they don't know they collected** —
	# it is the only thing that survives death, and if it is not on screen
	# there is no reason to start the next run.
	var balance: String = tr("RESULT_SHARD_BALANCE") % [_score.shards, Vault.shards]
	_hint.text = "%s   %s" % [best, balance]


func _refresh_purchase_goal() -> void:
	var next: Dictionary = Vault.next_purchase()
	if next.is_empty():
		_goal.text = tr("RESULT_GOAL_COMPLETE")
		_goal.add_theme_color_override("font_color", Color(0.72, 0.9, 1.0, 1))
		return
	var cost: int = int(next.get("cost", 0))
	var name: String = str(next.get("name", ""))
	var accent: Color = next.get("accent", Color(0.96, 0.82, 0.5, 1))
	_goal.add_theme_color_override("font_color", accent)
	if Vault.shards >= cost:
		_goal.text = tr("RESULT_GOAL_READY") % name
	else:
		_goal.text = tr("RESULT_GOAL_PROGRESS") % [name, cost - Vault.shards]


## One line's number is counting up.
func _set_row(value: int, index: int) -> void:
	_shown[index] = value
	_redraw()


func _set_sum(value: int) -> void:
	_sum_shown = value
	_redraw()


func _redraw() -> void:
	var out: PackedStringArray = []
	for i in _rows.size():
		out.append("%s   %d" % [_rows[i][0], _shown[i]])
	out.append("%s   %d" % [tr("SCORE_TOTAL"), _sum_shown])
	_detail.text = "\n".join(out)


## Appear large like a stamp, then shrink into place.
##
## Without `pivot_offset` the origin is top-left, so it stretches down-right then comes back.
func _stamp_in() -> void:
	_stamp.visible = true
	_stamp.pivot_offset = _stamp.size * 0.5
	_stamp.scale = Vector2.ONE * 2.4
	create_tween().tween_property(_stamp, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _finish_reveal() -> void:
	if _reveal_finished:
		return
	_reveal_finished = true
	_reveal = null
	_stamp_in()
	_set_actions_enabled(not _overlay_blocked)
	reveal_finished.emit()


## Wind the reveal to the end. From the second run they have already seen it.
func _skip_reveal() -> void:
	_reveal.kill()
	for i in _rows.size():
		_shown[i] = int(_rows[i][1])
	_sum_shown = _score.total()
	_redraw()
	_finish_reveal()


## While a higher modal is over the result, lock every result choice behind it.
##
## `_accepting` is owned by the reveal timer. Close the modal without a choice
## and restore the original result immediately; held-touch release is filtered
## separately by the modal above.
func set_overlay_blocked(value: bool) -> void:
	_overlay_blocked = value
	if not visible:
		return
	_set_actions_enabled(_reveal_finished and not _overlay_blocked)


func _set_actions_enabled(value: bool) -> void:
	_continue.disabled = not value or not _continue.visible
	_retry.disabled = not value
	_shrine.disabled = not value
	_record.disabled = not value
	_actions.modulate.a = 1.0 if value else 0.35
	# A pad with no pointer must still be able to leave the result screen.
	# Default is safe play-again, not paid continue; left/right reach the other choices.
	if value:
		_retry.grab_focus()


## Arcade continue. If they have coins, show how many remain; if not, the
## button is go-buy. **Do not put a price on the button** — the store sets
## display price per region, so they read it on the shop screen.
func _refresh_continue() -> void:
	var coins: int = Vault.continue_coins
	if coins > 0:
		_continue.text = tr("RESULT_CONTINUE_COINS") % coins
	else:
		_continue.text = tr("RESULT_CONTINUE_BUY")


func _request_continue() -> void:
	if not _accepting or _overlay_blocked or _continue.disabled:
		return
	_accepting = false
	if Vault.continue_coins > 0:
		continue_requested.emit()
		return
	continue_purchase_requested.emit()


## Restore the result screen when continue did not go through (balance lost,
## save failed). The reveal already finished, so only re-accept a choice.
func reopen_after_failed_continue() -> void:
	visible = true
	_refresh_continue()
	_set_actions_enabled(not _overlay_blocked)
	_accepting = true


func _request_restart() -> void:
	if not _accepting or _overlay_blocked or _retry.disabled:
		return
	_accepting = false
	restart_requested.emit()


func _request_shrine() -> void:
	if not _accepting or _overlay_blocked or _shrine.disabled:
		return
	_accepting = false
	shrine_requested.emit()


func _request_record() -> void:
	if not _accepting or _overlay_blocked or _record.disabled:
		return
	_accepting = false
	record_requested.emit()


## Tap during the reveal to wind the count to the end. After the reveal, the
## two buttons take the choice.
##
## `_unhandled_input` alone **cannot skip the reveal on device.** The virtual
## stick covers half the screen with `mouse_filter = STOP` and takes the
## touch first, so unhandled input never reaches here. After complete, a tap
## on empty space is deliberately a no-op so they do not pick `Retry` or
## `Shrine` by accident.
##
## On desktop any key wakes `_unhandled_input`, so **PC testing never sees
## it and only the phone is blocked.** That is how it was actually missed.
func _gui_input(event: InputEvent) -> void:
	_try_accept(event)


## Keyboard does not go through GUI picking. That path arrives here.
func _unhandled_input(event: InputEvent) -> void:
	_try_accept(event)


func _try_accept(event: InputEvent) -> void:
	if not _accepting or not visible or _overlay_blocked:
		return
	var pressed: bool = false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventKey:
		var key: InputEventKey = event
		pressed = key.pressed and not key.echo
	elif event is InputEventJoypadButton:
		pressed = (event as InputEventJoypadButton).pressed
	if not pressed:
		return

	# If the reveal is running, skip that first. This tap does not restart.
	if _reveal != null:
		get_viewport().set_input_as_handled()
		_skip_reveal()
	# After reveal, only a focused real button is handled. Treat any key as
	# play-again and a pad restarts the run before continue/shrine/records
	# can be chosen.
