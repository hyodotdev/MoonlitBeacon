class_name MissileProgression
extends RefCounted

## Single growth curve for moon wheels and missiles fed by kill loot.
##
## Kept apart from relic cards so the first upgrade is guaranteed to show on
## time. The first core is two regular spirits; after that each rank needs
## 3–6 kill-value. When the volley widens, shots do not clone original damage
## — the rank's total damage budget is split, so early power does not explode.

const MAX_POWER: int = 8
const HOMING_AT: int = 3
const THRESHOLDS: Array[int] = [2, 3, 4, 4, 5, 5, 6, 6]
const VOLLEYS: Array[int] = [1, 2, 3, 3, 4, 5, 6, 7, 8]
## Gentle curve that at base damage 5 becomes 5→7→9→10→13→15→18→22→26.
## A separate table means changing shot count cannot accidentally explode damage too.
const DAMAGE_SCALES: Array[float] = [
	1.0, 1.4, 1.8, 2.0, 2.6, 3.0, 3.6, 4.4, 5.2,
]


static func threshold(power: int) -> int:
	return THRESHOLDS[clampi(power, 0, MAX_POWER - 1)]


static func kill_value(elite: bool, guardian: bool) -> int:
	if guardian:
		return 10
	return 3 if elite else 1


## Progress restored when recovering a core ejected by a hit.
##
## Giving a whole rank back meant picking the core up again made a hit a
## 1-second detour with no weight. Like recovering medals in a shooter, only
## **70% of the next rank's requirement** is returned; the rest must be fought
## for. At every rank that is less than the requirement, so recovery alone
## cannot refill the lost rank.
const EJECT_RECOVERY_RATIO: float = 0.7


static func eject_recovery_progress(power: int) -> int:
	return maxi(
		int(floor(float(threshold(power)) * EJECT_RECOVERY_RATIO)),
		1)


static func volley_for_power(power: int) -> int:
	return VOLLEYS[clampi(power, 0, MAX_POWER)]


static func is_homing(power: int) -> bool:
	return power >= HOMING_AT


## `base_damage` already includes hero, relic, HP, and moon-ember multipliers.
##
## The core-rank stair and twin-moon-wheel card multiplier are computed
## separately. Extra shots do not clone damage, and even one card always raises
## damage by at least 1.
static func damage_budget(base_damage: int, power: int, count_cards: int = 0) -> int:
	var safe_power: int = clampi(power, 0, MAX_POWER)
	var safe_cards: int = maxi(count_cards, 0)
	var safe_base: int = maxi(base_damage, 1)
	var stage_budget: int = maxi(
		int(round(float(safe_base) * DAMAGE_SCALES[safe_power])),
		safe_base + safe_power)
	var with_cards: int = maxi(
		int(round(float(stage_budget) * pow(1.18, float(safe_cards)))),
		stage_budget + safe_cards)
	return maxi(with_cards, volley_for_power(safe_power))


## Split integer damage fairly across the volley. Each shot is at least 1, so
## if the budget arrives smaller than the shot count the count is raised to
## match; otherwise the sum equals `total_damage`.
static func lane_damages(total_damage: int, volley: int) -> PackedInt32Array:
	var count: int = maxi(volley, 1)
	var total: int = maxi(total_damage, count)
	var each: int = total / count
	var remainder: int = total % count
	var result: PackedInt32Array = PackedInt32Array()
	for index in count:
		result.append(each + (1 if index < remainder else 0))
	return result


## A homing volley uses shot 0 as the center meteor that keeps the real aim target.
##
## Assign damage that is never weaker than power-2's straight center shot first,
## then raise center damage by 1 per later core. Leftover budget splits across
## side meteors within 1, so a wider volley does not clone total damage and
## does not reverse-power at close range.
static func guided_lane_damages(
		base_damage: int, power: int, count_cards: int = 0) -> PackedInt32Array:
	var safe_power: int = clampi(power, 0, MAX_POWER)
	var volley: int = volley_for_power(safe_power)
	var total: int = damage_budget(base_damage, safe_power, count_cards)
	if safe_power < HOMING_AT:
		return straight_lane_damages(total, volley)

	var maximum_anchor: int = total - (volley - 1)
	# Guarantee line: power-2's real center shot plus 1 per later core.
	# Dump leftover budget into the center and even 10× attack leaves side
	# meteors as damage-1 decoration forever. Growth above the guarantee is
	# spread across the sides so several missiles feel stronger together.
	var straight_budget: int = damage_budget(base_damage, HOMING_AT - 1, count_cards)
	var straight_center: int = straight_lane_damages(
		straight_budget, volley_for_power(HOMING_AT - 1))[0]
	var anchor_floor: int = straight_center + safe_power - (HOMING_AT - 1)
	var anchor: int = mini(anchor_floor, maximum_anchor)
	var result: PackedInt32Array = PackedInt32Array([anchor])
	if volley <= 1:
		return result
	var sides: PackedInt32Array = lane_damages(total - anchor, volley - 1)
	result.append_array(sides)
	return result


## Before homing, a straight volley's center shot hits the real aim target and
## extras can miss off the fan. Leave as much budget as possible on the center
## and give extras at least 1 each, so picking up a core cannot reverse-power
## single-target damage.
static func straight_lane_damages(
		total_damage: int, volley: int) -> PackedInt32Array:
	var count: int = maxi(volley, 1)
	var total: int = maxi(total_damage, count)
	var result: PackedInt32Array = PackedInt32Array()
	result.append(total - (count - 1))
	for index in count - 1:
		result.append(1)
	return result
