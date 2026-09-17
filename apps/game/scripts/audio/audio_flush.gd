class_name AudioFlush
extends RefCounted

## Give the audio thread time to actually free playback nodes.
##
## If the engine shuts down while an Ogg is still playing, you get:
##   WARNING: 4 ObjectDB instances were leaked at exit
##   ERROR: 2 resources still in use at exit
##
## `AudioStreamPlayer` stops itself when it leaves the tree, but that stop only
## marks the node in AudioServer's playback list as "to be removed". The real
## free happens on the audio thread's next mix. If engine teardown starts before
## that mix, the playback node's references stay alive.
##
## Windowed mode was clean at 45ms in measurement, but the `--headless` dummy
## driver has a longer mix period and needed 120ms. 150ms is the floor with
## headroom.
##
## [b]This wait stalls the whole frame.[/b] Stop audio before swapping scenes
## and there is nothing to do here, so the transition stays smooth.
##
## `AudioStreamPlayer` and `AudioStreamPlayer2D` do not share a scriptable
## parent, so the wait lives here and both call into it.

const MIN_MSEC: int = 150
const LATENCY_FACTOR: int = 8


static func wait() -> void:
	var latency_msec: int = int(ProjectSettings.get_setting("audio/driver/output_latency", 15))
	OS.delay_msec(maxi(latency_msec * LATENCY_FACTOR, MIN_MSEC))
