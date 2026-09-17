class_name MoonfireAura
extends Node2D

## Marker that orbits the player while moonfire is awake.
##
## The blue ring is the current power; the gold ring and embers show that a
## beacon has locked that power in. Drawn on integer coordinates with no
## texture so it stays sharp on a small screen.

const INNER_RADIUS: float = 17.0
const OUTER_RADIUS: float = 23.0
const MOON_BLUE: Color = Color(0.35, 0.78, 1.0, 1.0)
const MOON_GOLD: Color = Color(1.0, 0.77, 0.28, 1.0)
const REDRAW_INTERVAL: float = 1.0 / 15.0

var _active: bool = false
var _locked: bool = false
var _spin: float = 0.0
var _pulse: float = 0.0
var _redraw_left: float = 0.0


func _ready() -> void:
	z_index = 2
	visible = _active
	set_process(_active)


## Updates both the active state and the beacon-locked state.
func set_active(value: bool, locked: bool = false) -> void:
	if _active == value and _locked == locked:
		return
	_active = value
	_locked = locked
	visible = value
	set_process(value)
	queue_redraw()


func _process(delta: float) -> void:
	_spin = fposmod(_spin + delta * (2.4 if _locked else 1.8), TAU)
	_pulse += delta * (7.0 if _locked else 4.8)
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left += REDRAW_INTERVAL
		queue_redraw()


## Two rings flowing opposite ways, plus embers on the orbit.
func _draw() -> void:
	if not _active:
		return

	var beat: float = 0.5 + 0.5 * sin(_pulse)
	var blue_alpha: float = 0.58 + 0.20 * beat
	var gold_alpha: float = (0.72 + 0.24 * beat) if _locked else 0.46
	var width: float = 2.0 if _locked else 1.0

	draw_arc(Vector2.ZERO, INNER_RADIUS, 0.0, TAU, 32,
		Color(MOON_BLUE.r, MOON_BLUE.g, MOON_BLUE.b, 0.16 + 0.08 * beat),
		width, false)
	draw_arc(Vector2.ZERO, INNER_RADIUS, _spin, _spin + 2.2, 12,
		Color(MOON_BLUE.r, MOON_BLUE.g, MOON_BLUE.b, blue_alpha),
		width, false)
	draw_arc(Vector2.ZERO, OUTER_RADIUS, -_spin - 2.5, -_spin - 0.2, 12,
		Color(MOON_GOLD.r, MOON_GOLD.g, MOON_GOLD.b, gold_alpha),
		width, false)

	if _locked:
		draw_arc(Vector2.ZERO, OUTER_RADIUS + 3.0, 0.0, TAU, 36,
			Color(MOON_GOLD.r, MOON_GOLD.g, MOON_GOLD.b, 0.12 + 0.10 * beat),
			2.0, false)

	var ember_count: int = 6 if _locked else 4
	for i in ember_count:
		var angle: float = _spin + TAU * float(i) / float(ember_count)
		var radius: float = OUTER_RADIUS + (3.0 if i % 2 == 0 else 0.0)
		var at: Vector2 = (Vector2.RIGHT.rotated(angle) * radius).round()
		var tone: Color = MOON_GOLD if _locked or i % 2 == 1 else MOON_BLUE
		var ember_radius: int = 3 if _locked and i % 2 == 0 else 2
		_draw_ember(at, ember_radius, tone, beat)


func _draw_ember(at: Vector2, radius: int, tone: Color, beat: float) -> void:
	var glow_size: int = radius + 2 + roundi(beat)
	draw_rect(Rect2(
		at - Vector2(glow_size, glow_size),
		Vector2(glow_size * 2 + 1, glow_size * 2 + 1)),
		Color(tone.r, tone.g, tone.b, 0.10), true)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0, -radius),
		at + Vector2(radius, 0),
		at + Vector2(0, radius),
		at + Vector2(-radius, 0),
	]), Color(tone.r, tone.g, tone.b, 0.92))
