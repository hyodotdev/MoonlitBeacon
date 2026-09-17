extends SceneTree

## Pure numeric contract for kill → core → volley growth.

const PROGRESSION: Script = preload(
	"res://scripts/gameplay/missile_progression.gd")

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	var thresholds: Array[int] = [2, 3, 4, 4, 5, 5, 6, 6]
	var cumulative: Array[int] = [2, 5, 9, 13, 18, 23, 29, 35]
	var sum: int = 0
	for power in thresholds.size():
		_expect_equal(
			PROGRESSION.threshold(power),
			thresholds[power],
			"missile power %d next-core requirement" % power)
		sum += PROGRESSION.threshold(power)
		_expect_equal(
			sum,
			cumulative[power],
			"missile power %d cumulative normal-kill contract" % (power + 1))
	_expect_equal(PROGRESSION.kill_value(false, false), 1, "normal spirit value 1")
	_expect_equal(PROGRESSION.kill_value(true, false), 3, "elite spirit value 3")
	_expect_equal(PROGRESSION.kill_value(false, true), 10, "guardian value 10")

	# Recovery returned by a stray core after a hit. Floor of 70% of the requirement — never the full amount.
	var recovery: Array[int] = [1, 2, 2, 2, 3, 3, 4, 4]
	for power in recovery.size():
		_expect_equal(
			PROGRESSION.eject_recovery_progress(power),
			recovery[power],
			"power %d stray-recovery returned progress" % power)
		_expect_true(
			PROGRESSION.eject_recovery_progress(power)
				< PROGRESSION.threshold(power),
			"power %d stray recovery is less than the requirement" % power)

	var expected: Array[int] = [1, 2, 3, 3, 4, 5, 6, 7, 8]
	for power in expected.size():
		_expect_equal(
			PROGRESSION.volley_for_power(power),
			expected[power],
			"missile power %d volley count" % power)
	_expect_false(PROGRESSION.is_homing(2), "straight moon discs through power 2")
	_expect_true(PROGRESSION.is_homing(3), "homing missiles from power 3")

	var previous: int = 0
	var previous_straight_center: int = 0
	var previous_guided_anchor: int = 0
	var expected_budgets: Array[int] = [5, 7, 9, 10, 13, 15, 18, 22, 26]
	var expected_straight_centers: Array[int] = [5, 6, 7]
	var expected_guided_anchors: Array[int] = [8, 9, 10, 11, 12, 13]
	var expected_guided_lanes: Array[PackedInt32Array] = [
		PackedInt32Array([8, 1, 1]),
		PackedInt32Array([9, 2, 1, 1]),
		PackedInt32Array([10, 2, 1, 1, 1]),
		PackedInt32Array([11, 2, 2, 1, 1, 1]),
		PackedInt32Array([12, 2, 2, 2, 2, 1, 1]),
		PackedInt32Array([13, 2, 2, 2, 2, 2, 2, 1]),
	]
	for power in PROGRESSION.MAX_POWER + 1:
		var budget: int = PROGRESSION.damage_budget(5, power)
		_expect_equal(
			budget,
			expected_budgets[power],
			"power %d base-damage 5 total-budget contract" % power)
		_expect_true(budget >= previous, "power %d total damage does not drop" % power)
		var volley: int = PROGRESSION.volley_for_power(power)
		var lanes: PackedInt32Array
		if power < PROGRESSION.HOMING_AT:
			lanes = PROGRESSION.straight_lane_damages(budget, volley)
			_expect_equal(
				lanes[0],
				expected_straight_centers[power],
				"power %d straight center-shot damage contract" % power)
			if power > 0:
				_expect_true(
					lanes[0] >= previous_straight_center + 1,
					"power %d center shot grows by at least 1 per core" % power)
			previous_straight_center = lanes[0]
		else:
			lanes = PROGRESSION.guided_lane_damages(5, power)
			_expect_equal(
				lanes,
				expected_guided_lanes[power - PROGRESSION.HOMING_AT],
				"power %d guided volley damage contract" % power)
			_expect_equal(
				lanes[0],
				expected_guided_anchors[power - PROGRESSION.HOMING_AT],
				"power %d guided anchor-shot damage contract" % power)
			_expect_true(
				lanes[0] >= previous_straight_center + 1,
				"power %d first guided anchor also keeps core growth" % power)
			if previous_guided_anchor > 0:
				_expect_true(
					lanes[0] >= previous_guided_anchor + 1,
					"power %d guided anchor also grows by at least 1 per core" % power)
			previous_guided_anchor = lanes[0]
		_expect_equal(
			_sum(lanes),
			maxi(budget, lanes.size()),
			"power %d per-shot damage sum matches the total budget" % power)
		if power >= PROGRESSION.HOMING_AT:
			_expect_true(
				_max(PackedInt32Array(Array(lanes).slice(1)))
					- _min(PackedInt32Array(Array(lanes).slice(1))) <= 1,
				"power %d guided side-meteor damage spread is at most 1" % power)
		else:
			for lane in range(1, lanes.size()):
				_expect_equal(
					lanes[lane], 1,
					"power %d extra straight shots use the minimum damage budget" % power)
		previous = budget

	# When base attack grows, side missiles grow with it enough to kill real late-game enemies.
	# Blocks the regression that dumps the budget into the center shot and leaves the rest as damage-1 decoys.
	var high_damage_lanes: PackedInt32Array = PROGRESSION.guided_lane_damages(
		50, PROGRESSION.MAX_POWER)
	_expect_equal(high_damage_lanes[0], 94, "high-damage power 8 anchor grows gently")
	_expect_true(
		_min(PackedInt32Array(Array(high_damage_lanes).slice(1))) >= 23,
		"high-damage power 8 side missiles also deal real damage")
	_expect_true(
		_sum(PackedInt32Array(Array(high_damage_lanes).slice(1)))
			> high_damage_lanes[0],
		"high-damage power 8 volley as a whole out-damages the center shot")

	_expect_true(
		PROGRESSION.damage_budget(5, 2, 1)
			> PROGRESSION.damage_budget(5, 2, 0),
		"Twin Disc cards raise total damage budget instead of cloning shots")
	for cards in 4:
		var card_curve_previous: int = 0
		for power in PROGRESSION.MAX_POWER + 1:
			var card_budget: int = PROGRESSION.damage_budget(5, power, cards)
			_expect_true(
				card_budget >= card_curve_previous,
				"Twin Disc ×%d power %d total damage does not drop" % [
					cards, power])
			card_curve_previous = card_budget

	# Even when base damage and card mix change, the actual aiming lane does not drop
	# after picking up a core. Blocks implementations that only match one default table.
	for base_damage in range(1, 21):
		for cards in 4:
			var previous_anchor: int = 0
			for power in PROGRESSION.MAX_POWER + 1:
				var guided: PackedInt32Array = PROGRESSION.guided_lane_damages(
					base_damage, power, cards)
				_expect_true(
					guided[0] >= previous_anchor,
					"base %d cards %d power %d aim damage does not drop" % [
						base_damage, cards, power])
				_expect_equal(
					_sum(guided),
					PROGRESSION.damage_budget(base_damage, power, cards),
					"base %d cards %d power %d total budget preserved" % [
						base_damage, cards, power])
				previous_anchor = guided[0]

	if _failed > 0:
		printerr("missile-growth test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("missile-growth test passed — ", _checked, " case(s)")
	quit(0)


func _sum(values: PackedInt32Array) -> int:
	var result: int = 0
	for value in values:
		result += value
	return result


func _min(values: PackedInt32Array) -> int:
	var result: int = values[0]
	for value in values:
		result = mini(result, value)
	return result


func _max(values: PackedInt32Array) -> int:
	var result: int = values[0]
	for value in values:
		result = maxi(result, value)
	return result


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
