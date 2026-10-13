## One finished run, scored: beacon pay, remaining time, the escape bonus.
class_name Score
extends RefCounted

const PER_BEACON: int = 500
const PER_SECOND: int = 10
const WIN_BONUS: int = 1000
const RANK_S: int = 3000
const RANK_A: int = 2200
const RANK_B: int = 1400

var beacons_lit: int = 0
var beacons_total: int = 0
var time_left: float = 0.0
var won: bool = false


static func build(lit: int, total: int, seconds: float, escaped: bool) -> Score:
	var score: Score = Score.new()
	score.beacons_lit = lit
	score.beacons_total = total
	score.time_left = maxf(seconds, 0.0)
	score.won = escaped
	return score


func beacon_points() -> int:
	return beacons_lit * PER_BEACON


func time_points() -> int:
	return int(time_left) * PER_SECOND


func bonus_points() -> int:
	return WIN_BONUS if won else 0


func total() -> int:
	return beacon_points() + time_points() + bonus_points()


func rank() -> String:
	## No escape, no rank above D, however large the pile.
	if not won:
		return "D"
	var sum: int = total()
	if sum >= RANK_S:
		return "S"
	if sum >= RANK_A:
		return "A"
	if sum >= RANK_B:
		return "B"
	return "C"


func lines() -> Array:
	return [
		["Beacons", beacon_points()],
		["Time", time_points()],
		["Escape", bonus_points()],
	]
