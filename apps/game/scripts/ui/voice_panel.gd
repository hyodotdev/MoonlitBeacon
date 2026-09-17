class_name VoicePanel
extends Control

## Shows one combat line from the hero as a dialogue strip at the bottom.
##
## Successor to the speech bubble (`speech_bubble.gd`). That bubble sat above
## the player's head, and because the camera follows the player they are always
## screen-center — so the bubble **always covered the hero.** It took three
## store screenshots going out that way before it showed. A fixed bottom strip
## never overlaps the character.
##
## Role differs from cycle story dialogue (`dialogue_scene.gd`) — that pauses
## the game and waits for a tap. This **does not pause.** It appears, fades on
## its own, and swaps in place when a new line arrives.

const PANEL_HEIGHT: float = 34.0
const PORTRAIT: float = 24.0
const MARGIN_X: float = 5.0
const FONT: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Multilingual.tres")
const FONT_SIZE: int = 13
## Even a short line gets time to be read. Longer lines hold by character count.
const HOLD_BASE: float = 1.9
const HOLD_PER_CHAR: float = 0.045
const FADE: float = 0.14

var _icon: TextureRect = null
var _text: Label = null
var _tween: Tween = null


func _ready() -> void:
	# Centered bottom strip. Control buttons sit left and right, so use about half width.
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -210.0
	offset_right = 210.0
	offset_top = -PANEL_HEIGHT - 6.0
	offset_bottom = -6.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false

	var panel := PanelContainer.new()
	panel.name = &"Box"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	# Dark panel in the same family as the cycle story dialogue. Text stands on
	# the combat screen, and the panel is translucent so the field behind it
	# does not go fully dead.
	style.bg_color = Color(0.05, 0.08, 0.14, 0.86)
	style.border_color = Color(0.42, 0.58, 0.86, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(4.0)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var row := HBoxContainer.new()
	row.name = &"Row"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	_icon = TextureRect.new()
	_icon.name = &"Portrait"
	_icon.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)

	_text = Label.new()
	_text.name = &"Text"
	_text.add_theme_font_override("font", FONT)
	_text.add_theme_font_size_override("font_size", FONT_SIZE)
	_text.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0, 1.0))
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_text)


## Show one line. If already up, swap the sentence and restart the timer.
func say(hero: Hero, line: String) -> void:
	if line.is_empty():
		return
	if hero != null:
		_icon.texture = hero.idle_icon_texture()
	_text.text = line
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = true
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE)
	_tween.tween_interval(HOLD_BASE + HOLD_PER_CHAR * float(line.length()))
	_tween.tween_property(self, "modulate:a", 0.0, FADE * 2.0)
	_tween.tween_callback(func() -> void: visible = false)


## Walk off quietly when the run ends.
func clear() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	visible = false
