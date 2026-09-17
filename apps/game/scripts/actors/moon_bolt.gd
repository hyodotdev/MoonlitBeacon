extends Node2D

## Moonlight orb thrown by a shooting spirit.
##
## Flies straight and vanishes on a hit or leaving the map. No homing —
## **homing leaves no way to dodge, and what cannot be dodged is a penalty,
## not a threat.**

## Flight speed. Faster than the player (96), but still sidesteppable.
const SPEED: float = 132.0

## Self-despawn after this long so shots that leave the map do not live forever.
const LIFETIME: float = 5.0
const PENDING_META: StringName = &"moonlit_pending_hostile_bolts"
## Orb 6 + player body 4. Compare the travel segment to this circle so low-FPS tunneling is blocked too.
const HIT_RADIUS: float = 10.0
## Structure hit radius fitted to the 40px source drawn at 0.42 scale.
const TERRAIN_RADIUS: float = 8.0
const PLAYER_BODY_OFFSET: Vector2 = Vector2(0, -4)
const SPIN_SPEED: float = TAU / 1.2

@onready var _sprite: Sprite2D = $Sprite

var _direction: Vector2 = Vector2.RIGHT
var _left: float = LIFETIME
var _hit_handler: Callable = Callable()
var _reserved_slot: bool = false
var _target: Node2D = null
var _terrain_room: Room = null
var _speed_scale: float = 1.0


func _enter_tree() -> void:
	# On the fire frame it is not in the group yet because of `add_child.call_deferred()`.
	# Return the reservation counted through that gap the instant the node enters the tree.
	if not _reserved_slot:
		return
	var tree: SceneTree = get_tree()
	var pending: int = int(tree.get_meta(PENDING_META, 0))
	tree.set_meta(PENDING_META, maxi(pending - 1, 0))
	_reserved_slot = false


func _ready() -> void:
	add_to_group("hostile_projectiles")


## The spirit sets direction as it fires.
func set_direction(direction: Vector2) -> void:
	_direction = direction.normalized()


func set_speed_scale(scale: float) -> void:
	_speed_scale = maxf(scale, 0.2)


func set_target(target: Node2D) -> void:
	_target = target


## Hostile projectiles stop on structures so the player can choose cover.
##
## The player's moon wheels and missiles do not take this link, so they pierce
## structures. Attack upgrades stay satisfying; only enemy fire adds a terrain
## read.
func set_terrain_room(room: Room) -> void:
	_terrain_room = room


## Even if the firing spirit is gone first, the arena still handles the hit.
func set_hit_handler(handler: Callable) -> void:
	_hit_handler = handler


## Count toward the projectile cap even on the frame before it joins the tree.
func reserve_slot() -> void:
	_reserved_slot = true


func _physics_process(delta: float) -> void:
	var from: Vector2 = global_position
	var destination: Vector2 = from + _direction * SPEED * _speed_scale * delta
	var terrain_hit: Dictionary = {}
	if _terrain_room != null and is_instance_valid(_terrain_room):
		var local_from: Vector2 = _terrain_room.to_local(from)
		var local_destination: Vector2 = _terrain_room.to_local(destination)
		terrain_hit = _terrain_room.first_terrain_intersection(
			local_from, local_destination, TERRAIN_RADIUS)
		if not terrain_hit.is_empty():
			destination = _terrain_room.to_global(terrain_hit["at"])

	# Compare only the clipped segment to the structure against the player.
	# That blocks hitting a player behind cover first, while a hit in front of
	# the structure still registers.
	if _target != null and is_instance_valid(_target):
		var player_center: Vector2 = _target.to_global(PLAYER_BODY_OFFSET)
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(
			player_center, from, destination)
		var player_scale: float = maxf(
			absf(_target.global_scale.x), absf(_target.global_scale.y))
		var reach: float = 6.0 + 4.0 * player_scale
		if nearest.distance_squared_to(player_center) <= reach * reach:
			global_position = nearest
			_on_player_hit()
			return
	if not terrain_hit.is_empty():
		global_position = destination
		_burst()
		return
	global_position = destination
	_sprite.rotation += SPIN_SPEED * delta
	_left -= delta
	if _left <= 0.0:
		queue_free()


func _on_player_hit() -> void:
	if _hit_handler.is_valid():
		_hit_handler.call(global_position)
	_burst()


func _burst() -> void:
	set_physics_process(false)
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	var out: Tween = create_tween()
	out.set_parallel(true)
	out.tween_property(_sprite, "scale", Vector2(2.2, 2.2), 0.14)
	out.tween_property(self, "modulate:a", 0.0, 0.14)
	out.chain().tween_callback(queue_free)
