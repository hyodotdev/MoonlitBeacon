extends Node

## Walk the camera across a room and photograph it at the game's own zoom.
##
## The depth pass has layers that only make sense in motion: mist that slides at a
## different speed from the ground, motes that live in world space, shafts that
## sway. A single still cannot show that they cover the screen at the map's corners
## or that the mist tiles without a seam. So put the camera at the corners and the
## middle and shoot each.
##
## Usage:
##     node scripts/godot.mjs --path apps/game res://tools/shot_tour.tscn -- tag [forest|field|camp]
##
## Output lands in `builds/shots/tour/<tag>_<terrain>_<n>.png`, so it is not
## committed. Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const ROOM: PackedScene = preload("res://scenes/gameplay/room.tscn")
const VIGNETTE: PackedScene = preload("res://scenes/ui/night_vignette.tscn")
const GRADE: PackedScene = preload("res://scenes/ui/night_grade.tscn")
const SEED: int = 20260929
const OUT: String = "res://../../builds/shots/tour"
## Room coordinates for the camera: the four corners of the play area, then the middle.
const STOPS: Array[Vector2] = [
	Vector2(330, 260), Vector2(1570, 260), Vector2(330, 920), Vector2(1570, 920), Vector2(950, 590),
]
const SETTLE_SECONDS: float = 1.2


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() >= 1 and not args[0].is_empty() else "shot"
	var terrain: String = args[1] if args.size() >= 2 else "forest"
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)

	var holder := Node2D.new()
	holder.y_sort_enabled = true
	add_child(holder)
	var room: Room = ROOM.instantiate() as Room
	holder.add_child(room)
	room.build(load("res://resources/rooms/%s.tres" % terrain) as RoomKind, SEED)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * Room.WORLD_CAMERA_ZOOM
	holder.add_child(camera)
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(GRADE.instantiate())
	layer.add_child(VIGNETTE.instantiate())

	for index in STOPS.size():
		camera.position = STOPS[index]
		var until: int = Time.get_ticks_msec() + int(SETTLE_SECONDS * 1000.0)
		while Time.get_ticks_msec() < until:
			await RenderingServer.frame_post_draw
		var shot: Image = get_viewport().get_texture().get_image()
		shot.save_png("%s/%s_%s_%d.png" % [out, tag, terrain, index])
		print("saved ", index)
	get_tree().quit(0)
