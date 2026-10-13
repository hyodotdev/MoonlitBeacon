## One body, many kinds: the assigned SpiritKind slices the sheet and sets the gait.
extends CharacterBody2D

signal touched_player

const FACING_NAMES: Array[StringName] = [&"down", &"up", &"left", &"right"]
const HIT_COOLDOWN: float = 1.0
const KNOCKBACK_SPEED: float = 260.0
const KNOCKBACK_SECONDS: float = 0.18
const HIT_FLASH_SECONDS: float = 0.12
const MATERIALIZE_SECONDS: float = 0.6
const RETREAT_SECONDS: float = 0.4

@export var kind: SpiritKind = null
@export var speed: float = 52.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _hitbox: Area2D = $Hitbox

var _target: Node2D = null
var _cooldown: float = 0.0
var _hit_flash: float = 0.0
var _turn_rate: float = 3.0
var _retreating: bool = false
var _single_facing: bool = false


func _ready() -> void:
	_apply_kind()
	_hitbox.body_entered.connect(_on_body_entered)


func _apply_kind() -> void:
	if kind == null:
		push_error("spirit without a kind cannot animate")
		return
	scale = Vector2.ONE * kind.body_scale
	modulate = kind.tint
	speed = kind.speed
	_turn_rate = kind.turn_rate
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation(&"default")
	if kind.rows == 1:
		## One row means one facing: every column is a frame of the same
		## look, laid out left to right along row zero.
		_add_float_animation(frames, &"float_down", kind.anim_fps)
		for col in kind.columns:
			frames.add_frame(&"float_down", _slice(col, 0))
		_single_facing = true
	else:
		for col in kind.columns:
			var anim: StringName = &"float_" + FACING_NAMES[mini(col, FACING_NAMES.size() - 1)]
			_add_float_animation(frames, anim, kind.anim_fps)
			for row in kind.rows:
				frames.add_frame(anim, _slice(col, row))
	_sprite.sprite_frames = frames


func _add_float_animation(frames: SpriteFrames, anim: StringName, fps: float) -> void:
	if frames.has_animation(anim):
		return
	frames.add_animation(anim)
	frames.set_animation_loop(anim, true)
	frames.set_animation_speed(anim, fps)


func _slice(col: int, row: int) -> AtlasTexture:
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = kind.sheet
	atlas.region = Rect2(col * kind.cell, row * kind.cell, kind.cell, kind.cell)
	return atlas


func materialize() -> void:
	## Fade in untouchable, then join the hunt once fully here.
	_hitbox.set_deferred("monitoring", false)
	modulate.a = 0.0
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", kind.tint.a, MATERIALIZE_SECONDS)
	await fade.finished
	if is_inside_tree():
		_hitbox.monitoring = true


func retreat() -> void:
	## The run is decided: stop hunting, fade out, leave the stage.
	_retreating = true
	set_target(null)
	_hitbox.set_deferred("monitoring", false)
	_cooldown = HIT_COOLDOWN
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 0.0, RETREAT_SECONDS)
	await fade.finished
	if is_inside_tree():
		queue_free()


func set_target(target: Node2D) -> void:
	_target = target


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _hit_flash > 0.0:
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		if _hit_flash <= 0.0 and not _retreating:
			_sprite.modulate = Color.WHITE
	if _target == null or not is_instance_valid(_target):
		return
	var wish: Vector2 = _target.global_position - global_position
	if wish.length() > 1.0:
		wish = wish.normalized()
	else:
		wish = Vector2.ZERO
	velocity = velocity.lerp(wish * speed, minf(_turn_rate * delta, 1.0))
	move_and_slide()
	_face_velocity()


func _face_velocity() -> void:
	if _single_facing:
		_sprite.play("float_down")
		return
	if velocity.length() < 4.0:
		return
	var facing: int = 0
	if absf(velocity.x) > absf(velocity.y):
		facing = 3 if velocity.x > 0.0 else 2
	else:
		facing = 0 if velocity.y > 0.0 else 1
	_sprite.play("float_" + FACING_NAMES[facing])


func poll_hits() -> void:
	## body_entered fires once per touch; overlap polling keeps hitting
	## while bodies stay tangled, so standing inside the player still hurts.
	## A materializing hitbox reports nothing until it arms.
	if _cooldown > 0.0 or not _hitbox.monitoring:
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
