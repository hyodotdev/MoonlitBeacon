class_name ScytheOrbit
extends Node2D

## Eclipse's orbiting scythe blades plus the ring pulse of each sweep tick.
##
## Two crescent blades circle the body continuously so the weapon reads even between
## ticks; `pulse()` fires the expanding ring the arena's timed sweep lands with. One
## node, a few arcs — the same bounded-draw idea as `WeaponRig`.
##
## The pulse fades itself in 0.3s, freezes with the tree under pause/result, and leaves
## with the player on scene change. Inactive (any other hero) it hides and sleeps.
##
## The carried sweep. The same `pulse()` call that lands the ring also starts a
## bright crescent that sweeps from the contact aim across the same travel, sign,
## and span as the held reaper (`WeaponRig`), so the orbit and the hand read as
## one committed cut.

const PULSE_SECONDS: float = 0.30
const BLADES: int = 2
## Sweep travel, degrees. Matches `WeaponRig.SWING_TRAVEL_ECLIPSE`: the crescent
## head crosses the contact aim at t=0 and follows through this far.
const SWEEP_TRAVEL_DEGREES: float = 135.0

var orbit_fraction: float = 0.78
var max_radius: float = 60.0

var _primary: Color = Color(1.0, 0.45, 0.5, 1.0)
var _secondary: Color = Color(1.0, 0.9, 0.9, 1.0)
var _spin: float = 0.0
var _pulse_age: float = 999.0
var _active: bool = false
var _sweep_age: float = 999.0
var _sweep_from: float = 0.0
var _sweep_sign: float = 1.0
var _sweep_span: float = PULSE_SECONDS
## Draw-layer VFX suppression for the motion harness no-VFX pass. Orbit,
## pulse, and sweep draw dark while `pulse()` timing still runs; the physical
## crescent sweep is the held sheet plus the Player's arms.
var _vfx_suppressed: bool = false


func _ready() -> void:
	z_index = 2
	self_modulate = Color(2.4, 2.2, 2.3, 1.0)
	visible = false
	set_process(false)


func configure(primary: Color, secondary: Color) -> void:
	_primary = primary
	_secondary = secondary
	queue_redraw()


func set_active(value: bool) -> void:
	_active = value
	visible = value
	set_process(value)
	if not value:
		_pulse_age = 999.0
		_sweep_age = 999.0
	queue_redraw()


func is_active() -> bool:
	return _active


func set_vfx_suppressed(value: bool) -> void:
	_vfx_suppressed = value
	queue_redraw()


## Fire the ring pulse and, when a contact angle is given, the carried sweep:
## a bright crescent from `from_angle` across the reaper's own travel, sign,
## and span. A call without an angle keeps the legacy ring-only pulse.
func pulse(
	from_angle: float = INF, sweep_sign: float = 1.0,
	sweep_span: float = PULSE_SECONDS
) -> void:
	if not _active:
		return
	_pulse_age = 0.0
	if is_finite(from_angle):
		_sweep_age = 0.0
		_sweep_from = from_angle
		_sweep_sign = 1.0 if sweep_sign >= 0.0 else -1.0
		_sweep_span = maxf(sweep_span, 0.01)
	set_process(true)
	queue_redraw()


## The sweep is still traveling.
func sweep_live() -> bool:
	return _active and _sweep_age >= 0.0 and _sweep_age < _sweep_span


## Current crescent head angle. Starts exactly on the contact aim.
func sweep_head_now() -> float:
	if not sweep_live():
		return _sweep_from
	var progress: float = clampf(_sweep_age / _sweep_span, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - progress, 2.0)
	return _sweep_from + _sweep_sign * deg_to_rad(SWEEP_TRAVEL_DEGREES) * eased


## Swept travel so far, radians from the contact aim. Signed with the cut.
func sweep_travel_now() -> float:
	return sweep_head_now() - _sweep_from


func orbit_radius() -> float:
	var reach: float = 64.0
	var parent: Node = get_parent()
	if parent != null and "attack_range" in parent:
		reach = float(parent.get("attack_range"))
	return minf(reach * orbit_fraction, max_radius)


func _process(delta: float) -> void:
	if not _active:
		set_process(false)
		return
	_spin += delta * 4.6
	_pulse_age += delta
	_sweep_age += delta
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	if _vfx_suppressed:
		return
	var radius: float = orbit_radius()
	var trail := Color(_primary.r, _primary.g, _primary.b, 0.20)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 30, trail, 2.4, false)
	var steel := Color(0.88, 0.90, 1.0, 0.95)
	var edge := Color(_secondary.r, _secondary.g, _secondary.b, 0.9)
	for blade in BLADES:
		var at: Vector2 = Vector2.RIGHT.rotated(
			_spin + TAU * float(blade) / float(BLADES)) * radius
		var tangent: float = at.angle() + PI * 0.5
		draw_line(at - Vector2.RIGHT.rotated(tangent) * 5.0,
			at + Vector2.RIGHT.rotated(tangent) * 5.0, steel, 2.0, false)
		draw_arc(at, 4.6, tangent - 1.2, tangent + 1.2, 8, edge, 1.4, false)
	if _pulse_age < PULSE_SECONDS:
		var progress: float = _pulse_age / PULSE_SECONDS
		draw_arc(Vector2.ZERO, radius * (0.6 + 0.55 * progress), 0.0, TAU, 30,
			Color(_primary.r, _primary.g, _primary.b, 0.55 * (1.0 - progress)),
			2.6, false)
	if sweep_live():
		var head: float = sweep_head_now()
		var sweep_fade: float = 1.0 - clampf(_sweep_age / _sweep_span, 0.0, 1.0)
		var head_light := Color(1.0, 0.98, 1.0, 0.95 * sweep_fade)
		var sweep_trail := Color(
			_primary.r, _primary.g, _primary.b, 0.65 * sweep_fade)
		var tail: float = head - _sweep_sign * 0.7
		draw_arc(Vector2.ZERO, radius, minf(head, tail), maxf(head, tail), 14,
			sweep_trail, 3.0, false)
		var at: Vector2 = Vector2.RIGHT.rotated(head) * radius
		draw_circle(at, 3.0, head_light)
		draw_circle(at, 1.5,
			Color(_secondary.r, _secondary.g, _secondary.b, 0.9 * sweep_fade))
