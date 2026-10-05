extends Node

## Owned-journey cloud coordinator tests: host configuration, guest-ID
## reservation, partitioned local journeys, conflict choices, safe restore,
## receipt floors, and bounded Hall reads. No network: the transport runs
## against scripted fakes. Journey and Vault files are real, under the
## isolated test HOME, and are removed afterwards.
##
## Scene-based (like the journey suite) because the coordinator bridges the
## Vault autoload and the Journey globals, which a bare `--script` run does
## not register.

const COORD_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_coordinator.gd")
const TRANSPORT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_transport.gd")
const SCHEMA_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_schema.gd")
const FAKE_SENDER_SCRIPT: Script = preload(
	"res://tests/support/fake_cloud_sender.gd")
const SENDER_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_http_sender.gd")

const PROJECT_ID: String = "moonlitbeacon-778ee"
const TOKEN: String = "test-id-token-coord-xyz"
const WEB_KEY: String = "test-web-key"
const UID_A: String = "uid-coord-alice"
const UID_B: String = "uid-coord-bob"
const GUEST_A: String = "MB-11111111111111111111111111111111"
const GUEST_B: String = "MB-22222222222222222222222222222222"
const CANON_C: String = "MB-cccccccccccccccccccccccccccccccc"
const SHARP_MOON: String = "res://resources/relics/sharp_moon.tres"
const HERO_DANCER: String = "res://resources/heroes/dancer.tres"
const HERO_KNIGHT: String = "res://resources/heroes/knight.tres"

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path(
		"user://").simplify_path()
	if expected_root.is_empty() or not user_root.begins_with(
			expected_root + "/"):
		printerr("cloud coordinator tests aborted: user:// path is not isolated — ",
			user_root)
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_run.call_deferred()


func _run() -> void:
	await _test_offline_start_claims_nothing()
	await _test_guest_reservation_uses_exact_id()
	await _test_existing_account_returns_canonical()
	await _test_guest_slot_moves_to_canonical()
	await _test_save_conflict_after_baseline_match()
	await _test_not_found_with_history_conflicts()
	await _test_identical_catchup_commits_nothing()
	await _test_baseline_survives_restart()
	await _test_local_choice_preserves_advanced_remote()
	await _test_reconcile_preserves_unpaid_local()
	await _test_imported_int_never_aliases_local()
	await _test_string_remote_installs_byte_identical()
	await _test_map_remote_journey_id_contract()
	await _test_newer_seal_survives_inflight_commit()
	await _test_switch_during_checkpoint_await_keeps_new_state()
	await _test_two_generations_share_no_lock()
	await _test_close_silences_late_flush()
	await _test_reconcile_receipt_policy()
	await _test_flush_serializes_owner()
	await _test_guest_collision_never_replaced()
	await _test_legacy_migration_once_without_losing_bytes()
	await _test_account_switch_preserves_journeys()
	await _test_switch_clears_hall_and_pending()
	await _test_stale_flush_applies_nothing()
	await _test_disk_failure_queues_nothing()
	await _test_auto_flush_acknowledges()
	await _test_cas_conflict_and_local_choice()
	await _test_remote_choice_installs_and_floors()
	await _test_malformed_download_rejected()
	await _test_oversized_download_rejected()
	await _test_remote_floor_grants_delta_once()
	await _test_retired_fallback_replay_grants_zero()
	await _test_rank_throttle_and_bounded_cache()
	await _test_rank_matches_owned_best_record()
	await _test_rank_missing_row_unranked()
	await _test_rank_converges_after_submit_and_device()
	await _test_rank_malformed_row_fails_labeled()
	await _test_rank_offline_cache_labeled()
	await _test_switch_during_rank_await()
	await _test_rank_concurrent_calls_bounded()
	await _test_rank_waiter_cancelled_by_switch()
	await _test_rank_invalidation_keeps_newer_pair()
	await _test_safe_restore_with_growth_and_hall()
	await _test_restore_cancel_discards_late_reply()
	await _test_restore_second_claim_preempts_first()
	await _test_sender_pre_bound_and_close()
	_reset_all([GUEST_A, GUEST_B, CANON_C])
	if _failed > 0:
		printerr("cloud coordinator tests failed — ", _failed, "/", _checked,
			" cases")
		get_tree().quit(1)
		return
	print("cloud coordinator tests passed — ", _checked, " cases")
	get_tree().quit(0)


func _config(sender: RefCounted, uid: String, guest: String) -> Dictionary:
	return {
		"uid": uid,
		"guest_public_id": guest,
		"token_supplier": func() -> String: return TOKEN,
		"sender": sender.call("sender_callable"),
		"vault": Vault,
		"release": "4.0.0",
		"project_id": PROJECT_ID,
		"web_api_key": WEB_KEY,
	}


func _new_coordinator() -> Node:
	var coordinator: Node = COORD_SCRIPT.new() as Node
	coordinator.call("set_auto_flush", false)
	return coordinator


func _close_coordinator(coordinator: Node) -> void:
	coordinator.call("close")
	coordinator.free()
	Journey.use_account("")
	Journey.clear_stable_hooks()


func _settle_account(coordinator: Node) -> Dictionary:
	for _index in 240:
		var snapshot: Dictionary = coordinator.call("account_snapshot")
		if str(snapshot.get("state", "")) != "reserving":
			return snapshot
		await get_tree().process_frame
	return coordinator.call("account_snapshot")


func _settle_save(coordinator: Node, states: Array) -> Dictionary:
	for _index in 240:
		var snapshot: Dictionary = coordinator.call("save_snapshot")
		if states.has(str(snapshot.get("state", ""))):
			return snapshot
		await get_tree().process_frame
	return coordinator.call("save_snapshot")


## Fire-and-forget flush whose result lands in `box["result"]` so two
## generations can genuinely overlap while the test interleaves between them.
func _flush_into(box: Dictionary, coordinator: Node) -> void:
	box["result"] = await coordinator.call("flush")


## Fire-and-forget restore whose result lands in `box["result"]` so a
## held read can overlap a cancel or a newer read.
func _restore_into(box: Dictionary, coordinator: Node) -> void:
	box["result"] = await coordinator.call("restore_from_cloud")


func _await_box(box: Dictionary, frames: int = 240) -> bool:
	for _index in frames:
		if box.has("result"):
			return true
		await get_tree().process_frame
	return box.has("result")


func _profile_body(uid: String, public_id: String) -> String:
	return JSON.stringify({
		"name": "projects/%s/databases/(default)/documents/mb_profiles_v1/%s"
			% [PROJECT_ID, uid],
		"fields": {
			"uid": {"stringValue": uid},
			"public_id": {"stringValue": public_id},
			"schema": {"integerValue": "1"},
			"created_at": {"timestampValue": "2026-10-01T00:00:00Z"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
		},
		"createTime": "2026-10-01T00:00:00Z",
		"updateTime": "2026-10-01T00:00:00Z",
	})


func _remote_body(uid: String, revision: int, payload: String,
		update_time: String) -> String:
	return JSON.stringify({
		"name": "projects/%s/databases/(default)/documents/mb_checkpoints_v1/%s"
			% [PROJECT_ID, uid],
		"fields": {
			"uid": {"stringValue": uid},
			"revision": {"integerValue": str(revision)},
			"payload": {"stringValue": payload},
			"schema": {"integerValue": "1"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
		},
		"createTime": "2026-10-01T00:00:00Z",
		"updateTime": update_time,
	})


func _row_body(public_id: String, score: int,
		hero: String = "", cycles: int = 3) -> String:
	var hero_path: String = hero if not hero.is_empty() else Vault.HEROES[0]
	return JSON.stringify({
		"name": "projects/%s/databases/(default)/documents/mb_hall_v1/%s"
			% [PROJECT_ID, public_id],
		"fields": {
			"public_id": {"stringValue": public_id},
			"hero": {"stringValue": hero_path},
			"score": {"integerValue": str(score)},
			"cycles": {"integerValue": str(cycles)},
			"release": {"stringValue": "4.0.0"},
			"schema": {"integerValue": "1"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
		},
	})


func _rank_body(greater: int) -> String:
	return JSON.stringify([{
		"result": {
			"aggregateFields": {
				"greater": {"integerValue": str(greater)},
			}
		}
	}])


func _valid_checkpoint(journey: Variant, checkpoint_id: int,
		shards: int, extra: Dictionary = {}) -> Dictionary:
	var checkpoint: Dictionary = {
		"schema_version": 1,
		"journey_id": journey,
		"checkpoint_id": checkpoint_id,
		"cycle": 3,
		"zone_index": 1,
		"route": [0, 4, -1],
		"run_seed": 7,
		"hero_path": Vault.HEROES[0],
		"relic_stacks": {SHARP_MOON: 2},
		"level": 4,
		"to_next": 12,
		"level_progress": 3,
		"missile_power": 2,
		"missile_progress": 1,
		"first_core_collected": true,
		"kills": 20,
		"kill_score": 300,
		"survived": 120.0,
		"lit_count": 1,
		"overcharge_successes": 0,
		"guardian_meetings": {"0": 1},
		"places_seen": ["forest"],
		"shards_awarded": shards,
		"settled_score": 2400,
		"gate_direction": [1.0, 0.0],
		"opening_played": true,
		"saved_at_unix": 1700000000,
	}
	for key in extra.keys():
		checkpoint[key] = extra[key]
	return checkpoint


func _expected_score(checkpoint: Dictionary) -> int:
	var score := Score.new()
	score.cycles = maxi(int(checkpoint.get("cycle", 1)) - 1, 0)
	score.beacons = int(checkpoint.get("lit_count", 0))
	score.survived = float(checkpoint.get("survived", 0.0))
	score.level = int(checkpoint.get("level", 1))
	score.kills = int(checkpoint.get("kill_score", 0))
	return score.total()


func _wipe_slot(key: String) -> void:
	var candidates: Array[String] = [
		Journey.account_main_path(key),
		Journey.account_backup_path(key),
		Journey.account_revision_path(key),
		Journey.account_rejected_path(key, "local"),
		Journey.account_rejected_path(key, "remote"),
	]
	for candidate in candidates:
		for suffixed in [candidate, candidate + ".tmp"]:
			_remove_path(suffixed)


func _wipe_legacy() -> void:
	for candidate in [Journey.DEFAULT_PATH, Journey.DEFAULT_BACKUP_PATH,
			Journey.DEFAULT_PATH + ".tmp", Journey.DEFAULT_BACKUP_PATH + ".tmp"]:
		_remove_path(candidate)


func _reset_vault() -> void:
	for candidate in ["user://vault.cfg", "user://vault.cfg.tmp",
			"user://vault.cfg.bak", "user://vault.cfg.bak.tmp"]:
		_remove_path(candidate)
	Vault.load_vault()


func _reset_all(keys: Array) -> void:
	for key in keys:
		_wipe_slot(str(key))
	_wipe_legacy()
	_reset_vault()
	Journey.use_account("")
	Journey.clear_stable_hooks()
	Journey.last_error = ""


func _remove_path(candidate: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(candidate)
	if FileAccess.file_exists(candidate):
		DirAccess.remove_absolute(absolute)
	elif DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)


func _read_text(candidate: String) -> String:
	if not FileAccess.file_exists(candidate):
		return ""
	return FileAccess.get_file_as_string(candidate)


func _write_text(candidate: String, text: String) -> void:
	var handle: FileAccess = FileAccess.open(candidate, FileAccess.WRITE)
	handle.store_string(text)
	handle.flush()
	handle.close()


func _rank_call_count(sender: RefCounted) -> int:
	var count: int = 0
	for call in sender.get("calls"):
		if str((call as Dictionary).get("url", "")).contains(
				"runAggregationQuery"):
			count += 1
	return count


func _own_get_call_count(sender: RefCounted) -> int:
	var count: int = 0
	for call in sender.get("calls"):
		var entry: Dictionary = call
		if str(entry.get("method", "")) == "GET" and str(
				entry.get("url", "")).contains("mb_hall_v1/"):
			count += 1
	return count


func _commit_call_count(sender: RefCounted) -> int:
	var count: int = 0
	for call in sender.get("calls"):
		if str((call as Dictionary).get("url", "")).contains(
				"documents:commit"):
			count += 1
	return count


func _hall_commit_call_count(sender: RefCounted) -> int:
	var count: int = 0
	for call in sender.get("calls"):
		var entry: Dictionary = call
		if str(entry.get("url", "")).contains("documents:commit") \
				and str(entry.get("body", "")).contains("mb_hall_v1"):
			count += 1
	return count


## Fire-and-forget rank refresh whose result lands in `box["result"]` so
## two refreshes can genuinely overlap while the test interleaves.
func _refresh_into(box: Dictionary, coordinator: Node) -> void:
	box["result"] = await coordinator.call("refresh_rank")


## Fire-and-forget best submission with the same overlap shape.
func _submit_into(box: Dictionary, coordinator: Node) -> void:
	box["result"] = await coordinator.call("submit_current_best")


func _test_offline_start_claims_nothing() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var coordinator: Node = _new_coordinator()
	var configured: Dictionary = coordinator.call(
		"configure_host", _config(sender, UID_A, GUEST_A))
	_expect_equal(configured.get("status", ""), "ok",
		"offline configure validates and starts locally")
	var account: Dictionary = await _settle_account(coordinator)
	_expect_equal(account.get("state", ""), "offline",
		"offline start reports offline")
	_expect_equal(account.get("public_id", "none"), "",
		"offline start claims no public ID")
	_expect_equal(coordinator.call("account_ready"), false,
		"offline account is not ready")
	_expect_equal(Journey.path, Journey.account_main_path(GUEST_A),
		"offline play partitions by the requested guest ID")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(11, 1, 0)), OK,
		"local checkpoints still write while offline")
	_expect_equal((coordinator.call("save_snapshot") as Dictionary).get(
		"state", ""), "unregistered",
		"offline writes stay local-only")
	_expect_equal(sender.get("calls").size(), 1,
		"offline start sends only the reservation probe")
	_close_coordinator(coordinator)


func _test_guest_reservation_uses_exact_id() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	var account: Dictionary = await _settle_account(coordinator)
	_expect_equal(account.get("state", ""), "ready", "reservation ready")
	_expect_equal(account.get("public_id", ""), GUEST_A,
		"a new UID reserves the exact pre-play guest ID")
	_expect_equal(coordinator.call("account_ready"), true,
		"reserved account is ready")
	var commit: Dictionary = JSON.parse_string(str(
		sender.call("last_call").get("body", "")))
	var writes: Array = commit.get("writes", [])
	_expect_equal(writes.size(), 2, "reservation commits both halves")
	var profile_fields: Dictionary = ((writes[0] as Dictionary).get(
		"update", {}) as Dictionary).get("fields", {})
	_expect_equal((profile_fields.get("public_id", {}) as Dictionary).get(
		"stringValue", ""), GUEST_A,
		"the profile carries the guest ID verbatim")
	_expect_true(str(((writes[1] as Dictionary).get("update", {})
		as Dictionary).get("name", "")).contains(
		"mb_reservations_v1/%s" % GUEST_A),
		"the reservation is keyed by the guest ID verbatim")
	_close_coordinator(coordinator)


func _test_existing_account_returns_canonical() -> void:
	_reset_all([GUEST_A, CANON_C])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _profile_body(UID_A, CANON_C))
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	var account: Dictionary = await _settle_account(coordinator)
	_expect_equal(account.get("state", ""), "ready", "restore ready")
	_expect_equal(account.get("public_id", ""), CANON_C,
		"an existing account returns its canonical ID explicitly")
	_expect_equal(account.get("requested_guest_id", ""), GUEST_A,
		"the supplied guest ID stays visible beside the canonical one")
	_expect_equal(sender.get("calls").size(), 1,
		"restore commits nothing")
	_expect_equal((coordinator.call("_test_state") as Dictionary).get(
		"partition", ""), CANON_C,
		"the slot follows the canonical ID")
	_close_coordinator(coordinator)


func _test_guest_collision_never_replaced() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_reply", {"transport": "ok", "code": 409,
		"body": "exists"})
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	var account: Dictionary = await _settle_account(coordinator)
	_expect_equal(account.get("state", ""), "conflict",
		"a taken guest ID reports a conflict")
	_expect_equal(account.get("code", ""), "guest-id-taken",
		"the collision has its own explicit code")
	_expect_equal(account.get("public_id", "none"), "",
		"no silent replacement ID is ever returned")
	_expect_equal(_commit_call_count(sender), 1,
		"one commit attempt only: no retry with a fresh ID")
	_close_coordinator(coordinator)


func _test_legacy_migration_once_without_losing_bytes() -> void:
	_reset_all([GUEST_A, GUEST_B])
	var legacy_main: String = JSON.stringify(_valid_checkpoint(21, 2, 5))
	var legacy_backup: String = JSON.stringify(_valid_checkpoint(21, 1, 0))
	_write_text(Journey.DEFAULT_PATH, legacy_main)
	_write_text(Journey.DEFAULT_BACKUP_PATH, legacy_backup)
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	var configured: Dictionary = coordinator.call(
		"configure_host", _config(sender, UID_A, GUEST_A))
	var migration: Dictionary = configured.get("migration", {})
	_expect_true(bool(migration.get("moved_main", false)),
		"the legacy main moves to the first guest")
	_expect_true(bool(migration.get("moved_backup", false)),
		"the legacy backup moves to the first guest")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)),
		legacy_main, "the migrated main is byte-identical")
	_expect_equal(_read_text(Journey.account_backup_path(GUEST_A)),
		legacy_backup, "the migrated backup is byte-identical")
	_expect_false(FileAccess.file_exists(Journey.DEFAULT_PATH),
		"the legacy main is gone after its verified move")
	_expect_false(FileAccess.file_exists(Journey.DEFAULT_BACKUP_PATH),
		"the legacy backup is gone after its verified move")
	await _settle_account(coordinator)
	# A second account finds no legacy file left to claim.
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var switched: Dictionary = coordinator.call(
		"configure_host", _config(sender, UID_B, GUEST_B))
	var second_migration: Dictionary = switched.get("migration", {})
	_expect_false(bool(second_migration.get("moved_main", true)),
		"the second guest migrates nothing")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(GUEST_B)),
		"the second guest starts with no journey file")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)),
		legacy_main, "the first guest keeps its migrated bytes")
	await _settle_account(coordinator)
	_close_coordinator(coordinator)


func _test_account_switch_preserves_journeys() -> void:
	_reset_all([GUEST_A, GUEST_B])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	var checkpoint_a: Dictionary = _valid_checkpoint(31, 3, 9)
	_expect_equal(Journey.write_checkpoint(checkpoint_a), OK,
		"account A seals its checkpoint")
	var bytes_a: String = _read_text(Journey.account_main_path(GUEST_A))
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	coordinator.call("configure_host", _config(sender, UID_B, GUEST_B))
	await _settle_account(coordinator)
	_expect_equal(Journey.path, Journey.account_main_path(GUEST_B),
		"the switch repoints the Journey slot")
	var checkpoint_b: Dictionary = _valid_checkpoint(32, 1, 0)
	_expect_equal(Journey.write_checkpoint(checkpoint_b), OK,
		"account B seals its own checkpoint")
	var bytes_b: String = _read_text(Journey.account_main_path(GUEST_B))
	_expect_false(bytes_a == bytes_b, "the two accounts hold different bytes")
	sender.call("queue_ok", _profile_body(UID_A, GUEST_A))
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), bytes_a,
		"account A bytes survive the round trip byte-identical")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_B)), bytes_b,
		"account B bytes are untouched by the switch back")
	_close_coordinator(coordinator)


func _test_switch_clears_hall_and_pending() -> void:
	_reset_all([GUEST_A, GUEST_B])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(41, 2, 4)), OK,
		"account A seals one checkpoint")
	_expect_true(bool((coordinator.call("_test_state") as Dictionary).get(
		"has_pending", false)), "the seal queues a pending upload")
	sender.call("queue_ok", _row_body(GUEST_A, 5000))
	sender.call("queue_ok", _rank_body(7))
	coordinator.call("_test_set_now", 500000)
	var rank: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(rank.get("source", ""), "live", "account A rank is live")
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	coordinator.call("configure_host", _config(sender, UID_B, GUEST_B))
	await _settle_account(coordinator)
	_expect_false(bool((coordinator.call("_test_state") as Dictionary).get(
		"has_pending", true)),
		"the old account pending is dropped, never uploaded as B")
	_expect_equal((coordinator.call("rank_snapshot") as Dictionary).get(
		"state", ""), "unregistered",
		"the old account rank does not leak across the switch")
	_expect_equal((coordinator.call("_test_state") as Dictionary).get(
		"rank_cache", -1), 0, "the Hall cache is cleared on switch")
	_expect_equal((coordinator.call("_test_state") as Dictionary).get(
		"own_cache", -1), 0, "the own-row cache is cleared on switch")
	var flushed: Dictionary = await coordinator.call("flush")
	_expect_equal(flushed.get("code", ""), "nothing-pending",
		"no flush of A payload under B")
	_expect_equal(_commit_call_count(sender), 2,
		"only the two reservation commits were ever sent")
	_close_coordinator(coordinator)


func _test_stale_flush_applies_nothing() -> void:
	_reset_all([GUEST_A, GUEST_B])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(51, 2, 6)), OK,
		"account A seals one checkpoint")
	var payload_a: String = _read_text(Journey.account_main_path(GUEST_A))
	var switching: RefCounted = _SwitchingSender.new(
		coordinator, _config(sender, UID_B, GUEST_B), sender, 4)
	var transport_swap: Dictionary = {
		"uid": UID_A, "guest_public_id": GUEST_A,
		"token_supplier": func() -> String: return TOKEN,
		"sender": switching.call("sender_callable"), "vault": Vault,
		"release": "4.0.0", "project_id": PROJECT_ID,
		"web_api_key": WEB_KEY,
	}
	# Reconfigure through the switching sender first (call 3 restores A),
	# so the later flush load (call 4) trips the switch mid-flight.
	sender.call("queue_ok", _profile_body(UID_A, GUEST_A))
	coordinator.call("configure_host", transport_swap)
	await _settle_account(coordinator)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(51, 3, 7)), OK,
		"account A seals again after the transport swap")
	payload_a = _read_text(Journey.account_main_path(GUEST_A))
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var flushed: Dictionary = await coordinator.call("flush")
	_expect_equal(flushed.get("status", ""), "cancelled",
		"the flush tripped by the switch reports cancelled")
	await _settle_account(coordinator)
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"uid", ""), UID_B, "account B is active after the switch")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), payload_a,
		"account A bytes are untouched by its stale flush")
	for call in sender.get("calls"):
		_expect_false(str((call as Dictionary).get("body", "")).contains(
			payload_a.substr(0, 64)),
			"A payload is never committed, not even under B")
	_close_coordinator(coordinator)


func _test_disk_failure_queues_nothing() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("set_auto_flush", true)
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	var calls_before: int = sender.get("calls").size()
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(
		Journey.path + ".tmp"))
	_expect_not_equal(Journey.write_checkpoint(_valid_checkpoint(61, 1, 0)),
		OK, "the write fails with its temp path occupied")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		Journey.path + ".tmp"))
	for _index in 12:
		await get_tree().process_frame
	_expect_false(bool((coordinator.call("_test_state") as Dictionary).get(
		"has_pending", true)),
		"a failed write queues no cloud upload")
	_expect_equal(sender.get("calls").size(), calls_before,
		"a failed write sends nothing")
	_close_coordinator(coordinator)


func _test_auto_flush_acknowledges() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("set_auto_flush", true)
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var sealed: Dictionary = _valid_checkpoint(71, 1, 0)
	_expect_equal(Journey.write_checkpoint(sealed), OK, "the seal writes")
	var saved: Dictionary = await _settle_save(
		coordinator, ["acked", "error", "offline", "conflict"])
	_expect_equal(saved.get("state", ""), "acked",
		"the deferred auto flush acknowledges the server commit")
	_expect_equal(saved.get("acked_revision", 0), 1,
		"the first upload acks revision 1")
	_close_coordinator(coordinator)


func _conflict_setup() -> Array:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	var local_seal: Dictionary = _valid_checkpoint(81, 5, 12)
	_expect_equal(Journey.write_checkpoint(local_seal), OK,
		"the local seal writes")
	var local_text: String = _read_text(Journey.account_main_path(GUEST_A))
	var remote_seal: Dictionary = _valid_checkpoint(81, 6, 14,
		{"cycle": 5, "kill_score": 900})
	var remote_text: String = JSON.stringify(remote_seal)
	sender.call("queue_ok", _remote_body(UID_A, 5, remote_text,
		"2026-10-01T01:00:00Z"))
	var seen: Array = []
	coordinator.connect("conflict_found",
		func(info: Dictionary) -> void: seen.append(info))
	var flushed: Dictionary = await coordinator.call("flush")
	return [sender, coordinator, flushed, seen, local_text, remote_text]


func _test_cas_conflict_and_local_choice() -> void:
	var setup: Array = await _conflict_setup()
	var sender: RefCounted = setup[0]
	var coordinator: Node = setup[1]
	var flushed: Dictionary = setup[2]
	var seen: Array = setup[3]
	var local_text: String = setup[4]
	var remote_text: String = setup[5]
	_expect_equal(flushed.get("status", ""), "conflict",
		"foreign progress surfaces a conflict before any commit")
	_expect_equal(flushed.get("code", ""), "foreign-progress",
		"the pre-commit conflict names its cause")
	_expect_equal(seen.size(), 1, "the conflict signal fires once")
	_expect_equal((flushed.get("local_summary", {}) as Dictionary).get(
		"cycle", 0), 3, "the local summary marks our cycle")
	_expect_equal((flushed.get("remote_summary", {}) as Dictionary).get(
		"cycle", 0), 5, "the remote summary marks their cycle")
	_expect_equal(_commit_call_count(sender), 1,
		"no silent rebase: only the reservation commit was ever sent")
	sender.call("queue_ok", _remote_body(UID_A, 5, remote_text,
		"2026-10-01T01:00:00Z"))
	sender.call("queue_ok", _remote_body(UID_A, 5, remote_text,
		"2026-10-01T01:00:00Z"))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var kept: Dictionary = await coordinator.call(
		"resolve_conflict", "local")
	_expect_equal(kept.get("code", ""), "local-kept",
		"the explicit local choice lands")
	_expect_equal(kept.get("revision", 0), 6,
		"the local choice lands one past the fresh remote")
	_expect_true(bool(kept.get("remote_exact", false)),
		"the preserved remote is exactly what the commit overwrote")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)),
		local_text, "the local file keeps our bytes")
	_expect_equal((coordinator.call("recovery_payload", "remote") as Dictionary
		).get("text", ""), remote_text,
		"the rejected remote is preserved byte for byte")
	var commit: Dictionary = JSON.parse_string(str(
		sender.call("last_call").get("body", "")))
	var writes: Array = commit.get("writes", [])
	_expect_equal(((writes[0] as Dictionary).get("currentDocument", {})
		as Dictionary).get("updateTime", ""),
		"2026-10-01T01:00:00Z", "the rebase carries the fresh guard")
	_close_coordinator(coordinator)


func _test_remote_choice_installs_and_floors() -> void:
	var setup: Array = await _conflict_setup()
	var coordinator: Node = setup[1]
	var local_text: String = setup[4]
	var remote_text: String = setup[5]
	var bank_before: int = Vault.shards
	var kept: Dictionary = await coordinator.call(
		"resolve_conflict", "remote")
	_expect_equal(kept.get("code", ""), "remote-kept",
		"the explicit remote choice lands")
	_expect_true(bool(kept.get("remapped", false)),
		"an imported integer id installs remapped")
	var mapped: Variant = coordinator.call(
		"map_remote_journey_id", UID_A, 81)
	var installed: Dictionary = Journey.read_checkpoint()
	_expect_equal(installed.get("journey_id", 0), mapped,
		"the installed checkpoint carries the mapped id")
	_expect_equal((coordinator.call("recovery_payload", "remote") as Dictionary
		).get("text", ""), remote_text,
		"the original remote bytes are preserved byte for byte")
	_expect_equal((coordinator.call("recovery_payload", "local") as Dictionary
		).get("text", ""), local_text,
		"the rejected local is preserved byte for byte")
	_expect_equal(Vault.shards, bank_before,
		"the remote history grants zero currency on this device")
	_expect_equal((coordinator.call("save_snapshot") as Dictionary).get(
		"floor_code", ""), "floored",
		"the install records its receipt floor")
	_expect_true(Vault._find_settled_journey(81).is_empty(),
		"the foreign integer never touches the local sequence namespace")
	var delta: Dictionary = Vault.settle_journey_receipt(mapped, 7, 44)
	_expect_equal(int(delta.get("granted", -1)), 30,
		"new play above the floor settles its delta exactly once")
	var replay: Dictionary = Vault.settle_journey_receipt(mapped, 7, 44)
	_expect_equal(int(replay.get("granted", -1)), 0,
		"the delta replay pays nothing")
	_close_coordinator(coordinator)


func _test_malformed_download_rejected() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	var bank_before: int = Vault.shards
	var settled_before: int = (Vault.settled_journeys as Array).size()
	for case in [["not json", "payload-not-json-object"],
			["{bad}", "payload-not-json-object"],
			["{\"gate\":1}", "invalid-checkpoint"]]:
		var bad: String = str((case as Array)[0])
		var want_code: String = str((case as Array)[1])
		sender.call("queue_ok", _remote_body(UID_A, 1, bad,
			"2026-10-01T04:00:00Z"))
		var restored: Dictionary = await coordinator.call(
			"restore_from_cloud")
		_expect_equal(restored.get("status", ""), "failure",
			"a malformed download is refused: " + bad)
		_expect_equal(restored.get("code", ""), want_code,
			"the refusal names its layer: " + bad)
		_expect_false(FileAccess.file_exists(Journey.account_main_path(
			GUEST_A)), "a malformed download installs nothing: " + bad)
	_expect_equal(Vault.shards, bank_before,
		"malformed downloads grant nothing")
	_expect_equal((Vault.settled_journeys as Array).size(), settled_before,
		"malformed downloads floor nothing")
	_close_coordinator(coordinator)


func _test_oversized_download_rejected() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	var huge: Dictionary = _valid_checkpoint(91, 1, 0,
		{"route": [0, 1, 2]})
	huge["pad"] = "x".repeat(40000)
	_expect_true(JSON.stringify(huge).to_utf8_buffer().size() > 32768,
		"the fixture really exceeds the cloud bound")
	sender.call("queue_ok", _remote_body(UID_A, 1, JSON.stringify(huge),
		"2026-10-01T04:00:00Z"))
	var restored: Dictionary = await coordinator.call("restore_from_cloud")
	_expect_equal(restored.get("code", ""), "payload-too-large",
		"an oversized download is refused before install")
	_expect_false(FileAccess.file_exists(Journey.account_main_path(GUEST_A)),
		"an oversized download installs nothing")
	_close_coordinator(coordinator)


func _test_remote_floor_grants_delta_once() -> void:
	_reset_all([GUEST_A])
	_expect_equal(Vault.shards, 0, "the device vault starts empty")
	_expect_equal(Vault.journey_seq_issued, 0,
		"no local journey was ever issued")
	_expect_true(Vault.grant_continue_coins(5, "coin-floor-guard"),
		"a paid coin grant seeds the ledger guard")
	var bundle: Array[String] = [HERO_DANCER]
	_expect_true(Vault.grant_heroes(bundle, Vault.HERO_SOURCE_IAP_BUNDLE),
		"a paid hero grant seeds the ledger guard")
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	var remote_seal: Dictionary = _valid_checkpoint(4242, 9, 100)
	sender.call("queue_ok", _remote_body(UID_A, 4, JSON.stringify(remote_seal),
		"2026-10-01T05:00:00Z"))
	var restored: Dictionary = await coordinator.call("restore_from_cloud")
	_expect_equal(restored.get("code", ""), "restored", "the restore lands")
	_expect_equal(Vault.shards, 0,
		"remote historical points grant zero currency")
	_expect_equal(Vault.continue_coins, Vault.STARTING_COINS + 5,
		"the floor leaves the paid coin balance alone")
	_expect_equal(int(Vault.continue_coin_grants.get("coin-floor-guard", 0)),
		5, "the floor leaves the paid coin ledger alone")
	_expect_equal(Vault.hero_sources.get(HERO_DANCER, []),
		[Vault.HERO_SOURCE_IAP_BUNDLE],
		"the floor leaves paid hero sources alone")
	_expect_equal(Vault.journey_seq_issued, 0,
		"the import never advances the local issue watermark")
	var mapped: Variant = coordinator.call(
		"map_remote_journey_id", UID_A, 4242)
	_expect_equal(Journey.read_checkpoint().get("journey_id", 0), mapped,
		"the restored checkpoint carries the mapped id")
	_expect_true(bool(restored.get("remapped", false)),
		"the restore reports its remap")
	var next: Variant = Vault.begin_journey()
	_expect_equal(next, 1,
		"local issuance continues in its own namespace")
	var delta: Dictionary = Vault.settle_journey_receipt(mapped, 10, 130)
	_expect_equal(int(delta.get("granted", -1)), 30,
		"the first new delta above the floor pays once")
	var replay: Dictionary = Vault.settle_journey_receipt(mapped, 10, 130)
	_expect_equal(int(replay.get("granted", -1)), 0,
		"the delta replay pays nothing")
	_expect_equal(Vault.shards, 30, "exactly the delta banks")
	_close_coordinator(coordinator)


func _test_retired_fallback_replay_grants_zero() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	var vault_tmp: String = "user://vault.cfg.tmp"
	DirAccess.make_dir_absolute(
		ProjectSettings.globalize_path(vault_tmp))
	var fallbacks: Array = []
	for _index in Vault.MAX_SETTLED_JOURNEYS + 1:
		fallbacks.append(Vault.begin_journey())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(vault_tmp))
	var distinct: Dictionary = {}
	for fallback in fallbacks:
		_expect_true(fallback is String,
			"a failed issue falls back to a string id")
		distinct[str(fallback)] = true
	_expect_equal(distinct.size(), fallbacks.size(),
		"every fallback id is distinct")
	var bank_before: int = Vault.shards
	var index: int = 0
	for fallback in fallbacks:
		index += 1
		var settled: Dictionary = Vault.settle_journey_receipt(
			fallback, 1, index)
		_expect_equal(int(settled.get("status", -1)),
			Vault.JourneyReceipt.SETTLED,
			"an issued fallback settles while retained")
	_expect_equal((Vault.settled_journeys as Array).size(),
		Vault.MAX_SETTLED_JOURNEYS, "the ledger stays bounded")
	var evicted: Variant = fallbacks[0]
	var replay: Dictionary = Vault.settle_journey_receipt(evicted, 1, 1)
	_expect_equal(int(replay.get("status", -1)),
		Vault.JourneyReceipt.RETIRED,
		"an evicted fallback replays as retired, never fresh money")
	_expect_equal(int(replay.get("granted", -1)), 0,
		"the retired replay grants zero")
	var unknown: Dictionary = Vault.settle_journey_receipt(
		"rneverissuedhere", 1, 50)
	_expect_equal(int(unknown.get("status", -1)),
		Vault.JourneyReceipt.RETIRED, "an unknown string retires")
	_expect_equal(int(unknown.get("granted", -1)), 0,
		"an unknown string grants zero")
	_expect_equal(Vault.shards - bank_before, 153,
		"the seventeen first settles bank exactly once (1+..+17)")
	_close_coordinator(coordinator)


func _test_rank_throttle_and_bounded_cache() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	coordinator.call("_test_set_now", 800000)
	sender.call("queue_ok", _row_body(GUEST_A, 5000))
	sender.call("queue_ok", _rank_body(7))
	sender.call("queue_ok", _row_body(GUEST_A, 5000))
	sender.call("queue_ok", _rank_body(3))
	var sources: Dictionary = {}
	for index in 200:
		var seal: Dictionary = _valid_checkpoint(101, 1, 0,
			{"kill_score": 300 + index * 10})
		_expect_equal(Journey.write_checkpoint(seal), OK,
			"score change %d seals" % index)
		var rank: Dictionary = await coordinator.call("refresh_rank")
		_expect_equal(rank.get("status", ""), "ok",
			"every throttled rank still answers ok")
		_expect_equal(rank.get("score", -1), 5000,
			"the rank carries the owned best, not the live score")
		sources[str(rank.get("source", ""))] = true
	_expect_equal(_rank_call_count(sender), 1,
		"two hundred score changes fire one rank request")
	_expect_equal(_own_get_call_count(sender), 1,
		"two hundred score changes fire one own-row request")
	_expect_true(int((coordinator.call("_test_state") as Dictionary).get(
		"rank_cache", 999)) <= 8, "the rank cache stays bounded")
	_expect_true(int((coordinator.call("_test_state") as Dictionary).get(
		"own_cache", 999)) <= 8, "the own-row cache stays bounded")
	_expect_true(sources.has("live") and sources.has("cache-throttled"),
		"ranks label live versus throttled last-known")
	coordinator.call("_test_set_now", 900000)
	var seal: Dictionary = _valid_checkpoint(101, 2, 0, {"kill_score": 9999})
	_expect_equal(Journey.write_checkpoint(seal), OK,
		"a later score seals after the window")
	var later: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(later.get("source", ""), "live",
		"the window crossing refreshes live again")
	_expect_equal(_rank_call_count(sender), 2,
		"two windows fire two rank requests total")
	_expect_equal(_own_get_call_count(sender), 2,
		"two windows fire two own-row requests total")
	_close_coordinator(coordinator)


func _test_safe_restore_with_growth_and_hall() -> void:
	_reset_all([GUEST_A])
	_expect_equal(Vault.shards, 0, "the new device vault starts empty")
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var coordinator: Node = _new_coordinator()
	coordinator.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(coordinator)
	var grown: Dictionary = _valid_checkpoint(777, 4, 40, {
		"cycle": 4, "hero_path": HERO_DANCER, "level": 12,
		"missile_power": 5, "kill_score": 5000, "lit_count": 2,
		"survived": 600.0, "relic_stacks": {SHARP_MOON: 3},
	})
	var grown_text: String = JSON.stringify(grown)
	sender.call("queue_ok", _remote_body(UID_A, 4, grown_text,
		"2026-10-01T06:00:00Z"))
	var restored: Dictionary = await coordinator.call("restore_from_cloud")
	_expect_equal(restored.get("code", ""), "restored",
		"the grown checkpoint restores")
	var revived: Dictionary = Journey.read_checkpoint()
	_expect_equal(int(revived.get("cycle", 0)), 4,
		"the restore starts at the validated gate")
	_expect_equal(int(revived.get("level", 0)), 12,
		"combat growth survives the restore")
	_expect_equal((revived.get("relic_stacks", {}) as Dictionary).get(
		SHARP_MOON, 0), 3, "held relic stacks survive the restore")
	_expect_equal(Vault.shards, 0,
		"the restored history grants zero currency")
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var submitted: Dictionary = await coordinator.call("submit_current_best")
	_expect_equal(submitted.get("status", ""), "ok",
		"the best row submits")
	var commit: Dictionary = JSON.parse_string(str(
		sender.call("last_call").get("body", "")))
	var update: Dictionary = ((commit.get("writes", []) as Array)[0]
		as Dictionary).get("update", {})
	_expect_true(str(update.get("name", "")).ends_with(
		"mb_hall_v1/%s" % GUEST_A),
		"the single best row is keyed by our public ID")
	var fields: Dictionary = update.get("fields", {})
	_expect_equal((fields.get("hero", {}) as Dictionary).get(
		"stringValue", ""), HERO_DANCER,
		"the row carries the checkpoint hero")
	_expect_equal(int((fields.get("score", {}) as Dictionary).get(
		"integerValue", "-1")), _expected_score(grown),
		"the row carries the checkpoint-derived score")
	_expect_equal(int((fields.get("score", {}) as Dictionary).get(
		"integerValue", "-1")), 18620,
		"the derived score matches the hand count")
	_expect_equal(int((fields.get("cycles", {}) as Dictionary).get(
		"integerValue", "-1")), 3,
		"the row carries closed cycles (cycle minus one)")
	coordinator.call("_test_set_now", 950000)
	sender.call("queue_ok", _row_body(GUEST_A, 18620, HERO_DANCER, 3))
	sender.call("queue_ok", _rank_body(7))
	var rank: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(rank.get("rank", 0), 8,
		"self rank is the server greater-count plus one, ties shared")
	_expect_equal(rank.get("source", ""), "live", "self rank is live")
	_expect_equal(rank.get("score", 0), 18620,
		"the rank carries the owned best score")
	_expect_equal(rank.get("hero", ""), HERO_DANCER,
		"the rank carries the owned best hero")
	_expect_equal(rank.get("cycles", 0), 3,
		"the rank carries the owned best cycles")
	var transcript: String = JSON.stringify(sender.get("calls"))
	_expect_false(transcript.contains(TOKEN),
		"no request transcript keeps the ID token")
	var hall_bodies: String = ""
	for call in sender.get("calls"):
		var body: String = str((call as Dictionary).get("body", ""))
		# Private profile/checkpoint paths legitimately key by UID; public
		# Hall rows must never carry it.
		if body.contains("mb_hall_v1"):
			hall_bodies += body
	_expect_false(hall_bodies.is_empty(), "a Hall body was actually sent")
	_expect_false(hall_bodies.contains(UID_A),
		"no public Hall row carries the Firebase UID")
	for candidate in [Journey.account_main_path(GUEST_A),
			Journey.account_revision_path(GUEST_A)]:
		_expect_false(_read_text(candidate).contains(TOKEN),
			"local files keep no token: " + candidate)
	_close_coordinator(coordinator)


func _test_restore_cancel_discards_late_reply() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var gated: RefCounted = _GatedSender.new(get_tree(), sender)
	var coordinator: Node = _new_coordinator()
	var config: Dictionary = _config(sender, UID_A, GUEST_A)
	config["sender"] = gated.call("sender_callable")
	gated.set("gate_open", true)
	sender.call("queue_ok", _profile_body(UID_A, GUEST_A))
	coordinator.call("configure_host", config)
	await _settle_account(coordinator)
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"state", ""), "ready", "the gated reservation completes while open")
	var payload: String = JSON.stringify(_valid_checkpoint(
		"remote-j-cancel", 4, 0, {"cycle": 5}))
	gated.set("gate_open", false)
	sender.call("queue_ok", _remote_body(UID_A, 3, payload,
		"2026-10-01T03:00:00Z"))
	var box: Dictionary = {}
	_restore_into(box, coordinator)
	await get_tree().process_frame
	await get_tree().process_frame
	coordinator.call("cancel_pending_restore")
	gated.set("gate_open", true)
	_expect_true(await _await_box(box), "the retired read answers")
	var reply: Dictionary = box.get("result", {})
	_expect_equal(reply.get("status", ""), "cancelled",
		"the retired read reports cancelled")
	_expect_equal(reply.get("code", ""), "stale-reply",
		"the retired read keeps the stale code")
	_expect_true(Journey.read_checkpoint().is_empty(),
		"the retired read installs nothing")
	var idle_save: Dictionary = coordinator.call("save_snapshot")
	_expect_false(str(idle_save.get("state", "")) == "acked",
		"the retired read acks nothing")
	_expect_equal(int(idle_save.get("acked_revision", -1)), 0,
		"the retired read advances no revision")
	# Narrow: a fresh read on the same coordinator still works.
	sender.call("queue_ok", _remote_body(UID_A, 3, payload,
		"2026-10-01T03:00:00Z"))
	var fresh: Dictionary = await coordinator.call("restore_from_cloud")
	_expect_equal(fresh.get("code", ""), "restored",
		"a read after the cancel restores")
	_expect_equal(str(Journey.read_checkpoint().get("journey_id", "")),
		"remote-j-cancel", "the fresh read installs its own bytes")
	_close_coordinator(coordinator)


func _test_restore_second_claim_preempts_first() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var gated: RefCounted = _GatedSender.new(get_tree(), sender)
	var coordinator: Node = _new_coordinator()
	var config: Dictionary = _config(sender, UID_A, GUEST_A)
	config["sender"] = gated.call("sender_callable")
	gated.set("gate_open", true)
	sender.call("queue_ok", _profile_body(UID_A, GUEST_A))
	coordinator.call("configure_host", config)
	await _settle_account(coordinator)
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"state", ""), "ready", "the gated reservation completes while open")
	var first_text: String = JSON.stringify(_valid_checkpoint(
		"remote-j-first", 4, 0, {"cycle": 5}))
	var second_text: String = JSON.stringify(_valid_checkpoint(
		"remote-j-second", 6, 0, {"cycle": 7}))
	gated.set("gate_open", false)
	sender.call("queue_ok", _remote_body(UID_A, 3, first_text,
		"2026-10-01T03:00:00Z"))
	sender.call("queue_ok", _remote_body(UID_A, 4, second_text,
		"2026-10-01T04:00:00Z"))
	var first_box: Dictionary = {}
	var second_box: Dictionary = {}
	_restore_into(first_box, coordinator)
	_restore_into(second_box, coordinator)
	gated.set("gate_open", true)
	_expect_true(await _await_box(first_box), "the first read answers")
	_expect_true(await _await_box(second_box), "the second read answers")
	var first: Dictionary = first_box.get("result", {})
	_expect_equal(first.get("status", ""), "cancelled",
		"the superseded read reports cancelled")
	var second: Dictionary = second_box.get("result", {})
	_expect_equal(second.get("code", ""), "restored",
		"the newer read restores")
	_expect_equal(str(Journey.read_checkpoint().get("journey_id", "")),
		"remote-j-second", "only the newer read installs")
	_close_coordinator(coordinator)


func _test_sender_pre_bound_and_close() -> void:
	_expect_equal(SENDER_SCRIPT.MAX_RESPONSE_BYTES,
		TRANSPORT_SCRIPT.MAX_RESPONSE_BYTES,
		"sender and transport share one response bound")
	var probe: HTTPRequest = HTTPRequest.new()
	probe.set("body_size_limit", SENDER_SCRIPT.MAX_RESPONSE_BYTES)
	_expect_equal(int(probe.get("body_size_limit")),
		SENDER_SCRIPT.MAX_RESPONSE_BYTES,
		"the bound rides the real engine body_size_limit property")
	probe.free()
	var sender_node: Node = SENDER_SCRIPT.new() as Node
	sender_node.call("close")
	var refused: Dictionary = await sender_node.call(
		"send", "GET", "https://example.invalid/x", {}, "")
	_expect_equal(refused.get("transport", ""), "cancelled",
		"a closed sender refuses new requests without sending")
	sender_node.free()
	var fake: RefCounted = FAKE_SENDER_SCRIPT.new()
	fake.call("queue_reply", {"transport": "response-too-large", "code": 200,
		"body": PackedByteArray()})
	var transport: RefCounted = TRANSPORT_SCRIPT.new()
	transport.call("configure", PROJECT_ID, WEB_KEY,
		func() -> String: return TOKEN, fake.call("sender_callable"))
	var reply: Dictionary = await transport.call("get_document",
		"documents/mb_hall_v1/%s" % GUEST_A)
	_expect_equal(reply.get("code", ""), "response-too-large",
		"the pre-receipt bound maps to its own failure")
	_expect_false(bool(reply.get("retryable", true)),
		"an oversized reply never retries")
	_expect_equal(fake.get("calls").size(), 1, "one attempt only")


func _ready_account(sender: RefCounted, coordinator: Node, uid: String,
		guest: String) -> void:
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	coordinator.call("configure_host", _config(sender, uid, guest))
	await _settle_account(coordinator)


func _test_save_conflict_after_baseline_match() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(111, 1, 0)), OK,
		"the first seal writes")
	var first_text: String = _read_text(Journey.account_main_path(GUEST_A))
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var first: Dictionary = await coordinator.call("flush")
	_expect_equal(first.get("status", ""), "ok", "the first upload lands")
	_expect_equal((coordinator.call("save_snapshot") as Dictionary).get(
		"baseline_revision", 0), 1,
		"the commit adopts its baseline")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(111, 2, 9)), OK,
		"the second seal writes")
	var other_text: String = JSON.stringify(_valid_checkpoint(112, 9, 40,
		{"cycle": 5, "kill_score": 700}))
	sender.call("queue_ok", _remote_body(UID_A, 1, first_text,
		"2026-10-01T01:00:00Z"))
	sender.call("queue_reply", {"transport": "ok", "code": 412,
		"body": "stale"})
	sender.call("queue_ok", _remote_body(UID_A, 2, other_text,
		"2026-10-01T03:00:00Z"))
	var flushed: Dictionary = await coordinator.call("flush")
	_expect_equal(flushed.get("code", ""), "revision-conflict",
		"a guard miss between load and commit conflicts")
	_expect_equal(flushed.get("remote_revision", 0), 2,
		"the conflict names the fresh remote revision")
	_expect_equal(_commit_call_count(sender), 3,
		"reservation plus two saves only: no silent rebase after the miss")
	_close_coordinator(coordinator)


func _test_not_found_with_history_conflicts() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(121, 1, 0)), OK,
		"the first seal writes")
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var first: Dictionary = await coordinator.call("flush")
	_expect_equal(first.get("status", ""), "ok", "the first upload lands")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(121, 2, 6)), OK,
		"the second seal writes")
	var commits_before: int = _commit_call_count(sender)
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	var flushed: Dictionary = await coordinator.call("flush")
	_expect_equal(flushed.get("code", ""), "remote-missing",
		"a missing remote with history is a conflict, not a re-create")
	_expect_equal((flushed.get("remote_summary", {}) as Dictionary).get(
		"gate", ""), "remote-not-found",
		"the missing side is labeled, not invented")
	_expect_equal(_commit_call_count(sender), commits_before,
		"the missing-remote conflict sends no commit")
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var kept: Dictionary = await coordinator.call(
		"resolve_conflict", "local")
	_expect_equal(kept.get("code", ""), "local-kept",
		"the explicit local choice recreates the document")
	_expect_equal(kept.get("revision", 0), 1,
		"the re-create mints revision 1")
	_expect_equal(kept.get("remote_revision", -99), -1,
		"no remote ever existed to preserve")
	_close_coordinator(coordinator)


func _test_identical_catchup_commits_nothing() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(131, 1, 0)), OK,
		"the seal writes")
	var sealed_text: String = _read_text(Journey.account_main_path(GUEST_A))
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var first: Dictionary = await coordinator.call("flush")
	_expect_equal(first.get("status", ""), "ok", "the upload lands")
	_close_coordinator(coordinator)
	var commits_before: int = _commit_call_count(sender)
	var revived: Node = _new_coordinator()
	sender.call("queue_ok", _profile_body(UID_A, GUEST_A))
	revived.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(revived)
	_expect_true(bool((revived.call("_test_state") as Dictionary).get(
		"has_pending", false)),
		"the restart catch-up queues the current checkpoint")
	sender.call("queue_ok", _remote_body(UID_A, 1, sealed_text,
		"2026-10-01T01:00:00Z"))
	var flushed: Dictionary = await revived.call("flush")
	_expect_equal(flushed.get("code", ""), "already-in-sync",
		"identical bytes agree without a commit")
	_expect_equal(_commit_call_count(sender), commits_before,
		"the re-check sends no commit")
	_close_coordinator(revived)


func _test_baseline_survives_restart() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(141, 1, 0)), OK,
		"the first seal writes")
	var first_text: String = _read_text(Journey.account_main_path(GUEST_A))
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var first: Dictionary = await coordinator.call("flush")
	_expect_equal(first.get("status", ""), "ok", "the upload lands")
	_expect_true(FileAccess.file_exists(
		Journey.account_revision_path(GUEST_A)),
		"the baseline persists beside the slot")
	_close_coordinator(coordinator)
	var revived: Node = _new_coordinator()
	sender.call("queue_ok", _profile_body(UID_A, GUEST_A))
	revived.call("configure_host", _config(sender, UID_A, GUEST_A))
	await _settle_account(revived)
	_expect_equal((revived.call("save_snapshot") as Dictionary).get(
		"baseline_revision", 0), 1,
		"the restart reloads the durable baseline")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(141, 2, 7)), OK,
		"the second seal writes after the restart")
	sender.call("queue_ok", _remote_body(UID_A, 1, first_text,
		"2026-10-01T01:00:00Z"))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var flushed: Dictionary = await revived.call("flush")
	_expect_equal(flushed.get("status", ""), "ok",
		"new work commits onto the reloaded baseline")
	_expect_equal(flushed.get("revision", 0), 2,
		"the commit lands one past the baseline")
	_close_coordinator(revived)


func _test_local_choice_preserves_advanced_remote() -> void:
	var setup: Array = await _conflict_setup()
	var sender: RefCounted = setup[0]
	var coordinator: Node = setup[1]
	var remote_text: String = setup[5]
	var advanced_seal: Dictionary = _valid_checkpoint(81, 9, 30,
		{"cycle": 7, "kill_score": 1500})
	var advanced_text: String = JSON.stringify(advanced_seal)
	sender.call("queue_ok", _remote_body(UID_A, 5, remote_text,
		"2026-10-01T01:00:00Z"))
	sender.call("queue_ok", _remote_body(UID_A, 7, advanced_text,
		"2026-10-01T05:00:00Z"))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var kept: Dictionary = await coordinator.call(
		"resolve_conflict", "local")
	_expect_equal(kept.get("code", ""), "local-kept",
		"the local choice lands past the advanced remote")
	_expect_equal(kept.get("revision", 0), 8,
		"the commit lands one past the actually read remote")
	_expect_equal((coordinator.call("recovery_payload", "remote") as Dictionary
		).get("text", ""), advanced_text,
		"recovery holds the actually overwritten bytes, not the dialog copy")
	_expect_true(bool(kept.get("remote_exact", false)),
		"the choice reports exact preservation")
	_expect_equal(kept.get("remote_revision", 0), 7,
		"the choice names the preserved revision")
	var commit: Dictionary = JSON.parse_string(str(
		sender.call("last_call").get("body", "")))
	var writes: Array = commit.get("writes", [])
	_expect_equal(((writes[0] as Dictionary).get("currentDocument", {})
		as Dictionary).get("updateTime", ""),
		"2026-10-01T05:00:00Z", "the rebase carries the newest guard")
	_close_coordinator(coordinator)


func _test_reconcile_preserves_unpaid_local() -> void:
	_reset_all([GUEST_A])
	# One locally issued journey seals its earned echo, but the settlement
	# save fails, so the retry is still owed in full across the restart.
	var issued: Variant = Vault.begin_journey()
	_expect_true(issued is int, "the journey issues locally")
	var vault_tmp: String = "user://vault.cfg.tmp"
	DirAccess.make_dir_absolute(
		ProjectSettings.globalize_path(vault_tmp))
	var failed: Dictionary = Vault.settle_journey_receipt(issued, 1, 15)
	_expect_equal(int(failed.get("status", -1)),
		Vault.JourneyReceipt.SAVE_FAILED,
		"the occupied save fails and retains the retry")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(vault_tmp))
	_expect_equal(Journey.write_checkpoint(
		_valid_checkpoint(issued, 2, 15)), OK,
		"the journey seals its earned echo")
	Vault.load_vault()
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	_expect_equal((coordinator.call("save_snapshot") as Dictionary).get(
		"floor_code", ""), "local-pending",
		"reconcile leaves locally-owed value strictly alone")
	_expect_true(Vault._find_settled_journey(issued).is_empty(),
		"no floor record steals the retry")
	_expect_equal(Vault.journey_seq_issued, int(issued),
		"reconcile leaves the local watermark alone")
	var retry: Dictionary = Vault.settle_journey_receipt(issued, 2, 15)
	_expect_equal(int(retry.get("granted", -1)), 15,
		"the failed settlement retries its full value across the restart")
	_expect_equal(Vault.shards, 15, "the retry banks exactly once")
	var replay: Dictionary = Vault.settle_journey_receipt(issued, 2, 15)
	_expect_equal(int(replay.get("granted", -1)), 0,
		"the retry replay pays nothing")
	_close_coordinator(coordinator)


func _test_imported_int_never_aliases_local() -> void:
	_reset_all([GUEST_A])
	var local_five: Dictionary = Vault.settle_journey_receipt(5, 1, 20)
	# Journey 5 was never issued here, so seed it as a genuinely local
	# record first: issue up to it, then settle it.
	_expect_equal(int(local_five.get("status", -1)),
		Vault.JourneyReceipt.RETIRED,
		"an unissued integer still retires on the direct path")
	for _index in 5:
		Vault.begin_journey()
	var seeded: Dictionary = Vault.settle_journey_receipt(5, 1, 20)
	_expect_equal(int(seeded.get("granted", -1)), 20,
		"the local journey 5 settles its own value")
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	var foreign: Dictionary = _valid_checkpoint(5, 9, 100,
		{"cycle": 6, "kill_score": 4000})
	sender.call("queue_ok", _remote_body(UID_A, 3, JSON.stringify(foreign),
		"2026-10-01T06:00:00Z"))
	var restored: Dictionary = await coordinator.call("restore_from_cloud")
	_expect_equal(restored.get("code", ""), "restored",
		"the foreign journey restores")
	var mapped: Variant = coordinator.call(
		"map_remote_journey_id", UID_A, 5)
	_expect_equal(Journey.read_checkpoint().get("journey_id", 0), mapped,
		"the import installs under its mapped id")
	_expect_equal(Vault._find_settled_journey(5), [5, 1, 20],
		"the existing local record is never aliased or corrupted")
	_expect_equal(Vault.shards, 20,
		"the import grants nothing on top of local value")
	var delta: Dictionary = Vault.settle_journey_receipt(mapped, 10, 130)
	_expect_equal(int(delta.get("granted", -1)), 30,
		"new play above the import floor pays its delta once")
	_expect_equal(Vault._find_settled_journey(5), [5, 1, 20],
		"the local record still stands after the import delta")
	_close_coordinator(coordinator)


func _test_string_remote_installs_byte_identical() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	var foreign: Dictionary = _valid_checkpoint("rstrangerdevice9", 4, 25)
	var foreign_text: String = JSON.stringify(foreign)
	sender.call("queue_ok", _remote_body(UID_A, 2, foreign_text,
		"2026-10-01T07:00:00Z"))
	var restored: Dictionary = await coordinator.call("restore_from_cloud")
	_expect_equal(restored.get("code", ""), "restored",
		"the string journey restores")
	_expect_false(bool(restored.get("remapped", true)),
		"strings install without remapping")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)),
		foreign_text, "a string import installs byte-identical")
	_expect_equal(Vault.shards, 0, "the import grants zero")
	var delta: Dictionary = Vault.settle_journey_receipt(
		"rstrangerdevice9", 5, 40)
	_expect_equal(int(delta.get("granted", -1)), 15,
		"new play above the string floor pays its delta once")
	_close_coordinator(coordinator)


func _test_map_remote_journey_id_contract() -> void:
	_reset_all([GUEST_A])
	var coordinator: Node = _new_coordinator()
	var first: Variant = coordinator.call(
		"map_remote_journey_id", UID_A, 81)
	var again: Variant = coordinator.call(
		"map_remote_journey_id", UID_A, 81)
	_expect_true(first is String, "an imported int maps to a string")
	_expect_equal(first, again, "the mapping is deterministic")
	_expect_equal((first as String).length(), 32,
		"the mapped id is short and bounded")
	_expect_true((first as String).is_valid_filename(),
		"the mapped id uses a safe charset")
	_expect_false((first as String).contains(":"),
		"the mapping input separator never leaks into the id")
	var other_uid: Variant = coordinator.call(
		"map_remote_journey_id", UID_B, 81)
	var other_id: Variant = coordinator.call(
		"map_remote_journey_id", UID_A, 82)
	_expect_not_equal(first, other_uid,
		"the mapping separates accounts")
	_expect_not_equal(first, other_id,
		"the mapping separates journeys")
	var whole_float: Variant = coordinator.call(
		"map_remote_journey_id", UID_A, 81.0)
	_expect_equal(whole_float, first,
		"a whole float maps exactly like its integer")
	_expect_equal(coordinator.call(
		"map_remote_journey_id", UID_A, "rkeepme"), "rkeepme",
		"strings pass through untouched")
	_expect_equal(coordinator.call(
		"map_remote_journey_id", UID_A, first), first,
		"an already-mapped id is stable")
	_close_coordinator(coordinator)


func _test_newer_seal_survives_inflight_commit() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(151, 1, 0)), OK,
		"the first seal writes")
	var first_text: String = _read_text(Journey.account_main_path(GUEST_A))
	var sealer: RefCounted = _SealingSender.new(
		sender, _valid_checkpoint(151, 2, 11))
	# Rebind the transport sender mid-test through a reconfigure that
	# restores the same account: the slot and its seal are preserved.
	sender.call("queue_ok", _profile_body(UID_A, GUEST_A))
	var rebound: Dictionary = _config(sender, UID_A, GUEST_A)
	rebound["sender"] = sealer.call("sender_callable")
	coordinator.call("configure_host", rebound)
	await _settle_account(coordinator)
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var first: Dictionary = await coordinator.call("flush")
	_expect_equal(first.get("status", ""), "ok",
		"the first commit lands")
	_expect_equal(first.get("revision", 0), 1,
		"the first commit mints revision 1")
	_expect_true(bool((coordinator.call("_test_state") as Dictionary).get(
		"has_pending", false)),
		"the seal that landed mid-commit is still queued")
	_expect_equal((coordinator.call("save_snapshot") as Dictionary).get(
		"state", ""), "queued",
		"nothing is reported acknowledged before its own commit")
	_expect_equal((coordinator.call("save_snapshot") as Dictionary).get(
		"acked_revision", 0), 1, "only the first seal is acknowledged")
	sealer.set("seal_on_commit", false)
	sender.call("queue_ok", _remote_body(UID_A, 1, first_text,
		"2026-10-01T01:00:00Z"))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var second: Dictionary = await coordinator.call("flush")
	_expect_equal(second.get("revision", 0), 2,
		"the surviving seal commits next, one past the first")
	var commits: Array = []
	for call in sender.get("calls"):
		if str((call as Dictionary).get("url", "")).contains(
				"documents:commit") and str(
				(call as Dictionary).get("body", "")).contains(
				"mb_checkpoints_v1"):
			var body: Dictionary = JSON.parse_string(
				str((call as Dictionary).get("body", "")))
			var fields: Dictionary = (((body.get("writes", [])
				as Array)[0] as Dictionary).get("update", {})
				as Dictionary).get("fields", {})
			commits.append(str((fields.get("payload", {})
				as Dictionary).get("stringValue", "")))
	_expect_equal(commits.size(), 2, "two checkpoint commits went out")
	_expect_true((commits[0] as String).contains("\"checkpoint_id\":1"),
		"the first commit carries the first seal")
	_expect_true((commits[1] as String).contains("\"checkpoint_id\":2"),
		"the second commit carries the seal that landed mid-flight")
	_close_coordinator(coordinator)


func _test_switch_during_checkpoint_await_keeps_new_state() -> void:
	_reset_all([GUEST_A, GUEST_B])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(161, 1, 0)), OK,
		"the first seal writes")
	var first_text: String = _read_text(Journey.account_main_path(GUEST_A))
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var first: Dictionary = await coordinator.call("flush")
	_expect_equal(first.get("status", ""), "ok", "the baseline upload lands")
	var other_text: String = JSON.stringify(_valid_checkpoint(162, 9, 40,
		{"cycle": 5, "kill_score": 700}))
	# Calls so far: 2 reservation + 2 first flush. The rebound restore is
	# call 5; the second flush loads (6), saves into a 412 (7), then the
	# conflict reload (8) trips the switch to B mid-await.
	var switching: RefCounted = _SwitchingSender.new(
		coordinator, _config(sender, UID_B, GUEST_B), sender, 8)
	var rebound: Dictionary = _config(sender, UID_A, GUEST_A)
	rebound["sender"] = switching.call("sender_callable")
	sender.call("queue_ok", _profile_body(UID_A, GUEST_A))
	coordinator.call("configure_host", rebound)
	await _settle_account(coordinator)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(161, 2, 8)), OK,
		"the second seal writes after the transport swap")
	sender.call("queue_ok", _remote_body(UID_A, 1, first_text,
		"2026-10-01T01:00:00Z"))
	sender.call("queue_reply", {"transport": "ok", "code": 412,
		"body": "stale"})
	sender.call("queue_ok", _remote_body(UID_A, 2, other_text,
		"2026-10-01T03:00:00Z"))
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var flushed: Dictionary = await coordinator.call("flush")
	_expect_equal(flushed.get("status", ""), "cancelled",
		"the tripped flush reports cancelled")
	await _settle_account(coordinator)
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"uid", ""), UID_B, "account B is active after the switch")
	_expect_false(bool((coordinator.call("_test_state") as Dictionary).get(
		"has_failed", true)),
		"the old conflict completion retains no failure under B")
	_expect_false(bool((coordinator.call("_test_state") as Dictionary).get(
		"has_pending", true)), "B starts with a clean queue")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(163, 1, 0)), OK,
		"B seals its own checkpoint")
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var landed: Dictionary = await coordinator.call("flush")
	_expect_equal(landed.get("status", ""), "ok",
		"B uploads cleanly on the unpolluted state")
	_expect_equal(landed.get("revision", 0), 1,
		"B mints its own first revision")
	_close_coordinator(coordinator)


func _test_reconcile_receipt_policy() -> void:
	_reset_all([GUEST_A])
	var issued: Variant = Vault.begin_journey()
	_expect_true(issued is int, "the journey issues locally")
	var pending: Dictionary = Vault.reconcile_local_receipt(issued, 2, 15)
	_expect_equal(pending.get("code", ""), "local-pending",
		"a locally-issued id with no record is left alone")
	_expect_equal(pending.get("granted", -1), 0, "reconcile grants nothing")
	_expect_true(Vault._find_settled_journey(issued).is_empty(),
		"reconcile records nothing for the owed retry")
	var retry: Dictionary = Vault.settle_journey_receipt(issued, 2, 15)
	_expect_equal(int(retry.get("granted", -1)), 15,
		"the owed retry still pays in full")
	var settled: Dictionary = Vault.reconcile_local_receipt(issued, 3, 20)
	_expect_equal(settled.get("code", ""), "duplicate",
		"a recorded id reconciles as a duplicate")
	_expect_equal(Vault._find_settled_journey(issued), [issued, 2, 15],
		"reconcile never raises a record from an echo")
	var delta: Dictionary = Vault.settle_journey_receipt(issued, 3, 20)
	_expect_equal(int(delta.get("granted", -1)), 5,
		"the unsettled delta above the record still pays")
	var unknown: Dictionary = Vault.reconcile_local_receipt(
		"rneverissued9", 1, 50)
	_expect_equal(unknown.get("code", ""), "floored",
		"an unknown id floors with zero granted")
	_expect_equal(Vault.shards, 20, "floors bank nothing")
	var retired: Dictionary = Vault.reconcile_local_receipt({}, 1, 5)
	_expect_equal(retired.get("code", ""), "floor-retired",
		"an unusable id retires")
	var vault_tmp: String = "user://vault.cfg.tmp"
	DirAccess.make_dir_absolute(
		ProjectSettings.globalize_path(vault_tmp))
	var stuck: Dictionary = Vault.reconcile_local_receipt(
		"rfloorretry7", 1, 10)
	_expect_equal(stuck.get("code", ""), "floor-save-failed",
		"a failed floor save is reported for retry")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(vault_tmp))
	var floored: Dictionary = Vault.reconcile_local_receipt(
		"rfloorretry7", 1, 10)
	_expect_equal(floored.get("code", ""), "floored",
		"the floor retry lands with zero granted")
	var replay: Dictionary = Vault.settle_journey_receipt(
		"rneverissued9", 1, 50)
	_expect_equal(int(replay.get("granted", -1)), 0,
		"the floored history replay pays nothing")


func _test_two_generations_share_no_lock() -> void:
	_reset_all([GUEST_A, GUEST_B, CANON_C])
	var sender_a: RefCounted = FAKE_SENDER_SCRIPT.new()
	var gated_a: RefCounted = _GatedSender.new(get_tree(), sender_a)
	var coordinator: Node = _new_coordinator()
	var saves: Array = []
	var accounts: Array = []
	var conflicts: Array = []
	coordinator.connect("save_changed",
		func(snap: Dictionary) -> void: saves.append(snap))
	coordinator.connect("account_changed",
		func(snap: Dictionary) -> void: accounts.append(snap))
	coordinator.connect("conflict_found",
		func(info: Dictionary) -> void: conflicts.append(info))
	var config_a: Dictionary = _config(sender_a, UID_A, GUEST_A)
	config_a["sender"] = gated_a.call("sender_callable")
	gated_a.set("gate_open", true)
	sender_a.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender_a.call("queue_ok", "{\"writeResults\":[{},{}]}")
	coordinator.call("configure_host", config_a)
	await _settle_account(coordinator)
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"state", ""), "ready", "generation A becomes ready")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(81, 5, 12)), OK,
		"A seals offline progress")
	var bytes_a: String = _read_text(Journey.account_main_path(GUEST_A))
	_expect_false(bytes_a.is_empty(), "A's slot holds the seal")
	gated_a.set("gate_open", false)
	sender_a.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender_a.call("queue_ok", "{\"writeResults\":[{}]}")
	var box_a: Dictionary = {}
	_flush_into(box_a, coordinator)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool((coordinator.call("_test_state") as Dictionary).get(
		"flush_running", false)), "A's flush owns the upload while parked")
	# Reconfigure while A's upload is parked: the new generation must be
	# able to acquire the lock, and A's late reply must not take it back.
	var sender_b: RefCounted = FAKE_SENDER_SCRIPT.new()
	var gated_b: RefCounted = _GatedSender.new(get_tree(), sender_b)
	var config_b: Dictionary = _config(sender_b, UID_B, GUEST_B)
	config_b["sender"] = gated_b.call("sender_callable")
	gated_b.set("gate_open", true)
	sender_b.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender_b.call("queue_ok", "{\"writeResults\":[{},{}]}")
	coordinator.call("configure_host", config_b)
	await _settle_account(coordinator)
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"state", ""), "ready", "generation B becomes ready while A parks")
	_expect_false(bool((coordinator.call("_test_state") as Dictionary).get(
		"flush_running", true)), "reconfigure frees the retired ticket")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), bytes_a,
		"A's slot survives the switch")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(82, 5, 12)), OK,
		"B seals its own progress")
	var remote_seal: Dictionary = _valid_checkpoint(82, 6, 14,
		{"cycle": 5, "kill_score": 900})
	var remote_text: String = JSON.stringify(remote_seal)
	sender_b.call("queue_ok", _remote_body(UID_B, 5, remote_text,
		"2026-10-01T01:00:00Z"))
	var first: Dictionary = await coordinator.call("flush")
	_expect_equal(first.get("code", ""), "foreign-progress",
		"B's first flush opens a conflict without committing")
	_expect_false(bool((coordinator.call("_test_state") as Dictionary).get(
		"flush_running", true)), "the conflict exit releases B's ticket")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(82, 7, 16)), OK,
		"B seals newer progress under the open conflict")
	gated_b.set("gate_open", false)
	sender_b.call("queue_ok", _remote_body(UID_B, 5, remote_text,
		"2026-10-01T01:00:00Z"))
	var box_b: Dictionary = {}
	_flush_into(box_b, coordinator)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool((coordinator.call("_test_state") as Dictionary).get(
		"flush_running", false)), "B's second flush owns the upload")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(82, 8, 18)), OK,
		"a third B seal queues behind the parked upload")
	var bytes_b: String = _read_text(Journey.account_main_path(GUEST_B))
	var frozen_saves: int = saves.size()
	var frozen_accounts: int = accounts.size()
	var frozen_conflicts: int = conflicts.size()
	var frozen_save: String = JSON.stringify(
		coordinator.call("save_snapshot"))
	var frozen_account: String = JSON.stringify(
		coordinator.call("account_snapshot"))
	var frozen_calls: int = (sender_b.get("calls") as Array).size()
	# A's sender answers while B stays blocked: A retires, B keeps the
	# lock, and no new active-account state is emitted.
	gated_a.set("gate_open", true)
	var settled_a: bool = await _await_box(box_a)
	_expect_true(settled_a, "A's parked flush completes")
	_expect_equal((box_a.get("result", {}) as Dictionary).get(
		"status", ""), "cancelled", "the retired flush reports cancelled")
	_expect_true(bool((coordinator.call("_test_state") as Dictionary).get(
		"flush_running", false)),
		"the stale completion cannot unlock B's upload")
	_expect_equal(saves.size(), frozen_saves,
		"A emits no save state into B's account")
	_expect_equal(accounts.size(), frozen_accounts,
		"A emits no account state into B's account")
	_expect_equal(conflicts.size(), frozen_conflicts,
		"A emits no conflict into B's account")
	_expect_equal(JSON.stringify(coordinator.call("save_snapshot")),
		frozen_save, "B's save snapshot is untouched")
	_expect_equal(JSON.stringify(coordinator.call("account_snapshot")),
		frozen_account, "B's account snapshot is untouched")
	_expect_equal((sender_b.get("calls") as Array).size(), frozen_calls,
		"A's answer sends nothing on B's sender")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_B)), bytes_b,
		"B's file is untouched by the stale reply")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), bytes_a,
		"A's file is untouched by its own stale reply")
	# A third flush, restore, or choice waits while B's upload is out.
	var third: Dictionary = await coordinator.call("flush")
	_expect_equal(third.get("code", ""), "flush-already-running",
		"a third flush waits its turn")
	var blocked_restore: Dictionary = await coordinator.call(
		"restore_from_cloud")
	_expect_equal(blocked_restore.get("code", ""), "flush-in-flight",
		"restore waits for the outstanding upload")
	var blocked_choice: Dictionary = await coordinator.call(
		"resolve_conflict", "local")
	_expect_equal(blocked_choice.get("code", ""), "flush-in-flight",
		"the open choice waits for the outstanding upload")
	_expect_equal((sender_b.get("calls") as Array).size(), frozen_calls,
		"refused operations send nothing")
	# B's own sender answers: the parked upload finishes and releases.
	gated_b.set("gate_open", true)
	var settled_b: bool = await _await_box(box_b)
	_expect_true(settled_b, "B's parked flush completes")
	_expect_equal((box_b.get("result", {}) as Dictionary).get(
		"code", ""), "foreign-progress",
		"B's upload still refuses the foreign remote")
	_expect_false(bool((coordinator.call("_test_state") as Dictionary).get(
		"flush_running", true)), "B's completion releases its own ticket")
	_expect_equal((coordinator.call("save_snapshot") as Dictionary).get(
		"state", ""), "conflict", "B's save reports the conflict")
	sender_b.call("queue_ok", _remote_body(UID_B, 5, remote_text,
		"2026-10-01T01:00:00Z"))
	sender_b.call("queue_ok", _remote_body(UID_B, 5, remote_text,
		"2026-10-01T01:00:00Z"))
	sender_b.call("queue_ok", "{\"writeResults\":[{}]}")
	var kept: Dictionary = await coordinator.call(
		"resolve_conflict", "local")
	_expect_equal(kept.get("code", ""), "local-kept",
		"the choice proceeds once the lock is free")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), bytes_a,
		"A's slot still holds its bytes at the end")
	_close_coordinator(coordinator)


func _test_close_silences_late_flush() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var gated: RefCounted = _GatedSender.new(get_tree(), sender)
	var coordinator: Node = _new_coordinator()
	var saves: Array = []
	var accounts: Array = []
	coordinator.connect("save_changed",
		func(snap: Dictionary) -> void: saves.append(snap))
	coordinator.connect("account_changed",
		func(snap: Dictionary) -> void: accounts.append(snap))
	var config: Dictionary = _config(sender, UID_A, GUEST_A)
	config["sender"] = gated.call("sender_callable")
	gated.set("gate_open", true)
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	coordinator.call("configure_host", config)
	await _settle_account(coordinator)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(81, 5, 12)), OK,
		"the seal writes before close")
	var sealed: String = _read_text(Journey.account_main_path(GUEST_A))
	gated.set("gate_open", false)
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var box: Dictionary = {}
	_flush_into(box, coordinator)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool((coordinator.call("_test_state") as Dictionary).get(
		"flush_running", false)), "the flush owns the upload while parked")
	coordinator.call("close")
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"state", ""), "closed", "close reports the closed account")
	_expect_equal((coordinator.call("save_snapshot") as Dictionary).get(
		"state", ""), "closed", "close reports the closed save")
	_expect_false(bool((coordinator.call("_test_state") as Dictionary).get(
		"flush_running", true)), "close frees the retired ticket")
	var frozen_saves: int = saves.size()
	var frozen_accounts: int = accounts.size()
	gated.set("gate_open", true)
	var settled: bool = await _await_box(box)
	_expect_true(settled, "the parked flush still completes")
	_expect_equal((box.get("result", {}) as Dictionary).get(
		"status", ""), "cancelled",
		"the late completion reports cancelled after close")
	for _index in 8:
		await get_tree().process_frame
	_expect_equal(saves.size(), frozen_saves,
		"the late reply emits no save state after close")
	_expect_equal(accounts.size(), frozen_accounts,
		"the late reply emits no account state after close")
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"state", ""), "closed", "the account stays closed")
	_expect_equal((coordinator.call("save_snapshot") as Dictionary).get(
		"state", ""), "closed", "the save stays closed")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), sealed,
		"the late reply touches no file")
	_close_coordinator(coordinator)


func _test_flush_serializes_owner() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var gated: RefCounted = _GatedSender.new(get_tree(), sender)
	var coordinator: Node = _new_coordinator()
	var config: Dictionary = _config(sender, UID_A, GUEST_A)
	config["sender"] = gated.call("sender_callable")
	gated.set("gate_open", true)
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	coordinator.call("configure_host", config)
	await _settle_account(coordinator)
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"state", ""), "ready", "the gated reservation completes while open")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(171, 1, 0)), OK,
		"the seal writes")
	gated.set("gate_open", false)
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	coordinator.call("flush")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool((coordinator.call("_test_state") as Dictionary).get(
		"flush_running", false)), "the first flush owns the upload")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(171, 2, 5)), OK,
		"a newer seal lands while the first upload is parked")
	var second: Dictionary = await coordinator.call("flush")
	_expect_equal(second.get("code", ""), "flush-already-running",
		"the second caller waits its turn without sending")
	gated.set("gate_open", true)
	var saved: Dictionary = coordinator.call("save_snapshot")
	for _index in 240:
		saved = coordinator.call("save_snapshot")
		if int(saved.get("acked_revision", 0)) == 1:
			break
		await get_tree().process_frame
	_expect_equal(saved.get("state", ""), "queued",
		"the parked flush lands with the newer seal still queued")
	_expect_equal(saved.get("acked_revision", 0), 1,
		"only the parked seal is acknowledged")
	_close_coordinator(coordinator)


func _test_guest_slot_moves_to_canonical() -> void:
	_reset_all([GUEST_B, CANON_C])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _profile_body(UID_B, CANON_C))
	var gated: RefCounted = _GatedSender.new(get_tree(), sender)
	var coordinator: Node = _new_coordinator()
	var config: Dictionary = _config(sender, UID_B, GUEST_B)
	config["sender"] = gated.call("sender_callable")
	coordinator.call("configure_host", config)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"state", ""), "reserving",
		"the reservation parks at the gate")
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(71, 1, 2)), OK,
		"offline progress seals on the guest slot")
	var guest_bytes: String = _read_text(Journey.account_main_path(GUEST_B))
	_expect_false(guest_bytes.is_empty(), "the guest slot holds the seal")
	gated.set("gate_open", true)
	var account: Dictionary = await _settle_account(coordinator)
	_expect_equal(account.get("state", ""), "ready",
		"the gated reservation completes")
	_expect_equal(account.get("public_id", ""), CANON_C,
		"the canonical ID wins explicitly")
	_expect_equal(_read_text(Journey.account_main_path(CANON_C)),
		guest_bytes, "the offline seal moves under the canonical ID")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(GUEST_B)),
		"the guest original is gone after its verified move")
	_close_coordinator(coordinator)


func _test_rank_matches_owned_best_record() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	var fresh: Dictionary = _valid_checkpoint(201, 1, 0, {
		"cycle": 1, "hero_path": HERO_DANCER, "level": 1,
		"kill_score": 10, "kills": 0, "lit_count": 0, "survived": 0.0,
	})
	_expect_equal(_expected_score(fresh), 10,
		"the fresh Dancer journey derives exactly 10")
	_expect_equal(Journey.write_checkpoint(fresh), OK,
		"the fresh journey seals")
	var sealed: String = _read_text(Journey.account_main_path(GUEST_A))
	var shards_before: int = Vault.shards
	coordinator.call("_test_set_now", 950000)
	sender.call("queue_ok", _row_body(GUEST_A, 100, HERO_KNIGHT, 2))
	sender.call("queue_ok", _rank_body(0))
	var rank: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(rank.get("status", ""), "ok", "the owned rank answers")
	_expect_equal(rank.get("rank", 0), 1,
		"one player on the board ranks first, not second")
	_expect_equal(rank.get("greater", -1), 0,
		"nothing stands above the owned best")
	_expect_equal(rank.get("score", 0), 100,
		"the rank carries the owned 100, not the live 10")
	_expect_equal(rank.get("hero", ""), HERO_KNIGHT,
		"the rank carries the historic Knight, not the new Dancer")
	_expect_equal(rank.get("cycles", 0), 2,
		"the rank carries the owned cycles")
	_expect_equal(rank.get("public_id", ""), GUEST_A,
		"the rank carries our public ID")
	_expect_equal(rank.get("source", ""), "live", "the rank is live")
	_expect_equal(rank.get("row_source", ""), "live",
		"the own half is live")
	_expect_equal(rank.get("rank_source", ""), "live",
		"the count half is live")
	_expect_equal(rank.get("fetched_msec", 0), 950000,
		"the pair keeps its measurement time")
	var snapshot: Dictionary = coordinator.call("rank_snapshot")
	_expect_equal(snapshot.get("state", ""), "ready",
		"the snapshot is ready")
	_expect_equal(snapshot.get("rank", 0), 1,
		"the snapshot ranks the owned record first")
	_expect_equal(snapshot.get("score", 0), 100,
		"the snapshot carries the owned score")
	_expect_equal(snapshot.get("hero", ""), HERO_KNIGHT,
		"the snapshot carries the owned hero")
	_expect_equal(snapshot.get("requested_score", 0), 100,
		"the requested score is the ranked owned best")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), sealed,
		"ranking rewrites no local journey byte")
	_expect_equal(Vault.shards, shards_before,
		"ranking floors no currency")
	_expect_equal(_hall_commit_call_count(sender), 0,
		"ranking starts no submission")
	_close_coordinator(coordinator)


func _test_rank_missing_row_unranked() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	coordinator.call("_test_set_now", 960000)
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	var rank: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(rank.get("status", ""), "unranked",
		"a missing own row is unranked with no checkpoint at all")
	_expect_equal(rank.get("code", ""), "own-row-missing",
		"the miss keeps its explicit code")
	_expect_equal(rank.get("rank", -1), 0, "no invented #1")
	var snapshot: Dictionary = coordinator.call("rank_snapshot")
	_expect_equal(snapshot.get("state", ""), "unranked",
		"the snapshot is unranked")
	_expect_equal(snapshot.get("public_id", ""), GUEST_A,
		"the unranked snapshot stays bound to our ID")
	var fresh: Dictionary = _valid_checkpoint(202, 1, 0, {
		"cycle": 1, "hero_path": HERO_DANCER, "level": 1,
		"kill_score": 10, "kills": 0, "lit_count": 0, "survived": 0.0,
	})
	_expect_equal(Journey.write_checkpoint(fresh), OK,
		"the fresh journey seals")
	var sealed: String = _read_text(Journey.account_main_path(GUEST_A))
	var again: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(again.get("status", ""), "unranked",
		"the sealed journey stays unranked while the row is missing")
	_expect_equal(again.get("source", ""), "cache-throttled",
		"the repeat is labeled throttled")
	_expect_equal(_own_get_call_count(sender), 1,
		"the miss is never re-probed inside the window")
	_expect_equal(_rank_call_count(sender), 0,
		"no count query fires without an owned score")
	coordinator.call("_test_set_now", 1030000)
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	var later: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(later.get("source", ""), "live",
		"the expired miss re-probes live for a first submit")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), sealed,
		"an unranked refresh rewrites no local journey byte")
	_expect_equal(_hall_commit_call_count(sender), 0,
		"an unranked refresh invents no submission")
	_close_coordinator(coordinator)


func _test_rank_converges_after_submit_and_device() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	var grown: Dictionary = _valid_checkpoint(203, 4, 9)
	_expect_equal(Journey.write_checkpoint(grown), OK,
		"the grown journey seals")
	var local_best: int = _expected_score(grown)
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var submitted: Dictionary = await coordinator.call(
		"submit_current_best")
	_expect_equal(submitted.get("status", ""), "ok",
		"the first best submits")
	coordinator.call("_test_set_now", 970000)
	sender.call("queue_ok", _row_body(GUEST_A, local_best,
		Vault.HEROES[0], 2))
	sender.call("queue_ok", _rank_body(5))
	var first: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(first.get("score", 0), local_best,
		"the refresh converges to the submitted best")
	_expect_equal(first.get("rank", 0), 6,
		"the refresh converges to the submitted rank")
	var low: Dictionary = _valid_checkpoint(204, 1, 0, {
		"cycle": 1, "hero_path": HERO_DANCER, "level": 1,
		"kill_score": 10, "kills": 0, "lit_count": 0, "survived": 0.0,
	})
	_expect_equal(Journey.write_checkpoint(low), OK,
		"a fresh low journey seals over the grown one")
	var low_bytes: String = _read_text(Journey.account_main_path(GUEST_A))
	sender.call("queue_ok", _row_body(GUEST_A, 50000, HERO_DANCER, 9))
	var refused: Dictionary = await coordinator.call(
		"submit_current_best")
	_expect_equal(refused.get("code", ""), "not-best",
		"the low submit loses to the server best")
	sender.call("queue_ok", _row_body(GUEST_A, 50000, HERO_DANCER, 9))
	sender.call("queue_ok", _rank_body(1))
	var second: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(second.get("score", 0), 50000,
		"not-best converges to the server best score")
	_expect_equal(second.get("hero", ""), HERO_DANCER,
		"not-best converges to the server best hero")
	_expect_equal(second.get("rank", 0), 2,
		"not-best converges to the server best rank")
	coordinator.call("_test_set_now", 1040000)
	sender.call("queue_ok", _row_body(GUEST_A, 80000, HERO_KNIGHT, 12))
	sender.call("queue_ok", _rank_body(0))
	var third: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(third.get("score", 0), 80000,
		"another device's higher row converges by score")
	_expect_equal(third.get("hero", ""), HERO_KNIGHT,
		"another device's higher row converges by hero")
	_expect_equal(third.get("rank", 0), 1,
		"another device's higher row converges by rank")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)),
		low_bytes, "converging refreshes rewrite no local journey byte")
	_close_coordinator(coordinator)


func _test_rank_malformed_row_fails_labeled() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(205, 1, 0)),
		OK, "the journey seals")
	var sealed: String = _read_text(Journey.account_main_path(GUEST_A))
	coordinator.call("_test_set_now", 980000)
	sender.call("queue_ok", _row_body(GUEST_A, 100,
		"res://resources/heroes/bogus.tres"))
	var rank: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(rank.get("status", ""), "failure",
		"an allow-listed hero is required")
	_expect_equal(rank.get("code", ""), "bad-hall-row",
		"the bogus hero keeps its code")
	var snapshot: Dictionary = coordinator.call("rank_snapshot")
	_expect_equal(snapshot.get("state", ""), "error",
		"the snapshot is labeled error")
	_expect_equal(snapshot.get("live_error", ""), "bad-hall-row",
		"the snapshot names the row failure")
	_expect_equal((coordinator.call("_test_state") as Dictionary).get(
		"own_cache", -1), 0, "a malformed row caches nothing")
	sender.call("queue_ok", _row_body(GUEST_B, 100))
	var foreign: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(foreign.get("code", ""), "bad-hall-row",
		"another ID's row is refused as malformed")
	sender.call("queue_ok", _row_body(GUEST_A, 100, HERO_KNIGHT, 2))
	sender.call("queue_ok", _rank_body(0))
	var recovered: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(recovered.get("rank", 0), 1,
		"a valid row recovers live afterwards")
	_expect_equal((coordinator.call("rank_snapshot") as Dictionary).get(
		"state", ""), "ready", "the snapshot is ready again")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), sealed,
		"malformed rows rewrite no local journey byte")
	_close_coordinator(coordinator)


func _test_rank_offline_cache_labeled() -> void:
	_reset_all([GUEST_A, GUEST_B])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(206, 1, 0)),
		OK, "the journey seals")
	coordinator.call("_test_set_now", 990000)
	sender.call("queue_ok", _row_body(GUEST_A, 5000))
	sender.call("queue_ok", _rank_body(4))
	var live: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(live.get("source", ""), "live", "the first rank is live")
	coordinator.call("_test_set_now", 1060000)
	sender.call("queue_reply", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var fallback: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(fallback.get("status", ""), "ok",
		"an expired cache plus offline still answers")
	_expect_equal(fallback.get("source", ""), "cache",
		"the offline answer is labeled cache")
	_expect_equal(fallback.get("live_error", ""), "offline",
		"the offline answer names the live failure")
	_expect_equal(fallback.get("score", 0), 5000,
		"the offline answer keeps the owned best")
	_expect_equal(fallback.get("rank", 0), 5,
		"the offline answer keeps the owned rank")
	var snapshot: Dictionary = coordinator.call("rank_snapshot")
	_expect_equal(snapshot.get("state", ""), "ready",
		"the snapshot stays ready on labeled cache")
	_expect_equal(_own_get_call_count(sender), 2,
		"the offline probe is the only extra request")
	_expect_equal(_rank_call_count(sender), 1,
		"no count query follows the failed own read")
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	coordinator.call("configure_host", _config(sender, UID_B, GUEST_B))
	await _settle_account(coordinator)
	coordinator.call("_test_set_now", 1070000)
	sender.call("queue_reply", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var bare: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(bare.get("status", ""), "offline",
		"offline with nothing cached reports offline")
	_expect_equal((coordinator.call("rank_snapshot") as Dictionary).get(
		"state", ""), "offline",
		"the bare snapshot is labeled offline")
	_close_coordinator(coordinator)


func _test_switch_during_rank_await() -> void:
	_reset_all([GUEST_A, GUEST_B])
	var sender_a: RefCounted = FAKE_SENDER_SCRIPT.new()
	var gated_a: RefCounted = _GatedSender.new(get_tree(), sender_a)
	var coordinator: Node = _new_coordinator()
	var ranks: Array = []
	coordinator.connect("rank_changed",
		func(snap: Dictionary) -> void: ranks.append(snap))
	var config_a: Dictionary = _config(sender_a, UID_A, GUEST_A)
	config_a["sender"] = gated_a.call("sender_callable")
	gated_a.set("gate_open", true)
	sender_a.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender_a.call("queue_ok", "{\"writeResults\":[{},{}]}")
	coordinator.call("configure_host", config_a)
	await _settle_account(coordinator)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(207, 1, 0)),
		OK, "account A seals")
	var bytes_a: String = _read_text(Journey.account_main_path(GUEST_A))
	gated_a.set("gate_open", false)
	sender_a.call("queue_ok", _row_body(GUEST_A, 5000))
	var box_a: Dictionary = {}
	_refresh_into(box_a, coordinator)
	await get_tree().process_frame
	await get_tree().process_frame
	var sender_b: RefCounted = FAKE_SENDER_SCRIPT.new()
	var gated_b: RefCounted = _GatedSender.new(get_tree(), sender_b)
	var config_b: Dictionary = _config(sender_b, UID_B, GUEST_B)
	config_b["sender"] = gated_b.call("sender_callable")
	gated_b.set("gate_open", true)
	sender_b.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender_b.call("queue_ok", "{\"writeResults\":[{},{}]}")
	coordinator.call("configure_host", config_b)
	await _settle_account(coordinator)
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"uid", ""), UID_B, "account B is active while A parks")
	gated_a.set("gate_open", true)
	var settled_a: bool = await _await_box(box_a)
	_expect_true(settled_a, "the parked own-row read completes")
	_expect_equal((box_a.get("result", {}) as Dictionary).get(
		"status", ""), "cancelled",
		"the retired own-row read reports cancelled")
	_expect_equal((sender_a.get("calls") as Array).size(), 3,
		"the retired read sends no count query after the switch")
	_expect_equal((coordinator.call("rank_snapshot") as Dictionary).get(
		"state", ""), "unregistered",
		"the retired read applies no rank under B")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), bytes_a,
		"the retired read touches no file")
	_close_coordinator(coordinator)
	for snap in ranks:
		_expect_equal((snap as Dictionary).get("state", ""),
			"unregistered",
			"a retired own-row read emits no ranked state")

	_reset_all([GUEST_A, GUEST_B])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var second: Node = _new_coordinator()
	var second_ranks: Array = []
	second.connect("rank_changed",
		func(snap: Dictionary) -> void: second_ranks.append(snap))
	await _ready_account(sender, second, UID_A, GUEST_A)
	var switching: RefCounted = _SwitchingSender.new(
		second, _config(sender, UID_B, GUEST_B), sender, 5)
	var rebound: Dictionary = _config(sender, UID_A, GUEST_A)
	rebound["sender"] = switching.call("sender_callable")
	sender.call("queue_ok", _profile_body(UID_A, GUEST_A))
	second.call("configure_host", rebound)
	await _settle_account(second)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(208, 1, 0)),
		OK, "account A seals after the transport swap")
	var bytes_switched: String = _read_text(
		Journey.account_main_path(GUEST_A))
	second.call("_test_set_now", 1080000)
	sender.call("queue_ok", _row_body(GUEST_A, 5000))
	sender.call("queue_ok", _rank_body(4))
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var tripped: Dictionary = await second.call("refresh_rank")
	_expect_equal(tripped.get("status", ""), "cancelled",
		"the rank tripped by the switch reports cancelled")
	await _settle_account(second)
	_expect_equal((second.call("account_snapshot") as Dictionary).get(
		"uid", ""), UID_B, "account B is active after the switch")
	_expect_equal((second.call("rank_snapshot") as Dictionary).get(
		"state", ""), "unregistered",
		"the tripped rank applies nothing under B")
	_expect_equal((second.call("_test_state") as Dictionary).get(
		"own_cache", -1), 0, "the switch clears the own-row cache")
	_expect_equal((second.call("_test_state") as Dictionary).get(
		"rank_cache", -1), 0, "the switch clears the rank cache")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)),
		bytes_switched, "the tripped rank touches no file")
	_close_coordinator(second)
	for snap in second_ranks:
		_expect_equal((snap as Dictionary).get("state", ""),
			"unregistered",
			"a tripped rank emits no ranked state")


func _test_rank_concurrent_calls_bounded() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(209, 1, 0)),
		OK, "the journey seals")
	var stepper: RefCounted = _StepRoutingSender.new(get_tree(), sender,
		_row_body(GUEST_A, 5000, HERO_KNIGHT, 2), _rank_body(4))
	var rebound: Dictionary = _config(sender, UID_A, GUEST_A)
	rebound["sender"] = stepper.call("sender_callable")
	sender.call("queue_ok", _profile_body(UID_A, GUEST_A))
	for _index in 4:
		sender.call("queue_ok", "{}")
	coordinator.call("configure_host", rebound)
	await _settle_account(coordinator)
	coordinator.call("_test_set_now", 1090000)
	var first_box: Dictionary = {}
	var second_box: Dictionary = {}
	_refresh_into(first_box, coordinator)
	_refresh_into(second_box, coordinator)
	_expect_true(await _await_box(first_box), "the first refresh lands")
	_expect_true(await _await_box(second_box), "the second refresh lands")
	var first: Dictionary = first_box.get("result", {})
	var second: Dictionary = second_box.get("result", {})
	_expect_equal(first.get("status", ""), "ok",
		"the first concurrent refresh answers ok")
	_expect_equal(second.get("status", ""), "ok",
		"the second concurrent refresh answers ok")
	_expect_equal(first.get("score", 0), 5000,
		"the first answer carries the owned best")
	_expect_equal(second.get("score", 0), 5000,
		"the second answer carries the owned best")
	_expect_equal(first.get("hero", ""), HERO_KNIGHT,
		"the first answer carries the owned hero")
	_expect_equal(second.get("hero", ""), HERO_KNIGHT,
		"the second answer carries the owned hero")
	_expect_equal(first.get("fetched_msec", -1),
		second.get("fetched_msec", -2),
		"concurrent refreshes share one measurement")
	_expect_equal(_own_get_call_count(sender), 1,
		"two concurrent refreshes fire one own-row read")
	_expect_equal(_rank_call_count(sender), 1,
		"two concurrent refreshes fire one count query")
	var calls_before: int = (sender.get("calls") as Array).size()
	var third: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(third.get("source", ""), "cache-throttled",
		"the follow-up inside the window is labeled throttled")
	_expect_equal((sender.get("calls") as Array).size(), calls_before,
		"the throttled follow-up sends nothing")
	_close_coordinator(coordinator)


func _test_rank_waiter_cancelled_by_switch() -> void:
	_reset_all([GUEST_A, GUEST_B])
	var sender_a: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	var ranks: Array = []
	coordinator.connect("rank_changed",
		func(snap: Dictionary) -> void: ranks.append(snap))
	await _ready_account(sender_a, coordinator, UID_A, GUEST_A)
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint(210, 1, 0)),
		OK, "account A seals")
	var bytes_a: String = _read_text(Journey.account_main_path(GUEST_A))
	var stepper: RefCounted = _StepRoutingSender.new(get_tree(),
		sender_a, _row_body(GUEST_A, 5000, HERO_KNIGHT, 2),
		_rank_body(4))
	var rebound: Dictionary = _config(sender_a, UID_A, GUEST_A)
	rebound["sender"] = stepper.call("sender_callable")
	# Only the profile restore needs a queued body: routed Hall calls
	# record against the inner default and answer by URL.
	sender_a.call("queue_ok", _profile_body(UID_A, GUEST_A))
	coordinator.call("configure_host", rebound)
	await _settle_account(coordinator)
	coordinator.call("_test_set_now", 1100000)
	var owner_box: Dictionary = {}
	var waiter_box: Dictionary = {}
	_refresh_into(owner_box, coordinator)
	_refresh_into(waiter_box, coordinator)
	# Both refreshes park inside the delayed first read; the switch
	# lands on the same frame, before either reply returns.
	var sender_b: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender_b.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender_b.call("queue_ok", "{\"writeResults\":[{},{}]}")
	coordinator.call("configure_host", _config(sender_b, UID_B, GUEST_B))
	await _settle_account(coordinator)
	_expect_equal((coordinator.call("account_snapshot") as Dictionary).get(
		"uid", ""), UID_B, "account B is active after the switch")
	_expect_true(await _await_box(waiter_box),
		"the joined waiter still lands")
	_expect_true(await _await_box(owner_box), "the ticket owner lands")
	_expect_equal((waiter_box.get("result", {}) as Dictionary).get(
		"status", ""), "cancelled",
		"the retired waiter reports cancelled")
	_expect_equal((owner_box.get("result", {}) as Dictionary).get(
		"status", ""), "cancelled",
		"the retired owner reports cancelled")
	_expect_equal((coordinator.call("rank_snapshot") as Dictionary).get(
		"state", ""), "unregistered",
		"the retired pair applies no rank under B")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), bytes_a,
		"the retired pair touches no file")
	var retired_emissions: int = ranks.size()
	# And back again: A to B to A strands no ticket.
	var home: Dictionary = _config(sender_a, UID_A, GUEST_A)
	home["sender"] = stepper.call("sender_callable")
	sender_a.call("queue_ok", _profile_body(UID_A, GUEST_A))
	coordinator.call("configure_host", home)
	await _settle_account(coordinator)
	coordinator.call("_test_set_now", 1170000)
	var revived: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(revived.get("status", ""), "ok",
		"the round trip home refreshes live")
	_expect_equal(revived.get("score", 0), 5000,
		"the round trip home ranks the owned best")
	_close_coordinator(coordinator)
	for index in retired_emissions:
		_expect_equal((ranks[index] as Dictionary).get("state", ""),
			"unregistered",
			"a retired pair emits no ranked state")


func _test_rank_invalidation_keeps_newer_pair() -> void:
	_reset_all([GUEST_A])
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var coordinator: Node = _new_coordinator()
	var ranks: Array = []
	coordinator.connect("rank_changed",
		func(snap: Dictionary) -> void: ranks.append(snap))
	await _ready_account(sender, coordinator, UID_A, GUEST_A)
	var low: Dictionary = _valid_checkpoint(211, 1, 0, {
		"cycle": 1, "hero_path": HERO_DANCER, "level": 1,
		"kill_score": 10, "kills": 0, "lit_count": 0, "survived": 0.0,
	})
	_expect_equal(_expected_score(low), 10,
		"the fresh journey derives exactly 10")
	_expect_equal(Journey.write_checkpoint(low), OK,
		"the low journey seals")
	var sealed: String = _read_text(Journey.account_main_path(GUEST_A))
	var stepper: RefCounted = _StepRoutingSender.new(get_tree(), sender,
		_row_body(GUEST_A, 600, HERO_DANCER, 6), _rank_body(1))
	var gated: RefCounted = _GatedSender.new(get_tree(), stepper)
	var rebound: Dictionary = _config(sender, UID_A, GUEST_A)
	rebound["sender"] = gated.call("sender_callable")
	gated.set("gate_open", true)
	sender.call("queue_ok", _profile_body(UID_A, GUEST_A))
	coordinator.call("configure_host", rebound)
	await _settle_account(coordinator)
	coordinator.call("_test_set_now", 1110000)
	var live: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(live.get("score", 0), 600,
		"the live refresh measures the newer best")
	_expect_equal((coordinator.call("rank_snapshot") as Dictionary).get(
		"state", ""), "ready", "the snapshot publishes the newer pair")
	var frozen: int = ranks.size()
	# Past TTL and window the overlap pair must read live (a cached
	# serve would never reach the gate); the server now holds an
	# older-looking row for the delayed read, and a submit refusal
	# retires the pending pair before it can land.
	coordinator.call("_test_set_now", 1180000)
	stepper.set("_row_body", _row_body(GUEST_A, 100, HERO_KNIGHT, 2))
	stepper.set("_rank_body", _rank_body(0))
	gated.set("gate_open", false)
	var submit_box: Dictionary = {}
	var owner_box: Dictionary = {}
	var waiter_box: Dictionary = {}
	_submit_into(submit_box, coordinator)
	_refresh_into(owner_box, coordinator)
	_refresh_into(waiter_box, coordinator)
	gated.set("gate_open", true)
	_expect_true(await _await_box(submit_box),
		"the submit lands past the gate")
	_expect_true(await _await_box(waiter_box),
		"the retired waiter lands")
	_expect_true(await _await_box(owner_box),
		"the retired owner lands")
	_expect_equal((submit_box.get("result", {}) as Dictionary).get(
		"code", ""), "not-best",
		"the low submit loses to the server best")
	_expect_equal((waiter_box.get("result", {}) as Dictionary).get(
		"status", ""), "cancelled",
		"the retired waiter reports cancelled")
	_expect_equal((owner_box.get("result", {}) as Dictionary).get(
		"status", ""), "cancelled",
		"the retired owner reports cancelled, never stale ok")
	var snapshot: Dictionary = coordinator.call("rank_snapshot")
	_expect_equal(snapshot.get("state", ""), "ready",
		"the snapshot stays ready, never degrades to error")
	_expect_equal(snapshot.get("score", 0), 600,
		"the snapshot keeps the newer best, not the stale row")
	_expect_equal(snapshot.get("hero", ""), HERO_DANCER,
		"the snapshot keeps the newer hero")
	_expect_equal(ranks.size(), frozen,
		"retired results emit no rank state at all")
	_expect_equal(_read_text(Journey.account_main_path(GUEST_A)), sealed,
		"the retired pair rewrites no local journey byte")
	var reread: Dictionary = await coordinator.call("refresh_rank")
	_expect_equal(reread.get("source", ""), "live",
		"the same-clock re-read measures live past the invalidation")
	_expect_equal(reread.get("score", 0), 100,
		"the re-read publishes a fresh measurement, not a restore")
	_close_coordinator(coordinator)


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("  expected true — ", label)


func _expect_false(value: bool, label: String) -> void:
	_checked += 1
	if value:
		_failed += 1
		printerr("  expected false — ", label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		_failed += 1
		printerr("  expected ", expected, " got ", actual, " — ", label)


func _expect_not_equal(actual: Variant, expected: Variant,
		label: String) -> void:
	_checked += 1
	if actual == expected:
		_failed += 1
		printerr("  expected not ", expected, " — ", label)


## Fake sender that reconfigures the coordinator to a second account on one
## numbered call, so the test can prove the in-flight reply is dropped.
class _SwitchingSender:
	extends RefCounted
	var _coordinator: Node
	var _next_config: Dictionary
	var _inner: RefCounted
	var _arm_on_call: int
	var switched: bool = false

	func _init(coordinator: Node, next_config: Dictionary,
			inner: RefCounted, arm_on_call: int) -> void:
		_coordinator = coordinator
		_next_config = next_config
		_inner = inner
		_arm_on_call = arm_on_call

	func sender_callable() -> Callable:
		return Callable(self, "send")

	func send(method: String, url: String, headers: Dictionary,
			body: String) -> Dictionary:
		var reply: Dictionary = await _inner.call("send", method, url,
			headers, body)
		if not switched \
				and (_inner.get("calls") as Array).size() == _arm_on_call:
			switched = true
			_coordinator.call("configure_host", _next_config)
		return reply


## Fake sender that seals a second verified checkpoint during a checkpoint
## commit callback, so the test can prove the in-flight completion keeps
## the newer queued payload instead of clearing it.
class _SealingSender:
	extends RefCounted
	var _inner: RefCounted
	var _seal: Dictionary
	var seal_on_commit: bool = true
	var sealed: bool = false

	func _init(inner: RefCounted, seal: Dictionary) -> void:
		_inner = inner
		_seal = seal

	func sender_callable() -> Callable:
		return Callable(self, "send")

	func send(method: String, url: String, headers: Dictionary,
			body: String) -> Dictionary:
		var reply: Dictionary = await _inner.call("send", method, url,
			headers, body)
		if seal_on_commit and not sealed \
				and str(url).contains("documents:commit") \
				and str(body).contains("mb_checkpoints_v1"):
			sealed = true
			Journey.write_checkpoint(_seal)
		return reply


## Fake sender parked shut until the test opens the gate, so offline seals
## land deterministically before the reservation completes.
class _GatedSender:
	extends RefCounted
	var _tree: SceneTree
	var _inner: RefCounted
	var gate_open: bool = false

	func _init(tree: SceneTree, inner: RefCounted) -> void:
		_tree = tree
		_inner = inner

	func sender_callable() -> Callable:
		return Callable(self, "send")

	func send(method: String, url: String, headers: Dictionary,
			body: String) -> Dictionary:
		while not gate_open:
			await _tree.process_frame
		return await _inner.call("send", method, url, headers, body)


## Fake sender that yields one frame per call so two refreshes genuinely
## overlap, then answers Hall reads from fixed bodies by URL while the
## inner fake still records every call. Other URLs delegate to the inner
## fake, so reservation traffic flows through its queue.
class _StepRoutingSender:
	extends RefCounted
	var _tree: SceneTree
	var _inner: RefCounted
	var _row_body: String
	var _rank_body: String

	func _init(tree: SceneTree, inner: RefCounted, row_body: String,
			rank_body: String) -> void:
		_tree = tree
		_inner = inner
		_row_body = row_body
		_rank_body = rank_body

	func sender_callable() -> Callable:
		return Callable(self, "send")

	func send(method: String, url: String, headers: Dictionary,
			body: String) -> Dictionary:
		await _tree.process_frame
		var recorded: Dictionary = await _inner.call("send", method, url,
			headers, body)
		if str(url).contains("runAggregationQuery"):
			return {"transport": "ok", "code": 200, "body": _rank_body}
		if str(method) == "GET" and str(url).contains("mb_hall_v1/"):
			return {"transport": "ok", "code": 200, "body": _row_body}
		return recorded
