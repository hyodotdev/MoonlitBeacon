extends Node

## Direct-distribution probe: title fields resolve the real embedded title.
##
## Boots the real production entry and the standalone title and proves the
## distribution probe reads Ui/Screen and Ui/Screen/StoreButton from the
## original title (the Title child under the production entry, the root
## itself standalone), never from the scene root. A bare scene, a decoy
## carrying the same Ui/Screen shape without title identity, a missing
## scene, and an occluded production title must all fail closed. Each
## button field is checked against the actual embedded node, and the live
## Shop singleton's memory entitlements, revision, and disk ledger must be
## byte-identical after the probe. A headless engine has no export
## feature, so it proves every component but not the final ready; the real
## installed binary proves that.

const PRODUCTION_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")
const TITLE_SCENE: PackedScene = preload(
	"res://scenes/menus/title_menu.tscn")
const PROBE_SCRIPT: Script = preload(
	"res://scripts/dev/store_capture_probe.gd")
const EXPECTED_PRODUCT_ID: String = \
	"com.crossplatformkorea.moonlitbeacon.hero_dancer"
const EXPECTED_HERO_PATH: String = "res://resources/heroes/dancer.tres"
const LEDGER_PATH: String = "user://iap_entitlements.cfg"
const LEDGER_BACKUP_PATH: String = "user://iap_entitlements.cfg.bak"
const ARENA_PATH: String = "res://scenes/gameplay/arena.tscn"
const EXPORTED_FIELDS: Array[String] = [
	"ready",
	"direct_distribution_feature",
	"storefront_enabled",
	"store_state_unavailable",
	"cached_paid_entitlement_product_id",
	"cached_paid_entitlement_hero_path",
	"cached_paid_entitlement_fixture_present",
	"cached_paid_entitlement_owned",
	"cached_paid_entitlement_ignored",
	"cached_paid_entitlements_restored",
	"title_screen_visible",
	"title_store_button_present",
	"title_store_button_self_visible",
	"title_store_button_visible_in_tree",
	"title_store_button_enabled",
	"title_store_button_hidden",
]

var _failed: int = 0
var _checked: int = 0


## Logged-out stub: the gate stays parked for the title behind it.
class StubDistributionHost extends Node:
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

	func provider_label(provider_id: String) -> String:
		return provider_id

	func note_first_paint() -> void:
		pass

	func release_entry_hold() -> void:
		pass

	func cancel_entry_plan() -> void:
		pass


func _ready() -> void:
	get_tree().root.size = Vector2i(808, 360)
	_run.call_deferred()


func _run() -> void:
	await _check_production_clean()
	await _check_standalone_clean()
	await _check_nontitle_rejection()
	await _check_occluded_production()
	await _check_shop_boundary()
	if _failed > 0:
		printerr("direct-distribution-title test failed — ",
			_failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("direct-distribution-title test passed — ", _checked, " case(s)")
	get_tree().quit(0)


## A clean production entry resolves the Title child's real screen and
## button. A root-only lookup finds neither, so these fail without the fix.
func _check_production_clean() -> void:
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubDistributionHost.new()
	add_child(stub)
	production.set_host_override(stub)
	get_tree().root.add_child(production)
	await _frames(4)
	var screen: CanvasItem = production.get_node(
		"Title/Ui/Screen") as CanvasItem
	var button: Button = production.get_node(
		"Title/Ui/Screen/StoreButton") as Button
	_expect_true(screen != null, "production: embedded screen exists")
	_expect_true(button != null, "production: embedded store button exists")
	_expect_equal(PROBE_SCRIPT._resolve_title_root(production),
		production.get_node("Title"),
		"production: resolver returns the Title child")
	_expect_true(not TestLauncher.is_production_title_occluded(production),
		"production: clean boot not occluded")
	var state: Dictionary = PROBE_SCRIPT._direct_distribution_state(
		production)
	_expect_equal(state.get("title_store_button_present"), true,
		"production: embedded store button found")
	_expect_equal(state.get("title_screen_visible"), true,
		"production: embedded screen visible")
	_check_button_fields(state, button, "production")
	_check_exported_fields(state, "production")
	_check_ready_conjunction(state, "production")
	if not OS.has_feature("direct_distribution"):
		_expect_equal(state.get("title_store_button_hidden"), false,
			"production: headless storefront keeps the real button up")
		_expect_equal(bool(state.get("ready", true)), false,
			"production: headless without the export feature is not ready")
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## The standalone title resolves its own root: same fields, same nodes.
func _check_standalone_clean() -> void:
	var title: Control = TITLE_SCENE.instantiate() as Control
	get_tree().root.add_child(title)
	await _frames(4)
	var button: Button = title.get_node(
		"Ui/Screen/StoreButton") as Button
	_expect_true(button != null, "standalone: store button exists")
	_expect_equal(PROBE_SCRIPT._resolve_title_root(title), title,
		"standalone: resolver returns the root itself")
	var state: Dictionary = PROBE_SCRIPT._direct_distribution_state(title)
	_expect_equal(state.get("title_store_button_present"), true,
		"standalone: store button found")
	_expect_equal(state.get("title_screen_visible"), true,
		"standalone: screen visible")
	_check_button_fields(state, button, "standalone")
	_check_ready_conjunction(state, "standalone")
	title.queue_free()
	await _frames(2)


## No title identity means no title proof: a bare scene, a decoy with the
## same Ui/Screen/StoreButton shape, and a missing scene all fail closed.
## A root-only lookup would credit the decoy's shape, so it fails there.
func _check_nontitle_rejection() -> void:
	var bare := Control.new()
	get_tree().root.add_child(bare)
	await _frames(2)
	_expect_true(PROBE_SCRIPT._resolve_title_root(bare) == null,
		"non-title: bare scene resolves to null")
	var bare_state: Dictionary = PROBE_SCRIPT._direct_distribution_state(
		bare)
	_expect_equal(bare_state.get("title_store_button_present"), false,
		"non-title: bare scene has no button proof")
	_expect_equal(bare_state.get("title_screen_visible"), false,
		"non-title: bare scene has no screen proof")
	_expect_equal(bare_state.get("title_store_button_hidden"), false,
		"non-title: bare scene never counts as hidden")
	_expect_equal(bool(bare_state.get("ready", true)), false,
		"non-title: bare scene is not ready")
	bare.queue_free()
	var decoy := Control.new()
	var decoy_ui := Control.new()
	decoy_ui.name = &"Ui"
	decoy.add_child(decoy_ui)
	var decoy_screen := Control.new()
	decoy_screen.name = &"Screen"
	decoy_ui.add_child(decoy_screen)
	var decoy_button := Button.new()
	decoy_button.name = &"StoreButton"
	decoy_button.visible = true
	decoy_button.disabled = false
	decoy_screen.add_child(decoy_button)
	get_tree().root.add_child(decoy)
	await _frames(2)
	_expect_true(decoy_button.is_visible_in_tree(),
		"non-title: decoy shape is genuinely on screen")
	_expect_true(PROBE_SCRIPT._resolve_title_root(decoy) == null,
		"non-title: decoy shape resolves to null")
	var decoy_state: Dictionary = PROBE_SCRIPT._direct_distribution_state(
		decoy)
	_expect_equal(decoy_state.get("title_store_button_present"), false,
		"non-title: decoy shape without title identity proves no button")
	_expect_equal(decoy_state.get("title_screen_visible"), false,
		"non-title: decoy shape without title identity proves no screen")
	_expect_equal(decoy_state.get("title_store_button_hidden"), false,
		"non-title: decoy shape never counts as hidden")
	_expect_equal(bool(decoy_state.get("ready", true)), false,
		"non-title: decoy shape is not ready")
	decoy.queue_free()
	_expect_true(PROBE_SCRIPT._resolve_title_root(null) == null,
		"non-title: missing scene resolves to null")
	var missing_state: Dictionary = PROBE_SCRIPT._direct_distribution_state(
		null)
	_expect_equal(missing_state.get("title_store_button_present"), false,
		"non-title: missing scene has no button proof")
	_expect_equal(missing_state.get("title_screen_visible"), false,
		"non-title: missing scene has no screen proof")
	_expect_equal(bool(missing_state.get("ready", true)), false,
		"non-title: missing scene is not ready")
	await _frames(2)


## An open gate card occludes the production title: the screen proof and
## ready refuse while the button fields still report the actual nodes.
func _check_occluded_production() -> void:
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubDistributionHost.new()
	add_child(stub)
	production.set_host_override(stub)
	get_tree().root.add_child(production)
	await _frames(4)
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var button: Button = production.get_node(
		"Title/Ui/Screen/StoreButton") as Button
	gate.show_logged_out()
	await _frames(2)
	_expect_true(gate.is_selection_open(), "occluded: selection open")
	_expect_true(TestLauncher.is_production_title_occluded(production),
		"occluded: production title occluded")
	var state: Dictionary = PROBE_SCRIPT._direct_distribution_state(
		production)
	_expect_equal(state.get("title_screen_visible"), false,
		"occluded: covered screen proves nothing")
	_expect_equal(bool(state.get("ready", true)), false,
		"occluded: covered title is not ready")
	_expect_equal(state.get("title_store_button_present"), true,
		"occluded: real button node still reported")
	_check_button_fields(state, button, "occluded")
	gate.show_title_rest()
	await _frames(2)
	_expect_true(not TestLauncher.is_production_title_occluded(production),
		"occluded: rest after card returns to clean")
	var restored: Dictionary = PROBE_SCRIPT._direct_distribution_state(
		production)
	_expect_equal(restored.get("title_screen_visible"), true,
		"occluded: screen proof returns after rest")
	await _check_occlusion_parity(production, gate)
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## Every face the boot marker rejects, the probe rejects too: each gate
## panel, the loader veil, and the fresh-journey confirm. The probe keeps
## its own structural copy of that rejection (it cannot name the gate
## classes under `--script`), so this pins the two to each other on one
## live production entry.
func _check_occlusion_parity(production: ProductionEntry,
		gate: GateEntry) -> void:
	var probe_panels: Array = PROBE_SCRIPT.GATE_OCCLUDING_PANELS.duplicate()
	probe_panels.sort()
	var marker_panels: Array = \
		TestLauncher.GATE_OCCLUDING_PANELS.duplicate()
	marker_panels.sort()
	_expect_equal(probe_panels, marker_panels,
		"parity: probe watches the same occluding panels as the marker")
	for panel_name in PROBE_SCRIPT.GATE_OCCLUDING_PANELS:
		var panel: Control = gate.get_node_or_null(
			panel_name) as Control
		_expect_true(panel != null, "parity: " + panel_name + " exists")
		if panel == null:
			continue
		panel.visible = true
		_expect_true(TestLauncher.is_production_title_occluded(production),
			"parity: marker rejects " + panel_name)
		var state: Dictionary = PROBE_SCRIPT._direct_distribution_state(
			production)
		_expect_equal(state.get("title_screen_visible"), false,
			"parity: probe rejects " + panel_name)
		_expect_equal(bool(state.get("ready", true)), false,
			"parity: " + panel_name + " is not ready")
		panel.visible = false
	var token: int = gate.load_scene(ARENA_PATH, "TEST entering the arena")
	_expect_true(token > 0, "parity: loader takes a token")
	_expect_true(TestLauncher.is_production_title_occluded(production),
		"parity: marker rejects the visible loader")
	var loading: Dictionary = PROBE_SCRIPT._direct_distribution_state(
		production)
	_expect_equal(loading.get("title_screen_visible"), false,
		"parity: probe rejects the visible loader")
	_expect_equal(bool(loading.get("ready", true)), false,
		"parity: visible loader is not ready")
	gate.get_loader().cancel()
	gate.get_loader()._on_back()
	await _frames(2)
	var confirm: Control = production.get_node(
		"FreshConfirm") as Control
	confirm.visible = true
	_expect_true(TestLauncher.is_production_title_occluded(production),
		"parity: marker rejects the confirm")
	var confirming: Dictionary = PROBE_SCRIPT._direct_distribution_state(
		production)
	_expect_equal(confirming.get("title_screen_visible"), false,
		"parity: probe rejects the confirm")
	_expect_equal(bool(confirming.get("ready", true)), false,
		"parity: confirm is not ready")
	confirm.visible = false
	var clean: Dictionary = PROBE_SCRIPT._direct_distribution_state(
		production)
	_expect_equal(clean.get("title_screen_visible"), true,
		"parity: screen proof returns when all faces clear")


## The probe uses the live Shop singleton, injects the paid SKU only in
## memory for the owns() call, and restores a byte-equivalent array at
## once. Memory, revision, and both disk replicas must read back equal.
func _check_shop_boundary() -> void:
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubDistributionHost.new()
	add_child(stub)
	production.set_host_override(stub)
	get_tree().root.add_child(production)
	await _frames(4)
	var entitlements_before: Array = Shop.entitlements.duplicate()
	var revision_before: int = int(Shop.revision)
	var ledger_before: String = _read_text(LEDGER_PATH)
	var backup_before: String = _read_text(LEDGER_BACKUP_PATH)
	var state: Dictionary = PROBE_SCRIPT._direct_distribution_state(
		production)
	_expect_equal(Shop.entitlements, entitlements_before,
		"shop: memory entitlements restored byte-equivalent")
	_expect_equal(int(Shop.revision), revision_before,
		"shop: ledger revision untouched")
	_expect_equal(_read_text(LEDGER_PATH), ledger_before,
		"shop: disk ledger untouched")
	_expect_equal(_read_text(LEDGER_BACKUP_PATH), backup_before,
		"shop: disk ledger backup untouched")
	_expect_equal(PROBE_SCRIPT.DIRECT_PROBE_PRODUCT_ID, EXPECTED_PRODUCT_ID,
		"shop: probe constant pins the paid SKU")
	_expect_equal(PROBE_SCRIPT.DIRECT_PROBE_HERO_PATH, EXPECTED_HERO_PATH,
		"shop: probe constant pins the hero path")
	_expect_equal(state.get("cached_paid_entitlement_product_id"),
		EXPECTED_PRODUCT_ID, "shop: paid SKU fixture product")
	_expect_equal(state.get("cached_paid_entitlement_hero_path"),
		EXPECTED_HERO_PATH, "shop: paid SKU fixture hero")
	_expect_equal(state.get("cached_paid_entitlement_fixture_present"), true,
		"shop: paid SKU fixture present during owns()")
	_expect_equal(state.get("cached_paid_entitlement_owned"),
		Shop.storefront_enabled(),
		"shop: owns() follows the live storefront with the fixture present")
	var ignored: bool = bool(
		state.get("cached_paid_entitlement_fixture_present", false)) \
		and not bool(state.get("cached_paid_entitlement_owned", true))
	_expect_equal(state.get("cached_paid_entitlement_ignored"), ignored,
		"shop: ignored is present-and-denied")
	_expect_equal(state.get("cached_paid_entitlements_restored"), true,
		"shop: entitlement array restored")
	_expect_equal(state.get("direct_distribution_feature"),
		OS.has_feature("direct_distribution"),
		"shop: direct export feature proof")
	_expect_equal(state.get("storefront_enabled"), Shop.storefront_enabled(),
		"shop: live storefront proof")
	_expect_equal(state.get("store_state_unavailable"),
		int(Shop.state) == 0, "shop: live unavailable-state proof")
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## Every button field equals the actual embedded node; nothing invented.
func _check_button_fields(state: Dictionary, button: Button,
		label: String) -> void:
	_expect_equal(state.get("title_store_button_self_visible"),
		button.visible, label + ": button self visibility is actual")
	_expect_equal(state.get("title_store_button_visible_in_tree"),
		button.is_visible_in_tree(),
		label + ": button tree visibility is actual")
	_expect_equal(state.get("title_store_button_enabled"),
		not button.disabled, label + ": button enabled state is actual")
	var expected_hidden: bool = not button.visible \
		and not button.is_visible_in_tree() and button.disabled
	_expect_equal(state.get("title_store_button_hidden"), expected_hidden,
		label + ": hidden flag follows the real button")


## Every field the installed-binary host assertion reads is exported.
func _check_exported_fields(state: Dictionary, label: String) -> void:
	for field in EXPORTED_FIELDS:
		_expect_true(state.has(field), label + ": exports " + field)


## Ready is the full conjunction, so a fixed title field gates the device
## proof instead of bypassing it.
func _check_ready_conjunction(state: Dictionary, label: String) -> void:
	var conjunction: bool = bool(state.get("direct_distribution_feature",
		false)) and not bool(state.get("storefront_enabled", true)) \
		and bool(state.get("store_state_unavailable", false)) \
		and bool(state.get("cached_paid_entitlement_ignored", false)) \
		and bool(state.get("cached_paid_entitlements_restored", false)) \
		and bool(state.get("title_screen_visible", false)) \
		and bool(state.get("title_store_button_hidden", false))
	_expect_equal(bool(state.get("ready", true)), conjunction,
		label + ": ready is the full conjunction")


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
