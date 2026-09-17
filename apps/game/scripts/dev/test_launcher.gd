class_name TestLauncher
extends HBoxContainer

## Test buttons that jump straight into a late-game state. **Debug builds only.**
##
## Why: every game fix needs a look at late-game power, but `adb shell input`
## automation **cannot dodge and dies around one minute.** The level-20 cycle-3
## screen was never seen, and "it is probably fine" kept happening.
##
## A human playing 20 minutes is not the answer either. Twenty minutes per
## number change means verifying costs more than fixing. **Late game can only
## be fixed if it can be opened in one second.**
##
## Gated with `OS.is_debug_build()` so it cannot leak into a shipping build.
## `--export-release` makes this node free itself. Not a check, not a hide —
## `queue_free()`. Leave it around and it will show someday.

## State each button builds. [level, cycle, label].
##
## Level means **that many relics are granted up front.** Cycle means spirits
## start that much tougher. They are separate because they break separately —
## only power high or only enemies high and you cannot tell which is the bug.
const PRESETS: Array = [
	[10, 1, "Lv10"],
	[20, 3, "Lv20·C3"],
	[40, 5, "Lv40·C5"],
]

## Slot the arena will read. `SceneTree` root survives a scene change, so a
## value can be passed without a new autoload.
const BOOST_META: String = "moonlit_test_boost"
const STORE_CAPTURE_TITLE_READY: String = "user://store_capture_title_runtime.ready"
const STORE_CAPTURE_CLEAN_UI: Script = preload(
	"res://scripts/dev/store_capture_clean_ui.gd")
const STORE_CAPTURE_PROBE: Script = preload(
	"res://scripts/dev/store_capture_probe.gd")
const STORE_CAPTURE_BOOT: Script = preload(
	"res://scripts/dev/store_capture_boot.gd")


static func take_boost(tree: SceneTree) -> Array:
	if tree == null or not tree.root.has_meta(BOOST_META):
		return []
	var boost: Array = tree.root.get_meta(BOOST_META)
	# Consume once. Leave it and it sticks on death-and-retry too.
	tree.root.remove_meta(BOOST_META)
	return boost


func _ready() -> void:
	if not OS.is_debug_build():
		set_process(false)
		queue_free()
		return

	add_theme_constant_override("separation", 6)

	# Grant shards. Checking the shrine and character unlocks needs shards, and
	# earning them for real takes dozens of runs. Writing the save file via
	# `adb run-as` is permission-blocked (tried it), so keep this in-game.
	var give: Button = Button.new()
	give.text = "Shards+500"
	give.focus_mode = Control.FOCUS_NONE
	give.add_theme_font_size_override("font_size", 8)
	give.pressed.connect(_give_test_shards)
	add_child(give)

	for entry in PRESETS:
		var button: Button = Button.new()
		button.text = str(entry[2])
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 8)
		button.pressed.connect(_launch.bind(int(entry[0]), int(entry[1])))
		add_child(button)

	# Checking a new sprite on all six heroes needs paid heroes open too.
	# Session-only toggle, so the save file is untouched; release locks both
	# TestLauncher and the Vault bypass.
	var heroes: Button = Button.new()
	heroes.text = "All heroes"
	heroes.focus_mode = Control.FOCUS_NONE
	heroes.add_theme_font_size_override("font_size", 8)
	heroes.pressed.connect(_toggle_all_heroes.bind(heroes))
	add_child(heroes)

	# Store-review images must be the real IAP panel. Direct-distribution debug
	# APKs hide purchase buttons on purpose, so only capture automation uses
	# this debug entry. Release queue_free()s TestLauncher above, so it never
	# shows.
	var store_preview: Button = Button.new()
	store_preview.text = "Store review"
	store_preview.focus_mode = Control.FOCUS_NONE
	store_preview.add_theme_font_size_override("font_size", 8)
	store_preview.pressed.connect(_open_store_preview)
	add_child(store_preview)
	_signal_store_capture_title_ready.call_deferred()
	_launch_store_capture_boot.call_deferred()


func _launch_store_capture_boot() -> void:
	var request: Dictionary = STORE_CAPTURE_BOOT.read_request()
	if request.is_empty() or not is_inside_tree():
		return
	match str(request["kind"]):
		"missile_core":
			_launch(10, 1)
		"moonlight_barrage", "field_guardian":
			_launch(20, 3)


func _signal_store_capture_title_ready() -> void:
	# After several Android relaunches, RenderingServer.frame_post_draw
	# sometimes never fires, so the real title is up and automation still
	# fails 90s later. After four game-loop frames, check this scene's real
	# title UI and version string directly. The host also checks this proof
	# plus foreground and landscape resolution, then waits another 350ms.
	for _frame in range(4):
		if not is_inside_tree():
			return
		var tree: SceneTree = get_tree()
		if tree == null:
			return
		await tree.process_frame
	if not is_inside_tree():
		return
	var scene: Node = get_tree().current_scene
	var screen: CanvasItem = scene.get_node_or_null("Ui/Screen") as CanvasItem \
		if scene != null else null
	var version: Label = scene.get_node_or_null("Ui/Screen/Version") as Label \
		if scene != null else null
	var expected_version: String = "v" + str(ProjectSettings.get_setting(
		"application/config/version", "0.0.0"))
	if screen == null or not screen.is_visible_in_tree() \
			or version == null or version.text != expected_version:
		return
	var ready: FileAccess = FileAccess.open(STORE_CAPTURE_TITLE_READY, FileAccess.WRITE)
	if ready != null:
		ready.store_string("title-ready\n")


func _process(_delta: float) -> void:
	STORE_CAPTURE_PROBE.poll(get_tree().current_scene)
	# Strip debug launch buttons only on capture masters. Title UI and version stay.
	STORE_CAPTURE_CLEAN_UI.hide_title(self)


func _give_test_shards() -> void:
	# `--script` regression compiles the project's global classes without
	# creating AutoLoad symbols. Look up Vault only at runtime so a debug
	# button cannot break that check. In a normal game /root/Vault always exists.
	var vault: Node = get_node_or_null("/root/Vault")
	if vault == null:
		return
	vault.set("shards", int(vault.get("shards")) + 500)
	vault.call("save_vault")


func _toggle_all_heroes(button: Button) -> void:
	var vault: Node = get_node_or_null("/root/Vault")
	if vault == null:
		return
	var open: bool = bool(vault.call("debug_open_all_heroes"))
	button.text = "All heroes✓" if open else "All heroes"


func _launch(level: int, cycle: int) -> void:
	get_tree().root.set_meta(BOOST_META, [level, cycle])
	get_tree().change_scene_to_file("res://scenes/gameplay/arena.tscn")


func _open_store_preview() -> void:
	var scene: Node = get_tree().current_scene
	if scene != null and scene.has_method("debug_open_iap_store"):
		scene.debug_open_iap_store()
