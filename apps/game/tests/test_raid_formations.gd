extends Node

## Every place raids in its own shape.
##
## Runs the real arena on each terrain's room and reads what a raid queues, so the shape is
## checked as positions and not as a promise in a comment: Frost Pass sends a wall with a gap
## in it, Mirewood Marsh three pods with wide gaps between them, Moonlit Ruins a group ahead and,
## a few seconds later, one from behind. The three older shapes are checked for the basics only
## (they are pinned by the game tests that already cover them).

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const CENTER: Vector2 = Vector2(950, 590)
const SEED: int = 730_421
const PLACES: Array[Dictionary] = [
	{"room": "res://resources/rooms/forest.tres", "id": "forest"},
	{"room": "res://resources/rooms/field.tres", "id": "field"},
	{"room": "res://resources/rooms/camp.tres", "id": "camp"},
	{"room": "res://resources/rooms/frost.tres", "id": "frost"},
	{"room": "res://resources/rooms/marsh.tres", "id": "marsh"},
	{"room": "res://resources/rooms/ruins.tres", "id": "ruins"},
]

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.call("debug_shield")
	# Nothing may eat the queue while the test reads it.
	arena.set_process(false)
	await _test_every_place_raids(arena)
	await _test_squall(arena)
	await _test_tide(arena)
	await _test_vigil(arena)
	arena.queue_free()
	await get_tree().process_frame
	_finish()


## Build `path` with no structures in it (so no spirit is nudged off its mark), stand the player
## at `at` and empty the queue.
func _stand(arena: Node2D, path: String, at: Vector2, velocity: Vector2 = Vector2.ZERO) -> void:
	var kind: RoomKind = (load(path) as RoomKind).duplicate() as RoomKind
	kind.obstacle_count = 0
	(arena.get("_room") as Room).build(kind, SEED)
	var player: CharacterBody2D = arena.get("_player") as CharacterBody2D
	player.position = at
	player.velocity = velocity
	(arena.get("_raid_queue") as Array).clear()


func _offsets(arena: Node2D) -> Array[Vector2]:
	var player: Node2D = arena.get("_player") as Node2D
	var found: Array[Vector2] = []
	for queued in arena.get("_raid_queue") as Array:
		found.append((queued as Dictionary)["at"] as Vector2 - player.position)
	return found


func _test_every_place_raids(arena: Node2D) -> void:
	for place in PLACES:
		_stand(arena, str(place["room"]), CENTER)
		_expect_equal(str(arena.call("_analytics_terrain_id")), str(place["id"]),
			"%s reports its own id" % place["id"])
		arena.call("_announce_world_rule")
		arena.call("_raid")
		var offsets: Array[Vector2] = _offsets(arena)
		# A vigil queues its first group now and the second a few seconds later.
		var least: int = 4 if str(place["id"]) == "ruins" else 5
		_expect_true(offsets.size() >= least, "%s raid queues a pack (%d)" % [place["id"], offsets.size()])
		for offset in offsets:
			var at: Vector2 = CENTER + offset
			_expect_true(Room.PLAY.grow(1.0).has_point(at),
				"%s raid stays inside the play area %s" % [place["id"], at])
			_expect_true(offset.length() >= 140.0,
				"%s raid never spawns on top of you (%.0f)" % [place["id"], offset.length()])
		(arena.get("_raid_queue") as Array).clear()
		await get_tree().process_frame
	# A ruins vigil schedules its second beat; leave that place so it cannot land in the next test.
	arena.set("_zone_serial", int(arena.get("_zone_serial")) + 1)


## A wall: one row (or more) straight across the approach, with a two-lane gap that is not at
## either end, so there is always a place to slip through.
func _test_squall(arena: Node2D) -> void:
	for attempt in 12:
		_stand(arena, "res://resources/rooms/frost.tres", CENTER)
		arena.call("_queue_squall", 9)
		var offsets: Array[Vector2] = _offsets(arena)
		_expect_equal(offsets.size(), 9, "a squall of nine queues nine")
		if offsets.size() != 9:
			return
		# The wall runs across one axis; find which by which coordinate barely varies.
		var horizontal_spread: float = 0.0
		var vertical_spread: float = 0.0
		for offset in offsets:
			horizontal_spread = maxf(horizontal_spread, absf(offset.x))
			vertical_spread = maxf(vertical_spread, absf(offset.y))
		var wall_is_vertical: bool = horizontal_spread > vertical_spread
		var front: Array[float] = []
		var nearest: float = INF
		for offset in offsets:
			nearest = minf(nearest, absf(offset.x if wall_is_vertical else offset.y))
		for offset in offsets:
			var along: float = absf(offset.x if wall_is_vertical else offset.y)
			if along < nearest + 8.0:
				front.append(offset.y if wall_is_vertical else offset.x)
		front.sort()
		_expect_equal(front.size(), 7, "the front row is nine lanes with a two-lane door (%d)" % front.size())
		var wide_gaps: int = 0
		var narrow_gaps: int = 0
		for index in range(1, front.size()):
			var gap: float = front[index] - front[index - 1]
			if gap > 70.0:
				wide_gaps += 1
			elif gap > 20.0:
				narrow_gaps += 1
		_expect_equal(wide_gaps, 1, "the wall has exactly one door")
		_expect_equal(narrow_gaps, front.size() - 2, "everything else is a solid wall")
		# The door is inside the wall, not at its end.
		_expect_true(front[0] < front[front.size() - 1], "the wall has two ends")
		(arena.get("_raid_queue") as Array).clear()


## Three pods with a wide gap between each pair: sorted by angle, the three largest gaps all
## exceed 60 degrees and no pod is wider than 40.
func _test_tide(arena: Node2D) -> void:
	for many in [7, 9, 10, 13, 21]:
		_stand(arena, "res://resources/rooms/marsh.tres", CENTER)
		arena.call("_queue_tide", many)
		var offsets: Array[Vector2] = _offsets(arena)
		_expect_equal(offsets.size(), many, "a tide of %d queues %d" % [many, many])
		var angles: Array[float] = []
		for offset in offsets:
			angles.append(offset.angle())
		angles.sort()
		var gaps: Array[float] = []
		for index in angles.size():
			var gap: float = angles[0] + TAU - angles[index] if index == angles.size() - 1 \
				else angles[index + 1] - angles[index]
			gaps.append(rad_to_deg(gap))
		gaps.sort()
		gaps.reverse()
		_expect_true(gaps[0] > 60.0 and gaps[1] > 60.0 and gaps[2] > 60.0,
			"a tide of %d leaves three wide gaps (%.0f %.0f %.0f)" % [many, gaps[0], gaps[1], gaps[2]])
		# The fourth-largest gap is inside a pod: pods are tight.
		if gaps.size() > 3:
			var shown: PackedStringArray = PackedStringArray()
			for offset in offsets:
				shown.append("%.0f@%.0f" % [offset.length(), rad_to_deg(offset.angle())])
			_expect_true(gaps[3] < 40.0, "a pod of a tide of %d is tight (%.0f) %s" % [
				many, gaps[3], ", ".join(shown)])
		(arena.get("_raid_queue") as Array).clear()


## Two beats: the group ahead is queued now, the group behind a few seconds later, and only if
## the place is still the one it was called in.
func _test_vigil(arena: Node2D) -> void:
	_stand(arena, "res://resources/rooms/ruins.tres", CENTER, Vector2(150, 0))
	arena.call("_queue_vigil", 9)
	var first: Array[Vector2] = _offsets(arena)
	_expect_equal(first.size(), 5, "the first beat is a little over half the raid")
	for offset in first:
		_expect_true(offset.x > 0.0 and absf(rad_to_deg(offset.angle())) < 62.0,
			"the first group is ahead of you %s" % offset)
	await get_tree().create_timer(3.6).timeout
	var both: Array[Vector2] = _offsets(arena)
	_expect_equal(both.size(), 9, "the second beat arrives, making the whole raid")
	if both.size() == 9:
		for index in range(5, 9):
			_expect_true(both[index].x < 0.0, "the second group comes from behind %s" % both[index])

	# A raid that outlived its place is dropped, like every queued one.
	_stand(arena, "res://resources/rooms/ruins.tres", CENTER, Vector2(150, 0))
	arena.call("_queue_vigil", 9)
	arena.set("_zone_serial", int(arena.get("_zone_serial")) + 1)
	await get_tree().create_timer(3.6).timeout
	_expect_equal(_offsets(arena).size(), 5, "a second beat for a place you left never arrives")
	(arena.get("_raid_queue") as Array).clear()


func _finish() -> void:
	if _failed > 0:
		printerr("raid-formations test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("raid-formations test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("raid-formations test aborted: user:// path is not isolated — ", user_root)
	return safe


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)
