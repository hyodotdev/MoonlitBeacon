extends Node

## Side-walk cycle board: all six heroes, left and right, live.
##
## Windowed, for the director's eyes and stills (stays open unless
## `shot=` is given). Twelve panels read the production walk.png
## sheets directly — six heroes times the left column and its mirrored
## right column — and step rows 0,1,2,3 in sync at one calm cycle a
## second, the middle of the intro's 0.8-1.5 band, so contact and
## recovery rows line up across the party. Ground rules sit under each
## row's feet. This is an operational helper, never a game screen.
##     godot --path apps/game res://tools/shot_sidewalk.tscn -- trace=1
##     godot --path apps/game res://tools/shot_sidewalk.tscn -- row=0 shot=/tmp/contact.png
##
## Headless, for wiring (regions, sync, pinning):
##     godot --headless --path apps/game res://tools/shot_sidewalk.tscn -- validate
##
## `row=` pins one stride row for stills (0/2 contact, 1/3 recover).
## `cycle=` sets seconds per full cycle. `t=` waits that many seconds
## before a still. `trace=1` prints one line per second naming every
## panel's row. The title-motion numbers live with the cadence suite,
## which prints the measured per-actor table on every run.

const HERO_PATHS: Array[String] = [
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/sage.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/warden.tres",
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/eclipse.tres",
]
const FACING_LEFT: int = 2
const FACING_RIGHT: int = 3
const PANEL_SCALE: float = 0.35
const COLUMN_X: Array[float] = [100.0, 222.0, 344.0, 466.0, 588.0, 710.0]
const ROW_Y: Array[float] = [110.0, 235.0]
const SETTLE_SECONDS: float = 2.0
const TRACE_INTERVAL: float = 1.0

var _failed: int = 0
var _checked: int = 0
var _clock: float = 0.0
var _cycle: float = 1.0
var _pinned: int = -1
var _row: int = -1
var _trace: bool = false
var _trace_clock: float = 0.0
var _panels: Array = []
var _caption: Label = null


func _ready() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if args.has("validate"):
		_build_board()
		_run_validate()
		if _failed > 0:
			printerr("shot-sidewalk validate failed — ",
				_failed, "/", _checked, " case(s)")
			get_tree().quit(1)
			return
		print("shot-sidewalk validate passed — ", _checked, " case(s)")
		get_tree().quit(0)
		return
	await _run_windowed(args)


func _process(delta: float) -> void:
	if _panels.is_empty():
		return
	_clock += delta
	_show_row(row_for(_clock, _cycle, _pinned))
	if not _trace:
		return
	_trace_clock += delta
	if _trace_clock < TRACE_INTERVAL:
		return
	_trace_clock = 0.0
	var rows: Array = []
	for panel in _panels:
		rows.append((panel["atlas"] as AtlasTexture).region.position.y)
	print("sidewalk t=%.1f rows=%s" % [_clock, str(rows)])


## Stride row for a board clock: pinned stills hold, otherwise four
## rows per cycle from time zero. Pure, so validate pins it exactly.
static func row_for(
	clock_sec: float, cycle_sec: float, pinned: int
) -> int:
	if pinned >= 0:
		return posmod(pinned, 4)
	return int(floor(clock_sec / maxf(cycle_sec, 0.01) * 4.0)) % 4


func _run_windowed(args: Dictionary) -> void:
	_cycle = float(args.get("cycle", 1.0))
	_pinned = int(args.get("row", -1))
	_trace = bool(args.get("trace", false))
	var width: int = int(args.get("width", 808))
	var height: int = int(args.get("height", 360))
	get_window().size = Vector2i(width, height)
	_build_board()
	_show_row(row_for(0.0, _cycle, _pinned))
	if args.has("shot"):
		var wait: float = float(args.get("t", SETTLE_SECONDS))
		await get_tree().create_timer(wait).timeout
		await _save_shot(str(args["shot"]))
		get_tree().quit(0)


func _build_board() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = &"Backdrop"
	backdrop.color = Color(0.07, 0.08, 0.13)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	for facing in [FACING_LEFT, FACING_RIGHT]:
		var rule := ColorRect.new()
		rule.name = &"Ground%d" % facing
		rule.color = Color(1.0, 1.0, 1.0, 0.22)
		rule.position = Vector2(
			60.0, ROW_Y[facing - FACING_LEFT] + 67.0 * 0.5)
		rule.size = Vector2(700.0, 2.0)
		add_child(rule)
		var tag := Label.new()
		tag.name = &"Facing%d" % facing
		tag.text = "LEFT" if facing == FACING_LEFT else "RIGHT"
		tag.position = Vector2(8.0, ROW_Y[facing - FACING_LEFT] - 10.0)
		tag.add_theme_font_size_override("font_size", 15)
		add_child(tag)
	for index in HERO_PATHS.size():
		var hero: Hero = load(HERO_PATHS[index]) as Hero
		var name_tag := Label.new()
		name_tag.name = &"Hero%d" % index
		name_tag.text = WeaponRig.painted_name(hero.attack_profile)
		name_tag.position = Vector2(COLUMN_X[index] - 40.0, 24.0)
		name_tag.size = Vector2(80.0, 24.0)
		name_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_tag.add_theme_font_size_override("font_size", 15)
		add_child(name_tag)
		for facing in [FACING_LEFT, FACING_RIGHT]:
			var atlas := AtlasTexture.new()
			atlas.atlas = hero.walk_sheet
			atlas.region = Rect2(
				facing * hero.sprite_cell.x, 0,
				hero.sprite_cell.x, hero.sprite_cell.y)
			var panel := Sprite2D.new()
			panel.name = &"Panel%d_%d" % [index, facing]
			panel.texture = atlas
			panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			panel.scale = Vector2(PANEL_SCALE, PANEL_SCALE)
			panel.position = Vector2(
				COLUMN_X[index], ROW_Y[facing - FACING_LEFT])
			add_child(panel)
			_panels.append({
				"hero": hero,
				"facing": facing,
				"atlas": atlas,
			})
	_caption = Label.new()
	_caption.name = &"Caption"
	_caption.position = Vector2(0.0, 326.0)
	_caption.size = Vector2(808.0, 26.0)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 15)
	add_child(_caption)


func _show_row(row: int) -> void:
	if row == _row:
		return
	_row = row
	for panel in _panels:
		var hero: Hero = panel["hero"]
		var atlas: AtlasTexture = panel["atlas"]
		atlas.region = Rect2(
			int(panel["facing"]) * hero.sprite_cell.x,
			row * hero.sprite_cell.y,
			hero.sprite_cell.x, hero.sprite_cell.y)
	var stride_pose: String = "contact" if row % 2 == 0 else "recover"
	_caption.text = "row %d · %s · %.1fs / %.1fs cycle, all 12 in sync" % [
		row, stride_pose, _clock, _cycle]


func _save_shot(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("shot-sidewalk: shot= needs a windowed run "
			+ "for real pixels; use validate headless")
		get_tree().quit(2)
		return
	var shot: Image = get_viewport().get_texture().get_image()
	var err: Error = shot.save_png(path)
	if err != OK:
		printerr("shot-sidewalk: could not save ", path)
		get_tree().quit(1)
		return
	print("shot-sidewalk: saved ", path)


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for token in raw:
		if token == "validate":
			out["validate"] = true
		elif token == "trace":
			out["trace"] = true
		elif token.contains("="):
			var parts: PackedStringArray = token.split("=", true, 2)
			if parts[0] in ["trace"]:
				out[parts[0]] = parts[1] not in ["0", "false", ""]
			else:
				out[parts[0]] = parts[1]
	return out


## Headless wiring proof: twelve production panels, exact regions, the
## sync math pinned to the second, pinning honored.
func _run_validate() -> void:
	_expect_true(_panels.size() == 12,
		"twelve side panels stand")
	for panel in _panels:
		var hero: Hero = panel["hero"]
		var atlas: AtlasTexture = panel["atlas"]
		_expect_true(atlas.atlas == hero.walk_sheet,
			"panel reads its production walk sheet")
		_expect_true(hero.walk_sheet.get_size() == Vector2(576, 768),
			"production walk sheet is 576x768")
	for row in 4:
		_show_row(row)
		for panel in _panels:
			var hero: Hero = panel["hero"]
			var atlas: AtlasTexture = panel["atlas"]
			_expect_true(atlas.region == Rect2(
				int(panel["facing"]) * hero.sprite_cell.x,
				row * hero.sprite_cell.y,
				hero.sprite_cell.x, hero.sprite_cell.y),
				"row %d regions sit on the faced column" % row)
	_expect_true(row_for(0.0, 1.0, -1) == 0, "cycle opens on row 0")
	_expect_true(row_for(0.26, 1.0, -1) == 1, "row 1 follows")
	_expect_true(row_for(0.51, 1.0, -1) == 2, "row 2 follows")
	_expect_true(row_for(0.76, 1.0, -1) == 3, "row 3 follows")
	_expect_true(row_for(1.0, 1.0, -1) == 0, "the cycle wraps")
	_expect_true(row_for(99.9, 1.0, 2) == 2, "pinning holds row 2")
	_expect_true(row_for(0.0, 2.0, -1) == 0, "slow cycles open on row 0")
	_expect_true(row_for(1.6, 2.0, -1) == 3, "slow cycles step by time")


func _expect_true(value: bool, message: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("  FAIL ", message)
