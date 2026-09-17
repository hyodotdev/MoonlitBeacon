class_name MoonEmber
extends Node2D

## Moon ember left when a spirit scatters.
##
## It pops like loot for a moment, then must be picked up at the player's feet.
## Distant embers must not later magnet across the screen.

signal collected(charge: float, at: Vector2)

const NEAR_SEEK_DELAY: float = 0.8
## A little narrower than a hero cell. It will not auto-pull from across the field.
const SEEK_RADIUS: float = 22.0
const COLLECT_RADIUS: float = 7.0

const TOSS_SPEED_MIN: float = 38.0
const TOSS_SPEED_MAX: float = 62.0
const TOSS_FRICTION: float = 92.0
const MAGNET_ACCELERATION: float = 560.0
const MAGNET_SPEED: float = 260.0
const REDRAW_INTERVAL: float = 1.0 / 15.0
const UPDATE_INTERVAL: float = 1.0 / 15.0

const MOON_BLUE: Color = Color(0.35, 0.76, 1.0, 1.0)
const MOON_GOLD: Color = Color(1.0, 0.76, 0.25, 1.0)

var charge: float = 1.0
var target: Node2D = null
var elite: bool = false:
	set(value):
		elite = value
		if is_inside_tree():
			queue_redraw()

var _age: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _floating_position: Vector2 = Vector2.ZERO
var _taken: bool = false
var _redraw_left: float = 0.0
var _update_left: float = 0.0
var _update_elapsed: float = 0.0


func _ready() -> void:
	z_index = 4
	add_to_group("moon_embers")
	_floating_position = global_position
	_redraw_left = randf() * REDRAW_INTERVAL
	_update_left = randf() * UPDATE_INTERVAL
	_velocity = Vector2.RIGHT.rotated(randf() * TAU) \
		* randf_range(TOSS_SPEED_MIN, TOSS_SPEED_MAX)


func _physics_process(delta: float) -> void:
	if _taken:
		return
	_update_left -= delta
	_update_elapsed += delta
	if _update_left > 0.0:
		return
	while _update_left <= 0.0:
		_update_left += UPDATE_INTERVAL
	var step: float = _update_elapsed
	_update_elapsed = 0.0

	_age += step
	var seeking: bool = false
	var offset: Vector2 = Vector2.ZERO
	var offset_sq: float = 0.0
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		offset = target.global_position - _floating_position
		offset_sq = offset.length_squared()
		seeking = _age >= NEAR_SEEK_DELAY \
			and offset_sq <= SEEK_RADIUS * SEEK_RADIUS

	if seeking:
		if offset_sq <= COLLECT_RADIUS * COLLECT_RADIUS:
			_collect()
			return
		var distance: float = sqrt(offset_sq)
		var toward: Vector2 = offset / distance
		_velocity = _velocity.move_toward(
			toward * MAGNET_SPEED, MAGNET_ACCELERATION * step)
	else:
		_velocity = _velocity.move_toward(Vector2.ZERO, TOSS_FRICTION * step)

	var travel: Vector2 = _velocity * step
	if seeking and travel.length_squared() >= offset_sq:
		_floating_position = target.global_position
		global_position = _floating_position.round()
		_collect()
		return

	_floating_position += travel
	# Snap to integer pixels so nearest-neighbor scale does not jitter the diamond edges.
	global_position = _floating_position.round()
	_redraw_left -= step
	if _redraw_left <= 0.0:
		while _redraw_left <= 0.0:
			_redraw_left += REDRAW_INTERVAL
		queue_redraw()


## Emit the collect signal first, then puff out and vanish.
func _collect() -> void:
	if _taken:
		return
	_taken = true
	set_physics_process(false)
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	remove_from_group("moon_embers")
	collected.emit(charge, global_position)

	var pop: Tween = create_tween()
	pop.set_parallel(true)
	pop.tween_property(self, "scale", Vector2(2.0, 2.0), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(self, "modulate:a", 0.0, 0.14)
	pop.chain().tween_callback(queue_free)


## On a terrain crossing, settle uneaten embers into the gauge.
func drain_for_transition() -> float:
	if _taken:
		return 0.0
	_taken = true
	set_physics_process(false)
	remove_from_group("moon_embers")
	var amount: float = charge
	queue_free()
	return amount


## Pixel flame rising on top of a glow.
##
## As a diamond it read as a gem or XP pickup. This item is a moon ember —
## collect ten to awaken a weapon — so even at this size the tip must flicker
## like a flame.
func _draw() -> void:
	var tone: Color = MOON_GOLD if elite else MOON_BLUE
	var radius: int = 7 if elite else 5
	var beat: float = 0.5 + 0.5 * sin(_age * (8.0 if elite else 6.0))

	draw_colored_polygon(_flame(radius + 2),
		Color(tone.r, tone.g, tone.b, 0.22 + 0.08 * beat))
	draw_colored_polygon(_flame(radius),
		tone.lerp(Color(1.0, 1.0, 0.88, 1.0), 0.14 + 0.12 * beat))
	draw_circle(Vector2(0, 1), 1.5 if elite else 1.0,
		Color(1.0, 1.0, 0.9, 0.92))
	draw_circle(Vector2(2 if beat > 0.5 else -2, -radius - 3), 1.0,
		Color(tone.r, tone.g, tone.b, 0.5 + 0.4 * beat))


func _flame(radius: int) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -radius - 2),
		Vector2(radius - 2, -1),
		Vector2(radius, radius / 3.0),
		Vector2(radius / 3.0, radius),
		Vector2(0, radius - 2),
		Vector2(-radius / 2.0, radius),
		Vector2(-radius, radius / 4.0),
		Vector2(-radius / 3.0, -radius / 2.0),
	])
