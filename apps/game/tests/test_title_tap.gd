extends Node

## Title tap regression: the original title opens the centered login
## chooser on a real pointer tap, and its own menus keep their clicks.
##
## Boots the real production entry (original Title plus decorative
## six-hero Gate) behind a logged-out stub host. Four layers:
##
## 1. Structural pins, every run: the decorative full-screen hosts stay
##    IGNORE while real buttons stay STOP, and no STOP control covers
##    the tap point at rest. These fail deterministically headless when
##    the scene regresses.
## 2. Deferred-open unit, every run: a pointer press plays feedback
##    but emits no open until its own release (wrong releases ignored),
##    while a key start emits at once. Direct `request_start`/`_input`
##    calls prove emission timing only — never tap reception; the
##    windowed layer proves the end-to-end path.
## 3. Delayed Hall ownership, every run: direct handler state checks
##    against a held stub `request_hall`. Pending Back dismisses the
##    owned intent and restores the title with no exit question, so a
##    late response opens nothing over Settings; a superseded older
##    response never replaces a newer board; a fresh request after a
##    dismiss still works; ordinary open/close and visible-Back
##    behavior are unchanged; teardown drops the late reply safely.
##    Handler state only — the windowed layer proves pointer travel.
## 4. Real pointer routing, windowed runs only: actual mouse
##    press/release and touch press/release through Input/Viewport
##    dispatch — never `request_start`, `_unhandled_input`, or
##    `pressed.emit` as proof. The realistic mixed history runs in
##    order: mouse tap, explicit Terms and Privacy link taps, Back,
##    Settings round-trip, Shop round-trip, touch tap, then Guest,
##    then a ladder-door Hall round-trip by pointer.
##    Each opening tap must open ONLY the chooser: Terms, Privacy,
##    Ready and the loader stay shut, provider calls stay zero, and
##    exactly one transition fires per gesture.
##
## Headless cannot guard the routing half. There is no OS window and no
## native pointer path: hover tracking is dead (`gui_get_hovered_control`
## stays null), and injected-event dispatch disagrees across
## environments about whether it even reproduces pointer failures (a
## probe passed headless where the same click failed windowed). A
## headless green therefore proves nothing about real taps, so the
## routing steps run only with a real window. Run windowed on a display:
## `pnpm godot:isolated --windowed res://tests/test_title_tap.tscn`

const PRODUCTION_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")
const ARENA_PATH: String = "res://scenes/gameplay/arena.tscn"

var _failed: int = 0
var _checked: int = 0


## Logged-out choice with no providers behind the booted production
## entry. Records every begin call so a stray dispatch fails loudly
## instead of erroring on a missing method.
class StubTapHost extends Node:
	signal production_changed(state: Dictionary)
	signal production_conflict(local: Dictionary, cloud: Dictionary)
	signal production_error(error: Dictionary)
	signal hall_released(ticket: int)

	var begin_calls: Array = []
	var hall_calls: int = 0
	var hall_results: Dictionary = {}

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

	func provider_label(provider_id: String) -> String:
		return provider_id

	func begin_provider(provider_id: String) -> Dictionary:
		begin_calls.append({"kind": "provider", "id": provider_id})
		return {}

	func begin_guest(_local_only: bool = false) -> Dictionary:
		begin_calls.append({"kind": "guest"})
		return {}

	func is_login_pending() -> bool:
		return false

	func note_first_paint() -> void:
		pass

	## Held Hall fetch: each call waits for its own ticket, so the
	## test releases responses late and out of order on purpose.
	func request_hall(_limit: int = 20) -> Dictionary:
		hall_calls += 1
		var ticket: int = hall_calls
		while not hall_results.has(ticket):
			await hall_released
		return hall_results[ticket]

	func release_hall(ticket: int, view: Dictionary) -> void:
		hall_results[ticket] = view
		hall_released.emit(ticket)


func _ready() -> void:
	get_tree().root.size = Vector2i(808, 360)
	_run.call_deferred()


func _run() -> void:
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubTapHost.new()
	add_child(stub)
	production.set_host_override(stub)
	add_child(production)
	await _frames(4)
	_check_first_paint(production)
	_check_hit_pins(production)
	await _check_deferred_open_unit()
	await _check_hall_pending_back()
	await _check_hall_supersede()
	await _check_hall_fresh_after_dismiss()
	await _check_hall_ordinary()
	await _check_hall_teardown()
	if DisplayServer.get_name() == "headless":
		print("title-tap: no window here; routing steps skipped — ",
			"run --windowed on a display for real pointer proof")
	else:
		await _check_windowed_routing(production, stub)
	production.queue_free()
	stub.queue_free()
	await _frames(2)
	if _failed > 0:
		printerr("title-tap test failed — ",
			_failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("title-tap test passed — ", _checked, " case(s)")
	get_tree().quit(0)


## First paint is the original title at rest over the real Gate: prompt
## and doors showing, six heroes standing, card parked, tap armed.
func _check_first_paint(production: ProductionEntry) -> void:
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	_expect_true(bool(title.is_external_start()),
		"first: production parks the title in external mode")
	_expect_true((title.get_node("Ui/Screen") as Control).visible,
		"first: title screen shows")
	_expect_true((title.get_node("Ui/Screen/TapPrompt") as Control
		).is_visible_in_tree(), "first: tap prompt shows")
	_expect_true(gate.get_forecourt().actor_count() == 6,
		"first: six heroes over the title")
	_expect_true(gate.is_title_rest(),
		"first: gate card parked for the title")
	_expect_true(not gate.is_selection_open(),
		"first: no selection on first paint")
	_expect_true(bool(title.get("_accepting")),
		"first: tap armed")
	_expect_no_arena("first")


## Hit-testing ownership: decorative full-screen hosts never stop
## input; only the scrim (hidden at rest) and real buttons do. Runs
## everywhere, so a scene regression fails even headless.
func _check_hit_pins(production: ProductionEntry) -> void:
	var title: Control = production.get_node("Title") as Control
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	_expect_true(production.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"pins: production root lets taps through")
	_expect_true(title.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"pins: title root keeps its original pass-through")
	_expect_true((title.get_node("Ui/Screen") as Control).mouse_filter \
			== Control.MOUSE_FILTER_IGNORE,
		"pins: title screen keeps its original pass-through")
	_expect_true(gate.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"pins: gate root keeps its original pass-through")
	_expect_true(gate.get_forecourt().mouse_filter \
			== Control.MOUSE_FILTER_IGNORE,
		"pins: hero forecourt never takes taps")
	_expect_true(not (gate.get_node("Content/Scrim") as Control
		).is_visible_in_tree(), "pins: no scrim over the title at rest")
	_expect_true(not (gate.get_node("Content/StatusCard") as Control
		).is_visible_in_tree(), "pins: no auth card at rest")
	var settings_button: Button = title.get_node(
		"Ui/Screen/SettingsButton") as Button
	_expect_true(settings_button.mouse_filter == Control.MOUSE_FILTER_STOP \
			and settings_button.is_visible_in_tree(),
		"pins: original menu doors keep their hitbox")
	var tap_point: Vector2 = _tap_point(title)
	_expect_true(_stops_at(production, tap_point).is_empty(),
		"pins: no STOP control covers the background tap point")


## Deferred-open semantics on fresh boots: a pointer press spends the
## arm and plays feedback but opens nothing until its own release; a
## key start emits at once. Emission timing only — the windowed layer
## proves real taps travel the native path.
func _check_deferred_open_unit() -> void:
	await _check_deferred_mouse_pair()
	await _check_deferred_touch_pair()
	await _check_deferred_key_immediate()


func _check_deferred_mouse_pair() -> void:
	var booted: Array = await _boot_production()
	var production: ProductionEntry = booted[0]
	var stub: StubTapHost = booted[1]
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var emits: Array = []
	title.external_start_requested.connect(
		func() -> void: emits.append(1))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	title.request_start(press)
	await _frames(2)
	_expect_true(emits.is_empty(),
		"defer: mouse press opens nothing yet")
	_expect_true(gate.is_title_rest() and not gate.is_selection_open(),
		"defer: card stays parked on mouse press")
	_expect_true(not bool(title.get("_accepting")),
		"defer: mouse press spends the one-shot arm")
	var wrong := InputEventMouseButton.new()
	wrong.button_index = MOUSE_BUTTON_RIGHT
	wrong.pressed = false
	title._input(wrong)
	await _frames(2)
	_expect_true(emits.is_empty(),
		"defer: another button's release opens nothing")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	title._input(release)
	await _frames(2)
	_expect_true(emits.size() == 1,
		"defer: mouse release opens exactly once")
	_expect_true(gate.is_selection_open(),
		"defer: mouse release shows the selection")
	await _free_production(production, stub)


func _check_deferred_touch_pair() -> void:
	var booted: Array = await _boot_production()
	var production: ProductionEntry = booted[0]
	var stub: StubTapHost = booted[1]
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var emits: Array = []
	title.external_start_requested.connect(
		func() -> void: emits.append(1))
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	title.request_start(press)
	await _frames(2)
	_expect_true(emits.is_empty(),
		"defer: touch press opens nothing yet")
	_expect_true(gate.is_title_rest() and not gate.is_selection_open(),
		"defer: card stays parked on touch press")
	var wrong := InputEventScreenTouch.new()
	wrong.index = 1
	wrong.pressed = false
	title._input(wrong)
	await _frames(2)
	_expect_true(emits.is_empty(),
		"defer: another finger's release opens nothing")
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	title._input(release)
	await _frames(2)
	_expect_true(emits.size() == 1,
		"defer: touch release opens exactly once")
	_expect_true(gate.is_selection_open(),
		"defer: touch release shows the selection")
	await _free_production(production, stub)


func _check_deferred_key_immediate() -> void:
	var booted: Array = await _boot_production()
	var production: ProductionEntry = booted[0]
	var stub: StubTapHost = booted[1]
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var emits: Array = []
	title.external_start_requested.connect(
		func() -> void: emits.append(1))
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	title.request_start(key)
	await _frames(2)
	_expect_true(emits.size() == 1,
		"defer: key start emits at once, never parked")
	_expect_true(gate.is_selection_open(),
		"defer: key start shows the selection")
	await _free_production(production, stub)


## Pending Back dismisses the owned Hall intent and restores the
## original title with no exit question; a late response then opens
## nothing over Settings. Direct handler state checks, every run.
func _check_hall_pending_back() -> void:
	var booted: Array = await _boot_production()
	var production: ProductionEntry = booted[0]
	var stub: StubTapHost = booted[1]
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var panel: GateHallPanel = _hall_panel(gate)
	var screen: Control = title.get_node("Ui/Screen") as Control
	(title.get_node("Ui/Screen/LadderButton") as Button).pressed.emit()
	await _frames(3)
	_expect_true(stub.hall_calls == 1,
		"hall-race: ladder tap starts one request")
	_expect_true(not panel.visible,
		"hall-race: held response shows no Hall yet")
	_expect_true(not screen.visible,
		"hall-race: title parks while the Hall loads")
	production._on_back()
	await _frames(2)
	_expect_true(not (gate.get_node("GateExitPanel") as Control).visible,
		"hall-race: pending Back asks no exit")
	_expect_true(screen.visible,
		"hall-race: pending Back restores the title")
	_expect_true(bool(title.get("_accepting")),
		"hall-race: pending Back re-arms the tap")
	title.open_settings()
	await _frames(2)
	_expect_true((title.get_node("Ui/Settings") as Control
		).is_visible_in_tree(), "hall-race: settings opens normally")
	stub.release_hall(1, _hall_view(100, "MB-" + "a".repeat(32)))
	await _frames(3)
	_expect_true(not panel.visible,
		"hall-race: late result opens no Hall")
	_expect_true((title.get_node("Ui/Settings") as Control).visible,
		"hall-race: late result leaves Settings up")
	_expect_true(stub.begin_calls.is_empty(),
		"hall-race: no login begun")
	await _free_production(production, stub)


## A newer request supersedes the older one: out-of-order results
## keep the newer board and the stale reply replaces nothing.
func _check_hall_supersede() -> void:
	var booted: Array = await _boot_production()
	var production: ProductionEntry = booted[0]
	var stub: StubTapHost = booted[1]
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var panel: GateHallPanel = _hall_panel(gate)
	var ladder: Button = title.get_node(
		"Ui/Screen/LadderButton") as Button
	ladder.pressed.emit()
	await _frames(3)
	# A second request while the first is still held (a re-tap or the
	# gate card's own Hall door): same ownership path, newer intent.
	ladder.pressed.emit()
	await _frames(3)
	_expect_true(stub.hall_calls == 2,
		"hall-order: second tap starts a newer request")
	var new_id: String = "MB-" + "b".repeat(32)
	stub.release_hall(2, _hall_view(9000, new_id))
	await _frames(3)
	_expect_true(panel.visible,
		"hall-order: newer result opens the Hall")
	_expect_true(_hall_headline(panel) == "#1 · 9000",
		"hall-order: newer result shows its score")
	_expect_true(_hall_first_id(panel) == new_id,
		"hall-order: newer result shows its id")
	stub.release_hall(1, _hall_view(100, "MB-" + "a".repeat(32)))
	await _frames(3)
	_expect_true(panel.visible,
		"hall-order: stale result closes nothing")
	_expect_true(panel.row_count() == 1,
		"hall-order: stale result adds no rows")
	_expect_true(_hall_headline(panel) == "#1 · 9000",
		"hall-order: stale result replaces no score")
	_expect_true(_hall_first_id(panel) == new_id,
		"hall-order: stale result replaces no id")
	_expect_true(stub.begin_calls.is_empty(),
		"hall-order: no login begun")
	await _free_production(production, stub)


## A fresh request after a dismiss still works, and the dismissed
## response cannot replace its board when it lands late.
func _check_hall_fresh_after_dismiss() -> void:
	var booted: Array = await _boot_production()
	var production: ProductionEntry = booted[0]
	var stub: StubTapHost = booted[1]
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var panel: GateHallPanel = _hall_panel(gate)
	var ladder: Button = title.get_node(
		"Ui/Screen/LadderButton") as Button
	ladder.pressed.emit()
	await _frames(3)
	production._on_back()
	await _frames(2)
	ladder.pressed.emit()
	await _frames(3)
	_expect_true(stub.hall_calls == 2,
		"hall-fresh: ladder works again after a dismiss")
	var fresh_id: String = "MB-" + "c".repeat(32)
	stub.release_hall(2, _hall_view(500, fresh_id))
	await _frames(3)
	_expect_true(panel.visible,
		"hall-fresh: fresh result opens the Hall")
	stub.release_hall(1, _hall_view(100, "MB-" + "a".repeat(32)))
	await _frames(3)
	_expect_true(_hall_headline(panel) == "#1 · 500",
		"hall-fresh: dismissed result replaces no score")
	_expect_true(_hall_first_id(panel) == fresh_id,
		"hall-fresh: dismissed result replaces no id")
	await _free_production(production, stub)


## Ordinary Hall behavior is unchanged: the current request opens
## over the parked title, Close restores it, and Back while the
## board is visible closes it instead of asking exit.
func _check_hall_ordinary() -> void:
	var booted: Array = await _boot_production()
	var production: ProductionEntry = booted[0]
	var stub: StubTapHost = booted[1]
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var panel: GateHallPanel = _hall_panel(gate)
	var screen: Control = title.get_node("Ui/Screen") as Control
	var ladder: Button = title.get_node(
		"Ui/Screen/LadderButton") as Button
	ladder.pressed.emit()
	stub.release_hall(1, _hall_view(9000, "MB-" + "d".repeat(32)))
	await _frames(3)
	_expect_true(panel.visible,
		"hall-plain: current result opens the Hall")
	_expect_true(panel.row_count() == 1,
		"hall-plain: supplied rows render")
	_expect_true(not screen.visible,
		"hall-plain: title doors parked under the Hall")
	_expect_true(gate.is_title_rest()
		and not gate.is_selection_open(),
		"hall-plain: no login card forced")
	(panel.get_node("Card/Stack/Close") as Button).pressed.emit()
	await _frames(2)
	_expect_true(not panel.visible,
		"hall-plain: Close shuts the Hall")
	_expect_true(screen.visible,
		"hall-plain: Close restores the doors")
	_expect_true(bool(title.get("_accepting")),
		"hall-plain: Close re-arms the tap")
	_expect_true(gate.is_title_rest(),
		"hall-plain: Close returns to title rest")
	ladder.pressed.emit()
	stub.release_hall(2, _hall_view(7000, "MB-" + "e".repeat(32)))
	await _frames(3)
	production._on_back()
	await _frames(2)
	_expect_true(not panel.visible,
		"hall-plain: visible Back closes the Hall")
	_expect_true(screen.visible
		and bool(title.get("_accepting")),
		"hall-plain: visible Back restores the title")
	_expect_true(not (gate.get_node("GateExitPanel") as Control).visible,
		"hall-plain: visible Back asks no exit")
	_expect_true(stub.begin_calls.is_empty(),
		"hall-plain: no login begun")
	await _free_production(production, stub)


## Teardown drops the late reply: detached from the tree, the held
## response lands nowhere and opens nothing.
func _check_hall_teardown() -> void:
	var booted: Array = await _boot_production()
	var production: ProductionEntry = booted[0]
	var stub: StubTapHost = booted[1]
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var panel: GateHallPanel = _hall_panel(gate)
	(production.get_node("Title/Ui/Screen/LadderButton") as Button
		).pressed.emit()
	await _frames(3)
	_expect_true(stub.hall_calls == 1,
		"hall-teardown: request held before teardown")
	remove_child(production)
	await _frames(2)
	stub.release_hall(1, _hall_view(100, "MB-" + "a".repeat(32)))
	await _frames(3)
	_expect_true(not panel.visible,
		"hall-teardown: late reply opens no Hall")
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## Windowed real-pointer proof in the realistic mixed order. Every step
## travels the native Input/Viewport path, and every opening gesture
## must open ONLY the chooser — Terms, Privacy, Ready and the loader
## stay shut, provider calls stay zero, Guest answers the next tap.
func _check_windowed_routing(
	production: ProductionEntry, stub: StubTapHost
) -> void:
	_expect_true(get_tree().root.size == Vector2i(808, 360),
		"route: window holds 808x360 so tap points land 1:1")
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var emits: Array = []
	title.external_start_requested.connect(
		func() -> void: emits.append(1))
	var links: Array = []
	gate.external_link_requested.connect(
		func(url: String) -> void: links.append(url))
	# Opening mouse tap on the natural prompt: only the chooser.
	var tap_point: Vector2 = _tap_point(title)
	_expect_true(_stops_at(production, tap_point).is_empty(),
		"route: tap point clear before the mouse tap")
	await _click(tap_point)
	_expect_true(emits.size() == 1,
		"route: mouse tap fires exactly one transition")
	_check_chooser_only(gate, stub, links, "route/mouse")
	_expect_true(not (title.get_node("Ui/Screen") as Control).visible,
		"route: tap parks the title chrome under the card")
	_expect_true(not bool(title.get("_accepting")),
		"route: tap spends the one-shot arm")
	# Explicit inline Terms link: opens by pointer and shuts by pointer.
	await _click(gate.consent_link_center("tos"))
	_expect_true((gate.get_node("GateTermsPanel") as Control).visible,
		"route: Terms link opens its sheet")
	_expect_true(links.is_empty(),
		"route: Terms sheet opens no browser link")
	_expect_true(stub.begin_calls.is_empty(),
		"route: Terms link starts no login")
	var terms_close: Button = gate.get_node(
		"GateTermsPanel/Card/Stack/Row/Close") as Button
	await _click(_center(terms_close))
	_expect_true(not (gate.get_node("GateTermsPanel") as Control).visible,
		"route: Terms Close shuts the sheet")
	_expect_true(gate.is_selection_open(),
		"route: sheet close keeps the selection")
	# Explicit inline Privacy link: hands its url by pointer, opens no
	# sheet, starts no login.
	await _click(gate.consent_link_center("privacy"))
	_expect_true(links.size() == 1 \
		and str(links[0]).begins_with("https://"),
		"route: Privacy link hands a safe url")
	_expect_true(not (gate.get_node("GateTermsPanel") as Control).visible,
		"route: Privacy link opens no sheet")
	_expect_true(stub.begin_calls.is_empty() \
		and gate.is_selection_open(),
		"route: Privacy link starts no login")
	links.clear()
	# Disabled provider tap: an unlisted door is not a way into a new
	# game, and opens no legal sheet either.
	var google: Button = gate.get_node(
		"Content/StatusCard/LoggedOut/Providers/ProviderGoogle") as Button
	_expect_true(google.is_visible_in_tree() and google.disabled,
		"route: unlisted provider honestly disabled")
	await _click(_center(google))
	_check_chooser_only(gate, stub, links, "route/disabled")
	# Footer Back click: back to the armed original title.
	var back: Button = gate.get_node(
		"Content/StatusCard/LoggedOut/Footer/Back") as Button
	await _click(_center(back))
	_expect_true(not gate.is_selection_open(),
		"route: footer Back closes the selection")
	_expect_true((title.get_node("Ui/Screen") as Control).visible,
		"route: Back restores the title chrome")
	_expect_true(bool(title.get("_accepting")),
		"route: Back re-arms the tap")
	# Original Settings round-trip by pointer: its panel, no login.
	var settings_button: Button = title.get_node(
		"Ui/Screen/SettingsButton") as Button
	await _click(_center(settings_button))
	_expect_true((title.get_node("Ui/Settings") as Control
		).is_visible_in_tree(), "route: menu click opens its panel")
	_expect_true(not gate.is_selection_open(),
		"route: menu click opens no login")
	var settings_close: Button = title.get_node(
		"Ui/Settings/Close") as Button
	await _click(_center(settings_close))
	_expect_true(not (title.get_node("Ui/Settings") as Control).visible,
		"route: Close click shuts the panel")
	_expect_true(bool(title.get("_accepting")),
		"route: panel close re-arms the tap")
	_expect_no_arena("route/menu")
	# Original Shop round-trip by pointer: its panel, no login.
	var store_button: Button = title.get_node(
		"Ui/Screen/StoreButton") as Button
	_expect_true(store_button.is_visible_in_tree(),
		"route: shop door shows on this build")
	await _click(_center(store_button))
	_expect_true((title.get_node("Ui/IapShop") as Control
		).is_visible_in_tree(), "route: shop click opens its panel")
	_expect_true(not gate.is_selection_open(),
		"route: shop click opens no login")
	var shop_close: Button = title.get_node(
		"Ui/IapShop/Frame/Margin/Rows/Footer/Close") as Button
	await _click(_center(shop_close))
	_expect_true(not (title.get_node("Ui/IapShop") as Control).visible,
		"route: shop Close shuts the panel")
	_expect_true(bool(title.get("_accepting")),
		"route: shop close re-arms the tap")
	_expect_no_arena("route/shop")
	# Second title tap after the history, this time a touch on the
	# natural prompt: only the chooser — never the Terms sheet its
	# emulated counterpart used to click through to.
	tap_point = _tap_point(title)
	_expect_true(_stops_at(production, tap_point).is_empty(),
		"route: tap point clear before the touch tap")
	await _touch_tap(tap_point)
	_expect_true(emits.size() == 2,
		"route: touch tap fires exactly one transition")
	_check_chooser_only(gate, stub, links, "route/touch")
	# The next tap answers: Guest begins, proving no modal
	# intercepted the click meant for it.
	var guest: Button = gate.get_node(
		"Content/StatusCard/LoggedOut/Guest") as Button
	await _click(_center(guest))
	_expect_true(stub.begin_calls.size() == 1 \
			and str(stub.begin_calls[0].get("kind", "")) == "guest",
		"route: Guest answers the tap after the touch")
	_expect_true(gate.is_selection_open(),
		"route: guest answer keeps the logged-out card")
	await _click(_center(back))
	_expect_true(not gate.is_selection_open(),
		"route: final Back closes the selection")
	_expect_true(bool(title.get("_accepting")),
		"route: final Back re-arms the tap")
	# Managed Hall round-trip by pointer: the real ladder door starts
	# the load, the released board opens, Close restores the title.
	var ladder_button: Button = title.get_node(
		"Ui/Screen/LadderButton") as Button
	await _click(_center(ladder_button))
	_expect_true(stub.hall_calls == 1,
		"route: ladder click starts one Hall request")
	_expect_true(not (gate.get_node("GateHallPanel") as Control).visible,
		"route: held Hall shows nothing yet")
	stub.release_hall(1, _hall_view(9000, "MB-" + "f".repeat(32)))
	await _frames(3)
	var hall_panel: GateHallPanel = _hall_panel(gate)
	_expect_true(hall_panel.visible,
		"route: released board opens the Hall")
	var hall_close: Button = hall_panel.get_node(
		"Card/Stack/Close") as Button
	await _click(_center(hall_close))
	_expect_true(not hall_panel.visible,
		"route: Hall Close shuts by pointer")
	_expect_true((title.get_node("Ui/Screen") as Control).visible,
		"route: Hall close restores the title chrome")
	_expect_true(bool(title.get("_accepting")),
		"route: Hall close re-arms the tap")
	_expect_no_arena("route/hall")


## The chooser and nothing else: selection up; Terms, browser links,
## Ready, Busy and the loader all shut; no login begun; no arena load.
func _check_chooser_only(
	gate: GateEntry, stub: StubTapHost, links: Array, tag: String
) -> void:
	_expect_true(gate.is_selection_open(), tag + ": selection open")
	_expect_true(not (gate.get_node("GateTermsPanel") as Control).visible,
		tag + ": no Terms sheet")
	_expect_true(links.is_empty(), tag + ": no Privacy link out")
	_expect_true(not (gate.get_node("Content/StatusCard/Ready") as Control
		).is_visible_in_tree(), tag + ": no Ready card")
	_expect_true(not (gate.get_node("Content/StatusCard/Busy") as Control
		).is_visible_in_tree(), tag + ": no Busy card")
	_expect_true(not (gate.get_node("GateLoadingOverlay") as Control
		).is_visible_in_tree(), tag + ": loader idle")
	_expect_true(stub.begin_calls.is_empty(), tag + ": no login begun")
	_expect_no_arena(tag)


## One supplied Hall row: rank, score and id only. No portrait or
## account data travels; the panel hides the empty portrait itself.
func _hall_view(score: int, row_id: String) -> Dictionary:
	return {
		"rows": [{"rank": 1, "score": score, "id": row_id}],
		"meta": {},
	}


func _hall_panel(gate: GateEntry) -> GateHallPanel:
	return gate.get_node("GateHallPanel") as GateHallPanel


func _hall_headline(panel: GateHallPanel) -> String:
	return (panel.get_node(
		"Card/Stack/Rows/RowsBox/HallRow0/Line/Middle/Headline"
		) as Label).text


func _hall_first_id(panel: GateHallPanel) -> String:
	return (panel.get_node(
		"Card/Stack/Rows/RowsBox/HallRow0/Line/Middle/IdLine"
		) as Label).text


## The player's natural tap point: center of the live tap prompt.
func _tap_point(title: Variant) -> Vector2:
	return _center(title.get_node("Ui/Screen/TapPrompt") as Control)


func _center(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


## A settled production entry behind a stub host for one unit case.
func _boot_production() -> Array:
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubTapHost.new()
	add_child(stub)
	production.set_host_override(stub)
	add_child(production)
	await _frames(4)
	return [production, stub]


func _free_production(production: ProductionEntry, stub: StubTapHost) -> void:
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## Real mouse press/release at a viewport point through Input dispatch.
func _click(point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	Input.parse_input_event(press)
	await _frames(4)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = point
	Input.parse_input_event(release)
	await _frames(4)


## Real touch press/release at a viewport point through Input dispatch.
func _touch_tap(point: Vector2) -> void:
	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.position = point
	Input.parse_input_event(press)
	await _frames(4)
	var release := InputEventScreenTouch.new()
	release.pressed = false
	release.position = point
	Input.parse_input_event(release)
	await _frames(4)


## Every visible STOP control under a canvas point. At the background
## tap point this must be empty: anything listed would eat the tap
## before the title's `_unhandled_input` ever sees it.
func _stops_at(root: Node, point: Vector2) -> Array:
	var found: Array = []
	_collect_stops(root, point, found)
	return found


func _collect_stops(node: Node, point: Vector2, found: Array) -> void:
	for child in node.get_children():
		_collect_stops(child, point, found)
	if node is Control:
		var control: Control = node as Control
		if control.mouse_filter == Control.MOUSE_FILTER_STOP \
				and control.is_visible_in_tree() \
				and control.get_global_rect().has_point(point):
			found.append(str(control.get_path()))


## No tap in this flow may start a direct arena entry.
func _expect_no_arena(tag: String) -> void:
	_expect_true(ResourceLoader.load_threaded_get_status(ARENA_PATH) \
			== ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		tag + ": no tap starts an arena load")


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _expect_true(condition: bool, tag: String) -> void:
	_checked += 1
	if condition:
		return
	_failed += 1
	printerr("title-tap FAIL: ", tag)
