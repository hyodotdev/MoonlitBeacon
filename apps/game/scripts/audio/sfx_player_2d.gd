extends AudioStreamPlayer2D

## Short positional SFX. When the west beacon lights, the sound comes from the left.
##
## Cleanup follows the same rule as music — the full story is in `AudioFlush`.

var _needs_flush: bool = false


func _ready() -> void:
	_needs_flush = autoplay
	set_process(not _needs_flush)


func _process(_delta: float) -> void:
	if not playing:
		return
	_needs_flush = true
	set_process(false)


## Call this before leaving the scene. Same rule as `music_player.release()`.
func release() -> void:
	if not _needs_flush:
		return
	_needs_flush = false
	stop()


func _exit_tree() -> void:
	if not _needs_flush:
		return
	_needs_flush = false
	stop()
	AudioFlush.wait()
