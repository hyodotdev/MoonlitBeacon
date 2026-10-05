extends Node

## Title-to-arena transition: veil rest state and worker load kick.
##
## A tap starts the arena load on a worker thread while the beacon flare
## plays, so a slow device fades behind a veil instead of hanging on dead
## black. The swap itself is left to the device loop: firing it here would
## replace the test scene out from under the runner.

const TITLE_SCENE: PackedScene = preload("res://scenes/menus/title_menu.tscn")
const ARENA_PATH: String = "res://scenes/gameplay/arena.tscn"
## Wall-time budget for the worker arena load below. Headless frames run
## without vsync, so a frame count is not a deadline: on a busy host the
## worker can still be mid-load after hundreds of frames. Thirty seconds is
## far past a normal load (under a second) yet still fails a real hang fast
## enough for the suite.
const LOAD_DEADLINE_MSEC: int = 30000
## Breathing room between status polls so the worker thread gets CPU while
## the main thread waits, instead of hot-spinning frame after frame.
const LOAD_POLL_SECONDS: float = 0.05
## A path nobody requests, so the wait's failure branch is observable
## without issuing a load that would print an engine error.
const MISSING_LOAD_PATH: String = "res://tests/does_not_exist_for_wait_check.tscn"

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return

	await _test_veil_rest_state()
	await _test_tap_kicks_worker_load()
	await _test_warm_cache_load()
	await _test_wait_boundaries()
	await _test_standalone_ladder_stays_local()
	if _failed > 0:
		printerr("title-transition test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("title-transition test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("title-transition test aborted: user:// path is not isolated — ", user_root)
	return safe


func _test_veil_rest_state() -> void:
	var title: Control = TITLE_SCENE.instantiate() as Control
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	var veil: ColorRect = title.get_node_or_null("Ui/TransitionVeil") as ColorRect
	_expect_true(veil != null, "transition veil exists")
	if veil == null:
		title.queue_free()
		return
	_expect_true(not veil.visible, "veil hidden at rest")
	_expect_true(is_equal_approx(veil.modulate.a, 0.0), "veil transparent at rest")
	_expect_equal(veil.mouse_filter, Control.MOUSE_FILTER_IGNORE, "veil never eats taps")
	_expect_equal(veil.color, Color.BLACK, "veil is black")
	_expect_true(
		veil.anchor_left == 0.0 and veil.anchor_top == 0.0
			and veil.anchor_right == 1.0 and veil.anchor_bottom == 1.0,
		"veil covers the screen")
	var ui: Node = title.get_node("Ui")
	var siblings: Array[Node] = ui.get_children()
	_expect_true(
		siblings.find(veil) > siblings.find(title.get_node("Ui/Screen")),
		"veil draws above the title screen")
	_expect_true(not bool(title.get("_awaiting_arena")), "not awaiting a swap at rest")
	title.queue_free()
	await get_tree().process_frame


func _test_tap_kicks_worker_load() -> void:
	var title: Control = TITLE_SCENE.instantiate() as Control
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	title.request_start()
	# request_start is synchronous until its first await: sfx, music fade,
	# flare, and the worker load request all issue before it yields.
	_expect_true(bool(title.get("_threaded_arena")), "tap kicks worker arena load")
	# Free before the 0.85s flare wait ends: the guarded continuation must
	# return without swapping scenes out from under the test.
	title.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(not is_instance_valid(title), "title freed before swap")
	# The worker load the tap issued must still complete on its own, even on
	# a busy host: bound the wait by wall time, not by frames.
	var wait: Dictionary = await _await_threaded_load(ARENA_PATH, LOAD_DEADLINE_MSEC)
	# The first poll may catch the load mid-flight or already complete: on
	# a warm cache the worker finishes before the first observation. Either
	# is a genuine observation; completion itself is asserted below.
	var first_status: int = int(wait["first_status"])
	_expect_true(
		first_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS
			or first_status == ResourceLoader.THREAD_LOAD_LOADED,
		"worker load in flight or already complete at first poll")
	_expect_equal(
		int(wait["status"]), ResourceLoader.THREAD_LOAD_LOADED,
		"worker arena load completes")
	_expect_true(
		int(wait["elapsed_msec"]) < LOAD_DEADLINE_MSEC,
		"worker load finished before the deadline")
	_expect_true(
		is_equal_approx(float(wait["progress"]), 1.0),
		"worker load progress reached full")
	# Consume the completed request: the loaded value must be the arena.
	var packed: PackedScene = null
	if int(wait["status"]) == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(ARENA_PATH) as PackedScene
	_expect_true(packed != null, "consumed worker load is a packed scene")
	_expect_equal(
		packed.resource_path if packed != null else "",
		ARENA_PATH,
		"consumed worker load is the arena")
	packed = null
	await get_tree().process_frame


## Same tap-to-load path with the arena already runtime-loaded and held:
## the first poll may see a completed load, so this case never requires
## catching IN_PROGRESS, only that the real request still drains to the arena.
func _test_warm_cache_load() -> void:
	var held: PackedScene = load(ARENA_PATH) as PackedScene
	_expect_true(held != null, "warm cache holds the runtime arena")
	var title: Control = TITLE_SCENE.instantiate() as Control
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	title.request_start()
	_expect_true(bool(title.get("_threaded_arena")), "warm tap kicks worker arena load")
	title.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(not is_instance_valid(title), "warm title freed before swap")
	var wait: Dictionary = await _await_threaded_load(ARENA_PATH, LOAD_DEADLINE_MSEC)
	_expect_equal(
		int(wait["status"]), ResourceLoader.THREAD_LOAD_LOADED,
		"warm worker arena load completes")
	_expect_true(
		int(wait["elapsed_msec"]) < LOAD_DEADLINE_MSEC,
		"warm worker load finished before the deadline")
	_expect_true(
		is_equal_approx(float(wait["progress"]), 1.0),
		"warm worker load progress reached full")
	var packed: PackedScene = null
	if int(wait["status"]) == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(ARENA_PATH) as PackedScene
	_expect_true(packed != null, "warm consumed worker load is a packed scene")
	_expect_equal(
		packed.resource_path if packed != null else "",
		ARENA_PATH,
		"warm consumed worker load is the arena")
	packed = null
	held = null
	await get_tree().process_frame


## The same wait rule under controlled inputs: a load nobody issued must
## stop at once instead of burning the deadline, and an expired budget must
## return the current status without waiting, even for a live request.
func _test_wait_boundaries() -> void:
	var missing: Dictionary = await _await_threaded_load(
		MISSING_LOAD_PATH, LOAD_DEADLINE_MSEC)
	_expect_equal(
		int(missing["status"]), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"missing load reports invalid at once")
	_expect_equal(int(missing["polls"]), 0, "missing load burns no polls")
	var probe_request: Error = ResourceLoader.load_threaded_request(ARENA_PATH)
	_expect_equal(probe_request, Error.OK, "boundary probe re-requests the arena")
	var expired: Dictionary = await _await_threaded_load(ARENA_PATH, 0)
	_expect_equal(int(expired["polls"]), 0, "expired budget waits for nothing")
	var drained: Dictionary = await _await_threaded_load(ARENA_PATH, LOAD_DEADLINE_MSEC)
	_expect_equal(
		int(drained["status"]), ResourceLoader.THREAD_LOAD_LOADED,
		"boundary probe load still completes")
	var probe_packed: PackedScene = null
	if int(drained["status"]) == ResourceLoader.THREAD_LOAD_LOADED:
		probe_packed = ResourceLoader.load_threaded_get(ARENA_PATH) as PackedScene
	_expect_true(probe_packed != null, "boundary probe load is consumable")
	probe_packed = null
	await get_tree().process_frame


## Poll a threaded load until it leaves IN_PROGRESS or the wall-time budget
## runs out. Only IN_PROGRESS keeps waiting; LOADED, FAILED and
## INVALID_RESOURCE all return at once. Returns the first and final status
## with the poll count, wall time spent and final progress, so the tests can
## assert on the wait itself.
func _await_threaded_load(path: String, deadline_msec: int) -> Dictionary:
	var progress: Array = []
	var first_status: ResourceLoader.ThreadLoadStatus = \
		ResourceLoader.load_threaded_get_status(path, progress)
	var status: ResourceLoader.ThreadLoadStatus = first_status
	var polls: int = 0
	var start_msec: int = Time.get_ticks_msec()
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS \
			and Time.get_ticks_msec() - start_msec < deadline_msec:
		await get_tree().create_timer(LOAD_POLL_SECONDS).timeout
		polls += 1
		status = ResourceLoader.load_threaded_get_status(path, progress)
	var final_progress: float = 0.0
	if progress.size() > 0:
		final_progress = float(progress[0])
	return {
		"first_status": first_status,
		"status": status,
		"polls": polls,
		"elapsed_msec": Time.get_ticks_msec() - start_msec,
		"progress": final_progress,
	}


func _test_standalone_ladder_stays_local() -> void:
	var title: Control = TITLE_SCENE.instantiate() as Control
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	var managed: Array = []
	title.connect("external_hall_requested",
		func() -> void: managed.append(true))
	(title.get_node("Ui/Screen/LadderButton") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(managed.is_empty(),
		"standalone rank never routes to the managed hall")
	_expect_true((title.get_node("Ui/Ladder") as Control).visible,
		"standalone rank opens the local ladder")
	_expect_true(not (title.get_node("Ui/Screen") as Control).visible,
		"standalone rank parks the screen")
	(title.get_node("Ui/Ladder") as Control).call("close")
	await get_tree().process_frame
	_expect_true((title.get_node("Ui/Screen") as Control).visible,
		"standalone ladder close restores the screen")
	title.queue_free()
	await get_tree().process_frame


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
