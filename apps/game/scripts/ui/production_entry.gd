class_name ProductionEntry
extends Control

## The production main entry: original title first, gate over it.
##
## First paint is the original title scene (diorama, tap prompt, small
## menu doors, all its own). A tap opens the GateEntry login selection
## over that same title; ProductionHost answers with real work. This
## scene only wires the two, plus the approved title BGM flow, the
## new-journey confirmation, and the back/exit/cancel unwind. The title
## owns its menus (Shrine, Shop/IAP, Settings, Credits, Chronicle,
## Ladder) natively; the gate keeps no second set. It preloads
## no Arena and instantiates none before the first entry paint: the Arena
## loads only through the embedded loading overlay after a tap.
##
## Scene swaps are generation-guarded: a finished load swaps only when its
## token is still the loader's current one, its path is the planned one,
## and the host confirms the planned account. Stale completions are
## ignored; the host is asked to wait out the loader's pending drain
## before the swap frees it.

const ExternalLinks := preload("res://scripts/ui/external_links.gd")

## Approved title BGM flow, mirrored from the old title: a short rest, a
## quick rise to the same target, a fade that finishes before the swap.
const BGM_VOLUME_DB: float = -9.0
const BGM_SILENCE_DB: float = -60.0
const BGM_START_DELAY_SECONDS: float = 0.15
const BGM_FADE_IN_SECONDS: float = 0.9
const BGM_FADE_OUT_SECONDS: float = 0.55
## Bound on the pre-swap drain wait: the loader drains without blocking,
## so this only yields frames while cancelled work is still landing.
const DRAIN_WAIT_MAX_FRAMES: int = 90

## Untyped on purpose: the title script carries no class name, so the
## external-start calls below stay dynamically dispatched.
@onready var _title = $Title
@onready var _entry: GateEntry = $Gate
@onready var _bgm: AudioStreamPlayer = $Bgm
@onready var _sfx: AudioStreamPlayer = $Sfx

var _host_override: Node = null
var _paint_noted: bool = false
var _swapping: bool = false
var _load_path: String = ""
var _load_account: String = ""
var _load_fresh: bool = false
var _fresh_confirmed: bool = false
var _busy_provider: String = ""
var _error_hold: String = ""
var _failed_public_id: String = ""
var _failed_cloud_uid: String = ""
var _failed_cloud_provider: String = ""
var _guest_chosen: bool = false
var _confirm_card: PanelContainer = null
var _hall_seq: int = 0
var _hall_live_seq: int = 0


## Tests and the exercise tool drive the entry against an injected host.
func set_host_override(host: Node) -> void:
	_host_override = host


func _host() -> Node:
	if _host_override != null:
		return _host_override
	return get_node_or_null("/root/ProductionHost")


func _ready() -> void:
	GateEntryStrings.ensure_loaded()
	_wire_entry()
	_wire_panels()
	_build_confirm()
	# First paint is the title at rest: the gate parks its card and its
	# painted backdrop, keeping only the hero forecourt over the title
	# diorama. A tap opens the selection (or the restored identity card)
	# through `_on_title_start`. The title consumes open-shop/shrine
	# handoff requests natively in its own `_ready`, which ran first.
	_entry.set_backdrop_visible(false)
	_entry.show_title_rest()
	_title.set_external_start(true)
	_title.external_start_requested.connect(_on_title_start)
	_title.external_hall_requested.connect(_on_hall)
	var host: Node = _host()
	if host == null:
		_fade_in_music()
		return
	host.startup()
	_wire_host(host)
	_entry.set_reduced_motion(bool(Settings.reduced_motion))
	# Provider data loads at boot so the doors exist before the tap;
	# the parked guard inside keeps the first paint title-only.
	_refresh_identity()
	_fade_in_music()


func _process(_delta: float) -> void:
	if not _paint_noted:
		_paint_noted = true
		var host: Node = _host()
		if host != null:
			host.note_first_paint()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	_on_back()


func _on_title_start() -> void:
	# The card paints over this title: park its chrome first so logo,
	# prompt and doors can neither cover the modal nor take its taps.
	_title.park_screen_for_overlay()
	# A fresh chooser is newer than any Hall still loading behind the
	# title: retire it so a late response cannot cover the card.
	_retire_hall_intent()
	var host: Node = _host()
	if host == null:
		_entry.set_providers([])
		_entry.show_error(GateEntryStrings.text("gate.auth.not_ready"))
		return
	_entry.show_logged_out()
	_refresh_identity()
	if not _error_hold.is_empty():
		_entry.show_error(_error_hold)


func _on_selection_closed() -> void:
	_entry.show_title_rest()
	_title.cancel_external_start()


func _wire_entry() -> void:
	_entry.provider_login_requested.connect(_on_provider_login)
	_entry.login_cancelled.connect(_on_login_cancelled)
	_entry.login_retry_requested.connect(_on_login_retry)
	_entry.guest_requested.connect(_on_guest)
	_entry.selection_closed.connect(_on_selection_closed)
	_entry.start_requested.connect(_on_start_pressed)
	_entry.resume_requested.connect(_on_resume_pressed)
	_entry.hall_requested.connect(_on_hall)
	_entry.chronicle_requested.connect(_on_chronicle)
	_entry.heroes_requested.connect(_on_heroes)
	_entry.shop_requested.connect(_on_shop)
	_entry.settings_requested.connect(_on_settings)
	_entry.account_requested.connect(_on_account)
	_entry.analytics_opt_in_changed.connect(_on_analytics_toggled)
	_entry.external_link_requested.connect(_on_external_link)
	_entry.conflict_resolved.connect(_on_conflict_resolved)
	_entry.conflict_cancelled.connect(_on_conflict_cancelled)
	_entry.exit_confirmed.connect(_on_exit_confirmed)
	_entry.exit_cancelled.connect(_on_exit_cancelled)
	_entry.loading_finished.connect(_on_loading_finished)
	_entry.loading_failed.connect(_on_loading_failed)
	_entry.loading_cancelled.connect(_on_loading_cancelled)
	_entry.loading_retry_requested.connect(_on_loading_retry)
	_entry.loading_return_requested.connect(_on_loading_return)
	_entry.music_intent.connect(_on_music_intent)


func _wire_panels() -> void:
	var account_panel: GateAccountPanel = _entry.get_node(
		"GateAccountPanel") as GateAccountPanel
	if account_panel != null:
		account_panel.link_requested.connect(_on_account_link)
		account_panel.sign_out_requested.connect(_on_account_sign_out)
		account_panel.delete_requested.connect(_on_account_delete)
	var hall_panel: GateHallPanel = _entry.get_node(
		"GateHallPanel") as GateHallPanel
	if hall_panel != null:
		hall_panel.closed.connect(_on_hall_closed)


func _wire_host(host: Node) -> void:
	host.production_changed.connect(_on_production_changed)
	host.production_conflict.connect(_on_production_conflict)
	host.production_error.connect(_on_production_error)


func _refresh_identity() -> void:
	var host: Node = _host()
	if host == null:
		return
	var identity: Dictionary = host.identity_for_entry()
	_entry.set_providers(host.providers_for_entry())
	var state: Dictionary = host.account_state()
	_entry.set_offline(bool(state.get("offline", false)))
	if _entry.is_title_rest():
		# Parked for the title: async host settle must not pop the
		# card open. The tap repaints from this same state.
		return
	if str(identity.get("stable_id", "")).is_empty():
		_entry.show_logged_out()
		return
	# The initial cloud save check owns the card until it resolves: a fetch
	# in flight shows the checking face, a failure the save error with its
	# retry and offline doors. No identity card and no start decision before
	# the terminal result.
	if bool(state.get("restore_pending", false)):
		_entry.show_save_check()
		return
	if bool(state.get("restore_failed", false)):
		_entry.show_save_error(_restore_error_body(),
			_restore_error_title(state))
		return
	# First entry shows the actual provider/guest choice: only a
	# cloud-restored account, a returning guest with a saved gate, or a
	# guest chosen earlier this boot goes straight to the identity card.
	var direct: bool = not str(state.get("cloud_uid", "")).is_empty() \
		or bool(state.get("has_save", false)) or _guest_chosen
	if not direct:
		_entry.show_logged_out()
		return
	var saved: Dictionary = identity.get("saved_gate", {})
	var summary: Dictionary = host.saved_gate_summary()
	if bool(saved.get("has_save", false)):
		saved["title"] = _saved_gate_title(summary)
	elif bool(state.get("restore_offline", false)):
		# Explicit offline start with an unchecked cloud: say so on the
		# card instead of claiming no save exists.
		saved["title"] = GateEntryStrings.text("gate.save.offline_unknown")
	_entry.show_identity(identity, saved)


## Save-error card copy: the headline names the failure (offline names
## itself), while the body explains the offline door instead of repeating
## the headline — it plays this device's saved journey, or starts fresh
## when this device has none.
func _restore_error_title(state: Dictionary) -> String:
	if str(state.get("restore_code", "")) == "offline":
		return "gate.save.check_offline"
	return "gate.save.check_failed"


func _restore_error_body() -> String:
	return GateEntryStrings.text("gate.save.offline_body")


func _saved_gate_title(summary: Dictionary) -> String:
	var hero: Hero = summary.get("hero") as Hero
	var hero_name: String = ""
	if hero != null and not str(hero.display_name).is_empty():
		hero_name = tr(str(hero.display_name))
	var wave: String = tr("HUD_WAVE") % int(summary.get("cycle", 1))
	if hero_name.is_empty():
		return wave
	return "%s · %s" % [wave, hero_name]


func _on_provider_login(provider_id: String) -> void:
	var host: Node = _host()
	if host == null:
		return
	_retire_failure()
	_busy_provider = provider_id
	_entry.show_busy(provider_id, host.provider_label(provider_id))
	host.begin_provider(provider_id)


func _on_login_cancelled(provider_id: String) -> void:
	var host: Node = _host()
	if host == null:
		return
	if not host.is_login_pending():
		var snap: Dictionary = host.account_state()
		if bool(snap.get("restore_pending", false)) \
				or bool(snap.get("restore_failed", false)):
			# Cancelling the save check dismisses the card to the title;
			# the bounded check itself keeps running and the tap repaints
			# whatever it resolved to. Never a login cancel: no login is
			# in flight, and the check must not relink or sign in.
			_retire_failure()
			_on_selection_closed()
			return
	if provider_id.is_empty():
		provider_id = _busy_provider
	_busy_provider = provider_id
	_retire_failure()
	var receipt: Dictionary = host.cancel_login(provider_id)
	if str(receipt.get("status", "")) == "draining":
		_entry.show_busy(provider_id, host.provider_label(provider_id))
	else:
		_refresh_identity()


func _on_login_retry(provider_id: String) -> void:
	var host: Node = _host()
	if host == null:
		return
	var snap: Dictionary = host.account_state()
	if bool(snap.get("restore_failed", false)):
		# Save-check retry re-reads the cloud checkpoint for the same
		# account; it never relinks or signs in.
		_retire_failure()
		_entry.show_save_check()
		host.retry_cloud_restore()
		return
	if bool(snap.get("restore_pending", false)):
		# A repeated tap while the re-check is already running stays on
		# the checking face: one active attempt, and never a fallthrough
		# into the auth retry below (an empty provider would guest in).
		_entry.show_save_check()
		return
	if provider_id.is_empty():
		provider_id = _busy_provider
	_retire_failure()
	_entry.show_busy(provider_id, host.provider_label(provider_id))
	host.retry_login(provider_id)


func _on_guest() -> void:
	var host: Node = _host()
	if host == null:
		return
	if bool((host.account_state() as Dictionary).get(
			"restore_failed", false)):
		# The save-error card relabels this door as the explicit offline
		# start: the player saw the failure and plays fresh under the same
		# cloud account. Never the guest escape and never a new choice.
		_retire_failure()
		_busy_provider = ""
		host.accept_offline_entry()
		_refresh_identity()
		return
	# A user intent unparks the card; only host-driven repaints stay
	# parked. Through the UI the selection is always open here already.
	_entry.show_logged_out()
	# Choosing guest drops any stale provider intent: the guest plays
	# locally under the durable ID, never as the failed provider.
	_busy_provider = ""
	var escaping_failure: bool = not _error_hold.is_empty()
	_guest_chosen = true
	if escaping_failure:
		# Error-screen escape: enter the durable local guest directly
		# instead of repeating a failing optional native registration.
		host.begin_guest(true)
	else:
		host.begin_guest()
	if host.is_login_pending():
		# Native registration is genuinely running: busy with cancel,
		# not a selection that looks stuck.
		_entry.show_busy("", GateEntryStrings.text("gate.auth.guest"))
		return
	if escaping_failure:
		_retire_failure()
	_refresh_identity()


func _on_start_pressed() -> void:
	_begin_planned_entry(true)


func _on_resume_pressed() -> void:
	_begin_planned_entry(false)


func _begin_planned_entry(fresh: bool) -> void:
	if _swapping:
		return
	var host: Node = _host()
	if host == null:
		return
	var plan: Dictionary = host.plan_entry(fresh, _fresh_confirmed)
	var status: String = str(plan.get("status", ""))
	if status != "ok":
		if str(plan.get("code", "")) == "needs_confirmation":
			_show_confirm()
		return
	_fresh_confirmed = false
	_load_fresh = fresh
	_load_path = str(plan.get("arena", ""))
	_load_account = str(plan.get("account_id", ""))
	_sfx.play()
	_entry.load_scene(_load_path, GateEntryStrings.text(
		"gate.loading.preparing"))


func _on_loading_finished(path: String, packed: PackedScene,
		token: int) -> void:
	if _swapping:
		return
	var host: Node = _host()
	var loader: GateLoadingOverlay = _entry.get_loader()
	if host == null or loader == null or not is_instance_valid(loader):
		return
	if packed == null or path != _load_path \
			or token != loader.current_token():
		return
	if not host.confirm_entry_account(_load_account):
		host.cancel_entry_plan()
		_load_path = ""
		_load_account = ""
		_refresh_identity()
		return
	_swapping = true
	# The loader owns cancelled worker results until they are claimed;
	# the swap that frees it waits out that drain first.
	var waited: int = 0
	while is_instance_valid(loader) and loader.has_pending_drain() \
			and waited < DRAIN_WAIT_MAX_FRAMES:
		await get_tree().process_frame
		waited += 1
	if not is_inside_tree():
		return
	_fade_out_music()
	get_tree().change_scene_to_packed(packed)


func _on_loading_failed(_path: String, _message: String, _token: int) -> void:
	# The loader shows its own honest error card with retry and back;
	# the plan stays so a retry can re-enter without re-confirming.
	pass


func _on_loading_cancelled(_path: String, _token: int) -> void:
	var host: Node = _host()
	if host == null:
		return
	host.release_entry_hold()


func _on_loading_retry(_path: String) -> void:
	# The loader already re-began under a new token; re-plan the same
	# entry so a retry can never swap an unarmed Arena.
	var host: Node = _host()
	if host == null:
		return
	var plan: Dictionary = host.plan_entry(_load_fresh, true)
	if str(plan.get("status", "")) != "ok":
		host.cancel_entry_plan()
		_load_path = ""
		_load_account = ""


func _on_loading_return() -> void:
	var host: Node = _host()
	if host == null:
		return
	host.cancel_entry_plan()
	_load_path = ""
	_load_account = ""
	_refresh_identity()


## Drop the owned Hall-opening intent, if any. Back and a fresh
## chooser retire it; a newer request supersedes it by minting its own.
## Teardown needs no call: the landing guard checks the tree first.
func _retire_hall_intent() -> void:
	_hall_live_seq = 0


## True while one Hall request is still loading behind the title.
func _hall_pending() -> bool:
	return _hall_live_seq != 0


func _on_hall() -> void:
	var host: Node = _host()
	if host == null:
		_title.close_external_hall()
		return
	# The request owns a monotonic intent before its first await: a
	# response for a dismissed or superseded intent must never open a
	# Hall or touch newer title/menu/card state when it lands.
	_hall_seq += 1
	var intent: int = _hall_seq
	_hall_live_seq = intent
	var view: Dictionary = await host.request_hall()
	if not is_inside_tree():
		return
	if intent != _hall_live_seq:
		return
	_hall_live_seq = 0
	_entry.open_hall(view.get("rows", []), view.get("meta", {}))


## The managed Hall's Close door: back to the title that parked for it.
## Guarded: with a card up the chrome stays parked for the card.
func _on_hall_closed() -> void:
	if _entry.is_title_rest():
		_title.close_external_hall()


## Host-routed menu signals land on the title's original panels; the
## gate keeps no second set. The title's own buttons call the same
## doors directly.
func _on_chronicle() -> void:
	_title.open_chronicle()


func _on_heroes() -> void:
	_title.open_shrine()


func _on_shop() -> void:
	_title.open_store()


func _on_settings() -> void:
	_title.open_settings()


func _on_account() -> void:
	_open_account()


func _open_account() -> void:
	var host: Node = _host()
	if host == null:
		return
	var identity: Dictionary = host.identity_for_entry()
	var state: Dictionary = host.account_state()
	var summary: Dictionary = host.saved_gate_summary()
	var provider_label: String = GateEntryStrings.text(
		"gate.account.local_guest")
	if not str(state.get("cloud_uid", "")).is_empty():
		provider_label = str(state.get("cloud_provider", ""))
		if provider_label.is_empty():
			provider_label = GateEntryStrings.text("gate.account.cloud_saved")
		else:
			provider_label = host.provider_label(provider_label)
	var data: Dictionary = {
		"stable_id": str(identity.get("stable_id", "")),
		"provider_label": provider_label,
		"hero": identity.get("hero"),
		"hero_name": str(identity.get("hero_name", "")),
		"saved_title": _saved_gate_title(summary) \
			if bool(summary.get("has_save", false)) else "",
		"saved_detail": "",
		"analytics_opt_in": Settings.analytics_consent \
			== Settings.AnalyticsConsent.GRANTED,
		"show_links": true,
		"link_providers": _linkable_providers(host),
		"can_sign_out": bool(state.get("ready", false)),
		"can_delete": bool(state.get("ready", false)) \
			and not bool(state.get("entry_in_flight", false)),
	}
	_entry.open_account(data)


func _linkable_providers(host: Node) -> Array:
	var rows: Array = []
	var state: Dictionary = host.account_state() as Dictionary
	var cloud_uid: String = str(state.get("cloud_uid", ""))
	var cloud_provider: String = str(state.get("cloud_provider", ""))
	# An anonymous Firebase guest stays linkable: the credential joins
	# the same UID and public ID. An authenticated provider session
	# hides every link, preserving conflict and switch protections.
	if not cloud_uid.is_empty() and cloud_provider != "anonymous":
		return rows
	for row in host.providers_for_entry():
		if str((row as Dictionary).get("id", "")) == "anonymous":
			continue
		rows.append(row)
	return rows


func _on_account_link(provider_id: String) -> void:
	var host: Node = _host()
	if host == null:
		return
	_retire_failure()
	_busy_provider = provider_id
	_entry.close_panels()
	_entry.show_busy(provider_id, host.provider_label(provider_id))
	host.link_provider(provider_id)


func _on_account_sign_out() -> void:
	var host: Node = _host()
	if host == null:
		return
	_entry.close_panels()
	# An explicit sign-out returns the fresh guest to the choice it has
	# not made yet, instead of inheriting the old guest's card.
	_guest_chosen = false
	_retire_failure()
	host.sign_out()
	_refresh_identity()


func _on_account_delete() -> void:
	var host: Node = _host()
	if host == null:
		return
	_entry.close_panels()
	var result: Dictionary = await host.delete_current_account()
	if not is_inside_tree():
		return
	if str(result.get("status", "")) != "ok":
		_entry.show_error(GateEntryStrings.text(
			"gate.auth.error_title"))
	else:
		_guest_chosen = false
		_refresh_identity()


func _on_analytics_toggled(enabled: bool) -> void:
	Settings.set_analytics_consent(
		Settings.AnalyticsConsent.GRANTED if enabled \
		else Settings.AnalyticsConsent.DENIED)


func _on_external_link(url: String) -> void:
	ExternalLinks.open_external_url(url)


func _on_production_changed(state: Dictionary) -> void:
	if _swapping or not is_inside_tree():
		return
	if not _error_hold.is_empty():
		# Only a genuine new outcome retires the failure: the session or
		# the ID moved. Benign duplicates of the same failure (same ID,
		# same UID, same session provider, settled pending) keep the
		# error on screen. The session provider is part of the move: a
		# successful link keeps the UID and the ID and flips only the
		# provider (anonymous to the linked one).
		var id_now: String = str(state.get("public_id", ""))
		var uid_now: String = str(state.get("cloud_uid", ""))
		var provider_now: String = str(state.get("cloud_provider", ""))
		if id_now != _failed_public_id \
				or uid_now != _failed_cloud_uid \
				or provider_now != _failed_cloud_provider:
			_retire_failure()
	_refresh_identity()
	if not _error_hold.is_empty() and not _entry.is_title_rest():
		_entry.show_error(_error_hold)
	var panel: GateAccountPanel = _entry.get_node(
		"GateAccountPanel") as GateAccountPanel
	if panel != null and panel.visible:
		_open_account()


## Retire the held login failure. Explicit user intents (retry, cancel,
## provider choice, guest, link, sign-out) and genuine new outcomes call
## this; benign duplicate change notifications never do.
func _retire_failure() -> void:
	_error_hold = ""
	_failed_public_id = ""
	_failed_cloud_uid = ""
	_failed_cloud_provider = ""


func _on_production_conflict(local: Dictionary, cloud: Dictionary) -> void:
	if _swapping or not is_inside_tree():
		return
	_entry.open_conflict(local, cloud)


func _on_production_error(error: Dictionary) -> void:
	if _swapping or not is_inside_tree():
		return
	if str(error.get("code", "")) == "save_check_failed":
		# The save-check failure needs no hold: the host flag drives the
		# card on every repaint, including the matching change below.
		_refresh_identity()
		return
	# The matching `production_changed` lands right after this error and
	# repaints the identity card, so the error text is held and applied
	# after that repaint instead of being swallowed by it. A second,
	# benign duplicate change follows for async failures; the hold
	# survives that too until an explicit intent or a genuine new
	# outcome retires it.
	if str(error.get("code", "")) == "already_linked_elsewhere" \
			and bool(error.get("can_switch", false)):
		_error_hold = "%s · %s" % [
			GateEntryStrings.text("gate.auth.error_title"),
			str(error.get("provider", ""))]
	else:
		_error_hold = GateEntryStrings.text("gate.auth.error_title")
	var host: Node = _host()
	if host != null:
		var snap: Dictionary = host.account_state()
		_failed_public_id = str(snap.get("public_id", ""))
		_failed_cloud_uid = str(snap.get("cloud_uid", ""))
		_failed_cloud_provider = str(snap.get("cloud_provider", ""))
	# Shown now for paths without a matching change, and held so the
	# matching change's repaint (which always follows) re-applies it.
	# While parked for the title the hold waits for the tap instead.
	_refresh_identity()
	if not _entry.is_title_rest():
		_entry.show_error(_error_hold)


func _on_conflict_resolved(which: StringName) -> void:
	var host: Node = _host()
	if host == null:
		return
	await host.resolve_save_choice(
		"remote" if which == &"cloud" else "local")
	if is_inside_tree():
		_refresh_identity()


func _on_conflict_cancelled() -> void:
	# Decide later: the coordinator keeps the conflict open and both
	# versions stay where they are until the player picks.
	pass


func _on_exit_confirmed() -> void:
	get_tree().quit()


## Staying: restore the title chrome the exit question parked, but
## never under a live card (back can ask from ready too).
func _on_exit_cancelled() -> void:
	if _entry.is_title_rest():
		_title.cancel_external_start()


func _on_music_intent(intent: StringName) -> void:
	if intent == &"stop":
		_fade_out_music()
	else:
		_fade_in_music()


## Direct-distribution debug APKs still check the real App Store review panel.
func debug_open_iap_store() -> void:
	if OS.is_debug_build():
		_title.open_store()


func debug_prepare_store_capture(request: Dictionary) -> void:
	if not OS.is_debug_build():
		return
	var kind: String = str(request.get("kind", ""))
	if kind == "title":
		_entry.close_panels()
		_entry.show_title_rest()
		_title.cancel_external_start()
	elif kind in ["shrine", "hero_preview", "iap_review"]:
		_title.debug_prepare_store_capture(request)


## Capture proof for the production entry. `title` reports the honest
## gate state plus the title layer (see the 4.0.0 production host log).
## Panel kinds forward to the title's original panels.
func debug_store_capture_state(request: Dictionary) -> Dictionary:
	if not OS.is_debug_build():
		return {}
	var kind: String = str(request.get("kind", ""))
	if kind == "title":
		var host: Node = _host()
		var debug: Dictionary = host.debug_production_state() \
			if host != null else {}
		debug["gate_visible"] = _entry.visible \
			and _entry.is_visible_in_tree()
		debug["title_visible"] = _title.visible \
			and _title.is_visible_in_tree()
		debug["selection_open"] = _entry.is_selection_open()
		debug["expected_version"] = "v" + str(ProjectSettings.get_setting(
			"application/config/version", "0.0.0"))
		return debug
	if kind in ["shrine", "hero_preview", "iap_review"]:
		return _title.debug_store_capture_state(request)
	return {}


## Android back unwinds one layer at a time: confirm, the loader, gate
## panels, the login selection, the title's panels, and only then the
## exit question.
func _on_back() -> void:
	if _confirm_card != null and _confirm_card.visible:
		_confirm_card.visible = false
		return
	var loader: GateLoadingOverlay = _entry.get_loader()
	if loader != null and loader.is_loading():
		loader.cancel()
	elif loader != null \
			and (loader.is_showing_error() or loader.is_showing_cancelled()):
		# Leave the loader's card the way its own Back button would, then
		# drop the plan so a later tap starts cleanly.
		loader.visible = false
		var host: Node = _host()
		if host != null:
			host.cancel_entry_plan()
		_refresh_identity()
	elif _gate_panel_open():
		var hall_panel: Control = _entry.get_node_or_null(
			"GateHallPanel") as Control
		var hall_was_open: bool = hall_panel != null \
			and hall_panel.visible
		var exit_panel: Control = _entry.get_node_or_null(
			"GateExitPanel") as Control
		var exit_was_open: bool = exit_panel != null \
			and exit_panel.visible
		_entry.close_panels()
		# close_panels hides without signals: restore the title the
		# Hall or exit parked, but never under a live card.
		if hall_was_open:
			_on_hall_closed()
		elif exit_was_open and _entry.is_title_rest():
			_title.cancel_external_start()
	elif _entry.is_selection_open():
		_on_selection_closed()
	elif _title.external_go_back():
		pass
	elif _hall_pending():
		# A Hall request is still loading behind the parked title: drop
		# the stale intent and restore the original title directly
		# instead of asking to quit. The late response opens nothing.
		_retire_hall_intent()
		_title.close_external_hall()
	else:
		_title.park_screen_for_overlay()
		_entry.open_exit()


func _gate_panel_open() -> bool:
	for panel_name in ["GateAccountPanel", "GateConflictPanel",
			"GateHallPanel", "GateExitPanel", "GateTermsPanel"]:
		var panel: Control = _entry.get_node_or_null(
			panel_name) as Control
		if panel != null and panel.visible:
			return true
	return false


func _build_confirm() -> void:
	_confirm_card = PanelContainer.new()
	_confirm_card.name = &"FreshConfirm"
	GateEntryStyle.apply_card(_confirm_card)
	_confirm_card.set_anchors_preset(Control.PRESET_CENTER)
	_confirm_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_confirm_card.custom_minimum_size = Vector2(360.0, 0.0)
	add_child(_confirm_card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override(&"separation", 8)
	_confirm_card.add_child(stack)
	var title := GateEntryStyle.make_label(
		"gate.confirm.title", GateEntryStyle.FONT_BODY,
		GateEntryStyle.TEXT_MAIN, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(title)
	var body := GateEntryStyle.make_label(
		"gate.confirm.body", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 8)
	stack.add_child(row)
	var erase := GateEntryStyle.make_button(
		"gate.confirm.erase", "danger")
	erase.pressed.connect(_on_confirm_erase)
	row.add_child(erase)
	var keep := GateEntryStyle.make_button("gate.confirm.keep")
	keep.pressed.connect(_on_confirm_keep)
	row.add_child(keep)
	_confirm_card.visible = false


func _show_confirm() -> void:
	_confirm_card.visible = true


func _on_confirm_erase() -> void:
	_confirm_card.visible = false
	_fresh_confirmed = true
	_begin_planned_entry(true)


func _on_confirm_keep() -> void:
	_confirm_card.visible = false


func _fade_in_music() -> void:
	_bgm.volume_db = BGM_SILENCE_DB
	await get_tree().create_timer(BGM_START_DELAY_SECONDS).timeout
	if not is_inside_tree():
		return
	_bgm.play()
	var fade: Tween = create_tween()
	fade.tween_property(_bgm, "volume_db", BGM_VOLUME_DB, BGM_FADE_IN_SECONDS)


func _fade_out_music() -> void:
	var fade: Tween = create_tween()
	fade.tween_property(_bgm, "volume_db", BGM_SILENCE_DB, BGM_FADE_OUT_SECONDS)
	await fade.finished
	if not is_inside_tree():
		return
	_bgm.release()
	_sfx.release()
