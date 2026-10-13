## The player: facing, stick movement inside the arena bounds.
extends CharacterBody2D

enum Facing { DOWN, UP, LEFT, RIGHT }

const FACING_NAMES: Array[StringName] = [&"down", &"up", &"left", &"right"]
const ACCELERATION: float = 900.0
const FRICTION: float = 1200.0
const WALK_THRESHOLD: float = 8.0
const DASH_SPEED: float = 420.0
const DASH_SECONDS: float = 0.14
const DASH_COOLDOWN: float = 1.15
const AFTERIMAGE_COUNT: int = 5
const AFTERIMAGE_FADE: float = 0.42
const AFTERIMAGE_ALPHA: float = 0.85
const AFTERIMAGE_TINT: Color = Color(0.6, 0.85, 1.0)
const DEFAULT_BOUNDS: Rect2 = Rect2(24, 120, 760, 202)

@export var facing: Facing = Facing.DOWN
@export var speed: float = 96.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _ring_back: Sprite2D = $RingBack
@onready var _ring_fill: Sprite2D = $RingFill

var bounds: Rect2 = DEFAULT_BOUNDS
var _dash_left: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_direction: Vector2 = Vector2.RIGHT
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
	_dash_left = 0.0
	set_walking(false)


func dash(direction: Vector2) -> bool:
	if _dash_cooldown > 0.0 or _dash_left > 0.0 or direction.length() < 0.01:
		return false
	_dash_direction = direction.normalized()
	_dash_left = DASH_SECONDS
	_dash_cooldown = DASH_COOLDOWN
	_leave_afterimages()
	return true


func is_dash_ready() -> bool:
	return _dash_cooldown <= 0.0 and _dash_left <= 0.0


func is_dashing() -> bool:
	return _dash_left > 0.0


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
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	if _dash_left > 0.0:
		_dash_left = maxf(_dash_left - delta, 0.0)
		velocity = _dash_direction * DASH_SPEED
		move_and_slide()
		_clamp_to_bounds()
		face_toward(_dash_direction)
		set_walking(true)
		return
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


func _leave_afterimages() -> void:
	## One ghost per slice of the dash, each fading on its own: the eye
	## reads the trail the body just traveled. Each ghost copies the
	## sprite's offset and global transform at creation, so the trail
	## sits exactly where the body was.
	var stage: Node = get_parent()
	for i in AFTERIMAGE_COUNT:
		var ghost: Sprite2D = Sprite2D.new()
		ghost.texture = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
		ghost.offset = _sprite.offset
		ghost.modulate = Color(AFTERIMAGE_TINT.r, AFTERIMAGE_TINT.g, AFTERIMAGE_TINT.b, AFTERIMAGE_ALPHA)
		stage.add_child(ghost)
		## After parenting: outside the tree there is no parent transform
		## to resolve against, and the centered arena is offset at wide
		## sizes. The ghost must sit where the body is, not where the
		## local numbers land.
		ghost.global_position = global_position
		var fade: Tween = ghost.create_tween()
		fade.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_FADE)
		fade.tween_callback(ghost.queue_free)
		await get_tree().create_timer(DASH_SECONDS * float(i) / float(AFTERIMAGE_COUNT)).timeout


func _play_current() -> void:
	var prefix: String = "walk_" if _walking else "idle_"
	_sprite.play(prefix + FACING_NAMES[facing])
