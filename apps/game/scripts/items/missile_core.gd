extends Area2D

## Moonlight core dropped when a spirit is slain.
##
## A normal core must be picked up at the player's feet. A core ejected by a
## hit lasts only 9 seconds. Detection stays locked for 0.75 seconds after
## ejection so overlapping the player does not auto-collect it.

signal collected(ejected: bool)
signal expired(ejected: bool)

const REGULAR_LIFETIME: float = 12.0
const EJECTED_LIFETIME: float = 9.0
const URGENT_AT: float = 3.0
const ARM_DELAY: float = 0.75
const FLING: float = 78.0
const FLING_TIME: float = 0.42
## A little narrower than a hero cell. It will not cross the screen from far away.
const MAGNET_RANGE: float = 22.0
const MAGNET_SPEED: float = 118.0
const RECOVERY_TINT: Color = Color(1.35, 0.54, 0.22, 1.0)
const RECOVERY_RING: Color = Color(1.0, 0.24, 0.08, 0.92)
const RECOVERY_GLOW: Color = Color(1.0, 0.57, 0.16, 0.28)

var ejected: bool = false
var target: Node2D = null
var bounds: Rect2 = Rect2()
var terrain_room: Room = null

var _left: float = REGULAR_LIFETIME
var _beat: float = 0.0
var _taken: bool = false
var _armed: bool = true
var _transition_paused: bool = false
var _toss: Tween = null

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	z_index = 4
	add_to_group("missile_cores")
	collision_layer = 0
	collision_mask = 2
	_left = EJECTED_LIFETIME if ejected else REGULAR_LIFETIME
	_armed = not ejected
	monitoring = _armed
	body_entered.connect(_on_body_entered)

	if ejected:
		_sprite.modulate = RECOVERY_TINT
		_fling()
		get_tree().create_timer(ARM_DELAY, false).timeout.connect(_arm)
	else:
		scale = Vector2(0.35, 0.35)
		var appear: Tween = create_tween()
		appear.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		appear.tween_property(self, "scale", Vector2.ONE, 0.22)


func _fling() -> void:
	var destination: Vector2 = position \
		+ Vector2.RIGHT.rotated(randf() * TAU) * FLING
	if bounds.has_area():
		destination.x = clampf(
			destination.x, bounds.position.x + 12.0, bounds.end.x - 12.0)
		destination.y = clampf(
			destination.y, bounds.position.y + 12.0, bounds.end.y - 12.0)
	if terrain_room != null and is_instance_valid(terrain_room):
		destination = terrain_room.nearest_clear(destination, 12.0)
	_toss = create_tween()
	_toss.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toss.tween_property(self, "position", destination, FLING_TIME)


func _arm() -> void:
	if _taken or not is_inside_tree():
		return
	_armed = true
	if not _transition_paused:
		set_deferred("monitoring", true)


func _process(delta: float) -> void:
	_beat += delta
	_left -= delta
	_sprite.frame = int(_beat * 8.0) % 4
	_sprite.position.y = -2.0 + sin(_beat * 5.0) * 1.5
	if ejected:
		queue_redraw()
	if _left <= 0.0 and not _taken:
		_expire()
		return

	var urgency: float = 1.0
	if _left <= URGENT_AT:
		urgency = 0.38 + 0.62 * (0.5 + 0.5 * sin(_beat * 18.0))
	modulate.a = urgency


func _draw() -> void:
	if not ejected:
		return
	var center: Vector2 = Vector2(0.0, -2.0)
	var pulse: float = 0.5 + 0.5 * sin(_beat * 8.0)
	var ring_radius: float = 13.0 + 2.5 * pulse
	draw_circle(center, 10.0 + 3.0 * pulse, RECOVERY_GLOW)
	draw_arc(center, ring_radius, 0.0, TAU, 32, RECOVERY_RING, 2.0, true)
	var life_ratio: float = clampf(_left / EJECTED_LIFETIME, 0.0, 1.0)
	draw_arc(
		center,
		18.0,
		-PI * 0.5,
		-PI * 0.5 + TAU * life_ratio,
		32,
		Color(1.0, 0.76, 0.24, 0.96),
		2.5,
		true)


func _physics_process(delta: float) -> void:
	if _taken or not _armed or target == null or not is_instance_valid(target):
		return
	var distance: float = global_position.distance_to(target.global_position)
	if distance > MAGNET_RANGE:
		return
	if distance <= 10.0:
		_collect()
		return
	global_position = global_position.move_toward(
		target.global_position, MAGNET_SPEED * delta)


func remaining_seconds() -> float:
	return maxf(_left, 0.0)


func is_armed() -> bool:
	return _armed


func set_transition_paused(paused: bool) -> void:
	if _taken:
		return
	_transition_paused = paused
	# The post-hit fling Tween also keeps moving the position. Pausing only
	# process/physics would freeze the capture JSON while the core still
	# moves, so pause the tween too.
	if _toss != null and _toss.is_valid():
		if paused:
			_toss.pause()
		else:
			_toss.play()
	set_process(not paused)
	set_physics_process(not paused)
	if paused:
		set_deferred("monitoring", false)
	elif _armed:
		set_deferred("monitoring", true)


func shift_for_transition(offset: Vector2, next_bounds: Rect2) -> void:
	if _taken:
		return
	if _toss != null and _toss.is_valid():
		_toss.kill()
	bounds = next_bounds
	position += offset
	if bounds.has_area():
		position.x = clampf(
			position.x, bounds.position.x + 12.0, bounds.end.x - 12.0)
		position.y = clampf(
			position.y, bounds.position.y + 12.0, bounds.end.y - 12.0)


func set_terrain_room(room: Room) -> void:
	terrain_room = room
	if terrain_room != null and is_instance_valid(terrain_room):
		position = terrain_room.nearest_clear(position, 12.0)


func _on_body_entered(_body: Node2D) -> void:
	if _armed:
		_collect()


func _collect() -> void:
	if _taken:
		return
	_taken = true
	set_deferred("monitoring", false)
	set_physics_process(false)
	collected.emit(ejected)
	var pop: Tween = create_tween()
	pop.set_parallel(true)
	pop.tween_property(self, "scale", Vector2(1.8, 1.8), 0.18)
	pop.tween_property(self, "modulate:a", 0.0, 0.18)
	pop.chain().tween_callback(queue_free)


func _expire() -> void:
	_taken = true
	set_deferred("monitoring", false)
	set_physics_process(false)
	expired.emit(ejected)
	var out: Tween = create_tween()
	out.set_parallel(true)
	out.tween_property(self, "scale", Vector2(0.2, 0.2), 0.24)
	out.tween_property(self, "modulate:a", 0.0, 0.24)
	out.chain().tween_callback(queue_free)
