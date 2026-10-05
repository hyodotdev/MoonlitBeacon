class_name WeaponRig
extends Node2D

## Bounded painted weapon layer for the chosen hero.
##
## One node, one supersampled sheet: the little guardian's held weapon plus a
## brief muzzle/cut flash on each shot. The six sheets are the original painted
## equipment packed by `tools/pack_painted_weapons.py` — sword, twin daggers,
## lantern pistol, ring cannon, crescent reaper, needle rifle — each holding
## four texels per logical pixel and drawn at 0.25 world scale through
## per-item Linear filtering, so the paint stays smooth at real 2x/3x output
## where a 1:1 nearest bitmap would collapse into blocks.
##
## Two spaces, one transform. Logical space is the round-1 geometry the game
## plays in: tips, grips, axis rows, muzzle seats. Texture space is exactly
## four times logical. Guns align by barrel axis: the painted tip lands
## exactly on the muzzle seat (`muzzle_length`), so the tip and the real
## projectile spawn coincide. Melee weapons align by grip: the hand holds the
## handle 2px behind the rig origin and the blade follows the aim. Aims
## pointing left mirror the sheet about its axis so lamp, sight and guard
## details never hang upside down.
##
## The sheets are lit art like the hero sheets, so they wear the hero's own
## readability tint and show their paint as-is under the Player night tint.
## Flash strokes keep the legacy boost explicitly, with anti-aliased edges.
##
## Flashes die on their own in ≤0.2s, freeze with the tree under pause/result, and
## leave with the player on scene change. `clear()` drops them immediately.
## The pose itself never moves on its own: no idle motion can imply a shot
## that did not happen. Every physical attack below starts at a real combat
## event, crosses the contact/discharge aim at that instant, and settles back
## to this exact rest pose.
##
## Attack motion. A primary attack carries the held sheet through a short
## deterministic timeline: melee blades sweep a cut (Warden broad, Dancer one
## fang at a time alternating handles, Eclipse a long crescent), guns kick
## back along the aim and pitch (Keeper snap, Knight heavy, Sage precise).
## The Player's painted arm chains carry the grip through the same motion, so
## the hand visibly holds the weapon; the node only rotates the sheet about
## the seated grip while the arm moves it. Sidearm cues light a flash at
## their own direction but never turn, move, or restart the held primary.

## Flash kinds. Cut ticks ride melee swings; muzzle kinds ride ranged volleys.
const CUT: StringName = &"cut"
const TWIN_CUT: StringName = &"twin_cut"
const RING_PULSE: StringName = &"ring_pulse"
const MUZZLE_RIFLE: StringName = &"muzzle_rifle"
const MUZZLE_SCATTER: StringName = &"muzzle_scatter"
const MUZZLE_CANNON: StringName = &"muzzle_cannon"
const MUZZLE_SPARK: StringName = &"muzzle_spark"

const FLASH_SECONDS: float = 0.16
const CANNON_FLASH_SECONDS: float = 0.22
## Flash seat per muzzle kind, px past the grip along the aim: needle 16,
## bell 9, ring 9, spark 9. The projectile spawns on the same seat
## (`Player.muzzle_origin`), so one fired shot has one origin on screen
## and in flight.
const MUZZLE_RIFLE_SEAT: float = 16.0
const MUZZLE_SCATTER_SEAT: float = 9.0
const MUZZLE_CANNON_SEAT: float = 9.0
const MUZZLE_SPARK_SEAT: float = 9.0

## Texture texels per logical pixel. Sheets are exactly this many times the
## logical size; the draw below compensates with DRAW_SCALE.
const TEXTURE_SCALE: float = 4.0
const DRAW_SCALE: float = 1.0 / TEXTURE_SCALE

## Painted sheets, one per hero, packed from the painted-weapons master.
const SHEET_WARDEN: Texture2D = preload("res://assets/custom/items/weapons/warden.png")
const SHEET_DANCER: Texture2D = preload("res://assets/custom/items/weapons/dancer.png")
const SHEET_KEEPER: Texture2D = preload("res://assets/custom/items/weapons/keeper.png")
const SHEET_KNIGHT: Texture2D = preload("res://assets/custom/items/weapons/knight.png")
const SHEET_ECLIPSE: Texture2D = preload("res://assets/custom/items/weapons/eclipse.png")
const SHEET_SAGE: Texture2D = preload("res://assets/custom/items/weapons/sage.png")

## Calibrated tips in logical pixels: the painted muzzle for guns (which the
## pivot seats exactly on the muzzle length), the blade end for melee.
## Frozen from the round-1 source calibration; texture tips are exactly four
## times these, and the weapon test guards both against the committed sheets.
const LOGICAL_TIP_WARDEN: Vector2i = Vector2i(15, 2)
const LOGICAL_TIP_DANCER: Vector2i = Vector2i(13, 4)
const LOGICAL_TIP_KEEPER: Vector2i = Vector2i(13, 2)
const LOGICAL_TIP_KNIGHT: Vector2i = Vector2i(13, 3)
const LOGICAL_TIP_ECLIPSE: Vector2i = Vector2i(15, 4)
const LOGICAL_TIP_SAGE: Vector2i = Vector2i(20, 3)
## Calibrated grips in logical pixels: the hand point for melee heroes. Gun
## heroes seat the barrel axis instead (see `logical_pivot`).
const LOGICAL_GRIP_WARDEN: Vector2i = Vector2i(1, 2)
const LOGICAL_GRIP_DANCER: Vector2i = Vector2i(1, 4)
const LOGICAL_GRIP_ECLIPSE: Vector2i = Vector2i(1, 4)
## Barrel-axis rows in logical pixels for the three guns. Symmetric bell lips
## and ring aperture center on them; the needle ends on its own.
const LOGICAL_AXIS_KEEPER: int = 2
const LOGICAL_AXIS_KNIGHT: int = 3
const LOGICAL_AXIS_SAGE: int = 3
## Twin-dagger handle rows in logical pixels. The pair straddles the grip row
## the way the twin tips straddle the tip row.
const LOGICAL_DANCER_UPPER_ROW: int = 2
const LOGICAL_DANCER_LOWER_ROW: int = 6
## Legacy hand point, px behind the rig origin along the aim. Melee grips sit
## here; gun pivots sit on the origin with the muzzle ahead on the seat.
const GRIP_BACK: float = 2.0
## Sheet tint. Must equal `Player.HERO_READABILITY_TINT`: the node itself no
## longer boosts, so the paint shows exactly as the file holds it.
const PAINT_TINT: Color = Color(3.175, 2.857, 1.754, 1.0)
## Legacy flash boost, now explicit per stroke. The node carries no boost, so
## each flame color is scaled by the old self_modulate (2.4, 2.4, 2.5) and
## reads on screen exactly as before.
const FLASH_BOOST: Vector3 = Vector3(2.4, 2.4, 2.5)

## Attack motion kinds. Swings rotate the blade through a cut; shots slide the
## gun back along the aim. Zero means settled at the rest pose.
const ATK_NONE: int = 0
const ATK_SWING: int = 1
const ATK_SHOT: int = 2

## Base spans, seconds. Melee spans shrink to 90% of the live attack interval
## (`attack_span_for`), so a hasted build never overlaps its own cut; ranged
## bases already sit under the 0.34s volley floor's 0.306s bound.
const SWING_SPAN_WARDEN: float = 0.24
const SWING_SPAN_DANCER: float = 0.18
const SWING_SPAN_ECLIPSE: float = 0.28
const SHOT_SPAN_KEEPER: float = 0.16
const SHOT_SPAN_KNIGHT: float = 0.18
const SHOT_SPAN_SAGE: float = 0.14
## Envelope peaks as fractions of the span: the cut/slide climbs to its extreme
## here, then settles back. Discharge peaks stay near the front so the kick
## reads inside one strip frame.
const SWING_PEAK_ANGLE: float = 0.40
const SWING_PEAK_PUSH: float = 0.35
const SHOT_PEAK_SLIDE: float = 0.22
const SHOT_PEAK_PITCH: float = 0.26

## Sweep travels, degrees. The blade points exactly along the contact aim at
## t=0 and follows through this far before settling back. Each holds a margin
## above its 90/60/120 minimum.
const SWING_TRAVEL_WARDEN: float = 100.0
const SWING_TRAVEL_DANCER: float = 75.0
const SWING_TRAVEL_ECLIPSE: float = 135.0

## Gun kick back along the aim at the discharge peak, px, and muzzle pitch,
## radians. Negative pitch reads as rise on screen for side aims.
const SHOT_SLIDE_KEEPER: float = 4.0
const SHOT_SLIDE_KNIGHT: float = 7.0
const SHOT_SLIDE_SAGE: float = 2.5
const SHOT_PITCH_KEEPER: float = -0.14
const SHOT_PITCH_KNIGHT: float = -0.21
const SHOT_PITCH_SAGE: float = 0.07

## Dancer per-dagger pivots and tips in logical px. Each action seats and swings
## one fang from its own handle, so the pair never rotates as one rigid icon.
const LOGICAL_PIVOT_DANCER_UPPER: Vector2 = Vector2(1.0, 2.5)
const LOGICAL_PIVOT_DANCER_LOWER: Vector2 = Vector2(1.0, 5.5)
const LOGICAL_TIP_DANCER_UPPER: Vector2 = Vector2(13.0, 2.5)
const LOGICAL_TIP_DANCER_LOWER: Vector2 = Vector2(13.0, 5.5)
## Half-sheet source rects in texels. They overlap one row on the near-empty gap
## band so neither fang loses its fringe at the split.
const DANCER_UPPER_RECT: Rect2i = Rect2i(0, 0, 60, 19)
const DANCER_LOWER_RECT: Rect2i = Rect2i(0, 17, 60, 19)

## Gun hand point: px behind the seated pivot along the aim where the
## painted hand grips the stock.
const GUN_GRIP_BACK_KEEPER: float = 2.0
const GUN_GRIP_BACK_KNIGHT: float = 2.0
const GUN_GRIP_BACK_SAGE: float = 3.0

var _profile: Hero.AttackProfile = Hero.AttackProfile.WARDEN
var _primary: Color = Color(0.3, 0.68, 1.0, 1.0)
var _secondary: Color = Color(0.82, 0.95, 1.0, 1.0)
var _aim: Vector2 = Vector2.RIGHT
var _kind: StringName = &""
var _age: float = 999.0
var _span: float = FLASH_SECONDS
var _kind_sidearm: bool = false
## Direction the live flash draws along. The held weapon keeps `_aim`; a
## sidearm cue burns at its own direction without relocating the primary.
var _flash_aim: Vector2 = Vector2.RIGHT
## Live attack motion. Kind, frozen aim, age, and span; sign and variant pick
## the cut (Warden/Eclipse alternate sides, Dancer alternates fangs).
var _attack_kind: int = ATK_NONE
var _attack_aim: Vector2 = Vector2.RIGHT
var _attack_age: float = -1.0
var _attack_span: float = 0.2
var _attack_sign: float = 1.0
var _attack_variant: int = 0
var _swing_sign: float = 1.0
var _dancer_action: int = 0
## Dancer halves: which fang cuts (seated on this origin through the live cut
## angle) and which braces (seated on `brace_local` along the held aim). The
## Player assigns both at rest and per attack, so each fang keeps its own hand.
var main_half: StringName = &"upper"
var brace_half: StringName = &"lower"
var brace_local: Vector2 = Vector2.ZERO
## Draw-layer VFX suppression for the motion harness no-VFX pass. Flashes draw
## dark; the held sheets still draw through the live transform.
var _vfx_suppressed: bool = false


func _ready() -> void:
	z_index = 2
	# The node carries no boost: sheets wear PAINT_TINT and flames FLASH_BOOST,
	# so neither washes out nor sinks under the Player night tint.
	self_modulate = Color.WHITE
	# The 4x sheets filter per item. Global Nearest stays locked for the pixel
	# world; the painted metal resolves through Linear instead of blocking up.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func configure(
	profile: Hero.AttackProfile, primary: Color, secondary: Color,
) -> void:
	_profile = profile
	_primary = primary
	_secondary = secondary
	clear_attack()
	_swing_sign = 1.0
	_dancer_action = 0
	queue_redraw()


## Last aim direction, so the held weapon points where the last shot went.
func aim() -> Vector2:
	return _aim


## Sheet id for one profile, for tests and harnesses that only know the hero.
static func painted_name(profile: Hero.AttackProfile) -> String:
	match profile:
		Hero.AttackProfile.DANCER:
			return "dancer"
		Hero.AttackProfile.KEEPER:
			return "keeper"
		Hero.AttackProfile.KNIGHT:
			return "knight"
		Hero.AttackProfile.ECLIPSE:
			return "eclipse"
		Hero.AttackProfile.SAGE:
			return "sage"
	return "warden"


## Painted sheet for one profile.
static func painted_sheet(profile: Hero.AttackProfile) -> Texture2D:
	match profile:
		Hero.AttackProfile.DANCER:
			return SHEET_DANCER
		Hero.AttackProfile.KEEPER:
			return SHEET_KEEPER
		Hero.AttackProfile.KNIGHT:
			return SHEET_KNIGHT
		Hero.AttackProfile.ECLIPSE:
			return SHEET_ECLIPSE
		Hero.AttackProfile.SAGE:
			return SHEET_SAGE
	return SHEET_WARDEN


## Calibrated tip for one profile, in logical pixels.
static func logical_tip(profile: Hero.AttackProfile) -> Vector2i:
	match profile:
		Hero.AttackProfile.DANCER:
			return LOGICAL_TIP_DANCER
		Hero.AttackProfile.KEEPER:
			return LOGICAL_TIP_KEEPER
		Hero.AttackProfile.KNIGHT:
			return LOGICAL_TIP_KNIGHT
		Hero.AttackProfile.ECLIPSE:
			return LOGICAL_TIP_ECLIPSE
		Hero.AttackProfile.SAGE:
			return LOGICAL_TIP_SAGE
	return LOGICAL_TIP_WARDEN


## Sheet point placed at the rig anchor, in logical pixels. Gun pivots sit one
## muzzle seat behind the painted tip on the barrel axis, so the tip always
## lands on the seat even if a seat constant moves; melee pivots are the
## grips themselves.
static func logical_pivot(profile: Hero.AttackProfile) -> Vector2:
	match profile:
		Hero.AttackProfile.KEEPER:
			return Vector2(
				float(LOGICAL_TIP_KEEPER.x) - muzzle_length(MUZZLE_SCATTER),
				float(LOGICAL_AXIS_KEEPER))
		Hero.AttackProfile.KNIGHT:
			return Vector2(
				float(LOGICAL_TIP_KNIGHT.x) - muzzle_length(MUZZLE_CANNON),
				float(LOGICAL_AXIS_KNIGHT))
		Hero.AttackProfile.SAGE:
			return Vector2(
				float(LOGICAL_TIP_SAGE.x) - muzzle_length(MUZZLE_RIFLE),
				float(LOGICAL_AXIS_SAGE))
		Hero.AttackProfile.DANCER:
			return Vector2(LOGICAL_GRIP_DANCER)
		Hero.AttackProfile.ECLIPSE:
			return Vector2(LOGICAL_GRIP_ECLIPSE)
	return Vector2(LOGICAL_GRIP_WARDEN)


## The same pivot in texture texels. Exactly TEXTURE_SCALE times logical, so
## the drawn sheet and the logical math cannot drift apart.
static func texture_pivot(profile: Hero.AttackProfile) -> Vector2:
	return logical_pivot(profile) * TEXTURE_SCALE


## Rig-local anchor the pivot sits on for one aim. Guns pivot on the origin
## with the muzzle ahead; melee grips hang 2px toward the body.
static func painted_anchor(profile: Hero.AttackProfile, aim: Vector2) -> Vector2:
	if HeroWeapons.primary_side(profile) == HeroWeapons.Side.RANGED:
		return Vector2.ZERO
	var flat: Vector2 = aim.normalized() if aim.length() > 0.01 else Vector2.RIGHT
	return -flat * GRIP_BACK


## World position of one logical sheet point for one aim: the single
## world-space transform the draw below and the tests share. Left aims mirror
## about the sheet axis row.
static func drawn_logical_point(
	profile: Hero.AttackProfile, aim: Vector2, logical_point: Vector2
) -> Vector2:
	var rel: Vector2 = logical_point - logical_pivot(profile)
	if aim.x < 0.0:
		rel.y = -rel.y
	return painted_anchor(profile, aim) + rel.rotated(aim.angle())


## Muzzle seat for one flash kind: the shared number the drawing and the
## projectile spawn both stand on.
static func muzzle_length(kind: StringName) -> float:
	match kind:
		MUZZLE_RIFLE:
			return MUZZLE_RIFLE_SEAT
		MUZZLE_SCATTER:
			return MUZZLE_SCATTER_SEAT
		MUZZLE_CANNON:
			return MUZZLE_CANNON_SEAT
	return MUZZLE_SPARK_SEAT


## Attack span for one profile: the base motion, shrunk to 90% of the live
## attack interval when one is known so the cut always settles before the next.
static func attack_span_for(profile: Hero.AttackProfile, cooldown: float) -> float:
	var base: float = SHOT_SPAN_SAGE
	match profile:
		Hero.AttackProfile.WARDEN:
			base = SWING_SPAN_WARDEN
		Hero.AttackProfile.DANCER:
			base = SWING_SPAN_DANCER
		Hero.AttackProfile.ECLIPSE:
			base = SWING_SPAN_ECLIPSE
		Hero.AttackProfile.KEEPER:
			base = SHOT_SPAN_KEEPER
		Hero.AttackProfile.KNIGHT:
			base = SHOT_SPAN_KNIGHT
	if cooldown > 0.0:
		return minf(base, cooldown * 0.9)
	return base


## Motion envelope: exactly 0 at both ends, 1 at `peak`, smooth between. Every
## cut, kick, and lunge rides this, so each settles exactly where it rested.
static func attack_envelope(progress: float, peak: float) -> float:
	if progress <= 0.0 or progress >= 1.0:
		return 0.0
	var rise: float = smoothstep(0.0, peak, progress)
	var fall: float = 1.0 - smoothstep(peak, 1.0, progress)
	return minf(rise, fall)


## Blade rotation at one progress point, radians. Zero at both ends; the sign
## picks forehand/backhand, the variant the Dancer fang (kept for symmetry —
## both fangs sweep the same travel in opposite directions).
static func swing_angle_at(
	profile: Hero.AttackProfile, _variant: int, sign: float, progress: float
) -> float:
	var travel: float = SWING_TRAVEL_WARDEN
	match profile:
		Hero.AttackProfile.DANCER:
			travel = SWING_TRAVEL_DANCER
		Hero.AttackProfile.ECLIPSE:
			travel = SWING_TRAVEL_ECLIPSE
	return deg_to_rad(travel) * attack_envelope(progress, SWING_PEAK_ANGLE) * sign


## Gun slide back along the aim at one progress point, px.
static func shot_slide_at(profile: Hero.AttackProfile, progress: float) -> float:
	var slide: float = SHOT_SLIDE_SAGE
	match profile:
		Hero.AttackProfile.KEEPER:
			slide = SHOT_SLIDE_KEEPER
		Hero.AttackProfile.KNIGHT:
			slide = SHOT_SLIDE_KNIGHT
	return slide * attack_envelope(progress, SHOT_PEAK_SLIDE)


## Muzzle pitch at one progress point, radians.
static func shot_pitch_at(profile: Hero.AttackProfile, progress: float) -> float:
	var pitch: float = SHOT_PITCH_SAGE
	match profile:
		Hero.AttackProfile.KEEPER:
			pitch = SHOT_PITCH_KEEPER
		Hero.AttackProfile.KNIGHT:
			pitch = SHOT_PITCH_KNIGHT
	return pitch * attack_envelope(progress, SHOT_PEAK_PITCH)


## Stock hand point for one gun profile: px behind the seated pivot along the
## barrel axis where the painted hand grips. Melee grips sit on the pivot
## itself, so this is zero for them.
static func stock_back(profile: Hero.AttackProfile) -> float:
	match profile:
		Hero.AttackProfile.KEEPER:
			return GUN_GRIP_BACK_KEEPER
		Hero.AttackProfile.KNIGHT:
			return GUN_GRIP_BACK_KNIGHT
		Hero.AttackProfile.SAGE:
			return GUN_GRIP_BACK_SAGE
	return 0.0


## Dancer fang geometry for one half name: handle pivot, tip, source rect.
static func dancer_half_pivot(half: StringName) -> Vector2:
	if half == &"lower":
		return LOGICAL_PIVOT_DANCER_LOWER
	return LOGICAL_PIVOT_DANCER_UPPER


static func dancer_half_tip(half: StringName) -> Vector2:
	if half == &"lower":
		return LOGICAL_TIP_DANCER_LOWER
	return LOGICAL_TIP_DANCER_UPPER


static func dancer_half_rect(half: StringName) -> Rect2i:
	if half == &"lower":
		return DANCER_LOWER_RECT
	return DANCER_UPPER_RECT


## Dancer pivot and tip for one fang action: 0 upper, 1 lower.
static func dancer_action_pivot(variant: int) -> Vector2:
	return dancer_half_pivot(&"lower" if variant == 1 else &"upper")


static func dancer_action_tip(variant: int) -> Vector2:
	return dancer_half_tip(&"lower" if variant == 1 else &"upper")


## Start the melee cut: the blade crosses `aim` now and follows through across
## `span`. Returns the cut sign. Dancer alternates fangs (upper forehand, lower
## backhand); Warden and Eclipse alternate sides. Restarting mid-cut restarts
## cleanly, so rapid relic attacks never stack offsets.
func play_primary_swing(aim: Vector2, span: float) -> float:
	if aim.length() > 0.01:
		_aim = aim.normalized()
	_attack_kind = ATK_SWING
	_attack_aim = _aim
	_attack_age = 0.0
	_attack_span = maxf(span, 0.01)
	if _profile == Hero.AttackProfile.DANCER:
		_attack_variant = _dancer_action
		_attack_sign = 1.0 if _dancer_action == 0 else -1.0
		_dancer_action = 1 - _dancer_action
	else:
		_attack_variant = 0
		_attack_sign = _swing_sign
		_swing_sign = -_swing_sign
	set_process(true)
	queue_redraw()
	return _attack_sign


## Start the ranged discharge: the gun sits exactly on its muzzle now, kicks
## back across `span`, and settles exactly. Restarting mid-kick restarts cleanly.
func play_primary_shot(aim: Vector2, span: float) -> void:
	if aim.length() > 0.01:
		_aim = aim.normalized()
	_attack_kind = ATK_SHOT
	_attack_aim = _aim
	_attack_age = 0.0
	_attack_span = maxf(span, 0.01)
	_attack_variant = 0
	_attack_sign = 1.0
	set_process(true)
	queue_redraw()


## A cut or kick is still traveling.
func attack_live() -> bool:
	return _attack_kind != ATK_NONE and _attack_age >= 0.0 \
		and _attack_age < _attack_span


## Live motion progress 0..1, or -1 settled.
func attack_progress() -> float:
	if not attack_live():
		return -1.0
	return clampf(_attack_age / _attack_span, 0.0, 1.0)


func attack_kind() -> int:
	return _attack_kind if attack_live() else ATK_NONE


func attack_aim() -> Vector2:
	return _attack_aim


func attack_sign() -> float:
	return _attack_sign


func attack_variant() -> int:
	return _attack_variant


func attack_span() -> float:
	return _attack_span


## Current blade rotation, radians. Zero settled or mid-shot.
func swing_angle_now() -> float:
	if _attack_kind != ATK_SWING or not attack_live():
		return 0.0
	return swing_angle_at(
		_profile, _attack_variant, _attack_sign, attack_progress())


## Current muzzle pitch, radians. Zero settled or mid-swing.
func gun_pitch_now() -> float:
	if _attack_kind != ATK_SHOT or not attack_live():
		return 0.0
	return shot_pitch_at(_profile, attack_progress())


## Current weapon travel along the attack aim: the kick back on a shot. Zero
## settled, and zero on a cut — the blade rotates about the grip while the
## Player's arm carries the grip itself, so the node adds no translation.
func attack_shift_now() -> Vector2:
	if not attack_live():
		return Vector2.ZERO
	if _attack_kind == ATK_SHOT:
		return -_attack_aim * shot_slide_at(_profile, attack_progress())
	return Vector2.ZERO


## Current drawn aim angle: the held aim plus the live cut or pitch.
func draw_angle_now() -> float:
	return _aim.angle() + swing_angle_now() + gun_pitch_now()


## Current rig-local anchor the seated pivot sits on. The rest seat only: the
## Player carries the node itself through the travel, so adding it here too
## would apply it twice.
func draw_anchor_now() -> Vector2:
	return painted_anchor(_profile, _aim)


## Current rig-local pivot the sheet seats on: the cutting Dancer fang handle
## for the Dancer, the calibrated pivot otherwise.
func draw_pivot_now() -> Vector2:
	if _profile == Hero.AttackProfile.DANCER:
		return dancer_half_pivot(main_half)
	return logical_pivot(_profile)


## Current rig-local tip the sheet draws: the cutting Dancer fang tip for the
## Dancer, the calibrated tip otherwise.
func draw_tip_logical_now() -> Vector2:
	if _profile == Hero.AttackProfile.DANCER:
		return dancer_half_tip(main_half)
	return Vector2(logical_tip(_profile))


## One logical sheet point through the live transform: the single world-space
## mapping the draw and the tests share, motion included.
func drawn_point_now(logical_point: Vector2) -> Vector2:
	var rel: Vector2 = logical_point - draw_pivot_now()
	if _aim.x < 0.0:
		rel.y = -rel.y
	return draw_anchor_now() + rel.rotated(draw_angle_now())


## Current rig-local drawn tip.
func drawn_tip_now() -> Vector2:
	return drawn_point_now(draw_tip_logical_now())


## One logical sheet point of the bracing fang through its own transform:
## seated on `brace_local` along the held aim, never through the cut angle.
func drawn_brace_point_now(logical_point: Vector2) -> Vector2:
	var rel: Vector2 = logical_point - dancer_half_pivot(brace_half)
	if _aim.x < 0.0:
		rel.y = -rel.y
	return brace_local + rel.rotated(_aim.angle())


## Drop the live cut or kick and settle exactly. Keeps the aim and the
## alternation, so the next attack continues the sequence.
func clear_attack() -> void:
	_attack_kind = ATK_NONE
	_attack_age = -1.0
	_attack_variant = 0


## Light the flash. A sidearm cue never cuts a live primary flash short: the
## held weapon is the primary, so its flash owns the eye while it burns. A
## sidearm cue never turns the held weapon either: the flash burns at its own
## direction while the primary keeps its aim.
func flash(aim: Vector2, kind: StringName, sidearm: bool = false) -> void:
	if sidearm and _kind != &"" and _age < _span and not _kind_sidearm:
		return
	if aim.length() > 0.01:
		_flash_aim = aim.normalized()
		if not sidearm:
			_aim = _flash_aim
	_kind = kind
	_kind_sidearm = sidearm
	_age = 0.0
	_span = CANNON_FLASH_SECONDS if kind == MUZZLE_CANNON else FLASH_SECONDS
	set_process(true)
	queue_redraw()


func clear() -> void:
	_kind = &""
	_kind_sidearm = false
	_age = 999.0
	_flash_aim = _aim
	clear_attack()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	if _age >= _span:
		_kind = &""
		_kind_sidearm = false
	if _attack_kind != ATK_NONE:
		_attack_age += delta
		if _attack_age >= _attack_span:
			clear_attack()
	if _kind == &"" and _attack_kind == ATK_NONE:
		set_process(false)
	queue_redraw()


## Draw-layer VFX suppression for the motion harness no-VFX pass. Flashes
## draw dark; the held sheets still draw through the live transform.
func set_vfx_suppressed(value: bool) -> void:
	_vfx_suppressed = value
	queue_redraw()


func _draw() -> void:
	_draw_held()
	if _vfx_suppressed:
		return
	if _kind == &"" or _age >= _span:
		return
	var fade: float = 1.0 - _age / _span
	match _kind:
		CUT, TWIN_CUT:
			_draw_cut_flash(fade)
		RING_PULSE:
			_draw_ring_flash(fade)
		_:
			_draw_muzzle_flash(fade)


## The weapon in hand, aimed at the last shot. Six painted sheets that share
## no silhouette: curved sword, twin fangs, lantern pistol with its lamp,
## ring-muzzled cannon, crescent reaper, needle rifle with its sight bead.
## Left aims mirror about the sheet axis so the details stay upright.
##
## The transform is `drawn_point_now` in texture space: texel t lands at
## anchor + R·(mirror·((t − pivot·4)·0.25)), which equals the logical mapping
## for t = 4·L exactly. A live cut or kick rides the same angle, so the sheet
## and the measured tip cannot drift apart. The Player seats this node on the
## painted wrist, so the grip lands exactly on the hand with no drawn glove.
##
## The Dancer always draws two halves: the cutting fang from its own handle
## through the live cut angle, the bracing fang from its own hand along the
## held aim. The two actions never rotate one rigid icon.
func _draw_held() -> void:
	var sheet: Texture2D = painted_sheet(_profile)
	if sheet == null:
		return
	if _profile == Hero.AttackProfile.DANCER:
		_draw_dancer_half(sheet, main_half, draw_anchor_now(),
			draw_angle_now())
		_draw_dancer_half(sheet, brace_half, brace_local, _aim.angle())
	else:
		_draw_sheet_full(sheet, draw_angle_now(), draw_anchor_now(),
			texture_pivot(_profile))


## One full sheet through the live transform.
func _draw_sheet_full(
	sheet: Texture2D, angle: float, anchor: Vector2, pivot: Vector2
) -> void:
	var mirror := Vector2(1.0, 1.0)
	if _aim.x < 0.0:
		mirror = Vector2(1.0, -1.0)
	var scaled := Vector2(
		mirror.x * DRAW_SCALE, mirror.y * DRAW_SCALE)
	var seated := Vector2(pivot.x * scaled.x, pivot.y * scaled.y)
	draw_set_transform(anchor - seated.rotated(angle), angle, scaled)
	draw_texture(sheet, Vector2.ZERO, PAINT_TINT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One Dancer fang from its own handle through one anchor and angle. The
## source rect maps 1:1 onto the same canvas points, so texel t still lands
## exactly where the full-sheet math puts it.
func _draw_dancer_half(
	sheet: Texture2D, half: StringName, anchor: Vector2, angle: float
) -> void:
	var pivot: Vector2 = dancer_half_pivot(half) * TEXTURE_SCALE
	var src: Rect2i = dancer_half_rect(half)
	var size: Vector2i = sheet.get_size()
	src = src.intersection(Rect2i(Vector2i.ZERO, size))
	if src.size.x <= 0 or src.size.y <= 0:
		return
	var mirror := Vector2(1.0, 1.0)
	if _aim.x < 0.0:
		mirror = Vector2(1.0, -1.0)
	var scaled := Vector2(
		mirror.x * DRAW_SCALE, mirror.y * DRAW_SCALE)
	var seated := Vector2(pivot.x * scaled.x, pivot.y * scaled.y)
	draw_set_transform(anchor - seated.rotated(angle), angle, scaled)
	draw_texture_rect_region(sheet,
		Rect2(Vector2(src.position), Vector2(src.size)),
		Rect2(Vector2(src.position), Vector2(src.size)), PAINT_TINT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Legacy flame color through the explicit boost. Alpha rides untouched.
func _lit(color: Color) -> Color:
	return Color(
		color.r * FLASH_BOOST.x,
		color.g * FLASH_BOOST.y,
		color.b * FLASH_BOOST.z,
		color.a)


func _draw_cut_flash(fade: float) -> void:
	var angle: float = _flash_aim.angle()
	var light := Color(_secondary.r, _secondary.g, _secondary.b, 0.75 * fade)
	light = _lit(light)
	if _kind == TWIN_CUT:
		for offset in [-0.42, 0.42]:
			draw_arc(Vector2.ZERO, 12.0, angle - 0.5 + offset,
				angle + 0.5 + offset, 8, light, 2.0, true)
	else:
		draw_arc(Vector2.ZERO, 13.0, angle - 0.7, angle + 0.7, 10, light, 2.4, true)


func _draw_ring_flash(fade: float) -> void:
	var radius: float = 20.0 + (1.0 - fade) * 26.0
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 26,
		_lit(Color(_primary.r, _primary.g, _primary.b, 0.5 * fade)), 2.2, true)


func _draw_muzzle_flash(fade: float) -> void:
	var angle: float = _flash_aim.angle()
	var along: Vector2 = Vector2.RIGHT.rotated(angle)
	var side: Vector2 = along.orthogonal()
	var hot := _lit(Color(1.0, 0.95, 0.82, 0.9 * fade))
	var warm := _lit(Color(_primary.r, _primary.g, _primary.b, 0.55 * fade))
	# Flash seats ride the same muzzles the sheets end on: needle 16, bell 9, ring 9.
	match _kind:
		MUZZLE_RIFLE:
			var tip: Vector2 = along * MUZZLE_RIFLE_SEAT
			draw_line(tip, tip + along * 7.0, hot, 2.0, true)
			draw_line(tip + side * 3.0, tip - side * 3.0, warm, 1.4, true)
		MUZZLE_SCATTER:
			var mouth: Vector2 = along * MUZZLE_SCATTER_SEAT
			for spread in [-0.5, -0.25, 0.0, 0.25, 0.5]:
				var ray: Vector2 = Vector2.RIGHT.rotated(angle + spread)
				draw_line(mouth, mouth + ray * 9.0, hot if spread == 0.0 else warm,
					1.8, true)
		MUZZLE_CANNON:
			var mouth: Vector2 = along * MUZZLE_CANNON_SEAT
			draw_circle(mouth + along * 3.0, 5.5 * fade + 2.0, warm)
			draw_circle(mouth + along * 3.0, 2.6 * fade + 1.0, hot)
			draw_line(mouth - along * 2.0, mouth + along * 9.0, hot, 2.6, true)
		_:
			var tip: Vector2 = along * MUZZLE_SPARK_SEAT
			draw_circle(tip, 3.4 * fade + 1.2, hot)
			draw_arc(tip, 5.5, 0.0, TAU, 12, warm, 1.2, true)
