extends RefCounted

## One private versioned checkpoint per Firebase UID.
##
## The cloud holds a single document (`mb_checkpoints_v1/{uid}`) with an
## integer revision and a bounded Journey payload. Writes use compare-and-swap:
## the client reads the remote revision and update time, then commits
## revision + 1 guarded by that update time. A stale guard reports an explicit
## conflict carrying safe local and remote summaries; the integration chooses
## local or remote afterwards. No automatic clock-timestamp choice is made.
##
## Local changes coalesce into one pending notification until the future
## integration flushes them. Failed saves are retained for retry, and success
## is reported only after the server acknowledges. A downloaded payload still
## needs the Journey validator before gameplay applies it; this helper never
## applies gameplay itself. Paid entitlements and Vault ledgers are rejected
## from every payload.

const CloudSchema: Script = preload("res://scripts/cloud/cloud_schema.gd")

const FIRST_REVISION: int = 1

var _pending_uid: String = ""
var _pending_revision: int = 0
var _pending_payload: String = ""
var _pending_coalesced: int = 0
var _failed_save: Dictionary = {}
var _last_acked_revision: int = 0
var _owner_uid: String = ""
var _owner_generation: int = 0


## Bind the queue to one account. Clears the previous account's ephemeral
## queue/failure state and retires its in-flight completions: a late reply
## for the old account reports cancelled and mutates nothing. Unbound
## instances (unit tests) skip the ownership checks.
func switch_account(uid: String) -> void:
	_owner_uid = uid
	_owner_generation += 1
	_last_acked_revision = 0
	take_pending()
	clear_failed_save()


func _stale(captured: int) -> bool:
	return captured != _owner_generation


func has_pending() -> bool:
	return not _pending_uid.is_empty()


func pending_coalesced_count() -> int:
	return _pending_coalesced


func last_acked_revision() -> int:
	return _last_acked_revision


func failed_save() -> Dictionary:
	return _failed_save.duplicate(true)


func clear_failed_save() -> void:
	_failed_save = {}


func checkpoint_relative_path(uid: String) -> String:
	return "documents/%s/%s" % [CloudSchema.CHECKPOINT_COLLECTION, uid]


func checkpoint_body(uid: String, revision: int, payload: String) -> Dictionary:
	return {
		"fields": {
			"uid": CloudSchema.encode_string(uid),
			"revision": CloudSchema.encode_int(revision),
			"payload": CloudSchema.encode_string(payload),
			"schema": CloudSchema.encode_int(CloudSchema.SCHEMA_VERSION),
			"updated_at": CloudSchema.encode_timestamp_rfc3339(
				CloudSchema.now_rfc3339()),
		}
	}


## Queue a local change for the future integration flush. Only the latest
## stable payload is kept; rapid edits coalesce into one notification.
func queue_checkpoint(uid: String, revision: int, payload: String) -> Dictionary:
	if not _owner_uid.is_empty() and uid != _owner_uid:
		return {"status": "failure", "code": "wrong-account",
			"retryable": false}
	if not CloudSchema.is_valid_uid(uid):
		return {"status": "failure", "code": "invalid-uid", "retryable": false}
	if revision < FIRST_REVISION:
		return {"status": "failure", "code": "invalid-revision",
			"retryable": false}
	var payload_check: Dictionary = CloudSchema.validate_checkpoint_payload(
		payload)
	if not bool(payload_check.get("ok", false)):
		return {"status": "failure", "code": str(payload_check.get("error", "")),
			"retryable": false}
	if CloudSchema.checkpoint_has_forbidden_ledger_keys(payload):
		return {"status": "failure", "code": "ledger-keys-rejected",
			"retryable": false}
	if _pending_uid == uid and _pending_payload == payload \
			and _pending_revision == revision:
		return {"status": "ok", "code": "already-queued", "coalesced": true}
	_pending_uid = uid
	_pending_revision = revision
	_pending_payload = payload
	_pending_coalesced += 1
	return {"status": "ok", "code": "queued", "coalesced": _pending_coalesced > 1}


func peek_pending() -> Dictionary:
	if _pending_uid.is_empty():
		return {}
	return {
		"uid": _pending_uid,
		"revision": _pending_revision,
		"payload": _pending_payload,
		"coalesced": _pending_coalesced,
	}


func take_pending() -> Dictionary:
	var pending: Dictionary = peek_pending()
	_pending_uid = ""
	_pending_revision = 0
	_pending_payload = ""
	_pending_coalesced = 0
	return pending


## Reads the remote checkpoint. The returned payload carries
## `needs_validator: true`: gameplay must run it through the Journey validator
## before applying anything.
func load_remote(transport: RefCounted, uid: String) -> Dictionary:
	if not CloudSchema.is_valid_uid(uid):
		return {"status": "failure", "code": "invalid-uid", "retryable": false}
	if transport == null or not transport.has_method("get_document"):
		return {"status": "unconfigured", "code": "missing-transport",
			"retryable": false}
	var captured: int = _owner_generation
	var reply: Dictionary = await transport.call("get_document",
		checkpoint_relative_path(uid))
	if _stale(captured):
		return {"status": "cancelled", "code": "stale-reply",
			"retryable": false}
	if str(reply.get("status", "")) != "ok":
		return reply
	return _parse_remote(str(reply.get("body", "")))


func _parse_remote(body: String) -> Dictionary:
	var decoded: Dictionary = CloudSchema.parse_json_value(body)
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_DICTIONARY:
		return {"status": "failure", "code": "bad-checkpoint-body",
			"retryable": false}
	var envelope: Dictionary = decoded.get("value")
	var fields: Dictionary = envelope.get("fields", {})
	var revision: int = CloudSchema.decode_int(fields, "revision")
	var payload: String = CloudSchema.decode_string(fields, "payload")
	var update_time: String = str(envelope.get("updateTime", ""))
	if revision < FIRST_REVISION:
		return {"status": "failure", "code": "bad-checkpoint-revision",
			"retryable": false}
	return {
		"status": "ok",
		"revision": revision,
		"payload": payload,
		"update_time": update_time,
		"needs_validator": true,
		"summary": CloudSchema.summarize_payload(payload, revision),
	}


## Saves revision `base_revision + 1` guarded by `base_update_time`. Pass an
## empty base update time only for the first revision of a new document.
func save_revision(transport: RefCounted, uid: String, base_revision: int,
		base_update_time: String, payload: String) -> Dictionary:
	if not CloudSchema.is_valid_uid(uid):
		return {"status": "failure", "code": "invalid-uid", "retryable": false}
	var payload_check: Dictionary = CloudSchema.validate_checkpoint_payload(
		payload)
	if not bool(payload_check.get("ok", false)):
		return {"status": "failure", "code": str(payload_check.get("error", "")),
			"retryable": false}
	if CloudSchema.checkpoint_has_forbidden_ledger_keys(payload):
		return {"status": "failure", "code": "ledger-keys-rejected",
			"retryable": false}
	if transport == null or not transport.has_method("post"):
		return {"status": "unconfigured", "code": "missing-transport",
			"retryable": false}
	var next_revision: int = base_revision + 1
	if next_revision < FIRST_REVISION:
		return {"status": "failure", "code": "invalid-revision",
			"retryable": false}
	var commit_body: Dictionary = {
		"writes": [
			{
				"update": {
					"name": CloudSchema.document_name(
						CloudSchema.CHECKPOINT_COLLECTION, uid),
					"fields": (checkpoint_body(uid, next_revision, payload) \
						as Dictionary)["fields"],
				},
				"currentDocument": _cas_precondition(
					base_revision, base_update_time),
			}
		]
	}
	var captured: int = _owner_generation
	var reply: Dictionary = await transport.call("post", "documents:commit",
		JSON.stringify(commit_body))
	if _stale(captured):
		return {"status": "cancelled", "code": "stale-reply",
			"retryable": false}
	var status: String = str(reply.get("status", "failure"))
	if status == "ok":
		_last_acked_revision = next_revision
		_failed_save = {}
		_drain_if_committed(uid, payload)
		return {"status": "ok", "revision": next_revision}
	if status == "conflict":
		_failed_save = {
			"uid": uid, "base_revision": base_revision,
			"base_update_time": base_update_time, "payload": payload,
			"code": "revision-conflict",
		}
		var remote: Dictionary = await load_remote(transport, uid)
		if _stale(captured):
			return {"status": "cancelled", "code": "stale-reply",
				"retryable": false}
		var remote_summary: Dictionary = {}
		var remote_revision: int = -1
		if str(remote.get("status", "")) == "ok":
			remote_summary = remote.get("summary", {})
			remote_revision = int(remote.get("revision", -1))
		return {
			"status": "conflict",
			"code": "revision-conflict",
			"retryable": false,
			"local_summary": CloudSchema.summarize_payload(
				payload, next_revision),
			"remote_summary": remote_summary,
			"local_revision": next_revision,
			"remote_revision": remote_revision,
			"remote": remote,
		}
	if status == "offline" or status == "unconfigured" \
			or status == "cancelled":
		_failed_save = {
			"uid": uid, "base_revision": base_revision,
			"base_update_time": base_update_time, "payload": payload,
			"code": str(reply.get("code", status)),
		}
		return reply
	_failed_save = {
		"uid": uid, "base_revision": base_revision,
		"base_update_time": base_update_time, "payload": payload,
		"code": str(reply.get("code", "save-failed")),
	}
	return reply


## Retry the retained failed save after the caller re-reads the remote state.
func retry_failed_save(transport: RefCounted) -> Dictionary:
	if _failed_save.is_empty():
		return {"status": "failure", "code": "no-failed-save",
			"retryable": false}
	var uid: String = str(_failed_save.get("uid", ""))
	var remote: Dictionary = await load_remote(transport, uid)
	if str(remote.get("status", "")) != "ok":
		if str(remote.get("code", "")) == "not-found":
			return await save_revision(transport, uid, 0, "",
				str(_failed_save.get("payload", "")))
		return remote
	return await save_revision(transport, uid, int(remote.get("revision", 0)),
		str(remote.get("update_time", "")),
		str(_failed_save.get("payload", "")))


## Explicit integration choice: keep the local payload by rebasing it on the
## fresh remote revision. No silent timestamp choice happens elsewhere.
## Success carries the fresh remote it rebased onto, so the caller preserves
## the exact bytes it overwrote even when the remote advanced again after
## the conflict was shown.
func choose_local(transport: RefCounted, uid: String,
		payload: String) -> Dictionary:
	var captured: int = _owner_generation
	var remote: Dictionary = await load_remote(transport, uid)
	if _stale(captured):
		return {"status": "cancelled", "code": "stale-reply",
			"retryable": false}
	if str(remote.get("status", "")) != "ok":
		if str(remote.get("code", "")) == "not-found":
			return await save_revision(transport, uid, 0, "", payload)
		return remote
	var saved: Dictionary = await save_revision(transport, uid,
		int(remote.get("revision", 0)), str(remote.get("update_time", "")),
		payload)
	if _stale(captured):
		return {"status": "cancelled", "code": "stale-reply",
			"retryable": false}
	if str(saved.get("status", "")) != "ok":
		return saved
	saved["local_revision"] = int(saved.get("revision", 0))
	saved["remote"] = remote.duplicate(true)
	return saved


## Drain the queue only when it still holds the exact bytes just committed
## (or accepted). A newer seal queued during the commit has different bytes
## and survives for its own server commit; an identical requeue drains as
## acknowledged. Revision numbers never drain: every queued edit shares the
## same local numbering while cloud revisions march independently.
func _drain_if_committed(uid: String, payload: String) -> void:
	if _pending_uid == uid and _pending_payload == payload:
		take_pending()


## Explicit integration choice: accept the remote payload. Gameplay must still
## run it through the Journey validator before applying.
func choose_remote(remote: Dictionary) -> Dictionary:
	if str(remote.get("status", "")) != "ok":
		return {"status": "failure", "code": "no-remote-checkpoint",
			"retryable": false}
	_failed_save = {}
	_last_acked_revision = int(remote.get("revision", _last_acked_revision))
	if has_pending():
		_drain_if_committed(_pending_uid, str(remote.get("payload", "")))
	var accepted: Dictionary = remote.duplicate(true)
	accepted["needs_validator"] = true
	accepted["choice"] = "remote"
	return accepted


func _cas_precondition(base_revision: int, base_update_time: String) -> Dictionary:
	if base_revision <= 0 or base_update_time.is_empty():
		return {"exists": false}
	return {"updateTime": base_update_time}
