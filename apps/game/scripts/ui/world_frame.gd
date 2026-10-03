class_name WorldFrame
extends PanelContainer

## A PanelContainer that paints a world-kit nine-patch at true logical scale.
##
## The container keeps measuring and padding from its theme style, so `_ready`
## swaps in an invisible style carrying the old kit's content margins and the
## art paints in `_draw` instead. Children, focus and scroll all stay native.

## One of panel, panel_tight or chip. Margins follow the kind.
@export var kind: String = "panel"
## Paint tint, white by default. The hero preview warms its frame toward the
## hero and shop artwork stages cool toward the product accent.
@export var face_tint: Color = Color.WHITE:
	set(value):
		face_tint = value
		queue_redraw()
## Content-margin override as (left, top, right, bottom). Negative keeps the
## kind default per side; shop coin rows pack tighter than hero rows.
@export var pad: Vector4 = Vector4(-1, -1, -1, -1)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var spec: Dictionary = WorldChrome.ART.get(kind, WorldChrome.ART["panel"])
	var base: Array = spec["margins"]
	var margins: Array = [
		base[0] if pad.x < 0.0 else pad.x,
		base[1] if pad.y < 0.0 else pad.y,
		base[2] if pad.z < 0.0 else pad.z,
		base[3] if pad.w < 0.0 else pad.w,
	]
	add_theme_stylebox_override(
		"panel", WorldChrome.margin_style(margins))
	resized.connect(queue_redraw)


func _draw() -> void:
	WorldChrome.draw_kind(self, kind, face_tint)
