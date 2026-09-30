extends Node

## Capture one framed shot per terrain at the real resolution (808×360).
##
## The atmosphere pass changes ground tone, vignette, beacon light, and prop
## shadows. None of that can be judged from a `.tres` diff, and driving the full
## arena to a given terrain needs eight cycles of state. So build the rooms
## directly and photograph them. Output lands under `builds/`, so it is not
## committed.
##
## Lives in `tools/`, which `_runtime_fingerprint()` excludes — adding it does
## not invalidate a store capture.

const ROOM: PackedScene = preload("res://scenes/gameplay/room.tscn")
const PLAYER: PackedScene = preload("res://scenes/actors/player.tscn")
## The arena puts this on its `Ui` CanvasLayer. Include it here or the preview
## lies about how framed the real screen looks.
const VIGNETTE: PackedScene = preload("res://scenes/ui/night_vignette.tscn")
const GRADE: PackedScene = preload("res://scenes/ui/night_grade.tscn")
## A lit beacon in frame. The ground tone has to be judged against the light
## the game is named after, not against an empty floor.
const BEACON: PackedScene = preload("res://scenes/objectives/beacon.tscn")
const KINDS: Array[String] = [
	"res://resources/rooms/forest.tres",
	"res://resources/rooms/field.tres",
	"res://resources/rooms/camp.tres",
	"res://resources/rooms/frost.tres",
	"res://resources/rooms/marsh.tres",
	"res://resources/rooms/ruins.tres",
]
## Same seed every run, so a diff between two shots is the change and not the scatter.
const SEED: int = 20260929
## Room coordinates the camera centers on. Inside `Room.PLAY`, away from the
## reserved door and structure zones, so the frame is not all empty floor.
const FRAME_AT: Vector2 = Vector2(950, 590)


func _ready() -> void:
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	# `-- tag` prefixes the file names, so a before and an after can sit side by side.
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tag: String = "%s_" % args[0] if args.size() >= 1 and not args[0].is_empty() else ""
	var out: String = ProjectSettings.globalize_path("res://../../builds/shots/rooms")
	DirAccess.make_dir_recursive_absolute(out)

	for path in KINDS:
		var kind: RoomKind = load(path) as RoomKind
		if kind == null:
			push_error("not a RoomKind: %s" % path)
			continue

		var holder := Node2D.new()
		add_child(holder)
		var room: Room = ROOM.instantiate() as Room
		holder.add_child(room)
		room.build(kind, SEED)

		# One actor in frame. A terrain shot with nothing in it cannot show whether
		# a character still reads against the new ground tone.
		var player: Node2D = PLAYER.instantiate() as Node2D
		holder.add_child(player)
		player.global_position = FRAME_AT

		var beacon: Node2D = BEACON.instantiate() as Node2D
		holder.add_child(beacon)
		beacon.global_position = FRAME_AT + Vector2(150, -40)
		beacon.set("lit", true)

		var camera := Camera2D.new()
		camera.position = FRAME_AT
		holder.add_child(camera)
		camera.make_current()

		var ui := CanvasLayer.new()
		holder.add_child(ui)
		ui.add_child(GRADE.instantiate())
		ui.add_child(VIGNETTE.instantiate())

		for _wait in 30:
			await RenderingServer.frame_post_draw
		var shot: Image = get_viewport().get_texture().get_image()
		shot.save_png("%s/%s%s.png" % [out, tag, path.get_file().get_basename()])
		holder.queue_free()
		await get_tree().process_frame

	get_tree().quit(0)
