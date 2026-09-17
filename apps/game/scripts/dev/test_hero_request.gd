extends RefCounted

## One-shot request so adb device checks can pick the next run's hero without
## forging the IAP ledger or Vault ownership. Debug builds delete it as soon as
## they read it.

const PATH: String = "user://test_hero.request"
const HERO_PATHS: Array[String] = [
	"res://resources/heroes/warden.tres",
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/eclipse.tres",
	"res://resources/heroes/sage.tres",
]


## Drop one Hero path line into `files/test_hero.request` over adb and only the
## next debug run uses that hero. Invalid paths are consumed once too, so a bad
## request cannot fail forever.
static func take(debug_build: bool) -> String:
	if not debug_build or not FileAccess.file_exists(PATH):
		return ""
	var path: String = FileAccess.get_file_as_string(PATH).strip_edges()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	return path if path in HERO_PATHS else ""
