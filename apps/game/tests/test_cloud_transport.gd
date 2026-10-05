extends SceneTree

## Cloud transport bounds and status-label regression tests. No network: a
## scripted fake sender stands in for HTTPRequest.

const TRANSPORT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_transport.gd")
const FAKE_SENDER_SCRIPT: Script = preload(
	"res://tests/support/fake_cloud_sender.gd")

const PROJECT_ID: String = "moonlitbeacon-778ee"
const TOKEN: String = "test-id-token-abc"

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_unconfigured_states()
	await _test_offline_no_retry()
	await _test_bounded_retries_then_success()
	await _test_bounded_retries_exhausted()
	await _test_no_retry_on_client_errors()
	await _test_conflict_mapping()
	await _test_response_bound()
	await _test_concurrency_bound()
	await _test_request_cancellation()
	await _test_account_and_generation_isolation()
	await _test_token_never_in_results()
	if _failed > 0:
		printerr("cloud transport tests failed — ", _failed, "/", _checked,
			" cases")
		quit(1)
		return
	print("cloud transport tests passed — ", _checked, " cases")
	quit(0)


func _new_transport(sender: RefCounted, token: String = TOKEN) -> RefCounted:
	var transport: RefCounted = TRANSPORT_SCRIPT.new()
	transport.call("configure", PROJECT_ID, "web-key",
		func() -> String: return token, sender.call("sender_callable"))
	return transport


func _test_unconfigured_states() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var missing_project: RefCounted = TRANSPORT_SCRIPT.new()
	missing_project.call("configure", "", "web-key",
		func() -> String: return TOKEN, sender.call("sender_callable"))
	var reply: Dictionary = await missing_project.call("get_document",
		"documents/mb_profiles_v1/u1")
	_expect_equal(reply.get("status", ""), "unconfigured",
		"empty project never attempts a request")
	_expect_equal(sender.calls.size(), 0, "unconfigured makes no sender call")

	var missing_token: RefCounted = _new_transport(sender, "")
	reply = await missing_token.call("get_document",
		"documents/mb_profiles_v1/u1")
	_expect_equal(reply.get("status", ""), "unconfigured",
		"empty ID token reports unconfigured")
	_expect_equal(reply.get("code", ""), "missing-id-token",
		"missing token has its own code")
	_expect_equal(sender.calls.size(), 0, "missing token makes no sender call")

	var bare: RefCounted = TRANSPORT_SCRIPT.new()
	reply = await bare.call("get_document", "documents/mb_profiles_v1/u1")
	_expect_equal(reply.get("status", ""), "unconfigured",
		"transport without sender stays unconfigured")


func _test_offline_no_retry() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var transport: RefCounted = _new_transport(sender)
	var reply: Dictionary = await transport.call("get_document",
		"documents/mb_profiles_v1/u1")
	_expect_equal(reply.get("status", ""), "offline", "offline is explicit")
	_expect_true(bool(reply.get("retryable", false)), "offline is retryable")
	_expect_equal(sender.calls.size(), 1, "offline does not spin retries")


func _test_bounded_retries_then_success() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 503,
		"body": "busy"})
	sender.call("queue_reply", {"transport": "timeout", "code": 0,
		"body": PackedByteArray()})
	sender.call("queue_ok", "{\"ok\":true}")
	var transport: RefCounted = _new_transport(sender)
	var reply: Dictionary = await transport.call("get_document",
		"documents/mb_profiles_v1/u1")
	_expect_equal(reply.get("status", ""), "ok",
		"retryable failures recover within the bound")
	_expect_equal(sender.calls.size(), 3, "two retries then success")
	_expect_equal(reply.get("http_code", 0), 200, "success carries HTTP code")


func _test_bounded_retries_exhausted() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	for _index in 5:
		sender.call("queue_reply", {"transport": "ok", "code": 503,
			"body": "busy"})
	var transport: RefCounted = _new_transport(sender)
	var reply: Dictionary = await transport.call("get_document",
		"documents/mb_profiles_v1/u1")
	_expect_equal(reply.get("status", ""), "failure",
		"exhausted retries stay a failure")
	_expect_true(bool(reply.get("retryable", false)),
		"exhausted 503 stays retryable for the caller")
	_expect_equal(sender.calls.size(), 3, "attempts stop at MAX_ATTEMPTS")


func _test_no_retry_on_client_errors() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 400,
		"body": "bad"})
	var transport: RefCounted = _new_transport(sender)
	var reply: Dictionary = await transport.call("get_document",
		"documents/mb_profiles_v1/u1")
	_expect_equal(reply.get("status", ""), "failure", "400 is a failure")
	_expect_false(bool(reply.get("retryable", true)), "400 never retries")
	_expect_equal(sender.calls.size(), 1, "400 sends once")

	sender.call("queue_reply", {"transport": "ok", "code": 403,
		"body": "denied"})
	reply = await transport.call("get_document", "documents/mb_profiles_v1/u1")
	_expect_equal(reply.get("code", ""), "permission-denied",
		"403 maps to permission-denied")
	_expect_equal(sender.calls.size(), 2, "403 sends once")

	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	reply = await transport.call("get_document", "documents/mb_profiles_v1/u1")
	_expect_equal(reply.get("code", ""), "not-found", "404 maps to not-found")
	_expect_equal(sender.calls.size(), 3, "404 sends once")


func _test_conflict_mapping() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 409,
		"body": "exists"})
	sender.call("queue_reply", {"transport": "ok", "code": 412,
		"body": "stale"})
	var transport: RefCounted = _new_transport(sender)
	var first: Dictionary = await transport.call("post", "documents:commit",
		"{}")
	var second: Dictionary = await transport.call("post", "documents:commit",
		"{}")
	_expect_equal(first.get("status", ""), "conflict", "409 is a conflict")
	_expect_equal(second.get("status", ""), "conflict", "412 is a conflict")
	_expect_false(bool(first.get("retryable", true)),
		"conflicts never auto-retry")
	_expect_equal(sender.calls.size(), 2, "conflicts send once each")


func _test_response_bound() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var huge: PackedByteArray = PackedByteArray()
	huge.resize(TRANSPORT_SCRIPT.MAX_RESPONSE_BYTES + 1)
	sender.call("queue_reply", {"transport": "ok", "code": 200,
		"body": huge})
	var transport: RefCounted = _new_transport(sender)
	var reply: Dictionary = await transport.call("get_document",
		"documents/mb_hall_v1/MB-" + "a".repeat(32))
	_expect_equal(reply.get("status", ""), "failure",
		"oversized response fails closed")
	_expect_equal(reply.get("code", ""), "response-too-large",
		"oversized response has its own code")
	_expect_equal(sender.calls.size(), 1, "oversized response never retries")

	var pre_bound: RefCounted = FAKE_SENDER_SCRIPT.new()
	pre_bound.call("queue_reply", {"transport": "response-too-large",
		"code": 200, "body": PackedByteArray()})
	var bounded: RefCounted = _new_transport(pre_bound)
	var early: Dictionary = await bounded.call("get_document",
		"documents/mb_hall_v1/MB-" + "a".repeat(32))
	_expect_equal(early.get("code", ""), "response-too-large",
		"the pre-receipt engine bound maps to its own failure")
	_expect_false(bool(early.get("retryable", true)),
		"a pre-bounded reply never retries")
	_expect_equal(pre_bound.calls.size(), 1, "one attempt only")


func _test_concurrency_bound() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var transport: RefCounted = _new_transport(sender)
	transport.set("_in_flight", TRANSPORT_SCRIPT.MAX_CONCURRENCY)
	var reply: Dictionary = await transport.call("get_document",
		"documents/mb_profiles_v1/u1")
	_expect_equal(reply.get("status", ""), "failure",
		"saturated transport reports instead of queueing forever")
	_expect_equal(reply.get("code", ""), "concurrency-exceeded",
		"saturation has its own code")
	_expect_true(bool(reply.get("retryable", false)), "saturation is retryable")
	_expect_equal(sender.calls.size(), 0, "saturated transport sends nothing")
	transport.set("_in_flight", 0)


func _test_request_cancellation() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", "{}")
	var transport: RefCounted = _new_transport(sender)
	transport.call("cancel_request", "r_9")
	var reply: Dictionary = await transport.call("request_with_id", "r_9",
		"GET", "documents/mb_profiles_v1/u1", "")
	_expect_equal(reply.get("status", ""), "cancelled",
		"cancelled request never sends")
	_expect_equal(sender.calls.size(), 0, "cancelled request makes no call")


func _test_account_and_generation_isolation() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var transport: RefCounted = _new_transport(sender)
	transport.call("set_account_uid", "uid-a")
	var switching: RefCounted = _SwitchingSender.new(transport, "uid-b",
		sender)
	transport.call("configure", PROJECT_ID, "web-key",
		func() -> String: return TOKEN, switching.call("sender_callable"))
	var reply: Dictionary = await transport.call("get_document",
		"documents/mb_profiles_v1/uid-a")
	_expect_equal(reply.get("status", ""), "cancelled",
		"late reply after account switch is cancelled")
	_expect_equal(reply.get("code", ""), "account-changed",
		"account change has its own code")

	var sender_b: RefCounted = FAKE_SENDER_SCRIPT.new()
	var transport_b: RefCounted = _new_transport(sender_b)
	transport_b.call("set_account_uid", "uid-a")
	var cancelling: RefCounted = _CancellingSender.new(transport_b, sender_b)
	transport_b.call("configure", PROJECT_ID, "web-key",
		func() -> String: return TOKEN, cancelling.call("sender_callable"))
	reply = await transport_b.call("get_document",
		"documents/mb_profiles_v1/uid-a")
	_expect_equal(reply.get("status", ""), "cancelled",
		"late reply after cancel-all is cancelled")
	_expect_equal(reply.get("code", ""), "stale-reply",
		"retired generation reports stale-reply")


func _test_token_never_in_results() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", "{\"ok\":true}")
	var transport: RefCounted = _new_transport(sender)
	var reply: Dictionary = await transport.call("get_document",
		"documents/mb_profiles_v1/u1")
	_expect_false(JSON.stringify(reply).contains(TOKEN),
		"results never echo the ID token")
	_expect_false(JSON.stringify(sender.calls).contains(TOKEN),
		"recorded calls never keep the ID token")


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


## Fake sender that swaps the transport account mid-flight so the test can
## prove the late reply is dropped.
class _SwitchingSender:
	extends RefCounted
	var _transport: RefCounted
	var _next_uid: String
	var _inner: RefCounted

	func _init(transport: RefCounted, next_uid: String,
			inner: RefCounted) -> void:
		_transport = transport
		_next_uid = next_uid
		_inner = inner

	func sender_callable() -> Callable:
		return Callable(self, "send")

	func send(method: String, url: String, headers: Dictionary,
			body: String) -> Dictionary:
		var reply: Dictionary = await _inner.call("send", method, url,
			headers, body)
		_transport.call("set_account_uid", _next_uid)
		return reply


## Fake sender that retires the transport generation mid-flight.
class _CancellingSender:
	extends RefCounted
	var _transport: RefCounted
	var _inner: RefCounted

	func _init(transport: RefCounted, inner: RefCounted) -> void:
		_transport = transport
		_inner = inner

	func sender_callable() -> Callable:
		return Callable(self, "send")

	func send(method: String, url: String, headers: Dictionary,
			body: String) -> Dictionary:
		var reply: Dictionary = await _inner.call("send", method, url,
			headers, body)
		_transport.call("cancel_all")
		return reply
