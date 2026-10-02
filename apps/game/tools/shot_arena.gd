extends Node

## Photograph the real arena a few seconds into a run, HUD and all.
##
## The gallery and the room tour build their own stage. This one runs the game's
## own scene, so it shows what a player sees: the room, the hero, the first
## spirits, the grade, the vignette and the HUD together.
##
## Run it with a throwaway HOME, so a run that ends cannot touch a real save:
##
##     HOME=$(mktemp -d) node scripts/godot.mjs --path apps/game res://tools/shot_arena.tscn -- tag 6
##
## The second argument is how many seconds to let the run play before the shot. Any
## further arguments are node paths under the arena to delete first (`Ui/Grade`), so a
## layer can be judged with and without itself.
## Output lands in `builds/shots/arena/<tag>_<n>.png`, so it is not committed.
## Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const ARENA: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const OUT: String = "res://../../builds/shots/arena"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() >= 1 and not args[0].is_empty() else "shot"
	var seconds: float = float(args[1]) if args.size() >= 2 else 6.0
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)

	var arena: Node2D = ARENA.instantiate() as Node2D
	get_tree().root.add_child.call_deferred(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = arena
	for extra in args.slice(2):
		var doomed: Node = arena.get_node_or_null(extra)
		if doomed != null:
			doomed.queue_free()
		else:
			push_warning("shot_arena: no node %s" % extra)

	var shots: int = 3
	for index in shots:
		var until: int = Time.get_ticks_msec() + int(seconds * 1000.0 / float(shots))
		while Time.get_ticks_msec() < until:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [out, tag, index])
		print("saved ", index)
	get_tree().quit(0)
