extends Node

## Result button → ladder submit if needed → chosen destination → shrine auto-open regression.

const TESTABLE_ARENA: Script = preload("res://tests/support/testable_arena.gd")
const LADDER_SPY: Script = preload("res://tests/support/ladder_spy.gd")
const RESULT_SPY: Script = preload("res://tests/support/result_spy.gd")
const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_panel.tscn")
const TITLE_SCENE: PackedScene = preload("res://scenes/menus/title_menu.tscn")
const ARENA_SCRIPT: Script = preload("res://scripts/gameplay/arena.gd")
const TITLE_SCRIPT: Script = preload("res://scripts/ui/title_menu.gd")
const KEEPER: String = "res://resources/heroes/keeper.tres"

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return

	await _test_result_buttons()
	_test_persistence_retry_before_restart()
	_test_record_waits_for_persistence()
	_test_board_then_shrine()
	_test_board_then_restart()
	_test_record_button()
	_test_without_board()
	await _test_store_handoff_ends_current_run()
	await _test_title_handoff()

	Ladder.entries.clear()
	if _failed > 0:
		printerr("result-route test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("result-route test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("result-route test aborted: user:// path is not isolated — ", user_root)
	return safe


func _test_result_buttons() -> void:
	var panel: Control = RESULT_SCENE.instantiate() as Control
	add_child(panel)
	await get_tree().process_frame

	var restart_count: Array[int] = [0]
	var shrine_count: Array[int] = [0]
	panel.restart_requested.connect(func() -> void: restart_count[0] += 1)
	panel.shrine_requested.connect(func() -> void: shrine_count[0] += 1)
	panel.visible = true
	panel.set("_accepting", true)
	panel.call("_set_actions_enabled", true)
	var retry: Button = panel.get_node("Actions/Retry") as Button
	_expect_true(
		get_viewport().gui_get_focus_owner() == retry,
		"keyboard/gamepad default focus is the safe retry")

	# If any key after reveal retried, a pad could not pick another result route.
	# Only the button's ui_accept must confirm the current focus.
	var stray_key: InputEventKey = InputEventKey.new()
	stray_key.keycode = KEY_A
	stray_key.pressed = true
	panel.call("_try_accept", stray_key)
	_expect_equal(restart_count[0], 0, "a normal key does not confirm retry")

	var accept: InputEventKey = InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	await get_tree().process_frame
	accept.pressed = false
	Input.parse_input_event(accept)
	await get_tree().process_frame
	_expect_equal(restart_count[0], 1, "ui_accept selects the focused result button")

	panel.set("_accepting", true)
	panel.get_node("Actions/Shrine").emit_signal("pressed")
	_expect_equal(shrine_count[0], 1, "Shrine button requests the shrine once")
	_expect_equal(restart_count[0], 1, "Shrine button does not restart")

	panel.set("_accepting", true)
	panel.get_node("Actions/Retry").emit_signal("pressed")
	_expect_equal(restart_count[0], 2, "Retry button requests restart once")
	_expect_equal(shrine_count[0], 1, "Retry button does not request the shrine")

	# After the reveal, a mis-tap on empty screen is not interpreted as any choice.
	# A finger that just misses Shrine and immediately opens a new run would break the buy route again.
	var stray_tap: InputEventMouseButton = InputEventMouseButton.new()
	stray_tap.button_index = MOUSE_BUTTON_LEFT
	stray_tap.pressed = true
	panel.set("_accepting", true)
	panel.call("_try_accept", stray_tap)
	_expect_equal(restart_count[0], 2, "tapping empty screen does not retry")
	_expect_equal(shrine_count[0], 1, "tapping empty screen does not open the shrine")

	panel.queue_free()
	await get_tree().process_frame


func _test_persistence_retry_before_restart() -> void:
	var parts: Dictionary = _route_parts(6180)
	var arena: Node = parts["arena"]
	var result: Control = parts["result"]
	arena.configure_persistence(
		[
			{"status": Vault.RunSettlementStatus.SAVE_FAILED, "awarded": 0},
			{"status": Vault.RunSettlementStatus.SAVE_FAILED, "awarded": 0},
			{"status": Vault.RunSettlementStatus.APPLIED, "awarded": 12},
		],
		[
			Records.SubmitResult.SAVE_FAILED,
			Records.SubmitResult.SAVE_FAILED,
			Records.SubmitResult.SAVED,
		])

	_expect_false(
		arena.persist_finished_result(6180, "C"),
		"the first save failure is not consumed as a new-best success")
	_expect_true(arena.persistence_pending(), "holds shard and new-best failures during the result")
	_expect_equal(arena.run_shards_awarded(), 0, "save-failed shards are not treated as granted")

	arena.request_restart()
	_expect_equal(arena.restart_calls, 0, "blocks retry if save keeps failing")
	_expect_equal(result.reopen_calls, 1, "result choices re-enabled after a save failure")
	_expect_equal(arena.run_shards_awarded(), 0, "no duplicate shards even after repeated failures")
	_expect_equal(arena.pending_action(), arena.no_pending_action(), "cancels auto-running a failed destination")

	arena.request_restart()
	_expect_equal(arena.restart_calls, 1, "chosen retry runs after both saves recover")
	_expect_false(arena.persistence_pending(), "recovered result save hold released")
	_expect_equal(arena.run_shards_awarded(), 12, "shards granted exactly once after recover")
	_expect_equal(arena.settlement_calls, 3, "shard save succeeds once after two failures")
	_expect_equal(arena.record_submit_calls, 3, "new-best save succeeds once after two failures")
	_expect_equal(result.persistence_refresh_calls, 1, "recovered result copy refreshed once")
	_expect_true(result.last_persistence_best, "applies the recovered saved new-best to the result")
	_expect_equal(result.last_persistence_shards, 12, "applies recovered granted shards to the result")

	# After the hold is gone, another result signal must not call persistence again.
	arena.request_restart()
	_expect_equal(arena.settlement_calls, 3, "no second shard settlement after success")
	_expect_equal(arena.record_submit_calls, 3, "no second new-best save after success")
	_expect_equal(arena.run_shards_awarded(), 12, "no duplicate shard grant after success")
	_free_route_parts(parts)


func _test_record_waits_for_persistence() -> void:
	var parts: Dictionary = _route_parts(32100)
	var arena: Node = parts["arena"]
	var result: Control = parts["result"]
	var ladder: Control = parts["ladder"]
	arena.configure_persistence(
		[{
			"status": Vault.RunSettlementStatus.APPLIED,
			"awarded": 28,
		}],
		[
			Records.SubmitResult.SAVE_FAILED,
			Records.SubmitResult.SAVE_FAILED,
			Records.SubmitResult.SAVED,
		])
	_expect_false(
		arena.persist_finished_result(32100, "A"),
		"holds a new-best save failure on the result")
	_expect_equal(arena.run_shards_awarded(), 28, "an independently successful shard settlement is kept")

	arena.request_record()
	_expect_equal(ladder.ask_count, 0, "record panel blocked while a new-best save fails")
	_expect_true(result.visible, "stays on the result screen if save fails before recording")
	_expect_equal(result.reopen_calls, 1, "a pre-record save failure also re-enables choices")

	arena.request_record()
	_expect_equal(ladder.ask_count, 1, "opens the record panel after a new-best save recovers")
	_expect_false(result.visible, "hides the result panel and records after save recovery")
	_expect_equal(arena.settlement_calls, 1, "a successful shard save is not duplicated on a record retry")
	_expect_equal(arena.record_submit_calls, 3, "retries only a new-best that failed before recording")
	_expect_equal(result.persistence_refresh_calls, 1, "late-saved new-best copy is refreshed")
	_expect_true(result.last_persistence_best, "late-saved new-best badge is applied")
	_expect_equal(result.last_persistence_shards, 28, "already-successful shard count is also kept")
	arena.complete_ladder()
	_expect_true(result.visible, "closing record after save recovery returns to result")
	_free_route_parts(parts)


func _test_board_then_shrine() -> void:
	Ladder.entries.clear()
	var parts: Dictionary = _route_parts(32100)
	var arena: Node = parts["arena"]
	var ladder: Control = parts["ladder"]

	# Even a ladder-eligible score's destination buttons skip recording. Recording is its own button.
	arena.request_shrine()
	_expect_equal(ladder.ask_count, 0, "shrine choice does not force ladder submit")
	_expect_equal(arena.title_calls, 1, "shrine choice goes to title immediately")
	_expect_true(arena.title_requested_shrine, "passes shrine auto-open to the title")
	_expect_equal(arena.restart_calls, 0, "shrine choice does not restart")
	_expect_equal(arena.pending_action(), arena.no_pending_action(), "finished-result destination reset")
	_free_route_parts(parts)


func _test_board_then_restart() -> void:
	Ladder.entries.clear()
	var parts: Dictionary = _route_parts(32100)
	var arena: Node = parts["arena"]
	var ladder: Control = parts["ladder"]

	arena.request_restart()
	_expect_equal(ladder.ask_count, 0, "retry choice does not force ladder submit")
	_expect_equal(arena.restart_calls, 1, "retry choice retries immediately")
	_expect_equal(arena.title_calls, 0, "retry choice does not go to title")
	_free_route_parts(parts)


func _test_record_button() -> void:
	Ladder.entries.clear()
	var parts: Dictionary = _route_parts(32100)
	var arena: Node = parts["arena"]
	var result: Control = parts["result"]
	var ladder: Control = parts["ladder"]

	# Even if a mid-run refund reverts Vault to the default hero, records still use the run-start hero.
	arena.set("_run_hero_path", KEEPER)
	Vault.chosen = ""
	result.visible = true
	arena.request_record()
	_expect_false(result.visible, "Record button hides the result panel and opens the ladder panel")
	_expect_equal(ladder.ask_count, 1, "only the Record button requests ladder submit")
	_expect_equal(ladder.last_hero, KEEPER, "ladder submit still uses the run-start hero after refund")
	_expect_equal(arena.restart_calls, 0, "Record button does not retry")
	_expect_equal(arena.title_calls, 0, "Record button does not go to title")
	var first_run_id: String = ladder.last_run_id
	_expect_equal(first_run_id.length(), 32, "ladder submit is passed a per-run temp ID")

	arena.complete_ladder()
	_expect_true(result.visible, "closing the ladder panel returns to the result screen")
	_expect_equal(arena.restart_calls, 0, "no automatic retry after recording")
	_expect_equal(arena.title_calls, 0, "no automatic title move after recording")

	# Reopening the same result panel must keep the same run ID and score so the lower ladder layer
	# can de-dupe. A higher score after continue still keeps the same run ID.
	arena.request_record()
	_expect_equal(ladder.last_run_id, first_run_id, "re-recording the same result uses the same run ID")
	arena.complete_ladder()
	arena.set_board_score(65400)
	arena.request_record()
	_expect_equal(ladder.last_run_id, first_run_id, "result after continue still uses the same run ID")
	_expect_equal(ladder.last_score, 65400, "passes a higher final score after continue")
	_free_route_parts(parts)


func _test_without_board() -> void:
	Ladder.entries.clear()
	for i in Ladder.KEEP:
		Ladder.entries.append({
			"score": 1000 + i,
			"version": Ladder.current_version(),
		})

	var shrine_parts: Dictionary = _route_parts(10)
	var shrine_arena: Node = shrine_parts["arena"]
	var shrine_ladder: Control = shrine_parts["ladder"]
	shrine_arena.request_shrine()
	_expect_equal(shrine_ladder.ask_count, 0, "a score outside the ladder skips recording")
	_expect_equal(shrine_arena.title_calls, 1, "shrine choice from outside the ladder goes to title immediately")
	_expect_true(shrine_arena.title_requested_shrine, "shrine request is kept even outside the ladder")
	_free_route_parts(shrine_parts)

	var retry_parts: Dictionary = _route_parts(10)
	var retry_arena: Node = retry_parts["arena"]
	var retry_ladder: Control = retry_parts["ladder"]
	retry_arena.request_restart()
	_expect_equal(retry_ladder.ask_count, 0, "retry from outside the ladder skips recording")
	_expect_equal(retry_arena.restart_calls, 1, "retry from outside the ladder runs immediately")
	_free_route_parts(retry_parts)


func _test_store_handoff_ends_current_run() -> void:
	var parts: Dictionary = _route_parts(1234)
	var arena: Node = parts["arena"]
	var result: Control = parts["result"]

	await arena.request_continue_purchase()

	_expect_false(result.visible, "zero-balance shop move closes the current result run")
	_expect_true(arena.leaving_for_title(), "zero-balance shop move is a current-run-ended state")
	_expect_equal(
		arena.pending_action(), arena.restart_pending_action(),
		"returning from the shop does not resume the just-finished run after a buy")
	_expect_true(arena.title_store_open_requested(), "passes a shop-open request to the next title")
	_expect_equal(arena.release_audio_calls, 1, "goes to the shop after releasing current-run audio")
	_free_route_parts(parts)


func _test_title_handoff() -> void:
	var arena_constants: Dictionary = ARENA_SCRIPT.get_script_constant_map()
	var title_constants: Dictionary = TITLE_SCRIPT.get_script_constant_map()
	var constant_name: String = "OPEN" + "_SHRINE" + "_META"
	var arena_meta: StringName = arena_constants.get(constant_name, &"")
	var title_meta: StringName = title_constants.get(constant_name, &"")
	_expect_equal(arena_meta, title_meta, "Arena and title shrine-handoff keys match")

	get_tree().root.set_meta(arena_meta, true)
	var first: Control = TITLE_SCENE.instantiate() as Control
	add_child(first)
	await get_tree().process_frame
	_expect_true(first.get_node("Ui/Shrine").visible, "handed-off title auto-opens the shrine")
	_expect_false(first.get_node("Ui/Screen").visible, "title buttons hidden when auto-opening the shrine")
	_expect_false(get_tree().root.has_meta(arena_meta), "shrine handoff key is removed as soon as it is read")
	first.queue_free()
	await get_tree().process_frame

	var second: Control = TITLE_SCENE.instantiate() as Control
	add_child(second)
	await get_tree().process_frame
	_expect_false(second.get_node("Ui/Shrine").visible, "shrine request is not repeated on the next title")
	_expect_true(second.get_node("Ui/Screen").visible, "next title is the default screen")
	second.queue_free()
	await get_tree().process_frame


func _route_parts(score: int) -> Dictionary:
	var arena: Node = TESTABLE_ARENA.new() as Node
	var result: Control = RESULT_SPY.new() as Control
	var ladder: Control = LADDER_SPY.new() as Control
	result.visible = true
	arena.prepare(result, ladder, score)
	return {"arena": arena, "result": result, "ladder": ladder}


func _free_route_parts(parts: Dictionary) -> void:
	(parts["arena"] as Node).free()
	(parts["result"] as Control).free()
	(parts["ladder"] as Control).free()


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)


func _expect_false(actual: bool, label: String) -> void:
	_expect_equal(actual, false, label)
