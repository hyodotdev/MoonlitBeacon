extends RefCounted

## Reads Firebase REST settings from one place.
##
## `firebase.cfg` is a local secret file injected at build time. A web API key
## cannot be fully hidden in a mobile binary. Firestore schema rules alone do
## not stop automated requests or cost attacks, so this also requires a separate
## lock that remote App Check or a protected ingestion path has been verified.
## This class never puts the key in logs or analytics events.

const PROJECT_ID: String = "moonlitbeacon-778ee"
const DATABASE_ID: String = "(default)"
const KEY_PATH: String = "res://firebase.cfg"
const API_ROOT: String = "https://firestore.googleapis.com/v1"


static func read() -> Dictionary:
	var result: Dictionary = {
		"web_api_key": "",
		"analytics_enabled": false,
		"analytics_ingestion_hardened": false,
		"analytics_allow_debug": false,
	}
	var config: ConfigFile = ConfigFile.new()
	if config.load(KEY_PATH) != OK:
		return result

	var key: Variant = config.get_value("firebase", "web_api_key", "")
	if typeof(key) == TYPE_STRING:
		result["web_api_key"] = str(key).strip_edges()
	var analytics_enabled: Variant = config.get_value(
		"analytics", "enabled", false)
	if typeof(analytics_enabled) == TYPE_BOOL:
		result["analytics_enabled"] = bool(analytics_enabled)
	var ingestion_hardened: Variant = config.get_value(
		"analytics", "ingestion_hardened", false)
	if typeof(ingestion_hardened) == TYPE_BOOL:
		result["analytics_ingestion_hardened"] = bool(ingestion_hardened)
	var allow_debug: Variant = config.get_value(
		"analytics", "allow_debug", false)
	if typeof(allow_debug) == TYPE_BOOL:
		result["analytics_allow_debug"] = bool(allow_debug)
	return result


static func configured_for_analytics(config: Dictionary = {}) -> bool:
	var resolved: Dictionary = read() if config.is_empty() else config
	return bool(resolved.get("analytics_enabled", false)) \
		and bool(resolved.get("analytics_ingestion_hardened", false)) \
		and not str(resolved.get("web_api_key", "")).is_empty()


static func document_create_url(collection: String, document_id: String,
		web_api_key: String) -> String:
	return "%s/projects/%s/databases/%s/documents/%s?documentId=%s&key=%s" % [
		API_ROOT,
		PROJECT_ID,
		DATABASE_ID,
		collection.uri_encode(),
		document_id.uri_encode(),
		web_api_key.uri_encode(),
	]
