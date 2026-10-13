## Floating stick: stands where pressed, reports the push, hides on release.
extends Control

signal flicked(direction: Vector2)

const MOUSE_TOUCH: int = -2
const FLICK_MIN_STRENGTH: float = 0.6

@export var dead_zone: float = 0.16
@export var radius: float = 64.0

var _touch_index: int = -1
var _origin: Vector2 = Vector2.ZERO
var _value: Vector2 = Vector2.ZERO

@onready var _base: Sprite2D = $Base
@onready var _knob: Sprite2D = $Knob


func get_value() -> Vector2:
	return _value


func reset() -> void:
	## Drop any finger: pausing mid-drag must not strand a stuck push.
	_touch_index = -1
	_value = Vector2.ZERO
	_base.visible = false
	_knob.visible = false


func _gui_input(event: InputEvent) -> void:
	## _gui_input positions arrive in this Control's own coordinates.
	if _touch_index != -1:
		return
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			_touch_index = MOUSE_TOUCH
			_show_at(click.position)
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_touch_index = touch.index
			_show_at(touch.position)


func _input(event: InputEvent) -> void:
	## _input positions are viewport-global; convert before use.
	if _touch_index == -1:
		return
	if event is InputEventMouseMotion and _touch_index == MOUSE_TOUCH:
		_move_to(_to_local(event.position))
	elif event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.button_index == MOUSE_BUTTON_LEFT and not click.pressed and _touch_index == MOUSE_TOUCH:
			_release()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _touch_index:
			_move_to(_to_local(drag.position))
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if not touch.pressed and touch.index == _touch_index:
			_release()


func _to_local(viewport_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_position


func _show_at(local_position: Vector2) -> void:
	_origin = local_position
	_base.position = local_position
	_knob.position = local_position
	_base.visible = true
	_knob.visible = true
	_value = Vector2.ZERO


func _move_to(local_position: Vector2) -> void:
	var push: Vector2 = local_position - _origin
	if push.length() > radius:
		push = push.normalized() * radius
	_knob.position = _origin + push
	var strength: float = push.length() / radius
	if strength < dead_zone:
		_value = Vector2.ZERO
	else:
		_value = push.normalized() * minf(strength, 1.0)


func _release() -> void:
	if _value.length() >= FLICK_MIN_STRENGTH:
		flicked.emit(_value.normalized())
	_touch_index = -1
	_value = Vector2.ZERO
	_base.visible = false
	_knob.visible = false
