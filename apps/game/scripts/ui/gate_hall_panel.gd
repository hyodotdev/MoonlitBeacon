class_name GateHallPanel
extends GatePanelBase

## Hall of ranks, drawn only from host-supplied rows.
##
## Each row carries a real hero portrait (a `Hero` resource or a texture the
## host hands over), a rank, a score and a unique ID, plus cached/offline
## labels when the host says the row is stale. An empty row list shows the
## honest empty line; this panel never invents population.

signal rows_closed

const PORTRAIT_SIZE: float = 44.0
const ROW_MIN_HEIGHT: float = 56.0
const LIST_MAX_HEIGHT: float = 176.0
## ID wrap bound: card content 388 less row padding 16, portrait 44 and
## separation 10 is 318; 300 stays safely at or below the assigned width.
const ROW_ID_WIDTH: float = 300.0

var _badges_row: HBoxContainer
var _cached_badge: Label
var _offline_badge: Label
var _scroll: ScrollContainer
var _rows_box: VBoxContainer
var _empty_label: Label
var _close_button: Button


func _ready() -> void:
	_build_base("gate.hall.title", Vector2(CARD_MIN_WIDTH + 80.0, 0.0))
	_badges_row = HBoxContainer.new()
	_badges_row.name = &"Badges"
	_badges_row.add_theme_constant_override(&"separation", 8)
	_stack.add_child(_badges_row)
	_cached_badge = GateEntryStyle.make_label(
		"gate.hall.cached", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.ACCENT_AMBER)
	_cached_badge.name = &"CachedBadge"
	_badges_row.add_child(_cached_badge)
	_offline_badge = GateEntryStyle.make_label(
		"gate.hall.offline", GateEntryStyle.FONT_SMALL, GateEntryStyle.CORAL)
	_offline_badge.name = &"OfflineBadge"
	_badges_row.add_child(_offline_badge)
	_scroll = ScrollContainer.new()
	_scroll.name = &"Rows"
	_scroll.custom_minimum_size = Vector2(0.0, ROW_MIN_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stack.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.name = &"RowsBox"
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override(&"separation", 6)
	_scroll.add_child(_rows_box)
	_empty_label = GateEntryStyle.make_label(
		"gate.hall.empty", GateEntryStyle.FONT_SMALL, GateEntryStyle.TEXT_DIM)
	_empty_label.name = &"Empty"
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.custom_minimum_size.x = _content_width()
	_stack.add_child(_empty_label)
	_close_button = GateEntryStyle.make_button("gate.hall.close")
	_close_button.name = &"Close"
	_close_button.pressed.connect(_on_close)
	_stack.add_child(_close_button)
	visible = false


## Render `rows` exactly as supplied. `meta` may hold `cached` and `offline`
## flags for the header badges. Row dictionaries read `rank` (int),
## `score` (int), `id` (String), and either `hero` (Hero) or `portrait`
## (Texture2D) with an optional `hero_name`. A verified `display` handle
## joins the headline; rows without one keep the honest rank-and-score
## headline with the full ID on its own line.
func show_rows(rows: Array, meta: Dictionary = {}) -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	for index in rows.size():
		_rows_box.add_child(_make_row(rows[index], index))
	_empty_label.visible = rows.is_empty()
	_scroll.visible = not rows.is_empty()
	_cached_badge.visible = bool(meta.get("cached", false))
	_offline_badge.visible = bool(meta.get("offline", false))
	_badges_row.visible = _cached_badge.visible or _offline_badge.visible
	_scroll.custom_minimum_size = Vector2(
		0.0, minf(float(maxi(rows.size(), 1)) * (ROW_MIN_HEIGHT + 6.0),
			LIST_MAX_HEIGHT))
	open()


func row_count() -> int:
	return _rows_box.get_child_count()


func _default_focus() -> Control:
	return _close_button


func _on_close() -> void:
	visible = false
	rows_closed.emit()
	closed.emit()


func _make_row(data: Dictionary, index: int) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = &"HallRow%d" % index
	row.add_theme_stylebox_override(
		&"panel", GateEntryStyle.hall_row_style(index))
	row.custom_minimum_size = Vector2(0.0, ROW_MIN_HEIGHT)
	var line := HBoxContainer.new()
	line.name = &"Line"
	line.add_theme_constant_override(&"separation", 10)
	row.add_child(line)
	var portrait := TextureRect.new()
	portrait.name = &"Portrait"
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.texture = _row_portrait(data)
	portrait.visible = portrait.texture != null
	line.add_child(portrait)
	var middle := VBoxContainer.new()
	middle.name = &"Middle"
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override(&"separation", 2)
	line.add_child(middle)
	var rank: int = int(data.get("rank", 0))
	var score: int = int(data.get("score", 0))
	var headline := GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_BODY, GateEntryStyle.TEXT_MAIN, true)
	headline.name = &"Headline"
	var display: String = str(data.get("display", ""))
	if display.is_empty():
		headline.text = "#%d · %d" % [rank, score]
	else:
		headline.text = "#%d · %d · %s" % [rank, score, display]
	middle.add_child(headline)
	var hero_name: String = str(data.get("hero_name", ""))
	var hero: Hero = data.get("hero") as Hero
	if hero_name.is_empty() and hero != null:
		hero_name = hero.display_name
		if not hero_name.is_empty():
			hero_name = tr(hero_name)
	# Hero name and ID live on separate lines. The ID wraps inside the
	# row instead of stretching it: a real 35-character ID as one line
	# would push the card past its intended width and off-center it.
	var hero_line := GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_SMALL, GateEntryStyle.TEXT_DIM)
	hero_line.name = &"HeroLine"
	hero_line.text = hero_name
	hero_line.visible = not hero_name.is_empty()
	middle.add_child(hero_line)
	var id_line := GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_SMALL, GateEntryStyle.TEXT_FAINT)
	id_line.name = &"IdLine"
	id_line.text = str(data.get("id", ""))
	id_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Bound just under the real middle width (318): the minimum must be
	# measured at or below the assigned width, never above, or a wrapped
	# line would overflow its row.
	id_line.custom_minimum_size.x = ROW_ID_WIDTH
	middle.add_child(id_line)
	return row


func _row_portrait(data: Dictionary) -> Texture2D:
	var portrait: Texture2D = data.get("portrait") as Texture2D
	if portrait != null:
		return portrait
	var hero: Hero = data.get("hero") as Hero
	if hero != null:
		return hero.portrait
	return null


