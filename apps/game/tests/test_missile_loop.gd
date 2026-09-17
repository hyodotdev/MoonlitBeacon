extends Node

## Focused regression that walks live Arena kill-core create, hit stray, and recover.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const CORE_SCENE: PackedScene = preload("res://scenes/items/missile_core.tscn")
const CORE_SCRIPT: Script = preload("res://scripts/items/missile_core.gd")
const CORE_TEXTURE_PATH: String = \
	"res://assets/custom/items/pickups/power_gem.png"
const DEBUG_CAPTURE_REQUEST: String = "user://store_capture_missile_core.request"
const DEBUG_CAPTURE_STATE: String = "user://store_capture_state.json"
const DEBUG_CAPTURE_TEMP: String = "user://store_capture_state.tmp"

var _failed: int = 0
var _checked: int = 0


class CaptureSpirit:
	extends Node2D

	func is_attackable() -> bool:
		return true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_remove_capture_file(DEBUG_CAPTURE_REQUEST)
	_remove_capture_file(DEBUG_CAPTURE_STATE)
	_remove_capture_file(DEBUG_CAPTURE_TEMP)
	_expect_equal(
		float(CORE_SCRIPT.get_script_constant_map().get(
			"EJECTED" + "_LIFETIME", 0.0)),
		9.0,
		"hit-core recover window is 9s")
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	_freeze_existing(arena)
	var player: Node2D = arena.get_node("Player") as Node2D
	await _test_enemy_sprite_capture_contract(arena)

	# Calling only `Arena._gain_missile_progress()` would pass even if Spirit signals were disconnected.
	# Scatter two live spirits with `take_damage` and walk kill→perished→Arena→core in full.
	var kills_before: int = int(arena.get("_kills"))
	var first_spirit: Node2D = arena.call(
		"_summon", Vector2(500, 300),
		"res://resources/wisp.tres", 0.5, false) as Node2D
	var second_spirit: Node2D = arena.call(
		"_summon", Vector2(518, 300),
		"res://resources/wisp.tres", 0.5, false) as Node2D
	_freeze_existing(first_spirit)
	_freeze_existing(second_spirit)
	# The materialize Tween is frozen too, so only this focused check marks them attackable.
	first_spirit.set("_materialized", true)
	second_spirit.set("_materialized", true)
	var first_spirit_at: Vector2 = first_spirit.global_position
	first_spirit.global_position = player.global_position + Vector2.RIGHT * 80.0
	await _test_moonlight_projectile_origin(
		arena, player, first_spirit)
	first_spirit.global_position = first_spirit_at
	first_spirit.call("take_damage", 999999, Vector2(460, 300))
	_expect_equal(int(arena.get("_missile_progress")), 1, "first actual Spirit kill progress is 1/2")
	_expect_equal(_cores().size(), 0, "no core yet on the first actual Spirit kill")
	second_spirit.call("take_damage", 999999, Vector2(478, 300))
	await get_tree().process_frame
	await get_tree().process_frame
	var regular: Array[Node] = _cores()
	_expect_equal(int(arena.get("_kills")), kills_before + 2, "Arena counts two Spirit perished events")
	_expect_equal(regular.size(), 1, "first core spawns on the second actual Spirit kill")
	if not regular.is_empty():
		_expect_false(bool(regular[0].get("ejected")), "kill cores are regular cores")
		regular[0].call("_expire")
	await get_tree().create_timer(0.3, true).timeout
	_expect_false(
		bool(arena.get("_first_missile_core_collected")),
		"missing the first core does not flip to a recovered-complete state")
	_expect_equal(
		int(arena.call("_missile_threshold_power")),
		0,
		"first power threshold is kept even after the first core expires")
	var missile_hud_label: Label = arena.get_node(
		"Ui/Hud/LeftPanel/Stack/MissilePower") as Label
	_expect_true(
		missile_hud_label.text.contains("0/2"),
		"after the first core expires HUD also shows the lower retry threshold")
	arena.call("_gain_missile_progress", Vector2(500, 300), false, false)
	_expect_equal(_cores().size(), 0, "first-core retry also does not drop at 1/2")
	_expect_true(missile_hud_label.text.contains("1/2"), "first-core retry HUD is 1/2")
	arena.call("_gain_missile_progress", Vector2(500, 300), false, false)
	await get_tree().process_frame
	await get_tree().process_frame
	regular = _cores()
	_expect_equal(regular.size(), 1, "drops again after two kills once the first core expires")
	if not regular.is_empty():
		regular[0].call("_collect")
	await get_tree().create_timer(0.25, true).timeout
	_expect_equal(int(arena.get("_missile_power")), 1, "recovering a retry core reaches power 1")
	_expect_true(
		bool(arena.get("_first_missile_core_collected")),
		"first core completes only after an actual recover")

	# Fill two core shares while leaving the next core idle. The moment the floor core is picked up, the slot
	# The follow-up core must spawn at the recent-kill position so HUD does not freeze full.
	# Do not recursively create both shares at once; each resolve should continue only one.
	var backlog_at: Vector2 = Vector2(520, 310)
	var room: Node = arena.get("_room") as Node
	var backlog_safe: Vector2 = room.call(
		"nearest_clear", backlog_at, 12.0)
	for i in 11:
		arena.call(
			"_gain_missile_progress", backlog_at, false, false)
	await get_tree().process_frame
	await get_tree().process_frame
	regular = _cores()
	_expect_equal(int(arena.get("_missile_progress")), 8, "next two cores of progress accumulate while idle")
	_expect_equal(
		int(arena.get("_regular_cores_outstanding")),
		1,
		"only one regular core is kept even while idle")
	if not regular.is_empty():
		regular[0].call("_collect")
		_expect_equal(
			int(arena.get("_regular_cores_outstanding")),
			1,
			"backlog core takes the waiting slot immediately on collect")
		_expect_equal(
			int(arena.get("_missile_progress")),
			4,
			"only one core share is deducted immediately on collect")
		_expect_equal(
			int(arena.get("_ejected_cores_outstanding")),
			0,
			"re-dropping a regular backlog does not change the stray-core count")
		await get_tree().create_timer(0.25, true).timeout
	_expect_equal(int(arena.get("_missile_power")), 2, "recovering the first backlog core reaches power 2")
	await get_tree().process_frame
	await get_tree().process_frame
	regular = _cores()
	_expect_equal(regular.size(), 1, "only the follow-up core remains right after collect")
	if not regular.is_empty():
		_expect_true(
			regular[0].position.distance_to(backlog_safe) < 1.0,
			"collected backlog core is created at a safe recent-kill position")

	# The remaining share after collect becomes one core again the moment the follow-up core expires.
	if not regular.is_empty():
		regular[0].call("_expire")
		_expect_equal(
			int(arena.get("_regular_cores_outstanding")),
			1,
			"backlog core takes the waiting slot immediately on expiry")
		_expect_equal(
			int(arena.get("_missile_progress")),
			0,
			"next core share is deducted immediately on expiry")
	await get_tree().create_timer(0.3, true).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	regular = _cores()
	_expect_equal(regular.size(), 1, "only the follow-up core remains right after expiry")
	if not regular.is_empty():
		_expect_true(
			regular[0].position.distance_to(backlog_safe) < 1.0,
			"expired backlog core spawns at a safe recent-kill position")
	if not regular.is_empty():
		regular[0].call("_collect")
		await get_tree().create_timer(0.25, true).timeout
	_expect_equal(int(arena.get("_missile_power")), 3, "a consecutively respawned core also upgrades normally")

	# A hit does not drop a random relic; it strays exactly one missile-power rank.
	# The 03 store-scene contract is Lv10, cycle 1, night forest, so match that live
	# Arena state. Changing only a JSON fixture would not exercise the terrain guard.
	arena.set("_level", 10)
	arena.set("_missile_power", 4)
	arena.call("_set_health", int(arena.get("_max_health")))
	var taken_before: int = (arena.get("_taken") as Array).size()
	_expect_true(_write_capture_request(), "store-capture request file created")
	arena.call("debug_take_hit")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(int(arena.get("_missile_power")), 3, "one hit drops power 4→3")
	_expect_equal(
		(arena.get("_taken") as Array).size(),
		taken_before,
		"a hit does not drop a random relic")
	_expect_false(
		FileAccess.file_exists(DEBUG_CAPTURE_REQUEST),
		"store-capture request is consumed only once")
	_expect_true(_write_capture_request("{}"), "CoreDevice capture-clear file created")
	_expect_false(
		bool(arena.call("_consume_debug_missile_capture_request")),
		"{} clear leftover is not a missile-capture request")
	_expect_true(
		FileAccess.file_exists(DEBUG_CAPTURE_REQUEST),
		"{} clear leftover is kept distinct from a new request")
	_remove_capture_file(DEBUG_CAPTURE_REQUEST)
	var expected_banner: String = tr("MISSILE_DROPPED") % [4, 3]
	var capture_state: Dictionary = _read_capture_state()
	_expect_equal(int(capture_state.get("schema", 0)), 1, "capture-state schema")
	_expect_equal(
		str(capture_state.get("kind", "")),
		"missile_core_recovery",
		"capture state is missile-core recover")
	_expect_equal(
		str(capture_state.get("game_locale", "")),
		TranslationServer.get_locale(),
		"capture-state locale is the actual game locale")
	_expect_equal(
		str(capture_state.get("banner_key", "")),
		"MISSILE_DROPPED",
		"capture-state banner key")
	_expect_equal(
		str(capture_state.get("expected_banner_text", "")),
		expected_banner,
		"capture state's expected translated copy")
	_expect_equal(
		str(capture_state.get("actual_banner_text", "")),
		expected_banner,
		"capture state's actual HUD copy")
	_expect_true(bool(capture_state.get("banner_visible", false)), "capture banner shown")
	_expect_true(bool(capture_state.get("banner_locked", false)), "capture banner pinned")
	_expect_equal(int(capture_state.get("missile_power_before", -1)), 4, "power before capture")
	_expect_equal(int(capture_state.get("missile_power_after", -1)), 3, "power after capture")
	_expect_equal(
		int(capture_state.get("ejected_cores_outstanding", 0)),
		1,
		"a recoverable stray core exists in capture state")
	_expect_true(
		bool(capture_state.get("core_capture_paused", false)),
		"capture state includes proof that core lifetime and magnet are paused")
	_expect_equal(
		int(capture_state.get("ejected_core_count", 0)),
		1,
		"capture state has exactly one live stray core")
	_expect_true(
		bool(capture_state.get("core_visible_in_tree", false)),
		"capture state's stray core is shown in the tree")
	_expect_true(
		float(capture_state.get("core_effective_alpha", 0.0)) >= 0.99,
		"capture state's stray core has valid alpha including parents")
	_expect_true(bool(capture_state.get("core_opaque", false)), "capture core opaque")
	_expect_true(bool(capture_state.get("core_onscreen", false)), "capture core on screen")
	_expect_equal(
		str(capture_state.get("core_texture_path", "")),
		CORE_TEXTURE_PATH,
		"capture core is the exact power_gem resource")
	_expect_true(
		bool(capture_state.get("core_texture_matches", false)),
		"capture core texture matches the live one")
	_expect_true(
		bool(capture_state.get("core_visible_draw_rect_positive", false)),
		"capture core's on-screen intersecting draw rect is positive")
	var hud: Control = arena.get_node("Ui/Hud") as Control
	var banner_snapshot: Dictionary = hud.call("debug_capture_banner_snapshot")
	_expect_equal(str(banner_snapshot.get("text", "")), expected_banner, "HUD actual recover banner")
	hud.call("announce", "wrong follow-up banner", Color.RED)
	hud.call("clear_banner")
	banner_snapshot = hud.call("debug_capture_banner_snapshot")
	_expect_equal(
		str(banner_snapshot.get("text", "")),
		expected_banner,
		"later notices and clear do not cover the recover banner while pinned")
	_expect_true(bool(banner_snapshot.get("visible", false)), "pinned banner stays fully shown")
	var ejected: Array[Node] = _cores()
	_expect_equal(ejected.size(), 1, "one power rank strays as one core on hit")
	if not ejected.is_empty():
		_expect_true(bool(ejected[0].get("ejected")), "hit cores are 9s recover cores")
		_expect_false(bool(ejected[0].call("is_armed")), "auto-recover is locked for 0.75s right after a hit")
		_expect_false(ejected[0].is_processing(), "core lifetime paused during capture")
		_expect_false(ejected[0].is_physics_processing(), "core magnet paused during capture")
		var paused_position: Vector2 = ejected[0].position
		await get_tree().create_timer(0.2, true).timeout
		_expect_true(
			ejected[0].position.distance_to(paused_position) < 0.001,
			"even the hit-fling Tween stops during capture so the live core stays put")
		var sprite: Sprite2D = ejected[0].get_node("Sprite") as Sprite2D
		_expect_true(
			sprite.modulate.r > sprite.modulate.b * 2.0,
			"hit cores use orange, distinct from regular blue")
		await _test_core_capture_visual_mutations(arena, ejected[0], sprite)
		ejected[0].call("set_transition_paused", false)
		ejected[0].set_physics_process(false)
		arena.call("_tick_missile_recovery_hud")
		var recovery_label: Label = hud.get_node(
			"LeftPanel/Stack/MissileRecovery") as Label
		_expect_true(recovery_label.visible, "hit-core HUD countdown shown")
		_expect_true(recovery_label.text.contains("9"), "HUD shows 9s right after a hit")
		var recovery_direction: Vector2 = hud.get("_recovery_direction")
		_expect_true(
			recovery_direction.length() > 0.99,
			"off-screen recover-direction cue is normalized")
		ejected[0].set("_left", 3.2)
		arena.call("_tick_missile_recovery_hud")
		_expect_true(recovery_label.text.contains("4"), "HUD countdown rounds up to 4s")
		await get_tree().create_timer(0.8, true).timeout
		_expect_true(bool(ejected[0].call("is_armed")), "hit-core recovery arms after 0.75s")
		ejected[0].global_position = player.global_position + Vector2.RIGHT * 60.0
		var far_before: float = ejected[0].global_position.distance_to(
			player.global_position)
		ejected[0].call("_physics_process", 0.2)
		_expect_true(
			is_equal_approx(
				ejected[0].global_position.distance_to(player.global_position),
				far_before),
			"a hit core at 60px is not magneted")
		ejected[0].global_position = player.global_position + Vector2.RIGHT * 16.0
		var before_magnet: float = ejected[0].global_position.distance_to(
			player.global_position)
		ejected[0].call("_physics_process", 0.2)
		_expect_true(
			ejected[0].global_position.distance_to(player.global_position) < before_magnet,
			"only a hit core inside 22px magnets to the player")
		arena.set("_missile_progress", 0)
		ejected[0].global_position = player.global_position + Vector2.RIGHT * 5.0
		ejected[0].call("_physics_process", 0.01)
		await get_tree().create_timer(0.25, true).timeout
	_expect_equal(
		int(arena.get("_missile_power")), 3,
		"recovering a stray core does not restore power immediately")
	_expect_equal(
		int(arena.get("_missile_progress")), 2,
		"recovering a stray core returns only 70% of the next-rank requirement")
	_expect_false(
		FileAccess.file_exists(DEBUG_CAPTURE_STATE),
		"live-core recover signal immediately drops stale capture state")
	banner_snapshot = hud.call("debug_capture_banner_snapshot")
	_expect_false(
		bool(banner_snapshot.get("locked", true)),
		"capture banner unpinned after recovering a live core")
	arena.call("_tick_missile_recovery_hud")
	var recovered_label: Label = arena.get_node(
		"Ui/Hud/LeftPanel/Stack/MissileRecovery") as Label
	_expect_false(recovered_label.visible, "HUD countdown hidden after recover")

	# Miss the next hit core. After expiry, power is confirmed at the lower rank,
	# The outstanding slot is freed so later kill growth can happen again.
	arena.call("_set_health", int(arena.get("_max_health")))
	_expect_true(_write_capture_request(), "expiry-path store-capture request file created")
	arena.call("debug_take_hit")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(
		FileAccess.file_exists(DEBUG_CAPTURE_STATE),
		"second stray core is also exposed in capture state")
	ejected = _cores()
	_expect_equal(int(arena.get("_missile_power")), 2, "second hit also strays exactly one rank")
	_expect_equal(ejected.size(), 1, "second hit also strays one core")
	if not ejected.is_empty():
		ejected[0].call("_expire")
	await get_tree().create_timer(0.3, true).timeout
	_expect_false(
		FileAccess.file_exists(DEBUG_CAPTURE_STATE),
		"live-core expiry signal immediately drops stale capture state")
	banner_snapshot = hud.call("debug_capture_banner_snapshot")
	_expect_false(
		bool(banner_snapshot.get("locked", true)),
		"capture banner unpinned after a live core expires")
	_expect_equal(int(arena.get("_missile_power")), 2, "lower power kept after a stray core expires")
	_expect_equal(
		int(arena.get("_ejected_cores_outstanding")),
		0,
		"waiting slot freed after a stray core expires")
	arena.call("_tick_missile_recovery_hud")
	_expect_false(recovered_label.visible, "HUD countdown hidden after a stray core expires")

	arena.set("_missile_power", MissileProgression.MAX_POWER)
	arena.set("_missile_progress", 4)
	for i in 12:
		arena.call("_gain_missile_progress", Vector2(560, 330), true, false)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(_cores().size(), 0, "does not spawn extra cores at max power")
	_expect_equal(int(arena.get("_missile_progress")), 0, "max-power progress is pinned at 0")

	# The result screen clears cores without a pickup signal. Capture proof and HUD pin
	# must vanish first, and a deferred publisher must not revive them after run end.
	arena.set("_missile_power", 4)
	arena.call("_set_health", int(arena.get("_max_health")))
	_expect_true(_write_capture_request(), "run-end-path store-capture request file created")
	arena.call("debug_take_hit")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(FileAccess.file_exists(DEBUG_CAPTURE_STATE), "capture state published before run end")
	arena.call("_finish", false)
	_expect_false(
		FileAccess.file_exists(DEBUG_CAPTURE_STATE),
		"run end immediately drops capture state before live cores are removed")
	banner_snapshot = hud.call("debug_capture_banner_snapshot")
	_expect_false(
		bool(banner_snapshot.get("locked", true)),
		"run end immediately unpins the capture banner")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_false(
		FileAccess.file_exists(DEBUG_CAPTURE_STATE),
		"a deferred publisher does not revive capture state after run end")
	_expect_equal(_cores().size(), 0, "no live core remains on the run-end result screen")

	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# If the hit that consumed the request is lethal, `_finish()` runs before the publisher is scheduled.
	# runs first. Do not mistake a queued core for proof and create new JSON on the result screen.
	var lethal_arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(lethal_arena)
	await get_tree().process_frame
	await get_tree().process_frame
	_freeze_existing(lethal_arena)
	lethal_arena.set("_missile_power", 4)
	lethal_arena.call("_set_health", 1)
	_expect_true(_write_capture_request(), "lethal capture-request file created")
	lethal_arena.call("debug_take_hit")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(bool(lethal_arena.get("_over")), "capture-request hit ends the run")
	_expect_false(
		FileAccess.file_exists(DEBUG_CAPTURE_STATE),
		"a scheduled publisher does not create new capture state after run end")
	_expect_equal(_cores().size(), 0, "no live core remains even on a lethal result screen")
	lethal_arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_remove_capture_file(DEBUG_CAPTURE_REQUEST)
	_remove_capture_file(DEBUG_CAPTURE_STATE)
	_remove_capture_file(DEBUG_CAPTURE_TEMP)
	if _failed > 0:
		printerr("missile combat-loop test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("missile combat-loop test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _test_core_capture_visual_mutations(
		arena: Node2D, core: Node, sprite: Sprite2D) -> void:
	var state: Dictionary = arena.call("_debug_missile_core_capture_visual_state")
	_expect_true(bool(state.get("ready", false)), "normal stray-core live proof")
	_expect_equal(int(state.get("ejected_core_count", 0)), 1, "live probe has one stray core")

	(core as CanvasItem).hide()
	state = arena.call("_debug_missile_core_capture_visual_state")
	_expect_false(
		bool(state.get("core_visible_in_tree", true)),
		"rejects capturing a hidden stray core")
	_expect_false(bool(state.get("ready", true)), "hidden-core live proof fails")
	(core as CanvasItem).show()

	var core_canvas: CanvasItem = core as CanvasItem
	core_canvas.modulate.a = 0.0
	state = arena.call("_debug_missile_core_capture_visual_state")
	_expect_true(
		float(state.get("core_effective_alpha", 1.0)) <= 0.001,
		"alpha-0 core valid alpha 0")
	_expect_false(bool(state.get("core_opaque", true)), "rejects capturing an alpha-0 core")
	_expect_false(bool(state.get("ready", true)), "transparent-core live proof fails")
	core_canvas.modulate.a = 1.0

	var original_position: Vector2 = (core as Node2D).global_position
	(core as Node2D).global_position = Vector2(-10000.0, -10000.0)
	state = arena.call("_debug_missile_core_capture_visual_state")
	_expect_false(bool(state.get("core_onscreen", true)), "rejects capturing an off-screen core")
	_expect_false(
		bool(state.get("core_visible_draw_rect_positive", true)),
		"off-screen core has no visible draw rect")
	_expect_false(bool(state.get("ready", true)), "off-screen core live proof fails")
	(core as Node2D).global_position = original_position

	var expected_texture: Texture2D = sprite.texture
	var wrong_texture := GradientTexture2D.new()
	sprite.texture = wrong_texture
	state = arena.call("_debug_missile_core_capture_visual_state")
	_expect_false(
		bool(state.get("core_texture_matches", true)),
		"rejects capturing a core with a different texture")
	_expect_false(bool(state.get("ready", true)), "wrong-core texture live proof fails")

	sprite.texture = null
	state = arena.call("_debug_missile_core_capture_visual_state")
	_expect_false(
		bool(state.get("core_visible_draw_rect_positive", true)),
		"rejects a positive draw rect for a core with no texture")
	_expect_false(bool(state.get("ready", true)), "shapeless-core live proof fails")
	sprite.texture = expected_texture

	var duplicate: Area2D = CORE_SCENE.instantiate() as Area2D
	duplicate.set("ejected", true)
	duplicate.position = (core as Node2D).position + Vector2(24.0, 0.0)
	arena.add_child(duplicate)
	await get_tree().process_frame
	state = arena.call("_debug_missile_core_capture_visual_state")
	_expect_equal(int(state.get("ejected_core_count", 0)), 2, "duplicate stray cores are actually counted")
	_expect_false(bool(state.get("ready", true)), "rejects capture when there are two stray cores")
	duplicate.queue_free()
	await get_tree().process_frame


func _test_enemy_sprite_capture_contract(arena: Node2D) -> void:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	# To get exact internal pixel coords regardless of Camera2D world movement,
	# Put test spirits on a separate CanvasLayer. All are live counterexamples with is_attackable=true.
	var layer := CanvasLayer.new()
	add_child(layer)
	var spirits: Array[Node2D] = []
	for index in 3:
		var spirit := CaptureSpirit.new()
		spirit.position = Vector2(100.0 + 48.0 * float(index), 100.0)
		var sprite := AnimatedSprite2D.new()
		sprite.name = "Sprite"
		var frames := SpriteFrames.new()
		frames.add_frame(&"default", texture)
		sprite.sprite_frames = frames
		sprite.animation = &"default"
		spirit.add_child(sprite)
		layer.add_child(spirit)
		spirits.append(spirit)
	await get_tree().process_frame

	_expect_equal(
		int(arena.call(
			"debug_visible_enemy_sprite_count", spirits, viewport_rect)),
		3,
		"counts three enemies whose current live frame is visible")
	var target: Node2D = spirits[0]
	var target_sprite: AnimatedSprite2D = target.get_node("Sprite") as AnimatedSprite2D
	var state: Dictionary = arena.call(
		"debug_enemy_sprite_capture_state", target, viewport_rect)
	_expect_true(bool(state.get("ready", false)), "normal enemy Sprite pixel contract")
	_expect_true(
		bool(state.get("enemy_sprite_frame_texture_ready", false)),
		"current AnimatedSprite frame texture")
	_expect_true(
		bool(state.get("enemy_sprite_draw_rect_positive", false)),
		"enemy Sprite positive draw rect")
	_expect_true(
		bool(state.get("enemy_sprite_meaningful_intersection", false)),
		"enemy Sprite meaningful viewport intersection")

	target_sprite.hide()
	state = arena.call("debug_enemy_sprite_capture_state", target, viewport_rect)
	_expect_false(
		bool(state.get("enemy_sprite_visible_in_tree", true)),
		"rejects capturing a hidden enemy Sprite")
	_expect_equal(
		int(arena.call(
			"debug_visible_enemy_sprite_count", spirits, viewport_rect)),
		2,
		"hidden but living enemies are excluded from volley count")
	target_sprite.show()

	target.modulate.a = 0.0
	state = arena.call("debug_enemy_sprite_capture_state", target, viewport_rect)
	_expect_false(
		bool(state.get("enemy_sprite_opaque", true)),
		"rejects capturing an enemy Sprite whose parent alpha is 0")
	_expect_equal(
		int(arena.call(
			"debug_visible_enemy_sprite_count", spirits, viewport_rect)),
		2,
		"transparent but living enemies are excluded from volley count")
	target.modulate.a = 1.0

	var valid_frames: SpriteFrames = target_sprite.sprite_frames
	target_sprite.sprite_frames = SpriteFrames.new()
	target_sprite.animation = &"default"
	state = arena.call("debug_enemy_sprite_capture_state", target, viewport_rect)
	_expect_false(
		bool(state.get("enemy_sprite_frame_texture_ready", true)),
		"rejects an enemy whose current frame texture is null")
	_expect_equal(
		int(arena.call(
			"debug_visible_enemy_sprite_count", spirits, viewport_rect)),
		2,
		"null-frame but living enemies are excluded from volley count")
	target_sprite.sprite_frames = valid_frames
	target_sprite.animation = &"default"
	target_sprite.frame = 0

	target.scale = Vector2(0.02, 0.02)
	state = arena.call("debug_enemy_sprite_capture_state", target, viewport_rect)
	_expect_true(
		bool(state.get("enemy_sprite_draw_rect_positive", false)),
		"even a tiny scale still has a positive mathematical draw rect")
	_expect_false(
		bool(state.get("enemy_sprite_meaningful_intersection", true)),
		"rejects capturing a subpixel enemy Sprite")
	_expect_equal(
		int(arena.call(
			"debug_visible_enemy_sprite_count", spirits, viewport_rect)),
		2,
		"subpixel but living enemies are excluded from volley count")
	target.scale = Vector2.ONE

	# Putting a 24px centered frame's center at x=-11 leaves exactly 1px in the viewport.
	target.position = Vector2(-11.0, 100.0)
	state = arena.call("debug_enemy_sprite_capture_state", target, viewport_rect)
	_expect_true(
		float(state.get("enemy_sprite_visible_width", 0.0)) <= 1.01,
		"edge enemy is an actual 1px sliver")
	_expect_false(
		bool(state.get("enemy_sprite_meaningful_intersection", true)),
		"rejects capturing a 1px edge-sliver enemy Sprite")
	_expect_equal(
		int(arena.call(
			"debug_visible_enemy_sprite_count", spirits, viewport_rect)),
		2,
		"edge-sliver but living enemies are excluded from volley count")

	layer.queue_free()
	await get_tree().process_frame


func _freeze_existing(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze_existing(child)


func _cores() -> Array[Node]:
	var result: Array[Node] = []
	for core in get_tree().get_nodes_in_group("missile_cores"):
		if is_instance_valid(core) and not core.is_queued_for_deletion():
			result.append(core)
	return result


func _write_capture_request(contents: String = "1") -> bool:
	var output: FileAccess = FileAccess.open(DEBUG_CAPTURE_REQUEST, FileAccess.WRITE)
	if output == null:
		return false
	var stored: bool = output.store_string(contents)
	output.close()
	return stored


func _read_capture_state() -> Dictionary:
	if not FileAccess.file_exists(DEBUG_CAPTURE_STATE):
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DEBUG_CAPTURE_STATE))
	return parsed as Dictionary if parsed is Dictionary else {}


func _remove_capture_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Confirm both straight moon discs and guided volleys spawn at the beacon candle in front of Player's chest, via the live
## Arena fire path. Stops the regression where only the character art changed and shots still spawned at the feet.
func _test_moonlight_projectile_origin(
		arena: Node2D,
		player: Node2D,
		target: Node2D,
	) -> void:
	var expected: Vector2 = player.call("moonlight_origin")
	var spirits_before: Array[Node2D] = arena.get("_spirits")
	arena.set("_spirits", [target])
	arena.set("_missile_power", 0)
	arena.set("_arrow_timer", 0.0)
	arena.call("_fire_arrows", 0.0)
	var projectiles: Array[Node] = _friendly_projectiles()
	_expect_true(not projectiles.is_empty(), "straight moon disc actually created")
	for projectile in projectiles:
		_expect_equal(
			int(projectile.call("profile_id")),
			int(player.call("attack_profile_id")),
			"selected-hero combat profile is passed to the straight moon disc")
		_expect_true(
			(projectile as Node2D).global_position.distance_to(expected) < 0.01,
			"straight moon disc is created at the beacon candle")
		_expect_true(
			(projectile.get("_direction") as Vector2).distance_to(
				(target.global_position - expected).normalized()) < 0.0001,
			"straight moon disc aims from the beacon candle")
	var cast: MoonlightCast = player.get_node("MoonlightCast") as MoonlightCast
	_expect_true(
		cast.remaining_seconds() > 0.0,
		"cast cue starts when a straight moon disc is fired")
	_clear_projectiles(projectiles)
	await get_tree().process_frame

	arena.set("_missile_power", MissileProgression.HOMING_AT)
	arena.call("_fire_missiles", target)
	projectiles = _friendly_projectiles()
	_expect_equal(projectiles.size(), 1, "guided volley is created as a single node")
	if not projectiles.is_empty():
		var missile: Node2D = projectiles[0] as Node2D
		_expect_equal(
			int(missile.call("profile_id")),
			int(player.call("attack_profile_id")),
			"selected-hero combat profile is passed to the guided volley")
		_expect_true(
			missile.global_position.distance_to(expected) < 0.01,
			"guided-volley node is created at the beacon candle")
		var positions: Array = missile.get("_positions") as Array
		_expect_true(not positions.is_empty(), "guided-volley inner-shot positions created")
		if not positions.is_empty():
			_expect_true(
				(positions[0] as Vector2).distance_to(expected) < 0.01,
				"guided-volley inner shots also start at the beacon candle")
	_expect_equal(
		cast.cast_count(),
		int(arena.call("_missile_volley")),
		"guided volley count is reflected on the cast glow")
	_clear_projectiles(projectiles)
	await get_tree().process_frame
	arena.set("_missile_power", 0)
	arena.set("_spirits", spirits_before)


func _friendly_projectiles() -> Array[Node]:
	var result: Array[Node] = []
	for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
		if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
			result.append(projectile)
	return result


func _clear_projectiles(projectiles: Array[Node]) -> void:
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()


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
