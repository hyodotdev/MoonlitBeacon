extends Node

## Photograph every guardian telegraph on a real floor, at the game's own zoom and at 3x.
##
## Each guardian is staged in the middle of a room in the last step of a windup, with the player a
## short way off, so the shape and the fill can be judged the way a player sees them.
##
##     node scripts/godot.mjs --path apps/game res://tools/shot_telegraphs.tscn -- before
##     node scripts/godot.mjs --path apps/game res://tools/shot_telegraphs.tscn -- honest 1,4,8,14
##
## The second argument is the cycles to photograph (default 3): a warning must show the volley of its own
## cycle, and the picture at cycle 14 is the one that used to say less than the bolts did.
##
## Output: `builds/shots/telegraphs/<tag>_c<cycle>_<name>.png`. Lives in `tools/`, which
## `_runtime_fingerprint()` excludes.

const ROOM: PackedScene = preload("res://scenes/gameplay/room.tscn")
const PLAYER: PackedScene = preload("res://scenes/actors/player.tscn")
const SPIRIT: PackedScene = preload("res://scenes/actors/spirit.tscn")
const VIGNETTE: PackedScene = preload("res://scenes/ui/night_vignette.tscn")
const GRADE: PackedScene = preload("res://scenes/ui/night_grade.tscn")
const FOREST: String = "res://resources/rooms/forest.tres"
const OUT: String = "res://../../builds/shots/telegraphs"
const CENTRE: Vector2 = Vector2(950, 590)

## name, guardian resource, telegraph kind (0 none, 1 aim, 2 charge, 3 volley), guardian pattern, ratio, fan index,
## and optionally an echo (the repeat of a volley: 2 fan, 1 field, 0 forest ring; -1 only gives the guardian the mutation, so
## the repeat is drawn beside the volley while it winds up)
const CASES: Array = [
	["forest_charge", "res://resources/guardian_forest.tres", 2, 0, 0.75, 0],
	["forest_ring", "res://resources/guardian_forest.tres", 3, 1, 0.75, 0],
	["field_cross", "res://resources/guardian_field.tres", 3, 0, 0.75, 0],
	["field_radial", "res://resources/guardian_field.tres", 3, 1, 0.75, 0],
	["camp_fan", "res://resources/guardian_camp.tres", 3, 0, 0.75, 0],
	["camp_spear", "res://resources/guardian_camp.tres", 3, 0, 0.75, 1],
	["gale_fan", "res://resources/guardian_frost.tres", 3, 0, 0.75, 0],
	["marsh_ring", "res://resources/guardian_marsh.tres", 3, 1, 0.75, 0],
	["ruins_ring", "res://resources/guardian_ruins.tres", 3, 1, 0.75, 0],
	["field_aim", "res://resources/guardian_field.tres", 1, 0, 0.75, 0],
	["camp_preview", "res://resources/guardian_camp.tres", 3, 0, 0.75, 1, -1],
	["field_preview", "res://resources/guardian_field.tres", 3, 1, 0.75, 0, -1],
	["camp_echo", "res://resources/guardian_camp.tres", 0, 0, 0.0, 0, 2],
	["field_echo", "res://resources/guardian_field.tres", 0, 1, 0.0, 0, 1],
]

var _camera: Camera2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() >= 1 and not args[0].is_empty() else "shot"
	var cycles: Array[int] = [3]
	if args.size() >= 2:
		cycles.clear()
		for value in args[1].split(","):
			cycles.append(maxi(int(value), 1))
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)

	var holder := Node2D.new()
	holder.y_sort_enabled = true
	add_child(holder)
	var room: Room = ROOM.instantiate() as Room
	holder.add_child(room)
	room.build(load(FOREST) as RoomKind, 20260929)
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

	for cycle in cycles:
		await _photograph(holder, player, out, tag, cycle)
	get_tree().quit(0)


func _photograph(holder: Node2D, player: Node2D, out: String, tag: String, cycle: int) -> void:
	for case in CASES:
		var spirit: Node2D = SPIRIT.instantiate() as Node2D
		var kind: SpiritKind = (load(str(case[1])) as SpiritKind).duplicate()
		spirit.set("kind", kind)
		spirit.set("guardian_cycle", cycle)
		spirit.set("_fan_index", int(case[5]))
		spirit.set("toughness", 1.8)
		spirit.process_mode = Node.PROCESS_MODE_DISABLED
		holder.add_child(spirit)
		spirit.global_position = CENTRE
		spirit.set("_target", player)
		spirit.set("_materialized", true)
		spirit.set("_guardian_pattern", int(case[3]))
		if int(case[2]) > 0:
			spirit.call("_set_telegraph", int(case[2]), Vector2.RIGHT.rotated(0.08), float(case[4]))
		if case.size() > 6:
			spirit.set("mutations", [Expedition.Mutation.ECHO] as Array[int])
			if int(case[6]) >= 0:
				var echoes: Array[Dictionary] = [{"left": 0.15, "volley": int(case[6]), "pattern": int(case[3]),
					"fan": int(case[5]), "angle": 0.08 + 0.42}]
				spirit.set("_echoes", echoes)
		# A telegraph animates; let it settle on a known frame.
		spirit.set("_telegraph_time", 0.6)
		spirit.queue_redraw()
		_camera.position = CENTRE + Vector2(50, 0)
		_camera.zoom = Vector2(Room.WORLD_CAMERA_ZOOM, Room.WORLD_CAMERA_ZOOM)
		await _settle(0.5)
		_save("%s/%s_c%d_%s.png" % [out, tag, cycle, case[0]])
		_camera.zoom = Vector2(2.6, 2.6)
		await _settle(0.3)
		_save("%s/%s_c%d_%s_zoom.png" % [out, tag, cycle, case[0]])
		spirit.queue_free()
		await get_tree().process_frame


func _settle(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
