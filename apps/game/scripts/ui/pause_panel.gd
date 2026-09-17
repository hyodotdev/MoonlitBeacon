extends Control

## Pause.
##
## Phone games **stop at any moment.** A call comes in, a notification pops, a
## hand has to leave. With no pause, each of those costs a run.

signal restart_requested
signal settings_requested
signal title_requested
signal pause_changed(paused: bool)

@onready var _overlay: ColorRect = $Overlay


func _ready() -> void:
	# `process_mode = ALWAYS`. This panel must stay alive while paused so
	# "resume" can be pressed. Otherwise it can never be unpaused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	$Button.pressed.connect(_pause)
	$Overlay/Resume.pressed.connect(_resume)
	$Overlay/Retry.pressed.connect(_on_retry)
	$Overlay/Settings.pressed.connect(settings_requested.emit)
	$Overlay/ToTitle.pressed.connect(_on_to_title)


## Hide the pause overlay while the settings window is open.
##
## A dim cover alone lets "paused" and three buttons show through behind the
## settings rows. The paused state (`get_tree().paused`) stays. It just is not
## visible.
func set_overlay_visible(value: bool) -> void:
	_overlay.visible = value


## Hide the pause button when the run is over. Stacking it on the result panel looks ugly.
func set_available(value: bool) -> void:
	$Button.visible = value


func _notification(what: int) -> void:
	# Home button or a phone call sends the app to the background. Pause so
	# coming back does not kill the run immediately.
	#
	# Why this does not handle `NOTIFICATION_WM_GO_BACK_REQUEST` (back):
	# Android back defaults to quit. That is Chapter 16.
	if what == NOTIFICATION_APPLICATION_PAUSED and $Button.visible:
		_pause()


## Pause from outside. Chapter 16's back press uses this.
func request_pause() -> void:
	if not $Button.visible:
		return                                   # do not pause a run that already ended
	_pause()


func _pause() -> void:
	if get_tree().paused:
		return
	get_tree().paused = true
	_overlay.visible = true
	pause_changed.emit(true)


func _resume() -> void:
	get_tree().paused = false
	_overlay.visible = false
	pause_changed.emit(false)


func _on_retry() -> void:
	get_tree().paused = false
	_overlay.visible = false
	restart_requested.emit()


## Return to the title (lobby). Same meaning as Android back once more while
## paused — fold the run with no record. The button is on screen for iOS,
## which has no back, and for people who look for a button. Pause itself is an
## intentional stop, so there is no extra confirm dialog.
func _on_to_title() -> void:
	get_tree().paused = false
	_overlay.visible = false
	title_requested.emit()
