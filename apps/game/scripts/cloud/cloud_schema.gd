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
const ADVENTURER_COLLECTION: String = "mb_adventurers_v1"
const NAME_COLLECTION: String = "mb_names_v1"
const ATTENDANCE_COLLECTION: String = "mb_attendance_v1"

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
## Hall rows may also carry `display`: the owner's verified adventurer
## name, bound server-side to the claimed name pair. Absent on legacy and
## unnamed rows, which keep rendering honestly.
const HALL_DISPLAY_FIELD: String = "display"
const ADVENTURER_FIELDS: Array[String] = [
	"public_id", "uid", "name_key", "display", "intro_complete",
	"schema", "created_at", "updated_at",
]
const NAME_FIELDS: Array[String] = [
	"name_key", "display", "public_id", "schema", "created_at",
]
## One private attendance row per public ID: the last claim's server
## timestamp plus the receiving install. The ONLY timestamp is server-set
## (`last_claim_at == request.time` in the rules); no client-writable
## created/updated stamp exists to forge.
const ATTENDANCE_FIELDS: Array[String] = [
	"public_id", "uid", "install_id", "last_claim_at", "schema",
	"prev_claim_at", "prev_install_id",
]
## Previous-claim carry on attendance advances: the overwritten row's
## stamp and install, copied opaquely so another install's later advance
## never erases this install's still-unapplied reward. Absent on first
## claims and pre-chain rows.
const ATTENDANCE_PREV_CLAIM_FIELD: String = "prev_claim_at"
const ATTENDANCE_PREV_INSTALL_FIELD: String = "prev_install_id"
## Rolling attendance cooldown in seconds: one grant per twelve hours,
## enforced by server time on both sides. Client wall clocks never enter.
const ATTENDANCE_COOLDOWN_SECONDS: int = 43200
## Coins per granted attendance claim.
const ATTENDANCE_GRANT_COINS: int = 2
const MAX_INSTALL_ID_LENGTH: int = 64
## Attendance receipt keys share the wallet's grant ledger with purchased
## coins. This prefix separates them so bounded pruning never evicts a
## purchase; store transaction keys never carry it.
const ATTENDANCE_KEY_PREFIX: String = "attendance:"
## Newest attendance receipts kept in the wallet ledger per install. Older
## ones prune once the owner-bound watermark passes them; the watermark
## (not the pruned key) stops them from ever granting again.
const MAX_ATTENDANCE_KEYS: int = 8
## Adventurer display bounds in visible characters. The allow-list below is
## BMP-only, so this count equals the rules `size()` UTF-16 count exactly.
const MIN_NAME_LENGTH: int = 2
const MAX_NAME_LENGTH: int = 12
## Verified names remembered per public ID on this device. Bounded: every
## entry is one small verified handle, never a token or identity profile.
const MAX_VERIFIED_NAME_CACHE: int = 8

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


## Normalize a raw adventurer name into its display form and collision key.
## Trims boundary whitespace, then requires 2-12 visible characters from
## the explicit allow-list: Latin letters, digits, underscore, precomposed
## Hangul syllables (U+AC00-U+D7A3), Hiragana (U+3041-U+3096), Katakana
## (U+30A1-U+30FA plus the prolonged mark U+30FC), CJK ideographs
## (U+4E00-U+9FFF), and single interior ASCII spaces. Path separators,
## controls, invisible/combining characters, Jamo, astral emoji, doubled
## or boundary spaces, and anything else are invalid. The key lowercases
## the display, so Latin variants collide and CJK passes through byte
## identical. The security rules mirror this list exactly; both sides
## count the same BMP-only characters.
## Returns `{ok, display, key}` or `{ok: false, error: "invalid-name"}`.
static func normalize_adventurer_name(raw: String) -> Dictionary:
	var display: String = raw.strip_edges()
	if display.length() < MIN_NAME_LENGTH \
			or display.length() > MAX_NAME_LENGTH:
		return {"ok": false, "error": "invalid-name"}
	var previous_space: bool = false
	for index in display.length():
		var code: int = display.unicode_at(index)
		if code == 32:
			if previous_space:
				return {"ok": false, "error": "invalid-name"}
			previous_space = true
			continue
		previous_space = false
		if _is_name_word(code) or _is_name_cjk(code):
			continue
		return {"ok": false, "error": "invalid-name"}
	return {"ok": true, "display": display, "key": display.to_lower()}


static func _is_name_word(code: int) -> bool:
	return (code >= 48 and code <= 57) \
		or (code >= 65 and code <= 90) \
		or (code >= 97 and code <= 122) \
		or code == 95


static func _is_name_cjk(code: int) -> bool:
	return (code >= 0xAC00 and code <= 0xD7A3) \
		or (code >= 0x3041 and code <= 0x3096) \
		or (code >= 0x30A1 and code <= 0x30FA) \
		or code == 0x30FC \
		or (code >= 0x4E00 and code <= 0x9FFF)


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


static func encode_bool(value: bool) -> Dictionary:
	return {"booleanValue": value}


static func decode_bool(fields: Dictionary, key: String) -> bool:
	var entry: Variant = fields.get(key, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	return bool((entry as Dictionary).get("booleanValue", false))


static func now_rfc3339() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


## Server timestamps arrive RFC3339 Zulu with optional fractional seconds.
## Truncation to whole seconds is deliberate: cooldown math compares
## seconds. Returns 0 for garbage; callers fail closed on unparseable
## server time rather than granting on an unknown clock. The engine logs
## an error for any malformed or impossible date, so every input passes
## the strict shape gate first and the log stays clean.
static func unix_from_rfc3339(text: String) -> int:
	var clean: String = text.strip_edges()
	if clean.ends_with("Z") or clean.ends_with("z"):
		clean = clean.left(clean.length() - 1)
	var dot: int = clean.find(".")
	if dot >= 0:
		clean = clean.left(dot)
	if not _is_datetime_string(clean):
		return 0
	return maxi(int(Time.get_unix_time_from_datetime_string(clean)), 0)


## Strict datetime shape: `DDDD-DD-DD` plus `T` (or one space) plus
## `DD:DD:DD`, a real calendar day with leap years counted, year
## 1970..9999, hour 00..23, minute and second 00..59. Anything else is
## not a stamp the engine may see.
static func _is_datetime_string(clean: String) -> bool:
	if clean.length() != 19:
		return false
	var join: String = clean.substr(10, 1)
	if join != "T" and join != " ":
		return false
	if clean.substr(4, 1) != "-" or clean.substr(7, 1) != "-" \
			or clean.substr(13, 1) != ":" \
			or clean.substr(16, 1) != ":":
		return false
	var digits: String = clean.left(4) + clean.substr(5, 2) \
		+ clean.substr(8, 2) + clean.substr(11, 2) \
		+ clean.substr(14, 2) + clean.substr(17, 2)
	for index in digits.length():
		var code: int = int(digits.unicode_at(index))
		if code < 48 or code > 57:
			return false
	var year: int = int(clean.left(4))
	if year < 1970 or year > 9999:
		return false
	var month: int = int(clean.substr(5, 2))
	if month < 1 or month > 12:
		return false
	var leap: bool = year % 4 == 0 \
		and (year % 100 != 0 or year % 400 == 0)
	var longest: Array = [31, 29 if leap else 28, 31, 30, 31, 30,
		31, 31, 30, 31, 30, 31]
	if int(clean.substr(8, 2)) < 1 \
			or int(clean.substr(8, 2)) > int(longest[month - 1]):
		return false
	if int(clean.substr(11, 2)) > 23 \
			or int(clean.substr(14, 2)) > 59 \
			or int(clean.substr(17, 2)) > 59:
		return false
	return true


## Absolute UTC deadline for the reminder API. Never a device clock: the
## input seconds always come from a server read or commit timestamp.
static func rfc3339_from_unix(seconds: int) -> String:
	var text: String = Time.get_datetime_string_from_unix_time(
		maxi(seconds, 0))
	return text.replace(" ", "T") + "Z"


## Whole-second cooldown math over server timestamps only. `server_now`
## is a batchGet readTime or commitTime, never the device clock.
## Returns `{eligible, remaining (0..cooldown), next_at}` in seconds. A
## backwards or forged-future stamp fails closed with the full wait,
## never an instant grant.
static func attendance_cooldown(server_now: int,
		last_claim_at: int) -> Dictionary:
	var elapsed: int = server_now - last_claim_at
	if elapsed >= ATTENDANCE_COOLDOWN_SECONDS:
		return {"eligible": true, "remaining": 0,
			"next_at": server_now + ATTENDANCE_COOLDOWN_SECONDS}
	if elapsed < 0:
		return {"eligible": false,
			"remaining": ATTENDANCE_COOLDOWN_SECONDS,
			"next_at": last_claim_at + ATTENDANCE_COOLDOWN_SECONDS}
	return {"eligible": false,
		"remaining": ATTENDANCE_COOLDOWN_SECONDS - elapsed,
		"next_at": last_claim_at + ATTENDANCE_COOLDOWN_SECONDS}


## Stable wallet receipt key for one attendance grant. Derived, never
## random: the claimer and any later recovery read the same server row
## and derive the same key, so double taps and uncertain acks converge
## on one idempotent grant, while another install's key never matches
## this wallet's.
static func attendance_receipt_key(public_id: String, claim_seconds: int,
		install_id: String) -> String:
	return "%s%s:%d:%s" % [ATTENDANCE_KEY_PREFIX, public_id,
		claim_seconds, install_id]


## Claim seconds embedded in a receipt key, or -1 unless the shape is
## exactly `attendance:{public_id}:{seconds}:{install}`.
static func attendance_key_seconds(key: String) -> int:
	var parts: PackedStringArray = key.split(":")
	if parts.size() != 4 or parts[0] != "attendance":
		return -1
	if parts[1].is_empty() or parts[3].is_empty():
		return -1
	if not parts[2].is_valid_int():
		return -1
	var seconds: int = int(parts[2])
	if seconds <= 0:
		return -1
	return seconds


## Our own install binding for a claim write. Fail closed on empty or
## overlong IDs: no claim without a receiving-install binding.
static func is_valid_install_id(install_id: String) -> bool:
	if install_id.is_empty():
		return false
	if install_id.length() > MAX_INSTALL_ID_LENGTH:
		return false
	return not (install_id.contains("/") or install_id.contains(" ")
		or install_id.contains(":"))


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
		# The defeat marker travels with the summary so a conflict dialog
		# can name a sealed run. Only a present bool rides along; payloads
		# sealed before the defeat rules carry no key at all.
		if parsed.has("ended") and parsed.get("ended") is bool:
			summary["ended"] = bool(parsed["ended"])
	return summary
