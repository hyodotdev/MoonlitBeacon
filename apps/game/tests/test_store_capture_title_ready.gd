extends Node

## Boot marker: TestLauncher publishes title-ready only for a real clean title.
##
## Boots the real production entry and the standalone title as the current
## scene and proves the debug marker file appears for a clean boot only.
## The production title lives under the entry's Title child, so a root-only
## Ui/Screen lookup must fail here. An open gate card, panel, loader or
## confirm, a wrong version label, and a non-title scene must refuse the
## marker. Guarded to isolated user data; never touches a real save.

const PRODUCTION_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")
const TITLE_SCENE: PackedScene = preload(
	"res://scenes/menus/title_menu.tscn")
const ARENA_PATH: String = "res://scenes/gameplay/arena.tscn"
const READY_PROOF: String = "title-ready"

var _failed: int = 0
var _checked: int = 0


## Logged-out stub: the gate stays parked for the title behind it.
class StubReadyHost extends Node:
	signal production_changed(state: Dictionary)
	signal production_conflict(local: Dictionary, cloud: Dictionary)
	signal production_error(error: Dictionary)

	func startup() -> void:
		pass

	func providers_for_entry() -> Array:
		return []

	func identity_for_entry() -> Dictionary:
		return {"stable_id": ""}

	func account_state() -> Dictionary:
		return {"offline": false}

	func saved_gate_summary() -> Dictionary:
		return {"has_save": false}

	func provider_label(provider_id: String) -> String:
		return provider_id

	func note_first_paint() -> void:
		pass

	func release_entry_hold() -> void:
		pass

	func cancel_entry_plan() -> void:
		pass


func _ready() -> void:
	get_tree().root.size = Vector2i(808, 360)
	_run.call_deferred()


func _run() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	var previous_scene: Node = get_tree().current_scene
	_cleanup_marker()
	_check_resolve_roots()
	await _check_production_predicates()
	await _check_standalone_predicates()
	await _check_production_clean_marker(previous_scene)
	await _check_standalone_clean_marker(previous_scene)
	await _check_production_occluded_marker(previous_scene)
	await _check_production_wrong_version_marker(previous_scene)
	await _check_nontitle_marker(previous_scene)
	get_tree().current_scene = previous_scene
	_cleanup_marker()
	if _failed > 0:
		printerr("store-capture-title-ready test failed — ",
			_failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("store-capture-title-ready test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() \
		and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("store-capture-title-ready test aborted: user:// path is not isolated — ",
			user_root)
	return safe


## Resolution follows real scene identity: the Title child under the
## production entry, the root itself for the standalone title, null for
## anything else — even a decoy carrying the same Ui/Screen shape.
func _check_resolve_roots() -> void:
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubReadyHost.new()
	add_child(stub)
	production.set_host_override(stub)
	get_tree().root.add_child(production)
	var title: Control = TITLE_SCENE.instantiate() as Control
	get_tree().root.add_child(title)
	await _frames(4)
	_expect_equal(TestLauncher.resolve_title_root(production),
		production.get_node("Title"), "production resolves its Title child")
	_expect_equal(TestLauncher.resolve_title_root(title), title,
		"standalone resolves its own root")
	_expect_true(TestLauncher.resolve_title_root(null) == null,
		"missing scene resolves to null")
	var bare := Control.new()
	get_tree().root.add_child(bare)
	await _frames(2)
	_expect_true(TestLauncher.resolve_title_root(bare) == null,
		"non-title scene resolves to null")
	_expect_true(not TestLauncher.is_clean_title_boot(bare),
		"non-title scene is not a clean boot")
	_expect_true(not TestLauncher.is_clean_title_boot(null),
		"missing scene is not a clean boot")
	var decoy := Control.new()
	var decoy_ui := Control.new()
	decoy_ui.name = &"Ui"
	decoy.add_child(decoy_ui)
	var decoy_screen := Control.new()
	decoy_screen.name = &"Screen"
	decoy_ui.add_child(decoy_screen)
	var decoy_version := Label.new()
	decoy_version.name = &"Version"
	decoy_version.text = "v" + str(ProjectSettings.get_setting(
		"application/config/version", "0.0.0"))
	decoy_screen.add_child(decoy_version)
	get_tree().root.add_child(decoy)
	await _frames(2)
	_expect_true(TestLauncher.resolve_title_root(decoy) == null,
		"decoy Ui/Screen shape without title identity resolves to null")
	_expect_true(not TestLauncher.is_clean_title_boot(decoy),
		"decoy Ui/Screen shape is not a clean boot")
	decoy.queue_free()
	bare.queue_free()
	title.queue_free()
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## Predicate faces on one live production entry: clean passes, every
## occluding face and a wrong version refuse, restore returns to clean.
func _check_production_predicates() -> void:
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubReadyHost.new()
	add_child(stub)
	production.set_host_override(stub)
	get_tree().root.add_child(production)
	await _frames(4)
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	_expect_true(gate.is_title_rest(), "predicate: gate parked at boot")
	_expect_true(not TestLauncher.is_production_title_occluded(production),
		"predicate: clean boot not occluded")
	_expect_true(TestLauncher.is_clean_title_boot(production),
		"predicate: clean boot accepted")
	gate.show_logged_out()
	_expect_true(gate.is_selection_open(), "predicate: selection open")
	_expect_true(TestLauncher.is_production_title_occluded(production),
		"predicate: open card occludes")
	_expect_true(not TestLauncher.is_clean_title_boot(production),
		"predicate: open card refuses")
	gate.show_title_rest()
	_expect_true(TestLauncher.is_clean_title_boot(production),
		"predicate: rest after card returns to clean")
	gate.open_exit()
	_expect_true((gate.get_node("GateExitPanel") as Control).visible,
		"predicate: exit panel open")
	_expect_true(not TestLauncher.is_clean_title_boot(production),
		"predicate: open panel refuses")
	gate.close_panels()
	_expect_true(TestLauncher.is_clean_title_boot(production),
		"predicate: close after panel returns to clean")
	for panel_name in TestLauncher.GATE_OCCLUDING_PANELS:
		var panel: Control = gate.get_node_or_null(
			panel_name) as Control
		_expect_true(panel != null, "predicate: " + panel_name + " exists")
		if panel == null:
			continue
		panel.visible = true
		_expect_true(not TestLauncher.is_clean_title_boot(production),
			"predicate: " + panel_name + " refuses")
		panel.visible = false
	_expect_true(TestLauncher.is_clean_title_boot(production),
		"predicate: panels hidden returns to clean")
	var token: int = gate.load_scene(ARENA_PATH, "TEST entering the arena")
	_expect_true(token > 0, "predicate: loader takes a token")
	_expect_true(gate.get_loader().visible, "predicate: loader veil visible")
	_expect_true(not TestLauncher.is_clean_title_boot(production),
		"predicate: visible loader refuses")
	gate.get_loader().cancel()
	gate.get_loader()._on_back()
	await _frames(2)
	_expect_true(TestLauncher.is_clean_title_boot(production),
		"predicate: loader hidden returns to clean")
	var confirm: Control = production.get_node(
		"FreshConfirm") as Control
	confirm.visible = true
	_expect_true(not TestLauncher.is_clean_title_boot(production),
		"predicate: confirm refuses")
	confirm.visible = false
	_expect_true(TestLauncher.is_clean_title_boot(production),
		"predicate: confirm hidden returns to clean")
	var version_label: Label = production.get_node(
		"Title/Ui/Screen/Version") as Label
	var original: String = version_label.text
	version_label.text = "v0.0.0-wrong"
	_expect_true(not TestLauncher.is_clean_title_boot(production),
		"predicate: wrong version refuses")
	version_label.text = original
	_expect_true(TestLauncher.is_clean_title_boot(production),
		"predicate: version restored returns to clean")
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## Predicate faces on the standalone title: clean passes, a wrong
## version refuses, restore returns to clean.
func _check_standalone_predicates() -> void:
	var title: Control = TITLE_SCENE.instantiate() as Control
	get_tree().root.add_child(title)
	await _frames(4)
	_expect_true(TestLauncher.is_clean_title_boot(title),
		"standalone predicate: clean boot accepted")
	var version_label: Label = title.get_node(
		"Ui/Screen/Version") as Label
	var original: String = version_label.text
	version_label.text = "v0.0.0-wrong"
	_expect_true(not TestLauncher.is_clean_title_boot(title),
		"standalone predicate: wrong version refuses")
	version_label.text = original
	_expect_true(TestLauncher.is_clean_title_boot(title),
		"standalone predicate: version restored returns to clean")
	title.queue_free()
	await _frames(2)


## A clean production boot as the current scene publishes the marker.
func _check_production_clean_marker(previous_scene: Node) -> void:
	_cleanup_marker()
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubReadyHost.new()
	add_child(stub)
	production.set_host_override(stub)
	get_tree().root.add_child(production)
	get_tree().current_scene = production
	await _frames(8)
	_expect_equal(_read_marker(), READY_PROOF,
		"production boot publishes the marker")
	get_tree().current_scene = previous_scene
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## A clean standalone title boot as the current scene publishes the marker.
func _check_standalone_clean_marker(previous_scene: Node) -> void:
	_cleanup_marker()
	var title: Control = TITLE_SCENE.instantiate() as Control
	get_tree().root.add_child(title)
	get_tree().current_scene = title
	await _frames(8)
	_expect_equal(_read_marker(), READY_PROOF,
		"standalone boot publishes the marker")
	get_tree().current_scene = previous_scene
	title.queue_free()
	await _frames(2)


## An open gate card before the four-frame wait ends refuses the marker.
func _check_production_occluded_marker(previous_scene: Node) -> void:
	_cleanup_marker()
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubReadyHost.new()
	add_child(stub)
	production.set_host_override(stub)
	get_tree().root.add_child(production)
	get_tree().current_scene = production
	(production.get_node("Gate") as GateEntry).show_logged_out()
	await _frames(8)
	_expect_equal(_read_marker(), "", "open card refuses the marker")
	get_tree().current_scene = previous_scene
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## A wrong version label before the four-frame wait ends refuses the marker.
func _check_production_wrong_version_marker(previous_scene: Node) -> void:
	_cleanup_marker()
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubReadyHost.new()
	add_child(stub)
	production.set_host_override(stub)
	get_tree().root.add_child(production)
	get_tree().current_scene = production
	(production.get_node("Title/Ui/Screen/Version") as Label).text = \
		"v0.0.0-wrong"
	await _frames(8)
	_expect_equal(_read_marker(), "", "wrong version refuses the marker")
	get_tree().current_scene = previous_scene
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## A non-title current scene with a live writer refuses the marker.
func _check_nontitle_marker(previous_scene: Node) -> void:
	_cleanup_marker()
	var bare := Control.new()
	get_tree().root.add_child(bare)
	bare.add_child(TestLauncher.new())
	get_tree().current_scene = bare
	await _frames(8)
	_expect_equal(_read_marker(), "", "non-title scene refuses the marker")
	get_tree().current_scene = previous_scene
	bare.queue_free()
	await _frames(2)


func _read_marker() -> String:
	var path: String = TestLauncher.STORE_CAPTURE_TITLE_READY
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()


func _cleanup_marker() -> void:
	var path: String = TestLauncher.STORE_CAPTURE_TITLE_READY
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
