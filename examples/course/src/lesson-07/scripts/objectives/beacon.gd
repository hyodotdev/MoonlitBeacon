## One beacon: dim until lit; near a player it charges, then ignites.
extends Node2D

signal lit_changed(beacon: Node2D, lit: bool)
signal charge_changed(beacon: Node2D, ratio: float)

const DIM_ENERGY: float = 0.5
const CHARGE_SECONDS: float = 2.0
const REACH_RADIUS: float = 34.0

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
@onready var _reach: Area2D = $Reach
@onready var _ignite_sound: AudioStreamPlayer2D = $IgniteSound

var _charge: float = 0.0
var _visitors: int = 0


func _ready() -> void:
	_apply_lit()
	_apply_flicker_speed()
	_normalize_reach()
	_reach.body_entered.connect(_on_body_entered)
	_reach.body_exited.connect(_on_body_exited)
	set_process(false)


func ignite() -> void:
	lit = true


func get_charge() -> float:
	return _charge


func is_audio_playing() -> bool:
	return AudioFlush.is_playing(_ignite_sound)


func stop_audio() -> void:
	AudioFlush.stop_player(_ignite_sound)


func _process(delta: float) -> void:
	if lit:
		set_process(false)
		return
	if _visitors > 0:
		_charge = minf(_charge + delta / CHARGE_SECONDS, 1.0)
	else:
		_charge = maxf(_charge - delta / CHARGE_SECONDS, 0.0)
		if _charge <= 0.0:
			set_process(false)
	charge_changed.emit(self, _charge)
	if _charge >= 1.0:
		_ignite_sound.play()
		ignite()


func _on_body_entered(_body: Node2D) -> void:
	_visitors += 1
	set_process(true)


func _on_body_exited(_body: Node2D) -> void:
	_visitors = maxi(_visitors - 1, 0)
	if _visitors == 0 and (lit or _charge <= 0.0):
		set_process(false)


func _normalize_reach() -> void:
	## Keep the sensor at REACH_RADIUS world pixels whatever the instance scale.
	var shape: CircleShape2D = _reach.get_node("ReachShape").shape.duplicate()
	_reach.get_node("ReachShape").shape = shape
	var world_scale: float = maxf(absf(global_scale.x), absf(global_scale.y))
	shape.radius = REACH_RADIUS / world_scale


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
