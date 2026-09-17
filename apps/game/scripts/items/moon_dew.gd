extends Area2D

## Moon dew. A heal drop at the spot a spirit scattered.
##
## A heal is one chance to get through a crisis, not emergency rations stacked
## forever across the map. Walk into body-width range to pick it up, and the
## last 5 seconds blink so the choice is now: take it or leave it.

## How many cells it fills.
const HEAL: int = 1
const LIFETIME: float = 18.0
const URGENT_AT: float = 5.0
## A little narrower than a hero cell (24). Stick only at the feet; it will not pull from across the screen.
const MAGNET_RANGE: float = 22.0
const MAGNET_SPEED: float = 118.0

## Hover height and period. Matched to the same grain as the spirit's `Hover`.
const BOB_HEIGHT: float = 3.0
const BOB_SECONDS: float = 1.6

## Distance it pops up when it drops.
const POP_DISTANCE: float = 14.0
const POP_SECONDS: float = 0.32

@onready var _sprite: Sprite2D = $Sprite

var _taken: bool = false
var _pop_tween: Tween = null
var _left: float = LIFETIME
var _beat: float = 0.0

## When close, pull toward this target. The arena assigns the player.
var target: Node2D = null


func _ready() -> void:
	z_index = 4
	add_to_group("moon_dews")
	# Mask is layer 2 (player) only, so a spirit stepping on this does nothing.
	body_entered.connect(_on_body_entered)
	_pop()
	_bob()


func _process(delta: float) -> void:
	if _taken:
		return
	_left -= delta
	_beat += delta
	if _left <= 0.0:
		_expire()
		return
	if _left <= URGENT_AT:
		modulate.a = 0.38 + 0.62 * (0.5 + 0.5 * sin(_beat * 18.0))


func _physics_process(delta: float) -> void:
	if _taken or target == null or not is_instance_valid(target):
		return
	var distance: float = global_position.distance_to(target.global_position)
	if distance > MAGNET_RANGE:
		return
	if distance <= 10.0:
		collect()
		return
	global_position = global_position.move_toward(
		target.global_position, MAGNET_SPEED * delta)


func _on_body_entered(_body: Node2D) -> void:
	collect()


## Pop up a little the instant it drops.
##
## Appear still and it sinks into the background. Motion is what the eye follows.
func _pop() -> void:
	var to: Vector2 = position + Vector2(randf_range(-8.0, 8.0), -POP_DISTANCE)
	_pop_tween = create_tween()
	_pop_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(self, "position", to, POP_SECONDS)


## Kill an in-flight drop tween when crossing a gate so it cannot rewind to the old room.
##
## Only the current Room knows structure hits, so this keeps relative position
## and a box bound; the arena then applies `nearest_clear()`.
func shift_for_transition(offset: Vector2, next_bounds: Rect2) -> void:
	if _taken:
		return
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	position += offset
	position.x = clampf(
		position.x, next_bounds.position.x + 11.0, next_bounds.end.x - 11.0)
	position.y = clampf(
		position.y, next_bounds.position.y + 11.0, next_bounds.end.y - 11.0)


## Bob in place. Makes it look alive.
func _bob() -> void:
	var bob: Tween = create_tween().set_loops()
	bob.set_trans(Tween.TRANS_SINE)
	bob.tween_property(_sprite, "position:y", -BOB_HEIGHT, BOB_SECONDS * 0.5)
	bob.tween_property(_sprite, "position:y", 0.0, BOB_SECONDS * 0.5)


## The player touched it. The arena hears and fills health.
##
## Do not change health here. The dew only announces it was eaten —
## whether full HP converts to score is the arena's call.
signal collected(amount: int, at: Vector2)
signal expired


func collect() -> void:
	# Can be touched twice in one frame. Eat twice and two cells fill.
	if _taken:
		return
	_taken = true
	set_process(false)
	set_physics_process(false)
	collected.emit(HEAL, global_position)
	# On eat, suck upward and vanish.
	set_deferred("monitoring", false)
	var gone: Tween = create_tween()
	gone.set_parallel(true)
	gone.tween_property(self, "position:y", position.y - 10.0, 0.22)
	gone.tween_property(self, "modulate:a", 0.0, 0.22)
	gone.chain().tween_callback(queue_free)


func _expire() -> void:
	if _taken:
		return
	_taken = true
	set_process(false)
	set_physics_process(false)
	set_deferred("monitoring", false)
	expired.emit()
	var out: Tween = create_tween()
	out.set_parallel(true)
	out.tween_property(self, "scale", Vector2(0.2, 0.2), 0.24)
	out.tween_property(self, "modulate:a", 0.0, 0.24)
	out.chain().tween_callback(queue_free)
