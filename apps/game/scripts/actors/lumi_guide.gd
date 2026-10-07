class_name LumiGuide
extends Node2D

## Lumi, the Lantern Keeper, standing by the lodge registry desk.
##
## One sprite, one common scale, one foot anchor: every facing frame is
## packed at the same height on the same ground line, so swapping the
## texture never moves her feet or resizes her face. The node converts
## packed source pixels to world units itself; the room only multiplies
## its layout zoom on top. She turns toward the hero (front/left/right;
## the rear frame exists for the contact sheet) and breathes in place
## with a still body and a breathing floor shadow. No walk cycle: she
## tends the desk and does not escort. Nothing here translates the
## sprite: the painted boots stay planted on the foot line.

const FACING_FRONT: String = "front"
const FACING_REAR: String = "rear"
const FACING_LEFT: String = "left"
const FACING_RIGHT: String = "right"

const TEX_FRONT: Texture2D = preload(
	"res://assets/custom/actors/lumi/front.png")
const TEX_REAR: Texture2D = preload(
	"res://assets/custom/actors/lumi/rear.png")
const TEX_LEFT: Texture2D = preload(
	"res://assets/custom/actors/lumi/left.png")
const TEX_RIGHT: Texture2D = preload(
	"res://assets/custom/actors/lumi/right.png")
const TEX_SHADOW: Texture2D = preload("res://assets/derived/player/shadow.png")

## Packed frame height every facing shares.
const FRAME_HEIGHT: float = 869.0
## World height at layout zoom 1.0: 1.5x the tallest playable hero
## opaque body (28.05 world px, measured across all five heroes), so
## the adult keeper reads beside the chibi arrival without towering.
const WORLD_HEIGHT: float = 42.0
## Packed-source-to-world conversion every facing shares.
const BASE_SCALE: float = WORLD_HEIGHT / FRAME_HEIGHT
## Floor shadow in world units: a touch wider than her ~16px body, the
## same soft ellipse language as the hero's own shadow.
const SHADOW_WORLD: Vector2 = Vector2(19.0, 8.0)
## Idle breath period. Only the floor shadow pulses; the body never
## translates, so the painted foot line stays fixed at every point of the breath.
const IDLE_PERIOD: float = 2.6
## Shadow pulse depth around its resting alpha.
const IDLE_SHADOW_PULSE: float = 0.04
## Face front while the hero stands this close to her center line.
const FRONT_DEAD_ZONE: float = 12.0

var _sprite: Sprite2D = null
var _shadow: Sprite2D = null
var _facing: String = FACING_FRONT
var _actor_scale: float = 1.0
var _idle_time: float = 0.0


func _ready() -> void:
	_shadow = Sprite2D.new()
	_shadow.name = &"Shadow"
	_shadow.light_mask = 0
	_shadow.modulate = Color(0.05, 0.06, 0.12, 0.85)
	_shadow.texture = TEX_SHADOW
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.name = &"Sprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.centered = false
	add_child(_sprite)
	set_facing(FACING_FRONT)
	_update_scale()


## Room layout zoom on top of the source-to-world conversion. The scene
## calls this on every relayout; the contact sheet leaves the default.
func set_actor_scale(actor_scale: float) -> void:
	_actor_scale = actor_scale
	if is_inside_tree():
		_update_scale()


## Total node scale: source conversion times layout zoom.
func total_scale() -> float:
	return BASE_SCALE * _actor_scale


func _update_scale() -> void:
	var total: float = total_scale()
	scale = Vector2.ONE * total
	if _shadow != null and _shadow.texture != null:
		var shadow_size: Vector2 = _shadow.texture.get_size()
		_shadow.scale = Vector2(SHADOW_WORLD.x / (shadow_size.x * total),
			SHADOW_WORLD.y / (shadow_size.y * total))


## Swap the facing texture. The foot anchor stays: every frame shares
## one height, so bottom-left offset math is identical per facing.
func set_facing(facing: String) -> void:
	if facing != FACING_FRONT and facing != FACING_REAR \
		and facing != FACING_LEFT and facing != FACING_RIGHT:
		return
	_facing = facing
	if _sprite == null:
		return
	var texture: Texture2D = TEX_FRONT
	if facing == FACING_REAR:
		texture = TEX_REAR
	elif facing == FACING_LEFT:
		texture = TEX_LEFT
	elif facing == FACING_RIGHT:
		texture = TEX_RIGHT
	_sprite.texture = texture
	var size: Vector2 = texture.get_size()
	_sprite.offset = Vector2(-size.x * 0.5, -size.y)
	_sprite.position = Vector2.ZERO


## Current facing key: front, rear, left, or right.
func facing() -> String:
	return _facing


## Turn toward the hero's horizontal position: left past the dead zone,
## right past it, front while near. The keeper faces the room, never
## away from her guest.
func face_toward(hero_x: float) -> void:
	var delta: float = hero_x - position.x
	if delta < -FRONT_DEAD_ZONE:
		set_facing(FACING_LEFT)
	elif delta > FRONT_DEAD_ZONE:
		set_facing(FACING_RIGHT)
	else:
		set_facing(FACING_FRONT)


## Foot point in local space: the node origin by construction.
func foot_local() -> Vector2:
	return Vector2.ZERO


func _process(delta: float) -> void:
	if _sprite == null:
		return
	_idle_time += delta
	var pulse_angle: float = _idle_time * TAU / IDLE_PERIOD
	_shadow.modulate.a = 0.85 + sin(pulse_angle) * IDLE_SHADOW_PULSE
