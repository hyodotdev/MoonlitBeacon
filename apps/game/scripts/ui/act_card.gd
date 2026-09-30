extends Control

## The card that opens an act: a storybook chapter page.
##
## `ACT I · The Debt`, a line under it, and nothing else. It appears on the
## cycle an act **begins** (`Acts.starting_at`) and ahead of that cycle's
## dialogue, so the story reads as chapters instead of one long run of lines.
##
## Same contract as the dialogue scene: it pauses the game while open, closes on
## a tap, unpauses, and emits `finished`. It opens only where the story already
## has the screen (after the reward pick), so it never interrupts a fight.

signal finished

## Ignore taps this long after opening. The tap that closed the loot panel is
## still in flight; without this the card would be dismissed by the very input
## that summoned it, before anyone read it.
const ARM_SECONDS: float = 1.1
## Stagger between the label, the title and the epigraph rising into place.
const RISE_STAGGER: float = 0.28
const RISE_SECONDS: float = 0.5
## A card nobody taps still closes, so a forgotten phone is not stuck on it.
const AUTO_CLOSE_SECONDS: float = 12.0

@onready var _beacon: TextureRect = $Center/Column/Beacon
@onready var _label: Label = $Center/Column/Label
@onready var _title: Label = $Center/Column/Title
@onready var _epigraph: Label = $Center/Column/Epigraph
@onready var _hint: Label = $Center/Column/Hint

var _open: bool = false
var _armed: bool = false
var _age: float = 0.0


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


## Show the card for one act. `act` is what `Acts` returns.
func play(act: Dictionary) -> void:
	if act.is_empty():
		finished.emit()
		return
	_label.text = tr(str(act["label"]))
	_title.text = tr(str(act["title"]))
	_epigraph.text = tr(str(act["epigraph"]))
	_open = true
	_armed = false
	_age = 0.0
	visible = true
	grab_focus()
	modulate.a = 0.0
	_hint.modulate.a = 0.0
	get_tree().paused = true
	set_process(true)

	var fade: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.tween_property(self, "modulate:a", 1.0, 0.3)
	# Each element rises into place one after another.
	var rise: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var parts: Array[Control] = [_beacon, _label, _title, _epigraph]
	for index in parts.size():
		var part: Control = parts[index]
		part.modulate.a = 0.0
		var delay: float = 0.25 + RISE_STAGGER * float(index)
		rise.parallel().tween_property(part, "modulate:a", 1.0, RISE_SECONDS) \
			.set_delay(delay)


func is_open() -> bool:
	return _open


func _process(delta: float) -> void:
	if not _open:
		return
	_age += delta
	if not _armed and _age >= ARM_SECONDS:
		_armed = true
		# The prompt only appears once the card can actually be dismissed.
		create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) \
			.tween_property(_hint, "modulate:a", 1.0, 0.4)
	if _age >= AUTO_CLOSE_SECONDS:
		_close()


func _gui_input(event: InputEvent) -> void:
	_try_dismiss(event)


func _unhandled_input(event: InputEvent) -> void:
	_try_dismiss(event)


func _try_dismiss(event: InputEvent) -> void:
	if not _open or not _armed:
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
	_close()


func _close() -> void:
	if not _open:
		return
	_open = false
	release_focus()
	set_process(false)
	# Stay paused through the fade and unpause only at the last moment, in the
	# same call that emits `finished`. The arena opens the cycle's dialogue from
	# that signal, and it pauses again before a single frame runs — unpausing
	# earlier would give enemies a quarter second of free movement between the
	# two screens.
	var fade: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.tween_property(self, "modulate:a", 0.0, 0.22)
	fade.tween_callback(func() -> void:
		visible = false
		get_tree().paused = false
		finished.emit())
