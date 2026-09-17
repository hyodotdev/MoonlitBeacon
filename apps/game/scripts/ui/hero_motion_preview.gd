extends Control

## Before purchase, show **how this hero's shot flies**.
##
## The six heroes are a sidegrade with the same damage and fire rate, so the
## only reason to pick one is "how it sits in the hand." That was unknowable
## before buying — a portrait and a blurb cannot tell a pistol-straight shot
## from one that draws a wide circle.
##
## Trajectories are **not recomputed here.** Spawn a real `moon_arrow.gd` off
## screen and ask its own `sample_motion_angle()`. Change the fire VFX and this
## preview follows automatically; the two cannot drift into "not what I bought."

const ARROW_SCRIPT: Script = preload("res://scripts/actors/moon_arrow.gd")

## How many seconds of trail to draw. Same window as the real arrow lifetime (~0.9s).
const TRACE_SECONDS: float = 0.9
## How many points to split the trail into.
const TRACE_STEPS: int = 96
## Time for the shot to go from the left of the preview to the right. Independent
## of real speed; tuned so one cycle is visible in the preview width.
const SWEEP_SECONDS: float = 1.35
## Horizontal padding left and right.
const EDGE_PAD: float = 10.0
## `moon_arrow` on-screen wobble is ±11px. The preview is short vertically, so
## that span is fitted inside the stage.
const LATERAL_SPAN: float = 11.0

var _arrow: Node2D = null
var _hero: Hero = null
var _age: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _exit_tree() -> void:
	_release_arrow()


## Which hero's trail to show. `null` stops and clears.
func show_hero(hero: Hero) -> void:
	_hero = hero
	_release_arrow()
	if hero == null:
		set_process(false)
		queue_redraw()
		return
	# Do not put it in the tree. Borrow only the trajectory math, no physics or collision.
	_arrow = ARROW_SCRIPT.new() as Node2D
	_arrow.configure_profile(
		hero.attack_profile,
		hero.projectile_primary,
		hero.projectile_secondary,
		hero.vfx_tier)
	_age = 0.0
	set_process(true)
	queue_redraw()


func stop() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_age = fmod(_age + delta, SWEEP_SECONDS)
	queue_redraw()


## Point on the trail at `age`.
func _point_at(age: float) -> Vector2:
	var span: float = maxf(size.x - EDGE_PAD * 2.0, 1.0)
	var travel: float = clampf(age / TRACE_SECONDS, 0.0, 1.0)
	var lateral: float = 0.0
	if _arrow != null:
		# Same function as the real shot. The 14x scale from angle to screen offset is the same too.
		lateral = clampf(
			float(_arrow.sample_motion_angle(age)) * 14.0,
			-LATERAL_SPAN, LATERAL_SPAN)
	return Vector2(
		EDGE_PAD + span * travel,
		size.y * 0.5 + lateral * (size.y * 0.5 - 6.0) / LATERAL_SPAN)


func _draw() -> void:
	if _hero == null or _arrow == null:
		return
	var primary: Color = _hero.projectile_primary
	var secondary: Color = _hero.projectile_secondary

	# Mark the fire point so "it leaves from the left" is read first.
	draw_circle(Vector2(EDGE_PAD, size.y * 0.5), 2.4,
		Color(secondary.r, secondary.g, secondary.b, 0.55))

	# Lay the whole path faint, then overdraw near the head darker.
	var path: PackedVector2Array = PackedVector2Array()
	for i in TRACE_STEPS + 1:
		path.append(_point_at(TRACE_SECONDS * float(i) / float(TRACE_STEPS)))
	draw_polyline(path, Color(primary.r, primary.g, primary.b, 0.22), 1.6, false)

	# Head and a short tail. Where it is now reads as motion.
	var head_age: float = clampf(_age, 0.0, TRACE_SECONDS)
	var tail: PackedVector2Array = PackedVector2Array()
	for i in 10:
		var back: float = head_age - 0.045 * float(9 - i)
		if back < 0.0:
			continue
		tail.append(_point_at(back))
	if tail.size() >= 2:
		draw_polyline(tail, Color(primary.r, primary.g, primary.b, 0.85), 2.4, false)
	var head: Vector2 = _point_at(head_age)
	draw_circle(head, 3.6, Color(primary.r, primary.g, primary.b, 0.5))
	draw_circle(head, 2.0, secondary)


func _release_arrow() -> void:
	if _arrow != null:
		_arrow.free()
		_arrow = null
