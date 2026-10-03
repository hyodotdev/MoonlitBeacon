extends RefCounted

## Shared contracts for the 4.0.0 owned-cloud data layer.
##
## Collections, field names, bounds, and Firestore value encoding live here so
## the transport, identity, checkpoint, Hall, and account helpers agree on one
## shape and the security rules mirror the same lists. This file performs no
## network calls and stores no credentials.

const PROJECT_ID: String = "moonlitbeacon-778ee"
const DATABASE_ID: String = "(default)"
const API_ROOT: String = "https://firestore.googleapis.com/v1"

const PROFILE_COLLECTION: String = "mb_profiles_v1"
const RESERVATION_COLLECTION: String = "mb_reservations_v1"
const CHECKPOINT_COLLECTION: String = "mb_checkpoints_v1"
const HALL_COLLECTION: String = "mb_hall_v1"

const SCHEMA_VERSION: int = 1
const PUBLIC_ID_PREFIX: String = "MB-"
const PUBLIC_ID_HEX_LENGTH: int = 32
const MAX_UID_LENGTH: int = 128
const MAX_RELEASE_LENGTH: int = 32
const MAX_SCORE: int = 2000000000
## Highest Hall cycle count. Matches `Journey.MAX_CYCLE`: the run is endless
## and the Hall must never refuse a cycle the local journey can seal. The
## additive rules carry the same bound.
const MAX_CYCLES: int = 99999
const MAX_CHECKPOINT_BYTES: int = 32768
const MAX_HALL_TOP_LIMIT: int = 100

const PROFILE_FIELDS: Array[String] = [
	"uid", "public_id", "schema", "created_at", "updated_at",
]
const RESERVATION_FIELDS: Array[String] = [
	"public_id", "uid", "schema", "created_at",
]
const CHECKPOINT_FIELDS: Array[String] = [
	"uid", "revision", "payload", "schema", "updated_at",
]
const HALL_FIELDS: Array[String] = [
	"public_id", "hero", "score", "cycles", "release", "schema",
	"updated_at",
]

## Full hero resource paths accepted in Hall rows. Short ids are resolved to
## these before upload so the rules list stays in one vocabulary.
const HERO_PATHS: Array[String] = [
	"res://resources/heroes/warden.tres",
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/eclipse.tres",
	"res://resources/heroes/sage.tres",
]
const HERO_SHORT_IDS: Dictionary = {
	"warden": "res://resources/heroes/warden.tres",
	"dancer": "res://resources/heroes/dancer.tres",
	"keeper": "res://resources/heroes/keeper.tres",
	"knight": "res://resources/heroes/knight.tres",
	"eclipse": "res://resources/heroes/eclipse.tres",
	"sage": "res://resources/heroes/sage.tres",
}


static func is_valid_uid(uid: String) -> bool:
	if uid.is_empty() or uid.length() > MAX_UID_LENGTH:
		return false
	if uid.contains("/") or uid.contains(".."):
		return false
	for code in uid.to_utf8_buffer():
		var is_word: bool = (code >= 48 and code <= 57) \
			or (code >= 65 and code <= 90) \
			or (code >= 97 and code <= 122) \
			or code == 45 or code == 95
		if not is_word:
			return false
	return true


static func is_valid_public_id(public_id: String) -> bool:
	if not public_id.begins_with(PUBLIC_ID_PREFIX):
		return false
	var tail: String = public_id.substr(PUBLIC_ID_PREFIX.length())
	if tail.length() != PUBLIC_ID_HEX_LENGTH:
		return false
	for code in tail.to_utf8_buffer():
		var is_digit: bool = code >= 48 and code <= 57
		var is_lower: bool = code >= 97 and code <= 102
		if not is_digit and not is_lower:
			return false
	return true


## Accepts a full hero path or a short id and returns the canonical full path.
## Returns "" when the hero is outside the allow-list.
static func canonical_hero(hero: String) -> String:
	if hero in HERO_PATHS:
		return hero
	if HERO_SHORT_IDS.has(hero):
		return str(HERO_SHORT_IDS[hero])
	return ""


static func document_name(collection: String, document_id: String) -> String:
	return "projects/%s/databases/%s/documents/%s/%s" % [
		PROJECT_ID, DATABASE_ID, collection, document_id,
	]


static func encode_string(value: String) -> Dictionary:
	return {"stringValue": value}


static func encode_int(value: int) -> Dictionary:
	return {"integerValue": str(value)}


static func encode_timestamp_rfc3339(value: String) -> Dictionary:
	return {"timestampValue": value}


static func decode_string(fields: Dictionary, key: String) -> String:
	var entry: Variant = fields.get(key, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	return str((entry as Dictionary).get("stringValue", ""))


static func decode_int(fields: Dictionary, key: String) -> int:
	var entry: Variant = fields.get(key, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return 0
	return int(str((entry as Dictionary).get("integerValue", "0")))


static func decode_timestamp(fields: Dictionary, key: String) -> String:
	var entry: Variant = fields.get(key, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	return str((entry as Dictionary).get("timestampValue", ""))


static func now_rfc3339() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


## Silent JSON parse for untrusted text. The static `JSON.parse_string`
## prints an engine ERROR on malformed input, which fails the regression
## runner's error gate; the instance `parse` only returns its error code.
static func parse_json_value(text: String) -> Dictionary:
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(text)
	if error != OK:
		return {"ok": false}
	return {"ok": true, "value": parser.data}


## Client-side mirror of the profile rules. Fail fast before any request.
static func validate_profile(uid: String, public_id: String) -> Dictionary:
	if not is_valid_uid(uid):
		return {"ok": false, "error": "invalid-uid"}
	if not is_valid_public_id(public_id):
		return {"ok": false, "error": "invalid-public-id"}
	return {"ok": true}


static func validate_checkpoint_payload(payload: String) -> Dictionary:
	if payload.is_empty():
		return {"ok": false, "error": "empty-payload"}
	if payload.to_utf8_buffer().size() > MAX_CHECKPOINT_BYTES:
		return {"ok": false, "error": "payload-too-large"}
	var decoded: Dictionary = parse_json_value(payload)
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "payload-not-json-object"}
	return {"ok": true}


## Paid ledgers never travel in a checkpoint. The Journey payload must not
## carry entitlements, Vault balances, or purchase records.
static func checkpoint_has_forbidden_ledger_keys(payload: String) -> bool:
	var decoded: Dictionary = parse_json_value(payload)
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_DICTIONARY:
		return false
	var parsed: Variant = decoded.get("value")
	var forbidden: Array[String] = [
		"entitlements", "vault", "purchase", "purchases", "shards",
		"iap", "coins", "ledger", "product", "products", "receipt",
	]
	for key in (parsed as Dictionary).keys():
		if str(key).to_lower() in forbidden:
			return true
	return false


static func validate_hall_row(hero: String, score: int, cycles: int,
		release: String) -> Dictionary:
	if canonical_hero(hero).is_empty():
		return {"ok": false, "error": "invalid-hero"}
	if score < 0 or score > MAX_SCORE:
		return {"ok": false, "error": "invalid-score"}
	if cycles < 0 or cycles > MAX_CYCLES:
		return {"ok": false, "error": "invalid-cycles"}
	if release.is_empty() or release.length() > MAX_RELEASE_LENGTH:
		return {"ok": false, "error": "invalid-release"}
	return {"ok": true}


## Safe one-line summary for conflict dialogs. Carries sizes and markers, never
## the full payload and never credentials.
static func summarize_payload(payload: String, revision: int) -> Dictionary:
	var byte_count: int = payload.to_utf8_buffer().size()
	var digest: String = payload.sha256_text().substr(0, 8)
	var summary: Dictionary = {
		"revision": revision,
		"bytes": byte_count,
		"digest": digest,
	}
	var decoded: Dictionary = parse_json_value(payload)
	if bool(decoded.get("ok", false)) \
			and typeof(decoded.get("value")) == TYPE_DICTIONARY:
		var parsed: Dictionary = decoded.get("value")
		for key in ["gate", "cycle", "checkpoint", "act"]:
			if parsed.has(key):
				summary[key] = parsed[key]
	return summary
