extends Node

## Photograph the six painted held weapons on real bodies and up close.
##
## Two production blocks, no posing: 24 live Players (six heroes by four aims)
## drive the real attack path — melee swings, lantern/rifle/cannon casts —
## while 24 bare rigs under night-tint carriers show the same sheets at 4x.
## Three stages per board: normal (settled aim, no flash), fire (a real attack
## frozen mid-flash under pause), clear (resumed, cleared, result-stopped).
## Every stage asserts aim, seating, facing, flash kind, and the no-stuck rule.
##
## Render on a real display (captures need `frame_post_draw`, which never fires
## headless). Validate anywhere headless: every observation runs, only PNG writes
## are skipped.
##
##     pnpm godot:isolated --windowed res://tools/shot_painted_weapons.tscn -- tag=weapons
##     pnpm godot:isolated --timeout 300 res://tools/shot_painted_weapons.tscn -- tag=weapons validate=1
##
## Arguments (`-- key=value`): tag validate.
## Output lands in `builds/shots/painted-weapons/`, so it is not committed.
## Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const PLAYER_SCENE: PackedScene = preload("res://scenes/actors/player.tscn")
const OUT: String = "res://../../builds/shots/painted-weapons"
const REQUEST_PATH: String = "user://test_hero.request"

const HEROES: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage",
]
const SIDES: Dictionary = {
	"right": Vector2(1, 0), "left": Vector2(-1, 0),
	"up": Vector2(0, -1), "down": Vector2(0, 1),
}
const SIDE_FACING: Dictionary = {
	"right": Player.Facing.RIGHT, "left": Player.Facing.LEFT,
	"up": Player.Facing.UP, "down": Player.Facing.DOWN,
}
const SIDE_ORDER: Array[String] = ["right", "left", "up", "down"]
## Primary flash kind per hero on the real attack path.
const FIRE_KIND: Dictionary = {
	"warden": WeaponRig.CUT, "dancer": WeaponRig.TWIN_CUT,
	"keeper": WeaponRig.MUZZLE_SCATTER, "knight": WeaponRig.MUZZLE_CANNON,
	"eclipse": WeaponRig.RING_PULSE, "sage": WeaponRig.MUZZLE_RIFLE,
}
const MELEE_PRIMARY: Array[String] = ["warden", "dancer", "eclipse"]
## Board geometry: camera block left, 4x block right, six rows by four aims.
const CAMERA_ORIGIN: Vector2 = Vector2(90, 70)
const CLOSE_ORIGIN: Vector2 = Vector2(660, 70)
const CELL: Vector2 = Vector2(130, 105)
const CLOSE_SCALE: float = 4.0
const BOARD_SIZE: Vector2i = Vector2i(1200, 700)
## Night tint the close carriers simulate, matching `player.tscn`.
const NIGHT_TINT: Color = Color(0.315, 0.35, 0.57, 1.0)

var _tag: String = "shot"
var _validate_only: bool = false
var _failed: int = 0
var _checked: int = 0
var _players: Dictionary = {}
var _close_rigs: Dictionary = {}


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = BOARD_SIZE
	get_window().content_scale_size = BOARD_SIZE
	_parse_args(OS.get_cmdline_user_args())
	_run.call_deferred()


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("shot_painted_weapons aborted: user:// path is not isolated — ", user_root)
	return safe


func _parse_args(args: PackedStringArray) -> void:
	for arg in args:
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"tag":
				_tag = parts[1] if not parts[1].is_empty() else "shot"
			"validate":
				_validate_only = parts[1] == "1" or parts[1] == "true"


func _run() -> void:
	var out: String = ProjectSettings.globalize_path(OUT)
	if not _validate_only:
		DirAccess.make_dir_recursive_absolute(out)
	_build_board()
	await get_tree().process_frame
	await get_tree().process_frame
	# No camera ever took over, so this only states the contract out loud:
	# the board renders from the origin at 1:1.
	get_viewport().canvas_transform = Transform2D.IDENTITY
	_expect_asset_bounds()
	await _stage_normal(out)
	await _stage_fire(out)
	await _stage_clear(out)
	get_tree().paused = false
	if _failed > 0:
		printerr("shot_painted_weapons %s failed — %d/%d check(s)" % [_tag, _failed, _checked])
		get_tree().quit(1)
		return
	print("shot_painted_weapons %s ok — %d check(s)%s" % [
		_tag, _checked, " (validate only, no PNGs)" if _validate_only else ""])
	get_tree().quit(0)


## One live Player per hero-aim at camera scale, one bare rig per hero-aim at
## 4x under a night-tint carrier. Player cameras are configured before they
## enter the tree — physics callback like the project requires, then off —
## so none ever becomes current, writes a canvas transform, or warns. With no
## current camera the viewport shows the board from the origin.
func _build_board() -> void:
	for row in HEROES.size():
		var hero_id: String = HEROES[row]
		var hero: Hero = load("res://resources/heroes/%s.tres" % hero_id) as Hero
		for column in SIDE_ORDER.size():
			var side: String = SIDE_ORDER[column]
			var key: String = "%s_%s" % [hero_id, side]
			var player: Player = PLAYER_SCENE.instantiate() as Player
			player.position = CAMERA_ORIGIN + Vector2(column, row) * CELL
			var cam: Camera2D = player.get_node("Cam") as Camera2D
			cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
			cam.enabled = false
			add_child(player)
			# The board is a bigger room than the arena: without this, the
			# production bounds clamp (96..712, 150..322) stacks rows 3-5 at
			# y=322 and shoves row 0 to y=150. Physics still simulates.
			player.set_bounds(
				Rect2(Vector2.ZERO, Vector2(BOARD_SIZE)).grow(200.0))
			_expect_true(player.apply_hero_visual(hero),
				"%s body wears its hero" % key)
			_players[key] = player
			var carrier := Node2D.new()
			carrier.modulate = NIGHT_TINT
			carrier.position = CLOSE_ORIGIN + Vector2(column, row) * CELL
			carrier.scale = Vector2(CLOSE_SCALE, CLOSE_SCALE)
			add_child(carrier)
			var rig := WeaponRig.new()
			carrier.add_child(rig)
			rig.configure(hero.attack_profile,
				hero.projectile_primary, hero.projectile_secondary)
			_close_rigs[key] = rig
	_expect_equal(_players.size(), 24, "camera block holds 24 bodies")
	_expect_equal(_close_rigs.size(), 24, "close block holds 24 rigs")


## Bounded asset, node, and draw costs of the rig layer itself.
func _expect_asset_bounds() -> void:
	var total_bytes: int = 0
	for hero_id in HEROES:
		var profile: Hero.AttackProfile = HeroWeapons.profile_of(hero_id)
		var sheet: Texture2D = WeaponRig.painted_sheet(profile)
		_expect_true(sheet != null, "%s close sheet loads" % hero_id)
		_expect_true(sheet.get_width() <= 96 and sheet.get_height() <= 40,
			"%s close sheet bounded" % hero_id)
		var file: FileAccess = FileAccess.open(
			"res://assets/custom/items/weapons/%s.png" % hero_id, FileAccess.READ)
		if file != null:
			total_bytes += int(file.get_length())
	_expect_true(total_bytes <= 32768, "six sheets total bounded (%d)" % total_bytes)
	for key in _players:
		var rig: Node = (_players[key] as Node).get_node("WeaponRig") as Node
		_expect_equal(rig.get_child_count(), 0, "%s rig stays one node" % key)
		_expect_equal((rig as Node2D).z_index, 2, "%s rig depth above the body" % key)
		_expect_equal((rig as CanvasItem).texture_filter,
			CanvasItem.TEXTURE_FILTER_LINEAR,
			"%s held sheet resolves through Linear" % key)
	for key in _close_rigs:
		_expect_equal((_close_rigs[key] as Node).get_child_count(), 0,
			"%s close rig stays one node" % key)
		_expect_equal((_close_rigs[key] as CanvasItem).texture_filter,
			CanvasItem.TEXTURE_FILTER_LINEAR,
			"%s close sheet resolves through Linear" % key)


## Drive one real attack per body, then settle: slash, cast, and flash all
## expire, the aim stays, and the board shows quiet held weapons.
func _attack_once(hero_id: String, side: String, player: Player) -> void:
	player.call("face_toward", SIDES[side])
	player.set("_attack_cooldown", 0.0)
	if hero_id in MELEE_PRIMARY:
		player.call("attack", SIDES[side])
	else:
		player.call("play_moonlight_cast", SIDES[side], 1)


func _stage_normal(out: String) -> void:
	for hero_id in HEROES:
		for side in SIDE_ORDER:
			var key: String = "%s_%s" % [hero_id, side]
			_attack_once(hero_id, side, _players[key])
			var rig: WeaponRig = _close_rigs[key] as WeaponRig
			rig.flash(SIDES[side], FIRE_KIND[hero_id])
	# Eclipse pulse (0.3s) is the longest tail; 0.6s settles every stage cue.
	await get_tree().create_timer(0.6, true).timeout
	for hero_id in HEROES:
		for side in SIDE_ORDER:
			var key: String = "%s_%s" % [hero_id, side]
			_expect_pose(key, hero_id, side)
			var rig: WeaponRig = _close_rigs[key] as WeaponRig
			_expect_true(str(rig.get("_kind")).is_empty(),
				"%s close rig settled quiet" % key)
			_expect_true((rig.aim() - (SIDES[side] as Vector2)).length() < 0.001,
				"%s close rig keeps its aim" % key)
	_expect_framing("normal", true)
	await _capture(out, "normal")


## One hero-build aim pose: body faces its side, the held weapon points there
## too, the grip clears the face on vertical aims, and nothing burns.
func _expect_pose(key: String, hero_id: String, side: String) -> void:
	var player: Player = _players[key] as Player
	var aim: Vector2 = SIDES[side]
	_expect_equal(int(player.get("facing")), int(SIDE_FACING[side]),
		"%s body faces %s" % [key, side])
	var rig: Node = player.get_node("WeaponRig") as Node
	_expect_true((((rig as WeaponRig).aim() - aim).length()) < 0.001,
		"%s held weapon points %s" % [key, side])
	_expect_equal((rig as Node2D).position, player.rest_rig_seat(aim),
		"%s grip sits in the painted wrist" % key)
	_expect_true(str(rig.get("_kind")).is_empty(), "%s rig burns nothing" % key)
	_expect_true(not (player.get_node("Slash") as Sprite2D).visible,
		"%s blade put away" % key)


## Real attacks again, frozen mid-flash: every rig burns its primary kind with
## a live body cue beside it.
func _stage_fire(out: String) -> void:
	get_tree().paused = false
	for hero_id in HEROES:
		for side in SIDE_ORDER:
			var key: String = "%s_%s" % [hero_id, side]
			_attack_once(hero_id, side, _players[key])
			var rig: WeaponRig = _close_rigs[key] as WeaponRig
			rig.flash(SIDES[side], FIRE_KIND[hero_id])
	await get_tree().create_timer(0.06, true).timeout
	get_tree().paused = true
	await get_tree().process_frame
	for hero_id in HEROES:
		for side in SIDE_ORDER:
			var key: String = "%s_%s" % [hero_id, side]
			var player: Player = _players[key] as Player
			var rig: Node = player.get_node("WeaponRig") as Node
			_expect_equal(str(rig.get("_kind")), String(FIRE_KIND[hero_id]),
				"%s rig burns its primary" % key)
			_expect_equal(bool(rig.get("_kind_sidearm")), false,
				"%s fire is no sidearm cue" % key)
			_expect_true(_live_body_cue(player, hero_id),
				"%s live body cue shows" % key)
			var close: WeaponRig = _close_rigs[key] as WeaponRig
			_expect_equal(str(close.get("_kind")), String(FIRE_KIND[hero_id]),
				"%s close rig burns its primary" % key)
	_expect_framing("fire", false)
	await _capture(out, "fire")


## Melee primaries swing the slash, Eclipse pulses its orbit, ranged primaries
## light the cast cue — all from the production attack calls above.
func _live_body_cue(player: Player, hero_id: String) -> bool:
	if (player.get_node("Slash") as Sprite2D).visible:
		return true
	if hero_id == "eclipse":
		var scythe: Node = player.get_node("ScytheOrbit") as Node
		if scythe != null and float(scythe.get("_pulse_age")) < 0.5:
			return true
	if hero_id not in MELEE_PRIMARY:
		var cast: Node = player.get_node("MoonlightCast") as Node
		if cast != null and float(cast.get("_left")) > 0.0:
			return true
	return false


## Resume, clear, and result-stop: no flash may stick on any rig.
func _stage_clear(out: String) -> void:
	get_tree().paused = false
	await get_tree().create_timer(0.5, true).timeout
	for hero_id in HEROES:
		for side in SIDE_ORDER:
			var key: String = "%s_%s" % [hero_id, side]
			var player: Player = _players[key] as Player
			var rig: Node = player.get_node("WeaponRig") as Node
			_expect_true(str(rig.get("_kind")).is_empty(),
				"%s flash dies on its own" % key)
			(player.get_node("WeaponRig") as WeaponRig).clear()
			(_close_rigs[key] as WeaponRig).clear()
			player.call("stop_for_result")
			_expect_true(str(rig.get("_kind")).is_empty(),
				"%s flash stays dead past result" % key)
			_expect_true(str((_close_rigs[key] as WeaponRig).get("_kind")).is_empty(),
				"%s close flash stays dead past clear" % key)
	_expect_framing("clear", false)
	await _capture(out, "clear")


## Rendered-bounds framing for one board: no camera owns the viewport, the
## transform is identity, and every body, held weapon, and close rig is
## actually drawn on screen — sprite rects and sheet quads, not node counts.
## Pairwise separation runs once: cells never overlap.
func _expect_framing(stage: String, pairwise: bool) -> void:
	var viewport: Viewport = get_viewport()
	_expect_true(viewport.get_camera_2d() == null,
		"%s board owns no camera" % stage)
	_expect_equal(viewport.canvas_transform, Transform2D.IDENTITY,
		"%s board transform predictable" % stage)
	var visible: Rect2 = viewport.canvas_transform.affine_inverse() \
		* viewport.get_visible_rect()
	if pairwise:
		print("%s board visible rect %s" % [stage, str(visible)])
	for hero_id in HEROES:
		for side in SIDE_ORDER:
			var key: String = "%s_%s" % [hero_id, side]
			var player: Player = _players[key] as Player
			var aim: Vector2 = SIDES[side]
			_expect_true(visible.has_point(player.position),
				"%s %s body stands on screen" % [stage, key])
			var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
			var bounds: Rect2 = _sprite_bounds(sprite)
			_expect_true(bounds.has_area(), "%s %s body rect renders" % [stage, key])
			_expect_true(visible.intersects(bounds),
				"%s %s body renders on screen" % [stage, key])
			_expect_equal(int(player.get("facing")), int(SIDE_FACING[side]),
				"%s %s body faces %s" % [stage, key, side])
			var profile: Hero.AttackProfile = HeroWeapons.profile_of(hero_id)
			var held: WeaponRig = player.get_node("WeaponRig") as WeaponRig
			_expect_true((held.aim() - aim).length() < 0.001,
				"%s %s held weapon points %s" % [stage, key, side])
			_expect_quad_inside(stage, key, "held",
				_rig_quad(profile, held.aim(), held), visible)
			var close: WeaponRig = _close_rigs[key] as WeaponRig
			_expect_true(visible.has_point((close.get_parent() as Node2D).position),
				"%s %s close rig stands on screen" % [stage, key])
			_expect_true((close.aim() - aim).length() < 0.001,
				"%s %s close rig points %s" % [stage, key, side])
			_expect_quad_inside(stage, key, "close",
				_rig_quad(profile, close.aim(), close), visible)
	if pairwise:
		var order: Array = _players.keys()
		var bodies: Array[Vector2] = []
		var carriers: Array[Vector2] = []
		for key in order:
			bodies.append((_players[key] as Node2D).position)
			carriers.append(((_close_rigs[key] as Node).get_parent() as Node2D).position)
		_expect_separated(stage, "body", order, bodies)
		_expect_separated(stage, "close", order, carriers)


## The body's current frame in global space: centered frame rect plus the
## sprite offset, through the live node transform. Empty when no frame is set,
## which the area assert names out loud.
func _sprite_bounds(sprite: AnimatedSprite2D) -> Rect2:
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null or not frames.has_animation(sprite.animation):
		return Rect2()
	if sprite.frame < 0 or sprite.frame >= frames.get_frame_count(sprite.animation):
		return Rect2()
	var texture: Texture2D = frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return Rect2()
	var size := Vector2(texture.get_size())
	return sprite.get_global_transform() * Rect2(-size * 0.5 + sprite.offset, size)


## The drawn sheet corners of one rig in global space: the same
## pivot/mirror/aim math `_draw_held` uses, through the live node transform.
func _rig_quad(
	profile: Hero.AttackProfile, aim: Vector2, rig: WeaponRig
) -> PackedVector2Array:
	var size: Vector2 = Vector2(WeaponRig.painted_sheet(profile).get_size())
	var pivot: Vector2 = WeaponRig.texture_pivot(profile)
	var anchor: Vector2 = WeaponRig.painted_anchor(profile, aim)
	var angle: float = aim.angle()
	var quad := PackedVector2Array()
	for corner in [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		var rel: Vector2 = (corner - pivot) * WeaponRig.DRAW_SCALE
		if aim.x < 0.0:
			rel.y = -rel.y
		quad.append(rig.to_global(anchor + rel.rotated(angle)))
	return quad


func _expect_quad_inside(
	stage: String, key: String, label: String,
	quad: PackedVector2Array, visible: Rect2
) -> void:
	for corner in quad.size():
		_expect_true(visible.has_point(quad[corner]),
			"%s %s %s sheet corner %d on screen" % [stage, key, label, corner])


func _expect_separated(
	stage: String, label: String, keys: Array, points: Array[Vector2]
) -> void:
	for first in points.size():
		for second in range(first + 1, points.size()):
			_expect_true(points[first].distance_to(points[second]) > 50.0,
				"%s %s cells never overlap (%s vs %s)" % [
					stage, label, str(keys[first]), str(keys[second])])


func _capture(out: String, stage: String) -> void:
	if _validate_only:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		"%s/%s_%s.png" % [out, _tag, stage])
	print("saved %s %s board" % [_tag, stage])


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)
