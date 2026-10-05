extends SceneTree

## Six-hero side-walk gait: the same physical leg alternates ahead/behind.
##
## The donors ship left-facing contact / recover / opposite-contact /
## recover rows; the right column is the exact mirror of the left. This
## test reads the production walk.png bytes and proves the loop walks:
## contact rows plant two feet wide apart with the near (lighter) boot
## trading sides between rows 0 and 2, recover rows narrow onto one
## support, heads and torsos hold still, no side cell clips its gutters,
## and the idle, portrait and down/up walk bytes keep their committed
## hash. Brief 186 rebuilt the idle stance (standing, not striding) and
## fitted each down/up column at one scale, so the hash locks the new
## standing art. Thresholds come from the baked sheets with room to
## spare; see notes/workflow/muse/gait-131-implementation.md.
##
## Direct-callable: `pnpm godot:isolated --script res://tests/test_hero_gait.gd`.

const HERO_IDS: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage"]
const CELL: Vector2i = Vector2i(144, 192)
const LEFT: int = 2
const RIGHT: int = 3
## Sole band: the bottom twelve rows of the cell.
const SOLE_TOP: int = 180
## Head/torso band: the top 110 rows, clear of every stride.
const TORSO_BOTTOM: int = 110
const INK: float = 32.0 / 255.0
## Contact rows plant at least this wide (measured 57-77).
const MIN_CONTACT_SPREAD: int = 50
## Contact rows clear the widest recover row by this (measured 20-33).
const SPREAD_MARGIN: int = 12
## The leading near boot reads this much lighter than the trailing far
## boot in the sole band, 0-255 (measured 13-61).
const BRIGHTNESS_MARGIN: float = 8.0
## Head/torso registration across the four rows of one column.
const TOP_WOBBLE: int = 2
const TORSO_CENTER_WOBBLE: float = 3.0
const TORSO_H_WOBBLE: int = 2
const TORSO_W_WOBBLE: int = 6
## Frame-contract gutters: side cells keep 4px left/right/top clear.
const GUTTER_SIDE: int = 4
const GUTTER_TOP: int = 4
## Committed bytes per hero: SHA-256 over idle.png file bytes, then
## portrait.png file bytes, then the decoded walk down/up columns
## (x0-288) RGBA bytes. Minted from the standing-stance bake with one
## canonical head per column; any drift in the idle stance, the
## portrait, the down/up columns or a walk head fails here.
const PRESERVED: Dictionary = {
	"warden": "e5f027b553e27a5993e7355b99d11bf4373601864a62027092e3a206093416c0",
	"dancer": "21ca3c920ca4d69ce6d7d57abba6e90b54242704d74864f9255598fc63952548",
	"keeper": "fbd114d28ac86aabdc3e65c0451ce64d2d3ea16535d76b7adbf6763dd3651187",
	"knight": "93b5232e2494ad96620f16677d941217ecde7184555081bf471cfac21643baaf",
	"eclipse": "82c4efcf1cf8c2e552ec367d9c92654389a4246719e45bb8e3cd645427011c87",
	"sage": "6db134b10e4b593d122e2c369dcd7986af65779d6d76d826d13d12f698a17932",
}

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for hero_id in HERO_IDS:
		_test_hero(hero_id)
	_finish()


func _test_hero(hero_id: String) -> void:
	var walk: Image = Image.load_from_file(
		"res://assets/custom/actors/heroes/%s/walk.png" % hero_id)
	_expect_true(walk != null, "%s walk source loads" % hero_id)
	if walk == null:
		return
	for column in [LEFT, RIGHT]:
		_test_stride(walk, hero_id, column)
		_test_registration(walk, hero_id, column)
		_test_gutters(walk, hero_id, column)
		_test_rows_distinct(walk, hero_id, column)
	_test_mirror(walk, hero_id)
	_test_preserved(hero_id)


## Contact rows plant wide, recover rows narrow; the near boot trades
## sides between the two contacts. Column 2 faces left (row 0 leads
## left), column 3 is its mirror (row 0 leads right).
func _test_stride(walk: Image, hero_id: String, column: int) -> void:
	var tag: String = "%s %s" % [
		hero_id, "left" if column == LEFT else "right"]
	var spreads: Array[int] = []
	var deltas: Array[float] = []
	for row in 4:
		var sole: Dictionary = _sole_metrics(walk, column, row)
		spreads.append(int(sole["spread"]))
		deltas.append(float(sole["delta"]))
	var contact: int = mini(spreads[0], spreads[2])
	var passing: int = maxi(spreads[1], spreads[3])
	_expect_true(contact >= MIN_CONTACT_SPREAD,
		"%s contacts plant wide (%d)" % [tag, contact])
	_expect_true(contact > passing + SPREAD_MARGIN,
		"%s contacts %d clear recoveries %d" % [tag, contact, passing])
	# Delta reads near-minus-far along the walk: positive when the left
	# boot is lighter. Left column row 0 leads left, row 2 trails
	# right; the mirrored right column reads the opposite way.
	var row0_sign: float = 1.0 if column == LEFT else -1.0
	var row2_sign: float = -row0_sign
	_expect_true(deltas[0] * row0_sign >= BRIGHTNESS_MARGIN,
		"%s row 0 near boot leads (%.1f)" % [tag, deltas[0]])
	_expect_true(deltas[2] * row2_sign >= BRIGHTNESS_MARGIN,
		"%s row 2 near boot trades sides (%.1f)" % [tag, deltas[2]])


## Sole-band ink extent and left/right mean brightness at alpha >= 32.
## Delta is left-minus-right luminance on 0-255.
func _sole_metrics(walk: Image, column: int, row: int) -> Dictionary:
	var origin := Vector2i(column * CELL.x, row * CELL.y)
	var lo: int = CELL.x
	var hi: int = -1
	for y in range(SOLE_TOP, CELL.y):
		for x in CELL.x:
			if walk.get_pixel(origin.x + x, origin.y + y).a >= INK:
				lo = mini(lo, x)
				hi = maxi(hi, x)
	if hi < 0:
		return {"spread": 0, "delta": 0.0}
	var mid: float = (float(lo) + float(hi)) * 0.5
	var left_sum: float = 0.0
	var left_count: int = 0
	var right_sum: float = 0.0
	var right_count: int = 0
	for y in range(SOLE_TOP, CELL.y):
		for x in CELL.x:
			var ink: Color = walk.get_pixel(
				origin.x + x, origin.y + y)
			if ink.a < INK:
				continue
			var tone: float = (
				0.299 * ink.r + 0.587 * ink.g + 0.114 * ink.b) * 255.0
			if float(x) <= mid:
				left_sum += tone
				left_count += 1
			else:
				right_sum += tone
				right_count += 1
	var delta: float = 0.0
	if left_count > 0 and right_count > 0:
		delta = left_sum / float(left_count) \
			- right_sum / float(right_count)
	return {"spread": hi - lo, "delta": delta}


## Heads and torsos hold still while the legs work: the top-band ink
## box barely moves across the four rows of one column.
func _test_registration(walk: Image, hero_id: String, column: int) -> void:
	var tag: String = "%s %s" % [
		hero_id, "left" if column == LEFT else "right"]
	var boxes: Array[Rect2i] = []
	for row in 4:
		boxes.append(_top_box(walk, column, row))
	var top_lo: int = 192
	var top_hi: int = -1
	var center_lo: float = 999.0
	var center_hi: float = -1.0
	var w_lo: int = 999
	var w_hi: int = -1
	var h_lo: int = 999
	var h_hi: int = -1
	for box in boxes:
		top_lo = mini(top_lo, box.position.y)
		top_hi = maxi(top_hi, box.position.y)
		var center: float = float(box.position.x) \
			+ float(box.size.x) * 0.5
		center_lo = minf(center_lo, center)
		center_hi = maxf(center_hi, center)
		w_lo = mini(w_lo, box.size.x)
		w_hi = maxi(w_hi, box.size.x)
		h_lo = mini(h_lo, box.size.y)
		h_hi = maxi(h_hi, box.size.y)
	_expect_true(top_hi - top_lo <= TOP_WOBBLE,
		"%s head line holds (%d-%d)" % [tag, top_lo, top_hi])
	_expect_true(center_hi - center_lo <= TORSO_CENTER_WOBBLE,
		"%s torso center holds (%.1f-%.1f)"
		% [tag, center_lo, center_hi])
	_expect_true(h_hi - h_lo <= TORSO_H_WOBBLE,
		"%s torso height holds (%d-%d)" % [tag, h_lo, h_hi])
	_expect_true(w_hi - w_lo <= TORSO_W_WOBBLE,
		"%s torso width holds (%d-%d)" % [tag, w_lo, w_hi])


func _top_box(walk: Image, column: int, row: int) -> Rect2i:
	var origin := Vector2i(column * CELL.x, row * CELL.y)
	var lo := Vector2i(CELL.x, CELL.y)
	var hi := Vector2i(-1, -1)
	for y in TORSO_BOTTOM:
		for x in CELL.x:
			if walk.get_pixel(origin.x + x, origin.y + y).a >= INK:
				lo.x = mini(lo.x, x)
				lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x)
				hi.y = maxi(hi.y, y)
	return Rect2i(lo, hi - lo + Vector2i(1, 1))


## No side cell touches its 4px side/top gutters at any alpha; feet
## plant on the bottom edge.
func _test_gutters(walk: Image, hero_id: String, column: int) -> void:
	var tag: String = "%s %s" % [
		hero_id, "left" if column == LEFT else "right"]
	for row in 4:
		var origin := Vector2i(column * CELL.x, row * CELL.y)
		var touches_side: bool = false
		var touches_top: bool = false
		var plants: bool = false
		for y in CELL.y:
			for x in CELL.x:
				if walk.get_pixel(origin.x + x, origin.y + y).a <= 0.0:
					continue
				if x < GUTTER_SIDE or x >= CELL.x - GUTTER_SIDE:
					touches_side = true
				if y < GUTTER_TOP:
					touches_top = true
				if y == CELL.y - 1:
					plants = true
		_expect_false(touches_side,
			"%s row %d keeps its side gutters" % [tag, row])
		_expect_false(touches_top,
			"%s row %d keeps its top gutter" % [tag, row])
		_expect_true(plants,
			"%s row %d plants its feet" % [tag, row])


## Four genuinely different stride poses per side, never a still or a
## duplicated recovery frame.
func _test_rows_distinct(walk: Image, hero_id: String, column: int) -> void:
	var tag: String = "%s %s" % [
		hero_id, "left" if column == LEFT else "right"]
	var rows: Array[PackedByteArray] = []
	for row in 4:
		rows.append(walk.get_region(Rect2i(
			column * CELL.x, row * CELL.y, CELL.x, CELL.y)).get_data())
	for first in 4:
		for second in range(first + 1, 4):
			_expect_false(rows[first] == rows[second],
				"%s rows %d and %d differ" % [tag, first, second])


## The right column is the exact mirror of the left, row by row.
func _test_mirror(walk: Image, hero_id: String) -> void:
	for row in 4:
		var left: PackedByteArray = walk.get_region(Rect2i(
			LEFT * CELL.x, row * CELL.y, CELL.x, CELL.y)).get_data()
		var right: PackedByteArray = walk.get_region(Rect2i(
			RIGHT * CELL.x, row * CELL.y, CELL.x, CELL.y)).get_data()
		_expect_true(_is_mirror(left, right),
			"%s row %d mirrors exactly" % [hero_id, row])


func _is_mirror(left: PackedByteArray, right: PackedByteArray) -> bool:
	if left.size() != CELL.x * CELL.y * 4:
		return false
	if right.size() != left.size():
		return false
	for y in CELL.y:
		for x in CELL.x:
			var a: int = (y * CELL.x + x) * 4
			var b: int = (y * CELL.x + CELL.x - 1 - x) * 4
			for channel in 4:
				if left[a + channel] != right[b + channel]:
					return false
	return true


## Idle, portraits and down/up walk columns keep their committed bytes:
## the stance bake minted them, and any drift fails here.
func _test_preserved(hero_id: String) -> void:
	var root: String = "res://assets/custom/actors/heroes/%s" % hero_id
	var idle: PackedByteArray = FileAccess.get_file_as_bytes(
		"%s/idle.png" % root)
	var portrait: PackedByteArray = FileAccess.get_file_as_bytes(
		"%s/portrait.png" % root)
	var walk: Image = Image.load_from_file("%s/walk.png" % root)
	_expect_true(idle.size() > 0 and portrait.size() > 0 \
		and walk != null,
		"%s preserved sources load" % hero_id)
	if idle.size() == 0 or portrait.size() == 0 or walk == null:
		return
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(idle)
	hash.update(portrait)
	hash.update(walk.get_region(
		Rect2i(0, 0, CELL.x * 2, CELL.y * 4)).get_data())
	_expect_equal(hash.finish().hex_encode(), PRESERVED[hero_id],
		"%s idle, portrait and down/up bytes preserved" % hero_id)


func _finish() -> void:
	if _failed > 0:
		printerr("hero-gait test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("hero-gait test passed — ", _checked, " case(s)")
	quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)


func _expect_false(actual: bool, label: String) -> void:
	_expect_equal(actual, false, label)
