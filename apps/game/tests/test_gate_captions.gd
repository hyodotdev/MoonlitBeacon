extends Node

## Fork-gate captions stay readable at every rim of the real arena.
##
## A gate on the top rim used to carry its three-line destination above itself,
## off-screen, while its compass hid because the gate was visible — the choice
## was unreadable with no arrow either. Each rim is staged like the director's
## diagnostic (gate at a real candidate, player beside it): the gate is
## visible so its compass hides, and the caption must still land fully inside
## the usable screen, below the top HUD, near its gate, without taking input —
## and clear of the hero standing beside it, whose face the usable shift alone
## would cross. A plain gate carries no caption, and closing one resets it.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
## Gate at a real escape candidate, player beside it toward the room middle.
const RIMS: Array = [
	["top", Vector2(950, 124), Vector2(950, 220)],
	["bottom", Vector2(950, 1056), Vector2(950, 960)],
	["left", Vector2(124, 590), Vector2(220, 590)],
	["right", Vector2(1776, 590), Vector2(1680, 590)],
]
const HEROES: Array[String] = [
	"res://resources/heroes/warden.tres",
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/sage.tres",
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/eclipse.tres",
]
## Caption center may sit this far (screen px) from its gate and still read
## as one thing. The top rim shifts a full label height below the gate.
const ASSOCIATION_PX: float = 170.0
## Screen margin the caption must clear around the hero. Mirrors the gate's
## own clearance; the footprint itself comes from each hero's resource.
const HERO_MARGIN: float = 6.0

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	get_tree().root.size = Vector2i(808, 360)
	get_tree().root.content_scale_size = Vector2i(808, 360)
	for rim in RIMS:
		await _test_rim(str(rim[0]), rim[1] as Vector2, rim[2] as Vector2)
	await _test_all_heroes_top()
	await _test_fork_wires_player()
	await _test_plain_gate()
	await _test_close_resets()
	_finish()


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


## Stage one rim's gate and player, wired the way the arena's naming path
## wires a real fork: a destination and the player reading it.
func _stage_rim(arena: Node2D, gate_at: Vector2, player_at: Vector2) -> void:
	var gate: Node2D = arena.get("_gate") as Node2D
	var player: Node2D = arena.get("_player") as Node2D
	gate.set_destination(
		tr("WORLD_FIELD"), tr("OMEN_BLOOD_MOON"),
		Color(0.62, 0.8, 1.0, 1.0), tr(PlaceMemory.clue_key(1)))
	gate.track_player(player)
	gate.position = gate_at
	gate.reset_physics_interpolation()
	player.position = player_at
	player.reset_physics_interpolation()
	gate.open()


func _test_rim(id: String, gate_at: Vector2, player_at: Vector2) -> void:
	var arena: Node2D = await _new_arena()
	_stage_rim(arena, gate_at, player_at)
	for _frame in 5:
		await get_tree().process_frame

	var gate: Node2D = arena.get("_gate") as Node2D
	var player: Node2D = arena.get("_player") as Node2D
	var xform: Transform2D = get_viewport().get_canvas_transform()
	var scale: float = maxf(xform.x.length(), xform.y.length())
	var safe: Rect2 = Screen.viewport_safe_rect(get_viewport())
	var gate_screen: Vector2 = xform * gate.global_position
	_expect_true(
		safe.has_point(gate_screen),
		"%s rim stages its gate on screen (%s)" % [id, gate_screen])

	# The gate is visible, so the real compass hides — the caption is the
	# only readable choice information left.
	var compass: Control = arena.get("_compass") as Control
	compass.point_to(
		BeaconCompass.Mark.EXIT, gate.position, player.position,
		safe, 0.0, 0.016)
	_expect_true(
		not bool(compass.get("_showing")),
		"%s rim hides the compass for its visible gate" % id)

	var label: Label = gate.get("_label") as Label
	_expect_true(
		label != null and label.visible,
		"%s rim keeps its caption shown" % id)
	if label == null:
		await _drop(arena)
		return
	_expect_equal(
		label.text.split("\n").size(), 3,
		"%s rim caption names place, omen and memory" % id)
	var rect: Rect2 = _caption_rect(gate, label, xform, scale)
	var usable_top: float = safe.position.y + BeaconCompass.TOP_HUD_SAFE_Y
	_expect_true(
		rect.position.x >= safe.position.x - 0.5
		and rect.end.x <= safe.end.x + 0.5,
		"%s rim caption stays inside left/right screen (%s / %s)" % [
			id, rect, safe])
	_expect_true(
		rect.position.y >= usable_top - 0.5
		and rect.end.y <= safe.end.y + 0.5,
		"%s rim caption stays below the HUD and on screen (%s / %s)" % [
			id, rect, safe])
	_expect_true(
		rect.get_center().distance_to(gate_screen) <= ASSOCIATION_PX,
		"%s rim caption stays with its gate (%s / %s)" % [
			id, rect.get_center(), gate_screen])
	_expect_equal(
		label.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"%s rim caption stays tap-through" % id)
	var hero: Hero = arena.call("_hero_for_run") as Hero
	_expect_true(
		not rect.intersects(_hero_footprint(player, hero, xform, scale)),
		"%s rim caption clears the hero (%s)" % [id, rect])
	await _drop(arena)


## Every shipped hero's actual footprint clears the top caption. The top rim
## is the reproduced overlap: the usable shift alone crosses the hero's face.
func _test_all_heroes_top() -> void:
	var gate_at: Vector2 = RIMS[0][1] as Vector2
	var player_at: Vector2 = RIMS[0][2] as Vector2
	for path in HEROES:
		var hero: Hero = load(path) as Hero
		var name: String = path.get_file().get_basename()
		var arena: Node2D = await _new_arena()
		var player: Node2D = arena.get("_player") as Node2D
		_expect_true(
			player.apply_hero_visual(hero),
			"%s stages its sheets" % name)
		_stage_rim(arena, gate_at, player_at)
		for _frame in 5:
			await get_tree().process_frame
		var gate: Node2D = arena.get("_gate") as Node2D
		var xform: Transform2D = get_viewport().get_canvas_transform()
		var scale: float = maxf(xform.x.length(), xform.y.length())
		var safe: Rect2 = Screen.viewport_safe_rect(get_viewport())
		var label: Label = gate.get("_label") as Label
		var rect: Rect2 = _caption_rect(gate, label, xform, scale)
		var usable_top: float = safe.position.y + BeaconCompass.TOP_HUD_SAFE_Y
		_expect_true(
			rect.position.x >= safe.position.x - 0.5
			and rect.end.x <= safe.end.x + 0.5
			and rect.position.y >= usable_top - 0.5
			and rect.end.y <= safe.end.y + 0.5,
			"%s keeps the top caption inside the usable screen (%s)" % [
				name, rect])
		_expect_true(
			rect.get_center().distance_to(xform * gate.global_position)
				<= ASSOCIATION_PX,
			"%s keeps the top caption with its gate" % name)
		_expect_true(
			not rect.intersects(_hero_footprint(player, hero, xform, scale)),
			"%s clears the top caption (%s)" % [name, rect])
		await _drop(arena)


## A real fork wires the player into both gates it names.
func _test_fork_wires_player() -> void:
	var arena: Node2D = await _new_arena()
	arena.set("_forks_enabled", true)
	arena.set("_run_seed", 4_242_001)
	arena.set("_cycle", 2)
	arena.set("_zone_index", 0)
	var start: int = Expedition.start_terrain(4_242_001, 2, 0)
	arena.set("_route", [start, -1, -1] as Array[int])
	arena.call("_change_cycle_world")
	await get_tree().process_frame
	arena.call("debug_light_next_beacon")
	await get_tree().create_timer(0.2, true).timeout
	_expect_equal(
		(arena.get("_fork_options") as Array).size(), 2,
		"the wiring staging opens a fork")
	var player: Node2D = arena.get("_player") as Node2D
	_expect_equal(
		(arena.get("_gate") as Node2D).get("_player"), player,
		"a fork wires the player into its first gate")
	var gate_b: Node2D = arena.get("_gate_b") as Node2D
	if gate_b == null:
		_expect_true(false, "a fork opens a second gate")
	else:
		_expect_equal(
			gate_b.get("_player"), player,
			"a fork wires the player into its second gate")
	await _drop(arena)


## A gate that never named a destination carries no caption at all.
func _test_plain_gate() -> void:
	var arena: Node2D = await _new_arena()
	var gate: Node2D = arena.get("_gate") as Node2D
	_expect_true(gate.get("_label") == null, "a plain gate builds no label")
	gate.open()
	await get_tree().process_frame
	_expect_true(
		gate.get("_label") == null, "opening a plain gate builds no label")
	_expect_true(
		arena.get("_gate_b") == null, "no fork means no second gate")
	gate.set_destination("Somewhere", "", Color.WHITE)
	await get_tree().process_frame
	_expect_true(
		(gate.get("_label") as Label).visible,
		"naming a gate shows its caption")
	gate.clear_destination()
	_expect_true(
		not (gate.get("_label") as Label).visible,
		"clearing a gate hides its caption again")
	await _drop(arena)


## Closing a gate resets it for the next terrain: shut, dark, unnamed.
func _test_close_resets() -> void:
	var arena: Node2D = await _new_arena()
	var gate: Node2D = arena.get("_gate") as Node2D
	gate.set_destination("Somewhere", "Something", Color.WHITE, "A clue")
	gate.open()
	await get_tree().process_frame
	gate.close()
	_expect_true(not gate.visible, "a closed gate is hidden")
	_expect_equal(gate.modulate.a, 0.0, "a closed gate is dark")
	_expect_true(
		not (gate.get("_label") as Label).visible,
		"a closed gate hides its caption")
	await _drop(arena)


func _caption_rect(
		gate: Node2D, label: Label, xform: Transform2D, scale: float) -> Rect2:
	return Rect2(xform * label.global_position, label.size * scale)


## The hero's screen footprint from their shipped resource cell and the live
## sprite transform — the gate reads its live frame texture instead, so the
## sizes meet from two sources.
func _hero_footprint(
		player: Node2D, hero: Hero, xform: Transform2D,
		scale: float) -> Rect2:
	var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	var unit: Vector2 = sprite.global_scale.abs()
	var size: Vector2 = Vector2(hero.sprite_cell) * unit * scale
	var center: Vector2 = xform * sprite.to_global(sprite.offset)
	return Rect2(center - size * 0.5, size).grow(HERO_MARGIN)


func _finish() -> void:
	if _failed > 0:
		printerr("gate-caption test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("gate-caption test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("gate-caption test aborted: user:// path is not isolated — ", user_root)
	return safe


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)
