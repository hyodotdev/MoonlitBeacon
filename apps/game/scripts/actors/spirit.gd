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
## Fired when materialize finishes. Arena shakes the screen for guardians only;
## trash landing every second must not rattle the camera.
signal landed()

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
## Guardian landing ring after materialize. A boss should hit the ground,
## not fade in like trash.
const SLAM_SECONDS: float = 0.4

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
## Time until the field guardian's next aimed bolt while strafing.
## Starts half-ready so the opening strafe pokes once, never on frame one.
var _guardian_poke_left: float = FIELD_POKE_INTERVAL * 0.5
## Short white edge flash when camp armor blocks damage.
var _camp_guard_flash: float = 0.0
## Guardian landing-ring time left. Trash never sets this.
var _slam_left: float = 0.0
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

## Elite. Bigger, brighter, triple tough. Always drops dew when killed.
var elite: bool = false
## Cycle read by guardian patterns. Arena sets this on spawn.
var guardian_cycle: int = 1


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
	return not _perishing and _materialized


## Hit by the moonlight blade. Arena calls this.
##
## Normal spirits read hits as white flash · knockback · hitch · perish. Guardians only take
## flash and perish. If auto-weapons keep overwriting guardian stagger, stronger builds
## paradoxically stop the boss from attacking.
func take_damage(amount: int, from_position: Vector2) -> void:
	if _perishing:
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

	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	# A boss bursts bigger than trash. Same fade length, wider pop.
	var burst: float = 1.6 \
		if kind != null and kind.behavior == SpiritKind.Behavior.GUARDIAN \
		else 1.35
	var out: Tween = create_tween()
	out.set_parallel(true)
	out.tween_property(self, "modulate:a", 0.0, PERISH_SECONDS)
	out.tween_property(self, "scale", scale * burst, PERISH_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	out.chain().tween_callback(queue_free)


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
	_finish_materialize()


## End of the appear fade, split out so tests can land a spirit without frames.
func _finish_materialize() -> void:
	# Off the target list while appearing, but already-flying AoE can still call
	# `take_damage()` directly. When materialization ends, reopen the opening shock budget
	# so the first on-screen frame still leaves real seconds of fight.
	_reset_guardian_damage_budget()
	_materialized = true
	if kind != null and kind.behavior == SpiritKind.Behavior.GUARDIAN:
		_slam_left = SLAM_SECONDS
		queue_redraw()
	landed.emit()


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
	if _slam_left > 0.0:
		_slam_left = maxf(_slam_left - delta, 0.0)
		queue_redraw()

	# Do nothing while perishing. The tween frees itself when done.
	if _perishing:
		return

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
			velocity = velocity.lerp(wish * kind.speed, kind.turn_rate * ai_delta)

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
	velocity = velocity.lerp(wish * kind.speed + inward * closing, kind.turn_rate * delta)
	return wish


## Keep distance and fire moonlight.
##
## Retreats when close, so it **rarely enters auto-attack range.**
## Dash in to catch it — the first real use for dash.
func _do_shoot(delta: float, to_player: Vector2) -> Vector2:
	var distance: float = to_player.length()
	var inward: Vector2 = to_player.normalized()

	# Retreat if too close; approach if too far.
	var pull: float = clampf((distance - kind.keep_distance) / 50.0, -1.0, 1.0)
	velocity = velocity.lerp(inward * pull * kind.speed, kind.turn_rate * delta)

	_beat -= delta
	if _locked != Vector2.ZERO:
		# Lock to the direction at telegraph start. Retargeting to the end makes it undodgeable.
		_set_telegraph(Telegraph.AIM, _locked,
			clampf(-_beat / CASTER_WINDUP, 0.0, 1.0))
		if _beat <= -CASTER_WINDUP:
			_fire(_locked)
			_locked = Vector2.ZERO
			_beat = kind.shoot_interval
			_clear_telegraph()
	elif _beat <= 0.0:
		_locked = inward
		_beat = 0.0
	return inward


## Hand each terrain guardian a fully different combat grammar.
func _do_guardian(delta: float, to_player: Vector2) -> Vector2:
	match kind.guardian_style:
		SpiritKind.GuardianStyle.FIELD:
			return _do_guardian_field(delta, to_player)
		SpiritKind.GuardianStyle.CAMP:
			return _do_guardian_camp(delta, to_player)
		_:
			return _do_guardian_forest(delta, to_player)


func _guardian_opening_seconds() -> float:
	match kind.guardian_style:
		SpiritKind.GuardianStyle.FIELD:
			return FIELD_STRAFE_SECONDS
		SpiritKind.GuardianStyle.CAMP:
			return CAMP_APPROACH_SECONDS
		_:
			return FOREST_CHASE_SECONDS


func _late_cycles() -> int:
	return maxi(guardian_cycle - 3, 0)


func _guardian_haste() -> float:
	# Cycles 1–3 add 10% each. From cycle 4, telegraphs and gaps shrink faster and hit pressure rises.
	var cycle_haste: float = 1.0 \
		+ 0.10 * float(maxi(guardian_cycle - 1, 0)) \
		+ 0.12 * float(_late_cycles())
	var enrage_at: float = 0.45 if guardian_cycle >= 5 else 0.3
	var enrage: float = 1.28 if guardian_cycle >= 5 else 1.15
	var low: float = enrage if get_health_ratio() <= enrage_at else 1.0
	return cycle_haste * low


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
		- 0.10 * float(maxi(guardian_cycle - 1, 0)) \
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


func _start_guardian_move(move: GuardianMove, seconds: float) -> void:
	_guardian_move = move
	_guardian_left = seconds
	_guardian_move_duration = maxf(seconds, 0.001)
	# Crossing the 30% HP boundary mid-state still waits until the next state to change speed.
	# That way telegraph and state sheet finish on one beat.
	_guardian_move_haste = _guardian_haste()
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
				inward * kind.speed * (1.0 + 0.06 * float(_late_cycles())),
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
					_locked = inward
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
				_locked = inward
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
		wish * kind.speed * (1.0 + 0.06 * float(_late_cycles())),
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
				inward * pull * kind.speed * (1.0 + 0.06 * float(_late_cycles())),
				kind.turn_rate * delta)
			if _guardian_left <= 0.0:
				_locked = inward
				_guardian_combo_left = 1
				_start_guardian_move(
					GuardianMove.VOLLEY_WINDUP, CAMP_VOLLEY_WINDUP)
			return inward

		GuardianMove.VOLLEY_WINDUP:
			velocity = velocity.lerp(Vector2.ZERO, 9.0 * delta)
			_set_telegraph(Telegraph.VOLLEY, _locked,
				1.0 - _guardian_left / _guardian_move_duration)
			if _guardian_left <= 0.0:
				_fire_camp_fan()
				_clear_telegraph()
				if _guardian_combo_left > 0:
					_guardian_combo_left -= 1
					_locked = inward
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


## Cross puts the player between two lines; radial leaves three spokes empty that way.
func _fire_field_volley() -> void:
	var base: float = _locked.angle()
	var extra: int = maxi(guardian_cycle - 1, 0)
	if kind != null:
		extra += kind.guardian_volley_extra
	if _guardian_pattern == 0:
		var arms: int = 4 + mini(extra, 4 + _late_cycles())
		for i in arms:
			_fire(Vector2.RIGHT.rotated(
				base + PI * 0.25 + TAU * float(i) / float(arms)))
		return

	var spokes: int = 12 + mini(extra * 2, 8 + _late_cycles() * 2)
	for i in spokes:
		# Leave a few spokes clear in front of the player. Higher cycles shrink the gap to one.
		var hole: int = 2 if extra <= 0 else 1
		if i <= hole or i >= spokes - hole:
			continue
		_fire(Vector2.RIGHT.rotated(base + TAU * float(i) / float(spokes)))

	# From cycle 6 a second ring follows at a skewed angle. Standing still dodges the first
	# and still takes the second — after dodging you must **move** to live.
	if guardian_cycle < 6:
		return
	var ring: int = mini(6 + _late_cycles(), 14)
	var skew: float = TAU / float(ring) * 0.5
	for i in ring:
		var shot: Vector2 = Vector2.RIGHT.rotated(
			base + skew + TAU * float(i) / float(ring))
		var bolt: Node2D = _fire(shot)
		if bolt != null and bolt.has_method("set_speed_scale"):
			bolt.set_speed_scale(0.72)


## Shockwave ring after the charge combo. Fewer spokes than the field radial,
## same promise: the gap faces the player, so the dodge is to hold ground.
func _fire_forest_ring() -> void:
	var base: float = _locked.angle()
	var extra: int = maxi(guardian_cycle - 1, 0)
	if kind != null:
		extra += kind.guardian_volley_extra
	var spokes: int = 8 + mini(extra, 4 + _late_cycles())
	var hole: int = 2 if extra <= 0 else 1
	for i in spokes:
		if i <= hole or i >= spokes - hole:
			continue
		_fire(Vector2.RIGHT.rotated(base + TAU * float(i) / float(spokes)))


## Aim fan. Higher cycles add spokes and narrow the safe lane.
func _fire_camp_fan() -> void:
	var base: float = _locked.angle()
	var extra: int = maxi(guardian_cycle - 1, 0)
	if kind != null:
		extra += kind.guardian_volley_extra
	var count: int = mini(5 + extra, 11 + _late_cycles())
	var span: float = 0.96 + 0.08 * float(extra)
	for i in count:
		var t: float = 0.0 if count == 1 else float(i) / float(count - 1)
		var spread: float = -span * 0.5 + span * t
		_fire(Vector2.RIGHT.rotated(base + spread))


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
		bolt.set_speed_scale(1.0 + 0.07 * float(_late_cycles()))
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
	if _slam_left > 0.0:
		_draw_slam_ring()
	if kind != null and kind.behavior == SpiritKind.Behavior.GUARDIAN \
			and _guardian_move == GuardianMove.CHARGE:
		_draw_charge_streaks()

	match _telegraph:
		Telegraph.AIM:
			var aim: Vector2 = _telegraph_direction * 118.0
			draw_line(Vector2(0, -6), aim + Vector2(0, -6),
				Color(0.76, 0.46, 1.0, 0.28 + 0.5 * _telegraph_ratio),
				1.0 + 1.4 * _telegraph_ratio)
		Telegraph.CHARGE:
			_draw_forest_corridor()
		Telegraph.VOLLEY:
			if kind.guardian_style == SpiritKind.GuardianStyle.CAMP:
				_draw_camp_fan_telegraph()
			else:
				_draw_field_volley_telegraph()


## Landing ring. Expands and thins in the boss accent, then gone in 0.4s.
func _draw_slam_ring() -> void:
	var t: float = 1.0 - _slam_left / SLAM_SECONDS
	var radius: float = 12.0 + 46.0 * t
	draw_arc(Vector2(0, -6), radius, 0.0, TAU, 40,
		_boss_color(0.85 * (1.0 - t), 1.9),
		0.6 + 2.2 * (1.0 - t), false)


## Charge streaks. Three speed lines trail the rushing boss so the corridor
## telegraph's promise reads in motion too.
func _draw_charge_streaks() -> void:
	if _locked.length_squared() < 0.001:
		return
	var back: Vector2 = -_locked.normalized()
	var side := Vector2(-back.y, back.x)
	for i in [-1.0, 0.0, 1.0]:
		var off: Vector2 = side * (i * 9.0) + Vector2(0, -6)
		draw_line(off + back * 6.0, off + back * 30.0,
			_boss_color(0.5, 1.7), 2.4 - absf(i) * 0.7)


## Procedurally add crown, wings, and armor on the same 50px sheet so silhouettes split first.
## No extra sprites or nodes — one scene even when the boss changes.
func _draw_guardian_silhouette() -> void:
	var accent: Color = _boss_color(0.82, 1.9)
	var dim: Color = _boss_color(0.30, 1.25)
	match kind.guardian_style:
		SpiritKind.GuardianStyle.FIELD:
			var left_wing := PackedVector2Array([
				Vector2(-17, -33), Vector2(-34, -42), Vector2(-29, -27),
				Vector2(-42, -19), Vector2(-20, -15),
			])
			var right_wing := PackedVector2Array([
				Vector2(17, -33), Vector2(34, -42), Vector2(29, -27),
				Vector2(42, -19), Vector2(20, -15),
			])
			draw_colored_polygon(left_wing, dim)
			draw_colored_polygon(right_wing, dim)
			draw_polyline(left_wing, accent, 2.0, false)
			draw_polyline(right_wing, accent, 2.0, false)
			draw_arc(Vector2(0, -20), 29.0, PI * 1.08, PI * 1.92, 18,
				accent, 2.2, false)

		SpiritKind.GuardianStyle.CAMP:
			var opened: float = 7.0 if _guardian_move == GuardianMove.RECOVER else 0.0
			var plate_edge: Color = Color(2.4, 2.4, 2.0, 0.96) \
				if _camp_guard_flash > 0.0 else accent
			var left_plate := PackedVector2Array([
				Vector2(-18 - opened, -38), Vector2(-35 - opened, -33),
				Vector2(-38 - opened, -5), Vector2(-23 - opened, 3),
				Vector2(-19 - opened, -12),
			])
			var right_plate := PackedVector2Array([
				Vector2(18 + opened, -38), Vector2(35 + opened, -33),
				Vector2(38 + opened, -5), Vector2(23 + opened, 3),
				Vector2(19 + opened, -12),
			])
			draw_colored_polygon(left_plate, dim)
			draw_colored_polygon(right_plate, dim)
			draw_polyline(left_plate, plate_edge,
				2.4 + 1.4 * _camp_guard_flash, false)
			draw_polyline(right_plate, plate_edge,
				2.4 + 1.4 * _camp_guard_flash, false)
			draw_polyline(PackedVector2Array([
				Vector2(-14, -42), Vector2(-8, -50), Vector2(0, -44),
				Vector2(8, -50), Vector2(14, -42),
			]), accent, 2.5, false)
			if _guardian_move == GuardianMove.RECOVER:
				# The teal open core marks that this is the safe approach window.
				draw_arc(Vector2(0, -18), 14.0, 0.0, TAU, 22,
					Color(0.42, 1.7, 1.05, 0.86), 3.0, false)
				draw_circle(Vector2(0, -18), 4.0,
					Color(0.72, 2.0, 1.35, 0.70))

		_:
			# Branch crown and shoulder horns. Keep them close to the body so they do not overlap the charge line.
			draw_polyline(PackedVector2Array([
				Vector2(-18, -34), Vector2(-24, -48), Vector2(-16, -44),
				Vector2(-12, -55), Vector2(-5, -45), Vector2(0, -53),
				Vector2(5, -45), Vector2(12, -55), Vector2(16, -44),
				Vector2(24, -48), Vector2(18, -34),
			]), accent, 2.5, false)
			draw_arc(Vector2(0, -19), 30.0, PI * 1.05, PI * 1.95, 18,
				dim, 3.4, false)

	_draw_guardian_damage_pressure()


## Moonlight past the budget is still damage that already landed. Show remaining pressure as a
## blue outline so a health bar that drains over seconds does not make the weapon feel useless.
func _draw_guardian_damage_pressure() -> void:
	if _guardian_deferred_damage < 1.0:
		return
	var ratio: float = clampf(
		_guardian_deferred_damage / maxf(float(_guardian_full_health), 1.0),
		0.0, 1.0)
	var arc_ratio: float = maxf(ratio, 0.08)
	var pressure_color := Color(
		0.52 + kind.boss_accent.r * 0.35,
		1.25 + kind.boss_accent.g * 0.35,
		1.85 + kind.boss_accent.b * 0.35,
		0.40 + ratio * 0.42)
	draw_arc(
		Vector2(0, -19),
		38.0,
		-PI * 0.5,
		-PI * 0.5 + TAU * arc_ratio,
		maxi(8, ceili(32.0 * arc_ratio)),
		pressure_color,
		1.8 + ratio * 2.2,
		false)


func _boss_color(alpha: float, strength: float = 1.0) -> Color:
	return Color(
		kind.boss_accent.r * strength,
		kind.boss_accent.g * strength,
		kind.boss_accent.b * strength,
		alpha)


## Forest charge telegraphs as a corridor with real width to dodge, not a thin line.
func _draw_forest_corridor() -> void:
	var origin := Vector2(0, -6)
	var direction: Vector2 = _telegraph_direction
	var side := Vector2(-direction.y, direction.x)
	# Paint only travel distance plus body radius. A longer corridor would lie that
	# safe ground is dangerous.
	var length: float = kind.charge_speed * FOREST_CHARGE_SECONDS \
		* (1.0 + 0.06 * float(_late_cycles())) + 11.0
	var half_width: float = 11.0 + 2.0 * _telegraph_ratio
	var end: Vector2 = origin + direction * length
	var corridor := PackedVector2Array([
		origin - side * half_width,
		end - side * half_width,
		end + side * half_width,
		origin + side * half_width,
	])
	draw_colored_polygon(corridor,
		Color(2.0, 0.20, 0.18, 0.08 + 0.12 * _telegraph_ratio))
	var outline := PackedVector2Array([
		corridor[0], corridor[1], corridor[2], corridor[3], corridor[0],
	])
	draw_polyline(outline,
		Color(2.2, 0.34, 0.26, 0.45 + 0.42 * _telegraph_ratio),
		1.3 + 1.5 * _telegraph_ratio, false)
	draw_line(origin, end,
		_boss_color(0.34 + 0.40 * _telegraph_ratio, 1.8),
		1.0 + 1.2 * _telegraph_ratio)
	draw_line(end - direction * 12.0 - side * 7.0, end, _boss_color(0.85, 2.0), 2.0)
	draw_line(end - direction * 12.0 + side * 7.0, end, _boss_color(0.85, 2.0), 2.0)


func _draw_field_volley_telegraph() -> void:
	var origin := Vector2(0, -6)
	var base: float = _telegraph_direction.angle()
	var danger := _boss_color(0.30 + 0.48 * _telegraph_ratio, 1.9)
	draw_arc(origin, 25.0 + 7.0 * _telegraph_ratio,
		0.0, TAU, 28, _boss_color(0.78, 1.8), 2.2, false)
	if _guardian_pattern == 0:
		for i in 4:
			var direction := Vector2.RIGHT.rotated(
				base + PI * 0.25 + PI * 0.5 * float(i))
			draw_line(origin, origin + direction * 66.0, danger, 1.8)
	else:
		for i in 12:
			if i == 0 or i == 1 or i == 11:
				continue
			var direction := Vector2.RIGHT.rotated(base + TAU * float(i) / 12.0)
			draw_line(origin, origin + direction * 60.0, danger, 1.5)

	# No real bolts fire between the two bright edges.
	var safe_half: float = 0.58 if _guardian_pattern == 0 else 0.82
	for sign_value in [-1.0, 1.0]:
		var edge := Vector2.RIGHT.rotated(base + safe_half * sign_value)
		draw_line(origin + edge * 22.0, origin + edge * 68.0,
			Color(0.55, 2.0, 1.35, 0.78), 2.2)
	draw_line(origin + _telegraph_direction * 28.0,
		origin + _telegraph_direction * 58.0,
		Color(0.65, 2.2, 1.5, 0.62), 2.8)


func _draw_camp_fan_telegraph() -> void:
	var origin := Vector2(0, -6)
	var base: float = _telegraph_direction.angle()
	var fan := PackedVector2Array([origin])
	const ARC_STEPS: int = 10
	for i in ARC_STEPS + 1:
		var angle: float = base - 0.54 + 1.08 * float(i) / float(ARC_STEPS)
		fan.append(origin + Vector2.RIGHT.rotated(angle) * 96.0)
	draw_colored_polygon(fan,
		Color(2.0, 0.58, 0.16, 0.06 + 0.12 * _telegraph_ratio))
	draw_arc(origin, 96.0, base - 0.54, base + 0.54, ARC_STEPS,
		Color(2.2, 0.72, 0.18, 0.48 + 0.38 * _telegraph_ratio),
		2.0, false)
	for i in 5:
		var spread: float = -0.48 + 0.24 * float(i)
		var direction := Vector2.RIGHT.rotated(base + spread)
		draw_line(origin, origin + direction * 92.0,
			Color(2.1, 0.62, 0.18, 0.30 + 0.5 * _telegraph_ratio),
			1.3 + 0.8 * _telegraph_ratio)


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


func _glide(delta: float, steer_around: bool) -> void:
	var motion: Vector2 = velocity * delta
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
