## Pause card: names the halt, offers the way back. Always processes.
extends Control

signal resume_requested
signal settings_requested

@onready var _title: Label = $Panel/Title
@onready var _resume: Button = $Panel/Resume
@onready var _settings: Button = $Panel/Settings


func _ready() -> void:
	_resume.pressed.connect(_on_resume_pressed)
	_settings.pressed.connect(_on_settings_pressed)
	Settings.changed.connect(_redraw)
	_redraw()


func open() -> void:
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _redraw() -> void:
	_title.text = tr("PAUSED")
	_resume.text = tr("RESUME")
	_settings.text = tr("SETTINGS")


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()
