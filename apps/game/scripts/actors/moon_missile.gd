extends Node2D

## Moonlight meteor volley.
##
## On screen, up to eight shots still draw different curves as before, but one
## node owns one fired volley. At Lv20 max fire, about five volleys live
## instead of 38 nodes and physics callbacks, cutting call and CanvasItem
## cost without reducing shot count or damage.

const TURN_RATE: float = 6.0
const SCATTER: float = 1.15
const FREE_FLIGHT: float = 0.16
const STEER_INTERVAL: float = 1.0 / 15.0
const REACQUIRE_SPREAD: float = 0.06
const REACQUIRE_GAP: float = 0.18
const LIFETIME: float = 1.6
## If an existing lane's angle or steer order changes when power rises, a
## missile that was hitting the same target can miss at the next rank. Use
## fixed slots sized for the max volley.
const MAX_FORMATION_LANES: int = 8
const MAX_FORMATION_RINGS: int = 4
## Upgrades add one tail sample inside this cap.
const PROFILE_TRAIL_STEPS: int = 10
const TRAIL_INTERVAL: float = 1.0 / 15.0
const MISSILE_RADIUS: float = 6.0
const SPIRIT_BODY_RADIUS: float = 4.0
const SPIRIT_BODY_OFFSET: Vector2 = Vector2(0, -6)
const BLAST: float = 26.0
const FLASH_LIFETIME: float = 0.22
const FLASH_SEGMENTS: int = 20
## One physics move of a homing volley is about 8px. A 64px cell reads only
## spirits near the segment and still keeps a 26px splash inside a few
## neighbor cells.
const BODY_CELL: float = 64.0

## Volleys in the same arena see the same spirit list. At Lv20 about five
## volleys are live at once, so world coords and size are computed once per
## physics tick and shared, not re-read per volley.
static var _shared_geometry_key: int = 0
static var _shared_geometry_frame: int = -1
static var _shared_bodies: Array[Node2D] = []
static var _shared_centers: PackedVector2Array = PackedVector2Array()
static var _shared_body_radii: PackedFloat32Array = PackedFloat32Array()
static var _shared_body_cells: Dictionary = {}
static var _shared_max_body_radius: float = 0.0
## Late-game perf regression must not pass by "deleting enemies and shots."
## Tests only count real splash brute-force vs candidates reduced by spatial
## cells. Default false, so live combat pays only one condition per
## segment/blast, no counter cost.
static var _work_diagnostics: bool = false
static var _diagnostic_naive_checks: int = 0
static var _diagnostic_broadphase_checks: int = 0
static var _diagnostic_live_lanes: int = 0
static var _diagnostic_live_lane_peak: int = 0
static var _diagnostic_instances: Dictionary = {}

var damage: int = 10
var speed: float = 250.0
var pierce: int = 1
## Times invested in the Starfall line. Used only for visual rank.
var upgrade_rank: int = 0
## Gold volley look during moon-ember awakening. Does not touch damage or blast radius.
var awakened: bool = false
var attack_profile: Hero.AttackProfile = Hero.AttackProfile.WARDEN
var profile_primary: Color = Color(0.3, 0.68, 1.0, 1.0)
var profile_secondary: Color = Color(0.82, 0.95, 1.0, 1.0)
var vfx_tier: int = 0

var _candidates: Array[Node2D] = []
## Independent tests and old callers with no share key cache only their own instance.
var _geometry_cache_key: int = 0
var _positions: Array[Vector2] = []
var _headings: Array[Vector2] = []
var _targets: Array[Node2D] = []
var _life_lefts: Array[float] = []
var _free_lefts: Array[float] = []
var _pierces: Array[int] = []
var _damages: Array[int] = []
var _dead: Array[bool] = []
var _steer_lefts: Array[float] = []
var _steer_elapsed: Array[float] = []
var _seek_lefts: Array[float] = []
var _lane_delays: Array[float] = []
var _ages: Array[float] = []
var _lanes: Array[float] = []
var _anchors: Array[bool] = []
## Each shot keeps its own hits and afterimage. Inner arrays are small and live 1.6s.
var _hits: Array = []
var _trails: Array = []
var _flash_positions: Array[Vector2] = []
var _flash_lefts: Array[float] = []
## Eight shots in one volley do not recompute the same spirit coords and size
## every tick. Body info is built once per physics tick and every lane's
## sweep/splash shares it.
var _frame_bodies: Array[Node2D] = []
var _frame_centers: PackedVector2Array = PackedVector2Array()
var _frame_body_radii: PackedFloat32Array = PackedFloat32Array()
var _frame_body_cells: Dictionary = {}
var _frame_max_body_radius: float = 0.0
var _trail_left: float = 0.0
var _live_count: int = 0
## This instance's share of the global live-lane total during diagnostics.
## Always 0 in normal play; must clear on diagnostics end and node exit.
var _diagnostic_tracked_live_lanes: int = 0
## Count real `_draw()` notifications so a capture probe cannot mistake an
## old CanvasItem draw from before launch for a new volley's live art.
var _capture_draw_serial: int = 0
var _capture_launch_draw_serial: int = -1
var _capture_last_draw_live_lanes: int = 0
var _capture_last_draw_head_geometry_lanes: int = 0
var _capture_last_draw_trail_geometry_lanes: int = 0


func _ready() -> void:
	z_index = 3
	add_to_group("friendly_projectiles")
	set_process(false)


func _exit_tree() -> void:
	if _work_diagnostics:
		_diagnostic_release_lanes(_diagnostic_tracked_live_lanes)
		_diagnostic_instances.erase(get_instance_id())


func _process(delta: float) -> void:
	for i in range(_flash_lefts.size() - 1, -1, -1):
		_flash_lefts[i] -= delta
		if _flash_lefts[i] <= 0.0:
			_flash_lefts.remove_at(i)
			_flash_positions.remove_at(i)
	queue_redraw()
	if _flash_lefts.is_empty():
		set_process(false)
		if _live_count <= 0:
			queue_free()


func set_candidates(candidates: Array[Node2D], shared_cache_key: int = 0) -> void:
	_candidates = candidates
	_geometry_cache_key = shared_cache_key if shared_cache_key != 0 else get_instance_id()


func configure_profile(
		profile: Hero.AttackProfile,
		primary: Color,
		secondary: Color,
		tier: int,
		_lane_index: int = 0,
		_lane_total: int = 1,
	) -> void:
	attack_profile = profile
	profile_primary = primary
	profile_secondary = secondary
	vfx_tier = clampi(tier, 0, 5)


static func begin_work_diagnostics(active_projectiles: Array[Node] = []) -> void:
	_reset_work_diagnostic_state()
	_work_diagnostics = true
	_diagnostic_naive_checks = 0
	_diagnostic_broadphase_checks = 0
	_diagnostic_live_lanes = 0
	_diagnostic_live_lane_peak = 0
	# Volleys already in flight before sampling starts also enter the global
	# total. Later fire and blast increment in the same tick per instance, so
	# this does not depend on process_frame polling timing.
	for projectile in active_projectiles:
		if is_instance_valid(projectile) \
				and projectile.has_method("_seed_work_diagnostic_lanes"):
			projectile.call("_seed_work_diagnostic_lanes")


static func end_work_diagnostics() -> Dictionary:
	var result: Dictionary = {
		"naive_checks": _diagnostic_naive_checks,
		"broadphase_checks": _diagnostic_broadphase_checks,
		"live_lanes": _diagnostic_live_lanes,
		"live_lane_peak": _diagnostic_live_lane_peak,
	}
	_reset_work_diagnostic_state()
	return result


static func _reset_work_diagnostic_state() -> void:
	_work_diagnostics = false
	for reference_value in _diagnostic_instances.values():
		var reference: WeakRef = reference_value as WeakRef
		var projectile: Object = reference.get_ref() if reference != null else null
		if is_instance_valid(projectile) \
				and projectile.has_method("_clear_work_diagnostic_lanes"):
			projectile.call("_clear_work_diagnostic_lanes")
	_diagnostic_instances.clear()
	_diagnostic_naive_checks = 0
	_diagnostic_broadphase_checks = 0
	_diagnostic_live_lanes = 0
	_diagnostic_live_lane_peak = 0


func _seed_work_diagnostic_lanes() -> void:
	if not _work_diagnostics or _diagnostic_instances.has(get_instance_id()):
		return
	_diagnostic_tracked_live_lanes = maxi(_live_count, 0)
	_diagnostic_instances[get_instance_id()] = weakref(self)
	_diagnostic_live_lanes += _diagnostic_tracked_live_lanes
	_diagnostic_live_lane_peak = maxi(
		_diagnostic_live_lane_peak, _diagnostic_live_lanes)


func _track_diagnostic_launched_lane() -> void:
	if not _work_diagnostics:
		return
	if not _diagnostic_instances.has(get_instance_id()):
		_diagnostic_instances[get_instance_id()] = weakref(self)
	_diagnostic_tracked_live_lanes += 1
	_diagnostic_live_lanes += 1
	_diagnostic_live_lane_peak = maxi(
		_diagnostic_live_lane_peak, _diagnostic_live_lanes)


func _diagnostic_release_lanes(want: int) -> void:
	if not _work_diagnostics or want <= 0 \
			or _diagnostic_tracked_live_lanes <= 0:
		return
	var released: int = mini(want, _diagnostic_tracked_live_lanes)
	_diagnostic_tracked_live_lanes -= released
	_diagnostic_live_lanes = maxi(_diagnostic_live_lanes - released, 0)


func _clear_work_diagnostic_lanes() -> void:
	_diagnostic_tracked_live_lanes = 0


func collision_radius() -> float:
	return MISSILE_RADIUS


func blast_radius() -> float:
	return BLAST


func profile_id() -> int:
	return int(attack_profile)


func motion_signature() -> StringName:
	match attack_profile:
		Hero.AttackProfile.DANCER: return &"spiral_reacquire"
		Hero.AttackProfile.KEEPER: return &"heavy_lock"
		Hero.AttackProfile.KNIGHT: return &"silver_fan"
		Hero.AttackProfile.ECLIPSE: return &"eclipse_orbit"
		Hero.AttackProfile.SAGE: return &"constellation_step"
		_: return &"boomerang_curve"


func impact_signature() -> StringName:
	match attack_profile:
		Hero.AttackProfile.DANCER: return &"twin_arc_bloom"
		Hero.AttackProfile.KEEPER: return &"heavy_shock"
		Hero.AttackProfile.KNIGHT: return &"crescent_shards"
		Hero.AttackProfile.ECLIPSE: return &"ember_eclipse"
		Hero.AttackProfile.SAGE: return &"constellation_starburst"
		_: return &"round_return"


## Store combat capture may accept only the frame a real max volley is drawn.
## Release has no call path and no probe, and non-debug never publishes the value.
func debug_store_capture_lanes() -> Dictionary:
	if not OS.is_debug_build():
		return {}
	var viewport_rect: Rect2 = get_viewport().get_visible_rect().grow(-8.0)
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var missile_visible_in_tree: bool = is_inside_tree() and is_visible_in_tree()
	var effective_alpha: float = _debug_effective_canvas_alpha()
	var missile_opaque: bool = effective_alpha >= 0.99
	var draw_after_launch: bool = _capture_launch_draw_serial >= 0 \
		and _capture_draw_serial > _capture_launch_draw_serial
	var current_live_lanes: int = 0
	var current_head_geometry_lanes: int = 0
	var current_trail_geometry_lanes: int = 0
	var visible_lanes: int = 0
	for index in _positions.size():
		if index >= _dead.size() or _dead[index]:
			continue
		current_live_lanes += 1
		var head_geometry: bool = _debug_lane_head_geometry(index)
		var trail_geometry: bool = _debug_lane_trail_geometry(index)
		current_head_geometry_lanes += 1 if head_geometry else 0
		current_trail_geometry_lanes += 1 if trail_geometry else 0
		if missile_visible_in_tree and missile_opaque and draw_after_launch \
				and head_geometry and trail_geometry \
				and viewport_rect.has_point(canvas_transform * _positions[index]):
			visible_lanes += 1
	var head_geometry_ready: bool = _live_count > 0 \
		and current_live_lanes == _live_count \
		and current_head_geometry_lanes == _live_count \
		and _capture_last_draw_live_lanes == _live_count \
		and _capture_last_draw_head_geometry_lanes == _live_count
	var trail_geometry_ready: bool = _live_count > 0 \
		and current_live_lanes == _live_count \
		and current_trail_geometry_lanes == _live_count \
		and _capture_last_draw_live_lanes == _live_count \
		and _capture_last_draw_trail_geometry_lanes == _live_count
	if not head_geometry_ready or not trail_geometry_ready:
		visible_lanes = 0
	return {
		"live_lanes": _live_count,
		"visible_lanes": visible_lanes,
		"missile_visible_in_tree": missile_visible_in_tree,
		"effective_alpha": effective_alpha,
		"missile_opaque": missile_opaque,
		"draw_after_launch": draw_after_launch,
		"head_geometry_ready": head_geometry_ready,
		"trail_geometry_ready": trail_geometry_ready,
		"actual_head_geometry_lanes": current_head_geometry_lanes,
		"actual_trail_geometry_lanes": current_trail_geometry_lanes,
	}


func _debug_effective_canvas_alpha() -> float:
	var alpha: float = 1.0
	var item: CanvasItem = self
	var own_item: bool = true
	while item != null:
		alpha *= item.modulate.a
		if own_item:
			alpha *= item.self_modulate.a
		own_item = false
		item = item.get_parent() as CanvasItem
	return alpha


func _debug_lane_head_geometry(index: int) -> bool:
	if index < 0 or index >= _positions.size() \
			or index >= _headings.size() or index >= _ages.size():
		return false
	var rank: float = float(clampi(upgrade_rank, 0, 10))
	var radius: float = 3.2 + 0.18 * rank + (0.6 if awakened else 0.0)
	var head: Vector2 = to_local(_positions[index])
	var heading: Vector2 = _headings[index]
	if heading.length_squared() <= 0.000001:
		return false
	var side := Vector2(-heading.y, heading.x)
	var head_lines := PackedVector2Array()
	var halo_lines := PackedVector2Array()
	_append_profile_head(
		head_lines, halo_lines, head, heading, side, radius,
		upgrade_rank >= 3 or awakened, _ages[index])
	return _debug_segments_have_geometry(head_lines)


func _debug_lane_trail_geometry(index: int) -> bool:
	if index < 0 or index >= _trails.size():
		return false
	var trail: Array = _trails[index]
	if trail.size() < 2:
		return false
	for point_index in trail.size() - 1:
		var from_point: Vector2 = trail[point_index]
		var to_point: Vector2 = trail[point_index + 1]
		if from_point.distance_squared_to(to_point) > 0.000001:
			return true
	return false


func _debug_segments_have_geometry(
		lines: PackedVector2Array, first_index: int = 0) -> bool:
	for point_index in range(first_index, lines.size() - 1, 2):
		if lines[point_index].distance_squared_to(lines[point_index + 1]) \
				> 0.000001:
			return true
	return false


## Live game path. Latch the target list at once instead of one node per shot.
##
## If `lane_damages` is set, the total damage budget is already split. Extra
## shots must not clone `damage` whole and double or triple early power.
func launch_volley(
		targets: Array[Node2D],
		total: int,
		lane_damages: PackedInt32Array = PackedInt32Array()) -> void:
	if OS.is_debug_build():
		_capture_launch_draw_serial = _capture_draw_serial
	var many: int = maxi(total, 1)
	for i in many:
		var target: Node2D = targets[i % targets.size()] if not targets.is_empty() else null
		var lane_damage: int = lane_damages[i] if i < lane_damages.size() else damage
		_append_missile(target, i, many, lane_damage)
	queue_redraw()


## One-shot compat path for independent tests and old callers.
func launch(target: Node2D, index: int, total: int) -> void:
	if OS.is_debug_build():
		_capture_launch_draw_serial = _capture_draw_serial
	_append_missile(target, index, maxi(total, 1), damage)
	queue_redraw()


func _append_missile(
		target: Node2D, index: int, total: int, lane_damage: int) -> void:
	var start: Vector2 = global_position
	var toward: Vector2 = Vector2.RIGHT
	if target != null and is_instance_valid(target):
		toward = (target.global_position - start).normalized()
	# Slot 0 is the aimed meteor that inherits the old straight center shot's
	# power. Only the rest fan left/right so growing the volley cannot drop
	# the strongest shot from the center.
	var anchor: bool = index == 0
	var lane: float = _formation_lane(index, total)
	var profile_scatter: float = _profile_scatter_scale()
	# Warden boomerang wobble is also a per-lane constant. Per-shot random
	# after a power-up can make an existing lane miss by chance and reverse
	# effective damage.
	var jitter: float = 0.12 * sin(float(index) * 2.39996323) \
		if attack_profile == Hero.AttackProfile.WARDEN else 0.0
	if anchor:
		jitter = 0.0
	var heading: Vector2 = toward.rotated(
		lane * 2.0 * SCATTER * profile_scatter + jitter)
	var lane_delay: float = 0.0 if anchor or total <= 1 \
		else REACQUIRE_SPREAD * float(index) \
			/ float(MAX_FORMATION_LANES - 1)

	_positions.append(start)
	_headings.append(heading)
	_targets.append(target)
	_life_lefts.append(LIFETIME)
	_free_lefts.append(FREE_FLIGHT)
	_pierces.append(pierce)
	_damages.append(maxi(lane_damage, 1))
	_dead.append(false)
	_steer_lefts.append(
		STEER_INTERVAL * float(index) / float(MAX_FORMATION_LANES))
	_steer_elapsed.append(0.0)
	_seek_lefts.append(lane_delay)
	_lane_delays.append(lane_delay)
	_ages.append(0.0)
	_lanes.append(lane)
	_anchors.append(anchor)
	_hits.append([])
	_trails.append([])
	_live_count += 1
	if _work_diagnostics:
		_track_diagnostic_launched_lane()


func _formation_lane(index: int, total: int) -> float:
	if total <= 1 or index <= 0:
		return 0.0
	var ring: int = (index + 1) / 2
	var side: float = -1.0 if index % 2 == 1 else 1.0
	return side * 0.5 * float(ring) / float(MAX_FORMATION_RINGS)


func _physics_process(delta: float) -> void:
	if _live_count <= 0:
		return
	_cache_body_geometry()

	for i in _positions.size():
		if _dead[i]:
			continue
		_tick_missile(i, delta)

	if _live_count <= 0:
		set_physics_process(false)
		if _flash_lefts.is_empty():
			queue_free()
		return
	# Even if the tail is sampled at 15Hz, the bright head must move at every
	# physics position. Otherwise a 250px/s meteor jumps 16.7px and bursts
	# ahead of the visible head.
	queue_redraw()

	_trail_left -= delta
	if _trail_left <= 0.0:
		while _trail_left <= 0.0:
			_trail_left += TRAIL_INTERVAL
		for i in _positions.size():
			if _dead[i]:
				continue
			var trail: Array = _trails[i]
			trail.push_front(_positions[i])
			var keep: int = _visual_trail_steps()
			if trail.size() > keep:
				trail.resize(keep)


## Tail length independent of damage math. Grows a little at 0→2→4→6 investment.
func _visual_trail_steps() -> int:
	return mini(
		3 + ceili(float(maxi(upgrade_rank, 0)) * 0.5)
			+ (1 if awakened else 0) + ceili(float(vfx_tier) * 0.55),
		PROFILE_TRAIL_STEPS)


func _profile_scatter_scale() -> float:
	match attack_profile:
		Hero.AttackProfile.DANCER: return 0.92
		Hero.AttackProfile.KEEPER: return 0.34
		Hero.AttackProfile.KNIGHT: return 1.24
		Hero.AttackProfile.ECLIPSE: return 1.38
		Hero.AttackProfile.SAGE: return 0.58
		_: return 0.72


func _cache_body_geometry() -> void:
	var frame: int = Engine.get_physics_frames()
	if _geometry_cache_key != 0 \
			and _shared_geometry_key == _geometry_cache_key \
			and _shared_geometry_frame == frame:
		_frame_bodies = _shared_bodies
		_frame_centers = _shared_centers
		_frame_body_radii = _shared_body_radii
		_frame_body_cells = _shared_body_cells
		_frame_max_body_radius = _shared_max_body_radius
		return

	# Clearing last tick's shared Array would wipe values other volleys still
	# point at. Snapshot this tick into a new container, then share read-only.
	_frame_bodies = []
	_frame_centers = PackedVector2Array()
	_frame_body_radii = PackedFloat32Array()
	_frame_body_cells = {}
	_frame_max_body_radius = 0.0
	for body in _candidates:
		if not is_instance_valid(body) or not body.has_method("take_damage") \
				or not body.is_attackable():
			continue
		_frame_bodies.append(body)
		_frame_centers.append(body.to_global(SPIRIT_BODY_OFFSET))
		var body_scale: float = maxf(
			absf(body.global_scale.x), absf(body.global_scale.y))
		var body_radius: float = SPIRIT_BODY_RADIUS * body_scale
		_frame_body_radii.append(body_radius)
		_frame_max_body_radius = maxf(_frame_max_body_radius, body_radius)
		var cell := Vector2i(
			floori(_frame_centers[-1].x / BODY_CELL),
			floori(_frame_centers[-1].y / BODY_CELL))
		if _frame_body_cells.has(cell):
			var bucket: Array = _frame_body_cells[cell]
			bucket.append(_frame_bodies.size() - 1)
		else:
			_frame_body_cells[cell] = [_frame_bodies.size() - 1]

	if _geometry_cache_key != 0:
		_shared_geometry_key = _geometry_cache_key
		_shared_geometry_frame = frame
		_shared_bodies = _frame_bodies
		_shared_centers = _frame_centers
		_shared_body_radii = _frame_body_radii
		_shared_body_cells = _frame_body_cells
		_shared_max_body_radius = _frame_max_body_radius


func _tick_missile(index: int, delta: float) -> void:
	_ages[index] += delta
	_free_lefts[index] = maxf(_free_lefts[index] - delta, 0.0)
	_steer_lefts[index] -= delta
	_steer_elapsed[index] += delta
	if _steer_lefts[index] <= 0.0:
		while _steer_lefts[index] <= 0.0:
			_steer_lefts[index] += STEER_INTERVAL
		_steer(index, _steer_elapsed[index])
		_steer_elapsed[index] = 0.0
	_apply_profile_bend(index, delta)

	var from: Vector2 = _positions[index]
	var destination: Vector2 = from + _headings[index] * speed * delta
	var target = _targets[index]
	_sweep(index, from, destination)
	if _dead[index]:
		return
	_positions[index] = destination
	# Hitting a spirit in front that is not the target still chases the
	# original. Only hitting the target itself looks for the next spirit.
	if target != null and is_instance_valid(target) and _hits[index].has(target):
		_targets[index] = null
		_seek_lefts[index] = _lane_delays[index]
		if _seek_lefts[index] <= 0.0:
			_reacquire(index)

	_life_lefts[index] -= delta
	if _life_lefts[index] <= 0.0:
		_burst(index)


func _apply_profile_bend(index: int, delta: float) -> void:
	# The aimed meteor locks straight power for the first 0.16s only. After
	# that it uses the same per-hero orbit and homing as the other shots, so
	# visual personality stays.
	if _anchors[index] and _free_lefts[index] > 0.0:
		return
	var age: float = _ages[index]
	var lane: float = _lanes[index]
	var side: float = -1.0 if lane < 0.0 else 1.0
	match attack_profile:
		Hero.AttackProfile.DANCER:
			_headings[index] = _headings[index].rotated(
				sin(age * 10.0 + lane * TAU) * 0.85 * delta)
		Hero.AttackProfile.KEEPER:
			# The lantern core does not wobble; it slowly holds the target.
			# Combined with `_steer`'s low turn rate it feels heavy, but hit
			# and damage are the same.
			pass
		Hero.AttackProfile.KNIGHT:
			if _free_lefts[index] > 0.0:
				_headings[index] = _headings[index].rotated(lane * 0.28 * delta)
		Hero.AttackProfile.ECLIPSE:
			if _free_lefts[index] > 0.0:
				_headings[index] = _headings[index].rotated(side * 1.05 * delta)
		Hero.AttackProfile.SAGE:
			var step: float = -1.0 if int(age / 0.14) % 2 == 0 else 1.0
			_headings[index] = _headings[index].rotated(step * side * 0.42 * delta)
		_:
			if _free_lefts[index] > 0.0:
				_headings[index] = _headings[index].rotated(side * 0.38 * delta)


## Compare this 30Hz travel segment to every spirit's real body circle.
##
## Homing-target-only would pass through a spirit in front, and dropping
## travel to 15Hz misses a charging spirit that crosses between two physics
## ticks. One node owns the volley, but travel and collision stay on the
## project's physics period.
func _sweep(index: int, from: Vector2, destination: Vector2) -> void:
	var low_x: float = minf(from.x, destination.x)
	var high_x: float = maxf(from.x, destination.x)
	var low_y: float = minf(from.y, destination.y)
	var high_y: float = maxf(from.y, destination.y)
	while not _dead[index]:
		var best: Node2D = null
		var best_at: Vector2 = Vector2.ZERO
		var best_t: float = INF
		var hit_list: Array = _hits[index]
		# Five volleys × eight shots used to brute-force 40×40=1,600 bodies
		# per tick. Walk only spatial cells the short moved segment can
		# touch, and inside those still solve the old circle-segment entry
		# time so first hit and pierce order are kept.
		var broad: float = MISSILE_RADIUS + _frame_max_body_radius
		var cell_left: int = floori((low_x - broad) / BODY_CELL)
		var cell_right: int = floori((high_x + broad) / BODY_CELL)
		var cell_top: int = floori((low_y - broad) / BODY_CELL)
		var cell_bottom: int = floori((high_y + broad) / BODY_CELL)
		if _work_diagnostics:
			_diagnostic_naive_checks += _frame_bodies.size()
		for cell_y in range(cell_top, cell_bottom + 1):
			for cell_x in range(cell_left, cell_right + 1):
				var cell := Vector2i(cell_x, cell_y)
				if not _frame_body_cells.has(cell):
					continue
				var bucket: Array = _frame_body_cells[cell]
				if _work_diagnostics:
					_diagnostic_broadphase_checks += bucket.size()
				for candidate_value in bucket:
					var candidate_index: int = int(candidate_value)
					var spirit: Node2D = _frame_bodies[candidate_index]
					if not is_instance_valid(spirit) or hit_list.has(spirit) \
							or not spirit.is_attackable():
						continue
					var center: Vector2 = _frame_centers[candidate_index]
					var reach: float = MISSILE_RADIUS \
						+ _frame_body_radii[candidate_index]
					if center.x < low_x - reach or center.x > high_x + reach \
							or center.y < low_y - reach \
							or center.y > high_y + reach:
						continue
					var entry_t: float = _circle_entry_t(
						from, destination, center, reach)
					if entry_t < 0.0 or entry_t >= best_t:
						continue
					best = spirit
					best_t = entry_t
					best_at = from.lerp(destination, entry_t)
		if best == null:
			return
		_positions[index] = best_at
		_strike(index, best)


## Time in 0..1 when a moving point first enters the circle. Projecting the
## circle center onto the segment would pick a target whose center is ahead
## over one whose large-circle edge was grazed first.
func _circle_entry_t(
		from: Vector2, destination: Vector2, center: Vector2, radius: float) -> float:
	var offset: Vector2 = from - center
	var radius_sq: float = radius * radius
	if offset.length_squared() <= radius_sq:
		return 0.0
	var motion: Vector2 = destination - from
	var a: float = motion.length_squared()
	if a <= 0.000001:
		return -1.0
	# A quadratic discriminant subtracting large b² and 4ac has more
	# cancellation error on a long diagonal. Decide intersection from the
	# nearest point's real distance first, then entry time from perpendicular
	# distance.
	var projection: float = -offset.dot(motion) / a
	var closest_t: float = clampf(projection, 0.0, 1.0)
	var closest_offset: Vector2 = offset + motion * closest_t
	var distance_sq_tolerance: float = 0.0000004 * maxf(radius_sq, 1.0)
	if closest_offset.length_squared() > radius_sq + distance_sq_tolerance:
		return -1.0
	var perpendicular: Vector2 = offset + motion * projection
	var half_t: float = sqrt(
		maxf(radius_sq - perpendicular.length_squared(), 0.0) / a)
	var entry_t: float = projection - half_t
	# The segment-nearest test above already confirmed intersection. Only a
	# ~0.000003 t overshoot from an endpoint tangent is clamped to the
	# segment end so a real endpoint hit is kept.
	return clampf(entry_t, 0.0, 1.0)


func _steer(index: int, delta: float) -> void:
	if _free_lefts[index] > 0.0:
		return
	var target = _targets[index]
	if target != null and is_instance_valid(target) and target.is_attackable():
		var want: Vector2 = (target.global_position - _positions[index]).normalized()
		var heading: Vector2 = _headings[index]
		var profile_turn: float = 0.76 if attack_profile == Hero.AttackProfile.KEEPER \
			else (1.08 if attack_profile == Hero.AttackProfile.SAGE else 1.0)
		var turn: float = clampf(
			heading.angle_to(want),
			-TURN_RATE * profile_turn * delta,
			TURN_RATE * profile_turn * delta)
		_headings[index] = heading.rotated(turn)
		return
	_seek_lefts[index] -= delta
	if _seek_lefts[index] <= 0.0:
		_seek_lefts[index] = REACQUIRE_GAP
		_reacquire(index)


func _reacquire(index: int) -> void:
	var best: Node2D = null
	var near_sq: float = 220.0 * 220.0
	var hit_list: Array = _hits[index]
	for body in _frame_bodies:
		if not is_instance_valid(body) or not body.is_attackable():
			continue
		if hit_list.has(body):
			continue
		var far_sq: float = _positions[index].distance_squared_to(body.global_position)
		if far_sq < near_sq:
			near_sq = far_sq
			best = body
	_targets[index] = best


func _strike(index: int, spirit: Node2D) -> void:
	if _dead[index] or spirit == null or not spirit.has_method("take_damage"):
		return
	var hit_list: Array = _hits[index]
	if hit_list.has(spirit) or not spirit.is_attackable():
		return

	hit_list.append(spirit)
	spirit.take_damage(_damages[index], _positions[index])
	_splash(index, spirit)
	# Pierce only slain enemies. Passing through a living one reads as a
	# miss on elites and guardians — the "do not pierce before they die"
	# feedback as-is. If it did not kill, it bursts there.
	if spirit.is_attackable():
		_burst(index)
		return
	# Pierce counts only direct hits. Subtracting splash too would make
	# homing vanish faster as enemies clump, weaker than before the layout
	# optimization.
	_pierces[index] -= 1
	if _pierces[index] <= 0:
		_burst(index)


func _splash(index: int, center: Node2D) -> int:
	var struck: int = 0
	var hit_list: Array = _hits[index]
	var at: Vector2 = _positions[index]
	var broad: float = BLAST + _frame_max_body_radius
	var cell_left: int = floori((at.x - broad) / BODY_CELL)
	var cell_right: int = floori((at.x + broad) / BODY_CELL)
	var cell_top: int = floori((at.y - broad) / BODY_CELL)
	var cell_bottom: int = floori((at.y + broad) / BODY_CELL)
	if _work_diagnostics:
		_diagnostic_naive_checks += _frame_bodies.size()
	for cell_y in range(cell_top, cell_bottom + 1):
		for cell_x in range(cell_left, cell_right + 1):
			var cell := Vector2i(cell_x, cell_y)
			if not _frame_body_cells.has(cell):
				continue
			var bucket: Array = _frame_body_cells[cell]
			if _work_diagnostics:
				_diagnostic_broadphase_checks += bucket.size()
			for candidate_value in bucket:
				var candidate_index: int = int(candidate_value)
				var body: Node2D = _frame_bodies[candidate_index]
				if body == center or hit_list.has(body) \
						or not is_instance_valid(body) or not body.is_attackable():
					continue
				var body_center: Vector2 = _frame_centers[candidate_index]
				var reach: float = BLAST + _frame_body_radii[candidate_index]
				if at.distance_squared_to(body_center) > reach * reach:
					continue
				hit_list.append(body)
				body.take_damage(maxi(_damages[index] / 2, 1), at)
				struck += 1
	return struck


func _burst(index: int) -> void:
	if _dead[index]:
		return
	_dead[index] = true
	_live_count -= 1
	if _work_diagnostics:
		_diagnostic_release_lanes(1)
	# Keep a per-shot blast look, but do not spawn extra nodes or Tweens.
	# This node draws the volley's flashes at once to stop a chain-kill spike.
	_flash_positions.append(_positions[index])
	_flash_lefts.append(FLASH_LIFETIME)
	set_process(true)
	queue_redraw()


func _draw() -> void:
	var capture_diagnostics: bool = OS.is_debug_build()
	if capture_diagnostics:
		_capture_draw_serial += 1
	var drawn_live_lanes: int = 0
	var drawn_head_geometry_lanes: int = 0
	var drawn_trail_geometry_lanes: int = 0
	var trail_lines: PackedVector2Array = PackedVector2Array()
	var head_lines: PackedVector2Array = PackedVector2Array()
	var halo_lines: PackedVector2Array = PackedVector2Array()
	var flash_lines: PackedVector2Array = PackedVector2Array()
	var flash_colors: PackedColorArray = PackedColorArray()
	var rank: float = float(clampi(upgrade_rank, 0, 10))
	var seed_radius: float = 3.2 + 0.18 * rank + (0.6 if awakened else 0.0)
	for i in _trails.size():
		if _dead[i]:
			continue
		if capture_diagnostics:
			drawn_live_lanes += 1
		var trail: Array = _trails[i]
		if capture_diagnostics and _debug_lane_trail_geometry(i):
			drawn_trail_geometry_lanes += 1
		if not trail.is_empty():
			for j in trail.size() - 1:
				trail_lines.append(to_local(trail[j]))
				trail_lines.append(to_local(trail[j + 1]))
		var head: Vector2 = to_local(_positions[i])
		var heading: Vector2 = _headings[i]
		var side := Vector2(-heading.y, heading.x)
		var head_first: int = head_lines.size()
		_append_profile_head(
			head_lines, halo_lines, head, heading, side, seed_radius,
			upgrade_rank >= 3 or awakened, _ages[i])
		if capture_diagnostics \
				and _debug_segments_have_geometry(head_lines, head_first):
			drawn_head_geometry_lanes += 1
	if capture_diagnostics:
		_capture_last_draw_live_lanes = drawn_live_lanes
		_capture_last_draw_head_geometry_lanes = drawn_head_geometry_lanes
		_capture_last_draw_trail_geometry_lanes = drawn_trail_geometry_lanes
	for i in _flash_positions.size():
		var grow: float = 1.0 - _flash_lefts[i] / FLASH_LIFETIME
		var fade: float = 1.0 - grow
		# Even the outermost circle stays inside the real BLAST splash radius.
		var radius: float = lerpf(4.0, BLAST, grow)
		var center: Vector2 = to_local(_flash_positions[i])
		var color := Color(1.35, 0.82, 0.30, 0.84 * fade) if awakened \
			else Color(profile_primary.r * (1.05 + 0.025 * rank),
				profile_primary.g * (1.05 + 0.025 * rank),
				profile_primary.b * (1.05 + 0.025 * rank), 0.76 * fade)
		_append_profile_flash(flash_lines, flash_colors, center, radius, color)
	if not trail_lines.is_empty():
		var trail_outer := Color(1.18, 0.70, 0.24, 0.32) if awakened \
			else Color(profile_primary.r, profile_primary.g, profile_primary.b,
				0.24 + 0.012 * rank + 0.012 * float(vfx_tier))
		var trail_core := Color(0.72, 0.94, 1.12, 0.62) if awakened \
			else Color(profile_secondary.r, profile_secondary.g, profile_secondary.b,
				0.46 + 0.012 * rank + 0.015 * float(vfx_tier))
		draw_multiline(trail_lines, trail_outer,
			3.0 + 0.18 * rank + 0.12 * float(vfx_tier)
				+ (0.8 if awakened else 0.0), false)
		draw_multiline(trail_lines, trail_core,
			1.1 + 0.07 * rank, false)
	if not head_lines.is_empty():
		var head_outer := Color(1.55, 0.94, 0.34, 0.94) if awakened \
			else _glow(profile_primary, 1.46, 0.82)
		var head_core := Color(0.92, 1.18, 1.28, 0.98) if awakened \
			else _glow(profile_secondary, 1.52, 0.94)
		draw_multiline(head_lines, head_outer, 2.4 + 0.12 * rank, false)
		draw_multiline(head_lines, head_core, 1.1 + 0.05 * rank, false)
	if not halo_lines.is_empty():
		var halo_color := Color(1.42, 0.88, 0.30, 0.54) if awakened \
			else _glow(profile_secondary, 1.34, 0.46 + 0.02 * float(vfx_tier))
		draw_multiline(halo_lines, halo_color, 1.0 + 0.04 * rank, false)
	if not flash_lines.is_empty():
		draw_multiline_colors(flash_lines, flash_colors,
			2.4 + 0.10 * rank + (0.5 if awakened else 0.0), false)


func _append_profile_head(
		head_lines: PackedVector2Array,
		halo_lines: PackedVector2Array,
		head: Vector2,
		heading: Vector2,
	side: Vector2,
	radius: float,
	show_halo: bool,
	age: float,
	) -> void:
	match attack_profile:
		Hero.AttackProfile.DANCER:
			for twin in [-1.0, 1.0]:
				var center: Vector2 = head + side * radius * 0.55 * twin
				for segment in 6:
					var a0: float = heading.angle() - 1.1 + 2.2 * float(segment) / 6.0
					var a1: float = heading.angle() - 1.1 + 2.2 * float(segment + 1) / 6.0
					head_lines.append(center + Vector2.from_angle(a0) * radius)
					head_lines.append(center + Vector2.from_angle(a1) * radius)
		Hero.AttackProfile.KEEPER:
			var top: Vector2 = head - heading * radius
			var bottom: Vector2 = head + heading * radius
			var left: Vector2 = head - side * radius * 0.82
			var right: Vector2 = head + side * radius * 0.82
			for pair in [[top, left], [left, bottom], [bottom, right], [right, top]]:
				head_lines.append(pair[0])
				head_lines.append(pair[1])
			halo_lines.append(head - side * radius * 1.35)
			halo_lines.append(head + side * radius * 1.35)
		Hero.AttackProfile.KNIGHT:
			for lane in [-1.0, 0.0, 1.0]:
				var center_angle: float = heading.angle() + lane * 0.42
				for segment in 5:
					var a0: float = center_angle - 0.48 + 0.96 * float(segment) / 5.0
					var a1: float = center_angle - 0.48 + 0.96 * float(segment + 1) / 5.0
					head_lines.append(head + Vector2.from_angle(a0) * radius * 1.15)
					head_lines.append(head + Vector2.from_angle(a1) * radius * 1.15)
			halo_lines.append(head - side * radius * 0.7)
			halo_lines.append(head + side * radius * 0.7)
		Hero.AttackProfile.ECLIPSE:
			_append_circle_lines(head_lines, head, radius * 0.82, 12)
			_append_circle_lines(halo_lines, head, radius * 1.55, 14)
		Hero.AttackProfile.SAGE:
			var stars := PackedVector2Array([
				head - heading * radius, head - side * radius * 0.8,
				head + heading * radius * 0.85, head + side * radius * 0.75,
			])
			for i in stars.size():
				head_lines.append(stars[i])
				head_lines.append(stars[(i + 1) % stars.size()])
				halo_lines.append(stars[i] - heading * 1.2)
				halo_lines.append(stars[i] + heading * 1.2)
		_:
			var front: Vector2 = head + heading * radius
			var back: Vector2 = head - heading * radius * 0.82
			var left: Vector2 = head - side * radius * 0.76
			var right: Vector2 = head + side * radius * 0.76
			for pair in [[front, left], [left, back], [back, right], [right, front]]:
				head_lines.append(pair[0])
				head_lines.append(pair[1])
			if show_halo:
				_append_circle_lines(halo_lines, head, radius * 1.55, 8)

	# Tier does not change shape; it only adds small satellites. Not in hit or damage arrays.
	for mote in vfx_tier:
		var angle: float = age * 2.0 + TAU * float(mote) \
			/ float(maxi(vfx_tier, 1))
		var at: Vector2 = head + Vector2.from_angle(angle) * radius * 1.9
		halo_lines.append(at - side * 0.7)
		halo_lines.append(at + side * 0.7)


func _append_profile_flash(
		lines: PackedVector2Array,
		colors: PackedColorArray,
		center: Vector2,
		radius: float,
		color: Color,
	) -> void:
	var segments: int = FLASH_SEGMENTS
	match attack_profile:
		Hero.AttackProfile.DANCER:
			for twin in [-1.0, 1.0]:
				_append_colored_circle(lines, colors,
					center + Vector2(twin * radius * 0.22, 0.0), radius * 0.78,
					segments / 2, color)
		Hero.AttackProfile.KEEPER:
			var diamond := PackedVector2Array([
				center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
				center + Vector2(0.0, radius), center + Vector2(-radius, 0.0),
			])
			for i in diamond.size():
				lines.append(diamond[i])
				lines.append(diamond[(i + 1) % diamond.size()])
				colors.append(color)
		Hero.AttackProfile.KNIGHT, Hero.AttackProfile.SAGE:
			var points: int = 6 if attack_profile == Hero.AttackProfile.KNIGHT else 8
			for i in points * 2:
				var from_radius: float = radius if i % 2 == 0 else radius * 0.3
				var to_radius: float = radius if (i + 1) % 2 == 0 else radius * 0.3
				lines.append(center + Vector2.from_angle(TAU * float(i) / float(points * 2))
					* from_radius)
				lines.append(center + Vector2.from_angle(
					TAU * float(i + 1) / float(points * 2)) * to_radius)
				colors.append(color)
		Hero.AttackProfile.ECLIPSE:
			_append_colored_circle(lines, colors, center, radius, segments, color)
			_append_colored_circle(lines, colors, center, radius * 0.55,
				segments / 2, color)
		_:
			_append_colored_circle(lines, colors, center, radius, segments, color)


func _append_circle_lines(
		lines: PackedVector2Array,
		center: Vector2,
		radius: float,
		segments: int,
	) -> void:
	for segment in maxi(segments, 3):
		lines.append(center + Vector2.from_angle(
			TAU * float(segment) / float(segments)) * radius)
		lines.append(center + Vector2.from_angle(
			TAU * float(segment + 1) / float(segments)) * radius)


func _append_colored_circle(
		lines: PackedVector2Array,
		colors: PackedColorArray,
		center: Vector2,
		radius: float,
		segments: int,
		color: Color,
	) -> void:
	_append_circle_lines(lines, center, radius, segments)
	for segment in maxi(segments, 3):
		colors.append(color)


func _glow(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)
