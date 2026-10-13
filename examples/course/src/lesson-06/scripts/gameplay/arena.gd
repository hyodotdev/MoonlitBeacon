## Owns the arena stage: centering, ignition, brightness, stick input.
extends Node2D

const FIRST_IGNITE_DELAY: float = 2.0
const IGNITE_INTERVAL: float = 2.6
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
	_update_brightness(false)
	_run_ignition_sequence()
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


func _run_ignition_sequence() -> void:
	await get_tree().create_timer(FIRST_IGNITE_DELAY).timeout
	for beacon in _beacons:
		beacon.ignite()
		await get_tree().create_timer(IGNITE_INTERVAL).timeout


func _exit_tree() -> void:
	## Quitting mid-music needs one audio mix after the stop. A transition
	## that already stopped the music pays no wait.
	var active: bool = AudioFlush.is_playing(_music)
	AudioFlush.stop_player(_music)
	if active:
		AudioFlush.wait_for_mix()


func release_audio() -> void:
	## See title_menu.release_audio: stop now, mix-wait while running.
	AudioFlush.stop_player(_music)


func _quit_gracefully() -> void:
	## The player closed the window: release our own audio while the loop
	## still runs, let the mix drain, then quit. Quitting with voices
	## playing leaks under the headless driver.
	release_audio()
	AudioFlush.wait_for_mix()
	get_tree().quit()
