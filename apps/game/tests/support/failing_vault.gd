extends "res://scripts/gameplay/vault.gd"

## Vault stand-in that writes the temp file, then fails only the final replace.
##
## A stand-in that first clears the real save path cannot test whether atomic
## replace keeps the previous file. This goes through the real verify-and-write
## path and stops only at the commit boundary.

var should_fail: bool = true
var fail_target_path: String = SAVE_PATH


func _replace_save(_from_path: String, _to_path: String) -> Error:
	if should_fail and _to_path == fail_target_path:
		return ERR_CANT_CREATE
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(_from_path),
		ProjectSettings.globalize_path(_to_path))
