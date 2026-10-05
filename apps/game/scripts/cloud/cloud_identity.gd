extends RefCounted

## Public-ID reservation and UID-to-public-ID profile ownership.
##
## Each Firebase UID owns one immutable profile (`mb_profiles_v1/{uid}`) and one
## matching reservation (`mb_reservations_v1/{public_id}`), created together in
## one atomic Firestore commit. A restored account reads back its canonical ID;
## linking a Firebase guest keeps the same UID, so the same ID comes back with
## no new registration. Offline work never claims a global reservation: without
## a server acknowledgement the ID stays local-only and unlabeled as reserved.
##
## Account switching only retires in-flight requests and swaps the active UID.
## It never writes one account's journey over another's local file; the local
## store keys every file by UID.

const CloudSchema: Script = preload("res://scripts/cloud/cloud_schema.gd")

const MAX_REGISTRATION_ATTEMPTS: int = 5
const HEX_ALPHABET: String = "0123456789abcdef"

var _active_uid: String = ""
var _active_public_id: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func active_uid() -> String:
	return _active_uid


func active_public_id() -> String:
	return _active_public_id


## Swap the in-memory account. Retires transport requests for the old account
## and clears the cached ID without touching any local journey file.
func switch_account(transport: RefCounted, new_uid: String) -> void:
	_active_uid = new_uid
	_active_public_id = ""
	if transport != null and transport.has_method("set_account_uid"):
		transport.call("set_account_uid", new_uid)


## Test hook for deterministic candidate IDs.
func _test_set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func make_candidate_id() -> String:
	var tail: String = ""
	for _index in CloudSchema.PUBLIC_ID_HEX_LENGTH:
		tail += HEX_ALPHABET[_rng.randi_range(0, 15)]
	return CloudSchema.PUBLIC_ID_PREFIX + tail


func profile_relative_path(uid: String) -> String:
	return "documents/%s/%s" % [CloudSchema.PROFILE_COLLECTION, uid]


func reservation_relative_path(public_id: String) -> String:
	return "documents/%s/%s" % [CloudSchema.RESERVATION_COLLECTION, public_id]


func profile_body(uid: String, public_id: String) -> Dictionary:
	var stamp: String = CloudSchema.now_rfc3339()
	return {
		"fields": {
			"uid": CloudSchema.encode_string(uid),
			"public_id": CloudSchema.encode_string(public_id),
			"schema": CloudSchema.encode_int(CloudSchema.SCHEMA_VERSION),
			"created_at": CloudSchema.encode_timestamp_rfc3339(stamp),
			"updated_at": CloudSchema.encode_timestamp_rfc3339(stamp),
		}
	}


func reservation_body(uid: String, public_id: String) -> Dictionary:
	return {
		"fields": {
			"public_id": CloudSchema.encode_string(public_id),
			"uid": CloudSchema.encode_string(uid),
			"schema": CloudSchema.encode_int(CloudSchema.SCHEMA_VERSION),
			"created_at": CloudSchema.encode_timestamp_rfc3339(
				CloudSchema.now_rfc3339()),
		}
	}


## Atomic two-write registration body. Both writes require `exists: false`, so
## a collision on either document fails the whole commit without half state.
func registration_commit_body(uid: String, public_id: String) -> Dictionary:
	return {
		"writes": [
			{
				"update": {
					"name": CloudSchema.document_name(
						CloudSchema.PROFILE_COLLECTION, uid),
					"fields": (profile_body(uid, public_id) as Dictionary)["fields"],
				},
				"currentDocument": {"exists": false},
			},
			{
				"update": {
					"name": CloudSchema.document_name(
						CloudSchema.RESERVATION_COLLECTION, public_id),
					"fields": (reservation_body(uid, public_id) as Dictionary)["fields"],
				},
				"currentDocument": {"exists": false},
			},
		]
	}


## Reads the canonical ID for a UID. Returns ok/not-found plus offline,
## unconfigured, cancelled, and failure without inventing an ID.
func fetch_canonical_id(transport: RefCounted, uid: String) -> Dictionary:
	var validation: Dictionary = _validate_transport_uid(transport, uid)
	if not bool(validation.get("ok", false)):
		return validation.get("result", {})
	var reply: Dictionary = await transport.call("get_document",
		profile_relative_path(uid))
	var status: String = str(reply.get("status", "failure"))
	if status != "ok":
		if str(reply.get("code", "")) == "not-found":
			return {
				"status": "failure", "code": "profile-not-found",
				"retryable": false,
			}
		return reply
	var decoded: Dictionary = CloudSchema.parse_json_value(
		str(reply.get("body", "")))
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_DICTIONARY:
		return {"status": "failure", "code": "bad-profile-body",
			"retryable": false}
	var fields: Dictionary = (decoded.get("value") as Dictionary).get(
		"fields", {})
	var public_id: String = CloudSchema.decode_string(fields, "public_id")
	var stored_uid: String = CloudSchema.decode_string(fields, "uid")
	if not CloudSchema.is_valid_public_id(public_id) or stored_uid != uid:
		return {"status": "failure", "code": "profile-mismatch",
			"retryable": false}
	return {"status": "ok", "public_id": public_id, "source": "cloud"}


## Registers a UID or restores its canonical ID. A collision on the
## reservation retries with a fresh candidate before any success is reported.
## Another UID's existing ID can never be claimed: its reservation already
## exists, so the atomic commit fails and this call retries instead.
func register_or_restore(transport: RefCounted, uid: String) -> Dictionary:
	var validation: Dictionary = _validate_transport_uid(transport, uid)
	if not bool(validation.get("ok", false)):
		return validation.get("result", {})
	var existing: Dictionary = await fetch_canonical_id(transport, uid)
	if str(existing.get("status", "")) == "ok":
		_active_uid = uid
		_active_public_id = str(existing.get("public_id", ""))
		return {
			"status": "ok", "public_id": _active_public_id,
			"restored": true, "source": "cloud",
		}
	if str(existing.get("code", "")) != "profile-not-found":
		return existing
	var attempt: int = 0
	while attempt < MAX_REGISTRATION_ATTEMPTS:
		attempt += 1
		var candidate: String = make_candidate_id()
		var commit: Dictionary = await transport.call("post",
			"documents:commit",
			JSON.stringify(registration_commit_body(uid, candidate)))
		var status: String = str(commit.get("status", "failure"))
		if status == "ok":
			_active_uid = uid
			_active_public_id = candidate
			return {
				"status": "ok", "public_id": candidate,
				"restored": false, "source": "cloud",
				"attempts": attempt,
			}
		if status == "conflict":
			# Either the candidate reservation or our own profile now exists.
			# Re-read the profile: a row means another device registered
			# first and its ID is canonical; no row means a true ID
			# collision and the next loop tries a fresh candidate.
			var recheck: Dictionary = await fetch_canonical_id(transport, uid)
			if str(recheck.get("status", "")) == "ok":
				_active_uid = uid
				_active_public_id = str(recheck.get("public_id", ""))
				return {
					"status": "ok", "public_id": _active_public_id,
					"restored": true, "source": "cloud",
					"attempts": attempt,
				}
			if str(recheck.get("code", "")) != "profile-not-found":
				return recheck
			continue
		if status == "offline" or status == "unconfigured" \
				or status == "cancelled":
			return commit
		return commit
	return {"status": "failure", "code": "id-collision-exhausted",
		"retryable": false}


## Registers a UID against the host-supplied durable guest ID, or restores
## its canonical ID. The guest ID is the exact pre-play `MB-` id the host
## holds: a new UID reserves that id and no other, and the single commit
## attempt uses it verbatim. A collision (another UID already reserved it)
## returns an explicit `guest-id-taken` conflict and never silently retries
## with a different id. An existing UID returns its canonical ID explicitly
## (`restored: true`), even when it differs from the supplied guest ID, so
## the host can persist the canonical one. Linking keeps the UID, so the
## same canonical ID comes back with no new registration.
func register_or_restore_with_guest_id(transport: RefCounted, uid: String,
		guest_public_id: String) -> Dictionary:
	var validation: Dictionary = _validate_transport_uid(transport, uid)
	if not bool(validation.get("ok", false)):
		return validation.get("result", {})
	if not CloudSchema.is_valid_public_id(guest_public_id):
		return {"status": "failure", "code": "invalid-guest-id",
			"retryable": false}
	var existing: Dictionary = await fetch_canonical_id(transport, uid)
	if str(existing.get("status", "")) == "ok":
		_active_uid = uid
		_active_public_id = str(existing.get("public_id", ""))
		return {
			"status": "ok", "public_id": _active_public_id,
			"restored": true, "source": "cloud",
			"requested": guest_public_id,
		}
	if str(existing.get("code", "")) != "profile-not-found":
		return existing
	var commit: Dictionary = await transport.call("post",
		"documents:commit",
		JSON.stringify(registration_commit_body(uid, guest_public_id)))
	var status: String = str(commit.get("status", "failure"))
	if status == "ok":
		_active_uid = uid
		_active_public_id = guest_public_id
		return {
			"status": "ok", "public_id": guest_public_id,
			"restored": false, "source": "cloud",
			"requested": guest_public_id, "attempts": 1,
		}
	if status == "conflict":
		# Either the guest reservation belongs to another UID, or our own
		# profile landed first (another device won the race). Re-read once:
		# a row means the canonical ID wins explicitly; no row means the
		# guest ID itself is taken and no silent replacement follows.
		var recheck: Dictionary = await fetch_canonical_id(transport, uid)
		if str(recheck.get("status", "")) == "ok":
			_active_uid = uid
			_active_public_id = str(recheck.get("public_id", ""))
			return {
				"status": "ok", "public_id": _active_public_id,
				"restored": true, "source": "cloud",
				"requested": guest_public_id,
			}
		if str(recheck.get("code", "")) != "profile-not-found":
			return recheck
		return {"status": "conflict", "code": "guest-id-taken",
			"retryable": false, "requested": guest_public_id}
	return commit


func _validate_transport_uid(transport: RefCounted, uid: String) -> Dictionary:
	if transport == null or not transport.has_method("get_document"):
		return {"ok": false, "result": {"status": "unconfigured",
			"code": "missing-transport", "retryable": false}}
	if not CloudSchema.is_valid_uid(uid):
		return {"ok": false, "result": {"status": "failure",
			"code": "invalid-uid", "retryable": false}}
	return {"ok": true}
