## Pause card: names the halt, offers the way back. Always processes.
extends Control

signal resume_requested

@onready var _resume: Button = $Panel/Resume


func _ready() -> void:
	_resume.pressed.connect(_on_resume_pressed)


func open() -> void:
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _on_resume_pressed() -> void:
	resume_requested.emit()
