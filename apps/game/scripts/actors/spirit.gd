extends Node2D

## Spirit of the night forest. Chases the player.
##
## Cannot light beacons. Not blocked in code — **because the layer differs** —
## beacon `Reach` sees layer 2 (player) only; spirits sit on layer 4.
##
## One spirit in Lesson 8; three kinds by Lesson 13.

## Fired on touching the player. Arena listens and flashes the screen.
## Passes where contact happened. Knockback goes the other way.
signal touched_player(from_position: Vector2)

## Fired on perish. Added in Lesson 17.
##
## **A spirit only announces its own death.** Score and kill count are not tallied here —
## Arena listens and decides. Lesson 18 heart drops also hear this signal.
## So it passes where it died (`at`) and whether it was elite. Without elite status
## Arena cannot keep the promise that "elites always drop a reward."
signal perished(kind: SpiritKind, at: Vector2, was_elite: bool)

## A guardian with the Summoner mutation calls a pack. Arena listens and brings the spirits in,
## so the guardian never touches the spirit cap or the tree above it.
signal calls_pack(at: Vector2, count: int)

## Which spirit. One `.tres` is one kind.
##
## Three scenes mean three places to fix. **One scene, many configs.**
@export var kind: SpiritKind = null

## After a hit, no re-hit for this long. Overlap would damage every frame otherwise.
const HIT_COOLDOWN: float = 1.1
## Position and contact stay at 30Hz; retargeting at 15Hz is enough. Velocity still
## applies between ticks so motion stays smooth, and vector/AI work for 34 spirits halves.
const AI_INTERVAL: float = 1.0 / 15.0

## Stand at least this far apart. Based on **drawn width**, not body radius (7px).
##
## Every spirit aims at one player point, so left alone they stack completely — six look
## like one blob. If you cannot read how many come from where, you cannot dodge.
const SEPARATION_RADIUS: float = 13.0
## Push strength. Must not beat chase force — if they shove each other off the player,
## pressure vanishes. Only enough to resolve overlap.
const SEPARATION_PUSH: float = 26.0
## Legacy Hitbox radius 7 plus player body radius 4. Centers are compared directly below,
## so the same 11px as the engine Area2D overlap result is used.
const CONTACT_RADIUS: float = 7.0
## Player art was scaled to 0.765, so body radius shrinks by the same ratio.
## Shrink art alone and hits land when they look like misses.
const PLAYER_BODY_RADIUS: float = 3.06
const CONTACT_OFFSET: Vector2 = Vector2(0, -6)
const PLAYER_BODY_OFFSET: Vector2 = Vector2(0, -4)

## Time to appear from the dark. Untouchable while materializing.
const MATERIALIZE_SECONDS: float = 0.9

## Names `_face()` uses every frame. Prebuilt so it does not concatenate on the spot.
const FLOAT_NAMES: Array[StringName] = [
	&"float_down", &"float_up", &"float_left", &"float_right",
]

const FACING_NAMES: Array[StringName] = [&"down", &"up", &"left", &"right"]
const GUARDIAN_WINDUP_ANIM: StringName = &"guardian_windup"
const GUARDIAN_ALT_WINDUP_ANIM: StringName = &"guardian_alt_windup"
const GUARDIAN_CHARGE_ANIM: StringName = &"guardian_charge"
const GUARDIAN_RECOVER_ANIM: StringName = &"guardian_recover"

## Fallback when kind is unset. Missing it in the inspector does not crash.
const FALLBACK_KIND: String = "res://resources/wisp.tres"

const BOLT_SCENE: PackedScene = preload("res://scenes/actors/moon_bolt.tscn")

## Hit flash duration. Short so it reads as a "flash," not "went white."
const FLASH_SECONDS: float = 0.06

## Casters lock and show aim before firing. A shot you can see and dodge is an attack.
const CASTER_WINDUP: float = 0.55
## Hostile bolt cap the screen and physics server can handle.
const HOSTILE_BOLT_LIMIT: int = 24
## What is off the screen is not shooting at you: an ordinary spirit throws its barrage only when the player is this
## near, a guardian (which is always the whole of the fight) when it is nearly across the map.
const BARRAGE_REACH: float = 250.0
const GUARDIAN_BARRAGE_REACH: float = 460.0
## Seconds between one caster starting a volley and the next one starting, wherever they stand.
const MOB_VOLLEY_GAP: float = 1.1
## A spirit that has just appeared does not throw for this long, and nor does anything for the first moments in a
## new place (`BulletField.quiet_for`): what arrives is met before it shoots.
const MOB_QUIET_SECONDS: float = 0.5
## Ordinary spirits leave room for a guardian: they stop throwing while this many bullets are in the air.
const MOB_BULLET_SOFT_LIMIT: int = 80
const PENDING_BOLT_META: StringName = &"moonlit_pending_hostile_bolts"

## Terrain guardians are not clones with only beat and numbers changed.
## Forest teaches corridor charges, field orbital barrages, camp siege fans.
const FOREST_CHASE_SECONDS: float = 1.25
const FOREST_CHARGE_WINDUP: float = 0.72
const FOREST_FOLLOWUP_WINDUP: float = 0.46
const FOREST_CHARGE_SECONDS: float = 0.40
const FOREST_BETWEEN_CHARGES: float = 0.24
const FOREST_RECOVER_SECONDS: float = 0.82
## After the charge combo lands, slam a shockwave ring. Charges punish standing
## still; the ring punishes the sidestep they taught — hold ground in the gap.
const FOREST_RING_WINDUP: float = 0.78

const FIELD_STRAFE_SECONDS: float = 2.15
const FIELD_VOLLEY_WINDUP: float = 0.78
const FIELD_RECOVER_SECONDS: float = 0.82
## Strafe used to be dead time. One aimed bolt per strafe keeps the dodge honest.
const FIELD_POKE_INTERVAL: float = 2.1
const FIELD_POKE_WINDUP: float = 0.35

const CAMP_APPROACH_SECONDS: float = 2.35
const CAMP_VOLLEY_WINDUP: float = 1.0
const CAMP_RECOVER_SECONDS: float = 1.45
## The second fan re-aims at where the player fled. One fan is a checkpoint;
## two is a question.
const CAMP_FOLLOWUP_WINDUP: float = 0.55

## The three places that came later have guardians of their own grammar, built from the same
## parts: a fan, a ring, a marked circle, a dive.
##
## However fast the night has grown, a marking stays up at least this long before what it marks lands. A person
## needs about a quarter of a second to see it and another quarter to half a second to get out of it;
## without a floor the windups of cycle 8 last a fifth of a second and cannot be answered by anyone.
const MIN_WINDUP: float = 0.45
## A circle on the floor is left on foot and the radius has to be crossed, so it stays longer still.
const MIN_MARK_FUSE: float = 0.85
## A fan is the widest thing a guardian aims and the one warning that has to be left on foot, so the
## first fan of a sequence shows itself at least this long before its first bolt goes.
const MIN_FAN_WINDUP: float = 0.75
## However many bolts a fan carries it never spreads wider than this (radians). Its width used to grow by a
## twelfth of a radian a cycle, and past cycle 6 the wedge could not be left in the time a warning gives.
const FAN_MAX_SPAN: float = 1.2
## However many spokes a ring or a cross carries, the way between two of them stays wide enough to stand in.
## These caps keep the half-angle of that way above `MIN_LANE_ANGLE` (radians): a cross of eleven arms, a
## ring of thirty-two spokes with three left out, a slow second ring of nine.
const MIN_LANE_ANGLE: float = 0.28
const MAX_CROSS_ARMS: int = 11
const MAX_RADIAL_SPOKES: int = 32
const MAX_SKEW_RING: int = 9
## Bolts fired by a guardian speed up with the night, to this multiple of the first cycle's speed and no more.
const MAX_BOLT_SCALE: float = 1.4
## One volley never carries more bolts than this, ring and second ring together: the field allows two dozen
## in the air, and a volley that asked for more would lose whichever spokes were fired last, unseen.
const MAX_VOLLEY_BOLTS: int = 22
## A whole run of fans and the repeat of its last one must fit under the same cap, or the later fans fire fewer
## bolts than the picture shows: this many feathers between them, shared out over the fans and the repeat.
const FAN_RUN_BOLTS: int = 22
## How far the picture of a fan and of a ring reaches, where the player usually stands.
const FAN_DRAW_REACH: float = 230.0
const RING_DRAW_REACH: float = 210.0
const AIM_MIN_REACH: float = 118.0
const AIM_MAX_REACH: float = 260.0
## A guardian's bolts fly this far and no farther, which is about where a fight is fought (the moon arrows reach
## 240), and the pictures of its volleys reach as far as its bolts do.
const VOLLEY_RANGE: float = 260.0

## Gale (the owl): glide in wide circles, blow a fan of feathers twice, the second re-aimed where
## you fled, then dive through where you were standing and perch.
const GALE_GLIDE_SECONDS: float = 2.2
const GALE_FAN_WINDUP: float = 0.85
const GALE_FAN_FOLLOWUP: float = 0.5
const GALE_DIVE_WINDUP: float = 0.7
const GALE_DIVE_SECONDS: float = 0.42
const GALE_RECOVER_SECONDS: float = 1.15

## Leap (the toad): waddle, then hop onto a circle marked on the floor. The third leap is a flop:
## a wider circle, a ring of bolts after it, and a long rest.
const LEAP_WADDLE_SECONDS: float = 1.5
const LEAP_BETWEEN_HOPS: float = 0.6
const LEAP_CROUCH: float = 0.78
const LEAP_AIR_SECONDS: float = 0.5
const LEAP_HOP_RADIUS: float = 34.0
const LEAP_FLOP_RADIUS: float = 52.0
const LEAP_RING_WINDUP: float = 0.62
const LEAP_RECOVER_SECONDS: float = 1.9

## Glyph (the sentinel): keep a little way off, write glowing circles round you, then a ring of
## bolts with a gap facing you, then rest. The circles are the mark: leave them before they fill.
const GLYPH_DRIFT_SECONDS: float = 2.0
const GLYPH_WRITE_SECONDS: float = 1.15
const GLYPH_RING_WINDUP: float = 0.72
const GLYPH_RECOVER_SECONDS: float = 1.7
const GLYPH_RADIUS: float = 30.0

## The three volleys a mutation can repeat or turn.
enum Volley {
	FOREST_RING,
	FIELD,
	CAMP_FAN,
}

## Echo: the volley comes again this long after the first, turned a little.
const ECHO_DELAY: float = 0.7
const ECHO_TURN: float = 0.42
## The ring and the ghost of an echo show this long before it fires: its whole beat, so the picture says where
## the repeat will go from the moment the volley it repeats has left.
const ECHO_WARN: float = 0.7
## Spiral: each volley's safe gap turns this far from the last one.
const SPIRAL_STEP: float = 0.55
## Aegis: a shield ring stands this long, then rests this long.
const AEGIS_UP: float = 2.4
const AEGIS_REST: float = 8.0
## Meteors: while it rests, a mark falls this often, up to this many a rest, each bursting after
## the fuse. The radius is the ground circle the player has to leave.
const METEOR_INTERVAL: float = 0.55
const METEORS_PER_REST: int = 4
const METEOR_FUSE: float = 1.0
const METEOR_RADIUS: float = 26.0
## Frenzy: everything the guardian does runs this much faster.
const FRENZY_HASTE: float = 1.22

enum GuardianMove {
	CHASE,
	CHARGE_WINDUP,
	CHARGE,
	RECOVER,
	VOLLEY_WINDUP,
}

enum Telegraph {
	NONE,
	AIM,
	CHARGE,
	VOLLEY,
}

## Knockback strength. Weaker than player knockback (190) — a hitch, not a shove.
const KNOCKBACK_SPEED: float = 96.0

## Time to perish.
const PERISH_SECONDS: float = 0.25

@onready var _sprite: AnimatedSprite2D = $Sprite

var _target: Node2D = null
## Current room so spirits avoid structures the same way the player does.
var _terrain_room: Room = null
var _cooldown: float = 0.0
## Spirits do not push other bodies. Instead of CharacterBody2D built-in velocity,
## the same value is held directly and used to update position.
var velocity: Vector2 = Vector2.ZERO
var _ai_left: float = 0.0
var _ai_elapsed: float = 0.0
var _last_wish: Vector2 = Vector2.DOWN

var _health: int = 0
## Guardian HP-ratio damage budget. Slow hits land in full immediately;
## only burst damage like a max volley drains across the health bar over a few seconds.
var _guardian_full_health: int = 1
var _guardian_damage_budget: float = 0.0
## Damage past the budget that already hit. Not discarded, so strong weapons do not
## feel like whiffs, and the pressure ring and health bar keep reacting.
var _guardian_deferred_damage: float = 0.0
## Action beat. Meaning differs by kind — windup time, or time until the next shot.
##
## Named `_beat` for a reason. The repo bans a certain English word under its lesson-numbering
## rule, and the check is case-insensitive so **even variable names trip it.**
## The first name used that word and `pnpm verify` spat out 10 hits.
var _beat: float = 0.0
## ORBIT spin direction. Must differ per spirit so they do not all circle together.
var _spin: float = 1.0
## Direction CHARGE locked onto. Does not change during the rush.
var _locked: Vector2 = Vector2.ZERO
var _stagger_left: float = 0.0
## Winter Bell: how much of its speed is taken, and for how much longer.
var _chill_slow: float = 0.0
var _chill_left: float = 0.0
## Perishing. Cannot take or deal more hits.
var _perishing: bool = false
## The first spirit placed in the scene is already solid; only freshly spawned ones
## are false during `materialize()`.
var _materialized: bool = true
## Even if several meteors hit in one physics tick, make only one white flash tween.
var _last_flash_frame: int = -1
## Guardian moves and telegraph art. Drawn directly so hit tint and elite tint do not mix.
var _guardian_move: GuardianMove = GuardianMove.CHASE
var _guardian_left: float = FOREST_CHASE_SECONDS
var _guardian_move_duration: float = FOREST_CHASE_SECONDS
## Late haste locked at state start. AI and state animation share one clock.
var _guardian_move_haste: float = 1.0
## Whether forest follows the first charge with another aim.
var _guardian_combo_left: int = 0
## Field barrage 0=cross, 1=radial with a safe gap.
var _guardian_pattern: int = 0
## Which fan of a sequence is being wound up: 0 the first, then the follow-ups that are re-aimed at you.
var _fan_index: int = 0
## Leap: where the toad is going, and how many leaps it has made (every third is the flop).
var _leap_target: Vector2 = Vector2.ZERO
var _leap_index: int = 0
var _leap_pace: float = 1.0
## Time until the field guardian's next aimed bolt while strafing.
## Starts half-ready so the opening strafe pokes once, never on frame one.
var _guardian_poke_left: float = FIELD_POKE_INTERVAL * 0.5
## Short white edge flash when camp armor blocks damage.
var _camp_guard_flash: float = 0.0
var _telegraph: Telegraph = Telegraph.NONE
var _telegraph_direction: Vector2 = Vector2.RIGHT
var _telegraph_ratio: float = 0.0
## Projectiles call the arena directly, not through the firer. So if the firer dies first,
## bolts already in flight do not become harmless.
var _projectile_hit_handler: Callable = Callable()


## Spirits toughen as the cycle rises.
##
## **Without this, endless play does not work.** By cycle 3 the player has stacked nine
## relics while spirits match cycle 1, so walking around melts them.
## If only guardians scale and fodder stays soft, a cycle is just waiting.
var toughness: float = 1.0
## Speed multiplier for this one spirit. 1 unless an omen is quickening the night.
var omen_speed: float = 1.0

## Elite. Bigger, brighter, triple tough. Always drops dew when killed.
var elite: bool = false
## Cycle read by guardian patterns. Arena sets this on spawn.
var guardian_cycle: int = 1
## What this guardian gained this cycle (`Expedition.Mutation`). Arena sets it before it appears.
var mutations: Array[int] = []
## The cycle an ordinary spirit is met in: what it throws grows a little with it. Arena sets it on spawn.
var mob_cycle: int = 1
## What it throws (`SpiritKind.barrage`; for a guardian the aura that never stops) and, for a guardian, the heavier
## stream it adds while it chases, glides or rests.
var _barrages: Array[BulletEmitter] = []
var _streams: Array[BulletEmitter] = []
var _field: BulletField = null
var _shooting_age: float = 0.0
var _echoes: Array[Dictionary] = []
var _volleys_fired: int = 0
var _aegis_wait: float = AEGIS_REST * 0.6
var _aegis_left: float = 0.0
var _aegis_ping: float = 0.0
var _pack_stage: int = 0
var _meteor_wait: float = 0.0
var _meteors_this_rest: int = 0


func _ready() -> void:
	if kind == null:
		kind = load(FALLBACK_KIND) as SpiritKind
	_health = maxi(int(round(float(kind.health) * toughness)), 1)
	_guardian_full_health = _health
	_reset_guardian_damage_budget()
	_spin = 1.0 if randf() < 0.5 else -1.0
	_ai_left = randf() * AI_INTERVAL
	# Scatter starts so same kinds do not sync when they spawn together.
	_beat = randf() * 1.5
	_apply_kind()
	if kind.behavior == SpiritKind.Behavior.GUARDIAN:
		_guardian_left = _guardian_opening_seconds() + MATERIALIZE_SECONDS
		_guardian_move_duration = _guardian_left
	if elite:
		_become_elite()
	_build_barrages()


## Remaining health as 0–1. Guardian health bar uses this.
func get_health_ratio() -> float:
	var full: float = maxf(float(kind.health) * toughness, 1.0)
	return clampf(float(_health) / full, 0.0, 1.0)


func _guardian_damage_capacity() -> float:
	if kind == null or kind.behavior != SpiritKind.Behavior.GUARDIAN:
		return 0.0
	return maxf(
		float(_guardian_full_health) \
			* clampf(
				kind.guardian_burst_fraction,
				SpiritKind.LATE_BUDGET_FLOOR,
				0.5),
		1.0)


func _reset_guardian_damage_budget() -> void:
	_guardian_damage_budget = _guardian_damage_capacity()
	_guardian_deferred_damage = 0.0


func _refill_guardian_damage_budget(delta: float) -> void:
	if kind == null or kind.behavior != SpiritKind.Behavior.GUARDIAN:
		return
	var per_second: float = float(_guardian_full_health) \
		* clampf(
			kind.guardian_sustain_fraction,
			SpiritKind.LATE_BUDGET_FLOOR,
			0.5)
	_guardian_damage_budget = minf(
		_guardian_damage_capacity(),
		_guardian_damage_budget + per_second * maxf(delta, 0.0))


func _queue_guardian_damage(amount: int) -> void:
	# Only cap so the integer does not grow past remaining HP. The ceiling does not
	# discard damage — it avoids double-storing past an already certain kill.
	_guardian_deferred_damage = minf(
		float(_health),
		_guardian_deferred_damage + float(maxi(amount, 0)))
	_drain_guardian_damage()
	queue_redraw()


func _drain_guardian_damage() -> void:
	if _guardian_deferred_damage < 1.0 or _guardian_damage_budget < 1.0:
		return
	var received: int = mini(
		floori(minf(_guardian_deferred_damage, _guardian_damage_budget) + 0.0001),
		_health)
	if received <= 0:
		return
	_guardian_damage_budget = maxf(
		_guardian_damage_budget - float(received), 0.0)
	_guardian_deferred_damage = maxf(
		_guardian_deferred_damage - float(received), 0.0)
	_health -= received
	queue_redraw()
	if _health <= 0:
		_guardian_deferred_damage = 0.0
		_sprite.modulate = _white_flash_modulate()
		_perish()


## Become elite. Elites must look elite.
##
## HP alone and the player **does not know why this one will not die.** Size and light
## say "that one is different" first, then toughness.
func _become_elite() -> void:
	_health = maxi(_health * 3, 1)
	_guardian_full_health = _health
	_reset_guardian_damage_budget()

	# `kind` is a shared resource. Multiplying in place gives **every spirit of that kind**
	# elite score. Duplicate, then raise only this one.
	kind = kind.duplicate()
	kind.score_value *= 4
	scale = Vector2(1.3, 1.3)

	var glow: Color = Color(1.0, 0.72, 0.42, 1)
	_sprite.modulate = glow
	var beat: Tween = create_tween().set_loops()
	beat.tween_property(_sprite, "modulate", Color(1.0, 0.94, 0.78, 1), 0.5)
	beat.tween_property(_sprite, "modulate", glow, 0.5)


## Alive and hittable. Arena uses this when picking the nearest spirit.
##
## Exclude materializing and perishing.
## Hitting something with no body only swings the blade through air.
func is_attackable() -> bool:
	return not _perishing and _materialized and _aegis_left <= 0.0


## Hit by the moonlight blade. Arena calls this.
##
## Normal spirits read hits as white flash · knockback · hitch · perish. Guardians only take
## flash and perish. If auto-weapons keep overwriting guardian stagger, stronger builds
## paradoxically stop the boss from attacking.
func take_damage(amount: int, from_position: Vector2) -> void:
	if _perishing:
		return
	# Behind a shield ring nothing lands. The ring flashes so the player sees why.
	if _aegis_left > 0.0:
		_aegis_ping = 1.0
		queue_redraw()
		return

	var received: int = amount
	var is_guardian: bool = kind.behavior == SpiritKind.Behavior.GUARDIAN
	var camp_guarded: bool = is_guardian \
		and kind.guardian_style == SpiritKind.GuardianStyle.CAMP \
		and _guardian_move != GuardianMove.RECOVER
	if camp_guarded:
		# Closed plate blocks only the first 15%. Open recover takes full damage, so the
		# guide text and the real damage window match. Later cycles raise the block ratio so
		# missing the open window leaves the boss barely scratched.
		received = maxi(roundi(float(amount) * _camp_guard_multiplier()), 1)
		_camp_guard_flash = 1.0
		queue_redraw()
	if is_guardian:
		_queue_guardian_damage(received)
	else:
		_health -= received
	# If the guardian's immediate apply was a killing blow, `_drain_guardian_damage()` already
	# emitted perish. Do not perish twice through the normal-spirit branch below.
	if _perishing:
		return
	if _health <= 0:
		# A killing hit must still read white. The node is gone in 0.25s, so skip a separate
		# flash Tween — set white immediately and let the perish fade carry it.
		_sprite.modulate = _white_flash_modulate()
		_perish()
		return

	# White flash. Eight AoE meteors in one tick all deal damage, but there is no need
	# to build eight identical tweens.
	#
	# **Brighten `Sprite` only, not the root.** Root modulate also lights child `Shadow`,
	# so the foot shadow becomes a pink bar. That shipped once and was fixed from a capture.
	#
	# Root carries night tint (`kind.tint`), so multiply by the inverse to cancel it.
	# tint (0.315, 0.35, 0.57) needs (3.2, 2.9, 1.8) to reach white.
	var frame: int = Engine.get_physics_frames()
	if frame != _last_flash_frame:
		_last_flash_frame = frame
		var flash: Tween = create_tween()
		flash.tween_property(_sprite, "modulate", _white_flash_modulate(), 0.0)
		flash.tween_interval(FLASH_SECONDS)
		flash.tween_property(_sprite, "modulate", Color.WHITE, 0.05)

	# Only normal spirits knock and hitch. Guardian position and action clocks ignore hits
	# so charge, barrage, and armor-open patterns are not crushed by combat power.
	if is_guardian:
		return
	var away: Vector2 = (global_position - from_position).normalized()
	if away.length() < 0.01:
		away = Vector2.DOWN
	velocity = away * KNOCKBACK_SPEED
	_stagger_left = kind.stagger_seconds


## The debug button verifies cycle transitions, not boss balance.
## Do not hide a 999999 exception in live damage — skip the budget only at this debug entry.
func debug_slay() -> void:
	if not OS.is_debug_build() or _perishing:
		return
	_guardian_deferred_damage = 0.0
	_health = 0
	_sprite.modulate = _white_flash_modulate()
	_perish()


func _white_flash_modulate() -> Color:
	# Original spirit sheets keep their palette with a white root tint.
	# A plain reciprocal then is white → white and the hit flash vanishes.
	# Dark legacy tints composite up to white; already-bright custom sheets still get
	# at least 1.65× glow so one frame of hit reaction remains.
	return Color(
		maxf(1.0 / maxf(kind.tint.r, 0.05), 1.65),
		maxf(1.0 / maxf(kind.tint.g, 0.05), 1.65),
		maxf(1.0 / maxf(kind.tint.b, 0.05), 1.65))


## Perish.
##
## Immediate `queue_free()` pops off screen. Appear took 0.9s; vanishing in 0 frames
## mismatches front and back.
func _perish() -> void:
	# Even if instant damage and another same-frame killing blow overlap, the cycle-complete
	# signal must fire once. Callers are not all required to know the time boundary.
	if _perishing:
		return
	_perishing = true
	_target = null
	_clear_telegraph()
	_materialized = false
	perished.emit(kind, global_position, elite)
	_burst_sparks()

	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	var out: Tween = create_tween()
	out.set_parallel(true)
	out.tween_property(self, "modulate:a", 0.0, PERISH_SECONDS)
	out.tween_property(self, "scale", scale * 1.35, PERISH_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	out.chain().tween_callback(queue_free)


## Ask the arena's spark pool for a burst where this spirit died.
##
## Through the group, not a node path: a spirit in a test or a title preview has no
## arena, and then nothing is listening and the kill is simply quiet.
func _burst_sparks() -> void:
	var guardian: bool = kind.behavior == SpiritKind.Behavior.GUARDIAN
	get_tree().call_group(KillSparks.GROUP, "burst", global_position,
		kind.boss_accent if guardian else kind.spark_color, guardian or elite)


## Slice the sheet into `SpriteFrames`.
##
## Required if each kind does not get its own `.tscn`.
##
## Two layouts. Directional sheets are **columns = facing, rows = frames**;
## directionless sheets (guardians) are **frames in one horizontal row.**
## The original spirit catalog keeps this spec so one assembly path covers every kind.
## Scale applied to every on-screen monster together.
##
## Per-kind `body_scale` is relative size — leave it. Feedback that things are "a bit
## big overall" is about global size, not those ratios, so shrink once here.
## `terrain_radius()` multiplies `global_scale`, so collision shrinks too.
const BODY_SCALE_GLOBAL: float = 0.612
## Guardian-only restore factor.
##
## When sizes were cut, player art went to 0.765× and mobs to 0.612×. Mobs lost an extra
## 20%, so bosses looked small next to the hero. 0.765 / 0.612 = 1.25 —
## that exactly restores the pre-shrink ratio. Normal spirits are fine at current size,
## so only guardians get this.
const GUARDIAN_BODY_SCALE: float = 1.25


func _apply_kind() -> void:
	var body: float = kind.body_scale * BODY_SCALE_GLOBAL
	if kind.behavior == SpiritKind.Behavior.GUARDIAN:
		body *= GUARDIAN_BODY_SCALE
	scale = Vector2.ONE * body
	modulate = kind.tint

	var sheet: SpriteFrames = SpriteFrames.new()
	sheet.remove_animation(&"default")
	for facing in maxi(kind.facings, 1):
		var anim: StringName = &"float_" + FACING_NAMES[mini(facing, FACING_NAMES.size() - 1)]
		sheet.add_animation(anim)
		sheet.set_animation_loop(anim, true)
		sheet.set_animation_speed(anim, kind.anim_fps)
		for frame in maxi(kind.frames, 1):
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = kind.sheet
			atlas.region = _cell_of(facing, frame)
			sheet.add_frame(anim, atlas)
	if kind.behavior == SpiritKind.Behavior.GUARDIAN:
		_add_guardian_animation(
			sheet, GUARDIAN_WINDUP_ANIM, kind.guardian_windup_sheet)
		_add_guardian_animation(
			sheet, GUARDIAN_ALT_WINDUP_ANIM, kind.guardian_alt_windup_sheet)
		_add_guardian_animation(
			sheet, GUARDIAN_CHARGE_ANIM, kind.guardian_charge_sheet)
		_add_guardian_animation(
			sheet, GUARDIAN_RECOVER_ANIM, kind.guardian_recover_sheet)
	_sprite.sprite_frames = sheet
	# `offset` is overwritten every frame by the `Hover` animation. Set it here and it lives
	# one frame then dies. Size-based lift goes on `position` instead.
	_sprite.position.y = kind.lift
	_sprite.play(&"float_down")


## Attach a directionless guardian state sheet as a one-shot animation.
##
## Real state length differs by terrain, so FPS is matched with speed_scale in
## `_play_guardian_visual()`. Empty sheets skip creating the animation.
func _add_guardian_animation(
		frames: SpriteFrames,
		animation: StringName,
		texture: Texture2D,
	) -> void:
	if texture == null:
		return
	var required_width: int = kind.cell * kind.guardian_state_frames
	var texture_size: Vector2 = texture.get_size()
	if texture_size.x < required_width or texture_size.y < kind.cell:
		push_warning(
			"%s guardian sheet is smaller than the required %dx%d"
			% [animation, required_width, kind.cell])
		return
	frames.add_animation(animation)
	frames.set_animation_loop(animation, false)
	frames.set_animation_speed(animation, kind.guardian_state_fps)
	for frame_index in kind.guardian_state_frames:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(
			frame_index * kind.cell, 0, kind.cell, kind.cell)
		frames.add_frame(animation, atlas)


## Where facing `facing`, frame `frame` sits on the sheet.
func _cell_of(facing: int, frame: int) -> Rect2:
	if kind.facings <= 1:
		return Rect2(frame * kind.cell, 0, kind.cell, kind.cell)
	return Rect2(facing * kind.cell, frame * kind.cell, kind.cell, kind.cell)


## Fade in from the dark.
##
## Popping in asks "when did that appear." And **untouchable while appearing** —
## hitting a body that is not solid yet feels unfair.
## As cycles rise, guardians change **visibly.**
##
## Numbers alone make cycle-5 and cycle-9 bosses look the same, so the player dies
## suddenly without knowing what they face. Show tier first with size, light, and pulse —
## the screen must say "this one is different" before they can prepare.
##
## Do not touch the hitbox. Growing the hit raises difficulty twice.
const GUARDIAN_TIER_STEP: float = 0.06
const GUARDIAN_TIER_MAX_SCALE: float = 1.42


func _apply_guardian_tier() -> void:
	var tier: int = maxi(guardian_cycle - 1, 0)
	if tier <= 0:
		return
	var grow: float = minf(1.0 + GUARDIAN_TIER_STEP * float(tier),
		GUARDIAN_TIER_MAX_SCALE)
	_sprite.scale = Vector2.ONE * grow

	# Swallowed light leaks out of the body. As designed —
	# what ate a beacon glows, and what glows is large.
	var heat: float = minf(0.08 * float(tier), 0.5)
	var accent: Color = kind.boss_accent if kind != null else Color(1, 0.8, 0.5)
	_sprite.modulate = Color(
		1.0 + heat * accent.r,
		1.0 + heat * accent.g * 0.6,
		1.0 + heat * accent.b * 0.4,
		1.0)

	# Late tiers breathe. Standing still still feels oppressive.
	if tier >= 3:
		var beat: Tween = create_tween().set_loops()
		var pace: float = maxf(0.62 - 0.04 * float(tier - 3), 0.32)
		beat.tween_property(_sprite, "scale", Vector2.ONE * (grow * 1.05), pace) \
			.set_trans(Tween.TRANS_SINE)
		beat.tween_property(_sprite, "scale", Vector2.ONE * grow, pace) \
			.set_trans(Tween.TRANS_SINE)


func materialize() -> void:
	_apply_guardian_tier()
	var alpha: float = modulate.a
	modulate.a = 0.0
	_materialized = false
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", alpha, MATERIALIZE_SECONDS)
	await fade.finished
	if not is_inside_tree():
		return
	# Off the target list while appearing, but already-flying AoE can still call
	# `take_damage()` directly. When materialization ends, reopen the opening shock budget
	# so the first on-screen frame still leaves real seconds of fight.
	_reset_guardian_damage_budget()
	_materialized = true


## Retreat. When a guardian appears, fodder fades into the dark.
func retreat() -> void:
	_target = null
	_clear_telegraph()
	_materialized = false
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.6)
	fade.tween_callback(queue_free)


## Arena sets who to chase. Spirits do not search the scene.
func set_target(node: Node2D) -> void:
	_target = node


func set_terrain_room(room: Room) -> void:
	_terrain_room = room


## Room swaps, spawn correction, and per-tick motion share the same real body radius.
func terrain_radius() -> float:
	var spirit_scale: float = maxf(absf(global_scale.x), absf(global_scale.y))
	return CONTACT_RADIUS * spirit_scale


## Radius actually drawn on screen. Much wider than contact radius.
##
## Compass uses this — a guardian's origin can sit just off-screen while the body remains
## large; treating that as "off-screen" puts an arrow on the boss in front of you.
func visual_radius() -> float:
	var spirit_scale: float = maxf(absf(global_scale.x), absf(global_scale.y))
	if _sprite != null and _sprite.sprite_frames != null \
			and _sprite.sprite_frames.has_animation(_sprite.animation):
		var frame: Texture2D = _sprite.sprite_frames.get_frame_texture(
			_sprite.animation, 0)
		if frame != null:
			var size: Vector2 = frame.get_size()
			return maxf(size.x, size.y) * 0.5 * spirit_scale
	return CONTACT_RADIUS * spirit_scale


func _physics_process(delta: float) -> void:
	if not _perishing:
		_refill_guardian_damage_budget(delta)
		_drain_guardian_damage()
	if _camp_guard_flash > 0.0:
		_camp_guard_flash = maxf(_camp_guard_flash - delta * 7.0, 0.0)
		queue_redraw()
	# A telegraph pulses and streams, so it needs a fresh frame each tick, not only when it changes.
	if _telegraph != Telegraph.NONE or _guardian_move == GuardianMove.RECOVER \
			or _aegis_left > 0.0 or not _echoes.is_empty():
		queue_redraw()

	# Do nothing while perishing. The tween frees itself when done.
	if _perishing:
		return

	if _chill_left > 0.0:
		_chill_left = maxf(_chill_left - delta, 0.0)
		if _chill_left <= 0.0:
			_chill_slow = 0.0
			queue_redraw()

	_cooldown = maxf(_cooldown - delta, 0.0)
	_try_hit()
	if _target == null:
		return

	# Do not chase while hitching. Only knockback velocity remains, sliding back.
	# A bare `return` here skips `move_and_slide()` and the knockback vanishes.
	if _stagger_left > 0.0:
		_stagger_left -= delta
		_glide(delta, false)
		return

	_tick_barrages(delta)
	_ai_left -= delta
	_ai_elapsed += delta
	if _ai_left > 0.0:
		_glide(delta, _can_steer_around_terrain())
		return
	while _ai_left <= 0.0:
		_ai_left += AI_INTERVAL
	var ai_delta: float = _ai_elapsed
	_ai_elapsed = 0.0

	var to_player: Vector2 = _target.global_position - global_position
	var wish: Vector2 = to_player.normalized()

	match kind.behavior:
		SpiritKind.Behavior.CHARGE:
			wish = _do_charge(ai_delta, to_player)
		SpiritKind.Behavior.ORBIT:
			wish = _do_orbit(ai_delta, to_player)
		SpiritKind.Behavior.SHOOT:
			wish = _do_shoot(ai_delta, to_player)
		SpiritKind.Behavior.GUARDIAN:
			wish = _do_guardian(ai_delta, to_player)
		_:
			# Turn gradually, not instantly. Glue-on chase leaves no way to dodge.
			velocity = velocity.lerp(wish * kind.speed * omen_speed, kind.turn_rate * ai_delta)

	_last_wish = wish
	_apply_separation(ai_delta)
	_glide(delta, _can_steer_around_terrain())
	_face(_last_wish)


## Stop, aim, then rush in a straight line.
##
## **There must be a telegraph.** Without one, getting hit just feels unfair.
## While aiming it shakes red; step aside in that window and it misses.
func _do_charge(delta: float, to_player: Vector2) -> Vector2:
	_beat -= delta

	if _beat > 0.0:
		# Aiming. Shake in place and keep updating direction.
		velocity = velocity.lerp(Vector2.ZERO, 8.0 * delta)
		_locked = to_player.normalized()
		var shake: float = sin(_beat * 42.0) * 1.6
		_sprite.position.x = shake
		_sprite.modulate = Color(1.8, 0.8, 0.8, 1)
		return _locked

	if _beat > -kind.charge_seconds:
		# Charging. Direction is already locked — it does not track, so sidestep.
		velocity = _locked * kind.charge_speed
		_sprite.position.x = 0.0
		_sprite.modulate = Color.WHITE
		return _locked

	# Catch breath. Rest until the next aim.
	_beat = kind.charge_windup
	velocity = velocity.lerp(Vector2.ZERO, 6.0 * delta)
	return _locked


## Circle and slowly close in.
##
## Only straight chasers make aim always the same. Mix in orbiters and **lining up gets harder.**
func _do_orbit(delta: float, to_player: Vector2) -> Vector2:
	var distance: float = to_player.length()
	var inward: Vector2 = to_player.normalized()
	# Tangent direction. Spin side differs per spirit.
	var around: Vector2 = Vector2(-inward.y, inward.x) * _spin

	# Approach when far, retreat when close; otherwise just orbit.
	var pull: float = clampf((distance - kind.orbit_radius) / 40.0, -1.0, 1.0)
	var wish: Vector2 = (around + inward * pull).normalized()

	# Close very slowly. Eternal orbit alone is not a threat.
	var closing: float = kind.orbit_closing * delta
	velocity = velocity.lerp(wish * kind.speed * omen_speed + inward * closing, kind.turn_rate * delta)
	return wish


## The bullets a spirit throws besides touching you, built once when it appears. A guardian gets the aura that never
## stops and the heavier stream that comes when it is not winding anything up; an ordinary spirit whose kind has a
## barrage gets that one (a caster's is thrown after its windup instead, see `_fire_caster_shot`).
func _build_barrages() -> void:
	_barrages.clear()
	_streams.clear()
	if kind == null:
		return
	if kind.behavior == SpiritKind.Behavior.GUARDIAN:
		_barrages = GuardianStreams.aura(kind.guardian_style, guardian_cycle)
		_streams = GuardianStreams.stream(kind.guardian_style, guardian_cycle)
		# A fight opens gently: the first thing it throws leaves a beat after it has appeared.
		for emitter in _barrages:
			emitter.restart(1.0 + randf() * 0.6)
			emitter.source = BulletField.Source.AURA
		for emitter in _streams:
			emitter.restart(1.6 + randf() * 0.8)
			emitter.source = BulletField.Source.STREAM
		return
	if kind.behavior == SpiritKind.Behavior.SHOOT or kind.barrage == SpiritKind.Barrage.NONE:
		return
	# Only some of a kind throw at all.
	if randf() > kind.barrage_share:
		return
	var emitter: BulletEmitter
	var speed: float = _mob_bullet_speed()
	match kind.barrage:
		SpiritKind.Barrage.AIMED:
			emitter = BulletEmitter.aimed(kind.barrage_count, kind.barrage_spread, kind.barrage_interval, speed,
				kind.barrage_tint)
		_:
			emitter = BulletEmitter.ring(kind.barrage_count, kind.barrage_interval, speed, 0.7, kind.barrage_tint)
	emitter.range_px = 100.0 if kind.barrage == SpiritKind.Barrage.RING else 110.0
	emitter.source = BulletField.Source.WISP if kind.barrage == SpiritKind.Barrage.RING else kind.barrage_source
	# Spirits that appear together do not shoot together, but the first shot comes fast: most engagements
	# last a few seconds, and a shooter that waits out its own life never throws at all.
	emitter.restart(kind.barrage_interval * randf_range(0.15, 0.5))
	_barrages.append(emitter)


func _mob_bullet_speed() -> float:
	return kind.barrage_speed * (1.0 + 0.02 * float(mini(maxi(mob_cycle, 1) - 1, 10)))


func _bullet_field() -> BulletField:
	if _field != null and is_instance_valid(_field) and _field.is_inside_tree():
		return _field
	_field = BulletField.of(self)
	return _field


## How fast a guardian's stream runs: how thick the night is, and a share of the tempo (enrage, frenzy) it has on.
## An ordinary spirit throws a little oftener each cycle.
func _barrage_rate() -> float:
	if kind.behavior == SpiritKind.Behavior.GUARDIAN:
		return GuardianStreams.stream_rate(guardian_cycle, _guardian_haste())
	return 1.0 + 0.04 * float(mini(maxi(mob_cycle, 1) - 1, 12))


func _tick_barrages(delta: float) -> void:
	if _barrages.is_empty() and _streams.is_empty():
		return
	if _perishing or not _materialized or _target == null or not is_instance_valid(_target):
		return
	var field: BulletField = _bullet_field()
	if field == null:
		return
	var guardian: bool = kind.behavior == SpiritKind.Behavior.GUARDIAN
	var origin: Vector2 = global_position + Vector2(0, -6)
	var aim_at: Vector2 = _target.global_position + Vector2(0, -4)
	if origin.distance_to(aim_at) > (GUARDIAN_BARRAGE_REACH if guardian else BARRAGE_REACH):
		return
	if not guardian:
		_shooting_age += delta
		if _shooting_age < MOB_QUIET_SECONDS or field.count() >= MOB_BULLET_SOFT_LIMIT or field.is_quiet():
			return
	var rate: float = _barrage_rate()
	for emitter in _barrages:
		emitter.tick(delta, origin, aim_at, field, rate)
	# The heavier layer runs only while it is not winding up a volley or a charge, and half as thick while it rests.
	if guardian and (_guardian_move == GuardianMove.CHASE or _guardian_move == GuardianMove.RECOVER):
		var share: float = 0.5 if _guardian_move == GuardianMove.RECOVER else 1.0
		for emitter in _streams:
			emitter.tick(delta, origin, aim_at, field, rate * share)


## The caster's shot, after the windup that showed its line: a fan of bullets where it used to throw one bolt, five
## from the third cycle.
func _fire_caster_shot(direction: Vector2) -> void:
	var field: BulletField = _bullet_field()
	if field == null or kind.barrage != SpiritKind.Barrage.AIMED:
		_fire(direction)
		return
	field.fan(global_position + Vector2(0, -6), direction.angle(), _caster_fan_count(), _caster_fan_spread(),
		_mob_bullet_speed(), kind.barrage_tint, 175.0, 0.0, BulletField.Source.CASTER)


## Keep distance and fire moonlight.
##
## Retreats when close, so it **rarely enters auto-attack range.**
## Dash in to catch it — the first real use for dash.
func _do_shoot(delta: float, to_player: Vector2) -> Vector2:
	var distance: float = to_player.length()
	var inward: Vector2 = to_player.normalized()

	# Retreat if too close; approach if too far.
	var pull: float = clampf((distance - kind.keep_distance) / 50.0, -1.0, 1.0)
	velocity = velocity.lerp(inward * pull * kind.speed * omen_speed, kind.turn_rate * delta)

	_beat -= delta
	if _locked != Vector2.ZERO:
		# Lock to the direction at telegraph start. Retargeting to the end makes it undodgeable.
		_set_telegraph(Telegraph.AIM, _locked,
			clampf(-_beat / CASTER_WINDUP, 0.0, 1.0))
		if _beat <= -CASTER_WINDUP:
			_fire_caster_shot(_locked)
			_locked = Vector2.ZERO
			_beat = kind.shoot_interval
			_clear_telegraph()
	elif _beat <= 0.0:
		# The screen's shooters take turns: a caster whose turn has not come waits a moment and asks again.
		var field: BulletField = _bullet_field()
		if field != null and not field.claim_volley(MOB_VOLLEY_GAP):
			_beat = 0.25
		else:
			_locked = inward
			_beat = 0.0
	return inward


## Hand each terrain guardian a fully different combat grammar.
func _do_guardian(delta: float, to_player: Vector2) -> Vector2:
	_tick_mutations(delta, to_player)
	match kind.guardian_style:
		SpiritKind.GuardianStyle.FIELD:
			return _do_guardian_field(delta, to_player)
		SpiritKind.GuardianStyle.CAMP:
			return _do_guardian_camp(delta, to_player)
		SpiritKind.GuardianStyle.GALE:
			return _do_guardian_gale(delta, to_player)
		SpiritKind.GuardianStyle.LEAP:
			return _do_guardian_leap(delta, to_player)
		SpiritKind.GuardianStyle.GLYPH:
			return _do_guardian_glyph(delta, to_player)
		_:
			return _do_guardian_forest(delta, to_player)


func _guardian_opening_seconds() -> float:
	match kind.guardian_style:
		SpiritKind.GuardianStyle.FIELD:
			return FIELD_STRAFE_SECONDS
		SpiritKind.GuardianStyle.CAMP:
			return CAMP_APPROACH_SECONDS
		SpiritKind.GuardianStyle.GALE:
			return GALE_GLIDE_SECONDS
		SpiritKind.GuardianStyle.LEAP:
			return LEAP_WADDLE_SECONDS
		SpiritKind.GuardianStyle.GLYPH:
			return GLYPH_DRIFT_SECONDS
		_:
			return FOREST_CHASE_SECONDS


## The cycle whose tempo this guardian fights at: the cycle itself through the official win, then
## a quarter as fast. Left to grow one for one, a cycle-14 windup lasts a fifth of a second and a
## bolt flies twice as fast, and the endless stretch would stop being a game of reading a marking and
## stepping out of it. Past the win a guardian is still a little quicker each time, never a reflex test.
func _tempo_cycle() -> int:
	var win: int = Expedition.OFFICIAL_WIN_CYCLE
	if guardian_cycle <= win:
		return guardian_cycle
	return win + (guardian_cycle - win) / 4


func _late_cycles() -> int:
	return maxi(_tempo_cycle() - 3, 0)


func _guardian_haste() -> float:
	# Cycles 1–3 add 10% each. From cycle 4, telegraphs and gaps shrink faster and hit pressure rises.
	var cycle_haste: float = 1.0 \
		+ 0.10 * float(maxi(_tempo_cycle() - 1, 0)) \
		+ 0.12 * float(_late_cycles())
	var enrage_at: float = 0.45 if guardian_cycle >= 5 else 0.3
	var enrage: float = 1.28 if guardian_cycle >= 5 else 1.15
	var low: float = enrage if get_health_ratio() <= enrage_at else 1.0
	var frenzy: float = FRENZY_HASTE if has_mutation(Expedition.Mutation.FRENZY) else 1.0
	return cycle_haste * low * frenzy


func _forest_followup_count() -> int:
	if kind == null:
		return 1
	var extra: int = maxi(guardian_cycle - 2, 0) + maxi(guardian_cycle - 5, 0)
	var cap: int = 5 if guardian_cycle <= 4 else 7
	return mini(maxi(kind.guardian_combo, 1) + extra, cap)


func _camp_recover_seconds() -> float:
	var scale: float = 1.0
	if kind != null:
		scale = kind.guardian_recover_scale
	var shrink: float = 1.0 \
		- 0.10 * float(maxi(_tempo_cycle() - 1, 0)) \
		- 0.12 * float(_late_cycles())
	return CAMP_RECOVER_SECONDS \
		* clampf(shrink, 0.32, 1.0) \
		* clampf(scale, 0.4, 1.4)


func _camp_guard_multiplier() -> float:
	return clampf(0.85 - 0.04 * float(_late_cycles()), 0.65, 0.85)


func _guardian_charge_speed() -> float:
	# Cycles 1–3 keep the existing charge speed. Only late cycles scale with the same haste
	# multiplier to hold corridor length, then push a bit more to widen the hit face.
	var kind_speed: float = kind.charge_speed if kind != null else 260.0
	if _late_cycles() <= 0:
		return kind_speed
	return kind_speed * _guardian_move_haste * (1.0 + 0.06 * float(_late_cycles()))


# --- Mutations ----------------------------------------------------------------------
#
# A mutation is a small rule hung on the move machine every guardian already has, so the same six
# work on every style. They are told to the player twice: at the introduction and under the boss bar.

func has_mutation(mutation: int) -> bool:
	return mutations.has(mutation)


## Runs once per guardian tick, before its own move.
func _tick_mutations(delta: float, _to_player: Vector2) -> void:
	if mutations.is_empty():
		return
	_tick_echoes(delta)
	_tick_aegis(delta)
	_tick_pack()
	_tick_meteors(delta)
	queue_redraw()


## A windup aims through the spiral. With the mutation each volley's safe gap sits a little further
## round than the last, so holding the ground you held before is the wrong answer. The telegraph and
## the shot both read `_locked`, so what is drawn is exactly what fires.
func _spiral_aim(inward: Vector2, volley: int) -> Vector2:
	if not has_mutation(Expedition.Mutation.SPIRAL):
		return inward
	if volley == Volley.CAMP_FAN:
		# An aimed fan swings to one side and the other, not round you.
		return inward.rotated(0.34 if _volleys_fired % 2 == 0 else -0.34)
	return inward.rotated(fposmod(SPIRAL_STEP * float(_volleys_fired + 1), TAU))


var _echoing: bool = false


## Every volley counts; with Echo it also queues to come again, turned a little.
func _after_volley(volley: int) -> void:
	_volleys_fired += 1
	if _echoing or not has_mutation(Expedition.Mutation.ECHO):
		return
	# A run of fans is one attack and repeats once, after its last fan: six fans in under two seconds is not a pattern.
	if volley == Volley.CAMP_FAN and _guardian_combo_left > 0:
		return
	_echoes.append({
		"left": ECHO_DELAY,
		"volley": volley,
		"pattern": _guardian_pattern,
		"fan": _fan_index,
		"angle": _locked.angle() + ECHO_TURN,
	})


func _tick_echoes(delta: float) -> void:
	for index in range(_echoes.size() - 1, -1, -1):
		var echo: Dictionary = _echoes[index]
		echo["left"] = float(echo["left"]) - delta
		if float(echo["left"]) > 0.0:
			continue
		_echoes.remove_at(index)
		_replay_volley(echo)


func _replay_volley(echo: Dictionary) -> void:
	var saved_lock: Vector2 = _locked
	var saved_pattern: int = _guardian_pattern
	var saved_fan: int = _fan_index
	_locked = Vector2.RIGHT.rotated(float(echo["angle"]))
	_guardian_pattern = int(echo["pattern"])
	_fan_index = int(echo["fan"])
	_echoing = true
	match int(echo["volley"]):
		Volley.FOREST_RING:
			_fire_forest_ring()
		Volley.FIELD:
			_fire_field_volley()
		_:
			_fire_camp_fan()
	_echoing = false
	_locked = saved_lock
	_guardian_pattern = saved_pattern
	_fan_index = saved_fan


## Aegis: a ring of light stands for a few seconds and nothing lands. It never opens during the rest
## that follows a volley, which is the window a fight is built around.
func _tick_aegis(delta: float) -> void:
	if not has_mutation(Expedition.Mutation.AEGIS):
		return
	_aegis_ping = maxf(_aegis_ping - delta * 4.0, 0.0)
	if _aegis_left > 0.0:
		_aegis_left = maxf(_aegis_left - delta, 0.0)
		if _guardian_move == GuardianMove.RECOVER:
			_aegis_left = minf(_aegis_left, 0.25)
		if _aegis_left <= 0.0:
			_aegis_wait = AEGIS_REST
		return
	if _guardian_move == GuardianMove.RECOVER or not _materialized:
		return
	_aegis_wait -= delta
	if _aegis_wait <= 0.0:
		_aegis_left = AEGIS_UP


## Summoner: at two thirds and at one third of its health it calls a pack.
func _tick_pack() -> void:
	if _pack_stage >= 2 or not has_mutation(Expedition.Mutation.SUMMONER) or _health <= 0:
		return
	var threshold: float = 0.66 if _pack_stage == 0 else 0.33
	if get_health_ratio() >= threshold:
		return
	_pack_stage += 1
	calls_pack.emit(global_position, 3 + mini(maxi(guardian_cycle - 8, 0) / 3, 3))


## Meteors: while it rests, marks fall on and around you. Each is a circle you can simply leave.
func _tick_meteors(delta: float) -> void:
	if not has_mutation(Expedition.Mutation.METEORS) or _target == null:
		return
	if _guardian_move != GuardianMove.RECOVER:
		_meteors_this_rest = 0
		_meteor_wait = 0.0
		return
	if _meteors_this_rest >= METEORS_PER_REST:
		return
	_meteor_wait -= delta * _guardian_move_haste
	if _meteor_wait > 0.0:
		return
	_meteor_wait = METEOR_INTERVAL
	var at: Vector2 = _target.global_position
	if _meteors_this_rest > 0:
		at += Vector2.RIGHT.rotated(randf() * TAU) * randf_range(28.0, 84.0)
	if _terrain_room != null and is_instance_valid(_terrain_room):
		at = _terrain_room.clamp_to_play(at)
	var mark: GroundBurst = GroundBurst.mark(
		get_parent(), at, METEOR_RADIUS, METEOR_FUSE, kind.boss_accent,
		_target, _projectile_hit_handler)
	if mark != null:
		_meteors_this_rest += 1


## What the mutations look like on the body: an echo ring just before a repeat, the shield bubble,
## and a red flicker for a frenzied one. All in the same soft light as the telegraphs.
func _draw_mutation_marks() -> void:
	if mutations.is_empty():
		return
	var accent: Color = _telegraph_accent().lerp(Color.WHITE, 0.3)
	var centre: Vector2 = Vector2(0, -6)
	for echo in _echoes:
		var left: float = float(echo["left"])
		if left < ECHO_WARN:
			var lit: float = 1.0 - left / ECHO_WARN
			TelegraphArt.glow_ring(self, centre, 26.0 + 16.0 * lit, accent, 0.3 + 0.6 * lit, 1.4, 0.85)
			# The repeat is shown where it will go, the way any warning is.
			_draw_volley(volley_shape_for(int(echo["volley"]), float(echo["angle"]),
				int(echo["pattern"]), int(echo["fan"])), lit, 0.75)
	if _aegis_left > 0.0:
		var fade: float = clampf(_aegis_left / 0.4, 0.0, 1.0)
		var bubble: Color = Color(0.66, 0.92, 1.0, 1.0)
		TelegraphArt.soft_disc(self, centre, 34.0, bubble, (0.2 + 0.22 * _aegis_ping) * fade, 0.9)
		TelegraphArt.glow_ring(self, centre, 34.0, bubble, (0.55 + 0.4 * _aegis_ping) * fade, 1.5, 0.9)
	if has_mutation(Expedition.Mutation.FRENZY):
		var flicker: float = 0.5 + 0.5 * sin(TelegraphArt.clock() * 14.0)
		TelegraphArt.glow_ring(self, centre, 30.0 + 2.0 * flicker, TelegraphArt.DANGER,
			0.25 + 0.3 * flicker, 1.3, 0.85)


func _start_guardian_move(move: GuardianMove, seconds: float, warning_floor: float = MIN_WINDUP) -> void:
	_guardian_move = move
	_guardian_left = seconds
	_guardian_move_duration = maxf(seconds, 0.001)
	# Crossing the 30% HP boundary mid-state still waits until the next state to change speed.
	# That way telegraph and state sheet finish on one beat.
	_guardian_move_haste = _guardian_haste()
	if move == GuardianMove.CHARGE_WINDUP or move == GuardianMove.VOLLEY_WINDUP:
		# The tempo may quicken everything else about a guardian; the warning keeps its floor.
		_guardian_move_haste = minf(_guardian_move_haste, maxf(seconds / warning_floor, 1.0))
	_play_guardian_visual(move)
	queue_redraw()


## Swap boss AI state and the chosen sheet in the same moment.
##
## If a custom sheet is still missing, fall back to the idle loop so existing guardian.png and
## procedural telegraphs do not change by a single pixel.
func _play_guardian_visual(move: GuardianMove) -> void:
	var animation: StringName = &"float_down"
	match move:
		GuardianMove.CHARGE_WINDUP, GuardianMove.VOLLEY_WINDUP:
			animation = GUARDIAN_WINDUP_ANIM
		GuardianMove.CHARGE:
			animation = GUARDIAN_CHARGE_ANIM
		GuardianMove.RECOVER:
			animation = GUARDIAN_RECOVER_ANIM
	if move == GuardianMove.VOLLEY_WINDUP \
			and kind.guardian_style == SpiritKind.GuardianStyle.FIELD \
			and _guardian_pattern == 1:
		animation = GUARDIAN_ALT_WINDUP_ANIM

	# If only the radial windup sheet is still an unfinished mid-commit, play the cross windup
	# anyway. Fall back to idle float only when both windup sheets are missing.
	if animation == GUARDIAN_ALT_WINDUP_ANIM \
			and not _sprite.sprite_frames.has_animation(animation):
		animation = GUARDIAN_WINDUP_ANIM
	if not _sprite.sprite_frames.has_animation(animation):
		animation = &"float_down"
	_sprite.speed_scale = 1.0
	if animation != &"float_down":
		var frame_count: int = _sprite.sprite_frames.get_frame_count(animation)
		var base_fps: float = _sprite.sprite_frames.get_animation_speed(animation)
		# Reach the last frame as the state ends. Short charges and long armor opens can share a
		# sheet without desyncing the pattern clock from the art clock.
		_sprite.speed_scale = float(frame_count) \
			* _guardian_move_haste \
			/ maxf(base_fps * _guardian_move_duration, 0.001)
	_sprite.play(animation)


## Forest — show a narrow danger corridor, then charge twice in a row.
##
## After the first charge, pause 0.24s and re-aim. Dodge the second and
## it is fully open for 0.82s. Direction locks at each telegraph start.
func _do_guardian_forest(delta: float, to_player: Vector2) -> Vector2:
	var inward: Vector2 = to_player.normalized()
	_guardian_left -= delta * _guardian_move_haste

	match _guardian_move:
		GuardianMove.CHASE:
			velocity = velocity.lerp(
				inward * kind.speed * omen_speed * (1.0 + 0.06 * float(_late_cycles())),
				kind.turn_rate * delta)
			if _guardian_left <= 0.0:
				_guardian_combo_left = _forest_followup_count()
				_locked = inward
				_start_guardian_move(
					GuardianMove.CHARGE_WINDUP, FOREST_CHARGE_WINDUP)
			return inward

		GuardianMove.CHARGE_WINDUP:
			velocity = velocity.lerp(Vector2.ZERO, 9.0 * delta)
			_set_telegraph(Telegraph.CHARGE, _locked,
				1.0 - _guardian_left / _guardian_move_duration)
			if _guardian_left <= 0.0:
				_clear_telegraph()
				_start_guardian_move(GuardianMove.CHARGE, FOREST_CHARGE_SECONDS)
			return _locked

		GuardianMove.CHARGE:
			velocity = _locked * _guardian_charge_speed()
			if _guardian_left <= 0.0:
				velocity *= 0.2
				if _guardian_combo_left > 0:
					_start_guardian_move(
						GuardianMove.RECOVER, FOREST_BETWEEN_CHARGES)
				else:
					# Combo spent. Slam the ring before resting — the gap faces
					# the player, so the answer is the opposite of the charges.
					_locked = _spiral_aim(inward, Volley.FOREST_RING)
					_guardian_pattern = 1
					_start_guardian_move(
						GuardianMove.VOLLEY_WINDUP, FOREST_RING_WINDUP)
			return _locked

		GuardianMove.VOLLEY_WINDUP:
			velocity = velocity.lerp(Vector2.ZERO, 7.0 * delta)
			_set_telegraph(Telegraph.VOLLEY, _locked,
				1.0 - _guardian_left / _guardian_move_duration)
			if _guardian_left <= 0.0:
				_fire_forest_ring()
				_after_volley(Volley.FOREST_RING)
				_clear_telegraph()
				_start_guardian_move(
					GuardianMove.RECOVER, FOREST_RECOVER_SECONDS)
			return _locked

		_:
			velocity = velocity.lerp(Vector2.ZERO, 8.0 * delta)
			if _guardian_left <= 0.0:
				if _guardian_combo_left > 0:
					_guardian_combo_left -= 1
					_locked = inward
					_start_guardian_move(
						GuardianMove.CHARGE_WINDUP, FOREST_FOLLOWUP_WINDUP)
				else:
					_start_guardian_move(
						GuardianMove.CHASE, FOREST_CHASE_SECONDS)
			return inward


## Field — strafe at range, then alternate cross and radial barrages.
func _do_guardian_field(delta: float, to_player: Vector2) -> Vector2:
	var inward: Vector2 = to_player.normalized()
	_guardian_left -= delta * _guardian_move_haste

	match _guardian_move:
		GuardianMove.CHASE:
			var wish: Vector2 = _field_strafe(delta, to_player)
			# Transition first. When the poke timer and the strafe end on the
			# same tick, firing the poke as well stacks a bolt onto the volley.
			if _guardian_left <= 0.0:
				_locked = _spiral_aim(inward, Volley.FIELD)
				_start_guardian_move(
					GuardianMove.VOLLEY_WINDUP, FIELD_VOLLEY_WINDUP)
				return wish
			_guardian_poke_left -= delta * _guardian_move_haste
			if _guardian_poke_left <= FIELD_POKE_WINDUP \
					and _guardian_poke_left > 0.0:
				_set_telegraph(Telegraph.AIM, inward,
					1.0 - _guardian_poke_left / FIELD_POKE_WINDUP)
			if _guardian_poke_left <= 0.0:
				_clear_telegraph()
				_fire(inward)
				_guardian_poke_left = FIELD_POKE_INTERVAL
			return wish

		GuardianMove.VOLLEY_WINDUP:
			velocity = velocity.lerp(Vector2.ZERO, 7.0 * delta)
			_set_telegraph(Telegraph.VOLLEY, _locked,
				1.0 - _guardian_left / _guardian_move_duration)
			if _guardian_left <= 0.0:
				_fire_field_volley()
				_after_volley(Volley.FIELD)
				_guardian_pattern = 1 - _guardian_pattern
				_clear_telegraph()
				_start_guardian_move(
					GuardianMove.RECOVER, FIELD_RECOVER_SECONDS)
			return _locked

		_:
			velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta)
			if _guardian_left <= 0.0:
				_guardian_poke_left = FIELD_POKE_INTERVAL * 0.5
				_start_guardian_move(
					GuardianMove.CHASE, FIELD_STRAFE_SECONDS)
			return inward


func _field_strafe(delta: float, to_player: Vector2) -> Vector2:
	var distance: float = to_player.length()
	var inward: Vector2 = to_player.normalized()
	var around: Vector2 = Vector2(-inward.y, inward.x) * _spin
	var pull: float = clampf(
		(distance - kind.orbit_radius) / 42.0, -0.85, 0.85)
	var wish: Vector2 = (around * 1.15 + inward * pull).normalized()
	velocity = velocity.lerp(
		wish * kind.speed * omen_speed * (1.0 + 0.06 * float(_late_cycles())),
		kind.turn_rate * delta)
	return wish


## Camp — slow siege that holds range. Fire an aim fan, then armor stays open a long time.
func _do_guardian_camp(delta: float, to_player: Vector2) -> Vector2:
	var distance: float = to_player.length()
	var inward: Vector2 = to_player.normalized()
	_guardian_left -= delta * _guardian_move_haste

	match _guardian_move:
		GuardianMove.CHASE:
			var pull: float = clampf(
				(distance - kind.keep_distance) / 58.0, -0.7, 1.0)
			velocity = velocity.lerp(
				inward * pull * kind.speed * omen_speed * (1.0 + 0.06 * float(_late_cycles())),
				kind.turn_rate * delta)
			if _guardian_left <= 0.0:
				_locked = _spiral_aim(inward, Volley.CAMP_FAN)
				_guardian_combo_left = 1
				_fan_index = 0
				_start_guardian_move(
					GuardianMove.VOLLEY_WINDUP, CAMP_VOLLEY_WINDUP, MIN_FAN_WINDUP)
			return inward

		GuardianMove.VOLLEY_WINDUP:
			velocity = velocity.lerp(Vector2.ZERO, 9.0 * delta)
			_set_telegraph(Telegraph.VOLLEY, _locked,
				1.0 - _guardian_left / _guardian_move_duration)
			if _guardian_left <= 0.0:
				_fire_camp_fan()
				_after_volley(Volley.CAMP_FAN)
				_clear_telegraph()
				if _guardian_combo_left > 0:
					_guardian_combo_left -= 1
					_locked = _spiral_aim(inward, Volley.CAMP_FAN)
					_fan_index += 1
					_start_guardian_move(
						GuardianMove.VOLLEY_WINDUP, CAMP_FOLLOWUP_WINDUP)
				else:
					_start_guardian_move(
						GuardianMove.RECOVER, _camp_recover_seconds())
			return _locked

		_:
			# Recover with armor open. No chase, no barrage — a window to dive in.
			velocity = velocity.lerp(Vector2.ZERO, 8.0 * delta)
			if _guardian_left <= 0.0:
				_start_guardian_move(
					GuardianMove.CHASE, CAMP_APPROACH_SECONDS)
			return inward


## Gale — glide, two fans of feathers, a dive through where you stood, then a perch.
func _do_guardian_gale(delta: float, to_player: Vector2) -> Vector2:
	var inward: Vector2 = to_player.normalized()
	_guardian_left -= delta * _guardian_move_haste

	match _guardian_move:
		GuardianMove.CHASE:
			var wish: Vector2 = _field_strafe(delta, to_player)
			if _guardian_left <= 0.0:
				_locked = _spiral_aim(inward, Volley.CAMP_FAN)
				# One follow-up fan, and two for the grown-up owl (`guardian_combo` counts the follow-ups).
				_guardian_combo_left = _fans_in_run() - 1
				_fan_index = 0
				_start_guardian_move(GuardianMove.VOLLEY_WINDUP, GALE_FAN_WINDUP, MIN_FAN_WINDUP)
			return wish

		GuardianMove.VOLLEY_WINDUP:
			velocity = velocity.lerp(Vector2.ZERO, 8.0 * delta)
			_set_telegraph(Telegraph.VOLLEY, _locked,
				1.0 - _guardian_left / _guardian_move_duration)
			if _guardian_left <= 0.0:
				_fire_camp_fan()
				_after_volley(Volley.CAMP_FAN)
				_clear_telegraph()
				if _guardian_combo_left > 0:
					_guardian_combo_left -= 1
					_locked = _spiral_aim(inward, Volley.CAMP_FAN)
					_fan_index += 1
					_start_guardian_move(GuardianMove.VOLLEY_WINDUP, GALE_FAN_FOLLOWUP)
				else:
					# The dive goes where you are now: the fans taught you to move, this asks where.
					_locked = inward
					_start_guardian_move(GuardianMove.CHARGE_WINDUP, GALE_DIVE_WINDUP)
			return _locked

		GuardianMove.CHARGE_WINDUP:
			velocity = velocity.lerp(Vector2.ZERO, 9.0 * delta)
			_set_telegraph(Telegraph.CHARGE, _locked,
				1.0 - _guardian_left / _guardian_move_duration)
			if _guardian_left <= 0.0:
				_clear_telegraph()
				_start_guardian_move(GuardianMove.CHARGE, GALE_DIVE_SECONDS)
			return _locked

		GuardianMove.CHARGE:
			velocity = _locked * _guardian_charge_speed()
			if _guardian_left <= 0.0:
				velocity *= 0.2
				_start_guardian_move(GuardianMove.RECOVER, GALE_RECOVER_SECONDS)
			return _locked

		_:
			velocity = velocity.lerp(Vector2.ZERO, 7.0 * delta)
			if _guardian_left <= 0.0:
				_start_guardian_move(GuardianMove.CHASE, GALE_GLIDE_SECONDS)
			return inward


## Leap — waddle, hop, hop, flop. The circle on the floor is the whole warning: it is where the
## toad lands, and it bursts the moment the toad does.
func _do_guardian_leap(delta: float, to_player: Vector2) -> Vector2:
	var inward: Vector2 = to_player.normalized()
	_guardian_left -= delta * _guardian_move_haste

	match _guardian_move:
		GuardianMove.CHASE:
			velocity = velocity.lerp(
				inward * kind.speed * omen_speed * (1.0 + 0.06 * float(_late_cycles())),
				kind.turn_rate * delta)
			if _guardian_left <= 0.0:
				_start_leap()
			return inward

		GuardianMove.CHARGE_WINDUP:
			velocity = velocity.lerp(Vector2.ZERO, 10.0 * delta)
			if _guardian_left <= 0.0:
				_start_guardian_move(GuardianMove.CHARGE, LEAP_AIR_SECONDS)
				_guardian_move_haste = _leap_pace
			return (_leap_target - global_position).normalized()

		GuardianMove.CHARGE:
			# Arrive exactly as the state ends, wherever the leap began.
			var remaining: float = maxf(_guardian_left / _guardian_move_haste, 0.03)
			velocity = ((_leap_target - global_position) / remaining).limit_length(720.0)
			if _guardian_left <= 0.0:
				velocity = Vector2.ZERO
				if _leap_index % 3 != 0:
					_start_guardian_move(GuardianMove.CHASE, LEAP_BETWEEN_HOPS)
				else:
					# The flop landed: a ring, its gap facing you, then a long rest.
					_locked = inward
					_guardian_pattern = 1
					_start_guardian_move(GuardianMove.VOLLEY_WINDUP, LEAP_RING_WINDUP)
			return (_leap_target - global_position).normalized()

		GuardianMove.VOLLEY_WINDUP:
			velocity = velocity.lerp(Vector2.ZERO, 8.0 * delta)
			_set_telegraph(Telegraph.VOLLEY, _locked,
				1.0 - _guardian_left / _guardian_move_duration)
			if _guardian_left <= 0.0:
				_fire_forest_ring()
				_after_volley(Volley.FOREST_RING)
				_clear_telegraph()
				_start_guardian_move(GuardianMove.RECOVER, _leap_recover_seconds())
			return _locked

		_:
			velocity = velocity.lerp(Vector2.ZERO, 8.0 * delta)
			if _guardian_left <= 0.0:
				_start_guardian_move(GuardianMove.CHASE, LEAP_WADDLE_SECONDS)
			return inward


## Choose where the toad lands, mark it, and crouch. Every third leap is the flop.
func _start_leap() -> void:
	_leap_index += 1
	var flop: bool = _leap_index % 3 == 0
	var at: Vector2 = _target.global_position if _target != null else global_position
	if _terrain_room != null and is_instance_valid(_terrain_room):
		at = _terrain_room.nearest_clear(_terrain_room.clamp_to_play(at), terrain_radius())
	_leap_target = at
	_start_guardian_move(GuardianMove.CHARGE_WINDUP, LEAP_CROUCH)
	# The crouch and the jump keep one pace, slow enough that the circle can be left before it bursts.
	_leap_pace = minf(_guardian_move_haste, maxf((LEAP_CROUCH + LEAP_AIR_SECONDS) / MIN_MARK_FUSE, 1.0))
	_guardian_move_haste = _leap_pace
	# Burst as it lands, whatever the pace of this state.
	GroundBurst.mark(
		get_parent(), at, LEAP_FLOP_RADIUS if flop else LEAP_HOP_RADIUS,
		(LEAP_CROUCH + LEAP_AIR_SECONDS) / _leap_pace, kind.boss_accent,
		_target, _projectile_hit_handler)


func _leap_recover_seconds() -> float:
	var shrink: float = 1.0 \
		- 0.06 * float(maxi(_tempo_cycle() - 1, 0)) \
		- 0.08 * float(_late_cycles())
	return LEAP_RECOVER_SECONDS * clampf(shrink, 0.5, 1.0)


## Glyph — keep a little way off, write circles round you, then a ring with a gap, then rest.
func _do_guardian_glyph(delta: float, to_player: Vector2) -> Vector2:
	var distance: float = to_player.length()
	var inward: Vector2 = to_player.normalized()
	_guardian_left -= delta * _guardian_move_haste

	match _guardian_move:
		GuardianMove.CHASE:
			var pull: float = clampf((distance - kind.keep_distance) / 58.0, -0.7, 1.0)
			velocity = velocity.lerp(
				inward * pull * kind.speed * omen_speed * (1.0 + 0.06 * float(_late_cycles())),
				kind.turn_rate * delta)
			if _guardian_left <= 0.0:
				_start_guardian_move(GuardianMove.CHARGE_WINDUP, GLYPH_WRITE_SECONDS)
				_guardian_move_haste = minf(_guardian_move_haste,
					maxf(GLYPH_WRITE_SECONDS / MIN_MARK_FUSE, 1.0))
				_write_glyphs()
			return inward

		GuardianMove.CHARGE_WINDUP:
			# Writing: it holds still while the circles fill.
			velocity = velocity.lerp(Vector2.ZERO, 9.0 * delta)
			if _guardian_left <= 0.0:
				_locked = _spiral_aim(inward, Volley.FIELD)
				_guardian_pattern = 1
				_start_guardian_move(GuardianMove.VOLLEY_WINDUP, GLYPH_RING_WINDUP)
			return inward

		GuardianMove.VOLLEY_WINDUP:
			velocity = velocity.lerp(Vector2.ZERO, 9.0 * delta)
			_set_telegraph(Telegraph.VOLLEY, _locked,
				1.0 - _guardian_left / _guardian_move_duration)
			if _guardian_left <= 0.0:
				_fire_field_volley()
				_after_volley(Volley.FIELD)
				_clear_telegraph()
				_start_guardian_move(GuardianMove.RECOVER, _glyph_recover_seconds())
			return _locked

		_:
			velocity = velocity.lerp(Vector2.ZERO, 8.0 * delta)
			if _guardian_left <= 0.0:
				_start_guardian_move(GuardianMove.CHASE, GLYPH_DRIFT_SECONDS)
			return inward


## The glyph circles: one where you stand and the rest spread round you, so the way out is a step
## and not a stand-still. More of them as the cycles go on.
func _write_glyphs() -> void:
	if _target == null:
		return
	var count: int = clampi(3 + (1 if guardian_cycle >= 5 else 0) + _late_cycles() / 3, 3, 5)
	var around: float = randf() * TAU
	for index in count:
		var at: Vector2 = _target.global_position
		if index > 0:
			at += Vector2.RIGHT.rotated(around + TAU * float(index - 1) / float(count - 1)) \
				* randf_range(58.0, 78.0)
		if _terrain_room != null and is_instance_valid(_terrain_room):
			at = _terrain_room.clamp_to_play(at)
		GroundBurst.mark(
			get_parent(), at, GLYPH_RADIUS, GLYPH_WRITE_SECONDS / _guardian_move_haste,
			kind.boss_accent, _target, _projectile_hit_handler)


func _glyph_recover_seconds() -> float:
	var shrink: float = 1.0 \
		- 0.07 * float(maxi(_tempo_cycle() - 1, 0)) \
		- 0.09 * float(_late_cycles())
	return GLYPH_RECOVER_SECONDS * clampf(shrink, 0.5, 1.0)


# --- What a volley fires, as lists of angles --------------------------------------------------
#
# The bolts and the picture of them are read from the same lists, because a warning that shows less than the
# volley fires is a lie, and this one told it: the wedge stayed at one width while a fan grew from five bolts to
# a dozen, and the gap drawn on a ring stayed at twelve spokes while the ring reached thirty.

## How much the volleys have grown: a step a cycle, and a step more for the grown-up form of a guardian.
func _volley_extra() -> int:
	var extra: int = maxi(guardian_cycle - 1, 0)
	if kind != null:
		extra += kind.guardian_volley_extra
	return extra


## The fans that follow the first of a sequence are spears: the windup is shorter and the bolts are faster, and
## a wedge the player has only just left has to be left again while still running.
func _fan_narrowing(index: int) -> float:
	if index <= 0:
		return 1.0
	return clampf(1.0 - 0.1 * float(guardian_cycle - 4), 0.8, 1.0)


## How many fans make one attack: the camp's two, the owl's two and the grown-up owl's three.
func _fans_in_run() -> int:
	if kind != null and kind.guardian_style == SpiritKind.GuardianStyle.GALE:
		return 1 + maxi(kind.guardian_combo, 1)
	return 2


## How wide a fan is. `index` is which fan of the sequence (the current one when left out).
func fan_span(index: int = -1) -> float:
	var which: int = _fan_index if index < 0 else index
	return minf(0.96 + 0.08 * float(_volley_extra()), FAN_MAX_SPAN) * _fan_narrowing(which)


## Aim fan. Higher cycles add bolts, not width.
func fan_angles(base: float, index: int = -1) -> Array[float]:
	var count: int = mini(5 + _volley_extra(), FAN_RUN_BOLTS / (_fans_in_run() + 1))
	var span: float = fan_span(index)
	var angles: Array[float] = []
	for i in count:
		var t: float = 0.0 if count == 1 else float(i) / float(count - 1)
		angles.append(base - span * 0.5 + span * t)
	return angles


## Cross puts the player between two lines: the aim falls between two arms whatever the count.
func cross_angles(base: float) -> Array[float]:
	var arms: int = mini(4 + mini(_volley_extra(), 4 + _late_cycles()), MAX_CROSS_ARMS)
	var angles: Array[float] = []
	for i in arms:
		angles.append(base + PI / float(arms) + TAU * float(i) / float(arms))
	return angles


## Radial leaves three spokes empty in front of the player; higher cycles shrink the gap to one.
func radial_angles(base: float) -> Array[float]:
	var extra: int = _volley_extra()
	var spokes: int = mini(12 + mini(extra * 2, 8 + _late_cycles() * 2), MAX_RADIAL_SPOKES)
	var hole: int = 2 if extra <= 0 else 1
	var angles: Array[float] = []
	for i in spokes:
		if i <= hole or i >= spokes - hole:
			continue
		angles.append(base + TAU * float(i) / float(spokes))
	# Room for the second ring too: what is dropped is the far side, behind the guardian, and never the
	# spokes that shape the way through.
	var room: int = MAX_VOLLEY_BOLTS - skew_ring_angles(base).size()
	while angles.size() > room:
		var farthest: int = 0
		for index in angles.size():
			if absf(wrapf(angles[index] - base, -PI, PI)) > absf(wrapf(angles[farthest] - base, -PI, PI)):
				farthest = index
		angles.remove_at(farthest)
	return angles


## From cycle 6 a second, slower ring follows the radial at a skewed angle. It has no gap; the way between
## two of its spokes is the way through.
func skew_ring_angles(base: float) -> Array[float]:
	var angles: Array[float] = []
	if guardian_cycle < 6:
		return angles
	var ring: int = mini(6 + _late_cycles(), MAX_SKEW_RING)
	var skew: float = TAU / float(ring) * 0.5
	for i in ring:
		angles.append(base + skew + TAU * float(i) / float(ring))
	return angles


## Shockwave ring after the charge combo. Fewer spokes than the field radial,
## same promise: the gap faces the player, so the dodge is to hold ground.
func forest_ring_angles(base: float) -> Array[float]:
	var extra: int = _volley_extra()
	var spokes: int = mini(8 + mini(extra, 4 + _late_cycles()), MAX_VOLLEY_BOLTS + 3)
	var hole: int = 2 if extra <= 0 else 1
	var angles: Array[float] = []
	for i in spokes:
		if i <= hole or i >= spokes - hole:
			continue
		angles.append(base + TAU * float(i) / float(spokes))
	return angles


## The way a bolt speeds up with the night.
func _bolt_scale() -> float:
	return minf(1.0 + 0.07 * float(_late_cycles()), MAX_BOLT_SCALE)


## Which volley this guardian winds up: the fans of camp and gale, the field's cross and radial (and the
## sentinel's ring), the forest's ring (and the toad's).
func _current_volley() -> int:
	if kind == null:
		return Volley.FOREST_RING
	match kind.guardian_style:
		SpiritKind.GuardianStyle.CAMP, SpiritKind.GuardianStyle.GALE:
			return Volley.CAMP_FAN
		SpiritKind.GuardianStyle.FIELD, SpiritKind.GuardianStyle.GLYPH:
			return Volley.FIELD
	return Volley.FOREST_RING


## What the warning on the floor shows for the volley being wound up, the way a player reads it:
## `kind` is fan, cross or ring; `base` the aim; `angles` every bolt of the volley and `slow` the slower second ring;
## `half` a fan's half-angle and `gap` the half-angle of the clear way facing the aim on a ring or a cross.
## The telegraph is drawn from this and the play bot reads it, so what is drawn, read and fired cannot differ.
func volley_shape() -> Dictionary:
	return volley_shape_for(_current_volley(), _telegraph_direction.angle(), _guardian_pattern, _fan_index)


## The same for any volley: the one being wound up, or the echo of one that has just been fired.
func volley_shape_for(volley: int, base: float, pattern: int, fan: int) -> Dictionary:
	var shape: Dictionary = {"kind": &"ring", "base": base, "angles": [] as Array[float],
		"slow": [] as Array[float], "half": 0.0, "gap": 0.0}
	match volley:
		Volley.CAMP_FAN:
			shape["kind"] = &"fan"
			shape["angles"] = fan_angles(base, fan)
			shape["half"] = fan_span(fan) * 0.5
			return shape
		Volley.FIELD:
			if pattern == 0:
				shape["kind"] = &"cross"
				shape["angles"] = cross_angles(base)
			else:
				shape["angles"] = radial_angles(base)
				shape["slow"] = skew_ring_angles(base)
		_:
			shape["angles"] = forest_ring_angles(base)
	var nearest: float = PI
	for group in [shape["angles"], shape["slow"]]:
		for angle in group:
			nearest = minf(nearest, absf(wrapf(float(angle) - base, -PI, PI)))
	shape["gap"] = nearest
	return shape


## Cross puts the player between two lines; radial leaves three spokes empty that way.
func _fire_field_volley() -> void:
	var base: float = _locked.angle()
	if _guardian_pattern == 0:
		for angle in cross_angles(base):
			_fire(Vector2.RIGHT.rotated(angle))
		return

	for angle in radial_angles(base):
		_fire(Vector2.RIGHT.rotated(angle))

	# From cycle 6 a second, slower ring follows at a skewed angle. It leaves the aim between two of its spokes
	# as well, so the way through is the same place, only narrower.
	for angle in skew_ring_angles(base):
		var bolt: Node2D = _fire(Vector2.RIGHT.rotated(angle))
		if bolt != null and bolt.has_method("set_speed_scale"):
			bolt.set_speed_scale(0.72)


func _fire_forest_ring() -> void:
	for angle in forest_ring_angles(_locked.angle()):
		_fire(Vector2.RIGHT.rotated(angle))


func _fire_camp_fan() -> void:
	for angle in fan_angles(_locked.angle()):
		_fire(Vector2.RIGHT.rotated(angle))


## Fire one moonlight orb.
func _fire(direction: Vector2) -> Node2D:
	var tree: SceneTree = get_tree()
	var pending: int = int(tree.get_meta(PENDING_BOLT_META, 0))
	if tree.get_node_count_in_group("hostile_projectiles") + pending >= HOSTILE_BOLT_LIMIT:
		return null
	var bolt: Node2D = BOLT_SCENE.instantiate()
	bolt.set_direction(direction)
	bolt.set_target(_target)
	bolt.set_terrain_room(_terrain_room)
	bolt.set_hit_handler(_projectile_hit_handler)
	if kind != null and kind.behavior == SpiritKind.Behavior.GUARDIAN:
		bolt.set_speed_scale(_bolt_scale())
		bolt.set_range(VOLLEY_RANGE)
	# Count toward the cap even before entering the tree. Several casters in one physics tick
	# must not exceed 24 through the deferred-add gap.
	tree.set_meta(PENDING_BOLT_META, pending + 1)
	bolt.reserve_slot()
	# Attach to the arena. The orb must keep flying even if the spirit dies.
	# Inside this node's `_physics_process`. Defer the attach to the next frame.
	get_parent().add_child.call_deferred(bolt)
	bolt.global_position = global_position + Vector2(0, -6)
	return bolt


func set_projectile_hit_handler(handler: Callable) -> void:
	_projectile_hit_handler = handler


func _set_telegraph(kind_value: Telegraph, direction: Vector2, ratio: float) -> void:
	_telegraph = kind_value
	_telegraph_direction = direction.normalized()
	_telegraph_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()


func _clear_telegraph() -> void:
	if _telegraph == Telegraph.NONE:
		return
	_telegraph = Telegraph.NONE
	_telegraph_ratio = 0.0
	queue_redraw()


## Action telegraphs do not use Sprite.modulate. Hit white and elite gold already share that
## property, so draw separate lines so the three signals do not erase each other.
func _draw() -> void:
	if kind != null and kind.behavior == SpiritKind.Behavior.GUARDIAN:
		_draw_guardian_silhouette()
		_draw_mutation_marks()

	match _telegraph:
		Telegraph.AIM:
			var lanes: Array[float] = aim_angles()
			if lanes.size() > 1:
				TelegraphArt.aim_fan(self, Vector2(0, -_local(6.0)), lanes, _local(aim_reach()),
					_telegraph_ratio, _telegraph_accent(), _local(1.0))
			else:
				TelegraphArt.aim(self, Vector2(0, -_local(6.0)), _telegraph_direction, _local(aim_reach()),
					_telegraph_ratio, _telegraph_accent(), _local(1.0))
		Telegraph.CHARGE:
			_draw_forest_corridor()
		Telegraph.VOLLEY:
			_draw_volley(volley_shape(), _telegraph_ratio)
			# An Echo is only fair if it can be planned for: the repeat is drawn beside the volley, fainter.
			var preview: Dictionary = echo_preview_shape()
			if not preview.is_empty():
				_draw_volley(preview, _telegraph_ratio, 0.4)
	# Winter Bell: a small ring of frost where it stands, fading as the chill runs out.
	if _chill_left > 0.0:
		var fade: float = clampf(_chill_left / 0.6, 0.0, 1.0)
		TelegraphArt.glow_ring(self, Vector2(0, -2), 9.0, Color(0.72, 0.92, 1.0, 1.0),
			0.6 * fade, 1.0, 0.7)


## What a guardian's body says beyond its picture. The drawn overlays that once split the three
## silhouettes (crown, wings, plates) are gone: the art carries its own silhouette now, and the outlines
## on top of it read as a debug layer. Two cues that the fight depends on remain, painted as light.
func _draw_guardian_silhouette() -> void:
	var accent: Color = _telegraph_accent()
	if kind.guardian_style == SpiritKind.GuardianStyle.CAMP:
		# A hit on the closed plates: a quick pale ring where the stone took it.
		if _camp_guard_flash > 0.0:
			TelegraphArt.glow_ring(self, Vector2(0, -20), 26.0 + 8.0 * (1.0 - _camp_guard_flash),
				Color(1.0, 0.96, 0.85, 1.0), _camp_guard_flash, 1.6, 0.9)
	# While it rests, a mint glow: this is the window to dive in. The forest and field guardians never
	# had one, and keep their look; every style that came with a marked rest says it the same way.
	if _guardian_move == GuardianMove.RECOVER and kind.guardian_style != SpiritKind.GuardianStyle.FOREST \
			and kind.guardian_style != SpiritKind.GuardianStyle.FIELD:
		var breathe: float = 0.5 + 0.5 * sin(TelegraphArt.clock() * 5.0)
		TelegraphArt.soft_disc(self, Vector2(0, -18), 24.0, TelegraphArt.SAFE,
			0.42 + 0.22 * breathe, 0.9)
		TelegraphArt.glow_ring(self, Vector2(0, -18), 16.0 + 2.0 * breathe,
			TelegraphArt.SAFE, 0.9, 1.4, 0.9)
	_draw_guardian_damage_pressure(accent)


## Moonlight past the budget is still damage that already landed. Show remaining pressure as a
## blue outline so a health bar that drains over seconds does not make the weapon feel useless.
func _draw_guardian_damage_pressure(accent: Color) -> void:
	if _guardian_deferred_damage < 1.0:
		return
	var ratio: float = clampf(
		_guardian_deferred_damage / maxf(float(_guardian_full_health), 1.0),
		0.0, 1.0)
	var arc_ratio: float = maxf(ratio, 0.08)
	var pressure_color := Color(0.62, 0.9, 1.0, 0.28 + ratio * 0.5)
	var steps: int = maxi(8, ceili(32.0 * arc_ratio))
	# A soft under-glow, then the bright arc: it reads as light held back, not as a drawn line.
	draw_arc(Vector2(0, -19), 38.0, -PI * 0.5, -PI * 0.5 + TAU * arc_ratio, steps,
		Color(pressure_color.r, pressure_color.g, pressure_color.b, pressure_color.a * 0.3),
		5.0 + ratio * 3.0, false)
	draw_arc(Vector2(0, -19), 38.0, -PI * 0.5, -PI * 0.5 + TAU * arc_ratio, steps,
		pressure_color, 1.6 + ratio * 1.8, false)
	if ratio > 0.0:
		_draw_glint(accent)


## A single bright mote at the end of the pressure arc, so it reads as flowing.
func _draw_glint(accent: Color) -> void:
	var ratio: float = clampf(
		_guardian_deferred_damage / maxf(float(_guardian_full_health), 1.0), 0.08, 1.0)
	var at: Vector2 = Vector2(0, -19) + Vector2.RIGHT.rotated(-PI * 0.5 + TAU * ratio) * 38.0
	draw_circle(at, 2.6, Color(accent.r, accent.g, accent.b, 0.25))
	draw_circle(at, 1.3, Color(1.0, 1.0, 1.0, 0.9))


func _boss_color(alpha: float, strength: float = 1.0) -> Color:
	return Color(
		kind.boss_accent.r * strength,
		kind.boss_accent.g * strength,
		kind.boss_accent.b * strength,
		alpha)


## The accent colour of this guardian, brightened, for the rim of whatever it is about to do.
func _telegraph_accent() -> Color:
	return kind.boss_accent if kind != null else Color(0.8, 0.9, 1.0, 1.0)


## World pixels to this node's local units. The guardian is drawn scaled, and a telegraph promises
## distances in the world, so it converts rather than hoping the two agree.
func _local(world_length: float) -> float:
	return world_length / maxf(absf(global_scale.x), 0.05)


## Charge: the lane it will run, exactly as long and as wide as the charge really is.
func _draw_forest_corridor() -> void:
	var seconds: float = GALE_DIVE_SECONDS \
		if kind.guardian_style == SpiritKind.GuardianStyle.GALE else FOREST_CHARGE_SECONDS
	var travel: float = kind.charge_speed * seconds * (1.0 + 0.06 * float(_late_cycles()))
	# Reach plus the body's own radius; a longer lane would say safe ground is dangerous.
	var length: float = _local(travel) + 11.0
	var half_width: float = _local(CONTACT_RADIUS * absf(global_scale.x) + PLAYER_BODY_RADIUS + 1.5)
	TelegraphArt.charge(self, Vector2(0, -6), _telegraph_direction, length, half_width,
		_telegraph_ratio, _telegraph_accent())


## A volley, drawn from the very angles it fires along: an aimed fan as wide as the fan really is, or a ring of
## bolts out in every direction with the way through them as wide as it really is.
func _draw_volley(shape: Dictionary, ratio: float, strength: float = 1.0) -> void:
	# The bolts fly in world pixels and leave six above the guardian's feet; a guardian's body is scaled, so
	# what is drawn here is converted, or the picture would reach only as far as the body is large.
	var origin: Vector2 = Vector2(0, -_local(6.0))
	if StringName(shape["kind"]) == &"fan":
		TelegraphArt.fan(self, origin, float(shape["base"]), float(shape["half"]) + 0.06,
			_local(FAN_DRAW_REACH), mini((shape["angles"] as Array).size(), 9), ratio, _telegraph_accent(),
			strength, _local(1.0))
		return
	var spokes: Array = (shape["angles"] as Array).duplicate()
	spokes.append_array(shape["slow"] as Array)
	# The gap is the way between the aim and the nearest spoke, less the width of a bolt where a player stands.
	var gap: float = maxf(float(shape["gap"]) - 0.09, 0.12)
	TelegraphArt.nova(self, origin, float(shape["base"]), spokes, gap, ratio,
		_telegraph_accent(), _local(RING_DRAW_REACH), strength, _local(1.0))


## The repeat that the volley being wound up will bring, where it will go: empty unless there is one. It is drawn
## beside the volley while it winds up, and the play bot reads it, so an Echo can be planned for and not only survived.
func echo_preview_shape() -> Dictionary:
	if _telegraph != Telegraph.VOLLEY or _echoing or not has_mutation(Expedition.Mutation.ECHO) \
			or not _echoes_this_volley():
		return {}
	return volley_shape_for(_current_volley(), _telegraph_direction.angle() + ECHO_TURN, _guardian_pattern, _fan_index)


## Only the last of a run of fans repeats: the owl's three fans and the camp's two are one attack, and it repeats once.
func _echoes_this_volley() -> bool:
	return _current_volley() != Volley.CAMP_FAN or _guardian_combo_left <= 0


## The directions a caster's next fan will fly, seen from where it is aiming: one for a plain shot, a fan of them for a
## caster with a barrage. The picture and the play bot both take the lanes from here.
func aim_angles() -> Array[float]:
	var base: float = _telegraph_direction.angle()
	var angles: Array[float] = []
	if kind == null or kind.behavior != SpiritKind.Behavior.SHOOT or kind.barrage != SpiritKind.Barrage.AIMED \
			or _bullet_field() == null:
		angles.append(base)
		return angles
	var count: int = _caster_fan_count()
	var spread: float = _caster_fan_spread()
	for index in count:
		angles.append(base + spread * (0.0 if count == 1 else float(index) / float(count - 1) - 0.5))
	return angles


func _caster_fan_count() -> int:
	return kind.barrage_count + (2 if mob_cycle >= 3 else 0)


func _caster_fan_spread() -> float:
	return kind.barrage_spread * (1.0 + 0.3 * float(_caster_fan_count() - kind.barrage_count))


## How far a single aimed shot is drawn: to the player and past, because the bolt does not stop there.
func aim_reach() -> float:
	if _target == null or not is_instance_valid(_target):
		return AIM_MIN_REACH
	return clampf(global_position.distance_to(_target.global_position) + 40.0, AIM_MIN_REACH, AIM_MAX_REACH)


func _face(direction: Vector2) -> void:
	if direction.length_squared() < 0.0001:
		return
	# Per-state guardian sheets have no facing. If `_face()` replays float_down every AI tick,
	# windup, charge, and open animations snap back to frame 0.
	if kind.behavior == SpiritKind.Behavior.GUARDIAN \
			and _guardian_move != GuardianMove.CHASE \
			and _sprite.animation in [
				GUARDIAN_WINDUP_ANIM,
				GUARDIAN_ALT_WINDUP_ANIM,
				GUARDIAN_CHARGE_ANIM,
				GUARDIAN_RECOVER_ANIM,
			]:
		return
	var index: int
	if absf(direction.x) > absf(direction.y):
		index = 3 if direction.x > 0.0 else 2
	else:
		index = 0 if direction.y > 0.0 else 1
	# Kinds with one facing (guardians) show the same art whichever way they look.
	#
	# **Prebuild the names.** `&"float_" + FACING_NAMES[i]` concatenates and makes a new
	# StringName every call. Forty spirits at 30 ticks/s is 1,200 allocations, most of them
	# discarded because the animation did not change.
	var wanted: StringName = FLOAT_NAMES[mini(index, maxi(kind.facings, 1) - 1)]
	if _sprite.animation != wanted:
		_sprite.play(wanted)


## While overlapping, hit on each cooldown.
##
## `body_entered` fires **only on enter.** If a spirit keeps overlapping while shoving the
## player, a second signal never comes.
## On device, one hit in 24 seconds and then nothing.
## Just move the position.
##
## **Do not use `move_and_slide()`.** Hundreds of decor pieces have no collision; a dozen
## structures share Room's circle list with the player. Spirits slide along structure rims
## without alone tunneling or issuing forty physics-server queries.
## Push away from other nearby spirits.
##
## Do not separate during a telegraphed charge. That path is a promise to the player —
## if a neighbor bends it, there is no way to dodge.
func _apply_separation(ai_delta: float) -> void:
	if not _can_steer_around_terrain():
		return
	var mine: float = SEPARATION_RADIUS * maxf(absf(global_scale.x), 1.0)
	var push: Vector2 = Vector2.ZERO
	for other in get_tree().get_nodes_in_group(&"spirits"):
		var body: Node2D = other as Node2D
		if body == null or body == self or not is_instance_valid(body):
			continue
		var reach: float = (mine + SEPARATION_RADIUS
			* maxf(absf(body.global_scale.x), 1.0)) * 0.5
		var away: Vector2 = global_position - body.global_position
		var gap: float = away.length()
		if gap >= reach:
			continue
		if gap < 0.5:
			# Fully overlapped. Cannot divide by zero, so pick a direction from the slot index.
			# Random would make the same run unreproducible.
			away = Vector2.RIGHT.rotated(float(get_index()) * 1.107)
			gap = 0.5
		push += away / gap * (1.0 - gap / reach)
	if push == Vector2.ZERO:
		return
	velocity += push * SEPARATION_PUSH * ai_delta


## Winter Bell: slow this spirit by `fraction` for `seconds`. A guardian feels a third of it, so the
## bell never turns a boss fight into a walk, and a spirit already slowed keeps the stronger and longer.
func chill(fraction: float, seconds: float) -> void:
	if _perishing:
		return
	var felt: float = clampf(fraction, 0.0, 0.8)
	if kind != null and kind.behavior == SpiritKind.Behavior.GUARDIAN:
		felt *= 0.35
	_chill_slow = maxf(_chill_slow if _chill_left > 0.0 else 0.0, felt)
	_chill_left = maxf(_chill_left, seconds)
	queue_redraw()


func is_chilled() -> bool:
	return _chill_left > 0.0


func _glide(delta: float, steer_around: bool) -> void:
	var motion: Vector2 = velocity * delta
	if _chill_left > 0.0:
		motion *= 1.0 - _chill_slow
	if _terrain_room != null and is_instance_valid(_terrain_room):
		position = _terrain_room.resolve_terrain_motion(
			position, motion, terrain_radius(), steer_around)
	else:
		position += motion


## While knocked or on a telegraphed charge, do not bend the path arbitrarily.
## Only chase / keep-distance AI break head-on circle deadlocks with tangent motion.
func _can_steer_around_terrain() -> bool:
	if _stagger_left > 0.0:
		return false
	if kind.behavior == SpiritKind.Behavior.CHARGE:
		return not (_beat <= 0.0 and _beat > -kind.charge_seconds)
	if kind.behavior == SpiritKind.Behavior.GUARDIAN:
		return _guardian_move != GuardianMove.CHARGE
	return true


func _try_hit() -> void:
	if _cooldown > 0.0:
		return
	if not _materialized or _target == null or not is_instance_valid(_target):
		return
	# Compute the old Area2D circle centers and global scales as-is. Elites and guardians that
	# grew larger get a contact range that grew with the scene collider they used to have.
	var spirit_center: Vector2 = to_global(CONTACT_OFFSET)
	var player_center: Vector2 = _target.to_global(PLAYER_BODY_OFFSET)
	var spirit_scale: float = maxf(absf(global_scale.x), absf(global_scale.y))
	var player_scale: float = maxf(
		absf(_target.global_scale.x), absf(_target.global_scale.y))
	var reach: float = CONTACT_RADIUS * spirit_scale + PLAYER_BODY_RADIUS * player_scale
	if spirit_center.distance_squared_to(player_center) > reach * reach:
		return
	_cooldown = HIT_COOLDOWN
	touched_player.emit(global_position)
