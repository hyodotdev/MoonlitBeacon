extends Node

## Title-to-arena transition: veil rest state and worker load kick.
##
## A tap starts the arena load on a worker thread while the beacon flare
## plays, so a slow device fades behind a veil instead of hanging on dead
## black. The swap itself is left to the device loop: firing it here would
## replace the test scene out from under the runner.

const TITLE_SCENE: PackedScene = preload("res://scenes/menus/title_menu.tscn")
const ARENA_PATH: String = "res://scenes/gameplay/arena.tscn"
## Upper bound for the worker load below. Headless frames run without vsync,
## so even a slow host clears a scene load long before this.
const LOAD_SPIN_FRAMES: int = 600

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return

	await _test_veil_rest_state()
	await _test_tap_kicks_worker_load()
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
	# The worker load the tap issued must still complete on its own.
	var status: ResourceLoader.ThreadLoadStatus = \
		ResourceLoader.load_threaded_get_status(ARENA_PATH)
	var spins: int = 0
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and spins < LOAD_SPIN_FRAMES:
		await get_tree().process_frame
		spins += 1
		status = ResourceLoader.load_threaded_get_status(ARENA_PATH)
	_expect_equal(status, ResourceLoader.THREAD_LOAD_LOADED, "worker arena load completes")


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
