class_name NightVignette
extends Sprite2D

## Screen-space vignette for the arena.
##
## The title screen already had one; the arena did not, so the gameplay frame
## read as one flat brightness from edge to edge with no depth. `room.tscn`
## even carried the gradient sub-resources, but no node ever used them.
##
## This sits on a `CanvasLayer`, not in the room. The arena camera follows the
## player, so a world-space vignette would darken the room's own corners and
## scroll away instead of framing the screen.
##
## `light_mask = 0` keeps beacon and lantern lights from eating the falloff.

## Darkest the edges go. Kept well below opaque — a dodge game must still show
## what is about to walk in from off-screen.
const MAX_ALPHA: float = 1.0


func _ready() -> void:
	# Draw over the world but under the HUD, and never take a touch.
	z_index = 0
	_fit()
	get_viewport().size_changed.connect(_fit)


## Cover the viewport to the edges at any aspect.
##
## Width grows with the device ratio under `expand` stretch while height stays
## 360, so a fixed scale would leave bright bands on a wide phone.
func _fit() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var rect: Rect2 = viewport.get_visible_rect()
	if not rect.has_area():
		return
	position = rect.size * 0.5
	scale = Screen.vignette_scale(rect.size)
