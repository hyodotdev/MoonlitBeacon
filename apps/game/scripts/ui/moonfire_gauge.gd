class_name MoonfireGauge
extends Control

## Procedural ten-cell gauge for moonfire charge.
##
## Cell count reads at a glance in combat instead of a number. Active is blue;
## beacon-locked pulses gold so the held reward is obvious.

const CELL_COUNT: int = 10
const CELL_SIZE: Vector2 = Vector2(8, 7)
const CELL_GAP: int = 2
const INNER_SIZE: Vector2 = Vector2(6, 5)
const NATURAL_SIZE: Vector2 = Vector2(102, 13)

const TRACK: Color = Color(0.055, 0.075, 0.13, 0.92)
const EMPTY: Color = Color(0.16, 0.21, 0.31, 0.92)
const MOON_BLUE: Color = Color(0.33, 0.76, 1.0, 1.0)
const MOON_GOLD: Color = Color(1.0, 0.75, 0.25, 1.0)
const REDRAW_INTERVAL: float = 1.0 / 15.0

var _ratio: float = 0.0
var _active: bool = false
var _locked: bool = false
var _pulse: float = 0.0
var _redraw_left: float = 0.0


func _ready() -> void:
	custom_minimum_size = NATURAL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(_active or _locked)
	queue_redraw()


## Applies charge plus the current active and locked states in one call.
func set_state(ratio: float, active: bool, locked: bool) -> void:
	var next_ratio: float = clampf(ratio, 0.0, 1.0)
	if is_equal_approx(_ratio, next_ratio) \
			and _active == active and _locked == locked:
		return
	_ratio = next_ratio
	_active = active
	_locked = locked
	set_process(active or locked)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta * (7.0 if _locked else 5.0)
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left += REDRAW_INTERVAL
		queue_redraw()


func _draw() -> void:
	var total_width: int = int(CELL_SIZE.x) * CELL_COUNT \
		+ CELL_GAP * (CELL_COUNT - 1)
	var start: Vector2 = Vector2(
		roundf((size.x - float(total_width)) * 0.5),
		roundf((size.y - CELL_SIZE.y) * 0.5))
	var frame: Rect2 = Rect2(
		start - Vector2(2, 2),
		Vector2(total_width + 4, int(CELL_SIZE.y) + 4))
	draw_rect(frame, TRACK, true)

	var beat: float = 0.5 + 0.5 * sin(_pulse)
	var tone: Color = MOON_GOLD if _locked else MOON_BLUE
	var strength: float = 0.58
	if _active:
		strength = 0.78 + 0.20 * beat
	if _locked:
		strength = 0.86 + 0.14 * beat

	if _active or _locked:
		draw_rect(frame.grow(1.0),
			Color(tone.r, tone.g, tone.b, 0.08 + 0.08 * beat), true)
		draw_rect(frame, TRACK, true)

	for i in CELL_COUNT:
		var cell_at: Vector2 = start + Vector2(
			i * (int(CELL_SIZE.x) + CELL_GAP), 0)
		var cell: Rect2 = Rect2(cell_at, CELL_SIZE)
		draw_rect(cell, EMPTY, true)

		var amount: float = clampf(_ratio * float(CELL_COUNT) - float(i), 0.0, 1.0)
		var fill_width: int = clampi(
			roundi(INNER_SIZE.x * amount), 0, int(INNER_SIZE.x))
		if fill_width <= 0:
			continue

		var fill: Rect2 = Rect2(
			cell_at + Vector2.ONE,
			Vector2(fill_width, INNER_SIZE.y))
		draw_rect(fill, Color(tone.r, tone.g, tone.b, strength), true)

		# Light the top pixel so a tiny cell reads as light, not a flat bar.
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, 1)),
			Color(1.0, 1.0, 0.88, strength), true)
