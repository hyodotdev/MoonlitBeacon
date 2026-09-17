class_name Room
extends Node2D

## One room. Bake the backdrop from a seed.
##
## The title forest embeds 1,294 trees in the scene file. Three maps that way
## would dump 30,000 lines into the repo and make moving one tree a chore.
## Here **`RoomKind` and a seed alone build it on the spot.**
##
## The same seed always yields the same room. Change only the seed to vary each run.

## Copied straight from the KIND table in `tools/build_title_forest.py`.
##
## **Every entry is a full tile verified by alpha bounding box.** Cutting a large
## tree at 48px once sheared the canopy's right edge into a straight line. Real
## width is 64. Re-measure alpha before adding new values.
const KIND: Dictionary = {
	"bigA": Rect2(0, 32, 64, 48), "bigB": Rect2(64, 32, 64, 48),
	"bigC": Rect2(256, 32, 64, 48), "bigD": Rect2(320, 32, 64, 48),
	"dead": Rect2(0, 80, 64, 48),
	"sm0": Rect2(0, 0, 32, 32), "sm1": Rect2(32, 0, 32, 32),
	"sm2": Rect2(64, 0, 32, 32), "sm3": Rect2(96, 0, 32, 32),
	"sm8": Rect2(256, 0, 32, 32), "sm9": Rect2(288, 0, 32, 32),
	"mid": Rect2(96, 128, 32, 32),
	"log": Rect2(0, 128, 32, 32), "stump": Rect2(32, 128, 32, 32),
	"stump2": Rect2(64, 128, 16, 16), "branch": Rect2(80, 128, 16, 16),
	"deadstub": Rect2(64, 144, 16, 16), "twig": Rect2(80, 144, 16, 16),
	"rockA": Rect2(208, 128, 32, 32), "rockB": Rect2(256, 128, 32, 32),
	"rockS": Rect2(240, 144, 16, 16), "rockS2": Rect2(288, 144, 16, 16),
	"bush": Rect2(192, 144, 16, 16),
}

## Intact props picked from the terrain-only sheet.
##
## Field 48px grass islands are one rounded tile; camp props were checked against
## their alpha edges. The camp hearth (192,80,32,30) looks like a beacon, so it
## is left out on purpose.
const PROP_KIND: Dictionary = {
	"field_grass_light": Rect2(0, 48, 48, 48),
	"field_grass_dark": Rect2(0, 96, 48, 48),
	"camp_tent_a": Rect2(64, 0, 48, 48),
	"camp_tent_b": Rect2(112, 0, 48, 48),
	"camp_tent_torn": Rect2(160, 0, 48, 48),
	"camp_barrels": Rect2(48, 16, 16, 32),
	"camp_barrels_light": Rect2(48, 48, 16, 32),
	"camp_chest": Rect2(64, 96, 32, 32),
	"camp_bench": Rect2(0, 112, 48, 16),
	"camp_crate": Rect2(48, 112, 16, 16),
	"camp_bedroll": Rect2(112, 128, 16, 16),
}

## Full map size. **Much larger than the screen (808×360).**
##
## One room as one screen is gone. The camera follows and also moves vertically.
## Not fitting on screen is the point — not knowing what emerges from the dark builds tension.
const MAP: Vector2 = Vector2(1900, 1180)

## Base internal viewport size and world-camera zoom. Real world visible area is
## `VIEW / WORLD_CAMERA_ZOOM`; Arena and density tests share this single value.
const VIEW: Vector2 = Vector2(808, 360)
const WORLD_CAMERA_ZOOM: float = 4.0 / 3.0

## Walkable interior. Outside this is the tree belt.
##
## Old `DEFAULT_BOUNDS` was Rect2(96, 150, 616, 172) — a 172px-tall strip.
## Drawing a perspective forest ate the top with trees. A room is a clearing
## walled on all sides, so the top can open further. Area grows about 1.3×.
const PLAY: Rect2 = Rect2(90, 90, 1720, 1000)

## Vertical span where doors open. Only at this height do you cross to the next room.
##
## At 34, walking down and hugging the right edge did nothing. Players scraped
## the wall without knowing a door was there. At 46 the passage matches the visible width.
const DOOR_HALF_HEIGHT: float = 46.0

## Moonlight under the door. Reuses the beacon ring — already a round moonlight graphic.
const DOOR_GLOW: Texture2D = preload("res://assets/derived/ui/charge_ring.png")

## Four cells on the first row of the custom obstacle sheet. Art is drawn in
## 64×64 with feet at y=50; the collision circle fits the ground part of the silhouette.
const OBSTACLE_REGIONS: Array[Rect2] = [
	Rect2(0, 0, 64, 64),
	Rect2(64, 0, 64, 64),
	Rect2(128, 0, 64, 64),
	Rect2(192, 0, 64, 64),
]
const OBSTACLE_RADII: Array[float] = [25.0, 24.0, 26.0, 27.0]
const OBSTACLE_SPRITE_OFFSET: Vector2 = Vector2(-32, -50)
const OBSTACLE_GAP: float = 34.0
const MOTION_STEP: float = 4.0
const OBSTACLE_COLUMNS: Array[float] = [0.12, 0.28, 0.42, 0.58, 0.72, 0.88]
const OBSTACLE_ROWS: Array[float] = [0.18, 0.34, 0.66, 0.82]
const MIDDLE_COLUMNS: Array[float] = [0.18, 0.365, 0.635, 0.82]
const OBSTACLE_JITTER: Vector2 = Vector2(54.0, 42.0)
const COVERAGE_JITTER_SCALE: float = 0.45

## Map start, four doors, and eight normal spawns stay clear regardless of seed.
##
## Beacons are rechecked by the arena each time, but start and doors are fixed
## coordinates. Reserve these zones at placement so the first frame in a new room
## never stands inside a structure. Door radius 120 covers the edge door and the
## 42px inward entrance together.
const RESERVED_POINTS: Array[Vector2] = [
	Vector2(950, 590),
	Vector2(124, 590), Vector2(1776, 590),
	Vector2(950, 124), Vector2(950, 1056),
	Vector2(160, 160), Vector2(950, 130), Vector2(1740, 160),
	Vector2(130, 590), Vector2(1770, 590),
	Vector2(160, 1020), Vector2(950, 1050), Vector2(1740, 1020),
]
const RESERVED_RADII: Array[float] = [
	140.0,
	120.0, 120.0, 120.0, 120.0,
	58.0, 58.0, 58.0, 58.0, 58.0, 58.0, 58.0, 58.0,
]

@onready var _ground: Sprite2D = $Ground
@onready var _structures: Node2D = $Structures
@onready var _decor: Node2D = $Decor

var kind: RoomKind = null
## `{at: Vector2, radius: float, variant: int}`. No dozens of engine physics nodes —
## the player and every spirit slide on the same small circle list.
var _obstacles: Array[Dictionary] = []

## Do not re-upload the same small floor tile to the GPU each cycle.
##
## Forest uses a finished 128px texture as-is; field and camp cut once from the
## atlas and store here. Cache size is at most the terrain count, so memory stays flat.
static var _floor_cache: Dictionary = {}


## Bake the room. The arena calls this.
##
func build(room_kind: RoomKind, seed_value: int) -> void:
	kind = room_kind
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var obstacle_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	obstacle_rng.seed = hash([seed_value, "terrain-obstacles", int(kind.encounter)])

	modulate = kind.tint
	_ground.texture = _floor_tile()
	_ground.modulate = kind.floor_tint

	_clear_children(_decor)
	_clear_children(_structures)
	_obstacles.clear()

	# Place collision structures first. Later decor reads these circles and sidesteps big silhouettes.
	# Separate RNG, so tweaking decor count alone does not move combat terrain.
	_scatter_obstacles(obstacle_rng)
	_scatter_border(rng)
	_scatter_inside(rng)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


## Place real blocking structures in a layout that differs per terrain.
##
## Forest bends paths between corner thickets; field spaces cover far apart;
## camp leaves a central escape between upper and lower barricades. Coordinates
## add only seed jitter on normalized anchors, so the same seed makes the same path.
func _scatter_obstacles(rng: RandomNumberGenerator) -> void:
	if kind.obstacle_tileset == null or kind.obstacle_count <= 0:
		return
	var anchors: Array[Vector2] = _obstacle_anchors()
	var count: int = mini(kind.obstacle_count, anchors.size())
	for index in count:
		var base: Vector2 = PLAY.position + Vector2(
			anchors[index].x * PLAY.size.x,
			anchors[index].y * PLAY.size.y)
		var placed: bool = false
		for attempt in 24:
			# Every tactical grid keeps real 4/3 screen density even on retries.
			# Wide re-search can push edge-sample structures off screen.
			var at: Vector2 = base + Vector2(
				rng.randf_range(-OBSTACLE_JITTER.x, OBSTACLE_JITTER.x) \
					* COVERAGE_JITTER_SCALE,
				rng.randf_range(-OBSTACLE_JITTER.y, OBSTACLE_JITTER.y) \
					* COVERAGE_JITTER_SCALE)
			var variant: int = rng.randi_range(0, OBSTACLE_REGIONS.size() - 1)
			var radius: float = OBSTACLE_RADII[variant]
			if not _can_place_obstacle(at, radius):
				continue
			_add_obstacle(at, radius, variant)
			placed = true
			break
		if not placed:
			push_warning("Room could not place structural obstacle %d in %s" % [
				index, kind.display_name])


func _obstacle_anchors() -> Array[Vector2]:
	match kind.encounter:
		RoomKind.Encounter.CROSSFIRE:
			# Cover alternating left/right across a crossfire field. Each 3×3 sample
			# screen gets at least two structures without forming a straight wall.
			return _coverage_anchors(
				PackedFloat32Array([-0.025, 0.015, -0.015, 0.025]))
		RoomKind.Encounter.CARAVAN:
			# Upper/lower camp barricades and side posts. Keep the middle crossroad and
			# vertical escape clear; two side covers even out chase directions.
			var camp: Array[Vector2] = _coverage_anchors(
				PackedFloat32Array([0.015, -0.01, 0.01, -0.015]))
			camp.append_array([Vector2(0.11, 0.50), Vector2(0.89, 0.50)])
			return camp
		_:
			# Forest adds top/bottom spine and left/right thickets to the outer clumps.
			# Leave the center start clear so an S-shaped escape runs between them.
			var forest: Array[Vector2] = _coverage_anchors(
				PackedFloat32Array([0.0, 0.025, -0.02, 0.015]))
			forest.append_array([
				Vector2(0.50, 0.26), Vector2(0.50, 0.74),
				Vector2(0.10, 0.50), Vector2(0.90, 0.50),
			])
			return forest


## Sparse tactical grid scaled from screen size versus map size.
##
## Four plain rows look like a corridor, so each row shifts in x and alternates
## up/down within the row. The middle row keeps only four cells, clear of start and doors.
func _coverage_anchors(row_shifts: PackedFloat32Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for row_index in OBSTACLE_ROWS.size():
		for column_index in OBSTACLE_COLUMNS.size():
			var alternating: float = 0.012 \
				if (row_index + column_index) % 2 == 0 else -0.012
			result.append(Vector2(
				clampf(
					OBSTACLE_COLUMNS[column_index] + row_shifts[row_index],
					0.10,
					0.90),
				OBSTACLE_ROWS[row_index] + alternating))

	# Keep a 140px radius clear around the center start (0.5, 0.5), yet place four
	# side cells so cover does not vanish from the 4/3 camera view. The inner two
	# stay inside the real visible width even at full allowed jitter.
	for middle_index in MIDDLE_COLUMNS.size():
		var middle_x: float = MIDDLE_COLUMNS[middle_index]
		var middle_y: float = 0.465 if middle_index % 2 == 0 else 0.535
		result.append(Vector2(middle_x, middle_y))
	return result


func _can_place_obstacle(at: Vector2, radius: float) -> bool:
	var inset: Rect2 = PLAY.grow(-(radius + 18.0))
	if not inset.has_point(at):
		return false
	for index in RESERVED_POINTS.size():
		var reserved_distance: float = radius + RESERVED_RADII[index]
		if at.distance_squared_to(RESERVED_POINTS[index]) \
				< reserved_distance * reserved_distance:
			return false
	for obstacle in _obstacles:
		var other_at: Vector2 = obstacle["at"]
		var other_radius: float = float(obstacle["radius"])
		var distance: float = radius + other_radius + OBSTACLE_GAP
		if at.distance_squared_to(other_at) < distance * distance:
			return false
	return true


func _add_obstacle(at: Vector2, radius: float, variant: int) -> void:
	var structure: Node2D = Node2D.new()
	structure.position = at
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = kind.obstacle_tileset
	sprite.region_enabled = true
	sprite.region_rect = OBSTACLE_REGIONS[variant]
	sprite.centered = false
	sprite.position = OBSTACLE_SPRITE_OFFSET
	structure.add_child(sprite)
	_structures.add_child(structure)
	_obstacles.append({"at": at, "radius": radius, "variant": variant})


## Can an object of radius `radius` sit at `at` without hitting structures or bounds.
##
## Beacons, spawns, player, and spirits all share this test. Add `margin` only when
## art and interact range must stay clear too, as with beacons.
func is_clear(at: Vector2, radius: float = 0.0, margin: float = 0.0) -> bool:
	var clearance: float = maxf(radius + margin, 0.0)
	var inset: Rect2 = PLAY.grow(-clearance)
	if not inset.has_point(at):
		return false
	for obstacle in _obstacles:
		var center: Vector2 = obstacle["at"]
		var distance: float = float(obstacle["radius"]) + clearance
		if at.distance_squared_to(center) < distance * distance:
			return false
	return true


## Push a blocked point to the nearest clear spot.
##
## Structures sit far enough apart that one or two pushes usually finish. Even the
## worst multi-circle overlap tries twelve pushes, then a fixed-angle ring search.
func nearest_clear(at: Vector2, radius: float = 0.0, margin: float = 0.0) -> Vector2:
	var clearance: float = maxf(radius + margin, 0.0)
	var result: Vector2 = _clamp_with_clearance(at, clearance)
	for pass_index in 12:
		var moved: bool = false
		for obstacle_index in _obstacles.size():
			var obstacle: Dictionary = _obstacles[obstacle_index]
			var center: Vector2 = obstacle["at"]
			var distance: float = float(obstacle["radius"]) + clearance
			var offset: Vector2 = result - center
			if offset.length_squared() >= distance * distance:
				continue
			if offset.length_squared() < 0.0001:
				offset = Vector2.RIGHT.rotated(float(obstacle_index) * 0.73)
			result = center + offset.normalized() * distance
			result = _clamp_with_clearance(result, clearance)
			moved = true
		if not moved and is_clear(result, radius, margin):
			return result
		# Consume the loop index for real so intent stays without a GDScript warning.
		if pass_index == 11:
			break

	var origin: Vector2 = _clamp_with_clearance(at, clearance)
	for ring in range(1, 25):
		var reach: float = float(ring) * 10.0
		for spoke in 16:
			var candidate: Vector2 = origin + Vector2.RIGHT.rotated(
				TAU * float(spoke) / 16.0) * reach
			candidate = _clamp_with_clearance(candidate, clearance)
			if is_clear(candidate, radius, margin):
				return candidate
	return result


## Split one physics tick of motion into small steps and slide along circle structures.
##
## Player and spirits call the same path, so neither alone cheats through walls.
## `steer_around` is only for AI that keeps re-aiming. Head-on into a circle center
## makes ordinary tangent projection zero and sticks forever on the same rim point,
## so each structure steps aside a fixed way to break the deadlock. Player motion and
## locked-direction charges do not rewrite the input path.
func resolve_terrain_motion(
		at: Vector2,
		motion: Vector2,
		radius: float = 4.0,
		steer_around: bool = false,
	) -> Vector2:
	var result: Vector2 = nearest_clear(at, radius)
	if motion.length_squared() < 0.0001:
		return result
	var steps: int = maxi(ceili(motion.length() / MOTION_STEP), 1)
	var step: Vector2 = motion / float(steps)
	for index in steps:
		var wanted: Vector2 = _clamp_with_clearance(result + step, radius)
		var blocker_index: int = _blocking_obstacle_index(wanted, radius)
		if steer_around and blocker_index >= 0:
			var tangent: Vector2 = _avoidance_tangent(
				result, step, blocker_index)
			var slid: bool = false
			for direction in [tangent, -tangent]:
				var slide: Vector2 = _clamp_with_clearance(
					result + direction * step.length(), radius)
				slide = _push_from_obstacles(slide, radius, index)
				if is_clear(slide, radius) \
						and slide.distance_squared_to(result) > 0.0001:
					result = slide
					slid = true
					break
			if not slid:
				var blocked: Vector2 = _push_from_obstacles(
					wanted, radius, index)
				if is_clear(blocked, radius):
					result = blocked
			continue

		var candidate: Vector2 = wanted
		candidate = _push_from_obstacles(candidate, radius, index)
		if is_clear(candidate, radius):
			result = candidate
	return result


## First structure a circular body meets traveling from `from` to `to`.
##
## Result is `{at, normal, obstacle_index, fraction}`, or empty if none.
## Solves the whole segment against an expanded hit circle, not just endpoints, so
## large-delta projectiles do not tunnel through thin structures.
func first_terrain_intersection(
		from: Vector2,
		to: Vector2,
		radius: float = 0.0,
	) -> Dictionary:
	var motion: Vector2 = to - from
	var motion_squared: float = motion.length_squared()
	var best_fraction: float = INF
	var best_index: int = -1
	var sweep_radius: float = maxf(radius, 0.0)
	var low_x: float = minf(from.x, to.x)
	var high_x: float = maxf(from.x, to.x)
	var low_y: float = minf(from.y, to.y)
	var high_y: float = maxf(from.y, to.y)

	for obstacle_index in _obstacles.size():
		var obstacle: Dictionary = _obstacles[obstacle_index]
		var center: Vector2 = obstacle["at"]
		var expanded: float = float(obstacle["radius"]) + sweep_radius
		# Hostile bolts (24-cap) call this every physics tick. Compare the segment AABB
		# to the circle bounds first so distant ones never reach a square-root.
		if center.x + expanded < low_x or center.x - expanded > high_x \
				or center.y + expanded < low_y or center.y - expanded > high_y:
			continue
		var relative: Vector2 = from - center
		var c: float = relative.length_squared() - expanded * expanded
		var fraction: float = INF
		if c <= 0.0:
			fraction = 0.0
		elif motion_squared > 0.000001:
			var b: float = 2.0 * relative.dot(motion)
			var discriminant: float = b * b - 4.0 * motion_squared * c
			if discriminant >= 0.0:
				var root: float = (-b - sqrt(discriminant)) \
					/ (2.0 * motion_squared)
				if root >= 0.0 and root <= 1.0:
					fraction = root
		if fraction < best_fraction:
			best_fraction = fraction
			best_index = obstacle_index

	if best_index < 0:
		return {}
	var hit_at: Vector2 = from + motion * best_fraction
	var hit_center: Vector2 = _obstacles[best_index]["at"]
	var normal: Vector2 = hit_at - hit_center
	if normal.length_squared() <= 0.000001:
		normal = -motion.normalized() if motion_squared > 0.000001 else Vector2.RIGHT
	else:
		normal = normal.normalized()
	return {
		"at": hit_at,
		"normal": normal,
		"obstacle_index": best_index,
		"fraction": best_fraction,
	}


## Light bool API over the terrain sweep. Callers that need no hit position —
## hostile projectiles, line-of-sight — need not carry a dictionary result outward.
func segment_hits_terrain(
		from: Vector2,
		to: Vector2,
		radius: float = 0.0,
	) -> bool:
	return not first_terrain_intersection(from, to, radius).is_empty()


func _blocking_obstacle_index(at: Vector2, radius: float) -> int:
	for obstacle_index in _obstacles.size():
		var obstacle: Dictionary = _obstacles[obstacle_index]
		var center: Vector2 = obstacle["at"]
		var distance: float = float(obstacle["radius"]) + radius
		if at.distance_squared_to(center) < distance * distance:
			return obstacle_index
	return -1


## Follow the current motion's tangent; on a dead-on hit pick turn side from the
## structure index. After the first step the new tangent keeps choosing the same
## side so motion does not jitter left/right.
func _avoidance_tangent(
		at: Vector2,
		step: Vector2,
		obstacle_index: int,
	) -> Vector2:
	var center: Vector2 = _obstacles[obstacle_index]["at"]
	var normal: Vector2 = at - center
	if normal.length_squared() < 0.0001:
		normal = -step.normalized()
	else:
		normal = normal.normalized()

	var tangent: Vector2 = step - normal * step.dot(normal)
	if tangent.length_squared() <= step.length_squared() * 0.0001:
		var turn: float = 1.0 if obstacle_index % 2 == 0 else -1.0
		return normal.rotated(turn * PI * 0.5)
	return tangent.normalized()


func _push_from_obstacles(at: Vector2, radius: float, step_index: int) -> Vector2:
	var result: Vector2 = at
	for pass_index in 4:
		var moved: bool = false
		for obstacle_index in _obstacles.size():
			var obstacle: Dictionary = _obstacles[obstacle_index]
			var center: Vector2 = obstacle["at"]
			var distance: float = float(obstacle["radius"]) + radius
			var offset: Vector2 = result - center
			if offset.length_squared() >= distance * distance:
				continue
			if offset.length_squared() < 0.0001:
				offset = Vector2.RIGHT.rotated(
					float(step_index + obstacle_index + pass_index) * 0.61)
			result = center + offset.normalized() * distance
			result = _clamp_with_clearance(result, radius)
			moved = true
		if not moved:
			break
	return result


func _clamp_with_clearance(at: Vector2, clearance: float) -> Vector2:
	return Vector2(
		clampf(at.x, PLAY.position.x + clearance, PLAY.end.x - clearance),
		clampf(at.y, PLAY.position.y + clearance, PLAY.end.y - clearance))


## Narrow API so deterministic / safe-placement regression tests do not depend on engine node order.
func terrain_obstacle_count() -> int:
	return _obstacles.size()


func terrain_obstacle_signature() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for obstacle in _obstacles:
		var at: Vector2 = obstacle["at"]
		parts.append("%d,%d,%d" % [
			roundi(at.x), roundi(at.y), int(obstacle["variant"])])
	return "|".join(parts)


func terrain_obstacle_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for obstacle in _obstacles:
		result.append(obstacle.duplicate())
	return result


## Cut the named interior piece from the floor sheet into a repeatable small texture.
func _floor_tile() -> Texture2D:
	if kind.floor_texture == null:
		return null
	if kind.floor_region.size.x <= 0 or kind.floor_region.size.y <= 0:
		return kind.floor_texture

	var key: String = "%s:%d,%d,%d,%d" % [
		kind.floor_texture.resource_path,
		kind.floor_region.position.x,
		kind.floor_region.position.y,
		kind.floor_region.size.x,
		kind.floor_region.size.y,
	]
	if _floor_cache.has(key):
		return _floor_cache[key] as Texture2D

	var source: Image = kind.floor_texture.get_image()
	if source == null or source.is_empty():
		return kind.floor_texture
	var bounds: Rect2i = Rect2i(Vector2i.ZERO, source.get_size())
	var region: Rect2i = kind.floor_region.intersection(bounds)
	if region.size != kind.floor_region.size:
		push_warning("Room floor_region is outside its texture: %s" % kind.display_name)
		return kind.floor_texture

	var tile: ImageTexture = ImageTexture.create_from_image(source.get_region(region))
	_floor_cache[key] = tile
	return tile






## Ring trees along the edge to form a wall.
##
## No collision bodies. The player is blocked by clamping coordinates —
## attaching colliders to hundreds of trees would be a whole other story.
## Pull into the playable area.
##
## Raids place spirits on a ring around the player; at the map edge
## **half that ring sits outside the wall.** Spirits spawned outside never walk
## in, so the raid count is wrong. Pull inward so the count matches.
func clamp_to_play(at: Vector2) -> Vector2:
	return Vector2(
		clampf(at.x, PLAY.position.x, PLAY.end.x),
		clampf(at.y, PLAY.position.y, PLAY.end.y))


func _scatter_border(rng: RandomNumberGenerator) -> void:
	for i in kind.border_count:
		_place(rng, kind.tree_kinds, _border_point(rng), rng.randf_range(0.85, 1.0))


## Any point inside the border belt.
func _border_point(rng: RandomNumberGenerator) -> Vector2:
	var side: int = rng.randi_range(0, 3)
	match side:
		0:  # top
			return Vector2(rng.randf_range(-40, MAP.x + 40), rng.randf_range(-40, PLAY.position.y))
		1:  # bottom
			return Vector2(rng.randf_range(-40, MAP.x + 40), rng.randf_range(PLAY.end.y, MAP.y + 40))
		2:  # left
			return Vector2(rng.randf_range(-40, PLAY.position.x), rng.randf_range(-40, MAP.y + 40))
		_:  # right
			return Vector2(rng.randf_range(PLAY.end.x, MAP.x + 40), rng.randf_range(-40, MAP.y + 40))




## Fill the interior.
##
## **Border alone turns the screen into a prairie.** With a 1900×1180 map and trees
## only on the rim, the 808×360 view showed only grass. That really happened.
##
## Scatter trees inside too, **clumped like thickets.** Even scatter looks artificial
## and makes no terrain to dodge through. Clumps leave escape lanes between them.
func _scatter_inside(rng: RandomNumberGenerator) -> void:
	# Tree clumps. Two to five gather in one spot.
	for i in kind.clump_count:
		var center: Vector2 = Room.MAP * 0.5
		for attempt in 10:
			center = Vector2(
				rng.randf_range(PLAY.position.x + 60, PLAY.end.x - 60),
				rng.randf_range(PLAY.position.y + 60, PLAY.end.y - 40))
			if is_clear(center, 46.0):
				break
		for j in rng.randi_range(2, 5):
			var at: Vector2 = center + Vector2(
				rng.randf_range(-52, 52), rng.randf_range(-34, 34))
			_place(rng, kind.tree_kinds, at, rng.randf_range(0.8, 0.98))

	# Dedicated props take slots from the small-decor budget. Combined count is always
	# `decor_count`, so field or camp never grow more nodes than forest.
	var prop_count: int = mini(kind.prop_count, kind.decor_count) \
		if kind.prop_tileset != null and not kind.prop_kinds.is_empty() else 0
	var small_count: int = maxi(kind.decor_count - prop_count, 0)

	# Small decor. Scatter evenly so the floor does not look empty.
	for i in small_count:
		var at: Vector2 = Vector2(
			rng.randf_range(PLAY.position.x + 16, PLAY.end.x - 16),
			rng.randf_range(PLAY.position.y + 16, PLAY.end.y - 8))
		_place(rng, kind.decor_kinds, at, rng.randf_range(0.7, 0.92))

	_scatter_props(rng, prop_count)


## Scatter field grass islands and camp tents/crates.
##
## Try a 52px gap first so large props do not fully overlap. Even on a packed map
## do not reroll forever — after twelve attempts take the last spot.
func _scatter_props(rng: RandomNumberGenerator, count: int) -> void:
	var placed: Array[Vector2] = []
	for i in count:
		var at: Vector2 = Vector2.ZERO
		for attempt in 12:
			at = Vector2(
				rng.randf_range(PLAY.position.x + 40, PLAY.end.x - 40),
				rng.randf_range(PLAY.position.y + 48, PLAY.end.y - 24))
			var clear: bool = is_clear(at, 34.0)
			for other in placed:
				if at.distance_squared_to(other) < 52.0 * 52.0:
					clear = false
					break
			if clear:
				break
		placed.append(at)
		_place_prop(rng, at)


func _place_prop(rng: RandomNumberGenerator, at: Vector2) -> void:
	var pick: String = kind.prop_kinds[rng.randi_range(0, kind.prop_kinds.size() - 1)]
	var region: Rect2 = PROP_KIND.get(pick, Rect2())
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		push_warning("Unknown room prop: %s" % pick)
		return

	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = kind.prop_tileset
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = false
	sprite.position = at - Vector2(region.size.x * 0.5, region.size.y)
	var shade: float = rng.randf_range(0.86, 1.0)
	sprite.modulate = Color(shade, shade, minf(shade * 1.04, 1.0), 1.0)
	_decor.add_child(sprite)


## Place one tile.
##
## **Anchor at the feet and let `y_sort` decide front/back.** Centering on the
## sprite sinks a large tree behind a small one.
func _place(rng: RandomNumberGenerator, names: PackedStringArray, at: Vector2, shade: float) -> void:
	if names.is_empty():
		return
	var pick: String = names[rng.randi_range(0, names.size() - 1)]
	var region: Rect2 = KIND.get(pick, KIND["bush"])

	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = kind.tileset
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = false
	sprite.position = at - Vector2(region.size.x * 0.5, region.size.y)
	sprite.modulate = Color(shade, shade, minf(shade * 1.06, 1.0), 1.0)
	_decor.add_child(sprite)
