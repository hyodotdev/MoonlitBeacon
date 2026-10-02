class_name RoomShadows
extends RoomLayer

## Cast shadows for everything that stands on the floor.
##
## A tree or a crate is drawn upright and the floor under it was flat, so nothing
## looked planted: a 2D sprite pasted on a texture. Under a low moon that hangs to
## one side, every object throws a soft shadow the same way, and that one shared
## direction is most of what makes a top-down scene read as a lit space.
##
## **One node for every shadow on the map.** A forest holds about 700 props, so a
## `Sprite2D` per shadow would double the room's node count; this draws all of
## them in one `_draw()` and is static after the build.
##
## Each object leaves two marks:
##
##   * a *cast* shadow, a long soft ellipse leaning away from the moon, and
##   * a contact patch, a small dark oval right under the base, which is what
##     stops an object from floating on its own cast shadow.
##
## Drawn above `Ground` and below everything else, so a shadow never darkens the
## art standing in it. It only draws what the camera can see (`RoomLayer`).

## Which way the moon throws shadows, as a unit-ish vector. Down and to the right:
## the light sits high on the upper left. Actors use the same value.
const LIGHT_DIRECTION: Vector2 = Vector2(0.92, 0.38)
## How far a shadow reaches, relative to its object's height.
const REACH: float = 0.34
## Ground-plane circles are squashed to this ratio, the same squash the lantern
## pools use, so a shadow and a pool of light agree about the camera angle.
const SQUASH: float = 0.36

const SHADOW_COLOR: Color = Color(0.008, 0.016, 0.06, 1.0)

## Radial soft-edged disc, built once. Linear filtering is set on the node.
static var _disc: GradientTexture2D = null

## `{at, size, strength}` per object. `at` is the point where it meets the ground,
## `size` the half-extent of its footprint, `strength` how dark its shadow is.
var _casts: Array[Dictionary] = []
var _contacts: Array[Dictionary] = []


func _ready() -> void:
	super._ready()
	z_index = -2
	light_mask = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## Register an upright object standing at `at`.
##
## `half_width` is half the visible footprint of its base, `height` how tall it
## stands. Taller objects cast longer shadows; wider ones cast fatter ones.
func add_cast(at: Vector2, half_width: float, height: float, strength: float = 0.3) -> void:
	var reach: float = height * REACH
	var center: Vector2 = at + LIGHT_DIRECTION * reach + Vector2(0.0, 0.6)
	var radius_x: float = half_width + reach * 0.9
	_casts.append({
		"at": center,
		"size": Vector2(radius_x, maxf(radius_x * SQUASH, 2.0)),
		"strength": strength,
	})
	_contacts.append({
		"at": at + Vector2(0.0, 0.4),
		"size": Vector2(half_width * 0.9, maxf(half_width * 0.9 * SQUASH, 1.6)),
		"strength": minf(strength * 1.5, 0.6),
	})


## A wide, faint pool of shade, for thickets and other things that darken the
## ground around them instead of casting one clean shape.
func add_shade(at: Vector2, radius: Vector2, strength: float = 0.2) -> void:
	_casts.append({"at": at, "size": radius, "strength": strength})


func clear() -> void:
	_casts.clear()
	_contacts.clear()
	queue_redraw()


func cast_count() -> int:
	return _casts.size()


func finish() -> void:
	queue_redraw()


func _draw() -> void:
	var disc: Texture2D = _disc_texture()
	var tilt: float = LIGHT_DIRECTION.angle() * 0.5
	var view: Rect2 = view_rect()
	for shadow: Dictionary in _casts:
		_stamp(disc, shadow, tilt, view)
	for shadow: Dictionary in _contacts:
		_stamp(disc, shadow, 0.0, view)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _stamp(disc: Texture2D, shadow: Dictionary, tilt: float, view: Rect2) -> void:
	var size: Vector2 = shadow["size"]
	var at: Vector2 = shadow["at"]
	# A shadow leans as far as its own width, so test its whole reach.
	if not view.intersects(Rect2(at - size * 1.2, size * 2.4)):
		return
	var color: Color = SHADOW_COLOR
	color.a = float(shadow["strength"])
	# Lean the ellipse along the light so it reads as thrown, not just placed.
	draw_set_transform(at, tilt, Vector2.ONE)
	draw_texture_rect(disc, Rect2(-size, size * 2.0), false, color)


static func _disc_texture() -> GradientTexture2D:
	if _disc == null:
		# Solid core, soft long edge: a cast shadow is darkest where it meets its object.
		_disc = SoftDisc.radial([
			Vector2(0.0, 1.0), Vector2(0.42, 0.82), Vector2(0.78, 0.26), Vector2(1.0, 0.0)])
	return _disc
