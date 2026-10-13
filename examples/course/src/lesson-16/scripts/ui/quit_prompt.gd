## Quit question on the title: Back asks, Yes leaves, No stays.
extends Control

signal quit_confirmed

@onready var _ask: Label = $Panel/Ask
@onready var _yes: Button = $Panel/Yes
@onready var _no: Button = $Panel/No


func _ready() -> void:
	_yes.pressed.connect(_on_yes_pressed)
	_no.pressed.connect(close)
	Settings.changed.connect(_redraw)
	_redraw()


func open() -> void:
	visible = true
	_redraw()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _redraw() -> void:
	_ask.text = tr("QUIT_ASK")
	_yes.text = tr("QUIT_YES")
	_no.text = tr("QUIT_NO")


func _on_yes_pressed() -> void:
	## The title owns the music, so it owns the goodbye: quitting here
	## with the theme playing would leak the voice at exit.
	quit_confirmed.emit()
