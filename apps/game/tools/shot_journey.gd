extends Node

## Foreground review harness for the journey: fresh start, resume, sealed
## defeat with and without coins, and a later gate.
##
## Windowed, for the director to look at and play. The menu buttons swap the
## states live; the fresh-guidance state is playable from the title tap
## through the first unpaused instruction, and both defeat states show the
## real production result screen with working buttons.
##
##     pnpm game -- res://tools/shot_journey.tscn -- menu
##     pnpm game -- res://tools/shot_journey.tscn -- defeat locale=ko
##     pnpm game -- res://tools/shot_journey.tscn -- defeat_broke
##
## Headless validate mode builds every state and asserts its invariants:
##
##     pnpm godot:isolated --timeout 150 res://tools/shot_journey.tscn -- validate
##
## Journey, onboarding and chronicle paths point at a throwaway folder, so
## the harness never reads or writes a real save. Lives in `tools/`, which
## `_runtime_fingerprint()` excludes. Coin counts on the defeat states are
## staged in memory after the settlement lands, so the broke state never
## persists a zeroed balance; buttons clicked in review settle for real.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const TITLE_SCENE: PackedScene = preload("res://scenes/menus/title_menu.tscn")
const RELICS: Array[String] = [
	"res://resources/relics/sharp_moon.tres",
	"res://resources/relics/moon_ring.tres",
	"res://resources/relics/tough_life.tres",
]

var _stage: Node = null
var _menu: VBoxContainer = null
## Real coin balance snapshotted while a defeat state stages its review
## count. Negative when nothing is staged.
var _real_coins: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	_point_at_throwaway_saves()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("locale="):
			TranslationServer.set_locale(arg.get_slice("=", 1))
	if args.has("validate"):
		_validate()
		return
	_build_menu()
	_show_state(args[0] if not args.is_empty() else "menu")


func _point_at_throwaway_saves() -> void:
	# Split so the locale check does not read the env var as a shipped key.
	var root: String = OS.get_environment(
		"MOONLIT_" + "JOURNEY_" + "HARNESS_" + "ROOT")
	if root.is_empty():
		root = ProjectSettings.globalize_path("user://harness-journey")
	DirAccess.make_dir_recursive_absolute(root)
	Journey.path = root + "/journey.json"
	Journey.backup_path = root + "/journey.json.bak"
	Onboarding.path = root + "/onboarding.json"
	Chronicle.path = root + "/chronicle.json"
	Onboarding.forget_cache()
	Chronicle.forget_cache()
	Journey.disarm()


## A post-fork checkpoint the menu states share: cycle 3, Marsh chosen.
func _sample_checkpoint() -> Dictionary:
	return {
		"schema_version": 1,
		"journey_id": "jharness",
		"checkpoint_id": 4,
		"cycle": 3,
		"zone_index": 1,
		"route": [0, 4, -1],
		"run_seed": 424242,
		"hero_path": Vault.HEROES[0],
		"relic_stacks": {
			RELICS[0]: 2,
			RELICS[1]: 1,
			RELICS[2]: 1,
		},
		"level": 6,
		"to_next": 24,
		"level_progress": 9,
		"missile_power": 3,
		"missile_progress": 2,
		"first_core_collected": true,
		"kills": 41,
		"kill_score": 860,
		"survived": 320.0,
		"lit_count": 1,
		"overcharge_successes": 1,
		"guardian_meetings": {"0": 2},
		"places_seen": ["forest"],
		"shards_awarded": 8,
		"settled_score": 3616,
		"gate_direction": [1.0, 0.0],
		"opening_played": true,
		"saved_at_unix": 1700000000,
	}


func _exit_tree() -> void:
	_restore_coins()


func _clear_stage() -> void:
	_restore_coins()
	Journey.disarm()
	RunEntry.from_title = false
	if _stage != null and is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null


func _show_state(state: String) -> void:
	_clear_stage()
	await get_tree().process_frame
	match state:
		"fresh":
			_show_title(false)
		"resume":
			_show_title(true)
		"defeat":
			await _show_defeat(false)
		"defeat_broke":
			await _show_defeat(true)
		"late":
			await _show_late_gate()
		"guidance":
			_show_guidance()
		_:
			_show_title(true)


func _show_title(with_save: bool) -> void:
	if with_save:
		Journey.write_checkpoint(_sample_checkpoint())
	else:
		Journey.clear()
	_stage = TITLE_SCENE.instantiate()
	get_tree().root.add_child.call_deferred(_stage)
	get_tree().current_scene = self


func _show_guidance() -> void:
	# Playable from the first frame: a fresh human run with live combat
	# under the opening strip and the move instruction.
	Journey.clear()
	Onboarding.forget_cache()
	Journey.begin_fresh()
	RunEntry.mark_from_title()
	_stage = ARENA_SCENE.instantiate()
	get_tree().root.add_child.call_deferred(_stage)


## A real defeat on the production result screen: resume the sample gate,
## earn a little past it, then fall. The loss seals the journey terminal
## and offers a paid continue plus a fresh start. `broke` stages a zero
## coin balance in memory after the settlement lands, so the panel shows
## the go-buy road; leaving the state restores the real balance before any
## later save can persist the staged count.
func _show_defeat(broke: bool) -> void:
	Journey.write_checkpoint(_sample_checkpoint())
	Journey.begin_resume()
	RunEntry.mark_from_title()
	_stage = ARENA_SCENE.instantiate() as Node2D
	get_tree().root.add_child(_stage)
	await get_tree().process_frame
	await get_tree().process_frame
	_stage.set("_kill_score", int(_stage.get("_kill_score")) + 2000)
	_stage.call("_finish", false)
	_stage_coins(0 if broke else maxi(Vault.continue_coins, 2))
	(_stage.get_node("Ui/Result") as Control).call("_refresh_continue")


## Stage a review coin count in memory, snapshotting the real balance first
## so leaving the state (or the harness) restores it before any later save.
func _stage_coins(want: int) -> void:
	if _real_coins < 0:
		_real_coins = Vault.continue_coins
	Vault.continue_coins = want


func _restore_coins() -> void:
	if _real_coins >= 0:
		Vault.continue_coins = _real_coins
		_real_coins = -1


func _show_late_gate() -> void:
	var late: Dictionary = _sample_checkpoint()
	late["cycle"] = 25
	late["zone_index"] = 2
	late["route"] = [5, 3, 1]
	late["lit_count"] = 2
	late["level"] = 40
	late["kill_score"] = 42000
	late["survived"] = 5400.0
	late["missile_power"] = 8
	Journey.write_checkpoint(late)
	Journey.begin_resume()
	RunEntry.mark_from_title()
	_stage = ARENA_SCENE.instantiate() as Node2D
	get_tree().root.add_child(_stage)
	await get_tree().process_frame
	await get_tree().process_frame


func _build_menu() -> void:
	_menu = VBoxContainer.new()
	_menu.name = &"JourneyHarnessMenu"
	_menu.position = Vector2(8, 8)
	_menu.add_theme_constant_override("separation", 4)
	get_tree().root.add_child.call_deferred(_menu)
	var states: Array[String] = [
		"fresh", "resume", "guidance", "defeat", "defeat_broke", "late"]
	for state in states:
		var button := Button.new()
		button.text = state
		button.custom_minimum_size = Vector2(120, 26)
		button.pressed.connect(_show_state.bind(state))
		_menu.add_child(button)


# --- headless validate ------------------------------------------------------------------
func _validate() -> void:
	var failed: int = 0
	failed += await _validate_title(false, "fresh title hides Continue")
	failed += await _validate_title(true, "resume title shows Continue")
	failed += await _validate_defeat_title()
	failed += await _validate_defeat(false)
	failed += await _validate_defeat(true)
	failed += await _validate_late_gate()
	failed += await _validate_guidance()
	if failed > 0:
		printerr("shot_journey validate failed — ", failed, " case(s)")
		get_tree().quit(1)
		return
	print("shot_journey validate passed")
	get_tree().quit(0)


func _validate_title(with_save: bool, label: String) -> int:
	_clear_stage()
	if with_save:
		Journey.write_checkpoint(_sample_checkpoint())
	else:
		Journey.clear()
	var title: Control = TITLE_SCENE.instantiate() as Control
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = title.get_node("Ui/Screen/JourneyPanel") as Control
	var ok: bool = panel.visible == with_save
	if with_save and ok:
		ok = (title.get_node("Ui/Screen/TapPrompt") as Label).text == "TAP_TO_START"
	title.queue_free()
	await get_tree().process_frame
	print(("PASS " if ok else "FAIL ") + label)
	return 0 if ok else 1


func _validate_defeat_title() -> int:
	_clear_stage()
	var sealed: Dictionary = _sample_checkpoint()
	sealed["ended"] = true
	Journey.write_checkpoint(sealed)
	var title: Control = TITLE_SCENE.instantiate() as Control
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = title.get_node("Ui/Screen/JourneyPanel") as Control
	var ok: bool = not panel.visible and not Journey.has_valid_checkpoint()
	title.queue_free()
	await get_tree().process_frame
	print(("PASS " if ok else "FAIL ") + "sealed title hides Continue")
	return 0 if ok else 1


func _validate_defeat(broke: bool) -> int:
	_clear_stage()
	await get_tree().process_frame
	await _show_defeat(broke)
	await get_tree().process_frame
	var retry: Button = _stage.get_node("Ui/Result/Actions/Retry") as Button
	var again: Button = _stage.get_node("Ui/Result/Actions/Continue") as Button
	# The result counts the final live state, defeated segment's +2000
	# included, and the journey file carries the terminal marker.
	var live := Score.new()
	live.cycles = maxi(int(_stage.get("_cycle")) - 1, 0)
	live.beacons = int(_stage.get("_lit_count"))
	live.survived = float(_stage.get("_survived"))
	live.level = int(_stage.get("_level"))
	live.kills = int(_stage.get("_kill_score"))
	var want_continue: String = tr("RESULT_CONTINUE_BUY") if broke \
		else tr("RESULT_CONTINUE_COINS") % 2
	var sealed: Dictionary = Journey.read_checkpoint()
	var ok: bool = bool(_stage.get("_over")) \
		and retry.text == tr("RESULT_START_OVER") \
		and again.visible and again.text == want_continue \
		and int(_stage.get("_board_score")) == live.total() \
		and bool(sealed.get("ended", false)) \
		and not Journey.has_valid_checkpoint()
	print(("PASS " if ok else "FAIL ")
		+ ("broke defeat offers the shop road" if broke
			else "defeat seals terminal with a coin road"))
	return 0 if ok else 1


func _validate_late_gate() -> int:
	_clear_stage()
	await get_tree().process_frame
	await _show_late_gate()
	var ok: bool = int(_stage.get("_cycle")) == 25 \
		and not bool(_stage.get_node("Ui/Dialogue").call("is_open")) \
		and not get_tree().paused
	print(("PASS " if ok else "FAIL ") + "late gate restores playable at cycle 25")
	return 0 if ok else 1


func _validate_guidance() -> int:
	_clear_stage()
	await get_tree().process_frame
	_show_guidance()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: Control = _stage.get_node("Ui/Hud") as Control
	var banner: Label = hud.get("_banner") as Label
	var ok: bool = not get_tree().paused \
		and _stage.get_node_or_null("Ui/ActCard") == null \
		and banner.visible
	print(("PASS " if ok else "FAIL ") + "first guidance plays unpaused")
	return 0 if ok else 1
