## Owns the arena stage: centering, ignition, brightness, stick input.
extends Node2D

const BRIGHTEN_SECONDS: float = 1.2
const UNLIT_FOREST: Color = Color(0.315, 0.35, 0.57)

@onready var _forest: Node2D = $NightForest
@onready var _music: AudioStreamPlayer = $Music
@onready var _player: CharacterBody2D = $Player
@onready var _stick: Control = $Ui/MoveStick

var _beacons: Array = []
var _lit_count: int = 0
var _brighten: Tween


func _ready() -> void:
	_apply_centering()
	get_tree().root.size_changed.connect(_apply_centering)
	get_tree().set_auto_accept_quit(false)
	get_tree().root.close_requested.connect(_quit_gracefully)
	_beacons = [$BeaconWest, $BeaconNorth, $BeaconEast]
	for beacon in _beacons:
		beacon.lit_changed.connect(_on_beacon_lit_changed)
		beacon.charge_changed.connect(_on_beacon_charge_changed)
	_update_brightness(false)
	AudioFlush.loop_stream(_music)


func _process(_delta: float) -> void:
	_player.set_move_input(_stick.get_value())


func _apply_centering() -> void:
	position = Screen.center_offset(get_viewport_rect().size)


func _on_beacon_lit_changed(_beacon: Node2D, lit: bool) -> void:
	_lit_count = clampi(_lit_count + (1 if lit else -1), 0, _beacons.size())
	_update_brightness(true)


func _update_brightness(animated: bool) -> void:
	var target: Color = UNLIT_FOREST.lerp(Color.WHITE, float(_lit_count) / float(_beacons.size()))
	if _brighten and _brighten.is_valid():
		_brighten.kill()
	if not animated:
		_forest.modulate = target
		return
	_brighten = create_tween()
	_brighten.tween_property(_forest, "modulate", target, BRIGHTEN_SECONDS)


func _on_beacon_charge_changed(_beacon: Node2D, _ratio: float) -> void:
	var top: float = 0.0
	for beacon in _beacons:
		top = maxf(top, beacon.get_charge())
	_player.set_charge(top)


func release_audio() -> void:
	## Call before leaving the arena (restart, quit to title) so the exit
	## finds silence and pays no mix-wait. Process quits skip this call and
	## pay one wait in _exit_tree instead.
	for beacon in _beacons:
		beacon.stop_audio()
	AudioFlush.stop_player(_music)


func _exit_tree() -> void:
	var active: bool = AudioFlush.is_playing(_music)
	for beacon in _beacons:
		active = beacon.is_audio_playing() or active
	release_audio()
	if active:
		AudioFlush.wait_for_mix()


func _quit_gracefully() -> void:
	## The player closed the window: release our own audio while the loop
	## still runs, let the mix drain, then quit. Quitting with voices
	## playing leaks under the headless driver.
	release_audio()
	AudioFlush.wait_for_mix()
	get_tree().quit()
