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
## Crosses the 4/3 camera's 606px visible width in about 5.4s. Fast enough to move between
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

const DEFAULT_SPEED: float = 112.0
@export var speed: float = DEFAULT_SPEED

## Response when stopping and starting. Larger values slide more.
const ACCELERATION: float = 1100.0
const FRICTION: float = 1500.0

## Slower than this counts as standing still.
const WALK_THRESHOLD: float = 4.0

## Dash — a short, fast slide. The way through a pack of spirits.
const DASH_SPEED: float = 320.0
const DASH_SECONDS: float = 0.19
## Until it can be used again. Too short and dash becomes the only movement.
const DEFAULT_DASH_COOLDOWN: float = 0.95
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
## Melee heroes keep their small moonlight backup here: the spark shots leave
## from the candle, and the cast cue sits on it. Gun heroes aim from the hand
## and fire from the muzzle instead (see `muzzle_origin`).
const MOONLIGHT_ORIGIN: Vector2 = Vector2(0, -20)
## Painted-arm attack articulation, degrees of wrist arc about the shoulder.
## A rotation keeps the wrist on its rest circle, so the cut never asks the
## arm to extend past straight; the elbow bends through two-bone IK to absorb
## the arc. Gun wrists track the kick (`WeaponRig.attack_shift_now`) instead
## and fold back, except straight up-aims, which bow out below.
const ARM_SWING_WARDEN: float = 35.0
const ARM_SWING_DANCER: float = 30.0
const ARM_SWING_ECLIPSE: float = 35.0
## Elbow bend through the cut: the fraction the wrist draws toward the
## shoulder at peak. A pure arc would swing a stiff arm; the tuck flexes the
## elbow while the blade rotates about the grip.
const ARM_TUCK_MELEE: float = 0.15
## Torso commit with the attack, cell px. The upper body leans rigidly while
## the live legs keep stepping; the shoulder rides the torso it is attached
## to. Small on purpose: the arm is the action, this is the brace.
const TORSO_LUNGE_MELEE: float = 5.0
const TORSO_KICK_RANGED: float = 6.0
## Up-aim gun path: the arm hangs straight down, so a straight kick would
## extend past the elbow. Bow outward (pole x) this far instead, in cell px,
## plus a touch back; the torso shift carries the visible kick.
const UP_BOW_OUT: float = 2.0
const UP_BOW_BACK: float = 0.5
## Sprite draw offset the seat math assumes, in texture px (scaled by the
## hero scale at draw). Cell (72,96) lands on position + this times scale.
const SPRITE_OFFSET: Vector2 = Vector2(0.0, -8.0)
const MOONLIGHT_CAST_SECONDS: float = MoonlightCast.CAST_SECONDS
## Hero art is already painted as if lit by moonlight. Undo the Player root night tint
## (0.315, 0.35, 0.57) on the sprite only so the face does not die into a purple blotch.
## Brightening the root overexposes Slash and MoonfireAura.
const HERO_READABILITY_TINT: Color = Color(3.175, 2.857, 1.754, 1)
## Sprite offset the foot planting assumes. Breathe animates the live offset,
## so the formula reads this base value instead.
const HERO_BASE_OFFSET_Y: float = -8.0
## Tuned body factor the legacy position formula was built around. Painted
## heroes render at visual_scale 0.255 = 1/3 of this for 3× cells.
const LEGACY_BODY_FACTOR: float = 0.765

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
@onready var _breathe: AnimationPlayer = $Breathe

## Drawn held-weapon layer and Eclipse orbit blades. Built in code so the Player scene
## keeps one shape for every hero; both clear/freeze with the body itself. The orbit
## only exists for Eclipse (see `_ensure_scythe`): other heroes never pay its node.
var _rig: WeaponRig = null
var _scythe: ScytheOrbit = null
## Moon-ember aura marker. Created on the first awakening; runs that never wake
## moonfire never pay its node. Seated exactly where the old scene node sat.
var _moonfire: MoonfireAura = null
## Sprite rest height. The attack split never moves the sprite itself.
var _sprite_base_y: float = -8.0
var _hero_scale: float = 0.255
var _hero: Hero = null
var _hero_id: String = "warden"
## Attack split render: frozen planted legs, armless torso, articulated arms.
## Hidden at rest (the baked sprite shows); swapped in for primary attacks. The main
## chain always exists; the off chain and the stacked nub join on first need
## (Dancer/Eclipse attacks), so single-hand heroes never pay their nodes.
var _legs: Sprite2D = null
var _torso: Sprite2D = null
var _arm_main: ArmRig = null
var _arm_off: ArmRig = null
var _nub: Sprite2D = null
var _split_shown: bool = false
var _attack_facing: String = "down"
var _torso_textures: Dictionary = {}
## Unshifted torso seat while the split shows; the commit shift adds per tick.
var _torso_base: Vector2 = Vector2.ZERO
## Baked-sprite state at the split swap, plus the live gait clock that keeps
## the hidden sprite and the drawn legs stepping through the attack.
var _split_walking: bool = false
var _split_animation: StringName = &""
var _split_facing: int = 0
var _gait_time: float = 0.0
## Facing hold: a primary attack faces its target until its rig finishes
## while locomotion continues underneath; movement re-faces once it does.
var _face_hold: float = 0.0
## Draw-layer VFX suppression for the motion harness no-VFX pass. Production
## attack methods run normally; cue draws stay dark.
var _vfx_suppressed: bool = false
## Negative-control probe for the motion regression: the arm chains hold
## their rest pose while the weapon rides the computed wrist and cues fire
## normally. The articulation test must fail with this on. Production never
## sets it; the test restores it before finishing.
var _debug_arm_freeze: bool = false
static var _rig_geometry: Dictionary = {}

var _walking: bool = false
var _attack_cooldown: float = 0.0
## Full-moon slash also shows the crescent on the far side so a full circle reads.
## Created on the first full-moon swing; ordinary attacks never pay its node.
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
	_sprite_base_y = _sprite.position.y
	_hero_scale = _sprite.scale.x
	_sprite.offset = Vector2(0.0, -8.0)
	_set_facing(facing)
	_slash.visible = false
	_rig = WeaponRig.new()
	_rig.name = "WeaponRig"
	add_child(_rig)
	_rig.configure(_hero_profile, _hero_primary, _hero_secondary)
	# The far crescent, orbit, off hand, nub, and aura join on first need
	# (`_ensure_*`); heroes that never need one never pay its node.
	_build_attack_split()


## Build the attack split nodes: live legs, armless torso, and the main arm
## chain. Siblings after the sprite at the same depth, so tree order layers
## them; the weapon rig (z=2) stays above them all. Split sprites wear the
## baked readability tint and polish, so the attack body renders exactly as
## bright as the idle body it replaces. The off chain and nub join on first
## need in this same relative order.
func _build_attack_split() -> void:
	_legs = Sprite2D.new()
	_legs.name = "AttackLegs"
	_legs.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_torso = Sprite2D.new()
	_torso.name = "AttackTorso"
	_torso.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_arm_main = ArmRig.new()
	_arm_main.name = "ArmMain"
	for node in [_legs, _torso, _arm_main]:
		node.visible = false
		add_child(node)
	_match_split_light()


## Match the baked body light on every split sprite: readability tint plus
## the polish material, so the attack body never blinks dark.
func _match_split_light() -> void:
	if _sprite == null:
		return
	var polish: Material = _sprite.material
	for patch in [_legs, _torso, _nub]:
		if patch != null:
			patch.self_modulate = HERO_READABILITY_TINT
			patch.material = polish
	for chain in [_arm_main, _arm_off]:
		if chain != null:
			chain.set_render_tint(HERO_READABILITY_TINT, polish)


## Lazily built attack nodes. Each is created once on first need and kept:
## repeated attacks, hero switches, and recoveries never duplicate one, and
## heroes that never need one never pay its node. Insertion order reproduces
## the old eager tree exactly where same-depth draw order matters.
func _ensure_arm_off() -> ArmRig:
	if _arm_off == null:
		_arm_off = ArmRig.new()
		_arm_off.name = "ArmOff"
		_arm_off.visible = false
		add_child(_arm_off)
		_match_split_light()
	return _arm_off


func _ensure_nub() -> Sprite2D:
	if _nub == null:
		_nub = Sprite2D.new()
		_nub.name = "AttackNub"
		_nub.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_nub.visible = false
		add_child(_nub)
		move_child(_nub, _arm_main.get_index())
		_match_split_light()
	return _nub


func _ensure_slash_back() -> Sprite2D:
	if _slash_back == null:
		_slash_back = _slash.duplicate() as Sprite2D
		_slash_back.name = "FullMoonBack"
		_slash_back.visible = false
		_slash_back.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_slash_back)
		move_child(_slash_back, _rig.get_index())
	return _slash_back


func _ensure_scythe() -> ScytheOrbit:
	if _scythe == null:
		_scythe = ScytheOrbit.new()
		_scythe.name = "ScytheOrbit"
		_scythe.position = BODY_CENTER
		add_child(_scythe)
		_scythe.configure(_hero_primary, _hero_secondary)
		_scythe.set_vfx_suppressed(_vfx_suppressed)
	return _scythe


func _ensure_moonfire() -> MoonfireAura:
	if _moonfire == null:
		_moonfire = MoonfireAura.new()
		_moonfire.name = "MoonfireAura"
		_moonfire.light_mask = 0
		_moonfire.modulate = Color(2.8, 2.5, 1.7, 1)
		_moonfire.position = Vector2(0, -17)
		add_child(_moonfire)
		move_child(_moonfire, _slash.get_index())
	return _moonfire


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
	_hero = hero
	_hero_id = hero.id
	_hero_profile = hero.attack_profile
	_hero_vfx_tier = clampi(hero.vfx_tier, 0, 5)
	_hero_primary = hero.projectile_primary
	_hero_secondary = hero.projectile_secondary
	_moonlight_cast.configure_profile(
		_hero_profile, _hero_primary, _hero_secondary, _hero_vfx_tier)
	if _rig != null:
		_rig.configure(_hero_profile, _hero_primary, _hero_secondary)
	if _hero_profile == Hero.AttackProfile.ECLIPSE \
			and not _debug_direction_capture_vfx_suppressed:
		_ensure_scythe()
		_scythe.configure(_hero_primary, _hero_secondary)
		_scythe.set_active(true)
	elif _scythe != null:
		_scythe.configure(_hero_primary, _hero_secondary)
		_scythe.set_active(false)
	_sprite.sprite_frames = frames
	_sprite.self_modulate = HERO_READABILITY_TINT
	# Painted cells are 3× the legacy pixels at 1/3 the legacy 0.765 body
	# factor, so the world body renders pixel-identical. Position runs the
	# legacy formula on the world cell, then corrects for the offset scaling
	# with the node: at 0.765 the legacy feet float 5.64px above the root, and
	# muzzle seats and BODY_CENTER were measured against that rendering.
	# Read the base offset, not the live one: Breathe animates offset, and a
	# mid-breath hero swap must not shift the feet.
	_sprite.scale = Vector2.ONE * hero.visual_scale
	_hero_scale = hero.visual_scale
	var world_cell: float = float(hero.sprite_cell.y) * hero.visual_scale \
		/ LEGACY_BODY_FACTOR
	_sprite.position.y = -float(maxi(int(round(world_cell)) - 16, 0)) * 0.5 \
		+ (LEGACY_BODY_FACTOR - hero.visual_scale) * HERO_BASE_OFFSET_Y
	_sprite_base_y = _sprite.position.y
	# A fresh hero starts settled: no cut or kick carries across the swap.
	_load_attack_rig()
	_end_attack_pose()
	_update_rest_seat()
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
	var melee_sidearm: bool = HeroWeapons.primary_side(_hero_profile) \
		!= HeroWeapons.Side.MELEE
	# Only the primary owns the body: it faces its target and holds that
	# facing for the whole cut while locomotion continues. A sidearm swings
	# its cue only and never touches facing, seat, or pose.
	if not melee_sidearm:
		_face_primary_target(direction)
		_start_primary_swing(direction, full_moon)
	if _hero_profile == Hero.AttackProfile.ECLIPSE and not full_moon:
		# The scythe sweep is a ring, not a crescent: pulse the orbit instead.
		if _rig != null:
			_rig.flash(direction, WeaponRig.RING_PULSE, melee_sidearm)
		return
	_show_slash(direction, full_moon)
	if _rig != null:
		_rig.flash(direction, WeaponRig.TWIN_CUT
			if _hero_profile == Hero.AttackProfile.DANCER else WeaponRig.CUT,
			melee_sidearm)


## Start the held-weapon cut for a primary melee attack, and tie the Eclipse
## orbit sweep to it: same contact angle, sign, and span. Seats the weapon in
## the painted wrist, swaps in the attack split, and holds facing. Sidearms
## never reach here — they swing the slash cue, not the held weapon.
func _start_primary_swing(direction: Vector2, full_moon: bool) -> void:
	if _rig == null or _debug_direction_capture_vfx_suppressed:
		return
	var span: float = WeaponRig.attack_span_for(
		_hero_profile, attack_cooldown_time)
	_face_hold = span
	var sign: float = _rig.play_primary_swing(direction, span)
	_begin_attack_pose()
	if _hero_profile == Hero.AttackProfile.ECLIPSE and not full_moon \
			and _scythe != null:
		_scythe.pulse(direction.normalized().angle(), sign, span)


## Show the blade. Art is one frame facing +x, so it is rotated into place.
##
## Drawing all four directions means four places to fix. That is why `build_slash.py` bakes one.
##
## Why `Slash` gets `light_mask = 0` and `modulate` above 1 is noted here too.
## Parent `Player` carries the night tint (0.315, 0.35, 0.57), so raw moonlight sinks to navy.
## Multiply back to white. Scene files cannot hold comments —
## the editor strips them on open/save.
func _show_slash(direction: Vector2, full_moon: bool = false) -> void:
	if _vfx_suppressed:
		return
	var angle: float = direction.angle()
	_slash.rotation = angle
	if _slash_back != null:
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
		_ensure_slash_back()
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
			if _slash_back != null and _slash_back.visible:
				_slash_back.frame = frame)
	_slash_play.tween_interval(step)
	_slash_play.tween_callback(func() -> void:
		_slash.visible = false
		if _slash_back != null:
			_slash_back.visible = false)


## How full the foot ring is. Arena passes beacon charge through.
##
## The player does not know beacons directly. Lesson 8 enemies reuse this body and
## do not light beacons.
func set_charge(ratio: float) -> void:
	_ring.set_progress(ratio)


func set_charge_overcharge(value: bool) -> void:
	_ring.set_overcharge(value)


## World position of the candle held in both hands. Melee backup shots and
## their cast cue share it; gun heroes fire from `muzzle_origin` instead.
func moonlight_origin() -> Vector2:
	return to_global(MOONLIGHT_ORIGIN)


## Facing one aim snaps to: the dominant axis, exactly like `face_toward`.
static func facing_for(aim: Vector2) -> String:
	var flat: Vector2 = aim.normalized() if aim.length() > 0.01 \
		else Vector2.RIGHT
	if absf(flat.x) > absf(flat.y):
		return "left" if flat.x < 0.0 else "right"
	return "up" if flat.y < 0.0 else "down"


## Facing direction vector for one facing name.
static func facing_vector_for(facing: String) -> Vector2:
	match facing:
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
		"up":
			return Vector2.UP
	return Vector2.DOWN


## Rest wrist seat for one hero and facing, player-local: the painted hand
## that holds the weapon, measured in the attack rig bake. Seats follow the
## AIM's facing (the hand is where the weapon points), never the body facing,
## so firing right while walking left keeps a coherent grip.
static func wrist_seat_for(hero_id: String, facing: String, base_y: float,
		hero_scale: float) -> Vector2:
	var wrist: Vector2 = rest_wrist_cell(hero_id, facing)
	return cell_to_local(wrist, base_y, hero_scale)


## Main-hand rest wrist in torso-space cell px: the grip at contact.
static func rest_wrist_cell(hero_id: String, facing: String) -> Vector2:
	var geometry: Dictionary = rig_geometry_for(hero_id)
	var entry: Dictionary = (geometry.get("facings", {}) as Dictionary).get(
		facing, {})
	var arms: Dictionary = entry.get("arms", {})
	var side: String = main_hand_side(hero_id, facing)
	if arms.has(side):
		var wrist: Array = (arms[side] as Dictionary).get("W", [72, 96])
		return Vector2(float(wrist[0]), float(wrist[1]))
	return Vector2(72, 96)


## Which baked arm is the weapon hand: the viewer-right arm front-on, the
## near arm in profile. Dancer's cutter varies per attack (see below).
static func main_hand_side(_hero_id: String, facing: String) -> String:
	if facing == "down" or facing == "up":
		return "right"
	return "near"


## Torso-space cell px to player-local, with the torso commit shift applied.
static func cell_to_local(cell: Vector2, base_y: float, hero_scale: float,
		shift_cells: Vector2 = Vector2.ZERO) -> Vector2:
	return Vector2(0.0, base_y) \
		+ (SPRITE_OFFSET + (cell - Vector2(72, 96))) * hero_scale \
		+ shift_cells * hero_scale


## Attack rig bake for one hero id, cached. Holds joints, patches, cutline.
static func rig_geometry_for(hero_id: String) -> Dictionary:
	if _rig_geometry.has(hero_id):
		return _rig_geometry[hero_id]
	var path: String = "res://assets/custom/actors/heroes/%s/rig/rig.json" \
		% hero_id
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path))
	_rig_geometry[hero_id] = parsed if parsed is Dictionary else {}
	return _rig_geometry[hero_id]


## Rig-origin offset from the painted wrist for one aim: melee grips hang
## behind the origin (`WeaponRig.GRIP_BACK`), gun pivots sit ahead of the
## stock hand, so the origin stands off the wrist and the grip lands on it.
static func seat_offset_for(
	profile: Hero.AttackProfile, aim: Vector2
) -> Vector2:
	var flat: Vector2 = aim.normalized() if aim.length() > 0.01 \
		else Vector2.RIGHT
	if HeroWeapons.primary_side(profile) == HeroWeapons.Side.RANGED:
		return flat * WeaponRig.stock_back(profile)
	return flat * WeaponRig.GRIP_BACK


## Rest rig position for one aim, player-local: the painted wrist of the aim's
## facing plus the seat offset, so the drawn grip sits exactly on the hand.
## Seats follow the AIM's facing, never the body facing, so firing right while
## walking left keeps a coherent grip.
func rest_rig_seat(aim: Vector2) -> Vector2:
	return wrist_seat_for(_hero_id, facing_for(aim), _sprite_base_y,
		_hero_scale) + seat_offset_for(_hero_profile, aim)


## World point shots are aimed from: the held pivot of the current facing
## for gun heroes, the candle for melee heroes whose ranged slot is a spark
## backup. The first rough pass; `hand_for_aim` refines it per aim.
func shot_anchor() -> Vector2:
	if HeroWeapons.primary_side(_hero_profile) == HeroWeapons.Side.RANGED:
		return to_global(rest_rig_seat(facing_vector()))
	return to_global(MOONLIGHT_ORIGIN)


## Aim point for one resolved aim: the held pivot of the aim's facing, so
## the muzzle sits on the aim line instead of firing parallel to it.
## Melee heroes keep the candle whatever the aim.
func hand_for_aim(aim: Vector2) -> Vector2:
	if HeroWeapons.primary_side(_hero_profile) != HeroWeapons.Side.RANGED:
		return to_global(MOONLIGHT_ORIGIN)
	return to_global(rest_rig_seat(aim))


## World launch point for one resolved aim: the held gun's muzzle — the rest
## seat plus the muzzle length along the aim — for gun heroes, the candle for
## melee backup. At the contact instant the drawn muzzle sits exactly here.
func muzzle_origin(aim: Vector2) -> Vector2:
	if HeroWeapons.primary_side(_hero_profile) != HeroWeapons.Side.RANGED:
		return to_global(MOONLIGHT_ORIGIN)
	var flat: Vector2 = aim.normalized() if aim.length() > 0.01 else Vector2.RIGHT
	return to_global(rest_rig_seat(aim)) \
		+ flat * WeaponRig.muzzle_length(_muzzle_kind())


## A 0.16s cue that "the character sent moonlight" without growing a separate attack sheet.
##
## Shot count only affects spark count and ring size. Damage and fire direction stay
## untouched so input and animation stay steady under rapid fire.
func play_moonlight_cast(direction: Vector2, count: int = 1) -> void:
	var cast_direction: Vector2 = direction.normalized()
	if cast_direction.length() < 0.01:
		cast_direction = facing_vector()
	_moonlight_cast.play(cast_direction, count)
	var ranged_sidearm: bool = HeroWeapons.primary_side(_hero_profile) \
		== HeroWeapons.Side.MELEE
	if ranged_sidearm:
		_moonlight_cast.position = MOONLIGHT_ORIGIN
	else:
		_moonlight_cast.position = to_local(muzzle_origin(cast_direction))
	# Only the primary owns the body: it faces its target and holds that
	# facing for the whole discharge. A sidearm spark never touches it.
	if not ranged_sidearm:
		_face_primary_target(cast_direction)
		_start_primary_shot(cast_direction)
	if _rig != null and not _debug_direction_capture_vfx_suppressed:
		_rig.flash(cast_direction, _muzzle_kind(), ranged_sidearm)


## Start the held-gun discharge: face held by the caller, weapon seated in the
## painted wrist, attack split swapped in. Sidearms never reach here.
func _start_primary_shot(direction: Vector2) -> void:
	if _rig == null or _debug_direction_capture_vfx_suppressed:
		return
	var span: float = WeaponRig.attack_span_for(_hero_profile, -1.0)
	_face_hold = span
	_rig.play_primary_shot(direction, span)
	_begin_attack_pose()


## Muzzle grammar per hero. Rifle snaps, the shotgun blooms, the cannon booms.
func _muzzle_kind() -> StringName:
	match _hero_profile:
		Hero.AttackProfile.SAGE:
			return WeaponRig.MUZZLE_RIFLE
		Hero.AttackProfile.KEEPER:
			return WeaponRig.MUZZLE_SCATTER
		Hero.AttackProfile.KNIGHT:
			return WeaponRig.MUZZLE_CANNON
	return WeaponRig.MUZZLE_SPARK


## Heavy-cannon kick. The volley starts the motion in `play_moonlight_cast`,
## which faces, seats, and poses; a lone call without a live kick starts one
## defensively through the same path. Never faces on its own.
func recoil(direction: Vector2) -> void:
	if _sprite == null or direction.length() < 0.01:
		return
	if _debug_direction_capture_vfx_suppressed:
		return
	if _rig != null and not _rig.attack_live():
		_start_primary_shot(direction.normalized())


## Load the attack rig bake for the current hero: armless torso strips per
## facing. Arm patches load per attack facing in `_begin_attack_pose`.
func _load_attack_rig() -> void:
	_torso_textures.clear()
	var geometry: Dictionary = rig_geometry_for(_hero_id)
	var facings: Dictionary = geometry.get("facings", {})
	for facing in facings:
		var entry: Dictionary = facings[facing]
		var path: String = "res://assets/custom/actors/heroes/%s/rig/%s" \
			% [_hero_id, str(entry.get("torso", ""))]
		if ResourceLoader.exists(path):
			_torso_textures[facing] = load(path) as Texture2D


## Swap in the attack split for the current facing: pause and hide the baked
## sprite on its frame, show that frame's legs plus the armless torso and the
## arm chains, and seat the weapon in the painted wrist. The hidden sprite
## keeps its gait clock, so the drawn legs step through the attack. Safe to
## call on a rapid restart: a new aim re-seats everything for its own facing
## while the live gait clock keeps striding, so the frame and sub-frame
## progress never reset.
func _begin_attack_pose() -> void:
	if _sprite == null or _rig == null or _legs == null or _hero == null:
		return
	var facing_name: String = FACING_NAMES[facing]
	_attack_facing = facing_name
	var geometry: Dictionary = rig_geometry_for(_hero_id)
	var entry: Dictionary = (geometry.get("facings", {}) as Dictionary).get(
		facing_name, {})
	if entry.is_empty():
		return
	var cutline: float = float(geometry.get("cutline", 156))
	var cell: Vector2i = _hero.sprite_cell
	# Live legs: the current frame's own strip below the cutline, so the feet
	# start exactly mid-stride with no pop; the gait clock steps it on.
	var sheet: Texture2D = _hero.walk_sheet \
		if str(_sprite.animation).begins_with("walk_") else _hero.idle_sheet
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(int(facing) * cell.x,
		_sprite.frame * cell.y + cutline, cell.x, cell.y - cutline)
	_legs.texture = atlas
	_legs.offset = SPRITE_OFFSET
	_legs.scale = Vector2.ONE * _hero_scale
	_legs.position = Vector2(0.0, _sprite_base_y) \
		+ (Vector2(72.0, (cutline + cell.y) / 2.0) - Vector2(72, 96)) \
		* _hero_scale
	# Armless torso overlays the same upper region; per-tick shift leans it.
	_torso.texture = _torso_textures.get(facing_name) as Texture2D
	_torso.offset = SPRITE_OFFSET
	_torso.scale = Vector2.ONE * _hero_scale
	_torso_base = Vector2(0.0, _sprite_base_y) \
		+ (Vector2(72.0, (cutline + 8.0) / 2.0) - Vector2(72, 96)) \
		* _hero_scale
	_torso.position = _torso_base
	_configure_attack_arms(entry)
	var first_swap: bool = not _split_shown
	_split_walking = _walking
	_split_animation = _sprite.animation
	_split_facing = int(facing)
	if first_swap:
		_gait_time = (float(_sprite.frame) + _sprite.frame_progress) \
			/ maxf(_gait_fps(), 1.0)
	_sprite.pause()
	_sprite.visible = false
	_legs.visible = true
	_torso.visible = true
	_split_shown = true
	_refresh_attack_rig(0.0)


## Hang the baked arm chains for one attack: main hand always, off hand for
## Dancer's brace and Eclipse's mirror, stacked nub for Eclipse in profile.
func _configure_attack_arms(entry: Dictionary) -> void:
	var arms: Dictionary = entry.get("arms", {})
	if _arm_off != null:
		_arm_off.visible = false
	if _nub != null:
		_nub.visible = false
	_rig.brace_local = Vector2.ZERO
	_rig.main_half = &"upper"
	_rig.brace_half = &"lower"
	if _hero_profile == Hero.AttackProfile.DANCER:
		_configure_dancer_arms(entry, arms)
	elif _hero_profile == Hero.AttackProfile.ECLIPSE:
		_configure_eclipse_arms(entry, arms)
	else:
		_setup_arm(_arm_main,
			main_hand_side(_hero_id, _attack_facing), arms)
		_arm_main.visible = true


func _setup_arm(chain: ArmRig, side: String, arms: Dictionary) -> void:
	if not arms.has(side):
		chain.visible = false
		return
	var arm: Dictionary = arms[side]
	var upper_path: String = "res://assets/custom/actors/heroes/%s/rig/%s" \
		% [_hero_id, str((arm["upper"] as Dictionary).get("file", ""))]
	var fore_path: String = "res://assets/custom/actors/heroes/%s/rig/%s" \
		% [_hero_id, str((arm["fore"] as Dictionary).get("file", ""))]
	var upper_tex: Texture2D = load(upper_path) as Texture2D
	var fore_tex: Texture2D = load(fore_path) as Texture2D
	if upper_tex == null or fore_tex == null:
		chain.visible = false
		return
	var upiv: Array = (arm["upper"] as Dictionary).get("pivot", [0, 0])
	var fpiv: Array = (arm["fore"] as Dictionary).get("pivot", [0, 0])
	var s: Array = arm.get("S", [72, 96])
	var e: Array = arm.get("E", [72, 96])
	var w: Array = arm.get("W", [72, 96])
	var pole: Array = arm.get("pole", [1.0, 0.35])
	chain.configure(upper_tex, fore_tex,
		Vector2(float(upiv[0]), float(upiv[1])),
		Vector2(float(fpiv[0]), float(fpiv[1])),
		Vector2(float(s[0]), float(s[1])),
		Vector2(float(e[0]), float(e[1])),
		Vector2(float(w[0]), float(w[1])),
		float(arm.get("L1", 1.0)), float(arm.get("L2", 1.0)),
		Vector2(float(pole[0]), float(pole[1])))
	chain.cell_scale = _hero_scale


## Dancer hands: action 0 cuts the upper fang, action 1 the lower, each from
## its own handle. Front views alternate cutters (right, then left) with the
## other bracing; profiles cut near either way and brace the real far hand.
## Both fangs stay gripped in both modes.
func _configure_dancer_arms(entry: Dictionary, arms: Dictionary) -> void:
	var variant: int = _rig.attack_variant() if _rig != null else 0
	_rig.main_half = &"upper" if variant == 0 else &"lower"
	_rig.brace_half = &"lower" if variant == 0 else &"upper"
	if _attack_facing == "down" or _attack_facing == "up":
		var cutter: String = "right" if variant == 0 else "left"
		var bracer: String = "left" if variant == 0 else "right"
		_setup_arm(_arm_main, cutter, arms)
		_setup_arm(_ensure_arm_off(), bracer, arms)
		_arm_main.visible = true
		_arm_off.visible = true
	else:
		_setup_arm(_arm_main, "near", arms)
		_arm_main.visible = true


## Eclipse hands: front views sweep main plus a mirrored off arm; profiles
## stack the off hand on the main grip (the far hand left its hip).
func _configure_eclipse_arms(entry: Dictionary, arms: Dictionary) -> void:
	if _attack_facing == "down" or _attack_facing == "up":
		_setup_arm(_arm_main, "right", arms)
		_setup_arm(_ensure_arm_off(), "left", arms)
		_arm_main.visible = true
		_arm_off.visible = true
	else:
		_setup_arm(_arm_main, "near", arms)
		_arm_main.visible = true
		if entry.has("nub_off"):
			var nub_entry: Dictionary = entry["nub_off"]
			var path: String = \
				"res://assets/custom/actors/heroes/%s/rig/%s" \
				% [_hero_id, str(nub_entry.get("file", ""))]
			var tex: Texture2D = load(path) as Texture2D \
				if ResourceLoader.exists(path) else null
			if tex != null:
				_ensure_nub()
				var grip: Array = nub_entry.get("grip", [4, 1])
				_nub.texture = tex
				_nub.offset = tex.get_size() / 2.0 \
					- Vector2(float(grip[0]), float(grip[1]))
				_nub.scale = Vector2.ONE * _hero_scale
				_nub.visible = true


## Wrist target for the main hand, torso-space cell px. Melee arcs the wrist
## about the shoulder with the cut sign and tucks it in at peak, so the hand
## sweeps, the elbow bends, and the blade rotates about the grip; the arc
## never extends the arm past straight. Guns fold the wrist back along the
## live kick, except up-aims, which bow outward (the arm hangs straight down
## there; a straight kick would overextend it). The weapon seats on the solved
## wrist, so the grip is exact at every instant; the clamp is a safety net the
## tests watch, not a travel source.
func _main_wrist_target(progress: float) -> Vector2:
	var rest: Vector2 = _arm_main.rest_wrist_cell()
	if HeroWeapons.primary_side(_hero_profile) != HeroWeapons.Side.RANGED:
		var swing: float = ARM_SWING_WARDEN
		match _hero_profile:
			Hero.AttackProfile.DANCER:
				swing = ARM_SWING_DANCER
			Hero.AttackProfile.ECLIPSE:
				swing = ARM_SWING_ECLIPSE
		return _arc_wrist_target(rest, _arm_main.shoulder_cell(), swing,
			progress)
	if _attack_facing == "up":
		var env: float = WeaponRig.attack_envelope(
			progress, WeaponRig.SHOT_PEAK_SLIDE)
		return rest + Vector2(_up_bow_sign() * UP_BOW_OUT,
			UP_BOW_BACK) * env
	return rest + _rig.attack_shift_now() / _hero_scale


## Melee wrist arc for one rest wrist and shoulder: sweep with the cut sign,
## tuck toward the shoulder at peak so the elbow bends.
func _arc_wrist_target(rest: Vector2, shoulder: Vector2, swing_deg: float,
		progress: float) -> Vector2:
	var env: float = WeaponRig.attack_envelope(
		progress, WeaponRig.SWING_PEAK_PUSH)
	var theta: float = deg_to_rad(swing_deg) * env * _rig.attack_sign()
	var arc: Vector2 = shoulder + (rest - shoulder).rotated(theta)
	return shoulder + (arc - shoulder) * (1.0 - ARM_TUCK_MELEE * env)


## Outward bow direction for an up-aim discharge: the arm's own pole side.
func _up_bow_sign() -> float:
	var entry: Dictionary = (rig_geometry_for(_hero_id).get("facings", {}) \
		as Dictionary).get(_attack_facing, {})
	var arms: Dictionary = entry.get("arms", {})
	var side: String = main_hand_side(_hero_id, _attack_facing)
	if arms.has(side):
		return signf(float((arms[side] as Dictionary).get("pole",
			[1.0])[0]))
	return 1.0


## Torso commit shift at one progress point, cell px: melee leans in, guns
## rock back. Shoulders ride it; frozen legs never do.
func _torso_shift_cells(progress: float) -> Vector2:
	var facing_vec: Vector2 = facing_vector_for(_attack_facing)
	if HeroWeapons.primary_side(_hero_profile) != HeroWeapons.Side.RANGED:
		return facing_vec * TORSO_LUNGE_MELEE * WeaponRig.attack_envelope(
			progress, WeaponRig.SWING_PEAK_PUSH)
	return -facing_vec * TORSO_KICK_RANGED * WeaponRig.attack_envelope(
		progress, WeaponRig.SHOT_PEAK_SLIDE)


## Pose the live split for the rig's current progress: torso shift, arm
## chains, weapon grip at the painted wrist, brace fang, off nub, plus the
## stepping legs. The wrist world position is the single source every seat
## derives from — no offset is ever applied twice. Called every physics tick,
## and directly by tests.
func _refresh_attack_rig(delta: float = 0.0) -> void:
	if not _split_shown or _rig == null or _sprite == null:
		return
	var progress: float = _rig.attack_progress()
	if progress < 0.0:
		progress = 0.0
	var shift: Vector2 = _torso_shift_cells(progress)
	_torso.position = _torso_base + shift * _hero_scale
	var origin: Vector2 = cell_to_local(
		Vector2.ZERO, _sprite_base_y, _hero_scale, shift)
	_arm_main.cell_origin = origin
	_arm_main.cell_scale = _hero_scale
	if _arm_off != null:
		_arm_off.cell_origin = origin
		_arm_off.cell_scale = _hero_scale
	_step_attack_gait(maxf(delta, 0.0))
	var target: Vector2 = _main_wrist_target(progress)
	if _debug_arm_freeze:
		_arm_main.pose(_arm_main.rest_wrist_cell())
		_pose_off_hand(progress, true)
		_rig.position = cell_to_local(
			target, _sprite_base_y, _hero_scale, shift) \
			+ seat_offset_for(_hero_profile, _rig.attack_aim())
	else:
		_arm_main.pose(target)
		_pose_off_hand(progress)
		_rig.position = cell_to_local(
			_arm_main.wrist_cell(), _sprite_base_y, _hero_scale, shift) \
			+ seat_offset_for(_hero_profile, _rig.attack_aim())
	_update_brace_seat(shift)


## Live gait under the attack: the hidden sprite keeps stepping at its own
## walk/idle rate, and the drawn legs mirror its sheet and frame, so thighs,
## knees, and boots all travel while the body holds its aim. Stationary idle
## barely advances, so planted feet stay planted. Walk/idle and facing
## switches preserve the stride progress in frames, never the frame alone,
## so the clock never steps backward.
func _step_attack_gait(delta: float) -> void:
	if _hero == null or _legs == null:
		return
	var want: StringName = StringName(
		("walk_" if _walking else "idle_") + FACING_NAMES[facing])
	if _sprite.animation != want:
		var old_fps: float = _hero.walk_fps \
			if str(_sprite.animation).begins_with("walk_") \
			else _hero.idle_fps
		var progress: float = _gait_time * old_fps
		_sprite.animation = want
		var new_fps: float = _gait_fps()
		var frames: int = maxi(_gait_frames(), 1)
		_gait_time = progress / maxf(new_fps, 1.0)
		_sprite.set_frame_and_progress(
			int(progress) % frames, fposmod(progress, 1.0))
	elif delta > 0.0:
		_gait_time += delta
		var stepped: float = _gait_time * _gait_fps()
		_sprite.set_frame_and_progress(
			int(stepped) % maxi(_gait_frames(), 1),
			fposmod(stepped, 1.0))
	_update_attack_legs()


## Drawn legs follow the hidden sprite: same sheet, same column, same frame,
## cropped below the cutline. The whole strip steps, never just the boots.
func _update_attack_legs() -> void:
	if _hero == null or _legs == null or _legs.texture == null:
		return
	var geometry: Dictionary = rig_geometry_for(_hero_id)
	var cutline: float = float(geometry.get("cutline", 156))
	var cell: Vector2i = _hero.sprite_cell
	var sheet: Texture2D = _hero.walk_sheet \
		if str(_sprite.animation).begins_with("walk_") else _hero.idle_sheet
	var atlas: AtlasTexture = _legs.texture as AtlasTexture
	if atlas == null:
		return
	atlas.atlas = sheet
	atlas.region = Rect2(int(facing) * cell.x,
		_sprite.frame * cell.y + cutline, cell.x, cell.y - cutline)


func _gait_fps() -> float:
	if _hero == null:
		return 9.0
	return _hero.walk_fps if _walking else _hero.idle_fps


func _gait_frames() -> int:
	if _hero == null:
		return 4
	return _hero.walk_frames if _walking else _hero.idle_frames


## Off hand per hero: Dancer's brace holds still, Eclipse's mirror sweeps
## with the cutter, Eclipse's profile nub stacks on the main grip. Frozen
## holds rest everywhere (the nub stacks on the resting main wrist).
func _pose_off_hand(progress: float, frozen: bool = false) -> void:
	if _hero_profile == Hero.AttackProfile.DANCER:
		if _arm_off != null and _arm_off.visible:
			_arm_off.pose(_arm_off.rest_wrist_cell())
	elif _hero_profile == Hero.AttackProfile.ECLIPSE:
		if _arm_off != null and _arm_off.visible:
			if frozen:
				_arm_off.pose(_arm_off.rest_wrist_cell())
				return
			_arm_off.pose(_arc_wrist_target(_arm_off.rest_wrist_cell(),
				_arm_off.shoulder_cell(), ARM_SWING_ECLIPSE, progress))
		elif _nub != null and _nub.visible:
			var entry: Dictionary = (rig_geometry_for(_hero_id).get(
				"facings", {}) as Dictionary).get(_attack_facing, {})
			var stack: Array = (entry.get("nub_off", {}) as Dictionary).get(
				"stack", [0, 3])
			var stack_vec := Vector2(float(stack[0]), float(stack[1]))
			_nub.position = cell_to_local(
				_arm_main.wrist_cell() + stack_vec,
				_sprite_base_y, _hero_scale, _current_shift_cells())


func _current_shift_cells() -> Vector2:
	var progress: float = _rig.attack_progress()
	if progress < 0.0:
		progress = 0.0
	return _torso_shift_cells(progress)


## Brace fang seat for Dancer: the bracing wrist in rig-local coords, so the
## off fang rides its own real hand while the cutter sweeps.
func _update_brace_seat(shift: Vector2) -> void:
	if _hero_profile != Hero.AttackProfile.DANCER:
		_rig.brace_local = Vector2.ZERO
		return
	var brace_cell: Vector2
	if _arm_off != null and _arm_off.visible:
		brace_cell = _arm_off.wrist_cell()
	else:
		var entry: Dictionary = (rig_geometry_for(_hero_id).get(
			"facings", {}) as Dictionary).get(_attack_facing, {})
		var grips: Dictionary = entry.get("static_grips", {})
		var pt: Array = (grips.get("far", [72, 96]) as Array)
		brace_cell = Vector2(float(pt[0]), float(pt[1]))
	_rig.brace_local = cell_to_local(
		brace_cell, _sprite_base_y, _hero_scale, shift) - _rig.position


## Rest seat: weapon in the painted wrist of the held aim's facing, brace
## fang in its own hand, both fangs gripped. Recomputes from the held aim so
## even a directly poked rig position comes home.
func _update_rest_seat() -> void:
	if _rig == null:
		return
	var aim: Vector2 = _rig.aim()
	_rig.position = rest_rig_seat(aim)
	_rig.main_half = &"upper"
	_rig.brace_half = &"lower"
	_rig.brace_local = Vector2.ZERO
	if _hero_profile != Hero.AttackProfile.DANCER:
		return
	var facing_name: String = facing_for(aim)
	var geometry: Dictionary = rig_geometry_for(_hero_id)
	var entry: Dictionary = (geometry.get("facings", {}) as Dictionary).get(
		facing_name, {})
	var brace_cell := Vector2(72, 96)
	if facing_name == "down" or facing_name == "up":
		brace_cell = _rest_cell_of(entry, "left")
	else:
		var grips: Dictionary = entry.get("static_grips", {})
		var pt: Array = grips.get("far", [72, 96])
		brace_cell = Vector2(float(pt[0]), float(pt[1]))
	_rig.brace_local = cell_to_local(
		brace_cell, _sprite_base_y, _hero_scale) - _rig.position


func _rest_cell_of(entry: Dictionary, side: String) -> Vector2:
	var arms: Dictionary = entry.get("arms", {})
	if arms.has(side):
		var wrist: Array = (arms[side] as Dictionary).get("W", [72, 96])
		return Vector2(float(wrist[0]), float(wrist[1]))
	return Vector2(72, 96)


## End the split: settle the rig, hide the pose, show the sprite. The hidden
## sprite kept stepping through the attack, so the restore resumes its live
## frame and sub-frame progress instead of the swap frame, never replaying
## into frame zero. Always re-seats the weapon, so a mid-attack cancel
## leaves nothing offset.
func _end_attack_pose() -> void:
	_face_hold = 0.0
	if _rig != null:
		_rig.clear_attack()
	if not _split_shown:
		return
	_split_shown = false
	_arm_main.pose(_arm_main.rest_wrist_cell())
	if _arm_off != null and _arm_off.visible:
		_arm_off.pose(_arm_off.rest_wrist_cell())
	_legs.visible = false
	_torso.visible = false
	_arm_main.visible = false
	if _arm_off != null:
		_arm_off.visible = false
	if _nub != null:
		_nub.visible = false
	if _sprite != null:
		_sprite.visible = true
		_resume_attack_gait()
	_update_rest_seat()


## Resume the baked clock after the attack split: the explicit gait clock
## hands its frame and sub-frame progress back to the sprite, which resumes
## playing from there. Setting the animation or replaying it would park on
## frame zero, so the seat is applied after the switch and the clock resumes
## with a nameless play.
func _resume_attack_gait() -> void:
	if _sprite == null:
		return
	if _hero == null:
		_play_current()
		return
	var want: StringName = StringName(
		("walk_" if _walking else "idle_") + FACING_NAMES[facing])
	var old_fps: float = _hero.walk_fps \
		if str(_sprite.animation).begins_with("walk_") \
		else _hero.idle_fps
	var progress: float = _gait_time * old_fps
	if _sprite.animation != want:
		_sprite.animation = want
		var new_fps: float = _gait_fps()
		_gait_time = progress / maxf(new_fps, 1.0)
	var frames: int = maxi(_gait_frames(), 1)
	_sprite.set_frame_and_progress(
		int(progress) % frames, fposmod(progress, 1.0))
	_sprite.play()


## Pass Arena's moonfire awakening state to the body-side marker.
func set_moonfire(value: bool, locked: bool = false) -> void:
	if value:
		_ensure_moonfire().set_active(true, locked)
	elif _moonfire != null:
		_moonfire.set_active(false, locked)


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
	# A live primary keeps facing its target through the dash; the pose
	# finishes its span and settles while the body slides. The rig itself
	# is the hold, so an exhausted countdown never turns the body early.
	if _face_hold <= 0.0 and not _attack_rig_live():
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
		if _moonfire != null:
			_moonfire.visible = true
		if _rig != null:
			_rig.visible = true
		if _hero_profile == Hero.AttackProfile.ECLIPSE:
			_ensure_scythe()
		if _scythe != null:
			_scythe.set_active(_hero_profile == Hero.AttackProfile.ECLIPSE)
		return
	_dash_streak_left = 0.0
	_continue_burst_left = 0.0
	if _slash_play != null and _slash_play.is_valid():
		_slash_play.kill()
	_end_attack_pose()
	if _rig != null:
		_rig.clear()
		_rig.visible = false
	if _scythe != null:
		_scythe.set_active(false)
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
	if _moonfire != null:
		_moonfire.set_active(false)
		_moonfire.visible = false
	for ghost in get_tree().get_nodes_in_group(&"player_afterimages"):
		if is_instance_valid(ghost):
			ghost.queue_free()
	queue_redraw()


## Draw-layer VFX suppression for the motion harness no-VFX pass. Production
## attack methods run normally — cues just draw dark — while the physical
## weapon, arms, and body stay visible. Production never calls this.
func set_vfx_suppressed(value: bool) -> void:
	_vfx_suppressed = value
	if _rig != null:
		_rig.set_vfx_suppressed(value)
	if _scythe != null:
		_scythe.set_vfx_suppressed(value)
	if _moonlight_cast != null:
		_moonlight_cast.set_vfx_suppressed(value)
	if value:
		_dash_streak_left = 0.0
		_continue_burst_left = 0.0
		_slash.visible = false
		if _slash_back != null and is_instance_valid(_slash_back):
			_slash_back.visible = false
		_full_wave = -1.0
		_starfall_preview = -1.0
		_slash_echo_wave = -1.0
		_ring.visible = false
		if _moonfire != null:
			_moonfire.visible = false
	else:
		_ring.visible = true
		if _moonfire != null:
			_moonfire.visible = true
	queue_redraw()


func debug_direction_capture_vfx_hidden() -> bool:
	if not OS.is_debug_build():
		return false
	var slash_back_hidden: bool = _slash_back == null \
		or not is_instance_valid(_slash_back) or not _slash_back.visible
	return _debug_direction_capture_vfx_suppressed \
		and not _moonlight_cast.visible and not _ring.visible \
		and (_moonfire == null or not _moonfire.visible) \
		and not _slash.visible and slash_back_hidden \
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
	if _scythe != null:
		_scythe.set_active(_hero_profile == Hero.AttackProfile.ECLIPSE
			and not _debug_direction_capture_vfx_suppressed)
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
	if _moonfire != null:
		_moonfire.set_active(false)
	_end_attack_pose()
	if _rig != null:
		_rig.clear()
	if _scythe != null:
		_scythe.set_active(false)
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

	# A primary attack faces its target until the actual rig finishes while
	# locomotion continues underneath; movement re-faces once it does. The
	# physics countdown and the rig clock tick separately, so the countdown
	# alone must never release the hold early.
	_face_hold = maxf(_face_hold - delta, 0.0)
	if _face_hold <= 0.0 and not _attack_rig_live():
		face_toward(_wish)
	set_walking(velocity.length() > WALK_THRESHOLD)
	_update_attack_pose(delta)


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
	# Every cue below is VFX: burst, streak, echoes, previews. The no-VFX
	# pass keeps only the body, arms, and held weapon.
	if _vfx_suppressed:
		return
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


## Face a primary target without losing the stride. `face_toward` replays the
## baked walk/idle from frame zero on a direction change, which is right for
## ordinary stick turns — but a first attack turning to its target must keep
## the current frame and sub-frame progress, exactly like a mid-attack
## retrigger, so the split entry seeds from the live stride. Only the two
## primary entries call this; sidearms never face at all.
func _face_primary_target(direction: Vector2) -> void:
	if _sprite == null or _split_shown:
		face_toward(direction)
		return
	var held_frame: int = _sprite.frame
	var held_progress: float = _sprite.frame_progress
	face_toward(direction)
	_sprite.set_frame_and_progress(
		held_frame % maxi(_gait_frames(), 1), held_progress)


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


## Whether the held weapon is mid-cut or mid-kick. The facing hold reads
## this, never the countdown alone: the two clocks tick separately.
func _attack_rig_live() -> bool:
	return _rig != null and _rig.attack_live()


## Drive the live attack split, and settle it the tick the motion ends. A
## directly poked rig still poses; an ended one always comes home. Called
## every physics tick, and directly by tests and harnesses that drive the rig
## by hand with the same step size.
func _update_attack_pose(delta: float = 0.0) -> void:
	if _rig == null or _sprite == null:
		return
	if _rig.attack_live():
		if _split_shown:
			_refresh_attack_rig(delta)
		else:
			face_toward(_rig.attack_aim())
			_face_hold = maxf(_face_hold, _rig.attack_span() \
				* (1.0 - _rig.attack_progress()))
			_begin_attack_pose()
	elif _split_shown:
		_end_attack_pose()


## Play the baked walk/idle for the current state. While the attack split
## shows, the hidden sprite stays paused and `_step_attack_gait` owns its
## frame, so this stages nothing and never starts a second clock.
func _play_current() -> void:
	if _split_shown:
		return
	var want: String = ("walk_" if _walking else "idle_") \
		+ FACING_NAMES[facing]
	if _sprite.animation != StringName(want):
		_sprite.play(want)
	elif not _sprite.is_playing():
		_sprite.play()
