class_name Score
extends RefCounted

## Score for one run.
##
## Score is **counted by the arena and drawn by the result panel.** Both know
## only this type. Same as Chapter 10's HUD rule — the drawer decides nothing.
##
## Rebuilt whole when the game became an endless survivor. **The old score was
## half dead:**
##
## | Field | What was wrong |
## | --- | --- |
## | `escaped` | Moon-gate escape is gone, so nothing calls `_finish(true)`. Always false |
## | `rank()` | So **even a great run was always "D"** |
## | `hearts` | A run ends on death, so always 0 |
## | `beacons` | Reset each cycle, leaving only the last cycle's partial count (0–3) |
## | cycles | **Not in the score at all.** Twenty loops still 0 points |
##
## Endless-game score is not "how cleanly you finished" — it is **"how far you went."**

## Each closed cycle. Lighting three beacons and downing the guardian, so this
## is the largest. This is the game's real unit of achievement.
const PER_CYCLE: int = 1500
## Per beacon lit in the current cycle. Die without closing the cycle and the
## progress still counts.
const PER_BEACON: int = 300
## Per survived second. **Longer is higher** — the old comment said "faster is better."
const PER_SECOND: int = 12
## Per level. How far you grew must stay in the score or building a loadout has no payoff.
const PER_LEVEL: int = 120

## Rank thresholds, read from the top.
##
## **Recalculated from real scores.** First pass was [24000 S, 14000 A, 7000 B,
## 3000 C] and that produced:
##
## | Run | Total | Rank |
## | --- | --- | --- |
## | 2 min | 6,180 | C |
## | 6 min | 24,600 | **S** |
## | 15 min | 70,380 | S |
## | 30 min | 159,480 | S |
##
## Six minutes is S, and S forever after — the scale is spent by 3:30.
## Score is superlinear in time (cycle bonuses stack), so thresholds must
## spread the same way. Current scale: 2 min D–C · 6 min B · 15 min A · 30 min S.
const RANKS: Array = [
	[140000, "S"], [60000, "A"], [20000, "B"], [6000, "C"],
]

## Closed-cycle count. `_cycle` starts at 1, so the arena subtracts 1.
var cycles: int = 0
var beacons: int = 0
var survived: float = 0.0
var level: int = 1
## Share from scattering spirits. Value differs by kind, so the arena sums and passes it.
##
## No constant here on purpose. Score lives per kind on `SpiritKind.score_value`,
## and **a new spirit is one `.tres`.** A table here would be a second place
## to edit when adding a spirit.
var kills: int = 0
## Moon shards earned this run. Not in the score; only on the result screen —
## **wealth, not grade.**
var shards: int = 0


func total() -> int:
	var sum: int = cycles * PER_CYCLE + beacons * PER_BEACON
	sum += int(survived) * PER_SECOND
	sum += maxi(level - 1, 0) * PER_LEVEL
	sum += kills
	return sum


## S · A · B · C · D.
##
## **Do not cut on escape.** An endless game has no end, so everyone dies.
## Cut on that and everyone is D — that is how it actually was.
func rank() -> String:
	var value: int = total()
	for entry in RANKS:
		if value >= int(entry[0]):
			return str(entry[1])
	return "D"


## Breakdown the result panel shows one line at a time. Fixed at five lines —
## if the labels grow they overlap other things (`result_panel.gd`).
func lines() -> Array:
	return [
		[tr("SCORE_CYCLES") % cycles, cycles * PER_CYCLE],
		[tr("SCORE_BEACONS") % beacons, beacons * PER_BEACON],
		[tr("SCORE_TIME") % int(survived), int(survived) * PER_SECOND],
		[tr("SCORE_LEVEL") % level, maxi(level - 1, 0) * PER_LEVEL],
		[tr("SCORE_KILLS"), kills],
	]
