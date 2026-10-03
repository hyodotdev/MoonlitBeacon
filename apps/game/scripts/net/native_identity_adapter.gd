extends "res://scripts/net/identity_adapter.gd"

## Adapt the MoonlitIdentity native bridge to the game's small adapter contract.
##
## The bridge speaks request/response Dictionaries over one completion signal;
## this layer translates those into `session_changed` / `operation_failed`
## with a cached session snapshot. Stale or double native callbacks are
## dropped by request id, so a late answer can never move the account.
##
## Tests inject a fake bridge object with the same method names. The game never
## touches the bridge directly.

const BRIDGE_AUTOLOAD_PATH: String = "/root/MoonlitIdentity"
const BRIDGE_IOS_CLASS: String = "MoonlitIdentityIos"
const SETTLED_CAP: int = 64

var _bridge: Node
var _session: Dictionary = {
	"status": STATUS_OK,
	"kind": KIND_LOCAL_GUEST,
	"uid": "",
	"provider": "",
}
var _pending_ids: Dictionary = {}
var _settled_ids: Dictionary = {}
var _settled_order: Array = []
var _signals_connected: bool = false


func _init(bridge: Node = null) -> void:
	_bridge = bridge


func get_capabilities() -> Dictionary:
	var bridge: Node = _require_bridge()
	if bridge == null:
		return get_capabilities_offline()
	if not bridge.has_method("get_capabilities"):
		return get_capabilities_offline()
	var caps: Variant = bridge.get_capabilities()
	if typeof(caps) != TYPE_DICTIONARY:
		return get_capabilities_offline()
	return caps as Dictionary


func get_capabilities_offline() -> Dictionary:
	return {
		"status": STATUS_UNSUPPORTED,
		"code": CODE_NATIVE_MISSING,
		"supported": false,
		"providers": [],
		"guest": true,
	}


func sign_in_guest() -> Dictionary:
	return _forward("sign_in_guest")


func sign_in_provider(provider: String, options: Dictionary = {}) -> Dictionary:
	return _forward("sign_in_provider", [provider, options])


func link_provider(provider: String, options: Dictionary = {}) -> Dictionary:
	return _forward("link_provider", [provider, options])


func get_session() -> Dictionary:
	return _session.duplicate()


func refresh_native_session() -> Dictionary:
	# The bridge's real `get_session`, folded like any other call: a sync
	# answer applies through `_fold_sync_outcome`, a `pending` receipt
	# settles on the signal through `_on_bridge_completed`. This is how an
	# SDK-restored sign-in hydrates the snapshot after a process restart,
	# without a new provider sign-in and without UI.
	return _forward("get_session")


func get_id_token(force_refresh: bool = false) -> Dictionary:
	return _forward("get_id_token", [force_refresh])


func sign_out() -> Dictionary:
	var receipt: Dictionary = _forward("sign_out")
	if str(receipt.get("status", "")) == STATUS_OK:
		_reset_session()
		session_changed.emit(get_session())
	return receipt


func delete_account(options: Dictionary = {}) -> Dictionary:
	var receipt: Dictionary = _forward("delete_account", [options])
	if str(receipt.get("status", "")) == STATUS_OK:
		_reset_session()
		session_changed.emit(get_session())
	return receipt


func cancel(request_id: String) -> Dictionary:
	if not _pending_ids.has(request_id):
		return {"status": STATUS_ERROR, "code": CODE_NO_PENDING_REQUEST}
	var bridge: Node = _require_bridge()
	var draining: bool = false
	if bridge != null and bridge.has_method("cancel_request"):
		var answer: Variant = bridge.cancel_request(request_id)
		if typeof(answer) == TYPE_DICTIONARY:
			draining = str((answer as Dictionary).get("status", "")) \
				== STATUS_DRAINING
	if draining:
		# The mutation is still draining natively: keep tracking this id so
		# the terminal outcome lands instead of being dropped as stale.
		return {"status": STATUS_DRAINING, "request_id": request_id}
	_pending_ids.erase(request_id)
	_remember_settled(request_id)
	return {"status": STATUS_CANCELLED, "request_id": request_id}


func _forward(method: String, args: Array = []) -> Dictionary:
	var bridge: Node = _require_bridge()
	if bridge == null:
		return _unsupported_receipt()
	if not bridge.has_method(method):
		return _unsupported_receipt()
	var receipt: Variant = bridge.callv(method, args)
	if typeof(receipt) != TYPE_DICTIONARY:
		return _unsupported_receipt()
	var folded: Dictionary = receipt as Dictionary
	_note_receipt(method, folded)
	return folded


func _note_receipt(method: String, receipt: Dictionary) -> void:
	if str(receipt.get("status", "")) != STATUS_PENDING:
		_fold_sync_outcome(receipt)
		return
	var request_id: String = str(receipt.get("request_id", ""))
	if request_id.is_empty():
		return
	_pending_ids[request_id] = method


func _fold_sync_outcome(receipt: Dictionary) -> void:
	var status: String = str(receipt.get("status", ""))
	if status == STATUS_OK and receipt.has("session"):
		_apply_session(receipt["session"])
	elif status == STATUS_OK and str(receipt.get("kind", "")) != "":
		_apply_session(receipt)


func _on_bridge_completed(outcome: Variant) -> void:
	if typeof(outcome) != TYPE_DICTIONARY:
		return
	var folded: Dictionary = (outcome as Dictionary).duplicate()
	var request_id: String = str(folded.get("request_id", ""))
	if request_id.is_empty():
		return
	if _settled_ids.has(request_id):
		return
	if not _pending_ids.has(request_id):
		return
	if str(folded.get("status", "")) == STATUS_DRAINING:
		# Draining is a cancel/timeout answer, never a terminal outcome. If
		# one ever arrives on the signal, the lock simply stays.
		return
	var method: String = str(_pending_ids[request_id])
	_pending_ids.erase(request_id)
	_remember_settled(request_id)
	var status: String = str(folded.get("status", ""))
	if status == STATUS_OK:
		if method == "get_id_token":
			_emit_token_session(folded)
		else:
			_apply_session(folded, request_id)
		return
	if status == STATUS_CONFLICT:
		operation_failed.emit(_public_outcome(folded))
		return
	var code: String = str(folded.get("code", ""))
	if code == CODE_TOKEN_REVOKED:
		_reset_session()
		session_changed.emit(get_session())
	operation_failed.emit(_public_outcome(folded))


func _apply_session(outcome: Dictionary, request_id: String = "") -> void:
	var kind: String = str(outcome.get("kind", KIND_LOCAL_GUEST))
	if kind == KIND_CLOUD and str(outcome.get("uid", "")).is_empty():
		# A cloud claim without a server UID is not a registration. Keep the
		# guest session rather than record a half-linked account.
		operation_failed.emit({
			"status": STATUS_ERROR,
			"code": CODE_NETWORK,
			"retryable": true,
			"request_id": str(outcome.get("request_id", "")),
		})
		return
	_session = {
		"status": STATUS_OK,
		"kind": kind,
		"uid": str(outcome.get("uid", "")),
		"provider": str(outcome.get("provider", "")),
	}
	# The cache stays a clean snapshot: no id, no token. Only the matching
	# async success carries its accepted id onward, on an ephemeral event
	# copy, so the account's ownership guard can settle its pending request.
	# Sync folds pass no id and keep emitting the bare snapshot.
	var event: Dictionary = get_session()
	if not request_id.is_empty():
		event["request_id"] = request_id
	session_changed.emit(event)


func _emit_token_session(outcome: Dictionary) -> void:
	# Token answers ride on `session_changed` with the cached session plus
	# the fresh token fields. This is the only signal that ever carries a
	# token; every other outcome is scrubbed by `_public_outcome`.
	var with_token: Dictionary = get_session()
	with_token["id_token"] = str(outcome.get("id_token", ""))
	with_token["token_expires_at"] = outcome.get("token_expires_at", 0)
	with_token["request_id"] = str(outcome.get("request_id", ""))
	session_changed.emit(with_token)


func settled_request_count() -> int:
	# Test hook: proves the settled-id bookkeeping stays bounded.
	return _settled_ids.size()


func _remember_settled(request_id: String) -> void:
	if _settled_ids.has(request_id):
		return
	_settled_ids[request_id] = true
	_settled_order.append(request_id)
	while _settled_order.size() > SETTLED_CAP:
		var oldest: Variant = _settled_order.pop_front()
		_settled_ids.erase(oldest)


func _reset_session() -> void:
	_session = {
		"status": STATUS_OK,
		"kind": KIND_LOCAL_GUEST,
		"uid": "",
		"provider": "",
	}


func _public_outcome(outcome: Dictionary) -> Dictionary:
	var clean: Dictionary = {
		"status": str(outcome.get("status", STATUS_ERROR)),
		"code": str(outcome.get("code", CODE_NETWORK)),
		"retryable": bool(outcome.get("retryable", false)),
		"request_id": str(outcome.get("request_id", "")),
	}
	if outcome.has("provider"):
		clean["provider"] = str(outcome.get("provider", ""))
	if outcome.has("missing"):
		clean["missing"] = (outcome.get("missing", []) as Array).duplicate()
	# Tokens, auth codes, emails, and display names never leave this layer.
	return clean


func _require_bridge() -> Node:
	if _bridge != null:
		_connect_bridge()
		return _bridge
	_bridge = get_node_or_null(BRIDGE_AUTOLOAD_PATH)
	_connect_bridge()
	return _bridge


func _connect_bridge() -> void:
	if _bridge == null or _signals_connected:
		return
	if not _bridge.has_signal("request_completed"):
		return
	_bridge.request_completed.connect(_on_bridge_completed)
	_signals_connected = true


func _exit_tree() -> void:
	if _bridge != null and _signals_connected \
			and _bridge.has_signal("request_completed") \
			and _bridge.request_completed.is_connected(_on_bridge_completed):
		_bridge.request_completed.disconnect(_on_bridge_completed)
	_signals_connected = false
