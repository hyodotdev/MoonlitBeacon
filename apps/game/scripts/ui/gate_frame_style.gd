class_name GateFrameStyle
extends StyleBox

## Authored fantasy frame for the moon gate entry controls, drawn from code.
##
## Every visible gate button face, dialog card, ID field, progress bar and
## Hall row wears one of these instead of a flat rectangle. The look is cut
## corners over worked material: a dark keyline seating the face into the
## art, a beveled ink face with a lit crown and a shaded foot, an etched
## inner frame, and a steel, gold, coral or mint edge per accent. Cards
## carry small gold rivets and a crescent moon on the top edge; buttons
## carry one small etched mark by the top-left chamfer — crescent for gold,
## diamond for steel, triangle for coral — so motifs stay accents and text
## reads first.
##
## There are no image files behind this. The whole face is vector geometry
## emitted through the canvas item the button hands over, so it stays crisp
## at 808x360, wide phones and tablets with no import step and no bitmap
## source to keep in sync. GateEntryStyle owns the shared instances; panels
## only ask for a kind and a state.

## What the frame surrounds. Geometry and ornament follow the kind.
enum Kind {
	BUTTON, ## 44px touch control with a steel, gold or coral edge.
	CARD, ## Dialog card with rivets and a crescent moon.
	FIELD, ## Read-only ID well: shallow chamfer, quiet edge.
	BAR_BACK, ## Progress track the fill travels in.
	BAR_FILL, ## Progress fill; the bar clips the rect to the real value.
	ROW, ## Hall rank row: soft chamfer, alternating ink fills.
	FOCUS, ## Keyboard focus ring drawn outside the control rect.
}

## Edge accent. Gold marks the primary action, coral the destructive one,
## mint the progress fill, steel everything else.
enum Accent { STEEL, GOLD, CORAL, MINT }

## Control state. Focus ignores this; it always draws the gold ring.
enum State { NORMAL, HOVER, PRESSED, DISABLED }

## Chamfer per kind, in canvas pixels at the 808x360 base.
const CHAMFER_BUTTON: float = 7.0
const CHAMFER_CARD: float = 12.0
const CHAMFER_FIELD: float = 5.0
const CHAMFER_BAR: float = 4.0
const CHAMFER_ROW: float = 6.0
## Edge line widths: hairline rim, readable control edge, focus ring.
const EDGE_THIN: float = 1.0
const EDGE_LINE: float = 1.2
const EDGE_RING: float = 2.2
## Bevel insets: the lit crown pools inside the rim, the etched frame sits
## deeper, both following the chamfer.
const CROWN_INSET: float = 2.5
const ETCH_INSET: float = 5.0
const ETCH_INSET_CARD: float = 7.0
const MOTIF_RADIUS: float = 3.2
## How far the hover glow and the focus ring stand off the face.
const GLOW_STANDOFF: float = 2.0
const RING_STANDOFF: float = 2.5
const RIVET_RADIUS: float = 1.6
const MOON_RADIUS: float = 5.0
const MOON_CARVE: Vector2 = Vector2(2.2, -1.2)

var _kind: int = Kind.BUTTON
var _accent: int = Accent.STEEL
var _state: int = State.NORMAL


func _init(kind: int = Kind.BUTTON, accent: int = Accent.STEEL,
		state: int = State.NORMAL) -> void:
	_kind = kind
	_accent = accent
	_state = state
	match kind:
		Kind.BUTTON:
			content_margin_left = 12.0
			content_margin_right = 12.0
			content_margin_top = 6.0
			content_margin_bottom = 6.0
		Kind.CARD:
			content_margin_left = 16.0
			content_margin_right = 16.0
			content_margin_top = 12.0
			content_margin_bottom = 12.0
		Kind.FIELD:
			content_margin_left = 8.0
			content_margin_right = 8.0
			content_margin_top = 4.0
			content_margin_bottom = 4.0
		Kind.ROW:
			content_margin_left = 8.0
			content_margin_right = 8.0
			content_margin_top = 6.0
			content_margin_bottom = 6.0
		_:
			content_margin_left = 2.0
			content_margin_right = 2.0
			content_margin_top = 2.0
			content_margin_bottom = 2.0


## Which kind this instance draws. Tests read this, never the pixels.
func kind() -> int:
	return _kind


func accent() -> int:
	return _accent


func state() -> int:
	return _state


func _get_minimum_size() -> Vector2:
	# Content margins only, like the flat boxes before: every gate card is
	# sized by fitted content math, and any extra floor here would clamp a
	# 420px card wider and off-center it.
	return Vector2(
		content_margin_left + content_margin_right,
		content_margin_top + content_margin_bottom)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	match _kind:
		Kind.FOCUS:
			_draw_ring(to_canvas_item, rect)
		Kind.BAR_FILL:
			_draw_fill(to_canvas_item, rect)
		_:
			_draw_frame(to_canvas_item, rect)


## Chamfered outline standing off the control: the keyboard focus answer.
func _draw_ring(to_canvas_item: RID, rect: Rect2) -> void:
	var grown: Rect2 = rect.grow(RING_STANDOFF)
	var points: PackedVector2Array = _chamfer_points(
		grown, CHAMFER_BUTTON + RING_STANDOFF)
	points.append(points[0])
	RenderingServer.canvas_item_add_polyline(
		to_canvas_item, points,
		PackedColorArray([Color(0.96, 0.76, 0.40, 0.90)]),
		EDGE_RING, true)


## Mint progress fill with a lighter crown so depth reads at any width.
func _draw_fill(to_canvas_item: RID, rect: Rect2) -> void:
	var colors := _palette()
	RenderingServer.canvas_item_add_polygon(
		to_canvas_item, _chamfer_points(rect, CHAMFER_BAR),
		PackedColorArray([colors["face"]]))
	var crown := Rect2(
		rect.position + Vector2(2.0, 2.0),
		Vector2(rect.size.x - 4.0, maxf(rect.size.y * 0.42 - 2.0, 1.0)))
	if crown.size.x > 2.0 and crown.size.y > 0.0:
		RenderingServer.canvas_item_add_polygon(
			to_canvas_item, _chamfer_points(crown, 2.0),
			PackedColorArray([colors["crown"]]))


func _draw_frame(to_canvas_item: RID, rect: Rect2) -> void:
	var colors := _palette()
	var chamfer: float = _chamfer()
	_draw_keyline(to_canvas_item, rect, chamfer)
	var face: PackedVector2Array = _chamfer_points(rect, chamfer)
	RenderingServer.canvas_item_add_polygon(
		to_canvas_item, face, PackedColorArray([colors["face"]]))
	if _state != State.DISABLED:
		_draw_bevel(to_canvas_item, rect, chamfer, colors)
		_draw_etch(to_canvas_item, rect, chamfer, colors)
	if _kind == Kind.BUTTON and _accent == Accent.GOLD \
			and _state != State.DISABLED:
		_draw_beacon_line(to_canvas_item, rect, chamfer, colors)
	_draw_rim(to_canvas_item, rect, chamfer, colors)
	var edge: PackedVector2Array = face.duplicate()
	edge.append(face[0])
	RenderingServer.canvas_item_add_polyline(
		to_canvas_item, edge, PackedColorArray([colors["edge"]]),
		EDGE_LINE, true)
	if _state == State.HOVER or (_kind == Kind.BUTTON \
			and _accent == Accent.GOLD and _state == State.NORMAL):
		_draw_glow(to_canvas_item, rect, chamfer, colors,
			0.30 if _state == State.HOVER else 0.16)
	if _state != State.DISABLED:
		if _kind == Kind.CARD:
			_draw_card_marks(to_canvas_item, rect, chamfer, colors)
		elif _kind == Kind.BUTTON:
			_draw_button_motif(to_canvas_item, rect, chamfer, colors)


## Dark keyline seating the face into the art behind it.
func _draw_keyline(to_canvas_item: RID, rect: Rect2, chamfer: float) -> void:
	var line: PackedVector2Array = _chamfer_points(
		rect.grow(1.0), chamfer + 1.0)
	line.append(line[0])
	RenderingServer.canvas_item_add_polyline(
		to_canvas_item, line,
		PackedColorArray([Color(0.01, 0.02, 0.05, 0.85)]),
		EDGE_THIN, true)


## Lit crown pooling inside the top rim, shaded foot inside the bottom.
## Pressed inverts the pair so the face reads pushed in.
func _draw_bevel(to_canvas_item: RID, rect: Rect2, chamfer: float,
		colors: Dictionary) -> void:
	var inner := Rect2(
		rect.position + Vector2(CROWN_INSET, CROWN_INSET),
		rect.size - Vector2(CROWN_INSET * 2.0, CROWN_INSET * 2.0))
	if inner.size.x <= 2.0 or inner.size.y <= 2.0:
		return
	var crown_color: Color = colors["pool"]
	var foot_color: Color = colors["shade"]
	if _state == State.PRESSED:
		crown_color = colors["shade"]
		foot_color = colors["pool"]
	var crown := Rect2(inner.position,
		Vector2(inner.size.x, inner.size.y * 0.45))
	RenderingServer.canvas_item_add_polygon(
		to_canvas_item,
		_chamfer_top_points(crown, maxf(chamfer - CROWN_INSET, 0.0)),
		PackedColorArray([crown_color]))
	var foot := Rect2(
		inner.position + Vector2(0.0, inner.size.y * 0.70),
		Vector2(inner.size.x, inner.size.y * 0.30))
	RenderingServer.canvas_item_add_polygon(
		to_canvas_item,
		_chamfer_bottom_points(foot, maxf(chamfer - CROWN_INSET, 0.0)),
		PackedColorArray([foot_color]))


## Etched inner frame: one dark line following the chamfer, well inside
## the edge so the face reads as worked material, not a second border.
func _draw_etch(to_canvas_item: RID, rect: Rect2, chamfer: float,
		colors: Dictionary) -> void:
	var inset: float = ETCH_INSET_CARD if _kind == Kind.CARD else ETCH_INSET
	var inner := Rect2(
		rect.position + Vector2(inset, inset),
		rect.size - Vector2(inset * 2.0, inset * 2.0))
	if inner.size.x <= 2.0 or inner.size.y <= 2.0:
		return
	var line: PackedVector2Array = _chamfer_points(
		inner, maxf(chamfer - inset, 0.0))
	line.append(line[0])
	RenderingServer.canvas_item_add_polyline(
		to_canvas_item, line, PackedColorArray([colors["etch"]]),
		EDGE_THIN, true)


func _draw_glow(to_canvas_item: RID, rect: Rect2, chamfer: float,
		colors: Dictionary, strength: float) -> void:
	var glow: PackedVector2Array = _chamfer_points(
		rect.grow(GLOW_STANDOFF), chamfer + GLOW_STANDOFF)
	glow.append(glow[0])
	var glow_color: Color = colors["edge"]
	glow_color.a *= strength / maxf(colors["edge"].a, 0.01)
	glow_color.a = minf(glow_color.a, 1.0)
	RenderingServer.canvas_item_add_polyline(
		to_canvas_item, glow, PackedColorArray([glow_color]),
		EDGE_THIN, true)


## One small etched mark by the top-left chamfer: crescent for gold,
## diamond for steel, triangle for coral, lit beacon diamond for mint.
## An accent, never an icon.
func _draw_button_motif(to_canvas_item: RID, rect: Rect2, chamfer: float,
		colors: Dictionary) -> void:
	var at := Vector2(
		rect.position.x + chamfer * 0.5 + 2.0,
		rect.position.y + chamfer * 0.5 + 2.0)
	match _accent:
		Accent.GOLD:
			var gold := Color(0.96, 0.76, 0.40, 0.80)
			RenderingServer.canvas_item_add_circle(
				to_canvas_item, at, MOTIF_RADIUS, gold)
			var face: Color = colors["face"]
			face.a = 1.0
			RenderingServer.canvas_item_add_circle(
				to_canvas_item, at + Vector2(1.4, -0.8),
				MOTIF_RADIUS - 0.6, face)
		Accent.CORAL:
			var coral := Color(1.0, 0.47, 0.44, 0.70)
			RenderingServer.canvas_item_add_polygon(
				to_canvas_item,
				PackedVector2Array([
					at + Vector2(0.0, -MOTIF_RADIUS),
					at + Vector2(MOTIF_RADIUS, MOTIF_RADIUS),
					at + Vector2(-MOTIF_RADIUS, MOTIF_RADIUS),
				]),
				PackedColorArray([coral]))
		Accent.MINT:
			var mint := Color(0.55, 0.95, 0.88, 0.85)
			RenderingServer.canvas_item_add_polygon(
				to_canvas_item,
				PackedVector2Array([
					at + Vector2(0.0, -MOTIF_RADIUS * 1.3),
					at + Vector2(MOTIF_RADIUS * 0.8, 0.0),
					at + Vector2(0.0, MOTIF_RADIUS * 1.3),
					at + Vector2(-MOTIF_RADIUS * 0.8, 0.0),
				]),
				PackedColorArray([mint]))
		_:
			var steel := Color(0.62, 0.78, 0.90, 0.65)
			RenderingServer.canvas_item_add_polygon(
				to_canvas_item,
				PackedVector2Array([
					at + Vector2(0.0, -MOTIF_RADIUS),
					at + Vector2(MOTIF_RADIUS, 0.0),
					at + Vector2(0.0, MOTIF_RADIUS),
					at + Vector2(-MOTIF_RADIUS, 0.0),
				]),
				PackedColorArray([steel]))


## Thin gold line under the primary button's top rim: the beacon answer.
func _draw_beacon_line(to_canvas_item: RID, rect: Rect2, chamfer: float,
		colors: Dictionary) -> void:
	var y: float = rect.position.y + 4.5
	RenderingServer.canvas_item_add_line(
		to_canvas_item,
		Vector2(rect.position.x + chamfer + 3.0, y),
		Vector2(rect.end.x - chamfer - 3.0, y),
		Color(colors["edge"].r, colors["edge"].g, colors["edge"].b, 0.55),
		EDGE_THIN, true)


## Bright top rim and dark foot. Pressed flips them so the face reads pushed.
func _draw_rim(to_canvas_item: RID, rect: Rect2, chamfer: float,
		colors: Dictionary) -> void:
	if _state == State.DISABLED:
		return
	var top_y: float = rect.position.y + 2.0
	var foot_y: float = rect.end.y - 2.0
	var from_x: float = rect.position.x + chamfer + 1.0
	var to_x: float = rect.end.x - chamfer - 1.0
	var bright: Color = colors["rim"]
	var dark: Color = colors["foot"]
	if _state == State.PRESSED:
		bright = colors["foot"]
		dark = colors["rim"]
	RenderingServer.canvas_item_add_line(
		to_canvas_item, Vector2(from_x, top_y), Vector2(to_x, top_y),
		bright, EDGE_THIN, true)
	RenderingServer.canvas_item_add_line(
		to_canvas_item, Vector2(from_x, foot_y), Vector2(to_x, foot_y),
		dark, EDGE_THIN, true)


## Card ornament only: a crescent moon riding the top edge and one gold
## rivet seated in each chamfer. Buttons stay quiet for text.
func _draw_card_marks(to_canvas_item: RID, rect: Rect2, chamfer: float,
		colors: Dictionary) -> void:
	var gold := Color(0.96, 0.76, 0.40, 0.88)
	var middle: float = rect.position.x + rect.size.x * 0.5
	var top: float = rect.position.y
	RenderingServer.canvas_item_add_circle(
		to_canvas_item, Vector2(middle, top), MOON_RADIUS, gold)
	var face: Color = colors["face"]
	face.a = 1.0
	RenderingServer.canvas_item_add_circle(
		to_canvas_item, Vector2(middle, top) + MOON_CARVE,
		MOON_RADIUS - 1.0, face)
	var inset: float = chamfer * 0.5
	var rivets: Array[Vector2] = [
		rect.position + Vector2(inset, inset),
		Vector2(rect.end.x - inset, rect.position.y + inset),
		Vector2(rect.position.x + inset, rect.end.y - inset),
		rect.end - Vector2(inset, inset),
	]
	for rivet in rivets:
		RenderingServer.canvas_item_add_circle(
			to_canvas_item, rivet, RIVET_RADIUS, gold)


func _chamfer() -> float:
	match _kind:
		Kind.CARD:
			return CHAMFER_CARD
		Kind.FIELD:
			return CHAMFER_FIELD
		Kind.BAR_BACK:
			return CHAMFER_BAR
		Kind.ROW:
			return CHAMFER_ROW
	return CHAMFER_BUTTON


## Top half of a chamfered outline, closed along its bottom edge.
func _chamfer_top_points(rect: Rect2, chamfer: float) -> PackedVector2Array:
	var cut: float = clampf(
		chamfer, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var left: float = rect.position.x
	var top: float = rect.position.y
	var right: float = rect.end.x
	var bottom: float = rect.end.y
	return PackedVector2Array([
		Vector2(left + cut, top),
		Vector2(right - cut, top),
		Vector2(right, top + cut),
		Vector2(right, bottom),
		Vector2(left, bottom),
		Vector2(left, top + cut),
	])


## Bottom half of a chamfered outline, closed along its top edge.
func _chamfer_bottom_points(rect: Rect2, chamfer: float) -> PackedVector2Array:
	var cut: float = clampf(
		chamfer, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var left: float = rect.position.x
	var top: float = rect.position.y
	var right: float = rect.end.x
	var bottom: float = rect.end.y
	return PackedVector2Array([
		Vector2(left, top),
		Vector2(right, top),
		Vector2(right, bottom - cut),
		Vector2(right - cut, bottom),
		Vector2(left + cut, bottom),
		Vector2(left, bottom - cut),
	])


## Eight-point chamfered outline, clockwise from the top edge.
func _chamfer_points(rect: Rect2, chamfer: float) -> PackedVector2Array:
	var cut: float = clampf(
		chamfer, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var left: float = rect.position.x
	var top: float = rect.position.y
	var right: float = rect.end.x
	var bottom: float = rect.end.y
	return PackedVector2Array([
		Vector2(left + cut, top),
		Vector2(right - cut, top),
		Vector2(right, top + cut),
		Vector2(right, bottom - cut),
		Vector2(right - cut, bottom),
		Vector2(left + cut, bottom),
		Vector2(left, bottom - cut),
		Vector2(left, top + cut),
	])


## Face, edge, rim, foot, bevel pool and shade, etched line and fill
## crown for this kind, accent and state.
func _palette() -> Dictionary:
	match _kind:
		Kind.BAR_BACK:
			return {
				"face": Color(0.03, 0.06, 0.12, 0.95),
				"edge": Color(0.45, 0.62, 0.78, 0.30),
				"rim": Color(0.75, 0.88, 1.0, 0.18),
				"foot": Color(0.01, 0.02, 0.05, 0.6),
				"pool": Color(0.75, 0.88, 1.0, 0.06),
				"shade": Color(0.0, 0.0, 0.0, 0.20),
				"etch": Color(0.0, 0.0, 0.0, 0.30),
				"crown": Color(0.75, 0.88, 1.0, 0.18),
			}
		Kind.BAR_FILL:
			return {
				"face": Color(0.30, 0.68, 0.66, 1.0),
				"edge": Color(0.45, 0.85, 0.82, 1.0),
				"rim": Color(0.75, 0.88, 1.0, 0.35),
				"foot": Color(0.01, 0.02, 0.05, 0.4),
				"pool": Color(0.75, 0.88, 1.0, 0.10),
				"shade": Color(0.0, 0.0, 0.0, 0.20),
				"etch": Color(0.0, 0.0, 0.0, 0.30),
				"crown": Color(0.62, 0.95, 0.90, 0.85),
			}
		Kind.CARD:
			return {
				"face": Color(0.05, 0.10, 0.19, 0.96),
				"edge": Color(0.36, 0.68, 0.72, 0.48),
				"rim": Color(0.75, 0.88, 1.0, 0.30),
				"foot": Color(0.01, 0.02, 0.05, 0.55),
				"pool": Color(0.75, 0.88, 1.0, 0.08),
				"shade": Color(0.0, 0.0, 0.0, 0.22),
				"etch": Color(0.0, 0.0, 0.0, 0.30),
				"crown": Color(0.75, 0.88, 1.0, 0.30),
			}
		Kind.FIELD:
			return {
				"face": Color(0.03, 0.06, 0.12, 0.95),
				"edge": Color(0.45, 0.62, 0.78, 0.42),
				"rim": Color(0.75, 0.88, 1.0, 0.22),
				"foot": Color(0.01, 0.02, 0.05, 0.55),
				"pool": Color(0.75, 0.88, 1.0, 0.06),
				"shade": Color(0.0, 0.0, 0.0, 0.20),
				"etch": Color(0.0, 0.0, 0.0, 0.30),
				"crown": Color(0.75, 0.88, 1.0, 0.22),
			}
		Kind.ROW:
			var even: bool = _accent == Accent.STEEL
			return {
				"face": Color(0.07, 0.13, 0.23, 0.9) if even
					else Color(0.09, 0.16, 0.27, 0.9),
				"edge": Color(0.45, 0.62, 0.78, 0.26),
				"rim": Color(0.75, 0.88, 1.0, 0.16),
				"foot": Color(0.01, 0.02, 0.05, 0.5),
				"pool": Color(0.75, 0.88, 1.0, 0.06),
				"shade": Color(0.0, 0.0, 0.0, 0.18),
				"etch": Color(0.0, 0.0, 0.0, 0.28),
				"crown": Color(0.75, 0.88, 1.0, 0.16),
			}
	return _button_palette()


## Button faces: steel, gold or coral worked metal over an ink face, with
## the state shifting brightness. Disabled sinks the whole face.
func _button_palette() -> Dictionary:
	var edge := Color(0.45, 0.62, 0.78, 0.55)
	var face := Color(0.08, 0.14, 0.25, 0.97)
	var pool := Color(0.70, 0.84, 1.0, 0.10)
	match _accent:
		Accent.GOLD:
			edge = Color(0.96, 0.72, 0.35, 0.80)
			face = Color(0.17, 0.13, 0.07, 0.98)
			pool = Color(1.0, 0.82, 0.45, 0.16)
		Accent.CORAL:
			edge = Color(0.95, 0.42, 0.38, 0.70)
			face = Color(0.18, 0.09, 0.10, 0.98)
			pool = Color(1.0, 0.55, 0.50, 0.13)
		Accent.MINT:
			edge = Color(0.45, 0.85, 0.82, 0.70)
			face = Color(0.06, 0.14, 0.15, 0.98)
			pool = Color(0.62, 0.95, 0.90, 0.13)
	match _state:
		State.HOVER:
			face = face.lightened(0.12)
			pool.a = minf(pool.a * 1.6, 0.30)
			edge.a = minf(edge.a + 0.15, 1.0)
		State.PRESSED:
			face = face.darkened(0.18)
		State.DISABLED:
			face = Color(0.05, 0.08, 0.14, 0.60)
			edge = Color(edge.r, edge.g, edge.b, 0.22)
	return {
		"face": face,
		"edge": edge,
		"rim": Color(0.78, 0.90, 1.0, 0.38),
		"foot": Color(0.01, 0.02, 0.05, 0.55),
		"pool": pool,
		"shade": Color(0.0, 0.0, 0.0, 0.20),
		"etch": Color(0.0, 0.0, 0.0, 0.35),
		"crown": Color(0.78, 0.90, 1.0, 0.38),
	}
