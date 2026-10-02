class_name HeroWeapons
extends RefCounted

## Per-hero primary-weapon numbers on the real arena path.
##
## Every hero fires the same two clocks the arena always had — a melee swing and a
## moon-wheel volley — but each side now reads its base numbers from this table instead
## of one shared default. One side is the PRIMARY (full strength, the hero's identity)
## and the other is a SIDEARM (roughly a third of the output) so every relic family,
## missile core and evolution keeps working for every hero without a second free
## full-strength weapon in any kit.
##
## Price and `vfx_tier` never enter this table. Only `attack_profile` selects a row,
## so a costly hero cannot buy damage here; the weapon tests lock that boundary.

## Which clock carries the hero's identity.
enum Side { MELEE, RANGED }

const HERO_IDS: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage",
]


## Primary side per profile. Warden/Dancer/Eclipse fight up close; Sage/Keeper/Knight
## fight at range. Mirrors `Hero.AttackProfile` order: WARDEN, DANCER, KEEPER, KNIGHT,
## ECLIPSE, SAGE.
static func primary_side(profile: Hero.AttackProfile) -> int:
	match profile:
		Hero.AttackProfile.SAGE, Hero.AttackProfile.KEEPER, Hero.AttackProfile.KNIGHT:
			return Side.RANGED
	return Side.MELEE


## Melee base numbers before relics: reach px, fan degrees, cooldown seconds, damage
## multiplier on `Player.DEFAULT_ATTACK_DAMAGE`. Twin/orbit flags select the swing shape
## in `Arena._swing_at`; they change hit geometry, never the damage formula.
static func melee_spec(profile: Hero.AttackProfile) -> Dictionary:
	match profile:
		Hero.AttackProfile.WARDEN:
			# Decisive wide sword cuts: the reference every other hero is compared to.
			return {"reach": 46.0, "arc": 130.0, "cooldown": 0.50, "damage": 1.0,
				"twin": false, "orbit": false}
		Hero.AttackProfile.DANCER:
			# Quick alternating twin blades: narrower, faster, left-right-left.
			return {"reach": 38.0, "arc": 85.0, "cooldown": 0.30, "damage": 0.55,
				"twin": true, "orbit": false}
		Hero.AttackProfile.ECLIPSE:
			# Orbiting scythe: a full ring pulse; reach is the ring's outer edge.
			return {"reach": 64.0, "arc": 360.0, "cooldown": 0.62, "damage": 0.8,
				"twin": false, "orbit": true}
		Hero.AttackProfile.SAGE:
			# Rifle-bash sidearm: short narrow jab for what closes in.
			return {"reach": 30.0, "arc": 60.0, "cooldown": 0.68, "damage": 0.4,
				"twin": false, "orbit": false}
		Hero.AttackProfile.KEEPER:
			# Lantern-sweep sidearm: very wide but short and soft.
			return {"reach": 34.0, "arc": 170.0, "cooldown": 0.80, "damage": 0.35,
				"twin": false, "orbit": false}
		_:
			# Knight heavy-chop sidearm: slow narrow backup chip, roughly a
			# third of close-range output now that the cannon carries.
			return {"reach": 40.0, "arc": 70.0, "cooldown": 1.0, "damage": 0.55,
				"twin": false, "orbit": false}


## Ranged base numbers before relics/cores: targeting range px, base lanes, fan half-angle
## degrees, bonus pierce, projectile speed px/s, cooldown seconds, damage multiplier on
## `Arena.ARROW_BASE_HIT` (the whole volley budget), and cannon blast radius px (0: none).
static func ranged_spec(profile: Hero.AttackProfile) -> Dictionary:
	match profile:
		Hero.AttackProfile.SAGE:
			# Precise long rifle: one piercing bolt down a long line. The whole
			# budget rides one shot, so the multiplier looks large next to fans.
			return {"range": 300.0, "lanes": 1, "fan": 0.0, "pierce": 5,
				"speed": 340.0, "cooldown": 1.20, "damage": 4.8, "blast": 0.0}
		Hero.AttackProfile.KEEPER:
			# Short lantern shotgun: a broad close fan that falls off fast. The
			# budget splits evenly across five pellets, so only a close spread
			# collects it all; per pellet it is a sidearm budget, summed it roars.
			return {"range": 125.0, "lanes": 5, "fan": 30.0, "pierce": 0,
				"speed": 260.0, "cooldown": 1.0, "damage": 6.5, "blast": 0.0}
		Hero.AttackProfile.KNIGHT:
			# Slow heavy cannon: one shell, then a delayed blast where it lands.
			# Still the slowest gun by far, but each shell now earns the primary
			# name: about two-thirds of close-range output with the chop behind.
			return {"range": 230.0, "lanes": 1, "fan": 0.0, "pierce": 0,
				"speed": 150.0, "cooldown": 2.10, "damage": 4.0, "blast": 48.0}
		Hero.AttackProfile.WARDEN:
			# Single moon-wheel sidearm: the classic backup shot. Keeps the old
			# volley cadence so a max-haste Lv40 build still reaches the fastest
			# fire-rate stage the late-game test guards.
			return {"range": 200.0, "lanes": 1, "fan": 0.0, "pierce": 0,
				"speed": 210.0, "cooldown": 1.15, "damage": 0.6, "blast": 0.0}
		Hero.AttackProfile.DANCER:
			# Twin light bolts sidearm: two quick sparks, little each.
			return {"range": 175.0, "lanes": 2, "fan": 16.0, "pierce": 0,
				"speed": 230.0, "cooldown": 1.35, "damage": 0.7, "blast": 0.0}
		_:
			# Eclipse ember pair sidearm: slow drifting embers.
			return {"range": 185.0, "lanes": 2, "fan": 26.0, "pierce": 0,
				"speed": 190.0, "cooldown": 1.50, "damage": 0.7, "blast": 0.0}


## Twin-blade side offset in degrees. Dancer alternates +/− around the aim each swing.
const TWIN_OFFSET_DEGREES: float = 28.0

## Orbit ring inner edge as a fraction of reach. Inside the hole the scythe never lands,
## so weaving at mid range — not hugging — is the Eclipse game.
const ORBIT_INNER_FRACTION: float = 0.55


## Profile row for a hero id, for tests and harnesses that only know the id.
static func profile_of(hero_id: String) -> Hero.AttackProfile:
	match hero_id:
		"dancer":
			return Hero.AttackProfile.DANCER
		"keeper":
			return Hero.AttackProfile.KEEPER
		"knight":
			return Hero.AttackProfile.KNIGHT
		"eclipse":
			return Hero.AttackProfile.ECLIPSE
		"sage":
			return Hero.AttackProfile.SAGE
	return Hero.AttackProfile.WARDEN
