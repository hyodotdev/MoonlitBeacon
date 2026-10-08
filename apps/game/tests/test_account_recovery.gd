extends Node

## Paid revive recovery stays in its owning account: a journaled debit
## materializes only in the slot that paid it, a pending receipt survives
## other accounts' play, and the loss-result button retries its own paid
## revive instead of sending a broke player to the shop.
##
## The director reproduced the transfer with the real journal API: seal
## under A, journal the debit, switch to empty B, and recovery wrote A's
## alive checkpoint into B's slot while clearing A's receipt. These pin the
## owner binding with real account slots, reloads, switches, late cloud
## hooks, B-side fresh play and B-side paid continue, the switch back to A,
## and the real result-button signal route. Uses throwaway account slots,
## so no human save is touched. The Vault autoload is real but isolated.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_panel.tscn")
const OWNER_A: String = "MB-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const OWNER_B: String = "MB-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const OWNER_C: String = "MB-cccccccccccccccccccccccccccccccc"
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
	_fresh_slots()
	_test_cross_account_recovery_defers()
	_fresh_slots()
	_test_b_plays_while_a_pends()
	_fresh_slots()
	_test_same_attempt_validates_exact_seal()
	_fresh_slots()
	await _test_result_button_retries_paid_revive()
	_fresh_slots()
	_test_owner_primitives()

	_restore_slots()
	Journey.disarm()
	if _failed > 0:
		printerr("account recovery tests failed — ", _failed, "/", _checked,
			" case(s)")
		get_tree().quit(1)
		return
	print("account recovery tests passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("account recovery tests aborted: user:// path is not isolated — ", user_root)
	return safe


func _wipe_slot(owner: String) -> void:
	for candidate in [Journey.account_main_path(owner),
			Journey.account_backup_path(owner),
			Journey.account_main_path(owner) + ".tmp",
			Journey.account_backup_path(owner) + ".tmp",
			Journey.account_revision_path(owner),
			Journey.account_rejected_path(owner, "local"),
			Journey.account_rejected_path(owner, "remote")]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _fresh_slots() -> void:
	_wipe_slot(OWNER_A)
	_wipe_slot(OWNER_B)
	Journey.use_account("")
	Journey.clear_stable_hooks()
	_stable_texts.clear()
	Vault.continue_coins = 2
	Vault.continue_txn = {}
	if Vault.get("continue_txn_parked") is Dictionary:
		Vault.set("continue_txn_parked", {})
	Vault.save_vault()
	Journey.disarm()
	Journey.last_error = ""
	Journey.install_fault = Journey.InstallFault.NONE
	RunEntry.from_title = false
	get_tree().paused = false


func _restore_slots() -> void:
	_wipe_slot(OWNER_A)
	_wipe_slot(OWNER_B)
	Journey.use_account("")
	Journey.clear_stable_hooks()
	_stable_texts.clear()
	Vault.continue_txn = {}
	if Vault.get("continue_txn_parked") is Dictionary:
		Vault.set("continue_txn_parked", {})
	Journey.disarm()
	Journey.last_error = ""
	Journey.install_fault = Journey.InstallFault.NONE
	RunEntry.from_title = false
	get_tree().paused = false


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


func _on_stable(info: Dictionary) -> void:
	_stable_texts.append(str(info.get("text", "")))


## Checkpoint id of the current scope's journaled entry, or -1 when the
## scoping API is absent (pre-fix) or nothing pends. Keeps the suite
## runnable — failing, not aborting — before the fix lands.
func _scoped_cid() -> int:
	var scoped: Variant = Vault.call("scoped_continue_txn")
	if not scoped is Dictionary:
		return -1
	return int((scoped as Dictionary).get("checkpoint_id", 0))


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


## The seal/journal round trip one paid revive pays for: alive seals, the
## terminal marker, then the journaled debit — all through the real API.
func _seal_and_journal(owner: String, journey: String, seal_id: int,
		revive_id: int) -> void:
	Journey.use_account(owner)
	var alive: Dictionary = _valid_checkpoint(journey, seal_id)
	_expect_equal(Journey.write_checkpoint(alive), OK,
		"the alive seal writes")
	var sealed: Dictionary = alive.duplicate(true)
	sealed["ended"] = true
	_expect_equal(Journey.write_checkpoint(sealed), OK,
		"the defeat seals")
	var revive: Dictionary = _valid_checkpoint(journey, revive_id)
	_expect_true(Vault.begin_continue_txn(journey, revive_id,
		JSON.stringify(revive)), "the debit journals")


# --- cross-account deferral ---------------------------------------------------
## The director's probe, registered: a debit journaled under A, reloaded,
## then met in B's empty slot defers without touching B's files, without
## notifying, and without consuming A's receipt. A late cloud hook stays
## silent until A itself recovers exactly one paid revive.
func _test_cross_account_recovery_defers() -> void:
	Vault.continue_coins = 2
	Vault.save_vault()
	_seal_and_journal(OWNER_A, "probe-a-1", 5, 6)
	_expect_equal(Vault.continue_coins, 1,
		"defer: the journal charges exactly one coin")
	Vault.load_vault()
	_expect_equal(Vault.continue_coins, 1,
		"defer: the reload keeps the acknowledged charge")
	_expect_false((Vault.continue_txn as Dictionary).is_empty(),
		"defer: the reload keeps the journaled seal")
	var seal_text: String = str(
		(Vault.continue_txn as Dictionary).get("seal", ""))

	Journey.use_account(OWNER_B)
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(OWNER_B)),
		"defer: B's slot starts empty")
	Journey.subscribe_stable_checkpoint(_on_stable)
	_expect_equal(Vault.recover_paid_continue(), "deferred",
		"defer: recovery on another account defers")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(OWNER_B)),
		"defer: nothing imports into B's main")
	_expect_false(FileAccess.file_exists(
		Journey.account_backup_path(OWNER_B)),
		"defer: nothing imports into B's backup")
	_expect_true(_stable_texts.is_empty(),
		"defer: the late hook hears nothing for B")
	_expect_equal(Vault.continue_coins, 1,
		"defer: the balance is untouched")
	_expect_false((Vault.continue_txn as Dictionary).is_empty(),
		"defer: A's receipt survives")
	_expect_equal(str((Vault.continue_txn as Dictionary).get(
		"owner", Journey.active_account)), OWNER_A,
		"defer: the receipt still names A")
	_expect_false(Journey.has_valid_checkpoint(),
		"defer: B's empty slot offers no resume")

	# The settle itself refuses foreign receipts, not just the Vault
	# wrapper: a direct call with A's entry defers without writing.
	var foreign: Dictionary = {"owner": OWNER_A,
		"journey_id": "probe-a-1", "checkpoint_id": 6, "seal": seal_text}
	_expect_equal(Journey.settle_continue_txn(foreign), "deferred",
		"defer: a direct settle of a foreign receipt defers")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(OWNER_B)),
		"defer: the direct settle writes nothing into B")

	# Back in A's scope the same receipt settles exactly once.
	Journey.use_account(OWNER_A)
	_expect_equal(Vault.recover_paid_continue(), "recovered",
		"defer: A materializes its paid seal")
	_expect_equal(_stable_ids(), [6],
		"defer: the late hook fires once, for A's seal")
	_expect_equal(Vault.continue_coins, 1,
		"defer: the materialize charges no second coin")
	_expect_true(Journey.has_valid_checkpoint(),
		"defer: A's paid seal is resumable")
	_expect_equal(int(Journey.read_checkpoint().get("checkpoint_id", 0)), 6,
		"defer: A's revive is the correct original seal")
	Journey.unsubscribe_stable_checkpoint(_on_stable)


# --- b plays while a pends ----------------------------------------------------
## A's pending receipt survives B starting, playing, quitting and
## continuing its own run: B's fresh start never clears it, B's files stay
## byte-identical across B-side recovery, and both attempts settle
## independently with exactly one debit each.
func _test_b_plays_while_a_pends() -> void:
	Vault.continue_coins = 2
	Vault.save_vault()
	_seal_and_journal(OWNER_A, "stays-a-1", 5, 6)
	_expect_equal(Vault.continue_coins, 1,
		"B-side: A's debit lands first")

	# B starts fresh: a new journey in B's scope must not abandon A's
	# receipt, which only a confirmed fresh action in A's scope clears.
	Journey.use_account(OWNER_B)
	Vault.begin_journey()
	_expect_false((Vault.continue_txn as Dictionary).is_empty(),
		"B-side: B's fresh start keeps A's receipt")
	_expect_equal(Vault.continue_coins, 1,
		"B-side: B's fresh start charges nothing")

	# B plays and quits. Recovery in B defers to A and leaves B's own
	# living files byte-identical.
	var first: Dictionary = _valid_checkpoint("runs-b-1", 1)
	first["cycle"] = 2
	_expect_equal(Journey.write_checkpoint(first), OK,
		"B-side: B's run seals")
	var second: Dictionary = _valid_checkpoint("runs-b-1", 2)
	second["cycle"] = 2
	_expect_equal(Journey.write_checkpoint(second), OK,
		"B-side: B's run seals again")
	Vault.load_vault()
	var main_before: String = FileAccess.get_file_as_string(
		Journey.account_main_path(OWNER_B))
	var backup_before: String = FileAccess.get_file_as_string(
		Journey.account_backup_path(OWNER_B))
	_expect_equal(Vault.recover_paid_continue(), "deferred",
		"B-side: B's recovery defers to A")
	_expect_equal(FileAccess.get_file_as_string(
		Journey.account_main_path(OWNER_B)), main_before,
		"B-side: B's main is byte-identical")
	_expect_equal(FileAccess.get_file_as_string(
		Journey.account_backup_path(OWNER_B)), backup_before,
		"B-side: B's backup is byte-identical")
	_expect_true(Journey.has_valid_checkpoint(),
		"B-side: B's living run stays resumable")

	# B continues its own run: its own debit, its own seal, A's receipt
	# still parked beside it.
	var sealed_b: Dictionary = second.duplicate(true)
	sealed_b["ended"] = true
	_expect_equal(Journey.write_checkpoint(sealed_b), OK,
		"B-side: B's defeat seals")
	var revived_b: Dictionary = _valid_checkpoint("runs-b-1", 3)
	revived_b["cycle"] = 2
	_expect_true(Vault.begin_continue_txn("runs-b-1", 3,
		JSON.stringify(revived_b)), "B-side: B's debit journals")
	_expect_equal(Vault.continue_coins, 0,
		"B-side: B's debit is its own coin")
	_expect_equal(Vault.recover_paid_continue(), "recovered",
		"B-side: B materializes its paid seal")
	_expect_true(Journey.has_valid_checkpoint(),
		"B-side: B's paid seal is resumable")
	_expect_equal(int(Journey.read_checkpoint().get("checkpoint_id", 0)), 3,
		"B-side: B's revive is B's own seal")
	_expect_equal(Vault.continue_coins, 0,
		"B-side: B's materialize charges nothing more")

	# Back in A: the original receipt settles as the one paid revive.
	Journey.use_account(OWNER_A)
	_expect_equal(Vault.recover_paid_continue(), "recovered",
		"B-side: A materializes afterwards")
	_expect_equal(int(Journey.read_checkpoint().get("checkpoint_id", 0)), 6,
		"B-side: A's revive is the correct original seal")
	_expect_equal(Vault.continue_coins, 0,
		"B-side: two debits total, one per account, none doubled")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"B-side: no journal survives both settlements")
	Vault.load_vault()
	_expect_equal(Vault.continue_coins, 0,
		"B-side: balance and receipts agree after reload")


# --- exact same-attempt validation ---------------------------------------------
## Retrying the same numbers with different seal bytes is not the
## acknowledged transaction: it refuses without charging or overwriting.
## The exact retry still rides free, and the same numbers in another scope
## are a new debit — never a free ride on A's coin.
func _test_same_attempt_validates_exact_seal() -> void:
	Vault.continue_coins = 2
	Vault.save_vault()
	Journey.use_account(OWNER_A)
	var revive: Dictionary = _valid_checkpoint("exact-a-1", 6)
	_expect_true(Vault.begin_continue_txn("exact-a-1", 6,
		JSON.stringify(revive)), "exact: the debit journals")
	_expect_equal(Vault.continue_coins, 1,
		"exact: the journal charges exactly one coin")
	var rival: Dictionary = _valid_checkpoint("exact-a-1", 6)
	rival["kill_score"] = 99999
	_expect_false(Vault.begin_continue_txn("exact-a-1", 6,
		JSON.stringify(rival)),
		"exact: rival bytes for the same numbers refuse")
	_expect_equal(Vault.continue_coins, 1,
		"exact: the refusal charges nothing")
	_expect_equal(str((Vault.continue_txn as Dictionary).get(
		"seal", "")), JSON.stringify(revive),
		"exact: the refusal overwrites nothing")
	_expect_true(Vault.begin_continue_txn("exact-a-1", 6,
		JSON.stringify(revive)),
		"exact: the byte-identical retry rides free")
	_expect_equal(Vault.continue_coins, 1,
		"exact: the free retry charges nothing")

	# The same numbers under B are B's own attempt, not A's receipt.
	Journey.use_account(OWNER_B)
	_expect_true(Vault.begin_continue_txn("exact-a-1", 6,
		JSON.stringify(revive)),
		"exact: B's same-numbered attempt journals separately")
	_expect_equal(Vault.continue_coins, 0,
		"exact: B's attempt spends B's coin, not A's receipt")


# --- result button retries its paid revive ---------------------------------------
## The real loss-result button: one coin, a real defeat, a failed alive
## install. The debit spent the last coin into the journal; the reopened
## panel must offer a save retry — not the shop — and the retry must
## revive without charging again. A true zero balance with no receipt
## still routes to the shop.
func _test_result_button_retries_paid_revive() -> void:
	Journey.use_account(OWNER_A)
	Vault.continue_coins = 1
	Vault.save_vault()
	Journey.begin_fresh()
	RunEntry.mark_from_title()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.set("_cycle", 2)
	arena.set("_zone_index", 1)
	_expect_true(bool(arena.call("_journey_checkpoint", true)),
		"button: the gate seals before the death")
	arena.call("_finish", false)
	await get_tree().process_frame
	_expect_true(bool(arena.get("_over")), "button: the run is over")

	Journey.install_fault = Journey.InstallFault.FAIL_ALL
	_expect_false(bool(arena.call("continue_run")),
		"button: the install failure refuses the revive")
	_expect_equal(Vault.continue_coins, 0,
		"button: the last coin sits in the journal")
	_expect_false((Vault.continue_txn as Dictionary).is_empty(),
		"button: the paid revive pends")
	var panel: Control = arena.get_node("Ui/Result") as Control
	panel.reopen_after_failed_continue()
	await get_tree().process_frame
	var retry_button: Button = panel.get_node("Actions/Continue") as Button
	_expect_equal(retry_button.text, tr("RESULT_CONTINUE_RETRY"),
		"button: the broke panel offers a save retry")
	var routes: Dictionary = {"continue": 0, "purchase": 0}
	panel.continue_requested.connect(
		func() -> void: routes["continue"] += 1)
	panel.continue_purchase_requested.connect(
		func() -> void: routes["purchase"] += 1)
	# The shop route would swap the test scene away; unhook the swap and
	# keep the emission itself as the assertion, like the probe.
	panel.continue_purchase_requested.disconnect(
		Callable(arena, "_on_continue_purchase_requested"))
	retry_button.pressed.emit()
	await get_tree().process_frame
	_expect_equal(int(routes["continue"]), 1,
		"button: the tap retries the paid revive")
	_expect_equal(int(routes["purchase"]), 0,
		"button: the tap never routes to the shop")
	_expect_true(bool(arena.get("_over")),
		"button: the blocked retry stays defeated")

	Journey.install_fault = Journey.InstallFault.NONE
	retry_button.pressed.emit()
	await get_tree().process_frame
	_expect_equal(int(routes["continue"]), 2,
		"button: the released tap retries again")
	_expect_false(bool(arena.get("_over")),
		"button: the released retry revives")
	_expect_equal(Vault.continue_coins, 0,
		"button: the recovery never charges again")
	_expect_true(Journey.has_valid_checkpoint(),
		"button: the revived run is resumable")
	arena.queue_free()
	await get_tree().process_frame

	# Control: a true zero balance with no receipt still goes to the shop.
	_fresh_slots()
	Journey.use_account(OWNER_A)
	Vault.continue_coins = 0
	var bare: Control = RESULT_SCENE.instantiate() as Control
	add_child(bare)
	await get_tree().process_frame
	var bare_routes: Dictionary = {"continue": 0, "purchase": 0}
	bare.continue_requested.connect(
		func() -> void: bare_routes["continue"] += 1)
	bare.continue_purchase_requested.connect(
		func() -> void: bare_routes["purchase"] += 1)
	bare.reopen_after_failed_continue()
	await get_tree().process_frame
	var buy_button: Button = bare.get_node("Actions/Continue") as Button
	_expect_equal(buy_button.text, tr("RESULT_CONTINUE_BUY"),
		"control: the receiptless panel still offers the shop")
	buy_button.pressed.emit()
	await get_tree().process_frame
	_expect_equal(int(bare_routes["continue"]), 0,
		"control: no receipt retries nothing")
	_expect_equal(int(bare_routes["purchase"]), 1,
		"control: the broke tap routes to the shop")
	bare.queue_free()
	await get_tree().process_frame


# --- owner primitives ----------------------------------------------------------------
## The Vault-level moves the account flows build on: scoping reads to the
## active slot, rekeying an entry when its slot moves, and clearing only
## the deleted account's entry.
func _test_owner_primitives() -> void:
	Vault.continue_coins = 2
	Vault.save_vault()
	_seal_and_journal(OWNER_A, "prim-a-1", 5, 6)
	Journey.use_account(OWNER_B)
	_seal_and_journal(OWNER_B, "prim-b-1", 2, 3)
	_expect_equal(Vault.continue_coins, 0,
		"primitives: both debits land")
	_expect_equal(_scoped_cid(), 3,
		"primitives: the scoped read sees B's entry")
	Journey.use_account(OWNER_A)
	_expect_equal(_scoped_cid(), 6,
		"primitives: the scoped read sees A's entry")

	# Rekey follows a slot move: onto an empty target it carries the
	# entry; onto an occupied one it refuses and keeps both.
	_expect_true(bool(Vault.call("rekey_continue_txn_owner",
		OWNER_A, OWNER_C)), "primitives: A rekeys onto empty C")
	_expect_equal(_scoped_cid(), 0,
		"primitives: A keeps nothing after the move")
	Journey.use_account(OWNER_C)
	_expect_equal(_scoped_cid(), 6,
		"primitives: the moved entry settles under C")
	Vault.load_vault()
	Journey.use_account(OWNER_C)
	_expect_equal(_scoped_cid(), 6,
		"primitives: the rekey survives reload")
	_expect_false(bool(Vault.call("rekey_continue_txn_owner",
		OWNER_C, OWNER_B)),
		"primitives: rekey onto occupied B refuses")
	Journey.use_account(OWNER_B)
	_expect_equal(_scoped_cid(), 3,
		"primitives: the refusal keeps B's entry")
	Journey.use_account(OWNER_C)
	_expect_equal(_scoped_cid(), 6,
		"primitives: the refusal keeps C's entry")

	_expect_true(bool(Vault.call("clear_continue_txn_for_owner",
		OWNER_C)), "primitives: deleting C clears C's entry")
	_expect_equal(_scoped_cid(), 0,
		"primitives: C's entry is gone")
	Journey.use_account(OWNER_B)
	_expect_equal(_scoped_cid(), 3,
		"primitives: the deletion spares B's entry")
	Vault.load_vault()
	Journey.use_account(OWNER_C)
	_expect_equal(_scoped_cid(), 0,
		"primitives: the deletion survives reload")
	Journey.use_account(OWNER_B)
	_expect_equal(_scoped_cid(), 3,
		"primitives: B's entry survives the reload too")


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
