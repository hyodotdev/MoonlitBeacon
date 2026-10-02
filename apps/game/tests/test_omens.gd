extends Node

## The endless stretch in the real arena: past the official win each zone carries an omen, and
## every omen changes exactly the one thing it says. Cycles 1 to 8 stay untouched: no omen, and
## the shipped elite chance, spawn pacing and spirit cap.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.call("debug_shield")
	await _test_shipped_cycles_carry_no_omen(arena)
	await _test_each_omen(arena)
	await _test_hud(arena)
	arena.queue_free()
	await get_tree().process_frame
	_finish()


func _set_zone(arena: Node2D, cycle: int, zone: int, run_seed: int) -> void:
	arena.set("_run_seed", run_seed)
	arena.set("_cycle", cycle)
	arena.set("_zone_index", zone)
	arena.call("_refresh_omens")


## The camp raises the elite chance. What counts is the room the arena is standing in.
func _in_camp(arena: Node2D) -> bool:
	return int(arena.call("_encounter_kind")) == RoomKind.Encounter.CARAVAN


## A (seed, zone) at this cycle whose only omen is `omen`.
func _find(cycle: int, omen: int) -> Vector2i:
	for run_seed in range(1, 4000):
		for zone in 3:
			var found: Array[int] = Expedition.omens_for(run_seed, cycle, zone)
			if found.size() == 1 and found[0] == omen:
				return Vector2i(run_seed, zone)
	return Vector2i(-1, -1)


func _test_shipped_cycles_carry_no_omen(arena: Node2D) -> void:
	for cycle in range(1, 9):
		_set_zone(arena, cycle, 0, 12345)
		_expect_true((arena.get("_omens") as Array).is_empty(), "cycle %d carries no omen" % cycle)
		var effects: Dictionary = arena.get("_omen_effects")
		_expect_approx(float(effects["hp"]), 1.0, "cycle %d HP untouched" % cycle)
		var expected_cap: int = mini(24 + 5 * (cycle - 1), 40)
		_expect_equal(int(arena.call("spirit_cap")), expected_cap,
			"cycle %d keeps the shipped spirit cap" % cycle)
		var chance: float = 0.0 if cycle < 2 else 0.08 * float(cycle - 1)
		if cycle >= 2 and _in_camp(arena):
			chance += 0.06
		chance = minf(chance, 0.3)
		_expect_approx(float(arena.call("elite_chance")), chance,
			"cycle %d keeps the shipped elite chance" % cycle)
		_expect_approx(float(arena.call("toughness")), Expedition.toughness(cycle),
			"cycle %d toughness follows Expedition" % cycle)
	arena.set("_cycle", 1)
	await get_tree().process_frame


func _test_each_omen(arena: Node2D) -> void:
	var cycle: int = 9
	# The neutral baseline for this cycle.
	_set_zone(arena, cycle, 0, 1)
	arena.set("_omens", [] as Array[int])
	arena.set("_omen_effects", Expedition.omen_effects([]))
	var base_elite: float = float(arena.call("elite_chance"))
	var base_interval: float = float(arena.call("_spawn_interval_now"))
	var base_cap: int = int(arena.call("spirit_cap"))
	_expect_equal(base_cap, 40, "depth 1 runs at the mobile ceiling")
	_expect_approx(base_elite, 0.32 + (0.06 if _in_camp(arena) else 0.0), "depth 1 elite chance")

	for omen in Expedition.OMEN_COUNT:
		var spot: Vector2i = _find(cycle, omen)
		_expect_true(spot.x >= 0, "a zone exists whose omen is %s" % Expedition.omen_name_key(omen))
		if spot.x < 0:
			continue
		_set_zone(arena, cycle, spot.y, spot.x)
		var carried: Array = arena.get("_omens")
		_expect_equal(carried.size(), 1, "depth 1 zone carries one omen")
		_expect_equal(int(carried[0]), omen, "the drawn omen is applied")
		var effect: Dictionary = Expedition.OMEN_EFFECTS[omen]
		var terrain_bonus: float = 0.06 if _in_camp(arena) else 0.0
		_expect_approx(float(arena.call("elite_chance")),
			minf(0.32 + terrain_bonus + float(effect["elite"]), Expedition.ELITE_CEILING),
			"%s elite chance" % Expedition.omen_name_key(omen))
		_expect_equal(int(arena.call("spirit_cap")),
			clampi(40 + int(effect["cap"]), 12, 40),
			"%s spirit cap" % Expedition.omen_name_key(omen))
		_expect_approx(
			float(arena.call("_ember_value", false)), float(effect["ember"]),
			"%s ember value" % Expedition.omen_name_key(omen))
		_expect_approx(
			float(arena.call("_ember_value", true)), 4.0 * float(effect["ember"]),
			"%s elite ember value" % Expedition.omen_name_key(omen))
		# Spawn pacing: same survival clock, only the omen differs.
		arena.set("_survived", 30.0)
		var paced: float = float(arena.call("_spawn_interval_now"))
		arena.set("_omen_effects", Expedition.omen_effects([]))
		var plain: float = float(arena.call("_spawn_interval_now"))
		arena.set("_omen_effects", Expedition.omen_effects(carried))
		_expect_approx(paced, maxf(plain * float(effect["spawn"]), 0.34),
			"%s spawn interval" % Expedition.omen_name_key(omen))
		arena.set("_survived", 0.0)
		# A spirit called under the omen carries its HP and speed.
		arena.call("debug_shield")
		var spirit: Node2D = arena.call("_summon", Room.MAP * 0.5 + Vector2(120, 0),
			"res://resources/wisp.tres", 1.0, false) as Node2D
		_expect_true(spirit != null, "a spirit can be called under the omen")
		if spirit != null:
			_expect_approx(float(spirit.get("toughness")),
				Expedition.toughness(cycle) * float(effect["hp"]),
				"%s spirit HP" % Expedition.omen_name_key(omen))
			_expect_approx(float(spirit.get("omen_speed")), float(effect["speed"]),
				"%s spirit speed" % Expedition.omen_name_key(omen))
			spirit.queue_free()
			arena.call("_prune_spirits")
			arena.call("debug_shield")
		var beacons: Array = arena.get("_beacons")
		for beacon in beacons:
			_expect_approx(float(beacon.get("charge_seconds")), 1.3 * float(effect["beacon"]),
				"%s beacon charge time" % Expedition.omen_name_key(omen))
	await get_tree().process_frame


func _test_hud(arena: Node2D) -> void:
	var spot: Vector2i = _find(9, Expedition.Omen.BLOOD_MOON)
	_set_zone(arena, 9, spot.y, spot.x)
	var hud: Control = arena.get("_hud") as Control
	var world: Label = hud.get("_world") as Label
	_expect_true(world.text.contains(TranslationServer.translate("OMEN_BLOOD_MOON")),
		"the world line names the omen")
	# Arriving in a zone with an omen, the hero remarks on it; a zone without one is quiet.
	var voice_spent: Dictionary = (arena.get("_voice") as HeroVoice).get("_spent") as Dictionary
	arena.set("_transitioning", false)
	arena.set("_over", false)
	arena.call("_announce_world_rule_if_current", int(arena.get("_zone_serial")))
	_expect_true(voice_spent.has("VOICE_OMEN_1") or voice_spent.has("VOICE_OMEN_2"),
		"the hero remarks on a night with an omen")
	hud.call("set_cycle", 9)
	var beacons_label: Label = hud.get("_beacons") as Label
	_expect_equal(beacons_label.text, TranslationServer.translate("HUD_DEPTH") % 1,
		"depth 1 shows as depth, not wave 9")
	hud.call("set_cycle", 8)
	_expect_equal(beacons_label.text, TranslationServer.translate("HUD_WAVE") % 8,
		"cycle 8 still shows as wave 8")
	_set_zone(arena, 8, 0, 1)
	_expect_true(not world.text.contains(TranslationServer.translate("OMEN_BLOOD_MOON")),
		"leaving depth clears the omen from the world line")
	await get_tree().process_frame


func _finish() -> void:
	if _failed > 0:
		printerr("omen test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("omen test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("omen test aborted: user:// path is not isolated — ", user_root)
	return safe


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
	if absf(actual - expected) <= 0.0001:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)
