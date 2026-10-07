extends SceneTree

## Attendance service contract: server-time cooldown reads, conditional
## claims, and honest already-claimed/offline/error legs. No wallet here;
## the coordinator applies acknowledged claims to the Vault exactly once.

const ATTEND_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_attendance.gd")
const SCHEMA_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_schema.gd")
const TRANSPORT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_transport.gd")
const FAKE_SENDER_SCRIPT: Script = preload(
	"res://tests/support/fake_cloud_sender.gd")

const UID_A: String = "uid-attendance-a"
const PUBLIC_A: String = "MB-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1"
const INSTALL_A: String = "install-a-001"
const INSTALL_B: String = "install-b-002"

## Fixed server clock for every reply: device time never enters.
const NOW: String = "2026-10-07T10:00:00Z"
const NOW_SECONDS: int = 1791367200
const HOURS_13_AGO: String = "2026-10-06T21:00:00Z"
const HOURS_11_AGO: String = "2026-10-06T23:00:00Z"
const EXACTLY_12H_AGO: String = "2026-10-06T22:00:00Z"
const SECOND_BEFORE_12H: String = "2026-10-06T22:00:01Z"
const DAYS_5_AGO: String = "2026-10-02T10:00:00Z"

var _checked: int = 0
var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_schema_timestamps()
	await _test_schema_cooldown_math()
	await _test_receipt_key_shape()
	await _test_first_claim()
	await _test_cooldown_claim_commits_cas()
	await _test_held_period_grants_nothing()
	await _test_cooldown_boundaries()
	await _test_no_catchup_stacking()
	await _test_conflict_converges()
	await _test_denied_stays_denied()
	await _test_malformed_server_data_fails_closed()
	await _test_invalid_inputs_send_nothing()
	await _test_advance_conflict_converges()
	await _test_prev_carry_parses()
	await _test_invalid_advance_sends_nothing()
	if _failed > 0:
		print("cloud attendance tests failed - %d/%d cases" % [
			_failed, _checked])
		quit(1)
		return
	print("cloud attendance tests passed - %d cases" % _checked)
	quit(0)


func _new_transport(sender: RefCounted) -> RefCounted:
	var transport: RefCounted = TRANSPORT_SCRIPT.new()
	transport.call("configure", "moonlitbeacon-778ee", "web-key",
		func() -> String: return "t", sender.call("sender_callable"))
	transport.call("set_account_uid", UID_A)
	return transport


func _missing_body(read_time: String = NOW) -> String:
	return JSON.stringify([{"missing": "mb_attendance_v1/x",
		"readTime": read_time}])


func _found_body(last_claim_at: String, install_id: String,
		read_time: String = NOW,
		update_time: String = "2026-10-06T21:00:00.5Z",
		prev_claim_at: String = "",
		prev_install: String = "") -> String:
	var fields: Dictionary = {
		"public_id": {"stringValue": PUBLIC_A},
		"uid": {"stringValue": UID_A},
		"install_id": {"stringValue": install_id},
		"last_claim_at": {"timestampValue": last_claim_at},
		"schema": {"integerValue": "1"},
	}
	if not prev_claim_at.is_empty():
		fields["prev_claim_at"] = {"timestampValue": prev_claim_at}
	if not prev_install.is_empty():
		fields["prev_install_id"] = {"stringValue": prev_install}
	return JSON.stringify([{
		"found": {
			"name": "mb_attendance_v1/x",
			"fields": fields,
			"updateTime": update_time,
		},
		"readTime": read_time,
	}])


func _commit_ack_body(commit_time: String = NOW) -> String:
	return JSON.stringify({"writeResults": [{}],
		"commitTime": commit_time})


func _expect_equal(actual: Variant, expected: Variant,
		label: String) -> void:
	_checked += 1
	if actual != expected:
		_failed += 1
		print("FAIL: %s - got %s, want %s" % [label, actual, expected])


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		print("FAIL: %s" % label)


func _test_schema_timestamps() -> void:
	_expect_equal(SCHEMA_SCRIPT.unix_from_rfc3339(NOW), NOW_SECONDS,
		"timestamps: the fixed clock parses")
	_expect_equal(SCHEMA_SCRIPT.unix_from_rfc3339(
		"2026-10-07T10:00:00.987654321Z"), NOW_SECONDS,
		"timestamps: fractional seconds truncate")
	_expect_equal(SCHEMA_SCRIPT.unix_from_rfc3339("garbage"), 0,
		"timestamps: garbage yields zero")
	_expect_equal(SCHEMA_SCRIPT.unix_from_rfc3339(""), 0,
		"timestamps: empty yields zero")
	_expect_equal(SCHEMA_SCRIPT.unix_from_rfc3339(
		"2026-02-30T00:00:00Z"), 0,
		"timestamps: an impossible day yields zero")
	_expect_equal(SCHEMA_SCRIPT.unix_from_rfc3339(
		"2026-13-01T00:00:00Z"), 0,
		"timestamps: a wild month yields zero")
	_expect_equal(SCHEMA_SCRIPT.unix_from_rfc3339(
		"2026-10-07T25:00:00Z"), 0,
		"timestamps: a wild hour yields zero")
	_expect_equal(SCHEMA_SCRIPT.unix_from_rfc3339(
		"2024-02-29T12:00:00Z"), 1709208000,
		"timestamps: leap day parses")
	_expect_equal(SCHEMA_SCRIPT.unix_from_rfc3339(
		"2026-10-07 10:00:00"), NOW_SECONDS,
		"timestamps: a space join parses")
	_expect_equal(SCHEMA_SCRIPT.rfc3339_from_unix(NOW_SECONDS), NOW,
		"timestamps: the fixed clock round-trips")
	_expect_equal(SCHEMA_SCRIPT.rfc3339_from_unix(
		NOW_SECONDS + 43200), "2026-10-07T22:00:00Z",
		"timestamps: the deadline formats Zulu")


func _test_schema_cooldown_math() -> void:
	var schema_now: int = NOW_SECONDS
	var just_held: Dictionary = SCHEMA_SCRIPT.attendance_cooldown(
		schema_now, schema_now - 43199)
	_expect_equal(bool(just_held.get("eligible", true)), false,
		"cooldown: one second short stays held")
	_expect_equal(int(just_held.get("remaining", 0)), 1,
		"cooldown: one second short waits one second")
	var exact: Dictionary = SCHEMA_SCRIPT.attendance_cooldown(
		schema_now, schema_now - 43200)
	_expect_equal(bool(exact.get("eligible", false)), true,
		"cooldown: exactly twelve hours is eligible")
	var future: Dictionary = SCHEMA_SCRIPT.attendance_cooldown(
		schema_now, schema_now + 60)
	_expect_equal(bool(future.get("eligible", true)), false,
		"cooldown: a future stamp never grants")
	_expect_equal(int(future.get("remaining", 0)), 43200,
		"cooldown: a future stamp waits the full period")


func _test_receipt_key_shape() -> void:
	var key: String = SCHEMA_SCRIPT.attendance_receipt_key(
		PUBLIC_A, NOW_SECONDS, INSTALL_A)
	_expect_equal(key, "attendance:%s:%d:%s" % [
		PUBLIC_A, NOW_SECONDS, INSTALL_A],
		"receipt: the key derives from row plus install")
	_expect_equal(SCHEMA_SCRIPT.attendance_key_seconds(key), NOW_SECONDS,
		"receipt: the seconds parse back")
	_expect_equal(SCHEMA_SCRIPT.attendance_key_seconds("nope"), -1,
		"receipt: garbage parses to -1")
	_expect_equal(SCHEMA_SCRIPT.attendance_key_seconds(
		"attendance:x:0:y"), -1,
		"receipt: zero seconds parses to -1")
	_expect_true(SCHEMA_SCRIPT.is_valid_install_id(INSTALL_A),
		"receipt: the test install binds")
	_expect_true(not SCHEMA_SCRIPT.is_valid_install_id(""),
		"receipt: empty install never binds")


func _first_call(sender: RefCounted) -> Dictionary:
	return (sender.calls as Array)[0]


func _test_first_claim() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	sender.queue_ok(_missing_body())
	sender.queue_ok(_commit_ack_body())
	var claimed: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(claimed.get("status", "")), "ok",
		"first claim succeeds")
	_expect_equal(int(claimed.get("claim_seconds", 0)), NOW_SECONDS,
		"first claim stamps from the commit time")
	_expect_equal(str(claimed.get("next_eligible_utc", "")),
		"2026-10-07T22:00:00Z",
		"first claim confirms the next deadline")
	_expect_equal(int(claimed.get("remaining_seconds", 0)), 43200,
		"first claim waits a full period")
	_expect_equal((sender.calls as Array).size(), 2,
		"first claim reads once and commits once")
	_expect_true(str(_first_call(sender).get("url", "")).contains(
		"documents:batchGet"), "the read uses batchGet for readTime")
	var commit: Dictionary = (sender.calls as Array)[1]
	var writes: Array = ((JSON.parse_string(
		str(commit.get("body", ""))) as Dictionary).get("writes", []))
	var write: Dictionary = writes[0]
	_expect_equal(bool((write.get("currentDocument", {}) as Dictionary
		).get("exists", true)), false,
		"first claim creates with exists:false")
	var transforms: Array = write.get("updateTransforms", [])
	_expect_equal(str((transforms[0] as Dictionary).get(
		"setToServerValue", "")), "REQUEST_TIME",
		"the stamp is server-set, never client-written")
	_expect_true(not (write.get("update", {}) as Dictionary).get(
		"fields", {}).has("last_claim_at"),
		"no client stamp rides beside the transform")
	var create_fields: Dictionary = (write.get("update", {})
		as Dictionary).get("fields", {})
	_expect_true(not create_fields.has("prev_claim_at"),
		"a first claim carries no previous stamp")
	_expect_true(not create_fields.has("prev_install_id"),
		"a first claim carries no previous install")


func _test_cooldown_claim_commits_cas() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	var fractured: String = "2026-10-06T21:00:00.123456789Z"
	sender.queue_ok(_found_body(fractured, INSTALL_B))
	var eligible: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(eligible.get("status", "")), "eligible",
		"elapsed claim reports eligible without committing")
	_expect_equal((sender.calls as Array).size(), 1,
		"eligible commits nothing before backfill")
	_expect_equal(str(eligible.get("last_claim_rfc", "")), fractured,
		"eligible carries the raw stamp opaquely")
	sender.queue_ok(_commit_ack_body())
	var claimed: Dictionary = await service.call("commit_advance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A,
		str(eligible.get("update_time", "")),
		str(eligible.get("last_claim_rfc", "")),
		str(eligible.get("install_id", "")))
	_expect_equal(str(claimed.get("status", "")), "ok",
		"elapsed advance succeeds for a new receiving install")
	var commit: Dictionary = (sender.calls as Array)[1]
	var write: Dictionary = (((JSON.parse_string(
		str(commit.get("body", ""))) as Dictionary).get("writes", []))
		as Array)[0]
	_expect_equal(str((write.get("currentDocument", {}) as Dictionary
		).get("updateTime", "")), "2026-10-06T21:00:00.5Z",
		"elapsed advance compare-and-swaps on the read updateTime")
	var fields: Dictionary = (write.get("update", {}) as Dictionary
		).get("fields", {})
	_expect_equal(str((fields.get("install_id", {}) as Dictionary).get(
		"stringValue", "")), INSTALL_A,
		"elapsed advance binds the receiving install")
	_expect_equal(str((fields.get("prev_claim_at", {}) as Dictionary
		).get("timestampValue", "")), fractured,
		"elapsed advance carries the old stamp byte for byte")
	_expect_equal(str((fields.get("prev_install_id", {}) as Dictionary
		).get("stringValue", "")), INSTALL_B,
		"elapsed advance carries the old install")


func _test_held_period_grants_nothing() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	sender.queue_ok(_found_body(HOURS_11_AGO, INSTALL_A))
	var held: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(held.get("status", "")), "already-claimed",
		"held period reports already-claimed")
	_expect_equal(int(held.get("remaining_seconds", 0)), 3600,
		"held period waits out the server remainder")
	_expect_equal(str(held.get("next_eligible_utc", "")),
		"2026-10-07T11:00:00Z",
		"held period confirms the server deadline")
	_expect_true(bool(held.get("mine", false)),
		"held period names this install as receiver")
	_expect_equal((sender.calls as Array).size(), 1,
		"held period commits nothing")
	sender.reset()
	sender.queue_ok(_found_body(HOURS_11_AGO, INSTALL_B))
	var foreign: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(foreign.get("status", "")), "already-claimed",
		"foreign-held period reports already-claimed")
	_expect_true(not bool(foreign.get("mine", true)),
		"foreign-held period names the other receiver")
	_expect_equal((sender.calls as Array).size(), 1,
		"foreign-held period commits nothing")


func _test_cooldown_boundaries() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	sender.queue_ok(_found_body(SECOND_BEFORE_12H, INSTALL_A))
	var held: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(int(held.get("remaining_seconds", 0)), 1,
		"boundary: one second short waits one second")
	_expect_equal((sender.calls as Array).size(), 1,
		"boundary: one second short commits nothing")
	sender.reset()
	sender.queue_ok(_found_body(EXACTLY_12H_AGO, INSTALL_A))
	var ready: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(ready.get("status", "")), "eligible",
		"boundary: exactly twelve hours is eligible")
	_expect_equal((sender.calls as Array).size(), 1,
		"boundary: eligibility commits nothing yet")
	sender.queue_ok(_commit_ack_body())
	var claimed: Dictionary = await service.call("commit_advance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A,
		str(ready.get("update_time", "")),
		str(ready.get("last_claim_rfc", "")),
		str(ready.get("install_id", "")))
	_expect_equal(str(claimed.get("status", "")), "ok",
		"boundary: exactly twelve hours claims")
	_expect_equal((sender.calls as Array).size(), 2,
		"boundary: exactly twelve hours commits")


func _test_no_catchup_stacking() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	sender.queue_ok(_found_body(DAYS_5_AGO, INSTALL_A))
	var ready: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(ready.get("status", "")), "eligible",
		"no stacking: a stale row reports eligible")
	sender.queue_ok(_commit_ack_body())
	var claimed: Dictionary = await service.call("commit_advance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A,
		str(ready.get("update_time", "")),
		str(ready.get("last_claim_rfc", "")),
		str(ready.get("install_id", "")))
	_expect_equal(str(claimed.get("status", "")), "ok",
		"no stacking: a stale row still claims once")
	_expect_equal(int(claimed.get("remaining_seconds", 0)), 43200,
		"no stacking: the next wait is one period, not five days")
	_expect_equal(str(claimed.get("next_eligible_utc", "")),
		"2026-10-07T22:00:00Z",
		"no stacking: the deadline counts from the new claim")


func _test_conflict_converges() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	sender.queue_ok(_missing_body())
	sender.queue_reply({"transport": "ok", "code": 409, "body": "{}"})
	sender.queue_ok(_found_body(NOW, INSTALL_A))
	var same: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(same.get("status", "")), "already-claimed",
		"conflict: the lost same-install race converges")
	_expect_true(bool(same.get("mine", false)),
		"conflict: the same-install winner keeps the grant")
	sender.reset()
	sender.queue_ok(_missing_body())
	sender.queue_reply({"transport": "ok", "code": 409, "body": "{}"})
	sender.queue_ok(_found_body(NOW, INSTALL_B))
	var other: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(other.get("status", "")), "already-claimed",
		"conflict: the lost cross-install race converges")
	_expect_true(not bool(other.get("mine", true)),
		"conflict: the other install keeps its grant")
	sender.reset()
	sender.queue_ok(_missing_body())
	sender.queue_reply({"transport": "ok", "code": 409, "body": "{}"})
	sender.queue_ok(_missing_body())
	var raced: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(raced.get("code", "")), "attendance-claim-race",
		"conflict: an incoherent recheck stays retryable")
	_expect_true(bool(raced.get("retryable", false)),
		"conflict: the next trigger may retry the race")


func _test_denied_stays_denied() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	sender.queue_reply({"transport": "ok", "code": 403, "body": "denied"})
	var blocked: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(blocked.get("code", "")), "permission-denied",
		"denied: a 403 read never becomes a first claim")
	_expect_equal((sender.calls as Array).size(), 1,
		"denied: a 403 read never reaches the commit")
	sender.reset()
	sender.queue_ok(_missing_body())
	sender.queue_reply({"transport": "ok", "code": 403, "body": "denied"})
	var refused: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(refused.get("status", "")), "failure",
		"denied: a 403 commit fails the claim")
	_expect_equal(str(refused.get("code", "")), "permission-denied",
		"denied: a 403 commit stays a configuration error")


func _test_malformed_server_data_fails_closed() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	sender.queue_ok(JSON.stringify([{"missing": "x"}]))
	var timeless: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(timeless.get("code", "")),
		"attendance-no-server-time",
		"malformed: a read without readTime grants nothing")
	sender.reset()
	var fields: Dictionary = {
		"public_id": {"stringValue": "MB-someone-else-000000000001"},
		"uid": {"stringValue": "uid-stranger"},
		"install_id": {"stringValue": INSTALL_A},
		"last_claim_at": {"timestampValue": HOURS_13_AGO},
		"schema": {"integerValue": "1"},
	}
	sender.queue_ok(JSON.stringify([{"found": {"name": "x",
		"fields": fields, "updateTime": "u"}, "readTime": NOW}]))
	var foreign: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(foreign.get("code", "")), "attendance-row-mismatch",
		"malformed: a foreign row is never adopted")
	sender.reset()
	sender.queue_ok(_missing_body())
	sender.queue_ok("{\"writeResults\": [{}]}")
	var uncertain: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(uncertain.get("code", "")),
		"attendance-uncertain-ack",
		"malformed: a commit without commitTime stays uncertain")
	_expect_true(bool(uncertain.get("retryable", false)),
		"malformed: the next trigger resolves the uncertainty")


func _test_invalid_inputs_send_nothing() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	var empty_install: Dictionary = await service.call(
		"claim_attendance", _new_transport(sender), UID_A, PUBLIC_A, "")
	_expect_equal(str(empty_install.get("code", "")), "invalid-install-id",
		"invalid: an empty install never claims")
	_expect_equal((sender.calls as Array).size(), 0,
		"invalid: an empty install sends nothing")
	var bad_uid: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), "!!", PUBLIC_A, INSTALL_A)
	_expect_equal(str(bad_uid.get("code", "")), "invalid-uid",
		"invalid: a bad UID never claims")
	_expect_equal((sender.calls as Array).size(), 0,
		"invalid: a bad UID sends nothing")


func _test_advance_conflict_converges() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	sender.queue_ok(_found_body(HOURS_13_AGO, INSTALL_B))
	var ready: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(ready.get("status", "")), "eligible",
		"advance race: the stale row is eligible")
	sender.queue_reply({"transport": "ok", "code": 409, "body": "{}"})
	sender.queue_ok(_found_body(NOW, INSTALL_B))
	var lost: Dictionary = await service.call("commit_advance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A,
		str(ready.get("update_time", "")),
		str(ready.get("last_claim_rfc", "")),
		str(ready.get("install_id", "")))
	_expect_equal(str(lost.get("status", "")), "already-claimed",
		"advance race: the lost swap converges on the winner")
	_expect_true(not bool(lost.get("mine", true)),
		"advance race: the other install keeps its grant")

	sender.reset()
	sender.queue_ok(_found_body(HOURS_13_AGO, INSTALL_A))
	var fresh: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	sender.queue_reply({"transport": "ok", "code": 409, "body": "{}"})
	sender.queue_ok(_missing_body())
	var raced: Dictionary = await service.call("commit_advance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A,
		str(fresh.get("update_time", "")),
		str(fresh.get("last_claim_rfc", "")),
		str(fresh.get("install_id", "")))
	_expect_equal(str(raced.get("code", "")), "attendance-claim-race",
		"advance race: an incoherent recheck stays retryable")


func _test_prev_carry_parses() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	sender.queue_ok(_found_body(HOURS_11_AGO, INSTALL_B, NOW,
		"2026-10-06T23:00:00.25Z", DAYS_5_AGO, INSTALL_A))
	var held: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(held.get("status", "")), "already-claimed",
		"prev: the held row still holds")
	_expect_equal(int(held.get("prev_claim_at", 0)), 1790935200,
		"prev: the carried stamp parses to seconds")
	_expect_equal(str(held.get("prev_install_id", "")), INSTALL_A,
		"prev: the carried install parses")

	sender.reset()
	sender.queue_ok(_found_body(HOURS_11_AGO, INSTALL_B, NOW,
		"2026-10-06T23:00:00.25Z", "not-a-stamp", INSTALL_A))
	var broken: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(str(broken.get("code", "")), "attendance-bad-stamp",
		"prev: a malformed carried stamp fails closed")

	sender.reset()
	sender.queue_ok(_found_body(HOURS_11_AGO, INSTALL_B))
	var legacy: Dictionary = await service.call("claim_attendance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A)
	_expect_equal(int(legacy.get("prev_claim_at", -1)), 0,
		"prev: a pre-chain row reads zero")
	_expect_equal(str(legacy.get("prev_install_id", "x")), "",
		"prev: a pre-chain row reads empty")


func _test_invalid_advance_sends_nothing() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var service: RefCounted = ATTEND_SCRIPT.new()
	var no_swap: Dictionary = await service.call("commit_advance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A, "",
		HOURS_13_AGO, INSTALL_B)
	_expect_equal(str(no_swap.get("code", "")), "attendance-bad-advance",
		"advance: a missing swap never commits")
	_expect_equal((sender.calls as Array).size(), 0,
		"advance: a missing swap sends nothing")
	var no_carry: Dictionary = await service.call("commit_advance",
		_new_transport(sender), UID_A, PUBLIC_A, INSTALL_A, "u", "", "")
	_expect_equal(str(no_carry.get("code", "")), "attendance-bad-advance",
		"advance: a missing carry never commits")
	_expect_equal((sender.calls as Array).size(), 0,
		"advance: a missing carry sends nothing")
