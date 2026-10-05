extends SceneTree

## Six-hero cross-facing head proportions: turning never shrinks the face.
##
## The side-walk donors painted the warden, knight and eclipse side heads
## about 15% smaller than their frontal heads; the packer now grows those
## three side heads to their frontal proportion while dancer, keeper and
## sage keep their audited match. This test re-measures the committed
## sheets independently of the packer (same audited face-core windows and
## skull rows, restated here): side visible-face height and skull width
## keep most of the frontal measure on every walk and idle frame. A probe
## that shrinks the side head back to the old undersized geometry fails
## every bound even pasted identically into all frames, so a future
## repack without the calibration fails here, not silently.
##
## Direct-callable: `pnpm godot:isolated --script res://tests/test_hero_face_proportions.gd`.

const HERO_IDS: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage"]
const CELL: Vector2i = Vector2i(144, 192)
const LEFT: int = 2
const INK: int = 64
## A core row counts toward the face with this many skin pixels. Matches
## the packer's HERO_FACE_ROW_INK.
const ROW_INK: int = 6
## Audited face-core windows (down, side) per hero, in cell pixels.
## Keeper has none: the beard mass runs continuous past the neck.
const FACE_CORE: Dictionary = {
	"warden": [Rect2i(62, 106, 26, 20), Rect2i(50, 100, 26, 23)],
	"dancer": [Rect2i(62, 104, 22, 18), Rect2i(50, 102, 12, 20)],
	"knight": [Rect2i(63, 102, 19, 16), Rect2i(55, 94, 19, 24)],
	"eclipse": [Rect2i(62, 107, 20, 14), Rect2i(52, 101, 18, 22)],
	"sage": [Rect2i(62, 107, 18, 10), Rect2i(54, 104, 16, 11)],
}
## Minimum side/down visible-face-height ratio per hero. Matches the packer.
const FACE_MIN: Dictionary = {
	"warden": 0.95, "dancer": 0.85, "knight": 0.80,
	"eclipse": 0.93, "sage": 0.72,
}
## Skull x windows and eye/temple-level rows per hero and facing.
const SKULL_X: Dictionary = {
	"warden": [Vector2i(45, 105), Vector2i(44, 102)],
	"dancer": [Vector2i(46, 98), Vector2i(42, 90)],
	"keeper": [Vector2i(36, 108), Vector2i(36, 108)],
	"knight": [Vector2i(48, 96), Vector2i(46, 96)],
	"eclipse": [Vector2i(44, 102), Vector2i(42, 92)],
	"sage": [Vector2i(50, 90), Vector2i(42, 82)],
}
const SKULL_ROWS: Dictionary = {
	"warden": [Vector2i(114, 122), Vector2i(105, 113)],
	"dancer": [Vector2i(109, 117), Vector2i(106, 114)],
	"keeper": [Vector2i(108, 114), Vector2i(108, 114)],
	"knight": [Vector2i(104, 112), Vector2i(99, 107)],
	"eclipse": [Vector2i(108, 116), Vector2i(104, 112)],
	"sage": [Vector2i(106, 114), Vector2i(103, 111)],
}
## Minimum side/down skull-width ratio per hero. Matches the packer.
const SKULL_MIN: Dictionary = {
	"warden": 0.85, "dancer": 0.90, "keeper": 0.90,
	"knight": 0.95, "eclipse": 0.92, "sage": 0.90,
}
## Canonical-head boundary per hero, in cell rows. Restates the packer's
## HERO_IDLE_NECK.
const HERO_NECK: Dictionary = {
	"warden": 130, "dancer": 130, "keeper": 128,
	"knight": 120, "eclipse": 126, "sage": 118,
}
## Calibration geometry the probe inverts: factor, anchor, head bottom.
const HEAD_CAL: Dictionary = {
	"warden": [1.18, Vector2(72, 84), 119],
	"knight": [1.17, Vector2(73, 100), 115],
	"eclipse": [1.19, Vector2(66, 84), 118],
}

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for hero_id in HERO_IDS:
		_test_hero(hero_id)
	_test_old_head_probes()
	_finish()


func _test_hero(hero_id: String) -> void:
	var walk: Image = Image.load_from_file(
		"res://assets/custom/actors/heroes/%s/walk.png" % hero_id)
	var idle: Image = Image.load_from_file(
		"res://assets/custom/actors/heroes/%s/idle.png" % hero_id)
	_expect_true(walk != null and idle != null,
		"%s proportion sources load" % hero_id)
	if walk == null or idle == null:
		return
	for frame in 4:
		_test_frame(hero_id, "walk", walk, frame)
		_test_frame(hero_id, "idle", idle, frame)


func _test_frame(hero_id: String, sheet: String, image: Image, frame: int) -> void:
	var tag: String = "%s %s frame %d" % [hero_id, sheet, frame]
	var front: Image = image.get_region(
		Rect2i(0, frame * CELL.y, CELL.x, CELL.y))
	var side: Image = image.get_region(
		Rect2i(LEFT * CELL.x, frame * CELL.y, CELL.x, CELL.y))
	if hero_id in FACE_CORE:
		var down_h: int = _face_height(front, hero_id, 0)
		var side_h: int = _face_height(side, hero_id, 1)
		_expect_true(down_h > 0 and side_h > 0,
			"%s face core sees a face" % tag)
		if down_h > 0 and side_h > 0:
			_expect_true(float(side_h) / float(down_h) \
				>= float(FACE_MIN[hero_id]),
				"%s side face %d keeps %.2f of the %d front" % [
					tag, side_h, float(side_h) / float(down_h), down_h])
	var down_w: int = _skull_width(front, hero_id, 0)
	var side_w: int = _skull_width(side, hero_id, 1)
	_expect_true(down_w > 0 and side_w > 0,
		"%s skull rows see a head" % tag)
	if down_w > 0 and side_w > 0:
		_expect_true(float(side_w) / float(down_w) \
			>= float(SKULL_MIN[hero_id]),
			"%s side skull %d keeps %.2f of the %d front" % [
				tag, side_w, float(side_w) / float(down_w), down_w])


## The old undersized side head, reconstructed by inverting the packer's
## calibration geometry, is rejected in every walk and idle frame even
## pasted identically into all of them. The resampling smear reads the
## reconstructed face rows slightly tall, so the skull bound carries the
## rejection here; the exact old bytes fail both bounds in the Python
## control (tools/test_hero_face_checks.py). A repack without the
## calibration fails here.
func _test_old_head_probes() -> void:
	for hero_id in HEAD_CAL:
		var neck: int = int(HERO_NECK[hero_id])
		var walk: Image = Image.load_from_file(
			"res://assets/custom/actors/heroes/%s/walk.png" % hero_id)
		_expect_true(walk != null, "%s probe source loads" % hero_id)
		if walk == null:
			continue
		var old_head: Image = _shrunk_side_head(walk, hero_id, neck)
		for sheet in ["walk", "idle"]:
			var image: Image = Image.load_from_file(
				"res://assets/custom/actors/heroes/%s/%s.png"
				% [hero_id, sheet])
			_expect_true(image != null,
				"%s probe %s loads" % [hero_id, sheet])
			if image == null:
				continue
			for frame in 4:
				image.blit_rect(old_head,
					Rect2i(0, 0, CELL.x, neck),
					Vector2i(LEFT * CELL.x, frame * CELL.y))
			for frame in 4:
				var front: Image = image.get_region(
					Rect2i(0, frame * CELL.y, CELL.x, CELL.y))
				var side: Image = image.get_region(
					Rect2i(LEFT * CELL.x, frame * CELL.y, CELL.x, CELL.y))
				var down_h: int = _face_height(front, hero_id, 0)
				var side_h: int = _face_height(side, hero_id, 1)
				var face_ok: bool = down_h > 0 and side_h > 0 \
					and float(side_h) / float(down_h) \
						>= float(FACE_MIN[hero_id])
				var down_w: int = _skull_width(front, hero_id, 0)
				var side_w: int = _skull_width(side, hero_id, 1)
				var skull_ok: bool = down_w > 0 and side_w > 0 \
					and float(side_w) / float(down_w) \
						>= float(SKULL_MIN[hero_id])
				_expect_true(not (face_ok and skull_ok),
					"%s old side head rejected in %s frame %d "
					% [hero_id, sheet, frame]
					+ "(face %d/%d, skull %d/%d)" % [
						side_h, down_h, side_w, down_w])


## The current calibrated side band scaled back down by the calibration
## factor about its anchor: the old undersized head geometry.
func _shrunk_side_head(image: Image, hero_id: String, neck: int) -> Image:
	var specs: Array = HEAD_CAL[hero_id]
	var factor: float = float(specs[0])
	var anchor: Vector2 = specs[1]
	var band: Image = image.get_region(
		Rect2i(LEFT * CELL.x, 0, CELL.x, neck))
	var shrunk: Image = band.duplicate() as Image
	shrunk.resize(
		maxi(1, roundi(float(CELL.x) / factor)),
		maxi(1, roundi(float(neck) / factor)),
		Image.INTERPOLATE_NEAREST)
	var probe: Image = band.duplicate() as Image
	probe.blit_rect(shrunk,
		Rect2i(0, 0, shrunk.get_width(), shrunk.get_height()),
		Vector2i(
			roundi(anchor.x - anchor.x / factor),
			roundi(anchor.y - anchor.y / factor)))
	return probe


## Visible-face rows in the audited core window, first to last.
func _face_height(cell: Image, hero_id: String, slot: int) -> int:
	var window: Rect2i = (FACE_CORE[hero_id] as Array)[slot]
	var first: int = -1
	var last: int = -1
	for y in range(window.position.y, window.end.y):
		var ink: int = 0
		for x in range(window.position.x, window.end.x):
			var pixel: Color = cell.get_pixel(x, y)
			if int(round(pixel.a * 255.0)) >= INK \
				and _face_skin(hero_id, pixel):
				ink += 1
		if ink >= ROW_INK:
			if first < 0:
				first = y
			last = y
	return last - first + 1 if first >= 0 else 0


## Median opaque span over the calibrated skull rows.
func _skull_width(cell: Image, hero_id: String, slot: int) -> int:
	var xrange: Vector2i = (SKULL_X[hero_id] as Array)[slot]
	var rows: Vector2i = (SKULL_ROWS[hero_id] as Array)[slot]
	var spans: Array[int] = []
	for y in range(rows.x, rows.y + 1):
		var lo: int = xrange.y
		var hi: int = xrange.x
		for x in range(xrange.x, xrange.y):
			if int(round(cell.get_pixel(x, y).a * 255.0)) >= INK:
				lo = mini(lo, x)
				hi = maxi(hi, x)
		if hi >= lo:
			spans.append(hi - lo + 1)
	spans.sort()
	return spans[spans.size() / 2] if not spans.is_empty() else 0


## Warm skin at one opaque pixel, plus the keeper beard mass.
func _face_skin(hero_id: String, pixel: Color) -> bool:
	var red: int = int(round(pixel.r * 255.0))
	var green: int = int(round(pixel.g * 255.0))
	var blue: int = int(round(pixel.b * 255.0))
	if hero_id == "keeper":
		if red >= 150 and green >= 100 and red - green >= 15 \
			and green >= blue - 5:
			return true
		return red >= 120 and green >= 70 and blue >= 40 \
			and red - green >= 25 and green - blue >= 10
	return red >= 170 and green >= 130 and blue >= 110 \
		and red - blue >= 12 and red >= green - 5 and green >= blue - 12


func _finish() -> void:
	if _failed > 0:
		printerr("hero-face-proportions test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("hero-face-proportions test passed — ", _checked, " case(s)")
	quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
