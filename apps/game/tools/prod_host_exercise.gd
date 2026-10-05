extends Node

## Production host exercise: boot the real entry, measure first paint and
## scene handoff, prove paint-before-load, cancellation safety, honest Hall
## emptiness, and live opening guidance through the production plan path.
##
## Run headless under isolation (never touches real `user://` files):
## `pnpm godot:isolated --timeout 600 res://tools/prod_host_exercise.tscn`
## Refuses to run when `user://` is not the isolated test root. Identity
## and cloud services are real; only the native adapter and the HTTP sender
## are fakes (no network, no SDK), injected through the host's test seam.
## Prints a measurement report and exits 0 on success, 1 on failure.

const HOST_SCRIPT: Script = preload("res://scripts/net/production_host.gd")
const ACCOUNT_SCRIPT: Script = preload("res://scripts/net/player_account.gd")
const FAKE_ADAPTER_SCRIPT: Script = preload(
	"res://tests/support/fake_identity_adapter.gd")
const FAKE_SENDER_SCRIPT: Script = preload(
	"res://tests/support/fake_cloud_sender.gd")
const COORD_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_coordinator.gd")
const ENTRY_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")

const ID_PATH: String = "user://prod_exercise_identity.cfg"
const BIND_PATH: String = "user://prod_exercise_bindings.cfg"
const ARENA_PATH: String = "res://scenes/gameplay/arena.tscn"

var _failed: int = 0
var _checked: int = 0
var _report: Array[String] = []


func _ready() -> void:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path(
		"user://").simplify_path()
	if expected_root.is_empty() or not user_root.begins_with(
			expected_root + "/"):
		printerr("production exercise aborted: user:// path is not isolated — ",
			user_root)
		get_tree().quit(2)
		return
	GateEntryStrings.ensure_loaded()
	_run.call_deferred()


func _run() -> void:
	_wipe_identity()
	var host: Node = _make_host()
	var entry: ProductionEntry = ENTRY_SCENE.instantiate() as ProductionEntry
	entry.set_host_override(host)
	add_child(entry)
	await _frames(5)
	_check_entry(host, entry)
	await _check_hall_empty(host, entry)
	await _check_cancel_safety(entry)
	await _check_live_guidance(host, entry)
	_report_timings(host)
	entry.queue_free()
	host.shutdown()
	host.queue_free()
	_wipe_identity()
	Journey.use_account("")
	Journey.disarm()
	Journey.clear_stable_hooks()
	await _frames(3)
	for line in _report:
		print(line)
	if _failed > 0:
		printerr("production exercise failed — ", _failed, "/", _checked)
		get_tree().quit(1)
		return
	print("production exercise passed — ", _checked, " checks")
	get_tree().quit(0)


func _make_host() -> Node:
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	fake.guest_receipt = {"status": "error", "code": "network_error",
		"retryable": true}
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake, ID_PATH, BIND_PATH)
	var host: Node = HOST_SCRIPT.new() as Node
	add_child(host)
	host.inject_services({
		"account": account, "adapter": fake,
		"sender": FAKE_SENDER_SCRIPT.new(),
		"coordinator": COORD_SCRIPT.new(), "vault": Vault,
	})
	return host


func _check_entry(host: Node, entry: ProductionEntry) -> void:
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	_expect(gate != null, "entry boots the gate surface")
	_expect(not (gate.get_node("Content/StatusCard") as Control).visible,
		"first paint is the title, no auth card")
	var title: Variant = entry.get_node("Title")
	title.request_start()
	await _frames(2)
	var logged_out: Control = gate.get_node(
		"Content/StatusCard/LoggedOut") as Control
	_expect(logged_out.visible, "tap shows the choice")
	(gate.get_node("Content/StatusCard/LoggedOut/Guest") as Button
		).pressed.emit()
	await _frames(2)
	_expect(not logged_out.visible, "guest choice enters")
	var shown: String = str((gate.get_node(
		"Content/StatusCard/Ready/IdRow/StableId") as LineEdit).text)
	_expect(ACCOUNT_SCRIPT.is_valid_public_id(shown),
		"durable id visible before play")
	_expect(str((host.account_state() as Dictionary).get(
		"source", "")) == "local", "offline guest labeled local")
	_report.append("id-shown: %s" % shown)


func _check_hall_empty(host: Node, entry: ProductionEntry) -> void:
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	var view: Dictionary = await host.request_hall()
	_expect((view.get("rows", []) as Array).is_empty(),
		"hall seeds no fake ranks")
	entry.get_node("Gate").hall_requested.emit()
	await _frames(3)
	var panel: GateHallPanel = gate.get_node(
		"GateHallPanel") as GateHallPanel
	_expect(panel.visible and panel.row_count() == 0,
		"hall panel opens honestly empty")
	panel.get_node("Card/Stack/Close").pressed.emit()
	await _frames(2)


func _check_cancel_safety(entry: ProductionEntry) -> void:
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	var loader: GateLoadingOverlay = gate.get_loader()
	var finished: Array = []
	gate.loading_finished.connect(
		func(_path: String, _packed: PackedScene, token: int) -> void:
			finished.append(token))
	# Paint-first: the veil paints two frames before the worker is asked.
	# The loader awaited those frames first, so it resumes first: after
	# frame one the request is still out, after frame two it is issued.
	var token_a: int = gate.load_scene(
		"res://scenes/ui/gate_exit_panel.tscn", "stage")
	_expect(not loader.is_request_issued(),
		"loader paints before requesting")
	await _frames(1)
	_expect(not loader.is_request_issued(),
		"loader still painting on frame one")
	await _frames(1)
	_expect(loader.is_request_issued(), "loader requests after paint")
	gate.cancel_loading()
	var token_b: int = gate.load_scene(
		"res://scenes/ui/gate_loading_overlay.tscn", "stage")
	_expect(token_a != token_b, "cancel moves the generation")
	for _index in 40:
		await _frames(2)
		if not loader.is_loading():
			break
	_expect(not finished.has(token_a), "cancelled token never finishes")
	_expect(not loader.has_pending_drain(), "cancelled load drained")
	entry._on_loading_return()


func _check_live_guidance(host: Node, entry: ProductionEntry) -> void:
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	var loader: GateLoadingOverlay = gate.get_loader()
	var plan: Dictionary = host.plan_entry(true, true)
	_expect(str(plan.get("status", "")) == "ok", "fresh entry plans")
	var begin_ticks: int = Time.get_ticks_msec()
	var finished: Array = []
	gate.loading_finished.connect(
		func(path: String, packed_scene: PackedScene,
				finish_token: int) -> void:
			finished.append([path, packed_scene, finish_token]))
	var token: int = gate.load_scene(ARENA_PATH, "stage")
	_expect(not loader.is_request_issued(),
		"arena load paints the veil first")
	for _index in 600:
		await _frames(2)
		if not loader.is_loading():
			break
	# The finished signal carries the packed arena under the live token.
	var packed: PackedScene = null
	for hit in finished:
		if str((hit as Array)[0]) == ARENA_PATH \
				and int((hit as Array)[2]) == token:
			packed = (hit as Array)[1] as PackedScene
	_expect(packed != null, "arena loads through the production path")
	_report.append("arena-load-msec: %d"
		% (Time.get_ticks_msec() - begin_ticks))
	if packed == null:
		return
	var arena: Node2D = packed.instantiate() as Node2D
	add_child(arena)
	await _frames(5)
	_expect(not get_tree().paused, "opening never pauses")
	_expect(int(arena.get("_tutorial_step")) == 1,
		"guidance starts at step 1")
	var banner: Label = (arena.get_node("Ui/Hud") as Control).get(
		"_banner") as Label
	_expect(banner.visible, "first instruction shows while unpaused")
	var player: Node2D = arena.get_node("Player") as Node2D
	player.position = player.position + Vector2(100, 0)
	await _frames(3)
	_expect(int(arena.get("_tutorial_step")) == 2,
		"movement advances guidance live")
	_expect(not get_tree().paused, "guidance advances without pausing")
	arena.queue_free()
	await _frames(2)
	host.cancel_entry_plan()


func _report_timings(host: Node) -> void:
	var debug: Dictionary = host.debug_production_state()
	_report.append("boot-msec: %d" % int(debug.get("boot_msec", 0)))
	_report.append("startup-msec: %d" % int(debug.get("startup_msec", 0)))
	_report.append("first-paint-msec: %d"
		% int(debug.get("first_paint_msec", 0)))
	_expect(int(debug.get("first_paint_msec", 0)) > 0,
		"first paint measured")


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _wipe_identity() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		for path in [ID_PATH, BIND_PATH]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(
					path + suffix))
	Journey.use_account("")
	Journey.disarm()
	Journey.clear_stable_hooks()


func _expect(value: bool, label: String) -> void:
	_checked += 1
	if value:
		_report.append("ok: %s" % label)
	else:
		_failed += 1
		_report.append("FAIL: %s" % label)
