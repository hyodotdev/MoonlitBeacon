class_name GateExitPanel
extends GatePanelBase

## "End at the gate?" ask, in the entry surface's own voice.
##
## The safe choice owns the focus: "stay" and the back button both take the
## `cancelled` branch. This panel never quits the app itself; the host quits
## when `confirmed` arrives, which keeps the exit testable and the app
## lifecycle in one pair of hands.

signal confirmed
signal cancelled

var _stay_button: Button


func _ready() -> void:
	_build_base("gate.exit.title", Vector2(CARD_MIN_WIDTH, 0.0))
	var body := GateEntryStyle.make_label(
		"gate.exit.body", GateEntryStyle.FONT_SMALL, GateEntryStyle.TEXT_DIM)
	body.name = &"Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = _content_width()
	_stack.add_child(body)
	var row := HBoxContainer.new()
	row.name = &"Choices"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 8)
	_stack.add_child(row)
	var end_button := GateEntryStyle.make_button("gate.exit.quit", "danger")
	end_button.name = &"End"
	end_button.pressed.connect(_on_end)
	row.add_child(end_button)
	_stay_button = GateEntryStyle.make_button("gate.exit.stay", "primary")
	_stay_button.name = &"Stay"
	_stay_button.pressed.connect(_on_stay)
	row.add_child(_stay_button)
	visible = false


func _default_focus() -> Control:
	return _stay_button


func _on_background_cancel() -> void:
	_on_stay()


func _on_end() -> void:
	visible = false
	confirmed.emit()


func _on_stay() -> void:
	visible = false
	cancelled.emit()
