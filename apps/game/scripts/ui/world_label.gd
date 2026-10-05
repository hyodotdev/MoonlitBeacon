class_name WorldLabel
extends Label

## A Label wearing a world-kit plate below its native drawing.
##
## Copy, fonts, alignment and wraps stay native. The painted plate lives on a
## WorldFace backing child with `show_behind_parent`, because owner script
## `_draw` runs after native paint and would bury the text. The theme style is
## neutralized to an invisible carrier holding the old plate's content
## margins, so text placement never moves.

## Title plates carry the old banner's wide margins; chip plates the old
## chip's narrow ones. One of title_plate or chip.
@export var kind: String = "chip"


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var margins: Array = [16.0, 8.0, 16.0, 8.0] \
		if kind == "title_plate" else [5.0, 3.0, 5.0, 3.0]
	add_theme_stylebox_override(
		"normal", WorldChrome.margin_style(margins))
	visibility_changed.connect(_sync_face)
	_sync_face()


## The plate exists exactly while the label is drawn. Children run `_ready`
## before their panel hides itself, so a summon-only layer would leak one
## node per label of every closed panel into the late-game node budget.
func _sync_face() -> void:
	if is_visible_in_tree():
		_summon_face()
	else:
		_dismiss_face()


## Attach the paint layer on visibility, never before: the arena holds every
## panel closed, and plates on hidden labels would spend the late-game node
## budget for pixels nobody sees.
func _summon_face() -> void:
	if get_node_or_null("WorldFace") != null:
		return
	if not is_visible_in_tree():
		return
	var face := WorldFace.new()
	face.watch(self, "chip_lit" if kind == "title_plate" else "chip", false)
	add_child(face)
	move_child(face, 0)


## Release the paint layer while hidden. Reopening re-summons one node with
## shared cached textures, so combat peaks never carry closed panels' plates.
func _dismiss_face() -> void:
	var face := get_node_or_null("WorldFace")
	if face != null:
		face.queue_free()
