## The player: facing, stick movement inside the arena bounds.
extends CharacterBody2D

enum Facing { DOWN, UP, LEFT, RIGHT }

const FACING_NAMES: Array[StringName] = [&"down", &"up", &"left", &"right"]
const ACCELERATION: float = 900.0
const FRICTION: float = 1200.0
const WALK_THRESHOLD: float = 8.0
const DEFAULT_BOUNDS: Rect2 = Rect2(24, 120, 760, 202)

@export var facing: Facing = Facing.DOWN
@export var speed: float = 96.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _ring_back: Sprite2D = $RingBack
@onready var _ring_fill: Sprite2D = $RingFill

var bounds: Rect2 = DEFAULT_BOUNDS
var _walking: bool = false
var _wish: Vector2 = Vector2.ZERO
var _knock_left: float = 0.0


func _ready() -> void:
	_play_current()


func knock_back(direction: Vector2, knock_speed: float, seconds: float) -> void:
	velocity = direction.normalized() * knock_speed
	_knock_left = seconds


func set_move_input(value: Vector2) -> void:
	_wish = value


func set_bounds(rect: Rect2) -> void:
	bounds = rect


func freeze() -> void:
	## The run ended mid-stride: drop all motion now so the result tableau
	## holds still. Facing stays; only movement stops.
	_wish = Vector2.ZERO
	velocity = Vector2.ZERO
	_knock_left = 0.0
	set_walking(false)


func set_charge(ratio: float) -> void:
	## Mirror the strongest nearby beacon charge on the ring at our feet.
	_ring_back.visible = ratio > 0.0 and ratio < 1.0
	_ring_fill.visible = _ring_back.visible
	if not _ring_fill.visible:
		return
	var height: float = 40.0 * clampf(ratio, 0.0, 1.0)
	_ring_fill.region_rect = Rect2(0, 40.0 - height, 40, height)
	_ring_fill.offset = Vector2(0, (40.0 - height) * 0.5)


func face_toward(direction: Vector2) -> void:
	## Lesson 6 passes the stick direction as-is. If the length is near 0, do not change facing.
	if direction.length() < 0.01:
		return
	if absf(direction.x) > absf(direction.y):
		facing = Facing.RIGHT if direction.x > 0.0 else Facing.LEFT
	else:
		facing = Facing.DOWN if direction.y > 0.0 else Facing.UP


func set_walking(value: bool) -> void:
	_walking = value
	_play_current()


func _physics_process(delta: float) -> void:
	if _knock_left > 0.0:
		_knock_left -= delta
		move_and_slide()
		_clamp_to_bounds()
		return
	var target: Vector2 = _wish * speed
	var rate: float = ACCELERATION if _wish.length() > 0.01 else FRICTION
	velocity = velocity.move_toward(target, rate * delta)
	move_and_slide()
	_clamp_to_bounds()
	face_toward(_wish)
	set_walking(velocity.length() > WALK_THRESHOLD)


func _clamp_to_bounds() -> void:
	position.x = clampf(position.x, bounds.position.x, bounds.position.x + bounds.size.x)
	position.y = clampf(position.y, bounds.position.y, bounds.position.y + bounds.size.y)


func _play_current() -> void:
	var prefix: String = "walk_" if _walking else "idle_"
	_sprite.play(prefix + FACING_NAMES[facing])
