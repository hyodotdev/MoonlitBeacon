extends Control

## Floating virtual stick.
##
## Not a stick parked in a fixed spot. **It appears where you press.**
## Hold a phone landscape and the thumb's rest point differs by hand size. A
## fixed stick is too far for some hands and off-screen for others.
##
## Lay this one control over the whole screen and a move stick stands anywhere
## except the dash button. Dash is a separate button at the bottom right.

## This far from origin counts as full input.
@export var radius: float = 22.0

## Inside this, input is 0. Resting a thumb must not start a walk.
@export var dead_zone: float = 0.16

@onready var _base: Sprite2D = $Base
@onready var _knob: Sprite2D = $Knob

## Finger currently holding this stick. -1 if none.
##
## Two fingers can land at once. Walking with one hand, the other may still
## touch the screen; this index keeps the second finger from stealing the stick.
var _touch_index: int = -1
var _origin: Vector2 = Vector2.ZERO
var _value: Vector2 = Vector2.ZERO


func _ready() -> void:
	_base.visible = false
	_knob.visible = false


## Turn the stick off. The arena calls this when a run ends.
##
## `set_process(false)` to **stop reading the value is not enough.**
## This control covers the whole screen and `mouse_filter` defaults to `STOP`,
## so even unread it **swallows touches.** Then the result panel cannot be tapped.
func set_active(value: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	if not value and _touch_index != -1:
		_release()                               # turning off while held would leave the stick drawn


## Direction in -1..1. Zero vector while not pressed.
func get_value() -> Vector2:
	return _value


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and _touch_index == -1:
			_touch_index = touch.index
			_origin = touch.position
			_show_at(_origin)
			accept_event()
		elif not touch.pressed and touch.index == _touch_index:
			_release()
			accept_event()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _touch_index:
			_move_to(drag.position)
			accept_event()


## `_gui_input` stops when the finger leaves the control.
## Leave that alone and the stick stays on, so the character keeps walking.
func _input(event: InputEvent) -> void:
	if _touch_index == -1:
		return
	if event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _touch_index:
		_move_to(make_input_local(event).position)
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if not touch.pressed and touch.index == _touch_index:
			_release()


func _show_at(local_position: Vector2) -> void:
	_base.position = local_position
	_knob.position = local_position
	_base.visible = true
	_knob.visible = true
	_value = Vector2.ZERO


func _move_to(local_position: Vector2) -> void:
	var offset: Vector2 = local_position - _origin
	var length: float = minf(offset.length(), radius)
	var direction: Vector2 = offset.normalized() if offset.length() > 0.001 else Vector2.ZERO

	_knob.position = _origin + direction * length

	var strength: float = length / radius
	_value = Vector2.ZERO if strength < dead_zone else direction * strength


func _release() -> void:
	_touch_index = -1
	_value = Vector2.ZERO
	_base.visible = false
	_knob.visible = false
