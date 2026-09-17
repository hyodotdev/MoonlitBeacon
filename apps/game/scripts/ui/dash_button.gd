extends Control

## Dash button. Bottom-right corner.
##
## Used to be **the right half of the screen**. That was a straight lift of
## Brawl Stars-style dual floating sticks, which is the right design for a
## twin-stick shooter.
##
## This game became a survivor. That genre's standard is **one move stick +
## auto attack**, and a dash is a small corner button (Vampire Survivors and
## Survivor.io both).
##
## When half the screen was dash, this actually happened —
## **"I pressed the middle and it slid, and pressing left moved."** The split
## was dead center with no mark, so there was no way to know. The whole screen
## is movement now, so that confusion is gone.

signal pressed

## Opacity when ready versus cooling down.
const READY_ALPHA: float = 0.85
const COOLING_ALPHA: float = 0.28

@onready var _base: TextureRect = $Base
@onready var _fill: TextureRect = $Fill

var _ready_now: bool = true


func _ready() -> void:
	set_ratio(1.0)


## How full the dash is. The arena passes this every frame.
##
## No numbers. All you need is "can I do it now," and counting a 1-second
## cooldown to a decimal makes the screen noisy.
func set_ratio(ratio: float) -> void:
	var full: bool = ratio >= 1.0
	_fill.modulate.a = 0.15 + 0.85 * clampf(ratio, 0.0, 1.0)
	_base.modulate.a = READY_ALPHA if full else COOLING_ALPHA

	# Pop once the instant it fills. The eye catches that moment.
	if full and not _ready_now:
		var pop: Tween = create_tween()
		pop.tween_property(self, "scale", Vector2(1.18, 1.18), 0.08)
		pop.tween_property(self, "scale", Vector2.ONE, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ready_now = full


## Was this press on the button.
##
## Uses `_gui_input`. The move stick covers the whole screen, but this button
## sits **later in the tree** so it gets input first. `accept_event()` here
## stops the event from reaching the stick — no walking off while trying to dash.
func _gui_input(event: InputEvent) -> void:
	var began: bool = false
	if event is InputEventScreenTouch:
		began = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		began = (event as InputEventMouseButton).pressed
	if not began:
		return
	accept_event()
	pressed.emit()
