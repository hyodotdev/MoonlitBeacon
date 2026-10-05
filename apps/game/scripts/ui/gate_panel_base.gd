class_name GatePanelBase
extends Control

## Shared modal shell for the moon gate entry dialogs.
##
## A dim that catches outside taps while the dialog is open, a centered card
## in the shared style, and one rule: hidden at rest, so a closed dialog can
## never eat taps meant for the buttons behind it. `ui_cancel` (back button)
## dismisses through `_on_background_cancel()`, which dangerous dialogs
## override to take the safe branch.

signal closed

const CARD_MIN_WIDTH: float = 340.0

var _dim: ColorRect
var _card: PanelContainer
var _stack: VBoxContainer
var _title_label: Label


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_background_cancel()


## Show the dialog, centered, with its safe default focused.
func open() -> void:
	visible = true
	_recenter_card()
	var focus: Control = _default_focus()
	if focus != null:
		focus.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


## Back-button behavior. Safe dialogs just close; conflict and exit panels
## treat it as their explicit cancel branch.
func _on_background_cancel() -> void:
	close()


## Control to focus on open. `null` leaves focus alone.
func _default_focus() -> Control:
	return null


## Build dim + card + title row. Children add their own rows to `_stack`.
func _build_base(title_key: String, card_min: Vector2) -> void:
	GateEntryStrings.ensure_loaded()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.name = &"Dim"
	_dim.color = GateEntryStyle.DIM_BG
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_card = PanelContainer.new()
	_card.name = &"Card"
	GateEntryStyle.apply_card(_card)
	_card.custom_minimum_size = card_min
	add_child(_card)
	_stack = VBoxContainer.new()
	_stack.name = &"Stack"
	_stack.add_theme_constant_override(&"separation", 8)
	_card.add_child(_stack)
	# Titles stay single-line: they are short locale keys, and an unwrapped
	# label keeps a sane minimum wherever it sits.
	_title_label = GateEntryStyle.make_label(
		title_key, GateEntryStyle.FONT_BODY, GateEntryStyle.TEXT_MAIN, true)
	_title_label.name = &"Title"
	_title_label.clip_text = true
	_stack.add_child(_title_label)
	_recenter_card()
	resized.connect(_recenter_card)
	visibility_changed.connect(_recenter_card)


## Usable content width inside the card. Panels bound their autowrap
## labels to this width so minimum sizes stay sane from birth.
func _content_width() -> float:
	return maxf(
		_card.custom_minimum_size.x - GateEntryStyle.CARD_MARGIN_H, 64.0)


func _recenter_card() -> void:
	if _card == null:
		return
	var view: Vector2 = get_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	# Fixed width, fitted height: wrapped labels are measured at the real
	# content width instead of their exploding minimum size.
	var width: float = minf(
		_card.custom_minimum_size.x, view.x - 32.0)
	var content: float = maxf(width - GateEntryStyle.CARD_MARGIN_H, 64.0)
	var height: float = GateEntryStyle.fitted_stack_height(
		_stack, content) + GateEntryStyle.CARD_MARGIN_V
	height = minf(height, view.y - 16.0)
	# Size first, then center from the read-back rect: assigning below a
	# child's minimum clamps the size up, and centering from the request
	# would leave a clamped card off-center.
	_card.size = Vector2(width, height).ceil()
	_card.position = ((view - _card.size) * 0.5).floor()
