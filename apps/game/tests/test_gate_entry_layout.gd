extends Node

## Moon gate entry layout: every framing, locale and dialog fits.
##
## The base 808x360 canvas, a wider 21:9 phone viewport and a 4:3 tablet
## viewport each render the entry surface in all five locales. Every
## visible button stays inside the viewport at a real touch size, labels
## keep their styled smooth fonts, no `gate.*` key ever shows unresolved,
## and dialog cards land fully on screen.

const ENTRY_SCENE: PackedScene = preload("res://scenes/ui/gate_entry.tscn")
const HERO_PATHS: Array[String] = [
	"res://resources/heroes/warden.tres",
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/eclipse.tres",
	"res://resources/heroes/sage.tres",
]
## Longest real hero name ("Silver Moon Knight", 18): the identity and
## Hall fixtures that must fit it prove every shorter name fits too.
const KNIGHT_PATH: String = "res://resources/heroes/knight.tres"
const SMALL_SCENE_PATH: String = "res://scenes/ui/quit_panel.tscn"
const NON_SCENE_PATH: String = "res://icon.svg"
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const FRAMINGS: Array[Vector2i] = [
	Vector2i(808, 360), Vector2i(840, 360), Vector2i(808, 606)]

const TEST_PROVIDERS: Array = [
	{"id": "google", "label": "Google", "ready": true},
	{"id": "apple", "label": "Apple", "ready": true},
]
const TEST_PROVIDERS_UNREADY: Array = [
	{"id": "google", "label": "Google", "ready": true},
	{"id": "apple", "label": "Apple", "ready": false},
	{"id": "passkey", "label": "Passkey", "ready": true, "draining": true},
]
const TEST_PROVIDERS_ALL_DRAINING: Array = [
	{"id": "google", "label": "Google", "ready": true, "draining": true},
	{"id": "apple", "label": "Apple", "ready": true, "draining": true},
	{"id": "passkey", "label": "Passkey", "ready": true, "draining": true},
]
const TEST_SAVE: String = "TEST Gate 1"

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	var original_locale: String = TranslationServer.get_locale()
	var original_size: Vector2i = get_tree().root.size
	# Sync-warm the one worker path this suite loads: cold worker loads
	# leak engine-side temporaries, warm round-trips are silent. The
	# in-flight check below uses the small scene, which is silent cold.
	var warmed: Resource = load(NON_SCENE_PATH) as Resource
	_expect_true(warmed != null, "worker-path warmup loads")
	for framing in FRAMINGS:
		for locale in LOCALES:
			TranslationServer.set_locale(locale)
			await _check_surface(framing, locale)
			await _check_panels(framing, locale)
			await _check_loader_cards(framing, locale)
	TranslationServer.set_locale("ko")
	await _check_settled_composition()
	TranslationServer.set_locale(original_locale)
	get_tree().root.size = original_size
	if _failed > 0:
		printerr("gate-entry-layout test failed — ",
			_failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("gate-entry-layout test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _check_surface(framing: Vector2i, locale: String) -> void:
	var tag: String = "surface/%s/%dx%d" % [locale, framing.x, framing.y]
	get_tree().root.size = framing
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	await get_tree().process_frame
	await get_tree().process_frame
	entry.set_providers(TEST_PROVIDERS)
	entry.show_identity(
		{"stable_id": _long_id(1), "hero": load(KNIGHT_PATH) as Hero},
		{"has_save": true, "title": TEST_SAVE, "detail": ""})
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag)
	_check_forecourt(entry, tag)
	# Geometry must hold after it settles, not just on the first frames.
	for _index in 5:
		await get_tree().process_frame
	_check_tree(entry, tag + "/settled")
	_check_forecourt(entry, tag + "/settled")
	# The login selection in its capable and unready shapes: guest,
	# provider stack, notes, consent and footer must all fit too.
	entry.show_logged_out()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/selection")
	_check_auth_touch(entry, tag + "/selection")
	_check_official_pair(entry, tag + "/selection")
	_check_status_rim(entry, tag + "/selection")
	_check_apple_clearspace(entry, tag + "/selection")
	_check_forecourt(entry, tag + "/selection")
	entry.set_providers(TEST_PROVIDERS_UNREADY)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/selection-unready")
	_check_auth_touch(entry, tag + "/selection-unready")
	_check_official_pair(entry, tag + "/selection-unready")
	_check_status_rim(entry, tag + "/selection-unready")
	_check_apple_clearspace(entry, tag + "/selection-unready")
	_check_forecourt(entry, tag + "/selection-unready")
	entry.set_providers(TEST_PROVIDERS_ALL_DRAINING)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/selection-draining")
	_check_auth_touch(entry, tag + "/selection-draining")
	_check_official_pair(entry, tag + "/selection-draining")
	_check_status_rim(entry, tag + "/selection-draining")
	_check_apple_clearspace(entry, tag + "/selection-draining")
	_check_forecourt(entry, tag + "/selection-draining")
	# Production-default empty shape: guest plus two honestly disabled
	# ordinary doors and the footer still inside 808x360 (Brief 107).
	entry.set_providers([])
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/selection-empty")
	_check_auth_touch(entry, tag + "/selection-empty")
	_check_official_pair(entry, tag + "/selection-empty")
	_check_status_rim(entry, tag + "/selection-empty")
	_check_apple_clearspace(entry, tag + "/selection-empty")
	_check_forecourt(entry, tag + "/selection-empty")
	var empty_doors: VBoxContainer = entry.get_node(
		"Content/StatusCard/LoggedOut/Providers") as VBoxContainer
	_expect_true(empty_doors.get_child_count() == 2,
		"%s: empty list still shows the ordinary pair" % tag)
	_expect_true((empty_doors.get_child(0) as Button).disabled \
		and (empty_doors.get_child(1) as Button).disabled,
		"%s: empty-list ordinary doors disabled" % tag)
	_expect_true(not (entry.get_node(
		"Content/StatusCard/LoggedOut/Guest") as Button).disabled,
		"%s: empty-list guest enabled" % tag)
	entry.queue_free()
	await get_tree().process_frame


func _check_panels(framing: Vector2i, locale: String) -> void:
	var tag: String = "panels/%s/%dx%d" % [locale, framing.x, framing.y]
	get_tree().root.size = framing
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	await get_tree().process_frame
	await get_tree().process_frame
	entry.set_providers(TEST_PROVIDERS)
	# One panel at a time; each must sit fully inside the viewport.
	entry.open_account({
		"stable_id": _long_id(2), "hero": load(KNIGHT_PATH) as Hero,
		"provider_label": "Google", "saved_title": TEST_SAVE,
		"saved_detail": "TEST detail line", "analytics_opt_in": false,
		"show_links": true})
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/account")
	for _index in 5:
		await get_tree().process_frame
	_check_tree(entry, tag + "/account/settled")
	# Production account shapes: the tall local-guest card with link
	# doors and actions scrolls under a pinned header and footer.
	await _check_account_variant(entry, tag, _account_data_ready())
	await _check_account_variant(entry, tag, _account_data_unready())
	await _check_account_variant(entry, tag, _account_data_cloud())
	entry.close_panels()
	entry.open_conflict(
		{"title": "TEST local", "detail": "TEST d1", "updated": "TEST u1"},
		{"title": "TEST cloud", "detail": "TEST d2", "updated": "TEST u2"})
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/conflict")
	entry.close_panels()
	# Real-shape Hall: one long-ID row with the longest hero name, then a
	# hundred rows cycling every hero. Short fixtures missed the 35-char
	# card stretch; these do not.
	entry.open_hall([
		{"rank": 1, "score": 12345, "id": _long_id(3),
			"hero": load(KNIGHT_PATH) as Hero},
	], {"cached": true, "offline": true})
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/hall1")
	_check_hall_card(entry, tag + "/hall1")
	for _index in 5:
		await get_tree().process_frame
	_check_tree(entry, tag + "/hall1/settled")
	_check_hall_card(entry, tag + "/hall1/settled")
	entry.close_panels()
	entry.open_hall(_many_hall_rows(100), {"cached": true, "offline": true})
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/hall100")
	_check_hall_card(entry, tag + "/hall100")
	entry.close_panels()
	entry.open_exit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/exit")
	entry.open_terms()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/terms")
	_check_terms_card(entry, tag + "/terms")
	entry.queue_free()
	await get_tree().process_frame


## Production account data, mirroring what the host hands the panel:
## a local guest with both doors ready, one with an unready door and a
## draining extra, and a linked cloud account with no hero and no save.
func _account_data_ready() -> Dictionary:
	return {
		"stable_id": _long_id(4), "hero": load(KNIGHT_PATH) as Hero,
		"provider_label": GateEntryStrings.text(
			"gate.account.local_guest"),
		"saved_title": TEST_SAVE, "saved_detail": _long_detail(),
		"analytics_opt_in": false, "show_links": true,
		"link_providers": [
			{"id": "google", "label": "Google", "ready": true},
			{"id": "apple", "label": "Apple", "ready": true},
		],
		"can_sign_out": true, "can_delete": true,
	}


func _account_data_unready() -> Dictionary:
	return {
		"stable_id": _long_id(5), "hero": load(KNIGHT_PATH) as Hero,
		"provider_label": GateEntryStrings.text(
			"gate.account.local_guest"),
		"saved_title": TEST_SAVE, "saved_detail": "TEST detail line",
		"analytics_opt_in": false, "show_links": true,
		"link_providers": [
			{"id": "google", "label": "Google", "ready": true},
			{"id": "apple", "label": "Apple", "ready": false},
			{"id": "passkey", "label": "Passkey", "ready": true,
				"draining": true},
		],
		"can_sign_out": true, "can_delete": true,
	}


func _account_data_cloud() -> Dictionary:
	return {
		"stable_id": _long_id(6), "provider_label": "Google",
		"analytics_opt_in": false, "show_links": true,
		"can_sign_out": true, "can_delete": true,
	}


## Save detail that truly exceeds the two-line budget at card width in
## every shape: ~170 characters against ~56 per line.
func _long_detail() -> String:
	return "TEST saved detail that must wrap past two lines at card " \
		+ "width for sure and then some more words to be certain it " \
		+ "exceeds the two-line budget in every locale and framing"


## One production account shape: generic tree checks, pinned
## header/footer, the link pair, real scroll reachability, and the
## armed-delete round trip where the shape offers delete.
func _check_account_variant(entry: GateEntry, tag: String,
		data: Dictionary) -> void:
	var shape: String = "cloud"
	var links: Array = data.get("link_providers", [])
	if not links.is_empty():
		shape = "ready"
		for link in links:
			var row: Dictionary = link as Dictionary
			if not bool(row.get("ready", true)) \
					or bool(row.get("draining", false)):
				shape = "unready"
	var shape_tag: String = "%s/account-%s" % [tag, shape]
	var ids: Dictionary = {}
	for link in links:
		ids[str((link as Dictionary).get("id", ""))] = true
	entry.open_account(data)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, shape_tag)
	_check_account_card(entry, shape_tag)
	_check_account_link_pair(entry, shape_tag,
		ids.has("google") and ids.has("apple"))
	await _check_account_scroll(entry, shape_tag)
	if bool(data.get("can_delete", false)):
		await _check_account_armed_delete(entry, shape_tag)


## The account card keeps its width, stays centered and inside, and
## pins its header and Close footer on screen with the scroll clipped
## to the card.
func _check_account_card(entry: GateEntry, tag: String) -> void:
	var viewport := Rect2(Vector2.ZERO, get_tree().root.size)
	var panel: GateAccountPanel = entry.get_node(
		"GateAccountPanel") as GateAccountPanel
	var card: PanelContainer = panel.get_node("Card") as PanelContainer
	var rect: Rect2 = card.get_global_rect()
	_expect_true(rect.size.x <= 380.5,
		"%s: account card keeps its width (%s)" % [tag, rect.size])
	_expect_true(viewport.encloses(rect.grow(-0.5)),
		"%s: account card inside %s" % [tag, rect])
	_expect_true(absf(viewport.get_center().x - rect.get_center().x) <= 1.0 \
		and absf(viewport.get_center().y - rect.get_center().y) <= 1.0,
		"%s: account card centered" % tag)
	for path in ["Card/Stack/TitleRow/Title",
			"Card/Stack/TitleRow/Status"]:
		var label: Label = panel.get_node(path) as Label
		if not label.is_visible_in_tree():
			continue
		var lrect: Rect2 = label.get_global_rect()
		_expect_true(viewport.encloses(lrect.grow(-0.5)),
			"%s: %s inside %s" % [tag, label.name, lrect])
		_expect_true(rect.grow(-1.0).encloses(lrect.grow(-0.5)),
			"%s: %s inside its card" % [tag, label.name])
	for path in ["Card/Stack/Links/Privacy",
			"Card/Stack/Links/Support", "Card/Stack/Links/Close"]:
		var button: Button = panel.get_node(path) as Button
		if not button.is_visible_in_tree():
			continue
		var brect: Rect2 = button.get_global_rect()
		_expect_true(viewport.encloses(brect.grow(-0.5)),
			"%s: %s inside %s" % [tag, button.name, brect])
		_expect_true(rect.grow(-1.0).encloses(brect.grow(-0.5)),
			"%s: %s inside its card" % [tag, button.name])
		_expect_true(brect.size.y >= 44.0,
			"%s: %s keeps 44px touch height" % [tag, button.name])
	var scroll: ScrollContainer = panel.get_node_or_null(
		"Card/Stack/Scroll") as ScrollContainer
	_expect_true(scroll != null, "%s: middle scrolls" % tag)
	if scroll != null:
		_expect_true(rect.grow(-1.0).encloses(
			scroll.get_global_rect().grow(-0.5)),
			"%s: scroll clips to its card" % tag)


## Every scrolled control by real scroll, not by static rect: each
## button and the ID field scrolls into view and lands inside the
## viewport and the card, actions keep 44px (the compact ID
## accessories keep 36px), and keyboard focus pulls the last action
## on screen from the top.
func _check_account_scroll(entry: GateEntry, tag: String) -> void:
	var viewport := Rect2(Vector2.ZERO, get_tree().root.size)
	var panel: GateAccountPanel = entry.get_node(
		"GateAccountPanel") as GateAccountPanel
	var card: PanelContainer = panel.get_node("Card") as PanelContainer
	var scroll: ScrollContainer = panel.get_node_or_null(
		"Card/Stack/Scroll") as ScrollContainer
	_expect_true(scroll != null, "%s: middle scrolls" % tag)
	if scroll == null:
		return
	var box: VBoxContainer = panel.get_node_or_null(
		"Card/Stack/Scroll/ScrollBox") as VBoxContainer
	_expect_true(box != null, "%s: scroll holds its rows" % tag)
	if box == null:
		return
	var targets: Array[Control] = []
	_collect_scroll_targets(box, targets)
	_expect_true(not targets.is_empty(),
		"%s: scrolled actions found" % tag)
	for target in targets:
		scroll.ensure_control_visible(target)
		await get_tree().process_frame
		await get_tree().process_frame
		var trect: Rect2 = target.get_global_rect()
		_expect_true(viewport.encloses(trect.grow(-0.5)),
			"%s: %s reachable at %s" % [tag, target.name, trect])
		_expect_true(card.get_global_rect().grow(-1.0).encloses(
			trect.grow(-0.5)),
			"%s: %s inside its card" % [tag, target.name])
		if target is Button:
			var floor_height: float = 44.0
			if target.name == "RevealToggle" \
					or target.name == "CopyId":
				floor_height = 36.0
			_expect_true(trect.size.y >= floor_height,
				"%s: %s keeps its touch height" % [tag, target.name])
	_check_account_detail(entry, tag)
	scroll.get_v_scroll_bar().value = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	var last: Button = null
	for target in targets:
		var door: Button = target as Button
		if door != null and not door.disabled:
			last = door
	if last != null:
		last.grab_focus()
		await get_tree().process_frame
		await get_tree().process_frame
		_expect_true(viewport.encloses(
			last.get_global_rect().grow(-0.5)),
			"%s: focus reaches %s" % [tag, last.name])


## Scrolled buttons and the ID field in layout order: rows hide their
## controls one level down, so this walks one level deeper.
func _collect_scroll_targets(box: VBoxContainer,
		out: Array[Control]) -> void:
	for child in box.get_children():
		var control: Control = child as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if child is Button or child is LineEdit:
			out.append(control)
		elif child is Container:
			for grandchild in child.get_children():
				var leaf: Control = grandchild as Control
				if leaf != null and leaf.is_visible_in_tree() \
						and (grandchild is Button \
						or grandchild is LineEdit):
					out.append(leaf)


## The save detail paints its real wrapped block: full text kept,
## rect fits the live shaped lines capped at two, glyphs visible,
## inside the card once scrolled to.
func _check_account_detail(entry: GateEntry, tag: String) -> void:
	var viewport := Rect2(Vector2.ZERO, get_tree().root.size)
	var panel: GateAccountPanel = entry.get_node(
		"GateAccountPanel") as GateAccountPanel
	var card: PanelContainer = panel.get_node("Card") as PanelContainer
	var scroll: ScrollContainer = panel.get_node(
		"Card/Stack/Scroll") as ScrollContainer
	var detail: Label = panel.get_node(
		"Card/Stack/Scroll/ScrollBox/SavedDetail") as Label
	if not detail.is_visible_in_tree():
		return
	scroll.ensure_control_visible(detail)
	await get_tree().process_frame
	await get_tree().process_frame
	var font: Font = detail.get_theme_font("font")
	var font_size: int = detail.get_theme_font_size("font_size")
	var line: float = float(font.get_height(font_size))
	var spacing: float = float(detail.get_theme_constant("line_spacing"))
	var lines: int = mini(maxi(detail.get_line_count(), 1), 2)
	var need: float = float(lines) * line \
		+ float(maxi(lines - 1, 0)) * spacing
	_expect_true(not detail.text.is_empty(),
		"%s: detail keeps its text" % tag)
	_expect_true(absf(detail.get_global_rect().size.y - need) <= 0.5,
		"%s: detail rect fits its lines" % tag)
	_expect_true(detail.get_visible_line_count() == lines,
		"%s: detail paints its lines" % tag)
	_expect_true(viewport.encloses(
		detail.get_global_rect().grow(-0.5)),
		"%s: detail reachable" % tag)
	_expect_true(card.get_global_rect().grow(-1.0).encloses(
		detail.get_global_rect().grow(-0.5)),
		"%s: detail inside its card" % tag)


## Armed delete keeps the pinned shell: the confirm pair scrolls into
## reach with the header and footer on screen, and cancel restores
## the actions row.
func _check_account_armed_delete(entry: GateEntry, tag: String) -> void:
	var viewport := Rect2(Vector2.ZERO, get_tree().root.size)
	var panel: GateAccountPanel = entry.get_node(
		"GateAccountPanel") as GateAccountPanel
	var card: PanelContainer = panel.get_node("Card") as PanelContainer
	var scroll: ScrollContainer = panel.get_node_or_null(
		"Card/Stack/Scroll") as ScrollContainer
	_expect_true(scroll != null, "%s: middle scrolls" % tag)
	if scroll == null:
		return
	var box: VBoxContainer = panel.get_node_or_null(
		"Card/Stack/Scroll/ScrollBox") as VBoxContainer
	_expect_true(box != null, "%s: scroll holds its rows" % tag)
	if box == null:
		return
	var actions: HBoxContainer = box.get_node_or_null(
		"AccountActions") as HBoxContainer
	_expect_true(actions != null, "%s: actions row present" % tag)
	if actions == null:
		return
	var confirm: HBoxContainer = box.get_node(
		"DeleteConfirm") as HBoxContainer
	var arm: Button = box.get_node(
		"AccountActions/DeleteAccount") as Button
	scroll.ensure_control_visible(arm)
	await get_tree().process_frame
	await get_tree().process_frame
	arm.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(confirm.visible and not actions.visible,
		"%s: delete arms" % tag)
	_check_account_card(entry, tag + "/armed")
	for path in ["DeleteConfirm/DeleteNow", "DeleteConfirm/DeleteKeep"]:
		var button: Button = box.get_node(path) as Button
		scroll.ensure_control_visible(button)
		await get_tree().process_frame
		await get_tree().process_frame
		var brect: Rect2 = button.get_global_rect()
		_expect_true(viewport.encloses(brect.grow(-0.5)),
			"%s: %s reachable" % [tag, button.name])
		_expect_true(card.get_global_rect().grow(-1.0).encloses(
			brect.grow(-0.5)),
			"%s: %s inside its card" % [tag, button.name])
		_expect_true(brect.size.y >= 44.0,
			"%s: %s keeps 44px touch height" % [tag, button.name])
	(box.get_node("DeleteConfirm/DeleteKeep") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(actions.visible and not confirm.visible,
		"%s: cancel restores the actions" % tag)


## The account link pair as one voice, like the entry selection pair:
## same 14px type size, one baseline family, one shared text baseline,
## one shared button axis, one shared left-column mark center, and one
## shared title glyph center. Shapes that should carry both doors
## fail when one is missing; shapes without links skip.
func _check_account_link_pair(entry: GateEntry, tag: String,
		expect_pair: bool) -> void:
	var panel: GateAccountPanel = entry.get_node(
		"GateAccountPanel") as GateAccountPanel
	var google: Button = panel.get_node_or_null(
		"Card/Stack/Scroll/ScrollBox/LinkRow/LinkGoogle") as Button
	var apple: Button = panel.get_node_or_null(
		"Card/Stack/Scroll/ScrollBox/LinkRow/LinkApple") as Button
	var both: bool = google != null and apple != null \
		and google.is_visible_in_tree() \
		and apple.is_visible_in_tree()
	if expect_pair:
		_expect_true(both, "%s: both link doors present" % tag)
	if not both:
		return
	var gtitle := GateProviderButtons.title_node(google)
	var atitle := GateProviderButtons.title_node(apple)
	_expect_true(gtitle.get_theme_font_size("font_size") == 14 \
		and atitle.get_theme_font_size("font_size") == 14,
		"%s: the link pair shares one 14px type size" % tag)
	var gfont: Font = gtitle.get_theme_font("font")
	var afont: Font = atitle.get_theme_font("font")
	_expect_true(gfont.get_height(14) == afont.get_height(14) \
		and gfont.get_ascent(14) == afont.get_ascent(14) \
		and gfont.get_descent(14) == afont.get_descent(14),
		"%s: the link pair shares one baseline family" % tag)
	_expect_true(absf(_title_baseline_door_y(google, gtitle) \
		- _title_baseline_door_y(apple, atitle)) <= 1.0,
		"%s: the link pair shares one text baseline" % tag)
	_expect_true(absf(google.get_global_rect().get_center().x \
		- apple.get_global_rect().get_center().x) <= 0.5,
		"%s: the link pair shares one button axis" % tag)
	var glogo := GateProviderButtons.logo_node(google)
	var alogo := GateProviderButtons.logo_node(apple)
	_expect_true(absf(glogo.get_global_rect().get_center().x \
		- alogo.get_global_rect().get_center().x) <= 1.0,
		"%s: the link pair shares one left-column mark center" % tag)
	_expect_true(absf(gtitle.get_global_rect().get_center().x \
		- atitle.get_global_rect().get_center().x) <= 1.0,
		"%s: the link pair shares one title glyph center" % tag)


## True while a ScrollContainer clips this control: scrolled content
## proves reachability through the scroll checks, never through static
## viewport rects.
func _inside_scroll(control: Control) -> bool:
	var current: Node = control.get_parent()
	while current != null:
		if current is ScrollContainer:
			return true
		current = current.get_parent()
	return false


## Loader cards must fit too: in-flight veil, error card, cancelled card.
## Stage/detail glyphs keep readable rects from the first paint, in every
## locale and framing, through text changes and the two-line cap.
func _check_loader_cards(framing: Vector2i, locale: String) -> void:
	var tag: String = "loader/%s/%dx%d" % [locale, framing.x, framing.y]
	get_tree().root.size = framing
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	await get_tree().process_frame
	await get_tree().process_frame
	entry.set_providers(TEST_PROVIDERS)
	var loader: GateLoadingOverlay = entry.get_loader()
	loader.begin(SMALL_SCENE_PATH, "TEST entering somewhere")
	await get_tree().process_frame
	_expect_true(not loader.is_request_issued(),
		"%s/flying: no request before first paint" % tag)
	_check_tree(entry, tag + "/flying")
	_check_loader_glyphs(entry, tag + "/flying")
	await _settle_loader(loader)
	loader.begin(NON_SCENE_PATH, "TEST entering nowhere")
	await _settle_loader(loader)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/error")
	_check_loader_glyphs(entry, tag + "/error")
	loader.begin(SMALL_SCENE_PATH, "TEST entering somewhere")
	loader.cancel()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/cancelled")
	_check_loader_glyphs(entry, tag + "/cancelled")
	# Locale-resolved stage and long wrapping stage on the stable
	# cancelled card: same reserve path, every locale and framing.
	loader.set_stage_text(GateEntryStrings.text("gate.loading.preparing"))
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/cancelled-locale")
	_check_loader_glyphs(entry, tag + "/cancelled-locale")
	var long_stage: String = "TEST entering somewhere with a very long stage line " \
		+ "that must wrap past two lines at card width for sure and more words"
	loader.set_stage_text(long_stage)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_tree(entry, tag + "/cancelled-long")
	_check_loader_glyphs(entry, tag + "/cancelled-long")
	var stage: Label = loader.get_node(
		"LoadingCard/Stack/Stage") as Label
	_expect_true(stage.get_line_count() >= 3,
		"%s/cancelled-long: stage wraps past max" % tag)
	_expect_true(stage.get_visible_line_count() == 2,
		"%s/cancelled-long: stage capped to two" % tag)
	entry.queue_free()
	await get_tree().process_frame


## Post-arrival composition at the base framing: the lineup at rest must
## hold the same bounds it holds mid-arrival, after the roots land and the
## drift has moved on. Wall time, not frames: arrival runs on tweens.
func _check_settled_composition() -> void:
	get_tree().root.size = Vector2i(808, 360)
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	await get_tree().process_frame
	await get_tree().process_frame
	entry.set_providers(TEST_PROVIDERS)
	entry.show_identity(
		{"stable_id": _long_id(1), "hero": load(KNIGHT_PATH) as Hero},
		{"has_save": true, "title": TEST_SAVE, "detail": ""})
	await get_tree().create_timer(2.0).timeout
	_check_forecourt(entry, "settled/ko/808x360")
	entry.queue_free()
	await get_tree().process_frame


## Actual-shape stable ID: `MB-` plus a zero-padded body, 35 characters.
func _long_id(index: int) -> String:
	return "MB-%032d" % index


func _many_hall_rows(count: int) -> Array:
	var rows: Array = []
	for index in count:
		var hero: Hero = load(HERO_PATHS[index % HERO_PATHS.size()]) as Hero
		rows.append({
			"rank": index + 1,
			"score": 12345 - index,
			"id": _long_id(1000 + index),
			"hero": hero,
		})
	return rows


## The Hall card keeps its intended width and stays fully on screen with
## real long IDs: no min-size stretch, no off-center drift, no spill.
func _check_hall_card(entry: GateEntry, tag: String) -> void:
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	var card: PanelContainer = entry.get_node(
		"GateHallPanel/Card") as PanelContainer
	var rect: Rect2 = card.get_global_rect()
	_expect_true(rect.size.x <= 420.5,
		"%s: hall card keeps its width (%s)" % [tag, rect.size])
	_expect_true(viewport.encloses(rect.grow(-0.5)),
		"%s: hall card inside %s" % [tag, rect])
	_expect_true(absf(viewport.get_center().x - rect.get_center().x) <= 1.0,
		"%s: hall card centered" % tag)
	for row in entry.get_node("GateHallPanel/Card/Stack/Rows/RowsBox") \
			.get_children():
		var id_line: Label = row.get_node("Line/Middle/IdLine") as Label
		_expect_true(id_line.text.length() == 35,
			"%s: full 35-char id kept" % tag)
		_expect_true(not id_line.clip_text,
			"%s: id wraps, never clips" % tag)


func _settle_loader(loader: GateLoadingOverlay) -> void:
	var start: int = Time.get_ticks_msec()
	while (loader.is_loading() or loader.has_pending_drain()) \
			and Time.get_ticks_msec() - start < 30000:
		await get_tree().create_timer(0.05).timeout


## Wrapped need for a clipped loader label: capped lines times font height
## plus spacing, from the label's own line count (correct even when its
## rect collapsed to 1px). Independent of the overlay's reserve path.
func _loader_wrapped_need(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var line: float = float(font.get_height(font_size))
	var spacing: float = float(label.get_theme_constant("line_spacing"))
	var lines: int = label.get_line_count()
	var max_lines: int = label.max_lines_visible
	var capped: int = mini(lines, max_lines) if max_lines > 0 else lines
	capped = maxi(capped, 1)
	return float(capped) * line + float(capped - 1) * spacing


## Loader card glyphs: readable stage/detail rects, disjoint stack, card
## and buttons inside. The generic tree check covers viewport and faces;
## this covers the clipped wrapped heights it cannot see.
func _check_loader_glyphs(entry: GateEntry, tag: String) -> void:
	var loader: GateLoadingOverlay = entry.get_loader()
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	var card: PanelContainer = loader.get_node("LoadingCard") as PanelContainer
	if not card.is_visible_in_tree():
		_expect_true(false, "%s: loader card visible" % tag)
		return
	var card_rect: Rect2 = card.get_global_rect()
	_expect_true(viewport.encloses(card_rect.grow(-0.5)),
		"%s: loader card inside %s" % [tag, card_rect])
	for label_path in ["LoadingCard/Stack/Stage",
			"LoadingCard/Stack/Detail"]:
		var label: Label = loader.get_node(label_path) as Label
		if not label.is_visible_in_tree():
			continue
		var font: Font = label.get_theme_font("font")
		var font_size: int = label.get_theme_font_size("font_size")
		var line: float = float(font.get_height(font_size))
		var need: float = _loader_wrapped_need(label)
		var rect: Rect2 = label.get_global_rect()
		var max_lines: int = label.max_lines_visible
		var capped: int = mini(label.get_line_count(), max_lines) \
			if max_lines > 0 else label.get_line_count()
		capped = maxi(capped, 1)
		_expect_true(not label.text.is_empty(),
			"%s: %s has text" % [tag, label.name])
		_expect_true(rect.size.x > 64.0,
			"%s: %s readable width" % [tag, label.name])
		_expect_true(rect.size.y >= line - 0.5,
			"%s: %s at least one line" % [tag, label.name])
		_expect_true(rect.size.y >= need - 0.5,
			"%s: %s wrapped need" % [tag, label.name])
		_expect_true(rect.size.y > 1.5,
			"%s: %s not 1px" % [tag, label.name])
		_expect_true(label.custom_minimum_size.y >= need - 0.5,
			"%s: %s reserved" % [tag, label.name])
		_expect_true(label.get_visible_line_count() >= capped,
			"%s: %s glyphs visible" % [tag, label.name])
	var parts: Array = []
	for path in ["LoadingCard/Stack/Stage", "LoadingCard/Stack/Progress",
			"LoadingCard/Stack/Status", "LoadingCard/Stack/Detail",
			"LoadingCard/Stack/Buttons"]:
		var child: Control = loader.get_node(path) as Control
		if child.is_visible_in_tree():
			parts.append(child)
	for index in parts.size():
		var first: Control = parts[index] as Control
		for other in range(index + 1, parts.size()):
			var second: Control = parts[other] as Control
			var overlap: bool = first.get_global_rect().grow(-1.0) \
				.intersects(second.get_global_rect().grow(-1.0))
			_expect_true(not overlap, "%s: %s and %s do not overlap" % [
				tag, first.name, second.name])
	for button_path in ["LoadingCard/Stack/Buttons/Cancel",
			"LoadingCard/Stack/Buttons/Retry",
			"LoadingCard/Stack/Buttons/Back"]:
		var button: Button = loader.get_node(button_path) as Button
		if not button.is_visible_in_tree():
			continue
		_expect_true(card_rect.grow(-1.0).encloses(
			button.get_global_rect().grow(-0.5)),
			"%s: %s inside loader card" % [tag, button.name])


func _check_tree(entry: GateEntry, tag: String) -> void:
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	var buttons: Array = []
	_collect(entry, buttons, "Button")
	var labels: Array = []
	_collect(entry, labels, "Label")
	var cards: Array = []
	_collect(entry, cards, "PanelContainer")
	var fields: Array = []
	_collect(entry, fields, "LineEdit")
	var bars: Array = []
	_collect(entry, bars, "ProgressBar")
	var consents: Array = []
	_collect(entry, consents, "RichTextLabel")
	for raw in buttons:
		var button: Button = raw as Button
		if not button.is_visible_in_tree():
			continue
		var rect: Rect2 = button.get_global_rect()
		# Scrolled controls prove reachability through real scrolls in
		# the panel checks, never through static viewport rects here.
		var scrolled: bool = _inside_scroll(button)
		if not scrolled:
			_expect_true(viewport.encloses(rect.grow(-0.5)),
				"%s: %s inside %s" % [tag, button.name, rect])
		_expect_true(rect.size.x >= 44.0 and rect.size.y >= 36.0,
			"%s: %s touch size %s" % [tag, button.name, rect.size])
		# The official doors carry vendor type on their Title labels
		# (pinned in _check_official_faces), not on the Button itself.
		if not _is_official_door(button):
			_expect_true(button.has_theme_font_override("font"),
				"%s: %s styled font" % [tag, button.name])
		_expect_resolved(button.text, "%s: %s" % [tag, button.name])
		_check_button_faces(button, "%s: %s" % [tag, button.name])
		var card: PanelContainer = _owning_card(button, entry)
		if card != null and not scrolled:
			_expect_true(
				card.get_global_rect().grow(-1.0).encloses(
					rect.grow(-0.5)),
				"%s: %s inside its card" % [tag, button.name])
	for index in buttons.size():
		var first: Button = buttons[index] as Button
		if not first.is_visible_in_tree():
			continue
		for other in range(index + 1, buttons.size()):
			var second: Button = buttons[other] as Button
			if not second.is_visible_in_tree():
				continue
			if _dialog_root(first) != _dialog_root(second):
				continue
			# A clipped-away global rect overlaps the pinned rows by
			# construction; the scroll checks prove each lands clear.
			# Two scrolled buttons stay comparable: the box lays them
			# out disjointly, clipped or not.
			if _inside_scroll(first) != _inside_scroll(second):
				continue
			var overlap: bool = first.get_global_rect().grow(-1.0) \
				.intersects(second.get_global_rect().grow(-1.0))
			_expect_true(not overlap, "%s: %s and %s do not overlap" % [
				tag, first.name, second.name])
	for raw_label in labels:
		var label: Label = raw_label as Label
		if not label.is_visible_in_tree():
			continue
		_expect_true(label.has_theme_font_override("font"),
			"%s: %s styled font" % [tag, label.name])
		_expect_resolved(label.text, "%s: %s" % [tag, label.name])
	for raw_card in cards:
		var card: PanelContainer = raw_card as PanelContainer
		if not card.is_visible_in_tree():
			continue
		_expect_true(card.get_theme_stylebox("panel") is GateFrameStyle,
			"%s: %s authored card face" % [tag, card.name])
	for raw_field in fields:
		var field: LineEdit = raw_field as LineEdit
		if not field.is_visible_in_tree():
			continue
		_expect_true(field.get_theme_stylebox("normal") is GateFrameStyle,
			"%s: %s authored field face" % [tag, field.name])
	for raw_bar in bars:
		var bar: ProgressBar = raw_bar as ProgressBar
		if not bar.is_visible_in_tree():
			continue
		_expect_true(bar.get_theme_stylebox("background") is GateFrameStyle \
			and bar.get_theme_stylebox("fill") is GateFrameStyle,
			"%s: %s authored progress faces" % [tag, bar.name])
	for raw_consent in consents:
		var rich: RichTextLabel = raw_consent as RichTextLabel
		if not rich.is_visible_in_tree():
			continue
		_expect_true(rich.has_theme_font_override("normal_font"),
			"%s: %s styled font" % [tag, rich.name])
		_expect_true(rich.text.contains("[url=tos]") \
			and rich.text.contains("[url=privacy]"),
			"%s: %s carries both links" % [tag, rich.name])
		_expect_true(not rich.get_parsed_text().contains("%s") \
			and not rich.get_parsed_text().contains("{comma}"),
			"%s: %s formats its sentence" % [tag, rich.name])
		var rich_rect: Rect2 = rich.get_global_rect()
		_expect_true(viewport.encloses(rich_rect.grow(-0.5)),
			"%s: %s inside %s" % [tag, rich.name, rich_rect])
		var rich_card: PanelContainer = _owning_card(rich, entry)
		if rich_card != null:
			_expect_true(
				rich_card.get_global_rect().grow(-1.0).encloses(
					rich_rect.grow(-0.5)),
				"%s: %s inside its card" % [tag, rich.name])


## All five button faces are authored frames, never flat boxes — except
## the two official provider doors, which wear vendor-brand flat faces
## and get stronger brand checks instead of the frame check.
func _check_button_faces(button: Button, where: String) -> void:
	if _is_official_door(button):
		_check_official_faces(button, where)
		return
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var face: StyleBox = button.get_theme_stylebox(state_name)
		_expect_true(face is GateFrameStyle,
			"%s %s authored" % [where, state_name])
		_expect_true(not (face is StyleBoxFlat),
			"%s %s no flat box" % [where, state_name])


func _is_official_door(button: Button) -> bool:
	var parent: Node = button.get_parent()
	if parent == null:
		return false
	if parent.name == "Providers":
		return button.name == "ProviderGoogle" \
			or button.name == "ProviderApple"
	if parent.name == "LinkRow":
		return button.name == "LinkGoogle" \
			or button.name == "LinkApple"
	return false


## The vendor-brand exception: flat faces in the brand palette, the
## outer focus ring, the left-column mark and centered title with
## vendor type and an untinted fitted mark, and 44px. Centering and
## fit come from live rects, never from alignment flags or summed widths.
func _check_official_faces(button: Button, where: String) -> void:
	var provider_id: String = "apple"
	if button.name == "ProviderGoogle" \
			or button.name == "LinkGoogle":
		provider_id = "google"
	# Spec values as literals, never the factory's own constants.
	var fill: Color = Color(1, 1, 1)
	var border: Color = Color("747775")
	var ink: Color = Color("1f1f1f")
	var font_size: int = 14
	if provider_id == "apple":
		fill = Color(0, 0, 0)
		border = Color(0, 0, 0)
		ink = Color(1, 1, 1)
		font_size = 14
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var face: StyleBox = button.get_theme_stylebox(state_name)
		_expect_true(face is StyleBoxFlat,
			"%s %s flat brand face" % [where, state_name])
		_expect_true(not (face is GateFrameStyle),
			"%s %s no game frame" % [where, state_name])
	_expect_true((button.get_theme_stylebox("normal") as StyleBoxFlat) \
		.bg_color == fill, "%s normal keeps its brand fill" % where)
	_expect_true((button.get_theme_stylebox("disabled") as StyleBoxFlat) \
		.bg_color == fill, "%s disabled keeps its brand fill" % where)
	_expect_true((button.get_theme_stylebox("normal") as StyleBoxFlat) \
		.border_color == border, "%s keeps its brand border" % where)
	var focus := button.get_theme_stylebox("focus") as StyleBoxFlat
	_expect_true(focus != null and focus.bg_color == fill,
		"%s focus retints nothing" % where)
	_expect_true(focus != null and focus.expand_margin_left == 2 \
		and focus.expand_margin_top == 2,
		"%s focus ring sits outside" % where)
	_expect_true(button.text.is_empty(),
		"%s draws no native text over its group" % where)
	_expect_true(button.icon == null,
		"%s draws no native icon over its group" % where)
	_expect_true(button.clip_contents,
		"%s clips overflow at its own rect" % where)
	var group := GateProviderButtons.content_group(button)
	var logo := GateProviderButtons.logo_node(button)
	var title := GateProviderButtons.title_node(button)
	_expect_true(group != null and logo != null and title != null,
		"%s composes its group, mark, and title" % where)
	if group == null or logo == null or title == null:
		return
	_expect_true(group is Control and not (group is Container),
		"%s anchors its content, never a box" % where)
	_expect_true(title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER \
		and title.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
		"%s centers its title on the door" % where)
	_expect_true(group.mouse_filter == Control.MOUSE_FILTER_IGNORE \
		and logo.mouse_filter == Control.MOUSE_FILTER_IGNORE \
		and title.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"%s keeps its children mouse-transparent" % where)
	_expect_true(button.accessibility_labeled_by_nodes.size() == 1,
		"%s binds one action label" % where)
	var labeled: Node = null
	if button.accessibility_labeled_by_nodes.size() == 1:
		labeled = button.get_node_or_null(
			button.accessibility_labeled_by_nodes[0])
	_expect_true(labeled == title,
		"%s labels its action from its visible title" % where)
	_expect_true(tr(title.text) != title.text,
		"%s resolves its action, never a raw key" % where)
	_expect_true(title.get_theme_font_size("font_size") == font_size,
		"%s keeps its brand type size" % where)
	_expect_true(title.get_theme_color("font_color") == ink,
		"%s keeps its opaque brand ink" % where)
	_expect_true(not title.clip_text,
		"%s never crushes its title to a sliver" % where)
	_expect_true(title.get_line_count() == 1 \
		and title.get_visible_line_count() == 1,
		"%s shapes its title on one line" % where)
	_expect_true(logo.texture != null, "%s shows its mark" % where)
	_expect_true(logo.texture_filter \
		== CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
		"%s minifies its mark clean" % where)
	_expect_true(logo.modulate == Color(1, 1, 1) \
		and logo.self_modulate == Color(1, 1, 1),
		"%s never tints its mark" % where)
	_expect_true(button.custom_minimum_size.y == 44.0,
		"%s keeps 44px prominence" % where)
	_check_official_group_rects(button, group, logo, title, where)


## All six heroes stand fully on screen at readable paint heights,
## clear of the centered card, the offline badge and the gate mouth, at
## every framing and locale. Bounds use visible paint (bodies plus held
## weapons), never the transparent atlas cells. (The gate's own title
## block and menu bar are retired: the original title owns them now.)
func _check_forecourt(entry: GateEntry, tag: String) -> void:
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	var forecourt: GateHeroForecourt = entry.get_forecourt()
	_expect_true(forecourt.actor_count() == 6,
		"%s: six heroes in the lineup" % tag)
	var clear: Array[Rect2] = [
		(entry.get_node("Content/StatusCard") as Control).get_global_rect(),
		(entry.get_node("Content/OfflineBadge") as Control).get_global_rect(),
		forecourt.gate_mouth_rect(),
	]
	for index in forecourt.actor_count():
		var info: Dictionary = forecourt.actor_info(index)
		var paint: Vector2 = info["paint_size"]
		var back_row: bool = index < 3
		var low: float = GateHeroForecourt.BACK_PAINT_MIN if back_row \
			else GateHeroForecourt.FRONT_PAINT_MIN
		var high: float = GateHeroForecourt.BACK_PAINT_MAX if back_row \
			else GateHeroForecourt.FRONT_PAINT_MAX
		_expect_true(paint.y >= low and paint.y <= high,
			"%s: hero %d paint height %d in %d-%d" % [
				tag, index, int(paint.y), int(low), int(high)])
		var rect: Rect2 = info["paint_rect"]
		_expect_true(viewport.encloses(rect.grow(-0.5)),
			"%s: hero %d inside %s" % [tag, index, rect])
		for zone in clear:
			_expect_true(not rect.grow(-1.0).intersects(zone.grow(-1.0)),
				"%s: hero %d clears %s" % [tag, index, zone])


## Guest keeps 40px touch height below the provider column, the two
## official doors keep exactly 44px each, and extra doors keep 40px.
func _check_auth_touch(entry: GateEntry, tag: String) -> void:
	var guest: Button = entry.get_node(
		"Content/StatusCard/LoggedOut/Guest") as Button
	_expect_true(guest.get_global_rect().size.y >= 40.0,
		"%s: guest keeps 40px touch height" % tag)
	var row: VBoxContainer = entry.get_node(
		"Content/StatusCard/LoggedOut/Providers") as VBoxContainer
	_expect_true(guest.get_global_rect().position.y \
		>= row.get_global_rect().end.y - 0.5,
		"%s: guest sits below the provider stack" % tag)
	for child in row.get_children():
		var door: Button = child as Button
		if door.name == "ProviderGoogle" \
				or door.name == "ProviderApple":
			_expect_true(absf(door.get_global_rect().size.y - 44.0) \
				<= 0.5,
				"%s: %s keeps 44px prominence" % [tag, door.name])
		else:
			_expect_true(door.get_global_rect().size.y >= 40.0,
				"%s: %s keeps 40px touch height" % [tag, door.name])


## The anchored content as the engine laid it out at this framing:
## the mark on the 32px left column, the title rect symmetric about
## the door axis with 64px reserves, the glyph line centered on the
## door within 1px, no glyph overlap, and both inside the door rect
## with platform edges. Every quantity is read back from live rects
## after layout.
func _check_official_group_rects(button: Button, group: Control,
		logo: TextureRect, title: Label, where: String) -> void:
	# Spec values as literals, never the factory's own constants.
	var edge: int = 12
	if OS.get_name() == "iOS":
		edge = 16
	if button.name == "ProviderApple" \
			or button.name == "LinkApple":
		edge = 16
	var brect: Rect2 = button.get_global_rect()
	var grect: Rect2 = group.get_global_rect()
	var lrect: Rect2 = logo.get_global_rect()
	var trect: Rect2 = title.get_global_rect()
	_expect_true(absf(grect.position.x - brect.position.x) <= 0.5 \
		and absf(grect.position.y - brect.position.y) <= 0.5 \
		and absf(grect.size.x - brect.size.x) <= 0.5 \
		and absf(grect.size.y - brect.size.y) <= 0.5,
		"%s spans its door, so the anchors hold" % where)
	_expect_true(lrect.size.x > 16.0 and trect.size.x > 64.0,
		"%s paints readable mark and title widths" % where)
	_expect_true(absf(lrect.get_center().x - brect.position.x - 32.0) \
		<= 1.0,
		"%s pins its mark on the 32px left column" % where)
	_expect_true(absf(trect.get_center().x - brect.get_center().x) \
		<= 1.0,
		"%s centers its title rect on the door axis" % where)
	_expect_true(absf(trect.position.x - brect.position.x - 64.0) \
		<= 1.0 \
		and absf(brect.end.x - trect.end.x - 64.0) <= 1.0,
		"%s reserves symmetric 64px edges" % where)
	var font: Font = title.get_theme_font("font")
	var ink: float = font.get_string_size(tr(title.text),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, float(
			title.get_theme_font_size("font_size"))).x
	var glyph := Rect2(trect.get_center().x - ink * 0.5,
		trect.position.y, ink, trect.size.y)
	_expect_true(absf(glyph.get_center().x - brect.get_center().x) \
		<= 1.0,
		"%s centers its glyph line on the door axis" % where)
	_expect_true(lrect.end.x <= glyph.position.x,
		"%s never overlaps mark and glyphs" % where)
	_expect_true(glyph.position.x - lrect.end.x >= 8.0 - 0.5,
		"%s clears its mark by 8px" % where)
	_expect_true(brect.grow(0.5).encloses(lrect) \
		and brect.grow(0.5).encloses(trect),
		"%s fits its content in its door rect" % where)
	_expect_true(glyph.position.x >= brect.position.x + float(edge) \
		- 0.5 and glyph.end.x <= brect.end.x - float(edge) + 0.5,
		"%s clears its platform edges" % where)
	_expect_true(lrect.position.x >= brect.position.x + float(edge) \
		- 0.5,
		"%s clears its platform edge" % where)


## The official pair as one voice at this framing: same 14px type size,
## same line metrics (one baseline family), one shared text baseline
## read back from live title rects, one shared button axis, one shared
## left-column mark center, and one shared title glyph center.
func _check_official_pair(entry: GateEntry, tag: String) -> void:
	var row: VBoxContainer = entry.get_node(
		"Content/StatusCard/LoggedOut/Providers") as VBoxContainer
	var google: Button = row.get_node("ProviderGoogle") as Button
	var apple: Button = row.get_node("ProviderApple") as Button
	var gtitle := GateProviderButtons.title_node(google)
	var atitle := GateProviderButtons.title_node(apple)
	_expect_true(gtitle.get_theme_font_size("font_size") == 14 \
		and atitle.get_theme_font_size("font_size") == 14,
		"%s: the pair shares one 14px type size" % tag)
	var gfont: Font = gtitle.get_theme_font("font")
	var afont: Font = atitle.get_theme_font("font")
	_expect_true(gfont.get_height(14) == afont.get_height(14) \
		and gfont.get_ascent(14) == afont.get_ascent(14) \
		and gfont.get_descent(14) == afont.get_descent(14),
		"%s: the pair shares one baseline family" % tag)
	_expect_true(absf(_title_baseline_door_y(google, gtitle) \
		- _title_baseline_door_y(apple, atitle)) <= 1.0,
		"%s: the pair shares one text baseline" % tag)
	_expect_true(absf(google.get_global_rect().get_center().x \
		- apple.get_global_rect().get_center().x) <= 0.5,
		"%s: the pair shares one button axis" % tag)
	var glogo := GateProviderButtons.logo_node(google)
	var alogo := GateProviderButtons.logo_node(apple)
	_expect_true(absf(glogo.get_global_rect().get_center().x \
		- alogo.get_global_rect().get_center().x) <= 1.0,
		"%s: the pair shares one left-column mark center" % tag)
	_expect_true(absf(gtitle.get_global_rect().get_center().x \
		- atitle.get_global_rect().get_center().x) <= 1.0,
		"%s: the pair shares one title glyph center" % tag)


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
		"%s: apple clears google by 5px" % tag)
	var apple_index: int = apple.get_index()
	if apple_index + 1 < row.get_child_count():
		var below: Control = row.get_child(apple_index + 1) as Control
		_expect_true(below.get_global_rect().position.y - arect.end.y \
			>= 5.0 - 0.01,
			"%s: apple clears %s by 5px" % [tag, below.name])
	else:
		var row_index: int = row.get_index()
		var sibling: Control = box.get_child(row_index + 1) as Control
		while not sibling.visible:
			row_index += 1
			sibling = box.get_child(row_index + 1) as Control
		_expect_true(sibling.get_global_rect().position.y \
			- row.get_global_rect().end.y >= 5.0 - 0.01,
			"%s: apple clears %s by 5px" % [tag, sibling.name])
	var crect: Rect2 = card.get_global_rect()
	_expect_true(arect.position.x - crect.position.x >= 5.0,
		"%s: apple clears the left rim by 5px" % tag)
	_expect_true(crect.end.x - arect.end.x >= 5.0,
		"%s: apple clears the right rim by 5px" % tag)


## The selection card keeps its fixed width with its whole rim inside
## the viewport at this framing, in every shape the surface takes.
func _check_status_rim(entry: GateEntry, tag: String) -> void:
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	var card: PanelContainer = entry.get_node(
		"Content/StatusCard") as PanelContainer
	var rect: Rect2 = card.get_global_rect()
	_expect_true(absf(rect.size.x - GateEntry.CARD_WIDTH) <= 0.5,
		"%s: card keeps its width" % tag)
	_expect_true(viewport.encloses(rect.grow(-0.5)),
		"%s: whole card rim inside %s" % [tag, rect])


## The Terms sheet keeps its width, stays centered and inside, and reads
## all eight paragraphs with its buttons in its card.
func _check_terms_card(entry: GateEntry, tag: String) -> void:
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	var card: PanelContainer = entry.get_node(
		"GateTermsPanel/Card") as PanelContainer
	var rect: Rect2 = card.get_global_rect()
	_expect_true(rect.size.x <= 420.5,
		"%s: terms card keeps its width (%s)" % [tag, rect.size])
	_expect_true(viewport.encloses(rect.grow(-0.5)),
		"%s: terms card inside %s" % [tag, rect])
	_expect_true(absf(viewport.get_center().x - rect.get_center().x) <= 1.0,
		"%s: terms card centered" % tag)
	var body: Label = entry.get_node(
		"GateTermsPanel/Card/Stack/Scroll/Body") as Label
	_expect_true(body.text.count("\n\n") == GateEntry.TERMS_PARAGRAPHS - 1,
		"%s: terms body reads all eight paragraphs" % tag)


func _expect_resolved(text_value: String, where: String) -> void:
	if not text_value.begins_with("gate."):
		_checked += 1
		return
	_expect_true(tr(text_value) != text_value,
		"%s shows resolved text, not %s" % [where, text_value])


func _collect(node: Node, out: Array, type_name: String) -> void:
	if node.get_class() == type_name:
		out.append(node)
	for child in node.get_children():
		_collect(child, out, type_name)


func _dialog_root(node: Node) -> Node:
	var current: Node = node
	while current.get_parent() != null and current.get_parent().name != "GateEntry":
		current = current.get_parent()
	return current


## Nearest card (dialog Card or StatusCard) above this control, if any.
func _owning_card(control: Control, entry: GateEntry) -> PanelContainer:
	var current: Node = control.get_parent()
	while current != null and current != entry:
		if current is PanelContainer \
				and (current.name == "Card" or current.name == "StatusCard"):
			return current as PanelContainer
		current = current.get_parent()
	return null


func _expect_true(value: bool, message: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("  FAIL ", message)
