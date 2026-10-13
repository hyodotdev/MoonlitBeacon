## The moonlight gate: hidden until every beacon burns, then the way out.
extends Node2D

signal entered

const OPEN_SECONDS: float = 0.5

@onready var _enter: Area2D = $Enter

var _open: bool = false


func _ready() -> void:
	_enter.body_entered.connect(_on_enter_body_entered)


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	modulate.a = 0.0
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 1.0, OPEN_SECONDS)
	await fade.finished
	if is_inside_tree():
		_enter.monitoring = true


func disarm() -> void:
	_enter.set_deferred("monitoring", false)


func is_open() -> bool:
	return _open


func _on_enter_body_entered(_body: Node2D) -> void:
	if _open:
		entered.emit()
