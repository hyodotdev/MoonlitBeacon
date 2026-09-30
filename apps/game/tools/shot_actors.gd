extends Node

## Photograph every actor on a real room floor: spirits, guardians and heroes.
##
## The depth pass changes how a character is lit, outlined and grounded. That
## cannot be judged from a diff, and the real arena only shows a few kinds at a
## time. So stand every kind in a row on the forest floor and photograph it, at
## the game's own zoom and at 3x for the details.
##
## Usage:
##     node scripts/godot.mjs --path apps/game res://tools/shot_actors.tscn -- before
##     node scripts/godot.mjs --path apps/game res://tools/shot_actors.tscn -- after all
##     node scripts/godot.mjs --path apps/game res://tools/shot_actors.tscn -- marsh all res://resources/rooms/marsh.tres
##
## The third argument is the room to stand them on (the forest by default), so a later place can be
## checked for whether every creature still reads against its floor.
##
## `all` stands all six guardians and all six heroes; without it only the first three
## of each stand, which is what the before/after pairs of the depth pass compared.
##
## Output lands in `builds/shots/actors/<tag>_<view>.png`, so it is not
## committed. Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const ROOM: PackedScene = preload("res://scenes/gameplay/room.tscn")
const PLAYER: PackedScene = preload("res://scenes/actors/player.tscn")
const SPIRIT: PackedScene = preload("res://scenes/actors/spirit.tscn")
const BEACON: PackedScene = preload("res://scenes/objectives/beacon.tscn")
const VIGNETTE: PackedScene = preload("res://scenes/ui/night_vignette.tscn")
const GRADE: PackedScene = preload("res://scenes/ui/night_grade.tscn")
const FOREST: String = "res://resources/rooms/forest.tres"
const SEED: int = 20260929
const OUT: String = "res://../../builds/shots/actors"

const SPIRITS: Array[String] = [
	"wisp", "drifter", "ember", "caster", "weaver", "stalker", "swarm"]
const GUARDIANS: Array[String] = [
	"guardian_forest", "guardian_field", "guardian_camp",
	"guardian_forest_thorn", "guardian_field_storm", "guardian_camp_siege"]
const HEROES: Array[String] = [
	"warden", "knight", "keeper", "dancer", "sage", "eclipse"]

## Where the rows stand. Inside `Room.PLAY`, clear of the reserved door zones.
const ROW_AT: Vector2 = Vector2(950, 560)
const ROW_GAP: float = 46.0
## A guardian's body is wider than a spirit's, so its row stands wider apart.
const GUARDIAN_GAP: float = 66.0
## Seconds of real time for entrance tweens and materializing to finish.
const SETTLE_SECONDS: float = 1.6

var _room: Room = null
var _camera: Camera2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() >= 1 and not args[0].is_empty() else "shot"
	var count: int = 6 if args.size() >= 2 and args[1] == "all" else 3
	var room_path: String = args[2] if args.size() >= 3 else FOREST
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)

	var holder := Node2D.new()
	holder.y_sort_enabled = true
	add_child(holder)
	_room = ROOM.instantiate() as Room
	holder.add_child(_room)
	_room.build(load(room_path) as RoomKind, SEED)

	_camera = Camera2D.new()
	holder.add_child(_camera)
	_camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(GRADE.instantiate())
	layer.add_child(VIGNETTE.instantiate())

	# A lit beacon behind the row, so the actors are judged under the game's
	# own warm light and not only the cold ambient one.
	var beacon: Node2D = BEACON.instantiate() as Node2D
	holder.add_child(beacon)
	beacon.global_position = ROW_AT + Vector2(150, -70)
	beacon.set("lit", true)

	# 1. What the game looks like: a mixed crowd at the real zoom.
	var crowd: Array[Node2D] = []
	crowd.append_array(_row(SPIRITS, ROW_AT + Vector2(-140, -30), holder))
	crowd.append_array(_row(GUARDIANS.slice(0, count), ROW_AT + Vector2(-40, 30), holder, GUARDIAN_GAP))
	crowd.append_array(_heroes(HEROES.slice(0, count), ROW_AT + Vector2(-40, 84), holder))
	_frame(Vector2(950, 590), Room.WORLD_CAMERA_ZOOM)
	await _settle()
	_save("%s/%s_game.png" % [out, tag])

	# 2. Details at 3x, one row at a time.
	_frame(ROW_AT + Vector2(-140, -30) + Vector2((SPIRITS.size() - 1) * ROW_GAP * 0.5, 0), 3.0)
	await _settle(0.3)
	_save("%s/%s_spirits.png" % [out, tag])
	_frame(ROW_AT + Vector2(-40, 30) + Vector2((count - 1) * GUARDIAN_GAP * 0.5, 0), 3.0)
	await _settle(0.3)
	_save("%s/%s_guardians.png" % [out, tag])
	_frame(ROW_AT + Vector2(-40, 84) + Vector2((count - 1) * ROW_GAP * 0.5, 0), 3.0)
	await _settle(0.3)
	_save("%s/%s_heroes.png" % [out, tag])

	# 3. A kill, a moment after it lands: a small burst and a big one.
	var sparks := KillSparks.new()
	holder.add_child(sparks)
	var stage: Vector2 = ROW_AT + Vector2(-40, 130)
	sparks.burst(stage + Vector2(0, 0), Color(0.75, 0.96, 1.0, 1.0))
	sparks.burst(stage + Vector2(ROW_GAP, 0), Color(1.0, 0.66, 0.3, 1.0))
	sparks.burst(stage + Vector2(ROW_GAP * 2.0, 0), Color(0.58, 0.82, 1.0, 1.0), true)
	_frame(stage + Vector2(ROW_GAP, -6), 3.0)
	await _settle(0.12)
	_save("%s/%s_sparks.png" % [out, tag])
	get_tree().quit(0)


func _frame(at: Vector2, zoom: float) -> void:
	_camera.position = at
	_camera.zoom = Vector2(zoom, zoom)


func _row(names: Array, from: Vector2, holder: Node2D, gap: float = ROW_GAP) -> Array[Node2D]:
	var placed: Array[Node2D] = []
	for index in names.size():
		var spirit: Node2D = SPIRIT.instantiate() as Node2D
		spirit.set("kind", load("res://resources/%s.tres" % names[index]))
		holder.add_child(spirit)
		spirit.global_position = from + Vector2(float(index) * gap, 0)
		placed.append(spirit)
	return placed


func _heroes(names: Array, from: Vector2, holder: Node2D) -> Array[Node2D]:
	var placed: Array[Node2D] = []
	for index in names.size():
		var player: Node2D = PLAYER.instantiate() as Node2D
		holder.add_child(player)
		player.global_position = from + Vector2(float(index) * ROW_GAP, 0)
		# One camera at a time, or the last hero added steals the frame.
		(player.get_node("Cam") as Camera2D).enabled = false
		# The default bounds are the old 616x172 strip; without this the hero is
		# pulled into that strip on its first physics tick and leaves the frame.
		player.call("set_bounds", Room.PLAY)
		player.call("apply_hero_visual", load("res://resources/heroes/%s.tres" % names[index]))
		placed.append(player)
	_camera.make_current()
	return placed


func _settle(seconds: float = SETTLE_SECONDS) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await RenderingServer.frame_post_draw
	# Two more frames so the last change is on screen before the read-back.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save(path: String) -> void:
	var shot: Image = get_viewport().get_texture().get_image()
	shot.save_png(path)
	print("saved ", path)
