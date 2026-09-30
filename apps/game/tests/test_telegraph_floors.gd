extends SceneTree

## However fast the night has grown, a guardian's warnings keep their floor.
##
## The tempo (cycle, enrage, frenzy) multiplies how quickly every guardian state runs, and past cycle 7 a
## windup fell to a fifth of a second, which is shorter than anyone can answer. `Spirit.MIN_WINDUP` is the
## least a fan, a ring or a charge shows itself and `Spirit.MIN_MARK_FUSE` the least a circle stays on the
## floor before it bursts. Step every guardian through real loops at the tempo of several cycles, enraged and
## frenzied, and measure the warnings it actually gave: the timing constants alone would pass even if the
## tempo still ran over them.
##
## The first night is checked the other way: at cycle 1 nothing is quickened, so every windup keeps exactly
## the length it was authored with. A floor may only ever lengthen a warning that tempo had cut short.

const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")
const SPIRIT_SCRIPT: Script = preload("res://scripts/actors/spirit.gd")
## The floors as the docs state them. Pinned here on purpose: the test must fail if the constants are lowered,
## which it could not if it read its thresholds from them.
const WINDUP_FLOOR: float = 0.45
const FUSE_FLOOR: float = 0.85
## The first fan of a sequence is the widest thing a guardian aims, so it keeps a longer floor of its own.
const FAN_FLOOR: float = 0.75
const STEP_SECONDS: float = 0.03
const STEPS: int = 1500
const SLACK: float = 0.001
const BOLT_META: StringName = &"moonlit_pending_hostile_bolts"

## Cycle, health left, mutations. The first row is the untouched first night; the rest quicken it.
const CASES: Array[Dictionary] = [
	{"cycle": 1, "health": 1.0, "frenzy": false},
	{"cycle": 3, "health": 1.0, "frenzy": false},
	{"cycle": 8, "health": 1.0, "frenzy": false},
	{"cycle": 8, "health": 0.2, "frenzy": true},
	{"cycle": 14, "health": 0.2, "frenzy": true},
	{"cycle": 24, "health": 0.2, "frenzy": true},
]

var _failed: int = 0
var _checked: int = 0
var _dummy: Node2D = null


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect_equal(SPIRIT_SCRIPT.MIN_WINDUP, WINDUP_FLOOR, "the windup floor is the documented one")
	_expect_equal(SPIRIT_SCRIPT.MIN_MARK_FUSE, FUSE_FLOOR, "the circle floor is the documented one")
	_expect_equal(SPIRIT_SCRIPT.MIN_FAN_WINDUP, FAN_FLOOR, "the first fan's floor is the documented one")
	var paths: Array[String] = _guardian_paths()
	_expect_true(paths.size() >= 12, "every guardian is found (%d)" % paths.size())
	for path in paths:
		for case in CASES:
			_measure(path, case)
	_finish()


func _guardian_paths() -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at("res://resources"):
		if not file.begins_with("guardian") or not file.ends_with(".tres"):
			continue
		var path: String = "res://resources/" + file
		var kind: SpiritKind = load(path) as SpiritKind
		if kind != null and kind.behavior == SpiritKind.Behavior.GUARDIAN:
			paths.append(path)
	paths.sort()
	return paths


func _measure(path: String, case: Dictionary) -> void:
	var cycle: int = int(case["cycle"])
	var label: String = "%s at cycle %d, %d%% health%s" % [
		path.get_file().get_basename(), cycle, int(float(case["health"]) * 100.0),
		", frenzied" if bool(case["frenzy"]) else ""]
	_clear()
	var mutations: Array[int] = []
	if bool(case["frenzy"]):
		mutations.append(Expedition.Mutation.FRENZY)
	var spirit: Node2D = _spawn(path, cycle, mutations)
	var full: float = float(spirit.get("kind").health) * float(spirit.get("toughness"))
	spirit.set("_health", maxi(int(full * float(case["health"])), 1))
	var style: int = int(spirit.get("kind").guardian_style)

	var windups: Array[Dictionary] = []
	var fuses: Array[float] = []
	var seen_marks: Dictionary = {}
	var landing_gaps: Array[float] = []
	var active: bool = false
	var steps: int = 0
	var active_move: int = -1
	var active_base: float = 0.0
	var active_fan: int = 0
	var last_move: int = -1
	var last_left: float = 0.0
	for step in STEPS:
		_dummy.position = Vector2(180.0 + 40.0 * sin(float(step) * 0.04), 40.0)
		spirit.call("_physics_process", STEP_SECONDS)
		var move: int = int(spirit.get("_guardian_move"))
		var left: float = float(spirit.get("_guardian_left"))
		var winding: bool = move == SPIRIT_SCRIPT.GuardianMove.VOLLEY_WINDUP \
			or move == SPIRIT_SCRIPT.GuardianMove.CHARGE_WINDUP
		# A windup ends when the state changes, or when its clock is wound back up for the next one.
		if active:
			steps += 1
			if move != active_move or left > last_left:
				windups.append({
					"move": active_move, "base": active_base, "fan": active_fan,
					"seconds": float(steps) * STEP_SECONDS})
				active = false
		if not active and winding and (move != last_move or left > last_left):
			active = true
			steps = 0
			active_move = move
			active_base = float(spirit.get("_guardian_move_duration"))
			active_fan = int(spirit.get("_fan_index"))
		# The toad lands as its circle bursts, whatever pace the state ran at.
		if style == SpiritKind.GuardianStyle.LEAP \
				and last_move == SPIRIT_SCRIPT.GuardianMove.CHARGE and move != last_move:
			var target: Vector2 = spirit.get("_leap_target")
			var nearest: float = INF
			for mark in get_nodes_in_group("ground_bursts"):
				if (mark as Node2D).position.distance_to(target) < 2.0:
					nearest = minf(nearest, absf(float(mark.get("_left"))))
			landing_gaps.append(nearest)
		for mark in get_nodes_in_group("ground_bursts"):
			var mark_id: int = mark.get_instance_id()
			if not seen_marks.has(mark_id):
				seen_marks[mark_id] = true
				fuses.append(float(mark.get("_fuse")))
			mark.call("_physics_process", STEP_SECONDS)
			# No frame runs between steps, so a burst never frees itself; do it when its flash is over.
			if bool(mark.get("_burst")) and float(mark.get("_left")) < -GroundBurst.FLASH_SECONDS:
				mark.free()
		for bolt in get_nodes_in_group("hostile_projectiles"):
			if is_instance_valid(bolt):
				bolt.free()
		set_meta(BOLT_META, 0)
		last_move = move
		last_left = left

	_expect_true(windups.size() >= 2, "%s shows its windups (%d)" % [label, windups.size()])
	# A guardian thinks fifteen times a second, so a state ends on its next thought, not the instant it is due.
	var tick: float = SPIRIT_SCRIPT.AI_INTERVAL + STEP_SECONDS
	for windup in windups:
		var base: float = float(windup["base"])
		var seconds: float = float(windup["seconds"])
		var window: float = _floor_for(style, int(windup["move"]), base, int(windup["fan"]))
		if cycle == 1:
			_expect_true(seconds >= base - SLACK and seconds <= base + tick + SLACK,
				"%s keeps the authored windup %.2f s (%.2f s)" % [label, base, seconds])
		if window > 0.0:
			_expect_true(seconds >= window - SLACK,
				"%s winds up %.2f s, floor %.2f s (authored %.2f s)" % [label, seconds, window, base])
	for fuse in fuses:
		_expect_true(fuse >= FUSE_FLOOR - SLACK,
			"%s leaves a circle %.2f s before it bursts" % [label, fuse])
	if style == SpiritKind.GuardianStyle.LEAP:
		_expect_true(landing_gaps.size() >= 3, "%s lands on its circles (%d)" % [label, landing_gaps.size()])
		# The crouch and the air each end on their own thought, so a landing may trail its circle by two.
		for gap in landing_gaps:
			_expect_true(gap <= 2.0 * tick + SLACK,
				"%s lands as the circle bursts (%.3f s apart)" % [label, gap])
	spirit.free()
	_free_marks()


## The least a warning may last in real time. A toad's crouch is not the warning (its circle is, and the
## circle is checked through its fuse), a sentinel's writing is the circle's fuse, and a windup authored
## shorter than the floor was never lengthened by it.
func _floor_for(style: int, move: int, base: float, fan: int) -> float:
	if style == SpiritKind.GuardianStyle.LEAP and move == SPIRIT_SCRIPT.GuardianMove.CHARGE_WINDUP:
		return 0.0
	if (style == SpiritKind.GuardianStyle.CAMP or style == SpiritKind.GuardianStyle.GALE) \
			and move == SPIRIT_SCRIPT.GuardianMove.VOLLEY_WINDUP and fan == 0:
		return minf(FAN_FLOOR, base)
	if style == SpiritKind.GuardianStyle.GLYPH and move == SPIRIT_SCRIPT.GuardianMove.CHARGE_WINDUP:
		return minf(FUSE_FLOOR, base)
	return minf(WINDUP_FLOOR, base)


func _spawn(resource_path: String, cycle: int, mutations: Array[int]) -> Node2D:
	var kind: SpiritKind = (load(resource_path) as SpiritKind).duplicate()
	var spirit: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	spirit.set("kind", kind)
	spirit.set("toughness", 1.0)
	spirit.set("guardian_cycle", cycle)
	spirit.set("mutations", mutations)
	spirit.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(spirit)
	_dummy = Node2D.new()
	_dummy.position = Vector2(180, 40)
	root.add_child(_dummy)
	spirit.set("_target", _dummy)
	spirit.set("_materialized", true)
	return spirit


func _clear() -> void:
	set_meta(BOLT_META, 0)
	for bolt in get_nodes_in_group("hostile_projectiles"):
		if is_instance_valid(bolt):
			bolt.free()
	_free_marks()
	if _dummy != null and is_instance_valid(_dummy):
		_dummy.free()
	_dummy = null


func _free_marks() -> void:
	for mark in get_nodes_in_group("ground_bursts"):
		if is_instance_valid(mark):
			mark.free()


func _finish() -> void:
	_clear()
	if _failed > 0:
		printerr("telegraph-floor test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("telegraph-floor test passed — ", _checked, " case(s)")
	quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
