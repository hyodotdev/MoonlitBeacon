extends Node

## Photograph the six live primary weapons plus beacon choices in five locales.
##
## Controlled stationary-target staging: each hero fights a real arena with
## production attacks only, but spawns are suppressed and a single live spirit
## holds still in the weapon's pocket, so the requested side is the only aim
## in the room and every strip shows a true primary aim — never a passing
## enemy's retarget. The arena's own clock fires, and the shot is taken only
## after a real hit lands with live effects on screen. Nothing is posed.
## Early builds run natural hero openings; strong builds feed a fixed relic list
## plus cores on top. Beacon choices open the real panel once per locale in both
## core states, photographed only once the fade has settled and choices arm.
## Natural bots stay the gameplay evidence; this tool stages aim evidence.
##
## Render on a real display (captures need `frame_post_draw`, which never fires
## headless). Validate anywhere headless: every observation runs, only PNG writes
## are skipped.
##
##     pnpm godot:isolated --windowed res://tools/shot_weapons.tscn -- tag=weapons
##     pnpm godot:isolated --timeout 900 res://tools/shot_weapons.tscn -- tag=weapons validate=1
##     pnpm godot:isolated --windowed --write-movie ../../builds/shots/weapons/tag_5245.avi res://tools/shot_weapons.tscn -- tag=5245 heroes=knight builds=strong
##
## Arguments (`-- key=value`): tag validate heroes builds sides.
## Output lands in `builds/shots/weapons/`, so it is not committed. Motion evidence
## is a four-frame 0.6s strip per hero-build-side (frames 0.2s apart), every
## frame synced to `frame_post_draw` so the strip shows four distinct moments;
## audio audition is the generator's own
## `python3 apps/game/tools/build_combat_audio.py --audition builds/audio/audition.wav`.
## Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const ARENA: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const ARROW_SCRIPT: Script = preload("res://scripts/actors/moon_arrow.gd")
## Slack over the hero's live fan when judging one lane against its
## mark line: float dust plus cross-attempt mark placement. A reversed
## flight still misses by ~180°, a legal lane by at most the fan.
const LANE_SLACK_DEG: float = 6.0
## Primary-anchor wait: inspect every process frame until this wall
## deadline. Sampling any slower aliases against the rapid cadence.
const PRIMARY_ANCHOR_MSEC: int = 6000
const OUT: String = "res://../../builds/shots/weapons"
const REQUEST_PATH: String = "user://test_hero.request"

const HEROES: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage",
]
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
## Spirit pocket per hero: inside the primary's bite, measured from the player.
const POCKETS: Dictionary = {
	"warden": 40.0, "dancer": 34.0, "keeper": 90.0,
	"knight": 140.0, "eclipse": 45.0, "sage": 150.0,
}
## Pocket sides: the single stationary spirit waits on this side, the body
## faces it through the movement contract, and the production aim points at
## it — four sides photograph all four body facings and all four true aims
## of every held weapon. The anchored aim is asserted, never inferred from
## the facing alone.
const SIDES: Dictionary = {
	"right": Vector2(1, 0), "left": Vector2(-1, 0),
	"up": Vector2(0, -1), "down": Vector2(0, 1),
}
## Body facing per side through `Player.face_toward`: the staged capture shows
## real `idle_<side>` bodies, not one front-facing sprite with moved targets.
const SIDE_FACING: Dictionary = {
	"right": Player.Facing.RIGHT, "left": Player.Facing.LEFT,
	"up": Player.Facing.UP, "down": Player.Facing.DOWN,
}
## Fixed strong build cards on top of each hero's own opening: sharp moons plus
## rate, fan, and pierce cards, then five cores.
const STRONG_RELICS: Array[String] = [
	"res://resources/relics/sharp_moon.tres",
	"res://resources/relics/sharp_moon.tres",
	"res://resources/relics/swift_hand.tres",
	"res://resources/relics/long_blade.tres",
	"res://resources/relics/wide_arc.tres",
	"res://resources/relics/twin_arrow.tres",
	"res://resources/relics/quick_arrow.tres",
	"res://resources/relics/pierce_arrow.tres",
]
const STRONG_POWER: int = 5

var _tag: String = "shot"
var _validate_only: bool = false
var _heroes: Array[String] = HEROES.duplicate()
var _builds: Array[String] = ["early", "strong"]
var _sides: Array[String] = ["right", "left", "up", "down"]
var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(808, 360)
	get_window().content_scale_size = Vector2i(808, 360)
	_parse_args(OS.get_cmdline_user_args())
	_run.call_deferred()


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("shot_weapons aborted: user:// path is not isolated — ", user_root)
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
			"heroes":
				_heroes.clear()
				for hero_id in parts[1].split(","):
					if hero_id in HEROES:
						_heroes.append(hero_id)
				if _heroes.is_empty():
					_heroes = HEROES.duplicate()
			"builds":
				_builds.clear()
				for build in parts[1].split(","):
					if build in ["early", "strong"]:
						_builds.append(build)
				if _builds.is_empty():
					_builds = ["early", "strong"]
			"sides":
				_sides.clear()
				for side in parts[1].split(","):
					if side in SIDES:
						_sides.append(side)
				if _sides.is_empty():
					_sides = ["right", "left", "up", "down"]


func _run() -> void:
	var out: String = ProjectSettings.globalize_path(OUT)
	if not _validate_only:
		DirAccess.make_dir_recursive_absolute(out)
	for hero_id in _heroes:
		for build in _builds:
			for side in _sides:
				await _stage_hero(hero_id, build, side, out)
	await _stage_beacons(out)
	if _failed > 0:
		printerr("shot_weapons %s failed — %d/%d check(s)" % [_tag, _failed, _checked])
		get_tree().quit(1)
		return
	print("shot_weapons %s ok — %d check(s), controlled stationary targets%s" % [
		_tag, _checked, " (validate only, no PNGs)" if _validate_only else ""])
	get_tree().quit(0)


## One hero-build-side: real arena, controlled stationary mark, production
## fight, observed hit, asserted true aim, then the strip.
func _stage_hero(hero_id: String, build: String, side: String, out: String) -> void:
	var request: FileAccess = FileAccess.open(REQUEST_PATH, FileAccess.WRITE)
	request.store_string("res://resources/heroes/%s.tres\n" % hero_id)
	request.close()
	var arena: Node2D = ARENA.instantiate() as Node2D
	get_tree().root.add_child.call_deferred(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = arena
	_settle_arena(arena)
	var player: Node2D = arena.get_node("Player") as Node2D
	_expect_equal(arena.call("_hero_path_for_run"),
		"res://resources/heroes/%s.tres" % hero_id,
		"%s runs its own hero" % hero_id)
	# Openings are production: each staged build must carry its hero's fixed relics.
	var hero: Hero = load("res://resources/heroes/%s.tres" % hero_id) as Hero
	var taken_paths: Array[String] = []
	for relic in arena.get("_taken") as Array:
		taken_paths.append(str((relic as Relic).get_meta("path")))
	for path in hero.opening:
		_expect_true(taken_paths.has(path),
			"%s %s carries its opening" % [hero_id, build])
	if build == "strong":
		for path in STRONG_RELICS:
			arena.call("_on_relic_picked",
				arena.get("_relic").call("take_named", path), false, "stage")
		arena.set("_missile_power", STRONG_POWER)
		arena.call("_settle_rates")
		arena.call("_refresh_missile_hud")
	# Survival staging only: the shield never touches attacks, which stay 100%
	# production; the observed hits below are real damage on a live spirit.
	arena.call("debug_shield")
	# Controlled staging: freeze capture progress first, so staged kills can
	# never level, open the relic draft, and pause the tree mid-strip — the
	# draft has no cancel path and its pause outlives the arena, which froze
	# every later stage. Then suppress spawns and raids, drain the queued
	# opening raid/vigil, and clear any wild spirit the settle frames
	# produced, so the staged pocket target is the only aim in the room and
	# no passing enemy can retarget the strip. Wild-era arrows in flight are
	# pre-staging noise too: the staged lanes must all fly at the mark.
	arena.call("debug_freeze_capture_progress")
	get_tree().paused = false
	arena.set("_spawn_timer", 99999.0)
	arena.set("_raid_left", 99999)
	var queued_raid: Array = arena.get("_raid_queue") as Array
	queued_raid.clear()
	for wild in get_tree().get_nodes_in_group("spirits"):
		if is_instance_valid(wild) and arena.is_ancestor_of(wild):
			wild.queue_free()
	for stray in get_tree().get_nodes_in_group("friendly_projectiles"):
		if is_instance_valid(stray) and arena.is_ancestor_of(stray):
			stray.queue_free()
	var roster: Array = arena.get("_spirits") as Array
	roster.clear()
	await get_tree().process_frame
	var pocket: float = float(POCKETS[hero_id])
	var seen_hit: bool = false
	var seen_live_effect: bool = false
	# A strong build can one-shot the wisp before any poll sees the slash. Offer
	# up to three live spirits in turn; the capture still needs a real hit plus
	# a live effect observed together, only the target is replaced.
	for attempt in 3:
		var spirit: Node2D = arena.call("_summon",
			player.global_position + (SIDES[side] as Vector2) * pocket,
			"res://resources/wisp.tres", 0.5, false) as Node2D
		spirit.set("_materialized", true)
		# Stationary but live: the body holds its mark while HP, damage and
		# perish stay production, so the aim never drifts off the side.
		spirit.set_physics_process(false)
		var health_before: int = int(spirit.get("_health"))
		for poll in 24:
			await get_tree().create_timer(0.25, true).timeout
			if not is_instance_valid(spirit):
				seen_hit = true
				break
			if int(spirit.get("_health")) < health_before:
				seen_hit = true
			if _live_effect_visible(arena, player, hero_id):
				seen_live_effect = true
			if seen_hit and seen_live_effect:
				break
			arena.call("debug_heal")
		if seen_hit and seen_live_effect:
			break
	_expect_true(seen_hit, "%s %s %s production hit lands" % [hero_id, build, side])
	_expect_true(seen_live_effect, "%s %s %s live effect shows" % [hero_id, build, side])
	# Hold the strip for a live primary moment so frame 0 anchors on the hero's
	# own weapon, not a backup-slot answer. The poll loop may have spent its
	# spirits, so offer a fresh body if the room went quiet.
	if arena.call("_nearest_spirit") == null:
		var fresh: Node2D = arena.call("_summon",
			player.global_position + (SIDES[side] as Vector2) * pocket,
			"res://resources/wisp.tres", 0.5, false) as Node2D
		fresh.set("_materialized", true)
		fresh.set_physics_process(false)
	var seen_primary: bool = false
	# Every process frame until the deadline: a 0.25s sample aliases
	# against the rapid cadence, polling cooldown gaps while the flash
	# shows on frames between polls. The break latches only a primary
	# observed live on this frame, never a cached past effect.
	var anchor_until_msec: int = Time.get_ticks_msec() + PRIMARY_ANCHOR_MSEC
	while Time.get_ticks_msec() < anchor_until_msec:
		if _live_primary_effect_visible(arena, player, hero_id):
			seen_primary = true
			break
		# The controlled room holds no backup targets: if the mark perished,
		# offer a fresh body so the clock keeps swinging for the anchor.
		if _live_mark_count(arena) == 0:
			var topup: Node2D = arena.call("_summon",
				player.global_position + (SIDES[side] as Vector2) * pocket,
				"res://resources/wisp.tres", 0.5, false) as Node2D
			topup.set("_materialized", true)
			topup.set_physics_process(false)
		arena.call("debug_heal")
		await get_tree().process_frame
	_expect_true(seen_primary, "%s %s %s primary shows for the strip" % [hero_id, build, side])
	# The body faces its pocket through the movement contract, set atomically
	# with the strip: a wild swing mid-staging may have re-faced it elsewhere.
	player.call("face_toward", SIDES[side])
	_expect_equal(int(player.get("facing")), int(SIDE_FACING[side]),
		"%s %s %s body faces its pocket" % [hero_id, build, side])
	_expect_equal((player.get_node("Sprite") as AnimatedSprite2D).animation,
		"idle_%s" % side,
		"%s %s %s body sprite shows its facing" % [hero_id, build, side])
	# The anchored primary aim itself points at the requested side: the rig's
	# live aim shares the side's dominant axis. Twin alternation (±28°)
	# stays inside the axis; a retarget never does. Grouped missiles have
	# no lanes; the rig aim covers them.
	var rig_aim: Vector2 = player.get_node("WeaponRig").get("_aim") as Vector2
	_expect_true(_aim_matches_side(rig_aim, side),
		"%s %s %s primary aim points %s" % [hero_id, build, side, side])
	# Controlled marks only: every live target sits on the requested side
	# and holds still (physics off from birth; HP/damage/perish production).
	var marks: Array[Node] = []
	for spirit in get_tree().get_nodes_in_group("spirits"):
		if is_instance_valid(spirit) and arena.is_ancestor_of(spirit) \
				and not spirit.is_queued_for_deletion():
			marks.append(spirit)
	for mark in marks:
		_expect_true(
			_aim_matches_side(
				(mark as Node2D).global_position - player.global_position, side),
			"%s %s %s staged mark waits %s" % [hero_id, build, side, side])
		_expect_false((mark as Node).is_physics_processing(),
			"%s %s %s staged mark holds still" % [hero_id, build, side])
	var mark_at: Vector2 = (marks[0] as Node2D).global_position \
		if not marks.is_empty() else Vector2.ZERO
	# Every surviving lane flies its own true line: origin to staged mark
	# within the hero's live fan plus slack. Gun primaries launch from the
	# muzzle, melee candle backups from the candle — `muzzle_origin` seats
	# both exactly as production did. Survivors never reconstruct a volley
	# (hits eat the center lane, even volleys alternate the unpaired side),
	# so each lane is judged alone against a mark, never averaged and never
	# against a compass axis. With no live mark the target is gone and
	# flight is unobservable; rig, body, and hit asserts still stand.
	if not marks.is_empty():
		var fan_deg: float = arena.get("_ranged_fan")
		for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
			if is_instance_valid(projectile) and arena.is_ancestor_of(projectile) \
					and projectile.get_script() == ARROW_SCRIPT:
				var lane: Vector2 = \
					(projectile.get("_base_direction") as Vector2).normalized()
				var origin: Vector2 = player.call("muzzle_origin", lane) as Vector2
				var best_deg: float = 180.0
				for mark in marks:
					var want: Vector2 = (mark as Node2D).global_position - origin
					if want.length() < 0.01:
						continue
					best_deg = minf(best_deg,
						absf(rad_to_deg(lane.angle_to(want.normalized()))))
				_expect_true(best_deg <= fan_deg + LANE_SLACK_DEG,
					"%s %s %s lane flies its mark" % [hero_id, build, side])
	if not _validate_only and seen_hit and seen_live_effect and seen_primary:
		for frame in 4:
			if frame > 0:
				var until: int = Time.get_ticks_msec() + 200
				while Time.get_ticks_msec() < until:
					await RenderingServer.frame_post_draw
			# Every frame waits for a finished draw — including the first, so a
			# mid-fight capture never grabs a half-presented frame.
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				"%s/%s_%s_%s_%s_%d.png" % [out, _tag, hero_id, build, side, frame])
		print("saved %s %s %s controlled strip" % [hero_id, build, side])
	if _validate_only and not marks.is_empty():
		await get_tree().create_timer(0.25, true).timeout
	if not marks.is_empty() and is_instance_valid(marks[0]) \
			and not (marks[0] as Node).is_queued_for_deletion():
		_expect_true(
			((marks[0] as Node2D).global_position - mark_at).length() < 0.5,
			"%s %s %s staged mark never drifts" % [hero_id, build, side])
	if hero_id == "knight":
		await _expect_recoil_rest(arena, player, "%s %s %s" % [hero_id, build, side])
	# Never leak a modal pause into the next stage: the tree must run there.
	get_tree().paused = false
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## The cannon settles between shots: inside a 0.5s window the sprite rests at
## its base at least once, so the strip's later frames show a settled gun.
func _expect_recoil_rest(arena: Node2D, player: Node2D, label: String) -> void:
	var sprite: Node2D = player.get_node("Sprite") as Node2D
	var rest: Vector2 = Vector2(0.0, float(player.get("_sprite_base_y")))
	var rested: bool = false
	for poll in 5:
		await get_tree().create_timer(0.1, true).timeout
		if not is_instance_valid(arena):
			break
		rested = rested or sprite.position.distance_to(rest) < 1.0
	_expect_true(rested, "%s recoil rests between shots" % label)


## Clean capture state for one staged arena: no dev toolbar, no tutorial or
## onboarding banners, no opening voice line still up, ko locale. Attacks,
## spawns, and drops stay production — only overlays settle.
func _settle_arena(arena: Node2D) -> void:
	var meter: Node = arena.get_node_or_null("Ui/FrameMeter")
	if meter != null:
		meter.queue_free()
	var tools: Node = arena.get_node_or_null("Ui/ArenaTools")
	if tools != null:
		(tools as Control).visible = false
	arena.set("_tutorial_step", 4)
	arena.set("_onboarding", false)
	arena.set("_capture_progress_frozen", true)
	(arena.get_node("Ui/Hud") as Control).call("set_banner_suppressed", true)
	var voice: Node = arena.get("_voice_panel") as Node
	if voice != null and is_instance_valid(voice):
		voice.call("clear")
	TranslationServer.set_locale("ko")


## Live-attack evidence, per weapon family. Slash sprite, volley nodes in flight,
## orbit pulse and rig flashes all come from production attack calls only.
func _live_effect_visible(arena: Node2D, player: Node2D, hero_id: String) -> bool:
	return _live_primary_effect_visible(arena, player, hero_id) \
		or _live_sidearm_effect_visible(arena, player, hero_id)


## The primary's own moment on screen: melee primaries swing the slash and ring
## the orbit, ranged primaries fly their volley, and the rig flash reads primary
## (never a yielded sidearm cue).
func _live_primary_effect_visible(arena: Node2D, player: Node2D, hero_id: String) -> bool:
	var melee_primary: bool = hero_id in ["warden", "dancer", "eclipse"]
	if melee_primary:
		var slash: Sprite2D = player.get_node("Slash") as Sprite2D
		if slash.visible:
			return true
	var rig: Node = player.get_node("WeaponRig") as Node
	if rig != null and not str(rig.get("_kind")).is_empty() \
			and not bool(rig.get("_kind_sidearm")):
		return true
	if hero_id == "eclipse":
		var scythe: Node = player.get_node("ScytheOrbit") as Node
		if scythe != null and float(scythe.get("_pulse_age")) < 0.5:
			return true
	if not melee_primary:
		for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
			if is_instance_valid(projectile) and arena.is_ancestor_of(projectile):
				return true
	return false


## Backup-slot evidence: a sidearm bash swings the slash on a ranged hero, and
## moon-wheel bolts fly on a melee hero.
func _live_sidearm_effect_visible(arena: Node2D, player: Node2D, hero_id: String) -> bool:
	var melee_primary: bool = hero_id in ["warden", "dancer", "eclipse"]
	if not melee_primary:
		var slash: Sprite2D = player.get_node("Slash") as Sprite2D
		if slash.visible:
			return true
	else:
		for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
			if is_instance_valid(projectile) and arena.is_ancestor_of(projectile):
				return true
	return false


## The arena's own beacon panel once per locale in both core states, over a live
## settled arena so the background is the real night, not a void. A real beacon
## carries the choice context, and every capture waits for a finished draw.
func _stage_beacons(out: String) -> void:
	var request: FileAccess = FileAccess.open(REQUEST_PATH, FileAccess.WRITE)
	request.store_string("res://resources/heroes/warden.tres\n")
	request.close()
	var arena: Node2D = ARENA.instantiate() as Node2D
	get_tree().root.add_child.call_deferred(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = arena
	_settle_arena(arena)
	arena.call("debug_shield")
	var panel: Control = arena.get_node("Ui/RunChoice") as Control
	var beacon: Node2D = (arena.get("_beacons") as Array)[0] as Node2D
	_expect_true(panel != null, "beacon panel rides the live arena")
	_expect_true(beacon != null, "beacon choice carries a real beacon")
	var original_locale: String = TranslationServer.get_locale()
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		for core_available in [true, false]:
			panel.call("open_beacon", beacon, 2, core_available)
			# Photograph only the settled, armed choice: the fade-in runs
			# 0.18s and the buttons arm after pointers release, so two bare
			# frames would catch a ghost.
			var state: String = "core" if core_available else "max"
			var settled: bool = false
			for wait in 40:
				await get_tree().create_timer(0.05, true).timeout
				if panel.modulate.a >= 0.999 \
						and bool(panel.get("_choice_armed")):
					settled = true
					break
			_expect_true(settled,
				"%s beacon %s fade settled and armed" % [locale, state])
			_expect_true(panel.modulate.a >= 0.999,
				"%s beacon %s alpha shot-ready" % [locale, state])
			var right: Label = panel.get_node(
				"Center/Frame/Content/Rows/Choices/Right/Copy/Rows/Description"
			) as Label
			_expect_true(right != null and not right.text.is_empty(),
				"%s beacon copy settled" % locale)
			if not _validate_only and right != null:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(
					"%s/%s_beacon_%s_%s.png" % [out, _tag, locale,
						"core" if core_available else "max"])
			panel.call("close_without_choice")
			await get_tree().process_frame
	TranslationServer.set_locale(original_locale)
	print("saved beacon locales" if not _validate_only else "beacon locales ok")
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


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


## Live staged marks in one arena: valid, unqueued spirits under its root.
func _live_mark_count(arena: Node2D) -> int:
	var total: int = 0
	for spirit in get_tree().get_nodes_in_group("spirits"):
		if is_instance_valid(spirit) and arena.is_ancestor_of(spirit) \
				and not spirit.is_queued_for_deletion():
			total += 1
	return total


## Dominant-axis side match, the same rule `Player.face_toward` walks by: an
## aim counts for a side when it runs furthest along that side's axis in the
## side's sign. Twin alternation and fan lanes stay inside; a retarget never.
func _aim_matches_side(aim: Vector2, side: String) -> bool:
	if aim.length() < 0.01:
		return false
	var want: Vector2 = SIDES[side] as Vector2
	if absf(want.x) > 0.0:
		return absf(aim.x) >= absf(aim.y) and signf(aim.x) == signf(want.x)
	return absf(aim.y) >= absf(aim.x) and signf(aim.y) == signf(want.y)
