extends Node

## The gates of a real run: one on cycle 1, a **fork** of two from cycle 2.
##
## Runs the real arena. A fork names the place each gate leads to, the gate you run for decides the
## next terrain and the side you arrive on, the second fork names the guardian waiting there, and a
## new cycle opens somewhere other than where the last guardian fell. A test that builds the arena
## by hand (no title) keeps the single classic gate.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	await _test_cycle_one_has_one_gate()
	await _test_hand_built_arena_keeps_one_gate()
	await _test_fork_travel()
	await _test_new_places()
	_finish()


func _new_arena() -> Node2D:
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.call("debug_shield")
	return arena


func _drop(arena: Node2D) -> void:
	arena.queue_free()
	# A finished loop leaves its cash-out panel up, and that pauses the tree for the next test.
	get_tree().paused = false
	await get_tree().process_frame


## Cycle 1 teaches the loop with one gate, even in a real run.
func _test_cycle_one_has_one_gate() -> void:
	var arena: Node2D = await _new_arena()
	arena.set("_forks_enabled", true)
	_expect_equal(int(arena.get("_cycle")), 1, "a new run starts at cycle 1")
	arena.call("debug_light_next_beacon")
	await get_tree().create_timer(0.2, true).timeout
	_expect_true(bool(arena.get("_escape_active")), "the first beacon opens a gate")
	_expect_equal((arena.get("_fork_options") as Array).size(), 0, "cycle 1 offers no fork")
	_expect_true(arena.get("_gate_b") == null, "cycle 1 has one gate only")
	await _drop(arena)


## A hand-built arena (a test, a store capture) never sees a fork.
func _test_hand_built_arena_keeps_one_gate() -> void:
	var arena: Node2D = await _new_arena()
	_expect_true(not bool(arena.get("_forks_enabled")), "an arena not started from the title has no forks")
	arena.set("_cycle", 4)
	arena.call("_change_cycle_world")
	await get_tree().process_frame
	_expect_equal(arena.call("_terrain_at", 0), 0, "cycle 4 starts on the classic rotation (forest)")
	arena.call("debug_light_next_beacon")
	await get_tree().create_timer(0.2, true).timeout
	_expect_true(bool(arena.get("_escape_active")), "a gate opens")
	_expect_true(arena.get("_gate_b") == null, "no second gate without forks")
	_expect_equal((arena.get("_fork_options") as Array).size(), 0, "no fork options")
	await _drop(arena)


func _test_fork_travel() -> void:
	var arena: Node2D = await _new_arena()
	var run_seed: int = 4_242_001
	arena.set("_forks_enabled", true)
	arena.set("_run_seed", run_seed)
	arena.set("_cycle", 2)
	arena.set("_zone_index", 0)
	var start: int = Expedition.start_terrain(run_seed, 2, 0)
	arena.set("_route", [start, -1, -1] as Array[int])
	arena.call("_change_cycle_world")
	await get_tree().process_frame
	var room: Room = arena.get("_room") as Room
	_expect_equal(room.kind.resource_path, str(Expedition.TERRAINS[start]["room"]),
		"cycle 2 opens on the drawn terrain")

	# --- The first fork: two gates, two named places.
	arena.call("debug_light_next_beacon")
	await get_tree().create_timer(0.2, true).timeout
	_expect_true(bool(arena.get("_escape_active")), "the first beacon opens the gates")
	var spent: Dictionary = (arena.get("_voice") as HeroVoice).get("_spent") as Dictionary
	_expect_true(spent.has("VOICE_FORK_1") or spent.has("VOICE_FORK_2"),
		"the hero says something the first time a fork opens")
	var options: Array[int] = []
	options.assign(arena.get("_fork_options"))
	var expected_route: Array[int] = [start, -1, -1]
	_expect_equal(options, Expedition.gate_options(run_seed, 2, 0, expected_route),
		"the fork offers what Expedition draws for this seed")
	_expect_equal(options.size(), 2, "a fork has two options")
	if options.size() != 2:
		await _drop(arena)
		return
	_expect_true(options[0] != options[1], "the two options differ")
	_expect_true(options[0] != start and options[1] != start, "neither option is where you stand")
	var gate_a: Node2D = arena.get("_gate") as Node2D
	var gate_b: Node2D = arena.get("_gate_b") as Node2D
	_expect_true(gate_b != null and is_instance_valid(gate_b), "a second gate exists")
	if gate_b == null:
		await _drop(arena)
		return
	_expect_true(gate_a.visible and gate_b.visible, "both gates are showing")
	_expect_true(gate_a.position.distance_to(gate_b.position) > 400.0,
		"the gates stand on different rims")
	var directions: Array[Vector2] = []
	directions.assign(arena.get("_fork_directions"))
	_expect_true(directions.size() == 2 and directions[0] != directions[1],
		"each gate remembers its own rim")
	var label_a: Label = gate_a.get("_label") as Label
	var label_b: Label = gate_b.get("_label") as Label
	_expect_true(label_a != null and label_a.text.begins_with(
		TranslationServer.translate(str(Expedition.TERRAINS[options[0]]["name"]))),
		"gate A names its terrain")
	_expect_true(label_b != null and label_b.text.begins_with(
		TranslationServer.translate(str(Expedition.TERRAINS[options[1]]["name"]))),
		"gate B names its terrain")
	arena.call("_point_compass", 0.016)
	_expect_true(arena.get("_compass_b") != null, "a second arrow points at the second gate")

	# --- Run for the second gate.
	arena.call("_on_gate_entered", 1)
	await _wait_for_travel(arena)
	_expect_equal(int(arena.get("_zone_index")), 1, "crossing a gate enters zone 2")
	var route: Array[int] = []
	route.assign(arena.get("_route"))
	_expect_equal(route[0], start, "the first zone stays in the route")
	_expect_equal(route[1], options[1], "the gate you ran for decides the terrain")
	room = arena.get("_room") as Room
	_expect_equal(room.kind.resource_path, str(Expedition.TERRAINS[options[1]]["room"]),
		"the room you arrive in is the one the gate named")
	_expect_equal(arena.get("_gate_direction"), directions[1], "you arrive on the gate's side")
	_expect_true(arena.get("_gate_b") == null, "the second gate is gone after the crossing")
	_expect_equal((arena.get("_fork_options") as Array).size(), 0, "the fork is over")

	# --- The second fork names the guardian waiting in the last zone.
	arena.call("debug_light_next_beacon")
	await get_tree().create_timer(0.2, true).timeout
	var second_options: Array[int] = []
	second_options.assign(arena.get("_fork_options"))
	_expect_equal(second_options.size(), 2, "the second beacon opens a fork too")
	if second_options.size() != 2:
		await _drop(arena)
		return
	_expect_true(not second_options.has(options[1]), "you are never sent back where you stand")
	gate_b = arena.get("_gate_b") as Node2D
	label_a = (arena.get("_gate") as Node2D).get("_label") as Label
	label_b = gate_b.get("_label") as Label
	for index in 2:
		var roster: Array = Expedition.TERRAINS[second_options[index]]["guardians"]
		var kind: SpiritKind = load(str(roster[1])) as SpiritKind
		var label: Label = label_a if index == 0 else label_b
		_expect_true(label.text.contains(TranslationServer.translate(kind.display_name)),
			"gate %d names the guardian of its terrain" % index)
	arena.call("_on_gate_entered", 0)
	await _wait_for_travel(arena)
	_expect_equal(int(arena.get("_zone_index")), 2, "crossing again enters the last zone")
	route.assign(arena.get("_route"))
	_expect_equal(route[2], second_options[0], "the second fork decides the guardian's terrain")

	# --- The last beacon calls that terrain's guardian, in its promoted form.
	arena.call("debug_light_next_beacon")
	await get_tree().create_timer(0.4, true).timeout
	var expected_guardian: String = str(
		Expedition.TERRAINS[second_options[0]]["guardians"][1])
	_expect_equal(str(arena.call("_guardian_resource_path")), expected_guardian,
		"the guardian follows the route")
	var guardian: Node2D = arena.get("_guardian") as Node2D
	_expect_true(guardian != null, "the last beacon summons the guardian")

	# --- Beating it opens a new loop somewhere other than where it fell.
	if guardian != null and guardian.has_method("debug_slay"):
		guardian.call("debug_slay")
		await get_tree().create_timer(0.5, true).timeout
	_expect_equal(int(arena.get("_cycle")), 3, "the loop closes and cycle 3 begins")
	route.assign(arena.get("_route"))
	_expect_equal(route[1], -1, "the new loop has not chosen its second zone yet")
	_expect_true(route[0] >= 0 and route[0] != second_options[0],
		"the new loop does not open where the guardian fell")
	_expect_equal(route[0], Expedition.start_terrain(run_seed, 3, second_options[0]),
		"and the opening is what Expedition draws")
	await _drop(arena)


## From cycle 3 a fork can lead somewhere new. The gate you run for builds that place's room, the
## place reports its own raid and id, and its guardian is the younger form the first time you meet
## it and the grown-up one after.
func _test_new_places() -> void:
	var arena: Node2D = await _new_arena()
	arena.set("_forks_enabled", true)
	var run_seed: int = -1
	var start: int = 0
	for candidate in range(1, 400):
		var opening: int = Expedition.start_terrain(candidate, 4, 0)
		var found: Array[int] = Expedition.gate_options(
			candidate, 4, 0, [opening, -1, -1] as Array[int])
		var new_place: bool = false
		for option in found:
			new_place = new_place or option >= Expedition.CLASSIC_TERRAINS
		if new_place:
			run_seed = candidate
			start = opening
			break
	_expect_true(run_seed >= 0, "some run offers a new place at cycle 4")
	if run_seed < 0:
		await _drop(arena)
		return
	arena.set("_run_seed", run_seed)
	arena.set("_cycle", 4)
	arena.set("_zone_index", 0)
	arena.set("_route", [start, -1, -1] as Array[int])
	arena.call("_change_cycle_world")
	await get_tree().process_frame
	arena.call("debug_light_next_beacon")
	await get_tree().create_timer(0.2, true).timeout
	var options: Array[int] = []
	options.assign(arena.get("_fork_options"))
	var index: int = 0 if options[0] >= Expedition.CLASSIC_TERRAINS else 1
	var place: int = options[index]
	arena.call("_on_gate_entered", index)
	await _wait_for_travel(arena)
	var room: Room = arena.get("_room") as Room
	_expect_equal(room.kind.resource_path, str(Expedition.TERRAINS[place]["room"]),
		"the new place builds its own room")
	var ids: Array[String] = ["forest", "field", "camp", "frost", "marsh", "ruins"]
	_expect_equal(str(arena.call("_analytics_terrain_id")), ids[place],
		"the new place reports its own id")
	_expect_equal(int(arena.call("_encounter_kind")), int(room.kind.encounter),
		"the new place raids in its own shape")

	# The younger form first, the grown-up after; the classic three still grow with the cycle.
	var roster: Array = Expedition.TERRAINS[place]["guardians"]
	arena.set("_guardian_meetings", {})
	_expect_equal(str(arena.call("_guardian_path_for", place)), str(roster[0]),
		"the first meeting is the younger guardian")
	arena.set("_guardian_meetings", {place: 1})
	_expect_equal(str(arena.call("_guardian_path_for", place)), str(roster[1]),
		"the second meeting is the grown-up")
	var classic: Array = Expedition.TERRAINS[0]["guardians"]
	arena.set("_guardian_meetings", {})
	_expect_equal(str(arena.call("_guardian_path_for", 0)), str(classic[1]),
		"a classic place still grows with the cycle")
	arena.set("_cycle", 1)
	_expect_equal(str(arena.call("_guardian_path_for", 0)), str(classic[0]),
		"and starts young at cycle 1")
	await _drop(arena)


func _wait_for_travel(arena: Node2D) -> void:
	var until: int = Time.get_ticks_msec() + 8000
	while bool(arena.get("_transitioning")) and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	await get_tree().process_frame


func _finish() -> void:
	if _failed > 0:
		printerr("fork-travel test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("fork-travel test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("fork-travel test aborted: user:// path is not isolated — ", user_root)
	return safe


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)
