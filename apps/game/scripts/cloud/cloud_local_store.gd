extends RefCounted

## Per-UID local journey files keyed by account. Switching accounts loads the
## new UID's file and never writes one account's payload over another's.
##
## Files hold only Journey checkpoint data the game already owns locally. They
## never hold ID tokens, emails, provider names, or auth codes.

const CloudSchema: Script = preload("res://scripts/cloud/cloud_schema.gd")

const FILE_PREFIX: String = "user://cloud_journey."
const FILE_SUFFIX: String = ".json"


func save_local(uid: String, payload: String, revision: int) -> Dictionary:
	if uid.is_empty():
		return {"ok": false, "error": "invalid-uid"}
	var path: String = path_for_uid(uid)
	var envelope: Dictionary = {
		"uid": uid,
		"revision": revision,
		"payload": payload,
		"saved_at": Time.get_datetime_string_from_system(true) + "Z",
	}
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "write-failed"}
	file.store_string(JSON.stringify(envelope))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_discard(path + ".tmp")
		return {"ok": false, "error": "write-failed"}
	var check: FileAccess = FileAccess.open(path + ".tmp", FileAccess.READ)
	if check == null:
		_discard(path + ".tmp")
		return {"ok": false, "error": "verify-failed"}
	var verified: Dictionary = CloudSchema.parse_json_value(
		check.get_as_text())
	check.close()
	if not bool(verified.get("ok", false)) \
			or typeof(verified.get("value")) != TYPE_DICTIONARY:
		_discard(path + ".tmp")
		return {"ok": false, "error": "verify-failed"}
	var move_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(path + ".tmp"),
		ProjectSettings.globalize_path(path))
	if move_error != OK:
		_discard(path + ".tmp")
		return {"ok": false, "error": "write-failed"}
	return {"ok": true, "path": path}


func load_local(uid: String) -> Dictionary:
	if uid.is_empty():
		return {"ok": false, "error": "invalid-uid"}
	var path: String = path_for_uid(uid)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "not-found"}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "read-failed"}
	var decoded: Dictionary = CloudSchema.parse_json_value(
		file.get_as_text())
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "corrupt"}
	var envelope: Dictionary = decoded.get("value")
	if str(envelope.get("uid", "")) != uid:
		return {"ok": false, "error": "uid-mismatch"}
	return {
		"ok": true,
		"uid": uid,
		"revision": int(envelope.get("revision", 0)),
		"payload": str(envelope.get("payload", "")),
		"path": path,
	}


func delete_local(uid: String) -> void:
	if uid.is_empty():
		return
	var path: String = path_for_uid(uid)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_discard(path + ".tmp")


func path_for_uid(uid: String) -> String:
	return FILE_PREFIX + safe_uid_token(uid) + FILE_SUFFIX


## UIDs from the server are never trusted as path text. Firebase UIDs are
## URL-safe already; anything else becomes a stable hash token.
static func safe_uid_token(uid: String) -> String:
	if uid.is_empty():
		return "empty"
	var plain: bool = uid.length() <= 64
	if plain:
		for code in uid.to_utf8_buffer():
			var ok: bool = (code >= 48 and code <= 57) \
				or (code >= 65 and code <= 90) \
				or (code >= 97 and code <= 122) \
				or code == 45 or code == 95
			if not ok:
				plain = false
				break
	if plain:
		return uid
	return "h_" + uid.sha256_text().substr(0, 32)


func _discard(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
