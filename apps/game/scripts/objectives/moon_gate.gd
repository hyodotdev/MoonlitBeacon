extends Node2D

## Moonlight gate.
##
## It opens only after every beacon is lit. Until then it is fully hidden —
## a closed door on screen makes people wander, thinking they should go there.

## Fired when the player walks in.
signal entered

## Time it takes to open.
const OPEN_SECONDS: float = 1.2

const LABEL_FONT: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres"
)

@onready var _enter: Area2D = $Enter
@onready var _sprite: Sprite2D = $Sprite
@onready var _halo: Sprite2D = $Halo
@onready var _light: PointLight2D = $Light

## Built the first time this gate names a destination. A plain gate never has one.
var _label: Label = null

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


## Say where this gate leads. A fork has two, so each carries the place's name in its own colour,
## and a second line for what waits there (an omen, or the guardian).
func set_destination(title: String, detail: String, accent: Color) -> void:
	if _label == null:
		_label = Label.new()
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.size = Vector2(150, 26)
		_label.position = Vector2(-75, -82)
		_label.add_theme_font_override("font", LABEL_FONT)
		_label.add_theme_font_size_override("font_size", 9)
		_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.95))
		_label.add_theme_constant_override("outline_size", 4)
		add_child(_label)
	_label.text = title if detail.is_empty() else title + "\n" + detail
	_label.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.25))
	_label.visible = true
	_sprite.modulate = accent.lerp(Color.WHITE, 0.45)
	_halo.modulate = accent
	_light.color = accent


## Put the gate back to a plain, unnamed one.
func clear_destination() -> void:
	if _label != null:
		_label.visible = false
	_sprite.modulate = Color.WHITE
	_halo.modulate = Color.WHITE
	_light.color = Color(0.62, 0.78, 1, 1)


## Close it fully so the same gate can be reused on the next terrain.
func close() -> void:
	_open = false
	_generation += 1
	_enter.set_deferred("monitoring", false)
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 0.0
	visible = false
	clear_destination()


func _on_body_entered(_body: Node2D) -> void:
	if not _open:
		return
	entered.emit()
