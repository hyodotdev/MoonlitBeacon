class_name Chronicle
extends RefCounted

## What the player has met, kept where they can read it again.
##
## The story used to be said once and lost: a first-sight line about a night bat
## crossed the screen in a balloon and was gone, and the cycle dialogue played
## once per run. The chronicle keeps them. Each entry is *unlocked by being
## seen* — the game marks it at the moment it plays — and the title screen's
## Chronicle page lists all of them, the unmet ones as blanks.
##
## **Its own save file, on purpose.** Purchases, shards and hero unlocks live in
## the Vault, whose writes are verified and backed up because losing them costs
## money. A reading log is not worth that risk, and putting it there would mean
## a schema bump on a file with in-app purchases in it. A missing or unreadable
## chronicle is not an error: it just starts empty.
##
## Static, with no autoload: the arena marks, the page reads, and neither needs
## the other to exist.

const DEFAULT_PATH: String = "user://chronicle.json"
const SCHEMA_VERSION: int = 1

## Where to read and write. Tests point this at a temp file so they never touch
## a real save.
static var path: String = DEFAULT_PATH

static var _seen: Dictionary = {}
static var _loaded: bool = false


## Reading order. Each entry is `{id, keys}`; `keys` are the translation keys
## shown once the entry is unlocked.
##
## Story entries are marked by the arena as their dialogue opens; `meet_*`
## entries are the first-sight lines (`HeroVoice`); `epitaph_*` are the three
## ways a run can end.
static func sections() -> Array[Dictionary]:
	# Story entries come from the episode catalog, grouped by act, so a
	# future episode appears here with no edit. Entry ids and keys stay
	# exactly as they were: old saves outlive this file.
	var beats_by_act: Dictionary = {}
	for beat: int in StoryEpisodes.story_beats():
		var act_number: int = int(StoryEpisodes.act_of_cycle(beat).get("number", 1))
		if not beats_by_act.has(act_number):
			beats_by_act[act_number] = []
		(beats_by_act[act_number] as Array).append(beat)
	var act_numbers: Array = beats_by_act.keys()
	act_numbers.sort()
	var out: Array[Dictionary] = []
	for act_number: int in act_numbers:
		var entries: Array = []
		if act_number == 1:
			entries.append(_entry("story_open", ["STORY_OPEN_A", "STORY_OPEN_B"]))
		for act_beat: int in beats_by_act[act_number]:
			entries.append(_story(act_beat))
		out.append(_act(act_number, entries))
	out.append(
		{"title": "CHRONICLE_PLACES", "label": "", "entries": [
			_place(0), _place(1), _place(2), _place(3), _place(4), _place(5)]})
	out.append(
		{"title": "CHRONICLE_SPIRITS", "label": "", "entries": [
			_meet("drifter"), _meet("ember"), _meet("caster"), _meet("weaver"),
			_meet("stalker"), _meet("swarm"), _meet("wisp")]})
	out.append(
		{"title": "CHRONICLE_GUARDIANS", "label": "", "entries": [
			_meet("guardian_forest"), _meet("guardian_field"), _meet("guardian_camp"),
			_meet("guardian_forest_thorn"), _meet("guardian_field_storm"),
			_meet("guardian_camp_siege"),
			_meet("guardian_frost"), _meet("guardian_marsh"), _meet("guardian_ruins"),
			_meet("guardian_frost_rime"), _meet("guardian_marsh_glow"),
			_meet("guardian_ruins_halo")]})
	out.append(
		{"title": "CHRONICLE_ENDINGS", "label": "", "entries": [
			_ending("win", "STORY_EPITAPH_WIN"),
			_ending("escape", "STORY_EPITAPH_ESCAPE"),
			_ending("lose", "STORY_EPITAPH_LOSE")]})
	return out


## Record that something was seen. Returns true only the first time.
##
## Unknown ids are refused, so a typo at a call site cannot silently write junk
## into a save file that will outlive the code that wrote it.
static func mark(id: String) -> bool:
	_ensure_loaded()
	if _seen.has(id) or not _known().has(id):
		return false
	_seen[id] = true
	_save()
	return true


static func has(id: String) -> bool:
	_ensure_loaded()
	return _seen.has(id)


## Entries the player has unlocked.
static func unlocked_count() -> int:
	_ensure_loaded()
	var count: int = 0
	for id in _known():
		if _seen.has(id):
			count += 1
	return count


## Every entry there is to find.
static func total_count() -> int:
	return _known().size()


## Forget the in-memory copy, so the next read comes from `path`. For tests.
##
## Not called `reload`: a class name resolves to its `GDScript` resource, and
## `Script.reload()` is a built-in that re-parses the file and **resets every
## static variable** — `path` and the cache with it. A function of that name is
## called by the engine's version, not this one, and silently undoes the very
## state the caller just set.
static func forget_cache() -> void:
	_seen = {}
	_loaded = false


## Entry id for a first-sight moment, e.g. `meet_drifter`, or a place-memory
## moment, e.g. `place_forest`; `""` for a moment that is not a chronicle
## entry.
static func id_for_moment(moment: String) -> String:
	if not _known().has(moment):
		return ""
	if moment.begins_with("meet_") or moment.begins_with("place_"):
		return moment
	return ""


# --- internals ----------------------------------------------------------------
## Built from the act number rather than a string prefix: an all-caps literal in
## a script is read by the locale check as a translation key, and a prefix is not.
static func _act(number: int, entries: Array) -> Dictionary:
	return {
		"title": "ACT_%d_TITLE" % number,
		"label": "ACT_%d_LABEL" % number,
		"entries": entries,
	}


static func _entry(id: String, keys: Array) -> Dictionary:
	return {"id": id, "keys": keys}


static func _story(cycle: int) -> Dictionary:
	return _entry("story_%d" % cycle, [
		"STORY_CYCLE_%d_A" % cycle, "STORY_CYCLE_%d_B" % cycle])


static func _meet(kind: String) -> Dictionary:
	return _entry("meet_" + kind, ["VOICE_MEET_%s_1" % kind.to_upper()])


## A restored place: its motif name first, then the discovery line.
static func _place(terrain: int) -> Dictionary:
	return {"id": PlaceMemory.chronicle_id(terrain), "keys": [
		PlaceMemory.name_key(terrain), PlaceMemory.memory_key(terrain)]}


## An ending shows its short name first, then the line the run closed on.
static func _ending(kind: String, key: String) -> Dictionary:
	return _entry("epitaph_" + kind, ["CHRONICLE_ENDING_" + kind.to_upper(), key])


static func _known() -> Dictionary:
	var ids: Dictionary = {}
	for section in sections():
		for entry: Dictionary in section["entries"]:
			ids[str(entry["id"])] = true
	return ids


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_seen = {}
	if not FileAccess.file_exists(path):
		return
	# JSON, parsed through the instance API. Both `ConfigFile.load` and the static
	# `JSON.parse_string` print an engine ERROR on a truncated file, while
	# `JSON.new().parse()` just returns an error code. A half-written reading log
	# is an ordinary event (the app was killed mid-save), not something to report.
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return
	var data: Variant = parser.data
	if not data is Dictionary:
		return
	var seen: Variant = (data as Dictionary).get("seen", [])
	if not seen is Array:
		return
	for id in seen as Array:
		if id is String:
			_seen[id] = true


static func _save() -> void:
	var ids: Array = _seen.keys()
	ids.sort()
	var text: String = JSON.stringify({"schema_version": SCHEMA_VERSION, "seen": ids})
	# Write beside, then swap in, so a kill mid-write leaves the old file whole.
	var temp: String = path + ".tmp"
	var handle: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if handle == null:
		push_warning("Chronicle: could not write %s" % temp)
		return
	handle.store_string(text)
	handle.close()
	var moved: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))
	if moved != OK:
		# Some platforms will not rename over an existing file. The log is tiny,
		# so a direct write is an acceptable fallback.
		var direct: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if direct != null:
			direct.store_string(text)
			direct.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
