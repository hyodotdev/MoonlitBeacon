class_name GateEntryStyle
extends RefCounted

## One look for the moon gate entry surface and its dialogs.
##
## The shaded gate painting sets the palette: deep navy grounds, teal lines
## stay thin and dim, amber marks only the primary action. Every visible
## face is an authored frame drawn from code (`GateFrameStyle`): cut
## corners over worked material, with a steel, gold, coral or mint edge
## per accent. Buttons share five states so pressed,
## hover, disabled and keyboard focus read the same everywhere.
##
## Type is the smooth MapleStory + Noto Sans CJK pair the rest of the game
## uses since the 2026-08 refresh, built here in code so these modules never
## touch the old pixel-font resource names. Every factory applies the font
## overrides, so no label can fall back to the engine default face.

const BODY_FONT_PATH: String = "res://assets/third_party/fonts/MaplestoryLight.ttf"
const BOLD_FONT_PATH: String = "res://assets/third_party/fonts/MaplestoryBold.ttf"
const CJK_FONT_PATH: String = "res://assets/third_party/fonts/NotoSansCJKsc-Regular.otf"
const CJK_BOLD_PATH: String = "res://assets/third_party/fonts/NotoSansCJKsc-SyntheticBold.tres"

const TEXT_MAIN: Color = Color(0.94, 0.96, 0.99)
const TEXT_DIM: Color = Color(0.68, 0.76, 0.85)
const TEXT_FAINT: Color = Color(0.52, 0.60, 0.70)
const ACCENT_AMBER: Color = Color(0.96, 0.76, 0.40)
const ACCENT_TEAL: Color = Color(0.45, 0.85, 0.82)
const CORAL: Color = Color(1.0, 0.47, 0.44)
const MINT: Color = Color(0.48, 0.94, 0.74)
const DIM_BG: Color = Color(0.02, 0.03, 0.07, 0.72)

const FONT_KICKER: int = 13
const FONT_TITLE: int = 32
const FONT_SUBTITLE: int = 15
const FONT_BODY: int = 15
const FONT_SMALL: int = 12
const FONT_BUTTON: int = 15
const TOUCH_HEIGHT: float = 44.0
const TOUCH_WIDTH: float = 64.0
## Card content margins, kept beside `apply_card` for layout math.
const CARD_MARGIN_H: float = 32.0
const CARD_MARGIN_V: float = 24.0

static var _body: Font = null
static var _bold: Font = null
static var _card: GateFrameStyle = null
static var _field: GateFrameStyle = null
static var _bar_back: GateFrameStyle = null
static var _bar_fill: GateFrameStyle = null
static var _rows: Array = []
static var _buttons: Dictionary = {}


## Smooth body face with the CJK fallback every locale needs.
static func body_font() -> Font:
	if _body == null:
		_body = _paired_font(BODY_FONT_PATH, CJK_FONT_PATH)
	return _body


## Smooth bold face with the synthetic-bold CJK fallback.
static func bold_font() -> Font:
	if _bold == null:
		_bold = _paired_font(BOLD_FONT_PATH, CJK_BOLD_PATH)
	return _bold


## A label that translates its key at draw time. Decorative text never eats taps.
static func make_label(key: String, size: int, color: Color, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = key
	label.add_theme_font_override(
		&"font", bold_font() if bold else body_font())
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A button in the shared five-state look. `kind` picks the edge accent:
## "primary" gold for the one gate-entry action, "portal" mint for
## provider and guest passage, "danger" coral for destructive choices,
## anything else the quiet steel blue of navigation.
## All five faces are authored frames drawn from code, never flat boxes.
static func make_button(key: String, kind: String = "normal") -> Button:
	var button := Button.new()
	button.text = key
	button.add_theme_font_override(&"font", body_font())
	button.add_theme_font_size_override(&"font_size", FONT_BUTTON)
	button.add_theme_color_override(&"font_color", TEXT_MAIN)
	button.add_theme_color_override(&"font_hover_color", TEXT_MAIN)
	button.add_theme_color_override(&"font_pressed_color", TEXT_MAIN)
	button.add_theme_color_override(&"font_disabled_color", TEXT_FAINT)
	button.add_theme_color_override(&"font_focus_color", TEXT_MAIN)
	apply_kind(button, kind)
	button.custom_minimum_size = Vector2(TOUCH_WIDTH, TOUCH_HEIGHT)
	return button


## Re-skin a live button to another accent. The entry uses this to keep
## exactly one gold primary action as saves come and go.
static func apply_kind(button: Button, kind: String) -> void:
	_ensure_button_styles()
	var styles: Dictionary = _buttons[kind] \
		if _buttons.has(kind) else _buttons["normal"]
	button.add_theme_stylebox_override(&"normal", styles["normal"])
	button.add_theme_stylebox_override(&"hover", styles["hover"])
	button.add_theme_stylebox_override(&"pressed", styles["pressed"])
	button.add_theme_stylebox_override(&"disabled", styles["disabled"])
	button.add_theme_stylebox_override(&"focus", styles["focus"])


## The shared dialog card look on any PanelContainer.
static func apply_card(card: PanelContainer) -> void:
	if _card == null:
		_card = GateFrameStyle.new(
			GateFrameStyle.Kind.CARD, GateFrameStyle.Accent.STEEL,
			GateFrameStyle.State.NORMAL)
	card.add_theme_stylebox_override(&"panel", _card)


## Read-only ID field look: quiet well, mono-friendly spacing, full text kept.
static func apply_id_field(field: LineEdit) -> void:
	if _field == null:
		_field = GateFrameStyle.new(
			GateFrameStyle.Kind.FIELD, GateFrameStyle.Accent.STEEL,
			GateFrameStyle.State.NORMAL)
	field.add_theme_stylebox_override(&"normal", _field)
	field.add_theme_stylebox_override(&"read_only", _field)
	field.add_theme_stylebox_override(&"focus", _field)
	field.add_theme_font_override(&"font", body_font())
	field.add_theme_font_size_override(&"font_size", FONT_SMALL)
	field.add_theme_color_override(&"font_color", TEXT_MAIN)
	field.editable = false
	field.selecting_enabled = true
	field.expand_to_text_length = false


## Thin progress bar that only ever shows real reported progress.
static func apply_progress(bar: ProgressBar) -> void:
	if _bar_back == null:
		_bar_back = GateFrameStyle.new(
			GateFrameStyle.Kind.BAR_BACK, GateFrameStyle.Accent.STEEL,
			GateFrameStyle.State.NORMAL)
		_bar_fill = GateFrameStyle.new(
			GateFrameStyle.Kind.BAR_FILL, GateFrameStyle.Accent.MINT,
			GateFrameStyle.State.NORMAL)
	bar.add_theme_stylebox_override(&"background", _bar_back)
	bar.add_theme_stylebox_override(&"fill", _bar_fill)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(TOUCH_WIDTH, 14.0)


## Alternating Hall row faces. The accent slot carries the stripe: even
## rows read steel, odd rows gold, both drawn as quiet ink.
static func hall_row_style(index: int) -> GateFrameStyle:
	if _rows.is_empty():
		_rows = [
			GateFrameStyle.new(GateFrameStyle.Kind.ROW,
				GateFrameStyle.Accent.STEEL,
				GateFrameStyle.State.NORMAL),
			GateFrameStyle.new(GateFrameStyle.Kind.ROW,
				GateFrameStyle.Accent.GOLD,
				GateFrameStyle.State.NORMAL),
		]
	return _rows[absi(index) % 2] as GateFrameStyle


## Height a vertical stack of visible children really needs at a fixed
## content width. Autowrap labels are measured wrapped at that width: their
## minimum size reports a 1px column and would explode any card sized from
## `get_combined_minimum_size`, so every gate card fits through here.
static func fitted_stack_height(
		stack: BoxContainer, content_width: float) -> float:
	var total: float = 0.0
	var shown: int = 0
	for child in stack.get_children():
		var control: Control = child as Control
		if control == null or not control.visible:
			continue
		shown += 1
		var label: Label = control as Label
		if label != null \
				and label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			total += wrapped_text_height(label, content_width)
		else:
			total += control.get_combined_minimum_size().y
	if shown > 1:
		total += float(shown - 1) \
			* float(stack.get_theme_constant("separation"))
	return total


## Wrapped height of one label from its live shaped lines, capped at
## its own max-lines budget with the theme spacing between lines. The
## count is valid synchronously once the caller bounds the label width,
## which every gate card does before fitting, so wrapped text and
## explicit newlines both measure honestly. `get_string_size` only ever
## measured one line here and underfit every two-line note by a line.
static func wrapped_text_height(label: Label, _width: float) -> float:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var line: float = float(font.get_height(font_size))
	var spacing: float = float(
		label.get_theme_constant("line_spacing"))
	var lines: int = maxi(label.get_line_count(), 1)
	if label.max_lines_visible > 0:
		lines = mini(lines, label.max_lines_visible)
	return float(lines) * line + float(maxi(lines - 1, 0)) * spacing


## Soft radial glow drawn from code, so effects need no texture files.
## `size` is the texture edge in pixels; `inner`/`outer` are its colors.
static func radial_glow(size: int, inner: Color, outer: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, inner)
	gradient.set_color(1, outer)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	return texture


static func _paired_font(base_path: String, fallback_path: String) -> Font:
	var variation := FontVariation.new()
	variation.base_font = load(base_path) as Font
	var fallbacks: Array[Font] = []
	var fallback: Font = load(fallback_path) as Font
	if fallback != null:
		fallbacks.append(fallback)
	variation.fallbacks = fallbacks
	return variation


static func _ensure_button_styles() -> void:
	if not _buttons.is_empty():
		return
	_buttons["normal"] = _button_set(GateFrameStyle.Accent.STEEL)
	_buttons["primary"] = _button_set(GateFrameStyle.Accent.GOLD)
	_buttons["danger"] = _button_set(GateFrameStyle.Accent.CORAL)
	_buttons["portal"] = _button_set(GateFrameStyle.Accent.MINT)


static func _button_set(accent: int) -> Dictionary:
	return {
		"normal": GateFrameStyle.new(
			GateFrameStyle.Kind.BUTTON, accent,
			GateFrameStyle.State.NORMAL),
		"hover": GateFrameStyle.new(
			GateFrameStyle.Kind.BUTTON, accent,
			GateFrameStyle.State.HOVER),
		"pressed": GateFrameStyle.new(
			GateFrameStyle.Kind.BUTTON, accent,
			GateFrameStyle.State.PRESSED),
		"disabled": GateFrameStyle.new(
			GateFrameStyle.Kind.BUTTON, accent,
			GateFrameStyle.State.DISABLED),
		"focus": GateFrameStyle.new(
			GateFrameStyle.Kind.FOCUS, accent,
			GateFrameStyle.State.NORMAL),
	}
