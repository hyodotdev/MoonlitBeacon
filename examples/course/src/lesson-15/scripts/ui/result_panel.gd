## Win/lose panel: ticks the score up line by line, stamps the rank, then
## offers one guarded restart. Skip fast-forwards the reveal, never the run.
extends Control

signal restart_requested

const ROW_SECONDS: float = 0.5
const ROW_GAP: float = 0.15
const SUM_SECONDS: float = 0.8

@onready var _title: Label = $Panel/Title
@onready var _rows: Array = [$Panel/Row0, $Panel/Row1, $Panel/Row2]
@onready var _sum: Label = $Panel/Sum
@onready var _stamp: Label = $Panel/Stamp
@onready var _skip: Button = $Panel/Skip
@onready var _restart: Button = $Panel/Restart

var _reveal: Tween = null
var _score: Score = null
var _done: bool = false


func _ready() -> void:
	_restart.pressed.connect(_on_restart_pressed)
	_skip.pressed.connect(_on_skip_pressed)
	Settings.changed.connect(_redraw_static)
	_redraw_static()


func _redraw_static() -> void:
	_skip.text = tr("SKIP")
	_restart.text = tr("RESTART")
	if _score != null:
		_title.text = tr("RESULT_WIN") if _score.won else tr("RESULT_LOSE")
		_redraw_rows()


func show_result(score: Score) -> void:
	visible = true
	_score = score
	_done = false
	_title.text = tr("RESULT_WIN") if score.won else tr("RESULT_LOSE")
	_stamp.text = ""
	_sum.text = "0"
	for i in _rows.size():
		(_rows[i] as Label).text = "%s  0" % _row_name(i)
	_restart.disabled = true
	_skip.disabled = false
	_reveal = create_tween()
	for i in _rows.size():
		_reveal.tween_method(_set_row.bind(i), 0.0, float(_score.lines()[i][1]), ROW_SECONDS)
		_reveal.tween_interval(ROW_GAP)
	_reveal.tween_method(_set_sum, 0.0, float(_score.total()), SUM_SECONDS)
	_reveal.tween_callback(_finish_reveal)


func is_accepting() -> bool:
	return visible and not _restart.disabled


func is_revealed() -> bool:
	return _done


func _row_name(index: int) -> String:
	return tr(["SCORE_BEACONS", "SCORE_TIME", "SCORE_ESCAPE"][index])


func _set_row(shown: float, index: int) -> void:
	(_rows[index] as Label).text = "%s  %d" % [_row_name(index), int(shown)]


func _redraw_rows() -> void:
	for i in _rows.size():
		var shown: int = int(_score.lines()[i][1]) if _done else 0
		(_rows[i] as Label).text = "%s  %d" % [_row_name(i), shown]
	if _done:
		_sum.text = "%d" % _score.total()
		_stamp.text = _score.rank()


func _set_sum(shown: float) -> void:
	_sum.text = "%d" % int(shown)


func _finish_reveal() -> void:
	if _done:
		return
	_done = true
	for i in _rows.size():
		_set_row(float(_score.lines()[i][1]), i)
	_set_sum(float(_score.total()))
	_stamp.text = _score.rank()
	_skip.disabled = true
	_restart.disabled = false


func _on_skip_pressed() -> void:
	if _done:
		return
	if _reveal and _reveal.is_valid():
		_reveal.kill()
	_finish_reveal()


func _on_restart_pressed() -> void:
	restart_requested.emit()
