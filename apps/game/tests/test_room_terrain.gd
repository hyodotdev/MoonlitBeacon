extends SceneTree

## Confirm terrain-structure determinism, safe zones, and real movement blocking.

const ROOM_SCENE: PackedScene = preload("res://scenes/gameplay/room.tscn")
const CASES: Array[Dictionary] = [
	{
		"path": "res://resources/rooms/forest.tres",
		"count": 32,
	},
	{
		"path": "res://resources/rooms/field.tres",
		"count": 28,
	},
	{
		"path": "res://resources/rooms/camp.tres",
		"count": 30,
	},
]
const SAFE_POINTS: Array[Vector2] = [
	Vector2(950, 590),
	Vector2(124, 590), Vector2(1776, 590),
	Vector2(950, 124), Vector2(950, 1056),
	Vector2(160, 160), Vector2(950, 130), Vector2(1740, 160),
	Vector2(130, 590), Vector2(1770, 590),
	Vector2(160, 1020), Vector2(950, 1050), Vector2(1740, 1020),
]
const CHASE_TICKS: int = 120
const CHASE_STEP: float = 2.0
const ROUTE_STEP: float = 40.0
const ROUTE_RADIUS: float = 8.0
const MIN_VISIBLE_STRUCTURES: int = 2
const DENSITY_REGRESSION_SEEDS: Array[int] = [70]
const VIEW_CENTERS: Array[Vector2] = [
	Vector2(494, 270), Vector2(950, 270), Vector2(1406, 270),
	Vector2(494, 590), Vector2(950, 590), Vector2(1406, 590),
	Vector2(494, 910), Vector2(950, 910), Vector2(1406, 910),
]
const ROUTE_TARGETS: Array[Vector2] = [
	Vector2(124, 590), Vector2(1776, 590),
	Vector2(950, 124), Vector2(950, 1056),
]

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var signatures: PackedStringArray = PackedStringArray()
	for terrain_case in CASES:
		var room: Room = ROOM_SCENE.instantiate() as Room
		root.add_child(room)
		var room_kind: RoomKind = load(str(terrain_case["path"])) as RoomKind
		var expected_count: int = int(terrain_case["count"])

		room.build(room_kind, 730_421)
		_expect_equal(
			room.terrain_obstacle_count(),
			expected_count,
			"%s structure count" % room_kind.display_name)
		_expect_true(
			room_kind.obstacle_tileset.resource_path.begins_with(
				"res://assets/custom/world/terrain/"),
			"%s custom structure sheet" % room_kind.display_name)
		var first_signature: String = room.terrain_obstacle_signature()
		signatures.append(first_signature)
		_expect_false(first_signature.is_empty(), "%s structure signature" % room_kind.display_name)

		# Rebaking the same node leaves no old structures and coordinates match exactly.
		room.build(room_kind, 730_421)
		_expect_equal(
			room.terrain_obstacle_count(),
			expected_count,
			"%s rebuild has no duplicate structures" % room_kind.display_name)
		_expect_equal(
			room.terrain_obstacle_signature(),
			first_signature,
			"%s same-seed determinism" % room_kind.display_name)

		room.build(room_kind, 730_422)
		_expect_not_equal(
			room.terrain_obstacle_signature(),
			first_signature,
			"%s different seed changes placement" % room_kind.display_name)
		room.build(room_kind, 730_421)

		for point in SAFE_POINTS:
			_expect_true(
				room.is_clear(point, 10.0),
				"%s start/gate/spawn safety %s" % [room_kind.display_name, point])

		var snapshot: Array[Dictionary] = room.terrain_obstacle_snapshot()
		_expect_false(snapshot.is_empty(), "%s collision circles exist" % room_kind.display_name)
		if not snapshot.is_empty():
			_test_visual_collision_contract(
				room, snapshot, expected_count, room_kind.display_name)
			_test_view_density(room, snapshot, room_kind.display_name)
			_test_swept_collision(room, snapshot[0], room_kind.display_name)
			_test_collision(room, snapshot[0], room_kind.display_name)
			var chase_obstacle: Dictionary = _find_chase_obstacle(room, snapshot)
			_expect_false(
				chase_obstacle.is_empty(),
				"%s repeated-chase test structure" % room_kind.display_name)
			if not chase_obstacle.is_empty():
				_test_repeated_chase(room, chase_obstacle, room_kind.display_name)
		for target in ROUTE_TARGETS:
			_expect_true(
				_has_safe_route(room, Room.MAP * 0.5, target),
				"%s safe reach from center to gate %s" % [
					room_kind.display_name, target])

		# This is the seed whose wide retry jitter pushed the lower-right structure off screen.
		for density_seed in DENSITY_REGRESSION_SEEDS:
			room.build(room_kind, density_seed)
			var density_snapshot: Array[Dictionary] = room.terrain_obstacle_snapshot()
			_expect_equal(
				density_snapshot.size(),
				expected_count,
				"%s density-regression seed %d structure count" % [
					room_kind.display_name, density_seed])
			_test_view_density(
				room,
				density_snapshot,
				"%s density-regression seed %d" % [room_kind.display_name, density_seed])

		room.queue_free()
		await process_frame

	_expect_not_equal(signatures[0], signatures[1], "forest vs field structure placements are distinct")
	_expect_not_equal(signatures[1], signatures[2], "field vs camp structure placements are distinct")

	if _failed > 0:
		printerr("terrain-structure test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("terrain-structure test passed — ", _checked, " case(s)")
	quit(0)


## Confirm each collision circle has one custom structure drawing at the same pivot.
## Contract that invisible walls and walkable large props do not come back.
func _test_visual_collision_contract(
		room: Room,
		obstacles: Array[Dictionary],
		expected_count: int,
		display_name: String,
	) -> void:
	var structures: Node2D = room.get_node("Structures") as Node2D
	_expect_equal(
		structures.get_child_count(),
		expected_count,
		"%s art and collision structure count 1:1" % display_name)
	var aligned: bool = true
	for index in obstacles.size():
		var structure: Node2D = structures.get_child(index) as Node2D
		var sprite: Sprite2D = structure.get_child(0) as Sprite2D
		var variant: int = int(obstacles[index]["variant"])
		aligned = aligned \
			and structure.position.is_equal_approx(obstacles[index]["at"]) \
			and sprite.texture == room.kind.obstacle_tileset \
			and sprite.region_enabled \
			and sprite.region_rect == Room.OBSTACLE_REGIONS[variant] \
			and sprite.position == Room.OBSTACLE_SPRITE_OFFSET
	_expect_true(aligned, "%s art pivot matches collision circle" % display_name)


## Sweep the playable region with a 3×3 live camera sample. In each of the nine samples,
## two large colliding structures are visible as real opaque pixels.
func _test_view_density(
		room: Room,
		obstacles: Array[Dictionary],
		display_name: String,
	) -> void:
	var camera_world_view: Vector2 = Room.VIEW / Room.WORLD_CAMERA_ZOOM
	var alpha_bounds: Array[Rect2] = _obstacle_alpha_bounds(room)
	for center in VIEW_CENTERS:
		var camera_rect: Rect2 = Rect2(
			center - camera_world_view * 0.5,
			camera_world_view)
		var count: int = 0
		for obstacle in obstacles:
			var variant: int = int(obstacle["variant"])
			var local_alpha: Rect2 = alpha_bounds[variant]
			var draw_rect: Rect2 = Rect2(
				(obstacle["at"] as Vector2) + Room.OBSTACLE_SPRITE_OFFSET \
					+ local_alpha.position,
				local_alpha.size)
			if camera_rect.intersects(draw_rect):
				count += 1
		_expect_true(
			count >= MIN_VISIBLE_STRUCTURES,
			"%s on-screen cover density %s (%d)" % [display_name, center, count])

	_test_anchor_extremes(room, alpha_bounds, display_name)


## Live PNG silhouette bounds excluding the cell's transparent padding.
func _obstacle_alpha_bounds(room: Room) -> Array[Rect2]:
	var image: Image = room.kind.obstacle_tileset.get_image()
	var result: Array[Rect2] = []
	for region in Room.OBSTACLE_REGIONS:
		var min_x: int = int(region.size.x)
		var min_y: int = int(region.size.y)
		var max_x: int = -1
		var max_y: int = -1
		for local_y in int(region.size.y):
			for local_x in int(region.size.x):
				var source: Vector2i = Vector2i(region.position) \
					+ Vector2i(local_x, local_y)
				if image.get_pixelv(source).a <= 0.0:
					continue
				min_x = mini(min_x, local_x)
				min_y = mini(min_y, local_y)
				max_x = maxi(max_x, local_x)
				max_y = maxi(max_y, local_y)
		_expect_true(max_x >= min_x and max_y >= min_y, "structure variant alpha silhouette exists")
		result.append(Rect2(
			Vector2(min_x, min_y),
			Vector2(max_x - min_x + 1, max_y - min_y + 1)))
	return result


## Every anchor, however structure variants and allowed jitter corners combine, must show
## at least two must be visible. Stops a check that only one RNG seed would pass.
func _test_anchor_extremes(
		room: Room,
		alpha_bounds: Array[Rect2],
		display_name: String,
	) -> void:
	var camera_size: Vector2 = Room.VIEW / Room.WORLD_CAMERA_ZOOM
	var jitter: Vector2 = Room.OBSTACLE_JITTER * Room.COVERAGE_JITTER_SCALE
	var corners: Array[Vector2] = [
		Vector2(-jitter.x, -jitter.y), Vector2(jitter.x, -jitter.y),
		Vector2(-jitter.x, jitter.y), Vector2(jitter.x, jitter.y),
	]
	var anchors: Array[Vector2] = room._obstacle_anchors()
	var anchor_count: int = mini(room.kind.obstacle_count, anchors.size())
	for center in VIEW_CENTERS:
		var camera_rect: Rect2 = Rect2(center - camera_size * 0.5, camera_size)
		var guaranteed_visible: int = 0
		for index in anchor_count:
			var base: Vector2 = Room.PLAY.position + Vector2(
				anchors[index].x * Room.PLAY.size.x,
				anchors[index].y * Room.PLAY.size.y)
			var visible_at_all_extremes: bool = true
			for local_alpha in alpha_bounds:
				for corner in corners:
					var draw_rect: Rect2 = Rect2(
						base + corner + Room.OBSTACLE_SPRITE_OFFSET \
							+ local_alpha.position,
						local_alpha.size)
					if not camera_rect.intersects(draw_rect):
						visible_at_all_extremes = false
						break
				if not visible_at_all_extremes:
					break
			if visible_at_all_extremes:
				guaranteed_visible += 1
		_expect_true(
			guaranteed_visible >= MIN_VISIBLE_STRUCTURES,
			"%s structure anchor worst-combo density %s (%d)" % [
				display_name, center, guaranteed_visible])


## Circle-segment sweep must block long low-FPS moves and must not block segments outside the tangent.
func _test_swept_collision(
		room: Room,
		obstacle: Dictionary,
		display_name: String,
	) -> void:
	var center: Vector2 = obstacle["at"]
	var projectile_radius: float = 8.0
	var expanded: float = float(obstacle["radius"]) + projectile_radius
	var from: Vector2 = center - Vector2(expanded + 10.0, 0.0)
	var to: Vector2 = center + Vector2(expanded + 10.0, 0.0)
	var hit: Dictionary = room.first_terrain_intersection(
		from, to, projectile_radius)
	var repeat: Dictionary = room.first_terrain_intersection(
		from, to, projectile_radius)
	_expect_false(hit.is_empty(), "%s projectile sweep detects structure" % display_name)
	if not hit.is_empty():
		_expect_true(
			is_equal_approx(
				(hit["at"] as Vector2).distance_to(center), expanded),
			"%s projectile sweep hit point" % display_name)
		_expect_true(
			float(hit["fraction"]) > 0.0 and float(hit["fraction"]) < 1.0,
			"%s projectile sweep segment ratio" % display_name)
		_expect_equal(hit, repeat, "%s projectile sweep determinism" % display_name)
	_expect_true(
		room.segment_hits_terrain(from, to, projectile_radius),
		"%s long-segment cover" % display_name)
	var miss_y: float = center.y + expanded + 1.0
	_expect_false(
		room.segment_hits_terrain(
			Vector2(from.x, miss_y), Vector2(to.x, miss_y), projectile_radius),
		"%s segment outside structure passes" % display_name)
	var inside: Dictionary = room.first_terrain_intersection(
		center, center, projectile_radius)
	_expect_equal(
		float(inside.get("fraction", -1.0)),
		0.0,
		"%s resting circle inside structure detected immediately" % display_name)


func _test_collision(room: Room, obstacle: Dictionary, display_name: String) -> void:
	var center: Vector2 = obstacle["at"]
	var obstacle_radius: float = float(obstacle["radius"])
	var actor_radius: float = 4.0
	var approach: float = obstacle_radius + actor_radius + 42.0
	var start: Vector2 = center - Vector2(approach, 0.0)
	var motion: Vector2 = Vector2(approach * 2.0, 0.0)
	var resolved: Vector2 = room.resolve_terrain_motion(start, motion, actor_radius)

	_expect_true(room.is_clear(resolved, actor_radius), "%s no intrusion after move" % display_name)
	_expect_true(
		resolved.x <= center.x - obstacle_radius - actor_radius + 0.5,
		"%s straight move does not tunnel through structures" % display_name)

	var recovered: Vector2 = room.nearest_clear(center, actor_radius)
	_expect_true(room.is_clear(recovered, actor_radius), "%s blocked spawn push-out" % display_name)
	_expect_true(
		recovered.distance_to(center) >= obstacle_radius + actor_radius - 0.1,
		"%s push-out distance" % display_name)


func _find_chase_obstacle(room: Room, obstacles: Array[Dictionary]) -> Dictionary:
	var actor_radius: float = 7.0
	for obstacle in obstacles:
		var center: Vector2 = obstacle["at"]
		var reach: float = float(obstacle["radius"]) + actor_radius + 42.0
		if room.is_clear(center - Vector2(reach, 0.0), actor_radius) \
				and room.is_clear(center + Vector2(reach, 0.0), actor_radius):
			return obstacle
	return {}


## Circle a front-facing collider for 120 ticks under live chase that re-aims at the player every tick.
## Do not only look at endpoints; check each move's distance, non-intrusion, and side detour to block teleport-through.
func _test_repeated_chase(
		room: Room,
		obstacle: Dictionary,
		display_name: String,
	) -> void:
	var center: Vector2 = obstacle["at"]
	var actor_radius: float = 7.0
	var clearance: float = float(obstacle["radius"]) + actor_radius
	var reach: float = clearance + 42.0
	var start: Vector2 = center - Vector2(reach, 0.0)
	var target: Vector2 = center + Vector2(reach, 0.0)
	var first_path: PackedVector2Array = _trace_chase(
		room, start, target, actor_radius)
	var second_path: PackedVector2Array = _trace_chase(
		room, start, target, actor_radius)

	var all_clear: bool = true
	var bounded_steps: bool = true
	var max_lateral: float = 0.0
	for index in first_path.size():
		var point: Vector2 = first_path[index]
		all_clear = all_clear and room.is_clear(point, actor_radius)
		max_lateral = maxf(max_lateral, absf(point.y - center.y))
		if index > 0:
			bounded_steps = bounded_steps \
				and point.distance_to(first_path[index - 1]) <= CHASE_STEP + 0.01

	var finish: Vector2 = first_path[first_path.size() - 1]
	_expect_true(all_clear, "%s no structure intrusion during repeated chase" % display_name)
	_expect_true(bounded_steps, "%s no teleport during repeated chase" % display_name)
	_expect_true(
		max_lateral >= clearance - 0.5,
		"%s repeated chase detours around structure" % display_name)
	_expect_true(
		finish.x > center.x + clearance,
		"%s repeated chase reaches far side of structure" % display_name)
	_expect_true(
		finish.distance_to(target) <= CHASE_STEP + 0.01,
		"%s repeated chase approaches the target" % display_name)
	_expect_equal(first_path, second_path, "%s repeated chase determinism" % display_name)


## Pathfind from center to the four gates on a 40px grid. Diagonal moves also go through segment sweep so they
## cannot tunnel a corner. Directly confirm an exit remains even if structure density is raised.
func _has_safe_route(room: Room, start: Vector2, target: Vector2) -> bool:
	if not room.is_clear(start, ROUTE_RADIUS) \
			or not room.is_clear(target, ROUTE_RADIUS):
		return false
	var frontier: Array[Vector2i] = [Vector2i.ZERO]
	var visited: Dictionary = {Vector2i.ZERO: true}
	var cursor: int = 0
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP,
		Vector2i(1, 1), Vector2i(1, -1),
		Vector2i(-1, 1), Vector2i(-1, -1),
	]
	while cursor < frontier.size():
		var cell: Vector2i = frontier[cursor]
		cursor += 1
		var point: Vector2 = start + Vector2(cell) * ROUTE_STEP
		if point.distance_to(target) <= ROUTE_STEP * 1.5 \
				and not room.segment_hits_terrain(
					point, target, ROUTE_RADIUS):
			return true
		for direction in directions:
			var next_cell: Vector2i = cell + direction
			if visited.has(next_cell):
				continue
			var next_point: Vector2 = start + Vector2(next_cell) * ROUTE_STEP
			if not room.is_clear(next_point, ROUTE_RADIUS):
				continue
			if room.segment_hits_terrain(point, next_point, ROUTE_RADIUS):
				continue
			visited[next_cell] = true
			frontier.append(next_cell)
	return false


func _trace_chase(
		room: Room,
		start: Vector2,
		target: Vector2,
		actor_radius: float,
	) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array([start])
	var current: Vector2 = start
	for tick in CHASE_TICKS:
		var to_target: Vector2 = target - current
		var motion: Vector2 = to_target.limit_length(CHASE_STEP)
		current = room.resolve_terrain_motion(
			current, motion, actor_radius, true)
		result.append(current)
	return result


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_not_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — both values were ", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)


func _expect_false(actual: bool, label: String) -> void:
	_expect_equal(actual, false, label)
