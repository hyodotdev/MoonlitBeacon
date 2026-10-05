extends Node

## Motion board for the six heroes' physical attacks: every cut and kick loops.
##
## Three production blocks, no posing. The normal block holds 24 live Players
## (six heroes by four aims) at 1:1; the close block holds 24 live Players
## (six heroes by four facings) under 2x linear-filtered carriers; the movers
## lane holds six walkers repeating moving attacks. Each cell drives the real
## attack path — melee swings, orbit sweeps, lantern/rifle/cannon discharges
## — on a staggered loop, so a timed windowed run records complete
## attack/recovery cycles at both scales plus stepping feet. Both modes use
## production attack methods; no-VFX mode only darkens the draw layer through
## `Player.set_vfx_suppressed`, so the physical action stays identical.
##
## Headless validation samples 6 heroes x 8 aims x both modes (96 samples)
## with machine-readable timing/geometry observations written to
## `builds/attack-motion/<tag>.json`, and asserts every acceptance minimum.
## Windowed mode runs the timed loop for `--write-movie`, samples live poses
## while it runs, and records the run config beside it. Nothing here writes
## PNGs or touches the store pipeline.
##
##     pnpm godot:isolated --timeout 300 res://tools/shot_hero_attack_motion.tscn -- tag=motion validate=1
##     pnpm godot:isolated --windowed res://tools/shot_hero_attack_motion.tscn -- tag=motion vfx=1 duration=12
##
## Arguments (`-- key=value`): tag validate vfx duration.
## Output lands in `builds/attack-motion/`, so it is not committed.
## Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const PLAYER_SCENE: PackedScene = preload("res://scenes/actors/player.tscn")
const OUT: String = "res://../../builds/attack-motion"

const HEROES: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage",
]
const SIDES: Dictionary = {
	"right": Vector2(1, 0), "left": Vector2(-1, 0),
	"up": Vector2(0, -1), "down": Vector2(0, 1),
}
const SIDE_ORDER: Array[String] = ["right", "left", "up", "down"]
const DIAGONAL: float = 0.70710678
const DIAGONALS: Array[Vector2] = [
	Vector2(DIAGONAL, DIAGONAL), Vector2(-DIAGONAL, DIAGONAL),
	Vector2(DIAGONAL, -DIAGONAL), Vector2(-DIAGONAL, -DIAGONAL),
]
const MELEE_PRIMARY: Array[String] = ["warden", "dancer", "eclipse"]
const SWING_MINIMUM: Dictionary = {
	"warden": 90.0, "dancer": 60.0, "eclipse": 120.0,
}
const SHOT_SLIDE: Dictionary = {"keeper": 4.0, "knight": 7.0, "sage": 2.5}
## Board geometry: normal block left (24 cells, six heroes by four aims),
## close block right (24 cells, six heroes by four facings at 2x), movers
## lane bottom (six walkers). Pitches clear full bodies, weapon tips,
## wrists, and the Eclipse orbit at every stage; the framing check proves
## it. Board matches the locked 1616x720 physical movie output.
const NORMAL_ORIGIN: Vector2 = Vector2(60, 50)
const NORMAL_CELL: Vector2 = Vector2(120, 100)
const CLOSE_ORIGIN: Vector2 = Vector2(560, 140)
const CLOSE_CELL: Vector2 = Vector2(160, 120)
const CLOSE_SCALE: float = 2.0
const MOVER_ORIGIN: Vector2 = Vector2(100, 650)
const MOVER_DX: float = 240.0
## Movers ping-pong inside disjoint lanes: each center holds its hero, the
## half-width clears a full pass of travel, and per-lane bounds clamp the
## body even if the bounce logic misses. Lanes stay in view with weapon
## tips, wrists, and the Eclipse orbit; separation is checked live.
const MOVER_LANE_HALF: float = 40.0
const MOVER_EDGE_SLOP: float = 3.0
const MOVER_MIN_TRAVEL: float = 40.0
const MOVER_MIN_SEPARATION: float = 80.0
const MOVER_MAX_STEP: float = 40.0
const BOARD_SIZE: Vector2i = Vector2i(1616, 720)
## Attack loop: a full cycle settles every span (max 0.28s) before the next.
const CYCLE_SECONDS: float = 0.7
const ROW_GAP_SECONDS: float = 0.08

var _tag: String = "shot"
var _validate_only: bool = false
var _vfx: bool = true
var _duration: float = 12.0
var _failed: int = 0
var _checked: int = 0
var _players: Dictionary = {}
var _close_players: Dictionary = {}
var _movers: Dictionary = {}
var _mover_dirs: Dictionary = {}
var _mover_centers: Dictionary = {}
var _mover_min: Dictionary = {}
var _mover_max: Dictionary = {}
var _mover_flips: Dictionary = {}
var _mover_last: Dictionary = {}
var _mover_min_sep: float = 1e9
var _mover_max_step: float = 0.0
var _samples: Array = []


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_force_board_window()
	_parse_args(OS.get_cmdline_user_args())
	_run.call_deferred()


## Pin the window to exactly the board: size, floor, ceiling, and stretch.
## The movie records viewport pixels, so anything wider/narrower than the
## board would letterbox or crop the rows. Harness only; no project change.
func _force_board_window() -> void:
	var window: Window = get_window()
	window.min_size = BOARD_SIZE
	window.max_size = BOARD_SIZE
	window.size = BOARD_SIZE
	window.content_scale_size = BOARD_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("shot_hero_attack_motion aborted: user:// path is not isolated — ", user_root)
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
			"vfx":
				_vfx = not (parts[1] == "0" or parts[1] == "false")
			"duration":
				_duration = clampf(float(parts[1]), 2.0, 120.0)


func _run() -> void:
	_build_board()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().canvas_transform = Transform2D.IDENTITY
	_force_board_window()
	print("motion board window: ", get_window().size,
		" viewport: ", get_viewport().get_visible_rect().size)
	_expect_equal(get_window().size, BOARD_SIZE, "board window pins 1616x720")
	if _validate_only:
		_freeze_board()
		_expect_framing()
		_sample_mode(true)
		_sample_mode(false)
		_expect_moving_gait()
		_write_observations()
	else:
		await _run_timed_loop()
		_write_run_record()
	if _failed > 0:
		printerr("shot_hero_attack_motion %s failed — %d/%d check(s)" % [
			_tag, _failed, _checked])
		get_tree().quit(1)
		return
	print("shot_hero_attack_motion %s ok — %d check(s), %d sample(s)%s" % [
		_tag, _checked, _samples.size(),
		" (validate only, no PNGs)" if _validate_only else ""])
	get_tree().quit(0)


## One live Player per hero-aim at normal scale, one per hero-facing under a
## 2x linear carrier, one walker per hero on the movers lane. Cameras are
## configured before they enter the tree and switched off, so the board
## renders from the origin at 1:1 with no current camera. The close carrier
## filters linear so the 2x paint stays smooth through global Nearest.
func _build_board() -> void:
	for row in HEROES.size():
		var hero_id: String = HEROES[row]
		var hero: Hero = load("res://resources/heroes/%s.tres" % hero_id) as Hero
		for column in SIDE_ORDER.size():
			var side: String = SIDE_ORDER[column]
			var key: String = "%s_%s" % [hero_id, side]
			var player: Player = PLAYER_SCENE.instantiate() as Player
			player.position = NORMAL_ORIGIN + Vector2(column, row) * NORMAL_CELL
			var cam: Camera2D = player.get_node("Cam") as Camera2D
			cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
			cam.enabled = false
			add_child(player)
			player.set_bounds(
				Rect2(Vector2.ZERO, Vector2(BOARD_SIZE)).grow(200.0))
			_expect_true(player.apply_hero_visual(hero),
				"%s body wears its hero" % key)
			_players[key] = player
		for facing_index in SIDE_ORDER.size():
			var side: String = SIDE_ORDER[facing_index]
			var key: String = "%s_%s" % [hero_id, side]
			var carrier := Node2D.new()
			carrier.position = CLOSE_ORIGIN \
				+ Vector2(row, facing_index) * CLOSE_CELL
			carrier.scale = Vector2(CLOSE_SCALE, CLOSE_SCALE)
			carrier.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			add_child(carrier)
			var close: Player = PLAYER_SCENE.instantiate() as Player
			var close_cam: Camera2D = close.get_node("Cam") as Camera2D
			close_cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
			close_cam.enabled = false
			carrier.add_child(close)
			close.set_bounds(Rect2(Vector2(-500, -500), Vector2(1000, 1000)))
			_expect_true(close.apply_hero_visual(hero),
				"%s close body wears its hero" % key)
			_close_players[key] = close
		var mover: Player = PLAYER_SCENE.instantiate() as Player
		var center_x: float = MOVER_ORIGIN.x + float(row) * MOVER_DX
		mover.position = Vector2(center_x, MOVER_ORIGIN.y)
		var mover_cam: Camera2D = mover.get_node("Cam") as Camera2D
		mover_cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		mover_cam.enabled = false
		add_child(mover)
		mover.set_bounds(Rect2(
			Vector2(center_x - MOVER_LANE_HALF - 10.0, MOVER_ORIGIN.y - 30.0),
			Vector2((MOVER_LANE_HALF + 10.0) * 2.0, 60.0)))
		_expect_true(mover.apply_hero_visual(hero),
			"%s mover wears its hero" % hero_id)
		_movers[hero_id] = mover
		_mover_dirs[hero_id] = Vector2.LEFT \
			if row % 2 == 0 else Vector2.RIGHT
		_mover_centers[hero_id] = center_x
		_mover_min[hero_id] = center_x
		_mover_max[hero_id] = center_x
		_mover_flips[hero_id] = 0
		_mover_last[hero_id] = mover.position
	_expect_equal(_players.size(), 24, "normal block holds 24 bodies")
	_expect_equal(_close_players.size(), 24, "close block holds 24 bodies")
	_expect_equal(_movers.size(), 6, "movers lane holds 6 walkers")


## Validation drives every attack by hand: no auto clocks, no wall time.
func _freeze_board() -> void:
	for key in _players:
		(_players[key] as Player).process_mode = Node.PROCESS_MODE_DISABLED
	for key in _close_players:
		(_close_players[key] as Player).process_mode = Node.PROCESS_MODE_DISABLED
	for key in _movers:
		(_movers[key] as Player).process_mode = Node.PROCESS_MODE_DISABLED


## One production attack per cell in both modes. The production call faces,
## seats, and poses; no-VFX mode only darkens the draw layer first.
func _attack_cell(player: Player, hero_id: String, aim: Vector2) -> void:
	player.set("_attack_cooldown", 0.0)
	if hero_id in MELEE_PRIMARY:
		player.attack(aim)
	else:
		player.play_moonlight_cast(aim, 1)


func _step(player: Player, dt: float) -> void:
	(player.get_node("WeaponRig") as WeaponRig).call("_process", dt)
	# The orbit only exists for Eclipse; other heroes have no orbit clock.
	var scythe: ScytheOrbit = player.get_node_or_null(
		"ScytheOrbit") as ScytheOrbit
	if scythe != null:
		scythe.call("_process", dt)
	(player.get_node("MoonlightCast") as MoonlightCast).call("_process", dt)
	player.call("_update_attack_pose", dt)


## Sample all six heroes across all eight aims in one mode: cardinals on their
## staged cells, diagonals re-aimed on the row's right cell. Each sample drives
## a production attack to completion and records timing plus geometry.
func _sample_mode(vfx: bool) -> void:
	var mode: String = "vfx" if vfx else "motion"
	var first: int = _samples.size()
	for hero_id in HEROES:
		var aims: Array[Vector2] = []
		for side in SIDE_ORDER:
			aims.append(SIDES[side])
		aims.append_array(DIAGONALS)
		for aim_index in aims.size():
			var aim: Vector2 = aims[aim_index]
			var key: String = "%s_right" % hero_id
			if aim_index < 4:
				key = "%s_%s" % [hero_id, SIDE_ORDER[aim_index]]
			var player: Player = _players[key] as Player
			var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
			# Sampling steps the motion clocks by hand, but the slash cue runs
			# on a tween and short kicks end before their flash: park both
			# before each sample so a VFX pass never leaks a visible cue into
			# the motion pass on the same cell.
			(player.get_node("Slash") as Sprite2D).visible = false
			rig.clear()
			player.set_vfx_suppressed(not vfx)
			_attack_cell(player, hero_id, aim)
			var label: String = "%s %s %s" % [hero_id, str(aim), mode]
			_expect_true(rig.attack_live(), "%s action starts" % label)
			if vfx:
				var cued: bool = (player.get_node("Slash") as Sprite2D).visible \
					or not str(rig.get("_kind")).is_empty()
				_expect_true(cued, "%s cue shows" % label)
			else:
				_expect_false(
					(player.get_node("Slash") as Sprite2D).visible,
					"%s motion shows no slash" % label)
				_expect_true(not str(rig.get("_kind")).is_empty(),
					"%s motion still lights its flash" % label)
				var dark_scythe: ScytheOrbit = player.get_node_or_null(
					"ScytheOrbit") as ScytheOrbit
				_expect_true(bool(rig.get("_vfx_suppressed"))
					and (dark_scythe == null
						or bool(dark_scythe.get("_vfx_suppressed")))
					and bool((player.get_node("MoonlightCast") as MoonlightCast)
						.get("_vfx_suppressed")),
					"%s motion draws dark" % label)
			var sample: Dictionary = {
				"hero": hero_id, "aim": [aim.x, aim.y], "mode": mode,
				"span": rig.attack_span(), "sign": rig.attack_sign(),
			}
			if hero_id in MELEE_PRIMARY:
				sample["contact_err"] = _blade_error(rig, aim)
				_expect_true(float(sample["contact_err"]) < 0.001,
					"%s blade crosses contact" % label)
				var cut: Dictionary = _sample_cut(player, rig)
				sample["arc_deg"] = cut["arc_deg"]
				_expect_true(float(sample["arc_deg"])
					>= float(SWING_MINIMUM[hero_id]),
					"%s cut sweeps %.1f" % [label, float(sample["arc_deg"])])
				sample["wrist_px"] = cut["wrist_px"]
				_expect_true(float(sample["wrist_px"]) > 1.0,
					"%s wrist travels %.2fpx" % [
						label, float(sample["wrist_px"])])
				sample["hand_gap"] = cut["hand_gap"]
				_expect_true(float(sample["hand_gap"]) < 0.05,
					"%s hand rides its grip" % label)
				if hero_id == "eclipse":
					sample["sweep_deg"] = _sample_sweep(
						player, hero_id, aim, vfx)
					_expect_true(float(sample["sweep_deg"]) >= 120.0,
						"%s orbit sweep travels %.1f" % [
							label, float(sample["sweep_deg"])])
			else:
				var drawn: Vector2 = rig.to_global(rig.drawn_tip_now())
				sample["muzzle_gap"] = drawn.distance_to(
					player.muzzle_origin(aim))
				_expect_true(float(sample["muzzle_gap"]) < 0.5,
					"%s muzzle meets its spawn" % label)
				var shot: Dictionary = _sample_shot(player, rig)
				sample["kick_px"] = shot["kick_px"]
				_expect_true(absf(float(sample["kick_px"])
					- float(SHOT_SLIDE[hero_id])) < 0.3,
					"%s kicks %.2fpx" % [label, float(sample["kick_px"])])
				sample["wrist_px"] = shot["wrist_px"]
				_expect_true(float(sample["wrist_px"]) > 1.0,
					"%s wrist travels %.2fpx" % [
						label, float(sample["wrist_px"])])
				sample["hand_gap"] = shot["hand_gap"]
				_expect_true(float(sample["hand_gap"]) < 0.05,
					"%s hand rides its grip" % label)
			sample["settled"] = _is_settled(player, rig)
			_expect_true(bool(sample["settled"]), "%s settles" % label)
			_samples.append(sample)
	_expect_equal(_samples.size() - first, 48,
		"%s mode covers 48 primary samples" % mode)


## One more Eclipse cut, returning the peak orbit-sweep travel in degrees.
func _sample_sweep(
	player: Player, hero_id: String, aim: Vector2, vfx: bool
) -> float:
	player.set_vfx_suppressed(not vfx)
	_attack_cell(player, hero_id, aim)
	var scythe: ScytheOrbit = player.get_node("ScytheOrbit") as ScytheOrbit
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	var travel: float = 0.0
	var span: float = rig.attack_span()
	var age: float = 0.0
	var dt: float = 1.0 / 240.0
	while age < span + dt:
		if not rig.attack_live():
			break
		travel = maxf(travel, absf(scythe.sweep_travel_now()))
		_step(player, dt)
		age += dt
	_step(player, dt)
	return rad_to_deg(travel)


## Drive one cut to completion, returning the unwrapped tip arc in degrees,
## the peak painted-wrist world travel in px, and the peak hand-to-grip gap.
func _sample_cut(player: Player, rig: WeaponRig) -> Dictionary:
	var arm: ArmRig = player.get_node("ArmMain") as ArmRig
	var start: Vector2 = _wrist_world(player, arm)
	var angles: Array[float] = []
	var travel: float = 0.0
	var gap: float = 0.0
	var span: float = rig.attack_span()
	var age: float = 0.0
	var dt: float = 1.0 / 120.0
	while age < span + dt:
		if not rig.attack_live():
			break
		var grip: Vector2 = rig.draw_anchor_now()
		angles.append((rig.drawn_tip_now() - grip).angle())
		travel = maxf(travel, start.distance_to(_wrist_world(player, arm)))
		gap = maxf(gap, _hand_gap(player, rig))
		_step(player, dt)
		age += dt
	_step(player, dt)
	var running: float = angles[0]
	var lo: float = running
	var hi: float = running
	for index in range(1, angles.size()):
		running += angle_difference(running, angles[index])
		lo = minf(lo, running)
		hi = maxf(hi, running)
	return {
		"arc_deg": rad_to_deg(hi - lo),
		"wrist_px": travel,
		"hand_gap": gap,
	}


## Drive one discharge to completion, returning the peak kick in px, the peak
## painted-wrist world travel, and the peak hand-to-grip gap.
func _sample_shot(player: Player, rig: WeaponRig) -> Dictionary:
	var arm: ArmRig = player.get_node("ArmMain") as ArmRig
	var start: Vector2 = _wrist_world(player, arm)
	var peak: float = 0.0
	var travel: float = 0.0
	var gap: float = 0.0
	var span: float = rig.attack_span()
	var age: float = 0.0
	var dt: float = 1.0 / 240.0
	while age < span + dt:
		if not rig.attack_live():
			break
		peak = maxf(peak, rig.attack_shift_now().length())
		travel = maxf(travel, start.distance_to(_wrist_world(player, arm)))
		gap = maxf(gap, _hand_gap(player, rig))
		_step(player, dt)
		age += dt
	_step(player, dt)
	return {"kick_px": peak, "wrist_px": travel, "hand_gap": gap}


func _blade_error(rig: WeaponRig, aim: Vector2) -> float:
	var grip: Vector2 = rig.draw_anchor_now()
	return absf((rig.drawn_tip_now() - grip).angle_to(aim.normalized()))


## Hand-to-grip gap in world space: the drawn grip against the painted wrist
## the IK solver reports.
func _hand_gap(player: Player, rig: WeaponRig) -> float:
	var arm: ArmRig = player.get_node("ArmMain") as ArmRig
	var wrist_local: Vector2 = Player.cell_to_local(arm.wrist_cell(),
		float(player.get("_sprite_base_y")), float(player.get("_hero_scale")),
		player.call("_current_shift_cells"))
	var grip_local: Vector2 = rig.position + rig.draw_anchor_now()
	var profile: Hero.AttackProfile = player.get("_hero_profile")
	if HeroWeapons.primary_side(profile) == HeroWeapons.Side.RANGED:
		var flat: Vector2 = rig.aim().normalized() \
			if rig.aim().length() > 0.01 else Vector2.RIGHT
		grip_local = rig.position - flat * WeaponRig.stock_back(profile)
	return grip_local.distance_to(wrist_local)


func _wrist_world(player: Player, arm: ArmRig) -> Vector2:
	return player.to_global(Player.cell_to_local(arm.wrist_cell(),
		float(player.get("_sprite_base_y")), float(player.get("_hero_scale")),
		player.call("_current_shift_cells")))


## Settled at rest: no live motion, zero offsets, home seat, hidden split,
## playing sprite, planted feet.
func _is_settled(player: Player, rig: WeaponRig) -> bool:
	if rig.attack_live():
		return false
	if rig.swing_angle_now() != 0.0 or rig.gun_pitch_now() != 0.0:
		return false
	if rig.attack_shift_now() != Vector2.ZERO:
		return false
	if rig.position != player.rest_rig_seat(rig.aim()):
		return false
	if bool(player.get("_split_shown")):
		return false
	var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	if not sprite.visible or not sprite.is_playing():
		return false
	if sprite.position != Vector2(0.0, float(player.get("_sprite_base_y"))):
		return false
	return sprite.rotation == 0.0


## Every body plus its weapon tip, painted wrist, and orbit bounds stands on
## screen at contact, peak, and settle — all 24 normal cells, all 24 close
## cells through their 2x carriers, and all 6 movers.
func _expect_framing() -> void:
	var viewport: Viewport = get_viewport()
	_expect_true(viewport.get_camera_2d() == null, "board owns no camera")
	_expect_equal(viewport.canvas_transform, Transform2D.IDENTITY,
		"board transform predictable")
	var visible: Rect2 = viewport.canvas_transform.affine_inverse() \
		* viewport.get_visible_rect()
	for key in _players:
		var parts: PackedStringArray = str(key).split("_")
		_expect_cell_framed(visible, _players[key], parts[0],
			SIDES[parts[1]], key)
	for key in _close_players:
		var parts: PackedStringArray = str(key).split("_")
		_expect_cell_framed(visible, _close_players[key], parts[0],
			SIDES[parts[1]], "close_%s" % key)
	for hero_id in _movers:
		_expect_cell_framed(visible, _movers[hero_id], hero_id,
			Vector2.RIGHT, "%s_mover" % hero_id)


func _expect_cell_framed(
	visible: Rect2, player: Player, hero_id: String, aim: Vector2,
	label: String
) -> void:
	_expect_true(visible.has_point(player.global_position),
		"%s body stands on screen" % label)
	player.set_vfx_suppressed(false)
	_attack_cell(player, hero_id, aim)
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	var arm: ArmRig = player.get_node("ArmMain") as ArmRig
	for stage in ["contact", "peak", "settle"]:
		_expect_true(visible.has_point(rig.to_global(rig.drawn_tip_now())),
			"%s tip on screen at %s" % [label, stage])
		_expect_true(visible.has_point(_wrist_world(player, arm)),
			"%s wrist on screen at %s" % [label, stage])
		if hero_id == "eclipse":
			_expect_orbit_framed(visible, player, label, stage)
		_step(player, rig.attack_span() / 2.0)
	_finish(player, rig)
	player.set_vfx_suppressed(false)


func _expect_orbit_framed(
	visible: Rect2, player: Player, label: String, stage: String
) -> void:
	var scythe: ScytheOrbit = player.get_node("ScytheOrbit") as ScytheOrbit
	var zoom: float = absf(
		(player as Node2D).get_global_transform().get_scale().x)
	var radius: float = scythe.orbit_radius() * maxf(zoom, 0.01)
	var center: Vector2 = scythe.global_position
	for extreme in [Vector2(radius, 0), Vector2(-radius, 0),
			Vector2(0, radius), Vector2(0, -radius)]:
		_expect_true(visible.has_point(center + extreme),
			"%s orbit on screen at %s" % [label, stage])


func _finish(player: Player, rig: WeaponRig) -> void:
	if rig.attack_live():
		var left: float = rig.attack_span() - float(rig.get("_attack_age"))
		_step(player, maxf(left, 0.0) + 1.0 / 120.0)
	_step(player, 1.0 / 120.0)


## Movers lane proves the gait: walking attacks step the drawn legs through
## distinct frames, opposite aims hold facing while stepping, and stationary
## attacks keep the idle sheet with planted feet.
func _expect_moving_gait() -> void:
	for hero_id in HEROES:
		var mover: Player = _movers[hero_id] as Player
		mover.set_vfx_suppressed(true)
		mover.call("set_walking", true)
		_attack_cell(mover, hero_id, Vector2.RIGHT)
		var rig: WeaponRig = mover.get_node("WeaponRig") as WeaponRig
		var legs: Sprite2D = mover.get_node("AttackLegs") as Sprite2D
		var frames: Dictionary = {}
		var span: float = rig.attack_span()
		var age: float = 0.0
		var dt: float = 1.0 / 120.0
		while age < span + dt:
			if not rig.attack_live():
				break
			var atlas: AtlasTexture = legs.texture as AtlasTexture
			frames[int(atlas.region.position.y)] = true
			_step(mover, dt)
			age += dt
		_expect_true(frames.size() >= 2,
			"%s mover steps its legs (%d frames)" % [hero_id, frames.size()])
		_finish(mover, rig)
		mover.call("set_walking", false)
		_attack_cell(mover, hero_id, Vector2.RIGHT)
		var idle_atlas: AtlasTexture = (
			mover.get_node("AttackLegs") as Sprite2D).texture as AtlasTexture
		var hero: Hero = load(
			"res://resources/heroes/%s.tres" % hero_id) as Hero
		_expect_equal(idle_atlas.atlas, hero.idle_sheet,
			"%s stationary legs keep the idle sheet" % hero_id)
		_finish(mover, rig)
		mover.set_vfx_suppressed(false)
	_samples.append({"movers": _movers.size()})


## Timed windowed loop for `--write-movie`: rows ripple so every cycle shows
## all six actions mid-flight at both scales plus the walkers' repeated
## moving attacks, then the board settles and quits. Each cycle samples every
## cell's live pose (progress, wrist, blade angle), so the run record proves
## multiple distinct rendered poses per cell — not just that the attack
## methods were called. Movers ping-pong inside their lanes, bouncing at the
## edges without teleporting, always aiming against their travel; every
## sample frame-checks all six bodies, tips, wrists, and orbits on screen.
func _run_timed_loop() -> void:
	for key in _players:
		(_players[key] as Player).set_vfx_suppressed(not _vfx)
	for key in _close_players:
		(_close_players[key] as Player).set_vfx_suppressed(not _vfx)
	for key in _movers:
		(_movers[key] as Player).set_vfx_suppressed(not _vfx)
	var poses: Dictionary = {}
	for key in _players:
		poses[key] = {}
	for key in _close_players:
		poses["close_%s" % key] = {}
	for key in _movers:
		poses["mover_%s" % key] = {}
	for hero_id in _movers:
		_mover_last[hero_id] = (_movers[hero_id] as Player).position
		_mover_min[hero_id] = (_movers[hero_id] as Player).position.x
		_mover_max[hero_id] = (_movers[hero_id] as Player).position.x
	var elapsed: float = 0.0
	var cycles: int = 0
	while elapsed < _duration:
		for row in HEROES.size():
			var hero_id: String = HEROES[row]
			for side in SIDE_ORDER:
				var key: String = "%s_%s" % [hero_id, side]
				_attack_cell(_players[key], hero_id, SIDES[side])
				_attack_cell(_close_players[key], hero_id, SIDES[side])
			_bounce_mover(hero_id)
			_sample_poses(poses)
			_track_movers()
			cycles += 1
			await get_tree().create_timer(
				ROW_GAP_SECONDS * 0.5, true, false, true).timeout
			_sample_poses(poses)
			_track_movers()
			await get_tree().create_timer(
				ROW_GAP_SECONDS * 0.5, true, false, true).timeout
			_sample_poses(poses)
			_track_movers()
			elapsed += ROW_GAP_SECONDS
		_sample_poses(poses)
		_track_movers()
		var rest: float = CYCLE_SECONDS - ROW_GAP_SECONDS * HEROES.size()
		await get_tree().create_timer(maxf(rest, 0.05), true, false, true).timeout
		elapsed += maxf(rest, 0.05)
	for key in _movers:
		(_movers[key] as Player).set_move_input(Vector2.ZERO)
	_sample_poses(poses)
	_track_movers()
	await get_tree().create_timer(0.6, true, false, true).timeout
	_sample_poses(poses)
	_track_movers()
	_expect_true(cycles > 0, "timed loop attacks every row")
	for key in poses:
		_expect_true((poses[key] as Dictionary).size() >= 5,
			"%s cycles through distinct poses (%d)" % [
				key, (poses[key] as Dictionary).size()])
	_expect_movers_traveled()
	var travel: Dictionary = {}
	for hero_id in _movers:
		travel[hero_id] = {
			"px": float(_mover_max[hero_id]) - float(_mover_min[hero_id]),
			"flips": int(_mover_flips[hero_id]),
		}
	_samples.append({
		"pose_cells": poses.size(),
		"pose_min": _pose_min(poses),
		"cycles": cycles,
		"mover_min_sep": _mover_min_sep,
		"mover_max_step": _mover_max_step,
		"mover_travel": travel,
	})
	print("motion loop ran %d row attacks over %.1fs (vfx=%s)" % [
		cycles, elapsed, str(_vfx)])


## One mover's lane bounce: hold the current direction until an edge, then
## flip. The attack aims against travel, so every pass shows a moving attack
## facing its target while the feet walk the other way. No teleports: the
## body steers by input only and the per-lane bounds clamp any overshoot.
func _bounce_mover(hero_id: String) -> void:
	var mover: Player = _movers[hero_id] as Player
	var center: float = float(_mover_centers[hero_id])
	var held: Vector2 = _mover_dirs[hero_id] as Vector2
	var next: Vector2 = held
	if mover.position.x <= center - MOVER_LANE_HALF + MOVER_EDGE_SLOP:
		next = Vector2.RIGHT
	elif mover.position.x >= center + MOVER_LANE_HALF - MOVER_EDGE_SLOP:
		next = Vector2.LEFT
	if next != held:
		_mover_flips[hero_id] = int(_mover_flips[hero_id]) + 1
	_mover_dirs[hero_id] = next
	mover.set_move_input(next)
	_attack_cell(mover, hero_id, -next)
	var rig: WeaponRig = mover.get_node("WeaponRig") as WeaponRig
	_expect_true(rig.aim().dot(next) < -0.9,
		"%s mover aims against its travel" % hero_id)


## Frame-check every mover on every timed sample: body, tip, and wrist on
## screen, the Eclipse orbit inside, plus travel extremes, pairwise
## separation, and the largest single-step jump for the no-teleport proof.
func _track_movers() -> void:
	var viewport: Viewport = get_viewport()
	var visible: Rect2 = viewport.canvas_transform.affine_inverse() \
		* viewport.get_visible_rect()
	for hero_id in _movers:
		var mover: Player = _movers[hero_id] as Player
		var rig: WeaponRig = mover.get_node("WeaponRig") as WeaponRig
		var arm: ArmRig = mover.get_node("ArmMain") as ArmRig
		_expect_true(visible.has_point(mover.global_position),
			"%s mover body stays in view" % hero_id)
		_expect_true(visible.has_point(rig.to_global(rig.drawn_tip_now())),
			"%s mover tip stays in view" % hero_id)
		_expect_true(visible.has_point(_wrist_world(mover, arm)),
			"%s mover wrist stays in view" % hero_id)
		if hero_id == "eclipse":
			_expect_orbit_framed(visible, mover,
				"%s_mover" % hero_id, "timed")
		var pos: Vector2 = mover.position
		_mover_min[hero_id] = minf(float(_mover_min[hero_id]), pos.x)
		_mover_max[hero_id] = maxf(float(_mover_max[hero_id]), pos.x)
		var last: Vector2 = _mover_last[hero_id] as Vector2
		_mover_max_step = maxf(_mover_max_step, last.distance_to(pos))
		_mover_last[hero_id] = pos
	var ids: Array = _movers.keys()
	for first in ids.size():
		for second in range(first + 1, ids.size()):
			var a: Vector2 = (_movers[ids[first]] as Player).position
			var b: Vector2 = (_movers[ids[second]] as Player).position
			_mover_min_sep = minf(_mover_min_sep, a.distance_to(b))


## Each mover traveled both ways across its lane, flipped more than once,
## never jumped, and never crowded another body.
func _expect_movers_traveled() -> void:
	for hero_id in _movers:
		var travel: float = float(_mover_max[hero_id]) \
			- float(_mover_min[hero_id])
		_expect_true(travel >= MOVER_MIN_TRAVEL,
			"%s mover travels both ways (%.1fpx)" % [hero_id, travel])
		_expect_true(int(_mover_flips[hero_id]) >= 2,
			"%s mover bounces repeatedly (%d)" % [
				hero_id, int(_mover_flips[hero_id])])
	_expect_true(_mover_max_step <= MOVER_MAX_STEP,
		"movers never teleport (max %.1fpx)" % _mover_max_step)
	_expect_true(_mover_min_sep >= MOVER_MIN_SEPARATION,
		"movers stay separate (min %.1fpx)" % _mover_min_sep)


## Record one coarse pose bucket per cell: progress, wrist, and blade angle
## quantized so repeats collapse and distinct poses accumulate.
func _sample_poses(poses: Dictionary) -> void:
	for key in _players:
		_sample_pose(poses[key], _players[key])
	for key in _close_players:
		_sample_pose(poses["close_%s" % key], _close_players[key])
	for key in _movers:
		_sample_pose(poses["mover_%s" % key], _movers[key])


func _sample_pose(buckets: Dictionary, player: Player) -> void:
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	var arm: ArmRig = player.get_node("ArmMain") as ArmRig
	var progress: float = rig.attack_progress()
	var wrist: Vector2 = _wrist_world(player, arm)
	var blade: float = rig.draw_angle_now()
	var bucket: String = "%d_%d_%d_%d" % [
		int(floor(progress * 8.0)),
		int(floor(wrist.x / 1.0)), int(floor(wrist.y / 1.0)),
		int(floor(blade / 0.15))]
	buckets[bucket] = true


func _pose_min(poses: Dictionary) -> int:
	var fewest: int = 1 << 30
	for key in poses:
		fewest = mini(fewest, (poses[key] as Dictionary).size())
	return fewest


func _write_observations() -> void:
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	var failures: int = _failed
	var record: Dictionary = {
		"tag": _tag, "mode": "validate",
		"heroes": HEROES, "aims": 8, "modes": ["vfx", "motion"],
		"samples": _samples.size(), "checks": _checked,
		"failures": failures,
		"samples_detail": _samples,
	}
	var path: String = "%s/%s.json" % [out, _tag]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failed += 1
		printerr("  failed: observations unwritable — ", path)
		return
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	print("wrote %s (%d samples)" % [path, _samples.size()])


func _write_run_record() -> void:
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	var record: Dictionary = {
		"tag": _tag, "mode": "movie",
		"vfx": _vfx, "duration": _duration,
		"heroes": HEROES, "sides": SIDE_ORDER,
		"board": [BOARD_SIZE.x, BOARD_SIZE.y],
		"window": [get_window().size.x, get_window().size.y],
		"checks": _checked, "failures": _failed,
		"samples_detail": _samples,
	}
	var path: String = "%s/%s.movie.json" % [out, _tag]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failed += 1
		printerr("  failed: run record unwritable — ", path)
		return
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	print("wrote %s" % path)


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
