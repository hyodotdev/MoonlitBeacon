class_name WorldChrome
extends RefCounted

## One crafted moon-gate look for the production screens, drawn at true scale.
##
## Deep-ink grounds, aged-metal rims, a dim moon-blue keyline and ember-gold
## reserved for what matters. Art is hand-authored SVG in
## `assets/custom/ui/world/`, rasterized at 4 source texels per logical unit
## (a 36-unit frame is 144px of vector art), sampled with an explicit Linear
## filter. The locked global Nearest never touches this kit.
##
## Why custom drawing: Godot 4.7 `StyleBoxTexture` passes its margins through
## as destination fixed edges with no source-to-destination scale, so a 48px
## margin corner draws 48 logical pixels wide. `WorldNine` below maps source
## texels to logical units explicitly (48 -> 12, 32 -> 8, 56 -> 14, 16 -> 4),
## and `WorldPanel`, `WorldFrame`, `WorldButton` and `WorldLabel` draw it in
## `_draw`, underneath the native text, icons and focus that those controls
## keep. Layout never moves: invisible margin styles preserve the content
## margins the old kit resolved to.
##
## Three button roads: `ember` is the primary road (buy, retry, continue),
## `steel` the quiet moon road (close, cancel, ghost actions), `coral` the
## painful road (quit, danger). `card` frames relic picks. Chips are HUD pills
## and list rows; `chip_lit` marks owned or highlighted rows.
##
## All decor this helper adds is `MOUSE_FILTER_IGNORE` and either absolutely
## positioned or a fixed small row, so it can never eat taps or move the
## layouts the focused suites measure.

## Source texels and logical units per art family, with the content margins
## the old kit resolved to. Buttons and labels keep native text, icons, focus
## and hitboxes; only the painted background moves into `_draw`.
const ART: Dictionary = {
	"panel": {
		"tex": preload("res://assets/custom/ui/world/frame_panel.svg"),
		"src": 48.0, "dst": 12.0, "margins": [10.0, 9.0, 10.0, 9.0],
	},
	"panel_tight": {
		"tex": preload("res://assets/custom/ui/world/frame_panel.svg"),
		"src": 48.0, "dst": 12.0, "margins": [8.0, 6.0, 8.0, 6.0],
	},
	"chip": {
		"tex": preload("res://assets/custom/ui/world/frame_chip.svg"),
		"src": 32.0, "dst": 8.0, "margins": [5.0, 3.0, 5.0, 3.0],
	},
	"chip_lit": {
		"tex": preload("res://assets/custom/ui/world/frame_chip_lit.svg"),
		"src": 32.0, "dst": 8.0, "margins": [5.0, 3.0, 5.0, 3.0],
	},
	"card": {
		"tex": preload("res://assets/custom/ui/world/frame_card.svg"),
		"src": 56.0, "dst": 14.0, "margins": [12.0, 12.0, 12.0, 12.0],
	},
	"bar_back": {
		"tex": preload("res://assets/custom/ui/world/bar_back.svg"),
		"src": 16.0, "dst": 4.0, "margins": [4.0, 3.0, 4.0, 3.0],
	},
	"bar_fill": {
		"tex": preload("res://assets/custom/ui/world/bar_fill.svg"),
		"src": 16.0, "dst": 4.0, "margins": [4.0, 3.0, 4.0, 3.0],
	},
}

const BUTTONS: Dictionary = {
	"ember": {
		"src": 32.0, "dst": 8.0, "margins": [5.0, 5.0, 5.0, 5.0],
		"normal": preload("res://assets/custom/ui/world/btn_ember_normal.svg"),
		"hover": preload("res://assets/custom/ui/world/btn_ember_hover.svg"),
		"pressed": preload("res://assets/custom/ui/world/btn_ember_pressed.svg"),
		"disabled": preload("res://assets/custom/ui/world/btn_ember_disabled.svg"),
		"focus": preload("res://assets/custom/ui/world/btn_ember_focus.svg"),
	},
	"steel": {
		"src": 32.0, "dst": 8.0, "margins": [5.0, 5.0, 5.0, 5.0],
		"normal": preload("res://assets/custom/ui/world/btn_steel_normal.svg"),
		"hover": preload("res://assets/custom/ui/world/btn_steel_hover.svg"),
		"pressed": preload("res://assets/custom/ui/world/btn_steel_pressed.svg"),
		"disabled": preload("res://assets/custom/ui/world/btn_steel_disabled.svg"),
		"focus": preload("res://assets/custom/ui/world/btn_steel_focus.svg"),
	},
	"coral": {
		"src": 32.0, "dst": 8.0, "margins": [5.0, 5.0, 5.0, 5.0],
		"normal": preload("res://assets/custom/ui/world/btn_coral_normal.svg"),
		"hover": preload("res://assets/custom/ui/world/btn_coral_hover.svg"),
		"pressed": preload("res://assets/custom/ui/world/btn_coral_pressed.svg"),
		"disabled": preload("res://assets/custom/ui/world/btn_coral_disabled.svg"),
		"focus": preload("res://assets/custom/ui/world/btn_coral_focus.svg"),
	},
	"card": {
		"src": 56.0, "dst": 14.0, "margins": [12.0, 12.0, 12.0, 12.0],
		"normal": preload("res://assets/custom/ui/world/frame_card.svg"),
		"hover": preload("res://assets/custom/ui/world/frame_card.svg"),
		"pressed": preload("res://assets/custom/ui/world/frame_card.svg"),
		"disabled": preload("res://assets/custom/ui/world/frame_card.svg"),
		"focus": preload("res://assets/custom/ui/world/card_focus.svg"),
	},
}

const CRESTS: Dictionary = {
	"moon": preload("res://assets/custom/ui/world/crest_moon.svg"),
	"beacon": preload("res://assets/custom/ui/world/crest_beacon.svg"),
	"relic": preload("res://assets/custom/ui/world/crest_relic.svg"),
	"book": preload("res://assets/custom/ui/world/crest_book.svg"),
	"coin": preload("res://assets/custom/ui/world/crest_coin.svg"),
	"gate": preload("res://assets/custom/ui/world/crest_gate.svg"),
}
const BEAD: Texture2D = preload("res://assets/custom/ui/world/bead_moon.svg")
const SEAL_WIN: Texture2D = preload("res://assets/custom/ui/world/seal_win.svg")
const SEAL_LOSE: Texture2D = preload("res://assets/custom/ui/world/seal_lose.svg")
const DAIS: Texture2D = preload("res://assets/custom/ui/world/dais.svg")

const LINE_METAL: Color = Color(0.79, 0.63, 0.37, 0.85)
const DECOR_NAME: String = "WorldDecor"
const TAB_NAME: String = "WorldTab"

static var _margin_styles: Dictionary = {}


## Nine source/destination rect pairs mapping `src` source texels of fixed
## edge to `dst` logical units over `rect_size`. Pure math, so the draw-scale
## regression can prove 48 -> 12 and 32 -> 8 without rendering a pixel.
##
## A control narrower than two fixed edges clamps the destination edge instead
## of inverting the middle band; the source corners squash slightly, the same
## way an undersized nine-patch always has.
static func slices(
		tex_size: Vector2i, rect_size: Vector2, src: float, dst: float
) -> Array:
	var dw: float = minf(dst, rect_size.x * 0.5)
	var dh: float = minf(dst, rect_size.y * 0.5)
	var sx: Array[float] = [0.0, src, float(tex_size.x) - src, float(tex_size.x)]
	var sy: Array[float] = [0.0, src, float(tex_size.y) - src, float(tex_size.y)]
	var dx: Array[float] = [0.0, dw, rect_size.x - dw, rect_size.x]
	var dy: Array[float] = [0.0, dh, rect_size.y - dh, rect_size.y]
	var out: Array = []
	for iy in 3:
		for ix in 3:
			out.append([
				Rect2(sx[ix], sy[iy], sx[ix + 1] - sx[ix], sy[iy + 1] - sy[iy]),
				Rect2(dx[ix], dy[iy], dx[ix + 1] - dx[ix], dy[iy + 1] - dy[iy]),
			])
	return out


## Paint one nine-patch with the explicit source-to-destination mapping.
static func draw_nine(
		item: CanvasItem, tex: Texture2D, rect_size: Vector2, src: float,
		dst: float, tint: Color = Color.WHITE) -> void:
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		return
	var size := Vector2i(int(tex.get_width()), int(tex.get_height()))
	for pair in slices(size, rect_size, src, dst):
		var from: Rect2 = pair[0]
		var to: Rect2 = pair[1]
		if to.size.x > 0.0 and to.size.y > 0.0:
			item.draw_texture_rect_region(tex, to, from, tint)


## Paint a frame, chip, card or bar kind over the item's full rect.
static func draw_kind(
		item: CanvasItem, kind: String, tint: Color = Color.WHITE) -> void:
	var spec: Dictionary = ART.get(kind, ART["chip"])
	var tex: Texture2D = spec["tex"]
	draw_nine(item, tex, item.get("size"), float(spec["src"]),
		float(spec["dst"]), tint)


## Paint a button kind in its current state on any item, plus the focus ring
## when held. The item is the WorldFace backing layer, never the button
## itself: button `_draw` runs after native paint and would bury the label.
static func draw_button_on(
		item: CanvasItem, kind: String, button: Button) -> void:
	var spec: Dictionary = BUTTONS.get(kind, BUTTONS["steel"])
	var state: String = button_face_state(button)
	var tex: Texture2D = spec[state]
	draw_nine(item, tex, button.size, float(spec["src"]), float(spec["dst"]))
	if button.has_focus():
		var ring: Texture2D = spec["focus"]
		draw_nine(item, ring, button.size, float(spec["src"]),
			float(spec["dst"]))


## The face a button wears right now: disabled, pressed, hover or normal.
static func button_face_state(button: Button) -> String:
	if button.disabled:
		return "disabled"
	if button.is_pressed():
		return "pressed"
	if button.is_hovered():
		return "hover"
	return "normal"


## An invisible style carrying content margins. Native Button, Label and
## PanelContainer measure and pad from their theme style, so custom-drawn
## controls keep one of these to hold the exact margins the old kit had.
static func margin_style(margins: Array) -> StyleBoxFlat:
	var key: String = "%s,%s,%s,%s" % margins
	if not _margin_styles.has(key):
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.bg_color = Color(0, 0, 0, 0)
		box.set_border_width_all(0)
		box.shadow_size = 0
		box.content_margin_left = margins[0]
		box.content_margin_top = margins[1]
		box.content_margin_right = margins[2]
		box.content_margin_bottom = margins[3]
		_margin_styles[key] = box
	return _margin_styles[key]


## Neutralize the native background styles of a custom-drawn button or label.
## Text, icons, focus behavior and hitboxes stay native; only paint moves.
static func neutralize(button: Control, kind: String) -> void:
	var spec: Dictionary = BUTTONS.get(kind, BUTTONS["steel"])
	var box: StyleBoxFlat = margin_style(spec["margins"])
	if button is Button:
		button.add_theme_stylebox_override("normal", box)
		button.add_theme_stylebox_override("hover", box)
		button.add_theme_stylebox_override("pressed", box)
		button.add_theme_stylebox_override("disabled", box)
		button.add_theme_stylebox_override("focus", box)
	elif button is Label:
		button.add_theme_stylebox_override("normal", box)


## A 20px header glyph. `motif` is one of moon, beacon, relic, book, coin, gate.
static func crest(motif: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = &"WorldCrest"
	rect.texture = CRESTS.get(motif, CRESTS["moon"])
	rect.custom_minimum_size = Vector2(20, 20)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## A 64px journey stamp: unbroken gold on a cleared gate, broken ash on defeat.
static func seal(won: bool) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = &"WorldSeal"
	rect.texture = SEAL_WIN if won else SEAL_LOSE
	rect.custom_minimum_size = Vector2(64, 64)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## The 96x24 hero stage, hung under a full-body portrait.
static func dais() -> TextureRect:
	var rect := TextureRect.new()
	rect.name = &"WorldDais"
	rect.texture = DAIS
	rect.custom_minimum_size = Vector2(96, 24)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## A 12px moon bead for in-flow rows that cannot take a full divider.
static func bead() -> TextureRect:
	var rect := TextureRect.new()
	rect.name = &"WorldBead"
	rect.texture = BEAD
	rect.custom_minimum_size = Vector2(12, 12)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## A moon-bead divider row for in-flow lists: line, bead, line.
static func divider() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = &"WorldDivider"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	var left := ColorRect.new()
	left.color = LINE_METAL
	left.custom_minimum_size = Vector2(24, 2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bead_rect := bead()
	var right := ColorRect.new()
	right.color = LINE_METAL
	right.custom_minimum_size = Vector2(24, 2)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	row.add_child(bead_rect)
	row.add_child(right)
	return row


## A crest tab straddling the frame's top edge: each screen's role glyph.
##
## Container-safe: under a Container the tab lives on one full-rect decor
## child behind the content, so the frame keeps its content child and the
## layout never sees the decor. `name` lookups take a String path here;
## `get_node_or_null` wants a NodePath, not a StringName.
static func tab(frame: Control, motif: String) -> void:
	var host: Control = frame
	if frame is Container:
		var decor := Control.new()
		decor.name = DECOR_NAME
		decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(decor)
		frame.move_child(decor, 0)
		host = decor
	var mark := crest(motif)
	mark.name = TAB_NAME
	mark.anchor_left = 0.5
	mark.anchor_top = 0.0
	mark.anchor_right = 0.5
	mark.anchor_bottom = 0.0
	mark.offset_left = -10.0
	mark.offset_top = -10.0
	mark.offset_right = 10.0
	mark.offset_bottom = 10.0
	host.add_child(mark)


## Add the crest tab on first open, never in `_ready`: the arena holds every
## panel closed, and decor on hidden panels would spend the late-game node
## budget for pixels nobody sees. Safe to call on every open.
static func ensure_tab(frame: Control, motif: String) -> void:
	if frame is Container:
		var decor := frame.get_node_or_null("WorldDecor") as Control
		if decor != null and decor.get_node_or_null("WorldTab") != null:
			return
	elif frame.get_node_or_null("WorldTab") != null:
		return
	tab(frame, motif)
