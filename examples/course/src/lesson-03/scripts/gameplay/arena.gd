## Owns the arena stage: centering now, beacons and the run later.
extends Node2D

@onready var _music: AudioStreamPlayer = $Music


func _ready() -> void:
	_apply_centering()
	get_tree().root.size_changed.connect(_apply_centering)
	get_tree().set_auto_accept_quit(false)
	get_tree().root.close_requested.connect(_quit_gracefully)
	AudioFlush.loop_stream(_music)


func _exit_tree() -> void:
	## Quitting mid-music needs one audio mix after the stop. A transition
	## that already stopped the music pays no wait.
	var active: bool = AudioFlush.is_playing(_music)
	AudioFlush.stop_player(_music)
	if active:
		AudioFlush.wait_for_mix()


func _apply_centering() -> void:
	position = Screen.center_offset(get_viewport_rect().size)


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
