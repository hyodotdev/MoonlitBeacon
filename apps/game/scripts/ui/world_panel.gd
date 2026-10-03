class_name WorldPanel
extends Panel

## A Panel that paints a world-kit nine-patch at true logical scale.
##
## Native Panel draws its theme style first and script `_draw` would hide
## underneath it, so the theme style is neutralized to margins in `_ready`
## and the art paints here instead. `self_modulate` still tints the paint,
## which is how the boss bar turns the neutral fill red when low.

## One of the WorldChrome.ART kinds: panel, chip, chip_lit, card, bar_back,
## bar_fill. Plain Panels have no content, so only the painted face matters.
@export var kind: String = "panel"


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_theme_stylebox_override(
		"panel", WorldChrome.margin_style([0.0, 0.0, 0.0, 0.0]))
	resized.connect(queue_redraw)


func _draw() -> void:
	WorldChrome.draw_kind(self, kind)
