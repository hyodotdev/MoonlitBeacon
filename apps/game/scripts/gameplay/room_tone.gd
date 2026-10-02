class_name RoomTone
extends RoomLayer

## Large soft colour patches laid over the floor tile.
##
## The floor is one small tile repeated across a 1900x1180 map, and from a few
## screens away the eye finds the repeat. Painting a few dozen wide, faint patches
## of moss, deep indigo and moonlit blue over it breaks the repeat and gives the
## ground the uneven, lived-in colour a real clearing has, with no new art.
##
## One node, one `_draw()`, static. It is drawn straight above `Ground` and below
## the cast shadows, so shade always falls on top of the colour it falls on.

## Radial disc, built once.
static var _disc: GradientTexture2D = null

## `{at, size, color}` per patch.
var _patches: Array[Dictionary] = []


func _ready() -> void:
	super._ready()
	z_index = -2
	light_mask = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## A soft elliptical patch. `size` is the half-extent, `color` carries its opacity.
func add_patch(at: Vector2, size: Vector2, color: Color) -> void:
	_patches.append({"at": at, "size": size, "color": color})


func clear() -> void:
	_patches.clear()
	queue_redraw()


func patch_count() -> int:
	return _patches.size()


func finish() -> void:
	queue_redraw()


func _draw() -> void:
	var disc: Texture2D = _disc_texture()
	var view: Rect2 = view_rect()
	for patch: Dictionary in _patches:
		var size: Vector2 = patch["size"]
		var at: Vector2 = patch["at"]
		if not view.intersects(Rect2(at - size, size * 2.0)):
			continue
		draw_texture_rect(disc, Rect2(at - size, size * 2.0), false, patch["color"])


static func _disc_texture() -> GradientTexture2D:
	if _disc == null:
		# Flat top with a long soft skirt: a patch of moss has a body, not a bright core.
		_disc = SoftDisc.radial([
			Vector2(0.0, 1.0), Vector2(0.5, 0.7), Vector2(0.82, 0.2), Vector2(1.0, 0.0)])
	return _disc
