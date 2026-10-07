extends Node

## Production host scene tests: durable ID boot, canonical adoption,
## offline guest, provider conflicts, login-error lifetime across duplicate
## signals, local-guest escape from the Error screen, token retirement,
## save choice, entry planning, menus, back/cancel, and HUD labels.
##
## Scene-based because the host bridges the Vault autoload and the Journey
## globals. Every service the host would reach over the process boundary
## is injected: the fake identity adapter and the fake cloud sender live
## ONLY in this test. Production builds the real ones and never calls
## `inject_services`.
##
## Call directly; the later tooling task owns shared-runner registration:
## `pnpm godot:isolated --timeout 300 res://tests/test_production_host.tscn`

const HOST_SCRIPT: Script = preload("res://scripts/net/production_host.gd")
const ACCOUNT_SCRIPT: Script = preload("res://scripts/net/player_account.gd")
const FAKE_ADAPTER_SCRIPT: Script = preload(
	"res://tests/support/fake_identity_adapter.gd")
const FAKE_SENDER_SCRIPT: Script = preload(
	"res://tests/support/fake_cloud_sender.gd")
const COORD_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_coordinator.gd")
const ENTRY_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")

const ID_PATH: String = "user://prod_host_identity.cfg"
const BIND_PATH: String = "user://prod_host_bindings.cfg"
const SHARP_MOON: String = "res://resources/relics/sharp_moon.tres"
const UID_A: String = "uid-prod-alice"
const UID_B: String = "uid-prod-bob"
const CANON_C: String = "MB-cccccccccccccccccccccccccccccccc"
const CANON_D: String = "MB-dddddddddddddddddddddddddddddddd"
const OTHER_ID: String = "MB-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
const SECRET_TOKEN: String = "tok-prod-secret-9f8e7d"

var _failed: int = 0
var _checked: int = 0
var _fired: Dictionary = {}


class CapableFake extends "res://tests/support/fake_identity_adapter.gd":
	var capabilities: Dictionary = {
		"status": STATUS_OK,
		"supported": true,
		"providers": [
			{"id": "play_games", "label": "Play Games", "ready": true},
			{"id": "apple", "label": "Apple", "ready": false},
		],
		"guest": true,
	}

	func get_capabilities() -> Dictionary:
		return capabilities.duplicate(true)


class DelayedSender extends RefCounted:
	var replies: Array = []
	var calls: Array = []
	var delay_frames: int = 3
	var tree_node: Node

	func queue_ok(body: String = "{}") -> void:
		replies.append({"transport": "ok", "code": 200, "body": body})

	func queue_reply(reply: Dictionary) -> void:
		replies.append(reply.duplicate(true))

	func send(method: String, url: String, _headers: Dictionary,
			_body: String) -> Dictionary:
		calls.append({"method": method, "url": url})
		for _index in delay_frames:
			await tree_node.get_tree().process_frame
		if not replies.is_empty():
			return (replies.pop_front() as Dictionary).duplicate(true)
		return {"transport": "ok", "code": 200, "body": "{}"}

	func reset() -> void:
		replies.clear()
		calls.clear()


class FakeClock extends RefCounted:
	var now: int = 0

	func now_msec() -> int:
		return now

	func advance(msec: int) -> void:
		now += msec


## Recorder stand-in for the cloud coordinator on the four name routes.
## Records every call without touching the wire; `hold_frames` parks the
## reply so a test can retire the account mid-call and observe the stale
## completion. Never emits: the host wires its signals like the real one.
class NameRecorder extends Node:
	signal account_changed(snapshot: Dictionary)
	signal save_changed(snapshot: Dictionary)
	signal conflict_found(info: Dictionary)
	signal hall_changed(snapshot: Dictionary)
	signal rank_changed(snapshot: Dictionary)
	signal attendance_changed(snapshot: Dictionary)
	signal dispatched

	var calls: Array = []
	var hold_frames: int = 0
	var tree_node: Node

	func close() -> void:
		pass

	# Inert stubs for production paths that can reach the live
	# coordinator outside the name routes (snapshots for account state,
	# a deferred best-submit from a late save ack). Only the four name
	# routes below record; these never touch the wire.
	func account_snapshot() -> Dictionary:
		return {"state": "unconfigured"}

	func save_snapshot() -> Dictionary:
		return {"state": "unconfigured"}

	func hall_snapshot() -> Dictionary:
		return {"state": "unregistered", "source": "unregistered",
			"rows": []}

	func rank_snapshot() -> Dictionary:
		return {"state": "unregistered", "source": "unregistered",
			"rank": 0, "score": 0}

	func conflict_snapshot() -> Dictionary:
		return {}

	func submit_current_best() -> Dictionary:
		return {"status": "cancelled", "code": "recorder",
			"retryable": false}

	func refresh_rank() -> Dictionary:
		return {"status": "cancelled", "code": "recorder",
			"retryable": false}

	func refresh_board(_limit: int = 20) -> Dictionary:
		return {"status": "cancelled", "code": "recorder",
			"retryable": false}

	func claim_adventurer_name(display: String) -> Dictionary:
		calls.append({"route": "claim", "display": display})
		dispatched.emit()
		await _hold()
		return {"status": "ok", "display": display,
			"key": str(display).to_lower(), "intro_complete": false,
			"cached": true, "backfilled": false,
			"backfill_code": "no-row"}

	func fetch_adventurer_name() -> Dictionary:
		calls.append({"route": "load"})
		dispatched.emit()
		await _hold()
		return {"status": "ok", "display": "Alpha", "key": "alpha",
			"intro_complete": false, "cached": true, "source": "cloud"}

	func complete_intro() -> Dictionary:
		calls.append({"route": "intro"})
		dispatched.emit()
		await _hold()
		return {"status": "ok", "display": "Alpha", "key": "alpha",
			"intro_complete": true, "cached": true, "source": "cloud"}

	func backfill_hall_name() -> Dictionary:
		calls.append({"route": "backfill"})
		dispatched.emit()
		await _hold()
		return {"status": "ok", "code": "no-row", "backfilled": false}

	func claim_attendance() -> Dictionary:
		calls.append({"route": "attendance"})
		dispatched.emit()
		await _hold()
		return {"status": "granted",
			"receipt": "attendance:stub:1:stub", "coins": 2,
			"granted": true, "duplicate": false,
			"next_eligible_utc": "2026-10-07T22:00:00Z",
			"remaining_seconds": 43200}

	func attendance_snapshot() -> Dictionary:
		return {"state": "unregistered", "source": "none",
			"public_id": "", "receipt": "",
			"last_claim_utc": "", "next_eligible_utc": "",
			"remaining_seconds": -1}

	func _hold() -> void:
		for _index in hold_frames:
			await tree_node.get_tree().process_frame


class RoutedSender extends RefCounted:
	var calls: Array = []
	var delay_frames: int = 3
	var tree_node: Node
	var profile_bodies: Dictionary = {}
	var checkpoint_replies: Array = []
	var in_flight: int = 0

	func queue_profile(uid: String, body: String) -> void:
		profile_bodies[uid] = body

	func queue_checkpoint_ok(body: String) -> void:
		checkpoint_replies.append(
			{"transport": "ok", "code": 200, "body": body})

	func queue_checkpoint_not_found() -> void:
		checkpoint_replies.append(
			{"transport": "ok", "code": 404, "body": "{}"})

	func queue_checkpoint_reply(reply: Dictionary) -> void:
		checkpoint_replies.append(reply.duplicate(true))

	func send(method: String, url: String, _headers: Dictionary,
			_body: String) -> Dictionary:
		calls.append({"method": method, "url": url})
		in_flight += 1
		for _index in delay_frames:
			await tree_node.get_tree().process_frame
		in_flight -= 1
		if url.contains("mb_checkpoints_v1"):
			if not checkpoint_replies.is_empty():
				return (checkpoint_replies.pop_front() as Dictionary
					).duplicate(true)
			return {"transport": "ok", "code": 404, "body": "{}"}
		if url.contains("mb_profiles_v1"):
			for uid in profile_bodies.keys():
				if url.contains(str(uid)):
					return {"transport": "ok", "code": 200,
						"body": str(profile_bodies[uid])}
		# Rank, hall, and any other follower: an authoritative empty that
		# can never steal a scripted reply, so completion order between
		# the check and its followers never matters.
		return {"transport": "ok", "code": 404, "body": "{}"}

	func reset() -> void:
		profile_bodies.clear()
		checkpoint_replies.clear()
		calls.clear()


class HungSender extends RefCounted:
	var calls: Array = []
	var tree_node: Node
	var profile_bodies: Dictionary = {}
	var checkpoint_releases: Dictionary = {}
	var _checkpoint_seen: int = 0

	func queue_profile(uid: String, body: String) -> void:
		profile_bodies[uid] = body

	func release_checkpoint_call(number: int, reply: Dictionary) -> void:
		checkpoint_releases[number] = reply.duplicate(true)

	func send(method: String, url: String, _headers: Dictionary,
			_body: String) -> Dictionary:
		calls.append({"method": method, "url": url})
		if url.contains("mb_checkpoints_v1"):
			_checkpoint_seen += 1
			var mine: int = _checkpoint_seen
			while not checkpoint_releases.has(mine):
				await tree_node.get_tree().process_frame
			return (checkpoint_releases[mine] as Dictionary
				).duplicate(true)
		if url.contains("mb_profiles_v1"):
			for uid in profile_bodies.keys():
				if url.contains(str(uid)):
					return {"transport": "ok", "code": 200,
						"body": str(profile_bodies[uid])}
		return {"transport": "ok", "code": 404, "body": "{}"}

	func reset() -> void:
		profile_bodies.clear()
		checkpoint_releases.clear()
		_checkpoint_seen = 0
		calls.clear()


func _ready() -> void:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path(
		"user://").simplify_path()
	if expected_root.is_empty() or not user_root.begins_with(
			expected_root + "/"):
		printerr("production host tests aborted: user:// path is not isolated — ",
			user_root)
		get_tree().quit(2)
		return
	GateEntryStrings.ensure_loaded()
	_run.call_deferred()


func _run() -> void:
	_wipe_all()
	await _test_boot_mints_id_before_play()
	await _test_restart_keeps_id()
	await _test_corrupt_identity_refuses_readiness()
	await _test_canonical_adoption_durable()
	await _test_adoption_rekey_failure_stays_guest_then_retries()
	await _test_legacy_paid_adoption_recovers()
	await _test_adoption_occupied_canonical_preserves_guest()
	await _test_adoption_crash_between_rekey_and_move()
	await _test_adoption_target_receipt_without_source_receipt()
	await _test_adoption_occupied_target_without_source_receipt()
	await _test_claim_name_caches_and_backfills_nothing()
	await _test_claim_taken_keeps_identity()
	await _test_local_guest_cannot_claim()
	await _test_linking_keeps_claimed_name()
	await _test_intro_complete_and_reload()
	await _test_claim_backfills_existing_best()
	await _test_submit_best_carries_handle()
	await _test_claim_restore_keeps_completion_bit()
	await _test_name_wrappers_cancel_on_token_switch()
	await _test_claim_token_failure_sends_nothing()
	await _test_claim_token_timeout_sends_nothing()
	await _test_claim_shutdown_mid_wait_cancels()
	await _test_claim_stale_completion_cancels()
	await _test_claim_retirement_mid_wait_cancels()
	await _test_claim_cancelled_across_failed_deletion()
	await _test_claim_cancelled_by_earlier_failed_deletion()
	await _test_claim_refused_while_deletion_in_flight()
	await _test_attendance_first_claim_grants_two()
	await _test_attendance_cooldown_grants_nothing()
	await _test_attendance_same_install_recovers_after_uncertain_ack()
	await _test_attendance_wallet_failure_recovers()
	await _test_attendance_request_skips_and_double_tap()
	await _test_attendance_receipt_flush_and_suppression()
	await _test_attendance_foreground_and_offline_cache()
	await _test_attendance_link_keeps_record()
	await _test_attendance_cancelled_across_failed_deletion()
	await _test_attendance_refused_while_deletion_in_flight()
	await _test_attendance_backfills_before_advance()
	await _test_attendance_other_install_advance_carries_prev()
	await _test_attendance_cooldown_backfills_carried_prev()
	await _test_attendance_backfill_replay_is_idempotent()
	await _test_attendance_uncertain_advance_recovers()
	await _test_attendance_ambiguous_backfill_skips_and_advances()
	await _test_attendance_pruned_return_advances()
	await _test_submit_best_pushes_hud_rank()
	await _test_hall_named_rows_reach_panel()
	await _test_adoption_conflict_preserves()
	await _test_bindings_have_no_secrets()
	await _test_offline_guest_labeled_local()
	await _test_capability_disablement()
	await _test_capable_providers_listed()
	await _test_draining_cancel_keeps_lock()
	await _test_provider_conflict_offers_switch()
	await _test_token_retirement_on_switch()
	await _test_save_choice_preserves_rejected()
	await _test_fresh_guest_on_signout_preserves_slot()
	await _test_new_save_confirmation()
	await _test_resume_needs_save()
	await _test_defeat_offers_no_resume()
	await _test_stuck_revive_needs_fresh_confirmation()
	await _test_lodge_local_guest_skips()
	await _test_lodge_unnamed_cloud_blocked()
	await _test_lodge_named_unfinished_recovers()
	await _test_lodge_completed_skips()
	await _test_lodge_exit_guards()
	await _test_lodge_exit_ok_and_confirm()
	await _test_lodge_exit_defeat_never_resumes()
	await _test_double_start_refused()
	await _test_wrong_account_entry_refused()
	await _test_continue_reward_safety()
	await _test_first_entry_shows_choice()
	await _test_relaunch_without_save_returns_to_choice()
	await _test_returning_guest_goes_direct()
	await _test_restored_session_goes_direct()
	await _test_guest_pending_shows_busy()
	await _test_signout_returns_to_selection()
	await _test_async_provider_error_persists()
	await _test_error_retry_replaces_and_succeeds()
	await _test_error_cancel_and_signout_retire()
	await _test_failure_to_local_guest()
	await _test_draining_refusal_preserves_lock()
	await _test_sync_refusal_settles_through_entry()
	await _test_anonymous_link_available_vs_authenticated()
	await _test_conflict_switch_preserved()
	await _test_link_retry_repeats_link_preserves_uid()
	await _test_signin_retry_repeats_signin()
	await _test_switch_retry_signs_in_after_explicit_switch()
	await _test_retry_mismatched_provider_refused()
	await _test_retry_cancel_signout_and_sync_failure_boundaries()
	await _test_delete_pending_success_cleans_up()
	await _test_delete_commit_denied_stops()
	await _test_delete_commit_timeout_preserves()
	await _test_delete_native_sync_error_preserves()
	await _test_delete_native_sync_cancel_preserves()
	await _test_delete_duplicate_taps_single_commit()
	await _test_delete_native_error_preserves_and_retries()
	await _test_delete_cancel_preserves()
	await _test_delete_draining_then_success()
	await _test_delete_rejects_switch_and_start()
	await _test_delete_account_move_aborts()
	await _test_delete_timeout_preserves_and_late_completion_safe()
	await _test_delete_frames_before_deadline_harmless()
	await _test_delete_success_just_before_deadline()
	await _test_delete_late_terminal_safe_for_next_run()
	await _test_delete_expired_run_deletes_no_other_account()
	await _test_token_elapsed_deadline()
	await _test_delete_local_guest_sends_no_cloud()
	await _test_delete_panel_flow()
	await _test_hall_ties_share_standing()
	await _test_menus_open_close()
	await _test_title_rank_opens_real_hall()
	await _test_back_cancel_unwind()
	await _test_loader_generation_safety()
	await _test_hud_source_labels()
	await _test_hall_rows_mapped_real()
	await _test_live_rank_reaches_hud()
	await _test_no_token_in_state()
	await _test_first_paint_noted()
	await _test_restore_blocks_fresh_until_remote_read()
	await _test_restore_pending_shows_save_check()
	await _test_restore_installs_remote_continue()
	await _test_restore_not_found_unlocks_fresh()
	await _test_restore_offline_failure_and_retry()
	await _test_restore_explicit_offline()
	await _test_restore_signout_retires_late_result()
	await _test_restore_switch_retires_late_result()
	await _test_restore_duplicate_ready_restarts_nothing()
	await _test_restore_local_resume_needs_no_cloud()
	await _test_restore_timeout_is_bounded()
	await _test_restore_claim_identity_never_reused()
	await _test_restore_held_switch_keeps_new_claim()
	await _test_restore_relogin_starts_new_generation()
	await _test_restore_timeout_offline_before_orphan()
	await _test_restore_timeout_retry_supersedes_orphan()
	_wipe_all()
	if _failed > 0:
		printerr("production host tests failed — ", _failed, "/", _checked,
			" cases")
		get_tree().quit(1)
		return
	print("production host tests passed — ", _checked, " cases")
	get_tree().quit(0)


func _make_parts(fake_script: Script = null,
		extra: Dictionary = {}) -> Dictionary:
	# Cloud-path tests present a supported bridge (native outcomes only
	# exist where the bridge is genuinely ready); the disablement case
	# passes the base fake explicitly. `extra` carries narrow deadline
	# overrides (a `clock` plus short `*_seconds`) for wait tests only.
	var fake: Node = null
	if fake_script == null:
		fake = CapableFake.new()
	else:
		fake = fake_script.new()
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake, ID_PATH, BIND_PATH)
	var coord: Node = COORD_SCRIPT.new() as Node
	var host: Node = HOST_SCRIPT.new() as Node
	add_child(host)
	var services: Dictionary = {
		"account": account, "adapter": fake, "sender": sender,
		"coordinator": coord, "vault": Vault,
	}
	for key in extra:
		services[key] = extra[key]
	host.inject_services(services)
	_watch(host)
	return {"host": host, "fake": fake, "sender": sender,
		"account": account, "coord": coord}


func _free_parts(parts: Dictionary) -> void:
	(parts["host"] as Node).shutdown()
	(parts["host"] as Node).queue_free()
	Journey.use_account("")
	Journey.disarm()
	Journey.clear_stable_hooks()
	Journey.last_error = ""
	await get_tree().process_frame


func _watch(host: Node) -> void:
	_fired = {"changed": [], "conflict": [], "hall": [], "error": []}
	host.production_changed.connect(
		func(state: Dictionary) -> void: _fired["changed"].append(state))
	host.production_conflict.connect(
		func(local: Dictionary, cloud: Dictionary) -> void: _fired[
			"conflict"].append([local, cloud]))
	host.production_hall.connect(
		func(rows: Array, meta: Dictionary) -> void: _fired["hall"].append(
			[rows, meta]))
	host.production_error.connect(
		func(error: Dictionary) -> void: _fired["error"].append(error))


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _settle_call(target: Object, method: String, want: String,
		key: String = "public_id", frames: int = 240) -> Dictionary:
	for _index in frames:
		var snapshot: Dictionary = target.call(method)
		if str(snapshot.get(key, "")) == want:
			return snapshot
		await get_tree().process_frame
	return target.call(method)


func _await_ready(host: Node, frames: int = 240) -> Dictionary:
	for _index in frames:
		var coord: Node = host.get("_coordinator") as Node
		if coord != null:
			var snapshot: Dictionary = coord.account_snapshot()
			if str(snapshot.get("state", "")) == "ready":
				return snapshot
		await get_tree().process_frame
	var coord: Node = host.get("_coordinator") as Node
	if coord == null:
		return {}
	return coord.account_snapshot()


## Wait until the live coordinator's reservation leaves `reserving` by any
## outcome — ready, offline, conflict, or error. For failure-path tests
## that must observe the error snapshot instead of a ready one.
func _await_reserve_settled(host: Node, frames: int = 120) -> Dictionary:
	for _index in frames:
		var coord: Node = host.get("_coordinator") as Node
		if coord != null:
			var snapshot: Dictionary = coord.account_snapshot()
			if str(snapshot.get("state", "")) != "reserving":
				return snapshot
		await get_tree().process_frame
	var coord: Node = host.get("_coordinator") as Node
	if coord == null:
		return {}
	return coord.account_snapshot()


## Wait until the host's initial cloud check stops fetching: resolved,
## failed, or never started. Returns the final account state.
func _settle_restore(host: Node, frames: int = 240) -> Dictionary:
	for _index in frames:
		var snapshot: Dictionary = host.account_state()
		if not bool(snapshot.get("restore_pending", false)):
			return snapshot
		await get_tree().process_frame
	return host.account_state()


## Sender calls that read the owned checkpoint document.
func _checkpoint_calls(sender: RefCounted) -> Array:
	var hits: Array = []
	for call in sender.calls:
		if str((call as Dictionary).get("url", "")).contains(
				"mb_checkpoints_v1"):
			hits.append(call)
	return hits


## Same parts as `_make_parts`, but the cloud sender is the caller's own
## double (delayed, routed, or hung). The double's `tree_node` must point
## at this test before the host can use it.
func _make_parts_with_sender(sender: RefCounted,
		extra: Dictionary = {}) -> Dictionary:
	var fake: Node = CapableFake.new()
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake, ID_PATH, BIND_PATH)
	var coord: Node = COORD_SCRIPT.new() as Node
	var host: Node = HOST_SCRIPT.new() as Node
	add_child(host)
	var services: Dictionary = {
		"account": account, "adapter": fake, "sender": sender,
		"coordinator": coord, "vault": Vault,
	}
	for key in extra:
		services[key] = extra[key]
	host.inject_services(services)
	_watch(host)
	return {"host": host, "fake": fake, "sender": sender,
		"account": account, "coord": coord}


## True once the host's initial cloud check is fetching.
func _await_restore_pending(host: Node, frames: int = 240) -> bool:
	for _index in frames:
		if bool((host.account_state() as Dictionary).get(
				"restore_pending", false)):
			return true
		await get_tree().process_frame
	return false


## True once at least `count` checkpoint reads have been sent.
func _await_checkpoint_sent(sender: RefCounted, count: int = 1,
		frames: int = 240) -> bool:
	for _index in frames:
		if _checkpoint_calls(sender).size() >= count:
			return true
		await get_tree().process_frame
	return false


## True once the routed sender has no delayed call still awaiting. Tests
## drain this before freeing parts, so no `send()` resumes on a freed
## double after the host is gone.
func _await_sender_idle(sender: RoutedSender, frames: int = 240) -> bool:
	for _index in frames:
		if sender.in_flight <= 0:
			return true
		await get_tree().process_frame
	return false


## Re-emit the live coordinator's ready snapshot, the way a same-account
## duplicate callback arrives. Uses the host's live coordinator: the
## injected one is retired on first configure, so the parts dict copy is
## already freed by the time any duplicate could arrive.
func _emit_duplicate_ready(host: Node) -> void:
	var live: Node = host.get("_coordinator") as Node
	live.account_changed.emit(live.account_snapshot())


func _test_boot_mints_id_before_play() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var state: Dictionary = (parts["host"] as Node).startup()
	_expect_true(bool(state.get("ready", false)), "boot: identity ready")
	_expect_true(ACCOUNT_SCRIPT.is_valid_public_id(
		str(state.get("public_id", ""))), "boot: durable MB id minted")
	_expect_true(FileAccess.file_exists(ID_PATH), "boot: id saved to disk")
	_expect_equal(str(state.get("source", "")), "local",
		"boot: guest starts local")
	await _free_parts(parts)


func _test_restart_keeps_id() -> void:
	_wipe_all()
	var first: Dictionary = _make_parts()
	var id_a: String = str(((first["host"] as Node).startup()
		).get("public_id", ""))
	await _free_parts(first)
	var second: Dictionary = _make_parts()
	var id_b: String = str(((second["host"] as Node).startup()
		).get("public_id", ""))
	_expect_equal(id_b, id_a, "restart: same durable id")
	await _free_parts(second)


func _test_corrupt_identity_refuses_readiness() -> void:
	_wipe_all()
	var writer: FileAccess = FileAccess.open(ID_PATH, FileAccess.WRITE)
	writer.store_string("not an identity file {{{")
	writer.close()
	var parts: Dictionary = _make_parts()
	var state: Dictionary = (parts["host"] as Node).startup()
	# A corrupt file recovers with a fresh durable id, never a half id.
	_expect_true(bool(state.get("ready", false)),
		"corrupt: recovered to ready")
	_expect_true(ACCOUNT_SCRIPT.is_valid_public_id(
		str(state.get("public_id", ""))),
		"corrupt: recovered id is valid")
	_expect_true(bool(((parts["account"] as Node).current_state()
		).get("recovered_from_corrupt", false)),
		"corrupt: recovery flagged")
	await _free_parts(parts)
	# An unwritable disk refuses readiness and advertises nothing.
	_wipe_all()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake, "user://no_such_dir_anywhere/player_identity.cfg",
		"user://no_such_dir_anywhere/player_bindings.cfg")
	var coord: Node = COORD_SCRIPT.new() as Node
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var host: Node = HOST_SCRIPT.new() as Node
	add_child(host)
	host.inject_services({"account": account, "adapter": fake,
		"sender": sender, "coordinator": coord, "vault": Vault})
	_watch(host)
	var broken: Dictionary = host.startup()
	_expect_false(bool(broken.get("ready", false)),
		"unwritable: readiness refused")
	_expect_true(str(broken.get("public_id", "")).is_empty(),
		"unwritable: no id advertised")
	_expect_equal(str(broken.get("source", "")), "unready",
		"unwritable: source unready")
	_expect_equal(str((host.plan_entry(true, true) as Dictionary).get(
		"code", "")), "identity_not_ready",
		"unwritable: entry refused without a durable id")
	await _free_parts({"host": host})


func _test_canonical_adoption_durable() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	Vault.continue_coins = 1
	Vault.save_vault()
	_seal_and_journal(guest, "adopt-j-1", 2, 3)
	Journey.use_account(guest)
	# Blocked installs keep the receipt pending past the first status
	# read, so the adoption below must carry it onto the canonical slot
	# instead of settling it in place. Slot moves are renames and still
	# run under the fault.
	Journey.install_fault = Journey.InstallFault.FAIL_ALL
	# A UID that already owns another id: the canonical one wins.
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var adopted: Dictionary = await _settle_call(
		host, "account_state", CANON_C)
	_expect_equal(str(adopted.get("public_id", "")), CANON_C,
		"adopt: canonical id wins")
	_expect_equal(str(Vault.scoped_continue_txn().get("owner", "")), CANON_C,
		"adopt: the guest receipt rekeys onto the canonical slot")
	_expect_equal(int(Vault.scoped_continue_txn().get("checkpoint_id", 0)),
		3, "adopt: the rekeyed receipt names the paid seal")
	Journey.install_fault = Journey.InstallFault.NONE
	_expect_equal(Vault.recover_paid_continue(), "recovered",
		"adopt: the rekeyed receipt still settles")
	_expect_equal(Vault.continue_coins, 0,
		"adopt: the rekeyed settle charges nothing more")
	_expect_equal(int(Journey.read_checkpoint().get("checkpoint_id", 0)), 3,
		"adopt: the canonical slot holds the paid revive")
	_expect_equal((host.account_state() as Dictionary).get(
		"cloud_uid", ""), UID_A, "adopt: cloud session kept")
	var account: Node = parts["account"]
	_expect_equal(account.public_id_for_uid(UID_A), CANON_C,
		"adopt: uid binding recorded")
	_expect_true((_fired["error"] as Array).is_empty(),
		"adopt: successful configure raises no error")
	_expect_true(guest != CANON_C, "adopt: guest really differed")
	await _free_parts(parts)
	# Relaunch keeps the adopted canonical id.
	var relaunched: Dictionary = _make_parts()
	var state: Dictionary = (relaunched["host"] as Node).startup()
	_expect_equal(str(state.get("public_id", "")), CANON_C,
		"adopt: canonical id survives restart")
	await _free_parts(relaunched)


## A wallet failure during canonical adoption keeps the guest scope and
## reports the failed move instead of adopting over a stranded receipt.
## After the fault clears and the account restarts, the retry adopts and
## the one paid revive lands under the canonical slot with no second
## debit, no foreign hook, and no orphan receipt.
func _test_adoption_rekey_failure_stays_guest_then_retries() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	Vault.continue_coins = 1
	Vault.save_vault()
	_seal_and_journal(guest, "fault-j-1", 5, 6)
	Journey.use_account(guest)
	var hooked: Array = []
	var hook := func(info: Dictionary) -> void: hooked.append(info)
	Journey.subscribe_stable_checkpoint(hook)
	var vault_tmp: String = ProjectSettings.globalize_path(
		Vault.TEMP_SAVE_PATH)
	_occupy_dir(vault_tmp)
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var faulted: Dictionary = await _await_reserve_settled(host)
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), guest,
		"fault-adopt: the failed move stays on the guest")
	_expect_equal(str(faulted.get("state", "")), "error",
		"fault-adopt: the failed move reports error, not ready")
	_expect_equal(str(faulted.get("code", "")), "slot-move-failed",
		"fault-adopt: the error names the failed move")
	var coord: Node = host.get("_coordinator") as Node
	_expect_equal(str((coord.save_snapshot() as Dictionary).get(
		"code", "")), "slot-move-failed",
		"fault-adopt: the save snapshot carries the failure")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(guest)),
		"fault-adopt: the guest main stays in place")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"fault-adopt: nothing moves into the canonical slot")
	_expect_equal(_txn_owner_cid(guest), 6,
		"fault-adopt: the receipt stays owned by the guest")
	_expect_equal(Vault.continue_coins, 0,
		"fault-adopt: the one debit stands, no second charge")
	var gate: Dictionary = host.saved_gate_summary()
	_expect_false(bool(gate.get("revive_stuck", true)),
		"fault-adopt: ordinary gate reads stay unstuck")

	# The restart: fault cleared, wallet reloaded, fresh host on the same
	# storage. The retry adopts and the paid seal lands canonically.
	_release_dir(vault_tmp)
	Vault.load_vault()
	_expect_equal(Vault.continue_coins, 0,
		"fault-adopt: the reload keeps the single debit")
	_expect_equal(_txn_owner_cid(guest), 6,
		"fault-adopt: the reload keeps the guest receipt")
	await _free_parts(parts)
	var restarted: Dictionary = _make_parts()
	var host2: Node = restarted["host"]
	var fake2: Node = restarted["fake"]
	var sender2: RefCounted = restarted["sender"]
	var state2: Dictionary = (host2 as Node).startup()
	_expect_equal(str(state2.get("public_id", "")), guest,
		"fault-adopt: the restart restores the guest")
	# The restart's own status reads deliver the seal that landed during
	# the fault (its ack was what the broken wallet held back), so the
	# retry below carries landed bytes rather than a pending receipt —
	# the crash-window case covers a receipt still in flight.
	var landed: Dictionary = Journey.read_checkpoint()
	_expect_false(Journey.is_ended(landed),
		"fault-adopt: the restart kept the landed seal")
	_expect_equal(int(landed.get("checkpoint_id", 0)), 6,
		"fault-adopt: the landed seal is the correct original")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"fault-adopt: the eager delivery clears the journal")
	_expect_equal(Vault.recover_paid_continue(), "none",
		"fault-adopt: nothing pends after the eager delivery")
	Journey.subscribe_stable_checkpoint(hook)
	sender2.queue_ok(_profile_body(UID_A, CANON_C))
	sender2.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake2.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host2.begin_guest()
	var adopted: Dictionary = await _settle_call(
		host2, "account_state", CANON_C)
	_expect_equal(str(adopted.get("public_id", "")), CANON_C,
		"fault-adopt: the retry adopts the canonical id")
	var canon: Dictionary = Journey.read_checkpoint()
	_expect_false(Journey.is_ended(canon),
		"fault-adopt: the canonical slot holds the alive revive")
	_expect_equal(int(canon.get("checkpoint_id", 0)), 6,
		"fault-adopt: the revive is the correct original seal")
	_expect_equal(Vault.continue_coins, 0,
		"fault-adopt: the retry charges nothing more")
	_expect_true(_txn_owner_cid(guest) == 0
		and _txn_owner_cid(CANON_C) == 0,
		"fault-adopt: no orphan receipt survives")
	for note in hooked:
		var heard: String = str((note as Dictionary).get("path", ""))
		_expect_true(heard == Journey.account_main_path(guest)
			or heard == Journey.account_main_path(CANON_C),
			"fault-adopt: every hook stays within the adopting slots")
	var seventh: Dictionary = _valid_checkpoint("fault-j-1", 7, 0)
	_expect_equal(Journey.write_checkpoint(seventh), OK,
		"fault-adopt: post-recovery play seals")
	_expect_false(hooked.is_empty(),
		"fault-adopt: the recovery notified at least once")
	if not hooked.is_empty():
		_expect_equal(str((hooked.back() as Dictionary).get("path", "")),
			Journey.account_main_path(CANON_C),
			"fault-adopt: routing follows the adoption")
	Journey.unsubscribe_stable_checkpoint(hook)
	await _free_parts(restarted)


## A legacy receipt adopts with its slot's files: the debit rekeys onto
## the owned account before the save migrates, then settles there. Under
## a wallet failure the migration waits — legacy bytes and receipt stay
## jointly in place — and the next startup converges without recharging.
func _test_legacy_paid_adoption_recovers() -> void:
	# Blocked installs keep each receipt pending past the status reads
	# around it, so the adoption — not an eager settle — carries it.
	_wipe_all()
	_write_legacy_pair("legacy-j-1", 5)
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	Journey.use_account("")
	Vault.continue_coins = 1
	Vault.save_vault()
	_journal_revive("legacy-j-1", 6)
	Journey.install_fault = Journey.InstallFault.FAIL_ALL
	var state: Dictionary = (host as Node).startup()
	var guest: String = str(state.get("public_id", ""))
	_expect_false(FileAccess.file_exists(Journey.DEFAULT_PATH),
		"legacy-adopt: the legacy main migrates away")
	_expect_equal(_txn_owner_cid(guest), 6,
		"legacy-adopt: the receipt rekeys onto the owned slot")
	Journey.install_fault = Journey.InstallFault.NONE
	_expect_equal(Vault.recover_paid_continue(), "recovered",
		"legacy-adopt: the owned receipt settles")
	_expect_equal(int(Journey.read_checkpoint().get("checkpoint_id", 0)),
		6, "legacy-adopt: the revive is the correct original seal")
	_expect_equal(Vault.continue_coins, 0,
		"legacy-adopt: the settle charges nothing more")
	await _free_parts(parts)

	# The fault half: a broken wallet holds the migration jointly — the
	# receipt and its bytes stay in the legacy scope together, so even a
	# rotation before the retry cannot split them across two guests.
	# Blocked installs keep the receipt itself pending (rather than
	# landed-but-unacked) so the retry carries receipt and bytes together;
	# the joint hold below is still the wallet's doing — file moves are
	# raw operations the install block does not stop.
	_wipe_all()
	_write_legacy_pair("legacy-j-2", 5)
	var held: Dictionary = _make_parts()
	var held_host: Node = held["host"]
	Journey.use_account("")
	Vault.continue_coins = 1
	Vault.save_vault()
	_journal_revive("legacy-j-2", 6)
	Journey.install_fault = Journey.InstallFault.FAIL_ALL
	var vault_tmp: String = ProjectSettings.globalize_path(
		Vault.TEMP_SAVE_PATH)
	_occupy_dir(vault_tmp)
	var held_state: Dictionary = (held_host as Node).startup()
	var held_guest: String = str(held_state.get("public_id", ""))
	_expect_true(FileAccess.file_exists(Journey.DEFAULT_PATH),
		"legacy-adopt: the failed rekey holds the migration")
	_expect_equal(_txn_owner_cid(""), 6,
		"legacy-adopt: the receipt stays legacy-owned")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(held_guest)),
		"legacy-adopt: the owned slot stays empty meanwhile")
	_expect_equal(str(((held_host as Node).account_state()
		as Dictionary).get("legacy_hold", "")), "legacy-adopt-held",
		"legacy-adopt: the hold carries a truthful retry code")
	(held_host as Node).sign_out()
	var rotated: String = str(((held_host as Node).account_state()
		as Dictionary).get("public_id", ""))
	_expect_true(rotated != held_guest and not rotated.is_empty(),
		"legacy-adopt: the rotation mints the next guest")
	_expect_true(FileAccess.file_exists(Journey.DEFAULT_PATH),
		"legacy-adopt: the rotation moves nothing while held")
	_expect_equal(_txn_owner_cid(""), 6,
		"legacy-adopt: the rotation keeps the legacy receipt")
	_release_dir(vault_tmp)
	Vault.load_vault()
	_expect_equal(Vault.continue_coins, 0,
		"legacy-adopt: the reload keeps the single debit")
	_expect_equal(_txn_owner_cid(""), 6,
		"legacy-adopt: the reload keeps the legacy receipt")
	await _free_parts(held)
	var retry: Dictionary = _make_parts()
	var retry_state: Dictionary = (retry["host"] as Node).startup()
	_expect_equal(str(retry_state.get("public_id", "")), rotated,
		"legacy-adopt: the retry restores the rotated guest")
	_expect_true(str(retry_state.get("legacy_hold", "")).is_empty(),
		"legacy-adopt: the retry clears the hold code")
	_expect_false(FileAccess.file_exists(Journey.DEFAULT_PATH),
		"legacy-adopt: the retry migrates the save")
	_expect_equal(_txn_owner_cid(rotated), 6,
		"legacy-adopt: the retry rekeys the receipt with its bytes")
	Journey.install_fault = Journey.InstallFault.NONE
	_expect_equal(Vault.recover_paid_continue(), "recovered",
		"legacy-adopt: the retry settles without recharging")
	_expect_equal(Vault.continue_coins, 0,
		"legacy-adopt: exactly one debit across the fault")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(held_guest)),
		"legacy-adopt: no split-brain copy lands in the first guest")
	await _free_parts(retry)


## A canonical slot that already holds a journey keeps it: adoption still
## lands, the unrelated slot stays byte-identical, and the guest receipt
## is retained (deferred) rather than rekeyed or dropped.
func _test_adoption_occupied_canonical_preserves_guest() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	Vault.continue_coins = 1
	Vault.save_vault()
	_seal_and_journal(guest, "occ-j-1", 5, 6)
	Journey.use_account(CANON_C)
	_write_checkpoint({"journey_id": "canon-j-9", "checkpoint_id": 4,
		"cycle": 2})
	var canon_before: String = FileAccess.get_file_as_string(
		Journey.account_main_path(CANON_C))
	Journey.use_account(guest)
	# Blocked installs keep the receipt pending past the first status
	# read, so the adoption meets it instead of settling it in place.
	Journey.install_fault = Journey.InstallFault.FAIL_ALL
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var adopted: Dictionary = await _settle_call(
		host, "account_state", CANON_C)
	_expect_equal(str(adopted.get("public_id", "")), CANON_C,
		"occupied: adoption still lands")
	_expect_equal(FileAccess.get_file_as_string(
		Journey.account_main_path(CANON_C)), canon_before,
		"occupied: the canonical slot stays byte-identical")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(guest)),
		"occupied: the guest slot stays in place")
	_expect_equal(_txn_owner_cid(guest), 6,
		"occupied: the guest receipt is retained")
	_expect_equal(Vault.recover_paid_continue(), "deferred",
		"occupied: the retained receipt defers, never imports")
	_expect_equal(Vault.continue_coins, 0,
		"occupied: the one debit stands")
	Journey.install_fault = Journey.InstallFault.NONE
	Journey.use_account(guest)
	_expect_equal(Vault.recover_paid_continue(), "recovered",
		"occupied: the retained receipt still settles in its scope")
	_expect_equal(Vault.continue_coins, 0,
		"occupied: the late settle charges nothing more")
	await _free_parts(parts)


## The rekey-first crash window converges: the receipt already owns the
## canonical slot while its files still sit in the guest slot. Only the
## durable state survives the death; the next adoption completes the move
## and the paid seal lands with no second debit.
func _test_adoption_crash_between_rekey_and_move() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	Vault.continue_coins = 1
	Vault.save_vault()
	_seal_and_journal(guest, "crash-j-1", 5, 6)
	_expect_true(Vault.rekey_continue_txn_owner(guest, CANON_C),
		"crash-window: the rekey lands first")
	Vault.load_vault()
	_expect_equal(_txn_owner_cid(CANON_C), 6,
		"crash-window: only the rekeyed receipt survives the death")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(guest)),
		"crash-window: the files never moved")
	_expect_equal(Vault.continue_coins, 0,
		"crash-window: the death charges nothing")
	# Blocked installs keep the receipt pending past the status reads
	# around it, so the explicit recovery — not an eager settle — lands it.
	Journey.install_fault = Journey.InstallFault.FAIL_ALL
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var adopted: Dictionary = await _settle_call(
		host, "account_state", CANON_C)
	_expect_equal(str(adopted.get("public_id", "")), CANON_C,
		"crash-window: adoption completes the move")
	Journey.install_fault = Journey.InstallFault.NONE
	_expect_equal(Vault.recover_paid_continue(), "recovered",
		"crash-window: the paid seal materializes canonically")
	_expect_equal(int(Journey.read_checkpoint().get("checkpoint_id", 0)),
		6, "crash-window: the revive is the correct original seal")
	_expect_equal(Vault.continue_coins, 0,
		"crash-window: the materialize charges nothing more")
	_expect_true(_txn_owner_cid(guest) == 0
		and _txn_owner_cid(CANON_C) == 0,
		"crash-window: no orphan receipt survives")
	await _free_parts(parts)


## A canonical target holding its own pending paid receipt is occupied
## even when the source carries no receipt: the adoption keeps the
## unrelated source bytes out, and the target's exact acknowledged seal
## settles from the journal with no second debit.
func _test_adoption_target_receipt_without_source_receipt() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	# Target C's acknowledged receipt, journaled through the real API,
	# with no surviving target files: a supported paid recovery state.
	Journey.use_account(CANON_C)
	Vault.continue_coins = 1
	Vault.save_vault()
	var paid: Dictionary = _valid_checkpoint("d1", 6, 0)
	_expect_true(Vault.begin_continue_txn("d1", 6,
		JSON.stringify(paid)), "target-kept: the target debit journals")
	_wipe_slot(CANON_C)
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"target-kept: the target holds no files")
	# Source A's unrelated living journey, carrying no receipt.
	Journey.use_account(guest)
	var living: Dictionary = _valid_checkpoint("d1-other", 2, 0)
	_expect_equal(Journey.write_checkpoint(living), OK,
		"target-kept: the source journey seals")
	var source_main: String = FileAccess.get_file_as_string(
		Journey.account_main_path(guest))
	var source_backup: String = ""
	if FileAccess.file_exists(Journey.account_backup_path(guest)):
		source_backup = FileAccess.get_file_as_string(
			Journey.account_backup_path(guest))
	# Only durable state crosses the restart: the reload and fresh parts
	# below prove the receipt, not test memory, drives the recovery.
	Vault.load_vault()
	_expect_equal(_txn_owner_cid(CANON_C), 6,
		"target-kept: the reload retains the target receipt")
	_expect_equal(Vault.continue_coins, 0,
		"target-kept: the reload keeps the single debit")
	await _free_parts(parts)
	var restarted: Dictionary = _make_parts()
	var host2: Node = restarted["host"]
	var fake2: Node = restarted["fake"]
	var sender2: RefCounted = restarted["sender"]
	var state2: Dictionary = (host2 as Node).startup()
	_expect_equal(str(state2.get("public_id", "")), guest,
		"target-kept: the restart restores the source guest")
	_expect_equal(_txn_owner_cid(CANON_C), 6,
		"target-kept: the restart retains the target receipt")
	sender2.queue_ok(_profile_body(UID_A, CANON_C))
	sender2.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake2.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host2.begin_guest()
	var adopted: Dictionary = await _settle_call(
		host2, "account_state", CANON_C)
	_expect_equal(str(adopted.get("public_id", "")), CANON_C,
		"target-kept: the adoption still lands")
	_expect_equal(Vault.recover_paid_continue(), "none",
		"target-kept: the adoption settles the receipt eagerly")
	var restored: Dictionary = Journey.read_checkpoint()
	var want: Variant = JSON.parse_string(JSON.stringify(paid))
	_expect_equal(restored, want,
		"target-kept: the target's exact acknowledged seal restores")
	_expect_true(_txn_owner_cid(guest) == 0
		and _txn_owner_cid(CANON_C) == 0,
		"target-kept: no orphan receipt survives")
	_expect_equal(Vault.continue_coins, 0,
		"target-kept: the recovery charges nothing more")
	_expect_equal(FileAccess.get_file_as_string(
		Journey.account_main_path(guest)), source_main,
		"target-kept: the source main is retained byte-identical")
	if source_backup.is_empty():
		_expect_false(FileAccess.file_exists(
			Journey.account_backup_path(guest)),
			"target-kept: no source backup appears")
	else:
		_expect_equal(FileAccess.get_file_as_string(
			Journey.account_backup_path(guest)), source_backup,
			"target-kept: the source backup is retained byte-identical")
	await _free_parts(restarted)


## A canonical target holding its own journey is occupied even when the
## source carries no receipt: neither side moves, neither loses a byte.
func _test_adoption_occupied_target_without_source_receipt() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	Journey.use_account(CANON_C)
	var owned: Dictionary = _valid_checkpoint("canon-own", 4, 0)
	_expect_equal(Journey.write_checkpoint(owned), OK,
		"bare-occupied: the target journey seals")
	var canon_main: String = FileAccess.get_file_as_string(
		Journey.account_main_path(CANON_C))
	Journey.use_account(guest)
	var living: Dictionary = _valid_checkpoint("guest-own", 2, 0)
	_expect_equal(Journey.write_checkpoint(living), OK,
		"bare-occupied: the source journey seals")
	var source_main: String = FileAccess.get_file_as_string(
		Journey.account_main_path(guest))
	Vault.load_vault()
	await _free_parts(parts)
	var restarted: Dictionary = _make_parts()
	var host2: Node = restarted["host"]
	var fake2: Node = restarted["fake"]
	var sender2: RefCounted = restarted["sender"]
	var state2: Dictionary = (host2 as Node).startup()
	_expect_equal(str(state2.get("public_id", "")), guest,
		"bare-occupied: the restart restores the source guest")
	sender2.queue_ok(_profile_body(UID_A, CANON_C))
	sender2.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake2.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host2.begin_guest()
	var adopted: Dictionary = await _settle_call(
		host2, "account_state", CANON_C)
	_expect_equal(str(adopted.get("public_id", "")), CANON_C,
		"bare-occupied: the adoption still lands")
	_expect_equal(FileAccess.get_file_as_string(
		Journey.account_main_path(CANON_C)), canon_main,
		"bare-occupied: the target slot stays byte-identical")
	_expect_equal(FileAccess.get_file_as_string(
		Journey.account_main_path(guest)), source_main,
		"bare-occupied: the source slot stays byte-identical")
	_expect_equal(Vault.recover_paid_continue(), "none",
		"bare-occupied: no receipt pends anywhere")
	_expect_true(_txn_owner_cid(guest) == 0
		and _txn_owner_cid(CANON_C) == 0,
		"bare-occupied: no orphan receipt survives")
	await _free_parts(restarted)


## Adopt a fresh guest to the canonical id through the real route.
## Returns the parts plus the guest id; the caller owns freeing.
func _adopt_guest_to_canonical(extra: Dictionary = {}) -> Dictionary:
	_wipe_all()
	_clear_name_cache()
	_clear_attendance_cache()
	var parts: Dictionary = _make_parts(null, extra)
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _settle_call(host, "account_state", CANON_C)
	parts["guest"] = guest
	return parts


## Swap the live coordinator for a recorder without moving the account:
## the configured UID stays, so only the instance retires. A narrow
## white-box seam: re-injection would churn the account signals and free
## the retired coordinator mid-test, while production retirement keeps
## late replies observable. The retired node stays parented and is freed
## with the host.
func _swap_coordinator(parts: Dictionary, recorder: NameRecorder) -> void:
	recorder.tree_node = self
	var host: Node = parts["host"]
	host.add_child(recorder)
	host.set("_coordinator", recorder)
	host._wire_signals()
	parts["coord"] = recorder


## Call one name route, awaited. Single-line calls: a split never parses.
func _call_name_route(host: Node, route: String) -> Dictionary:
	match route:
		"claim":
			return await host.claim_adventurer_name("Alpha")
		"load":
			return await host.load_adventurer_name()
		"intro":
			return await host.mark_intro_complete()
	return await host.backfill_hall_name()


## Retire the live coordinator to `recorder` mid-flight, proving the
## request under test is parked at the token barrier first. Runs from a
## timer or a recorder signal while the test awaits the wrapper: parking
## the wrapper coroutine itself is impossible, since an un-awaited async
## call is a hard error.
func _swap_to_b(parts: Dictionary, recorder: NameRecorder,
		label: String) -> void:
	var host: Node = parts["host"]
	_expect_true((host.get("_token_waiters") as Array).size() > 0,
		"%s: the call parks at the barrier" % label)
	_swap_coordinator(parts, recorder)
	# The account side of the retirement: production moves the configured
	# UID through retire/reconfigure, which would also fail the waiters.
	host.set("_configured_uid", UID_B)


## Hand the live slot to `recorder` for account B without parking
## assertions: the stale-completion swap runs on dispatch, past the token.
func _adopt_b(parts: Dictionary, recorder: NameRecorder) -> void:
	_swap_coordinator(parts, recorder)
	(parts["host"] as Node).set("_configured_uid", UID_B)


## Shut the host down mid-wait, proving the request under test parked at
## the token barrier first.
func _shutdown_mid_wait(parts: Dictionary) -> void:
	var host: Node = parts["host"]
	_expect_true((host.get("_token_waiters") as Array).size() > 0,
		"shutdown-wait: the claim parks at the barrier")
	host.shutdown()


## Begin the real account deletion from a timer while the test awaits
## another wrapper. Signal-driven, since an un-awaited async call is a
## hard error; the terminal result lands in `box["r"]` for settling.
func _begin_deletion_async(parts: Dictionary, box: Dictionary) -> void:
	box["r"] = await (parts["host"] as Node).delete_current_account()


## Prove the deletion run holds its ticket with both the name request and
## the deletion parked at the shared token barrier.
func _assert_deletion_barrier(parts: Dictionary) -> void:
	var host: Node = parts["host"]
	_expect_false((host.get("_deletion_ticket") as Dictionary).is_empty(),
		"del-barrier: the deletion run holds its ticket")
	_expect_equal((host.get("_token_waiters") as Array).size(), 2,
		"del-barrier: claim and deletion share the barrier")


## Fail a real deletion fast mid-wait: prove the name request parked
## first, hand the deletion a sync-ok token so it never shares the
## barrier, and run it to its terminal failure on the same account.
func _fail_deletion_fast(parts: Dictionary, box: Dictionary) -> void:
	var host: Node = parts["host"]
	_expect_equal((host.get("_token_waiters") as Array).size(), 1,
		"del-gen: the claim parks before deletion begins")
	(parts["fake"] as Node).token_receipt = {"status": "ok",
		"id_token": "tok-ok", "token_expires_at": 4102444800000}
	box["r"] = await host.delete_current_account()


## Bounded wait for a detached run's terminal result.
func _await_box_key(box: Dictionary, key: String,
		frames: int = 180) -> bool:
	for _index in frames:
		if box.has(key):
			return true
		await get_tree().process_frame
	return box.has(key)


## Retire through the production path mid-flight, then hand the live slot
## to `recorder` with the UID still dropped, the deletion/startup shape.
func _retire_to_recorder(parts: Dictionary,
		recorder: NameRecorder) -> void:
	var host: Node = parts["host"]
	_expect_true((host.get("_token_waiters") as Array).size() > 0,
		"retire-wait: the call parks at the barrier")
	# Read before the production retire frees the live recorder.
	var retired: NameRecorder = parts["coord"] as NameRecorder
	_expect_true(retired.calls.is_empty(),
		"retire-wait: nothing dispatched before the token")
	host._retire_coordinator()
	_expect_equal(str(host.get("_configured_uid")), "",
		"retire-wait: the production path drops the configured UID")
	_swap_coordinator(parts, recorder)


## Drop the cached token so the next wrapper must refresh through the
## scripted adapter receipt (pending holds the barrier, an error fails
## it). Narrow white-box seam: production drops this only on account
## moves, which would also retire the request under test.
func _drop_cached_token(host: Node) -> void:
	host.set("_id_token", "")


## Complete the held token wait through the production signal, as a
## refreshed native token would.
func _release_token_ok(parts: Dictionary) -> void:
	(parts["account"] as Node).emit_signal("id_token_ready", {
		"id_token": "tok-held-ok", "token_expires_at": 4102444800000})


func _name_row_body(display: String, key: String,
		intro_complete: bool) -> String:
	return JSON.stringify({
		"name": "projects/x/databases/(default)/documents/mb_adventurers_v1/%s"
			% CANON_C,
		"fields": {
			"public_id": {"stringValue": CANON_C},
			"uid": {"stringValue": UID_A},
			"name_key": {"stringValue": key},
			"display": {"stringValue": display},
			"intro_complete": {"booleanValue": intro_complete},
			"schema": {"integerValue": "1"},
			"created_at": {"timestampValue": "2026-10-01T00:00:00Z"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
		},
	})


func _hall_own_body(score: int, hero: String, cycles: int,
		display: String = "") -> String:
	var fields: Dictionary = {
		"public_id": {"stringValue": CANON_C},
		"hero": {"stringValue": hero},
		"score": {"integerValue": str(score)},
		"cycles": {"integerValue": str(cycles)},
		"release": {"stringValue": "4.0.0"},
		"schema": {"integerValue": "1"},
		"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
	}
	if not display.is_empty():
		fields["display"] = {"stringValue": display}
	return JSON.stringify({
		"name": "projects/x/databases/(default)/documents/mb_hall_v1/%s"
			% CANON_C,
		"fields": fields,
	})


## The verified-name cache is a shared durable store like the vault
## file: name tests reset it coming and going so neither earlier tests
## nor later deletion tests observe a leaked handle.
func _clear_name_cache() -> void:
	Vault.verified_names = {}


func _clear_attendance_cache() -> void:
	Vault.attendance_marks = {}
	Vault.attendance_floor = 0
	Vault.attendance_next = {}
	for key in (Vault.continue_coin_grants as Dictionary).keys():
		if str(key).begins_with("attendance:"):
			(Vault.continue_coin_grants as Dictionary).erase(key)


func _commit_with(sender: RefCounted, needle: String) -> Dictionary:
	for call in (sender.calls as Array):
		var entry: Dictionary = call
		if str(entry.get("url", "")).contains("documents:commit") \
				and str(entry.get("body", "")).contains(needle):
			return JSON.parse_string(str(entry.get("body", "")))
	return {}


func _test_claim_name_caches_and_backfills_nothing() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_ok("{\"writeResults\": [{}, {}]}")
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var claimed: Dictionary = await host.claim_adventurer_name("Luna")
	_expect_equal(str(claimed.get("status", "")), "ok",
		"name-claim: the claim succeeds")
	_expect_equal(str(claimed.get("display", "")), "Luna",
		"name-claim: the display comes back")
	_expect_equal(str(claimed.get("key", "")), "luna",
		"name-claim: the immutable key comes back")
	_expect_true(bool(claimed.get("cached", false)),
		"name-claim: the verified handle caches")
	_expect_false(bool(claimed.get("backfilled", true)),
		"name-claim: no best row means no backfill write")
	_expect_equal(str(claimed.get("backfill_code", "")), "no-row",
		"name-claim: the empty backfill names no-row")
	_expect_equal((host as Node).verified_display_name(), "Luna",
		"name-claim: the live handle reads synchronously")
	_expect_equal(str((Vault.verified_name_for_account(CANON_C)
		as Dictionary).get("key", "")), "luna",
		"name-claim: the cache keys by public ID")
	var commit: Dictionary = _commit_with(sender, "mb_names_v1")
	_expect_equal((commit.get("writes", []) as Array).size(), 2,
		"name-claim: the commit carries both halves")
	_expect_true(str(JSON.stringify(commit)).contains(
		"mb_adventurers_v1"),
		"name-claim: the adventurer half rides along")
	_clear_name_cache()
	await _free_parts(parts)


func _test_claim_taken_keeps_identity() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_reply({"transport": "ok", "code": 409, "body": "{}"})
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var claimed: Dictionary = await host.claim_adventurer_name("Luna")
	_expect_equal(str(claimed.get("status", "")), "conflict",
		"name-taken: the taken name conflicts")
	_expect_equal(str(claimed.get("code", "")), "name-taken",
		"name-taken: the conflict names name-taken")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), CANON_C,
		"name-taken: the loser keeps its canonical ID")
	_expect_true((Vault.verified_name_for_account(CANON_C)
		as Dictionary).is_empty(),
		"name-taken: the loser caches nothing")
	_expect_equal((host as Node).verified_display_name(), "",
		"name-taken: the loser reads unnamed")
	_clear_name_cache()
	await _free_parts(parts)


func _test_local_guest_cannot_claim() -> void:
	_wipe_all()
	_clear_name_cache()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	var refused_claim: Dictionary = await (host as Node
		).claim_adventurer_name("Luna")
	_expect_equal(str(refused_claim.get("code", "")), "local-guest",
		"name-local: claim without a session refuses")
	var refused_load: Dictionary = await (host as Node
		).load_adventurer_name()
	_expect_equal(str(refused_load.get("code", "")), "local-guest",
		"name-local: load without a session refuses")
	var refused_intro: Dictionary = await (host as Node
		).mark_intro_complete()
	_expect_equal(str(refused_intro.get("code", "")), "local-guest",
		"name-local: intro without a session refuses")
	_expect_true((Vault.verified_name_for_account(guest)
		as Dictionary).is_empty(),
		"name-local: offline work certifies no name")
	_clear_name_cache()
	await _free_parts(parts)


func _test_linking_keeps_claimed_name() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	_write_checkpoint({"cycle": 1, "journey_id": "link-name-j-1"})
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_ok("{\"writeResults\": [{}, {}]}")
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var claimed: Dictionary = await host.claim_adventurer_name("Luna")
	_expect_equal(str(claimed.get("status", "")), "ok",
		"name-link: the guest claims first")
	var journey_before: String = FileAccess.get_file_as_string(
		Journey.account_main_path(CANON_C))
	fake.link_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "google"}}
	var linked: Dictionary = host.link_provider("google")
	await _frames(2)
	_expect_equal(str(linked.get("status", "")), "ok",
		"name-link: the link succeeds")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), CANON_C,
		"name-link: the link keeps the canonical ID")
	_expect_equal((host as Node).verified_display_name(), "Luna",
		"name-link: the link keeps the verified handle")
	_expect_equal(FileAccess.get_file_as_string(
		Journey.account_main_path(CANON_C)), journey_before,
		"name-link: the link keeps the journey bytes")
	host.sign_out()
	var rotated: String = str(((host as Node).account_state()
		as Dictionary).get("public_id", ""))
	_expect_true(rotated != CANON_C and not rotated.is_empty(),
		"name-link: sign-out rotates")
	_expect_equal((host as Node).verified_display_name(), "",
		"name-link: the rotated guest reads unnamed")
	_expect_equal(str((Vault.verified_name_for_account(CANON_C)
		as Dictionary).get("display", "")), "Luna",
		"name-link: rotation never shares the old handle")
	_clear_name_cache()
	await _free_parts(parts)


func _test_intro_complete_and_reload() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_ok("{\"writeResults\": [{}, {}]}")
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var claimed: Dictionary = await host.claim_adventurer_name("Luna")
	_expect_equal(str(claimed.get("status", "")), "ok",
		"name-intro: the claim succeeds")
	sender.queue_ok(_name_row_body("Luna", "luna", false))
	sender.queue_ok("{\"writeResults\": [{}]}")
	var done: Dictionary = await host.mark_intro_complete()
	_expect_equal(str(done.get("status", "")), "ok",
		"name-intro: the bit flips")
	_expect_true(bool((Vault.verified_name_for_account(CANON_C)
		as Dictionary).get("intro_complete", false)),
		"name-intro: the cache flips with it")
	Vault.load_vault()
	_expect_equal(str((Vault.verified_name_for_account(CANON_C)
		as Dictionary).get("display", "")), "Luna",
		"name-intro: the reload keeps the handle")
	_expect_true(bool((Vault.verified_name_for_account(CANON_C)
		as Dictionary).get("intro_complete", false)),
		"name-intro: the reload keeps the bit")
	sender.queue_ok(_name_row_body("Luna", "luna", true))
	var loaded: Dictionary = await host.load_adventurer_name()
	_expect_equal(str(loaded.get("status", "")), "ok",
		"name-intro: the reload restores from the server too")
	_expect_equal(str(loaded.get("display", "")), "Luna",
		"name-intro: the restore names the same handle")
	_clear_name_cache()
	await _free_parts(parts)


func _test_claim_backfills_existing_best() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_ok("{\"writeResults\": [{}, {}]}")
	sender.queue_ok(_hall_own_body(500,
		"res://resources/heroes/keeper.tres", 7))
	sender.queue_ok(_hall_own_body(500,
		"res://resources/heroes/keeper.tres", 7))
	sender.queue_ok("{\"writeResults\": [{}]}")
	var claimed: Dictionary = await host.claim_adventurer_name("Luna")
	_expect_equal(str(claimed.get("status", "")), "ok",
		"name-backfill: the claim succeeds")
	_expect_true(bool(claimed.get("backfilled", false)),
		"name-backfill: the existing best backfills")
	var commit: Dictionary = _commit_with(sender, "mb_hall_v1")
	var fields: Dictionary = ((commit.get("writes", []) as Array)[0]
		as Dictionary).get("update", {}).get("fields", {})
	_expect_equal(str(fields.get("score", {}).get("integerValue", "")),
		"500", "name-backfill: the backfill keeps the best score")
	_expect_equal(str(fields.get("hero", {}).get("stringValue", "")),
		"res://resources/heroes/keeper.tres",
		"name-backfill: the backfill keeps the saved hero")
	_expect_equal(str(fields.get("display", {}).get("stringValue", "")),
		"Luna", "name-backfill: the backfill attaches the handle")
	_clear_name_cache()
	await _free_parts(parts)


func _test_submit_best_carries_handle() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_ok("{\"writeResults\": [{}, {}]}")
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var claimed: Dictionary = await host.claim_adventurer_name("Luna")
	_expect_equal(str(claimed.get("status", "")), "ok",
		"name-submit: the claim succeeds")
	_write_checkpoint({"cycle": 2, "journey_id": "submit-name-j-1"})
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_ok("{\"writeResults\": [{}]}")
	var coord: Node = host.get("_coordinator") as Node
	var submitted: Dictionary = await coord.call("submit_current_best")
	_expect_equal(str(submitted.get("status", "")), "ok",
		"name-submit: the best submits")
	var commit: Dictionary = _commit_with(sender, "mb_hall_v1")
	var fields: Dictionary = ((commit.get("writes", []) as Array)[0]
		as Dictionary).get("update", {}).get("fields", {})
	_expect_equal(str(fields.get("display", {}).get("stringValue", "")),
		"Luna", "name-submit: the production write carries the handle")
	_clear_name_cache()
	await _free_parts(parts)


## A completed name restore keeps the true tutorial bit through a claim of
## a different ask and a local reload; a later stale incomplete same-name
## response carries its bytes honestly but cannot regress the durable bit.
func _test_claim_restore_keeps_completion_bit() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_ok("{\"writeResults\": [{}, {}]}")
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var claimed: Dictionary = await host.claim_adventurer_name("Luna")
	_expect_equal(str(claimed.get("status", "")), "ok",
		"name-bit: the claim succeeds")
	_expect_false(bool(claimed.get("intro_complete", true)),
		"name-bit: the fresh claim starts incomplete")
	sender.queue_ok(_name_row_body("Luna", "luna", false))
	sender.queue_ok("{\"writeResults\": [{}]}")
	var done: Dictionary = await host.mark_intro_complete()
	_expect_equal(str(done.get("status", "")), "ok",
		"name-bit: the bit flips")
	sender.queue_ok(_name_row_body("Luna", "luna", true))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var restored: Dictionary = await host.claim_adventurer_name("Different")
	_expect_equal(str(restored.get("status", "")), "ok",
		"name-bit: the restore succeeds")
	_expect_equal(str(restored.get("display", "")), "Luna",
		"name-bit: the restore keeps the canonical handle")
	_expect_true(bool(restored.get("intro_complete", false)),
		"name-bit: the restore returns the real completion bit")
	Vault.load_vault()
	_expect_true(bool((Vault.verified_name_for_account(CANON_C)
		as Dictionary).get("intro_complete", false)),
		"name-bit: the reload keeps the restored bit")
	sender.queue_ok(_name_row_body("Luna", "luna", false))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var stale: Dictionary = await host.claim_adventurer_name("Different")
	_expect_equal(str(stale.get("status", "")), "ok",
		"name-bit: the stale same-name claim still restores")
	_expect_false(bool(stale.get("intro_complete", true)),
		"name-bit: the stale result carries its own bytes")
	_expect_true(bool((Vault.verified_name_for_account(CANON_C)
		as Dictionary).get("intro_complete", false)),
		"name-bit: the stale response never regresses the cache")
	Vault.load_vault()
	_expect_true(bool((Vault.verified_name_for_account(CANON_C)
		as Dictionary).get("intro_complete", false)),
		"name-bit: the reload still keeps the bit")
	_clear_name_cache()
	await _free_parts(parts)


## All four name wrappers pin to the initiating account: a token wait
## that outlives a switch to B cancels instead of dispatching onto B.
func _test_name_wrappers_cancel_on_token_switch() -> void:
	for route in ["claim", "load", "intro", "backfill"]:
		await _run_token_switch_case(route)


func _run_token_switch_case(route: String) -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var rec_a: NameRecorder = NameRecorder.new()
	_swap_coordinator(parts, rec_a)
	_drop_cached_token(host)
	fake.token_receipt = {"status": "pending"}
	var rec_b: NameRecorder = NameRecorder.new()
	var label: String = "token-switch/%s" % route
	# The swap lands strictly before the token release; the timer
	# callbacks prove the barrier parked the call first.
	get_tree().create_timer(0.1).timeout.connect(
		_swap_to_b.bind(parts, rec_b, label))
	get_tree().create_timer(0.2).timeout.connect(
		_release_token_ok.bind(parts))
	var result: Dictionary = await _call_name_route(host, route)
	_expect_equal(str(result.get("status", "")), "cancelled",
		"token-switch/%s: the retired request cancels" % route)
	_expect_equal(str(result.get("code", "")), "account-retired",
		"token-switch/%s: the cancel names the retirement" % route)
	_expect_true(rec_a.calls.is_empty(),
		"token-switch/%s: nothing dispatched before the token" % route)
	_expect_true(rec_b.calls.is_empty(),
		"token-switch/%s: the next account receives nothing" % route)
	_clear_name_cache()
	await _free_parts(parts)


## A failed token refresh sends no name mutation: the claim fails with
## the token code and the live coordinator stays silent.
func _test_claim_token_failure_sends_nothing() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var rec_a: NameRecorder = NameRecorder.new()
	_swap_coordinator(parts, rec_a)
	_drop_cached_token(host)
	fake.token_receipt = {"status": "error", "code": "token_error"}
	var failed: Dictionary = await host.claim_adventurer_name("Alpha")
	_expect_equal(str(failed.get("status", "")), "failure",
		"token-fail: the claim fails with the token")
	_expect_equal(str(failed.get("code", "")), "token_error",
		"token-fail: the token code passes through")
	_expect_true(rec_a.calls.is_empty(),
		"token-fail: no mutation dispatches without a token")
	_clear_name_cache()
	await _free_parts(parts)


## A token wait that times out fails the same way: no dispatch, no name.
func _test_claim_token_timeout_sends_nothing() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical(
		{"token_wait_seconds": 0.05})
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var rec_a: NameRecorder = NameRecorder.new()
	_swap_coordinator(parts, rec_a)
	_drop_cached_token(host)
	fake.token_receipt = {"status": "pending"}
	var timed_out: Dictionary = await host.claim_adventurer_name("Alpha")
	_expect_equal(str(timed_out.get("status", "")), "failure",
		"token-timeout: the claim fails with the token")
	_expect_equal(str(timed_out.get("code", "")), "token_timeout",
		"token-timeout: the timeout code passes through")
	_expect_true(rec_a.calls.is_empty(),
		"token-timeout: no mutation dispatches without a token")
	_clear_name_cache()
	await _free_parts(parts)


## Shutdown during the token wait cancels the parked claim; the retired
## coordinator receives nothing.
func _test_claim_shutdown_mid_wait_cancels() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var rec_a: NameRecorder = NameRecorder.new()
	_swap_coordinator(parts, rec_a)
	_drop_cached_token(host)
	fake.token_receipt = {"status": "pending"}
	get_tree().create_timer(0.1).timeout.connect(
		_shutdown_mid_wait.bind(parts))
	var result: Dictionary = await _call_name_route(host, "claim")
	_expect_equal(str(result.get("status", "")), "cancelled",
		"shutdown-wait: the parked claim cancels")
	_expect_equal(str(result.get("code", "")), "host-closed",
		"shutdown-wait: the cancel names the closed host")
	_expect_true(rec_a.calls.is_empty(),
		"shutdown-wait: the retired coordinator receives nothing")
	_clear_name_cache()
	await _free_parts(parts)


## A coordinator reply that lands after the account retired is a stale
## completion: the wrapper cancels instead of adopting it, and the next
## account receives nothing.
func _test_claim_stale_completion_cancels() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var rec_a: NameRecorder = NameRecorder.new()
	rec_a.hold_frames = 8
	_swap_coordinator(parts, rec_a)
	var rec_b: NameRecorder = NameRecorder.new()
	# The swap runs synchronously on dispatch, inside A's held reply.
	rec_a.dispatched.connect(_adopt_b.bind(parts, rec_b))
	var changed_before: int = (_fired["changed"] as Array).size()
	var result: Dictionary = await _call_name_route(host, "claim")
	_expect_equal(rec_a.calls.size(), 1,
		"stale-complete: the live coordinator receives the claim")
	_expect_equal(str(result.get("status", "")), "cancelled",
		"stale-complete: the late reply cancels")
	_expect_equal(str(result.get("code", "")), "account-retired",
		"stale-complete: the cancel names the retirement")
	_expect_true(rec_b.calls.is_empty(),
		"stale-complete: the next account receives nothing")
	_expect_equal((_fired["changed"] as Array).size(), changed_before,
		"stale-complete: the stale reply emits nothing")
	_clear_name_cache()
	await _free_parts(parts)


## Retirement through the production path (the deletion/startup shape)
## cancels a parked claim; the next coordinator stays silent.
func _test_claim_retirement_mid_wait_cancels() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var rec_a: NameRecorder = NameRecorder.new()
	_swap_coordinator(parts, rec_a)
	_drop_cached_token(host)
	fake.token_receipt = {"status": "pending"}
	var rec_b: NameRecorder = NameRecorder.new()
	get_tree().create_timer(0.1).timeout.connect(
		_retire_to_recorder.bind(parts, rec_b))
	get_tree().create_timer(0.2).timeout.connect(
		_release_token_ok.bind(parts))
	var result: Dictionary = await _call_name_route(host, "claim")
	_expect_equal(str(result.get("status", "")), "cancelled",
		"retire-wait: the retired request cancels")
	_expect_equal(str(result.get("code", "")), "account-retired",
		"retire-wait: the cancel names the retirement")
	_expect_true(rec_b.calls.is_empty(),
		"retire-wait: the next coordinator receives nothing")
	_clear_name_cache()
	await _free_parts(parts)


## A claim begun before deletion stays cancelled even when the deletion
## later fails on the same account and coordinator: the pinned deletion
## generation retires it either way. A genuinely new request afterwards
## proceeds on the fresh generation.
func _test_claim_cancelled_across_failed_deletion() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	var rec_a: NameRecorder = NameRecorder.new()
	_swap_coordinator(parts, rec_a)
	_drop_cached_token(host)
	fake.token_receipt = {"status": "pending"}
	# Settle the account-level pending without releasing the host waiter,
	# so the real deletion can begin while the claim still waits.
	fake.auto_error = {"code": "token_error"}
	_queue_unclaimed_adventurer(sender)
	sender.queue_reply({"transport": "ok", "code": 403, "body": "{}"})
	var del_box: Dictionary = {}
	get_tree().create_timer(0.1).timeout.connect(
		_begin_deletion_async.bind(parts, del_box))
	get_tree().create_timer(0.15).timeout.connect(
		_assert_deletion_barrier.bind(parts))
	get_tree().create_timer(0.2).timeout.connect(
		_release_token_ok.bind(parts))
	var result: Dictionary = await _call_name_route(host, "claim")
	_expect_equal(str(result.get("status", "")), "cancelled",
		"del-cancel: the pre-deletion claim cancels")
	_expect_equal(str(result.get("code", "")), "account-retired",
		"del-cancel: the cancel names the retirement")
	_expect_true(rec_a.calls.is_empty(),
		"del-cancel: nothing dispatches during deletion")
	_expect_true(await _await_box_key(del_box, "r"),
		"del-cancel: the deletion run settles")
	var deleted: Dictionary = del_box["r"]
	_expect_equal(str(deleted.get("status", "")), "failure",
		"del-cancel: the denied commit fails the run")
	_expect_equal(str(deleted.get("code", "")), "permission-denied",
		"del-cancel: the denial code passes through")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), CANON_C,
		"del-cancel: the failed run keeps the same account")
	var retry: Dictionary = await host.claim_adventurer_name("Beta")
	_expect_equal(str(retry.get("status", "")), "ok",
		"del-cancel: a new request proceeds after failed deletion")
	_expect_equal(rec_a.calls.size(), 1,
		"del-cancel: the new request dispatches once")
	_clear_name_cache()
	await _free_parts(parts)


## A claim still parked when an earlier deletion already failed on the
## same account and coordinator stays cancelled: the pinned deletion
## generation retires it even though no ticket is in flight at resume.
func _test_claim_cancelled_by_earlier_failed_deletion() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	var rec_a: NameRecorder = NameRecorder.new()
	_swap_coordinator(parts, rec_a)
	_drop_cached_token(host)
	fake.token_receipt = {"status": "pending"}
	fake.auto_error = {"code": "token_error"}
	_queue_unclaimed_adventurer(sender)
	sender.queue_reply({"transport": "ok", "code": 403, "body": "{}"})
	var del_box: Dictionary = {}
	get_tree().create_timer(0.05).timeout.connect(
		_fail_deletion_fast.bind(parts, del_box))
	get_tree().create_timer(0.3).timeout.connect(
		_release_token_ok.bind(parts))
	var result: Dictionary = await _call_name_route(host, "claim")
	_expect_equal(str(result.get("status", "")), "cancelled",
		"del-gen: the pre-deletion claim cancels")
	_expect_equal(str(result.get("code", "")), "account-retired",
		"del-gen: the cancel names the retirement")
	_expect_true(rec_a.calls.is_empty(),
		"del-gen: nothing dispatches after the failed run")
	_expect_true((host.get("_deletion_ticket") as Dictionary).is_empty(),
		"del-gen: no ticket is in flight at resume")
	_expect_true(await _await_box_key(del_box, "r"),
		"del-gen: the deletion run settles")
	_expect_equal(str((del_box["r"] as Dictionary).get("status", "")),
		"failure", "del-gen: the denied commit fails the run")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), CANON_C,
		"del-gen: the failed run keeps the same account")
	_clear_name_cache()
	await _free_parts(parts)


## A new request started while deletion is in flight refuses at the sync
## guard instead of queueing behind the destructive run.
func _test_claim_refused_while_deletion_in_flight() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var rec_a: NameRecorder = NameRecorder.new()
	_swap_coordinator(parts, rec_a)
	var delayed: DelayedSender = DelayedSender.new()
	delayed.tree_node = self
	delayed.delay_frames = 45
	_queue_unclaimed_adventurer(delayed)
	delayed.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "ok"}
	host.set("_sender", delayed)
	var del_box: Dictionary = {}
	get_tree().create_timer(0.05).timeout.connect(
		_begin_deletion_async.bind(parts, del_box))
	var commit_seen: bool = false
	for _index in 180:
		for call in (delayed.calls as Array):
			if str((call as Dictionary).get("url", "")).contains(
				"documents:commit"):
				commit_seen = true
				break
		if commit_seen:
			break
		await get_tree().process_frame
	_expect_true(commit_seen,
		"del-refuse: the deletion commit goes outstanding")
	var refused: Dictionary = await host.claim_adventurer_name("Alpha")
	_expect_equal(str(refused.get("status", "")), "failure",
		"del-refuse: the claim refuses during deletion")
	_expect_equal(str(refused.get("code", "")), "deletion-in-flight",
		"del-refuse: the refusal names the flight")
	_expect_true(rec_a.calls.is_empty(),
		"del-refuse: nothing dispatches during deletion")
	_expect_true(await _await_box_key(del_box, "r", 240),
		"del-refuse: the deletion run settles")
	_expect_equal(str((del_box["r"] as Dictionary).get("status", "")),
		"ok", "del-refuse: the held deletion completes")
	_expect_true(str((host.account_state() as Dictionary).get(
		"public_id", "")) != CANON_C,
		"del-refuse: the completed run rotates the account")
	_clear_name_cache()
	await _free_parts(parts)


const ATT_NOW: int = 1791367200  # 2026-10-07T10:00:00Z.


## Bare HUD stand-in: records attendance receipts without a scene. Carries
## the rank calls too, so a leaked stub can never break a later rank test.
class AttHudStub extends Node:
	var announced: Array = []

	func announce(text: String, _color: Color) -> void:
		announced.append(text)

	func clear_cloud_rank() -> void:
		pass

	func set_cloud_rank(_text: String) -> void:
		pass


## Bare dialogue stand-in: reports open so the receipt gate drops.
class AttDialogueStub extends Node:
	var open: bool = true

	func is_open() -> bool:
		return open


func _att_rfc(seconds: int) -> String:
	return Time.get_datetime_string_from_unix_time(maxi(seconds, 0)) \
		.replace(" ", "T") + "Z"


func _att_missing_body(read_time: String = "") -> String:
	var stamp: String = read_time
	if stamp.is_empty():
		stamp = _att_rfc(ATT_NOW)
	return JSON.stringify([{"missing": "mb_attendance_v1/x",
		"readTime": stamp}])


func _att_row_body(last_claim: String, install: String,
		read_time: String = "", update_time: String = "",
		prev_claim: String = "", prev_install: String = "") -> String:
	var stamp: String = read_time
	if stamp.is_empty():
		stamp = _att_rfc(ATT_NOW)
	var swapped: String = update_time
	if swapped.is_empty():
		swapped = last_claim
	var fields: Dictionary = {
		"public_id": {"stringValue": CANON_C},
		"uid": {"stringValue": UID_A},
		"install_id": {"stringValue": install},
		"last_claim_at": {"timestampValue": last_claim},
		"schema": {"integerValue": "1"},
	}
	if not prev_claim.is_empty():
		fields["prev_claim_at"] = {"timestampValue": prev_claim}
	if not prev_install.is_empty():
		fields["prev_install_id"] = {"stringValue": prev_install}
	return JSON.stringify([{
		"found": {
			"name": "projects/p/databases/(default)/documents/mb_attendance_v1/x",
			"fields": fields,
			"updateTime": swapped,
		},
		"readTime": stamp,
	}])


## Every attendance commit write this sender carried, oldest first, parsed
## from the recorded request bodies.
func _att_commit_writes(sender: RefCounted) -> Array:
	var writes: Array = []
	for call in (sender.calls as Array):
		if not str((call as Dictionary).get("url", "")).contains(
				"documents:commit"):
			continue
		var body: Variant = JSON.parse_string(
			str((call as Dictionary).get("body", "")))
		if typeof(body) != TYPE_DICTIONARY:
			continue
		var each: Array = (body as Dictionary).get("writes", [])
		if each.is_empty():
			continue
		writes.append(each[0])
	return writes


func _att_commit_body(commit_time: String) -> String:
	return JSON.stringify({"writeResults": [{}],
		"commitTime": commit_time})


## First attendance claim over the real stack: a missing server row plus an
## acknowledged commit grants exactly two coins with a stable receipt, a
## live twelve-hour deadline, one signal, and a queued HUD receipt. Reload
## keeps the coins and the key together.
func _test_attendance_first_claim_grants_two() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var fired: Array = []
	host.production_attendance.connect(
		func(snap: Dictionary) -> void: fired.append(
			(snap as Dictionary).duplicate()))
	var install: String = Vault.ensure_install_id()
	var before: int = Vault.continue_coins
	var calls_before: int = (sender.calls as Array).size()
	var grants_before: int = (
		Vault.continue_coin_grants as Dictionary).size()
	sender.queue_ok(_att_missing_body())
	sender.queue_ok(_att_commit_body(_att_rfc(ATT_NOW)))
	var result: Dictionary = await host.claim_attendance()
	var receipt: String = "attendance:%s:%d:%s" % [CANON_C, ATT_NOW,
		install]
	_expect_equal(str(result.get("status", "")), "granted",
		"att-first: the claim grants")
	_expect_equal(int(result.get("coins", 0)), 2,
		"att-first: the grant is exactly two")
	_expect_equal(str(result.get("receipt", "")), receipt,
		"att-first: the receipt names the claim")
	_expect_true(bool(result.get("granted", false)),
		"att-first: the wallet took the coins")
	_expect_false(bool(result.get("duplicate", true)),
		"att-first: the first grant is not a duplicate")
	_expect_equal(str(result.get("next_eligible_utc", "")),
		_att_rfc(ATT_NOW + 43200),
		"att-first: the deadline is twelve hours out")
	_expect_equal(int(result.get("remaining_seconds", -1)), 43200,
		"att-first: the full cooldown remains")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-first: the balance rises by two")
	_expect_equal(int((Vault.continue_coin_grants as Dictionary).get(
		receipt, 0)), 2,
		"att-first: the receipt lands with the coins")
	_expect_equal((Vault.continue_coin_grants as Dictionary).size(),
		grants_before + 1,
		"att-first: one new grant entry only")
	_expect_equal((sender.calls as Array).size() - calls_before, 2,
		"att-first: one read plus one commit")
	_expect_equal(fired.size(), 1,
		"att-first: one attendance signal fires")
	var first: Dictionary = (fired[0] as Dictionary) \
		if not fired.is_empty() else {}
	_expect_equal(str(first.get("receipt", "")), receipt,
		"att-first: the signal carries the receipt")
	var view: Dictionary = host.attendance_view()
	_expect_equal(str(view.get("state", "")), "ready",
		"att-first: the view is live")
	_expect_equal(str(view.get("source", "")), "live",
		"att-first: the view is server-confirmed")
	_expect_equal(str(view.get("next_eligible_utc", "")),
		_att_rfc(ATT_NOW + 43200),
		"att-first: the view carries the deadline")
	Vault.load_vault()
	_expect_equal(Vault.continue_coins, before + 2,
		"att-first: the reload keeps the coins")
	_expect_equal(int((Vault.continue_coin_grants as Dictionary).get(
		receipt, 0)), 2,
		"att-first: the reload keeps the key")
	await _free_parts(parts)


## A row claimed eleven hours ago on another install cools down: no commit,
## no coins, no receipt, and the live view names the remaining hour.
func _test_attendance_cooldown_grants_nothing() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var before: int = Vault.continue_coins
	var calls_before: int = (sender.calls as Array).size()
	var grants_before: int = (
		Vault.continue_coin_grants as Dictionary).size()
	sender.queue_ok(_att_row_body(_att_rfc(ATT_NOW - 39600),
		"install-other-9"))
	var result: Dictionary = await host.request_attendance()
	_expect_equal(str(result.get("status", "")), "cooldown",
		"att-cool: the repeat cools down")
	_expect_equal(int(result.get("remaining_seconds", -1)), 3600,
		"att-cool: one hour remains")
	_expect_equal(str(result.get("next_eligible_utc", "")),
		_att_rfc(ATT_NOW + 3600),
		"att-cool: the deadline names the hour")
	_expect_false(bool(result.get("granted", false)),
		"att-cool: nothing grants")
	_expect_equal(Vault.continue_coins, before,
		"att-cool: the balance holds")
	_expect_equal((Vault.continue_coin_grants as Dictionary).size(),
		grants_before,
		"att-cool: no grant entry appears")
	_expect_equal((sender.calls as Array).size() - calls_before, 1,
		"att-cool: the read alone goes out")
	_expect_true(str(host.get("_attendance_receipt_pending")).is_empty(),
		"att-cool: no receipt queues")
	var view: Dictionary = host.attendance_view()
	_expect_equal(str(view.get("source", "")), "live",
		"att-cool: the view is server-confirmed")
	_expect_equal(int(view.get("remaining_seconds", -1)), 3600,
		"att-cool: the view names the hour")
	await _free_parts(parts)


## An acknowledged commit without a timestamp stays uncertain: no coins
## until the re-read proves the row is ours, then one top-up lands.
func _test_attendance_same_install_recovers_after_uncertain_ack() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var install: String = Vault.ensure_install_id()
	var before: int = Vault.continue_coins
	sender.queue_ok(_att_missing_body())
	sender.queue_ok("{}")
	var uncertain: Dictionary = await host.claim_attendance()
	_expect_equal(str(uncertain.get("status", "")), "failure",
		"att-uncertain: the timeless commit fails")
	_expect_equal(str(uncertain.get("code", "")),
		"attendance-uncertain-ack",
		"att-uncertain: the code names the ack")
	_expect_equal(Vault.continue_coins, before,
		"att-uncertain: no coins land early")
	var interim: Dictionary = host.attendance_view()
	_expect_equal(str(interim.get("state", "")), "offline",
		"att-uncertain: the interim view admits the gap")
	sender.queue_ok(_att_row_body(_att_rfc(ATT_NOW), install))
	var again: Dictionary = await host.claim_attendance()
	var receipt: String = "attendance:%s:%d:%s" % [CANON_C, ATT_NOW,
		install]
	_expect_equal(str(again.get("status", "")), "already-claimed",
		"att-uncertain: the re-read settles")
	_expect_true(bool(again.get("granted", false)),
		"att-uncertain: the top-up lands")
	_expect_equal(str(again.get("receipt", "")), receipt,
		"att-uncertain: the receipt matches the row")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-uncertain: exactly two arrive")
	_expect_equal(int((Vault.continue_coin_grants as Dictionary).get(
		receipt, 0)), 2,
		"att-uncertain: the key lands with the coins")
	await _free_parts(parts)


## A blocked wallet temp file fails the local grant without losing the
## server claim: nothing lands, and the retry after repair grants once
## under the same receipt.
func _test_attendance_wallet_failure_recovers() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var install: String = Vault.ensure_install_id()
	var before: int = Vault.continue_coins
	var receipt: String = "attendance:%s:%d:%s" % [CANON_C, ATT_NOW,
		install]
	sender.queue_ok(_att_missing_body())
	sender.queue_ok(_att_commit_body(_att_rfc(ATT_NOW)))
	var temp: String = ProjectSettings.globalize_path(
		Vault.TEMP_SAVE_PATH)
	DirAccess.make_dir_recursive_absolute(temp)
	var failed: Dictionary = await host.claim_attendance()
	DirAccess.remove_absolute(temp)
	_expect_equal(str(failed.get("status", "")), "failure",
		"att-wallet: the blocked grant fails")
	_expect_equal(str(failed.get("code", "")), "local-grant-failed",
		"att-wallet: the code names the wallet")
	_expect_true(bool(failed.get("server_claimed", false)),
		"att-wallet: the server claim survives")
	_expect_equal(str(failed.get("receipt", "")), receipt,
		"att-wallet: the receipt names the claim")
	_expect_equal(Vault.continue_coins, before,
		"att-wallet: the balance holds")
	_expect_false((Vault.continue_coin_grants as Dictionary).has(
		receipt),
		"att-wallet: no key lands")
	sender.queue_ok(_att_row_body(_att_rfc(ATT_NOW), install))
	var again: Dictionary = await host.claim_attendance()
	_expect_equal(str(again.get("status", "")), "already-claimed",
		"att-wallet: the retry settles")
	_expect_true(bool(again.get("granted", false)),
		"att-wallet: the retry grants")
	_expect_equal(str(again.get("receipt", "")), receipt,
		"att-wallet: the retry reuses the receipt")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-wallet: exactly two arrive once")
	_expect_equal(int((Vault.continue_coin_grants as Dictionary).get(
		receipt, 0)), 2,
		"att-wallet: the key lands with the coins")
	await _free_parts(parts)


## Entry checks never block play: local guests, deletion, restore, and
## overlap skip without touching the wire, and a real double tap grants
## once from a single read plus commit.
func _test_attendance_request_skips_and_double_tap() -> void:
	_wipe_all()
	_clear_name_cache()
	_clear_attendance_cache()
	var guest_parts: Dictionary = _make_parts()
	var guest_host: Node = guest_parts["host"]
	var guest_fake: Node = guest_parts["fake"]
	var guest_sender: RefCounted = guest_parts["sender"]
	guest_fake.guest_receipt = {"status": "error", "code": "network_error",
		"retryable": true}
	guest_host.startup()
	guest_host.begin_guest()
	var skipped: Dictionary = await guest_host.request_attendance()
	_expect_equal(str(skipped.get("status", "")), "skipped",
		"att-skip: the local guest skips")
	_expect_equal(str(skipped.get("code", "")), "local-guest",
		"att-skip: the skip names the guest")
	_expect_true((guest_sender.calls as Array).is_empty(),
		"att-skip: the local guest sends nothing")
	await _free_parts(guest_parts)
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var calls_before: int = (sender.calls as Array).size()
	host.set("_deletion_ticket", {"generation": 7})
	var del_skip: Dictionary = await host.request_attendance()
	_expect_equal(str(del_skip.get("code", "")), "deletion-in-flight",
		"att-skip: deletion skips")
	host.set("_deletion_ticket", {})
	host.set("_restore_state", "checking")
	var restore_skip: Dictionary = await host.request_attendance()
	_expect_equal(str(restore_skip.get("code", "")), "restore-pending",
		"att-skip: restore skips")
	host.set("_restore_state", "")
	host.set("_attendance_in_flight", true)
	var busy_skip: Dictionary = await host.request_attendance()
	_expect_equal(str(busy_skip.get("code", "")), "in-flight",
		"att-skip: overlap skips")
	host.set("_attendance_in_flight", false)
	_expect_equal((sender.calls as Array).size(), calls_before,
		"att-skip: the skips send nothing")
	sender.queue_ok(_att_missing_body())
	sender.queue_ok(_att_commit_body(_att_rfc(ATT_NOW)))
	var before: int = Vault.continue_coins
	var tap_before: int = (sender.calls as Array).size()
	# A detached wrapper coroutine cannot park on this Godot build, so the
	# first tap parks at the token barrier in the test while a timer fires
	# the second tap mid-flight; the release then lets the first land.
	_drop_cached_token(host)
	var fake: Node = parts["fake"]
	fake.token_receipt = {"status": "pending"}
	var tap_box: Dictionary = {}
	get_tree().create_timer(0.05).timeout.connect(
		_request_attendance_async.bind(parts, tap_box))
	get_tree().create_timer(0.15).timeout.connect(
		_release_token_ok.bind(parts))
	var first: Dictionary = await host.request_attendance()
	_expect_equal(str(first.get("status", "")), "granted",
		"att-tap: the first tap lands")
	_expect_true(await _await_box_key(tap_box, "r"),
		"att-tap: the second tap settles")
	var dup: Dictionary = tap_box["r"]
	_expect_equal(str(dup.get("status", "")), "skipped",
		"att-tap: the second tap skips")
	_expect_equal(str(dup.get("code", "")), "in-flight",
		"att-tap: the skip names the flight")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-tap: exactly two arrive")
	_expect_equal((sender.calls as Array).size() - tap_before, 2,
		"att-tap: one read plus one commit")
	await _free_parts(parts)


## Fire one entry check from a timer while the test holds another: the
## parked call cannot run detached, so the timer carries the overlap.
func _request_attendance_async(parts: Dictionary,
		box: Dictionary) -> void:
	var host: Node = parts["host"]
	box["r"] = await host.request_attendance()


## A granted entry claim queues a five-language receipt; the HUD shows it
## once, while an IME field or an open NPC dialogue drops the overlay and
## the wallet keeps the coins.
func _test_attendance_receipt_flush_and_suppression() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var before: int = Vault.continue_coins
	sender.queue_ok(_att_missing_body())
	sender.queue_ok(_att_commit_body(_att_rfc(ATT_NOW)))
	var result: Dictionary = await host.request_attendance()
	_expect_equal(str(result.get("status", "")), "granted",
		"att-receipt: the entry claim grants")
	var pending: String = str(host.get("_attendance_receipt_pending"))
	_expect_false(pending.is_empty(),
		"att-receipt: the grant queues a receipt")
	_expect_true(pending.contains("+2"),
		"att-receipt: the receipt names two coins")
	var hud: AttHudStub = AttHudStub.new()
	hud.add_to_group("moonlit_hud")
	add_child(hud)
	host.call("_flush_attendance_receipt")
	_expect_equal((hud.announced as Array).size(), 1,
		"att-receipt: the HUD shows it once")
	var shown: String = str((hud.announced as Array)[0]) \
		if not (hud.announced as Array).is_empty() else ""
	_expect_equal(shown, pending,
		"att-receipt: the HUD shows the queued text")
	_expect_true(str(host.get("_attendance_receipt_pending")).is_empty(),
		"att-receipt: the flush clears the queue")
	var field: LineEdit = LineEdit.new()
	add_child(field)
	field.grab_focus()
	await _frames(1)
	host.set("_attendance_receipt_pending", "att-queued-ime")
	host.call("_flush_attendance_receipt")
	_expect_equal((hud.announced as Array).size(), 1,
		"att-receipt: the IME focus drops the overlay")
	_expect_true(str(host.get("_attendance_receipt_pending")).is_empty(),
		"att-receipt: the dropped queue clears")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-receipt: the wallet keeps the coins")
	field.release_focus()
	field.queue_free()
	var talk: AttDialogueStub = AttDialogueStub.new()
	talk.add_to_group("moonlit_dialogue")
	add_child(talk)
	host.set("_attendance_receipt_pending", "att-queued-talk")
	host.call("_flush_attendance_receipt")
	_expect_equal((hud.announced as Array).size(), 1,
		"att-receipt: the open dialogue drops the overlay")
	_expect_true(str(host.get("_attendance_receipt_pending")).is_empty(),
		"att-receipt: the dialogue drop clears")
	hud.queue_free()
	talk.queue_free()
	await _free_parts(parts)


## A foreground return re-checks without granting again, and an outage
## grants nothing while the live deadline survives for reminders.
func _test_attendance_foreground_and_offline_cache() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var install: String = Vault.ensure_install_id()
	var before: int = Vault.continue_coins
	sender.queue_ok(_att_missing_body())
	sender.queue_ok(_att_commit_body(_att_rfc(ATT_NOW)))
	var entered: Dictionary = await host.request_attendance()
	_expect_equal(str(entered.get("status", "")), "granted",
		"att-fore: the entry claim grants")
	sender.queue_ok(_att_row_body(_att_rfc(ATT_NOW), install))
	var again: Dictionary = await host.notify_foreground_return()
	_expect_equal(str(again.get("status", "")), "already-claimed",
		"att-fore: the return re-checks")
	_expect_false(bool(again.get("granted", true)),
		"att-fore: no new coins land")
	_expect_equal(str(again.get("receipt", "")),
		str(entered.get("receipt", "")),
		"att-fore: the re-check names the same receipt")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-fore: the balance holds")
	sender.queue_reply({"transport": "offline", "code": 0, "body": ""})
	var off: Dictionary = await host.request_attendance()
	_expect_equal(str(off.get("status", "")), "offline",
		"att-fore: the outage stays offline")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-fore: the outage grants nothing")
	var view: Dictionary = host.attendance_view()
	_expect_equal(str(view.get("source", "")), "live",
		"att-fore: the live view survives")
	_expect_equal(str(view.get("next_eligible_utc", "")),
		_att_rfc(ATT_NOW + 43200),
		"att-fore: the deadline survives")
	await _free_parts(parts)


## Linking a provider keeps the attendance record on the same canonical
## ID without a second grant; signing out rotates to a guest with no
## cached deadline.
func _test_attendance_link_keeps_record() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	var install: String = Vault.ensure_install_id()
	var before: int = Vault.continue_coins
	sender.queue_ok(_att_missing_body())
	sender.queue_ok(_att_commit_body(_att_rfc(ATT_NOW)))
	var result: Dictionary = await host.claim_attendance()
	_expect_equal(str(result.get("status", "")), "granted",
		"att-link: the guest claims first")
	fake.link_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "google"}}
	var linked: Dictionary = host.link_provider("google")
	await _frames(2)
	_expect_equal(str(linked.get("status", "")), "ok",
		"att-link: the link succeeds")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), CANON_C,
		"att-link: the link keeps the canonical ID")
	sender.queue_ok(_att_row_body(_att_rfc(ATT_NOW), install))
	var again: Dictionary = await host.claim_attendance()
	_expect_equal(str(again.get("status", "")), "already-claimed",
		"att-link: the link keeps the record")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-link: no second grant lands")
	host.sign_out()
	var rotated: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_expect_true(rotated != CANON_C and not rotated.is_empty(),
		"att-link: sign-out rotates")
	_expect_true((Vault.attendance_next_for_account(rotated)
		as Dictionary).is_empty(),
		"att-link: the rotated guest reads no deadline")
	await _free_parts(parts)


## An attendance claim parked before deletion stays cancelled even though
## the deletion fails on the same account; a genuinely new request after
## the failure proceeds.
func _test_attendance_cancelled_across_failed_deletion() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	var rec_a: NameRecorder = NameRecorder.new()
	_swap_coordinator(parts, rec_a)
	_drop_cached_token(host)
	fake.token_receipt = {"status": "pending"}
	fake.auto_error = {"code": "token_error"}
	_queue_unclaimed_adventurer(sender)
	sender.queue_reply({"transport": "ok", "code": 403, "body": "{}"})
	var del_box: Dictionary = {}
	get_tree().create_timer(0.1).timeout.connect(
		_begin_deletion_async.bind(parts, del_box))
	get_tree().create_timer(0.15).timeout.connect(
		_assert_deletion_barrier.bind(parts))
	get_tree().create_timer(0.2).timeout.connect(
		_release_token_ok.bind(parts))
	var result: Dictionary = await host.claim_attendance()
	_expect_equal(str(result.get("status", "")), "cancelled",
		"att-del: the pre-deletion claim cancels")
	_expect_equal(str(result.get("code", "")), "account-retired",
		"att-del: the cancel names the retirement")
	_expect_true(rec_a.calls.is_empty(),
		"att-del: nothing dispatches during deletion")
	_expect_true(await _await_box_key(del_box, "r"),
		"att-del: the deletion run settles")
	var deleted: Dictionary = del_box["r"]
	_expect_equal(str(deleted.get("status", "")), "failure",
		"att-del: the denied commit fails the run")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), CANON_C,
		"att-del: the failed run keeps the same account")
	var retry: Dictionary = await host.claim_attendance()
	_expect_equal(str(retry.get("status", "")), "granted",
		"att-del: a new request proceeds after failed deletion")
	_expect_equal(rec_a.calls.size(), 1,
		"att-del: the new request dispatches once")
	await _free_parts(parts)


## A fresh attendance claim refuses while a deletion commit is in flight
## and dispatches nothing; the held deletion still completes.
func _test_attendance_refused_while_deletion_in_flight() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var rec_a: NameRecorder = NameRecorder.new()
	_swap_coordinator(parts, rec_a)
	var delayed: DelayedSender = DelayedSender.new()
	delayed.tree_node = self
	delayed.delay_frames = 45
	_queue_unclaimed_adventurer(delayed)
	delayed.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "ok"}
	host.set("_sender", delayed)
	var del_box: Dictionary = {}
	get_tree().create_timer(0.05).timeout.connect(
		_begin_deletion_async.bind(parts, del_box))
	var commit_seen: bool = false
	for _index in 180:
		for call in (delayed.calls as Array):
			if str((call as Dictionary).get("url", "")).contains(
					"documents:commit"):
				commit_seen = true
				break
		if commit_seen:
			break
		await get_tree().process_frame
	_expect_true(commit_seen,
		"att-refuse: the deletion commit goes outstanding")
	var refused: Dictionary = await host.claim_attendance()
	_expect_equal(str(refused.get("status", "")), "failure",
		"att-refuse: the claim refuses during deletion")
	_expect_equal(str(refused.get("code", "")), "deletion-in-flight",
		"att-refuse: the refusal names the flight")
	_expect_true(rec_a.calls.is_empty(),
		"att-refuse: nothing dispatches during deletion")
	_expect_true(await _await_box_key(del_box, "r", 240),
		"att-refuse: the deletion run settles")
	_expect_equal(str((del_box["r"] as Dictionary).get("status", "")),
		"ok", "att-refuse: the held deletion completes")
	await _free_parts(parts)


## A server-acknowledged reward lost to a blocked wallet save recovers
## before the next eligible period advances: the old two coins land under
## their own receipt, the new claim lands under the next, and the advance
## commit carries the old stamp byte for byte with its swap intact.
func _test_attendance_backfills_before_advance() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var install: String = Vault.ensure_install_id()
	var before: int = Vault.continue_coins
	var stamp: String = "2026-10-06T21:00:00.75Z"
	var first: int = ATT_NOW - 46800
	var swapped: String = "2026-10-06T21:05:00.125Z"
	var old_key: String = "attendance:%s:%d:%s" % [CANON_C, first,
		install]
	var new_key: String = "attendance:%s:%d:%s" % [CANON_C, ATT_NOW,
		install]
	sender.queue_ok(_att_missing_body(stamp))
	sender.queue_ok(_att_commit_body(stamp))
	var temp: String = ProjectSettings.globalize_path(
		Vault.TEMP_SAVE_PATH)
	DirAccess.make_dir_recursive_absolute(temp)
	var failed: Dictionary = await host.request_attendance()
	DirAccess.remove_absolute(temp)
	_expect_equal(str(failed.get("status", "")), "failure",
		"att-back: the blocked first grant fails")
	_expect_equal(str(failed.get("receipt", "")), old_key,
		"att-back: the failure names the earned receipt")
	_expect_equal(Vault.continue_coins, before,
		"att-back: nothing lands while blocked")
	_expect_true(str(host.get("_attendance_receipt_pending")).is_empty(),
		"att-back: no receipt queues for nothing")
	Vault.load_vault()
	_expect_equal(Vault.continue_coins, before,
		"att-back: the restart keeps the honest balance")
	sender.queue_ok(_att_row_body(stamp, install, _att_rfc(ATT_NOW),
		swapped))
	sender.queue_ok(_att_commit_body(_att_rfc(ATT_NOW)))
	var advanced: Dictionary = await host.request_attendance()
	_expect_equal(str(advanced.get("status", "")), "granted",
		"att-back: the next period advances")
	_expect_true(bool(advanced.get("backfilled", false)),
		"att-back: the old reward backfills first")
	_expect_equal(str(advanced.get("backfilled_receipt", "")), old_key,
		"att-back: the backfill names the old receipt")
	_expect_equal(str(advanced.get("receipt", "")), new_key,
		"att-back: the advance names the new receipt")
	_expect_equal(Vault.continue_coins, before + 4,
		"att-back: both earned visits land")
	_expect_equal(int((Vault.continue_coin_grants as Dictionary).get(
		old_key, 0)), 2,
		"att-back: the old key lands with its coins")
	_expect_equal(int((Vault.continue_coin_grants as Dictionary).get(
		new_key, 0)), 2,
		"att-back: the new key lands with its coins")
	_expect_true(str(host.get("_attendance_receipt_pending")).contains(
		"+4"), "att-back: the receipt names all four coins")
	var writes: Array = _att_commit_writes(sender)
	_expect_equal(writes.size(), 2,
		"att-back: one create plus one advance commit")
	var create: Dictionary = writes[0]
	_expect_true(not ((create.get("update", {}) as Dictionary).get(
		"fields", {}) as Dictionary).has("prev_claim_at"),
		"att-back: the create carries no previous stamp")
	var advance: Dictionary = writes[1]
	_expect_equal(str((advance.get("currentDocument", {}) as Dictionary
		).get("updateTime", "")), swapped,
		"att-back: the advance swaps on the read updateTime")
	var fields: Dictionary = (advance.get("update", {}) as Dictionary
		).get("fields", {})
	_expect_equal(str((fields.get("prev_claim_at", {}) as Dictionary
		).get("timestampValue", "")), stamp,
		"att-back: the advance carries the old stamp exactly")
	_expect_equal(str((fields.get("prev_install_id", {}) as Dictionary
		).get("stringValue", "")), install,
		"att-back: the advance carries the old install")
	var view: Dictionary = host.attendance_view()
	_expect_equal(str(view.get("receipt", "")), new_key,
		"att-back: the live view names the newest receipt")
	await _free_parts(parts)


## Another install's eligible row advances without granting its reward
## into this wallet: only the new claim lands, carrying the foreign
## stamp and install so the earning install can still recover.
func _test_attendance_other_install_advance_carries_prev() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var install: String = Vault.ensure_install_id()
	var before: int = Vault.continue_coins
	var old: String = _att_rfc(ATT_NOW - 46800)
	var other: String = "install-other-9"
	sender.queue_ok(_att_row_body(old, other))
	sender.queue_ok(_att_commit_body(_att_rfc(ATT_NOW)))
	var advanced: Dictionary = await host.request_attendance()
	_expect_equal(str(advanced.get("status", "")), "granted",
		"att-xback: the foreign row advances")
	_expect_false(bool(advanced.get("backfilled", true)),
		"att-xback: the foreign reward never backfills here")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-xback: only the new claim lands")
	_expect_false((Vault.continue_coin_grants as Dictionary).has(
		"attendance:%s:%d:%s" % [CANON_C, ATT_NOW - 46800, other]),
		"att-xback: no foreign key lands")
	var writes: Array = _att_commit_writes(sender)
	_expect_equal(writes.size(), 1,
		"att-xback: one advance commit goes out")
	var fields: Dictionary = ((writes[0] as Dictionary).get("update", {})
		as Dictionary).get("fields", {})
	_expect_equal(str((fields.get("prev_claim_at", {}) as Dictionary
		).get("timestampValue", "")), old,
		"att-xback: the advance carries the foreign stamp")
	_expect_equal(str((fields.get("prev_install_id", {}) as Dictionary
		).get("stringValue", "")), other,
		"att-xback: the advance carries the foreign install")
	_expect_true(str(host.get("_attendance_receipt_pending")).contains(
		"+2"), "att-xback: the receipt names two coins")
	_expect_equal(str((fields.get("install_id", {}) as Dictionary
		).get("stringValue", "")), install,
		"att-xback: the advance binds the receiving install")
	await _free_parts(parts)


## A held foreign row carrying this install's previous stamp backfills
## it without committing: the earned two land, the cooldown stands, and
## the receipt shows for the backfill alone.
func _test_attendance_cooldown_backfills_carried_prev() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var install: String = Vault.ensure_install_id()
	var before: int = Vault.continue_coins
	var calls_before: int = (sender.calls as Array).size()
	var last: String = _att_rfc(ATT_NOW - 3600)
	var prev: String = _att_rfc(ATT_NOW - 46800)
	var old_key: String = "attendance:%s:%d:%s" % [CANON_C,
		ATT_NOW - 46800, install]
	sender.queue_ok(_att_row_body(last, "install-other-9",
		_att_rfc(ATT_NOW), "", prev, install))
	var held: Dictionary = await host.request_attendance()
	_expect_equal(str(held.get("status", "")), "cooldown",
		"att-prev: the foreign period holds")
	_expect_true(bool(held.get("backfilled", false)),
		"att-prev: the carried reward backfills")
	_expect_equal(str(held.get("backfilled_receipt", "")), old_key,
		"att-prev: the backfill names the old receipt")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-prev: exactly the earned two land")
	_expect_equal((sender.calls as Array).size() - calls_before, 1,
		"att-prev: the read alone goes out")
	_expect_true(str(host.get("_attendance_receipt_pending")).contains(
		"+2"), "att-prev: the receipt shows the backfill")
	var view: Dictionary = host.attendance_view()
	_expect_equal(str(view.get("receipt", "")), old_key,
		"att-prev: the live view names the backfilled receipt")
	await _free_parts(parts)


## Re-reading the same carried row backfills once: the second visit
## finds the receipt applied, grants nothing more, and the restart
## between keeps the key with its coins.
func _test_attendance_backfill_replay_is_idempotent() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var install: String = Vault.ensure_install_id()
	var before: int = Vault.continue_coins
	var last: String = _att_rfc(ATT_NOW - 3600)
	var prev: String = _att_rfc(ATT_NOW - 46800)
	var old_key: String = "attendance:%s:%d:%s" % [CANON_C,
		ATT_NOW - 46800, install]
	sender.queue_ok(_att_row_body(last, "install-other-9",
		_att_rfc(ATT_NOW), "", prev, install))
	var held: Dictionary = await host.request_attendance()
	_expect_true(bool(held.get("backfilled", false)),
		"att-replay: the first visit backfills")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-replay: the earned two land")
	Vault.load_vault()
	_expect_equal(Vault.continue_coins, before + 2,
		"att-replay: the restart keeps the backfill")
	sender.queue_ok(_att_row_body(last, "install-other-9",
		_att_rfc(ATT_NOW), "", prev, install))
	var again: Dictionary = await host.request_attendance()
	_expect_equal(str(again.get("status", "")), "cooldown",
		"att-replay: the second visit still holds")
	_expect_false(bool(again.get("backfilled", true)),
		"att-replay: the second visit backfills nothing")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-replay: the replay adds nothing")
	_expect_equal(int((Vault.continue_coin_grants as Dictionary).get(
		old_key, 0)), 2,
		"att-replay: the key lands exactly once")
	await _free_parts(parts)


## An uncertain advance commit still backfills first: the old two land
## with their receipt while the new claim stays unknown, and the next
## visit tops the new claim up without ever doubling the old.
func _test_attendance_uncertain_advance_recovers() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var install: String = Vault.ensure_install_id()
	var before: int = Vault.continue_coins
	var stamp: String = _att_rfc(ATT_NOW - 46800)
	var old_key: String = "attendance:%s:%d:%s" % [CANON_C,
		ATT_NOW - 46800, install]
	var new_key: String = "attendance:%s:%d:%s" % [CANON_C, ATT_NOW,
		install]
	sender.queue_ok(_att_missing_body(stamp))
	sender.queue_ok(_att_commit_body(stamp))
	var temp: String = ProjectSettings.globalize_path(
		Vault.TEMP_SAVE_PATH)
	DirAccess.make_dir_recursive_absolute(temp)
	var failed: Dictionary = await host.request_attendance()
	DirAccess.remove_absolute(temp)
	_expect_equal(str(failed.get("code", "")), "local-grant-failed",
		"att-unadv: the blocked first grant fails")
	sender.queue_ok(_att_row_body(stamp, install))
	sender.queue_ok("{}")
	var uncertain: Dictionary = await host.request_attendance()
	_expect_equal(str(uncertain.get("code", "")),
		"attendance-uncertain-ack",
		"att-unadv: the timeless advance stays uncertain")
	_expect_true(bool(uncertain.get("backfilled", false)),
		"att-unadv: the old reward backfills anyway")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-unadv: the old two land alone")
	_expect_true(str(host.get("_attendance_receipt_pending")).contains(
		"+2"), "att-unadv: the receipt names the backfill")
	host.set("_attendance_receipt_pending", "")
	sender.queue_ok(_att_row_body(_att_rfc(ATT_NOW), install,
		_att_rfc(ATT_NOW + 3600)))
	var topped: Dictionary = await host.request_attendance()
	_expect_equal(str(topped.get("status", "")), "already-claimed",
		"att-unadv: the re-read settles the new claim")
	_expect_true(bool(topped.get("granted", false)),
		"att-unadv: the new claim tops up")
	_expect_equal(str(topped.get("receipt", "")), new_key,
		"att-unadv: the top-up names the new receipt")
	_expect_equal(Vault.continue_coins, before + 4,
		"att-unadv: both earned visits land")
	_expect_equal(int((Vault.continue_coin_grants as Dictionary).get(
		old_key, 0)), 2,
		"att-unadv: the old key never doubles")
	Vault.load_vault()
	_expect_equal(Vault.continue_coins, before + 4,
		"att-unadv: the restart keeps both visits")
	await _free_parts(parts)


## A backfill refused by the eviction floor is skipped, never repaid,
## while the genuine new claim still advances: the old receipt lands
## nothing, the new commit lands two, and the result names the skipped
## receipt. Retired history never freezes future rewards.
func _test_attendance_ambiguous_backfill_skips_and_advances() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var install: String = Vault.ensure_install_id()
	var before: int = Vault.continue_coins
	var stamp: String = _att_rfc(ATT_NOW - 46800)
	var old_key: String = "attendance:%s:%d:%s" % [CANON_C,
		ATT_NOW - 46800, install]
	var new_key: String = "attendance:%s:%d:%s" % [CANON_C, ATT_NOW,
		install]
	# Narrow white-box seam: the floor normally folds from real
	# evictions (vault suite and the pruned-return test below);
	# pinning it here isolates the coordinator's skip mapping.
	Vault.attendance_floor = ATT_NOW
	sender.queue_ok(_att_row_body(stamp, install))
	sender.queue_ok(_att_commit_body(_att_rfc(ATT_NOW)))
	var advanced: Dictionary = await host.request_attendance()
	Vault.attendance_floor = 0
	_expect_equal(str(advanced.get("status", "")), "granted",
		"att-amb: the new claim still advances")
	_expect_false(bool(advanced.get("backfilled", true)),
		"att-amb: the old receipt never backfills")
	_expect_true(bool(advanced.get("backfill_skipped", false)),
		"att-amb: the skip is reported")
	_expect_equal(str(advanced.get("skipped_receipt", "")), old_key,
		"att-amb: the skip names the old receipt")
	_expect_equal(str(advanced.get("receipt", "")), new_key,
		"att-amb: the grant names the new receipt")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-amb: only the new two land")
	_expect_false((Vault.continue_coin_grants as Dictionary).has(
		old_key),
		"att-amb: the old key never lands")
	_expect_true(str(host.get("_attendance_receipt_pending")).contains(
		"+2"), "att-amb: the receipt names the new two")
	sender.queue_ok(_att_row_body(_att_rfc(ATT_NOW), install,
		_att_rfc(ATT_NOW + 3600)))
	var again: Dictionary = await host.request_attendance()
	_expect_equal(str(again.get("status", "")), "already-claimed",
		"att-amb: the next visit settles the new claim")
	_expect_false(bool(again.get("backfill_skipped", true)),
		"att-amb: the covered stamp stays silent")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-amb: the settle adds nothing more")
	await _free_parts(parts)


## Ten owners claim on one install, the first owner's mark and receipt
## prune, and that owner returns after twelve hours: the forgotten old
## receipt is refused without repayment while the eligible new claim
## commits and pays. Purchased keys stay intact throughout.
func _test_attendance_pruned_return_advances() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var install: String = Vault.ensure_install_id()
	_expect_true(bool(Vault.grant_continue_coins(5, "store-order-9")),
		"att-prune: the purchased key lands")
	var first: int = ATT_NOW - 46800
	var old_key: String = "attendance:%s:%d:%s" % [CANON_C, first,
		install]
	var new_key: String = "attendance:%s:%d:%s" % [CANON_C, ATT_NOW,
		install]
	sender.queue_ok(_att_missing_body(_att_rfc(first)))
	sender.queue_ok(_att_commit_body(_att_rfc(first)))
	var opened: Dictionary = await host.request_attendance()
	_expect_equal(str(opened.get("status", "")), "granted",
		"att-prune: the first claim lands")
	# Nine further owners grant through the real vault path; the first
	# owner's mark and key prune past the bounds.
	for index in 9:
		var owner: String = "MB-prune-%d" % index
		var step: Dictionary = Vault.grant_attendance_coins(owner,
			first + 60 * (index + 1), install, true)
		_expect_true(bool(step.get("granted", false)),
			"att-prune: owner %d grants" % index)
	_expect_false((Vault.attendance_marks as Dictionary).has(CANON_C),
		"att-prune: the first mark prunes")
	_expect_false((Vault.continue_coin_grants as Dictionary).has(
		old_key),
		"att-prune: the first key prunes")
	Vault.load_vault()
	var before: int = Vault.continue_coins
	sender.queue_ok(_att_row_body(_att_rfc(first), install))
	sender.queue_ok(_att_commit_body(_att_rfc(ATT_NOW)))
	var returned: Dictionary = await host.request_attendance()
	_expect_equal(str(returned.get("status", "")), "granted",
		"att-prune: the return advances")
	_expect_false(bool(returned.get("backfilled", true)),
		"att-prune: the forgotten receipt is never repaid")
	_expect_true(bool(returned.get("backfill_skipped", false)),
		"att-prune: the skip is reported")
	_expect_equal(str(returned.get("skipped_receipt", "")), old_key,
		"att-prune: the skip names the old receipt")
	_expect_equal(Vault.continue_coins, before + 2,
		"att-prune: exactly the new two land")
	_expect_equal(int((Vault.continue_coin_grants as Dictionary).get(
		new_key, 0)), 2,
		"att-prune: the new key lands with its coins")
	_expect_equal(int((Vault.continue_coin_grants as Dictionary).get(
		"store-order-9", 0)), 5,
		"att-prune: the purchase stays intact")
	await _free_parts(parts)


## Best completion reaches HUD standing again: after a submit, the Arena
## rank chip shows the refreshed standing without another rank pull.
func _test_submit_best_pushes_hud_rank() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_ok("{\"writeResults\": [{}, {}]}")
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var claimed: Dictionary = await host.claim_adventurer_name("Luna")
	_expect_equal(str(claimed.get("status", "")), "ok",
		"submit-hud: the claim succeeds")
	sender.queue_ok(_own_row_body(CANON_C, 7000))
	sender.queue_ok(_rank_body(1))
	var view: Dictionary = await host.request_rank()
	_expect_equal(int(view.get("rank", 0)), 2,
		"submit-hud: the standing refreshes")
	var hud: Control = HUD_SCENE.instantiate() as Control
	add_child(hud)
	await _frames(2)
	var rank: Label = hud.get_node("RightPanel/Row/Rank") as Label
	# A late rank push can light the chip before the submit runs; clear
	# it and prove a quiet window first, so only the submit can relight.
	hud.clear_cloud_rank()
	await _frames(5)
	_expect_false(rank.visible, "submit-hud: the cleared chip stays dark")
	_write_checkpoint({"cycle": 2, "journey_id": "submit-hud-j-1"})
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_ok("{\"writeResults\": [{}]}")
	await host._submit_best()
	_expect_true(rank.visible and rank.text.begins_with("#2 · "),
		"submit-hud: the submit pushes the standing to the chip")
	var commit: Dictionary = _commit_with(sender, "mb_hall_v1")
	var live: Node = host.get("_coordinator") as Node
	var expected: Dictionary = live._derive_hall_row(
		Journey.read_checkpoint())
	var fields: Dictionary = ((commit.get("writes", []) as Array)[0]
		as Dictionary).get("update", {}).get("fields", {})
	_expect_equal(str(fields.get("display", {}).get("stringValue", "")),
		"Luna", "submit-hud: the write carries the verified handle")
	_expect_equal(str(fields.get("hero", {}).get("stringValue", "")),
		str(expected.get("hero", "")),
		"submit-hud: the write carries the saved hero")
	_expect_equal(int(fields.get("score", {}).get("integerValue", "0")),
		int(expected.get("score", 0)),
		"submit-hud: the write carries the saved score")
	_expect_equal(int(fields.get("cycles", {}).get("integerValue", "0")),
		int(expected.get("cycles", 0)),
		"submit-hud: the write carries the saved cycles")
	hud.queue_free()
	_clear_name_cache()
	await _free_parts(parts)


## Verified handles travel the production board path into the real panel:
## maximum-length Korean and Japanese handles read on the headline, the
## stable MB ID keeps its own line, and unnamed rows keep the honest
## rank-and-score fallback.
func _test_hall_named_rows_reach_panel() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var sender: RefCounted = parts["sender"]
	var korean12: String = "달빛기사단달빛기사단달빛"
	var japanese12: String = "ルミールミールミールミー"
	_expect_equal(korean12.length(), 12, "panel: the Korean handle is max")
	_expect_equal(japanese12.length(), 12,
		"panel: the Japanese handle is max")
	sender.reset()
	sender.queue_ok(_board_body([
		[OTHER_ID, Vault.HEROES[0], 9000, korean12],
		[CANON_D, "warden", 8000, japanese12],
		[CANON_C, Vault.HEROES[0], 7000],
	]))
	var view: Dictionary = await host.request_hall()
	var rows: Array = view.get("rows", [])
	_expect_equal(rows.size(), 3, "panel: three board rows mapped")
	_expect_equal(str((rows[0] as Dictionary).get("display", "")), korean12,
		"panel: the mapper keeps the Korean handle")
	_expect_equal(str((rows[2] as Dictionary).get("display", "")), "",
		"panel: the unnamed row maps no handle")
	var panel: GateHallPanel = GateHallPanel.new()
	add_child(panel)
	await _frames(1)
	panel.show_rows(rows)
	_expect_equal(panel.row_count(), 3, "panel: three real rows render")
	var first: Label = panel.get_node(
		"Card/Stack/Rows/RowsBox/HallRow0/Line/Middle/Headline") as Label
	_expect_equal(first.text, "#1 · 9000 · " + korean12,
		"panel: the Korean handle reads on the headline")
	var first_id: Label = panel.get_node(
		"Card/Stack/Rows/RowsBox/HallRow0/Line/Middle/IdLine") as Label
	_expect_equal(first_id.text, OTHER_ID,
		"panel: the stable ID keeps its own line")
	var second: Label = panel.get_node(
		"Card/Stack/Rows/RowsBox/HallRow1/Line/Middle/Headline") as Label
	_expect_equal(second.text, "#2 · 8000 · " + japanese12,
		"panel: the Japanese handle reads on the headline")
	var third: Label = panel.get_node(
		"Card/Stack/Rows/RowsBox/HallRow2/Line/Middle/Headline") as Label
	_expect_equal(third.text, "#3 · 7000",
		"panel: the unnamed row keeps its honest fallback")
	var row_box: Control = panel.get_node(
		"Card/Stack/Rows/RowsBox/HallRow0") as Control
	_expect_equal(row_box.custom_minimum_size.y,
		GateHallPanel.ROW_MIN_HEIGHT,
		"panel: the named row keeps the row height")
	panel.queue_free()
	await _free_parts(parts)


func _test_adoption_conflict_preserves() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _settle_call(host, "account_state", CANON_C)
	var before: String = FileAccess.get_file_as_string(ID_PATH)
	await _free_parts(parts)
	# Same UID now claims a different canonical id elsewhere: conflict,
	# never a silent overwrite.
	var second: Dictionary = _make_parts()
	var host_b: Node = second["host"]
	var fake_b: Node = second["fake"]
	var sender_b: RefCounted = second["sender"]
	host_b.startup()
	sender_b.queue_ok(_profile_body(UID_A, CANON_D))
	fake_b.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host_b.begin_guest()
	await _frames(30)
	var codes: Array = []
	for error in _fired["error"]:
		codes.append(str((error as Dictionary).get("code", "")))
	_expect_true(codes.has("canonical_binding_differs"),
		"adopt-conflict: explicit error raised")
	_expect_equal(str((host_b.account_state() as Dictionary).get(
		"public_id", "")), CANON_C, "adopt-conflict: local id kept")
	_expect_equal(FileAccess.get_file_as_string(ID_PATH), before,
		"adopt-conflict: old bytes preserved")
	await _free_parts(second)


func _test_bindings_have_no_secrets() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	fake.token_receipt = {"status": "ok", "id_token": SECRET_TOKEN,
		"token_expires_at": 4102444800000}
	host.begin_guest()
	await _settle_call(host, "account_state", CANON_C)
	var bindings: String = FileAccess.get_file_as_string(BIND_PATH)
	_expect_true(not bindings.is_empty(), "secrets: bindings file exists")
	for needle in [UID_A, SECRET_TOKEN, "fake-id-token", "@", "vault",
			"purchase", "uid-prod"]:
		_expect_true(not bindings.contains(needle),
			"secrets: bindings hold no " + needle)
	_expect_true(bindings.contains(CANON_C),
		"secrets: bindings hold the public id")
	var hashed: String = ACCOUNT_SCRIPT.uid_binding_hash(UID_A)
	_expect_true(bindings.contains(hashed),
		"secrets: uid stored hashed only")
	var identity: String = FileAccess.get_file_as_string(ID_PATH)
	_expect_true(not identity.contains(UID_A)
		and not identity.contains(SECRET_TOKEN),
		"secrets: identity file holds no uid or token")
	await _free_parts(parts)


func _test_offline_guest_labeled_local() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	fake.guest_receipt = {"status": "error", "code": "network_error",
		"retryable": true}
	var state: Dictionary = host.startup()
	_expect_equal(str(state.get("source", "")), "local",
		"offline: guest labeled local")
	var entered: Dictionary = host.begin_guest()
	_expect_true(bool(entered.get("ready", false)),
		"offline: guest playable without registration")
	_expect_true(str((host.account_state() as Dictionary).get(
		"cloud_uid", "")).is_empty(),
		"offline: never presented as a cloud account")
	var identity: Dictionary = host.identity_for_entry()
	_expect_equal(str(identity.get("source", "")), "local",
		"offline: entry card says local")
	await _free_parts(parts)


func _test_capability_disablement() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts(FAKE_ADAPTER_SCRIPT)
	var host: Node = parts["host"]
	host.startup()
	_expect_true((host.providers_for_entry() as Array).is_empty(),
		"caps: unsupported bridge lists no providers")
	var fake: Node = parts["fake"]
	_expect_false((fake.calls as Array).has("sign_in_provider"),
		"caps: no provider call without readiness")
	host.begin_guest()
	_expect_false((fake.calls as Array).has("sign_in_guest"),
		"caps: desktop guest plays with no registration attempt")
	_expect_true((_fired["error"] as Array).is_empty(),
		"caps: no error for the local guest")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"source", "")), "local", "caps: guest stays local")
	await _free_parts(parts)


func _test_capable_providers_listed() -> void:
	_wipe_all()
	var capable: Node = CapableFake.new()
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(capable, ID_PATH, BIND_PATH)
	var coord: Node = COORD_SCRIPT.new() as Node
	var host: Node = HOST_SCRIPT.new() as Node
	add_child(host)
	host.inject_services({"account": account, "adapter": capable,
		"sender": sender, "coordinator": coord, "vault": Vault})
	_watch(host)
	host.startup()
	var rows: Array = host.providers_for_entry()
	_expect_equal(rows.size(), 2, "caps: ready bridge lists providers")
	_expect_true(bool((rows[0] as Dictionary).get("ready", false)),
		"caps: ready provider enabled")
	_expect_false(bool((rows[1] as Dictionary).get("ready", true)),
		"caps: unready provider disabled honestly")
	_expect_true(not str(host.provider_label("play_games")).is_empty()
		and host.provider_label("mystery") == "mystery",
		"caps: known labels mapped, unknown shown raw")
	await _free_parts({"host": host})


func _test_draining_cancel_keeps_lock() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	fake.guest_receipt = {"status": "pending"}
	fake.cancel_status = "draining"
	host.begin_guest()
	_expect_true(bool((host.account_state() as Dictionary).get(
		"ready", false)), "drain: play stays ready while pending")
	var cancelled: Dictionary = host.cancel_login()
	_expect_equal(str(cancelled.get("status", "")), "draining",
		"drain: cancel reports draining")
	_expect_true(bool((host.account_state() as Dictionary).get(
		"draining", false)), "drain: lock visible in state")
	var issued: Array = (fake.get("_issued") as Dictionary).keys()
	fake.complete_session(str(issued[0]), {"kind": "cloud",
		"uid": UID_A, "provider": "anonymous"})
	await _frames(10)
	_expect_equal((host.account_state() as Dictionary).get(
		"cloud_uid", ""), UID_A, "drain: terminal outcome still lands")
	_expect_false(bool((host.account_state() as Dictionary).get(
		"draining", true)), "drain: lock settles on terminal")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), guest, "drain: guest id untouched by the lock")
	await _free_parts(parts)


func _test_provider_conflict_offers_switch() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	fake.link_receipt = {"status": "conflict",
		"code": "already_linked_elsewhere", "provider": "play_games"}
	host.link_provider("play_games")
	await _frames(5)
	_expect_equal((_fired["error"] as Array).size(), 1,
		"switch: one conflict error")
	var error: Dictionary = (_fired["error"] as Array)[0]
	_expect_true(bool(error.get("can_switch", false)),
		"switch: explicit switch offered")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), guest,
		"switch: guest preserved, never auto-merged")
	_expect_true(str((host.account_state() as Dictionary).get(
		"cloud_uid", "")).is_empty(), "switch: still a local guest")
	await _free_parts(parts)


func _test_token_retirement_on_switch() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _settle_call(host, "account_state", CANON_C)
	_expect_equal(host.supply_token(), "fake-id-token",
		"token: live token supplied")
	Vault.continue_coins = 1
	Vault.save_vault()
	_seal_and_journal(CANON_C, "token-j-1", 2, 3)
	_expect_equal(Vault.continue_coins, 0,
		"token: the debit journals before sign-out")
	var fetches: int = (fake.calls as Array).count("get_id_token")
	host.sign_out()
	_expect_true(host.supply_token().is_empty(),
		"token: retired on sign-out")
	_expect_equal(Vault.recover_paid_continue(), "deferred",
		"token: sign-out defers the old receipt instead of dropping it")
	_expect_equal(_txn_owner_cid(CANON_C), 3,
		"token: the old receipt survives the rotation")
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_B, "provider": "anonymous"}}
	sender.reset()
	sender.queue_ok(_profile_body(UID_B, CANON_D))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	host.begin_guest()
	await _settle_call(host, "account_state", CANON_D)
	_expect_true((fake.calls as Array).count("get_id_token") > fetches,
		"token: refreshed for the new account")
	_expect_equal(host.supply_token(), "fake-id-token",
		"token: new account serves its own token")
	_expect_equal(Vault.recover_paid_continue(), "deferred",
		"token: the refresh keeps deferring the old receipt")
	_expect_equal(_txn_owner_cid(CANON_C), 3,
		"token: the refresh leaves the old receipt alone")
	_expect_equal(_txn_owner_cid(CANON_D), 0,
		"token: the new scope journals nothing of its own")
	_expect_true(bool(Vault.clear_continue_txn_for_owner(CANON_C)),
		"token: cleanup drops the retained receipt")
	await _free_parts(parts)


func _test_save_choice_preserves_rejected() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_write_checkpoint({"cycle": 3, "journey_id": "local-j-1"})
	var local_before: String = FileAccess.get_file_as_string(
		Journey.account_main_path(guest))
	sender.queue_ok(_profile_body(UID_A, guest))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _await_ready(host)
	await _frames(20)
	sender.reset()
	var remote_payload: String = JSON.stringify(
		_valid_checkpoint("remote-j-9", 4, 0, {"cycle": 5}))
	sender.queue_ok(_remote_body(UID_A, 7, remote_payload,
		"2026-10-02T00:00:00Z"))
	var restored: Dictionary = await host.restore_cloud()
	_expect_equal(str(restored.get("code", "")), "restore-differs",
		"choice: differing remote conflicts")
	_expect_equal((_fired["conflict"] as Array).size(), 1,
		"choice: conflict surfaced with both options")
	# Keep local: the actually overwritten remote bytes are preserved.
	# The resolution re-reads the remote twice (preserve, then rebase).
	sender.queue_ok(_remote_body(UID_A, 7, remote_payload,
		"2026-10-02T00:00:00Z"))
	sender.queue_ok(_remote_body(UID_A, 7, remote_payload,
		"2026-10-02T00:00:00Z"))
	sender.queue_ok("{}")
	var resolved: Dictionary = await host.resolve_save_choice("local")
	_expect_equal(str(resolved.get("status", "")), "ok",
		"choice: local resolves")
	var rejected: String = FileAccess.get_file_as_string(
		Journey.account_rejected_path(guest, "remote"))
	_expect_true(rejected.contains("remote-j-9"),
		"choice: rejected remote preserved byte for byte")
	_expect_equal(FileAccess.get_file_as_string(
		Journey.account_main_path(guest)), local_before,
		"choice: local bytes untouched")
	await _free_parts(parts)


func _test_fresh_guest_on_signout_preserves_slot() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var first_id: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	sender.queue_ok(_profile_body(UID_A, first_id))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _await_ready(host)
	_write_checkpoint({"cycle": 2, "journey_id": "slot-j-1"})
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(first_id)), "slot: journey saved")
	host.sign_out()
	var second_id: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_expect_true(not second_id.is_empty() and second_id != first_id,
		"slot: sign-out mints a fresh guest id")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(first_id)),
		"slot: old account slot preserved")
	_expect_equal((parts["account"] as Node).public_id_for_uid(UID_A),
		first_id, "slot: old uid binding kept")
	await _free_parts(parts)


func _test_new_save_confirmation() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	_write_checkpoint({"cycle": 3, "journey_id": "confirm-j-1"})
	var refused: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(refused.get("code", "")), "needs_confirmation",
		"confirm: fresh over save needs confirmation")
	_expect_false(Journey.armed, "confirm: nothing armed before confirm")
	var planned: Dictionary = host.plan_entry(true, true)
	_expect_equal(str(planned.get("status", "")), "ok",
		"confirm: confirmed fresh plans")
	_expect_true(Journey.armed, "confirm: journey armed")
	_expect_equal(Journey.pending, Journey.Pending.FRESH,
		"confirm: fresh pending")
	host.cancel_entry_plan()
	_expect_false(Journey.armed, "confirm: cancel disarms")
	await _free_parts(parts)


func _test_resume_needs_save() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	var refused: Dictionary = host.plan_entry(false, true)
	_expect_equal(str(refused.get("code", "")), "no_save",
		"resume: refused without a checkpoint")
	_write_checkpoint({"cycle": 4, "journey_id": "resume-j-1"})
	var planned: Dictionary = host.plan_entry(false, true)
	_expect_equal(str(planned.get("status", "")), "ok",
		"resume: plans with a checkpoint")
	_expect_equal(Journey.pending, Journey.Pending.RESUME,
		"resume: resume pending")
	_expect_true(bool((host.saved_gate_summary() as Dictionary).get(
		"has_save", false)), "resume: summary reports the save")
	await _free_parts(parts)


## A sealed defeat offers no resume: the saved-gate summary reports no save,
## planning a resume is refused like an empty slot, and a fresh expedition
## needs no erase confirmation because nothing resumable waits.
func _test_defeat_offers_no_resume() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	_write_checkpoint({"cycle": 4, "journey_id": "defeat-j-1",
		"ended": true})
	_expect_false(bool((host.saved_gate_summary() as Dictionary).get(
		"has_save", true)), "defeat: summary reports no save")
	var refused: Dictionary = host.plan_entry(false, true)
	_expect_equal(str(refused.get("code", "")), "no_save",
		"defeat: resume refused for a sealed run")
	_expect_false(Journey.armed, "defeat: nothing armed by the refusal")
	var fresh: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(fresh.get("status", "")), "ok",
		"defeat: fresh over a sealed run needs no confirmation")
	_expect_equal(Journey.pending, Journey.Pending.FRESH,
		"defeat: fresh pending")
	await _free_parts(parts)


## A paid revive stranded behind failing writes is not a save, but a fresh
## expedition over it still asks first — the paid coin is only ever
## abandoned explicitly. Once the writes heal, the same entry recovers the
## paid seal and resumes it without another charge.
func _test_stuck_revive_needs_fresh_confirmation() -> void:
	_wipe_all()
	_release_dir(ProjectSettings.globalize_path(Journey.path + ".tmp"))
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	_write_checkpoint({"cycle": 4, "journey_id": "stuck-j-1",
		"checkpoint_id": 2, "ended": true})
	Vault.continue_coins = 2
	Vault.continue_txn = {}
	var seal: Dictionary = _valid_checkpoint("stuck-j-1", 3, 9)
	_expect_true(Vault.begin_continue_txn("stuck-j-1", 3,
		JSON.stringify(seal)), "stuck: the debit journals its seal")
	_occupy_dir(ProjectSettings.globalize_path(Journey.path + ".tmp"))
	var summary: Dictionary = host.saved_gate_summary()
	_expect_false(bool(summary.get("has_save", true)),
		"stuck: summary reports no save")
	_expect_true(bool(summary.get("revive_stuck", false)),
		"stuck: summary names the stuck revive")
	var refused: Dictionary = host.plan_entry(false, true)
	_expect_equal(str(refused.get("code", "")), "no_save",
		"stuck: resume refused while the seal cannot land")
	var needs_confirm: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(needs_confirm.get("code", "")), "needs_confirmation",
		"stuck: fresh over a stuck revive asks first")
	_release_dir(ProjectSettings.globalize_path(Journey.path + ".tmp"))
	var planned: Dictionary = host.plan_entry(false, true)
	_expect_equal(str(planned.get("status", "")), "ok",
		"stuck: resume plans after recovery")
	_expect_true(Journey.has_valid_checkpoint(),
		"stuck: the recovered seal is resumable")
	_expect_equal(Vault.continue_coins, 1,
		"stuck: recovery charges nothing more")
	_expect_true((Vault.continue_txn as Dictionary).is_empty(),
		"stuck: recovery clears the journal")
	await _free_parts(parts)


## Occupy a path as a directory so the next write there fails. Always paired
## with `_release_dir`, and released again at the next test start.
func _occupy_dir(absolute: String) -> void:
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	DirAccess.make_dir_absolute(absolute)


func _release_dir(absolute: String) -> void:
	if DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)


func _test_lodge_local_guest_skips() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	_expect_false(host.needs_lodge_lesson(),
		"lodge: a local guest settles no claim")
	var planned: Dictionary = host.plan_entry(true, true)
	_expect_equal(str(planned.get("status", "")), "ok",
		"lodge: a local guest still enters the arena")
	_expect_true(str(planned.get("arena", "")).ends_with("arena.tscn"),
		"lodge: the local plan names the arena")
	host.cancel_entry_plan()
	await _free_parts(parts)


func _test_lodge_unnamed_cloud_blocked() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	_expect_true(host.needs_lodge_lesson(),
		"lodge: an unnamed cloud account needs the lesson")
	var refused: Dictionary = host.plan_entry(true, true)
	_expect_equal(str(refused.get("code", "")), "needs_lodge",
		"lodge: the arena refuses before the lesson")
	_expect_false(Journey.armed, "lodge: the refusal arms nothing")
	var visit: Dictionary = host.plan_lodge_entry()
	_expect_equal(str(visit.get("status", "")), "ok",
		"lodge: the visit plans")
	_expect_true(str(visit.get("lodge", "")).ends_with("gate_lodge.tscn"),
		"lodge: the visit names the lodge scene")
	_expect_true(bool(visit.get("needs_name", false)),
		"lodge: the visit reports the missing name")
	_expect_false(Journey.armed, "lodge: the visit arms no journey")
	_expect_equal(Journey.pending, Journey.Pending.NONE,
		"lodge: the visit pends nothing")
	var again: Dictionary = host.plan_lodge_entry()
	_expect_equal(str(again.get("code", "")), "entry_in_flight",
		"lodge: a second visit refuses while one holds")
	host.cancel_entry_plan()
	_expect_false(Journey.armed, "lodge: the cancel arms nothing")
	await _free_parts(parts)


func _test_lodge_named_unfinished_recovers() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	_expect_true(Vault.cache_verified_name(CANON_C, "Luna", "luna", false),
		"lodge: the unfinished handle caches")
	_expect_true(host.needs_lodge_lesson(),
		"lodge: a named unfinished account still needs the lesson")
	_expect_equal(host.verified_display_name(), "Luna",
		"lodge: the claimed handle recovers synchronously")
	var visit: Dictionary = host.plan_lodge_entry()
	_expect_equal(str(visit.get("status", "")), "ok",
		"lodge: the unfinished visit plans")
	_expect_false(bool(visit.get("needs_name", true)),
		"lodge: the visit reports the name settled")
	host.cancel_entry_plan()
	_clear_name_cache()
	await _free_parts(parts)


func _test_lodge_completed_skips() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	_expect_true(Vault.cache_verified_name(CANON_C, "Luna", "luna", true),
		"lodge: the completed handle caches")
	_expect_false(host.needs_lodge_lesson(),
		"lodge: a completed account skips the lesson")
	var visit: Dictionary = host.plan_lodge_entry()
	_expect_equal(str(visit.get("code", "")), "lodge_complete",
		"lodge: a completed account cannot plan a visit")
	var planned: Dictionary = host.plan_entry(true, true)
	_expect_equal(str(planned.get("status", "")), "ok",
		"lodge: a completed account enters the arena directly")
	host.cancel_entry_plan()
	_clear_name_cache()
	await _free_parts(parts)


func _test_lodge_exit_guards() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	var naked: Dictionary = host.plan_lodge_exit(true, true)
	_expect_equal(str(naked.get("code", "")), "no_lodge_plan",
		"lodge: no exit without a live visit")
	var visit: Dictionary = host.plan_lodge_entry()
	_expect_equal(str(visit.get("status", "")), "ok",
		"lodge: the guarded visit plans")
	var early: Dictionary = host.plan_lodge_exit(true, true)
	_expect_equal(str(early.get("code", "")), "needs_lodge",
		"lodge: an exit before the seal still refuses")
	_expect_false(Journey.armed, "lodge: the early exit arms nothing")
	var held: Dictionary = host.plan_lodge_entry()
	_expect_equal(str(held.get("code", "")), "entry_in_flight",
		"lodge: the refused exit keeps the visit hold")
	host.cancel_entry_plan()
	await _free_parts(parts)


func _test_lodge_exit_ok_and_confirm() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	_expect_true(Vault.cache_verified_name(CANON_C, "Luna", "luna", true),
		"lodge: the departing handle caches")
	_write_checkpoint({"cycle": 3, "journey_id": "lodge-j-1"})
	var visit: Dictionary = host.plan_lodge_entry()
	_expect_equal(str(visit.get("code", "")), "lodge_complete",
		"lodge: a completed account cannot plan a visit")
	_clear_name_cache()
	_expect_true(Vault.cache_verified_name(CANON_C, "Luna", "luna", false),
		"lodge: the exit test reopens the lesson bit")
	visit = host.plan_lodge_entry()
	_expect_equal(str(visit.get("status", "")), "ok",
		"lodge: the exit visit plans")
	_expect_true(Vault.cache_verified_name(CANON_C, "Luna", "luna", true),
		"lodge: the seal lands before departure")
	var unconfirmed: Dictionary = host.plan_lodge_exit(true, false)
	_expect_equal(str(unconfirmed.get("code", "")), "needs_confirmation",
		"lodge: fresh over a save still asks first")
	var held: Dictionary = host.plan_lodge_entry()
	_expect_equal(str(held.get("code", "")), "entry_in_flight",
		"lodge: the refused exit keeps the visit hold")
	var resume: Dictionary = host.plan_lodge_exit(false, true)
	_expect_equal(str(resume.get("status", "")), "ok",
		"lodge: the sealed resume departs")
	_expect_true(str(resume.get("arena", "")).ends_with("arena.tscn"),
		"lodge: the departure names the arena")
	_expect_true(host.confirm_entry_account(CANON_C),
		"lodge: the departure confirms the same account")
	_expect_true(Journey.armed, "lodge: the departure arms the journey")
	_expect_equal(Journey.pending, Journey.Pending.RESUME,
		"lodge: the resume pends")
	host.cancel_entry_plan()
	_clear_name_cache()
	await _free_parts(parts)


func _test_lodge_exit_defeat_never_resumes() -> void:
	var parts: Dictionary = await _adopt_guest_to_canonical()
	var host: Node = parts["host"]
	_expect_true(Vault.cache_verified_name(CANON_C, "Luna", "luna", false),
		"lodge: the defeated visit caches its handle")
	_write_checkpoint({"cycle": 4, "journey_id": "lodge-defeat-j-1",
		"ended": true})
	var visit: Dictionary = host.plan_lodge_entry()
	_expect_equal(str(visit.get("status", "")), "ok",
		"lodge: the defeated visit plans")
	_expect_true(Vault.cache_verified_name(CANON_C, "Luna", "luna", true),
		"lodge: the seal lands after the defeat")
	var resume: Dictionary = host.plan_lodge_exit(false, true)
	_expect_equal(str(resume.get("code", "")), "no_save",
		"lodge: the sealed run never resumes from the lodge")
	var fresh: Dictionary = host.plan_lodge_exit(true, false)
	_expect_equal(str(fresh.get("status", "")), "ok",
		"lodge: fresh over a sealed run needs no confirmation")
	host.cancel_entry_plan()
	_clear_name_cache()
	await _free_parts(parts)


func _test_double_start_refused() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	_write_checkpoint({"cycle": 1, "journey_id": "double-j-1"})
	_expect_equal(str((host.plan_entry(false, true) as Dictionary).get(
		"status", "")), "ok", "double: first plan ok")
	_expect_equal(str((host.plan_entry(false, true) as Dictionary).get(
		"code", "")), "entry_in_flight", "double: second plan refused")
	await _free_parts(parts)


func _test_wrong_account_entry_refused() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	var first_id: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_write_checkpoint({"cycle": 1, "journey_id": "wrong-j-1"})
	host.plan_entry(false, true)
	_expect_true(host.confirm_entry_account(first_id),
		"wrong-account: same account confirms")
	host.sign_out()
	_expect_false(host.confirm_entry_account(first_id),
		"wrong-account: moved account refuses the stale plan")
	# The fresh guest owns an empty slot: resume is honestly refused,
	# while a confirmed fresh start plans cleanly.
	_expect_equal(str((host.plan_entry(false, true) as Dictionary).get(
		"code", "")), "no_save",
		"wrong-account: resume refused in the fresh empty slot")
	_expect_equal(str((host.plan_entry(true, true) as Dictionary).get(
		"status", "")), "ok",
		"wrong-account: a clean plan works after the move")
	await _free_parts(parts)


func _test_continue_reward_safety() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_write_checkpoint({"cycle": 3, "journey_id": "reward-j-1",
		"shards_awarded": 15, "settled_score": 2400})
	var before: String = FileAccess.get_file_as_string(
		Journey.account_main_path(guest))
	var planned: Dictionary = host.plan_entry(false, true)
	_expect_equal(str(planned.get("status", "")), "ok",
		"reward: resume plans")
	_expect_equal(FileAccess.get_file_as_string(
		Journey.account_main_path(guest)), before,
		"reward: planning seals nothing and mints nothing")
	var summary: Dictionary = host.saved_gate_summary()
	_expect_equal(int(summary.get("cycle", 0)), 3,
		"reward: growth checkpoint intact")
	await _free_parts(parts)


func _make_entry(host: Node) -> ProductionEntry:
	var entry: ProductionEntry = ENTRY_SCENE.instantiate() as ProductionEntry
	entry.set_host_override(host)
	add_child(entry)
	return entry


## Tap the production title. The external start opens the login
## selection (or the restored identity card) over that same title.
func _tap(entry: ProductionEntry) -> void:
	var title: Variant = entry.get_node("Title")
	title.request_start()
	await _frames(2)


func _test_first_entry_shows_choice() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_expect_true(ACCOUNT_SCRIPT.is_valid_public_id(minted),
		"choice: durable id minted before play")
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	_expect_false((gate.get_node("Content/StatusCard") as Control).visible,
		"choice: first paint is the title, no auth card")
	await _tap(entry)
	var logged_out: Control = gate.get_node(
		"Content/StatusCard/LoggedOut") as Control
	_expect_true(logged_out.visible,
		"choice: tap shows the choice, not the card")
	var providers: Control = gate.get_node(
		"Content/StatusCard/LoggedOut/Providers") as Control
	# Brief 107: the ordinary pair always shows (host entries where the
	# bridge lists them, disabled placeholders where it omits them),
	# with actually supported extras after. This bridge lists apple
	# (unready) and Play Games (ready): google renders placeholder.
	_expect_equal(providers.get_child_count(), 3,
		"choice: ordinary pair plus supported extra listed")
	_expect_true((providers.get_child(0) as Button).name \
		== "ProviderGoogle", "choice: google door first")
	_expect_true((providers.get_child(0) as Button).disabled,
		"choice: unlisted google honestly disabled")
	_expect_true((providers.get_child(1) as Button).disabled,
		"choice: unready apple stays disabled")
	_expect_true(not (providers.get_child(2) as Button).disabled,
		"choice: supported extra stays enabled")
	_expect_true((gate.get_node(
		"Content/StatusCard/LoggedOut/Guest") as Button).visible,
		"choice: guest stays available")
	# Choosing the guest enters with the same durable id.
	gate.guest_requested.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "choice: guest choice shows the identity card")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted, "choice: same id after choosing")
	entry.queue_free()
	await _free_parts(parts)


func _test_relaunch_without_save_returns_to_choice() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	(entry.get_node("Gate") as GateEntry).guest_requested.emit()
	await _frames(2)
	entry.queue_free()
	await _free_parts(parts)
	var relaunched: Dictionary = _make_parts()
	var host_b: Node = relaunched["host"]
	host_b.startup()
	_expect_equal(str((host_b.account_state() as Dictionary).get(
		"public_id", "")), minted,
		"relaunch: no fresh id on every boot")
	var entry_b: ProductionEntry = _make_entry(host_b)
	await _frames(3)
	var gate_b: GateEntry = entry_b.get_node("Gate") as GateEntry
	_expect_false((gate_b.get_node("Content/StatusCard") as Control).visible,
		"relaunch: first paint is the title, no auth card")
	await _tap(entry_b)
	_expect_true((gate_b.get_node("Content/StatusCard/LoggedOut"
		) as Control).visible,
		"relaunch: choiceless guest returns to selection")
	entry_b.queue_free()
	await _free_parts(relaunched)


func _test_returning_guest_goes_direct() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	_write_checkpoint({"cycle": 2, "journey_id": "direct-j-1"})
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	_expect_false((gate.get_node("Content/StatusCard") as Control).visible,
		"direct: first paint is the title, no auth card")
	await _tap(entry)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "direct: saved guest skips selection")
	_expect_false((gate.get_node("Content/StatusCard/LoggedOut"
		) as Control).visible, "direct: choice stays hidden")
	entry.queue_free()
	await _free_parts(parts)


func _test_restored_session_goes_direct() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	sender.queue_ok(_profile_body(UID_A, guest))
	# Authoritative empty cloud: the initial check resolves cleanly and
	# the restored account skips the selection with no save.
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _await_ready(host)
	await _settle_restore(host)
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	_expect_false((gate.get_node("Content/StatusCard") as Control).visible,
		"direct: first paint is the title, no auth card")
	await _tap(entry)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "direct: restored account skips selection")
	entry.queue_free()
	await _free_parts(parts)


func _test_guest_pending_shows_busy() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	fake.guest_receipt = {"status": "pending"}
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	gate.guest_requested.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "guest-busy: pending registration shows busy")
	_expect_true(host.is_login_pending(), "guest-busy: host reports pend")
	fake.complete_session(_pending_request_id(fake), {"kind": "cloud",
		"uid": UID_A, "provider": "anonymous"})
	await _frames(10)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "guest-busy: terminal registration shows the card")
	entry.queue_free()
	await _free_parts(parts)


func _test_signout_returns_to_selection() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	var first_id: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	await _tap(entry)
	gate.guest_requested.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "signout: guest sees the card first")
	entry._on_account_sign_out()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/LoggedOut"
		) as Control).visible, "signout: fresh guest returns to selection")
	_expect_true(str((host.account_state() as Dictionary).get(
		"public_id", "")) != first_id,
		"signout: fresh id minted for the new guest")
	entry.queue_free()
	await _free_parts(parts)


## Async provider failure through the real entry buttons and the real
## PlayerAccount folding: Google, then Apple. The Error screen must still
## show three frames later and across further benign duplicate changes,
## with the same durable ID, settled pending, and friendly text that
## carries no UID, token, request id, or raw SDK code.
func _test_async_provider_error_persists() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	fake.capabilities = {
		"status": "ok", "supported": true,
		"providers": [
			{"id": "google", "label": "Google", "ready": true},
			{"id": "apple", "label": "Apple", "ready": true},
		],
		"guest": true,
	}
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	for provider_id in ["google", "apple"]:
		fake.provider_receipt = {"status": "pending"}
		(gate.get_node("Content/StatusCard/LoggedOut/Providers/Provider%s"
			% provider_id.capitalize()) as Button).pressed.emit()
		await _frames(2)
		_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
			).visible, "persist-%s: pending shows busy" % provider_id)
		var request_id: String = _last_request_id(fake)
		_expect_false(request_id.is_empty(),
			"persist-%s: native request issued" % provider_id)
		fake.complete_error(request_id, {"status": "error",
			"code": "network_error", "retryable": true})
		await _frames(3)
		_expect_true((gate.get_node("Content/StatusCard/Error"
			) as Control).visible,
			"persist-%s: error still shows three frames later"
			% provider_id)
		_expect_false((gate.get_node("Content/StatusCard/Ready"
			) as Control).visible,
			"persist-%s: no silent identity card" % provider_id)
		_expect_false((gate.get_node("Content/StatusCard/LoggedOut"
			) as Control).visible,
			"persist-%s: no silent return to choices" % provider_id)
		_expect_equal(str((host.account_state() as Dictionary).get(
			"public_id", "")), minted,
			"persist-%s: same durable id" % provider_id)
		_expect_false(host.is_login_pending(),
			"persist-%s: pending settled" % provider_id)
		var detail: String = str((gate.get_node(
			"Content/StatusCard/Error/ErrorDetail") as Label).text)
		_expect_equal(detail, GateEntryStrings.text(
			"gate.auth.error_title"),
			"persist-%s: friendly translated text" % provider_id)
		for needle in ["network_error", request_id, UID_A, UID_B,
				"tok-", "@", "MB-"]:
			_expect_false(detail.contains(needle),
				"persist-%s: screen shows no %s" % [provider_id, needle])
		for _index in 3:
			host.production_changed.emit(host.account_state())
		await _frames(1)
		_expect_true((gate.get_node("Content/StatusCard/Error"
			) as Control).visible,
			"persist-%s: duplicates keep the error" % provider_id)
		_expect_equal(str((host.account_state() as Dictionary).get(
			"public_id", "")), minted,
			"persist-%s: id stable across duplicates" % provider_id)
		(gate.get_node("Content/StatusCard/Error/ErrorRow/ErrorCancel"
			) as Button).pressed.emit()
		await _frames(2)
		_expect_true((gate.get_node("Content/StatusCard/LoggedOut"
			) as Control).visible,
			"persist-%s: cancel returns to choices" % provider_id)
	entry.queue_free()
	await _free_parts(parts)


## Retry retires the old failure and the new outcome replaces it: a second
## pending shows busy, a stale completion of the superseded request is
## ignored, a second error shows again, and a success clears to the card.
func _test_error_retry_replaces_and_succeeds() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	fake.provider_receipt = {"status": "pending"}
	gate.provider_login_requested.emit("play_games")
	await _frames(2)
	var first_id: String = _last_request_id(fake)
	fake.complete_error(first_id, {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "retry: first failure shows the error")
	fake.provider_receipt = {"status": "pending"}
	(gate.get_node("Content/StatusCard/Error/ErrorRow/RetryLogin"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "retry: new attempt shows busy, old retired")
	_expect_true(str(entry.get("_error_hold")).is_empty(),
		"retry: hold cleared by the new intent")
	var second_id: String = _last_request_id(fake)
	_expect_true(not second_id.is_empty() and second_id != first_id,
		"retry: second native request issued")
	# A late failure for the superseded request must not overwrite the
	# live busy state.
	fake.complete_error(first_id, {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "retry: stale failure keeps busy")
	_expect_false((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "retry: stale failure shows no error")
	_expect_true(host.is_login_pending(),
		"retry: live request still pending after the stale one")
	fake.complete_error(second_id, {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "retry: second failure shows again")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted, "retry: same id across failures")
	fake.provider_receipt = {"status": "pending"}
	(gate.get_node("Content/StatusCard/Error/ErrorRow/RetryLogin"
		) as Button).pressed.emit()
	await _frames(2)
	var third_id: String = _last_request_id(fake)
	sender.queue_ok(_profile_body(UID_A, minted))
	# Authoritative empty cloud for the initial check after this success.
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.complete_session(third_id, {"kind": "cloud", "uid": UID_A,
		"provider": "play_games"})
	await _frames(10)
	await _settle_restore(host)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "retry: success clears to the card")
	_expect_false((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "retry: success shows no error")
	_expect_equal((host.account_state() as Dictionary).get(
		"cloud_uid", ""), UID_A, "retry: cloud session live")
	for _index in 2:
		host.production_changed.emit(host.account_state())
	await _frames(1)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "retry: duplicates after success keep the card")
	entry.queue_free()
	await _free_parts(parts)


## Cancel from Busy and from Error, plus explicit sign-out, retire the
## failure: duplicates afterwards must not resurrect it (negative
## control), and sign-out mints a fresh guest without touching Vault.
func _test_error_cancel_and_signout_retire() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	var shards_before: int = Vault.shards
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	# Busy cancel while a provider request is genuinely in flight.
	fake.provider_receipt = {"status": "pending"}
	gate.provider_login_requested.emit("play_games")
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "cancel: pending shows busy first")
	(gate.get_node("Content/StatusCard/Busy/CancelLogin"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/LoggedOut"
		) as Control).visible, "cancel: busy cancel returns to choices")
	# Error cancel after an async failure.
	fake.provider_receipt = {"status": "pending"}
	gate.provider_login_requested.emit("play_games")
	await _frames(2)
	fake.complete_error(_last_request_id(fake), {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "cancel: failure shows the error first")
	(gate.get_node("Content/StatusCard/Error/ErrorRow/ErrorCancel"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/LoggedOut"
		) as Control).visible, "cancel: error cancel returns to choices")
	for _index in 2:
		host.production_changed.emit(host.account_state())
	await _frames(1)
	_expect_true((gate.get_node("Content/StatusCard/LoggedOut"
		) as Control).visible,
		"cancel: duplicates after cancel keep the choices")
	_expect_false((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "cancel: duplicates resurrect no error")
	# Logout retires a live failure with a fresh guest id.
	fake.provider_receipt = {"status": "pending"}
	gate.provider_login_requested.emit("apple")
	await _frames(2)
	fake.complete_error(_last_request_id(fake), {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "cancel: second failure shows before sign-out")
	entry._on_account_sign_out()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/LoggedOut"
		) as Control).visible, "cancel: sign-out returns to choices")
	_expect_true(str(entry.get("_error_hold")).is_empty(),
		"cancel: sign-out retires the hold")
	var fresh: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_expect_true(not fresh.is_empty() and fresh != minted,
		"cancel: sign-out mints a fresh guest id")
	_expect_equal(Vault.shards, shards_before,
		"cancel: vault shards untouched")
	for _index in 2:
		host.production_changed.emit(host.account_state())
	await _frames(1)
	_expect_false((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "cancel: duplicates after sign-out keep no error")
	entry.queue_free()
	await _free_parts(parts)


## The Error screen's guest action enters the durable local guest without
## another native registration: same ID, zero extra guest calls, no other
## slot touched, no purchases cleared. Covers provider failure and an
## async anonymous guest failure alike.
func _test_failure_to_local_guest() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_write_decoy_slot()
	var shards_before: int = Vault.shards
	var settled_before: Array = (
		Vault.settled_journeys as Array).duplicate()
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	fake.provider_receipt = {"status": "pending"}
	gate.provider_login_requested.emit("play_games")
	await _frames(2)
	fake.complete_error(_last_request_id(fake), {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "local-guest: provider failure shows first")
	var guest_calls: int = (fake.calls as Array).count("sign_in_guest")
	(gate.get_node("Content/StatusCard/Error/ErrorRow/ErrorGuest"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "local-guest: escape shows the card")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted, "local-guest: same id, none minted")
	_expect_equal((fake.calls as Array).count("sign_in_guest"),
		guest_calls, "local-guest: zero extra native guest calls")
	_expect_true(str(entry.get("_busy_provider")).is_empty(),
		"local-guest: stale provider intent cleared")
	_expect_true(str((host.account_state() as Dictionary).get(
		"cloud_uid", "")).is_empty(),
		"local-guest: stays a local guest")
	for _index in 2:
		host.production_changed.emit(host.account_state())
	await _frames(1)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "local-guest: duplicates keep the card")
	# An async anonymous guest failure escapes the same way.
	entry._on_account_sign_out()
	await _frames(2)
	var second_id: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	fake.guest_receipt = {"status": "pending"}
	(gate.get_node("Content/StatusCard/LoggedOut/Guest"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "local-guest: anonymous pending shows busy")
	fake.complete_error(_last_request_id(fake), {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "local-guest: anonymous failure shows the error")
	guest_calls = (fake.calls as Array).count("sign_in_guest")
	(gate.get_node("Content/StatusCard/Error/ErrorRow/ErrorGuest"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "local-guest: anonymous escape shows the card")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), second_id,
		"local-guest: anonymous escape keeps the id")
	_expect_equal((fake.calls as Array).count("sign_in_guest"),
		guest_calls, "local-guest: anonymous escape adds no calls")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(OTHER_ID)),
		"local-guest: other account slot untouched")
	_expect_equal(Vault.shards, shards_before,
		"local-guest: vault shards untouched")
	_expect_equal(Vault.settled_journeys, settled_before,
		"local-guest: settled ledgers untouched")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		Journey.account_main_path(OTHER_ID)))
	entry.queue_free()
	await _free_parts(parts)


## A draining mutation cannot be bypassed: retry while draining is
## refused, guest shows the finishing lock, and the terminal outcome
## still lands and settles the lock.
func _test_draining_refusal_preserves_lock() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	fake.provider_receipt = {"status": "pending"}
	fake.cancel_status = "draining"
	gate.provider_login_requested.emit("play_games")
	await _frames(2)
	(gate.get_node("Content/StatusCard/Busy/CancelLogin"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "drain-refuse: cancel keeps the finishing lock")
	_expect_true(bool((host.account_state() as Dictionary).get(
		"draining", false)), "drain-refuse: lock visible in state")
	var refused: Dictionary = host.retry_login("play_games")
	_expect_equal(str(refused.get("status", "")), "draining",
		"drain-refuse: retry refused while draining")
	entry._on_guest()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "drain-refuse: guest cannot bypass the lock")
	_expect_true(host.is_login_pending(),
		"drain-refuse: request still pending")
	_expect_false((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "drain-refuse: no card while draining")
	sender.queue_ok(_profile_body(UID_A, minted))
	# Authoritative empty cloud for the initial check after this terminal.
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.complete_session(_last_request_id(fake), {"kind": "cloud",
		"uid": UID_A, "provider": "play_games"})
	await _frames(10)
	await _settle_restore(host)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "drain-refuse: terminal still lands the card")
	_expect_false(bool((host.account_state() as Dictionary).get(
		"draining", true)), "drain-refuse: lock settles on terminal")
	entry.queue_free()
	await _free_parts(parts)


## A synchronous terminal refusal (reduced SDK or config) settles through
## the entry like any failure: the error shows, busy never sticks, no lock
## is held, and the ID, binding, and slot are untouched. Covers provider
## sign-in from a local guest and a link refusal on an anonymous guest.
func _test_sync_refusal_settles_through_entry() -> void:
	var refusals: Array = [
		{"status": "unsupported", "code": "native_bridge_unavailable"},
		{"status": "not_configured", "code": "identity_not_configured",
			"missing": ["firebase.project_id"]},
	]
	for refusal in refusals:
		_wipe_all()
		var parts: Dictionary = _make_parts()
		var host: Node = parts["host"]
		var fake: Node = parts["fake"]
		var account: Node = parts["account"]
		fake.capabilities = {
			"status": "ok", "supported": true,
			"providers": [
				{"id": "google", "label": "Google", "ready": true},
			],
			"guest": true,
		}
		host.startup()
		var minted: String = str((host.account_state() as Dictionary).get(
			"public_id", ""))
		var entry: ProductionEntry = _make_entry(host)
		await _frames(3)
		var gate: GateEntry = entry.get_node("Gate") as GateEntry
		await _tap(entry)
		var label: String = str((refusal as Dictionary).get("status", ""))
		fake.provider_receipt = (refusal as Dictionary).duplicate()
		(_fired["error"] as Array).clear()
		gate.provider_login_requested.emit("google")
		await _frames(3)
		_expect_true((gate.get_node("Content/StatusCard/Error") as Control
			).visible, "refusal-%s: sync refusal shows the error" % label)
		_expect_false((gate.get_node("Content/StatusCard/Busy") as Control
			).visible, "refusal-%s: busy does not stick" % label)
		_expect_false(host.is_login_pending(),
			"refusal-%s: no pending lock" % label)
		_expect_equal(str((host.account_state() as Dictionary).get(
			"public_id", "")), minted,
			"refusal-%s: same durable id" % label)
		_expect_true(str((host.account_state() as Dictionary).get(
			"cloud_uid", "")).is_empty(),
			"refusal-%s: stays a local guest" % label)
		_expect_true((_fired["error"] as Array).size() >= 1,
			"refusal-%s: production error fired" % label)
		_expect_equal(str(((_fired["error"] as Array)[0] as Dictionary).get(
			"status", "")), label,
			"refusal-%s: error preserves its status" % label)
		(gate.get_node("Content/StatusCard/Error/ErrorRow/ErrorCancel"
			) as Button).pressed.emit()
		await _frames(2)
		_expect_true((gate.get_node("Content/StatusCard/LoggedOut"
			) as Control).visible,
			"refusal-%s: cancel returns to choices" % label)
		# An anonymous guest with a durable binding, refused at link:
		# the same UID, ID, and binding survive.
		fake.guest_receipt = {"status": "ok", "session": {
			"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
		host.begin_guest()
		await _frames(2)
		var anon_id: String = str((host.account_state() as Dictionary).get(
			"public_id", ""))
		account.adopt_canonical_id(UID_A, anon_id)
		(_fired["error"] as Array).clear()
		fake.link_receipt = (refusal as Dictionary).duplicate()
		var link_receipt: Dictionary = host.link_provider("google")
		await _frames(2)
		_expect_equal(str(link_receipt.get("status", "")), label,
			"refusal-%s: link receipt stays terminal" % label)
		_expect_true((_fired["error"] as Array).size() >= 1,
			"refusal-%s: link refusal fires an error" % label)
		_expect_equal(str((host.account_state() as Dictionary).get(
			"public_id", "")), anon_id,
			"refusal-%s: link keeps the id" % label)
		_expect_equal(str((host.account_state() as Dictionary).get(
			"cloud_uid", "")), UID_A,
			"refusal-%s: link keeps the uid" % label)
		_expect_equal(account.public_id_for_uid(UID_A), anon_id,
			"refusal-%s: link keeps the durable binding" % label)
		_expect_false(host.is_login_pending(),
			"refusal-%s: link takes no lock" % label)
		entry.queue_free()
		await _free_parts(parts)


## An anonymous Firebase guest stays linkable while an authenticated
## provider session hides every link, as before. Linking keeps the same
## UID and public ID; a conflicting link never merges.
func _test_anonymous_link_available_vs_authenticated() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	fake.capabilities = {
		"status": "ok", "supported": true,
		"providers": [
			{"id": "google", "label": "Google", "ready": true},
			{"id": "apple", "label": "Apple", "ready": true},
		],
		"guest": true,
	}
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var local_links: Array = entry._linkable_providers(host)
	_expect_equal(local_links.size(), 2,
		"links: local guest sees both providers")
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _frames(2)
	_expect_equal(str((host.account_state() as Dictionary).get(
		"cloud_uid", "")), UID_A, "links: anonymous session live")
	var anon_links: Array = entry._linkable_providers(host)
	_expect_equal(anon_links.size(), 2,
		"links: anonymous guest stays linkable")
	for row in anon_links:
		_expect_true(str((row as Dictionary).get("id", ""))
			!= "anonymous", "links: anonymous itself never listed")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted, "links: anonymous keeps the id")
	fake.link_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "google"}}
	var linked: Dictionary = host.link_provider("google")
	await _frames(2)
	_expect_equal(str(linked.get("status", "")), "ok", "links: link ok")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"cloud_uid", "")), UID_A, "links: link keeps the uid")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted, "links: link keeps the id")
	var auth_links: Array = entry._linkable_providers(host)
	_expect_true(auth_links.is_empty(),
		"links: authenticated account hides every link")
	fake.link_receipt = {"status": "conflict",
		"code": "already_linked_elsewhere", "provider": "apple"}
	(_fired["error"] as Array).clear()
	var conflicted: Dictionary = host.link_provider("apple")
	await _frames(2)
	_expect_equal(str(conflicted.get("status", "")), "conflict",
		"links: conflicting link reports conflict")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"cloud_uid", "")), UID_A,
		"links: conflict keeps the session")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted, "links: conflict keeps the id")
	_expect_true((_fired["error"] as Array).size() >= 1,
		"links: conflict fires for a UI choice")
	entry.queue_free()
	await _free_parts(parts)


## A conflicting link is never auto-merged and never auto-switched:
## the conflict error persists across duplicates with its switch
## affordance, Retry repeats the link (the conflict returns, the guest
## stays), and only the explicit switch signs into the other account.
func _test_conflict_switch_preserved() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	fake.link_receipt = {"status": "conflict",
		"code": "already_linked_elsewhere", "provider": "play_games"}
	entry._on_account_link("play_games")
	await _frames(3)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "switch: conflict shows the error")
	var detail: String = str((gate.get_node(
		"Content/StatusCard/Error/ErrorDetail") as Label).text)
	_expect_true(detail.contains(GateEntryStrings.text(
		"gate.auth.error_title")),
		"switch: conflict keeps the friendly title")
	_expect_true(detail.contains("play_games"),
		"switch: conflict names the provider for the switch")
	for _index in 2:
		host.production_changed.emit(host.account_state())
	await _frames(1)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "switch: duplicates keep the conflict error")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted, "switch: guest kept, never merged")
	# Retry after the failed link repeats the link: the conflict comes
	# back, no sign-in starts, and nothing switches accounts.
	fake.link_receipt = {"status": "conflict",
		"code": "already_linked_elsewhere", "provider": "play_games"}
	(gate.get_node("Content/StatusCard/Error/ErrorRow/RetryLogin"
		) as Button).pressed.emit()
	await _frames(3)
	_expect_equal((fake.calls as Array).count("link_provider"), 2,
		"switch: retry repeats the link")
	_expect_equal((fake.calls as Array).count("sign_in_provider"), 0,
		"switch: retry starts no sign-in")
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "switch: repeated conflict shows the error again")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted,
		"switch: retry keeps the guest, never merges")
	_expect_true(str((host.account_state() as Dictionary).get(
		"cloud_uid", "")).is_empty(),
		"switch: retry switches no account")
	# Only the explicit switch signs into the other account.
	fake.provider_receipt = {"status": "pending"}
	var switched: Dictionary = host.switch_to_provider("play_games")
	_expect_equal(str(switched.get("status", "")), "pending",
		"switch: explicit switch starts a sign-in")
	sender.queue_ok(_profile_body(UID_A, minted))
	# Authoritative empty cloud for the initial check after the switch.
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.complete_session(_last_request_id(fake), {"kind": "cloud",
		"uid": UID_A, "provider": "play_games"})
	await _frames(10)
	await _settle_restore(host)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "switch: switch lands the card")
	_expect_equal((host.account_state() as Dictionary).get(
		"cloud_uid", ""), UID_A, "switch: new session live")
	_expect_equal((fake.calls as Array).count("sign_in_provider"), 1,
		"switch: exactly the explicit switch signed in")
	entry.queue_free()
	await _free_parts(parts)


## The link-retry ownership regression: an anonymous SDK session fails
## its Google link (async, like the real device failure), and the shared
## Error Retry repeats the LINK. The adapter receives link again with
## zero sign-in calls, the successful link keeps the original UID and
## durable public ID, and profile/checkpoint/Hall configuration never
## adopts a second UID.
func _test_link_retry_repeats_link_preserves_uid() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	var account: Node = parts["account"]
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_write_checkpoint({"cycle": 1, "journey_id": "link-retry-j-1"})
	sender.queue_ok(_profile_body(UID_A, minted))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _await_ready(host)
	_expect_equal(account.public_id_for_uid(UID_A), minted,
		"link-retry: anonymous binding durable before the link")
	_expect_equal(str(host.get("_configured_uid")), UID_A,
		"link-retry: cloud configured for the original uid")
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	fake.link_receipt = {"status": "pending"}
	entry._on_account_link("google")
	await _frames(2)
	var first_id: String = _last_request_id(fake)
	_expect_true(host.is_login_pending(),
		"link-retry: link request in flight")
	fake.complete_error(first_id, {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "link-retry: failed link shows the error")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"cloud_uid", "")), UID_A,
		"link-retry: failure keeps the original uid")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted,
		"link-retry: failure keeps the durable id")
	fake.link_receipt = {"status": "pending"}
	(gate.get_node("Content/StatusCard/Error/ErrorRow/RetryLogin"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "link-retry: retry shows busy, old failure retired")
	var second_id: String = _last_request_id(fake)
	_expect_true(not second_id.is_empty() and second_id != first_id,
		"link-retry: retry issues a second native request")
	_expect_equal((fake.calls as Array).count("link_provider"), 2,
		"link-retry: adapter receives link again")
	_expect_equal((fake.calls as Array).count("sign_in_provider"), 0,
		"link-retry: zero sign-in calls, never a silent sign-in")
	fake.complete_session(second_id, {"kind": "cloud", "uid": UID_A,
		"provider": "google"})
	await _frames(10)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "link-retry: linked success clears to the card")
	_expect_false((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "link-retry: linked success shows no error")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"cloud_uid", "")), UID_A,
		"link-retry: retried link keeps the original uid")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted,
		"link-retry: retried link keeps the durable id")
	_expect_equal(account.public_id_for_uid(UID_A), minted,
		"link-retry: binding still names the original id")
	_expect_equal(str(host.get("_configured_uid")), UID_A,
		"link-retry: cloud still configured for the original uid")
	_expect_equal(str(((host.get("_coordinator") as Node
		).account_snapshot() as Dictionary).get("uid", "")), UID_A,
		"link-retry: coordinator snapshot names the original uid")
	var wire: String = JSON.stringify((sender as RefCounted).calls)
	_expect_true(wire.contains(UID_A),
		"link-retry: wire traffic names the original uid")
	_expect_false(wire.contains(UID_B),
		"link-retry: wire traffic never adopts a second uid")
	_expect_false(wire.contains("fake-cloud-uid"),
		"link-retry: wire traffic never adopts a foreign uid")
	_expect_true(FileAccess.get_file_as_string(
		Journey.account_main_path(minted)).contains("link-retry-j-1"),
		"link-retry: checkpoint slot untouched")
	_expect_equal((fake.calls as Array).count("sign_in_provider"), 0,
		"link-retry: still zero sign-in calls at the end")
	_expect_true(str(host.get("_retry_operation")).is_empty(),
		"link-retry: terminal success retires the record")
	entry.queue_free()
	await _free_parts(parts)


## Ordinary sign-in retry repeats the sign-in: two provider calls, zero
## link calls, and the session lands on the signed-in UID.
func _test_signin_retry_repeats_signin() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	fake.provider_receipt = {"status": "pending"}
	var first: Dictionary = host.begin_provider("play_games")
	_expect_equal(str(first.get("status", "")), "pending",
		"signin-retry: sign-in starts")
	var first_id: String = _last_request_id(fake)
	fake.complete_error(first_id, {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted,
		"signin-retry: failure keeps the durable id")
	_expect_false(host.is_login_pending(),
		"signin-retry: failure settles the lock")
	fake.provider_receipt = {"status": "pending"}
	var retried: Dictionary = host.retry_login("play_games")
	_expect_equal(str(retried.get("status", "")), "pending",
		"signin-retry: retry starts again")
	_expect_true(_last_request_id(fake) != first_id,
		"signin-retry: retry issues a second native request")
	_expect_equal((fake.calls as Array).count("sign_in_provider"), 2,
		"signin-retry: adapter receives sign-in again")
	_expect_equal((fake.calls as Array).count("link_provider"), 0,
		"signin-retry: zero link calls")
	sender.queue_ok(_profile_body(UID_A, minted))
	fake.complete_session(_last_request_id(fake), {"kind": "cloud",
		"uid": UID_A, "provider": "play_games"})
	await _frames(10)
	_expect_equal((host.account_state() as Dictionary).get(
		"cloud_uid", ""), UID_A, "signin-retry: session live")
	_expect_true(str(host.get("_retry_operation")).is_empty(),
		"signin-retry: terminal success retires the record")
	await _free_parts(parts)


## Retry after an explicit switch repeats the sign-in-shaped switch, and
## only an explicit switch ever dispatches one.
func _test_switch_retry_signs_in_after_explicit_switch() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	fake.provider_receipt = {"status": "pending"}
	var first: Dictionary = host.switch_to_provider("apple")
	_expect_equal(str(first.get("status", "")), "pending",
		"switch-retry: explicit switch starts")
	_expect_equal(str(host.get("_retry_operation")), "switch",
		"switch-retry: record names the explicit switch")
	var first_id: String = _last_request_id(fake)
	fake.complete_error(first_id, {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	fake.provider_receipt = {"status": "pending"}
	var retried: Dictionary = host.retry_login("apple")
	_expect_equal(str(retried.get("status", "")), "pending",
		"switch-retry: retry repeats the switch")
	_expect_true(_last_request_id(fake) != first_id,
		"switch-retry: retry issues a second native request")
	_expect_equal((fake.calls as Array).count("sign_in_provider"), 2,
		"switch-retry: adapter receives sign-in again")
	_expect_equal((fake.calls as Array).count("link_provider"), 0,
		"switch-retry: zero link calls")
	sender.queue_ok(_profile_body(UID_B, minted))
	fake.complete_session(_last_request_id(fake), {"kind": "cloud",
		"uid": UID_B, "provider": "apple"})
	await _frames(10)
	_expect_equal((host.account_state() as Dictionary).get(
		"cloud_uid", ""), UID_B, "switch-retry: switched session live")
	_expect_true(str(host.get("_retry_operation")).is_empty(),
		"switch-retry: terminal success retires the record")
	await _free_parts(parts)


## Retry is bound to the remembered provider: a different stale provider
## (or none remembered at all) is refused without touching any account,
## the entry repaints instead of sticking on busy, and the genuine Retry
## for the remembered provider still works afterwards.
func _test_retry_mismatched_provider_refused() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	var changed_before: int = (_fired["changed"] as Array).size()
	var cold: Dictionary = host.retry_login("google")
	_expect_equal(str(cold.get("code", "")), "stale_retry",
		"stale-retry: no record is refused")
	_expect_true((fake.calls as Array).is_empty(),
		"stale-retry: refused retry touches no account")
	_expect_equal((_fired["changed"] as Array).size(),
		changed_before + 1,
		"stale-retry: refused retry repaints the honest state")
	_expect_true((_fired["error"] as Array).is_empty(),
		"stale-retry: refused retry raises no error")
	fake.link_receipt = {"status": "pending"}
	host.link_provider("google")
	var first_id: String = _last_request_id(fake)
	fake.complete_error(first_id, {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_equal((fake.calls as Array).count("link_provider"), 1,
		"stale-retry: failed link issued once")
	changed_before = (_fired["changed"] as Array).size()
	var stale: Dictionary = host.retry_login("apple")
	_expect_equal(str(stale.get("code", "")), "stale_retry",
		"stale-retry: different provider is refused")
	_expect_equal((fake.calls as Array).count("link_provider"), 1,
		"stale-retry: refused retry issues no link")
	_expect_equal((fake.calls as Array).count("sign_in_provider"), 0,
		"stale-retry: refused retry issues no sign-in")
	_expect_equal((_fired["changed"] as Array).size(),
		changed_before + 1,
		"stale-retry: mismatch repaints instead of sticking")
	_expect_equal(str(host.get("_retry_operation")), "link",
		"stale-retry: mismatch keeps the remembered link")
	_expect_equal(str(host.get("_retry_provider")), "google",
		"stale-retry: mismatch keeps the remembered provider")
	fake.link_receipt = {"status": "pending"}
	var genuine: Dictionary = host.retry_login("google")
	_expect_equal(str(genuine.get("status", "")), "pending",
		"stale-retry: genuine retry still works")
	_expect_equal((fake.calls as Array).count("link_provider"), 2,
		"stale-retry: genuine retry repeats the link")
	fake.complete_error(_last_request_id(fake), {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	await _free_parts(parts)


## Retry boundaries: a synchronous link failure still records the link
## intent (the error arrives during the call), ordinary cancellation and
## sign-out retire the record, a completed deletion retires it with the
## deleted account, and a draining answer keeps it until the terminal.
func _test_retry_cancel_signout_and_sync_failure_boundaries() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	var minted: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	# A synchronous link failure records link intent: Retry repeats the
	# link and the success keeps the UID and the ID.
	fake.link_receipt = {"status": "error", "code": "network_error",
		"retryable": true}
	var sync_failed: Dictionary = host.link_provider("google")
	_expect_equal(str(sync_failed.get("status", "")), "error",
		"retry-edge: sync link failure stays terminal")
	_expect_equal((_fired["error"] as Array).size(), 1,
		"retry-edge: sync failure fires once")
	_expect_false(host.is_login_pending(),
		"retry-edge: sync failure takes no lock")
	_expect_equal(str(host.get("_retry_operation")), "link",
		"retry-edge: sync failure still records the link")
	fake.link_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "google"}}
	var sync_retried: Dictionary = host.retry_login("google")
	_expect_equal(str(sync_retried.get("status", "")), "ok",
		"retry-edge: retry repeats the sync link")
	_expect_equal((fake.calls as Array).count("link_provider"), 2,
		"retry-edge: adapter receives link again")
	_expect_equal((fake.calls as Array).count("sign_in_provider"), 0,
		"retry-edge: zero sign-in calls")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"cloud_uid", "")), UID_A,
		"retry-edge: retried link keeps the uid")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), minted,
		"retry-edge: retried link keeps the id")
	_expect_true(str(host.get("_retry_operation")).is_empty(),
		"retry-edge: sync success retires the record")
	# Cancelling a live attempt retires the record with it.
	fake.provider_receipt = {"status": "pending"}
	host.begin_provider("apple")
	await _frames(1)
	var cancelled: Dictionary = host.cancel_login("apple")
	_expect_equal(str(cancelled.get("status", "")), "cancelled",
		"retry-edge: live cancel lands")
	_expect_true(str(host.get("_retry_operation")).is_empty(),
		"retry-edge: live cancel retires the record")
	var after_cancel: Dictionary = host.retry_login("apple")
	_expect_equal(str(after_cancel.get("code", "")), "stale_retry",
		"retry-edge: retry after cancel is refused")
	_expect_equal((fake.calls as Array).count("sign_in_provider"), 1,
		"retry-edge: refused retry issues no sign-in")
	# Cancelling after a settled failure retires the record too.
	fake.provider_receipt = {"status": "pending"}
	host.begin_provider("apple")
	fake.complete_error(_last_request_id(fake), {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	var settled_cancel: Dictionary = host.cancel_login("apple")
	_expect_equal(str(settled_cancel.get("code", "")),
		"no_pending_request",
		"retry-edge: settled cancel reports nothing pending")
	_expect_true(str(host.get("_retry_operation")).is_empty(),
		"retry-edge: settled cancel retires the record")
	_expect_equal(str((host.retry_login("apple") as Dictionary).get(
		"code", "")), "stale_retry",
		"retry-edge: retry after settled cancel is refused")
	# Sign-out retires the record with the old account.
	fake.provider_receipt = {"status": "pending"}
	host.begin_provider("apple")
	fake.complete_error(_last_request_id(fake), {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_equal(str(host.get("_retry_operation")), "sign_in",
		"retry-edge: failure records the sign-in")
	var sign_ins: int = (fake.calls as Array).count("sign_in_provider")
	host.sign_out()
	await _frames(2)
	_expect_true(str(host.get("_retry_operation")).is_empty(),
		"retry-edge: sign-out retires the record")
	_expect_equal(str((host.retry_login("apple") as Dictionary).get(
		"code", "")), "stale_retry",
		"retry-edge: retry after sign-out is refused")
	_expect_equal((fake.calls as Array).count("sign_in_provider"),
		sign_ins, "retry-edge: refused retry issues no sign-in")
	# A draining answer keeps the record until the terminal lands.
	fake.cancel_status = "draining"
	fake.provider_receipt = {"status": "pending"}
	host.begin_provider("apple")
	await _frames(1)
	_expect_equal(str((host.cancel_login("apple") as Dictionary).get(
		"status", "")), "draining",
		"retry-edge: draining cancel keeps the lock")
	_expect_equal(str(host.get("_retry_operation")), "sign_in",
		"retry-edge: draining keeps the record")
	_expect_equal(str((host.retry_login("apple") as Dictionary).get(
		"status", "")), "draining",
		"retry-edge: retry while draining is refused")
	fake.complete_error(_last_request_id(fake), {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_false(bool((host.account_state() as Dictionary).get(
		"draining", true)),
		"retry-edge: terminal settles the drain")
	fake.provider_receipt = {"status": "pending"}
	_expect_equal(str((host.retry_login("apple") as Dictionary).get(
		"status", "")), "pending",
		"retry-edge: retry after the drained terminal repeats")
	_expect_equal((fake.calls as Array).count("link_provider"), 2,
		"retry-edge: drained terminal issues no link")
	fake.complete_error(_last_request_id(fake), {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	fake.cancel_status = "cancelled"
	await _free_parts(parts)
	# A completed deletion retires the record with the deleted account.
	_wipe_all()
	var second: Dictionary = _make_parts()
	var host_b: Node = second["host"]
	var fake_b: Node = second["fake"]
	host_b.startup()
	fake_b.link_receipt = {"status": "pending"}
	host_b.link_provider("google")
	fake_b.complete_error(_last_request_id(fake_b), {"status": "error",
		"code": "network_error", "retryable": true})
	await _frames(3)
	_expect_equal(str(host_b.get("_retry_operation")), "link",
		"retry-edge: failure records the link before deletion")
	var links: int = (fake_b.calls as Array).count("link_provider")
	var deleted: Dictionary = await host_b.delete_current_account()
	_expect_equal(str(deleted.get("status", "")), "ok",
		"retry-edge: local deletion completes")
	_expect_true(str(host_b.get("_retry_operation")).is_empty(),
		"retry-edge: completed deletion retires the record")
	_expect_equal(str((host_b.retry_login("google") as Dictionary).get(
		"code", "")), "stale_retry",
		"retry-edge: retry after deletion is refused")
	_expect_equal((fake_b.calls as Array).count("link_provider"), links,
		"retry-edge: refused retry issues no link")
	await _free_parts(second)


func _sign_in_cloud(parts: Dictionary, uid: String,
		canonical_id: String) -> void:
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	sender.queue_ok(_profile_body(uid, canonical_id))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": uid, "provider": "anonymous"}}
	host.begin_guest()
	await _await_ready(host)


func _launch_delete(host: Node) -> Dictionary:
	var box: Dictionary = {}
	_run_delete_box(host, box)
	return box


func _run_delete_box(host: Node, box: Dictionary) -> void:
	box["result"] = await host.delete_current_account()


func _await_box(box: Dictionary, frames: int = 240) -> Dictionary:
	for _index in frames:
		if box.has("result"):
			return box["result"]
		await get_tree().process_frame
	return box.get("result", {})


func _pending_request_id(fake: Node) -> String:
	var issued: Dictionary = fake.get("_issued")
	if issued.is_empty():
		return ""
	return str(issued.keys()[0])


func _last_request_id(fake: Node) -> String:
	var issued: Dictionary = fake.get("_issued")
	if issued.is_empty():
		return ""
	return str(issued.keys()[-1])


func _launch_token(host: Node) -> Dictionary:
	var box: Dictionary = {}
	_run_token_box(host, box)
	return box


func _run_token_box(host: Node, box: Dictionary) -> void:
	box["result"] = await host.ensure_token(true)


func _write_decoy_slot() -> void:
	var writer: FileAccess = FileAccess.open(
		Journey.account_main_path(OTHER_ID), FileAccess.WRITE)
	writer.store_string("{\"decoy\": true}")
	writer.close()


func _commit_ack_body() -> String:
	return "{\"writeResults\":[{},{},{},{}]}"


## The four owned document names one deletion commit must carry, in the
## CloudAccount plan order: Hall, checkpoint, reservation, profile.
func _expected_commit_documents(uid: String, public_id: String) -> Array:
	var root: String = \
		"projects/moonlitbeacon-778ee/databases/(default)/documents"
	return [
		"%s/mb_hall_v1/%s" % [root, public_id],
		"%s/mb_checkpoints_v1/%s" % [root, uid],
		"%s/mb_attendance_v1/%s" % [root, public_id],
		"%s/mb_reservations_v1/%s" % [root, public_id],
		"%s/mb_profiles_v1/%s" % [root, uid],
	]


## Queues the name-resolution lookup an unnamed account's deletion
## performs before its atomic commit: no adventurer row exists.
func _queue_unclaimed_adventurer(sender: RefCounted) -> void:
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})


## Asserts the wire holds one name lookup plus the atomic four-row
## deletion commit: a single POST to `documents:commit` carrying exactly
## the four owned deletes with no preconditions. Sequential or incomplete
## shapes fail here.
func _expect_commit_shape(sender: RefCounted, uid: String,
		public_id: String, label: String) -> void:
	var calls: Array = sender.calls
	_expect_equal(calls.size(), 2,
		label + ": one lookup plus one commit, never five deletes")
	if calls.size() < 2:
		return
	_expect_equal(str((calls[0] as Dictionary).get("method", "")), "GET",
		label + ": deletion resolves the name first")
	_expect_true(str((calls[0] as Dictionary).get("url", "")).contains(
		"mb_adventurers_v1"), label + ": lookup reads the adventurer row")
	var call: Dictionary = calls[1]
	_expect_equal(str(call.get("method", "")), "POST",
		label + ": deletion commits via POST")
	_expect_true(str(call.get("url", "")).contains("documents:commit"),
		label + ": deletion hits the commit endpoint")
	var parsed: Variant = JSON.parse_string(str(call.get("body", "")))
	_expect_true(typeof(parsed) == TYPE_DICTIONARY,
		label + ": commit body parses")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var writes: Array = (parsed as Dictionary).get("writes", [])
	_expect_equal(writes.size(), 5,
		label + ": commit carries all five deletes")
	var names: Array = []
	for write in writes:
		names.append(str((write as Dictionary).get("delete", "")))
		_expect_false((write as Dictionary).has("currentDocument"),
			label + ": no preconditions, missing rows are no-ops")
	_expect_equal(names, _expected_commit_documents(uid, public_id),
		label + ": exact five owned documents in plan order")
	_expect_no_delete_calls(sender, label)


## Negative control: the run must never send a standalone DELETE. The live
## rules deny sequential profile/reservation deletes, so any DELETE on the
## wire is the rejected shape.
func _expect_no_delete_calls(sender: RefCounted, label: String) -> void:
	for call in (sender.calls as Array):
		_expect_true(str((call as Dictionary).get("method", ""))
			!= "DELETE", label + ": no sequential DELETE on the wire")


## Delete names carried by the last commit on the wire, for proving a
## retry repeats the identical four-row shape over already absent rows.
func _commit_documents(sender: RefCounted) -> Array:
	var calls: Array = sender.calls
	if calls.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(str(
		(calls[calls.size() - 1] as Dictionary).get("body", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var names: Array = []
	for write in ((parsed as Dictionary).get("writes", []) as Array):
		names.append(str((write as Dictionary).get("delete", "")))
	return names


func _test_delete_pending_success_cleans_up() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 3, "journey_id": "gone-j-1"})
	_write_decoy_slot()
	Vault.continue_coins = 2
	Vault.save_vault()
	_seal_and_journal(CANON_C, "gone-j-1", 4, 5)
	Journey.use_account(OTHER_ID)
	_seal_and_journal(OTHER_ID, "spared-j-1", 2, 3)
	Journey.use_account(CANON_C)
	_expect_equal(Vault.continue_coins, 0,
		"delete: both scopes journal before deletion")
	var shards_before: int = Vault.shards
	var settled_before: Array = (Vault.settled_journeys as Array).duplicate()
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	var box: Dictionary = _launch_delete(host)
	await _frames(3)
	_expect_true(bool((host.account_state() as Dictionary).get(
		"deletion_in_flight", false)),
		"delete: lock visible while native pends")
	fake.complete_session(_pending_request_id(fake),
		{"kind": "local_guest"})
	var result: Dictionary = await _await_box(box)
	_expect_equal(str(result.get("status", "")), "ok",
		"delete: pending native success finishes cleanup")
	_expect_commit_shape(sender, UID_A, CANON_C, "delete")
	var evidence: Dictionary = host.last_delete_commit_evidence()
	_expect_equal(str(evidence.get("method", "")), "POST",
		"delete: seam records the commit method")
	_expect_equal(str(evidence.get("relative_path", "")),
		"documents:commit", "delete: seam records the commit path")
	_expect_equal(evidence.get("documents", []),
		_expected_commit_documents(UID_A, CANON_C),
		"delete: seam records the exact four owned documents")
	_expect_equal(str(evidence.get("reply_status", "")), "ok",
		"delete: seam records the acknowledgement")
	var planned: Dictionary = HOST_SCRIPT.delete_commit_request(
		UID_A, CANON_C)
	var wire_calls: Array = sender.calls as Array
	_expect_equal(str(planned.get("body", "")), str(
		(wire_calls[wire_calls.size() - 1] as Dictionary).get(
			"body", "")),
		"delete: seam body matches the wire bytes")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete: own slot removed")
	_expect_true((parts["account"] as Node).public_id_for_uid(
		UID_A).is_empty(), "delete: own binding forgotten")
	_expect_true(str((host.account_state() as Dictionary).get(
		"public_id", "")) != CANON_C,
		"delete: fresh guest minted after cleanup")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(OTHER_ID)),
		"delete: other account slot untouched")
	Journey.use_account(OTHER_ID)
	_expect_equal(int(Vault.scoped_continue_txn().get("checkpoint_id", 0)),
		3, "delete: the spared scope keeps its receipt")
	_expect_equal(Vault.recover_paid_continue(), "recovered",
		"delete: the spared receipt still settles")
	_expect_equal(Vault.continue_coins, 0,
		"delete: the spared settle charges nothing more")
	Journey.use_account(CANON_C)
	_expect_true(Vault.scoped_continue_txn().is_empty(),
		"delete: the deleted scope keeps no receipt")
	_expect_equal(Vault.continue_coins, 0,
		"delete: two debits total, none refunded, none doubled")
	_expect_equal(Vault.shards, shards_before,
		"delete: vault shards untouched")
	_expect_equal(Vault.settled_journeys, settled_before,
		"delete: settled ledgers untouched")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		Journey.account_main_path(OTHER_ID)))
	await _free_parts(parts)


func _test_delete_commit_denied_stops() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 2, "journey_id": "stay-j-1"})
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_reply({"transport": "ok", "code": 403, "body": "{}"})
	var result: Dictionary = await host.delete_current_account()
	_expect_equal(str(result.get("status", "")), "failure",
		"delete-fail: denied commit fails the run")
	_expect_equal(str(result.get("code", "")), "permission-denied",
		"delete-fail: denial code passes through")
	_expect_equal(str(result.get("failed_step", "")), "commit",
		"delete-fail: names the refused atomic commit")
	_expect_equal(result.get("remaining", []),
		["hall", "checkpoint", "attendance", "reservation", "profile"],
		"delete-fail: all five steps remain for a clean retry")
	_expect_commit_shape(sender, UID_A, CANON_C, "delete-fail")
	_expect_false((fake.calls as Array).has("delete_account"),
		"delete-fail: native never called after a cloud refusal")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-fail: local slot preserved")
	_expect_equal((parts["account"] as Node).public_id_for_uid(UID_A),
		CANON_C, "delete-fail: binding preserved")
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), CANON_C, "delete-fail: same id kept")
	var evidence: Dictionary = host.last_delete_commit_evidence()
	_expect_equal(str(evidence.get("reply_code", "")), "permission-denied",
		"delete-fail: seam records the denial")
	# A truthful retry succeeds once the commit acknowledges.
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "ok"}
	var retry: Dictionary = await host.delete_current_account()
	_expect_equal(str(retry.get("status", "")), "ok",
		"delete-fail: retry finishes after the commit acks")
	_expect_commit_shape(sender, UID_A, CANON_C, "delete-fail-retry")
	await _free_parts(parts)


func _test_delete_commit_timeout_preserves() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 2, "journey_id": "timeout-commit-j-1"})
	await _frames(20)
	sender.reset()
	for _index in 3:
		sender.queue_reply({"transport": "timeout", "code": 0,
			"body": PackedByteArray()})
	var result: Dictionary = await host.delete_current_account()
	_expect_equal(str(result.get("status", "")), "failure",
		"delete-timeout-commit: timed-out commit fails the run")
	_expect_equal(str(result.get("code", "")), "timeout",
		"delete-timeout-commit: timeout code passes through")
	_expect_equal((sender.calls as Array).size(), 3,
		"delete-timeout-commit: bounded retries, never endless")
	_expect_no_delete_calls(sender, "delete-timeout-commit")
	_expect_false((fake.calls as Array).has("delete_account"),
		"delete-timeout-commit: native never called without an ack")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-timeout-commit: local slot preserved")
	_expect_equal((parts["account"] as Node).public_id_for_uid(UID_A),
		CANON_C, "delete-timeout-commit: binding preserved")
	var evidence: Dictionary = host.last_delete_commit_evidence()
	_expect_equal(str(evidence.get("reply_code", "")), "timeout",
		"delete-timeout-commit: seam records the timeout")
	# The retry repeats the identical four-row shape and finishes.
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "ok"}
	var retry: Dictionary = await host.delete_current_account()
	_expect_equal(str(retry.get("status", "")), "ok",
		"delete-timeout-commit: retry finishes after the commit acks")
	_expect_commit_shape(sender, UID_A, CANON_C, "delete-timeout-retry")
	await _free_parts(parts)


func _test_delete_native_sync_error_preserves() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 2, "journey_id": "sync-err-j-1"})
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "error", "code": "native_misfire",
		"retryable": true}
	var result: Dictionary = await host.delete_current_account()
	_expect_equal(str(result.get("status", "")), "failure",
		"delete-sync-err: sync native error fails the run")
	_expect_equal(str(result.get("code", "")), "native_misfire",
		"delete-sync-err: sync native code passes through")
	_expect_commit_shape(sender, UID_A, CANON_C, "delete-sync-err")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-sync-err: slot preserved for the retry")
	_expect_equal((parts["account"] as Node).public_id_for_uid(UID_A),
		CANON_C, "delete-sync-err: binding preserved")
	# The retry re-sends the identical commit over the already absent
	# rows (missing rows are server no-ops) and finishes.
	var first_documents: Array = _commit_documents(sender)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "ok"}
	var retry: Dictionary = await host.delete_current_account()
	_expect_equal(str(retry.get("status", "")), "ok",
		"delete-sync-err: retry succeeds over absent rows")
	_expect_equal(_commit_documents(sender), first_documents,
		"delete-sync-err: retry repeats the identical four deletes")
	await _free_parts(parts)


func _test_delete_native_sync_cancel_preserves() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 1, "journey_id": "sync-cancel-j-1"})
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	# The native sheet dismissed before anything began: a sync
	# cancellation after the acknowledged commit.
	fake.delete_receipt = {"status": "cancelled"}
	var result: Dictionary = await host.delete_current_account()
	_expect_equal(str(result.get("code", "")), "delete_cancelled",
		"delete-sync-cancel: cancellation reported")
	_expect_commit_shape(sender, UID_A, CANON_C, "delete-sync-cancel")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-sync-cancel: slot preserved")
	_expect_equal((host.account_state() as Dictionary).get(
		"cloud_uid", ""), UID_A, "delete-sync-cancel: session kept")
	await _free_parts(parts)


func _test_delete_duplicate_taps_single_commit() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 1, "journey_id": "double-tap-j-1"})
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	var box: Dictionary = _launch_delete(host)
	await _frames(3)
	var second: Dictionary = await host.delete_current_account()
	_expect_equal(str(second.get("code", "")), "deletion_in_flight",
		"delete-taps: second tap retired while the first owns the op")
	_expect_equal((sender.calls as Array).size(), 2,
		"delete-taps: duplicate tap sends no second commit")
	fake.complete_session(_pending_request_id(fake),
		{"kind": "local_guest"})
	var first: Dictionary = await _await_box(box)
	_expect_equal(str(first.get("status", "")), "ok",
		"delete-taps: owned run still finishes")
	_expect_equal((fake.calls as Array).count("delete_account"), 1,
		"delete-taps: exactly one native attempt ran")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-taps: slot removed once by the owned run")
	await _free_parts(parts)


func _test_delete_native_error_preserves_and_retries() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 2, "journey_id": "reauth-j-1"})
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	var box: Dictionary = _launch_delete(host)
	await _frames(3)
	# The SDK demands a recent login: a test-only scripted native code
	# passes through opaquely, preserves everything, and allows retry.
	fake.complete_error(_pending_request_id(fake),
		{"status": "error", "code": "recent_login_required",
			"retryable": true})
	var result: Dictionary = await _await_box(box)
	_expect_equal(str(result.get("status", "")), "failure",
		"delete-reauth: native error fails the run")
	_expect_equal(str(result.get("code", "")), "recent_login_required",
		"delete-reauth: native code passes through")
	_expect_commit_shape(sender, UID_A, CANON_C, "delete-reauth")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-reauth: slot preserved for the retry")
	_expect_equal((parts["account"] as Node).public_id_for_uid(UID_A),
		CANON_C, "delete-reauth: binding preserved")
	# The kept session retries the same delete end to end (a real
	# re-authentication would sign in again first; the session here was
	# never dropped, so the retry proceeds directly). The acknowledged
	# rows are already absent, so the identical commit repeats as no-ops.
	var first_documents: Array = _commit_documents(sender)
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _frames(5)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "ok"}
	var retry: Dictionary = await host.delete_current_account()
	_expect_equal(str(retry.get("status", "")), "ok",
		"delete-reauth: retry succeeds after re-authentication")
	_expect_equal(_commit_documents(sender), first_documents,
		"delete-reauth: retry repeats the identical four deletes")
	await _free_parts(parts)


func _test_delete_cancel_preserves() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 1, "journey_id": "cancel-j-1"})
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	var box: Dictionary = _launch_delete(host)
	await _frames(3)
	host.cancel_login()
	var result: Dictionary = await _await_box(box)
	_expect_equal(str(result.get("code", "")), "delete_cancelled",
		"delete-cancel: cancellation reported")
	_expect_commit_shape(sender, UID_A, CANON_C, "delete-cancel")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-cancel: slot preserved")
	_expect_equal((host.account_state() as Dictionary).get(
		"cloud_uid", ""), UID_A, "delete-cancel: session kept")
	await _free_parts(parts)


func _test_delete_draining_then_success() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	fake.cancel_status = "draining"
	var box: Dictionary = _launch_delete(host)
	await _frames(3)
	var cancelled: Dictionary = host.cancel_login()
	_expect_equal(str(cancelled.get("status", "")), "draining",
		"delete-drain: cancel reports draining, lock kept")
	fake.complete_session(_pending_request_id(fake),
		{"kind": "local_guest"})
	var result: Dictionary = await _await_box(box)
	_expect_equal(str(result.get("status", "")), "ok",
		"delete-drain: terminal success still finishes cleanup")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-drain: slot removed after the terminal")
	await _free_parts(parts)


func _test_delete_rejects_switch_and_start() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 1, "journey_id": "locked-j-1"})
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	var box: Dictionary = _launch_delete(host)
	await _frames(3)
	for attempt in [host.begin_provider("apple"),
			host.link_provider("apple"),
			host.switch_to_provider("apple"), host.sign_out(),
			host.retry_login("apple")]:
		_expect_equal(str((attempt as Dictionary).get("code", "")),
			"deletion_in_flight",
			"delete-lock: switch retired while deletion owns the op")
	_expect_equal(str((host.plan_entry(false, true) as Dictionary).get(
		"code", "")), "deletion_in_flight",
		"delete-lock: start retired while deletion owns the op")
	fake.complete_session(_pending_request_id(fake),
		{"kind": "local_guest"})
	_expect_equal(str((await _await_box(box)).get("status", "")), "ok",
		"delete-lock: owned run still finishes")
	await _free_parts(parts)


func _test_delete_account_move_aborts() -> void:
	_wipe_all()
	var fake: Node = CapableFake.new()
	var delayed: RefCounted = DelayedSender.new()
	delayed.tree_node = self
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake, ID_PATH, BIND_PATH)
	var coord: Node = COORD_SCRIPT.new() as Node
	var host: Node = HOST_SCRIPT.new() as Node
	add_child(host)
	host.inject_services({"account": account, "adapter": fake,
		"sender": delayed, "coordinator": coord, "vault": Vault})
	_watch(host)
	host.startup()
	delayed.queue_ok(_profile_body(UID_A, CANON_C))
	# Written before the coordinator subscribes, so no auto-flush races
	# the delayed delete calls below; adoption moves it to the canonical.
	_write_checkpoint({"cycle": 1, "journey_id": "moved-j-1"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _await_ready(host)
	await _frames(30)
	delayed.reset()
	_queue_unclaimed_adventurer(delayed)
	delayed.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	var box: Dictionary = _launch_delete(host)
	await _frames(2)
	# The account moves (a direct sign-out, past the host lock) while the
	# commit is still in flight.
	account.sign_out()
	var result: Dictionary = await _await_box(box)
	_expect_equal(str(result.get("code", "")), "account_moved",
		"delete-move: moved run retires before the next step")
	_expect_equal((delayed.calls as Array).size(), 1,
		"delete-move: moved account sends nothing more")
	var only_call: Dictionary = (delayed.calls as Array)[0]
	_expect_equal(str(only_call.get("method", "")), "GET",
		"delete-move: the single in-flight call is the lookup")
	_expect_true(str(only_call.get("url", "")).contains(
		"mb_adventurers_v1"),
		"delete-move: in-flight call reads the adventurer row")
	_expect_false((fake.calls as Array).has("delete_account"),
		"delete-move: native never runs for a moved account")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-move: abandoned slot preserved")
	await _free_parts({"host": host})


func _test_delete_timeout_preserves_and_late_completion_safe() -> void:
	_wipe_all()
	# A short injected deadline over the real monotonic clock: the
	# timeout is genuine elapsed expiry, not a frame count.
	var parts: Dictionary = _make_parts(null,
		{"delete_timeout_seconds": 0.4})
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 1, "journey_id": "timeout-j-1"})
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	var started_msec: int = Time.get_ticks_msec()
	var box: Dictionary = _launch_delete(host)
	var result: Dictionary = await _await_box(box)
	_expect_equal(str(result.get("code", "")), "deletion_timeout",
		"delete-timeout: bounded wait reports instead of hanging")
	_expect_true(Time.get_ticks_msec() - started_msec < 10000,
		"delete-timeout: elapsed deadline, not wall-clock 30 seconds")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-timeout: slot preserved")
	# The late terminal applies to the account but cleans up nothing and
	# releases no lock: the run already ended in failure.
	fake.complete_session(_pending_request_id(fake),
		{"kind": "local_guest"})
	await _frames(5)
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-timeout: late completion removes nothing")
	_expect_equal((parts["account"] as Node).public_id_for_uid(UID_A),
		CANON_C, "delete-timeout: binding kept for the retry")
	_expect_false(bool((host.account_state() as Dictionary).get(
		"deletion_in_flight", true)),
		"delete-timeout: lock released by the timeout")
	await _free_parts(parts)


func _test_delete_frames_before_deadline_harmless() -> void:
	_wipe_all()
	# Frozen clock, production 30-second deadline: frames alone must
	# never trip the wait.
	var clock: FakeClock = FakeClock.new()
	var parts: Dictionary = _make_parts(null, {"clock": clock})
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	var box: Dictionary = _launch_delete(host)
	await _frames(125)
	_expect_false(box.has("result"),
		"delete-frames: 125 frames are not 30 elapsed seconds")
	_expect_true(bool((host.account_state() as Dictionary).get(
		"deletion_in_flight", false)),
		"delete-frames: lock held before elapsed expiry")
	clock.advance(31000)
	var result: Dictionary = await _await_box(box)
	_expect_equal(str(result.get("code", "")), "deletion_timeout",
		"delete-frames: elapsed expiry terminates the wait")
	await _free_parts(parts)


func _test_delete_success_just_before_deadline() -> void:
	_wipe_all()
	var clock: FakeClock = FakeClock.new()
	var parts: Dictionary = _make_parts(null, {"clock": clock})
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 2, "journey_id": "near-j-1"})
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	var box: Dictionary = _launch_delete(host)
	await _frames(5)
	clock.advance(29900)
	await _frames(3)
	_expect_false(box.has("result"),
		"delete-near: 100ms shy of the deadline is still pending")
	fake.complete_session(_pending_request_id(fake),
		{"kind": "local_guest"})
	var result: Dictionary = await _await_box(box)
	_expect_equal(str(result.get("status", "")), "ok",
		"delete-near: timely genuine terminal succeeds")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-near: cleanup ran for the timely success")
	await _free_parts(parts)


func _test_delete_late_terminal_safe_for_next_run() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts(null,
		{"delete_timeout_seconds": 0.3})
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 1, "journey_id": "retry-j-1"})
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	var first_box: Dictionary = _launch_delete(host)
	var first: Dictionary = await _await_box(first_box)
	_expect_equal(str(first.get("code", "")), "deletion_timeout",
		"delete-retry: first run expires on the elapsed deadline")
	var stale_id: String = _pending_request_id(fake)
	# The late terminal (SDK kept the session: a cancellation) lands
	# after expiry. The run already ended, so it releases no waiter and
	# cleans nothing, and only settles the adapter pending.
	fake.complete_session(stale_id, {"kind": "cloud", "uid": UID_A,
		"provider": "anonymous"})
	await _frames(5)
	_expect_false(bool((host.account_state() as Dictionary).get(
		"deletion_in_flight", true)),
		"delete-retry: expired run holds no lock")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-retry: expired run kept the slot")
	# A truthful retry starts a new generation with its own native wait.
	# Its commit repeats the acknowledged one over already absent rows.
	var first_documents: Array = _commit_documents(sender)
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	var box: Dictionary = _launch_delete(host)
	await _frames(5)
	_expect_true(bool((host.account_state() as Dictionary).get(
		"deletion_in_flight", false)),
		"delete-retry: second run holds the lock")
	# A stale double-completion of the expired run cannot release it.
	fake.complete_session(stale_id, {"kind": "cloud", "uid": UID_A,
		"provider": "anonymous"})
	await _frames(3)
	_expect_false(box.has("result"),
		"delete-retry: stale terminal releases no newer waiter")
	_expect_true(bool((host.account_state() as Dictionary).get(
		"deletion_in_flight", false)),
		"delete-retry: newer lock survives the stale terminal")
	fake.complete_session(_last_request_id(fake),
		{"kind": "local_guest"})
	var second: Dictionary = await _await_box(box)
	_expect_equal(str(second.get("status", "")), "ok",
		"delete-retry: genuine terminal finishes the retry")
	_expect_equal((fake.calls as Array).count("delete_account"), 2,
		"delete-retry: exactly two native attempts ran")
	_expect_equal((sender.calls as Array).size(), 4,
		"delete-retry: one lookup plus one commit per run, nothing more")
	_expect_equal(_commit_documents(sender), first_documents,
		"delete-retry: retry repeats the identical four deletes")
	await _free_parts(parts)


func _test_delete_expired_run_deletes_no_other_account() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts(null,
		{"delete_timeout_seconds": 0.3})
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	_write_checkpoint({"cycle": 1, "journey_id": "other-j-1"})
	await _frames(20)
	sender.reset()
	_queue_unclaimed_adventurer(sender)
	sender.queue_ok(_commit_ack_body())
	fake.delete_receipt = {"status": "pending"}
	var box: Dictionary = _launch_delete(host)
	var result: Dictionary = await _await_box(box)
	_expect_equal(str(result.get("code", "")), "deletion_timeout",
		"delete-other: run expires on the elapsed deadline")
	fake.complete_session(_pending_request_id(fake),
		{"kind": "cloud", "uid": UID_A, "provider": "anonymous"})
	await _frames(5)
	# The next account moves in over the expired run's residue.
	host.sign_out()
	sender.reset()
	sender.queue_ok(_profile_body(UID_B, CANON_D))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_B, "provider": "anonymous"}}
	host.begin_guest()
	await _settle_call(host, "account_state", CANON_D)
	_write_checkpoint({"cycle": 4, "journey_id": "bob-j-1"})
	await _frames(5)
	_expect_equal(str((host.account_state() as Dictionary).get(
		"public_id", "")), CANON_D,
		"delete-other: second account session live")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_D)),
		"delete-other: second account slot intact")
	_expect_true(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"delete-other: expired run kept the first slot")
	_expect_equal((parts["account"] as Node).public_id_for_uid(UID_A),
		CANON_C, "delete-other: first binding kept for the retry")
	_expect_equal((fake.calls as Array).count("delete_account"), 1,
		"delete-other: no native delete ran for anyone else")
	await _free_parts(parts)


func _test_token_elapsed_deadline() -> void:
	_wipe_all()
	# Frozen clock, production 15-second bound: frames alone never
	# expire the token wait.
	var clock: FakeClock = FakeClock.new()
	var parts: Dictionary = _make_parts(null, {"clock": clock})
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	await _frames(20)
	fake.token_receipt = {"status": "pending"}
	var box: Dictionary = _launch_token(host)
	await _frames(60)
	_expect_false(box.has("result"),
		"token-frames: 60 frames are not 15 elapsed seconds")
	clock.advance(16000)
	var result: Dictionary = await _await_box(box)
	_expect_equal(str(result.get("code", "")), "token_timeout",
		"token-frames: elapsed expiry terminates the wait")
	_expect_equal(host.supply_token(), "fake-id-token",
		"token-frames: expiry serves no new token, cached one kept")
	await _free_parts(parts)
	# A genuine token answer just before the deadline still wins.
	_wipe_all()
	clock = FakeClock.new()
	parts = _make_parts(null, {"clock": clock})
	host = parts["host"]
	fake = parts["fake"]
	host.startup()
	await _sign_in_cloud(parts, UID_A, CANON_C)
	await _frames(20)
	fake.token_receipt = {"status": "pending"}
	box = _launch_token(host)
	await _frames(3)
	clock.advance(14900)
	await _frames(2)
	_expect_false(box.has("result"),
		"token-near: 100ms shy of the deadline is still pending")
	fake.complete_session(_pending_request_id(fake),
		{"id_token": "near-deadline-token",
			"token_expires_at": 4102444800000})
	result = await _await_box(box)
	_expect_equal(str(result.get("status", "")), "ok",
		"token-near: timely genuine token succeeds")
	_expect_equal(host.supply_token(), "near-deadline-token",
		"token-near: timely token served")
	await _free_parts(parts)


func _test_delete_local_guest_sends_no_cloud() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts(FAKE_ADAPTER_SCRIPT)
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_write_checkpoint({"cycle": 1, "journey_id": "local-gone-j-1"})
	var result: Dictionary = await host.delete_current_account()
	_expect_equal(str(result.get("status", "")), "ok",
		"delete-local: local guest deletion succeeds")
	_expect_true((sender.calls as Array).is_empty(),
		"delete-local: no cloud request sent")
	_expect_false((fake.calls as Array).has("delete_account"),
		"delete-local: no native call with nothing to delete")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(guest)),
		"delete-local: own slot removed")
	_expect_true(str((host.account_state() as Dictionary).get(
		"public_id", "")) != guest,
		"delete-local: fresh guest minted")
	await _free_parts(parts)


func _test_delete_panel_flow() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts(FAKE_ADAPTER_SCRIPT)
	var host: Node = parts["host"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_write_checkpoint({"cycle": 1, "journey_id": "panel-j-1"})
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	(entry.get_node("Gate") as GateEntry).account_requested.emit()
	await _frames(2)
	var panel: GateAccountPanel = (entry.get_node("Gate") as GateEntry
		).get_node("GateAccountPanel") as GateAccountPanel
	var delete_button: Button = panel.get_node_or_null(
		"Card/Stack/Scroll/ScrollBox/AccountActions/DeleteAccount") as Button
	var confirm_button: Button = panel.get_node_or_null(
		"Card/Stack/Scroll/ScrollBox/DeleteConfirm/DeleteNow") as Button
	_expect_true(delete_button != null and confirm_button != null,
		"delete-panel: scrolled delete doors present")
	if delete_button == null or confirm_button == null:
		entry.queue_free()
		await _free_parts(parts)
		return
	delete_button.pressed.emit()
	await _frames(2)
	confirm_button.pressed.emit()
	for _index in 120:
		await _frames(2)
		if str((host.account_state() as Dictionary).get(
				"public_id", "")) != guest:
			break
	_expect_true(str((host.account_state() as Dictionary).get(
		"public_id", "")) != guest,
		"delete-panel: two-tap confirm deletes and rotates")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(guest)),
		"delete-panel: slot removed through the panel")
	entry.queue_free()
	await _free_parts(parts)


func _test_hall_ties_share_standing() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_write_checkpoint({"cycle": 3, "journey_id": "tie-j-1"})
	sender.queue_ok(_profile_body(UID_A, guest))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _await_ready(host)
	await _frames(20)
	sender.reset()
	sender.queue_ok(_board_body([
		[CANON_C, Vault.HEROES[0], 9000],
		[CANON_D, "warden", 7000],
		[guest, "dancer", 7000],
		[OTHER_ID, "keeper", 5000],
	]))
	var view: Dictionary = await host.request_hall()
	var rows: Array = view.get("rows", [])
	_expect_equal([int((rows[0] as Dictionary).get("rank", 0)),
		int((rows[1] as Dictionary).get("rank", 0)),
		int((rows[2] as Dictionary).get("rank", 0)),
		int((rows[3] as Dictionary).get("rank", 0))], [1, 2, 2, 4],
		"ties: equal scores share one competition standing")
	sender.reset()
	# Owned-best contract: our own row first, then the greater-count.
	# 7000 matches this guest's tied board row above.
	sender.queue_ok(_own_row_body(guest, 7000))
	sender.queue_ok(_rank_body(1))
	var hud: Control = HUD_SCENE.instantiate() as Control
	add_child(hud)
	await _frames(2)
	var rank: Label = hud.get_node("RightPanel/Row/Rank") as Label
	var own: Dictionary = await host.request_rank()
	_expect_equal(int(own.get("rank", 0)), 2,
		"ties: backend counts strictly greater scores plus one")
	_expect_equal(int(own.get("score", 0)), 7000,
		"ties: rank carries the owned best score")
	_expect_true(rank.text.begins_with("#2 · "),
		"ties: own-rank label agrees with the shared standing")
	hud.queue_free()
	await _free_parts(parts)


func _test_menus_open_close() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	_write_checkpoint({"cycle": 2, "journey_id": "menu-j-1"})
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	_expect_true(gate != null, "menus: gate surface present")
	await _tap(entry)
	gate.guest_requested.emit()
	await _frames(2)
	_expect_true(str((gate.get_node(
		"Content/StatusCard/Ready/IdRow/StableId") as LineEdit).text
		).begins_with("MB-"), "menus: durable id shown before play")
	gate.heroes_requested.emit()
	await _frames(2)
	_expect_true((entry.get_node("Title/Ui/Shrine") as Control).visible,
		"menus: heroes door opens the shrine")
	(entry.get_node("Title/Ui/Shrine") as Control).close()
	gate.settings_requested.emit()
	await _frames(2)
	_expect_true((entry.get_node("Title/Ui/Settings") as Control).visible,
		"menus: settings door opens settings")
	(entry.get_node("Title/Ui/Settings") as Control).close()
	gate.chronicle_requested.emit()
	await _frames(2)
	_expect_true((entry.get_node("Title/Ui/Chronicle") as Control).visible,
		"menus: chronicle door opens the chronicle")
	(entry.get_node("Title/Ui/Chronicle") as Control).close()
	gate.account_requested.emit()
	await _frames(2)
	var panel: GateAccountPanel = gate.get_node(
		"GateAccountPanel") as GateAccountPanel
	_expect_true(panel.visible, "menus: account door opens the account")
	var id_field: LineEdit = panel.get_node_or_null(
		"Card/Stack/Scroll/ScrollBox/StableId") as LineEdit
	_expect_true(id_field != null,
		"menus: scrolled account id field present")
	if id_field == null:
		entry.queue_free()
		await _free_parts(parts)
		return
	_expect_true(str(id_field.text).begins_with("MB-"),
		"menus: account shows the full id")
	entry.queue_free()
	await _free_parts(parts)


## The production title's own Rank door opens the real Hall: one
## board fetch, rows with hero, score and full ID, no game start, and
## Close/back restore the same title with the tap re-armed.
func _test_title_rank_opens_real_hall() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	sender.queue_ok(_profile_body(UID_A, guest))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _await_ready(host)
	await _frames(20)
	sender.reset()
	sender.queue_ok(_board_body([
		[CANON_C, Vault.HEROES[0], 9000],
		[CANON_D, "warden", 7000],
	]))
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	var title: Variant = entry.get_node("Title")
	_expect_true(gate.is_title_rest(), "rank: title holds the screen first")
	(title.get_node("Ui/Screen/LadderButton") as Button).pressed.emit()
	await _frames(15)
	_expect_equal((sender.calls as Array).size(), 1,
		"rank: one board fetch per press")
	var panel: GateHallPanel = gate.get_node("GateHallPanel") \
		as GateHallPanel
	_expect_true(panel.visible, "rank: real Hall opens over the title")
	_expect_true(not (title.get_node("Ui/Screen") as Control).visible,
		"rank: title doors parked under the Hall")
	_expect_equal(panel.row_count(), 2, "rank: two real rows mapped")
	var first: PanelContainer = panel.get_node(
		"Card/Stack/Rows/RowsBox/HallRow0") as PanelContainer
	_expect_true((first.get_node("Line/Middle/Headline") as Label).text \
		== "#1 · 9000", "rank: rank and score shown")
	_expect_true((first.get_node("Line/Middle/IdLine") as Label).text \
		== CANON_C, "rank: full unique id shown")
	_expect_true((first.get_node("Line/Portrait") as TextureRect).texture \
		!= null, "rank: real hero portrait shown")
	_expect_true(not gate.get_loader().is_loading(),
		"rank: no loading started")
	_expect_true(gate.is_title_rest(), "rank: no login card forced")
	_expect_true(ResourceLoader.load_threaded_get_status(
			"res://scenes/gameplay/arena.tscn") \
			== ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"rank: no arena load issued")
	(panel.get_node("Card/Stack/Close") as Button).pressed.emit()
	await _frames(2)
	_expect_true(not panel.visible, "rank: close shuts the Hall")
	_expect_true((title.get_node("Ui/Screen") as Control).visible,
		"rank: close restores the doors")
	_expect_true(bool(title.get("_accepting")),
		"rank: close re-arms the tap")
	_expect_true(gate.is_title_rest(),
		"rank: close returns to title rest")
	sender.reset()
	sender.queue_ok(_board_body([
		[CANON_C, Vault.HEROES[0], 9000],
	]))
	(title.get_node("Ui/Screen/LadderButton") as Button).pressed.emit()
	await _frames(15)
	_expect_true(panel.visible, "rank: door reopens the Hall")
	entry._on_back()
	await _frames(2)
	_expect_true(not panel.visible, "rank: back shuts the Hall")
	_expect_true((title.get_node("Ui/Screen") as Control).visible,
		"rank: back restores the doors")
	_expect_true(bool(title.get("_accepting")),
		"rank: back re-arms the tap")
	entry.queue_free()
	await _free_parts(parts)


func _test_back_cancel_unwind() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	_write_checkpoint({"cycle": 1, "journey_id": "back-j-1"})
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	gate.heroes_requested.emit()
	await _frames(2)
	entry._on_back()
	_expect_false((entry.get_node("Title/Ui/Shrine") as Control).visible,
		"back: shrine closes first")
	# Fresh over a save asks; back dismisses the question, save intact.
	gate.start_requested.emit()
	await _frames(2)
	var confirm: PanelContainer = entry.get_node(
		"FreshConfirm") as PanelContainer
	_expect_true(confirm.visible, "back: fresh asks for confirmation")
	entry._on_back()
	_expect_false(confirm.visible, "back: confirm dismissed")
	_expect_true(bool((host.saved_gate_summary() as Dictionary).get(
		"has_save", false)), "back: save kept after dismiss")
	entry.queue_free()
	await _free_parts(parts)


func _test_loader_generation_safety() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	_write_checkpoint({"cycle": 1, "journey_id": "gen-j-1"})
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	var loader: GateLoadingOverlay = gate.get_loader()
	var finished: Array = []
	gate.loading_finished.connect(
		func(path: String, _packed: PackedScene, token: int) -> void:
			finished.append([path, token]))
	host.plan_entry(false, true)
	# Two tiny real scenes: bogus paths would log engine errors, and the
	# regression runner fails any run that prints ERROR.
	var first_token: int = gate.load_scene(
		"res://scenes/ui/gate_exit_panel.tscn", "stage")
	gate.cancel_loading()
	var second_token: int = gate.load_scene(
		"res://scenes/ui/gate_loading_overlay.tscn", "stage")
	_expect_true(first_token != second_token,
		"generation: superseded load takes a new token")
	_expect_equal(loader.current_token(), second_token,
		"generation: loader tracks the live token")
	for _index in 30:
		await _frames(2)
		if not loader.is_loading():
			break
	for hit in finished:
		_expect_true(int((hit as Array)[1]) != first_token,
			"generation: stale token never finishes")
	# The entry also refuses a stale completion directly.
	entry._on_loading_finished("res://scenes/ui/gate_exit_panel.tscn",
		null, first_token)
	_expect_false(entry.get("_swapping"),
		"generation: stale finish swaps nothing")
	entry.queue_free()
	await _free_parts(parts)


func _test_hud_source_labels() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	var hud: Control = HUD_SCENE.instantiate() as Control
	add_child(hud)
	await _frames(2)
	var rank: Label = hud.get_node("RightPanel/Row/Rank") as Label
	_expect_false(rank.visible, "hud: no rank shown while unranked")
	host._push_rank_to_hud()
	_expect_false(rank.visible, "hud: host push keeps it hidden")
	hud.set_cloud_rank("#7 · live")
	_expect_true(rank.visible and rank.text == "#7 · live",
		"hud: live rank readable")
	hud.clear_cloud_rank()
	_expect_false(rank.visible, "hud: clear hides the chip")
	_expect_equal(host._rank_source_label("live"),
		GateEntryStrings.text("gate.rank.live"),
		"hud: live label localized")
	_expect_equal(host._rank_source_label("cache-throttled"),
		GateEntryStrings.text("gate.rank.cached"),
		"hud: throttled reads as cached")
	hud.queue_free()
	await _free_parts(parts)


func _test_hall_rows_mapped_real() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	sender.queue_ok(_profile_body(UID_A, guest))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _await_ready(host)
	await _frames(20)
	sender.reset()
	sender.queue_ok(_board_body([
		[CANON_C, Vault.HEROES[0], 9000],
		[CANON_D, "warden", 7000],
	]))
	var view: Dictionary = await host.request_hall()
	var rows: Array = view.get("rows", [])
	_expect_equal(rows.size(), 2, "hall: two real rows mapped")
	_expect_equal(int((rows[0] as Dictionary).get("rank", 0)), 1,
		"hall: ranks assigned in order")
	_expect_equal(str((rows[0] as Dictionary).get("id", "")), CANON_C,
		"hall: full unique ids shown")
	_expect_true((rows[0] as Dictionary).get("hero") is Hero,
		"hall: real hero resource by path")
	_expect_true((rows[1] as Dictionary).get("hero") is Hero,
		"hall: real hero resource by short id")
	_expect_equal(int((rows[1] as Dictionary).get("score", 0)), 7000,
		"hall: actual scores shown")
	await _free_parts(parts)
	# A fresh host against an empty board seeds nothing.
	_wipe_all()
	var bare: Dictionary = _make_parts()
	var host_b: Node = bare["host"]
	var fake_b: Node = bare["fake"]
	var sender_b: RefCounted = bare["sender"]
	host_b.startup()
	var guest_b: String = str((host_b.account_state() as Dictionary).get(
		"public_id", ""))
	sender_b.queue_ok(_profile_body(UID_A, guest_b))
	fake_b.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host_b.begin_guest()
	await _await_ready(host_b)
	await _frames(20)
	sender_b.reset()
	sender_b.queue_ok("[]")
	var empty: Dictionary = await host_b.request_hall()
	_expect_true((empty.get("rows", []) as Array).is_empty(),
		"hall: empty board seeds nothing")
	await _free_parts(bare)


func _test_live_rank_reaches_hud() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_write_checkpoint({"cycle": 3, "journey_id": "rank-j-1"})
	sender.queue_ok(_profile_body(UID_A, guest))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _settle_call(host, "account_state", guest)
	await _frames(20)
	var hud: Control = HUD_SCENE.instantiate() as Control
	add_child(hud)
	await _frames(2)
	var rank: Label = hud.get_node("RightPanel/Row/Rank") as Label
	sender.reset()
	# Owned-best contract: our own row first, then the greater-count.
	# The count reply stays scripted; the row carries our real shape.
	sender.queue_ok(_own_row_body(guest, 5000))
	sender.queue_ok(_rank_body(1))
	var view: Dictionary = await host.request_rank()
	_expect_equal(int(view.get("rank", 0)), 2,
		"rank: server count plus one")
	_expect_equal(int(view.get("score", 0)), 5000,
		"rank: rank carries the owned best score")
	_expect_true(rank.visible and rank.text.begins_with("#2 · "),
		"rank: hud shows the live rank")
	hud.queue_free()
	await _free_parts(parts)


func _test_no_token_in_state() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.token_receipt = {"status": "ok", "id_token": SECRET_TOKEN,
		"token_expires_at": 4102444800000}
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _settle_call(host, "account_state", CANON_C)
	var flattened: String = JSON.stringify(host.account_state()) \
		+ JSON.stringify(host.debug_production_state())
	_expect_true(not flattened.contains(SECRET_TOKEN),
		"leak: no token in state or debug")
	_expect_true(not flattened.contains("id_token"),
		"leak: no token key in state or debug")
	_expect_false((host.debug_production_state() as Dictionary).has(
		"cloud_uid"), "leak: debug carries no uid")
	await _free_parts(parts)


func _test_first_paint_noted() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	host.startup()
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	var debug: Dictionary = host.debug_production_state()
	_expect_true(int(debug.get("first_paint_msec", 0)) > 0,
		"paint: first paint measured")
	_expect_true(int(debug.get("first_paint_msec", 0)) \
		>= int(debug.get("boot_msec", 0)), "paint: paint after boot")
	_expect_true(bool(debug.get("started", false)),
		"paint: host started")
	entry.queue_free()
	await _free_parts(parts)


## New-device cloud sign-in with a delayed remote checkpoint: the tap
## before the pull resolves plans nothing. Fresh and resume are both
## refused with the honest pending code, the Journey never arms, and only
## the installed remote unlocks Continue.
func _test_restore_blocks_fresh_until_remote_read() -> void:
	_wipe_all()
	var routed: RoutedSender = RoutedSender.new()
	routed.delay_frames = 10
	routed.tree_node = self
	var parts: Dictionary = _make_parts_with_sender(routed)
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	routed.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	routed.queue_checkpoint_ok(_remote_body(UID_A, 3, JSON.stringify(
		_valid_checkpoint("remote-j-7", 9, 0, {"cycle": 7})),
		"2026-10-02T00:00:00Z"))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var pending: bool = await _await_restore_pending(host)
	_expect_true(pending, "restore-block: empty slot owns the check")
	# Settled handle: restore tests judge the restore gate, not the lodge.
	Vault.cache_verified_name(CANON_C, "Luna", "luna", true)
	var refused: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(refused.get("code", "")), "cloud_restore_pending",
		"restore-block: fresh refused while checking")
	_expect_false(Journey.armed, "restore-block: journey never armed")
	_expect_true(Journey.pending != Journey.Pending.FRESH,
		"restore-block: fresh never pends")
	var refused_resume: Dictionary = host.plan_entry(false, true)
	_expect_equal(str(refused_resume.get("code", "")),
		"cloud_restore_pending",
		"restore-block: resume refused while checking, not no_save")
	await _settle_restore(host)
	_expect_true(bool((host.saved_gate_summary() as Dictionary).get(
		"has_save", false)), "restore-block: remote installs after read")
	var planned: Dictionary = host.plan_entry(false, true)
	_expect_equal(str(planned.get("status", "")), "ok",
		"restore-block: resume plans after install")
	_expect_equal(Journey.pending, Journey.Pending.RESUME,
		"restore-block: resume pends")
	await _await_sender_idle(routed)
	_clear_name_cache()
	await _free_parts(parts)


## While the check fetches, the card shows the checking face: busy with
## the save line, never the identity card. Cancelling parks to the title
## without issuing any login cancel; the tap afterwards shows the card
## once the remote has installed.
func _test_restore_pending_shows_save_check() -> void:
	_wipe_all()
	var routed: RoutedSender = RoutedSender.new()
	routed.delay_frames = 30
	routed.tree_node = self
	var parts: Dictionary = _make_parts_with_sender(routed)
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	routed.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	routed.queue_checkpoint_ok(_remote_body(UID_A, 3, JSON.stringify(
		_valid_checkpoint("remote-j-8", 2, 0, {"cycle": 6})),
		"2026-10-02T00:00:00Z"))
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	await _tap(entry)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var pending: bool = await _await_restore_pending(host)
	_expect_true(pending, "restore-check: check owns the empty slot")
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "restore-check: checking shows busy")
	_expect_equal((gate.get_node("Content/StatusCard/Busy/Working"
		) as Label).text, "gate.save.checking",
		"restore-check: working line names the save check")
	_expect_false((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "restore-check: no identity card before the read")
	(gate.get_node("Content/StatusCard/Busy/CancelLogin"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_false((gate.get_node("Content/StatusCard") as Control).visible,
		"restore-check: cancel parks the card")
	_expect_true((fake.cancelled_ids as Array).is_empty(),
		"restore-check: cancel issues no login cancel")
	await _settle_restore(host)
	await _tap(entry)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "restore-check: tap after install shows the card")
	entry.queue_free()
	await _await_sender_idle(routed)
	await _free_parts(parts)


## After a valid remote restore, Continue resumes the remote
## cycle, zone, hero, and checkpoint id on the real entry card.
func _test_restore_installs_remote_continue() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	var remote_payload: String = JSON.stringify(_valid_checkpoint(
		"remote-j-9", 11, 0, {"cycle": 7, "zone_index": 2,
			"hero_path": Vault.HEROES[3]}))
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_ok(_remote_body(UID_A, 3, remote_payload,
		"2026-10-02T00:00:00Z"))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _settle_restore(host)
	var summary: Dictionary = host.saved_gate_summary()
	_expect_true(bool(summary.get("has_save", false)),
		"restore-install: remote installs into the empty slot")
	_expect_equal(int(summary.get("cycle", 0)), 7,
		"restore-install: Continue resumes the remote cycle")
	_expect_equal(int(summary.get("zone_index", -1)), 2,
		"restore-install: Continue resumes the remote zone")
	_expect_equal(str(summary.get("hero_path", "")), Vault.HEROES[3],
		"restore-install: Continue resumes the remote hero")
	_expect_equal(str(summary.get("journey_id", "")), "remote-j-9",
		"restore-install: Continue resumes the remote checkpoint")
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	await _tap(entry)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "restore-install: installed save shows the card")
	_expect_true((gate.get_node("Content/StatusCard/Ready/StartRow/Resume"
		) as Button).visible, "restore-install: Continue offered")
	entry.queue_free()
	await _free_parts(parts)


## Authoritative not-found unlocks a fresh start with no error: the card
## shows Start and no Continue, and the Journey arms fresh.
func _test_restore_not_found_unlocks_fresh() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var settled: Dictionary = await _settle_restore(host)
	_expect_false(bool(settled.get("restore_pending", true)),
		"restore-404: check settles")
	_expect_false(bool(settled.get("restore_failed", true)),
		"restore-404: authoritative empty is not a failure")
	_expect_true((_fired["error"] as Array).is_empty(),
		"restore-404: no error on clean empty")
	# Settled handle: restore tests judge the restore gate, not the lodge.
	Vault.cache_verified_name(CANON_C, "Luna", "luna", true)
	var planned: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(planned.get("status", "")), "ok",
		"restore-404: fresh unlocks after not-found")
	_expect_equal(Journey.pending, Journey.Pending.FRESH,
		"restore-404: fresh pends")
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	await _tap(entry)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "restore-404: card shows after not-found")
	_expect_false((gate.get_node("Content/StatusCard/Ready/StartRow/Resume"
		) as Button).visible, "restore-404: no Continue without a save")
	entry.queue_free()
	_clear_name_cache()
	await _free_parts(parts)


## A failed fetch is never proof of no save: the entry stays refused
## with the honest unresolved code, the card shows the save error with
## its offline door, and retry re-checks without signing anything in. A
## double retry fires exactly one pull.
func _test_restore_offline_failure_and_retry() -> void:
	_wipe_all()
	var routed: RoutedSender = RoutedSender.new()
	routed.delay_frames = 10
	routed.tree_node = self
	var parts: Dictionary = _make_parts_with_sender(routed)
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	routed.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	routed.queue_checkpoint_reply(
		{"transport": "offline", "code": 0, "body": ""})
	routed.queue_checkpoint_reply(
		{"transport": "offline", "code": 0, "body": ""})
	routed.queue_checkpoint_not_found()
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	await _tap(entry)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	host.begin_guest()
	var started: bool = await _await_restore_pending(host)
	_expect_true(started, "restore-offline: check starts over the delay")
	var failed: Dictionary = await _settle_restore(host)
	_expect_true(bool(failed.get("restore_failed", false)),
		"restore-offline: failed fetch blocks, never unlocks")
	_expect_equal(str(failed.get("restore_code", "")), "offline",
		"restore-offline: reason names offline")
	var refused: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(refused.get("code", "")), "cloud_restore_unresolved",
		"restore-offline: fresh refused while unresolved")
	_expect_false(Journey.armed, "restore-offline: nothing armed")
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "restore-offline: failure shows the save error")
	_expect_equal((gate.get_node("Content/StatusCard/Error/ErrorTitle"
		) as Label).text, "gate.save.check_offline",
		"restore-offline: offline headline names offline")
	_expect_equal(str((gate.get_node(
		"Content/StatusCard/Error/ErrorDetail") as Label).text),
		GateEntryStrings.text("gate.save.offline_body"),
		"restore-offline: body explains the offline start")
	_expect_equal((gate.get_node(
		"Content/StatusCard/Error/ErrorRow/ErrorGuest"
		) as Button).text, "gate.save.play_offline",
		"restore-offline: escape offers the offline start")
	var codes: Array = []
	for err in (_fired["error"] as Array):
		codes.append(str((err as Dictionary).get("code", "")))
	_expect_true(codes.has("save_check_failed"),
		"restore-offline: honest error emitted")
	# Retry from the card re-checks; a second failure keeps blocking.
	(gate.get_node("Content/StatusCard/Error/ErrorRow/RetryLogin"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "restore-offline: retry shows checking")
	var failed_again: Dictionary = await _settle_restore(host)
	_expect_true(bool(failed_again.get("restore_failed", false)),
		"restore-offline: second failure still blocks")
	# A double retry fires one pull: the second is refused in flight.
	host.retry_cloud_restore()
	var dup: Dictionary = await host.retry_cloud_restore()
	_expect_equal(str(dup.get("code", "")), "restore_in_flight",
		"restore-offline: parallel retry refused")
	await _settle_restore(host)
	_expect_equal(_checkpoint_calls(routed).size(), 3,
		"restore-offline: one pull per attempt, never parallel")
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "restore-offline: not-found after retry shows the card")
	_expect_false((fake.calls as Array).has("sign_in_provider"),
		"restore-offline: retry signs nothing in")
	_expect_false((fake.calls as Array).has("link_provider"),
		"restore-offline: retry relinks nothing")
	entry.queue_free()
	await _await_sender_idle(routed)
	await _free_parts(parts)


## The explicit offline decision after a failed check: the card shows with
## an honest unchecked-save line, fresh unlocks under the same cloud
## account, and a later retry still re-checks.
func _test_restore_explicit_offline() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "offline", "code": 0, "body": ""})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	await _tap(entry)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	host.begin_guest()
	await _settle_restore(host)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "restore-decide: failure shows first")
	(gate.get_node("Content/StatusCard/Error/ErrorRow/ErrorGuest"
		) as Button).pressed.emit()
	await _frames(2)
	var decided: Dictionary = host.account_state()
	_expect_true(bool(decided.get("restore_offline", false)),
		"restore-decide: offline decision recorded")
	_expect_equal(str(decided.get("cloud_uid", "")), UID_A,
		"restore-decide: account ownership retained")
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "restore-decide: offline shows the card")
	_expect_equal((gate.get_node(
		"Content/StatusCard/Ready/HeroRow/HeroText/SavedLine"
		) as Label).text,
		GateEntryStrings.text("gate.save.offline_unknown"),
		"restore-decide: card says the save is unchecked")
	# Settled handle: restore tests judge the restore gate, not the lodge.
	Vault.cache_verified_name(CANON_C, "Luna", "luna", true)
	var planned: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(planned.get("status", "")), "ok",
		"restore-decide: fresh unlocks after the decision")
	host.cancel_entry_plan()
	# Reversible: a retry re-checks the same account.
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var retried: Dictionary = await host.retry_cloud_restore()
	_expect_equal(str(retried.get("code", "")), "not-found",
		"restore-decide: retry re-checks after offline")
	var clean: Dictionary = host.account_state()
	_expect_false(bool(clean.get("restore_offline", true)),
		"restore-decide: decision clears on clean resolve")
	_expect_false(bool(clean.get("restore_failed", true)),
		"restore-decide: no failure after clean resolve")
	entry.queue_free()
	_clear_name_cache()
	await _free_parts(parts)


## Signing out mid-check retires the ticket: the late pull — a valid
## remote here — installs nowhere, unlocks nothing, and leaves the fresh
## guest planning cleanly.
func _test_restore_signout_retires_late_result() -> void:
	_wipe_all()
	var routed: RoutedSender = RoutedSender.new()
	routed.delay_frames = 10
	routed.tree_node = self
	var parts: Dictionary = _make_parts_with_sender(routed)
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	routed.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	routed.queue_checkpoint_ok(_remote_body(UID_A, 3, JSON.stringify(
		_valid_checkpoint("remote-j-stale", 4, 0, {"cycle": 5})),
		"2026-10-02T00:00:00Z"))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var sent: bool = await _await_checkpoint_sent(routed)
	_expect_true(sent, "restore-stale: check in flight before sign-out")
	var signed_out: Dictionary = host.sign_out()
	_expect_equal(str(signed_out.get("status", "")), "ok",
		"restore-stale: sign-out lands mid-check")
	var guest: String = str((host.account_state() as Dictionary).get(
		"public_id", ""))
	_expect_true(not guest.is_empty() and guest != CANON_C,
		"restore-stale: fresh guest owns the session")
	await _frames(30)
	_expect_equal(_checkpoint_calls(routed).size(), 1,
		"restore-stale: the late pull really landed")
	_expect_true(Journey.read_checkpoint().is_empty(),
		"restore-stale: late bytes never enter the new guest")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"restore-stale: retired account gains no file")
	var clean: Dictionary = host.account_state()
	_expect_false(bool(clean.get("restore_pending", true)),
		"restore-stale: no pending check after sign-out")
	_expect_false(bool(clean.get("restore_failed", true)),
		"restore-stale: no failure after sign-out")
	var planned: Dictionary = host.plan_entry(true, true)
	_expect_equal(str(planned.get("status", "")), "ok",
		"restore-stale: guest plans cleanly")
	await _await_sender_idle(routed)
	await _free_parts(parts)


## Switching accounts mid-check retires the old pull: A's late valid
## remote installs nowhere while B's own check resolves and unlocks B.
func _test_restore_switch_retires_late_result() -> void:
	_wipe_all()
	var routed: RoutedSender = RoutedSender.new()
	routed.delay_frames = 10
	routed.tree_node = self
	var parts: Dictionary = _make_parts_with_sender(routed)
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	routed.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	routed.queue_checkpoint_ok(_remote_body(UID_A, 3, JSON.stringify(
		_valid_checkpoint("remote-j-doomed", 4, 0, {"cycle": 5})),
		"2026-10-02T00:00:00Z"))
	routed.queue_profile(UID_B, _profile_body(UID_B, CANON_D))
	routed.queue_checkpoint_not_found()
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var sent: bool = await _await_checkpoint_sent(routed)
	_expect_true(sent, "restore-switch: A check in flight before switch")
	fake.provider_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_B, "provider": "play_games"}}
	var switched: Dictionary = host.switch_to_provider("play_games")
	_expect_equal(str(switched.get("status", "")), "ok",
		"restore-switch: switch lands mid-check")
	var settled: Dictionary = await _settle_call(
		host, "account_state", CANON_D)
	_expect_equal(str(settled.get("public_id", "")), CANON_D,
		"restore-switch: B owns the session")
	await _settle_restore(host)
	_expect_equal(_checkpoint_calls(routed).size(), 2,
		"restore-switch: one pull per account, A late and B live")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"restore-switch: A's late valid bytes install nowhere")
	_expect_true(Journey.read_checkpoint().is_empty(),
		"restore-switch: B slot honestly empty after not-found")
	# Settled handle: restore tests judge the restore gate, not the lodge.
	Vault.cache_verified_name(CANON_D, "Luna", "luna", true)
	var planned: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(planned.get("status", "")), "ok",
		"restore-switch: B plans fresh after its own resolve")
	await _await_sender_idle(routed)
	_clear_name_cache()
	await _free_parts(parts)


## Same-account duplicate ready callbacks restart nothing: after a
## clean resolve they send no new pull and keep the entry unlocked; while
## failed they send nothing and keep the failure for the explicit retry;
## while checking they never stack a second pull.
func _test_restore_duplicate_ready_restarts_nothing() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _settle_restore(host)
	var pulls: int = _checkpoint_calls(sender).size()
	_emit_duplicate_ready(host)
	await _frames(10)
	_expect_equal(_checkpoint_calls(sender).size(), pulls,
		"restore-dupe: resolved duplicate sends no pull")
	# Settled handle: restore tests judge the restore gate, not the lodge.
	Vault.cache_verified_name(CANON_C, "Luna", "luna", true)
	var planned: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(planned.get("status", "")), "ok",
		"restore-dupe: entry stays unlocked after duplicate")
	host.cancel_entry_plan()
	_clear_name_cache()
	await _free_parts(parts)
	# While failed, a duplicate neither re-checks nor clears the failure.
	_wipe_all()
	var failed_parts: Dictionary = _make_parts()
	var failed_host: Node = failed_parts["host"]
	var failed_fake: Node = failed_parts["fake"]
	var failed_sender: RefCounted = failed_parts["sender"]
	failed_host.startup()
	failed_sender.queue_ok(_profile_body(UID_A, CANON_C))
	failed_sender.queue_reply(
		{"transport": "offline", "code": 0, "body": ""})
	failed_fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	failed_host.begin_guest()
	await _settle_restore(failed_host)
	var failed_pulls: int = _checkpoint_calls(failed_sender).size()
	_emit_duplicate_ready(failed_host)
	await _frames(10)
	_expect_equal(_checkpoint_calls(failed_sender).size(), failed_pulls,
		"restore-dupe: failed duplicate sends no pull")
	_expect_true(bool((failed_host.account_state() as Dictionary).get(
		"restore_failed", false)),
		"restore-dupe: failure stands for the explicit retry")
	await _free_parts(failed_parts)
	# While checking, a duplicate never stacks a second pull.
	_wipe_all()
	var routed: RoutedSender = RoutedSender.new()
	routed.delay_frames = 10
	routed.tree_node = self
	var slow_parts: Dictionary = _make_parts_with_sender(routed)
	var slow_host: Node = slow_parts["host"]
	var slow_fake: Node = slow_parts["fake"]
	slow_host.startup()
	routed.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	routed.queue_checkpoint_not_found()
	slow_fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	slow_host.begin_guest()
	var pending: bool = await _await_restore_pending(slow_host)
	_expect_true(pending, "restore-dupe: check in flight for duplicate")
	_emit_duplicate_ready(slow_host)
	await _frames(3)
	_expect_equal(_checkpoint_calls(routed).size(), 1,
		"restore-dupe: checking duplicate stacks no pull")
	await _settle_restore(slow_host)
	await _await_sender_idle(routed)
	await _free_parts(slow_parts)


## A valid local checkpoint never waits on the cloud: sign-in adopts the
## slot without sending any checkpoint read, resume plans at once, and a
## local-only guest plays with the sender fully offline.
func _test_restore_local_resume_needs_no_cloud() -> void:
	_wipe_all()
	var parts: Dictionary = _make_parts()
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	var sender: RefCounted = parts["sender"]
	host.startup()
	_write_checkpoint({"cycle": 4, "journey_id": "local-j-9"})
	sender.queue_ok(_profile_body(UID_A, CANON_C))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	await _await_ready(host)
	await _frames(10)
	var state: Dictionary = host.account_state()
	_expect_false(bool(state.get("restore_pending", true)),
		"restore-local: no check pends over a local save")
	_expect_false(bool(state.get("restore_failed", true)),
		"restore-local: no failure over a local save")
	# The single pull is the upload's own guard read, never the initial
	# check: the check would have failed loudly on the default reply and
	# left restore_failed set with a save_check_failed error behind.
	_expect_equal(_checkpoint_calls(sender).size(), 1,
		"restore-local: one upload read, no check read")
	var codes: Array = []
	for err in (_fired["error"] as Array):
		codes.append(str((err as Dictionary).get("code", "")))
	_expect_false(codes.has("save_check_failed"),
		"restore-local: the check never ran over a local save")
	# Settled handle: restore tests judge the restore gate, not the lodge.
	Vault.cache_verified_name(CANON_C, "Luna", "luna", true)
	var planned: Dictionary = host.plan_entry(false, true)
	_expect_equal(str(planned.get("status", "")), "ok",
		"restore-local: resume plans at once")
	_expect_equal(Journey.pending, Journey.Pending.RESUME,
		"restore-local: resume pends")
	_expect_equal(int((host.saved_gate_summary() as Dictionary).get(
		"cycle", 0)), 4, "restore-local: local cycle intact")
	_clear_name_cache()
	await _free_parts(parts)
	# A local-only guest never checks at all, even fully offline.
	_wipe_all()
	var guest_parts: Dictionary = _make_parts()
	var guest_host: Node = guest_parts["host"]
	var guest_fake: Node = guest_parts["fake"]
	var guest_sender: RefCounted = guest_parts["sender"]
	guest_sender.default_reply = {"transport": "offline", "code": 0,
		"body": ""}
	guest_fake.guest_receipt = {"status": "error", "code": "network_error",
		"retryable": true}
	guest_host.startup()
	guest_host.begin_guest()
	await _frames(5)
	var guest_state: Dictionary = guest_host.account_state()
	_expect_false(bool(guest_state.get("restore_pending", true)),
		"restore-local: guest never pends a check")
	_expect_false(bool(guest_state.get("restore_failed", true)),
		"restore-local: guest never fails a check")
	var guest_planned: Dictionary = guest_host.plan_entry(true, true)
	_expect_equal(str(guest_planned.get("status", "")), "ok",
		"restore-local: guest plans fresh offline")
	await _free_parts(guest_parts)


## The check is bounded by elapsed time, not frames: a hung pull fails
## honestly on the injected clock, the timed-out attempt retires so the
## advertised retry proceeds while the orphan is still held, and the late
## valid reply installs nothing and changes nothing.
func _test_restore_timeout_is_bounded() -> void:
	_wipe_all()
	var hung: HungSender = HungSender.new()
	hung.tree_node = self
	var clock: FakeClock = FakeClock.new()
	var parts: Dictionary = _make_parts_with_sender(hung, {"clock": clock,
		"restore_timeout_seconds": 0.3})
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	hung.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var pending: bool = await _await_restore_pending(host)
	_expect_true(pending, "restore-timeout: check in flight on the hung pull")
	await _frames(5)
	_expect_true(bool((host.account_state() as Dictionary).get(
		"restore_pending", false)),
		"restore-timeout: frames alone never trip the wait")
	clock.advance(1000)
	var failed: Dictionary = await _settle_restore(host)
	_expect_true(bool(failed.get("restore_failed", false)),
		"restore-timeout: elapsed expiry fails honestly")
	_expect_equal(str(failed.get("restore_code", "")), "restore_timeout",
		"restore-timeout: reason names the timeout")
	# Settled handle: restore tests judge the restore gate, not the lodge.
	Vault.cache_verified_name(CANON_C, "Luna", "luna", true)
	var refused: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(refused.get("code", "")), "cloud_restore_unresolved",
		"restore-timeout: fresh refused while unresolved")
	# The retired attempt frees the doors: retry proceeds while the orphan
	# is still held, and a second tap is refused without a parallel pull.
	host.retry_cloud_restore()
	var dup: Dictionary = await host.retry_cloud_restore()
	_expect_equal(str(dup.get("code", "")), "restore_in_flight",
		"restore-timeout: parallel retry refused")
	_expect_true(bool((host.account_state() as Dictionary).get(
		"restore_pending", false)),
		"restore-timeout: retry proceeds while the orphan is held")
	# The old valid reply lands first: ignored, nothing installed.
	hung.release_checkpoint_call(1, {"transport": "ok", "code": 200,
		"body": _remote_body(UID_A, 3, JSON.stringify(
			_valid_checkpoint("remote-j-late", 6, 0, {"cycle": 8})),
			"2026-10-02T00:00:00Z")})
	await _frames(5)
	_expect_true(bool((host.account_state() as Dictionary).get(
		"restore_pending", false)),
		"restore-timeout: old reply changes nothing")
	_expect_true(Journey.read_checkpoint().is_empty(),
		"restore-timeout: old valid bytes never install")
	# The new reply resolves the live attempt.
	hung.release_checkpoint_call(2,
		{"transport": "ok", "code": 404, "body": "{}"})
	await _settle_restore(host)
	_expect_equal(_checkpoint_calls(hung).size(), 2,
		"restore-timeout: one pull per attempt, never parallel")
	var clean: Dictionary = host.account_state()
	_expect_false(bool(clean.get("restore_failed", true)),
		"restore-timeout: failure clears on the new resolve")
	var planned: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(planned.get("status", "")), "ok",
		"restore-timeout: fresh plans after the new resolve")
	_clear_name_cache()
	await _free_parts(parts)


## Claim ownership across generations on one live coordinator: the first
## pull is held, its attempt retires, and a newer generation claims and
## holds its own pull. When the retired valid reply lands it cannot free
## the newer claim — the counter never reuses an identity — installs
## nothing, and the newer read still settles for itself.
func _test_restore_claim_identity_never_reused() -> void:
	_wipe_all()
	var hung: HungSender = HungSender.new()
	hung.tree_node = self
	var parts: Dictionary = _make_parts_with_sender(hung)
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	hung.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var first_held: bool = await _await_restore_pending(host)
	_expect_true(first_held, "restore-claim: first check starts")
	var first_sent: bool = await _await_checkpoint_sent(hung)
	_expect_true(first_sent, "restore-claim: first pull held")
	host._retire_restore()
	_expect_true(bool(host._begin_initial_restore(CANON_C)),
		"restore-claim: newer generation claims on the live coordinator")
	var newer_sent: bool = await _await_checkpoint_sent(hung, 2)
	_expect_true(newer_sent, "restore-claim: newer pull held")
	var open_before: int = int(host.get("_restore_fetch_open"))
	_expect_true(open_before != 0, "restore-claim: newer claim open")
	# The retired valid reply lands: newer claim, bytes, and error
	# surface all untouched.
	hung.release_checkpoint_call(1, {"transport": "ok", "code": 200,
		"body": _remote_body(UID_A, 3, JSON.stringify(
			_valid_checkpoint("remote-j-retired", 4, 0, {"cycle": 5})),
			"2026-10-02T00:00:00Z")})
	await _frames(10)
	_expect_equal(int(host.get("_restore_fetch_open")), open_before,
		"restore-claim: retired completion frees no newer claim")
	_expect_true(bool((host.account_state() as Dictionary).get(
		"restore_pending", false)),
		"restore-claim: newer check still checking")
	_expect_true(Journey.read_checkpoint().is_empty(),
		"restore-claim: retired bytes never install")
	# The newer read settles for itself.
	hung.release_checkpoint_call(2,
		{"transport": "ok", "code": 404, "body": "{}"})
	await _settle_restore(host)
	# Settled handle: restore tests judge the restore gate, not the lodge.
	Vault.cache_verified_name(CANON_C, "Luna", "luna", true)
	var planned: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(planned.get("status", "")), "ok",
		"restore-claim: newer resolve unlocks fresh")
	_expect_equal(_checkpoint_calls(hung).size(), 2,
		"restore-claim: one pull per attempt")
	_clear_name_cache()
	await _free_parts(parts)


## The harmful cross-account ordering: A's pull is held, B switches in
## and B's own pull is held, and only then does A's late valid reply
## land. B's claim and deadline survive it — B's failure still shows the
## error card instead of sticking on checking forever — and A's bytes
## install nowhere.
func _test_restore_held_switch_keeps_new_claim() -> void:
	_wipe_all()
	var hung: HungSender = HungSender.new()
	hung.tree_node = self
	var parts: Dictionary = _make_parts_with_sender(hung)
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	hung.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	hung.queue_profile(UID_B, _profile_body(UID_B, CANON_D))
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	await _tap(entry)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var a_held: bool = await _await_restore_pending(host)
	_expect_true(a_held, "restore-held: A check starts")
	var a_sent: bool = await _await_checkpoint_sent(hung)
	_expect_true(a_sent, "restore-held: A pull held")
	fake.provider_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_B, "provider": "play_games"}}
	var switched: Dictionary = host.switch_to_provider("play_games")
	_expect_equal(str(switched.get("status", "")), "ok",
		"restore-held: switch lands mid-pull")
	var moved: Dictionary = await _settle_call(
		host, "account_state", CANON_D)
	_expect_equal(str(moved.get("public_id", "")), CANON_D,
		"restore-held: B owns the session")
	var b_held: bool = await _await_restore_pending(host)
	_expect_true(b_held, "restore-held: B check starts its own claim")
	var b_sent: bool = await _await_checkpoint_sent(hung, 2)
	_expect_true(b_sent, "restore-held: B pull held")
	_expect_equal(_checkpoint_calls(hung).size(), 2,
		"restore-held: both pulls outstanding")
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "restore-held: B check shows checking")
	# A's late valid reply lands after B claimed: B is untouched.
	hung.release_checkpoint_call(1, {"transport": "ok", "code": 200,
		"body": _remote_body(UID_A, 3, JSON.stringify(
			_valid_checkpoint("remote-j-held-a", 4, 0, {"cycle": 5})),
			"2026-10-02T00:00:00Z")})
	await _frames(10)
	_expect_true(bool((host.account_state() as Dictionary).get(
		"restore_pending", false)),
		"restore-held: B claim survives A's late reply")
	_expect_false(FileAccess.file_exists(
		Journey.account_main_path(CANON_C)),
		"restore-held: A late bytes install nowhere")
	# B's own failure lands as an honest error, never a stuck check.
	hung.release_checkpoint_call(2,
		{"transport": "offline", "code": 0, "body": ""})
	var failed: Dictionary = await _settle_restore(host)
	_expect_true(bool(failed.get("restore_failed", false)),
		"restore-held: B failure fails, not stuck")
	_expect_equal(str(failed.get("restore_code", "")), "offline",
		"restore-held: B reason is its own failure")
	_expect_equal(str(host.plan_entry(true, false).get("code", "")),
		"cloud_restore_unresolved",
		"restore-held: B entry refused unresolved")
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "restore-held: B failure shows the error card")
	_expect_equal((gate.get_node("Content/StatusCard/Error/ErrorTitle"
		) as Label).text, "gate.save.check_offline",
		"restore-held: B headline names offline")
	_expect_true(Journey.read_checkpoint().is_empty(),
		"restore-held: B slot stays empty")
	entry.queue_free()
	await _free_parts(parts)


## Returning to the same UID and public ID starts a newer generation: the
## old held pull belongs to the retired attempt, so when it lands it
## grants nothing to the new check, and the new read resolves for itself.
func _test_restore_relogin_starts_new_generation() -> void:
	_wipe_all()
	var hung: HungSender = HungSender.new()
	hung.tree_node = self
	var parts: Dictionary = _make_parts_with_sender(hung)
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	hung.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	await _tap(entry)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var first_held: bool = await _await_restore_pending(host)
	_expect_true(first_held, "restore-relogin: first check starts")
	var first_sent: bool = await _await_checkpoint_sent(hung)
	_expect_true(first_sent, "restore-relogin: first pull held")
	_expect_equal(str(host.sign_out().get("status", "")), "ok",
		"restore-relogin: sign-out retires the first attempt")
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	host.begin_guest()
	var newer_held: bool = await _await_restore_pending(host)
	_expect_true(newer_held, "restore-relogin: same UID starts a newer check")
	var newer_sent: bool = await _await_checkpoint_sent(hung, 2)
	_expect_true(newer_sent, "restore-relogin: newer pull held")
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "restore-relogin: newer check shows checking")
	# The retired valid reply lands: the newer generation is untouched.
	hung.release_checkpoint_call(1, {"transport": "ok", "code": 200,
		"body": _remote_body(UID_A, 3, JSON.stringify(
			_valid_checkpoint("remote-j-old", 4, 0, {"cycle": 5})),
			"2026-10-02T00:00:00Z")})
	await _frames(10)
	_expect_true(bool((host.account_state() as Dictionary).get(
		"restore_pending", false)),
		"restore-relogin: old reply grants nothing newer")
	_expect_true(Journey.read_checkpoint().is_empty(),
		"restore-relogin: old valid bytes never install")
	# The newer read resolves for itself.
	hung.release_checkpoint_call(2,
		{"transport": "ok", "code": 404, "body": "{}"})
	await _settle_restore(host)
	# Settled handle: restore tests judge the restore gate, not the lodge.
	Vault.cache_verified_name(CANON_C, "Luna", "luna", true)
	var planned: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(planned.get("status", "")), "ok",
		"restore-relogin: newer resolve unlocks fresh")
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "restore-relogin: newer resolve shows the card")
	entry.queue_free()
	_clear_name_cache()
	await _free_parts(parts)


## Timeout retires the attempt, so the explicit offline decision acts
## while the old read is still held: the card shows, fresh plans, and
## when the old valid reply lands it installs nothing and changes
## nothing — the offline journey stands.
func _test_restore_timeout_offline_before_orphan() -> void:
	_wipe_all()
	var hung: HungSender = HungSender.new()
	hung.tree_node = self
	var clock: FakeClock = FakeClock.new()
	var parts: Dictionary = _make_parts_with_sender(hung, {"clock": clock,
		"restore_timeout_seconds": 0.3})
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	hung.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	await _tap(entry)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	host.begin_guest()
	var pending: bool = await _await_restore_pending(host)
	_expect_true(pending, "restore-timed-offline: check in flight")
	var sent: bool = await _await_checkpoint_sent(hung)
	_expect_true(sent, "restore-timed-offline: pull held")
	clock.advance(1000)
	var failed: Dictionary = await _settle_restore(host)
	_expect_true(bool(failed.get("restore_failed", false)),
		"restore-timed-offline: timeout fails honestly")
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "restore-timed-offline: failure shows the error card")
	_expect_equal((gate.get_node("Content/StatusCard/Error/ErrorTitle"
		) as Label).text, "gate.save.check_failed",
		"restore-timed-offline: timeout keeps the generic headline")
	# The offline door acts while the orphan is still held.
	var decided: Dictionary = host.accept_offline_entry()
	_expect_equal(str(decided.get("status", "")), "ok",
		"restore-timed-offline: offline acts before the orphan returns")
	_expect_true(bool((host.account_state() as Dictionary).get(
		"restore_offline", false)),
		"restore-timed-offline: offline decision recorded")
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "restore-timed-offline: offline shows the card")
	# Settled handle: restore tests judge the restore gate, not the lodge.
	Vault.cache_verified_name(CANON_C, "Luna", "luna", true)
	var planned: Dictionary = host.plan_entry(true, false)
	_expect_equal(str(planned.get("status", "")), "ok",
		"restore-timed-offline: fresh plans while held")
	_expect_equal(Journey.pending, Journey.Pending.FRESH,
		"restore-timed-offline: fresh pends")
	# The old valid reply lands into the started journey: nothing.
	hung.release_checkpoint_call(1, {"transport": "ok", "code": 200,
		"body": _remote_body(UID_A, 3, JSON.stringify(
			_valid_checkpoint("remote-j-orphan", 6, 0, {"cycle": 8})),
			"2026-10-02T00:00:00Z")})
	await _frames(10)
	_expect_true(Journey.read_checkpoint().is_empty(),
		"restore-timed-offline: old valid bytes never install")
	_expect_true(bool((host.account_state() as Dictionary).get(
		"restore_offline", false)),
		"restore-timed-offline: offline stands after the orphan")
	_expect_equal(Journey.pending, Journey.Pending.FRESH,
		"restore-timed-offline: fresh plan intact")
	_expect_equal(_checkpoint_calls(hung).size(), 1,
		"restore-timed-offline: only the retired pull was sent")
	entry.queue_free()
	_clear_name_cache()
	await _free_parts(parts)


## Timeout retires the attempt, so retry supersedes the orphan: the old
## valid reply lands first and is ignored, the new failure shows the
## honest error again, and a second retry — one pull for repeated taps,
## at the host and on the card — resolves cleanly.
func _test_restore_timeout_retry_supersedes_orphan() -> void:
	_wipe_all()
	var hung: HungSender = HungSender.new()
	hung.tree_node = self
	var clock: FakeClock = FakeClock.new()
	var parts: Dictionary = _make_parts_with_sender(hung, {"clock": clock,
		"restore_timeout_seconds": 0.3})
	var host: Node = parts["host"]
	var fake: Node = parts["fake"]
	host.startup()
	hung.queue_profile(UID_A, _profile_body(UID_A, CANON_C))
	fake.guest_receipt = {"status": "ok", "session": {
		"kind": "cloud", "uid": UID_A, "provider": "anonymous"}}
	var entry: ProductionEntry = _make_entry(host)
	await _frames(3)
	await _tap(entry)
	var gate: GateEntry = entry.get_node("Gate") as GateEntry
	host.begin_guest()
	var pending: bool = await _await_restore_pending(host)
	_expect_true(pending, "restore-timed-retry: check in flight")
	var sent: bool = await _await_checkpoint_sent(hung)
	_expect_true(sent, "restore-timed-retry: pull held")
	clock.advance(1000)
	var failed: Dictionary = await _settle_restore(host)
	_expect_true(bool(failed.get("restore_failed", false)),
		"restore-timed-retry: timeout fails honestly")
	# Retry supersedes while the orphan is held; a second tap refuses.
	host.retry_cloud_restore()
	var dup: Dictionary = await host.retry_cloud_restore()
	_expect_equal(str(dup.get("code", "")), "restore_in_flight",
		"restore-timed-retry: parallel retry refused")
	var waiting: bool = await _await_checkpoint_sent(hung, 2)
	_expect_true(waiting, "restore-timed-retry: superseding pull sent")
	# Old valid reply first: ignored, nothing installed.
	hung.release_checkpoint_call(1, {"transport": "ok", "code": 200,
		"body": _remote_body(UID_A, 3, JSON.stringify(
			_valid_checkpoint("remote-j-orphan", 6, 0, {"cycle": 8})),
			"2026-10-02T00:00:00Z")})
	await _frames(10)
	_expect_true(bool((host.account_state() as Dictionary).get(
		"restore_pending", false)),
		"restore-timed-retry: old reply changes nothing")
	_expect_true(Journey.read_checkpoint().is_empty(),
		"restore-timed-retry: old valid bytes never install")
	# The new reply fails: the honest error shows again.
	hung.release_checkpoint_call(2,
		{"transport": "offline", "code": 0, "body": ""})
	var failed_again: Dictionary = await _settle_restore(host)
	_expect_true(bool(failed_again.get("restore_failed", false)),
		"restore-timed-retry: new failure fails honestly")
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Error") as Control
		).visible, "restore-timed-retry: new failure shows the error")
	# Repeated card taps make one active attempt and sign nothing in.
	var guest_calls: int = (fake.calls as Array).count("sign_in_guest")
	(gate.get_node("Content/StatusCard/Error/ErrorRow/RetryLogin"
		) as Button).pressed.emit()
	(gate.get_node("Content/StatusCard/Error/ErrorRow/RetryLogin"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true((gate.get_node("Content/StatusCard/Busy") as Control
		).visible, "restore-timed-retry: taps stay on checking")
	var third: bool = await _await_checkpoint_sent(hung, 3)
	_expect_true(third, "restore-timed-retry: one pull for two taps")
	await _frames(5)
	_expect_equal(_checkpoint_calls(hung).size(), 3,
		"restore-timed-retry: taps never stack pulls")
	_expect_equal((fake.calls as Array).count("sign_in_guest"),
		guest_calls, "restore-timed-retry: taps sign nothing in")
	_expect_false((fake.calls as Array).has("sign_in_provider"),
		"restore-timed-retry: taps relink nothing")
	hung.release_checkpoint_call(3,
		{"transport": "ok", "code": 404, "body": "{}"})
	await _settle_restore(host)
	_expect_true((gate.get_node("Content/StatusCard/Ready") as Control
		).visible, "restore-timed-retry: resolve shows the card")
	_expect_true(Journey.read_checkpoint().is_empty(),
		"restore-timed-retry: slot honestly empty after not-found")
	entry.queue_free()
	await _free_parts(parts)


func _write_checkpoint(extra: Dictionary) -> void:
	var checkpoint: Dictionary = _valid_checkpoint(
		str(extra.get("journey_id", "test-j-1")),
		int(extra.get("checkpoint_id", 1)),
		int(extra.get("shards_awarded", 0)), extra)
	var error: Error = Journey.write_checkpoint(checkpoint)
	_expect_equal(error, OK, "helper: checkpoint writes")


## Checkpoint id of one owner's journaled entry, flat or parked, or 0
## when the owner holds nothing. Reads without switching the scope.
func _txn_owner_cid(owner: String) -> int:
	if not (Vault.continue_txn as Dictionary).is_empty() \
			and str((Vault.continue_txn as Dictionary).get("owner", "")) \
				== owner:
		return int((Vault.continue_txn as Dictionary).get(
			"checkpoint_id", 0))
	var parked: Variant = (Vault.get("continue_txn_parked") as Dictionary
		).get(owner)
	if parked is Dictionary:
		return int((parked as Dictionary).get("checkpoint_id", 0))
	return 0


## Seal a defeat and journal its paid revive in one scope, through the
## real API. The caller owns the active account before and after.
func _seal_and_journal(owner: String, journey: String, seal_id: int,
		revive_id: int) -> void:
	Journey.use_account(owner)
	var alive: Dictionary = _valid_checkpoint(journey, seal_id, 0)
	_expect_equal(Journey.write_checkpoint(alive), OK,
		"helper: the alive seal writes")
	var sealed: Dictionary = alive.duplicate(true)
	sealed["ended"] = true
	_expect_equal(Journey.write_checkpoint(sealed), OK,
		"helper: the defeat seals")
	var revive: Dictionary = _valid_checkpoint(journey, revive_id, 0)
	_expect_true(Vault.begin_continue_txn(journey, revive_id,
		JSON.stringify(revive)), "helper: the debit journals")


## Seal a legacy defeat's file pair without journaling. Split from the
## debit because the coordinator swap inside `_make_parts` settles any
## journal already pending in the active scope; legacy tests plant the
## files first, build parts, then journal just before the startup under
## test.
func _write_legacy_pair(journey: String, seal_id: int) -> void:
	Journey.use_account("")
	var alive: Dictionary = _valid_checkpoint(journey, seal_id, 0)
	_expect_equal(Journey.write_checkpoint(alive), OK,
		"helper: the legacy seal writes")
	var sealed: Dictionary = alive.duplicate(true)
	sealed["ended"] = true
	_expect_equal(Journey.write_checkpoint(sealed), OK,
		"helper: the legacy defeat seals")


## Journal one paid revive in the currently active scope, through the
## real API. The caller funds the coin first.
func _journal_revive(journey: String, revive_id: int) -> void:
	var revive: Dictionary = _valid_checkpoint(journey, revive_id, 0)
	_expect_true(Vault.begin_continue_txn(journey, revive_id,
		JSON.stringify(revive)), "helper: the debit journals")


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


func _profile_body(uid: String, public_id: String) -> String:
	return JSON.stringify({
		"fields": {
			"uid": {"stringValue": uid},
			"public_id": {"stringValue": public_id},
		},
	})


func _remote_body(uid: String, revision: int, payload: String,
		update_time: String) -> String:
	return JSON.stringify({
		"fields": {
			"uid": {"stringValue": uid},
			"revision": {"integerValue": str(revision)},
			"payload": {"stringValue": payload},
			"schema": {"integerValue": "1"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
		},
		"updateTime": update_time,
	})


func _board_body(rows: Array) -> String:
	var entries: Array = []
	for row in rows:
		var fields: Dictionary = {
			"public_id": {"stringValue": str((row as Array)[0])},
			"hero": {"stringValue": str((row as Array)[1])},
			"score": {"integerValue": str(int((row as Array)[2]))},
			"cycles": {"integerValue": "3"},
			"release": {"stringValue": "4.0.0"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
		}
		if (row as Array).size() > 3:
			fields["display"] = {"stringValue": str((row as Array)[3])}
		entries.append({"document": {"fields": fields}})
	return JSON.stringify(entries)


func _rank_body(greater: int) -> String:
	return JSON.stringify([{
		"result": {"aggregateFields": {
			"greater": {"integerValue": str(greater)},
		}},
	}])


## Scripted owned best row for the rank fixtures. The accepted Hall
## contract reads our own `mb_hall_v1` row before counting strictly
## greater scores, so every rank queue needs this GET ahead of the count.
func _own_row_body(public_id: String, score: int) -> String:
	return JSON.stringify({
		"name": "projects/moonlitbeacon-778ee/databases/(default)/documents/mb_hall_v1/%s"
			% public_id,
		"fields": {
			"public_id": {"stringValue": public_id},
			"hero": {"stringValue": Vault.HEROES[0]},
			"score": {"integerValue": str(score)},
			"cycles": {"integerValue": "3"},
			"release": {"stringValue": "4.0.0"},
			"schema": {"integerValue": "1"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
		},
	})


func _wipe_all() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		for path in [ID_PATH, BIND_PATH]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(
					path + suffix))
	for key in [CANON_C, CANON_D]:
		_wipe_slot(key)
	_wipe_legacy()
	_wipe_current_slot_files()
	Journey.use_account("")
	Journey.disarm()
	Journey.clear_stable_hooks()
	Journey.last_error = ""


func _wipe_current_slot_files() -> void:
	# Slots are keyed by minted ids; sweep every partitioned journey file.
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with("journey.") and file != "journey.json" \
				and file != "journey.json.bak":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(
				"user://" + file))


func _wipe_slot(key: String) -> void:
	for path in [Journey.account_main_path(key),
			Journey.account_backup_path(key),
			Journey.account_revision_path(key),
			Journey.account_rejected_path(key, "local"),
			Journey.account_rejected_path(key, "remote")]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path))


func _wipe_legacy() -> void:
	for path in [Journey.DEFAULT_PATH, Journey.DEFAULT_BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path))


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
