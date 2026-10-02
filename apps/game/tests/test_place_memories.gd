extends Node

## Place memories: the six motifs, their discovery lines, and the road home.
##
## Runs the real arena. The first beacon of each terrain lights its motif and
## speaks its memory once per run; repeats and fresh runs still restore the
## motif without spamming the line. Fork gates name the waiting memory without
## losing the guardian or omen they already named. Old chronicle records
## survive the new entries. The official win needs no particular terrain, and
## every ending's prose matches the real state.
##
## A discovery owns the voice strip for a readable interval: the fork and
## guardian lines that fire on the same beacon wait instead of replacing it in
## the same frame, and a discovery suppressed by a modal still records its
## chronicle entry and plays once the screen is clear.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_panel.tscn")
const CHOICE_SCENE: PackedScene = preload("res://scenes/ui/run_choice_panel.tscn")
const TEST_PATH: String = "user://test_place_chronicle.json"
const LOCALES: Array[String] = ["en", "ko", "ja", "zh_CN", "zh_TW"]
const UI_FONT: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Multilingual.tres")
const UI_FONT_BOLD: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres")

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	var original: String = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_test_place_memory_data()
	_test_chronicle_places()
	await _test_first_beacon_real_path()
	await _test_all_six_and_fork_clues()
	await _test_fresh_run_restores()
	_test_persistence_with_old_records()
	await _test_no_popup_during_modal_or_transition()
	await _test_fork_preserves_discovery_real_path()
	await _test_guardian_preserves_discovery_real_path()
	await _test_all_six_real_path()
	await _test_repeat_run_real_path()
	await _test_suppressed_discovery_replays_real_path()
	await _test_endings()
	await _test_nari_resolution()
	await _test_road_geometry()
	await _test_story_not_gated_on_places()
	_test_five_languages_fit()
	await _test_budget_and_teardown()
	TranslationServer.set_locale(original)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Chronicle.path = Chronicle.DEFAULT_PATH
	Chronicle.forget_cache()
	get_tree().paused = false
	if _failed > 0:
		printerr("place-memories test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("place-memories test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _new_arena() -> Node2D:
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.call("debug_shield")
	return arena


func _drop(arena: Node2D) -> void:
	arena.queue_free()
	get_tree().paused = false
	await get_tree().process_frame


func _fresh_chronicle() -> void:
	Chronicle.path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Chronicle.forget_cache()


func _voice_text(arena: Node2D) -> String:
	var panel: Control = arena.get("_voice_panel") as Control
	if panel == null:
		return ""
	var label: Label = panel.get_node_or_null("Box/Row/Text") as Label
	return label.text if label != null else ""


## Mark every spirit kind already seen, so ambient spawns stay off the strip
## while a multi-second delivery is awaited. The Dictionary is shared by
## reference, so this edits the arena's own set.
func _quiet_first_sights(arena: Node2D) -> void:
	var seen: Dictionary = arena.get("_seen_spirits") as Dictionary
	for kind in ["drifter", "ember", "caster", "weaver", "stalker", "swarm", "wisp"]:
		seen["meet_" + kind] = true


## Spend a voice moment's whole pool so it can never take the strip mid-test.
func _spend_moment(arena: Node2D, moment: String) -> void:
	var voice: HeroVoice = arena.get("_voice") as HeroVoice
	for _take in 6:
		if voice.take(moment).is_empty():
			return


# --- data -------------------------------------------------------------------
func _test_place_memory_data() -> void:
	_expect_equal(PlaceMemory.TERRAIN_IDS.size(), 6, "six terrains have memories")
	_expect_equal(PlaceMemory.terrain_id(0), "forest", "terrain 0 is the forest")
	_expect_equal(PlaceMemory.terrain_id(5), "ruins", "terrain 5 is the ruins")
	_expect_equal(PlaceMemory.terrain_id(6), "", "terrain 6 is out of range")
	_expect_equal(PlaceMemory.terrain_id(-1), "", "terrain -1 is out of range")
	_expect_equal(PlaceMemory.chronicle_id(2), "place_camp",
		"the camp chronicle id")
	_expect_equal(PlaceMemory.chronicle_id(9), "", "no chronicle id out of range")
	_expect_equal(PlaceMemory.name_key(1), "PLACE_NAME_FIELD", "the field name key")
	_expect_equal(PlaceMemory.clue_key(4), "PLACE_CLUE_MARSH", "the marsh clue key")
	_expect_equal(PlaceMemory.memory_key(3), "PLACE_MEMORY_FROST",
		"the frost memory key")
	_expect_equal(Chronicle.id_for_moment("place_forest"), "place_forest",
		"a place moment maps to its entry")
	_expect_equal(Chronicle.id_for_moment("place_nowhere"), "",
		"an unknown place is not an entry")


func _test_chronicle_places() -> void:
	_fresh_chronicle()
	_expect_equal(Chronicle.total_count(), 40, "forty entries to find")
	_expect_equal(Chronicle.sections().size(), 8, "eight sections with Places")
	_expect_true(Chronicle.mark("place_forest"), "a place marks once")
	_expect_false(Chronicle.mark("place_forest"), "a place never marks twice")
	Chronicle.forget_cache()
	_expect_true(Chronicle.has("place_forest"), "a place survives a reload")


# --- the real path ----------------------------------------------------------
## Cycle 1 walks the forest first: lighting its beacon must light the motif,
## speak the memory, and record it — instead of the routine beacon line.
func _test_first_beacon_real_path() -> void:
	_fresh_chronicle()
	var arena: Node2D = await _new_arena()
	_expect_equal(arena.call("_terrain_at", 0), 0, "cycle 1 opens in the forest")
	var motif: Node2D = arena.get("_motif") as Node2D
	_expect_true(motif != null, "a motif stands in the arena")
	_expect_equal(motif.get_child_count(), 1, "the motif is one node plus its sprite")
	_expect_false(bool(motif.call("is_lit")), "the motif starts dim")
	var beacon: Node2D = (arena.get("_beacons") as Array)[0] as Node2D
	var gap: float = motif.position.distance_to(beacon.position)
	_expect_true(gap > 20.0 and gap < 160.0,
		"the motif stands beside the clearing, not underfoot (%d px)" % int(gap))
	_expect_true(Room.PLAY.has_point(motif.position), "the motif stands in play")

	arena.call("debug_light_next_beacon")
	await get_tree().process_frame
	_expect_true(bool(motif.call("is_lit")), "the first beacon lights its motif")
	_expect_true(Chronicle.has("place_forest"), "the restoration is recorded")
	_expect_equal(_voice_text(arena), tr("PLACE_MEMORY_FOREST"),
		"the strip speaks the memory, not the beacon line")
	var spent: Dictionary = (arena.get("_voice") as HeroVoice).get("_spent") as Dictionary
	_expect_false(spent.has("VOICE_BEACON_FIRST_1") or spent.has("VOICE_BEACON_FIRST_2"),
		"the beacon moment stays unspent for the next beacon")

	# A second restoration in the same terrain restores the motif but says nothing new.
	_expect_false(bool(arena.call("_maybe_show_place_memory", 0)),
		"the same terrain does not speak twice in one run")
	_expect_false(bool(arena.call("_restore_place")),
		"a repeat restoration reports no new line")
	_expect_true(bool(motif.call("is_lit")), "but the motif still shows lit")
	await _drop(arena)


## Every terrain has its own line and entry, and a fork gate names the memory
## waiting behind it while keeping the guardian it already named.
func _test_all_six_and_fork_clues() -> void:
	_fresh_chronicle()
	var arena: Node2D = await _new_arena()
	for terrain in 6:
		var shown: bool = bool(arena.call("_maybe_show_place_memory", terrain))
		_expect_true(shown, "terrain %d speaks its memory" % terrain)
		_expect_equal(_voice_text(arena), tr(PlaceMemory.memory_key(terrain)),
			"terrain %d says its own line" % terrain)
		_expect_true(Chronicle.has(PlaceMemory.chronicle_id(terrain)),
			"terrain %d is recorded" % terrain)
	# The motif follows whatever terrain it is shown.
	var motif: Node2D = arena.get("_motif") as Node2D
	motif.call("show_terrain", 5)
	_expect_equal(int(motif.call("terrain")), 5, "the motif shows the ruins")
	_expect_false(bool(motif.call("is_lit")), "a new zone starts dim")
	motif.call("set_lit", true)
	_expect_true(bool(motif.call("is_lit")), "and lights on restoration")
	await _drop(arena)

	# Alternate routes: the clue rides the gate, the guardian stays on it.
	var forked: Node2D = await _new_arena()
	var run_seed: int = 4_242_001
	forked.set("_forks_enabled", true)
	forked.set("_run_seed", run_seed)
	forked.set("_cycle", 2)
	var start: int = Expedition.start_terrain(run_seed, 2, 0)
	forked.set("_route", [start, -1, -1] as Array[int])
	forked.call("_change_cycle_world")
	await get_tree().process_frame
	forked.call("debug_light_next_beacon")
	await get_tree().create_timer(0.2, true).timeout
	var options: Array = forked.get("_fork_options") as Array
	_expect_equal(options.size(), 2, "cycle 2 opens a fork")
	var gates: Array[Node2D] = [
		forked.get("_gate") as Node2D, forked.get("_gate_b") as Node2D]
	for index in 2:
		var label: Label = (gates[index] as Node2D).get("_label") as Label
		var terrain: int = int(options[index])
		_expect_true(label.text.contains(tr(PlaceMemory.clue_key(terrain))),
			"gate %d hints the waiting memory" % index)
	# On the way to the last zone the guardian stays named too.
	forked.call("_on_gate_entered", 0)
	await get_tree().process_frame
	while bool(forked.get("_transitioning")) and is_instance_valid(forked):
		await get_tree().process_frame
	forked.call("debug_light_next_beacon")
	await get_tree().create_timer(0.2, true).timeout
	var last_options: Array = forked.get("_fork_options") as Array
	_expect_equal(last_options.size(), 2, "the second beacon opens a fork too")
	gates = [forked.get("_gate") as Node2D, forked.get("_gate_b") as Node2D]
	for index in 2:
		var label: Label = (gates[index] as Node2D).get("_label") as Label
		var terrain: int = int(last_options[index])
		var kind: SpiritKind = load(
			str(forked.call("_guardian_path_for", terrain))) as SpiritKind
		_expect_true(label.text.contains(tr(kind.display_name)),
			"gate %d still names its guardian" % index)
		_expect_true(label.text.contains(tr(PlaceMemory.clue_key(terrain))),
			"gate %d still hints its memory" % index)
	await _drop(forked)


## A new run restores visibly even when the chronicle already holds the place.
func _test_fresh_run_restores() -> void:
	_fresh_chronicle()
	_expect_true(Chronicle.mark("place_forest"), "an earlier run recorded the forest")
	var arena: Node2D = await _new_arena()
	_expect_false(bool((arena.get("_motif") as Node2D).call("is_lit")),
		"a fresh run starts dim")
	arena.call("debug_light_next_beacon")
	await get_tree().process_frame
	_expect_true(bool((arena.get("_motif") as Node2D).call("is_lit")),
		"the fresh run still lights the motif")
	_expect_equal(_voice_text(arena), tr("PLACE_MEMORY_FOREST"),
		"and still speaks the memory")
	await _drop(arena)


# --- persistence ------------------------------------------------------------
func _test_persistence_with_old_records() -> void:
	Chronicle.path = TEST_PATH
	var handle: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	handle.store_string(
		'{"schema_version": 1, "seen": ["story_1", "meet_wisp", "epitaph_lose"]}')
	handle.close()
	Chronicle.forget_cache()
	_expect_true(Chronicle.has("story_1"), "an old story record loads")
	_expect_true(Chronicle.has("meet_wisp"), "an old first-sight loads")
	_expect_true(Chronicle.has("epitaph_lose"), "an old ending loads")
	_expect_true(Chronicle.mark("place_marsh"), "a new place marks beside them")
	Chronicle.forget_cache()
	_expect_true(Chronicle.has("story_1"), "the story survives the new mark")
	_expect_true(Chronicle.has("place_marsh"), "the new place survives a reload")
	_expect_equal(Chronicle.unlocked_count(), 4, "old and new count together")


# --- quiet when it must be --------------------------------------------------
func _test_no_popup_during_modal_or_transition() -> void:
	_fresh_chronicle()
	var arena: Node2D = await _new_arena()
	var terrain: int = 3
	arena.set("_transitioning", true)
	_expect_false(bool(arena.call("_maybe_show_place_memory", terrain)),
		"no discovery during a transition")
	arena.set("_transitioning", false)
	arena.set("_capture_progress_frozen", true)
	_expect_false(bool(arena.call("_maybe_show_place_memory", terrain)),
		"no discovery during capture")
	arena.set("_capture_progress_frozen", false)

	var dialogue: Control = arena.get_node("Ui/Dialogue") as Control
	dialogue.play(arena.call("_hero_for_run"), ["a held line"] as Array[String])
	_expect_true(bool(dialogue.call("is_open")), "the dialogue opens")
	_expect_false(bool(arena.call("_maybe_show_place_memory", terrain)),
		"no discovery over dialogue")
	dialogue.call("_close")
	await get_tree().create_timer(0.3, true).timeout

	var choice: Control = arena.get("_run_choice") as Control
	choice.open_cycle(1)
	_expect_false(bool(arena.call("_maybe_show_place_memory", terrain)),
		"no discovery over a choice")
	choice.close_without_choice()

	var relic: Control = arena.get("_relic") as Control
	relic.visible = true
	_expect_false(bool(arena.call("_maybe_show_place_memory", terrain)),
		"no discovery over loot")
	relic.visible = false

	# None of the blocks consumed the memory.
	_expect_true(bool(arena.call("_maybe_show_place_memory", terrain)),
		"the memory still plays once the screen is clear")
	_expect_false(bool(arena.call("_maybe_show_place_memory", terrain)),
		"and then stays quiet")
	await _drop(arena)


# --- the guard through the real paths ---------------------------------------
## The first fork opens on the same beacon that restores a place. The discovery
## must stay readable while the gates carry the route, and the fork line must
## still arrive — taken at once, spoken after the guard.
func _test_fork_preserves_discovery_real_path() -> void:
	_fresh_chronicle()
	var arena: Node2D = await _new_arena()
	_quiet_first_sights(arena)
	_spend_moment(arena, "moonfire")
	_spend_moment(arena, "swarm")
	var run_seed: int = 4_242_001
	arena.set("_forks_enabled", true)
	arena.set("_run_seed", run_seed)
	arena.set("_cycle", 2)
	var start: int = Expedition.start_terrain(run_seed, 2, 0)
	arena.set("_route", [start, -1, -1] as Array[int])
	arena.call("_change_cycle_world")
	await get_tree().process_frame
	arena.call("debug_light_next_beacon")
	await get_tree().process_frame
	var memory: String = tr(PlaceMemory.memory_key(start))
	_expect_equal(_voice_text(arena), memory,
		"the discovery survives the frame the fork opens")
	_expect_true(Chronicle.has(PlaceMemory.chronicle_id(start)),
		"the restoration is recorded at once")
	var spent: Dictionary = (arena.get("_voice") as HeroVoice).get("_spent") as Dictionary
	_expect_true(spent.has("VOICE_FORK_1") or spent.has("VOICE_FORK_2"),
		"the fork line is taken at once, not after the wait")
	var options: Array = arena.get("_fork_options") as Array
	_expect_equal(options.size(), 2, "the fork still opens two gates")
	var gates: Array[Node2D] = [
		arena.get("_gate") as Node2D, arena.get("_gate_b") as Node2D]
	for index in 2:
		var label: Label = (gates[index] as Node2D).get("_label") as Label
		var terrain: int = int(options[index])
		_expect_true(label.text.begins_with(
			TranslationServer.translate(str(Expedition.TERRAINS[terrain]["name"]))),
			"gate %d keeps its terrain name while the discovery reads" % index)
		_expect_true(label.text.contains(tr(PlaceMemory.clue_key(terrain))),
			"gate %d keeps its memory hint while the discovery reads" % index)
	await get_tree().create_timer(1.0, true).timeout
	_expect_equal(_voice_text(arena), memory,
		"the discovery is still up a second later")
	await get_tree().create_timer(3.5, true).timeout
	var forked: String = _voice_text(arena)
	_expect_true(forked == tr("VOICE_FORK_1") or forked == tr("VOICE_FORK_2"),
		"the fork line arrives after the discovery had its interval")
	await _drop(arena)


## The classic third beacon restores a place and summons the guardian in the
## same frame. The discovery must stay readable; the banner still names the
## guardian and its rule at once, and the first-meet line follows.
func _test_guardian_preserves_discovery_real_path() -> void:
	_fresh_chronicle()
	var arena: Node2D = await _new_arena()
	_quiet_first_sights(arena)
	_spend_moment(arena, "call_dark")
	_spend_moment(arena, "guardian_down")
	_spend_moment(arena, "swarm")
	for _step in 3:
		arena.call("debug_light_next_beacon")
		await get_tree().create_timer(0.15, true).timeout
		if bool(arena.get("_escape_active")):
			arena.call("_on_gate_entered")
			while bool(arena.get("_transitioning")) and is_instance_valid(arena):
				await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var terrain: int = int(arena.call("_terrain_at", 2))
	var memory: String = tr(PlaceMemory.memory_key(terrain))
	_expect_equal(_voice_text(arena), memory,
		"the discovery survives the frame the guardian is summoned")
	var guardian: Node2D = arena.get("_guardian") as Node2D
	_expect_true(guardian != null and is_instance_valid(guardian),
		"the guardian still arrives")
	_expect_true(guardian != null and guardian.get("kind") != null,
		"with the kind its telegraphs come from")
	var banner: Label = (arena.get("_hud") as Control).get("_banner") as Label
	var title: String = str(arena.get("_guardian_title"))
	_expect_true(not title.is_empty(), "the guardian has a name")
	_expect_true(banner.text.contains(title),
		"the banner names the guardian at once")
	var moment: String = "meet_" + str(arena.call("_guardian_resource_path")) \
		.get_file().get_basename()
	_expect_true(Chronicle.has(moment),
		"the first meeting is recorded before its line speaks")
	await get_tree().create_timer(1.0, true).timeout
	_expect_equal(_voice_text(arena), memory,
		"the discovery is still up a second into the duel")
	await get_tree().create_timer(3.5, true).timeout
	_expect_equal(_voice_text(arena), tr((HeroVoice.LINES[moment] as Array)[0]),
		"the first-meet line arrives after the discovery had its interval")
	await _drop(arena)


## Every terrain restores through the real beacon path: motif lights, line
## speaks, entry records. One fresh arena per terrain.
func _test_all_six_real_path() -> void:
	_fresh_chronicle()
	for terrain in 6:
		var arena: Node2D = await _new_arena()
		_quiet_first_sights(arena)
		arena.set("_cycle", 1)
		arena.set("_route", [terrain, -1, -1] as Array[int])
		arena.call("_change_cycle_world")
		await get_tree().process_frame
		arena.call("debug_light_next_beacon")
		await get_tree().process_frame
		var motif: Node2D = arena.get("_motif") as Node2D
		_expect_true(bool(motif.call("is_lit")),
			"terrain %d lights its motif on the real path" % terrain)
		_expect_true(Room.PLAY.has_point(motif.position),
			"terrain %d keeps its motif in play" % terrain)
		_expect_equal(_voice_text(arena), tr(PlaceMemory.memory_key(terrain)),
			"terrain %d speaks its memory on the real path" % terrain)
		_expect_true(Chronicle.has(PlaceMemory.chronicle_id(terrain)),
			"terrain %d records its entry on the real path" % terrain)
		await _drop(arena)


## The same terrain twice in one run: the motif restores both times but the
## line plays once, and the run counts one place.
func _test_repeat_run_real_path() -> void:
	_fresh_chronicle()
	var arena: Node2D = await _new_arena()
	_quiet_first_sights(arena)
	arena.set("_route", [0, 0, 2] as Array[int])
	arena.call("debug_light_next_beacon")
	await get_tree().process_frame
	var memory: String = tr("PLACE_MEMORY_FOREST")
	_expect_equal(_voice_text(arena), memory, "the first forest beacon speaks")
	arena.call("_on_gate_entered")
	while bool(arena.get("_transitioning")) and is_instance_valid(arena):
		await get_tree().process_frame
	_expect_equal(int(arena.call("_terrain_at", 1)), 0,
		"the forced route returns to the forest")
	await get_tree().create_timer(1.3, true).timeout
	var motif: Node2D = arena.get("_motif") as Node2D
	_expect_false(bool(motif.call("is_lit")), "the new zone starts dim again")
	arena.call("debug_light_next_beacon")
	await get_tree().process_frame
	_expect_true(bool(motif.call("is_lit")), "the repeat still lights the motif")
	_expect_true(_voice_text(arena) != memory,
		"the repeat does not speak the line again")
	_expect_true(
		_voice_text(arena) == tr("VOICE_BEACON_FIRST_1")
		or _voice_text(arena) == tr("VOICE_BEACON_FIRST_2")
		or _voice_text(arena) == tr("VOICE_BEACON_MID_1")
		or _voice_text(arena) == tr("VOICE_BEACON_MID_2"),
		"the repeat speaks the routine beacon line instead")
	_expect_equal((arena.get("_places_seen_run") as Dictionary).size(), 1,
		"the run counts one forest")
	await _drop(arena)


## A discovery suppressed on the real path is not marked seen and never loses
## its entry; it plays once the screen is clear.
func _test_suppressed_discovery_replays_real_path() -> void:
	_fresh_chronicle()
	var arena: Node2D = await _new_arena()
	_quiet_first_sights(arena)
	var dialogue: Control = arena.get_node("Ui/Dialogue") as Control
	dialogue.play(arena.call("_hero_for_run"), ["a held line"] as Array[String])
	arena.call("debug_light_next_beacon")
	await get_tree().process_frame
	var motif: Node2D = arena.get("_motif") as Node2D
	_expect_true(bool(motif.call("is_lit")), "a modal cannot stop the motif")
	_expect_true(Chronicle.has("place_forest"),
		"the suppressed discovery keeps its entry")
	_expect_false((arena.get("_places_seen_run") as Dictionary).has("forest"),
		"but it is not marked seen until it plays")
	_expect_true(_voice_text(arena) != tr("PLACE_MEMORY_FOREST"),
		"and it stays off the strip over the modal")
	dialogue.call("_close")
	await get_tree().create_timer(0.3, true).timeout
	await get_tree().create_timer(2.5, true).timeout
	_expect_equal(_voice_text(arena), tr("PLACE_MEMORY_FOREST"),
		"the queued discovery plays once the screen is clear")
	_expect_true((arena.get("_places_seen_run") as Dictionary).has("forest"),
		"and only then is it marked seen")
	await _drop(arena)

	# Capture suppresses the record too: a staged shot must not write the log.
	_fresh_chronicle()
	var staged: Node2D = await _new_arena()
	_quiet_first_sights(staged)
	staged.set("_capture_progress_frozen", true)
	staged.call("debug_light_next_beacon")
	await get_tree().process_frame
	_expect_true(bool((staged.get("_motif") as Node2D).call("is_lit")),
		"capture still lights the motif")
	_expect_false(Chronicle.has("place_forest"),
		"capture writes no entry while frozen")
	_expect_false((staged.get("_places_seen_run") as Dictionary).has("forest"),
		"and marks nothing seen")
	staged.set("_capture_progress_frozen", false)
	await get_tree().create_timer(2.5, true).timeout
	_expect_equal(_voice_text(staged), tr("PLACE_MEMORY_FOREST"),
		"the queued discovery plays after the unfreeze")
	_expect_true(Chronicle.has("place_forest"), "and records its entry then")
	await _drop(staged)


# --- endings ----------------------------------------------------------------
func _ending_score(cycles: int) -> Score:
	var score := Score.new()
	score.cycles = cycles
	score.beacons = 3
	score.survived = 120.0
	score.level = 5
	score.kills = 40
	score.shards = 10
	return score


func _test_endings() -> void:
	_fresh_chronicle()
	# The official win: the road burns, the window is lit.
	var win: Control = RESULT_SCENE.instantiate() as Control
	add_child(win)
	win.show_result(true, _ending_score(8), false, false, 3)
	await get_tree().process_frame
	_expect_equal((win.get_node("Title") as Label).text, tr("RESULT_WIN"),
		"cycle 8 keeps the victory title")
	_expect_equal((win.get_node("Epitaph") as Label).text,
		tr("STORY_EPITAPH_WIN"), "the win answers Nari's message")
	_expect_true((win.get_node("Road") as Label).visible, "the win shows the road")
	_expect_true((win.get_node("Road") as Label).text.contains("3"),
		"the road counts restored places")
	var lit: AtlasTexture = (win.get_node("Window") as TextureRect).texture as AtlasTexture
	_expect_true((win.get_node("Window") as TextureRect).visible,
		"the win lights the window")
	_expect_equal(lit.region.position.x, 32.0, "the lit cell answers the kettle")
	win.queue_free()
	await get_tree().process_frame

	# An early return: safe, dim, and invited back.
	var early: Control = RESULT_SCENE.instantiate() as Control
	add_child(early)
	early.show_result(true, _ending_score(1), false, false, 1)
	await get_tree().process_frame
	_expect_equal((early.get_node("Title") as Label).text, tr("RESULT_ESCAPE"),
		"an early return keeps its title")
	var dim: AtlasTexture = (early.get_node("Window") as TextureRect).texture as AtlasTexture
	_expect_true((early.get_node("Window") as TextureRect).visible,
		"the early return shows the waiting window")
	_expect_equal(dim.region.position.x, 0.0, "dim, not lit: Nari is not home yet")
	early.queue_free()
	await get_tree().process_frame

	# Defeat: compassionate, no window, still a road count.
	var lost: Control = RESULT_SCENE.instantiate() as Control
	add_child(lost)
	lost.show_result(false, _ending_score(0), false, false, 0)
	await get_tree().process_frame
	_expect_equal((lost.get_node("Title") as Label).text, tr("RESULT_LOSE"),
		"defeat keeps its title")
	_expect_false((lost.get_node("Window") as TextureRect).visible,
		"defeat shows no window")
	_expect_true((lost.get_node("Road") as Label).visible,
		"defeat still states the road")
	lost.queue_free()
	await get_tree().process_frame

	# The win needs no particular terrain.
	var bare: Control = RESULT_SCENE.instantiate() as Control
	add_child(bare)
	bare.show_result(true, _ending_score(8), false, false, 0)
	await get_tree().process_frame
	_expect_equal((bare.get_node("Title") as Label).text, tr("RESULT_WIN"),
		"cycle 8 wins with zero places restored")
	bare.queue_free()
	await get_tree().process_frame

	# Callers that predate the road hide both additions.
	var legacy: Control = RESULT_SCENE.instantiate() as Control
	add_child(legacy)
	legacy.show_result(false, _ending_score(0), false, false)
	await get_tree().process_frame
	_expect_false((legacy.get_node("Road") as Label).visible,
		"no count hides the road")
	_expect_false((legacy.get_node("Window") as TextureRect).visible,
		"no count hides the window")
	legacy.queue_free()
	await get_tree().process_frame


## Eight completed cycles resolve Nari's promise out loud: her signal answers,
## she reaches home, and the kettle is warm. Both the cash-out ending and the
## continue choice say so, in all five languages; earlier return and defeat
## never claim she was rescued.
func _test_nari_resolution() -> void:
	var names: Dictionary = {
		"en": "Nari", "ko": "나리", "ja": "ナリ",
		"zh_CN": "娜莉", "zh_TW": "娜莉",
	}
	var kettles: Dictionary = {
		"en": "kettle", "ko": "주전자", "ja": "やかん",
		"zh_CN": "水壶", "zh_TW": "水壺",
	}
	# Homecoming words that must never appear before the road is complete.
	# The player's own return ("your return", "귀환", "帰り", "归来") is not
	# among them: only Nari coming home counts.
	var homecomings: Dictionary = {
		"en": ["is home", "came home"],
		"ko": ["돌아왔"],
		"ja": ["帰ってきた", "帰った"],
		"zh_CN": ["回家", "到家"],
		"zh_TW": ["回家", "到家"],
	}
	var current: String = TranslationServer.get_locale()
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		var name: String = str(names[locale])
		# The cash-out ending on the result card.
		var panel: Control = RESULT_SCENE.instantiate() as Control
		add_child(panel)
		panel.show_result(true, _ending_score(8), false, false, 4)
		await get_tree().process_frame
		var epitaph: Label = panel.get_node("Epitaph") as Label
		_expect_true(epitaph.text.contains(name),
			"%s win names Nari coming home" % locale)
		_expect_true(epitaph.text.contains(str(kettles[locale])),
			"%s win pays off the kettle" % locale)
		_expect_equal(epitaph.get_line_count(), 1,
			"%s win keeps one epitaph line" % locale)
		panel.queue_free()
		await get_tree().process_frame
		# The continue choice at eight completed cycles.
		var choice: Control = CHOICE_SCENE.instantiate() as Control
		add_child(choice)
		choice.open_cycle(8)
		await get_tree().process_frame
		await get_tree().process_frame
		var title: Label = choice.get_node(
			"Center/Frame/Content/Rows/Title") as Label
		var subtitle: Label = choice.get_node(
			"Center/Frame/Content/Rows/Subtitle") as Label
		_expect_equal(title.text, tr("CYCLE_CHOICE_MAP_BEYOND_TITLE"),
			"%s choice carries the resolution title" % locale)
		_expect_true(title.text.to_upper().contains(name.to_upper()),
			"%s choice names Nari coming home" % locale)
		_expect_true(subtitle.text.contains(str(kettles[locale])),
			"%s choice pays off the kettle" % locale)
		_expect_true(tr("CHRONICLE_ENDING_WIN").contains(name),
			"%s chronicle ending agrees" % locale)
		choice.close_without_choice()
		choice.queue_free()
		await get_tree().process_frame
		# Earlier return and defeat: the lamp waits, nobody is rescued.
		for key in ["STORY_EPITAPH_ESCAPE", "STORY_EPITAPH_LOSE"]:
			var line: String = tr(key)
			_expect_false(line.contains(name),
				"%s %s never names her home" % [locale, key])
			for word in homecomings[locale] as Array:
				_expect_false(line.contains(str(word)),
					"%s %s never claims the rescue (%s)" % [locale, key, word])
	TranslationServer.set_locale(current)


## The road line gets a real, nonoverlapping place on the result card: every
## label's text fits its own box, and the boxes run in order with air between
## them. Win, early return, defeat, deep runs and large scores, five languages.
func _test_road_geometry() -> void:
	get_tree().root.size = Vector2i(808, 360)
	get_tree().root.content_scale_size = Vector2i(808, 360)
	var cases: Array = [
		["win", true, 8, 4],
		["early", true, 1, 1],
		["defeat", false, 0, 0],
		["deep win", true, 12, 6],
		["deep defeat", false, 123, 2],
	]
	var current: String = TranslationServer.get_locale()
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		for entry in cases:
			var panel: Control = RESULT_SCENE.instantiate() as Control
			add_child(panel)
			var score: Score = _ending_score(int(entry[2]))
			if str(entry[0]) == "deep defeat":
				score.beacons = 3
				score.survived = 3599.0
				score.level = 40
				score.kills = 99999
				score.shards = 999
			panel.show_result(
				bool(entry[1]), score, false, false, int(entry[3]))
			await get_tree().process_frame
			panel.call("_skip_reveal")
			await get_tree().create_timer(0.3, true).timeout
			_check_road_case(panel, locale, str(entry[0]),
				int(entry[2]), int(entry[3]))
			panel.queue_free()
			await get_tree().process_frame
	TranslationServer.set_locale(current)


func _check_road_case(
		panel: Control, locale: String, name: String, cycles: int,
		places: int) -> void:
	var tag: String = "%s %s" % [locale, name]
	var road: Label = panel.get_node("Road") as Label
	_expect_true(road.visible, "%s shows its road" % tag)
	_expect_equal(road.text,
		tr("RESULT_ROAD") % [tr("HUD_WAVE") % maxi(cycles, 1), places],
		"%s road states the real reach and count" % tag)
	var detail: Label = panel.get_node("Detail") as Label
	var hint: Label = panel.get_node("Hint") as Label
	var goal: Label = panel.get_node("Goal") as Label
	var epitaph: Label = panel.get_node("Epitaph") as Label
	var title: Label = panel.get_node("Title") as Label
	for labeled in [
		[detail, "score table"], [road, "road"], [hint, "record line"],
		[goal, "purchase goal"], [epitaph, "closing line"],
		[title, "title"],
	]:
		var box: Control = labeled[0] as Control
		var minimum: Vector2 = box.get_combined_minimum_size()
		_expect_true(
			minimum.x <= box.size.x + 0.5 and minimum.y <= box.size.y + 0.5,
			"%s %s fits its box (%s / %s)" % [
				tag, str(labeled[1]), minimum, box.size])
	var detail_rect: Rect2 = detail.get_global_rect()
	var road_rect: Rect2 = road.get_global_rect()
	var hint_rect: Rect2 = hint.get_global_rect()
	_expect_true(detail_rect.end.y <= road_rect.position.y,
		"%s score table clears the road (%s / %s)" % [
			tag, detail_rect, road_rect])
	_expect_true(road_rect.end.y <= hint_rect.position.y,
		"%s road clears the record line (%s / %s)" % [
			tag, road_rect, hint_rect])
	var actions: Control = panel.get_node("Actions") as Control
	var card: Control = panel.get_node("Card") as Control
	_expect_true(
		actions.get_global_rect().end.y <= card.get_global_rect().end.y,
		"%s buttons stay on the card" % tag)
	if cycles > 8:
		_expect_true(epitaph.text.contains(tr("HUD_DEPTH") % Expedition.depth(cycles)),
			"%s closing line keeps its Depth caption" % tag)
		_expect_false(road.text.contains(tr("HUD_DEPTH") % Expedition.depth(cycles)),
			"%s road never repeats the Depth" % tag)


## The main arc runs on cycles alone: beats play and the win lands with no
## place ever restored.
func _test_story_not_gated_on_places() -> void:
	_fresh_chronicle()
	var arena: Node2D = await _new_arena()
	arena.set("_cycle", 1)
	_expect_equal((arena.call("_story_lines", 1) as Array).size(), 4,
		"cycle 1 opens with its promise and its ground")
	arena.set("_cycle", 8)
	_expect_false((arena.call("_story_lines", 8) as Array).is_empty(),
		"cycle 8 speaks with no places restored")
	arena.set("_cycle", 9)
	_expect_false((arena.call("_story_lines", 9) as Array).is_empty(),
		"cycle 9 speaks with no places restored")
	_expect_equal(str(Acts.starting_at(1).get("id", "")), "debt",
		"act I still opens cycle 1")
	_expect_equal(str(Acts.starting_at(9).get("id", "")), "moonless",
		"the epilogue still opens cycle 9")
	# Ambient first-sight lines may record their own entries while the arena
	# runs; what matters is that no place and no story beat was needed.
	for terrain in 6:
		_expect_false(Chronicle.has(PlaceMemory.chronicle_id(terrain)),
			"terrain %d needed no entry" % terrain)
	_expect_false(Chronicle.has("story_8"), "cycle 8 needed no entry")
	_expect_false(Chronicle.has("story_9"), "cycle 9 needed no entry")
	await _drop(arena)


# --- languages --------------------------------------------------------------
func _test_five_languages_fit() -> void:
	var keys: Array[String] = []
	for terrain in 6:
		keys.append(PlaceMemory.name_key(terrain))
		keys.append(PlaceMemory.clue_key(terrain))
		keys.append(PlaceMemory.memory_key(terrain))
	keys.append_array([
		"CHRONICLE_PLACES", "OBJECTIVE_ROAD", "OBJECTIVE_PLACES", "RESULT_ROAD",
		"STORY_OPEN_A", "STORY_OPEN_B", "STORY_EPITAPH_WIN", "STORY_EPITAPH_ESCAPE",
		"STORY_EPITAPH_LOSE", "VOICE_FORK_1", "VOICE_FORK_2",
		"CYCLE_CHOICE_MAP_BEYOND_TITLE", "CYCLE_CHOICE_MAP_BEYOND_SUBTITLE",
		"CYCLE_CHOICE_MAP_BEYOND_RIGHT_TITLE",
		"CYCLE_CHOICE_MAP_BEYOND_RIGHT_DESC",
		"CHRONICLE_ENDING_WIN", "CHRONICLE_ENDING_LOSE",
	])
	for cycle in [1, 2, 3, 4, 5, 6, 7, 8, 9, 12]:
		keys.append("STORY_CYCLE_%d_A" % cycle)
		keys.append("STORY_CYCLE_%d_B" % cycle)
	for hero in ["DANCER", "KEEPER", "KNIGHT", "ECLIPSE", "SAGE"]:
		keys.append("HVOICE_%s_OPEN_A" % hero)
		keys.append("HVOICE_%s_OPEN_B" % hero)
		keys.append("HVOICE_%s_BEACON_FIRST" % hero)
	var current: String = TranslationServer.get_locale()
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		for key in keys:
			var text: String = tr(key)
			_expect_true(not text.is_empty() and text != key,
				"%s has a %s line" % [key, locale])
		for terrain in 6:
			var clue: float = UI_FONT_BOLD.get_string_size(
				tr(PlaceMemory.clue_key(terrain)),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9).x
			_expect_true(clue <= 150.0,
				"%s clue fits its gate (%d px)" % [locale, int(clue)])
			var memory: float = UI_FONT.get_string_size(
				tr(PlaceMemory.memory_key(terrain)),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x
			_expect_true(memory <= 375.0,
				"%s memory %d fits the strip (%d px)" % [
					locale, terrain, int(memory)])
		var road: float = UI_FONT_BOLD.get_string_size(
			tr("RESULT_ROAD") % [tr("HUD_WAVE") % 8, 6],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10).x
		_expect_true(road <= 780.0, "%s road fits (%d px)" % [locale, int(road)])
		var epitaph: float = UI_FONT_BOLD.get_string_size(
			tr("STORY_EPITAPH_LOSE"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x
		_expect_true(epitaph <= 780.0,
			"%s longest epitaph fits (%d px)" % [locale, int(epitaph)])
	TranslationServer.set_locale(current)


# --- budget -----------------------------------------------------------------
func _test_budget_and_teardown() -> void:
	_fresh_chronicle()
	var arena: Node2D = await _new_arena()
	var motifs: Array[Node] = []
	for child in arena.get_children():
		if child is PlaceMotif:
			motifs.append(child)
	_expect_equal(motifs.size(), 1, "one motif node stands in the arena")
	_expect_equal((motifs[0] as Node).get_child_count(), 1,
		"plus its one sprite and nothing else")
	var result: Control = arena.get_node("Ui/Result") as Control
	_expect_true(result.has_node("Road"), "the result carries its road line")
	_expect_true(result.has_node("Window"), "the result carries its window")
	var pause: Control = arena.get_node("Ui/Pause") as Control
	_expect_true(pause.has_node("Overlay/Objective"),
		"the pause carries its objective")
	arena.call("debug_light_next_beacon")
	await get_tree().process_frame
	_expect_true(Chronicle.has("place_forest"), "teardown test lit its beacon")
	var motif: Node2D = motifs[0] as Node2D
	await _drop(arena)
	_expect_false(is_instance_valid(motif), "the motif leaves with the arena")


# --- helpers ----------------------------------------------------------------
func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("place-memories test aborted: user:// path is not isolated — ", user_root)
	return safe


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
