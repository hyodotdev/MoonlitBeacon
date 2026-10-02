extends Control

## The Chronicle page: everything the player has met, and blanks for what they
## have not.
##
## Opened from the title. It reads `Chronicle` (what has been seen) and draws
## `Chronicle.sections()` (what there is to see). Rows are built in code from the
## shared UI kit styles, the same way the shrine builds its rows, so the page
## never needs a scene edit when an entry is added.
##
## Unmet entries stay visible as a dim `?` line on purpose. A page with only
## what you have already found never tells you how much is left.

signal closed

const FONT: Font = preload("res://assets/third_party/fonts/Galmuri11-Multilingual.tres")
const FONT_BOLD: Font = preload("res://assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres")
const ROW_STYLE: StyleBox = preload("res://resources/ui/panels/chip.tres")
const ROW_STYLE_FOUND: StyleBox = preload("res://resources/ui/panels/chip_gold.tres")

const HEADLINE: Color = Color(1, 0.87, 0.6, 1)
const TEXT: Color = Color(0.92, 0.94, 1, 1)
const TEXT_SECOND: Color = Color(0.72, 0.78, 0.96, 1)
const LOCKED: Color = Color(0.5, 0.54, 0.7, 1)

@onready var _progress: Label = $Frame/Margin/Rows/Header/Progress
@onready var _list: VBoxContainer = $Frame/Margin/Rows/Scroll/List
@onready var _scroll: ScrollContainer = $Frame/Margin/Rows/Scroll
@onready var _close: Button = $Frame/Margin/Rows/Footer/Close


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_close.pressed.connect(close)


func open() -> void:
	_rebuild()
	_scroll.scroll_vertical = 0
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.22)
	_close.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	for section: Dictionary in Chronicle.sections():
		_list.add_child(_make_header(section))
		for entry: Dictionary in section["entries"]:
			_list.add_child(_make_row(entry))
	_progress.text = tr("CHRONICLE_PROGRESS") % [
		Chronicle.unlocked_count(), Chronicle.total_count()]


## A section heading. Acts carry their own label (`ACT I`) beside the title.
func _make_header(section: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label_key: String = str(section.get("label", ""))
	# Not expanded: an expanding label splits the row, and the act number ended up
	# a screen-width away from its own title.
	if not label_key.is_empty():
		row.add_child(_label(tr(label_key), 10, LOCKED, true, false))
	row.add_child(_label(tr(str(section["title"])), 13, HEADLINE, true, false))
	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 4)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)
	return pad


func _make_row(entry: Dictionary) -> Control:
	var found: bool = Chronicle.has(str(entry["id"]))
	var card: PanelContainer = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", ROW_STYLE_FOUND if found else ROW_STYLE)
	var lines: VBoxContainer = VBoxContainer.new()
	lines.add_theme_constant_override("separation", 1)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lines)
	if not found:
		lines.add_child(_label("?  " + tr("CHRONICLE_LOCKED"), 10, LOCKED, false))
		return card
	var keys: Array = entry["keys"]
	for index in keys.size():
		lines.add_child(_label(
			tr(str(keys[index])), 10, TEXT if index == 0 else TEXT_SECOND, index == 0))
	return card


func _label(text: String, size: int, color: Color, bold: bool, expand: bool = true) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Only a label that fills its row may wrap. An autowrapping label that does not
	# expand has no width to wrap against and collapses to one character a line.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if expand else TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_SHRINK_BEGIN
	label.add_theme_font_override("font", FONT_BOLD if bold else FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and visible:
		_rebuild.call_deferred()


## Close on back. Without this, Android is trapped.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		accept_event()
		close()
