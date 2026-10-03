extends "res://scripts/net/identity_adapter.gd"

## Scripted stand-in for the native identity adapter.
##
## Each behavior returns either a sync receipt or a `pending` receipt the test
## settles by hand with `complete_session()` / `complete_error()`. Recorded
## calls let tests assert the service asked for exactly what it should.

var guest_receipt: Dictionary = {"status": STATUS_OK, "session": {
	"kind": KIND_CLOUD, "uid": "fake-anon-uid", "provider": PROVIDER_ANONYMOUS}}
var provider_receipt: Dictionary = {"status": STATUS_OK, "session": {
	"kind": KIND_CLOUD, "uid": "fake-cloud-uid",
	"provider": PROVIDER_PLAY_GAMES}}
var link_receipt: Dictionary = {"status": STATUS_OK, "session": {
	"kind": KIND_CLOUD, "uid": "fake-cloud-uid",
	"provider": PROVIDER_PLAY_GAMES}}
var token_receipt: Dictionary = {"status": STATUS_OK,
	"id_token": "fake-id-token", "token_expires_at": 4102444800000}
var sign_out_receipt: Dictionary = {"status": STATUS_OK}
var delete_receipt: Dictionary = {"status": STATUS_OK}
var session: Dictionary = {"status": STATUS_OK, "kind": KIND_LOCAL_GUEST,
	"uid": "", "provider": ""}

var calls: Array[String] = []
var last_provider: String = ""
var last_options: Dictionary = {}
var last_force_refresh: bool = false
var cancelled_ids: Array[String] = []
# Scripted `cancel()` answer status: "cancelled" stops before mutation,
# "draining" keeps the lock because a mutation already began.
var cancel_status: String = "cancelled"
var auto_session: Dictionary = {}
var auto_error: Dictionary = {}

var _request_counter: int = 0
var _issued: Dictionary = {}
var _completed: Dictionary = {}


func sign_in_guest() -> Dictionary:
	calls.append("sign_in_guest")
	return _answer("sign_in_guest", guest_receipt)


func sign_in_provider(provider: String, options: Dictionary = {}) -> Dictionary:
	calls.append("sign_in_provider")
	last_provider = provider
	last_options = options.duplicate()
	return _answer("sign_in_provider", provider_receipt)


func link_provider(provider: String, options: Dictionary = {}) -> Dictionary:
	calls.append("link_provider")
	last_provider = provider
	last_options = options.duplicate()
	return _answer("link_provider", link_receipt)


func get_session() -> Dictionary:
	return session.duplicate()


func refresh_native_session() -> Dictionary:
	# The fake has no native side: the scripted snapshot is already the
	# truth, exactly like the base contract. Tests set `session` first,
	# then prove the host picks it up through this call.
	return session.duplicate()


func get_id_token(force_refresh: bool = false) -> Dictionary:
	calls.append("get_id_token")
	last_force_refresh = force_refresh
	if str(token_receipt.get("status", "")) == STATUS_PENDING:
		return _pending_receipt("get_id_token")
	return token_receipt.duplicate()


func sign_out() -> Dictionary:
	calls.append("sign_out")
	if str(sign_out_receipt.get("status", "")) == STATUS_PENDING:
		return _pending_receipt("sign_out")
	session = {"status": STATUS_OK, "kind": KIND_LOCAL_GUEST,
		"uid": "", "provider": ""}
	return sign_out_receipt.duplicate()


func delete_account(options: Dictionary = {}) -> Dictionary:
	calls.append("delete_account")
	last_options = options.duplicate()
	if str(delete_receipt.get("status", "")) == STATUS_PENDING:
		return _pending_receipt("delete_account")
	# Like the real SDK, only a genuine success drops the session: a sync
	# error or cancellation keeps the account exactly as it was.
	if str(delete_receipt.get("status", "")) == STATUS_OK:
		session = {"status": STATUS_OK, "kind": KIND_LOCAL_GUEST,
			"uid": "", "provider": ""}
	return delete_receipt.duplicate()


func cancel(request_id: String) -> Dictionary:
	cancelled_ids.append(request_id)
	if cancel_status == STATUS_DRAINING:
		return {"status": STATUS_DRAINING, "request_id": request_id}
	_completed[request_id] = true
	return {"status": STATUS_CANCELLED, "request_id": request_id}


func _first_live_completion(request_id: String) -> bool:
	if not _issued.has(request_id):
		return false
	if _completed.has(request_id):
		return false
	_completed[request_id] = true
	return true


func complete_session(request_id: String, outcome: Dictionary) -> void:
	var folded: Dictionary = outcome.duplicate()
	folded["request_id"] = request_id
	# Like the real adapter, the session cache moves only on the first live
	# completion; the signal still fires so the service's own rejection of
	# stale, cancelled, or double completions is what the test observes.
	if _first_live_completion(request_id):
		if str(folded.get("kind", "")) == KIND_CLOUD \
				and not str(folded.get("uid", "")).is_empty():
			session = {
				"status": STATUS_OK,
				"kind": KIND_CLOUD,
				"uid": str(folded.get("uid", "")),
				"provider": str(folded.get("provider", "")),
			}
		elif folded.has("kind"):
			session = {
				"status": STATUS_OK,
				"kind": KIND_LOCAL_GUEST,
				"uid": "",
				"provider": "",
			}
	session_changed.emit(folded)


func complete_error(request_id: String, outcome: Dictionary) -> void:
	var folded: Dictionary = outcome.duplicate()
	folded["request_id"] = request_id
	# Mirror the real adapter: a live revocation resets the session cache to
	# a local guest before the failure is reported.
	if str(folded.get("code", "")) == "token_revoked" \
			and _first_live_completion(request_id):
		session = {"status": STATUS_OK, "kind": KIND_LOCAL_GUEST,
			"uid": "", "provider": ""}
	operation_failed.emit(folded)


func _answer(operation: String, scripted: Dictionary) -> Dictionary:
	var receipt: Dictionary = scripted.duplicate()
	var status: String = str(receipt.get("status", ""))
	if status == STATUS_PENDING:
		return _pending_receipt(operation)
	if status == STATUS_OK and receipt.has("session"):
		var folded: Dictionary = (receipt["session"] as Dictionary).duplicate()
		session = {
			"status": STATUS_OK,
			"kind": str(folded.get("kind", KIND_LOCAL_GUEST)),
			"uid": str(folded.get("uid", "")),
			"provider": str(folded.get("provider", "")),
		}
	return receipt


func _pending_receipt(operation: String) -> Dictionary:
	_request_counter += 1
	var request_id: String = "fake-%s-%d" % [operation, _request_counter]
	_issued[request_id] = true
	if not auto_session.is_empty():
		var folded: Dictionary = auto_session.duplicate()
		auto_session = {}
		complete_session.call_deferred(request_id, folded)
	elif not auto_error.is_empty():
		var failed: Dictionary = auto_error.duplicate()
		auto_error = {}
		complete_error.call_deferred(request_id, failed)
	return {"status": STATUS_PENDING, "request_id": request_id}
