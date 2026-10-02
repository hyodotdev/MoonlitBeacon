class_name WeaponRig
extends Node2D

## Bounded drawn weapon layer for the chosen hero.
##
## One node, a dozen short strokes: the little guardian's held weapon plus a brief
## muzzle/cut flash on each shot. Carried-weapon readability without six new sprite
## sheets, and nothing to pose — the arena's real attacks trigger every flash.
##
## Flashes die on their own in ≤0.2s, freeze with the tree under pause/result, and
## leave with the player on scene change. `clear()` drops them immediately.

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
	# Parent Player carries the night tint; multiply back so moon-metal reads.
	self_modulate = Color(2.4, 2.4, 2.5, 1.0)


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


## The weapon in hand, ~14px, aimed at the last shot. Six silhouettes that share
## no stripe: blade, twin fangs, needle rifle, bell-mouth lantern gun with its
## lamp orb, stubby ring-muzzled cannon, reaper crescent. Each gun wears one
## band of the hero's own color so length is not the only tell.
func _draw_held() -> void:
	var angle: float = _aim.angle()
	var along: Vector2 = Vector2.RIGHT.rotated(angle)
	var side: Vector2 = along.orthogonal()
	var grip: Vector2 = -along * 2.0
	var metal := Color(0.82, 0.90, 1.0, 0.95)
	var dark := Color(0.35, 0.48, 0.72, 0.95)
	var glow := Color(_primary.r, _primary.g, _primary.b, 0.9)
	match _profile:
		Hero.AttackProfile.DANCER:
			for offset in [-3.2, 3.2]:
				var base: Vector2 = grip + side * offset * 0.6
				draw_line(base, base + along * 10.0 + side * offset * 0.4,
					metal, 1.6, false)
			draw_circle(grip, 1.6, glow)
		Hero.AttackProfile.SAGE:
			# Needle rifle: longest, thinnest, scoped. The sight bead floats past
			# the muzzle so the eye finds the tip even at a glance.
			draw_line(grip - along * 5.0, grip + along * 15.0, dark, 2.2, false)
			draw_line(grip + along * 5.0, grip + along * 15.0, metal, 1.0, false)
			draw_circle(grip + along * 1.0 - side * 2.2, 1.3, metal)
			draw_line(grip + along * 6.0 - side * 1.7,
				grip + along * 6.0 + side * 1.7, glow, 1.6, false)
			draw_circle(grip + along * 16.0, 1.0, glow)
		Hero.AttackProfile.KEEPER:
			# Bell-mouth lantern gun: short fat body, wide flare, and the lamp
			# orb riding above — the orb is the Keeper's tell at any range.
			draw_line(grip - along * 3.0, grip + along * 5.0, dark, 4.2, false)
			var tip: Vector2 = grip + along * 5.0
			draw_line(tip, tip + along * 4.0 + side * 3.6, metal, 1.6, false)
			draw_line(tip, tip + along * 4.0 - side * 3.6, metal, 1.6, false)
			var lamp: Vector2 = grip + along * 1.0 - side * 3.6
			draw_circle(lamp, 2.8, glow)
			draw_circle(lamp, 1.3, Color(1.0, 0.98, 0.9, 0.95))
			draw_line(grip - side * 1.0, grip + side * 1.0, glow, 2.2, false)
		Hero.AttackProfile.KNIGHT:
			# Stubby cannon: the shortest barrel, the thickest walls, a ringed
			# muzzle you could drop a marble through, and a round breech.
			draw_line(grip - along * 5.0, grip + along * 7.0, dark, 5.4, false)
			draw_line(grip - along * 4.0, grip + along * 6.0, metal, 2.2, false)
			draw_arc(grip + along * 7.0, 2.8, 0.0, TAU, 12, metal, 1.2, false)
			draw_circle(grip + along * 7.0, 1.6, Color(0.08, 0.08, 0.12, 0.95))
			draw_circle(grip - along * 5.0, 2.2, dark)
			draw_line(grip - along * 1.0 - side * 2.6,
				grip - along * 1.0 + side * 2.6, glow, 1.4, false)
		Hero.AttackProfile.ECLIPSE:
			draw_line(grip - along * 7.0, grip + along * 6.0, dark, 1.8, false)
			draw_arc(grip + along * 6.0, 4.2, angle - 1.2, angle + 1.2, 10,
				metal, 1.5, false)
			draw_circle(grip - along * 7.0, 1.5, glow)
		_:
			draw_line(grip, grip + along * 11.0, metal, 2.2, false)
			draw_line(grip + side * 2.4, grip - side * 2.4, glow, 1.6, false)
			draw_circle(grip - along * 1.6, 1.4, glow)
			draw_circle(grip + along * 11.0, 0.9, Color(1.0, 1.0, 1.0, 0.9))


func _draw_cut_flash(fade: float) -> void:
	var angle: float = _aim.angle()
	var light := Color(_secondary.r, _secondary.g, _secondary.b, 0.75 * fade)
	if _kind == TWIN_CUT:
		for offset in [-0.42, 0.42]:
			draw_arc(Vector2.ZERO, 12.0, angle - 0.5 + offset,
				angle + 0.5 + offset, 8, light, 2.0, false)
	else:
		draw_arc(Vector2.ZERO, 13.0, angle - 0.7, angle + 0.7, 10, light, 2.4, false)


func _draw_ring_flash(fade: float) -> void:
	var radius: float = 20.0 + (1.0 - fade) * 26.0
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 26,
		Color(_primary.r, _primary.g, _primary.b, 0.5 * fade), 2.2, false)


func _draw_muzzle_flash(fade: float) -> void:
	var angle: float = _aim.angle()
	var along: Vector2 = Vector2.RIGHT.rotated(angle)
	var side: Vector2 = along.orthogonal()
	var hot := Color(1.0, 0.95, 0.82, 0.9 * fade)
	var warm := Color(_primary.r, _primary.g, _primary.b, 0.55 * fade)
	# Flash seats float just past each new muzzle: needle 13, bell 7, ring 5.
	match _kind:
		MUZZLE_RIFLE:
			var tip: Vector2 = along * MUZZLE_RIFLE_SEAT
			draw_line(tip, tip + along * 7.0, hot, 2.0, false)
			draw_line(tip + side * 3.0, tip - side * 3.0, warm, 1.4, false)
		MUZZLE_SCATTER:
			var mouth: Vector2 = along * MUZZLE_SCATTER_SEAT
			for spread in [-0.5, -0.25, 0.0, 0.25, 0.5]:
				var ray: Vector2 = Vector2.RIGHT.rotated(angle + spread)
				draw_line(mouth, mouth + ray * 9.0, hot if spread == 0.0 else warm,
					1.8, false)
		MUZZLE_CANNON:
			var mouth: Vector2 = along * MUZZLE_CANNON_SEAT
			draw_circle(mouth + along * 3.0, 5.5 * fade + 2.0, warm)
			draw_circle(mouth + along * 3.0, 2.6 * fade + 1.0, hot)
			draw_line(mouth - along * 2.0, mouth + along * 9.0, hot, 2.6, false)
		_:
			var tip: Vector2 = along * MUZZLE_SPARK_SEAT
			draw_circle(tip, 3.4 * fade + 1.2, hot)
			draw_arc(tip, 5.5, 0.0, TAU, 12, warm, 1.2, false)
