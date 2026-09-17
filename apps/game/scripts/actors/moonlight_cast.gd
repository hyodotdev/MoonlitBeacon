class_name MoonlightCast
extends Node2D

## Short cast glow as the little guardian sends a ranged attack from the beacon
## candles in both hands.
##
## Put this in the Player parent's `_draw()` and child Sprites cover the core
## and palm embers. This node sits after Sprite in the scene so it draws over
## face and chest, and it stops both process and redraw when there is no attack.

const CAST_SECONDS: float = 0.16

var _left: float = 0.0
var _cast_direction: Vector2 = Vector2.UP
var _cast_count: int = 1
var _profile: Hero.AttackProfile = Hero.AttackProfile.WARDEN
var _primary: Color = Color(0.3, 0.68, 1.0, 1.0)
var _secondary: Color = Color(0.82, 0.95, 1.0, 1.0)
var _vfx_tier: int = 0


func _ready() -> void:
	set_process(false)


## Hero price only changes this cast glow's decoration density. Shot count and
## damage use `play()`'s `count` as-is and never feed profile/tier back into
## combat math.
func configure_profile(
		profile: Hero.AttackProfile,
		primary: Color,
		secondary: Color,
		tier: int,
	) -> void:
	_profile = profile
	_primary = primary
	_secondary = secondary
	_vfx_tier = clampi(tier, 0, 5)
	queue_redraw()


func profile_id() -> int:
	return int(_profile)


func vfx_tier() -> int:
	return _vfx_tier


func play(direction: Vector2, count: int = 1) -> void:
	var normalized: Vector2 = direction.normalized()
	if normalized.length() < 0.01:
		normalized = Vector2.UP
	_cast_direction = normalized
	_cast_count = clampi(count, 1, 8)
	_left = CAST_SECONDS
	set_process(true)
	queue_redraw()


func stop() -> void:
	_left = 0.0
	set_process(false)
	queue_redraw()


func remaining_seconds() -> float:
	return _left


func cast_direction() -> Vector2:
	return _cast_direction


func cast_count() -> int:
	return _cast_count


func _process(delta: float) -> void:
	if _left <= 0.0:
		set_process(false)
		return
	_left = maxf(_left - delta, 0.0)
	queue_redraw()
	if _left <= 0.0:
		set_process(false)


func _draw() -> void:
	if _left <= 0.0:
		return
	var fade: float = clampf(_left / CAST_SECONDS, 0.0, 1.0)
	var progress: float = 1.0 - fade
	var power: float = float(mini(_cast_count - 1, 5))
	var ring_radius: float = lerpf(3.4, 7.0 + power * 0.35, progress)
	var cast_side := Vector2(-_cast_direction.y, _cast_direction.x)
	var primary_glow: Color = _light(_primary, 2.8, 0.92 * fade)
	var secondary_glow: Color = _light(_secondary, 2.3, 0.76 * fade)

	# A round core and two inward motes make the "sending the moon with both
	# hands" motion. Draw no fixed object that could read as a barrel or grip.
	draw_circle(Vector2.ZERO, 2.2 + 0.55 * sin(progress * PI),
		primary_glow)
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 18,
		secondary_glow,
		1.2 + 0.08 * power, false)
	var palm_distance: float = lerpf(6.0 + 0.22 * power, 3.2, progress)
	for side_sign in [-1.0, 1.0]:
		var palm_light: Vector2 = cast_side * palm_distance * side_sign
		draw_circle(palm_light, 1.15,
			primary_glow)

	# As the volley grows, one extra moon mote appears in front of the ring so
	# attack growth reads even near the character. Cap is five, so dense combat
	# stays cheap.
	var mote_count: int = mini(_cast_count, 5)
	for i in mote_count:
		var spread: float = 0.0 if mote_count <= 1 \
			else lerpf(-0.72, 0.72, float(i) / float(mote_count - 1))
		var mote_direction: Vector2 = _cast_direction.rotated(spread)
		var mote_at: Vector2 = mote_direction * (ring_radius + 1.6)
		draw_circle(mote_at, 0.85 + 0.08 * power,
			secondary_glow)

	_draw_profile_motif(ring_radius, cast_side, progress, fade)


## Pure decoration so the same shot reads as six silhouettes. Every coordinate
## is independent of the real projectile's hit radius, and this node has no
## physics monitoring.
func _draw_profile_motif(
		ring_radius: float,
		cast_side: Vector2,
		progress: float,
		fade: float,
	) -> void:
	var primary: Color = _light(_primary, 2.6, 0.72 * fade)
	var secondary: Color = _light(_secondary, 2.1, 0.58 * fade)
	match _profile:
		Hero.AttackProfile.DANCER:
			var sweep: float = progress * 1.6
			draw_arc(Vector2.ZERO, ring_radius + 2.0, -1.25 + sweep, 0.55 + sweep,
				14, primary, 1.45, false)
			draw_arc(Vector2.ZERO, ring_radius + 2.0, PI - 1.25 - sweep,
				PI + 0.55 - sweep, 14, secondary, 1.45, false)
		Hero.AttackProfile.KEEPER:
			var top: Vector2 = -_cast_direction * (ring_radius + 2.0)
			var side: Vector2 = cast_side * 2.8
			var bottom: Vector2 = _cast_direction * (ring_radius + 1.0)
			draw_polyline(PackedVector2Array([top, side, bottom, -side, top]),
				primary, 1.5, false)
			draw_arc(Vector2.ZERO, ring_radius + 3.0 + 2.0 * progress,
				0.0, TAU, 20, secondary, 1.0, false)
		Hero.AttackProfile.KNIGHT:
			for lane in [-1.0, 0.0, 1.0]:
				var ray: Vector2 = _cast_direction.rotated(lane * 0.48)
				draw_arc(Vector2.ZERO, ring_radius + 2.0, ray.angle() - 0.34,
					ray.angle() + 0.34, 8, primary, 1.3, false)
			draw_circle(-_cast_direction * (ring_radius + 3.5), 1.25, secondary)
		Hero.AttackProfile.ECLIPSE:
			# A crimson rim wraps a dark core. The core keeps alpha so the empty
			# eclipse center stays visible even in a bright forest; only the rim
			# uses a self-lit color.
			draw_circle(Vector2.ZERO, ring_radius * 0.72,
				Color(_secondary.r, _secondary.g, _secondary.b, 0.72 * fade))
			draw_arc(Vector2.ZERO, ring_radius + 2.5, progress * TAU,
				progress * TAU + PI * 1.55, 20, primary, 2.0, false)
			for i in 3 + _vfx_tier / 2:
				var ember_angle: float = progress * 5.0 + TAU * float(i) \
					/ float(3 + _vfx_tier / 2)
				draw_circle(Vector2.from_angle(ember_angle) * (ring_radius + 4.0),
					0.75, primary)
		Hero.AttackProfile.SAGE:
			var stars: int = 3 + _vfx_tier
			var points: PackedVector2Array = PackedVector2Array()
			for i in stars:
				var t: float = float(i) / float(maxi(stars - 1, 1))
				var at: Vector2 = -_cast_direction * lerpf(-ring_radius, ring_radius, t) \
					+ cast_side * sin(t * TAU + progress * 2.0) * 2.4
				points.append(at)
				draw_circle(at, 0.75 + 0.12 * float(i % 2),
					primary if i % 2 == 0 else secondary)
			if points.size() >= 2:
				draw_polyline(points, secondary, 1.0, false)
		_:
			# Warden's round rewind mark. The default hero is the simplest single layer.
			draw_arc(Vector2.ZERO, ring_radius + 2.4, progress * PI,
				progress * PI + PI * 1.35, 16, primary, 1.25, false)

	# Tiny orbit dots that grow with price order. Kept apart from each profile's
	# core motif so a higher tier does not muddle the silhouette.
	for i in _vfx_tier:
		var angle: float = progress * TAU * (1.0 + 0.08 * float(i)) \
			+ TAU * float(i) / float(maxi(_vfx_tier, 1))
		draw_circle(Vector2.from_angle(angle) * (ring_radius + 5.5 + float(i % 2)),
			0.48, secondary)


func _light(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)
