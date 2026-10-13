## Real-startup close probe for course practice outputs. Registered as a
## scaffold-only autoload (TestClose), so the engine boots the configured
## main scene with real autoloads and a real current_scene. The observer
## only observes and presses production buttons and signals: it never
## releases the app's audio. The app must quit itself through its own
## close path, so a clean exit with music playing is the proof — the same
## flow leaked voices before the production handlers existed.
extends Node

const BOOT_FRAMES: int = 30
const WATCHDOG_FRAMES: int = 3600

var _lesson: int = 0
var _mode: String = ""
var _frames: int = 0
var _stage: int = 0
var _mark: int = 0
var _arena_id: int = 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lesson="):
			_lesson = int(arg.get_slice("=", 1))
		if arg.begins_with("--close-mode="):
			_mode = arg.get_slice("=", 1)
	if _mode == "":
		## Not a close run: the compile and practice runs carry this
		## autoload too. Idle and let their own scene drive the exit.
		return
	if _lesson < 1 or _lesson > 16:
		print("BOOT RESULT ok=false reason=bad-args")
		push_error("close_probe needs --lesson=N (1-16)")
		get_tree().quit(1)
		return
	get_tree().process_frame.connect(_on_frame)


func _fail(reason: String) -> void:
	print("CLOSE RESULT ok=false reason=", reason)
	push_error("close_probe: " + reason)
	get_tree().quit(1)


func _booted_title() -> Node:
	## The engine names the booted main scene; anything else means this
	## run is not the real startup it claims to be.
	var current: Node = get_tree().current_scene
	if current == null or current.name != "TitleMenu":
		_fail("current_scene-is-not-title")
		return null
	print("BOOT RESULT ok=true current=TitleMenu frames=", _frames)
	return current


func _on_frame() -> void:
	_frames += 1
	if _frames > WATCHDOG_FRAMES:
		_fail("watchdog")
		return
	match _mode:
		"plain":
			_tick_plain()
		"window":
			_tick_window()
		"yes":
			_tick_yes()
		_:
			_fail("unknown-mode")


func _tick_plain() -> void:
	## Lessons 1-2: the title has no script and no looping voice, so no
	## production close path exists to take. Quitting directly is honest
	## here; the output gate still proves nothing leaked.
	if _frames < BOOT_FRAMES or _stage != 0:
		return
	if _booted_title() == null:
		return
	_stage = 1
	print("CLOSE SENT mode=plain")
	print("CLOSE RESULT ok=true mode=plain")
	get_tree().quit()


func _tick_window() -> void:
	if _stage == 0:
		if _frames < BOOT_FRAMES:
			return
		var title: Node = _booted_title()
		if title == null:
			return
		title.request_start()
		_mark = _frames
		_stage = 1
	elif _stage == 1:
		var current: Node = get_tree().current_scene
		if current != null and current.name == "Arena":
			if _lesson >= 9:
				current._on_spirit_touched_player()
				current._on_spirit_touched_player()
				current._on_spirit_touched_player()
			_mark = _frames
			_stage = 2
		elif _frames - _mark > 900:
			_fail("title-never-entered-arena")
	elif _stage == 2:
		if _lesson < 9:
			_mark = _frames
			_stage = 4
			return
		var result: Control = get_tree().current_scene.get_node("Ui/ResultPanel")
		if result.is_accepting():
			_arena_id = get_tree().current_scene.get_instance_id()
			result.get_node("Panel/Restart").pressed.emit()
			_mark = _frames
			_stage = 3
		elif _frames - _mark > 1200:
			_fail("result-never-accepted")
	elif _stage == 3:
		var current: Node = get_tree().current_scene
		if current != null and current.name == "Arena" and current.get_instance_id() != _arena_id:
			if _frames - _mark > 30:
				_mark = _frames
				_stage = 4
		elif _frames - _mark > 600:
			_fail("restart-never-reloaded")
	elif _stage == 4:
		print("CLOSE SENT mode=window")
		get_tree().root.close_requested.emit()
		_mark = _frames
		_stage = 5
	elif _stage == 5 and _frames - _mark > 300:
		_fail("app-never-quit")


func _tick_yes() -> void:
	if _stage == 0:
		if _frames < BOOT_FRAMES:
			return
		var title: Node = _booted_title()
		if title == null:
			return
		title.get_node("QuitPrompt").open()
		_mark = _frames
		_stage = 1
	elif _stage == 1:
		print("CLOSE SENT mode=yes")
		get_tree().current_scene.get_node("QuitPrompt/Panel/Yes").pressed.emit()
		_mark = _frames
		_stage = 5
	elif _stage == 5 and _frames - _mark > 300:
		_fail("app-never-quit")
