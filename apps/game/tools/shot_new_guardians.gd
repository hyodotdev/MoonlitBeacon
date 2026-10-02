extends Node

## Photograph the guardians of the later places in their own rooms, live, at the game's own zoom.
##
## Each guardian runs its real move machine against a player who stands still, and a frame is
## saved when it reaches the moments that matter: the fan or the dive lane (owl), the crouch with
## its mark on the floor and the flop's ring (toad), the circles and the ring (sentinel), and a
## plain one of each form so the two can be compared.
##
##     node scripts/godot.mjs --path apps/game res://tools/shot_new_guardians.tscn -- draft
##
## Output: `builds/shots/new_guardians/<tag>_<name>.png`. Lives in `tools/`, which
## `_runtime_fingerprint()` excludes.

const ROOM: PackedScene = preload("res://scenes/gameplay/room.tscn")
const PLAYER: PackedScene = preload("res://scenes/actors/player.tscn")
const SPIRIT: PackedScene = preload("res://scenes/actors/spirit.tscn")
const VIGNETTE: PackedScene = preload("res://scenes/ui/night_vignette.tscn")
const GRADE: PackedScene = preload("res://scenes/ui/night_grade.tscn")
const OUT: String = "res://../../builds/shots/new_guardians"
const CENTRE: Vector2 = Vector2(950, 590)

## guardian resource, its room, then the moves to photograph:
## [name, move (Spirit.GuardianMove), how far into the move (0..1)]
const CASES: Array = [
	["frost", "res://resources/guardian_frost.tres", "res://resources/rooms/frost.tres",
		[["fan", 2, 0.72], ["dive", 1, 0.8]]],
	["frost_rime", "res://resources/guardian_frost_rime.tres", "res://resources/rooms/frost.tres",
		[["fan", 2, 0.72]]],
	["marsh", "res://resources/guardian_marsh.tres", "res://resources/rooms/marsh.tres",
		[["crouch", 1, 0.5], ["ring", 4, 0.72]]],
	["marsh_glow", "res://resources/guardian_marsh_glow.tres", "res://resources/rooms/marsh.tres",
		[["crouch", 1, 0.5]]],
	["ruins", "res://resources/guardian_ruins.tres", "res://resources/rooms/ruins.tres",
		[["glyphs", 1, 0.55], ["ring", 4, 0.72]]],
	["ruins_halo", "res://resources/guardian_ruins_halo.tres", "res://resources/rooms/ruins.tres",
		[["glyphs", 1, 0.55]]],
]

var _camera: Camera2D = null


func _ready() -> void:
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() >= 1 and not args[0].is_empty() else "shot"
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)

	for case in CASES:
		await _stage(tag, out, case)
	get_tree().quit(0)


func _stage(tag: String, out: String, case: Array) -> void:
	var holder := Node2D.new()
	holder.y_sort_enabled = true
	add_child(holder)
	var room: Room = ROOM.instantiate() as Room
	holder.add_child(room)
	var room_kind: RoomKind = (load(str(case[2])) as RoomKind).duplicate() as RoomKind
	room_kind.obstacle_count = 0
	room.build(room_kind, 20260929)
	_camera = Camera2D.new()
	holder.add_child(_camera)
	_camera.make_current()
	var layer := CanvasLayer.new()
	holder.add_child(layer)
	layer.add_child(GRADE.instantiate())
	layer.add_child(VIGNETTE.instantiate())

	var player: Node2D = PLAYER.instantiate() as Node2D
	holder.add_child(player)
	player.global_position = CENTRE + Vector2(130, 24)
	(player.get_node("Cam") as Camera2D).enabled = false
	player.call("set_bounds", Room.PLAY)
	player.call("apply_hero_visual", load("res://resources/heroes/warden.tres"))
	player.set_process(false)
	player.set_physics_process(false)
	_camera.make_current()

	var spirit: Node2D = SPIRIT.instantiate() as Node2D
	spirit.set("kind", (load(str(case[1])) as SpiritKind).duplicate())
	spirit.set("guardian_cycle", 3)
	spirit.set("toughness", 1.8)
	holder.add_child(spirit)
	spirit.global_position = CENTRE
	spirit.set("_target", player)
	spirit.set("_terrain_room", room)
	spirit.set("_materialized", true)

	_camera.zoom = Vector2(Room.WORLD_CAMERA_ZOOM, Room.WORLD_CAMERA_ZOOM)
	_camera.position = CENTRE + Vector2(60, 0)
	await _settle(0.4)
	_save("%s/%s_%s_idle.png" % [out, tag, case[0]])
	_camera.zoom = Vector2(2.6, 2.6)
	await _settle(0.2)
	_save("%s/%s_%s_idle_zoom.png" % [out, tag, case[0]])
	_camera.zoom = Vector2(Room.WORLD_CAMERA_ZOOM, Room.WORLD_CAMERA_ZOOM)

	for moment in case[3]:
		var wanted_move: int = int(moment[1])
		var wanted_ratio: float = float(moment[2])
		var until: int = Time.get_ticks_msec() + 30000
		var got: bool = false
		while Time.get_ticks_msec() < until:
			await RenderingServer.frame_post_draw
			# Keep the player where the shot wants them however the guardian shoves.
			player.global_position = CENTRE + Vector2(130, 24)
			if int(spirit.get("_guardian_move")) != wanted_move:
				continue
			var left: float = float(spirit.get("_guardian_left"))
			var duration: float = maxf(float(spirit.get("_guardian_move_duration")), 0.001)
			if 1.0 - left / duration >= wanted_ratio:
				got = true
				break
		_camera.position = spirit.global_position.lerp(player.global_position, 0.5)
		await RenderingServer.frame_post_draw
		_save("%s/%s_%s_%s.png" % [out, tag, case[0], moment[0]])
		if not got:
			printerr("did not reach ", moment[0], " for ", case[0])
	holder.queue_free()
	await get_tree().process_frame


func _settle(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
