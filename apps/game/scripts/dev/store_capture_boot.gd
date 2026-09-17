extends RefCounted

## Debug request that opens the same real scene on iOS and Android tablets
## without coordinate input.
##
## Drop the request in the app data container and relaunch: TestLauncher opens
## the run, and ArenaTools handles the one-shot setup for that shot. Release
## builds never even read the file, so the store build's normal start path is
## untouched.

const REQUEST_PATH: String = "user://store_capture_boot.request.json"
const ALLOWED_KINDS: Array[String] = [
	"moonlight_barrage",
	"missile_core",
	"field_guardian",
]


static func read_request(debug_build: bool = OS.is_debug_build()) -> Dictionary:
	if not debug_build or not FileAccess.file_exists(REQUEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REQUEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var request: Dictionary = parsed
	var nonce: String = str(request.get("nonce", ""))
	var kind: String = str(request.get("kind", ""))
	if nonce.length() != 64 or not nonce.is_valid_hex_number(false) \
			or kind not in ALLOWED_KINDS:
		return {}
	return {"schema": 1, "nonce": nonce, "kind": kind}
