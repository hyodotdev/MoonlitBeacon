extends Node

## Render harness for the moon gate entry surface.
##
## Windowed, for the director's eyes and screenshots (stays open unless
## `shot=` is given):
##     godot --path apps/game res://tools/shot_gate_entry.tscn -- state=ready locale=ko
##     godot --path apps/game res://tools/shot_gate_entry.tscn -- state=hall width=808 height=606 shot=/tmp/hall.png
##
## Headless, for invariants (walks every state, locale and framing):
##     godot --headless --path apps/game res://tools/shot_gate_entry.tscn -- validate
##
## `state=` picks one of logged_out, busy, error, ready, ready_no_save,
## loading, loading_error, loading_cancelled, hall, hall_single,
## hall_many, hall_empty, conflict, account, exit, lineup, unready,
## terms. `reduced_motion=1` freezes the ambient layers. `lineup` is the
## marketing composition: the ready card with the gold primary and the
## full six-hero forecourt. `unready` shows a real unavailable-provider
## shape: one ready, one down, one draining. `terms` opens the in-app
## Terms sheet over the selection.
##
## `prod=1` boots the real production entry instead (windowed): the
## original title at rest, or with `state=selection` the tapped login
## selection over it. `capable=1` swaps the real host for a TEST stub
## whose Google and Apple doors read ready; every such run prints a
## FIXTURE banner and is never the production truth.
##
## All identity, save and Hall payloads below are clearly marked TEST data.
## Portraits come from the real hero resources on purpose: the panel must
## exercise the same portrait path production will use. Provider proper
## nouns ("Google", "Apple") are labels, not identities.

const ENTRY_SCENE: PackedScene = preload("res://scenes/ui/gate_entry.tscn")
const PRODUCTION_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")
const HERO_PATHS: Array[String] = [
	"res://resources/heroes/warden.tres",
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/eclipse.tres",
	"res://resources/heroes/sage.tres",
]
const KNIGHT_PATH: String = "res://resources/heroes/knight.tres"
const SAGE_PATH: String = "res://resources/heroes/sage.tres"
const ARENA_PATH: String = "res://scenes/gameplay/arena.tscn"
const SMALL_SCENE_PATH: String = "res://scenes/ui/quit_panel.tscn"
## A real resource that is not a scene: the worker round-trips cleanly and
## the error card still shows, with no engine error spam in the log.
const NON_SCENE_PATH: String = "res://icon.svg"

const STATES: Array[String] = [
	"logged_out", "busy", "error", "ready", "ready_no_save", "loading",
	"loading_error", "loading_cancelled", "hall", "hall_single",
	"hall_many", "hall_empty", "conflict", "account", "exit", "lineup",
	"unready", "terms",
]
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const FRAMINGS: Array[Vector2i] = [
	Vector2i(808, 360), Vector2i(840, 360), Vector2i(808, 606)]
const SETTLE_SECONDS: float = 0.6
const LOAD_TIMEOUT_SECONDS: float = 15.0

const TEST_SAVED_TITLE: String = "TEST Gate 3 · Cycle 2"
const TEST_SAVED_DETAIL: String = "TEST saved at the third gate"
const TEST_ERROR_DETAIL: String = "TEST sign-in failed: network unreachable"
const TEST_PROVIDERS: Array = [
	{"id": "google", "label": "Google", "ready": true},
	{"id": "apple", "label": "Apple", "ready": true},
]
## Real unavailable-provider shape: one ready, one down, one draining.
const TEST_PROVIDERS_UNREADY: Array = [
	{"id": "google", "label": "Google", "ready": true},
	{"id": "apple", "label": "Apple", "ready": false},
	{"id": "passkey", "label": "Passkey", "ready": true, "draining": true},
]

var _failed: int = 0
var _checked: int = 0


## Windowed-stand-in host for `prod=1 capable=1` shots only. It never
## touches real services; every capable run prints a FIXTURE banner.
class StubShotHost extends Node:
	signal production_changed(state: Dictionary)
	signal production_conflict(local: Dictionary, cloud: Dictionary)
	signal production_error(error: Dictionary)

	var _capable: bool = false

	func _init(capable: bool = false) -> void:
		_capable = capable

	func startup() -> void:
		pass

	func providers_for_entry() -> Array:
		if not _capable:
			return []
		return [
			{"id": "google", "label": "Google", "ready": true},
			{"id": "apple", "label": "Apple", "ready": true},
		]

	func identity_for_entry() -> Dictionary:
		return {"stable_id": ""}

	func account_state() -> Dictionary:
		return {"offline": false}

	func saved_gate_summary() -> Dictionary:
		return {"has_save": false}

	func provider_label(provider_id: String) -> String:
		return provider_id

	func note_first_paint() -> void:
		pass


func _ready() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if args.has("validate"):
		await _run_validate()
		if _failed > 0:
			printerr("shot-gate-entry validate failed — ",
				_failed, "/", _checked, " case(s)")
			get_tree().quit(1)
			return
		print("shot-gate-entry validate passed — ", _checked, " case(s)")
		get_tree().quit(0)
		return
	if args.has("prod"):
		await _run_prod(args)
		return
	var state: String = str(args.get("state", "logged_out"))
	var locale: String = str(args.get("locale", "ko"))
	var width: int = int(args.get("width", 808))
	var height: int = int(args.get("height", 360))
	TranslationServer.set_locale(locale)
	get_window().size = Vector2i(width, height)
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	if bool(args.get("reduced_motion", false)):
		entry.set_reduced_motion(true)
	await get_tree().process_frame
	await get_tree().process_frame
	await _apply_state(entry, state)
	if args.has("shot"):
		# Loading states photograph mid-flight; the rest settle first.
		# Process frames, not frame_post_draw: headless runs never emit
		# the draw signal and would hang here. Real pixels still need a
		# windowed run; headless only proves the plumbing.
		if state == "loading":
			await get_tree().process_frame
		else:
			await get_tree().create_timer(SETTLE_SECONDS).timeout
		await _save_shot(str(args["shot"]))
		if state == "loading" or state == "loading_cancelled":
			await _drain_path(ARENA_PATH)
		get_tree().quit(0)


## Windowed production shots: the real entry scene, the real host by
## default (`capable=1` swaps in the TEST stub and prints FIXTURE).
## `state=selection` taps the title first; `state=terms` taps, then
## opens the Terms sheet over the selection.
func _run_prod(args: Dictionary) -> void:
	var state: String = str(args.get("state", "title"))
	var locale: String = str(args.get("locale", "ko"))
	var width: int = int(args.get("width", 808))
	var height: int = int(args.get("height", 360))
	var capable: bool = args.has("capable")
	if capable:
		print("shot-gate-entry: FIXTURE host — TEST providers, "
			+ "never the production truth")
	TranslationServer.set_locale(locale)
	get_window().size = Vector2i(width, height)
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub: StubShotHost = null
	if capable:
		stub = StubShotHost.new(true)
		add_child(stub)
		production.set_host_override(stub)
	add_child(production)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if state in ["selection", "terms"]:
		var title: Variant = production.get_node("Title")
		title.request_start()
		await get_tree().process_frame
		await get_tree().process_frame
		if state == "terms":
			(production.get_node("Gate") as GateEntry).open_terms()
			await get_tree().process_frame
			await get_tree().process_frame
	if args.has("shot"):
		await get_tree().create_timer(SETTLE_SECONDS).timeout
		await _save_shot(str(args["shot"]))
		get_tree().quit(0)


func _save_shot(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("shot-gate-entry: shot= needs a windowed run "
			+ "for real pixels; use validate headless")
		get_tree().quit(2)
		return
	var shot: Image = get_viewport().get_texture().get_image()
	var err: Error = shot.save_png(path)
	if err != OK:
		printerr("shot-gate-entry: could not save ", path)
		get_tree().quit(1)
		return
	print("shot-gate-entry: saved ", path)


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for token in raw:
		if token == "validate":
			out["validate"] = true
		elif token.contains("="):
			var parts: PackedStringArray = token.split("=", true, 2)
			if parts[0] == "reduced_motion":
				out["reduced_motion"] = parts[1] not in ["0", "false", ""]
			else:
				out[parts[0]] = parts[1]
	return out


## Drive one entry surface into the named showcase state with TEST data.
func _apply_state(entry: GateEntry, state: String) -> void:
	entry.set_providers(TEST_PROVIDERS)
	match state:
		"busy":
			entry.show_busy("google", "Google")
		"error":
			entry.show_busy("google", "Google")
			entry.show_error(TEST_ERROR_DETAIL)
		"ready", "loading", "loading_error", "loading_cancelled":
			entry.show_identity(_test_identity(), _test_saved_gate(true))
			if state == "loading":
				entry.load_scene(ARENA_PATH, "TEST entering the arena")
			elif state == "loading_error":
				entry.load_scene(NON_SCENE_PATH, "TEST entering nowhere")
				await _settle_loader(entry)
			elif state == "loading_cancelled":
				entry.load_scene(ARENA_PATH, "TEST entering the arena")
				await get_tree().process_frame
				await get_tree().process_frame
				entry.cancel_loading()
		"ready_no_save":
			entry.show_identity(_test_identity(), {"has_save": false})
		"hall":
			entry.show_identity(_test_identity(), _test_saved_gate(true))
			entry.open_hall(_test_hall_rows(),
				{"cached": true, "offline": true})
		"hall_single":
			entry.open_hall(_test_hall_single(), {})
		"hall_many":
			entry.open_hall(_test_hall_many(100),
				{"cached": true, "offline": true})
		"hall_empty":
			entry.open_hall([], {})
		"conflict":
			entry.open_conflict(
				{"title": "TEST local gate 3",
					"detail": "TEST 12 beacons",
					"updated": "TEST today 21:40"},
				{"title": "TEST cloud gate 5",
					"detail": "TEST 20 beacons",
					"updated": "TEST yesterday"})
		"account":
			entry.show_identity(_test_identity(), _test_saved_gate(true))
			entry.open_account(_test_account())
		"exit":
			entry.open_exit()
		"lineup":
			entry.show_identity(_test_identity(), _test_saved_gate(true))
		"unready":
			entry.set_providers(TEST_PROVIDERS_UNREADY)
			entry.show_logged_out()
		"terms":
			entry.show_logged_out()
			entry.open_terms()
		_:
			entry.show_logged_out()


## Actual-shape stable ID: `MB-` plus a zero-padded body, 35 characters.
func _long_id(index: int) -> String:
	return "MB-%032d" % index


func _test_identity() -> Dictionary:
	return {
		"stable_id": _long_id(711),
		"hero": load(KNIGHT_PATH) as Hero,
	}


func _test_saved_gate(has_save: bool) -> Dictionary:
	return {
		"has_save": has_save,
		"title": TEST_SAVED_TITLE if has_save else "",
		"detail": TEST_SAVED_DETAIL if has_save else "",
	}


func _test_account() -> Dictionary:
	return {
		"stable_id": _long_id(712),
		"hero": load(KNIGHT_PATH) as Hero,
		"provider_label": "Google",
		"saved_title": TEST_SAVED_TITLE,
		"saved_detail": TEST_SAVED_DETAIL,
		"analytics_opt_in": false,
		"show_links": true,
	}


func _test_hall_rows() -> Array:
	var knight: Hero = load(KNIGHT_PATH) as Hero
	var sage: Hero = load(SAGE_PATH) as Hero
	return [
		{"rank": 1, "score": 12345, "id": _long_id(1), "hero": knight},
		{"rank": 2, "score": 9870, "id": _long_id(2), "hero": sage},
		{"rank": 3, "score": 8015, "id": _long_id(3),
			"portrait": knight.portrait, "hero_name": "TEST Traveler"},
	]


func _test_hall_single() -> Array:
	return [
		{"rank": 1, "score": 12345, "id": _long_id(4),
			"hero": load(KNIGHT_PATH) as Hero},
	]


func _test_hall_many(count: int) -> Array:
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


func _settle_loader(entry: GateEntry) -> void:
	var loader: GateLoadingOverlay = entry.get_loader()
	var waited: float = 0.0
	while (loader.is_loading() or loader.has_pending_drain()) \
			and waited < LOAD_TIMEOUT_SECONDS:
		await get_tree().process_frame
		waited += get_process_delta_time()


## Wait until the worker drops this path, bounded by wall time. A load the
## overlay cancelled or stopped watching still occupies the worker; the
## tree must not quit under it.
func _drain_path(path: String) -> void:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < LOAD_TIMEOUT_SECONDS * 1000:
		var status: ResourceLoader.ThreadLoadStatus = \
			ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED \
				or status == ResourceLoader.THREAD_LOAD_FAILED \
				or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return
		await get_tree().create_timer(0.05).timeout


## Headless invariant sweep: every render state x locale x framing, plus
## signal smoke and a loader smoke. Prints the motion/node budgets too.
func _run_validate() -> void:
	_warm_worker_paths()
	var original_locale: String = TranslationServer.get_locale()
	var original_size: Vector2i = get_tree().root.size
	for framing in FRAMINGS:
		get_tree().root.size = framing
		for locale in LOCALES:
			TranslationServer.set_locale(locale)
			for state in ["logged_out", "ready", "hall", "hall_single",
					"hall_many", "conflict", "account", "exit", "lineup"]:
				await _validate_render(state, locale, framing)
	for extra in ["busy", "error", "loading", "loading_error",
			"loading_cancelled", "ready_no_save", "hall_empty", "unready",
			"terms"]:
		TranslationServer.set_locale("ko")
		await _validate_render(extra, "ko", Vector2i(808, 360))
	TranslationServer.set_locale(original_locale)
	get_tree().root.size = original_size
	await _validate_signals()
	await _validate_loader_smoke()
	await _drain_path(ARENA_PATH)
	await _print_budgets()


## Sync-load every path validate worker-loads. Cold worker loads leak a
## few engine-side temporaries per script (proven with raw API calls and no
## overlay code); warming keeps validate output free of engine warnings.
## Windowed single-state runs stay cold on purpose: a real loading veil
## screenshot needs a real cold load, and its exit warning is cosmetic.
func _warm_worker_paths() -> void:
	for path in [ARENA_PATH, SMALL_SCENE_PATH, NON_SCENE_PATH]:
		var warmed: Resource = load(path) as Resource
		if warmed == null:
			printerr("shot-gate-entry warmup failed for ", path)


func _validate_render(state: String, locale: String, framing: Vector2i) -> void:
	var tag: String = "%s/%s/%dx%d" % [
		state, locale, framing.x, framing.y]
	get_tree().root.size = framing
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	await get_tree().process_frame
	await get_tree().process_frame
	await _apply_state(entry, state)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_entry_invariants(entry, tag)
	if state == "loading" or state == "loading_cancelled":
		# The worker keeps the arena load after the overlay stops
		# watching it. Drain it before freeing: quitting mid-load
		# tears the worker down with engine errors.
		await _drain_path(ARENA_PATH)
		_expect_true(not entry.get_loader().has_pending_drain(),
			"%s: orphan drain completes" % tag)
	entry.queue_free()
	await get_tree().process_frame


func _check_entry_invariants(entry: GateEntry, tag: String) -> void:
	var viewport: Rect2 = Rect2(
		Vector2.ZERO, get_tree().root.size)
	var buttons: Array = []
	_collect(entry, buttons, "Button")
	var labels: Array = []
	_collect(entry, labels, "Label")
	var fields: Array = []
	_collect(entry, fields, "LineEdit")
	var consents: Array = []
	_collect(entry, consents, "RichTextLabel")
	for raw_button in buttons:
		var button: Button = raw_button as Button
		if not button.is_visible_in_tree():
			continue
		var rect: Rect2 = button.get_global_rect()
		_expect_true(viewport.encloses(rect.grow(-0.5)),
			"%s: button %s inside %s" % [tag, button.name, rect])
		_expect_true(rect.size.x >= 44.0 and rect.size.y >= 36.0,
			"%s: button %s touch size %s" % [tag, button.name, rect.size])
		# The official doors carry vendor type on their Title labels,
		# not on the Button itself; every label still needs its face.
		if not _is_official_door(button):
			_expect_true(button.has_theme_font_override("font"),
				"%s: button %s styled font" % [tag, button.name])
		_expect_no_raw_key(button.text, "%s: button %s" % [tag, button.name])
		var card: PanelContainer = _owning_card(button, entry)
		if card != null:
			_expect_true(
				card.get_global_rect().grow(-1.0).encloses(
					rect.grow(-0.5)),
				"%s: button %s inside its card" % [tag, button.name])
	for index in buttons.size():
		var first: Button = buttons[index] as Button
		if not first.is_visible_in_tree():
			continue
		for other in range(index + 1, buttons.size()):
			var second: Button = buttons[other] as Button
			if not second.is_visible_in_tree():
				continue
			# Buttons in different dialogs never show together; only
			# siblings on one surface must not overlap.
			if _dialog_root(first) != _dialog_root(second):
				continue
			var overlap: bool = first.get_global_rect().grow(-1.0) \
				.intersects(second.get_global_rect().grow(-1.0))
			_expect_true(not overlap,
				"%s: buttons %s and %s do not overlap" % [
					tag, first.name, second.name])
	for raw_label in labels:
		var label: Label = raw_label as Label
		if not label.is_visible_in_tree():
			continue
		_expect_true(label.has_theme_font_override("font"),
			"%s: label %s styled font" % [tag, label.name])
		_expect_no_raw_key(label.text, "%s: label %s" % [tag, label.name])
	for raw_field in fields:
		var field: LineEdit = raw_field as LineEdit
		if not field.is_visible_in_tree():
			continue
		_expect_true(viewport.encloses(field.get_global_rect().grow(-0.5)),
			"%s: id field inside" % tag)
	for raw_consent in consents:
		var rich: RichTextLabel = raw_consent as RichTextLabel
		if not rich.is_visible_in_tree():
			continue
		_expect_true(rich.has_theme_font_override("normal_font"),
			"%s: consent %s styled font" % [tag, rich.name])
		_expect_true(rich.text.contains("[url=tos]") \
			and rich.text.contains("[url=privacy]"),
			"%s: consent %s carries both links" % [tag, rich.name])
		_expect_true(not rich.get_parsed_text().contains("%s"),
			"%s: consent %s formats its sentence" % [tag, rich.name])
		_expect_true(viewport.encloses(
			rich.get_global_rect().grow(-0.5)),
			"%s: consent %s inside" % [tag, rich.name])
		var consent_card: PanelContainer = _owning_card(rich, entry)
		if consent_card != null:
			_expect_true(
				consent_card.get_global_rect().grow(-1.0).encloses(
					rich.get_global_rect().grow(-0.5)),
				"%s: consent %s inside its card" % [tag, rich.name])
	var forecourt: GateHeroForecourt = entry.get_forecourt()
	_expect_true(forecourt.actor_count() == 6,
		"%s: six heroes in the forecourt" % tag)
	for hero_index in forecourt.actor_count():
		var paint_rect: Rect2 = forecourt.paint_global_rect(hero_index)
		_expect_true(viewport.encloses(paint_rect.grow(-0.5)),
			"%s: hero %d paint inside %s" % [tag, hero_index, paint_rect])


func _expect_no_raw_key(text_value: String, where: String) -> void:
	if not text_value.begins_with("gate."):
		_checked += 1
		return
	_expect_true(tr(text_value) != text_value,
		"%s shows resolved text, not %s" % [where, text_value])


func _validate_signals() -> void:
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	await get_tree().process_frame
	await get_tree().process_frame
	var fired: Dictionary = {}
	var watch := func(key: String) -> Callable:
		return func(_a: Variant = null, _b: Variant = null,
				_c: Variant = null) -> void:
			fired[key] = true
	entry.provider_login_requested.connect(watch.call("provider"))
	entry.guest_requested.connect(watch.call("guest"))
	entry.start_requested.connect(watch.call("start"))
	entry.resume_requested.connect(watch.call("resume"))
	entry.hall_requested.connect(watch.call("hall"))
	entry.chronicle_requested.connect(watch.call("chronicle"))
	entry.heroes_requested.connect(watch.call("heroes"))
	entry.shop_requested.connect(watch.call("shop"))
	entry.settings_requested.connect(watch.call("settings"))
	entry.set_providers(TEST_PROVIDERS)
	(entry.get_node("Content/StatusCard/LoggedOut/Providers").get_child(0) \
		as Button).pressed.emit()
	(entry.get_node("Content/StatusCard/LoggedOut/Guest") as Button) \
		.pressed.emit()
	# No gate menu bar: the routing contract smokes by direct emission
	# while the title's original buttons are the real doors.
	entry.hall_requested.emit()
	entry.chronicle_requested.emit()
	entry.heroes_requested.emit()
	entry.shop_requested.emit()
	entry.settings_requested.emit()
	entry.show_identity(_test_identity(), _test_saved_gate(true))
	await get_tree().process_frame
	(entry.get_node("Content/StatusCard/Ready/StartRow/Resume") as Button) \
		.pressed.emit()
	(entry.get_node("Content/StatusCard/Ready/StartRow/Start") as Button) \
		.pressed.emit()
	for key in ["provider", "guest", "start", "resume", "hall",
			"chronicle", "heroes", "shop", "settings"]:
		_expect_true(bool(fired.get(key, false)),
			"signal smoke: %s fires" % key)
	_expect_true(entry.get_music_intent() == &"stop",
		"signal smoke: start flips music intent to stop")
	entry.queue_free()
	await get_tree().process_frame


func _validate_loader_smoke() -> void:
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	await get_tree().process_frame
	await get_tree().process_frame
	var loader: GateLoadingOverlay = entry.get_loader()
	var finished: Array = []
	var failed: Array = []
	loader.finished.connect(
		func(path: String, _packed: PackedScene, _token: int) -> void:
			finished.append(path))
	loader.failed.connect(
		func(path: String, _message: String, _token: int) -> void:
			failed.append(path))
	loader.begin(SMALL_SCENE_PATH, "TEST smoke")
	await get_tree().process_frame
	_expect_true(loader.visible and not loader.is_request_issued(),
		"loader smoke: first paint lands before the request")
	await _settle_loader(entry)
	_expect_true(finished == [SMALL_SCENE_PATH],
		"loader smoke: small scene finishes")
	loader.begin(NON_SCENE_PATH, "TEST smoke")
	await _settle_loader(entry)
	_expect_true(failed == [NON_SCENE_PATH],
		"loader smoke: missing path fails honestly")
	_expect_true(loader.is_showing_error(),
		"loader smoke: error card offers retry/return")
	entry.queue_free()
	await get_tree().process_frame


func _print_budgets() -> void:
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	await get_tree().process_frame
	await get_tree().process_frame
	var total: int = _count_nodes(entry)
	print("budgets: entry nodes=%d dust=%d drift=8x5px/16s+13s glows=2 mists=2" % [
		total, GateEntry.DUST_COUNT])
	var art: FileAccess = FileAccess.open(
		"res://assets/gate/moon_gate_title.png", FileAccess.READ)
	if art != null:
		print("budgets: moon_gate_title.png bytes=%d" % art.get_length())
		art.close()
	entry.queue_free()
	await get_tree().process_frame


func _count_nodes(node: Node) -> int:
	var total: int = 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


func _collect(node: Node, out: Array, type_name: String) -> void:
	if node.get_class() == type_name:
		out.append(node)
	for child in node.get_children():
		_collect(child, out, type_name)


## Official provider doors compose vendor type on Title labels, so the
## generic Button font-face check does not apply to them.
func _is_official_door(button: Button) -> bool:
	var parent: Node = button.get_parent()
	if parent == null or parent.name != "Providers":
		return false
	return button.name == "ProviderGoogle" \
		or button.name == "ProviderApple"


## Which top-level dialog (or the base surface) owns this control.
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
