extends AudioStreamPlayer

## If this has ever played, give the audio thread one mix when it leaves the tree.
##
## Cleanup is documented in `AudioFlush`. Call `release()` before swapping scenes
## so that wait does not land on a transition frame.

var _needs_flush: bool = false


func _ready() -> void:
	# Autoplay is started by the engine, so mark it immediately.
	# Otherwise watch until sound actually starts.
	#
	# Overriding `play()` would be nicer, but it is native so GDScript blocks it.
	#   Parse Error: The method "play()" overrides a method from native class
	#   "AudioStreamPlayer". This won't be called by the engine.
	# Watching `_process` is the reliable way to catch every start.
	_needs_flush = autoplay
	set_process(not _needs_flush)


func _process(_delta: float) -> void:
	if not playing:
		return
	_needs_flush = true
	set_process(false)


## Call this before leaving the scene. If at least one frame has passed after
## this call, `_exit_tree()` can return immediately and the transition does not stall.
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
