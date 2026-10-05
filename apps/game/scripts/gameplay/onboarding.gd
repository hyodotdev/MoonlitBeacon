class_name Onboarding
extends RefCounted

## What the player has already learned, kept apart from purchases.
##
## Movement tips are taught once. Without a record of that, every fresh run
## repeats "touch anywhere to move" and every resume replays guidance the
## player already finished. This file remembers the learned keys so a
## relaunch or a new journey stays quiet about them.
##
## **Its own save file, on purpose.** The Vault holds paid entitlements and
## its schema must not churn for a teaching record; the journey holds run
## state and is replaced wholesale on a fresh start, which must not wipe
## what was learned. A missing or unreadable file is not an error: every tip
## simply shows again until it is learned.
##
## Static, with no autoload: the arena marks, nothing else reads. Writes
## happen only while `Journey.armed` is on, so tests, debug boards and
## capture harnesses never touch the human record.

const DEFAULT_PATH: String = "user://onboarding.json"
const SCHEMA_VERSION: int = 1

## Learned tip keys. `opening` is the first story strip; the rest match the
## `TUTORIAL_*` guidance moments.
const KEYS: Array[String] = [
	"opening", "move", "dash", "beacon", "auto", "heart", "core",
]

## Where to read and write. Tests point this at a temp file.
static var path: String = DEFAULT_PATH

static var _done: Dictionary = {}
static var _loaded: bool = false


## True when this tip was already learned on an earlier run.
static func is_done(key: String) -> bool:
	_ensure_loaded()
	return bool(_done.get(key, false))


## Record a learned tip and persist it. Unknown keys are refused.
static func mark_done(key: String) -> void:
	_ensure_loaded()
	if key not in KEYS or _done.get(key, false):
		return
	_done[key] = true
	_save()


## True when every guidance tip was learned. The story strip still plays.
static func all_tips_done() -> bool:
	_ensure_loaded()
	for key: String in KEYS:
		if key != "opening" and not bool(_done.get(key, false)):
			return false
	return true


## Forget the in-memory copy, so the next read comes from `path`. For tests.
static func forget_cache() -> void:
	_done = {}
	_loaded = false


# --- internals ----------------------------------------------------------------

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_done = {}
	if not FileAccess.file_exists(path):
		return
	# A half-written learning record is ordinary (the app was killed
	# mid-save). Parse quietly and start unlearned rather than reporting.
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return
	var data: Variant = parser.data
	if not data is Dictionary:
		return
	if int((data as Dictionary).get("schema_version", 0)) != SCHEMA_VERSION:
		return
	var done: Variant = (data as Dictionary).get("done", [])
	if not done is Array:
		return
	for key: Variant in done as Array:
		if key is String and (key as String) in KEYS:
			_done[key] = true


static func _save() -> void:
	# Only a human run may write the human record. Tests and capture either
	# disarm or point `path` at a temp file; both stay silent here.
	if not Journey.armed:
		return
	var learned: Array[String] = []
	for key: String in KEYS:
		if bool(_done.get(key, false)):
			learned.append(key)
	var text: String = JSON.stringify(
		{"schema_version": SCHEMA_VERSION, "done": learned})
	var temp: String = path + ".tmp"
	var handle: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if handle == null:
		push_warning("Onboarding: could not write %s" % temp)
		return
	handle.store_string(text)
	handle.flush()
	handle.close()
	var moved: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))
	if moved != OK:
		var direct: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if direct != null:
			direct.store_string(text)
			direct.flush()
			direct.close()
		if FileAccess.file_exists(temp):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
