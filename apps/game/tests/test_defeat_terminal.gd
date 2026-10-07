extends Node

## Sealed defeat: the terminal marker outranks backup and stale data, the
## paid continue is transactional, and a fresh expedition resets the run
## while wallets, unlocks and records survive.
##
## Death seals the journey file with `ended: true` at the last seal's id. No
## title, relaunch, backup or cloud path resumes it; only a coin continue in
## the live arena replaces the marker with a new alive seal, spending exactly
## one coin. These pin the parts a regression could quietly break: the main
## file beating an older alive backup, the title hiding Continue for a sealed
## run but showing it after an alive quit, the fresh cycle-1/zone-0 reset
## with permanent wealth kept, the revive preserving hero/cycle/score/growth
## in place, and every failure (zero coins, blocked journey write, blocked
## Vault save, blocked defeat seal) keeping balances and terminal status
## safe. Cloud precedence has its own cases in `test_cloud_coordinator.gd`.
##
## Uses temp journey/onboarding/chronicle paths under the isolated test HOME,
## so no human save is touched. The Vault and Records autoloads are real but
## isolated; assertions use deltas, never absolutes.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const TITLE_SCENE: PackedScene = preload("res://scenes/menus/title_menu.tscn")
const TEST_PATH: String = "user://test_defeat.json"
const TEST_BACKUP: String = "user://test_defeat.json.bak"
const TEST_ONBOARD: String = "user://test_defeat_onboarding.json"
const TEST_CHRONICLE: String = "user://test_defeat_chronicle.json"
const VAULT_TMP: String = "user://vault.cfg.tmp"
const SHARP_MOON: String = "res://resources/relics/sharp_moon.tres"
const TOUGH_LIFE: String = "res://resources/relics/tough_life.tres"

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_run.call_deferred()


func _run() -> void:
	_fresh_paths()
	_test_terminal_main_outranks_alive_backup()
	_fresh_paths()
	await _test_death_hides_title_continue_alive_quit_shows_it()
	_fresh_paths()
	await _test_fresh_restart_resets_run_keeps_permanents()
	_fresh_paths()
	await _test_coin_continue_revives_transactionally()
	_fresh_paths()
	await _test_coin_continue_zero_and_save_failures()
	_fresh_paths()
	await _test_defeat_seal_failure_blocks_exit()
	_fresh_paths()
	await _test_alive_quit_resumes()

	_restore_paths()
	Journey.disarm()
	if _failed > 0:
		printerr("defeat test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("defeat test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("defeat test aborted: user:// path is not isolated — ", user_root)
	return safe


func _fresh_paths() -> void:
	Journey.path = TEST_PATH
	Journey.backup_path = TEST_BACKUP
	Onboarding.path = TEST_ONBOARD
	Chronicle.path = TEST_CHRONICLE
	for candidate in [TEST_PATH, TEST_BACKUP, TEST_PATH + ".tmp",
			TEST_BACKUP + ".tmp", TEST_ONBOARD, TEST_ONBOARD + ".tmp",
			TEST_CHRONICLE]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	for occupied in [TEST_PATH + ".tmp", TEST_BACKUP + ".tmp", VAULT_TMP]:
		if DirAccess.dir_exists_absolute(
				ProjectSettings.globalize_path(occupied)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(occupied))
	Onboarding.forget_cache()
	Chronicle.forget_cache()
	Journey.disarm()
	Journey.last_error = ""
	Journey.install_fault = Journey.InstallFault.NONE
	RunEntry.from_title = false
	get_tree().paused = false


func _restore_paths() -> void:
	for candidate in [TEST_PATH, TEST_BACKUP, TEST_PATH + ".tmp", TEST_ONBOARD,
			TEST_ONBOARD + ".tmp", TEST_CHRONICLE]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	Journey.path = Journey.DEFAULT_PATH
	Journey.backup_path = Journey.DEFAULT_BACKUP_PATH
	Onboarding.path = Onboarding.DEFAULT_PATH
	Chronicle.path = Chronicle.DEFAULT_PATH
	Onboarding.forget_cache()
	Chronicle.forget_cache()
	Journey.disarm()
	Journey.last_error = ""
	RunEntry.from_title = false
	get_tree().paused = false


## A human run starts from the title: writes armed, entry marked.
func _begin_human_fresh() -> void:
	Journey.begin_fresh()
	RunEntry.mark_from_title()


func _begin_human_resume() -> void:
	Journey.begin_resume()
	RunEntry.mark_from_title()


func _write_text(candidate: String, text: String) -> void:
	var handle: FileAccess = FileAccess.open(candidate, FileAccess.WRITE)
	handle.store_string(text)
	handle.close()


## Raw JSON of one file, bypassing the Journey validator. Empty when the
## file is missing or malformed.
func _read_json_file(candidate: String) -> Dictionary:
	if not FileAccess.file_exists(candidate):
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(candidate)) != OK:
		return {}
	return parser.data as Dictionary if parser.data is Dictionary else {}


func _valid_checkpoint() -> Dictionary:
	return {
		"schema_version": 1,
		"journey_id": "d1",
		"checkpoint_id": 1,
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
		"shards_awarded": 5,
		"settled_score": 2400,
		"gate_direction": [1.0, 0.0],
		"opening_played": true,
		"saved_at_unix": 1700000000,
	}


func _stack_counts(arena: Node2D) -> Dictionary:
	var counts: Dictionary = {}
	for item in arena.get("_taken"):
		if item == null:
			continue
		var relic_path: String = str(item.get_meta("path", ""))
		if relic_path.is_empty():
			relic_path = (item as Relic).resource_path
		counts[relic_path] = int(counts.get(relic_path, 0)) + 1
	return counts


## Occupy a path as a directory so the next write there fails. Always paired
## with `_release_dir`.
func _occupy_as_dir(candidate: String) -> void:
	if FileAccess.file_exists(candidate):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(candidate))


func _release_dir(candidate: String) -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(candidate)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


# --- terminal precedence ------------------------------------------------------
## The real writer leaves no older alive backup behind a seal: the terminal
## marker mirrors into both files, backup first, so a corrupt or deleted
## main still reads terminal and heals forward. A mistyped marker is
## hostile, not ended: the whole save refuses and the sealed pair on disk
## survives the refused write.
func _test_terminal_main_outranks_alive_backup() -> void:
	var first: Dictionary = _valid_checkpoint()
	first["checkpoint_id"] = 1
	_expect_equal(Journey.write_checkpoint(first), OK,
		"the first checkpoint writes")
	var second: Dictionary = _valid_checkpoint()
	second["checkpoint_id"] = 2
	_expect_equal(Journey.write_checkpoint(second), OK,
		"the second checkpoint writes")
	_expect_false(bool(_read_json_file(TEST_BACKUP).get("ended", false)),
		"alive seals rotate the older seal into the backup")
	var sealed: Dictionary = second.duplicate(true)
	sealed["ended"] = true
	_expect_true(Journey.validate(sealed), "an ended checkpoint validates")
	_expect_equal(Journey.write_checkpoint(sealed), OK,
		"the terminal marker writes")
	_expect_true(bool(_read_json_file(TEST_BACKUP).get("ended", false)),
		"the seal mirrors into the backup")
	_expect_equal(FileAccess.get_file_as_string(TEST_BACKUP),
		FileAccess.get_file_as_string(TEST_PATH),
		"the mirrored pair is byte-identical")
	var read: Dictionary = Journey.read_checkpoint()
	_expect_true(bool(read.get("ended", false)),
		"the read returns the terminal pair")
	_expect_equal(int(read.get("checkpoint_id", 0)), 2,
		"the read keeps the marker's seal id")
	_expect_false(Journey.has_valid_checkpoint(),
		"a sealed pair offers no Continue")
	_expect_true(Journey.summary(read).is_empty(),
		"a sealed pair summarizes to nothing")

	# A corrupt main over the mirrored pair restores the marker — never an
	# older alive seal — and heals the main forward to terminal.
	_write_text(TEST_PATH, "{\"schema_version\": 1, \"cycle\":")
	var recovered: Dictionary = Journey.read_checkpoint()
	_expect_true(bool(recovered.get("ended", false)),
		"a corrupt main restores the mirrored marker")
	_expect_equal(int(recovered.get("checkpoint_id", 0)), 2,
		"the restored marker keeps its seal id")
	_expect_false(Journey.has_valid_checkpoint(),
		"a restored marker offers no Continue")
	_expect_true(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"the restored marker heals the main forward")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	_expect_true(bool(Journey.read_checkpoint().get("ended", false)),
		"a deleted main restores the mirrored marker")
	_expect_false(Journey.has_valid_checkpoint(),
		"a deleted main offers no Continue")

	# A mistyped marker is hostile, not ended: the whole save refuses and
	# the sealed pair on disk survives the refused write.
	for bad_marker in [1, "true", 1.0]:
		var hostile: Dictionary = _valid_checkpoint()
		hostile["ended"] = bad_marker
		_expect_false(Journey.validate(hostile),
			"a non-bool ended marker is refused: %s" % str(bad_marker))
		_expect_not_equal(Journey.write_checkpoint(hostile), OK,
			"a mistyped marker never writes")
	_expect_true(bool(Journey.read_checkpoint().get("ended", false)),
		"refused writes keep the sealed pair")


# --- title --------------------------------------------------------------------
## A real death hides the title's Continue panel; quitting while alive keeps
## showing it, and the alive quit still resumes.
func _test_death_hides_title_continue_alive_quit_shows_it() -> void:
	_begin_human_fresh()
	var doomed: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(doomed)
	await get_tree().process_frame
	await get_tree().process_frame
	doomed.set("_level", 4)
	doomed.set("_kill_score", 900)
	_expect_true(bool(doomed.call("_journey_checkpoint", true)),
		"the gate seals before the death")
	doomed.call("_finish", false)
	await get_tree().process_frame
	doomed.queue_free()
	await get_tree().process_frame

	var lost_title: Control = TITLE_SCENE.instantiate() as Control
	add_child(lost_title)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_false((lost_title.get_node("Ui/Screen/JourneyPanel") as Control).visible,
		"a sealed defeat hides Continue on the title")
	lost_title.queue_free()
	await get_tree().process_frame

	# Quitting while alive is the honest Continue: it shows and it resumes.
	_begin_human_fresh()
	var living: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(living)
	await get_tree().process_frame
	await get_tree().process_frame
	living.set("_cycle", 2)
	living.set("_kill_score", 1200)
	_expect_true(bool(living.call("_journey_checkpoint", true)),
		"the alive quit seals its gate")
	living.queue_free()
	await get_tree().process_frame
	var waiting_title: Control = TITLE_SCENE.instantiate() as Control
	add_child(waiting_title)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true((waiting_title.get_node("Ui/Screen/JourneyPanel") as Control).visible,
		"an alive quit shows Continue on the title")
	waiting_title.queue_free()
	await get_tree().process_frame
	_begin_human_resume()
	var returned: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(returned)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool(returned.get("_journey_resuming")),
		"an alive quit resumes its run")
	_expect_equal(int(returned.get("_cycle")), 2,
		"the alive quit keeps its cycle")
	returned.queue_free()
	await get_tree().process_frame


# --- fresh restart ------------------------------------------------------------
## A fresh expedition after a defeat starts at cycle 1/zone 0 with a new
## journey, while shards, coins, unlocks and records survive untouched. The
## new journey settles only its own value afterwards.
func _test_fresh_restart_resets_run_keeps_permanents() -> void:
	Vault.continue_coins = 2
	_begin_human_fresh()
	var doomed: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(doomed)
	await get_tree().process_frame
	await get_tree().process_frame
	doomed.set("_level", 5)
	doomed.set("_kill_score", 1500)
	doomed.set("_survived", 200.0)
	_expect_true(bool(doomed.call("_journey_checkpoint", true)),
		"the gate seals before the death")
	var old_journey: String = str(doomed.get("_journey_id"))
	doomed.set("_kill_score", 2600)
	doomed.call("_finish", false)
	await get_tree().process_frame
	var banked: int = Vault.shards
	var best: int = Records.best_score
	var opened: Array = (Vault.opened as Array).duplicate()
	doomed.queue_free()
	await get_tree().process_frame

	# What `_restart` arms, without the scene reload the test cannot take:
	# a fresh expedition over the sealed defeat.
	_begin_human_fresh()
	var fresh: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(fresh)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(int(fresh.get("_cycle")), 1,
		"a fresh expedition starts at cycle 1")
	_expect_equal(int(fresh.get("_zone_index")), 0,
		"a fresh expedition starts at zone 0")
	_expect_equal(int(fresh.get("_lit_count")), 0,
		"a fresh expedition lights nothing yet")
	_expect_not_equal(str(fresh.get("_journey_id")), old_journey,
		"a fresh expedition begins a new journey")
	_expect_false(bool(fresh.get("_over")), "a fresh expedition is alive")
	_expect_equal(Vault.shards, banked,
		"a fresh expedition banks nothing by starting")
	_expect_equal(Records.best_score, best,
		"a fresh expedition keeps the records")
	_expect_equal(Vault.opened as Array, opened,
		"a fresh expedition keeps the unlocks")
	_expect_equal(Vault.continue_coins, 2,
		"a fresh expedition spends no coins")
	_expect_false(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"a fresh expedition clears the marker")
	_expect_equal(int(_read_json_file(TEST_PATH).get("checkpoint_id", 0)), 1,
		"a fresh expedition seals its first checkpoint")

	# The new journey's own defeat settles only its own value: the sealed
	# run's receipt never pays twice across the restart.
	fresh.set("_kill_score", 400)
	fresh.call("_finish", false)
	await get_tree().process_frame
	_expect_true(Vault.shards >= banked,
		"the new journey settles only its own value")
	_expect_equal(int(_read_json_file(TEST_PATH).get("journey_id", -1)),
		int(fresh.get("_journey_id")),
		"the new defeat seals under the new journey")
	fresh.queue_free()
	await get_tree().process_frame


# --- coin continue ------------------------------------------------------------
## A paid continuation revives the current run in place — hero, cycle/zone,
## score and growth — debits exactly one coin, and durably restores a
## resumable live journey. Quitting after the revive resumes the revived
## state, defeated-segment loot included.
func _test_coin_continue_revives_transactionally() -> void:
	Vault.continue_coins = 2
	Vault.continue_txn = {}
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.set("_cycle", 2)
	arena.set("_zone_index", 1)
	arena.set("_level", 6)
	arena.set("_kill_score", 1500)
	arena.set("_survived", 300.0)
	_expect_true(bool(arena.call("_journey_checkpoint", true)),
		"the gate seals before the death")
	var sealed_id: int = int(
		(arena.get("_journey_snapshot") as Dictionary)["checkpoint_id"])
	var journey: String = str(arena.get("_journey_id"))
	var hero_path: String = str(arena.get("_run_hero_path"))
	arena.set("_kill_score", 2400)
	var relic_panel: Control = arena.get_node("Ui/Relic") as Control
	arena.call("_on_relic_picked",
		relic_panel.call("take_named", TOUGH_LIFE), false)
	var live_stacks: Dictionary = _stack_counts(arena)
	arena.call("_finish", false)
	await get_tree().process_frame
	var banked: int = Vault.shards
	_expect_true(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"death seals the marker before the coin")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"death journals no transaction")

	_expect_true(bool(arena.call("continue_run")),
		"a paid continuation revives the run")
	_expect_equal(Vault.continue_coins, 1,
		"the revive debits exactly one coin")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"the landed seal clears the journal")
	_expect_false(bool(arena.get("_over")), "the revived run is alive")
	_expect_equal(int(arena.get("_health")), int(arena.get("_max_health")),
		"the revive restores full health")
	_expect_equal(int(arena.get("_cycle")), 2,
		"the revive keeps the cycle")
	_expect_equal(int(arena.get("_zone_index")), 1,
		"the revive keeps the zone")
	_expect_equal(int(arena.get("_kill_score")), 2400,
		"the revive keeps the score")
	_expect_equal(str(arena.get("_run_hero_path")), hero_path,
		"the revive keeps the hero")
	_expect_equal(_stack_counts(arena), live_stacks,
		"the revive keeps the growth")
	_expect_equal(str(arena.get("_journey_id")), journey,
		"the revive keeps the journey")
	_expect_equal(Vault.shards, banked,
		"the revive itself settles no receipt")
	var revived_file: Dictionary = _read_json_file(TEST_PATH)
	_expect_false(bool(revived_file.get("ended", false)),
		"the revive durably clears the marker")
	_expect_equal(int(revived_file.get("checkpoint_id", 0)), sealed_id + 1,
		"the revive seals the next checkpoint")
	_expect_true(Journey.has_valid_checkpoint(),
		"the revive restores a resumable journey")

	# Quitting after the revive resumes the revived state, not the defeat.
	arena.queue_free()
	await get_tree().process_frame
	_begin_human_resume()
	var returned: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(returned)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool(returned.get("_journey_resuming")),
		"the revived journey resumes")
	_expect_equal(int(returned.get("_kill_score")), 2400,
		"the resumed revive keeps its score")
	_expect_equal(_stack_counts(returned), live_stacks,
		"the resumed revive keeps its growth")
	returned.queue_free()
	await get_tree().process_frame


## Zero coins and injected save failures keep balances and terminal status
## safe: a failed debit writes nothing and journals nothing, while a failed
## seal keeps the marker with the debit journaled — so the retry reuses it
## without charging again and no failure strands an unpaid alive checkpoint.
func _test_coin_continue_zero_and_save_failures() -> void:
	# No coins: nothing moves and the result choice reopens.
	Vault.continue_coins = 0
	Vault.continue_txn = {}
	_begin_human_fresh()
	var broke: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(broke)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool(broke.call("_journey_checkpoint", true)),
		"broke: the gate seals before the death")
	broke.call("_finish", false)
	await get_tree().process_frame
	_expect_false(bool(broke.call("continue_run")),
		"broke: the revive refuses without coins")
	_expect_equal(Vault.continue_coins, 0, "broke: the balance stays zero")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"broke: no debit journals a transaction")
	_expect_true(bool(broke.get("_over")), "broke: the run stays over")
	_expect_true(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"broke: the marker stays sealed")
	broke.call("_on_continue_requested")
	await get_tree().process_frame
	_expect_true(bool((broke.get_node("Ui/Result") as Control).visible),
		"broke: the result choice reopens")
	broke.queue_free()
	await get_tree().process_frame

	# A blocked seal write: the debit journals first, the marker stands, and
	# the retry after recovery reuses the journal without charging again.
	Vault.continue_coins = 2
	Vault.continue_txn = {}
	_begin_human_fresh()
	var blocked: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(blocked)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool(blocked.call("_journey_checkpoint", true)),
		"blocked seal: the gate seals before the death")
	var sealed_id: int = int(
		(blocked.get("_journey_snapshot") as Dictionary)["checkpoint_id"])
	blocked.call("_finish", false)
	await get_tree().process_frame
	_occupy_as_dir(TEST_PATH + ".tmp")
	_expect_false(bool(blocked.call("continue_run")),
		"blocked seal: the revive fails")
	_expect_equal(Vault.continue_coins, 1,
		"blocked seal: the debit lands before the seal")
	_expect_false((Vault.continue_txn as Dictionary).is_empty(),
		"blocked seal: the debit journals its seal")
	_expect_equal(int((Vault.continue_txn as Dictionary).get(
		"checkpoint_id", 0)), sealed_id + 1,
		"blocked seal: the journal names the next seal")
	_expect_true(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"blocked seal: the marker stands")
	_expect_false(Journey.has_valid_checkpoint(),
		"blocked seal: no unpaid checkpoint is resumable")
	_expect_true(bool((blocked.get("_journey_snapshot") as Dictionary).get(
		"ended", false)), "blocked seal: the run stays sealed in memory")
	_expect_equal(int(blocked.get("_journey_checkpoint_id")), sealed_id,
		"blocked seal: the checkpoint counter is restored")
	_release_dir(TEST_PATH + ".tmp")
	_expect_true(bool(blocked.call("continue_run")),
		"blocked seal: the retry after recovery revives")
	_expect_equal(Vault.continue_coins, 1,
		"blocked seal: the retry charges nothing more")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"blocked seal: the landed seal clears the journal")
	blocked.queue_free()
	await get_tree().process_frame

	# A blocked Vault save: the debit cannot journal, so no seal is even
	# attempted. Both writes failing together behaves the same; then each
	# recovery in turn lands exactly one debit and one seal in total.
	Vault.continue_coins = 2
	Vault.continue_txn = {}
	_begin_human_fresh()
	var poor_save: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(poor_save)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool(poor_save.call("_journey_checkpoint", true)),
		"blocked debit: the gate seals before the death")
	var spend_sealed_id: int = int(
		(poor_save.get("_journey_snapshot") as Dictionary)["checkpoint_id"])
	poor_save.call("_finish", false)
	await get_tree().process_frame
	_occupy_as_dir(VAULT_TMP)
	_occupy_as_dir(TEST_PATH + ".tmp")
	_expect_false(bool(poor_save.call("continue_run")),
		"blocked debit: the revive fails")
	_expect_equal(Vault.continue_coins, 2,
		"blocked debit: the balance is untouched")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"blocked debit: a failed debit journals nothing")
	_expect_true(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"blocked debit: the marker stands")
	_expect_equal(int(poor_save.get("_journey_checkpoint_id")),
		spend_sealed_id, "blocked debit: the checkpoint counter is restored")
	_expect_false(Journey.has_valid_checkpoint(),
		"blocked debit: the sealed run is not resumable")
	_release_dir(VAULT_TMP)
	_expect_false(bool(poor_save.call("continue_run")),
		"blocked debit: the seal still fails with the vault healed")
	_expect_equal(Vault.continue_coins, 1,
		"blocked debit: the healed debit journals first")
	_expect_false((Vault.continue_txn as Dictionary).is_empty(),
		"blocked debit: the journal waits for its seal")
	_expect_true(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"blocked debit: the marker still stands")
	_release_dir(TEST_PATH + ".tmp")
	_expect_true(bool(poor_save.call("continue_run")),
		"blocked debit: the retry after recovery revives")
	_expect_equal(Vault.continue_coins, 1,
		"blocked debit: exactly one coin spent in total")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"blocked debit: the landed seal clears the journal")
	poor_save.queue_free()
	await get_tree().process_frame


## A defeat whose terminal seal fails cannot be left: result exits reoffer
## the choice until the marker lands, so the older alive file behind it
## never becomes a free continuation.
func _test_defeat_seal_failure_blocks_exit() -> void:
	Vault.continue_coins = 2
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool(arena.call("_journey_checkpoint", true)),
		"the gate seals before the death")
	_occupy_as_dir(TEST_PATH + ".tmp")
	arena.call("_finish", false)
	await get_tree().process_frame
	_expect_true(bool(arena.get("_journey_defeat_pending")),
		"the failed seal stays pending")
	_expect_false(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"the older alive file is still in place")
	_expect_true(bool(_read_json_file(TEST_BACKUP).get("ended", false)),
		"the backup already mirrors the seal")
	_expect_false(Journey.has_valid_checkpoint(),
		"the mirrored backup keeps the pair terminal meanwhile")
	# Restart would reload the scene; the blocked retry reopens instead, so
	# the run cannot be left and the test scene survives.
	arena.call("_on_result_dismissed", int(arena.ResultAction.RESTART))
	await get_tree().process_frame
	_expect_true(bool(arena.get("_over")), "the blocked exit stays over")
	_expect_true(bool((arena.get_node("Ui/Result") as Control).visible),
		"the blocked exit reoffers the choice")
	_expect_true(is_instance_valid(arena), "the blocked exit reloads nothing")
	_release_dir(TEST_PATH + ".tmp")
	_expect_true(bool(arena.call("_retry_pending_result_persistence")),
		"the retry after recovery lands the seal")
	_expect_false(bool(arena.get("_journey_defeat_pending")),
		"the landed seal clears the pending marker")
	_expect_true(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"the landed seal writes the marker")
	arena.queue_free()
	await get_tree().process_frame


## Quitting while alive — no finish, no death — resumes the sealed gate with
## its growth, health restored, guidance quiet.
func _test_alive_quit_resumes() -> void:
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.set("_cycle", 2)
	arena.set("_zone_index", 1)
	arena.set("_kill_score", 1100)
	var relic_panel: Control = arena.get_node("Ui/Relic") as Control
	arena.call("_on_relic_picked",
		relic_panel.call("take_named", SHARP_MOON), false)
	var want_stacks: Dictionary = _stack_counts(arena)
	_expect_true(bool(arena.call("_journey_checkpoint", true)),
		"the alive quit seals its gate")
	arena.queue_free()
	await get_tree().process_frame
	_begin_human_resume()
	var returned: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(returned)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool(returned.get("_journey_resuming")),
		"the alive quit resumes")
	_expect_equal(int(returned.get("_cycle")), 2,
		"the alive quit keeps its cycle")
	_expect_equal(int(returned.get("_zone_index")), 1,
		"the alive quit keeps its zone")
	_expect_equal(_stack_counts(returned), want_stacks,
		"the alive quit keeps its growth")
	_expect_equal(int(returned.get("_health")),
		int(returned.get("_max_health")),
		"the alive quit restores full health")
	_expect_false(bool(returned.get("_over")), "the alive quit is alive")
	returned.queue_free()
	await get_tree().process_frame


# --- expectations -------------------------------------------------------------
func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_not_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected not ", expected)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _expect_false(value: bool, label: String) -> void:
	_expect_equal(value, false, label)
