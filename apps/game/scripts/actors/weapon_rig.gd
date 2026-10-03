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
## The pose itself never moves: no idle motion can imply a shot that did not
## happen.

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

var _profile: Hero.AttackProfile = Hero.AttackProfile.WARDEN
var _primary: Color = Color(0.3, 0.68, 1.0, 1.0)
var _secondary: Color = Color(0.82, 0.95, 1.0, 1.0)
var _aim: Vector2 = Vector2.RIGHT
var _kind: StringName = &""
var _age: float = 999.0
var _span: float = FLASH_SECONDS
var _kind_sidearm: bool = false


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


## Light the flash. A sidearm cue never cuts a live primary flash short: the
## held weapon is the primary, so its flash owns the eye while it burns.
func flash(aim: Vector2, kind: StringName, sidearm: bool = false) -> void:
	if sidearm and _kind != &"" and _age < _span and not _kind_sidearm:
		return
	if aim.length() > 0.01:
		_aim = aim.normalized()
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
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	if _age >= _span:
		_kind = &""
		_kind_sidearm = false
		set_process(false)
	queue_redraw()


func _draw() -> void:
	_draw_held()
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
## The transform is `drawn_logical_point` in texture space: texel t lands at
## anchor + R·(mirror·((t − pivot·4)·0.25)), which equals the logical mapping
## for t = 4·L exactly.
func _draw_held() -> void:
	var sheet: Texture2D = painted_sheet(_profile)
	if sheet == null:
		return
	var angle: float = _aim.angle()
	var mirror := Vector2(1.0, 1.0)
	if _aim.x < 0.0:
		mirror = Vector2(1.0, -1.0)
	var anchor: Vector2 = painted_anchor(_profile, _aim)
	var pivot: Vector2 = texture_pivot(_profile)
	var scaled := Vector2(
		mirror.x * DRAW_SCALE, mirror.y * DRAW_SCALE)
	var seated := Vector2(pivot.x * scaled.x, pivot.y * scaled.y)
	draw_set_transform(anchor - seated.rotated(angle), angle, scaled)
	draw_texture(sheet, Vector2.ZERO, PAINT_TINT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Legacy flame color through the explicit boost. Alpha rides untouched.
func _lit(color: Color) -> Color:
	return Color(
		color.r * FLASH_BOOST.x,
		color.g * FLASH_BOOST.y,
		color.b * FLASH_BOOST.z,
		color.a)


func _draw_cut_flash(fade: float) -> void:
	var angle: float = _aim.angle()
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
	var angle: float = _aim.angle()
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
