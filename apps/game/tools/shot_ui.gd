extends Node

## Photograph every UI screen at the real resolution (808x360), per locale.
##
## The UI pass touches seventeen scenes. None of that can be judged from a diff,
## and driving the real game to each screen (a paid shop, a defeat result, a
## first-run consent prompt) is slow and, on a phone, writes to the real save.
## So build each panel directly, open it with sample data, and photograph it.
##
## Each screen sits over a real forest room, because most panels dim what is
## behind them and a flat colour would hide how they read in play.
##
## Usage:
##     node scripts/godot.mjs --path apps/game res://tools/shot_ui.tscn
##     node scripts/godot.mjs --path apps/game res://tools/shot_ui.tscn -- ko,ja hud,relic
##     node scripts/godot.mjs --path apps/game res://tools/shot_ui.tscn -- ko "" 840x360
##     node scripts/godot.mjs --path apps/game res://tools/shot_ui.tscn -- en "" 808x360 validate
##
## The third argument overrides the capture size (responsive bounds are
## confirmed at 840x360 and 808x606). A fourth `validate` argument skips the
## capture and instead asserts, per screen, that the panel opens visible and
## error-free, that every World* decor node ignores the mouse, and that every
## custom-drawn control samples Linear. Validate runs headless; the director
## renders the real pictures on a display.
##
## Output lands in `builds/shots/ui/<locale>/<screen>.png`, so it is not
## committed. Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const ROOM: PackedScene = preload("res://scenes/gameplay/room.tscn")
const VIGNETTE: PackedScene = preload("res://scenes/ui/night_vignette.tscn")
const FOREST: String = "res://resources/rooms/forest.tres"
const WARDEN: String = "res://resources/heroes/warden.tres"
const KEEPER: String = "res://resources/heroes/keeper.tres"
const SEED: int = 20260929
const FRAME_AT: Vector2 = Vector2(950, 590)
const OUT: String = "res://../../builds/shots/ui"

const DEFAULT_LOCALES: Array[String] = ["en", "ko"]
## Seconds of real time to let tweens and fade-ins finish before the shot.
##
## Time, not frames: the title (a thousand-node forest) renders at a fraction of
## the frame rate of a small panel, so a frame count that suits one screen is a
## minute of waiting on another. Fades and count-ups are driven by time anyway.
const SETTLE_SECONDS: float = 0.9
## Screens that animate in for longer (the title fades its logo and menu up; the
## result counts numbers and then drops the rank stamp).
const SETTLE_OVERRIDES: Dictionary = {
	"title": 3.0,
	"result_lose": 3.6,
	"result_win": 3.6,
	"dialogue": 2.4,
}

## `id -> scene`. Every screen the player can reach.
const SCREENS: Dictionary = {
	"title": "res://scenes/menus/title_menu.tscn",
	"hud": "res://scenes/ui/hud.tscn",
	"pause": "res://scenes/ui/pause_panel.tscn",
	"settings": "res://scenes/ui/settings_panel.tscn",
	"relic": "res://scenes/ui/relic_panel.tscn",
	"choice_beacon": "res://scenes/ui/run_choice_panel.tscn",
	"choice_cycle": "res://scenes/ui/run_choice_panel.tscn",
	"result_lose": "res://scenes/ui/result_panel.tscn",
	"result_win": "res://scenes/ui/result_panel.tscn",
	"shrine": "res://scenes/ui/shrine_panel.tscn",
	"shop": "res://scenes/ui/iap_shop_panel.tscn",
	"ladder": "res://scenes/ui/ladder_panel.tscn",
	"credits": "res://scenes/ui/credits_panel.tscn",
	"quit": "res://scenes/ui/quit_panel.tscn",
	"consent": "res://scenes/ui/analytics_consent_panel.tscn",
	"hero": "res://scenes/ui/hero_preview_panel.tscn",
	"dialogue": "res://scenes/ui/dialogue_scene.tscn",
	"chronicle": "res://scenes/ui/chronicle_panel.tscn",
	"act_1": "res://scenes/ui/act_card.tscn",
	"act_2": "res://scenes/ui/act_card.tscn",
	"act_3": "res://scenes/ui/act_card.tscn",
	"act_4": "res://scenes/ui/act_card.tscn",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var win_size := Vector2i(808, 360)
	if args.size() >= 3 and not args[2].is_empty() and args[2] != "validate":
		var bits: PackedStringArray = args[2].split("x")
		win_size = Vector2i(int(bits[0]), int(bits[1]))
	get_window().size = win_size
	get_window().content_scale_size = win_size
	var validate: bool = "validate" in args

	var locales: Array[String] = DEFAULT_LOCALES.duplicate()
	var wanted: Array[String] = []
	if args.size() >= 1 and not args[0].is_empty():
		locales = []
		for locale in args[0].split(","):
			locales.append(locale)
	if args.size() >= 2 and not args[1].is_empty():
		for id in args[1].split(","):
			if id != "validate":
				wanted.append(id)

	var failures: int = 0
	for locale in locales:
		TranslationServer.set_locale(locale)
		var dir: String = ProjectSettings.globalize_path("%s/%s" % [OUT, locale])
		DirAccess.make_dir_recursive_absolute(dir)
		for id: String in SCREENS:
			if not wanted.is_empty() and not id in wanted:
				continue
			if validate:
				failures += await _validate(id, locale)
			else:
				await _shoot(id, "%s/%s.png" % [dir, id])
	if validate:
		print("validate: %d screens checked at %dx%d" % [
			SCREENS.size() if wanted.is_empty() else wanted.size(),
			win_size.x, win_size.y])
	get_tree().quit(1 if failures > 0 else 0)


## Open one screen like the capture does, then assert structure instead of
## photographing it. Returns 1 on failure, 0 when the screen is sound.
func _validate(id: String, locale: String) -> int:
	var world := Node2D.new()
	add_child(world)
	if id != "title":
		var room: Room = ROOM.instantiate() as Room
		world.add_child(room)
		room.build(load(FOREST) as RoomKind, SEED)
		var camera := Camera2D.new()
		camera.position = FRAME_AT
		world.add_child(camera)
		camera.make_current()
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	var node: Node = (load(SCREENS[id]) as PackedScene).instantiate()
	if id == "title":
		world.add_child(node)
	else:
		layer.add_child(node)
	await get_tree().process_frame
	_open(id, node)
	await get_tree().process_frame
	await get_tree().process_frame

	var problems: Array[String] = []
	if not is_instance_valid(node):
		problems.append("instance invalid")
	elif not (node as CanvasItem).visible:
		problems.append("not visible after open")
	if is_instance_valid(node):
		_walk_validate(node, problems)
		_check_role(id, node, problems)
	if problems.is_empty():
		print("ok %s [%s]" % [id, locale])
	else:
		printerr("FAIL %s [%s]: %s" % [id, locale, "; ".join(problems)])
	get_tree().paused = false
	world.queue_free()
	await get_tree().process_frame
	return 0 if problems.is_empty() else 1


func _walk_validate(node: Node, problems: Array[String]) -> void:
	for child in node.get_children():
		if child is TextureRect and str(child.name).begins_with("World"):
			if (child as TextureRect).mouse_filter != Control.MOUSE_FILTER_IGNORE:
				problems.append("%s eats taps" % child.get_path())
		if child is WorldButton or child is WorldFrame \
				or child is WorldPanel or child is WorldLabel:
			if (child as Control).texture_filter \
					!= CanvasItem.TEXTURE_FILTER_LINEAR:
				problems.append("%s not Linear" % child.get_path())
		if child is WorldButton or child is WorldLabel:
			# Faces exist exactly while drawn; hidden branches carry none.
			if not (child as Control).is_visible_in_tree():
				_walk_validate(child, problems)
				continue
			var face := (child as Control).get_child(0) as WorldFace
			if face == null or not face.show_behind_parent:
				problems.append("%s face not behind native paint"
					% child.get_path())
		_walk_validate(child, problems)


## Role-layout asserts: each major screen carries its own composition, not
## a generic dialog. Structural only (nodes, counts, copy hooks); the
## director judges the pixels from the real renders.
func _check_role(id: String, node: Node, problems: Array[String]) -> void:
	match id:
		"shrine":
			var rail: HBoxContainer = node.get_node_or_null(
				"Frame/Margin/Rows/HeroesScroll/Heroes") as HBoxContainer
			if rail == null or rail.get_child_count() != 6:
				problems.append("shrine rail is not six heroes")
		"hero":
			var body: TextureRect = node.get_node_or_null(
				"Frame/Margin/Rows/Content/BodyStage/Center/Body") as TextureRect
			if body == null or body.texture == null:
				problems.append("hero exhibition has no body")
			else:
				if body.get_node_or_null("Dais") == null:
					problems.append("hero exhibition has no dais")
				var weapon: TextureRect = body.get_node_or_null(
					"Weapon") as TextureRect
				if weapon == null or weapon.texture == null:
					problems.append("hero exhibition has no weapon")
		"chronicle":
			var index: VBoxContainer = node.get_node_or_null(
				"Frame/Margin/Rows/Book/IndexScroll/IndexList") as VBoxContainer
			var page: Label = node.get_node_or_null(
				"Frame/Margin/Rows/Book/Page/PageMargin/PageRows/PageTitle") as Label
			if index == null or index.get_child_count() == 0:
				problems.append("chronicle index is empty")
			if page == null or page.text.is_empty():
				problems.append("chronicle page shows no memory")
		"shop":
			var cards: HBoxContainer = node.get_node_or_null(
				"Frame/Margin/Rows/CardsScroll/Cards") as HBoxContainer
			var coins: HBoxContainer = node.get_node_or_null(
				"Frame/Margin/Rows/CoinsScroll/Coins") as HBoxContainer
			if cards == null or cards.get_child_count() == 0:
				problems.append("shop has no product cards")
			if coins == null or coins.get_child_count() == 0:
				problems.append("shop has no coin cards")
			if coins != null and coins.get_child_count() > 0:
				var mint: Control = (coins.get_child(0) as Control) \
					.get_node_or_null("Rows/Footer/Artwork") as Control
				if mint == null:
					problems.append("coin card has no mint mark")
		"result_lose", "result_win":
			var hero_body: TextureRect = node.get_node_or_null(
				"HeroBody") as TextureRect
			var hero_name: Label = node.get_node_or_null(
				"HeroName") as Label
			if hero_body == null or not hero_body.visible \
					or hero_body.texture == null:
				problems.append("journey record hides its hero")
			if hero_name == null or not hero_name.visible \
					or hero_name.text.is_empty():
				problems.append("journey record names no hero")


func _shoot(id: String, path: String) -> void:
	var world := Node2D.new()
	add_child(world)
	# The title has its own diorama; every other screen gets the real forest.
	if id != "title":
		var room: Room = ROOM.instantiate() as Room
		world.add_child(room)
		room.build(load(FOREST) as RoomKind, SEED)
		var camera := Camera2D.new()
		camera.position = FRAME_AT
		world.add_child(camera)
		camera.make_current()
		var backdrop := CanvasLayer.new()
		world.add_child(backdrop)
		backdrop.add_child(VIGNETTE.instantiate())

	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	var node: Node = (load(SCREENS[id]) as PackedScene).instantiate()
	# The title owns a CanvasLayer of its own (layer 2) under its forest. Nest it
	# inside layer 10 and the forest is drawn over its own menu.
	if id == "title":
		world.add_child(node)
	else:
		layer.add_child(node)
	# `_ready` has run once the node is in the tree; open on the next frame so
	# panels that connect signals or build children in `_ready` are complete.
	await get_tree().process_frame
	_open(id, node)

	await get_tree().create_timer(float(SETTLE_OVERRIDES.get(id, SETTLE_SECONDS)), true).timeout
	for _wait in 3:
		await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(path)

	get_tree().paused = false
	world.queue_free()
	await get_tree().process_frame


## Put one screen into the state a player would actually see it in.
func _open(id: String, node: Node) -> void:
	match id:
		"hud":
			_fill_hud(node)
		"pause":
			node.call("set_available", true)
			# The pause button lives inside the panel; the panel itself is what
			# a paused player sees.
			node.call("set_overlay_visible", true)
		"settings", "shrine", "shop", "credits", "quit":
			node.call("open")
		"consent":
			# `open()` refuses to show without a shipping analytics config, which
			# a dev checkout does not have. Force it up so the styling can be seen.
			node.call("open")
			node.call("_refresh_copy")
			node.set("visible", true)
			node.set("modulate", Color.WHITE)
		"relic":
			node.call("open")
		"choice_beacon":
			node.call("open_beacon", null, 1, true)
		"choice_cycle":
			node.call("open_cycle", 3)
		"result_lose":
			node.call("show_result", false, _sample_score(2), true, true,
				-1, false, KEEPER)
		"result_win":
			node.call("show_result", true, _sample_score(9), true, false,
				3, false, KEEPER)
		"ladder":
			node.call("view")
		"hero":
			node.call("open_hero", load(KEEPER) as Hero, KEEPER)
		"dialogue":
			var lines: Array[String] = [tr("STORY_CYCLE_2_A")]
			node.call("play", load(WARDEN) as Hero, lines)
		"chronicle":
			_stage_chronicle()
			node.call("open")
		"act_1", "act_2", "act_3", "act_4":
			var cycle: int = [1, 3, 6, 9][int(id.substr(4)) - 1]
			node.call("play", Acts.of_cycle(cycle))


## A half-read chronicle: enough found to show both a lit row and a blank one.
## Written to a scratch file so the shot never touches a real save.
func _stage_chronicle() -> void:
	Chronicle.path = "user://shot_chronicle.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Chronicle.path))
	Chronicle.forget_cache()
	for id in ["story_open", "story_1", "story_2", "story_3", "meet_drifter",
			"meet_swarm", "meet_guardian_forest", "epitaph_lose"]:
		Chronicle.mark(id)


func _sample_score(cycles: int) -> Score:
	var score := Score.new()
	score.cycles = cycles
	score.beacons = 2
	score.survived = 191.0
	score.level = 20
	return score


## A believable mid-run state: hurt, mid-cycle, carrying a build.
func _fill_hud(hud: Node) -> void:
	hud.call("set_max_health", 6)
	hud.call("set_health", 4)
	hud.call("set_beacons", 2, 3)
	hud.call("set_level", 20)
	hud.call("set_kills", 37)
	hud.call("set_survived", 184.0)
	hud.call("set_world", "WORLD_CAMP", "TIME_NIGHT")
	hud.call("set_moonfire", 0.6, false, false)
	hud.call("set_evolution", Relic.Family.FULL_MOON, 3, 0, 6)
	hud.call("set_missile_power", 6, 8, 1, 2, false)
	# A build with five kinds, so the strip shows its cap and the `+N` overflow.
	var taken: Array = []
	for entry: Array in [["twin_arrow", 5], ["quick_arrow", 4], ["moon_ring", 2],
			["long_blade", 1], ["shadow_veil", 1]]:
		var relic: Relic = load("res://resources/relics/%s.tres" % entry[0]) as Relic
		for _i in int(entry[1]):
			taken.append(relic)
	hud.call("set_relics", taken)
	# A guardian fight in progress: the boss bar, the centre banner, a combo.
	hud.call("set_boss", true, 0.62, "Thornwood Pursuer", Color(0.72, 0.92, 0.55, 1))
	hud.call("announce", "Guardian · dodge the charge", Color(1, 0.84, 0.42, 1), 30.0)
	hud.call("set_combo", 12, 2)
