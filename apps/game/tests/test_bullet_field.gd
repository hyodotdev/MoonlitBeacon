extends SceneTree

## The bullets you weave through: one node holding a hundred and fifty, and the emitters that shoot them.
##
## Step a real `BulletField` and count real bullets. The rules that matter are the ones a player feels: a bullet
## flies where it was aimed, hits only inside its small circle, stops on a structure, fades and goes at the end
## of its range, and the field never holds more than its cap nor deletes a bullet to make room.

const STEP: float = 1.0 / 60.0

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_flight()
	_test_the_cap()
	_test_range_and_fade_distance()
	_test_hits()
	_test_structures()
	_test_curves_and_speed_ups()
	_test_clear_and_dissolve()
	_test_emitters()
	_test_emitter_spacing()
	_test_the_cost_of_a_full_field()
	_finish()


func _field() -> BulletField:
	var field: BulletField = BulletField.new()
	root.add_child(field)
	return field


func _step(field: BulletField, seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds - 0.0001:
		field._physics_process(STEP)
		elapsed += STEP


func _test_flight() -> void:
	var field: BulletField = _field()
	_expect_true(field.is_in_group(BulletField.GROUP), "the field can be found by its group")
	_expect_true(BulletField.of(field) == field, "and by `BulletField.of`")
	field.spawn(Vector2(10, 20), 0.0, 100.0, BulletField.Tint.PINK, 1000.0)
	field.spawn(Vector2(10, 20), PI * 0.5, 60.0, BulletField.Tint.MINT, 1000.0)
	_expect_equal(field.count(), 2, "two bullets are two rows")
	_step(field, 1.0)
	var at: PackedVector2Array = field.positions()
	_expect_approx(at[0].x, 110.0, 2.5, "a bullet flies where it was aimed at its speed")
	_expect_approx(at[0].y, 20.0, 0.5, "and stays on its line")
	_expect_approx(at[1].y, 80.0, 2.5, "a slower one flies slower, another way")
	field.spawn(Vector2.ZERO, 0.0, 100.0, 0, 1000.0, 0.0, 0.0, 0.1)
	_expect_approx(field.positions()[2].x, 10.0, 0.001, "a bullet due a tenth of a second ago starts that far along")
	field.free()


func _test_the_cap() -> void:
	var field: BulletField = _field()
	var placed: int = 0
	for index in BulletField.LIMIT + 50:
		if field.spawn(Vector2(float(index), 0.0), 0.0, 50.0):
			placed += 1
	_expect_equal(placed, BulletField.LIMIT, "the field takes no more than its cap")
	_expect_equal(field.count(), BulletField.LIMIT, "and holds exactly that many")
	_expect_equal(field.refused, 50, "it says how many it turned away")
	_expect_true(field.positions()[0].x == 0.0, "and it turns the new ones away, it never deletes one flying")
	_expect_true(field.is_full(), "it knows it is full")
	field.free()


func _test_range_and_fade_distance() -> void:
	var field: BulletField = _field()
	field.spawn(Vector2.ZERO, 0.0, 100.0, 0, 50.0)
	_step(field, 0.3)
	_expect_equal(field.count(), 1, "a bullet is still flying inside its range")
	_step(field, 0.4)
	_expect_equal(field.count(), 0, "and gone past it")
	_expect_true(BulletField.FADE_DISTANCE < 100.0, "the fade is shorter than a bullet's usual range")
	field.free()


func _test_hits() -> void:
	var field: BulletField = _field()
	var player: Node2D = Node2D.new()
	player.position = Vector2(60, 0)
	root.add_child(player)
	field.set_target(player)
	var hits: Array[Vector2] = []
	field.struck.connect(func(at: Vector2) -> void: hits.append(at))
	var chest_y: float = BulletField.PLAYER_BODY_OFFSET.y
	# One straight at the chest, one that grazes the drawn orb but not the hit circle, one that misses by a body.
	field.spawn(Vector2(0, chest_y), 0.0, 90.0, 0, 400.0)
	_step(field, 1.2)
	_expect_equal(hits.size(), 1, "a bullet aimed at the chest hits once")
	_expect_equal(field.count(), 0, "and is spent")
	hits.clear()
	field.spawn(Vector2(0, chest_y + BulletField.HIT_RADIUS - 0.5), 0.0, 90.0, 0, 400.0)
	_step(field, 1.2)
	_expect_equal(hits.size(), 1, "a bullet just inside the hit circle hits")
	hits.clear()
	field.spawn(Vector2(0, chest_y + BulletField.HIT_RADIUS + 1.5), 0.0, 90.0, 0, 400.0)
	_step(field, 1.2)
	_expect_equal(hits.size(), 0, "one just outside it goes by")
	_expect_true(BulletField.HIT_RADIUS < BulletField.DRAW_SIZE * 0.5, "the hit circle is smaller than the orb that is drawn")
	# A fast bullet does not tunnel through: it is a segment and not a point.
	hits.clear()
	field.spawn(Vector2(0, chest_y), 0.0, 4000.0, 0, 400.0)
	_step(field, 0.1)
	_expect_equal(hits.size(), 1, "a very fast bullet does not skip over the player")
	player.free()
	field.free()


func _test_structures() -> void:
	var field: BulletField = _field()
	# A tree of radius 12 at (100, 0): a bullet heading through its middle stops there, one passing wide does not.
	field.set("_centers", PackedVector2Array([Vector2(100, 0)]))
	field.set("_radii", PackedFloat32Array([12.0 + BulletField.TERRAIN_RADIUS]))
	field.spawn(Vector2(0, 0), 0.0, 90.0, 0, 600.0)
	field.spawn(Vector2(0, 40), 0.0, 90.0, 0, 600.0)
	_step(field, 1.6)
	_expect_equal(field.count(), 1, "a bullet stops on a structure and one that passes wide flies on")
	_expect_approx(field.positions()[0].y, 40.0, 0.5, "it is the one that went round")
	field.free()


func _test_curves_and_speed_ups() -> void:
	var field: BulletField = _field()
	field.spawn(Vector2.ZERO, 0.0, 100.0, 0, 2000.0, 0.0, 1.0)
	_step(field, 1.0)
	var heading: float = field.velocities()[0].angle()
	_expect_approx(heading, 1.0, 0.05, "a bullet that turns a radian a second has turned a radian in a second")
	_expect_approx(field.velocities()[0].length(), 100.0, 0.5, "and kept its speed")
	field.clear()
	field.spawn(Vector2.ZERO, 0.0, 40.0, 0, 2000.0, 60.0)
	_step(field, 1.0)
	_expect_approx(field.velocities()[0].length(), 100.0, 1.0, "a bullet that speeds up a little each second is faster later")
	field.free()


func _test_clear_and_dissolve() -> void:
	var field: BulletField = _field()
	for index in 60:
		field.spawn(Vector2(float(index) * 8.0, 0.0), 0.0, 10.0)
	field.dissolve()
	_expect_equal(field.count(), 0, "a guardian's bullets are all gone when they dissolve")
	_expect_true(field.get("_spark_pos").size() > 0 and field.get("_spark_pos").size() <= BulletField.SPARK_LIMIT,
		"and leave a few sparks, never more than the cap")
	_step(field, BulletField.SPARK_SECONDS + 0.1)
	_expect_equal(field.get("_spark_pos").size(), 0, "which go out")
	field.spawn(Vector2.ZERO, 0.0, 10.0)
	field.clear()
	_expect_equal(field.count(), 0, "clear leaves nothing")
	field.free()


func _test_emitters() -> void:
	var field: BulletField = _field()
	var spiral: BulletEmitter = BulletEmitter.spiral(3, 0.2, 80.0, 1.0, BulletField.Tint.MINT)
	spiral.restart()
	var placed: int = 0
	for step in 60:
		placed += spiral.tick(STEP, Vector2.ZERO, Vector2(100, 0), field)
	_expect_equal(placed, 15, "a three-armed spiral firing five times a second puts fifteen bullets in a second")
	var angles: Array[float] = []
	for velocity in field.velocities():
		angles.append(velocity.angle())
	# The first shot's three arms are a third of a turn apart.
	_expect_approx(wrapf(angles[1] - angles[0], 0.0, TAU), TAU / 3.0, 0.001, "the arms of a spiral are evenly spread")
	_expect_approx(wrapf(angles[3] - angles[0], -PI, PI), 1.0 * 0.2, 0.001, "and each shot has turned by spin times the interval")
	field.clear()

	var aimed: BulletEmitter = BulletEmitter.aimed(3, 0.6, 0.5, 90.0, BulletField.Tint.PINK)
	aimed.restart()
	for step in 20:
		aimed.tick(STEP, Vector2.ZERO, Vector2(0, 100), field)
	var fan: Array[float] = []
	for velocity in field.velocities():
		fan.append(velocity.angle())
	_expect_equal(fan.size(), 3, "an aimed three-way fan is three bullets")
	_expect_approx(fan[1], PI * 0.5, 0.001, "the middle one flies at the target")
	_expect_approx(fan[2] - fan[0], 0.6, 0.001, "the fan is as wide as it was told to be")
	field.clear()

	var ring: BulletEmitter = BulletEmitter.ring(8, 0.5, 60.0, 0.3, BulletField.Tint.GOLD)
	ring.restart()
	for step in 40:
		ring.tick(STEP, Vector2.ZERO, Vector2(100, 0), field)
	_expect_equal(field.count(), 16, "a ring of eight fired twice is sixteen")
	var first: float = field.velocities()[0].angle()
	var second: float = field.velocities()[8].angle()
	_expect_approx(wrapf(second - first, -PI, PI), 0.3, 0.001, "and the second ring has turned, so its gaps are somewhere new")
	field.clear()

	var wave: BulletEmitter = BulletEmitter.wave(0.5, 2.0, 0.1, 100.0, BulletField.Tint.SKY)
	wave.restart()
	var lowest: float = INF
	var highest: float = -INF
	for step in 240:
		wave.tick(STEP, Vector2.ZERO, Vector2(100, 0), field)
	for velocity in field.velocities():
		lowest = minf(lowest, velocity.angle())
		highest = maxf(highest, velocity.angle())
	_expect_true(highest <= 0.5001 and lowest >= -0.5001, "a wave sways no further than it was told to")
	_expect_true(highest - lowest > 0.6, "and does sway (%.2f rad)" % (highest - lowest))
	field.clear()

	var double_speed: BulletEmitter = BulletEmitter.aimed(1, 0.0, 0.5, 80.0, 0)
	double_speed.restart()
	var slow_total: int = 0
	var fast_total: int = 0
	var slow: BulletEmitter = BulletEmitter.aimed(1, 0.0, 0.5, 80.0, 0)
	slow.restart()
	for step in 180:
		slow_total += slow.tick(STEP, Vector2.ZERO, Vector2(100, 0), field, 1.0)
		fast_total += double_speed.tick(STEP, Vector2.ZERO, Vector2(100, 0), field, 2.0)
	_expect_true(fast_total >= slow_total * 2 - 1, "an emitter run at double tempo shoots twice as often (%d and %d)" % [slow_total, fast_total])
	field.free()


func _test_emitter_spacing() -> void:
	# A long tick still spaces its bullets by the interval: a bullet is where it would have been had it left on time.
	var field: BulletField = _field()
	var stream: BulletEmitter = BulletEmitter.aimed(1, 0.0, 0.05, 100.0, 0)
	stream.muzzle = 0.0
	stream.restart()
	stream.tick(0.2, Vector2.ZERO, Vector2(100, 0), field)
	var xs: Array[float] = []
	for at in field.positions():
		xs.append(at.x)
	xs.sort()
	_expect_equal(xs.size(), 4, "a tick four intervals long fires four bullets")
	for index in range(1, xs.size()):
		_expect_approx(xs[index] - xs[index - 1], 5.0, 0.001, "spaced by speed times interval (5 px)")
	field.free()


func _test_the_cost_of_a_full_field() -> void:
	# The reason for one node: a hundred and fifty bullets move and are tested every tick, all of them, cheaply.
	var field: BulletField = _field()
	var player: Node2D = Node2D.new()
	player.position = Vector2(5000, 5000)
	root.add_child(player)
	field.set_target(player)
	var ticks: int = 300
	var started: int = Time.get_ticks_usec()
	for tick in ticks:
		while not field.is_full():
			field.spawn(Vector2(float(tick % 40) * 9.0, float(field.count()) * 3.0), float(field.count()) * 0.21, 90.0, field.count() % 5, 400.0)
		field._physics_process(STEP)
	var per_tick: float = float(Time.get_ticks_usec() - started) / float(ticks) / 1000.0
	print("BULLET_FIELD_COST %.3f ms a tick with %d bullets" % [per_tick, field.count()])
	_expect_true(per_tick < 3.0, "a full field costs well under a frame a tick (%.2f ms)" % per_tick)
	player.free()
	field.free()


func _finish() -> void:
	if _failed > 0:
		printerr("bullet-field test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("bullet-field test passed — ", _checked, " case(s)")
	quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)


func _expect_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	_checked += 1
	if absf(actual - expected) <= tolerance:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, "±", tolerance, " actual=", actual)
