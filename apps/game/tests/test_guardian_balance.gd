extends SceneTree

## Pin guardian max-burst survival and normal-hit feel at cycle-3 Lv20 live HP.
## Checking constants alone would pass even if damage is discarded mid-way, so
## Deal damage to a live Spirit and run the physics clock.

const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")
const CYCLE_THREE_TOUGHNESS: float = 1.35 * 1.35
const SATURATED_DAMAGE: int = 999999
const STEP_SECONDS: float = 0.05

const GUARDIAN_CASES: Array[Dictionary] = [
	{
		"id": "forest",
		"resource": "res://resources/guardian_forest.tres",
		"style": SpiritKind.GuardianStyle.FOREST,
		"health": 1276,
		"burst": 0.18,
		"sustain": 0.15,
		"min_ttk": 5.30,
		"max_ttk": 5.75,
		"ordinary_damage": 70,
	},
	{
		"id": "field",
		"resource": "res://resources/guardian_field.tres",
		"style": SpiritKind.GuardianStyle.FIELD,
		"health": 1130,
		"burst": 0.10,
		"sustain": 0.12,
		# Field fires its second radial barrage 6.68s after materializing.
		"min_ttk": 7.35,
		"max_ttk": 7.75,
		"ordinary_damage": 70,
	},
	{
		"id": "camp",
		"resource": "res://resources/guardian_camp.tres",
		"style": SpiritKind.GuardianStyle.CAMP,
		"health": 1239,
		"burst": 0.16,
		"sustain": 0.13,
		"min_ttk": 6.30,
		"max_ttk": 6.75,
		# Closed plate still blocks 15% when not in recover, matching the existing tactic.
		"ordinary_damage": 60,
	},
]

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_normal_spirit_damage()
	var saturated_times: Dictionary = {}
	for guardian_case in GUARDIAN_CASES:
		_test_guardian_profile(guardian_case)
		_test_guardian_ordinary_hits(guardian_case)
		saturated_times[guardian_case["id"]] = _test_guardian_saturated_ttk(
			guardian_case)
	_test_camp_open_window()
	_test_guardian_order(saturated_times)
	_test_guardian_cycle_pressure()
	_test_guardian_late_cycle_wall()
	_test_guardian_immediate_lethal_once()
	_test_debug_slay_bypass()
	_finish()


func _test_normal_spirit_damage() -> void:
	var spirit: Node2D = _spawn("res://resources/wisp.tres", 1.0)
	var full_health: int = int(spirit.get("_health"))
	spirit.call("take_damage", 7, Vector2.ZERO)
	_expect_equal(
		int(spirit.get("_health")), full_health - 7,
		"regular spirit 7 damage applies in full immediately")
	_expect_approx(
		float(spirit.get("_guardian_deferred_damage")), 0.0, 0.001,
		"regular spirits do not use guardian delayed damage")
	spirit.call("take_damage", SATURATED_DAMAGE, Vector2.ZERO)
	_expect_true(bool(spirit.get("_perishing")), "regular spirit lethal hit kills immediately")
	spirit.free()


func _test_guardian_profile(guardian_case: Dictionary) -> void:
	var kind: SpiritKind = load(str(guardian_case["resource"])) as SpiritKind
	_expect_true(kind != null, "%s guardian balance resource" % guardian_case["id"])
	if kind == null:
		return
	_expect_equal(
		kind.guardian_style, guardian_case["style"],
		"%s keeps unique pattern" % guardian_case["id"])
	_expect_approx(
		kind.guardian_burst_fraction, float(guardian_case["burst"]), 0.0001,
		"%s first-hit budget" % guardian_case["id"])
	_expect_approx(
		kind.guardian_sustain_fraction, float(guardian_case["sustain"]), 0.0001,
		"%s sustained-damage budget" % guardian_case["id"])
	var theoretical_ttk: float = (1.0 - kind.guardian_burst_fraction) \
		/ kind.guardian_sustain_fraction
	_expect_between(
		theoretical_ttk,
		float(guardian_case["min_ttk"]),
		float(guardian_case["max_ttk"]),
		"%s ratio-based minimum TTK" % guardian_case["id"])


func _test_guardian_ordinary_hits(guardian_case: Dictionary) -> void:
	var spirit: Node2D = _spawn(str(guardian_case["resource"]))
	_expect_equal(
		int(spirit.get("_health")), int(guardian_case["health"]),
		"%s cycle-3 real HP" % guardian_case["id"])
	for hit_index in 6:
		var before: int = int(spirit.get("_health"))
		spirit.call("take_damage", 70, Vector2.ZERO)
		_expect_equal(
			before - int(spirit.get("_health")),
			int(guardian_case["ordinary_damage"]),
			"%s normal single hit %d applies full damage immediately"
				% [guardian_case["id"], hit_index + 1])
		_expect_approx(
			float(spirit.get("_guardian_deferred_damage")), 0.0, 0.001,
			"%s normal single hit %d has no queued damage"
				% [guardian_case["id"], hit_index + 1])
		# 70 / 0.6s is below all three guardians' sustained budgets. A normal build
		# recovers budget before the next hit so damage does not shrink or delay.
		spirit.call("_physics_process", 0.6)
	spirit.free()


func _test_camp_open_window() -> void:
	var spirit: Node2D = _spawn("res://resources/guardian_camp.tres")
	var constants: Dictionary = spirit.get_script().get_script_constant_map()
	var moves: Dictionary = constants.get("GuardianMove", {}) as Dictionary
	spirit.set("_guardian_move", int(moves.get("RECOVER", 3)))
	var before: int = int(spirit.get("_health"))
	spirit.call("take_damage", 70, Vector2.ZERO)
	_expect_equal(
		before - int(spirit.get("_health")), 70,
		"camp guardian takes 100% damage in the armor-open recover window")
	_expect_approx(
		float(spirit.get("_guardian_deferred_damage")), 0.0, 0.001,
		"camp open-window single hits are not delayed")
	spirit.free()


func _test_guardian_saturated_ttk(guardian_case: Dictionary) -> float:
	var spirit: Node2D = _spawn(str(guardian_case["resource"]))
	var full_health: int = int(spirit.get("_health"))
	var kind: SpiritKind = spirit.get("kind") as SpiritKind
	spirit.call("take_damage", SATURATED_DAMAGE, Vector2.ZERO)
	var first_burst: int = full_health - int(spirit.get("_health"))
	_expect_equal(
		first_burst,
		floori(float(full_health) * kind.guardian_burst_fraction + 0.0001),
		"%s max-burst first hit applies only the ratio budget immediately"
			% guardian_case["id"])
	_expect_true(
		float(spirit.get("_guardian_deferred_damage")) > 0.0,
		"%s overflow damage is queued, not discarded" % guardian_case["id"])
	_expect_true(
		not bool(spirit.get("_perishing")),
		"%s max burst does not kill in one frame" % guardian_case["id"])

	var elapsed: float = 0.0
	while not bool(spirit.get("_perishing")) and elapsed < 10.0:
		spirit.call("_physics_process", STEP_SECONDS)
		elapsed += STEP_SECONDS

	_expect_true(
		bool(spirit.get("_perishing")),
		"%s queued damage still kills after budget recovers" % guardian_case["id"])
	_expect_between(
		elapsed,
		float(guardian_case["min_ttk"]),
		float(guardian_case["max_ttk"]),
		"%s actual max-burst TTK" % guardian_case["id"])
	_expect_approx(
		float(spirit.get("_guardian_deferred_damage")), 0.0, 0.001,
		"%s queued damage cleared after kill" % guardian_case["id"])
	spirit.free()
	return elapsed


func _test_guardian_order(times: Dictionary) -> void:
	_expect_true(
		float(times.get("forest", 0.0)) < float(times.get("camp", 0.0)),
		"forest charger is released sooner than the camp siege type")
	_expect_true(
		float(times.get("camp", 0.0)) < float(times.get("field", 0.0)),
		"field barrage type shows both patterns and is released last")
	_expect_true(
		float(times.get("field", 0.0)) >= 7.35,
		"cycle-3 field guardian survives past the 3.4s store-capture moment")


## Cycle-pressure contract. Burst-budget ratio tightens each cycle so the climax lasts longer.
##
## If the value changes, every cycle's boss fight length changes, so catch it here.
func _test_guardian_cycle_pressure() -> void:
	_expect_approx(
		SpiritKind.cycle_pressure(1), 1.0, 0.0001, "cycle 1 has no pressure")
	_expect_approx(
		SpiritKind.cycle_pressure(2), 1.22, 0.0001, "cycle 2 pressure 22%")
	_expect_approx(
		SpiritKind.cycle_pressure(3), 1.44, 0.0001, "cycle 3 pressure 44%")
	_expect_approx(
		SpiritKind.cycle_pressure(4), 1.84, 0.0001, "cycle 4 uses the previous pressure")
	_expect_approx(
		SpiritKind.cycle_pressure(5),
		1.84 * 1.48,
		0.0001,
		"exponential pressure from cycle 5")
	_expect_approx(
		SpiritKind.cycle_pressure(6),
		1.84 * 1.48 * 1.48,
		0.0001,
		"cycle 6 pressure")

	# Cycle-3 field: tightened ratio must lengthen both theoretical and measured TTK.
	var kind: SpiritKind = (
		load("res://resources/guardian_field.tres") as SpiritKind).duplicate()
	var pressure: float = SpiritKind.cycle_pressure(3)
	var budget_floor: float = SpiritKind.guardian_budget_floor(3)
	kind.guardian_burst_fraction = maxf(
		kind.guardian_burst_fraction / pressure, budget_floor)
	kind.guardian_sustain_fraction = maxf(
		kind.guardian_sustain_fraction / pressure, budget_floor)
	var theoretical: float = (1.0 - kind.guardian_burst_fraction) \
		/ kind.guardian_sustain_fraction
	_expect_between(theoretical, 11.0, 11.35, "cycle-3 field ratio-based TTK is extended")

	var spirit: Node2D = _spawn_kind(kind)
	spirit.call("take_damage", SATURATED_DAMAGE, Vector2.ZERO)
	var elapsed: float = 0.0
	while not bool(spirit.get("_perishing")) and elapsed < 14.0:
		spirit.call("_physics_process", STEP_SECONDS)
		elapsed += STEP_SECONDS
	_expect_true(
		bool(spirit.get("_perishing")), "pressured field still dies from queued damage")
	_expect_between(elapsed, 11.0, 11.8, "cycle-3 field measured max-burst TTK is extended")
	spirit.free()

	_expect_approx(
		SpiritKind.guardian_budget_floor(1), 0.05, 0.0001, "early budget floor")
	_expect_approx(
		SpiritKind.guardian_budget_floor(3), 0.05, 0.0001, "cycle-3 budget floor")
	_expect_approx(
		SpiritKind.guardian_budget_floor(6), 0.0256, 0.0001, "cycle-6 budget floor")
	_expect_approx(
		SpiritKind.guardian_budget_floor(9), 0.018, 0.0001, "deep-cycle budget floor")
	_expect_approx(
		SpiritKind.guardian_toughness_scale(3), 1.0, 0.0001,
		"no extra guardian HP on cycles 1–3")
	_expect_approx(
		SpiritKind.guardian_toughness_scale(6),
		1.22 * 1.22 * 1.22,
		0.0001,
		"cycle-6 extra guardian HP")


## From cycle 4 the field also lasts a long time even against finished firepower. Keep the early contract and
## pin here whether only late-game becomes a wall.
func _test_guardian_late_cycle_wall() -> void:
	const LATE_CYCLE: int = 6
	var kind: SpiritKind = (
		load("res://resources/guardian_field.tres") as SpiritKind).duplicate()
	var pressure: float = SpiritKind.cycle_pressure(LATE_CYCLE)
	var budget_floor: float = SpiritKind.guardian_budget_floor(LATE_CYCLE)
	kind.guardian_burst_fraction = maxf(
		kind.guardian_burst_fraction / pressure, budget_floor)
	kind.guardian_sustain_fraction = maxf(
		kind.guardian_sustain_fraction / pressure, budget_floor)
	var theoretical: float = (1.0 - kind.guardian_burst_fraction) \
		/ kind.guardian_sustain_fraction
	_expect_between(theoretical, 32.0, 34.0, "cycle-6 field ratio-based TTK wall")

	var toughness: float = pow(1.35, 2.0) * pow(1.58, 3.0) \
		* SpiritKind.guardian_toughness_scale(LATE_CYCLE)
	var spirit: Node2D = _spawn_kind(kind, toughness, LATE_CYCLE)
	_expect_equal(
		int(spirit.get("_health")),
		maxi(int(round(float(kind.health) * toughness)), 1),
		"cycle-6 field uses guardian-only HP scaling")
	spirit.call("take_damage", SATURATED_DAMAGE, Vector2.ZERO)
	var elapsed: float = 0.0
	while not bool(spirit.get("_perishing")) and elapsed < 40.0:
		spirit.call("_physics_process", STEP_SECONDS)
		elapsed += STEP_SECONDS
	_expect_true(
		bool(spirit.get("_perishing")), "cycle-6 field still dies from queued damage")
	_expect_between(elapsed, 32.0, 34.5, "cycle-6 field measured max-burst TTK wall")
	spirit.free()


func _test_guardian_immediate_lethal_once() -> void:
	var spirit: Node2D = _spawn("res://resources/guardian_field.tres")
	var perished_count: Array[int] = [0]
	spirit.connect(
		"perished",
		func(_kind: SpiritKind, _at: Vector2, _elite: bool) -> void:
			perished_count[0] += 1)
	# Lower HP with single hits slower than the sustained budget, then the last hit once the budget is full
	# becomes immediately lethal inside `_queue_guardian_damage()`.
	while int(spirit.get("_health")) > 70:
		spirit.call("take_damage", 70, Vector2.ZERO)
		spirit.call("_physics_process", 0.6)
	spirit.call("take_damage", 70, Vector2.ZERO)
	_expect_true(
		bool(spirit.get("_perishing")),
		"immediate lethal kill inside the guardian budget")
	_expect_equal(
		perished_count[0], 1,
		"guardian instant-lethal perished signal once")
	spirit.call("_perish")
	_expect_equal(
		perished_count[0], 1,
		"duplicate despawn calls also do not re-emit perished")
	spirit.free()


func _test_debug_slay_bypass() -> void:
	if not OS.is_debug_build():
		return
	var spirit: Node2D = _spawn("res://resources/guardian_field.tres")
	spirit.call("debug_slay")
	_expect_true(
		bool(spirit.get("_perishing")),
		"debug cycle check explicitly skips live damage budget")
	spirit.free()


func _spawn(resource_path: String, toughness: float = CYCLE_THREE_TOUGHNESS) -> Node2D:
	return _spawn_kind(
		(load(resource_path) as SpiritKind).duplicate(), toughness)


func _spawn_kind(
		kind: SpiritKind,
		toughness: float = CYCLE_THREE_TOUGHNESS,
		cycle: int = 3) -> Node2D:
	var spirit: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	spirit.set("kind", kind)
	spirit.set("toughness", toughness)
	spirit.set("guardian_cycle", cycle)
	spirit.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(spirit)
	spirit.set("_materialized", true)
	return spirit


func _finish() -> void:
	if _failed > 0:
		printerr("guardian firepower-balance test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("guardian firepower-balance test passed — ", _checked, " case(s)")
	quit(0)


func _expect_between(actual: float, minimum: float, maximum: float, label: String) -> void:
	_checked += 1
	if actual >= minimum and actual <= maximum:
		return
	_failed += 1
	printerr(
		"  FAIL ", label, " — expected=", minimum, "..", maximum, " actual=", actual)


func _expect_approx(
		actual: float,
		expected: float,
		tolerance: float,
		label: String,
	) -> void:
	_checked += 1
	if absf(actual - expected) <= tolerance:
		return
	_failed += 1
	printerr(
		"  FAIL ", label, " — expected=", expected, "±", tolerance,
		" actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)
