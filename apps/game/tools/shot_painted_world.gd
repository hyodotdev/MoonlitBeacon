extends Node

## Review harness for the painted world: every production sheet at source
## resolution plus staged game-camera shots of every hero, species, guardian
## state and terrain.
##
##     pnpm godot:isolated --windowed res://tools/shot_painted_world.tscn -- tag=painted
##     pnpm godot:isolated --timeout 900 res://tools/shot_painted_world.tscn -- validate=1
##
## Arguments (`-- key=value`): tag validate mode. `mode=contact` captures each
## of the 89 runtime sheets 1:1; `mode=stage` frames actors and rooms at the
## 808×360 game camera; the default runs both. Output lands under
## `builds/shots/painted/`, so it is not committed.
##
## Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const PLAYER: PackedScene = preload("res://scenes/actors/player.tscn")
const SPIRIT: PackedScene = preload("res://scenes/actors/spirit.tscn")
const ROOM: PackedScene = preload("res://scenes/gameplay/room.tscn")
const VIGNETTE: PackedScene = preload("res://scenes/ui/night_vignette.tscn")
const GRADE: PackedScene = preload("res://scenes/ui/night_grade.tscn")

const HEROES: Array[String] = ["warden", "dancer", "keeper", "knight", "eclipse", "sage"]
const SPIRITS: Array[String] = [
	"drifter", "ember", "caster", "weaver", "stalker", "swarm", "wisp",
]
const GUARDIANS: Array[String] = [
	"forest", "field", "camp", "frost", "marsh", "ruins",
	"forest_thorn", "field_storm", "camp_siege", "frost_rime", "marsh_glow", "ruins_halo",
]
const TERRAINS: Array[String] = ["forest", "field", "camp", "frost", "marsh", "ruins"]
const DIRECTIONS: Array[String] = ["down", "up", "left", "right"]
const GUARDIAN_STATES: Array[String] = [
	"guardian_windup", "guardian_alt_windup", "guardian_charge", "guardian_recover",
]
const SEED: int = 20261002
const FRAME_AT: Vector2 = Vector2(950, 590)

var _tag: String = "painted"
var _validate_only: bool = false
var _mode: String = "both"
var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() < 2:
			continue
		match parts[0]:
			"tag":
				_tag = parts[1] if not parts[1].is_empty() else "painted"
			"validate":
				_validate_only = parts[1] == "1"
			"mode":
				_mode = parts[1]
	_run.call_deferred()


func _is_isolated() -> bool:
	return OS.has_environment("MOONLIT" + "_VAULT" + "_TEST" + "_ROOT")


func _run() -> void:
	_check_lists()
	if _validate_only:
		_report_validate()
		get_tree().quit(1 if _failed > 0 else 0)
		return
	var out: String = ProjectSettings.globalize_path("res://../../builds/shots/painted")
	DirAccess.make_dir_recursive_absolute(out)
	if _mode == "contact" or _mode == "both":
		await _capture_contact(out)
	if _mode == "stage" or _mode == "both":
		await _capture_stage(out)
	get_tree().quit(0)


## Every production sheet the game reads, no more and no fewer.
func _sheet_paths() -> Array[String]:
	var paths: Array[String] = []
	for hero_id in HEROES:
		for state in ["walk", "idle", "portrait"]:
			paths.append("res://assets/custom/actors/heroes/%s/%s.png" % [hero_id, state])
	for spirit_id in SPIRITS:
		paths.append("res://assets/custom/actors/spirits/%s.png" % spirit_id)
	for guardian_id in GUARDIANS:
		var kind: SpiritKind = load(
			"res://resources/guardian_%s.tres" % guardian_id) as SpiritKind
		if kind == null or kind.sheet == null:
			continue
		paths.append(kind.sheet.resource_path)
		for slot in [
			kind.guardian_windup_sheet,
			kind.guardian_alt_windup_sheet,
			kind.guardian_charge_sheet,
			kind.guardian_recover_sheet,
		]:
			if slot != null and slot.resource_path not in paths:
				paths.append(slot.resource_path)
	for terrain_id in TERRAINS:
		var kind: RoomKind = load(
			"res://resources/rooms/%s.tres" % terrain_id) as RoomKind
		if kind == null or kind.tileset == null:
			continue
		for sheet in [kind.tileset, kind.obstacle_tileset, kind.floor_texture]:
			if sheet != null and sheet.resource_path not in paths:
				paths.append(sheet.resource_path)
		if kind.prop_tileset != null \
				and kind.prop_tileset.resource_path not in paths:
			paths.append(kind.prop_tileset.resource_path)
	return paths


func _check_lists() -> void:
	_checked += 1
	var sheets: Array[String] = _sheet_paths()
	if sheets.size() != 89:
		_failed += 1
		printerr("  FAIL painted sheet count — expected=89 actual=", sheets.size())
	for path in sheets:
		_checked += 1
		if not ResourceLoader.exists(path):
			_failed += 1
			printerr("  FAIL missing sheet: ", path)
	for hero_id in HEROES:
		_checked += 1
		var hero: Hero = load("res://resources/heroes/%s.tres" % hero_id) as Hero
		if hero == null or hero.walk_sheet == null or hero.idle_sheet == null:
			_failed += 1
			printerr("  FAIL hero without sheets: ", hero_id)
	for spirit_id in SPIRITS:
		_checked += 1
		var kind: SpiritKind = load("res://resources/%s.tres" % spirit_id) as SpiritKind
		if kind == null or kind.sheet == null:
			_failed += 1
			printerr("  FAIL spirit without sheet: ", spirit_id)
	for terrain_id in TERRAINS:
		_checked += 1
		var kind: RoomKind = load("res://resources/rooms/%s.tres" % terrain_id) as RoomKind
		if kind == null or kind.tileset == null:
			_failed += 1
			printerr("  FAIL terrain without tileset: ", terrain_id)


func _report_validate() -> void:
	if _failed > 0:
		printerr("shot_painted_world validate failed — ", _failed, "/", _checked)
		return
	print("shot_painted_world validate: ", _checked, " case(s) staged")


func _capture_contact(out: String) -> void:
	for path in _sheet_paths():
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			continue
		var size: Vector2i = Vector2i(texture.get_size())
		get_window().size = size
		get_window().content_scale_size = size
		var holder := Node2D.new()
		add_child(holder)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.position = Vector2(size) * 0.5
		holder.add_child(sprite)
		var camera := Camera2D.new()
		camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		camera.position = Vector2(size) * 0.5
		holder.add_child(camera)
		camera.make_current()
		for _wait in 6:
			await RenderingServer.frame_post_draw
		var shot: Image = get_viewport().get_texture().get_image()
		var flat: String = path.replace("res://assets/custom/", "").replace("/", "_")
		shot.save_png("%s/%s_contact_%s" % [out, _tag, flat])
		holder.queue_free()
		await get_tree().process_frame


func _capture_stage(out: String) -> void:
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	for terrain_id in TERRAINS:
		await _capture_room(out, terrain_id)
	for hero_id in HEROES:
		await _capture_hero_strip(out, hero_id)
	for spirit_id in SPIRITS:
		await _capture_spirit_strip(out, spirit_id)
	for guardian_id in GUARDIANS:
		await _capture_guardian_states(out, guardian_id)


func _stage_floor(terrain_id: String) -> Node2D:
	var holder := Node2D.new()
	add_child(holder)
	var kind: RoomKind = load("res://resources/rooms/%s.tres" % terrain_id) as RoomKind
	var room: Room = ROOM.instantiate() as Room
	holder.add_child(room)
	room.build(kind, SEED)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	return holder


func _stage_camera(holder: Node2D, at: Vector2) -> void:
	var camera := Camera2D.new()
	# Physics interpolation is on project-wide: match its override up front
	# so staging a camera never warns. Production cameras are untouched.
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = at
	holder.add_child(camera)
	camera.make_current()
	var ui := CanvasLayer.new()
	holder.add_child(ui)
	ui.add_child(GRADE.instantiate())
	ui.add_child(VIGNETTE.instantiate())


func _settle_and_save(out: String, name: String, holder: Node) -> void:
	for _wait in 30:
		await RenderingServer.frame_post_draw
	var shot: Image = get_viewport().get_texture().get_image()
	shot.save_png("%s/%s_%s.png" % [out, _tag, name])
	holder.queue_free()
	await get_tree().process_frame


func _capture_room(out: String, terrain_id: String) -> void:
	var holder: Node2D = _stage_floor(terrain_id)
	var player: Player = PLAYER.instantiate() as Player
	player.process_mode = Node.PROCESS_MODE_DISABLED
	(player.get_node("Cam") as Camera2D).process_callback = \
		Camera2D.CAMERA2D_PROCESS_PHYSICS
	holder.add_child(player)
	player.global_position = FRAME_AT
	var hero: Hero = load(
		"res://resources/heroes/%s.tres"
			% HEROES[TERRAINS.find(terrain_id) % HEROES.size()]) as Hero
	player.apply_hero_visual(hero)
	_stage_camera(holder, FRAME_AT)
	await _settle_and_save(out, "stage_" + terrain_id, holder)


func _capture_hero_strip(out: String, hero_id: String) -> void:
	var holder: Node2D = _stage_floor("forest")
	var hero: Hero = load("res://resources/heroes/%s.tres" % hero_id) as Hero
	for direction_index in DIRECTIONS.size():
		var player: Player = PLAYER.instantiate() as Player
		player.process_mode = Node.PROCESS_MODE_DISABLED
		(player.get_node("Cam") as Camera2D).process_callback = \
			Camera2D.CAMERA2D_PROCESS_PHYSICS
		holder.add_child(player)
		player.global_position = FRAME_AT + Vector2((direction_index - 1.5) * 150.0, 0.0)
		player.apply_hero_visual(hero)
		var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
		sprite.play(StringName("walk_" + DIRECTIONS[direction_index]))
		sprite.frame = 0
	_stage_camera(holder, FRAME_AT)
	await _settle_and_save(out, "stage_hero_" + hero_id, holder)


func _capture_spirit_strip(out: String, spirit_id: String) -> void:
	var holder: Node2D = _stage_floor("forest")
	var kind: SpiritKind = load("res://resources/%s.tres" % spirit_id) as SpiritKind
	for direction_index in DIRECTIONS.size():
		var spirit: Node2D = SPIRIT.instantiate() as Node2D
		spirit.set("kind", kind)
		spirit.process_mode = Node.PROCESS_MODE_DISABLED
		holder.add_child(spirit)
		spirit.global_position = FRAME_AT + Vector2((direction_index - 1.5) * 150.0, 0.0)
		var sprite: AnimatedSprite2D = spirit.get_node("Sprite") as AnimatedSprite2D
		sprite.play(StringName("float_" + DIRECTIONS[direction_index]))
		sprite.frame = 0
	_stage_camera(holder, FRAME_AT)
	await _settle_and_save(out, "stage_spirit_" + spirit_id, holder)


func _capture_guardian_states(out: String, guardian_id: String) -> void:
	var holder: Node2D = _stage_floor("forest")
	var kind: SpiritKind = load(
		"res://resources/guardian_%s.tres" % guardian_id) as SpiritKind
	var animations: Array[String] = ["float_down"]
	animations.append_array(GUARDIAN_STATES)
	for state_index in animations.size():
		var spirit: Node2D = SPIRIT.instantiate() as Node2D
		spirit.set("kind", kind)
		spirit.process_mode = Node.PROCESS_MODE_DISABLED
		holder.add_child(spirit)
		spirit.global_position = FRAME_AT + Vector2((state_index - 2.0) * 130.0, 0.0)
		var sprite: AnimatedSprite2D = spirit.get_node("Sprite") as AnimatedSprite2D
		if sprite.sprite_frames.has_animation(StringName(animations[state_index])):
			sprite.play(StringName(animations[state_index]))
			sprite.frame = mini(1, sprite.sprite_frames.get_frame_count(
				StringName(animations[state_index])) - 1)
	_stage_camera(holder, FRAME_AT)
	await _settle_and_save(out, "stage_guardian_" + guardian_id, holder)
