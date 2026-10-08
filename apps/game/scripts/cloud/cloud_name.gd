extends RefCounted

## Account-owned adventurer names and their global reservation pair.
##
## Each registered account owns one private adventurer row
## (`mb_adventurers_v1/{public_id}`) and one matching global name claim
## (`mb_names_v1/{name_key}`), created together in one atomic Firestore
## commit. The claim is immutable: no rename, no reassignment, no lone
## halves. Two owners racing for one name yield exactly one winner; the
## loser reads `name-taken` and keeps its own ID, journey, and best score.
##
## The collision key lowercases the display, so `Luna` and `LUNA` are one
## name. Commit JSON carries raw Unicode document names; only HTTP request
## URLs percent-encode the name segment. Offline work never certifies a
## global claim: without a server acknowledgement there is no name.

const CloudSchema: Script = preload("res://scripts/cloud/cloud_schema.gd")


func adventurer_relative_path(public_id: String) -> String:
	return "documents/%s/%s" % [CloudSchema.ADVENTURER_COLLECTION, public_id]


func name_relative_path(name_key: String) -> String:
	return "documents/%s/%s" % [
		CloudSchema.NAME_COLLECTION, name_key.uri_encode()]


func adventurer_body(uid: String, public_id: String, name_key: String,
		display: String, intro_complete: bool) -> Dictionary:
	var stamp: String = CloudSchema.now_rfc3339()
	return {
		"fields": {
			"public_id": CloudSchema.encode_string(public_id),
			"uid": CloudSchema.encode_string(uid),
			"name_key": CloudSchema.encode_string(name_key),
			"display": CloudSchema.encode_string(display),
			"intro_complete": CloudSchema.encode_bool(intro_complete),
			"schema": CloudSchema.encode_int(CloudSchema.SCHEMA_VERSION),
			"created_at": CloudSchema.encode_timestamp_rfc3339(stamp),
			"updated_at": CloudSchema.encode_timestamp_rfc3339(stamp),
		}
	}


func name_body(name_key: String, display: String,
		public_id: String) -> Dictionary:
	return {
		"fields": {
			"name_key": CloudSchema.encode_string(name_key),
			"display": CloudSchema.encode_string(display),
			"public_id": CloudSchema.encode_string(public_id),
			"schema": CloudSchema.encode_int(CloudSchema.SCHEMA_VERSION),
			"created_at": CloudSchema.encode_timestamp_rfc3339(
				CloudSchema.now_rfc3339()),
		}
	}


## Atomic two-write claim body. Both writes require `exists: false`, so a
## taken name fails the whole commit without half state. Document names
## carry the raw Unicode key; URL encoding applies to request URLs only.
func claim_commit_body(uid: String, public_id: String, name_key: String,
		display: String) -> Dictionary:
	return {
		"writes": [
			{
				"update": {
					"name": CloudSchema.document_name(
						CloudSchema.ADVENTURER_COLLECTION, public_id),
					"fields": (adventurer_body(uid, public_id,
						name_key, display, false) as Dictionary)["fields"],
				},
				"currentDocument": {"exists": false},
			},
			{
				"update": {
					"name": CloudSchema.document_name(
						CloudSchema.NAME_COLLECTION, name_key),
					"fields": (name_body(name_key, display,
						public_id) as Dictionary)["fields"],
				},
				"currentDocument": {"exists": false},
			},
		]
	}


## Reads the account's claimed name. Returns ok/not-found plus offline,
## unconfigured, cancelled, and failure without inventing a name. A row
## bound to another UID or public ID reports `adventurer-mismatch` and is
## never adopted.
func fetch_adventurer(transport: RefCounted, uid: String,
		public_id: String) -> Dictionary:
	var validation: Dictionary = _validate_ids(transport, uid, public_id)
	if not bool(validation.get("ok", false)):
		return validation.get("result", {})
	var reply: Dictionary = await transport.call("get_document",
		adventurer_relative_path(public_id))
	var status: String = str(reply.get("status", "failure"))
	if status != "ok":
		if str(reply.get("code", "")) == "not-found":
			return {
				"status": "failure", "code": "adventurer-not-found",
				"retryable": false,
			}
		return reply
	var decoded: Dictionary = CloudSchema.parse_json_value(
		str(reply.get("body", "")))
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_DICTIONARY:
		return {"status": "failure", "code": "bad-adventurer-body",
			"retryable": false}
	var fields: Dictionary = (decoded.get("value") as Dictionary).get(
		"fields", {})
	var stored_uid: String = CloudSchema.decode_string(fields, "uid")
	var stored_id: String = CloudSchema.decode_string(fields, "public_id")
	if stored_uid != uid or stored_id != public_id:
		return {"status": "failure", "code": "adventurer-mismatch",
			"retryable": false}
	var normalized: Dictionary = CloudSchema.normalize_adventurer_name(
		CloudSchema.decode_string(fields, "display"))
	if not bool(normalized.get("ok", false)) \
			or str(normalized.get("key", "")) \
				!= CloudSchema.decode_string(fields, "name_key"):
		return {"status": "failure", "code": "adventurer-mismatch",
			"retryable": false}
	return {
		"status": "ok",
		"display": str(normalized.get("display", "")),
		"key": str(normalized.get("key", "")),
		"intro_complete": CloudSchema.decode_bool(
			fields, "intro_complete"),
		"source": "cloud",
	}


## Claims a display name for a registered account, or restores the one it
## already owns. A taken name reports `name-taken` after one recheck rules
## out our own landed row; a permission denial is never renamed to taken,
## so missing backend rules surface as a configuration failure instead.
## Invalid names fail before any request; offline callers get no name.
func claim_name(transport: RefCounted, uid: String, public_id: String,
		raw_display: String) -> Dictionary:
	var normalized: Dictionary = CloudSchema.normalize_adventurer_name(
		raw_display)
	if not bool(normalized.get("ok", false)):
		return {"status": "failure", "code": "invalid-name",
			"retryable": false}
	var validation: Dictionary = _validate_ids(transport, uid, public_id)
	if not bool(validation.get("ok", false)):
		return validation.get("result", {})
	var display: String = str(normalized.get("display", ""))
	var key: String = str(normalized.get("key", ""))
	var existing: Dictionary = await fetch_adventurer(
		transport, uid, public_id)
	if str(existing.get("status", "")) == "ok":
		return {
			"status": "ok", "display": str(existing.get("display", "")),
			"key": str(existing.get("key", "")),
			"intro_complete": bool(
				existing.get("intro_complete", false)),
			"restored": true, "source": "cloud",
		}
	if str(existing.get("code", "")) != "adventurer-not-found":
		return existing
	var commit: Dictionary = await transport.call("post",
		"documents:commit", JSON.stringify(claim_commit_body(
			uid, public_id, key, display)))
	var commit_status: String = str(commit.get("status", "failure"))
	if commit_status == "ok":
		return {
			"status": "ok", "display": display, "key": key,
			"intro_complete": false, "restored": false,
			"source": "cloud",
		}
	if commit_status == "conflict":
		# Either the name belongs to another owner, or our own pair
		# landed first (another device won, or an uncertain
		# acknowledgement hid our own success). Re-read once: a row
		# means our canonical name wins explicitly; no row means the
		# name itself is taken and no silent replacement follows.
		var recheck: Dictionary = await fetch_adventurer(
			transport, uid, public_id)
		if str(recheck.get("status", "")) == "ok":
			return {
				"status": "ok",
				"display": str(recheck.get("display", "")),
				"key": str(recheck.get("key", "")),
				"intro_complete": bool(
					recheck.get("intro_complete", false)),
				"restored": true, "source": "cloud",
			}
		if str(recheck.get("code", "")) != "adventurer-not-found":
			return recheck
		return {"status": "conflict", "code": "name-taken",
			"retryable": false, "key": key}
	return commit


## Flips the tutorial bit false to true. Idempotent: an already complete
## row reports ok without a write, so uncertain acknowledgements and
## double taps converge instead of duplicating.
func mark_intro_complete(transport: RefCounted, uid: String,
		public_id: String) -> Dictionary:
	var validation: Dictionary = _validate_ids(transport, uid, public_id)
	if not bool(validation.get("ok", false)):
		return validation.get("result", {})
	var current: Dictionary = await fetch_adventurer(
		transport, uid, public_id)
	if str(current.get("status", "")) != "ok":
		return current
	if bool(current.get("intro_complete", false)):
		return {
			"status": "ok", "display": str(current.get("display", "")),
			"key": str(current.get("key", "")), "intro_complete": true,
			"source": "cloud",
		}
	var body: Dictionary = {
		"writes": [
			{
				"update": {
					"name": CloudSchema.document_name(
						CloudSchema.ADVENTURER_COLLECTION, public_id),
					"fields": (adventurer_body(uid, public_id,
						str(current.get("key", "")),
						str(current.get("display", "")),
						true) as Dictionary)["fields"],
				},
				"currentDocument": {"exists": true},
			}
		]
	}
	var reply: Dictionary = await transport.call("post",
		"documents:commit", JSON.stringify(body))
	if str(reply.get("status", "")) != "ok":
		return reply
	return {
		"status": "ok", "display": str(current.get("display", "")),
		"key": str(current.get("key", "")), "intro_complete": true,
		"source": "cloud",
	}


func _validate_ids(transport: RefCounted, uid: String,
		public_id: String) -> Dictionary:
	if transport == null or not transport.has_method("get_document"):
		return {"ok": false, "result": {"status": "unconfigured",
			"code": "missing-transport", "retryable": false}}
	if not CloudSchema.is_valid_uid(uid):
		return {"ok": false, "result": {"status": "failure",
			"code": "invalid-uid", "retryable": false}}
	if not CloudSchema.is_valid_public_id(public_id):
		return {"ok": false, "result": {"status": "failure",
			"code": "invalid-public-id", "retryable": false}}
	return {"ok": true}
