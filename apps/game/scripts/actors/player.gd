class_name Player
extends CharacterBody2D

## Player body for the chosen Moonlit Guardian.
##
## From Lesson 6, walks with the left floating stick. Lighting beacons is Lesson 7; dash is Lesson 12.
##
## The arena reads the stick. This only takes **"go this way."**
## That way Lesson 8 enemies reuse the same body (they have no stick), and Lesson 12 can
## layer dash without touching the input side.

## Facing. Matches the sprite-sheet column order.
enum Facing { DOWN, UP, LEFT, RIGHT }

## Walk speed. World pixels per second.
## Crosses the 4/3 camera's 606px visible width in about 6.3s. Fast enough to move between
## beacons without feeling stuck, not so fast the zoomed view feels rushed.
## Default walk speed. Relics raise it; restore falls back to this.
## Center for body-wrapping effects. Root (0,0) is **at the feet.**
##
## Top-down, so the sprite draws above the root. Orbs or ripples parented at the root
## sit the character on the circle's top rim and look like they stick out.
## Aim at body center and they sit inside the circle.
##
## Value was **measured on screen.** Sheet-coordinate math (-3) did not match reality —
## the first try, -24, overshot by 7px and left the toes hanging below.
## On a real device, body center and ring center were measured directly to -17.
## Better a measured value than trusting the math and missing twice.
const BODY_CENTER: Vector2 = Vector2(0.0, -17.0)

const DEFAULT_SPEED: float = 96.0
@export var speed: float = DEFAULT_SPEED

## Response when stopping and starting. Larger values slide more.
const ACCELERATION: float = 900.0
const FRICTION: float = 1200.0

## Slower than this counts as standing still.
const WALK_THRESHOLD: float = 4.0

## Dash — a short, fast slide. The way through a pack of spirits.
const DASH_SPEED: float = 320.0
const DASH_SECONDS: float = 0.19
## Until it can be used again. Too short and dash becomes the only movement.
const DEFAULT_DASH_COOLDOWN: float = 1.15
var dash_cooldown_time: float = DEFAULT_DASH_COOLDOWN
## Short moonlight speed lines left only at the dash start, not a full-body afterimage.
## Must end before the dash (0.19s) so it does not linger behind a stopped body.
const DASH_STREAK_SECONDS: float = 0.14
## Moonlight shockwave that spreads from the body on continue. Arena owns the clear hit;
## Player briefly shows the same radius so spending a coin reads immediately.
const CONTINUE_BURST_SECONDS: float = 0.72

## Knockback strength and duration on hit.
const KNOCKBACK_SPEED: float = 190.0
const KNOCKBACK_SECONDS: float = 0.18

## Moonlight blade — Lesson 17.
##
## **No extra button.** Both thumbs already cover the left and right halves of the screen,
## so there is nowhere for a new button. Close range fires on its own.
##
## Reach is 34, same as the beacon `REACH_RADIUS`. Matched on purpose, not by chance —
## once "beside you" was measured on screen, that distance is reused.
## Relics change it mid-run, so it is not a constant.
## Defaults stay under `DEFAULT_` — relics need a baseline to multiply.
const DEFAULT_ATTACK_RANGE: float = 34.0
const DEFAULT_ATTACK_COOLDOWN: float = 0.55
var attack_range: float = DEFAULT_ATTACK_RANGE
var attack_cooldown_time: float = DEFAULT_ATTACK_COOLDOWN
## Full-moon slash investment count. Does not change the slash hit; only tiered afterimages.
var slash_rank: int = 0
## Fan angle. Must **match** `ARC_DEGREES` in `tools/build_slash.py`.
## If visible range and hit range differ, you get "I touched it but it lived."
const DEFAULT_ATTACK_ARC: float = 110.0
var attack_arc: float = DEFAULT_ATTACK_ARC
## Slash animation currently playing. Killed when the next slash starts.
var _slash_play: Tween = null

## Base damage.
##
## **Scale of 1 lets multiplicative growth die to rounding.** `_scaled(1, 1.35)` stays 1, so
## the first Keen Moonlight stack did nothing (the second barely moved 1.82 → 2).
## At 10, 1.35× reads clearly each stack: 10 → 14 → 18 → 25.
## Spirit and guardian HP were scaled by the same factor — only the unit changed; balance is the same.
const DEFAULT_ATTACK_DAMAGE: int = 10
var attack_damage: int = DEFAULT_ATTACK_DAMAGE
## How long the blade stays up. The 3-frame art plays fully inside this window.
const SLASH_SECONDS: float = 0.18
## Blade appears this far from the body.
const SLASH_OFFSET: float = 13.0
## Body center. Feet are the origin, so the art sits this far above.
## The blade must orbit this point so it leaves at hand height, not at the feet.
const SLASH_PIVOT: Vector2 = Vector2(0, -6)
## Where the little guardian holds the beacon candle in both hands.
##
## Ranged attacks must start here so shots do not pop in outside the body, or look like
## they are fired from a prop held to the side.
const MOONLIGHT_ORIGIN: Vector2 = Vector2(0, -20)
const MOONLIGHT_CAST_SECONDS: float = MoonlightCast.CAST_SECONDS
## Hero art is already painted as if lit by moonlight. Undo the Player root night tint
## (0.315, 0.35, 0.57) on the sprite only so the face does not die into a purple blotch.
## Brightening the root overexposes Slash and MoonfireAura.
const HERO_READABILITY_TINT: Color = Color(3.175, 2.857, 1.754, 1)

## Bounds that keep the player inside the arena. Coordinates in the base resolution.
## Held inward of the dense tree edge.
##
## In Lesson 9, when the moonlight gate opens at the forest edge, play goes outside this rect.
## So it is a **mutable value**, not a constant (`set_bounds`).
const DEFAULT_BOUNDS: Rect2 = Rect2(96, 150, 616, 172)

var bounds: Rect2 = DEFAULT_BOUNDS
## Real structures of the current room. Arena passes a new Room when terrain changes.
var _terrain_room: Room = null

## When the gate opens, the player can go down this far. Empty means none.
##
## `bounds.merge()` into one rect drops **the whole bottom edge.** You walk into the tree belt
## from anywhere on screen, not only near the gate. That really happened.
var gate_path: Rect2 = Rect2()

const FACING_NAMES: Array[StringName] = [&"down", &"up", &"left", &"right"]

@export var facing: Facing = Facing.DOWN:
	set = _set_facing

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _moonlight_cast: MoonlightCast = $MoonlightCast
@onready var _ring: Node2D = $ChargeRing
@onready var _slash: Sprite2D = $Slash
@onready var _moonfire: Node2D = $MoonfireAura
@onready var _breathe: AnimationPlayer = $Breathe

var _walking: bool = false
var _attack_cooldown: float = 0.0
## Full-moon slash also shows the crescent on the far side so a full circle reads.
var _slash_back: Sprite2D = null
var _full_wave: float = -1.0
var _starfall_preview: float = -1.0
var _starfall_preview_count: int = 1
## One to three short fan afterimages left by an empowered slash.
var _slash_echo_wave: float = -1.0
var _slash_echo_angle: float = 0.0
var _slash_echo_half_arc: float = 0.0
var _slash_echo_reach: float = 0.0
## Desired direction this frame. Arena fills it every frame.
var _wish: Vector2 = Vector2.ZERO
var _knock_left: float = 0.0
var _dash_left: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_streak_left: float = 0.0
var _dash_streak_direction: Vector2 = Vector2.RIGHT
var _continue_burst_left: float = 0.0
var _continue_burst_radius: float = 0.0
var _stopped_for_result: bool = false
## Pure visual combat grammar for the chosen hero. Speed, damage, and hits are separate
## Arena fields; these values tint cast light, blade light, and dash speed lines only.
var _hero_profile: Hero.AttackProfile = Hero.AttackProfile.WARDEN
var _hero_vfx_tier: int = 0
var _hero_primary: Color = Color(0.3, 0.68, 1.0, 1.0)
var _hero_secondary: Color = Color(0.82, 0.95, 1.0, 1.0)
## In a debug session capturing the facing matrix, keep real move/dash but hide cast light,
## ring, and speed lines that cover the silhouette. Release rejects the setter.
var _debug_direction_capture_vfx_suppressed: bool = false


func _ready() -> void:
	# Final heroes already have 4-frame idle, so full-body offset animation is unnecessary.
	# Even at 4× scale a 1px Breathe is a 4px jump, so pin the Sprite baseline.
	_breathe.stop()
	_sprite.offset = Vector2(0.0, -8.0)
	_set_facing(facing)
	_slash.visible = false
	_slash_back = _slash.duplicate() as Sprite2D
	_slash_back.name = "FullMoonBack"
	_slash_back.visible = false
	_slash_back.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_slash_back)


## Build eight animations from the chosen hero's sheets.
##
## If the resource is empty or the sheet is smaller than declared cells, return false and
## keep the Player scene's default animations. One missing custom asset must not make the
## character invisible or stop the run.
func apply_hero_visual(hero: Hero) -> bool:
	if hero == null or _sprite == null:
		return false
	var frames: SpriteFrames = _build_hero_frames(hero)
	if frames == null:
		return false
	_hero_profile = hero.attack_profile
	_hero_vfx_tier = clampi(hero.vfx_tier, 0, 5)
	_hero_primary = hero.projectile_primary
	_hero_secondary = hero.projectile_secondary
	_moonlight_cast.configure_profile(
		_hero_profile, _hero_primary, _hero_secondary, _hero_vfx_tier)
	_sprite.sprite_frames = frames
	_sprite.self_modulate = HERO_READABILITY_TINT
	# Custom cells larger than the default 16px still keep feet at the same world point.
	# Sprite offset stays -8, so only raise the node by half the extra height.
	# A 32px cell then is position -8 + offset -8 = center -16, so the bottom edge is at 0.
	_sprite.position.y = -float(maxi(hero.sprite_cell.y - 16, 0)) * 0.5
	_play_current()
	return true


func attack_profile_id() -> int:
	return int(_hero_profile)


func hero_vfx_tier() -> int:
	return _hero_vfx_tier


func _build_hero_frames(hero: Hero) -> SpriteFrames:
	if hero.walk_sheet == null or hero.idle_sheet == null:
		return null
	if hero.sprite_cell.x <= 0 or hero.sprite_cell.y <= 0:
		return null
	if hero.walk_frames <= 0 or hero.idle_frames <= 0:
		return null

	var directions: int = FACING_NAMES.size()
	var required_width: int = hero.sprite_cell.x * directions
	var required_walk_height: int = hero.sprite_cell.y * hero.walk_frames
	var required_idle_height: int = hero.sprite_cell.y * hero.idle_frames
	var walk_size: Vector2 = hero.walk_sheet.get_size()
	var idle_size: Vector2 = hero.idle_sheet.get_size()
	if walk_size.x < required_width or walk_size.y < required_walk_height:
		return null
	if idle_size.x < required_width or idle_size.y < required_idle_height:
		return null

	var result := SpriteFrames.new()
	result.remove_animation(&"default")
	for direction in directions:
		_add_sheet_animation(result, &"walk_" + FACING_NAMES[direction],
			hero.walk_sheet, direction, hero.walk_frames,
			hero.sprite_cell, hero.walk_fps)
		_add_sheet_animation(result, &"idle_" + FACING_NAMES[direction],
			hero.idle_sheet, direction, hero.idle_frames,
			hero.sprite_cell, hero.idle_fps)
	return result


func _add_sheet_animation(
		frames: SpriteFrames,
		animation: StringName,
		sheet: Texture2D,
		direction: int,
		frame_count: int,
		cell: Vector2i,
		fps: float,
	) -> void:
	frames.add_animation(animation)
	frames.set_animation_loop(animation, true)
	frames.set_animation_speed(animation, maxf(fps, 1.0))
	for frame_index in frame_count:
		var texture := AtlasTexture.new()
		texture.atlas = sheet
		texture.region = Rect2(
			direction * cell.x, frame_index * cell.y, cell.x, cell.y)
		frames.add_frame(animation, texture)


## Can the moonlight blade fire right now.
func can_attack() -> bool:
	return _attack_cooldown <= 0.0


## Slash this way. Arena finds the nearest spirit and calls this.
##
## **The player does not find enemies.** Arena already holds the list as `_spirits`, and the
## Lesson 6 rule "the player does not even read the stick" holds here too.
## If this starts walking the scene, Lesson 8 enemies cannot reuse the same body.
##
## Who sits inside the fan is also Arena's call. This only **swings the blade.**
func attack(direction: Vector2, full_moon: bool = false) -> void:
	if not can_attack() or direction.length() < 0.01:
		return
	_attack_cooldown = attack_cooldown_time
	face_toward(direction)
	_show_slash(direction, full_moon)


## Show the blade. Art is one frame facing +x, so it is rotated into place.
##
## Drawing all four directions means four places to fix. That is why `build_slash.py` bakes one.
##
## Why `Slash` gets `light_mask = 0` and `modulate` above 1 is noted here too.
## Parent `Player` carries the night tint (0.315, 0.35, 0.57), so raw moonlight sinks to navy.
## Multiply back to white. Scene files cannot hold comments —
## the editor strips them on open/save.
func _show_slash(direction: Vector2, full_moon: bool = false) -> void:
	var angle: float = direction.angle()
	_slash.rotation = angle
	_slash_back.visible = false

	# **When the blade grows stronger, it must look larger.**
	#
	# Numbers up and art unchanged reads as "attack always feels the same."
	# Reach shows as length, fan as width, damage as brightness —
	# three relics each push the art on a different axis.
	var reach: float = attack_range / DEFAULT_ATTACK_RANGE
	var width: float = attack_arc / DEFAULT_ATTACK_ARC

	# Higher damage: whiter, hotter, and a thicker blade.
	#
	# With `(damage - 1) / 5` it **saturated at six.** Damage 6 or 60 looked identical
	# pixel for pixel. After switching to multiplicative growth, damage climbs into the
	# hundreds, so a linear scale hits the ceiling immediately anyway.
	#
	# A log has no end. Equal multipliers brighten by the same step, so
	# 5 → 10 and 50 → 100 read as the same-size jump.
	var heat: float = clampf(log(maxf(float(attack_damage) / float(DEFAULT_ATTACK_DAMAGE), 1.0)) / log(64.0), 0.0, 1.0)

	# Thickness is a separate axis from reach and fan. Stack all three and late hits hit hard.
	var bulk: float = 1.0 + 0.45 * heat
	# Cap drawn size. **Hit size still grows** — this only shrinks what you see.
	# Stacking reach many times would stretch the 128×32 sprite across half the screen,
	# and that much alpha fill would land on every hit.
	var shown: float = minf(reach, 3.2)
	_slash.scale = Vector2(shown * bulk, shown * width * bulk)
	_slash.position = SLASH_PIVOT + direction.normalized() * SLASH_OFFSET * reach
	var slash_light: Color = _hero_primary.lerp(Color.WHITE, 0.44 + 0.20 * heat)
	_slash.modulate = Color(
		slash_light.r * (3.2 + 1.2 * heat),
		slash_light.g * (3.2 + 1.0 * heat),
		slash_light.b * (3.2 + 0.8 * heat), 1.0)
	if slash_rank > 0:
		# Afterimages store a smaller angle and radius than Arena's real fan.
		# `_draw` below also origins at zero so it never looks like it cut an out-of-hit enemy.
		_slash_echo_wave = 0.0
		_slash_echo_angle = angle
		_slash_echo_half_arc = PI if full_moon \
			else deg_to_rad(attack_arc) * 0.5
		_slash_echo_reach = attack_range * (1.15 if full_moon else 1.0)
		queue_redraw()
	else:
		_slash_echo_wave = -1.0
	if full_moon:
		# Two crescents and a spreading ring. Arena also switches the hit to 360°.
		_slash_back.rotation = angle + PI
		_slash_back.scale = Vector2(shown * bulk * 1.08, shown * maxf(width, 1.2) * bulk)
		_slash_back.position = SLASH_PIVOT - direction.normalized() * SLASH_OFFSET * reach
		var back_light: Color = _hero_secondary.lerp(Color.WHITE, 0.48)
		_slash_back.modulate = Color(
			back_light.r * 4.4, back_light.g * 4.4, back_light.b * 4.4, 1.0)
		_slash_back.frame = 0
		_slash_back.visible = true
		_slash.modulate = Color(
			slash_light.r * 4.4, slash_light.g * 4.4, slash_light.b * 4.4, 1.0)
		_full_wave = 0.0
		queue_redraw()

	_slash.frame = 0
	_slash.visible = true

	# Advance three frames in order. Skip `AnimatedSprite2D` because there are only a few
	# frames and it only needs to play once.
	#
	# **Always kill the previous tween.** Otherwise around Fast Hands 4 the attack interval
	# drops below the animation (0.18s), and the old tween's last callback sets
	# `visible = false` **mid** next slash and the blade flickers.
	# Stronger builds would paradoxically make the screen quieter.
	if _slash_play != null and _slash_play.is_valid():
		_slash_play.kill()

	# Shorten play length to match the interval too. An animation longer than the interval
	# never finishes anyway; shortening makes fast attacks **look** fast.
	var span: float = minf(SLASH_SECONDS, attack_cooldown_time * 0.9)
	var step: float = span / float(_slash.hframes)

	_slash_play = create_tween()
	for frame in range(1, _slash.hframes):
		_slash_play.tween_interval(step)
		_slash_play.tween_callback(func() -> void:
			_slash.frame = frame
			if _slash_back.visible:
				_slash_back.frame = frame)
	_slash_play.tween_interval(step)
	_slash_play.tween_callback(func() -> void:
		_slash.visible = false
		_slash_back.visible = false)


## How full the foot ring is. Arena passes beacon charge through.
##
## The player does not know beacons directly. Lesson 8 enemies reuse this body and
## do not light beacons.
func set_charge(ratio: float) -> void:
	_ring.set_progress(ratio)


func set_charge_overcharge(value: bool) -> void:
	_ring.set_overcharge(value)


## World position of the candle held in both hands. Arrows and missiles share it.
func moonlight_origin() -> Vector2:
	return to_global(MOONLIGHT_ORIGIN)


## A 0.16s cue that "the character sent moonlight" without growing a separate attack sheet.
##
## Shot count only affects spark count and ring size. Damage and fire direction stay
## untouched so input and animation stay steady under rapid fire.
func play_moonlight_cast(direction: Vector2, count: int = 1) -> void:
	var cast_direction: Vector2 = direction.normalized()
	if cast_direction.length() < 0.01:
		cast_direction = facing_vector()
	_moonlight_cast.play(cast_direction, count)


## Pass Arena's moonfire awakening state to the body-side marker.
func set_moonfire(value: bool, locked: bool = false) -> void:
	_moonfire.set_active(value, locked)


## Widen walkable bounds. Arena calls this when the Lesson 9 moonlight gate opens.
func set_bounds(rect: Rect2) -> void:
	bounds = rect


## Share the structure list that really blocks motion, unlike decor.
func set_terrain_room(room: Room) -> void:
	_terrain_room = room


## Open the path in front of the gate. **Only inside that x span** can you go further down.
func open_gate_path(rect: Rect2) -> void:
	gate_path = rect


## How far down the current spot allows.
##
## Extra depth only while inside the gate path's x span.
func _lower_limit() -> float:
	if not gate_path.has_area():
		return bounds.end.y
	if position.x < gate_path.position.x or position.x > gate_path.end.x:
		return bounds.end.y
	return maxf(bounds.end.y, gate_path.end.y)


## Is dash ready. HUD uses this to draw the ring.
func get_dash_ratio() -> float:
	return 1.0 - clampf(_dash_cooldown / dash_cooldown_time, 0.0, 1.0)


func is_dashing() -> bool:
	return _dash_left > 0.0


## Arena calls this on the dash button. During cooldown it does nothing.
func dash(direction: Vector2) -> bool:
	if _dash_cooldown > 0.0 or direction.length() < 0.01:
		return false
	_dash_cooldown = dash_cooldown_time
	_dash_left = DASH_SECONDS
	velocity = direction.normalized() * DASH_SPEED
	face_toward(direction)
	if not (OS.is_debug_build() and _debug_direction_capture_vfx_suppressed):
		_dash_streak_direction = direction.normalized()
		_dash_streak_left = DASH_STREAK_SECONDS
		queue_redraw()
	return true


## Pixel 10 hero facing-matrix capture only. Does not touch move, physics, or Sprite animation.
func debug_set_direction_capture_vfx_suppressed(value: bool) -> void:
	if not OS.is_debug_build():
		return
	_debug_direction_capture_vfx_suppressed = value
	if not value:
		_moonlight_cast.visible = true
		_ring.visible = true
		_moonfire.visible = true
		return
	_dash_streak_left = 0.0
	_continue_burst_left = 0.0
	if _slash_play != null and _slash_play.is_valid():
		_slash_play.kill()
	_slash_play = null
	_slash.visible = false
	if _slash_back != null and is_instance_valid(_slash_back):
		_slash_back.visible = false
	_full_wave = -1.0
	_starfall_preview = -1.0
	_slash_echo_wave = -1.0
	_moonlight_cast.stop()
	_moonlight_cast.visible = false
	_ring.set_progress(0.0)
	_ring.visible = false
	_moonfire.set_active(false)
	_moonfire.visible = false
	for ghost in get_tree().get_nodes_in_group(&"player_afterimages"):
		if is_instance_valid(ghost):
			ghost.queue_free()
	queue_redraw()


func debug_direction_capture_vfx_hidden() -> bool:
	if not OS.is_debug_build():
		return false
	var slash_back_hidden: bool = _slash_back == null \
		or not is_instance_valid(_slash_back) or not _slash_back.visible
	return _debug_direction_capture_vfx_suppressed \
		and not _moonlight_cast.visible and not _ring.visible \
		and not _moonfire.visible and not _slash.visible and slash_back_hidden \
		and _full_wave < 0.0 and _starfall_preview < 0.0 \
		and _slash_echo_wave < 0.0 and _dash_streak_left <= 0.0


## Knock back on hit. Away from where the spirit was.
##
## Ignore the stick while knocked. Otherwise a held stick cancels knockback and
## the hit never feels like a hit.
func knock_back(from_position: Vector2) -> void:
	var away: Vector2 = (global_position - from_position).normalized()
	if away.length() < 0.01:
		away = Vector2.DOWN
	velocity = away * KNOCKBACK_SPEED
	_knock_left = KNOCKBACK_SECONDS


## Facing as a vector. Used when dashing while standing still.
func facing_vector() -> Vector2:
	match facing:
		Facing.UP: return Vector2.UP
		Facing.LEFT: return Vector2.LEFT
		Facing.RIGHT: return Vector2.RIGHT
		_: return Vector2.DOWN


## Arena reads the stick and passes it. Length 0–1.
func set_move_input(direction: Vector2) -> void:
	_wish = direction.limit_length(1.0)


## Fully stop so the body and attached VFX do not keep ticking behind the result panel.
##
## A killing blow applies knockback first, then enters Arena `_finish()`. Zeroing input alone
## leaves residual knockback speed moving behind the result screen, so kill velocity and physics too.
## Insert a coin on the result screen and stand up in place.
##
## Restore exactly what `stop_for_result()` stopped. Leave position, facing, and look at the
## death spot so it differs from "from the start" — arcade continue is about feeling that
## the run continues.
func resume_after_continue(clear_radius: float) -> void:
	if not _stopped_for_result:
		return
	_stopped_for_result = false
	_wish = Vector2.ZERO
	velocity = Vector2.ZERO
	process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(true)
	set_walking(false)
	_continue_burst_radius = maxf(clear_radius, 1.0)
	_continue_burst_left = CONTINUE_BURST_SECONDS
	queue_redraw()


func stop_for_result() -> void:
	_stopped_for_result = true
	_wish = Vector2.ZERO
	velocity = Vector2.ZERO
	_knock_left = 0.0
	_dash_left = 0.0
	_dash_streak_left = 0.0
	_continue_burst_left = 0.0
	set_walking(false)
	if _slash_play != null and _slash_play.is_valid():
		_slash_play.kill()
	_slash_play = null
	_slash.visible = false
	if _slash_back != null and is_instance_valid(_slash_back):
		_slash_back.visible = false
	_full_wave = -1.0
	_starfall_preview = -1.0
	_slash_echo_wave = -1.0
	_moonlight_cast.stop()
	_ring.set_progress(0.0)
	_moonfire.set_active(false)
	for ghost in get_tree().get_nodes_in_group(&"player_afterimages"):
		if is_instance_valid(ghost):
			ghost.queue_free()
	queue_redraw()
	set_physics_process(false)
	process_mode = Node.PROCESS_MODE_DISABLED


func _physics_process(delta: float) -> void:
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if _dash_streak_left > 0.0:
		_dash_streak_left = maxf(_dash_streak_left - delta, 0.0)
		queue_redraw()
	if _continue_burst_left > 0.0:
		_continue_burst_left = maxf(_continue_burst_left - delta, 0.0)
		queue_redraw()
	if _full_wave >= 0.0:
		_full_wave += delta * 4.2
		if _full_wave > 1.0:
			_full_wave = -1.0
		queue_redraw()
	if _starfall_preview >= 0.0:
		_starfall_preview += delta * 3.8
		if _starfall_preview > 1.0:
			_starfall_preview = -1.0
		queue_redraw()
	if _slash_echo_wave >= 0.0:
		_slash_echo_wave += delta * 5.4
		if _slash_echo_wave > 1.0:
			_slash_echo_wave = -1.0
		queue_redraw()
	if _knock_left > 0.0:
		_knock_left -= delta                     # Ignore the stick while knocked back
	elif _dash_left > 0.0:
		_dash_left -= delta                      # Ignore the stick during dash too
	else:
		var target: Vector2 = _wish * speed
		var rate: float = ACCELERATION if _wish.length() > 0.0 else FRICTION
		velocity = velocity.move_toward(target, rate * delta)
	# Hundreds of decor pieces get no physics nodes; terrain structure circles share Room's
	# small list. Dash and knockback take the same path, so they do not clip walls.
	var motion: Vector2 = velocity * delta
	if _terrain_room != null and is_instance_valid(_terrain_room):
		position = _terrain_room.resolve_terrain_motion(position, motion, 4.0)
	else:
		position += motion

	# Stay inside the trees. Clamp coordinates instead of building walls —
	# attaching colliders to a 1,296-tree forest would be a whole other lesson.
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.y = clampf(position.y, bounds.position.y, _lower_limit())

	face_toward(_wish)
	set_walking(velocity.length() > WALK_THRESHOLD)


## Short circular afterglow for full-moon slash and moon dance. No permanent node or physics watch.
func play_moon_dance() -> void:
	_full_wave = 0.0
	queue_redraw()


## On picking the full-moon card, flash both crescents once. No damage.
func play_full_moon_preview() -> void:
	_show_slash(facing_vector(), true)


## On gaining Moonlight Core / Starfall, raise starlight equal to the next real volley count.
func play_starfall_preview(count: int = 1) -> void:
	_starfall_preview_count = clampi(count, 1, 8)
	_starfall_preview = 0.0
	queue_redraw()


func _draw() -> void:
	if _continue_burst_left > 0.0:
		var burst_progress: float = 1.0 \
			- _continue_burst_left / CONTINUE_BURST_SECONDS
		var eased: float = 1.0 - pow(1.0 - burst_progress, 2.0)
		var burst_radius: float = lerpf(10.0, _continue_burst_radius, eased)
		var burst_fade: float = pow(1.0 - burst_progress, 1.4)
		var burst_tone: Color = _hero_secondary.lerp(Color.WHITE, 0.46)
		draw_arc(Vector2(0.0, -7.0), burst_radius, 0.0, TAU, 40,
			Color(burst_tone.r * 1.8, burst_tone.g * 1.8,
				burst_tone.b * 1.8, 0.88 * burst_fade), 2.4, false)
		draw_arc(Vector2(0.0, -7.0), burst_radius * 0.72, 0.0, TAU, 32,
			Color(1.0, 0.94, 0.68, 0.46 * burst_fade), 1.2, false)
		for ray_index in 8:
			var ray: Vector2 = Vector2.RIGHT.rotated(
				TAU * float(ray_index) / 8.0)
			draw_line(
				Vector2(0.0, -7.0) + ray * burst_radius * 0.80,
				Vector2(0.0, -7.0) + ray * burst_radius,
				Color(1.0, 0.88, 0.58, 0.55 * burst_fade), 1.2, false)

	if _dash_streak_left > 0.0:
		var progress: float = _dash_streak_left / DASH_STREAK_SECONDS
		var trail: Vector2 = -_dash_streak_direction
		var side := Vector2(-trail.y, trail.x)
		var tone: Color = _hero_secondary.lerp(Color.WHITE, 0.28)
		var color := Color(
			tone.r * 1.9, tone.g * 1.9, tone.b * 1.9, 0.38 * progress)
		# Do not copy the full silhouette — leave short 1px lines beside the body.
		# Parent `_draw` runs before the Sprite child, so the lines sit behind the body.
		var center := Vector2(0.0, -11.0)
		draw_line(center + side * 4.0 + trail * 3.0,
			center + side * 4.0 + trail * 13.0, color, 1.0, false)
		draw_line(center - side * 4.0 + trail * 5.0,
			center - side * 4.0 + trail * 11.0,
			Color(color.r, color.g, color.b, color.a * 0.72), 1.0, false)

	if _slash_echo_wave >= 0.0:
		var echo_count: int = mini(ceili(float(slash_rank) / 2.0), 3)
		for i in echo_count:
			# Rear rings start slightly late so they read as multi-hit afterimages, not one thick stroke.
			var delayed: float = _slash_echo_wave - 0.07 * float(i)
			if delayed < 0.0:
				continue
			var progress: float = clampf(delayed, 0.0, 1.0)
			var fade: float = 1.0 - progress
			# Center on the real hit origin, not SLASH_PIVOT. Cap radius at 86% and
			# angle at 88% so even with stroke width they stay inside the real attack fan.
			var radius_ratio: float = 0.46 + 0.32 * progress + 0.04 * float(i)
			var radius: float = _slash_echo_reach * minf(radius_ratio, 0.86)
			var visual_half_arc: float = _slash_echo_half_arc * (
				0.76 + 0.04 * progress)
			var color := Color(0.55, 0.82, 1.12, (0.52 - 0.08 * float(i)) * fade)
			if slash_rank >= 5:
				color = Color(1.18, 0.82, 0.34, (0.58 - 0.08 * float(i)) * fade)
			draw_arc(Vector2.ZERO, radius,
				_slash_echo_angle - visual_half_arc,
				_slash_echo_angle + visual_half_arc,
				18 + 4 * i, color, 1.4 + 0.35 * float(i), false)

	if _full_wave >= 0.0:
		var fade: float = 1.0 - _full_wave
		var reach: float = lerpf(18.0, attack_range * 1.3, _full_wave)
		draw_arc(SLASH_PIVOT, reach, 0.0, TAU, 36,
			Color(1.0, 0.82, 0.42, 0.88 * fade), 3.0, false)
		draw_arc(SLASH_PIVOT, reach * 0.78, 0.0, TAU, 28,
			Color(0.72, 0.58, 1.0, 0.58 * fade), 1.5, false)

	if _starfall_preview >= 0.0:
		var fade: float = 1.0 - _starfall_preview
		var inner: float = lerpf(8.0, 20.0, _starfall_preview)
		var outer: float = lerpf(18.0, 58.0, _starfall_preview)
		for i in _starfall_preview_count:
			var direction: Vector2 = Vector2.UP.rotated(
				TAU * float(i) / float(_starfall_preview_count))
			draw_line(SLASH_PIVOT + direction * inner,
				SLASH_PIVOT + direction * outer,
				Color(0.5, 0.86, 1.0, 0.9 * fade), 2.2)
			draw_circle(SLASH_PIVOT + direction * outer, 2.4,
				Color(1.0, 0.94, 0.68, 0.88 * fade))


## Lesson 6 passes stick direction as-is. Near-zero length leaves facing unchanged.
func face_toward(direction: Vector2) -> void:
	if direction.length() < 0.01:
		return
	if absf(direction.x) > absf(direction.y):
		facing = Facing.RIGHT if direction.x > 0.0 else Facing.LEFT
	else:
		facing = Facing.DOWN if direction.y > 0.0 else Facing.UP


## Report whether walking. Lesson 6 calls this every frame.
func set_walking(value: bool) -> void:
	if _walking == value:
		return
	_walking = value
	_play_current()


func _set_facing(value: Facing) -> void:
	facing = value
	if _sprite == null:
		return                                   # Setter runs before `@onready`
	_play_current()


func _play_current() -> void:
	var prefix: String = "walk_" if _walking else "idle_"
	_sprite.play(prefix + FACING_NAMES[facing])
