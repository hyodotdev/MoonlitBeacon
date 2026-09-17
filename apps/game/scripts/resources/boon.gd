class_name Boon
extends Resource

## One permanent upgrade. **It survives death.**
##
## Pair of `Relic` — relics live only inside a run, boons survive across runs.
## Same `.tres` pattern, so adding one does not grow the code.
##
## **Why this is needed.** Until now death left nothing but a high score.
## In an endless survivor that is fatal — play well for 30 minutes, die, and
## the next run is bare-handed level 1 again. Unless skill grew, yesterday
## and today are the same. **There is no reason to open it again.**
##
## Every successful game in this genre has growth outside the run. Something
## must go up when a run ends, or "one more run" never happens. Without that
## it is a good demo, not a good game.

## What it raises. The arena reads this when a run starts.
enum Grace {
	START_HEALTH,     ## starting heart cells
	START_DAMAGE,     ## starting damage multiplier
	START_SPEED,      ## walk speed
	START_RELIC,      ## how many relics you enter a run holding
	DEW_LUCK,         ## moon dew drops more often
	SHARD_YIELD,      ## more shards when a run ends
}

@export var display_name: String = "Boon"

## One-line description. **The value changes per rank, so leave `%s` blank.**
## `describe()` fills in the actual value for the current rank.
@export var description: String = ""

@export var grace: Grace = Grace.START_HEALTH

## Amount added per rank.
@export var step: float = 1.0

## How many ranks it can be raised.
##
## There must be a ceiling. Without one, a long-time player starts invincible
## and **the game vanishes for that person only.** A boon nudges the starting
## line forward; it is not a skip-the-run device.
@export var max_rank: int = 3

## Cost to open rank 1. The next rank multiplies this by `cost_growth`.
@export var base_cost: int = 40
@export var cost_growth: float = 1.8

@export var accent: Color = Color(0.78, 0.9, 1, 1)


## Shards to buy `rank`. Ranks start at 1.
func cost_at(rank: int) -> int:
	return int(round(float(base_cost) * pow(cost_growth, float(maxi(rank - 1, 0)))))


## Actual effect size at the current rank.
func amount_at(rank: int) -> float:
	return step * float(maxi(rank, 0))


## Sentence for the card. Show **as a number** what the next rank becomes.
## "Gets a bit stronger" is not a reason to spend shards.
func describe(rank: int) -> String:
	return tr(description) % _pretty(amount_at(rank + 1))


func _pretty(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.0f" % (value * 100.0)
