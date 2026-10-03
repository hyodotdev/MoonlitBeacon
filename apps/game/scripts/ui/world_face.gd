class_name WorldFace
extends Control

## A world-kit paint layer pinned BEHIND its owner's native drawing.
##
## Owner script `_draw` runs after native paint, so a face painted there would
## bury the button's label. `show_behind_parent` instead puts this layer below
## everything the owner draws: native text, icons and focus stay on top and
## stay native, hitboxes and signals never move. Full-rect anchors track the
## owner through resizes; button faces repaint on a cached state signature,
## plates paint once.

## Button road (ember, steel, coral, card) or plate art (chip, chip_lit).
@export var kind: String = "steel"
## True when watching a Button's hover/press/disabled/focus states.
@export var live: bool = true

var _target: Control
var _signature: Array = []


## Pin to a button or label. Called before the owner enters the tree.
func watch(target: Control, face_kind: String, track_state: bool) -> void:
	_target = target
	kind = face_kind
	live = track_state
	name = &"WorldFace"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	show_behind_parent = true
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	if is_instance_valid(_target):
		_target.resized.connect(queue_redraw)
		_target.visibility_changed.connect(_sync_process)
		_signature = _state_signature()
	_sync_process()


func _process(_delta: float) -> void:
	if not is_instance_valid(_target):
		return
	var current: Array = _state_signature()
	if current != _signature:
		_signature = current
		queue_redraw()


## Poll only while the target is actually on screen; hidden panels cost
## nothing per frame.
func _sync_process() -> void:
	set_process(live and is_instance_valid(_target)
		and _target.is_visible_in_tree())


func _draw() -> void:
	if not is_instance_valid(_target):
		return
	if _target is Button:
		WorldChrome.draw_button_on(self, kind, _target as Button)
	else:
		WorldChrome.draw_kind(self, kind)


func _state_signature() -> Array:
	if _target is Button:
		var button := _target as Button
		return [button.disabled, button.is_pressed(), button.is_hovered(),
			button.has_focus()]
	return [true]
