extends SceneTree

## Player lazy attack nodes stay inside the late-game node budget.
##
## The physical attack split builds most of its body up front, but the nodes a
## hero never uses must never exist: the off-hand chain and stacked nub (only
## Dancer/Eclipse attacks), the Eclipse orbit (only Eclipse), the far crescent
## (only full-moon swings), and the moonfire aura (only awakened runs). This
## pins the single-hand Player subtree at 18 nodes at rest, mid-attack, and
## recovered; proves each lazy node appears exactly once on its first real
## production use with the eager tree's draw order; and proves hero switches
## plus repeated attack/recovery never accumulate nodes. The late-game suite
## keeps the strict 1200 cap; this file guards the allocation contract it
## rests on. The closing control rebuilds the old always-present shape and
## proves the ceiling check catches it.
##
## Direct-callable, no scene:
##     pnpm godot:isolated --timeout 150 --script res://tests/test_player_node_budget.gd

const PLAYER_SCENE: PackedScene = preload("res://scenes/actors/player.tscn")
const SINGLE_HAND_HEROES: Array[String] = ["warden", "keeper", "knight", "sage"]
## Eager 25 minus the 7 lazy nodes (off chain plus its two patch sprites, the
## nub, the far crescent, the orbit, the aura).
const SINGLE_HAND_NODES: int = 18
const FULL_LOAD_NODES: int = 25
const MELEE_PRIMARY: Array[String] = ["warden", "dancer", "eclipse"]

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_single_hand_ceiling()
	await _test_two_hand_intact()
	await _test_lazy_once_lifetimes()
	await _test_switch_no_accumulation()
	await _test_repeated_attack_recovery()
	await _test_vfx_suppression_inherited_at_creation()
	await _test_direction_restore_recreates_orbit()
	await _test_always_present_control()
	_finish()


## Single-hand heroes never allocate the off chain, nub, orbit, far crescent,
## or aura: 18 subtree nodes at rest, mid-attack, and recovered.
func _test_single_hand_ceiling() -> void:
	for hero_id in SINGLE_HAND_HEROES:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		_expect_absent(player, hero_id + " rest")
		_expect_equal(_subtree_nodes(player), SINGLE_HAND_NODES,
			hero_id + " rest subtree")
		_primary_attack(player, hero_id, Vector2.RIGHT)
		_expect_absent(player, hero_id + " mid-attack")
		_expect_equal(_subtree_nodes(player), SINGLE_HAND_NODES,
			hero_id + " mid-attack subtree")
		_step(player, 1.0 / 120.0)
		_expect_equal(_subtree_nodes(player), SINGLE_HAND_NODES,
			hero_id + " stepped subtree")
		_finish_attack(player)
		_expect_absent(player, hero_id + " recovered")
		_expect_equal(_subtree_nodes(player), SINGLE_HAND_NODES,
			hero_id + " recovered subtree")
		player.queue_free()
		await process_frame


## Both-hand heroes still get both hands: Dancer braces its off chain on front
## views, Eclipse mirrors its off chain front-on and stacks its nub in profile.
## Each lazy node carries paint and keeps the eager draw order.
func _test_two_hand_intact() -> void:
	var dancer: Player = _add_player()
	_apply_hero(dancer, "dancer")
	_primary_attack(dancer, "dancer", Vector2.DOWN)
	var brace: ArmRig = dancer.get_node_or_null("ArmOff") as ArmRig
	_expect_true(brace != null and brace.visible, "dancer brace arm shows")
	_expect_true(brace != null and brace.upper_texture() != null
		and brace.fore_texture() != null, "dancer brace arm wears paint")
	_expect_true(brace != null and brace.get_index()
		> (dancer.get_node("ArmMain") as Node).get_index(),
		"dancer brace arm layers after the main chain")
	_finish_attack(dancer)
	_primary_attack(dancer, "dancer", Vector2.RIGHT)
	var profile_off: ArmRig = dancer.get_node_or_null("ArmOff") as ArmRig
	_expect_true(profile_off == null or not profile_off.visible,
		"dancer profile keeps no spare arm")
	_finish_attack(dancer)
	dancer.queue_free()
	await process_frame
	var eclipse: Player = _add_player()
	_apply_hero(eclipse, "eclipse")
	_primary_attack(eclipse, "eclipse", Vector2.DOWN)
	var mirror: ArmRig = eclipse.get_node_or_null("ArmOff") as ArmRig
	_expect_true(mirror != null and mirror.visible,
		"eclipse mirror arm shows")
	_expect_true(mirror != null and mirror.upper_texture() != null,
		"eclipse mirror arm wears paint")
	_finish_attack(eclipse)
	_primary_attack(eclipse, "eclipse", Vector2.RIGHT)
	var nub: Sprite2D = eclipse.get_node_or_null("AttackNub") as Sprite2D
	_expect_true(nub != null and nub.visible, "eclipse off hand stacks")
	_expect_true(nub != null and nub.texture != null,
		"eclipse nub wears paint")
	_expect_true(nub != null and nub.get_index()
		< (eclipse.get_node("ArmMain") as Node).get_index(),
		"eclipse nub layers before the main chain")
	_finish_attack(eclipse)
	eclipse.queue_free()
	await process_frame


## Each remaining lazy node appears exactly once on its first real production
## use and is reused after: the far crescent on a full-moon swing, the aura on
## awakening, the orbit when Eclipse is equipped. Draw order matches eager.
func _test_lazy_once_lifetimes() -> void:
	var player: Player = _add_player()
	_apply_hero(player, "warden")
	player.set("_attack_cooldown", 0.0)
	player.attack(Vector2.RIGHT, true)
	var back: Sprite2D = player.get_node_or_null("FullMoonBack") as Sprite2D
	_expect_true(back != null and back.visible,
		"full-moon swing builds the far crescent")
	_expect_true(back != null and back.get_index()
		< (player.get_node("WeaponRig") as Node).get_index(),
		"far crescent layers before the weapon rig")
	var back_id: int = back.get_instance_id() if back != null else 0
	_finish_attack(player)
	player.set("_attack_cooldown", 0.0)
	player.attack(Vector2.LEFT, true)
	var back_again: Sprite2D = player.get_node_or_null(
		"FullMoonBack") as Sprite2D
	_expect_true(back_again != null
		and back_again.get_instance_id() == back_id,
		"second full moon reuses the far crescent")
	_finish_attack(player)
	player.call("set_moonfire", true, false)
	var aura: Node2D = player.get_node_or_null("MoonfireAura") as Node2D
	_expect_true(aura != null and bool(aura.get("_active")),
		"awakening builds the aura")
	_expect_true(aura != null and aura.get_index()
		< (player.get_node("Slash") as Node).get_index(),
		"aura layers before the slash cue")
	var aura_id: int = aura.get_instance_id() if aura != null else 0
	player.call("set_moonfire", false, false)
	player.call("set_moonfire", true, true)
	var aura_again: Node2D = player.get_node_or_null(
		"MoonfireAura") as Node2D
	_expect_true(aura_again != null
		and aura_again.get_instance_id() == aura_id,
		"relight reuses the aura")
	_expect_true(aura_again != null and bool(aura_again.get("_locked")),
		"relight keeps the lock state")
	_apply_hero(player, "eclipse")
	var scythe: Node = player.get_node_or_null("ScytheOrbit")
	_expect_true(scythe != null and bool(scythe.call("is_active")),
		"eclipse equips the orbit")
	var scythe_id: int = scythe.get_instance_id() if scythe != null else 0
	_apply_hero(player, "knight")
	_apply_hero(player, "eclipse")
	var scythe_again: Node = player.get_node_or_null("ScytheOrbit")
	_expect_true(scythe_again != null
		and scythe_again.get_instance_id() == scythe_id,
		"re-equip reuses the orbit")
	player.queue_free()
	await process_frame


## Switching heroes on one live Player with attacks between never duplicates
## a lazy node: the subtree grows only by first uses and then holds flat.
func _test_switch_no_accumulation() -> void:
	var player: Player = _add_player()
	_apply_hero(player, "knight")
	_primary_attack(player, "knight", Vector2.RIGHT)
	_finish_attack(player)
	_expect_equal(_subtree_nodes(player), SINGLE_HAND_NODES,
		"knight starts at the ceiling")
	_apply_hero(player, "eclipse")
	_primary_attack(player, "eclipse", Vector2.DOWN)
	_finish_attack(player)
	var front_count: int = _subtree_nodes(player)
	_expect_equal(front_count, SINGLE_HAND_NODES + 4,
		"eclipse front adds orbit plus off chain")
	_primary_attack(player, "eclipse", Vector2.RIGHT)
	_finish_attack(player)
	_expect_equal(_subtree_nodes(player), front_count + 1,
		"eclipse profile adds the nub once")
	_apply_hero(player, "dancer")
	_primary_attack(player, "dancer", Vector2.DOWN)
	_finish_attack(player)
	_expect_equal(_subtree_nodes(player), front_count + 1,
		"dancer front reuses the off chain")
	_apply_hero(player, "knight")
	_primary_attack(player, "knight", Vector2.LEFT)
	_finish_attack(player)
	_apply_hero(player, "eclipse")
	_primary_attack(player, "eclipse", Vector2.UP)
	_finish_attack(player)
	_expect_equal(_subtree_nodes(player), front_count + 1,
		"repeated switches hold the subtree flat")
	player.queue_free()
	await process_frame


## Repeated attack/recovery on both facings never grows the subtree once every
## lazy node has joined.
func _test_repeated_attack_recovery() -> void:
	var player: Player = _add_player()
	_apply_hero(player, "eclipse")
	_primary_attack(player, "eclipse", Vector2.DOWN)
	_finish_attack(player)
	_primary_attack(player, "eclipse", Vector2.RIGHT)
	_finish_attack(player)
	var loaded: int = _subtree_nodes(player)
	_expect_equal(loaded, SINGLE_HAND_NODES + 5,
		"front plus profile loads orbit, off chain, and nub")
	for cycle in 6:
		_primary_attack(player, "eclipse",
			Vector2.DOWN if cycle % 2 == 0 else Vector2.RIGHT)
		_step(player, 1.0 / 120.0)
		_finish_attack(player)
		_expect_equal(_subtree_nodes(player), loaded,
			"attack cycle %d holds flat" % cycle)
	player.queue_free()
	await process_frame


## Draw suppression set before Eclipse is equipped survives the lazy orbit
## creation, and repeated suppress/restore reaches the same single orbit.
func _test_vfx_suppression_inherited_at_creation() -> void:
	var player: Player = _add_player()
	player.set_vfx_suppressed(true)
	_apply_hero(player, "eclipse")
	var scythe: ScytheOrbit = player.get_node_or_null(
		"ScytheOrbit") as ScytheOrbit
	_expect_true(scythe != null, "suppressed eclipse still equips the orbit")
	_expect_true(scythe != null and bool(scythe.get("_vfx_suppressed")),
		"orbit inherits draw suppression at creation")
	if scythe == null:
		player.queue_free()
		await process_frame
		return
	var loaded: int = _subtree_nodes(player)
	for cycle in 3:
		player.set_vfx_suppressed(false)
		_expect_true(not bool(scythe.get("_vfx_suppressed")),
			"restore clears orbit suppression (%d)" % cycle)
		player.set_vfx_suppressed(true)
		_expect_true(bool(scythe.get("_vfx_suppressed")),
			"re-suppress reaches the orbit (%d)" % cycle)
		var again: ScytheOrbit = player.get_node_or_null(
			"ScytheOrbit") as ScytheOrbit
		_expect_true(again != null
			and again.get_instance_id() == scythe.get_instance_id(),
			"one orbit across suppress cycles (%d)" % cycle)
		_expect_equal(_subtree_nodes(player), loaded,
			"suppress/restore duplicates no node (%d)" % cycle)
	player.set_vfx_suppressed(false)
	player.queue_free()
	await process_frame


## Direction suppression skips the orbit allocation, and restoring the
## direction effects recreates one active orbit without duplicating nodes.
func _test_direction_restore_recreates_orbit() -> void:
	var player: Player = _add_player()
	player.debug_set_direction_capture_vfx_suppressed(true)
	_apply_hero(player, "eclipse")
	_expect_true(player.get_node_or_null("ScytheOrbit") == null,
		"suppressed eclipse skips the orbit")
	_expect_equal(_subtree_nodes(player), SINGLE_HAND_NODES,
		"suppressed eclipse holds the ceiling")
	player.debug_set_direction_capture_vfx_suppressed(false)
	var scythe: ScytheOrbit = player.get_node_or_null(
		"ScytheOrbit") as ScytheOrbit
	_expect_true(scythe != null and scythe.is_active(),
		"restore recreates an active orbit")
	if scythe == null:
		player.queue_free()
		await process_frame
		return
	var orbit_id: int = scythe.get_instance_id()
	var loaded: int = _subtree_nodes(player)
	for cycle in 3:
		player.debug_set_direction_capture_vfx_suppressed(true)
		_expect_true(not scythe.is_active(),
			"re-suppress sleeps the orbit (%d)" % cycle)
		player.debug_set_direction_capture_vfx_suppressed(false)
		var again: ScytheOrbit = player.get_node_or_null(
			"ScytheOrbit") as ScytheOrbit
		_expect_true(again != null and again.is_active(),
			"re-restore reactivates the orbit (%d)" % cycle)
		_expect_true(again != null
			and again.get_instance_id() == orbit_id,
			"one orbit across direction cycles (%d)" % cycle)
		_expect_equal(_subtree_nodes(player), loaded,
			"direction cycles duplicate no node (%d)" % cycle)
	player.queue_free()
	await process_frame


## Negative control: rebuild the old always-present shape through production
## calls and prove the single-hand ceiling catches it.
func _test_always_present_control() -> void:
	var player: Player = _add_player()
	_apply_hero(player, "eclipse")
	_primary_attack(player, "eclipse", Vector2.DOWN)
	_finish_attack(player)
	_primary_attack(player, "eclipse", Vector2.RIGHT)
	_finish_attack(player)
	player.set("_attack_cooldown", 0.0)
	player.attack(Vector2.DOWN, true)
	_finish_attack(player)
	player.call("set_moonfire", true, false)
	var loaded: int = _subtree_nodes(player)
	_expect_equal(loaded, FULL_LOAD_NODES,
		"old shape carries all 25 nodes")
	_expect_true(loaded > SINGLE_HAND_NODES,
		"old shape breaks the single-hand ceiling")
	_expect_true(player.has_node("ArmOff")
		and player.has_node("AttackNub")
		and player.has_node("ScytheOrbit")
		and player.has_node("FullMoonBack")
		and player.has_node("MoonfireAura"),
		"old shape holds every lazy node")
	player.queue_free()
	await process_frame


## Every lazy node absent: the single-hand rest shape.
func _expect_absent(player: Player, label: String) -> void:
	for node_name in ["ArmOff", "AttackNub", "ScytheOrbit", "FullMoonBack",
			"MoonfireAura"]:
		_expect_true(player.get_node_or_null(node_name) == null,
			label + " " + node_name + " absent")


func _subtree_nodes(player: Player) -> int:
	var total: int = 0
	var stack: Array[Node] = [player]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		total += 1
		for child in node.get_children():
			stack.append(child)
	return total


func _primary_attack(player: Player, hero_id: String, aim: Vector2) -> void:
	if hero_id in MELEE_PRIMARY:
		player.set("_attack_cooldown", 0.0)
		player.attack(aim)
	else:
		player.play_moonlight_cast(aim, 1)


func _step(player: Player, dt: float) -> void:
	(player.get_node("WeaponRig") as WeaponRig).call("_process", dt)
	var scythe: ScytheOrbit = player.get_node_or_null(
		"ScytheOrbit") as ScytheOrbit
	if scythe != null:
		scythe.call("_process", dt)
	(player.get_node("MoonlightCast") as MoonlightCast).call("_process", dt)
	player.call("_update_attack_pose", dt)


func _finish_attack(player: Player) -> void:
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	if rig.attack_live():
		var left: float = rig.attack_span() - float(rig.get("_attack_age"))
		_step(player, maxf(left, 0.0) + 1.0 / 120.0)
	_step(player, 1.0 / 120.0)


func _apply_hero(player: Player, hero_id: String) -> void:
	var hero: Hero = load(
		"res://resources/heroes/%s.tres" % hero_id) as Hero
	_expect_true(player.apply_hero_visual(hero), hero_id + " visual applies")
	var melee: Dictionary = HeroWeapons.melee_spec(
		HeroWeapons.profile_of(hero_id))
	player.attack_cooldown_time = float(melee["cooldown"])
	player.position = Vector2(400, 220)


## Player entering the tree with its camera on the physics callback the
## project's interpolation requires. Process-disabled so every attack below is
## stepped by hand.
func _add_player() -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	(player.get_node("Cam") as Camera2D).process_callback = \
		Camera2D.CAMERA2D_PROCESS_PHYSICS
	root.add_child(player)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	return player


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _finish() -> void:
	if _failed > 0:
		printerr("node-budget test failed — ", _failed, "/", _checked,
			" case(s)")
		quit(1)
		return
	print("node-budget test passed — ", _checked, " case(s)")
	quit(0)
