extends Label

## Frame meter that only appears on debug builds.
##
## Why: a mobile survivor drops frames when the screen fills up.
## And **every way of measuring from outside was blocked.**
##
## | Attempt | Result |
## | --- | --- |
## | `dumpsys gfxinfo` | `Total frames rendered: 0`. Godot draws on its own SurfaceView, so the view hierarchy never sees it |
## | `dumpsys SurfaceFlinger --latency` | The emulator does not fill timestamps |
##
## Measuring inside and drawing on screen is the surest path. A screenshot
## captures the frame count too, so there is no need to re-measure "what was it
## then" later.
##
## Release `queue_free()`s it. That is removal, not hide —
## leave it around and it will show someday.

## Hold the worst value this long. A one-frame dip is gone before the eye
## can catch it, and that one dip is the important one.
const HOLD: float = 3.0

var _worst: float = 999.0
var _hold_left: float = 0.0

## How often to log. Every frame and the log is heavier than the numbers.
const LOG_EVERY: float = 2.0
var _log_left: float = 0.0
const DISPLAY_EVERY: float = 0.25
var _display_left: float = 0.0


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	add_theme_font_size_override("font_size", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var now: float = Engine.get_frames_per_second()

	_hold_left -= delta
	if now < _worst or _hold_left <= 0.0:
		_worst = now
		_hold_left = HOLD

	# **Show where it is slow, not only fps.** fps alone forces guesswork.
	# Missile count was cut from 1034 to 56 and it was still 1fps; without
	# these numbers there was no way to tell render vs script vs physics.
	var cpu: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	# If primitives dwarf draw calls, suspect **antialiasing**.
	# Godot's `antialiased = true` turns one line into dozens of triangles.
	var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_display_left -= delta
	if _display_left <= 0.0:
		_display_left += DISPLAY_EVERY
		text = "%d fps (min %d)\ncpu %.0fms phys %.0fms\ndraw %d prim %d\nnode %d" % [
			int(now), int(_worst), cpu, phys, draws, prims, nodes]

	# **Also log it.** iOS devices cannot be screen-captured (from iOS 17+
	# `screenshotr` moved behind a RemoteXPC tunnel so libimobiledevice cannot
	# reach it, and `devicectl` has no screenshot command). Put the meter only
	# on screen and **there is no way to know device performance until a human
	# looks.**
	#
	# `print()` becomes NSLog on iOS and can be read with `idevicesyslog`.
	# Android is `adb logcat`. One line opens both.
	_log_left -= delta
	if _log_left <= 0.0:
		_log_left = LOG_EVERY
		print("MOONLIT_PERF fps=%d worst=%d cpu=%.1f phys=%.1f draw=%d prim=%d node=%d"
			% [int(now), int(_worst), cpu, phys, draws, prims, nodes])
	# Green → yellow → red. Color is known before the numbers are read.
		if _worst >= 55.0:
			add_theme_color_override("font_color", Color(0.6, 1.0, 0.6, 0.85))
		elif _worst >= 40.0:
			add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 0.9))
		else:
			add_theme_color_override("font_color", Color(1.0, 0.5, 0.45, 1.0))
