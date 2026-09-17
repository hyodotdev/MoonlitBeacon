extends Control

## Leaderboard and name entry. One panel with two faces.
##
## There is a reason they are not split. In an arcade, typing a name and the
## ranks rolling up are **one connected scene**. Change screens and that link
## dies. Enter a name and the table appears in place with your row lit.

signal closed

## Rows shown on the table. Five is the limit on 808×360.
const SHOW: int = 5
const BOARD_FONT: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres"
)

@onready var _title: Label = $Center/Rows/Title
@onready var _pending_summary: Label = $Center/Rows/Pending
@onready var _entry: HBoxContainer = $Center/Rows/Entry
@onready var _name: LineEdit = $Center/Rows/Entry/Name
@onready var _submit: Button = $Center/Rows/Entry/Submit
@onready var _board: VBoxContainer = $Center/Rows/Board
@onready var _close: Button = $Center/Rows/Close

## Record waiting to be submitted. Empty means view-only.
var _pending: Dictionary = {}
var _mine: int = -1
## Global board. Empty means draw local.
var _global: Array = []
## Accept a late server response only while viewing the global board from title.
## Result submit reuses this panel, so accepting without a mode check can mix
## global rows with the local `_mine` index and light the wrong record as yours.
var _accept_global: bool = false


func _ready() -> void:
	visible = false
	# Redraw when the global board arrives. No key and this signal never comes —
	# the local board is already up, so the screen is not empty.
	GlobalLadder.board_arrived.connect(_on_global)
	_submit.pressed.connect(_on_submit)
	_close.pressed.connect(close)
	_name.max_length = Ladder.NAME_MAX
	# Enter also submits. People on a physical keyboard should not have to find the button.
	_name.text_submitted.connect(func(_t: String) -> void: _on_submit())


## Ask for a name and submit. The result screen calls this. `run_id` is not a
## server field — a client boundary that only blocks tapping the same final
## score of the same run more than once.
func ask(score: int, rank_letter: String, cycles: int, hero_id: String,
		run_id: String = "") -> void:
	_accept_global = false
	_global = []
	_pending = {
		"score": score,
		"rank": rank_letter,
		"cycles": cycles,
		"hero": hero_id,
		"run_id": run_id,
	}
	_mine = -1
	_title.text = tr("LADDER_NEW")
	# Show what will go up before the name is confirmed. Score alone makes a
	# record on another hero or a different-balance version look like the same run.
	_pending_summary.text = tr("LADDER_PENDING") % [
		_hero_name(hero_id), Ladder.current_version(), score]
	_pending_summary.visible = true
	_entry.visible = true
	# Prefill the last name. **Make people type every time and they skip submit on run two.**
	_name.text = Ladder.last_name
	_name.select_all()
	_draw_board()
	_show()


## Just look at ranks. Called from the title.
func view() -> void:
	_accept_global = true
	_global = []
	_pending = {}
	_mine = -1
	_title.text = tr("LADDER_TITLE")
	_pending_summary.visible = false
	_entry.visible = false
	_draw_board()
	GlobalLadder.fetch_board()                            # if it arrives, redraw over with global
	_show()


func _show() -> void:
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.22)
	if _entry.visible:
		_name.grab_focus()


func close() -> void:
	# **Closing without submit still keeps the record.** Drop it here and there
	# is nowhere to undo — the arena swaps scenes as soon as it gets `closed`.
	# An empty name is filled as anonymous by `_sanitize()`, so nothing is lost.
	if not _pending.is_empty():
		if not _on_submit():
			return
	_accept_global = false
	visible = false
	closed.emit()


func _on_submit() -> bool:
	if _pending.is_empty():
		return true
	var player: String = _name.text
	var hero: String = str(_pending.get("hero", ""))
	var score: int = int(_pending.get("score", 0))
	var letter: String = str(_pending.get("rank", "D"))
	var cycles: int = int(_pending.get("cycles", 0))
	var run_id: String = str(_pending.get("run_id", ""))

	_mine = Ladder.submit(player, hero, score, letter, cycles, run_id)
	if _mine < 0:
		# Until the local record is actually saved, do not commit global submit,
		# screen close, or dedupe. Keep the input so a retry can run after the
		# save path is restored.
		_pending_summary.text = tr("SHRINE_SAVE_FAILED")
		_pending_summary.visible = true
		_entry.visible = true
		_name.grab_focus()
		return false
	# Upload globally too. Failure is a no-op — it already lives locally.
	GlobalLadder.submit(Ladder.last_name, hero, score, letter, cycles, run_id)
	_accept_global = false
	_global = []
	_pending = {}
	_pending_summary.visible = false
	_entry.visible = false
	_title.text = tr("LADDER_TITLE")
	_draw_board()
	return true


## Global board arrived. Draw this instead of local.
##
## Local is not deleted. Open next time with no network and local comes back.
func _on_global(rows: Array) -> void:
	if rows.is_empty() or not visible or not _accept_global:
		return
	_global = rows
	_draw_board()


func _draw_board() -> void:
	for old in _board.get_children():
		_board.remove_child(old)
		old.queue_free()

	# Use global if present, otherwise local.
	var table: Array = Ladder.sorted_copy(
		_global if not _global.is_empty() else Ladder.entries)
	if _pending.is_empty():
		_title.text = tr("LADDER_GLOBAL") if not _global.is_empty() else tr("LADDER_TITLE")

	if table.is_empty():
		_board.add_child(_line(tr("LADDER_EMPTY"), Color(0.7, 0.74, 0.82, 1), true))
		return

	for i in mini(table.size(), SHOW):
		var row: Dictionary = table[i]
		var text: String = _format_row(i + 1, row)
		# Light only the row just entered. **Cannot find your place on the board** and submit had no payoff.
		var tone: Color = Color(1, 0.92, 0.6, 1) if i == _mine else Color(0.78, 0.82, 0.9, 1)
		_board.add_child(_line(text, tone))

	# If your row is outside the top five, append it as its own line.
	if _mine >= SHOW and _global.is_empty():
		var mine: Dictionary = Ladder.entries[_mine]
		_board.add_child(_line(_format_row(_mine + 1, mine),
			Color(1, 0.92, 0.6, 1)))


func _hero_name(path: String) -> String:
	# Do not trust strings from local JSON or the public global board. Load
	# only the known six resources so one corrupt record cannot error every
	# time the screen opens.
	if path not in Vault.HEROES:
		return tr("LADDER_UNKNOWN_HERO")
	var hero: Hero = load(path) as Hero
	return tr(hero.display_name) if hero != null else tr("LADDER_UNKNOWN_HERO")


func _format_row(place: int, row: Dictionary) -> String:
	return "%d.  %-8s  %s  %s  %d  v%s" % [
		place,
		str(row.get("name", "")),
		_hero_name(str(row.get("hero", ""))),
		str(row.get("rank", "-")),
		int(row.get("score", 0)),
		str(row.get("version", Ladder.LEGACY_VERSION)),
	]


func _line(text: String, tone: Color, center: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text
	# Table rows left-align so place and name line up vertically.
	# A one-line notice like "no records" is centered.
	label.horizontal_alignment = \
		HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size = Vector2(480, 0)
	label.add_theme_color_override("font_color", tone)
	label.add_theme_font_override("font", BOARD_FONT)
	label.add_theme_font_size_override("font_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		accept_event()
		close()
