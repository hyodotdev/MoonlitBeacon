extends Control

## Ask once whether they really want to quit.
##
## Stops a stray back press from closing the game.
## **The default is "go back".** A confirm dialog must not rest the finger on
## the dangerous choice.

signal cancelled

@onready var _no: Button = $No
@onready var _card: Panel = $Card


func _ready() -> void:
	_no.pressed.connect(close)
	$Yes.pressed.connect(_quit)


func open() -> void:
	# The gate sigil over the gate-return question; the title starts well
	# below the card's top edge, so the tab never touches it. Hung on first
	# open, never in `_ready` (arena node budget).
	WorldChrome.ensure_tab(_card, "gate")
	visible = true
	_no.grab_focus()


func close() -> void:
	visible = false
	cancelled.emit()


## Save before leaving.
##
## Android can kill the app at any time. Settings and records already save on
## every change; writing again here means **this really is the end**.
func _quit() -> void:
	Settings.save_settings()
	Records.save_records()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
