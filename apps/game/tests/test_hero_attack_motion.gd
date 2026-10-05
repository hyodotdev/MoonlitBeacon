extends SceneTree

## Six-hero physical attack motion: painted arms carry the weapon, no duplicates.
##
## A sword must visibly travel through its cut, carried by a moving hand and a
## readable body action. This drives live Players through their production
## attack calls and proves the physical path, not the flash: the painted
## shoulder stays attached while the elbow bends and the wrist sweeps, the
## grip never leaves the hand, the baked idle arm never doubles the posed one,
## melee blades sweep a measured arc (Warden ≥90, each Dancer fang ≥60,
## Eclipse ≥120) and settle back exactly, guns kick back with their hands and
## return exactly, the blade crosses the contact aim at t=0, muzzles meet
## their spawns within half a pixel, primaries face their target while
## locomotion continues (even when the physics countdown lapses first),
## same-facing and first-turn entries keep the full frame-plus-progress at
## nonzero fractions with exact recovery, sidearms never touch the primary
## pose, and pause,
## retrigger, dash, result, hero switch, and clear never stick an offset.
## Freezing only the arm rig fails the articulation checks while the weapon
## and cues still move.
##
## Direct-callable, no scene:
##     pnpm godot:isolated --timeout 150 --script res://tests/test_hero_attack_motion.gd

const PLAYER_SCENE: PackedScene = preload("res://scenes/actors/player.tscn")
const HERO_IDS: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage",
]
const DIAGONAL: float = 0.70710678
const AIMS: Array[Vector2] = [
	Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
	Vector2(DIAGONAL, DIAGONAL), Vector2(-DIAGONAL, DIAGONAL),
	Vector2(DIAGONAL, -DIAGONAL), Vector2(-DIAGONAL, -DIAGONAL),
]
const CARDINAL_AIMS: Array[Vector2] = [
	Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
]
## Independent motion floors. Must match `WeaponRig` constants, never read them.
const SWING_BASE: Dictionary = {"warden": 0.24, "dancer": 0.18, "eclipse": 0.28}
const SHOT_BASE: Dictionary = {"keeper": 0.16, "knight": 0.18, "sage": 0.14}
const SWING_MINIMUM: Dictionary = {
	"warden": 90.0, "dancer": 60.0, "eclipse": 120.0,
}
const SHOT_SLIDE: Dictionary = {"keeper": 4.0, "knight": 7.0, "sage": 2.5}
const MELEE_PRIMARY: Array[String] = ["warden", "dancer", "eclipse"]
## Independent articulation floors: elbow flexion through the cut in degrees,
## wrist world travel in px. Up-aim guns bow instead of folding, so their
## elbow barely bends; their wrist still travels with the torso. Melee cuts
## alternate forehand/backhand wrist paths; the floor covers the backhand,
## whose arc runs against the torso lunge.
const ELBOW_FLEX_MINIMUM: Dictionary = {
	"warden": 20.0, "dancer": 15.0, "eclipse": 20.0,
	"keeper": 20.0, "knight": 20.0, "sage": 20.0,
}
const WRIST_TRAVEL_MINIMUM: Dictionary = {
	"warden": 1.2, "dancer": 1.2, "eclipse": 1.2,
	"keeper": 2.0, "knight": 3.0, "sage": 1.2,
}

var _failed: int = 0
var _checked: int = 0
var _samples: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_spans_bounded()
	await _test_melee_arcs()
	await _test_ranged_kicks()
	await _test_contact_muzzle()
	await _test_hand_grip()
	await _test_arm_articulation()
	await _test_split_swap()
	await _test_facing_hold()
	await _test_facing_boundary()
	await _test_distinction()
	await _test_sidearm_priority()
	await _test_rapid_retrigger()
	await _test_pause()
	await _test_cleanup()
	await _test_attack_gait()
	await _test_attack_gait_fraction()
	await _test_attack_gait_first_turn()
	await _test_no_vfx_motion()
	await _test_eclipse_tie()
	await _test_arm_freeze_control()
	_expect_true(_samples >= 48,
		"at least 48 primary action/aim samples (%d)" % _samples)
	_finish()


## Spans never outrun the attack interval, even at the relic-haste floors.
func _test_spans_bounded() -> void:
	for hero_id in HERO_IDS:
		var profile: Hero.AttackProfile = HeroWeapons.profile_of(hero_id)
		if hero_id in MELEE_PRIMARY:
			var melee: Dictionary = HeroWeapons.melee_spec(profile)
			var base_cd: float = float(melee["cooldown"])
			_expect_equal(WeaponRig.attack_span_for(profile, base_cd),
				float(SWING_BASE[hero_id]),
				hero_id + " full cut at its base cadence")
			_expect_true(absf(WeaponRig.attack_span_for(profile, 0.11) - 0.099)
				< 0.000001,
				hero_id + " cut shrinks under the 0.11s melee floor")
			_expect_true(WeaponRig.attack_span_for(profile, 0.11) < 0.11,
				hero_id + " shrunk cut settles before the next swing")
		else:
			_expect_equal(WeaponRig.attack_span_for(profile, -1.0),
				float(SHOT_BASE[hero_id]),
				hero_id + " discharge base span")
			_expect_true(float(SHOT_BASE[hero_id]) <= 0.306,
				hero_id + " discharge fits the 0.34s volley floor")
			_expect_true(absf(WeaponRig.attack_span_for(profile, 0.15) - 0.135)
				< 0.000001,
				hero_id + " discharge shrinks with a known interval")


## Melee blades sweep their minimum arc, cross the contact aim exactly at t=0,
## and settle exactly. Dancer attacks twice per aim: one fang, then the other.
func _test_melee_arcs() -> void:
	for hero_id in MELEE_PRIMARY:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		var cuts: int = 2 if hero_id == "dancer" else 1
		for aim in AIMS:
			for cut in cuts:
				player.set("_attack_cooldown", 0.0)
				player.attack(aim)
				_expect_true(rig.attack_live(),
					"%s %s cut starts" % [hero_id, str(aim)])
				_samples += 1
				var contact: float = _blade_error(rig, aim)
				_expect_true(contact < 0.001,
					"%s %s blade crosses contact at t=0 (%.4f)" % [
						hero_id, str(aim), contact])
				if hero_id == "dancer":
					_expect_equal(rig.attack_variant(), cut,
						"%s %s alternates fangs" % [hero_id, str(aim)])
				var arc: float = _sample_arc(player, rig)
				_expect_true(arc >= float(SWING_MINIMUM[hero_id]),
					"%s %s cut sweeps %.1f (min %s)" % [
						hero_id, str(aim), arc,
						str(SWING_MINIMUM[hero_id])])
				_expect_settled(player, rig,
					"%s %s cut" % [hero_id, str(aim)])
			if hero_id == "dancer":
				_expect_true(true, "dancer %s both fangs cut" % str(aim))
		player.queue_free()
		await process_frame
	# A hasted cut still sweeps full and settles inside its shrunken span.
	var hasted: Player = _add_player()
	_apply_hero(hasted, "dancer")
	hasted.attack_cooldown_time = 0.11
	var hasted_rig: WeaponRig = hasted.get_node("WeaponRig") as WeaponRig
	hasted.set("_attack_cooldown", 0.0)
	hasted.attack(Vector2.RIGHT)
	_expect_true(absf(hasted_rig.attack_span() - 0.099) < 0.000001,
		"hasted cut spans 0.099s")
	_samples += 1
	var hasted_arc: float = _sample_arc(hasted, hasted_rig, 1.0 / 240.0)
	_expect_true(hasted_arc >= 60.0,
		"hasted cut still sweeps %.1f" % hasted_arc)
	_expect_settled(hasted, hasted_rig, "hasted cut")
	hasted.queue_free()
	await process_frame


## Guns kick their own distance back, pitch their own way, and return exactly.
## The painted wrist carries the kick in world space; up-aims bow outward
## with the torso instead of folding past the elbow.
func _test_ranged_kicks() -> void:
	for hero_id in ["keeper", "knight", "sage"]:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		var arm: ArmRig = player.get_node("ArmMain") as ArmRig
		for aim in AIMS:
			player.play_moonlight_cast(aim, 1)
			_expect_true(rig.attack_live(),
				"%s %s discharge starts" % [hero_id, str(aim)])
			_samples += 1
			var up_aim: bool = str(player.get("_attack_facing")) == "up"
			var start: Vector2 = _wrist_world(player, arm)
			var peak_slide: float = 0.0
			var peak_pitch: float = 0.0
			var wrist_travel: float = 0.0
			var span: float = rig.attack_span()
			var age: float = 0.0
			var dt: float = 1.0 / 240.0
			while age < span + dt:
				if not rig.attack_live():
					break
				peak_slide = maxf(peak_slide, rig.attack_shift_now().length())
				var pitch: float = rig.gun_pitch_now()
				if absf(pitch) > absf(peak_pitch):
					peak_pitch = pitch
				wrist_travel = maxf(wrist_travel,
					start.distance_to(_wrist_world(player, arm)))
				_step(player, dt)
				age += dt
			var want_slide: float = float(SHOT_SLIDE[hero_id])
			_expect_true(absf(peak_slide - want_slide) < 0.3,
				"%s %s kicks %.2fpx (seat %.1f)" % [
					hero_id, str(aim), peak_slide, want_slide])
			_expect_true(absf(peak_pitch) > 0.05,
				"%s %s muzzle pitches (%.3f)" % [
					hero_id, str(aim), peak_pitch])
			if hero_id == "sage":
				_expect_true(peak_pitch > 0.0,
					"sage presses down while keeper/knight rise")
			else:
				_expect_true(peak_pitch < 0.0,
					"%s muzzle rises" % hero_id)
			if up_aim:
				_expect_true(wrist_travel > 1.0,
					"%s %s up-aim wrist bows out (%.2f)" % [
						hero_id, str(aim), wrist_travel])
			else:
				_expect_true(wrist_travel > want_slide * 0.6,
					"%s %s wrist carries the kick (%.2f)" % [
						hero_id, str(aim), wrist_travel])
			_expect_settled(player, rig,
				"%s %s discharge" % [hero_id, str(aim)])
		player.queue_free()
		await process_frame


## At the combat instant the blade sits on the contact direction and the painted
## muzzle sits on the real projectile spawn, in all eight aims.
func _test_contact_muzzle() -> void:
	for hero_id in HERO_IDS:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		for aim in AIMS:
			_primary_attack(player, hero_id, aim)
			if hero_id in MELEE_PRIMARY:
				var error: float = _blade_error(rig, aim)
				_expect_true(error < 0.001,
					"%s %s contact blade exact (%.4f)" % [
						hero_id, str(aim), error])
			else:
				var drawn: Vector2 = rig.to_global(rig.drawn_tip_now())
				var muzzle: Vector2 = player.muzzle_origin(aim)
				_expect_true(drawn.distance_to(muzzle) < 0.5,
					"%s %s muzzle meets its spawn (%.3f)" % [
						hero_id, str(aim), drawn.distance_to(muzzle)])
			_finish_attack(player, rig)
		player.queue_free()
		await process_frame


## The painted hand grips the weapon: the drawn grip sits on the solved wrist
## in world space through the whole action, within a twentieth of a pixel.
func _test_hand_grip() -> void:
	for hero_id in HERO_IDS:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		var arm: ArmRig = player.get_node("ArmMain") as ArmRig
		for aim in AIMS:
			_primary_attack(player, hero_id, aim)
			var gap: float = _grip_gap(player, rig, arm)
			_expect_true(gap < 0.05,
				"%s %s hand seats its grip (%.4f)" % [
					hero_id, str(aim), gap])
			var rest_wrist: Vector2 = _wrist_world(player, arm)
			var travel: float = 0.0
			var span: float = rig.attack_span()
			var age: float = 0.0
			var dt: float = 1.0 / 120.0
			while age < span + dt:
				if not rig.attack_live():
					break
				_expect_true(_grip_gap(player, rig, arm) < 0.05,
					"%s %s hand never leaves its grip" % [hero_id, str(aim)])
				travel = maxf(travel,
					rest_wrist.distance_to(_wrist_world(player, arm)))
				_step(player, dt)
				age += dt
			_expect_true(travel > 1.0,
				"%s %s hand travels %.2fpx" % [hero_id, str(aim), travel])
			_finish_attack(player, rig)
			_expect_true(
				_wrist_world(player, arm).distance_to(rest_wrist) < 0.01,
				"%s %s hand rests exactly" % [hero_id, str(aim)])
		player.queue_free()
		await process_frame


## The arm articulates: the shoulder rides the torso it is attached to, the
## elbow bends through the cut, the wrist sweeps its floor. The reach clamp
## stays a safety net, never a travel source. Dancer's brace holds still
## while the cutter sweeps; Eclipse's mirror sweeps with it. Drawn sprites
## carry the same motion at the cell scale, with painted endpoints meeting
## the joints and the grip.
func _test_arm_articulation() -> void:
	for hero_id in HERO_IDS:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		var arm: ArmRig = player.get_node("ArmMain") as ArmRig
		for aim in AIMS:
			_primary_attack(player, hero_id, aim)
			# The off chain joins on first need; fetch it per aim so a
			# front-view attack later in the loop still observes it.
			var off: ArmRig = player.get_node_or_null("ArmOff") as ArmRig
			var facing: String = str(player.get("_attack_facing"))
			var up_gun: bool = facing == "up" \
				and not hero_id in MELEE_PRIMARY
			var rest_angle: float = _elbow_interior(arm)
			var rest_shoulder: Vector2 = arm.shoulder_cell()
			var torso: Node2D = player.get_node("AttackTorso") as Node2D
			var flex: float = 0.0
			var travel: float = 0.0
			var drawn_travel: float = 0.0
			var off_travel: float = 0.0
			var slack: float = 0.0
			var attach_drift: float = 0.0
			var elbow_gap: float = 0.0
			var wrist_gap: float = 0.0
			var shoulder_slid: bool = false
			var scale_wrong: bool = false
			var start: Vector2 = _wrist_world(player, arm)
			var drawn_start: Vector2 = arm.painted_wrist_world()
			var shoulder_start: Vector2 = _shoulder_world(player, arm)
			var torso_start: Vector2 = torso.position
			var off_start: Vector2 = _wrist_world(player, off) \
				if off != null else Vector2.ZERO
			var want_scale: Vector2 = Vector2.ONE * float(
				player.get("_hero_scale"))
			var span: float = rig.attack_span()
			var age: float = 0.0
			var dt: float = 1.0 / 240.0
			while age < span + dt:
				if not rig.attack_live():
					break
				var progress: float = rig.attack_progress()
				flex = maxf(flex, rest_angle - _elbow_interior(arm))
				travel = maxf(travel,
					start.distance_to(_wrist_world(player, arm)))
				drawn_travel = maxf(drawn_travel,
					drawn_start.distance_to(arm.painted_wrist_world()))
				if off != null and off.visible:
					off_travel = maxf(off_travel,
						off_start.distance_to(_wrist_world(player, off)))
				var target: Vector2 = player.call(
					"_main_wrist_target", maxf(progress, 0.0))
				var lengths: Vector2 = arm.segment_lengths()
				slack = maxf(slack, target.distance_to(ArmRig.clamp_to_reach(
					arm.shoulder_cell(), target, lengths.x, lengths.y)))
				shoulder_slid = shoulder_slid \
					or arm.shoulder_cell() != rest_shoulder
				attach_drift = maxf(attach_drift,
					(_shoulder_world(player, arm) - shoulder_start)
						.distance_to(torso.position - torso_start))
				var upper: Sprite2D = arm.upper_sprite()
				var fore: Sprite2D = arm.fore_sprite()
				scale_wrong = scale_wrong \
					or upper.scale != want_scale or fore.scale != want_scale
				elbow_gap = maxf(elbow_gap,
					arm.painted_elbow_world().distance_to(
						fore.global_position))
				wrist_gap = maxf(wrist_gap,
					arm.painted_wrist_world().distance_to(
						_grip_world(player, rig)))
				_step(player, dt)
				age += dt
			_expect_false(shoulder_slid,
				"%s %s shoulder never slides in torso space" % [
					hero_id, str(aim)])
			_expect_true(attach_drift < 0.01,
				"%s %s shoulder rides the torso (%.4f)" % [
					hero_id, str(aim), attach_drift])
			_expect_false(scale_wrong,
				"%s %s arm patches draw at the cell scale" % [
					hero_id, str(aim)])
			_expect_true(elbow_gap < 0.5,
				"%s %s painted elbow meets its joint (%.3f)" % [
					hero_id, str(aim), elbow_gap])
			_expect_true(wrist_gap < 0.5,
				"%s %s painted wrist meets its grip (%.3f)" % [
					hero_id, str(aim), wrist_gap])
			if up_gun:
				_expect_true(travel > 1.0,
					"%s %s up-aim wrist travels %.2f" % [
						hero_id, str(aim), travel])
				_expect_true(drawn_travel > 1.0,
					"%s %s drawn wrist travels %.2f" % [
						hero_id, str(aim), drawn_travel])
			else:
				_expect_true(flex >= float(ELBOW_FLEX_MINIMUM[hero_id]),
					"%s %s elbow flexes %.1f (min %s)" % [
						hero_id, str(aim), flex,
						str(ELBOW_FLEX_MINIMUM[hero_id])])
				_expect_true(travel >= float(WRIST_TRAVEL_MINIMUM[hero_id]),
					"%s %s wrist travels %.2f (min %s)" % [
						hero_id, str(aim), travel,
						str(WRIST_TRAVEL_MINIMUM[hero_id])])
				_expect_true(
					drawn_travel >= float(WRIST_TRAVEL_MINIMUM[hero_id]),
					"%s %s drawn wrist travels %.2f (min %s)" % [
						hero_id, str(aim), drawn_travel,
						str(WRIST_TRAVEL_MINIMUM[hero_id])])
			var slack_cap: float = 4.0 \
				if not hero_id in MELEE_PRIMARY else 0.1
			_expect_true(slack <= slack_cap,
				"%s %s reach clamp idles (%.2f cells)" % [
					hero_id, str(aim), slack])
			if hero_id == "dancer" and off != null and off.visible:
				_expect_true(off_travel < 0.3,
					"dancer %s brace holds still (%.2f)" % [
						str(aim), off_travel])
			if hero_id == "eclipse" and off != null and off.visible:
				_expect_true(off_travel > 1.5,
					"eclipse %s mirror sweeps (%.2f)" % [str(aim), off_travel])
			_finish_attack(player, rig)
		player.queue_free()
		await process_frame


## Exactly one body shows at a time: at rest the baked sprite plays and the
## split hides; mid-attack the sprite steps hidden while the armless torso,
## live legs, and textured arm chains show. No third arm, no bare patch.
func _test_split_swap() -> void:
	for hero_id in HERO_IDS:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		for aim in CARDINAL_AIMS:
			_expect_split_hidden(player, "%s %s rest" % [hero_id, str(aim)])
			_primary_attack(player, hero_id, aim)
			_expect_split_shown(player, hero_id, "%s %s attack" % [
				hero_id, str(aim)])
			_finish_attack(player, rig)
			_step(player, 1.0 / 120.0)
			_expect_split_hidden(player, "%s %s settled" % [
				hero_id, str(aim)])
		player.queue_free()
		await process_frame


## The baked sprite plays and every split node hides with no live motion.
func _expect_split_hidden(player: Player, label: String) -> void:
	var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	_expect_true(sprite.visible, label + " baked sprite shows")
	_expect_true(sprite.is_playing(), label + " baked sprite plays")
	_expect_false(bool(player.get("_split_shown")), label + " split parks")
	for node_name in ["AttackLegs", "AttackTorso", "ArmMain"]:
		_expect_false((player.get_node(node_name) as Node2D).visible,
			label + " " + node_name + " hides")
	# The off chain and nub join on first need; absent hides vacuously.
	for node_name in ["ArmOff", "AttackNub"]:
		var extra: Node2D = player.get_node_or_null(node_name) as Node2D
		_expect_true(extra == null or not extra.visible,
			label + " " + node_name + " hides")


## The sprite steps hidden while the textured split shows. Dancer braces a
## second chain on front views, Eclipse mirrors one; Eclipse stacks its nub
## in profile. Every split sprite keeps the baked light.
func _expect_split_shown(
	player: Player, hero_id: String, label: String
) -> void:
	var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	_expect_false(sprite.visible, label + " baked sprite hides")
	_expect_false(sprite.is_playing(), label + " baked clock parks hidden")
	_expect_true(bool(player.get("_split_shown")), label + " split shows")
	var legs: Sprite2D = player.get_node("AttackLegs") as Sprite2D
	var torso: Sprite2D = player.get_node("AttackTorso") as Sprite2D
	var main: ArmRig = player.get_node("ArmMain") as ArmRig
	_expect_true(legs.visible, label + " legs show")
	_expect_true(legs.texture != null, label + " legs draw a frame")
	_expect_true(torso.visible, label + " torso shows")
	_expect_true(torso.texture != null, label + " torso wears paint")
	_expect_true(main.visible, label + " main arm shows")
	_expect_true(main.upper_texture() != null and main.fore_texture() != null,
		label + " main arm wears paint")
	_expect_equal(legs.self_modulate, Player.HERO_READABILITY_TINT,
		label + " legs keep the baked light")
	_expect_equal(torso.self_modulate, Player.HERO_READABILITY_TINT,
		label + " torso keeps the baked light")
	_expect_equal(legs.material, sprite.material,
		label + " legs keep the polish")
	_expect_equal(torso.material, sprite.material,
		label + " torso keeps the polish")
	_expect_equal(main.upper_sprite().self_modulate,
		Player.HERO_READABILITY_TINT,
		label + " arm keeps the baked light")
	_expect_equal(main.upper_sprite().material, sprite.material,
		label + " arm keeps the polish")
	_expect_equal(main.fore_sprite().self_modulate,
		Player.HERO_READABILITY_TINT,
		label + " fore keeps the baked light")
	var facing: String = str(player.get("_attack_facing"))
	var front: bool = facing == "down" or facing == "up"
	var off: ArmRig = player.get_node_or_null("ArmOff") as ArmRig
	var nub: Sprite2D = player.get_node_or_null("AttackNub") as Sprite2D
	if hero_id == "dancer":
		if front:
			_expect_true(off != null and off.visible,
				label + " brace arm shows")
			_expect_true(off != null and off.upper_texture() != null,
				label + " brace arm wears paint")
		else:
			_expect_true(off == null or not off.visible,
				label + " no spare arm")
		_expect_true(nub == null or not nub.visible, label + " no nub")
	elif hero_id == "eclipse":
		if front:
			_expect_true(off != null and off.visible,
				label + " mirror arm shows")
			_expect_true(nub == null or not nub.visible,
				label + " no nub with a mirror")
		else:
			_expect_true(off == null or not off.visible,
				label + " no spare arm")
			_expect_true(nub != null and nub.visible,
				label + " off hand stacks")
			_expect_true(nub != null and nub.texture != null,
				label + " nub wears paint")
			if nub != null:
				_expect_equal(nub.self_modulate, Player.HERO_READABILITY_TINT,
					label + " nub keeps the baked light")
	else:
		_expect_true(off == null or not off.visible,
			label + " no spare arm")
		_expect_true(nub == null or not nub.visible, label + " no nub")


## Primaries face their target for the whole span while locomotion continues:
## firing right while walking left, and the inverse, plus diagonals. No
## `face_toward` pre-call here — the production attack faces, the hold keeps.
func _test_facing_hold() -> void:
	var pairs: Array = [
		[Vector2.LEFT, Vector2.RIGHT], [Vector2.RIGHT, Vector2.LEFT],
		[Vector2.UP, Vector2.DOWN], [Vector2.DOWN, Vector2.UP],
		[Vector2(-DIAGONAL, DIAGONAL), Vector2(DIAGONAL, -DIAGONAL)],
		[Vector2(DIAGONAL, DIAGONAL), Vector2(-DIAGONAL, -DIAGONAL)],
	]
	for hero_id in HERO_IDS:
		var player: Player = _add_player()
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.set_bounds(Rect2(Vector2.ZERO, Vector2(2000, 2000)))
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		for pair in pairs:
			var move: Vector2 = pair[0]
			var target: Vector2 = pair[1]
			player.set_move_input(move)
			for tick in 3:
				await physics_frame
			player.set("_attack_cooldown", 0.0)
			_primary_attack(player, hero_id, target)
			var want: int = _facing_int(target)
			_expect_equal(int(player.facing), want,
				"%s %s attack faces its target" % [hero_id, str(target)])
			var from: Vector2 = player.position
			var held: int = 0
			var slipped: int = 0
			for tick in 60:
				await physics_frame
				if not rig.attack_live():
					break
				held += 1
				if int(player.facing) != want:
					slipped += 1
			_expect_true(held >= 2,
				"%s %s hold outlasts a tick (%d)" % [
					hero_id, str(target), held])
			_expect_equal(slipped, 0,
				"%s %s hold keeps facing while moving" % [
					hero_id, str(target)])
			_expect_true(
				(player.position - from).dot(move) > 2.0,
				"%s locomotion continues under fire" % hero_id)
			await physics_frame
			await physics_frame
			_expect_equal(int(player.facing), _facing_int(move),
				"%s movement re-faces after the span" % hero_id)
			_expect_true(float(player.get("_face_hold")) <= 0.0,
				"%s hold lapses with the span" % hero_id)
		player.queue_free()
		await process_frame


## Exact facing boundary: the physics countdown and the rig clock tick
## separately, so the countdown can lapse while the rig is still live. One
## movement tick at that boundary must keep the target facing while the body
## keeps moving and stepping; after cleanup, movement re-faces promptly.
func _test_facing_boundary() -> void:
	for hero_id in HERO_IDS:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		var sprite: AnimatedSprite2D = player.get_node(
			"Sprite") as AnimatedSprite2D
		player.call("set_walking", true)
		player.set_move_input(Vector2.LEFT)
		_primary_attack(player, hero_id, Vector2.RIGHT)
		_expect_true(rig.attack_live(),
			"%s boundary rig starts live" % hero_id)
		_expect_equal(int(player.facing), int(Player.Facing.RIGHT),
			"%s boundary attack faces its target" % hero_id)
		var from: float = player.position.x
		var gait_before: float = float(player.get("_gait_time"))
		player.set("_face_hold", 0.0)
		player.call("_physics_process", 1.0 / 60.0)
		_expect_equal(int(player.facing), int(Player.Facing.RIGHT),
			"%s exhausted countdown keeps the target facing" % hero_id)
		_expect_true(rig.attack_live(),
			"%s rig still live past the countdown" % hero_id)
		_expect_equal(rig.attack_aim(), Vector2.RIGHT,
			"%s rig keeps its aim past the countdown" % hero_id)
		_expect_true(player.position.x < from,
			"%s locomotion continues under the hold" % hero_id)
		_expect_true(float(player.get("_gait_time")) > gait_before,
			"%s gait continues under the hold" % hero_id)
		_expect_false(sprite.is_playing(),
			"%s hidden clock parks past the countdown" % hero_id)
		_finish_attack(player, rig)
		player.call("_physics_process", 1.0 / 60.0)
		_expect_equal(int(player.facing), _facing_int(Vector2.LEFT),
			"%s movement re-faces promptly after cleanup" % hero_id)
		_expect_true(float(player.get("_face_hold")) <= 0.0,
			"%s hold clears with the rig" % hero_id)
		player.queue_free()
		await process_frame


## Six heroes read as six actions: every pair of blade-plus-wrist motion
## signatures differs, including the Dancer's second fang.
func _test_distinction() -> void:
	var signatures: Dictionary = {}
	for hero_id in HERO_IDS:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		_primary_attack(player, hero_id, Vector2.RIGHT)
		signatures[hero_id] = _signature(player, rig)
		# The Dancer's second fang is its own action, not a replay.
		if hero_id == "dancer":
			_primary_attack(player, hero_id, Vector2.RIGHT)
			signatures["dancer_second"] = _signature(player, rig)
		player.queue_free()
		await process_frame
	var names: Array = signatures.keys()
	for first in names.size():
		for second in range(first + 1, names.size()):
			var gap: float = _signature_gap(
				signatures[names[first]], signatures[names[second]])
			_expect_true(gap > 0.15,
				"%s vs %s actions differ (%.2f)" % [
					str(names[first]), str(names[second]), gap])


## A sidearm cue never steals or restarts the held primary: not its aim, seat,
## facing, flash, motion, or arm pose — live or idle.
func _test_sidearm_priority() -> void:
	var warden: Player = _add_player()
	_apply_hero(warden, "warden")
	var rig: WeaponRig = warden.get_node("WeaponRig") as WeaponRig
	var arm: ArmRig = warden.get_node("ArmMain") as ArmRig
	warden.set("_attack_cooldown", 0.0)
	warden.attack(Vector2.RIGHT)
	_step(warden, 1.0 / 60.0)
	_step(warden, 1.0 / 60.0)
	var age: float = float(rig.get("_attack_age"))
	var seat: Vector2 = rig.position
	var wrist: Vector2 = arm.wrist_cell()
	warden.play_moonlight_cast(Vector2.UP, 1)
	_expect_equal(rig.aim(), Vector2.RIGHT,
		"sidearm spark never turns the live blade")
	_expect_equal(rig.get("_kind"), WeaponRig.CUT,
		"sidearm spark yields to the live cut")
	_expect_true(rig.attack_live(), "live cut survives the sidearm cue")
	_expect_equal(arm.wrist_cell(), wrist,
		"sidearm cue never re-poses the live arm")
	_expect_equal(rig.position, seat,
		"sidearm cue never moves the live blade")
	_step(warden, 1.0 / 60.0)
	_expect_true(absf(float(rig.get("_attack_age")) - age - 1.0 / 60.0) < 0.001,
		"live cut is never restarted by the sidearm cue")
	_expect_equal(int(warden.facing), int(Player.Facing.RIGHT),
		"sidearm cue never steals the live facing")
	_finish_attack(warden, rig)
	warden.play_moonlight_cast(Vector2.UP, 1)
	_expect_equal(rig.aim(), Vector2.RIGHT,
		"held blade keeps its aim past an idle sidearm cue")
	_expect_equal(rig.get("_kind"), WeaponRig.MUZZLE_SPARK,
		"idle sidearm cue still shows")
	_expect_true(not rig.attack_live(),
		"idle sidearm cue never starts a cut")
	_expect_false(bool(warden.get("_split_shown")),
		"idle sidearm cue never poses the arms")
	warden.queue_free()
	await process_frame
	var sage: Player = _add_player()
	_apply_hero(sage, "sage")
	var sage_rig: WeaponRig = sage.get_node("WeaponRig") as WeaponRig
	sage.play_moonlight_cast(Vector2.RIGHT, 1)
	_step(sage, 1.0 / 60.0)
	var sage_seat: Vector2 = sage_rig.position
	sage.set("_attack_cooldown", 0.0)
	sage.attack(Vector2.UP)
	_expect_equal(sage_rig.aim(), Vector2.RIGHT,
		"sidearm bash never turns the live rifle")
	_expect_equal(sage_rig.get("_kind"), WeaponRig.MUZZLE_RIFLE,
		"sidearm bash yields to the live rifle flash")
	_expect_true(sage_rig.attack_live(), "live kick survives the sidearm cue")
	_expect_equal(sage_rig.position, sage_seat,
		"sidearm bash never moves the live rifle")
	_expect_equal(int(sage.facing), int(Player.Facing.RIGHT),
		"sidearm bash never steals the live facing")
	_finish_attack(sage, sage_rig)
	sage.set("_attack_cooldown", 0.0)
	sage.attack(Vector2.UP)
	_expect_equal(sage_rig.aim(), Vector2.RIGHT,
		"held rifle keeps its aim past an idle sidearm bash")
	_expect_true(not sage_rig.attack_live(),
		"idle sidearm bash never starts a kick")
	sage.queue_free()
	await process_frame


## Rapid relic-rate attacks restart one timeline instead of stacking offsets.
func _test_rapid_retrigger() -> void:
	var player: Player = _add_player()
	_apply_hero(player, "dancer")
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	var variants: Array = []
	for cycle in 5:
		player.set("_attack_cooldown", 0.0)
		player.attack(Vector2.RIGHT)
		variants.append(rig.attack_variant())
		_expect_true(rig.attack_progress() < 0.05,
			"retrigger %d restarts its cut" % cycle)
		_expect_true(bool(player.get("_split_shown")),
			"retrigger %d keeps one pose" % cycle)
		_step(player, 1.0 / 60.0)
		_step(player, 1.0 / 60.0)
		_step(player, 1.0 / 60.0)
	_expect_equal(variants, [0, 1, 0, 1, 0],
		"rapid cuts keep alternating fangs")
	_finish_attack(player, rig)
	_expect_settled(player, rig, "rapid cuts")
	player.queue_free()
	await process_frame


## Pause freezes the cut, the torso, the weapon, and the stepping legs
## mid-motion; the baked sprite never drifts, and resume settles exactly.
func _test_pause() -> void:
	var player: Player = _add_player()
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.set_bounds(Rect2(Vector2.ZERO, Vector2(2000, 2000)))
	_apply_hero(player, "warden")
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	var torso: Node2D = player.get_node("AttackTorso") as Node2D
	var legs: Sprite2D = player.get_node("AttackLegs") as Sprite2D
	player.set("_attack_cooldown", 0.0)
	player.attack(Vector2.RIGHT)
	await process_frame
	await process_frame
	_expect_true(rig.attack_live(), "live cut runs unpaused")
	paused = true
	await process_frame
	var age: float = float(rig.get("_attack_age"))
	var pose: Vector2 = torso.position
	var seat: Vector2 = rig.position
	var rest := Vector2(0.0, float(player.get("_sprite_base_y")))
	var legs_region: Rect2 = (legs.texture as AtlasTexture).region
	for tick in 5:
		await process_frame
		_expect_equal(float(rig.get("_attack_age")), age,
			"paused cut never advances")
		_expect_equal(torso.position, pose, "paused torso never drifts")
		_expect_equal(rig.position, seat, "paused weapon never drifts")
		_expect_equal(sprite.position, rest, "paused sprite never drifts")
		_expect_equal((legs.texture as AtlasTexture).region, legs_region,
			"paused legs never drift")
	paused = false
	for tick in 120:
		await process_frame
		if not rig.attack_live():
			break
	_expect_true(not rig.attack_live(), "resumed cut finishes")
	await physics_frame
	await physics_frame
	_expect_settled(player, rig, "paused cut")
	player.queue_free()
	await process_frame


## Result, clear, hero switch, dash, and walking never stick an offset: the
## split hides, the sprite resumes its frame, the seat and hold reset.
func _test_cleanup() -> void:
	for hero_id in ["warden", "sage"]:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		# Result mid-cut clears everything; continue can attack again.
		_primary_attack(player, hero_id, Vector2.RIGHT)
		_step(player, 1.0 / 60.0)
		_step(player, 1.0 / 60.0)
		_expect_true(rig.attack_live(),
			"%s cut is live before result" % hero_id)
		player.stop_for_result()
		_expect_true(not rig.attack_live(),
			"%s result drops the cut" % hero_id)
		_expect_equal(rig.get("_kind"), &"",
			"%s result drops the flash" % hero_id)
		_expect_settled(player, rig, "%s result" % hero_id)
		player.resume_after_continue(10.0)
		_primary_attack(player, hero_id, Vector2.LEFT)
		_expect_true(rig.attack_live(),
			"%s attacks again after continue" % hero_id)
		_finish_attack(player, rig)
		# Clear mid-cut settles through the pose.
		_primary_attack(player, hero_id, Vector2.UP)
		_step(player, 1.0 / 60.0)
		rig.clear()
		player.call("_update_attack_pose", 1.0 / 60.0)
		_expect_true(not rig.attack_live(),
			"%s clear drops the cut" % hero_id)
		_expect_settled(player, rig, "%s clear" % hero_id)
		# Hero switch mid-cut starts the new hero settled.
		_primary_attack(player, hero_id, Vector2.DOWN)
		_step(player, 1.0 / 60.0)
		var other: Hero = load("res://resources/heroes/%s.tres" % (
			"sage" if hero_id == "warden" else "warden")) as Hero
		_expect_true(player.apply_hero_visual(other),
			"%s hero switch applies mid-cut" % hero_id)
		_expect_true(not rig.attack_live(),
			"%s hero switch drops the cut" % hero_id)
		_expect_settled(player, rig, "%s hero switch" % hero_id)
		_expect_equal(float(rig.get("_swing_sign")), 1.0,
			"%s hero switch resets the cut sequence" % hero_id)
		# Dash mid-cut keeps the target facing, then settles clean.
		_primary_attack(player,
			"sage" if hero_id == "warden" else "warden", Vector2.RIGHT)
		_expect_equal(int(player.facing), int(Player.Facing.RIGHT),
			"%s cut faces its target" % hero_id)
		_expect_true(player.dash(Vector2.LEFT),
			"%s dashes mid-cut" % hero_id)
		_expect_equal(int(player.facing), int(Player.Facing.RIGHT),
			"%s dash keeps the target facing" % hero_id)
		_finish_attack(player, rig)
		_expect_settled(player, rig, "%s dash" % hero_id)
		player.queue_free()
		await process_frame
	# Walking steps through the cut: the hidden sprite keeps its gait and the
	# drawn legs mirror it, then the restore resumes the live frame.
	var walker: Player = _add_player()
	_apply_hero(walker, "warden")
	var walker_rig: WeaponRig = walker.get_node("WeaponRig") as WeaponRig
	var sprite: AnimatedSprite2D = walker.get_node("Sprite") as AnimatedSprite2D
	walker.face_toward(Vector2.RIGHT)
	walker.set_walking(true)
	_expect_equal(sprite.animation, &"walk_right", "walker strides out")
	sprite.frame = 2
	walker.set("_attack_cooldown", 0.0)
	walker.attack(Vector2.RIGHT)
	_expect_equal(sprite.animation, &"walk_right",
		"cut keeps the walk")
	_expect_equal(sprite.frame, 2, "cut starts on the stride frame")
	_expect_false(sprite.is_playing(), "hidden clock parks through the cut")
	var legs: Sprite2D = walker.get_node("AttackLegs") as Sprite2D
	var seen: Dictionary = {}
	var span: float = walker_rig.attack_span()
	var age: float = 0.0
	while age < span:
		var atlas: AtlasTexture = legs.texture as AtlasTexture
		seen[int(atlas.region.position.y)] = true
		_step(walker, 1.0 / 120.0)
		age += 1.0 / 120.0
	_expect_true(seen.size() >= 2,
		"walking cut steps its legs (%d frames)" % seen.size())
	_finish_attack(walker, walker_rig)
	_step(walker, 1.0 / 120.0)
	_expect_equal(sprite.animation, &"walk_right",
		"walk resumes after the cut")
	_expect_true(sprite.is_playing(), "walk plays on")
	walker.set_walking(false)
	_expect_equal(sprite.animation, &"idle_right", "walker settles to idle")
	_expect_settled(walker, walker_rig, "walking cut")
	walker.queue_free()
	await process_frame


## Attacks keep the real gait: walking attacks step the drawn legs through
## distinct walk frames (thighs, knees, and boots together), opposite aims
## hold facing while stepping, and stationary attacks keep the idle sheet
## with planted feet. A dash fired mid-attack keeps stepping; a walk
## stop/start mid-attack switches sheets without resetting the stride frame,
## running a second clock, or stepping backward. Facing-change retriggers
## and rapid repeats preserve the live frame and sub-frame progress, so
## repeated attacks keep a complete stride. Stepped by hand and on live
## SceneTree clocks.
func _test_attack_gait() -> void:
	for hero_id in HERO_IDS:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		var legs: Sprite2D = player.get_node("AttackLegs") as Sprite2D
		var hero: Hero = load(
			"res://resources/heroes/%s.tres" % hero_id) as Hero
		player.call("set_walking", true)
		_primary_attack(player, hero_id, Vector2.RIGHT)
		var seen: Dictionary = {}
		var span: float = rig.attack_span()
		var age: float = 0.0
		var dt: float = 1.0 / 120.0
		while age < span + dt:
			if not rig.attack_live():
				break
			var atlas: AtlasTexture = legs.texture as AtlasTexture
			seen[int(atlas.region.position.y)] = true
			_expect_equal(atlas.atlas, hero.walk_sheet,
				"%s walking legs draw the walk sheet" % hero_id)
			_step(player, dt)
			age += dt
		_expect_true(seen.size() >= 2,
			"%s walking attack steps its legs (%d)" % [
				hero_id, seen.size()])
		_expect_true(_legs_bands_move(hero, seen.keys()),
			"%s thighs, knees, and boots all step" % hero_id)
		_finish_attack(player, rig)
		player.call("set_walking", false)
		_primary_attack(player, hero_id, Vector2.RIGHT)
		var idle_atlas: AtlasTexture = (
			legs.texture as AtlasTexture)
		_expect_equal(idle_atlas.atlas, hero.idle_sheet,
			"%s stationary legs keep the idle sheet" % hero_id)
		_finish_attack(player, rig)
		player.queue_free()
		await process_frame
	var opposite: Player = _add_player()
	_apply_hero(opposite, "warden")
	var opposite_rig: WeaponRig = opposite.get_node("WeaponRig") as WeaponRig
	var opposite_legs: Sprite2D = opposite.get_node(
		"AttackLegs") as Sprite2D
	opposite.face_toward(Vector2.LEFT)
	opposite.call("set_walking", true)
	opposite.set("_attack_cooldown", 0.0)
	opposite.attack(Vector2.RIGHT)
	_expect_equal(int(opposite.facing), int(Player.Facing.RIGHT),
		"opposite attack holds its aim")
	var stepped: Dictionary = {}
	var opposite_span: float = opposite_rig.attack_span()
	var opposite_age: float = 0.0
	while opposite_age < opposite_span + 1.0 / 120.0:
		if not opposite_rig.attack_live():
			break
		var atlas: AtlasTexture = opposite_legs.texture as AtlasTexture
		stepped[int(atlas.region.position.y)] = true
		_step(opposite, 1.0 / 120.0)
		opposite_age += 1.0 / 120.0
	_expect_true(stepped.size() >= 2,
		"opposite attack steps while holding (%d)" % stepped.size())
	_finish_attack(opposite, opposite_rig)
	_expect_true(opposite.call("dash", Vector2.LEFT),
		"dash fires after the opposite cut")
	_finish_attack(opposite, opposite_rig)
	opposite.queue_free()
	await process_frame
	await _test_attack_gait_dash_during()
	await _test_attack_gait_walk_transitions()
	await _test_attack_gait_retrigger_stride()
	await _test_attack_gait_live()


## A dash fired mid-attack keeps the target facing and keeps stepping the
## drawn legs: controlled steps observe the leg frames through the dash.
func _test_attack_gait_dash_during() -> void:
	for hero_id in HERO_IDS:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		var sprite: AnimatedSprite2D = player.get_node(
			"Sprite") as AnimatedSprite2D
		var legs: Sprite2D = player.get_node("AttackLegs") as Sprite2D
		var hero: Hero = load(
			"res://resources/heroes/%s.tres" % hero_id) as Hero
		player.face_toward(Vector2.RIGHT)
		player.call("set_walking", true)
		sprite.frame = 2
		_primary_attack(player, hero_id, Vector2.RIGHT)
		for tick in 3:
			_step(player, 1.0 / 120.0)
		_expect_true(rig.attack_live(),
			"%s dash starts mid-attack" % hero_id)
		_expect_false(sprite.is_playing(),
			"%s hidden clock parks before the dash" % hero_id)
		_expect_true(player.call("dash", Vector2.LEFT),
			"%s dashes mid-attack" % hero_id)
		_expect_equal(int(player.facing), int(Player.Facing.RIGHT),
			"%s dash keeps the target facing" % hero_id)
		_expect_true(rig.attack_live(),
			"%s attack survives its dash" % hero_id)
		_expect_false(sprite.is_playing(),
			"%s hidden clock parks through the dash" % hero_id)
		var seen: Dictionary = {}
		var span: float = rig.attack_span()
		var age: float = float(rig.get("_attack_age"))
		var dt: float = 1.0 / 120.0
		while age < span + dt:
			if not rig.attack_live():
				break
			var atlas: AtlasTexture = legs.texture as AtlasTexture
			seen[int(atlas.region.position.y)] = true
			_expect_equal(atlas.atlas, hero.walk_sheet,
				"%s dash legs draw the walk sheet" % hero_id)
			_expect_false(sprite.is_playing(),
				"%s hidden clock never restarts mid-dash" % hero_id)
			_step(player, dt)
			age += dt
		_expect_true(seen.size() >= 2,
			"%s dash keeps stepping (%d frames)" % [
				hero_id, seen.size()])
		_finish_attack(player, rig)
		player.queue_free()
		await process_frame


## Walk stop/start mid-attack switches the drawn sheet without resetting the
## stride frame, running a second clock, or stepping the gait backward.
## Controlled steps measure the exact frame and sub-frame progress.
func _test_attack_gait_walk_transitions() -> void:
	var hero: Hero = load(
		"res://resources/heroes/warden.tres") as Hero
	# Stop mid-cut: walk frame 2 must survive the switch to idle.
	var player: Player = _add_player()
	_apply_hero(player, "warden")
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	var sprite: AnimatedSprite2D = player.get_node(
		"Sprite") as AnimatedSprite2D
	var legs: Sprite2D = player.get_node("AttackLegs") as Sprite2D
	player.face_toward(Vector2.RIGHT)
	player.call("set_walking", true)
	sprite.frame = 2
	player.set("_attack_cooldown", 0.0)
	player.attack(Vector2.RIGHT)
	for tick in 5:
		_step(player, 1.0 / 120.0)
	var frame_before: int = sprite.frame
	var gait_before: float = float(player.get("_gait_time"))
	var progress_before: float = gait_before * hero.walk_fps
	player.call("set_walking", false)
	_expect_false(sprite.is_playing(),
		"stop never starts a second clock")
	_expect_equal(sprite.frame, frame_before,
		"stop keeps the stride frame at once (%d)" % frame_before)
	_step(player, 1.0 / 120.0)
	_expect_equal(sprite.animation, &"idle_right",
		"stop switches the hidden sheet")
	_expect_equal(sprite.frame, frame_before,
		"stop keeps the stride frame (%d)" % frame_before)
	_expect_false(sprite.is_playing(),
		"stop never starts a second clock on its tick")
	var gait_after: float = float(player.get("_gait_time"))
	var progress_after: float = gait_after * hero.idle_fps
	_expect_true(progress_after >= progress_before - 0.001,
		"stop never steps the gait backward (%.2f to %.2f)" % [
			progress_before, progress_after])
	var stop_atlas: AtlasTexture = legs.texture as AtlasTexture
	_expect_equal(stop_atlas.atlas, hero.idle_sheet,
		"stopped legs draw the idle sheet")
	_expect_false(sprite.is_playing(),
		"stopped legs never restart the clock")
	_finish_attack(player, rig)
	_expect_settled(player, rig, "stopped cut")
	player.queue_free()
	await process_frame
	# Start mid-cut: idle frame 1 must survive the switch to walk.
	var starter: Player = _add_player()
	_apply_hero(starter, "warden")
	var starter_rig: WeaponRig = starter.get_node(
		"WeaponRig") as WeaponRig
	var starter_sprite: AnimatedSprite2D = starter.get_node(
		"Sprite") as AnimatedSprite2D
	var starter_legs: Sprite2D = starter.get_node(
		"AttackLegs") as Sprite2D
	starter.face_toward(Vector2.RIGHT)
	starter.call("set_walking", false)
	starter_sprite.frame = 1
	starter.set("_attack_cooldown", 0.0)
	starter.attack(Vector2.RIGHT)
	for tick in 5:
		_step(starter, 1.0 / 120.0)
	var start_frame: int = starter_sprite.frame
	var start_gait: float = float(starter.get("_gait_time"))
	var start_progress: float = start_gait * hero.idle_fps
	starter.call("set_walking", true)
	_expect_false(starter_sprite.is_playing(),
		"start never starts a second clock")
	_expect_equal(starter_sprite.frame, start_frame,
		"start keeps the stride frame at once (%d)" % start_frame)
	_step(starter, 1.0 / 120.0)
	_expect_equal(starter_sprite.animation, &"walk_right",
		"start switches the hidden sheet")
	_expect_equal(starter_sprite.frame, start_frame,
		"start keeps the stride frame (%d)" % start_frame)
	_expect_false(starter_sprite.is_playing(),
		"start never starts a second clock on its tick")
	var started_gait: float = float(starter.get("_gait_time"))
	var started_progress: float = started_gait * hero.walk_fps
	_expect_true(started_progress >= start_progress - 0.001,
		"start never steps the gait backward (%.2f to %.2f)" % [
			start_progress, started_progress])
	var start_atlas: AtlasTexture = starter_legs.texture as AtlasTexture
	_expect_equal(start_atlas.atlas, hero.walk_sheet,
		"started legs draw the walk sheet")
	_finish_attack(starter, starter_rig)
	_expect_settled(starter, starter_rig, "started cut")
	starter.queue_free()
	await process_frame
	# Facing-change retrigger keeps the stride frame and progress.
	var turner: Player = _add_player()
	_apply_hero(turner, "warden")
	var turner_rig: WeaponRig = turner.get_node(
		"WeaponRig") as WeaponRig
	var turner_sprite: AnimatedSprite2D = turner.get_node(
		"Sprite") as AnimatedSprite2D
	turner.face_toward(Vector2.RIGHT)
	turner.call("set_walking", true)
	turner_sprite.frame = 2
	turner.set("_attack_cooldown", 0.0)
	turner.attack(Vector2.RIGHT)
	for tick in 8:
		_step(turner, 1.0 / 120.0)
	var turn_frame: int = turner_sprite.frame
	var turn_gait: float = float(turner.get("_gait_time"))
	turner.set("_attack_cooldown", 0.0)
	turner.attack(Vector2.UP)
	_expect_equal(turner_sprite.animation, &"walk_up",
		"retrigger turns the hidden sheet")
	_expect_equal(turner_sprite.frame, turn_frame,
		"retrigger keeps the stride frame (%d)" % turn_frame)
	_expect_false(turner_sprite.is_playing(),
		"retrigger never starts a second clock")
	_expect_true(float(turner.get("_gait_time")) >= turn_gait - 0.000001,
		"retrigger never steps the gait backward")
	var turn_atlas: AtlasTexture = (
		turner.get_node("AttackLegs") as Sprite2D).texture as AtlasTexture
	_expect_equal(int(turn_atlas.region.position.x),
		int(turner.facing) * hero.sprite_cell.x,
		"retriggered legs follow the new facing")
	_finish_attack(turner, turner_rig)
	turner.queue_free()
	await process_frame


## Rapid repeats keep one striding clock: five retriggers with two steps
## between still visit every walk frame exactly forward, and the gait time
## never steps backward on a same-aim restart.
func _test_attack_gait_retrigger_stride() -> void:
	var player: Player = _add_player()
	_apply_hero(player, "warden")
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	var sprite: AnimatedSprite2D = player.get_node(
		"Sprite") as AnimatedSprite2D
	player.face_toward(Vector2.RIGHT)
	player.call("set_walking", true)
	sprite.frame = 0
	var frames: Array[int] = []
	var last_gait: float = -1.0
	var backward: bool = false
	for cycle in 5:
		player.set("_attack_cooldown", 0.0)
		player.attack(Vector2.RIGHT)
		var gait_now: float = float(player.get("_gait_time"))
		if last_gait >= 0.0 and gait_now < last_gait - 0.000001:
			backward = true
		last_gait = gait_now
		_expect_false(sprite.is_playing(),
			"retrigger %d never starts a second clock" % cycle)
		for tick in 8:
			frames.append(sprite.frame)
			_step(player, 1.0 / 120.0)
			last_gait = float(player.get("_gait_time"))
	_expect_false(backward, "rapid repeats never step the gait backward")
	var distinct: Dictionary = {}
	for frame in frames:
		distinct[frame] = true
	_expect_true(distinct.size() >= 4,
		"rapid repeats keep a complete stride (%d frames)" % distinct.size())
	var stepped_back: bool = false
	var last: int = frames[0]
	for index in range(1, frames.size()):
		var forward: int = (last + 1) % 4
		if frames[index] != last and frames[index] != forward:
			stepped_back = true
		last = frames[index]
	_expect_false(stepped_back, "rapid repeats never step backward")
	_finish_attack(player, rig)
	_expect_settled(player, rig, "rapid stride")
	player.queue_free()
	await process_frame


## Live SceneTree clocks: dash and walk stop/start mid-attack on real
## physics ticks keep stepping, hold facing, and never run two clocks.
func _test_attack_gait_live() -> void:
	for hero_id in ["warden", "sage"]:
		var player: Player = _add_player()
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.set_bounds(Rect2(Vector2.ZERO, Vector2(2000, 2000)))
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		var sprite: AnimatedSprite2D = player.get_node(
			"Sprite") as AnimatedSprite2D
		var legs: Sprite2D = player.get_node("AttackLegs") as Sprite2D
		player.set_move_input(Vector2.LEFT)
		for tick in 5:
			await physics_frame
		_expect_true(bool(player.get("_walking")),
			"%s live walker strides out" % hero_id)
		_primary_attack(player, hero_id, Vector2.RIGHT)
		_expect_true(rig.attack_live(),
			"%s live attack starts" % hero_id)
		var seen: Dictionary = {}
		var clocked: bool = false
		for tick in 2:
			await physics_frame
			if rig.attack_live():
				clocked = clocked or sprite.is_playing()
				var windup: AtlasTexture = legs.texture as AtlasTexture
				seen[int(windup.region.position.y)] = true
		_expect_true(rig.attack_live(),
			"%s live attack survives its windup" % hero_id)
		_expect_true(player.call("dash", Vector2.LEFT),
			"%s live dashes mid-attack" % hero_id)
		_expect_equal(int(player.facing), int(Player.Facing.RIGHT),
			"%s live dash keeps its aim" % hero_id)
		var dash_seen: Dictionary = {}
		for tick in 40:
			await physics_frame
			if not rig.attack_live():
				break
			clocked = clocked or sprite.is_playing()
			var atlas: AtlasTexture = legs.texture as AtlasTexture
			seen[int(atlas.region.position.y)] = true
			dash_seen[int(atlas.region.position.y)] = true
			_expect_equal(int(player.facing), int(Player.Facing.RIGHT),
				"%s live dash holds its aim" % hero_id)
		_expect_false(clocked,
			"%s live dash never runs two clocks" % hero_id)
		_expect_true(seen.size() >= 2,
			"%s live dash keeps stepping (%d)" % [
				hero_id, seen.size()])
		_expect_true(dash_seen.size() >= 1,
			"%s live dash observes its legs" % hero_id)
		for tick in 10:
			await physics_frame
		player.set_move_input(Vector2.ZERO)
		player.queue_free()
		await process_frame
	# Live walk stop mid-attack: release the stick while the cut runs.
	var stopper: Player = _add_player()
	stopper.process_mode = Node.PROCESS_MODE_INHERIT
	stopper.set_bounds(Rect2(Vector2.ZERO, Vector2(2000, 2000)))
	_apply_hero(stopper, "warden")
	var stopper_rig: WeaponRig = stopper.get_node(
		"WeaponRig") as WeaponRig
	var stopper_sprite: AnimatedSprite2D = stopper.get_node(
		"Sprite") as AnimatedSprite2D
	stopper.set_move_input(Vector2.LEFT)
	for tick in 5:
		await physics_frame
	stopper.set("_attack_cooldown", 0.0)
	stopper.attack(Vector2.RIGHT)
	for tick in 2:
		await physics_frame
	var was_walking: bool = bool(stopper.get("_walking"))
	stopper.set_move_input(Vector2.ZERO)
	var live_clocked: bool = false
	var saw_stop: bool = false
	for tick in 30:
		await physics_frame
		if not stopper_rig.attack_live():
			break
		live_clocked = live_clocked or stopper_sprite.is_playing()
		var now_walking: bool = bool(stopper.get("_walking"))
		if was_walking and not now_walking:
			saw_stop = true
		was_walking = now_walking
	_expect_true(saw_stop, "live stop switches mid-attack")
	_expect_false(live_clocked,
		"live stop never runs two clocks")
	for tick in 10:
		await physics_frame
	stopper.queue_free()
	await process_frame
	# Live walk start mid-attack: push the stick while the cut runs.
	var starter: Player = _add_player()
	starter.process_mode = Node.PROCESS_MODE_INHERIT
	starter.set_bounds(Rect2(Vector2.ZERO, Vector2(2000, 2000)))
	_apply_hero(starter, "warden")
	var starter_rig: WeaponRig = starter.get_node(
		"WeaponRig") as WeaponRig
	var starter_sprite: AnimatedSprite2D = starter.get_node(
		"Sprite") as AnimatedSprite2D
	var starter_legs: Sprite2D = starter.get_node(
		"AttackLegs") as Sprite2D
	starter_sprite.frame = 2
	starter.set("_attack_cooldown", 0.0)
	starter.attack(Vector2.RIGHT)
	for tick in 2:
		await physics_frame
	starter.set_move_input(Vector2.RIGHT)
	var started_seen: Dictionary = {}
	var started_clocked: bool = false
	var start_was: bool = bool(starter.get("_walking"))
	var saw_start: bool = false
	for tick in 30:
		await physics_frame
		if not starter_rig.attack_live():
			break
		started_clocked = started_clocked or starter_sprite.is_playing()
		var atlas: AtlasTexture = starter_legs.texture as AtlasTexture
		started_seen[int(atlas.region.position.y)] = true
		var start_now: bool = bool(starter.get("_walking"))
		if not start_was and start_now:
			saw_start = true
		start_was = start_now
	_expect_true(saw_start, "live start switches mid-attack")
	_expect_false(started_clocked,
		"live start never runs two clocks")
	_expect_true(started_seen.size() >= 2,
		"live start keeps stepping (%d)" % started_seen.size())
	for tick in 10:
		await physics_frame
	starter.queue_free()
	await process_frame


## Fractional gait: attack entry and recovery preserve the complete
## frame-plus-progress through the real sprite clock at nonzero fractions,
## walking and idle, across walk/idle and facing switches, at an unchanged
## rate. Either handoff dropping the fraction fails these.
func _test_attack_gait_fraction() -> void:
	for hero_id in HERO_IDS:
		await _test_gait_fraction_handoffs(hero_id, true)
		await _test_gait_fraction_handoffs(hero_id, false)
		await _test_gait_fraction_switches(hero_id)
		await _test_gait_fraction_pending(hero_id)


## One hero, one sheet: seed frame 2 + 0.75 walking (1 + 0.6 idle), prove
## the entry clock reads the full 2.75 (1.6), the parked sprite tracks the
## explicit clock tick by tick, the rate never changes, and the recovered
## sprite agrees with the explicit clock to float tolerance.
func _test_gait_fraction_handoffs(hero_id: String, walking: bool) -> void:
	var player: Player = _add_player()
	_apply_hero(player, hero_id)
	var hero: Hero = load(
		"res://resources/heroes/%s.tres" % hero_id) as Hero
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	var sprite: AnimatedSprite2D = player.get_node(
		"Sprite") as AnimatedSprite2D
	var fps: float = hero.walk_fps if walking else hero.idle_fps
	var frames: int = hero.walk_frames if walking else hero.idle_frames
	var sheet: String = "walk" if walking else "idle"
	var seat_frame: int = 2 if walking else 1
	var seat_fraction: float = 0.75 if walking else 0.6
	player.face_toward(Vector2.RIGHT)
	player.call("set_walking", walking)
	sprite.set_frame_and_progress(seat_frame, seat_fraction)
	var before: float = float(seat_frame) + seat_fraction
	_primary_attack(player, hero_id, Vector2.RIGHT)
	var clock: float = float(player.get("_gait_time")) * fps
	_expect_true(absf(clock - before) < 0.000001,
		"%s %s entry keeps %.2f (got %.4f)" % [
			hero_id, sheet, before, clock])
	_expect_equal(sprite.frame, seat_frame,
		"%s %s entry keeps its frame" % [hero_id, sheet])
	_expect_true(absf(sprite.frame_progress - seat_fraction) < 0.0001,
		"%s %s entry keeps its fraction" % [hero_id, sheet])
	_expect_false(sprite.is_playing(),
		"%s %s hidden clock parks" % [hero_id, sheet])
	var dt: float = 1.0 / 120.0
	for tick in 5:
		_step(player, dt)
		var want_total: float = float(player.get("_gait_time")) * fps
		var hidden_total: float = float(sprite.frame) \
			+ sprite.frame_progress
		_expect_true(absf(hidden_total - fposmod(
			want_total, float(frames))) < 0.001,
			"%s %s hidden clock tracks its fraction" % [hero_id, sheet])
		_expect_false(sprite.is_playing(),
			"%s %s hidden clock never restarts" % [hero_id, sheet])
	var rated: float = float(player.get("_gait_time"))
	_expect_true(absf(rated - (before / fps + 5.0 * dt)) < 0.000001,
		"%s %s gait rate never changes" % [hero_id, sheet])
	_finish_attack(player, rig)
	_step(player, dt)
	var explicit: float = float(player.get("_gait_time")) * fps
	_expect_true(sprite.is_playing(),
		"%s %s clock plays on" % [hero_id, sheet])
	_expect_equal(sprite.frame, int(explicit) % frames,
		"%s %s recovery keeps its frame" % [hero_id, sheet])
	_expect_true(absf(sprite.frame_progress - fposmod(explicit, 1.0))
		< 0.001,
		"%s %s recovery keeps its fraction" % [hero_id, sheet])
	player.queue_free()
	await process_frame


## One hero mid-attack: stop and start switch sheets, and a facing-change
## retrigger turns the hidden sheet, each preserving the exact
## frame-plus-progress; the drawn legs follow every switch.
func _test_gait_fraction_switches(hero_id: String) -> void:
	var player: Player = _add_player()
	_apply_hero(player, hero_id)
	var hero: Hero = load(
		"res://resources/heroes/%s.tres" % hero_id) as Hero
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	var sprite: AnimatedSprite2D = player.get_node(
		"Sprite") as AnimatedSprite2D
	var legs: Sprite2D = player.get_node("AttackLegs") as Sprite2D
	player.face_toward(Vector2.RIGHT)
	player.call("set_walking", true)
	sprite.set_frame_and_progress(2, 0.75)
	_primary_attack(player, hero_id, Vector2.RIGHT)
	var dt: float = 1.0 / 120.0
	for tick in 3:
		_step(player, dt)
	var cruising: float = float(player.get("_gait_time")) * hero.walk_fps
	player.call("set_walking", false)
	_step(player, dt)
	_expect_equal(sprite.animation, &"idle_right",
		"%s stop switches the hidden sheet" % hero_id)
	_expect_equal(sprite.frame, int(cruising) % hero.idle_frames,
		"%s stop keeps the stride frame" % hero_id)
	_expect_true(absf(sprite.frame_progress - fposmod(cruising, 1.0))
		< 0.001,
		"%s stop keeps the stride fraction" % hero_id)
	_expect_equal((legs.texture as AtlasTexture).atlas, hero.idle_sheet,
		"%s stopped legs draw the idle sheet" % hero_id)
	for tick in 2:
		_step(player, dt)
	var resting: float = float(player.get("_gait_time")) * hero.idle_fps
	player.call("set_walking", true)
	_step(player, dt)
	_expect_equal(sprite.animation, &"walk_right",
		"%s start switches the hidden sheet" % hero_id)
	_expect_equal(sprite.frame, int(resting) % hero.walk_frames,
		"%s start keeps the stride frame" % hero_id)
	_expect_true(absf(sprite.frame_progress - fposmod(resting, 1.0))
		< 0.001,
		"%s start keeps the stride fraction" % hero_id)
	for tick in 2:
		_step(player, dt)
	var turning: float = float(player.get("_gait_time")) * hero.walk_fps
	if hero_id in MELEE_PRIMARY:
		player.set("_attack_cooldown", 0.0)
		player.attack(Vector2.UP)
	else:
		player.play_moonlight_cast(Vector2.UP, 1)
	_expect_equal(sprite.animation, &"walk_up",
		"%s retrigger turns the hidden sheet" % hero_id)
	_expect_equal(sprite.frame, int(turning) % hero.walk_frames,
		"%s retrigger keeps the stride frame" % hero_id)
	_expect_true(absf(sprite.frame_progress - fposmod(turning, 1.0))
		< 0.001,
		"%s retrigger keeps the stride fraction" % hero_id)
	_expect_equal(int((legs.texture as AtlasTexture).region.position.x),
		int(player.facing) * hero.sprite_cell.x,
		"%s retriggered legs follow the new facing" % hero_id)
	_finish_attack(player, rig)
	_step(player, dt)
	var explicit: float = float(player.get("_gait_time")) * hero.walk_fps
	_expect_equal(sprite.frame, int(explicit) % hero.walk_frames,
		"%s switched recovery keeps its frame" % hero_id)
	_expect_true(absf(sprite.frame_progress - fposmod(explicit, 1.0))
		< 0.001,
		"%s switched recovery keeps its fraction" % hero_id)
	player.queue_free()
	await process_frame


## One hero, recovery with a pending sheet switch: the rig finishes on its
## own clock while the body stops or turns with no gait tick left, so the
## resume itself must carry the frame-plus-progress across the switch instead
## of replaying into frame zero.
func _test_gait_fraction_pending(hero_id: String) -> void:
	for pending in ["stop", "turn"]:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var hero: Hero = load(
			"res://resources/heroes/%s.tres" % hero_id) as Hero
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		var sprite: AnimatedSprite2D = player.get_node(
			"Sprite") as AnimatedSprite2D
		player.face_toward(Vector2.RIGHT)
		player.call("set_walking", true)
		sprite.set_frame_and_progress(2, 0.75)
		_primary_attack(player, hero_id, Vector2.RIGHT)
		var dt: float = 1.0 / 120.0
		_step(player, dt)
		_step(player, dt)
		var progress: float = float(player.get("_gait_time")) \
			* hero.walk_fps
		var left: float = rig.attack_span() \
			- float(rig.get("_attack_age"))
		rig.call("_process", left + dt)
		_expect_false(rig.attack_live(),
			"%s pending %s rig finishes alone" % [hero_id, pending])
		if pending == "stop":
			player.call("set_walking", false)
		else:
			player.face_toward(Vector2.LEFT)
		player.call("_update_attack_pose", dt)
		var want_anim: StringName = &"idle_right" \
			if pending == "stop" else &"walk_left"
		var frames: int = hero.idle_frames \
			if pending == "stop" else hero.walk_frames
		_expect_equal(sprite.animation, want_anim,
			"%s pending %s resumes its sheet" % [hero_id, pending])
		_expect_equal(sprite.frame, int(progress) % frames,
			"%s pending %s recovery keeps its frame" % [hero_id, pending])
		_expect_true(absf(sprite.frame_progress - fposmod(progress, 1.0))
			< 0.001,
			"%s pending %s recovery keeps its fraction" % [
				hero_id, pending])
		_expect_true(sprite.is_playing(),
			"%s pending %s clock plays on" % [hero_id, pending])
		player.queue_free()
		await process_frame


## The ordinary moving-against-aim entry: face one way, stride mid-frame,
## then fire the production primary at the opposite target. The turn must
## keep the full 2.75 (1.6) exactly like a mid-attack retrigger — never the
## replayed 0.0 — with the new sheet, the new legs column, one parked
## hidden clock, the unchanged gait rate, and exact recovery. Opposite
## horizontal and vertical turns, walking and idle, all six heroes.
func _test_attack_gait_first_turn() -> void:
	for hero_id in HERO_IDS:
		await _test_first_turn_entries(hero_id, true)
		await _test_first_turn_entries(hero_id, false)
		await _test_first_turn_ordinary(hero_id)


## One hero, one sheet: four opposite first-entry turns through the
## production primary call, seeded at a nonzero fraction.
func _test_first_turn_entries(hero_id: String, walking: bool) -> void:
	var hero: Hero = load(
		"res://resources/heroes/%s.tres" % hero_id) as Hero
	var fps: float = hero.walk_fps if walking else hero.idle_fps
	var frames: int = hero.walk_frames if walking else hero.idle_frames
	var sheet: String = "walk" if walking else "idle"
	var seat_frame: int = 2 if walking else 1
	var seat_fraction: float = 0.75 if walking else 0.6
	var before: float = float(seat_frame) + seat_fraction
	var turns: Array = [
		[Vector2.LEFT, Vector2.RIGHT], [Vector2.RIGHT, Vector2.LEFT],
		[Vector2.UP, Vector2.DOWN], [Vector2.DOWN, Vector2.UP],
	]
	for turn in turns:
		var from: Vector2 = turn[0]
		var target: Vector2 = turn[1]
		var tag: String = "%s %s %s-to-%s" % [
			hero_id, sheet, Player.facing_for(from),
			Player.facing_for(target)]
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		var sprite: AnimatedSprite2D = player.get_node(
			"Sprite") as AnimatedSprite2D
		var legs: Sprite2D = player.get_node("AttackLegs") as Sprite2D
		player.face_toward(from)
		player.call("set_walking", walking)
		sprite.set_frame_and_progress(seat_frame, seat_fraction)
		_primary_attack(player, hero_id, target)
		var clock: float = float(player.get("_gait_time")) * fps
		_expect_true(absf(clock - before) < 0.000001,
			"%s turn entry keeps %.2f (got %.4f)" % [tag, before, clock])
		var want_anim: StringName = StringName(
			sheet + "_" + Player.facing_for(target))
		_expect_equal(sprite.animation, want_anim,
			"%s turn entry turns its sheet" % tag)
		_expect_equal(sprite.frame, seat_frame,
			"%s turn entry keeps its frame" % tag)
		_expect_true(absf(sprite.frame_progress - seat_fraction) < 0.0001,
			"%s turn entry keeps its fraction" % tag)
		_expect_false(sprite.is_playing(),
			"%s hidden clock parks through the turn" % tag)
		var want_sheet: Texture2D = hero.walk_sheet \
			if walking else hero.idle_sheet
		_expect_equal((legs.texture as AtlasTexture).atlas, want_sheet,
			"%s turned legs draw the %s sheet" % [tag, sheet])
		var region: Rect2 = (legs.texture as AtlasTexture).region
		_expect_equal(int(region.position.x),
			int(player.facing) * hero.sprite_cell.x,
			"%s turned legs take the new column" % tag)
		var cutline: float = float(Player.rig_geometry_for(
			hero_id).get("cutline", 156))
		_expect_equal(int(region.position.y),
			seat_frame * hero.sprite_cell.y + int(cutline),
			"%s turned legs start mid-stride" % tag)
		var dt: float = 1.0 / 120.0
		for tick in 3:
			_step(player, dt)
			var want_total: float = float(player.get("_gait_time")) * fps
			var hidden_total: float = float(sprite.frame) \
				+ sprite.frame_progress
			_expect_true(absf(hidden_total - fposmod(
				want_total, float(frames))) < 0.001,
				"%s hidden clock tracks the turn" % tag)
			_expect_false(sprite.is_playing(),
				"%s hidden clock never restarts" % tag)
		var rated: float = float(player.get("_gait_time"))
		_expect_true(absf(rated - (before / fps + 3.0 * dt)) < 0.000001,
			"%s gait rate never changes" % tag)
		_finish_attack(player, rig)
		_step(player, dt)
		var explicit: float = float(player.get("_gait_time")) * fps
		_expect_true(sprite.is_playing(),
			"%s clock plays on" % tag)
		_expect_equal(sprite.frame, int(explicit) % frames,
			"%s recovery keeps its frame" % tag)
		_expect_true(absf(sprite.frame_progress - fposmod(explicit, 1.0))
			< 0.001,
			"%s recovery keeps its fraction" % tag)
		player.queue_free()
		await process_frame


## The fix stays narrow: a plain stick turn with no attack still replays its
## sheet from frame zero. Only the two primary entries carry the stride.
func _test_first_turn_ordinary(hero_id: String) -> void:
	for walking in [true, false]:
		var sheet: String = "walk" if walking else "idle"
		var tag: String = "%s %s" % [hero_id, sheet]
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var sprite: AnimatedSprite2D = player.get_node(
			"Sprite") as AnimatedSprite2D
		player.face_toward(Vector2.LEFT)
		player.call("set_walking", walking)
		sprite.set_frame_and_progress(2, 0.75)
		player.face_toward(Vector2.RIGHT)
		_expect_equal(sprite.animation, StringName(sheet + "_right"),
			"%s ordinary turn switches its sheet" % tag)
		_expect_equal(sprite.frame, 0,
			"%s ordinary turn replays its frame" % tag)
		_expect_true(absf(sprite.frame_progress) < 0.000001,
			"%s ordinary turn replays its fraction" % tag)
		player.queue_free()
		await process_frame


## Thigh, knee, and boot bands all differ across the drawn leg frames: no
## static upper leg with only the boots stepping.
func _legs_bands_move(hero: Hero, region_tops: Array) -> bool:
	if region_tops.size() < 2:
		return false
	var image: Image = hero.walk_sheet.get_image()
	if image == null:
		return false
	var cell: Vector2i = hero.sprite_cell
	var geometry: Dictionary = Player.rig_geometry_for(hero.id)
	var cutline: int = int(float(geometry.get("cutline", 156)))
	var bands: Array = [
		[cutline, cutline + 10],
		[cutline + 10, cutline + 20],
		[180, 192],
	]
	var frames: Array[int] = []
	for top in region_tops:
		frames.append(int((int(top) - cutline) / cell.y))
	for band in bands:
		var moved: bool = false
		for first in frames.size():
			for second in range(first + 1, frames.size()):
				if _band_differs(image, cell, frames[first],
						frames[second], int(band[0]), int(band[1])):
					moved = true
		if not moved:
			return false
	return true


func _band_differs(image: Image, cell: Vector2i, first: int,
		second: int, y0: int, y1: int) -> bool:
	if first == second:
		return false
	for y in range(y0, mini(y1, cell.y)):
		for x in cell.x:
			var a: Color = image.get_pixel(x, first * cell.y + y)
			var b: Color = image.get_pixel(x, second * cell.y + y)
			if a != b:
				return true
	return false


## Motion without any cue: production attack methods run with the draw layer
## dark — no slash, flash glow, cast, or orbit — and the physical action
## travels exactly as far as it does with VFX.
func _test_no_vfx_motion() -> void:
	for hero_id in HERO_IDS:
		var player: Player = _add_player()
		_apply_hero(player, hero_id)
		var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
		_primary_attack(player, hero_id, Vector2.RIGHT)
		var lit_travel: float = _action_travel(player, rig)
		_finish_attack(player, rig)
		# One unrecorded action advances the cut/fang alternation, so the
		# dark run below matches the lit run's variant exactly.
		_primary_attack(player, hero_id, Vector2.RIGHT)
		_finish_attack(player, rig)
		player.set_vfx_suppressed(true)
		_expect_true(bool(rig.get("_vfx_suppressed")),
			"%s rig flash draws dark" % hero_id)
		var dark_scythe: ScytheOrbit = player.get_node_or_null(
			"ScytheOrbit") as ScytheOrbit
		_expect_true(dark_scythe == null
			or bool(dark_scythe.get("_vfx_suppressed")),
			"%s orbit draws dark" % hero_id)
		_expect_true(bool(
			(player.get_node("MoonlightCast") as MoonlightCast)
				.get("_vfx_suppressed")),
			"%s cast draws dark" % hero_id)
		_primary_attack(player, hero_id, Vector2.RIGHT)
		_expect_true(rig.attack_live(),
			"%s dark action still starts" % hero_id)
		_expect_true(not (player.get_node("Slash") as Sprite2D).visible,
			"%s dark action shows no slash" % hero_id)
		_expect_true(str(rig.get("_kind")) != "",
			"%s dark action still lights its flash" % hero_id)
		var dark_travel: float = _action_travel(player, rig)
		_expect_true(absf(dark_travel - lit_travel) < 0.01,
			"%s dark action travels as far (%.2f)" % [hero_id, dark_travel])
		_finish_attack(player, rig)
		_expect_settled(player, rig, "%s dark action" % hero_id)
		player.set_vfx_suppressed(false)
		player.queue_free()
		await process_frame


## The Eclipse orbit sweep starts on the contact aim with the reaper's own sign
## and span, and travels the same long crescent — even with VFX dark, where
## the timing still runs.
func _test_eclipse_tie() -> void:
	_expect_equal(ScytheOrbit.SWEEP_TRAVEL_DEGREES, 135.0,
		"orbit sweep matches the reaper travel")
	var player: Player = _add_player()
	_apply_hero(player, "eclipse")
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	var scythe: ScytheOrbit = player.get_node("ScytheOrbit") as ScytheOrbit
	for aim in AIMS:
		player.set("_attack_cooldown", 0.0)
		player.attack(aim)
		_expect_equal(float(scythe.get("_sweep_from")), aim.angle(),
			"eclipse %s sweep starts on contact" % str(aim))
		_expect_equal(float(scythe.get("_sweep_sign")), rig.attack_sign(),
			"eclipse %s sweep shares the cut sign" % str(aim))
		_expect_equal(float(scythe.get("_sweep_span")), rig.attack_span(),
			"eclipse %s sweep shares the cut span" % str(aim))
		_expect_true(float(scythe.get("_pulse_age")) < 0.001,
			"eclipse %s ring lands with the cut" % str(aim))
		var travel: float = 0.0
		var span: float = rig.attack_span()
		var age: float = 0.0
		var dt: float = 1.0 / 240.0
		while age < span + dt:
			travel = maxf(travel, absf(scythe.sweep_travel_now()))
			_step(player, dt)
			age += dt
		_expect_true(travel >= deg_to_rad(120.0),
			"eclipse %s sweep travels %.1f" % [str(aim), rad_to_deg(travel)])
	player.queue_free()
	await process_frame
	# The full-moon ring still swings the reaper and shows the crescent.
	var full: Player = _add_player()
	_apply_hero(full, "eclipse")
	var full_rig: WeaponRig = full.get_node("WeaponRig") as WeaponRig
	full.set("_attack_cooldown", 0.0)
	full.attack(Vector2.RIGHT, true)
	_expect_true(full_rig.attack_live(), "full-moon ring swings the reaper")
	_expect_true((full.get_node("Slash") as Sprite2D).visible,
		"full-moon ring shows the crescent")
	_finish_attack(full, full_rig)
	full.queue_free()
	await process_frame
	# Suppressed, the pulse timing still runs while the draw stays dark.
	var dark: Player = _add_player()
	_apply_hero(dark, "eclipse")
	var dark_scythe: ScytheOrbit = dark.get_node("ScytheOrbit") as ScytheOrbit
	dark.set_vfx_suppressed(true)
	dark.set("_attack_cooldown", 0.0)
	dark.attack(Vector2.RIGHT)
	_expect_true(float(dark_scythe.get("_pulse_age")) < 0.001,
		"dark sweep still lands its ring timing")
	_expect_true(dark_scythe.sweep_live(),
		"dark sweep still travels its timing")
	_finish_attack(dark, dark.get_node("WeaponRig") as WeaponRig)
	dark.set_vfx_suppressed(false)
	dark.queue_free()
	await process_frame


## Negative control: with only the arm rig frozen, the weapon and cues still
## move but the elbow never bends and the wrist never sweeps. The probe
## restores before finishing, and the thawed action articulates again.
func _test_arm_freeze_control() -> void:
	var player: Player = _add_player()
	_apply_hero(player, "warden")
	var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	var arm: ArmRig = player.get_node("ArmMain") as ArmRig
	player.set("_debug_arm_freeze", true)
	player.set("_attack_cooldown", 0.0)
	player.attack(Vector2.RIGHT)
	var rest_angle: float = _elbow_interior(arm)
	var flex: float = 0.0
	var tip_travel: float = 0.0
	var cue_lit: bool = false
	var tip_start: Vector2 = rig.to_global(rig.drawn_tip_now())
	var span: float = rig.attack_span()
	var age: float = 0.0
	var dt: float = 1.0 / 240.0
	while age < span + dt:
		flex = maxf(flex, absf(_elbow_interior(arm) - rest_angle))
		tip_travel = maxf(tip_travel,
			tip_start.distance_to(rig.to_global(rig.drawn_tip_now())))
		cue_lit = cue_lit or str(rig.get("_kind")) != ""
		_step(player, dt)
		age += dt
	_expect_true(flex < 0.5,
		"frozen elbow never bends (%.2f)" % flex)
	_expect_true(tip_travel > 5.0,
		"frozen weapon tip still travels (%.2f)" % tip_travel)
	_expect_true(cue_lit, "frozen cue still lights")
	_finish_attack(player, rig)
	player.set("_debug_arm_freeze", false)
	player.set("_attack_cooldown", 0.0)
	player.attack(Vector2.LEFT)
	var thawed: float = 0.0
	var thawed_rest: float = _elbow_interior(arm)
	span = rig.attack_span()
	age = 0.0
	while age < span + dt:
		thawed = maxf(thawed, thawed_rest - _elbow_interior(arm))
		_step(player, dt)
		age += dt
	_expect_true(thawed >= float(ELBOW_FLEX_MINIMUM["warden"]),
		"thawed elbow bends again (%.1f)" % thawed)
	_expect_false(bool(player.get("_debug_arm_freeze")),
		"freeze probe restores")
	player.queue_free()
	await process_frame


## Settled means settled: no live motion, zero offsets, rest seat, split
## hidden, baked sprite playing, feet planted, hold cleared.
func _expect_settled(player: Player, rig: WeaponRig, label: String) -> void:
	_expect_true(not rig.attack_live(), label + " motion ends")
	_expect_equal(rig.attack_progress(), -1.0, label + " progress parks")
	_expect_equal(rig.swing_angle_now(), 0.0, label + " blade parks")
	_expect_equal(rig.gun_pitch_now(), 0.0, label + " muzzle parks")
	_expect_equal(rig.attack_shift_now(), Vector2.ZERO,
		label + " travel parks")
	_expect_equal(rig.position, player.rest_rig_seat(rig.aim()),
		label + " weapon seats home")
	_expect_equal(rig.z_index, 2, label + " weapon rides above")
	if str(player.get("_hero_id")) == "dancer":
		_expect_true(rig.brace_local.length() > 1.0,
			label + " brace fang keeps its hand")
	_expect_false(bool(player.get("_split_shown")), label + " split hides")
	var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	_expect_true(sprite.visible, label + " baked sprite returns")
	_expect_true(sprite.is_playing(), label + " baked sprite plays on")
	_expect_equal(sprite.position,
		Vector2(0.0, float(player.get("_sprite_base_y"))),
		label + " feet plant home")
	_expect_equal(sprite.rotation, 0.0, label + " shoulders flatten")
	_expect_equal(sprite.scale,
		Vector2.ONE * float(player.get("_hero_scale")),
		label + " silhouette restores")
	_expect_equal(float(player.get("_face_hold")), 0.0,
		label + " hold clears")


func _primary_attack(player: Player, hero_id: String, aim: Vector2) -> void:
	if hero_id in MELEE_PRIMARY:
		player.set("_attack_cooldown", 0.0)
		player.attack(aim)
	else:
		player.play_moonlight_cast(aim, 1)


## Facing enum int one aim snaps to, mirroring `face_toward`.
func _facing_int(aim: Vector2) -> int:
	if absf(aim.x) > absf(aim.y):
		return int(Player.Facing.RIGHT) if aim.x > 0.0 \
			else int(Player.Facing.LEFT)
	return int(Player.Facing.DOWN) if aim.y > 0.0 \
		else int(Player.Facing.UP)


## Blade angle error at the contact instant, radians from the aim.
func _blade_error(rig: WeaponRig, aim: Vector2) -> float:
	var grip: Vector2 = rig.draw_anchor_now()
	var tip: Vector2 = rig.drawn_tip_now()
	return absf((tip - grip).angle_to(aim.normalized()))


## Hand-to-grip gap in world space: the drawn grip against the painted wrist
## the IK solver reports. Melee grips sit on the seated pivot, gun hands on
## the stock behind it.
func _grip_gap(player: Player, rig: WeaponRig, arm: ArmRig) -> float:
	var wrist_local: Vector2 = Player.cell_to_local(arm.wrist_cell(),
		float(player.get("_sprite_base_y")), float(player.get("_hero_scale")),
		player.call("_current_shift_cells"))
	return _grip_local(player, rig).distance_to(wrist_local)


func _grip_local(player: Player, rig: WeaponRig) -> Vector2:
	var grip_local: Vector2 = rig.position + rig.draw_anchor_now()
	var profile: Hero.AttackProfile = player.get("_hero_profile")
	if HeroWeapons.primary_side(profile) == HeroWeapons.Side.RANGED:
		var flat: Vector2 = rig.aim().normalized() \
			if rig.aim().length() > 0.01 else Vector2.RIGHT
		grip_local = rig.position - flat * WeaponRig.stock_back(profile)
	return grip_local


func _grip_world(player: Player, rig: WeaponRig) -> Vector2:
	return player.to_global(_grip_local(player, rig))


## One chain joint in world space through the live torso shift.
func _wrist_world(player: Player, arm: ArmRig) -> Vector2:
	return player.to_global(Player.cell_to_local(arm.wrist_cell(),
		float(player.get("_sprite_base_y")), float(player.get("_hero_scale")),
		player.call("_current_shift_cells")))


func _shoulder_world(player: Player, arm: ArmRig) -> Vector2:
	return player.to_global(Player.cell_to_local(arm.shoulder_cell(),
		float(player.get("_sprite_base_y")), float(player.get("_hero_scale")),
		player.call("_current_shift_cells")))


## Interior elbow angle in degrees: 180 reads straight, less reads bent.
func _elbow_interior(arm: ArmRig) -> float:
	var elbow: Vector2 = arm.elbow_cell()
	return rad_to_deg(absf((arm.shoulder_cell() - elbow).angle_to(
		arm.wrist_cell() - elbow)))


## Peak wrist world travel over the live attack, stepping it to completion.
func _action_travel(player: Player, rig: WeaponRig) -> float:
	var arm: ArmRig = player.get_node("ArmMain") as ArmRig
	var start: Vector2 = _wrist_world(player, arm)
	var travel: float = 0.0
	var span: float = rig.attack_span()
	var age: float = 0.0
	var dt: float = 1.0 / 240.0
	while age < span + dt:
		if not rig.attack_live():
			break
		travel = maxf(travel, start.distance_to(_wrist_world(player, arm)))
		_step(player, dt)
		age += dt
	return travel


## Sweep one cut to completion, returning the unwrapped tip arc in degrees.
func _sample_arc(
	player: Player, rig: WeaponRig, dt: float = 1.0 / 120.0
) -> float:
	var angles: Array[float] = []
	var span: float = rig.attack_span()
	var age: float = 0.0
	while age < span + dt:
		var grip: Vector2 = rig.draw_anchor_now()
		angles.append((rig.drawn_tip_now() - grip).angle())
		_step(player, dt)
		age += dt
	_step(player, dt)
	var unwrapped: Array[float] = [angles[0]]
	for index in range(1, angles.size()):
		var step: float = angle_difference(
			unwrapped[index - 1], angles[index])
		unwrapped.append(unwrapped[index - 1] + step)
	return rad_to_deg(unwrapped.max() - unwrapped.min())


## Nine samples of blade angle plus wrist seat: one action's signature.
func _signature(player: Player, rig: WeaponRig) -> Array:
	var arm: ArmRig = player.get_node("ArmMain") as ArmRig
	var base_y: float = float(player.get("_sprite_base_y"))
	var scale: float = float(player.get("_hero_scale"))
	var signature: Array = []
	# t=0 sample first: every action starts exactly on its aim.
	var shift: Vector2 = player.call("_current_shift_cells")
	var at: Vector2 = Player.cell_to_local(arm.wrist_cell(), base_y, scale,
		shift)
	signature.append(Vector3(
		rig.swing_angle_now() + rig.gun_pitch_now(), at.x, at.y))
	var span: float = rig.attack_span()
	for sample in 8:
		_step(player, span / 8.0)
		shift = player.call("_current_shift_cells")
		at = Player.cell_to_local(arm.wrist_cell(), base_y, scale, shift)
		signature.append(Vector3(
			rig.swing_angle_now() + rig.gun_pitch_now(), at.x, at.y))
	_finish_attack(player, rig)
	return signature


## Largest sample gap between two signatures, radians plus px.
func _signature_gap(first: Array, second: Array) -> float:
	var gap: float = 0.0
	for index in mini(first.size(), second.size()):
		var a: Vector3 = first[index]
		var b: Vector3 = second[index]
		gap = maxf(gap, absf(a.x - b.x) + Vector2(a.y, a.z).distance_to(
			Vector2(b.y, b.z)))
	return gap


## Step the attack's own clocks forward: rig, orbit, cast, and body pose.
func _step(player: Player, dt: float) -> void:
	(player.get_node("WeaponRig") as WeaponRig).call("_process", dt)
	# The orbit only exists for Eclipse; other heroes have no orbit clock.
	var scythe: ScytheOrbit = player.get_node_or_null(
		"ScytheOrbit") as ScytheOrbit
	if scythe != null:
		scythe.call("_process", dt)
	(player.get_node("MoonlightCast") as MoonlightCast).call("_process", dt)
	player.call("_update_attack_pose", dt)


## Step to one progress fraction of the live attack.
func _step_to(player: Player, rig: WeaponRig, progress: float) -> void:
	var target: float = rig.attack_span() * progress
	var age: float = 0.0
	while age < target:
		var dt: float = minf(1.0 / 240.0, target - age)
		_step(player, dt)
		age += dt


## Run the live attack to completion, then one settling step.
func _finish_attack(player: Player, rig: WeaponRig) -> void:
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
## stepped by hand; the pause, facing, and walk tests re-enable their own.
func _add_player() -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	(player.get_node("Cam") as Camera2D).process_callback = \
		Camera2D.CAMERA2D_PROCESS_PHYSICS
	root.add_child(player)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	return player


func _finish() -> void:
	if _failed > 0:
		printerr("attack-motion test failed — ", _failed, "/", _checked,
			" case(s)")
		quit(1)
		return
	print("attack-motion test passed — ", _checked, " case(s)")
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
