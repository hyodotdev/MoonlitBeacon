extends Area2D

## Relic orb flung out on a hit. Pick it up and it comes back.
##
## **That thing from old plane games.** In Raiden a hit knocks the power-up
## off to roll around the screen, and right then you decide: risk going for
## it, or let it go. Those few seconds are the most tense in the genre.
##
## Why this: if power only goes up, late game has no tension. Invuln is boring.
## **Something to lose is a reason to dodge.** Losing it only on death is too
## harsh — it has to be lose-for-a-moment, then reclaim.
##
## Unlike `moon_dew`, **it has a lifetime.** Stay forever and you pick it up
## whenever, so missing it never lands. It blinks fast just before it vanishes
## to hurry you.

signal reclaimed(relic: Relic)
## Lifetime ran out and it is gone for good. The arena is told which relic.
signal expired(relic: Relic)

## How long it lasts. Too short is a permanent loss; too long has no tension.
## Tuned so a sprint from the far side of the screen just barely makes it.
const LIFETIME: float = 9.0
## Below this remaining time it blinks fast.
const URGENT_AT: float = 3.0

## Fling distance and time.
const FLING: float = 78.0
const FLING_TIME: float = 0.42

## Must wait this long before it can be picked up.
##
## **Without this it reclaims itself the instant it drops.** The orb (radius 12)
## spawns on the player body (radius 4), so it starts 12px overlapped, and the
## fling tween is idle-processed so **not even one tick runs** before physics
## scans overlap. Measured: at reclaim the orb had moved 0px from spawn, and
## the gap was only 3.17px of knockback.
##
## So this PR's "drop on hit → decide whether to chase" never existed for a
## single frame. Every hit showed a `reclaimed` banner.
##
## Timed close to hit invuln (`HIT_INVULNERABLE` 0.8s) so "cannot pick up
## while being knocked back" reads in the body.
const ARM_DELAY: float = 0.75

var relic: Relic = null
## Fling off the map edge and it can never be recovered. The arena supplies the play bounds.
var bounds: Rect2 = Rect2()

var _left: float = LIFETIME
var _beat: float = 0.0
var _taken: bool = false
var _arm_ready: bool = false
var _transition_paused: bool = false
var _toss: Tween = null

@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	z_index = 4
	add_to_group("power_orbs")
	collision_layer = 0
	collision_mask = 2                          # player body
	# Do not detect at all until the arm delay ends. More certain than gating
	# inside `_on_body_entered` — physics pays no overlap cost.
	monitoring = false
	body_entered.connect(_on_body_entered)
	# Pausing the tree for a relic pick also pauses the fling tween. If only
	# the timer kept running it would become reclaimable at the player's feet
	# and auto-return the instant play resumes.
	get_tree().create_timer(ARM_DELAY, false).timeout.connect(_arm)

	# Fling any direction from the hit. Straight backward often pins it in a wall.
	var away: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * FLING
	var destination: Vector2 = position + away
	if bounds.has_area():
		destination.x = clampf(destination.x, bounds.position.x + 12.0, bounds.end.x - 12.0)
		destination.y = clampf(destination.y, bounds.position.y + 12.0, bounds.end.y - 12.0)
	_toss = create_tween()
	_toss.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toss.tween_property(self, "position", destination, FLING_TIME)


## Arm delay ended. It can be picked up now.
func _arm() -> void:
	if _taken or not is_inside_tree():
		return
	_arm_ready = true
	if _transition_paused:
		return
	set_deferred("monitoring", true)


## Freeze lifetime and detection during a terrain-transition cover.
func set_transition_paused(paused: bool) -> void:
	if _taken:
		return
	_transition_paused = paused
	set_process(not paused)
	if paused:
		set_deferred("monitoring", false)
	elif _arm_ready:
		set_deferred("monitoring", true)


## Kill the fling Tween aimed at the old terrain and move to a relative spot at the new entrance.
func shift_for_transition(offset: Vector2, next_bounds: Rect2) -> void:
	if _taken:
		return
	if _toss != null and _toss.is_valid():
		_toss.kill()
	bounds = next_bounds
	position += offset
	if bounds.has_area():
		position.x = clampf(position.x, bounds.position.x + 12.0, bounds.end.x - 12.0)
		position.y = clampf(position.y, bounds.position.y + 12.0, bounds.end.y - 12.0)


func _process(delta: float) -> void:
	_beat += delta * (3.0 if _left > URGENT_AT else 11.0)
	_left -= delta
	if _left <= 0.0 and not _taken:
		_expire()
	queue_redraw()


## Time is up. The relic is gone for good.
func _expire() -> void:
	_taken = true
	set_deferred("monitoring", false)
	expired.emit(relic)
	var out: Tween = create_tween()
	out.set_parallel(true)
	out.tween_property(self, "scale", Vector2(0.2, 0.2), 0.25)
	out.tween_property(self, "modulate:a", 0.0, 0.25)
	out.chain().tween_callback(queue_free)


func _on_body_entered(_body: Node2D) -> void:
	if _taken:
		return
	_taken = true
	set_deferred("monitoring", false)
	reclaimed.emit(relic)

	var pop: Tween = create_tween()
	pop.set_parallel(true)
	pop.tween_property(self, "scale", Vector2(1.9, 1.9), 0.2)
	pop.tween_property(self, "modulate:a", 0.0, 0.2)
	pop.chain().tween_callback(queue_free)


## Orb in the relic's own color. **The color must say what dropped** so you can decide whether to chase.
func _draw() -> void:
	var tone: Color = relic.accent if relic != null else Color(1, 0.9, 0.6, 1)
	var pulse: float = 0.5 + 0.5 * sin(_beat)
	# Fade the whole orb when time is almost up. Blink alone does not say it is urgent.
	var urgency: float = 1.0 if _left > URGENT_AT else 0.45 + 0.55 * pulse

	draw_circle(Vector2.ZERO, 9.4 + 2.6 * pulse,
		Color(tone.r, tone.g, tone.b, 0.16 * urgency))
	draw_circle(Vector2.ZERO, 5.1, Color(tone.r, tone.g, tone.b, 0.92 * urgency))
	draw_circle(Vector2.ZERO, 2.2, Color(1, 1, 1, 0.95 * urgency))
	draw_arc(Vector2.ZERO, 7.7, 0.0, TAU, 24,
		Color(1, 1, 1, 0.5 * urgency), 1.0, false)
