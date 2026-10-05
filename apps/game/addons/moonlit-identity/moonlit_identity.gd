extends Node

## Godot-side end of the MoonlitIdentity native bridge.
##
## One bounded async API over two native implementations: the Android Godot
## plugin (`MoonlitIdentity` engine singleton, Google Credential Manager +
## Apple browser OAuth + Play Games v2 + Firebase Auth) and the iOS
## GDExtension class (`MoonlitIdentityIos`, GoogleSignIn + Sign in with Apple
## + Firebase Auth). Where no native side exists (desktop editor, unconfigured
## export) every provider call answers with an explicit `unsupported` or
## `not_configured` receipt, so guest play stays possible and no caller has to
## guess what happened.
##
## Providers are platform-independent ids with per-platform readiness:
## `google` is the shared Firebase `google.com` identity on Android and iOS,
## `apple` the shared Firebase `apple.com` identity on both, and
## `play_games` the distinct Android-only Play Games v2 gaming profile
## (`playgames.google.com`). Readiness gates each provider separately: a
## missing Google client id never blocks guest or Apple play, and a missing
## Apple setup never blocks Google.
##
## Callback contract (both natives honor it):
## - Each call takes a `request_id` string plus one JSON object argument and
##   answers synchronously with a receipt JSON object: `pending` (work
##   started), or a terminal `ok` / `error` / `cancelled` / `conflict` /
##   `unsupported` / `not_configured` receipt.
## - A `pending` receipt is always followed by exactly one terminal outcome on
##   the native `moonlit_identity_event` signal, carrying the same
##   `request_id`. Late answers after cancel or timeout are dropped here by id,
##   and a second terminal for one id is dropped too.
## - `moonlitCancelRequest(request_id)` answers `cancelled` while the native
##   side has not yet begun an irreversible SDK mutation (the native side
##   emits nothing further for the id), or `draining` once a mutation began.
##   Draining keeps this request's lock: the terminal outcome still arrives on
##   the signal and reports what really happened. Dropping a callback never
##   undoes a mutation, so this layer never claims `cancelled` past that line.
## - Outcomes carry only identifiers and status: `uid`, `provider`, `kind`,
##   `status`, `code`. ID tokens and auth codes are consumed inside the native
##   SDK calls and are never placed in a receipt, a signal, or a log.
##
## This wrapper never prints or stores a token, auth code, email, or display
## name. Diagnostics name the `request_id`, `status`, and `code` only.

signal request_completed(outcome: Dictionary)

const PROVIDER_GOOGLE: String = "google"
const PROVIDER_PLAY_GAMES: String = "play_games"
const PROVIDER_APPLE: String = "apple"

const STATUS_OK: String = "ok"
const STATUS_PENDING: String = "pending"
const STATUS_CANCELLED: String = "cancelled"
const STATUS_CONFLICT: String = "conflict"
const STATUS_ERROR: String = "error"
const STATUS_UNSUPPORTED: String = "unsupported"
const STATUS_NOT_CONFIGURED: String = "not_configured"
const STATUS_DRAINING: String = "draining"

const CODE_USER_CANCELLED: String = "user_cancelled"
const CODE_ALREADY_LINKED_ELSEWHERE: String = "already_linked_elsewhere"
const CODE_NATIVE_MISSING: String = "native_bridge_unavailable"
const CODE_NOT_CONFIGURED: String = "identity_not_configured"
const CODE_UNKNOWN_PROVIDER: String = "unknown_provider"
const CODE_NETWORK: String = "network_error"
const CODE_TOKEN_EXPIRED: String = "token_expired"
const CODE_TOKEN_REVOKED: String = "token_revoked"
const CODE_REQUEST_TIMEOUT: String = "request_timeout"
const CODE_NO_PENDING_REQUEST: String = "no_pending_request"

const ANDROID_SINGLETON_NAME: String = "MoonlitIdentity"
const IOS_CLASS_NAME: String = "MoonlitIdentityIos"
const NATIVE_SIGNAL_NAME: String = "moonlit_identity_event"
const CONFIG_PATH: String = "res://moonlit_identity.cfg"
const REQUEST_TIMEOUT_SECONDS: float = 30.0
# Provider account/consent sheets wait on a human, not the network: a
# player reading the Google/Apple chooser must not be cancelled as a slow
# request. Only the sheet calls use this window; every other call keeps
# the ordinary network window above. Both stay bounded: expiry still asks
# the native side to stop and then force-settles (see _on_request_timeout).
const INTERACTIVE_TIMEOUT_SECONDS: float = 300.0
# A timeout asks the native side to stop. While a mutation is draining, the
# deadline extends this many extra windows before the request force-settles.
const TIMEOUT_EXTRA_WINDOWS: int = 2
# Settled ids exist only to drop late/double signal outcomes. The cap keeps a
# long session's bookkeeping bounded; pending entries need no cap because each
# one always settles through its own timeout.
const SETTLED_CAP: int = 64

var _request_timeout_seconds: float = REQUEST_TIMEOUT_SECONDS
var _interactive_timeout_seconds: float = INTERACTIVE_TIMEOUT_SECONDS
var _request_counter: int = 0
var _pending: Dictionary = {}
var _settled: Dictionary = {}
var _settled_order: Array = []
var _native: Object
var _native_platform: String = ""
var _native_signal_connected: bool = false
var _config_loaded: bool = false
var _config_cache: Dictionary = {}


## Tests only: blanket deadline override for both windows. This keeps the
## setter's historical meaning (every pending request, whatever its
## method), so older suites behave exactly as before. Call
## `set_interactive_timeout_seconds` after this to separate the windows.
func set_request_timeout_seconds(value: float) -> void:
	_request_timeout_seconds = maxf(0.5, value)
	_interactive_timeout_seconds = maxf(0.5, value)


## Tests only: deadline override for the provider sheet calls alone. The
## ordinary window keeps whatever `set_request_timeout_seconds` set (or
## the 30-second production default), so one bridge can prove the two
## windows differ without sleeping five minutes.
func set_interactive_timeout_seconds(value: float) -> void:
	_interactive_timeout_seconds = maxf(0.5, value)


func set_config_override(config: Dictionary) -> void:
	_config_loaded = true
	_config_cache = config.duplicate(true)


func set_native_override(native: Object, platform: String) -> void:
	# Tests only: stand in for the engine singleton / GDExtension class so
	# the request bookkeeping runs without a device build.
	_native = native
	_native_platform = platform
	_connect_native_signal()


func is_native_available() -> bool:
	return _require_native() != null


func native_platform() -> String:
	_require_native()
	return _native_platform


func get_capabilities() -> Dictionary:
	if _require_native() == null:
		return {
			"status": STATUS_UNSUPPORTED,
			"code": CODE_NATIVE_MISSING,
			"supported": false,
			"providers": [],
			"guest": true,
		}
	# Both natives initialize Firebase from staged public client config, so
	# missing Firebase keys gate guests as well as providers. The Apple
	# services id is deliberately not consulted: the native sheet needs the
	# App ID entitlement plus Firebase client config, not a web services id.
	var firebase_missing: Array = _missing_firebase_keys()
	if not firebase_missing.is_empty():
		# No Firebase for this platform: guests and every provider refuse,
		# so one report names every missing key.
		var missing: Array = []
		missing.append_array(firebase_missing)
		missing.append_array(_missing_provider_keys())
		return {
			"status": STATUS_NOT_CONFIGURED,
			"code": CODE_NOT_CONFIGURED,
			"supported": true,
			"providers": [],
			"guest": true,
			"missing": missing,
		}
	# Firebase is present, so guests work and each ready provider is
	# listed. A missing provider key removes only that provider: missing
	# Google config never blocks Apple or guest play, and a missing Apple
	# setup never blocks Google. Full readiness is `missing` empty.
	return {
		"status": STATUS_OK,
		"code": "",
		"supported": true,
		"providers": _ready_providers(),
		"guest": true,
		"missing": _missing_provider_keys(),
	}


## Provider ids whose staged config is complete on this platform. The
## caller checked Firebase first; these are the provider keys on top.
func _ready_providers() -> Array:
	var providers: Array = []
	if _native_platform == "android":
		var server_client_id: String = _public_config_value(
			"google", "server_client_id")
		if not server_client_id.is_empty():
			providers.append(PROVIDER_GOOGLE)
			# The native bridge is fail-closed on the manifest APP_ID
			# the export stamps from this key, so readiness says so up
			# front: without it the Play Games profile stays unoffered.
			if not _public_config_value(
					"google", "play_app_id").is_empty():
				providers.append(PROVIDER_PLAY_GAMES)
		if _is_apple_android_enabled():
			providers.append(PROVIDER_APPLE)
	elif _native_platform == "ios":
		if not _public_config_value(
				"google", "ios_client_id").is_empty():
			providers.append(PROVIDER_GOOGLE)
		if _is_apple_ios_enabled():
			providers.append(PROVIDER_APPLE)
	return providers


## Provider keys missing on this platform, independent of Firebase.
func _missing_provider_keys() -> Array:
	var missing: Array = []
	if _native_platform == "android":
		if _public_config_value(
				"google", "server_client_id").is_empty():
			missing.append("google.server_client_id")
		if _public_config_value("google", "play_app_id").is_empty():
			missing.append("google.play_app_id")
		if not _is_apple_android_enabled():
			missing.append("apple.android_enabled")
	elif _native_platform == "ios":
		if _public_config_value(
				"google", "ios_client_id").is_empty():
			missing.append("google.ios_client_id")
		if not _is_apple_ios_enabled():
			missing.append("apple.ios_enabled")
	return missing


## The staged setup acknowledgment for the Apple browser flow on Android.
## Firebase-side Service ID/key material never enters the app; this flag
## only records that the director configured it, so buttons stay truthful
## before that setup lands.
func _is_apple_android_enabled() -> bool:
	return _is_apple_flag_enabled("android_enabled")


## The staged setup acknowledgment for the native Apple sheet on iOS: the
## entitlement plus the Firebase-console Apple provider setup, both of
## which live outside the app. Without it the sheet stays unoffered even
## when Firebase client config is present.
func _is_apple_ios_enabled() -> bool:
	return _is_apple_flag_enabled("ios_enabled")


func _is_apple_flag_enabled(key: String) -> bool:
	var raw: String = _public_config_value("apple", key)
	raw = raw.strip_edges().to_lower()
	return raw == "true" or raw == "1"


func _missing_firebase_keys() -> Array:
	var missing: Array = []
	if _native_platform != "android" and _native_platform != "ios":
		return missing
	var keys: Array[String] = ["project_id", "sender_id"]
	if _native_platform == "android":
		keys.append_array(["android_api_key", "android_app_id"])
	else:
		keys.append_array(["ios_api_key", "ios_app_id"])
	for key in keys:
		if _public_config_value("firebase", key).is_empty():
			missing.append("firebase." + key)
	return missing


func sign_in_guest() -> Dictionary:
	var gate: Dictionary = _gate_firebase_ready()
	if not gate.is_empty():
		return gate
	return _native_call("moonlitSignInGuest", {})


func sign_in_provider(provider: String, _options: Dictionary = {}) -> Dictionary:
	var gate: Dictionary = _gate_provider_ready(provider)
	if not gate.is_empty():
		return gate
	return _native_call("moonlitSignInProvider", {"provider": provider})


func link_provider(provider: String, _options: Dictionary = {}) -> Dictionary:
	var gate: Dictionary = _gate_provider_ready(provider)
	if not gate.is_empty():
		return gate
	return _native_call("moonlitLinkProvider", {"provider": provider})


func get_session() -> Dictionary:
	var native: Object = _require_native()
	if native == null:
		return {
			"status": STATUS_OK,
			"kind": "local_guest",
			"uid": "",
			"provider": "",
		}
	var receipt: Dictionary = _native_call("moonlitGetSession", {})
	if str(receipt.get("status", "")) == STATUS_OK:
		return receipt
	if str(receipt.get("status", "")) == STATUS_PENDING:
		# A native side that answers session reads asynchronously (both
		# shipped natives answer synchronously): the terminal settles on
		# the signal like any other pending call, so adapters can hydrate
		# through `refresh_native_session` without a special path.
		return receipt
	return {
		"status": STATUS_OK,
		"kind": "local_guest",
		"uid": "",
		"provider": "",
	}


func get_id_token(force_refresh: bool = false) -> Dictionary:
	var gate: Dictionary = _gate_firebase_ready()
	if not gate.is_empty():
		return gate
	# The documented single exception to token scrubbing: this call's own
	# answer may carry `id_token`. Hold it in memory, use it at once, never
	# save or log it.
	return _native_call("moonlitGetIdToken", {"force_refresh": force_refresh},
		true)


func sign_out() -> Dictionary:
	var gate: Dictionary = _gate_native_ready()
	if not gate.is_empty():
		return gate
	return _native_call("moonlitSignOut", {})


func delete_account(options: Dictionary = {}) -> Dictionary:
	var gate: Dictionary = _gate_firebase_ready()
	if not gate.is_empty():
		return gate
	# On iOS the native side re-runs the Sign in with Apple sheet itself to
	# get a fresh auth code for revocation, unless the caller passes
	# `keep_provider_grant: true` to delete only the Firebase user. Auth codes
	# are single-use and short-lived, so they are minted and consumed inside
	# the native call and never cross into GDScript, logs, or saves.
	return _native_call("moonlitDeleteAccount", options)


func cancel_request(request_id: String) -> Dictionary:
	if not _pending.has(request_id):
		return {"status": STATUS_ERROR, "code": CODE_NO_PENDING_REQUEST}
	if _native_reports_draining(request_id):
		# A mutation already began natively: the lock stays and the terminal
		# outcome still arrives on the signal. Claiming `cancelled` here
		# would free the next sign-in to race the mutation's real outcome.
		return {"status": STATUS_DRAINING, "request_id": request_id}
	_pending.erase(request_id)
	_remember_settled(request_id)
	request_completed.emit({
		"status": STATUS_CANCELLED,
		"code": CODE_USER_CANCELLED,
		"request_id": request_id,
	})
	return {"status": STATUS_CANCELLED, "request_id": request_id}


func pending_request_ids() -> Array:
	return _pending.keys()


func settled_request_count() -> int:
	# Test hook: proves the settled-id bookkeeping stays bounded.
	return _settled.size()


func pending_timeout_seconds(request_id: String) -> float:
	# Test hook: the armed deadline for one tracked request, or -1 when
	# the id is unknown. Proves each method stored its own policy window.
	if not _pending.has(request_id):
		return -1.0
	return float((_pending[request_id] as Dictionary).get(
		"timeout_seconds", -1.0))


func _gate_native_ready() -> Dictionary:
	if _require_native() == null:
		return {"status": STATUS_UNSUPPORTED, "code": CODE_NATIVE_MISSING}
	return {}


func _gate_firebase_ready() -> Dictionary:
	var gate: Dictionary = _gate_native_ready()
	if not gate.is_empty():
		return gate
	var missing: Array = _missing_firebase_keys()
	if not missing.is_empty():
		return {
			"status": STATUS_NOT_CONFIGURED,
			"code": CODE_NOT_CONFIGURED,
			"missing": missing,
		}
	return {}


func _gate_provider_ready(provider: String) -> Dictionary:
	var gate: Dictionary = _gate_native_ready()
	if not gate.is_empty():
		return gate
	# Platform allowlist first: `google` and `apple` are the same Firebase
	# provider on either OS, while `play_games` is Android-only and never
	# stands in for `google.com` anywhere.
	if _native_platform == "android":
		if provider != PROVIDER_GOOGLE \
				and provider != PROVIDER_PLAY_GAMES \
				and provider != PROVIDER_APPLE:
			return {"status": STATUS_ERROR, "code": CODE_UNKNOWN_PROVIDER}
	elif _native_platform == "ios":
		if provider != PROVIDER_GOOGLE \
				and provider != PROVIDER_APPLE:
			return {"status": STATUS_ERROR, "code": CODE_UNKNOWN_PROVIDER}
	else:
		return {"status": STATUS_ERROR, "code": CODE_UNKNOWN_PROVIDER}
	# Then only this provider's own keys: a missing Google client id
	# refuses Google while Apple and guest play on.
	var missing: Array = _missing_firebase_keys()
	missing.append_array(_missing_provider_keys_for(provider))
	if not missing.is_empty():
		return {
			"status": STATUS_NOT_CONFIGURED,
			"code": CODE_NOT_CONFIGURED,
			"missing": missing,
		}
	return {}


## Staged keys this provider needs beyond Firebase, on this platform.
func _missing_provider_keys_for(provider: String) -> Array:
	var missing: Array = []
	if _native_platform == "android":
		if provider == PROVIDER_GOOGLE:
			if _public_config_value(
					"google", "server_client_id").is_empty():
				missing.append("google.server_client_id")
		elif provider == PROVIDER_PLAY_GAMES:
			if _public_config_value(
					"google", "server_client_id").is_empty():
				missing.append("google.server_client_id")
			if _public_config_value(
					"google", "play_app_id").is_empty():
				missing.append("google.play_app_id")
		elif provider == PROVIDER_APPLE:
			if not _is_apple_android_enabled():
				missing.append("apple.android_enabled")
	elif _native_platform == "ios":
		if provider == PROVIDER_GOOGLE:
			if _public_config_value(
					"google", "ios_client_id").is_empty():
				missing.append("google.ios_client_id")
		elif provider == PROVIDER_APPLE:
			if not _is_apple_ios_enabled():
				missing.append("apple.ios_enabled")
	return missing


## Deadline policy for one native method. Only the provider sheet calls
## wait on a human: sign-in and link always present the native
## account/consent chooser, so they use the interactive window. There is
## no dedicated reauthentication method — a stale session re-runs the
## sign-in sheet (covered), and the Apple reauth inside delete answers to
## the host's own delete deadline — so guest, session, token, sign-out,
## and delete calls keep the ordinary network window.
func _timeout_for_method(method: String) -> float:
	if method == "moonlitSignInProvider" \
			or method == "moonlitLinkProvider":
		return _interactive_timeout_seconds
	return _request_timeout_seconds


func _native_call(method: String, args: Dictionary,
		keep_token: bool = false) -> Dictionary:
	var native: Object = _require_native()
	if native == null:
		return {"status": STATUS_UNSUPPORTED, "code": CODE_NATIVE_MISSING}
	if not _native_has_method(native, method):
		return {"status": STATUS_UNSUPPORTED, "code": CODE_NATIVE_MISSING}
	var request_id: String = _new_request_id()
	var payload: Dictionary = args.duplicate()
	payload["request_id"] = request_id
	_inject_public_config(payload)
	var raw: Variant = native.call(method, request_id, JSON.stringify(payload))
	var receipt: Dictionary = _parse_receipt(raw)
	if receipt.is_empty():
		return {"status": STATUS_ERROR, "code": CODE_NETWORK}
	receipt["request_id"] = request_id
	if str(receipt.get("status", "")) == STATUS_PENDING:
		_pending[request_id] = {
			"method": method,
			"keep_token": keep_token,
			"started_msec": Time.get_ticks_msec(),
			"windows_left": TIMEOUT_EXTRA_WINDOWS,
			"timeout_seconds": _timeout_for_method(method),
		}
		_arm_timeout(request_id)
	# Sync terminal receipts record nothing: no signal can follow them, so
	# remembering their ids would only grow the bookkeeping forever.
	return _public_receipt(receipt, keep_token)


func _on_native_event(raw: Variant) -> void:
	var outcome: Dictionary = _parse_receipt(raw)
	if outcome.is_empty():
		return
	var request_id: String = str(outcome.get("request_id", ""))
	if request_id.is_empty():
		return
	if _settled.has(request_id):
		return
	if not _pending.has(request_id):
		return
	var tracked: Dictionary = _pending[request_id]
	_pending.erase(request_id)
	_remember_settled(request_id)
	request_completed.emit(
		_public_receipt(outcome, bool(tracked.get("keep_token", false))))


## True when the native side exposes one bridge method. Android plugins
## are `JNISingleton`: their Java method registry is separate from
## Object's bound-method registry, so `has_method` never sees them. The
## engine documents `has_java_method` for that registry; when the actual
## native object exposes it, its verdict is authoritative for both
## dispatch and cancellation. iOS GDExtension and ordinary fakes expose
## no such oracle and keep the `has_method` check.
func _native_has_method(native: Object, method: String) -> bool:
	if native == null:
		return false
	if native.has_method("has_java_method"):
		var verdict: Variant = native.call("has_java_method", method)
		return typeof(verdict) == TYPE_BOOL and bool(verdict)
	return native.has_method(method)


func _native_reports_draining(request_id: String) -> bool:
	var native: Object = _require_native()
	if not _native_has_method(native, "moonlitCancelRequest"):
		return false
	var raw: Variant = native.call("moonlitCancelRequest", request_id)
	var answer: Dictionary = _parse_receipt(raw)
	return str(answer.get("status", "")) == STATUS_DRAINING


func _on_request_timeout(request_id: String) -> void:
	if _settled.has(request_id) or not _pending.has(request_id):
		return
	if _native_reports_draining(request_id):
		var tracked: Dictionary = _pending[request_id]
		var windows_left: int = int(tracked.get("windows_left", 0))
		if windows_left > 0:
			# The mutation is still draining: extend the deadline instead of
			# force-settling a request whose real outcome is on its way.
			tracked["windows_left"] = windows_left - 1
			_arm_timeout(request_id)
			return
		# Drained past the final window: force-settle the request. A late
		# native outcome is dropped by id below, and session truth always
		# comes from a fresh `get_session`, never from this stale request.
		_pending.erase(request_id)
		_remember_settled(request_id)
		request_completed.emit({
			"status": STATUS_ERROR,
			"code": CODE_REQUEST_TIMEOUT,
			"retryable": true,
			"request_id": request_id,
		})
		return
	# Pre-mutation the native side stopped too, but the request still ended
	# on a timeout, so it reports a timeout rather than a user cancel.
	_pending.erase(request_id)
	_remember_settled(request_id)
	request_completed.emit({
		"status": STATUS_ERROR,
		"code": CODE_REQUEST_TIMEOUT,
		"retryable": true,
		"request_id": request_id,
	})


func _remember_settled(request_id: String) -> void:
	if _settled.has(request_id):
		return
	_settled[request_id] = true
	_settled_order.append(request_id)
	while _settled_order.size() > SETTLED_CAP:
		var oldest: Variant = _settled_order.pop_front()
		_settled.erase(oldest)


func _arm_timeout(request_id: String) -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	# Draining extensions re-arm the window the request was given, never
	# the live globals: an override changed mid-flight must not stretch or
	# shrink a deadline this request already holds.
	var window: float = _request_timeout_seconds
	if _pending.has(request_id):
		window = float((_pending[request_id] as Dictionary).get(
			"timeout_seconds", _request_timeout_seconds))
	var timer: SceneTreeTimer = tree.create_timer(window)
	timer.timeout.connect(_on_request_timeout.bind(request_id))


func _new_request_id() -> String:
	_request_counter += 1
	var crypto: Crypto = Crypto.new()
	var salt: PackedByteArray = crypto.generate_random_bytes(4)
	return "mi-%d-%s" % [_request_counter, salt.hex_encode()]


func _parse_receipt(raw: Variant) -> Dictionary:
	if typeof(raw) == TYPE_DICTIONARY:
		return (raw as Dictionary).duplicate()
	if typeof(raw) != TYPE_STRING:
		return {}
	var parsed: Variant = JSON.parse_string(str(raw))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return (parsed as Dictionary).duplicate()


func _public_receipt(receipt: Dictionary,
		keep_token: bool = false) -> Dictionary:
	var clean: Dictionary = receipt.duplicate()
	# Defense in depth: even if a native build echoes secrets, they never
	# reach a signal, a save file, or a log from this layer — except the one
	# documented `id_token` field on this token call's own answer.
	var scrub: Array = ["auth_code", "server_auth_code", "email",
		"display_name", "full_name", "given_name", "family_name"]
	if not keep_token:
		scrub.append("id_token")
	for key in scrub:
		clean.erase(key)
	return clean


func _public_config_value(section: String, key: String) -> String:
	_ensure_config()
	var section_map: Variant = _config_cache.get(section, {})
	if typeof(section_map) != TYPE_DICTIONARY:
		return ""
	return str((section_map as Dictionary).get(key, "")).strip_edges()


func _inject_public_config(payload: Dictionary) -> void:
	_ensure_config()
	if _native_platform == "android":
		payload["server_client_id"] = \
			_public_config_value("google", "server_client_id")
		_inject_firebase_keys(payload, "android")
	elif _native_platform == "ios":
		payload["ios_client_id"] = \
			_public_config_value("google", "ios_client_id")
		_inject_firebase_keys(payload, "ios")


func _inject_firebase_keys(payload: Dictionary, platform: String) -> void:
	# Platform-resolved Firebase public client config. The natives use these
	# only to initialize Firebase when no configured app exists yet; when
	# the values are absent the calls gate out before reaching native code.
	payload["firebase_api_key"] = \
		_public_config_value("firebase", platform + "_api_key")
	payload["firebase_app_id"] = \
		_public_config_value("firebase", platform + "_app_id")
	payload["firebase_project_id"] = \
		_public_config_value("firebase", "project_id")
	payload["firebase_sender_id"] = \
		_public_config_value("firebase", "sender_id")


func _ensure_config() -> void:
	if _config_loaded:
		return
	_config_loaded = true
	_config_cache = {}
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var config: ConfigFile = ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	for section in ["google", "firebase", "apple"]:
		var section_map: Dictionary = {}
		var keys: Array[String] = []
		if section == "google":
			keys = ["server_client_id", "play_app_id", "ios_client_id"]
		elif section == "apple":
			keys = ["android_enabled", "ios_enabled"]
		else:
			keys = ["project_id", "sender_id",
				"android_api_key", "android_app_id", "ios_api_key",
				"ios_app_id"]
		for key in keys:
			var value: Variant = config.get_value(section, key, "")
			if typeof(value) == TYPE_STRING and not str(value).is_empty():
				section_map[key] = str(value).strip_edges()
		if not section_map.is_empty():
			_config_cache[section] = section_map


func _require_native() -> Object:
	if _native != null:
		return _native
	if Engine.has_singleton(ANDROID_SINGLETON_NAME):
		_native = Engine.get_singleton(ANDROID_SINGLETON_NAME)
		_native_platform = "android"
	elif ClassDB.class_exists(IOS_CLASS_NAME):
		_native = ClassDB.instantiate(IOS_CLASS_NAME)
		_native_platform = "ios"
	else:
		return null
	_connect_native_signal()
	return _native


func _connect_native_signal() -> void:
	if _native == null or _native_signal_connected:
		return
	if not _native.has_signal(NATIVE_SIGNAL_NAME):
		return
	_native.connect(NATIVE_SIGNAL_NAME, _on_native_event)
	_native_signal_connected = true


func _exit_tree() -> void:
	if _native != null and _native_signal_connected \
			and _native.has_signal(NATIVE_SIGNAL_NAME) \
			and _native.is_connected(
				NATIVE_SIGNAL_NAME, _on_native_event):
		_native.disconnect(NATIVE_SIGNAL_NAME, _on_native_event)
	_native_signal_connected = false
