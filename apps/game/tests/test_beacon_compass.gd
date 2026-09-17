extends Node

## Compass off-screen check regression.
##
## Prevents the guardian-fight report "the arrow keeps blinking in front of the boss and is confusing"
## from coming back. The check uses the whole safe region and the target's drawn radius,
## Hide and show thresholds differ (hysteresis), and a brief
## stray must not show the arrow. Wait time is not wall-clock;
## it is caller-supplied delta accumulation, so this test also mimics game time.

const COMPASS_SCRIPT: Script = preload("res://scripts/ui/beacon_compass.gd")

## Safe region matching the internal game resolution. The default check uses world coords equal to
## screen coords with no camera, then attach a live play zoom camera at the end.
const SAFE_RECT: Rect2 = Rect2(0, 0, 808, 360)
## Half a guardian sheet (64×64) × body_scale 0.94, approximated.
const GUARDIAN_EXTENT: float = 30.0
const WORLD_CAMERA_ZOOM: float = 4.0 / 3.0
## One 60fps frame.
const FRAME: float = 1.0 / 60.0

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var compass: Control = COMPASS_SCRIPT.new() as Control
	add_child(compass)
	await get_tree().process_frame

	var from: Vector2 = SAFE_RECT.get_center()

	# Old false positive: the top HUD inset (126px) made a perfectly
	# treated a visible boss as "off screen". It must stay hidden now.
	_point(compass, Vector2(404, 60), from)
	_expect_false(_showing(compass), "no arrow for a boss visible at the top of the screen")

	# A boss whose origin is just off screen but whose body still overlaps.
	_point(compass, Vector2(404, -20), from)
	_expect_false(_showing(compass), "no arrow when the body still overlaps the screen")

	# Border zone (off screen but inside SHOW_MARGIN) — must not appear even if it flickers.
	_point(compass, Vector2(404, -60), from)
	_expect_false(_showing(compass), "does not appear in the border zone")

	# Even fully off screen, it must not appear before SHOW_DELAY_SECONDS is filled.
	_point(compass, Vector2(404, -240), from, FRAME)
	_expect_false(_showing(compass), "does not appear on the first frame right after straying")

	# Appears once consecutive off-screen frames fill the delay.
	for _i in 30:
		_point(compass, Vector2(404, -240), from, FRAME)
	_expect_true(_showing(compass), "the arrow appears once the delay is filled")
	_expect_true(compass.visible, "a shown arrow is actually drawn")

	# Hides immediately when the body is visible again.
	_point(compass, Vector2(404, 60), from)
	_expect_false(_showing(compass), "hides immediately when the body is visible")

	# A charge that overshoots the screen edge for a half-beat and comes back — the arrow must not pop.
	for _i in 10:
		_point(compass, Vector2(404, -240), from, FRAME)
	_point(compass, Vector2(404, 60), from)
	_expect_false(_showing(compass), "a half-beat stray does not pop the arrow")

	# If the body is visible during stray wait, the wait resets too.
	for _i in 10:
		_point(compass, Vector2(404, -240), from, FRAME)
	_expect_equal(
		snappedf(float(compass.get("_show_wait_seconds")), 0.001),
		snappedf(FRAME * 10.0, 0.001),
		"stray wait accumulates frame delta")
	_point(compass, Vector2(404, 60), from)
	_expect_equal(
		float(compass.get("_show_wait_seconds")), -1.0,
		"stray wait resets when the body is visible")

	# If there is nothing to point at, reset the wait too.
	for _i in 10:
		_point(compass, Vector2(404, -240), from, FRAME)
	compass.point_to(
		BeaconCompass.Mark.NONE, Vector2.ZERO, from, SAFE_RECT)
	_expect_false(_showing(compass), "no arrow when there is no target")
	_expect_equal(
		float(compass.get("_show_wait_seconds")), -1.0,
		"stray wait resets when there is no target")

	# With a zoomed camera, a 30px world radius becomes a 40px screen radius. If the center is
	# even if the center is 35px above the screen, 5px of body still shows, so an already-visible arrow must
	# Using the radius in world coords as-is keeps this case visible.
	var camera := Camera2D.new()
	camera.position = from
	camera.zoom = Vector2.ONE * WORLD_CAMERA_ZOOM
	add_child(camera)
	camera.make_current()
	await get_tree().process_frame
	for _i in 30:
		_point_at_screen(compass, Vector2(404, -240), from, FRAME)
	_expect_true(_showing(compass), "still points at a distant guardian with a zoomed camera")
	_point_at_screen(compass, Vector2(404, -35), from)
	_expect_false(
		_showing(compass),
		"arrow hides when a zoomed guardian body still overlaps the screen")

	if _failed > 0:
		printerr("compass off-screen test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("compass off-screen test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _point(
		compass: Control, target: Vector2, from: Vector2,
		delta: float = 0.0) -> void:
	compass.point_to(
		BeaconCompass.Mark.GUARDIAN, target, from, SAFE_RECT,
		GUARDIAN_EXTENT, delta)


func _point_at_screen(
		compass: Control, screen_target: Vector2, from: Vector2,
		delta: float = 0.0) -> void:
	var world_target: Vector2 = get_viewport().get_canvas_transform() \
		.affine_inverse() * screen_target
	_point(compass, world_target, from, delta)


func _showing(compass: Control) -> bool:
	return bool(compass.get("_showing"))


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
