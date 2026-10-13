## Verification-only progression checks for course practice outputs.
## Runs as a scene (practice_check.tscn) in a throwaway scaffold so engine
## autoloads resolve exactly as they do in the real player; never shipped.
extends Node

const MIX_WAIT_MSEC: int = 200
const SAVE_SENTINEL: int = 7777

var _lesson: int = 0
var _pass: int = 0
var _fail: int = 0
var _frames: int = 0
var _arena: Node2D = null
var _title: Control = null
var _stage: int = 0
var _d0: float = 0.0
var _x0: float = 0.0
var _host: Control = null
var _stick_probe: Control = null
var _mark: int = 0
var _frozen_at: Vector2 = Vector2.ZERO
var _spirit_at: Vector2 = Vector2.ZERO
var _dash_from: Vector2 = Vector2.ZERO
var _dash_sprite_offset: Vector2 = Vector2.ZERO
var _flick_count: int = 0
var _flick_dir: Vector2 = Vector2.ZERO


func _on_test_flicked(direction: Vector2) -> void:
	_flick_count += 1
	_flick_dir = direction


func _ready() -> void:
	var verify_save: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lesson="):
			_lesson = int(arg.get_slice("=", 1))
		if arg == "--verify-save":
			verify_save = true
	if _lesson < 1 or _lesson > 16:
		print("PRACTICE RESULT lesson=0 pass=0 fail=1")
		push_error("practice_check needs --lesson=N (1-16)")
		get_tree().quit(1)
		return
	if verify_save:
		_run_save_check()
		return
	get_tree().process_frame.connect(_on_frame)
	get_tree().physics_frame.connect(_on_physics)


func _run_save_check() -> void:
	## Fresh-process reload: new holder objects read the files pass one
	## wrote, proving records and settings survive a restart.
	var records: Node = (load("res://scripts/records.gd") as Script).new()
	records.load_best()
	var ok: bool = records.best_score == SAVE_SENTINEL
	records.free()
	if _lesson >= 15:
		var settings: Node = (load("res://scripts/settings.gd") as Script).new()
		settings.load_all()
		ok = ok and settings.locale == "ko" and settings.music_step == 3 and settings.sfx_step == 7
		settings.free()
	print("SAVE RESULT ok=", ok)
	get_tree().quit(0 if ok else 1)



func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("PRACTICE FAIL lesson=", _lesson, " ", label)


func _print_result() -> void:
	print("PRACTICE RESULT lesson=", _lesson, " pass=", _pass, " fail=", _fail)


static func _transition_landing() -> void:
	## Tree-owned timer callback with no self to lose: runs after the
	## paused-back scene change freed the checker itself, reports the
	## arrival, then shuts the harness down. The production close path
	## itself is covered by close_probe, not here.
	var loop: SceneTree = Engine.get_main_loop()
	var current: Node = loop.current_scene
	if current != null and current.has_method("release_audio"):
		current.release_audio()
	OS.delay_msec(MIX_WAIT_MSEC)
	var where: String = current.name if current != null else "none"
	print("TRANSITION RESULT current=", where, " paused=", loop.paused)
	loop.quit()


func _finish() -> void:
	## Harness shutdown for test-instantiated scenes: these nodes never
	## became current_scene through a real transition, so the harness
	## releases their voices, waits out one mix, then quits. The real
	## startup/transition/close behavior is covered by close_probe.
	for scene in [_title, _arena, get_tree().current_scene]:
		if is_instance_valid(scene) and scene.has_method("release_audio"):
			scene.release_audio()
	OS.delay_msec(MIX_WAIT_MSEC)
	_print_result()
	get_tree().quit(1 if _fail > 0 else 0)


func _on_physics() -> void:
	## Re-assert movement input on the physics step: the arena zeroes it on
	## every idle frame, so an idle-time set never reaches the body.
	if _lesson == 6 and _stage == 2 and _arena != null:
		_arena.get_node("Player").set_move_input(Vector2(1, 0))


func _on_frame() -> void:
	_frames += 1
	if _frames > 3600:
		_check(false, "stages did not complete (watchdog)")
		_finish()
		return
	match _lesson:
		1:
			_check_lesson_1()
		2:
			_check_lesson_2()
		3:
			_check_lesson_3()
		4:
			_check_lesson_4()
		5:
			_check_lesson_5()
		6:
			_tick_lesson_6()
		7:
			_tick_lesson_7()
		8:
			_tick_lesson_8()
		9:
			_tick_lesson_9()
		10:
			_tick_lesson_10()
		11:
			_tick_lesson_11()
		12:
			_tick_lesson_12()
		13:
			_tick_lesson_13()
		14:
			_tick_lesson_14()
		15:
			_tick_lesson_15()
		16:
			_tick_lesson_16()


func _check_lesson_1() -> void:
	if _frames != 2:
		return
	_title = load("res://scenes/menus/title_menu.tscn").instantiate()
	get_tree().root.add_child(_title)
	_check(_title.get_child_count() == 9, "title has nine nodes")
	var blinker: AnimationPlayer = _title.get_node("Blinker")
	_check(blinker.is_playing() and blinker.assigned_animation == "blink", "prompt blinks")
	var tap: Button = _title.get_node("TapCatcher")
	var confirm: AudioStreamPlayer = _title.get_node("Confirm")
	_check(tap.is_connected("pressed", Callable(confirm, "play")), "tap plays confirm sound")
	_check(_title.get_node("Prompt").get_theme_font_size("font_size", "Label") == 22, "prompt size 22")
	_check(FileAccess.file_exists("res://docs/licenses/MIT-LICENSE.txt"), "mit notice ships")
	_check("moon_gate" in FileAccess.get_file_as_string("res://docs/licenses/THIRD_PARTY.txt"), "derived credits name the moon gate")
	_finish()


func _check_lesson_2() -> void:
	if _frames != 2:
		return
	_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
	get_tree().root.add_child(_arena)
	_check(_arena.get_node_or_null("NightForest") != null, "forest instance exists")
	var beacon: Node2D = _arena.get_node("Beacon")
	var names: Array = []
	for child in beacon.get_children():
		names.append(String(child.name))
	_check(names == ["Pit", "Light", "Glow", "Flame", "Flicker"], "beacon has five fire nodes")
	_check(_arena.get_node("NightForest").modulate == Color(0.315, 0.35, 0.57, 1), "forest night tint")
	_check(_arena.get_node("NightForest/Trees").get_child_count() == 6, "six edge trees")
	_finish()


func _check_lesson_3() -> void:
	if _frames != 2:
		return
	_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
	get_tree().root.add_child(_arena)
	var west: Node2D = _arena.get_node("BeaconWest")
	var north: Node2D = _arena.get_node("BeaconNorth")
	_check(west.position == Vector2(258, 286) and absf(west.scale.x - 0.78) < 0.001, "west place and scale")
	_check(north.position == Vector2(414, 196) and absf(north.scale.x - 0.62) < 0.001, "north place and scale")
	_check(absf(float(west.get_node("Flicker").speed_scale) - 0.87) < 0.001, "west flicker beat")
	_check(absf(float(north.get_node("Flicker").speed_scale) - 1.24) < 0.001, "north flicker beat")
	_check(west.get_node("Clearing").z_index == -1, "clearing pinned below")
	_check(_arena.get_node("NightForest").get_node_or_null("Clearing") == null, "clearing left the forest")
	_check(_arena.get_node("Music").autoplay, "arena music autoplays")
	var screen: GDScript = load("res://scripts/util/screen.gd")
	_check(screen.center_offset(Vector2(900, 360)) == Vector2(46, 0), "centering math")
	_title = load("res://scenes/menus/title_menu.tscn").instantiate()
	get_tree().root.add_child(_title)
	_check(_title.has_signal("start_requested"), "title emits start_requested")
	var bgm_stream: AudioStreamOggVorbis = (_title.get_node("Bgm") as AudioStreamPlayer).stream as AudioStreamOggVorbis
	_check(bgm_stream != null and bgm_stream.loop, "title music loops")
	var arena_stream: AudioStreamOggVorbis = (_arena.get_node("Music") as AudioStreamPlayer).stream as AudioStreamOggVorbis
	_check(arena_stream != null and arena_stream.loop, "arena music loops")
	_finish()


func _check_lesson_4() -> void:
	if _frames != 2:
		return
	_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
	get_tree().root.add_child(_arena)
	var west: Node2D = _arena.get_node("BeaconWest")
	_check(not west.lit, "beacons start unlit")
	_check(absf(float(west.get_node("Flicker").speed_scale) - 0.87) < 0.001, "flicker export survived")
	west.ignite()
	_check(west.lit, "ignite lights the beacon")
	_check(_arena.get("_lit_count") == 1, "arena counted one lit beacon")
	_finish()


func _check_lesson_5() -> void:
	if _frames != 2:
		return
	var player: CharacterBody2D = load("res://scenes/player.tscn").instantiate()
	get_tree().root.add_child(player)
	_check(player.collision_layer == 2 and player.collision_mask == 0, "player on layer value 2")
	var sprite: AnimatedSprite2D = player.get_node("Sprite")
	_check(sprite.sprite_frames.get_animation_names().size() == 8, "eight facing animations")
	_check(sprite.animation == "idle_down", "exported facing shows on run")
	player.face_toward(Vector2.ZERO)
	_check(player.facing == 0, "zero input keeps facing")
	player.face_toward(Vector2(-3, 1))
	_check(player.facing == 2, "left input faces left")
	_finish()


func _tick_lesson_6() -> void:
	if _frames == 2 and _stage == 0:
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		var stick: Control = _arena.get_node("Ui/MoveStick")
		_check(stick.anchor_right == 0.5 and stick.anchor_bottom == 1.0, "stick anchors left half")
		_check(stick.offset_right == 0.0, "no fixed-pixel width")
		_host = Control.new()
		_host.size = Vector2(1200, 360)
		get_tree().root.add_child(_host)
		_stick_probe = load("res://scenes/ui/virtual_stick.tscn").instantiate()
		_host.add_child(_stick_probe)
		_stage = 1
	elif _frames == 4 and _stage == 1:
		_check(_stick_probe.size.x == 600.0, "stick is half of a wide viewport")
		var player: CharacterBody2D = _arena.get_node("Player")
		_x0 = player.position.x
		_stage = 2
	elif _stage == 2:
		var player: CharacterBody2D = _arena.get_node("Player")
		if _frames == 124:
			_check(player.position.x > _x0 + 20.0, "stick input moves the player")
			_check(player.facing == 3, "moving right faces right")
			player.set_move_input(Vector2.ZERO)
			_stage = 3
	elif _frames == 244 and _stage == 3:
		var player: CharacterBody2D = _arena.get_node("Player")
		_check(player.velocity.length() < 1.0, "release stops the player")
		_check(player.facing == 3, "release keeps facing")
		_check(player.get_node("Sprite").animation == "idle_right", "stop returns to idle")
		player.position = Vector2(4000, 4000)
		_stage = 4
	elif _frames == 249 and _stage == 4:
		var player: CharacterBody2D = _arena.get_node("Player")
		_check(player.position == Vector2(784, 322), "bounds clamp the player")
		_finish()
	elif _frames > 400:
		_check(false, "lesson 6 stages did not complete")
		_finish()


func _tick_lesson_7() -> void:
	if _frames == 2 and _stage == 0:
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		var west: Node2D = _arena.get_node("BeaconWest")
		_check(west.get_node("Reach").collision_mask == 2, "reach watches layer value 2")
		var radius: float = west.get_node("Reach/ReachShape").shape.radius
		_check(absf(radius - 34.0 / 0.78) < 0.01, "reach normalized against scale")
		_check(not _arena.has_method("_run_ignition_sequence"), "auto sequence deleted")
		var player: CharacterBody2D = _arena.get_node("Player")
		var fill: Sprite2D = player.get_node("RingFill")
		for ratio in [0.25, 0.5, 0.75]:
			player.set_charge(ratio)
			var bottom: float = fill.offset.y + fill.region_rect.size.y * 0.5
			_check(absf(bottom - 20.0) < 0.01, "ring bottom fixed at %d%%" % int(ratio * 100.0))
			_check(absf(fill.region_rect.size.y - 40.0 * ratio) < 0.01, "ring height tracks charge")
		player.set_charge(1.0)
		_check(not fill.visible, "full charge hides the ring")
		player.set_charge(0.0)
		_check(not fill.visible, "empty charge hides the ring")
		player.position = west.position + Vector2(20, 0)
		_stage = 1
	elif _stage == 1:
		var west: Node2D = _arena.get_node("BeaconWest")
		if west.get_charge() > 0.2:
			var player: CharacterBody2D = _arena.get_node("Player")
			_check(player.get_node("RingFill").visible, "ring mirrors proximity charge")
			_check(not west.lit, "partial charge does not ignite")
			_stage = 2
			_finish()
		elif _frames > 900:
			_check(false, "charge never rose near the beacon")
			_finish()


func _tick_lesson_8() -> void:
	if _frames == 2 and _stage == 0:
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		var spirit: CharacterBody2D = _arena.get_node("Spirit")
		_check(spirit.collision_layer == 4, "spirit on layer value 4")
		_check(_arena.get_node("Player").collision_layer == 2, "player stays on layer value 2")
		_check(spirit.get_node("Hitbox").collision_mask == 2, "hitbox watches the player")
		_d0 = spirit.global_position.distance_to(_arena.get_node("Player").global_position)
		_stage = 1
	elif _stage == 1:
		var spirit: CharacterBody2D = _arena.get_node("Spirit")
		if _d0 - spirit.global_position.distance_to(_arena.get_node("Player").global_position) > 20.0:
			_check(true, "spirit chases the player")
			spirit.global_position = _arena.get_node("Player").global_position + Vector2(5, 0)
			_stage = 2
		elif _frames > 900:
			_check(false, "spirit never approached")
			_finish()
	elif _stage == 2:
		var player: CharacterBody2D = _arena.get_node("Player")
		if player.velocity.length() > 100.0:
			var flash: ColorRect = _arena.get_node("Ui/HitFlash")
			var spirit: CharacterBody2D = _arena.get_node("Spirit")
			_check(flash.modulate.a > 0.0, "screen flashes on contact")
			_check(spirit.get_node("Sprite").modulate == Color(1, 0.35, 0.35, 1), "spirit flashes red")
			_stage = 3
			_finish()
		elif _frames > 1200:
			_check(false, "contact never knocked the player back")
			_finish()


func _tick_lesson_9() -> void:
	if _frames == 2 and _stage == 0:
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		var gate: Node2D = _arena.get_node("Gate")
		_check(gate.position == Vector2(404, 336), "gate waits past the bounds")
		_check(not gate.get_node("Enter").monitoring, "gate sensor off until open")
		var player: CharacterBody2D = _arena.get_node("Player")
		_check(player.bounds == Rect2(24, 120, 760, 202), "run starts inside default bounds")
		_check(not _arena.get_node("Ui/ResultPanel").visible, "result hidden during play")
		_check(_arena.get_health() == 3 and not _arena.is_over(), "three hearts, run live")
		_arena.get_node("BeaconWest").ignite()
		_arena.get_node("BeaconNorth").ignite()
		_arena.get_node("BeaconEast").ignite()
		_mark = _frames
		_stage = 1
	elif _stage == 1:
		var gate: Node2D = _arena.get_node("Gate")
		if gate.get_node("Enter").monitoring:
			var player: CharacterBody2D = _arena.get_node("Player")
			_check(player.bounds == Rect2(24, 120, 760, 234), "merge opens the bounding span")
			_check(player.bounds.end.y > gate.position.y, "merged bounds reach the gate")
			player.position = gate.position
			_mark = _frames
			_stage = 2
		elif _frames - _mark > 1500:
			_check(false, "gate never opened")
			_finish()
	elif _stage == 2:
		if _arena.is_over():
			_check(_arena.did_win(), "reaching the open gate wins")
			var result: Control = _arena.get_node("Ui/ResultPanel")
			_check(result.visible, "result shows on win")
			_check(result.get_node("Panel/Title").text == "All beacons are burning", "win text")
			_check(not result.is_accepting(), "restart waits out its input gate")
			_check(not _arena.get_node("Gate/Enter").monitoring, "gate disarms after the win")
			_mark = _frames
			_stage = 3
		elif _frames - _mark > 600:
			_check(false, "gate entry never finished the run")
			_finish()
	elif _stage == 3:
		var result: Control = _arena.get_node("Ui/ResultPanel")
		if result.is_accepting():
			_check(true, "restart accepts after its gate")
			_arena.release_audio()
			_arena.queue_free()
			_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
			get_tree().root.add_child(_arena)
			_mark = _frames
			_stage = 4
		elif _frames - _mark > 1500:
			_check(false, "restart never accepted")
			_finish()
	elif _stage == 4:
		var player: CharacterBody2D = _arena.get_node("Player")
		var west: Node2D = _arena.get_node("BeaconWest")
		if west.get_charge() > 0.2:
			## Lose mid-stride on a partial charge: knockback velocity is
			## still live when the third hit lands. The spirit stays on the
			## hunt until the finish, so its stillness below is earned.
			_arena.set("_health", 3)
			player.knock_back(Vector2.RIGHT, 200.0, 1.0)
			_arena._on_spirit_touched_player()
			_arena._on_spirit_touched_player()
			_arena._on_spirit_touched_player()
			_check(_arena.get_health() == 0, "three hits spend every heart")
			_check(_arena.is_over() and not _arena.did_win(), "no hearts left loses")
			_check(_arena.get_node("Ui/ResultPanel/Panel/Title").text == "The night takes you", "lose text")
			_check(west.is_frozen(), "the finish freezes the beacon")
			_d0 = west.get_charge()
			_check(_d0 > 0.2 and _d0 < 1.0, "the frozen charge is partial")
			_frozen_at = player.position
			_spirit_at = _arena.get_node("Spirit").position
			_mark = _frames
			_stage = 5
		elif _frames - _mark > 1500:
			_check(false, "charge never rose near the beacon")
			_finish()
		else:
			player.position = west.position + Vector2(20, 0)
	elif _stage == 5 and _frames - _mark > 30:
		var player: CharacterBody2D = _arena.get_node("Player")
		var west: Node2D = _arena.get_node("BeaconWest")
		_check(player.velocity.length() < 1.0, "the finish stops a moving player")
		_check(player.position == _frozen_at, "the player holds still after the finish")
		_check(west.get_charge() == _d0, "a frozen beacon holds its partial charge")
		_check(_arena.get("_lit_count") == 0, "no late ignition counts")
		_check(_arena.get_node("Spirit").position == _spirit_at, "spirits freeze after the finish")
		_finish()


func _tick_lesson_10() -> void:
	if _frames == 2 and _stage == 0:
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		var hud: Control = _arena.get_node("Ui/Hud")
		_check(hud.get_node("Hearts").text == "HP 3", "hud draws hearts at start")
		_check(hud.get_node("Beacons").text == "Beacons 0/3", "hud draws beacons at start")
		_check(hud.get_node("Time").text == "1:30", "hud draws the full clock at start")
		_check(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "hud never eats touches")
		_check(hud.get_node("Time").mouse_filter == Control.MOUSE_FILTER_IGNORE, "clock never eats touches")
		_arena.get_node("BeaconWest").ignite()
		_check(hud.get_node("Beacons").text == "Beacons 1/3", "hud follows lit beacons")
		_arena._on_spirit_touched_player()
		_check(hud.get_node("Hearts").text == "HP 2", "hud follows health")
		_d0 = _arena.get_time_left()
		_mark = _frames
		_stage = 1
	elif _stage == 1 and _frames - _mark > 30:
		_check(_arena.get_time_left() < _d0, "the clock counts down")
		var hud: Control = _arena.get_node("Ui/Hud")
		hud.set_time_left(9.5)
		_check(hud.get_node("Time").text == "0:10", "urgent seconds still round up")
		_check(hud.get_node("Time").get_theme_color("font_color", "Label") == Color(1, 0.35, 0.35, 1), "short clock turns red")
		hud.set_time_left(89.99)
		_check(hud.get_node("Time").text == "1:30", "ceil keeps 89.99 at 1:30")
		hud.set_time_left(-3.0)
		_check(hud.get_node("Time").text == "0:00", "maxf pins the past at 0:00")
		_arena.set("_time_left", 0.05)
		_mark = _frames
		_stage = 2
	elif _stage == 2:
		if _arena.is_over():
			_check(not _arena.did_win(), "timeout loses the run")
			_check(_arena.get_node("Ui/ResultPanel").visible, "result shows on timeout")
			_d0 = _arena.get_time_left()
			_mark = _frames
			_stage = 3
		elif _frames - _mark > 600:
			_check(false, "timeout never finished the run")
			_finish()
	elif _stage == 3 and _frames - _mark > 20:
		_check(_arena.get_time_left() == _d0, "the clock freezes after the finish")
		_finish()


func _tick_lesson_11() -> void:
	if _frames == 2 and _stage == 0:
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		_check(ProjectSettings.get_setting("application/config/version") == "0.1.0", "phone build carries 0.1.0")
		var panel: Control = _arena.get_node("Ui/PausePanel")
		_check(not panel.visible, "pause card hidden during play")
		_check(panel.process_mode == Node.PROCESS_MODE_ALWAYS, "pause card always processes")
		var card: ColorRect = panel.get_node("Panel")
		_check(card.anchor_left == 0.5 and card.anchor_right == 0.5, "pause card pins to center x")
		_check(card.anchor_top == 0.5 and card.anchor_bottom == 0.5, "pause card pins to center y")
		var stick: Control = _arena.get_node("Ui/MoveStick")
		stick.set("_touch_index", -2)
		stick.set("_value", Vector2(1, 0))
		_arena.request_pause()
		_check(get_tree().paused, "pause halts the tree")
		_check(panel.is_open(), "pause card opens")
		_check(stick.get("_touch_index") == -1 and stick.get_value() == Vector2.ZERO, "pause drops a mid-drag finger")
		_d0 = _arena.get_time_left()
		_mark = _frames
		_stage = 1
	elif _stage == 1 and _frames - _mark > 20:
		_check(_arena.get_time_left() == _d0, "the clock freezes while get_tree().paused")
		_arena.resume_play()
		_check(not get_tree().paused, "resume restarts the tree")
		_check(not _arena.get_node("Ui/PausePanel").is_open(), "resume closes the card")
		_arena._notification(NOTIFICATION_APPLICATION_PAUSED)
		_check(get_tree().paused, "backgrounding auto-pauses")
		_arena.resume_play()
		_arena._on_spirit_touched_player()
		_arena._on_spirit_touched_player()
		_arena._on_spirit_touched_player()
		_arena.request_pause()
		_check(not get_tree().paused, "a finished run refuses to pause")
		_finish()


func _tick_lesson_12() -> void:
	if _frames == 2 and _stage == 0:
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		var dash_stick: Control = _arena.get_node("Ui/DashStick")
		_check(dash_stick.anchor_left == 0.5 and dash_stick.anchor_right == 1.0, "dash stick anchors the right half")
		_check(dash_stick.offset_left == 0.0 and dash_stick.offset_right == 0.0, "dash stick has no fixed pixels")
		_host = Control.new()
		_host.size = Vector2(1200, 360)
		get_tree().root.add_child(_host)
		_stick_probe = load("res://scenes/ui/virtual_stick.tscn").instantiate()
		_stick_probe.anchor_left = 0.5
		_stick_probe.anchor_right = 1.0
		_stick_probe.offset_left = 0.0
		_stick_probe.offset_right = 0.0
		_host.add_child(_stick_probe)
		_flick_count = 0
		dash_stick.flicked.connect(_on_test_flicked)
		dash_stick._show_at(Vector2(100, 180))
		dash_stick._move_to(Vector2(120, 180))
		dash_stick._release()
		_check(_flick_count == 0, "a weak release stays silent")
		var player: CharacterBody2D = _arena.get_node("Player")
		_check(player.dash(Vector2.ZERO) == false, "zero flick cannot dash")
		_x0 = player.position.x
		_dash_from = player.global_position
		## The breathe animation re-poses the sprite offset every frame, so
		## pin it now: the first ghost is created synchronously inside the
		## dash call below, before any animation tick can move it.
		_dash_sprite_offset = (player.get_node("Sprite") as AnimatedSprite2D).offset
		_check(player.dash(Vector2.RIGHT) == true, "a flick dashes")
		_check(player.dash(Vector2.RIGHT) == false, "dash refuses while dashing")
		_check(not player.is_dash_ready(), "cooldown starts on dash")
		_mark = _frames
		_stage = 1
	elif _stage == 1:
		var first_ghost: Sprite2D = null
		for child in _arena.get_children():
			if child is Sprite2D and first_ghost == null:
				first_ghost = child
		if first_ghost != null:
			_check(true, "the dash leaves afterimages")
			_check(first_ghost.offset == _dash_sprite_offset, "ghost copies the sprite offset")
			_check(first_ghost.global_position.distance_to(_dash_from) < 0.01, "ghost stays where the dash began")
			_mark = _frames
			_stage = 2
		elif _frames - _mark > 600:
			_check(false, "no afterimages appeared")
			_finish()
	elif _stage == 2:
		var player: CharacterBody2D = _arena.get_node("Player")
		if not player.is_dashing() and _frames - _mark > 5:
			_check(player.position.x - _x0 > 40.0, "the dash crosses ground")
			_check(player.facing == 3, "the dash faces its flick")
			_check(_arena.get_node("Ui/Hud/Dash").text == "Dash ...", "hud shows the cooldown")
			_mark = _frames
			_stage = 3
		elif _frames - _mark > 600:
			_check(false, "the dash never ended")
			_finish()
	elif _stage == 3:
		var player: CharacterBody2D = _arena.get_node("Player")
		if player.is_dash_ready():
			_mark = _frames
			_stage = 4
		elif _frames - _mark > 2400:
			_check(false, "the cooldown never cleared")
			_finish()
	elif _stage == 4 and _frames - _mark > 3:
		_check(_arena.get_node("Ui/Hud/Dash").text == "Dash ready", "hud shows readiness")
		_check(_stick_probe.size.x == 600.0, "right half holds at wide viewports")
		var dash_stick: Control = _arena.get_node("Ui/DashStick")
		dash_stick._show_at(Vector2(100, 180))
		dash_stick._move_to(Vector2(164, 180))
		dash_stick._release()
		_check(_flick_count == 1 and _flick_dir.x > 0.99, "a full release flicks")
		_check(_arena.get_node("Player").is_dashing(), "the wired flick dashes the player")
		_finish()


func _kind_probe(kind_path: String) -> CharacterBody2D:
	var spirit: CharacterBody2D = (load("res://scenes/spirit.tscn") as PackedScene).instantiate()
	spirit.kind = load(kind_path)
	get_tree().root.add_child(spirit)
	return spirit


func _tick_lesson_13() -> void:
	if _frames == 2 and _stage == 0:
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		_arena.set("_health", 99)
		var base: CharacterBody2D = _arena.get_node("Spirit")
		_check(base.kind.display_name == "Drifting spirit", "the first spirit drifts")
		_check(base.speed == 62.0, "kind sets the gait")
		var names: Array = base.get_node("Sprite").sprite_frames.get_animation_names()
		names.sort()
		_check(names == ["float_down", "float_left", "float_right", "float_up"], "ordinary kinds face four ways")
		_check(base.get_node("Sprite").sprite_frames.get_frame_count("float_down") == 4, "four frames a facing")
		var bat: CharacterBody2D = _kind_probe("res://resources/kinds/night_bat.tres")
		_check(bat.speed == 70.0, "the bat outruns the drifter")
		bat.queue_free()
		var ember: CharacterBody2D = _kind_probe("res://resources/kinds/ember.tres")
		_check(ember.speed == 84.0, "the ember outruns the bat")
		ember.queue_free()
		var guardian: CharacterBody2D = _kind_probe("res://resources/kinds/guardian.tres")
		var gnames: Array = guardian.get_node("Sprite").sprite_frames.get_animation_names()
		_check(gnames == ["float_down"], "the guardian has one facing")
		_check(guardian.get_node("Sprite").sprite_frames.get_frame_count("float_down") == 5, "the guardian floats through five frames")
		var frames_ok: bool = true
		for i in 5:
			var region: Rect2 = (guardian.get_node("Sprite").sprite_frames.get_frame_texture("float_down", i) as AtlasTexture).region
			frames_ok = frames_ok and region == Rect2(i * 50, 0, 50, 50)
		_check(frames_ok, "guardian frames run left to right along row zero")
		guardian.queue_free()
		_arena.get_node("Player").position = Vector2(120, 170)
		var spawned: CharacterBody2D = _arena._spawn_spirit(load("res://resources/kinds/drifter.tres"))
		_check(spawned.position == Vector2(690, 310), "new spirits rise farthest from the player")
		_mark = _frames
		_stage = 1
	elif _stage == 1 and _frames - _mark > 2:
		var spawned: CharacterBody2D = null
		for child in _arena.get_children():
			if child is CharacterBody2D and child != _arena.get_node("Player") and child != _arena.get_node_or_null("Spirit"):
				spawned = child
		if spawned == null:
			_check(false, "the spawned spirit vanished")
			_finish()
			return
		_check(not spawned.get_node("Hitbox").monitoring, "materializing spirits cannot hit")
		_mark = _frames
		_stage = 4
	elif _stage == 4:
		var armed: CharacterBody2D = null
		for child in _arena.get_children():
			if child is CharacterBody2D and child != _arena.get_node("Player") and child != _arena.get_node_or_null("Spirit"):
				armed = child
		if armed != null and armed.get_node("Hitbox").monitoring:
			_check(true, "materialized spirits join the hunt")
			_check(_arena._kind_for_progress().display_name == "Drifting spirit", "no beacons, drifters")
			_arena.get_node("BeaconWest").ignite()
			_check(_arena._kind_for_progress().display_name == "Night bat", "one beacon, bats")
			_arena.get_node("BeaconNorth").ignite()
			_check(_arena._kind_for_progress().display_name == "Ember spirit", "two beacons, embers")
			_arena.get_node("BeaconEast").ignite()
			_mark = _frames
			_stage = 2
		elif _frames - _mark > 1500:
			_check(false, "materialize never armed the hitbox")
			_finish()
	elif _stage == 2:
		var guardian_out: bool = false
		for child in _arena.get_children():
			if child is CharacterBody2D and child.has_method("retreat") and child.kind.display_name == "Forest guardian":
				guardian_out = true
		var music: AudioStreamOggVorbis = (_arena.get_node("Music") as AudioStreamPlayer).stream as AudioStreamOggVorbis
		if guardian_out and _arena.get_node_or_null("Spirit") == null:
			_check(true, "the guardian replaces the pack")
			_check(music != null and music.resource_path.ends_with("guardian_theme.ogg"), "the guardian brings its theme")
			_check(music != null and music.loop, "the guardian theme loops")
			_arena.get_node("Player").position = _arena.get_node("Gate").position
			_mark = _frames
			_stage = 3
		elif _frames - _mark > 1500:
			_check(false, "the guardian never arrived")
			_finish()
	elif _stage == 3:
		if _arena.is_over():
			var left: int = 0
			for child in _arena.get_children():
				if child is CharacterBody2D and child.has_method("retreat"):
					left += 1
			if left == 0:
				_check(_arena.did_win(), "the gate still wins with the guardian out")
				_check(true, "the pack retreats on the win")
				_finish()
		if _frames - _mark > 2400:
			_check(false, "spirits never retreated")
			_finish()


func _tick_lesson_14() -> void:
	if _frames == 2 and _stage == 0:
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		_arena.set("_health", 99)
		var score_script: Script = load("res://scripts/score.gd")
		var full: RefCounted = score_script.build(3, 3, 89.9, true)
		_check(full.total() == 3390, "beacons plus time plus escape")
		_check(full.rank() == "S", "a full fast win is S")
		_check(full.lines() == [["Beacons", 1500], ["Time", 890], ["Escape", 1000]], "reveal rows carry the parts")
		_check(score_script.build(1, 3, 60.0, true).rank() == "B", "a slow win is B")
		_check(score_script.build(0, 3, 5.0, true).rank() == "C", "an empty win is C")
		_check(score_script.build(1, 3, 10.0, false).rank() == "D", "no escape is D")
		_arena.get_node("BeaconWest").ignite()
		_arena.get_node("BeaconNorth").ignite()
		_arena.get_node("BeaconEast").ignite()
		_mark = _frames
		_stage = 1
	elif _stage == 1:
		if _arena.get_node("Gate/Enter").monitoring:
			_arena.get_node("Player").position = _arena.get_node("Gate").position
			_mark = _frames
			_stage = 2
		elif _frames - _mark > 1500:
			_check(false, "gate never opened")
			_finish()
	elif _stage == 2:
		var result: Control = _arena.get_node("Ui/ResultPanel")
		if _arena.is_over() and result.is_revealed():
			_check(result.get_node("Panel/Row0").text == "Beacons  1500", "beacon row ticks to full")
			_check(result.get_node("Panel/Row2").text == "Escape  1000", "escape row ticks to full")
			var time_part: int = int(result.get_node("Panel/Row1").text.get_slice(" ", 2))
			_check(result.get_node("Panel/Sum").text == str(1500 + time_part + 1000), "the sum adds the rows")
			_check(result.get_node("Panel/Stamp").text != "D", "a win never stamps D")
			_check(result.is_accepting(), "restart accepts after the reveal")
			_arena.release_audio()
			_arena.queue_free()
			_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
			get_tree().root.add_child(_arena)
			var west: Node2D = _arena.get_node("BeaconWest")
			_arena.get_node("Player").position = west.position + Vector2(20, 0)
			_mark = _frames
			_stage = 3
		elif _frames - _mark > 3600:
			_check(false, "the win reveal never completed")
			_finish()
	elif _stage == 3:
		var west: Node2D = _arena.get_node("BeaconWest")
		if west.get_charge() > 0.2:
			_arena._on_spirit_touched_player()
			_arena._on_spirit_touched_player()
			_arena._on_spirit_touched_player()
			_check(_arena.is_over() and not _arena.did_win(), "three hits lose the run")
			_check(west.is_frozen(), "the finish freezes every beacon")
			_d0 = west.get_charge()
			_frozen_at = _arena.get_node("Player").position
			_mark = _frames
			_stage = 4
		elif _frames - _mark > 1500:
			_check(false, "charge never rose near the beacon")
			_finish()
	elif _stage == 4 and _frames - _mark > 20:
		var west: Node2D = _arena.get_node("BeaconWest")
		_check(west.get_charge() == _d0, "a frozen beacon holds its charge")
		_check(_arena.get_node("Player").position == _frozen_at, "the player holds still after the finish")
		var result: Control = _arena.get_node("Ui/ResultPanel")
		result.get_node("Panel/Skip").emit_signal("pressed")
		_check(result.is_revealed(), "skip finishes the reveal at once")
		_check(result.get_node("Panel/Stamp").text == "D", "a loss stamps D")
		_check(result.is_accepting(), "skip unlocks the restart")
		_check(not _arena.did_win(), "skipping never restarts the run")
		var records: Node = get_tree().root.get_node("Records")
		_check(records.save_best(SAVE_SENTINEL), "the sentinel best saves")
		_check(FileAccess.file_exists("user://records.cfg"), "records land in user://")
		_finish()


func _tick_lesson_15() -> void:
	if _frames == 2 and _stage == 0:
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		var settings: Node = get_tree().root.get_node("Settings")
		_check(settings != null, "settings autoload boots")
		_check(get_tree().root.get_node("Records") != null, "records autoload boots")
		_check(ProjectSettings.get_setting("autoload/Settings") == "*res://scripts/settings.gd", "settings autoload registered")
		_check(AudioServer.get_bus_index("Music") >= 0, "music bus exists")
		_check(AudioServer.get_bus_index("Sfx") >= 0, "sfx bus exists")
		_check(settings.step_to_db(10) == 0.0, "full step is full volume")
		_check(settings.step_to_db(0) == -80.0, "zero step mutes")
		settings.set_music_step(5)
		var music_db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
		_check(absf(music_db - settings.step_to_db(5)) < 0.001, "music steps reach the bus")
		settings.set_music_step(0)
		_check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) == -80.0, "music zero mutes the bus")
		settings.set_music_step(8)
		settings.set_locale("xx")
		_check(settings.locale == "en", "unknown locales are ignored")
		_check((_arena.get_node("Music") as AudioStreamPlayer).bus == "Music", "arena music rides its bus")
		_check((_arena.get_node("BeaconWest/IgniteSound") as AudioStreamPlayer2D).bus == "Sfx", "ignite rides the sfx bus")
		_title = load("res://scenes/menus/title_menu.tscn").instantiate()
		get_tree().root.add_child(_title)
		_check((_title.get_node("Bgm") as AudioStreamPlayer).bus == "Music", "title music rides its bus")
		_check((_title.get_node("Confirm") as AudioStreamPlayer).bus == "Sfx", "confirm rides the sfx bus")
		_check(_title.get_node("Prompt").text == "Tap to start", "english prompt by default")
		_title.get_node("SettingsButton").emit_signal("pressed")
		_check(_title.get_node("SettingsPanel").is_open(), "title opens settings")
		_title.get_node("SettingsPanel").close()
		_arena.get_node("Ui/PausePanel/Panel/Settings").emit_signal("pressed")
		_check(_arena.get_node("Ui/SettingsPanel").is_open(), "pause opens settings")
		settings.set_locale("ko")
		_check(_arena.get_node("Ui/Hud/Hearts").text == "체력 3", "hearts speak korean")
		_check(_arena.get_node("Ui/PausePanel/Panel/Title").text == "일시정지", "pause speaks korean")
		_check(_title.get_node("Prompt").text == "탭하여 시작", "prompt speaks korean")
		settings.set_locale("en")
		_check(_arena.get_node("Ui/Hud/Hearts").text == "HP 3", "english comes back")
		var panel: Control = _arena.get_node("Ui/SettingsPanel")
		panel.get_node("Panel/MusicUp").emit_signal("pressed")
		_check(settings.music_step == 9 and panel.get_node("Panel/MusicValue").text == "9", "music stepper steps up")
		panel.get_node("Panel/MusicDown").emit_signal("pressed")
		panel.get_node("Panel/MusicDown").emit_signal("pressed")
		_check(settings.music_step == 7, "music stepper steps down")
		panel.get_node("Panel/SfxDown").emit_signal("pressed")
		_check(settings.sfx_step == 7, "sfx stepper steps down")
		_check(panel.get_node("Panel/LangEn").disabled, "the active locale rests")
		_check("Godot" in panel.get_node("Panel/CreditsBody").text, "credits name the engine")
		settings.set_locale("ko")
		_check("Godot" in panel.get_node("Panel/CreditsBody").text, "korean credits name the engine")
		_arena._on_spirit_touched_player()
		_arena._on_spirit_touched_player()
		_arena._on_spirit_touched_player()
		_mark = _frames
		_stage = 1
	elif _stage == 1:
		var result: Control = _arena.get_node("Ui/ResultPanel")
		if _arena.is_over():
			result.get_node("Panel/Skip").emit_signal("pressed")
			_check(result.is_revealed(), "skip reveals at once")
			_check(result.get_node("Panel/Row0").text.begins_with("봉화"), "reveal rows speak korean")
			_check(result.get_node("Panel/Title").text == "밤이 당신을 삼킨다", "the loss speaks korean")
			var settings: Node = get_tree().root.get_node("Settings")
			settings.set_music_step(3)
			settings.set_sfx_step(7)
			_check(FileAccess.file_exists("user://settings.cfg"), "settings land in user://")
			get_tree().root.get_node("Records").save_best(SAVE_SENTINEL)
			_finish()
		elif _frames - _mark > 600:
			_check(false, "three hits never lost the run")
			_finish()


func _send_back(node: Node) -> void:
	node._notification(NOTIFICATION_WM_GO_BACK_REQUEST)


func _tick_lesson_16() -> void:
	if _frames == 2 and _stage == 0:
		_check(ProjectSettings.get_setting("application/config/version") == "1.0.0", "release carries 1.0.0")
		_check(ProjectSettings.get_setting("application/config/quit_on_go_back") == false, "back never auto-quits")
		_check(FileAccess.file_exists("res://export_presets.cfg"), "export preset ships")
		var preset: String = FileAccess.get_file_as_string("res://export_presets.cfg")
		_check("com.example.moonlitcourse.ref" in preset, "preset uses the reference package")
		_check("com.crossplatformkorea.moonlitbeacon" not in preset, "preset never names shipping")
		_check("com.example.moonlitcourse\"" not in preset, "preset never names the learner package")
		_check("package/signed=true" in preset, "preset signs the installable build")
		_check("docs/licenses/*.txt" in preset, "preset retains the license notices")
		var lowered: String = preset.to_lower()
		_check(not ("keystore" in lowered or "key_pass" in lowered or "_pass=" in lowered or "password" in lowered), "preset embeds no key material")
		_check("version/name=\"1.0.0\"" in preset, "preset matches the release")
		_title = load("res://scenes/menus/title_menu.tscn").instantiate()
		get_tree().root.add_child(_title)
		_check(_title.get_node("Version").text == "v1.0.0", "title shows the release")
		_title.get_node("SettingsPanel").open()
		_send_back(_title)
		_check(not _title.get_node("SettingsPanel").is_open(), "back walks out of settings")
		_send_back(_title)
		_check(_title.get_node("QuitPrompt").is_open(), "back asks on the title")
		_title.get_node("QuitPrompt/Panel/No").emit_signal("pressed")
		_check(not _title.get_node("QuitPrompt").is_open(), "no stays on the title")
		## Done with the title: release and free it so the finale's real
		## transition lands on the name without a clash or a stray voice.
		_title.release_audio()
		_title.free()
		_title = null
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		_send_back(_arena)
		_check(get_tree().paused, "back pauses the run")
		_arena.resume_play()
		_arena.get_node("Ui/SettingsPanel").open()
		_send_back(_arena)
		_check(not _arena.get_node("Ui/SettingsPanel").is_open(), "back walks out of arena settings")
		_check(not get_tree().paused, "settings back does not pause")
		_arena._on_spirit_touched_player()
		_arena._on_spirit_touched_player()
		_arena._on_spirit_touched_player()
		_send_back(_arena)
		_check(_arena.is_over(), "the result ignores back")
		_check(_arena.get_node("Ui/ResultPanel").visible, "the result stays up")
		_check(load(_arena.TITLE_SCENE) != null, "paused back targets a loadable title")
		get_tree().root.get_node("Records").save_best(SAVE_SENTINEL)
		var settings: Node = get_tree().root.get_node("Settings")
		settings.set_locale("ko")
		settings.set_music_step(3)
		settings.set_sfx_step(7)
		_arena.release_audio()
		_arena.free()
		_arena = load("res://scenes/gameplay/arena.tscn").instantiate()
		get_tree().root.add_child(_arena)
		_arena.request_pause()
		_print_result()
		## Take the real transition last: it frees this checker, so a
		## tree-owned timer and the static landing report the arrival.
		get_tree().create_timer(3.0).timeout.connect(_transition_landing)
		_send_back(_arena)
