extends Node

## Photograph the three skills of the endless stretch in the real arena, at the moment each one shows:
## the ring of Moon Burst, the frost of Winter Bell on the spirits it reaches, and the marks a dash of
## Comet Trail leaves behind.
##
##     node scripts/godot.mjs --path apps/game res://tools/shot_skills.tscn -- draft
##
## Output: `builds/shots/skills/<tag>_<name>.png`. Lives in `tools/`, which
## `_runtime_fingerprint()` excludes.

const ARENA: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const OUT: String = "res://../../builds/shots/skills"

var _arena: Node2D = null


func _ready() -> void:
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() >= 1 and not args[0].is_empty() else "shot"
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)

	var arena: Node2D = ARENA.instantiate() as Node2D
	_arena = arena
	add_child(arena)
	await _frames(3)
	arena.call("debug_shield")
	# A calm arena: only the spirits this harness places.
	arena.set("_spawn_timer", 9999.0)
	arena.set("_raid_left", 9999.0)
	var player: Node2D = arena.get("_player") as Node2D
	for id in ["moon_burst", "moon_burst", "winter_bell", "winter_bell", "comet_trail", "comet_trail"]:
		arena.call("_on_relic_picked", load("res://resources/relics/%s.tres" % id) as Relic, false)
	await _frames(2)
	var skills: PlayerSkills = arena.get("_skills") as PlayerSkills

	var burst_ring: Array[Node2D] = _ring(arena, player, 10, 0)
	# They fade in from the dark first.
	await _wait(1.1)
	await _save(out, tag, "before")

	skills.call("on_card_chosen")
	await _wait(0.16)
	await _save(out, tag, "burst")
	await _wait(0.5)

	# Fresh spirits for the bell, tough enough to be seen standing after it tolls.
	var bell_ring: Array[Node2D] = _ring(arena, player, 12, 1)
	await _wait(1.1)
	skills.set("_bell_wait", 0.0)
	await _wait(0.2)
	await _save(out, tag, "bell")
	await _wait(0.6)
	await _save(out, tag, "chilled")
	for spirit in bell_ring:
		if is_instance_valid(spirit):
			spirit.queue_free()
	await _frames(2)

	var here: Vector2 = player.global_position
	skills.call("on_dash", here + Vector2(-70, 6), here + Vector2(0, 6))
	await _wait(0.2)
	await _save(out, tag, "trail")
	get_tree().quit(0)


## A ring of spirits standing round the player, frozen where they are so a frame can be judged.
func _ring(arena: Node2D, player: Node2D, count: int, seed_offset: int) -> Array[Node2D]:
	var ring: Array[Node2D] = []
	for index in count:
		var angle: float = TAU * float(index) / float(count) + 0.2 + 0.1 * float(seed_offset)
		var reach: float = 60.0 + 10.0 * float(index % 4)
		var spirit: Node2D = arena.call("_summon", player.global_position + Vector2.RIGHT.rotated(angle) * reach,
			"res://resources/drifter.tres" if index % 2 == 0 else "res://resources/wisp.tres", 1.0, false) as Node2D
		spirit.set("_materialized", true)
		spirit.set("_health", 9999)
		spirit.set_physics_process(false)
		ring.append(spirit)
	return ring


func _clear_panels() -> void:
	if _arena == null or not is_instance_valid(_arena):
		return
	var panel: Control = _arena.get("_relic") as Control
	if panel != null and panel.visible:
		panel.visible = false
	_arena.set("_owed", 0)
	var dialogue: Control = _arena.get_node_or_null("Ui/Dialogue") as Control
	if dialogue != null and dialogue.has_method("is_open") and bool(dialogue.call("is_open")):
		dialogue.call("_close")
	get_tree().paused = false


func _frames(count: int) -> void:
	for _i in count:
		_clear_panels()
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		_clear_panels()
		await RenderingServer.frame_post_draw


func _save(out: String, tag: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, tag, name])
	print("saved ", name)
