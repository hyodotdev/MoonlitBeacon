class_name BeaconCompass
extends Control

## Guide that points at where to go now.
##
## The map is 1900×1180 and the screen is 808×360. **The target is usually
## off-screen, so there is no way to know where to go.** People actually asked
## twice — "after opening three beacons, where do I go," and "after lighting
## all three, where do I go."
##
## The second one matters. At first it pointed at **unlit beacons only.** Light
## all three and there was nothing to point at, so the arrow vanished, while
## the guardian had spawned off-screen. **The target is "what to do now," not
## "a beacon."**
##
## A minimap was considered, but the screen is tight. Direction and distance
## are all you need.

## What it points at. Color and grain change.
enum Mark { NONE, BEACON, EXIT, GUARDIAN }

## Radius the arrow occupies, and inset from the edge.
##
## First pass inset 18px and **glow and tail were clipped off-screen.**
## The drawing extends about 34px front and back, so leave more than that.
##
## It also once orbited 116px from center, right beside the player, and
## blocked the view. The guide must be visible, but must not cover the game.
const ARROW_REACH: float = 34.0
const EDGE_INSET: float = ARROW_REACH + 12.0
## At the top, health/weapon panel and boss name/gauge come down to 112px.
## Leave the edge intersection as-is and an upward target's arrow and text
## hide fully behind the HUD.
const TOP_HUD_SAFE_Y: float = 126.0

## Hide threshold and show threshold differ (hysteresis).
##
## Overlap the screen at all and it hides; it must leave **fully** by this
## margin before it shows again. One threshold and the arrow blinks whenever
## the target shimmers on the edge — in a guardian fight people actually said
## "I'm already in front of the boss and the arrow pops in and out." Visible
## plus an arrow is noisy.
const SHOW_MARGIN: float = 48.0

## Must stay off-screen this many seconds in a row before showing. A guardian
## charge that overshoots the edge for a half-beat then comes back would also
## be noise if the arrow popped.
const SHOW_DELAY_SECONDS: float = 0.3

## Beacons are gold, the exit teal, the guardian blood-red. Pair color with
## a short word and a mark so meaning survives color vision and a small screen.
const BEACON_COLOR: Color = Color(1.0, 0.84, 0.48, 1)
const EXIT_COLOR: Color = Color(0.38, 0.94, 1.0, 1)
const GUARDIAN_COLOR: Color = Color(1.0, 0.44, 0.42, 1)
const LABEL_FONT: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres"
)

var _mark: Mark = Mark.NONE
var _tint: Color = BEACON_COLOR
## 0–1. Farther is closer to 1. The arrow grows and pulses faster.
var _urgency: float = 0.0
var _pulse: float = 0.0
var _showing: bool = false
## Seconds the off-screen test has held. Accumulates delta the arena passes
## every frame. Game time, not wall clock, so pause and headless stay aligned.
## Negative means not waiting.
var _show_wait_seconds: float = -1.0
var _label: Label = null
var _fade_tween: Tween = null
var _fade_generation: int = 0


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.custom_minimum_size = Vector2(84, 16)
	_label.size = Vector2(84, 16)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", LABEL_FONT)
	_label.add_theme_font_size_override("font_size", 10)
	add_child(_label)


func _process(delta: float) -> void:
	if not _showing:
		return
	# Farther pulses faster. Closer settles — "we're there" reads in the body.
	_pulse += delta * lerpf(2.8, 5.6, _urgency)
	queue_redraw()


## The arena reports this every frame. safe_rect is internal coords excluding
## OS gestures and the notch, so arrow and text do not hide behind system edges.
##
## target_extent is the radius the target is drawn at. Judging origin as a
## point made a guardian "off-screen" when the origin barely left, even with
## half the body visible, so an arrow sat on the boss in front of you.
## delta is the caller's frame time. Used to measure the pre-show wait
## (SHOW_DELAY_SECONDS) in game time.
func point_to(
		mark: Mark, target: Vector2, from: Vector2, safe_rect: Rect2,
		target_extent: float = 0.0, delta: float = 0.0) -> void:
	if mark == Mark.NONE:
		_show_wait_seconds = -1.0
		_fade(false)
		return

	var offset: Vector2 = target - from
	# At the map edge the camera does not keep the player screen-center. Treat
	# world-delta as screen coords and a gate on the edge still gets an arrow
	# even when it is actually on screen.
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var target_screen: Vector2 = canvas_transform * target
	# target_extent is the guardian body's world radius; safe_rect is screen
	# coords. Convert to the same space so zooming the camera does not raise
	# the arrow while the body still overlaps. SHOW_MARGIN is already a screen
	# margin, so do not scale it.
	var target_screen_extent: float = target_extent * maxf(
		canvas_transform.x.length(), canvas_transform.y.length())
	# Any body overlap is "visible" — no arrow needed.
	if safe_rect.grow(target_screen_extent).has_point(target_screen):
		_show_wait_seconds = -1.0
		_fade(false)
		return
	if not _showing:
		# Ignore the just-left edge band (inside SHOW_MARGIN); it must stay
		# beyond that for SHOW_DELAY_SECONDS in a row before showing.
		if safe_rect.grow(target_screen_extent + SHOW_MARGIN).has_point(target_screen):
			_show_wait_seconds = -1.0
			return
		_show_wait_seconds = maxf(_show_wait_seconds, 0.0) + delta
		if _show_wait_seconds < SHOW_DELAY_SECONDS:
			return
	_show_wait_seconds = -1.0

	_mark = mark
	match mark:
		Mark.GUARDIAN:
			_tint = GUARDIAN_COLOR
			_label.text = tr("COMPASS_GUARDIAN")
		Mark.EXIT:
			_tint = EXIT_COLOR
			_label.text = tr("COMPASS_EXIT")
		_:
			_tint = BEACON_COLOR
			_label.text = tr("COMPASS_BEACON")
	_label.add_theme_color_override("font_color", _tint)
	# One screen of distance is 1. Farther than that does not grow more.
	_urgency = clampf(offset.length() / 900.0, 0.0, 1.0)

	_fade(true)
	var direction: Vector2 = offset.normalized()
	position = _edge_point(direction, safe_rect)
	rotation = direction.angle()
	# The parent arrow rotates toward the target; the text always stands upright on screen.
	_label.rotation = -rotation
	_label.position = Vector2(-42, 15).rotated(-rotation)


## Where a ray from screen center along `direction` meets the screen edge.
##
## Orbit a fixed radius and it floats near center and blocks the view.
## Pin it to the edge and **the arrow is always at the screen end, center empty.**
##
## Aspect can widen to 4:1 (`stretch aspect=expand`), so the intersection is
## with a **rectangle**, not a circle. A circle leaves leftover on the sides
## of a wide screen.
func _edge_point(direction: Vector2, safe_rect: Rect2) -> Vector2:
	var half: Vector2 = safe_rect.size * 0.5 \
		- Vector2(EDGE_INSET, EDGE_INSET)
	half.x = maxf(half.x, 1.0)
	half.y = maxf(half.y, 1.0)
	# Which hits first, horizontal or vertical. The smaller one is first.
	var tx: float = INF if absf(direction.x) < 0.0001 else half.x / absf(direction.x)
	var ty: float = INF if absf(direction.y) < 0.0001 else half.y / absf(direction.y)
	var edge: Vector2 = safe_rect.get_center() + direction * minf(tx, ty)
	# Drop it to the first empty row under the top HUD. Rotation still aims
	# at the real target, so a slight drop does not change which way to go.
	edge.y = maxf(edge.y, safe_rect.position.y + TOP_HUD_SAFE_Y)
	return edge


func _fade(on: bool) -> void:
	if on == _showing:
		return
	_showing = on
	set_process(on)
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_generation += 1
	var generation: int = _fade_generation
	if on:
		visible = true
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0 if on else 0.0, 0.2)
	_fade_tween.finished.connect(_finish_fade.bind(on, generation))


func _finish_fade(on: bool, generation: int) -> void:
	if generation != _fade_generation:
		return
	if not on:
		visible = false


## Draw it like a comet.
##
## One solid triangle **sank into a dark forest and felt stiff.**
## Tail → glow → point → spark, four layers, make a flow. Back-to-front
## motion so "that way" reads as **movement**, not arrow **shape**.
func _draw() -> void:
	var beat: float = 0.5 + 0.5 * sin(_pulse)
	var drift: float = 3.0 * beat * (0.5 + 0.5 * _urgency)

	# 1. Tail. Three dots, smaller and fainter toward the back.
	for i in 3:
		var back: float = -9.0 - 7.0 * float(i)
		var t: float = 1.0 - float(i) / 3.0
		draw_circle(Vector2(back + drift, 0.0), 1.5 + 1.5 * t,
			Color(_tint.r, _tint.g, _tint.b, 0.10 + 0.24 * t * beat))

	# 2. Glow. The guardian's red glow alone was read as a gem circle, so shrink it.
	var halo: float = 8.0 if _mark == Mark.GUARDIAN else 12.0
	draw_circle(Vector2(drift, 0.0), halo + 1.5 * beat,
		Color(_tint.r, _tint.g, _tint.b, 0.10 + 0.07 * beat))

	# 3. Point. A chevron with a hollow back so direction is obvious.
	draw_colored_polygon(_chevron(drift), Color(_tint.r, _tint.g, _tint.b, 0.96))
	if _mark == Mark.GUARDIAN:
		# Three-horn crown. Read "boss" from silhouette, not a red circle.
		var crown: PackedVector2Array = PackedVector2Array([
			Vector2(-6, -6), Vector2(-3, -13), Vector2(1, -7),
			Vector2(5, -13), Vector2(8, -5),
		])
		for i in crown.size():
			crown[i] += Vector2(drift, 0)
		draw_polyline(crown, Color(_tint.r, _tint.g, _tint.b, 0.96), 2.2)
	elif _mark == Mark.EXIT:
		# Two doorposts behind the point so it reads as a travel exit.
		draw_line(Vector2(-6 + drift, -9), Vector2(-6 + drift, 9),
			Color(_tint.r, _tint.g, _tint.b, 0.88), 2.0)
		draw_line(Vector2(1 + drift, -9), Vector2(1 + drift, 9),
			Color(_tint.r, _tint.g, _tint.b, 0.88), 2.0)

	# 4. Tip spark. Lift it toward white so the eye pins there.
	var spark: Color = Color(
		minf(_tint.r * 1.6, 1.0), minf(_tint.g * 1.6, 1.0), minf(_tint.b * 1.6, 1.0),
		0.75 + 0.25 * beat)
	draw_circle(Vector2(13.0 + drift, 0.0), 2.4 + 0.7 * beat, spark)


## Chevron with a hollow back. The tip faces +x.
func _chevron(drift: float) -> PackedVector2Array:
	var pts: Array[Vector2] = [
		Vector2(14.0, 0.0),
		Vector2(-3.0, -7.0),
		Vector2(1.0, 0.0),
		Vector2(-3.0, 7.0),
	]
	var out: PackedVector2Array = PackedVector2Array()
	for p in pts:
		out.append(p + Vector2(drift, 0.0))
	return out
