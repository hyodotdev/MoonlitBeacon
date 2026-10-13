## Run readout: hearts, lit beacons, and the countdown. Decides nothing.
extends Control

const CALM_COLOR: Color = Color(1, 1, 1, 1)
const URGENT_COLOR: Color = Color(1, 0.35, 0.35, 1)
const URGENT_SECONDS: float = 15.0
const DIM_COLOR: Color = Color(0.55, 0.55, 0.6, 1)

@onready var _hearts: Label = $Hearts
@onready var _beacons: Label = $Beacons
@onready var _time: Label = $Time
@onready var _dash: Label = $Dash

var _health: int = 0
var _lit: int = 0
var _total: int = 0


func set_health(value: int) -> void:
	_health = value
	_hearts.text = "HP %d" % value


func set_beacons(lit: int, total: int) -> void:
	_lit = lit
	_total = total
	_beacons.text = "Beacons %d/%d" % [lit, total]


func set_time_left(seconds: float) -> void:
	## ceilf: with floor, 89.99 would already read 1:29 at the start.
	## maxf: a negative would print past zero when time runs out.
	var whole: int = int(ceilf(maxf(seconds, 0.0)))
	_time.text = "%d:%02d" % [whole / 60, whole % 60]
	_time.add_theme_color_override(
		"font_color", URGENT_COLOR if seconds <= URGENT_SECONDS else CALM_COLOR)


func set_dash_ready(ready: bool) -> void:
	_dash.text = "Dash ready" if ready else "Dash ..."
	_dash.add_theme_color_override("font_color", CALM_COLOR if ready else DIM_COLOR)
