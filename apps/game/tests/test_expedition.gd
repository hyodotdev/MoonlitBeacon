extends SceneTree

## The rules of a run beyond one loop: places, difficulty, guardian mutations and omens.
##
## `Expedition` is plain functions of `(run seed, cycle, zone)`, so everything here is
## checked without a scene: the shipped cycles 1 to 8 keep their numbers, the endless
## stretch grows gently and never jumps, the same seed always answers the same way, and
## a draw never repeats itself.

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_shipped_cycles_are_unchanged()
	_test_depth_and_growth()
	_test_elite_chance()
	_test_classic_route()
	_test_terrain_table()
	_test_forks()
	_test_mutations()
	_test_omens()
	_finish()


func _test_shipped_cycles_are_unchanged() -> void:
	for cycle in range(1, 9):
		var old_toughness: float
		if cycle <= 3:
			old_toughness = pow(1.35, float(cycle - 1))
		else:
			old_toughness = pow(1.35, 2.0) * pow(1.58, float(cycle - 3))
		_expect_approx(Expedition.toughness(cycle), old_toughness, 0.0001,
			"cycle %d toughness is the shipped value" % cycle)
		_expect_approx(
			Expedition.guardian_scale(cycle), SpiritKind.guardian_toughness_scale(cycle),
			0.0001, "cycle %d guardian scale is the shipped value" % cycle)
	var old_elite: Dictionary = {
		1: 0.0, 2: 0.08, 3: 0.16, 4: 0.24, 5: 0.3, 6: 0.3, 7: 0.3, 8: 0.3,
	}
	for cycle in old_elite:
		_expect_approx(Expedition.elite_chance(cycle), float(old_elite[cycle]), 0.0001,
			"cycle %d elite chance is the shipped value" % cycle)
	_expect_equal(Expedition.depth(8), 0, "the official win cycle is depth 0")
	_expect_equal(Expedition.depth(1), 0, "cycle 1 is depth 0")


func _test_depth_and_growth() -> void:
	_expect_equal(Expedition.depth(9), 1, "cycle 9 is depth 1")
	_expect_equal(Expedition.depth(20), 12, "cycle 20 is depth 12")
	_expect_approx(
		Expedition.toughness(9) / Expedition.toughness(8),
		Expedition.DEPTH_TOUGHNESS_GROWTH, 0.0001,
		"depth 1 grows by the endless rate, not the shipped x1.58")
	_expect_approx(
		Expedition.guardian_scale(9) / Expedition.guardian_scale(8),
		Expedition.DEPTH_GUARDIAN_GROWTH, 0.0001,
		"a guardian's extra HP grows by the endless rate past the win")
	var previous_toughness: float = 0.0
	var previous_scale: float = 0.0
	for cycle in range(1, 41):
		var toughness: float = Expedition.toughness(cycle)
		var scale: float = Expedition.guardian_scale(cycle)
		_expect_true(toughness > previous_toughness,
			"toughness rises every cycle up to %d" % cycle)
		_expect_true(scale >= previous_scale,
			"guardian scale never falls up to %d" % cycle)
		if cycle > 1:
			var step: float = toughness / previous_toughness
			_expect_true(step <= 1.58 + 0.0001 and step >= 1.19,
				"no cycle-to-cycle jump beyond x1.58 at %d (was x%.3f)" % [cycle, step])
			if cycle > Expedition.OFFICIAL_WIN_CYCLE:
				_expect_approx(step, Expedition.DEPTH_TOUGHNESS_GROWTH, 0.0001,
					"depth %d grows at the steady endless rate" % (cycle - 8))
		previous_toughness = toughness
		previous_scale = scale
	# The wall this replaced: the shipped rate would have made cycle 16 about 700 tough.
	_expect_true(Expedition.toughness(16) < 100.0,
		"cycle 16 stays a hurdle, not a wall (%.1f)" % Expedition.toughness(16))


func _test_elite_chance() -> void:
	var previous: float = 0.0
	for cycle in range(1, 60):
		var chance: float = Expedition.elite_chance(cycle)
		_expect_true(chance >= previous, "elite chance never falls at %d" % cycle)
		_expect_true(chance <= Expedition.ELITE_CEILING + 0.0001,
			"elite chance stays under the ceiling at %d" % cycle)
		previous = chance
	_expect_approx(Expedition.elite_chance(9), 0.32, 0.0001, "depth 1 elite chance")
	_expect_approx(Expedition.elite_chance(60), Expedition.ELITE_CEILING, 0.0001,
		"elite chance settles at the ceiling")


func _test_classic_route() -> void:
	for cycle in range(1, 13):
		var route: Array[int] = Expedition.classic_route(cycle)
		_expect_equal(route.size(), 3, "classic route has three zones at cycle %d" % cycle)
		for zone in 3:
			# The rotation the arena has always used: WORLD_STEPS[((cycle - 1) + zone) % 3].
			_expect_equal(route[zone], ((cycle - 1) + zone) % 3,
				"classic zone %d of cycle %d" % [zone, cycle])
	_expect_equal(Expedition.classic_route(1), [0, 1, 2] as Array[int],
		"cycle 1 walks forest, field, camp")


func _test_terrain_table() -> void:
	var ids: Dictionary = {}
	for index in Expedition.TERRAINS.size():
		var terrain: Dictionary = Expedition.TERRAINS[index]
		var id: String = str(terrain["id"])
		_expect_true(not ids.has(id), "terrain id %s is unique" % id)
		ids[id] = true
		_expect_true(ResourceLoader.exists(str(terrain["room"])),
			"%s room resource exists" % id)
		_expect_true(str(terrain["name"]).begins_with("WORLD_"),
			"%s has a translated name key" % id)
		_expect_true(int(terrain["from_cycle"]) >= 1, "%s opens from a real cycle" % id)
		var roster: Array = terrain["guardians"]
		_expect_true(roster.size() >= 2, "%s has a base and a promoted guardian" % id)
		for path in roster:
			_expect_true(ResourceLoader.exists(str(path)),
				"%s guardian %s exists" % [id, path])
		_expect_equal(str(terrain["guardian"]), str(roster[0]),
			"%s keeps its base guardian as the default" % id)
	_expect_true(Expedition.TERRAINS.size() >= Expedition.CLASSIC_TERRAINS,
		"the classic three exist")
	_expect_equal(str(Expedition.TERRAINS[0]["id"]), "forest", "terrain 0 is the forest")
	_expect_equal(str(Expedition.TERRAINS[1]["id"]), "field", "terrain 1 is the field")
	_expect_equal(str(Expedition.TERRAINS[2]["id"]), "camp", "terrain 2 is the camp")
	# The later places arrive as the run goes on, and each has a room of its own with its own raid.
	var expected_ids: Array[String] = ["forest", "field", "camp", "frost", "marsh", "ruins"]
	_expect_equal(Expedition.TERRAINS.size(), expected_ids.size(), "six places in all")
	var encounters: Dictionary = {}
	for index in mini(Expedition.TERRAINS.size(), expected_ids.size()):
		_expect_equal(str(Expedition.TERRAINS[index]["id"]), expected_ids[index],
			"terrain %d is %s" % [index, expected_ids[index]])
		var kind: RoomKind = load(str(Expedition.TERRAINS[index]["room"])) as RoomKind
		_expect_true(kind != null, "%s room loads as a RoomKind" % expected_ids[index])
		if kind == null:
			continue
		_expect_true(not encounters.has(kind.encounter),
			"%s has a raid formation no other place has" % expected_ids[index])
		encounters[kind.encounter] = true
	_expect_equal(Expedition.pool(1).size(), 3, "cycle 1 knows three places")
	_expect_equal(Expedition.pool(2).size(), 3, "cycle 2 still knows three places")
	_expect_equal(Expedition.pool(3).size(), 5, "cycle 3 adds Frost Pass and Mirewood Marsh")
	_expect_equal(Expedition.pool(4).size(), 6, "cycle 4 adds Moonlit Ruins")
	_expect_equal(Expedition.pool(30).size(), 6, "no more places after that")


func _test_forks() -> void:
	_expect_true(not Expedition.forks_open(1), "cycle 1 has one gate")
	_expect_true(Expedition.forks_open(2), "forks open at cycle 2")
	for cycle in range(1, 30):
		var open: Array[int] = Expedition.pool(cycle)
		_expect_true(open.size() >= Expedition.CLASSIC_TERRAINS,
			"cycle %d keeps at least the classic terrains" % cycle)
	var starts: Dictionary = {}
	for run_seed in 60:
		for cycle in range(2, 12):
			for previous in Expedition.pool(cycle):
				var start: int = Expedition.start_terrain(run_seed, cycle, previous)
				_expect_true(start != previous,
					"a cycle never opens where the last guardian was (seed %d cycle %d)"
					% [run_seed, cycle])
				_expect_true(Expedition.pool(cycle).has(start),
					"the opening terrain is in the pool")
				_expect_equal(start, Expedition.start_terrain(run_seed, cycle, previous),
					"the opening terrain is deterministic")
				starts[start] = true
	_expect_true(starts.size() >= 2, "different seeds open in different places")

	for run_seed in 60:
		for cycle in range(2, 20):
			var route: Array[int] = [Expedition.start_terrain(run_seed, cycle, 0), -1, -1]
			for zone in 2:
				var options: Array[int] = Expedition.gate_options(run_seed, cycle, zone, route)
				_expect_equal(options.size(), 2,
					"a gate offers two places (seed %d cycle %d zone %d)"
					% [run_seed, cycle, zone])
				if options.size() < 2:
					continue
				_expect_true(options[0] != options[1], "the two places differ")
				_expect_true(not options.has(route[zone]),
					"a gate never leads back to where you stand")
				for option in options:
					_expect_true(Expedition.pool(cycle).has(option), "an option is in the pool")
				_expect_equal(
					options, Expedition.gate_options(run_seed, cycle, zone, route),
					"a gate's options are deterministic")
				route[zone + 1] = options[run_seed % 2]


func _test_mutations() -> void:
	var expected: Dictionary = {
		1: 0, 2: 0, 3: 0, 4: 0, 5: 1, 6: 1, 7: 1, 8: 2, 9: 2, 10: 2,
		11: 3, 12: 3, 13: 4, 14: 3, 15: 4, 16: 4, 18: 4, 30: 4,
	}
	for cycle in expected:
		_expect_equal(Expedition.mutation_slots(cycle), int(expected[cycle]),
			"mutation slots at cycle %d" % cycle)
	_expect_true(not Expedition.is_trial(8), "the official win is not a trial")
	_expect_true(not Expedition.is_trial(12), "depth 4 is not a trial")
	_expect_true(Expedition.is_trial(13), "depth 5 is the first Moonless Trial")
	_expect_true(Expedition.is_trial(18), "depth 10 is a Moonless Trial")
	for run_seed in 40:
		for cycle in range(1, 24):
			for terrain in Expedition.TERRAINS.size():
				var found: Array[int] = Expedition.mutations_for(run_seed, cycle, terrain)
				_expect_equal(found.size(), Expedition.mutation_slots(cycle),
					"a guardian carries its slots (seed %d cycle %d)" % [run_seed, cycle])
				var seen: Dictionary = {}
				for mutation in found:
					_expect_true(mutation >= 0 and mutation < Expedition.MUTATION_COUNT,
						"a mutation is a real one")
					_expect_true(not seen.has(mutation), "a guardian never repeats a mutation")
					seen[mutation] = true
				_expect_equal(
					found, Expedition.mutations_for(run_seed, cycle, terrain),
					"mutations are deterministic")
	var variety: Dictionary = {}
	for run_seed in 40:
		variety[str(Expedition.mutations_for(run_seed, 8, 0))] = true
	_expect_true(variety.size() >= 4, "different runs meet different mutations")
	_expect_equal(Expedition.mutation_name_key(Expedition.Mutation.ECHO), "MUTATION_ECHO",
		"mutation name key")
	_expect_equal(
		Expedition.mutation_name_key(Expedition.Mutation.METEORS), "MUTATION_METEORS",
		"last mutation name key")


func _test_omens() -> void:
	for cycle in range(1, 9):
		_expect_equal(Expedition.omen_slots(cycle), 0, "no omens through cycle %d" % cycle)
		_expect_true(Expedition.omens_for(1, cycle, 0).is_empty(),
			"cycle %d draws no omen" % cycle)
	for cycle in range(9, 13):
		_expect_equal(Expedition.omen_slots(cycle), 1, "one omen at depth %d" % (cycle - 8))
	for cycle in range(13, 25):
		_expect_equal(Expedition.omen_slots(cycle), 2, "two omens at depth %d" % (cycle - 8))
	for run_seed in 40:
		for cycle in range(9, 24):
			for zone in 3:
				var found: Array[int] = Expedition.omens_for(run_seed, cycle, zone)
				_expect_equal(found.size(), Expedition.omen_slots(cycle),
					"a zone carries its omen slots")
				var seen: Dictionary = {}
				for omen in found:
					_expect_true(omen >= 0 and omen < Expedition.OMEN_COUNT, "a real omen")
					_expect_true(not seen.has(omen), "a zone never repeats an omen")
					seen[omen] = true
				_expect_equal(found, Expedition.omens_for(run_seed, cycle, zone),
					"omens are deterministic")
	var neutral: Dictionary = Expedition.omen_effects([])
	_expect_approx(float(neutral["hp"]), 1.0, 0.0001, "no omen leaves HP alone")
	_expect_equal(int(neutral["cap"]), 0, "no omen leaves the cap alone")
	var blood: Dictionary = Expedition.omen_effects([Expedition.Omen.BLOOD_MOON])
	_expect_approx(float(blood["elite"]), 0.14, 0.0001, "Blood Moon adds elites")
	_expect_approx(float(blood["ember"]), 1.5, 0.0001, "Blood Moon adds embers")
	var both: Dictionary = Expedition.omen_effects(
		[Expedition.Omen.BLOOD_MOON, Expedition.Omen.SWARM_TIDE])
	_expect_approx(float(both["hp"]), 0.65, 0.0001, "omens multiply HP")
	_expect_approx(float(both["spawn"]), 0.72, 0.0001, "omens multiply the spawn interval")
	_expect_equal(int(both["cap"]), 0, "omens add to the cap")
	_expect_approx(float(both["elite"]), 0.14, 0.0001, "omens add elite chance")
	var iron_swarm: Dictionary = Expedition.omen_effects(
		[Expedition.Omen.SWARM_TIDE, Expedition.Omen.IRON_NIGHT])
	_expect_approx(float(iron_swarm["hp"]), 0.65 * 1.45, 0.0001, "opposed omens multiply out")
	_expect_equal(int(iron_swarm["cap"]), -6, "opposed omens add out")
	for omen in Expedition.OMEN_COUNT:
		var effect: Dictionary = Expedition.OMEN_EFFECTS[omen]
		_expect_true(float(effect["hp"]) > 0.0 and float(effect["spawn"]) > 0.0
			and float(effect["speed"]) > 0.0 and float(effect["beacon"]) > 0.0,
			"omen %d keeps every multiplier positive" % omen)
	_expect_equal(Expedition.omen_name_key(Expedition.Omen.GALE), "OMEN_GALE", "omen name key")
	_expect_equal(Expedition.omen_desc_key(Expedition.Omen.GALE), "OMEN_GALE_DESC",
		"omen description key")


func _finish() -> void:
	if _failed > 0:
		printerr("expedition test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("expedition test passed — ", _checked, " case(s)")
	quit(0)


func _expect_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	_checked += 1
	if absf(actual - expected) <= tolerance:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, "±", tolerance, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)
