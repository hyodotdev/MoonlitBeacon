extends SceneTree

## Moonlit vault buy atomicity and legacy-version save-migration regression.
##
## Must run via `tools/run_regression_tests.mjs`. The runner builds a temp HOME and
## isolates it from the real `user://vault.cfg`. Below, only create files after re-checking that path.
## create files.

const VAULT_SCRIPT: Script = preload("res://scripts/gameplay/vault.gd")
const FAILING_VAULT_SCRIPT: Script = preload("res://tests/support/failing_vault.gd")
const DANCER: String = "res://resources/heroes/dancer.tres"
const KEEPER: String = "res://resources/heroes/keeper.tres"
const KNIGHT: String = "res://resources/heroes/knight.tres"
const WARDEN: String = "res://resources/heroes/warden.tres"
const HEART: String = "res://resources/boons/steady_heart.tres"
const EDGE: String = "res://resources/boons/keen_edge.tres"

var _failed: int = 0
var _checked: int = 0
var _save_absolute: String = ""
var _temp_absolute: String = ""
var _backup_absolute: String = ""
var _backup_temp_absolute: String = ""


func _init() -> void:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	if expected_root.is_empty() or not user_root.begins_with(expected_root + "/"):
		printerr("vault test aborted: user:// path is not isolated — ", user_root)
		quit(2)
		return

	_save_absolute = ProjectSettings.globalize_path("user://vault.cfg")
	_temp_absolute = ProjectSettings.globalize_path("user://vault.cfg.tmp")
	_backup_absolute = ProjectSettings.globalize_path("user://vault.cfg.bak")
	_backup_temp_absolute = ProjectSettings.globalize_path("user://vault.cfg.bak.tmp")
	_remove_save_target()

	_test_hero_visual_assets()
	_test_legacy_migration()
	_test_boon_purchase()
	_test_hero_purchase()
	_test_hero_source_grant_and_revoke()
	_test_continue_coin_grant_atomicity()
	_test_continue_txn_atomicity()
	_test_prepare_receipt_move()
	_test_lodge_progress()
	_test_verified_name_cache()
	_test_verified_name_intro_monotone()
	_test_attendance_wallet()
	_test_attendance_cross_owner_prune()
	_test_score_settlement()
	_test_versioned_primary_beats_backup()
	_test_backup_recovery()
	_test_purchase_recommendation()
	_test_save_failure_rollback()

	_remove_save_target()
	if _failed > 0:
		printerr("vault test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("vault test passed — ", _checked, " case(s) · isolated path ", user_root)
	quit(0)


func _new_vault() -> Node:
	return VAULT_SCRIPT.new() as Node


func _orphan_node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _test_hero_visual_assets() -> void:
	for path in [WARDEN, DANCER, KEEPER]:
		var hero: Hero = load(path) as Hero
		_expect_true(hero != null, "hero resource loaded " + path)
		if hero == null:
			continue
		var hero_id: String = path.get_file().get_basename()
		var custom_root: String = "res://assets/custom/actors/heroes/" + hero_id + "/"
		_expect_equal(hero.sprite_cell, Vector2i(144, 192), hero_id + " cell spec")
		_expect_equal(hero.walk_frames, 4, hero_id + " walk frames")
		_expect_equal(hero.idle_frames, 4, hero_id + " idle frames")
		_expect_true(hero.walk_sheet != null, hero_id + " walk sheet")
		_expect_true(hero.idle_sheet != null, hero_id + " idle sheet")
		_expect_true(hero.portrait != null, hero_id + " portrait")
		if hero.walk_sheet != null:
			_expect_equal(
				hero.walk_sheet.resource_path,
				custom_root + "walk.png",
				hero_id + " custom walk path")
		if hero.idle_sheet != null:
			_expect_equal(
				hero.idle_sheet.resource_path,
				custom_root + "idle.png",
				hero_id + " custom idle path")
		if hero.portrait != null:
			_expect_equal(
				hero.portrait.resource_path,
				custom_root + "portrait.png",
				hero_id + " custom portrait path")


func _test_legacy_migration() -> void:
	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value("vault", "schema_version", 2)
	legacy.set_value("vault", "shards", -17)
	legacy.set_value("vault", "hero", KEEPER)
	legacy.set_value(
		"vault",
		"opened",
		[DANCER, DANCER, KNIGHT, "res://invalid/hero.tres"])
	legacy.set_value("vault", HEART, 999)
	legacy.set_value("vault", EDGE, -4)
	_expect_error(legacy.save(_save_absolute), OK, "prepares a legacy save")

	var vault: Node = _new_vault()
	vault.load_vault()
	_expect_equal(vault.shards, 0, "negative shards clamp to 0")
	_expect_equal(vault.opened, [DANCER], "duplicate/invalid Sage paths removed")
	_expect_equal(
		vault.hero_sources.get(DANCER, []),
		[vault.HERO_SOURCE_SHARDS],
		"schema-2 heroes migrate as shard sources")
	_expect_false(vault.hero_open(KNIGHT), "old save does not shard-unlock a new paid hero")
	_expect_false(vault.hero_sources.has(KNIGHT), "forbids injecting a legacy shard source onto a new paid hero")
	_expect_equal(
		vault.rank_of(HEART),
		(load(HEART) as Boon).max_rank,
		"boon rank is clamped to max_rank")
	_expect_equal(vault.rank_of(EDGE), 0, "negative boon ranks removed")
	_expect_equal(vault.hero_path(), WARDEN, "an unopened selected hero restores to the default hero")

	legacy.set_value("vault", "shards", 77)
	legacy.set_value("vault", "hero", DANCER)
	_expect_error(legacy.save(_save_absolute), OK, "prepares a valid legacy save")
	vault.load_vault()
	_expect_equal(vault.shards, 77, "legacy positive shards kept")
	_expect_equal(vault.hero_path(), DANCER, "keeps a selected hero that was opened")
	_expect_equal(
		vault.hero_sources.get(DANCER, []),
		[vault.HERO_SOURCE_SHARDS],
		"a valid legacy-version hero also keeps the shard source")
	vault.free()


func _test_boon_purchase() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	var boon: Boon = load(HEART) as Boon
	var cost: int = boon.cost_at(1)
	vault.shards = cost + 5
	var changed_count: Array[int] = [0]
	vault.changed.connect(func() -> void: changed_count[0] += 1)

	_expect_equal(
		vault.purchase_boon(boon, HEART, 0),
		vault.PurchaseResult.OK,
		"boon buy succeeds")
	_expect_equal(vault.rank_of(HEART), 1, "boon buy rank applied")
	_expect_equal(vault.shards, 5, "boon buy deducts the price once")
	_expect_equal(changed_count[0], 1, "boon buy changed signal once")
	_expect_equal(
		vault.purchase_boon(boon, HEART, 0),
		vault.PurchaseResult.STALE,
		"a fast duplicate tap is rejected as a previous-step request")
	_expect_equal(vault.rank_of(HEART), 1, "rank unchanged after a duplicate tap")
	_expect_equal(vault.shards, 5, "shards unchanged after a duplicate tap")
	_expect_equal(
		vault.purchase_boon(boon, "res://resources/boons/not_real.tres", 1),
		vault.PurchaseResult.INVALID,
		"rejects a boon outside the catalog")

	var saved: ConfigFile = ConfigFile.new()
	_expect_error(saved.load(_save_absolute), OK, "purchase save file created")
	_expect_equal(
		int(saved.get_value("vault", "schema_version", 0)),
		vault.SCHEMA_VERSION,
		"save-schema version recorded")
	_expect_false(FileAccess.file_exists(_temp_absolute), "temp save file removed after success")
	var restored: Node = _new_vault()
	restored.load_vault()
	_expect_equal(restored.rank_of(HEART), 1, "purchase rank kept after a rerun")
	_expect_equal(restored.shards, 5, "purchase balance kept after a rerun")
	restored.free()
	vault.free()


## A paid continue journals its debit and exact revive seal in one atomic
## save: the balance and the journal land together, a retry of the same
## attempt charges nothing more, a failed save changes neither, and a new
## journey clears the moot journal (restoring it when its own save fails).
func _test_continue_txn_atomicity() -> void:
	var orphans_before: int = _orphan_node_count()
	_remove_save_target()
	var vault: Node = _new_vault()
	vault.load_vault()
	vault.continue_coins = 2
	_expect_true(vault.begin_continue_txn(7, 3, "{\"seal\":true}"),
		"begin journals the debit and its seal")
	_expect_equal(vault.continue_coins, 1, "begin debits exactly one coin")
	_expect_equal(int(vault.continue_txn.get("checkpoint_id", 0)), 3,
		"begin names the revive seal")
	vault.continue_coins = 0
	_expect_true(vault.begin_continue_txn(7, 3, "{\"seal\":true}"),
		"a retry reuses the journaled attempt")
	_expect_equal(vault.continue_coins, 0,
		"a retry charges nothing more")
	_expect_false(vault.begin_continue_txn(7, 4, "{\"seal\":true}"),
		"a different attempt needs its own coin")
	_expect_false(vault.begin_continue_txn(0, 4, "{\"seal\":true}"),
		"a bad journey id is refused")
	_expect_false(vault.begin_continue_txn(7, -1, "{\"seal\":true}"),
		"a bad seal id is refused")
	_expect_false(vault.begin_continue_txn(7, 4, ""),
		"an empty seal is refused")

	# The debit and the journal persist across a reload together.
	_remove_save_target()
	var first: Node = _new_vault()
	first.load_vault()
	first.continue_coins = 2
	_expect_true(first.begin_continue_txn("rABC", 5, "{\"seal\":5}"),
		"a string journey begins")
	var second: Node = _new_vault()
	second.load_vault()
	_expect_equal(second.continue_coins, 1, "a reload keeps the debit")
	_expect_equal(str(second.continue_txn.get("journey_id", "")), "rABC",
		"a reload keeps the journal journey")
	_expect_equal(int(second.continue_txn.get("checkpoint_id", 0)), 5,
		"a reload keeps the journal seal id")
	_expect_equal(str(second.continue_txn.get("seal", "")), "{\"seal\":5}",
		"a reload keeps the journal seal")
	_expect_true(second.ack_continue_txn(), "ack clears the journal")
	_expect_true((second.continue_txn as Dictionary).is_empty(),
		"the journal stays cleared in memory")
	var third: Node = _new_vault()
	third.load_vault()
	_expect_true((third.continue_txn as Dictionary).is_empty(),
		"a reload keeps the ack")
	_expect_true(third.ack_continue_txn(), "acking nothing acks true")

	# A malformed journal drops on load instead of forging a revive.
	for bad_txn in [{"journey_id": "", "checkpoint_id": 5, "seal": "x"},
			{"journey_id": 7, "checkpoint_id": "5", "seal": "x"},
			{"journey_id": 7, "checkpoint_id": 5, "seal": 9}]:
		_remove_save_target()
		var seed: ConfigFile = ConfigFile.new()
		seed.set_value("vault", "schema_version", 5)
		seed.set_value("vault", "continue_txn", bad_txn)
		seed.save(_save_absolute)
		var loaded: Node = _new_vault()
		loaded.load_vault()
		_expect_true((loaded.continue_txn as Dictionary).is_empty(),
			"a malformed journal drops on load: %s" % str(bad_txn))
		loaded.free()

	# A failing save reverts the debit and the journal together, and a
	# failing ack keeps the journal for the next recovery.
	_remove_save_target()
	var failing: Node = FAILING_VAULT_SCRIPT.new() as Node
	failing.load_vault()
	_expect_false(failing.begin_continue_txn(9, 1, "{\"s\":1}"),
		"begin fails when the save fails")
	_expect_equal(failing.continue_coins, 2,
		"a failed begin keeps the balance")
	_expect_true((failing.continue_txn as Dictionary).is_empty(),
		"a failed begin journals nothing")
	failing.continue_txn = {
		"journey_id": 9, "checkpoint_id": 1, "seal": "{\"s\":1}"}
	_expect_false(failing.ack_continue_txn(),
		"ack fails when the save fails")
	_expect_false((failing.continue_txn as Dictionary).is_empty(),
		"a failed ack keeps the journal")

	# A new journey clears the moot journal — unless its own save fails,
	# which restores it like the sequence.
	_remove_save_target()
	var fresh: Node = _new_vault()
	fresh.load_vault()
	fresh.continue_coins = 2
	_expect_true(fresh.begin_continue_txn(11, 2, "{\"s\":2}"),
		"the old journey journals first")
	_expect_true(fresh.begin_journey() is int, "the new journey issues")
	_expect_true((fresh.continue_txn as Dictionary).is_empty(),
		"a new journey clears the journal")
	var failing_fresh: Node = FAILING_VAULT_SCRIPT.new() as Node
	failing_fresh.load_vault()
	failing_fresh.continue_txn = {
		"journey_id": 11, "checkpoint_id": 2, "seal": "{\"s\":2}"}
	_expect_true(failing_fresh.begin_journey() is String,
		"a failed issue falls back without saving")
	_expect_false((failing_fresh.continue_txn as Dictionary).is_empty(),
		"a failed issue restores the journal")
	vault.free()
	first.free()
	second.free()
	third.free()
	failing.free()
	fresh.free()
	failing_fresh.free()
	_expect_equal(_orphan_node_count(), orphans_before,
		"continue txn frees every temporary vault")


## Moving a receipt ahead of its slot's files reports one honest outcome:
## `ready` (nothing pending, or the rekey landed), `kept` (the target
## holds its own receipt or journey — the source stays), or `failed` (the
## rekey could not save — the caller must not move files).
func _test_prepare_receipt_move() -> void:
	var orphans_before: int = _orphan_node_count()
	_remove_save_target()
	var vault: Node = _new_vault()
	vault.load_vault()
	_expect_equal(str(vault.call("prepare_receipt_move", "", "MB-x")),
		"ready", "prepare: nothing pending is ready")
	vault.continue_coins = 2
	_expect_true(vault.begin_continue_txn(7, 3, "{\"seal\":true}"),
		"prepare: the debit journals")
	# Instance vaults journal under the global legacy scope here.
	_expect_equal(str(vault.call("prepare_receipt_move", "", "MB-x")),
		"ready", "prepare: the rekey onto an empty slot lands")
	_expect_equal(str(vault.continue_txn.get("owner", "")), "MB-x",
		"prepare: the entry now owns the target")
	_expect_equal(vault.continue_coins, 1,
		"prepare: the rekey charges nothing")
	var reloaded: Node = _new_vault()
	reloaded.load_vault()
	_expect_equal(str(reloaded.continue_txn.get("owner", "")), "MB-x",
		"prepare: the rekey survives reload")

	# A target holding its own receipt keeps both entries in place.
	reloaded.continue_txn_parked = {"MB-x": {
		"owner": "MB-x", "journey_id": 7, "checkpoint_id": 3,
		"seal": "{\"seal\":true}"}}
	reloaded.continue_txn = {"owner": "", "journey_id": 9,
		"checkpoint_id": 1, "seal": "{\"s\":1}"}
	_expect_equal(str(reloaded.call("prepare_receipt_move", "", "MB-x")),
		"kept", "prepare: an owned target keeps the source")
	_expect_equal(str(reloaded.continue_txn.get("owner", "")), "",
		"prepare: the kept entry stays put")

	# A target holding a journey but no receipt is kept too: settling
	# against a foreign journey would stale-clear the receipt.
	reloaded.continue_txn_parked = {}
	var occupant: String = ProjectSettings.globalize_path(
		Journey.account_main_path("MB-y"))
	var writer: FileAccess = FileAccess.open(
		Journey.account_main_path("MB-y"), FileAccess.WRITE)
	writer.store_string("{\"slot\":true}")
	writer.close()
	_expect_equal(str(reloaded.call("prepare_receipt_move", "", "MB-y")),
		"kept", "prepare: a journey-occupied target keeps the source")
	DirAccess.remove_absolute(occupant)
	_expect_equal(str(reloaded.call("prepare_receipt_move", "", "MB-y")),
		"ready", "prepare: the freed slot adopts afterwards")

	# A target holding its own receipt or journey is occupied even when
	# the source carries no receipt: importing unrelated source bytes
	# over it would stale-clear the target's paid recovery.
	reloaded.continue_txn = {}
	reloaded.continue_txn_parked = {"MB-x": {
		"owner": "MB-x", "journey_id": 7, "checkpoint_id": 3,
		"seal": "{\"seal\":true}"}}
	_expect_equal(str(reloaded.call(
		"prepare_receipt_move", "MB-s", "MB-x")), "kept",
		"prepare: a receipt-held target keeps a receiptless source")
	reloaded.continue_txn_parked = {}
	writer = FileAccess.open(
		Journey.account_main_path("MB-y"), FileAccess.WRITE)
	writer.store_string("{\"slot\":true}")
	writer.close()
	_expect_equal(str(reloaded.call(
		"prepare_receipt_move", "MB-s", "MB-y")), "kept",
		"prepare: a journey-held target keeps a receiptless source")
	DirAccess.remove_absolute(occupant)
	_expect_equal(str(reloaded.call(
		"prepare_receipt_move", "MB-s", "MB-y")), "ready",
		"prepare: the freed target takes a receiptless source")

	# A rekey that cannot save fails loudly and restores the entry.
	_remove_save_target()
	var failing: Node = FAILING_VAULT_SCRIPT.new() as Node
	failing.load_vault()
	failing.continue_txn = {"owner": "", "journey_id": 9,
		"checkpoint_id": 1, "seal": "{\"s\":1}"}
	_expect_equal(str(failing.call("prepare_receipt_move", "", "MB-z")),
		"failed", "prepare: an unsavable rekey fails")
	_expect_equal(str(failing.continue_txn.get("owner", "")), "",
		"prepare: the failed rekey restores the owner")
	vault.free()
	reloaded.free()
	failing.free()
	_expect_equal(_orphan_node_count(), orphans_before,
		"prepare frees every temporary vault")


func _test_lodge_progress() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	vault.load_vault()
	_expect_equal(vault.call("lodge_progress_for_account", "MB-1"),
		{"move": false, "dash": false},
		"lodge: gates start unlearned")
	_expect_false(bool(vault.call("mark_lodge_gate", "MB-1", "swim")),
		"lodge: unknown gates refuse without a save")
	_expect_false(bool(vault.call("mark_lodge_gate", "", "move")),
		"lodge: an empty scope refuses")
	_expect_true(bool(vault.call("mark_lodge_gate", "MB-1", "move")),
		"lodge: the move gate marks")
	_expect_true(bool(vault.call("mark_lodge_gate", "MB-1", "move")),
		"lodge: re-practice stays true")
	_expect_equal(vault.call("lodge_progress_for_account", "MB-1"),
		{"move": true, "dash": false},
		"lodge: the practiced gate reads back")
	var reloaded: Node = _new_vault()
	reloaded.load_vault()
	_expect_equal(reloaded.call("lodge_progress_for_account", "MB-1"),
		{"move": true, "dash": false},
		"lodge: the gate survives reload")
	_expect_true(bool(vault.call("mark_lodge_gate", "MB-1", "dash")),
		"lodge: the dash gate marks")
	for index in 10:
		_expect_true(bool(vault.call("mark_lodge_gate",
			"MB-g%d" % index, "move")),
			"lodge: scope %d marks" % index)
	var scoped: Dictionary = vault.get("lodge_progress") as Dictionary
	_expect_equal(scoped.size(), 8, "lodge: the scopes stay bounded")
	_expect_false(scoped.has("MB-1"), "lodge: the oldest scope evicts")
	_expect_false(scoped.has("MB-g0"), "lodge: eviction runs oldest-first")
	_expect_true(scoped.has("MB-g2"), "lodge: newer scopes survive")
	_expect_true(scoped.has("MB-g9"), "lodge: the newest scope survives")
	_expect_true(bool(vault.call("clear_lodge_for_owner", "MB-g9")),
		"lodge: one scope clears")
	_expect_equal(vault.call("lodge_progress_for_account", "MB-g9"),
		{"move": false, "dash": false},
		"lodge: the cleared scope reads unlearned")
	_expect_true((vault.get("lodge_progress") as Dictionary).has("MB-g8"),
		"lodge: the clear keeps every other scope")
	vault.set("lodge_progress", {"MB-x": "garbage", "": {"move": true}})
	vault.save_vault()
	var scrubbed: Node = _new_vault()
	scrubbed.load_vault()
	_expect_false((scrubbed.get("lodge_progress") as Dictionary).has(
		"MB-x"), "lodge: a malformed entry drops on load")
	vault.free()
	reloaded.free()
	scrubbed.free()
	_remove_save_target()


func _test_verified_name_cache() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	vault.load_vault()
	_expect_true((vault.call("verified_name_for_account", "MB-x")
		as Dictionary).is_empty(), "cache: unknown account reads empty")
	_expect_true(bool(vault.call("cache_verified_name", "MB-x",
		"Luna", "luna", false)), "cache: the verified handle stores")
	_expect_equal(str((vault.call("verified_name_for_account", "MB-x")
		as Dictionary).get("display", "")), "Luna",
		"cache: the owning scope reads its handle")
	_expect_true((vault.call("verified_name_for_account", "MB-y")
		as Dictionary).is_empty(),
		"cache: separate accounts never share")
	_expect_false(bool(vault.call("cache_verified_name", "MB-y",
		"Luna", "bob", false)),
		"cache: a mismatched key refuses")
	_expect_false(bool(vault.call("cache_verified_name", "MB-y",
		"x", "x", false)), "cache: a short display refuses")
	_expect_true(bool(vault.call("cache_verified_name", "MB-x",
		"Luna", "luna", true)),
		"cache: the intro flip re-stores")
	_expect_true(bool((vault.call("verified_name_for_account", "MB-x")
		as Dictionary).get("intro_complete", false)),
		"cache: the intro flip reads back")
	for index in 10:
		_expect_true(bool(vault.call("cache_verified_name",
			"MB-fill-%d" % index, "Name%d" % index,
			"name%d" % index, false)),
			"cache: fill entry stores")
	_expect_true(int((vault.get("verified_names") as Dictionary).size())
		<= 8, "cache: the bound holds")
	_expect_true((vault.call("verified_name_for_account", "MB-x")
		as Dictionary).is_empty(),
		"cache: the oldest entry evicts first")
	var reloaded: Node = _new_vault()
	reloaded.load_vault()
	_expect_equal(str((reloaded.call("verified_name_for_account",
		"MB-fill-9") as Dictionary).get("display", "")), "Name9",
		"cache: handles survive reload")
	_expect_true(bool(reloaded.call(
		"clear_verified_name_for_owner", "MB-fill-9")),
		"cache: the owner clears")
	_expect_true((reloaded.call("verified_name_for_account",
		"MB-fill-9") as Dictionary).is_empty(),
		"cache: the cleared owner reads empty")
	_expect_equal(str((reloaded.call("verified_name_for_account",
		"MB-fill-8") as Dictionary).get("display", "")), "Name8",
		"cache: clearing drops only the deleted scope")
	reloaded.free()
	vault.free()


func _test_verified_name_intro_monotone() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	vault.load_vault()
	_expect_true(bool(vault.call("cache_verified_name", "MB-m",
		"Luna", "luna", true)), "monotone: the completion stores")
	_expect_true(bool(vault.call("cache_verified_name", "MB-m",
		"Luna", "luna", false)),
		"monotone: a late incomplete same-name write still lands")
	_expect_true(bool((vault.call("verified_name_for_account", "MB-m")
		as Dictionary).get("intro_complete", false)),
		"monotone: the stored completion never regresses")
	_expect_true(bool(vault.call("cache_verified_name", "MB-n",
		"Luna", "luna", false)),
		"monotone: an unrelated account starts incomplete")
	_expect_false(bool((vault.call("verified_name_for_account", "MB-n")
		as Dictionary).get("intro_complete", true)),
		"monotone: the new scope reads incomplete")
	var reloaded: Node = _new_vault()
	reloaded.load_vault()
	_expect_true(bool((reloaded.call("verified_name_for_account", "MB-m")
		as Dictionary).get("intro_complete", false)),
		"monotone: the completion survives reload")
	reloaded.free()
	vault.free()


func _test_attendance_wallet() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	vault.load_vault()
	var install: String = str(vault.call("ensure_install_id"))
	_expect_equal(install.length(), 32, "attend: the install id is 32 hex")
	_expect_equal(str(vault.call("ensure_install_id")), install,
		"attend: the install id is stable")
	var before: int = int(vault.continue_coins)
	var first: Dictionary = vault.call("grant_attendance_coins",
		"MB-m", 1000000, install)
	_expect_equal(str(first.get("status", "")), "ok",
		"attend: the first grant lands")
	_expect_true(bool(first.get("granted", false)),
		"attend: the first grant is new")
	_expect_equal(int(vault.continue_coins), before + 2,
		"attend: the grant adds exactly two")
	var key: String = str(first.get("key", ""))
	_expect_true(key.begins_with("attendance:MB-m:1000000:"),
		"attend: the receipt key derives from row plus install")
	var again: Dictionary = vault.call("grant_attendance_coins",
		"MB-m", 1000000, install)
	_expect_true(bool(again.get("duplicate", false)),
		"attend: the same key grants idempotently")
	_expect_equal(int(vault.continue_coins), before + 2,
		"attend: the duplicate adds nothing")
	var older: Dictionary = vault.call("grant_attendance_coins",
		"MB-m", 999000, install)
	_expect_true(bool(older.get("duplicate", false)),
		"attend: an older key hits the watermark")
	_expect_equal(int(vault.continue_coins), before + 2,
		"attend: the watermark adds nothing")
	var sibling: Dictionary = vault.call("grant_attendance_coins",
		"MB-n", 1000000, install)
	_expect_true(bool(sibling.get("granted", false)),
		"attend: another account grants on its own mark")
	_expect_true(bool(vault.call("cache_attendance_next", "MB-m",
		"2026-10-08T02:00:00Z", 3600, 1000000)),
		"attend: the deadline caches")
	_expect_equal(str((vault.call("attendance_next_for_account", "MB-m")
		as Dictionary).get("next_utc", "")), "2026-10-08T02:00:00Z",
		"attend: the cached deadline reads back")
	var reloaded: Node = _new_vault()
	reloaded.load_vault()
	_expect_equal(str(reloaded.call("ensure_install_id")), install,
		"attend: the install id survives reload")
	_expect_equal(int(reloaded.continue_coins), before + 4,
		"attend: the balances survive reload")
	_expect_true((reloaded.get("continue_coin_grants")
		as Dictionary).has(key),
		"attend: the receipt survives with its coins")
	_expect_true(bool((reloaded.call("grant_attendance_coins",
		"MB-m", 999000, install) as Dictionary).get("duplicate", false)),
		"attend: the watermark survives reload")
	reloaded.free()

	# Bounded replay: purchases never evict, pruned receipts never regrant.
	_expect_true(bool(vault.call("grant_continue_coins", 5,
		"store-order-1")), "attend: the purchased key lands")
	for index in 12:
		var stamp: int = 2000000 + index * 43200
		var step: Dictionary = vault.call("grant_attendance_coins",
			"MB-m", stamp, install)
		_expect_true(bool(step.get("granted", false)),
			"attend: period %d grants" % index)
	var grants: Dictionary = vault.get(
		"continue_coin_grants") as Dictionary
	_expect_true(grants.has("store-order-1"),
		"attend: pruning never evicts a purchase")
	_expect_equal(int(grants["store-order-1"]), 5,
		"attend: the purchase keeps its count")
	var kept: int = 0
	for grant_key in grants:
		if str(grant_key).begins_with("attendance:"):
			kept += 1
	_expect_equal(kept, 8, "attend: only the newest eight receipts stay")
	_expect_true(not grants.has(key),
		"attend: the oldest receipt prunes away")
	var reprised: Dictionary = vault.call("grant_attendance_coins",
		"MB-m", 1000000, install)
	_expect_true(bool(reprised.get("duplicate", false)),
		"attend: the pruned receipt never grants again")

	# Failed saves grant nothing and keep nothing half-written.
	_remove_save_target()
	var failing: Node = FAILING_VAULT_SCRIPT.new() as Node
	failing.load_vault()
	_expect_equal(str(failing.call("ensure_install_id")), "",
		"attend: an undurable install stays hidden")
	var failed_before: int = int(failing.continue_coins)
	var denied: Dictionary = failing.call("grant_attendance_coins",
		"MB-m", 3000000, install)
	_expect_equal(str(denied.get("status", "")), "failure",
		"attend: an unsavable grant fails")
	_expect_equal(int(failing.continue_coins), failed_before,
		"attend: the failed grant keeps the balance")
	_expect_true((failing.get("continue_coin_grants")
		as Dictionary).is_empty(),
		"attend: the failed grant keeps no key")
	failing.free()

	# Deletion clears one scope's marks and deadline, never its receipts.
	_expect_true(bool(vault.call("clear_attendance_for_owner", "MB-m")),
		"attend: the owner clears")
	_expect_true((vault.get("attendance_marks") as Dictionary).has(
		"MB-n"), "attend: the sibling mark survives")
	_expect_true((vault.call("attendance_next_for_account", "MB-m")
		as Dictionary).is_empty(),
		"attend: the cleared deadline reads empty")
	vault.free()


## Ten owners grant one minute apart, then the vault reloads: the first
## owner's identical old receipt must never grant again even though its
## key and mark both pruned, while a genuine new account, a new period,
## and a same-second fresh tie still grant. The purchased receipt stays.
func _test_attendance_cross_owner_prune() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	vault.load_vault()
	var install: String = str(vault.call("ensure_install_id"))
	_expect_true(bool(vault.call("grant_continue_coins", 5,
		"store-order-9")), "attend-x: the purchased key lands")
	var before: int = int(vault.continue_coins)
	var base: int = 1791000000
	for index in 10:
		var owner: String = "MB-x%d" % index
		var step: Dictionary = vault.call("grant_attendance_coins",
			owner, base + index * 60, install)
		_expect_true(bool(step.get("granted", false)),
			"attend-x: owner %d grants" % index)
	_expect_equal(int(vault.continue_coins), before + 20,
		"attend-x: ten owners add twenty")
	var reloaded: Node = _new_vault()
	reloaded.load_vault()
	_expect_equal(int(reloaded.continue_coins), before + 20,
		"attend-x: the balances survive reload")
	_expect_equal(int((reloaded.get("continue_coin_grants")
		as Dictionary).get("store-order-9", 0)), 5,
		"attend-x: the purchase survives reload")
	var replay: Dictionary = reloaded.call("grant_attendance_coins",
		"MB-x0", base, install)
	_expect_equal(str(replay.get("status", "")), "failure",
		"attend-x: the evicted receipt never grants again")
	_expect_equal(str(replay.get("code", "")),
		"attendance-replay-ambiguous",
		"attend-x: the refusal names the eviction")
	_expect_equal(int(reloaded.continue_coins), before + 20,
		"attend-x: the replay adds nothing")
	var fresh: Dictionary = reloaded.call("grant_attendance_coins",
		"MB-new", base + 600, install)
	_expect_true(bool(fresh.get("granted", false)),
		"attend-x: a genuine new account grants")
	var period: Dictionary = reloaded.call("grant_attendance_coins",
		"MB-x9", base + 540 + 43200, install)
	_expect_true(bool(period.get("granted", false)),
		"attend-x: a genuine new period grants")
	# A blocked save rolls the eviction back with the balance and keys.
	DirAccess.make_dir_recursive_absolute(_temp_absolute)
	var blocked: Dictionary = vault.call("grant_attendance_coins",
		"MB-blocked", base + 600, install)
	DirAccess.remove_absolute(_temp_absolute)
	_expect_equal(str(blocked.get("status", "")), "failure",
		"attend-x: the blocked grant fails")
	_expect_equal(int(vault.continue_coins), before + 20,
		"attend-x: the blocked grant keeps the balance")
	_expect_equal(int(vault.get("attendance_floor")), base + 60,
		"attend-x: the failed eviction leaves the floor")
	var strict_tie: Dictionary = reloaded.call(
		"grant_attendance_coins", "MB-tie", base, install, false)
	_expect_equal(str(strict_tie.get("status", "")), "failure",
		"attend-x: an uncertain same-second tie fails closed")
	_expect_equal(int(reloaded.continue_coins), before + 24,
		"attend-x: only the genuine grants land")
	var tie: Dictionary = reloaded.call(
		"grant_attendance_coins", "MB-tie", base, install, true)
	_expect_true(bool(tie.get("granted", false)),
		"attend-x: a fresh same-second tie grants")
	_expect_equal(int(reloaded.continue_coins), before + 26,
		"attend-x: the fresh tie adds two")
	var tie_again: Dictionary = reloaded.call(
		"grant_attendance_coins", "MB-tie", base, install, true)
	_expect_true(bool(tie_again.get("duplicate", false)),
		"attend-x: the fresh tie stays idempotent")
	_expect_true(bool(reloaded.call("attendance_receipt_applied",
		"MB-x9", base + 540 + 43200, install)),
		"attend-x: the applied receipt reads applied")
	_expect_false(bool(reloaded.call("attendance_receipt_applied",
		"MB-x0", base, install)),
		"attend-x: the evicted receipt reads unapplied")
	_expect_false(bool(reloaded.call("attendance_receipt_applied",
		"MB-ghost", base, install)),
		"attend-x: the unknown receipt reads unapplied")
	reloaded.free()
	vault.free()
func _test_score_settlement() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	var changed_count: Array[int] = [0]
	vault.changed.connect(func() -> void: changed_count[0] += 1)

	var first_result: Dictionary = vault.settle_run_score(6180, 0)
	_expect_equal(
		int(first_result.get("status", -1)),
		vault.RunSettlementStatus.APPLIED,
		"cumulative-score settlement success status")
	var first_award: int = int(first_result.get("awarded", 0))
	_expect_equal(first_award, 12, "goal-shard settlement of cumulative score")
	_expect_equal(vault.shards, 12, "first settlement applied to the shard balance")
	_expect_equal(changed_count[0], 1, "first settlement changed signal once")

	var second_result: Dictionary = vault.settle_run_score(24600, first_award)
	_expect_equal(
		int(second_result.get("status", -1)),
		vault.RunSettlementStatus.APPLIED,
		"continued-run delta settlement success status")
	var second_award: int = int(second_result.get("awarded", 0))
	_expect_equal(second_award, 12, "a continued run settles only the increased goal delta")
	_expect_equal(vault.shards, 24, "second settlement accumulates only the delta")
	_expect_equal(changed_count[0], 2, "changed signal only on an extra grant")

	var duplicate_result: Dictionary = vault.settle_run_score(
		24600, first_award + second_award)
	_expect_equal(
		int(duplicate_result.get("status", -1)),
		vault.RunSettlementStatus.NO_CHANGE,
		"a normal extra grant of 0 is distinct from a save failure")
	_expect_equal(
		int(duplicate_result.get("awarded", -1)),
		0,
		"settling the same cumulative score twice grants nothing")
	_expect_equal(vault.shards, 24, "no duplicate shards after re-settlement")
	_expect_equal(changed_count[0], 2, "re-settlement emits no changed signal")

	var restored: Node = _new_vault()
	restored.load_vault()
	_expect_equal(restored.shards, 24, "cumulative-settlement balance kept after a rerun")
	restored.free()
	vault.free()

	_remove_save_target()
	var minimum_vault: Node = _new_vault()
	var minimum_result: Dictionary = minimum_vault.settle_run_score(-100, 0)
	_expect_equal(
		int(minimum_result.get("status", -1)),
		minimum_vault.RunSettlementStatus.APPLIED,
		"negative-score minimum-reward settlement success status")
	_expect_equal(
		int(minimum_result.get("awarded", 0)),
		1,
		"even a negative score settles at least 1 shard the first time")
	_expect_equal(minimum_vault.shards, 1, "minimum reward applied to the balance")
	var minimum_duplicate: Dictionary = minimum_vault.settle_run_score(0, 1)
	_expect_equal(
		int(minimum_duplicate.get("status", -1)),
		minimum_vault.RunSettlementStatus.NO_CHANGE,
		"even the minimum reward grants nothing if it was already settled")
	_expect_equal(int(minimum_duplicate.get("awarded", -1)), 0, "no duplicate minimum reward")
	_expect_equal(
		minimum_vault.award(0),
		1,
		"existing award keeps minimum-reward compatibility")
	_expect_equal(minimum_vault.shards, 2, "existing award is granted as an independent run")
	minimum_vault.free()


func _test_hero_purchase() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	var dancer: Hero = load(DANCER) as Hero
	vault.shards = dancer.unlock_cost + 8
	_expect_equal(
		vault.purchase_hero(DANCER),
		vault.PurchaseResult.INVALID,
		"rejects buying a paid hero with shards")
	_expect_equal(vault.shards, dancer.unlock_cost + 8, "shards unchanged after rejecting a paid hero")
	_expect_false(vault.choose_hero(DANCER), "rejects selecting a locked hero")
	_expect_true(
		vault.purchase_options().all(func(option: Dictionary) -> bool:
			return str(option.get("path", "")) != DANCER),
		"paid heroes are excluded from shard goals")
	var knight_only: Array[String] = [KNIGHT]
	_expect_false(
		vault.grant_heroes(knight_only, vault.HERO_SOURCE_SHARDS),
		"1.0.1 new heroes also reject injected shard sources")
	_expect_false(vault.hero_open(KNIGHT), "rejected shard source does not unlock a new hero")

	var dancer_only: Array[String] = [DANCER]
	_expect_true(
		vault.grant_heroes(dancer_only, vault.HERO_SOURCE_SHARDS),
		"grants grandfather to an existing shard buyer")
	_expect_equal(
		vault.hero_sources.get(DANCER, []),
		[vault.HERO_SOURCE_SHARDS],
		"records grandfather shard source")
	_expect_equal(
		vault.purchase_hero(DANCER),
		vault.PurchaseResult.OWNED,
		"rejects rebuying a grandfathered hero")
	_expect_true(vault.choose_hero(DANCER), "selecting Sage succeeds")

	var restored: Node = _new_vault()
	restored.load_vault()
	_expect_true(restored.hero_open(DANCER), "Sage kept after a rerun")
	_expect_equal(restored.hero_path(), DANCER, "selected hero kept after a rerun")
	_expect_equal(restored.shards, dancer.unlock_cost + 8, "shard balance kept after grandfather")
	_expect_equal(
		restored.hero_sources.get(DANCER, []),
		[restored.HERO_SOURCE_SHARDS],
		"shard source kept after a rerun")
	restored.free()
	vault.free()


func _test_hero_source_grant_and_revoke() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	var dancer_only: Array[String] = [DANCER]
	_expect_equal(
		vault.grant_heroes(dancer_only, vault.HERO_SOURCE_SHARDS),
		true,
		"prepares grandfather shard source before IAP grant")

	var bundle: Array[String] = [DANCER, KEEPER]
	var source: String = vault.HERO_SOURCE_IAP_BUNDLE
	var changed_count: Array[int] = [0]
	vault.changed.connect(func() -> void: changed_count[0] += 1)
	_expect_true(vault.grant_heroes(bundle, source), "atomic hero-bundle grant succeeds")
	_expect_true(vault.hero_open(DANCER), "Dancing Star unlocked after the bundle grant")
	_expect_true(vault.hero_open(KEEPER), "Lantern Keeper unlocked after the bundle grant")
	_expect_equal(
		vault.hero_sources.get(DANCER, []),
		[vault.HERO_SOURCE_SHARDS, source],
		"adds an IAP source onto an existing shard source")
	_expect_equal(
		vault.hero_sources.get(KEEPER, []),
		[source],
		"records an IAP source on the new hero")
	_expect_equal(changed_count[0], 1, "grants two heroes in one changed signal")

	var saved: ConfigFile = ConfigFile.new()
	_expect_error(saved.load(_save_absolute), OK, "hero-bundle save file created")
	_expect_equal(
		int(saved.get_value("vault", "schema_version", 0)),
		vault.SCHEMA_VERSION,
		"hero-source save is the current schema")
	var saved_sources: Dictionary = saved.get_value("vault", "hero_sources", {})
	_expect_equal(
		saved_sources.get(DANCER, []),
		[vault.HERO_SOURCE_SHARDS, source],
		"same save includes the Dancing Star source")
	_expect_equal(
		saved_sources.get(KEEPER, []),
		[source],
		"same save includes the Lantern Keeper source")

	var granted_bytes: String = FileAccess.get_file_as_string(_save_absolute)
	_expect_true(vault.grant_heroes(bundle, source), "re-granting the same hero bundle succeeds")
	_expect_equal(changed_count[0], 1, "a duplicate bundle grant emits no changed signal")
	_expect_equal(
		FileAccess.get_file_as_string(_save_absolute),
		granted_bytes,
		"a duplicate bundle grant leaves the save file unchanged")

	var restored: Node = _new_vault()
	restored.load_vault()
	_expect_equal(
		restored.hero_sources.get(DANCER, []),
		[restored.HERO_SOURCE_SHARDS, source],
		"multiple sources kept after restore")
	_expect_equal(
		restored.hero_sources.get(KEEPER, []),
		[source],
		"IAP-only source kept after restore")
	restored.free()

	_expect_true(vault.revoke_heroes(bundle, source), "IAP hero-source revoke succeeds")
	_expect_true(vault.hero_open(DANCER), "a hero with a shard source stays unlocked")
	_expect_false(vault.hero_open(KEEPER), "IAP-only hero restores to locked")
	_expect_equal(
		vault.hero_sources.get(DANCER, []),
		[vault.HERO_SOURCE_SHARDS],
		"shard source survives after IAP revoke")
	_expect_false(vault.hero_sources.has(KEEPER), "IAP-only source is fully removed")
	_expect_equal(changed_count[0], 2, "source revoke is also one changed signal")
	vault.free()


func _test_continue_coin_grant_atomicity() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	vault.load_vault()
	var initial_coins: int = vault.continue_coins
	var changed_count: Array[int] = [0]
	vault.changed.connect(func() -> void: changed_count[0] += 1)

	_expect_false(vault.grant_continue_coins(0, "coin-zero"), "rejects a 0 grant")
	_expect_false(vault.grant_continue_coins(11, "coin-too-many"), "rejects an over-grant")
	_expect_false(vault.grant_continue_coins(5, ""), "rejects a grant with no transaction key")
	_expect_true(vault.grant_continue_coins(5, "coin-transaction-5"), "grants 5 coins")
	_expect_equal(vault.continue_coins, initial_coins + 5, "coin balance increased")
	_expect_equal(
		int(vault.continue_coin_grants.get("coin-transaction-5", 0)),
		5,
		"transaction quantity is recorded in the same save as the balance")
	var granted_bytes: String = FileAccess.get_file_as_string(_save_absolute)
	_expect_true(
		vault.grant_continue_coins(5, "coin-transaction-5"),
		"retry with the same transaction key and quantity succeeds")
	_expect_equal(vault.continue_coins, initial_coins + 5, "same transaction is not granted twice")
	_expect_equal(changed_count[0], 1, "a duplicate transaction emits no changed signal")
	_expect_equal(
		FileAccess.get_file_as_string(_save_absolute),
		granted_bytes,
		"a duplicate transaction leaves the save file unchanged")
	_expect_false(
		vault.grant_continue_coins(10, "coin-transaction-5"),
		"rejects a different quantity on the same transaction key")

	var restored: Node = _new_vault()
	restored.load_vault()
	_expect_equal(restored.continue_coins, initial_coins + 5, "coins kept after a rerun")
	_expect_true(
		restored.grant_continue_coins(5, "coin-transaction-5"),
		"retrying the same transaction succeeds after a rerun")
	_expect_equal(
		restored.continue_coins,
		initial_coins + 5,
		"same transaction is still not granted twice after a rerun")
	restored.free()
	vault.free()

	# Schema 4 had no transaction ledger. Keep the existing balance and read an empty ledger.
	_remove_save_target()
	var schema_four: ConfigFile = ConfigFile.new()
	schema_four.set_value("vault", "schema_version", 4)
	schema_four.set_value("vault", "shards", 0)
	schema_four.set_value("vault", "continue_coins", 7)
	schema_four.set_value("vault", "hero", "")
	schema_four.set_value("vault", "opened", [])
	schema_four.set_value("vault", "hero_sources", {})
	_expect_error(schema_four.save(_save_absolute), OK, "prepares a schema-4 coin save")
	var migrated: Node = _new_vault()
	migrated.load_vault()
	_expect_equal(migrated.continue_coins, 7, "schema-4 coin balance preserved")
	_expect_true(migrated.continue_coin_grants.is_empty(), "old save has an empty transaction ledger")
	_expect_true(
		migrated.adopt_continue_coin_grant(5, "legacy-coin-transaction"),
		"migrates the old IAP grant key into Vault")
	_expect_equal(migrated.continue_coins, 7, "old grant-key migration leaves the balance unchanged")
	_expect_equal(
		int(migrated.continue_coin_grants.get("legacy-coin-transaction", 0)),
		5,
		"old grant-key migration saved")
	_expect_true(
		migrated.adopt_continue_coin_grant(5, "legacy-coin-transaction"),
		"old grant-key migration is idempotent")
	_expect_false(
		migrated.adopt_continue_coin_grant(10, "legacy-coin-transaction"),
		"rejects a different quantity on the old grant key")
	migrated.free()


func _test_versioned_primary_beats_backup() -> void:
	_remove_save_target()
	var backup: ConfigFile = ConfigFile.new()
	backup.set_value("vault", "schema_version", 2)
	backup.set_value("vault", "shards", 41)
	backup.set_value("vault", "hero", "")
	backup.set_value("vault", "opened", [])
	for path in VAULT_SCRIPT.POOL:
		backup.set_value("vault", path, 0)
	_expect_error(backup.save(_backup_absolute), OK, "prepares a legacy vault backup")
	var primary: ConfigFile = ConfigFile.new()
	primary.set_value("vault", "schema_version", 2)
	primary.set_value("vault", "shards", 92)
	primary.set_value("vault", "hero", "")
	primary.set_value("vault", "opened", [])
	for path in VAULT_SCRIPT.POOL:
		primary.set_value("vault", path, 0)
	_expect_error(primary.save(_save_absolute), OK, "prepares a newer legacy vault primary file")

	var vault: Node = _new_vault()
	vault.load_vault()
	_expect_equal(vault.shards, 92, "schema upgrade keeps shards from the newest primary")
	var persisted: ConfigFile = ConfigFile.new()
	_expect_error(persisted.load(_save_absolute), OK, "primary file kept after upgrade")
	_expect_equal(
		int(persisted.get_value("vault", "shards", -1)),
		92,
		"schema upgrade does not overwrite the primary with an old backup")
	vault.free()

	_remove_save_target()
	var complete_backup: ConfigFile = ConfigFile.new()
	complete_backup.set_value("vault", "schema_version", 2)
	complete_backup.set_value("vault", "shards", 41)
	complete_backup.set_value("vault", "hero", "")
	complete_backup.set_value("vault", "opened", [])
	for path in VAULT_SCRIPT.POOL:
		complete_backup.set_value("vault", path, 0)
	_expect_error(
		complete_backup.save(_backup_absolute), OK, "prepares a complete legacy vault backup")
	var truncated_primary: ConfigFile = ConfigFile.new()
	truncated_primary.set_value("vault", "schema_version", 2)
	truncated_primary.set_value("vault", "shards", 999)
	truncated_primary.set_value("vault", "hero", "")
	truncated_primary.set_value("vault", "opened", [])
	_expect_error(
		truncated_primary.save(_save_absolute), OK, "prepares a truncated but parseable vault primary file")

	var recovered: Node = _new_vault()
	recovered.load_vault()
	_expect_equal(recovered.shards, 41, "prefers a complete backup over a truncated legacy-version primary file")
	var repaired: ConfigFile = ConfigFile.new()
	_expect_error(repaired.load(_save_absolute), OK, "truncated vault primary file repaired")
	_expect_equal(
		int(repaired.get_value("vault", "shards", -1)),
		41,
		"repaired vault primary file keeps backup state")
	recovered.free()

	_remove_save_target()
	var legacy_backup: ConfigFile = ConfigFile.new()
	legacy_backup.set_value("vault", "shards", 63)
	legacy_backup.set_value("vault", "hero", "")
	legacy_backup.set_value("vault", "opened", [])
	for path in VAULT_SCRIPT.POOL:
		legacy_backup.set_value("vault", path, 0)
	_expect_error(
		legacy_backup.save(_backup_absolute), OK, "prepares a complete unversioned vault backup")
	var sparse_versioned_primary: ConfigFile = ConfigFile.new()
	sparse_versioned_primary.set_value("vault", "schema_version", 2)
	sparse_versioned_primary.set_value("vault", "shards", 999)
	sparse_versioned_primary.set_value("vault", "hero", "")
	sparse_versioned_primary.set_value("vault", "opened", [])
	_expect_error(
		sparse_versioned_primary.save(_save_absolute),
		OK,
		"prepares a versioned vault primary file that only has core lines left")

	var legacy_recovered: Node = _new_vault()
	legacy_recovered.load_vault()
	_expect_equal(
		legacy_recovered.shards,
		63,
		"prefers a complete unversioned backup over a sparse high-version primary file")
	legacy_recovered.free()


func _test_backup_recovery() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	vault.shards = 41
	_expect_error(vault.save_vault(), OK, "first successful save")
	vault.shards = 92
	_expect_error(vault.save_vault(), OK, "next successful save")

	var backup: ConfigFile = ConfigFile.new()
	_expect_error(backup.load(_backup_absolute), OK, "backup of the previous good copy created")
	_expect_equal(
		int(backup.get_value("vault", "shards", -1)),
		41,
		"backup keeps the good copy from before replace")

	_remove_path(_save_absolute)
	var missing_restored: Node = _new_vault()
	missing_restored.load_vault()
	_expect_equal(missing_restored.shards, 41, "restores the backup when the primary file is missing")
	var repaired: ConfigFile = ConfigFile.new()
	_expect_error(repaired.load(_save_absolute), OK, "recreates a missing primary file")
	_expect_equal(
		int(repaired.get_value("vault", "shards", -1)),
		41,
		"recreated primary file is in backup state")
	missing_restored.free()

	var incomplete: ConfigFile = ConfigFile.new()
	incomplete.set_value("vault", "schema_version", VAULT_SCRIPT.SCHEMA_VERSION)
	incomplete.set_value("vault", "shards", 999)
	_expect_error(incomplete.save(_save_absolute), OK, "prepares a truncated current save")
	var truncated_restored: Node = _new_vault()
	truncated_restored.load_vault()
	_expect_equal(truncated_restored.shards, 41, "restores the backup if the current save is incomplete")
	repaired = ConfigFile.new()
	_expect_error(repaired.load(_save_absolute), OK, "incomplete primary file recovered")
	_expect_true(
		repaired.has_section_key("vault", HEART),
		"recovered primary file keeps every current-schema key")
	_expect_false(FileAccess.file_exists(_temp_absolute), "temp file removed after restoring a backup")
	truncated_restored.free()

	var versionless: ConfigFile = ConfigFile.new()
	versionless.set_value("vault", "shards", 999)
	_expect_error(versionless.save(_save_absolute), OK, "prepares a save truncated before the version line")
	var versionless_restored: Node = _new_vault()
	versionless_restored.load_vault()
	_expect_equal(
		versionless_restored.shards,
		41,
		"a backup beats an unversioned incomplete primary file")
	repaired = ConfigFile.new()
	_expect_error(repaired.load(_save_absolute), OK, "unversioned primary file recovered")
	_expect_equal(
		int(repaired.get_value("vault", "schema_version", 0)),
		VAULT_SCRIPT.SCHEMA_VERSION,
		"recovered primary file is the current schema")
	versionless_restored.free()
	vault.free()


func _test_save_failure_rollback() -> void:
	_remove_save_target()
	var seed: ConfigFile = ConfigFile.new()
	seed.set_value("vault", "shards", 123)
	_expect_error(seed.save(_save_absolute), OK, "prepares the existing save before replace failure")
	var original: String = FileAccess.get_file_as_string(_save_absolute)

	var vault: Node = FAILING_VAULT_SCRIPT.new() as Node
	vault.load_vault()
	var changed_count: Array[int] = [0]
	vault.changed.connect(func() -> void: changed_count[0] += 1)
	var boon: Boon = load(HEART) as Boon
	_expect_equal(
		vault.purchase_boon(boon, HEART, 0),
		vault.PurchaseResult.SAVE_FAILED,
		"returns a save failure as a buy failure")
	_expect_equal(vault.shards, 123, "shards roll back after a save failure")
	_expect_equal(vault.rank_of(HEART), 0, "boon rank rolls back after a save failure")

	_expect_equal(
		vault.purchase_hero(DANCER),
		vault.PurchaseResult.INVALID,
		"shard-buy of a paid hero is rejected before save")
	_expect_equal(vault.shards, 123, "shards roll back after a hero save failure")
	_expect_false(vault.hero_open(DANCER), "stays locked after a hero save failure")

	var bundle: Array[String] = [DANCER, KEEPER]
	_expect_false(
		vault.grant_heroes(bundle, vault.HERO_SOURCE_IAP_BUNDLE),
		"returns a hero-bundle save failure")
	_expect_false(vault.hero_open(DANCER), "Dancing Star rolls back after a bundle save failure")
	_expect_false(vault.hero_open(KEEPER), "Lantern Keeper rolls back after a bundle save failure")
	_expect_true(vault.hero_sources.is_empty(), "all sources roll back after a bundle save failure")
	var coins_before: int = vault.continue_coins
	_expect_false(
		vault.grant_continue_coins(5, "failed-coin-transaction"),
		"returns an atomic coin-save failure")
	_expect_equal(vault.continue_coins, coins_before, "coin balance rolls back after a save failure")
	_expect_true(
		vault.continue_coin_grants.is_empty(),
		"coin ledger rolls back after a save failure")

	_expect_equal(vault.award(0), 0, "returns a reward save failure")
	_expect_equal(vault.shards, 123, "shards roll back after a reward save failure")
	var failed_settlement: Dictionary = vault.settle_run_score(24600, 12)
	_expect_equal(
		int(failed_settlement.get("status", -1)),
		vault.RunSettlementStatus.SAVE_FAILED,
		"returns save-failed status for cumulative settlement")
	_expect_equal(
		int(failed_settlement.get("awarded", -1)),
		0,
		"a save-failed cumulative settlement grants nothing")
	_expect_equal(vault.shards, 123, "shards roll back after a cumulative-settlement save failure")
	vault.opened.append(DANCER)
	_expect_false(vault.choose_hero(DANCER), "returns a select save failure")
	_expect_equal(vault.chosen, "", "hero rolls back after a select save failure")
	_expect_equal(changed_count[0], 0, "a save failure emits no changed signal")
	_expect_equal(
		FileAccess.get_file_as_string(_save_absolute),
		original,
		"existing save bytes kept after a final-replace failure")
	_expect_true(FileAccess.file_exists(_backup_absolute), "good backup kept after replace failure")
	_expect_false(FileAccess.file_exists(_temp_absolute), "temp file removed after replace failure")

	# If the caller holds the failure and retries with the same `already_awarded`,
	# must be able to grant exactly once after save recovery.
	vault.should_fail = false
	var recovered_settlement: Dictionary = vault.settle_run_score(24600, 12)
	_expect_equal(
		int(recovered_settlement.get("status", -1)),
		vault.RunSettlementStatus.APPLIED,
		"pending settlement succeeds after save recovery")
	_expect_equal(
		int(recovered_settlement.get("awarded", 0)),
		12,
		"delta is granted exactly once after save recovery")
	_expect_equal(vault.shards, 135, "recovered settlement applied to the shard balance")
	_expect_equal(changed_count[0], 1, "only recovered settlement emits a changed signal")
	var settled_again: Dictionary = vault.settle_run_score(24600, 24)
	_expect_equal(
		int(settled_again.get("status", -1)),
		vault.RunSettlementStatus.NO_CHANGE,
		"retrying the same run after recovered settlement grants nothing")
	_expect_equal(vault.shards, 135, "no duplicate shards on retry after recover")
	vault.free()


func _test_purchase_recommendation() -> void:
	_remove_save_target()
	var vault: Node = _new_vault()
	var options: Array[Dictionary] = vault.purchase_options()
	_expect_true(not options.is_empty(), "a buy goal exists in a new vault")

	var cheapest: int = 1 << 30
	for option in options:
		_expect_true(
			str(option.get("kind", "")) != "hero",
			"paid heroes are not next_purchase candidates")
		cheapest = mini(cheapest, int(option.get("cost", 0)))
	_expect_equal(
		int(vault.next_purchase().get("cost", -1)),
		cheapest,
		"recommends the nearest goal when there are no shards")

	vault.shards = cheapest
	var affordable: int = 0
	for option in vault.purchase_options():
		if int(option.get("cost", 0)) <= vault.shards:
			affordable += 1
	_expect_equal(
		vault.affordable_purchase_count(),
		affordable,
		"ready-to-buy badge count matches product-row count")
	_expect_true(
		int(vault.next_purchase().get("cost", 0)) <= vault.shards,
		"a ready goal is preferred when something is still buyable")

	for path in vault.POOL:
		var boon: Boon = load(path) as Boon
		vault.ranks[path] = boon.max_rank
	_expect_true(vault.next_purchase().is_empty(), "no next goal after buying everything")
	_expect_equal(vault.affordable_purchase_count(), 0, "ready-to-buy badge is 0 after buying everything")
	vault.free()


func _remove_save_target() -> void:
	_remove_path(_save_absolute)
	_remove_path(_temp_absolute)
	_remove_path(_backup_absolute)
	_remove_path(_backup_temp_absolute)


func _remove_path(path: String) -> void:
	if FileAccess.file_exists(path):
		var file_error: Error = DirAccess.remove_absolute(path)
		if file_error != OK:
			printerr("failed to clean test save file: ", path, " — ", error_string(file_error))
	elif DirAccess.dir_exists_absolute(path):
		var dir_error: Error = DirAccess.remove_absolute(path)
		if dir_error != OK:
			printerr("failed to clean test save folder: ", path, " — ", error_string(dir_error))


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


func _expect_error(actual: Error, expected: Error, label: String) -> void:
	_expect_equal(actual, expected, label)
