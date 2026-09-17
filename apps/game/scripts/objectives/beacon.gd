@tool
extends Node2D

## One beacon.
##
## Unlit it is a cold pile of stone; lit, flame, sparks, and smoke rise and
## the area brightens.
##
## `@tool` so toggling `lit` in the editor is visible immediately.
## Through Chapter 3 this was a "run it to know" value; placing three beacons
## made it better to see which is lit in the editor.

## Fired when this beacon lights. Passes which beacon so the arena can count.
signal lit_changed(beacon: Node2D, is_lit: bool)

## Fired whenever charge changes (0–1). HUD listens in Chapter 10.
signal charge_changed(beacon: Node2D, ratio: float)

## Charge is full but the lighting method is not chosen yet. The arena opens
## the choice panel.
##
## Through 2.0.0, full charge was lighting. From 2.1.0 the same 1.3s fill is
## followed by a pick between stable lighting and overcharge, so `lit_changed`
## (real progress) is split from the choice request.
signal charge_completed(beacon: Node2D)

## Unlit pit color. Colder than the night-tint multiply.
const PIT_UNLIT: Color = Color(0.17, 0.19, 0.33, 1)
## Lit pit color. Same value Chapter 2 multiplied by hand with the night tint.
const PIT_LIT: Color = Color(0.258, 0.28, 0.45, 1)

## Time for the fire to catch. It does not snap on; it overshoots then settles.
const IGNITE_SECONDS: float = 0.45

## Midpoint of the flicker brightness. `Flicker` keyframe baseline.
const LIGHT_ENERGY: float = 4.64

## How far it overshoots on the catch, then comes down.
const IGNITE_OVERSHOOT: float = 1.7

## Time you must stand beside it. Too short and walking by lights it; too long is dull.
const CHARGE_SECONDS: float = 1.3

## Distance the beacon recognizes the player (screen pixels).
##
## Each beacon has a different `scale` (Chapter 3, for depth). Leave that as-is
## and **a small-drawn beacon also has a small detect range.** It was shrunk to
## look far, not to be hard to approach. Divide by `scale` to get world space.
const REACH_RADIUS: float = 34.0

## Drain speed when you leave. Faster than the fill so a brief step-out
## is not a big loss.
const DECAY_MULTIPLIER: float = 1.8

const DEFAULT_LIGHT_COLOR: Color = Color(1.0, 0.6, 0.3, 1.0)
const DEFAULT_GLOW_COLOR: Color = Color(1.0, 0.5, 0.16, 1.0)
const OVERCHARGE_LIGHT_COLOR: Color = Color(0.78, 0.55, 1.0, 1.0)
const OVERCHARGE_GLOW_COLOR: Color = Color(0.72, 0.36, 1.0, 1.0)

@export var lit: bool = true:
	set = _set_lit

## Flicker speed. Give several beacons different values and they burn on their own beats.
##
## Chapter 3 turned on `Editable Children` and poked `Flicker.speed_scale`
## directly. That ties the instance to the beacon scene's inner structure —
## rename `Flicker` later and the arena breaks quietly. Exporting it here
## pays that debt.
@export_range(0.5, 2.0, 0.01) var flicker_speed: float = 1.0:
	set = _set_flicker_speed

@onready var _pit: Sprite2D = $Pit
@onready var _light: PointLight2D = $Light
@onready var _glow: Sprite2D = $Glow
@onready var _flicker: AnimationPlayer = $Flicker
@onready var _emitters: Array[GPUParticles2D] = [$Smoke, $Embers, $Flame]
@onready var _reach: Area2D = $Reach
@onready var _sfx: AudioStreamPlayer2D = $Sfx


## Bodies currently standing beside it. Greater than 0 and it fills.
var _visitors: int = 0
## 0 ~ 1.
var _charge: float = 0.0
var _iap_store: Node
var _awaiting_choice: bool = false
var _overcharging: bool = false


func _ready() -> void:
	# Inspector values arrive before `@onready` is filled. Apply once more here.
	_set_lit(lit)
	_set_flicker_speed(flicker_speed)

	if Engine.is_editor_hint():
		return
	_iap_store = get_node_or_null("/root/IapStore")
	if _iap_store != null:
		_iap_store.lantern_changed.connect(_on_lantern_changed)
		_apply_lantern_palette()
	_normalize_reach()
	_reach.body_entered.connect(_on_body_entered)
	_reach.body_exited.connect(_on_body_exited)
	set_process(false)                           # nobody here, nothing to count


func _on_lantern_changed(_palette_id: String) -> void:
	_apply_lantern_palette()


## Cosmetics never touch detect range, charge time, or brightness. Only light
## and flame color change, fully split from rank and combat power.
func _apply_lantern_palette() -> void:
	if _overcharging:
		_apply_overcharge_palette()
		return
	var light_color: Color = DEFAULT_LIGHT_COLOR
	var glow_color: Color = DEFAULT_GLOW_COLOR
	if _iap_store != null:
		light_color = _iap_store.lantern_light_color()
		glow_color = _iap_store.lantern_glow_color()
	_light.color = light_color
	_glow.modulate = glow_color
	# Smoke stays gray on any flame. Only sparks and fire take color.
	_emitters[1].modulate = glow_color
	_emitters[2].modulate = light_color


## While defense continues after the choice, force violet regardless of cosmetic
## color. After success or give-up, `_apply_lantern_palette()` restores the
## chosen color.
func _apply_overcharge_palette() -> void:
	_light.color = OVERCHARGE_LIGHT_COLOR
	_glow.modulate = OVERCHARGE_GLOW_COLOR
	_emitters[1].modulate = OVERCHARGE_GLOW_COLOR
	_emitters[2].modulate = OVERCHARGE_LIGHT_COLOR


## Not in the progress count yet, but the field must show a defense is on.
## Light only a temporary violet flame and keep the pit unlit so it is distinct
## from a real lighting.
func _show_overcharge_visual(value: bool) -> void:
	if value:
		_light.visible = true
		_glow.visible = true
		for emitter in _emitters:
			emitter.emitting = true
		_light.energy = LIGHT_ENERGY * 0.72
		_flicker.play(&"flicker")
		return
	if lit:
		return
	_light.visible = false
	_glow.visible = false
	for emitter in _emitters:
		emitter.emitting = false
	_flicker.stop()


## Draw the beacon small and the detect range must stay the same.
func _normalize_reach() -> void:
	var s: float = maxf(absf(scale.x), 0.01)
	var shape: CircleShape2D = ($Reach/ReachShape as CollisionShape2D).shape
	shape = shape.duplicate()                    # instances share the resource
	shape.radius = REACH_RADIUS / s
	($Reach/ReachShape as CollisionShape2D).shape = shape


func _process(delta: float) -> void:
	var before: float = _charge
	if _visitors > 0:
		_charge += delta / CHARGE_SECONDS
	else:
		_charge -= delta / CHARGE_SECONDS * DECAY_MULTIPLIER
	_charge = clampf(_charge, 0.0, 1.0)

	if not is_equal_approx(before, _charge):
		charge_changed.emit(self, _charge)

	if _charge >= 1.0:
		_awaiting_choice = true
		_reach.set_deferred("monitoring", false)
		set_process(false)
		charge_completed.emit(self)
	elif _charge <= 0.0 and _visitors == 0:
		set_process(false)                       # all gone. turn on again when someone arrives


func _on_body_entered(_body: Node2D) -> void:
	_visitors += 1
	if not lit and not _awaiting_choice and not _overcharging:
		set_process(true)


func _on_body_exited(_body: Node2D) -> void:
	_visitors = maxi(_visitors - 1, 0)
	if not lit and not _awaiting_choice and not _overcharging and _charge > 0.0:
		set_process(true)


## How full it is now (0–1). Lit is 0 — no reason to show the ring.
func get_charge() -> float:
	return 0.0 if lit else _charge


func is_awaiting_choice() -> bool:
	return _awaiting_choice


func is_overcharging() -> bool:
	return _overcharging


## Overcharge was picked in the choice panel. Real time, range, and raid are
## the arena's; the beacon owns only the pre-light state and the visual cue.
func begin_overcharge() -> bool:
	if lit or not _awaiting_choice:
		return false
	_awaiting_choice = false
	_overcharging = true
	_charge = 1.0
	_visitors = 0
	set_process(false)
	_reach.set_deferred("monitoring", false)
	_apply_overcharge_palette()
	_show_overcharge_visual(true)
	return true


## Overcharge success and give-up both light the beacon itself. Success rewards are the arena's.
func resolve_overcharge() -> bool:
	if lit or not _overcharging:
		return false
	_overcharging = false
	_show_overcharge_visual(false)
	_apply_lantern_palette()
	ignite()
	return true


## Stop SFX before leaving the scene. The arena calls this.
func release_audio() -> void:
	_sfx.release()


## The run is over. It no longer fills.
##
## Chapter 9 put `_over` on the arena, but **the beacon runs on its own clock.**
## Die beside a beacon after being shoved by a spirit and it kept filling after
## the panel appeared, then lit itself a moment later. Chapter 14 started
## printing beacon count on the result screen and the mismatch
## `total 0, HUD 1/3` showed on device.
## Reset to an unlit beacon. The arena calls this when a cycle ends.
##
## `lit = false` alone is not enough. Lighting calls `set_process(false)` and
## leaves `_charge` at 1.0, so the next step-on **lights immediately with no
## charge.** Zero the charge and open detection again.
func reset() -> void:
	lit = false
	_charge = 0.0
	_visitors = 0
	_awaiting_choice = false
	_overcharging = false
	_apply_lantern_palette()
	_reach.monitoring = true
	set_process(false)                           # run again when someone enters
	charge_changed.emit(self, 0.0)


## One beacon per terrain. Other terrains' beacons are neither seen nor detected.
func set_active(value: bool) -> void:
	visible = value
	_visitors = 0
	set_process(false)
	if not Engine.is_editor_hint():
		_reach.set_deferred("monitoring", value and not lit)
	if not value and not lit and (_charge > 0.0 or _awaiting_choice or _overcharging):
		_charge = 0.0
		_awaiting_choice = false
		_overcharging = false
		_show_overcharge_visual(false)
		_apply_lantern_palette()
		charge_changed.emit(self, 0.0)


## Continue lets the run flow again. Restore only what `freeze()` turned off.
##
## Filling charge is not restored — it went to 0 at death, and continue buys
## a life, not progress.
func thaw() -> void:
	set_process(false)
	# Arena freezes all three beacons, so continue restores detection only on
	# the visible current-terrain beacon. If a hidden next-terrain Area turns
	# on, it would charge off-screen or carry partial charge into the next zone.
	_reach.monitoring = visible and not lit
	_visitors = 0


func freeze() -> void:
	set_process(false)
	_reach.monitoring = false
	_visitors = 0
	if not lit and (_charge > 0.0 or _awaiting_choice or _overcharging):
		_charge = 0.0
		_awaiting_choice = false
		_overcharging = false
		_show_overcharge_visual(false)
		_apply_lantern_palette()
		charge_changed.emit(self, 0.0)           # clear the ring at the feet too


## Light an unlit beacon. Already lit is a no-op.
##
## Setting `lit = true` snaps it on. To look like fire catching, overshoot
## then settle. Stop flicker during that, then hand it back when done.
##
## From Chapter 7 this is called **when the player stands beside it**
## (`_process` calls it when full). Chapter 4 had the arena calling them in
## order; Chapter 7 deleted that.
func ignite() -> void:
	if lit:
		return
	_awaiting_choice = false
	_overcharging = false
	_show_overcharge_visual(false)
	_reach.set_deferred("monitoring", false)
	_apply_lantern_palette()
	lit = true

	_charge = 1.0
	charge_changed.emit(self, 0.0)               # lit, so clear the ring
	_sfx.play()

	_flicker.stop()
	_light.energy = 0.0
	var flare: Tween = create_tween()
	flare.tween_property(_light, "energy", LIGHT_ENERGY * IGNITE_OVERSHOOT, IGNITE_SECONDS * 0.35)
	flare.tween_property(_light, "energy", LIGHT_ENERGY, IGNITE_SECONDS * 0.65)
	await flare.finished
	# May have left the scene during the 0.45s.
	if not is_inside_tree() or not lit:
		return
	_flicker.play(&"flicker")


func _set_lit(value: bool) -> void:
	lit = value
	if _pit == null:
		return                                   # not in the tree yet. `_ready()` applies again
	_pit.modulate = PIT_LIT if lit else PIT_UNLIT
	_light.visible = lit
	_glow.visible = lit
	for e in _emitters:
		e.emitting = lit
	if lit:
		_flicker.play(&"flicker")
	else:
		_flicker.stop()
	if not Engine.is_editor_hint():
		lit_changed.emit(self, lit)


func _set_flicker_speed(value: float) -> void:
	flicker_speed = value
	if _flicker != null:
		_flicker.speed_scale = flicker_speed
