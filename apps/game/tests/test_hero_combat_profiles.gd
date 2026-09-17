extends SceneTree

## Confirm the six heroes' prices change playstyle and visual density, not a combat-power ladder.
## Wire Hero resources directly onto live Player/projectiles without IAP/Vault,
## so the combat contract stays independent if Shop implementation changes.

const PLAYER_SCENE: PackedScene = preload("res://scenes/actors/player.tscn")
const ARROW_SCENE: PackedScene = preload("res://scenes/actors/moon_arrow.tscn")
const MISSILE_SCENE: PackedScene = preload("res://scenes/actors/moon_missile.tscn")
const HERO_REQUEST_SCRIPT: Script = preload("res://scripts/dev/test_hero_request.gd")


class TargetSpirit:
	extends Node2D

	var hits: int = 0

	func is_attackable() -> bool:
		return hits == 0

	func take_damage(_damage: int, _at: Vector2) -> void:
		hits += 1


class DurableTargetSpirit:
	extends Node2D

	var hits: int = 0
	var damage_taken: int = 0

	func is_attackable() -> bool:
		return true

	func take_damage(amount: int, _at: Vector2) -> void:
		hits += 1
		damage_taken += amount

const CASES: Array[Dictionary] = [
	{
		"id": "warden", "price": 0, "profile": Hero.AttackProfile.WARDEN,
		"tier": 0, "health": 5, "speed": 1.0, "damage": 1.0, "dash": 1.0,
		"opening": [], "motion": &"round_boomerang", "impact": &"round_burst",
	},
	{
		"id": "dancer", "price": 499, "profile": Hero.AttackProfile.DANCER,
		"tier": 1, "health": 3, "speed": 1.25, "damage": 0.9, "dash": 0.6,
		"opening": ["moon_ring.tres", "light_step.tres"],
		"motion": &"spiral_twin_arc", "impact": &"twin_arc",
	},
	{
		"id": "keeper", "price": 999, "profile": Hero.AttackProfile.KEEPER,
		"tier": 2, "health": 5, "speed": 0.85, "damage": 1.25, "dash": 1.3,
		"opening": ["moon_ripple.tres", "tough_life.tres"],
		"motion": &"heavy_lantern", "impact": &"shock_ripple",
	},
	{
		"id": "knight", "price": 1499, "profile": Hero.AttackProfile.KNIGHT,
		"tier": 3, "health": 5, "speed": 0.88, "damage": 1.08, "dash": 1.25,
		"opening": ["long_blade.tres", "shadow_veil.tres"],
		"motion": &"silver_fan", "impact": &"star_shards",
	},
	{
		"id": "eclipse", "price": 1999, "profile": Hero.AttackProfile.ECLIPSE,
		"tier": 4, "health": 3, "speed": 1.08, "damage": 1.1, "dash": 1.05,
		"opening": ["swift_hand.tres", "moon_dash.tres"],
		"motion": &"eclipse_orbit", "impact": &"ember_ring",
	},
	{
		"id": "sage", "price": 2499, "profile": Hero.AttackProfile.SAGE,
		"tier": 5, "health": 4, "speed": 0.92, "damage": 0.84, "dash": 1.15,
		"opening": ["twin_arrow.tres", "pierce_arrow.tres"],
		"motion": &"constellation_step", "impact": &"starburst_chain",
	},
]

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_debug_hero_request()
	var player: Player = PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	player.process_mode = Node.PROCESS_MODE_DISABLED

	var motion_signatures: Dictionary = {}
	var impact_signatures: Dictionary = {}
	var trajectory_samples: Dictionary = {}
	var stat_signatures: Dictionary = {}
	var primary_colors: Array[Color] = []
	var ranged_budgets: Array[int] = []
	var melee_rates: Array[float] = []
	var visual_smoke_nodes: Array[Node] = []
	var previous: Hero = null

	for index in CASES.size():
		var expected: Dictionary = CASES[index]
		var hero: Hero = load(_hero_path(str(expected["id"]))) as Hero
		_expect_true(hero != null, str(expected["id"]) + " Hero resource")
		if hero == null:
			continue
		_test_resource(hero, expected, index)
		_test_assets(hero, str(expected["id"]))
		_test_player_profile(player, hero, expected)
		var opening: Dictionary = _opening_state(hero)
		_test_sidegrade(hero, opening, index)
		ranged_budgets.append(_ranged_budget(hero, opening))
		melee_rates.append(hero.damage_scale / float(opening["attack_cooldown_scale"]))

		var arrow: Node2D = ARROW_SCENE.instantiate() as Node2D
		root.add_child(arrow)
		arrow.set("damage", 17)
		arrow.set("pierce", 3)
		arrow.call("configure_profile", hero.attack_profile,
			hero.projectile_primary, hero.projectile_secondary, hero.vfx_tier, 1, 3)
		arrow.call("launch", Vector2.RIGHT)
		_expect_equal(int(arrow.call("profile_id")), int(hero.attack_profile),
			str(expected["id"]) + " straight-shot profile passed")
		_expect_equal(float(arrow.call("collision_radius")), 7.0,
			str(expected["id"]) + " straight-shot shared collision radius")
		_expect_equal(int(arrow.get("damage")), 17,
			str(expected["id"]) + " profile leaves straight-shot damage unchanged")
		_expect_equal(int(arrow.get("pierce")), 3,
			str(expected["id"]) + " profile leaves straight-shot pierce unchanged")
		var motion: StringName = arrow.call("motion_signature") as StringName
		var impact: StringName = arrow.call("impact_signature") as StringName
		_expect_equal(motion, expected["motion"], str(expected["id"]) + " movement grammar")
		_expect_equal(impact, expected["impact"], str(expected["id"]) + " collision grammar")
		_expect_true(not motion_signatures.has(motion), str(expected["id"]) + " unique movement grammar")
		_expect_true(not impact_signatures.has(impact), str(expected["id"]) + " unique collision grammar")
		motion_signatures[motion] = true
		impact_signatures[impact] = true
		var trajectory: String = "%.4f/%.4f/%.4f" % [
			float(arrow.call("sample_motion_angle", 0.27)),
			float(arrow.call("sample_motion_angle", 0.81)),
			float(arrow.call("sample_motion_angle", 1.29)),
		]
		_expect_true(not trajectory_samples.has(trajectory),
			str(expected["id"]) + " visual orbit samples are unique")
		trajectory_samples[trajectory] = true
		visual_smoke_nodes.append(arrow)

		var missile: Node2D = MISSILE_SCENE.instantiate() as Node2D
		root.add_child(missile)
		missile.set("damage", 17)
		missile.set("pierce", 3)
		missile.call("configure_profile", hero.attack_profile,
			hero.projectile_primary, hero.projectile_secondary, hero.vfx_tier)
		var no_targets: Array[Node2D] = []
		missile.call("launch_volley", no_targets, 3, PackedInt32Array([7, 6, 5]))
		_expect_equal(int(missile.call("profile_id")), int(hero.attack_profile),
			str(expected["id"]) + " homing-shot profile passed")
		_expect_equal(float(missile.call("collision_radius")), 6.0,
			str(expected["id"]) + " homing-shot shared collision radius")
		_expect_equal(float(missile.call("blast_radius")), 26.0,
			str(expected["id"]) + " homing-shot shared blast radius")
		_expect_equal(_sum_ints(missile.get("_damages") as Array), 18,
			str(expected["id"]) + " profile leaves volley total damage unchanged")
		visual_smoke_nodes.append(missile)

		var signature: String = "%d/%.2f/%.2f/%.2f/%s" % [
			hero.health, hero.speed_scale, hero.damage_scale, hero.dash_scale,
			",".join(hero.opening),
		]
		_expect_true(not stat_signatures.has(signature),
			str(expected["id"]) + " unique movement, survival, and weapon mix")
		stat_signatures[signature] = true
		primary_colors.append(hero.projectile_primary)

		if previous != null:
			_expect_true(not _raw_dominates(hero, previous),
				str(expected["id"]) + "is not an upgrade of a cheaper hero")
		previous = hero

	_test_color_distance(primary_colors)
	_expect_equal(ranged_budgets, [5, 5, 6, 5, 6, 5],
		"raising price does not increase power-0 long-range total damage")
	for index in melee_rates.size():
		_expect_true(melee_rates[index] >= 0.8 and melee_rates[index] <= 1.3,
			str(CASES[index]["id"]) + " melee DPS sidegrade range")
	_expect_true(not _strictly_increasing(ranged_budgets), "no ranged-DPS price ladder")
	_expect_true(not _strictly_increasing_floats(melee_rates), "no melee-DPS price ladder")
	_test_tier_is_visual_only()
	await _test_profiles_hit_aimed_targets()
	await _test_missile_power_never_reverses()
	await _test_missile_store_capture_visual_proof()
	# Run every profile's live physics/draw for at least two frames, so a getter-only
	# matching, then catch regressions that error at runtime in orbit arrays or draw shapes.
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame
	for node in visual_smoke_nodes:
		if is_instance_valid(node):
			node.queue_free()

	player.queue_free()
	await process_frame
	_finish()


func _test_missile_store_capture_visual_proof() -> void:
	var visual_parent := Node2D.new()
	root.add_child(visual_parent)
	var missile: Node2D = MISSILE_SCENE.instantiate() as Node2D
	missile.position = Vector2(320.0, 180.0)
	visual_parent.add_child(missile)
	var no_targets: Array[Node2D] = []
	missile.call("launch_volley", no_targets, 3, PackedInt32Array([3, 3, 3]))
	# Wait for two 15Hz tail samples and the actual CanvasItem draw after them.
	for frame in 12:
		await physics_frame
		await process_frame
	var state: Dictionary = missile.call("debug_store_capture_lanes")
	_expect_equal(int(state.get("live_lanes", 0)), 3, "capture volley has three live lanes")
	_expect_equal(int(state.get("visible_lanes", 0)), 3, "three lanes shown after the live proof")
	_expect_true(
		bool(state.get("missile_visible_in_tree", false)),
		"capture volley is shown in the live tree")
	_expect_true(
		float(state.get("effective_alpha", 0.0)) >= 0.99,
		"capture volley has valid alpha including parents")
	_expect_true(bool(state.get("missile_opaque", false)), "capture volley opaque")
	_expect_true(
		bool(state.get("draw_after_launch", false)),
		"actual draw notice after launch")
	_expect_true(
		bool(state.get("head_geometry_ready", false)),
		"head segment shape of the actual draw")
	_expect_true(
		bool(state.get("trail_geometry_ready", false)),
		"tail segment shape of the actual draw")

	missile.hide()
	state = missile.call("debug_store_capture_lanes")
	_expect_false(
		bool(state.get("missile_visible_in_tree", true)),
		"rejects capturing a hidden volley")
	_expect_equal(int(state.get("visible_lanes", -1)), 0, "hidden volley display lane 0")
	missile.show()

	visual_parent.modulate.a = 0.0
	state = missile.call("debug_store_capture_lanes")
	_expect_false(
		bool(state.get("missile_opaque", true)),
		"rejects capturing a volley whose parent alpha is 0")
	_expect_equal(
		int(state.get("visible_lanes", -1)), 0, "parent-alpha-0 volley display lane 0")
	visual_parent.modulate.a = 1.0

	var saved_trails: Array = (missile.get("_trails") as Array).duplicate(true)
	var empty_trails: Array = []
	for lane in saved_trails.size():
		empty_trails.append([])
	missile.set("_trails", empty_trails)
	state = missile.call("debug_store_capture_lanes")
	_expect_false(
		bool(state.get("trail_geometry_ready", true)),
		"rejects capturing a volley with no tail shape")
	_expect_equal(int(state.get("visible_lanes", -1)), 0, "shapeless volley display lane 0")
	missile.set("_trails", saved_trails)

	var saved_headings: Array = (missile.get("_headings") as Array).duplicate()
	var empty_headings: Array[Vector2] = []
	for lane in saved_headings.size():
		empty_headings.append(Vector2.ZERO)
	missile.set("_headings", empty_headings)
	state = missile.call("debug_store_capture_lanes")
	_expect_false(
		bool(state.get("head_geometry_ready", true)),
		"rejects capturing a volley with no head shape")
	_expect_equal(int(state.get("visible_lanes", -1)), 0, "headless volley display lane 0")
	missile.set("_headings", saved_headings)

	var saved_draw_serial: int = int(missile.get("_capture_draw_serial"))
	missile.set(
		"_capture_draw_serial", int(missile.get("_capture_launch_draw_serial")))
	state = missile.call("debug_store_capture_lanes")
	_expect_false(
		bool(state.get("draw_after_launch", true)),
		"rejects capturing a stale draw from before launch")
	_expect_equal(int(state.get("visible_lanes", -1)), 0, "stale draw display lane 0")
	missile.set("_capture_draw_serial", saved_draw_serial)

	visual_parent.queue_free()
	await process_frame


func _test_debug_hero_request() -> void:
	var request_path: String = str(HERO_REQUEST_SCRIPT.PATH)
	var absolute_path: String = ProjectSettings.globalize_path(request_path)
	DirAccess.remove_absolute(absolute_path)
	var expected_paths: Array[String] = []
	for expected in CASES:
		expected_paths.append(_hero_path(str(expected["id"])))
	_expect_equal(
		HERO_REQUEST_SCRIPT.HERO_PATHS,
		expected_paths,
		"adb debug select list matches the 6-hero combat contract")

	# The release boundary neither reads nor consumes the request.
	_write_debug_hero_request(request_path, _hero_path("dancer"))
	_expect_equal(
		HERO_REQUEST_SCRIPT.take(false),
		"",
		"release fully ignores adb hero requests")
	_expect_true(
		FileAccess.file_exists(request_path),
		"the release boundary does not even touch request files")
	_expect_equal(
		HERO_REQUEST_SCRIPT.take(true),
		_hero_path("dancer"),
		"debug one-shot Dancer select")
	_expect_true(
		not FileAccess.file_exists(request_path),
		"debug hero request consumed immediately")

	for expected in CASES:
		var path: String = _hero_path(str(expected["id"]))
		_write_debug_hero_request(request_path, path)
		_expect_equal(
			HERO_REQUEST_SCRIPT.take(true),
			path,
			str(expected["id"]) + " adb debug combat select")

	_write_debug_hero_request(request_path, "res://resources/heroes/not-a-hero.tres")
	_expect_equal(
		HERO_REQUEST_SCRIPT.take(true),
		"",
		"rejects an off-list adb hero request")
	_expect_true(
		not FileAccess.file_exists(request_path),
		"a bad adb request is still consumed before restart")


func _write_debug_hero_request(path: String, hero_path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect_true(file != null, "adb debug hero-request file created")
	if file != null:
		file.store_string(hero_path + "\n")
		file.close()


func _test_resource(hero: Hero, expected: Dictionary, index: int) -> void:
	var id: String = str(expected["id"])
	_expect_equal(hero.attack_profile, expected["profile"], id + " profile")
	_expect_equal(hero.vfx_tier, int(expected["tier"]), id + " VFX tier by price")
	_expect_equal(hero.vfx_tier, index, id + " VFX is free0→highest5")
	_expect_equal(hero.health, int(expected["health"]), id + " starting hearts")
	_expect_approx(hero.speed_scale, float(expected["speed"]), id + " move multiplier")
	_expect_approx(hero.damage_scale, float(expected["damage"]), id + " damage multiplier")
	_expect_approx(hero.dash_scale, float(expected["dash"]), id + " dash multiplier")
	_expect_equal(hero.opening.size(), (expected["opening"] as Array).size(), id + " starting relic count")
	for opening_name in expected["opening"]:
		_expect_true(hero.opening.has("res://resources/relics/" + str(opening_name)),
			id + " starting relic " + str(opening_name))
	_expect_true(int(expected["price"]) == 0 or int(expected["price"]) \
		== 499 + 500 * (index - 1), id + " price-tier contract")


func _test_assets(hero: Hero, id: String) -> void:
	var root_path: String = "res://assets/custom/actors/heroes/%s/" % id
	_expect_true(hero.walk_sheet != null, id + " walk sheet")
	_expect_true(hero.idle_sheet != null, id + " idle sheet")
	_expect_true(hero.portrait != null, id + " portrait")
	if hero.walk_sheet != null:
		_expect_equal(hero.walk_sheet.resource_path, root_path + "walk.png", id + " walk path")
		_expect_equal(Vector2i(hero.walk_sheet.get_size()), Vector2i(192, 256), id + " walk 192x256")
	if hero.idle_sheet != null:
		_expect_equal(hero.idle_sheet.resource_path, root_path + "idle.png", id + " idle path")
		_expect_equal(Vector2i(hero.idle_sheet.get_size()), Vector2i(192, 256), id + " idle 192x256")
	if hero.portrait != null:
		_expect_equal(hero.portrait.resource_path, root_path + "portrait.png", id + " portrait path")
		_expect_equal(Vector2i(hero.portrait.get_size()), Vector2i(96, 96), id + " portrait 96x96")


func _test_player_profile(player: Player, hero: Hero, expected: Dictionary) -> void:
	var id: String = str(expected["id"])
	_expect_true(player.apply_hero_visual(hero), id + " Player sheet applied")
	_expect_equal(player.attack_profile_id(), int(hero.attack_profile), id + " Player profile")
	_expect_equal(player.hero_vfx_tier(), hero.vfx_tier, id + " Player VFX tier")
	var cast: MoonlightCast = player.get_node("MoonlightCast") as MoonlightCast
	_expect_equal(cast.profile_id(), int(hero.attack_profile), id + " cast-glow profile")
	_expect_equal(cast.vfx_tier(), hero.vfx_tier, id + " cast-glow VFX tier")


func _opening_state(hero: Hero) -> Dictionary:
	var health: int = hero.health
	var speed: float = hero.speed_scale
	var attack_cooldown_scale: float = 1.0
	var dash: float = hero.dash_scale
	var count_cards: int = 0
	var pierce: int = 1
	var relics: Array[Relic] = []
	for path in hero.opening:
		var relic: Relic = load(path) as Relic
		_expect_true(relic != null, hero.resource_path.get_file() + " starting relic loaded")
		if relic == null:
			continue
		relics.append(relic)
		match relic.effect:
			Relic.Effect.MOVE_SPEED: speed += relic.amount / Player.DEFAULT_SPEED
			Relic.Effect.MAX_HEALTH: health += int(relic.amount)
			Relic.Effect.ATTACK_SPEED: attack_cooldown_scale *= relic.amount
			Relic.Effect.DASH_COOLDOWN: dash *= relic.amount
			Relic.Effect.ARROW_COUNT: count_cards += int(relic.amount)
			Relic.Effect.ARROW_PIERCE: pierce += int(relic.amount)
	for family in [Relic.Family.STARFALL, Relic.Family.FULL_MOON, Relic.Family.MOON_DANCE]:
		_expect_true(not Relic.family_evolved(relics, family),
			hero.resource_path.get_file() + " does not start already fully evolved")
	return {
		"health": health, "speed": speed,
		"attack_cooldown_scale": attack_cooldown_scale,
		"dash": dash, "count_cards": count_cards, "pierce": pierce,
	}


func _test_sidegrade(hero: Hero, opening: Dictionary, index: int) -> void:
	if index == 0:
		return
	var has_tradeoff: bool = int(opening["health"]) < 5 \
		or float(opening["speed"]) < 1.0 \
		or hero.damage_scale < 1.0 \
		or float(opening["dash"]) > 1.0
	_expect_true(has_tradeoff, hero.resource_path.get_file() + " explicit weakness vs Warden")
	_expect_true(hero.opening.size() <= 2, hero.resource_path.get_file() + " does not skip early growth")


func _ranged_budget(hero: Hero, opening: Dictionary) -> int:
	var base_damage: int = maxi(int(round(5.0 * hero.damage_scale)), 1)
	return MissileProgression.damage_budget(
		base_damage, 0, int(opening["count_cards"]))


func _raw_dominates(costlier: Hero, cheaper: Hero) -> bool:
	return costlier.health >= cheaper.health \
		and costlier.speed_scale >= cheaper.speed_scale \
		and costlier.damage_scale >= cheaper.damage_scale \
		and costlier.dash_scale <= cheaper.dash_scale


func _test_color_distance(colors: Array[Color]) -> void:
	for first in colors.size():
		for second in range(first + 1, colors.size()):
			var a := Vector3(colors[first].r, colors[first].g, colors[first].b)
			var b := Vector3(colors[second].r, colors[second].g, colors[second].b)
			_expect_true(a.distance_squared_to(b) >= 0.1,
				"%s·%s projectile main colors distinct" % [CASES[first]["id"], CASES[second]["id"]])


func _test_tier_is_visual_only() -> void:
	var hero: Hero = load(_hero_path("sage")) as Hero
	var arrow: Node2D = ARROW_SCENE.instantiate() as Node2D
	root.add_child(arrow)
	arrow.process_mode = Node.PROCESS_MODE_DISABLED
	arrow.set("damage", 19)
	arrow.set("pierce", 4)
	arrow.call("configure_profile", hero.attack_profile,
		hero.projectile_primary, hero.projectile_secondary, 0, 1, 3)
	var angle_without_richness: float = float(arrow.call("sample_motion_angle", 0.81))
	arrow.call("configure_profile", hero.attack_profile,
		hero.projectile_primary, hero.projectile_secondary, 5, 1, 3)
	_expect_approx(float(arrow.call("sample_motion_angle", 0.81)),
		angle_without_richness, "VFX tier does not change straight-shot orbit")
	_expect_equal(float(arrow.call("collision_radius")), 7.0,
		"VFX tier does not change straight-shot collision radius")
	_expect_equal(int(arrow.get("damage")), 19, "VFX tier does not change straight-shot damage")
	_expect_equal(int(arrow.get("pierce")), 4, "VFX tier does not change straight-shot pierce")
	arrow.queue_free()


func _test_profiles_hit_aimed_targets() -> void:
	# Fire near/mid/far targets at once per profile. In the past, visual shake was
	# applied it to movement, so Eclipse missed aimed shots from 50px and Warden missed at range.
	var arrows: Array[Node2D] = []
	var targets: Array[TargetSpirit] = []
	var distances: Array[float] = [80.0, 200.0, 360.0]
	for profile_index in CASES.size():
		var expected: Dictionary = CASES[profile_index]
		var hero: Hero = load(_hero_path(str(expected["id"]))) as Hero
		for distance_index in distances.size():
			var lane_y: float = float(profile_index * distances.size() + distance_index) * 24.0
			var target := TargetSpirit.new()
			target.global_position = Vector2(distances[distance_index], lane_y)
			root.add_child(target)
			targets.append(target)

			var arrow: Node2D = ARROW_SCENE.instantiate() as Node2D
			arrow.global_position = Vector2(0.0, lane_y)
			root.add_child(arrow)
			arrow.set("pierce", 1)
			arrow.call("configure_profile", hero.attack_profile,
				hero.projectile_primary, hero.projectile_secondary, hero.vfx_tier, 1, 3)
			var candidates: Array[Node2D] = [target]
			arrow.call("set_candidates", candidates)
			arrow.call("launch", Vector2.RIGHT)
			arrows.append(arrow)

	# Reaching a 360px target needs 1.72s. Run a real physics sweep for 2s.
	for _frame in 120:
		await physics_frame
	for index in targets.size():
		var profile_index: int = index / distances.size()
		var distance_index: int = index % distances.size()
		_expect_equal(targets[index].hits, 1,
			"%s aimed hit on a %.0fpx target" % [
				CASES[profile_index]["id"], distances[distance_index]])
	for arrow in arrows:
		if is_instance_valid(arrow):
			arrow.queue_free()
	for target in targets:
		if is_instance_valid(target):
			target.queue_free()
	await process_frame


func _test_missile_power_never_reverses() -> void:
	# The power-3 guided volley used to be weaker up close than the power-2 straight center shot (7 from base 5).
	# Reproduce the close-range weaken regression with a live 30Hz sweep. Fire all six profiles and
	# every homing rank together, and check aimed meteors and effective damage stay per rank.
	var records: Array[Dictionary] = []
	var previous_lanes_by_hero: Dictionary = {}
	var previous_damages_by_hero: Dictionary = {}
	var row: int = 0
	for expected in CASES:
		var hero: Hero = load(_hero_path(str(expected["id"]))) as Hero
		for power in range(MissileProgression.HOMING_AT, MissileProgression.MAX_POWER + 1):
			var lane_y: float = float(row) * 64.0
			row += 1
			var target := DurableTargetSpirit.new()
			target.global_position = Vector2(50.0, lane_y)
			root.add_child(target)

			var lanes: PackedInt32Array = MissileProgression.guided_lane_damages(
				5, power)
			var missile: Node2D = MISSILE_SCENE.instantiate() as Node2D
			missile.global_position = Vector2(0.0, lane_y)
			root.add_child(missile)
			missile.call("configure_profile", hero.attack_profile,
				hero.projectile_primary, hero.projectile_secondary, hero.vfx_tier)
			var candidates: Array[Node2D] = [target]
			missile.call("set_candidates", candidates)
			missile.call("launch_volley", candidates, lanes.size(), lanes)
			var formation: Array = missile.get("_lanes") as Array
			var anchors: Array = missile.get("_anchors") as Array
			_expect_approx(float(formation[0]), 0.0,
				str(expected["id"]) + " power %d aim meteor center orbit" % power)
			_expect_true(bool(anchors[0]),
				str(expected["id"]) + " power %d aim meteor 0" % power)
			var hero_id: String = str(expected["id"])
			if previous_lanes_by_hero.has(hero_id):
				var previous_lanes: Array = previous_lanes_by_hero[hero_id] as Array
				var previous_damages: PackedInt32Array = \
					previous_damages_by_hero[hero_id] as PackedInt32Array
				for lane_index in previous_lanes.size():
					_expect_approx(
						float(formation[lane_index]),
						float(previous_lanes[lane_index]),
						"%s power %d existing lane %d orbit preserved" % [
							hero_id, power, lane_index])
					_expect_true(
						lanes[lane_index] >= previous_damages[lane_index],
						"%s power %d existing lane %d damage does not drop" % [
							hero_id, power, lane_index])
			previous_lanes_by_hero[hero_id] = formation.duplicate()
			previous_damages_by_hero[hero_id] = lanes.duplicate()
			records.append({
				"hero": hero_id,
				"power": power,
				"minimum": lanes[0],
				"target": target,
				"missile": missile,
			})

	for _frame in 100:
		await physics_frame
	var previous_by_hero: Dictionary = {}
	for record in records:
		var target: DurableTargetSpirit = record["target"] as DurableTargetSpirit
		var hero_id: String = str(record["hero"])
		var power: int = int(record["power"])
		_expect_true(target.hits >= 1,
			"%s power %d close-range aim meteor hit" % [hero_id, power])
		_expect_true(target.damage_taken >= int(record["minimum"]),
			"%s power %d close-range center damage preserved" % [hero_id, power])
		if previous_by_hero.has(hero_id):
			var previous_damage: int = int(previous_by_hero[hero_id])
			_expect_true(
				target.damage_taken >= previous_damage,
				"%s power %d close-range effective damage monotonic (%d→%d)" % [
					hero_id, power, previous_damage, target.damage_taken])
		previous_by_hero[hero_id] = target.damage_taken
		if is_instance_valid(record["missile"]):
			(record["missile"] as Node).queue_free()
		if is_instance_valid(target):
			target.queue_free()
	await process_frame


func _hero_path(id: String) -> String:
	return "res://resources/heroes/%s.tres" % id


func _sum_ints(values: Array) -> int:
	var result: int = 0
	for value in values:
		result += int(value)
	return result


func _strictly_increasing(values: Array[int]) -> bool:
	for i in range(1, values.size()):
		if values[i] <= values[i - 1]:
			return false
	return true


func _strictly_increasing_floats(values: Array[float]) -> bool:
	for i in range(1, values.size()):
		if values[i] <= values[i - 1]:
			return false
	return true


func _finish() -> void:
	if _failed > 0:
		printerr("hero combat-profile test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("hero combat-profile test passed — ", _checked, " case(s)")
	quit(0)


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


func _expect_approx(actual: float, expected: float, label: String) -> void:
	_checked += 1
	if is_equal_approx(actual, expected):
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)
