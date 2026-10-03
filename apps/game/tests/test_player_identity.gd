extends SceneTree

## Standalone player-identity regression: public ID durability, guest/cloud
## distinction, link conflict, cancellation, token handling, and leakage.
##
## Call directly; no other suite, scene, or autoload is needed:
## `pnpm godot:isolated --timeout 150 --script res://tests/test_player_identity.gd`
## The isolated runner builds a temp HOME and `MOONLIT_VAULT_TEST_ROOT`, so the
## identity files below never touch the developer's real save.

const ACCOUNT_SCRIPT: Script = preload("res://scripts/net/player_account.gd")
const ADAPTER_SCRIPT: Script = preload("res://scripts/net/identity_adapter.gd")
const NATIVE_ADAPTER_SCRIPT: Script = preload(
	"res://scripts/net/native_identity_adapter.gd")
const WRAPPER_SCRIPT: Script = preload(
	"res://addons/moonlit-identity/moonlit_identity.gd")
const FAKE_ADAPTER_SCRIPT: Script = preload(
	"res://tests/support/fake_identity_adapter.gd")
const FAKE_BRIDGE_SCRIPT: Script = preload(
	"res://tests/support/fake_identity_bridge.gd")
const COMPOSER_SCRIPT: Script = preload(
	"res://addons/moonlit-identity/extension_list_composer.gd")
const MANIFEST_HOOK_SCRIPT: Script = preload(
	"res://addons/moonlit-identity/android_manifest_hook.gd")
const IOS_MANIFEST_SCRIPT: Script = preload(
	"res://addons/moonlit-identity/ios_export_manifest.gd")
const SAVE_PATH: String = "user://player_identity.cfg"
const SECRET_TOKEN: String = "tok-secret-9f8e7d6c5b4a"
const SECRET_EMAIL: String = "player@example.test"

var _failed: int = 0
var _checked: int = 0


## Stand-in that models Android `JNISingleton` discovery: the GDScript
## methods exist (so `has_method` sees them), but the Java registry verdict
## comes from `has_java_method`. An oracle of false refuses dispatch even
## though the stand-in method is exposed.
class JavaOracleBridge extends "res://tests/support/fake_identity_bridge.gd":
	var java_methods: Dictionary = {}

	func has_java_method(method: String) -> bool:
		return bool(java_methods.get(method, false))


func _init() -> void:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	if expected_root.is_empty() or not user_root.begins_with(expected_root + "/"):
		printerr("identity test aborted: user:// path is not isolated — ",
			user_root)
		quit(2)
		return
	call_deferred("_run", user_root)


func _run(user_root: String) -> void:
	_remove_save_target()
	_test_public_id_format_and_uniqueness()
	_test_id_survives_restart()
	_test_backup_recovery()
	_test_corrupt_recovery()
	_test_temp_leftover_keeps_primary()
	_test_failed_write_is_not_ready_and_retries_same_id()
	_test_schema_and_length_guards()
	_test_offline_guest_by_default()
	await _test_cloud_claim_needs_server_uid()
	await _test_guest_sign_in_ok()
	await _test_link_conflict_keeps_guest()
	await _test_cancel_pending_link_keeps_guest()
	await _test_drain_keeps_lock_until_terminal()
	await _test_wrapper_drain_and_timeout_extension()
	_test_bookkeeping_stays_bounded()
	await _test_competing_mutation_blocked_until_native_settles()
	await _test_double_callback_settles_once()
	await _test_stale_callback_ignored()
	await _test_token_expiry_keeps_link_but_errors()
	await _test_revocation_returns_to_guest()
	await _test_token_reaches_caller_only()
	await _test_sign_out_and_delete_keep_public_id()
	_test_save_has_no_secrets_or_neighbors()
	_test_wrapper_unsupported_on_desktop()
	await _test_wrapper_not_configured_names_missing()
	await _test_ios_gate_needs_flag_not_service_id()
	await _test_wrapper_rejects_unknown_provider()
	await _test_wrapper_timeout_and_late_answer_dropped()
	await _test_wrapper_scrubs_secrets_from_signals()
	await _test_native_adapter_drops_stale_and_double()
	await _test_native_chain_async_success_settles_account()
	await _test_native_chain_late_completion_ignores_current_request()
	await _test_native_chain_sync_refresh_stays_id_free()
	await _test_provider_capabilities_gate_independently()
	await _test_google_sign_in_reaches_native_with_client_id()
	await _test_link_keeps_firebase_uid()
	await _test_google_link_conflict_keeps_guest()
	await _test_refresh_native_session_hydrates_after_restart()
	await _test_refresh_native_session_async_and_signed_out()
	_test_sign_out_failure_preserves_session()
	await _test_cancel_google_request_drains_like_any_provider()
	await _test_wrapper_java_registry_authority()
	await _test_wrapper_java_cancel_authority()
	_test_consent_window_policy_selects_per_method()
	await _test_consent_window_interactive_timeout_settles_and_drops_late()
	await _test_consent_window_ordinary_and_interactive_differ()
	await _test_consent_window_cancel_stays_immediate()
	await _test_consent_window_draining_retains_stored_policy()
	await _test_sync_refusal_settles_with_error()
	_test_extension_list_composition()
	_test_android_gate_needs_play_app_id()
	_test_manifest_hook_stamps_app_id()
	_test_ios_export_manifest_links_everything()
	_test_ios_static_entry_registration()
	_test_cpp_code_hook_fallback()
	_test_google_url_scheme_stamps_reversed_client_id()
	_test_plist_hook_fallback()
	_remove_save_target()
	if _failed > 0:
		printerr("identity test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("identity test passed — ", _checked, " case(s) · isolated path ",
		user_root)
	quit(0)


func _test_public_id_format_and_uniqueness() -> void:
	var seen: Dictionary = {}
	for i in 1000:
		var candidate: String = ACCOUNT_SCRIPT.generate_public_id()
		if not ACCOUNT_SCRIPT.is_valid_public_id(candidate):
			_expect_true(false, "generated id matches MB- + 32 hex")
			return
		if seen.has(candidate):
			_expect_true(false, "1000 generated ids are unique")
			return
		seen[candidate] = true
	_expect_true(true, "1000 generated ids match format and are unique")
	_expect_true(not ACCOUNT_SCRIPT.is_valid_public_id("MB-xyz"),
		"short id rejected")
	_expect_true(not ACCOUNT_SCRIPT.is_valid_public_id("player@example.test"),
		"email rejected as public id")
	_expect_true(not ACCOUNT_SCRIPT.is_valid_public_id("CoolNick"),
		"nickname rejected as public id")
	_expect_true(not ACCOUNT_SCRIPT.is_valid_public_id(""),
		"empty id rejected")


func _test_id_survives_restart() -> void:
	_remove_save_target()
	var first: Node = ACCOUNT_SCRIPT.new()
	var id_a: String = first.ensure_public_id()
	_expect_true(ACCOUNT_SCRIPT.is_valid_public_id(id_a),
		"first boot generates a valid id")
	_expect_true(FileAccess.file_exists(SAVE_PATH), "id file written")
	# A second instance is a restart: no shared memory, same file.
	var second: Node = ACCOUNT_SCRIPT.new()
	var id_b: String = second.ensure_public_id()
	_expect_equal(id_b, id_a, "public id survives restart")
	first.free()
	second.free()


func _test_backup_recovery() -> void:
	_remove_save_target()
	var account: Node = ACCOUNT_SCRIPT.new()
	var healthy: String = account.ensure_public_id()
	account.free()
	# Corrupt the primary; the backup written alongside it still holds the id.
	_write_text(SAVE_PATH, "not a config file {{{{{")
	var revived: Node = ACCOUNT_SCRIPT.new()
	_expect_equal(revived.ensure_public_id(), healthy,
		"backup restores the id when the primary is corrupt")
	_expect_true(not revived.recovered_from_corrupt(),
		"backup recovery is not reported as corrupt regeneration")
	_expect_equal(_read_id_from(SAVE_PATH), healthy,
		"primary rewritten from backup")
	revived.free()


func _test_corrupt_recovery() -> void:
	_remove_save_target()
	_write_text(SAVE_PATH, "garbage {{{{ not a config")
	_write_text(SAVE_PATH + ".bak", "more garbage }}}} not a config")

	var account: Node = ACCOUNT_SCRIPT.new()
	var fresh: String = account.ensure_public_id()
	_expect_true(ACCOUNT_SCRIPT.is_valid_public_id(fresh),
		"corrupt files regenerate a valid id")
	_expect_true(account.recovered_from_corrupt(),
		"corrupt regeneration is reported")
	account.free()


func _test_temp_leftover_keeps_primary() -> void:
	_remove_save_target()
	var account: Node = ACCOUNT_SCRIPT.new()
	var healthy: String = account.ensure_public_id()
	account.free()
	_write_text(SAVE_PATH + ".tmp", "half-written {{{{")
	var loaded: Node = ACCOUNT_SCRIPT.new()
	_expect_equal(loaded.ensure_public_id(), healthy,
		"leftover tmp file does not disturb the primary")
	loaded.free()


func _test_failed_write_is_not_ready_and_retries_same_id() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake, "user://no_such_dir_anywhere/player_identity.cfg")
	_expect_equal(account.ensure_public_id(), "",
		"failed write advertises no id")
	_expect_true(not account.is_identity_ready(),
		"failed write is not identity-ready")
	_expect_equal(account.public_id(), "",
		"unsaved id is not published as the public id")
	var pending: String = account.pending_public_id()
	_expect_true(ACCOUNT_SCRIPT.is_valid_public_id(pending),
		"failed write retains a valid pending id for retry")
	_expect_equal(account.sign_in_guest().get("code"), "identity_not_ready",
		"cloud calls refuse while identity is not ready")
	_expect_true(fake.calls.is_empty(),
		"refused calls never reach the adapter")
	# The disk heals: retry persists the same pending id, not a second mint.
	account.setup(fake, SAVE_PATH)
	_expect_true(account.retry_identity_save(), "retry saves")
	_expect_true(account.is_identity_ready(), "retry reaches ready")
	_expect_equal(account.public_id(), pending,
		"retry persists the same pending id")
	account.free()
	fake.free()
	# Across restart the broken path is still not ready: nothing durable
	# was ever written, so no ready state may be claimed.
	var rebooted: Node = ACCOUNT_SCRIPT.new()
	var rebooted_fake: Node = FAKE_ADAPTER_SCRIPT.new()
	rebooted.setup(rebooted_fake,
		"user://no_such_dir_anywhere/player_identity.cfg")
	_expect_equal(rebooted.ensure_public_id(), "",
		"restart with broken disk advertises no id")
	_expect_true(not rebooted.is_identity_ready(),
		"restart with broken disk is not ready")
	_free_all([rebooted, rebooted_fake])


func _test_schema_and_length_guards() -> void:
	_remove_save_target()
	var bad_schema: ConfigFile = ConfigFile.new()
	bad_schema.set_value("identity", "schema_version", 99)
	bad_schema.set_value("identity", "public_id",
		"MB-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	bad_schema.save(SAVE_PATH)
	var wrong_schema: Node = ACCOUNT_SCRIPT.new()
	var fresh: String = wrong_schema.ensure_public_id()
	_expect_true(ACCOUNT_SCRIPT.is_valid_public_id(fresh),
		"unknown schema regenerates a valid id")
	_expect_true(fresh != "MB-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"unknown schema does not adopt the unreadable id")
	_expect_true(wrong_schema.recovered_from_corrupt(),
		"unknown schema is reported as recovery")
	wrong_schema.free()
	_remove_save_target()
	_write_text(SAVE_PATH, "[identity]\npublic_id=\"MB-" + "b".repeat(9000)
		+ "\"\n")
	var oversized: Node = ACCOUNT_SCRIPT.new()
	_expect_true(ACCOUNT_SCRIPT.is_valid_public_id(
		oversized.ensure_public_id()),
		"oversized file regenerates a valid id")
	_expect_true(oversized.recovered_from_corrupt(),
		"oversized file is reported as recovery")
	oversized.free()


func _test_offline_guest_by_default() -> void:
	_remove_save_target()
	var account: Node = ACCOUNT_SCRIPT.new()
	var adapter: Node = ADAPTER_SCRIPT.new()
	account.setup(adapter)
	account.ensure_public_id()
	_expect_equal(account.account_kind(), "local_guest",
		"unsupported platform starts as a local guest")
	_expect_true(not account.is_cloud_linked(),
		"no cloud claim without an adapter session")
	_expect_equal(account.cloud_uid(), "", "no cloud uid offline")
	_expect_equal(account.refresh_session().get("kind"), "local_guest",
		"session reports local guest")
	_free_all([account, adapter])


func _test_cloud_claim_needs_server_uid() -> void:
	_remove_save_target()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInProvider"] = {"status": "pending"}
	var wrapper: Node = WRAPPER_SCRIPT.new()
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	var adapter: Node = NATIVE_ADAPTER_SCRIPT.new(wrapper)
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(adapter)
	account.ensure_public_id()
	var errors: Array = []
	account.account_error.connect(func(error: Dictionary) -> void:
		errors.append(error))
	var receipt: Dictionary = account.sign_in_provider("play_games")
	var request_id: String = str(receipt.get("request_id", ""))
	# A cloud session with an empty server UID is not a registration.
	bridge.emit_outcome({"status": "ok", "kind": "cloud", "uid": "",
		"provider": "play_games", "request_id": request_id})
	await process_frame
	_expect_true(not account.is_cloud_linked(),
		"cloud claim without server uid is rejected")
	_expect_equal(account.account_kind(), "local_guest",
		"account stays a local guest")
	_expect_equal(errors.size(), 1, "one error for the bad cloud claim")
	account.free()
	adapter.free()
	wrapper.free()
	bridge.free()


func _test_guest_sign_in_ok() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	var guest_id: String = account.ensure_public_id()
	var changed: Array = []
	account.account_changed.connect(func(state: Dictionary) -> void:
		changed.append(state))
	var receipt: Dictionary = account.sign_in_guest()
	_expect_equal(receipt.get("status"), "ok", "guest receipt ok")
	_expect_true(account.is_cloud_linked(), "guest sign-in links a server id")
	_expect_equal(account.cloud_uid(), "fake-anon-uid", "anonymous uid kept")
	_expect_equal(account.cloud_provider(), "anonymous",
		"anonymous provider named")
	_expect_equal(account.public_id(), guest_id,
		"public id unchanged by guest sign-in")
	_expect_true(changed.size() >= 1, "account change emitted")
	account.free()
	fake.free()


func _test_link_conflict_keeps_guest() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	fake.link_receipt = {"status": "conflict",
		"code": "already_linked_elsewhere", "provider": "play_games"}
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	var guest_id: String = account.ensure_public_id()
	account.sign_in_guest()
	var conflicts: Array = []
	account.account_conflict.connect(func(conflict: Dictionary) -> void:
		conflicts.append(conflict))
	var receipt: Dictionary = account.link_current_provider("play_games")
	_expect_equal(receipt.get("status"), "conflict", "link conflict receipt")
	_expect_equal(conflicts.size(), 1, "conflict signal needs a UI choice")
	_expect_equal(conflicts[0].get("provider"), "play_games",
		"conflict names the provider")
	_expect_equal(account.public_id(), guest_id,
		"conflict keeps the guest public id")
	_expect_equal(account.cloud_uid(), "fake-anon-uid",
		"conflict keeps the previous cloud binding")
	_expect_true(not conflicts[0].has("id_token"),
		"conflict carries no token")
	account.free()
	fake.free()


func _test_cancel_pending_link_keeps_guest() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	fake.link_receipt = {"status": "pending"}
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	var guest_id: String = account.ensure_public_id()
	account.sign_in_guest()
	var changed: Array = []
	account.account_changed.connect(func(state: Dictionary) -> void:
		changed.append(state))
	var errors: Array = []
	account.account_error.connect(func(error: Dictionary) -> void:
		errors.append(error))
	var receipt: Dictionary = account.link_current_provider("play_games")
	var request_id: String = str(receipt.get("request_id", ""))
	_expect_equal(receipt.get("status"), "pending", "link starts pending")
	_expect_equal(account.sign_out().get("code"), "request_already_pending",
		"sign-out waits while a request is pending")
	_expect_equal(account.delete_account().get("code"),
		"request_already_pending", "delete waits while a request is pending")
	var cancel: Dictionary = account.cancel_pending()
	_expect_equal(cancel.get("status"), "cancelled", "cancel settles")
	_expect_true(errors.is_empty(), "cancel is not an error")
	_expect_equal(account.public_id(), guest_id,
		"cancelled link keeps the guest id")
	_expect_equal(account.cloud_uid(), "fake-anon-uid",
		"cancelled link keeps the previous binding")
	var changes_before_late: int = changed.size()
	# The native answer arrives after the cancel: it must be dropped.
	fake.complete_session(request_id,
		{"status": "ok", "kind": "cloud", "uid": "late-uid",
			"provider": "play_games"})
	await process_frame
	_expect_equal(changed.size(), changes_before_late,
		"late answer after cancel is dropped")
	_expect_equal(account.cloud_uid(), "fake-anon-uid",
		"late answer does not move the binding")
	account.free()
	fake.free()


func _test_drain_keeps_lock_until_terminal() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	fake.link_receipt = {"status": "pending"}
	fake.cancel_status = "draining"
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	var guest_id: String = account.ensure_public_id()
	account.sign_in_guest()
	var receipt: Dictionary = account.link_current_provider("play_games")
	var request_id: String = str(receipt.get("request_id", ""))
	# The mutation already began natively: cancel reports draining, keeps
	# the lock, and must not publish a fake cancelled success.
	var drain: Dictionary = account.cancel_pending()
	_expect_equal(drain.get("status"), "draining",
		"cancel during mutation reports draining")
	_expect_true(bool(account.pending_request().get("pending", false)),
		"draining keeps the operation lock")
	_expect_equal(account.link_current_provider("play_games").get("code"),
		"request_already_pending",
		"no second sign-in races the draining mutation")
	# The terminal truth still lands and ends the lock.
	fake.complete_session(request_id,
		{"status": "ok", "kind": "cloud", "uid": "drained-uid",
			"provider": "play_games"})
	await process_frame
	_expect_equal(account.cloud_uid(), "drained-uid",
		"drained mutation publishes its real outcome")
	_expect_equal(account.public_id(), guest_id,
		"drained mutation keeps the guest id")
	_expect_equal(account.cancel_pending().get("code"), "no_pending_request",
		"lock released after the drained terminal")
	_free_all([account, fake])


func _test_wrapper_drain_and_timeout_extension() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	root.add_child(wrapper)
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	bridge.cancel_answer = {"status": "draining"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	wrapper.set_request_timeout_seconds(0.5)
	var outcomes: Array = []
	wrapper.request_completed.connect(func(outcome: Dictionary) -> void:
		outcomes.append(outcome))
	var receipt: Dictionary = wrapper.sign_in_guest()
	var request_id: String = str(receipt.get("request_id", ""))
	var drain: Dictionary = wrapper.cancel_request(request_id)
	_expect_equal(drain.get("status"), "draining",
		"wrapper cancel during mutation reports draining")
	_expect_equal(wrapper.pending_request_ids(), [request_id],
		"wrapper keeps the pending lock while draining")
	bridge.emit_outcome({"status": "ok", "kind": "cloud", "uid": "w-1",
		"provider": "anonymous", "request_id": request_id})
	await process_frame
	_expect_equal(outcomes.size(), 1, "drained outcome lands")
	_expect_equal(wrapper.pending_request_ids(), [],
		"drained terminal releases the lock")
	# Draining past every window still ends the request, truthfully late.
	var hung: Dictionary = wrapper.sign_in_guest()
	var hung_id: String = str(hung.get("request_id", ""))
	await _wait_for(outcomes, 2, 6.0)
	_expect_equal(outcomes.size(), 2, "drained timeout settles eventually")
	_expect_equal(outcomes[1].get("code"), "request_timeout",
		"drained timeout keeps its code")
	bridge.emit_outcome({"status": "ok", "kind": "cloud", "uid": "late",
		"provider": "anonymous", "request_id": hung_id})
	await process_frame
	await process_frame
	_expect_equal(outcomes.size(), 2, "post-timeout answer dropped")
	root.remove_child(wrapper)
	_free_all([wrapper, bridge])


func _test_bookkeeping_stays_bounded() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	bridge.receipts["moonlitGetSession"] = {"status": "ok",
		"kind": "local_guest", "uid": "", "provider": ""}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	for i in 200:
		wrapper.get_session()
	_expect_equal(wrapper.settled_request_count(), 0,
		"sync session reads record no bookkeeping")
	for i in 200:
		var receipt: Dictionary = wrapper.sign_in_guest()
		wrapper.cancel_request(str(receipt.get("request_id", "")))
	_expect_true(wrapper.settled_request_count() <= 64,
		"settled ids stay capped under cancel stress")
	_expect_equal(wrapper.pending_request_ids(), [],
		"no pending entries survive cancel stress")
	_free_all([wrapper, bridge])


func _test_competing_mutation_blocked_until_native_settles() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	root.add_child(wrapper)
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.enforce_mutation_lock = true
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	bridge.receipts["moonlitLinkProvider"] = {"status": "pending"}
	bridge.cancel_answer = {"status": "draining"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	wrapper.set_request_timeout_seconds(0.5)
	var outcomes: Array = []
	wrapper.request_completed.connect(func(outcome: Dictionary) -> void:
		outcomes.append(outcome))
	var guest: Dictionary = wrapper.sign_in_guest()
	_expect_equal(guest.get("status"), "pending",
		"first mutation claims the native slot")
	var race: Dictionary = wrapper.link_provider("play_games", {})
	_expect_equal(race.get("status"), "error",
		"competing mutation refused while one drains")
	_expect_equal(race.get("code"), "mutation_in_progress",
		"busy code is explicit and retryable")
	_expect_equal(race.get("retryable"), true, "busy is retryable")
	# The wrapper deadlines pass, but the native mutation never completes:
	# the slot stays held and no competing mutation may start.
	await _wait_for(outcomes, 1, 6.0)
	_expect_equal(outcomes[0].get("code"), "request_timeout",
		"wrapper force-settles past the draining windows")
	var late_race: Dictionary = wrapper.link_provider("play_games", {})
	_expect_equal(late_race.get("code"), "mutation_in_progress",
		"timeout does not free the native slot")
	_expect_equal(wrapper.sign_out().get("code"), "mutation_in_progress",
		"sign-out waits for the draining mutation")
	# Read-only session truth stays available throughout.
	bridge.receipts["moonlitGetSession"] = {"status": "ok",
		"kind": "cloud", "uid": "mutated-uid", "provider": "anonymous"}
	_expect_equal(wrapper.get_session().get("uid"), "mutated-uid",
		"session reads bypass the mutation slot")
	# Only the native terminal releases the slot; the wrapper already
	# settled this id, so the late terminal is dropped, not applied.
	bridge.emit_outcome({"status": "ok", "kind": "cloud",
		"uid": "mutated-uid", "provider": "anonymous",
		"request_id": str(guest.get("request_id", ""))})
	await process_frame
	_expect_equal(outcomes.size(), 1,
		"late terminal after force-settle is dropped")
	_expect_equal(wrapper.link_provider("play_games", {}).get("status"),
		"pending", "slot frees once the native mutation settles")
	root.remove_child(wrapper)
	_free_all([wrapper, bridge])


func _test_double_callback_settles_once() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	fake.provider_receipt = {"status": "pending"}
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	account.ensure_public_id()
	var changed: Array = []
	account.account_changed.connect(func(state: Dictionary) -> void:
		changed.append(state))
	var receipt: Dictionary = account.sign_in_provider("play_games")
	var request_id: String = str(receipt.get("request_id", ""))
	fake.complete_session(request_id,
		{"status": "ok", "kind": "cloud", "uid": "uid-one",
			"provider": "play_games"})
	await process_frame
	fake.complete_session(request_id,
		{"status": "ok", "kind": "cloud", "uid": "uid-two",
			"provider": "play_games"})
	await process_frame
	_expect_equal(changed.size(), 1, "double callback settles once")
	_expect_equal(account.cloud_uid(), "uid-one",
		"second terminal does not overwrite")
	account.free()
	fake.free()


func _test_stale_callback_ignored() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	fake.provider_receipt = {"status": "pending"}
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	account.ensure_public_id()
	var changed: Array = []
	account.account_changed.connect(func(state: Dictionary) -> void:
		changed.append(state))
	account.sign_in_provider("play_games")
	fake.complete_session("no-such-request",
		{"status": "ok", "kind": "cloud", "uid": "stale-uid",
			"provider": "play_games"})
	await process_frame
	_expect_equal(changed.size(), 0, "stale callback ignored")
	_expect_true(not account.is_cloud_linked(),
		"stale callback does not link")
	account.free()
	fake.free()


func _test_token_expiry_keeps_link_but_errors() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	fake.token_receipt = {"status": "pending"}
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	account.ensure_public_id()
	account.sign_in_guest()
	var errors: Array = []
	account.account_error.connect(func(error: Dictionary) -> void:
		errors.append(error))
	var receipt: Dictionary = account.get_id_token(true)
	var request_id: String = str(receipt.get("request_id", ""))
	fake.complete_error(request_id,
		{"status": "error", "code": "token_expired", "retryable": true})
	await process_frame
	_expect_equal(errors.size(), 1, "expiry surfaces an error")
	_expect_equal(account.cloud_uid(), "fake-anon-uid",
		"expired token does not unbind the account")
	account.free()
	fake.free()


func _test_revocation_returns_to_guest() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	fake.token_receipt = {"status": "pending"}
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	var guest_id: String = account.ensure_public_id()
	account.sign_in_guest()
	var receipt: Dictionary = account.get_id_token(false)
	var request_id: String = str(receipt.get("request_id", ""))
	fake.complete_error(request_id,
		{"status": "error", "code": "token_revoked", "retryable": false})
	await process_frame
	_expect_equal(account.account_kind(), "local_guest",
		"revocation returns to local guest")
	_expect_equal(account.public_id(), guest_id,
		"revocation keeps the public id")
	account.free()
	fake.free()


func _test_token_reaches_caller_only() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	fake.token_receipt = {"status": "pending"}
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	account.ensure_public_id()
	account.sign_in_guest()
	var tokens: Array = []
	account.id_token_ready.connect(func(token: Dictionary) -> void:
		tokens.append(token))
	var receipt: Dictionary = account.get_id_token(false)
	var request_id: String = str(receipt.get("request_id", ""))
	fake.complete_session(request_id,
		{"status": "ok", "id_token": SECRET_TOKEN,
			"token_expires_at": 4102444800000})
	await process_frame
	_expect_equal(tokens.size(), 1, "token delivered once")
	_expect_equal(tokens[0].get("id_token"), SECRET_TOKEN,
		"token value reaches the caller")
	var saved: String = _read_text(SAVE_PATH)
	_expect_true(not saved.contains(SECRET_TOKEN),
		"save file holds no token")
	account.free()
	fake.free()


func _test_sign_out_and_delete_keep_public_id() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	var guest_id: String = account.ensure_public_id()
	account.sign_in_guest()
	account.sign_out()
	_expect_equal(account.account_kind(), "local_guest",
		"sign-out returns to local guest")
	_expect_equal(account.public_id(), guest_id,
		"sign-out keeps the public id")
	account.sign_in_guest()
	account.delete_account()
	_expect_equal(account.account_kind(), "local_guest",
		"delete returns to local guest")
	_expect_equal(account.public_id(), guest_id,
		"delete keeps the public id")
	_expect_equal(fake.last_options.get("keep_provider_grant"), false,
		"delete revokes the provider grant by default")
	account.free()
	fake.free()


func _test_save_has_no_secrets_or_neighbors() -> void:
	_remove_save_target()
	var account: Node = ACCOUNT_SCRIPT.new()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	account.setup(fake)
	var public_id: String = account.ensure_public_id()
	account.sign_in_guest()
	account.get_id_token(false)
	var saved: String = _read_text(SAVE_PATH)
	_expect_true(saved.contains(public_id), "save holds the public id")
	_expect_true(saved.contains("[identity]"), "save holds only identity")
	for needle in ["fake-id-token", SECRET_TOKEN, SECRET_EMAIL, "@",
			"shard", "entitlement", "vault", "purchase"]:
		_expect_true(not saved.contains(needle),
			"save holds no " + needle)
	_free_all([account, fake])


func _test_wrapper_unsupported_on_desktop() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	_expect_true(not wrapper.is_native_available(),
		"desktop has no native bridge")
	var caps: Dictionary = wrapper.get_capabilities()
	_expect_equal(caps.get("status"), "unsupported",
		"desktop capabilities are explicit")
	_expect_equal(caps.get("guest"), true, "guest play stays possible")
	_expect_equal(wrapper.sign_in_guest().get("status"), "unsupported",
		"guest call is explicit without native")
	_expect_equal(
		wrapper.sign_in_provider("play_games", {}).get("status"),
		"unsupported", "provider call is explicit without native")
	wrapper.free()


func _test_wrapper_not_configured_names_missing() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override({})
	var caps: Dictionary = wrapper.get_capabilities()
	_expect_equal(caps.get("status"), "not_configured",
		"missing client ids are explicit")
	var missing: Array = caps.get("missing", [])
	for key in ["google.server_client_id", "google.play_app_id",
			"apple.android_enabled",
			"firebase.project_id", "firebase.sender_id",
			"firebase.android_api_key", "firebase.android_app_id"]:
		_expect_true(missing.has(key), "missing key is named " + key)
	var receipt: Dictionary = wrapper.sign_in_provider("play_games", {})
	_expect_equal(receipt.get("status"), "not_configured",
		"provider sign-in refuses without config")
	_expect_equal(wrapper.sign_in_guest().get("status"), "not_configured",
		"guest sign-in refuses without firebase config")
	_expect_true(bridge.calls.is_empty(),
		"nothing reaches native without config")
	_free_all([wrapper, bridge])


func _test_ios_gate_needs_flag_not_service_id() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInProvider"] = {"status": "pending"}
	wrapper.set_native_override(bridge, "ios")
	wrapper.set_config_override({})
	_expect_equal(wrapper.get_capabilities().get("status"), "not_configured",
		"ios without firebase config is explicit")
	# Firebase client config alone no longer offers the sheet: the export
	# carries no entitlement and the server provider is off, so Apple
	# stays unoffered until the setup is explicitly acknowledged — while
	# Google starts normally.
	var unacknowledged: Dictionary = _full_ios_config()
	(unacknowledged["apple"] as Dictionary).erase("ios_enabled")
	wrapper.set_config_override(unacknowledged)
	var dark: Dictionary = wrapper.get_capabilities()
	_expect_true(not (dark.get("providers", []) as Array).has("apple"),
		"apple unoffered without setup acknowledgement")
	_expect_true((dark.get("missing", []) as Array).has(
		"apple.ios_enabled"), "missing acknowledgement is named")
	_expect_equal(wrapper.sign_in_provider("apple", {}).get("status"),
		"not_configured", "apple refuses without acknowledgement")
	_expect_equal(wrapper.sign_in_provider("google", {}).get("status"),
		"pending", "google starts without apple acknowledgement")
	wrapper.set_config_override(_full_ios_config())
	var caps: Dictionary = wrapper.get_capabilities()
	_expect_equal(caps.get("status"), "ok",
		"ios with acknowledged setup is ready without any services id")
	_expect_true((caps.get("providers", []) as Array).has("apple"),
		"apple provider offered on ios")
	var receipt: Dictionary = wrapper.sign_in_provider("apple", {})
	_expect_equal(receipt.get("status"), "pending",
		"apple sign-in starts without a services id")
	var args: Dictionary = bridge.last_args.get(
		"moonlitSignInProvider", {}) as Dictionary
	_expect_true(not args.has("service_id"),
		"no services id is sent to the native sheet")
	_expect_equal(args.get("firebase_project_id"), "demo-project",
		"firebase project reaches native for safe init")
	_free_all([wrapper, bridge])


func _test_wrapper_rejects_unknown_provider() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInProvider"] = {"status": "pending"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	var calls_before_refusal: int = bridge.calls.size()
	_expect_equal(
		wrapper.sign_in_provider("game_center", {}).get("code"),
		"unknown_provider", "unknown provider refused")
	_expect_equal(bridge.calls.size(), calls_before_refusal,
		"refused calls stay local")
	# The same Firebase providers exist on both OSes now: google and
	# apple route on Android, while only the gaming profile stays out.
	_expect_equal(
		wrapper.sign_in_provider("google", {}).get("status"),
		"pending", "google routes on android")
	_expect_equal(
		wrapper.sign_in_provider("apple", {}).get("status"),
		"pending", "apple routes on android")
	wrapper.set_native_override(bridge, "ios")
	wrapper.set_config_override(_full_ios_config())
	calls_before_refusal = bridge.calls.size()
	_expect_equal(
		wrapper.sign_in_provider("play_games", {}).get("code"),
		"unknown_provider", "gaming profile refused on ios")
	_expect_equal(bridge.calls.size(), calls_before_refusal,
		"platform refusal stays local")
	_expect_equal(
		wrapper.sign_in_provider("google", {}).get("status"),
		"pending", "google routes on ios")
	_free_all([wrapper, bridge])


func _test_wrapper_timeout_and_late_answer_dropped() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	root.add_child(wrapper)
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	wrapper.set_request_timeout_seconds(0.5)
	var outcomes: Array = []
	wrapper.request_completed.connect(func(outcome: Dictionary) -> void:
		outcomes.append(outcome))
	var receipt: Dictionary = wrapper.sign_in_guest()
	var request_id: String = str(receipt.get("request_id", ""))
	_expect_equal(receipt.get("status"), "pending", "guest starts pending")
	await _wait_for(outcomes, 1, 5.0)
	_expect_equal(outcomes.size(), 1, "timeout settles the request")
	_expect_equal(outcomes[0].get("code"), "request_timeout",
		"timeout code is explicit")
	bridge.emit_outcome({"status": "ok", "kind": "cloud",
		"uid": "late-uid", "provider": "anonymous",
		"request_id": request_id})
	await process_frame
	await process_frame
	_expect_equal(outcomes.size(), 1, "late answer after timeout dropped")
	root.remove_child(wrapper)
	wrapper.free()
	bridge.free()


func _test_wrapper_scrubs_secrets_from_signals() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	root.add_child(wrapper)
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	bridge.receipts["moonlitGetIdToken"] = {"status": "pending"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	var outcomes: Array = []
	wrapper.request_completed.connect(func(outcome: Dictionary) -> void:
		outcomes.append(outcome))
	var sign_receipt: Dictionary = wrapper.sign_in_guest()
	bridge.emit_outcome({"status": "ok", "kind": "cloud", "uid": "u-1",
		"provider": "anonymous",
		"id_token": SECRET_TOKEN, "auth_code": "code-secret",
		"email": SECRET_EMAIL, "display_name": "Secret Name",
		"request_id": str(sign_receipt.get("request_id", ""))})
	await process_frame
	_expect_equal(outcomes.size(), 1, "sign-in outcome emitted")
	for key in ["id_token", "auth_code", "email", "display_name"]:
		_expect_true(not outcomes[0].has(key),
			"sign-in outcome scrubs " + key)
	var token_receipt: Dictionary = wrapper.get_id_token(false)
	bridge.emit_outcome({"status": "ok", "id_token": SECRET_TOKEN,
		"token_expires_at": 1, "email": SECRET_EMAIL,
		"request_id": str(token_receipt.get("request_id", ""))})
	await process_frame
	_expect_equal(outcomes.size(), 2, "token outcome emitted")
	_expect_equal(outcomes[1].get("id_token"), SECRET_TOKEN,
		"token answer keeps its documented token")
	_expect_true(not outcomes[1].has("email"),
		"token answer still scrubs email")
	root.remove_child(wrapper)
	wrapper.free()
	bridge.free()


func _test_native_adapter_drops_stale_and_double() -> void:
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInProvider"] = {"status": "pending"}
	var wrapper: Node = WRAPPER_SCRIPT.new()
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	var adapter: Node = NATIVE_ADAPTER_SCRIPT.new(wrapper)
	var sessions: Array = []
	var failures: Array = []
	adapter.session_changed.connect(func(session: Dictionary) -> void:
		sessions.append(session))
	adapter.operation_failed.connect(func(error: Dictionary) -> void:
		failures.append(error))
	var receipt: Dictionary = adapter.sign_in_provider("play_games", {})
	var request_id: String = str(receipt.get("request_id", ""))
	# Stale and double outcomes are injected past the wrapper (which has its
	# own rejection, covered above) so this test observes the adapter's.
	wrapper.request_completed.emit({"status": "ok", "kind": "cloud",
		"uid": "x", "provider": "play_games", "request_id": "stale-id"})
	await process_frame
	_expect_true(sessions.is_empty(), "adapter drops stale callback")
	bridge.emit_outcome({"status": "ok", "kind": "cloud", "uid": "x",
		"provider": "play_games", "request_id": request_id})
	await process_frame
	wrapper.request_completed.emit({"status": "ok", "kind": "cloud",
		"uid": "y", "provider": "play_games", "request_id": request_id})
	await process_frame
	_expect_equal(sessions.size(), 1, "adapter settles double once")
	_expect_equal(adapter.get_session().get("uid"), "x",
		"adapter keeps the first terminal")
	_expect_true(failures.is_empty(), "no failures recorded")
	adapter.free()
	wrapper.free()
	bridge.free()


func _test_native_chain_async_success_settles_account() -> void:
	# Whole-chain guest, link, and provider sign-in: fake native bridge ->
	# wrapper -> native adapter -> PlayerAccount. Each async success must
	# settle the account's pending request exactly once, keep the public
	# ID, and publish the real cloud UID/provider. The adapter's cached
	# snapshot stays clean while the transient event carries the accepted
	# id; without that id the account would stay pending forever.
	_remove_save_target()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	bridge.receipts["moonlitSignInProvider"] = {"status": "pending"}
	bridge.receipts["moonlitLinkProvider"] = {"status": "pending"}
	var wrapper: Node = WRAPPER_SCRIPT.new()
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	var adapter: Node = NATIVE_ADAPTER_SCRIPT.new(wrapper)
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(adapter)
	var guest_id: String = account.ensure_public_id()
	var changed: Array = []
	account.account_changed.connect(func(state: Dictionary) -> void:
		changed.append(state))
	var sessions: Array = []
	adapter.session_changed.connect(func(session: Dictionary) -> void:
		sessions.append(session))
	# Guest leg: anonymous sign-in settles the pending request.
	var guest_receipt: Dictionary = account.sign_in_guest()
	var guest_request: String = str(guest_receipt.get("request_id", ""))
	_expect_equal(guest_receipt.get("status"), "pending",
		"chain: guest starts pending")
	bridge.emit_outcome({"status": "ok", "kind": "cloud",
		"uid": "chain-anon-uid", "provider": "anonymous",
		"request_id": guest_request})
	await process_frame
	_expect_true(not bool(account.pending_request().get("pending", true)),
		"chain: guest terminal clears the pending lock")
	_expect_equal(changed.size(), 1,
		"chain: guest terminal emits exactly one account change")
	_expect_equal(account.public_id(), guest_id,
		"chain: guest keeps the public id")
	_expect_equal(account.cloud_uid(), "chain-anon-uid",
		"chain: guest publishes the real anonymous uid")
	_expect_equal(account.cloud_provider(), "anonymous",
		"chain: guest names the anonymous provider")
	_expect_equal(sessions.size(), 1, "chain: guest emits one session")
	_expect_equal((sessions[0] as Dictionary).get("request_id"),
		guest_request, "chain: guest event carries exactly the accepted id")
	_expect_true(not (adapter.get_session() as Dictionary).has(
		"request_id"), "chain: cached snapshot keeps no request id")
	_expect_true(not (adapter.get_session() as Dictionary).has("id_token"),
		"chain: cached snapshot keeps no token")
	_expect_true(not (sessions[0] as Dictionary).has("id_token"),
		"chain: guest event carries no token")
	# Link leg: Firebase links onto the same UID with the new provider.
	var link_receipt: Dictionary = account.link_current_provider("google")
	var link_request: String = str(link_receipt.get("request_id", ""))
	bridge.emit_outcome({"status": "ok", "kind": "cloud",
		"uid": "chain-anon-uid", "provider": "google",
		"request_id": link_request})
	await process_frame
	_expect_true(not bool(account.pending_request().get("pending", true)),
		"chain: link terminal clears the pending lock")
	_expect_equal(changed.size(), 2,
		"chain: link terminal emits exactly one more change")
	_expect_equal(account.public_id(), guest_id,
		"chain: link keeps the public id")
	_expect_equal(account.cloud_uid(), "chain-anon-uid",
		"chain: link keeps the firebase uid")
	_expect_equal(account.cloud_provider(), "google",
		"chain: link records the new provider")
	_expect_equal(sessions.size(), 2, "chain: link emits one more session")
	_expect_equal((sessions[1] as Dictionary).get("request_id"),
		link_request, "chain: link event carries exactly the accepted id")
	# Provider leg: a fresh provider sign-in settles the same way.
	var provider_receipt: Dictionary = account.sign_in_provider("play_games")
	var provider_request: String = str(
		provider_receipt.get("request_id", ""))
	bridge.emit_outcome({"status": "ok", "kind": "cloud",
		"uid": "chain-play-uid", "provider": "play_games",
		"request_id": provider_request})
	await process_frame
	_expect_true(not bool(account.pending_request().get("pending", true)),
		"chain: provider terminal clears the pending lock")
	_expect_equal(changed.size(), 3,
		"chain: provider terminal emits exactly one more change")
	_expect_equal(account.public_id(), guest_id,
		"chain: provider sign-in keeps the public id")
	_expect_equal(account.cloud_uid(), "chain-play-uid",
		"chain: provider sign-in publishes its uid")
	_expect_equal(account.cloud_provider(), "play_games",
		"chain: provider sign-in names its provider")
	_expect_equal(sessions.size(), 3,
		"chain: provider emits one more session")
	_expect_equal((sessions[2] as Dictionary).get("request_id"),
		provider_request,
		"chain: provider event carries exactly the accepted id")
	_free_all([account, adapter, wrapper, bridge])


func _test_native_chain_late_completion_ignores_current_request() -> void:
	# A late terminal for a cancelled chain request, a mismatched id, and
	# a double delivery must all leave the account's current pending
	# request untouched. Injections go past the wrapper so the adapter's
	# own rejection is what the chain observes.
	_remove_save_target()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	var wrapper: Node = WRAPPER_SCRIPT.new()
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	var adapter: Node = NATIVE_ADAPTER_SCRIPT.new(wrapper)
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(adapter)
	var guest_id: String = account.ensure_public_id()
	var changed: Array = []
	account.account_changed.connect(func(state: Dictionary) -> void:
		changed.append(state))
	var first: Dictionary = account.sign_in_guest()
	var stale_id: String = str(first.get("request_id", ""))
	_expect_equal(account.cancel_pending().get("status"), "cancelled",
		"chain-late: cancel releases the first request")
	var changes_after_cancel: int = changed.size()
	_expect_true(not bool(account.pending_request().get("pending", false)),
		"chain-late: cancel clears the lock")
	var second: Dictionary = account.sign_in_guest()
	var live_id: String = str(second.get("request_id", ""))
	_expect_true(bool(account.pending_request().get("pending", false)),
		"chain-late: second request takes the lock")
	# The late terminal for the cancelled request arrives now: dropped.
	wrapper.request_completed.emit({"status": "ok", "kind": "cloud",
		"uid": "late-uid", "provider": "anonymous",
		"request_id": stale_id})
	await process_frame
	# A mismatched id that no request ever owned: dropped.
	wrapper.request_completed.emit({"status": "ok", "kind": "cloud",
		"uid": "mismatch-uid", "provider": "anonymous",
		"request_id": "mi-never-issued"})
	await process_frame
	_expect_equal(changed.size(), changes_after_cancel,
		"chain-late: late and mismatched terminals emit nothing")
	_expect_equal(account.pending_request().get("request_id"), live_id,
		"chain-late: the current request still owns the lock")
	_expect_true(not account.is_cloud_linked(),
		"chain-late: dropped terminals link nothing")
	_expect_equal(account.public_id(), guest_id,
		"chain-late: dropped terminals keep the public id")
	# The live request still settles exactly once; its double is dropped.
	bridge.emit_outcome({"status": "ok", "kind": "cloud",
		"uid": "chain-live-uid", "provider": "anonymous",
		"request_id": live_id})
	await process_frame
	wrapper.request_completed.emit({"status": "ok", "kind": "cloud",
		"uid": "chain-double-uid", "provider": "anonymous",
		"request_id": live_id})
	await process_frame
	_expect_equal(changed.size(), changes_after_cancel + 1,
		"chain-late: live terminal settles once despite the double")
	_expect_equal(account.cloud_uid(), "chain-live-uid",
		"chain-late: double terminal does not overwrite the binding")
	_expect_true(not bool(account.pending_request().get("pending", false)),
		"chain-late: live terminal clears the lock")
	_free_all([account, adapter, wrapper, bridge])


func _test_native_chain_sync_refresh_stays_id_free() -> void:
	# Synchronous startup refresh hydrates the chain without taking a
	# pending lock: the adapter emits its bare snapshot (no id) and the
	# account folds the sync receipt on its explicit sync path instead of
	# treating it as a pending mutation.
	_remove_save_target()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitGetSession"] = {"status": "ok",
		"kind": "cloud", "uid": "restored-uid", "provider": "google"}
	var wrapper: Node = WRAPPER_SCRIPT.new()
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	var adapter: Node = NATIVE_ADAPTER_SCRIPT.new(wrapper)
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(adapter)
	var guest_id: String = account.ensure_public_id()
	var changed: Array = []
	account.account_changed.connect(func(state: Dictionary) -> void:
		changed.append(state))
	var sessions: Array = []
	adapter.session_changed.connect(func(session: Dictionary) -> void:
		sessions.append(session))
	var receipt: Dictionary = account.refresh_session()
	_expect_equal(receipt.get("status"), "ok",
		"chain-sync: refresh receipt ok")
	_expect_true(not bool(account.pending_request().get("pending", false)),
		"chain-sync: refresh takes no pending lock")
	_expect_true(account.is_cloud_linked(),
		"chain-sync: restored session links the account")
	_expect_equal(account.cloud_uid(), "restored-uid",
		"chain-sync: restored uid published")
	_expect_equal(account.cloud_provider(), "google",
		"chain-sync: restored provider published")
	_expect_equal(account.public_id(), guest_id,
		"chain-sync: refresh keeps the public id")
	_expect_equal(sessions.size(), 1, "chain-sync: one snapshot emitted")
	_expect_true(not (sessions[0] as Dictionary).has("request_id"),
		"chain-sync: snapshot carries no request id")
	_expect_true(changed.is_empty(),
		"chain-sync: no pending mutation means no account change")
	_free_all([account, adapter, wrapper, bridge])


func _test_provider_capabilities_gate_independently() -> void:
	# Android: Firebase alone leaves the bridge usable with no providers;
	# each staged key then adds only its own provider.
	var wrapper: Node = WRAPPER_SCRIPT.new()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	wrapper.set_native_override(bridge, "android")
	var firebase_only: Dictionary = {"firebase":
		(_full_android_config()["firebase"] as Dictionary).duplicate()}
	wrapper.set_config_override(firebase_only)
	var caps: Dictionary = wrapper.get_capabilities()
	_expect_equal(caps.get("status"), "ok",
		"firebase alone keeps the bridge usable")
	_expect_true((caps.get("providers", []) as Array).is_empty(),
		"no provider without provider keys")
	for key in ["google.server_client_id", "google.play_app_id",
			"apple.android_enabled"]:
		_expect_true((caps.get("missing", []) as Array).has(key),
			"unready provider key named " + key)
	# The Apple acknowledgement alone offers only Apple; Google refuses.
	var apple_only: Dictionary = _full_android_config()
	(apple_only["google"] as Dictionary).erase("server_client_id")
	(apple_only["google"] as Dictionary).erase("play_app_id")
	wrapper.set_config_override(apple_only)
	var apple_caps: Dictionary = wrapper.get_capabilities()
	_expect_equal(apple_caps.get("providers", []), ["apple"],
		"apple stands without google config")
	_expect_equal(
		wrapper.sign_in_provider("google", {}).get("status"),
		"not_configured", "google refuses without its client id")
	# The web client id alone offers Google but not the gaming profile.
	var no_app_id: Dictionary = _full_android_config()
	(no_app_id["google"] as Dictionary).erase("play_app_id")
	(no_app_id["apple"] as Dictionary).erase("android_enabled")
	wrapper.set_config_override(no_app_id)
	var google_caps: Dictionary = wrapper.get_capabilities()
	_expect_equal(google_caps.get("providers", []), ["google"],
		"google stands without apple setup or app id")
	# iOS: Firebase alone offers nothing; the acknowledgement adds
	# Apple, the client id adds Google, each independently.
	wrapper.set_native_override(bridge, "ios")
	wrapper.set_config_override({"firebase":
		(_full_ios_config()["firebase"] as Dictionary).duplicate()})
	var ios_caps: Dictionary = wrapper.get_capabilities()
	_expect_true((ios_caps.get("providers", []) as Array).is_empty(),
		"ios offers nothing without provider setup")
	_expect_true((ios_caps.get("missing", []) as Array).has(
		"google.ios_client_id"), "missing ios client id is named")
	_expect_true((ios_caps.get("missing", []) as Array).has(
		"apple.ios_enabled"), "missing ios acknowledgement is named")
	var ios_apple_only: Dictionary = _full_ios_config()
	(ios_apple_only["google"] as Dictionary).erase("ios_client_id")
	wrapper.set_config_override(ios_apple_only)
	_expect_equal(wrapper.get_capabilities().get("providers", []),
		["apple"], "ios apple stands without google config")
	wrapper.set_config_override(_full_ios_config())
	var ios_full: Dictionary = wrapper.get_capabilities()
	_expect_equal(ios_full.get("providers", []), ["google", "apple"],
		"ios offers both providers when configured")
	_expect_true((ios_full.get("missing", []) as Array).is_empty(),
		"full ios config names nothing missing")
	_free_all([wrapper, bridge])


func _test_google_sign_in_reaches_native_with_client_id() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInProvider"] = {"status": "pending"}
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	# Android Google carries the web client id, never the iOS one.
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	_expect_equal(wrapper.sign_in_provider("google", {}).get("status"),
		"pending", "android google starts")
	var android_args: Dictionary = bridge.last_args.get(
		"moonlitSignInProvider", {}) as Dictionary
	_expect_equal(android_args.get("provider"), "google",
		"native receives the google provider name")
	_expect_equal(android_args.get("server_client_id"), "public-client-id",
		"native receives the web client id")
	_expect_true(not android_args.has("ios_client_id"),
		"android never sends the ios client id")
	# An unacknowledged Apple setup refuses Apple while Google starts.
	var no_flag: Dictionary = _full_android_config()
	(no_flag["apple"] as Dictionary).erase("android_enabled")
	wrapper.set_config_override(no_flag)
	var refused: Dictionary = wrapper.sign_in_provider("apple", {})
	_expect_equal(refused.get("status"), "not_configured",
		"apple refuses without server-setup acknowledgement")
	_expect_true((refused.get("missing", []) as Array).has(
		"apple.android_enabled"), "missing acknowledgement is named")
	_expect_equal(wrapper.sign_in_provider("google", {}).get("status"),
		"pending", "google starts without apple setup")
	# iOS Google carries the iOS client id, never the web one.
	wrapper.set_native_override(bridge, "ios")
	wrapper.set_config_override(_full_ios_config())
	_expect_equal(wrapper.sign_in_provider("google", {}).get("status"),
		"pending", "ios google starts")
	var ios_args: Dictionary = bridge.last_args.get(
		"moonlitSignInProvider", {}) as Dictionary
	_expect_equal(ios_args.get("provider"), "google",
		"ios native receives the google provider name")
	_expect_equal(ios_args.get("ios_client_id"),
		"123456789012-zyxwvutsrqponmlkjihg.apps.googleusercontent.com",
		"ios native receives the ios client id")
	_expect_true(not ios_args.has("server_client_id"),
		"ios never sends the web client id")
	_free_all([wrapper, bridge])


func _test_link_keeps_firebase_uid() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	fake.link_receipt = {"status": "pending"}
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	var guest_id: String = account.ensure_public_id()
	account.sign_in_guest()
	_expect_equal(account.cloud_uid(), "fake-anon-uid",
		"guest holds its anonymous uid")
	var receipt: Dictionary = account.link_current_provider("google")
	var request_id: String = str(receipt.get("request_id", ""))
	# Firebase links the credential onto the signed-in user: the link
	# answers the same UID with the new provider, never a UID switch.
	fake.complete_session(request_id,
		{"status": "ok", "kind": "cloud", "uid": "fake-anon-uid",
			"provider": "google"})
	await process_frame
	_expect_equal(account.cloud_uid(), "fake-anon-uid",
		"linking keeps the firebase uid")
	_expect_equal(account.cloud_provider(), "google",
		"linking records the new provider")
	_expect_equal(account.public_id(), guest_id,
		"linking keeps the public id")
	account.free()
	fake.free()


func _test_google_link_conflict_keeps_guest() -> void:
	_remove_save_target()
	var fake: Node = FAKE_ADAPTER_SCRIPT.new()
	fake.link_receipt = {"status": "conflict",
		"code": "already_linked_elsewhere", "provider": "google"}
	var account: Node = ACCOUNT_SCRIPT.new()
	account.setup(fake)
	var guest_id: String = account.ensure_public_id()
	account.sign_in_guest()
	var conflicts: Array = []
	account.account_conflict.connect(func(conflict: Dictionary) -> void:
		conflicts.append(conflict))
	var receipt: Dictionary = account.link_current_provider("google")
	_expect_equal(receipt.get("status"), "conflict",
		"google link conflict receipt")
	_expect_equal(conflicts.size(), 1, "google conflict needs a UI choice")
	_expect_equal(conflicts[0].get("provider"), "google",
		"google conflict names the attempted provider")
	_expect_equal(account.public_id(), guest_id,
		"google conflict keeps the guest public id")
	_expect_equal(account.cloud_uid(), "fake-anon-uid",
		"google conflict keeps the previous cloud binding")
	account.free()
	fake.free()


func _test_refresh_native_session_hydrates_after_restart() -> void:
	# A fresh adapter starts as a local guest; the SDK-restored session
	# hydrates it through refresh, with no sign-in call and no UI.
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitGetSession"] = {"status": "ok",
		"kind": "cloud", "uid": "restored-uid", "provider": "google"}
	var wrapper: Node = WRAPPER_SCRIPT.new()
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	var adapter: Node = NATIVE_ADAPTER_SCRIPT.new(wrapper)
	_expect_equal(adapter.get_session().get("uid"), "",
		"fresh adapter memory is a guest")
	_expect_true(bridge.calls.is_empty(),
		"get_session never touches the bridge")
	var sessions: Array = []
	adapter.session_changed.connect(func(session: Dictionary) -> void:
		sessions.append(session))
	var receipt: Dictionary = adapter.refresh_native_session()
	_expect_equal(receipt.get("status"), "ok", "refresh receipt ok")
	_expect_equal(adapter.get_session().get("uid"), "restored-uid",
		"refresh hydrates the restored uid")
	_expect_equal(adapter.get_session().get("provider"), "google",
		"refresh hydrates the restored provider")
	_expect_equal(sessions.size(), 1, "refresh emits one session")
	_expect_equal(bridge.calls, ["moonlitGetSession"] as Array[String],
		"refresh performs no sign-in")
	adapter.free()
	wrapper.free()
	bridge.free()


func _test_refresh_native_session_async_and_signed_out() -> void:
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitGetSession"] = {"status": "pending"}
	var wrapper: Node = WRAPPER_SCRIPT.new()
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	var adapter: Node = NATIVE_ADAPTER_SCRIPT.new(wrapper)
	var sessions: Array = []
	var failures: Array = []
	adapter.session_changed.connect(func(session: Dictionary) -> void:
		sessions.append(session))
	adapter.operation_failed.connect(func(error: Dictionary) -> void:
		failures.append(error))
	var receipt: Dictionary = adapter.refresh_native_session()
	var request_id: String = str(receipt.get("request_id", ""))
	_expect_equal(receipt.get("status"), "pending",
		"async refresh starts pending")
	_expect_equal(adapter.get_session().get("uid"), "",
		"nothing applied before the terminal")
	bridge.emit_outcome({"status": "ok", "kind": "cloud",
		"uid": "async-uid", "provider": "apple",
		"request_id": request_id})
	await process_frame
	_expect_equal(adapter.get_session().get("uid"), "async-uid",
		"async refresh hydrates through the signal")
	_expect_equal(sessions.size(), 1, "async refresh emits one session")
	_expect_true(failures.is_empty(), "async refresh reports no failure")
	# A signed-out SDK answers a local guest: the adapter stays a guest
	# without reporting a failure.
	bridge.receipts["moonlitGetSession"] = {"status": "ok",
		"kind": "local_guest", "uid": "", "provider": ""}
	var plain: Node = NATIVE_ADAPTER_SCRIPT.new(wrapper)
	var plain_sessions: Array = []
	plain.session_changed.connect(func(session: Dictionary) -> void:
		plain_sessions.append(session))
	var plain_receipt: Dictionary = plain.refresh_native_session()
	_expect_equal(plain_receipt.get("status"), "ok",
		"signed-out refresh receipt ok")
	_expect_equal(plain.get_session().get("kind"), "local_guest",
		"signed-out refresh stays a guest")
	_expect_equal(plain_sessions.size(), 1,
		"signed-out refresh emits the guest session")
	_expect_true(failures.is_empty(), "signed-out refresh reports no failure")
	adapter.free()
	plain.free()
	wrapper.free()
	bridge.free()


func _test_sign_out_failure_preserves_session() -> void:
	# A real SDK sign-out failure answers a truthful error carrying the
	# re-read session — never a guest success — and the adapter keeps
	# the preserved session in memory.
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitGetSession"] = {"status": "ok",
		"kind": "cloud", "uid": "still-here", "provider": "apple"}
	bridge.receipts["moonlitSignOut"] = {"status": "error",
		"code": "sign_out_failed", "retryable": true,
		"kind": "cloud", "uid": "still-here", "provider": "apple"}
	var wrapper: Node = WRAPPER_SCRIPT.new()
	wrapper.set_native_override(bridge, "ios")
	wrapper.set_config_override(_full_ios_config())
	var adapter: Node = NATIVE_ADAPTER_SCRIPT.new(wrapper)
	var failures: Array = []
	adapter.operation_failed.connect(func(error: Dictionary) -> void:
		failures.append(error))
	adapter.refresh_native_session()
	_expect_equal(adapter.get_session().get("uid"), "still-here",
		"signed-in session hydrates before sign-out")
	var receipt: Dictionary = adapter.sign_out()
	_expect_equal(receipt.get("status"), "error",
		"failed sign-out answers an error")
	_expect_equal(receipt.get("code"), "sign_out_failed",
		"failed sign-out names its code")
	_expect_equal(receipt.get("kind"), "cloud",
		"failed sign-out carries the re-read session")
	_expect_equal(adapter.get_session().get("uid"), "still-here",
		"failed sign-out preserves the session")
	_expect_true(failures.is_empty(),
		"sync sign-out failure reports no async failure")
	adapter.free()
	wrapper.free()
	bridge.free()


func _test_cancel_google_request_drains_like_any_provider() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	root.add_child(wrapper)
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInProvider"] = {"status": "pending"}
	bridge.cancel_answer = {"status": "draining"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	wrapper.set_request_timeout_seconds(0.5)
	var outcomes: Array = []
	wrapper.request_completed.connect(func(outcome: Dictionary) -> void:
		outcomes.append(outcome))
	var receipt: Dictionary = wrapper.sign_in_provider("google", {})
	var request_id: String = str(receipt.get("request_id", ""))
	var drain: Dictionary = wrapper.cancel_request(request_id)
	_expect_equal(drain.get("status"), "draining",
		"google cancel during mutation reports draining")
	_expect_equal(wrapper.pending_request_ids(), [request_id],
		"google keeps the pending lock while draining")
	bridge.emit_outcome({"status": "ok", "kind": "cloud", "uid": "g-1",
		"provider": "google", "request_id": request_id})
	await process_frame
	_expect_equal(outcomes.size(), 1, "google drained outcome lands")
	_expect_equal(outcomes[0].get("provider"), "google",
		"google drained outcome names its provider")
	_expect_equal(wrapper.pending_request_ids(), [],
		"google drained terminal releases the lock")
	root.remove_child(wrapper)
	_free_all([wrapper, bridge])


func _test_wrapper_java_registry_authority() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	var bridge: Node = JavaOracleBridge.new()
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	# The stand-in exposes the GDScript method, so the old `has_method`
	# guard alone would dispatch. The Java oracle says absent, so the
	# fixed discovery must refuse without touching native.
	_expect_true(bridge.has_method("moonlitSignInGuest"),
		"java: stand-in exposes the method to has_method")
	_expect_true(not bool(bridge.call("has_java_method",
		"moonlitSignInGuest")), "java: oracle reports the method absent")
	var refused: Dictionary = wrapper.sign_in_guest()
	_expect_equal(refused.get("status"), "unsupported",
		"java: absent oracle refuses dispatch")
	_expect_equal(refused.get("code"), "native_bridge_unavailable",
		"java: refusal names the missing bridge")
	_expect_true((bridge.calls as Array).is_empty(),
		"java: refused call never reaches native")
	_expect_true(wrapper.pending_request_ids().is_empty(),
		"java: refused call takes no lock")
	# Oracle present: the same stand-in dispatches normally.
	(bridge.get("java_methods") as Dictionary)["moonlitSignInGuest"] = true
	var started: Dictionary = wrapper.sign_in_guest()
	_expect_equal(started.get("status"), "pending",
		"java: present oracle dispatches")
	_expect_equal(bridge.calls, ["moonlitSignInGuest"] as Array[String],
		"java: present oracle reaches native once")
	_expect_equal(wrapper.pending_request_ids(),
		[str(started.get("request_id", ""))],
		"java: dispatched call takes the lock")
	# Ordinary fakes without any oracle keep the `has_method` path.
	var plain_wrapper: Node = WRAPPER_SCRIPT.new()
	var plain: Node = FAKE_BRIDGE_SCRIPT.new()
	plain.receipts["moonlitSignInGuest"] = {"status": "pending"}
	plain_wrapper.set_native_override(plain, "android")
	plain_wrapper.set_config_override(_full_android_config())
	_expect_true(not plain.has_method("has_java_method"),
		"java: ordinary fake exposes no oracle")
	_expect_equal(plain_wrapper.sign_in_guest().get("status"), "pending",
		"java: ordinary fake still dispatches")
	_free_all([wrapper, bridge, plain_wrapper, plain])


func _test_wrapper_java_cancel_authority() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	root.add_child(wrapper)
	var bridge: Node = JavaOracleBridge.new()
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	bridge.cancel_answer = {"status": "draining"}
	(bridge.get("java_methods") as Dictionary)["moonlitSignInGuest"] = true
	(bridge.get("java_methods") as Dictionary)["moonlitCancelRequest"] = true
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	var outcomes: Array = []
	wrapper.request_completed.connect(func(outcome: Dictionary) -> void:
		outcomes.append(outcome))
	var first: Dictionary = wrapper.sign_in_guest()
	var first_id: String = str(first.get("request_id", ""))
	# Oracle present: native draining is honored and the lock stays.
	var drain: Dictionary = wrapper.cancel_request(first_id)
	_expect_equal(drain.get("status"), "draining",
		"java-cancel: present oracle honors draining")
	_expect_equal(wrapper.pending_request_ids(), [first_id],
		"java-cancel: draining keeps the lock")
	_expect_equal(bridge.cancelled_ids, [first_id] as Array[String],
		"java-cancel: present oracle reaches native cancel")
	bridge.emit_outcome({"status": "ok", "kind": "cloud", "uid": "j-1",
		"provider": "anonymous", "request_id": first_id})
	await process_frame
	_expect_equal(outcomes.size(), 1, "java-cancel: drained terminal lands")
	# Oracle absent for cancel only: the same GDScript cancel method
	# exists, but the fixed discovery must not invoke it.
	var second: Dictionary = wrapper.sign_in_guest()
	var second_id: String = str(second.get("request_id", ""))
	(bridge.get("java_methods") as Dictionary)["moonlitCancelRequest"] = false
	_expect_true(bridge.has_method("moonlitCancelRequest"),
		"java-cancel: stand-in still exposes cancel")
	var cancels_before: int = (bridge.cancelled_ids as Array).size()
	var settled: Dictionary = wrapper.cancel_request(second_id)
	_expect_equal(settled.get("status"), "cancelled",
		"java-cancel: absent oracle settles as cancelled")
	_expect_true(wrapper.pending_request_ids().is_empty(),
		"java-cancel: absent oracle releases the lock")
	_expect_equal((bridge.cancelled_ids as Array).size(), cancels_before,
		"java-cancel: absent oracle never reaches native")
	_expect_equal(outcomes.size(), 2, "java-cancel: local cancel emits once")
	_expect_equal(outcomes[1].get("status"), "cancelled",
		"java-cancel: local cancel names its status")
	root.remove_child(wrapper)
	_free_all([wrapper, bridge])


func _test_consent_window_policy_selects_per_method() -> void:
	# Production defaults, no overrides: the provider sheet calls arm the
	# human-interaction window while every other call keeps the ordinary
	# network window. Nothing here waits: the wrapper stays off the tree
	# so no timer arms, and the stored per-request window is read back.
	var wrapper: Node = WRAPPER_SCRIPT.new()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInProvider"] = {"status": "pending"}
	bridge.receipts["moonlitLinkProvider"] = {"status": "pending"}
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	bridge.receipts["moonlitGetSession"] = {"status": "pending"}
	bridge.receipts["moonlitGetIdToken"] = {"status": "pending"}
	bridge.receipts["moonlitSignOut"] = {"status": "pending"}
	bridge.receipts["moonlitDeleteAccount"] = {"status": "pending"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	_expect_equal(wrapper.pending_timeout_seconds("mi-never-issued"), -1.0,
		"consent: unknown id reports no window")
	for provider in ["google", "apple"]:
		var sign_in: Dictionary = wrapper.sign_in_provider(provider, {})
		_expect_equal(sign_in.get("status"), "pending",
			"consent: " + provider + " sign-in starts")
		_expect_equal(wrapper.pending_timeout_seconds(
			str(sign_in.get("request_id", ""))), 300.0,
			"consent: " + provider + " sign-in arms 300s")
		var link: Dictionary = wrapper.link_provider(provider, {})
		_expect_equal(link.get("status"), "pending",
			"consent: " + provider + " link starts")
		_expect_equal(wrapper.pending_timeout_seconds(
			str(link.get("request_id", ""))), 300.0,
			"consent: " + provider + " link arms 300s")
	var guest: Dictionary = wrapper.sign_in_guest()
	_expect_equal(guest.get("status"), "pending",
		"consent: guest starts")
	_expect_equal(wrapper.pending_timeout_seconds(
		str(guest.get("request_id", ""))), 30.0,
		"consent: guest keeps 30s")
	var session: Dictionary = wrapper.get_session()
	_expect_equal(session.get("status"), "pending",
		"consent: async session read starts")
	_expect_equal(wrapper.pending_timeout_seconds(
		str(session.get("request_id", ""))), 30.0,
		"consent: session read keeps 30s")
	var token: Dictionary = wrapper.get_id_token(true)
	_expect_equal(token.get("status"), "pending",
		"consent: token refresh starts")
	_expect_equal(wrapper.pending_timeout_seconds(
		str(token.get("request_id", ""))), 30.0,
		"consent: token refresh keeps 30s")
	var sign_out: Dictionary = wrapper.sign_out()
	_expect_equal(sign_out.get("status"), "pending",
		"consent: sign-out starts")
	_expect_equal(wrapper.pending_timeout_seconds(
		str(sign_out.get("request_id", ""))), 30.0,
		"consent: sign-out keeps 30s")
	var removal: Dictionary = wrapper.delete_account({})
	_expect_equal(removal.get("status"), "pending",
		"consent: delete starts")
	_expect_equal(wrapper.pending_timeout_seconds(
		str(removal.get("request_id", ""))), 30.0,
		"consent: delete keeps 30s")
	# The policy is method-based, so the iOS sheets select it too.
	wrapper.set_native_override(bridge, "ios")
	wrapper.set_config_override(_full_ios_config())
	for provider in ["google", "apple"]:
		var ios_sign_in: Dictionary = wrapper.sign_in_provider(provider, {})
		_expect_equal(ios_sign_in.get("status"), "pending",
			"consent: ios " + provider + " sign-in starts")
		_expect_equal(wrapper.pending_timeout_seconds(
			str(ios_sign_in.get("request_id", ""))), 300.0,
			"consent: ios " + provider + " sign-in arms 300s")
	_free_all([wrapper, bridge])


func _test_consent_window_interactive_timeout_settles_and_drops_late(
) -> void:
	# The real pending timer uses the interactive window: with a short
	# injected interactive deadline and the ordinary default untouched, a
	# provider sheet still pending settles as a bounded timeout, and the
	# late provider answer is dropped by id. Under a universal 30s policy
	# nothing would settle inside the wait below.
	var wrapper: Node = WRAPPER_SCRIPT.new()
	root.add_child(wrapper)
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInProvider"] = {"status": "pending"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	wrapper.set_interactive_timeout_seconds(0.5)
	var outcomes: Array = []
	wrapper.request_completed.connect(func(outcome: Dictionary) -> void:
		outcomes.append(outcome))
	var receipt: Dictionary = wrapper.sign_in_provider("google", {})
	var request_id: String = str(receipt.get("request_id", ""))
	_expect_equal(wrapper.pending_timeout_seconds(request_id), 0.5,
		"consent-timer: injected interactive window stored")
	await _wait_for(outcomes, 1, 5.0)
	_expect_equal(outcomes.size(), 1, "consent-timer: timeout settles")
	_expect_equal(outcomes[0].get("status"), "error",
		"consent-timer: timeout is an error, not a success")
	_expect_equal(outcomes[0].get("code"), "request_timeout",
		"consent-timer: timeout keeps its code")
	_expect_equal(outcomes[0].get("retryable"), true,
		"consent-timer: timeout stays retryable")
	_expect_equal(outcomes[0].get("request_id"), request_id,
		"consent-timer: timeout names its request")
	_expect_true(wrapper.pending_request_ids().is_empty(),
		"consent-timer: timeout releases the lock")
	bridge.emit_outcome({"status": "ok", "kind": "cloud",
		"uid": "late-uid", "provider": "google",
		"request_id": request_id})
	await process_frame
	await process_frame
	_expect_equal(outcomes.size(), 1,
		"consent-timer: late provider answer dropped")
	root.remove_child(wrapper)
	_free_all([wrapper, bridge])


func _test_consent_window_ordinary_and_interactive_differ() -> void:
	# One bridge, two windows: the blanket override shortens the ordinary
	# deadline, then the interactive override re-separates the sheet
	# window. The guest times out fast while the Apple link stays pending;
	# cancelling it then settles at once instead of waiting out its minute.
	var wrapper: Node = WRAPPER_SCRIPT.new()
	root.add_child(wrapper)
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	bridge.receipts["moonlitLinkProvider"] = {"status": "pending"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	wrapper.set_request_timeout_seconds(0.5)
	wrapper.set_interactive_timeout_seconds(60.0)
	var outcomes: Array = []
	wrapper.request_completed.connect(func(outcome: Dictionary) -> void:
		outcomes.append(outcome))
	var guest: Dictionary = wrapper.sign_in_guest()
	var guest_id: String = str(guest.get("request_id", ""))
	var link: Dictionary = wrapper.link_provider("apple", {})
	var link_id: String = str(link.get("request_id", ""))
	_expect_equal(wrapper.pending_timeout_seconds(guest_id), 0.5,
		"consent-split: guest stored the ordinary window")
	_expect_equal(wrapper.pending_timeout_seconds(link_id), 60.0,
		"consent-split: apple link stored the interactive window")
	await _wait_for(outcomes, 1, 5.0)
	_expect_equal(outcomes.size(), 1, "consent-split: guest times out fast")
	_expect_equal(outcomes[0].get("request_id"), guest_id,
		"consent-split: the fast timeout is the guest")
	_expect_equal(outcomes[0].get("code"), "request_timeout",
		"consent-split: fast timeout keeps its code")
	_expect_equal(wrapper.pending_request_ids(), [link_id],
		"consent-split: apple link still pending past the guest deadline")
	var cancel: Dictionary = wrapper.cancel_request(link_id)
	_expect_equal(cancel.get("status"), "cancelled",
		"consent-split: pending link cancels at once")
	_expect_equal(outcomes.size(), 2,
		"consent-split: cancel emits exactly once")
	_expect_equal(outcomes[1].get("code"), "user_cancelled",
		"consent-split: cancel keeps its code")
	bridge.emit_outcome({"status": "ok", "kind": "cloud",
		"uid": "late-uid", "provider": "apple", "request_id": link_id})
	await process_frame
	await process_frame
	_expect_equal(outcomes.size(), 2,
		"consent-split: late link answer dropped")
	root.remove_child(wrapper)
	_free_all([wrapper, bridge])


func _test_consent_window_cancel_stays_immediate() -> void:
	# No overrides: the provider sheet arms the full 300s window, yet an
	# explicit cancel settles at once instead of waiting it out. Stale,
	# late, and double answers around it stay dropped.
	var wrapper: Node = WRAPPER_SCRIPT.new()
	root.add_child(wrapper)
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInProvider"] = {"status": "pending"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	var outcomes: Array = []
	wrapper.request_completed.connect(func(outcome: Dictionary) -> void:
		outcomes.append(outcome))
	# A stale answer for an id no request owns: dropped, nothing emitted.
	bridge.emit_outcome({"status": "ok", "kind": "cloud", "uid": "stale",
		"provider": "apple", "request_id": "mi-never-issued"})
	await process_frame
	_expect_true(outcomes.is_empty(),
		"consent-cancel: stale provider answer dropped")
	var receipt: Dictionary = wrapper.sign_in_provider("apple", {})
	var request_id: String = str(receipt.get("request_id", ""))
	_expect_equal(wrapper.pending_timeout_seconds(request_id), 300.0,
		"consent-cancel: production sheet arms 300s")
	var cancel: Dictionary = wrapper.cancel_request(request_id)
	_expect_equal(cancel.get("status"), "cancelled",
		"consent-cancel: cancel settles at once")
	_expect_equal(bridge.cancelled_ids, [request_id] as Array[String],
		"consent-cancel: cancel reaches native at once")
	_expect_equal(outcomes.size(), 1,
		"consent-cancel: cancel emits exactly once")
	_expect_equal(outcomes[0].get("code"), "user_cancelled",
		"consent-cancel: cancel keeps its code")
	_expect_true(wrapper.pending_request_ids().is_empty(),
		"consent-cancel: cancel releases the lock")
	# Late and double answers for the cancelled id: dropped.
	bridge.emit_outcome({"status": "ok", "kind": "cloud", "uid": "late",
		"provider": "apple", "request_id": request_id})
	await process_frame
	bridge.emit_outcome({"status": "ok", "kind": "cloud",
		"uid": "late-again", "provider": "apple",
		"request_id": request_id})
	await process_frame
	await process_frame
	_expect_equal(outcomes.size(), 1,
		"consent-cancel: late and double answers dropped")
	root.remove_child(wrapper)
	_free_all([wrapper, bridge])


func _test_consent_window_draining_retains_stored_policy() -> void:
	# Draining extensions re-arm the window the request was given, not the
	# live globals: the interactive override changes mid-flight, yet the
	# draining provider request still force-settles on its original short
	# window instead of stretching to the new one.
	var wrapper: Node = WRAPPER_SCRIPT.new()
	root.add_child(wrapper)
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitLinkProvider"] = {"status": "pending"}
	bridge.cancel_answer = {"status": "draining"}
	wrapper.set_native_override(bridge, "android")
	wrapper.set_config_override(_full_android_config())
	wrapper.set_interactive_timeout_seconds(0.5)
	var outcomes: Array = []
	wrapper.request_completed.connect(func(outcome: Dictionary) -> void:
		outcomes.append(outcome))
	var receipt: Dictionary = wrapper.link_provider("google", {})
	var request_id: String = str(receipt.get("request_id", ""))
	wrapper.set_interactive_timeout_seconds(60.0)
	_expect_equal(wrapper.pending_timeout_seconds(request_id), 0.5,
		"consent-drain: stored window survives the override change")
	await _wait_for(outcomes, 1, 6.0)
	_expect_equal(outcomes.size(), 1,
		"consent-drain: draining request force-settles bounded")
	_expect_equal(outcomes[0].get("code"), "request_timeout",
		"consent-drain: force-settle keeps the timeout code")
	_expect_equal(outcomes[0].get("retryable"), true,
		"consent-drain: force-settle stays retryable")
	bridge.emit_outcome({"status": "ok", "kind": "cloud",
		"uid": "late-uid", "provider": "google",
		"request_id": request_id})
	await process_frame
	await process_frame
	_expect_equal(outcomes.size(), 1,
		"consent-drain: post-timeout answer dropped")
	root.remove_child(wrapper)
	_free_all([wrapper, bridge])


func _test_sync_refusal_settles_with_error() -> void:
	var refusals: Array = [
		{"status": "unsupported", "code": "native_bridge_unavailable"},
		{"status": "not_configured", "code": "identity_not_configured",
			"missing": ["firebase.project_id"]},
	]
	for refusal in refusals:
		var label: String = str((refusal as Dictionary).get("status", ""))
		# A local guest refused at sign-in: one error, same ID, no lock.
		_remove_identity_and_bindings()
		var bare_fake: Node = FAKE_ADAPTER_SCRIPT.new()
		var bare: Node = ACCOUNT_SCRIPT.new()
		bare.setup(bare_fake)
		var bare_id: String = bare.ensure_public_id()
		var bare_errors: Array = []
		bare.account_error.connect(func(error: Dictionary) -> void:
			bare_errors.append(error))
		bare_fake.provider_receipt = (refusal as Dictionary).duplicate()
		var bare_receipt: Dictionary = bare.sign_in_provider("google")
		_expect_equal(bare_receipt.get("status"), label,
			"refusal: local receipt stays " + label)
		_expect_equal(bare_errors.size(), 1,
			"refusal: local sync " + label + " emits one error")
		_expect_equal(bare_errors[0].get("status"), label,
			"refusal: local error preserves " + label)
		_expect_equal(bare_errors[0].get("code"),
			str((refusal as Dictionary).get("code", "")),
			"refusal: local error preserves its code")
		_expect_equal(bare.public_id(), bare_id,
			"refusal: local " + label + " keeps the id")
		_expect_equal(bare.cloud_uid(), "",
			"refusal: local " + label + " stays a guest")
		_expect_true(not bool(bare.pending_request().get(
			"pending", false)),
			"refusal: local " + label + " takes no lock")
		_expect_equal(bare.cancel_pending().get("code"),
			"no_pending_request",
			"refusal: local " + label + " leaves nothing to cancel")
		_free_all([bare, bare_fake])
		# An anonymous guest refused at link: binding and ID untouched.
		_remove_identity_and_bindings()
		var fake: Node = FAKE_ADAPTER_SCRIPT.new()
		var account: Node = ACCOUNT_SCRIPT.new()
		account.setup(fake)
		var guest_id: String = account.ensure_public_id()
		account.sign_in_guest()
		var anon_uid: String = account.cloud_uid()
		account.adopt_canonical_id(anon_uid, guest_id)
		var errors: Array = []
		account.account_error.connect(func(error: Dictionary) -> void:
			errors.append(error))
		fake.link_receipt = (refusal as Dictionary).duplicate()
		var receipt: Dictionary = account.link_current_provider("google")
		_expect_equal(receipt.get("status"), label,
			"refusal: link receipt stays " + label)
		_expect_equal(errors.size(), 1,
			"refusal: link sync " + label + " emits one error")
		_expect_equal(errors[0].get("status"), label,
			"refusal: link error preserves " + label)
		if label == "not_configured":
			_expect_equal(errors[0].get("missing", []),
				["firebase.project_id"],
				"refusal: link error preserves its missing keys")
		_expect_equal(account.public_id(), guest_id,
			"refusal: link " + label + " keeps the id")
		_expect_equal(account.cloud_uid(), anon_uid,
			"refusal: link " + label + " keeps the binding")
		_expect_equal(account.public_id_for_uid(anon_uid), guest_id,
			"refusal: link " + label + " keeps the durable binding")
		_expect_true(not bool(account.pending_request().get(
			"pending", false)),
			"refusal: link " + label + " takes no lock")
		_expect_true(not errors[0].has("id_token"),
			"refusal: link error carries no token")
		_free_all([account, fake])


func _free_all(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			if node is Node and (node as Node).is_inside_tree():
				(node as Node).remove_parent()
			node.free()


func _test_extension_list_composition() -> void:
	# Both export plugins must parse with the shared composer wired in.
	# Loading is compiling; neither plugin is instantiated or enabled here.
	for path in ["res://addons/godot-iap/godot_iap_plugin.gd",
			"res://addons/moonlit-identity/moonlit_identity_plugin.gd"]:
		var plugin: Script = load(path) as Script
		_expect_true(plugin != null and plugin.can_instantiate(),
			"export plugin compiles " + path)
	var composed: String = COMPOSER_SCRIPT.compose()
	_expect_true(composed.contains(
		"res://addons/moonlit-identity/bin/moonlit_identity.gdextension"),
		"composed list names the identity extension")
	# The IAP descriptor is a director-built artifact: present in configured
	# copies, absent here. Either way the composed list must agree with it.
	var iap_source: String = \
		"res://addons/godot-iap/bin/godot_iap.gdextension.ios"
	var iap_export: String = \
		"res://addons/godot-iap/bin/godot_iap.gdextension"
	if FileAccess.file_exists(iap_source):
		_expect_true(composed.contains(iap_export),
			"composed list keeps the purchase extension")
	else:
		_expect_true(not composed.contains(iap_export),
			"composed list omits the missing purchase descriptor")
	_expect_true(composed.ends_with("\n") or composed.is_empty(),
		"composed list ends in a newline")


func _test_android_gate_needs_play_app_id() -> void:
	var wrapper: Node = WRAPPER_SCRIPT.new()
	var bridge: Node = FAKE_BRIDGE_SCRIPT.new()
	bridge.receipts["moonlitSignInProvider"] = {"status": "pending"}
	bridge.receipts["moonlitSignInGuest"] = {"status": "pending"}
	wrapper.set_native_override(bridge, "android")
	var partial: Dictionary = _full_android_config()
	(partial["google"] as Dictionary).erase("play_app_id")
	wrapper.set_config_override(partial)
	# Without the Play app id only the gaming profile is unoffered: the
	# bridge stays usable and Google, Apple, and guest play on.
	var caps: Dictionary = wrapper.get_capabilities()
	_expect_equal(caps.get("status"), "ok",
		"android without play app id stays usable")
	var providers: Array = caps.get("providers", [])
	_expect_true(providers.has("google"), "google offered without app id")
	_expect_true(providers.has("apple"), "apple offered without app id")
	_expect_true(not providers.has("play_games"),
		"gaming profile unoffered without app id")
	_expect_true((caps.get("missing", []) as Array).has(
		"google.play_app_id"), "missing play app id is named")
	_expect_equal(
		wrapper.sign_in_provider("play_games", {}).get("status"),
		"not_configured", "gaming sign-in refuses without play app id")
	_expect_equal(
		wrapper.sign_in_provider("google", {}).get("status"),
		"pending", "google sign-in starts without play app id")
	_expect_equal(wrapper.sign_in_guest().get("status"), "pending",
		"guest sign-in starts without play app id")
	wrapper.set_config_override(_full_android_config())
	var ready: Dictionary = wrapper.get_capabilities()
	_expect_equal(ready.get("status"), "ok",
		"android with play app id is ready")
	_expect_true((ready.get("providers", []) as Array).has("play_games"),
		"play games offered when configured")
	_expect_true((ready.get("missing", []) as Array).is_empty(),
		"full config names nothing missing")
	_free_all([wrapper, bridge])


func _test_manifest_hook_stamps_app_id() -> void:
	var fixture: String = "user://hook_fixture.cfg"
	# Valid id: exact element text, nothing else.
	_write_text(fixture, "[google]\nplay_app_id=\"123456789012\"\n")
	_expect_equal(
		MANIFEST_HOOK_SCRIPT.application_element_contents(fixture),
		'<meta-data android:name="com.google.android.gms.games.APP_ID" '
		+ 'android:value="123456789012" />',
		"manifest hook stamps the numeric app id")
	# Every defect injects nothing: the export stays honest and the
	# bridge reports not_configured at runtime instead.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	_expect_equal(
		MANIFEST_HOOK_SCRIPT.application_element_contents(fixture), "",
		"missing config injects nothing")
	_write_text(fixture, "[google]\nserver_client_id=\"x\"\n")
	_expect_equal(
		MANIFEST_HOOK_SCRIPT.application_element_contents(fixture), "",
		"missing app id injects nothing")
	_write_text(fixture, "[google]\nplay_app_id=\"12ab\"\n")
	_expect_equal(
		MANIFEST_HOOK_SCRIPT.application_element_contents(fixture), "",
		"non-numeric app id injects nothing")
	_write_text(fixture, "[google]\nplay_app_id=\"123\"\n")
	_expect_equal(
		MANIFEST_HOOK_SCRIPT.application_element_contents(fixture), "",
		"short app id injects nothing")
	_write_text(fixture, "not a config {{{{")
	_expect_equal(
		MANIFEST_HOOK_SCRIPT.application_element_contents(fixture), "",
		"corrupt config injects nothing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))


func _test_ios_export_manifest_links_everything() -> void:
	var root: String = "user://export_fixture"
	var frameworks_dir: String = root + "/frameworks"
	var resources_dir: String = root + "/resources"
	_make_fixture_dir(frameworks_dir + "/FirebaseAuth.framework")
	_make_fixture_dir(frameworks_dir + "/FirebaseCore.framework")
	_make_fixture_dir(frameworks_dir + "/StrayDir")
	_write_text(frameworks_dir + "/notes.txt", "ignored\n")
	_make_fixture_dir(resources_dir + "/FirebaseAuth_Privacy.bundle")
	_write_text(resources_dir
		+ "/FirebaseAuth_Privacy.bundle/PrivacyInfo.xcprivacy", "<!-- x -->\n")
	_make_fixture_dir(resources_dir + "/Bare.bundle")
	var frameworks: PackedStringArray = \
		IOS_MANIFEST_SCRIPT.framework_paths(frameworks_dir)
	_expect_equal(frameworks.size(), 2,
		"manifest lists every staged framework")
	_expect_true(frameworks[0].ends_with("FirebaseAuth.framework")
		and frameworks[1].ends_with("FirebaseCore.framework"),
		"framework paths are sorted full paths")
	_expect_equal(
		IOS_MANIFEST_SCRIPT.framework_paths(root + "/absent").size(), 0,
		"missing frameworks dir lists nothing")
	var bundles: PackedStringArray = \
		IOS_MANIFEST_SCRIPT.resource_bundle_paths(resources_dir)
	_expect_equal(bundles.size(), 2,
		"manifest lists every staged bundle")
	_expect_true(
		IOS_MANIFEST_SCRIPT.bundle_has_manifest(
			resources_dir + "/FirebaseAuth_Privacy.bundle"),
		"bundle with manifest passes")
	_expect_true(
		not IOS_MANIFEST_SCRIPT.bundle_has_manifest(
			resources_dir + "/Bare.bundle"),
		"bundle without manifest fails")
	var missing: PackedStringArray = \
		IOS_MANIFEST_SCRIPT.missing_required_bundles(resources_dir)
	_expect_true(missing.has("FirebaseCore_Privacy.bundle"),
		"missing bundle is named")
	_expect_true(missing.has("GoogleSignIn.bundle"),
		"missing sign-in bundle is named")
	_expect_true(missing.has("AppAuthCore_Privacy.bundle"),
		"missing auth closure bundle is named")
	_expect_true(missing.has("GTMAppAuth_Privacy.bundle"),
		"missing app-auth closure bundle is named")
	_expect_true(not missing.has("FirebaseAuth_Privacy.bundle"),
		"staged bundle is not missing")
	_expect_equal(IOS_MANIFEST_SCRIPT.REQUIRED_BUNDLES.size(), 9,
		"nine privacy bundles required")
	var systems: PackedStringArray = IOS_MANIFEST_SCRIPT.system_frameworks()
	_expect_equal(systems.size(), 7,
		"seven system frameworks declared")
	for name in ["AuthenticationServices", "CoreTelephony", "GameKit",
			"SafariServices", "Security", "SystemConfiguration", "WebKit"]:
		_expect_true(systems.has(name + ".framework"),
			"system framework linked " + name)
	_expect_equal(IOS_MANIFEST_SCRIPT.linker_flags(), "-ObjC -lz",
		"linker flags carry -ObjC and -lz")
	_remove_tree(root)


func _test_ios_static_entry_registration() -> void:
	var entry: String = IOS_MANIFEST_SCRIPT.ENTRY_SYMBOL
	_expect_equal(IOS_MANIFEST_SCRIPT.registration_cpp_code(""), "",
		"empty library path emits no registration")
	_expect_equal(IOS_MANIFEST_SCRIPT.registration_cpp_code(
		"user://no_such_dir_anywhere/libmoonlit_identity.debug.a"), "",
		"absent library emits no registration")
	var lib: String = "user://registration_fixture.a"
	_write_text(lib, "fake archive\n")
	var code: String = IOS_MANIFEST_SCRIPT.registration_cpp_code(lib)
	_expect_true(not code.is_empty(),
		"present library emits registration")
	_expect_true(code.contains(
		"extern \"C\" unsigned char " + entry
		+ "(void *, void *, void *);"),
		"snippet preserves the C entry declaration")
	_expect_true(not code.contains("__asm__"),
		"snippet needs no asm label at namespace scope")
	_expect_true(code.contains("(void *)&" + entry),
		"snippet takes the entry address so the link retains it")
	_expect_true(code.contains(
		"register_dynamic_symbol((char *)\"" + entry + "\""),
		"snippet registers the entry by its exact name")
	_expect_true(code.contains(
		"extern void register_dynamic_symbol(char *, void *);"),
		"snippet declares the engine registrar")
	_expect_true(code.contains(
		"add_apple_embedded_platform_init_callback(moonlit_identity_register_entry)"),
		"snippet queues the registration for the engine init stage")
	_expect_true(code.contains("struct MoonlitIdentityInitRegistrar"),
		"snippet carries a startup registrar")
	_expect_true(code.find("static void moonlit_identity_register_entry()")
		< code.find("register_dynamic_symbol((char *)"),
		"symbol-table write lives in the deferred callback")
	_expect_true(not code.contains("godot_apple_embedded_plugins_initialize"),
		"snippet never duplicates the generated init function")
	_expect_true(not code.contains("#include"),
		"snippet needs no headers")
	var statements: Array[String] = []
	for line in code.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("//"):
			continue
		statements.append(stripped)
	_expect_true(not "\n".join(statements).contains("GDExtension")
		and not "\n".join(statements).contains("godot::"),
		"snippet statements name no engine types")
	var calls: int = 0
	for stripped in statements:
		if stripped.contains(entry + "(") \
				and not stripped.begins_with("extern"):
			calls += 1
	_expect_equal(calls, 0, "snippet declares but never calls the entry")
	var descriptor: String = _read_text(
		"res://addons/moonlit-identity/ios/moonlit_identity.gdextension.ios")
	_expect_true(descriptor.contains("entry_symbol = \"" + entry + "\""),
		"snippet entry matches the descriptor")
	var listed: String = COMPOSER_SCRIPT.compose()
	_expect_true(listed.contains(
		"res://addons/moonlit-identity/bin/moonlit_identity.gdextension"),
		"identity descriptor stays listed with registration")
	var iap_source: String = \
		"res://addons/godot-iap/bin/godot_iap.gdextension.ios"
	var iap_export: String = \
		"res://addons/godot-iap/bin/godot_iap.gdextension"
	if FileAccess.file_exists(iap_source):
		_expect_true(listed.contains(iap_export),
			"purchase extension stays listed with registration")
	else:
		_expect_true(not listed.contains(iap_export),
			"missing purchase descriptor stays omitted with registration")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(lib))


func _test_cpp_code_hook_fallback() -> void:
	# EditorExportPlugin cannot be instantiated outside the editor, so
	# the routing decision lives in the manifest as a pure function and
	# the real engine surface is read through ClassDB, never an instance.
	_expect_equal(IOS_MANIFEST_SCRIPT.select_cpp_code_hook(
		["add_apple_embedded_platform_cpp_code", "add_ios_cpp_code"]),
		"add_apple_embedded_platform_cpp_code",
		"modern hook wins when both exist")
	_expect_equal(IOS_MANIFEST_SCRIPT.select_cpp_code_hook(
		["add_ios_cpp_code"]),
		"add_ios_cpp_code",
		"legacy hook takes the snippet when modern is absent")
	_expect_equal(IOS_MANIFEST_SCRIPT.select_cpp_code_hook([]), "",
		"no hook selects nothing")
	var available: Array = []
	for hook in IOS_MANIFEST_SCRIPT.CPP_CODE_HOOKS:
		if ClassDB.class_has_method("EditorExportPlugin", hook):
			available.append(hook)
	_expect_equal(
		IOS_MANIFEST_SCRIPT.select_cpp_code_hook(available),
		"add_apple_embedded_platform_cpp_code",
		"running engine routes the snippet to the modern hook")


func _test_google_url_scheme_stamps_reversed_client_id() -> void:
	var fixture: String = "user://scheme_fixture.cfg"
	var client_id: String = \
		"123456789012-zyxwvutsrqponmlkjihg.apps.googleusercontent.com"
	var scheme: String = \
		"com.googleusercontent.apps.123456789012-zyxwvutsrqponmlkjihg"
	_write_text(fixture, "[google]\nios_client_id=\"" + client_id + "\"\n")
	_expect_equal(IOS_MANIFEST_SCRIPT.read_ios_client_id(fixture),
		client_id, "staged ios client id reads back")
	_expect_equal(IOS_MANIFEST_SCRIPT.google_url_scheme(fixture), scheme,
		"callback scheme is the reversed client id")
	var content: String = \
		IOS_MANIFEST_SCRIPT.plist_url_types_content(fixture)
	_expect_true(content.contains("<key>CFBundleURLTypes</key>"),
		"plist fragment names the url types key")
	_expect_true(content.contains("<string>%s</string>" % scheme),
		"plist fragment carries the reversed scheme")
	_expect_true(content.ends_with("\n"), "plist fragment ends in a newline")
	# Every defect stamps nothing: the export stays honest and Google
	# sign-in reports not_configured at runtime instead.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	_expect_equal(IOS_MANIFEST_SCRIPT.google_url_scheme(fixture), "",
		"missing config stamps no scheme")
	_write_text(fixture, "[google]\nserver_client_id=\"x\"\n")
	_expect_equal(IOS_MANIFEST_SCRIPT.google_url_scheme(fixture), "",
		"missing client id stamps no scheme")
	_expect_equal(IOS_MANIFEST_SCRIPT.plist_url_types_content(fixture),
		"", "missing client id emits no plist fragment")
	_write_text(fixture,
		"[google]\nios_client_id=\"com.example.bundle\"\n")
	_expect_equal(IOS_MANIFEST_SCRIPT.google_url_scheme(fixture), "",
		"bundle id stamps no scheme")
	_write_text(fixture,
		"[google]\nios_client_id=\"AIza-not-a-client-id\"\n")
	_expect_equal(IOS_MANIFEST_SCRIPT.google_url_scheme(fixture), "",
		"api key stamps no scheme")
	_write_text(fixture, "not a config {{{{")
	_expect_equal(IOS_MANIFEST_SCRIPT.google_url_scheme(fixture), "",
		"corrupt config stamps no scheme")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))


func _test_plist_hook_fallback() -> void:
	_expect_equal(IOS_MANIFEST_SCRIPT.select_plist_content_hook(
		["add_apple_embedded_platform_plist_content",
			"add_ios_plist_content"]),
		"add_apple_embedded_platform_plist_content",
		"modern plist hook wins when both exist")
	_expect_equal(IOS_MANIFEST_SCRIPT.select_plist_content_hook(
		["add_ios_plist_content"]),
		"add_ios_plist_content",
		"legacy plist hook takes the fragment when modern is absent")
	_expect_equal(IOS_MANIFEST_SCRIPT.select_plist_content_hook([]), "",
		"no plist hook selects nothing")
	var available: Array = []
	for hook in IOS_MANIFEST_SCRIPT.PLIST_CONTENT_HOOKS:
		if ClassDB.class_has_method("EditorExportPlugin", hook):
			available.append(hook)
	_expect_equal(
		IOS_MANIFEST_SCRIPT.select_plist_content_hook(available),
		"add_apple_embedded_platform_plist_content",
		"running engine routes the fragment to the modern hook")


func _make_fixture_dir(path: String) -> void:
	var error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path))
	_expect_equal(error, OK, "fixture dir created " + path)


func _remove_tree(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	for dir in DirAccess.get_directories_at(path):
		_remove_tree(path + "/" + dir)
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(absolute + "/" + file)
	DirAccess.remove_absolute(absolute)


func _full_android_config() -> Dictionary:
	return {
		"google": {
			"server_client_id": "public-client-id",
			"play_app_id": "123456789012",
		},
		"apple": {
			"android_enabled": "true",
		},
		"firebase": {
			"project_id": "demo-project",
			"sender_id": "123456789012",
			"android_api_key": "AIza-test-android-key",
			"android_app_id": "1:123456789012:android:abcdef",
			"ios_api_key": "AIza-test-ios-key",
			"ios_app_id": "1:123456789012:ios:abcdef",
		},
	}


func _full_ios_config() -> Dictionary:
	# No services id anywhere: the native sheet needs the acknowledged
	# entitlement plus Firebase client config, never a web services id.
	return {
		"google": {
			"ios_client_id":
			"123456789012-zyxwvutsrqponmlkjihg.apps.googleusercontent.com",
		},
		"apple": {
			"ios_enabled": "true",
		},
		"firebase": {
			"project_id": "demo-project",
			"sender_id": "123456789012",
			"ios_api_key": "AIza-test-ios-key",
			"ios_app_id": "1:123456789012:ios:abcdef",
		},
	}


func _wait_for(bucket: Array, want: int, timeout_sec: float) -> void:
	var start_msec: int = Time.get_ticks_msec()
	while bucket.size() < want \
			and Time.get_ticks_msec() - start_msec < timeout_sec * 1000.0:
		await process_frame


func _write_text(path: String, text: String) -> void:
	var writer: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(text)
	writer.close()


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _read_id_from(path: String) -> String:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return ""
	return str(config.get_value("identity", "public_id", ""))


func _remove_save_target() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = ProjectSettings.globalize_path(
			SAVE_PATH + suffix)
		if FileAccess.file_exists(SAVE_PATH + suffix):
			DirAccess.remove_absolute(path)


## The refusal test below is the only case in this suite that adopts UID
## bindings, so it wipes the default bindings file alongside the identity
## file. Every fake guest shares one anonymous UID, and a leftover binding
## from the previous refusal would turn the next adoption into a conflict.
func _remove_identity_and_bindings() -> void:
	_remove_save_target()
	for suffix in ["", ".tmp", ".bak"]:
		var bindings: String = "user://player_bindings.cfg" + suffix
		if FileAccess.file_exists(bindings):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(bindings))


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("  expected true: ", label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		_failed += 1
		printerr("  expected ", expected, " but got ", actual, ": ", label)
