extends Node

## Real identity registration: the MoonlitIdentity bridge autoload exists
## before ProductionHost at ordinary startup, the host's real adapter
## resolves that exact node, desktop-native-missing still yields a durable
## local guest and a live unpaused Arena, and the editor/export plugin
## registration stays reachable.
##
## Scene-based: only a real boot loads the default autoloads in order. The
## host under test is the REAL `/root/ProductionHost` with its default
## services — no `inject_services`, no fake bridge, no fake adapter.
##
## Call directly:
## `pnpm godot:isolated --timeout 300 res://tests/test_identity_registration.tscn`

const WRAPPER_SCRIPT: Script = preload(
	"res://addons/moonlit-identity/moonlit_identity.gd")
const NATIVE_ADAPTER_SCRIPT: Script = preload(
	"res://scripts/net/native_identity_adapter.gd")
const ACCOUNT_SCRIPT: Script = preload("res://scripts/net/player_account.gd")
const PLUGIN_SCRIPT: Script = preload(
	"res://addons/moonlit-identity/moonlit_identity_plugin.gd")
const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const MAIN_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")

const IDENTITY_PATH: String = "user://player_identity.cfg"
const BINDINGS_PATH: String = "user://player_bindings.cfg"
const IDENTITY_PLUGIN_CFG: String = \
	"res://addons/moonlit-identity/plugin.cfg"
const IAP_PLUGIN_CFG: String = "res://addons/godot-iap/plugin.cfg"
const ARENA_FRAMES: int = 30

var _failed: int = 0
var _checked: int = 0
var _host_errors: Array = []
var _bridge_deliveries: Array = []
var _adapter_noise: Array = []


func _ready() -> void:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path(
		"user://").simplify_path()
	if expected_root.is_empty() or not user_root.begins_with(
			expected_root + "/"):
		printerr("identity registration tests aborted: user:// path is not isolated — ",
			user_root)
		get_tree().quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	_wipe_identity_files()
	_test_bridge_registered_before_host_startup()
	_test_export_plugin_reachable()
	_test_adapter_resolves_real_bridge()
	await _test_real_main_boots_host()
	_test_negative_bridge_removed_and_restored()
	await _test_desktop_guest_durable()
	await _test_live_arena_unpaused()
	_cleanup()
	_wipe_identity_files()
	if _failed > 0:
		printerr("identity registration tests failed — ", _failed, "/",
			_checked, " cases")
		get_tree().quit(1)
		return
	print("identity registration tests passed — ", _checked, " cases")
	get_tree().quit(0)


func _test_bridge_registered_before_host_startup() -> void:
	var bridge: Node = get_node_or_null("/root/MoonlitIdentity")
	var host: Node = get_node_or_null("/root/ProductionHost")
	_expect_true(bridge != null, "register: /root/MoonlitIdentity exists")
	_expect_true(host != null, "register: /root/ProductionHost exists")
	if bridge == null or host == null:
		return
	_expect_equal(bridge.get_script(), WRAPPER_SCRIPT,
		"register: bridge runs the real wrapper script")
	_expect_false(host.is_started(),
		"register: host not started before the entry boots it")
	var siblings: Array[Node] = get_tree().root.get_children()
	_expect_true(siblings.find(bridge) >= 0
		and siblings.find(bridge) < siblings.find(host),
		"register: bridge sibling ordered before the host")
	_expect_equal(PLUGIN_SCRIPT.AUTOLOAD_NAME, "MoonlitIdentity",
		"register: plugin names the live autoload")
	_expect_equal(PLUGIN_SCRIPT.AUTOLOAD_PATH,
		"res://addons/moonlit-identity/moonlit_identity.gd",
		"register: plugin path matches the wrapper")
	_expect_equal(
		str(ProjectSettings.get_setting("autoload/MoonlitIdentity", "")),
		"*" + PLUGIN_SCRIPT.AUTOLOAD_PATH,
		"register: explicit project setting carries the bridge")


func _test_export_plugin_reachable() -> void:
	var enabled: Array = Array(ProjectSettings.get_setting(
		"editor_plugins/enabled", []))
	_expect_true(_is_identity_plugin_enabled(enabled),
		"register: moonlit-identity editor plugin enabled")
	_expect_true(enabled.has(IAP_PLUGIN_CFG),
		"register: purchase editor plugin still enabled")
	_expect_false(_is_identity_plugin_enabled(
		enabled.filter(func(path: String) -> bool:
			return path != IDENTITY_PLUGIN_CFG)),
		"register: plugin check fails without the entry")
	var export_script: Script = \
		PLUGIN_SCRIPT.MoonlitIdentityExportPlugin as Script
	_expect_true(export_script != null,
		"register: export plugin class reachable")
	if export_script == null:
		return
	# The engine only instantiates export plugins inside the editor, so the
	# game-side proof is the script itself: an EditorExportPlugin subclass
	# carrying every hook the ordinary exports call.
	_expect_equal(export_script.get_instance_base_type(),
		"EditorExportPlugin",
		"register: export class extends EditorExportPlugin")
	var methods: Array = []
	for entry in export_script.get_script_method_list():
		methods.append(str(entry.get("name", "")))
	for hook in ["_supports_platform", "_export_begin",
			"_get_android_libraries", "_get_android_dependencies",
			"_get_android_manifest_application_element_contents"]:
		_expect_true(methods.has(hook),
			"register: export plugin exposes " + hook)
	_expect_equal(export_script.IDENTITY_CONFIG_PATH,
		"res://moonlit_identity.cfg",
		"register: config staging path preserved")
	_expect_true(FileAccess.file_exists(export_script.ANDROID_GDAP_PATH),
		"register: android dependency manifest on disk")
	_expect_true(FileAccess.file_exists(
		export_script.IOS_GDEXTENSION_SOURCE),
		"register: ios descriptor source on disk")


func _test_adapter_resolves_real_bridge() -> void:
	var bridge: Node = get_node_or_null("/root/MoonlitIdentity")
	var host: Node = get_node_or_null("/root/ProductionHost")
	if bridge == null or host == null:
		_expect_true(false, "register: bridge and host for adapter check")
		return
	var adapter: Node = host.get("_adapter") as Node
	_expect_true(adapter != null, "register: host owns an adapter")
	if adapter == null:
		return
	_expect_equal(adapter.get_script(), NATIVE_ADAPTER_SCRIPT,
		"register: host adapter is the real native adapter")
	var caps: Dictionary = adapter.get_capabilities()
	_expect_equal(caps.get("supported", true), false,
		"register: desktop reports native unsupported")
	_expect_equal(adapter.get("_bridge"), bridge,
		"register: adapter resolves the exact live bridge")
	_expect_true(bridge.request_completed.is_connected(
		Callable(adapter, "_on_bridge_completed")),
		"register: adapter wired to the bridge signal")
	# A live round trip with a bogus id: delivery reaches the slot and the
	# slot drops it, so the account never moves and no error fires.
	bridge.request_completed.connect(_note_bridge_delivery)
	adapter.session_changed.connect(_note_adapter_noise)
	adapter.operation_failed.connect(_note_adapter_noise)
	var before: Dictionary = host.account_state()
	bridge.request_completed.emit({"status": "ok", "kind": "cloud",
		"uid": "bogus-uid", "provider": "google",
		"request_id": "bogus-id"})
	_expect_equal(_bridge_deliveries.size(), 1,
		"register: bridge signal delivers to listeners")
	_expect_true(_adapter_noise.is_empty(),
		"register: stale outcome dropped without account noise")
	_expect_equal(host.account_state().get("cloud_uid", "x"),
		before.get("cloud_uid", "y"),
		"register: stale outcome keeps the session")
	bridge.request_completed.disconnect(_note_bridge_delivery)
	adapter.session_changed.disconnect(_note_adapter_noise)
	adapter.operation_failed.disconnect(_note_adapter_noise)


func _test_real_main_boots_host() -> void:
	var bridge: Node = get_node_or_null("/root/MoonlitIdentity")
	var host: Node = get_node_or_null("/root/ProductionHost")
	if bridge == null or host == null:
		_expect_true(false, "register: bridge and host for main check")
		return
	host.production_error.connect(_note_host_error)
	var main: Control = MAIN_SCENE.instantiate() as Control
	_expect_true(main != null, "register: real main instantiates")
	if main == null:
		return
	add_child(main)
	for _index in 5:
		await get_tree().process_frame
	_expect_true(host.is_started(),
		"register: real main boots the host")
	_expect_true(bool((host.account_state() as Dictionary).get(
		"ready", false)), "register: main-booted host reaches ready")
	var siblings: Array[Node] = get_tree().root.get_children()
	_expect_true(siblings.find(bridge) < siblings.find(host),
		"register: bridge still before host after main boot")
	_expect_equal((host.get("_adapter") as Node).get("_bridge"), bridge,
		"register: main-booted adapter holds the live bridge")
	_expect_true(_host_errors.is_empty(),
		"register: main boot raises no host error")
	remove_child(main)
	main.queue_free()
	for _index in 2:
		await get_tree().process_frame


func _test_negative_bridge_removed_and_restored() -> void:
	var root: Window = get_tree().root
	var bridge: Node = root.get_node_or_null("MoonlitIdentity")
	if bridge == null:
		_expect_true(false, "register: bridge present for removal check")
		return
	var home_index: int = root.get_children().find(bridge)
	root.remove_child(bridge)
	_expect_true(root.get_node_or_null("MoonlitIdentity") == null,
		"register: removal hides the bridge path")
	var orphan: Node = NATIVE_ADAPTER_SCRIPT.new() as Node
	add_child(orphan)
	var offline: Dictionary = orphan.get_capabilities()
	_expect_equal(offline.get("supported", true), false,
		"register: no bridge resolves to offline capabilities")
	_expect_equal(offline.get("guest", false), true,
		"register: offline capabilities keep the guest")
	_expect_true(orphan.get("_bridge") == null,
		"register: no bridge leaves the lookup empty")
	remove_child(orphan)
	orphan.free()
	root.add_child(bridge)
	root.move_child(bridge, home_index)
	_expect_true(root.get_node_or_null("MoonlitIdentity") == bridge,
		"register: restored bridge answers the path again")
	var siblings: Array[Node] = root.get_children()
	var host: Node = root.get_node_or_null("ProductionHost")
	_expect_true(siblings.find(bridge) == home_index
		and siblings.find(bridge) < siblings.find(host),
		"register: restored bridge keeps its order before the host")
	var revived: Node = NATIVE_ADAPTER_SCRIPT.new() as Node
	add_child(revived)
	revived.get_capabilities()
	_expect_equal(revived.get("_bridge"), bridge,
		"register: restored bridge resolves again")
	remove_child(revived)
	revived.free()


func _test_desktop_guest_durable() -> void:
	var bridge: Node = get_node_or_null("/root/MoonlitIdentity")
	var host: Node = get_node_or_null("/root/ProductionHost")
	if bridge == null or host == null:
		_expect_true(false, "register: bridge and host for guest check")
		return
	if not host.production_error.is_connected(_note_host_error):
		host.production_error.connect(_note_host_error)
	_expect_false(bridge.is_native_available(),
		"register: no native singleton on desktop")
	_expect_equal(bridge.get_capabilities().get("status", ""),
		"unsupported", "register: desktop capabilities say unsupported")
	var state: Dictionary = host.startup()
	_expect_true(bool(state.get("ready", false)),
		"register: real startup reaches ready")
	_expect_true(ACCOUNT_SCRIPT.is_valid_public_id(
		str(state.get("public_id", ""))),
		"register: real startup mints a durable id")
	_expect_true(FileAccess.file_exists(IDENTITY_PATH),
		"register: durable id written to disk")
	_expect_true((host.providers_for_entry() as Array).is_empty(),
		"register: unsupported bridge lists no providers")
	var entered: Dictionary = host.begin_guest()
	_expect_true(bool(entered.get("ready", false)),
		"register: desktop guest enters without registration")
	_expect_equal(str(entered.get("source", "")), "local",
		"register: desktop guest labeled local")
	_expect_true(str(entered.get("cloud_uid", "")).is_empty(),
		"register: desktop guest claims no cloud uid")
	_expect_false(host.is_login_pending(),
		"register: desktop guest starts no login")
	_expect_true(_host_errors.is_empty(),
		"register: desktop guest raises no host error")


func _test_live_arena_unpaused() -> void:
	var host: Node = get_node_or_null("/root/ProductionHost")
	if host == null:
		_expect_true(false, "register: host for arena check")
		return
	var plan: Dictionary = host.plan_entry(true, true)
	_expect_equal(str(plan.get("status", "")), "ok",
		"register: fresh entry plans on the real host")
	if str(plan.get("status", "")) != "ok":
		return
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	_expect_true(arena != null, "register: real arena instantiates")
	if arena == null:
		return
	add_child(arena)
	for _index in ARENA_FRAMES:
		await get_tree().process_frame
	_expect_true(is_instance_valid(arena) and arena.is_inside_tree(),
		"register: arena stays in the tree")
	_expect_false(get_tree().paused, "register: tree unpaused with arena")
	_expect_true(arena.is_in_group("moonlit_combat_sfx"),
		"register: arena ready ran to group registration")
	var player: Node = arena.get_node_or_null("Player")
	_expect_true(player != null and player.is_inside_tree(),
		"register: arena hero present")
	if player != null:
		_expect_true(player.is_physics_processing(),
			"register: arena hero processes")
	_expect_true(_host_errors.is_empty(),
		"register: live arena raises no host error")
	remove_child(arena)
	arena.queue_free()
	for _index in 2:
		await get_tree().process_frame


func _cleanup() -> void:
	var host: Node = get_node_or_null("/root/ProductionHost")
	if host != null:
		if host.has_method("cancel_entry_plan"):
			host.cancel_entry_plan()
		if host.production_error.is_connected(_note_host_error):
			host.production_error.disconnect(_note_host_error)
		host.shutdown()
	Journey.use_account("")
	Journey.disarm()
	Journey.clear_stable_hooks()
	Journey.last_error = ""


func _is_identity_plugin_enabled(enabled: Array) -> bool:
	return enabled.has(IDENTITY_PLUGIN_CFG)


func _note_host_error(error: Dictionary) -> void:
	_host_errors.append(error)


func _note_bridge_delivery(_outcome: Dictionary) -> void:
	_bridge_deliveries.append(true)


func _note_adapter_noise(_outcome: Dictionary) -> void:
	_adapter_noise.append(true)


func _wipe_identity_files() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		for path in [IDENTITY_PATH, BINDINGS_PATH]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(
					path + suffix))


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("FAIL: ", label)


func _expect_false(value: bool, label: String) -> void:
	_expect_true(not value, label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		_failed += 1
		printerr("FAIL: ", label, " — got ", actual, ", want ", expected)
