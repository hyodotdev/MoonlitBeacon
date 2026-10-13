## A chasing spirit: drifts toward the player, hits once per cooldown.
extends CharacterBody2D

signal touched_player

const FACING_NAMES: Array[StringName] = [&"down", &"up", &"left", &"right"]
const TURN_RATE: float = 3.0
const HIT_COOLDOWN: float = 1.0
const KNOCKBACK_SPEED: float = 260.0
const KNOCKBACK_SECONDS: float = 0.18
const HIT_FLASH_SECONDS: float = 0.12

@export var speed: float = 52.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _hitbox: Area2D = $Hitbox

var _target: Node2D = null
var _cooldown: float = 0.0
var _hit_flash: float = 0.0


func _ready() -> void:
	_hitbox.body_entered.connect(_on_body_entered)


func set_target(target: Node2D) -> void:
	_target = target


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _hit_flash > 0.0:
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		if _hit_flash <= 0.0:
			_sprite.modulate = Color.WHITE
	if _target == null or not is_instance_valid(_target):
		return
	var wish: Vector2 = _target.global_position - global_position
	if wish.length() > 1.0:
		wish = wish.normalized()
	else:
		wish = Vector2.ZERO
	velocity = velocity.lerp(wish * speed, minf(TURN_RATE * delta, 1.0))
	move_and_slide()
	_face_velocity()


func _face_velocity() -> void:
	if velocity.length() < 4.0:
		return
	var facing: int = 0
	if absf(velocity.x) > absf(velocity.y):
		facing = 3 if velocity.x > 0.0 else 2
	else:
		facing = 0 if velocity.y > 0.0 else 1
	_sprite.play("move_" + FACING_NAMES[facing])


func poll_hits() -> void:
	## body_entered fires once per touch; overlap polling keeps hitting
	## while bodies stay tangled, so standing inside the player still hurts.
	if _cooldown > 0.0:
		return
	for body in _hitbox.get_overlapping_bodies():
		if body.has_method("knock_back"):
			_try_hit(body)
			return


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("knock_back"):
		_try_hit(body)


func _try_hit(body: Node2D) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = HIT_COOLDOWN
	if body.has_method("knock_back"):
		var push: Vector2 = body.global_position - global_position
		if push.length() < 0.01:
			push = Vector2.DOWN
		body.knock_back(push.normalized(), KNOCKBACK_SPEED, KNOCKBACK_SECONDS)
	_hit_flash = HIT_FLASH_SECONDS
	_sprite.modulate = Color(1, 0.35, 0.35)
	touched_player.emit()
