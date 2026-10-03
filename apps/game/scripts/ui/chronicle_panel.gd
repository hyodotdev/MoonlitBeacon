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
## Rows here are built in code from the shared world classes. Found memories
## take the lit chip, undiscovered ones the plain chip.

const HEADLINE: Color = Color(1, 0.87, 0.6, 1)
const TEXT: Color = Color(0.92, 0.94, 1, 1)
const TEXT_SECOND: Color = Color(0.72, 0.78, 0.96, 1)
const LOCKED: Color = Color(0.5, 0.54, 0.7, 1)

@onready var _frame: PanelContainer = $Frame
@onready var _header: HBoxContainer = $Frame/Margin/Rows/Header
@onready var _progress: Label = $Frame/Margin/Rows/Header/Progress
@onready var _list: VBoxContainer = $Frame/Margin/Rows/Book/IndexScroll/IndexList
@onready var _scroll: ScrollContainer = $Frame/Margin/Rows/Book/IndexScroll
@onready var _close: Button = $Frame/Margin/Rows/Footer/Close
@onready var _page_section: Label = $Frame/Margin/Rows/Book/Page/PageMargin/PageRows/PageSection
@onready var _page_title: Label = $Frame/Margin/Rows/Book/Page/PageMargin/PageRows/PageTitle
@onready var _page_body: VBoxContainer = \
	$Frame/Margin/Rows/Book/Page/PageMargin/PageRows/PageScroll/PageBody
@onready var _page_state: Label = $Frame/Margin/Rows/Book/Page/PageMargin/PageRows/PageState

## Selected memory id. Focus is selection: the focused row is always the
## shown page, so keyboard and tap never disagree about what is selected.
var _selected_id: String = ""


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_close.pressed.connect(close)


func open() -> void:
	# Book tab and rail crest, hung on first open, never in `_ready`:
	# the arena holds this panel closed and hidden decor would spend the
	# node budget for nothing.
	WorldChrome.ensure_tab(_frame, "book")
	if _header.get_node_or_null("WorldCrest") == null:
		_header.add_child(WorldChrome.crest("book"))
		_header.move_child(_header.get_child(-1), 0)
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
		_list.remove_child(child)
		child.queue_free()
	var first_found: Dictionary = {}
	var first_entry: Dictionary = {}
	for section: Dictionary in Chronicle.sections():
		_list.add_child(_make_header(section))
		for entry: Dictionary in section["entries"]:
			_list.add_child(_make_row(section, entry))
			if first_entry.is_empty():
				first_entry = {"section": section, "entry": entry}
			if first_found.is_empty() \
					and Chronicle.has(str(entry["id"])):
				first_found = {"section": section, "entry": entry}
	_progress.text = tr("CHRONICLE_PROGRESS") % [
		Chronicle.unlocked_count(), Chronicle.total_count()]
	# Keep the open page across rebuilds; otherwise show the first memory
	# actually found, or the first page locked if nothing is found yet.
	if not _select_quiet(str(_selected_id)):
		var pick: Dictionary = first_found if not first_found.is_empty() \
			else first_entry
		if not pick.is_empty():
			_select_row(pick["section"], pick["entry"])


## A section heading. Acts carry their own label (`ACT I`) beside the title.
func _make_header(section: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(WorldChrome.bead())
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


func _make_row(section: Dictionary, entry: Dictionary) -> Control:
	var found: bool = Chronicle.has(str(entry["id"]))
	var card := WorldFrame.new()
	card.kind = "chip_lit" if found else "chip"
	card.custom_minimum_size.y = 34.0
	# The body is PASS so a touch drag reaches the index ScrollContainer;
	# clicks still land in `_gui_input`, which takes focus and the page.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = tr(str(section["title"]))
	card.set_meta(&"entry_id", str(entry["id"]))
	var lines: VBoxContainer = VBoxContainer.new()
	lines.add_theme_constant_override("separation", 1)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lines)
	if not found:
		lines.add_child(_label("?  " + tr("CHRONICLE_LOCKED"), 10, LOCKED, false))
	else:
		var keys: Array = entry["keys"]
		for index in keys.size():
			lines.add_child(_label(
				tr(str(keys[index])), 10,
				TEXT if index == 0 else TEXT_SECOND, index == 0))
	card.gui_input.connect(_on_row_input.bind(card, section, entry))
	card.focus_entered.connect(_select_row.bind(section, entry))
	_mark_selected(card, str(entry["id"]) == _selected_id)
	return card


func _on_row_input(
		event: InputEvent, card: WorldFrame, section: Dictionary,
		entry: Dictionary) -> void:
	var tap: bool = event is InputEventMouseButton \
		and (event as InputEventMouseButton).pressed \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	var touch: bool = event is InputEventScreenTouch \
		and (event as InputEventScreenTouch).pressed
	var key: bool = event is InputEventKey \
		and (event as InputEventKey).pressed \
		and not (event as InputEventKey).echo \
		and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	if tap or touch:
		# Focus first so keyboard and tap agree; the page follows at once
		# even when focus did not move.
		card.grab_focus()
		_select_row(section, entry)
	elif key:
		_select_row(section, entry)


## Show one memory on the page and mark its index row. Called from tap,
## touch, key and focus, so every road lands on the same page.
func _select_row(section: Dictionary, entry: Dictionary) -> void:
	_selected_id = str(entry["id"])
	for child in _list.get_children():
		if child is WorldFrame:
			_mark_selected(child, str(child.get_meta(&"entry_id", "")) == _selected_id)
	_show_page(section, entry)


## Reselect by id without moving focus, for rebuilds. False when the id is
## gone and the caller must pick a page.
func _select_quiet(entry_id: String) -> bool:
	if entry_id.is_empty():
		return false
	for section: Dictionary in Chronicle.sections():
		for entry: Dictionary in section["entries"]:
			if str(entry["id"]) == entry_id:
				_select_row(section, entry)
				return true
	return false


func _mark_selected(card: WorldFrame, selected: bool) -> void:
	card.face_tint = Color(1.16, 1.09, 0.9) if selected else Color.WHITE


## The open page: section, memory title and every recorded line at reading
## size. Locked pages show the same dim `?` line as the index, never the text.
func _show_page(section: Dictionary, entry: Dictionary) -> void:
	var found: bool = Chronicle.has(str(entry["id"]))
	var label_key: String = str(section.get("label", ""))
	_page_section.text = tr(str(section["title"])) \
		if label_key.is_empty() \
		else "%s · %s" % [tr(label_key), tr(str(section["title"]))]
	for child in _page_body.get_children():
		_page_body.remove_child(child)
		child.queue_free()
	if not found:
		_page_title.text = "?"
		_page_body.add_child(_label(tr("CHRONICLE_LOCKED"), 12, LOCKED, false))
	else:
		var keys: Array = entry["keys"]
		_page_title.text = tr(str(keys[0])) if not keys.is_empty() else ""
		for index in keys.size():
			if index == 0:
				continue
			_page_body.add_child(_label(
				tr(str(keys[index])), 12, TEXT_SECOND, false))
	# The page number needs no translation: position among all memories.
	_page_state.text = "%d / %d" % [
		_flat_index(str(entry["id"])), Chronicle.total_count()]


## One-based position of an entry in flat section order.
func _flat_index(entry_id: String) -> int:
	var position: int = 0
	for section: Dictionary in Chronicle.sections():
		for entry: Dictionary in section["entries"]:
			position += 1
			if str(entry["id"]) == entry_id:
				return position
	return position


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
