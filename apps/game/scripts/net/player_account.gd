extends Node

## Stable public player identity, kept separate from sign-in session state.
##
## `ensure_public_id()` loads the saved public ID, or mints a cryptographically
## random one and saves it to `user://player_identity.cfg` before any local
## guest play. The ID is public but not a credential: it is never an email,
## nickname, token, or key. Sign-in, linking, tokens, and cloud UIDs live in
## the injected adapter; this service only records which server identity, if
## any, the adapter confirmed.
##
## Readiness is durability: `public_id()` returns an ID only once it is saved
## to disk. A minted-but-unsaved ID is retained as pending for `retry` (the
## same pending ID is persisted on retry, never a second mint), but it is
## never advertised as ready and every cloud call refuses with
## `identity_not_ready` until the save lands. An ID that was never saved would
## change on relaunch, which is not a durable identity.
##
## The service never claims a cloud registration is confirmed before a server
## identity exists: `is_cloud_linked()` is true only while the adapter reports
## a `cloud` session with a non-empty UID. Cancelled, failed, or conflicting
## linking always keeps the guest identity and its data untouched.
##
## This file knows nothing about the Vault or IAP ledgers. It shares no save
## file, no key, and no signal with them.
##
## The production host (4.0.0) additionally uses the durable canonical-ID
## adoption and the per-SDK-UID binding cache below. Bindings map a hashed
## UID to the public ID that UID plays under; the raw UID, tokens, emails,
## and display names never reach disk. Adoption never silently overwrites a
## differing local binding: that reports `already_bound_elsewhere` and
## keeps old bytes.

signal account_changed(state: Dictionary)
signal account_conflict(conflict: Dictionary)
signal account_error(error: Dictionary)
signal id_token_ready(token: Dictionary)

const IDENTITY_PATH: String = "user://player_identity.cfg"
const IDENTITY_SECTION: String = "identity"
const SCHEMA_VERSION: int = 1
const BINDINGS_PATH: String = "user://player_bindings.cfg"
const BINDINGS_SECTION: String = "bindings"
const BINDINGS_SCHEMA_VERSION: int = 1
const BINDINGS_FILE_MAX_BYTES: int = 65536
# The saved file is about 150 bytes. Anything past this bound is not an
# identity file, so it is rejected before parsing instead of being read.
const IDENTITY_FILE_MAX_BYTES: int = 4096
const PUBLIC_ID_PREFIX: String = "MB-"
const PUBLIC_ID_BYTES: int = 16
const PUBLIC_ID_PATTERN: String = "^MB-[0-9a-f]{32}$"

const ACCOUNT_LOCAL_GUEST: String = "local_guest"
const ACCOUNT_CLOUD: String = "cloud"

# Receipt vocabulary, mirrored from identity_adapter.gd. This service is not
# an adapter subclass (its sign-in/link/delete signatures differ on purpose),
# so it names the shared words itself instead of inheriting them.
const STATUS_OK: String = "ok"
const STATUS_PENDING: String = "pending"
const STATUS_CANCELLED: String = "cancelled"
const STATUS_CONFLICT: String = "conflict"
const STATUS_ERROR: String = "error"
const STATUS_UNSUPPORTED: String = "unsupported"
const STATUS_NOT_CONFIGURED: String = "not_configured"
const KIND_LOCAL_GUEST: String = "local_guest"
const KIND_CLOUD: String = "cloud"
const CODE_USER_CANCELLED: String = "user_cancelled"
const CODE_ALREADY_LINKED_ELSEWHERE: String = "already_linked_elsewhere"
const CODE_NATIVE_MISSING: String = "native_bridge_unavailable"
const CODE_NOT_CONFIGURED: String = "identity_not_configured"
const CODE_NETWORK: String = "network_error"
const CODE_TOKEN_EXPIRED: String = "token_expired"
const CODE_TOKEN_REVOKED: String = "token_revoked"
const CODE_REQUEST_TIMEOUT: String = "request_timeout"
const CODE_NO_PENDING_REQUEST: String = "no_pending_request"
const CODE_ALREADY_PENDING: String = "request_already_pending"
const CODE_IDENTITY_NOT_READY: String = "identity_not_ready"
const CODE_ALREADY_BOUND: String = "already_bound_elsewhere"
const CODE_BINDING_IO: String = "binding_not_saved"
const STATUS_DRAINING: String = "draining"

var _adapter: Node
var _save_path: String = IDENTITY_PATH
var _bindings_path: String = BINDINGS_PATH
var _bindings: Dictionary = {}
var _bindings_loaded: bool = false
var _fresh_guest_on_sign_out: bool = false
var _public_id: String = ""
var _pending_id: String = ""
var _cloud_uid: String = ""
var _cloud_provider: String = ""
var _pending_request_id: String = ""
var _pending_operation: String = ""
var _pending_settled: bool = true
var _recovered_from_corrupt: bool = false
var _signals_connected: bool = false


func setup(adapter: Node, save_path_override: String = "",
		bindings_override: String = "") -> void:
	if _adapter != null and _signals_connected:
		_disconnect_adapter()
	_adapter = adapter
	if not save_path_override.is_empty():
		_save_path = save_path_override
	if not bindings_override.is_empty():
		_bindings_path = bindings_override
	_bindings_loaded = false
	_bindings = {}
	_connect_adapter()


## Production host only: an explicit sign-out mints a fresh guest ID instead
## of keeping the old one, so the signed-out account's ID and save are never
## stolen by the next guest. Default off, so existing guest flows keep their
## durable ID across sign-out and delete.
func enable_fresh_guest_on_sign_out(enabled: bool) -> void:
	_fresh_guest_on_sign_out = enabled


## Stable hash token for one SDK UID. Only this hash is ever written; the
## raw UID stays in memory.
static func uid_binding_hash(uid: String) -> String:
	return uid.strip_edges().sha256_text()


## Durable public ID recorded for one SDK UID, or "" when unknown.
func public_id_for_uid(uid: String) -> String:
	_ensure_bindings()
	var record: Dictionary = _bindings.get(uid_binding_hash(uid), {})
	return str(record.get("public_id", ""))


func ensure_public_id() -> String:
	if not _public_id.is_empty():
		return _public_id
	var loaded: String = _load_saved_id()
	if not loaded.is_empty():
		_public_id = loaded
		_pending_id = ""
		return _public_id
	if _pending_id.is_empty():
		_pending_id = generate_public_id()
	if _save_id(_pending_id):
		_public_id = _pending_id
		_pending_id = ""
		return _public_id
	# The save failed: the minted ID stays pending for a retry, but nothing
	# here advertises it. Returning it would let a caller treat an ID that
	# changes on relaunch as a durable identity.
	return ""


func retry_identity_save() -> bool:
	if not _public_id.is_empty():
		return true
	if _pending_id.is_empty():
		_pending_id = generate_public_id()
	if _save_id(_pending_id):
		_public_id = _pending_id
		_pending_id = ""
		_emit_changed()
		return true
	return false


func public_id() -> String:
	return _public_id


func pending_public_id() -> String:
	return _pending_id


func is_identity_ready() -> bool:
	return not _public_id.is_empty() \
		and is_valid_public_id(_public_id)


func account_kind() -> String:
	if is_cloud_linked():
		return ACCOUNT_CLOUD
	return ACCOUNT_LOCAL_GUEST


func is_cloud_linked() -> bool:
	if _adapter == null:
		return false
	var session: Dictionary = _adapter.get_session()
	if str(session.get("status", "")) != STATUS_OK:
		return false
	if str(session.get("kind", "")) != KIND_CLOUD:
		return false
	var uid: String = str(session.get("uid", ""))
	if uid.is_empty():
		return false
	_cloud_uid = uid
	_cloud_provider = str(session.get("provider", ""))
	return true


func cloud_uid() -> String:
	if is_cloud_linked():
		return _cloud_uid
	return ""


func cloud_provider() -> String:
	if is_cloud_linked():
		return _cloud_provider
	return ""


func recovered_from_corrupt() -> bool:
	return _recovered_from_corrupt


func pending_request() -> Dictionary:
	if _pending_settled or _pending_request_id.is_empty():
		return {"status": STATUS_OK, "pending": false}
	return {
		"status": STATUS_PENDING,
		"pending": true,
		"request_id": _pending_request_id,
		"operation": _pending_operation,
	}


func sign_in_guest() -> Dictionary:
	return _guarded_call("sign_in_guest")


func sign_in_provider(provider: String) -> Dictionary:
	return _guarded_call("sign_in_provider", provider)


func link_current_provider(provider: String) -> Dictionary:
	return _guarded_call("link_provider", provider)


func refresh_session() -> Dictionary:
	if _adapter == null:
		return _unsupported_receipt()
	# The native adapter hydrates a real SDK session through
	# `refresh_native_session()` when the provider task's build supplies it.
	# Cached `get_session()` stays a snapshot, so this is the only call that
	# may reach the SDK; adapters without it keep the snapshot behavior.
	if _adapter.has_method("refresh_native_session"):
		var refusal: Dictionary = _refuse_unless_ready()
		if not refusal.is_empty():
			return refusal
		if not _pending_settled and not _pending_request_id.is_empty():
			return {"status": STATUS_ERROR, "code": CODE_ALREADY_PENDING}
		var receipt: Dictionary = _adapter.refresh_native_session()
		_track_receipt("refresh_session", receipt)
		_fold_sync_receipt(receipt)
		return receipt
	return _adapter.get_session()


func get_id_token(force_refresh: bool = false) -> Dictionary:
	if _adapter == null:
		return _unsupported_receipt()
	var refusal: Dictionary = _refuse_unless_ready()
	if not refusal.is_empty():
		return refusal
	if not _pending_settled and not _pending_request_id.is_empty():
		return {"status": STATUS_ERROR, "code": CODE_ALREADY_PENDING}
	var receipt: Dictionary = _adapter.get_id_token(force_refresh)
	_track_receipt("get_id_token", receipt)
	_fold_sync_receipt(receipt)
	return receipt


func sign_out() -> Dictionary:
	var refusal: Dictionary = _refuse_unless_ready()
	if not refusal.is_empty():
		return refusal
	if not _pending_settled and not _pending_request_id.is_empty():
		return {"status": STATUS_ERROR, "code": CODE_ALREADY_PENDING}
	_clear_cloud_binding()
	if _adapter == null:
		_emit_changed()
		return {"status": STATUS_OK, "kind": KIND_LOCAL_GUEST}
	var receipt: Dictionary = _adapter.sign_out()
	_track_receipt("sign_out", receipt)
	if str(receipt.get("status", "")) == STATUS_OK:
		if _fresh_guest_on_sign_out:
			var rotated: Dictionary = rotate_to_fresh_guest()
			if str(rotated.get("status", "")) != STATUS_OK:
				# The SDK session is gone but the fresh ID did not land:
				# keep the old durable ID (and its save) instead of
				# advertising a guest that changes on relaunch.
				_emit_changed()
				return rotated
		_emit_changed()
	return receipt


## Mint a fresh guest ID and make it the durable current one. The previous
## ID's binding and save files are untouched: nothing is stolen. Returns
## `identity_not_ready` without changing anything when the save fails.
func rotate_to_fresh_guest() -> Dictionary:
	var fresh: String = generate_public_id()
	if _save_id(fresh):
		_public_id = fresh
		_pending_id = ""
		_emit_changed()
		return {"status": STATUS_OK, "kind": KIND_LOCAL_GUEST,
			"public_id": _public_id}
	return {"status": STATUS_ERROR, "code": CODE_IDENTITY_NOT_READY,
		"retryable": true, "public_id": _public_id}


## Adopt the cloud's canonical public ID for one SDK UID, durably. The
## current ID and the UID binding move together: either both land or
## neither does, and old bytes are preserved on failure. When this UID
## already owns a *different* local ID, that is an explicit conflict, not
## a silent overwrite: nothing changes and the caller asks the player.
func adopt_canonical_id(uid: String, canonical_id: String) -> Dictionary:
	var clean_uid: String = uid.strip_edges()
	var clean_id: String = canonical_id.strip_edges()
	if clean_uid.is_empty() or not is_valid_public_id(clean_id):
		return {"status": STATUS_ERROR, "code": CODE_IDENTITY_NOT_READY,
			"retryable": false}
	_ensure_bindings()
	var key: String = uid_binding_hash(clean_uid)
	var record: Dictionary = _bindings.get(key, {})
	var known: String = str(record.get("public_id", ""))
	if not known.is_empty() and known != clean_id:
		return {"status": STATUS_CONFLICT, "code": CODE_ALREADY_BOUND,
			"public_id": _public_id, "known_id": known,
			"canonical_id": clean_id}
	var previous_id: String = _public_id
	var previous_bindings: Dictionary = _bindings.duplicate(true)
	if not _save_id(clean_id):
		return {"status": STATUS_ERROR, "code": CODE_IDENTITY_NOT_READY,
			"retryable": true, "public_id": _public_id}
	_bindings[key] = {
		"public_id": clean_id,
		"provider": str(record.get("provider", _cloud_provider)),
	}
	if not _save_bindings():
		# The ID file moved but the binding did not: roll the ID back so
		# the two never disagree about who owns this UID.
		_bindings = previous_bindings
		if previous_id.is_empty():
			_remove_file(_save_path)
			_remove_file(_save_path + ".bak")
		else:
			_save_id(previous_id)
		return {"status": STATUS_ERROR, "code": CODE_BINDING_IO,
			"retryable": true, "public_id": _public_id}
	_public_id = clean_id
	_pending_id = ""
	_emit_changed()
	return {"status": STATUS_OK, "public_id": _public_id,
		"canonical_id": clean_id}


## Forget one UID's binding durably. Used after a player-confirmed account
## deletion removed the cloud side first. The identity file is untouched.
func forget_binding(uid: String) -> bool:
	_ensure_bindings()
	var key: String = uid_binding_hash(uid.strip_edges())
	if not _bindings.has(key):
		return true
	var previous: Dictionary = _bindings.duplicate(true)
	_bindings.erase(key)
	if _save_bindings():
		return true
	_bindings = previous
	return false


## True while the current cloud UID has a durable ID binding.
func uid_bound() -> bool:
	if not is_cloud_linked():
		return false
	return not public_id_for_uid(_cloud_uid).is_empty()


func delete_account(keep_provider_grant: bool = false) -> Dictionary:
	var refusal: Dictionary = _refuse_unless_ready()
	if not refusal.is_empty():
		return refusal
	if not _pending_settled and not _pending_request_id.is_empty():
		return {"status": STATUS_ERROR, "code": CODE_ALREADY_PENDING}
	if _adapter == null:
		_clear_cloud_binding()
		_emit_changed()
		return {"status": STATUS_OK, "kind": KIND_LOCAL_GUEST}
	# No auth code, token, or password crosses here. On iOS the native side
	# re-runs the Sign in with Apple sheet itself for a fresh revocation code
	# unless the caller explicitly keeps the provider grant.
	var options: Dictionary = {"keep_provider_grant": keep_provider_grant}
	var receipt: Dictionary = _adapter.delete_account(options)
	_track_receipt("delete_account", receipt)
	if str(receipt.get("status", "")) == STATUS_OK:
		# Only a real success clears the live binding. A pending native
		# delete keeps it until the terminal outcome: clearing early
		# would read as proof the deletion succeeded while the SDK still
		# owns the account, and a failure would strand the cache.
		_clear_cloud_binding()
		_emit_changed()
	return receipt


func cancel_pending() -> Dictionary:
	if _pending_settled or _pending_request_id.is_empty():
		return {"status": STATUS_ERROR, "code": CODE_NO_PENDING_REQUEST}
	if _adapter == null:
		_settle_pending()
		return {"status": STATUS_CANCELLED}
	var receipt: Dictionary = _adapter.cancel(_pending_request_id)
	if str(receipt.get("status", "")) == STATUS_DRAINING:
		# A native mutation already began: the lock stays and the terminal
		# outcome still arrives on the signals. The caller shows a finishing
		# state instead of a cancelled one.
		return {"status": STATUS_DRAINING,
			"request_id": _pending_request_id}
	_settle_pending()
	# Cancelling never touches the guest ID or the cloud binding snapshot:
	# the account the user had before the attempt is the account they keep.
	_emit_changed()
	if str(receipt.get("status", "")) == STATUS_OK \
			or str(receipt.get("status", "")) == STATUS_CANCELLED:
		return {"status": STATUS_CANCELLED}
	return receipt


static func generate_public_id() -> String:
	var crypto: Crypto = Crypto.new()
	var bytes: PackedByteArray = crypto.generate_random_bytes(PUBLIC_ID_BYTES)
	return PUBLIC_ID_PREFIX + bytes.hex_encode()


static func is_valid_public_id(value: String) -> bool:
	var pattern: RegEx = RegEx.new()
	if pattern.compile(PUBLIC_ID_PATTERN) != OK:
		return false
	return pattern.search(value.strip_edges()) != null


func _guarded_call(operation: String, provider: String = "") -> Dictionary:
	var refusal: Dictionary = _refuse_unless_ready()
	if not refusal.is_empty():
		return refusal
	if _adapter == null:
		return _unsupported_receipt()
	if not _pending_settled and not _pending_request_id.is_empty():
		return {"status": STATUS_ERROR, "code": CODE_ALREADY_PENDING}
	var receipt: Dictionary
	if operation == "sign_in_guest":
		receipt = _adapter.sign_in_guest()
	elif operation == "sign_in_provider":
		receipt = _adapter.sign_in_provider(provider, {})
	else:
		receipt = _adapter.link_provider(provider, {})
	_track_receipt(operation, receipt)
	_fold_sync_receipt(receipt)
	return receipt


func _refuse_unless_ready() -> Dictionary:
	ensure_public_id()
	if is_identity_ready():
		return {}
	return {"status": STATUS_ERROR, "code": CODE_IDENTITY_NOT_READY}


func _track_receipt(operation: String, receipt: Dictionary) -> void:
	if str(receipt.get("status", "")) != STATUS_PENDING:
		return
	_pending_request_id = str(receipt.get("request_id", ""))
	_pending_operation = operation
	_pending_settled = false


func _fold_sync_receipt(receipt: Dictionary) -> void:
	var status: String = str(receipt.get("status", ""))
	if status == STATUS_CONFLICT:
		account_conflict.emit(_public_conflict(receipt))
	elif status == STATUS_ERROR \
			or status == STATUS_UNSUPPORTED \
			or status == STATUS_NOT_CONFIGURED:
		# A synchronous terminal refusal (reduced SDK or config) settles
		# through the same honest error path as any sync failure, so a
		# busy entry unblocks without inventing a login. IDs, bindings,
		# and locks are untouched: only the error signal fires.
		account_error.emit(_public_error(receipt))
	elif status == STATUS_CANCELLED:
		_emit_changed()
	elif status == STATUS_OK and receipt.has("session"):
		# Sync answers carry no request id, so they apply directly instead
		# of passing the pending check below.
		if typeof(receipt["session"]) == TYPE_DICTIONARY:
			_apply_session_outcome(receipt["session"])


func _on_session_changed(session: Variant) -> void:
	if typeof(session) != TYPE_DICTIONARY:
		return
	var outcome: Dictionary = session as Dictionary
	if not _accept_outcome(outcome):
		return
	if outcome.has("id_token"):
		# A token answer settles the token request without moving the
		# account. The token is re-emitted once for immediate use and is
		# never written anywhere by this service.
		var token_receipt: Dictionary = {
			"id_token": str(outcome.get("id_token", "")),
			"token_expires_at": outcome.get("token_expires_at", 0),
			"request_id": str(outcome.get("request_id", "")),
		}
		_settle_pending()
		id_token_ready.emit(token_receipt)
		return
	_settle_pending()
	_apply_session_outcome(outcome)


func _on_operation_failed(error: Variant) -> void:
	if typeof(error) != TYPE_DICTIONARY:
		return
	var outcome: Dictionary = error as Dictionary
	if not _accept_outcome(outcome):
		return
	_settle_pending()
	if str(outcome.get("status", "")) == STATUS_CONFLICT:
		account_conflict.emit(_public_conflict(outcome))
		_emit_changed()
		return
	if str(outcome.get("status", "")) == STATUS_CANCELLED:
		_emit_changed()
		return
	var code: String = str(outcome.get("code", ""))
	if code == CODE_TOKEN_REVOKED:
		_clear_cloud_binding()
	account_error.emit(_public_error(outcome))
	_emit_changed()


func _apply_session_outcome(outcome: Dictionary) -> void:
	var kind: String = str(outcome.get("kind", ""))
	if kind == KIND_CLOUD and not str(outcome.get("uid", "")).is_empty():
		_cloud_uid = str(outcome.get("uid", ""))
		_cloud_provider = str(outcome.get("provider", ""))
		# The UID/ID pair is bound durably by `adopt_canonical_id` once the
		# cloud names this UID's canonical ID — never from the session
		# echo itself, which would pre-claim the binding and turn every
		# restored canonical ID into a false conflict.
	else:
		_clear_cloud_binding()
	_emit_changed()


func _accept_outcome(outcome: Dictionary) -> bool:
	var request_id: String = str(outcome.get("request_id", ""))
	if _pending_settled or _pending_request_id.is_empty():
		return false
	if request_id.is_empty() or request_id != _pending_request_id:
		return false
	return true


func _settle_pending() -> void:
	_pending_request_id = ""
	_pending_operation = ""
	_pending_settled = true


func _clear_cloud_binding() -> void:
	_cloud_uid = ""
	_cloud_provider = ""


func _emit_changed() -> void:
	account_changed.emit(current_state())


func _unsupported_receipt() -> Dictionary:
	return {
		"status": STATUS_UNSUPPORTED,
		"code": CODE_NATIVE_MISSING,
	}


func current_state() -> Dictionary:
	return {
		"public_id": _public_id,
		"ready": is_identity_ready(),
		"has_pending_id": not _pending_id.is_empty(),
		"kind": account_kind(),
		"cloud_uid": cloud_uid(),
		"cloud_provider": cloud_provider(),
		"uid_bound": uid_bound(),
		"recovered_from_corrupt": _recovered_from_corrupt,
	}


func _ensure_bindings() -> void:
	if _bindings_loaded:
		return
	_bindings_loaded = true
	_bindings = _load_bindings()


func _load_bindings() -> Dictionary:
	var found: Dictionary = {}
	if not _save_exists(_bindings_path):
		return found
	if _file_byte_length(_bindings_path) > BINDINGS_FILE_MAX_BYTES:
		return found
	var config: ConfigFile = ConfigFile.new()
	if config.load(_bindings_path) != OK:
		return found
	if int(config.get_value(BINDINGS_SECTION, "schema_version", 0)) \
			!= BINDINGS_SCHEMA_VERSION:
		return found
	for section in config.get_sections():
		if section == BINDINGS_SECTION:
			continue
		var key: String = str(section).strip_edges()
		if key.length() != 64:
			continue
		var clean: bool = true
		for code in key.to_utf8_buffer():
			var hex: bool = (code >= 48 and code <= 57) \
				or (code >= 97 and code <= 102)
			if not hex:
				clean = false
				break
		if not clean:
			continue
		var bound: String = str(config.get_value(
			section, "public_id", "")).strip_edges()
		if not is_valid_public_id(bound):
			continue
		found[key] = {
			"public_id": bound,
			"provider": str(config.get_value(
				section, "provider", "")).strip_edges(),
		}
	return found


func _save_bindings() -> bool:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(BINDINGS_SECTION, "schema_version",
		BINDINGS_SCHEMA_VERSION)
	for key in _bindings.keys():
		var record: Dictionary = _bindings[key]
		config.set_value(key, "public_id",
			str(record.get("public_id", "")))
		config.set_value(key, "provider",
			str(record.get("provider", "")))
	var temp_path: String = _bindings_path + ".tmp"
	if config.save(temp_path) != OK:
		DirAccess.remove_absolute(_global_path(temp_path))
		return false
	if _rename_file(temp_path, _bindings_path) != OK:
		DirAccess.remove_absolute(_global_path(temp_path))
		return false
	_copy_file(_bindings_path, _bindings_path + ".bak")
	return true


func _remove_file(path: String) -> void:
	if _save_exists(path):
		DirAccess.remove_absolute(_global_path(path))


func _public_conflict(receipt: Dictionary) -> Dictionary:
	return {
		"status": STATUS_CONFLICT,
		"code": str(receipt.get("code", CODE_ALREADY_LINKED_ELSEWHERE)),
		"provider": str(receipt.get("provider", "")),
		"public_id": _public_id,
	}


func _public_error(receipt: Dictionary) -> Dictionary:
	var clean: Dictionary = {
		"status": str(receipt.get("status", STATUS_ERROR)),
		"code": str(receipt.get("code", CODE_NETWORK)),
		"retryable": bool(receipt.get("retryable", false)),
		"public_id": _public_id,
	}
	if receipt.has("missing"):
		clean["missing"] = (receipt.get("missing", []) as Array).duplicate()
	return clean


func _connect_adapter() -> void:
	if _adapter == null or _signals_connected:
		return
	if _adapter.has_signal("session_changed"):
		_adapter.session_changed.connect(_on_session_changed)
	if _adapter.has_signal("operation_failed"):
		_adapter.operation_failed.connect(_on_operation_failed)
	_signals_connected = true


func _disconnect_adapter() -> void:
	if _adapter == null or not _signals_connected:
		return
	if _adapter.has_signal("session_changed") \
			and _adapter.session_changed.is_connected(_on_session_changed):
		_adapter.session_changed.disconnect(_on_session_changed)
	if _adapter.has_signal("operation_failed") \
			and _adapter.operation_failed.is_connected(_on_operation_failed):
		_adapter.operation_failed.disconnect(_on_operation_failed)
	_signals_connected = false


func _load_saved_id() -> String:
	var primary: String = _read_id_file(_save_path)
	if not primary.is_empty():
		return primary
	var backup: String = _read_id_file(_save_path + ".bak")
	if not backup.is_empty():
		# The primary is unreadable but the backup is intact: restore it so
		# the next boot reads the primary again.
		_save_id(backup)
		return backup
	if _save_exists(_save_path) or _save_exists(_save_path + ".bak"):
		_recovered_from_corrupt = true
	return ""


func _read_id_file(path: String) -> String:
	if not _save_exists(path):
		return ""
	if _file_byte_length(path) > IDENTITY_FILE_MAX_BYTES:
		return ""
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return ""
	var schema: Variant = config.get_value(IDENTITY_SECTION, "schema_version", 0)
	if typeof(schema) != TYPE_INT or int(schema) != SCHEMA_VERSION:
		return ""
	var raw: Variant = config.get_value(IDENTITY_SECTION, "public_id", "")
	if typeof(raw) != TYPE_STRING:
		return ""
	var candidate: String = str(raw).strip_edges()
	if not is_valid_public_id(candidate):
		return ""
	return candidate


func _file_byte_length(path: String) -> int:
	var reader: FileAccess = FileAccess.open(path, FileAccess.READ)
	if reader == null:
		return IDENTITY_FILE_MAX_BYTES + 1
	var length: int = int(reader.get_length())
	reader.close()
	return length


func _save_exists(path: String) -> bool:
	return FileAccess.file_exists(path)


func _save_id(public_id: String) -> bool:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(IDENTITY_SECTION, "schema_version", SCHEMA_VERSION)
	config.set_value(IDENTITY_SECTION, "public_id", public_id)
	config.set_value(
		IDENTITY_SECTION, "created_utc", Time.get_datetime_string_from_system(true))
	# Atomic write: a crash or a failed linking attempt must never leave a
	# half-written primary. The id is immutable once minted, so the backup
	# mirrors the primary after every successful save instead of lagging one
	# write behind: either copy alone holds the whole truth.
	var temp_path: String = _save_path + ".tmp"
	if config.save(temp_path) != OK:
		DirAccess.remove_absolute(_global_path(temp_path))
		return false
	if _rename_file(temp_path, _save_path) != OK:
		DirAccess.remove_absolute(_global_path(temp_path))
		return false
	_copy_file(_save_path, _save_path + ".bak")
	return true


func _copy_file(from_path: String, to_path: String) -> void:
	var bytes: PackedByteArray = _read_all_bytes(from_path)
	if bytes.is_empty():
		return
	var writer: FileAccess = FileAccess.open(to_path, FileAccess.WRITE)
	if writer == null:
		return
	writer.store_buffer(bytes)
	writer.close()


func _read_all_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var reader: FileAccess = FileAccess.open(path, FileAccess.READ)
	if reader == null:
		return PackedByteArray()
	var bytes: PackedByteArray = reader.get_buffer(reader.get_length())
	reader.close()
	return bytes


func _rename_file(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(
		_global_path(from_path), _global_path(to_path))


func _global_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
