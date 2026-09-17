extends Node2D

## Moonlight gate.
##
## It opens only after every beacon is lit. Until then it is fully hidden —
## a closed door on screen makes people wander, thinking they should go there.

## Fired when the player walks in.
signal entered

## Time it takes to open.
const OPEN_SECONDS: float = 1.2

@onready var _enter: Area2D = $Enter

var _open: bool = false
var _fade: Tween = null
var _generation: int = 0


func _ready() -> void:
	modulate.a = 0.0
	visible = false
	# While closed, walking in must do nothing.
	_enter.monitoring = false
	_enter.body_entered.connect(_on_body_entered)


func open() -> void:
	if _open:
		return
	_open = true
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_generation += 1
	var generation: int = _generation
	visible = true
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, OPEN_SECONDS)
	_fade.finished.connect(_finish_open.bind(generation))


func _finish_open(generation: int) -> void:
	if not is_inside_tree() or not _open or generation != _generation:
		return
	# Turn it on only after it is fully open. Brushing past mid-open would end the run for nothing.
	_enter.monitoring = true


## Close it fully so the same gate can be reused on the next terrain.
func close() -> void:
	_open = false
	_generation += 1
	_enter.set_deferred("monitoring", false)
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 0.0
	visible = false


func _on_body_entered(_body: Node2D) -> void:
	if not _open:
		return
	entered.emit()
