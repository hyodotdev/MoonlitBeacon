extends Node

## Six real primary weapons on the real arena path.
##
## Each hero's melee swing and moon-wheel volley read base numbers from
## `HeroWeapons`, not one shared default: sword cone, alternating twin cuts,
## rifle pierce line, shotgun fan, delayed cannon blast, timed orbit sweep.
## This drives the live `Arena` scene per hero — swings, volleys, relics, cores,
## resets — so six names or colors alone cannot pass it.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const ARROW_SCENE: PackedScene = preload("res://scenes/actors/moon_arrow.tscn")
const HERO_IDS: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage",
]

var _failed: int = 0
var _checked: int = 0


class DurableTargetSpirit:
	extends Node2D

	var hits: int = 0
	var damage_taken: int = 0
	var attackable: bool = true

	func is_attackable() -> bool:
		return attackable

	func take_damage(amount: int, _at: Vector2) -> void:
		hits += 1
		damage_taken += amount


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	_run.call_deferred()


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("hero-weapon test aborted: user:// path is not isolated — ", user_root)
	return safe


func _run() -> void:
	_test_spec_table()
	await _test_warden_cone()
	await _test_dancer_twins()
	await _test_sage_rifle()
	await _test_keeper_shotgun()
	await _test_muzzle_coherence()
	await _test_guided_volley_agreement()
	await _test_knight_cannon()
	await _test_eclipse_orbit()
	await _test_full_circle_antipodal_ring()
	await _test_full_moon_circle()
	await _test_wide_arc_full_circle()
	await _test_swing_arc_precision()
	await _test_rate_floors()
	await _test_invalid_targets()
	await _test_resets_and_growth()
	await _test_price_tier_never_matters()
	await _test_cleanup()
	await _test_same_target_comparison()
	await _test_grouped_comparison()
	if _failed > 0:
		printerr("hero-weapon test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("hero-weapon test passed — ", _checked, " case(s)")
	get_tree().quit(0)


## The profile table itself: six distinct rows keyed by profile only, no price or tier.
func _test_spec_table() -> void:
	var signatures: Dictionary = {}
	for hero_id in HERO_IDS:
		var profile: Hero.AttackProfile = HeroWeapons.profile_of(hero_id)
		var melee: Dictionary = HeroWeapons.melee_spec(profile)
		var ranged: Dictionary = HeroWeapons.ranged_spec(profile)
		var signature: String = "%s|%s" % [str(melee), str(ranged)]
		_expect_true(not signatures.has(signature),
			hero_id + " weapon row differs from every other hero")
		signatures[signature] = true
		_expect_true(float(melee["reach"]) > 0.0, hero_id + " melee reach set")
		_expect_true(float(melee["cooldown"]) > 0.0, hero_id + " melee cadence set")
		_expect_true(float(melee["damage"]) > 0.0, hero_id + " melee damage set")
		_expect_true(float(ranged["range"]) > 0.0, hero_id + " ranged reach set")
		_expect_true(float(ranged["cooldown"]) > 0.0, hero_id + " ranged cadence set")
		_expect_true(float(ranged["damage"]) > 0.0, hero_id + " ranged damage set")
		_expect_true(int(ranged["lanes"]) >= 1, hero_id + " at least one lane")
		_expect_true(not melee.has("price") and not ranged.has("price"),
			hero_id + " spec has no price key")
		_expect_true(not melee.has("vfx_tier") and not ranged.has("vfx_tier"),
			hero_id + " spec has no tier key")


## Fresh live arena running one hero at pure Lv1: no relics, no cores, no moonfire.
## The arena's own `_process` stays off so every swing and volley below is explicit;
## physics still flies every projectile for real.
func _fresh_arena(hero_id: String) -> Array:
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	for spirit in (arena.get("_spirits") as Array).duplicate():
		if is_instance_valid(spirit):
			spirit.queue_free()
	(arena.get("_spirits") as Array).clear()
	arena.set("_spawn_timer", 99999.0)
	arena.set("_raid_left", 99999.0)
	arena.set_process(false)
	var hero: Hero = load("res://resources/heroes/%s.tres" % hero_id) as Hero
	arena.set("_run_hero", hero)
	arena.set("_run_hero_path", "res://resources/heroes/%s.tres" % hero_id)
	var player: Node2D = arena.get_node("Player") as Node2D
	_expect_true(player.call("apply_hero_visual", hero),
		hero_id + " hero visual applies on the live player")
	arena.call("_recompute")
	arena.call("_settle_rates")
	return [arena, player, hero]


func _target(arena: Node2D, player: Node2D, offset: Vector2) -> DurableTargetSpirit:
	return _target_global(
		arena, (player as Node2D).global_position + offset)


func _target_global(arena: Node2D, at: Vector2) -> DurableTargetSpirit:
	var double := DurableTargetSpirit.new()
	arena.add_child(double)
	double.global_position = at
	(arena.get("_spirits") as Array).append(double)
	return double


## Point on the real firing ray: shots aim from the player's shot anchor, so
## close-range test geometry must follow the ray, not the floor.
func _ray_global(
	player: Node2D, through_local: Vector2, distance: float
) -> Vector2:
	var origin: Vector2 = player.call("shot_anchor")
	var through: Vector2 = (player as Node2D).global_position + through_local
	var direction: Vector2 = (through - origin).normalized()
	return origin + direction * distance


func _swing(arena: Node2D, player: Node2D, target: Node2D) -> void:
	player.set("_attack_cooldown", 0.0)
	arena.call("_swing_at", target)


func _volley(arena: Node2D) -> void:
	arena.set("_arrow_timer", 0.0)
	arena.call("_fire_arrows", 1.0)


func _free_arena(arena: Node2D) -> void:
	# Friendly projectiles and sparks are arena children: freeing the arena frees them.
	for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
		if is_instance_valid(projectile) and projectile.is_inside_tree() \
				and arena.is_ancestor_of(projectile):
			projectile.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_warden_cone() -> void:
	var setup: Array = await _fresh_arena("warden")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	_expect_equal(float(player.get("attack_range")), 46.0, "warden sword reach")
	_expect_equal(float(player.get("attack_arc")), 130.0, "warden sword fan")
	_expect_equal(float(player.get("attack_cooldown_time")), 0.50, "warden sword cadence")
	_expect_equal(int(player.get("attack_damage")), 10, "warden sword damage")
	var front: DurableTargetSpirit = _target(arena, player, Vector2(40, 0))
	var side: DurableTargetSpirit = _target(arena, player, Vector2(0, 45))
	var behind: DurableTargetSpirit = _target(arena, player, Vector2(-40, 0))
	var far: DurableTargetSpirit = _target(arena, player, Vector2(60, 0))
	_swing(arena, player, front)
	_expect_equal(front.hits, 1, "sword cone hits ahead")
	_expect_equal(side.hits, 0, "sword cone misses the flank")
	_expect_equal(behind.hits, 0, "sword cone misses behind")
	_expect_equal(far.hits, 0, "sword cone misses past reach")
	_expect_true((player.get_node("Slash") as Sprite2D).visible,
		"sword crescent shows on the swing")
	_expect_true(
		(arena.get_node("WeaponSfx") as AudioStreamPlayer).stream
			== load("res://assets/custom/audio/sfx/weapon_sword.wav"),
		"sword voice on the swing")
	await _free_arena(arena)


func _test_dancer_twins() -> void:
	var setup: Array = await _fresh_arena("dancer")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	_expect_equal(float(player.get("attack_range")), 38.0, "twin blade reach")
	_expect_equal(float(player.get("attack_cooldown_time")), 0.30, "twin blade cadence")
	var left: DurableTargetSpirit = _target(arena, player,
		Vector2.RIGHT.rotated(deg_to_rad(28.0)) * 35.0)
	var right: DurableTargetSpirit = _target(arena, player,
		Vector2.RIGHT.rotated(deg_to_rad(-28.0)) * 35.0)
	var anchor: DurableTargetSpirit = _target(arena, player, Vector2(35, 0))
	anchor.attackable = false
	_swing(arena, player, _mid_target(arena, player))
	_expect_equal(float(arena.get("_twin_side")), -1.0, "first cut flips the side")
	_swing(arena, player, _mid_target(arena, player))
	_expect_equal(float(arena.get("_twin_side")), 1.0, "second cut flips back")
	_expect_equal(left.hits, 1, "first cut lands left")
	_expect_equal(right.hits, 1, "second cut lands right")
	_expect_equal(anchor.hits, 0, "a non-attackable anchor never takes a cut")
	_expect_true(
		str((player.get_node("WeaponRig") as Node).get("_kind")) == "twin_cut",
		"twin-cut tick shows on the rig")
	await _free_arena(arena)


## A raw aim point between the twin targets: a plain Node2D the arena can face.
## Kept out of `_spirits` so it never takes a cut itself.
func _mid_target(arena: Node2D, player: Node2D) -> Node2D:
	var aim := Node2D.new()
	arena.add_child(aim)
	aim.global_position = (player as Node2D).global_position + Vector2(35, 0)
	return aim


func _test_sage_rifle() -> void:
	var setup: Array = await _fresh_arena("sage")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	_expect_equal(float(arena.get("_ranged_range")), 300.0, "rifle line reach")
	_expect_equal(float(arena.get("_arrow_cooldown")), 1.20, "rifle cadence")
	_expect_equal(int(arena.get("_arrow_pierce")), 6, "rifle pierce")
	var near: DurableTargetSpirit = _target(arena, player, Vector2(100, 0))
	var mid_at: Vector2 = _ray_global(player, Vector2(100, 0), 180.0)
	var far_at: Vector2 = _ray_global(player, Vector2(100, 0), 260.0)
	var mid: DurableTargetSpirit = _target_global(arena, mid_at)
	var far: DurableTargetSpirit = _target_global(arena, far_at)
	var ray: Vector2 = (mid_at - far_at).normalized().orthogonal()
	var off_line: DurableTargetSpirit = _target_global(arena, mid_at + ray * 40.0)
	_volley(arena)
	var bolts: Array[Node] = get_tree().get_nodes_in_group("friendly_projectiles")
	_expect_equal(bolts.size(), 1, "rifle fires one bolt")
	if bolts.size() == 1:
		_expect_equal(float(bolts[0].get("speed")), 340.0, "rifle bolt velocity")
		_expect_equal(float(bolts[0].get("blast_radius")), 0.0, "rifle bolt flies clean")
	for frame in 120:
		await get_tree().physics_frame
		if near.hits > 0 and mid.hits > 0 and far.hits > 0:
			break
	_expect_equal(near.hits, 1, "rifle pierces the first body")
	_expect_equal(mid.hits, 1, "rifle pierces the second body")
	_expect_equal(far.hits, 1, "rifle pierces the third body")
	_expect_equal(off_line.hits, 0, "rifle misses off the line")
	_expect_equal(near.damage_taken, 20, "rifle bolt carries the whole budget")
	await _free_arena(arena)


func _test_keeper_shotgun() -> void:
	var setup: Array = await _fresh_arena("keeper")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	_expect_equal(float(arena.get("_ranged_range")), 125.0, "shotgun reach")
	_expect_equal(int(arena.get("_ranged_lanes")), 5, "shotgun lanes")
	# One body per lane ray from the hand anchor: 0 and ±15/±30 degrees.
	# Distances keep the center body nearest-to-player (so the fan aims 0°),
	# each lane clear of its neighbor's body, and each lane's own body first
	# along its ray. The hand sits 12px below the old candle, so the upper
	# lanes stand further out to hold the same nearest-center ordering.
	var origin: Vector2 = player.call("shot_anchor")
	var bodies: Array[DurableTargetSpirit] = []
	var distances: Array[float] = [68.0, 75.0, 72.0, 81.0, 70.0]
	var lane_index: int = 0
	for degrees in [0.0, 15.0, -15.0, 30.0, -30.0]:
		bodies.append(_target_global(
			arena, origin + Vector2.RIGHT.rotated(deg_to_rad(degrees))
				* distances[lane_index]))
		lane_index += 1
	var beyond: DurableTargetSpirit = _target_global(arena, origin + Vector2(150, 60))
	_volley(arena)
	var pellets: Array[Node] = get_tree().get_nodes_in_group("friendly_projectiles")
	_expect_equal(pellets.size(), 5, "shotgun fires a five-pellet fan")
	for frame in 90:
		await get_tree().physics_frame
		var connected: bool = true
		for body in bodies:
			connected = connected and body.hits > 0
		if connected:
			break
	# Even 41/5 split [9,8,8,8,8], one lane per body, no center carrier.
	var want: Array[int] = [9, 8, 8, 8, 8]
	for lane in bodies.size():
		_expect_equal(bodies[lane].damage_taken, want[lane],
			"shotgun lane %d carries its share" % lane)
	_expect_equal(beyond.hits, 0, "shotgun falls off past range")
	var spread: int = 0
	for body in bodies:
		spread += body.damage_taken
	_expect_equal(spread, 41, "five pellets share the whole budget evenly")
	await _free_arena(arena)


## One fired shot has one origin: the live volley spawns on the held gun's
## muzzle, flies its lane, seats the side hand on vertical aims, and the cast
## cue rides the muzzle too. Melee backup still leaves from the candle.
func _test_muzzle_coherence() -> void:
	var sides: Dictionary = {
		"right": Vector2.RIGHT, "left": Vector2.LEFT,
		"up": Vector2.UP, "down": Vector2.DOWN,
	}
	# Independent muzzle seats: the helper must agree with these literals,
	# not just with itself.
	var seats: Dictionary = {"sage": 16.0, "keeper": 9.0, "knight": 9.0}
	for hero_id in ["sage", "keeper", "knight"]:
		for side in sides.keys():
			var setup: Array = await _fresh_arena(hero_id)
			var arena: Node2D = setup[0]
			var player: Node2D = setup[1]
			var aim: Vector2 = sides[side] as Vector2
			var mark: DurableTargetSpirit = _target(arena, player, aim * 120.0)
			_volley(arena)
			var shots: Array[Node] = _arena_shots(arena)
			_expect_true(not shots.is_empty(),
				"%s %s volley leaves the gun" % [hero_id, side])
			# The arena's own two-pass aim: anchor, then the side hand.
			var anchor: Vector2 = player.call("shot_anchor")
			var base: Vector2 = (mark.global_position - anchor).normalized()
			base = (mark.global_position - player.call("hand_for_aim", base)).normalized()
			for shot in shots:
				var lane: Vector2 = shot.get("_base_direction") as Vector2
				var muzzle: Vector2 = player.call("muzzle_origin", lane)
				var want: Vector2 = player.to_global(Player.WEAPON_GRIP \
					+ Player.side_shift(lane)) \
					+ lane * float(seats[hero_id])
				_expect_true(muzzle.distance_to(want) < 0.01,
					"%s %s muzzle helper matches its seat" % [hero_id, side])
				_expect_true(
					(shot as Node2D).global_position.distance_to(muzzle) < 0.5,
					"%s %s shot spawns on its lane muzzle" % [hero_id, side])
			var rig: Node2D = player.get_node("WeaponRig") as Node2D
			_expect_equal(rig.position,
				Player.WEAPON_GRIP + Player.side_shift(base),
				"%s %s seats the hand off the face" % [hero_id, side])
			var cast: Node2D = player.get_node("MoonlightCast") as Node2D
			_expect_true(
				cast.global_position.distance_to(player.call("muzzle_origin", base)) < 0.5,
				"%s %s cast cue rides the muzzle" % [hero_id, side])
			if hero_id == "knight":
				await _expect_recoil_settles(player, side)
			for frame in 90:
				await get_tree().physics_frame
				if mark.hits > 0:
					break
			_expect_true(mark.hits > 0,
				"%s %s aimed shot connects" % [hero_id, side])
			await _free_arena(arena)
	# Melee heroes keep the small moonlight backup: sparks leave the candle.
	var backup: Array = await _fresh_arena("warden")
	var backup_arena: Node2D = backup[0]
	var backup_player: Node2D = backup[1]
	_target(backup_arena, backup_player, Vector2(120, 0))
	_volley(backup_arena)
	var sparks: Array[Node] = _arena_shots(backup_arena)
	_expect_true(not sparks.is_empty(), "warden backup sparks fly")
	var candle: Vector2 = backup_player.call("moonlight_origin")
	for spark in sparks:
		_expect_true(
			(spark as Node2D).global_position.distance_to(candle) < 0.5,
			"warden backup spark spawns at the candle")
	_expect_equal(
		(backup_player.get_node("MoonlightCast") as Node2D).position,
		Player.MOONLIGHT_ORIGIN, "warden cast cue stays on the candle")
	await _free_arena(backup_arena)


## Cannon kick is seen and settled: the sprite jumps, then rests at its base
## inside the 0.2s strip gap, so a strip frame never catches a drift.
func _expect_recoil_settles(player: Node2D, side: String) -> void:
	var sprite: Node2D = player.get_node("Sprite") as Node2D
	var rest: Vector2 = Vector2(0.0, float(player.get("_sprite_base_y")))
	var kicked: bool = sprite.position.distance_to(rest) > 1.0
	for frame in 30:
		await get_tree().process_frame
		kicked = kicked or sprite.position.distance_to(rest) > 1.0
	_expect_true(kicked, "knight %s cannon kicks the sprite" % side)
	_expect_true(sprite.position.distance_to(rest) < 0.5,
		"knight %s recoil settles at rest" % side)


func _arena_shots(arena: Node2D) -> Array[Node]:
	var shots: Array[Node] = []
	for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
		if is_instance_valid(projectile) and arena.is_ancestor_of(projectile):
			shots.append(projectile)
	return shots


## A primed Starfall volley fires each hero's base lanes once, and the meteors
## total one damage budget. A wide hero at power 0 used to deal the anchor's
## whole damage per extra lane — five budgets for the Keeper.
func _test_guided_volley_agreement() -> void:
	for hero_id in ["keeper", "dancer", "knight"]:
		var setup: Array = await _fresh_arena(hero_id)
		var arena: Node2D = setup[0]
		var player: Node2D = setup[1]
		_target(arena, player, Vector2(80, 0))
		arena.set("_starfall_primed", true)
		_volley(arena)
		var shots: Array[Node] = get_tree().get_nodes_in_group("friendly_projectiles")
		_expect_equal(shots.size(), 1, hero_id + " starfall fires one meteor node")
		if shots.size() == 1:
			var damages: Array = shots[0].get("_damages") as Array
			var lanes: int = int(arena.get("_ranged_lanes"))
			_expect_equal(damages.size(), lanes,
				hero_id + " meteors match base lanes")
			var budget: int = MissileProgression.damage_budget(
				int(arena.get("_arrow_damage")), 0,
				maxi(int(arena.get("_arrow_count")) - 1, 0))
			var total: int = 0
			for lane in damages:
				total += int(lane)
			_expect_equal(total, maxi(budget, lanes),
				hero_id + " meteors total one budget, never cloned")
		await _free_arena(arena)
	# Awakened homing at power 5 on the live path: moonfire boosts the budget,
	# the split still totals it exactly.
	var hot: Array = await _fresh_arena("keeper")
	var hot_arena: Node2D = hot[0]
	_target(hot_arena, hot[1], Vector2(80, 0))
	hot_arena.set("_missile_power", 5)
	hot_arena.set("_moonfire_on", true)
	hot_arena.call("_settle_rates")
	hot_arena.set("_starfall_primed", true)
	_volley(hot_arena)
	var meteors: Array[Node] = get_tree().get_nodes_in_group("friendly_projectiles")
	_expect_equal(meteors.size(), 1, "awakened starfall fires one meteor node")
	if meteors.size() == 1:
		var hot_damages: Array = meteors[0].get("_damages") as Array
		_expect_equal(hot_damages.size(), 5, "awakened meteors keep five lanes")
		var hot_budget: int = MissileProgression.damage_budget(
			int(hot_arena.get("_arrow_damage")), 5,
			maxi(int(hot_arena.get("_arrow_count")) - 1, 0))
		var hot_total: int = 0
		for lane in hot_damages:
			hot_total += int(lane)
		_expect_equal(hot_total, hot_budget,
			"awakened meteors total the boosted budget, never cloned")
	await _free_arena(hot_arena)


func _test_knight_cannon() -> void:
	var setup: Array = await _fresh_arena("knight")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	_expect_equal(float(arena.get("_arrow_cooldown")), 2.10, "cannon cadence")
	_expect_equal(float(arena.get("_ranged_blast")), 48.0, "cannon blast radius")
	var direct: DurableTargetSpirit = _target(arena, player, Vector2(120, 0))
	var caught: DurableTargetSpirit = _target(arena, player, Vector2(140, 25))
	var clear: DurableTargetSpirit = _target(arena, player, Vector2(190, 0))
	_volley(arena)
	var shells: Array[Node] = get_tree().get_nodes_in_group("friendly_projectiles")
	_expect_equal(shells.size(), 1, "cannon fires one shell")
	if shells.size() == 1:
		_expect_equal(float(shells[0].get("speed")), 150.0, "cannon shell lobs slow")
		_expect_equal(float(shells[0].get("blast_radius")), 48.0,
			"cannon shell carries its blast")
	for frame in 150:
		await get_tree().physics_frame
		if direct.hits > 0 and caught.hits > 0:
			break
	_expect_equal(direct.hits, 1, "cannon shell strikes its mark")
	_expect_equal(direct.damage_taken, 22, "direct shell carries the budget")
	_expect_equal(caught.hits, 1, "cannon blast catches the neighbor")
	_expect_equal(caught.damage_taken, 22, "blast hits as hard as the shell")
	_expect_equal(clear.hits, 0, "cannon blast spares the far body")
	# A shell that meets nothing still goes off where it falls.
	var lone: DurableTargetSpirit = _target(arena, player, Vector2(12, 30))
	var shell: Node2D = ARROW_SCENE.instantiate() as Node2D
	arena.add_child(shell)
	shell.set("damage", 5)
	shell.set("pierce", 1)
	shell.set("speed", 210.0)
	shell.set("flight_time", 0.05)
	shell.set("blast_radius", 48.0)
	shell.call("set_candidates", arena.get("_spirits"))
	shell.global_position = (player as Node2D).global_position
	shell.call("launch", Vector2.RIGHT)
	for frame in 30:
		await get_tree().physics_frame
		if lone.hits > 0:
			break
	_expect_equal(lone.hits, 1, "a burnt-out shell still detonates")
	await _free_arena(arena)


func _test_eclipse_orbit() -> void:
	var setup: Array = await _fresh_arena("eclipse")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	_expect_equal(float(player.get("attack_range")), 64.0, "orbit ring reach")
	_expect_true((player.get_node("ScytheOrbit") as Node).call("is_active"),
		"scythe blades circle the Eclipse body")
	var ring: DurableTargetSpirit = _target(arena, player, Vector2(50, 0))
	var behind: DurableTargetSpirit = _target(arena, player, Vector2(-50, 0))
	var hole: DurableTargetSpirit = _target(arena, player, Vector2(20, 0))
	var outside: DurableTargetSpirit = _target(arena, player, Vector2(90, 0))
	var trigger: Node2D = arena.call("_nearest_spirit") as Node2D
	_expect_true(trigger == ring or trigger == behind,
		"orbit triggers on band presence")
	hole.attackable = false
	ring.attackable = false
	behind.attackable = false
	outside.attackable = false
	_expect_true(arena.call("_nearest_spirit") == null,
		"an empty band never triggers a sweep")
	hole.attackable = true
	ring.attackable = true
	behind.attackable = true
	outside.attackable = true
	_swing(arena, player, ring)
	_expect_equal(ring.hits, 1, "orbit sweep bites its ring")
	_expect_equal(behind.hits, 1, "orbit sweep is a full circle")
	_expect_equal(hole.hits, 0, "orbit sweep spares the hole at the feet")
	_expect_equal(outside.hits, 0, "orbit sweep spares past the ring")
	_expect_equal(float((player.get_node("ScytheOrbit") as Node).get("_pulse_age")),
		0.0, "sweep tick pulses the orbit")
	_expect_equal(int(player.get("attack_damage")), 9, "orbit sweep damage")
	await _free_arena(arena)


## The orbit ring bites every bearing in its band: eight compass points plus bodies
## just inside both radial edges, all hit by one sweep aimed ahead. The hole and
## past-the-rim bodies still go untouched.
func _test_full_circle_antipodal_ring() -> void:
	var setup: Array = await _fresh_arena("eclipse")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	var bodies: Array[DurableTargetSpirit] = []
	for degrees in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		bodies.append(_target(arena, player,
			Vector2.RIGHT.rotated(deg_to_rad(degrees)) * 50.0))
	var near_hole: DurableTargetSpirit = _target(arena, player, Vector2(36, 0))
	var near_edge: DurableTargetSpirit = _target(arena, player, Vector2(-63, 0))
	var hole: DurableTargetSpirit = _target(arena, player, Vector2(34, 0))
	var outside: DurableTargetSpirit = _target(arena, player, Vector2(65, 0))
	_swing(arena, player, bodies[0])
	for i in bodies.size():
		_expect_equal(bodies[i].hits, 1, "orbit ring bites bearing %d" % i)
	_expect_equal(near_hole.hits, 1, "orbit ring bites just outside the hole")
	_expect_equal(near_edge.hits, 1, "orbit ring bites just inside the rim")
	_expect_equal(hole.hits, 0, "orbit ring still spares the hole")
	_expect_equal(outside.hits, 0, "orbit ring still spares past the rim")
	await _free_arena(arena)


## A primed full-moon swing is a full circle on a partial-arc hero: the same
## behind-body an ordinary swing spares, the primed swing bites. Reach still ends.
func _test_full_moon_circle() -> void:
	var setup: Array = await _fresh_arena("warden")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	await _take_relics(arena, [
		"res://resources/relics/long_blade.tres",
		"res://resources/relics/swift_hand.tres",
	])
	_expect_true(
		Relic.family_resonant(arena.get("_taken"), Relic.Family.FULL_MOON),
		"full-moon build genuinely resonates")
	var reach: float = float(player.get("attack_range"))
	var front: DurableTargetSpirit = _target(arena, player, Vector2(40, 0))
	var behind: DurableTargetSpirit = _target(arena, player, Vector2(-40, 0))
	var past: DurableTargetSpirit = _target(
		arena, player, Vector2(reach * 1.15 + 5.0, 0))
	_swing(arena, player, front)
	_expect_equal(front.hits, 1, "ordinary swing bites ahead")
	_expect_equal(behind.hits, 0, "ordinary swing still spares behind")
	front.hits = 0
	behind.hits = 0
	arena.set("_full_moon_primed", true)
	_swing(arena, player, front)
	_expect_true(not bool(arena.get("_full_moon_primed")),
		"primed swing consumes its full-moon prime")
	_expect_equal(front.hits, 1, "full-moon swing bites ahead")
	_expect_equal(behind.hits, 1, "full-moon swing is a full circle")
	_expect_equal(past.hits, 0, "full-moon swing still ends at reach")
	await _free_arena(arena)


## Five genuine Wide Arc takes cap a Warden fan at 360 degrees, and the capped
## swing is a full circle: the behind-body the ordinary fan spares, it bites.
## Cadence is untouched and damage follows the existing overflow rule
## (130 * 1.25^5 = 396.7, capped at 360, so 36.7 leftover turns into damage).
func _test_wide_arc_full_circle() -> void:
	var setup: Array = await _fresh_arena("warden")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	var front: DurableTargetSpirit = _target(arena, player, Vector2(40, 0))
	var behind: DurableTargetSpirit = _target(arena, player, Vector2(-40, 0))
	var past: DurableTargetSpirit = _target(arena, player, Vector2(51, 0))
	_swing(arena, player, front)
	_expect_equal(front.hits, 1, "ordinary fan bites ahead")
	_expect_equal(behind.hits, 0, "ordinary fan spares behind")
	_expect_equal(past.hits, 0, "ordinary fan ends at reach")
	front.hits = 0
	behind.hits = 0
	await _take_relics(arena, [
		"res://resources/relics/wide_arc.tres",
		"res://resources/relics/wide_arc.tres",
		"res://resources/relics/wide_arc.tres",
		"res://resources/relics/wide_arc.tres",
		"res://resources/relics/wide_arc.tres",
	])
	_expect_equal(float(player.get("attack_arc")), 360.0,
		"five wide arcs cap the fan")
	_expect_equal(float(player.get("attack_cooldown_time")), 0.50,
		"wide arcs leave cadence alone")
	_expect_equal(int(player.get("attack_damage")), 11,
		"capped overflow follows the damage rule")
	_swing(arena, player, front)
	_expect_equal(front.hits, 1, "capped fan bites ahead")
	_expect_equal(behind.hits, 1, "capped fan is a full circle")
	_expect_equal(past.hits, 0, "capped fan still ends at reach")
	await _free_arena(arena)


## The PI boundary itself: a computed antipodal angle lands within one float ulp
## of PI, and single-precision PI sits above the double PI the old comparison
## used. Full-circle swings ignore the bearing entirely; partial fans keep the
## inclusive edge they always had.
func _test_swing_arc_precision() -> void:
	var setup: Array = await _fresh_arena("warden")
	var arena: Node2D = setup[0]
	var float_pi: float = PackedFloat32Array([PI])[0]
	_expect_true(float_pi > PI, "single-precision PI sits above double PI")
	_expect_true(bool(arena.call("_swing_arc_hits", 0.0, PI, true)),
		"full circle hits straight ahead")
	_expect_true(bool(arena.call("_swing_arc_hits", PI, PI, true)),
		"full circle hits the exact antipode")
	_expect_true(bool(arena.call("_swing_arc_hits", -PI, PI, true)),
		"full circle hits the mirrored antipode")
	_expect_true(bool(arena.call("_swing_arc_hits", float_pi, PI, true)),
		"full circle hits a rounding step past PI")
	_expect_true(bool(arena.call("_swing_arc_hits", -float_pi, PI, true)),
		"full circle hits a mirrored rounding step past PI")
	var half: float = deg_to_rad(130.0) * 0.5
	_expect_true(bool(arena.call("_swing_arc_hits", 0.0, half, false)),
		"partial fan hits straight ahead")
	_expect_true(bool(arena.call("_swing_arc_hits", half, half, false)),
		"partial fan keeps its inclusive edge")
	_expect_true(not bool(arena.call("_swing_arc_hits", half + 0.01, half, false)),
		"partial fan still misses past its edge")
	_expect_true(not bool(arena.call("_swing_arc_hits", PI, half, false)),
		"partial fan still misses exactly behind")
	_expect_true(not bool(arena.call("_swing_arc_hits", float_pi, half, false)),
		"partial fan still misses a rounding step past PI")
	# The capped arc counts as full circle through the same production path:
	# derive the flag the swing uses, then check the past-PI bearing with it.
	var capped: bool = bool(arena.call("_swing_full_circle", false, false, 360.0))
	var near_capped: bool = bool(
		arena.call("_swing_full_circle", false, false, 359.0))
	var ordinary: bool = bool(
		arena.call("_swing_full_circle", false, false, 130.0))
	_expect_true(capped, "a 360-degree arc is a full circle")
	_expect_true(not near_capped, "a 359-degree arc stays partial")
	_expect_true(not ordinary, "an ordinary fan stays partial")
	_expect_true(bool(arena.call("_swing_arc_hits", float_pi, PI, capped)),
		"a capped arc hits a rounding step past PI")
	var near_half: float = deg_to_rad(359.0) * 0.5
	_expect_true(not bool(arena.call(
		"_swing_arc_hits", float_pi, near_half, near_capped)),
		"a 359-degree arc still misses a rounding step past PI")
	_expect_true(not bool(arena.call(
		"_swing_arc_hits", PI, near_half, near_capped)),
		"a 359-degree arc still misses exactly behind")
	await _free_arena(arena)


## Production card takes, one frame apart so HUD and rate settles land.
func _take_relics(arena: Node2D, paths: Array) -> void:
	for path in paths:
		arena.call("_on_relic_picked",
			arena.get("_relic").call("take_named", path), false, "stage")
		await get_tree().process_frame
	arena.call("_settle_rates")


func _test_rate_floors() -> void:
	var setup: Array = await _fresh_arena("warden")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	arena.set("_relic_haste", 0.05)
	arena.call("_apply_haste")
	_expect_equal(float(player.get("attack_cooldown_time")), 0.11,
		"melee interval floors instead of vanishing")
	_expect_equal(int(player.get("attack_damage")), 44,
		"floored melee overflow turns into damage")
	var keeper: Array = await _fresh_arena("keeper")
	var keeper_arena: Node2D = keeper[0]
	keeper_arena.set("_arrow_haste", 0.05)
	keeper_arena.call("_settle_rates")
	_expect_equal(float(keeper_arena.get("_arrow_cooldown")), 0.34,
		"ranged interval floors instead of vanishing")
	_expect_true(int(keeper_arena.get("_arrow_damage")) > 100,
		"floored ranged overflow turns into damage")
	await _free_arena(arena)
	await _free_arena(keeper_arena)


func _test_invalid_targets() -> void:
	var setup: Array = await _fresh_arena("sage")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	var live: DurableTargetSpirit = _target(arena, player, Vector2(100, 0))
	var dead: DurableTargetSpirit = _target(arena, player, Vector2(40, 0))
	dead.queue_free()
	await get_tree().process_frame
	_swing(arena, player, live)
	_volley(arena)
	for frame in 90:
		await get_tree().physics_frame
		if live.hits > 0:
			break
	_expect_true(live.hits >= 1, "freed bodies are skipped, live ones still hit")
	await _free_arena(arena)


func _test_resets_and_growth() -> void:
	var setup: Array = await _fresh_arena("warden")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	var blade: Relic = load("res://resources/relics/long_blade.tres") as Relic
	arena.call("_feed", blade)
	_expect_true(float(player.get("attack_range")) > 46.0,
		"reach relic lengthens the sword")
	arena.call("_recompute")
	arena.call("_settle_rates")
	_expect_equal(float(player.get("attack_range")), 46.0,
		"reset restores the sword's own reach")
	_expect_equal(float(player.get("attack_cooldown_time")), 0.50,
		"reset restores the sword's own cadence")
	var keen: Relic = load("res://resources/relics/sharp_moon.tres") as Relic
	var before: int = int(player.get("attack_damage"))
	arena.call("_feed", keen)
	_expect_true(int(player.get("attack_damage")) > before,
		"damage relic sharpens the primary")
	var twin: Relic = load("res://resources/relics/twin_arrow.tres") as Relic
	var budget_before: int = MissileProgression.damage_budget(
		int(arena.get("_arrow_damage")), 0, 0)
	arena.call("_feed", twin)
	var budget_after: int = MissileProgression.damage_budget(
		int(arena.get("_arrow_damage")), 0,
		maxi(int(arena.get("_arrow_count")) - 1, 0))
	_expect_true(budget_after > budget_before, "volley relic grows the budget")
	var volley_before: int = int(arena.call("_missile_volley"))
	arena.set("_missile_power", 3)
	_expect_true(int(arena.call("_missile_volley")) > volley_before,
		"cores widen the volley")
	_expect_true(MissileProgression.is_homing(3), "three cores wake homing")
	await _free_arena(arena)


## Price and presentation tier never enter weapon math: mutating the tier and
## re-running the whole reset path must change nothing but the paint.
func _test_price_tier_never_matters() -> void:
	# Warden rides tier 0, so 0→5 is a real mutation (Sage already sits at 5).
	var setup: Array = await _fresh_arena("warden")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	var hero: Hero = setup[2]
	var plain: Array = [
		int(arena.get("_arrow_damage")), float(arena.get("_arrow_cooldown")),
		int(player.get("attack_damage")), float(player.get("attack_cooldown_time")),
	]
	hero.set("vfx_tier", 5)
	player.call("apply_hero_visual", hero)
	arena.call("_recompute")
	arena.call("_settle_rates")
	_expect_equal(
		[
			int(arena.get("_arrow_damage")),
			float(arena.get("_arrow_cooldown")),
			int(player.get("attack_damage")),
			float(player.get("attack_cooldown_time")),
		],
		plain,
		"vfx tier 0→5 changes no weapon number")
	_expect_equal(int(player.call("hero_vfx_tier")), 5, "tier paint still applies")
	await _free_arena(arena)


## Result stops the body: rig flashes clear, the orbit sleeps, and freeing the arena
## takes every live projectile with it.
func _test_cleanup() -> void:
	var setup: Array = await _fresh_arena("eclipse")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	var ring: DurableTargetSpirit = _target(arena, player, Vector2(50, 0))
	_swing(arena, player, ring)
	_volley(arena)
	# Attack VFX clear themselves once the effect ends: rig flashes live ≤0.22s.
	for frame in 30:
		await get_tree().process_frame
	_expect_true(
		str((player.get_node("WeaponRig") as Node).get("_kind")).is_empty(),
		"rig flashes clear themselves after the effect")
	player.call("stop_for_result")
	_expect_true(
		str((player.get_node("WeaponRig") as Node).get("_kind")).is_empty(),
		"result clears rig flashes")
	_expect_true(
		not (player.get_node("ScytheOrbit") as Node).call("is_active"),
		"result sleeps the orbit")
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(not is_instance_valid(arena), "arena frees clean")
	_expect_equal(get_tree().get_nodes_in_group("friendly_projectiles").size(), 0,
		"no live projectile survives the arena")


## Independent deterministic comparison: one target at 37px — inside every primary's
## bite (rifle, fan and cannon need no melee range) — driven six seconds on both
## clocks. Ordinary single-target output stays broadly near Warden (0.7–1.4x).
func _test_same_target_comparison() -> void:
	var totals: Dictionary = {}
	var melee_share: Dictionary = {}
	for hero_id in HERO_IDS:
		var setup: Array = await _fresh_arena(hero_id)
		var arena: Node2D = setup[0]
		var player: Node2D = setup[1]
		var target: DurableTargetSpirit = _target(arena, player, Vector2(37, 0))
		# Physics runs 30 ticks a second: 180 ticks are six game-seconds, and the
		# volley clock advances the same 1/30 per tick or melee outruns ranged 2:1.
		for frame in 180:
			if player.call("can_attack"):
				var aim: Node2D = arena.call("_nearest_spirit") as Node2D
				if aim != null:
					arena.call("_swing_at", aim)
			arena.call("_fire_arrows", 1.0 / 30.0)
			await get_tree().physics_frame
		totals[hero_id] = target.damage_taken
		_expect_true(target.damage_taken > 0,
			hero_id + " primary deals nonzero damage at Lv1")
		await _free_arena(arena)
		# Split records: the same six seconds with one clock at a time. Durable
		# targets never die, so melee-only plus ranged-only equals the combined
		# run exactly, and each hero's primary/sidearm share reads off directly.
		var melee_only: int = await _split_run(hero_id, true)
		var ranged_only: int = await _split_run(hero_id, false)
		_expect_equal(melee_only + ranged_only, int(totals[hero_id]),
			hero_id + " split runs add up to the combined run")
		melee_share[hero_id] = float(melee_only) / float(maxi(melee_only + ranged_only, 1))
		var primary_share: float = float(melee_share[hero_id]) \
			if hero_id in ["warden", "dancer", "eclipse"] \
			else 1.0 - float(melee_share[hero_id])
		# Floor only, no ceiling: at 37px the rifle-bash and lantern-sweep
		# sidearms (reach 30/34) cannot connect, so those primaries honestly
		# carry 100% here. Viability of the short sidearms is proven at their
		# own range below instead.
		_expect_true(primary_share >= 0.55,
			"%s primary carries %.0f%% of close-range output" % [hero_id, primary_share * 100.0])
	var warden: float = float(maxi(int(totals["warden"]), 1))
	for hero_id in HERO_IDS:
		if hero_id == "warden":
			continue
		var ratio: float = float(totals[hero_id]) / warden
		_expect_true(ratio >= 0.7 and ratio <= 1.4,
			"%s single-target %.2fx of Warden" % [hero_id, ratio])
	print("single-target 6s totals: ", str(totals))
	print("single-target melee shares: ", str(melee_share))
	# Short sidearms still bite inside their own reach: a body at 25px eats a
	# bash and a sweep within two seconds.
	for hero_id in ["sage", "keeper"]:
		var setup: Array = await _fresh_arena(hero_id)
		var arena: Node2D = setup[0]
		var player: Node2D = setup[1]
		var close: DurableTargetSpirit = _target(arena, player, Vector2(25, 0))
		for frame in 60:
			if player.call("can_attack"):
				var aim: Node2D = arena.call("_nearest_spirit") as Node2D
				if aim != null:
					arena.call("_swing_at", aim)
			await get_tree().physics_frame
		_expect_true(close.damage_taken > 0,
			hero_id + " sidearm connects inside its reach")
		await _free_arena(arena)


## One clock for six seconds against a fresh durable body at close range.
func _split_run(hero_id: String, melee_only: bool) -> int:
	var setup: Array = await _fresh_arena(hero_id)
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	var target: DurableTargetSpirit = _target(arena, player, Vector2(37, 0))
	for frame in 180:
		if melee_only:
			if player.call("can_attack"):
				var aim: Node2D = arena.call("_nearest_spirit") as Node2D
				if aim != null:
					arena.call("_swing_at", aim)
		else:
			arena.call("_fire_arrows", 1.0 / 30.0)
		await get_tree().physics_frame
	var total: int = target.damage_taken
	await _free_arena(arena)
	return total


## Crowd/range tradeoff: four bodies clustered at ~110px for four seconds. Melee
## heroes fade with distance while the blast and the fan earn their keep.
func _test_grouped_comparison() -> void:
	var totals: Dictionary = {}
	for hero_id in HERO_IDS:
		var setup: Array = await _fresh_arena(hero_id)
		var arena: Node2D = setup[0]
		var player: Node2D = setup[1]
		var pack: Array[DurableTargetSpirit] = [
			_target(arena, player, Vector2(110, 0)),
			_target(arena, player, Vector2(118, 10)),
			_target(arena, player, Vector2(104, -8)),
			_target(arena, player, Vector2(126, 4)),
		]
		for frame in 120:
			if player.call("can_attack"):
				var aim: Node2D = arena.call("_nearest_spirit") as Node2D
				if aim != null:
					arena.call("_swing_at", aim)
			arena.call("_fire_arrows", 1.0 / 30.0)
			await get_tree().physics_frame
		var total: int = 0
		for double in pack:
			total += double.damage_taken
		totals[hero_id] = total
		_expect_true(total > 0, hero_id + " volley reaches the far pack")
		await _free_arena(arena)
	_expect_true(int(totals["knight"]) > int(totals["warden"]),
		"cannon blast out-values the sidearm wheel on a pack")
	_expect_true(int(totals["keeper"]) > int(totals["warden"]),
		"shotgun fan out-values the sidearm wheel on a pack")
	_expect_true(int(totals["sage"]) > int(totals["warden"]),
		"rifle line out-values the sidearm wheel on a pack")
	print("grouped 4s totals: ", str(totals))


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)
