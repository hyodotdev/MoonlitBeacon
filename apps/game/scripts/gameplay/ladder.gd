extends Node

## Leaderboard. The arcade high-score thing.
##
## **Local first.** A global board is nice, but the game must run without it.
## No network or no API key and it quietly uses local only — no freeze or
## error on the result screen. Playing in airplane mode must not stop the game
## because of a leaderboard.
##
## Characters are stored with the score. There are three now and there will be
## more, and **who scored it on which character** is half the board. Per-
## character boards come from here later too.

## How many records to keep locally. Ten lines do not fit 808×360, but top
## five plus your own row is enough.
const KEEP: int = 10
const SAVE_PATH: String = "user://ladder.json"
const TEMP_SAVE_PATH: String = "user://ladder.json.tmp"
## From 1.0.1 records store a version. Local records made before that migrate
## as 1.0.0, the first shipping version, so they can be told apart from new
## balance records without deleting them.
const LEGACY_VERSION: String = "1.0.0"

## Name length cap.
##
## Arcades were three letters (AAA). Touch has no such limit, but **it must
## fit one leaderboard row.** Hangul is wide; eight characters already eat the
## screen.
const NAME_MAX: int = 8

## This value is required to upload to Firestore.
##
## **Not baked into the repo.** Google assumes web API keys are public, but a
## key still lets someone burn quota for fun. Empty means local only. When
## attaching one, read it from an export-preset env var or a separate config.
const PROJECT_ID: String = "moonlitbeacon-778ee"

var entries: Array = []
## Last name used. Make people type every time and they skip submit on run two.
var last_name: String = ""
## `(run_id, score)` already accepted this app launch, plus the first submitted row.
## run_id is not written to local JSON or global requests. A continue that
## actually raises the score becomes a different key so a new final result can
## be submitted once more.
var _submitted_results: Dictionary = {}


func _ready() -> void:
	load_ladder()


## Whether this score makes the board. Used when the result screen decides whether to ask for a name.
func makes_board(score: int) -> bool:
	if entries.size() < KEEP:
		return true
	var cutoff: Dictionary = entries[entries.size() - 1]
	var version_order: int = _compare_versions(
		current_version(), str(cutoff.get("version", LEGACY_VERSION)))
	if version_order != 0:
		return version_order > 0
	# Before submit there is no name or cycle count, so do not borrow the
	# tie-break sort. Same version keeps the old contract: only a strictly
	# higher score than the cutoff asks for a name.
	return score > int(cutoff.get("score", 0))


## Record a score. Returns the 0-based place, or -1 if it did not make the board.
func submit(player: String, hero_id: String, score: int, rank_letter: String,
		cycles: int, run_id: String = "") -> int:
	var clean: String = _sanitize(player)
	var submission_key: String = _submission_key(run_id, score)
	if not submission_key.is_empty() and _submitted_results.has(submission_key):
		return _placement_of(_submitted_results[submission_key] as Dictionary)
	var previous_last_name: String = last_name
	var previous_entries: Array = entries.duplicate(true)
	last_name = clean

	var row: Dictionary = {
		"name": clean,
		"hero": hero_id,
		"score": score,
		"rank": rank_letter,
		"cycles": cycles,
		"version": current_version(),
	}
	entries.append(row)
	_sort_entries(entries)
	if entries.size() > KEEP:
		entries.resize(KEEP)
	var placement: int = _placement_of(row)
	if save_ladder() != OK:
		# Do not treat an unsaved row as success this run or lock it with
		# dedupe. Roll memory back too, then retry after the path is restored.
		last_name = previous_last_name
		entries = previous_entries
		return -1
	if not submission_key.is_empty():
		_submitted_results[submission_key] = row.duplicate()
	return placement


## Even in the same run, a higher score after continue is a new final result.
## The key includes score so that result is allowed once, and only repeat taps
## of the same score are blocked.
func _submission_key(run_id: String, score: int) -> String:
	var clean_run_id: String = run_id.strip_edges()
	return "" if clean_run_id.is_empty() else "%s:%d" % [clean_run_id, score]


func _placement_of(wanted: Dictionary) -> int:
	var placed: int = -1
	for i in entries.size():
		var row: Dictionary = entries[i]
		if int(row.get("score", 0)) == int(wanted.get("score", 0)) \
				and str(row.get("name", "")) == str(wanted.get("name", "")) \
				and str(row.get("hero", "")) == str(wanted.get("hero", "")) \
				and str(row.get("rank", "")) == str(wanted.get("rank", "")) \
				and int(row.get("cycles", 0)) == int(wanted.get("cycles", 0)) \
				and str(row.get("version", LEGACY_VERSION)) \
					== str(wanted.get("version", LEGACY_VERSION)):
			placed = i
			break
	return placed


## Clean a name.
##
## The board is **a place other people see.** Block empty names and edge
## whitespace, and trim length. Profanity filter is not here — a list is
## quickly bypassed, and doing it right needs a server. Handle that when
## global ranks actually turn on.
func _sanitize(player: String) -> String:
	var clean: String = player.strip_edges()
	if clean.is_empty():
		return tr("LADDER_ANON")
	if clean.length() > NAME_MAX:
		clean = clean.substr(0, NAME_MAX)
	return clean


func load_ladder() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return                                   # corrupt: quietly go to an empty board
	last_name = str(parsed.get("last_name", ""))
	var rows: Variant = parsed.get("entries", [])
	if typeof(rows) == TYPE_ARRAY:
		entries = []
		for value in rows:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = (value as Dictionary).duplicate()
			if str(row.get("version", "")).is_empty():
				row["version"] = LEGACY_VERSION
			if not row.has("hero"):
				row["hero"] = ""
			entries.append(row)
		_sort_entries(entries)
		if entries.size() > KEEP:
			entries.resize(KEEP)


## Currently running app version. Score save and title use the same ProjectSettings value.
func current_version() -> String:
	var value: String = str(ProjectSettings.get_setting(
		"application/config/version", LEGACY_VERSION)).strip_edges()
	return LEGACY_VERSION if value.is_empty() else value.trim_prefix("v")


## Sort the global board with the same rule just before drawing.
func sorted_copy(rows: Array) -> Array:
	var result: Array = []
	for value in rows:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = (value as Dictionary).duplicate()
		if str(row.get("version", "")).is_empty():
			row["version"] = LEGACY_VERSION
		if not row.has("hero"):
			row["hero"] = ""
		result.append(row)
	_sort_entries(result)
	return result


func _sort_entries(rows: Array) -> void:
	rows.sort_custom(_entry_before)


## Newest version first; same version, score first. If score ties, more closed
## cycles then name freeze the order so a reload does not shuffle rows.
func _entry_before(a: Dictionary, b: Dictionary) -> bool:
	var version_order: int = _compare_versions(
		str(a.get("version", LEGACY_VERSION)),
		str(b.get("version", LEGACY_VERSION)))
	if version_order != 0:
		return version_order > 0
	var a_score: int = int(a.get("score", 0))
	var b_score: int = int(b.get("score", 0))
	if a_score != b_score:
		return a_score > b_score
	var a_cycles: int = int(a.get("cycles", 0))
	var b_cycles: int = int(b.get("cycles", 0))
	if a_cycles != b_cycles:
		return a_cycles > b_cycles
	return str(a.get("name", "")) < str(b.get("name", ""))


## Compare numeric parts in order. 1.10.0 must be newer than 1.9.9, so no
## string compare. Same numbers put a release before a prerelease.
func _compare_versions(a: String, b: String) -> int:
	var a_clean: String = a.trim_prefix("v").split("+", false, 1)[0]
	var b_clean: String = b.trim_prefix("v").split("+", false, 1)[0]
	var a_main: String = a_clean.split("-", false, 1)[0]
	var b_main: String = b_clean.split("-", false, 1)[0]
	var a_parts: PackedStringArray = a_main.split(".")
	var b_parts: PackedStringArray = b_main.split(".")
	for i in maxi(a_parts.size(), b_parts.size()):
		var a_number: int = int(a_parts[i]) if i < a_parts.size() \
				and a_parts[i].is_valid_int() else 0
		var b_number: int = int(b_parts[i]) if i < b_parts.size() \
				and b_parts[i].is_valid_int() else 0
		if a_number != b_number:
			return 1 if a_number > b_number else -1
	var a_prerelease: bool = a_clean.contains("-")
	var b_prerelease: bool = b_clean.contains("-")
	if a_prerelease != b_prerelease:
		return -1 if a_prerelease else 1
	return 0


## JSON, not ConfigFile.
##
## The repo has used ConfigFile until now (`records.cfg`, `settings.cfg`,
## `vault.cfg`). This one is different because it stores **dictionaries in an
## array**. Ten rows in ConfigFile would mean keys like `row_0_name`, and then
## the reader has to know the table's shape.
func save_ladder() -> Error:
	var payload: Dictionary = {
		"last_name": last_name,
		"entries": entries,
	}
	var file: FileAccess = FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		_discard_ladder_temp_file()
		return error
	var verification: FileAccess = FileAccess.open(TEMP_SAVE_PATH, FileAccess.READ)
	if verification == null:
		error = FileAccess.get_open_error()
		_discard_ladder_temp_file()
		return error
	var parsed: Variant = JSON.parse_string(verification.get_as_text())
	verification.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_discard_ladder_temp_file()
		return ERR_FILE_CORRUPT
	error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_SAVE_PATH),
		ProjectSettings.globalize_path(SAVE_PATH))
	if error != OK:
		_discard_ladder_temp_file()
	return error


func _discard_ladder_temp_file() -> void:
	# Failure-injection tests may occupy the same path as a directory. Delete only
	# a regular temp file we created; do not touch an external directory.
	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
