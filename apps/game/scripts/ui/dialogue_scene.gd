extends Control

## Visual-novel style dialogue. Bust on the left, nameplate and box below.
##
## Role differs from a combat one-liner (`voice_panel.gd`). That is a muttered
## aside **during play**, so it does not freeze the screen. This scene opens
## only where **the story advances**, and it pauses the game while open — do
## not make people read while their hands are busy.
##
## It opens when a cycle rolls over. That moment is already paused for the
## loot panel, so nothing extra is cut.

signal finished

## Typewriter speed (characters per second). Tap before it finishes and it completes at once.
const TYPE_SPEED: float = 42.0
## Blip every this many characters. One per letter is 42 times a second and hurts.
const BLIP_EVERY: int = 3
## Jitter pitch by this much. The same sound on repeat sounds like a machine talking.
const BLIP_PITCH_SPREAD: float = 0.14

@onready var _dim: ColorRect = $Dim
@onready var _bust: TextureRect = $Bust
@onready var _name_plate: Panel = $Box/NamePlate
@onready var _name_label: Label = $Box/NamePlate/Name
@onready var _text: Label = $Box/Text
@onready var _hint: Label = $Box/Hint
@onready var _skip: Button = $Skip
@onready var _blip: AudioStreamPlayer = $Blip

var _lines: Array[String] = []
var _index: int = 0
var _typed: float = 0.0
var _typing: bool = false
var _blipped: int = 0
var _open: bool = false


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_skip.pressed.connect(_close)


## Show several lines in order. The hero's bust and name come with them.
func play(hero: Hero, lines: Array[String]) -> void:
	if lines.is_empty():
		finished.emit()
		return
	_lines = lines
	_index = 0
	_open = true

	if hero != null:
		_name_label.text = tr(hero.display_name)
		_name_plate.modulate = hero.accent
		var bust_path: String = "res://assets/custom/ui/busts/%s.png" % \
			hero.resource_path.get_file().get_basename()
		if ResourceLoader.exists(bust_path):
			_bust.texture = load(bust_path)
			_bust.visible = true
		else:
			_bust.visible = false

	visible = true
	grab_focus()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	get_tree().paused = true
	_start_line()


func is_open() -> bool:
	return _open


func _start_line() -> void:
	_text.text = _lines[_index]
	_text.visible_ratio = 0.0
	_typed = 0.0
	_typing = true
	_blipped = 0
	_hint.visible = false
	set_process(true)


func _process(delta: float) -> void:
	if not _typing:
		return
	_typed += delta * TYPE_SPEED
	var total: float = float(_text.text.length())
	_text.visible_ratio = clampf(_typed / maxf(total, 1.0), 0.0, 1.0)
	var shown: int = int(_typed)
	if shown >= _blipped + BLIP_EVERY:
		_blipped = shown
		_play_blip()
	if _text.visible_ratio >= 1.0:
		_typing = false
		_hint.visible = true
		set_process(false)


## One character blip. Pitch shifts a little each time.
func _play_blip() -> void:
	_blip.pitch_scale = 1.0 + randf_range(-BLIP_PITCH_SPREAD, BLIP_PITCH_SPREAD)
	_blip.play()


## Tap anywhere to advance. If typing is unfinished, complete it first.
func _gui_input(event: InputEvent) -> void:
	_try_advance_input(event)


## Some platforms deliver pad input as unhandled before the focused Control's
## GUI path. Both funnel into the same function; the GUI path calls
## accept_event so a line does not advance twice.
func _unhandled_input(event: InputEvent) -> void:
	_try_advance_input(event)


func _try_advance_input(event: InputEvent) -> void:
	if not _open:
		return
	var pressed: bool = false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		pressed = key.pressed and not key.echo
	elif event is InputEventJoypadButton:
		pressed = (event as InputEventJoypadButton).pressed
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	_advance()


func _advance() -> void:
	if _typing:
		# Do not make someone who already read it wait.
		_typing = false
		_blip.stop()
		_text.visible_ratio = 1.0
		_hint.visible = true
		set_process(false)
		return
	_index += 1
	if _index >= _lines.size():
		_close()
		return
	_start_line()


func _close() -> void:
	if not _open:
		return
	_open = false
	release_focus()
	set_process(false)
	_blip.stop()
	get_tree().paused = false
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.16)
	fade.tween_callback(func() -> void:
		visible = false
		finished.emit())
