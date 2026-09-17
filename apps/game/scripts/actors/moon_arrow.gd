extends Node2D

## Moonlight arrow the player fires.
##
## Slash alone is a dull screen. Survivor fun is **several weapons firing
## themselves and visibly getting stronger** — that plane-game feeling when
## bullets go from one to three.
##
## Same bones as the enemy `moon_bolt`, but **pierce**. Upgrade and one shot
## goes through several. That is when the screen fills.

## Hits before it vanishes. 1 bursts on the first enemy.
var pierce: int = 1
var damage: int = 10
var speed: float = 210.0
## Times invested in the Starfall line. Used only for visual rank.
var upgrade_rank: int = 0
## Look while moon embers are charged. Does not touch damage, pierce, or hitbox.
var awakened: bool = false

const LIFETIME: float = 2.4
const PROFILE_TRAIL_MAX: int = 10
const HIT_RADIUS: float = 7.0
const SPIRIT_BODY_RADIUS: float = 4.0
const SPIRIT_BODY_OFFSET: Vector2 = Vector2(0, -6)
const SPIN_SPEED: float = TAU / 0.5
## One tick of a straight moon wheel moves about 3.5px. A 64px cell is small
## enough to split 24–40 spirit centers at once while usually reading only one
## or two cells.
const BODY_CELL: float = 64.0

## During awakening, even a straight moon wheel has up to five live shots.
## If each shot re-reads spirit coords and size, the same work repeats dozens
## of times per physics tick, so build it once.
static var _shared_geometry_key: int = 0
static var _shared_geometry_frame: int = -1
static var _shared_bodies: Array[Node2D] = []
static var _shared_centers: PackedVector2Array = PackedVector2Array()
static var _shared_body_radii: PackedFloat32Array = PackedFloat32Array()
static var _shared_body_cells: Dictionary = {}
static var _shared_max_body_radius: float = 0.0

@onready var _sprite: Sprite2D = $Sprite

var attack_profile: Hero.AttackProfile = Hero.AttackProfile.WARDEN
var profile_primary: Color = Color(0.3, 0.68, 1.0, 1.0)
var profile_secondary: Color = Color(0.82, 0.95, 1.0, 1.0)
var vfx_tier: int = 0
var _direction: Vector2 = Vector2.RIGHT
var _base_direction: Vector2 = Vector2.RIGHT
var _age: float = 0.0
var _lane_offset: float = 0.0
var _lane_sign: float = 1.0
var _left: float = LIFETIME
## Do not count the same enemy twice. With pierce, overlap would hit several times.
var _hit: Array = []
var _trail: Array[Vector2] = []
var _candidates: Array[Node2D] = []
var _geometry_cache_key: int = 0
var _frame_bodies: Array[Node2D] = []
var _frame_centers: PackedVector2Array = PackedVector2Array()
var _frame_body_radii: PackedFloat32Array = PackedFloat32Array()
var _frame_body_cells: Dictionary = {}
var _frame_max_body_radius: float = 0.0
var _dead: bool = false


func _ready() -> void:
	add_to_group("friendly_projectiles")


func set_candidates(candidates: Array[Node2D], shared_cache_key: int = 0) -> void:
	_candidates = candidates
	_geometry_cache_key = shared_cache_key if shared_cache_key != 0 else get_instance_id()


func configure_profile(
		profile: Hero.AttackProfile,
		primary: Color,
		secondary: Color,
		tier: int,
		lane_index: int = 0,
		lane_total: int = 1,
	) -> void:
	attack_profile = profile
	profile_primary = primary
	profile_secondary = secondary
	vfx_tier = clampi(tier, 0, 5)
	var total: int = maxi(lane_total, 1)
	_lane_offset = TAU * float(lane_index) / float(total)
	_lane_sign = -1.0 if lane_index % 2 == 1 else 1.0


## Contract tests/debug read so a profile cannot quietly widen the physics hit.
func collision_radius() -> float:
	return HIT_RADIUS


func profile_id() -> int:
	return int(attack_profile)


func motion_signature() -> StringName:
	match attack_profile:
		Hero.AttackProfile.DANCER: return &"spiral_twin_arc"
		Hero.AttackProfile.KEEPER: return &"heavy_lantern"
		Hero.AttackProfile.KNIGHT: return &"silver_fan"
		Hero.AttackProfile.ECLIPSE: return &"eclipse_orbit"
		Hero.AttackProfile.SAGE: return &"constellation_step"
		_: return &"round_boomerang"


func impact_signature() -> StringName:
	match attack_profile:
		Hero.AttackProfile.DANCER: return &"twin_arc"
		Hero.AttackProfile.KEEPER: return &"shock_ripple"
		Hero.AttackProfile.KNIGHT: return &"star_shards"
		Hero.AttackProfile.ECLIPSE: return &"ember_ring"
		Hero.AttackProfile.SAGE: return &"starburst_chain"
		_: return &"round_burst"


## Visual orbit angle, separate from the hit. Tests check that the six
## profiles look different without running a node for seconds. This does not
## change real aim.
func sample_motion_angle(age: float) -> float:
	return _profile_angle(maxf(age, 0.0))


func launch(direction: Vector2) -> void:
	_direction = direction.normalized()
	_base_direction = _direction
	_age = 0.0
	rotation = _direction.angle()
	_sprite.position = Vector2.ZERO

	# **Stronger looks thicker.** Numbers up and art the same is boring.
	# Damage is size and brightness; pierce is blue light.
	# Log scale so it does not saturate. Why: `_show_slash` in `player.gd`.
	var heat: float = clampf(log(maxf(float(damage) / float(10), 1.0)) / log(64.0), 0.0, 1.0)
	var bore: float = clampf(float(pierce - 1) / 4.0, 0.0, 1.0)
	var growth: float = float(clampi(upgrade_rank, 0, 8))
	var awakened_growth: float = 0.12 if awakened else 0.0
	_sprite.scale = Vector2.ONE * (
		0.52 + 0.075 * growth + 0.18 * heat + 0.07 * bore + awakened_growth)
	var profile_tint: Color = profile_primary.lerp(profile_secondary, 0.26)
	if awakened:
		# Gold rim and pale-cyan core tell moon-ember awakening even from far away.
		_sprite.modulate = Color(
			3.9 + 0.16 * growth + 0.8 * heat,
			3.2 + 0.12 * growth + 0.5 * heat,
			2.0 + 0.10 * growth + 0.5 * bore, 1.0)
	else:
		_sprite.modulate = Color(
			profile_tint.r * (3.1 + 0.20 * growth + 0.9 * heat),
			profile_tint.g * (3.1 + 0.15 * growth + 0.5 * heat),
			profile_tint.b * (3.1 + 0.18 * growth + 0.7 * bore), 1.0)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_cache_body_geometry()
	_age += delta
	var from: Vector2 = global_position
	_direction = _profile_heading(delta)
	var destination: Vector2 = from + _direction * speed * delta
	global_position = destination
	rotation = _direction.angle()
	var visual_lateral: float = _visual_lateral_offset(_age)
	_sprite.position = Vector2(0.0, visual_lateral)
	_sweep(from, destination)
	if _dead:
		return
	_sprite.rotation += SPIN_SPEED * delta
	if upgrade_rank > 0 or awakened or vfx_tier > 0:
		# Only the visual trail wobbles in the character's grammar. Hit center
		# always stays on the aimed segment, so a costly character cannot
		# become pay-to-lose by missing more.
		_trail.push_front(global_position + _direction.orthogonal() * visual_lateral)
		var keep: int = mini(
			2 + ceili(float(maxi(upgrade_rank, 0)) * 0.65)
				+ (1 if awakened else 0) + ceili(float(vfx_tier) * 0.55),
			PROFILE_TRAIL_MAX)
		if _trail.size() > keep:
			_trail.resize(keep)
	queue_redraw()
	_left -= delta
	if _left <= 0.0:
		queue_free()


func _profile_heading(_delta: float) -> Vector2:
	# Profile only changes look, afterglow, and hit glyph. Arena's chosen
	# aim must be kept through real travel so every hero hits at the same range.
	return _base_direction


func _visual_lateral_offset(age: float) -> float:
	# On-screen wobble alone makes profile personality. Real travel uses
	# `_profile_heading()` which keeps aim, so no hero's hit rate differs.
	#
	# At ±6px a "wide circling shot" and a "pistol-straight shot" were
	# indistinguishable. Spread to ±11px, short of looking off its own trail.
	return clampf(_profile_angle(age) * 14.0, -11.0, 11.0)


## How each hero's shot flies. The six branches must split at a glance or
## changing character has no payoff — a wide circling shot and a pistol-
## straight shot are the ends, the rest fill between.
func _profile_angle(age: float) -> float:
	match attack_profile:
		Hero.AttackProfile.DANCER:
			# Twin arcs coil. The largest left-right sway.
			return sin(age * 10.5 + _lane_offset) * 0.52 * _lane_sign
		Hero.AttackProfile.KEEPER:
			# Heavy lantern. Almost no wobble; it pushes through.
			return sin(age * 2.4 + _lane_offset) * 0.03
		Hero.AttackProfile.KNIGHT:
			# Silver crescent — a pistol-straight line. Wobble 0.
			return 0.0
		Hero.AttackProfile.ECLIPSE:
			# Eclipse ring orbit. Coils one way as it goes.
			return sin(age * 5.2 + _lane_offset) * 0.26 \
				+ age * 0.20 * _lane_sign
		Hero.AttackProfile.SAGE:
			# Angled constellation stairs. Not smooth; it kinks.
			var step: float = -1.0 if int(age / 0.16) % 2 == 0 else 1.0
			return step * 0.22 * _lane_sign
		_:
			# Moon wheel — a boomerang that draws a wide circle.
			return sin(age * 3.2 + _lane_offset) * 0.30 * _lane_sign


## Only an upgraded moon wheel leaves afterglow. One first card already
## tells it from the default shot.
##
## Afterglow sits only behind the real arrow. Two circles per sample would
## make thousands of primitives during awakening, so the same path is drawn
## twice as a thick outline and a thin core. Thickness does not change
## `HIT_RADIUS`, so VFX cannot quietly widen the hit.
func _draw() -> void:
	draw_set_transform(Vector2(0.0, _visual_lateral_offset(_age)), 0.0, Vector2.ONE)
	_draw_profile_head()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if (upgrade_rank <= 0 and not awakened and vfx_tier <= 0) or _trail.size() < 2:
		return
	var rank: float = float(clampi(upgrade_rank, 0, 8))
	var outer_color := Color(1.0, 0.7, 0.28, 0.24) if awakened \
		else Color(profile_primary.r, profile_primary.g, profile_primary.b,
			0.18 + 0.018 * float(vfx_tier))
	var core_color := Color(0.76, 0.94, 1.0, 0.42) if awakened \
		else Color(profile_secondary.r, profile_secondary.g, profile_secondary.b,
			0.34 + 0.025 * float(vfx_tier))
	var points: PackedVector2Array = PackedVector2Array()
	for at in _trail:
		points.append(to_local(at))
	var outer_width: float = 3.8 + 0.42 * rank + 0.18 * float(vfx_tier) \
		+ (1.2 if awakened else 0.0)
	draw_polyline(points, outer_color, outer_width, false)
	draw_polyline(points, core_color, maxf(1.0, outer_width * 0.36), false)


func _draw_profile_head() -> void:
	var primary: Color = _glow(profile_primary, 2.25, 0.72)
	var secondary: Color = _glow(profile_secondary, 2.0, 0.62)
	match attack_profile:
		Hero.AttackProfile.DANCER:
			draw_arc(Vector2(1.0, -1.8), 4.4, -1.2, 1.2, 9,
				primary, 1.3, false)
			draw_arc(Vector2(1.0, 1.8), 4.4, PI - 1.2, PI + 1.2, 9,
				secondary, 1.3, false)
		Hero.AttackProfile.KEEPER:
			draw_polyline(PackedVector2Array([
				Vector2(4.0, 0.0), Vector2(0.0, -3.8), Vector2(-3.2, 0.0),
				Vector2(0.0, 3.8), Vector2(4.0, 0.0),
			]), primary, 1.5, false)
			draw_arc(Vector2.ZERO, 5.5, 0.0, TAU, 14, secondary, 0.9, false)
		Hero.AttackProfile.KNIGHT:
			for lane in [-1.0, 0.0, 1.0]:
				draw_arc(Vector2.ZERO, 5.0 + absf(lane), lane * 0.34 - 0.38,
					lane * 0.34 + 0.38, 6, primary, 1.25, false)
			draw_circle(Vector2(-3.0, -2.5), 0.8, secondary)
		Hero.AttackProfile.ECLIPSE:
			draw_circle(Vector2.ZERO, 3.1,
				Color(profile_secondary.r, profile_secondary.g,
					profile_secondary.b, 0.84))
			draw_arc(Vector2.ZERO, 5.2, -0.35, TAU - 0.55, 16,
				primary, 1.8, false)
			for i in 2 + vfx_tier / 2:
				draw_circle(Vector2.from_angle(_age * 5.0 + float(i) * PI) * 7.0,
					0.6, primary)
		Hero.AttackProfile.SAGE:
			var chain := PackedVector2Array([
				Vector2(-5.0, 2.5), Vector2(-1.5, -2.8),
				Vector2(2.0, 1.6), Vector2(5.0, -2.2),
			])
			draw_polyline(chain, primary, 1.0, false)
			for at in chain:
				draw_circle(at, 0.8, secondary)
		_:
			draw_arc(Vector2.ZERO, 5.0, -0.8, PI + 0.7, 14,
				primary, 1.15, false)


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
		var center: Vector2 = body.to_global(SPIRIT_BODY_OFFSET)
		_frame_centers.append(center)
		var body_scale: float = maxf(
			absf(body.global_scale.x), absf(body.global_scale.y))
		var body_radius: float = SPIRIT_BODY_RADIUS * body_scale
		_frame_body_radii.append(body_radius)
		_frame_max_body_radius = maxf(_frame_max_body_radius, body_radius)
		var cell := Vector2i(
			floori(center.x / BODY_CELL), floori(center.y / BODY_CELL))
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


## Compare this tick's travel segment to spirit body circles directly. If a
## physics tick stalls and it moves far in one frame, the whole segment is
## still seen, so a thin spirit is not tunneled.
func _sweep(from: Vector2, destination: Vector2) -> void:
	var low_x: float = minf(from.x, destination.x)
	var high_x: float = maxf(from.x, destination.x)
	var low_y: float = minf(from.y, destination.y)
	var high_y: float = maxf(from.y, destination.y)
	# Cells store centers only. Search expands to the largest body radius so
	# a spirit whose body only clips the segment across a cell edge is not
	# missed. Real hits re-check each spirit's exact radius below, so cell
	# size does not widen the hit.
	var cell_margin: float = HIT_RADIUS + _frame_max_body_radius
	var first_cell_x: int = floori((low_x - cell_margin) / BODY_CELL)
	var last_cell_x: int = floori((high_x + cell_margin) / BODY_CELL)
	var first_cell_y: int = floori((low_y - cell_margin) / BODY_CELL)
	var last_cell_y: int = floori((high_y + cell_margin) / BODY_CELL)
	while not _dead:
		var best: Node2D = null
		var best_at: Vector2 = Vector2.ZERO
		var best_t: float = INF
		for cell_y in range(first_cell_y, last_cell_y + 1):
			for cell_x in range(first_cell_x, last_cell_x + 1):
				var bucket = _frame_body_cells.get(Vector2i(cell_x, cell_y))
				if bucket == null:
					continue
				for candidate_index: int in bucket:
					var center: Vector2 = _frame_centers[candidate_index]
					var reach: float = HIT_RADIUS + _frame_body_radii[candidate_index]
					if center.x < low_x - reach or center.x > high_x + reach \
							or center.y < low_y - reach or center.y > high_y + reach:
						continue
					# Most on-screen spirits are other cells and never reach here.
					# Filter on stored numbers first, then pay Object validity,
					# method calls, and circle-segment hits only on nearby targets.
					var spirit: Node2D = _frame_bodies[candidate_index]
					if not is_instance_valid(spirit) or _hit.has(spirit) \
							or not spirit.is_attackable():
						continue
					var entry_t: float = _circle_entry_t(from, destination, center, reach)
					if entry_t < 0.0 or entry_t >= best_t:
						continue
					best = spirit
					best_t = entry_t
					best_at = from.lerp(destination, entry_t)
		if best == null:
			return
		_strike(best, best_at)


## A piercing arrow must hit in the order it actually first touches on the
## travel segment, not candidate spawn order. Use first entry time on the
## circle edge, not the projected center.
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
	return clampf(entry_t, 0.0, 1.0)


func _strike(spirit: Node2D, at: Vector2) -> void:
	if spirit == null or not spirit.has_method("take_damage"):
		return
	if _hit.has(spirit):
		return
	if not spirit.is_attackable():
		return

	_hit.append(spirit)
	spirit.take_damage(damage, at)
	_spark(at)

	pierce -= 1
	if pierce <= 0:
		_burst()


## A small spark bursts at the hit.
##
## A hit that only shows **on the hit side** is not enough. The striker needs
## a mark too or there is no feel. Pierce bursts at every place it passes.
func _spark(at: Vector2) -> void:
	var flash: Sprite2D = Sprite2D.new()
	flash.texture = _sprite.texture
	flash.hframes = 4
	flash.frame = 0
	flash.light_mask = 0
	var flash_color: Color = profile_secondary if attack_profile \
		== Hero.AttackProfile.ECLIPSE else profile_primary.lerp(profile_secondary, 0.35)
	flash.modulate = _glow(flash_color, 3.2, 1.0)
	# At a 0.025 tier factor even the top-price hero's flash was 12% larger
	# than default, visible only side by side. "Costly characters should
	# feel chewy" means that gap must be seen at once, so spread it to 2×.
	flash.scale = Vector2.ONE * (0.42 + 0.085 * float(vfx_tier))
	flash.rotation = randf() * TAU
	flash.global_position = at
	flash.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_parent().add_child(flash)

	var glyph := Line2D.new()
	glyph.name = &"ProfileImpact"
	glyph.points = _impact_points()
	glyph.closed = true
	glyph.width = 1.4 + 0.34 * float(vfx_tier)
	glyph.default_color = _glow(profile_primary, 2.4, 0.9)
	glyph.antialiased = false
	flash.add_child(glyph)

	var pop: Tween = flash.create_tween()
	pop.set_parallel(true)
	pop.tween_property(flash, "scale", Vector2(1.1, 1.1), 0.16)
	pop.tween_property(flash, "modulate:a", 0.0, 0.16)
	pop.chain().tween_callback(flash.queue_free)


## Hero-unique mark left at the hit.
##
## Shapes were six-way from the start, but at 5–7px radius they **clumped
## into white dots on screen.** That is why "VFX should differ or there is
## no reason to buy a character" came up. Grow readable size instead of
## changing shape, and leave costly heroes a bit larger so tier also reads
## on the same mark.
func _impact_points() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var scale: float = 1.75 + 0.11 * float(vfx_tier)
	match attack_profile:
		Hero.AttackProfile.DANCER:
			# Twin arcs coiling into an 8.
			for i in 16:
				var angle: float = TAU * float(i) / 16.0
				points.append(Vector2(
					sin(angle) * 5.4 * scale, sin(angle * 2.0) * 2.8 * scale))
		Hero.AttackProfile.KEEPER:
			# Lantern diamond. One heavy layer.
			points = PackedVector2Array([
				Vector2(0.0, -6.4) * scale, Vector2(5.2, 0.0) * scale,
				Vector2(0.0, 6.4) * scale, Vector2(-5.2, 0.0) * scale,
			])
		Hero.AttackProfile.KNIGHT:
			# Crescent fan — a sharp five-point star.
			for i in 10:
				var radius: float = (6.8 if i % 2 == 0 else 2.4) * scale
				points.append(Vector2.from_angle(-PI * 0.5 + TAU * float(i) / 10.0) * radius)
		Hero.AttackProfile.ECLIPSE:
			# Eclipse ring — a packed circle.
			for i in 18:
				points.append(Vector2.from_angle(TAU * float(i) / 18.0) * 6.2 * scale)
		Hero.AttackProfile.SAGE:
			# Constellation — the sharpest six points.
			for i in 12:
				var radius: float = (7.4 if i % 2 == 0 else 1.6) * scale
				points.append(Vector2.from_angle(TAU * float(i) / 12.0) * radius)
		_:
			# Moon wheel — default circle.
			for i in 12:
				points.append(Vector2.from_angle(TAU * float(i) / 12.0) * 5.0 * scale)
	return points


func _glow(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)


func _burst() -> void:
	if _dead:
		return
	_dead = true
	set_physics_process(false)
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	var out: Tween = create_tween()
	out.set_parallel(true)
	out.tween_property(_sprite, "scale", _sprite.scale * 2.4, 0.12)
	out.tween_property(self, "modulate:a", 0.0, 0.12)
	out.chain().tween_callback(queue_free)
