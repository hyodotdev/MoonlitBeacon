extends SceneTree

## A gauntlet run is one fight; a natural run draws its loop target from `loops=`.
##
## The gauntlet battery leaves `loops` unset, so the default two-loop ceiling and the random draw used to
## send gauntlet runs into a second, unboosted loop after the boosted fight — a harness artefact, not a game
## one. This holds the boundary: gauntlet always targets one loop whatever the ceiling is, natural always
## honours the draw.

const BOT_MODES: Script = preload("res://tools/bot_modes.gd")

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_gauntlet_is_one_fight()
	_test_natural_honours_the_draw()
	_finish()


func _test_gauntlet_is_one_fight() -> void:
	for loops_max in range(1, 5):
		for seed_value in [1, 5, 11, 1021, 65536]:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var target: int = BOT_MODES.loops_target_for(true, loops_max, rng)
			if target != 1:
				_expect_true(false, "gauntlet targets one loop (ceiling %d, seed %d gave %d)"
					% [loops_max, seed_value, target])
				return
			_checked += 1
	_expect_true(true, "gauntlet targets one loop at every ceiling")


func _test_natural_honours_the_draw() -> void:
	for loops_max in range(1, 5):
		var seen: Dictionary = {}
		for seed_value in range(1, 51):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var target: int = BOT_MODES.loops_target_for(false, loops_max, rng)
			if target < 1 or target > loops_max:
				_expect_true(false, "natural stays inside 1..%d (seed %d gave %d)"
					% [loops_max, seed_value, target])
				return
			seen[target] = true
		_checked += 1
		if loops_max == 2 and seen.size() < 2:
			_expect_true(false, "natural draws, not pins: both targets appear over fifty seeds")
			return
		_checked += 1
	var first := RandomNumberGenerator.new()
	first.seed = 7
	var second := RandomNumberGenerator.new()
	second.seed = 7
	_expect_true(BOT_MODES.loops_target_for(false, 4, first) == BOT_MODES.loops_target_for(false, 4, second),
		"natural draws from the run's own generator")


func _finish() -> void:
	if _failed > 0:
		printerr("bot-mode test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("bot-mode test passed — ", _checked, " case(s)")
	quit(0)


func _expect_true(actual: bool, label: String) -> void:
	_checked += 1
	if actual:
		return
	_failed += 1
	printerr("  FAIL ", label)
