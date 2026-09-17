extends Node

## Global leaderboard — Firestore REST client.
##
## Autoload is named `GlobalLadder` because first it was `Sky` and **it
## collided with Godot's built-in `Sky` (skybox resource)** so signals and
## functions could not be found. Autoload names are global identifiers and
## must not overlap engine classes.
##
## Godot has no Firebase SDK. **Call REST directly.** Less to attach, and
## on failure it can quietly fall back to local.
##
## `Ladder` owns the local top 10; this owns global. They are split because
## **the game must run without global.** No network or no key and this
## autoload does nothing; the board panel still shows the local table.
## Playing in airplane mode must not stop the game because of a leaderboard.

## Global board arrived. If it cannot, this signal never fires.
signal board_arrived(rows: Array)
## Upload finished. Success is passed with it.
signal upload_done(ok: bool)

const PROJECT_ID: String = "moonlitbeacon-778ee"
const COLLECTION: String = "scores"

## File that holds the web API key. **Not in the repo.**
##
## Google assumes the key itself is public (an APK can be unpacked anyway),
## but baking it into the repo lets a fork burn someone else's quota.
## No file and global is off entirely — that is the default.
##
## How to make it is in the leaderboard section of `apps/docs/docs/rebuild.md`.
const KEY_PATH: String = "res://firebase.cfg"

## How many rows to fetch from the global board.
const FETCH_LIMIT: int = 20

## Give up if it takes longer. **Do not make people wait on the result screen.**
const TIMEOUT: float = 6.0
const MSEC_PER_SECOND: float = 1000.0

var _key: String = ""
var _http: HTTPRequest = null
## What is in flight. When a response arrives we must know which.
var _doing: String = ""
## Latest-version board and all-time high board are separate queries. Merge
## by document ID so a low latest-version score is not crowded out of the
## overall top 20.
var _latest_rows: Array = []
var _latest_ok: bool = false
var _score_rows: Array = []
var _score_ok: bool = false
## Shared deadline set when the first request starts, so two sequential queries do not each spend 6s.
var _fetch_deadline_msec: int = 0
## `(run_id, score)` of an HTTP request that actually started. Run ID is not
## in the request body; the client uses it only to filter repeat submits.
var _submitted_results: Dictionary = {}


func _ready() -> void:
	_key = _read_key()
	if _key.is_empty():
		return                                   # no key. stay quietly off

	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT
	_http.request_completed.connect(_on_response)
	add_child(_http)


## Whether global is available. The board panel asks.
func available() -> bool:
	return _http != null


## Upload a record. Failure does not affect the game.
func submit(player: String, hero_id: String, score: int, rank_letter: String,
		cycles: int, run_id: String = "") -> void:
	if not available() or _doing != "":
		return
	if not _claim_submission(run_id, score):
		return
	_doing = "submit"

	if not _send("documents/%s" % COLLECTION,
			_submission_body(player, hero_id, score, rank_letter, cycles)):
		_release_submission(run_id, score)
		_finish(false, [])


## Take the key the instant a request starts. Keeping one attempt is a more
## accurate submit boundary than resending a lost response and creating two
## Firestore documents. Release the key only if `_send()` itself never started.
func _claim_submission(run_id: String, score: int) -> bool:
	var key: String = _submission_key(run_id, score)
	if key.is_empty():
		return true
	if _submitted_results.has(key):
		return false
	_submitted_results[key] = true
	return true


func _release_submission(run_id: String, score: int) -> void:
	var key: String = _submission_key(run_id, score)
	if not key.is_empty():
		_submitted_results.erase(key)


func _submission_key(run_id: String, score: int) -> String:
	var clean_run_id: String = run_id.strip_edges()
	return "" if clean_run_id.is_empty() else "%s:%d" % [clean_run_id, score]


## Global submit carries the same hero, version, and score as the local record.
## The request body is built separately so this contract can be tested without a network.
func _submission_body(player: String, hero_id: String, score: int,
		rank_letter: String, cycles: int) -> Dictionary:
	# Firestore names a type per value. Numbers are sent **as strings** —
	# a spec that avoids JSON integer-range differences across languages.
	return {
		"fields": {
			"name": {"stringValue": player},
			"hero": {"stringValue": hero_id},
			"score": {"integerValue": str(score)},
			"rank": {"stringValue": rank_letter},
			"cycles": {"integerValue": str(cycles)},
			"version": {"stringValue": Ladder.current_version()},
			"at": {"timestampValue": Time.get_datetime_string_from_system(true) + "Z"},
		}
	}


## Fetch top records.
func fetch_board() -> void:
	if not available() or _doing != "":
		return
	_latest_rows = []
	_latest_ok = false
	_score_rows = []
	_score_ok = false
	_fetch_deadline_msec = _deadline_after(Time.get_ticks_msec(), TIMEOUT)
	_doing = "fetch_latest"

	if not _send_fetch("documents:runQuery", _latest_query_body()):
		_finish_fetch()


## Latest version fetches that version's top 20 from the server, separate from
## the overall score top 20. The `version + score` composite index is the
## `firestore.indexes.json` contract in the repo.
func _latest_query_body() -> Dictionary:
	return {
		"structuredQuery": {
			"from": [{"collectionId": COLLECTION}],
			"where": {
				"fieldFilter": {
					"field": {"fieldPath": "version"},
					"op": "EQUAL",
					"value": {"stringValue": Ladder.current_version()},
				}
			},
			"orderBy": [{
				"field": {"fieldPath": "score"},
				"direction": "DESCENDING",
			}],
			"limit": FETCH_LIMIT,
		}
	}


## Old versions and records with no version field still fetch overall score
## top 20, same as the prior contract. Documents that also hit the latest-
## version query stay once when merging.
func _score_query_body() -> Dictionary:
	return {
		"structuredQuery": {
			"from": [{"collectionId": COLLECTION}],
			"orderBy": [{
				"field": {"fieldPath": "score"},
				"direction": "DESCENDING",
			}],
			"limit": FETCH_LIMIT,
		}
	}


func _start_score_fetch() -> void:
	_doing = "fetch_score"
	if not _send_fetch("documents:runQuery", _score_query_body()):
		_finish_fetch()


## The two queries share one 6s budget started on the first. If the first
## response took 4.5s, the second HTTPRequest.timeout gets about 1.5s left.
func _send_fetch(path: String, body: Dictionary) -> bool:
	var remaining: float = _remaining_seconds(
		_fetch_deadline_msec, Time.get_ticks_msec())
	if remaining <= 0.0:
		return false
	return _send(path, body, remaining)


func _send(path: String, body: Dictionary, timeout_seconds: float = TIMEOUT) -> bool:
	var url: String = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/%s?key=%s" \
		% [PROJECT_ID, path, _key]
	_http.timeout = timeout_seconds
	var error: int = _http.request(url, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(body))
	return error == OK


## Split time math from the network so boundary values can be regression-tested.
func _deadline_after(start_msec: int, duration_seconds: float) -> int:
	return start_msec + ceili(duration_seconds * MSEC_PER_SECOND)


func _remaining_seconds(deadline_msec: int, now_msec: int) -> float:
	return maxf(float(deadline_msec - now_msec) / MSEC_PER_SECOND, 0.0)


func _on_response(_result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	var was: String = _doing
	if was == "submit":
		_finish(code >= 200 and code < 300, [])
		return

	var ok: bool = code >= 200 and code < 300
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if ok else null
	if typeof(parsed) != TYPE_ARRAY:
		ok = false
	var rows: Array = _parse_query_rows(parsed) if ok else []
	if was == "fetch_latest":
		_latest_ok = ok
		_latest_rows = rows
		# If the latest board fails, do not show overall highs only. That would
		# make a prior-version high look like the latest board and revive the
		# original miss. If the latest 20 is already full, version-first sort
		# is already decided, so the second query is not needed.
		if not _should_fetch_score(ok, rows.size()):
			_finish_fetch()
			return
		_start_score_fetch()
		return
	if was == "fetch_score":
		_score_ok = ok
		_score_rows = rows
		_finish_fetch()


func _should_fetch_score(latest_ok: bool, latest_count: int) -> bool:
	return latest_ok and latest_count < FETCH_LIMIT


func _parse_query_rows(parsed: Variant) -> Array:
	# `runQuery` is one line per document; no results is one line with no
	# `document` key. Walk the array and keep only what is there.
	var rows: Array = []
	for entry in parsed:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("document"):
			continue
		var fields: Dictionary = entry["document"].get("fields", {})
		rows.append({
			"_document": str(entry["document"].get("name", "")),
			"name": _text(fields, "name"),
			"hero": _text(fields, "hero"),
			"rank": _text(fields, "rank"),
			"score": _number(fields, "score"),
			"cycles": _number(fields, "cycles"),
			"version": _text(fields, "version"),
		})
	return rows


func _finish_fetch() -> void:
	var outcome: Dictionary = _fetch_outcome(
		_latest_ok, _latest_rows, _score_ok, _score_rows)
	_finish(bool(outcome.get("ok", false)), outcome.get("rows", []))


## Only the latest-version query is the trust baseline for the remote board.
## A past-score query fills empty slots on success; on failure the latest
## board is still usable. Latest-query failure falls back to local.
func _fetch_outcome(latest_ok: bool, latest: Array,
		score_ok: bool, by_score: Array) -> Dictionary:
	if not latest_ok:
		return {"ok": false, "rows": []}
	return {
		"ok": true,
		"rows": _merge_fetch_rows(latest, by_score if score_ok else []),
	}


## The same Firestore document in both queries stays once. Test/legacy rows
## with no document name use content as the id. Internal document names are
## not exported to UI.
func _merge_fetch_rows(latest: Array, by_score: Array) -> Array:
	var merged: Array = []
	var seen: Dictionary = {}
	for source in [latest, by_score]:
		for value in source:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = (value as Dictionary).duplicate()
			var identity: String = _row_identity(row)
			if seen.has(identity):
				continue
			seen[identity] = true
			row.erase("_document")
			merged.append(row)
	var result: Array = Ladder.sorted_copy(merged)
	if result.size() > FETCH_LIMIT:
		result.resize(FETCH_LIMIT)
	return result


func _row_identity(row: Dictionary) -> String:
	var document: String = str(row.get("_document", ""))
	if not document.is_empty():
		return "document:" + document
	return "row:" + JSON.stringify([
		row.get("name", ""),
		row.get("hero", ""),
		row.get("rank", ""),
		row.get("score", 0),
		row.get("cycles", 0),
		row.get("version", ""),
	])


func _finish(ok: bool, rows: Array) -> void:
	var was: String = _doing
	_doing = ""
	if was.begins_with("fetch_"):
		_fetch_deadline_msec = 0
	if was == "submit":
		upload_done.emit(ok)
	elif ok:
		board_arrived.emit(rows)


func _text(fields: Dictionary, key: String) -> String:
	return str(fields.get(key, {}).get("stringValue", ""))


func _number(fields: Dictionary, key: String) -> int:
	return int(str(fields.get(key, {}).get("integerValue", "0")))


## Read the key file. Missing is an empty string — that is the normal path.
func _read_key() -> String:
	if not FileAccess.file_exists(KEY_PATH):
		return ""
	var file: ConfigFile = ConfigFile.new()
	if file.load(KEY_PATH) != OK:
		return ""
	return str(file.get_value("firebase", "web_api_key", ""))
