extends "res://scripts/iap/iap_store.gd"

## Store stand-in that builds both verified temp replicas, then fails only the chosen commit replace.

var fail_target_path: String = BACKUP_SAVE_PATH


func _replace_save(_from_path: String, _to_path: String) -> Error:
	if _to_path == fail_target_path:
		return ERR_CANT_CREATE
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(_from_path),
		ProjectSettings.globalize_path(_to_path))
