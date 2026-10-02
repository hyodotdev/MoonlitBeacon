extends SceneTree

## What a volley fires, what its warning draws and whether a person can get out of the way.
##
## The play bot found that the wedge drawn for a fan stayed at one width while the fan itself grew from five
## bolts to a dozen, that the gap drawn on a ring stayed at twelve spokes while the ring reached thirty, and
## that from cycle 7 a fan could not be left in the time its warning gave. So the bolts, the picture and the
## bot now read the same lists of angles, and this holds every guardian at every cycle to the same three rules:
##
## - **Honest.** Every bolt of a fan lies inside the wedge drawn for it, every ring's clear way is the way
##   between the aim and its nearest spoke, and the number of bolts fired is the number of angles drawn.
## - **A way through.** On a ring or a cross the clear way is at least `MIN_LANE_ANGLE` either side of the
##   aim, however many spokes there are, and a volley never carries more bolts than the field allows in the air:
##   a ring and its slower second ring together, and a whole run of fans and the repeat of its last one, fit under
##   the cap of two dozen, so no later fan or repeat fires fewer bolts than the picture shows.
## - **Leavable.** A fan can be left, on foot and with one dash, by the slowest hero who reacts in a third of a
##   second, in the time between its warning and its bolts arriving, at the worst tempo (enraged and frenzied);
##   the follow-up fans, aimed at where the player has just run to, by the same hero still running.
##
## The human is a model, not a person: it has the numbers of a keeper (the slowest hero) and a reaction
## slower than a good player's. It is here to fail loudly when a change makes a volley impossible, not to
## say how hard a fight is.

const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")
const SPIRIT_SCRIPT: Script = preload("res://scripts/actors/spirit.gd")
const BOLT_SCENE: PackedScene = preload("res://scenes/actors/moon_bolt.tscn")
const BOLT_META: StringName = &"moonlit_pending_hostile_bolts"
const CYCLES: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 20, 30, 45, 60, 100]

## Pinned on purpose, like the windup floors: lowering one must be a decision that changes this file.
const FAN_MAX_SPAN: float = 1.2
const MIN_LANE_ANGLE: float = 0.28
const MAX_VOLLEY_BOLTS: int = 22
## What the field allows in the air (`Spirit.HOSTILE_BOLT_LIMIT`), and no more.
const HOSTILE_BOLT_CAP: int = 24
const FAN_WINDUP_FLOOR: float = 0.75
## A guardian's bolts fly this far, and the pictures of its volleys reach as far as they do.
const VOLLEY_RANGE: float = 260.0
const FOLLOWUP_WINDUP_FLOOR: float = 0.45

## The model person.
const REACTION_SECONDS: float = 0.3
const SLOWEST_SPEED: float = 82.0
const DASH_GAIN: float = 43.0
## A bolt's own radius and the body it would meet.
const BODY_MARGIN: float = 14.0
## Where a player usually stands from the guardian.
const RANGE: float = 150.0
const BOLT_SPEED: float = 132.0

var _failed: int = 0
var _checked: int = 0
var _dummy: Node2D = null


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect_equal(SPIRIT_SCRIPT.FAN_MAX_SPAN, FAN_MAX_SPAN, "the widest fan is the documented one")
	_expect_equal(SPIRIT_SCRIPT.MIN_LANE_ANGLE, MIN_LANE_ANGLE, "the narrowest way through is the documented one")
	_expect_equal(SPIRIT_SCRIPT.MAX_VOLLEY_BOLTS, MAX_VOLLEY_BOLTS, "the biggest volley is the documented one")
	_expect_equal(SPIRIT_SCRIPT.HOSTILE_BOLT_LIMIT, HOSTILE_BOLT_CAP, "the cap the volleys are fitted under is the field's")
	_expect_true(SPIRIT_SCRIPT.FAN_RUN_BOLTS <= HOSTILE_BOLT_CAP and SPIRIT_SCRIPT.MAX_VOLLEY_BOLTS <= HOSTILE_BOLT_CAP,
		"and neither budget asks for more than that")
	_expect_equal(SPIRIT_SCRIPT.MIN_FAN_WINDUP, FAN_WINDUP_FLOOR, "the first fan's floor is the documented one")
	_expect_equal(SPIRIT_SCRIPT.VOLLEY_RANGE, VOLLEY_RANGE, "the furthest a volley flies is the documented one")
	_expect_true(SPIRIT_SCRIPT.FAN_DRAW_REACH <= VOLLEY_RANGE and SPIRIT_SCRIPT.RING_DRAW_REACH <= VOLLEY_RANGE
		and SPIRIT_SCRIPT.AIM_MAX_REACH <= VOLLEY_RANGE, "no picture reaches past where its bolts fly")
	_expect_true(SPIRIT_SCRIPT.FAN_DRAW_REACH >= VOLLEY_RANGE - 60.0 and SPIRIT_SCRIPT.RING_DRAW_REACH >= VOLLEY_RANGE - 60.0,
		"and none stops much short of it")
	var paths: Array[String] = _guardian_paths()
	_expect_true(paths.size() >= 12, "every guardian is found (%d)" % paths.size())
	for path in paths:
		for cycle in CYCLES:
			_check_guardian(path, cycle)
	_check_the_first_cycles_are_as_shipped()
	_check_a_bolt_stops_at_its_range()
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


func _check_guardian(path: String, cycle: int) -> void:
	var label: String = "%s at cycle %d" % [path.get_file().get_basename(), cycle]
	var spirit: Node2D = _spawn(path, cycle)
	var style: int = int(spirit.get("kind").guardian_style)
	match style:
		SpiritKind.GuardianStyle.CAMP, SpiritKind.GuardianStyle.GALE:
			for index in 3:
				spirit.set("_fan_index", index)
				_check_fan(spirit, style, index, label + " fan %d" % index, 3 if path.ends_with("frost_rime.tres") else 2)
		SpiritKind.GuardianStyle.FIELD, SpiritKind.GuardianStyle.GLYPH:
			for pattern in 2:
				spirit.set("_guardian_pattern", pattern)
				_check_ring(spirit, label + (" cross" if pattern == 0 else " radial"))
		_:
			_check_ring(spirit, label + " ring")
	spirit.free()
	_clear()


func _check_fan(spirit: Node2D, style: int, index: int, label: String, expected_run: int) -> void:
	var shape: Dictionary = spirit.call("volley_shape")
	var angles: Array = shape["angles"]
	var base: float = float(shape["base"])
	var half: float = float(shape["half"])
	_expect_equal(StringName(shape["kind"]), &"fan", label + " is a fan")
	_expect_true(angles.size() >= 5, label + " carries bolts (%d)" % angles.size())
	# The whole attack: every fan of the run and the repeat of the last one are in the air together.
	var fans: int = int(spirit.call("_fans_in_run"))
	_expect_equal(fans, expected_run, label + " is a run of the right length")
	_expect_true((fans + 1) * angles.size() <= HOSTILE_BOLT_CAP,
		label + " fits under the cap with its repeat (%d fans of %d)" % [fans, angles.size()])
	_expect_true(half * 2.0 <= FAN_MAX_SPAN + 0.0001, label + " is no wider than the widest fan (%.2f)" % (half * 2.0))
	for angle in angles:
		_expect_true(absf(wrapf(float(angle) - base, -PI, PI)) <= half + 0.0001,
			label + " keeps every bolt inside its wedge")
	_clear_bolts()
	spirit.set("_locked", Vector2.RIGHT.rotated(base))
	spirit.call("_fire_camp_fan")
	_expect_equal(_bolt_count(), angles.size(), label + " fires the bolts it draws")

	# Can the model person leave it? The worst tempo: enraged and frenzied.
	var haste: float = float(spirit.call("_guardian_haste"))
	var first_base: float = SPIRIT_SCRIPT.GALE_FAN_WINDUP if style == SpiritKind.GuardianStyle.GALE \
		else SPIRIT_SCRIPT.CAMP_VOLLEY_WINDUP
	var follow_base: float = SPIRIT_SCRIPT.GALE_FAN_FOLLOWUP if style == SpiritKind.GuardianStyle.GALE \
		else SPIRIT_SCRIPT.CAMP_FOLLOWUP_WINDUP
	var windup: float = _real_windup(first_base if index == 0 else follow_base,
		FAN_WINDUP_FLOOR if index == 0 else FOLLOWUP_WINDUP_FLOOR, haste)
	var flight: float = RANGE / (BOLT_SPEED * float(spirit.call("_bolt_scale")))
	var need: float = RANGE * tan(half) + BODY_MARGIN
	var reach: float
	if index == 0:
		reach = SLOWEST_SPEED * maxf(0.0, windup + flight - REACTION_SECONDS) + DASH_GAIN
	else:
		# Already running from the last fan: no reaction to wait for, and the dash is spent.
		reach = SLOWEST_SPEED * (windup + flight)
	_expect_true(reach >= need, "%s can be left: needs %.0f px, a person covers %.0f (windup %.2f s, bolts %.2f s)" % [
		label, need, reach, windup, flight])


func _check_ring(spirit: Node2D, label: String) -> void:
	var shape: Dictionary = spirit.call("volley_shape")
	var angles: Array = shape["angles"]
	var slow: Array = shape["slow"]
	var base: float = float(shape["base"])
	var gap: float = float(shape["gap"])
	_expect_true(angles.size() + slow.size() <= MAX_VOLLEY_BOLTS,
		label + " carries no more than the field allows (%d)" % (angles.size() + slow.size()))
	_expect_true(gap >= MIN_LANE_ANGLE - 0.0001, label + " leaves a way through %.2f rad either side (min %.2f)" % [
		gap, MIN_LANE_ANGLE])
	# The drawn way through is exactly the way between the aim and the nearest spoke.
	var nearest: float = PI
	for angle in angles + slow:
		nearest = minf(nearest, absf(wrapf(float(angle) - base, -PI, PI)))
	_expect_true(absf(nearest - gap) < 0.0001, label + " draws the gap it fires")
	# Fire it and count.
	_clear_bolts()
	spirit.set("_locked", Vector2.RIGHT.rotated(base))
	var style: int = int(spirit.get("kind").guardian_style)
	if style == SpiritKind.GuardianStyle.FIELD or style == SpiritKind.GuardianStyle.GLYPH:
		spirit.call("_fire_field_volley")
	else:
		spirit.call("_fire_forest_ring")
	_expect_equal(_bolt_count(), angles.size() + slow.size(), label + " fires the bolts it draws")


## Cycle 1 to 4 keep the numbers the game shipped with: the caps only ever bite past them.
func _check_the_first_cycles_are_as_shipped() -> void:
	var spans: Array[float] = [0.96, 1.04, 1.12, 1.20]
	for index in spans.size():
		_clear()
		var spirit: Node2D = _spawn("res://resources/guardian_camp.tres", index + 1)
		_expect_true(absf(float(spirit.call("fan_span")) - spans[index]) < 0.0001,
			"the camp fan at cycle %d is as wide as it shipped (%.2f)" % [index + 1, spans[index]])
		spirit.set("_fan_index", 1)
		_expect_true(absf(float(spirit.call("fan_span")) - spans[index]) < 0.0001,
			"and so is its second fan (%.2f)" % spans[index])
		spirit.free()
	_clear()
	var camp: Node2D = _spawn("res://resources/guardian_camp.tres", 3)
	_expect_equal((camp.call("fan_angles", 0.0) as Array).size(), 7, "the camp fan at cycle 3 carries seven bolts")
	camp.free()
	_clear()
	var field: Node2D = _spawn("res://resources/guardian_field.tres", 1)
	field.set("_guardian_pattern", 1)
	_expect_equal((field.call("radial_angles", 0.0) as Array).size(), 7, "the field radial at cycle 1 fires seven bolts")
	field.set("_guardian_pattern", 0)
	_expect_equal((field.call("cross_angles", 0.0) as Array).size(), 4, "the field cross at cycle 1 fires four")
	field.free()
	_clear()


## A guardian's bolt flies its range, fades over the last stretch and is gone; one without a range still lives
## its five seconds, so nothing else in the field changes.
func _check_a_bolt_stops_at_its_range() -> void:
	var ranged: Node2D = BOLT_SCENE.instantiate() as Node2D
	root.add_child(ranged)
	ranged.call("set_direction", Vector2.RIGHT)
	ranged.call("set_range", 100.0)
	var faded: bool = false
	var steps: int = 0
	while not ranged.is_queued_for_deletion() and steps < 600:
		ranged.call("_physics_process", 1.0 / 60.0)
		if ranged.global_position.x > 70.0 and (ranged.get_node("Sprite") as Sprite2D).modulate.a < 0.9:
			faded = true
		steps += 1
	_expect_true(ranged.is_queued_for_deletion(), "a bolt with a range is gone once it has flown it")
	_expect_true(absf(ranged.global_position.x - 100.0) < 3.0, "and it flew that far (%.1f px)" % ranged.global_position.x)
	_expect_true(faded, "and it faded over its last stretch")
	ranged.free()
	var free: Node2D = BOLT_SCENE.instantiate() as Node2D
	root.add_child(free)
	free.call("set_direction", Vector2.RIGHT)
	for step in 240:
		free.call("_physics_process", 1.0 / 60.0)
	_expect_true(not free.is_queued_for_deletion() and free.global_position.x > 500.0,
		"a bolt without a range flies on (%.0f px in four seconds)" % free.global_position.x)
	free.free()


## The time a warning really lasts once the tempo and the floor have had their say.
func _real_windup(seconds: float, floor_seconds: float, haste: float) -> float:
	return seconds / minf(haste, maxf(seconds / floor_seconds, 1.0))


func _spawn(resource_path: String, cycle: int) -> Node2D:
	var kind: SpiritKind = (load(resource_path) as SpiritKind).duplicate()
	var spirit: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	spirit.set("kind", kind)
	spirit.set("toughness", 1.0)
	spirit.set("guardian_cycle", cycle)
	# The worst tempo the fight has: frenzied and at the last of its health.
	spirit.set("mutations", [Expedition.Mutation.FRENZY] as Array[int])
	spirit.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(spirit)
	spirit.set("_health", 1)
	_dummy = Node2D.new()
	_dummy.position = Vector2(180, 40)
	root.add_child(_dummy)
	spirit.set("_target", _dummy)
	spirit.set("_materialized", true)
	return spirit


func _bolt_count() -> int:
	return int(get_meta(BOLT_META, 0)) + get_node_count_in_group("hostile_projectiles")


func _clear_bolts() -> void:
	set_meta(BOLT_META, 0)
	for bolt in get_nodes_in_group("hostile_projectiles"):
		if is_instance_valid(bolt):
			bolt.free()


func _clear() -> void:
	_clear_bolts()
	if _dummy != null and is_instance_valid(_dummy):
		_dummy.free()
	_dummy = null


func _finish() -> void:
	_clear()
	if _failed > 0:
		printerr("volley-fairness test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("volley-fairness test passed — ", _checked, " case(s)")
	quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
