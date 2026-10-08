extends SceneTree

## Adventurer name claim, restore, and intro-bit tests. No network: the
## transport runs against a scripted fake sender.

const TRANSPORT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_transport.gd")
const NAME_SCRIPT: Script = preload("res://scripts/cloud/cloud_name.gd")
const SCHEMA_SCRIPT: Script = preload("res://scripts/cloud/cloud_schema.gd")
const FAKE_SENDER_SCRIPT: Script = preload(
	"res://tests/support/fake_cloud_sender.gd")

const PROJECT_ID: String = "moonlitbeacon-778ee"
const TOKEN: String = "test-id-token-abc"
const UID_A: String = "uid-alice-001"
const PUBLIC_A: String = "MB-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_normalization_matrix()
	await _test_claim_body_shape()
	await _test_first_claim()
	await _test_restore_existing()
	await _test_taken_name()
	await _test_uncertain_ack_recovers()
	await _test_invalid_name_fails_fast()
	await _test_permission_denied_is_not_taken()
	await _test_offline_claims_nothing()
	await _test_mismatched_adventurer_never_adopted()
	await _test_double_claim_converges()
	await _test_intro_complete_idempotent()
	await _test_intro_without_claim()
	await _test_missing_transport()
	if _failed > 0:
		printerr("cloud name tests failed — ", _failed, "/", _checked,
			" cases")
		quit(1)
		return
	print("cloud name tests passed — ", _checked, " cases")
	quit(0)


func _new_transport(sender: RefCounted) -> RefCounted:
	var transport: RefCounted = TRANSPORT_SCRIPT.new()
	transport.call("configure", PROJECT_ID, "web-key",
		func() -> String: return TOKEN, sender.call("sender_callable"))
	transport.call("set_account_uid", UID_A)
	return transport


func _adventurer_get_body(uid: String, public_id: String, display: String,
		key: String, intro_complete: bool) -> String:
	return JSON.stringify({
		"name": "projects/%s/databases/(default)/documents/mb_adventurers_v1/%s"
			% [PROJECT_ID, public_id],
		"fields": {
			"public_id": {"stringValue": public_id},
			"uid": {"stringValue": uid},
			"name_key": {"stringValue": key},
			"display": {"stringValue": display},
			"intro_complete": {"booleanValue": intro_complete},
			"schema": {"integerValue": "1"},
			"created_at": {"timestampValue": "2026-10-01T00:00:00Z"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
		},
	})


func _test_normalization_matrix() -> void:
	var valid: Array = [
		["Luna", "Luna", "luna"],
		["  Abby  ", "Abby", "abby"],
		["Moon Knight", "Moon Knight", "moon knight"],
		["a1_", "a1_", "a1_"],
		["ab", "ab", "ab"],
		["abcdefghijkl", "abcdefghijkl", "abcdefghijkl"],
		["루나", "루나", "루나"],
		["달빛기사단", "달빛기사단", "달빛기사단"],
		["ルミー", "ルミー", "ルミー"],
		["ひかり", "ひかり", "ひかり"],
		["月光", "月光", "月光"],
		["Moon月光_1", "Moon月光_1", "moon月光_1"],
	]
	for row in valid:
		var result: Dictionary = SCHEMA_SCRIPT.normalize_adventurer_name(
			str(row[0]))
		_expect_true(bool(result.get("ok", false)),
			"names accept " + str(row[0]))
		_expect_equal(str(result.get("display", "")), str(row[1]),
			"display keeps " + str(row[0]))
		_expect_equal(str(result.get("key", "")), str(row[2]),
			"key folds " + str(row[0]))
	var invalid: Array[String] = [
		"", " ", "a", "abcdefghijklm", " A", "A ", "A  B",
		"a/b", "a\\b", "a.b", "a-b", "a\tb", "a\nb",
		"é", "e" + String.chr(0x0301), "ㅎㅎ", "😀ab", "ＡＢ", "・ab",
		String.chr(0x00A0) + "Moon", "Moon" + String.chr(0x00A0),
		"Mo" + String.chr(0x00A0) + "on",
	]
	for raw in invalid:
		var result: Dictionary = SCHEMA_SCRIPT.normalize_adventurer_name(
			raw)
		_expect_false(bool(result.get("ok", true)),
			"names reject " + JSON.stringify(raw))
		_expect_equal(str(result.get("error", "")), "invalid-name",
			"rejection names invalid-name")


func _test_claim_body_shape() -> void:
	var names: RefCounted = NAME_SCRIPT.new()
	var body: Dictionary = names.call("claim_commit_body",
		UID_A, PUBLIC_A, "루나", "루나")
	var writes: Array = body.get("writes", [])
	_expect_equal(writes.size(), 2, "claim commits both halves")
	for write in writes:
		_expect_equal(str((write as Dictionary).get(
			"currentDocument", {}).get("exists", true)), "false",
			"claim halves require absence")
	var text: String = JSON.stringify(body)
	_expect_true(text.contains("루나"),
		"commit JSON carries raw Unicode, never escapes")
	_expect_false(text.contains("%"),
		"commit JSON carries no percent-encoding")
	var relative: String = str(names.call(
		"name_relative_path", "루나"))
	_expect_true(relative.contains("%") and not relative.contains("루나"),
		"request URLs encode the name segment")
	_expect_equal(relative.uri_decode(),
		"documents/mb_names_v1/루나",
		"the encoded segment decodes back exactly")


func _test_first_claim() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var names: RefCounted = NAME_SCRIPT.new()
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_ok("{\"writeResults\": [{}, {}]}")
	var claimed: Dictionary = await names.call("claim_name",
		_new_transport(sender), UID_A, PUBLIC_A, "Luna")
	_expect_equal(str(claimed.get("status", "")), "ok",
		"first claim succeeds")
	_expect_equal(str(claimed.get("display", "")), "Luna",
		"claim returns the display")
	_expect_equal(str(claimed.get("key", "")), "luna",
		"claim returns the immutable key")
	_expect_false(bool(claimed.get("restored", true)),
		"first claim is not a restore")
	_expect_false(bool(claimed.get("intro_complete", true)),
		"first claim starts the tutorial incomplete")
	_expect_equal((sender.calls as Array).size(), 2,
		"claim reads once and commits once")
	var commit: Dictionary = sender.last_call()
	_expect_true(str(commit.get("body", "")).contains("mb_names_v1"),
		"commit carries the name half")
	_expect_true(str(commit.get("body", "")).contains("mb_adventurers_v1"),
		"commit carries the adventurer half")


func _test_restore_existing() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var names: RefCounted = NAME_SCRIPT.new()
	sender.queue_ok(_adventurer_get_body(
		UID_A, PUBLIC_A, "Luna", "luna", true))
	var claimed: Dictionary = await names.call("claim_name",
		_new_transport(sender), UID_A, PUBLIC_A, "Other")
	_expect_equal(str(claimed.get("status", "")), "ok",
		"restore succeeds")
	_expect_equal(str(claimed.get("display", "")), "Luna",
		"restore returns the canonical display, not the new ask")
	_expect_true(bool(claimed.get("restored", false)),
		"restore is labeled restored")
	_expect_true(bool(claimed.get("intro_complete", false)),
		"restore returns the real completion bit")
	_expect_equal((sender.calls as Array).size(), 1,
		"restore commits nothing")


func _test_taken_name() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var names: RefCounted = NAME_SCRIPT.new()
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_reply({"transport": "ok", "code": 409, "body": "{}"})
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var claimed: Dictionary = await names.call("claim_name",
		_new_transport(sender), UID_A, PUBLIC_A, "Luna")
	_expect_equal(str(claimed.get("status", "")), "conflict",
		"taken name conflicts")
	_expect_equal(str(claimed.get("code", "")), "name-taken",
		"taken name names name-taken")
	_expect_equal(str(claimed.get("key", "")), "luna",
		"taken name echoes the losing key")


func _test_uncertain_ack_recovers() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var names: RefCounted = NAME_SCRIPT.new()
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_reply({"transport": "ok", "code": 409, "body": "{}"})
	sender.queue_ok(_adventurer_get_body(
		UID_A, PUBLIC_A, "Luna", "luna", false))
	var claimed: Dictionary = await names.call("claim_name",
		_new_transport(sender), UID_A, PUBLIC_A, "Luna")
	_expect_equal(str(claimed.get("status", "")), "ok",
		"uncertain ack recovers")
	_expect_true(bool(claimed.get("restored", false)),
		"uncertain ack restores the landed row")
	_expect_equal(str(claimed.get("display", "")), "Luna",
		"uncertain ack returns the canonical display")
	_expect_false(bool(claimed.get("intro_complete", true)),
		"uncertain ack carries the landed row's bit")


func _test_invalid_name_fails_fast() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var names: RefCounted = NAME_SCRIPT.new()
	var claimed: Dictionary = await names.call("claim_name",
		_new_transport(sender), UID_A, PUBLIC_A, "a/b")
	_expect_equal(str(claimed.get("status", "")), "failure",
		"invalid name fails")
	_expect_equal(str(claimed.get("code", "")), "invalid-name",
		"invalid name names invalid-name")
	_expect_true((sender.calls as Array).is_empty(),
		"invalid name sends nothing")


func _test_permission_denied_is_not_taken() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var names: RefCounted = NAME_SCRIPT.new()
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_reply(
		{"transport": "ok", "code": 403, "body": "denied"})
	var claimed: Dictionary = await names.call("claim_name",
		_new_transport(sender), UID_A, PUBLIC_A, "Luna")
	_expect_equal(str(claimed.get("status", "")), "failure",
		"denied commit fails")
	_expect_equal(str(claimed.get("code", "")), "permission-denied",
		"denied commit is never renamed to taken")
	sender.reset()
	sender.queue_reply(
		{"transport": "ok", "code": 403, "body": "denied"})
	var loaded: Dictionary = await names.call("fetch_adventurer",
		_new_transport(sender), UID_A, PUBLIC_A)
	_expect_equal(str(loaded.get("code", "")), "permission-denied",
		"denied read stays permission-denied")

	sender.reset()
	sender.queue_reply(
		{"transport": "ok", "code": 403, "body": "denied"})
	var blocked: Dictionary = await names.call("claim_name",
		_new_transport(sender), UID_A, PUBLIC_A, "Luna")
	_expect_equal(str(blocked.get("status", "")), "failure",
		"denied first read fails the claim")
	_expect_equal(str(blocked.get("code", "")), "permission-denied",
		"denied first read is never renamed to taken")
	_expect_equal((sender.calls as Array).size(), 1,
		"denied first read never reaches the commit")

	sender.reset()
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_reply({"transport": "ok", "code": 409, "body": "{}"})
	sender.queue_reply(
		{"transport": "ok", "code": 403, "body": "denied"})
	var recheck: Dictionary = await names.call("claim_name",
		_new_transport(sender), UID_A, PUBLIC_A, "Luna")
	_expect_equal(str(recheck.get("status", "")), "failure",
		"denied recheck after conflict fails")
	_expect_equal(str(recheck.get("code", "")), "permission-denied",
		"denied recheck is never renamed to taken")


func _test_offline_claims_nothing() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var names: RefCounted = NAME_SCRIPT.new()
	sender.queue_reply({"transport": "offline", "code": 0, "body": ""})
	var claimed: Dictionary = await names.call("claim_name",
		_new_transport(sender), UID_A, PUBLIC_A, "Luna")
	_expect_equal(str(claimed.get("status", "")), "offline",
		"offline claim reports offline")
	_expect_equal((sender.calls as Array).size(), 1,
		"offline claim never reaches the commit")


func _test_mismatched_adventurer_never_adopted() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var names: RefCounted = NAME_SCRIPT.new()
	sender.queue_ok(_adventurer_get_body(
		"uid-eve-999", PUBLIC_A, "Luna", "luna", false))
	var wrong_uid: Dictionary = await names.call("fetch_adventurer",
		_new_transport(sender), UID_A, PUBLIC_A)
	_expect_equal(str(wrong_uid.get("code", "")), "adventurer-mismatch",
		"another UID's row is never adopted")
	sender.reset()
	sender.queue_ok(_adventurer_get_body(
		UID_A, "MB-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
		"Luna", "luna", false))
	var wrong_id: Dictionary = await names.call("fetch_adventurer",
		_new_transport(sender), UID_A, PUBLIC_A)
	_expect_equal(str(wrong_id.get("code", "")), "adventurer-mismatch",
		"another public ID's row is never adopted")
	sender.reset()
	sender.queue_ok(_adventurer_get_body(
		UID_A, PUBLIC_A, "Luna", "bob", false))
	var wrong_key: Dictionary = await names.call("fetch_adventurer",
		_new_transport(sender), UID_A, PUBLIC_A)
	_expect_equal(str(wrong_key.get("code", "")), "adventurer-mismatch",
		"a forged key is never adopted")


func _test_double_claim_converges() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var names: RefCounted = NAME_SCRIPT.new()
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	sender.queue_ok("{\"writeResults\": [{}, {}]}")
	var first: Dictionary = await names.call("claim_name",
		_new_transport(sender), UID_A, PUBLIC_A, "Luna")
	_expect_equal(str(first.get("status", "")), "ok",
		"first tap claims")
	sender.reset()
	sender.queue_ok(_adventurer_get_body(
		UID_A, PUBLIC_A, "Luna", "luna", false))
	var second: Dictionary = await names.call("claim_name",
		_new_transport(sender), UID_A, PUBLIC_A, "Luna")
	_expect_equal(str(second.get("status", "")), "ok",
		"second tap succeeds")
	_expect_true(bool(second.get("restored", false)),
		"second tap restores instead of duplicating")
	_expect_equal(str(second.get("key", "")), "luna",
		"second tap returns the same key")


func _test_intro_complete_idempotent() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var names: RefCounted = NAME_SCRIPT.new()
	sender.queue_ok(_adventurer_get_body(
		UID_A, PUBLIC_A, "Luna", "luna", false))
	sender.queue_ok("{\"writeResults\": [{}]}")
	var done: Dictionary = await names.call("mark_intro_complete",
		_new_transport(sender), UID_A, PUBLIC_A)
	_expect_equal(str(done.get("status", "")), "ok",
		"intro completes")
	_expect_true(bool(done.get("intro_complete", false)),
		"intro reports complete")
	var update: Dictionary = sender.last_call()
	_expect_true(str(update.get("body", "")).contains("\"exists\":true"),
		"intro update requires the row")
	_expect_true(str(update.get("body", "")).contains(
		"\"booleanValue\":true"),
		"intro update flips the bit")
	sender.reset()
	sender.queue_ok(_adventurer_get_body(
		UID_A, PUBLIC_A, "Luna", "luna", true))
	var again: Dictionary = await names.call("mark_intro_complete",
		_new_transport(sender), UID_A, PUBLIC_A)
	_expect_equal(str(again.get("status", "")), "ok",
		"repeat intro succeeds")
	_expect_equal((sender.calls as Array).size(), 1,
		"repeat intro writes nothing")


func _test_intro_without_claim() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var names: RefCounted = NAME_SCRIPT.new()
	sender.queue_reply({"transport": "ok", "code": 404, "body": "{}"})
	var done: Dictionary = await names.call("mark_intro_complete",
		_new_transport(sender), UID_A, PUBLIC_A)
	_expect_equal(str(done.get("code", "")), "adventurer-not-found",
		"intro without a claim reports not-found")
	_expect_equal((sender.calls as Array).size(), 1,
		"intro without a claim writes nothing")


func _test_missing_transport() -> void:
	var names: RefCounted = NAME_SCRIPT.new()
	var claimed: Dictionary = await names.call("claim_name",
		null, UID_A, PUBLIC_A, "Luna")
	_expect_equal(str(claimed.get("status", "")), "unconfigured",
		"claim without transport is unconfigured")
	var loaded: Dictionary = await names.call("fetch_adventurer",
		null, UID_A, PUBLIC_A)
	_expect_equal(str(loaded.get("status", "")), "unconfigured",
		"fetch without transport is unconfigured")


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("FAIL: ", label)


func _expect_false(value: bool, label: String) -> void:
	_checked += 1
	if value:
		_failed += 1
		printerr("FAIL: ", label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		_failed += 1
		printerr("FAIL: ", label, " — expected=", expected,
			" actual=", actual)
