class_name TelegraphArt
extends RefCounted

## How a guardian says "this is coming": soft moonlit decals on the floor, not drawn outlines.
##
## The old marks were thin bright lines and hard-edged outlines: a red rectangle for a charge, spokes
## for a volley, an orange wedge for a fan. They were readable and they looked like a debug overlay.
## These keep every promise the old ones made (the same reach, the same width, the same safe gap, a fill
## that shows how long is left) and paint it the way the rest of the night is painted: gradients that
## fade at the edges, a warm core, a slow pulse, a few small motes. A volley is drawn from the very angles
## it fires along and each bolt as wide as it is dangerous, so the picture can show no more room than there is.
##
## Two colours carry the meaning, everywhere, for every guardian: **coral is where it will hurt, mint is
## where it will not.** The boss's own colour only tints the rim, so it says whose attack this is.
##
## Every function draws into a `CanvasItem` that is inside its own `_draw()`, in that item's local
## space, and allocates nothing but the small arrays `draw_polygon` needs.

const DANGER: Color = Color(1.0, 0.5, 0.4, 1.0)
const HOT: Color = Color(1.0, 0.88, 0.74, 1.0)
const SAFE: Color = Color(0.6, 1.0, 0.8, 1.0)
## Half the width of the path of a bolt that hurts: the bolt's own radius and the body it would meet.
const BOLT_DANGER_HALF_WIDTH: float = 13.0


## Seconds for animation. One clock for every decal so they pulse together.
static func clock() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


static func _alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))


## A lane that is solid down the middle and fades to nothing at both edges.
static func lane(
		canvas: CanvasItem, from: Vector2, to: Vector2, half_width: float,
		color: Color, alpha: float, feather: float = 0.6) -> void:
	var direction: Vector2 = (to - from).normalized()
	var side: Vector2 = Vector2(-direction.y, direction.x)
	var inner: float = half_width * (1.0 - feather)
	var clear: Color = _alpha(color, 0.0)
	var core: Color = _alpha(color, alpha)
	canvas.draw_polygon(
		PackedVector2Array([from - side * half_width, to - side * half_width,
			to - side * inner, from - side * inner]),
		PackedColorArray([clear, clear, core, core]))
	canvas.draw_polygon(
		PackedVector2Array([from - side * inner, to - side * inner,
			to + side * inner, from + side * inner]),
		PackedColorArray([core, core, core, core]))
	canvas.draw_polygon(
		PackedVector2Array([from + side * inner, to + side * inner,
			to + side * half_width, from + side * half_width]),
		PackedColorArray([core, core, clear, clear]))


## A ray that widens and fades with distance: one bolt's path, drawn as light.
static func beam(
		canvas: CanvasItem, from: Vector2, direction: Vector2, length: float,
		start_width: float, end_width: float, color: Color,
		alpha_near: float, alpha_far: float) -> void:
	var dir: Vector2 = direction.normalized()
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var to: Vector2 = from + dir * length
	var near: Color = _alpha(color, alpha_near)
	var far: Color = _alpha(color, alpha_far)
	canvas.draw_polygon(
		PackedVector2Array([from - side * start_width, to - side * end_width,
			to + side * end_width, from + side * start_width]),
		PackedColorArray([near, far, far, near]))


## A fan of light that is faint at the tip and strongest at the far edge, with a soft rim.
static func wedge(
		canvas: CanvasItem, origin: Vector2, angle: float, half_angle: float, radius: float,
		color: Color, alpha_in: float, alpha_out: float, steps: int = 12) -> void:
	var inner: Color = _alpha(color, alpha_in)
	var outer: Color = _alpha(color, alpha_out)
	var rim: Color = _alpha(color, 0.0)
	var previous: Vector2 = origin + Vector2.RIGHT.rotated(angle - half_angle) * radius
	for step in range(1, steps + 1):
		var turn: float = angle - half_angle + 2.0 * half_angle * float(step) / float(steps)
		var next: Vector2 = origin + Vector2.RIGHT.rotated(turn) * radius
		canvas.draw_polygon(PackedVector2Array([origin, previous, next]),
			PackedColorArray([inner, outer, outer]))
		# The rim: a narrow band past the edge that fades out.
		var out_previous: Vector2 = origin + (previous - origin) * 1.07
		var out_next: Vector2 = origin + (next - origin) * 1.07
		canvas.draw_polygon(PackedVector2Array([previous, next, out_next, out_previous]),
			PackedColorArray([outer, outer, rim, rim]))
		previous = next


## A ring with a glow: three arcs, wide and faint to narrow and bright.
static func glow_ring(
		canvas: CanvasItem, centre: Vector2, radius: float, color: Color, alpha: float,
		width: float = 1.4, squash: float = 1.0) -> void:
	if squash != 1.0:
		canvas.draw_set_transform(centre, 0.0, Vector2(1.0, squash))
		centre = Vector2.ZERO
	canvas.draw_arc(centre, radius, 0.0, TAU, 40, _alpha(color, alpha * 0.16), width * 4.0)
	canvas.draw_arc(centre, radius, 0.0, TAU, 40, _alpha(color, alpha * 0.4), width * 2.2)
	canvas.draw_arc(centre, radius, 0.0, TAU, 40, _alpha(color, alpha), width)
	if squash != 1.0:
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A disc that is bright in the middle and fades outward: rings stacked to look like a gradient.
static func soft_disc(
		canvas: CanvasItem, centre: Vector2, radius: float, color: Color, alpha: float,
		squash: float = 1.0) -> void:
	if squash != 1.0:
		canvas.draw_set_transform(centre, 0.0, Vector2(1.0, squash))
		centre = Vector2.ZERO
	const LAYERS: int = 6
	for layer in LAYERS:
		var t: float = float(layer + 1) / float(LAYERS)
		canvas.draw_circle(centre, radius * t, _alpha(color, alpha / float(LAYERS) * (1.0 + (1.0 - t))))
	if squash != 1.0:
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Small arrowheads that stream along a lane, so direction reads as movement and not as a shape.
static func chevrons(
		canvas: CanvasItem, from: Vector2, direction: Vector2, length: float,
		color: Color, alpha: float, size: float, spacing: float, speed: float) -> void:
	var dir: Vector2 = direction.normalized()
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var offset: float = fposmod(clock() * speed, spacing)
	var distance: float = offset
	while distance < length - size:
		var fade: float = 1.0 - distance / length
		var tip: Vector2 = from + dir * distance
		var tail: Vector2 = tip - dir * size * 1.1
		canvas.draw_polygon(
			PackedVector2Array([tip, tail + side * size * 0.9, tail - dir * size * 0.2,
				tail - side * size * 0.9]),
			PackedColorArray([_alpha(color, alpha * (0.4 + 0.6 * fade))]))
		distance += spacing


## A line of soft dots, for a single aimed shot.
static func dots(
		canvas: CanvasItem, from: Vector2, direction: Vector2, length: float,
		color: Color, alpha: float, count: int) -> void:
	var dir: Vector2 = direction.normalized()
	var drift: float = fposmod(clock() * 1.6, 1.0)
	for index in count:
		var t: float = (float(index) + drift) / float(count)
		var at: Vector2 = from + dir * length * t
		var fade: float = 1.0 - t * 0.7
		canvas.draw_circle(at, 3.4, _alpha(color, alpha * 0.3 * fade))
		canvas.draw_circle(at, 1.7, _alpha(HOT, alpha * fade))


# --- The four telegraphs a guardian uses ----------------------------------------------

## A charge: the lane it will run, filling from its feet to the end as the windup runs out.
static func charge(
		canvas: CanvasItem, origin: Vector2, direction: Vector2, length: float,
		half_width: float, ratio: float, accent: Color) -> void:
	var end: Vector2 = origin + direction * length
	var pulse: float = 0.5 + 0.5 * sin(clock() * 7.0)
	lane(canvas, origin, end, half_width * 1.25, DANGER, 0.13 + 0.17 * ratio, 0.7)
	# The fill: a brighter lane racing out to the end.
	var reach: float = length * clampf(0.12 + 0.88 * ratio, 0.0, 1.0)
	lane(canvas, origin, origin + direction * reach, half_width * 0.9, HOT, 0.16 + 0.26 * ratio, 0.85)
	chevrons(canvas, origin + direction * 16.0, direction, length - 16.0,
		HOT, 0.5 + 0.3 * ratio, half_width * 0.42, half_width * 1.9, 70.0 + 90.0 * ratio)
	# Where it will stop: a soft mark on the floor.
	soft_disc(canvas, end, half_width * 1.5, DANGER, 0.42 + 0.3 * pulse * ratio, 0.72)
	glow_ring(canvas, origin, half_width * 1.9, accent.lerp(Color.WHITE, 0.3), 0.6, 1.2, 0.8)


## A volley of bolts in every direction round the guardian, with a clear gap to stand in.
## `gap` is the half-angle, in radians, of the empty wedge that faces `base`; `arms` how many bolts.
static func nova(
		canvas: CanvasItem, origin: Vector2, base: float, spokes: Array, gap: float,
		ratio: float, accent: Color, reach: float, strength: float = 1.0, unit: float = 1.0) -> void:
	var pulse: float = 0.5 + 0.5 * sin(clock() * 6.0)
	for angle in spokes:
		beam(canvas, origin + Vector2.RIGHT.rotated(float(angle)) * 16.0,
			Vector2.RIGHT.rotated(float(angle)), reach, 2.0, BOLT_DANGER_HALF_WIDTH * unit * (0.85 + 0.15 * ratio),
			DANGER, (0.26 + 0.34 * ratio) * strength, 0.06 * strength)
	# The gap: a calm wedge, edged with two soft beams.
	wedge(canvas, origin, base, gap, reach * 0.9, SAFE, 0.05 * strength, (0.16 + 0.14 * pulse) * strength, 6)
	for sign_value in [-1.0, 1.0]:
		var edge: Vector2 = Vector2.RIGHT.rotated(base + gap * sign_value)
		beam(canvas, origin + edge * 20.0, edge, reach * 0.86, 1.2, 2.6, SAFE, 0.62 * strength, 0.06 * strength)
	if strength >= 1.0:
		glow_ring(canvas, origin, 24.0 + 8.0 * ratio, accent.lerp(Color.WHITE, 0.3), 0.75, 1.3, 0.85)


## An aimed fan: a wedge of danger that strengthens toward its far edge. `unit` (here and in `nova` and `aim`) is how
## many local units make a pixel of the world: a guardian's body is scaled, and a length that is a bolt's danger
## has to stay so many pixels of the floor.
static func fan(
		canvas: CanvasItem, origin: Vector2, base: float, half_angle: float, reach: float,
		spokes: int, ratio: float, accent: Color, strength: float = 1.0, unit: float = 1.0) -> void:
	wedge(canvas, origin, base, half_angle, reach, DANGER, (0.05 + 0.08 * ratio) * strength,
		(0.24 + 0.26 * ratio) * strength, 14)
	for index in spokes:
		var t: float = 0.0 if spokes == 1 else float(index) / float(spokes - 1)
		var angle: float = base - half_angle * 0.86 + half_angle * 1.72 * t
		beam(canvas, origin + Vector2.RIGHT.rotated(angle) * 18.0 * unit, Vector2.RIGHT.rotated(angle),
			reach * 0.94, 1.0 * unit, 3.2 * unit, HOT, (0.16 + 0.26 * ratio) * strength, 0.02 * strength)
	if strength >= 1.0:
		glow_ring(canvas, origin, 20.0 + 6.0 * ratio, accent.lerp(Color.WHITE, 0.3), 0.7, 1.2, 0.85)


## Several aimed shots at once (a caster's fan): every bullet's path as a soft band, and the dots and the mark on the
## middle one. `angles` are the directions of the paths.
static func aim_fan(
		canvas: CanvasItem, origin: Vector2, angles: Array, length: float,
		ratio: float, accent: Color, unit: float = 1.0) -> void:
	var middle: float = 0.0
	for angle in angles:
		middle += float(angle)
	middle /= float(maxi(angles.size(), 1))
	for angle in angles:
		var direction: Vector2 = Vector2.RIGHT.rotated(float(angle))
		lane(canvas, origin + direction * 14.0, origin + direction * length, BOLT_DANGER_HALF_WIDTH * 0.75 * unit,
			DANGER, 0.1 + 0.18 * ratio, 0.75)
	aim(canvas, origin, Vector2.RIGHT.rotated(middle), length, ratio, accent, unit)


## A single aimed shot: a string of soft dots ending in a small mark where it is going.
static func aim(
		canvas: CanvasItem, origin: Vector2, direction: Vector2, length: float,
		ratio: float, accent: Color, unit: float = 1.0) -> void:
	var tint: Color = accent.lerp(DANGER, 0.5)
	# The path of the bolt as a soft band, as wide as the bolt is dangerous, with the dots streaming down it.
	lane(canvas, origin + direction * 14.0, origin + direction * length, BOLT_DANGER_HALF_WIDTH * 0.75 * unit,
		DANGER, 0.12 + 0.2 * ratio, 0.75)
	dots(canvas, origin + direction * 14.0, direction, length - 14.0, tint, 0.65 + 0.35 * ratio,
		maxi(6, roundi(length / 20.0)))
	soft_disc(canvas, origin + direction * length, 6.0 + 3.0 * ratio, tint, 0.35 + 0.35 * ratio, 0.8)
	glow_ring(canvas, origin + direction * length, 6.0 + 3.0 * ratio, tint, 0.7 + 0.3 * ratio,
		1.1, 0.8)
