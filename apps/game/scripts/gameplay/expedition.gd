class_name Expedition
extends RefCounted

## The shape of a run once one loop is not the whole game.
##
## A cycle is three places, three beacons and a guardian. This file decides **which
## places, which guardian, how hard, and what is different this time**, and does it with
## plain functions of `(run seed, cycle, zone)`. Nothing here touches the scene tree, so
## every rule can be tested without running a fight, and the same run always answers the
## same way. The arena only asks.
##
## Cycles 1 to `OFFICIAL_WIN_CYCLE` are the shipped game and their numbers are pinned by
## tests. Everything that changes the feel of the run is either **additive** or starts at
## `Depth 1`, the first cycle past the official win.

## Closing this cycle and returning is the official win. Going on is the endless stretch.
const OFFICIAL_WIN_CYCLE: int = 8

## Places. The index in this table is the terrain id everywhere else, so append, never reorder.
##
## `from_cycle` is the first cycle a terrain may be offered at a fork. The first three are
## the classic route; Frost Pass and Mirewood Marsh arrive at cycle 3 and Moonlit Ruins at 4,
## so the first loops stay simple and the run keeps opening new places as it goes on.
## `guardians` is the roster by tier. The classic three meet the first at cycle 1 and the second
## from then on; the later places meet the first form the first time and the second every time after.
const TERRAINS: Array[Dictionary] = [
	{
		"id": "forest",
		"room": "res://resources/rooms/forest.tres",
		"name": "WORLD_FOREST",
		"emblem": Color(0.5, 0.92, 0.66, 1.0),
		"from_cycle": 1,
		"guardian": "res://resources/guardian_forest.tres",
		"guardians": [
			"res://resources/guardian_forest.tres",
			"res://resources/guardian_forest_thorn.tres",
		],
	},
	{
		"id": "field",
		"room": "res://resources/rooms/field.tres",
		"name": "WORLD_FIELD",
		"emblem": Color(0.62, 0.8, 1.0, 1.0),
		"from_cycle": 1,
		"guardian": "res://resources/guardian_field.tres",
		"guardians": [
			"res://resources/guardian_field.tres",
			"res://resources/guardian_field_storm.tres",
		],
	},
	{
		"id": "camp",
		"room": "res://resources/rooms/camp.tres",
		"name": "WORLD_CAMP",
		"emblem": Color(1.0, 0.72, 0.4, 1.0),
		"from_cycle": 1,
		"guardian": "res://resources/guardian_camp.tres",
		"guardians": [
			"res://resources/guardian_camp.tres",
			"res://resources/guardian_camp_siege.tres",
		],
	},
	{
		"id": "frost",
		"room": "res://resources/rooms/frost.tres",
		"name": "WORLD_FROST",
		"emblem": Color(0.78, 0.9, 1.0, 1.0),
		"from_cycle": 3,
		"guardian": "res://resources/guardian_frost.tres",
		"guardians": [
			"res://resources/guardian_frost.tres",
			"res://resources/guardian_frost_rime.tres",
		],
	},
	{
		"id": "marsh",
		"room": "res://resources/rooms/marsh.tres",
		"name": "WORLD_MARSH",
		"emblem": Color(0.55, 0.95, 0.7, 1.0),
		"from_cycle": 3,
		"guardian": "res://resources/guardian_marsh.tres",
		"guardians": [
			"res://resources/guardian_marsh.tres",
			"res://resources/guardian_marsh_glow.tres",
		],
	},
	{
		"id": "ruins",
		"room": "res://resources/rooms/ruins.tres",
		"name": "WORLD_RUINS",
		"emblem": Color(0.86, 0.78, 1.0, 1.0),
		"from_cycle": 4,
		"guardian": "res://resources/guardian_ruins.tres",
		"guardians": [
			"res://resources/guardian_ruins.tres",
			"res://resources/guardian_ruins_halo.tres",
		],
	},
]

## How many terrains make the classic route. Cycle 1, and any state a test or a store
## capture builds by hand, walks these three in rotation.
const CLASSIC_TERRAINS: int = 3

## Forks open from this cycle. Cycle 1 teaches the loop with one gate.
const FORK_FROM_CYCLE: int = 2


## How far past the official win. 0 through cycle 8.
static func depth(cycle: int) -> int:
	return maxi(cycle - OFFICIAL_WIN_CYCLE, 0)


# --- Difficulty ---------------------------------------------------------------------

## Mob HP multiplier past the official win.
##
## The shipped curve is x1.58 a cycle from cycle 4. That outruns anything the player can
## stack in a few cycles and turns the endless stretch into a wall. Past cycle 8 it grows
## at this rate instead: the relics the player keeps collecting can keep pace, so the
## stretch stays a game you can keep winning, only a little harder each time.
const DEPTH_TOUGHNESS_GROWTH: float = 1.22

## The same for a guardian's own HP on top of the mob multiplier (x1.22 a cycle until 8).
const DEPTH_GUARDIAN_GROWTH: float = 1.10

## Elite chance climbs 8% a cycle to 30% in the shipped game; the endless stretch keeps
## climbing, slowly, to this ceiling.
const ELITE_CEILING: float = 0.45
const ELITE_DEPTH_STEP: float = 0.02


## Measurement only: `tools/soak_run.gd` sets this to replay the 2.1.0 curve (x1.58 past cycle 8)
## next to the new one. Nothing in the game sets it.
static var shipped_curve: bool = false


## How tough this cycle's ordinary spirits are.
static func toughness(cycle: int) -> float:
	var safe: int = maxi(cycle, 1)
	if safe <= 3:
		return pow(1.35, float(safe - 1))
	if safe <= OFFICIAL_WIN_CYCLE or shipped_curve:
		return pow(1.35, 2.0) * pow(1.58, float(safe - 3))
	return toughness(OFFICIAL_WIN_CYCLE) \
		* pow(DEPTH_TOUGHNESS_GROWTH, float(safe - OFFICIAL_WIN_CYCLE))


## The extra multiplier a guardian's HP takes on top of `toughness()`.
static func guardian_scale(cycle: int) -> float:
	var safe: int = maxi(cycle, 1)
	if safe <= 3:
		return 1.0
	if safe <= OFFICIAL_WIN_CYCLE or shipped_curve:
		return pow(1.22, float(safe - 3))
	return pow(1.22, float(OFFICIAL_WIN_CYCLE - 3)) \
		* pow(DEPTH_GUARDIAN_GROWTH, float(safe - OFFICIAL_WIN_CYCLE))


## Base chance an elite is mixed in, before terrain and omens.
static func elite_chance(cycle: int) -> float:
	if cycle < 2:
		return 0.0
	var chance: float = minf(0.08 * float(cycle - 1), 0.3)
	if depth(cycle) > 0:
		chance = minf(0.3 + ELITE_DEPTH_STEP * float(depth(cycle)), ELITE_CEILING)
	return chance


# --- Places -------------------------------------------------------------------------

## The classic route: the three original terrains in rotation, one step further each cycle.
static func classic_route(cycle: int) -> Array[int]:
	var route: Array[int] = []
	for zone in 3:
		route.append((maxi(cycle, 1) - 1 + zone) % CLASSIC_TERRAINS)
	return route


## Terrains that may be offered at this cycle.
static func pool(cycle: int) -> Array[int]:
	var open: Array[int] = []
	for index in TERRAINS.size():
		if int(TERRAINS[index]["from_cycle"]) <= cycle:
			open.append(index)
	return open


## Whether the gates are forks this cycle.
static func forks_open(cycle: int) -> bool:
	return cycle >= FORK_FROM_CYCLE


## The terrain a cycle opens in. It is never the terrain of the guardian just beaten, so a
## fresh loop never starts where the last one ended.
static func start_terrain(run_seed: int, cycle: int, previous_guardian_terrain: int) -> int:
	var open: Array[int] = pool(cycle)
	var choices: Array[int] = []
	for index in open:
		if index != previous_guardian_terrain:
			choices.append(index)
	if choices.is_empty():
		return open[0]
	return choices[_draw(run_seed, cycle, 0, 11).randi_range(0, choices.size() - 1)]


## The two places a gate leads to. Both differ from where you stand, and from each other.
##
## `route` holds the terrains of this cycle so far (`-1` for a zone not chosen yet). A place
## already visited this cycle is only offered again when there is nothing else to offer,
## so a cycle with six terrains rarely repeats one.
static func gate_options(
		run_seed: int, cycle: int, zone: int, route: Array[int]) -> Array[int]:
	var here: int = route[zone]
	var open: Array[int] = pool(cycle)
	var fresh: Array[int] = []
	var seen: Array[int] = []
	for index in open:
		if index == here:
			continue
		if route.has(index):
			seen.append(index)
		else:
			fresh.append(index)
	var rng: RandomNumberGenerator = _draw(run_seed, cycle, zone + 1, 23)
	var picked: Array[int] = []
	while picked.size() < 2 and not (fresh.is_empty() and seen.is_empty()):
		var source: Array[int] = fresh if not fresh.is_empty() else seen
		picked.append(source.pop_at(rng.randi_range(0, source.size() - 1)))
	return picked


# --- Guardian mutations -------------------------------------------------------------

## What a guardian can gain. Each one is a small, readable rule that hooks the move
## machine every guardian already has, so it works on any style.
enum Mutation {
	ECHO,     ## every volley repeats once, a beat later, turned a little
	SPIRAL,   ## the safe gap of each volley moves a little every time
	SUMMONER, ## at two thirds and one third health it calls a small pack
	FRENZY,   ## the whole tempo is faster
	AEGIS,    ## shield rings: it cannot be hurt for a few seconds while one shows
	METEORS,  ## marked circles rain around you while it rests, then burst
}

const MUTATION_COUNT: int = 6
const MAX_MUTATIONS: int = 4
## Every fifth Depth the guardian is a Moonless Trial.
const TRIAL_EVERY: int = 5


static func mutation_name_key(mutation: int) -> String:
	return "MUTATION_" + str(Mutation.keys()[mutation])


## Every fifth Depth is a Moonless Trial: more mutations, more loot.
static func is_trial(cycle: int) -> bool:
	var deep: int = depth(cycle)
	return deep > 0 and deep % TRIAL_EVERY == 0


## How many mutations a guardian carries at this cycle.
static func mutation_slots(cycle: int) -> int:
	var slots: int = 0
	if cycle >= 15:
		slots = 4
	elif cycle >= 11:
		slots = 3
	elif cycle >= 8:
		slots = 2
	elif cycle >= 5:
		slots = 1
	if is_trial(cycle):
		slots += 1
	return mini(slots, MAX_MUTATIONS)


## The mutations one guardian carries, drawn from the seed and never repeating.
static func mutations_for(run_seed: int, cycle: int, terrain: int) -> Array[int]:
	var slots: int = mutation_slots(cycle)
	var bag: Array[int] = []
	for index in MUTATION_COUNT:
		bag.append(index)
	var rng: RandomNumberGenerator = _draw(run_seed, cycle, terrain, 37)
	var chosen: Array[int] = []
	while chosen.size() < slots and not bag.is_empty():
		chosen.append(bag.pop_at(rng.randi_range(0, bag.size() - 1)))
	return chosen


# --- Omens --------------------------------------------------------------------------

## A rule that changes one thing about a zone, shown at the gate so it is part of the
## choice. Some are gifts. The numbers are multipliers unless noted.
enum Omen {
	BLOOD_MOON,     ## more elites, more embers
	SWARM_TIDE,     ## spirits arrive faster, and fall faster
	IRON_NIGHT,     ## fewer spirits, each tougher
	LANTERN_BLOOM,  ## beacons kindle faster
	DEW_RAIN,       ## moon dew falls more often
	GALE,           ## spirits move faster
}

const OMEN_COUNT: int = 6

## Keys: `hp`, `spawn` (interval multiplier; lower is faster), `cap` (spirits added; the arena
## never lets the total pass the mobile ceiling, so an omen can only take spirits away),
## `elite` (chance added), `ember` (Moonfire charge), `speed`, `dew`, `beacon` (seconds
## multiplier; lower is faster).
const OMEN_EFFECTS: Array[Dictionary] = [
	{"hp": 1.0, "spawn": 1.0, "cap": 0, "elite": 0.14, "ember": 1.5, "speed": 1.0, "dew": 1.0, "beacon": 1.0},
	{"hp": 0.65, "spawn": 0.72, "cap": 0, "elite": 0.0, "ember": 1.0, "speed": 1.0, "dew": 1.0, "beacon": 1.0},
	{"hp": 1.45, "spawn": 1.3, "cap": -6, "elite": 0.0, "ember": 1.0, "speed": 1.0, "dew": 1.0, "beacon": 1.0},
	{"hp": 1.0, "spawn": 1.0, "cap": 0, "elite": 0.0, "ember": 1.0, "speed": 1.0, "dew": 1.0, "beacon": 0.6},
	{"hp": 1.0, "spawn": 1.0, "cap": 0, "elite": 0.0, "ember": 1.0, "speed": 1.0, "dew": 2.2, "beacon": 1.0},
	{"hp": 1.0, "spawn": 1.0, "cap": 0, "elite": 0.0, "ember": 1.0, "speed": 1.16, "dew": 1.0, "beacon": 1.0},
]


static func omen_name_key(omen: int) -> String:
	return "OMEN_" + str(Omen.keys()[omen])


static func omen_desc_key(omen: int) -> String:
	return omen_name_key(omen) + "_DESC"


## Omens a zone carries: none before Depth 1, one to Depth 4, two after.
static func omen_slots(cycle: int) -> int:
	var deep: int = depth(cycle)
	if deep <= 0:
		return 0
	return 1 if deep < 5 else 2


static func omens_for(run_seed: int, cycle: int, zone: int) -> Array[int]:
	var slots: int = omen_slots(cycle)
	var bag: Array[int] = []
	for index in OMEN_COUNT:
		bag.append(index)
	var rng: RandomNumberGenerator = _draw(run_seed, cycle, zone, 53)
	var chosen: Array[int] = []
	while chosen.size() < slots and not bag.is_empty():
		chosen.append(bag.pop_at(rng.randi_range(0, bag.size() - 1)))
	return chosen


## What a set of omens does together: multipliers multiply, added amounts add.
static func omen_effects(omens: Array) -> Dictionary:
	var total: Dictionary = {
		"hp": 1.0, "spawn": 1.0, "cap": 0, "elite": 0.0,
		"ember": 1.0, "speed": 1.0, "dew": 1.0, "beacon": 1.0,
	}
	for omen in omens:
		var effect: Dictionary = OMEN_EFFECTS[int(omen)]
		for key in ["hp", "spawn", "ember", "speed", "dew", "beacon"]:
			total[key] = float(total[key]) * float(effect[key])
		total["cap"] = int(total["cap"]) + int(effect["cap"])
		total["elite"] = float(total["elite"]) + float(effect["elite"])
	return total


# --- Seeding ------------------------------------------------------------------------

## One deterministic stream per question. `salt` keeps two questions asked with the same
## numbers (a gate and a mutation, say) from ever sharing an answer.
static func _draw(run_seed: int, cycle: int, key: int, salt: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([run_seed, cycle, key, salt])
	return rng
