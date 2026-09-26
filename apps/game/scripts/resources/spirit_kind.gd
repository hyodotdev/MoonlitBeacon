class_name SpiritKind
extends Resource

## Settings for one spirit kind.
##
## Chapter 13 grows enemies to three. Three scenes means three places to edit —
## that is the debt carried since Chapter 2.
##
## **One scene, many settings.** One `.tres` file is one enemy kind.
## A new enemy needs neither code nor a scene.

## How it moves. **This is the axis that makes enemies feel different.**
##
## When all three were just "chase," only speed and turn rate differed, so
## more kinds still did the same thing on screen. Different behavior means
## a different answer.
enum Behavior {
	CHASE,   ## chase straight in. the baseline
	CHARGE,  ## stop, aim, then dash in a line
	ORBIT,   ## circle and slowly close. hard to aim at
	SHOOT,   ## keep range and fire moonlight
	GUARDIAN, ## chase, telegraph charge, and a bullet pattern with a gap, in turn
}

## A guardian is not the same large spirit per terrain — it is a boss with a
## different answer.
enum GuardianStyle {
	FOREST, ## telegraph a corridor, then two charges in a row
	FIELD,  ## orbit the player, swapping cross and radial fire
	CAMP,   ## slow assault form, aimed fan fire, then a long opening
}

@export var display_name: String = "Spirit"

@export var behavior: Behavior = Behavior.CHASE
@export var guardian_style: GuardianStyle = GuardianStyle.FOREST
## Shared accent for the health bar, procedural decor, and telegraph line.
@export var boss_accent: Color = Color(0.58, 0.82, 1.0, 1)
## Short how-to line for a card or boss UI.
@export_multiline var guardian_rule: String = ""
## Max HP fraction a guardian can take at once right after spawn. A big first
## hit still reads, but a max volley already in flight cannot delete the boss
## in one frame.
@export_range(0.05, 0.5, 0.01) var guardian_burst_fraction: float = 0.14
## How many max-HP fractions of empty damage budget refill per second. Ordinary
## attacks slower than this are not damped at all; only dense auto-weapons hit
## a sustained-damage cap.
@export_range(0.05, 0.5, 0.01) var guardian_sustain_fraction: float = 0.16


## Multiplier that tightens the two budget ratios each cycle. The arena divides
## by this when spawning a guardian.
##
## Mobs gain pressure naturally from count and HP, but burst budget is a
## **fraction of HP**, so minimum TTK stayed the same across cycles — a
## completed-power run ended the boss in 6–7 seconds on every cycle, and
## "the boss keeps dying too easily" actually came up. Cycles 1–3 tighten 22%
## each to keep the existing climax, cycle 4 holds that line (1.84), and from
## cycle 5 the squeeze is one step steeper than relic growth so late game is
## a real wall.
## Changing the value also changes the test_guardian_balance contract.
const CYCLE_PRESSURE_STEP: float = 0.22
const LATE_PRESSURE_AT_FOUR: float = 1.84
const LATE_PRESSURE_GROWTH: float = 1.48
const BUDGET_FLOOR: float = 0.05
const LATE_BUDGET_FLOOR: float = 0.018
const LATE_BUDGET_DECAY: float = 0.80
const LATE_TOUGHNESS_GROWTH: float = 1.22


static func cycle_pressure(cycle: int) -> float:
	var safe_cycle: int = maxi(cycle, 1)
	if safe_cycle <= 3:
		return 1.0 + CYCLE_PRESSURE_STEP * float(safe_cycle - 1)
	return LATE_PRESSURE_AT_FOUR * pow(
		LATE_PRESSURE_GROWTH, float(safe_cycle - 4))


## Floor the burst and sustain budgets can drop to. Cycles 1–3 keep 0.05 to
## hold the existing TTK; after that the floor itself drops so even completed
## power still takes longer to kill.
static func guardian_budget_floor(cycle: int) -> float:
	if cycle <= 3:
		return BUDGET_FLOOR
	return maxf(
		BUDGET_FLOOR * pow(LATE_BUDGET_DECAY, float(cycle - 3)),
		LATE_BUDGET_FLOOR)


## Extra HP multiplier only the guardian takes. Multiplied on top of mob
## `toughness()`. Cycles 1–3 stay at 1 so the existing HP contract holds; from
## cycle 4 the boss toughens faster than the mobs.
static func guardian_toughness_scale(cycle: int) -> float:
	if cycle <= 3:
		return 1.0
	return pow(LATE_TOUGHNESS_GROWTH, float(cycle - 3))

## Optional per-state sheets for the guardian.
##
## `sheet` is the idle hover; the four below match combat patterns to art.
## Leave them empty and the idle sheet keeps being used, so existing resources
## still work. All are facing-less horizontal sheets with `guardian_state_frames`
## cells of size `cell`.
@export_group("Guardian Visuals")
@export var guardian_windup_sheet: Texture2D = null
## Used when the same state telegraphs a different pattern, like the field guardian's second volley.
@export var guardian_alt_windup_sheet: Texture2D = null
@export var guardian_charge_sheet: Texture2D = null
@export var guardian_recover_sheet: Texture2D = null
@export_range(1, 12, 1) var guardian_state_frames: int = 6
@export_range(1.0, 24.0, 0.5) var guardian_state_fps: float = 6.0
## Extra follow-up count for the forest charge. 1 means two telegraphed charges.
@export_range(1, 6, 1) var guardian_combo: int = 1
## Extra shots added to field and camp barrages.
@export_range(0, 8, 1) var guardian_volley_extra: int = 0
## Camp armor-open time multiplier. Lower means a shorter gap.
@export_range(0.4, 1.4, 0.05) var guardian_recover_scale: float = 1.0
@export_group("")

## CHARGE — time spent stopped aiming before the dash. Shakes red during this.
## No telegraph and the hit just feels unfair.
@export var charge_windup: float = 0.9
## CHARGE — dash speed and duration.
@export var charge_speed: float = 260.0
@export var charge_seconds: float = 0.55

## ORBIT — hold this distance while circling. Slowly closes in.
@export var orbit_radius: float = 96.0
@export var orbit_closing: float = 6.0

## SHOOT — hold this distance. Closer than that, back off.
@export var keep_distance: float = 150.0
## SHOOT — seconds between shots.
@export var shoot_interval: float = 2.4

## Sprite sheet.
##
## Two layouts. **With facing, columns = facing, rows = frames.**
## Without facing (guardian), **frames run horizontally on one row.**
## Original sheets follow this spec too, so the same assembly code works with
## pre-course compatibility resources.
@export var sheet: Texture2D = null

## Cell size. Regular spirits are 24, guardians 64.
@export var cell: int = 16

## Facing count. 1 means no facing — the same picture from every side.
@export var facings: int = 4

## Frames per facing.
@export var frames: int = 4

## Extra lift on the sprite.
##
## The hover VFX in `spirit.tscn`'s `Hover` is tuned for a 16px cell.
## Larger cells need more lift so the feet sit on the shadow.
@export var lift: float = 0.0

@export var speed: float = 62.0
## Turn rate. Low swings wide; high sticks and follows.
@export var turn_rate: float = 5.0

## Hits before it scatters.
##
## Arrived in Chapter 17. The Chapter 13 plan's "not doing" list had "enemy
## HP / kills"; this is the value that reverses that. **Neither code nor
## scenes grow — only a number on the `.tres`** — paying off keeping one
## scene in Chapter 13.
@export var health: int = 2

## Score given on a kill.
@export var score_value: int = 60

## How long it staggers after a hit.
##
## 0 and it keeps pushing in even when hit. Hitting it feels like nothing.
## Too long and one hit lets you walk out at will, so tension dies.
@export var stagger_seconds: float = 0.12
@export var body_scale: float = 1.0
## Color laid over the night tint. Kind is told apart by color.
@export var tint: Color = Color(0.315, 0.35, 0.57, 1)
## Animation playback speed (fps).
@export var anim_fps: float = 5.0
