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


func _test_hero_visual_assets() -> void:
	for path in [WARDEN, DANCER, KEEPER]:
		var hero: Hero = load(path) as Hero
		_expect_true(hero != null, "hero resource loaded " + path)
		if hero == null:
			continue
		var hero_id: String = path.get_file().get_basename()
		var custom_root: String = "res://assets/custom/actors/heroes/" + hero_id + "/"
		_expect_equal(hero.sprite_cell, Vector2i(48, 64), hero_id + " cell spec")
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
