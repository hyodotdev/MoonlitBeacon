extends SceneTree

## The rules that keep the small bullets fair: slow, gappy, turning, and never a flood.
##
## The big volleys have `test_volley_fairness`; this holds the bullets you *weave through* (a guardian's aura
## and stream, an ordinary spirit's barrage) to the same promise: every one is slower than the slowest hero, one
## shot's neighbours leave a way through, a ring that fires again has turned, one guardian can never fill the
## field alone, and the stream goes quiet while a telegraph is drawn so the warning still reads on its own.
## Every guardian style is checked at every cycle from 1 to 100, and every ordinary kind that shoots.

const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")
const SPIRIT_SCRIPT: Script = preload("res://scripts/actors/spirit.gd")

## Where a player usually stands from whoever is shooting: the gap is measured there.
const DODGE_RANGE: float = 150.0
## What must fit between two neighbouring bullets of one shot: the player's hit width plus a drawn orb, so the
## way through reads by eye and not only by the hit test.
const REQUIRED_GAP: float = BulletField.HIT_RADIUS * 2.0 + BulletField.DRAW_SIZE
## A ring or a set of arms that fires again must have turned by at least this, or its gaps are where they were.
const MIN_TURN: float = 0.05
## The most bullets one guardian may ever have in the air, at any cycle, at the hottest tempo. With the casters'
## worst case on top it still fits under the field's `LIMIT` with room to spare.
const GUARDIAN_AIR_CAP: float = 110.0

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_intensity()
	_test_rate_clamp()
	_test_speeds_below_slowest_hero()
	_test_gaps()
	_test_rings_turn()
	_test_air_caps()
	_test_stream_silence_and_aura()
	_finish()


func _slowest_hero_speed() -> float:
	var slowest: float = INF
	var found: int = 0
	for file in DirAccess.get_files_at("res://resources/heroes"):
		if not file.ends_with(".tres"):
			continue
		var hero: Hero = load("res://resources/heroes/" + file) as Hero
		if hero == null:
			continue
		found += 1
		slowest = minf(slowest, Player.DEFAULT_SPEED * hero.speed_scale)
	_expect_true(found >= 6, "every hero is found (%d)" % found)
	return slowest


func _shooting_kinds() -> Array[SpiritKind]:
	var kinds: Array[SpiritKind] = []
	for file in DirAccess.get_files_at("res://resources"):
		if not file.ends_with(".tres"):
			continue
		var kind: SpiritKind = load("res://resources/" + file) as SpiritKind
		if kind == null or kind.behavior == SpiritKind.Behavior.GUARDIAN:
			continue
		if kind.barrage != SpiritKind.Barrage.NONE:
			kinds.append(kind)
	return kinds


func _test_intensity() -> void:
	_expect_approx(GuardianStreams.intensity(1), 0.6, 0.0001, "the first meeting throws gently (0.6)")
	_expect_approx(GuardianStreams.intensity(4), 1.0, 0.0001, "the night is full by cycle 4 (1.0)")
	var last: float = 0.0
	for cycle in range(1, 101):
		var now: float = GuardianStreams.intensity(cycle)
		if now < last - 0.00001:
			_expect_true(false, "intensity never falls back (cycle %d: %.3f after %.3f)" % [cycle, now, last])
			return
		last = now
	_checked += 1
	for cycle in range(17, 101):
		if absf(GuardianStreams.intensity(cycle) - GuardianStreams.MAX_INTENSITY) > 0.0001:
			_expect_true(false, "intensity is 2.0 at cycle 17 and after (cycle %d)" % cycle)
			return
	_checked += 1


func _test_rate_clamp() -> void:
	_expect_approx(GuardianStreams.stream_rate(1, 1.0), GuardianStreams.intensity(1), 0.0001,
		"a calm first cycle runs unclamped")
	_expect_true(GuardianStreams.stream_rate(100, 50.0) <= GuardianStreams.MAX_RATE,
		"however hot the tempo, the rate never passes its cap (%.2f)" % GuardianStreams.stream_rate(100, 50.0))


func _test_speeds_below_slowest_hero() -> void:
	var slowest: float = _slowest_hero_speed()
	var worst: float = 0.0
	var worst_label: String = ""
	for style in range(6):
		for cycle in range(1, 101):
			for emitter in GuardianStreams.aura(style, cycle) + GuardianStreams.stream(style, cycle):
				if emitter.speed > worst:
					worst = emitter.speed
					worst_label = "style %d cycle %d" % [style, cycle]
				if emitter.accel > 0.0:
					_expect_true(false, "no bullet speeds up after leaving (%s)" % worst_label)
					return
	_checked += 1
	for kind in _shooting_kinds():
		var spirit: Node2D = SPIRIT_SCENE.instantiate()
		spirit.set("kind", kind)
		for cycle in range(1, 101):
			spirit.set("mob_cycle", cycle)
			var speed: float = spirit.call("_mob_bullet_speed")
			if speed > worst:
				worst = speed
				worst_label = "%s cycle %d" % [kind.resource_path.get_file(), cycle]
		spirit.free()
	_checked += 1
	_expect_true(worst < slowest,
		"every bullet is slower than the slowest hero (%.1f < %.1f, worst %s)" % [worst, slowest, worst_label])


## The angular gap between two neighbouring bullets of one shot, or -1 when a shot is one bullet.
func _neighbour_gap(emitter: BulletEmitter) -> float:
	match emitter.pattern:
		BulletEmitter.Pattern.RING, BulletEmitter.Pattern.SPIRAL:
			return TAU / float(maxi(emitter.count, 1))
		BulletEmitter.Pattern.AIMED:
			if emitter.count <= 1:
				return -1.0
			return emitter.spread / float(emitter.count - 1)
	return -1.0


func _check_gap(angle: float, label: String) -> void:
	if angle < 0.0:
		return
	var gap: float = 2.0 * DODGE_RANGE * sin(angle * 0.5)
	if gap <= REQUIRED_GAP:
		_expect_true(false, "%s leaves no way through (%.1f px at %.0f px)" % [label, gap, DODGE_RANGE])
		return
	_checked += 1


func _test_gaps() -> void:
	var kinds: Array[SpiritKind] = _shooting_kinds()
	_expect_true(kinds.size() >= 3, "the shooting kinds are found (%d)" % kinds.size())
	for style in range(6):
		for cycle in range(1, 101):
			for emitter in GuardianStreams.aura(style, cycle) + GuardianStreams.stream(style, cycle):
				_check_gap(_neighbour_gap(emitter), "style %d cycle %d" % [style, cycle])
				if _failed > 0:
					return
	for kind in kinds:
		var spirit: Node2D = SPIRIT_SCENE.instantiate()
		spirit.set("kind", kind)
		for cycle in range(1, 101):
			spirit.set("mob_cycle", cycle)
			if kind.behavior == SpiritKind.Behavior.SHOOT:
				var count: int = spirit.call("_caster_fan_count")
				var spread: float = spirit.call("_caster_fan_spread")
				var angle: float = -1.0 if count <= 1 else spread / float(count - 1)
				_check_gap(angle, "%s cycle %d" % [kind.resource_path.get_file(), cycle])
			else:
				var emitter: BulletEmitter = _built_mob_emitter(spirit)
				if emitter != null:
					_check_gap(_neighbour_gap(emitter), "%s cycle %d" % [kind.resource_path.get_file(), cycle])
			if _failed > 0:
				spirit.free()
				return
		spirit.free()
	_expect_true(true, "within one shot the neighbours leave a way through (%.0f px at %.0f px)"
		% [REQUIRED_GAP, DODGE_RANGE])


## Build what this spirit throws, the way `_ready` does: only some of a kind throw at all, so ask until one does.
func _built_mob_emitter(spirit: Node2D) -> BulletEmitter:
	for attempt in 200:
		spirit.call("_build_barrages")
		var built: Array = spirit.get("_barrages")
		if not built.is_empty():
			return built[0]
	return null


func _test_rings_turn() -> void:
	for style in range(6):
		for cycle in range(1, 101):
			for emitter in GuardianStreams.aura(style, cycle) + GuardianStreams.stream(style, cycle):
				if not _check_turn(emitter, "style %d cycle %d" % [style, cycle]):
					return
	for kind in _shooting_kinds():
		if kind.behavior == SpiritKind.Behavior.SHOOT:
			continue
		var spirit: Node2D = SPIRIT_SCENE.instantiate()
		spirit.set("kind", kind)
		spirit.set("mob_cycle", 6)
		var emitter: BulletEmitter = _built_mob_emitter(spirit)
		spirit.free()
		if emitter != null and not _check_turn(emitter, kind.resource_path.get_file()):
			return
	_expect_true(true, "every ring and set of arms fires again somewhere new")


func _check_turn(emitter: BulletEmitter, label: String) -> bool:
	if emitter.pattern == BulletEmitter.Pattern.RING:
		var pitch: float = TAU / float(maxi(emitter.count, 1))
		var step: float = fmod(emitter.ring_step, pitch)
		if step <= MIN_TURN or step >= pitch - MIN_TURN:
			_expect_true(false, "%s fires its ring again where it was (step %.3f)" % [label, step])
			return false
	elif emitter.pattern == BulletEmitter.Pattern.SPIRAL:
		if absf(emitter.spin) <= MIN_TURN:
			_expect_true(false, "%s barely turns between shots (%.3f)" % [label, emitter.spin])
			return false
	_checked += 1
	return true


func _test_air_caps() -> void:
	var worst: float = 0.0
	var worst_label: String = ""
	for style in range(6):
		for cycle in range(1, 101):
			var air: float = 0.0
			for emitter in GuardianStreams.aura(style, cycle) + GuardianStreams.stream(style, cycle):
				air += float(emitter.count) / emitter.interval * GuardianStreams.MAX_RATE \
					* emitter.range_px / emitter.speed
			if air > worst:
				worst = air
				worst_label = "style %d cycle %d" % [style, cycle]
	_expect_true(worst < GUARDIAN_AIR_CAP,
		"one guardian never fills the field alone (%.0f < %.0f, worst %s)" % [worst, GUARDIAN_AIR_CAP, worst_label])
	# The casters take turns on one shared beat and their fans live a few seconds: this many at most.
	var caster: SpiritKind = load("res://resources/caster.tres") as SpiritKind
	var spirit: Node2D = SPIRIT_SCENE.instantiate()
	spirit.set("kind", caster)
	spirit.set("mob_cycle", 100)
	var fan: int = spirit.call("_caster_fan_count")
	spirit.set("mob_cycle", 1)
	var slowest: float = spirit.call("_mob_bullet_speed")
	var field: BulletField = BulletField.new()
	root.add_child(field)
	var me: Node2D = Node2D.new()
	me.position = Vector2(100, 0)
	root.add_child(me)
	root.add_child(spirit)
	spirit.call("set_target", me)
	field.clear()
	spirit.call("_fire_caster_shot", Vector2.RIGHT)
	var flight: float = (field.get("_range_left") as PackedFloat32Array)[0] / slowest
	spirit.free()
	me.free()
	var volleys: int = int(ceil(flight / SPIRIT_SCRIPT.MOB_VOLLEY_GAP))
	var caster_worst: int = fan * volleys
	_expect_true(GUARDIAN_AIR_CAP + float(caster_worst) <= float(BulletField.LIMIT),
		"a guardian and the casters together fit under the cap (%.0f + %d <= %d)"
		% [GUARDIAN_AIR_CAP, caster_worst, BulletField.LIMIT])
	field.free()


func _test_stream_silence_and_aura() -> void:
	var cases: Array = [
		["forest", "res://resources/guardian_forest.tres"],
		["field", "res://resources/guardian_field.tres"],
		["camp", "res://resources/guardian_camp.tres"],
		["gale", "res://resources/guardian_frost.tres"],
		["leap", "res://resources/guardian_marsh.tres"],
		["glyph", "res://resources/guardian_ruins.tres"],
	]
	var moves: Array = SPIRIT_SCRIPT.GuardianMove.values()
	var field: BulletField = BulletField.new()
	root.add_child(field)
	field.set_physics_process(false)
	var me: Node2D = Node2D.new()
	me.position = Vector2(100, 0)
	root.add_child(me)
	for entry in cases:
		var spirit: Node2D = SPIRIT_SCENE.instantiate()
		spirit.set("kind", load(entry[1]) as SpiritKind)
		spirit.set("guardian_cycle", 6)
		root.add_child(spirit)
		spirit.set_physics_process(false)
		spirit.set_process(false)
		spirit.call("set_target", me)
		var chase_stream: int = -1
		for move in moves:
			spirit.set("_guardian_move", move)
			for emitter in spirit.get("_barrages") + spirit.get("_streams"):
				emitter.restart(0.0)
			field.clear()
			for tick in 40:
				spirit.call("_tick_barrages", 0.1)
			var aura: int = 0
			var stream: int = 0
			for source in field.get("_source"):
				if source == BulletField.Source.AURA:
					aura += 1
				elif source == BulletField.Source.STREAM:
					stream += 1
			if aura <= 0:
				_expect_true(false, "%s sheds nothing while %s" % [entry[0], SPIRIT_SCRIPT.GuardianMove.keys()[move]])
				return
			_checked += 1
			if move == SPIRIT_SCRIPT.GuardianMove.CHASE:
				chase_stream = stream
				_expect_true(stream > 0, "%s runs its stream while chasing" % entry[0])
			elif move == SPIRIT_SCRIPT.GuardianMove.RECOVER:
				_expect_true(stream > 0 and stream <= chase_stream,
					"%s rests at half stream (%d of %d)" % [entry[0], stream, chase_stream])
			else:
				_expect_true(stream == 0, "%s holds its stream while %s"
					% [entry[0], SPIRIT_SCRIPT.GuardianMove.keys()[move]])
			if _failed > 0:
				return
		spirit.free()
	me.free()
	field.free()


func _finish() -> void:
	if _failed > 0:
		printerr("barrage test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("barrage test passed — ", _checked, " case(s)")
	quit(0)


func _expect_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	_checked += 1
	if absf(actual - expected) <= tolerance:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, "±", tolerance, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_checked += 1
	if actual:
		return
	_failed += 1
	printerr("  FAIL ", label)
