extends Node

## Versioned local ladder save, migration, sort, and display contract.

const PANEL_SCENE: PackedScene = preload("res://scenes/ui/ladder_panel.tscn")
const VERSION_KEY: String = "application/config/version"
const KEEPER: String = "res://resources/heroes/keeper.tres"

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return

	var original_version: Variant = ProjectSettings.get_setting(VERSION_KEY, "1.0.0")
	ProjectSettings.set_setting(VERSION_KEY, "1.0.1")
	_write_ladder({
		"last_name": "moonlight",
		"entries": [
			{"name": "old record", "score": 999999, "cycles": 12},
			{"name": "new record", "score": 10, "cycles": 1, "version": "1.0.1"},
			{"name": "Mid", "score": 500, "cycles": 2, "version": "1.0.0"},
		],
	})
	Ladder.entries.clear()
	Ladder.load_ladder()

	_expect_equal(Ladder.entries.size(), 3, "three save-record lines restored")
	_expect_equal(str(Ladder.entries[0].get("name", "")), "new record",
		"newest version still comes first even with a low score")
	_expect_equal(str(Ladder.entries[1].get("name", "")), "old record",
		"higher scores still come first inside a previous version")
	_expect_equal(str(Ladder.entries[1].get("version", "")), "1.0.0",
		"unversioned records migrate as 1.0.0")
	_expect_equal(str(Ladder.entries[1].get("hero", "missing")), "",
		"legacy records with no hero migrate as an unknown hero")
	_expect_true(int(Ladder.call("_compare_versions", "1.10.0", "1.9.9")) > 0,
		"versions are compared by numeric parts, not as strings")

	Ladder.entries.clear()
	for i in Ladder.KEEP:
		Ladder.entries.append({
			"name": "old%d" % i,
			"score": 100000 - i,
			"version": "1.0.0",
		})
	_expect_true(Ladder.makes_board(1),
		"the first newest-version record enters ahead of older high scores")
	var low_place: int = Ladder.submit("Low", KEEPER, 10, "D", 1)
	var high_place: int = Ladder.submit("High", KEEPER, 20, "D", 1)
	_expect_equal(high_place, 0, "within the same newest version, higher scores come first")
	_expect_equal(low_place, 0, "the first newest-version score entered at the front at that time")
	_expect_equal(str(Ladder.entries[0].get("version", "")), "1.0.1",
		"new record stores the current app version")
	_expect_equal(str(Ladder.entries[0].get("hero", "")), KEEPER,
		"new record stores the actual play hero")

	# Ladder submit idempotency is `(one run ID, final score)`. Reopening the same result
	# still keeps the first row, and if continue raises the live score, that new
	# final result is allowed once more. The run ID is not put on save rows or in the server body.
	Ladder.entries.clear()
	Ladder.set("_submitted_results", {})
	var run_id: String = "0123456789abcdef0123456789abcdef"
	var first_result_place: int = Ladder.submit(
		"firstrec", KEEPER, 400, "B", 2, run_id)
	var duplicate_result_place: int = Ladder.submit(
		"changedn", KEEPER, 400, "B", 2, run_id)
	_expect_equal(first_result_place, 0, "records the first final score of a run")
	_expect_equal(duplicate_result_place, 0, "re-recording the same run and score returns the first slot")
	_expect_equal(Ladder.entries.size(), 1, "no duplicate local rows for the same run and score")
	_expect_equal(str(Ladder.entries[0].get("name", "")), "firstrec",
		"same run and score keep the first recorded contents")
	_expect_true(not Ladder.entries[0].has("run_id"),
		"run ID is not stored on local ladder rows")
	Ladder.submit("firstrec", KEEPER, 900, "A", 3, run_id)
	Ladder.submit("changedn", KEEPER, 900, "A", 3, run_id)
	_expect_equal(Ladder.entries.size(), 2,
		"a higher final score after continue adds exactly one row")
	_expect_equal(int(Ladder.entries[0].get("score", 0)), 900,
		"sorts a higher final result of the same run as a new record")

	GlobalLadder.set("_submitted_results", {})
	_expect_true(bool(GlobalLadder.call("_claim_submission", run_id, 400)),
		"allows the first global final-score request")
	_expect_equal(bool(GlobalLadder.call("_claim_submission", run_id, 400)), false,
		"rejects a duplicate global same-run/score request")
	_expect_true(bool(GlobalLadder.call("_claim_submission", run_id, 900)),
		"allows a higher final score of the same run globally once")
	_expect_equal(bool(GlobalLadder.call("_claim_submission", run_id, 900)), false,
		"a second global request of an even higher final score is still rejected")
	GlobalLadder.call("_release_submission", run_id, 900)
	_expect_true(bool(GlobalLadder.call("_claim_submission", run_id, 900)),
		"keys rolled back after HTTP start failure may be retried")

	# If local save fails, do not leave in-memory rows and the dedupe claim as success.
	# The same result must be resubmittable onto a real file after the path is recovered.
	var ladder_temp_absolute: String = ProjectSettings.globalize_path(
		Ladder.TEMP_SAVE_PATH)
	if FileAccess.file_exists(Ladder.TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ladder_temp_absolute)
	_expect_equal(DirAccess.make_dir_absolute(ladder_temp_absolute), OK,
		"prepares a directory for ladder save failure")
	Ladder.entries.clear()
	Ladder.last_name = "previous name"
	Ladder.set("_submitted_results", {})
	var failed_place: int = Ladder.submit(
		"save failed", KEEPER, 500, "B", 2, run_id)
	var failed_key: String = str(Ladder.call("_submission_key", run_id, 500))
	_expect_equal(failed_place, -1, "does not return success when the ladder file save fails")
	_expect_equal(Ladder.entries.size(), 0, "a save failure rolls back in-memory ladder rows")
	_expect_equal(Ladder.last_name, "previous name", "a save failure rolls back the latest name")
	_expect_false((Ladder.get("_submitted_results") as Dictionary).has(failed_key),
		"a save-failed result does not claim dedupe")
	_expect_equal(DirAccess.remove_absolute(ladder_temp_absolute), OK,
		"ladder save path recovered")
	_expect_equal(Ladder.submit("save ok", KEEPER, 500, "B", 2, run_id), 0,
		"same run/score retry succeeds after path recovery")
	_expect_equal(Ladder.entries.size(), 1, "a successful retry saves one ladder row")
	_expect_true((Ladder.get("_submitted_results") as Dictionary).has(failed_key),
		"dedupe is claimed only after an actual save succeeds")

	Ladder.entries.clear()
	for i in Ladder.KEEP:
		Ladder.entries.append({
			"name": "same%d" % i,
			"score": 100 - i,
			"version": "1.0.1",
		})
	_expect_true(not Ladder.makes_board(91),
		"a same-version cut tie does not open the record window via name sort")
	_expect_true(Ladder.makes_board(92),
		"a score above the same-version cut opens the record window")
	Ladder.entries.clear()
	Ladder.submit("Low", KEEPER, 10, "D", 1)
	Ladder.submit("High", KEEPER, 20, "D", 1)

	var panel: Control = PANEL_SCENE.instantiate() as Control
	add_child(panel)
	await get_tree().process_frame
	var pending: Label = panel.get_node("Center/Rows/Pending") as Label
	# The panel also keeps pending and input, and does not close, before local save succeeds.
	if FileAccess.file_exists(Ladder.TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ladder_temp_absolute)
	_expect_equal(DirAccess.make_dir_absolute(ladder_temp_absolute), OK,
		"prepares a directory for panel-ladder save failure")
	var panel_failed_run_id: String = "11111111111111111111111111111111"
	panel.call("ask", 25, "C", 1, KEEPER, panel_failed_run_id)
	panel.call("close")
	_expect_true(panel.visible, "does not close the ladder panel if local save fails")
	_expect_true(not (panel.get("_pending") as Dictionary).is_empty(),
		"keeps the panel result for retry if local save fails")
	_expect_true((panel.get("_entry") as Control).visible,
		"keeps the name field if local save fails")
	_expect_equal(pending.text, tr("SHRINE_SAVE_FAILED"),
		"tells the panel about a local save failure")
	_expect_equal(DirAccess.remove_absolute(ladder_temp_absolute), OK,
		"panel ladder save path recovered")
	_expect_true(bool(panel.call("_on_submit")),
		"pending-result retry succeeds after save-path recovery")
	_expect_true((panel.get("_pending") as Dictionary).is_empty(),
		"panel result cleared after an actual save succeeds")
	# Later layout checks revert to the original two-row baseline.
	Ladder.entries.clear()
	Ladder.submit("Low", KEEPER, 10, "D", 1)
	Ladder.submit("High", KEEPER, 20, "D", 1)
	panel.call("ask", 20, "D", 1, KEEPER)
	_expect_true(pending.visible, "shows the record summary before name submit")
	_expect_true(pending.text.contains(tr("HERO_KEEPER_NAME")),
		"record summary shows the play hero")
	_expect_true(pending.text.contains("v1.0.1"), "record summary shows the play version")
	_expect_true(pending.text.contains("20"), "record summary shows the score")
	panel.call("view")
	var first_line: Label = panel.get_node("Center/Rows/Board").get_child(0) as Label
	_expect_true(first_line.text.ends_with("v1.0.1"),
		"ladder row shows play version at the end")
	_expect_true(first_line.text.contains(tr("HERO_KEEPER_NAME")),
		"ladder row shows the play hero")
	_expect_true(first_line.text.contains("20"), "ladder row shows the score")
	var remote_rows: Array = [{
		"name": "remote record",
		"hero": KEEPER,
		"score": 777,
		"rank": "S",
		"cycles": 3,
		"version": "1.0.1",
	}]
	panel.call("_on_global", remote_rows)
	_expect_equal((panel.get("_global") as Array).size(), 1,
		"accepts a global-ladder response on the view screen")
	panel.call("close")
	panel.call("view")
	_expect_true((panel.get("_global") as Array).is_empty(),
		"reopening the ladder removes the previous global response")
	first_line = panel.get_node("Center/Rows/Board").get_child(0) as Label
	_expect_true(not first_line.text.contains("remote record"),
		"shows the local ladder before a network response")
	panel.call("_on_global", remote_rows)
	var panel_run_id: String = "fedcba9876543210fedcba9876543210"
	panel.call("ask", 30, "C", 1, KEEPER, panel_run_id)
	_expect_true((panel.get("_global") as Array).is_empty(),
		"switching to the record screen removes the global ladder")
	panel.call("_on_global", remote_rows)
	_expect_true((panel.get("_global") as Array).is_empty(),
		"ignores a late global response during recording")
	_expect_equal((panel.get("_title") as Label).text, tr("LADDER_NEW"),
		"a late global response does not overwrite the record title")
	panel.call("_on_submit")
	_expect_true((panel.get("_global") as Array).is_empty(),
		"post-record table uses the local ladder and local index")
	first_line = panel.get_node("Center/Rows/Board").get_child(0) as Label
	_expect_true(first_line.text.contains("30"),
		"new local score is shown on the first row right after recording")
	var rows_after_panel_submit: int = Ladder.entries.size()
	panel.call("ask", 30, "C", 1, KEEPER, panel_run_id)
	panel.call("_on_submit")
	_expect_equal(Ladder.entries.size(), rows_after_panel_submit,
		"reopening the same result panel does not duplicate local rows")
	panel.call("ask", 31, "C", 1, KEEPER, panel_run_id)
	panel.call("_on_submit")
	_expect_equal(Ladder.entries.size(), rows_after_panel_submit + 1,
		"a higher panel result after continue is added once")
	_expect_equal(panel.call("_hero_name", "res://not-a-hero.tres"),
		tr("LADDER_UNKNOWN_HERO"), "does not load an unknown global hero path")
	panel.queue_free()
	await get_tree().process_frame

	# Even with the server off, the global-submit request field contract must be checkable locally.
	var global_body: Dictionary = GlobalLadder.call(
		"_submission_body", "moonlight", KEEPER, 321, "B", 2)
	var global_fields: Dictionary = global_body.get("fields", {})
	_expect_equal(str(global_fields.get("hero", {}).get("stringValue", "")), KEEPER,
		"global record stores the play hero")
	_expect_equal(str(global_fields.get("version", {}).get("stringValue", "")), "1.0.1",
		"global record stores the play version")
	_expect_equal(str(global_fields.get("score", {}).get("integerValue", "")), "321",
		"global record stores the play score")
	_expect_true(not global_fields.has("run_id"),
		"the dedupe run ID is not put in the global request body")

	# Cutting the global top 20 by score first can drop every low newest-version score.
	# Look up the newest-version top 20 separately, and keep the existing score query for older records.
	var latest_query: Dictionary = GlobalLadder.call("_latest_query_body")
	var latest_structured: Dictionary = latest_query.get("structuredQuery", {})
	var latest_filter: Dictionary = latest_structured.get(
		"where", {}).get("fieldFilter", {})
	_expect_equal(
		str(latest_filter.get("field", {}).get("fieldPath", "")),
		"version",
		"global table looks up the newest-version field separately")
	_expect_equal(str(latest_filter.get("op", "")), "EQUAL",
		"newest-version query looks up only exact-matching records")
	_expect_equal(
		str(latest_filter.get("value", {}).get("stringValue", "")),
		"1.0.1",
		"newest-version query uses the current app version")
	_expect_equal(int(latest_structured.get("limit", 0)), GlobalLadder.FETCH_LIMIT,
		"newest version is also capped at 20 on the server")
	_expect_equal(
		str(latest_structured.get("orderBy", [])[0].get("field", {}).get(
			"fieldPath", "")),
		"score",
		"inside the newest version the server looks up by score")
	_expect_equal(
		str(latest_structured.get("orderBy", [])[0].get("direction", "")),
		"DESCENDING",
		"newest-version scores are looked up descending on the server")

	var score_query: Dictionary = GlobalLadder.call("_score_query_body")
	var score_structured: Dictionary = score_query.get("structuredQuery", {})
	_expect_equal(int(score_structured.get("limit", 0)), GlobalLadder.FETCH_LIMIT,
		"older-best query keeps the existing 20-row contract")
	_expect_equal(
		str(score_structured.get("orderBy", [])[0].get("field", {}).get(
			"fieldPath", "")),
		"score",
		"older-best query stays score-based")
	_expect_equal(
		str(score_structured.get("orderBy", [])[0].get("direction", "")),
		"DESCENDING",
		"older-best query stays descending")

	var latest_row: Dictionary = {
		"_document": "projects/test/documents/scores/latest-low",
		"name": "newest low score",
		"hero": KEEPER,
		"score": 1,
		"rank": "D",
		"cycles": 0,
		"version": "1.0.1",
	}
	var old_highs: Array = [latest_row.duplicate()]
	for i in GlobalLadder.FETCH_LIMIT:
		old_highs.append({
			"_document": "projects/test/documents/scores/old-%d" % i,
			"name": "past%d" % i,
			"hero": KEEPER,
			"score": 100000 - i,
			"rank": "S",
			"cycles": 10,
			"version": "1.0.0",
		})
	var merged_global: Array = GlobalLadder.call(
		"_merge_fetch_rows", [latest_row], old_highs)
	_expect_equal(merged_global.size(), GlobalLadder.FETCH_LIMIT,
		"caps at 20 only after merging both server results")
	_expect_equal(str(merged_global[0].get("name", "")), "newest low score",
		"a low newest-version score is kept even with 20 older high scores")
	var latest_count: int = 0
	for row in merged_global:
		if str(row.get("name", "")) == "newest low score":
			latest_count += 1
	_expect_equal(latest_count, 1, "Firestore documents overlapping both queries are de-duplicated")
	_expect_true(not merged_global[0].has("_document"),
		"Firestore internal document names are stripped from on-screen data")
	var latest_failed: Dictionary = GlobalLadder.call(
		"_fetch_outcome", false, [], true, old_highs)
	_expect_true(not bool(latest_failed.get("ok", true)),
		"does not show older high scores as the remote table if newest-version lookup fails")
	_expect_equal((latest_failed.get("rows", []) as Array).size(), 0,
		"clears remote rows for local-table fallback if newest-version lookup fails")
	var score_failed: Dictionary = GlobalLadder.call(
		"_fetch_outcome", true, [latest_row], false, [])
	_expect_true(bool(score_failed.get("ok", false)),
		"allows older-score lookup failure if newest-version lookup succeeds")
	_expect_equal(
		str((score_failed.get("rows", []) as Array)[0].get("name", "")),
		"newest low score",
		"still shows confirmed newest-version rows if older-score lookup fails")
	_expect_true(not bool(GlobalLadder.call("_should_fetch_score", false, 0)),
		"does not start an older-score request if newest-version lookup fails")
	_expect_true(not bool(GlobalLadder.call(
		"_should_fetch_score", true, GlobalLadder.FETCH_LIMIT)),
		"skips an unneeded second request when 20 newest-version rows are full")
	_expect_true(bool(GlobalLadder.call(
		"_should_fetch_score", true, GlobalLadder.FETCH_LIMIT - 1)),
		"requests older scores only when the newest-version table has empty slots")

	# Two sequential HTTP requests at 6s each would delay local fallback by up to 12s.
	# Check the contract that only remaining shared-deadline time is passed as the next HTTPRequest.timeout.
	var deadline: int = int(GlobalLadder.call("_deadline_after", 1000, 6.0))
	_expect_equal(deadline, 7000, "computes the global table's 6s shared deadline")
	_expect_equal(
		float(GlobalLadder.call("_remaining_seconds", deadline, 5500)),
		1.5,
		"second-request timeout subtracts time spent on the first lookup")
	_expect_equal(
		float(GlobalLadder.call("_remaining_seconds", deadline, 7000)),
		0.0,
		"does not start a second request once the shared deadline is reached")
	_expect_equal(
		float(GlobalLadder.call("_remaining_seconds", deadline, 7500)),
		0.0,
		"time left past the shared deadline does not go negative")

	# Treat the existing personal best as 1.0.0, but do not mix it into 1.0.1 new-best compares.
	var legacy_best: ConfigFile = ConfigFile.new()
	legacy_best.set_value("best", "score", 999999)
	legacy_best.set_value("best", "rank", "S")
	_expect_equal(legacy_best.save(Records.SAVE_PATH), OK, "prepares a legacy personal best")
	Records.load_records()
	_expect_equal(Records.best_score, 0, "a new-version personal best starts separately")
	_expect_true(Records.submit(25, "D"), "first score of a new version is a new best")
	_expect_equal(Records.best_version, "1.0.1", "personal best also stores the version")
	var saved_best: ConfigFile = ConfigFile.new()
	_expect_equal(saved_best.load(Records.SAVE_PATH), OK, "reread the new-version personal best")
	_expect_equal(
		str(saved_best.get_value("best", "version", "")),
		"1.0.1",
		"personal-best file version contract")

	# Personal best also does not confirm in-memory state or the new-best badge before save succeeds.
	# Block the temp path with a directory to reproduce atomic save failure, then after path recovery
	# check the same score can be submitted again.
	var records_temp_absolute: String = ProjectSettings.globalize_path(
		Records.TEMP_SAVE_PATH)
	if FileAccess.file_exists(Records.TEMP_SAVE_PATH):
		DirAccess.remove_absolute(records_temp_absolute)
	var saved_records_text: String = FileAccess.get_file_as_string(Records.SAVE_PATH)
	_expect_equal(DirAccess.make_dir_absolute(records_temp_absolute), OK,
		"prepares a directory for personal-best save failure")
	_expect_equal(
		Records.submit_result(50, "C"),
		Records.SubmitResult.SAVE_FAILED,
		"a personal-best save failure is distinct from a new best")
	_expect_equal(Records.best_score, 25, "best score rolls back after a save failure")
	_expect_equal(Records.best_rank, "D", "best rank rolls back after a save failure")
	_expect_equal(
		FileAccess.get_file_as_string(Records.SAVE_PATH),
		saved_records_text,
		"existing file kept after a personal-best save failure")
	_expect_equal(DirAccess.remove_absolute(records_temp_absolute), OK,
		"personal-best save path recovered")
	_expect_equal(
		Records.submit_result(50, "C"),
		Records.SubmitResult.SAVED,
		"same personal-best retry succeeds after path recovery")
	Records.load_records()
	_expect_equal(Records.best_score, 50, "retried best-score file restored")
	_expect_equal(Records.best_rank, "C", "retried best-rank file restored")

	ProjectSettings.set_setting(VERSION_KEY, original_version)
	Ladder.entries.clear()
	var absolute: String = ProjectSettings.globalize_path(Ladder.SAVE_PATH)
	DirAccess.remove_absolute(absolute)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.TEMP_SAVE_PATH))

	if _failed > 0:
		printerr("versioned-ladder test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("versioned-ladder test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _write_ladder(value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(Ladder.SAVE_PATH, FileAccess.WRITE)
	if file == null:
		printerr("ladder-test save prep failed")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(value))


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() \
		and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("ladder test aborted: user:// path is not isolated — ", user_root)
	return safe


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)


func _expect_false(actual: bool, label: String) -> void:
	_expect_equal(actual, false, label)
