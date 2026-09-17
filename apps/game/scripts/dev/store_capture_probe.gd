extends RefCounted

## Prove the actual runtime state of a store-capture screen as JSON.
##
## Coordinates or PNG size become false positives as soon as art, translation,
## or device speed change. Only TestLauncher/ArenaTools on a debug build call
## this probe: they actually build and check the requested scene state, then
## atomically publish proof that includes the nonce.

const REQUEST_PATH: String = "user://store_capture_runtime.request.json"
const STATE_PATH: String = "user://store_capture_runtime.state.json"
const TEMP_PATH: String = "user://store_capture_runtime.state.tmp"
const ALLOWED_KINDS: Array[String] = [
	"arena_ready",
	"title",
	"moonlight_barrage",
	"shrine",
	"hero_preview",
	"hero_direction",
	"field_guardian",
	"iap_review",
	"direct_distribution",
]
const ALLOWED_LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const DIRECT_PROBE_PRODUCT_ID: String = \
	"com.crossplatformkorea.moonlitbeacon.hero_dancer"
const DIRECT_PROBE_HERO_PATH: String = "res://resources/heroes/dancer.tres"

static var _last_nonce: String = ""
static var _frames_after_prepare: int = 0
static var _ready_latched: bool = false
static var _observation: int = 0


static func valid_nonce(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in value.length():
		var codepoint: int = value.unicode_at(index)
		if not (codepoint >= 48 and codepoint <= 57) \
				and not (codepoint >= 97 and codepoint <= 102):
			return false
	return true


static func poll(scene: Node) -> void:
	if not OS.is_debug_build() or scene == null \
			or not FileAccess.file_exists(REQUEST_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REQUEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var request: Dictionary = parsed
	var nonce: String = str(request.get("nonce", ""))
	var kind: String = str(request.get("kind", ""))
	if not valid_nonce(nonce) \
			or kind not in ALLOWED_KINDS:
		return
	var requested_locale: String = capture_locale(request)
	if not requested_locale.is_empty() \
			and TranslationServer.get_locale() != requested_locale:
		# Device capture language switches do not save the settings file. The
		# host can byte-exact compare settings.cfg before and after capture,
		# and only this debug process's translation changes — the settings
		# screen's choice is left alone.
		TranslationServer.set_locale(requested_locale)
	if nonce != _last_nonce:
		_last_nonce = nonce
		_frames_after_prepare = 0
		_ready_latched = false
		_observation = 0
	# After the first ready, keep the same nonce as a pure observation session.
	# Restoring guardian position or IAP scroll with a new prepare after capture
	# can make a wrong screen look the same before and after, so a post-screencap
	# sample must never call prepare again.
	if kind != "direct_distribution" and not _ready_latched \
			and scene.has_method("debug_prepare_store_capture"):
		scene.debug_prepare_store_capture(request)
	_frames_after_prepare += 1
	# Give open()/scroll_horizontal changes and Control layout time to hit a real draw.
	if _frames_after_prepare < 2:
		return
	var state: Dictionary = _direct_distribution_state(scene) \
		if kind == "direct_distribution" \
		else scene.debug_store_capture_state(request) \
		if scene.has_method("debug_store_capture_state") else {}
	if state.is_empty():
		return
	_observation += 1
	state["schema"] = 1
	state["nonce"] = nonce
	state["observation"] = _observation
	state["kind"] = kind
	state["game_locale"] = TranslationServer.get_locale()
	if not _write_state(state):
		return
	# Publish not-ready states under the same nonce so the host can report which
	# semantic condition is missing. Keep the request file after ready and write
	# a new observation number every frame, but do not run the prepare above
	# again. The host confirms a larger observation after screencap, then deletes
	# the handshake.
	if bool(state.get("ready", false)):
		_ready_latched = true


static func _direct_distribution_state(scene: Node) -> Dictionary:
	var store: Node = scene.get_node_or_null("/root/IapStore")
	var screen: CanvasItem = scene.get_node_or_null("Ui/Screen") as CanvasItem
	var store_button: Button = scene.get_node_or_null(
		"Ui/Screen/StoreButton") as Button
	if store == null or not store.has_method("storefront_enabled") \
			or not store.has_method("owns"):
		return {
			"ready": false,
			"direct_distribution_feature": OS.has_feature("direct_distribution"),
			"storefront_enabled": true,
			"store_state_unavailable": false,
			"cached_paid_entitlement_product_id": DIRECT_PROBE_PRODUCT_ID,
			"cached_paid_entitlement_hero_path": DIRECT_PROBE_HERO_PATH,
			"cached_paid_entitlement_fixture_present": false,
			"cached_paid_entitlement_owned": true,
			"cached_paid_entitlement_ignored": false,
			"cached_paid_entitlements_restored": false,
			"title_screen_visible": screen != null and screen.is_visible_in_tree(),
			"title_store_button_present": store_button != null,
			"title_store_button_self_visible": store_button.visible \
				if store_button != null else true,
			"title_store_button_visible_in_tree": store_button.is_visible_in_tree() \
				if store_button != null else true,
			"title_store_button_enabled": not store_button.disabled \
				if store_button != null else true,
			"title_store_button_hidden": false,
		}

	# Do not touch the disk ledger. Put a paid SKU in the live singleton's
	# memory cache for one frame, call the owns() boundary the exported binary
	# compiled, then restore a byte-equivalent Array immediately. If the
	# feature is stripped from export, owns=true and this probe fails.
	var entitlements_value: Variant = store.get("entitlements")
	var entitlements_before: Array[String] = []
	if entitlements_value is Array:
		entitlements_before.assign(entitlements_value)
	var entitlements_fixture: Array[String] = entitlements_before.duplicate()
	if DIRECT_PROBE_PRODUCT_ID not in entitlements_fixture:
		entitlements_fixture.append(DIRECT_PROBE_PRODUCT_ID)
	store.set("entitlements", entitlements_fixture)
	var fixture_present: bool = DIRECT_PROBE_PRODUCT_ID in store.get("entitlements")
	var fixture_owned: bool = bool(store.call("owns", DIRECT_PROBE_PRODUCT_ID))
	store.set("entitlements", entitlements_before)
	var entitlements_restored: bool = store.get("entitlements") == entitlements_before

	var direct_feature: bool = OS.has_feature("direct_distribution")
	var storefront_enabled: bool = bool(store.call("storefront_enabled"))
	var store_state_unavailable: bool = int(store.get("state")) == 0
	var title_screen_visible: bool = screen != null and screen.is_visible_in_tree()
	var button_present: bool = store_button != null
	var button_self_visible: bool = store_button.visible if button_present else true
	var button_visible_in_tree: bool = store_button.is_visible_in_tree() \
		if button_present else true
	var button_enabled: bool = not store_button.disabled if button_present else true
	var button_hidden: bool = button_present and not button_self_visible \
		and not button_visible_in_tree and not button_enabled
	var cached_ignored: bool = fixture_present and not fixture_owned
	return {
		"ready": direct_feature and not storefront_enabled \
			and store_state_unavailable and cached_ignored \
			and entitlements_restored and title_screen_visible and button_hidden,
		"direct_distribution_feature": direct_feature,
		"storefront_enabled": storefront_enabled,
		"store_state_unavailable": store_state_unavailable,
		"cached_paid_entitlement_product_id": DIRECT_PROBE_PRODUCT_ID,
		"cached_paid_entitlement_hero_path": DIRECT_PROBE_HERO_PATH,
		"cached_paid_entitlement_fixture_present": fixture_present,
		"cached_paid_entitlement_owned": fixture_owned,
		"cached_paid_entitlement_ignored": cached_ignored,
		"cached_paid_entitlements_restored": entitlements_restored,
		"title_screen_visible": title_screen_visible,
		"title_store_button_present": button_present,
		"title_store_button_self_visible": button_self_visible,
		"title_store_button_visible_in_tree": button_visible_in_tree,
		"title_store_button_enabled": button_enabled,
		"title_store_button_hidden": button_hidden,
	}


static func capture_locale(request: Dictionary) -> String:
	var value: String = str(request.get("game_locale", ""))
	return value if value in ALLOWED_LOCALES else ""


static func _write_state(state: Dictionary) -> bool:
	var encoded: String = JSON.stringify(state)
	var output: FileAccess = FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if output == null or not output.store_string(encoded):
		if output != null:
			output.close()
		return false
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	if write_error != OK or FileAccess.get_file_as_string(TEMP_PATH) != encoded:
		return false
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_PATH),
		ProjectSettings.globalize_path(STATE_PATH)) == OK
