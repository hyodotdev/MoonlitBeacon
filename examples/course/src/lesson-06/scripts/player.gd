## The player: facing, stick movement inside the arena bounds.
extends CharacterBody2D

enum Facing { DOWN, UP, LEFT, RIGHT }

const FACING_NAMES: Array[StringName] = [&"down", &"up", &"left", &"right"]
const ACCELERATION: float = 900.0
const FRICTION: float = 1200.0
const WALK_THRESHOLD: float = 8.0
const BOUNDS: Rect2 = Rect2(24, 120, 760, 202)

@export var facing: Facing = Facing.DOWN
@export var speed: float = 96.0

@onready var _sprite: AnimatedSprite2D = $Sprite

var _walking: bool = false
var _wish: Vector2 = Vector2.ZERO


func _ready() -> void:
	_play_current()


func set_move_input(value: Vector2) -> void:
	_wish = value


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
	var target: Vector2 = _wish * speed
	var rate: float = ACCELERATION if _wish.length() > 0.01 else FRICTION
	velocity = velocity.move_toward(target, rate * delta)
	move_and_slide()
	position.x = clampf(position.x, BOUNDS.position.x, BOUNDS.position.x + BOUNDS.size.x)
	position.y = clampf(position.y, BOUNDS.position.y, BOUNDS.position.y + BOUNDS.size.y)
	face_toward(_wish)
	set_walking(velocity.length() > WALK_THRESHOLD)


func _play_current() -> void:
	var prefix: String = "walk_" if _walking else "idle_"
	_sprite.play(prefix + FACING_NAMES[facing])
