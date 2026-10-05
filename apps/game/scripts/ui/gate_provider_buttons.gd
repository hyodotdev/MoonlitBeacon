class_name GateProviderButtons
extends RefCounted

## Official Google / Apple sign-in doors for the moon gate entry.
##
## The two real providers wear their vendor-brand faces, not the game's
## fantasy frames: Google is the custom light button from the current
## branding guide (white fill, inside 1px #747775 stroke, #1f1f1f text
## in Google Sans Medium with the gradient Super G), Apple is the black
## button from the Human Interface Guide (black fill, white title, the
## official padded white artwork). Guest and every extra provider keep
## the game's own GateEntryStyle look; only `google` and `apple` ids
## ever reach this factory.
##
## Composition is deliberate, not native: the Button holds the vendor
## styleboxes and the native press, hover, focus, and disabled semantics
## with no native text or icon of its own, and a full-rect `Group`
## anchors the official mark (`Logo`) on a stable left column beside
## the real action title (`Title`) centered on the whole door axis, all
## mouse-transparent. The native icon-plus-text path cannot do this —
## title CENTER and icon CENTER land independently on the same axis and
## the mark covers the middle of the text — so the anchors below are
## the only centering story. Both doors are full card width at 44px
## touch height with an 8px radius; each mark centers on the shared
## 32px left column while each title centers on the shared door axis
## with symmetric reserved edge space, independent of word length. The
## Button's `accessibility_labeled_by_nodes` points at `Title`, so the
## actionable control reads its visible translated label.
##
## The Google mark is the measured 79x80 glyph alone, drawn from the
## unmodified tile at an explicit 20px logical height with the spec
## platform padding and no baked tile padding; both donor tiles carry
## the identical glyph at different offsets, and the factory draws each
## platform's own tile. Apple uses the whole padded file scaled to the
## button height, never the glyph alone.
##
## No state tints the marks or fades the titles: the logo nodes keep a
## white modulate and every title ink — including disabled — stays fully
## opaque, so an unconfigured door still reads dark Google ink on white
## and white Apple ink on black. Readiness stays honest through the
## entry's own disabled flag and its separate provider note, never
## through dimming. Focus is an outer ring drawn outside the button
## rect, so the logo pixels never change under keyboard focus.

const GOOGLE_ANDROID_TILE: String = \
	"res://assets/third_party/signin/google-android-icon-official.png"
const GOOGLE_IOS_TILE: String = \
	"res://assets/third_party/signin/google-ios-icon-official.png"
const APPLE_ARTWORK: String = \
	"res://assets/third_party/signin/apple-left-white-medium.svg"
const GOOGLE_SANS_PATH: String = \
	"res://assets/third_party/fonts/GoogleSans[GRAD,opsz,wght].ttf"

const GOOGLE_FILL: Color = Color(1, 1, 1)
const GOOGLE_FILL_HOVER: Color = Color(0.949, 0.949, 0.949)
const GOOGLE_FILL_PRESSED: Color = Color(0.902, 0.902, 0.902)
const GOOGLE_STROKE: Color = Color("747775")
const GOOGLE_INK: Color = Color("1f1f1f")
const GOOGLE_FOCUS_RING: Color = Color("1a73e8")
const APPLE_FILL: Color = Color(0, 0, 0)
const APPLE_FILL_HOVER: Color = Color(0.063, 0.063, 0.063)
const APPLE_FILL_PRESSED: Color = Color(0.173, 0.173, 0.18)
const APPLE_INK: Color = Color(1, 1, 1)
const APPLE_FOCUS_RING: Color = Color(1, 1, 1)

const BUTTON_HEIGHT: float = 44.0
const CORNER_RADIUS: int = 8
const GOOGLE_FONT_SIZE: int = 14
## Apple custom typography is permitted by the sign-in guide; 14 matches
## Google's explicit brand type, so both titles share one visual size and
## one baseline family with neither door outsized — equal prominence.
const APPLE_FONT_SIZE: int = 14
const GOOGLE_WEIGHT: int = 500
## Measured G ink bounds in each donor tile, in tile pixels: every
## colorful pixel (channel spread above 8) with zero transparent,
## neutral-dark, or sub-threshold fringe pixels in or around the box.
## Both tiles carry the identical 79x80 glyph at different offsets.
const GOOGLE_GLYPH_ANDROID: Rect2 = Rect2(40, 40, 79, 80)
const GOOGLE_GLYPH_IOS: Rect2 = Rect2(48, 48, 79, 80)
## Explicit logical draw height of the G mark: the logo node's minimum
## height, fitted from the measured glyph region. The 20px G balances
## the ~19px Apple glyph on the shared 44px door.
const GOOGLE_GLYPH_HEIGHT: float = 20.0
## Left-column center for both marks, from the door left: the Apple
## padded file (31 wide) starts at 16.5 and the Google glyph (19.75
## wide) at 22.1, both clearing the 16px iOS edge and the 12px
## Android edge with room for the platform clearspace.
const LOGO_CENTER_X: float = 32.0
## Symmetric title reserve per edge: the title rect insets 64px each
## side, so its center stays on the door axis while its glyphs clear
## the 47.5px Apple right edge by 16px and the longest 122px action
## fits with 39px slack per side at the 328px door width.
const TITLE_INSET: float = 64.0
## Spec edge padding per platform: Android/Web 12, iOS 16.
const EDGE_ANDROID: int = 12
const EDGE_IOS: int = 16
## Google vertical content margin: (44 - GOOGLE_GLYPH_HEIGHT) / 2 - 1.
## The composed children center in the full rect, so these margins only
## bound the native minimum size; the 44px floor keeps the door.
const GOOGLE_MARGIN_V: int = 11
const APPLE_MARGIN_V: int = 0
## Focus ring geometry: drawn fully outside the button rect.
const FOCUS_RING_WIDTH: int = 2
const FOCUS_RING_EXPAND: int = 2

static var _google_font: Font = null
static var _google_icons: Dictionary = {}
static var _apple_icon: Texture2D = null


## True for the two ids this factory brands; everything else keeps the
## game's own provider look.
static func is_official_provider(provider_id: String) -> bool:
	return provider_id == "google" or provider_id == "apple"


## Which Google tile the running platform draws: the iOS tile with its
## wider baked padding on iOS, the Android tile everywhere else.
static func google_tile_path() -> String:
	if OS.get_name() == "iOS":
		return GOOGLE_IOS_TILE
	return GOOGLE_ANDROID_TILE


## One official door: the vendor mark on the left column and the real
## title text at `action_key` centered on the whole door axis, with all
## five button states. Returns a plain Button so the entry's collectors
## and signals treat it like every other provider door.
static func make_provider_button(
		provider_id: String, action_key: String) -> Button:
	var button := Button.new()
	# No native text or icon: the engine centers those two independently
	# and the mark lands on the middle of the title. The anchors below
	# are the only content, so presses, hover, focus, and disabled stay
	# exactly the native Button's while the visuals compose by hand.
	button.text = ""
	button.clip_contents = true
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	var group := Control.new()
	group.name = &"Group"
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(group)
	var logo := TextureRect.new()
	logo.name = &"Logo"
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# The marks minify ~4x from their official rasters; mipmapped linear
	# keeps the gradient G and the Apple curves clean. The project
	# default is Nearest for pixel art, so this override is load-bearing.
	logo.texture_filter = \
		CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Anchored left column, vertically centered: the offsets land in
	# the style step once the mark size is known.
	logo.anchor_left = 0.0
	logo.anchor_right = 0.0
	logo.anchor_top = 0.5
	logo.anchor_bottom = 0.5
	group.add_child(logo)
	var title := Label.new()
	title.name = &"Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = action_key
	# Unclipped on purpose: clip_text collapses a Label's minimum width
	# to 1px. The button's own clip_contents is the overflow guard.
	title.clip_text = false
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.offset_left = TITLE_INSET
	title.offset_right = -TITLE_INSET
	group.add_child(title)
	# The actionable control reads its visible title: a live node path,
	# so assistive tech follows the translated label while native text
	# stays empty and never double-draws.
	var labeled_by: Array[NodePath] = [button.get_path_to(title)]
	button.accessibility_labeled_by_nodes = labeled_by
	if provider_id == "apple":
		_style_apple(button, group, logo, title)
	else:
		if provider_id != "google":
			push_error("official door for unknown provider: %s"
				% provider_id)
		_style_google(button, group, logo, title)
	return button


## The composed content of an official door, for tests and readback:
## the full-rect group, its left-column mark, and its centered title.
static func content_group(button: Button) -> Control:
	return button.get_node("Group") as Control


static func logo_node(button: Button) -> TextureRect:
	return button.get_node("Group/Logo") as TextureRect


static func title_node(button: Button) -> Label:
	return button.get_node("Group/Title") as Label


## Google Sans Medium with the bundled Noto Sans CJK fallback the other
## entry faces use, so localized titles keep every glyph.
static func google_font() -> Font:
	if _google_font == null:
		var variation := FontVariation.new()
		variation.base_font = load(GOOGLE_SANS_PATH) as Font
		variation.variation_opentype = {"wght": GOOGLE_WEIGHT}
		var fallbacks: Array[Font] = []
		var cjk: Font = load(
			GateEntryStyle.CJK_FONT_PATH) as Font
		if cjk != null:
			fallbacks.append(cjk)
		variation.fallbacks = fallbacks
		_google_font = variation
	return _google_font


## The measured glyph region for a tile path: a pure function of the
## path so tests can pin both platforms without switching OS.
static func glyph_region(tile_path: String) -> Rect2:
	if tile_path == GOOGLE_IOS_TILE:
		return GOOGLE_GLYPH_IOS
	return GOOGLE_GLYPH_ANDROID


## The intact official G alone, drawn from the unmodified tile. Only
## the measured glyph region ever reaches the logo: no stroke ring,
## no rounded corners, no baked padding.
static func google_icon() -> AtlasTexture:
	var path: String = google_tile_path()
	if not _google_icons.has(path):
		var crop := AtlasTexture.new()
		crop.atlas = load(path) as Texture2D
		crop.region = glyph_region(path)
		_google_icons[path] = crop
	return _google_icons[path] as AtlasTexture


## The whole padded Apple file, exactly as shipped: full-file height
## scales to the button, never the glyph alone.
static func apple_icon() -> Texture2D:
	if _apple_icon == null:
		_apple_icon = load(APPLE_ARTWORK) as Texture2D
	return _apple_icon


static func _style_google(button: Button, _group: Control,
		logo: TextureRect, title: Label) -> void:
	var crop := google_icon()
	logo.texture = crop
	var mark := Vector2(
		GOOGLE_GLYPH_HEIGHT * crop.region.size.x / crop.region.size.y,
		GOOGLE_GLYPH_HEIGHT)
	logo.custom_minimum_size = mark
	_anchor_logo(logo, mark)
	title.add_theme_font_override("font", google_font())
	title.add_theme_font_size_override("font_size", GOOGLE_FONT_SIZE)
	# One opaque ink for every state: the label has no per-state colors,
	# and a dimmed title reads as broken gray, never as honest state.
	title.add_theme_color_override("font_color", GOOGLE_INK)
	_apply_faces(button, GOOGLE_FILL, GOOGLE_FILL_HOVER,
		GOOGLE_FILL_PRESSED, GOOGLE_STROKE, GOOGLE_FOCUS_RING,
		_google_edge(), GOOGLE_MARGIN_V)


static func _style_apple(button: Button, _group: Control,
		logo: TextureRect, title: Label) -> void:
	var art := apple_icon()
	logo.texture = art
	var mark := Vector2(
		BUTTON_HEIGHT * art.get_size().x / art.get_size().y,
		BUTTON_HEIGHT)
	logo.custom_minimum_size = mark
	_anchor_logo(logo, mark)
	title.add_theme_font_override("font", GateEntryStyle.body_font())
	title.add_theme_font_size_override("font_size", APPLE_FONT_SIZE)
	# One opaque ink for every state: the label has no per-state colors,
	# and a dimmed title reads as broken gray, never as honest state.
	title.add_theme_color_override("font_color", APPLE_INK)
	_apply_faces(button, APPLE_FILL, APPLE_FILL_HOVER,
		APPLE_FILL_PRESSED, APPLE_FILL, APPLE_FOCUS_RING,
		EDGE_IOS, APPLE_MARGIN_V)


## Pin a mark on the shared left column, vertically centered: the
## offsets hold across locale and door width because the anchors do.
static func _anchor_logo(logo: TextureRect, mark: Vector2) -> void:
	logo.offset_left = LOGO_CENTER_X - mark.x * 0.5
	logo.offset_right = LOGO_CENTER_X + mark.x * 0.5
	logo.offset_top = -mark.y * 0.5
	logo.offset_bottom = mark.y * 0.5


static func _google_edge() -> int:
	if OS.get_name() == "iOS":
		return EDGE_IOS
	return EDGE_ANDROID


## Five flat brand faces plus the outer focus ring. Disabled keeps the
## brand fill and border while the title keeps its opaque ink on its own
## label; focus redraws the normal fill with the ring outside the rect,
## tinting nothing.
static func _apply_faces(button: Button, fill: Color, hover: Color,
		pressed: Color, border: Color, ring: Color, edge: int,
		margin_v: int) -> void:
	var fills: Dictionary = {
		"normal": fill,
		"hover": hover,
		"pressed": pressed,
		"disabled": fill,
	}
	for state in fills.keys():
		var face := StyleBoxFlat.new()
		face.bg_color = fills[state]
		face.border_color = border
		face.set_border_width_all(1)
		face.set_corner_radius_all(CORNER_RADIUS)
		face.content_margin_left = edge
		face.content_margin_right = edge
		face.content_margin_top = margin_v
		face.content_margin_bottom = margin_v
		face.anti_aliasing = true
		button.add_theme_stylebox_override(state, face)
	var focus := StyleBoxFlat.new()
	focus.bg_color = fill
	focus.border_color = ring
	focus.set_border_width_all(FOCUS_RING_WIDTH)
	focus.set_corner_radius_all(CORNER_RADIUS + FOCUS_RING_EXPAND)
	focus.content_margin_left = edge
	focus.content_margin_right = edge
	focus.content_margin_top = margin_v
	focus.content_margin_bottom = margin_v
	focus.expand_margin_left = FOCUS_RING_EXPAND
	focus.expand_margin_right = FOCUS_RING_EXPAND
	focus.expand_margin_top = FOCUS_RING_EXPAND
	focus.expand_margin_bottom = FOCUS_RING_EXPAND
	focus.anti_aliasing = true
	button.add_theme_stylebox_override("focus", focus)
