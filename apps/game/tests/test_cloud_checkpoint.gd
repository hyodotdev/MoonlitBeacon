extends SceneTree

## Cloud checkpoint queueing, compare-and-swap saves, conflicts, and retry
## tests. No network: the transport runs against a scripted fake sender.

const TRANSPORT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_transport.gd")
const CHECKPOINT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_checkpoint.gd")
const SCHEMA_SCRIPT: Script = preload("res://scripts/cloud/cloud_schema.gd")
const FAKE_SENDER_SCRIPT: Script = preload(
	"res://tests/support/fake_cloud_sender.gd")

const PROJECT_ID: String = "moonlitbeacon-778ee"
const TOKEN: String = "test-id-token-abc"
const UID: String = "uid-checkpoint-001"

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_queue_coalesces_stable_changes()
	await _test_queue_rejects_bad_payloads()
	await _test_save_rejects_malformed_before_any_request()
	await _test_first_save_uses_create_guard()
	await _test_guarded_save_acknowledges_revision()
	await _test_offline_save_retained_for_retry()
	await _test_conflict_carries_both_summaries()
	await _test_explicit_local_and_remote_choice()
	await _test_completion_drains_only_committed_bytes()
	await _test_switch_account_retires_inflight()
	await _test_choose_local_returns_fresh_remote()
	await _test_load_needs_validator()
	if _failed > 0:
		printerr("cloud checkpoint tests failed — ", _failed, "/", _checked,
			" cases")
		quit(1)
		return
	print("cloud checkpoint tests passed — ", _checked, " cases")
	quit(0)


func _new_transport(sender: RefCounted) -> RefCounted:
	var transport: RefCounted = TRANSPORT_SCRIPT.new()
	transport.call("configure", PROJECT_ID, "web-key",
		func() -> String: return TOKEN, sender.call("sender_callable"))
	transport.call("set_account_uid", UID)
	return transport


func _remote_body(revision: int, payload: String,
		update_time: String) -> String:
	return JSON.stringify({
		"name": "projects/%s/databases/(default)/documents/mb_checkpoints_v1/%s"
			% [PROJECT_ID, UID],
		"fields": {
			"uid": {"stringValue": UID},
			"revision": {"integerValue": str(revision)},
			"payload": {"stringValue": payload},
			"schema": {"integerValue": "1"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
		},
		"createTime": "2026-10-01T00:00:00Z",
		"updateTime": update_time,
	})


func _test_queue_coalesces_stable_changes() -> void:
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	var first: Dictionary = checkpoint.call("queue_checkpoint", UID, 4,
		"{\"gate\":2}")
	var second: Dictionary = checkpoint.call("queue_checkpoint", UID, 5,
		"{\"gate\":3}")
	var third: Dictionary = checkpoint.call("queue_checkpoint", UID, 5,
		"{\"gate\":3}")
	_expect_equal(first.get("code", ""), "queued", "first change queued")
	_expect_true(bool(second.get("coalesced", false)),
		"second change coalesces with the first")
	_expect_equal(third.get("code", ""), "already-queued",
		"identical repeat is a no-op")
	_expect_equal(checkpoint.call("pending_coalesced_count"), 2,
		"two distinct payloads coalesced")
	var pending: Dictionary = checkpoint.call("peek_pending")
	_expect_equal(pending.get("payload", ""), "{\"gate\":3}",
		"only the latest stable payload is kept")
	var taken: Dictionary = checkpoint.call("take_pending")
	_expect_equal(taken.get("revision", 0), 5, "take returns the latest")
	_expect_false(bool(checkpoint.call("has_pending")),
		"take drains the queue")


func _test_queue_rejects_bad_payloads() -> void:
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	var ledger: Dictionary = checkpoint.call("queue_checkpoint", UID, 1,
		"{\"entitlements\":[\"dancer\"],\"gate\":1}")
	_expect_equal(ledger.get("code", ""), "ledger-keys-rejected",
		"paid entitlements never queue")
	var vault: Dictionary = checkpoint.call("queue_checkpoint", UID, 1,
		"{\"vault\":{\"shards\":9}}")
	_expect_equal(vault.get("code", ""), "ledger-keys-rejected",
		"Vault ledgers never queue")
	var huge: Dictionary = checkpoint.call("queue_checkpoint", UID, 1,
		"{\"gate\":\"" + "x".repeat(40000) + "\"}")
	_expect_equal(huge.get("code", ""), "payload-too-large",
		"oversized payload rejected before any request")
	var broken: Dictionary = checkpoint.call("queue_checkpoint", UID, 1,
		"not json")
	_expect_equal(broken.get("code", ""), "payload-not-json-object",
		"non-object payload rejected")
	var brace_garbage: Dictionary = checkpoint.call("queue_checkpoint", UID,
		1, "{bad}")
	_expect_equal(brace_garbage.get("code", ""), "payload-not-json-object",
		"brace-shaped non-JSON rejected: the rules cannot parse it, so the client must")
	var bad_revision: Dictionary = checkpoint.call("queue_checkpoint", UID,
		0, "{\"gate\":1}")
	_expect_equal(bad_revision.get("code", ""), "invalid-revision",
		"revision starts at one")
	_expect_false(bool(checkpoint.call("has_pending")),
		"rejected payloads queue nothing")


func _test_save_rejects_malformed_before_any_request() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	for bad in ["not json", "{bad}", "{\"gate\":}"]:
		var result: Dictionary = await checkpoint.call("save_revision",
			_new_transport(sender), UID, 0, "", bad)
		_expect_equal(result.get("code", ""), "payload-not-json-object",
			"malformed payload rejected before any request: " + bad)
	_expect_equal(sender.calls.size(), 0, "rejected payloads send nothing")
	_expect_true((checkpoint.call("failed_save") as Dictionary).is_empty(),
		"validation rejects are not retained as failed saves")


func _test_first_save_uses_create_guard() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	var result: Dictionary = await checkpoint.call("save_revision",
		_new_transport(sender), UID, 0, "", "{\"gate\":1}")
	_expect_equal(result.get("status", ""), "ok", "first save ok")
	_expect_equal(result.get("revision", 0), 1, "first save mints revision 1")
	var commit: Dictionary = JSON.parse_string(str(
		sender.call("last_call").get("body", "")))
	var guard: Dictionary = ((commit.get("writes", []) as Array)[0]
		as Dictionary).get("currentDocument", {})
	_expect_false(bool(guard.get("exists", true)),
		"first save requires document absence")
	_expect_equal(checkpoint.call("last_acked_revision"), 1,
		"acknowledged revision tracked")


func _test_guarded_save_acknowledges_revision() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	var result: Dictionary = await checkpoint.call("save_revision",
		_new_transport(sender), UID, 4, "2026-10-01T01:00:00Z",
		"{\"gate\":4}")
	_expect_equal(result.get("revision", 0), 5,
		"guarded save writes base plus one")
	var commit: Dictionary = JSON.parse_string(str(
		sender.call("last_call").get("body", "")))
	var guard: Dictionary = ((commit.get("writes", []) as Array)[0]
		as Dictionary).get("currentDocument", {})
	_expect_equal(guard.get("updateTime", ""),
		"2026-10-01T01:00:00Z", "save carries the compare-and-swap guard")
	_expect_true((checkpoint.call("failed_save") as Dictionary).is_empty(),
		"success clears any retained failure")


func _test_offline_save_retained_for_retry() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	var result: Dictionary = await checkpoint.call("save_revision",
		_new_transport(sender), UID, 2, "2026-10-01T01:00:00Z",
		"{\"gate\":2}")
	_expect_equal(result.get("status", ""), "offline",
		"offline save reports offline, never success")
	_expect_equal(checkpoint.call("last_acked_revision"), 0,
		"unacknowledged save advances nothing")
	var failed: Dictionary = checkpoint.call("failed_save")
	_expect_equal(failed.get("code", ""), "offline",
		"failed save retained with its cause")
	# Retry re-reads the remote guard, then saves on top of it.
	sender.call("queue_ok", _remote_body(2, "{\"gate\":2}",
		"2026-10-01T02:00:00Z"))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var retried: Dictionary = await checkpoint.call("retry_failed_save",
		_new_transport(sender))
	_expect_equal(retried.get("status", ""), "ok", "retained save retries")
	_expect_equal(retried.get("revision", 0), 3,
		"retry writes one past the re-read revision")
	_expect_true((checkpoint.call("failed_save") as Dictionary).is_empty(),
		"retry success clears the retained save")


func _test_conflict_carries_both_summaries() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 412,
		"body": "stale"})
	sender.call("queue_ok", _remote_body(6, "{\"gate\":9,\"cycle\":4}",
		"2026-10-01T03:00:00Z"))
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	var result: Dictionary = await checkpoint.call("save_revision",
		_new_transport(sender), UID, 5, "2026-10-01T00:30:00Z",
		"{\"gate\":5,\"cycle\":3}")
	_expect_equal(result.get("status", ""), "conflict",
		"stale guard reports an explicit conflict")
	_expect_equal(result.get("local_revision", 0), 6,
		"conflict names the attempted revision")
	_expect_equal(result.get("remote_revision", 0), 6,
		"conflict names the remote revision")
	var local_summary: Dictionary = result.get("local_summary", {})
	var remote_summary: Dictionary = result.get("remote_summary", {})
	_expect_equal(local_summary.get("gate", 0), 5,
		"local summary marks our gate")
	_expect_equal(remote_summary.get("gate", 0), 9,
		"remote summary marks their gate")
	_expect_true(local_summary.has("digest") and remote_summary.has("digest"),
		"summaries carry digests, not full payloads")
	_expect_false((checkpoint.call("failed_save") as Dictionary).is_empty(),
		"conflicted save retained for an explicit choice")


func _test_explicit_local_and_remote_choice() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _remote_body(6, "{\"gate\":9}",
		"2026-10-01T03:00:00Z"))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	var kept: Dictionary = await checkpoint.call("choose_local",
		_new_transport(sender), UID, "{\"gate\":5}")
	_expect_equal(kept.get("status", ""), "ok",
		"explicit local choice rebases and saves")
	_expect_equal(kept.get("revision", 0), 7,
		"local choice lands one past the fresh remote")

	var checkpoint_b: RefCounted = CHECKPOINT_SCRIPT.new()
	var remote: Dictionary = {
		"status": "ok", "revision": 6, "payload": "{\"gate\":9}",
		"update_time": "2026-10-01T03:00:00Z",
		"summary": SCHEMA_SCRIPT.summarize_payload("{\"gate\":9}", 6),
	}
	var accepted: Dictionary = await checkpoint_b.call("choose_remote",
		remote)
	_expect_equal(accepted.get("choice", ""), "remote",
		"explicit remote choice labeled")
	_expect_true(bool(accepted.get("needs_validator", false)),
		"accepted remote still needs the Journey validator first")
	_expect_equal(accepted.get("payload", ""), "{\"gate\":9}",
		"accepted remote keeps its payload")


func _test_completion_drains_only_committed_bytes() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	checkpoint.call("queue_checkpoint", UID, 1, "{\"gate\":1}")
	var taken: Dictionary = checkpoint.call("take_pending")
	_expect_equal(taken.get("payload", ""), "{\"gate\":1}",
		"the flush takes the first seal")
	checkpoint.call("queue_checkpoint", UID, 1, "{\"gate\":2}")
	var saved: Dictionary = await checkpoint.call("save_revision",
		_new_transport(sender), UID, 0, "", "{\"gate\":1}")
	_expect_equal(saved.get("status", ""), "ok", "the first seal commits")
	_expect_true(bool(checkpoint.call("has_pending")),
		"the newer seal queued mid-commit survives the completion")
	_expect_equal((checkpoint.call("peek_pending") as Dictionary).get(
		"payload", ""), "{\"gate\":2}",
		"the surviving payload is the newer seal")

	var sender_b: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender_b.call("queue_ok", "{\"writeResults\":[{}]}")
	var checkpoint_b: RefCounted = CHECKPOINT_SCRIPT.new()
	checkpoint_b.call("queue_checkpoint", UID, 1, "{\"gate\":1}")
	var resent: Dictionary = await checkpoint_b.call("save_revision",
		_new_transport(sender_b), UID, 0, "", "{\"gate\":1}")
	_expect_equal(resent.get("status", ""), "ok", "the seal commits")
	_expect_false(bool(checkpoint_b.call("has_pending")),
		"an identical requeue drains as acknowledged")


func _test_switch_account_retires_inflight() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	checkpoint.call("switch_account", UID)
	checkpoint.call("queue_checkpoint", UID, 1, "{\"gate\":1}")
	var switching: RefCounted = _SwitchCheckpointSender.new(
		checkpoint, "uid-checkpoint-002", sender, 1)
	var saved: Dictionary = await checkpoint.call("save_revision",
		_new_transport(switching), UID, 0, "", "{\"gate\":1}")
	_expect_equal(saved.get("status", ""), "cancelled",
		"the tripped save reports cancelled")
	_expect_false(bool(checkpoint.call("has_pending")),
		"the switch clears the old queue")
	_expect_true((checkpoint.call("failed_save") as Dictionary).is_empty(),
		"the stale completion retains no failure under the new account")
	_expect_equal(checkpoint.call("last_acked_revision"), 0,
		"the stale completion acknowledges nothing")
	var foreign: Dictionary = checkpoint.call("queue_checkpoint", UID, 1,
		"{\"gate\":1}")
	_expect_equal(foreign.get("code", ""), "wrong-account",
		"the old account cannot queue under the new binding")
	var own: Dictionary = checkpoint.call("queue_checkpoint",
		"uid-checkpoint-002", 1, "{\"gate\":9}")
	_expect_equal(own.get("code", ""), "queued",
		"the new account queues cleanly")


func _test_choose_local_returns_fresh_remote() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _remote_body(6, "{\"gate\":9}",
		"2026-10-01T03:00:00Z"))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	var kept: Dictionary = await checkpoint.call("choose_local",
		_new_transport(sender), UID, "{\"gate\":5}")
	_expect_equal(kept.get("status", ""), "ok", "the local choice lands")
	_expect_equal((kept.get("remote", {}) as Dictionary).get(
		"revision", 0), 6,
		"the choice carries the fresh remote it rebased onto")
	_expect_equal((kept.get("remote", {}) as Dictionary).get(
		"payload", ""), "{\"gate\":9}",
		"the carried remote keeps the overwritten bytes")


func _test_load_needs_validator() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _remote_body(3, "{\"gate\":3}",
		"2026-10-01T04:00:00Z"))
	var checkpoint: RefCounted = CHECKPOINT_SCRIPT.new()
	var loaded: Dictionary = await checkpoint.call("load_remote",
		_new_transport(sender), UID)
	_expect_equal(loaded.get("status", ""), "ok", "remote load ok")
	_expect_equal(loaded.get("revision", 0), 3, "remote revision decoded")
	_expect_true(bool(loaded.get("needs_validator", false)),
		"downloaded payload flagged for the Journey validator")
	_expect_equal(loaded.get("update_time", ""),
		"2026-10-01T04:00:00Z", "compare-and-swap guard decoded")


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


## Fake sender that rebinds the checkpoint mid-request, so the test can
## prove the in-flight completion is retired instead of applied.
class _SwitchCheckpointSender:
	extends RefCounted
	var _checkpoint: RefCounted
	var _next_uid: String
	var _inner: RefCounted
	var _arm_on_call: int
	var switched: bool = false

	func _init(checkpoint: RefCounted, next_uid: String,
			inner: RefCounted, arm_on_call: int) -> void:
		_checkpoint = checkpoint
		_next_uid = next_uid
		_inner = inner
		_arm_on_call = arm_on_call

	func sender_callable() -> Callable:
		return Callable(self, "send")

	func send(method: String, url: String, headers: Dictionary,
			body: String) -> Dictionary:
		var reply: Dictionary = await _inner.call("send", method, url,
			headers, body)
		if not switched \
				and (_inner.get("calls") as Array).size() == _arm_on_call:
			switched = true
			_checkpoint.call("switch_account", _next_uid)
		return reply
