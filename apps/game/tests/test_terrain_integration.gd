extends Node

## Confirm Arena cycle swap, shared y-sort, and loot moves as Room-external wiring.
##
## A Room-only test cannot catch placing beacons on the previous terrain then making a new room, or
## only `Rooms` y-sorting so Player always draws above structures.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const PAUSE_SCENE: PackedScene = preload("res://scenes/ui/pause_panel.tscn")
const POWER_ORB_SCENE: PackedScene = preload("res://scenes/items/power_orb.tscn")
const MISSILE_CORE_SCENE: PackedScene = preload("res://scenes/items/missile_core.tscn")
const MOON_DEW_SCENE: PackedScene = preload("res://scenes/items/moon_dew.tscn")
const MOON_BOLT_SCENE: PackedScene = preload("res://scenes/actors/moon_bolt.tscn")
const KEEPER: String = "res://resources/heroes/keeper.tres"
const WARDEN: String = "res://resources/heroes/warden.tres"
const KEEPER_IDLE: String = "res://assets/custom/actors/heroes/keeper/idle.png"
const FIELD_GUARDIAN: String = "res://resources/guardian_field.tres"
const WISP: String = "res://resources/wisp.tres"

var _failed: int = 0
var _checked: int = 0
var _bolt_player_hits: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return

	# The refund regression actually writes Vault, so only run it under the runner's temp user://.
	# Start from Keeper IAP-only ownership regardless of what a previous check saved.
	Vault.shards = 0
	Vault.ranks.clear()
	Vault.opened.clear()
	Vault.hero_sources.clear()
	Vault.chosen = ""
	var paid_heroes: Array[String] = [KEEPER]
	var keeper_source: String = Vault.hero_iap_source(KEEPER)
	_expect_true(
		Vault.grant_heroes(paid_heroes, keeper_source),
		"grants an individual Keeper hero for the refund regression")
	_expect_true(Vault.choose_hero(KEEPER), "selects Keeper for the refund regression")

	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_safe_ui_capture_guards(arena)
	await _test_pause_banner_suppression(arena)
	await _test_dialogue_and_result_back_input(arena)
	_freeze_existing(arena)

	_expect_true(arena.y_sort_enabled, "Arena shared y-sort")
	var rooms: Node2D = arena.get_node("Rooms") as Node2D
	_expect_true(rooms.y_sort_enabled, "Rooms nested y-sort")
	var player: Player = arena.get_node("Player") as Player
	var spirit: Node2D = arena.get_node("Spirit") as Node2D
	_expect_equal(str(arena.get("_run_hero_path")), KEEPER, "run-start Keeper path pinned")
	var run_hero: Hero = arena.get("_run_hero") as Hero
	_expect_true(run_hero != null, "run-start Keeper resource pinned")
	if run_hero != null:
		_expect_equal(run_hero.resource_path, KEEPER, "run-start Keeper resource path")
	_expect_equal(int(arena.get("_max_health")), 6, "Keeper starts with 6 hearts")
	_expect_equal(player.attack_damage, 13, "Keeper starting damage +25%")
	_expect_approx(player.speed, 81.6, "Keeper starting move speed -15%")
	_expect_approx(player.dash_cooldown_time, 1.495, "Keeper dash cooldown +30%")
	_expect_equal(_hero_sprite_source(player), KEEPER_IDLE, "run-start Keeper sheet")

	# A payment refund immediately reverts vault select to Warden, but the already-open run's look, start
	# relics, stats, and record hero must stay Keeper through the end.
	_expect_true(
		Vault.revoke_heroes(paid_heroes, keeper_source),
		"individual Keeper refund during combat")
	_expect_equal(Vault.hero_path(), WARDEN, "vault select is Warden after refund")
	arena.call("_recompute")
	_expect_equal(str(arena.get("_run_hero_path")), KEEPER, "run-hero path kept after refund")
	run_hero = arena.get("_run_hero") as Hero
	_expect_true(run_hero != null, "run-hero resource kept after refund")
	if run_hero != null:
		_expect_equal(run_hero.resource_path, KEEPER, "Keeper resource path kept after refund")
	_expect_equal(int(arena.get("_max_health")), 6, "Keeper hearts kept after refund")
	_expect_equal(player.attack_damage, 13, "Keeper damage kept after refund")
	_expect_approx(player.speed, 81.6, "Keeper move speed kept after refund")
	_expect_approx(player.dash_cooldown_time, 1.495, "Keeper dash kept after refund")
	_expect_equal(_hero_sprite_source(player), KEEPER_IDLE, "Keeper sheet kept after refund")
	_expect_equal(player.get_parent(), arena, "Player shared y-sort root")
	_expect_equal(spirit.get_parent(), arena, "Spirit shared y-sort root")
	await _test_guardian_capture_visual_guards(arena, player, spirit)

	# Change the cycle value first in the same order as the late-game preset, then make a new room. Inside this function
	# Place beacons after the new structure list exists.
	arena.set("_run_seed", 91_730_421)
	arena.set("_cycle", 5)
	arena.set("_zone_index", 0)
	arena.call("_change_cycle_world")
	await get_tree().process_frame
	var room: Room = arena.get("_room") as Room
	_expect_true(room != null, "late-game cycle new Room")
	_expect_true(room.y_sort_enabled, "Room nested y-sort")
	var ground: Sprite2D = room.get_node("Ground") as Sprite2D
	var decor: Node2D = room.get_node("Decor") as Node2D
	var structures: Node2D = room.get_node("Structures") as Node2D
	_expect_true(structures.y_sort_enabled, "Structures foot-pivot y-sort")
	_expect_equal(ground.z_index, -2, "Ground render layer -2")
	_expect_equal(decor.z_index, -1, "non-colliding Decor render layer -1")
	_expect_equal(structures.z_index, 0, "colliding Structures render layer 0")
	_expect_equal(player.z_index, 0, "Player and structures share a render layer")
	_expect_equal(spirit.z_index, 0, "Spirit and structures share a render layer")
	_expect_equal(
		int(room.kind.encounter),
		RoomKind.Encounter.CROSSFIRE,
		"applies cycle-5 start terrain")
	var beacon: Node2D = arena.get_node("BeaconWest") as Node2D
	_expect_true(beacon.visible, "first beacon of the new cycle is active")
	_expect_true(
		room.is_clear(beacon.position, 42.0, 10.0),
		"new-cycle beacon is outside the new terrain structures")

	# Rebuilding the same seed and terrain keeps obstacle coords. Deliberately put player and spirits
	# in the first obstacle center, then swap, and check they are immediately safe after the new room wires.
	var obstacle: Dictionary = room.terrain_obstacle_snapshot()[0]
	player.position = obstacle["at"]
	spirit.position = obstacle["at"]
	arena.call("_change_world", false, false)
	await get_tree().process_frame
	room = arena.get("_room") as Room
	_expect_true(room.is_clear(player.position, 4.0), "Player immediately safe after a room swap")
	var spirit_radius: float = float(spirit.call("terrain_radius"))
	_expect_true(
		room.is_clear(spirit.position, spirit_radius),
		"Spirit immediately safe after a room swap")

	# Fire a live enemy moonlight orb at the player beyond a structure. Player weapons
	# do not take terrain wiring so they pierce, but enemy shots must explode in front of the structure first.
	obstacle = room.terrain_obstacle_snapshot()[0]
	var bolt_center: Vector2 = obstacle["at"]
	var bolt_clearance: float = float(obstacle["radius"]) + 8.0 + 24.0
	player.position = bolt_center + Vector2(bolt_clearance, 4.0)
	var bolt: Node2D = MOON_BOLT_SCENE.instantiate() as Node2D
	bolt.position = bolt_center - Vector2(bolt_clearance, 0.0)
	bolt.set_direction(Vector2.RIGHT)
	bolt.set_target(player)
	bolt.set_terrain_room(room)
	bolt.set_hit_handler(Callable(self, "_record_bolt_player_hit"))
	arena.add_child(bolt)
	bolt.call("_physics_process", 1.0)
	_expect_equal(_bolt_player_hits, 0, "structure cover for Player vs enemy moon orbs")
	_expect_true(
		not bolt.is_physics_processing(),
		"enemy moonlight orb explodes immediately on structure collision")
	_expect_true(
		bolt.position.x < bolt_center.x,
		"enemy moonlight orb stops on the front of a structure")
	bolt.queue_free()

	# Move weapon loot outside the new room's structures, and clear heal dew when crossing the gate.
	# If dew follows too, heal stacked in the previous room becomes a mobile stash.
	obstacle = room.terrain_obstacle_snapshot()[0]
	var center: Vector2 = obstacle["at"]
	player.position = Room.MAP * 0.5
	var orb: Node2D = POWER_ORB_SCENE.instantiate() as Node2D
	var core: Node2D = MISSILE_CORE_SCENE.instantiate() as Node2D
	var dew: Node2D = MOON_DEW_SCENE.instantiate() as Node2D
	orb.position = center
	core.position = center
	dew.position = center
	arena.add_child(orb)
	arena.add_child(core)
	arena.add_child(dew)
	arena.call("_move_transition_pickups", Vector2.ZERO)
	await get_tree().process_frame
	_expect_true(room.is_clear(orb.position, 12.0), "transition relic-orb 12px safety")
	_expect_true(room.is_clear(core.position, 10.0), "transition missile-core 10px safety")
	_expect_true(not is_instance_valid(dew), "clears previous-terrain heal dew on a transition")

	# Even if kills pile up in one physics tick, the battlefield-wide cooldown reserves only one.
	arena.set("_health", 2)
	arena.set("_max_health", 5)
	arena.set("_dew_multiplier", 100.0)
	for i in 10:
		arena.call("_maybe_drop_dew", Vector2(320.0 + i, 320.0), false)
	_expect_equal(int(arena.get("_pending_dews")), 1, "only one regular dew is reserved in the same tick")
	await get_tree().process_frame
	_expect_equal(
		get_tree().get_node_count_in_group("moon_dews"), 1,
		"regular dew has a battlefield-wide cooldown")
	_expect_equal(
		int(arena.get("_dew_drop_cooldown")), 12,
		"12s cooldown after a regular dew drop")
	for live_dew in get_tree().get_nodes_in_group("moon_dews"):
		live_dew.queue_free()
	await get_tree().process_frame

	# A full-HP roll converted to score still spends the regular-dew clock. Otherwise, after a full-HP
	# taking damage right after that roll could also roll heal dew in the same tick.
	arena.set("_dew_drop_cooldown", 0.0)
	arena.set("_health", 5)
	var score_before_full_dew: int = int(arena.get("_kill_score"))
	arena.call("_maybe_drop_dew", Vector2(350.0, 325.0), false)
	_expect_equal(
		int(arena.get("_kill_score")), score_before_full_dew + 150,
		"a full-HP regular-dew roll converts to score")
	_expect_equal(
		int(arena.get("_dew_drop_cooldown")), 12,
		"full-HP score convert also spends the regular-dew 12s clock")
	arena.set("_health", 4)
	arena.call("_maybe_drop_dew", Vector2(355.0, 325.0), false)
	_expect_equal(int(arena.get("_pending_dews")), 0, "taking damage right after full HP does not roll another dew")

	# Dew pending to attach after a physics tick is also discarded on a room change so it is not a mobile stash.
	arena.set("_dew_drop_cooldown", 0.0)
	arena.call("_maybe_drop_dew", Vector2(360.0, 325.0), false)
	_expect_equal(int(arena.get("_pending_dews")), 1, "one regular dew pending before a map change")
	arena.set("_zone_serial", int(arena.get("_zone_serial")) + 1)
	await get_tree().process_frame
	_expect_equal(int(arena.get("_pending_dews")), 0, "pending dew count cleared after a map change")
	_expect_equal(
		get_tree().get_node_count_in_group("moon_dews"), 0,
		"pending dew discarded after a map change")

	# Guaranteed elite rescue skips the regular cooldown at one heart and no dew, but only once.
	arena.set("_dew_drop_cooldown", 12.0)
	arena.set("_health", 2)
	arena.set("_dew_multiplier", -1.0)
	arena.call("_maybe_drop_dew", Vector2(375.0, 330.0), true)
	_expect_equal(int(arena.get("_pending_dews")), 0, "no guaranteed elite rescue at two hearts")
	arena.set("_health", 0)
	arena.call("_maybe_drop_dew", Vector2(377.0, 330.0), true)
	_expect_equal(int(arena.get("_pending_dews")), 0, "no elite dew is reserved at death HP")
	arena.set("_health", 1)
	for i in 8:
		arena.call("_maybe_drop_dew", Vector2(380.0 + i, 330.0), true)
	await get_tree().process_frame
	_expect_equal(
		get_tree().get_node_count_in_group("moon_dews"), 1,
		"guarantees only one elite rescue dew at low HP")
	for live_dew in get_tree().get_nodes_in_group("moon_dews"):
		live_dew.queue_free()
	await get_tree().process_frame

	# Dew magnets only at the feet, stays put far away, and vanishes when the lifetime ends.
	var far_dew: Area2D = MOON_DEW_SCENE.instantiate() as Area2D
	far_dew.position = player.position + Vector2(50.0, 0.0)
	far_dew.set("target", player)
	arena.add_child(far_dew)
	var far_before: float = far_dew.position.distance_to(player.position)
	far_dew.call("_physics_process", 0.1)
	_expect_true(
		is_equal_approx(far_dew.position.distance_to(player.position), far_before),
		"heal dew is not magneted at 50px")
	far_dew.queue_free()
	var timed_dew: Area2D = MOON_DEW_SCENE.instantiate() as Area2D
	timed_dew.position = player.position + Vector2(16.0, 0.0)
	timed_dew.set("target", player)
	arena.add_child(timed_dew)
	var before_magnet: float = timed_dew.position.distance_to(player.position)
	timed_dew.call("_physics_process", 0.1)
	_expect_true(
		timed_dew.position.distance_to(player.position) < before_magnet,
		"heal dew magnets to the player only inside 22px")
	var expired: Array[int] = [0]
	timed_dew.expired.connect(func() -> void: expired[0] += 1)
	timed_dew.set("_left", 0.01)
	timed_dew.call("_process", 0.02)
	_expect_equal(expired[0], 1, "heal-dew lifetime expiry signal")
	await get_tree().create_timer(0.3).timeout
	_expect_true(not is_instance_valid(timed_dew), "expired heal dew removed")

	# Even a save with every permanent boon and relic stops at eight hearts.
	var arena_constants: Dictionary = arena.get_script().get_script_constant_map()
	_expect_equal(int(arena_constants.get(
		"MAX" + "_" + "HEALTH" + "_" + "LIMIT", 0)), 8,
		"max heart cap is 8")
	_expect_equal(int(arena_constants.get("CYCLE" + "_" + "HEAL", 0)), 1,
		"heals one heart after a guardian instead of a full heal")
	_expect_equal(
		int(arena_constants.get("DEW" + "_" + "DROP" + "_" + "COOLDOWN", 0)),
		12,
		"regular dew battlefield-wide cooldown is 12s")
	arena.set("_max_health", 8)
	arena.set("_health", 7)
	var tough: Relic = load("res://resources/relics/tough_life.tres") as Relic
	arena.call("_feed", tough)
	_expect_equal(int(arena.get("_max_health")), 8, "even Tough Life does not exceed the heart cap")
	_expect_equal(int(arena.get("_health")), 7, "no fake instant recover at the cap")

	# Beacon warmth that restored three hearts every three beacons, stacked with guardian rewards, would
	# almost resets. Heal once on the first beacon of a cycle, then once again next cycle.
	arena.set("_beacon_heal", 1)
	arena.set("_beacon_healed_cycle", 0)
	arena.set("_cycle", 5)
	arena.set("_max_health", 8)
	arena.set("_health", 4)
	_expect_true(bool(arena.call("_try_apply_beacon_heal")), "first-beacon heal of a cycle applied")
	_expect_equal(int(arena.get("_health")), 5, "first beacon of a cycle heals one heart")
	_expect_true(
		not bool(arena.call("_try_apply_beacon_heal")),
		"rejects extra-beacon heals in the same cycle")
	_expect_equal(int(arena.get("_health")), 5, "no extra-beacon heal in the same cycle")
	arena.set("_cycle", 6)
	_expect_true(bool(arena.call("_try_apply_beacon_heal")), "next-cycle beacon heal applied")
	_expect_equal(int(arena.get("_health")), 6, "first-beacon heal of the next cycle resumes")
	arena.set("_cycle", 7)
	arena.set("_health", 8)
	_expect_true(
		not bool(arena.call("_try_apply_beacon_heal")),
		"a full first beacon spends the chance with no heal")
	arena.set("_health", 7)
	_expect_true(
		not bool(arena.call("_try_apply_beacon_heal")),
		"cannot defer a heal onto the second beacon of the same cycle")
	_expect_equal(int(arena.get("_health")), 7, "first-beacon copy matches the actual heal timing")

	# Even after lighting the first beacon and gaining a relic on level-up, that cycle's second beacon
	# must not masquerade as the first. The first beacon spends the chance regardless of relics.
	arena.set("_cycle", 8)
	arena.set("_beacon_heal", 0)
	arena.set("_beacon_healed_cycle", 0)
	arena.set("_health", 4)
	_expect_true(
		not bool(arena.call("_try_apply_beacon_heal")),
		"a first beacon with no relic still spends the cycle chance")
	_expect_equal(int(arena.get("_beacon_healed_cycle")), 8,
		"records a first-beacon cycle with no relic")
	arena.set("_beacon_heal", 1)
	_expect_true(
		not bool(arena.call("_try_apply_beacon_heal")),
		"a relic gained after the first beacon is rejected for extra same-cycle healing")
	_expect_equal(int(arena.get("_health")), 4,
		"gaining a mid-run relic does not heal in the same cycle")
	arena.set("_cycle", 9)
	_expect_true(bool(arena.call("_try_apply_beacon_heal")),
		"a mid-run relic applies from the first beacon of the next cycle")
	_expect_equal(int(arena.get("_health")), 5,
		"first beacon of the next cycle heals one heart")

	await _test_continue_safety(arena, player)

	# Only boot capture freezes level progress so a slow CoreDevice round-trip still hits the Lv20 store scene.
	# There is no ArenaTools caller on the normal play path.
	arena.set("_level_progress", 4)
	arena.set("_to_next", 5)
	arena.call("debug_freeze_capture_progress")
	_expect_equal(int(arena.get("_level_progress")), 0, "device-capture level progress reset")
	_expect_equal(int(arena.get("_to_next")), 2_000_000_000, "device-capture level frozen")

	# Shake happens only in the camera world transform; structure local coords do not move.
	var camera: Camera2D = player.get_node("Cam") as Camera2D
	_expect_true(
		camera.zoom.is_equal_approx(Vector2.ONE * (4.0 / 3.0)),
		"world-camera zoom stays independent of HUD scale")
	arena.call("_shake", 4.0)
	arena.call("_tick_shake", 0.04)
	_expect_equal(room.position, Vector2.ZERO, "structure collision and art coordinates match during shake")
	_expect_true(camera.offset != Vector2.ZERO, "camera world shake still feels the same")
	arena.call("_stop_shake")
	_expect_equal(camera.offset, Vector2.ZERO, "camera returns after shake ends")

	# This test force-enables moon-ember awakening and can quit the process right after playing EventSfx.
	# can quit. Stop playback before freeing the scene so the audio server does not keep OGG playback
	# for one extra frame at exit, which is a test-only leak.
	for node in arena.find_children("*", "AudioStreamPlayer", true, false):
		var audio: AudioStreamPlayer = node as AudioStreamPlayer
		if audio != null:
			audio.stop()
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if _failed > 0:
		printerr("terrain-wiring test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("terrain-wiring test passed — ", _checked, " case(s)")
	get_tree().quit(0)


## Spending a coin at the death spot while surrounded must not let the same pack touch again immediately.
## Nearby regular spirits withdraw with no score; guardians and far spirits stay for progress.
func _test_continue_safety(arena: Node2D, player: Player) -> void:
	var spirits: Array = arena.get("_spirits") as Array
	for existing in spirits:
		if is_instance_valid(existing):
			existing.retreat()
	spirits.clear()
	arena.set("_guardian", null)
	player.position = Room.MAP * 0.5

	var near_spirit: Node2D = arena.call(
		"_summon", player.position + Vector2(24.0, 0.0), WISP)
	var guardian: Node2D = arena.call(
		"_summon", player.position + Vector2(0.0, 72.0), FIELD_GUARDIAN)
	var far_spirit: Node2D = arena.call(
		"_summon", player.position + Vector2(220.0, 0.0), WISP)
	arena.set("_guardian", guardian)
	await get_tree().process_frame

	# Guardian delayed damage that used to leak on the result screen, core counters left without a live core,
	# Pin the awakening aura that used to vanish after continue, in one live finish/continue.
	arena.set("_first_missile_core_collected", true)
	# While one stray core exists, make a regular core at the costlier power-4 threshold, then
	# Even if that stray state changes, result settlement must refund the originally deducted 5 exactly.
	for old_core in get_tree().get_nodes_in_group("missile_cores"):
		old_core.queue_free()
	await get_tree().process_frame
	arena.set("_missile_power", 3)
	arena.set("_regular_cores_outstanding", 0)
	arena.set("_regular_core_progress_escrow", 0)
	arena.set("_ejected_cores_outstanding", 1)
	arena.set("_missile_progress", MissileProgression.threshold(
		int(arena.call("_missile_threshold_power"))))
	arena.call("_try_drop_missile_core", player.global_position + Vector2(120.0, 0.0))
	await get_tree().process_frame
	_expect_equal(int(arena.get("_regular_cores_outstanding")), 1,
		"one regular core waiting before result")
	_expect_equal(int(arena.get("_regular_core_progress_escrow")), 5,
		"stores the progress the regular core actually deducted")
	arena.set("_ejected_cores_outstanding", 0)
	arena.call("_eject_missile_power")
	_expect_equal(int(arena.get("_ejected_cores_outstanding")), 1,
		"a lethal hit schedules one stray core")
	arena.call("_activate_moonfire", true, false)
	var aura: Node2D = player.get_node("MoonfireAura") as Node2D
	_expect_true(bool(aura.get("_active")), "moon-ember aura active before result")
	_expect_true(bool(aura.get("_locked")), "guardian moon-ember locked before result")

	var hostile: Node2D = Node2D.new()
	hostile.add_to_group("hostile_projectiles")
	arena.add_child(hostile)
	hostile.set_physics_process(true)
	var raid_queue: Array = arena.get("_raid_queue") as Array
	raid_queue.append({"kind": WISP})

	# Enter result on the same tick that queued the damage, so only the result-screen pause contract is measured.
	# Advancing a frame in the middle lets the guardian spend damage budget and changes the compare value.
	guardian.call("take_damage", 2_000_000_000, player.global_position)
	var guardian_health_at_result: int = int(guardian.get("_health"))
	var deferred_damage_at_result: float = float(
		guardian.get("_guardian_deferred_damage"))
	_expect_true(guardian_health_at_result > 0, "still alive immediately after guardian delayed damage")
	_expect_true(deferred_damage_at_result > 0.0, "reproduces queued guardian damage")

	arena.set("_health", 0)
	Vault.continue_coins = 1
	var score_before: int = int(arena.get("_kill_score"))
	arena.call("_finish", false)
	_expect_true(bool(arena.get("_over")), "enters an actual defeat result")
	_expect_true(not guardian.is_physics_processing(),
		"guardian delayed-damage physics ticks stop during result")
	_expect_equal(int(arena.get("_regular_cores_outstanding")), 0,
		"regular-core phantom counter cleared on result")
	_expect_equal(int(arena.get("_ejected_cores_outstanding")), 0,
		"stray-core phantom counter cleared on result")
	_expect_true(not bool(aura.get("_active")), "moon-ember aura hidden during result")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(int(guardian.get("_health")), guardian_health_at_result,
		"guardian delayed damage pauses while viewing results")
	_expect_approx(
		float(guardian.get("_guardian_deferred_damage")),
		deferred_damage_at_result,
		"queued guardian damage is kept while viewing results")

	_expect_true(bool(arena.call("continue_run")), "using a continue coin succeeds")
	_expect_equal(Vault.continue_coins, 0, "one continue coin deducted")
	_expect_equal(
		int(arena.get("_health")), int(arena.get("_max_health")),
		"continue fully restores health")
	_expect_true(float(arena.get("_invulnerable")) >= 3.0,
		"continue grants 3s i-frames")
	_expect_true(float(arena.get("_spawn_timer")) >= 4.0,
		"continue regular-spawn hush lasts 4s")
	_expect_true(float(arena.get("_raid_left")) >= 4.0,
		"continue raid hush lasts 4s")
	_expect_true(raid_queue.is_empty(), "continue clears a scheduled raid")
	_expect_true(
		not is_instance_valid(hostile) or hostile.is_queued_for_deletion(),
		"continue schedules immediate enemy-shot removal")
	_expect_true(
		not is_instance_valid(hostile) or not hostile.is_physics_processing(),
		"continue blocks same-tick hits from enemy shots")
	_expect_true(near_spirit not in spirits, "continue removes nearby regular spirits from the list")
	_expect_true(not bool(near_spirit.call("is_attackable")),
		"continue immediately makes nearby regular spirits non-attackable")
	_expect_true(guardian in spirits, "guardian progress kept after continue")
	_expect_true(guardian.is_physics_processing(), "continue resumes guardian physics ticks")
	_expect_true(far_spirit in spirits, "far-spirit progress kept after continue")
	_expect_equal(int(arena.get("_kill_score")), score_before,
		"continue shockwave grants no free kill score")
	_expect_equal(player.process_mode, Node.PROCESS_MODE_INHERIT,
		"continue resumes Player processing")
	_expect_true(player.is_physics_processing(), "continue resumes Player movement")
	_expect_true(float(player.get("_continue_burst_left")) > 0.0,
		"continue shows the moonlight shockwave")
	_expect_true(bool(aura.get("_active")), "continue restores the moon-ember aura")
	_expect_true(bool(aura.get("_locked")), "continue restores guardian moon-ember lock")
	var beacons: Array = arena.get("_beacons") as Array
	var active_beacon_index: int = int(arena.get("_zone_index"))
	for index in beacons.size():
		var reach: Area2D = (beacons[index] as Node2D).get_node("Reach") as Area2D
		_expect_equal(
			reach.monitoring,
			index == active_beacon_index and not bool(beacons[index].get("lit")),
			"only the current-terrain beacon is monitored after continue %d" % index)
	_expect_equal(int(arena.get("_ejected_cores_outstanding")), 0,
		"no stray-core phantom after continue")
	_expect_equal(int(arena.get("_regular_cores_outstanding")), 1,
		"earned regular cores are placed again after continue")
	_expect_equal(int(arena.get("_missile_progress")), 1,
		"regular-core progress delta is kept after continue even if the threshold changed")

	await get_tree().process_frame
	_expect_true(not is_instance_valid(hostile), "continue fully removes enemy shots on the next frame")
	_expect_equal(get_tree().get_nodes_in_group("missile_cores").size(), 1,
		"logical counters match the live core count after continue")

	guardian.set("_guardian_deferred_damage", 0.0)
	arena.call("_end_moonfire")
	arena.set("_guardian", null)
	for survivor in spirits:
		if is_instance_valid(survivor):
			survivor.retreat()
	spirits.clear()


func _test_dialogue_and_result_back_input(arena: Node2D) -> void:
	var dialogue: Control = arena.get_node("Ui/Dialogue") as Control
	var hero: Hero = load(KEEPER) as Hero
	var lines: Array[String] = ["first", "second"]
	dialogue.call("play", hero, lines)
	await get_tree().process_frame
	_expect_true(bool(dialogue.call("is_open")), "story dialogue opens")
	_expect_true(get_tree().paused, "combat paused during story dialogue")
	_expect_true(
		get_viewport().gui_get_focus_owner() == dialogue,
		"story dialogue keyboard/gamepad focus")
	arena.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_expect_true(bool(dialogue.call("is_open")), "Android back keeps required dialogue")
	_expect_true(not bool(arena.get("_leaving_for_title")),
		"one Android back does not abandon a run during dialogue")

	# Advance the first line with a real pad A. The first input during typing only completes,
	# Pin to a fully typed line and check that one accept advances to the next line.
	dialogue.set("_typing", false)
	var accept: InputEventJoypadButton = InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	Input.parse_input_event(accept)
	await get_tree().process_frame
	accept.pressed = false
	Input.parse_input_event(accept)
	await get_tree().process_frame
	_expect_equal(int(dialogue.get("_index")), 1, "pad accept advances to the next line")

	dialogue.set("_typing", false)
	accept.pressed = true
	Input.parse_input_event(accept)
	await get_tree().process_frame
	accept.pressed = false
	Input.parse_input_event(accept)
	await get_tree().create_timer(0.2).timeout
	_expect_true(not bool(dialogue.call("is_open")), "pad accept closes the last line")
	_expect_true(not get_tree().paused, "combat resumes after dialogue finishes")

	var ladder: Control = arena.get_node("Ui/Ladder") as Control
	ladder.visible = true
	arena.set("_over", true)
	arena.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_expect_true(not ladder.visible, "result record window closes on Android back")
	arena.set("_over", false)


func _record_bolt_player_hit(_at: Vector2) -> void:
	_bolt_player_hits += 1


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("terrain-wiring test aborted: user:// path is not isolated — ", user_root)
	return safe


func _hero_sprite_source(player: Player) -> String:
	var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return ""
	var texture: AtlasTexture = sprite.sprite_frames.get_frame_texture(
		&"idle_down", 0) as AtlasTexture
	if texture == null or texture.atlas == null:
		return ""
	return texture.atlas.resource_path


func _test_safe_ui_capture_guards(arena: Node2D) -> void:
	var state: Dictionary = arena.call("_debug_safe_ui_state") as Dictionary
	for field in [
		"safe_area_inside_viewport", "safe_ui_ready",
		"hud_left_inside_safe_area", "hud_right_inside_safe_area",
		"pause_button_inside_safe_area", "dash_inside_safe_area",
		"move_stick_inside_safe_area", "boss_inside_safe_area",
		"banner_inside_safe_area",
	]:
		_expect_true(bool(state.get(field, false)), "combat UI safe area " + field)
	for rect_field in [
		"viewport_rect", "safe_rect", "hud_left_rect", "hud_right_rect",
		"pause_button_rect", "dash_rect", "move_stick_rect",
		"boss_rect", "banner_rect",
	]:
		var values: Array = state.get(rect_field, []) as Array
		_expect_equal(values.size(), 4, "combat UI " + rect_field + " coordinate proof")

	# If the right HUD shrinks when kill/time digits change, device capture
	# before/after is judged as a different screen, and live play also sees HUD jump sideways.
	var hud: Control = arena.get_node("Ui/Hud") as Control
	var right_panel: Control = hud.get_node("RightPanel") as Control
	_expect_equal(
		right_panel.custom_minimum_size, Vector2(320.0, 26.0),
		"right HUD pinned minimum size")
	var right_before: Rect2 = right_panel.get_global_rect()
	hud.call("set_kills", 999_999)
	hud.call("set_survived", 35_999.0)
	await get_tree().process_frame
	_expect_equal(
		right_panel.get_global_rect(), right_before,
		"right HUD position and size stay fixed even when kill/time digits change")

	# The max-missile scene pins the live core-complete copy opaque at 1×.
	# Do not dress an ad screen by pasting awakening copy onto a preset whose moon-ember is off.
	var missile_power_before: int = int(arena.get("_missile_power"))
	arena.set("_missile_power", MissileProgression.MAX_POWER)
	arena.call("debug_prepare_store_capture", {"kind": "moonlight_barrage"})
	var banner: Dictionary = hud.call("debug_capture_banner_snapshot") as Dictionary
	var banner_label: Label = hud.get_node("Banner") as Label
	_expect_true(bool(banner.get("locked", false)), "max-missile capture banner locked")
	_expect_true(bool(banner.get("visible", false)), "max-missile capture banner opaque")
	_expect_equal(str(banner.get("text", "")), tr("MISSILE_COMPLETE") % [
		MissileProgression.MAX_POWER, MissileProgression.MAX_POWER],
		"max-missile capture actual volley-complete copy")
	_expect_equal(banner_label.scale, Vector2.ONE, "max-missile capture banner at 1×")
	_expect_approx(banner_label.modulate.a, 1.0, "max-missile capture banner alpha")
	hud.call("debug_unlock_capture_banner")
	arena.set("_missile_power", missile_power_before)

	var dash: Control = arena.get_node("Ui/Dash") as Control
	var original_position: Vector2 = dash.position
	dash.position += Vector2(5000.0, 0.0)
	state = arena.call("_debug_safe_ui_state") as Dictionary
	_expect_true(
		not bool(state.get("dash_inside_safe_area", true)),
		"rejects a dash button outside the gesture safe area")
	_expect_true(
		not bool(state.get("safe_ui_ready", true)),
		"rejects combat-UI ready outside the gesture safe area")
	dash.position = original_position
	state = arena.call("_debug_safe_ui_state") as Dictionary
	_expect_true(
		bool(state.get("safe_ui_ready", false)),
		"combat UI safe-area counterexample then restore state")

	var full: Rect2 = arena.get_viewport().get_visible_rect()
	var safe: Rect2 = full.grow(-12.0)
	var pause: Control = arena.get_node("Ui/Pause") as Control
	Screen.apply_safe_content(pause, safe, full)
	_expect_true(
		pause.get_global_rect().is_equal_approx(full),
		"pause modal root stays fullscreen")
	var overlay: Control = pause.get_node("Overlay") as Control
	_expect_true(
		overlay.get_global_rect().is_equal_approx(full),
		"pause dim Overlay stays fullscreen")
	for path in ["Button", "Overlay/Title", "Overlay/Resume", "Overlay/Retry", "Overlay/Settings"]:
		var content: Control = pause.get_node(path) as Control
		_expect_true(
			_rect_fully_inside(content.get_global_rect(), safe),
			"pause content safe area " + path)
	arena.call("_recenter")


func _test_pause_banner_suppression(arena: Node2D) -> void:
	var hud: Control = arena.get_node("Ui/Hud") as Control
	var banner: Label = hud.get_node("Banner") as Label
	var pause: Control = arena.get_node("Ui/Pause") as Control
	hud.call("announce", "pause banner regression", Color.WHITE)
	_expect_true(banner.visible, "center notice shown before pause")
	await get_tree().create_timer(0.3).timeout
	pause.call("request_pause")
	_expect_true(get_tree().paused, "pause pauses the tree")
	_expect_true(not banner.visible, "center notice hidden after the pause title")
	pause.call("_resume")
	_expect_true(not get_tree().paused, "pause resumed")
	_expect_true(banner.visible, "center-notice remaining time restored after resume")
	await get_tree().create_timer(2.1).timeout
	_expect_true(not banner.visible, "remaining notice Tween ends after resume")
	_expect_approx(banner.modulate.a, 0.0, "notice alpha ends after resume")

	# A banner that was already hidden must not reappear from pause/resume alone.
	pause.call("request_pause")
	_expect_true(not banner.visible, "hidden banner stays during pause")
	pause.call("_resume")
	_expect_true(not get_tree().paused, "tree unpauses after resume with a hidden banner")
	_expect_true(not banner.visible, "hidden banner is not restored after resume")

	# Restart/title leave the scene. During the one frame waiting for audio release,
	# Unlike live Resume, do not restore hide state so the previous notice does not flash.
	var detached_pause: Control = PAUSE_SCENE.instantiate() as Control
	add_child(detached_pause)
	await get_tree().process_frame
	detached_pause.connect(
		"pause_changed", Callable(hud, "set_banner_suppressed"))
	for method in ["_on_retry", "_on_to_title"]:
		hud.call("announce", "leave pause regression", Color.WHITE)
		detached_pause.call("request_pause")
		_expect_true(not banner.visible, "%s hides center notice beforehand" % method)
		detached_pause.call(method)
		_expect_true(not get_tree().paused, "%s tree unpaused" % method)
		_expect_true(not banner.visible, "%s notice not restored before leaving the scene" % method)
		hud.call("set_banner_suppressed", false)
	detached_pause.queue_free()
	await get_tree().process_frame


func _rect_fully_inside(rect: Rect2, boundary: Rect2) -> bool:
	const EPSILON: float = 0.01
	return rect.has_area() \
		and rect.position.x >= boundary.position.x - EPSILON \
		and rect.position.y >= boundary.position.y - EPSILON \
		and rect.end.x <= boundary.end.x + EPSILON \
		and rect.end.y <= boundary.end.y + EPSILON


func _canvas_delta_to_world(canvas_delta: Vector2) -> Vector2:
	var inverse_canvas: Transform2D = get_viewport().get_canvas_transform() \
		.affine_inverse()
	return inverse_canvas * canvas_delta - inverse_canvas * Vector2.ZERO


func _test_guardian_capture_visual_guards(
		arena: Node2D, player: Player, spirit: Node2D) -> void:
	var original_kind: SpiritKind = spirit.get("kind") as SpiritKind
	var original_position: Vector2 = spirit.position
	var sprite: AnimatedSprite2D = spirit.get_node("Sprite") as AnimatedSprite2D
	var original_sprite_visible: bool = sprite.visible
	var original_sprite_scale: Vector2 = sprite.scale
	var field_kind: SpiritKind = load(FIELD_GUARDIAN) as SpiritKind
	_expect_true(field_kind != null, "04 capture field-guardian resource")
	if field_kind == null:
		return

	# Duplicate like the live spawn code. Godot clears duplicate resource_path, so
	# unless the original path is bound on the guardian node separately, capture proof regresses.
	var duplicated_field_kind: SpiritKind = field_kind.duplicate()
	_expect_equal(
		duplicated_field_kind.resource_path,
		"",
		"live premise that a duplicated guardian resource path is empty")
	spirit.set("kind", duplicated_field_kind)
	spirit.call("_apply_kind")
	spirit.set("_materialized", true)
	spirit.position = player.position + Vector2(96.0, 0.0)
	spirit.visible = true
	spirit.modulate.a = 1.0
	sprite.visible = true
	sprite.scale = Vector2.ONE
	arena.set("_guardian", spirit)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect_equal(
		arena.call("_debug_guardian_kind_source_path"),
		"",
		"rejects a guardian with no source metadata")
	var capture_state: Dictionary = arena.call(
		"debug_store_capture_state", {"kind": "field_guardian"}) as Dictionary
	_expect_equal(
		capture_state.get("guardian_kind_path"),
		"",
		"capture state also does not dress a sourceless guardian as field")
	spirit.set_meta(&"moonlit_guardian_kind_source_path", "res://resources/guardian_forest.tres")
	_expect_equal(
		arena.call("_debug_guardian_kind_source_path"),
		"res://resources/guardian_forest.tres",
		"exposes a mis-bundled guardian source as-is")
	capture_state = arena.call(
		"debug_store_capture_state", {"kind": "field_guardian"}) as Dictionary
	_expect_equal(
		capture_state.get("guardian_kind_path"),
		"res://resources/guardian_forest.tres",
		"capture state does not hide a mis-bundled forest-guardian source")
	spirit.set_meta(&"moonlit_guardian_kind_source_path", FIELD_GUARDIAN)
	_expect_equal(
		arena.call("_debug_guardian_kind_source_path"),
		FIELD_GUARDIAN,
		"field source of the actual guardian node")
	capture_state = arena.call(
		"debug_store_capture_state", {"kind": "field_guardian"}) as Dictionary
	_expect_equal(
		capture_state.get("guardian_kind_path"),
		FIELD_GUARDIAN,
		"capture state exports the actual field source")

	# Pin the live spawn name and tactic copy fully opaque. The guardian
	# banner must not be captured mid pop-Tween or dressed with arbitrary copy.
	arena.call("debug_prepare_store_capture", {"kind": "field_guardian"})
	var hud: Control = arena.get_node("Ui/Hud") as Control
	var guardian_banner: Dictionary = hud.call(
		"debug_capture_banner_snapshot") as Dictionary
	var expected_guardian_banner: String = tr("GUARDIAN_INTRO") % [
		tr(duplicated_field_kind.display_name),
		tr(duplicated_field_kind.guardian_rule),
	]
	_expect_true(bool(guardian_banner.get("locked", false)),
		"field-guardian capture banner locked")
	_expect_true(bool(guardian_banner.get("visible", false)),
		"field-guardian capture banner opaque")
	_expect_equal(str(guardian_banner.get("text", "")), expected_guardian_banner,
		"field-guardian capture actual name and tactic copy")
	var guardian_banner_label: Label = hud.get_node("Banner") as Label
	_expect_equal(guardian_banner_label.scale, Vector2.ONE,
		"field-guardian capture banner at 1×")

	var state: Dictionary = arena.call(
		"_debug_guardian_capture_visual_state") as Dictionary
	for field in [
		"guardian_visual_node_present",
		"guardian_root_visible_in_tree",
		"guardian_sprite_visible_in_tree",
		"guardian_root_opaque",
		"guardian_sprite_opaque",
		"guardian_frame_texture_present",
		"guardian_frame_texture_matches_field",
		"guardian_draw_rect_positive",
		"guardian_draw_rect_intersects_viewport",
		"guardian_draw_rect_fully_inside_viewport",
		"guardian_draw_rect_inside_focus",
		"guardian_draw_center_inside_focus",
		"guardian_separated_from_player",
		"guardian_central_composition",
		"guardian_visual_ready",
	]:
		_expect_true(bool(state.get(field, false)), "04 field guardian live " + field)
	_expect_equal(
		state.get("guardian_visual_node_class"),
		"AnimatedSprite2D",
		"04 field guardian actual AnimatedSprite2D")
	_expect_equal(
		state.get("guardian_frame_texture_path"),
		"res://assets/custom/actors/guardians/field.png",
		"04 field guardian current actual frame source")
	_expect_equal(
		(state.get("guardian_draw_rect", []) as Array).size(),
		4,
		"04 field guardian actual canvas-rect proof")
	_expect_equal(
		(state.get("guardian_focus_rect", []) as Array).size(),
		4,
		"04 field guardian center-focus rect proof")
	_expect_true(
		float(state.get("guardian_player_canvas_distance", 0.0)) >= 72.0,
		"04 field guardian and player silhouettes separated")

	# After the first ready, the probe does not call prepare again. The watch API must restore both the guardian
	# Restore both the off-screen push and new ally projectiles before the next sample.
	var friendly_projectile: Node2D = Node2D.new()
	friendly_projectile.add_to_group("friendly_projectiles")
	arena.add_child(friendly_projectile)
	spirit.position += Vector2(5000.0, 0.0)
	var clearing_state: Dictionary = arena.call(
		"debug_store_capture_state", {"kind": "field_guardian"}) as Dictionary
	_expect_true(
		bool(clearing_state.get("guardian_capture_active", false)),
		"field-guardian capture watch window active")
	_expect_true(
		bool(clearing_state.get("guardian_central_composition", false)),
		"center framing restored on every field-guardian capture watch")
	_expect_equal(
		int(clearing_state.get("friendly_projectile_count", -1)),
		1,
		"queue_free-scheduled frame is proven while ally projectiles still remain")
	_expect_true(
		friendly_projectile.is_queued_for_deletion(),
		"field-guardian capture schedules removal of existing ally projectiles")
	_expect_true(
		not bool(clearing_state.get("ready", true)),
		"rejects capture proof before ally projectiles actually leave the tree")
	await get_tree().process_frame
	capture_state = arena.call(
		"debug_store_capture_state", {"kind": "field_guardian"}) as Dictionary
	_expect_equal(
		int(capture_state.get("friendly_projectile_count", -1)),
		0,
		"ally projectiles are actually gone on the next frame")

	var original_root_modulate: Color = spirit.modulate
	spirit.modulate.a = 0.0
	state = arena.call("_debug_guardian_capture_visual_state") as Dictionary
	_expect_equal(
		float(state.get("guardian_root_effective_alpha", 1.0)),
		0.0,
		"reproduces the root-alpha-0 guardian counterexample")
	_expect_true(
		not bool(state.get("guardian_root_opaque", true)),
		"rejects opaque judgement for a root-alpha-0 guardian")
	_expect_true(
		not bool(state.get("guardian_sprite_opaque", true)),
		"root alpha 0 also rejects child-Sprite opaque judgement")
	_expect_true(
		not bool(state.get("guardian_visual_ready", true)),
		"rejects ready for a root-alpha-0 guardian")
	spirit.modulate = original_root_modulate

	sprite.visible = false
	state = arena.call("_debug_guardian_capture_visual_state") as Dictionary
	_expect_true(
		not bool(state.get("guardian_sprite_visible_in_tree", true)),
		"reproduces the hidden-guardian Sprite counterexample")
	_expect_true(
		not bool(state.get("guardian_visual_ready", true)),
		"rejects ready for a hidden guardian Sprite")
	sprite.visible = true

	var original_frames: SpriteFrames = sprite.sprite_frames
	var original_animation: StringName = sprite.animation
	var original_frame: int = sprite.frame
	var swapped_frames: SpriteFrames = SpriteFrames.new()
	swapped_frames.add_frame(
		&"default",
		load("res://assets/custom/actors/spirits/wisp.png") as Texture2D)
	sprite.sprite_frames = swapped_frames
	sprite.play(&"default")
	state = arena.call("_debug_guardian_capture_visual_state") as Dictionary
	_expect_true(
		bool(state.get("guardian_frame_texture_present", false)),
		"reproduces the counterexample of swapping another live spirit frame")
	_expect_equal(
		state.get("guardian_frame_texture_path"),
		"res://assets/custom/actors/spirits/wisp.png",
		"swapped actual spirit-frame source is exposed")
	_expect_true(
		not bool(state.get("guardian_frame_texture_matches_field", true)),
		"rejects a live frame resource that is not the field guardian")
	_expect_true(
		not bool(state.get("guardian_visual_ready", true)),
		"rejects ready after swapping another live spirit frame")

	sprite.sprite_frames = SpriteFrames.new()
	sprite.play(&"default")
	state = arena.call("_debug_guardian_capture_visual_state") as Dictionary
	_expect_true(
		not bool(state.get("guardian_frame_texture_present", true)),
		"reproduces the frameless-guardian AnimatedSprite counterexample")
	_expect_true(
		not bool(state.get("guardian_draw_rect_positive", true)),
		"rejects a frameless guardian draw region")
	_expect_true(
		not bool(state.get("guardian_visual_ready", true)),
		"rejects ready for a frameless guardian")
	sprite.sprite_frames = original_frames
	sprite.play(original_animation)
	sprite.frame = original_frame

	# Node2D internally corrects an exact 0 scale, so confirm the positive draw-region gate
	# with an essentially empty transform.
	sprite.scale = Vector2(0.001, 0.001)
	state = arena.call("_debug_guardian_capture_visual_state") as Dictionary
	_expect_true(
		not bool(state.get("guardian_draw_rect_positive", true)),
		"rejects sub-1px guardian live draw region")
	_expect_true(
		not bool(state.get("guardian_visual_ready", true)),
		"rejects sub-1px guardian ready")
	sprite.scale = Vector2.ONE

	# Even with the whole body visible, sticking to the left used to pass the old intersection check.
	# The center-focus contract explicitly rejects this framing.
	var frame_texture: Texture2D = sprite.sprite_frames.get_frame_texture(
		sprite.animation, sprite.frame)
	var central_position: Vector2 = spirit.position
	var central_canvas_rect: Rect2 = arena.call(
		"_debug_canvas_rect", sprite, arena.call(
			"_debug_animated_sprite_draw_rect", sprite, frame_texture)) as Rect2
	spirit.position += _canvas_delta_to_world(Vector2(
		54.0 - central_canvas_rect.get_center().x, 0.0))
	state = arena.call("_debug_guardian_capture_visual_state") as Dictionary
	_expect_true(
		bool(state.get("guardian_draw_rect_intersects_viewport", false)),
		"a guardian body on the left of the screen still passes the existing intersection check")
	_expect_true(
		not bool(state.get("guardian_draw_rect_inside_focus", true)),
		"rejects center focus for a left-of-screen guardian")
	_expect_true(
		not bool(state.get("guardian_central_composition", true)),
		"rejects center framing for a left-of-screen guardian")
	_expect_true(
		not bool(state.get("guardian_visual_ready", true)),
		"rejects ready for a left-of-screen guardian")
	spirit.position = central_position

	# Overlap the live frame on the right of the screen by less than 1px. Plain has_area() would
	# would also pass an essentially invisible boss, so require a meaningful visible area.
	var local_draw_rect: Rect2 = arena.call(
		"_debug_animated_sprite_draw_rect", sprite, frame_texture) as Rect2
	var canvas_draw_rect: Rect2 = arena.call(
		"_debug_canvas_rect", sprite, local_draw_rect) as Rect2
	var viewport_rect: Rect2 = arena.get_viewport().get_visible_rect()
	spirit.position += _canvas_delta_to_world(Vector2(
		viewport_rect.end.x - canvas_draw_rect.position.x - 0.5, 0.0))
	state = arena.call("_debug_guardian_capture_visual_state") as Dictionary
	_expect_true(
		bool(state.get("guardian_draw_rect_positive", false)),
		"edge sliver still has positive guardian source size")
	_expect_true(
		not bool(state.get("guardian_draw_rect_intersects_viewport", true)),
		"does not accept a sub-1px edge sliver as a visible guardian")
	_expect_true(
		not bool(state.get("guardian_visual_ready", true)),
		"rejects edge-sliver guardian ready")

	spirit.position = player.position + Vector2(96.0, 0.0)
	spirit.position += Vector2(5000.0, 0.0)
	state = arena.call("_debug_guardian_capture_visual_state") as Dictionary
	_expect_true(
		bool(state.get("guardian_draw_rect_positive", false)),
		"guardian live size is still positive even off screen")
	_expect_true(
		not bool(state.get("guardian_draw_rect_intersects_viewport", true)),
		"rejects an off-screen guardian viewport intersection")
	_expect_true(
		not bool(state.get("guardian_visual_ready", true)),
		"rejects off-screen guardian ready")

	arena.set("_guardian", null)
	arena.set("_debug_guardian_capture_active", false)
	spirit.remove_meta(&"moonlit_guardian_kind_source_path")
	spirit.set("kind", original_kind)
	spirit.call("_apply_kind")
	spirit.position = original_position
	spirit.visible = true
	sprite.visible = original_sprite_visible
	sprite.scale = original_sprite_scale
	hud.call("debug_unlock_capture_banner")


func _freeze_existing(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze_existing(child)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _expect_approx(actual: float, expected: float, label: String) -> void:
	_checked += 1
	if is_equal_approx(actual, expected):
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)
