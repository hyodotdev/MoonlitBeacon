extends Node

## Moon gate entry states: auth flow, identity, panels, motion, music.
##
## The surface defaults to a real logged-out state and only moves when the
## host moves it. Every tap emits its signal; every host setter lands on
## screen with the supplied data and nothing invented. Reduced motion
## freezes the ambient layers while status keeps working.

const ENTRY_SCENE: PackedScene = preload("res://scenes/ui/gate_entry.tscn")
const PRODUCTION_SCENE: PackedScene = preload("res://scenes/menus/production_entry.tscn")
const WARDEN_PATH: String = "res://resources/heroes/warden.tres"
const KEEPER_PATH: String = "res://resources/heroes/keeper.tres"
const FORECOURT_HEROES: Array[String] = [
	"res://resources/heroes/warden.tres",
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/eclipse.tres",
	"res://resources/heroes/sage.tres",
]
const TEST_ID: String = "TEST-ID-STATE-7F3A"
const TEST_ERROR: String = "TEST sign-in failed: offline"
const MOTION_FRAMES: int = 10
const NOTE_LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const NOTE_FRAMINGS: Array[Vector2i] = [
	Vector2i(808, 360), Vector2i(840, 360), Vector2i(808, 606)]
const NOTE_PROVIDERS_UNREADY: Array = [
	{"id": "google", "label": "Google", "ready": true},
	{"id": "apple", "label": "Apple", "ready": false},
	{"id": "passkey", "label": "Passkey", "ready": true, "draining": true},
]
const NOTE_PROVIDERS_READY: Array = [
	{"id": "google", "label": "Google", "ready": true},
	{"id": "apple", "label": "Apple", "ready": true},
]
const NOTE_PROVIDERS_ALL_DRAINING: Array = [
	{"id": "google", "label": "Google", "ready": true, "draining": true},
	{"id": "apple", "label": "Apple", "ready": true, "draining": true},
	{"id": "passkey", "label": "Passkey", "ready": true, "draining": true},
]
const NOTE_PROVIDERS_ALL_UNREADY: Array = [
	{"id": "google", "label": "Google", "ready": false},
	{"id": "apple", "label": "Apple", "ready": false},
	{"id": "passkey", "label": "Passkey", "ready": false},
]
const NOTE_SHORT_DETAIL: String = "TEST sign-in failed: network unreachable"
const NOTE_LONG_DETAIL: String = "TEST sign-in failed: network unreachable while shaking the gateway hand. TEST sign-in failed: network unreachable while shaking the gateway hand. TEST sign-in failed: network unreachable while shaking the gateway hand."

var _failed: int = 0
var _checked: int = 0
var _fired: Dictionary = {}


## Stand-in behind the booted production entry: a logged-out choice with
## no providers, so the launcher regression never touches real services.
class StubProductionHost extends Node:
	signal production_changed(state: Dictionary)
	signal production_conflict(local: Dictionary, cloud: Dictionary)
	signal production_error(error: Dictionary)

	func startup() -> void:
		pass

	func providers_for_entry() -> Array:
		return []

	func identity_for_entry() -> Dictionary:
		return {"stable_id": ""}

	func account_state() -> Dictionary:
		return {"offline": false}

	func saved_gate_summary() -> Dictionary:
		return {"has_save": false}

	func note_first_paint() -> void:
		pass


func _ready() -> void:
	get_tree().root.size = Vector2i(808, 360)
	var original_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	await _test_default_logged_out()
	await _test_providers()
	await _test_busy_and_error()
	await _test_identity()
	await _test_title_rest()
	await _test_backdrop()
	await _test_terms()
	await _test_doors_and_account()
	await _test_account_links()
	await _test_account_actions()
	await _test_conflict()
	await _test_hall()
	await _test_exit()
	await _test_reduced_motion()
	await _test_music()
	await _test_button_faces()
	await _test_forecourt_identity()
	await _test_paint_bounds()
	await _test_forecourt_transparency()
	await _test_forecourt_motion()
	await _test_production_launcher()
	await _test_production_title_first()
	await _test_note_glyphs()
	await _test_official_provider_buttons()
	await _test_official_accessible_action_follows_locale()
	await _test_consent_links_exact()
	await _test_google_glyph_truth()
	await _test_apple_artwork_centering()
	await _test_light_isolation()
	TranslationServer.set_locale(original_locale)
	if _failed > 0:
		printerr("gate-entry-state test failed — ",
			_failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("gate-entry-state test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _make_entry() -> GateEntry:
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	return entry


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _watch(entry: GateEntry) -> void:
	_fired.clear()
	var keys: Array[String] = ["provider", "provider_id", "cancelled",
		"retry", "guest", "closed", "start", "resume", "hall", "chronicle",
		"heroes", "shop", "settings", "account", "analytics", "id_copied",
		"link", "resolved", "conflict_cancelled", "hall_closed",
		"exit_yes", "exit_no", "music"]
	for key in keys:
		_fired[key] = []
	entry.provider_login_requested.connect(
		func(provider_id: String) -> void: _fired["provider"].append(provider_id))
	entry.login_cancelled.connect(
		func(provider_id: String) -> void: _fired["cancelled"].append(provider_id))
	entry.login_retry_requested.connect(
		func(provider_id: String) -> void: _fired["retry"].append(provider_id))
	entry.guest_requested.connect(
		func() -> void: _fired["guest"].append(true))
	entry.selection_closed.connect(
		func() -> void: _fired["closed"].append(true))
	entry.start_requested.connect(
		func() -> void: _fired["start"].append(true))
	entry.resume_requested.connect(
		func() -> void: _fired["resume"].append(true))
	entry.hall_requested.connect(
		func() -> void: _fired["hall"].append(true))
	entry.chronicle_requested.connect(
		func() -> void: _fired["chronicle"].append(true))
	entry.heroes_requested.connect(
		func() -> void: _fired["heroes"].append(true))
	entry.shop_requested.connect(
		func() -> void: _fired["shop"].append(true))
	entry.settings_requested.connect(
		func() -> void: _fired["settings"].append(true))
	entry.account_requested.connect(
		func() -> void: _fired["account"].append(true))
	entry.analytics_opt_in_changed.connect(
		func(enabled: bool) -> void: _fired["analytics"].append(enabled))
	entry.id_copied.connect(
		func(stable_id: String) -> void: _fired["id_copied"].append(stable_id))
	entry.external_link_requested.connect(
		func(url: String) -> void: _fired["link"].append(url))
	entry.conflict_resolved.connect(
		func(which: StringName) -> void: _fired["resolved"].append(which))
	entry.conflict_cancelled.connect(
		func() -> void: _fired["conflict_cancelled"].append(true))
	entry.hall_closed.connect(
		func() -> void: _fired["hall_closed"].append(true))
	entry.exit_confirmed.connect(
		func() -> void: _fired["exit_yes"].append(true))
	entry.exit_cancelled.connect(
		func() -> void: _fired["exit_no"].append(true))
	entry.music_intent.connect(
		func(intent: StringName) -> void: _fired["music"].append(intent))


func _press(entry: GateEntry, path: String) -> void:
	(entry.get_node(path) as Button).pressed.emit()


func _test_default_logged_out() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	_expect_true(entry.get_node("Content/StatusCard/LoggedOut").visible,
		"default: logged-out card shows")
	_expect_true(entry.get_node("Content/StatusCard/LoggedOut/Guest").visible,
		"default: guest entry usable with no providers")
	_expect_true(
		(entry.get_node("Content/StatusCard/LoggedOut/Guest") as Button) \
			.disabled == false, "default: guest enabled")
	_expect_true(
		entry.get_node("Content/StatusCard/LoggedOut/Unconfigured").visible,
		"default: unconfigured note honest about missing providers")
	_expect_true(not entry.get_node("Content/StatusCard/Busy").visible,
		"default: no busy state")
	_expect_true(not entry.get_node("Content/StatusCard/Ready").visible,
		"default: no invented identity")
	_expect_true(not entry.get_node("Content/StatusCard/Error").visible,
		"default: no error")
	# The gate keeps no menu bar or shop door of its own: the original
	# title's buttons are the doors (Brief 096 presentation change).
	_expect_true(entry.get_node_or_null("Content/Menu") == null,
		"default: no gate menu bar over the title's doors")
	_expect_true(entry.get_music_intent() == &"play",
		"default: music intent is play")
	_expect_true(not entry.get_loader().visible,
		"default: loader hidden at rest")
	_press(entry, "Content/StatusCard/LoggedOut/Guest")
	_expect_true(_fired["guest"] == [true], "default: guest tap signals")
	entry.queue_free()
	await _frames(2)


func _test_providers() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	entry.set_providers([
		{"id": "google", "label": "Google", "ready": true},
		{"id": "apple", "label": "Apple", "ready": false},
	])
	await _frames(2)
	var row: VBoxContainer = entry.get_node(
		"Content/StatusCard/LoggedOut/Providers") as VBoxContainer
	_expect_true(row.get_child_count() == 2,
		"providers: only supplied providers shown")
	var google: Button = row.get_child(0) as Button
	var apple: Button = row.get_child(1) as Button
	var gtitle := GateProviderButtons.title_node(google)
	var atitle := GateProviderButtons.title_node(apple)
	_expect_true(gtitle.text == "gate.auth.signin.google",
		"providers: google reads the official action key")
	_expect_true(tr(gtitle.text).contains("Google"),
		"providers: google action names the brand")
	_expect_true(atitle.text == "gate.auth.signin.apple",
		"providers: apple reads the official action key")
	_expect_true(not google.disabled, "providers: ready provider enabled")
	_expect_true(apple.disabled, "providers: unready provider disabled")
	_check_official_door(google, "google", "providers")
	_check_official_door(apple, "apple", "providers")
	_expect_true(
		(google.get_theme_stylebox("normal") as StyleBoxFlat).bg_color \
			== Color(1, 1, 1),
		"providers: google wears its brand white, not a game frame")
	var note: Label = entry.get_node(
		"Content/StatusCard/LoggedOut/ProviderNote") as Label
	_expect_true(note.visible and note.text.contains("Apple"),
		"providers: unready note names the provider")
	_expect_true(not entry.get_node(
		"Content/StatusCard/LoggedOut/Unconfigured").visible,
		"providers: configured note hides the unconfigured line")
	google.pressed.emit()
	_expect_true(_fired["provider"] == ["google"],
		"providers: tap requests the real login")
	entry.show_busy("google", "Google")
	await _frames(2)
	google.pressed.emit()
	_expect_true(_fired["provider"] == ["google"],
		"providers: no second request while busy")
	entry.show_logged_out()
	await _frames(2)
	# The official doors first, then the always-usable guest door
	# below the provider stack (Brief 125 ordering change).
	var guest: Button = entry.get_node(
		"Content/StatusCard/LoggedOut/Guest") as Button
	_expect_true(guest.get_global_rect().position.y \
		>= row.get_global_rect().end.y - 0.5,
		"providers: guest sits below the provider stack")
	_expect_true(guest.custom_minimum_size.y >= 40.0,
		"providers: guest keeps its touch height")
	_expect_true(google.custom_minimum_size.y == 44.0 \
		and apple.custom_minimum_size.y == 44.0,
		"providers: official doors keep equal 44px prominence")
	_expect_true(
		(guest.get_theme_stylebox("normal") as GateFrameStyle).accent() \
			== GateFrameStyle.Accent.MINT,
		"providers: guest keeps the portal accent")
	var consent: RichTextLabel = entry.get_node(
		"Content/StatusCard/LoggedOut/Consent") as RichTextLabel
	_expect_true(consent.visible \
		and not consent.get_parsed_text().begins_with("gate.") \
		and consent.text.contains("[url=tos]") \
		and consent.text.contains("[url=privacy]"),
		"providers: consent shows both inline links")
	_expect_true(entry.get_node_or_null(
		"Content/StatusCard/LoggedOut/Footer/Privacy") == null,
		"providers: no redundant footer privacy door")
	_expect_true(entry.get_node_or_null(
		"Content/StatusCard/LoggedOut/Footer/Terms") == null,
		"providers: no redundant footer terms door")
	_expect_true((entry.get_node(
		"Content/StatusCard/LoggedOut/Footer/Back") as Button).visible,
		"providers: back door shown")
	_press(entry, "Content/StatusCard/LoggedOut/Footer/Back")
	_expect_true(_fired["closed"] == [true],
		"providers: footer back closes the selection")
	entry.queue_free()
	await _frames(2)


func _test_busy_and_error() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	entry.set_providers([{"id": "google", "label": "Google"}])
	entry.show_busy("google", "Google")
	await _frames(2)
	var working: Label = entry.get_node(
		"Content/StatusCard/Busy/Working") as Label
	_expect_true(working.text.contains("Google"),
		"busy: working line names the provider")
	_press(entry, "Content/StatusCard/Busy/CancelLogin")
	_expect_true(_fired["cancelled"] == ["google"],
		"busy: cancel signals with the provider id")
	entry.show_error(TEST_ERROR)
	await _frames(2)
	var detail: Label = entry.get_node(
		"Content/StatusCard/Error/ErrorDetail") as Label
	_expect_true(detail.text == TEST_ERROR,
		"error: host detail shown as given")
	_press(entry, "Content/StatusCard/Error/ErrorRow/RetryLogin")
	_expect_true(_fired["retry"] == ["google"],
		"error: retry signals with the provider id")
	_press(entry, "Content/StatusCard/Error/ErrorRow/ErrorGuest")
	_expect_true(_fired["guest"] == [true],
		"error: guest stays usable after a failure")
	entry.queue_free()
	await _frames(2)


func _test_identity() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	var warden: Hero = load(WARDEN_PATH) as Hero
	entry.set_providers([{"id": "google", "label": "Google"}])
	entry.show_identity(
		{"stable_id": TEST_ID, "hero": warden},
		{"has_save": true, "title": "TEST Gate 2", "detail": ""})
	await _frames(2)
	var field: LineEdit = entry.get_node(
		"Content/StatusCard/Ready/IdRow/StableId") as LineEdit
	_expect_true(field.text == TEST_ID,
		"identity: full stable id readable")
	var portrait: TextureRect = entry.get_node(
		"Content/StatusCard/Ready/HeroRow/Portrait") as TextureRect
	_expect_true(portrait.visible and portrait.texture == warden.portrait,
		"identity: real hero portrait shown")
	var hero_name: Label = entry.get_node(
		"Content/StatusCard/Ready/HeroRow/HeroText/HeroName") as Label
	_expect_true(hero_name.text == tr(warden.display_name),
		"identity: hero name translated from the resource")
	var saved: Label = entry.get_node(
		"Content/StatusCard/Ready/HeroRow/HeroText/SavedLine") as Label
	_expect_true(saved.text == "TEST Gate 2",
		"identity: saved-gate summary shown")
	_expect_true(entry.get_node(
		"Content/StatusCard/Ready/StartRow/Resume").visible,
		"identity: resume offered with a save")
	_press(entry, "Content/StatusCard/Ready/IdRow/CopyId")
	_expect_true(_fired["id_copied"] == [TEST_ID],
		"identity: copy affordance signals the id")
	_press(entry, "Content/StatusCard/Ready/StartRow/Resume")
	_press(entry, "Content/StatusCard/Ready/StartRow/Start")
	_expect_true(_fired["resume"] == [true], "identity: resume signals")
	_expect_true(_fired["start"] == [true], "identity: start signals")
	entry.show_identity({"stable_id": TEST_ID, "hero": warden},
		{"has_save": false})
	await _frames(2)
	_expect_true(not entry.get_node(
		"Content/StatusCard/Ready/StartRow/Resume").visible,
		"identity: no resume without a save")
	_expect_true(entry.get_node(
		"Content/StatusCard/Ready/StartRow/Start").visible,
		"identity: start stays without a save")
	entry.show_identity({"stable_id": "", "hero_name": ""}, {})
	await _frames(2)
	_expect_true(not (entry.get_node(
		"Content/StatusCard/Ready/HeroRow/Portrait") as TextureRect).visible,
		"identity: no portrait invented when none supplied")
	_expect_true((entry.get_node(
		"Content/StatusCard/Ready/HeroRow/HeroText/HeroName") as Label) \
		.text == "gate.auth.no_hero",
		"identity: honest empty hero line")
	entry.queue_free()
	await _frames(2)


func _test_title_rest() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	entry.set_providers([{"id": "google", "label": "Google"}])
	entry.show_title_rest()
	await _frames(2)
	_expect_true(not entry.is_selection_open(),
		"rest: no selection while the title holds the screen")
	_expect_true(not (entry.get_node("Content/StatusCard") as Control
		).visible, "rest: card parked")
	_expect_true(not (entry.get_node("Content/Scrim") as Control).visible,
		"rest: scrim parked")
	for box_name in ["LoggedOut", "Busy", "Ready", "Error"]:
		_expect_true(not (entry.get_node(
			"Content/StatusCard/" + box_name) as Control).visible,
			"rest: no %s box" % box_name.to_lower())
	_expect_true(entry.get_forecourt().actor_count() == 6,
		"rest: the lineup keeps standing")
	entry.show_logged_out()
	await _frames(2)
	_expect_true(entry.is_selection_open(),
		"rest: tap opens the selection")
	_expect_true((entry.get_node("Content/StatusCard") as Control).visible,
		"rest: card back with the selection")
	# The scrim tap only ever closes the selection: busy keeps its
	# explicit cancel, and nothing else may dismiss it by stray tap.
	var tap := InputEventMouseButton.new()
	tap.pressed = true
	tap.button_index = MOUSE_BUTTON_LEFT
	entry._on_scrim_input(tap)
	_expect_true(_fired["closed"] == [true],
		"rest: scrim tap closes the selection")
	entry.show_busy("google", "Google")
	await _frames(2)
	entry._on_scrim_input(tap)
	_expect_true(_fired["closed"] == [true],
		"rest: scrim tap never dismisses busy")
	entry.show_identity({"stable_id": TEST_ID}, {"has_save": false})
	await _frames(2)
	entry._on_scrim_input(tap)
	_expect_true(_fired["closed"] == [true],
		"rest: scrim tap never dismisses ready")
	entry.queue_free()
	await _frames(2)


func _test_backdrop() -> void:
	var entry: GateEntry = _make_entry()
	await _frames(3)
	entry.set_backdrop_visible(false)
	await _frames(1)
	for layer_name in ["Art", "Shade", "GateGlow", "HearthGlow", "MistA",
			"MistB", "Dust", "Flash"]:
		_expect_true(not (entry.get_node("ArtLayer/" + layer_name
			) as CanvasItem).visible,
			"backdrop: %s hidden for the title" % layer_name)
	_expect_true((entry.get_node("ArtLayer/Forecourt") as Control).visible,
		"backdrop: the lineup stays over the title")
	entry.set_backdrop_visible(true)
	await _frames(1)
	for layer_name in ["Art", "Shade", "GateGlow", "HearthGlow", "MistA",
			"MistB", "Dust", "Flash"]:
		_expect_true((entry.get_node("ArtLayer/" + layer_name
			) as CanvasItem).visible,
			"backdrop: %s restored" % layer_name)
	entry.queue_free()
	await _frames(2)


func _test_terms() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	entry.set_providers([{"id": "google", "label": "Google"}])
	entry.show_logged_out()
	await _frames(2)
	_expect_true(not (entry.get_node("GateTermsPanel") as Control).visible,
		"terms: sheet hidden at rest")
	var consent: RichTextLabel = entry.get_node(
		"Content/StatusCard/LoggedOut/Consent") as RichTextLabel
	consent.meta_clicked.emit("tos")
	await _frames(2)
	var panel: Control = entry.get_node("GateTermsPanel") as Control
	_expect_true(panel.visible, "terms: inline link opens the sheet")
	_expect_true((panel.get_node("Dim") as Control).mouse_filter \
		== Control.MOUSE_FILTER_STOP,
		"terms: dim stops pass-through taps")
	var title: Label = panel.get_node("Card/Stack/Title") as Label
	_expect_true(tr(title.text) != title.text,
		"terms: title resolves, never a raw key")
	var body: Label = panel.get_node("Card/Stack/Scroll/Body") as Label
	_expect_true(body.text.count("\n\n") == GateEntry.TERMS_PARAGRAPHS - 1,
		"terms: all eight paragraphs read")
	_expect_true(not body.text.begins_with("gate."),
		"terms: body resolved, never raw keys")
	_expect_true(_fired["guest"].is_empty() and _fired["start"].is_empty() \
		and _fired["resume"].is_empty() and _fired["provider"].is_empty(),
		"terms: opening starts no login and no run")
	_expect_true(not entry.get_loader().is_loading(),
		"terms: loader idle while reading")
	consent.meta_clicked.emit("privacy")
	_expect_true(_fired["link"].size() == 1 \
		and str(_fired["link"][0]).begins_with("https://"),
		"terms: inline privacy hands a safe url to the host")
	(panel.get_node("Card/Stack/Row/Privacy") as Button).pressed.emit()
	_expect_true(_fired["link"].size() == 2 \
		and str(_fired["link"][1]).begins_with("https://"),
		"terms: sheet privacy hands a safe url to the host")
	_expect_true(entry.is_selection_open(),
		"terms: links never leave the selection")
	_press(entry, "GateTermsPanel/Card/Stack/Row/Close")
	await _frames(2)
	_expect_true(not panel.visible, "terms: close shuts the sheet")
	_expect_true(entry.is_selection_open(),
		"terms: close returns to the same selection")
	consent.meta_clicked.emit("tos")
	await _frames(2)
	_expect_true(panel.visible, "terms: link reopens the sheet")
	entry.close_panels()
	_expect_true(not panel.visible, "terms: host unwind shuts the sheet")
	entry.queue_free()
	await _frames(2)


func _test_doors_and_account() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	# No gate menu bar: the routing signals stay provable by direct
	# emission while the title's original buttons are the real doors.
	entry.hall_requested.emit()
	entry.chronicle_requested.emit()
	entry.heroes_requested.emit()
	entry.shop_requested.emit()
	entry.settings_requested.emit()
	_expect_true(_fired["hall"] == [true], "doors: hall signals")
	_expect_true(_fired["chronicle"] == [true], "doors: chronicle signals")
	_expect_true(_fired["heroes"] == [true], "doors: heroes signals")
	_expect_true(_fired["shop"] == [true], "doors: shop signals")
	_expect_true(_fired["settings"] == [true], "doors: settings signals")
	entry.show_identity({"stable_id": TEST_ID}, {"has_save": false})
	await _frames(2)
	_press(entry, "Content/StatusCard/Ready/Account")
	_expect_true(_fired["account"] == [true], "doors: account signals")
	var keeper: Hero = load(KEEPER_PATH) as Hero
	entry.open_account({
		"stable_id": TEST_ID, "hero": keeper, "provider_label": "Google",
		"saved_title": "TEST Gate 2", "saved_detail": "",
		"analytics_opt_in": false, "show_links": true})
	await _frames(2)
	var panel: GateAccountPanel = entry.get_node("GateAccountPanel") \
		as GateAccountPanel
	_expect_true(panel.visible, "account: panel opens with host data")
	var id_field: LineEdit = panel.get_node_or_null(
		"Card/Stack/Scroll/ScrollBox/StableId") as LineEdit
	_expect_true(id_field != null,
		"account: scrolled id field present")
	if id_field == null:
		entry.queue_free()
		await _frames(2)
		return
	_expect_true(id_field.text == TEST_ID,
		"account: full id readable")
	var analytics: Button = panel.get_node(
		"Card/Stack/Scroll/ScrollBox/AnalyticsOptIn") as Button
	_expect_true(analytics.button_pressed == false,
		"account: analytics opt-in defaults off")
	analytics.toggled.emit(true)
	_expect_true(_fired["analytics"] == [true],
		"account: analytics toggle signals the host")
	entry.open_account({
		"stable_id": TEST_ID, "analytics_opt_in": true,
		"show_links": true})
	await _frames(2)
	_expect_true((panel.get_node(
		"Card/Stack/Scroll/ScrollBox/AnalyticsOptIn") as Button) \
		.button_pressed == true,
		"account: host opt-in state lands on the toggle")
	var privacy: Button = panel.get_node("Card/Stack/Links/Privacy") as Button
	_expect_true(privacy.visible, "account: existing privacy link shown")
	privacy.pressed.emit()
	_expect_true(_fired["link"].size() == 1 \
		and str(_fired["link"][0]).begins_with("https://"),
		"account: privacy tap hands a safe url to the host")
	entry.queue_free()
	await _frames(2)


## Account link doors are the entry's own official factory faces
## with the exact entry action labels: brand geometry, Latin brands,
## honest readiness, per-door link ids, and game controls for extras.
func _test_account_links() -> void:
	var original_locale: String = TranslationServer.get_locale()
	for locale in NOTE_LOCALES:
		TranslationServer.set_locale(locale)
		var tag: String = "account-link/%s" % locale
		var entry: GateEntry = _make_entry()
		await _frames(3)
		entry.set_providers([])
		var panel: GateAccountPanel = entry.get_node(
			"GateAccountPanel") as GateAccountPanel
		var fired_links: Array = []
		panel.link_requested.connect(
			func(provider_id: String) -> void:
				fired_links.append(provider_id))
		entry.open_account({
			"stable_id": TEST_ID, "provider_label": "Google",
			"saved_title": "TEST Gate 2", "saved_detail": "",
			"analytics_opt_in": false, "show_links": true,
			"link_providers": NOTE_PROVIDERS_UNREADY,
			"can_sign_out": true, "can_delete": true})
		await _frames(2)
		var google: Button = panel.get_node_or_null(
			"Card/Stack/Scroll/ScrollBox/LinkRow/LinkGoogle") as Button
		var apple: Button = panel.get_node_or_null(
			"Card/Stack/Scroll/ScrollBox/LinkRow/LinkApple") as Button
		var extra: Button = panel.get_node_or_null(
			"Card/Stack/Scroll/ScrollBox/LinkRow/LinkPasskey") as Button
		_expect_true(google != null and apple != null \
			and extra != null,
			tag + ": link doors present")
		if google == null or apple == null or extra == null:
			entry.queue_free()
			await _frames(2)
			continue
		_check_official_door(google, "google", tag)
		_check_official_door(apple, "apple", tag)
		_check_official_pair(google, apple, tag)
		var gtitle := GateProviderButtons.title_node(google)
		var atitle := GateProviderButtons.title_node(apple)
		_expect_true(tr(gtitle.text).contains("Google") \
			and tr(atitle.text).contains("Apple"),
			tag + ": actions keep Latin brand names")
		var entry_google := GateProviderButtons.title_node(
			entry.get_node(
				"Content/StatusCard/LoggedOut/Providers/ProviderGoogle"
				) as Button)
		_expect_true(gtitle.text == entry_google.text,
			tag + ": link reuses the entry action label")
		_expect_true(not google.disabled and apple.disabled \
			and extra.disabled,
			tag + ": readiness stays honest")
		_expect_true(extra.text == "Passkey",
			tag + ": extra door keeps its host label")
		for state_name in ["normal", "hover", "pressed", "disabled"]:
			var face: StyleBox = extra.get_theme_stylebox(state_name)
			_expect_true(face is GateFrameStyle,
				tag + ": extra %s is authored, not flat" % state_name)
			_expect_true(not (face is StyleBoxFlat),
				tag + ": extra %s is no flat box" % state_name)
		_expect_true(extra.custom_minimum_size.y == 44.0,
			tag + ": extra keeps 44px")
		google.pressed.emit()
		_expect_true(fired_links == ["google"],
			tag + ": google tap requests its link id")
		# Disabled doors take no real taps; the programmatic emission
		# below only proves the id binding, never a tap path.
		apple.pressed.emit()
		_expect_true(fired_links == ["google", "apple"],
			tag + ": apple binds its own link id")
		entry.queue_free()
		await _frames(2)
	TranslationServer.set_locale(original_locale)


## Account actions: sign-out and the two-step delete with a safe
## cancel, Close and back, reveal/copy, and the legal footer.
func _test_account_actions() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	var panel: GateAccountPanel = entry.get_node(
		"GateAccountPanel") as GateAccountPanel
	_expect_true(not panel.visible, "actions: panel hidden at rest")
	_expect_true((panel.get_node("Dim") as ColorRect).mouse_filter \
		== Control.MOUSE_FILTER_STOP,
		"actions: dim stops pass-through taps")
	_expect_true(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"actions: the shell itself eats no taps")
	var sign_outs: Array = []
	var deletes: Array = []
	var closes: Array = []
	panel.sign_out_requested.connect(
		func() -> void: sign_outs.append(true))
	panel.delete_requested.connect(
		func() -> void: deletes.append(true))
	panel.closed.connect(func() -> void: closes.append(true))
	var keeper: Hero = load(KEEPER_PATH) as Hero
	var data: Dictionary = {
		"stable_id": TEST_ID, "hero": keeper,
		"provider_label": "Google", "saved_title": "TEST Gate 2",
		"saved_detail": "", "analytics_opt_in": false,
		"show_links": true, "can_sign_out": true, "can_delete": true,
	}
	entry.open_account(data)
	await _frames(2)
	_expect_true(panel.visible, "actions: panel opens")
	var actions: HBoxContainer = panel.get_node_or_null(
		"Card/Stack/Scroll/ScrollBox/AccountActions") as HBoxContainer
	var confirm: HBoxContainer = panel.get_node_or_null(
		"Card/Stack/Scroll/ScrollBox/DeleteConfirm") as HBoxContainer
	_expect_true(actions != null and confirm != null,
		"actions: scrolled action rows present")
	if actions == null or confirm == null:
		entry.queue_free()
		await _frames(2)
		return
	(actions.get_node("SignOut") as Button).pressed.emit()
	_expect_true(sign_outs == [true] and deletes.is_empty(),
		"actions: sign-out signals once and deletes nothing")
	(panel.get_node(
		"Card/Stack/Scroll/ScrollBox/AccountActions/DeleteAccount"
		) as Button).pressed.emit()
	_expect_true(confirm.visible and not actions.visible,
		"actions: first tap only arms the delete")
	_expect_true(deletes.is_empty(),
		"actions: arming deletes nothing")
	(panel.get_node(
		"Card/Stack/Scroll/ScrollBox/DeleteConfirm/DeleteKeep"
		) as Button).pressed.emit()
	_expect_true(actions.visible and not confirm.visible,
		"actions: cancel restores the actions")
	_expect_true(deletes.is_empty(),
		"actions: cancel-before-delete deletes nothing")
	(panel.get_node(
		"Card/Stack/Scroll/ScrollBox/AccountActions/DeleteAccount"
		) as Button).pressed.emit()
	(panel.get_node(
		"Card/Stack/Scroll/ScrollBox/DeleteConfirm/DeleteNow"
		) as Button).pressed.emit()
	_expect_true(deletes == [true],
		"actions: confirm deletes once")
	# Every opening starts unarmed.
	entry.open_account(data)
	await _frames(2)
	_expect_true(actions.visible and not confirm.visible,
		"actions: reopening disarms")
	# Close and the back branch both shut the panel.
	(panel.get_node("Card/Stack/Links/Close") as Button).pressed.emit()
	_expect_true(not panel.visible and closes == [true],
		"actions: close shuts the panel")
	entry.open_account(data)
	await _frames(2)
	panel._on_background_cancel()
	_expect_true(not panel.visible and closes == [true, true],
		"actions: back shuts the panel")
	# Reveal toggles the secret; copy hands the id to the host.
	entry.open_account(data)
	await _frames(2)
	var field: LineEdit = panel.get_node(
		"Card/Stack/Scroll/ScrollBox/StableId") as LineEdit
	var reveal: Button = panel.get_node(
		"Card/Stack/Scroll/ScrollBox/IdRow/RevealToggle") as Button
	reveal.pressed.emit()
	_expect_true(field.secret \
		and reveal.text == "gate.auth.show_id",
		"actions: reveal hides the id")
	reveal.pressed.emit()
	_expect_true(not field.secret \
		and reveal.text == "gate.auth.hide_id",
		"actions: reveal shows the id again")
	(panel.get_node(
		"Card/Stack/Scroll/ScrollBox/IdRow/CopyId") as Button).pressed.emit()
	_expect_true(_fired["id_copied"] == [TEST_ID],
		"actions: copy affordance signals the id")
	entry.open_account({"stable_id": "", "show_links": true})
	await _frames(2)
	(panel.get_node(
		"Card/Stack/Scroll/ScrollBox/IdRow/CopyId") as Button).pressed.emit()
	_expect_true(_fired["id_copied"] == [TEST_ID],
		"actions: empty id copies nothing")
	# The footer keeps its legal doors, and Close never hides with them.
	entry.open_account(data)
	await _frames(2)
	_fired["link"].clear()
	(panel.get_node("Card/Stack/Links/Support") as Button).pressed.emit()
	_expect_true(_fired["link"].size() == 1 \
		and str(_fired["link"][0]).begins_with("https://"),
		"actions: support tap hands a safe url to the host")
	data["show_links"] = false
	entry.open_account(data)
	await _frames(2)
	_expect_true(not (panel.get_node("Card/Stack/Links/Privacy"
		) as Button).visible \
		and not (panel.get_node("Card/Stack/Links/Support"
		) as Button).visible,
		"actions: hidden links hide their doors")
	_expect_true((panel.get_node("Card/Stack/Links/Close"
		) as Button).visible,
		"actions: close stays when links hide")
	entry.queue_free()
	await _frames(2)


func _test_conflict() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	entry.open_conflict(
		{"title": "TEST local 3", "detail": "TEST 1", "updated": "TEST u1"},
		{"title": "TEST cloud 5", "detail": "TEST 2", "updated": "TEST u2"})
	await _frames(2)
	var panel: GateConflictPanel = entry.get_node("GateConflictPanel") \
		as GateConflictPanel
	_expect_true(panel.visible, "conflict: panel opens")
	_expect_true((panel.get_node("Card/Stack/LocalTagTitle") as Label).text \
		== "TEST local 3", "conflict: local summary shown")
	_expect_true((panel.get_node("Card/Stack/CloudTagTitle") as Label).text \
		== "TEST cloud 5", "conflict: cloud summary shown")
	(panel.get_node("Card/Stack/Choices/KeepLocal") as Button).pressed.emit()
	_expect_true(_fired["resolved"] == [&"local"],
		"conflict: keep-local resolves explicitly")
	entry.open_conflict({"title": "TEST a"}, {"title": "TEST b"})
	await _frames(2)
	(panel.get_node("Card/Stack/Choices/DecideLater") as Button).pressed.emit()
	_expect_true(_fired["conflict_cancelled"] == [true],
		"conflict: decide-later cancels")
	entry.queue_free()
	await _frames(2)


func _test_hall() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	var warden: Hero = load(WARDEN_PATH) as Hero
	entry.open_hall([
		{"rank": 1, "score": 300, "id": "TEST-HALL-1", "hero": warden},
		{"rank": 2, "score": 150, "id": "TEST-HALL-2",
			"portrait": warden.portrait, "hero_name": "TEST Traveler"},
	], {"cached": true, "offline": true})
	await _frames(2)
	var panel: GateHallPanel = entry.get_node("GateHallPanel") \
		as GateHallPanel
	_expect_true(panel.row_count() == 2, "hall: supplied rows render")
	var first: PanelContainer = panel.get_node(
		"Card/Stack/Rows/RowsBox/HallRow0") as PanelContainer
	_expect_true((first.get_node("Line/Middle/Headline") as Label).text \
		== "#1 · 300", "hall: rank and score shown")
	_expect_true((first.get_node("Line/Middle/HeroLine") as Label).text \
		== tr(warden.display_name), "hall: hero name on its own line")
	_expect_true((first.get_node("Line/Middle/IdLine") as Label).text \
		== "TEST-HALL-1", "hall: full unique id on its own line")
	_expect_true((first.get_node("Line/Portrait") as TextureRect).texture \
		== warden.portrait, "hall: real hero portrait shown")
	_expect_true(panel.get_node("Card/Stack/Badges/CachedBadge").visible,
		"hall: cached label shown")
	_expect_true(panel.get_node("Card/Stack/Badges/OfflineBadge").visible,
		"hall: offline label shown")
	(panel.get_node("Card/Stack/Close") as Button).pressed.emit()
	_expect_true(_fired["hall_closed"] == [true], "hall: close signals")
	entry.open_hall([], {})
	await _frames(2)
	_expect_true(panel.row_count() == 0, "hall: no rows invented")
	_expect_true(panel.get_node("Card/Stack/Empty").visible,
		"hall: honest empty line")
	entry.queue_free()
	await _frames(2)


func _test_exit() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	entry.open_exit()
	await _frames(2)
	var panel: GateExitPanel = entry.get_node("GateExitPanel") \
		as GateExitPanel
	_expect_true(panel.visible, "exit: panel opens")
	(panel.get_node("Card/Stack/Choices/Stay") as Button).pressed.emit()
	_expect_true(_fired["exit_no"] == [true], "exit: stay cancels")
	entry.open_exit()
	await _frames(2)
	(panel.get_node("Card/Stack/Choices/End") as Button).pressed.emit()
	_expect_true(_fired["exit_yes"] == [true], "exit: end confirms")
	entry.queue_free()
	await _frames(2)


func _test_reduced_motion() -> void:
	var entry: GateEntry = _make_entry()
	await _frames(3)
	_expect_true(entry.is_motion_active(), "motion: ambient runs by default")
	var layer: Control = entry.get_node("ArtLayer") as Control
	var before: Vector2 = layer.position
	await _frames(MOTION_FRAMES)
	_expect_true(layer.position != before,
		"motion: art drifts with motion on")
	entry.set_reduced_motion(true)
	await _frames(2)
	_expect_true(not entry.is_motion_active(),
		"motion: reduced motion stops the ambient layers")
	_expect_true((entry.get_node("ArtLayer/Dust") as CPUParticles2D) \
		.emitting == false, "motion: dust stops")
	var frozen: Vector2 = layer.position
	await _frames(MOTION_FRAMES)
	_expect_true(layer.position == frozen,
		"motion: art holds still with reduced motion")
	_expect_true(entry.get_node(
		"Content/StatusCard/LoggedOut/Guest").visible,
		"motion: status and buttons stay readable")
	entry.set_reduced_motion(false)
	await _frames(2)
	_expect_true(entry.is_motion_active(),
		"motion: hospitality returns when re-enabled")
	entry.queue_free()
	await _frames(2)


func _test_music() -> void:
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	_expect_true(_fired["music"] == [&"play"],
		"music: deferred announce reaches ready-time hosts")
	entry.sync_music()
	_expect_true(_fired["music"] == [&"play", &"play"],
		"music: sync announces play for late hosts")
	entry.show_identity({"stable_id": TEST_ID}, {"has_save": true})
	await _frames(2)
	_press(entry, "Content/StatusCard/Ready/StartRow/Start")
	_expect_true(_fired["music"] == [&"play", &"play", &"stop"],
		"music: leaving for a run announces stop")
	_expect_true(entry.get_music_intent() == &"stop",
		"music: intent query matches")
	entry.queue_free()
	await _frames(2)


func _test_button_faces() -> void:
	for kind in ["normal", "primary", "danger", "portal"]:
		var button: Button = GateEntryStyle.make_button("TEST face", kind)
		add_child(button)
		await _frames(1)
		var wanted_accent: int = GateFrameStyle.Accent.STEEL
		if kind == "primary":
			wanted_accent = GateFrameStyle.Accent.GOLD
		elif kind == "danger":
			wanted_accent = GateFrameStyle.Accent.CORAL
		elif kind == "portal":
			wanted_accent = GateFrameStyle.Accent.MINT
		for state_name in ["normal", "hover", "pressed", "disabled"]:
			var face: StyleBox = button.get_theme_stylebox(state_name)
			_expect_true(face is GateFrameStyle,
				"faces: %s %s is authored, not flat" % [kind, state_name])
			_expect_true(not (face is StyleBoxFlat),
				"faces: %s %s is no flat box" % [kind, state_name])
			if face is GateFrameStyle:
				_expect_true((face as GateFrameStyle).accent() == wanted_accent,
					"faces: %s %s wears its accent" % [kind, state_name])
		var focus: StyleBox = button.get_theme_stylebox("focus")
		_expect_true(focus is GateFrameStyle \
			and (focus as GateFrameStyle).kind() == GateFrameStyle.Kind.FOCUS,
			"faces: %s focus is the authored ring" % kind)
		button.queue_free()
	var card := PanelContainer.new()
	GateEntryStyle.apply_card(card)
	_expect_true(card.get_theme_stylebox("panel") is GateFrameStyle,
		"faces: dialog card is authored")
	var field := LineEdit.new()
	GateEntryStyle.apply_id_field(field)
	_expect_true(field.get_theme_stylebox("normal") is GateFrameStyle,
		"faces: id field is authored")
	var bar := ProgressBar.new()
	GateEntryStyle.apply_progress(bar)
	_expect_true(bar.get_theme_stylebox("background") is GateFrameStyle \
		and bar.get_theme_stylebox("fill") is GateFrameStyle,
		"faces: progress track and fill are authored")
	_expect_true(GateEntryStyle.hall_row_style(0) is GateFrameStyle \
		and GateEntryStyle.hall_row_style(1) is GateFrameStyle,
		"faces: hall rows are authored")
	# Every cached face must survive a real draw call without errors.
	var probe := Control.new()
	add_child(probe)
	await _frames(1)
	var faces: Array[StyleBox] = [
		card.get_theme_stylebox("panel"),
		field.get_theme_stylebox("normal"),
		bar.get_theme_stylebox("background"),
		bar.get_theme_stylebox("fill"),
		GateEntryStyle.hall_row_style(3),
	]
	var reskinned: Button = GateEntryStyle.make_button("TEST reskin")
	add_child(reskinned)
	GateEntryStyle.apply_kind(reskinned, "primary")
	faces.append(reskinned.get_theme_stylebox("normal"))
	_expect_true(
		(reskinned.get_theme_stylebox("normal") as GateFrameStyle).accent() \
			== GateFrameStyle.Accent.GOLD,
		"faces: re-skin swaps the accent live")
	for face in faces:
		face.draw(probe.get_canvas_item(), Rect2(0, 0, 120, 44))
		_checked += 1
		# Bevel, etch and keyline guards must survive degenerate rects.
		face.draw(probe.get_canvas_item(), Rect2(0, 0, 4, 4))
		face.draw(probe.get_canvas_item(), Rect2(0, 0, 0, 0))
		_checked += 2
	probe.queue_free()
	reskinned.queue_free()
	card.free()
	field.free()
	bar.free()
	await _frames(1)


func _test_forecourt_identity() -> void:
	var entry: GateEntry = _make_entry()
	await _frames(3)
	var forecourt: GateHeroForecourt = entry.get_forecourt()
	_expect_true(forecourt.actor_count() == 6,
		"forecourt: all six heroes stand in the lineup")
	var seen: Dictionary = {}
	for index in forecourt.actor_count():
		var info: Dictionary = forecourt.actor_info(index)
		var hero: Hero = load(str(info["hero_path"])) as Hero
		_expect_true(hero != null \
			and str(info["hero_path"]) in FORECOURT_HEROES,
			"forecourt: actor %d is a real game hero" % index)
		seen[str(info["hero_path"])] = true
		var sheet: Texture2D = WeaponRig.painted_sheet(
			hero.attack_profile) as Texture2D
		_expect_true(str(info["weapon_path"]) == sheet.resource_path \
			and str(info["weapon_path"]).ends_with(".png"),
			"forecourt: actor %d holds its real painted weapon" % index)
		_expect_true(int(info["frame_count"]) == maxi(hero.idle_frames, 1) \
			and int(info["frame_count"]) == 4,
			"forecourt: actor %d animates all four idle frames" % index)
		_expect_true(int(info["facing"]) == 0 or int(info["facing"]) == 2,
			"forecourt: actor %d faces the viewer or the gate" % index)
		var body: Sprite2D = forecourt.get_node(
			"HeroActor%d/Body" % index) as Sprite2D
		var atlas: AtlasTexture = body.texture as AtlasTexture
		_expect_true(atlas != null and atlas.atlas == hero.idle_sheet,
			"forecourt: actor %d frames its own idle sheet" % index)
		if atlas != null:
			_expect_true(atlas.region.size == Vector2(hero.sprite_cell),
				"forecourt: actor %d keeps the 144x192 cell" % index)
			var sheet_rect := Rect2(Vector2.ZERO, hero.idle_sheet.get_size())
			_expect_true(sheet_rect.encloses(atlas.region),
				"forecourt: actor %d region sits inside the sheet" % index)
		var weapon: Sprite2D = forecourt.get_node(
			"HeroActor%d/Weapon" % index) as Sprite2D
		_expect_true(weapon.texture == sheet,
			"forecourt: actor %d weapon sprite is the rig sheet" % index)
	_expect_true(seen.size() == 6, "forecourt: no hero repeats")
	entry.queue_free()
	await _frames(2)


## The hardcoded paint bounds match the committed sheets, re-measured
## here from the source files: union opaque bounds (alpha >= 32) across
## the four idle frames of the down and left columns.
func _test_paint_bounds() -> void:
	for hero_id in ["warden", "dancer", "keeper", "knight", "eclipse", "sage"]:
		var image: Image = Image.load_from_file(
			"res://assets/custom/actors/heroes/%s/idle.png" % hero_id)
		_expect_true(image != null and image.get_size() == Vector2i(576, 768),
			"paint: %s sheet loads at 576x768" % hero_id)
		if image == null:
			continue
		for facing in [0, 2]:
			var measured: Rect2i = _measure_column(image, facing)
			var table: Dictionary = GateHeroForecourt.PAINT_LEFT \
				if facing == 2 else GateHeroForecourt.PAINT_DOWN
			_expect_true(table[hero_id] == measured,
				"paint: %s column %d is %s" % [hero_id, facing, measured])


func _measure_column(image: Image, column: int) -> Rect2i:
	var lo := Vector2i(144, 192)
	var hi := Vector2i(-1, -1)
	for frame in 4:
		var origin := Vector2i(column * 144, frame * 192)
		for y in 192:
			for x in 144:
				if image.get_pixel(origin.x + x, origin.y + y).a \
						>= 32.0 / 255.0:
					lo.x = mini(lo.x, x)
					lo.y = mini(lo.y, y)
					hi.x = maxi(hi.x, x)
					hi.y = maxi(hi.y, y)
	return Rect2i(lo, hi - lo + Vector2i(1, 1))


func _test_forecourt_transparency() -> void:
	var entry: GateEntry = _make_entry()
	await _frames(3)
	var forecourt: GateHeroForecourt = entry.get_forecourt()
	_expect_true(forecourt.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"forecourt: the layer never takes input")
	var stack: Array[Node] = [forecourt]
	var interactive: int = 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			var control: Control = node as Control
			if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				interactive += 1
		if node is Button or node is LineEdit or node is ScrollContainer:
			interactive += 1
		stack.append_array(node.get_children())
	_expect_true(interactive == 0,
		"forecourt: no actor or descendant intercepts taps")
	entry.queue_free()
	await _frames(2)


func _test_forecourt_motion() -> void:
	var entry: GateEntry = _make_entry()
	await _frames(3)
	var forecourt: GateHeroForecourt = entry.get_forecourt()
	_expect_true(forecourt.is_motion_active(),
		"forecourt: idle clocks run by default")
	# Actor 5 still dwells at 0.8s (its opening stop runs 2.3s); actor 0
	# steps off at exactly 0.8s, so its second sample would read the walk
	# sheet's opening stride row instead of the idle breath.
	var first: int = int(forecourt.actor_info(5)["frame"])
	# Wall time, not frames: headless frames run faster than real time and
	# the idle clocks integrate delta, so only elapsed seconds move them.
	await get_tree().create_timer(0.8).timeout
	var later: int = int(forecourt.actor_info(5)["frame"])
	_expect_true(first != later, "forecourt: idle frames advance")
	entry.set_reduced_motion(true)
	await _frames(2)
	_expect_true(not forecourt.is_motion_active(),
		"forecourt: reduced motion stops the idle clocks")
	_expect_true(not entry.is_motion_active(),
		"forecourt: the entry reports the frozen lineup")
	var frozen: int = int(forecourt.actor_info(0)["frame"])
	var frozen_feet: Vector2 = forecourt.actor_info(0)["feet"]
	var frozen_body: Vector2 = (forecourt.get_node("HeroActor0/Body") \
		as Sprite2D).position
	await _frames(MOTION_FRAMES)
	_expect_true(int(forecourt.actor_info(0)["frame"]) == frozen,
		"forecourt: frames hold still with reduced motion")
	_expect_true(forecourt.actor_info(0)["feet"] == frozen_feet,
		"forecourt: feet hold still with reduced motion")
	_expect_true((forecourt.get_node("HeroActor0/Body") as Sprite2D) \
		.position == frozen_body,
		"forecourt: bob holds still with reduced motion")
	_expect_true(forecourt.actor_count() == 6 \
		and (forecourt.get_node("HeroActor5") as Node2D).modulate.a >= 0.99,
		"forecourt: the frozen lineup stays complete")
	entry.set_reduced_motion(false)
	await _frames(2)
	_expect_true(forecourt.is_motion_active(),
		"forecourt: the clocks resume when re-enabled")
	entry.queue_free()
	await _frames(2)


func _test_production_launcher() -> void:
	# The shipped production scene pins the launcher hidden by default.
	var found: bool = false
	var pinned: bool = false
	var script_first: bool = false
	var state: SceneState = PRODUCTION_SCENE.get_state()
	for node_index in state.get_node_count():
		if str(state.get_node_name(node_index)) != "TestLauncher":
			continue
		found = true
		var script_at: int = -1
		var pin_at: int = -1
		for prop_index in state.get_node_property_count(node_index):
			var prop_name: String = str(state.get_node_property_name(
				node_index, prop_index))
			if prop_name == "script":
				script_at = prop_index
			elif prop_name == "show_developer_controls":
				pin_at = prop_index
				pinned = bool(state.get_node_property_value(
					node_index, prop_index)) == false
		script_first = script_at >= 0 and pin_at >= 0 \
			and script_at < pin_at
	_expect_true(found, "launcher: production entry carries the launcher")
	_expect_true(pinned,
		"launcher: production entry hides developer controls by default")
	_expect_true(script_first,
		"launcher: the pin serializes after the script assignment")
	# The SceneState pin is not the proof: a custom property stored
	# before its script never lands on the real node. Boot the actual
	# packed scene untouched and read the live launcher instead.
	_expect_true(not get_tree().root.has_meta(
		TestLauncher.DEV_LAUNCHER_META),
		"launcher: no debug opt-in leaks into the production boot")
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubProductionHost.new()
	add_child(stub)
	production.set_host_override(stub)
	add_child(production)
	await _frames(3)
	var live: TestLauncher = production.get_node(
		"Ui/TestLauncher") as TestLauncher
	_expect_true(live != null,
		"launcher: the booted production scene carries the launcher")
	if live != null:
		_expect_true(live.show_developer_controls == false,
			"launcher: the booted pin lands on the live node")
		_expect_true(not live.visible,
			"launcher: the booted launcher stays hidden")
		_expect_true(live.get_child_count() == 0,
			"launcher: the booted launcher builds no buttons")
		_expect_true(not live.are_developer_controls_visible(),
			"launcher: the booted launcher reports no developer controls")
		_expect_true(live.is_processing(),
			"launcher: the booted launcher keeps its hooks")
	production.queue_free()
	stub.queue_free()
	await _frames(2)
	# Hidden keeps its hooks: processing stays on, no buttons exist.
	var hidden := TestLauncher.new()
	hidden.show_developer_controls = false
	add_child(hidden)
	await _frames(3)
	_expect_true(not hidden.visible,
		"launcher: hidden on a normal first boot")
	_expect_true(hidden.get_child_count() == 0,
		"launcher: hidden builds no buttons")
	_expect_true(not hidden.are_developer_controls_visible(),
		"launcher: hidden reports no developer controls")
	_expect_true(hidden.is_processing(),
		"launcher: hidden keeps polling its automation hooks")
	hidden.queue_free()
	# The legacy default still shows, and the meta re-enables a hide.
	var legacy := TestLauncher.new()
	_expect_true(legacy.show_developer_controls,
		"launcher: legacy default keeps its buttons")
	add_child(legacy)
	await _frames(2)
	_expect_true(legacy.are_developer_controls_visible(),
		"launcher: legacy shows its buttons")
	legacy.queue_free()
	get_tree().root.set_meta(TestLauncher.DEV_LAUNCHER_META, true)
	var opted := TestLauncher.new()
	opted.show_developer_controls = false
	add_child(opted)
	await _frames(2)
	_expect_true(opted.are_developer_controls_visible(),
		"launcher: the root meta re-enables hidden buttons")
	opted.queue_free()
	get_tree().root.remove_meta(TestLauncher.DEV_LAUNCHER_META)
	await _frames(2)


## Production first paint is the original title at rest: tap prompt
## and small doors showing, gate card parked, lineup flanking clear of
## the prompt glyphs and the doors. A tap opens the selection over the
## same title; back returns to it. No legacy direct arena entry.
func _test_production_title_first() -> void:
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubProductionHost.new()
	add_child(stub)
	production.set_host_override(stub)
	add_child(production)
	await _frames(3)
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	_expect_true(bool(title.is_external_start()),
		"first: production parks the title in external mode")
	_expect_true((title.get_node("Ui/Screen") as Control).visible,
		"first: title screen shows")
	_expect_true((title.get_node("Ui/Screen/TapPrompt") as Control
		).is_visible_in_tree(), "first: tap prompt shows")
	_expect_true(not (gate.get_node("Content/StatusCard") as Control
		).visible, "first: no auth card on first paint")
	_expect_true(not gate.is_selection_open(),
		"first: no selection on first paint")
	_expect_true(not (gate.get_node("ArtLayer/Art") as CanvasItem).visible,
		"first: gate backdrop hidden for the title diorama")
	_expect_true(gate.get_forecourt().actor_count() == 6,
		"first: six heroes over the title")
	_expect_true(not (title.get_node("Ui/Screen/JourneyPanel") as Control
		).visible, "first: no title journey panel under the host")
	var title_launcher: TestLauncher = title.get_node(
		"Ui/Screen/TestLauncher") as TestLauncher
	_expect_true(title_launcher.show_developer_controls == false,
		"first: title launcher controls off in production")
	_expect_true(not title_launcher.are_developer_controls_visible(),
		"first: no title developer controls on screen")
	_expect_true(not (title.get_node("Bgm") as AudioStreamPlayer).playing,
		"first: title stays silent, the host owns music")
	# Layering mechanism: the title UI sits on the default layer below
	# the later gate sibling, so the card always draws above the title.
	_expect_true((title.get_node("Ui") as CanvasLayer).layer == 0,
		"first: title UI on the default layer")
	_expect_true(gate.get_canvas_layer_node() == null,
		"first: gate draws on the default canvas")
	_expect_true(title.get_index() < gate.get_index(),
		"first: gate sibling above the title")
	await get_tree().create_timer(1.5).timeout
	_check_title_clearance(production, "first")
	# Tap: the selection opens over the same title, honestly
	# unconfigured behind this stub, with no arena preload.
	title.request_start()
	await _frames(3)
	_expect_true(gate.is_selection_open(),
		"first: tap opens the selection")
	_expect_true((title.get_node("Ui/Screen/PromptBlink"
		) as AnimationPlayer).is_playing(),
		"first: prompt blink keeps running for the return")
	_expect_true((gate.get_node("Content/StatusCard/LoggedOut/Guest"
		) as Button).visible, "first: guest usable unconfigured")
	_expect_true((gate.get_node("Content/StatusCard/LoggedOut/Unconfigured"
		) as Label).visible, "first: honest unconfigured note")
	_expect_true(not (title.get_node("Ui/Screen") as Control).visible,
		"first: tap parks the title chrome under the card")
	# Production-default empty shape: Guest plus the ordinary pair,
	# providers honestly disabled, nothing synthesized (Brief 107).
	var doors: VBoxContainer = gate.get_node(
		"Content/StatusCard/LoggedOut/Providers") as VBoxContainer
	_expect_true(doors.get_child_count() == 2,
		"first: ordinary pair shown with no providers listed")
	_expect_true((doors.get_child(0) as Button).name == "ProviderGoogle" \
		and (doors.get_child(1) as Button).name == "ProviderApple",
		"first: google then apple order kept")
	_expect_true((doors.get_child(0) as Button).disabled \
		and (doors.get_child(1) as Button).disabled,
		"first: unlisted providers honestly disabled")
	_expect_true(GateProviderButtons.title_node(
		doors.get_child(0) as Button).text == "gate.auth.signin.google" \
		and GateProviderButtons.title_node(
		doors.get_child(1) as Button).text == "gate.auth.signin.apple",
		"first: placeholders read the official action keys")
	_expect_true(not (gate.get_node("Content/StatusCard/LoggedOut/Guest"
		) as Button).disabled, "first: guest stays enabled")
	var arena_status: ResourceLoader.ThreadLoadStatus = \
		ResourceLoader.load_threaded_get_status(
			"res://scenes/gameplay/arena.tscn")
	_expect_true(arena_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"first: tap issues no legacy arena load")
	(gate.get_node("Content/StatusCard/LoggedOut/Consent"
		) as RichTextLabel).meta_clicked.emit("tos")
	await _frames(2)
	_expect_true((gate.get_node("GateTermsPanel") as Control).visible,
		"first: terms sheet opens over the selection")
	(gate.get_node("GateTermsPanel/Card/Stack/Row/Close"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true(gate.is_selection_open(),
		"first: terms close returns to the same selection")
	production._on_back()
	await _frames(2)
	_expect_true(not gate.is_selection_open(),
		"first: back closes the selection")
	_expect_true(not (gate.get_node("Content/StatusCard") as Control
		).visible, "first: back parks the card")
	_expect_true(bool(title.get("_accepting")),
		"first: back re-arms the tap")
	_expect_true((title.get_node("Ui/Screen") as Control).visible,
		"first: back restores the title chrome")
	# The exit question parks the chrome too; staying restores it.
	production._on_back()
	await _frames(2)
	_expect_true((gate.get_node("GateExitPanel") as Control).visible,
		"first: back at rest asks to exit")
	_expect_true(not (title.get_node("Ui/Screen") as Control).visible,
		"first: exit parks the title chrome")
	(gate.get_node("GateExitPanel/Card/Stack/Choices/Stay"
		) as Button).pressed.emit()
	await _frames(2)
	_expect_true(not (gate.get_node("GateExitPanel") as Control).visible,
		"first: staying shuts the exit question")
	_expect_true((title.get_node("Ui/Screen") as Control).visible,
		"first: staying restores the title chrome")
	# Parked stays parked: async host settle never pops the card open.
	stub.production_changed.emit({"public_id": "TEST-PARKED-ID"})
	await _frames(2)
	_expect_true(not gate.is_selection_open(),
		"first: host settle never pops the parked card")
	_expect_true(not (gate.get_node("Content/StatusCard") as Control
		).visible, "first: card stays parked on host settle")
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## Clipped entry notes paint their real glyphs: the provider note and
## the error detail keep a true wrapped line block (never the 1px
## collapse), capped at the 3-line budget, inside the centered card on
## every locale and framing. Clearing and re-showing shrink and grow
## honestly, with no stale gaps and no shortened text.
func _test_note_glyphs() -> void:
	var original_locale: String = TranslationServer.get_locale()
	var original_size: Vector2i = get_tree().root.size
	for framing in NOTE_FRAMINGS:
		for locale in NOTE_LOCALES:
			TranslationServer.set_locale(locale)
			get_tree().root.size = framing
			await _check_note_combo(framing, locale)
	TranslationServer.set_locale(original_locale)
	get_tree().root.size = original_size


func _check_note_combo(framing: Vector2i, locale: String) -> void:
	var tag: String = "note/%s/%dx%d" % [locale, framing.x, framing.y]
	var entry: GateEntry = _make_entry()
	await _frames(3)
	entry.set_providers([])
	entry.show_logged_out()
	await _frames(2)
	var note: Label = entry.get_node(
		"Content/StatusCard/LoggedOut/ProviderNote") as Label
	_expect_true(note.text.contains("Google") \
		and note.text.contains("Apple"),
		tag + ": empty note names both placeholders")
	_check_note_label(entry, tag + "/empty",
		"Content/StatusCard/LoggedOut/ProviderNote", true)
	_check_note_card(entry, tag + "/empty")
	_check_compact_shape(entry, tag + "/empty", false)
	_check_consent_glyphs(entry, tag + "/empty")
	_check_apple_clearspace(entry, tag + "/empty")
	entry.set_providers(NOTE_PROVIDERS_UNREADY)
	await _frames(2)
	_expect_true(note.text.contains("Apple") \
		and note.text.contains("Passkey") \
		and not note.text.contains("Google"),
		tag + ": unready note names only the down doors")
	_check_note_label(entry, tag + "/unready",
		"Content/StatusCard/LoggedOut/ProviderNote", true)
	_check_note_card(entry, tag + "/unready")
	# The one-line donor consent fits where the two-line paraphrase
	# did not: unready keeps its hint in every framing and locale.
	_check_compact_shape(entry, tag + "/unready", false)
	_check_consent_glyphs(entry, tag + "/unready")
	_check_apple_clearspace(entry, tag + "/unready")
	entry.set_providers(NOTE_PROVIDERS_READY)
	await _frames(2)
	_check_note_label(entry, tag + "/ready",
		"Content/StatusCard/LoggedOut/ProviderNote", false)
	_check_note_card(entry, tag + "/ready")
	_check_compact_shape(entry, tag + "/ready", false)
	_check_consent_glyphs(entry, tag + "/ready")
	_check_apple_clearspace(entry, tag + "/ready")
	entry.set_providers(NOTE_PROVIDERS_ALL_DRAINING)
	await _frames(2)
	_expect_true(note.text.contains("Google") \
		and note.text.contains("Apple") \
		and note.text.contains("Passkey"),
		tag + ": draining note names every draining door")
	_check_note_label(entry, tag + "/draining",
		"Content/StatusCard/LoggedOut/ProviderNote", true)
	_check_note_card(entry, tag + "/draining")
	_check_compact_shape(entry, tag + "/draining", framing.y <= 360)
	_check_consent_glyphs(entry, tag + "/draining")
	_check_apple_clearspace(entry, tag + "/draining")
	entry.set_providers(NOTE_PROVIDERS_ALL_UNREADY)
	await _frames(2)
	_expect_true(note.text.contains("Google") \
		and note.text.contains("Apple") \
		and note.text.contains("Passkey"),
		tag + ": all-down note names every down door")
	_check_note_label(entry, tag + "/alldown",
		"Content/StatusCard/LoggedOut/ProviderNote", true)
	_check_note_card(entry, tag + "/alldown")
	_check_compact_shape(entry, tag + "/alldown", framing.y <= 360)
	_check_consent_glyphs(entry, tag + "/alldown")
	_check_apple_clearspace(entry, tag + "/alldown")
	entry.show_busy("google", "Google")
	entry.show_error(NOTE_SHORT_DETAIL)
	await _frames(2)
	var detail: Label = entry.get_node(
		"Content/StatusCard/Error/ErrorDetail") as Label
	_expect_true(detail.text == NOTE_SHORT_DETAIL,
		tag + ": short detail kept whole")
	_check_note_label(entry, tag + "/err-short",
		"Content/StatusCard/Error/ErrorDetail", true)
	_check_note_card(entry, tag + "/err-short")
	var short_height: float = _note_card_height(entry)
	entry.show_error(NOTE_LONG_DETAIL)
	await _frames(2)
	_expect_true(detail.text == NOTE_LONG_DETAIL,
		tag + ": long detail kept whole")
	_check_note_capped(entry, tag + "/err-long",
		"Content/StatusCard/Error/ErrorDetail")
	_check_note_card(entry, tag + "/err-long")
	var long_height: float = _note_card_height(entry)
	_expect_true(long_height > short_height,
		tag + ": long detail grows the card")
	entry.show_error("")
	await _frames(2)
	_check_note_label(entry, tag + "/err-clear",
		"Content/StatusCard/Error/ErrorDetail", false)
	_check_note_card(entry, tag + "/err-clear")
	_expect_true(_note_card_height(entry) < long_height,
		tag + ": clearing shrinks the card")
	_check_error_compact(entry, tag + "/err-clear")
	entry.show_error(NOTE_SHORT_DETAIL)
	await _frames(2)
	_check_note_label(entry, tag + "/err-again",
		"Content/StatusCard/Error/ErrorDetail", true)
	_check_note_card(entry, tag + "/err-again")
	_expect_true(absf(_note_card_height(entry) - short_height) <= 0.5,
		tag + ": re-showing restores the short height")
	entry.queue_free()
	await _frames(2)


## One clipped note: config locked, rect fits its live shaped lines, all
## lines visible, inside the card and clear of its siblings.
func _check_note_label(entry: GateEntry, tag: String, path: String,
		expect_visible: bool) -> void:
	var label: Label = entry.get_node(path) as Label
	_expect_true(label.max_lines_visible == 3,
		tag + ": %s keeps the 3-line budget" % label.name)
	_expect_true(label.clip_text,
		tag + ": %s stays clipped" % label.name)
	_expect_true(label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
		tag + ": %s keeps word wrap" % label.name)
	_expect_true(label.visible == expect_visible,
		tag + ": %s visibility reads %s" % [label.name, expect_visible])
	if not expect_visible:
		return
	var need: float = _note_need(label)
	_expect_true(absf(label.get_global_rect().size.y - need) <= 0.5,
		tag + ": %s rect %s fits its lines" % [label.name,
			label.get_global_rect().size])
	_expect_true(label.get_visible_line_count() == label.get_line_count(),
		tag + ": %s shows every shaped line" % label.name)
	_check_note_inside(entry, label, tag)
	_check_note_siblings(label, tag)


## An over-budget detail: full text kept, rect pinned at the 3-line
## budget, three lines painted.
func _check_note_capped(entry: GateEntry, tag: String, path: String) -> void:
	var label: Label = entry.get_node(path) as Label
	_expect_true(label.visible, tag + ": %s shows" % label.name)
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var ink: float = font.get_string_size(label.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, float(font_size)).x
	_expect_true(ink > 3.0 * label.custom_minimum_size.x,
		tag + ": fixture truly exceeds three lines")
	var need: float = _note_need(label)
	_expect_true(absf(label.get_global_rect().size.y - need) <= 0.5,
		tag + ": %s rect holds the budget" % label.name)
	_expect_true(label.get_visible_line_count() == 3,
		tag + ": %s paints three lines" % label.name)
	_check_note_inside(entry, label, tag)
	_check_note_siblings(label, tag)


## Rendered block height for a label's live shaped lines, capped at its
## own max-lines budget: one font line per line plus the theme spacing
## between them.
func _note_need(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var line: float = float(font.get_height(font_size))
	var spacing: float = float(label.get_theme_constant("line_spacing"))
	var lines: int = maxi(label.get_line_count(), 1)
	if label.max_lines_visible > 0:
		lines = mini(lines, label.max_lines_visible)
	return float(lines) * line + float(lines - 1) * spacing


func _check_note_inside(entry: GateEntry, label: Control, tag: String) -> void:
	var card: PanelContainer = entry.get_node(
		"Content/StatusCard") as PanelContainer
	_expect_true(card.get_global_rect().grow(-1.0).encloses(
		label.get_global_rect().grow(-0.5)),
		tag + ": %s inside its card" % label.name)


func _check_note_siblings(label: Control, tag: String) -> void:
	var leaves: Array[Control] = []
	_collect_note_leaves(label.get_parent(), leaves)
	for leaf in leaves:
		if leaf == label:
			continue
		_expect_true(not label.get_global_rect().grow(-1.0).intersects(
			leaf.get_global_rect().grow(-1.0)),
			tag + ": %s clears %s" % [label.name, leaf.name])


## After clearing, the error row sits directly under the title: no stale
## gap where the detail was, and the hold keeps its doors.
func _check_error_compact(entry: GateEntry, tag: String) -> void:
	var title: Label = entry.get_node(
		"Content/StatusCard/Error/ErrorTitle") as Label
	var row: Control = entry.get_node(
		"Content/StatusCard/Error/ErrorRow") as Control
	var gap: float = row.position.y - (title.position.y + title.size.y)
	_expect_true(absf(gap - 6.0) <= 0.5,
		tag + ": error row closes the cleared gap")
	_expect_true((entry.get_node("Content/StatusCard/Error") as Control) \
		.visible, tag + ": error hold persists")
	_expect_true((entry.get_node(
		"Content/StatusCard/Error/ErrorRow/ErrorGuest") as Button).visible,
		tag + ": guest escape stays after clearing")


## The card keeps its fixed width, stays centered with its whole rim
## inside the viewport, and holds every visible leaf (titles, notes,
## buttons, footer links) inside itself.
func _check_note_card(entry: GateEntry, tag: String) -> void:
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	var card: PanelContainer = entry.get_node(
		"Content/StatusCard") as PanelContainer
	var rect: Rect2 = card.get_global_rect()
	_expect_true(absf(rect.size.x - GateEntry.CARD_WIDTH) <= 0.5,
		tag + ": card keeps its width")
	_expect_true(absf(viewport.get_center().x - rect.get_center().x) <= 1.0 \
		and absf(viewport.get_center().y - rect.get_center().y) <= 1.0,
		tag + ": card centered")
	_expect_true(viewport.encloses(rect.grow(-0.5)),
		tag + ": whole card rim inside the viewport %s" % rect)
	for box_name in ["LoggedOut", "Busy", "Ready", "Error"]:
		var box: Control = entry.get_node(
			"Content/StatusCard/%s" % box_name) as Control
		if not box.visible:
			continue
		var leaves: Array[Control] = []
		_collect_note_leaves(box, leaves)
		for leaf in leaves:
			_expect_true(rect.grow(-1.0).encloses(
				leaf.get_global_rect().grow(-0.5)),
				tag + ": %s inside its card" % leaf.name)
	var buttons: Array = []
	_collect_note_buttons(entry, buttons)
	for raw in buttons:
		var button: Button = raw as Button
		if not button.is_visible_in_tree():
			continue
		var brect: Rect2 = button.get_global_rect()
		_expect_true(viewport.encloses(brect.grow(-0.5)),
			tag + ": %s inside" % button.name)
		_expect_true(rect.grow(-1.0).encloses(brect.grow(-0.5)),
			tag + ": %s inside its card" % button.name)
	for index in buttons.size():
		var first: Button = buttons[index] as Button
		if not first.is_visible_in_tree():
			continue
		for other in range(index + 1, buttons.size()):
			var second: Button = buttons[other] as Button
			if not second.is_visible_in_tree():
				continue
			_expect_true(not first.get_global_rect().grow(-1.0) \
				.intersects(second.get_global_rect().grow(-1.0)),
				tag + ": %s and %s do not overlap" % [
					first.name, second.name])


func _note_card_height(entry: GateEntry) -> float:
	return (entry.get_node("Content/StatusCard") as PanelContainer).size.y


func _collect_note_leaves(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		var control: Control = child as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if child is Container:
			_collect_note_leaves(child, out)
		else:
			out.append(control)


func _collect_note_buttons(node: Node, out: Array) -> void:
	if node.get_class() == "Button":
		out.append(node)
	for child in node.get_children():
		_collect_note_buttons(child, out)


## Compact sheds only where necessary: the hint hides exactly on the
## shapes whose honest want exceeds the viewport, while consent stays
## visible, guest and extras keep at least 40px, and the official pair
## keeps 44px in every shape here.
func _check_compact_shape(entry: GateEntry, tag: String,
		expect_hint_hidden: bool) -> void:
	var hint: Label = entry.get_node(
		"Content/StatusCard/LoggedOut/Hint") as Label
	_expect_true(hint.visible == (not expect_hint_hidden),
		tag + ": hint compact reads %s" % expect_hint_hidden)
	_expect_true((entry.get_node(
		"Content/StatusCard/LoggedOut/Consent") as RichTextLabel).visible,
		tag + ": consent survives compact")
	_expect_true((entry.get_node(
		"Content/StatusCard/LoggedOut/Guest") as Button) \
		.custom_minimum_size.y >= 40.0,
		tag + ": guest keeps its touch floor")
	var row: VBoxContainer = entry.get_node(
		"Content/StatusCard/LoggedOut/Providers") as VBoxContainer
	for child in row.get_children():
		var door: Button = child as Button
		if door.name == "ProviderGoogle" \
				or door.name == "ProviderApple":
			_expect_true(door.custom_minimum_size.y == 44.0,
				tag + ": %s keeps 44px" % door.name)
		else:
			_expect_true(door.custom_minimum_size.y >= 40.0,
				tag + ": %s keeps its touch floor" % door.name)


## The consent sentence paints fully: visible, both inline links
## present and styled, a line of glyphs in its rect, the rect inside
## the card, clearing siblings, and clickable.
func _check_consent_glyphs(entry: GateEntry, tag: String) -> void:
	var consent: RichTextLabel = entry.get_node(
		"Content/StatusCard/LoggedOut/Consent") as RichTextLabel
	_expect_true(consent.visible, tag + ": consent visible")
	_expect_true(consent.bbcode_enabled, tag + ": consent parses links")
	_expect_true(consent.text.contains("[url=tos]") \
		and consent.text.contains("[url=privacy]"),
		tag + ": consent carries both links")
	_expect_true(consent.text.contains("[u]") \
		and consent.text.contains("[color="),
		tag + ": links read as links")
	_expect_true(consent.mouse_filter == Control.MOUSE_FILTER_STOP,
		tag + ": consent takes link taps")
	var font: Font = consent.get_theme_font("normal_font")
	var line: float = float(font.get_height(
		consent.get_theme_font_size("normal_font_size")))
	_expect_true(consent.get_global_rect().size.y >= line - 0.5,
		tag + ": consent paints a line of glyphs")
	_expect_true(not consent.get_parsed_text().is_empty() \
		and not consent.get_parsed_text().contains("%s") \
		and not consent.get_parsed_text().contains("{comma}"),
		tag + ": consent formats its template")
	_check_note_inside(entry, consent, tag + "/consent")
	_check_note_siblings(consent, tag + "/consent")


## Apple clearspace is at least height/10 on all four sides: the 44px
## door needs 4.4px, pinned here as the integer 5px the layout holds in
## full and compact shapes alike.
func _check_apple_clearspace(entry: GateEntry, tag: String) -> void:
	var card: PanelContainer = entry.get_node(
		"Content/StatusCard") as PanelContainer
	var box: VBoxContainer = entry.get_node(
		"Content/StatusCard/LoggedOut") as VBoxContainer
	var row: VBoxContainer = entry.get_node(
		"Content/StatusCard/LoggedOut/Providers") as VBoxContainer
	var apple: Button = row.get_node("ProviderApple") as Button
	var google: Button = row.get_node("ProviderGoogle") as Button
	var arect: Rect2 = apple.get_global_rect()
	_expect_true(arect.position.y - google.get_global_rect().end.y \
		>= 5.0 - 0.01,
		tag + ": apple clears google by 5px")
	var apple_index: int = apple.get_index()
	if apple_index + 1 < row.get_child_count():
		var below: Control = row.get_child(apple_index + 1) as Control
		_expect_true(below.get_global_rect().position.y - arect.end.y \
			>= 5.0 - 0.01,
			tag + ": apple clears %s by 5px" % below.name)
	else:
		var row_index: int = row.get_index()
		var sibling: Control = box.get_child(row_index + 1) as Control
		while not sibling.visible:
			row_index += 1
			sibling = box.get_child(row_index + 1) as Control
		_expect_true(sibling.get_global_rect().position.y \
			- row.get_global_rect().end.y >= 5.0 - 0.01,
			tag + ": apple clears %s by 5px" % sibling.name)
	var crect: Rect2 = card.get_global_rect()
	_expect_true(arect.position.x - crect.position.x >= 5.0,
		tag + ": apple clears the left rim by 5px")
	_expect_true(crect.end.x - arect.end.x >= 5.0,
		tag + ": apple clears the right rim by 5px")


## One official door: plain Button, brand faces in all five states,
## the left-column mark and the independently centered title with
## vendor type and the official mark at its ratio, equal 44px height,
## and the platform's edge padding. Centering and fit come from live
## rects, never from alignment flags or summed widths.
func _check_official_door(button: Button, provider_id: String,
		tag: String) -> void:
	var where: String = "%s: %s" % [tag, button.name]
	_expect_true(button.get_class() == "Button",
		where + " stays a plain Button")
	# Spec values as literals, never the factory's own constants: moving
	# a constant must fail here.
	var fill: Color = Color(1, 1, 1)
	var border: Color = Color("747775")
	var ink: Color = Color("1f1f1f")
	var ring: Color = Color("1a73e8")
	var edge: int = 12
	var margin_v: int = 11
	var font_size: int = 14
	if OS.get_name() == "iOS":
		edge = 16
	if provider_id == "apple":
		fill = Color(0, 0, 0)
		border = Color(0, 0, 0)
		ink = Color(1, 1, 1)
		ring = Color(1, 1, 1)
		edge = 16
		margin_v = 0
		font_size = 14
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var face: StyleBox = button.get_theme_stylebox(state_name)
		_expect_true(face is StyleBoxFlat,
			"%s %s is a flat brand face" % [where, state_name])
		_expect_true(not (face is GateFrameStyle),
			"%s %s wears no game frame" % [where, state_name])
		var flat := face as StyleBoxFlat
		if state_name == "normal" or state_name == "disabled":
			_expect_true(flat.bg_color == fill,
				"%s %s keeps its brand fill" % [where, state_name])
		else:
			_expect_true(flat.bg_color != fill,
				"%s %s answers the pointer" % [where, state_name])
			_expect_true(absf(flat.bg_color.r - flat.bg_color.g) \
				<= 0.02 \
				and absf(flat.bg_color.g - flat.bg_color.b) <= 0.02,
				"%s %s stays grayscale" % [where, state_name])
		_expect_true(flat.border_color == border,
			"%s %s keeps its brand border" % [where, state_name])
		_expect_true(flat.border_width_left == 1 \
			and flat.border_width_top == 1 \
			and flat.border_width_right == 1 \
			and flat.border_width_bottom == 1,
			"%s %s keeps the 1px stroke" % [where, state_name])
		_expect_true(flat.corner_radius_top_left == 8 \
			and flat.corner_radius_top_right == 8 \
			and flat.corner_radius_bottom_left == 8 \
			and flat.corner_radius_bottom_right == 8,
			"%s %s keeps the modest radius" % [where, state_name])
		_expect_true(flat.content_margin_left == edge \
			and flat.content_margin_right == edge,
			"%s %s keeps the platform edge" % [where, state_name])
		_expect_true(flat.content_margin_top == margin_v \
			and flat.content_margin_bottom == margin_v,
			"%s %s keeps its logo balance" % [where, state_name])
	var focus: StyleBox = button.get_theme_stylebox("focus")
	_expect_true(focus is StyleBoxFlat,
		where + " focus is a flat brand ring")
	_expect_true(not (focus is GateFrameStyle),
		where + " focus wears no game frame")
	var ring_face := focus as StyleBoxFlat
	_expect_true(ring_face.bg_color == fill,
		where + " focus retints nothing")
	_expect_true(ring_face.border_color == ring,
		where + " focus keeps its ring color")
	_expect_true(ring_face.border_width_left == 2 \
		and ring_face.border_width_top == 2 \
		and ring_face.border_width_right == 2 \
		and ring_face.border_width_bottom == 2,
		where + " focus keeps its ring width")
	_expect_true(ring_face.expand_margin_left == 2 \
		and ring_face.expand_margin_top == 2 \
		and ring_face.expand_margin_right == 2 \
		and ring_face.expand_margin_bottom == 2,
		where + " focus ring sits outside the rect")
	_expect_true(button.text.is_empty(),
		where + " draws no native text over its group")
	_expect_true(button.icon == null,
		where + " draws no native icon over its group")
	_expect_true(button.clip_contents,
		where + " clips overflow at its own rect")
	_expect_true(button.custom_minimum_size.y == 44.0,
		where + " keeps 44px prominence")
	var group := GateProviderButtons.content_group(button)
	var logo := GateProviderButtons.logo_node(button)
	var title := GateProviderButtons.title_node(button)
	_expect_true(group != null and logo != null and title != null,
		where + " composes its group, mark, and title")
	if group == null or logo == null or title == null:
		return
	_expect_true(group is Control and not (group is Container),
		where + " anchors its content, never a box")
	_expect_true(title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER \
		and title.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
		where + " centers its title on the door")
	_expect_true(group.mouse_filter == Control.MOUSE_FILTER_IGNORE \
		and logo.mouse_filter == Control.MOUSE_FILTER_IGNORE \
		and title.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		where + " keeps its children mouse-transparent")
	_expect_true(title.text == "gate.auth.signin.%s" % provider_id,
		where + " titles its real action key")
	_expect_true(button.accessibility_labeled_by_nodes.size() == 1,
		where + " binds one action label")
	var labeled: Node = null
	if button.accessibility_labeled_by_nodes.size() == 1:
		labeled = button.get_node_or_null(
			button.accessibility_labeled_by_nodes[0])
	_expect_true(labeled == title,
		where + " labels its action from its visible title")
	_expect_true(tr(title.text) != title.text,
		where + " resolves its action, never a raw key")
	_expect_true(title.get_theme_font_size("font_size") == font_size,
		where + " keeps its brand type size")
	if provider_id == "google":
		var face_font: Font = title.get_theme_font("font")
		_expect_true(face_font is FontVariation,
			where + " sets the variable brand face")
		var variation := face_font as FontVariation
		_expect_true(variation != null and int(
			variation.variation_opentype.get("wght", 0)) == 500,
			where + " sets Medium weight 500")
		_expect_true(variation != null \
			and variation.get_fallbacks().size() >= 1,
			where + " keeps its CJK fallback")
	else:
		_expect_true(title.get_theme_font("font") \
			== GateEntryStyle.body_font(),
			where + " sets the plain bundled reading face")
	_expect_true(title.get_theme_color("font_color") == ink,
		where + " keeps its opaque brand ink")
	_expect_true(not title.clip_text,
		where + " never crushes its title to a sliver")
	_expect_true(title.get_line_count() == 1 \
		and title.get_visible_line_count() == 1,
		where + " shapes its title on one line")
	_expect_true(logo.texture_filter \
		== CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
		where + " minifies its mark clean")
	_expect_true(logo.expand_mode == TextureRect.EXPAND_IGNORE_SIZE \
		and logo.stretch_mode \
			== TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		where + " fits its mark by aspect")
	_expect_true(logo.modulate == Color(1, 1, 1) \
		and logo.self_modulate == Color(1, 1, 1),
		where + " never tints its mark")
	if provider_id == "google":
		_expect_true(logo.texture is AtlasTexture,
			where + " draws the glyph region")
		var crop := logo.texture as AtlasTexture
		var atlas: Texture2D = crop.atlas as Texture2D
		var glyph := Rect2(40, 40, 79, 80)
		if atlas != null and atlas.get_size().x > 160.0:
			glyph = Rect2(48, 48, 79, 80)
		_expect_true(crop.region == glyph,
			where + " draws the intact G alone")
		_expect_true(logo.custom_minimum_size == Vector2(19.75, 20.0),
			where + " fits its G at 20px")
	else:
		var art: Vector2 = (logo.texture as Texture2D).get_size()
		_expect_true(absf(art.x * 44.0 - art.y * 31.0) <= 0.5,
			where + " keeps the padded file ratio")
		_expect_true(logo.custom_minimum_size == Vector2(31.0, 44.0),
			where + " draws its whole file at door height")
	_check_official_group_rects(button, group, logo, title, where, edge)


## The anchored content as the engine laid it out: the mark on the
## 32px left column, the title rect symmetric about the door axis with
## 64px reserves, the glyph line centered on the door within 1px, no
## glyph overlap, and both inside the door rect with platform edges.
## Every quantity is read back from live rects after layout.
func _check_official_group_rects(button: Button, group: Control,
		logo: TextureRect, title: Label, where: String,
		edge: int) -> void:
	var brect: Rect2 = button.get_global_rect()
	var grect: Rect2 = group.get_global_rect()
	var lrect: Rect2 = logo.get_global_rect()
	var trect: Rect2 = title.get_global_rect()
	_expect_true(absf(grect.position.x - brect.position.x) <= 0.5 \
		and absf(grect.position.y - brect.position.y) <= 0.5 \
		and absf(grect.size.x - brect.size.x) <= 0.5 \
		and absf(grect.size.y - brect.size.y) <= 0.5,
		where + " spans its door, so the anchors hold")
	_expect_true(lrect.size.x > 16.0 and trect.size.x > 64.0,
		where + " paints readable mark and title widths")
	_expect_true(absf(lrect.get_center().x - brect.position.x - 32.0) \
		<= 1.0,
		where + " pins its mark on the 32px left column")
	_expect_true(absf(trect.get_center().x - brect.get_center().x) \
		<= 1.0,
		where + " centers its title rect on the door axis")
	_expect_true(absf(trect.position.x - brect.position.x - 64.0) \
		<= 1.0 \
		and absf(brect.end.x - trect.end.x - 64.0) <= 1.0,
		where + " reserves symmetric 64px edges")
	var font: Font = title.get_theme_font("font")
	var ink: float = font.get_string_size(tr(title.text),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, float(
			title.get_theme_font_size("font_size"))).x
	var glyph := Rect2(trect.get_center().x - ink * 0.5,
		trect.position.y, ink, trect.size.y)
	_expect_true(absf(glyph.get_center().x - brect.get_center().x) \
		<= 1.0,
		where + " centers its glyph line on the door axis")
	_expect_true(lrect.end.x <= glyph.position.x,
		where + " never overlaps mark and glyphs")
	_expect_true(glyph.position.x - lrect.end.x >= 8.0 - 0.5,
		where + " clears its mark by 8px")
	_expect_true(brect.grow(0.5).encloses(lrect) \
		and brect.grow(0.5).encloses(trect),
		where + " fits its content in its door rect")
	_expect_true(glyph.position.x >= brect.position.x + float(edge) \
		- 0.5 and glyph.end.x <= brect.end.x - float(edge) + 0.5,
		where + " clears its platform edges")
	_expect_true(lrect.position.x >= brect.position.x + float(edge) \
		- 0.5,
		where + " clears its platform edge")


## The official pair as one voice: same 14px type size, same line metrics
## (one baseline family), one shared text baseline read back from live
## title rects, one shared button axis, one shared left-column mark
## center, and one shared title glyph center. Word lengths differ per
## door, so the compared quantities are the actual mark centers, the
## actual glyph centers, and the actual baselines.
func _check_official_pair(google: Button, apple: Button, tag: String) -> void:
	var gtitle := GateProviderButtons.title_node(google)
	var atitle := GateProviderButtons.title_node(apple)
	_expect_true(gtitle.get_theme_font_size("font_size") == 14 \
		and atitle.get_theme_font_size("font_size") == 14,
		tag + ": the pair shares one 14px type size")
	var gfont: Font = gtitle.get_theme_font("font")
	var afont: Font = atitle.get_theme_font("font")
	_expect_true(gfont.get_height(14) == afont.get_height(14) \
		and gfont.get_ascent(14) == afont.get_ascent(14) \
		and gfont.get_descent(14) == afont.get_descent(14),
		tag + ": the pair shares one baseline family")
	_expect_true(absf(_title_baseline_door_y(google, gtitle) \
		- _title_baseline_door_y(apple, atitle)) <= 1.0,
		tag + ": the pair shares one text baseline")
	var grect: Rect2 = google.get_global_rect()
	var arect: Rect2 = apple.get_global_rect()
	_expect_true(absf(grect.get_center().x - arect.get_center().x) <= 0.5,
		tag + ": the pair shares one button axis")
	var glogo := GateProviderButtons.logo_node(google)
	var alogo := GateProviderButtons.logo_node(apple)
	_expect_true(absf(glogo.get_global_rect().get_center().x \
		- alogo.get_global_rect().get_center().x) <= 1.0,
		tag + ": the pair shares one left-column mark center")
	_expect_true(absf(_title_glyph_center_x(google) \
		- _title_glyph_center_x(apple)) <= 1.0,
		tag + ": the pair shares one title glyph center")


## Live title glyph-line center of one door: the centered single
## line sits on its symmetric title rect's center, read back from the
## laid-out rect.
func _title_glyph_center_x(door: Button) -> float:
	var title := GateProviderButtons.title_node(door)
	return title.get_global_rect().get_center().x


## Live text baseline of one title, measured down from its own door
## top: the line box centers the font line, so the baseline is the
## centered line top plus the font ascent. The doors stack vertically,
## so only the within-door offsets are comparable between rows.
func _title_baseline_door_y(door: Button, title: Label) -> float:
	var trect: Rect2 = title.get_global_rect()
	var font: Font = title.get_theme_font("font")
	var font_size: int = title.get_theme_font_size("font_size")
	var line: float = float(font.get_height(font_size))
	return trect.position.y - door.get_global_rect().position.y \
		+ (trect.size.y - line) * 0.5 \
		+ float(font.get_ascent(font_size))


## Official doors in every locale: brand faces, localized actions with
## Latin brand names, live signals, honestly disabled marks, and extra
## providers untouched in the game's own look.
func _test_official_provider_buttons() -> void:
	var original_locale: String = TranslationServer.get_locale()
	for locale in NOTE_LOCALES:
		TranslationServer.set_locale(locale)
		var tag: String = "official/%s" % locale
		var entry: GateEntry = _make_entry()
		_watch(entry)
		await _frames(3)
		entry.set_providers(NOTE_PROVIDERS_UNREADY)
		entry.show_logged_out()
		await _frames(2)
		var row: VBoxContainer = entry.get_node(
			"Content/StatusCard/LoggedOut/Providers") as VBoxContainer
		_expect_true(row.get_child_count() == 3,
			tag + ": ordinary pair plus the extra door")
		var google: Button = entry.get_node(
			"Content/StatusCard/LoggedOut/Providers/ProviderGoogle"
			) as Button
		var apple: Button = entry.get_node(
			"Content/StatusCard/LoggedOut/Providers/ProviderApple"
			) as Button
		var extra: Button = entry.get_node(
			"Content/StatusCard/LoggedOut/Providers/ProviderPasskey"
			) as Button
		_expect_true(tr(GateProviderButtons.title_node(google).text) \
			.contains("Google") \
			and tr(GateProviderButtons.title_node(apple).text) \
			.contains("Apple"),
			tag + ": actions keep Latin brand names")
		_check_official_door(google, "google", tag)
		_check_official_door(apple, "apple", tag)
		_check_official_pair(google, apple, tag)
		_expect_true(apple.disabled \
			and GateProviderButtons.logo_node(apple).texture != null,
			tag + ": disabled apple keeps its mark")
		_expect_true((extra.get_theme_stylebox("normal") \
			as GateFrameStyle).accent() \
			== GateFrameStyle.Accent.MINT,
			tag + ": extra door keeps the portal accent")
		_expect_true(extra.text == "Passkey",
			tag + ": extra door keeps its host label")
		google.pressed.emit()
		_expect_true(_fired["provider"] == ["google"],
			tag + ": google tap requests the real login")
		entry.set_providers(NOTE_PROVIDERS_READY)
		await _frames(2)
		# New provider list, new door instances: re-fetch after rebuild.
		google = entry.get_node(
			"Content/StatusCard/LoggedOut/Providers/ProviderGoogle"
			) as Button
		apple = entry.get_node(
			"Content/StatusCard/LoggedOut/Providers/ProviderApple"
			) as Button
		apple.pressed.emit()
		_expect_true(_fired["provider"] == ["google", "apple"],
			tag + ": apple tap requests the real login")
		_check_official_door(google, "google", tag + "/capable")
		_check_official_door(apple, "apple", tag + "/capable")
		_check_official_pair(google, apple, tag + "/capable")
		entry.queue_free()
		await _frames(2)
	TranslationServer.set_locale(original_locale)


## The accessible action follows the visible title across a live locale
## switch: the binding is a live node path, not a translated snapshot,
## so the same door resolves the right text in every locale.
func _test_official_accessible_action_follows_locale() -> void:
	var original_locale: String = TranslationServer.get_locale()
	var entry: GateEntry = _make_entry()
	await _frames(3)
	entry.set_providers(NOTE_PROVIDERS_UNREADY)
	entry.show_logged_out()
	await _frames(2)
	var google: Button = entry.get_node(
		"Content/StatusCard/LoggedOut/Providers/ProviderGoogle"
		) as Button
	var title := GateProviderButtons.title_node(google)
	var seen: Dictionary = {}
	for locale in NOTE_LOCALES:
		TranslationServer.set_locale(locale)
		await _frames(2)
		var tag: String = "action-label/%s" % locale
		_expect_true(google.accessibility_labeled_by_nodes.size() == 1,
			tag + ": door still binds one action label")
		var bound: Node = null
		if google.accessibility_labeled_by_nodes.size() == 1:
			bound = google.get_node_or_null(
				google.accessibility_labeled_by_nodes[0])
		_expect_true(bound == title,
			tag + ": action still reads the visible title")
		_expect_true(tr(title.text) != title.text,
			tag + ": action resolves, never a raw key")
		seen[locale] = tr(title.text)
	_expect_true(seen["ko"] != seen["en"] \
		and seen["en"] != seen["ja"],
		"action-label: the switch lands real per-locale text")
	entry.queue_free()
	await _frames(2)
	TranslationServer.set_locale(original_locale)


## The inline consent is the donor sentence in every locale: exact
## ko/en/ja template and labels, matching Chinese variants, both links
## routed without starting play, and live locale updates for text and
## the privacy URL.
func _test_consent_links_exact() -> void:
	var original_locale: String = TranslationServer.get_locale()
	var donor: Dictionary = {
		"ko": ["계속하면 %s·%s에 동의한 것으로 간주합니다.",
			"약관", "개인정보 처리방침"],
		"en": ["By continuing, you agree to %s & %s.",
			"Terms", "Privacy Policy"],
		"ja": ["%s・%sに同意して続行。",
			"利用規約", "プライバシーポリシー"],
		"zh_CN": ["继续即表示您同意%s和%s。",
			"条款", "隐私政策"],
		"zh_TW": ["繼續即表示您同意%s和%s。",
			"條款", "隱私權政策"],
	}
	var entry: GateEntry = _make_entry()
	_watch(entry)
	await _frames(3)
	entry.set_providers(NOTE_PROVIDERS_UNREADY)
	entry.show_logged_out()
	await _frames(2)
	var consent: RichTextLabel = entry.get_node(
		"Content/StatusCard/LoggedOut/Consent") as RichTextLabel
	for locale in NOTE_LOCALES:
		TranslationServer.set_locale(locale)
		await _frames(2)
		var tag: String = "consent/%s" % locale
		var want: Array = donor[locale]
		_expect_true(GateEntryStrings.text("gate.auth.consent.tos") \
			== want[1],
			tag + ": tos label exact")
		_expect_true(GateEntryStrings.text("gate.auth.consent.privacy") \
			== want[2],
			tag + ": privacy label exact")
		_expect_true(consent.get_parsed_text() == want[0] % [
			want[1], want[2]],
			tag + ": sentence exact")
		_expect_true(entry.consent_link_center("tos") \
			!= entry.consent_link_center("privacy"),
			tag + ": links land apart")
		for meta in ["tos", "privacy"]:
			var point: Vector2 = entry.consent_link_center(meta)
			_expect_true(consent.get_global_rect().grow(0.5).has_point(
				point),
				tag + ": %s tap lands on the line" % meta)
	_fired["link"].clear()
	_fired["guest"].clear()
	_fired["provider"].clear()
	TranslationServer.set_locale("ko")
	await _frames(2)
	consent.meta_clicked.emit("tos")
	await _frames(2)
	_expect_true((entry.get_node("GateTermsPanel") as Control).visible,
		"consent: tos opens the Moonlit sheet")
	_expect_true(_fired["link"].is_empty() \
		and _fired["guest"].is_empty() \
		and _fired["provider"].is_empty(),
		"consent: tos starts no play and no login")
	(entry.get_node("GateTermsPanel/Card/Stack/Row/Close"
		) as Button).pressed.emit()
	await _frames(2)
	consent.meta_clicked.emit("privacy")
	_expect_true(_fired["link"].size() == 1 \
		and str(_fired["link"][0]).contains("/ko/privacy"),
		"consent: privacy dispatches the ko Moonlit url")
	_expect_true(_fired["guest"].is_empty() \
		and _fired["provider"].is_empty() \
		and entry.is_selection_open(),
		"consent: privacy starts no play and no login")
	TranslationServer.set_locale("en")
	await _frames(2)
	consent.meta_clicked.emit("privacy")
	_expect_true(_fired["link"].size() == 2 \
		and str(_fired["link"][1]).contains("/en/privacy"),
		"consent: locale switch retargets the url")
	entry.queue_free()
	await _frames(2)
	TranslationServer.set_locale(original_locale)


## The Google mark is the intact measured glyph: this test re-measures
## both donor PNGs itself (desktop suites read the sources), pins the
## ink bounds as literals, and proves the factory draws exactly that
## region with zero stroke, corner, or transparent residue inside.
func _test_google_glyph_truth() -> void:
	_check_tile_glyph(
		"res://assets/third_party/signin/google-android-icon-official.png",
		Rect2(40, 40, 79, 80), "glyph/android")
	_check_tile_glyph(
		"res://assets/third_party/signin/google-ios-icon-official.png",
		Rect2(48, 48, 79, 80), "glyph/ios")


func _check_tile_glyph(path: String, glyph: Rect2, tag: String) -> void:
	var image := Image.load_from_file(path)
	_expect_true(not image.is_empty(), tag + ": donor loads")
	var size: Vector2i = image.get_size()
	var minpos := Vector2i(size.x, size.y)
	var maxpos := Vector2i(-1, -1)
	var colorful: int = 0
	for y in size.y:
		for x in size.x:
			# Integer channels: float boundaries would misclassify.
			var pixel: Color = image.get_pixel(x, y)
			var red: int = int(round(pixel.r * 255.0))
			var green: int = int(round(pixel.g * 255.0))
			var blue: int = int(round(pixel.b * 255.0))
			var alpha: int = int(round(pixel.a * 255.0))
			var spread: int = maxi(maxi(red, green), blue) \
				- mini(mini(red, green), blue)
			if alpha > 128 and mini(mini(red, green), blue) < 248 \
					and spread > 8:
				colorful += 1
				minpos.x = mini(minpos.x, x)
				minpos.y = mini(minpos.y, y)
				maxpos.x = maxi(maxpos.x, x)
				maxpos.y = maxi(maxpos.y, y)
	var measured := Rect2(Vector2(minpos),
		Vector2(maxpos - minpos + Vector2i(1, 1)))
	_expect_true(measured == glyph,
		tag + ": ink bounds re-measured %s" % measured)
	_expect_true(colorful > 3000, tag + ": the G is present")
	_expect_true(GateProviderButtons.glyph_region(path) == measured,
		tag + ": factory draws the measured glyph")
	var drawn: Rect2 = GateProviderButtons.glyph_region(path)
	_expect_true(drawn.position.x >= 30.0 \
		and drawn.position.y >= 30.0 \
		and drawn.end.x <= float(size.x) - 30.0 \
		and drawn.end.y <= float(size.y) - 30.0,
		tag + ": crop clears the tile edges")
	var dirt: int = 0
	for y in int(drawn.size.y):
		for x in int(drawn.size.x):
			var pixel: Color = image.get_pixel(
				int(drawn.position.x) + x,
				int(drawn.position.y) + y)
			var red: int = int(round(pixel.r * 255.0))
			var green: int = int(round(pixel.g * 255.0))
			var blue: int = int(round(pixel.b * 255.0))
			var alpha: int = int(round(pixel.a * 255.0))
			var top: int = maxi(maxi(red, green), blue)
			var spread: int = top - mini(mini(red, green), blue)
			if alpha < 255 or (spread <= 8 and top < 200):
				dirt += 1
	_expect_true(dirt == 0, tag + ": no border residue in the mark")


## The whole padded Apple file carries its glyph horizontally centered,
## so the centered door group needs no layout compensation: symmetric
## white-ink pads, measured here from the imported raster the button
## draws. Integer channel math, like the glyph census above.
func _test_apple_artwork_centering() -> void:
	var tag: String = "apple-center"
	var art: Texture2D = GateProviderButtons.apple_icon()
	_expect_true(art != null, tag + ": artwork loads")
	if art == null:
		return
	var size: Vector2 = art.get_size()
	_expect_true(absf(size.x * 44.0 - size.y * 31.0) <= 0.5,
		tag + ": keeps the padded file ratio")
	var image: Image = art.get_image()
	_expect_true(not image.is_empty(), tag + ": raster reads")
	if image.is_empty():
		return
	var pixels: Vector2i = image.get_size()
	var lo := Vector2i(pixels.x, pixels.y)
	var hi := Vector2i(-1, -1)
	var lit: int = 0
	for y in pixels.y:
		for x in pixels.x:
			var pixel: Color = image.get_pixel(x, y)
			var red: int = int(round(pixel.r * 255.0))
			var green: int = int(round(pixel.g * 255.0))
			var blue: int = int(round(pixel.b * 255.0))
			var alpha: int = int(round(pixel.a * 255.0))
			if alpha > 128 and mini(mini(red, green), blue) > 128:
				lit += 1
				lo.x = mini(lo.x, x)
				lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x)
				hi.y = maxi(hi.y, y)
	_expect_true(lit > 1000, tag + ": the mark is present")
	var pad_l: int = lo.x
	var pad_r: int = pixels.x - 1 - hi.x
	_expect_true(absi(pad_l - pad_r) <= 2,
		tag + ": glyph pads symmetric %d vs %d" % [pad_l, pad_r])


## The modal boundary ignores the real title beacon at its real flare
## peak: every canvas item under the card, dialogs, Terms and loader
## sits on light mask 0 while the art layer keeps mask 1, the beacon
## itself is untouched, and no UI color keys off the light's energy.
## Headless cannot render pixels, so this pins the engine-level
## isolation the render proves; the director screenshots the pixels.
func _test_light_isolation() -> void:
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubProductionHost.new()
	add_child(stub)
	production.set_host_override(stub)
	add_child(production)
	await _frames(3)
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	_expect_true(_flare_peak(title) == 9.92,
		"light: flare peak reads the real 9.92")
	var light: PointLight2D = title.get_node(
		"Beacon/Light") as PointLight2D
	_expect_true(light.range_item_cull_mask == 1,
		"light: the title beacon keeps its own cull mask")
	light.energy = 9.92
	title.request_start()
	await _frames(3)
	gate.set_providers(NOTE_PROVIDERS_UNREADY)
	await _frames(2)
	gate.open_terms()
	await _frames(1)
	# The beacon's own flicker drives energy every frame, so the peak
	# is set synchronously with each walk: no frame lands between.
	light.energy = 9.92
	_expect_true(absf(light.energy - 9.92) <= 0.001,
		"light: peak holds for the terms walk")
	_check_modal_dark(gate, "light/terms")
	gate.close_panels()
	var warden: Hero = load(WARDEN_PATH) as Hero
	gate.open_hall([
		{"rank": 1, "score": 300, "id": "TEST-HALL-1",
			"hero": warden},
	], {"cached": true, "offline": true})
	await _frames(1)
	light.energy = 9.92
	_expect_true(absf(light.energy - 9.92) <= 0.001,
		"light: peak holds for the hall walk")
	_check_modal_dark(gate, "light/hall")
	var keeper: Hero = load(KEEPER_PATH) as Hero
	gate.open_account({"stable_id": TEST_ID, "hero": keeper,
		"provider_label": "Google", "saved_title": "TEST Gate 2",
		"saved_detail": "", "analytics_opt_in": false,
		"show_links": true,
		"link_providers": NOTE_PROVIDERS_READY})
	await _frames(1)
	light.energy = 9.92
	_expect_true(absf(light.energy - 9.92) <= 0.001,
		"light: peak holds for the account walk")
	_check_modal_dark(gate, "light/account")
	gate.open_conflict(
		{"title": "TEST local 3", "detail": "TEST 1",
			"updated": "TEST u1"},
		{"title": "TEST cloud 5", "detail": "TEST 2",
			"updated": "TEST u2"})
	await _frames(1)
	light.energy = 9.92
	_expect_true(absf(light.energy - 9.92) <= 0.001,
		"light: peak holds for the conflict walk")
	_check_modal_dark(gate, "light/conflict")
	_expect_true(light.range_item_cull_mask == 1,
		"light: UI work never reconfigures the beacon")
	light.energy = 4.64
	await _frames(1)
	var idle: Array = _ui_colors(gate)
	light.energy = 9.92
	await _frames(1)
	_expect_true(_ui_colors(gate) == idle,
		"light: UI colors stable from idle to flare")
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## Flare peak of the real title beacon animation: the energy the tap
## flash drives the beacon's light to, read from the shipped track.
func _flare_peak(title: Node) -> float:
	var player: AnimationPlayer = title.get_node(
		"BeaconFx") as AnimationPlayer
	var anim: Animation = player.get_animation("flare")
	var peak: float = 0.0
	for track in anim.get_track_count():
		if str(anim.track_get_path(track)) != "Beacon/Light:energy":
			continue
		for key in anim.track_get_key_count(track):
			peak = maxf(peak,
				float(anim.track_get_key_value(track, key)))
	return peak


## Every modal canvas item unlit, every art item lit-eligible.
func _check_modal_dark(gate: GateEntry, tag: String) -> void:
	var modal: Array = []
	for path in ["Content", "GateAccountPanel", "GateConflictPanel",
			"GateHallPanel", "GateExitPanel", "GateTermsPanel"]:
		_collect_light_items(gate.get_node(path), modal)
	_collect_light_items(gate.get_loader(), modal)
	_expect_true(modal.size() > 0, tag + ": modal tree found")
	for raw in modal:
		var item: CanvasItem = raw as CanvasItem
		_expect_true(item.light_mask == 0,
			tag + ": %s unlit" % item.name)
	var art: Array = []
	_collect_light_items(gate.get_node("ArtLayer"), art)
	_expect_true(art.size() > 0, tag + ": art tree found")
	for raw in art:
		var item: CanvasItem = raw as CanvasItem
		_expect_true(item.light_mask == 1,
			tag + ": %s keeps world light" % item.name)


func _collect_light_items(node: Node, out: Array) -> void:
	if node is CanvasItem:
		out.append(node)
	for child in node.get_children():
		_collect_light_items(child, out)


## Brand fills and inks plus the note text color: the UI palette the
## flare must not move.
func _ui_colors(entry: GateEntry) -> Array:
	var google: Button = entry.get_node(
		"Content/StatusCard/LoggedOut/Providers/ProviderGoogle"
		) as Button
	var apple: Button = entry.get_node(
		"Content/StatusCard/LoggedOut/Providers/ProviderApple"
		) as Button
	var note: Label = entry.get_node(
		"Content/StatusCard/LoggedOut/ProviderNote") as Label
	return [
		(google.get_theme_stylebox("normal") as StyleBoxFlat).bg_color,
		(apple.get_theme_stylebox("normal") as StyleBoxFlat).bg_color,
		GateProviderButtons.title_node(google).get_theme_color(
			"font_color"),
		GateProviderButtons.title_node(apple).get_theme_color(
			"font_color"),
		note.get_theme_color("font_color"),
	]


## Every hero paint rect stays inside the viewport and clear of the tap
## prompt glyphs (measured rendered text, not the full-width label), the
## visible title doors and the version tag.
func _check_title_clearance(production: ProductionEntry, tag: String) -> void:
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var prompt: Label = title.get_node("Ui/Screen/TapPrompt") as Label
	var font: Font = prompt.get_theme_font("font")
	var glyph_width: float = font.get_string_size(tr(prompt.text),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		float(prompt.get_theme_font_size("font_size"))).x
	var prompt_rect: Rect2 = prompt.get_global_rect()
	var glyphs := Rect2(
		prompt_rect.get_center().x - glyph_width * 0.5,
		prompt_rect.position.y, glyph_width, prompt_rect.size.y)
	var clear: Array[Rect2] = [glyphs,
		(title.get_node("Ui/Screen/Version") as Control).get_global_rect()]
	for door_name in ["SettingsButton", "ShrineButton", "LadderButton",
			"ChronicleButton", "StoreButton"]:
		var door: Button = title.get_node("Ui/Screen/" + door_name) as Button
		if door.is_visible_in_tree():
			clear.append(door.get_global_rect())
	var forecourt: GateHeroForecourt = gate.get_forecourt()
	for index in forecourt.actor_count():
		var rect: Rect2 = forecourt.paint_global_rect(index)
		_expect_true(viewport.encloses(rect.grow(-0.5)),
			"%s: hero %d inside %s" % [tag, index, rect])
		for zone in clear:
			_expect_true(not rect.grow(-1.0).intersects(zone.grow(-1.0)),
				"%s: hero %d clears %s" % [tag, index, zone])


func _expect_true(value: bool, message: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("  FAIL ", message)
