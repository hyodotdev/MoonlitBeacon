extends Node

## Crash-boundary regressions: the actual defeat file pair stays terminal
## through a failed primary, and a paid continuation debits durably before
## any alive seal is materialized, notified, or uploaded.
##
## The director reproduced both defects in isolated storage: the real
## defeat writer's pair revived after one corrupt main, and `continue_run()`
## stranded a resumable checkpoint with no durable debit at the alive
## stable hook. These pin the guards with the real writer, real reloads,
## real title/host/arena entry, and fault injection at each durable
## boundary — never a hand-built file pair or a simulated ordering. The
## cross-client half lives in `test_cloud_coordinator.gd`, beside its
## fixture. Uses temp journey paths under the isolated test HOME, so no
## human save is touched. The Vault autoload is real but isolated.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const TITLE_SCENE: PackedScene = preload("res://scenes/menus/title_menu.tscn")
const TEST_PATH: String = "user://test_crash.json"
const TEST_BACKUP: String = "user://test_crash.json.bak"
const VAULT_TMP: String = "user://vault.cfg.tmp"
const SHARP_MOON: String = "res://resources/relics/sharp_moon.tres"

var _failed: int = 0
var _checked: int = 0
var _stable_texts: Array[String] = []


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_run.call_deferred()


func _run() -> void:
	_fresh_paths()
	_test_actual_defeat_pair_survives_failed_primary()
	_fresh_paths()
	await _test_failed_primary_hides_title_and_host_gate()
	_fresh_paths()
	_test_paid_debit_lands_before_seal()
	_fresh_paths()
	await _test_double_fault_keeps_terminal_then_retries()
	_fresh_paths()
	await _test_stuck_revive_asks_before_boot()
	_fresh_paths()
	await _test_double_tap_debits_once()

	_restore_paths()
	Journey.disarm()
	if _failed > 0:
		printerr("crash boundary tests failed — ", _failed, "/", _checked,
			" case(s)")
		get_tree().quit(1)
		return
	print("crash boundary tests passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("crash boundary tests aborted: user:// path is not isolated — ", user_root)
	return safe


func _fresh_paths() -> void:
	Journey.path = TEST_PATH
	Journey.backup_path = TEST_BACKUP
	for candidate in [TEST_PATH, TEST_BACKUP, TEST_PATH + ".tmp",
			TEST_BACKUP + ".tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	for occupied in [TEST_PATH + ".tmp", TEST_BACKUP + ".tmp", VAULT_TMP]:
		if DirAccess.dir_exists_absolute(
				ProjectSettings.globalize_path(occupied)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(occupied))
	Journey.clear_stable_hooks()
	_stable_texts.clear()
	Vault.continue_txn = {}
	Journey.disarm()
	Journey.last_error = ""
	Journey.install_fault = Journey.InstallFault.NONE
	RunEntry.from_title = false
	get_tree().paused = false


func _restore_paths() -> void:
	for candidate in [TEST_PATH, TEST_BACKUP, TEST_PATH + ".tmp",
			TEST_BACKUP + ".tmp", VAULT_TMP]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(VAULT_TMP)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(VAULT_TMP))
	Journey.path = Journey.DEFAULT_PATH
	Journey.backup_path = Journey.DEFAULT_BACKUP_PATH
	Journey.clear_stable_hooks()
	_stable_texts.clear()
	Vault.continue_txn = {}
	Journey.disarm()
	Journey.last_error = ""
	Journey.install_fault = Journey.InstallFault.NONE
	RunEntry.from_title = false
	get_tree().paused = false


## A human run starts from the title: writes armed, entry marked.
func _begin_human_fresh() -> void:
	Journey.begin_fresh()
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


func _valid_checkpoint(journey_id: String, checkpoint_id: int) -> Dictionary:
	return {
		"schema_version": 1,
		"journey_id": journey_id,
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
		"shards_awarded": 5,
		"settled_score": 2400,
		"gate_direction": [1.0, 0.0],
		"opening_played": true,
		"saved_at_unix": 1700000000,
	}


## Occupy a path as a directory so the next write there fails. Always paired
## with `_release_dir`.
func _occupy_as_dir(candidate: String) -> void:
	if FileAccess.file_exists(candidate):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(candidate))


func _release_dir(candidate: String) -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(candidate)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _on_stable(info: Dictionary) -> void:
	_stable_texts.append(str(info.get("text", "")))


func _stable_ids() -> Array:
	var ids: Array = []
	for text in _stable_texts:
		var parser: JSON = JSON.new()
		if parser.parse(text) != OK:
			ids.append(-1)
			continue
		var data: Dictionary = parser.data as Dictionary
		ids.append(int(data.get("checkpoint_id", -1)))
	return ids


func _stable_ended_flags() -> Array:
	var flags: Array = []
	for text in _stable_texts:
		var parser: JSON = JSON.new()
		if parser.parse(text) != OK:
			flags.append(null)
			continue
		var data: Dictionary = parser.data as Dictionary
		flags.append(bool(data.get("ended", false)))
	return flags


func _find_button(node: Node, button_name: String) -> Button:
	if node is Button and node.name == StringName(button_name):
		return node as Button
	for child in node.get_children():
		var found: Button = _find_button(child, button_name)
		if found != null:
			return found
	return null


func _claim_threaded_arena(label: String) -> void:
	var progress: Array = []
	var status: ResourceLoader.ThreadLoadStatus = \
		ResourceLoader.load_threaded_get_status(
			ARENA_SCENE.resource_path, progress)
	var guard: int = 0
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and guard < 600:
		guard += 1
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(
			ARENA_SCENE.resource_path, progress)
	var claimed: Resource = ResourceLoader.load_threaded_get(
		ARENA_SCENE.resource_path) as Resource
	_expect_true(claimed != null, "%s drains its arena load" % label)


## Defeat one arena run through the real route and return it over.
func _defeat_arena(cycle: int, zone: int) -> Node2D:
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.set("_cycle", cycle)
	arena.set("_zone_index", zone)
	_expect_true(bool(arena.call("_journey_checkpoint", true)),
		"the gate seals before the death")
	arena.call("_finish", false)
	await get_tree().process_frame
	_expect_true(bool(arena.get("_over")), "the run is over")
	_expect_true(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"death seals the marker on the main")
	return arena


# --- defeat crash pair --------------------------------------------------------
## The file pair left by the real defeat writer — alive seals, then the
## terminal marker — cannot resurrect after one failed primary. Corrupt or
## delete the main and an independent reload still reads ended; the backup
## heals the main forward as terminal. A healthy alive pair still recovers
## from its backup, so the seal rule did not break living recovery.
func _test_actual_defeat_pair_survives_failed_primary() -> void:
	var first: Dictionary = _valid_checkpoint("cb-pair", 1)
	_expect_equal(Journey.write_checkpoint(first), OK,
		"the first alive seal writes")
	var second: Dictionary = _valid_checkpoint("cb-pair", 2)
	_expect_equal(Journey.write_checkpoint(second), OK,
		"the second alive seal writes")
	var sealed: Dictionary = second.duplicate(true)
	sealed["ended"] = true
	_expect_equal(Journey.write_checkpoint(sealed), OK,
		"the real writer seals the defeat")
	_expect_true(bool(_read_json_file(TEST_BACKUP).get("ended", false)),
		"the writer's own pair carries the seal in the backup")

	_write_text(TEST_PATH, "{a corrupt main is not a checkpoint")
	var recovered: Dictionary = Journey.read_checkpoint()
	_expect_true(not recovered.is_empty(),
		"a corrupt main falls back instead of vanishing")
	_expect_true(Journey.is_ended(recovered),
		"the fallback reads ended, never alive")
	_expect_equal(int(recovered.get("checkpoint_id", 0)), 2,
		"the fallback keeps the seal id")
	_expect_false(Journey.has_valid_checkpoint(),
		"the corrupt main offers no free resume")
	_expect_true(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"the fallback heals the main forward as terminal")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var revived: Dictionary = Journey.read_checkpoint()
	_expect_true(Journey.is_ended(revived),
		"a deleted main still reads ended from the backup")
	_expect_false(Journey.has_valid_checkpoint(),
		"the deleted main offers no free resume")

	# Each fallback read above healed the main back; both must go now.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_BACKUP))
	_expect_true(Journey.read_checkpoint().is_empty(),
		"no pair at all reads empty, not alive")
	_expect_false(Journey.has_valid_checkpoint(),
		"no pair at all offers no resume")

	# Control: an alive pair still recovers its run from the backup.
	var alive_first: Dictionary = _valid_checkpoint("cb-alive", 1)
	_expect_equal(Journey.write_checkpoint(alive_first), OK,
		"control: the alive seal writes")
	var alive_second: Dictionary = _valid_checkpoint("cb-alive", 2)
	_expect_equal(Journey.write_checkpoint(alive_second), OK,
		"control: the second alive seal writes")
	_write_text(TEST_PATH, "{a corrupt main is not a checkpoint")
	var living: Dictionary = Journey.read_checkpoint()
	_expect_false(Journey.is_ended(living),
		"control: the alive backup recovers a living run")
	_expect_equal(int(living.get("checkpoint_id", 0)), 1,
		"control: the recovery is the older alive seal")
	_expect_true(Journey.has_valid_checkpoint(),
		"control: living recovery stays resumable")


## The failed primary hides every entry: the production host reports no
## save, and the title shows no Continue. The same title then proves an
## alive pair still offers its run.
func _test_failed_primary_hides_title_and_host_gate() -> void:
	var first: Dictionary = _valid_checkpoint("cb-gate", 1)
	_expect_equal(Journey.write_checkpoint(first), OK,
		"gate: the alive seal writes")
	var sealed: Dictionary = _valid_checkpoint("cb-gate", 1)
	sealed["ended"] = true
	_expect_equal(Journey.write_checkpoint(sealed), OK,
		"gate: the defeat seals")
	_write_text(TEST_PATH, "{a corrupt main is not a checkpoint")
	var summary: Dictionary = ProductionHost.saved_gate_summary()
	_expect_false(bool(summary.get("has_save", true)),
		"gate: the host reports no save for the failed primary")
	_expect_false(bool(summary.get("revive_stuck", true)),
		"gate: no journal means no stuck revive")

	var title: Control = TITLE_SCENE.instantiate() as Control
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = title.get_node("Ui/Screen/JourneyPanel") as Control
	_expect_false(panel.visible,
		"gate: the title shows no Continue for the failed primary")
	_expect_equal(Journey.pending, Journey.Pending.NONE,
		"gate: nothing arms behind the hidden panel")
	title.queue_free()
	await get_tree().process_frame

	# Control: the same title offers a living run after an alive quit.
	_fresh_paths()
	var living: Dictionary = _valid_checkpoint("cb-gate-alive", 3)
	_expect_equal(Journey.write_checkpoint(living), OK,
		"gate control: the alive quit seals")
	var live_title: Control = TITLE_SCENE.instantiate() as Control
	add_child(live_title)
	await get_tree().process_frame
	await get_tree().process_frame
	var live_panel: Control = live_title.get_node(
		"Ui/Screen/JourneyPanel") as Control
	_expect_true(live_panel.visible,
		"gate control: the title offers the living run")
	_expect_true(_find_button(live_panel, "JourneyContinue") != null,
		"gate control: the living run keeps its Continue")
	live_title.queue_free()
	await get_tree().process_frame


# --- paid debit before seal ---------------------------------------------------
## The coin debit is durably acknowledged before the revive seal exists
## anywhere resumable: the journal lands on disk first, the seal
## materializes only from it, and the stable hook fires only for the
## landed seal. A crash between the two recovers exactly one paid
## continuation without another charge; the retry never re-notifies.
func _test_paid_debit_lands_before_seal() -> void:
	Vault.continue_coins = 2
	_expect_equal(Vault.save_vault(), OK, "debit: the purse persists")
	var first: Dictionary = _valid_checkpoint("cb-debit", 1)
	_expect_equal(Journey.write_checkpoint(first), OK,
		"debit: the alive seal writes")
	var second: Dictionary = _valid_checkpoint("cb-debit", 2)
	_expect_equal(Journey.write_checkpoint(second), OK,
		"debit: the last alive seal writes")
	var sealed: Dictionary = second.duplicate(true)
	sealed["ended"] = true
	_expect_equal(Journey.write_checkpoint(sealed), OK,
		"debit: the defeat seals")
	_expect_false(Journey.has_valid_checkpoint(),
		"debit: the sealed run is not resumable")

	Journey.subscribe_stable_checkpoint(_on_stable)
	var revive: Dictionary = _valid_checkpoint("cb-debit", 3)
	_expect_true(Vault.begin_continue_txn("cb-debit", 3,
		JSON.stringify(revive)), "debit: the journaled debit lands")
	_expect_equal(Vault.continue_coins, 1,
		"debit: the journal charges exactly one coin")
	_expect_true(_stable_texts.is_empty(),
		"debit: journaling alone notifies nothing stable")
	_expect_false(Journey.has_valid_checkpoint(),
		"debit: the journal alone resumes nothing")

	# The crash: the purse file cannot be rewritten, then the process
	# dies. A relaunch reloads the acknowledged debit from disk.
	_occupy_as_dir(VAULT_TMP)
	Vault.load_vault()
	_expect_equal(Vault.continue_coins, 1,
		"debit: the reload keeps the acknowledged charge")
	_expect_false((Vault.continue_txn as Dictionary).is_empty(),
		"debit: the reload keeps the journaled seal")
	_expect_equal(Vault.recover_paid_continue(), "recovered",
		"debit: the relaunch materializes the paid seal")
	_expect_equal(_stable_ids(), [3],
		"debit: the hook fires once, for the landed seal")
	_expect_equal(_stable_ended_flags(), [false],
		"debit: the landed seal is alive")
	_expect_true(Journey.has_valid_checkpoint(),
		"debit: the paid seal is resumable")
	_expect_false((Vault.continue_txn as Dictionary).is_empty(),
		"debit: the blocked purse keeps the journal for retry")

	# The retry with a working purse delivers without charging again.
	_release_dir(VAULT_TMP)
	_expect_equal(Vault.recover_paid_continue(), "delivered",
		"debit: the retry delivers the landed seal")
	_expect_equal(Vault.continue_coins, 1,
		"debit: the retry charges no second coin")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"debit: the delivery clears the journal")
	_expect_equal(_stable_ids(), [3],
		"debit: the retry never re-notifies the seal")
	Vault.load_vault()
	_expect_equal(Vault.continue_coins, 1,
		"debit: balance and receipts agree after reload")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"debit: no journal survives the reload")
	Journey.unsubscribe_stable_checkpoint(_on_stable)

	# Control: an alive seal written before any debit is immediately
	# resumable with the coin unspent. A passing control documents the
	# leak the journal-first order exists to close.
	_fresh_paths()
	Vault.continue_coins = 2
	var early: Dictionary = _valid_checkpoint("cb-early", 3)
	Journey.subscribe_stable_checkpoint(_on_stable)
	_expect_equal(Journey.write_checkpoint(early), OK,
		"control: the pre-debit seal writes")
	_expect_equal(_stable_ids(), [3],
		"control: the pre-debit seal notifies while unpaid")
	_expect_true(Journey.has_valid_checkpoint(),
		"control: the pre-debit seal resumes with coins unspent")
	_expect_equal(Vault.continue_coins, 2,
		"control: no coin moved for the early seal")
	Journey.unsubscribe_stable_checkpoint(_on_stable)


# --- double fault ---------------------------------------------------------------
## A blocked purse — alone, then together with failed journey installs —
## keeps the defeat terminal: no alive checkpoint, no stable alive
## payload, no journal, no charge. The retry with working storage then
## revives exactly once.
func _test_double_fault_keeps_terminal_then_retries() -> void:
	Vault.continue_coins = 2
	Vault.save_vault()
	Journey.subscribe_stable_checkpoint(_on_stable)
	var arena: Node2D = await _defeat_arena(2, 1)
	var sealed_id: int = int(
		(arena.get("_journey_snapshot") as Dictionary)["checkpoint_id"])
	_stable_texts.clear()
	# A blocked purse alone already refuses: the debit is attempted before
	# any alive seal exists, so a swapped order would strand a free resume
	# here instead.
	_occupy_as_dir(VAULT_TMP)
	_expect_false(bool(arena.call("continue_run")),
		"double fault: the blocked purse refuses first")
	_expect_equal(Vault.continue_coins, 2,
		"double fault: the blocked purse spends nothing")
	_expect_true(_stable_texts.is_empty(),
		"double fault: the blocked purse notifies nothing")
	_expect_false(Journey.has_valid_checkpoint(),
		"double fault: the blocked purse resumes nothing")
	Journey.install_fault = Journey.InstallFault.FAIL_ALL
	_expect_false(bool(arena.call("continue_run")),
		"double fault: the revive refuses")
	_expect_equal(Vault.continue_coins, 2,
		"double fault: the balance stays whole")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"double fault: no journal survives the refused debit")
	_expect_true(_stable_texts.is_empty(),
		"double fault: no alive payload reaches the hook")
	_expect_true(bool(_read_json_file(TEST_PATH).get("ended", false)),
		"double fault: the main stays sealed")
	_expect_false(Journey.has_valid_checkpoint(),
		"double fault: nothing is resumable")
	_expect_false(bool(ProductionHost.saved_gate_summary().get(
		"has_save", true)),
		"double fault: the host gate stays closed")
	_expect_true(bool(arena.get("_over")),
		"double fault: the arena stays defeated")
	_expect_equal(Vault.recover_paid_continue(), "none",
		"double fault: recovery finds no transaction")

	_release_dir(VAULT_TMP)
	Journey.install_fault = Journey.InstallFault.NONE
	_expect_true(bool(arena.call("continue_run")),
		"double fault: the retry revives")
	_expect_equal(Vault.continue_coins, 1,
		"double fault: the retry debits exactly one coin")
	_expect_equal(int(_read_json_file(TEST_PATH).get("checkpoint_id", 0)),
		sealed_id + 1, "double fault: the retry seals once past the death")
	_expect_equal(_stable_ids(), [sealed_id + 1],
		"double fault: the hook fires once, for the paid seal")
	_expect_true(Journey.has_valid_checkpoint(),
		"double fault: the paid seal is resumable")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"double fault: the landed seal clears the journal")
	Journey.unsubscribe_stable_checkpoint(_on_stable)
	arena.queue_free()
	await get_tree().process_frame


# --- stuck revive -------------------------------------------------------------
## A journaled debit whose seal cannot materialize never boots: the host
## reports a stuck revive instead of a save, and the title asks before
## anything starts. Releasing storage delivers the paid seal without
## another charge; abandoning it instead starts fresh only by confirm.
func _test_stuck_revive_asks_before_boot() -> void:
	Vault.continue_coins = 2
	_expect_equal(Vault.save_vault(), OK, "stuck: the purse persists")
	var first: Dictionary = _valid_checkpoint("cb-stuck", 1)
	_expect_equal(Journey.write_checkpoint(first), OK,
		"stuck: the alive seal writes")
	var sealed: Dictionary = first.duplicate(true)
	sealed["ended"] = true
	_expect_equal(Journey.write_checkpoint(sealed), OK,
		"stuck: the defeat seals")
	var revive: Dictionary = _valid_checkpoint("cb-stuck", 2)
	_expect_true(Vault.begin_continue_txn("cb-stuck", 2,
		JSON.stringify(revive)), "stuck: the debit journals")
	_expect_equal(Vault.continue_coins, 1,
		"stuck: the journal charges exactly one coin")
	Journey.install_fault = Journey.InstallFault.FAIL_ALL

	var summary: Dictionary = ProductionHost.saved_gate_summary()
	_expect_false(bool(summary.get("has_save", true)),
		"stuck: the host offers no save")
	_expect_true(bool(summary.get("revive_stuck", false)),
		"stuck: the host names the stuck revive")
	_expect_false(Journey.has_valid_checkpoint(),
		"stuck: the sealed run is not resumable")

	var title: Control = TITLE_SCENE.instantiate() as Control
	add_child(title)
	title.start_requested.disconnect(Callable(title, "_enter_arena"))
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = title.get_node("Ui/Screen/JourneyPanel") as Control
	_expect_true(panel.visible, "stuck: the title names the failure")
	var resume_button: Button = _find_button(panel, "JourneyContinue")
	_expect_true(resume_button != null
		and not resume_button.is_visible_in_tree(),
		"stuck: no Continue boots the unopenable seal")
	var erase_button: Button = _find_button(panel, "JourneyErase")
	_expect_false(erase_button.is_visible_in_tree(),
		"stuck: the confirm waits for an explicit tap")
	title.request_start()
	await get_tree().process_frame
	_expect_true(erase_button.is_visible_in_tree(),
		"stuck: the tap asks instead of booting")
	_expect_equal(Journey.pending, Journey.Pending.NONE,
		"stuck: the tap arms no resume")
	_expect_false(Journey.armed, "stuck: the tap arms no writes")

	# Releasing storage delivers the paid seal without another charge.
	Journey.install_fault = Journey.InstallFault.NONE
	_expect_equal(Vault.recover_paid_continue(), "recovered",
		"stuck: released storage materializes the paid seal")
	_expect_equal(Vault.continue_coins, 1,
		"stuck: the delivery charges no second coin")
	_expect_true(Journey.has_valid_checkpoint(),
		"stuck: the paid seal is resumable")
	title.queue_free()
	await get_tree().process_frame

	# Abandoning the stuck revive instead starts fresh only by confirm.
	_fresh_paths()
	Vault.continue_coins = 2
	Vault.save_vault()
	var doomed: Dictionary = _valid_checkpoint("cb-abandon", 1)
	doomed["ended"] = true
	_expect_equal(Journey.write_checkpoint(doomed), OK,
		"stuck: the second defeat seals")
	var doomed_revive: Dictionary = _valid_checkpoint("cb-abandon", 2)
	_expect_true(Vault.begin_continue_txn("cb-abandon", 2,
		JSON.stringify(doomed_revive)), "stuck: the second debit journals")
	Journey.install_fault = Journey.InstallFault.FAIL_ALL
	var second: Control = TITLE_SCENE.instantiate() as Control
	add_child(second)
	second.start_requested.disconnect(Callable(second, "_enter_arena"))
	await get_tree().process_frame
	await get_tree().process_frame
	var second_panel: Control = second.get_node(
		"Ui/Screen/JourneyPanel") as Control
	_find_button(second_panel, "JourneyNew").pressed.emit()
	await get_tree().process_frame
	_expect_equal(Journey.pending, Journey.Pending.NONE,
		"stuck: asking alone starts nothing")
	Journey.install_fault = Journey.InstallFault.NONE
	_find_button(second_panel, "JourneyErase").pressed.emit()
	_expect_equal(Journey.pending, Journey.Pending.FRESH,
		"stuck: the confirmed erase starts fresh")
	_expect_true(Journey.armed, "stuck: the fresh start arms writes")
	# The confirmed boot is a real fresh arena: a new journey, the first
	# cycle, the moot journal cleared, the abandoned coin untouched.
	var booted: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(booted)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(int(booted.get("_cycle")), 1,
		"stuck: the fresh boot begins the first cycle")
	_expect_false(str(booted.get("_journey_id")) == "cb-abandon",
		"stuck: the fresh boot leaves the doomed journey behind")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"stuck: the fresh boot clears the moot journal")
	_expect_equal(Vault.continue_coins, 1,
		"stuck: the abandoned coin is neither refunded nor double-spent")
	booted.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	second.queue_free()
	await get_tree().process_frame
	await _claim_threaded_arena("Stuck erase")
	Journey.disarm()


# --- double tap -----------------------------------------------------------------
## Two rapid taps on the result screen revive once: the first debits one
## coin and seals one past the death, the second finds a living run and
## spends nothing.
func _test_double_tap_debits_once() -> void:
	Vault.continue_coins = 2
	Journey.subscribe_stable_checkpoint(_on_stable)
	var arena: Node2D = await _defeat_arena(3, 0)
	var sealed_id: int = int(
		(arena.get("_journey_snapshot") as Dictionary)["checkpoint_id"])
	_stable_texts.clear()
	_expect_true(bool(arena.call("continue_run")),
		"double tap: the first tap revives")
	_expect_false(bool(arena.call("continue_run")),
		"double tap: the second tap finds a living run")
	_expect_equal(Vault.continue_coins, 1,
		"double tap: exactly one coin moves")
	_expect_equal(int(_read_json_file(TEST_PATH).get("checkpoint_id", 0)),
		sealed_id + 1, "double tap: exactly one seal lands past the death")
	_expect_equal(_stable_ids(), [sealed_id + 1],
		"double tap: the hook fires exactly once")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"double tap: no journal survives the revive")
	_expect_equal(int(arena.get("_analytics_continues")), 1,
		"double tap: the run counts one continuation")
	Journey.unsubscribe_stable_checkpoint(_on_stable)
	arena.queue_free()
	await get_tree().process_frame


# --- expectations ---------------------------------------------------------------
func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("FAIL: ", label)


func _expect_false(value: bool, label: String) -> void:
	_expect_true(not value, label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		_failed += 1
		printerr("FAIL: ", label, " — got ", actual, ", want ", expected)
