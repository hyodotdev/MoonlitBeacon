class_name GateEntry
extends Control

## The moon gate entry surface: sign-in card over the original title.
##
## A standalone presentation module. In production it sits above the
## original title scene: first paint is the title at rest (art, type and
## doors all the title's own), and a tap opens this compact centered card
## with guest, provider sign-in, start/resume, and the legal footer. It
## owns no services: providers, identity, saves and Hall rows all arrive
## from the host, and every tap leaves as a signal for the host to answer
## with real work.
##
## Default state is honestly logged out. When the host supplies no
## providers at all, the card says sign-in is off and guest entry stays
## usable; nothing here hardcodes a successful login. `show_title_rest`
## parks the surface with the card hidden while the title holds the
## screen; `set_backdrop_visible` hides the painted backdrop (but never
## the hero forecourt) so the title diorama shows through.
##
## Music stays the host's player: this surface only announces its intent
## (`music_intent`, `sync_music`), never touches audio streams. Loading is
## delegated to the embedded GateLoadingOverlay, which never enters a scene
## itself; the host places the `packed` scene from `loading_finished`.
##
## Layout is manual against the real viewport rect, so the 808x360 base,
## wider phones and tablets all frame from the same code. Decorative layers
## never eat taps; only the scrim and real buttons stop input.

signal provider_login_requested(provider_id: String)
signal login_cancelled(provider_id: String)
signal login_retry_requested(provider_id: String)
signal guest_requested
signal selection_closed
signal start_requested
signal resume_requested
## The hall/chronicle/heroes/shop/settings routing contract. This surface
## shows no menu bar of its own: the original title's buttons are the
## doors, and the host routes these signals to the title's panels (Hall
## to the gate hall). They stay so the host wiring stays provable.
signal hall_requested
signal chronicle_requested
signal heroes_requested
signal shop_requested
signal settings_requested
signal account_requested
signal account_closed
signal analytics_opt_in_changed(enabled: bool)
signal external_link_requested(url: String)
signal id_copied(stable_id: String)
signal conflict_resolved(which: StringName)
signal conflict_cancelled
signal hall_closed
signal exit_confirmed
signal exit_cancelled
signal loading_finished(scene_path: String, packed: PackedScene, token: int)
signal loading_failed(scene_path: String, message: String, token: int)
signal loading_cancelled(scene_path: String, token: int)
signal loading_retry_requested(scene_path: String)
signal loading_return_requested
signal music_intent(intent: StringName)

const ART: Texture2D = preload("res://assets/gate/moon_gate_title.png")
const ACCOUNT_SCENE: PackedScene = preload("res://scenes/ui/gate_account_panel.tscn")
const CONFLICT_SCENE: PackedScene = preload("res://scenes/ui/gate_conflict_panel.tscn")
const HALL_SCENE: PackedScene = preload("res://scenes/ui/gate_hall_panel.tscn")
const EXIT_SCENE: PackedScene = preload("res://scenes/ui/gate_exit_panel.tscn")
const LOADER_SCENE: PackedScene = preload("res://scenes/ui/gate_loading_overlay.tscn")
const ExternalLinks := preload("res://scripts/ui/external_links.gd")

const AUTH_TITLE_REST: StringName = &"title_rest"
## The ordinary sign-in doors, always visible in this order. The host
## lists what its platform supports; any ordinary id it omits renders
## as an honestly disabled placeholder (same builder, same note line),
## never as a working login. Brand names stay Latin in every locale,
## like the existing Play Games strings.
const ORDINARY_PROVIDER_IDS: Array[String] = ["google", "apple"]
const ORDINARY_PROVIDER_NAMES: Dictionary = {
	"google": "Google",
	"apple": "Apple",
}
const AUTH_LOGGED_OUT: StringName = &"logged_out"
const AUTH_BUSY: StringName = &"busy"
const AUTH_IDENTITY_READY: StringName = &"identity_ready"
const AUTH_ERROR: StringName = &"error"
const MUSIC_PLAY: StringName = &"play"
const MUSIC_STOP: StringName = &"stop"

## Manual layout, measured from the real viewport rect each resize. One
## centered card; the original title owns type, doors and version around
## it, so this surface keeps no title block, menu bar or version of its
## own. The offline badge tucks top-left, clear of the title's
## bottom-right version and top-right doors and of the lineup below.
const CARD_WIDTH: float = 360.0
const CARD_MARGIN: float = 12.0
const EDGE_MARGIN: float = 16.0
## Logged-out compact stages: shed order when the honest fitted height
## exceeds the viewport on short screens. The official 44px doors, the
## consent sentence, and the note glyph budgets never move; separations
## never drop below the 5px Apple clearspace floor.
const LOGGED_OUT_SEPARATION_FULL: int = 6
const LOGGED_OUT_SEPARATION_COMPACT: int = 5
const PROVIDER_SEPARATION_FULL: int = 8
const PROVIDER_SEPARATION_COMPACT: int = 5
const GUEST_HEIGHT_COMPACT: float = 40.0
const EXTRA_HEIGHT_COMPACT: float = 40.0
## In-app Terms sheet: fixed width, explicit fitted height, scroll body.
const TERMS_CARD_WIDTH: float = 420.0
const TERMS_PARAGRAPHS: int = 8
const TERMS_SCROLL_MIN: float = 110.0
const TERMS_SCROLL_MAX: float = 220.0
## Modal dim behind the card. It blocks the title doors while the card is
## up; a tap on it only ever closes the selection, never busy, error or
## ready, which each keep their explicit buttons.
const SCRIM_COLOR: Color = Color(0.02, 0.04, 0.09, 0.35)
## Art overscan so the slow drift never shows an edge.
const ART_OVERSCAN: float = 16.0
## Motion budget: everything below loops on a sine, nothing travels far.
const DRIFT_X: float = 8.0
const DRIFT_Y: float = 5.0
const DRIFT_SECONDS_X: float = 16.0
const DRIFT_SECONDS_Y: float = 13.0
const DUST_COUNT: int = 20
const DUST_LIFETIME: float = 7.0

var _auth_mode: StringName = AUTH_LOGGED_OUT
var _providers: Array = []
var _busy_provider_id: String = ""
var _busy_provider_label: String = ""
var _offline: bool = false
var _backdrop_visible: bool = true
var _has_save: bool = false
var _reduced_motion: bool = false
var _effect_time: float = 0.0
var _music: StringName = MUSIC_PLAY

var _mist_a_base: float = 0.0
var _mist_b_base: float = 0.0
## Autowrap labels inside the status card. Their minimum widths are bound
## to the card content width every layout: unbounded, an autowrap label
## reports a 1px column and a matching giant height, which would clamp the
## card size up and off-center it.
var _wrapped_labels: Array[Label] = []
var _art_layer: Control
var _art: TextureRect
var _shade: TextureRect
var _gate_glow: TextureRect
var _hearth_glow: TextureRect
var _mist_a: TextureRect
var _mist_b: TextureRect
var _dust: CPUParticles2D
var _flash: TextureRect
var _flash_tween: Tween = null
var _forecourt: GateHeroForecourt
## The production title's screen chrome, when this surface is hosted
## beside the original title. Its visibility is the title-modal
## signal: every title door parks it, every close restores it.
## World staging needs that same host: only beside a real title is
## there a forest to walk, so a standalone surface keeps its
## formation even with its own backdrop hidden.
var _title_screen: Control = null
var _scrim: ColorRect
var _content: Control
var _status_card: PanelContainer
var _logged_out_box: VBoxContainer
var _hint: Label
var _guest_button: Button
var _provider_row: VBoxContainer
var _provider_note: Label
var _unconfigured_note: Label
var _consent: RichTextLabel
var _back_button: Button
var _busy_box: VBoxContainer
var _working_label: Label
var _ready_box: VBoxContainer
var _id_field: LineEdit
var _portrait: TextureRect
var _hero_name: Label
var _saved_line: Label
var _start_button: Button
var _resume_button: Button
var _account_button: Button
var _error_box: VBoxContainer
var _error_title: Label
var _error_detail: Label
var _error_guest: Button
## Save-check variant of the busy card. Same box, same door, honest save
## copy: the working line reads the checking key while set, and every
## other `show_*` restores the auth faces (including the error title and
## the guest escape, which the save-error card retexted directly).
var _busy_save_check: bool = false
var _offline_badge: Label
var _account_panel: GateAccountPanel
var _conflict_panel: GateConflictPanel
var _hall_panel: GateHallPanel
var _exit_panel: GateExitPanel
var _terms_panel: Control
var _terms_card: PanelContainer
var _terms_scroll: ScrollContainer
var _terms_body: Label
var _terms_privacy: Button
var _terms_close: Button
var _loader: GateLoadingOverlay


func _ready() -> void:
	GateEntryStrings.ensure_loaded()
	_build_layers()
	_build_content()
	_build_panels()
	_watch_modal_visibility()
	_isolate_modal_light()
	_refresh_auth()
	_refresh_motion()
	_relayout()
	resized.connect(_relayout)
	# Hosts connect in their own `_ready`, which runs after this one but
	# before the first idle frame, so this deferred note still lands.
	_music_announce.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_consent()
		_relayout()


func _process(delta: float) -> void:
	if _reduced_motion:
		return
	_effect_time += delta
	var time: float = _effect_time
	_art_layer.position = Vector2(
		sin(time * TAU / DRIFT_SECONDS_X) * DRIFT_X,
		cos(time * TAU / DRIFT_SECONDS_Y) * DRIFT_Y)
	_gate_glow.modulate.a = 0.30 + 0.08 * sin(time * TAU / 6.0)
	_hearth_glow.modulate.a = 0.20 + 0.06 * sin(time * TAU / 7.3 + 1.7)
	_mist_a.position.x = _mist_a_base + sin(time * TAU / 19.0) * 36.0
	_mist_b.position.x = _mist_b_base + sin(time * TAU / 23.0 + 2.1) * -30.0


## Providers the host really supports: [{id, label, ready, draining}].
## Omitted providers stay hidden; `ready == false` shows disabled with its
## honest note. Never invents success: an empty list is a valid state.
func set_providers(providers: Array) -> void:
	_providers = providers.duplicate()
	_rebuild_provider_buttons()
	_refresh_auth()
	_relayout()


## Park the surface while the original title holds the screen: card and
## scrim hide, the forecourt keeps standing over the title diorama.
func show_title_rest() -> void:
	_auth_mode = AUTH_TITLE_REST
	_reset_save_faces()
	_refresh_auth()
	_relayout()


## True while the login selection is the card on screen: the only state
## the scrim tap and the footer Back may close.
func is_selection_open() -> bool:
	return _auth_mode == AUTH_LOGGED_OUT


## True while the card is parked for the title: host-driven repaints
## must not pop it open; only the tap opens it.
func is_title_rest() -> bool:
	return _auth_mode == AUTH_TITLE_REST


## Hide the painted backdrop (art, shade, glows, mist, dust, flash) so
## the original title shows through. The hero forecourt switches to
## world staging; modal content may conceal it while covered.
func set_backdrop_visible(visible: bool) -> void:
	_backdrop_visible = visible
	if _art == null:
		return
	_art.visible = visible
	_shade.visible = visible
	_gate_glow.visible = visible
	_hearth_glow.visible = visible
	_mist_a.visible = visible
	_mist_b.visible = visible
	_dust.visible = visible
	_flash.visible = visible
	_refresh_forecourt_presentation()


## Watch the two visibility signals the auth refresh cannot see: the
## loader veil and the production title's screen chrome. Both park and
## restore without passing through the auth modes.
func _watch_modal_visibility() -> void:
	if _loader != null:
		_loader.visibility_changed.connect(_refresh_forecourt_presentation)
	var host_parent: Node = get_parent()
	if host_parent == null:
		return
	var title_node: Node = host_parent.get_node_or_null("Title")
	if title_node == null:
		return
	_title_screen = title_node.get_node_or_null("Ui/Screen") as Control
	if _title_screen != null:
		_title_screen.visibility_changed.connect(
			_refresh_forecourt_presentation)


## Narrow presentation context for the hero forecourt: world staging
## over the production forest, formation staging over the standalone
## backdrop. While world-staged, any centered content over the
## clearing — the status card, the loader, a gate dialog, or a title
## modal — quietly conceals the decorative party; the patrol keeps
## simulating underneath, so the return never teleports.
func _refresh_forecourt_presentation() -> void:
	if _forecourt == null or _status_card == null:
		return
	var world := not _backdrop_visible and _title_screen != null
	var covered := _status_card.visible
	if _loader != null and _loader.visible:
		covered = true
	for panel in [_account_panel, _conflict_panel, _hall_panel,
			_exit_panel, _terms_panel]:
		if panel != null and (panel as Control).visible:
			covered = true
	if _title_screen != null and not _title_screen.visible:
		covered = true
	_forecourt.set_presentation(world, world and covered)


func show_logged_out() -> void:
	_auth_mode = AUTH_LOGGED_OUT
	_reset_save_faces()
	_refresh_auth()
	_relayout()


func show_busy(provider_id: String, provider_label: String) -> void:
	_busy_provider_id = provider_id
	_busy_provider_label = provider_label
	_auth_mode = AUTH_BUSY
	_reset_save_faces()
	_refresh_auth()
	_relayout()


## The initial cloud save check, on the busy card: the working line reads
## the checking key instead of the sign-in one. Same cancel door.
func show_save_check() -> void:
	_auth_mode = AUTH_BUSY
	_busy_save_check = true
	_working_label.text = "gate.save.checking"
	_refresh_auth()
	_relayout()


func show_error(detail_text: String) -> void:
	_auth_mode = AUTH_ERROR
	_reset_save_faces()
	_error_detail.text = detail_text
	_error_detail.visible = not detail_text.is_empty()
	_refresh_auth()
	_relayout()


## A failed initial cloud save check, on the error card: the title reads
## the given save headline and the guest escape becomes the explicit
## offline start. Retry and cancel keep their doors; the host routes all
## three.
func show_save_error(detail_text: String,
		title_key: String = "gate.save.check_failed") -> void:
	_auth_mode = AUTH_ERROR
	_busy_save_check = false
	_error_title.text = title_key
	_error_detail.text = detail_text
	_error_detail.visible = not detail_text.is_empty()
	_error_guest.text = "gate.save.play_offline"
	_refresh_auth()
	_relayout()


## Restore the auth faces after a save-check card. Called by every `show_*`
## except the two save variants, so a later auth card never wears save copy.
func _reset_save_faces() -> void:
	_busy_save_check = false
	if _error_title != null:
		_error_title.text = "gate.auth.error_title"
	if _error_guest != null:
		_error_guest.text = "gate.auth.guest"


## Identity and saved gate arrive together from the host; either may be
## empty, and each empty side shows its honest empty line.
func show_identity(identity: Dictionary, saved_gate: Dictionary) -> void:
	_auth_mode = AUTH_IDENTITY_READY
	_reset_save_faces()
	_id_field.text = str(identity.get("stable_id", ""))
	var portrait: Texture2D = identity.get("portrait") as Texture2D
	var hero: Hero = identity.get("hero") as Hero
	if portrait == null and hero != null:
		portrait = hero.portrait
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	var hero_name: String = str(identity.get("hero_name", ""))
	if hero_name.is_empty() and hero != null:
		hero_name = hero.display_name
		if not hero_name.is_empty():
			hero_name = tr(hero_name)
	_hero_name.text = hero_name \
		if not hero_name.is_empty() else "gate.auth.no_hero"
	_has_save = bool(saved_gate.get("has_save", false))
	var saved_title: String = str(saved_gate.get("title", ""))
	_saved_line.text = saved_title \
		if not saved_title.is_empty() else "gate.auth.no_save"
	_refresh_auth()
	_relayout()


func set_offline(offline: bool) -> void:
	_offline = offline
	_refresh_auth()


## Reduced motion freezes drift, glow travel, dust and the hero
## forecourt, and skips the readiness flash. Status text, progress and
## buttons keep working.
func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if _forecourt != null:
		_forecourt.set_reduced_motion(enabled)
	_refresh_motion()


func is_reduced_motion() -> bool:
	return _reduced_motion


## True while the ambient layers are allowed to move. Tests read this.
func is_motion_active() -> bool:
	return not _reduced_motion and _dust.emitting \
		and _forecourt.is_motion_active()


## The decorative hero lineup, for tests and the shot harness.
func get_forecourt() -> GateHeroForecourt:
	return _forecourt


func open_account(data: Dictionary) -> void:
	close_panels()
	_account_panel.show_account(data)
	_isolate_modal_light()
	_refresh_forecourt_presentation()


func open_conflict(local: Dictionary, cloud: Dictionary) -> void:
	close_panels()
	_conflict_panel.show_conflict(local, cloud)
	_isolate_modal_light()
	_refresh_forecourt_presentation()


func open_hall(rows: Array, meta: Dictionary = {}) -> void:
	close_panels()
	_hall_panel.show_rows(rows, meta)
	_isolate_modal_light()
	_refresh_forecourt_presentation()


func open_exit() -> void:
	close_panels()
	_exit_panel.open()
	_isolate_modal_light()
	_refresh_forecourt_presentation()


## The in-app Terms sheet over the selection. It starts nothing: Close
## (or the host back unwind) returns to the same card underneath.
func open_terms() -> void:
	close_panels()
	_terms_body.text = _terms_text()
	_terms_privacy.visible = not ExternalLinks.privacy_policy_url().is_empty()
	_relayout_terms()
	_terms_panel.visible = true
	_terms_close.grab_focus()
	_isolate_modal_light()
	_refresh_forecourt_presentation()


func close_panels() -> void:
	for panel in [_account_panel, _conflict_panel, _hall_panel,
			_exit_panel, _terms_panel]:
		(panel as Control).visible = false
	_refresh_forecourt_presentation()


## Hand a scene path to the embedded loader. See GateLoadingOverlay for the
## paint-first and stale-completion rules. Returns the load token.
func load_scene(scene_path: String, stage_text: String) -> int:
	return _loader.begin(scene_path, stage_text)


func cancel_loading() -> void:
	_loader.cancel()


func get_loader() -> GateLoadingOverlay:
	return _loader


func get_music_intent() -> StringName:
	return _music


## Re-announce the current music intent for hosts that connected late.
func sync_music() -> void:
	_music_announce()


func _music_announce() -> void:
	music_intent.emit(_music)


func _set_music(intent: StringName) -> void:
	_music = intent
	_music_announce()


func _on_provider_pressed(provider_id: String) -> void:
	if _auth_mode == AUTH_BUSY:
		return
	provider_login_requested.emit(provider_id)


func _on_cancel_login() -> void:
	login_cancelled.emit(_busy_provider_id)


func _on_retry_login() -> void:
	login_retry_requested.emit(_busy_provider_id)


func _on_guest() -> void:
	guest_requested.emit()


## The selection's way back to the tap screen. Only the selection may
## close this way; busy, error and ready keep their explicit buttons.
func _on_selection_back() -> void:
	if _auth_mode == AUTH_LOGGED_OUT:
		selection_closed.emit()


func _on_scrim_input(event: InputEvent) -> void:
	if _auth_mode != AUTH_LOGGED_OUT:
		return
	if event is InputEventMouseButton:
		var press: InputEventMouseButton = event
		if press.pressed and press.button_index == MOUSE_BUTTON_LEFT:
			selection_closed.emit()
	elif event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			selection_closed.emit()


## The consent Privacy link never starts play: it only hands a
## validated URL to the host. With no safe URL it emits nothing.
func _on_privacy() -> void:
	var url: String = ExternalLinks.privacy_policy_url()
	if not url.is_empty():
		external_link_requested.emit(url)


## The consent Terms link opens the in-app sheet, never a browser.
func _on_terms() -> void:
	open_terms()


## Inline consent link routing: Terms opens the Moonlit sheet, Privacy
## dispatches the Moonlit URL. Neither starts play nor picks a door.
func _on_consent_meta(meta: Variant) -> void:
	match str(meta):
		"tos":
			open_terms()
		"privacy":
			_on_privacy()


## The donor consent sentence with its two inline links, resolved now
## so the line always reads the language the player is using. The
## English cell stores `{comma}` because the locale table forbids ASCII
## commas; the runtime restores the donor comma here. With no safe
## privacy URL the privacy phrase stays plain text, never a dead link.
func _refresh_consent() -> void:
	if _consent == null:
		return
	var template: String = GateEntryStrings.text(
		"gate.auth.consent").replace("{comma}", ",")
	var tos_label: String = GateEntryStrings.text("gate.auth.consent.tos")
	var privacy_label: String = GateEntryStrings.text(
		"gate.auth.consent.privacy")
	var accent: String = "#" + GateEntryStyle.ACCENT_AMBER.to_html(false)
	var tos: String = "[url=tos][color=%s][u]%s[/u][/color][/url]" % [
		accent, tos_label]
	var privacy: String = privacy_label
	if not ExternalLinks.privacy_policy_url().is_empty():
		privacy = "[url=privacy][color=%s][u]%s[/u][/color][/url]" % [
			accent, privacy_label]
	_consent.text = template % [tos, privacy]


## Global center of a consent link for pointer tests. The sentence is
## left-aligned with both links on the first wrapped line in every
## locale (measured Noto 12px: the link span ends within 282px of the
## 328px content), so the first-line prefix widths land the tap.
func consent_link_center(meta: String) -> Vector2:
	var font: Font = _consent.get_theme_font("normal_font")
	var size: int = _consent.get_theme_font_size("normal_font_size")
	var template: String = GateEntryStrings.text(
		"gate.auth.consent").replace("{comma}", ",")
	var tos_label: String = GateEntryStrings.text("gate.auth.consent.tos")
	var privacy_label: String = GateEntryStrings.text(
		"gate.auth.consent.privacy")
	var parts: PackedStringArray = template.split("%s")
	var prefix: float = font.get_string_size(
		parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var tos_w: float = font.get_string_size(
		tos_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var middle: float = font.get_string_size(
		parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var privacy_w: float = font.get_string_size(
		privacy_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var x: float = prefix + tos_w * 0.5
	if meta != "tos":
		x = prefix + tos_w + middle + privacy_w * 0.5
	var line: float = float(font.get_height(size))
	return _consent.get_global_rect().position + Vector2(x, line * 0.5)


func _on_terms_close() -> void:
	_terms_panel.visible = false


## The eight Terms paragraphs in the current locale, resolved now so
## the sheet always reads the language the player is using.
func _terms_text() -> String:
	var parts: Array[String] = []
	for index in TERMS_PARAGRAPHS:
		parts.append(GateEntryStrings.text("gate.terms.p%d" % (index + 1)))
	return "\n\n".join(parts)


func _on_start() -> void:
	_set_music(MUSIC_STOP)
	start_requested.emit()


func _on_resume() -> void:
	_set_music(MUSIC_STOP)
	resume_requested.emit()


func _on_copy_id() -> void:
	var stable_id: String = _id_field.text
	if stable_id.is_empty():
		return
	DisplayServer.clipboard_set(stable_id)
	id_copied.emit(stable_id)


func _on_loader_finished(path: String, packed: PackedScene, token: int) -> void:
	_flash_gate_light()
	loading_finished.emit(path, packed, token)


## A short gate-light answer to readiness. It never blocks input: the flash
## ignores the mouse and the overlay is already gone when it plays.
func _flash_gate_light() -> void:
	if _reduced_motion or _flash == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.modulate.a = 0.0
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.45, 0.18)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.45)


func _refresh_auth() -> void:
	if _logged_out_box == null:
		return
	_logged_out_box.visible = _auth_mode == AUTH_LOGGED_OUT
	_busy_box.visible = _auth_mode == AUTH_BUSY
	_ready_box.visible = _auth_mode == AUTH_IDENTITY_READY
	_error_box.visible = _auth_mode == AUTH_ERROR
	_status_card.visible = _auth_mode != AUTH_TITLE_REST
	_scrim.visible = _auth_mode != AUTH_TITLE_REST
	_offline_badge.visible = _offline \
		and _auth_mode != AUTH_TITLE_REST
	_unconfigured_note.visible = _providers.is_empty()
	_refresh_consent()
	if _auth_mode == AUTH_BUSY and not _busy_save_check:
		if _busy_provider_label.is_empty():
			_working_label.text = "gate.auth.working"
		else:
			_working_label.text = "%s · %s" % [
				GateEntryStrings.text("gate.auth.working"),
				_busy_provider_label]
	_resume_button.visible = _has_save
	# Exactly one gold primary: resume when a save waits, start otherwise.
	if _auth_mode == AUTH_IDENTITY_READY and not _has_save:
		GateEntryStyle.apply_kind(_start_button, "primary")
	else:
		GateEntryStyle.apply_kind(_start_button, "normal")
	_refresh_forecourt_presentation()


## Modal UI ignores scene light: every canvas item under the card,
## the dialogs, Terms and the loader sits on light mask 0, so the title
## beacon's idle glow and tap flare can never tint card fills, text,
## logos or the loading paint. The art layer and hero forecourt keep
## mask 1 with their world ambience. Draw order, input and coordinates
## never move: masks only decide what the lights touch. Re-applied when
## provider doors rebuild and when a dialog opens, the only modal
## structure that ever changes after build.
func _isolate_modal_light() -> void:
	for root in [_content, _account_panel, _conflict_panel,
			_hall_panel, _exit_panel, _terms_panel, _loader]:
		_unlight_tree(root)


func _unlight_tree(node: Node) -> void:
	if node == null:
		return
	var item: CanvasItem = node as CanvasItem
	if item != null:
		item.light_mask = 0
	for child in node.get_children():
		_unlight_tree(child)


func _refresh_motion() -> void:
	if _dust == null:
		return
	if _reduced_motion:
		if _flash_tween != null and _flash_tween.is_valid():
			_flash_tween.kill()
		_flash.modulate.a = 0.0
		_art_layer.position = Vector2.ZERO
		_gate_glow.modulate.a = 0.30
		_hearth_glow.modulate.a = 0.20
		_mist_a.position.x = _mist_a_base
		_mist_b.position.x = _mist_b_base
		_dust.emitting = false
	else:
		_dust.emitting = true


func _build_layers() -> void:
	_art_layer = Control.new()
	_art_layer.name = &"ArtLayer"
	_art_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art_layer)
	_art = TextureRect.new()
	_art.name = &"Art"
	_art.texture = ART
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.offset_left = -ART_OVERSCAN
	_art.offset_top = -ART_OVERSCAN
	_art.offset_right = ART_OVERSCAN
	_art.offset_bottom = ART_OVERSCAN
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_layer.add_child(_art)
	_shade = TextureRect.new()
	_shade.name = &"Shade"
	_shade.texture = _legibility_shade()
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_layer.add_child(_shade)
	_gate_glow = _glow_rect(
		&"GateGlow", Color(1.0, 0.75, 0.40, 0.30), Vector2(280.0, 280.0))
	_hearth_glow = _glow_rect(
		&"HearthGlow", Color(0.45, 0.85, 0.82, 0.20), Vector2(200.0, 200.0))
	_mist_a = _glow_rect(
		&"MistA", Color(0.60, 0.75, 0.90, 0.10), Vector2(560.0, 120.0))
	_mist_b = _glow_rect(
		&"MistB", Color(0.60, 0.75, 0.90, 0.08), Vector2(640.0, 140.0))
	_dust = CPUParticles2D.new()
	_dust.name = &"Dust"
	_dust.amount = DUST_COUNT
	_dust.lifetime = DUST_LIFETIME
	_dust.explosiveness = 0.0
	_dust.direction = Vector2(0.0, -1.0)
	_dust.spread = 35.0
	_dust.initial_velocity_min = 5.0
	_dust.initial_velocity_max = 13.0
	_dust.gravity = Vector2.ZERO
	_dust.scale_amount_min = 0.5
	_dust.scale_amount_max = 1.2
	_dust.color = Color(0.82, 0.90, 1.0, 0.32)
	_dust.texture = GateEntryStyle.radial_glow(
		16, Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.local_coords = false
	_art_layer.add_child(_dust)
	_forecourt = GateHeroForecourt.new()
	_forecourt.name = &"Forecourt"
	_forecourt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_layer.add_child(_forecourt)
	_flash = TextureRect.new()
	_flash.name = &"Flash"
	_flash.texture = GateEntryStyle.radial_glow(
		256, Color(1.0, 0.88, 0.62, 0.85), Color(1.0, 0.88, 0.62, 0.0))
	_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flash.stretch_mode = TextureRect.STRETCH_SCALE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.modulate.a = 0.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_layer.add_child(_flash)
	set_backdrop_visible(_backdrop_visible)


func _build_content() -> void:
	_content = Control.new()
	_content.name = &"Content"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_scrim = ColorRect.new()
	_scrim.name = &"Scrim"
	_scrim.color = SCRIM_COLOR
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.gui_input.connect(_on_scrim_input)
	_content.add_child(_scrim)
	_status_card = PanelContainer.new()
	_status_card.name = &"StatusCard"
	GateEntryStyle.apply_card(_status_card)
	_status_card.clip_contents = true
	_content.add_child(_status_card)
	_logged_out_box = _state_box(&"LoggedOut")
	_status_card.add_child(_logged_out_box)
	_hint = GateEntryStyle.make_label(
		"gate.auth.hint.logged_out", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.TEXT_DIM)
	_hint.name = &"Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_logged_out_box.add_child(_hint)
	_wrapped_labels.append(_hint)
	# The official doors first, then the always-usable guest door
	# below: Google, Apple, Guest, while unconfigured providers
	# read disabled.
	_provider_row = VBoxContainer.new()
	_provider_row.name = &"Providers"
	_provider_row.add_theme_constant_override(
		&"separation", PROVIDER_SEPARATION_FULL)
	_provider_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logged_out_box.add_child(_provider_row)
	_guest_button = GateEntryStyle.make_button(
		"gate.auth.guest", "portal")
	_guest_button.name = &"Guest"
	_guest_button.pressed.connect(_on_guest)
	_logged_out_box.add_child(_guest_button)
	_provider_note = GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_SMALL, GateEntryStyle.TEXT_FAINT)
	_provider_note.name = &"ProviderNote"
	_provider_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_provider_note.max_lines_visible = 3
	_provider_note.clip_text = true
	_logged_out_box.add_child(_provider_note)
	_wrapped_labels.append(_provider_note)
	_unconfigured_note = GateEntryStyle.make_label(
		"gate.auth.unconfigured", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.ACCENT_AMBER)
	_unconfigured_note.name = &"Unconfigured"
	_unconfigured_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_logged_out_box.add_child(_unconfigured_note)
	_wrapped_labels.append(_unconfigured_note)
	_consent = RichTextLabel.new()
	_consent.name = &"Consent"
	_consent.bbcode_enabled = true
	_consent.scroll_active = false
	_consent.fit_content = true
	_consent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_consent.mouse_filter = Control.MOUSE_FILTER_STOP
	# Noto alone, never the Maple+Noto pair: a RichTextLabel sizes its
	# line from one run's font (measured 15px Maple vs 18px Noto at
	# 12px), and with mixed runs Korean Hangul would clip 3px under
	# the clip the label keeps on. Noto covers all five consent
	# scripts at one 18px line height.
	_consent.add_theme_font_override(
		"normal_font", load(GateEntryStyle.CJK_FONT_PATH) as Font)
	_consent.add_theme_font_size_override(
		"normal_font_size", GateEntryStyle.FONT_SMALL)
	_consent.add_theme_color_override(
		"default_color", GateEntryStyle.TEXT_FAINT)
	_consent.meta_clicked.connect(_on_consent_meta)
	_logged_out_box.add_child(_consent)
	_refresh_consent()
	# One compact footer: the inline consent above carries both legal
	# links, so only the way back to the tap screen stays here. A
	# stacked Back would not fit the 360px base height.
	var footer := HBoxContainer.new()
	footer.name = &"Footer"
	footer.add_theme_constant_override(&"separation", 8)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logged_out_box.add_child(footer)
	_back_button = _footer_button(
		"gate.auth.back", &"Back", _on_selection_back)
	footer.add_child(_back_button)
	_busy_box = _state_box(&"Busy")
	_status_card.add_child(_busy_box)
	_working_label = GateEntryStyle.make_label(
		"gate.auth.working", GateEntryStyle.FONT_BODY,
		GateEntryStyle.TEXT_MAIN)
	_working_label.name = &"Working"
	_working_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_busy_box.add_child(_working_label)
	_wrapped_labels.append(_working_label)
	var cancel_button := GateEntryStyle.make_button("gate.auth.cancel")
	cancel_button.name = &"CancelLogin"
	cancel_button.pressed.connect(_on_cancel_login)
	_busy_box.add_child(cancel_button)
	_ready_box = _state_box(&"Ready")
	_status_card.add_child(_ready_box)
	var id_row := HBoxContainer.new()
	id_row.name = &"IdRow"
	id_row.add_theme_constant_override(&"separation", 8)
	_ready_box.add_child(id_row)
	_id_field = LineEdit.new()
	_id_field.name = &"StableId"
	_id_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_id_field.custom_minimum_size = Vector2(0.0, 36.0)
	GateEntryStyle.apply_id_field(_id_field)
	id_row.add_child(_id_field)
	var copy_button := GateEntryStyle.make_button("gate.auth.copy")
	copy_button.name = &"CopyId"
	copy_button.custom_minimum_size = Vector2(64.0, 36.0)
	copy_button.pressed.connect(_on_copy_id)
	id_row.add_child(copy_button)
	var hero_row := HBoxContainer.new()
	hero_row.name = &"HeroRow"
	hero_row.add_theme_constant_override(&"separation", 10)
	_ready_box.add_child(hero_row)
	_portrait = TextureRect.new()
	_portrait.name = &"Portrait"
	_portrait.custom_minimum_size = Vector2(40.0, 40.0)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_row.add_child(_portrait)
	var hero_text := VBoxContainer.new()
	hero_text.name = &"HeroText"
	hero_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_text.add_theme_constant_override(&"separation", 2)
	hero_row.add_child(hero_text)
	_hero_name = GateEntryStyle.make_label(
		"gate.auth.no_hero", GateEntryStyle.FONT_BODY,
		GateEntryStyle.TEXT_MAIN)
	_hero_name.name = &"HeroName"
	hero_text.add_child(_hero_name)
	_saved_line = GateEntryStyle.make_label(
		"gate.auth.no_save", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.TEXT_DIM)
	_saved_line.name = &"SavedLine"
	hero_text.add_child(_saved_line)
	var start_row := HBoxContainer.new()
	start_row.name = &"StartRow"
	start_row.add_theme_constant_override(&"separation", 8)
	_ready_box.add_child(start_row)
	_resume_button = GateEntryStyle.make_button(
		"gate.start.resume", "primary")
	_resume_button.name = &"Resume"
	_resume_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resume_button.pressed.connect(_on_resume)
	start_row.add_child(_resume_button)
	_start_button = GateEntryStyle.make_button("gate.start.new")
	_start_button.name = &"Start"
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.pressed.connect(_on_start)
	start_row.add_child(_start_button)
	# The account door lives inside the identity card now: a floating
	# corner button would sit on the original title's own doors.
	_account_button = GateEntryStyle.make_button("gate.menu.account")
	_account_button.name = &"Account"
	_account_button.custom_minimum_size = Vector2(0.0, 36.0)
	_account_button.pressed.connect(account_requested.emit)
	_ready_box.add_child(_account_button)
	_error_box = _state_box(&"Error")
	_status_card.add_child(_error_box)
	_error_title = GateEntryStyle.make_label(
		"gate.auth.error_title", GateEntryStyle.FONT_BODY,
		GateEntryStyle.CORAL, true)
	_error_title.name = &"ErrorTitle"
	_error_box.add_child(_error_title)
	_error_detail = GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_SMALL, GateEntryStyle.TEXT_DIM)
	_error_detail.name = &"ErrorDetail"
	_error_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_detail.max_lines_visible = 3
	_error_detail.clip_text = true
	_error_box.add_child(_error_detail)
	_wrapped_labels.append(_error_detail)
	var error_row := HBoxContainer.new()
	error_row.name = &"ErrorRow"
	error_row.add_theme_constant_override(&"separation", 8)
	_error_box.add_child(error_row)
	var retry_button := GateEntryStyle.make_button(
		"gate.auth.retry", "primary")
	retry_button.name = &"RetryLogin"
	retry_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry_button.pressed.connect(_on_retry_login)
	error_row.add_child(retry_button)
	_error_guest = GateEntryStyle.make_button(
		"gate.auth.guest", "portal")
	_error_guest.name = &"ErrorGuest"
	_error_guest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_error_guest.pressed.connect(_on_guest)
	error_row.add_child(_error_guest)
	var error_cancel := GateEntryStyle.make_button("gate.auth.cancel")
	error_cancel.name = &"ErrorCancel"
	error_cancel.pressed.connect(_on_cancel_login)
	error_row.add_child(error_cancel)
	_offline_badge = GateEntryStyle.make_label(
		"gate.auth.offline", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.ACCENT_AMBER)
	_offline_badge.name = &"OfflineBadge"
	_offline_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_content.add_child(_offline_badge)


func _build_panels() -> void:
	_account_panel = ACCOUNT_SCENE.instantiate() as GateAccountPanel
	add_child(_account_panel)
	_account_panel.analytics_opt_in_changed.connect(
		analytics_opt_in_changed.emit)
	_account_panel.external_link_requested.connect(
		external_link_requested.emit)
	_account_panel.id_copied.connect(id_copied.emit)
	_account_panel.closed.connect(account_closed.emit)
	_conflict_panel = CONFLICT_SCENE.instantiate() as GateConflictPanel
	add_child(_conflict_panel)
	_conflict_panel.resolved.connect(conflict_resolved.emit)
	_conflict_panel.cancelled.connect(conflict_cancelled.emit)
	_hall_panel = HALL_SCENE.instantiate() as GateHallPanel
	add_child(_hall_panel)
	_hall_panel.rows_closed.connect(hall_closed.emit)
	_exit_panel = EXIT_SCENE.instantiate() as GateExitPanel
	add_child(_exit_panel)
	_exit_panel.confirmed.connect(exit_confirmed.emit)
	_exit_panel.cancelled.connect(exit_cancelled.emit)
	_build_terms()
	_loader = LOADER_SCENE.instantiate() as GateLoadingOverlay
	add_child(_loader)
	_loader.finished.connect(_on_loader_finished)
	_loader.failed.connect(loading_failed.emit)
	_loader.cancelled.connect(loading_cancelled.emit)
	_loader.retry_requested.connect(loading_retry_requested.emit)
	_loader.return_requested.connect(loading_return_requested.emit)


## The in-app Terms sheet, built in code like the host's confirm card:
## the same dim-plus-centered-card shell the scene panels use, with a
## fixed scroll body so eight paragraphs fit the 360px base height. The
## dim stops every tap while open; hidden at rest it eats nothing.
func _build_terms() -> void:
	_terms_panel = Control.new()
	_terms_panel.name = &"GateTermsPanel"
	_terms_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_terms_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terms_panel.visible = false
	add_child(_terms_panel)
	var dim := ColorRect.new()
	dim.name = &"Dim"
	dim.color = GateEntryStyle.DIM_BG
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_terms_panel.add_child(dim)
	_terms_card = PanelContainer.new()
	_terms_card.name = &"Card"
	GateEntryStyle.apply_card(_terms_card)
	_terms_panel.add_child(_terms_card)
	var stack := VBoxContainer.new()
	stack.name = &"Stack"
	stack.add_theme_constant_override(&"separation", 8)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terms_card.add_child(stack)
	var title := GateEntryStyle.make_label(
		"gate.terms.title", GateEntryStyle.FONT_BODY,
		GateEntryStyle.TEXT_MAIN, true)
	title.name = &"Title"
	title.clip_text = true
	stack.add_child(title)
	_terms_scroll = ScrollContainer.new()
	_terms_scroll.name = &"Scroll"
	_terms_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_terms_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	stack.add_child(_terms_scroll)
	_terms_body = GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_SMALL, GateEntryStyle.TEXT_DIM)
	_terms_body.name = &"Body"
	_terms_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_terms_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_terms_scroll.add_child(_terms_body)
	var row := HBoxContainer.new()
	row.name = &"Row"
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(row)
	_terms_privacy = GateEntryStyle.make_button("gate.account.privacy")
	_terms_privacy.name = &"Privacy"
	_terms_privacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_terms_privacy.pressed.connect(_on_privacy)
	row.add_child(_terms_privacy)
	_terms_close = GateEntryStyle.make_button("gate.account.close")
	_terms_close.name = &"Close"
	_terms_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_terms_close.pressed.connect(_on_terms_close)
	row.add_child(_terms_close)


func _rebuild_provider_buttons() -> void:
	for child in _provider_row.get_children():
		_provider_row.remove_child(child)
		child.queue_free()
	# Display order: the ordinary doors first (host entries where the
	# platform lists them, disabled placeholders where it omits them),
	# then any extra ids the host sent (Play Games, passkeys) in host
	# order. `_providers` keeps the host truth for the notes below.
	var by_id: Dictionary = {}
	for entry in _providers:
		if entry is Dictionary and not str(entry.get("id", "")).is_empty():
			by_id[str(entry.get("id", ""))] = entry
	var display: Array = []
	for ordinary_id in ORDINARY_PROVIDER_IDS:
		if by_id.has(ordinary_id):
			display.append(by_id[ordinary_id])
		else:
			display.append({
				"id": ordinary_id,
				"label": str(ORDINARY_PROVIDER_NAMES[ordinary_id]),
				"ready": false,
			})
		by_id.erase(ordinary_id)
	for entry in _providers:
		if entry is Dictionary and by_id.has(str(entry.get("id", ""))):
			display.append(entry)
	var notes: Array[String] = []
	for entry in display:
		var data: Dictionary = entry
		var provider_id: String = str(data.get("id", ""))
		var label: String = str(data.get("label", provider_id))
		if provider_id.is_empty():
			continue
		var ready: bool = bool(data.get("ready", true))
		var draining: bool = bool(data.get("draining", false))
		var button: Button
		if GateProviderButtons.is_official_provider(provider_id):
			button = GateProviderButtons.make_provider_button(
				provider_id, "gate.auth.signin.%s" % provider_id)
		else:
			button = GateEntryStyle.make_button(label, "portal")
		button.name = &"Provider%s" % provider_id.capitalize()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not ready or draining
		button.pressed.connect(_on_provider_pressed.bind(provider_id))
		_provider_row.add_child(button)
		if draining:
			notes.append("%s · %s" % [label, GateEntryStrings.text(
				"gate.auth.draining")])
		elif not ready:
			notes.append("%s · %s" % [label, GateEntryStrings.text(
				"gate.auth.not_ready")])
	_provider_note.text = "\n".join(notes)
	_provider_note.visible = not notes.is_empty()
	# Rebuilt doors spawn on light mask 1; the modal boundary owns them.
	_isolate_modal_light()


func _relayout() -> void:
	if _status_card == null:
		return
	var view: Vector2 = get_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var card_width: float = minf(CARD_WIDTH, view.x - CARD_MARGIN * 2.0)
	var content: float = maxf(card_width - GateEntryStyle.CARD_MARGIN_H, 64.0)
	# Vertical budget is the viewport itself: the 12px side margins
	# stay, but a tall chooser may sit closer to the top and bottom
	# edges rather than hide consent or clip its rim. Nothing paints
	# outside: the card still centers from its read-back rect below.
	var max_height: float = maxf(view.y, 60.0)
	for label in _wrapped_labels:
		label.custom_minimum_size.x = content
	# The inline consent wraps at the same content width: unbounded, a
	# RichTextLabel reports a 1px column like the labels above.
	_consent.custom_minimum_size.x = content
	_apply_logged_out_compact(content, max_height)
	_reserve_clipped_note_heights()
	var want_height: float = _status_fitted_height(content)
	var card_size := Vector2(card_width, minf(want_height, max_height))
	# Size first, then center from the read-back rect: assigning below a
	# child's minimum clamps the size up, and centering from the request
	# would leave a clamped card off-center with its footer off-screen.
	_status_card.size = card_size
	_status_card.position = (view - _status_card.size) * 0.5
	_offline_badge.position = Vector2(EDGE_MARGIN, EDGE_MARGIN)
	_offline_badge.size = Vector2(280.0, 18.0)
	_gate_glow.position = Vector2(view.x - 140.0 - 140.0, view.y * 0.42 - 140.0)
	_hearth_glow.position = Vector2(50.0, view.y - 160.0)
	_mist_a_base = view.x * 0.25 - 280.0
	_mist_b_base = view.x * 0.55 - 320.0
	_mist_a.position = Vector2(_mist_a_base, view.y * 0.55)
	_mist_b.position = Vector2(_mist_b_base, view.y * 0.28)
	_dust.position = view * 0.5
	_dust.emission_rect_extents = view * 0.5
	_relayout_terms()
	if _reduced_motion:
		_refresh_motion()


## Terms sheet geometry: fixed width, explicit height from the title,
## the scroll body and the button row, always centered and inside.
func _relayout_terms() -> void:
	if _terms_card == null:
		return
	var view: Vector2 = get_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var width: float = minf(TERMS_CARD_WIDTH, view.x - 32.0)
	var content: float = maxf(width - GateEntryStyle.CARD_MARGIN_H, 64.0)
	# The vertical scrollbar reserves its width inside the scroll minimum
	# once the body overflows; without this gutter the card stretches by
	# exactly that width past its fitted 420. Read from the live bar, so
	# a theme change moves the text, not the card.
	var gutter: float = _terms_scroll.get_v_scroll_bar() \
		.get_combined_minimum_size().x
	_terms_body.custom_minimum_size.x = maxf(content - gutter, 64.0)
	var scroll_h: float = clampf(
		view.y - 210.0, TERMS_SCROLL_MIN, TERMS_SCROLL_MAX)
	_terms_scroll.custom_minimum_size = Vector2(0.0, scroll_h)
	var title_h: float = (_terms_card.get_node("Stack/Title") as Label) \
		.get_combined_minimum_size().y
	var height: float = title_h + 16.0 + scroll_h + 44.0 \
		+ GateEntryStyle.CARD_MARGIN_V
	height = minf(height, view.y - 16.0)
	_terms_card.size = Vector2(width, height).ceil()
	_terms_card.position = ((view - _terms_card.size) * 0.5).floor()


## Clipped wrapped labels report a 1px minimum and paint nothing until
## a real height is reserved: `clip_text` collapses the minimum no matter
## how many lines the text wraps to (measured on both notes here and on
## the loader's stage line). Reserve the rendered line block at the real
## content width before card layout, capped at the label's own max-lines
## budget. Recomputed every layout from live shaped lines, so clearing,
## shortening, locale and resize all shrink honestly with no stale gaps.
func _reserve_clipped_note_heights() -> void:
	for label in _wrapped_labels:
		if not label.clip_text \
				or label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			continue
		var font: Font = label.get_theme_font("font")
		var font_size: int = label.get_theme_font_size("font_size")
		var line: float = float(font.get_height(font_size))
		var spacing: float = float(
			label.get_theme_constant("line_spacing"))
		var lines: int = maxi(label.get_line_count(), 1)
		var need: float = float(lines) * line \
			+ float(lines - 1) * spacing
		if label.max_lines_visible > 0:
			var budget: int = label.max_lines_visible
			need = minf(need, float(budget) * line \
				+ float(budget - 1) * spacing)
		label.custom_minimum_size.y = need


## Compact logged-out layout, only while the honest fitted height
## exceeds the viewport. Stages shed in order: the hint first, then the
## stack and provider separations tighten to the 5px clearspace floor,
## then the guest and any extra doors drop to 40px. Every stage
## recomputes and stops early; a roomy layout resets it all. Consent is
## never hidden to fit, and the official 44px doors and the note glyph
## budgets never move.
func _apply_logged_out_compact(
		content_width: float, max_height: float) -> void:
	_hint.visible = true
	_logged_out_box.add_theme_constant_override(
		&"separation", LOGGED_OUT_SEPARATION_FULL)
	_provider_row.add_theme_constant_override(
		&"separation", PROVIDER_SEPARATION_FULL)
	_guest_button.custom_minimum_size = Vector2(
		GateEntryStyle.TOUCH_WIDTH, GateEntryStyle.TOUCH_HEIGHT)
	_reset_extra_heights()
	if _auth_mode != AUTH_LOGGED_OUT:
		return
	if _status_fitted_height(content_width) <= max_height:
		return
	_hint.visible = false
	if _status_fitted_height(content_width) <= max_height:
		return
	_logged_out_box.add_theme_constant_override(
		&"separation", LOGGED_OUT_SEPARATION_COMPACT)
	if _status_fitted_height(content_width) <= max_height:
		return
	_provider_row.add_theme_constant_override(
		&"separation", PROVIDER_SEPARATION_COMPACT)
	if _status_fitted_height(content_width) <= max_height:
		return
	_guest_button.custom_minimum_size = Vector2(
		GateEntryStyle.TOUCH_WIDTH, GUEST_HEIGHT_COMPACT)
	if _status_fitted_height(content_width) <= max_height:
		return
	_compact_extra_heights()


## Extra provider doors at full touch height. The official pair is
## never touched here: it keeps 44px in every layout.
func _reset_extra_heights() -> void:
	for child in _provider_row.get_children():
		if child.name == &"ProviderGoogle" \
				or child.name == &"ProviderApple":
			continue
		(child as Button).custom_minimum_size = Vector2(
			GateEntryStyle.TOUCH_WIDTH, GateEntryStyle.TOUCH_HEIGHT)


## Extra provider doors at compact touch height. Guest-adjacent extras
## shed with the guest; the official pair keeps 44px.
func _compact_extra_heights() -> void:
	for child in _provider_row.get_children():
		if child.name == &"ProviderGoogle" \
				or child.name == &"ProviderApple":
			continue
		(child as Button).custom_minimum_size = Vector2(
			GateEntryStyle.TOUCH_WIDTH, EXTRA_HEIGHT_COMPACT)


## Fitted height of whichever auth box is visible, measured wrapped at
## the real content width like every other gate card.
func _status_fitted_height(content_width: float) -> float:
	for box in [_logged_out_box, _busy_box, _ready_box, _error_box]:
		if box.visible:
			return GateEntryStyle.fitted_stack_height(
				box, content_width) + GateEntryStyle.CARD_MARGIN_V
	return 60.0


func _state_box(box_name: StringName) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = box_name
	box.add_theme_constant_override(&"separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


## One compact legal/back button sharing the footer row. Full label
## height is spared here so the whole selection still fits the base
## 360px height in every locale; the auth doors keep full touch height.
func _footer_button(
		key: String, button_name: StringName, on_press: Callable) -> Button:
	var button := GateEntryStyle.make_button(key)
	button.name = button_name
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_press)
	return button


func _glow_rect(glow_name: StringName, color: Color, rect_size: Vector2) -> TextureRect:
	var glow := TextureRect.new()
	glow.name = glow_name
	glow.texture = GateEntryStyle.radial_glow(
		128, color, Color(color.r, color.g, color.b, 0.0))
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.custom_minimum_size = rect_size
	glow.size = rect_size
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_layer.add_child(glow)
	return glow


## Dark-to-clear scrim over the art so card type stays legible on
## every framing without touching the painting.
func _legibility_shade() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.04, 0.09, 0.78))
	gradient.set_color(1, Color(0.02, 0.04, 0.09, 0.0))
	gradient.set_offset(1, 0.62)
	var shade := GradientTexture2D.new()
	shade.gradient = gradient
	shade.fill = GradientTexture2D.FILL_LINEAR
	shade.fill_from = Vector2(0.0, 0.5)
	shade.fill_to = Vector2(1.0, 0.5)
	shade.width = 256
	shade.height = 8
	return shade
