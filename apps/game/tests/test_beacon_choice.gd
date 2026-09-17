extends Node

## 2.1.0 beacon-choice state regression.
##
## After splitting charge-complete from live ignite, awaiting choice, overcharge, and run end
## must not overlap. Use the live Beacon scene and pin signal, monitoring, color, and recharge
## one state transition at a time.

const BEACON_SCENE: PackedScene = preload("res://scenes/objectives/beacon.tscn")
const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const CHARGE_SECONDS: float = 1.3
const OVERCHARGE_LIGHT_COLOR: Color = Color(0.78, 0.55, 1.0, 1.0)
const OVERCHARGE_GLOW_COLOR: Color = Color(0.72, 0.36, 1.0, 1.0)

var _failed: int = 0
var _checked: int = 0
var _lit_events: Array[bool] = []
var _completed_events: int = 0
var _charge_events: Array[float] = []
var _body: Node2D


func _ready() -> void:
	# The test coroutine must keep running even if RunChoicePanel pauses the game tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_run.call_deferred()


func _run() -> void:
	_body = Node2D.new()
	add_child(_body)

	await _test_charge_waits_for_choice()
	await _test_safe_ignite_is_one_shot()
	await _test_overcharge_begin_and_resolve()
	await _test_reset_cleans_every_state()
	await _test_freeze_and_thaw_discard_progress()
	await _test_inactive_beacon_discards_pending_choice()
	await _test_inactive_beacon_discards_overcharge()
	await _test_arena_choice_and_overcharge_flow()

	if _failed > 0:
		printerr("beacon-choice state test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("beacon-choice state test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _test_charge_waits_for_choice() -> void:
	var beacon: Node2D = await _spawn_unlit_beacon()
	_complete_charge(beacon)
	await get_tree().process_frame

	_expect_false(bool(beacon.get("lit")), "charge complete alone does not light the fire")
	_expect_true(bool(beacon.call("is_awaiting_choice")), "awaits choice after charge completes")
	_expect_false(bool(beacon.call("is_overcharging")), "not overcharging before the choice")
	_expect_approx(float(beacon.call("get_charge")), 1.0, 0.0001, "charge stays at 100% while awaiting choice")
	_expect_equal(_completed_events, 1, "charge_completed emitted once")
	_expect_equal(_lit_events.size(), 0, "lit_changed not emitted before the choice")
	_expect_false(beacon.is_processing(), "own clock stops after charge completes")
	_expect_false(_monitoring(beacon), "monitoring stopped while awaiting choice")

	for _i in 3:
		await get_tree().process_frame
	_expect_equal(_completed_events, 1, "no second complete signal while awaiting choice")
	_expect_false(bool(beacon.call("resolve_overcharge")), "cannot resolve before overcharge")
	await _free_beacon(beacon)


func _test_safe_ignite_is_one_shot() -> void:
	var beacon: Node2D = await _spawn_unlit_beacon()
	_complete_charge(beacon)
	beacon.call("ignite")

	_expect_true(bool(beacon.get("lit")), "stable ignite switches to lit immediately")
	_expect_false(bool(beacon.call("is_awaiting_choice")), "awaiting choice cleared after stable ignite")
	_expect_false(bool(beacon.call("is_overcharging")), "not overcharging after stable ignite")
	_expect_equal(_lit_events, [true], "stable ignite emits lit_changed exactly once")
	_expect_approx(float(beacon.call("get_charge")), 0.0, 0.0001, "charge ring hidden after ignite")

	beacon.call("ignite")
	await get_tree().process_frame
	_expect_equal(_lit_events, [true], "re-igniting an already-lit beacon emits no signal")
	await _free_beacon(beacon, 0.5)


func _test_overcharge_begin_and_resolve() -> void:
	var beacon: Node2D = await _spawn_unlit_beacon()
	var normal_light: Color = _light(beacon).color
	var normal_glow: Color = _glow(beacon).modulate
	_complete_charge(beacon)

	_expect_true(bool(beacon.call("begin_overcharge")), "overcharge starts from awaiting choice")
	_expect_false(bool(beacon.call("begin_overcharge")), "starting overcharge succeeds only once")
	await get_tree().process_frame
	_expect_false(bool(beacon.get("lit")), "still unlit while defending overcharge")
	_expect_false(bool(beacon.call("is_awaiting_choice")), "awaiting choice cleared after overcharge starts")
	_expect_true(bool(beacon.call("is_overcharging")), "overcharge state shown")
	_expect_approx(float(beacon.call("get_charge")), 1.0, 0.0001, "charge stays at 100% during overcharge")
	_expect_false(beacon.is_processing(), "beacon's own clock stops during overcharge")
	_expect_false(_monitoring(beacon), "normal monitoring stopped during overcharge")
	_expect_color(_light(beacon).color, OVERCHARGE_LIGHT_COLOR, "overcharge violet light")
	_expect_color(_glow(beacon).modulate, OVERCHARGE_GLOW_COLOR, "overcharge violet flame")
	_expect_equal(_lit_events.size(), 0, "starting overcharge alone does not emit ignite")

	_expect_true(bool(beacon.call("resolve_overcharge")), "overcharge resolve succeeds")
	_expect_false(bool(beacon.call("resolve_overcharge")), "resolving overcharge succeeds only once")
	_expect_true(bool(beacon.get("lit")), "beacon ignites after resolving overcharge")
	_expect_false(bool(beacon.call("is_overcharging")), "overcharge state cleared after resolve")
	_expect_equal(_lit_events, [true], "resolving overcharge also emits lit_changed exactly once")
	_expect_color(_light(beacon).color, normal_light, "chosen light color restored after resolve")
	_expect_color(_glow(beacon).modulate, normal_glow, "chosen flame color restored after resolve")
	await _free_beacon(beacon, 0.5)


func _test_reset_cleans_every_state() -> void:
	var beacon: Node2D = await _spawn_unlit_beacon()
	var normal_light: Color = _light(beacon).color
	_complete_charge(beacon)
	beacon.call("begin_overcharge")
	beacon.call("reset")

	_expect_false(bool(beacon.get("lit")), "unlit after reset")
	_expect_false(bool(beacon.call("is_awaiting_choice")), "awaiting choice cleared after reset")
	_expect_false(bool(beacon.call("is_overcharging")), "overcharge cleared after reset")
	_expect_approx(float(beacon.call("get_charge")), 0.0, 0.0001, "charge 0 after reset")
	_expect_true(_monitoring(beacon), "monitoring resumes after reset")
	_expect_false(beacon.is_processing(), "clock stopped before visit after reset")
	_expect_color(_light(beacon).color, normal_light, "chosen light color restored after reset")
	_expect_true(_charge_events.has(0.0), "reset emits a charge-ring 0 signal")

	_clear_events()
	_complete_charge(beacon)
	_expect_equal(_completed_events, 1, "can charge from scratch after reset")
	_expect_false(bool(beacon.get("lit")), "still unlit before the choice even after recharging")
	await _free_beacon(beacon)


func _test_freeze_and_thaw_discard_progress() -> void:
	var beacon: Node2D = await _spawn_unlit_beacon()
	var normal_light: Color = _light(beacon).color
	_complete_charge(beacon)
	beacon.call("begin_overcharge")
	beacon.call("freeze")

	_expect_false(bool(beacon.call("is_awaiting_choice")), "awaiting choice cleared after freeze")
	_expect_false(bool(beacon.call("is_overcharging")), "overcharge cleared after freeze")
	_expect_approx(float(beacon.call("get_charge")), 0.0, 0.0001, "charge 0 after freeze")
	_expect_false(_monitoring(beacon), "monitoring stopped during freeze")
	_expect_false(beacon.is_processing(), "clock stopped during freeze")
	_expect_color(_light(beacon).color, normal_light, "chosen light color restored after freeze")

	beacon.call("thaw")
	_expect_true(_monitoring(beacon), "unlit beacon monitoring resumes after thaw")
	_expect_false(beacon.is_processing(), "clock stopped before visit after thaw")
	_clear_events()
	_complete_charge(beacon)
	_expect_equal(_completed_events, 1, "new charge completes after thaw")
	await _free_beacon(beacon)


func _test_inactive_beacon_discards_pending_choice() -> void:
	var beacon: Node2D = await _spawn_unlit_beacon()
	_complete_charge(beacon)
	beacon.call("set_active", false)
	await get_tree().process_frame

	_expect_false(beacon.visible, "inactive beacon hidden")
	_expect_false(bool(beacon.call("is_awaiting_choice")), "hiding clears awaiting choice")
	_expect_false(bool(beacon.call("is_overcharging")), "hidden beacon is not overcharging")
	_expect_approx(float(beacon.call("get_charge")), 0.0, 0.0001, "hiding sets charge to 0")
	_expect_false(_monitoring(beacon), "inactive beacon monitoring stopped")
	_expect_false(beacon.is_processing(), "inactive beacon clock stopped")

	beacon.call("set_active", true)
	await get_tree().process_frame
	_expect_true(beacon.visible, "reactivated beacon shown")
	_expect_true(_monitoring(beacon), "unlit beacon monitoring resumes after reactivation")
	_clear_events()
	_complete_charge(beacon)
	_expect_equal(_completed_events, 1, "new choice requested after reactivation")
	await _free_beacon(beacon)


func _test_inactive_beacon_discards_overcharge() -> void:
	var beacon: Node2D = await _spawn_unlit_beacon()
	var normal_light: Color = _light(beacon).color
	_complete_charge(beacon)
	beacon.call("begin_overcharge")
	beacon.call("set_active", false)
	await get_tree().process_frame

	_expect_false(bool(beacon.call("is_overcharging")), "hiding an overcharging beacon clears the state")
	_expect_false(bool(beacon.call("is_awaiting_choice")), "hiding an overcharging beacon still leaves no await")
	_expect_approx(float(beacon.call("get_charge")), 0.0, 0.0001, "hidden overcharging beacon charge 0")
	_expect_color(_light(beacon).color, normal_light, "hidden overcharging beacon color restored")
	_expect_false(_monitoring(beacon), "hidden overcharging beacon monitoring stopped")
	await _free_beacon(beacon)


func _test_arena_choice_and_overcharge_flow() -> void:
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame

	# Freeze the combat clock and drive only the choice state. If a spirit's accidental collision or
	# If spawn spacing can change the result, it is not a state regression.
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.set("_shielded", true)
	var player: Node2D = arena.get_node("Player") as Node2D
	player.set_physics_process(false)
	for spirit in arena.get_tree().get_nodes_in_group(&"spirits"):
		(spirit as Node).set_physics_process(false)

	var panel: Control = arena.get_node("Ui/RunChoice") as Control
	_expect_true(panel is RunChoicePanel, "Arena hosts a real RunChoicePanel")
	_expect_true(panel.has_signal(&"chosen"), "Arena choice panel chosen signal")
	_expect_true(
		panel.get_signal_connection_list(&"chosen").size() >= 1,
		"Arena wires chosen into the state transition")

	var beacons: Array = arena.get("_beacons") as Array
	var active_index: int = clampi(int(arena.get("_zone_index")), 0, beacons.size() - 1)
	var beacon: Node2D = beacons[active_index] as Node2D
	for i in beacons.size():
		(beacons[i] as Node2D).call("set_active", i == active_index)
	beacon.call("reset")
	beacon.call("set_active", true)
	_prepare_arena_choice(arena)
	_clear_events()
	beacon.connect(&"lit_changed", _on_lit_changed)

	# Wire the live charge_completed signal → Arena → panel → left button.
	_complete_charge(beacon)
	await _settle_choice_panel(panel)
	_expect_true(panel.visible, "Arena choice panel opens when fully charged")
	_expect_true(get_tree().paused, "game tree paused during beacon choice")
	_expect_true(arena.get("_pending_beacon_choice") == beacon, "awaiting-choice beacon kept")
	_expect_false(bool(beacon.get("lit")), "still unlit before picking from the panel")
	_press_choice(panel, "Left")
	await get_tree().process_frame

	_expect_false(panel.visible, "panel closes after choosing stable ignite")
	_expect_false(get_tree().paused, "game resumes after choosing stable ignite")
	_expect_true(bool(beacon.get("lit")), "Arena left choice ignites the beacon")
	_expect_equal(_lit_events, [true], "Arena stable ignite also emits lit once")
	_expect_true(arena.get("_pending_beacon_choice") == null, "pending reference cleared after stable ignite")

	# Reset the same beacon like a new cycle and walk the right choice and success boundary directly.
	beacon.call("reset")
	beacon.call("set_active", true)
	_prepare_arena_choice(arena)
	arena.set("_overcharge_successes", 0)
	_clear_events()
	_complete_charge(beacon)
	await _settle_choice_panel(panel)
	_press_choice(panel, "Right")
	await get_tree().process_frame

	_expect_false(panel.visible, "panel closes after choosing overcharge")
	_expect_true(bool(beacon.call("is_overcharging")), "Arena right choice starts overcharge")
	_expect_true(arena.get("_overcharge_beacon") == beacon, "overcharge beacon reference kept")
	_expect_false(bool(beacon.get("lit")), "still unlit during overcharge defense")
	_expect_true(
		_arena_population(arena) <= int(arena.call("spirit_cap")),
		"first overcharge raid stays within the spirit cap")

	# The first run after a CSV change, before .translation exists, must still be safe.
	# Intentionally overlay only the success line with a no-placeholder key to walk the bootstrap boundary.
	var original_locale: String = TranslationServer.get_locale()
	var bootstrap_translation := Translation.new()
	bootstrap_translation.locale = "eo"
	bootstrap_translation.add_message(
		&"OVERCHARGE_SUCCEEDED", "OVERCHARGE_SUCCEEDED")
	TranslationServer.add_translation(bootstrap_translation)
	TranslationServer.set_locale("eo")
	_expect_equal(
		tr("OVERCHARGE_SUCCEEDED"), "OVERCHARGE_SUCCEEDED",
		"translation-bootstrap success copy has no placeholder")
	player.global_position = beacon.global_position
	arena.call("_tick_overcharge", 6.6)
	TranslationServer.set_locale(original_locale)
	TranslationServer.remove_translation(bootstrap_translation)
	_expect_true(bool(beacon.get("lit")), "beacon ignites after the overcharge timer finishes")
	_expect_false(bool(beacon.call("is_overcharging")), "beacon overcharge cleared after success")
	_expect_true(arena.get("_overcharge_beacon") == null, "Arena reference cleared after success")
	_expect_equal(int(arena.get("_overcharge_successes")), 1, "overcharge success credited once")
	_expect_equal(_lit_events, [true], "successful overcharge ignite signal once")
	_expect_true(
		_arena_population(arena) <= int(arena.call("spirit_cap")),
		"second overcharge raid also stays within the spirit cap")

	arena.call("_tick_overcharge", 6.6)
	_expect_equal(int(arena.get("_overcharge_successes")), 1, "a tick after completion does not credit success again")
	_expect_equal(_lit_events, [true], "a tick after completion does not duplicate the ignite signal")

	# A far stray-fail still lights the beacon once, but does not grow the success reward.
	beacon.call("reset")
	beacon.call("set_active", true)
	_prepare_arena_choice(arena)
	_clear_events()
	_complete_charge(beacon)
	await _settle_choice_panel(panel)
	_press_choice(panel, "Right")
	await get_tree().process_frame
	player.global_position = beacon.global_position + Vector2(500.0, 500.0)
	arena.call("_tick_overcharge", 0.9)

	_expect_true(bool(beacon.get("lit")), "overcharge stray-fail still ignites the beacon")
	_expect_false(bool(beacon.call("is_overcharging")), "overcharge cleared after a stray fail")
	_expect_true(arena.get("_overcharge_beacon") == null, "Arena reference cleared after a stray fail")
	_expect_equal(int(arena.get("_overcharge_successes")), 1, "a stray fail does not credit the success reward")
	_expect_equal(_lit_events, [true], "stray-fail ignite signal once")

	# When an already-earned regular core is on the floor, consecutive overcharge rewards must reserve each core's actual
	# 2/3/4 rank thresholds in order (4 + 4 + 5 = 13).
	for core in get_tree().get_nodes_in_group(&"missile_cores"):
		if is_ancestor_of(core as Node):
			(core as Node).queue_free()
	await get_tree().process_frame
	var queued_reward_at: Vector2 = beacon.global_position
	var existing_core_cost: int = MissileProgression.threshold(1)
	var first_reward_cost: int = MissileProgression.threshold(2)
	var second_reward_cost: int = MissileProgression.threshold(3)
	var third_reward_cost: int = MissileProgression.threshold(4)
	arena.set("_missile_power", 1)
	arena.set("_regular_cores_outstanding", 1)
	arena.set("_regular_core_progress_escrow", existing_core_cost)
	arena.set("_ejected_cores_outstanding", 0)
	arena.set("_missile_progress", 0)
	arena.set("_missile_last_kill_at", queued_reward_at)
	arena.call("_spawn_missile_core", queued_reward_at, false)
	await get_tree().process_frame
	_expect_equal(_active_regular_cores(arena).size(), 1,
		"existing regular core is physically placed before consecutive overcharge")
	_expect_true(bool(arena.call("_grant_overcharge_core", queued_reward_at)),
		"first overcharge reward approved after a floor regular core")
	_expect_equal(int(arena.get("_missile_progress")), first_reward_cost,
		"first overcharge reserves the power-2 core threshold")
	_expect_true(bool(arena.call("_grant_overcharge_core", queued_reward_at)),
		"second overcharge reward approved after a floor regular core")
	_expect_equal(
		int(arena.get("_missile_progress")), first_reward_cost + second_reward_cost,
		"second overcharge reserves the power-3 core threshold")
	_expect_true(bool(arena.call("_grant_overcharge_core", queued_reward_at)),
		"third overcharge reward approved after a floor regular core")
	_expect_equal(int(arena.get("_missile_progress")),
		first_reward_cost + second_reward_cost + third_reward_cost,
		"core thresholds through the third overcharge credit 13")
	_expect_equal(int(arena.get("_regular_cores_outstanding")), 1,
		"all three reward cores wait to spawn until the existing regular core is picked up")
	_expect_equal(int(arena.get("_regular_core_progress_escrow")), existing_core_cost,
		"threshold deducted by the existing regular core is kept apart from the reward backlog")
	var active_reward_cores: Array[Node] = _active_regular_cores(arena)
	if not active_reward_cores.is_empty():
		(active_reward_cores[0] as Node).call("_collect")
	_expect_equal(int(arena.get("_missile_power")), 2,
		"collecting the existing regular core reaches power 2")
	_expect_equal(int(arena.get("_regular_cores_outstanding")), 1,
		"the first overcharge reward core takes the existing core's slot")
	_expect_equal(int(arena.get("_missile_progress")),
		second_reward_cost + third_reward_cost,
		"remaining two core thresholds kept after the first reward core is created")
	_expect_equal(int(arena.get("_regular_core_progress_escrow")), first_reward_cost,
		"stores the threshold the first overcharge reward core actually deducted")
	await get_tree().process_frame
	active_reward_cores = _active_regular_cores(arena)
	_expect_equal(active_reward_cores.size(), 1,
		"first overcharge backlog is placed as one real regular core")
	if not active_reward_cores.is_empty():
		(active_reward_cores[0] as Node).call("_collect")
	_expect_equal(int(arena.get("_missile_power")), 3,
		"collecting the first reward core reaches power 3")
	_expect_equal(int(arena.get("_missile_progress")), third_reward_cost,
		"third-core threshold kept after spawning the second reward core")
	await get_tree().process_frame
	active_reward_cores = _active_regular_cores(arena)
	_expect_equal(active_reward_cores.size(), 1,
		"second overcharge backlog also becomes one real core")
	if not active_reward_cores.is_empty():
		(active_reward_cores[0] as Node).call("_collect")
	_expect_equal(int(arena.get("_missile_power")), 4,
		"collecting the second reward core reaches power 4")
	_expect_equal(int(arena.get("_regular_cores_outstanding")), 1,
		"third overcharge reward core waits at power 4")
	_expect_equal(int(arena.get("_missile_progress")), 0,
		"backlog progress is 0 after the third reward core is created")
	_expect_equal(int(arena.get("_regular_core_progress_escrow")), third_reward_cost,
		"third reward core deducts the power-4 threshold of 5")
	await get_tree().process_frame
	active_reward_cores = _active_regular_cores(arena)
	_expect_equal(active_reward_cores.size(), 1,
		"third overcharge backlog placed as a real core")
	if not active_reward_cores.is_empty():
		_expect_false(bool(active_reward_cores[0].get("ejected")),
			"consecutive overcharge backlog is all regular cores")
		(active_reward_cores[0] as Node).call("_collect")
	_expect_equal(int(arena.get("_missile_power")), 5,
		"collecting the last reward core reaches power 5")
	_expect_equal(int(arena.get("_regular_cores_outstanding")), 0,
		"no regular core waiting after collecting three overcharge rewards")
	_expect_equal(int(arena.get("_missile_progress")), 0,
		"no progress lost or leftover after collecting three overcharge rewards")

	# Partial progress just below max power must remain outside one reward-core share.
	# After that core is reserved, the modal and the live grant together must not offer another core.
	for core in get_tree().get_nodes_in_group(&"missile_cores"):
		if is_ancestor_of(core as Node):
			(core as Node).queue_free()
	await get_tree().process_frame
	var final_core_cost: int = MissileProgression.threshold(
		MissileProgression.MAX_POWER - 1)
	var partial_progress: int = 2
	arena.set("_missile_power", MissileProgression.MAX_POWER - 2)
	arena.set("_regular_cores_outstanding", 1)
	arena.set("_regular_core_progress_escrow", MissileProgression.threshold(
		MissileProgression.MAX_POWER - 2))
	arena.set("_ejected_cores_outstanding", 0)
	arena.set("_missile_progress", partial_progress)
	arena.set("_missile_last_kill_at", queued_reward_at)
	_expect_true(bool(arena.call("_overcharge_core_available")),
		"partial progress just below max power still has a slot for the last reward core")
	_expect_true(bool(arena.call("_grant_overcharge_core", queued_reward_at)),
		"last overcharge reward approved just below max power")
	_expect_equal(int(arena.get("_missile_progress")),
		partial_progress + final_core_cost,
		"existing partial progress is kept even after adding one last-core share")
	arena.call("_on_missile_core_collected", false)
	_expect_equal(int(arena.get("_missile_power")), MissileProgression.MAX_POWER - 1,
		"reaches the power just below max after collecting the existing core")
	_expect_equal(int(arena.get("_regular_cores_outstanding")), 1,
		"spawns one last overcharge reward core")
	_expect_equal(int(arena.get("_missile_progress")), partial_progress,
		"partial progress kept even after spawning the last reward core")
	_expect_false(bool(arena.call("_overcharge_core_available")),
		"modal explains the growth reward once the last core is reserved")
	_expect_false(bool(arena.call("_grant_overcharge_core", queued_reward_at)),
		"rejects extra overcharge cores after the last core is reserved")
	_expect_equal(int(arena.get("_missile_progress")), partial_progress,
		"a reward rejected after max reservation does not clear partial progress")

	# If the backlog already holds a completed last-core share rather than partial progress, it is
	# unavailable. After reject, that one share still becomes a collectible live core.
	for core in get_tree().get_nodes_in_group(&"missile_cores"):
		if is_ancestor_of(core as Node):
			(core as Node).queue_free()
	await get_tree().process_frame
	arena.set("_missile_power", MissileProgression.MAX_POWER - 2)
	arena.set("_regular_cores_outstanding", 1)
	arena.set("_regular_core_progress_escrow", MissileProgression.threshold(
		MissileProgression.MAX_POWER - 2))
	arena.set("_ejected_cores_outstanding", 0)
	arena.set("_missile_progress", final_core_cost)
	_expect_false(bool(arena.call("_overcharge_core_available")),
		"counting queued cores up to just below max makes extra rewards unavailable")
	_expect_false(bool(arena.call("_grant_overcharge_core", queued_reward_at)),
		"also rejects a live grant if queued cores would fill max power")
	_expect_equal(int(arena.get("_missile_progress")), final_core_cost,
		"progress preserved on the reject path for a queued last core")
	arena.call("_on_missile_core_collected", false)
	_expect_equal(int(arena.get("_missile_power")), MissileProgression.MAX_POWER - 1,
		"queued last core is ready to spawn after collecting the existing core")
	_expect_equal(int(arena.get("_regular_cores_outstanding")), 1,
		"queued last core takes the regular-core slot")
	_expect_equal(int(arena.get("_missile_progress")), 0,
		"spawning the queued last core deducts exactly one threshold")
	arena.call("_on_missile_core_collected", false)
	_expect_equal(int(arena.get("_missile_power")), MissileProgression.MAX_POWER,
		"collecting the queued last core reaches max power")
	_expect_equal(int(arena.get("_missile_progress")), 0,
		"no extra backlog after reaching max power")

	# At power 8, succeeding at overcharge while a hit has one core strayed on the floor
	# do not discard the reward core. A stray core only means there is temporarily no slot,
	# When it expires and the slot frees, the reward backlog must appear as a regular core.
	for core in get_tree().get_nodes_in_group(&"missile_cores"):
		if is_ancestor_of(core as Node):
			(core as Node).queue_free()
	await get_tree().process_frame
	arena.set("_missile_power", MissileProgression.MAX_POWER - 1)
	arena.set("_regular_cores_outstanding", 0)
	arena.set("_ejected_cores_outstanding", 1)
	arena.set("_regular_core_progress_escrow", 0)
	arena.set("_missile_progress", 0)
	var overcharge_reward: int = MissileProgression.threshold(
		MissileProgression.MAX_POWER - 1)
	_expect_true(bool(arena.call("_grant_overcharge_core", player.global_position)),
		"overcharge core reward is still approved even with a stray core")
	_expect_equal(
		int(arena.get("_missile_progress")), overcharge_reward,
		"overcharge reward is still credited in a slot occupied by a stray core")
	_expect_equal(
		int(arena.get("_regular_cores_outstanding")), 0,
		"reward cores wait to spawn while a stray core exists")
	# Keep the recent-kill spot away from the player. Using the player's feet and skipping an idle frame
	# would let a new core collect immediately, making the backlog look gone.
	var reward_drop_at: Vector2 = beacon.global_position
	_expect_true(
		reward_drop_at.distance_to(player.global_position) > 200.0,
		"overcharge-backlog inspection core is placed away from the player")
	arena.call("_gain_missile_progress", reward_drop_at, false, false)
	_expect_equal(
		int(arena.get("_missile_progress")), overcharge_reward + 1,
		"kills while a stray core waits also keep the overcharge-reward backlog")
	arena.call("_on_missile_core_expired", true)
	await get_tree().process_frame
	_expect_equal(
		int(arena.get("_ejected_cores_outstanding")), 0,
		"slot freed after a stray core expires")
	_expect_equal(
		int(arena.get("_regular_cores_outstanding")), 1,
		"overcharge reward core created in the empty slot")
	_expect_equal(
		int(arena.get("_missile_progress")), 1,
		"only the spawned overcharge reward is deducted; extra kill progress is kept")

	# If live power and already-placed regular cores are at max, there is nothing more to give, so do not credit.
	for core in get_tree().get_nodes_in_group(&"missile_cores"):
		if is_ancestor_of(core as Node):
			(core as Node).queue_free()
	await get_tree().process_frame
	arena.set("_missile_power", MissileProgression.MAX_POWER)
	arena.set("_regular_cores_outstanding", 0)
	arena.set("_ejected_cores_outstanding", 0)
	arena.set("_regular_core_progress_escrow", 0)
	arena.set("_missile_progress", 0)
	_expect_false(bool(arena.call("_grant_overcharge_core", player.global_position)),
		"true max power offers a growth reward instead of a core")
	_expect_equal(int(arena.get("_missile_progress")), 0, "true max power has no extra reward")
	_expect_equal(
		int(arena.get("_regular_cores_outstanding")), 0,
		"true max power has no extra cores")

	# Even if a guardian-kill level-up queues a regular relic, that card must be taken first
	# and then continue to the settlement choice. Walk the regression where the two queues blocked each other, on a live panel.
	_prepare_arena_choice(arena)
	arena.set("_cycle_decision_queued", true)
	arena.set("_completed_cycle", 8)
	arena.set("_completed_cycle_overcharges", 3)
	arena.set("_owed", 1)
	arena.set("_last_offer", float(arena.get("_survived")))
	var relic_panel: Control = arena.get_node("Ui/Relic") as Control
	arena.call("_offer_relic")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(relic_panel.visible, "queued regular relic opens immediately while a cycle decision waits")
	_expect_equal(int(arena.get("_owed")), 0, "one queued regular relic consumed")
	var first_relic: Button = relic_panel.get_node("Center/Rows/Cards/C0") as Button
	_expect_false(first_relic.disabled, "queued regular relic ready to pick")
	_expect_true(
		get_viewport().gui_get_focus_owner() == first_relic,
		"relic pick defaults keyboard/gamepad focus to the first card")
	var accept_relic: InputEventKey = InputEventKey.new()
	accept_relic.keycode = KEY_ENTER
	accept_relic.physical_keycode = KEY_ENTER
	accept_relic.pressed = true
	Input.parse_input_event(accept_relic)
	await get_tree().process_frame
	accept_relic.pressed = false
	Input.parse_input_event(accept_relic)
	await get_tree().process_frame
	await _settle_choice_panel(panel)
	# Return (left) opens the whole result/save route, so here only pin the state boundary
	# with the side-effect-free right choice.
	_expect_true(panel.visible, "cycle-choice panel opens after the guardian reward")
	_expect_equal(int(panel.get("_mode")), 1, "passes cycle-choice mode")
	_expect_equal(int(panel.get("_context")), 8, "passes completed cycle-8 context")
	_expect_true(bool(arena.get("_cycle_decision_queued")), "cycle decision stays queued before the choice")
	_press_choice(panel, "Right")
	await get_tree().process_frame
	_expect_false(panel.visible, "cycle panel closes after choosing keep exploring")
	_expect_false(get_tree().paused, "game resumes after choosing keep exploring")
	_expect_false(bool(arena.get("_cycle_decision_queued")), "cycle decision consumed after keep exploring")
	_expect_false(bool(arena.get("_over")), "keep exploring does not end on the result screen")

	get_tree().paused = false
	arena.queue_free()
	await get_tree().process_frame


func _prepare_arena_choice(arena: Node2D) -> void:
	arena.set("_over", false)
	arena.set("_transitioning", false)
	arena.set("_escape_active", false)
	arena.set("_pending_beacon_choice", null)
	arena.set("_overcharge_beacon", null)
	arena.set("_overcharge_progress", 0.0)
	arena.set("_overcharge_abandon_left", 0.0)
	arena.set("_overcharge_second_wave_sent", false)
	arena.set("_lit_count", 0)


func _settle_choice_panel(panel: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_false(_choice_button(panel, "Left").disabled, "choice-panel left input ready")
	_expect_false(_choice_button(panel, "Right").disabled, "choice-panel right input ready")


func _press_choice(panel: Control, side: String) -> void:
	_choice_button(panel, side).emit_signal(&"pressed")


func _choice_button(panel: Control, side: String) -> Button:
	return panel.get_node("Center/Frame/Content/Rows/Choices/%s" % side) as Button


func _arena_population(arena: Node2D) -> int:
	var spirits: Array = arena.get("_spirits") as Array
	var queued: Array = arena.get("_raid_queue") as Array
	return spirits.size() + queued.size()


func _active_regular_cores(arena: Node2D) -> Array[Node]:
	var result: Array[Node] = []
	for candidate in get_tree().get_nodes_in_group(&"missile_cores"):
		var core: Node = candidate as Node
		if not arena.is_ancestor_of(core) or core.is_queued_for_deletion() \
				or bool(core.get("ejected")) or bool(core.get("_taken")):
			continue
		result.append(core)
	return result


func _spawn_unlit_beacon() -> Node2D:
	_clear_events()
	var beacon: Node2D = BEACON_SCENE.instantiate() as Node2D
	beacon.set("lit", false)
	add_child(beacon)
	await get_tree().process_frame
	beacon.connect(&"lit_changed", _on_lit_changed)
	beacon.connect(&"charge_completed", _on_charge_completed)
	beacon.connect(&"charge_changed", _on_charge_changed)
	return beacon


func _complete_charge(beacon: Node2D) -> void:
	beacon.call("_on_body_entered", _body)
	beacon.call("_process", CHARGE_SECONDS)


func _free_beacon(beacon: Node2D, settle_seconds: float = 0.0) -> void:
	if settle_seconds > 0.0:
		await get_tree().create_timer(settle_seconds).timeout
	beacon.queue_free()
	await get_tree().process_frame


func _monitoring(beacon: Node2D) -> bool:
	return (beacon.get_node("Reach") as Area2D).monitoring


func _light(beacon: Node2D) -> PointLight2D:
	return beacon.get_node("Light") as PointLight2D


func _glow(beacon: Node2D) -> Sprite2D:
	return beacon.get_node("Glow") as Sprite2D


func _clear_events() -> void:
	_lit_events.clear()
	_completed_events = 0
	_charge_events.clear()


func _on_lit_changed(_beacon: Node2D, is_lit: bool) -> void:
	_lit_events.append(is_lit)


func _on_charge_completed(_beacon: Node2D) -> void:
	_completed_events += 1


func _on_charge_changed(_beacon: Node2D, ratio: float) -> void:
	_charge_events.append(ratio)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _expect_false(value: bool, label: String) -> void:
	_expect_equal(value, false, label)


func _expect_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	_checked += 1
	if absf(actual - expected) <= tolerance:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, "±", tolerance, ", got ", actual)


func _expect_color(actual: Color, expected: Color, label: String) -> void:
	_checked += 1
	if actual.is_equal_approx(expected):
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)
