extends Node

## Consent-based minimal game-analytics sender.
##
## Does not create or send a permanent user ID. Each launch gets a new
## session_id, each run a new run_id, and retry nonce/sequence live only in a
## local file. Event names and properties cannot grow past the allow-list below,
## so player names, product IDs, advertising IDs, and device IDs cannot leak in.

const FirebaseConfigScript: Script = preload("res://scripts/net/firebase_config.gd")

const SAVE_PATH: String = "user://analytics.json"
const TEMP_SAVE_PATH: String = "user://analytics.json.tmp"
const COLLECTION: String = "analytics_events_v1"
const SCHEMA_VERSION: int = 1
const MAX_PENDING: int = 200
const QUEUE_PRIORITY_DETAIL: int = 0
const QUEUE_PRIORITY_STRUCTURE: int = 1
const QUEUE_PRIORITY_LIFECYCLE_ANCHOR: int = 2
## When the queue saturates, keep the boundaries that decide analyzability
## longer than detail logs. activation and retention are top-level lifecycle
## anchors in an atomic contract with local cohort metadata; app open and
## run start/end are the funnel's denominator and close. Remaining repeat-play
## events are default detail and drop first.
const EVENT_QUEUE_PRIORITIES: Dictionary = {
	"analytics_activated": QUEUE_PRIORITY_LIFECYCLE_ANCHOR,
	"retention_checkpoint": QUEUE_PRIORITY_LIFECYCLE_ANCHOR,
	"app_opened": QUEUE_PRIORITY_STRUCTURE,
	"run_started": QUEUE_PRIORITY_STRUCTURE,
	"run_ended": QUEUE_PRIORITY_STRUCTURE,
}
const MAX_LOCAL_AGE_SECONDS: int = 14 * 24 * 60 * 60
## Block reuse of run IDs whose pending starts expired in this process.
## The cap matches the local queue a process can hold; there is no reason to
## grow past that.
const MAX_INVALIDATED_PENDING_RUNS: int = MAX_PENDING
const SERVER_TTL_SECONDS: int = 90 * 24 * 60 * 60
const REQUEST_TIMEOUT_SECONDS: float = 4.0
const INITIAL_RETRY_SECONDS: float = 5.0
const MAX_RETRY_SECONDS: float = 300.0
const RETENTION_DAYS: Array[int] = [1, 7, 30]
const RETENTION_BITS: Array[int] = [1, 2, 4]

const EVENT_PROPERTY_KEYS: Dictionary = {
	"analytics_activated": ["cohort_version", "cohort_day"],
	"app_opened": ["open_kind"],
	"retention_checkpoint": ["day", "cohort_version", "cohort_day"],
	"hero_selected": ["hero"],
	"boon_purchased": ["boon", "rank", "shards_spent"],
	"run_started": ["hero", "boon_tier"],
	"tutorial_step_completed": ["step", "elapsed_ms"],
	"relic_chosen": ["relic", "family", "source", "stack", "cycle", "elapsed_ms"],
	"beacon_choice": ["beacon", "cycle", "terrain", "mode", "elapsed_ms"],
	"beacon_lit": ["beacon", "cycle", "terrain", "mode", "elapsed_ms"],
	"overcharge_resolved": ["outcome", "terrain", "cycle", "duration_ms", "reward"],
	"gate_crossed": ["cycle", "terrain", "elapsed_ms"],
	"guardian_started": ["guardian", "terrain", "cycle", "elapsed_ms"],
	"guardian_defeated": [
		"guardian", "terrain", "cycle", "duration_ms", "elapsed_ms",
	],
	"cycle_decision": ["choice", "cycle", "overcharges", "elapsed_ms"],
	"evolution_unlocked": ["family", "cycle", "elapsed_ms"],
	"continue_used": ["cycle", "elapsed_ms"],
	"run_ended": [
		"reason", "cycle", "duration_ms", "score", "kills", "beacons",
		"guardians", "relics", "continues",
	],
}

const REQUIRED_EVENT_PROPERTY_KEYS: Dictionary = {
	"analytics_activated": ["cohort_version", "cohort_day"],
	"retention_checkpoint": ["day", "cohort_version", "cohort_day"],
}

const STRING_PROPERTY_VALUES: Dictionary = {
	"hero": ["warden", "dancer", "keeper", "knight", "eclipse", "sage"],
	"boon": [
		"steady_heart", "keen_edge", "light_foot", "first_gift",
		"dew_sense", "shard_sense",
	],
	"step": ["move", "dash", "core", "beacon", "relic"],
	"relic": [
		"dew_hunter", "heavy_arrow", "light_step", "long_blade",
		"moon_dash", "moon_ring", "moon_ripple", "pierce_arrow",
		"quick_arrow", "shadow_veil", "sharp_moon", "swift_hand",
		"tough_life", "twin_arrow", "warm_beacon", "wide_arc",
	],
	"family": ["starfall", "full_moon", "moon_dance", "support"],
	"source": ["opening", "level", "beacon", "guardian"],
	"terrain": ["forest", "field", "camp"],
	"mode": ["normal", "overcharge"],
	"outcome": ["success", "failed", "abandoned", "defeat"],
	"reward": ["core", "growth", "relic", "shards", "none"],
	"choice": ["cashout", "continue"],
	"open_kind": ["cold", "resume"],
	"guardian": [
		"guardian", "guardian_forest", "guardian_forest_thorn",
		"guardian_field", "guardian_field_storm", "guardian_camp",
		"guardian_camp_siege",
	],
	"reason": ["defeat", "restart", "title", "quit", "cashout"],
}

const INTEGER_PROPERTY_RANGES: Dictionary = {
	"day": [1, 30],
	"rank": [1, 20],
	"shards_spent": [0, 1000000],
	"boon_tier": [0, 100],
	"elapsed_ms": [0, 7 * 24 * 60 * 60 * 1000],
	"duration_ms": [0, 7 * 24 * 60 * 60 * 1000],
	"stack": [1, 999],
	"cycle": [0, 999],
	"beacon": [1, 9],
	"overcharges": [0, 3],
	"score": [0, 2000000000],
	"kills": [0, 2000000000],
	"beacons": [0, 9999],
	"guardians": [0, 9999],
	"relics": [0, 9999],
	"continues": [0, 999],
}

var _config: Dictionary = {}
var _consent_granted: bool = false
var _session_id: String = ""
var _queue_nonce: String = ""
var _next_sequence: int = 0
var _pending: Array = []
var _invalidated_pending_run_ids: Dictionary = {}

var _http: HTTPRequest = null
var _in_flight_id: String = ""
var _next_attempt_msec: int = 0
var _retry_seconds: float = INITIAL_RETRY_SECONDS
var _cold_launch_recorded: bool = false

## Tests inject consent and config in memory and never make a network request.
var _test_mode: bool = false
var _test_consent: bool = false
var _test_configured: bool = false
var _test_now_unix: int = -1
var _test_write_disk: bool = false
var _test_fail_next_save: bool = false
var _test_fail_next_metadata_save: bool = false
var _test_cohort_unix: int = 0
var _test_cohort_version: String = ""
var _test_retention_mask: int = 0


func _ready() -> void:
	_session_id = _random_token()
	_reload_config()
	_enforce_configuration_gate()
	var settings: Node = get_node_or_null("/root/Settings")
	var consent_callback: Callable = Callable(self, "refresh_consent")
	if settings != null and settings.has_signal("changed") \
			and not settings.is_connected("changed", consent_callback):
		settings.connect("changed", consent_callback)
	_consent_granted = _read_settings_consent()
	if _consent_granted:
		_load_state()
	else:
		clear_pending()
	# The first process tick can start a send, so keep the send loop closed
	# until local metadata for the recovery lifecycle is fixed in one deferred
	# bootstrap.
	set_process(false)
	_bootstrap.call_deferred()


func _bootstrap() -> void:
	activate()
	set_process(true)
	_schedule_flush()


func _notification(what: int) -> void:
	# Mobile can revive the same instance days later without killing the process.
	# Count only cold launch and that return is missing from app_opened and
	# D1/D7, so record foreground as a new ephemeral session. Initial launch is
	# `_ready()`'s, so it does not double.
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_record_foreground.call_deferred()


func _process(_delta: float) -> void:
	if _test_mode or _in_flight_id != "" or _pending.is_empty():
		return
	if Time.get_ticks_msec() >= _next_attempt_msec:
		_try_flush()


## Whether this build is configured to actually send analytics.
##
## Does not look at consent. Read-only boundary for whether an UNKNOWN user
## can be shown a consent choice. Debug builds also need allow_debug to be true.
func configured() -> bool:
	if _test_mode:
		return _test_configured
	if not FirebaseConfigScript.configured_for_analytics(_config):
		return false
	return not OS.is_debug_build() or bool(_config.get("analytics_allow_debug", false))


## True only on a shipping build with config, consent, and key all present.
func enabled() -> bool:
	return _consent_granted and configured()


## Do not carry a stored GRANTED into the next shipping build when this build
## has no send config.
##
## A choice made with no config is not consent that described the real
## collection scope. Leave it and a later update that only adds config can
## start collecting with no new choice. Close this run's memory and queue
## first, then leave DENIED via Settings' revoke atomic-save contract. Even if
## settings save fails, Settings keeps this run DENIED.
func _enforce_configuration_gate() -> bool:
	if configured():
		return true
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("set_analytics_consent"):
		var settings_script: Script = settings.get_script() as Script
		var constants: Dictionary = settings_script.get_script_constant_map() \
			if settings_script != null else {}
		var consent_enum: Variant = constants.get("AnalyticsConsent", null)
		if typeof(consent_enum) == TYPE_DICTIONARY \
				and (consent_enum as Dictionary).has("GRANTED") \
				and (consent_enum as Dictionary).has("DENIED") \
				and int(settings.get("analytics_consent")) \
					== int((consent_enum as Dictionary).get("GRANTED")):
			settings.call(
				"set_analytics_consent",
				int((consent_enum as Dictionary).get("DENIED")),
			)
	_consent_granted = false
	if _test_mode:
		_test_consent = false
	clear_pending()
	return false


## Ephemeral ID for one run. Do not save it or reuse it on another run.
func new_run_id() -> String:
	return _random_token()


## Enqueue this app launch's start event and each reached D1/D7/D30 return
## signal once.
##
## Cohort time, version, and bitmask live only in Settings' local file and are
## not sent. Confirm the cohort only after the first activation event is in
## the atomic queue.
func activate(open_kind: String = "cold") -> bool:
	if _cold_launch_recorded or not enabled():
		return false
	var now_unix: int = _now_unix()
	var cohort: Dictionary = _cohort_metadata()
	var cohort_unix: int = int(cohort.get("unix", 0))
	var cohort_version: String = str(cohort.get("version", ""))
	if cohort_unix <= 0 or cohort_unix > now_unix + 600 \
			or not _is_safe_version(cohort_version):
		if cohort_unix > 0 or not cohort_version.is_empty():
			_clear_cohort_metadata()
		var queued_cohort: Dictionary = _queued_activation_cohort()
		cohort_unix = int(queued_cohort.get("unix", now_unix))
		cohort_version = str(queued_cohort.get("version", _app_version()))
		if queued_cohort.is_empty():
			if not track("analytics_activated", {
				"cohort_version": cohort_version,
				"cohort_day": _day_string(cohort_unix),
			}):
				return false
		if not _set_cohort_metadata(cohort_unix, cohort_version):
			_discard_queued_lifecycle("analytics_activated", cohort_version)
			return false
		cohort = _cohort_metadata()
	cohort["mask"] = _reconcile_queued_retention(cohort)
	if not track("app_opened", {"open_kind": open_kind}):
		return false
	_enqueue_crossed_retention(now_unix, cohort)
	_cold_launch_recorded = true
	return true


func _record_foreground() -> bool:
	if not enabled():
		return false
	# session_id is one cold process, not a foreground count. A brief
	# background before the first run still keeps cold app_opened linked to
	# run_started.
	_cold_launch_recorded = false
	return activate("resume")


## Put an allowed play event on the async queue.
##
## Do not start a server request before the save finishes. If the app dies
## right after the response and the same document is sent again, a
## deterministic document_id makes 409 and blocks double-count.
func track(event_name: String, properties: Dictionary = {}, run_id: String = "") -> bool:
	if not enabled() or not EVENT_PROPERTY_KEYS.has(event_name):
		return false
	if not run_id.is_empty() and not _is_lower_hex(run_id, 32):
		return false
	# A run whose pending start this process dropped to expiry or validation
	# failure is known to have no start on the server. Do not revive later
	# events of the same ID on a new sequence.
	if not run_id.is_empty() and _invalidated_pending_run_ids.has(run_id):
		return false
	var sanitized: Dictionary = _sanitize_properties(event_name, properties)
	if not bool(sanitized.get("ok", false)):
		return false
	if _session_id.is_empty():
		_session_id = _random_token()
	if _queue_nonce.is_empty():
		_queue_nonce = _random_token()
		_next_sequence = 0

	var now_unix: int = _now_unix()
	var sequence: int = _next_sequence
	var payload: Dictionary = {
		"schema": SCHEMA_VERSION,
		"event": event_name,
		"client_at_unix": now_unix,
		"client_day": _day_string(now_unix),
		"expires_at_unix": now_unix + SERVER_TTL_SECONDS,
		"session_id": _session_id,
		"app_version": _app_version(),
		"platform": _platform(),
		"locale": _locale(),
		"properties": sanitized.get("properties", {}),
	}
	if not run_id.is_empty():
		payload["run_id"] = run_id
	var item: Dictionary = {
		"id": _event_document_id(_queue_nonce, sequence),
		"sequence": sequence,
		"queued_at_unix": now_unix,
		"event": payload,
	}

	var old_pending: Array = _pending.duplicate(true)
	var old_sequence: int = _next_sequence
	if _pending.size() >= MAX_PENDING \
			and not _make_room_for_event(_pending, event_name):
		# If only structure/lifecycle remain, do not drop a more meaningful
		# event for one new detail. Queue and sequence stay unchanged.
		return false
	_next_sequence += 1
	_pending.append(item)
	var save_error: Error = _persist_if_needed()
	if save_error != OK:
		_pending = old_pending
		_next_sequence = old_sequence
		return false
	_schedule_flush()
	return true


## Re-read the Settings.analytics_consent == Settings.AnalyticsConsent.GRANTED
## contract. If consent is revoked, wipe unsent events and the local nonce
## immediately.
func refresh_consent() -> void:
	var granted: bool = _test_consent if _test_mode else _read_settings_consent()
	var was_granted: bool = _consent_granted
	_consent_granted = granted
	if not granted:
		clear_pending()
		_clear_cohort_metadata()
		_cold_launch_recorded = false
	elif granted:
		if not was_granted:
			_cold_launch_recorded = false
		_schedule_flush()
		activate.call_deferred()


func clear_pending() -> void:
	if _http != null:
		_http.cancel_request()
	_pending.clear()
	_queue_nonce = ""
	_next_sequence = 0
	_invalidated_pending_run_ids.clear()
	_in_flight_id = ""
	_retry_seconds = INITIAL_RETRY_SECONDS
	_next_attempt_msec = 0
	_discard_file(TEMP_SAVE_PATH)
	_discard_file(SAVE_PATH)


func _reload_config() -> void:
	_config = FirebaseConfigScript.read()


func _read_settings_consent() -> bool:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null:
		return false
	var settings_script: Script = settings.get_script() as Script
	if settings_script == null:
		return false
	var constants: Dictionary = settings_script.get_script_constant_map()
	var consent_enum: Variant = constants.get("AnalyticsConsent", null)
	if typeof(consent_enum) != TYPE_DICTIONARY \
			or not (consent_enum as Dictionary).has("GRANTED"):
		return false
	var has_consent_property: bool = false
	for property in settings.get_property_list():
		if str((property as Dictionary).get("name", "")) == "analytics_consent":
			has_consent_property = true
			break
	if not has_consent_property:
		return false
	return int(settings.get("analytics_consent")) \
		== int((consent_enum as Dictionary).get("GRANTED"))


func _cohort_metadata() -> Dictionary:
	if _test_mode:
		return {
			"unix": _test_cohort_unix,
			"version": _test_cohort_version,
			"mask": _test_retention_mask,
		}
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null:
		return {"unix": 0, "version": "", "mask": 0}
	return {
		"unix": int(settings.get("analytics_cohort_unix")),
		"version": str(settings.get("analytics_cohort_version")),
		"mask": int(settings.get("analytics_retention_mask")),
	}


func _set_cohort_metadata(unix_time: int, version: String) -> bool:
	if _test_mode:
		if _test_fail_next_metadata_save:
			_test_fail_next_metadata_save = false
			return false
		_test_cohort_unix = unix_time
		_test_cohort_version = version
		_test_retention_mask = 0
		return true
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null or not settings.has_method("set_analytics_cohort"):
		return false
	if not bool(settings.call("set_analytics_cohort", unix_time, version)):
		return false
	return int(settings.get("analytics_cohort_unix")) == unix_time \
		and str(settings.get("analytics_cohort_version")) == version


func _mark_retention(bit: int) -> bool:
	if _test_mode:
		if _test_fail_next_metadata_save:
			_test_fail_next_metadata_save = false
			return false
		_test_retention_mask |= bit
		return true
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null or not settings.has_method("mark_analytics_retention"):
		return false
	if not bool(settings.call("mark_analytics_retention", bit)):
		return false
	return (int(settings.get("analytics_retention_mask")) & bit) != 0


func _clear_cohort_metadata() -> void:
	if _test_mode:
		_test_cohort_unix = 0
		_test_cohort_version = ""
		_test_retention_mask = 0
		return
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("clear_analytics_cohort"):
		settings.call("clear_analytics_cohort")


func _enqueue_crossed_retention(now_unix: int, cohort: Dictionary) -> void:
	var cohort_unix: int = int(cohort.get("unix", 0))
	var cohort_version: String = str(cohort.get("version", ""))
	var mask: int = int(cohort.get("mask", 0))
	if cohort_unix <= 0 or now_unix < cohort_unix \
			or not _is_safe_version(cohort_version):
		return
	var cohort_day_unix: int = Time.get_unix_time_from_datetime_string(
		_day_string(cohort_unix) + "T00:00:00Z")
	var current_day_unix: int = Time.get_unix_time_from_datetime_string(
		_day_string(now_unix) + "T00:00:00Z")
	var crossed_days: int = maxi(
		floori(float(current_day_unix - cohort_day_unix) / (24.0 * 60.0 * 60.0)),
		0)
	for index in RETENTION_DAYS.size():
		var day: int = RETENTION_DAYS[index]
		var bit: int = RETENTION_BITS[index]
		if (mask & bit) != 0 or crossed_days < day:
			continue
		# D1/D7/D30 is 'did they return on that calendar day'. Back-issuing
		# D1 and D7 on the first relaunch after 30 days would inflate real
		# return, so a past window is local-complete only.
		if crossed_days > day:
			if _mark_retention(bit):
				mask |= bit
			continue
		if _queued_retention_exists(cohort_version, day):
			if _mark_retention(bit):
				mask |= bit
			else:
				_discard_queued_lifecycle(
					"retention_checkpoint", cohort_version, day)
			continue
		if track("retention_checkpoint", {
			"day": day,
			"cohort_version": cohort_version,
			"cohort_day": _day_string(cohort_unix),
		}):
			if _mark_retention(bit):
				mask |= bit
			else:
				_discard_queued_lifecycle(
					"retention_checkpoint", cohort_version, day)


func _queued_retention_exists(version: String, day: int) -> bool:
	for item in _pending:
		var payload: Dictionary = (item as Dictionary).get("event", {}) as Dictionary
		if str(payload.get("event", "")) != "retention_checkpoint":
			continue
		var properties: Dictionary = payload.get("properties", {}) as Dictionary
		if str(properties.get("cohort_version", "")) == version \
				and int(properties.get("day", 0)) == day:
			return true
	return false


func _discard_queued_lifecycle(event_name: String, version: String,
		day: int = 0) -> void:
	var cancelled_in_flight: bool = false
	for index in range(_pending.size() - 1, -1, -1):
		var item: Dictionary = _pending[index] as Dictionary
		var payload: Dictionary = item.get(
			"event", {}) as Dictionary
		if str(payload.get("event", "")) != event_name:
			continue
		var properties: Dictionary = payload.get("properties", {}) as Dictionary
		if str(properties.get("cohort_version", "")) != version:
			continue
		if day > 0 and int(properties.get("day", 0)) != day:
			continue
		cancelled_in_flight = cancelled_in_flight \
			or str(item.get("id", "")) == _in_flight_id
		_pending.remove_at(index)
	if cancelled_in_flight:
		if _http != null:
			_http.cancel_request()
		_in_flight_id = ""
		_next_attempt_msec = 0
	# A lifecycle whose metadata is not permanently saved will duplicate under
	# a new ID on relaunch if it hits the server first. Even if disk cleanup
	# fails, it must leave current memory.
	_persist_if_needed()


func _queued_activation_cohort() -> Dictionary:
	for item in _pending:
		var payload: Dictionary = (item as Dictionary).get("event", {}) as Dictionary
		if str(payload.get("event", "")) != "analytics_activated":
			continue
		var properties: Dictionary = payload.get("properties", {}) as Dictionary
		var version: String = str(properties.get("cohort_version", ""))
		var unix_time: int = int(payload.get("client_at_unix", 0))
		if unix_time > 0 and _is_safe_version(version):
			return {"unix": unix_time, "version": version}
	return {}


func _reconcile_queued_retention(cohort: Dictionary) -> int:
	var version: String = str(cohort.get("version", ""))
	var mask: int = int(cohort.get("mask", 0))
	var unpersisted_days: Array[int] = []
	for item in _pending.duplicate(true):
		var payload: Dictionary = (item as Dictionary).get("event", {}) as Dictionary
		if str(payload.get("event", "")) != "retention_checkpoint":
			continue
		var properties: Dictionary = payload.get("properties", {}) as Dictionary
		if str(properties.get("cohort_version", "")) != version:
			continue
		var day: int = int(properties.get("day", 0))
		var index: int = RETENTION_DAYS.find(day)
		if index < 0:
			continue
		var bit: int = RETENTION_BITS[index]
		if (mask & bit) != 0:
			continue
		if _mark_retention(bit):
			mask |= bit
		else:
			unpersisted_days.append(day)
			# Close only the in-memory mask so this activate does not immediately
			# recreate the same day under a new document ID. Settings bits stay
			# 0 so the next foreground can retry safely.
			mask |= bit
	for day in unpersisted_days:
		_discard_queued_lifecycle("retention_checkpoint", version, day)
	return mask


func _make_room_for_event(queue: Array, incoming_event_name: String) -> bool:
	var victim_index: int = _lowest_value_event_index(queue)
	if victim_index < 0:
		return false
	var victim_priority: int = _queued_event_priority(queue[victim_index])
	if _event_queue_priority(incoming_event_name) < victim_priority:
		return false
	queue.remove_at(victim_index)
	return true


func _remove_lowest_value_event(queue: Array) -> bool:
	var victim_index: int = _lowest_value_event_index(queue)
	if victim_index < 0:
		return false
	queue.remove_at(victim_index)
	return true


func _lowest_value_event_index(queue: Array) -> int:
	if queue.is_empty():
		return -1
	# A still-pending run start has no proof the server got it. No later event
	# may push it out, or the same Arena adding an end later would orphan it.
	# A completed end is kept longer than same-tier alternatives but can still
	# be dropped as last-resort fallback.
	var queued_run_starts: Dictionary = _queued_run_ids(queue, "run_started")
	var result: int = -1
	var lowest_priority: int = QUEUE_PRIORITY_LIFECYCLE_ANCHOR + 1
	var paired_end_fallback: int = -1
	var paired_end_priority: int = QUEUE_PRIORITY_LIFECYCLE_ANCHOR + 1
	for index in range(queue.size()):
		var candidate: Variant = queue[index]
		if not _in_flight_id.is_empty() and typeof(candidate) == TYPE_DICTIONARY \
				and str((candidate as Dictionary).get("id", "")) == _in_flight_id:
			continue
		var candidate_start_id: String = _queued_event_run_id(
			candidate, "run_started")
		if not candidate_start_id.is_empty():
			continue
		var priority: int = _queued_event_priority(queue[index])
		var candidate_end_id: String = _queued_event_run_id(
			candidate, "run_ended")
		if not candidate_end_id.is_empty() \
				and queued_run_starts.has(candidate_end_id):
			if paired_end_fallback < 0 or priority < paired_end_priority:
				paired_end_fallback = index
				paired_end_priority = priority
			continue
		# Same tier: drop the oldest so recent context stays.
		if result < 0 or priority < lowest_priority:
			result = index
			lowest_priority = priority
	if paired_end_fallback >= 0 \
			and (result < 0 or paired_end_priority < lowest_priority):
		return paired_end_fallback
	return result


func _queued_run_ids(queue: Array, event_name: String) -> Dictionary:
	var result: Dictionary = {}
	for candidate in queue:
		var run_id: String = _queued_event_run_id(candidate, event_name)
		if not run_id.is_empty():
			result[run_id] = true
	return result


func _queued_event_run_id(candidate: Variant, event_name: String) -> String:
	if typeof(candidate) != TYPE_DICTIONARY:
		return ""
	var payload: Variant = (candidate as Dictionary).get("event", null)
	if typeof(payload) != TYPE_DICTIONARY:
		return ""
	if str((payload as Dictionary).get("event", "")) != event_name:
		return ""
	return str((payload as Dictionary).get("run_id", ""))


func _queued_event_priority(candidate: Variant) -> int:
	if typeof(candidate) != TYPE_DICTIONARY:
		return QUEUE_PRIORITY_DETAIL
	var payload: Variant = (candidate as Dictionary).get("event", null)
	if typeof(payload) != TYPE_DICTIONARY:
		return QUEUE_PRIORITY_DETAIL
	return _event_queue_priority(str((payload as Dictionary).get("event", "")))


func _event_queue_priority(event_name: String) -> int:
	return int(EVENT_QUEUE_PRIORITIES.get(event_name, QUEUE_PRIORITY_DETAIL))


func _schedule_flush() -> void:
	if not enabled() or _pending.is_empty():
		return
	# Keep a future deadline set by 429/5xx even if a new event arrives. After
	# success or a permanent error the caller opens 0, and only then is the
	# next head sent immediately.
	if _next_attempt_msec <= 0:
		_next_attempt_msec = Time.get_ticks_msec()
	if _test_mode:
		return
	_ensure_http()
	_try_flush.call_deferred()


func _ensure_http() -> void:
	if _http != null or _test_mode:
		return
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT_SECONDS
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


func _try_flush() -> void:
	if _test_mode or not enabled() or _pending.is_empty() or _in_flight_id != "":
		return
	if Time.get_ticks_msec() < _next_attempt_msec:
		return
	if not _prune_expired_pending():
		_schedule_retry()
		return
	if _pending.is_empty():
		return
	_ensure_http()
	if _http == null:
		return
	var request: Dictionary = _request_for_head()
	if request.is_empty():
		_drop_head()
		return
	_in_flight_id = str(request.get("id", ""))
	var error: Error = _http.request(
		str(request.get("url", "")),
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(request.get("body", {})))
	if error != OK:
		_in_flight_id = ""
		_schedule_retry()


func _prune_expired_pending() -> bool:
	var now_unix: int = _now_unix()
	var before: Array = _pending.duplicate(true)
	var invalidated_runs: Dictionary = {}
	for index in range(_pending.size() - 1, -1, -1):
		var candidate: Variant = _pending[index]
		var queued: Dictionary = _coerce_integer(
			(candidate as Dictionary).get("queued_at_unix", -1) \
			if typeof(candidate) == TYPE_DICTIONARY else null)
		var queued_at: int = int(queued.get("value", -1))
		if not bool(queued.get("ok", false)) or queued_at > now_unix + 600 \
				or now_unix - queued_at > MAX_LOCAL_AGE_SECONDS:
			var run_id: String = _recognized_pending_run_start_id(candidate)
			if not run_id.is_empty():
				invalidated_runs[run_id] = true
			_pending.remove_at(index)
	# The start may be old while later events are new. If the local start never
	# reached the server, wipe end and detail events as a bundle so the run
	# is not orphaned.
	_discard_run_scoped_items(_pending, invalidated_runs)
	if _pending.size() == before.size():
		return true
	if _persist_if_needed() == OK:
		_remember_invalidated_pending_runs(invalidated_runs)
		return true
	_pending = before
	return false


func _recognized_pending_run_start_id(candidate: Variant) -> String:
	var run_id: String = _queued_event_run_id(candidate, "run_started")
	return run_id if _is_lower_hex(run_id, 32) else ""


func _queued_item_run_id(candidate: Variant) -> String:
	if typeof(candidate) != TYPE_DICTIONARY:
		return ""
	var payload: Variant = (candidate as Dictionary).get("event", null)
	if typeof(payload) != TYPE_DICTIONARY:
		return ""
	var run_id: String = str((payload as Dictionary).get("run_id", ""))
	return run_id if _is_lower_hex(run_id, 32) else ""


func _discard_run_scoped_items(queue: Array, run_ids: Dictionary) -> void:
	if run_ids.is_empty():
		return
	for index in range(queue.size() - 1, -1, -1):
		var run_id: String = _queued_item_run_id(queue[index])
		if not run_id.is_empty() and run_ids.has(run_id):
			queue.remove_at(index)


func _remember_invalidated_pending_runs(run_ids: Dictionary) -> void:
	for run_id_value in run_ids.keys():
		var run_id: String = str(run_id_value)
		if not _is_lower_hex(run_id, 32):
			continue
		# A re-seen ID refreshes order from the latest invalidation.
		_invalidated_pending_run_ids.erase(run_id)
		_invalidated_pending_run_ids[run_id] = true
	while _invalidated_pending_run_ids.size() > MAX_INVALIDATED_PENDING_RUNS:
		var oldest: Variant = _invalidated_pending_run_ids.keys()[0]
		_invalidated_pending_run_ids.erase(oldest)


func _request_for_head() -> Dictionary:
	if _pending.is_empty():
		return {}
	var item: Dictionary = _pending[0] as Dictionary
	var document_id: String = str(item.get("id", ""))
	var payload: Dictionary = item.get("event", {}) as Dictionary
	if not _valid_loaded_payload(payload) or not _is_document_id(document_id):
		return {}
	var key: String = str(_config.get("web_api_key", ""))
	if _test_mode:
		key = "test-key"
	return {
		"id": document_id,
		"url": FirebaseConfigScript.document_create_url(COLLECTION, document_id, key),
		"body": _firestore_body(payload),
	}


func _on_request_completed(_result: int, response_code: int,
		_headers: PackedStringArray, _body: PackedByteArray) -> void:
	var completed_id: String = _in_flight_id
	_in_flight_id = ""
	if completed_id.is_empty() or _pending.is_empty() \
			or str((_pending[0] as Dictionary).get("id", "")) != completed_id:
		_schedule_retry()
		return
	if (response_code >= 200 and response_code < 300) or response_code == 409:
		_drop_head()
		_retry_seconds = INITIAL_RETRY_SECONDS
		_next_attempt_msec = 0
		_schedule_flush()
		return
	# Drop only requests whose body/document is permanently wrong. Auth, rules,
	# quota, and server errors stay on the bounded queue — shipping config may
	# be fixed or the connection may return.
	if response_code in [400, 404, 413, 422]:
		_drop_head()
		_retry_seconds = INITIAL_RETRY_SECONDS
		_next_attempt_msec = 0
		_schedule_flush()
		return
	_schedule_retry()


func _drop_head() -> void:
	if _pending.is_empty():
		return
	_pending.pop_front()
	if _pending.is_empty():
		_queue_nonce = ""
		_next_sequence = 0
	_persist_if_needed()


func _schedule_retry() -> void:
	_next_attempt_msec = Time.get_ticks_msec() + ceili(_retry_seconds * 1000.0)
	_retry_seconds = minf(_retry_seconds * 2.0, MAX_RETRY_SECONDS)


func _firestore_body(payload: Dictionary) -> Dictionary:
	var property_fields: Dictionary = {}
	for key in (payload.get("properties", {}) as Dictionary).keys():
		property_fields[str(key)] = _firestore_value(
			(payload.get("properties", {}) as Dictionary).get(key))
	var fields: Dictionary = {
		"schema": {"integerValue": str(int(payload.get("schema", SCHEMA_VERSION)))},
		"event": {"stringValue": str(payload.get("event", ""))},
		"client_at": {
			"timestampValue": _timestamp_string(int(payload.get("client_at_unix", 0))),
		},
		"client_day": {"stringValue": str(payload.get("client_day", ""))},
		"expires_at": {
			"timestampValue": _timestamp_string(int(payload.get("expires_at_unix", 0))),
		},
		"session_id": {"stringValue": str(payload.get("session_id", ""))},
		"app_version": {"stringValue": str(payload.get("app_version", ""))},
		"platform": {"stringValue": str(payload.get("platform", ""))},
		"locale": {"stringValue": str(payload.get("locale", ""))},
		"properties": {"mapValue": {"fields": property_fields}},
	}
	if payload.has("run_id"):
		fields["run_id"] = {"stringValue": str(payload.get("run_id", ""))}
	return {"fields": fields}


func _firestore_value(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_BOOL:
			return {"booleanValue": bool(value)}
		TYPE_INT:
			return {"integerValue": str(int(value))}
		_:
			return {"stringValue": str(value)}


func _sanitize_properties(event_name: String, properties: Dictionary) -> Dictionary:
	if not EVENT_PROPERTY_KEYS.has(event_name):
		return {"ok": false}
	var allowed: Array = EVENT_PROPERTY_KEYS[event_name] as Array
	if properties.size() > allowed.size():
		return {"ok": false}
	var result: Dictionary = {}
	for raw_key in properties.keys():
		if typeof(raw_key) != TYPE_STRING:
			return {"ok": false}
		var key: String = str(raw_key)
		if key not in allowed:
			return {"ok": false}
		var checked: Dictionary = _sanitize_property_value(key, properties.get(raw_key))
		if not bool(checked.get("ok", false)):
			return {"ok": false}
		result[key] = checked.get("value")
	for required_key in REQUIRED_EVENT_PROPERTY_KEYS.get(event_name, []):
		if not result.has(required_key):
			return {"ok": false}
	if event_name == "retention_checkpoint" and result.has("day") \
			and int(result.get("day")) not in [1, 7, 30]:
		return {"ok": false}
	return {"ok": true, "properties": result}


func _sanitize_property_value(key: String, value: Variant) -> Dictionary:
	if key == "cohort_version":
		if typeof(value) != TYPE_STRING:
			return {"ok": false}
		var version: String = str(value)
		return {"ok": _is_safe_version(version), "value": version}
	if key == "cohort_day":
		if typeof(value) != TYPE_STRING:
			return {"ok": false}
		var day: String = str(value)
		return {"ok": _is_safe_client_day(day), "value": day}
	if STRING_PROPERTY_VALUES.has(key):
		if typeof(value) != TYPE_STRING or str(value) not in STRING_PROPERTY_VALUES[key]:
			return {"ok": false}
		return {"ok": true, "value": str(value)}
	if INTEGER_PROPERTY_RANGES.has(key):
		var integer: Dictionary = _coerce_integer(value)
		if not bool(integer.get("ok", false)):
			return {"ok": false}
		var range_values: Array = INTEGER_PROPERTY_RANGES[key] as Array
		var number: int = int(integer.get("value", 0))
		if number < int(range_values[0]) or number > int(range_values[1]):
			return {"ok": false}
		return {"ok": true, "value": number}
	return {"ok": false}


func _coerce_integer(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return {"ok": true, "value": int(value)}
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)) \
			and float(value) == floorf(float(value)):
		return {"ok": true, "value": int(value)}
	return {"ok": false}


func _persist_if_needed() -> Error:
	if _test_fail_next_save:
		_test_fail_next_save = false
		return ERR_FILE_CANT_WRITE
	if _test_mode and not _test_write_disk:
		return OK
	return _save_state()


func _save_state() -> Error:
	if _pending.is_empty():
		_discard_file(TEMP_SAVE_PATH)
		_discard_file(SAVE_PATH)
		return OK
	var encoded: String = JSON.stringify({
		"schema": SCHEMA_VERSION,
		"nonce": _queue_nonce,
		"next_sequence": _next_sequence,
		"pending": _pending,
	})
	var output: FileAccess = FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if output == null:
		return FileAccess.get_open_error()
	if not output.store_string(encoded):
		var store_error: Error = output.get_error()
		output.close()
		return store_error if store_error != OK else ERR_FILE_CANT_WRITE
	output.flush()
	var flush_error: Error = output.get_error()
	output.close()
	if flush_error != OK:
		return flush_error
	var written: String = FileAccess.get_file_as_string(TEMP_SAVE_PATH)
	var read_error: Error = FileAccess.get_open_error()
	if read_error != OK or written != encoded \
			or typeof(JSON.parse_string(written)) != TYPE_DICTIONARY:
		return read_error if read_error != OK else ERR_FILE_CORRUPT
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_SAVE_PATH),
		ProjectSettings.globalize_path(SAVE_PATH))


func _load_state() -> void:
	_pending.clear()
	_queue_nonce = ""
	_next_sequence = 0
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or not _apply_loaded_state(parsed as Dictionary):
		clear_pending()


func _apply_loaded_state(state: Dictionary) -> bool:
	if int(state.get("schema", 0)) != SCHEMA_VERSION:
		return false
	var nonce: String = str(state.get("nonce", ""))
	if not _is_lower_hex(nonce, 32) or typeof(state.get("pending")) != TYPE_ARRAY:
		return false
	var now_unix: int = _now_unix()
	var restored: Array = []
	var seen_ids: Dictionary = {}
	var invalidated_runs: Dictionary = {}
	var highest_sequence: int = -1
	for candidate in state.get("pending", []):
		var possible_start_id: String = _recognized_pending_run_start_id(candidate)
		var restored_item: Dictionary = _restore_loaded_item(
			candidate, nonce, now_unix, seen_ids)
		if restored_item.is_empty():
			if not possible_start_id.is_empty():
				invalidated_runs[possible_start_id] = true
			continue
		var document_id: String = str(restored_item.get("id", ""))
		var sequence: int = int(restored_item.get("sequence", -1))
		restored.append(restored_item)
		seen_ids[document_id] = true
		highest_sequence = maxi(highest_sequence, sequence)
	# No start in the raw queue may be a healthy run the server already acked.
	# Conversely, only IDs whose real raw start was seen but not recovered drop
	# the whole run together.
	_discard_run_scoped_items(restored, invalidated_runs)
	restored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("sequence", 0)) < int(b.get("sequence", 0)))
	while restored.size() > MAX_PENDING:
		# A healthy saver never exceeds 200. If a corrupt/old file has only
		# protected starts left and no safe victim, refuse rather than loop
		# forever or create orphans.
		if not _remove_lowest_value_event(restored):
			return false
	_remember_invalidated_pending_runs(invalidated_runs)
	_pending = restored
	if _pending.is_empty():
		_queue_nonce = ""
		_next_sequence = 0
		_discard_file(SAVE_PATH)
		return true
	_queue_nonce = nonce
	var saved_next: Dictionary = _coerce_integer(state.get("next_sequence", 0))
	_next_sequence = maxi(
		int(saved_next.get("value", 0)) if bool(saved_next.get("ok", false)) else 0,
		highest_sequence + 1)
	_persist_if_needed()
	return true


func _restore_loaded_item(candidate: Variant, nonce: String,
		now_unix: int, seen_ids: Dictionary) -> Dictionary:
	if typeof(candidate) != TYPE_DICTIONARY:
		return {}
	var item: Dictionary = candidate as Dictionary
	var sequence_value: Dictionary = _coerce_integer(item.get("sequence", -1))
	var queued_value: Dictionary = _coerce_integer(item.get("queued_at_unix", -1))
	if not bool(sequence_value.get("ok", false)) \
			or not bool(queued_value.get("ok", false)):
		return {}
	var sequence: int = int(sequence_value.get("value", -1))
	var queued_at: int = int(queued_value.get("value", -1))
	if sequence < 0 or queued_at < 0 or queued_at > now_unix + 600 \
			or now_unix - queued_at > MAX_LOCAL_AGE_SECONDS:
		return {}
	var document_id: String = str(item.get("id", ""))
	if document_id != _event_document_id(nonce, sequence) \
			or seen_ids.has(document_id):
		return {}
	var payload: Variant = item.get("event", null)
	if typeof(payload) != TYPE_DICTIONARY \
			or not _valid_loaded_payload(payload as Dictionary):
		return {}
	var restored_payload: Dictionary = (payload as Dictionary).duplicate(true)
	if int(restored_payload.get("client_at_unix", -1)) != queued_at:
		return {}
	var sanitized: Dictionary = _sanitize_properties(
		str(restored_payload.get("event", "")),
		restored_payload.get("properties", {}) as Dictionary)
	restored_payload["client_at_unix"] = queued_at
	restored_payload["expires_at_unix"] = queued_at + SERVER_TTL_SECONDS
	restored_payload["properties"] = sanitized.get("properties", {})
	return {
		"id": document_id,
		"sequence": sequence,
		"queued_at_unix": queued_at,
		"event": restored_payload,
	}


func _valid_loaded_payload(payload: Dictionary) -> bool:
	if int(payload.get("schema", 0)) != SCHEMA_VERSION:
		return false
	var event_name: String = str(payload.get("event", ""))
	if not EVENT_PROPERTY_KEYS.has(event_name):
		return false
	if not _is_lower_hex(str(payload.get("session_id", "")), 32):
		return false
	if payload.has("run_id") and not _is_lower_hex(str(payload.get("run_id", "")), 32):
		return false
	if not _is_safe_version(str(payload.get("app_version", ""))) \
			or str(payload.get("platform", "")) not in [
				"android", "ios", "macos", "windows", "linux", "web", "other",
			] \
			or str(payload.get("locale", "")) not in ["ko", "en", "ja", "zh_CN", "zh_TW"]:
		return false
	var at_value: Dictionary = _coerce_integer(payload.get("client_at_unix", -1))
	var expiry_value: Dictionary = _coerce_integer(payload.get("expires_at_unix", -1))
	if not bool(at_value.get("ok", false)) or not bool(expiry_value.get("ok", false)):
		return false
	var client_at: int = int(at_value.get("value", -1))
	var expires_at: int = int(expiry_value.get("value", -1))
	if client_at < 0 or expires_at != client_at + SERVER_TTL_SECONDS \
			or str(payload.get("client_day", "")) != _day_string(client_at):
		return false
	var properties: Variant = payload.get("properties", null)
	if typeof(properties) != TYPE_DICTIONARY:
		return false
	return bool(_sanitize_properties(event_name, properties as Dictionary).get("ok", false))


func _random_token() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	if bytes.size() == 16:
		return bytes.hex_encode()
	return ("%s:%s:%s" % [
		Time.get_ticks_usec(), Time.get_unix_time_from_system(), get_instance_id(),
	]).sha256_text().substr(0, 32)


func _event_document_id(nonce: String, sequence: int) -> String:
	return "e_" + (nonce + ":" + str(sequence)).sha256_text().substr(0, 40)


func _is_document_id(value: String) -> bool:
	return value.begins_with("e_") and _is_lower_hex(value.substr(2), 40)


func _is_lower_hex(value: String, expected_length: int) -> bool:
	if value.length() != expected_length:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _is_safe_version(value: String) -> bool:
	if value.is_empty() or value.length() > 32:
		return false
	for character in value:
		if character not in "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.+-":
			return false
	return true


func _now_unix() -> int:
	return _test_now_unix if _test_now_unix >= 0 \
		else int(Time.get_unix_time_from_system())


func _day_string(unix_time: int) -> String:
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d" % [
		int(date.get("year", 1970)),
		int(date.get("month", 1)),
		int(date.get("day", 1)),
	]


func _is_safe_client_day(value: String) -> bool:
	if value.length() != 10 or value[4] != "-" or value[7] != "-":
		return false
	var unix_time: int = Time.get_unix_time_from_datetime_string(
		value + "T00:00:00Z")
	return unix_time >= 0 and _day_string(unix_time) == value


func _timestamp_string(unix_time: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix_time) + "Z"


func _app_version() -> String:
	var version: String = str(ProjectSettings.get_setting(
		"application/config/version", "0.0.0"))
	return version if _is_safe_version(version) else "0.0.0"


func _platform() -> String:
	match OS.get_name().to_lower():
		"android":
			return "android"
		"ios":
			return "ios"
		"macos":
			return "macos"
		"windows":
			return "windows"
		"linux", "freebsd", "netbsd", "openbsd", "bsd":
			return "linux"
		"web":
			return "web"
		_:
			return "other"


func _locale() -> String:
	var value: String = TranslationServer.get_locale().replace("-", "_")
	if value.begins_with("zh"):
		var upper: String = value.to_upper()
		return "zh_TW" if "HANT" in upper or "_TW" in upper \
			or "_HK" in upper or "_MO" in upper else "zh_CN"
	var language: String = value.get_slice("_", 0).to_lower()
	return language if language in ["ko", "en", "ja"] else "en"


func _discard_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## ---- network-free regression-test helpers ----

func _test_configure(consent_granted: bool, config_enabled: bool = true,
		write_disk: bool = false) -> void:
	_test_mode = true
	_test_consent = consent_granted
	_test_configured = config_enabled
	_test_write_disk = write_disk
	_consent_granted = consent_granted
	_config = {
		"analytics_enabled": config_enabled,
		"analytics_ingestion_hardened": config_enabled,
		"analytics_allow_debug": true,
		"web_api_key": "test-key" if config_enabled else "",
	}
	_session_id = "1".repeat(32)
	_queue_nonce = ""
	_next_sequence = 0
	_pending.clear()
	_invalidated_pending_run_ids.clear()
	_in_flight_id = ""
	_retry_seconds = INITIAL_RETRY_SECONDS
	_next_attempt_msec = 0
	_cold_launch_recorded = false
	_test_fail_next_save = false
	_test_fail_next_metadata_save = false
	_test_cohort_unix = 0
	_test_cohort_version = ""
	_test_retention_mask = 0


func _test_set_now(unix_time: int) -> void:
	_test_now_unix = unix_time


func _test_fail_next_metadata_persist() -> void:
	_test_fail_next_metadata_save = true


func _test_set_consent(granted: bool) -> void:
	_test_consent = granted


func _test_set_cohort(unix_time: int, version: String, retention_mask: int) -> void:
	_test_cohort_unix = unix_time
	_test_cohort_version = version
	_test_retention_mask = retention_mask


func _test_cohort() -> Dictionary:
	return _cohort_metadata().duplicate(true)


func _test_fail_next_persist() -> void:
	_test_fail_next_save = true


func _test_set_nonce(value: String) -> bool:
	if not _is_lower_hex(value, 32):
		return false
	_queue_nonce = value
	_next_sequence = 0
	return true


func _test_pending_items() -> Array:
	return _pending.duplicate(true)


func _test_next_attempt_msec() -> int:
	return _next_attempt_msec


func _test_request() -> Dictionary:
	return _request_for_head().duplicate(true)


func _test_receive(response_code: int) -> void:
	if _pending.is_empty():
		return
	_in_flight_id = str((_pending[0] as Dictionary).get("id", ""))
	_on_request_completed(0, response_code, PackedStringArray(), PackedByteArray())


func _test_apply_state(state: Dictionary) -> bool:
	return _apply_loaded_state(state.duplicate(true))


func _test_state() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"nonce": _queue_nonce,
		"next_sequence": _next_sequence,
		"pending": _pending.duplicate(true),
	}


func _test_document_id(nonce: String, sequence: int) -> String:
	return _event_document_id(nonce, sequence)
