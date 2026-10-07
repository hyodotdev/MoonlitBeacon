extends RefCounted

## Account-owned attendance claims: two continue coins per rolling twelve
## hours, enforced by server time.
##
## Each registered account owns one private row
## (`mb_attendance_v1/{public_id}`) holding the last claim's server
## timestamp plus the receiving install. A first read uses `batchGet` so
## the single response carries both the row (or its authoritative absence
## for the proven owner) and the server `readTime` the cooldown compares
## against. Eligibility and remaining time derive ONLY from server
## timestamps — device wall clocks, time zones, and launches never enter.
##
## A first claim is one conditional commit (`exists:false`); an eligible
## advance commits separately through `commit_advance`, after the caller
## backfills any owned still-unapplied reward, compare-and-swapped on the
## read row's `updateTime`. Concurrent claims for one account yield
## exactly one new receipt; the loser re-reads and converges on
## already-claimed. The claim stamp is a server timestamp transform, so
## forged times die in the rules. Every advance carries the overwritten
## row's stamp and install (`prev_*`, copied opaquely), so another
## install's later advance never erases this install's recoverable
## receipt; the rules require exactly that carry. The wallet receipt key
## derives from `{public_id, claim seconds, install}`: the claimer and
## any later recovery derive the same key, while another install's key
## never matches this wallet.
##
## Reads and writes pass transport replies through untouched: 403 stays
## `permission-denied` (a configuration/ownership error, never a taken
## period), offline stays offline. No row here grants coins by itself;
## the coordinator applies the acknowledged claim to the Vault exactly
## once.

const CloudSchema: Script = preload("res://scripts/cloud/cloud_schema.gd")


## Single-document batchGet body. The response carries `readTime` (server
## now) alongside `found` or `missing`, which plain documents.get omits.
static func batch_get_body(public_id: String) -> String:
	var doc_name: String = CloudSchema.document_name(
		CloudSchema.ATTENDANCE_COLLECTION, public_id)
	return JSON.stringify({"documents": [doc_name]})


## Atomic claim commit: create-on-first-claim or updateTime
## compare-and-swap afterwards. The stamp is server-set; the payload
## binds the canonical halves and the receiving install. Advances also
## carry the overwritten row's stamp and install opaquely (`prev_*`),
## copied byte for byte so sub-second precision survives; first claims
## omit them.
static func claim_commit_body(public_id: String, uid: String,
		install_id: String, update_time: String,
		prev_claim_rfc: String = "",
		prev_install: String = "") -> String:
	var doc_name: String = CloudSchema.document_name(
		CloudSchema.ATTENDANCE_COLLECTION, public_id)
	var fields: Dictionary = {
		"public_id": CloudSchema.encode_string(public_id),
		"uid": CloudSchema.encode_string(uid),
		"install_id": CloudSchema.encode_string(install_id),
		"schema": CloudSchema.encode_int(CloudSchema.SCHEMA_VERSION),
	}
	if not update_time.is_empty():
		fields[CloudSchema.ATTENDANCE_PREV_CLAIM_FIELD] = \
			CloudSchema.encode_timestamp_rfc3339(prev_claim_rfc)
		fields[CloudSchema.ATTENDANCE_PREV_INSTALL_FIELD] = \
			CloudSchema.encode_string(prev_install)
	var write: Dictionary = {
		"update": {"name": doc_name, "fields": fields},
		"updateTransforms": [{
			"fieldPath": "last_claim_at",
			"setToServerValue": "REQUEST_TIME",
		}],
	}
	if update_time.is_empty():
		write["currentDocument"] = {"exists": false}
	else:
		write["currentDocument"] = {"updateTime": update_time}
	return JSON.stringify({"writes": [write]})


## Read the account's attendance row with its server time. Returns `ok`
## with `{last_claim_at, last_claim_rfc, install_id, prev_claim_at,
## prev_install_id, update_time, server_now}` (stamps in seconds plus the
## raw current stamp for the opaque advance carry; `prev_*` are zero and
## empty on rows without a carried claim),
## `attendance-not-found` with `{server_now}` for a first claim, or the
## transport reply untouched (offline/denied stay errors, never reads).
## A row bound to another UID or public ID fails closed: never adopt it.
func fetch_attendance(transport: RefCounted, uid: String,
		public_id: String) -> Dictionary:
	var checked: Dictionary = CloudSchema.validate_profile(
		uid, public_id)
	if not bool(checked.get("ok", false)):
		return {"status": "failure",
			"code": str(checked.get("error", "invalid-uid")),
			"retryable": false}
	var reply: Dictionary = await transport.call("post",
		"documents:batchGet", batch_get_body(public_id))
	if str(reply.get("status", "")) != "ok":
		return reply
	var body: Dictionary = CloudSchema.parse_json_value(
		str(reply.get("body", "")))
	if not bool(body.get("ok", false)) \
			or typeof(body.get("value")) != TYPE_ARRAY:
		return {"status": "failure", "code": "attendance-bad-read",
			"retryable": false}
	var entries: Array = body.get("value", [])
	if entries.is_empty() or typeof(entries[0]) != TYPE_DICTIONARY:
		return {"status": "failure", "code": "attendance-bad-read",
			"retryable": false}
	var entry: Dictionary = entries[0]
	var server_now: int = CloudSchema.unix_from_rfc3339(
		str(entry.get("readTime", "")))
	if server_now <= 0:
		return {"status": "failure", "code": "attendance-no-server-time",
			"retryable": false}
	if entry.has("missing"):
		return {"status": "attendance-not-found",
			"server_now": server_now}
	var found: Dictionary = entry.get("found", {})
	if typeof(found) != TYPE_DICTIONARY or found.is_empty():
		return {"status": "failure", "code": "attendance-bad-read",
			"retryable": false}
	var fields: Dictionary = found.get("fields", {})
	if typeof(fields) != TYPE_DICTIONARY:
		return {"status": "failure", "code": "attendance-bad-read",
			"retryable": false}
	if CloudSchema.decode_string(fields, "uid") != uid \
			or CloudSchema.decode_string(fields, "public_id") \
			!= public_id:
		return {"status": "failure", "code": "attendance-row-mismatch",
			"retryable": false}
	var last_claim_rfc: String = CloudSchema.decode_timestamp(
		fields, "last_claim_at")
	var last_claim_at: int = CloudSchema.unix_from_rfc3339(
		last_claim_rfc)
	if last_claim_at <= 0:
		return {"status": "failure", "code": "attendance-bad-stamp",
			"retryable": false}
	var prev_claim_at: int = 0
	var prev_install_id: String = ""
	if fields.has(CloudSchema.ATTENDANCE_PREV_CLAIM_FIELD) \
			or fields.has(CloudSchema.ATTENDANCE_PREV_INSTALL_FIELD):
		prev_install_id = CloudSchema.decode_string(fields,
			CloudSchema.ATTENDANCE_PREV_INSTALL_FIELD)
		prev_claim_at = CloudSchema.unix_from_rfc3339(
			CloudSchema.decode_timestamp(fields,
				CloudSchema.ATTENDANCE_PREV_CLAIM_FIELD))
		if prev_claim_at <= 0 or prev_install_id.is_empty() \
				or prev_install_id.length() \
				> CloudSchema.MAX_INSTALL_ID_LENGTH:
			return {"status": "failure",
				"code": "attendance-bad-stamp",
				"retryable": false}
	return {"status": "ok",
		"last_claim_at": last_claim_at,
		"last_claim_rfc": last_claim_rfc,
		"install_id": CloudSchema.decode_string(fields, "install_id"),
		"prev_claim_at": prev_claim_at,
		"prev_install_id": prev_install_id,
		"update_time": str(found.get("updateTime", "")),
		"server_now": server_now}


## Claim the current period: read the server row, compare server
## timestamps, and commit a first claim conditionally. An eligible
## advance is NOT committed here: the caller must first backfill any
## owned still-unapplied reward from the returned row, then commit
## through `commit_advance`, so no advance erases a recoverable receipt.
##
## Returns `ok` with `{claim_seconds, next_eligible_utc,
## remaining_seconds, server_now}` on a landed first claim (the caller
## still owes the local wallet grant), `eligible` with the read row when
## the next period can advance, `already-claimed` with the same
## server-derived deadline fields when the period belongs to any install
## (plus `mine`, whether this install received it, and any carried
## `prev_*` for backfill), or an honest failure/offline/conflict that
## grants nothing.
func claim_attendance(transport: RefCounted, uid: String,
		public_id: String, install_id: String) -> Dictionary:
	if not CloudSchema.is_valid_install_id(install_id):
		return {"status": "failure", "code": "invalid-install-id",
			"retryable": false}
	var current: Dictionary = await fetch_attendance(
		transport, uid, public_id)
	var state: String = str(current.get("status", ""))
	if state != "ok" and state != "attendance-not-found":
		return current
	if state == "ok":
		var held: Dictionary = _cooldown_result(current, install_id)
		if not bool(held.get("eligible", false)):
			return held
		if str(current.get("update_time", "")).is_empty():
			return {"status": "failure",
				"code": "attendance-no-update-time",
				"retryable": false}
		held.erase("eligible")
		held["status"] = "eligible"
		return held
	var commit: Dictionary = await transport.call("post",
		"documents:commit", claim_commit_body(
			public_id, uid, install_id, ""))
	var commit_status: String = str(commit.get("status", ""))
	if commit_status == "ok":
		return _granted_result(commit, install_id)
	if commit_status != "conflict":
		return commit
	return await _settle_conflict(
		transport, uid, public_id, install_id)


## Commit one eligible advance after the caller backfilled every owned
## still-unapplied reward on the read row. Carries the overwritten row's
## stamp and install opaquely, compare-and-swapped on its update time;
## the rules require exactly that carry, so a racing advance that changed
## the row fails the swap and settles by re-reading. Returns `ok` with
## the new claim, an uncertain ack without a stamp, or the conflict
## verdict, exactly like a first claim.
func commit_advance(transport: RefCounted, uid: String,
		public_id: String, install_id: String, update_time: String,
		prev_claim_rfc: String, prev_install: String) -> Dictionary:
	if not CloudSchema.is_valid_install_id(install_id):
		return {"status": "failure", "code": "invalid-install-id",
			"retryable": false}
	if update_time.is_empty() or prev_claim_rfc.is_empty() \
			or prev_install.is_empty() \
			or CloudSchema.unix_from_rfc3339(prev_claim_rfc) <= 0:
		return {"status": "failure", "code": "attendance-bad-advance",
			"retryable": false}
	var commit: Dictionary = await transport.call("post",
		"documents:commit", claim_commit_body(public_id, uid,
			install_id, update_time, prev_claim_rfc, prev_install))
	var commit_status: String = str(commit.get("status", ""))
	if commit_status == "ok":
		return _granted_result(commit, install_id)
	if commit_status != "conflict":
		return commit
	return await _settle_conflict(
		transport, uid, public_id, install_id)


## Cooldown verdict for a row already read: an eligible row returns its
## full read shape for the caller's backfill-then-commit advance, a held
## period returns `already-claimed` with server-derived deadline fields.
## `mine` tells the caller whether this install received the held period;
## both shapes carry any `prev_*` so owned unapplied rewards backfill.
func _cooldown_result(current: Dictionary, install_id: String) -> Dictionary:
	var window: Dictionary = CloudSchema.attendance_cooldown(
		int(current.get("server_now", 0)),
		int(current.get("last_claim_at", 0)))
	if bool(window.get("eligible", false)):
		return {
			"eligible": true,
			"last_claim_at": int(current.get("last_claim_at", 0)),
			"last_claim_rfc": str(current.get("last_claim_rfc", "")),
			"install_id": str(current.get("install_id", "")),
			"prev_claim_at": int(current.get("prev_claim_at", 0)),
			"prev_install_id": str(current.get(
				"prev_install_id", "")),
			"update_time": str(current.get("update_time", "")),
			"server_now": int(current.get("server_now", 0)),
		}
	return {
		"status": "already-claimed",
		"mine": str(current.get("install_id", "")) == install_id
			and not install_id.is_empty(),
		"last_claim_at": int(current.get("last_claim_at", 0)),
		"last_claim_rfc": str(current.get("last_claim_rfc", "")),
		"install_id": str(current.get("install_id", "")),
		"prev_claim_at": int(current.get("prev_claim_at", 0)),
		"prev_install_id": str(current.get("prev_install_id", "")),
		"next_eligible_utc": CloudSchema.rfc3339_from_unix(
			int(window.get("next_at", 0))),
		"remaining_seconds": int(window.get("remaining", 0)),
		"server_now": int(current.get("server_now", 0)),
	}


## Granted-claim result from the commit's server `commitTime`: the exact
## claim seconds plus the confirmed next deadline. A missing commitTime
## is an uncertain ack the caller must resolve by re-reading, never a
## grant on an assumed clock.
func _granted_result(commit: Dictionary, install_id: String) -> Dictionary:
	var body: Dictionary = CloudSchema.parse_json_value(
		str(commit.get("body", "")))
	var commit_time: String = ""
	if bool(body.get("ok", false)) \
			and typeof(body.get("value")) == TYPE_DICTIONARY:
		commit_time = str((body.get("value") as Dictionary).get(
			"commitTime", ""))
	var claim_seconds: int = CloudSchema.unix_from_rfc3339(commit_time)
	if claim_seconds <= 0:
		return {"status": "failure", "code": "attendance-uncertain-ack",
			"retryable": true}
	return {
		"status": "ok", "claim_seconds": claim_seconds,
		"install_id": install_id,
		"next_eligible_utc": CloudSchema.rfc3339_from_unix(
			claim_seconds + CloudSchema.ATTENDANCE_COOLDOWN_SECONDS),
		"remaining_seconds": CloudSchema.ATTENDANCE_COOLDOWN_SECONDS,
		"server_now": claim_seconds,
	}


## One bounded re-read after a lost compare-and-swap: the winner's row
## decides. A held period converges on `already-claimed` (granting
## locally when this install won); anything else passes through honestly
## for the next trigger to resolve.
func _settle_conflict(transport: RefCounted, uid: String,
		public_id: String, install_id: String) -> Dictionary:
	var recheck: Dictionary = await fetch_attendance(
		transport, uid, public_id)
	var state: String = str(recheck.get("status", ""))
	if state == "ok":
		var held: Dictionary = _cooldown_result(recheck, install_id)
		if not bool(held.get("eligible", false)):
			return held
		return {"status": "failure", "code": "attendance-claim-race",
			"retryable": true}
	if state == "attendance-not-found":
		return {"status": "failure", "code": "attendance-claim-race",
			"retryable": true}
	return recheck
