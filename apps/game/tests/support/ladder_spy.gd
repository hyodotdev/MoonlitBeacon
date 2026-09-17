extends Control

## Ladder panel stand-in for inspecting the Arena result route.

var ask_count: int = 0
var last_score: int = -1
var last_rank: String = ""
var last_cycles: int = -1
var last_hero: String = ""
var last_run_id: String = ""
var asked_run_ids: Array[String] = []


func ask(score: int, rank_letter: String, cycles: int, hero_id: String,
		run_id: String = "") -> void:
	ask_count += 1
	last_score = score
	last_rank = rank_letter
	last_cycles = cycles
	last_hero = hero_id
	last_run_id = run_id
	asked_run_ids.append(run_id)
