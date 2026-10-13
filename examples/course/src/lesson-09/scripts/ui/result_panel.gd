## Win/lose panel: names the ending, then offers one guarded restart.
extends Control

signal restart_requested

const ACCEPT_DELAY: float = 0.6
const WIN_TEXT: String = "All beacons are burning"
const LOSE_TEXT: String = "The night takes you"

@onready var _title: Label = $Panel/Title
@onready var _restart: Button = $Panel/Restart


func _ready() -> void:
	_restart.pressed.connect(_on_restart_pressed)


func show_result(won: bool) -> void:
	visible = true
	_title.text = WIN_TEXT if won else LOSE_TEXT
	_restart.disabled = true
	await get_tree().create_timer(ACCEPT_DELAY).timeout
	if is_inside_tree():
		_restart.disabled = false


func is_accepting() -> bool:
	return visible and not _restart.disabled


func _on_restart_pressed() -> void:
	restart_requested.emit()
