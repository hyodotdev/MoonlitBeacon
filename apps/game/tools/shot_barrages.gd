extends Node

## Photograph live bullet patterns on real floors, at the game's own zoom.
##
## Each guardian is staged mid-chase on its own place with its aura and stream pre-rolled a few
## seconds through the real emitters, so the picture shows what a player weaves through; a busy
## zone and a caster's fan are staged the same way through the real spirit code.
##
##     node scripts/godot.mjs --path apps/game res://tools/shot_barrages.tscn -- tag 6
##
## Windowed, in the foreground: headless cannot draw. The second argument is the cycle to stage
## (default 6). With a third argument `validate` it stages everything headless, prints the bullet
## counts and quits without saving, so the staging itself is checked without a display.
## Output: `builds/shots/barrages/<tag>_<name>.png`. Lives in `tools/`, which
## `_runtime_fingerprint()` excludes.

const ROOM: PackedScene = preload("res://scenes/gameplay/room.tscn")
const PLAYER: PackedScene = preload("res://scenes/actors/player.tscn")
const SPIRIT: PackedScene = preload("res://scenes/actors/spirit.tscn")
const VIGNETTE: PackedScene = preload("res://scenes/ui/night_vignette.tscn")
const GRADE: PackedScene = preload("res://scenes/ui/night_grade.tscn")
const OUT: String = "res://../../builds/shots/barrages"
const CENTRE: Vector2 = Vector2(950, 590)
const STEP: float = 1.0 / 60.0

## name, room, guardian ("" for the staged zone and fan scenes).
const CASES: Array = [
	["forest_stream", "res://resources/rooms/forest.tres", "res://resources/guardian_forest.tres"],
	["field_stream", "res://resources/rooms/field.tres", "res://resources/guardian_field.tres"],
	["camp_stream", "res://resources/rooms/camp.tres", "res://resources/guardian_camp.tres"],
	["frost_stream", "res://resources/rooms/frost.tres", "res://resources/guardian_frost.tres"],
	["marsh_stream", "res://resources/rooms/marsh.tres", "res://resources/guardian_marsh.tres"],
	["ruins_stream", "res://resources/rooms/ruins.tres", "res://resources/guardian_ruins.tres"],
	["busy_zone", "res://resources/rooms/forest.tres", ""],
	["caster_fan", "res://resources/rooms/camp.tres", ""],
]

var _camera: Camera2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() >= 1 and not args[0].is_empty() else "shot"
	var cycle: int = int(args[1]) if args.size() >= 2 else 6
	var validate: bool = args.size() >= 3 and args[2] == "validate"
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)

	var holder := Node2D.new()
	holder.y_sort_enabled = true
	add_child(holder)
	_camera = Camera2D.new()
	holder.add_child(_camera)
	_camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(GRADE.instantiate())
	layer.add_child(VIGNETTE.instantiate())
	var player: Node2D = PLAYER.instantiate() as Node2D
	holder.add_child(player)
	player.global_position = CENTRE + Vector2(120, 22)
	(player.get_node("Cam") as Camera2D).enabled = false
	player.call("set_bounds", Room.PLAY)
	player.call("apply_hero_visual", load("res://resources/heroes/warden.tres"))
	_camera.make_current()
	var field: BulletField = BulletField.new()
	holder.add_child(field)

	for case in CASES:
		await _photograph(holder, player, field, out, tag, cycle, validate, case)
	get_tree().quit(0)


func _photograph(holder: Node2D, player: Node2D, field: BulletField, out: String, tag: String,
		cycle: int, validate: bool, case: Array) -> void:
	var room: Room = ROOM.instantiate() as Room
	holder.add_child(room)
	room.build(load(case[1]) as RoomKind, 20260930)
	field.set_terrain_room(room)
	field.clear()
	player.global_position = CENTRE + Vector2(120, 22)
	var actors: Array[Node2D] = []
	if str(case[2]).is_empty():
		if str(case[0]) == "busy_zone":
			actors = _stage_zone(holder, player, cycle)
		else:
			actors = _stage_fan(holder, player, cycle)
		_roll(field, actors, 6.0)
	else:
		var spirit: Node2D = _stage_guardian(holder, player, cycle, str(case[2]))
		actors.append(spirit)
		_roll(field, actors, 4.0)
	# A caster's fan lives a few seconds: loose it last, then let it fly half a second, so the picture
	# catches it spread out. Guardian scenes have no casters and this is a no-op for them.
	for actor in actors:
		var kind: SpiritKind = actor.get("kind")
		if kind != null and kind.behavior == SpiritKind.Behavior.SHOOT:
			var direction: Vector2 = (player.global_position - actor.global_position).normalized()
			actor.call("_fire_caster_shot", direction)
	for step in 30:
		field._physics_process(STEP)
	_camera.position = CENTRE + Vector2(50, 0)
	_camera.zoom = Vector2(Room.WORLD_CAMERA_ZOOM, Room.WORLD_CAMERA_ZOOM)
	if validate:
		print("barrages validate: %s has %d bullets in the air" % [case[0], field.count()])
	else:
		await _settle(0.5)
		_save("%s/%s_%s.png" % [out, tag, case[0]])
	for actor in actors:
		actor.queue_free()
	room.queue_free()
	if not validate:
		await get_tree().process_frame


func _stage_guardian(holder: Node2D, player: Node2D, cycle: int, path: String) -> Node2D:
	var spirit: Node2D = SPIRIT.instantiate() as Node2D
	spirit.set("kind", load(path) as SpiritKind)
	spirit.set("guardian_cycle", cycle)
	spirit.process_mode = Node.PROCESS_MODE_DISABLED
	holder.add_child(spirit)
	spirit.global_position = CENTRE
	spirit.set("_target", player)
	spirit.set("_materialized", true)
	for emitter in spirit.get("_barrages") + spirit.get("_streams"):
		emitter.restart(0.0)
	return spirit


func _stage_zone(holder: Node2D, player: Node2D, cycle: int) -> Array[Node2D]:
	var placed: Array[Node2D] = []
	var kinds: Array[String] = [
		"res://resources/caster.tres", "res://resources/caster.tres", "res://resources/caster.tres",
		"res://resources/weaver.tres", "res://resources/weaver.tres",
		"res://resources/weaver.tres", "res://resources/weaver.tres",
		"res://resources/wisp.tres", "res://resources/wisp.tres", "res://resources/wisp.tres",
	]
	var ring: int = 0
	for path in kinds:
		var spirit: Node2D = SPIRIT.instantiate() as Node2D
		spirit.set("kind", load(path) as SpiritKind)
		spirit.set("mob_cycle", cycle)
		spirit.process_mode = Node.PROCESS_MODE_DISABLED
		holder.add_child(spirit)
		var angle: float = TAU * float(ring) / float(kinds.size())
		ring += 1
		spirit.global_position = CENTRE + Vector2.RIGHT.rotated(angle) * 150.0
		spirit.set("_target", player)
		spirit.set("_materialized", true)
		spirit.set("_shooting_age", 99.0)
		# The picture wants shooters: only some of a kind throw, so ask until this one does.
		for attempt in 200:
			if not (spirit.get("_barrages") as Array).is_empty():
				break
			spirit.call("_build_barrages")
		for emitter in spirit.get("_barrages"):
			emitter.restart(0.0)
		placed.append(spirit)
	# One caster shows its aim; the fans fly just before the picture (see `_photograph`), so they are
	# mid-flight and not spent.
	for spirit in placed:
		var kind: SpiritKind = spirit.get("kind")
		if kind.behavior == SpiritKind.Behavior.SHOOT:
			var direction: Vector2 = (player.global_position - spirit.global_position).normalized()
			spirit.call("_set_telegraph", 1, direction, 0.9)
			break
	return placed


func _stage_fan(holder: Node2D, player: Node2D, cycle: int) -> Array[Node2D]:
	var spirit: Node2D = SPIRIT.instantiate() as Node2D
	spirit.set("kind", load("res://resources/caster.tres") as SpiritKind)
	spirit.set("mob_cycle", maxi(cycle, 3))
	spirit.process_mode = Node.PROCESS_MODE_DISABLED
	holder.add_child(spirit)
	spirit.global_position = CENTRE + Vector2(-60, -30)
	spirit.set("_target", player)
	spirit.set("_materialized", true)
	var direction: Vector2 = (player.global_position - spirit.global_position).normalized()
	spirit.call("_set_telegraph", 1, direction, 0.9)
	return [spirit]


## Run the real shooting and flight code forward without drawing, so the staged patterns are flight, not muzzle.
func _roll(field: BulletField, actors: Array[Node2D], seconds: float) -> void:
	var steps: int = int(seconds / STEP)
	for step in steps:
		for actor in actors:
			actor.call("_tick_barrages", STEP)
		field._physics_process(STEP)


func _settle(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
