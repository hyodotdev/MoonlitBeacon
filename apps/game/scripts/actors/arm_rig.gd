class_name ArmRig
extends Node2D

## One painted two-bone arm: shoulder, elbow, wrist from the attack rig bake.
##
## The upper/forearm patches are capsule cuts of the hero's own idle cell, so
## the articulated arm is the same painted character, not a drawn limb. The
## shoulder stays fixed in torso space; `pose()` solves the elbow with
## two-bone IK toward the wrist target and hangs the patches on the joints.
## Segment lengths never change: the elbow must bend because the bones cannot
## stretch. The weapon grips the wrist the solver reports, so hand and grip
## share one source and cannot separate.
##
## Coordinates are torso-space cell px; `cell_origin`/`cell_scale` map them to
## the Player. Hidden at rest (the baked arm shows); posed during attacks.

var _upper: Sprite2D = null
var _fore: Sprite2D = null
var _shoulder: Vector2 = Vector2.ZERO
var _rest_elbow: Vector2 = Vector2.ZERO
var _rest_wrist: Vector2 = Vector2.ZERO
var _l1: float = 1.0
var _l2: float = 1.0
var _pole: Vector2 = Vector2(1.0, 0.35)
var _elbow: Vector2 = Vector2.ZERO
var _wrist: Vector2 = Vector2.ZERO
var _rest_upper_angle: float = 0.0
var _rest_fore_angle: float = 0.0
var _rest_upper_vec: Vector2 = Vector2.RIGHT
var _rest_fore_vec: Vector2 = Vector2.RIGHT

## Player-local position of torso-space cell (0,0), plus torso shift.
var cell_origin: Vector2 = Vector2.ZERO
var cell_scale: float = 0.255


func _ready() -> void:
	_upper = Sprite2D.new()
	_upper.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fore = Sprite2D.new()
	_fore.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_upper)
	add_child(_fore)
	visible = false


## Two-bone IK elbow with a pole: the solution bowing toward `pole`. Targets
## clamp into honest reach first, so this always solves; callers that need
## the raw answer use `solve_elbow_raw` and handle null.
static func solve_elbow_clamped(s: Vector2, w: Vector2, l1: float,
		l2: float, pole: Vector2) -> Vector2:
	var target: Vector2 = clamp_to_reach(s, w, l1, l2)
	var solved: Variant = solve_elbow_raw(s, target, l1, l2, pole)
	if solved == null:
		return s + (w - s).normalized() * l1
	return solved


## Raw two-bone IK elbow, or null past full extension. Deterministic: same
## inputs, same elbow, every tick on every machine.
static func solve_elbow_raw(s: Vector2, w: Vector2, l1: float,
		l2: float, pole: Vector2) -> Variant:
	var span: float = s.distance_to(w)
	if span < 0.000001 or span > l1 + l2 + 0.000001:
		return null
	var d: float = minf(maxf(span, absf(l1 - l2) + 0.000001), l1 + l2)
	var along: Vector2 = (w - s) / span
	var a: float = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h: float = sqrt(maxf(l1 * l1 - a * a, 0.0))
	var mid: Vector2 = s + along * a
	var perp := Vector2(-along.y, along.x)
	var first: Vector2 = mid + perp * h
	var second: Vector2 = mid - perp * h
	if (first - s).dot(pole) >= (second - s).dot(pole):
		return first
	return second


## Clamp a wrist target into the honest reach annulus. Timelines stay inside
## it by construction; this is the safety net, and tests prove it idles.
static func clamp_to_reach(s: Vector2, w: Vector2, l1: float,
		l2: float) -> Vector2:
	var span: float = s.distance_to(w)
	var lo: float = absf(l1 - l2) + 1.0
	var hi: float = l1 + l2
	if span < 0.000001:
		return s + Vector2(lo, 0.0)
	if span < lo or span > hi:
		return s + (w - s) / span * minf(maxf(span, lo), hi)
	return w


## Hang the patches on one baked arm entry. Pivot offsets seat the joints
## exactly on the node positions, so rotation pivots on the joint.
func configure(upper_tex: Texture2D, fore_tex: Texture2D,
		upper_pivot: Vector2, fore_pivot: Vector2,
		shoulder: Vector2, elbow: Vector2, wrist: Vector2,
		l1: float, l2: float, pole: Vector2) -> void:
	_shoulder = shoulder
	_rest_elbow = elbow
	_rest_wrist = wrist
	_l1 = l1
	_l2 = l2
	_pole = pole
	_elbow = elbow
	_wrist = wrist
	_rest_upper_angle = (elbow - shoulder).angle()
	_rest_fore_angle = (wrist - elbow).angle()
	_rest_upper_vec = elbow - shoulder
	_rest_fore_vec = wrist - elbow
	_upper.texture = upper_tex
	_upper.offset = upper_tex.get_size() / 2.0 - upper_pivot
	_fore.texture = fore_tex
	_fore.offset = fore_tex.get_size() / 2.0 - fore_pivot
	_layout()


## Pose the chain at one wrist target (torso-space cell px). Shoulder fixed.
func pose(wrist_target: Vector2) -> void:
	_wrist = clamp_to_reach(_shoulder, wrist_target, _l1, _l2)
	_elbow = solve_elbow_clamped(
		_shoulder, _wrist, _l1, _l2, _pole)
	_layout()


func elbow_cell() -> Vector2:
	return _elbow


func wrist_cell() -> Vector2:
	return _wrist


func shoulder_cell() -> Vector2:
	return _shoulder


func rest_wrist_cell() -> Vector2:
	return _rest_wrist


func segment_lengths() -> Vector2:
	return Vector2(_l1, _l2)


## Hung patch textures, for tests proving the chain wears paint, not nulls.
func upper_texture() -> Texture2D:
	return _upper.texture if _upper != null else null


func fore_texture() -> Texture2D:
	return _fore.texture if _fore != null else null


## Hung patch sprites, for tests observing the actual drawn transforms.
func upper_sprite() -> Sprite2D:
	return _upper


func fore_sprite() -> Sprite2D:
	return _fore


## Painted elbow through the drawn upper transform: the rest elbow vector
## rotated and scaled by the live sprite, in world space. Meets the fore
## joint when the scale/pivot math is right.
func painted_elbow_world() -> Vector2:
	if _upper == null or not _upper.is_inside_tree():
		return Vector2.ZERO
	return _upper.to_global(_rest_upper_vec)


## Painted wrist through the drawn fore transform: the rest wrist vector
## rotated and scaled by the live sprite, in world space. Meets the grip.
func painted_wrist_world() -> Vector2:
	if _fore == null or not _fore.is_inside_tree():
		return Vector2.ZERO
	return _fore.to_global(_rest_fore_vec)


## Match the baked body light: readability tint plus the polish material.
func set_render_tint(tint: Color, material: Material) -> void:
	if _upper != null:
		_upper.self_modulate = tint
		_upper.material = material
	if _fore != null:
		_fore.self_modulate = tint
		_fore.material = material


func _to_local(cell: Vector2) -> Vector2:
	return cell_origin + cell * cell_scale


func _layout() -> void:
	if _upper == null:
		return
	# Node positions ride the joints; offsets (pivot minus center) seat the
	# pivot exactly on the node, so rotation pivots on the joint itself.
	# Patches are cell-px paint, so they draw at the cell scale: without it
	# the elbow and wrist paint lands ~4x too far from the joints.
	_upper.scale = Vector2(cell_scale, cell_scale)
	_fore.scale = Vector2(cell_scale, cell_scale)
	_upper.position = _to_local(_shoulder)
	_upper.rotation = (_elbow - _shoulder).angle() - _rest_upper_angle
	_fore.position = _to_local(_elbow)
	_fore.rotation = (_wrist - _elbow).angle() - _rest_fore_angle


## Re-seat after the torso shifts (same joints, new origin).
func relayout() -> void:
	_layout()
