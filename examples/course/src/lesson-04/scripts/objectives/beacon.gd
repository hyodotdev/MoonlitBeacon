## One beacon: dim and still until lit, then fire and flicker.
extends Node2D

signal lit_changed(beacon: Node2D, lit: bool)

const DIM_ENERGY: float = 0.5

@export var lit: bool = false:
	set(value):
		if lit == value:
			return
		lit = value
		_apply_lit()
@export_range(0.2, 3.0) var flicker_speed: float = 1.0:
	set(value):
		flicker_speed = value
		_apply_flicker_speed()

@onready var _light: PointLight2D = $Light
@onready var _glow: Sprite2D = $Glow
@onready var _flame: GPUParticles2D = $Flame
@onready var _flicker: AnimationPlayer = $Flicker


func _ready() -> void:
	_apply_lit()
	_apply_flicker_speed()


func ignite() -> void:
	lit = true


func _apply_lit() -> void:
	if not is_node_ready():
		return
	if lit:
		_glow.visible = true
		_flame.emitting = true
		_flicker.play("flicker")
	else:
		_flicker.stop()
		_light.energy = DIM_ENERGY
		_glow.visible = false
		_flame.emitting = false
	lit_changed.emit(self, lit)


func _apply_flicker_speed() -> void:
	if not is_node_ready():
		return
	_flicker.speed_scale = flicker_speed
