extends Node

## Narrow boundary between the player-account service and native sign-in SDKs.
##
## On device this is `NativeIdentityAdapter` over the MoonlitIdentity bridge;
## regression tests inject `FakeIdentityAdapter`. The game never sees
## Google / Play Games / Apple / Firebase shapes, only small validated
## Dictionaries.
##
## Provider ids are platform-independent: `google` is the shared Firebase
## `google.com` identity on Android and iOS (one Google account, one
## provider), `apple` is the shared Firebase `apple.com` identity on both,
## and `play_games` is the distinct Android-only Play Games v2 gaming
## profile (`playgames.google.com`), never merged with `google.com`.
##
## Every mutating call is a command that returns a receipt at once. A receipt
## is one of:
## - `{"status": "ok", ...}` — settled synchronously.
## - `{"status": "pending", "request_id": "..."}` — the terminal outcome
##   arrives later on `session_changed` / `operation_failed`, correlated by
##   the same `request_id`.
## - `{"status": "conflict", ...}` — the provider account is already linked
##   to a different player. The caller must ask the user; nothing is merged.
## - `{"status": "cancelled" | "error" | "unsupported" | "not_configured",
##   "code": "...", ...}` — settled without changing the account.
## - `{"status": "draining", "request_id": "..."}` — only from `cancel()`: an
##   irreversible native mutation already began, so the lock stays and the
##   terminal outcome still arrives on the signals. Never treated as settled.
##
## No method here ever prints, logs, or stores an ID token, auth code, email,
## or display name. Those values travel only inside the native SDK calls.

signal session_changed(session: Dictionary)
signal operation_failed(error: Dictionary)

const STATUS_OK: String = "ok"
const STATUS_PENDING: String = "pending"
const STATUS_CANCELLED: String = "cancelled"
const STATUS_CONFLICT: String = "conflict"
const STATUS_ERROR: String = "error"
const STATUS_UNSUPPORTED: String = "unsupported"
const STATUS_NOT_CONFIGURED: String = "not_configured"
const STATUS_DRAINING: String = "draining"

const KIND_LOCAL_GUEST: String = "local_guest"
const KIND_CLOUD: String = "cloud"

const PROVIDER_GOOGLE: String = "google"
const PROVIDER_PLAY_GAMES: String = "play_games"
const PROVIDER_APPLE: String = "apple"
const PROVIDER_ANONYMOUS: String = "anonymous"

const CODE_USER_CANCELLED: String = "user_cancelled"
const CODE_ALREADY_LINKED_ELSEWHERE: String = "already_linked_elsewhere"
const CODE_NATIVE_MISSING: String = "native_bridge_unavailable"
const CODE_NOT_CONFIGURED: String = "identity_not_configured"
const CODE_NETWORK: String = "network_error"
const CODE_TOKEN_EXPIRED: String = "token_expired"
const CODE_TOKEN_REVOKED: String = "token_revoked"
const CODE_STALE_CALLBACK: String = "stale_callback"
const CODE_REQUEST_TIMEOUT: String = "request_timeout"
const CODE_NO_PENDING_REQUEST: String = "no_pending_request"
const CODE_ALREADY_PENDING: String = "request_already_pending"


func get_capabilities() -> Dictionary:
	return {
		"status": STATUS_UNSUPPORTED,
		"code": CODE_NATIVE_MISSING,
		"supported": false,
		"providers": [],
		"guest": true,
	}


func sign_in_guest() -> Dictionary:
	return _unsupported_receipt()


func sign_in_provider(_provider: String, _options: Dictionary = {}) -> Dictionary:
	return _unsupported_receipt()


func link_provider(_provider: String, _options: Dictionary = {}) -> Dictionary:
	return _unsupported_receipt()


func get_session() -> Dictionary:
	return {
		"status": STATUS_OK,
		"kind": KIND_LOCAL_GUEST,
		"uid": "",
		"provider": "",
	}


## Re-read the native session (an SDK-restored sign-in after a process
## restart) and fold it into the cached snapshot through the same outcome
## path as any other call: a sync answer applies at once, a `pending`
## receipt settles later on `session_changed` / `operation_failed`. Never
## starts a provider sign-in and never shows UI. `get_session()` stays a
## pure memory snapshot because it is called inside signal emission, where
## a native query would recurse. The base adapter has no native side, so
## the snapshot is already the truth and is returned as-is.
func refresh_native_session() -> Dictionary:
	return get_session()


func get_id_token(_force_refresh: bool = false) -> Dictionary:
	return _unsupported_receipt()


func sign_out() -> Dictionary:
	return _unsupported_receipt()


func delete_account(_options: Dictionary = {}) -> Dictionary:
	return _unsupported_receipt()


func cancel(_request_id: String) -> Dictionary:
	return {
		"status": STATUS_ERROR,
		"code": CODE_NO_PENDING_REQUEST,
	}


func _unsupported_receipt() -> Dictionary:
	return {
		"status": STATUS_UNSUPPORTED,
		"code": CODE_NATIVE_MISSING,
	}
