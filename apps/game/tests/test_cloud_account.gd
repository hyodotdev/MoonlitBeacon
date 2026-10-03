extends SceneTree

## Cloud account deletion ordering and per-UID local store tests. No network:
## the transport runs against a scripted fake sender. Local files land in the
## runner-isolated user:// and are removed afterwards.

const TRANSPORT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_transport.gd")
const ACCOUNT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_account.gd")
const LOCAL_STORE_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_local_store.gd")
const FAKE_SENDER_SCRIPT: Script = preload(
	"res://tests/support/fake_cloud_sender.gd")

const PROJECT_ID: String = "moonlitbeacon-778ee"
const TOKEN: String = "test-id-token-abc"
const UID: String = "uid-delete-001"
const PUBLIC_ID: String = "MB-fedcba9876543210fedcba9876543210"

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path(
		"user://").simplify_path()
	if expected_root.is_empty() or not user_root.begins_with(
			expected_root + "/"):
		printerr("cloud account tests aborted: user:// path is not isolated — ",
			user_root)
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	await _test_deletion_plan_order()
	await _test_full_deletion_is_one_atomic_commit()
	await _test_missing_rows_are_commit_no_ops()
	await _test_failure_applies_nothing()
	await _test_offline_reports_remaining()
	_test_local_store_round_trip()
	_test_local_store_rejects_unsafe_uids()
	_cleanup_local_files()
	if _failed > 0:
		printerr("cloud account tests failed — ", _failed, "/", _checked,
			" cases")
		quit(1)
		return
	print("cloud account tests passed — ", _checked, " cases")
	quit(0)


func _new_transport(sender: RefCounted) -> RefCounted:
	var transport: RefCounted = TRANSPORT_SCRIPT.new()
	transport.call("configure", PROJECT_ID, "web-key",
		func() -> String: return TOKEN, sender.call("sender_callable"))
	transport.call("set_account_uid", UID)
	return transport


func _test_deletion_plan_order() -> void:
	var plan: Array = ACCOUNT_SCRIPT.deletion_plan(UID, PUBLIC_ID)
	var steps: Array[String] = []
	for entry in plan:
		steps.append(str((entry as Dictionary).get("step", "")))
	_expect_equal(steps,
		["hall", "checkpoint", "reservation", "profile"],
		"deletion runs Hall first and profile last")
	_expect_true(str((plan[0] as Dictionary).get("path", "")).contains(
		"mb_hall_v1/%s" % PUBLIC_ID), "Hall step targets the public row")
	_expect_true(str((plan[3] as Dictionary).get("path", "")).contains(
		"mb_profiles_v1/%s" % UID), "profile step targets the UID row")


func _test_full_deletion_is_one_atomic_commit() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", "{\"writeResults\":[{},{},{},{}]}")
	var account: RefCounted = ACCOUNT_SCRIPT.new()
	var result: Dictionary = await account.call("delete_account_data",
		_new_transport(sender), UID, PUBLIC_ID)
	_expect_equal(result.get("status", ""), "ok", "full deletion ok")
	_expect_equal(result.get("completed", []),
		["hall", "checkpoint", "reservation", "profile"],
		"all four steps complete together")
	_expect_equal(result.get("remaining", []), [],
		"acknowledged commit leaves nothing remaining")
	_expect_equal(sender.calls.size(), 1, "one commit, never four deletes")
	var call: Dictionary = sender.call("last_call")
	_expect_equal(call.get("method", ""), "POST", "deletion commits via POST")
	_expect_true(str(call.get("url", "")).contains("documents:commit"),
		"deletion hits the commit endpoint")
	var writes: Array = JSON.parse_string(str(call.get("body", ""))).get(
		"writes", [])
	_expect_equal(writes.size(), 4, "commit carries all four deletes")
	var names: Array[String] = []
	for write in writes:
		names.append(str((write as Dictionary).get("delete", "")))
	_expect_true(names[0].contains("mb_hall_v1/%s" % PUBLIC_ID),
		"Hall row deleted in the commit")
	_expect_true(names[1].contains("mb_checkpoints_v1/%s" % UID),
		"checkpoint deleted in the commit")
	_expect_true(names[2].contains("mb_reservations_v1/%s" % PUBLIC_ID),
		"reservation deleted in the commit")
	_expect_true(names[3].contains("mb_profiles_v1/%s" % UID),
		"profile deleted in the commit")
	for write in writes:
		_expect_false((write as Dictionary).has("currentDocument"),
			"no preconditions: missing rows are server no-ops")


func _test_missing_rows_are_commit_no_ops() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", "{\"writeResults\":[{},{},{},{}]}")
	var account: RefCounted = ACCOUNT_SCRIPT.new()
	var result: Dictionary = await account.call("delete_account_data",
		_new_transport(sender), UID, PUBLIC_ID)
	_expect_equal(result.get("status", ""), "ok",
		"repeat over missing rows still finishes ok")
	_expect_equal((result.get("completed", []) as Array).size(), 4,
		"missing rows count as completed")
	_expect_equal(sender.calls.size(), 1,
		"repeat deletion is still a single commit")


func _test_failure_applies_nothing() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 400,
		"body": "bad"})
	var account: RefCounted = ACCOUNT_SCRIPT.new()
	var result: Dictionary = await account.call("delete_account_data",
		_new_transport(sender), UID, PUBLIC_ID)
	_expect_equal(result.get("status", ""), "failure",
		"failed commit reports failure, never partial success")
	_expect_equal(result.get("code", ""), "bad-request",
		"failure keeps its explicit code")
	_expect_equal(result.get("completed", []), [],
		"atomic failure completes nothing: no stranded profile")
	_expect_equal(result.get("remaining", []),
		["hall", "checkpoint", "reservation", "profile"],
		"all four steps remain for a clean retry")


func _test_offline_reports_remaining() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var account: RefCounted = ACCOUNT_SCRIPT.new()
	var result: Dictionary = await account.call("delete_account_data",
		_new_transport(sender), UID, PUBLIC_ID)
	_expect_equal(result.get("status", ""), "offline",
		"offline deletion reports offline")
	_expect_equal(result.get("completed", []), [],
		"offline completes nothing")
	_expect_equal((result.get("remaining", []) as Array).size(), 4,
		"offline keeps all four steps remaining")


func _test_local_store_round_trip() -> void:
	var store: RefCounted = LOCAL_STORE_SCRIPT.new()
	var saved: Dictionary = store.call("save_local", UID, "{\"gate\":2}", 2)
	_expect_true(bool(saved.get("ok", false)), "local save ok")
	var loaded: Dictionary = store.call("load_local", UID)
	_expect_true(bool(loaded.get("ok", false)), "local load ok")
	_expect_equal(loaded.get("payload", ""), "{\"gate\":2}",
		"local payload round-trips")
	_expect_equal(loaded.get("revision", 0), 2, "local revision round-trips")
	store.call("delete_local", UID)
	var missing: Dictionary = store.call("load_local", UID)
	_expect_equal(missing.get("error", ""), "not-found",
		"deleted local file reads as not-found")


func _test_local_store_rejects_unsafe_uids() -> void:
	_expect_equal(LOCAL_STORE_SCRIPT.safe_uid_token("../../secret"), "h_" +
		"../../secret".sha256_text().substr(0, 32),
		"path traversal UID becomes a hash token")
	_expect_equal(LOCAL_STORE_SCRIPT.safe_uid_token("plain-uid_9"),
		"plain-uid_9", "plain UID stays readable in the file name")
	var store: RefCounted = LOCAL_STORE_SCRIPT.new()
	var saved: Dictionary = store.call("save_local", "a/b", "{\"gate\":1}",
		1)
	_expect_true(bool(saved.get("ok", false)), "unsafe UID still saves")
	_expect_false(str(saved.get("path", "")).contains("/b."),
		"unsafe UID never escapes the file name")
	store.call("delete_local", "a/b")


func _cleanup_local_files() -> void:
	var store: RefCounted = LOCAL_STORE_SCRIPT.new()
	store.call("delete_local", UID)
	store.call("delete_local", "a/b")


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
