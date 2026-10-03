extends RefCounted

## Stamps the Play Games application id into the exported Android manifest.
##
## The native bridge is fail-closed: provider calls answer `not_configured`
## with `missing: ["play_games_app_id"]` unless the app manifest carries the
## `com.google.android.gms.games.APP_ID` metadata. The per-game id lives in
## the staged public config (`[google] play_app_id`), never in the plugin
## AAR, so the export plugin injects it here at export time through
## `_get_android_manifest_application_element_contents`.
##
## Pure static functions over the config file path, so tests exercise the
## exact manifest text without running an export.

const APP_ID_KEY: String = "play_app_id"
const APP_ID_META_NAME: String = "com.google.android.gms.games.APP_ID"
const MIN_APP_ID_DIGITS: int = 4
const MAX_APP_ID_DIGITS: int = 20


static func application_element_contents(config_path: String) -> String:
	var app_id: String = read_play_app_id(config_path)
	if app_id.is_empty():
		# No valid id: inject nothing. Provider sign-in reports
		# not_configured at runtime; guest play is unaffected.
		return ""
	return '<meta-data android:name="%s" android:value="%s" />' % [
		APP_ID_META_NAME, app_id]


static func read_play_app_id(config_path: String) -> String:
	if config_path.is_empty() or not FileAccess.file_exists(config_path):
		return ""
	var config: ConfigFile = ConfigFile.new()
	if config.load(config_path) != OK:
		return ""
	var raw: Variant = config.get_value("google", APP_ID_KEY, "")
	if typeof(raw) != TYPE_STRING:
		return ""
	var app_id: String = str(raw).strip_edges()
	if app_id.length() < MIN_APP_ID_DIGITS \
			or app_id.length() > MAX_APP_ID_DIGITS:
		return ""
	for i in app_id.length():
		var code: int = int(app_id.unicode_at(i))
		if code < 48 or code > 57:
			return ""
	return app_id
