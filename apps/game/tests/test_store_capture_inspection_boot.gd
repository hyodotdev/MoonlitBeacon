extends Node

## Unboosted hero inspection boot: the real title opens a quiet real Lv1 Arena.
##
## The `hero_direction` runtime probe already proves a clean Lv1 inspection,
## but every boot preset used to be boosted (Lv10 or Lv20/C3 with max missile
## and survived time). This boots the real production entry with an inspection
## request and proves the arena opens fresh — Lv1, cycle 1, zone 0, zero kills,
## full HP, the consumed `test_hero.request` hero — with no boost meta, no
## journey arm/clear/checkpoint write, and byte-identical journey and Vault
## files. A boot that would discard an already armed or waiting real journey
## refuses and leaves the title, the pending action, and the request alone.
## Guarded to isolated user data; never touches a real save.

const PRODUCTION_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")
const BOOT_SCRIPT: Script = preload("res://scripts/dev/store_capture_boot.gd")
const ARENA_PATH: String = "res://scenes/gameplay/arena.tscn"
const HERO_REQUEST_PATH: String = "user://test_hero.request"
const RUNTIME_REQUEST_PATH: String = "user://store_capture_runtime.request.json"
const RUNTIME_STATE_PATH: String = "user://store_capture_runtime.state.json"
const RUNTIME_TEMP_PATH: String = "user://store_capture_runtime.state.tmp"
const VAULT_PATH: String = "user://vault.cfg"
const DANCER: String = "res://resources/heroes/dancer.tres"
const BOOSTED_SURVIVED_FLOOR: float = 60.0

var _failed: int = 0
var _checked: int = 0


## Logged-out stub: the gate stays parked for the title behind it.
class StubInspectionHost extends Node:
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
	_cleanup()
	_reset_debug_state()
	await _check_refuses_armed_journey(previous_scene)
	_reset_debug_state()
	_cleanup()
	await _check_unboosted_inspection(previous_scene)
	get_tree().current_scene = previous_scene
	_cleanup()
	_reset_debug_state()
	if _failed > 0:
		printerr("store-capture-inspection-boot test failed — ",
			_failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("store-capture-inspection-boot test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() \
		and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("store-capture-inspection-boot test aborted: user:// path is not isolated — ",
			user_root)
	return safe


## An armed fresh journey plus a waiting title entry refuses the boot: the
## title stays, the pending action and from-title flag are untouched, no
## boost meta appears, and the request file is left for a later boot.
func _check_refuses_armed_journey(previous_scene: Node) -> void:
	Journey.begin_fresh()
	RunEntry.mark_from_title()
	_write_boot_inspection("a".repeat(64))
	var production: ProductionEntry = _boot_production()
	await _frames(10)
	_expect_true(
		get_tree().current_scene == production,
		"armed journey keeps the title, no inspection launch")
	_expect_true(Journey.armed, "armed journey stays armed after refusal")
	_expect_equal(
		Journey.pending, Journey.Pending.FRESH,
		"armed journey keeps its pending fresh action")
	_expect_true(
		RunEntry.from_title,
		"armed journey keeps its from-title flag")
	_expect_true(
		not get_tree().root.has_meta(TestLauncher.BOOST_META),
		"refused boot sets no boost meta")
	_expect_true(
		FileAccess.file_exists(str(BOOT_SCRIPT.REQUEST_PATH)),
		"refused boot leaves the request for a later boot")
	_expect_equal(
		_read_text(TestLauncher.STORE_CAPTURE_TITLE_READY), "title-ready",
		"refused boot keeps the clean-title boot marker")
	get_tree().current_scene = previous_scene
	production.queue_free()
	await _frames(2)

	# A waiting resume alone refuses too, without any from-title flag.
	_reset_debug_state()
	Journey.begin_resume()
	_write_boot_inspection("b".repeat(64))
	production = _boot_production()
	await _frames(10)
	_expect_true(
		get_tree().current_scene == production,
		"waiting resume keeps the title, no inspection launch")
	_expect_equal(
		Journey.pending, Journey.Pending.RESUME,
		"waiting resume keeps its pending action")
	get_tree().current_scene = previous_scene
	production.queue_free()
	await _frames(2)


## A clean boot opens the real Arena unboosted, consumes the selected hero,
## then proves the nonce-bound hero/direction readiness while journey and
## Vault bytes stay identical and the observation advances past the shot.
func _check_unboosted_inspection(previous_scene: Node) -> void:
	var guarded: Array[String] = [Journey.path, Journey.backup_path, VAULT_PATH]
	var before: Dictionary = _snapshot_files(guarded)
	_write_text(HERO_REQUEST_PATH, DANCER + "\n")
	_write_boot_inspection("c".repeat(64))
	_boot_production()
	var arena: Node = await _wait_for_arena(240)
	_expect_true(arena != null, "inspection opens the real Arena")
	if arena == null:
		return
	_expect_equal(int(arena.get("_level")), 1, "inspection is Lv1")
	_expect_equal(int(arena.get("_cycle")), 1, "inspection is cycle 1")
	_expect_equal(int(arena.get("_zone_index")), 0, "inspection is zone 0")
	_expect_equal(int(arena.get("_kills")), 0, "inspection has zero kills")
	_expect_equal(int(arena.get("_kill_score")), 0, "inspection has zero kill score")
	_expect_equal(
		int(arena.get("_health")), int(arena.get("_max_health")),
		"inspection has full HP")
	_expect_true(int(arena.get("_health")) > 0, "inspection HP is positive")
	_expect_equal(int(arena.get("_lit_count")), 0, "inspection lits no beacon")
	_expect_equal(
		str(arena.get("_run_hero_path")), DANCER,
		"inspection consumes the selected hero")
	_expect_true(
		not FileAccess.file_exists(HERO_REQUEST_PATH),
		"hero request is consumed one-shot")
	_expect_true(
		not get_tree().root.has_meta(TestLauncher.BOOST_META),
		"inspection sets no boost meta")
	_expect_true(not Journey.armed, "inspection arms no journey")
	_expect_equal(
		Journey.pending, Journey.Pending.NONE,
		"inspection leaves no pending journey action")
	_expect_true(not RunEntry.from_title, "inspection marks no title origin")
	# A boost always maxes the missile and pushes survived time, even at Lv1.
	_expect_equal(
		int(arena.get("_missile_power")), 0,
		"inspection grants no missile power")
	_expect_true(
		float(arena.get("_survived")) < BOOSTED_SURVIVED_FLOOR,
		"inspection grants no survived time")
	_expect_equal(
		_snapshot_files(guarded), before,
		"inspection leaves journey and Vault bytes identical")

	var runtime_nonce: String = "d".repeat(64)
	_write_json(RUNTIME_REQUEST_PATH, {
		"nonce": runtime_nonce,
		"kind": "hero_direction",
		"hero_resource_path": DANCER,
		"direction": "down",
	})
	var state: Dictionary = await _wait_for_ready(runtime_nonce, 240)
	_expect_true(not state.is_empty(), "inspection proves hero/direction ready")
	if state.is_empty():
		return
	_expect_equal(str(state.get("nonce", "")), runtime_nonce, "ready carries the runtime nonce")
	_expect_equal(str(state.get("kind", "")), "hero_direction", "ready carries the inspection kind")
	_expect_equal(int(state.get("level", -1)), 1, "ready is Lv1")
	_expect_equal(int(state.get("cycle", -1)), 1, "ready is cycle 1")
	_expect_equal(int(state.get("zone_index", -1)), 0, "ready is zone 0")
	_expect_equal(int(state.get("kills", -1)), 0, "ready has zero kills")
	_expect_true(bool(state.get("health_full", false)), "ready has full HP")
	_expect_equal(
		str(state.get("hero_resource_path", "")), DANCER,
		"ready carries the consumed hero")
	_expect_true(
		bool(state.get("hero_resource_matches_request", false)),
		"ready matches the requested hero")
	_expect_true(
		bool(state.get("hero_direction_matches_request", false)),
		"ready matches the requested direction")
	_expect_true(
		bool(state.get("hero_animation_matches_request", false)),
		"ready matches the requested still animation")
	var first_observation: int = int(state.get("observation", -1))
	var first_health: int = int(state.get("health", -1))
	await _frames(6)
	var later: Dictionary = _read_json(RUNTIME_STATE_PATH)
	_expect_true(
		int(later.get("observation", -1)) > first_observation,
		"observation advances past the shot")
	_expect_equal(
		int(later.get("health", -2)), first_health,
		"health is unchanged past the shot")
	_expect_true(bool(later.get("ready", false)), "readiness holds past the shot")
	_expect_equal(
		_snapshot_files(guarded), before,
		"proof leaves journey and Vault bytes identical")


## Boot the real production entry as the current scene behind a stub host.
func _boot_production() -> ProductionEntry:
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubInspectionHost.new()
	add_child(stub)
	production.set_host_override(stub)
	get_tree().root.add_child(production)
	get_tree().current_scene = production
	return production


## Wait until the boot opens the real Arena, or time out with null.
func _wait_for_arena(budget_frames: int) -> Node:
	for _index in budget_frames:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and is_instance_valid(scene) \
				and scene.scene_file_path == ARENA_PATH:
			await get_tree().process_frame
			await get_tree().process_frame
			return scene
	return null


## Wait until the probe publishes ready for this nonce, or time out empty.
func _wait_for_ready(nonce: String, budget_frames: int) -> Dictionary:
	for _index in budget_frames:
		await get_tree().process_frame
		var state: Dictionary = _read_json(RUNTIME_STATE_PATH)
		if str(state.get("nonce", "")) == nonce \
				and bool(state.get("ready", false)):
			return state
	return {}


func _write_boot_inspection(nonce: String) -> void:
	_write_json(str(BOOT_SCRIPT.REQUEST_PATH), {
		"schema": 1,
		"nonce": nonce,
		"kind": "hero_direction",
	})


func _snapshot_files(paths: Array[String]) -> Dictionary:
	var snapshot: Dictionary = {}
	for path in paths:
		if FileAccess.file_exists(path):
			snapshot[path] = FileAccess.get_file_as_string(path)
		else:
			snapshot[path] = null
	return snapshot


func _write_text(path: String, body: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect_true(file != null, path + " created")
	if file != null:
		file.store_string(body)


func _write_json(path: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect_true(file != null, path + " JSON created")
	if file != null:
		file.store_string(JSON.stringify(value))


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _cleanup() -> void:
	for path in [
		str(BOOT_SCRIPT.REQUEST_PATH),
		HERO_REQUEST_PATH,
		RUNTIME_REQUEST_PATH,
		RUNTIME_STATE_PATH,
		RUNTIME_TEMP_PATH,
		TestLauncher.STORE_CAPTURE_TITLE_READY,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _reset_debug_state() -> void:
	Journey.disarm()
	RunEntry.from_title = false
	if get_tree() != null and get_tree().root.has_meta(TestLauncher.BOOST_META):
		get_tree().root.remove_meta(TestLauncher.BOOST_META)


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
