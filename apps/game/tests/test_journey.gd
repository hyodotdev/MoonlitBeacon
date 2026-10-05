extends Node

## Journey persistence: checkpoints, resume, death retry, and the episode catalog.
##
## The endless game keeps its run across launches: segment-entry checkpoints
## seal the gate behind the player, death retries the saved segment without
## farming it, and the title offers Continue back through the last gate. The
## opening plays over live combat instead of pausing it, and learned tips
## stay learned. These pin the parts a regression could quietly break: the
## round trip after a fork and a guardian reward, a late cycle past every
## authored episode, hostile saves, backup recovery, failed writes, repeated
## death/retry/launches that must not mint shards, the fresh-journey
## confirmation, the unpaused opening contract, and the story catalog that
## Acts, the chronicle and the arena all read from.
##
## Uses temp journey/onboarding/chronicle paths under the isolated test HOME,
## so no human save is touched. The Vault and Records autoloads are real but
## isolated; assertions use deltas, never absolutes.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const TITLE_SCENE: PackedScene = preload("res://scenes/menus/title_menu.tscn")
const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_panel.tscn")
const TEST_PATH: String = "user://test_journey.json"
const TEST_BACKUP: String = "user://test_journey.json.bak"
const TEST_ONBOARD: String = "user://test_onboarding.json"
const TEST_CHRONICLE: String = "user://test_journey_chronicle.json"
const VAULT_TMP: String = "user://vault.cfg.tmp"
const DANCER: String = "res://resources/heroes/dancer.tres"
const SHARP_MOON: String = "res://resources/relics/sharp_moon.tres"
const TOUGH_LIFE: String = "res://resources/relics/tough_life.tres"
const MOON_RING: String = "res://resources/relics/moon_ring.tres"
const LIGHT_STEP: String = "res://resources/relics/light_step.tres"
const LOCALES: Array[String] = ["en", "ko", "ja", "zh_CN", "zh_TW"]

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_run.call_deferred()


func _run() -> void:
	_fresh_paths()
	await _test_checkpoint_roundtrip_fork_reward()
	_fresh_paths()
	await _test_late_cycle_restore()
	_fresh_paths()
	_test_save_rejection()
	_fresh_paths()
	_test_backup_recovery()
	_fresh_paths()
	_test_failed_write_keeps_previous()
	_fresh_paths()
	await _test_death_retry_no_farming()
	_fresh_paths()
	await _test_result_retry_copy()
	_fresh_paths()
	await _test_fresh_confirm_required()
	_fresh_paths()
	await _test_opening_continuous_input()
	_fresh_paths()
	await _test_later_story_still_modal()
	_fresh_paths()
	_test_catalog_consistency()
	_fresh_paths()
	await _test_unarmed_writes_nothing()
	_fresh_paths()
	await _test_blocked_checkpoint_settles_exactly_once()
	_fresh_paths()
	_test_committed_payout_survives_crash()
	_fresh_paths()
	await _test_vault_save_failure_retry_across_restart()
	_fresh_paths()
	_test_replacement_faults()
	_fresh_paths()
	_test_schema_strictness()
	_fresh_paths()
	_test_oversized_refused_before_read()
	_fresh_paths()
	_test_safe_integer_boundaries()
	_fresh_paths()
	await _test_cycle_beyond_1000()
	_fresh_paths()
	_test_receipt_retirement()
	_fresh_paths()
	_test_mixed_eviction_and_garbage_ids()
	_fresh_paths()
	await _test_journey_ui_fits_five_locales()
	await _test_every_journey_key_exists_in_every_locale()

	_restore_paths()
	Journey.disarm()
	if _failed > 0:
		printerr("journey test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("journey test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("journey test aborted: user:// path is not isolated — ", user_root)
	return safe


func _fresh_paths() -> void:
	Journey.path = TEST_PATH
	Journey.backup_path = TEST_BACKUP
	Onboarding.path = TEST_ONBOARD
	Chronicle.path = TEST_CHRONICLE
	for candidate in [TEST_PATH, TEST_BACKUP, TEST_PATH + ".tmp",
			TEST_BACKUP + ".tmp", TEST_ONBOARD, TEST_ONBOARD + ".tmp",
			TEST_CHRONICLE]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	# Fault-injection residue is always ours in the isolated HOME: a temp or
	# vault path left occupied as a directory comes down.
	for occupied in [TEST_PATH + ".tmp", TEST_BACKUP + ".tmp", VAULT_TMP]:
		if DirAccess.dir_exists_absolute(
				ProjectSettings.globalize_path(occupied)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(occupied))
	Onboarding.forget_cache()
	Chronicle.forget_cache()
	Journey.disarm()
	Journey.last_error = ""
	Journey.install_fault = Journey.InstallFault.NONE
	RunEntry.from_title = false
	get_tree().paused = false


func _restore_paths() -> void:
	for candidate in [TEST_PATH, TEST_BACKUP, TEST_PATH + ".tmp", TEST_ONBOARD,
			TEST_ONBOARD + ".tmp", TEST_CHRONICLE]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	Journey.path = Journey.DEFAULT_PATH
	Journey.backup_path = Journey.DEFAULT_BACKUP_PATH
	Onboarding.path = Onboarding.DEFAULT_PATH
	Chronicle.path = Chronicle.DEFAULT_PATH
	Onboarding.forget_cache()
	Chronicle.forget_cache()
	Journey.disarm()
	Journey.last_error = ""
	RunEntry.from_title = false
	get_tree().paused = false


## A human run starts from the title: writes armed, entry marked.
func _begin_human_fresh() -> void:
	Journey.begin_fresh()
	RunEntry.mark_from_title()


func _begin_human_resume() -> void:
	Journey.begin_resume()
	RunEntry.mark_from_title()


func _open_dancer() -> void:
	# The isolated Vault starts locked. Grant Dancer through her real IAP
	# source so the round trip can carry a non-default hero.
	if not Vault.hero_open(DANCER):
		Vault.grant_heroes([DANCER] as Array[String], Vault.hero_iap_source(DANCER))
	Vault.choose_hero(DANCER)


func _stack_counts(arena: Node2D) -> Dictionary:
	var counts: Dictionary = {}
	for item in arena.get("_taken"):
		if item == null:
			continue
		var relic_path: String = str(item.get_meta("path", ""))
		if relic_path.is_empty():
			relic_path = (item as Relic).resource_path
		counts[relic_path] = int(counts.get(relic_path, 0)) + 1
	return counts


# --- round trip -----------------------------------------------------------------
## A journey saved after a fork and a guardian reward restores the same hero,
## selected terrain/route, held stack counts, power, score counters and gate.
func _test_checkpoint_roundtrip_fork_reward() -> void:
	_open_dancer()
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	# A post-fork, post-reward state: cycle 3, second zone, Marsh chosen.
	arena.set("_cycle", 3)
	arena.set("_zone_index", 1)
	# The route is a typed array: assign in place, never replace.
	(arena.get("_route") as Array)[0] = 0
	(arena.get("_route") as Array)[1] = 4
	(arena.get("_route") as Array)[2] = -1
	arena.set("_lit_count", 1)
	arena.set("_run_seed", 424242)
	arena.set("_level", 6)
	arena.set("_to_next", 24)
	arena.set("_level_progress", 9)
	arena.set("_missile_power", 3)
	arena.set("_missile_progress", 4)
	arena.set("_first_missile_core_collected", true)
	arena.set("_kills", 41)
	arena.set("_kill_score", 860)
	arena.set("_survived", 320.0)
	arena.set("_overcharge_successes", 1)
	arena.set("_guardian_meetings", {0: 2})
	arena.set("_places_seen_run", {"forest": true})
	arena.set("_gate_direction", Vector2.RIGHT)
	var relic_panel: Control = arena.get_node("Ui/Relic") as Control
	arena.call("_on_relic_picked", relic_panel.call("take_named", SHARP_MOON), false)
	arena.call("_on_relic_picked", relic_panel.call("take_named", SHARP_MOON), false)
	arena.call("_on_relic_picked", relic_panel.call("take_named", TOUGH_LIFE), false)
	var want_stacks: Dictionary = _stack_counts(arena)
	_expect_equal(int(want_stacks.get(SHARP_MOON, 0)), 2, "two Sharp Moon stacks held")
	_expect_equal(int(want_stacks.get(TOUGH_LIFE, 0)), 1, "one Tough Life stack held")
	_expect_equal(int(want_stacks.get(MOON_RING, 0)), 1, "Dancer opening ring held")
	_expect_equal(int(want_stacks.get(LIGHT_STEP, 0)), 1, "Dancer opening step held")

	_expect_true(bool(arena.call("_journey_checkpoint", true)), "the gate checkpoint writes")
	_expect_true(FileAccess.file_exists(TEST_PATH), "the checkpoint file exists")
	var awarded: int = int(arena.get("_run_shards_awarded"))

	arena.queue_free()
	await get_tree().process_frame
	_begin_human_resume()
	var revived: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(revived)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_expect_equal(str(revived.get("_run_hero_path")), DANCER, "the saved hero returns")
	_expect_equal(int(revived.get("_cycle")), 3, "the saved cycle returns")
	_expect_equal(int(revived.get("_zone_index")), 1, "the saved zone returns")
	var route: Array = revived.get("_route")
	_expect_equal([int(route[0]), int(route[1]), int(route[2])], [0, 4, -1],
		"the chosen fork route returns")
	_expect_equal(int(revived.call("_terrain_at", 1)), 4, "the chosen terrain returns")
	_expect_equal(int(revived.get("_run_seed")), 424242, "the deterministic seed returns")
	_expect_equal(_stack_counts(revived), want_stacks, "held stack counts return")
	_expect_equal(int(revived.get("_missile_power")), 3, "missile power returns")
	_expect_equal(int(revived.get("_level")), 6, "level returns")
	_expect_equal(int(revived.get("_kills")), 41, "kill count returns")
	_expect_equal(int(revived.get("_kill_score")), 860, "kill score returns")
	_expect_true(absf(float(revived.get("_survived")) - 320.0) < 5.0,
		"survived time returns")
	_expect_equal(int(revived.get("_lit_count")), 1, "the lit beacon count returns")
	_expect_equal(int(revived.get("_overcharge_successes")), 1,
		"cycle overcharge count returns")
	_expect_equal(int((revived.get("_guardian_meetings") as Dictionary).get(0, 0)), 2,
		"guardian meetings return")
	_expect_true(bool((revived.get("_places_seen_run") as Dictionary).has("forest")),
		"restored places return")
	_expect_equal(int(revived.get("_run_shards_awarded")), awarded,
		"settlement bookkeeping returns")
	var beacons: Array = revived.get("_beacons")
	_expect_true(bool(beacons[0].get("lit")), "the completed zone stays lit")
	_expect_false(bool(beacons[1].get("lit")), "the entered zone starts unlit")
	_expect_equal(int(revived.get("_health")), int(revived.get("_max_health")),
		"the gate restores full health")
	_expect_false(bool(revived.get("_over")), "the restored run is alive")
	_expect_equal(int(revived.get("_tutorial_step")), 4,
		"a resume replays no guidance")
	_expect_true((revived.get("_journey_opening_strip") as Array).is_empty(),
		"a resume replays no opening strip")
	_expect_true(Room.PLAY.has_point((revived.get_node("Player") as Node2D).position),
		"the restored hero stands inside the room")
	revived.queue_free()
	await get_tree().process_frame


# --- late cycle -------------------------------------------------------------------
## Past every authored episode the journey still restores, with no dialogue.
func _test_late_cycle_restore() -> void:
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.set("_cycle", 25)
	arena.set("_zone_index", 2)
	(arena.get("_route") as Array)[0] = 5
	(arena.get("_route") as Array)[1] = 3
	(arena.get("_route") as Array)[2] = 1
	arena.set("_lit_count", 2)
	arena.set("_level", 40)
	arena.set("_kill_score", 42000)
	arena.set("_survived", 5400.0)
	arena.set("_missile_power", 8)
	_expect_true(bool(arena.call("_journey_checkpoint", true)),
		"a cycle-25 checkpoint writes")
	arena.queue_free()
	await get_tree().process_frame

	_begin_human_resume()
	var revived: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(revived)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(int(revived.get("_cycle")), 25, "cycle 25 restores")
	_expect_equal(int(revived.get("_zone_index")), 2, "late zone restores")
	_expect_equal(int(revived.call("_terrain_at", 2)), 1, "late route restores")
	_expect_true(StoryEpisodes.is_endless(25), "cycle 25 is past authored beats")
	_expect_true((revived.call("_story_lines", 25) as Array).is_empty(),
		"no dialogue lines past authored beats")
	_expect_false(bool(revived.get_node("Ui/Dialogue").call("is_open")),
		"no modal opens on a late resume")
	_expect_false(get_tree().paused, "a late resume never pauses")
	revived.queue_free()
	await get_tree().process_frame


# --- hostile saves ------------------------------------------------------------------
func _write_text(candidate: String, text: String) -> void:
	var handle: FileAccess = FileAccess.open(candidate, FileAccess.WRITE)
	handle.store_string(text)
	handle.close()


func _valid_checkpoint() -> Dictionary:
	return {
		"schema_version": 1,
		"journey_id": "j1",
		"checkpoint_id": 1,
		"cycle": 3,
		"zone_index": 1,
		"route": [0, 4, -1],
		"run_seed": 7,
		"hero_path": Vault.HEROES[0],
		"relic_stacks": {SHARP_MOON: 2},
		"level": 4,
		"to_next": 12,
		"level_progress": 3,
		"missile_power": 2,
		"missile_progress": 1,
		"first_core_collected": true,
		"kills": 20,
		"kill_score": 300,
		"survived": 120.0,
		"lit_count": 1,
		"overcharge_successes": 0,
		"guardian_meetings": {"0": 1},
		"places_seen": ["forest"],
		"shards_awarded": 5,
		"settled_score": 2400,
		"gate_direction": [1.0, 0.0],
		"opening_played": true,
		"saved_at_unix": 1700000000,
	}


## Corrupt, truncated, oversized, future-schema and invalid-path saves are
## refused whole: no partial state, no arbitrary loads, paid state untouched.
func _test_save_rejection() -> void:
	_expect_true(Journey.validate(_valid_checkpoint()), "the example checkpoint validates")
	var vault_shards: int = Vault.shards
	var vault_opened: Array = (Vault.opened as Array).duplicate()
	var vault_sources: Dictionary = (Vault.hero_sources as Dictionary).duplicate(true)

	_write_text(TEST_PATH, "{not json at all")
	_expect_true(Journey.read_checkpoint().is_empty(), "a corrupt save is refused")
	_write_text(TEST_PATH, "{\"schema_version\": 1, \"cycle\": 3")
	_expect_true(Journey.read_checkpoint().is_empty(), "a truncated save is refused")
	_write_text(TEST_PATH, "x".repeat(Journey.MAX_FILE_BYTES + 1))
	_expect_true(Journey.read_checkpoint().is_empty(), "an oversized save is refused")

	var future: Dictionary = _valid_checkpoint()
	future["schema_version"] = 99
	_write_text(TEST_PATH, JSON.stringify(future))
	_expect_true(Journey.read_checkpoint().is_empty(), "a future schema is refused")

	for bad_path in ["res://scripts/gameplay/vault.gd",
			"res://resources/heroes/../../project.godot", ""]:
		var bad_hero: Dictionary = _valid_checkpoint()
		bad_hero["hero_path"] = bad_path
		_write_text(TEST_PATH, JSON.stringify(bad_hero))
		_expect_true(Journey.read_checkpoint().is_empty(),
			"a hero path outside the roster is refused: %s" % bad_path)

	for bad_relic in ["res://resources/relics/../../project.godot",
			"res://resources/relics/no_such_relic.tres",
			"res://resources/heroes/warden.tres"]:
		var bad_stack: Dictionary = _valid_checkpoint()
		bad_stack["relic_stacks"] = {bad_relic: 1}
		_write_text(TEST_PATH, JSON.stringify(bad_stack))
		_expect_true(Journey.read_checkpoint().is_empty(),
			"a relic path outside the relic folder is refused: %s" % bad_relic)

	for field in ["cycle", "zone_index", "level", "kills", "shards_awarded"]:
		var bad_number: Dictionary = _valid_checkpoint()
		bad_number[field] = -1
		_expect_false(Journey.validate(bad_number),
			"a negative %s is refused" % field)
	var bad_route: Dictionary = _valid_checkpoint()
	bad_route["route"] = [0, 99, -1]
	_expect_false(Journey.validate(bad_route), "an unknown terrain id is refused")
	var bad_zone: Dictionary = _valid_checkpoint()
	bad_zone["zone_index"] = 5
	_expect_false(Journey.validate(bad_zone), "an out-of-range zone is refused")

	_expect_equal(Vault.shards, vault_shards, "refused saves grant no shards")
	_expect_equal(Vault.opened, vault_opened, "refused saves open no heroes")
	_expect_equal(Vault.hero_sources, vault_sources, "refused saves touch no sources")
	_expect_false(Journey.last_error.is_empty(), "refusal leaves a readable reason")


## A corrupt main file falls back to the valid backup, which is copied forward.
func _test_backup_recovery() -> void:
	var first: Dictionary = _valid_checkpoint()
	first["checkpoint_id"] = 1
	_expect_equal(Journey.write_checkpoint(first), OK, "the first checkpoint writes")
	var second: Dictionary = _valid_checkpoint()
	second["checkpoint_id"] = 2
	_expect_equal(Journey.write_checkpoint(second), OK, "the second checkpoint writes")
	_write_text(TEST_PATH, "{\"schema_version\": 1, \"cycle\":")
	var recovered: Dictionary = Journey.read_checkpoint()
	_expect_equal(int(recovered.get("checkpoint_id", 0)), 1,
		"the valid backup recovers the journey")
	var parser: JSON = JSON.new()
	parser.parse(FileAccess.get_file_as_string(TEST_PATH))
	_expect_equal(int((parser.data as Dictionary).get("checkpoint_id", 0)), 1,
		"the recovered backup is copied back to the main file")


## A failed write keeps the previous playable save.
func _test_failed_write_keeps_previous() -> void:
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint()), OK,
		"the previous checkpoint writes")
	# Occupy the temp path as a directory so the write cannot begin.
	var temp: String = TEST_PATH + ".tmp"
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(temp))
	var failed: Dictionary = _valid_checkpoint()
	failed["checkpoint_id"] = 9
	_expect_not_equal(Journey.write_checkpoint(failed), OK,
		"a blocked write reports failure")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	var kept: Dictionary = Journey.read_checkpoint()
	_expect_equal(int(kept.get("checkpoint_id", 0)), 1,
		"the previous playable save survives the failed write")


# --- death and retry ------------------------------------------------------------------
## Repeated death, restore and process-launch retries cannot increase banked
## shards or duplicate record and reward settlement.
func _test_death_retry_no_farming() -> void:
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.set("_level", 5)
	arena.set("_kills", 30)
	arena.set("_kill_score", 700)
	arena.set("_survived", 240.0)
	_expect_true(bool(arena.call("_journey_checkpoint", true)), "the gate seals")
	var banked: int = Vault.shards
	var awarded: int = int(arena.get("_run_shards_awarded"))
	var checkpoint_score: int = int((arena.get("_journey_snapshot") as Dictionary)["settled_score"])
	var checkpoint_stacks: Dictionary = (
		arena.get("_journey_snapshot") as Dictionary)["relic_stacks"]
	var coins: int = Vault.continue_coins
	var retry_action: int = int(arena.ResultAction.RESTART)

	for attempt in 3:
		# The defeated segment earns score, loot and time — all of it is lost.
		arena.set("_kill_score", int(arena.get("_kill_score")) + 5000)
		arena.set("_survived", float(arena.get("_survived")) + 60.0)
		var relic_panel: Control = arena.get_node("Ui/Relic") as Control
		arena.call("_on_relic_picked",
			relic_panel.call("take_named", TOUGH_LIFE), false)
		arena.call("_finish", false)
		await get_tree().process_frame
		_expect_equal(Vault.shards, banked,
			"death %d banks no new shards" % (attempt + 1))
		_expect_equal(int(arena.get("_run_shards_awarded")), awarded,
			"death %d grants no new reward" % (attempt + 1))
		_expect_true(Records.best_score >= checkpoint_score,
			"death %d keeps one record submission" % (attempt + 1))
		var retry: Button = arena.get_node("Ui/Result/Actions/Retry") as Button
		_expect_equal(retry.text, tr("RESULT_GATE_RETRY"),
			"death %d offers the gate retry" % (attempt + 1))
		arena.call("_on_result_dismissed", retry_action)
		await get_tree().process_frame
		_expect_false(bool(arena.get("_over")),
			"retry %d resumes the run" % (attempt + 1))
		_expect_equal(_stack_counts(arena).size(), (checkpoint_stacks as Dictionary).size(),
			"retry %d drops the defeated loot" % (attempt + 1))
		_expect_equal(int(arena.get("_kill_score")),
			int((arena.get("_journey_snapshot") as Dictionary)["kill_score"]),
			"retry %d restores the checkpoint score" % (attempt + 1))
		_expect_equal(Vault.shards, banked,
			"retry %d mints no shards" % (attempt + 1))
	_expect_equal(Vault.continue_coins, coins, "gate retries spend no paid coins")

	# A new process launching into the same gate cannot grant again either.
	arena.queue_free()
	await get_tree().process_frame
	_begin_human_resume()
	var relaunched: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(relaunched)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(int(relaunched.get("_run_shards_awarded")), awarded,
		"a relaunch restores the settlement bookkeeping")
	relaunched.set("_kill_score", int(relaunched.get("_kill_score")) + 9000)
	relaunched.call("_finish", false)
	await get_tree().process_frame
	_expect_equal(Vault.shards, banked, "a relaunched death banks no new shards")
	relaunched.queue_free()
	await get_tree().process_frame


## Retry says which road it takes: the gate on a loss, a fresh run on a win.
func _test_result_retry_copy() -> void:
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(FileAccess.file_exists(TEST_PATH),
		"the fresh start writes its checkpoint (err: %s)" % Journey.last_error)
	_expect_false((arena.get("_journey_snapshot") as Dictionary).is_empty(),
		"the fresh run holds its checkpoint")
	arena.call("_finish", false)
	await get_tree().process_frame
	var retry: Button = arena.get_node("Ui/Result/Actions/Retry") as Button
	_expect_equal(retry.text, tr("RESULT_GATE_RETRY"),
		"a lost checkpoint run names the gate retry")
	# Leaving the death behind, a cashout keeps the plain fresh-run retry.
	arena.call("_retry_from_gate")
	await get_tree().process_frame
	arena.call("_journey_checkpoint", true)
	arena.call("_finish", true)
	await get_tree().process_frame
	_expect_equal(retry.text, tr("RESULT_RETRY"),
		"a settled run keeps the fresh-run retry")
	arena.queue_free()
	await get_tree().process_frame


# --- title ----------------------------------------------------------------------------
## Switching from Continue to a fresh journey needs the in-game confirmation.
func _test_fresh_confirm_required() -> void:
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint()), OK,
		"a checkpoint waits on the title")
	var title: Control = TITLE_SCENE.instantiate() as Control
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = title.get_node("Ui/Screen/JourneyPanel") as Control
	_expect_true(panel.visible, "Continue shows for a valid journey")
	var before: String = FileAccess.get_file_as_string(TEST_PATH)
	# The buttons sit under the panel's rows; resolve them with a walk.
	var fresh_button: Button = _find_button(panel, "JourneyNew")
	var keep_button: Button = _find_button(panel, "JourneyKeep")
	var erase_button: Button = _find_button(panel, "JourneyErase")
	var continue_button: Button = _find_button(panel, "JourneyContinue")
	_expect_true(fresh_button != null and keep_button != null
		and erase_button != null and continue_button != null,
		"Continue, New, Keep and Erase all exist")
	fresh_button.pressed.emit()
	await get_tree().process_frame
	_expect_true(FileAccess.get_file_as_string(TEST_PATH) == before,
		"asking does not touch the save")
	# The flare below would swap the test scene away; unhook the swap and
	# keep the pending action as the assertion.
	title.start_requested.disconnect(Callable(title, "_enter_arena"))
	continue_button.pressed.emit()
	_expect_equal(Journey.pending, Journey.Pending.RESUME,
		"Continue resumes the journey")
	_expect_true(Journey.armed, "Continue arms journey writes")
	# Let the flare land, then free the title and drain the worker arena
	# load the tap requested: the swap that would claim it is unhooked, and
	# each request must be claimed before the next title issues its own.
	await get_tree().create_timer(1.2).timeout
	title.queue_free()
	await get_tree().process_frame
	await _claim_threaded_arena("Continue")

	# A second title proves the confirm-then-erase road arms a fresh journey.
	var second: Control = TITLE_SCENE.instantiate() as Control
	add_child(second)
	await get_tree().process_frame
	await get_tree().process_frame
	second.start_requested.disconnect(Callable(second, "_enter_arena"))
	var second_panel: Control = second.get_node("Ui/Screen/JourneyPanel") as Control
	_find_button(second_panel, "JourneyNew").pressed.emit()
	await get_tree().process_frame
	_find_button(second_panel, "JourneyErase").pressed.emit()
	_expect_equal(Journey.pending, Journey.Pending.FRESH,
		"the confirmed erase starts a fresh journey")
	_expect_true(Journey.armed, "the fresh journey arms writes")
	await get_tree().create_timer(1.2).timeout
	second.queue_free()
	await get_tree().process_frame
	await _claim_threaded_arena("Erase")
	Journey.disarm()


## Drain one completed threaded arena load the way the title's swap would.
## A request left for the next tap to overwrite leaks its result at exit.
func _claim_threaded_arena(label: String) -> void:
	var progress: Array = []
	var status: ResourceLoader.ThreadLoadStatus = \
		ResourceLoader.load_threaded_get_status(
			ARENA_SCENE.resource_path, progress)
	var guard: int = 0
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and guard < 600:
		guard += 1
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(
			ARENA_SCENE.resource_path, progress)
	var claimed: Resource = ResourceLoader.load_threaded_get(
		ARENA_SCENE.resource_path) as Resource
	_expect_true(claimed != null, "%s drains its arena load" % label)


func _find_button(node: Node, button_name: String) -> Button:
	if node is Button and node.name == StringName(button_name):
		return node as Button
	for child in node.get_children():
		var found: Button = _find_button(child, button_name)
		if found != null:
			return found
	return null


# --- opening ----------------------------------------------------------------------------
## Fresh title entry stays unpaused while the first instruction shows, and the
## player moves while it is visible. Learned tips never repeat.
func _test_opening_continuous_input() -> void:
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_false(get_tree().paused, "the fresh opening never pauses")
	_expect_true(arena.get_node_or_null("Ui/ActCard") == null,
		"the fresh opening builds no act card")
	_expect_false(bool(arena.get_node("Ui/Dialogue").call("is_open")),
		"the fresh opening opens no dialogue")
	_expect_equal(int(arena.get("_tutorial_step")), 1, "guidance starts at step 1")
	var banner: Label = (arena.get_node("Ui/Hud") as Control).get("_banner") as Label
	_expect_true(banner.visible and banner.text == tr("TUTORIAL_MOVE"),
		"the first instruction shows while unpaused")
	var before: Vector2 = (arena.get_node("Player") as Node2D).position
	(arena.get_node("Player") as Node2D).position = before + Vector2(100, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(int(arena.get("_tutorial_step")), 2,
		"moving while the instruction shows advances guidance")
	_expect_false(get_tree().paused, "guidance advances without pausing")
	_expect_true(Chronicle.has("story_open"), "the opening is recorded for rereading")
	_expect_true(Chronicle.has("story_1"), "Wave 1 is recorded for rereading")
	arena.queue_free()
	await get_tree().process_frame

	# Once learned, tips do not repeat on a relaunch: all guidance is quiet.
	for key in Onboarding.KEYS:
		Onboarding.mark_done(key)
	_begin_human_fresh()
	var relaunched: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(relaunched)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(int(relaunched.get("_tutorial_step")), 4,
		"learned guidance stays finished on relaunch")
	var banner_after: Label = (relaunched.get_node("Ui/Hud") as Control).get("_banner") as Label
	_expect_false(banner_after.visible, "no learned tip repeats on relaunch")
	_expect_true(relaunched.get_node_or_null("Ui/ActCard") == null,
		"the relaunch builds no act card either")
	relaunched.queue_free()
	await get_tree().process_frame

	# A resume at cycle 1 replays neither the strip nor the old modal chain.
	Onboarding.forget_cache()
	if FileAccess.file_exists(TEST_ONBOARD):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ONBOARD))
	_begin_human_fresh()
	var early: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(early)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool(early.get("_journey_opening_played")),
		"the fresh opening plays once")
	early.call("_journey_checkpoint", true)
	early.queue_free()
	await get_tree().process_frame
	_begin_human_resume()
	var resumed_early: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(resumed_early)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true((resumed_early.get("_journey_opening_strip") as Array).is_empty(),
		"a cycle-1 resume replays no opening strip")
	_expect_true(resumed_early.get_node_or_null("Ui/ActCard") == null,
		"a cycle-1 resume builds no act card")
	_expect_false(bool(resumed_early.get_node("Ui/Dialogue").call("is_open")),
		"a cycle-1 resume opens no dialogue")
	_expect_false(get_tree().paused, "a cycle-1 resume never pauses")
	resumed_early.queue_free()
	await get_tree().process_frame


## The opening change stops at cycle 1: later beats keep their modal pauses,
## and cycles without beats pass quietly with no modal at all.
func _test_later_story_still_modal() -> void:
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.set_process(false)
	arena.set_physics_process(false)
	var dialogue: Control = arena.get_node("Ui/Dialogue") as Control
	arena.set("_pending_story_cycle", 5)
	arena.call("_flush_cycle_story")
	await get_tree().process_frame
	_expect_true(bool(dialogue.call("is_open")), "cycle 5 still opens its dialogue")
	_expect_true(get_tree().paused, "cycle 5 still pauses for its story")
	dialogue.call("_close")
	await get_tree().create_timer(0.3).timeout
	arena.set("_cycle", 11)
	arena.call("_show_cycle_story")
	_expect_equal(int(arena.get("_pending_story_cycle")), 0,
		"cycle 11 queues no modal without a beat")
	_expect_true((arena.call("_story_lines", 11) as Array).is_empty(),
		"cycle 11 has no authored lines")
	get_tree().paused = false
	arena.queue_free()
	await get_tree().process_frame


# --- catalog ------------------------------------------------------------------------------
## Acts, the chronicle and the arena read one episode catalog, and a future
## episode resolves as data without arena edits.
func _test_catalog_consistency() -> void:
	var bounds: Array[Dictionary] = StoryEpisodes.act_boundaries()
	_expect_equal(bounds.size(), Acts.LIST.size(), "the catalog holds four act starts")
	for index in bounds.size():
		_expect_equal(str(bounds[index]["id"]), str(Acts.LIST[index]["id"]),
			"act %d keeps its id" % index)
		_expect_equal(int(bounds[index]["from"]), int(Acts.LIST[index]["from"]),
			"act %d keeps its start cycle" % index)
	for cycle in range(1, 16):
		var act: Dictionary = Acts.starting_at(cycle)
		var catalog_act: Dictionary = StoryEpisodes.act_starting_at(cycle)
		_expect_equal(str(act.get("id", "")), str(catalog_act.get("id", "")),
			"cycle %d opens the catalog act" % cycle)
		_expect_equal(str(Acts.of_cycle(cycle).get("id", "")),
			str(StoryEpisodes.act_of_cycle(cycle).get("id", "")),
			"cycle %d belongs to the catalog act" % cycle)
	_expect_equal(StoryEpisodes.story_beats(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12],
		"the catalog beats match the shipped story")
	_expect_equal(Chronicle.total_count(), 40, "the chronicle still holds forty entries")
	_expect_equal(StoryEpisodes.story_keys(4),
		["STORY_CYCLE_4_A", "STORY_CYCLE_4_B"] as Array[String],
		"a beat resolves its translation keys")
	_expect_true(StoryEpisodes.story_keys(11).is_empty(),
		"the deliberate silence at cycle 11 resolves empty")
	_expect_true(StoryEpisodes.is_endless(13), "cycle 13 falls back to endless trials")
	_expect_false(StoryEpisodes.is_endless(12), "cycle 12 is still authored")

	# Content-extension example: a hypothetical next episode appended after
	# the endless fallback, exactly as the catalog comment documents. The
	# shipped rows are never moved: the finite range wins over the fallback's
	# open range by precedence, not by row order. It is data in this test
	# only — no chapter ships.
	var extended: Array = StoryEpisodes.episodes()
	extended.append({
		"id": "example_tide", "act_id": "moonless", "act_number": 4,
		"from": 13, "to": 16, "beats": [13, 14],
	})
	_expect_equal(extended.size(), StoryEpisodes.EPISODES.size() + 1,
		"the example episode only appends one row")
	_expect_equal(str(extended[4].get("id", "")), "endless",
		"the endless fallback is not moved")
	_expect_equal(str(extended[5].get("id", "")), "example_tide",
		"the example episode lands last")
	_expect_true(StoryEpisodes.story_beats(extended).has(13)
		and StoryEpisodes.story_beats(extended).has(14),
		"the example episode adds its beats")
	# Built by format, not literal: the locale check reads an all-caps
	# literal as a shipped key, and the example episode ships nothing.
	var want_13: Array[String] = [
		"STORY_CYCLE_%d_A" % 13, "STORY_CYCLE_%d_B" % 13]
	_expect_equal(StoryEpisodes.story_keys(13, extended), want_13,
		"the lower bound resolves its keys")
	_expect_equal(str(StoryEpisodes.episode_for_cycle(13, extended).get("id", "")),
		"example_tide", "the lower bound belongs to the example episode")
	_expect_false(StoryEpisodes.is_endless(13, extended),
		"the lower bound is not endless")
	_expect_equal(str(StoryEpisodes.act_of_cycle(13, extended).get("id", "")),
		"moonless", "the lower bound stays in its act")
	_expect_true(StoryEpisodes.act_starting_at(13, extended).is_empty(),
		"the appended chapter opens no new act card")
	_expect_equal(StoryEpisodes.story_keys(14, extended),
		["STORY_CYCLE_%d_A" % 14, "STORY_CYCLE_%d_B" % 14] as Array[String],
		"the second beat resolves its keys")
	_expect_equal(str(StoryEpisodes.episode_for_cycle(16, extended).get("id", "")),
		"example_tide", "the upper bound belongs to the example episode")
	_expect_false(StoryEpisodes.is_endless(16, extended),
		"the upper bound is not endless")
	_expect_true(StoryEpisodes.story_keys(15, extended).is_empty(),
		"the chapter's unbeaten cycle stays silent")
	_expect_equal(str(StoryEpisodes.episode_for_cycle(15, extended).get("id", "")),
		"example_tide", "the silent cycle still belongs to the example episode")
	_expect_false(StoryEpisodes.is_endless(15, extended),
		"the silent cycle is not endless")
	_expect_equal(str(StoryEpisodes.episode_for_cycle(17, extended).get("id", "")),
		"endless", "the cycle past the chapter falls back to endless")
	_expect_true(StoryEpisodes.is_endless(17, extended),
		"the cycle past the chapter is endless")
	_expect_true(StoryEpisodes.story_keys(17, extended).is_empty(),
		"the cycle past the chapter carries no dialogue")
	_expect_equal(str(StoryEpisodes.episode_for_cycle(40, extended).get("id", "")),
		"endless", "the endless fallback survives the example episode")


## Tests, debug boards and capture never arm writes: nothing is saved.
func _test_unarmed_writes_nothing() -> void:
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_false(bool(arena.call("_journey_checkpoint", true)),
		"an unarmed run writes no checkpoint")
	_expect_false(FileAccess.file_exists(TEST_PATH), "no journey file appears")
	_expect_false(FileAccess.file_exists(TEST_ONBOARD), "no onboarding file appears")
	arena.queue_free()
	await get_tree().process_frame


# --- crash safety -------------------------------------------------------------------
## Occupy a path as a directory so the next write there fails. Always paired
## with `_release_dir`.
func _occupy_as_dir(candidate: String) -> void:
	if FileAccess.file_exists(candidate):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(candidate))


func _release_dir(candidate: String) -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(candidate)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


## A successful Vault save plus a failed journey write cannot grant twice:
## block the checkpoint, bank the receipt, destroy the arena, resume, repeat
## the identical progress — the bank grows at most once.
func _test_blocked_checkpoint_settles_exactly_once() -> void:
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.set("_kill_score", 10000)
	arena.set("_survived", 300.0)
	var bank_before: int = Vault.shards
	_occupy_as_dir(TEST_PATH + ".tmp")
	_expect_false(bool(arena.call("_journey_checkpoint", true)),
		"a blocked checkpoint reports failure")
	var bank_after_failed: int = Vault.shards
	_expect_true(bank_after_failed > bank_before,
		"the receipt committed before the write failed (%d -> %d)" % [
			bank_before, bank_after_failed])
	_release_dir(TEST_PATH + ".tmp")
	arena.queue_free()
	await get_tree().process_frame

	# Process-style restart: statics reset, Vault reloaded from disk.
	Journey.disarm()
	RunEntry.from_title = false
	Vault.load_vault()
	_expect_equal(Vault.shards, bank_after_failed,
		"the committed payout survives the restart")
	_begin_human_resume()
	var relaunched: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(relaunched)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(int(relaunched.get("_run_shards_awarded")), 0,
		"the stale checkpoint echoes nothing banked")
	# Identical progress, frozen clock: the repeated receipt must pay 0.
	relaunched.set("_kill_score", 10000)
	relaunched.set("_survived", 300.0)
	_expect_true(bool(relaunched.call("_journey_checkpoint", true)),
		"the repeated seal writes")
	_expect_equal(Vault.shards, bank_after_failed,
		"identical progress after a crash banks nothing twice")
	_expect_equal(int(relaunched.get("_run_shards_awarded")),
		bank_after_failed - bank_before,
		"the duplicate syncs the awarded echo from the ledger")
	relaunched.queue_free()
	await get_tree().process_frame


## A payout committed in the Vault stays committed across a reload: settling
## the same receipt again pays 0, while the next checkpoint carries on.
func _test_committed_payout_survives_crash() -> void:
	var bank_before: int = Vault.shards
	var journey: Variant = Vault.begin_journey()
	_expect_true(journey is int, "a healthy issue returns a sequence")
	var first: Dictionary = Vault.settle_journey_receipt(journey, 3, 100)
	_expect_equal(int(first["status"]), Vault.JourneyReceipt.SETTLED,
		"the first delivery settles")
	_expect_equal(int(first["granted"]), 100, "the first delivery pays in full")
	Vault.load_vault()
	_expect_equal(Vault.shards, bank_before + 100,
		"the payout is durable on disk")
	var replay: Dictionary = Vault.settle_journey_receipt(journey, 3, 100)
	_expect_equal(int(replay["status"]), Vault.JourneyReceipt.DUPLICATE,
		"the redelivery reads duplicate")
	_expect_equal(int(replay["granted"]), 0, "the redelivery pays nothing")
	_expect_equal(int(replay["settled_target"]), 100,
		"the redelivery echoes the settled total")
	var onward: Dictionary = Vault.settle_journey_receipt(journey, 5, 130)
	_expect_equal(int(onward["status"]), Vault.JourneyReceipt.SETTLED,
		"the next checkpoint settles")
	_expect_equal(int(onward["granted"]), 30,
		"the next checkpoint pays only its delta")
	# The same receipt with an advanced live score pays only the new delta,
	# immediately, so value is never stranded; then it is spent.
	var advanced: Dictionary = Vault.settle_journey_receipt(journey, 5, 150)
	_expect_equal(int(advanced["status"]), Vault.JourneyReceipt.SETTLED,
		"an advanced redelivery settles")
	_expect_equal(int(advanced["granted"]), 20,
		"an advanced redelivery pays only its delta")
	var spent: Dictionary = Vault.settle_journey_receipt(journey, 5, 150)
	_expect_equal(int(spent["status"]), Vault.JourneyReceipt.DUPLICATE,
		"the advanced receipt then reads duplicate")
	_expect_equal(int(spent["granted"]), 0, "the spent receipt pays nothing")
	# An older checkpoint never re-mints, even revalued far upward.
	var revalued: Dictionary = Vault.settle_journey_receipt(journey, 3, 500)
	_expect_equal(int(revalued["status"]), Vault.JourneyReceipt.DUPLICATE,
		"an older checkpoint never re-mints")
	_expect_equal(int(revalued["granted"]), 0,
		"a revalued older checkpoint pays nothing")
	_expect_equal(Vault.shards, bank_before + 150,
		"the journey banks exactly once per value")


## A Vault save failure seals the checkpoint unsettled and stays pending;
## the retry after recovery settles once, and a restart still cannot double.
func _test_vault_save_failure_retry_across_restart() -> void:
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.set("_kill_score", 5000)
	var bank_before: int = Vault.shards
	_occupy_as_dir(VAULT_TMP)
	_expect_true(bool(arena.call("_journey_checkpoint", true)),
		"the checkpoint seals (unsettled) despite the Vault failure")
	_expect_equal(Vault.shards, bank_before,
		"a failed receipt banks nothing")
	_expect_true(bool(arena.get("_journey_receipt_pending")),
		"the failed receipt stays pending")
	_expect_equal(int(arena.get("_run_shards_awarded")), 0,
		"a failed receipt echoes nothing")
	_release_dir(VAULT_TMP)
	_expect_true(bool(arena.call("_retry_pending_result_persistence")),
		"the retry after recovery succeeds")
	var bank_after_retry: int = Vault.shards
	_expect_true(bank_after_retry > bank_before,
		"the retry settles the carried value once")
	_expect_false(bool(arena.get("_journey_receipt_pending")),
		"the retry clears the pending receipt")
	arena.queue_free()
	await get_tree().process_frame

	Journey.disarm()
	RunEntry.from_title = false
	Vault.load_vault()
	_begin_human_resume()
	var relaunched: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(relaunched)
	await get_tree().process_frame
	await get_tree().process_frame
	# Same progress, one seal further on: only genuinely new value may pay.
	relaunched.set("_kill_score", 5000)
	relaunched.set("_survived", float(relaunched.get("_survived")) + 60.0)
	var carried_target: int = Vault.shard_target_for_score(
		int(relaunched.call("_journey_score_total")))
	_expect_true(bool(relaunched.call("_journey_checkpoint", true)),
		"the post-restart seal writes")
	var retried_target: int = bank_after_retry - bank_before
	_expect_equal(Vault.shards - bank_after_retry,
		maxi(carried_target - retried_target, 0),
		"the post-restart seal pays only new value")
	_expect_equal(int(relaunched.get("_run_shards_awarded")),
		Vault.shards - bank_before,
		"every banked shard is echoed exactly once")
	relaunched.queue_free()
	await get_tree().process_frame


## Every install boundary fails safe: the rotate fallback installs, a failed
## rotated install restores the aside copy, a failed rotation aborts with the
## main untouched, and a failed backup refresh aborts behind a stale backup.
func _test_replacement_faults() -> void:
	var first: Dictionary = _valid_checkpoint()
	first["checkpoint_id"] = 1
	_expect_equal(Journey.write_checkpoint(first), OK, "checkpoint 1 writes")
	var second: Dictionary = _valid_checkpoint()
	second["checkpoint_id"] = 2
	_expect_equal(Journey.write_checkpoint(second), OK, "checkpoint 2 writes")

	Journey.install_fault = Journey.InstallFault.SKIP_DIRECT
	var third: Dictionary = _valid_checkpoint()
	third["checkpoint_id"] = 3
	_expect_equal(Journey.write_checkpoint(third), OK,
		"the rotate fallback installs")
	Journey.install_fault = Journey.InstallFault.NONE
	_expect_equal(int(Journey.read_checkpoint().get("checkpoint_id", 0)), 3,
		"the rotated main holds the new checkpoint")
	_expect_equal(int(_read_backup_id()), 2,
		"the rotated backup holds the prior checkpoint")

	Journey.install_fault = Journey.InstallFault.FAIL_TEMP_INSTALL
	var fourth: Dictionary = _valid_checkpoint()
	fourth["checkpoint_id"] = 4
	_expect_not_equal(Journey.write_checkpoint(fourth), OK,
		"a failed rotated install reports failure")
	Journey.install_fault = Journey.InstallFault.NONE
	_expect_equal(int(Journey.read_checkpoint().get("checkpoint_id", 0)), 3,
		"the aside copy restores the prior save")
	# The backup refresh ran before the failed install, so the backup holds
	# the same prior checkpoint as the restored main.
	_expect_equal(int(_read_backup_id()), 3, "the backup mirrors the restore")

	Journey.install_fault = Journey.InstallFault.FAIL_ALL
	var fifth: Dictionary = _valid_checkpoint()
	fifth["checkpoint_id"] = 5
	_expect_not_equal(Journey.write_checkpoint(fifth), OK,
		"a failed rotation reports failure")
	Journey.install_fault = Journey.InstallFault.NONE
	_expect_equal(int(Journey.read_checkpoint().get("checkpoint_id", 0)), 3,
		"an aborted rotation keeps the main save")

	_occupy_as_dir(TEST_BACKUP + ".tmp")
	var sixth: Dictionary = _valid_checkpoint()
	sixth["checkpoint_id"] = 6
	_expect_not_equal(Journey.write_checkpoint(sixth), OK,
		"a failed backup refresh aborts the write")
	_release_dir(TEST_BACKUP + ".tmp")
	_expect_equal(int(Journey.read_checkpoint().get("checkpoint_id", 0)), 3,
		"the aborted write keeps the prior main save")
	_expect_equal(int(_read_backup_id()), 3,
		"the aborted write keeps the prior backup")
	_expect_equal(Journey.write_checkpoint(sixth), OK,
		"the write succeeds once the backup path clears")
	_expect_equal(int(Journey.read_checkpoint().get("checkpoint_id", 0)), 6,
		"the recovered write seals the new checkpoint")
	_expect_equal(int(_read_backup_id()), 3,
		"the recovered write rotates the prior save behind it")


func _read_backup_id() -> int:
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(TEST_BACKUP)) != OK:
		return -1
	return int((parser.data as Dictionary).get("checkpoint_id", -1))


## The schema is strictly an integer with exactly the supported value: 1.5,
## "1" and true are unreadable, not version 1; only integral newer versions
## ask for a newer game.
func _test_schema_strictness() -> void:
	var fractional: Dictionary = _valid_checkpoint()
	fractional["schema_version"] = 1.5
	_expect_false(Journey.validate(fractional), "schema 1.5 is refused")
	var stringy: Dictionary = _valid_checkpoint()
	stringy["schema_version"] = "1"
	_expect_false(Journey.validate(stringy), 'schema "1" is refused')
	var boolean: Dictionary = _valid_checkpoint()
	boolean["schema_version"] = true
	_expect_false(Journey.validate(boolean), "schema true is refused")
	var integral: Dictionary = _valid_checkpoint()
	integral["schema_version"] = 1.0
	_expect_true(Journey.validate(integral),
		"schema 1.0 (a JSON round trip) validates")
	_write_text(TEST_PATH, JSON.stringify(fractional))
	_expect_true(Journey.read_checkpoint().is_empty(),
		"schema 1.5 on disk is refused")
	_expect_false(Journey.last_error.contains("newer"),
		"schema 1.5 reads unreadable, not newer")
	var future: Dictionary = _valid_checkpoint()
	future["schema_version"] = 2
	_write_text(TEST_PATH, JSON.stringify(future))
	_expect_true(Journey.read_checkpoint().is_empty(),
		"schema 2 on disk is refused")
	_expect_true(Journey.last_error.contains("newer"),
		"schema 2 asks for a newer game")


## Oversized files are refused by the length gate before a byte is kept or
## parsed — even absurd ones — and an oversized main still falls back to a
## valid backup.
func _test_oversized_refused_before_read() -> void:
	_write_text(TEST_PATH, "x".repeat(Journey.MAX_FILE_BYTES + 1))
	_expect_true(Journey.read_checkpoint().is_empty(),
		"a file one byte past the bound is refused")
	_expect_true(Journey.last_error.contains("too large"),
		"an oversized file says so")
	_write_text(TEST_PATH, "x".repeat(10 * 1024 * 1024))
	_expect_true(Journey.read_checkpoint().is_empty(),
		"a 10 MB file is refused, not allocated")
	var backup: Dictionary = _valid_checkpoint()
	backup["checkpoint_id"] = 7
	_write_text(TEST_BACKUP, JSON.stringify(backup))
	_write_text(TEST_PATH, "x".repeat(Journey.MAX_FILE_BYTES + 1))
	var recovered: Dictionary = Journey.read_checkpoint()
	_expect_equal(int(recovered.get("checkpoint_id", 0)), 7,
		"an oversized main falls back to the valid backup")


## Integers compare in their own type: in-memory ints against 2^53 - 1
## exactly, parsed floats strictly below 2^53. 9007199254740993 must not
## round into the bound, and JSON cannot recover precision already lost.
func _test_safe_integer_boundaries() -> void:
	var top: Dictionary = _valid_checkpoint()
	top["kill_score"] = 9007199254740991
	_expect_true(Journey.validate(top), "2^53 - 1 validates in memory")
	var past: Dictionary = _valid_checkpoint()
	past["kill_score"] = 9007199254740992
	_expect_false(Journey.validate(past), "2^53 fails in memory")
	var rounded: Dictionary = _valid_checkpoint()
	rounded["kill_score"] = 9007199254740993
	_expect_false(Journey.validate(rounded),
		"2^53 + 1 fails instead of rounding into the bound")
	var float_top: Dictionary = _valid_checkpoint()
	float_top["kill_score"] = 9007199254740991.0
	_expect_true(Journey.validate(float_top), "float 2^53 - 1 validates")
	var float_past: Dictionary = _valid_checkpoint()
	float_past["kill_score"] = 9007199254740992.0
	_expect_false(Journey.validate(float_past), "float 2^53 fails")
	var max_id: Dictionary = _valid_checkpoint()
	max_id["journey_id"] = 9007199254740991
	_expect_true(Journey.validate(max_id),
		"a journey id of 2^53 - 1 validates")
	var wide_id: Dictionary = _valid_checkpoint()
	wide_id["journey_id"] = 9007199254740992
	_expect_false(Journey.validate(wide_id),
		"a journey id past 2^53 - 1 is refused")
	var neg_seed: Dictionary = _valid_checkpoint()
	neg_seed["run_seed"] = -9007199254740991
	_expect_true(Journey.validate(neg_seed),
		"run seed -(2^53 - 1) validates")
	neg_seed["run_seed"] = -9007199254740992
	_expect_false(Journey.validate(neg_seed), "run seed -2^53 fails")
	var survived: Dictionary = _valid_checkpoint()
	survived["survived"] = 320.5
	_expect_true(Journey.validate(survived),
		"a fractional survived validates")
	survived["survived"] = 9007199254740992.0
	_expect_false(Journey.validate(survived), "a survived past 2^53 fails")
	_write_text(TEST_PATH, JSON.stringify(top))
	_expect_false(Journey.read_checkpoint().is_empty(),
		"2^53 - 1 on disk restores")
	_write_text(TEST_PATH, JSON.stringify(past))
	_expect_true(Journey.read_checkpoint().is_empty(),
		"2^53 on disk is refused")
	_write_text(TEST_PATH, JSON.stringify(rounded))
	_expect_true(Journey.read_checkpoint().is_empty(),
		"2^53 + 1 on disk is refused after parsing rounds it")
	_write_text(TEST_PATH, JSON.stringify(float_top))
	_expect_false(Journey.read_checkpoint().is_empty(),
		"float 2^53 - 1 on disk restores")


## The endless run outgrows any authored bound: a cycle past 1000 seals and
## restores, 99999 validates, and only absurd cycles refuse.
func _test_cycle_beyond_1000() -> void:
	var deep: Dictionary = _valid_checkpoint()
	deep["cycle"] = 1500
	_expect_true(Journey.validate(deep), "cycle 1500 validates")
	deep["cycle"] = 99999
	_expect_true(Journey.validate(deep), "cycle 99999 validates")
	deep["cycle"] = 100000
	_expect_false(Journey.validate(deep), "cycle 100000 is refused")
	_begin_human_fresh()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.set("_cycle", 1500)
	arena.set("_zone_index", 1)
	(arena.get("_route") as Array)[0] = 2
	(arena.get("_route") as Array)[1] = 5
	(arena.get("_route") as Array)[2] = 0
	arena.set("_lit_count", 1)
	arena.set("_level", 900)
	arena.set("_kill_score", 800000)
	arena.set("_survived", 200000.0)
	_expect_true(bool(arena.call("_journey_checkpoint", true)),
		"a cycle-1500 checkpoint writes")
	arena.queue_free()
	await get_tree().process_frame
	_begin_human_resume()
	var revived: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(revived)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(int(revived.get("_cycle")), 1500, "cycle 1500 restores")
	_expect_equal(int(revived.call("_terrain_at", 1)), 5,
		"the deep route restores")
	_expect_true(StoryEpisodes.is_endless(1500), "cycle 1500 is endless")
	_expect_false(get_tree().paused, "a cycle-1500 resume never pauses")
	revived.queue_free()
	await get_tree().process_frame


## The bounded ledger grants exactly once: replays and older checkpoints pay
## nothing, evicted sequences retire instead of minting, and the ledger
## survives a Vault reload. A failed issue falls back to a random id.
func _test_receipt_retirement() -> void:
	var bank_before: int = Vault.shards
	var ids: Array = []
	for i in Vault.MAX_SETTLED_JOURNEYS + 1:
		var seq: Variant = Vault.begin_journey()
		_expect_true(seq is int, "issue %d returns a sequence" % i)
		ids.append(seq)
		var first: Dictionary = Vault.settle_journey_receipt(seq, 1, 10)
		_expect_equal(int(first["status"]), Vault.JourneyReceipt.SETTLED,
			"journey %d settles" % seq)
	_expect_equal((Vault.settled_journeys as Array).size(),
		Vault.MAX_SETTLED_JOURNEYS, "the ledger stays bounded")
	var retired: Variant = ids[0]
	var replay: Dictionary = Vault.settle_journey_receipt(retired, 1, 10)
	_expect_equal(int(replay["status"]), Vault.JourneyReceipt.RETIRED,
		"an evicted sequence retires instead of settling")
	_expect_equal(int(replay["granted"]), 0, "a retired replay pays nothing")
	var retired_new: Dictionary = Vault.settle_journey_receipt(retired, 2, 50)
	_expect_equal(int(retired_new["status"]), Vault.JourneyReceipt.RETIRED,
		"a retired sequence stays retired at a new checkpoint")
	var live: Variant = ids[ids.size() - 1]
	var stale: Dictionary = Vault.settle_journey_receipt(live, 0, 5)
	_expect_equal(int(stale["status"]), Vault.JourneyReceipt.DUPLICATE,
		"an older checkpoint of a live journey pays nothing")
	var again: Dictionary = Vault.settle_journey_receipt(live, 2, 25)
	_expect_equal(int(again["granted"]), 15, "new value pays its delta")
	var twice: Dictionary = Vault.settle_journey_receipt(live, 2, 25)
	_expect_equal(int(twice["status"]), Vault.JourneyReceipt.DUPLICATE,
		"the same receipt twice pays once")
	_expect_equal(int(twice["settled_target"]), 25,
		"the duplicate echoes the settled total")
	Vault.load_vault()
	var after_reload: Dictionary = Vault.settle_journey_receipt(live, 2, 25)
	_expect_equal(int(after_reload["status"]), Vault.JourneyReceipt.DUPLICATE,
		"the ledger survives a Vault reload")
	_expect_equal((Vault.settled_journeys as Array).size(),
		Vault.MAX_SETTLED_JOURNEYS, "the reloaded ledger stays bounded")
	_occupy_as_dir(VAULT_TMP)
	var issued_before: int = Vault.journey_seq_issued
	var fallback: Variant = Vault.begin_journey()
	_expect_true(fallback is String and str(fallback).begins_with("r"),
		"a failed issue falls back to a random id")
	_expect_equal(Vault.journey_seq_issued, issued_before,
		"a failed issue consumes no sequence")
	_release_dir(VAULT_TMP)
	var fallback_settle: Dictionary = Vault.settle_journey_receipt(
		fallback, 1, 7)
	_expect_equal(int(fallback_settle["status"]), Vault.JourneyReceipt.SETTLED,
		"a fallback id settles while retained")
	Vault.load_vault()
	var fallback_replay: Dictionary = Vault.settle_journey_receipt(
		fallback, 1, 7)
	_expect_equal(int(fallback_replay["status"]), Vault.JourneyReceipt.DUPLICATE,
		"a mixed int/string ledger survives a Vault reload")
	_expect_equal(Vault.shards - bank_before,
		(Vault.MAX_SETTLED_JOURNEYS + 1) * 10 + 15 + 7,
		"every grant lands exactly once")


## Mixed-type eviction stays error-free while unknown strings retire.
##
## Why this test changed: a string id evicted from the bounded ledger used
## to pay again when replayed, because any well-formed string settled as
## fresh money. Strings with no ledger record now settle only when this
## session issued them through `begin_journey()`; every other string retires
## and mints nothing. Settling sixteen arbitrary `"rtest.."` ids without
## issuance was the unsafe expectation, so it now asserts `RETIRED` with
## zero grants and no ledger growth. Legitimate fallbacks still settle
## while retained (issued under a failed save below), an evicted one replays
## `RETIRED`, and junk still retires without minting or growing the ledger.
func _test_mixed_eviction_and_garbage_ids() -> void:
	var bank_before: int = Vault.shards
	var size_before: int = (Vault.settled_journeys as Array).size()
	for i in Vault.MAX_SETTLED_JOURNEYS:
		var unknown: Dictionary = Vault.settle_journey_receipt(
			"rtest%02d" % i, 1, i + 1)
		_expect_equal(int(unknown["status"]), Vault.JourneyReceipt.RETIRED,
			"unissued fallback %d retires" % i)
		_expect_equal(int(unknown["granted"]), 0,
			"unissued fallback %d grants nothing" % i)
	_expect_equal((Vault.settled_journeys as Array).size(), size_before,
		"unissued strings grow no ledger entry")
	_expect_equal(Vault.shards, bank_before,
		"unissued strings bank nothing")
	_occupy_as_dir(VAULT_TMP)
	var fallbacks: Array = []
	for _index in Vault.MAX_SETTLED_JOURNEYS + 1:
		fallbacks.append(Vault.begin_journey())
	_release_dir(VAULT_TMP)
	var distinct: Dictionary = {}
	for fallback in fallbacks:
		_expect_true(fallback is String,
			"a failed issue falls back to a string id")
		distinct[str(fallback)] = true
	_expect_equal(distinct.size(), fallbacks.size(),
		"every issued fallback id is distinct")
	var index: int = 0
	for fallback in fallbacks:
		index += 1
		var settled: Dictionary = Vault.settle_journey_receipt(
			fallback, 1, index)
		_expect_equal(int(settled["status"]), Vault.JourneyReceipt.SETTLED,
			"an issued fallback settles while retained")
	_expect_equal((Vault.settled_journeys as Array).size(),
		Vault.MAX_SETTLED_JOURNEYS, "the mixed ledger stays bounded")
	_expect_true(Vault._find_settled_journey(fallbacks[0]).is_empty(),
		"seventeen settles into a full ledger evict the oldest fallback")
	var replay: Dictionary = Vault.settle_journey_receipt(
		fallbacks[0], 1, 1)
	_expect_equal(int(replay["status"]), Vault.JourneyReceipt.RETIRED,
		"an evicted fallback replays as retired, never fresh money")
	_expect_equal(int(replay["granted"]), 0,
		"the evicted replay grants zero")
	var seq: Variant = Vault.begin_journey()
	_expect_true(seq is int, "a sequence follows the fallbacks")
	var entry: Dictionary = Vault.settle_journey_receipt(seq, 1, 40)
	_expect_equal(int(entry["status"]), Vault.JourneyReceipt.SETTLED,
		"an int settles among strings")
	_expect_equal((Vault.settled_journeys as Array).size(),
		Vault.MAX_SETTLED_JOURNEYS, "the mixed ledger stays bounded")
	_expect_false(Vault._find_settled_journey(seq).is_empty(),
		"the just-written int survives its own eviction")
	for junk: Variant in [{}, [], "", "bad id!", 1.5, true,
			9007199254740992.0]:
		var refused: Dictionary = Vault.settle_journey_receipt(junk, 1, 5)
		_expect_equal(int(refused["status"]), Vault.JourneyReceipt.RETIRED,
			"junk %s retires" % str(junk))
	_expect_equal((Vault.settled_journeys as Array).size(),
		Vault.MAX_SETTLED_JOURNEYS, "junk mints no ledger entry")
	_expect_equal(Vault.shards - bank_before, 153 + 40,
		"only issued grants land exactly once (1+..+17, then 40)")


# --- layout -------------------------------------------------------------------
## The Continue panel and the gate-retry button fit their copy in all five
## locales: no clipped text on the title or the result screen.
func _test_journey_ui_fits_five_locales() -> void:
	_expect_equal(Journey.write_checkpoint(_valid_checkpoint()), OK,
		"a checkpoint waits for the fit check")
	var original: String = TranslationServer.get_locale()
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		var title: Control = TITLE_SCENE.instantiate() as Control
		add_child(title)
		await get_tree().process_frame
		await get_tree().process_frame
		var panel: Control = title.get_node("Ui/Screen/JourneyPanel") as Control
		_expect_true(panel.visible, "%s shows Continue" % locale)
		_expect_journey_button_fits(panel, "JourneyContinue", locale)
		_expect_journey_button_fits(panel, "JourneyNew", locale)
		_find_button(panel, "JourneyNew").pressed.emit()
		await get_tree().process_frame
		_expect_journey_button_fits(panel, "JourneyErase", locale)
		_expect_journey_button_fits(panel, "JourneyKeep", locale)
		title.queue_free()
		await get_tree().process_frame

		var result: Control = RESULT_SCENE.instantiate() as Control
		add_child(result)
		await get_tree().process_frame
		var score := Score.new()
		score.cycles = 3
		score.beacons = 1
		score.survived = 320.0
		score.level = 6
		score.kills = 860
		result.show_result(false, score, false, false, 2, true)
		await get_tree().process_frame
		var retry: Button = result.get_node("Actions/Retry") as Button
		var minimum: Vector2 = retry.get_combined_minimum_size()
		_expect_true(minimum.x <= retry.size.x + 0.5
			and minimum.y <= retry.size.y + 0.5,
			"%s gate-retry button fits (%s / %s)" % [locale, minimum, retry.size])
		result.queue_free()
		await get_tree().process_frame

	# A settings locale switch relabels the code-built buttons on refresh.
	var relabel: Control = TITLE_SCENE.instantiate() as Control
	add_child(relabel)
	await get_tree().process_frame
	await get_tree().process_frame
	var relabel_panel: Control = relabel.get_node(
		"Ui/Screen/JourneyPanel") as Control
	TranslationServer.set_locale("en")
	relabel.call("_refresh_journey_ui")
	_expect_equal(_find_button(relabel_panel, "JourneyContinue").text,
		"Continue", "Continue reads English after a switch to en")
	TranslationServer.set_locale("ko")
	relabel.call("_refresh_journey_ui")
	_expect_equal(_find_button(relabel_panel, "JourneyContinue").text,
		"계속하기", "Continue reads Korean after a switch to ko")
	relabel.queue_free()
	await get_tree().process_frame
	TranslationServer.set_locale(original)


func _expect_journey_button_fits(
	panel: Control, button_name: String, locale: String
) -> void:
	var button: Button = _find_button(panel, button_name)
	var minimum: Vector2 = button.get_combined_minimum_size()
	_expect_true(minimum.x <= button.size.x + 0.5
		and minimum.y <= button.size.y + 0.5,
		"%s %s fits (%s / %s)" % [locale, button_name, minimum, button.size])


# --- translations ---------------------------------------------------------------
func _test_every_journey_key_exists_in_every_locale() -> void:
	var keys: Array[String] = ["JOURNEY_CONTINUE", "JOURNEY_NEW",
		"JOURNEY_CONFIRM_TITLE", "JOURNEY_CONFIRM_DESC", "JOURNEY_CONFIRM_ERASE",
		"JOURNEY_CONFIRM_KEEP", "JOURNEY_SAVE_FAILED", "JOURNEY_RESUME_FAILED",
		"JOURNEY_RESUMED", "RESULT_GATE_RETRY"]
	var original: String = TranslationServer.get_locale()
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		for key in keys:
			var text: String = tr(key)
			_expect_true(not text.is_empty() and text != key,
				"%s has a %s translation" % [key, locale])
	TranslationServer.set_locale(original)


# --- expectations -------------------------------------------------------------
func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_not_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected not ", expected)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _expect_false(value: bool, label: String) -> void:
	_expect_equal(value, false, label)
