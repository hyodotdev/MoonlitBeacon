extends SceneTree

## The three guardians of the later places, stepped live at cycle 3.
##
## Gale (the owl): glide, two fans of feathers, a dive through where you stood, a perch.
## Leap (the toad): waddle, hop, hop, flop with a ring, a long rest; each leap lands on a circle
## marked on the floor, and the circle bursts as the toad lands.
## Glyph (the sentinel): keep a way off, write circles round you, a ring with a gap, a rest.
##
## Step real Spirits and count real bolts and real marks: the timing constants alone would pass
## even if a new state never ran. Then run every mutation on every new guardian for a long
## stretch, so no combination can leave a move machine stuck or throw.

const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")
const SPIRIT_SCRIPT: Script = preload("res://scripts/actors/spirit.gd")
const CYCLE_THREE_TOUGHNESS: float = 1.35 * 1.35
const STEP_SECONDS: float = 0.05
const MAX_STEPS: int = 600
const BOLT_META: StringName = &"moonlit_pending_hostile_bolts"
const NEW_GUARDIANS: Array[String] = [
	"res://resources/guardian_frost.tres", "res://resources/guardian_frost_rime.tres",
	"res://resources/guardian_marsh.tres", "res://resources/guardian_marsh_glow.tres",
	"res://resources/guardian_ruins.tres", "res://resources/guardian_ruins_halo.tres",
]

var _failed: int = 0
var _checked: int = 0
var _dummy: Node2D = null


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_styles_are_declared()
	_test_gale()
	_test_grown_owl_blows_three_fans()
	_test_leap()
	_test_glyph()
	_test_every_mutation_on_every_new_guardian()
	_finish()


func _test_styles_are_declared() -> void:
	var expected: Dictionary = {
		"guardian_frost": SpiritKind.GuardianStyle.GALE,
		"guardian_frost_rime": SpiritKind.GuardianStyle.GALE,
		"guardian_marsh": SpiritKind.GuardianStyle.LEAP,
		"guardian_marsh_glow": SpiritKind.GuardianStyle.LEAP,
		"guardian_ruins": SpiritKind.GuardianStyle.GLYPH,
		"guardian_ruins_halo": SpiritKind.GuardianStyle.GLYPH,
	}
	for path in NEW_GUARDIANS:
		var kind: SpiritKind = load(path) as SpiritKind
		_expect_true(kind != null, "%s loads" % path)
		if kind == null:
			continue
		_expect_equal(kind.behavior, SpiritKind.Behavior.GUARDIAN, "%s is a guardian" % path)
		_expect_equal(kind.guardian_style, int(expected[path.get_file().get_basename()]),
			"%s has its own style" % path)
		_expect_true(TranslationServer.get_locale() != "" and not kind.display_name.is_empty(),
			"%s has a name key" % path)
	# The old three keep their numbers: new styles are appended.
	_expect_equal(int(SpiritKind.GuardianStyle.FOREST), 0, "forest is still 0")
	_expect_equal(int(SpiritKind.GuardianStyle.FIELD), 1, "field is still 1")
	_expect_equal(int(SpiritKind.GuardianStyle.CAMP), 2, "camp is still 2")


func _test_gale() -> void:
	_clear()
	var before: int = _bolt_count()
	var spirit: Node2D = _spawn("res://resources/guardian_frost.tres", Vector2(4000, 0))
	var start: Vector2 = spirit.position
	var fan_windups: int = 0
	var last_move: int = -1
	var last_left: float = 0.0
	var saw_dive_telegraph: bool = false
	var dive_start: Vector2 = Vector2.ZERO
	var dive_end: Vector2 = Vector2.ZERO
	var saw_perch: bool = false
	var loop_closed: bool = false
	var bolts_at_dive: int = 0
	for step in MAX_STEPS:
		spirit.call("_physics_process", STEP_SECONDS)
		var move: int = int(spirit.get("_guardian_move"))
		var left: float = float(spirit.get("_guardian_left"))
		# A fan starts when the windup begins, or when its clock is wound back up for the second one.
		if move == SPIRIT_SCRIPT.GuardianMove.VOLLEY_WINDUP and (last_move != move or left > last_left):
			fan_windups += 1
		last_left = left
		if move == SPIRIT_SCRIPT.GuardianMove.CHARGE_WINDUP \
				and int(spirit.get("_telegraph")) == SPIRIT_SCRIPT.Telegraph.CHARGE:
			saw_dive_telegraph = true
			bolts_at_dive = _bolt_count() - before
		if move == SPIRIT_SCRIPT.GuardianMove.CHARGE:
			if last_move != move:
				dive_start = spirit.position
			dive_end = spirit.position
		if move == SPIRIT_SCRIPT.GuardianMove.RECOVER:
			saw_perch = true
		if saw_perch and move == SPIRIT_SCRIPT.GuardianMove.CHASE:
			loop_closed = true
			break
		last_move = move
	_expect_equal(fan_windups, 2, "the owl blows two fans before it dives")
	_expect_equal(bolts_at_dive, 14, "two fans of seven feathers at cycle 3")
	_expect_true(saw_dive_telegraph, "the dive shows its lane before it goes")
	_expect_true(dive_end.distance_to(dive_start) > 50.0, "the dive really travels")
	_expect_true(saw_perch, "the owl perches after the dive")
	_expect_true(loop_closed, "the owl's loop closes back to gliding")
	_expect_true(spirit.position.distance_to(start) > 50.0, "the owl moved")
	spirit.free()


## The grown-up owl is "one more feather fan than before": three, from its first meeting, with fewer feathers each so
## the run and its repeat still fit the two dozen bolts the field holds.
func _test_grown_owl_blows_three_fans() -> void:
	_clear()
	var before: int = _bolt_count()
	var spirit: Node2D = _spawn("res://resources/guardian_frost_rime.tres", Vector2(4000, 0))
	var fans: int = 0
	var last_move: int = -1
	var last_left: float = 0.0
	var feathers: Array[int] = []
	var seen_at_windup: int = before
	for step in MAX_STEPS:
		spirit.call("_physics_process", STEP_SECONDS)
		var move: int = int(spirit.get("_guardian_move"))
		var left: float = float(spirit.get("_guardian_left"))
		if move == SPIRIT_SCRIPT.GuardianMove.VOLLEY_WINDUP and (last_move != move or left > last_left):
			if fans > 0:
				feathers.append(_bolt_count() - seen_at_windup)
			seen_at_windup = _bolt_count()
			fans += 1
		if move == SPIRIT_SCRIPT.GuardianMove.CHARGE_WINDUP:
			feathers.append(_bolt_count() - seen_at_windup)
			break
		last_move = move
		last_left = left
	_expect_equal(fans, 3, "the grown-up owl blows three fans before it dives")
	_expect_equal(feathers.size(), 3, "and every one of them fired")
	for count in feathers:
		_expect_true(count >= 4 and count <= 6, "each fan carries a handful of feathers (%d)" % count)
	_expect_true(_bolt_count() - before <= 24, "and the run fits under the cap of two dozen (%d)" % (_bolt_count() - before))
	spirit.free()


func _test_leap() -> void:
	_clear()
	var before: int = _bolt_count()
	var spirit: Node2D = _spawn("res://resources/guardian_marsh.tres", Vector2(150, 0))
	var landings: Array[Dictionary] = []
	var last_move: int = -1
	var marks_seen: Dictionary = {}
	var saw_ring_telegraph: bool = false
	var bolts_after_flop: int = -1
	var saw_rest: bool = false
	var loop_closed: bool = false
	for step in MAX_STEPS:
		spirit.call("_physics_process", STEP_SECONDS)
		for mark in get_nodes_in_group("ground_bursts"):
			mark.call("_physics_process", STEP_SECONDS)
			marks_seen[mark.get_instance_id()] = mark
		var move: int = int(spirit.get("_guardian_move"))
		if last_move == SPIRIT_SCRIPT.GuardianMove.CHARGE and move != last_move:
			landings.append({
				"at": spirit.position, "target": spirit.get("_leap_target"),
				"marks": marks_seen.size()})
		if move == SPIRIT_SCRIPT.GuardianMove.VOLLEY_WINDUP \
				and int(spirit.get("_telegraph")) == SPIRIT_SCRIPT.Telegraph.VOLLEY:
			saw_ring_telegraph = true
		if move == SPIRIT_SCRIPT.GuardianMove.RECOVER and last_move != move:
			saw_rest = true
			bolts_after_flop = _bolt_count() - before
		if saw_rest and move == SPIRIT_SCRIPT.GuardianMove.CHASE:
			loop_closed = true
			break
		last_move = move
	_expect_equal(landings.size(), 3, "the toad hops twice and flops once")
	for landing in landings:
		_expect_true((landing["at"] as Vector2).distance_to(landing["target"] as Vector2) < 4.0,
			"the toad lands on its mark")
	var radii: Array[float] = []
	for mark in marks_seen.values():
		radii.append(float(mark.get("radius")))
	radii.sort()
	_expect_equal(radii.size(), 3, "every leap marks the floor")
	if radii.size() == 3:
		_expect_equal(radii[0], SPIRIT_SCRIPT.LEAP_HOP_RADIUS, "a hop marks a small circle")
		_expect_equal(radii[1], SPIRIT_SCRIPT.LEAP_HOP_RADIUS, "both hops do")
		_expect_equal(radii[2], SPIRIT_SCRIPT.LEAP_FLOP_RADIUS, "the flop marks a wider one")
	_expect_true(saw_ring_telegraph, "the flop's ring shows its gap before it fires")
	# Cycle 3: ten spokes with one left out either side of your lane, seven bolts.
	_expect_equal(bolts_after_flop, 7, "the flop is followed by one ring with its gap")
	_expect_true(saw_rest, "the toad rests after the flop")
	_expect_true(loop_closed, "the toad's loop closes back to waddling")
	spirit.free()
	_free_marks()


func _test_glyph() -> void:
	_clear()
	var before: int = _bolt_count()
	var spirit: Node2D = _spawn("res://resources/guardian_ruins.tres", Vector2(150, 0))
	var last_move: int = -1
	var marks: Array[Vector2] = []
	var marks_at_write: int = -1
	var saw_ring_telegraph: bool = false
	var bolts_at_rest: int = -1
	var loop_closed: bool = false
	var saw_rest: bool = false
	for step in MAX_STEPS:
		spirit.call("_physics_process", STEP_SECONDS)
		var move: int = int(spirit.get("_guardian_move"))
		if move == SPIRIT_SCRIPT.GuardianMove.CHARGE_WINDUP and last_move != move:
			marks_at_write = get_node_count_in_group("ground_bursts")
			for mark in get_nodes_in_group("ground_bursts"):
				marks.append((mark as Node2D).position)
		for mark in get_nodes_in_group("ground_bursts"):
			mark.call("_physics_process", STEP_SECONDS)
		if move == SPIRIT_SCRIPT.GuardianMove.VOLLEY_WINDUP \
				and int(spirit.get("_telegraph")) == SPIRIT_SCRIPT.Telegraph.VOLLEY:
			saw_ring_telegraph = true
		if move == SPIRIT_SCRIPT.GuardianMove.RECOVER and last_move != move:
			saw_rest = true
			bolts_at_rest = _bolt_count() - before
		if saw_rest and move == SPIRIT_SCRIPT.GuardianMove.CHASE:
			loop_closed = true
			break
		last_move = move
	_expect_equal(marks_at_write, 3, "the sentinel writes three circles at cycle 3")
	var on_you: int = 0
	for at in marks:
		if at.distance_to(_dummy.position) < 1.0:
			on_you += 1
	_expect_equal(on_you, 1, "one circle is written where you stand")
	_expect_true(saw_ring_telegraph, "the ring shows its gap before it fires")
	# Cycle 3: sixteen spokes, one left out either side of your lane and the lane itself, 13 bolts.
	_expect_equal(bolts_at_rest, 13, "one ring with a gap follows the circles")
	_expect_true(loop_closed, "the sentinel's loop closes back to drifting")
	spirit.free()
	_free_marks()


## Every mutation on every new guardian, deep into the endless stretch: nothing may throw, nothing
## may leave the move machine stuck, and the loop must keep coming round.
func _test_every_mutation_on_every_new_guardian() -> void:
	for path in NEW_GUARDIANS:
		for mutation in Expedition.MUTATION_COUNT:
			_clear()
			var spirit: Node2D = _spawn(path, Vector2(180, 40), 13, [mutation] as Array[int])
			var moves_seen: Dictionary = {}
			var loops: int = 0
			var last_move: int = -1
			for step in 1500:
				_dummy.position = Vector2(180.0 + 40.0 * sin(float(step) * 0.05), 40.0)
				spirit.call("_physics_process", STEP_SECONDS)
				for mark in get_nodes_in_group("ground_bursts"):
					mark.call("_physics_process", STEP_SECONDS)
				for bolt in get_nodes_in_group("hostile_projectiles"):
					if is_instance_valid(bolt) and bolt.get_index() >= 0:
						bolt.free()
				set_meta(BOLT_META, 0)
				var move: int = int(spirit.get("_guardian_move"))
				moves_seen[move] = true
				if last_move == SPIRIT_SCRIPT.GuardianMove.RECOVER \
						and move == SPIRIT_SCRIPT.GuardianMove.CHASE:
					loops += 1
				last_move = move
			_expect_true(loops >= 2, "%s with mutation %d keeps looping (%d)" % [
				path.get_file(), mutation, loops])
			_expect_true(moves_seen.has(SPIRIT_SCRIPT.GuardianMove.RECOVER),
				"%s with mutation %d still rests" % [path.get_file(), mutation])
			spirit.free()
			_free_marks()


func _spawn(resource_path: String, target_at: Vector2, cycle: int = 3,
		mutations: Array[int] = [] as Array[int]) -> Node2D:
	var kind: SpiritKind = (load(resource_path) as SpiritKind).duplicate()
	var spirit: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	spirit.set("kind", kind)
	spirit.set("toughness", CYCLE_THREE_TOUGHNESS)
	spirit.set("guardian_cycle", cycle)
	spirit.set("mutations", mutations)
	spirit.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(spirit)
	_dummy = Node2D.new()
	_dummy.position = target_at
	root.add_child(_dummy)
	spirit.set("_target", _dummy)
	spirit.set("_materialized", true)
	return spirit


func _bolt_count() -> int:
	return int(get_meta(BOLT_META, 0)) + get_node_count_in_group("hostile_projectiles")


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
		printerr("guardian-new-styles test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("guardian-new-styles test passed — ", _checked, " case(s)")
	quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
