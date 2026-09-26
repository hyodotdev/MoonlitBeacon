extends SceneTree

## Pin each guardian's second answer at cycle 3.
##
## One loop per boss made fights predictable: forest only charged, field strafed
## in dead time, camp fired one fan and napped. Forest now slams a shockwave ring
## after its combo, field pokes an aimed bolt per strafe, camp fires a re-aimed
## second fan. Step live Spirits and count real bolts; timing constants alone
## would pass even if the new states never ran.

const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")
const SPIRIT_SCRIPT: Script = preload("res://scripts/actors/spirit.gd")
const CYCLE_THREE_TOUGHNESS: float = 1.35 * 1.35
const STEP_SECONDS: float = 0.05
const MAX_STEPS: int = 240
const BOLT_META: StringName = &"moonlit_pending_hostile_bolts"

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_forest_ring()
	_test_field_poke()
	_test_camp_double_fan()
	_test_guardian_landing()
	_finish()


func _test_forest_ring() -> void:
	_clear_bolts()
	var before: int = _bolt_count()
	var spirit: Node2D = _spawn("res://resources/guardian_forest.tres")
	var saw_ring_windup: bool = false
	var saw_ring_telegraph: bool = false
	var saw_recover_after_ring: bool = false
	var ring_fired: bool = false
	var loop_closed: bool = false
	for step in MAX_STEPS:
		spirit.call("_physics_process", STEP_SECONDS)
		var move: int = int(spirit.get("_guardian_move"))
		if move == SPIRIT_SCRIPT.GuardianMove.VOLLEY_WINDUP:
			saw_ring_windup = true
			if int(spirit.get("_guardian_pattern")) == 1 \
					and int(spirit.get("_telegraph")) == SPIRIT_SCRIPT.Telegraph.VOLLEY:
				saw_ring_telegraph = true
		if saw_ring_windup and _bolt_count() - before > 0:
			ring_fired = true
		if ring_fired and move == SPIRIT_SCRIPT.GuardianMove.RECOVER:
			saw_recover_after_ring = true
		if saw_recover_after_ring and move == SPIRIT_SCRIPT.GuardianMove.CHASE:
			loop_closed = true
			break
	_expect_true(saw_ring_windup, "forest slams a volley after its charge combo")
	_expect_true(
		saw_ring_telegraph, "forest ring telegraphs radial with a safe gap")
	_expect_true(ring_fired, "forest ring fires real bolts")
	# Cycle 3: 10 spokes, one hole each side of the player lane — 7 bolts.
	_expect_equal(_bolt_count() - before, 7, "forest ring leaves its gap open")
	_expect_true(
		saw_recover_after_ring, "forest rests after the ring, not before")
	_expect_true(loop_closed, "forest loop closes back to chase")
	spirit.free()


func _test_field_poke() -> void:
	_clear_bolts()
	var before: int = _bolt_count()
	var spirit: Node2D = _spawn("res://resources/guardian_field.tres")
	var poke_before_volley: int = -1
	var saw_aim: bool = false
	for step in MAX_STEPS:
		spirit.call("_physics_process", STEP_SECONDS)
		var move: int = int(spirit.get("_guardian_move"))
		if move == SPIRIT_SCRIPT.GuardianMove.CHASE \
				and int(spirit.get("_telegraph")) == SPIRIT_SCRIPT.Telegraph.AIM:
			saw_aim = true
		if move == SPIRIT_SCRIPT.GuardianMove.VOLLEY_WINDUP:
			poke_before_volley = _bolt_count() - before
			break
	_expect_true(saw_aim, "field poke shows an aim line while strafing")
	_expect_equal(poke_before_volley, 1, "field fires exactly one poke per strafe")
	spirit.free()


func _test_camp_double_fan() -> void:
	_clear_bolts()
	var before: int = _bolt_count()
	var spirit: Node2D = _spawn("res://resources/guardian_camp.tres")
	# The follow-up windup restarts inside the same move, so count entries by the
	# duration reset (1.0s first aim, 0.55s re-aim), not by move edges.
	var windup_durations: Dictionary = {}
	var saw_recover: bool = false
	var loop_closed: bool = false
	for step in MAX_STEPS:
		spirit.call("_physics_process", STEP_SECONDS)
		var move: int = int(spirit.get("_guardian_move"))
		if move == SPIRIT_SCRIPT.GuardianMove.VOLLEY_WINDUP and not saw_recover:
			windup_durations[float(spirit.get("_guardian_move_duration"))] = true
		if move == SPIRIT_SCRIPT.GuardianMove.RECOVER:
			saw_recover = true
		if saw_recover and move == SPIRIT_SCRIPT.GuardianMove.CHASE:
			loop_closed = true
			break
	_expect_true(
		windup_durations.has(1.0) and windup_durations.has(0.55),
		"camp re-aims a second fan before resting")
	# Cycle 3: 7-bolt fan, twice.
	_expect_equal(_bolt_count() - before, 14, "camp double fan fires both volleys")
	_expect_true(loop_closed, "camp loop closes back to approach")
	spirit.free()


func _test_guardian_landing() -> void:
	var boss: Node2D = _spawn("res://resources/guardian_forest.tres")
	var landed_count: Array[int] = [0]
	boss.connect("landed", func() -> void: landed_count[0] += 1)
	boss.call("_finish_materialize")
	_expect_equal(landed_count[0], 1, "guardian landing emits once")
	_expect_equal(
		float(boss.get("_slam_left")), SPIRIT_SCRIPT.SLAM_SECONDS,
		"guardian landing starts the slam ring")
	boss.call("_physics_process", 0.5)
	_expect_equal(
		float(boss.get("_slam_left")), 0.0,
		"slam ring drains within half a second")
	boss.free()
	var trash: Node2D = _spawn("res://resources/wisp.tres")
	trash.call("_finish_materialize")
	_expect_equal(
		float(trash.get("_slam_left")), 0.0,
		"trash landing starts no slam ring")
	trash.free()


func _spawn(resource_path: String) -> Node2D:
	var kind: SpiritKind = (
		load(resource_path) as SpiritKind).duplicate()
	var spirit: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	spirit.set("kind", kind)
	spirit.set("toughness", CYCLE_THREE_TOUGHNESS)
	spirit.set("guardian_cycle", 3)
	spirit.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(spirit)
	var dummy: Node2D = Node2D.new()
	dummy.position = Vector2(4000, 0)
	root.add_child(dummy)
	spirit.set("_target", dummy)
	spirit.set("_materialized", true)
	return spirit


## Bolts fired so far, whether or not the deferred tree join already flushed.
## The reservation lives on the tree itself, not the root window.
func _bolt_count() -> int:
	return int(get_meta(BOLT_META, 0)) \
		+ get_node_count_in_group("hostile_projectiles")


func _clear_bolts() -> void:
	set_meta(BOLT_META, 0)
	for bolt in get_nodes_in_group("hostile_projectiles"):
		if is_instance_valid(bolt):
			bolt.free()


func _finish() -> void:
	if _failed > 0:
		printerr("guardian-moves test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("guardian-moves test passed — ", _checked, " case(s)")
	quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
