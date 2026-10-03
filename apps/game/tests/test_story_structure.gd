extends Node

## 3.0.0 story structure: acts, the chronicle, per-hero voice, and the order they
## reach the player in.
##
## The story used to be lines with no shape. These pin the parts a regression
## could quietly break: which cycle opens which act, that the chronicle keeps
## what it is given and survives a bad file, that each hero really opens a run in
## their own voice, that every string exists in all five languages, and that an
## act card and its dialogue hand the paused game to each other without a frame
## of free movement between them.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const CARD_SCENE: PackedScene = preload("res://scenes/ui/act_card.tscn")
const PANEL_SCENE: PackedScene = preload("res://scenes/ui/chronicle_panel.tscn")
const TEST_PATH: String = "user://test_chronicle.json"
const LOCALES: Array[String] = ["en", "ko", "ja", "zh_CN", "zh_TW"]
const HEROES: Array[String] = ["dancer", "keeper", "knight", "eclipse", "sage"]

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	# The story UI pauses the tree; the test coroutine has to keep running.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_run.call_deferred()


func _run() -> void:
	_test_acts_by_cycle()
	_test_acts_match_episode_catalog()
	_test_every_key_exists_in_every_locale()
	_test_chronicle_persistence()
	_test_chronicle_survives_a_corrupt_file()
	_test_chronicle_moment_ids()
	_test_hero_voice()
	await _test_act_card_hand_off()
	await _test_chronicle_panel()
	await _test_arena_plays_card_then_dialogue()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Chronicle.path = Chronicle.DEFAULT_PATH
	Chronicle.forget_cache()
	if _failed > 0:
		printerr("story structure test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("story structure test passed — ", _checked, " case(s)")
	get_tree().quit(0)


# --- acts ---------------------------------------------------------------------
func _test_acts_by_cycle() -> void:
	var starts: Dictionary = {1: "debt", 3: "hunger", 6: "line", 9: "moonless"}
	for cycle in range(1, 15):
		var act: Dictionary = Acts.starting_at(cycle)
		if starts.has(cycle):
			_expect_equal(str(act.get("id", "")), str(starts[cycle]),
				"cycle %d opens act %s" % [cycle, starts[cycle]])
		else:
			_expect_true(act.is_empty(), "cycle %d does not open an act" % cycle)

	var membership: Dictionary = {
		0: "debt", 1: "debt", 2: "debt", 3: "hunger", 4: "hunger", 5: "hunger",
		6: "line", 7: "line", 8: "line", 9: "moonless", 10: "moonless", 60: "moonless",
	}
	for cycle: int in membership:
		_expect_equal(str(Acts.of_cycle(cycle)["id"]), str(membership[cycle]),
			"cycle %d belongs to %s" % [cycle, membership[cycle]])


## `Acts` resolves through the episode catalog now; the literal boundaries
## it keeps for direct iteration must agree with it, or the two drift apart.
func _test_acts_match_episode_catalog() -> void:
	var bounds: Array[Dictionary] = StoryEpisodes.act_boundaries()
	_expect_equal(bounds.size(), Acts.LIST.size(), "four act boundaries in the catalog")
	for index in bounds.size():
		_expect_equal(str(bounds[index]["id"]), str(Acts.LIST[index]["id"]),
			"catalog act %d id" % index)
		_expect_equal(int(bounds[index]["from"]), int(Acts.LIST[index]["from"]),
			"catalog act %d start" % index)
		_expect_equal(int(bounds[index]["number"]), int(Acts.LIST[index]["number"]),
			"catalog act %d number" % index)
	_expect_equal(StoryEpisodes.story_beats(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12],
		"catalog beats match the shipped story")


# --- translations -------------------------------------------------------------
## A raw key on screen is the failure that nothing else catches until someone
## plays that cycle in that language. Check every key the story touches.
func _test_every_key_exists_in_every_locale() -> void:
	var keys: Array[String] = []
	for act in Acts.LIST:
		var full: Dictionary = Acts.starting_at(int(act["from"]))
		for field in ["label", "title", "epigraph"]:
			keys.append(str(full[field]))
	for section in Chronicle.sections():
		keys.append(str(section["title"]))
		if not str(section.get("label", "")).is_empty():
			keys.append(str(section["label"]))
		for entry: Dictionary in section["entries"]:
			for key in entry["keys"]:
				keys.append(str(key))
	for hero in HEROES:
		for key in HeroVoice.open_keys(hero):
			keys.append(key)
		var moments: Dictionary = HeroVoice.HERO_LINES[hero]
		for moment in moments:
			for key in moments[moment]:
				keys.append(str(key))
	for key in ["ACT_TAP", "CHRONICLE_TITLE", "CHRONICLE_OPEN", "CHRONICLE_PROGRESS",
			"CHRONICLE_HINT", "CHRONICLE_LOCKED", "CHRONICLE_CLOSE", "HUD_WAVE",
			"VOICE_CYCLE_7", "VOICE_CYCLE_8"]:
		keys.append(key)

	var original: String = TranslationServer.get_locale()
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		for key in keys:
			var text: String = tr(key)
			_expect_true(not text.is_empty() and text != key,
				"%s has a %s translation" % [key, locale])
	TranslationServer.set_locale(original)


# --- chronicle ----------------------------------------------------------------
func _fresh_chronicle() -> void:
	Chronicle.path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Chronicle.forget_cache()


func _test_chronicle_persistence() -> void:
	_fresh_chronicle()
	# Forty since the six place memories joined the chronicle (Brief 006).
	_expect_equal(Chronicle.total_count(), 40, "forty entries to find")
	_expect_equal(Chronicle.unlocked_count(), 0, "a new save has found nothing")
	_expect_true(Chronicle.mark("story_1"), "first mark of an entry reports new")
	_expect_false(Chronicle.mark("story_1"), "marking again reports nothing new")
	_expect_true(Chronicle.has("story_1"), "a marked entry is found")
	_expect_false(Chronicle.has("story_2"), "an unmarked entry is not found")
	_expect_equal(Chronicle.unlocked_count(), 1, "one entry unlocked")

	# What was written must come back from disk, not from the cache.
	Chronicle.forget_cache()
	_expect_true(Chronicle.has("story_1"), "the entry survives a reload from disk")
	_expect_equal(Chronicle.unlocked_count(), 1, "the count survives a reload")

	_expect_false(Chronicle.mark("story_999"), "an unknown id is refused")
	Chronicle.forget_cache()
	_expect_false(Chronicle.has("story_999"), "a refused id was never written")
	_expect_false(FileAccess.get_file_as_string(TEST_PATH).contains("story_999"),
		"a refused id is not in the file")


## A reading log must never be able to break the game: a truncated or garbage
## file starts the chronicle empty instead of raising.
func _test_chronicle_survives_a_corrupt_file() -> void:
	Chronicle.path = TEST_PATH
	var handle: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	handle.store_string("{\"schema_version\": 1, \"seen\": [\"story_1\"")
	handle.close()
	Chronicle.forget_cache()
	_expect_equal(Chronicle.unlocked_count(), 0, "a corrupt file reads as empty")
	_expect_true(Chronicle.mark("story_2"), "a corrupt file can be written over")
	Chronicle.forget_cache()
	_expect_true(Chronicle.has("story_2"), "the rewritten file is readable")


func _test_chronicle_moment_ids() -> void:
	_expect_equal(Chronicle.id_for_moment("meet_drifter"), "meet_drifter",
		"a first-sight moment maps to its entry")
	_expect_equal(Chronicle.id_for_moment("meet_guardian_camp_siege"),
		"meet_guardian_camp_siege", "a guardian first-sight maps to its entry")
	_expect_equal(Chronicle.id_for_moment("beacon_first"), "",
		"an ordinary moment is not an entry")
	_expect_equal(Chronicle.id_for_moment("meet_nothing"), "",
		"an unknown first-sight is not an entry")


# --- hero voice ---------------------------------------------------------------
func _test_hero_voice() -> void:
	var original: String = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	for hero in HEROES:
		var voice: HeroVoice = HeroVoice.new()
		var own: String = tr("HVOICE_%s_BEACON_FIRST" % hero.to_upper())
		_expect_equal(voice.take("beacon_first", hero), own,
			"%s says their own line first" % hero)
		var second: String = voice.take("beacon_first", hero)
		_expect_true(second != own and not second.is_empty(),
			"%s falls back to the shared pool after their own line" % hero)
		_expect_equal(HeroVoice.open_keys(hero).size(), 2,
			"%s opens a run with two lines" % hero)
		_expect_true(tr(HeroVoice.open_keys(hero)[0]) != tr("STORY_OPEN_A"),
			"%s does not open with the Warden's words" % hero)

	# The Warden and unknown ids are the shared voice.
	var shared: HeroVoice = HeroVoice.new()
	var line: String = shared.take("beacon_first", "warden")
	_expect_true(line == tr("VOICE_BEACON_FIRST_1") or line == tr("VOICE_BEACON_FIRST_2"),
		"the Warden speaks the shared lines")
	_expect_true(HeroVoice.open_keys("warden").is_empty(), "the Warden has no override opening")
	_expect_true(HeroVoice.open_keys("nobody").is_empty(), "an unknown hero has no override opening")

	# The never-twice rule still holds with a hero override in play.
	var once: HeroVoice = HeroVoice.new()
	var heard: Dictionary = {}
	for _i in 6:
		var spoken: String = once.take("beacon_first", "dancer")
		if spoken.is_empty():
			continue
		_expect_false(heard.has(spoken), "no line is repeated inside one run")
		heard[spoken] = true
	_expect_equal(heard.size(), 3, "a hero's line plus the two shared lines, then quiet")
	TranslationServer.set_locale(original)


# --- act card -----------------------------------------------------------------
func _test_act_card_hand_off() -> void:
	var card: Control = CARD_SCENE.instantiate() as Control
	add_child(card)
	await get_tree().process_frame
	var finished: Array[int] = [0]
	card.finished.connect(func() -> void: finished[0] += 1)

	# `play()` calls `grab_focus()`, which warns on every act card if the control cannot
	# take focus. The warning is printed by the engine, so it has to be prevented here.
	_expect_equal(card.focus_mode, Control.FOCUS_ALL, "the card can take focus")
	card.call("play", Acts.of_cycle(3))
	_expect_true(bool(card.call("is_open")), "the card opens")
	_expect_true(get_tree().paused, "the card pauses the game while it is up")

	# A tap on the very frame the card opens is the tap that summoned it.
	var tap: InputEventMouseButton = InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	card.call("_try_dismiss", tap)
	_expect_true(bool(card.call("is_open")), "a tap before the card is armed does not dismiss it")

	await get_tree().create_timer(1.4).timeout
	card.call("_try_dismiss", tap)
	# Still paused during the fade-out, so nothing moves before the next screen.
	_expect_true(get_tree().paused, "the game stays paused through the fade-out")
	_expect_equal(finished[0], 0, "finished waits for the fade")
	await get_tree().create_timer(0.5).timeout
	_expect_equal(finished[0], 1, "finished fires once the card is gone")
	_expect_false(get_tree().paused, "the card releases the pause when it finishes")
	card.queue_free()
	await get_tree().process_frame


# --- chronicle page -----------------------------------------------------------
func _test_chronicle_panel() -> void:
	_fresh_chronicle()
	Chronicle.mark("story_open")
	Chronicle.mark("meet_wisp")
	var panel: Control = PANEL_SCENE.instantiate() as Control
	add_child(panel)
	await get_tree().process_frame
	var closed: Array[int] = [0]
	panel.closed.connect(func() -> void: closed[0] += 1)

	var original: String = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	panel.call("open")
	await get_tree().process_frame
	var list: VBoxContainer = panel.get_node(
		"Frame/Margin/Rows/Book/IndexScroll/IndexList") as VBoxContainer
	# Eight section headings plus one row per entry: nothing is hidden, so the
	# player can see how much is left.
	_expect_equal(list.get_child_count(), 8 + Chronicle.total_count(),
		"the index lists every section and every entry")
	var progress: Label = panel.get_node("Frame/Margin/Rows/Header/Progress") as Label
	_expect_equal(progress.text, "Recorded 2/40", "the page shows how many are recorded")

	# A heading that collapses to a sliver wraps one character per line (this
	# happened when the act label stopped expanding but kept autowrap on).
	await get_tree().process_frame
	var heading_row: Control = list.get_child(0).get_child(0) as Control
	var heading_title: Label = heading_row.get_child(heading_row.get_child_count() - 1) as Label
	_expect_true(heading_title.size.x >= 40.0 and heading_title.size.y <= 30.0,
		"a section heading lays out on one line")

	# The open page beside the index shows the selected memory at reading
	# size: first the first found entry, then whatever row is tapped.
	var page_title: Label = panel.get_node(
		"Frame/Margin/Rows/Book/Page/PageMargin/PageRows/PageTitle") as Label
	var page_body: VBoxContainer = panel.get_node(
		"Frame/Margin/Rows/Book/Page/PageMargin/PageRows/PageScroll/PageBody") \
		as VBoxContainer
	var page_state: Label = panel.get_node(
		"Frame/Margin/Rows/Book/Page/PageMargin/PageRows/PageState") as Label
	_expect_true(page_title != null and not page_title.text.is_empty()
		and page_title.text != "?",
		"the page opens on a found memory")
	_expect_true(page_body != null and page_body.get_child_count() >= 1,
		"the page carries the memory's lines")
	_expect_true(page_state != null and page_state.text.contains("/"),
		"the page numbers itself among all memories")
	var locked_row: Control = null
	var found_row: Control = null
	for child in list.get_children():
		if child is WorldFrame:
			if (child as WorldFrame).kind == "chip":
				locked_row = child
			else:
				found_row = child
	_expect_true(locked_row != null and found_row != null,
		"the index keeps found and undiscovered rows apart")
	if locked_row != null:
		var tap := InputEventMouseButton.new()
		tap.button_index = MOUSE_BUTTON_LEFT
		tap.pressed = true
		locked_row.emit_signal(&"gui_input", tap)
		_expect_equal(page_title.text, "?",
			"a locked row opens a locked page")
	if found_row != null:
		found_row.grab_focus()
		_expect_true(page_title.text != "?",
			"keyboard focus opens the focused memory")

	panel.call("close")
	_expect_equal(closed[0], 1, "closing the page reports it")
	TranslationServer.set_locale(original)
	panel.queue_free()
	await get_tree().process_frame


# --- the arena ----------------------------------------------------------------
## Cycle 3 opens Act II: the card first, then that cycle's dialogue, with the
## game paused across the whole handoff and both recorded in the chronicle.
func _test_arena_plays_card_then_dialogue() -> void:
	_fresh_chronicle()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.set_process(false)
	arena.set_physics_process(false)

	var dialogue: Control = arena.get_node("Ui/Dialogue") as Control
	_expect_false(arena.has_node("Ui/ActCard"), "no act card stands in the arena between acts")

	arena.set("_pending_story_cycle", 3)
	arena.call("_flush_cycle_story")
	await get_tree().process_frame
	var card: Control = arena.get_node_or_null("Ui/ActCard") as Control
	_expect_true(card != null, "cycle 3 builds the Act II card")
	if card == null:
		arena.queue_free()
		return
	_expect_true(bool(card.call("is_open")), "cycle 3 opens the Act II card")
	_expect_false(bool(dialogue.call("is_open")), "the dialogue waits behind the card")
	_expect_true(Chronicle.has("story_3"), "the cycle's story is recorded when it opens")

	# Arm and dismiss the card. The dialogue must open in the same handoff, with
	# the tree still paused when it does.
	card.set("_armed", true)
	var tap: InputEventMouseButton = InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	card.call("_try_dismiss", tap)
	await get_tree().create_timer(0.5).timeout
	_expect_true(not is_instance_valid(card) or not bool(card.call("is_open")), "the card is closed")
	_expect_true(bool(dialogue.call("is_open")), "the dialogue opens right after the card")
	_expect_true(get_tree().paused, "the game is paused for the dialogue")

	# A cycle that opens no act goes straight to its dialogue.
	dialogue.call("_close")
	await get_tree().create_timer(0.3).timeout
	arena.set("_pending_story_cycle", 4)
	arena.call("_flush_cycle_story")
	await get_tree().process_frame
	_expect_false(arena.has_node("Ui/ActCard"), "cycle 4 opens no act card")
	_expect_true(bool(dialogue.call("is_open")), "cycle 4 goes straight to its dialogue")
	_expect_true(Chronicle.has("story_4"), "cycle 4 is recorded")

	dialogue.call("_close")
	get_tree().paused = false
	arena.queue_free()
	await get_tree().process_frame


# --- expectations -------------------------------------------------------------
func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _expect_false(value: bool, label: String) -> void:
	_expect_equal(value, false, label)
