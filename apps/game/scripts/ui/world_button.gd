class_name WorldButton
extends Button

## A Button wearing a world-kit face below its native drawing.
##
## Text, icons, focus behavior, signals and hitboxes stay native. The painted
## face lives on a WorldFace backing child with `show_behind_parent`, because
## owner script `_draw` runs after native paint and would bury the label. The
## theme styles are neutralized to invisible margin carriers so minimum sizes
## and text placement never move. Faces repaint on state change only: idle
## buttons cost one tuple compare a frame, never a redraw.

## One of ember, steel, coral or card.
@export var kind: String = "steel"


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	WorldChrome.neutralize(self, kind)
	visibility_changed.connect(_sync_face)
	_sync_face()


## The face exists exactly while the button is drawn. Children run `_ready`
## before their panel hides itself, so a summon-only layer would leak one
## node per button of every closed panel into the late-game node budget.
func _sync_face() -> void:
	if is_visible_in_tree():
		_summon_face()
	else:
		_dismiss_face()


## Attach the paint layer on visibility, never before: the arena holds every
## panel closed, and faces on hidden buttons would spend the late-game node
## budget for pixels nobody sees.
func _summon_face() -> void:
	if get_node_or_null("WorldFace") != null:
		return
	if not is_visible_in_tree():
		return
	var face := WorldFace.new()
	face.watch(self, kind, true)
	add_child(face)
	move_child(face, 0)


## Release the paint layer while hidden. Reopening re-summons one node with
## shared cached textures, so combat peaks never carry closed panels' faces.
func _dismiss_face() -> void:
	var face := get_node_or_null("WorldFace")
	if face != null:
		face.queue_free()
