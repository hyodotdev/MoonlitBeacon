extends Node

## How a mutated guardian is introduced and shown, in the real arena.
##
## A guardian met again is the same one: it keeps its name and gains a numeral. What it has gained
## is named in a banner just after the introduction and stays under the boss bar, a Moonless Trial
## says so, and a called pack arrives through the spirit cap like any other spirit.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.call("debug_shield")
	await _test_introduction(arena)
	await _test_pack(arena)
	await _test_trial(arena)
	arena.queue_free()
	await get_tree().process_frame
	_finish()


## Stand in the last zone of `cycle`, always in the forest, and call its guardian.
func _summon(arena: Node2D, cycle: int) -> Node2D:
	arena.set("_run_seed", 9001)
	arena.set("_cycle", cycle)
	arena.set("_zone_index", 2)
	arena.set("_route", [-1, -1, 0] as Array[int])
	arena.call("_summon_guardian")
	await get_tree().process_frame
	await get_tree().process_frame
	return arena.get("_guardian") as Node2D


func _clear_guardian(arena: Node2D) -> void:
	var guardian: Node2D = arena.get("_guardian") as Node2D
	arena.set("_guardian", null)
	if guardian != null and is_instance_valid(guardian):
		guardian.queue_free()
	await get_tree().process_frame


func _test_introduction(arena: Node2D) -> void:
	var terrain: int = 0
	var guardian: Node2D = await _summon(arena, 8)
	_expect_true(guardian != null, "the last beacon calls a guardian")
	if guardian == null:
		return
	var expected: Array[int] = Expedition.mutations_for(9001, 8, terrain)
	_expect_equal(expected.size(), 2, "the official win cycle grants two mutations")
	var carried: Array[int] = []
	carried.assign(guardian.get("mutations"))
	_expect_equal(carried, expected, "the arena hands the drawn mutations to the guardian")
	var kind: SpiritKind = guardian.get("kind") as SpiritKind
	var plain: String = TranslationServer.translate(kind.display_name)
	_expect_equal(str(arena.get("_guardian_title")), plain, "a first meeting has no numeral")
	var names: PackedStringArray = PackedStringArray()
	for mutation in expected:
		names.append(TranslationServer.translate(Expedition.mutation_name_key(mutation)))
	var detail: String = " · ".join(names)
	_expect_equal(str(arena.get("_guardian_detail")), detail, "the mutations are named")

	# The boss bar carries the name and the line under it.
	await get_tree().create_timer(0.3, true).timeout
	var hud: Control = arena.get("_hud") as Control
	var detail_label: Label = hud.get("_boss_detail") as Label
	_expect_true(detail_label != null and detail_label.visible and detail_label.text == detail,
		"the boss bar shows what it gained")

	# A second banner names them just after the introduction.
	await get_tree().create_timer(2.0, true).timeout
	var banner: Label = hud.get("_banner") as Label
	_expect_true(banner.text.contains(detail), "a banner names the mutations")

	# Met again, it is the same guardian and it has a numeral.
	await _clear_guardian(arena)
	guardian = await _summon(arena, 9)
	_expect_true(str(arena.get("_guardian_title")).ends_with(" II"),
		"the second meeting is numbered II")
	await _clear_guardian(arena)
	guardian = await _summon(arena, 10)
	_expect_true(str(arena.get("_guardian_title")).ends_with(" III"),
		"the third meeting is numbered III")
	await _clear_guardian(arena)
	_expect_equal(str(arena.call("_numeral", 4)), "IV", "numerals count on")
	_expect_equal(str(arena.call("_numeral", 12)), "12", "past ten it falls back to digits")


func _test_pack(arena: Node2D) -> void:
	var guardian: Node2D = await _summon(arena, 8)
	if guardian == null:
		return
	arena.call("_prune_spirits")
	var before: int = (arena.get("_spirits") as Array).size()
	guardian.calls_pack.emit(guardian.global_position, 4)
	await get_tree().process_frame
	var after: int = (arena.get("_spirits") as Array).size()
	_expect_true(after - before >= 1 and after - before <= 4,
		"a called pack arrives (%d spirits)" % (after - before))
	_expect_true(after <= int(arena.call("spirit_cap")), "and never past the cap")
	# A full field takes none.
	while (arena.get("_spirits") as Array).size() < int(arena.call("spirit_cap")):
		arena.call("_summon", Vector2(600, 600), "res://resources/wisp.tres", 1.0, false)
	var full: int = (arena.get("_spirits") as Array).size()
	guardian.calls_pack.emit(guardian.global_position, 4)
	await get_tree().process_frame
	_expect_equal((arena.get("_spirits") as Array).size(), full,
		"a full field takes no more than the cap")
	await _clear_guardian(arena)


func _test_trial(arena: Node2D) -> void:
	# Depth 5 is the first Moonless Trial: one more mutation, and the banner says so.
	var terrain: int = 0
	var guardian: Node2D = await _summon(arena, 13)
	if guardian == null:
		return
	_expect_equal((guardian.get("mutations") as Array).size(),
		Expedition.mutation_slots(13), "a trial guardian carries its extra mutation")
	_expect_true(Expedition.is_trial(13), "cycle 13 is a Moonless Trial")
	await get_tree().create_timer(2.2, true).timeout
	var banner: Label = (arena.get("_hud") as Control).get("_banner") as Label
	_expect_true(banner.text.contains(TranslationServer.translate("TRIAL_NAME")),
		"the banner names the trial")
	_expect_true(terrain >= 0, "the guardian stands in a real terrain")
	await _clear_guardian(arena)


func _finish() -> void:
	if _failed > 0:
		printerr("guardian-staging test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("guardian-staging test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("guardian-staging test aborted: user:// path is not isolated — ", user_root)
	return safe


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)
