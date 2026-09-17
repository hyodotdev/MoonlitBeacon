class_name Screen
extends RefCounted

## Math that centers a stage drawn at the base resolution on the real screen.
##
## Stretch aspect is `expand`, so visible width and height differ per device.
## Height 360 is fixed; width grows with the device ratio. The leftover is
## used to shift the whole stage to screen center.
##
## Title and arena share this math, so it lives here once.

## Base resolution the background was drawn at.
const BASE_SIZE: Vector2 = Vector2(808, 360)

## The vignette must look the same at any aspect.
## Scale the base-resolution factor in proportion to the viewport.
const VIGNETTE_BASE_SCALE: Vector2 = Vector2(2.15, 1.2)

## On mobile, hiding the system bars still leaves edge gestures and rounded
## corners. On both Android and iOS some devices report that zone as 0 from
## DisplayServer's safe area, so 34 physical pixels are converted to internal
## coords and inset again.
const MOBILE_EDGE_INSET: float = 28.0
const MOBILE_EDGE_INSET_PIXELS: float = 34.0

## Store the scene file's original offsets on the Control itself so calling
## apply_safe_area() on every size change does not accumulate.
const SAFE_BASE_OFFSETS_META: StringName = &"moonlit_safe_base_offsets"


## Offset that moves the stage to screen center.
## Floored to integer pixels. A half pixel left over misaligns dots under nearest scale.
static func center_offset(viewport_size: Vector2) -> Vector2:
	return ((viewport_size - BASE_SIZE) * 0.5).floor()


## Vignette scale that covers the widened screen to the edges.
static func vignette_scale(viewport_size: Vector2) -> Vector2:
	return VIGNETTE_BASE_SCALE * (viewport_size / BASE_SIZE)


## Safe internal-coord rectangle in the real viewport where UI may sit.
##
## DisplayServer returns device-screen pixels and Control uses stretched
## internal coords, so the Viewport screen transform must be inverted. On
## mobile some devices include a transparent system bar in the safe area, so
## a conservative edge inset is intersected as well.
static func viewport_safe_rect(viewport: Viewport) -> Rect2:
	if viewport == null:
		return Rect2()
	var full_rect: Rect2 = viewport.get_visible_rect()
	if not full_rect.has_area():
		return full_rect

	var platform_rect: Rect2 = Rect2()
	if OS.has_feature("mobile"):
		var display_safe: Rect2i = DisplayServer.get_display_safe_area()
		if display_safe.has_area():
			platform_rect = _screen_rect_to_viewport(
				viewport, Rect2(display_safe.position, display_safe.size))

	var mobile_inset: float = _mobile_edge_inset(viewport) \
		if OS.has_feature("mobile") else 0.0
	return safe_rect(full_rect, platform_rect, mobile_inset)


## Same boundary with runtime dependencies split out so tests can judge it.
## If platform_rect is empty or absurdly small, ignore the OS report and apply
## only the mobile edge inset.
static func safe_rect(
		full_rect: Rect2, platform_rect: Rect2 = Rect2(),
		gesture_inset: float = 0.0) -> Rect2:
	if not full_rect.has_area():
		return full_rect
	var result: Rect2 = full_rect
	if platform_rect.has_area():
		var clipped: Rect2 = full_rect.intersection(platform_rect)
		if clipped.size.x >= full_rect.size.x * 0.5 \
				and clipped.size.y >= full_rect.size.y * 0.5:
			result = clipped
	if gesture_inset > 0.0 \
			and full_rect.size.x > gesture_inset * 2.0 \
			and full_rect.size.y > gesture_inset * 2.0:
		var gesture_rect: Rect2 = Rect2(
			full_rect.position + Vector2.ONE * gesture_inset,
			full_rect.size - Vector2.ONE * gesture_inset * 2.0)
		var guarded: Rect2 = result.intersection(gesture_rect)
		if guarded.has_area():
			result = guarded
	return result


## Remap a Control's anchors/offsets written against full_rect onto safe_rect.
##
## Full-screen Controls, the bottom-right dash button, and center panels all
## keep their original shape with the same formula even though their anchors
## differ. Original offsets are stored only on the first call.
static func apply_safe_area(
		control: Control, safe_area: Rect2, full_rect: Rect2) -> void:
	if control == null or not safe_area.has_area() or not full_rect.has_area():
		return
	var base: Vector4
	if control.has_meta(SAFE_BASE_OFFSETS_META):
		base = control.get_meta(SAFE_BASE_OFFSETS_META) as Vector4
	else:
		base = Vector4(
			control.offset_left, control.offset_top,
			control.offset_right, control.offset_bottom)
		control.set_meta(SAFE_BASE_OFFSETS_META, base)

	control.offset_left = base.x + safe_area.position.x \
		+ control.anchor_left * safe_area.size.x \
		- full_rect.position.x - control.anchor_left * full_rect.size.x
	control.offset_top = base.y + safe_area.position.y \
		+ control.anchor_top * safe_area.size.y \
		- full_rect.position.y - control.anchor_top * full_rect.size.y
	control.offset_right = base.z + safe_area.position.x \
		+ control.anchor_right * safe_area.size.x \
		- full_rect.position.x - control.anchor_right * full_rect.size.x
	control.offset_bottom = base.w + safe_area.position.y \
		+ control.anchor_bottom * safe_area.size.y \
		- full_rect.position.y - control.anchor_bottom * full_rect.size.y


## Leave a full-screen modal's dark dim and input blocker, and fit only the
## real content to the safe area.
##
## Shrink the modal root itself and a bright strip appears in the notch/gesture
## zone, and touches there leak to the screen behind. `Dim`/`Overlay` stay
## full-bleed; nested modals with their own Dim, like Overlay menus and
## HeroPreview, recurse.
static func apply_safe_content(
		root: Control, safe_area: Rect2, full_rect: Rect2) -> void:
	if root == null:
		return
	for node: Node in root.get_children():
		if not node is Control:
			continue
		var child: Control = node as Control
		var full_bleed: bool = child.name in [&"Dim", &"Overlay"]
		var nested_modal: bool = child.has_node("Dim")
		if full_bleed or nested_modal:
			apply_safe_content(child, safe_area, full_rect)
			continue
		apply_safe_area(child, safe_area, full_rect)


static func _screen_rect_to_viewport(viewport: Viewport, rect: Rect2) -> Rect2:
	var inverse: Transform2D = viewport.get_screen_transform().affine_inverse()
	var points: PackedVector2Array = PackedVector2Array([
		inverse * rect.position,
		inverse * Vector2(rect.end.x, rect.position.y),
		inverse * Vector2(rect.position.x, rect.end.y),
		inverse * rect.end,
	])
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


static func _mobile_edge_inset(viewport: Viewport) -> float:
	var transform: Transform2D = viewport.get_screen_transform()
	var scale: float = minf(transform.x.length(), transform.y.length())
	if scale <= 0.001:
		return MOBILE_EDGE_INSET
	# Keep the same 34 device pixels, but on low-res tablets allow up to 28
	# internal coords. Do not force 28 internal coords (84px) on a 3× phone
	# and squash the panel.
	return minf(MOBILE_EDGE_INSET, MOBILE_EDGE_INSET_PIXELS / scale)
