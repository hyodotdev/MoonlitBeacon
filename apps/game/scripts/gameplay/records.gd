extends Node

## High scores. The only thing that survives across scenes.
##
## Chapter 9 reset the whole run with `reload_current_scene()`.
## The note then was "what must survive a scene change is Chapter 14." This is it.
##
## It is an autoload, so it lives through scene changes.

const SAVE_PATH: String = "user://records.cfg"
const TEMP_SAVE_PATH: String = "user://records.cfg.tmp"
const SECTION: String = "best"

enum SubmitResult {
	NOT_BEST,
	SAVED,
	SAVE_FAILED,
}

var best_score: int = 0
var best_rank: String = "-"
var best_version: String = ""


func _ready() -> void:
	load_records()


## If higher, replace and return true. The result panel shows "new record".
func submit(score: int, rank: String) -> bool:
	return submit_result(score, rank) == SubmitResult.SAVED


## Distinguishes "not a new record" from a save failure. The result screen must
## not treat an unsaved score as a new record or consume it as success.
func submit_result(score: int, rank: String) -> SubmitResult:
	var previous_score: int = best_score
	var previous_rank: String = best_rank
	var previous_version: String = best_version
	_ensure_current_version()
	if score <= best_score:
		return SubmitResult.NOT_BEST
	best_score = score
	best_rank = rank
	if save_records() != OK:
		best_score = previous_score
		best_rank = previous_rank
		best_version = previous_version
		return SubmitResult.SAVE_FAILED
	return SubmitResult.SAVED


func load_records() -> void:
	best_score = 0
	best_rank = "-"
	best_version = Ladder.current_version()
	var cfg: ConfigFile = ConfigFile.new()
	# First launch has no file. That is normal, not an error.
	if cfg.load(SAVE_PATH) != OK:
		return
	var saved_version: String = str(cfg.get_value(
		SECTION, "version", Ladder.LEGACY_VERSION))
	if saved_version != best_version:
		return
	best_score = int(cfg.get_value(SECTION, "score", 0))
	best_rank = str(cfg.get_value(SECTION, "rank", "-"))


func save_records() -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "score", best_score)
	cfg.set_value(SECTION, "rank", best_rank)
	cfg.set_value(SECTION, "version", best_version)
	# Write a temp file in the same folder, then replace, so a half-written
	# file never overwrites the old record. `user://` is the per-device app folder.
	var error: Error = cfg.save(TEMP_SAVE_PATH)
	if error != OK:
		_discard_temp_file()
		return error
	var verification: ConfigFile = ConfigFile.new()
	error = verification.load(TEMP_SAVE_PATH)
	if error != OK:
		_discard_temp_file()
		return error
	error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_SAVE_PATH),
		ProjectSettings.globalize_path(SAVE_PATH))
	if error != OK:
		_discard_temp_file()
	return error


func _discard_temp_file() -> void:
	# Failure-injection tests may occupy the same path as a directory. Delete
	# only a regular temp file we created; do not touch an external directory.
	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))


func _ensure_current_version() -> void:
	var current: String = Ladder.current_version()
	if best_version == current:
		return
	best_version = current
	best_score = 0
	best_rank = "-"
