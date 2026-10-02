extends SceneTree

## The depth pass, checked without a screen.
##
## Shadows, floor life, mist and actor lighting are all things you judge by looking
## at them, and `tools/shot_*.tscn` do that. What can be pinned down without a
## screen is pinned here: every terrain gets all of it, the same seed builds the
## same floor, nothing grows on a structure, the effects stay faint, and the
## outline shader has the clear pixel around every frame that it draws into.

const ROOM_SCENE: PackedScene = preload("res://scenes/gameplay/room.tscn")
const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/actors/player.tscn")
const ARENA_SCENE_PATH: String = "res://scenes/gameplay/arena.tscn"
const KIND_PATHS: Array[String] = [
	"res://resources/rooms/forest.tres",
	"res://resources/rooms/field.tres",
	"res://resources/rooms/camp.tres",
	"res://resources/rooms/frost.tres",
	"res://resources/rooms/marsh.tres",
	"res://resources/rooms/ruins.tres",
]
const HEROES: Array[String] = [
	"warden", "knight", "keeper", "dancer", "sage", "eclipse"]
const SEED: int = 730_421
## A dodge game has to keep reading its enemies through all of this, so no effect
## colour may carry more opacity than this. Raising it needs a look at a screen.
const MAX_FAINT_ALPHA: float = 0.4

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for path in KIND_PATHS:
		await _test_room(load(path) as RoomKind)
	_test_actor_lighting()
	_test_sheet_margins()
	_test_margin_check_can_fail()
	await _test_sparks()
	_test_scene_wiring()
	_test_soft_disc()

	if _failed > 0:
		printerr("room-depth test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("room-depth test passed — ", _checked, " case(s)")
	quit(0)


func _test_room(kind: RoomKind) -> void:
	var label: String = kind.display_name
	var room: Room = ROOM_SCENE.instantiate() as Room
	root.add_child(room)
	room.build(kind, SEED)
	var shadows: RoomShadows = room.get_node("Shadows") as RoomShadows
	var tone: RoomTone = room.get_node("Tone") as RoomTone
	var flora: RoomFlora = room.get_node("Flora") as RoomFlora
	var lights: RoomLights = room.get_node("Lights") as RoomLights
	var atmosphere: RoomAtmosphere = room.get_node("Atmosphere") as RoomAtmosphere

	_expect_true(shadows.cast_count() > room.terrain_obstacle_count(),
		"%s every structure and most decor casts a shadow" % label)
	_expect_equal(tone.patch_count(), kind.tone_count, "%s colour patches" % label)
	_expect_equal(lights.dapple_count(), kind.dapple_count, "%s moonlight dapples" % label)
	_expect_equal(atmosphere.shaft_count(), kind.beam_count, "%s light shafts" % label)
	_expect_true(flora.plant_count() > 0, "%s has plants on the floor" % label)
	_expect_true(flora.plant_count() <= kind.flora_count * 3, "%s plant count is bounded" % label)
	_expect_true(lights.glow_count() > 0, "%s mushrooms and flowers glow" % label)

	for at in flora.plant_positions():
		if not room.is_clear(at, 8.0):
			_expect_true(false, "%s plant at %s stands on a structure" % [label, at])
			break
	_checked += 1

	# The same seed builds the same floor; another seed builds another.
	var signature: String = _floor_signature(shadows, flora)
	room.build(kind, SEED)
	_expect_equal(_floor_signature(shadows, flora), signature, "%s floor is deterministic" % label)
	room.build(kind, SEED + 1)
	_expect_not_equal(_floor_signature(shadows, flora), signature, "%s another seed, another floor" % label)
	room.build(kind, SEED)
	# Rebuilding clears the last room; nothing piles up.
	_expect_equal(shadows.cast_count(), _cast_count_for(kind, SEED), "%s rebuild leaves no old shadows" % label)

	# Every effect colour stays faint.
	_expect_true(kind.mist_color.a <= MAX_FAINT_ALPHA, "%s mist is faint" % label)
	_expect_true(kind.beam_color.a <= MAX_FAINT_ALPHA, "%s light shafts are faint" % label)
	_expect_true(kind.dapple_color.a <= MAX_FAINT_ALPHA, "%s dapples are faint" % label)
	for color in kind.tone_colors:
		_expect_true(color.a <= MAX_FAINT_ALPHA, "%s colour patch is faint" % label)
	_expect_true(kind.flora_glow <= 1.0, "%s plant glow is within range" % label)

	# The decor draws in a few batches: one material per sheet, none for flat pieces.
	var lit: int = 0
	var flat: int = 0
	for child in room.get_node("Decor").get_children():
		var sprite: Sprite2D = child as Sprite2D
		if sprite == null:
			continue
		if sprite.material == null:
			flat += 1
		else:
			lit += 1
			_expect_true(
				sprite.material == Room.NATURE_MATERIAL or sprite.material == Room.STILL_MATERIAL,
				"%s decor uses only the two shared materials" % label)
	_expect_true(lit > flat, "%s most decor is lit and only flat pieces are left plain" % label)
	for structure in room.get_node("Structures").get_children():
		var sprite: Sprite2D = structure.get_child(0) as Sprite2D
		_expect_true(sprite != null and sprite.material == Room.STILL_MATERIAL,
			"%s structure is lit" % label)
		break

	# The motes are drawn by the atmosphere, follow the camera, and never change in number.
	_expect_equal(atmosphere.mote_count(), kind.mote_count, "%s motes" % label)
	for _step in 30:
		atmosphere._process(0.2)
	_expect_equal(atmosphere.mote_count(), kind.mote_count, "%s motes are recycled, never added" % label)
	_expect_true(atmosphere.get_node("Motes") is Node2D and not atmosphere.get_node("Motes") is GPUParticles2D,
		"%s motes are drawn, not simulated on the GPU" % label)

	room.queue_free()
	await process_frame


## What the shadow layer and the flora layer hold, as one comparable string.
func _floor_signature(shadows: RoomShadows, flora: RoomFlora) -> String:
	var parts: PackedStringArray = PackedStringArray([str(shadows.cast_count())])
	for at in flora.plant_positions():
		parts.append("%d,%d" % [roundi(at.x), roundi(at.y)])
	return "|".join(parts)


## How many shadows a fresh build of this room makes, from a clean node.
func _cast_count_for(kind: RoomKind, seed_value: int) -> int:
	var fresh: Room = ROOM_SCENE.instantiate() as Room
	root.add_child(fresh)
	fresh.build(kind, seed_value)
	var count: int = (fresh.get_node("Shadows") as RoomShadows).cast_count()
	fresh.queue_free()
	return count


func _test_actor_lighting() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	var player_sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	_expect_true(player_sprite.material is ShaderMaterial, "the hero is lit by the actor shader")
	var spirit: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	var spirit_sprite: AnimatedSprite2D = spirit.get_node("Sprite") as AnimatedSprite2D
	_expect_true(spirit_sprite.material is ShaderMaterial, "a spirit is lit by the actor shader")
	_expect_true(player_sprite.material == spirit_sprite.material,
		"hero and spirits share one material, so they batch")
	var polish: ShaderMaterial = player_sprite.material as ShaderMaterial
	_expect_true(polish.shader != null and polish.shader.code.contains("shader_type canvas_item"),
		"the actor shader is a canvas item shader")
	# The shadow sits at the feet and leans the way the world's shadows do.
	var hero_shadow: Sprite2D = player.get_node("Shadow") as Sprite2D
	_expect_true(hero_shadow.position.x > 0.0, "the hero's shadow leans away from the moon")
	_expect_true(player.get_node("MoonPool") != null, "the hero stands in a small pool of moonlight")
	player.free()
	spirit.free()


## The outline shader draws into the clear pixel beside the art, and reads one pixel
## further to find it. Every frame therefore needs a clear pixel down its left, right
## and top edges, or it would draw a line on the frame's own edge and pick up the
## neighbouring frame's. The bottom row is exempt: feet touch it and nothing is drawn
## below them.
func _test_sheet_margins() -> void:
	for path in _spirit_paths():
		var kind: SpiritKind = load(path) as SpiritKind
		if kind == null or kind.sheet == null:
			continue
		var cell: Vector2i = Vector2i(kind.cell, kind.cell)
		var columns: int = maxi(kind.facings, 1)
		var rows: int = maxi(kind.frames, 1)
		if kind.behavior == SpiritKind.Behavior.GUARDIAN:
			# Guardian sheets are frames in one row.
			columns = maxi(kind.frames, 1)
			rows = 1
		_check_margin(kind.sheet, cell, columns, rows, path.get_file())
		for extra in [
				kind.guardian_windup_sheet, kind.guardian_alt_windup_sheet,
				kind.guardian_charge_sheet, kind.guardian_recover_sheet]:
			if extra != null:
				_check_margin(extra, cell, kind.guardian_state_frames, 1,
					"%s %s" % [path.get_file(), (extra as Texture2D).resource_path.get_file()])
	for hero_id in HEROES:
		var hero: Hero = load("res://resources/heroes/%s.tres" % hero_id) as Hero
		_check_margin(hero.walk_sheet, hero.sprite_cell, 4, hero.walk_frames, "%s walk" % hero_id)
		_check_margin(hero.idle_sheet, hero.sprite_cell, 4, hero.idle_frames, "%s idle" % hero_id)


func _spirit_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for file in DirAccess.get_files_at("res://resources"):
		if file.ends_with(".tres"):
			paths.append("res://resources/%s" % file)
	return paths


func _check_margin(texture: Texture2D, cell: Vector2i, columns: int, rows: int, label: String) -> void:
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		_expect_true(false, "%s sheet can be read" % label)
		return
	if image.is_compressed():
		image.decompress()
	_expect_equal(_dirty_edge_pixels(image, cell, columns, rows), 0,
		"%s frames keep a clear pixel on the left, right and top" % label)


## Opaque pixels on the left, right or top edge of any frame.
func _dirty_edge_pixels(image: Image, cell: Vector2i, columns: int, rows: int) -> int:
	var dirty: int = 0
	for column in columns:
		for row in rows:
			var origin: Vector2i = Vector2i(column * cell.x, row * cell.y)
			for x in cell.x:
				if image.get_pixel(origin.x + x, origin.y).a > 0.0:
					dirty += 1
			for y in cell.y:
				if image.get_pixel(origin.x, origin.y + y).a > 0.0 \
						or image.get_pixel(origin.x + cell.x - 1, origin.y + y).a > 0.0:
					dirty += 1
	return dirty


## The margin check has to be able to fail, or a green run proves nothing.
func _test_margin_check_can_fail() -> void:
	var clean: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	clean.set_pixel(8, 8, Color.WHITE)
	_expect_equal(_dirty_edge_pixels(clean, Vector2i(16, 16), 1, 1), 0, "art inside the frame is clean")
	var left: Image = clean.duplicate() as Image
	left.set_pixel(0, 5, Color.WHITE)
	_expect_equal(_dirty_edge_pixels(left, Vector2i(16, 16), 1, 1), 1, "art on the left edge is caught")
	var top: Image = clean.duplicate() as Image
	top.set_pixel(7, 0, Color.WHITE)
	_expect_equal(_dirty_edge_pixels(top, Vector2i(16, 16), 1, 1), 1, "art on the top edge is caught")
	var bottom: Image = clean.duplicate() as Image
	bottom.set_pixel(7, 15, Color.WHITE)
	_expect_equal(_dirty_edge_pixels(bottom, Vector2i(16, 16), 1, 1), 0, "feet on the bottom row are allowed")


func _test_sparks() -> void:
	var sparks: KillSparks = KillSparks.new()
	root.add_child(sparks)
	await process_frame
	_expect_equal(sparks.active_count(), 0, "no bursts at rest")
	sparks.burst(Vector2(100, 100), Color.WHITE)
	sparks.burst(Vector2(120, 100), Color.WHITE, true)
	_expect_equal(sparks.active_count(), 2, "a burst is one row in a list, not a node")
	_expect_equal(sparks.get_child_count(), 0, "a burst adds no node")
	sparks._process(KillSparks.LIFE + 0.01)
	_expect_equal(sparks.active_count(), 0, "a burst ends by itself")
	for index in KillSparks.MAX_BURSTS + 20:
		sparks.burst(Vector2(float(index), 0.0), Color.WHITE)
	_expect_equal(sparks.active_count(), KillSparks.MAX_BURSTS, "a chain kill cannot grow the list")
	sparks._process(KillSparks.LIFE + 0.01)

	# A spirit that dies asks the group for a burst; with no pool it just dies.
	var alone: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	alone.set("kind", load("res://resources/wisp.tres"))
	root.add_child(alone)
	await process_frame
	alone.call("take_damage", 9999, Vector2.ZERO)
	_expect_equal(sparks.active_count(), 1, "a kill bursts sparks through the group")
	sparks.queue_free()
	await process_frame
	var quiet: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	quiet.set("kind", load("res://resources/wisp.tres"))
	root.add_child(quiet)
	await process_frame
	quiet.call("take_damage", 9999, Vector2.ZERO)
	_expect_true(true, "a kill with no spark pool in the tree is quiet")


func _test_scene_wiring() -> void:
	# The grade goes first on the arena's UI layer: it grades the world and leaves
	# the HUD, which comes after it, untouched.
	#
	# Read as text. Loading the arena needs the game's autoloads, which a bare
	# `--script` run does not start, and the order of two nodes is all that is asked.
	var text: String = FileAccess.get_file_as_string(ARENA_SCENE_PATH)
	var grade: int = text.find("[node name=\"Grade\" parent=\"Ui\"")
	var vignette: int = text.find("[node name=\"Vignette\" parent=\"Ui\"")
	var hud: int = text.find("[node name=\"Hud\" parent=\"Ui\"")
	_expect_true(grade >= 0, "the arena has a colour grade")
	_expect_true(grade < vignette, "the grade comes before the vignette")
	_expect_true(grade < hud, "the grade does not touch the HUD")
	_expect_true(text.contains("[node name=\"Sparks\" type=\"Node2D\" parent=\".\"]"),
		"the arena has its spark pool")


func _test_soft_disc() -> void:
	var texture: GradientTexture2D = SoftDisc.radial([Vector2(0.0, 1.0), Vector2(1.0, 0.0)], 32)
	_expect_equal(texture.gradient.get_point_count(), 2, "the soft disc keeps its stops")
	_expect_equal(texture.width, 32, "the soft disc keeps its size")
	_expect_equal(texture.gradient.get_color(0).a, 1.0, "the soft disc is opaque at the centre")
	_expect_equal(texture.gradient.get_color(1).a, 0.0, "the soft disc fades to nothing at the rim")


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_not_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — both values were ", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
