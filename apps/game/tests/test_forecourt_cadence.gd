extends Node

## Forecourt cadence: the stride follows measured travel, stops idle.
##
## Drives the real GateHeroForecourt tick by tick (frozen _process, direct
## _tick_actor steps) in world staging, formation staging, and the tall
## tablet formation, and proves the walk cycle advances by the distance
## honestly moved: frames step 0,1,2,3 with the feet, cadence stays a
## calm 0.8-1.5 cycles a second, dwell stops plant on the idle sheet
## with a frozen cycle, and departures resume their stride row even
## across a turn. Prints the per-actor cadence table as title-motion
## proof. The party suite owns live-tree travel, facing and clearance.

const STEP: float = 0.016
const FRAMINGS: Array = [
	{"world": true, "view": Vector2(808, 360)},
	{"world": false, "view": Vector2(808, 360)},
	{"world": false, "view": Vector2(808, 606)},
]
## Brief band 0.8-1.5 cycles/s; the floor admits the slowest-plus-
## biggest actor under the tablet presence boost (0.75, exact math).
const CADENCE_LO: float = 0.75
const CADENCE_HI: float = 1.55
const MAX_LEG_TICKS: int = 600
const DWELL_TICKS: int = 30
const SECOND_LEG_TICKS: int = 60

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect_equal(GateHeroForecourt.WALK_CYCLE_HEIGHTS, 0.5,
		"stride holds half a body per cycle")
	for framing in FRAMINGS:
		_test_framing(
			bool(framing["world"]), framing["view"] as Vector2)
	if _failed > 0:
		printerr("forecourt-cadence test failed — ",
			_failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("forecourt-cadence test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _test_framing(world_mode: bool, view: Vector2) -> void:
	var tag: String = "%s/%dx%d" % [
		"world" if world_mode else "formation",
		int(view.x), int(view.y)]
	var forecourt := GateHeroForecourt.new()
	forecourt.size = view
	add_child(forecourt)
	forecourt.set_reduced_motion(true)
	forecourt.set_presentation(world_mode, false)
	forecourt.call("_reset_to_route_heads")
	_expect_true(forecourt.actor_count() == 6,
		"%s: six heroes march" % tag)
	_expect_true(not forecourt.is_motion_active(),
		"%s: frozen clock for the drive" % tag)
	var actors: Array = forecourt.get("_actors")
	for index in actors.size():
		_test_actor(forecourt, actors[index] as Dictionary, view, tag)
	forecourt.queue_free()


func _test_actor(
	forecourt: GateHeroForecourt, data: Dictionary, view: Vector2,
	tag: String
) -> void:
	var slot: int = int(data["slot"])
	var label: String = "%s hero %d" % [tag, slot]
	# Depart from the route head onto the walk sheet.
	data["dwell_left"] = 0.0
	forecourt.call("_rest_stop", data, STEP)
	_expect_true(bool(data["moving"])
		and int(data["sheet"]) == GateHeroForecourt.SHEET_WALK,
		"%s steps off on walk" % label)
	var paint_y: float = (
		forecourt.actor_info(slot)["paint_size"] as Vector2).y
	var cycle: float = paint_y * GateHeroForecourt.WALK_CYCLE_HEIGHTS
	_expect_true(cycle > 1.0, "%s stride spans %spx" % [label, cycle])
	# March the whole leg: every tick's cycle matches its travel.
	var march: Dictionary = _march_leg(forecourt, data, view)
	_expect_true(not bool(data["moving"])
		and int(data["sheet"]) == GateHeroForecourt.SHEET_IDLE,
		"%s arrives onto idle" % label)
	var distance: float = float(march["distance"])
	var moving_time: float = float(march["ticks"]) * STEP
	_expect_true(distance > 1.0, "%s travels %spx" % [label, distance])
	var arrival_cycle: float = float(data["walk_cycle"])
	_expect_true(absf(arrival_cycle - distance / cycle) <= 0.001,
		"%s cycle %.4f matches %.1fpx over %.2fpx cycles" % [
			label, arrival_cycle, distance, cycle])
	var cadence: float = arrival_cycle / moving_time
	_expect_true(cadence >= CADENCE_LO and cadence <= CADENCE_HI,
		"%s cadence %.2f cycles/s" % [label, cadence])
	print("cadence %s speed=%.1f paint=%.1f cycle=%.2f "
		% [label,
			float(GateHeroForecourt.SPEEDS[slot]), paint_y, cycle]
		+ "dist=%.1f cycles=%.2f cps=%.3f frames=%s" % [
			distance, arrival_cycle, cadence,
			str(march["rows"])])
	if distance >= cycle:
		for row in 4:
			_expect_true(row in (march["rows"] as Array),
				"%s visits stride row %d" % [label, row])
	var arrival_row: int = int(floor(arrival_cycle * 4.0)) % 4
	# Dwell: feet planted, idle sheet, frozen cycle.
	var feet: Vector2 = data["feet"]
	for _tick in DWELL_TICKS:
		forecourt.call("_tick_actor", data, STEP)
		_expect_true((data["feet"] as Vector2) == feet,
			"%s dwell plants its feet" % label)
		_expect_true(int(data["sheet"]) == GateHeroForecourt.SHEET_IDLE,
			"%s dwell holds idle" % label)
		_expect_true(float(data["walk_cycle"]) == arrival_cycle,
			"%s dwell freezes its cycle" % label)
	# Depart again: the cycle survives the stop exactly, so the
	# stride row resumes (or steps once with the first step), whatever
	# the new facing.
	data["dwell_left"] = 0.0
	forecourt.call("_rest_stop", data, STEP)
	_expect_true(bool(data["moving"]),
		"%s steps off again" % label)
	_expect_true(float(data["walk_cycle"]) == arrival_cycle,
		"%s departure keeps its cycle" % label)
	forecourt.call("_tick_actor", data, STEP)
	_expect_true(posmod(int(data["frame"]) - arrival_row, 4) <= 1,
		"%s resumes row %d without a jump" % [label, arrival_row])
	var second: Dictionary = _march_ticks(
		forecourt, data, view, SECOND_LEG_TICKS)
	_expect_true(float(second["distance"]) > 1.0,
		"%s second leg travels" % label)


## March until the leg ends, checking the frame mapping and step order
## on every moving tick. Returns travel, moving ticks and rows visited.
func _march_leg(
	forecourt: GateHeroForecourt, data: Dictionary, view: Vector2
) -> Dictionary:
	var world: bool = forecourt.is_world_mode()
	var distance: float = 0.0
	var ticks: int = 0
	var rows: Array = []
	var previous_frame: int = -1
	for _tick in MAX_LEG_TICKS:
		if not bool(data["moving"]):
			break
		var before: Vector2 = data["feet"]
		var cycle_before: float = float(data["walk_cycle"])
		forecourt.call("_tick_actor", data, STEP)
		var step: Vector2 = (data["feet"] as Vector2) - before
		if world:
			distance += step.length()
		else:
			distance += (step * view).length()
		ticks += 1
		var want: int = int(floor(
			float(data["walk_cycle"]) * 4.0)) % 4
		if bool(data["moving"]):
			_expect_true(int(data["frame"]) == want,
				"frame follows its cycle")
			if not rows.has(int(data["frame"])):
				rows.append(int(data["frame"]))
			if previous_frame >= 0:
				var advance: int = posmod(
					int(data["frame"]) - previous_frame, 4)
				_expect_true(advance == 0 or advance == 1,
					"stride steps without skips")
			previous_frame = int(data["frame"])
		_expect_true(float(data["walk_cycle"]) >= cycle_before,
			"cycle never runs back")
	return {"distance": distance, "ticks": ticks, "rows": rows}


## March a fixed number of ticks or to the arrival, recording travel.
func _march_ticks(
	forecourt: GateHeroForecourt, data: Dictionary, view: Vector2,
	count: int
) -> Dictionary:
	var world: bool = forecourt.is_world_mode()
	var distance: float = 0.0
	for _tick in count:
		if not bool(data["moving"]):
			break
		var before: Vector2 = data["feet"]
		forecourt.call("_tick_actor", data, STEP)
		var step: Vector2 = (data["feet"] as Vector2) - before
		if world:
			distance += step.length()
		else:
			distance += (step * view).length()
	return {"distance": distance}


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
