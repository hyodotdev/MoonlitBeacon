extends Node

## Persistent production host: identity, cloud, saves, and entry wiring.
##
## One node that survives entry and Arena scene swaps (registered as the
## `ProductionHost` autoload) and joins the accepted foundations: a real
## PlayerAccount, the real NativeIdentityAdapter, the real CloudHttpSender,
## the real CloudCoordinator, and the Vault autoload. The production entry
## scene drives GateEntry through this host; the host never preloads or
## instantiates the Arena itself.
##
## Boot is lazy on purpose. `_ready` only constructs the service children
## (no files, no Journey repointing, no network), so scene-based regression
## suites that never start production are unaffected. The entry scene calls
## `startup()` once: mint the durable pre-play ID, hydrate the real SDK
## session, partition the Journey slot, and configure the coordinator when
## a cloud session exists. Tests and the exercise tool inject fakes through
## `inject_services()` instead; production never sees a fake.
##
## Money and conflict boundaries stay where the coordinator contract puts
## them: the host routes explicit player choices and never settles, merges,
## or overwrites. Tokens live in memory only and are never logged, saved,
## or returned in a state dictionary.

signal production_changed(state: Dictionary)
signal production_conflict(local: Dictionary, cloud: Dictionary)
signal production_hall(rows: Array, meta: Dictionary)
signal production_error(error: Dictionary)

const ACCOUNT_SCRIPT: Script = preload("res://scripts/net/player_account.gd")
const ADAPTER_SCRIPT: Script = preload(
	"res://scripts/net/native_identity_adapter.gd")
const SENDER_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_http_sender.gd")
const COORD_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_coordinator.gd")
const CLOUD_ACCOUNT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_account.gd")
const TRANSPORT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_transport.gd")
const SCHEMA_SCRIPT: Script = preload("res://scripts/cloud/cloud_schema.gd")
const FIREBASE_SCRIPT: Script = preload(
	"res://scripts/net/firebase_config.gd")

const ARENA_SCENE: String = "res://scenes/gameplay/arena.tscn"
const RELEASE_TAG: String = "4.0.0"
const TOKEN_REFRESH_MARGIN_SECONDS: float = 60.0
const TOKEN_WAIT_SECONDS: float = 15.0
## Bound on the initial empty-slot cloud check. The production sender answers
## every request within its own 10-second timeout, so this only bounds what
## the player sees; a late answer still lands and may surface installed bytes.
const RESTORE_TIMEOUT_SECONDS: float = 15.0
const DELETE_NATIVE_TIMEOUT_SECONDS: float = 30.0
const HALL_DEFAULT_LIMIT: int = 20

const PROVIDER_GOOGLE: String = "google"
const PROVIDER_APPLE: String = "apple"
const PROVIDER_PLAY_GAMES: String = "play_games"

## Retry-operation vocabulary: the actual last user-requested authentication
## operation, recorded at the boundary before the account call. Retry repeats
## exactly this operation; it never infers link intent from provider names or
## from the presence of a cloud session. `switch` dispatches sign-in-shaped,
## but only after that explicit operation.
const AUTH_OP_SIGN_IN: String = "sign_in"
const AUTH_OP_LINK: String = "link"
const AUTH_OP_SWITCH: String = "switch"

var _account: Node
var _adapter: Node
var _sender: Object
var _coordinator: Node
var _vault: Node
var _injected: Dictionary = {}
var _wired_account: Node
var _wired_coordinator: Node

var _started: bool = false
var _closing: bool = false
var _configured_uid: String = ""
var _token_uid: String = ""
var _planned_account: String = ""
var _id_token: String = ""
var _token_expires_at: float = 0.0
var _token_waiters: Array = []
var _draining: bool = false
var _draining_provider: String = ""
var _deletion_generation: int = 0
var _deletion_ticket: Dictionary = {}
var _deletion_waiters: Array = []
var _entry_in_flight: bool = false
## Initial empty-slot cloud check. Owned synchronously in `_adopted_canonical`
## before any deferred work or ready emission, so no tap can plan an entry
## between the coordinator going ready and the restore resolving. The ticket
## names the exact account and generation; only its terminal result unlocks
## the entry, and late results for anyone else change nothing.
var _restore_ticket: Dictionary = {}
var _restore_generation: int = 0
## One of `none`, `checking`, `failed`, `offline`. `failed` keeps blocking
## until an explicit retry or offline decision; `offline` is that decision.
var _restore_state: String = "none"
var _restore_code: String = ""
## Checkpoint-read claim. One fetch runs at a time, so retries can never
## stack parallel pulls. The counter is monotonic and never reset — the
## open slot below is what clears — so a retired completion can never
## match a newer account's outstanding claim the way a reused sequence
## would. Mirrors the coordinator's flush ticket.
var _restore_fetch_seq: int = 0
## The open claim's identity, or zero when no fetch is outstanding.
var _restore_fetch_open: int = 0
## Account whose initial check already resolved cleanly (installed bytes or
## authoritative not-found): duplicate ready callbacks for it start nothing.
var _restore_resolved: Dictionary = {}
var _auth_retry_done: bool = false
var _retry_operation: String = ""
var _retry_provider: String = ""
var _retry_uid_before: String = ""
var _retry_session_before: String = ""
var _last_hall_rows: Array = []
var _last_hall_meta: Dictionary = {}

var _boot_ticks: int = 0
var _startup_ticks: int = 0
var _first_paint_ticks: int = 0
var _handoff_ticks: int = 0
var _last_delete_commit: Dictionary = {}


func _init() -> void:
	_boot_ticks = Time.get_ticks_msec()


func _ready() -> void:
	_build_services()
	if get_tree() != null:
		get_tree().scene_changed.connect(_on_scene_changed)


func _exit_tree() -> void:
	shutdown()


## Replace service children with test doubles. Tests and the exercise tool
## only; production builds real services in `_build_services` and never
## calls this. Keys: `account`, `adapter`, `sender`, `coordinator`, `vault`.
## Tests may also narrow the two native wait deadlines (`clock` with a
## `now_msec()` method plus `delete_timeout_seconds` / `token_wait_seconds`);
## production never injects those and always waits on the real monotonic
## clock with the fixed constants below.
func inject_services(services: Dictionary) -> void:
	_injected = services.duplicate()
	_build_services()


## Monotonic milliseconds for wait deadlines. Only an injected test clock
## overrides the engine monotonic clock; production has no override.
func _clock_now_msec() -> int:
	var clock: Variant = _injected.get("clock", null)
	if clock != null and (clock as Object).has_method("now_msec"):
		return int((clock as Object).call("now_msec"))
	return Time.get_ticks_msec()


## Effective native-delete wait bound. Production always uses
## DELETE_NATIVE_TIMEOUT_SECONDS; tests may inject a shorter deadline.
func _delete_timeout_seconds() -> float:
	return float(_injected.get(
		"delete_timeout_seconds", DELETE_NATIVE_TIMEOUT_SECONDS))


## Effective token wait bound. Production always uses TOKEN_WAIT_SECONDS;
## tests may inject a shorter deadline.
func _token_wait_seconds_effective() -> float:
	return float(_injected.get(
		"token_wait_seconds", TOKEN_WAIT_SECONDS))


## Effective initial-restore bound. Production always uses
## RESTORE_TIMEOUT_SECONDS; tests may inject a shorter deadline.
func _restore_timeout_seconds_effective() -> float:
	return float(_injected.get(
		"restore_timeout_seconds", RESTORE_TIMEOUT_SECONDS))


## Retire everything owned. Late replies change nothing afterwards.
func shutdown() -> void:
	_closing = true
	if _coordinator != null and is_instance_valid(_coordinator):
		_coordinator.call("close")
	if _sender != null and is_instance_valid(_sender) \
			and _sender.has_method("close"):
		_sender.call("close")
	_configured_uid = ""
	_id_token = ""
	_token_expires_at = 0.0
	_token_uid = ""
	_deletion_ticket = {}
	_retire_restore()
	_clear_auth_retry()
	_fail_token_waiters()
	for waiter in _deletion_waiters:
		(waiter as Dictionary)["done"] = true
		(waiter as Dictionary)["ok"] = false
		(waiter as Dictionary)["code"] = "host_closed"


## Boot production: durable ID, SDK hydration, Journey partition, and cloud
## configuration when a cloud session exists. Idempotent. Returns the
## account state; refuses (without touching saves) while the ID is not
## durable.
func startup() -> Dictionary:
	_wire_signals()
	if _started:
		return account_state()
	_account.call("enable_fresh_guest_on_sign_out", true)
	var public_id: String = _account.call("ensure_public_id")
	if public_id.is_empty():
		return account_state()
	_started = true
	_startup_ticks = Time.get_ticks_msec()
	Journey.use_account(public_id)
	Journey.migrate_legacy_to_account(public_id)
	_account.call("refresh_session")
	_maybe_configure_cloud()
	production_changed.emit(account_state())
	return account_state()


## True once `startup()` landed a durable ID.
func is_started() -> bool:
	return _started


## Public account/save/cloud summary for the entry surface. Never carries
## a token. `cloud_uid` names the server identity the coordinator already
## reports; logs and debug probes use `has_cloud` instead.
func account_state() -> Dictionary:
	var base: Dictionary = _account.call("current_state")
	var public_id: String = str(base.get("public_id", ""))
	var ready: bool = bool(base.get("ready", false))
	var kind: String = str(base.get("kind", "local_guest"))
	var cloud_uid: String = str(base.get("cloud_uid", ""))
	var saved: Dictionary = saved_gate_summary()
	var coord: Dictionary = _coordinator.call("account_snapshot") \
		if _coordinator != null else {}
	var save: Dictionary = _coordinator.call("save_snapshot") \
		if _coordinator != null else {}
	var source: String = "unready"
	if ready and not cloud_uid.is_empty():
		source = "cloud"
	elif ready:
		source = "local"
	var restore_live: bool = _restore_ticket_live()
	return {
		"public_id": public_id,
		"ready": ready,
		"kind": kind,
		"cloud_uid": cloud_uid,
		"cloud_provider": str(base.get("cloud_provider", "")),
		"uid_bound": bool(base.get("uid_bound", false)),
		"source": source,
		"offline": _offline_now(),
		"draining": _draining,
		"draining_provider": _draining_provider,
		"deletion_in_flight": not _deletion_ticket.is_empty(),
		"entry_in_flight": _entry_in_flight,
		"has_save": bool(saved.get("has_save", false)),
		"restore_pending": restore_live and _restore_state == "checking",
		"restore_failed": restore_live and _restore_state == "failed",
		"restore_offline": restore_live and _restore_state == "offline",
		"restore_code": _restore_code if restore_live else "",
		"account": coord,
		"save": save,
	}


## Identity card data for GateEntry: full durable ID, hero, saved gate.
func identity_for_entry() -> Dictionary:
	var state: Dictionary = account_state()
	var saved: Dictionary = saved_gate_summary()
	var hero: Hero = saved.get("hero") as Hero
	var hero_name: String = ""
	if hero != null and not str(hero.display_name).is_empty():
		hero_name = tr(str(hero.display_name))
	return {
		"stable_id": str(state.get("public_id", "")),
		"hero": hero,
		"hero_name": hero_name,
		"saved_gate": {
			"has_save": bool(saved.get("has_save", false)),
			"title": str(saved.get("title", "")),
		},
		"source": str(state.get("source", "unready")),
	}


## Provider buttons the entry may show, from real adapter capabilities.
## Unknown capability shapes degrade to guest-only; nothing is invented.
func providers_for_entry() -> Array:
	var rows: Array = []
	if _adapter == null or not _adapter.has_method("get_capabilities"):
		return rows
	var caps: Variant = _adapter.call("get_capabilities")
	if typeof(caps) != TYPE_DICTIONARY:
		return rows
	var supported: bool = bool((caps as Dictionary).get("supported", false))
	for entry in (caps as Dictionary).get("providers", []):
		var provider_id: String = ""
		var ready: bool = supported
		var label: String = ""
		if typeof(entry) == TYPE_STRING:
			provider_id = str(entry)
		elif typeof(entry) == TYPE_DICTIONARY:
			provider_id = str((entry as Dictionary).get("id", ""))
			label = str((entry as Dictionary).get("label", ""))
			ready = supported \
				and bool((entry as Dictionary).get("ready", true))
		if provider_id.is_empty():
			continue
		if label.is_empty():
			label = provider_label(provider_id)
		rows.append({
			"id": provider_id,
			"label": label,
			"ready": ready and not _entry_in_flight,
			"draining": _draining and _draining_provider == provider_id,
		})
	return rows


## Honest display label for one provider id. Unknown ids show raw.
func provider_label(provider_id: String) -> String:
	match provider_id:
		PROVIDER_GOOGLE:
			return GateEntryStrings.text("gate.provider.google")
		PROVIDER_APPLE:
			return GateEntryStrings.text("gate.provider.apple")
		PROVIDER_PLAY_GAMES:
			return GateEntryStrings.text("gate.provider.play_games")
	return provider_id


## Local guest entry. Always usable once the ID is durable, with or without
## configuration: native anonymous registration starts only when the bridge
## genuinely supports it, and never blocks play. On desktop or missing
## configuration the guest plays locally with no registration attempt and
## no error. Returns the account state.
##
## `local_only` is the Error-screen escape: the durable local guest enters
## directly without starting (or repeating) the optional native anonymous
## registration. The pending (which covers a draining mutation) and
## deletion guards above still refuse first, so a mutation in flight
## cannot be bypassed. The default keeps the original first-selection
## behavior untouched.
func begin_guest(local_only: bool = false) -> Dictionary:
	if not _started:
		startup()
	var state: Dictionary = account_state()
	if not bool(state.get("ready", false)):
		return state
	if _account_has_pending():
		return state
	if not _deletion_ticket.is_empty():
		return account_state()
	if _cloud_session_present():
		# Already linked: retry a cloud setup whose token failed before.
		_maybe_configure_cloud()
		return account_state()
	if local_only:
		return account_state()
	if _adapter != null and _adapter.has_method("get_capabilities"):
		var caps: Variant = _adapter.call("get_capabilities")
		var supported: bool = false
		var guest_ok: bool = true
		if typeof(caps) == TYPE_DICTIONARY:
			supported = bool((caps as Dictionary).get(
				"supported", false))
			guest_ok = bool((caps as Dictionary).get("guest", true))
		if supported and guest_ok:
			_account.call("sign_in_guest")
	return account_state()


## True while a login request is in flight (native registration, provider
## sign-in/link, or token refresh). The entry shows its busy state from this.
func is_login_pending() -> bool:
	return _account_has_pending()


## Start a provider sign-in. Thin over PlayerAccount; terminal outcomes
## arrive on the production signals.
func begin_provider(provider_id: String) -> Dictionary:
	if not _deletion_ticket.is_empty():
		return _deletion_refusal()
	_record_auth_attempt(AUTH_OP_SIGN_IN, provider_id)
	return _account.call("sign_in_provider", provider_id)


## Link a provider onto the current guest. Never merges: a provider that
## is already linked elsewhere reports a conflict and keeps the guest.
func link_provider(provider_id: String) -> Dictionary:
	if not _deletion_ticket.is_empty():
		return _deletion_refusal()
	_record_auth_attempt(AUTH_OP_LINK, provider_id)
	return _account.call("link_current_provider", provider_id)


## Sign into a conflicting provider anyway, as an explicit switch. The
## guest's ID, binding, and save files stay on disk untouched; the new
## session only repoints the live account.
func switch_to_provider(provider_id: String) -> Dictionary:
	if not _deletion_ticket.is_empty():
		return _deletion_refusal()
	_record_auth_attempt(AUTH_OP_SWITCH, provider_id)
	return _account.call("sign_in_provider", provider_id)


## Remember the last user-requested authentication operation for Retry,
## plus the live session it started from. Recorded BEFORE the account
## call: synchronous outcomes arrive during it, and a synchronous success
## must clear through the move check instead of being overwritten by a
## record written after. A call that cannot start (a request already
## pending) leaves the live attempt's record untouched.
func _record_auth_attempt(operation: String, provider_id: String) -> void:
	if _account_has_pending():
		return
	_retry_operation = operation
	_retry_provider = provider_id
	_retry_uid_before = _account.call("cloud_uid")
	_retry_session_before = _account.call("cloud_provider")


## Drop the remembered Retry operation. Ordinary cancellation, terminal
## success, sign-out, and deletion call this; retryable failures keep the
## record so Retry can repeat the original operation.
func _clear_auth_retry() -> void:
	_retry_operation = ""
	_retry_provider = ""
	_retry_uid_before = ""
	_retry_session_before = ""


## While deletion owns the operation, starts and switches are retired
## with an explicit code instead of racing the ticket.
func _deletion_refusal() -> Dictionary:
	return {"status": "refused", "code": "deletion_in_flight",
		"retryable": true}


## Cancel the pending login. A draining answer keeps the lock: the entry
## shows a finishing state and the terminal outcome still lands. The entry
## names the provider it was busy with so the right row shows the lock.
func cancel_login(provider_id: String = "") -> Dictionary:
	var receipt: Dictionary = _account.call("cancel_pending")
	if str(receipt.get("status", "")) == "draining":
		_draining = true
		_draining_provider = provider_id
		production_changed.emit(account_state())
		return receipt
	# An ordinary cancellation retires the remembered operation with the
	# attempt: a later Retry must not resurrect it. A draining answer
	# keeps the record above, and its terminal outcome still lands.
	_clear_auth_retry()
	return receipt


## Retry the last provider attempt with its original operation: link after
## a link failure, sign-in after a sign-in failure, and a sign-in-shaped
## switch only after that explicit operation. Guest retry keeps its
## current semantics. Refuses while a request is draining or deletion
## owns the operation. A provider that does not match the remembered
## attempt is a stale UI event: it is refused without touching any
## account, and the entry repaints the honest state instead of sticking
## on busy. The matching record is retained, so a genuine Retry for the
## remembered provider still works afterwards.
func retry_login(provider_id: String) -> Dictionary:
	if _draining:
		return {"status": "draining", "request_id": "",
			"provider": provider_id}
	if not _deletion_ticket.is_empty():
		return _deletion_refusal()
	if provider_id.is_empty():
		return begin_guest()
	if _retry_operation.is_empty() \
			or _retry_provider != provider_id:
		production_changed.emit(account_state())
		return {"status": "refused", "code": "stale_retry",
			"retryable": false, "provider": provider_id}
	match _retry_operation:
		AUTH_OP_LINK:
			return link_provider(provider_id)
		AUTH_OP_SWITCH:
			return switch_to_provider(provider_id)
	return begin_provider(provider_id)


## Sign out to a fresh local guest. The old account's ID, binding, and
## save stay on disk; the new guest mints its own ID.
func sign_out() -> Dictionary:
	if not _deletion_ticket.is_empty():
		return _deletion_refusal()
	var receipt: Dictionary = _account.call("sign_out")
	# An effective sign-out retires the remembered operation with the old
	# account; a refusal (login in flight, identity not ready) keeps the
	# live attempt's record untouched.
	match str(receipt.get("status", "")):
		"ok", "pending", "cancelled":
			_clear_auth_retry()
	_on_account_env_changed()
	return receipt


## Synchronous token supplier for the coordinator. In-memory only; ""
## when signed out or retired. Never logged, saved, or returned.
func supply_token() -> String:
	if _id_token.is_empty():
		return ""
	if _token_expires_at > 0.0 and not _token_fresh():
		return ""
	return _id_token


## Refresh the in-memory token before wire work. Failed or offline refresh
## keeps local play and reports status; it never blocks the caller past
## its wait.
func ensure_token(force_refresh: bool = false) -> Dictionary:
	if not _cloud_session_present():
		return {"status": "ok", "token": false, "reason": "local-guest"}
	if not force_refresh and not _id_token.is_empty() and _token_fresh():
		return {"status": "ok", "token": true, "reason": "cached"}
	var receipt: Dictionary = _account.call("get_id_token", true)
	var status: String = str(receipt.get("status", ""))
	if status == "ok" and receipt.has("id_token"):
		_store_token(receipt)
		return {"status": "ok", "token": true, "reason": "sync"}
	if status != "pending":
		return {"status": status,
			"code": str(receipt.get("code", "token_error")),
			"token": false}
	return await _wait_for_token()


## Pull the public board and emit mapped Hall rows. Coordinator-owned
## cache, throttle, and source labels pass through untouched.
func request_hall(limit: int = HALL_DEFAULT_LIMIT) -> Dictionary:
	await ensure_token(false)
	if _coordinator == null:
		return hall_view()
	await _coordinator.call("refresh_board", limit)
	_emit_hall()
	return hall_view()


## Last mapped Hall view: real rows plus honest source meta.
func hall_view() -> Dictionary:
	return {"rows": _last_hall_rows.duplicate(true),
		"meta": _last_hall_meta.duplicate(true)}


## Refresh our own rank and push it to the Arena HUD when present.
func request_rank() -> Dictionary:
	await ensure_token(false)
	if _coordinator == null:
		return rank_view()
	await _coordinator.call("refresh_rank")
	_push_rank_to_hud()
	return rank_view()


## Current rank view for HUD/account surfaces.
func rank_view() -> Dictionary:
	if _coordinator == null:
		return {"state": "unregistered", "source": "unregistered",
			"rank": 0, "score": 0}
	return _coordinator.call("rank_snapshot")


## Explicit local/remote save choice from the conflict panel.
func resolve_save_choice(which: String) -> Dictionary:
	await ensure_token(false)
	if _coordinator == null:
		return {"status": "failure", "code": "no-cloud"}
	var choice: String = "remote" if which == "remote" else "local"
	var reply: Variant = await _coordinator.call(
		"resolve_conflict", choice)
	production_changed.emit(account_state())
	if typeof(reply) == TYPE_DICTIONARY:
		return reply
	return {"status": "failure", "code": "bad-reply"}


## Pull the cloud checkpoint. Installs only into an empty or identical
## slot; a differing local journey becomes an explicit conflict. While the
## initial empty-slot check owns the account, this joins it instead of
## firing a second pull: a fetch in flight is refused, a failed or
## offline-accepted check retries through the same settling path.
func restore_cloud() -> Dictionary:
	if _restore_ticket_live():
		if _restore_state == "checking" or _restore_fetch_open != 0:
			return {"status": "failure", "code": "restore-in-flight",
				"retryable": true}
		if _restore_state == "failed" or _restore_state == "offline":
			return await retry_cloud_restore()
	await ensure_token(false)
	if _coordinator == null:
		return {"status": "failure", "code": "no-cloud"}
	var reply: Variant = await _coordinator.call("restore_from_cloud")
	production_changed.emit(account_state())
	if typeof(reply) == TYPE_DICTIONARY:
		return reply
	return {"status": "failure", "code": "bad-reply"}


## Retry the initial empty-slot cloud check after a failure, or re-check
## after an explicit offline decision. Never touches authentication: it
## re-reads the checkpoint for the same account only, and refuses while a
## fetch is already outstanding so retries stack no parallel pulls. Every
## failure mode is retryable here, including a timed-out attempt whose
## orphaned read was retired; only a moved or retired account refuses
## outright. Outcomes land on the production signals; the returned reply
## is the terminal fetch result.
func retry_cloud_restore() -> Dictionary:
	if _closing or _coordinator == null:
		return {"status": "failure", "code": "no-cloud",
			"retryable": true}
	if not _restore_ticket_live():
		_retire_restore()
		return {"status": "refused", "code": "no_restore",
			"retryable": false}
	if _restore_state == "checking" or _restore_fetch_open != 0:
		return {"status": "refused", "code": "restore_in_flight",
			"retryable": true}
	if _restore_state != "failed" and _restore_state != "offline":
		return {"status": "refused", "code": "no_restore",
			"retryable": false}
	_restore_state = "checking"
	_restore_code = ""
	# Claimed before the first await: a second retry issued on the same
	# tick sees the in-flight refusal above, never a second pull.
	_restore_fetch_seq += 1
	var seq: int = _restore_fetch_seq
	_restore_fetch_open = seq
	production_changed.emit(account_state())
	_watch_restore_deadline(_restore_ticket, seq)
	return await _fetch_restore(_restore_ticket, seq)


## Explicit offline decision after a failed initial check: the player saw
## the failure and chooses to start fresh on this device anyway. Unlocks
## fresh planning without signing out — the UID, binding, and slot stay —
## and stays reversible: a later retry re-checks the same account.
func accept_offline_entry() -> Dictionary:
	if not _restore_ticket_live():
		_retire_restore()
		return {"status": "refused", "code": "no_restore",
			"retryable": false}
	if _restore_state == "checking" or _restore_fetch_open != 0:
		return {"status": "refused", "code": "restore_in_flight",
			"retryable": true}
	if _restore_state != "failed" and _restore_state != "offline":
		return {"status": "refused", "code": "no_restore",
			"retryable": false}
	_restore_state = "offline"
	_restore_code = ""
	production_changed.emit(account_state())
	return {"status": "ok", "code": "offline_accepted",
		"account_id": _account.call("public_id")}


## Upload the coalesced pending payload, if any.
func flush_saves() -> Dictionary:
	await ensure_token(false)
	if _coordinator == null:
		return {"status": "failure", "code": "no-cloud"}
	var reply: Variant = await _coordinator.call("flush")
	if typeof(reply) == TYPE_DICTIONARY:
		_maybe_refresh_auth((reply as Dictionary).get("code", ""))
		return reply
	return {"status": "failure", "code": "bad-reply"}


## What the saved gate holds: hero, wave, and display lines. Empty when no
## valid checkpoint exists. The hero resource loads only from an already
## validated checkpoint path, never from a raw string.
func saved_gate_summary() -> Dictionary:
	var data: Dictionary = Journey.read_checkpoint()
	if data.is_empty():
		return {"has_save": false}
	var info: Dictionary = Journey.summary(data)
	if info.is_empty():
		return {"has_save": false}
	var hero: Hero = load(str(info.get("hero_path", ""))) as Hero
	return {
		"has_save": true,
		"cycle": int(info.get("cycle", 1)),
		"zone_index": int(info.get("zone_index", 0)),
		"terrain": int(info.get("terrain", 0)),
		"level": int(info.get("level", 1)),
		"hero_path": str(info.get("hero_path", "")),
		"hero": hero,
		"journey_id": str(info.get("journey_id", "")),
		"checkpoint_id": int(info.get("checkpoint_id", 0)),
		"title": "",
	}


## Plan one Arena entry. Fresh over an existing save needs `confirmed`;
## resume needs a valid checkpoint; a second plan while one is in flight
## is refused. On success the Journey is armed and the caller loads the
## returned scene through the loading overlay.
func plan_entry(fresh: bool, confirmed: bool) -> Dictionary:
	if not _started or not _account.call("is_identity_ready"):
		return {"status": "refused", "code": "identity_not_ready"}
	if not _deletion_ticket.is_empty():
		return {"status": "refused", "code": "deletion_in_flight"}
	if _entry_in_flight:
		return {"status": "refused", "code": "entry_in_flight"}
	if _account_has_pending():
		return {"status": "refused", "code": "login_in_flight"}
	if _restore_blocks_entry():
		return {"status": "refused", "code": _restore_block_code()}
	var account_id: String = _account.call("public_id")
	var saved: Dictionary = saved_gate_summary()
	if fresh and bool(saved.get("has_save", false)) and not confirmed:
		return {"status": "refused", "code": "needs_confirmation"}
	if not fresh and not bool(saved.get("has_save", false)):
		return {"status": "refused", "code": "no_save"}
	if fresh:
		Journey.begin_fresh()
	else:
		Journey.begin_resume()
	RunEntry.mark_from_title()
	_entry_in_flight = true
	_planned_account = account_id
	production_changed.emit(account_state())
	return {"status": "ok", "arena": ARENA_SCENE, "fresh": fresh,
		"account_id": account_id,
		"hero_path": str(saved.get("hero_path", ""))}


## True when a planned entry may still swap: same plan, same account, and
## no login moved under it. The entry scene checks this before placing the
## loaded Arena, so a stale load can never enter as the wrong account.
func confirm_entry_account(account_id: String) -> bool:
	if not _entry_in_flight:
		return false
	if _account_has_pending():
		return false
	return not account_id.is_empty() \
		and account_id == _planned_account \
		and account_id == _account.call("public_id")


## Drop a planned entry before the scene swap (back/cancel). Disarms the
## Journey so a later tap plans cleanly.
func cancel_entry_plan() -> void:
	if not _entry_in_flight:
		return
	_entry_in_flight = false
	_planned_account = ""
	Journey.disarm()
	production_changed.emit(account_state())


## Release the in-flight hold after a load cancellation while keeping the
## Journey armed: the loader's retry re-plans the same entry, and only a
## planned entry may swap.
func release_entry_hold() -> void:
	_entry_in_flight = false
	_planned_account = ""
	production_changed.emit(account_state())


## Player-confirmed account deletion. Order is fixed: the owned cloud rows
## acknowledge deletion first, then the real native Auth deletion runs, and
## only then is the local slot removed. Any failure preserves recovery
## data and reports; a local-only guest (no cloud UID) skips the cloud
## step without sending anyone else's request.
##
## Native deletion is an operation with a genuine terminal result: a pending
## receipt is awaited (with a timeout), never treated as failure. A ticket
## carrying the account and generation is held across every await; any
## account move retires the run before the next destructive step, so a
## moved account can never delete or clean up a different account.
func delete_current_account() -> Dictionary:
	if not _started or not _account.call("is_identity_ready"):
		return {"status": "failure", "code": "identity_not_ready"}
	if not _deletion_ticket.is_empty():
		return {"status": "failure", "code": "deletion_in_flight",
			"retryable": true}
	if _entry_in_flight or _account_has_pending():
		return {"status": "failure", "code": "busy"}
	_deletion_generation += 1
	var ticket: Dictionary = {
		"uid": _account.call("cloud_uid"),
		"public_id": _account.call("public_id"),
		"generation": _deletion_generation,
	}
	_deletion_ticket = ticket
	production_changed.emit(account_state())
	var result: Dictionary = await _run_deletion(ticket)
	# Only the owning run releases its own lock: a late completion from a
	# timed-out run must never release a newer operation's ticket.
	if _deletion_ticket.get("generation", -1) == ticket["generation"]:
		_deletion_ticket = {}
	# A completed deletion retires the remembered operation with the
	# deleted account; a failed run keeps it for an honest retry.
	if str(result.get("status", "")) == "ok":
		_clear_auth_retry()
	production_changed.emit(account_state())
	return result


func _run_deletion(ticket: Dictionary) -> Dictionary:
	var public_id: String = str(ticket.get("public_id", ""))
	var cloud_uid: String = str(ticket.get("uid", ""))
	if not cloud_uid.is_empty():
		await ensure_token(true)
		if not _ticket_live(ticket):
			return {"status": "failure", "code": "account_moved",
				"retryable": true}
		var wiped: Dictionary = await _delete_owned_cloud_rows(
			cloud_uid, public_id, ticket)
		if str(wiped.get("status", "")) != "ok":
			return wiped
		if not _ticket_live(ticket):
			return {"status": "failure", "code": "account_moved",
				"retryable": true}
		var native: Dictionary = await _delete_native_account(ticket)
		if str(native.get("status", "")) != "ok":
			return native
		if not _ticket_live(ticket, true):
			return {"status": "failure", "code": "account_moved",
				"retryable": true}
		_account.call("forget_binding", cloud_uid)
	elif not _ticket_live(ticket):
		return {"status": "failure", "code": "account_moved",
			"retryable": true}
	_remove_account_slot(public_id)
	var rotated: Dictionary = _account.call("rotate_to_fresh_guest")
	if str(rotated.get("status", "")) != "ok":
		return rotated
	_on_account_env_changed()
	return {"status": "ok",
		"public_id": str(rotated.get("public_id", ""))}


## True while the ticket still names the live account. Before the native
## delete lands, the cloud UID must match; after it, an empty UID is the
## expected proof the SDK let go. The public ID must always match: any
## switch or rotation retires the run.
func _ticket_live(ticket: Dictionary, after_native: bool = false) -> bool:
	if _deletion_ticket.is_empty() \
			or _deletion_ticket.get("generation", -1) \
			!= ticket.get("generation", -2):
		return false
	if _account.call("public_id") != str(ticket.get("public_id", "")):
		return false
	var uid_now: String = _account.call("cloud_uid")
	if uid_now == str(ticket.get("uid", "")):
		return true
	return after_native and uid_now.is_empty() \
		and not str(ticket.get("uid", "")).is_empty()


## Run the real native Auth deletion to its genuine terminal result. Sync
## ok continues; pending is awaited with a timeout; anything else
## preserves the local slot and passes its code through for a truthful
## retry (including re-authentication when the SDK demands a recent
## login before the next attempt).
func _delete_native_account(ticket: Dictionary) -> Dictionary:
	var receipt: Dictionary = _account.call("delete_account", false)
	var status: String = str(receipt.get("status", ""))
	if status == "ok":
		return {"status": "ok"}
	if status == "cancelled":
		return {"status": "failure", "code": "delete_cancelled",
			"retryable": true}
	if status != "pending":
		return {"status": "failure",
			"code": str(receipt.get("code", "native_delete_failed")),
			"retryable": bool(receipt.get("retryable", true))}
	return await _wait_for_deletion(ticket)


func _wait_for_deletion(ticket: Dictionary) -> Dictionary:
	var waiter: Dictionary = {"done": false, "ok": false, "code": "",
		"retryable": true,
		"generation": int(ticket.get("generation", -1))}
	_deletion_waiters.append(waiter)
	# A monotonic wall-clock deadline, computed once: frame counts are
	# not elapsed time and must never stand in for it.
	var deadline_msec: int = _clock_now_msec() \
		+ int(_delete_timeout_seconds() * 1000.0)
	while _clock_now_msec() < deadline_msec:
		if bool(waiter.get("done", false)):
			break
		await get_tree().process_frame
	_deletion_waiters.erase(waiter)
	if bool(waiter.get("ok", false)):
		return {"status": "ok"}
	var code: String = str(waiter.get("code", ""))
	if code.is_empty():
		code = "deletion_timeout"
	return {"status": "failure", "code": code,
		"retryable": bool(waiter.get("retryable", true))}


## Release deletion waiters only for the owning generation. Late terminal
## outcomes from a timed-out run find no waiter and apply to the account
## normally without touching any newer lock.
func _release_deletion_waiters(ok: bool, code: String,
		retryable: bool) -> void:
	var active: int = int(_deletion_ticket.get("generation", -1))
	for waiter in _deletion_waiters.duplicate():
		if int((waiter as Dictionary).get("generation", -2)) != active:
			continue
		if bool((waiter as Dictionary).get("done", false)):
			# First terminal wins: the error's follow-up change must not
			# relabel the failure as a cancellation.
			continue
		(waiter as Dictionary)["done"] = true
		(waiter as Dictionary)["ok"] = ok
		(waiter as Dictionary)["code"] = code
		(waiter as Dictionary)["retryable"] = retryable


## A settled account change during deletion ends the native wait: the SDK
## let go (session gone) or the attempt was cancelled (session kept).
## Unsettled changes (a late coordinator adoption, a token answer) are
## not the delete's terminal and release nothing.
func _maybe_release_deletion_on_changed() -> void:
	if _deletion_ticket.is_empty() or _account_has_pending():
		return
	if _cloud_session_present():
		_release_deletion_waiters(false, "delete_cancelled", true)
	else:
		_release_deletion_waiters(true, "", true)


## First-paint tick from the entry scene's earliest process frame.
func note_first_paint() -> void:
	if _first_paint_ticks == 0:
		_first_paint_ticks = Time.get_ticks_msec()


## Debug-safe production snapshot: timings and state labels, no UID and
## never a token.
func debug_production_state() -> Dictionary:
	var state: Dictionary = account_state()
	return {
		"started": _started,
		"ready": bool(state.get("ready", false)),
		"has_cloud": not str(state.get("cloud_uid", "")).is_empty(),
		"source": str(state.get("source", "unready")),
		"offline": bool(state.get("offline", false)),
		"has_save": bool(state.get("has_save", false)),
		"entry_in_flight": _entry_in_flight,
		"deletion_in_flight": not _deletion_ticket.is_empty(),
		"restore": _restore_state if _restore_ticket_live() else "none",
		"draining": _draining,
		"boot_msec": _boot_ticks,
		"startup_msec": _startup_ticks,
		"first_paint_msec": _first_paint_ticks,
		"handoff_msec": _handoff_ticks,
		"account_state": str((state.get("account", {}) as Dictionary).get(
			"state", "unconfigured")),
		"save_state": str((state.get("save", {}) as Dictionary).get(
			"state", "unconfigured")),
	}


func _build_services() -> void:
	for child in [_account, _adapter, _coordinator]:
		if child != null and is_instance_valid(child):
			remove_child(child)
			child.queue_free()
	if _sender != null and is_instance_valid(_sender):
		if _sender is Node and (_sender as Node).get_parent() == self:
			remove_child(_sender)
			(_sender as Node).queue_free()
		_sender = null
	_account = null
	_adapter = null
	_coordinator = null
	_wired_account = null
	_wired_coordinator = null
	_account = _take_node_service("account", ACCOUNT_SCRIPT)
	_adapter = _take_node_service("adapter", ADAPTER_SCRIPT)
	_sender = _take_sender_service()
	_coordinator = _take_node_service("coordinator", COORD_SCRIPT)
	_wire_signals()
	_vault = _injected.get("vault", null)
	if _vault == null:
		_vault = get_node_or_null("/root/Vault")


func _take_node_service(key: String, script: Script) -> Node:
	if _injected.has(key) and _injected[key] is Node:
		var node: Node = _injected[key]
		if node.get_parent() == null:
			add_child(node)
		return node
	var fresh: Node = script.new() as Node
	add_child(fresh)
	return fresh


## The production sender is a Node; test doubles are RefCounteds with the
## same `send()` shape. Both work as a sender Callable.
func _take_sender_service() -> Object:
	if _injected.has("sender") and _injected["sender"] != null:
		var double: Object = _injected["sender"]
		if double is Node and (double as Node).get_parent() == null:
			add_child(double)
		return double
	var fresh: Node = SENDER_SCRIPT.new() as Node
	add_child(fresh)
	return fresh


func _wire_signals() -> void:
	if _account != null and _wired_account != _account:
		_wired_account = _account
		_account.setup(_adapter)
		_account.account_changed.connect(_on_account_changed)
		_account.account_conflict.connect(_on_account_conflict)
		_account.account_error.connect(_on_account_error)
		_account.id_token_ready.connect(_on_id_token_ready)
	if _coordinator != null and _wired_coordinator != _coordinator:
		_wired_coordinator = _coordinator
		_coordinator.account_changed.connect(_on_coordinator_account)
		_coordinator.save_changed.connect(_on_coordinator_save)
		_coordinator.conflict_found.connect(_on_coordinator_conflict)
		_coordinator.hall_changed.connect(_on_coordinator_hall)
		_coordinator.rank_changed.connect(_on_coordinator_rank)


func _on_account_changed(state: Dictionary) -> void:
	if _closing:
		return
	# A terminal success moves the live session (a new UID, or a new
	# session provider on a link that keeps the UID): the remembered
	# operation is done and retires. Failures, conflicts, and cancels
	# move nothing, so the record survives for Retry; cancellation
	# retires it explicitly in `cancel_login` instead.
	if not _retry_operation.is_empty() \
			and (str(state.get("cloud_uid", ""))
				!= _retry_uid_before
			or str(state.get("cloud_provider", ""))
				!= _retry_session_before):
		_clear_auth_retry()
	# Any terminal account outcome settles a draining lock: draining is a
	# cancel/timeout answer, never a state of its own.
	_draining = false
	_draining_provider = ""
	_on_account_env_changed()
	_maybe_release_deletion_on_changed()
	production_changed.emit(account_state())


func _on_account_conflict(conflict: Dictionary) -> void:
	if _closing:
		return
	_draining = false
	_draining_provider = ""
	_release_deletion_waiters(false, str(conflict.get("code", "")), true)
	var folded: Dictionary = conflict.duplicate()
	# A provider that is already linked elsewhere offers an explicit
	# switch; the guest and its save stay exactly where they are.
	folded["can_switch"] = str(conflict.get("code", "")) \
		== "already_linked_elsewhere"
	production_error.emit(folded)
	production_changed.emit(account_state())


func _on_account_error(error: Dictionary) -> void:
	if _closing:
		return
	_draining = false
	_draining_provider = ""
	_release_deletion_waiters(false, str(error.get("code", "")),
		bool(error.get("retryable", true)))
	production_error.emit(error.duplicate())
	production_changed.emit(account_state())


func _on_id_token_ready(token: Dictionary) -> void:
	if _closing:
		return
	_store_token(token)
	_release_token_waiters(true)
	production_changed.emit(account_state())


## The live account moved (sign-in, sign-out, switch, delete): retire the
## in-memory token, repoint the Journey slot, and reconfigure the cloud
## for the new session. Old slots and old replies stay untouched.
func _on_account_env_changed() -> void:
	var uid_now: String = _account.call("cloud_uid")
	if uid_now != _token_uid:
		# The cloud identity moved (sign-in, switch, sign-out): the old
		# token and its waiters belong to the previous account. Adoption
		# of the same UID keeps the live token.
		_id_token = ""
		_token_expires_at = 0.0
		_token_uid = uid_now
		_fail_token_waiters()
	_auth_retry_done = false
	# A moved account retires the initial cloud check with the old one;
	# adopting the same canonical id keeps the live check untouched.
	_retire_restore_unless_current()
	if _entry_in_flight:
		# The account moved under a planned entry: drop the plan so a
		# stale load can never swap as the wrong account.
		_entry_in_flight = false
		_planned_account = ""
		Journey.disarm()
	if not _started:
		return
	var public_id: String = _account.call("public_id")
	if public_id.is_empty():
		return
	Journey.use_account(public_id)
	Journey.migrate_legacy_to_account(public_id)
	_maybe_configure_cloud()


func _maybe_configure_cloud() -> void:
	if _coordinator == null or _vault == null:
		return
	var cloud_uid: String = _account.call("cloud_uid")
	if cloud_uid.is_empty():
		if not _configured_uid.is_empty():
			_retire_coordinator()
		return
	if cloud_uid == _configured_uid:
		return
	_configure_cloud_async(cloud_uid)


## Configure the coordinator once an in-memory token is held: the
## reservation runs on the first wire call, so configuring tokenless
## would fail closed before the refresh lands. Late completions for a
## moved-on account apply nothing.
func _configure_cloud_async(cloud_uid: String) -> void:
	await ensure_token(true)
	if _closing or _coordinator == null:
		return
	if cloud_uid != _account.call("cloud_uid"):
		return
	if cloud_uid == _configured_uid:
		return
	_retire_coordinator()
	var firebase: Dictionary = FIREBASE_SCRIPT.read()
	# Claimed before the call: a synchronous sender can finish the
	# reservation (and emit ready) from inside `configure_host`, and the
	# ready handler must already recognize this account. Cleared again
	# when the call itself refuses.
	_configured_uid = cloud_uid
	var reply: Dictionary = _coordinator.call("configure_host", {
		"uid": cloud_uid,
		"guest_public_id": _account.call("public_id"),
		"token_supplier": Callable(self, "supply_token"),
		"sender": Callable(_sender, "send"),
		"vault": _vault,
		"release": RELEASE_TAG,
		"web_api_key": str(firebase.get("web_api_key", "")),
	})
	if _closing:
		return
	if str(reply.get("status", "")) == "ok":
		return
	_configured_uid = ""
	production_error.emit({
		"status": "error",
		"code": str(reply.get("code", "cloud_configure_failed")),
		"retryable": false,
		"public_id": _account.call("public_id"),
	})
	production_changed.emit(account_state())


func _retire_coordinator() -> void:
	_configured_uid = ""
	if _coordinator == null:
		return
	_coordinator.call("close")
	if is_instance_valid(_coordinator):
		remove_child(_coordinator)
		_coordinator.queue_free()
	_coordinator = null
	# Tests that drive a switch inject a fresh coordinator per case through
	# `inject_services()`; production always builds a new one here.
	_coordinator = COORD_SCRIPT.new() as Node
	add_child(_coordinator)
	_wired_coordinator = null
	_wire_signals()


func _on_coordinator_account(snapshot: Dictionary) -> void:
	if _closing:
		return
	var snap: Dictionary = snapshot.duplicate()
	if str(snap.get("state", "")) != "ready":
		production_changed.emit(account_state())
		return
	var canonical: String = str(snap.get("public_id", ""))
	var uid: String = str(snap.get("uid", ""))
	if canonical.is_empty() or uid.is_empty() or uid != _configured_uid:
		production_changed.emit(account_state())
		return
	# The UID owns this canonical ID: adopt it durably. A differing local
	# binding is an explicit conflict, never a silent overwrite.
	var adopted: Dictionary = _account.call(
		"adopt_canonical_id", uid, canonical)
	if str(adopted.get("status", "")) == "conflict":
		production_error.emit({
			"status": "conflict",
			"code": "canonical_binding_differs",
			"known_id": str(adopted.get("known_id", "")),
			"canonical_id": canonical,
			"public_id": _account.call("public_id"),
		})
		production_changed.emit(account_state())
		return
	if str(adopted.get("status", "")) != "ok":
		production_error.emit({
			"status": "error",
			"code": str(adopted.get("code", "canonical_not_saved")),
			"retryable": true,
			"public_id": _account.call("public_id"),
		})
		production_changed.emit(account_state())
		return
	_adopted_canonical(canonical)
	production_changed.emit(account_state())


func _adopted_canonical(canonical: String) -> void:
	if _account.call("public_id") != canonical:
		return
	Journey.use_account(canonical)
	# A fresh device with no local checkpoint pulls the cloud state before
	# any start decision; a differing local journey becomes a conflict.
	# The check is owned synchronously here — before any deferred work or
	# ready emission — so no tap can plan between ready and the pull.
	if Journey.read_checkpoint().is_empty():
		_begin_initial_restore(canonical)
	else:
		ensure_token.call_deferred(false)
	_submit_best.call_deferred()
	request_rank.call_deferred()


## Own the initial empty-slot cloud check for this exact account. Runs
## synchronously inside the ready handler: the ticket is set before the
## `production_changed` emission at the end of it, which is what closes the
## ready-to-pull race. Duplicate ready callbacks for a live or already
## resolved check start nothing, and a local-only guest (no cloud UID)
## never checks. Returns false when no fetch was started.
func _begin_initial_restore(canonical: String) -> bool:
	var uid: String = _account.call("cloud_uid")
	if uid.is_empty():
		return false
	if _restore_ticket_live_for(uid, canonical):
		return false
	if _restore_resolved_for(uid, canonical):
		return false
	if not Journey.read_checkpoint().is_empty():
		return false
	_restore_generation += 1
	_restore_ticket = {
		"uid": uid,
		"public_id": canonical,
		"generation": _restore_generation,
	}
	_restore_state = "checking"
	_restore_code = ""
	# A live ticket implies no outstanding fetch, and the counter never
	# reuses an identity anyway, so this claim cannot collide with a
	# retired completion from any earlier account or generation.
	_restore_fetch_seq += 1
	var seq: int = _restore_fetch_seq
	_restore_fetch_open = seq
	_fetch_restore(_restore_ticket, seq)
	_watch_restore_deadline(_restore_ticket, seq)
	return true


## One checkpoint read for the owning ticket. Only a result that is still
## current — same ticket, same fetch, still checking — settles; anything
## else lands in `_adopt_late_restore`, which verifies the owner and then
## ignores it: a superseded read can neither grant nor change anything.
func _fetch_restore(ticket: Dictionary, seq: int) -> Dictionary:
	await ensure_token(false)
	if not _restore_fetch_current(ticket, seq):
		_release_restore_fetch(seq)
		return {"status": "cancelled", "code": "stale-reply",
			"retryable": false}
	if _coordinator == null:
		var missing: Dictionary = {"status": "failure", "code": "no-cloud",
			"retryable": true}
		_settle_initial_restore(ticket, seq, missing)
		return missing
	var reply: Variant = await _coordinator.call("restore_from_cloud")
	if not _restore_fetch_current(ticket, seq):
		_adopt_late_restore(ticket, reply)
		_release_restore_fetch(seq)
		return {"status": "cancelled", "code": "stale-reply",
			"retryable": false}
	var folded: Dictionary = {"status": "failure", "code": "bad-reply",
		"retryable": true}
	if typeof(reply) == TYPE_DICTIONARY:
		folded = reply
	_settle_initial_restore(ticket, seq, folded)
	return folded


## Elapsed bound on one check. Frames are not time: the deadline is real
## milliseconds on the monotonic clock (or the injected test clock). On
## expiry the attempt is retired before the failure lands, so the retry
## and offline doors the failure screen advertises act at once.
func _watch_restore_deadline(ticket: Dictionary, seq: int) -> void:
	var deadline_msec: int = _clock_now_msec() \
		+ int(_restore_timeout_seconds_effective() * 1000.0)
	while _clock_now_msec() < deadline_msec:
		if not _restore_fetch_current(ticket, seq):
			return
		await get_tree().process_frame
	if not _restore_fetch_current(ticket, seq):
		return
	_timeout_initial_restore(seq)


## Retire one timed-out attempt, then fail honestly with `restore_timeout`.
## The coordinator epoch kills the orphaned read first, so its late reply
## reports cancelled and can install nothing — not into this slot, not
## into a journey the player starts from the failure screen. Only then
## does the claim release, which is what makes the advertised retry and
## offline choice act while the orphan is still held. The ticket itself
## stays: the failure still blocks the entry until the player answers it.
func _timeout_initial_restore(seq: int) -> void:
	if _coordinator != null \
			and _coordinator.has_method("cancel_pending_restore"):
		_coordinator.call("cancel_pending_restore")
	_release_restore_fetch(seq)
	_fail_restore("restore_timeout")


## Settle the owning ticket with its terminal fetch result. Installed bytes
## and authoritative not-found both resolve cleanly — the former shows
## Continue, the latter unlocks a fresh start with no error. A conflict
## resolves to the conflict choice, which stays explicit. Every other
## failure keeps blocking with an honest retry and an explicit offline
## decision instead of pretending no save exists.
func _settle_initial_restore(ticket: Dictionary, seq: int,
		reply: Dictionary) -> void:
	if not _restore_fetch_current(ticket, seq):
		_adopt_late_restore(ticket, reply)
		_release_restore_fetch(seq)
		return
	_release_restore_fetch(seq)
	var status: String = str(reply.get("status", ""))
	var code: String = str(reply.get("code", ""))
	if status == "ok" or status == "conflict":
		_resolve_restore_clean()
	elif status == "failure" and code == "not-found":
		_resolve_restore_clean()
	elif code.is_empty():
		_fail_restore("restore-failed")
	else:
		_fail_restore(code)


## A fetch result that arrived after its attempt stopped being current.
## Verified against the owning ticket and generation — a relogin to the
## same UID and public ID still carries a newer generation — and then
## ignored unconditionally. The coordinator epoch already preempted the
## orphaned read, so by the time anything lands here it reports
## cancelled; either way a superseded read can neither install, unlock,
## resolve, fail, nor re-fail the live ticket, and a returning account
## re-reads for itself instead of inheriting the old answer.
func _adopt_late_restore(ticket: Dictionary, reply: Variant) -> void:
	if typeof(reply) != TYPE_DICTIONARY:
		return
	if _restore_ticket.is_empty() or not _restore_ticket_live():
		return
	if int(ticket.get("generation", -1)) != _restore_generation:
		return
	if str(ticket.get("uid", "")) \
			!= str(_restore_ticket.get("uid", "")):
		return
	if str(ticket.get("public_id", "")) \
			!= str(_restore_ticket.get("public_id", "")):
		return


## The initial check resolved terminally: installed bytes, authoritative
## not-found, or an explicit conflict choice. Remember the account so
## duplicate ready callbacks never restart the block.
func _resolve_restore_clean() -> void:
	if not _restore_ticket.is_empty():
		_restore_resolved = {
			"uid": str(_restore_ticket.get("uid", "")),
			"public_id": str(_restore_ticket.get("public_id", "")),
		}
	_restore_ticket = {}
	_restore_state = "none"
	_restore_code = ""
	production_changed.emit(account_state())


## The initial check failed without an answer. Keeps blocking the entry
## and reports honestly: a `save_check_failed` error carrying the real
## reason, with retry and the explicit offline decision both available.
func _fail_restore(code: String) -> void:
	if _restore_ticket.is_empty():
		return
	_restore_state = "failed"
	_restore_code = code
	production_error.emit({
		"status": "error",
		"code": "save_check_failed",
		"reason": code,
		"retryable": true,
		"public_id": _account.call("public_id"),
	})
	production_changed.emit(account_state())


## Retire the initial check outright. Late fetches find no ticket and
## change nothing; the next adoption for the same account starts over
## with a newer generation and a never-reused fetch identity. The claim
## counter is deliberately not reset.
func _retire_restore() -> void:
	_restore_ticket = {}
	_restore_state = "none"
	_restore_code = ""
	_restore_resolved = {}
	_restore_fetch_open = 0
	_restore_generation += 1


## Retire the check only when the live account moved away from it.
## Sign-out, switch, and deletion rotation retire; adopting the same
## canonical id keeps the live check and its resolution untouched.
func _retire_restore_unless_current() -> void:
	if _restore_ticket.is_empty() and _restore_resolved.is_empty():
		return
	var uid_now: String = _account.call("cloud_uid")
	var id_now: String = _account.call("public_id")
	if not _restore_ticket.is_empty():
		if str(_restore_ticket.get("uid", "")) != uid_now \
				or str(_restore_ticket.get("public_id", "")) != id_now:
			_retire_restore()
			return
	if not _restore_resolved.is_empty():
		if str(_restore_resolved.get("uid", "")) != uid_now \
				or str(_restore_resolved.get("public_id", "")) != id_now:
			_restore_resolved = {}


## True while the ticket still names the live account and generation.
func _restore_ticket_live() -> bool:
	if _restore_ticket.is_empty():
		return false
	if int(_restore_ticket.get("generation", -1)) != _restore_generation:
		return false
	return str(_restore_ticket.get("uid", "")) \
		== _account.call("cloud_uid") \
		and str(_restore_ticket.get("public_id", "")) \
		== _account.call("public_id")


## True while the live ticket is exactly this account's check.
func _restore_ticket_live_for(uid: String, canonical: String) -> bool:
	return _restore_ticket_live() \
		and str(_restore_ticket.get("uid", "")) == uid \
		and str(_restore_ticket.get("public_id", "")) == canonical


## True when this account's initial check already resolved cleanly.
func _restore_resolved_for(uid: String, canonical: String) -> bool:
	return not _restore_resolved.is_empty() \
		and str(_restore_resolved.get("uid", "")) == uid \
		and str(_restore_resolved.get("public_id", "")) == canonical


## True while this exact fetch still owns the live ticket's check.
func _restore_fetch_current(ticket: Dictionary, seq: int) -> bool:
	if not _restore_ticket_live():
		return false
	if int(ticket.get("generation", -1)) != _restore_generation:
		return false
	if seq == 0 or seq != _restore_fetch_open:
		return false
	return _restore_state == "checking"


## Release one fetch claim. Only the open claim releases: the counter is
## never reused, so a late completion from a retired attempt or
## generation can never free a newer fetch — not even for the same UID.
func _release_restore_fetch(seq: int) -> void:
	if seq != 0 and seq == _restore_fetch_open:
		_restore_fetch_open = 0


## True while the entry must wait on the initial cloud check: a fetch in
## flight, or a failure nobody has answered yet. An explicit offline
## decision and a clean resolution both stop blocking.
func _restore_blocks_entry() -> bool:
	if not _restore_ticket_live():
		return false
	return _restore_state == "checking" or _restore_state == "failed"


## Honest refusal code for the blocked entry: still checking, or failed
## and waiting on the player's retry-or-offline choice.
func _restore_block_code() -> String:
	if _restore_state == "failed":
		return "cloud_restore_unresolved"
	return "cloud_restore_pending"


func _on_coordinator_save(snapshot: Dictionary) -> void:
	if _closing:
		return
	var snap: Dictionary = snapshot.duplicate()
	_maybe_refresh_auth(str(snap.get("code", "")))
	if str(snap.get("state", "")) == "acked":
		_submit_best.call_deferred()
	production_changed.emit(account_state())


func _on_coordinator_conflict(_info: Dictionary) -> void:
	if _closing:
		return
	var snap: Dictionary = _coordinator.call("conflict_snapshot")
	var local: Dictionary = (snap.get("local_summary", {}) as Dictionary
		).duplicate()
	var remote: Dictionary = (snap.get("remote_summary", {}) as Dictionary
		).duplicate()
	production_conflict.emit(
		_conflict_option(local, "gate.conflict.local_tag"),
		_conflict_option(remote, "gate.conflict.cloud_tag"))
	production_changed.emit(account_state())


func _on_coordinator_hall(_snapshot: Dictionary) -> void:
	if _closing:
		return
	_emit_hall()


func _on_coordinator_rank(_snapshot: Dictionary) -> void:
	if _closing:
		return
	_push_rank_to_hud()


func _conflict_option(summary: Dictionary, tag_key: String) -> Dictionary:
	var gate_text: String = str(summary.get("gate", ""))
	var cycles: int = int(summary.get("cycles", 0))
	var detail: String = ""
	if not gate_text.is_empty():
		detail = gate_text
	if cycles > 0:
		var cycle_text: String = "%d" % cycles
		detail = cycle_text if detail.is_empty() \
			else "%s · %s" % [detail, cycle_text]
	var revision: int = int(summary.get("revision", 0))
	if revision > 0:
		var rev_text: String = "rev %d" % revision
		detail = rev_text if detail.is_empty() \
			else "%s · %s" % [detail, rev_text]
	return {
		"title": GateEntryStrings.text(tag_key),
		"detail": detail,
		"updated": str(summary.get("updated_at", "")),
	}


func _submit_best() -> void:
	if _coordinator == null or _configured_uid.is_empty():
		return
	if not _cloud_session_present():
		return
	await ensure_token(false)
	if _coordinator == null or not is_instance_valid(_coordinator):
		return
	await _coordinator.call("submit_current_best")
	_push_rank_to_hud()


func _store_token(receipt: Dictionary) -> void:
	_id_token = str(receipt.get("id_token", ""))
	_token_expires_at = float(receipt.get("token_expires_at", 0))
	_token_uid = _account.call("cloud_uid")


func _token_fresh() -> bool:
	if _id_token.is_empty():
		return false
	if _token_expires_at <= 0.0:
		return true
	var now_seconds: float = Time.get_unix_time_from_system()
	return _token_expires_at / 1000.0 - now_seconds \
		> TOKEN_REFRESH_MARGIN_SECONDS


func _wait_for_token() -> Dictionary:
	var waiter: Dictionary = {"done": false, "ok": false}
	_token_waiters.append(waiter)
	# Same monotonic-deadline contract as the deletion wait: the bound
	# is elapsed milliseconds, not frames.
	var deadline_msec: int = _clock_now_msec() \
		+ int(_token_wait_seconds_effective() * 1000.0)
	while _clock_now_msec() < deadline_msec:
		if bool(waiter.get("done", false)):
			break
		await get_tree().process_frame
	_token_waiters.erase(waiter)
	if bool(waiter.get("ok", false)) and not _id_token.is_empty():
		return {"status": "ok", "token": true, "reason": "refreshed"}
	return {"status": "error", "code": "token_timeout", "token": false}


func _release_token_waiters(ok: bool) -> void:
	for waiter in _token_waiters:
		(waiter as Dictionary)["done"] = true
		(waiter as Dictionary)["ok"] = ok


func _fail_token_waiters() -> void:
	_release_token_waiters(false)


func _cloud_session_present() -> bool:
	return _account != null and bool(_account.call("is_cloud_linked"))


func _account_has_pending() -> bool:
	if _account == null:
		return false
	var pending: Dictionary = _account.call("pending_request")
	return bool(pending.get("pending", false))


func _offline_now() -> bool:
	if _coordinator == null:
		return false
	var coord: Dictionary = _coordinator.call("account_snapshot")
	var save: Dictionary = _coordinator.call("save_snapshot")
	return str(coord.get("state", "")) == "offline" \
		or str(save.get("state", "")) == "offline"


func _emit_hall() -> void:
	if _coordinator == null:
		_last_hall_rows = []
		_last_hall_meta = {"cached": false, "offline": _offline_now()}
		production_hall.emit(_last_hall_rows, _last_hall_meta)
		return
	var snap: Dictionary = _coordinator.call("hall_snapshot")
	var source: String = str(snap.get("source", "unregistered"))
	_last_hall_rows = _map_hall_rows(
		snap.get("rows", []) as Array)
	_last_hall_meta = {
		"cached": source == "cache" or source == "cache-throttled" \
			or source == "stale",
		"offline": source == "offline" or _offline_now(),
		"source": source,
		"state": str(snap.get("state", "unregistered")),
	}
	production_hall.emit(
		_last_hall_rows.duplicate(true), _last_hall_meta.duplicate(true))


## Map coordinator rows to Hall panel rows. Hero art loads only from the
## owned allowlist; unknown heroes show score and full ID with no portrait
## rather than an invented one. No seeded rows, ever.
##
## Standings are competition ranks ("1, 2, 2, 4"): equal scores share one
## standing, exactly like the backend's count of strictly greater scores
## plus one, so the Hall and the own-rank label agree on ties.
func _map_hall_rows(rows: Array) -> Array:
	var mapped: Array = []
	var position: int = 0
	var standing: int = 0
	var last_score: int = -1
	for entry in rows:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		position += 1
		var row: Dictionary = entry
		var score: int = int(row.get("score", 0))
		if score != last_score:
			standing = position
			last_score = score
		var hero_ref: String = str(row.get("hero", ""))
		var hero_path: String = str((SCHEMA_SCRIPT.HERO_SHORT_IDS as Dictionary).get(
			hero_ref, hero_ref))
		var hero: Hero = null
		if hero_path in SCHEMA_SCRIPT.HERO_PATHS:
			hero = load(hero_path) as Hero
		mapped.append({
			"rank": standing,
			"score": score,
			"id": str(row.get("public_id", "")),
			"hero": hero,
			"hero_name": "",
		})
	return mapped


func _push_rank_to_hud() -> void:
	var view: Dictionary = rank_view()
	var rank: int = int(view.get("rank", 0))
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for hud in tree.get_nodes_in_group("moonlit_hud"):
		if rank <= 0:
			hud.call("clear_cloud_rank")
		else:
			hud.call("set_cloud_rank", "#%d · %s" % [
				rank, _rank_source_label(
					str(view.get("source", "unregistered")))])


func _rank_source_label(source: String) -> String:
	match source:
		"live":
			return GateEntryStrings.text("gate.rank.live")
		"cache", "cache-throttled", "stale":
			return GateEntryStrings.text("gate.rank.cached")
		"offline":
			return GateEntryStrings.text("gate.rank.offline")
	return GateEntryStrings.text("gate.rank.unregistered")


## Delete our four owned cloud rows (Hall, checkpoint, reservation, and
## profile) in ONE atomic `documents:commit` through the owned CloudAccount
## helper on the real transport. The live owned-cloud rules require the
## profile and reservation halves to go together with the Hall row already
## gone; sequential DELETEs are denied there, so the single commit is the
## only shape that can complete. Missing rows are server no-ops, which
## keeps a repeat after a crash or a failure safe.
##
## The ticket is checked before the commit starts and again after its
## acknowledgement: a moved account sends nothing more, and anything but
## an acknowledged commit stops the run with local data preserved. The
## exact request is recorded for `last_delete_commit_evidence()` either
## way, so the wire shape stays inspectable after every run.
func _delete_owned_cloud_rows(uid: String, public_id: String,
		ticket: Dictionary) -> Dictionary:
	if not _ticket_live(ticket):
		return {"status": "failure", "code": "account_moved",
			"retryable": true}
	var transport: RefCounted = TRANSPORT_SCRIPT.new()
	var firebase: Dictionary = FIREBASE_SCRIPT.read()
	transport.call("configure", FIREBASE_SCRIPT.PROJECT_ID,
		str(firebase.get("web_api_key", "")),
		Callable(self, "supply_token"), Callable(_sender, "send"))
	transport.call("set_account_uid", uid)
	var helper: RefCounted = CLOUD_ACCOUNT_SCRIPT.new()
	var reply: Dictionary = await helper.call("delete_account_data",
		transport, uid, public_id)
	_last_delete_commit = delete_commit_request(uid, public_id)
	_last_delete_commit["reply_status"] = str(reply.get("status", ""))
	_last_delete_commit["reply_code"] = str(reply.get("code", ""))
	if not _ticket_live(ticket):
		return {"status": "failure", "code": "account_moved",
			"retryable": true}
	if str(reply.get("status", "")) != "ok":
		return {"status": "failure",
			"code": str(reply.get("code", "cloud_delete_failed")),
			"failed_step": "commit",
			"retryable": bool(reply.get("retryable", true)),
			"remaining": reply.get("remaining", [])}
	return {"status": "ok"}


## The exact deletion commit account removal sends, built by the same
## CloudAccount helper the run uses, without sending it: method, relative
## path, JSON body, and the four owned document names in commit order.
## The director replays this shape against the real Firebase emulator.
static func delete_commit_request(uid: String,
		public_id: String) -> Dictionary:
	var body: Dictionary = CLOUD_ACCOUNT_SCRIPT.deletion_commit_body(
		uid, public_id)
	var names: Array = []
	for write in (body.get("writes", []) as Array):
		names.append(str((write as Dictionary).get("delete", "")))
	return {"method": "POST", "relative_path": "documents:commit",
		"body": JSON.stringify(body), "documents": names}


## The last deletion commit actually attempted: the exact request shape
## plus the acknowledgement it received. Empty before the first run.
func last_delete_commit_evidence() -> Dictionary:
	return _last_delete_commit.duplicate(true)


func _remove_account_slot(public_id: String) -> void:
	var paths: Array[String] = [
		Journey.account_main_path(public_id),
		Journey.account_backup_path(public_id),
		Journey.account_revision_path(public_id),
		Journey.account_rejected_path(public_id, "local"),
		Journey.account_rejected_path(public_id, "remote"),
	]
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path))


## A 401/403 from the wire means the token died: refresh once and let the
## next explicit flush retry. Local play never waits on this.
func _maybe_refresh_auth(code: Variant) -> void:
	if str(code) != "permission-denied" or _auth_retry_done:
		return
	if not _cloud_session_present():
		return
	_auth_retry_done = true
	ensure_token.call_deferred(true)


func _on_scene_changed() -> void:
	var scene: Node = get_tree().current_scene
	if scene != null \
			and scene.scene_file_path == ARENA_SCENE:
		_entry_in_flight = false
		_planned_account = ""
		_handoff_ticks = Time.get_ticks_msec()
		_push_rank_to_hud()
