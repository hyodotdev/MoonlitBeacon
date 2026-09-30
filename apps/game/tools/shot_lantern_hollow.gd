extends Node

## Stage the Lantern Hollow story for screenshots, or validate the staging.
##
## The director renders on a real display; this sandbox cannot. So the harness
## has two modes. `validate` builds every stage headless and checks the nodes,
## texts and regions are what the shot needs — that is what runs here.
## `shot=<name>` captures PNGs under `builds/shots/story/` on a machine with
## a display.
##
##   pnpm godot:isolated --timeout 300 res://tools/shot_lantern_hollow.tscn -- validate
##   godot --path apps/game res://tools/shot_lantern_hollow.tscn -- shot=all tag=story locale=ko
##
## Shots: `opening`, `forest`, `field`, `camp`, `frost`, `marsh`, `ruins`
## (each dim then lit), `fork`, `chronicle`, `choice_beyond` (the cycle-8
## continue choice that resolves Nari's promise), `discovery_fork` and
## `discovery_guardian` (a new place discovery staying readable on the real
## fork and third-beacon paths), `ending_win`, `ending_escape`, `ending_lose`,
## or `all`. Lives in `tools/`, which the capture fingerprint excludes.
## Diagnostic desktop evidence, not store capture.
const ARENA: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const ROOM: PackedScene = preload("res://scenes/gameplay/room.tscn")
const PLAYER: PackedScene = preload("res://scenes/actors/player.tscn")
const BEACON: PackedScene = preload("res://scenes/objectives/beacon.tscn")
const GATE: PackedScene = preload("res://scenes/objectives/moon_gate.tscn")
const VIGNETTE: PackedScene = preload("res://scenes/ui/night_vignette.tscn")
const GRADE: PackedScene = preload("res://scenes/ui/night_grade.tscn")
const DIALOGUE: PackedScene = preload("res://scenes/ui/dialogue_scene.tscn")
const CHRONICLE_PANEL: PackedScene = preload("res://scenes/ui/chronicle_panel.tscn")
const RESULT_PANEL: PackedScene = preload("res://scenes/ui/result_panel.tscn")
const CHOICE_PANEL: PackedScene = preload("res://scenes/ui/run_choice_panel.tscn")
const KINDS: Array[String] = [
	"res://resources/rooms/forest.tres",
	"res://resources/rooms/field.tres",
	"res://resources/rooms/camp.tres",
	"res://resources/rooms/frost.tres",
	"res://resources/rooms/marsh.tres",
	"res://resources/rooms/ruins.tres",
]
const SEED: int = 20260930
const FRAME_AT: Vector2 = Vector2(950, 590)
const SHOT_DIR: String = "res://../../builds/shots/story"

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var named: Dictionary = {}
	for arg in args:
		if arg.contains("="):
			var parts: PackedStringArray = arg.split("=", true, 1)
			named[parts[0]] = parts[1]
		else:
			named[arg] = ""
	TranslationServer.set_locale(str(named.get("locale", "ko")))
	if named.has("validate"):
		await _validate()
		_finish_validate()
		return
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	await _capture(str(named.get("shot", "all")), str(named.get("tag", "")))
	get_tree().quit(0)


# --- validate -----------------------------------------------------------------
func _validate() -> void:
	_expect_chronicle()
	_expect_motif_sheet()
	_expect_window_sheet()
	_expect_keys()
	_expect_gate_label()
	_expect_result_states()
	_expect_choice_beyond()
	await _expect_beacon_ignite()
	await _expect_discovery_staging()


func _finish_validate() -> void:
	Chronicle.path = Chronicle.DEFAULT_PATH
	Chronicle.forget_cache()
	if _failed > 0:
		printerr("shot_lantern_hollow validate failed — ", _failed, "/", _checked)
		get_tree().quit(1)
		return
	print("shot_lantern_hollow validate passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _expect_chronicle() -> void:
	Chronicle.path = "user://shot_lantern_hollow.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Chronicle.path))
	Chronicle.forget_cache()
	Chronicle.mark("story_open")
	Chronicle.mark("story_1")
	Chronicle.mark("place_forest")
	Chronicle.mark("place_camp")
	Chronicle.mark("epitaph_win")
	_expect_equal(Chronicle.total_count(), 40, "forty entries to stage")
	_expect_true(Chronicle.has("place_forest"), "a staged place reads back")
	var panel: Control = CHRONICLE_PANEL.instantiate() as Control
	add_child(panel)
	panel.call("open")
	var list: VBoxContainer = panel.get_node("Frame/Margin/Rows/Scroll/List") as VBoxContainer
	_expect_equal(list.get_child_count(), 8 + Chronicle.total_count(),
		"the staged page lists every section and entry")
	panel.call("close")
	panel.queue_free()


func _expect_motif_sheet() -> void:
	var sheet: Texture2D = load("res://assets/custom/world/places/motifs.png")
	_expect_true(sheet != null, "the motif sheet loads")
	_expect_equal(sheet.get_size(), Vector2(192, 64), "the motif sheet is 192x64")
	for terrain in 6:
		var motif := PlaceMotif.new()
		add_child(motif)
		motif.show_terrain(terrain)
		var sprite: Sprite2D = motif.get_node("Motif") as Sprite2D
		_expect_equal(sprite.region_rect, Rect2(terrain * 32, 0, 32, 32),
			"terrain %d stages dim" % terrain)
		motif.set_lit(true)
		_expect_equal(sprite.region_rect, Rect2(terrain * 32, 32, 32, 32),
			"terrain %d stages lit" % terrain)
		motif.queue_free()


func _expect_window_sheet() -> void:
	var sheet: Texture2D = load("res://assets/custom/world/places/window.png")
	_expect_true(sheet != null, "the window sheet loads")
	_expect_equal(sheet.get_size(), Vector2(64, 32), "the window sheet is 64x32")


func _expect_keys() -> void:
	var keys: Array[String] = ["CHRONICLE_PLACES", "OBJECTIVE_ROAD",
		"OBJECTIVE_PLACES", "RESULT_ROAD", "STORY_OPEN_A", "STORY_OPEN_B",
		"STORY_EPITAPH_WIN", "STORY_EPITAPH_ESCAPE", "STORY_EPITAPH_LOSE",
		"CHRONICLE_ENDING_WIN", "CHRONICLE_ENDING_LOSE",
		"CYCLE_CHOICE_MAP_BEYOND_TITLE", "CYCLE_CHOICE_MAP_BEYOND_SUBTITLE",
		"CYCLE_CHOICE_MAP_BEYOND_LEFT_TITLE",
		"CYCLE_CHOICE_MAP_BEYOND_LEFT_DESC",
		"CYCLE_CHOICE_MAP_BEYOND_RIGHT_TITLE",
		"CYCLE_CHOICE_MAP_BEYOND_RIGHT_DESC"]
	for terrain in 6:
		keys.append(PlaceMemory.name_key(terrain))
		keys.append(PlaceMemory.clue_key(terrain))
		keys.append(PlaceMemory.memory_key(terrain))
	var current: String = TranslationServer.get_locale()
	for locale in ["en", "ko", "ja", "zh_CN", "zh_TW"]:
		TranslationServer.set_locale(locale)
		for key in keys:
			_expect_true(tr(key) != key, "%s resolves in %s" % [key, locale])
	TranslationServer.set_locale(current)


func _expect_gate_label() -> void:
	var gate: Node2D = GATE.instantiate() as Node2D
	add_child(gate)
	gate.set_destination("Moonlit Field", "Azure Fieldwing",
		Color(0.62, 0.8, 1.0, 1.0), tr(PlaceMemory.clue_key(1)))
	var label: Label = gate.get("_label") as Label
	_expect_true(label != null, "the staged gate carries a label")
	_expect_true(label.text.contains("Moonlit Field"), "the label names the place")
	_expect_true(label.text.contains("Azure Fieldwing"),
		"the label keeps the guardian")
	_expect_true(label.text.contains(tr(PlaceMemory.clue_key(1))),
		"the label hints the memory")
	gate.queue_free()


func _expect_result_states() -> void:
	var cases: Array = [
		[true, 8, 3, true, 32.0],
		[true, 1, 1, true, 0.0],
		[false, 0, 0, false, 0.0],
	]
	for entry in cases:
		var panel: Control = RESULT_PANEL.instantiate() as Control
		add_child(panel)
		var score := Score.new()
		score.cycles = int(entry[1])
		panel.show_result(bool(entry[0]), score, false, false, int(entry[2]))
		_expect_equal((panel.get_node("Road") as Label).visible, true,
			"cycles %d shows its road" % int(entry[1]))
		_expect_equal((panel.get_node("Window") as TextureRect).visible,
			bool(entry[3]), "cycles %d windows %s" % [
				int(entry[1]), "shows" if bool(entry[3]) else "hides"])
		if bool(entry[3]):
			var cell: AtlasTexture = (panel.get_node("Window") as TextureRect) \
				.texture as AtlasTexture
			_expect_equal(cell.region.position.x, float(entry[4]),
				"cycles %d stages the right cell" % int(entry[1]))
		panel.queue_free()


func _expect_choice_beyond() -> void:
	var panel: Control = CHOICE_PANEL.instantiate() as Control
	add_child(panel)
	panel.open_cycle(8)
	var title: Label = panel.get_node(
		"Center/Frame/Content/Rows/Title") as Label
	var subtitle: Label = panel.get_node(
		"Center/Frame/Content/Rows/Subtitle") as Label
	_expect_equal(title.text, tr("CYCLE_CHOICE_MAP_BEYOND_TITLE"),
		"the choice stages its resolution title")
	_expect_equal(subtitle.text, tr("CYCLE_CHOICE_MAP_BEYOND_SUBTITLE"),
		"the choice stages its kettle subtitle")
	for labeled in [
		[title, "title"], [subtitle, "subtitle"],
		[_choice_label(panel, "Left", "Title"), "left title"],
		[_choice_label(panel, "Left", "Description"), "left description"],
		[_choice_label(panel, "Right", "Title"), "right title"],
		[_choice_label(panel, "Right", "Description"), "right description"],
	]:
		var text: Label = labeled[0] as Label
		_expect_true(text.get_line_count() <= text.get_visible_line_count(),
			"the staged choice %s is not clipped" % str(labeled[1]))
	panel.close_without_choice()
	panel.queue_free()


func _choice_label(panel: Control, side: String, name: String) -> Label:
	return panel.get_node(
		"Center/Frame/Content/Rows/Choices/%s/Copy/Rows/%s" % [side, name]) as Label


## A staged terrain beacon really ignites: `set("lit")` would skip the lantern
## palette, the flare and the flicker the lit shot is meant to show.
func _expect_beacon_ignite() -> void:
	var staged: Dictionary = _stage_room(2)
	var beacon: Node2D = staged["beacon"] as Node2D
	_expect_false(bool(beacon.get("lit")), "the staged beacon starts out")
	beacon.ignite()
	await get_tree().create_timer(0.7, true).timeout
	_expect_true(bool(beacon.get("lit")), "ignite lights the staged beacon")
	var energy: float = float(
		(beacon.get("_light") as Node2D).get("energy") as float)
	_expect_true(energy > 0.0, "the flare settles with the lamp on")
	(staged["holder"] as Node).queue_free()
	await get_tree().process_frame


## The discovery shots stage through the real arena paths: the strip shows the
## memory while the fork gates and the guardian banner carry their own lines.
func _expect_discovery_staging() -> void:
	Chronicle.path = "user://shot_lantern_hollow.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Chronicle.path))
	Chronicle.forget_cache()
	var forked: Node2D = await _stage_arena()
	forked.set("_forks_enabled", true)
	forked.set("_run_seed", 4_242_001)
	forked.set("_cycle", 2)
	var start: int = Expedition.start_terrain(4_242_001, 2, 0)
	forked.set("_route", [start, -1, -1] as Array[int])
	forked.call("_change_cycle_world")
	await get_tree().process_frame
	forked.call("debug_light_next_beacon")
	await get_tree().process_frame
	_expect_equal(_strip_text(forked), tr(PlaceMemory.memory_key(start)),
		"the fork staging reads the discovery")
	_expect_equal((forked.get("_fork_options") as Array).size(), 2,
		"the fork staging opens two gates")
	forked.queue_free()
	await get_tree().process_frame

	var dueled: Node2D = await _stage_arena()
	for _step in 3:
		dueled.call("debug_light_next_beacon")
		await get_tree().create_timer(0.15, true).timeout
		if bool(dueled.get("_escape_active")):
			dueled.call("_on_gate_entered")
			while bool(dueled.get("_transitioning")) and is_instance_valid(dueled):
				await get_tree().process_frame
	await get_tree().process_frame
	var terrain: int = int(dueled.call("_terrain_at", 2))
	_expect_equal(_strip_text(dueled), tr(PlaceMemory.memory_key(terrain)),
		"the guardian staging reads the discovery")
	var banner: Label = (dueled.get("_hud") as Control).get("_banner") as Label
	_expect_true(banner.text.contains(str(dueled.get("_guardian_title"))),
		"the guardian staging banners its name")
	dueled.queue_free()
	await get_tree().process_frame
	get_tree().paused = false


func _stage_arena() -> Node2D:
	var arena: Node2D = ARENA.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.call("debug_shield")
	var seen: Dictionary = arena.get("_seen_spirits") as Dictionary
	for kind in ["drifter", "ember", "caster", "weaver", "stalker", "swarm", "wisp"]:
		seen["meet_" + kind] = true
	return arena


func _strip_text(arena: Node2D) -> String:
	var panel: Control = arena.get("_voice_panel") as Control
	var label: Label = panel.get_node_or_null("Box/Row/Text") as Label
	return label.text if label != null else ""


# --- capture ------------------------------------------------------------------
func _capture(want: String, tag: String) -> void:
	var out: String = ProjectSettings.globalize_path(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(out)
	var prefix: String = "%s_" % tag if not tag.is_empty() else ""
	if want in ["all", "opening"]:
		await _shot_opening(out, prefix)
	if want == "all":
		for terrain in 6:
			await _shot_terrain(out, prefix, terrain)
	elif want in PlaceMemory.TERRAIN_IDS:
		await _shot_terrain(out, prefix, PlaceMemory.TERRAIN_IDS.find(want))
	if want in ["all", "fork"]:
		await _shot_fork(out, prefix)
	if want in ["all", "discovery_fork"]:
		await _shot_discovery_fork(out, prefix)
	if want in ["all", "discovery_guardian"]:
		await _shot_discovery_guardian(out, prefix)
	if want in ["all", "choice_beyond"]:
		await _shot_choice_beyond(out, prefix)
	if want in ["all", "chronicle"]:
		await _shot_chronicle(out, prefix)
	if want in ["all", "ending_win", "ending_escape", "ending_lose"]:
		await _shot_endings(out, prefix, want)


func _stage_room(terrain: int) -> Dictionary:
	var holder := Node2D.new()
	add_child(holder)
	var room: Room = ROOM.instantiate() as Room
	holder.add_child(room)
	room.build(load(KINDS[terrain]) as RoomKind, SEED)
	var player: Node2D = PLAYER.instantiate() as Node2D
	holder.add_child(player)
	player.global_position = FRAME_AT
	var beacon: Node2D = BEACON.instantiate() as Node2D
	holder.add_child(beacon)
	beacon.global_position = FRAME_AT + Vector2(150, -40)
	# A bare beacon instantiates lit; the dim shot needs it out. The lit
	# shot then really ignites it instead of snapping the flag.
	beacon.reset()
	var motif := PlaceMotif.new()
	holder.add_child(motif)
	motif.show_terrain(terrain)
	motif.position = beacon.global_position + Vector2(58, 30)
	var camera := Camera2D.new()
	camera.position = FRAME_AT + Vector2(75, -20)
	holder.add_child(camera)
	camera.make_current()
	var ui := CanvasLayer.new()
	holder.add_child(ui)
	ui.add_child(GRADE.instantiate())
	ui.add_child(VIGNETTE.instantiate())
	return {"holder": holder, "beacon": beacon, "motif": motif}


func _snap(out: String, name: String, waits: int = 30) -> void:
	for _wait in waits:
		await RenderingServer.frame_post_draw
	var shot: Image = get_viewport().get_texture().get_image()
	shot.save_png("%s/%s.png" % [out, name])


func _shot_opening(out: String, prefix: String) -> void:
	var staged: Dictionary = _stage_room(0)
	var layer := CanvasLayer.new()
	add_child(layer)
	var scene: Control = DIALOGUE.instantiate() as Control
	layer.add_child(scene)
	var hero: Hero = load("res://resources/heroes/warden.tres") as Hero
	scene.play(hero, [tr("STORY_OPEN_A"), tr("STORY_OPEN_B")] as Array[String])
	# Complete the first line, step to the kettle message, complete it too.
	scene.call("_advance")
	scene.call("_advance")
	scene.call("_advance")
	await _snap(out, prefix + "opening")
	layer.queue_free()
	get_tree().paused = false
	(staged["holder"] as Node).queue_free()
	await get_tree().process_frame


func _shot_terrain(out: String, prefix: String, terrain: int) -> void:
	var staged: Dictionary = _stage_room(terrain)
	var beacon: Node2D = staged["beacon"] as Node2D
	var motif: PlaceMotif = staged["motif"] as PlaceMotif
	await _snap(out, "%s%s_dim" % [prefix, PlaceMemory.TERRAIN_IDS[terrain]])
	# Really ignite: the lit shot shows the lantern palette, the flare and
	# the flicker, after the 0.45 s flare has settled.
	beacon.ignite()
	motif.set_lit(true)
	await _snap(out, "%s%s_lit" % [prefix, PlaceMemory.TERRAIN_IDS[terrain]], 60)
	(staged["holder"] as Node).queue_free()
	await get_tree().process_frame


func _shot_fork(out: String, prefix: String) -> void:
	var staged: Dictionary = _stage_room(0)
	var holder: Node2D = staged["holder"] as Node2D
	var gate_a: Node2D = GATE.instantiate() as Node2D
	holder.add_child(gate_a)
	gate_a.position = FRAME_AT + Vector2(-160, -60)
	var gate_b: Node2D = GATE.instantiate() as Node2D
	holder.add_child(gate_b)
	gate_b.position = FRAME_AT + Vector2(160, 60)
	var camp_kind: SpiritKind = load("res://resources/guardian_camp.tres") as SpiritKind
	gate_a.set_destination(tr("WORLD_FIELD"), tr("OMEN_BLOOD_MOON"),
		Color(0.62, 0.8, 1.0, 1.0), tr(PlaceMemory.clue_key(1)))
	gate_b.set_destination(tr("WORLD_CAMP"), tr(camp_kind.display_name),
		Color(1.0, 0.72, 0.4, 1.0), tr(PlaceMemory.clue_key(2)))
	gate_a.open()
	gate_b.open()
	gate_a.modulate.a = 1.0
	gate_b.modulate.a = 1.0
	await _snap(out, prefix + "fork")
	holder.queue_free()
	await get_tree().process_frame


## The discovery stays readable while the first fork's gates stand open.
## Driven through the real arena path; stray strip lines are spent so the
## shot shows the memory, not a passing first sight.
func _shot_discovery_fork(out: String, prefix: String) -> void:
	var arena: Node2D = await _stage_arena()
	_spend(arena, "moonfire")
	_spend(arena, "swarm")
	arena.set("_forks_enabled", true)
	arena.set("_run_seed", 4_242_001)
	arena.set("_cycle", 2)
	var start: int = Expedition.start_terrain(4_242_001, 2, 0)
	arena.set("_route", [start, -1, -1] as Array[int])
	arena.call("_change_cycle_world")
	await get_tree().process_frame
	arena.call("debug_light_next_beacon")
	await get_tree().create_timer(0.6, true).timeout
	await _snap(out, prefix + "discovery_fork")
	arena.queue_free()
	get_tree().paused = false
	await get_tree().process_frame


## The discovery stays readable while the guardian banner names the duel.
## Driven through the real three-beacon path; snapped while the banner still
## holds and after its pop has settled.
func _shot_discovery_guardian(out: String, prefix: String) -> void:
	var arena: Node2D = await _stage_arena()
	_spend(arena, "call_dark")
	_spend(arena, "guardian_down")
	_spend(arena, "swarm")
	for _step in 3:
		arena.call("debug_light_next_beacon")
		await get_tree().create_timer(0.15, true).timeout
		if bool(arena.get("_escape_active")):
			arena.call("_on_gate_entered")
			while bool(arena.get("_transitioning")) and is_instance_valid(arena):
				await get_tree().process_frame
	await get_tree().create_timer(0.8, true).timeout
	await _snap(out, prefix + "discovery_guardian")
	arena.queue_free()
	get_tree().paused = false
	await get_tree().process_frame


func _spend(arena: Node2D, moment: String) -> void:
	var voice: HeroVoice = arena.get("_voice") as HeroVoice
	for _take in 6:
		if voice.take(moment).is_empty():
			return


func _shot_choice_beyond(out: String, prefix: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel: Control = CHOICE_PANEL.instantiate() as Control
	layer.add_child(panel)
	panel.open_cycle(8)
	await _snap(out, prefix + "choice_beyond")
	panel.close_without_choice()
	get_tree().paused = false
	layer.queue_free()
	await get_tree().process_frame


func _shot_chronicle(out: String, prefix: String) -> void:
	Chronicle.path = "user://shot_lantern_hollow.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Chronicle.path))
	Chronicle.forget_cache()
	for id in ["story_open", "story_1", "story_2", "place_forest", "place_field",
			"meet_wisp", "meet_guardian_forest", "epitaph_escape"]:
		Chronicle.mark(id)
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel: Control = CHRONICLE_PANEL.instantiate() as Control
	layer.add_child(panel)
	panel.call("open")
	await _snap(out, prefix + "chronicle")
	layer.queue_free()
	await get_tree().process_frame


func _shot_endings(out: String, prefix: String, want: String) -> void:
	var cases: Array = [
		["ending_win", true, 8, 4],
		["ending_escape", true, 3, 2],
		["ending_lose", false, 5, 1],
	]
	for entry in cases:
		if want != "all" and want != str(entry[0]):
			continue
		var layer := CanvasLayer.new()
		add_child(layer)
		var panel: Control = RESULT_PANEL.instantiate() as Control
		layer.add_child(panel)
		var score := Score.new()
		score.cycles = int(entry[2])
		score.beacons = 3
		score.survived = 640.0
		score.level = 12
		score.kills = 320
		score.shards = 40
		panel.show_result(bool(entry[1]), score, false, false, int(entry[3]))
		await get_tree().process_frame
		panel.call("_skip_reveal")
		await _snap(out, prefix + str(entry[0]))
		layer.queue_free()
		await get_tree().process_frame


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _expect_false(value: bool, label: String) -> void:
	_expect_equal(value, false, label)
