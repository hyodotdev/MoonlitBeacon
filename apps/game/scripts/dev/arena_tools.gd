extends HBoxContainer

## In-run debug buttons. **Debug builds only.**
##
## Title [TestLauncher] can **open** a run in a given state, but cannot change
## state **while the run is going.** The path that was never fully verified
## sits mid-run — three beacons → guardian → next cycle.
##
## Automation cannot find beacons on a wide map, and a human takes over a
## minute per cycle. That time cannot be spent on every cycle-transition fix.
##
## Release frees itself. Removal, not hide.

const STORE_CAPTURE_CLEAN_UI: Script = preload(
	"res://scripts/dev/store_capture_clean_ui.gd")
const STORE_CAPTURE_PROBE: Script = preload(
	"res://scripts/dev/store_capture_probe.gd")
const STORE_CAPTURE_BOOT: Script = preload(
	"res://scripts/dev/store_capture_boot.gd")

var _capture_boot_nonce: String = ""

func _ready() -> void:
	if not OS.is_debug_build():
		set_process(false)
		queue_free()
		return

	add_theme_constant_override("separation", 4)
	_add("Beacon+1", _light_next_beacon)
	_add("Beacon3", _light_beacons)
	_add("HP↑", _heal)
	_add("Invuln", _toggle_shield)
	_add("Dmg×10", _boost)
	_add("Awaken", _awaken)
	_add("Hit", _take_hit)
	_add("Disc↑", _upgrade_disc)
	_add("Blade↑", _upgrade_full_moon)
	_add("Dance↑", _upgrade_moon_dance)
	_add("Guard←", _stage_guardian)
	_add("Guard↓", _slay)
	_prepare_store_capture_boot.call_deferred()


func _prepare_store_capture_boot() -> void:
	var request: Dictionary = STORE_CAPTURE_BOOT.read_request()
	if request.is_empty() or not is_inside_tree():
		return
	var nonce: String = str(request["nonce"])
	if nonce == _capture_boot_nonce:
		return
	_capture_boot_nonce = nonce
	# On a physical iPad, retrieving container state can let a Lv20 raid die
	# first and become Lv21, so the exact capture state is lost forever. Only
	# boot capture locks the next-level threshold so the shot does not depend
	# on device or ADB/CoreDevice round-trip speed.
	var arena: Node = get_tree().current_scene
	if arena != null and arena.has_method("debug_freeze_capture_progress"):
		arena.debug_freeze_capture_progress()
	# After Arena's _ready and first draw, call the existing debug actions as-is.
	await get_tree().process_frame
	match str(request["kind"]):
		"moonlight_barrage":
			_toggle_shield()
		"missile_core":
			_toggle_shield()
			await get_tree().create_timer(1.8, false).timeout
			if not is_inside_tree():
				return
			_toggle_shield()
			await get_tree().create_timer(0.12, false).timeout
			if is_inside_tree():
				_take_hit()
		"field_guardian":
			_toggle_shield()
			await get_tree().create_timer(0.12, false).timeout
			arena = get_tree().current_scene
			if arena != null and arena.has_method("debug_complete_route"):
				await arena.debug_complete_route()


func _process(_delta: float) -> void:
	STORE_CAPTURE_PROBE.poll(get_tree().current_scene)
	# Keep the combat master's real HUD, dash, and version; hide only debug tools and the meter.
	var scene: Node = get_tree().current_scene
	var frame_meter: CanvasItem = null
	if scene != null:
		frame_meter = scene.get_node_or_null("Ui/FrameMeter") as CanvasItem
	STORE_CAPTURE_CLEAN_UI.hide_combat(self, frame_meter)


func _add(label: String, action: Callable) -> void:
	var button: Button = Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 8)
	button.pressed.connect(action)
	add_child(button)


## Light all three beacons now. See if the guardian appears and if killing it rolls the cycle.
func _light_beacons() -> void:
	var arena: Node = get_tree().current_scene
	if arena != null and arena.has_method("debug_complete_route"):
		arena.debug_complete_route()


## Light one unlit beacon so the four time-of-day stages can be checked one shot at a time.
func _light_next_beacon() -> void:
	var arena: Node = get_tree().current_scene
	if arena != null and arena.has_method("debug_light_next_beacon"):
		arena.debug_light_next_beacon()


## Fill health. Die mid-check and it is back to the start.
func _heal() -> void:
	var arena: Node = get_tree().current_scene
	if arena != null and arena.has_method("debug_heal"):
		arena.debug_heal()


## Down the guardian immediately.
##
## **What is under test is whether `_finish_cycle()` can run any number of
## times, not pathfinding.** Automation only circles in place, so it never
## reaches a guardian on the far side of the map (meteor range 312px, map
## 1900×1180). Cycle 3 was tried eight times and never met once.
##
## A human can meet it, but one cycle is over a minute, so eight cycles is
## ten minutes. That time cannot be spent on every cycle-code fix.
func _slay() -> void:
	for spirit in get_tree().get_nodes_in_group("spirits"):
		if not spirit.is_attackable():
			continue
		if spirit.has_method("debug_slay"):
			spirit.debug_slay()
		elif spirit.has_method("take_damage"):
			spirit.take_damage(999999, spirit.global_position)


## Damage ×10. Each press multiplies again.
##
## **This is not a combat-feel check.** Seeing whether cycles repeat means
## killing the guardian, and cycle 3's guardian has 690 HP, which a fresh
## character cannot do. What is under test is whether `_finish_cycle()` can
## run any number of times, not the feel of a hit.
func _boost() -> void:
	var arena: Node = get_tree().current_scene
	if arena != null and arena.has_method("debug_boost_damage"):
		arena.debug_boost_damage()


func _awaken() -> void:
	var arena: Node = get_tree().current_scene
	if arena != null and arena.has_method("debug_awaken"):
		arena.debug_awaken()


func _take_hit() -> void:
	var arena: Node = get_tree().current_scene
	if arena != null and arena.has_method("debug_take_hit"):
		arena.debug_take_hit()


func _upgrade_disc() -> void:
	var arena: Node = get_tree().current_scene
	if arena != null and arena.has_method("debug_upgrade_disc"):
		arena.debug_upgrade_disc()


func _upgrade_full_moon() -> void:
	var arena: Node = get_tree().current_scene
	if arena != null and arena.has_method("debug_upgrade_full_moon"):
		arena.debug_upgrade_full_moon()


func _upgrade_moon_dance() -> void:
	var arena: Node = get_tree().current_scene
	if arena != null and arena.has_method("debug_upgrade_moon_dance"):
		arena.debug_upgrade_moon_dance()


## Move an actually spawned guardian onto the screen.
##
## Guardians appear as far from the player as possible for a fair fight.
## Automated device checks cannot reliably steer around terrain to that
## spot, so spawn, kind, and pattern stay, and only the position is moved
## to a safe coord near the player so the body can be verified.
func _stage_guardian() -> void:
	var arena: Node = get_tree().current_scene
	if arena != null and arena.has_method("debug_stage_guardian"):
		arena.debug_stage_guardian()


## Do not die.
##
## Checking several cycles in a row needs **the run not to cut.** Heal alone
## was not enough — twelve cells gone between heals and the run dies, retry
## resets the cycle to 1, and the check starts over.
func _toggle_shield() -> void:
	var arena: Node = get_tree().current_scene
	if arena == null or not arena.has_method("debug_shield"):
		return
	var on: bool = arena.debug_shield()
	for child in get_children():
		if child is Button and str(child.text).begins_with("Invuln"):
			child.text = "Invuln●" if on else "Invuln"
