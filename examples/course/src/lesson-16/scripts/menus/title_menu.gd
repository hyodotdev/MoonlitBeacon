## Title screen: centers its art, then hands the run to the arena on tap.
extends Control

signal start_requested

## Where a tap takes you.
## Keep the path in this one line so there is one place to edit if the arena file moves.
const ARENA_SCENE: String = "res://scenes/gameplay/arena.tscn"
const BGM_FADE_OUT_SECONDS: float = 0.55
const BGM_SILENCE_DB: float = -80.0
const SHAFTS_HOME: Vector2 = Vector2(404, 100)
const HEARTH_HOME: Vector2 = Vector2(404, 240)

@onready var _shafts: Sprite2D = $Shafts
@onready var _hearth: Sprite2D = $Hearth
@onready var _tap: Button = $TapCatcher
@onready var _prompt: Label = $Prompt
@onready var _settings_button: Button = $SettingsButton
@onready var _settings_panel: Control = $SettingsPanel
@onready var _quit_prompt: Control = $QuitPrompt
@onready var _bgm: AudioStreamPlayer = $Bgm
@onready var _sfx: AudioStreamPlayer = $Confirm

var _started: bool = false


func _ready() -> void:
	_apply_centering()
	get_tree().root.size_changed.connect(_apply_centering)
	get_tree().set_auto_accept_quit(false)
	get_tree().root.close_requested.connect(_quit_gracefully)
	AudioFlush.loop_stream(_bgm)
	_tap.pressed.connect(request_start)
	start_requested.connect(_enter_arena)
	_settings_button.pressed.connect(_settings_panel.open)
	_quit_prompt.quit_confirmed.connect(_quit_gracefully)
	Settings.changed.connect(_redraw)
	_redraw()


func _redraw() -> void:
	_prompt.text = tr("TAP_START")
	_settings_button.text = tr("SETTINGS")


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _settings_panel.is_open():
		_settings_panel.close()
	elif _quit_prompt.is_open():
		_quit_prompt.close()
	else:
		_quit_prompt.open()


func request_start() -> void:
	if _started:
		return
	_started = true
	start_requested.emit()


func _apply_centering() -> void:
	var offset: Vector2 = Screen.center_offset(get_viewport_rect().size)
	_shafts.position = SHAFTS_HOME + offset
	_hearth.position = HEARTH_HOME + offset


func _exit_tree() -> void:
	## Quitting mid-music needs one audio mix after the stop; the arena
	## transition already stopped everything, so it pays no wait.
	var active: bool = AudioFlush.is_playing(_bgm) or AudioFlush.is_playing(_sfx)
	AudioFlush.stop_player(_bgm)
	AudioFlush.stop_player(_sfx)
	if active:
		AudioFlush.wait_for_mix()


func _enter_arena() -> void:
	await _fade_out_music()
	get_tree().change_scene_to_file(ARENA_SCENE)


func _fade_out_music() -> void:
	var fade: Tween = create_tween()
	fade.tween_property(_bgm, "volume_db", BGM_SILENCE_DB, BGM_FADE_OUT_SECONDS)
	await fade.finished
	if not is_inside_tree():
		return
	AudioFlush.stop_player(_bgm)
	AudioFlush.stop_player(_sfx)


func release_audio() -> void:
	## Stop every voice this scene owns. Call before leaving the scene or
	## quitting while the main loop still runs, then give the audio thread
	## one mix (AudioFlush.wait_for_mix) before the process exits.
	AudioFlush.stop_player(_bgm)
	AudioFlush.stop_player(_sfx)


func _quit_gracefully() -> void:
	## The player closed the window or confirmed the quit prompt: release
	## our own audio while the loop still runs, let the mix drain, then
	## quit. Quitting with voices playing leaks under the headless driver.
	release_audio()
	AudioFlush.wait_for_mix()
	get_tree().quit()
