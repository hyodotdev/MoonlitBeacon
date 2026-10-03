extends Node

## Render harness for the walking forecourt party on the original title.
##
## Windowed, for the director's eyes, stills, and clips (stays open
## unless `shot=` is given):
##     godot --path apps/game res://tools/shot_forecourt_party.tscn -- trace=1
##     godot --path apps/game res://tools/shot_forecourt_party.tscn -- state=selection t=6.0 shot=/tmp/party.png
##
## For the 10-14 second title clip: run windowed at the native framing
## with `trace=1`, capture the window externally for 10-14 seconds, and
## keep the trace log beside it — it names every sheet and facing
## change per actor per second.
##
## Headless, for invariants (title and selection at every framing):
##     godot --headless --path apps/game res://tools/shot_forecourt_party.tscn -- validate
##
## `state=` picks title (the tap prompt and small doors over the
## party walking the forest clearing) or selection (the login
## chooser, which quietly conceals the party). `t=` waits that many
## seconds before a still. `trace=1` prints one line per actor per
## second. `reduced_motion=1` freezes the party mid-pose. No host
## override: title rest needs no providers, and the selection reads
## honestly unconfigured.

const PRODUCTION_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")
const FRAMINGS: Array[Vector2i] = [
	Vector2i(808, 360), Vector2i(840, 360), Vector2i(808, 606)]
const FACING_NAMES: Array[String] = ["down", "up", "left", "right"]
const OPEN_CENTER: Vector2 = Vector2(404.0, 258.0)
const OPEN_RADII: Vector2 = Vector2(196.0, 90.0)
const OPEN_LIMIT: float = 0.80
const FIRE_BOX: Rect2 = Rect2(388, 200, 42, 72)
const SOLID_PROPS: Array[String] = [
	"NightForest/Trees/T925",
	"NightForest/Details/D025",
]
const SETTLE_SECONDS: float = 2.0
const TRACE_INTERVAL: float = 1.0
const VALIDATE_SECONDS: float = 2.5
const VALIDATE_INTERVAL: float = 0.25

var _failed: int = 0
var _checked: int = 0
var _trace: bool = false
var _trace_clock: float = 0.0
var _party: ProductionEntry = null


func _ready() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if args.has("validate"):
		await _run_validate()
		if _failed > 0:
			printerr("shot-forecourt-party validate failed — ",
				_failed, "/", _checked, " case(s)")
			get_tree().quit(1)
			return
		print("shot-forecourt-party validate passed — ",
			_checked, " case(s)")
		get_tree().quit(0)
		return
	await _run_windowed(args)


func _process(delta: float) -> void:
	if not _trace or _party == null or not is_instance_valid(_party):
		return
	_trace_clock += delta
	if _trace_clock < TRACE_INTERVAL:
		return
	_trace_clock = 0.0
	var gate: GateEntry = _party.get_node("Gate") as GateEntry
	var forecourt: GateHeroForecourt = gate.get_forecourt()
	for index in forecourt.actor_count():
		var info: Dictionary = forecourt.actor_info(index)
		var hero: Hero = load(str(info["hero_path"])) as Hero
		var hero_id: String = WeaponRig.painted_name(hero.attack_profile)
		var feet: Vector2 = info["feet"]
		print("party t=%.1f %s feet=(%d, %d) facing=%s sheet=%s frame=%d moving=%s" % [
			Time.get_ticks_msec() / 1000.0, hero_id,
			int(feet.x), int(feet.y),
			FACING_NAMES[int(info["facing"])],
			"walk" if bool(info["moving"]) else "idle",
			int(info["frame"]), str(bool(info["moving"]))])


func _run_windowed(args: Dictionary) -> void:
	var state: String = str(args.get("state", "title"))
	var locale: String = str(args.get("locale", "ko"))
	var width: int = int(args.get("width", 808))
	var height: int = int(args.get("height", 360))
	var wait: float = float(args.get("t", SETTLE_SECONDS))
	_trace = bool(args.get("trace", false))
	TranslationServer.set_locale(locale)
	get_window().size = Vector2i(width, height)
	_party = PRODUCTION_SCENE.instantiate() as ProductionEntry
	add_child(_party)
	await get_tree().process_frame
	await get_tree().process_frame
	var gate: GateEntry = _party.get_node("Gate") as GateEntry
	if bool(args.get("reduced_motion", false)):
		gate.set_reduced_motion(true)
	if state == "selection":
		(_party.get_node("Title") as Variant).request_start()
		await get_tree().process_frame
		await get_tree().process_frame
	if args.has("shot"):
		await get_tree().create_timer(wait).timeout
		await _save_shot(str(args["shot"]))
		get_tree().quit(0)


func _save_shot(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("shot-forecourt-party: shot= needs a windowed run "
			+ "for real pixels; use validate headless")
		get_tree().quit(2)
		return
	var shot: Image = get_viewport().get_texture().get_image()
	var err: Error = shot.save_png(path)
	if err != OK:
		printerr("shot-forecourt-party: could not save ", path)
		get_tree().quit(1)
		return
	print("shot-forecourt-party: saved ", path)


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for token in raw:
		if token == "validate":
			out["validate"] = true
		elif token == "trace":
			out["trace"] = true
		elif token.contains("="):
			var parts: PackedStringArray = token.split("=", true, 2)
			if parts[0] in ["reduced_motion", "trace"]:
				out[parts[0]] = parts[1] not in ["0", "false", ""]
			else:
				out[parts[0]] = parts[1]
	return out


## Headless invariant sweep: title and selection at every framing. The
## registered party suite is the rigorous proof; this is the fast
## iteration sweep for render work.
func _run_validate() -> void:
	var original_size: Vector2i = get_tree().root.size
	TranslationServer.set_locale("en")
	for framing in FRAMINGS:
		for state in ["title", "selection"]:
			await _validate_combo(framing, state)
	get_tree().root.size = original_size


func _validate_combo(framing: Vector2i, state: String) -> void:
	var tag: String = "%s/%dx%d" % [state, framing.x, framing.y]
	get_tree().root.size = framing
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	add_child(production)
	await get_tree().process_frame
	await get_tree().process_frame
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	if state == "selection":
		title.request_start()
		await get_tree().process_frame
		await get_tree().process_frame
		_expect_true(gate.is_selection_open(),
			"%s: selection opens" % tag)
	else:
		_expect_true(gate.is_title_rest(),
			"%s: card parked" % tag)
	var forecourt: GateHeroForecourt = gate.get_forecourt()
	_expect_true(forecourt.actor_count() == 6,
		"%s: six heroes walk" % tag)
	_expect_true(forecourt.is_world_mode(),
		"%s: production stages the forest world" % tag)
	if state == "selection":
		_expect_true(not forecourt.visible,
			"%s: the selection conceals the party" % tag)
	else:
		_expect_true(forecourt.visible,
			"%s: the party shows at title rest" % tag)
	var first: Array = []
	for index in forecourt.actor_count():
		first.append(forecourt.actor_info(index)["feet"])
	var saw_walk: int = 0
	var saw_idle: int = 0
	var facings: Dictionary = {}
	var start: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start) / 1000.0 < VALIDATE_SECONDS:
		await get_tree().create_timer(VALIDATE_INTERVAL).timeout
		_check_combo_clear(title, gate, forecourt, tag)
		_check_world_placement(title, forecourt, tag)
		for index in forecourt.actor_count():
			var info: Dictionary = forecourt.actor_info(index)
			if bool(info["moving"]):
				saw_walk += 1
				_check_walk_truth(forecourt, index, info, tag)
			else:
				saw_idle += 1
			facings[int(info["facing"])] = true
			var feet: Vector2 = info["feet"]
			var root: Node2D = forecourt.get_node(
				"HeroActor%d" % index) as Node2D
			_expect_true(root.z_index == int(feet.y),
				"%s: hero %d sorts by its ground" % [tag, index])
			var paint: Vector2 = info["paint_size"]
			_expect_true(paint.y >= GateHeroForecourt.WORLD_PAINT_MIN \
				and paint.y <= GateHeroForecourt.WORLD_PAINT_MAX,
				"%s: hero %d reads world scale" % [tag, index])
	var moved: int = 0
	for index in forecourt.actor_count():
		var feet: Vector2 = forecourt.actor_info(index)["feet"]
		if (feet - (first[index] as Vector2)).length() > 1.0:
			moved += 1
	_expect_true(moved >= 1, "%s: the party travels" % tag)
	_expect_true(saw_walk >= 1 and saw_idle >= 1,
		"%s: walk and idle sheets both show" % tag)
	_expect_true(facings.size() >= 2,
		"%s: more than one facing shows" % tag)
	_expect_true(forecourt.find_children(
		"*", "Timer", true, false).is_empty(),
		"%s: no timers behind the party" % tag)
	production.queue_free()
	await get_tree().process_frame


## A walking sample shows the hero's own walk sheet in the faced
## column; a stopped sample shows the idle sheet. Regions stay inside
## the real sheet at the real 144x192 cell.
func _check_walk_truth(
	forecourt: GateHeroForecourt, index: int, info: Dictionary, tag: String
) -> void:
	var hero: Hero = load(str(info["hero_path"])) as Hero
	var body: Sprite2D = forecourt.get_node(
		"HeroActor%d/Body" % index) as Sprite2D
	var atlas: AtlasTexture = body.texture as AtlasTexture
	_expect_true(atlas != null and atlas.atlas == hero.walk_sheet,
		"%s: hero %d walks its own sheet" % [tag, index])
	if atlas == null:
		return
	_expect_true(atlas.region.size == Vector2(hero.sprite_cell),
		"%s: hero %d keeps the 144x192 cell" % [tag, index])
	var sheet_rect := Rect2(Vector2.ZERO, hero.walk_sheet.get_size())
	_expect_true(sheet_rect.encloses(atlas.region),
		"%s: hero %d region sits inside the sheet" % [tag, index])
	_expect_true(int(atlas.region.position.x) \
		== int(info["facing"]) * hero.sprite_cell.x,
		"%s: hero %d walks the faced column" % [tag, index])


## Feet stay on the tree-free clearing through the center offset,
## clear of the beacon fire; paint clears the fire and the nearest
## solid props read back from the live forest.
func _check_world_placement(
	title: Variant, forecourt: GateHeroForecourt, tag: String
) -> void:
	var view: Vector2 = Vector2(get_tree().root.size)
	var offset: Vector2 = Screen.center_offset(view)
	var fire := Rect2(FIRE_BOX.position + offset, FIRE_BOX.size)
	var solids: Array[Rect2] = []
	for path in SOLID_PROPS:
		var prop: Node2D = title.get_node_or_null(path) as Node2D
		_expect_true(prop != null,
			"%s: solid prop %s stands" % [tag, path])
		if prop == null:
			continue
		var sprite: Sprite2D = prop as Sprite2D
		solids.append(Rect2(
			prop.position + offset,
			sprite.region_rect.size * sprite.scale))
	for index in forecourt.actor_count():
		var info: Dictionary = forecourt.actor_info(index)
		var ground: Vector2 = (info["feet"] as Vector2) - offset
		var r: float = Vector2(
			(ground.x - OPEN_CENTER.x) / OPEN_RADII.x,
			(ground.y - OPEN_CENTER.y) / OPEN_RADII.y).length()
		_expect_true(r <= OPEN_LIMIT,
			"%s: hero %d feet read ground %.2f" % [tag, index, r])
		var rect: Rect2 = info["paint_rect"]
		_expect_true(
			not rect.grow(-1.0).intersects(fire.grow(-1.0)),
			"%s: hero %d paint clears the fire" % [tag, index])
		for zone in solids:
			_expect_true(
				not rect.grow(-1.0).intersects(zone.grow(-1.0)),
				"%s: hero %d paint clears %s" % [tag, index, zone])


## Paint stays inside the viewport and clear of what the player reads:
## prompt glyphs, doors and version on the title; the card and badge
## under the selection; the gate mouth everywhere.
func _check_combo_clear(
	title: Variant, gate: GateEntry, forecourt: GateHeroForecourt,
	tag: String
) -> void:
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	# A concealed party hides behind the modal by design: the login
	# panel may cover it. Only a visible party must clear the chrome.
	var clear: Array[Rect2] = []
	if forecourt.visible:
		clear.append(forecourt.gate_mouth_rect())
	if gate.is_title_rest():
		var prompt: Label = title.get_node("Ui/Screen/TapPrompt") as Label
		var font: Font = prompt.get_theme_font("font")
		var ink: float = font.get_string_size(tr(prompt.text),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			float(prompt.get_theme_font_size("font_size"))).x
		var prompt_rect: Rect2 = prompt.get_global_rect()
		clear.append(Rect2(
			prompt_rect.get_center().x - ink * 0.5,
			prompt_rect.position.y, ink, prompt_rect.size.y))
		clear.append((title.get_node("Ui/Screen/Version") as Control
			).get_global_rect())
		for door_name in ["SettingsButton", "ShrineButton", "LadderButton",
				"ChronicleButton", "StoreButton"]:
			var door: Button = title.get_node(
				"Ui/Screen/" + door_name) as Button
			if door.is_visible_in_tree():
				clear.append(door.get_global_rect())
	elif forecourt.visible:
		clear.append((gate.get_node("Content/StatusCard") as Control
			).get_global_rect())
		clear.append((gate.get_node("Content/OfflineBadge") as Control
			).get_global_rect())
	for index in forecourt.actor_count():
		var rect: Rect2 = forecourt.paint_global_rect(index)
		_expect_true(viewport.encloses(rect.grow(-0.5)),
			"%s: hero %d inside %s" % [tag, index, rect])
		for zone in clear:
			_expect_true(not rect.grow(-1.0).intersects(zone.grow(-1.0)),
				"%s: hero %d clears %s" % [tag, index, zone])


func _expect_true(value: bool, message: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("  FAIL ", message)
