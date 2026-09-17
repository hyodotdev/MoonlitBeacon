class_name MoonRipple
extends Node2D

## Moonlight ripple that spreads from the player on a beat.
##
## If [MoonRing] is a **stuck-on** weapon, this is a **pushing** one. When
## surrounded it clears everything at once. No aim, no facing — it just bursts
## on a timer. The garlic / holy-water slot in a survivor.
##
## Having it versus not having it is **visible while standing still.**
## That is the point. Pick a relic and the screen stays the same, and the pick
## was for nothing.
##
## Stack it and it spreads wider, more often, and harder.

const BASE_RADIUS: float = 46.0
const BASE_INTERVAL: float = 2.6
const EVOLVED_RADIUS_SCALE: float = 1.18
const EVOLVED_INTERVAL_SCALE: float = 0.82

var damage: int = 10
## Stack count. Starts at 1.
var rank: int = 1
## Whether ring and ripple together became Moon Dance.
##
## A violet ring stays at the feet even while resting, and from the next
## ripple radius and interval change.
var evolved: bool = false:
	set(value):
		if evolved == value:
			return
		evolved = value
		queue_redraw()

## First ripple only fires within 0.12s so the pickup reads as a reward immediately.
var _left: float = 0.12
## Progress of the ripple currently spreading. 0–1; 1 means fully out.
var _wave: float = -1.0
var _evolved_beat: float = 0.0
var _candidates: Array[Node2D] = []


func _ready() -> void:
	z_index = 2


func set_candidates(candidates: Array[Node2D]) -> void:
	_candidates = candidates


func radius() -> float:
	# Cap the radius. Even on a 4/3 camera part of a max ripple leaves the
	# screen top and bottom, so this is a hit/draw-cost ceiling, not a fit.
	var scale_up: float = EVOLVED_RADIUS_SCALE if evolved else 1.0
	return minf(BASE_RADIUS * (1.0 + 0.22 * float(rank - 1)) * scale_up, 120.0)


func interval() -> float:
	# Stacks make it more frequent. Floor is 0.42s.
	#
	# At 1.1s, **growth stopped entirely at 7 stacks.** The only all-around
	# weapon, and after that only radius crept up. 0.42 grows through twelve
	# stacks.
	var evolution_rate: float = EVOLVED_INTERVAL_SCALE if evolved else 1.0
	return maxf(BASE_INTERVAL * pow(0.84, float(rank - 1)) * evolution_rate, 0.42)


func _physics_process(delta: float) -> void:
	if evolved:
		_evolved_beat += delta * 2.8
		queue_redraw()
	if _wave >= 0.0:
		_wave += delta * 3.4
		if _wave > 1.0:
			_wave = -1.0
		queue_redraw()

	_left -= delta
	if _left > 0.0:
		return
	_left = interval()
	_burst()


## Spread once. Hit everything it reaches.
##
## **No `Area2D`.** A 120px Area2D used to monitor all the time, but overlap
## is needed only at the burst, once every 0.4s. The rest of the time physics
## was pairing it with forty spirits.
##
## It also `await get_tree().physics_frame`. Drop the relic in that gap and
## `_recompute()` frees this node, **the coroutine aborts, and that ripple's
## damage vanishes whole.**
##
## Walk the arena's existing spirit list and there is no frame delay, no
## coroutine, no physics-server round trip.
func _burst() -> void:
	_wave = 0.0
	for body in _candidates:
		if body == null or not is_instance_valid(body) \
				or not body.has_method("take_damage"):
			continue
		if not body.is_attackable():
			continue
		var center: Vector2 = body.to_global(Vector2(0, -6))
		var body_scale: float = maxf(
			absf(body.global_scale.x), absf(body.global_scale.y))
		var reach: float = radius() + 4.0 * body_scale
		if global_position.distance_squared_to(center) > reach * reach:
			continue
		body.take_damage(damage, global_position)


## The spreading ring.
##
## Drawn in two layers — inner is packed light, outer is a thin rim. One layer
## vanishes in a dark forest; a full fill covers the screen.
func _draw() -> void:
	if _wave < 0.0:
		if evolved:
			# Moon Dance mark so the gap from evolve to the next fire does not look empty.
			var pulse: float = 0.5 + 0.5 * sin(_evolved_beat)
			draw_arc(Vector2.ZERO, 19.0 + 2.0 * pulse, 0.0, TAU, 24,
				Color(0.78, 0.64, 1.0, 0.26 + 0.12 * pulse), 2.0, false)
			draw_arc(Vector2.ZERO, 25.0 + 3.0 * pulse, 0.0, TAU, 24,
				Color(0.62, 0.82, 1.0, 0.12 + 0.06 * pulse), 1.0, false)
		return
	var reach: float = radius() * _wave
	var fade: float = 1.0 - _wave

	# **Do not draw a filled circle.** Max radius 120 world px is 160px on a
	# 4/3 camera, so an alpha fill alone covers ~28% of 808×360. Two rings
	# already read as "spreading," and no fill keeps the view clear.
	var outer: Color = Color(0.92, 0.78, 1.0, 0.94 * fade) if evolved \
		else Color(0.86, 0.94, 1.0, 0.9 * fade)
	draw_arc(Vector2.ZERO, reach, 0.0, TAU, 32, outer,
		3.8 if evolved else 3.0, false)
	draw_arc(Vector2.ZERO, reach * 0.78, 0.0, TAU, 24,
		Color(1, 1, 1, 0.4 * fade), 1.4, false)
	if evolved:
		draw_arc(Vector2.ZERO, reach * 0.56, 0.0, TAU, 20,
			Color(0.58, 0.8, 1.0, 0.3 * fade), 1.2, false)
