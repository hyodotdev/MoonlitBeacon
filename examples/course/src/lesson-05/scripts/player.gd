## The player: facing now, movement and charge later.
extends CharacterBody2D

enum Facing { DOWN, UP, LEFT, RIGHT }

const FACING_NAMES: Array[StringName] = [&"down", &"up", &"left", &"right"]

@export var facing: Facing = Facing.DOWN

@onready var _sprite: AnimatedSprite2D = $Sprite

var _walking: bool = false


func _ready() -> void:
	_play_current()


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


func _play_current() -> void:
	var prefix: String = "walk_" if _walking else "idle_"
	_sprite.play(prefix + FACING_NAMES[facing])
