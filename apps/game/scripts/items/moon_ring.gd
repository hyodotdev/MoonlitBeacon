class_name MoonRing
extends Node2D

## Moonlight orbs that orbit the player.
##
## **If a relic only changes a number, the screen looks the same no matter how
## strong you get.** People actually said "the attack always looks the same,
## so it feels boring." Damage going from 1 to 6 still shows one slash. Of
## course it does.
##
## Survivors solve this by **adding weapons.** A bible orbits, garlic spreads,
## lightning drops. Strength is read as **the screen getting louder**, not a
## number. These orbs are the first of that — once you have them they stay
## visible until death.
##
## Stack them and more orbs spin faster. Around four, they become a wall.

## Time before one orb can hit the same spirit again.
## Without it, contact would hit every frame and instakill.
##
## **Each orb has its own timer.** The dictionary used to live on one
## `MoonRing` node, so eight orbs still hit a spirit once per 0.45s —
## `count` made the screen flashy and DPS did not move an inch. The only relic
## pick where nothing happened.
const REHIT_DELAY: float = 0.45

const RADIUS: float = 34.0
const ORB_SIZE: float = 5.0
## Past six the circles overlap, so extras do not look like more — they only
## add distance checks and draws. `count` itself is not reduced. Arena must
## be able to turn overflow stacks into damage.
const MAX_VISIBLE_ORBS: int = 6
const EVOLVED_RADIUS: float = 42.0
const EVOLVED_ORB_SIZE: float = 6.0
const EVOLVED_SPIN: float = 1.22
## The 1px orb padding and spirit body-circle radius the old physics query used.
## Manual distance checks must use the same sum or swapping weapons would
## quietly widen range.
const PROBE_PADDING: float = 1.0
const SPIRIT_BODY_RADIUS: float = 4.0

var damage: int = 10
## How many orbit. One more per stack.
var count: int = 1:
	set(value):
		count = maxi(value, 1)
		if is_inside_tree():
			_rebuild()

## Whether ring and ripple together became Moon Dance.
##
## The orbit widens and brightens the instant this is set. If the change waited
## until the next hit, picking the evolution card would have no reward.
var evolved: bool = false:
	set(value):
		if evolved == value:
			return
		evolved = value
		if is_inside_tree():
			_rebuild()
			queue_redraw()

var _spin: float = 0.0
## Each orb has its own cooldown. See the `REHIT_DELAY` comment above.
var _cooldowns: Array[Dictionary] = []
var _candidates: Array[Node2D] = []



func _ready() -> void:
	z_index = 3
	_rebuild()


func set_candidates(candidates: Array[Node2D]) -> void:
	_candidates = candidates


## Rebuild the cooldown table when orb count changes.
##
## **Orbs are not nodes.** Used to spawn an `Area2D` per orb and call
## `get_overlapping_bodies()` every physics frame. Eight orbs meant eight
## queries, while physics kept pairing them with forty spirits. Orbs only need
## to draw; hits are asked once when they fire.
func _rebuild() -> void:
	_cooldowns.clear()
	for i in visible_count():
		_cooldowns.append({})


func visible_count() -> int:
	return mini(count, MAX_VISIBLE_ORBS)


## Stacks not drawn. Arena can compensate this many as damage.
func overflow_count() -> int:
	return maxi(count - MAX_VISIBLE_ORBS, 0)


func orbit_radius() -> float:
	return EVOLVED_RADIUS if evolved else RADIUS


func orb_size() -> float:
	return EVOLVED_ORB_SIZE if evolved else ORB_SIZE


func _physics_process(delta: float) -> void:
	# More orbs spin faster. Four is already too fast for the eye to follow.
	var shown: int = visible_count()
	var evolution_speed: float = EVOLVED_SPIN if evolved else 1.0
	_spin += delta * (1.9 + 0.22 * float(shown)) * evolution_speed
	# Skip a 30Hz physics tick and a 300px/s charging spirit tunnels between
	# two samples. This is at most 40×6 distance checks instead of a physics
	# server query, so check every tick.
	_probe_hits()
	queue_redraw()


## Sweep once around the player and hit only spirits near a real orb.
## Compare the arena's existing 40-cap list directly to skip a physics-server
## round trip and result Dictionary alloc.
func _probe_hits() -> void:
	var shown: int = visible_count()
	var radius: float = orbit_radius()
	var step: float = TAU / float(shown)
	var now: float = float(Time.get_ticks_msec()) * 0.001
	var orbs: PackedVector2Array = PackedVector2Array()
	for i in shown:
		orbs.append(global_position \
			+ Vector2.RIGHT.rotated(_spin + step * float(i)) * radius)

	for body in _candidates:
		if not is_instance_valid(body) or not body.is_attackable():
			continue
		# The spirit's old body shape sat 6px above the root.
		var center: Vector2 = body.to_global(Vector2(0, -6))
		var body_scale: float = maxf(
			absf(body.global_scale.x), absf(body.global_scale.y))
		var contact: float = orb_size() + PROBE_PADDING \
			+ SPIRIT_BODY_RADIUS * body_scale
		# Orbs live only on radius `radius`. A spirit outside that band cannot
		# touch any orb, so skip up to six fine comparisons.
		var center_distance_sq: float = global_position.distance_squared_to(center)
		var inner: float = maxf(radius - contact, 0.0)
		var outer: float = radius + contact
		if center_distance_sq < inner * inner or center_distance_sq > outer * outer:
			continue
		for i in orbs.size():
			var at: Vector2 = orbs[i]
			if at.distance_squared_to(center) <= contact * contact:
				_strike(i, body, at, now)


func _strike(orb: int, spirit: Object, at: Vector2, now: float) -> void:
	if spirit == null or not spirit.has_method("take_damage"):
		return
	if not spirit.is_attackable():
		return
	if orb >= _cooldowns.size():
		return
	var cooldown: Dictionary = _cooldowns[orb]
	var id: int = spirit.get_instance_id()
	if float(cooldown.get(id, 0.0)) > now:
		return
	cooldown[id] = now + REHIT_DELAY
	spirit.take_damage(damage, at)


## The orbs and the trail they draw.
##
## Drawn directly, no sprites. Orbs are a few circles, and **the trail must
## remain or "orbiting" does not read** — dots alone look like blinking.
func _draw() -> void:
	var shown: int = visible_count()
	var radius: float = orbit_radius()
	var size: float = orb_size()
	var step: float = TAU / float(shown)

	# Bundle the trail into one arc. Four circles per orb would be 32 calls at
	# eight orbs, and `draw_circle` is not batched in Compatibility so each is
	# a draw call.
	var trail: Color = Color(0.76, 0.68, 1.0, 0.26) if evolved \
		else Color(0.55, 0.75, 1.0, 0.14)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, trail, 3.2 if evolved else 2.6, false)
	if evolved:
		draw_arc(Vector2.ZERO, radius - 5.0, 0.0, TAU, 28,
			Color(0.92, 0.82, 1.0, 0.16), 1.2, false)

	var glow_lines: PackedVector2Array = PackedVector2Array()
	var body_lines: PackedVector2Array = PackedVector2Array()
	for i in shown:
		var at: Vector2 = Vector2.RIGHT.rotated(_spin + step * float(i)) * radius
		glow_lines.append(at + Vector2(-size, 0))
		glow_lines.append(at + Vector2(size, 0))
		glow_lines.append(at + Vector2(0, -size))
		glow_lines.append(at + Vector2(0, size))
		body_lines.append(at + Vector2(-size, 0))
		body_lines.append(at + Vector2(size, 0))
		body_lines.append(at + Vector2(0, -size))
		body_lines.append(at + Vector2(0, size))
	var glow: Color = Color(0.72, 0.52, 1.0, 0.28) if evolved \
		else Color(0.45, 0.70, 1.0, 0.20)
	var body: Color = Color(0.96, 0.88, 1.0, 0.98) if evolved \
		else Color(0.86, 0.94, 1.0, 0.96)
	if not glow_lines.is_empty():
		draw_multiline(glow_lines, glow, size * 1.7, false)
		draw_multiline(body_lines, body, size * 0.8, false)
