extends Node

## The skills that keep appearing: cards unlock by cycle, and each one does what it says.
##
## The cards join the free third slot only once open, and the first sight of one is guaranteed and
## marked. Then each skill is driven in the real arena: the ward swallows a hit and recharges,
## the second light stands you up once a cycle, the comet lands on the thickest cluster, thorns
## burst on a hit, the magnet widens every pickup, a familiar shoots, choosing a card bursts
## moonlight, the bell slows what it reaches, and a dash leaves marks that burst behind it.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const RELIC_PANEL_SCENE: PackedScene = preload("res://scenes/ui/relic_panel.tscn")
const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	await _test_unlocks()
	await _test_skills_in_the_arena()
	_finish()


func _relic(path: String) -> Relic:
	return load(path) as Relic


func _test_unlocks() -> void:
	var panel: Node = RELIC_PANEL_SCENE.instantiate()
	add_child(panel)
	await get_tree().process_frame
	var expected: Dictionary = {
		"lantern_familiar": [5, Relic.Effect.LANTERN_FAMILIAR],
		"moon_ward": [5, Relic.Effect.MOON_WARD],
		"comet_call": [8, Relic.Effect.COMET_CALL],
		"star_magnet": [8, Relic.Effect.STAR_MAGNET],
		"moon_burst": [10, Relic.Effect.MOON_BURST],
		"thorn_bloom": [11, Relic.Effect.THORN_BLOOM],
		"second_light": [11, Relic.Effect.SECOND_LIGHT],
		"winter_bell": [13, Relic.Effect.WINTER_BELL],
		"comet_trail": [16, Relic.Effect.COMET_TRAIL],
	}
	for id in expected:
		var relic: Relic = _relic("res://resources/relics/%s.tres" % id)
		_expect_true(relic != null, "%s exists" % id)
		if relic == null:
			continue
		_expect_equal(relic.from_cycle, int(expected[id][0]), "%s unlocks at its cycle" % id)
		_expect_equal(relic.effect, int(expected[id][1]), "%s has its effect" % id)
		_expect_true(relic.icon != null, "%s has an emblem" % id)
		_expect_true(str(relic.display_name).begins_with("RELIC_"), "%s has a name key" % id)
		_expect_true(TranslationServer.translate(relic.display_name) != relic.display_name,
			"%s is translated" % id)
		_expect_true(TranslationServer.translate(relic.description) != relic.description,
			"%s has a translated card line" % id)
	_expect_true(Relic.family_of_effect(Relic.Effect.MOON_WARD) == Relic.Family.NONE,
		"skills belong to no evolution path")

	# Nothing before cycle 5.
	panel.set("cycle", 4)
	var early: bool = false
	for round in 80:
		var offer: Array[Relic] = panel.call("_draw_offer")
		for relic in offer:
			if relic.effect >= Relic.Effect.LANTERN_FAMILIAR:
				early = true
	_expect_true(not early, "no skill is offered before cycle 5")

	# At cycle 5 the first sight of each newly opened skill is guaranteed, and marked. Both
	# cycle-5 skills arrive within exactly the two unseen draws, never by a lucky repeat.
	panel.set("cycle", 5)
	panel.set("_first_offer_done", true)
	var discovered: Dictionary = {}
	for round in 2:
		var offer: Array[Relic] = panel.call("_draw_offer")
		for relic in offer:
			if bool(relic.get_meta("new_skill", false)):
				discovered[relic.effect] = true
	_expect_true(discovered.has(Relic.Effect.LANTERN_FAMILIAR),
		"the lantern familiar is shown and marked when it opens")
	_expect_true(discovered.has(Relic.Effect.MOON_WARD),
		"the moon ward is shown and marked when it opens")
	_expect_equal(discovered.size(), 2, "both cycle-5 skills arrive in two bounded draws")
	_expect_true(not discovered.has(Relic.Effect.COMET_CALL), "a cycle-8 skill waits for cycle 8")
	_expect_true(not discovered.has(Relic.Effect.THORN_BLOOM), "a cycle-11 skill waits for cycle 11")

	# Cycle 8 opens two more, and each is guaranteed within its own unseen draw.
	panel.set("cycle", 8)
	for round in 2:
		for relic in panel.call("_draw_offer"):
			if bool(relic.get_meta("new_skill", false)):
				discovered[relic.effect] = true
	_expect_true(discovered.has(Relic.Effect.COMET_CALL), "the comet call is shown when it opens")
	_expect_true(discovered.has(Relic.Effect.STAR_MAGNET), "the star magnet is shown when it opens")
	_expect_equal(discovered.size(), 4, "four skills discovered by cycle 8")

	# Cycle 10 opens the moon burst alone: one unseen skill, one draw.
	panel.set("cycle", 10)
	for relic in panel.call("_draw_offer"):
		if bool(relic.get_meta("new_skill", false)):
			discovered[relic.effect] = true
	_expect_true(discovered.has(Relic.Effect.MOON_BURST), "the moon burst is shown when it opens")
	_expect_equal(discovered.size(), 5, "five skills discovered by cycle 10")

	# By cycle 11 the seven that are open have been shown once, and the mark is only on the first
	# sight. The bell (13) and the trail (16) are still waiting.
	panel.set("cycle", 11)
	for round in 2:
		for relic in panel.call("_draw_offer"):
			if bool(relic.get_meta("new_skill", false)):
				discovered[relic.effect] = true
	_expect_true(discovered.has(Relic.Effect.THORN_BLOOM), "the thorn bloom is shown when it opens")
	_expect_true(discovered.has(Relic.Effect.SECOND_LIGHT), "the second light is shown when it opens")
	_expect_equal(discovered.size(), 7, "every unlocked skill has been offered by cycle 11")
	_expect_true(not discovered.has(Relic.Effect.WINTER_BELL), "the bell waits for cycle 13")
	_expect_true(not discovered.has(Relic.Effect.COMET_TRAIL), "the trail waits for cycle 16")
	var marks: int = 0
	for round in 30:
		for relic in panel.call("_draw_offer"):
			if bool(relic.get_meta("new_skill", false)):
				marks += 1
	_expect_equal(marks, 0, "a skill already seen is not marked new again")

	# A new skill keeps arriving through the endless stretch: cycles 13 and 16 each bring one.
	panel.set("cycle", 16)
	var late_new: Dictionary = {}
	for round in 8:
		for relic in panel.call("_draw_offer"):
			if bool(relic.get_meta("new_skill", false)):
				late_new[relic.effect] = true
	_expect_true(late_new.has(Relic.Effect.WINTER_BELL), "the bell is shown and marked when it opens")
	_expect_true(late_new.has(Relic.Effect.COMET_TRAIL), "and so is the trail")

	# Caps: a skill at its stack limit leaves the offer.
	panel.set("_stacks", {"res://resources/relics/second_light.tres": 2})
	var capped_seen: bool = false
	for round in 80:
		for relic in panel.call("_draw_offer"):
			if relic.effect == Relic.Effect.SECOND_LIGHT:
				capped_seen = true
	_expect_true(not capped_seen, "a skill at its stack cap is not offered")
	panel.queue_free()
	await get_tree().process_frame


func _new_arena() -> Node2D:
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	return arena


func _take(arena: Node2D, id: String, times: int = 1) -> void:
	for i in times:
		arena.call("_on_relic_picked", _relic("res://resources/relics/%s.tres" % id), false)
	await get_tree().process_frame


func _test_skills_in_the_arena() -> void:
	var arena: Node2D = await _new_arena()
	_expect_true(arena.get("_skills") == null, "a run with no skill carries no skills node")
	var player: Player = arena.get("_player") as Player

	# --- Moon Ward: one hit swallowed, then a recharge that speeds up with stacks.
	await _take(arena, "moon_ward")
	var skills: PlayerSkills = arena.get("_skills") as PlayerSkills
	_expect_true(skills != null, "taking a skill builds the skills node")
	_expect_true(skills.ward_ready(), "the ward starts ready")
	var health: int = int(arena.get("_health"))
	arena.set("_invulnerable", 0.0)
	arena.call("_on_player_hit", player.global_position + Vector2(10, 0))
	_expect_equal(int(arena.get("_health")), health, "the ward swallows the hit")
	_expect_true(not skills.ward_ready(), "and is spent")
	arena.set("_invulnerable", 0.0)
	arena.call("_on_player_hit", player.global_position + Vector2(10, 0))
	_expect_equal(int(arena.get("_health")), health - 1, "the next hit lands while it recharges")
	var one: float = skills.ward_recharge_seconds()
	await _take(arena, "moon_ward")
	var two: float = skills.ward_recharge_seconds()
	_expect_true(two < one, "a second stack recharges faster (%.1f then %.1f)" % [one, two])
	_expect_approx(one, PlayerSkills.WARD_RECHARGE, 0.001, "one stack recharges in 26 seconds")

	# --- Second Light: standing back up once a cycle.
	await _take(arena, "second_light")
	_expect_true(skills.second_light_ready(), "the second light starts lit")
	arena.set("_health", 1)
	arena.set("_invulnerable", 0.0)
	arena.set("_over", false)
	arena.call("_on_player_hit", player.global_position + Vector2(10, 0))
	_expect_true(not bool(arena.get("_over")), "a lethal hit does not end the run")
	_expect_true(int(arena.get("_health")) >= 1, "you stand back up")
	_expect_true(float(arena.get("_invulnerable")) >= PlayerSkills.SECOND_LIGHT_INVULNERABLE - 0.1,
		"with a moment of safety")
	_expect_true(not skills.second_light_ready(), "and it is spent")
	skills.new_cycle()
	_expect_true(skills.second_light_ready(), "a new cycle lights it again")

	# --- Thorn Bloom: a hit hurts what is near and pushes it back.
	await _take(arena, "thorn_bloom")
	arena.call("_summon", player.global_position + Vector2(30, 0),
		"res://resources/wisp.tres", 1.0, false)
	var near: Node2D = (arena.get("_spirits") as Array)[-1] as Node2D
	near.set("_materialized", true)
	var far: Node2D = arena.call("_summon", player.global_position + Vector2(400, 0),
		"res://resources/wisp.tres", 1.0, false) as Node2D
	far.set("_materialized", true)
	var near_before: int = int(near.get("_health"))
	var far_before: int = int(far.get("_health"))
	arena.set("_health", 4)
	arena.set("_invulnerable", 0.0)
	arena.set("_max_health", 5)
	skills.set("_ward_ready", false)
	skills.set("_ward_left", 999.0)
	arena.call("_on_player_hit", player.global_position + Vector2(10, 0))
	_expect_true(int(near.get("_health")) < near_before, "thorns hurt what is close")
	_expect_equal(int(far.get("_health")), far_before, "and leave what is far")
	near.queue_free()
	far.queue_free()
	arena.call("_prune_spirits")

	# --- Star Magnet: every pickup reaches further, and the arena puts it back when it leaves.
	_expect_approx(PickupMagnet.scale, 1.0, 0.001, "no magnet without the skill")
	await _take(arena, "star_magnet")
	_expect_approx(PickupMagnet.scale, 1.0 + PlayerSkills.MAGNET_PER_STACK, 0.001,
		"one stack widens every pickup")
	await _take(arena, "star_magnet")
	_expect_approx(PickupMagnet.scale, 1.0 + 2.0 * PlayerSkills.MAGNET_PER_STACK, 0.001,
		"a second stack widens it again")

	# --- Lantern Familiar: it shoots the nearest spirit.
	await _take(arena, "lantern_familiar")
	_expect_equal(skills.familiar_count(), 1, "one familiar joins")
	var target: Node2D = arena.call("_summon", player.global_position + Vector2(60, 0),
		"res://resources/wisp.tres", 1.0, false) as Node2D
	target.set("_materialized", true)
	var before: int = int(target.get("_health"))
	skills.set("_familiar_wait", [0.0] as Array[float])
	skills.call("_process", 0.02)
	_expect_true(int(target.get("_health")) < before, "the familiar's spark lands")
	target.queue_free()
	arena.call("_prune_spirits")

	# --- Comet Call: a mark on the thickest cluster, then a burst that hurts all of it.
	await _take(arena, "comet_call")
	var pack: Array[Node2D] = []
	for i in 4:
		var member: Node2D = arena.call("_summon", player.global_position + Vector2(150 + i * 8, 20),
			"res://resources/wisp.tres", 1.0, false) as Node2D
		member.set("_materialized", true)
		pack.append(member)
	var lone: Node2D = arena.call("_summon", player.global_position + Vector2(-150, 0),
		"res://resources/wisp.tres", 1.0, false) as Node2D
	lone.set("_materialized", true)
	var hp: Array[int] = []
	for member in pack:
		hp.append(int(member.get("_health")))
	var lone_before: int = int(lone.get("_health"))
	skills.set("_comet_wait", 0.0)
	skills.call("_process", 0.02)
	_expect_equal(get_tree().get_node_count_in_group("ground_bursts"), 1,
		"the comet marks a spot")
	for node in get_tree().get_nodes_in_group("ground_bursts"):
		node.call("_physics_process", 1.0)
	var hurt: int = 0
	for index in pack.size():
		if int(pack[index].get("_health")) < hp[index]:
			hurt += 1
	_expect_true(hurt >= 3, "the comet lands on the thick cluster (%d of 4 hurt)" % hurt)
	_expect_equal(int(lone.get("_health")), lone_before, "and misses the lone spirit")
	_expect_true(skills.comet_interval() <= PlayerSkills.COMET_EVERY, "the comet has a rhythm")
	for member in pack:
		member.queue_free()
	lone.queue_free()
	arena.call("_prune_spirits")
	_free_marks()

	# --- Moon Burst: choosing a card bursts moonlight that hurts what is near.
	await _take(arena, "moon_burst")
	var burst_near: Node2D = arena.call("_summon", player.global_position + Vector2(40, 0),
		"res://resources/wisp.tres", 1.0, false) as Node2D
	burst_near.set("_materialized", true)
	var burst_far: Node2D = arena.call("_summon", player.global_position + Vector2(300, 0),
		"res://resources/wisp.tres", 1.0, false) as Node2D
	burst_far.set("_materialized", true)
	var burst_near_before: int = int(burst_near.get("_health"))
	var burst_far_before: int = int(burst_far.get("_health"))
	arena.call("_on_relic_picked", _relic("res://resources/relics/quick_arrow.tres"), true)
	_expect_true(int(burst_near.get("_health")) < burst_near_before,
		"choosing a card hurts what is close")
	_expect_equal(int(burst_far.get("_health")), burst_far_before, "and leaves what is far")
	_expect_true(skills.burst_radius() >= PlayerSkills.BURST_RADIUS, "the burst has a reach")
	await _take(arena, "moon_burst")
	_expect_true(skills.burst_radius() > PlayerSkills.BURST_RADIUS, "a second stack reaches further")
	var quiet_before: int = int(burst_near.get("_health"))
	await _take(arena, "quick_arrow")
	_expect_equal(int(burst_near.get("_health")), quiet_before,
		"a card granted without a choice (the recompute path) does not burst")
	burst_near.queue_free()
	burst_far.queue_free()
	arena.call("_prune_spirits")

	# --- Winter Bell: a ring of frost slows every spirit it reaches, and only those.
	await _take(arena, "winter_bell")
	var chilled: Node2D = arena.call("_summon", player.global_position + Vector2(90, 0),
		"res://resources/wisp.tres", 1.0, false) as Node2D
	chilled.set("_materialized", true)
	var spared: Node2D = arena.call("_summon", player.global_position + Vector2(420, 0),
		"res://resources/wisp.tres", 1.0, false) as Node2D
	spared.set("_materialized", true)
	skills.set("_bell_wait", 0.0)
	skills.call("_process", 0.02)
	_expect_true(bool(chilled.call("is_chilled")), "the bell chills what it reaches")
	_expect_true(not bool(spared.call("is_chilled")), "and not what it does not")
	# A chilled spirit really covers less ground than a free one in the same time.
	chilled.set("velocity", Vector2(100, 0))
	spared.set("velocity", Vector2(100, 0))
	var chilled_from: Vector2 = chilled.position
	var spared_from: Vector2 = spared.position
	chilled.call("_glide", 0.1, false)
	spared.call("_glide", 0.1, false)
	var chilled_run: float = chilled.position.distance_to(chilled_from)
	var spared_run: float = spared.position.distance_to(spared_from)
	_expect_true(chilled_run < spared_run * 0.7,
		"a chilled spirit moves slower (%.1f against %.1f)" % [chilled_run, spared_run])
	# A guardian feels a third of it.
	var boss: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	boss.set("kind", (load("res://resources/guardian_forest.tres") as SpiritKind).duplicate())
	add_child(boss)
	boss.call("chill", 0.5, 2.0)
	_expect_approx(float(boss.get("_chill_slow")), 0.5 * 0.35, 0.001, "a guardian feels a third of the chill")
	boss.free()
	_expect_true(skills.bell_interval() <= PlayerSkills.BELL_EVERY, "the bell has a rhythm")
	_expect_true(skills.bell_slow() >= PlayerSkills.BELL_SLOW, "the bell slows")
	# A bell over an empty floor rings again soon and wastes nothing.
	for spirit in (arena.get("_spirits") as Array).duplicate():
		if is_instance_valid(spirit):
			spirit.free()
	arena.call("_prune_spirits")
	skills.set("_bell_wait", 0.0)
	skills.call("_process", 0.02)
	_expect_true(float(skills.get("_bell_wait")) < 2.0, "over an empty floor the bell rings again soon")

	# --- Comet Trail: a dash leaves marks that burst behind you.
	_free_marks()
	await _take(arena, "comet_trail")
	var runner: Node2D = arena.call("_summon", player.global_position + Vector2(30, 0),
		"res://resources/wisp.tres", 1.0, false) as Node2D
	runner.set("_materialized", true)
	var runner_before: int = int(runner.get("_health"))
	skills.call("on_dash", player.global_position, player.global_position + Vector2(60, 0))
	_expect_equal(get_tree().get_node_count_in_group("ground_bursts"), 3, "a dash leaves three marks")
	for node in get_tree().get_nodes_in_group("ground_bursts"):
		node.call("_physics_process", 2.0)
	_expect_true(int(runner.get("_health")) < runner_before, "and what stands on them is hurt")
	_free_marks()
	await _take(arena, "comet_trail", 2)
	skills.call("on_dash", player.global_position, player.global_position + Vector2(60, 0))
	_expect_equal(get_tree().get_node_count_in_group("ground_bursts"), 5, "three stacks leave five")
	_free_marks()
	# The real dash button does it too.
	player.set("_dash_cooldown", 0.0)
	arena.call("_on_dash_pressed")
	_expect_true(get_tree().get_node_count_in_group("ground_bursts") >= 3,
		"the dash button leaves the trail")
	_free_marks()
	runner.queue_free()
	arena.call("_prune_spirits")

	arena.queue_free()
	await get_tree().process_frame
	_expect_approx(PickupMagnet.scale, 1.0, 0.001, "leaving the arena resets the magnet")


func _free_marks() -> void:
	for node in get_tree().get_nodes_in_group("ground_bursts"):
		if is_instance_valid(node):
			node.free()


func _finish() -> void:
	if _failed > 0:
		printerr("skills test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("skills test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("skills test aborted: user:// path is not isolated — ", user_root)
	return safe


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _expect_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	_checked += 1
	if absf(actual - expected) <= tolerance:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)
