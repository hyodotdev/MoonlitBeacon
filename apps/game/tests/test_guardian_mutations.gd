extends SceneTree

## The six things a guardian can gain, driven on live spirits.
##
## Each mutation hangs on the move machine every guardian already has, so each is checked the way
## `test_guardian_moves` checks the base fights: step a real spirit, count real bolts and real marks.
## A constant proves nothing here; the point is that the rule actually happens.

const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")
const SPIRIT_SCRIPT: Script = preload("res://scripts/actors/spirit.gd")
const STEP_SECONDS: float = 0.05
const BOLT_META: StringName = &"moonlit_pending_hostile_bolts"

var _failed: int = 0
var _checked: int = 0
var _pack_calls: Array[Vector2i] = []
var _hits: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_frenzy()
	_test_spiral()
	_test_echo()
	_test_echo_of_a_run_of_fans()
	_test_summoner()
	_test_aegis()
	_test_meteors()
	_test_plain_guardian_is_untouched()
	_finish()


func _on_hit(_at: Vector2) -> void:
	_hits += 1


func _spawn(resource_path: String, gained: Array[int], cycle: int = 5) -> Node2D:
	var kind: SpiritKind = (load(resource_path) as SpiritKind).duplicate()
	var spirit: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	spirit.set("kind", kind)
	spirit.set("toughness", Expedition.toughness(cycle))
	spirit.set("guardian_cycle", cycle)
	spirit.set("mutations", gained)
	spirit.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(spirit)
	var dummy: Node2D = Node2D.new()
	dummy.position = Vector2(4000, 0)
	root.add_child(dummy)
	spirit.set("_target", dummy)
	spirit.set("_materialized", true)
	spirit.call("set_projectile_hit_handler", _on_hit)
	return spirit


func _bolt_count() -> int:
	return int(get_meta(BOLT_META, 0)) + get_node_count_in_group("hostile_projectiles")


func _clear_world() -> void:
	set_meta(BOLT_META, 0)
	for group in ["hostile_projectiles", "ground_bursts"]:
		for node in get_nodes_in_group(group):
			if is_instance_valid(node):
				node.free()


func _step(spirit: Node2D, seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		spirit.call("_physics_process", STEP_SECONDS)
		elapsed += STEP_SECONDS


func _test_frenzy() -> void:
	var plain: Node2D = _spawn("res://resources/guardian_forest.tres", [] as Array[int])
	var frenzied: Node2D = _spawn(
		"res://resources/guardian_forest.tres", [Expedition.Mutation.FRENZY] as Array[int])
	_expect_approx(
		float(frenzied.call("_guardian_haste")) / float(plain.call("_guardian_haste")),
		SPIRIT_SCRIPT.FRENZY_HASTE, 0.0001, "frenzy runs the whole tempo faster")
	plain.free()
	frenzied.free()


## The safe gap of a ring turns a little further each volley, and the telegraph is drawn from the
## same direction the shot uses, so what is shown is what fires.
func _test_spiral() -> void:
	var spirit: Node2D = _spawn(
		"res://resources/guardian_field.tres", [Expedition.Mutation.SPIRAL] as Array[int])
	var inward: Vector2 = Vector2.RIGHT
	var first: Vector2 = spirit.call("_spiral_aim", inward, SPIRIT_SCRIPT.Volley.FIELD)
	spirit.set("_volleys_fired", 1)
	var second: Vector2 = spirit.call("_spiral_aim", inward, SPIRIT_SCRIPT.Volley.FIELD)
	_expect_true(absf(first.angle()) > 0.1, "the first volley's gap is already off the player")
	_expect_true(absf(second.angle() - first.angle()) > 0.3, "each volley's gap moves on")
	_expect_approx(second.angle() - first.angle(), SPIRIT_SCRIPT.SPIRAL_STEP, 0.0001,
		"by one spiral step")
	var fan_a: Vector2 = spirit.call("_spiral_aim", inward, SPIRIT_SCRIPT.Volley.CAMP_FAN)
	spirit.set("_volleys_fired", 2)
	var fan_b: Vector2 = spirit.call("_spiral_aim", inward, SPIRIT_SCRIPT.Volley.CAMP_FAN)
	_expect_true(fan_a.angle() * fan_b.angle() < 0.0, "an aimed fan swings to alternate sides")
	var plain: Node2D = _spawn("res://resources/guardian_field.tres", [] as Array[int])
	_expect_equal(plain.call("_spiral_aim", inward, SPIRIT_SCRIPT.Volley.FIELD), inward,
		"without the mutation the aim is untouched")
	spirit.free()
	plain.free()


## Every volley comes again 0.7 seconds later, at a turned angle, and the repeat never repeats.
func _test_echo() -> void:
	_clear_world()
	var spirit: Node2D = _spawn(
		"res://resources/guardian_forest.tres", [Expedition.Mutation.ECHO] as Array[int])
	var base_bolts: int = 0
	var saw_echo: bool = false
	var before: int = _bolt_count()
	var fired_at: float = -1.0
	var echoed_at: float = -1.0
	var elapsed: float = 0.0
	for step in 400:
		spirit.call("_physics_process", STEP_SECONDS)
		elapsed += STEP_SECONDS
		var count: int = _bolt_count() - before
		var queued: int = (spirit.get("_echoes") as Array).size()
		if fired_at < 0.0 and queued > 0:
			fired_at = elapsed
			base_bolts = count
		if fired_at >= 0.0 and queued == 0 and count > base_bolts:
			echoed_at = elapsed
			saw_echo = true
			break
	_expect_true(base_bolts > 0, "the first volley fires real bolts")
	_expect_true(saw_echo, "the volley comes again")
	_expect_between(echoed_at - fired_at, 0.55, 1.0, "the echo comes about 0.7s later")
	# Let it run on: one echo per volley, never an echo of an echo.
	_step(spirit, 0.5)
	_expect_true((spirit.get("_echoes") as Array).size() <= 1, "an echo is not echoed")
	spirit.free()
	_clear_world()


## An attack that is a run of fans (camp's two, the owl's two, the grown-up owl's three) repeats once, after its last
## fan, and the repeat is drawn beside that fan while it winds up. Six fans in under two seconds is not a pattern
## anyone can read, and the field only holds two dozen bolts in the air.
func _test_echo_of_a_run_of_fans() -> void:
	for case in [["res://resources/guardian_frost.tres", 2], ["res://resources/guardian_frost_rime.tres", 3],
			["res://resources/guardian_camp.tres", 2]]:
		_clear_world()
		var spirit: Node2D = _spawn(str(case[0]), [Expedition.Mutation.ECHO] as Array[int], 8)
		var windups: int = 0
		var last_move: int = -1
		var last_left: float = 0.0
		var queued_at_windup: Array[int] = []
		var preview_at_windup: Array[bool] = []
		for step in 600:
			spirit.call("_physics_process", STEP_SECONDS)
			var move: int = int(spirit.get("_guardian_move"))
			var left: float = float(spirit.get("_guardian_left"))
			var winding: bool = move == SPIRIT_SCRIPT.GuardianMove.VOLLEY_WINDUP
			if winding and (last_move != move or left > last_left):
				windups += 1
				queued_at_windup.append((spirit.get("_echoes") as Array).size())
				preview_at_windup.append(false)
			if winding and windups > 0:
				var showing: bool = not (spirit.call("echo_preview_shape") as Dictionary).is_empty()
				preview_at_windup[windups - 1] = preview_at_windup[windups - 1] or showing
			if not winding and windups > 0 and (last_move == SPIRIT_SCRIPT.GuardianMove.VOLLEY_WINDUP) \
					and int(spirit.get("_guardian_combo_left")) <= 0 and move != last_move:
				break
			last_move = move
			last_left = left
		var label: String = "%s at cycle 8" % str(case[0]).get_file().get_basename()
		_expect_equal(windups, int(case[1]), label + " blows " + str(case[1]) + " fans")
		if windups == int(case[1]):
			for index in windups:
				var last: bool = index == windups - 1
				_expect_equal(preview_at_windup[index], last,
					label + (": the last fan shows its repeat beside it" if last else ": a fan before the last does not"))
			_expect_equal(queued_at_windup[windups - 1], 0, label + ": no fan before the last queued an echo")
		_expect_true((spirit.get("_echoes") as Array).size() >= 1, label + ": the last fan queued one")
		spirit.free()
		_clear_world()
	var plain: Node2D = _spawn("res://resources/guardian_frost.tres", [] as Array[int], 8)
	plain.call("_set_telegraph", SPIRIT_SCRIPT.Telegraph.VOLLEY, Vector2.RIGHT, 0.5)
	_expect_true((plain.call("echo_preview_shape") as Dictionary).is_empty(), "no repeat is drawn without the mutation")
	plain.free()
	_clear_world()


func _test_summoner() -> void:
	_pack_calls.clear()
	var spirit: Node2D = _spawn(
		"res://resources/guardian_forest.tres", [Expedition.Mutation.SUMMONER] as Array[int],
		9)
	spirit.calls_pack.connect(func(at: Vector2, count: int) -> void:
		_pack_calls.append(Vector2i(int(at.x), count)))
	var full: int = int(spirit.get("_health"))
	_step(spirit, 0.3)
	_expect_equal(_pack_calls.size(), 0, "no pack while healthy")
	spirit.set("_health", int(float(full) * 0.6))
	_step(spirit, 0.3)
	_expect_equal(_pack_calls.size(), 1, "a pack at two thirds")
	_step(spirit, 0.3)
	_expect_equal(_pack_calls.size(), 1, "and only once")
	spirit.set("_health", int(float(full) * 0.3))
	_step(spirit, 0.3)
	_expect_equal(_pack_calls.size(), 2, "a second pack at one third")
	_step(spirit, 0.6)
	_expect_equal(_pack_calls.size(), 2, "never a third")
	_expect_equal(_pack_calls[0].y, 3 + 0, "the pack is three at the win")
	spirit.free()


func _test_aegis() -> void:
	var spirit: Node2D = _spawn(
		"res://resources/guardian_field.tres", [Expedition.Mutation.AEGIS] as Array[int])
	_expect_true(bool(spirit.call("is_attackable")), "attackable before the shield")
	var full: int = int(spirit.get("_health"))
	# Run to the first ring.
	var up: bool = false
	for step in 400:
		spirit.call("_physics_process", STEP_SECONDS)
		if float(spirit.get("_aegis_left")) > 0.0:
			up = true
			break
	_expect_true(up, "a shield ring stands up")
	_expect_true(not bool(spirit.call("is_attackable")), "nothing targets a shielded guardian")
	var before: int = int(spirit.get("_health"))
	spirit.call("take_damage", 500, Vector2.ZERO)
	_expect_equal(int(spirit.get("_health")), before, "a hit does nothing behind the ring")
	_expect_approx(float(spirit.get("_guardian_deferred_damage")), 0.0, 0.001,
		"and is not queued to land later")
	_expect_true(float(spirit.get("_aegis_ping")) > 0.5, "the ring flashes so you see why")
	# It falls again.
	var down: bool = false
	for step in 200:
		spirit.call("_physics_process", STEP_SECONDS)
		if float(spirit.get("_aegis_left")) <= 0.0:
			down = true
			break
	_expect_true(down, "the ring falls after a few seconds")
	_expect_true(bool(spirit.call("is_attackable")), "attackable again")
	spirit.call("take_damage", 40, Vector2.ZERO)
	_expect_true(int(spirit.get("_health")) < full, "damage lands once it is down")
	spirit.free()

	# The rest after a volley is the window a fight is built around: a ring never spends it.
	var camp: Node2D = _spawn(
		"res://resources/guardian_camp.tres", [Expedition.Mutation.AEGIS] as Array[int])
	camp.set("_aegis_left", 2.0)
	camp.set("_guardian_move", SPIRIT_SCRIPT.GuardianMove.RECOVER)
	_step(camp, 0.1)
	_expect_true(float(camp.get("_aegis_left")) <= 0.25, "a ring is cut short when it rests")
	camp.free()


func _test_meteors() -> void:
	_clear_world()
	_hits = 0
	var spirit: Node2D = _spawn(
		"res://resources/guardian_field.tres", [Expedition.Mutation.METEORS] as Array[int])
	# The player stands where the first mark falls; the room is a bare root, so no clamping.
	var player: Node2D = Node2D.new()
	player.position = Vector2(300, 300)
	root.add_child(player)
	spirit.set("_target", player)
	spirit.set("_guardian_move", SPIRIT_SCRIPT.GuardianMove.RECOVER)
	spirit.set("_guardian_left", 3.0)
	var marks: int = 0
	for step in 40:
		spirit.call("_physics_process", STEP_SECONDS)
		marks = get_node_count_in_group("ground_bursts")
		if marks >= 1:
			break
	_expect_true(marks >= 1, "a mark falls while it rests")
	# Nothing hurts until the disc is full. The marks are ordinary nodes, so drive them by hand.
	_expect_equal(_hits, 0, "a fresh mark has not burst yet")
	for node in get_nodes_in_group("ground_bursts"):
		node.call("_physics_process", 0.5)
	_expect_equal(_hits, 0, "half way to the burst still hurts nothing")
	for node in get_nodes_in_group("ground_bursts"):
		node.call("_physics_process", 0.6)
	_expect_true(_hits >= 1, "standing in the first mark gets you hit when it bursts")
	_expect_true(get_node_count_in_group("ground_bursts") <= GroundBurst.LIMIT,
		"the floor never holds more than the limit")
	# Stepping out is the whole answer.
	_clear_world()
	_hits = 0
	var second: Node2D = _spawn(
		"res://resources/guardian_field.tres", [Expedition.Mutation.METEORS] as Array[int])
	second.set("_target", player)
	second.set("_guardian_move", SPIRIT_SCRIPT.GuardianMove.RECOVER)
	second.set("_guardian_left", 3.0)
	for step in 40:
		second.call("_physics_process", STEP_SECONDS)
		if get_node_count_in_group("ground_bursts") >= 1:
			break
	player.position = Vector2(900, 900)
	# Freeze the guardian so no new marks fall on the new spot; the one on the floor still bursts.
	second.set("_guardian_move", SPIRIT_SCRIPT.GuardianMove.CHASE)
	for node in get_nodes_in_group("ground_bursts"):
		node.call("_physics_process", 1.2)
	_expect_equal(_hits, 0, "leaving the circle takes no damage")
	# A rest fires a bounded number of marks.
	var count: int = 0
	var third: Node2D = _spawn(
		"res://resources/guardian_field.tres", [Expedition.Mutation.METEORS] as Array[int])
	third.set("_target", player)
	third.set("_guardian_move", SPIRIT_SCRIPT.GuardianMove.RECOVER)
	third.set("_guardian_left", 30.0)
	_clear_world()
	_step(third, 6.0)
	count = int(third.get("_meteors_this_rest"))
	_expect_equal(count, SPIRIT_SCRIPT.METEORS_PER_REST, "a rest holds a fixed number of marks")
	spirit.free()
	second.free()
	third.free()
	player.free()
	_clear_world()


## No mutation, no change: the shipped fights are exactly what they were.
func _test_plain_guardian_is_untouched() -> void:
	_clear_world()
	var spirit: Node2D = _spawn("res://resources/guardian_forest.tres", [] as Array[int], 3)
	var before: int = _bolt_count()
	_step(spirit, 8.0)
	_expect_true((spirit.get("_echoes") as Array).is_empty(), "no echo without the mutation")
	_expect_equal(get_node_count_in_group("ground_bursts"), 0, "no marks without the mutation")
	_expect_true(bool(spirit.call("is_attackable")), "never shielded without the mutation")
	_expect_true(_bolt_count() - before > 0, "the shipped volleys still fire")
	spirit.free()
	_clear_world()


func _finish() -> void:
	if _failed > 0:
		printerr("guardian-mutation test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("guardian-mutation test passed — ", _checked, " case(s)")
	quit(0)


func _expect_between(actual: float, minimum: float, maximum: float, label: String) -> void:
	_checked += 1
	if actual >= minimum and actual <= maximum:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", minimum, "..", maximum, " actual=", actual)


func _expect_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	_checked += 1
	if absf(actual - expected) <= tolerance:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, "±", tolerance, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)
