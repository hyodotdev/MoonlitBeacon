class_name BulletField
extends Node2D

## Every small enemy bullet in the field, in one node.
##
## The big volleys of a guardian (a fan, a ring, a cross) are `MoonBolt` nodes, capped at two dozen because each
## one is two nodes and the late-game budget is twelve hundred. The bullets you *weave through* (a spiral
## turning slowly, a stream that sways, a ring that drifts) cannot be nodes: a shooter needs a hundred of them
## at once. Here they are rows in packed arrays, moved, tested against the player and drawn by this one node,
## so a hundred and fifty cost one node, one texture and a few dozen microseconds a tick.
##
## They are meant to be dodged, not to be unfair. They are slower than the player, their hit circle is smaller than
## the orb that is drawn, they stop on structures (so cover is cover) and fade out over the last stretch of their
## range, and a hit only asks the arena the same question a touch does: it has its own invulnerable time.

const GROUP: StringName = &"bullet_field"
## Alive at once. Past this a barrage simply skips the shots it cannot place: it never deletes one already flying.
const LIMIT: int = 150
## A bullet is this far from the player's chest, at its nearest, when it hits. The orb is drawn wider than this.
const HIT_RADIUS: float = 6.0
const DRAW_SIZE: float = 15.0
## A bullet fades over its last stretch and is gone, so nothing hangs in the air at the far end of the map.
const FADE_DISTANCE: float = 40.0
const PLAYER_BODY_OFFSET: Vector2 = Vector2(0, -4)
## Bullets test the structures every few ticks: at their speeds that is a pixel or two.
const TERRAIN_EVERY: int = 3
const TERRAIN_RADIUS: float = 3.0
const SPARK_LIMIT: int = 28
const SPARK_SECONDS: float = 0.3

const TEXTURE: Texture2D = preload("res://assets/custom/items/projectiles/hostile_moon_bolt.png")

## Whose a bullet is: only for the tests and the play bot, so a hit can say what threw it.
enum Source { NONE, CASTER, WEAVER, WISP, AURA, STREAM, MOB }

## The colours of the night's bullets. A guardian's stream is in its own colour, so whose it is reads at a glance.
enum Tint { PINK, MINT, GOLD, LILAC, SKY }
const TINTS: Array[Color] = [
	Color(1.0, 0.62, 0.78, 1.0),
	Color(0.62, 1.0, 0.82, 1.0),
	Color(1.0, 0.86, 0.5, 1.0),
	Color(0.8, 0.68, 1.0, 1.0),
	Color(0.6, 0.86, 1.0, 1.0),
]

## Sent with where the bullet was when it hit. The arena answers it as it answers a touch.
signal struck(at: Vector2)

var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _accel: PackedFloat32Array = PackedFloat32Array()
var _turn: PackedFloat32Array = PackedFloat32Array()
var _tint: PackedInt32Array = PackedInt32Array()
var _source: PackedInt32Array = PackedInt32Array()
var _range_left: PackedFloat32Array = PackedFloat32Array()
var _spark_pos: PackedVector2Array = PackedVector2Array()
var _spark_age: PackedFloat32Array = PackedFloat32Array()
var _spark_tint: PackedInt32Array = PackedInt32Array()
var _target: Node2D = null
var _centers: PackedVector2Array = PackedVector2Array()
var _radii: PackedFloat32Array = PackedFloat32Array()
var _tick: int = 0
var _quiet_left: float = 0.0
var _volley_wait: float = 0.0
## Shots that could not be placed because the field was full, for the tests and the play bot to read.
var refused: int = 0
var _texture_half: Vector2 = Vector2.ONE * DRAW_SIZE * 0.5


func _ready() -> void:
	add_to_group(GROUP)
	# Above the y-sorted actors: a bullet is drawn over whoever it is flying past.
	z_index = 20
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


static func of(node: Node) -> BulletField:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as BulletField


## Ordinary spirits stop throwing for this long: the first moments in a new place are for looking round.
func quiet_for(seconds: float) -> void:
	_quiet_left = maxf(_quiet_left, seconds)


func is_quiet() -> bool:
	return _quiet_left > 0.0


## The shooters on the screen take turns: one may start a volley only when `gap` seconds have passed since the last
## one started, so a room of casters is a rhythm and not a wall. Returns whether this one may.
func claim_volley(gap: float) -> bool:
	if _volley_wait > 0.0:
		return false
	_volley_wait = gap
	return true


## The one whose bullets hurt.
func set_target(target: Node2D) -> void:
	_target = target


## The structures bullets stop on. Taken once from the room, which does not change while it stands.
func set_terrain_room(room: Room) -> void:
	_centers.clear()
	_radii.clear()
	if room == null or not is_instance_valid(room):
		return
	for obstacle in room.terrain_obstacle_snapshot():
		_centers.append(room.to_global(obstacle["at"] as Vector2))
		_radii.append(float(obstacle["radius"]) + TERRAIN_RADIUS)


func count() -> int:
	return _pos.size()


func is_full() -> bool:
	return _pos.size() >= LIMIT


func positions() -> PackedVector2Array:
	return _pos


func velocities() -> PackedVector2Array:
	return _vel


## Fire one bullet. `advance` is how long ago it should have left, so a barrage that ticks at a fixed rate still
## spaces its bullets evenly. Returns false, and places nothing, when the field is full.
func spawn(at: Vector2, angle: float, speed: float, tint: int = Tint.PINK, range_px: float = 300.0,
		accel: float = 0.0, turn: float = 0.0, advance: float = 0.0, source: int = Source.NONE) -> bool:
	if _pos.size() >= LIMIT:
		refused += 1
		return false
	var direction: Vector2 = Vector2.RIGHT.rotated(angle)
	_pos.append(at + direction * speed * advance)
	_vel.append(direction * speed)
	_accel.append(accel)
	_turn.append(turn)
	_tint.append(clampi(tint, 0, TINTS.size() - 1))
	_source.append(source)
	_range_left.append(range_px - speed * advance)
	return true


## A fan of `count` bullets around `angle`, `spread` radians wide in all.
func fan(at: Vector2, angle: float, count: int, spread: float, speed: float, tint: int = Tint.PINK,
		range_px: float = 300.0, advance: float = 0.0, source: int = Source.NONE) -> int:
	var placed: int = 0
	for index in count:
		var t: float = 0.0 if count == 1 else float(index) / float(count - 1) - 0.5
		if spawn(at, angle + spread * t, speed, tint, range_px, 0.0, 0.0, advance, source):
			placed += 1
	return placed


## `count` bullets round a circle, the first at `first_angle`.
func ring(at: Vector2, count: int, first_angle: float, speed: float, tint: int = Tint.PINK,
		range_px: float = 300.0, advance: float = 0.0, source: int = Source.NONE) -> int:
	var placed: int = 0
	for index in count:
		if spawn(at, first_angle + TAU * float(index) / float(count), speed, tint, range_px, 0.0, 0.0, advance, source):
			placed += 1
	return placed


## How many bullets are within `radius` of `at`.
func count_near(at: Vector2, radius: float) -> int:
	var found: int = 0
	var limit: float = radius * radius
	for index in _pos.size():
		if _pos[index].distance_squared_to(at) <= limit:
			found += 1
	return found


## Everything gone, silently.
func clear() -> void:
	_pos.clear()
	_vel.clear()
	_accel.clear()
	_turn.clear()
	_tint.clear()
	_source.clear()
	_range_left.clear()
	_spark_pos.clear()
	_spark_age.clear()
	_spark_tint.clear()
	queue_redraw()


## Everything turns to sparks and is gone: what a guardian's bullets do when it falls.
func dissolve() -> void:
	var step: int = maxi(_pos.size() / SPARK_LIMIT, 1)
	for index in range(0, _pos.size(), step):
		_add_spark(_pos[index], _tint[index])
	_pos.clear()
	_vel.clear()
	_accel.clear()
	_turn.clear()
	_tint.clear()
	_source.clear()
	_range_left.clear()
	queue_redraw()


func _add_spark(at: Vector2, tint: int) -> void:
	if _spark_pos.size() >= SPARK_LIMIT:
		return
	_spark_pos.append(at)
	_spark_age.append(0.0)
	_spark_tint.append(tint)


func _remove(index: int) -> void:
	var last: int = _pos.size() - 1
	if index != last:
		_pos[index] = _pos[last]
		_vel[index] = _vel[last]
		_accel[index] = _accel[last]
		_turn[index] = _turn[last]
		_tint[index] = _tint[last]
		_source[index] = _source[last]
		_range_left[index] = _range_left[last]
	_pos.resize(last)
	_vel.resize(last)
	_accel.resize(last)
	_turn.resize(last)
	_tint.resize(last)
	_source.resize(last)
	_range_left.resize(last)


func _physics_process(delta: float) -> void:
	_tick += 1
	_quiet_left = maxf(_quiet_left - delta, 0.0)
	_volley_wait = maxf(_volley_wait - delta, 0.0)
	var chest: Vector2 = Vector2.ZERO
	var can_hit: bool = _target != null and is_instance_valid(_target)
	if can_hit:
		chest = _target.to_global(PLAYER_BODY_OFFSET)
	var limit: float = HIT_RADIUS * HIT_RADIUS
	var index: int = 0
	while index < _pos.size():
		var velocity: Vector2 = _vel[index]
		var speed_up: float = _accel[index]
		if speed_up != 0.0:
			var length: float = velocity.length()
			if length > 0.001:
				velocity = velocity / length * maxf(length + speed_up * delta, 0.0)
		var turn: float = _turn[index]
		if turn != 0.0:
			velocity = velocity.rotated(turn * delta)
		_vel[index] = velocity
		var from: Vector2 = _pos[index]
		var to: Vector2 = from + velocity * delta
		if can_hit:
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(chest, from, to)
			if nearest.distance_squared_to(chest) <= limit:
				_add_spark(to, _tint[index])
				_remove(index)
				struck.emit(to)
				continue
		if (_tick + index) % TERRAIN_EVERY == 0 and _blocked(to):
			_add_spark(to, _tint[index])
			_remove(index)
			continue
		_pos[index] = to
		var left: float = _range_left[index] - from.distance_to(to)
		_range_left[index] = left
		if left <= 0.0:
			_remove(index)
			continue
		index += 1
	var spark: int = 0
	while spark < _spark_pos.size():
		_spark_age[spark] += delta
		if _spark_age[spark] >= SPARK_SECONDS:
			var last: int = _spark_pos.size() - 1
			_spark_pos[spark] = _spark_pos[last]
			_spark_age[spark] = _spark_age[last]
			_spark_tint[spark] = _spark_tint[last]
			_spark_pos.resize(last)
			_spark_age.resize(last)
			_spark_tint.resize(last)
			continue
		spark += 1


func _blocked(at: Vector2) -> bool:
	for index in _centers.size():
		var reach: float = _radii[index]
		if at.distance_squared_to(_centers[index]) < reach * reach:
			return true
	return false


func _process(_delta: float) -> void:
	if not _pos.is_empty() or not _spark_pos.is_empty():
		queue_redraw()


func _draw() -> void:
	# Drawn a fraction of a tick ahead of where the last tick left it, so a hundred and twenty hertz screen sees
	# smooth flight from a sixty hertz simulation.
	var lead: float = Engine.get_physics_interpolation_fraction() / float(Engine.physics_ticks_per_second)
	var size: Vector2 = Vector2.ONE * DRAW_SIZE
	for index in _pos.size():
		var fade: float = clampf(_range_left[index] / FADE_DISTANCE, 0.0, 1.0)
		var color: Color = TINTS[_tint[index]]
		color.a = fade
		var at: Vector2 = _pos[index] + _vel[index] * lead
		draw_texture_rect(TEXTURE, Rect2(at - _texture_half, size), false, color)
	for index in _spark_pos.size():
		var t: float = _spark_age[index] / SPARK_SECONDS
		var color: Color = TINTS[_spark_tint[index]]
		color.a = (1.0 - t) * 0.8
		draw_arc(_spark_pos[index], 3.0 + 9.0 * t, 0.0, TAU, 12, color, 1.6)
