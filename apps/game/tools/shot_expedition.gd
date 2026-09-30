extends Node

## Photograph the expedition update in the real arena: a fork, an omen, a mutated guardian and
## the skills, each in a state a player would meet.
##
## Run it with a throwaway HOME so nothing touches a real save. Output lands in
## `builds/shots/expedition/<tag>_<scene>.png`, so it is not committed. Lives in `tools/`, which
## `_runtime_fingerprint()` excludes.
##
##     HOME=$(mktemp -d) node scripts/godot.mjs --path apps/game res://tools/shot_expedition.tscn -- tag

const ARENA: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const OUT: String = "res://../../builds/shots/expedition"

var _arena: Node2D = null
var _out: String = ""
var _tag: String = "shot"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_tag = args[0] if args.size() >= 1 and not args[0].is_empty() else "shot"
	_out = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(_out)

	_arena = ARENA.instantiate() as Node2D
	get_tree().root.add_child.call_deferred(_arena)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = _arena
	_arena.call("debug_shield")
	_arena.set("_forks_enabled", true)

	await _shoot_fork()
	await _shoot_omen()
	await _shoot_boss()
	await _shoot_skills()
	await _shoot_card()
	get_tree().quit(0)


func _settle(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _tag, name])
	print("saved ", name)


func _player() -> Node2D:
	return _arena.get("_player") as Node2D


## Two gates on a cycle-2 fork, the player beside the first one.
func _shoot_fork() -> void:
	_arena.set("_run_seed", 24680)
	_arena.set("_cycle", 2)
	_arena.set("_zone_index", 0)
	_arena.set("_route", [Expedition.start_terrain(24680, 2, 0), -1, -1] as Array[int])
	_arena.call("_change_cycle_world")
	await _settle(0.4)
	_arena.call("debug_light_next_beacon")
	await _settle(1.8)
	var gate: Node2D = _arena.get("_gate") as Node2D
	var player: Node2D = _player()
	player.position = gate.position + Vector2(-130, 40) if gate.position.x > 900 \
		else gate.position + Vector2(130, 40)
	player.call("reset_physics_interpolation")
	await _settle(0.8)
	_save("fork")
	# The second gate, from the other side.
	var other: Node2D = _arena.get("_gate_b") as Node2D
	if other != null:
		player.position = other.position + Vector2(-130, 40) if other.position.x > 900 \
			else other.position + Vector2(130, 40)
		player.call("reset_physics_interpolation")
		await _settle(0.8)
		_save("fork_b")


## Depth 1: the omen on the world line and the depth on the top bar.
func _shoot_omen() -> void:
	_arena.call("_close_fork_gates")
	_arena.call("_finish_cycle_debug_reset") if _arena.has_method("_finish_cycle_debug_reset") else null
	_arena.set("_escape_active", false)
	_arena.get("_gate").call("close")
	var found: Vector2i = Vector2i(24680, 0)
	for run_seed in range(1, 4000):
		var omens: Array[int] = Expedition.omens_for(run_seed, 9, 0)
		if omens.size() == 1 and omens[0] == Expedition.Omen.BLOOD_MOON:
			found = Vector2i(run_seed, 0)
			break
	_arena.set("_run_seed", found.x)
	_arena.set("_cycle", 9)
	_arena.set("_zone_index", 0)
	_arena.set("_route", [-1, -1, -1] as Array[int])
	_arena.call("_change_cycle_world")
	var hud: Control = _arena.get("_hud") as Control
	hud.call("set_cycle", 9)
	_player().position = Room.MAP * 0.5
	_player().call("reset_physics_interpolation")
	await _settle(1.0)
	_save("omen")


## A guardian of the official-win cycle, with two mutations, its shield up and marks on the floor.
func _shoot_boss() -> void:
	_arena.set("_run_seed", 13579)
	_arena.set("_cycle", 8)
	_arena.set("_zone_index", 2)
	_arena.set("_route", [-1, -1, 0] as Array[int])
	_arena.call("_change_cycle_world")
	_player().position = Room.MAP * 0.5
	_player().call("reset_physics_interpolation")
	_arena.call("_summon_guardian")
	await _settle(2.4)
	var guardian: Node2D = _arena.get("_guardian") as Node2D
	if guardian == null:
		return
	guardian.set("mutations", [Expedition.Mutation.AEGIS, Expedition.Mutation.METEORS,
		Expedition.Mutation.FRENZY] as Array[int])
	_arena.set("_guardian_detail", _arena.call("_mutation_line", guardian.get("mutations")))
	_arena.call("debug_stage_guardian")
	guardian.set("_aegis_left", 2.0)
	guardian.set("_guardian_move", guardian.get_script().GuardianMove.RECOVER)
	guardian.set("_guardian_left", 4.0)
	await _settle(1.4)
	_save("boss")


## Every skill at once: familiars round the hero, the ward's bubble, a comet mark and a crowd.
func _shoot_skills() -> void:
	var guardian: Node2D = _arena.get("_guardian") as Node2D
	if guardian != null and is_instance_valid(guardian):
		_arena.set("_guardian", null)
		guardian.queue_free()
	_arena.call("_prune_spirits")
	_arena.set("_cycle", 5)
	_arena.set("_zone_index", 0)
	_arena.set("_route", [-1, -1, -1] as Array[int])
	_arena.call("_change_cycle_world")
	var player: Node2D = _player()
	player.position = Room.MAP * 0.5
	player.call("reset_physics_interpolation")
	for id in ["lantern_familiar", "lantern_familiar", "moon_ward", "star_magnet",
			"thorn_bloom", "second_light", "comet_call"]:
		_arena.call("_on_relic_picked", load("res://resources/relics/%s.tres" % id), false)
	for i in 9:
		var spirit: Node2D = _arena.call("_summon",
			player.position + Vector2(90 + (i % 3) * 16, -40 + (i / 3) * 24 + (i % 2) * 6),
			"res://resources/wisp.tres", 1.0, false) as Node2D
		if spirit != null:
			spirit.set("_materialized", true)
	await _settle(1.2)
	var skills: PlayerSkills = _arena.get("_skills") as PlayerSkills
	skills.set("_comet_wait", 0.0)
	await _settle(0.55)
	_save("skills")


## A level-up card offering a skill for the first time.
func _shoot_card() -> void:
	var relic: Control = _arena.get("_relic") as Control
	relic.set("cycle", 8)
	relic.set("_skills_seen", {})
	relic.set("_first_offer_done", true)
	relic.call("open")
	await _settle(0.9)
	_save("card")
