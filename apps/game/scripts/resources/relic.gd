class_name Relic
extends Resource

## One relic. Pick one of three when a beacon lights.
##
## Same pattern as `SpiritKind` and `RoomKind` — **one `.tres` is one relic,
## and adding a new relic does not grow the code.**
##
## This is the answer to "do it once and done." Lighting a beacon used to
## raise one number; now every lighting is a fork. Three picks per run, so
## each run is a different character.

## What it changes. The arena reads this and feeds it to the player.
enum Effect {
	ATTACK_RANGE,      ## how far the blade reaches
	ATTACK_SPEED,      ## swing interval shortens
	ATTACK_DAMAGE,     ## damage per hit
	ATTACK_ARC,        ## the fan widens
	MOVE_SPEED,        ## walk speed
	MAX_HEALTH,        ## heart cells
	DASH_COOLDOWN,     ## dash returns faster
	INVULNERABLE,      ## invuln time after a hit
	DEW_CHANCE,        ## chance moon dew drops
	BEACON_HEAL,       ## heal when lighting the first beacon of each cycle
	ARROW_COUNT,       ## total damage budget of the moon-wheel / missile volley rises
	ARROW_PIERCE,      ## arrows pierce enemies
	ARROW_SPEED,       ## arrows fire more often
	ARROW_DAMAGE,      ## one arrow hits harder

	# The next two do not change a number — they **add a weapon.**
	#
	# The first fourteen only grow an attack that already exists, so the screen
	# looked the same no matter how strong. Survivor growth comes from more
	# weapons making the screen louder.
	MOON_RING,         ## orbs that orbit. stacking adds more
	MOON_RIPPLE,       ## ripple that spreads every way. stacking is wider and more often
}

## Relic bundle that makes the same combat look.
##
## Do not write the path again on the relic resource. Put effect and path on
## both sides and they drift when adding a relic or moving an effect. Every
## consumer uses only the helpers below.
enum Family {
	NONE,
	STARFALL,          ## learn all four moon-wheel effects and invest six times
	FULL_MOON,         ## learn all four slash effects and invest six times
	MOON_DANCE,        ## learn moon ring and ripple and invest five times
}

## Evolution does not open from “a few different cards” alone.
##
## Starfall and Full Moon used to complete at 3 cards, Moon Dance at 2, so the
## first 7–12 kills finished them. The screen hit final form before a new
## weapon was even learned, and the middle of growth was gone. After seeing
## every component, a few more investments are still required before the
## final form opens.
const DEFAULT_EVOLVE_AT: int = 6
const MOON_DANCE_EVOLVE_AT: int = 5
const RESONANCE_DISTINCT: int = 2


## Which evolution path one effect belongs to.
static func family_of_effect(effect: Effect) -> Family:
	match effect:
		Effect.ARROW_COUNT, Effect.ARROW_PIERCE, Effect.ARROW_SPEED, Effect.ARROW_DAMAGE:
			return Family.STARFALL
		Effect.ATTACK_RANGE, Effect.ATTACK_SPEED, Effect.ATTACK_DAMAGE, Effect.ATTACK_ARC:
			return Family.FULL_MOON
		Effect.MOON_RING, Effect.MOON_RIPPLE:
			return Family.MOON_DANCE
		_:
			return Family.NONE


static func family_of_relic(relic: Relic) -> Family:
	return Family.NONE if relic == null else family_of_effect(relic.effect)


## Effects that make up the path. A new array every call so the caller cannot mutate it.
static func family_effects(family: Family) -> Array[Effect]:
	match family:
		Family.STARFALL:
			return [
				Effect.ARROW_COUNT, Effect.ARROW_PIERCE,
				Effect.ARROW_SPEED, Effect.ARROW_DAMAGE,
			]
		Family.FULL_MOON:
			return [
				Effect.ATTACK_RANGE, Effect.ATTACK_SPEED,
				Effect.ATTACK_DAMAGE, Effect.ATTACK_ARC,
			]
		Family.MOON_DANCE:
			return [Effect.MOON_RING, Effect.MOON_RIPPLE]
		_:
			return []


## **Total investments** needed for the final form.
static func family_evolve_at(family: Family) -> int:
	return MOON_DANCE_EVOLVE_AT if family == Family.MOON_DANCE \
		else DEFAULT_EVOLVE_AT


## How many distinct components must be learned at least once before the final form.
static func family_required_distinct(family: Family) -> int:
	match family:
		Family.STARFALL, Family.FULL_MOON:
			return 4
		Family.MOON_DANCE:
			return 2
		_:
			return 0


static func family_name_key(family: Family) -> String:
	match family:
		Family.STARFALL:
			return "EVOLUTION_STARFALL"
		Family.FULL_MOON:
			return "EVOLUTION_FULL_MOON"
		Family.MOON_DANCE:
			return "EVOLUTION_MOON_DANCE"
		_:
			return "EVOLUTION_NONE"


static func family_accent(family: Family) -> Color:
	match family:
		Family.STARFALL:
			return Color(0.68, 0.88, 1.0, 1.0)
		Family.FULL_MOON:
			return Color(1.0, 0.82, 0.46, 1.0)
		Family.MOON_DANCE:
			return Color(0.82, 0.72, 1.0, 1.0)
		_:
			return Color(0.82, 0.84, 0.9, 1.0)


## Count distinct effects of this path in the live held array.
##
## The same `Relic` reference twice still enters the effect dictionary once.
## Even if a card later grants several stacks, evolution material is one kind.
static func family_distinct(relics: Array, family: Family) -> int:
	var found: Dictionary = {}
	for item in relics:
		if not item is Relic:
			continue
		var relic: Relic = item as Relic
		if family_of_effect(relic.effect) == family:
			found[relic.effect] = true
	return found.size()


## Count total stacks invested in this path in the live held array.
static func family_total(relics: Array, family: Family) -> int:
	var total: int = 0
	for item in relics:
		if item is Relic and family_of_effect((item as Relic).effect) == family:
			total += 1
	return total


static func family_evolved(relics: Array, family: Family) -> bool:
	var state: Dictionary = family_state(relics, family)
	return bool(state["evolved"])


## Two-effect resonance that opens before the final evolution.
##
## Stacking the same effect twice is a damage bump, not a new combo. Resonance
## needs two different effects; Moon Dance has only two components, so that
## means both ring and ripple. NONE is not a valid attack path, so always false.
static func family_resonant(relics: Array, family: Family) -> bool:
	if family == Family.NONE:
		return false
	return family_distinct(relics, family) >= RESONANCE_DISTINCT


## Full state of one path, used to compare before/after pick, hit, and recover.
static func family_state(relics: Array, family: Family) -> Dictionary:
	var distinct: int = family_distinct(relics, family)
	var total: int = family_total(relics, family)
	var evolve_at: int = family_evolve_at(family)
	var required_distinct: int = family_required_distinct(family)
	var resonant: bool = family_resonant(relics, family)
	var evolved: bool = distinct >= required_distinct and total >= evolve_at
	# Even at full total, a missing component must not look complete as 6/6.
	var progress: int = mini(total, evolve_at)
	if distinct < required_distinct:
		progress = mini(progress, maxi(evolve_at - 1, 0))
	return {
		"family": family,
		"distinct": distinct,
		"required_distinct": required_distinct,
		"total": total,
		"progress": progress,
		"evolve_at": evolve_at,
		"resonant": resonant,
		"evolved": evolved,
		"tier": 1 + maxi(total - evolve_at, 0) if evolved else 0,
	}


## Snapshot all three evolution states. Arena can use this as a before/after snapshot as-is.
static func evolution_states(relics: Array) -> Dictionary:
	return {
		Family.STARFALL: family_state(relics, Family.STARFALL),
		Family.FULL_MOON: family_state(relics, Family.FULL_MOON),
		Family.MOON_DANCE: family_state(relics, Family.MOON_DANCE),
	}

@export var display_name: String = "Relic"

## One-line description. Show **as a number** what gets better.
## "Gets a bit stronger" is not a reason to pick it.
@export var description: String = ""

@export var effect: Effect = Effect.ATTACK_DAMAGE

## Effect size. Meaning differs by kind — some multiply, some add.
@export var amount: float = 1.0

## Color for the card. Kind is told apart by color.
@export var accent: Color = Color(1, 0.86, 0.5, 1)

## 48x48 card emblem for this relic.
@export var icon: Texture2D = null
