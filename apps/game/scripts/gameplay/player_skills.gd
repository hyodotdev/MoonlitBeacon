class_name PlayerSkills
extends Node2D

## The skills of the endless stretch, and the one node that carries them all out.
##
## Nine cards unlock as cycles pass (`Relic.from_cycle`). None of them is a number on a stat: each is a
## thing that happens. They live here, apart from the arena, and share one rule: **every damage they
## deal scales with the same multiplier the player's other weapons use** (`host.skill_damage()`), so a
## skill picked late is worth as much as one picked early, and never falls behind the spirits.
##
## One node, one `_draw()`. The familiars, the ward's bubble and the comet's flight are all drawn
## here, so a run with all nine skills adds one node, not a dozen.

## The arena, by duck typing: it must offer `skill_player()`, `skill_targets()`, `skill_damage()`,
## `skill_room()`, `skill_say()` and `skill_flash()`.
var host: Node2D = null

# --- Lantern Familiar ---
const FAMILIAR_ORBIT: float = 27.0
const FAMILIAR_SPIN: float = 1.7
const FAMILIAR_INTERVAL: float = 1.5
const FAMILIAR_RANGE: float = 170.0
const FAMILIAR_DAMAGE: float = 0.9
const SPARK_SECONDS: float = 0.14
var _familiars: int = 0
var _familiar_spin: float = 0.0
var _familiar_wait: Array[float] = []
var _sparks: Array[Dictionary] = []

# --- Moon Ward ---
const WARD_RECHARGE: float = 26.0
const WARD_FASTER: float = 0.74
var _ward_stacks: int = 0
var _ward_ready: bool = false
var _ward_left: float = 0.0
var _ward_pop: float = 0.0

# --- Comet Call ---
const COMET_EVERY: float = 9.0
const COMET_FASTER: float = 1.4
const COMET_FLOOR: float = 3.5
const COMET_FUSE: float = 0.75
const COMET_RADIUS: float = 46.0
const COMET_RANGE: float = 240.0
var _comet_stacks: int = 0
var _comet_wait: float = COMET_EVERY * 0.5

# --- Star Magnet ---
const MAGNET_PER_STACK: float = 1.2
var _magnet_stacks: int = 0

# --- Thorn Bloom ---
const THORN_RADIUS: float = 58.0
const THORN_SECONDS: float = 0.3
var _thorn_stacks: int = 0
var _thorn_pop: float = 0.0
var _thorn_at: Vector2 = Vector2.ZERO

# --- Second Light ---
const SECOND_LIGHT_INVULNERABLE: float = 3.0
var _second_stacks: int = 0
var _second_ready: bool = false

# --- Moon Burst ---
const BURST_RADIUS: float = 86.0
const BURST_PER_STACK: float = 12.0
const BURST_SECONDS: float = 0.42
var _burst_stacks: int = 0
var _burst_pop: float = 0.0
var _burst_at: Vector2 = Vector2.ZERO
var _burst_reach: float = BURST_RADIUS

# --- Winter Bell ---
const BELL_EVERY: float = 13.0
const BELL_FASTER: float = 1.8
const BELL_FLOOR: float = 6.0
const BELL_RADIUS: float = 150.0
const BELL_SECONDS: float = 0.6
const BELL_SLOW: float = 0.42
const BELL_SLOW_PER_STACK: float = 0.06
const BELL_SLOW_SECONDS: float = 2.6
const BELL_SECONDS_PER_STACK: float = 0.5
var _bell_stacks: int = 0
var _bell_wait: float = BELL_EVERY * 0.6
var _bell_pop: float = 0.0
var _bell_at: Vector2 = Vector2.ZERO

# --- Comet Trail ---
const TRAIL_RADIUS: float = 27.0
const TRAIL_FUSE: float = 0.5
const TRAIL_STEP: float = 0.14
var _trail_stacks: int = 0


func _ready() -> void:
	# Above the actors, and not sorted among them: these are effects, not things standing on the floor.
	y_sort_enabled = false
	z_as_relative = false
	z_index = 20
	set_process(false)


## Count what the held relics grant. Called whenever the held list changes.
func configure(taken: Array) -> void:
	var stacks: Dictionary = {}
	for item in taken:
		if item is Relic:
			var effect: int = (item as Relic).effect
			stacks[effect] = int(stacks.get(effect, 0)) + 1
	_familiars = mini(int(stacks.get(Relic.Effect.LANTERN_FAMILIAR, 0)), 3)
	while _familiar_wait.size() < _familiars:
		_familiar_wait.append(FAMILIAR_INTERVAL * 0.5)
	while _familiar_wait.size() > _familiars:
		_familiar_wait.pop_back()
	var ward_before: int = _ward_stacks
	_ward_stacks = int(stacks.get(Relic.Effect.MOON_WARD, 0))
	if _ward_stacks > 0 and ward_before == 0:
		_ward_ready = true
	if _ward_stacks == 0:
		_ward_ready = false
	_comet_stacks = int(stacks.get(Relic.Effect.COMET_CALL, 0))
	_magnet_stacks = int(stacks.get(Relic.Effect.STAR_MAGNET, 0))
	_thorn_stacks = int(stacks.get(Relic.Effect.THORN_BLOOM, 0))
	var second_before: int = _second_stacks
	_second_stacks = int(stacks.get(Relic.Effect.SECOND_LIGHT, 0))
	if _second_stacks > 0 and second_before == 0:
		_second_ready = true
	if _second_stacks == 0:
		_second_ready = false
	_burst_stacks = int(stacks.get(Relic.Effect.MOON_BURST, 0))
	var bell_before: int = _bell_stacks
	_bell_stacks = int(stacks.get(Relic.Effect.WINTER_BELL, 0))
	if _bell_stacks > 0 and bell_before == 0:
		_bell_wait = BELL_EVERY * 0.6
	_trail_stacks = int(stacks.get(Relic.Effect.COMET_TRAIL, 0))
	PickupMagnet.scale = magnet_scale()
	set_process(has_any())
	queue_redraw()


func has_any() -> bool:
	return _familiars > 0 or _ward_stacks > 0 or _comet_stacks > 0 \
		or _thorn_stacks > 0 or _second_stacks > 0 or _burst_stacks > 0 \
		or _bell_stacks > 0 or _trail_stacks > 0


func magnet_scale() -> float:
	return 1.0 + MAGNET_PER_STACK * float(_magnet_stacks)


func familiar_count() -> int:
	return _familiars


func ward_ready() -> bool:
	return _ward_ready


func ward_recharge_seconds() -> float:
	return WARD_RECHARGE * pow(WARD_FASTER, float(maxi(_ward_stacks - 1, 0)))


func comet_interval() -> float:
	return maxf(COMET_EVERY - COMET_FASTER * float(maxi(_comet_stacks - 1, 0)), COMET_FLOOR)


func second_light_ready() -> bool:
	return _second_ready


func burst_radius() -> float:
	return BURST_RADIUS + BURST_PER_STACK * float(maxi(_burst_stacks - 1, 0))


func bell_interval() -> float:
	return maxf(BELL_EVERY - BELL_FASTER * float(maxi(_bell_stacks - 1, 0)), BELL_FLOOR)


func bell_slow() -> float:
	return minf(BELL_SLOW + BELL_SLOW_PER_STACK * float(maxi(_bell_stacks - 1, 0)), 0.72)


func bell_seconds() -> float:
	return BELL_SLOW_SECONDS + BELL_SECONDS_PER_STACK * float(maxi(_bell_stacks - 1, 0))


## A new cycle starts: the second light is lit again.
func new_cycle() -> void:
	if _second_stacks > 0:
		_second_ready = true


## Moon Ward. Called for a hit that was going to land; true means the bubble took it.
func absorb_hit() -> bool:
	if _ward_stacks <= 0 or not _ward_ready:
		return false
	_ward_ready = false
	_ward_left = ward_recharge_seconds()
	_ward_pop = 1.0
	queue_redraw()
	return true


## Second Light. Called when a hit would be the last one; returns the hearts to stand back up with
## (0 when it is not lit).
func revive() -> int:
	if _second_stacks <= 0 or not _second_ready:
		return 0
	_second_ready = false
	return _second_stacks


func invulnerable_after_revive() -> float:
	return SECOND_LIGHT_INVULNERABLE


## Thorn Bloom. A hit landed at `at`: thorns burst round the player and push back what touched them.
func on_player_hit(at: Vector2) -> void:
	if _thorn_stacks <= 0 or host == null:
		return
	_thorn_pop = 1.0
	_thorn_at = at
	var damage: int = host.call("skill_damage", 2.5 + 1.5 * float(_thorn_stacks))
	for spirit in host.call("skill_targets"):
		if is_instance_valid(spirit) and spirit.global_position.distance_to(at) <= THORN_RADIUS:
			spirit.take_damage(damage, at)
	queue_redraw()
	set_process(true)


## Moon Burst. A card was chosen: moonlight bursts round you, hurts what is near and pushes it back.
func on_card_chosen() -> void:
	if _burst_stacks <= 0 or host == null:
		return
	var player: Node2D = host.call("skill_player") as Node2D
	if player == null:
		return
	_burst_at = player.global_position
	_burst_reach = burst_radius()
	_burst_pop = 1.0
	var damage: int = host.call("skill_damage", 4.0 + 2.0 * float(_burst_stacks))
	for spirit in host.call("skill_targets"):
		if is_instance_valid(spirit) and spirit.is_attackable() \
				and spirit.global_position.distance_to(_burst_at) <= _burst_reach:
			spirit.take_damage(damage, _burst_at)
	host.call("skill_flash", Color(1.0, 0.86, 0.5, 0.2))
	queue_redraw()
	set_process(true)


## Comet Trail. A dash from `from` to `to`: marks along the way burst a moment after you have gone,
## one after another, so whatever chased you runs through them.
func on_dash(from: Vector2, to: Vector2) -> void:
	if _trail_stacks <= 0 or host == null:
		return
	var damage: int = host.call("skill_damage", 3.5 + 1.5 * float(_trail_stacks))
	var count: int = 3 + mini(_trail_stacks - 1, 2)
	for index in count:
		var at: Vector2 = from.lerp(to, (float(index) + 0.4) / float(count))
		var mark: GroundBurst = GroundBurst.mark(
			host, at, TRAIL_RADIUS, TRAIL_FUSE + TRAIL_STEP * float(index),
			Color(0.62, 0.86, 1.0, 1.0), null, _trail_lands.bind(damage), true)
		if mark == null:
			break


func _trail_lands(at: Vector2, damage: int) -> void:
	if host == null or not is_inside_tree():
		return
	for spirit in host.call("skill_targets"):
		if not is_instance_valid(spirit) or not spirit.is_attackable():
			continue
		var offset: Vector2 = spirit.global_position - at
		offset.y /= GroundBurst.SQUASH
		if offset.length() <= TRAIL_RADIUS + 4.0:
			spirit.take_damage(damage, at)


## Winter Bell: a ring of frost slows every spirit it reaches. It waits for company: a bell that tolls
## over an empty floor rings again soon instead of wasting its whole interval.
func _toll_bell(player: Node2D) -> void:
	_bell_at = player.global_position
	var hushed: int = 0
	for spirit in host.call("skill_targets"):
		if is_instance_valid(spirit) and spirit.has_method("chill") \
				and spirit.global_position.distance_to(_bell_at) <= BELL_RADIUS:
			spirit.chill(bell_slow(), bell_seconds())
			hushed += 1
	if hushed == 0:
		_bell_wait = 1.5
		return
	_bell_pop = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if host == null or not is_inside_tree() or bool(host.get("_over")):
		return
	var player: Node2D = host.call("skill_player") as Node2D
	if player == null:
		return
	if _familiars > 0:
		_tick_familiars(delta, player)
	if _ward_stacks > 0 and not _ward_ready:
		_ward_left -= delta
		if _ward_left <= 0.0:
			_ward_ready = true
	_ward_pop = maxf(_ward_pop - delta * 3.0, 0.0)
	_thorn_pop = maxf(_thorn_pop - delta / THORN_SECONDS, 0.0)
	_burst_pop = maxf(_burst_pop - delta / BURST_SECONDS, 0.0)
	_bell_pop = maxf(_bell_pop - delta / BELL_SECONDS, 0.0)
	if _bell_stacks > 0:
		_bell_wait -= delta
		if _bell_wait <= 0.0:
			_bell_wait = bell_interval()
			_toll_bell(player)
	if _comet_stacks > 0:
		_comet_wait -= delta
		if _comet_wait <= 0.0:
			_comet_wait = comet_interval()
			_call_comet(player)
	for index in range(_sparks.size() - 1, -1, -1):
		_sparks[index]["left"] = float(_sparks[index]["left"]) - delta
		if float(_sparks[index]["left"]) <= 0.0:
			_sparks.remove_at(index)
	queue_redraw()


func _familiar_position(index: int, player: Node2D) -> Vector2:
	var angle: float = _familiar_spin + TAU * float(index) / float(maxi(_familiars, 1))
	return player.global_position + Vector2(0, -8) + Vector2(cos(angle), sin(angle) * 0.7) * FAMILIAR_ORBIT


func _tick_familiars(delta: float, player: Node2D) -> void:
	_familiar_spin = fposmod(_familiar_spin + FAMILIAR_SPIN * delta, TAU)
	for index in _familiars:
		_familiar_wait[index] -= delta
		if _familiar_wait[index] > 0.0:
			continue
		var from: Vector2 = _familiar_position(index, player)
		var target: Node2D = _nearest_target(from, FAMILIAR_RANGE)
		if target == null:
			_familiar_wait[index] = 0.25
			continue
		_familiar_wait[index] = FAMILIAR_INTERVAL
		target.take_damage(host.call("skill_damage", FAMILIAR_DAMAGE), from)
		_sparks.append({"from": from, "to": target.global_position, "left": SPARK_SECONDS})


func _nearest_target(from: Vector2, reach: float) -> Node2D:
	var best: Node2D = null
	var best_distance: float = reach * reach
	for spirit in host.call("skill_targets"):
		if not is_instance_valid(spirit) or not spirit.is_attackable():
			continue
		var distance: float = spirit.global_position.distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = spirit
	return best


## Comet Call: the spirit with the most company within reach of the blast, or the nearest if none.
func _call_comet(player: Node2D) -> void:
	var best: Node2D = null
	var best_score: int = 0
	var candidates: Array = host.call("skill_targets")
	for spirit in candidates:
		if not is_instance_valid(spirit) or not spirit.is_attackable():
			continue
		if spirit.global_position.distance_to(player.global_position) > COMET_RANGE:
			continue
		var score: int = 0
		for other in candidates:
			if is_instance_valid(other) and other.is_attackable() \
					and other.global_position.distance_to(spirit.global_position) <= COMET_RADIUS:
				score += 1
		if score > best_score:
			best_score = score
			best = spirit
	if best == null:
		return
	var at: Vector2 = best.global_position
	var damage: int = host.call("skill_damage", 5.0 + 2.0 * float(_comet_stacks))
	var mark: GroundBurst = GroundBurst.mark(
		host, at, COMET_RADIUS, COMET_FUSE, Color(1.0, 0.82, 0.42, 1.0), null,
		_comet_lands.bind(damage), true)
	if mark == null:
		_comet_wait = 1.0


func _comet_lands(at: Vector2, damage: int) -> void:
	if host == null or not is_inside_tree():
		return
	for spirit in host.call("skill_targets"):
		if not is_instance_valid(spirit) or not spirit.is_attackable():
			continue
		var offset: Vector2 = spirit.global_position - at
		offset.y /= GroundBurst.SQUASH
		if offset.length() <= COMET_RADIUS + 4.0:
			spirit.take_damage(damage, at)
	host.call("skill_flash", Color(1.0, 0.86, 0.5, 0.18))


func _draw() -> void:
	if host == null or not is_inside_tree():
		return
	var player: Node2D = host.call("skill_player") as Node2D
	if player == null:
		return
	var centre: Vector2 = to_local(player.global_position + Vector2(0, -6))
	if _ward_stacks > 0:
		if _ward_ready:
			var breathe: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.004)
			draw_circle(centre, 15.0, Color(0.62, 0.86, 1.0, 0.07 + 0.05 * breathe))
			draw_arc(centre, 15.0, 0.0, TAU, 32, Color(0.72, 0.92, 1.0, 0.4 + 0.25 * breathe), 1.4)
		elif _ward_pop > 0.0:
			draw_arc(centre, 15.0 + 12.0 * (1.0 - _ward_pop), 0.0, TAU, 32,
				Color(0.8, 0.96, 1.0, _ward_pop), 2.0)
	if _thorn_pop > 0.0:
		var grown: float = THORN_RADIUS * (1.0 - _thorn_pop * 0.6)
		var thorn_centre: Vector2 = to_local(_thorn_at)
		draw_arc(thorn_centre, grown, 0.0, TAU, 40, Color(1.0, 0.5, 0.62, 0.8 * _thorn_pop), 2.0)
		for spike in 10:
			var angle: float = TAU * float(spike) / 10.0
			var inner: Vector2 = thorn_centre + Vector2.RIGHT.rotated(angle) * grown * 0.62
			var outer: Vector2 = thorn_centre + Vector2.RIGHT.rotated(angle) * grown
			draw_line(inner, outer, Color(1.0, 0.72, 0.8, 0.7 * _thorn_pop), 1.5)
	if _burst_pop > 0.0:
		var burst_centre: Vector2 = to_local(_burst_at)
		var reach: float = _burst_reach * (1.0 - _burst_pop * _burst_pop)
		draw_circle(burst_centre, reach, Color(1.0, 0.86, 0.5, 0.08 * _burst_pop))
		draw_arc(burst_centre, reach, 0.0, TAU, 44, Color(1.0, 0.9, 0.62, 0.85 * _burst_pop), 2.2)
		for spark in 12:
			var angle: float = TAU * float(spark) / 12.0
			draw_line(burst_centre + Vector2.RIGHT.rotated(angle) * reach * 0.72,
				burst_centre + Vector2.RIGHT.rotated(angle) * reach * 1.0,
				Color(1.0, 0.96, 0.78, 0.8 * _burst_pop), 1.6)
	if _bell_pop > 0.0:
		var bell_centre: Vector2 = to_local(_bell_at)
		var rolled: float = BELL_RADIUS * (1.0 - _bell_pop * _bell_pop)
		draw_circle(bell_centre, rolled, Color(0.7, 0.9, 1.0, 0.06 * _bell_pop))
		draw_arc(bell_centre, rolled, 0.0, TAU, 44, Color(0.78, 0.94, 1.0, 0.8 * _bell_pop), 2.0)
		for crystal in 8:
			var facing: float = TAU * float(crystal) / 8.0 + 0.3
			draw_line(bell_centre + Vector2.RIGHT.rotated(facing) * rolled * 0.9,
				bell_centre + Vector2.RIGHT.rotated(facing) * rolled * 1.04,
				Color(0.92, 0.98, 1.0, 0.8 * _bell_pop), 1.6)
	for index in _familiars:
		_draw_familiar(to_local(_familiar_position(index, player)), index)
	for spark in _sparks:
		var fade: float = clampf(float(spark["left"]) / SPARK_SECONDS, 0.0, 1.0)
		draw_line(to_local(spark["from"] as Vector2), to_local(spark["to"] as Vector2),
			Color(1.0, 0.86, 0.5, 0.9 * fade), 1.6)


## A small paper lantern with two eyes and a flame: cute, and easy to tell from an enemy.
func _draw_familiar(at: Vector2, index: int) -> void:
	var bob: float = sin(float(Time.get_ticks_msec()) * 0.006 + float(index) * 2.0) * 1.2
	var body: Vector2 = at + Vector2(0, bob)
	draw_circle(body, 9.0, Color(1.0, 0.72, 0.36, 0.16))
	draw_circle(body, 4.0, Color(1.0, 0.62, 0.28, 1.0))
	draw_circle(body + Vector2(0, -0.5), 2.6, Color(1.0, 0.86, 0.55, 1.0))
	draw_rect(Rect2(body + Vector2(-2.5, -4.6), Vector2(5.0, 1.2)), Color(0.42, 0.24, 0.14, 1.0))
	draw_colored_polygon(PackedVector2Array([
		body + Vector2(0, -9.2), body + Vector2(-1.7, -5.2), body + Vector2(1.7, -5.2)]),
		Color(1.0, 0.94, 0.62, 1.0))
	draw_rect(Rect2(body + Vector2(-2.2, -1.0), Vector2(1.0, 1.4)), Color(0.24, 0.14, 0.1, 1.0))
	draw_rect(Rect2(body + Vector2(1.2, -1.0), Vector2(1.0, 1.4)), Color(0.24, 0.14, 0.1, 1.0))
