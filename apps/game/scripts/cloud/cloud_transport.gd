extends RefCounted

## Firebase-authenticated Firestore REST transport with injected boundaries.
##
## The game has no Firebase SDK, so this helper speaks REST directly. The real
## HTTP sender and the in-memory ID-token supplier are injected Callables, which
## keeps tests offline and keeps tokens out of saves and logs. Every reply is
## labeled with one status: ok, offline, unconfigured, cancelled, conflict, or
## failure. A late reply for a retired account or a cancelled request reports
## cancelled and never applies to the current player.
##
## Sender contract: `sender.call(method, url, headers, body) -> Dictionary`
## with keys `transport` ("ok", "offline", "timeout", "dns", "cancelled"),
## `code` (HTTP int, 0 when no response), and `body` (PackedByteArray or
## String). The sender may be async; this transport always awaits it.
##
## Token supplier contract: `supplier.call() -> String`, synchronous, returning
## the current Firebase ID token or "" when signed out. The token is held only
## for the request and is never written to a result Dictionary.

const CloudSchema: Script = preload("res://scripts/cloud/cloud_schema.gd")

const TIMEOUT_SECONDS: float = 10.0
const MAX_RESPONSE_BYTES: int = 262144
const MAX_ATTEMPTS: int = 3
const MAX_CONCURRENCY: int = 2
const RETRYABLE_CODES: Array[int] = [408, 425, 429, 500, 502, 503, 504]

const STATUS_OK: String = "ok"
const STATUS_OFFLINE: String = "offline"
const STATUS_UNCONFIGURED: String = "unconfigured"
const STATUS_CANCELLED: String = "cancelled"
const STATUS_CONFLICT: String = "conflict"
const STATUS_FAILURE: String = "failure"

var _project_id: String = ""
var _database_id: String = CloudSchema.DATABASE_ID
var _web_api_key: String = ""
var _token_supplier: Callable = Callable()
var _sender: Callable = Callable()
var _sleeper: Callable = Callable()

var _in_flight: int = 0
var _generation: int = 0
var _account_uid: String = ""
var _request_seq: int = 0
var _cancelled_requests: Dictionary = {}


func configure(project_id: String, web_api_key: String,
		token_supplier: Callable, sender: Callable) -> void:
	_project_id = project_id.strip_edges()
	_web_api_key = web_api_key.strip_edges()
	_token_supplier = token_supplier
	_sender = sender


## Optional injected sleep between retries. Tests leave it empty for instant
## bounded retries; production may pass a Callable that awaits a timer.
func set_sleeper(sleeper: Callable) -> void:
	_sleeper = sleeper


func set_account_uid(uid: String) -> void:
	if _account_uid != uid:
		_account_uid = uid
		_generation += 1


func account_uid() -> String:
	return _account_uid


## Retire every in-flight request. Late replies report cancelled.
func cancel_all() -> void:
	_generation += 1


func cancel_request(request_id: String) -> void:
	_cancelled_requests[request_id] = true


func configured() -> bool:
	return not _project_id.is_empty() \
		and _token_supplier.is_valid() \
		and _sender.is_valid()


func _next_request_id() -> String:
	_request_seq += 1
	return "r_%d" % _request_seq


## Authenticated GET of one document path below `documents/`.
func get_document(relative_path: String) -> Dictionary:
	return await request("GET", relative_path, "")


## Authenticated POST to a `documents` or `documents:runQuery` style path.
func post(relative_path: String, body: String) -> Dictionary:
	return await request("POST", relative_path, body)


func patch_document(relative_path: String, body: String) -> Dictionary:
	return await request("PATCH", relative_path, body)


func delete_document(relative_path: String) -> Dictionary:
	return await request("DELETE", relative_path, "")


func request(method: String, relative_path: String, body: String) -> Dictionary:
	var request_id: String = _next_request_id()
	return await request_with_id(request_id, method, relative_path, body)


func request_with_id(request_id: String, method: String,
		relative_path: String, body: String) -> Dictionary:
	if not configured():
		return _status(STATUS_UNCONFIGURED, "transport-unconfigured", false,
			request_id)
	if _cancelled_requests.has(request_id):
		return _status(STATUS_CANCELLED, "request-cancelled", false, request_id)
	if _in_flight >= MAX_CONCURRENCY:
		return _status(STATUS_FAILURE, "concurrency-exceeded", true, request_id)
	var token: String = str(_token_supplier.call())
	if token.is_empty():
		return _status(STATUS_UNCONFIGURED, "missing-id-token", false, request_id)
	var url: String = _build_url(relative_path)
	# Headers carry the token only on the wire. Results below never include it.
	var headers: Dictionary = {
		"Content-Type": "application/json",
		"Accept": "application/json",
		"Authorization": "Bearer " + token,
	}
	token = ""

	var captured_generation: int = _generation
	var captured_account: String = _account_uid
	_in_flight += 1
	var attempt: int = 0
	var last: Dictionary = _status(STATUS_FAILURE, "no-attempt", false, request_id)
	while attempt < MAX_ATTEMPTS:
		attempt += 1
		if _is_retired(request_id, captured_generation, captured_account):
			last = _retired_status(request_id, captured_generation,
				captured_account)
			break
		var reply: Variant = await _sender.call(method, url, headers, body)
		if _is_retired(request_id, captured_generation, captured_account):
			last = _retired_status(request_id, captured_generation,
				captured_account)
			break
		last = _interpret_reply(reply, request_id)
		var status: String = str(last.get("status", STATUS_FAILURE))
		if status != STATUS_FAILURE or not bool(last.get("retryable", false)):
			break
		if attempt >= MAX_ATTEMPTS:
			break
		if _sleeper.is_valid():
			await _sleeper.call(attempt)
		if _is_retired(request_id, captured_generation, captured_account):
			last = _retired_status(request_id, captured_generation,
				captured_account)
			break
	_in_flight = maxi(_in_flight - 1, 0)
	return last


func _is_retired(request_id: String, captured_generation: int,
		captured_account: String) -> bool:
	if _cancelled_requests.has(request_id):
		return true
	if captured_generation != _generation:
		return true
	return captured_account != _account_uid


func _retired_status(request_id: String, captured_generation: int,
		captured_account: String) -> Dictionary:
	_cancelled_requests.erase(request_id)
	if captured_account != _account_uid:
		return _status(STATUS_CANCELLED, "account-changed", false, request_id)
	return _status(STATUS_CANCELLED, "stale-reply", false, request_id)


func _build_url(relative_path: String) -> String:
	var trimmed: String = relative_path.strip_edges().trim_prefix("/")
	var url: String = "%s/projects/%s/databases/%s/%s" % [
		CloudSchema.API_ROOT, _project_id, _database_id, trimmed,
	]
	if not _web_api_key.is_empty():
		var separator: String = "&" if url.contains("?") else "?"
		url += "%skey=%s" % [separator, _web_api_key.uri_encode()]
	return url


func _interpret_reply(reply: Variant, request_id: String) -> Dictionary:
	if typeof(reply) != TYPE_DICTIONARY:
		return _status(STATUS_FAILURE, "malformed-sender-result", false,
			request_id)
	var envelope: Dictionary = reply as Dictionary
	var transport: String = str(envelope.get("transport", "ok"))
	if transport == "offline":
		return _status(STATUS_OFFLINE, "offline", true, request_id)
	if transport == "cancelled":
		return _status(STATUS_CANCELLED, "request-cancelled", false, request_id)
	if transport == "timeout":
		return _status(STATUS_FAILURE, "timeout", true, request_id)
	if transport == "response-too-large":
		return _status(STATUS_FAILURE, "response-too-large", false, request_id)
	if transport == "dns" or transport == "unreachable":
		return _status(STATUS_FAILURE, "network-unreachable", true, request_id)
	if transport != "ok":
		return _status(STATUS_FAILURE, "sender-error", true, request_id)
	var code: int = int(envelope.get("code", 0))
	var body_bytes: PackedByteArray = _reply_bytes(envelope.get("body"))
	if body_bytes.size() > MAX_RESPONSE_BYTES:
		return _status(STATUS_FAILURE, "response-too-large", false, request_id)
	var text: String = body_bytes.get_string_from_utf8()
	if code >= 200 and code < 300:
		return {
			"status": STATUS_OK,
			"code": "ok",
			"retryable": false,
			"request_id": request_id,
			"http_code": code,
			"body": text,
		}
	if code == 401 or code == 403:
		return _status(STATUS_FAILURE, "permission-denied", false, request_id,
			code)
	if code == 404:
		return _status(STATUS_FAILURE, "not-found", false, request_id, code)
	if code == 409 or code == 412:
		return _status(STATUS_CONFLICT, "precondition-failed", false, request_id,
			code, text)
	if code == 400 or code == 0:
		return _status(STATUS_FAILURE, "bad-request", false, request_id, code)
	if code in RETRYABLE_CODES:
		return _status(STATUS_FAILURE, "http-%d" % code, true, request_id, code)
	if code >= 400 and code < 500:
		return _status(STATUS_FAILURE, "http-%d" % code, false, request_id, code)
	return _status(STATUS_FAILURE, "http-%d" % code, true, request_id, code)


func _reply_bytes(body: Variant) -> PackedByteArray:
	if body is PackedByteArray:
		return body as PackedByteArray
	if typeof(body) == TYPE_STRING:
		return (body as String).to_utf8_buffer()
	return PackedByteArray()


func _status(status: String, code: String, retryable: bool, request_id: String,
		http_code: int = 0, body: String = "") -> Dictionary:
	var result: Dictionary = {
		"status": status,
		"code": code,
		"retryable": retryable,
		"request_id": request_id,
	}
	if http_code != 0:
		result["http_code"] = http_code
	if not body.is_empty():
		result["body"] = body
	return result


func _test_state() -> Dictionary:
	return {
		"in_flight": _in_flight,
		"generation": _generation,
		"account": _account_uid,
		"requests": _request_seq,
	}
