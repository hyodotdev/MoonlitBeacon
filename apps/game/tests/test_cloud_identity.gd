extends SceneTree

## Cloud identity registration, restore, and account-switch tests. No network:
## the transport runs against a scripted fake sender.

const TRANSPORT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_transport.gd")
const IDENTITY_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_identity.gd")
const SCHEMA_SCRIPT: Script = preload("res://scripts/cloud/cloud_schema.gd")
const LOCAL_STORE_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_local_store.gd")
const FAKE_SENDER_SCRIPT: Script = preload(
	"res://tests/support/fake_cloud_sender.gd")

const PROJECT_ID: String = "moonlitbeacon-778ee"
const TOKEN: String = "test-id-token-abc"
const UID_A: String = "uid-alice-001"
const UID_B: String = "uid-bob-002"

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path(
		"user://").simplify_path()
	if expected_root.is_empty() or not user_root.begins_with(
			expected_root + "/"):
		printerr("cloud identity tests aborted: user:// path is not isolated — ",
			user_root)
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	await _test_candidate_shape_and_bodies()
	await _test_first_registration()
	await _test_canonical_restore()
	await _test_collision_retries_with_fresh_candidate()
	await _test_conflict_then_canonical_wins()
	await _test_taken_ids_are_never_claimed()
	await _test_guest_id_reservation()
	await _test_guest_link_keeps_identity()
	await _test_offline_claims_nothing()
	await _test_account_switch_preserves_local_journeys()
	_cleanup_local_files()
	if _failed > 0:
		printerr("cloud identity tests failed — ", _failed, "/", _checked,
			" cases")
		quit(1)
		return
	print("cloud identity tests passed — ", _checked, " cases")
	quit(0)


func _new_transport(sender: RefCounted) -> RefCounted:
	var transport: RefCounted = TRANSPORT_SCRIPT.new()
	transport.call("configure", PROJECT_ID, "web-key",
		func() -> String: return TOKEN, sender.call("sender_callable"))
	transport.call("set_account_uid", UID_A)
	return transport


func _profile_get_body(uid: String, public_id: String) -> String:
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


func _test_candidate_shape_and_bodies() -> void:
	var identity: RefCounted = IDENTITY_SCRIPT.new()
	identity.call("_test_set_seed", 7)
	var first: String = str(identity.call("make_candidate_id"))
	var second: String = str(identity.call("make_candidate_id"))
	_expect_true(SCHEMA_SCRIPT.is_valid_public_id(first),
		"candidate carries MB- plus 32 lowercase hex")
	_expect_false(first == second, "consecutive candidates differ")
	_expect_false(SCHEMA_SCRIPT.is_valid_public_id("MB-" + "A".repeat(32)),
		"uppercase hex is rejected")
	_expect_false(SCHEMA_SCRIPT.is_valid_public_id("MB-short"),
		"short tail is rejected")

	var commit: Dictionary = identity.call("registration_commit_body", UID_A,
		first)
	var writes: Array = commit.get("writes", [])
	_expect_equal(writes.size(), 2,
		"registration commits profile plus reservation atomically")
	_expect_false(bool((writes[0] as Dictionary).get("currentDocument", {})
		.get("exists", true)), "profile write requires absence")
	_expect_false(bool((writes[1] as Dictionary).get("currentDocument", {})
		.get("exists", true)), "reservation write requires absence")
	var profile_name: String = str((writes[0] as Dictionary).get("update", {})
		.get("name", ""))
	var reservation_name: String = str((writes[1] as Dictionary).get(
		"update", {}).get("name", ""))
	_expect_true(profile_name.contains("mb_profiles_v1/%s" % UID_A),
		"profile document is keyed by UID")
	_expect_true(reservation_name.contains("mb_reservations_v1/%s" % first),
		"reservation document is keyed by public ID")


func _test_first_registration() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var identity: RefCounted = IDENTITY_SCRIPT.new()
	identity.call("_test_set_seed", 11)
	var result: Dictionary = await identity.call("register_or_restore",
		_new_transport(sender), UID_A)
	_expect_equal(result.get("status", ""), "ok", "first registration ok")
	_expect_false(bool(result.get("restored", true)),
		"first registration is not a restore")
	_expect_true(SCHEMA_SCRIPT.is_valid_public_id(
		str(result.get("public_id", ""))), "registered ID is well formed")
	_expect_equal(sender.calls.size(), 2, "read then one atomic commit")
	_expect_equal(identity.call("active_public_id"),
		str(result.get("public_id", "")), "active ID cached after register")


func _test_canonical_restore() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var canonical: String = "MB-" + "c".repeat(32)
	sender.call("queue_ok", _profile_get_body(UID_A, canonical))
	var identity: RefCounted = IDENTITY_SCRIPT.new()
	var result: Dictionary = await identity.call("register_or_restore",
		_new_transport(sender), UID_A)
	_expect_equal(result.get("status", ""), "ok", "restore ok")
	_expect_true(bool(result.get("restored", false)), "restore is labeled")
	_expect_equal(result.get("public_id", ""), canonical,
		"restore returns the canonical ID")
	_expect_equal(sender.calls.size(), 1, "restore commits nothing")


func _test_collision_retries_with_fresh_candidate() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_reply", {"transport": "ok", "code": 409,
		"body": "exists"})
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var identity: RefCounted = IDENTITY_SCRIPT.new()
	identity.call("_test_set_seed", 23)
	var result: Dictionary = await identity.call("register_or_restore",
		_new_transport(sender), UID_A)
	_expect_equal(result.get("status", ""), "ok",
		"reservation collision retries before success")
	_expect_equal(result.get("attempts", 0), 2, "second candidate succeeds")
	var first_commit: String = str((sender.calls[1] as Dictionary).get(
		"body", ""))
	var second_commit: String = str((sender.calls[3] as Dictionary).get(
		"body", ""))
	_expect_false(first_commit == second_commit,
		"retry uses a fresh candidate ID")
	_expect_equal(sender.calls.size(), 4, "read, commit, recheck, commit")


func _test_conflict_then_canonical_wins() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var canonical: String = "MB-" + "d".repeat(32)
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_reply", {"transport": "ok", "code": 409,
		"body": "exists"})
	sender.call("queue_ok", _profile_get_body(UID_A, canonical))
	var identity: RefCounted = IDENTITY_SCRIPT.new()
	identity.call("_test_set_seed", 29)
	var result: Dictionary = await identity.call("register_or_restore",
		_new_transport(sender), UID_A)
	_expect_equal(result.get("status", ""), "ok",
		"conflict plus existing profile restores")
	_expect_true(bool(result.get("restored", false)),
		"another device winning the race restores as canonical")
	_expect_equal(result.get("public_id", ""), canonical,
		"canonical ID from the winning registration is returned")


func _test_taken_ids_are_never_claimed() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	# Every candidate collides and no profile ever appears: all IDs belong to
	# other UIDs, so registration must exhaust retries, never return one.
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	for _index in IDENTITY_SCRIPT.MAX_REGISTRATION_ATTEMPTS:
		sender.call("queue_reply", {"transport": "ok", "code": 409,
			"body": "exists"})
		sender.call("queue_reply", {"transport": "ok", "code": 404,
			"body": "missing"})
	var identity: RefCounted = IDENTITY_SCRIPT.new()
	identity.call("_test_set_seed", 31)
	var result: Dictionary = await identity.call("register_or_restore",
		_new_transport(sender), UID_A)
	_expect_equal(result.get("status", ""), "failure",
		"endless collisions fail instead of claiming")
	_expect_equal(result.get("code", ""), "id-collision-exhausted",
		"exhaustion has its own code")
	_expect_false(result.has("public_id"),
		"no foreign ID is ever returned as ours")


func _test_guest_id_reservation() -> void:
	var guest: String = "MB-" + "1".repeat(32)
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{},{}]}")
	var identity: RefCounted = IDENTITY_SCRIPT.new()
	var reserved: Dictionary = await identity.call(
		"register_or_restore_with_guest_id", _new_transport(sender),
		UID_A, guest)
	_expect_equal(reserved.get("public_id", ""), guest,
		"a new UID reserves the supplied guest ID verbatim")
	_expect_equal(reserved.get("requested", ""), guest,
		"the reservation echoes the request")
	var commit: String = str((sender.calls[1] as Dictionary).get("body", ""))
	_expect_true(commit.contains(guest),
		"the single commit carries the guest ID")
	_expect_equal(sender.calls.size(), 2, "read then one atomic commit")

	var taken: RefCounted = FAKE_SENDER_SCRIPT.new()
	taken.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	taken.call("queue_reply", {"transport": "ok", "code": 409,
		"body": "exists"})
	taken.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	var identity_b: RefCounted = IDENTITY_SCRIPT.new()
	var collided: Dictionary = await identity_b.call(
		"register_or_restore_with_guest_id", _new_transport(taken),
		UID_B, guest)
	_expect_equal(collided.get("status", ""), "conflict",
		"a taken guest ID reports a conflict")
	_expect_equal(collided.get("code", ""), "guest-id-taken",
		"the collision has its own explicit code")
	_expect_false(collided.has("public_id"),
		"no silent replacement ID is ever returned")
	_expect_equal(taken.calls.size(), 3,
		"one commit attempt only, then the explicit collision")

	var canonical: String = "MB-" + "c".repeat(32)
	var restoring: RefCounted = FAKE_SENDER_SCRIPT.new()
	restoring.call("queue_ok", _profile_get_body(UID_A, canonical))
	var identity_c: RefCounted = IDENTITY_SCRIPT.new()
	var restored: Dictionary = await identity_c.call(
		"register_or_restore_with_guest_id", _new_transport(restoring),
		UID_A, guest)
	_expect_equal(restored.get("public_id", ""), canonical,
		"an existing UID returns its canonical ID explicitly")
	_expect_true(bool(restored.get("restored", false)),
		"the canonical return is labeled a restore")

	var bad_guest: RefCounted = FAKE_SENDER_SCRIPT.new()
	var identity_d: RefCounted = IDENTITY_SCRIPT.new()
	var refused: Dictionary = await identity_d.call(
		"register_or_restore_with_guest_id", _new_transport(bad_guest),
		UID_A, "not-an-id")
	_expect_equal(refused.get("code", ""), "invalid-guest-id",
		"a malformed guest ID is refused before any request")
	_expect_equal(bad_guest.calls.size(), 0, "the refusal sends nothing")


func _test_guest_link_keeps_identity() -> void:
	# Linking a guest to a provider keeps the Firebase UID, so the profile
	# lookup returns the same public ID with no new reservation.
	var canonical: String = "MB-" + "e".repeat(32)
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _profile_get_body(UID_A, canonical))
	var identity: RefCounted = IDENTITY_SCRIPT.new()
	var before: Dictionary = await identity.call("fetch_canonical_id",
		_new_transport(sender), UID_A)
	sender.call("queue_ok", _profile_get_body(UID_A, canonical))
	var after: Dictionary = await identity.call("fetch_canonical_id",
		_new_transport(sender), UID_A)
	_expect_equal(before.get("public_id", ""), canonical,
		"guest ID before link")
	_expect_equal(after.get("public_id", ""), canonical,
		"same UID keeps the same ID after link")
	for call in sender.calls:
		_expect_false(str((call as Dictionary).get("body", "")).contains(
			"google"),
			"identity requests never carry provider names")


func _test_offline_claims_nothing() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var identity: RefCounted = IDENTITY_SCRIPT.new()
	var result: Dictionary = await identity.call("register_or_restore",
		_new_transport(sender), UID_A)
	_expect_equal(result.get("status", ""), "offline",
		"offline registration reports offline")
	_expect_false(result.has("public_id"),
		"offline work never claims a globally reserved ID")
	_expect_equal(str(identity.call("active_public_id")), "",
		"no active ID cached while offline")


func _test_account_switch_preserves_local_journeys() -> void:
	var store: RefCounted = LOCAL_STORE_SCRIPT.new()
	var saved_a: Dictionary = store.call("save_local", UID_A,
		"{\"gate\":3,\"cycle\":5}", 5)
	var saved_b: Dictionary = store.call("save_local", UID_B,
		"{\"gate\":1,\"cycle\":1}", 1)
	_expect_true(bool(saved_a.get("ok", false)), "local journey A saved")
	_expect_true(bool(saved_b.get("ok", false)), "local journey B saved")
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var transport: RefCounted = _new_transport(sender)
	var identity: RefCounted = IDENTITY_SCRIPT.new()
	identity.call("switch_account", transport, UID_A)
	identity.call("switch_account", transport, UID_B)
	_expect_equal(transport.call("account_uid"), UID_B,
		"transport follows the new account")
	_expect_equal(identity.call("active_uid"), UID_B,
		"identity follows the new account")
	var reloaded_a: Dictionary = store.call("load_local", UID_A)
	var reloaded_b: Dictionary = store.call("load_local", UID_B)
	_expect_true(bool(reloaded_a.get("ok", false)),
		"prior account file survives the switch")
	_expect_equal(reloaded_a.get("payload", ""), "{\"gate\":3,\"cycle\":5}",
		"prior account payload byte-identical after switch")
	_expect_equal(reloaded_b.get("payload", ""), "{\"gate\":1,\"cycle\":1}",
		"new account payload untouched by the switch")


func _cleanup_local_files() -> void:
	var store: RefCounted = LOCAL_STORE_SCRIPT.new()
	store.call("delete_local", UID_A)
	store.call("delete_local", UID_B)


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
