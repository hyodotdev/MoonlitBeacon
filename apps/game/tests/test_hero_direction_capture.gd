extends Node

## The Pixel 10 hero-direction-matrix debug board keeps live Player move/dash/Sprite/Camera
## alive, strips only combat dirt, and emits ready only after two consecutive observations.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const PROBE_SCRIPT: Script = preload("res://scripts/dev/store_capture_probe.gd")
const BOOT_SCRIPT: Script = preload("res://scripts/dev/store_capture_boot.gd")

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect_true("hero_direction" in PROBE_SCRIPT.ALLOWED_KINDS,
		"allows hero_direction runtime probe")
	_expect_true("hero_direction" not in BOOT_SCRIPT.ALLOWED_KINDS,
		"hero_direction is not allowed as a boost boot request")
	_expect_true(PROBE_SCRIPT.valid_nonce("a".repeat(64)),
		"allows a 64-digit lowercase hex nonce")
	for invalid_nonce in [
		"A".repeat(64), "+" + "a".repeat(63), "-" + "a".repeat(63),
		"0x" + "a".repeat(62), "g".repeat(64), "a".repeat(63),
	]:
		_expect_true(not PROBE_SCRIPT.valid_nonce(invalid_nonce),
			"rejects a nonce that is not lowercase hex")

	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	get_tree().root.add_child(arena)
	# The production probe also proves the current scene is Arena itself. Even if the test
	# even if the test attached Arena as a fixture child, only current_scene is aligned so the same boundary passes.
	get_tree().current_scene = arena
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Player = arena.get_node("Player") as Player
	var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	var camera: Camera2D = player.get_node("Cam") as Camera2D
	var breathe: AnimationPlayer = player.get_node("Breathe") as AnimationPlayer
	var request: Dictionary = {
		"kind": "hero_direction",
		"nonce": "a".repeat(64),
		"hero_resource_path": str(arena.get("_run_hero_path")),
		"direction": "down",
	}

	arena.call("debug_prepare_store_capture", request)
	var clearing: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_true(bool(clearing.get("capture_active", false)),
		"hero-direction capture active")
	_expect_true(int(clearing.get("enemy_count", 0)) > 0,
		"keeps existing enemies on a queue_free-scheduled frame via actual tree count")
	_expect_true(not bool(clearing.get("ready", true)),
		"rejects ready before existing enemies leave the tree")

	var clean: Dictionary = {}
	for i in 3:
		await get_tree().process_frame
		clean = arena.call("debug_store_capture_state", request) as Dictionary
	_expect_true(bool(clean.get("ready", false)), "ready after two consecutive clean frames")
	_expect_equal(clean.get("hero_resource_path"), arena.get("_run_hero_path"),
		"actual hero resource path of the current run")
	_expect_equal(int(clean.get("level", -1)), 1, "fresh Lv1 proof")
	_expect_equal(int(clean.get("kills", -1)), 0, "fresh kills 0 proof")
	_expect_equal(int(clean.get("kill_score", -1)), 0, "fresh kill-score 0 proof")
	_expect_equal(int(clean.get("health", -1)), int(clean.get("max_health", -2)),
		"fresh max-health proof")
	_expect_true(bool(clean.get("health_full", false)), "fresh full-health proof")
	_expect_true(bool(clean.get("shielded", false)), "capture i-frames stabilizer proof")
	for field in [
		"capture_active", "hero_resource_loaded", "hero_sprite_node_present",
		"hero_sprite_visible_in_tree", "hero_sprite_opaque", "hero_sprite_playing",
		"hero_sprite_animation_matches_facing",
		"hero_sprite_frame_texture_present",
		"hero_sprite_frame_texture_matches_resource",
		"hero_sprite_draw_rect_fully_inside_viewport", "hero_sprite_visual_ready",
		"tutorial_suppressed", "result_modal_hidden", "relic_modal_hidden",
		"pause_modal_hidden", "all_modals_hidden", "player_capture_vfx_hidden",
		"player_physics_active", "camera_current", "combat_progress_frozen",
		"hero_resource_matches_request", "hero_direction_matches_request",
		"hero_animation_matches_request",
	]:
		_expect_true(bool(clean.get(field, false)), "clean proof " + field)
	for field in [
		"enemy_count", "guardian_count", "hostile_projectile_count",
		"friendly_projectile_count", "projectile_count", "pickup_count",
		"player_afterimage_count", "arena_aux_vfx_count", "raid_queue_count",
		"pending_dew_count", "pending_ember_count",
	]:
		_expect_equal(int(clean.get(field, -1)), 0, "clean count " + field)
	_expect_true(not bool(clean.get("tree_paused", true)), "capture tree is running")
	_expect_true(not bool(clean.get("banner_visible", true)), "capture banner hidden")
	_expect_true(camera.enabled and camera.get_parent() == player,
		"keeps the actual Player child Camera2D")
	_expect_true(not camera.position_smoothing_enabled,
		"forbids duplicate position smoothing on Camera2D above an interpolated Player")
	_expect_true(bool(ProjectSettings.get_setting(
		"physics/common/physics_interpolation", false)),
		"Player and child Camera2D share physics interpolation")
	var wrong_hero_request: Dictionary = request.duplicate()
	wrong_hero_request["hero_resource_path"] = "res://resources/heroes/not-current.tres"
	var wrong_hero: Dictionary = arena.call(
		"debug_store_capture_state", wrong_hero_request) as Dictionary
	_expect_true(not bool(wrong_hero.get("hero_resource_matches_request", true)),
		"rejects another hero's resource nonce")
	_expect_true(not bool(wrong_hero.get("ready", true)), "rejects ready for another hero's proof")
	var wrong_direction_request: Dictionary = request.duplicate()
	wrong_direction_request["direction"] = "left"
	var wrong_direction: Dictionary = arena.call(
		"debug_store_capture_state", wrong_direction_request) as Dictionary
	_expect_true(not bool(wrong_direction.get("hero_direction_matches_request", true)),
		"rejects a different-facing nonce")
	_expect_true(not bool(wrong_direction.get("ready", true)), "rejects ready for a different-facing proof")

	# A clean streak stacked on the previous facing never carries to a new nonce/facing.
	player.set_move_input(Vector2.RIGHT)
	player.call("_physics_process", 0.12)
	var right_request: Dictionary = request.duplicate()
	right_request["nonce"] = "b".repeat(64)
	right_request["direction"] = "right"
	arena.call("debug_prepare_store_capture", right_request)
	var right_walk: Dictionary = arena.call(
		"debug_store_capture_state", right_request) as Dictionary
	_expect_equal(str(right_walk.get("hero_sprite_animation", "")), "walk_right",
		"observes actual walk_right for an explicit facing request")
	_expect_true(not bool(right_walk.get("hero_animation_matches_request", true)),
		"a still-right request also rejects same-facing walk")
	_expect_equal(int(right_walk.get("clean_frame_streak", -1)), 0,
		"walk during a still request is clean streak 0")
	_expect_true(not bool(right_walk.get("ready", true)),
		"rejects walk ready during a still request")
	_settle_player_idle(player)
	# Switching to idle on the same render frame as a dirty walk observation cannot raise
	# the clean streak. Observe twice from the next live process frame.
	await get_tree().process_frame
	var right_first: Dictionary = arena.call(
		"debug_store_capture_state", right_request) as Dictionary
	_expect_equal(str(right_first.get("hero_sprite_animation", "")), "idle_right",
		"observes actual idle_right after releasing input")
	_expect_equal(int(right_first.get("clean_frame_streak", -1)), 1,
		"first idle observation of a new nonce is streak 1")
	_expect_true(not bool(right_first.get("ready", true)),
		"rejects ready on the first idle observation of a new nonce")
	await get_tree().process_frame
	var right_second: Dictionary = arena.call(
		"debug_store_capture_state", right_request) as Dictionary
	_expect_true(bool(right_second.get("ready", false)),
		"ready on the second clean observation of a new nonce")
	request = right_request

	# Use the same Player input, physics, and Sprite switches Arena's live stick path calls.
	var before_walk: Vector2 = player.position
	player.set_move_input(Vector2.RIGHT)
	player.call("_physics_process", 0.12)
	_expect_true(player.position.x > before_walk.x, "actual Player walk during capture")
	_expect_equal(str(sprite.animation), "walk_right", "actual walk_right animation during capture")
	_expect_true(sprite.is_playing(), "AnimatedSprite2D plays during capture")
	_expect_true(not breathe.is_playing(), "stops duplicate full-body Breathe on 4-frame heroes")
	_expect_equal(sprite.offset, Vector2(0.0, -8.0),
		"Sprite baseline stays fixed while walking")
	var static_walk: Dictionary = arena.call(
		"debug_store_capture_state", right_request) as Dictionary
	_expect_true(not bool(static_walk.get("ready", true)),
		"same-facing walk after ready also invalidates the still proof")
	_expect_equal(int(static_walk.get("clean_frame_streak", -1)), 0,
		"switching to walk after ready resets the streak")
	request["direction"] = "right"

	var before_dash: Vector2 = player.position
	player.set_move_input(Vector2.DOWN)
	_expect_true(player.dash(Vector2.DOWN), "actual Player dash start during capture")
	player.call("_physics_process", 0.05)
	_expect_true(player.position.y > before_dash.y and player.is_dashing(),
		"actual dash physics during capture")
	_expect_equal(str(sprite.animation), "walk_down", "dash-facing animation during capture")
	request["direction"] = "down"
	request["nonce"] = "c".repeat(64)
	arena.call("debug_prepare_store_capture", request)
	await get_tree().process_frame
	var dash_state: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_equal(int(dash_state.get("player_afterimage_count", -1)), 0,
		"no afterimage covering the dash silhouette")
	_expect_true(not bool(dash_state.get("ready", true)),
		"explicit down-still request rejects dash walk_down frames")
	_settle_player_idle(player)
	await _expect_two_clean_frames(arena, request, "idle restored after dash")

	# Motion footage is direction=any only. idle→walk→dash in the same clean hold
	# still keep the animation contract and ready.
	var video_request: Dictionary = request.duplicate()
	video_request["nonce"] = "e".repeat(64)
	video_request["direction"] = "any"
	arena.call("debug_prepare_store_capture", video_request)
	await _expect_two_clean_frames(arena, video_request, "footage any idle")
	var video_idle: Dictionary = arena.call(
		"debug_store_capture_state", video_request) as Dictionary
	_expect_true(bool(video_idle.get("hero_animation_matches_request", false)),
		"footage any allows idle")
	_expect_true(bool(video_idle.get("ready", false)), "footage any idle ready kept")

	player.set_move_input(Vector2.RIGHT)
	player.call("_physics_process", 0.12)
	var video_walk: Dictionary = arena.call(
		"debug_store_capture_state", video_request) as Dictionary
	_expect_equal(str(video_walk.get("hero_sprite_animation", "")), "walk_right",
		"footage any actual walk_right")
	_expect_true(bool(video_walk.get("hero_animation_matches_request", false)),
		"footage any allows walk")
	_expect_true(bool(video_walk.get("ready", false)), "footage any walk ready kept")

	_settle_player_idle(player)
	_expect_true(not breathe.is_playing(), "only the idle sheet plays while still")
	_expect_equal(sprite.offset, Vector2(0.0, -8.0),
		"Sprite baseline holds across idle/walk switches")
	# Also let the previous dash's live cooldown finish before starting the next dash.
	player.call("_physics_process", player.dash_cooldown_time + 0.01)
	_expect_true(player.dash(Vector2.DOWN), "footage any actual dash start")
	player.call("_physics_process", 0.05)
	var video_dash: Dictionary = arena.call(
		"debug_store_capture_state", video_request) as Dictionary
	_expect_equal(str(video_dash.get("hero_sprite_animation", "")), "walk_down",
		"footage any actual dash walk_down")
	_expect_true(bool(video_dash.get("hero_animation_matches_request", false)),
		"footage any allows the dash animation")
	_expect_true(bool(video_dash.get("ready", false)), "footage any dash ready kept")
	_expect_equal(int(video_dash.get("player_afterimage_count", -1)), 0,
		"footage any dash also has no afterimage")

	# A normal-play dash draws only 0.14s moonlight speed lines, with no full-body Sprite clone.
	# Briefly lift capture suppression and lock the live VFX path directly.
	_settle_player_idle(player)
	player.call("_physics_process", player.dash_cooldown_time + 0.01)
	player.debug_set_direction_capture_vfx_suppressed(false)
	_expect_true(player.dash(Vector2.DOWN), "normal dash speed lines start")
	_expect_true(float(player.get("_dash_streak_left")) > 0.0,
		"short non-body speed lines active during dash")
	_expect_equal(get_tree().get_nodes_in_group(&"player_afterimages").size(), 0,
		"a normal dash also does not clone the full-body Sprite")
	player.call("_physics_process", Player.DASH_STREAK_SECONDS + 0.01)
	_expect_equal(float(player.get("_dash_streak_left")), 0.0,
		"speed lines end before the dash")
	player.debug_set_direction_capture_vfx_suppressed(true)

	# Later dirt counterexamples return to the still-down contract.
	_settle_player_idle(player)
	# Manual physics ticks advanced the dash distance in one go, so give Camera2D's actual
	# Give render interpolation time to catch up.
	for i in 12:
		await get_tree().process_frame
	request["nonce"] = "f".repeat(64)
	request["direction"] = "down"
	arena.call("debug_prepare_store_capture", request)
	await _expect_two_clean_frames(arena, request, "still-down restored after footage")

	# Inject combat dirt and a modal. A queue_free-scheduled frame must fail, and
	# hold must remove them from the live tree, then two clean observations must be stacked again.
	var injected: Array[Node2D] = []
	for group in [
		&"spirits", &"hostile_projectiles", &"friendly_projectiles", &"moon_embers",
	]:
		var node: Node2D = Node2D.new()
		node.add_to_group(group)
		if group == &"spirits":
			node.set_meta(&"moonlit_guardian_kind_source_path", "fixture")
		arena.add_child(node)
		injected.append(node)
	arena.set("_pending_dews", 1)
	arena.set("_pending_embers", 1)
	(arena.get("_ember_positions") as Array).append(player.position)
	(arena.get("_ember_elites") as Array).append(false)
	(arena.get("_raid_queue") as Array).append({"fixture": true})
	var hud: Control = arena.get_node("Ui/Hud") as Control
	hud.call("debug_lock_capture_banner", "fixture", Color.WHITE)
	(arena.get_node("Ui/Pause") as Control).call("set_overlay_visible", true)
	(arena.get_node("Ui/Result") as Control).visible = true
	(arena.get_node("Ui/Relic") as Control).visible = true
	get_tree().paused = true
	var dirty: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_true(int(dirty.get("enemy_count", 0)) > 0,
		"detects an injected enemy queue_free-scheduled frame")
	_expect_true(int(dirty.get("projectile_count", 0)) > 0,
		"detects an injected projectile queue_free-scheduled frame")
	_expect_true(int(dirty.get("pickup_count", 0)) > 0,
		"detects an injected pickup queue_free-scheduled frame")
	_expect_true(not bool(dirty.get("ready", true)), "rejects ready for a dirty frame")
	_expect_true(not bool(dirty.get("tree_paused", true)), "hold unpauses")
	_expect_true(not bool(dirty.get("banner_visible", true)), "locked banner also hides immediately")
	_expect_true(bool(dirty.get("all_modals_hidden", false)), "injected modal hidden immediately")

	# Deferred races like the tutorial _ready scheduled also cannot pierce suppression.
	arena.call_deferred("_begin_tutorial")
	await get_tree().process_frame
	var tutorial_race: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_true(not bool(tutorial_race.get("banner_visible", true)),
		"deferred tutorial-banner race hidden")
	_expect_true(bool(tutorial_race.get("tutorial_suppressed", false)),
		"deferred tutorial state re-suppressed")
	_expect_equal(int(tutorial_race.get("clean_frame_streak", -1)), 1,
		"first clean frame after dirt restarts the streak at 1")
	_expect_true(not bool(tutorial_race.get("ready", true)),
		"rejects ready on the first clean frame after dirt")
	await get_tree().process_frame
	var recovered_second: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_true(bool(recovered_second.get("ready", false)),
		"ready on the second consecutive clean frame after dirt")

	# Fail if the live Sprite is hidden or the current frame source is missing, even if surroundings are clean.
	sprite.visible = false
	var hidden_sprite: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_true(not bool(hidden_sprite.get("hero_sprite_visual_ready", true)),
		"rejects a hidden hero Sprite as live")
	_expect_true(not bool(hidden_sprite.get("ready", true)), "rejects ready for a hidden hero Sprite")
	sprite.visible = true

	# Capture prep must not rewrite a bad run as fresh. Bad level/kills/health
	# still close ready, and after recovery still require two clean frames again.
	arena.set("_level", 2)
	var wrong_level: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_equal(int(wrong_level.get("level", -1)), 2, "bad level state preserved")
	_expect_true(not bool(wrong_level.get("ready", true)), "rejects Lv2 capture ready")
	arena.set("_level", 1)
	await _expect_two_clean_frames(arena, request, "level restored")

	arena.set("_kills", 1)
	var wrong_kills: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_equal(int(wrong_kills.get("kills", -1)), 1, "bad kills state preserved")
	_expect_true(not bool(wrong_kills.get("ready", true)), "rejects capture ready at 1 kill")
	arena.set("_kills", 0)
	await _expect_two_clean_frames(arena, request, "kills restored")

	var max_health: int = int(arena.get("_max_health"))
	arena.call("_set_health", max_health - 1)
	var wrong_health: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_equal(int(wrong_health.get("health", -1)), max_health - 1,
		"missing-health state preserved")
	_expect_true(not bool(wrong_health.get("ready", true)), "rejects capture ready at missing health")
	arena.call("_set_health", max_health)
	await _expect_two_clean_frames(arena, request, "health restored")

	# Reach charging and already-scheduled guardians/loot must not appear one frame after ready.
	var beacon: Node2D = (arena.get("_beacons") as Array)[0] as Node2D
	beacon.call("ignite")
	await get_tree().process_frame
	var beacon_state: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_equal(int(beacon_state.get("actual_lit_beacon_count", -1)), 0,
		"beacon ignite is a no-op during capture")
	_expect_equal(int(beacon_state.get("beacon_monitoring_count", -1)), 0,
		"beacon Reach monitoring stops during capture")
	_expect_equal(float(beacon_state.get("beacon_max_charge", -1.0)), 0.0,
		"beacon charge 0 during capture")

	# An add_child scheduled just before active must not remain in the live tree when the helper runs.
	arena.set("_debug_hero_direction_capture_active", false)
	arena.set("_guardian", null)
	arena.call("_summon_guardian")
	request["nonce"] = "d".repeat(64)
	arena.call("debug_prepare_store_capture", request)
	await get_tree().process_frame
	var guardian_first: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_equal(int(guardian_first.get("guardian_count", -1)), 0,
		"scheduled guardian is blocked from entering the capture tree")
	_expect_true(not bool(guardian_first.get("ready", true)),
		"rejects ready on the first clean frame after clearing a scheduled guardian")
	await get_tree().process_frame
	var guardian_second: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_true(bool(guardian_second.get("ready", false)),
		"ready on the second clean frame after clearing a scheduled guardian")

	var deferred_dew: Area2D = Area2D.new()
	deferred_dew.set_meta(&"zone_serial", int(arena.get("_zone_serial")))
	arena.call_deferred("_attach_dew", deferred_dew)
	var deferred_core: Area2D = Area2D.new()
	arena.call_deferred("_attach_missile_core", deferred_core)
	await get_tree().process_frame
	_expect_true(not is_instance_valid(deferred_dew) or not deferred_dew.is_inside_tree(),
		"scheduled dew is blocked from entering the capture tree")
	_expect_true(not is_instance_valid(deferred_core) or not deferred_core.is_inside_tree(),
		"scheduled core is blocked from entering the capture tree")

	get_tree().current_scene = self
	arena.queue_free()
	await get_tree().process_frame
	if _failed > 0:
		printerr("hero-direction capture test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("hero-direction capture test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _expect_two_clean_frames(arena: Node, request: Dictionary, label: String) -> void:
	await get_tree().process_frame
	var first: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_equal(int(first.get("clean_frame_streak", -1)), 1, label + " first streak")
	_expect_true(not bool(first.get("ready", true)), label + " first ready rejected")
	await get_tree().process_frame
	var second: Dictionary = arena.call(
		"debug_store_capture_state", request) as Dictionary
	_expect_true(bool(second.get("ready", false)), label + " second ready")


func _settle_player_idle(player: Player) -> void:
	player.set_move_input(Vector2.ZERO)
	# Walk the real post-release slowdown. Even if called mid-dash, the first tick closes remaining
	# close dash time, then the next two ticks friction the speed below WALK_THRESHOLD.
	for i in 3:
		player.call("_physics_process", 0.20)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)
