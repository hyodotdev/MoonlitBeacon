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

const PULSE_SECONDS: float = 0.30
const BLADES: int = 2

var orbit_fraction: float = 0.78
var max_radius: float = 60.0

var _primary: Color = Color(1.0, 0.45, 0.5, 1.0)
var _secondary: Color = Color(1.0, 0.9, 0.9, 1.0)
var _spin: float = 0.0
var _pulse_age: float = 999.0
var _active: bool = false


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
	queue_redraw()


func is_active() -> bool:
	return _active


func pulse() -> void:
	if not _active:
		return
	_pulse_age = 0.0
	set_process(true)
	queue_redraw()


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
	queue_redraw()


func _draw() -> void:
	if not _active:
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
