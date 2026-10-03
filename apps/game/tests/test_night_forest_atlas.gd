extends SceneTree

## Night-forest painted-atlas addressing: the intro diorama reads nature.png at 3x.
##
## The accepted painted `nature.png` is 1152x1008, three source pixels per
## logical pixel, and the room runtime already scales its KIND rects by
## `art_zoom` and draws at the reciprocal (`room.gd`). The static intro
## diorama was left behind at 1x regions, so every tree sampled a third of
## its frame and the title forest showed chopped fragments. Each nature
## sprite now carries its region times 3, draws at exactly 1/3, and smooths
## node-locally, which keeps the original logical placement and extent:
## top-left anchored (`centered = false`), same position, same draw size.
##
## This walks the actual sprites, pins the 34 logical families and their
## counts, pins the ground repeat mapping it must not disturb, and trips
## on one old 1x region restored as a negative control.
##
## Direct-callable: `pnpm godot:isolated --script res://tests/test_night_forest_atlas.gd`.

const NIGHT_FOREST: PackedScene = preload("res://scenes/gameplay/night_forest.tscn")
const NATURE_PATH: String = "res://assets/custom/world/terrain/nature.png"
const NATURE_SIZE: Vector2i = Vector2i(1152, 1008)
const ART_ZOOM: float = 3.0
const NATURE_COUNT: int = 1280
const SCALE_TOLERANCE: float = 0.00001
const DRAW_TOLERANCE: float = 0.01
const GRID_TOLERANCE: float = 0.001

const GROUND_PATH: String = "res://assets/custom/world/terrain/forest_floor.png"
const GROUND_REGION: Rect2 = Rect2(0, 0, 1800, 940)

## The original logical (1x) families and how many sprites each holds, from
## `tools/build_title_forest.py` KIND plus its grass rows. Region divided by
## 3 must land here or the diorama changed shape, not just density.
const LOGICAL_FAMILIES: Dictionary = {
	Rect2i(0, 0, 32, 32): 45,
	Rect2i(0, 32, 64, 48): 154,
	Rect2i(0, 80, 64, 48): 75,
	Rect2i(0, 128, 32, 32): 9,
	Rect2i(0, 160, 16, 16): 26,
	Rect2i(16, 160, 16, 16): 29,
	Rect2i(32, 0, 32, 32): 66,
	Rect2i(32, 128, 32, 32): 7,
	Rect2i(32, 160, 16, 16): 34,
	Rect2i(48, 160, 16, 16): 38,
	Rect2i(64, 0, 32, 32): 34,
	Rect2i(64, 32, 64, 48): 62,
	Rect2i(64, 128, 16, 16): 16,
	Rect2i(64, 144, 16, 16): 20,
	Rect2i(64, 160, 16, 16): 36,
	Rect2i(80, 128, 16, 16): 23,
	Rect2i(80, 144, 16, 16): 39,
	Rect2i(80, 160, 16, 16): 33,
	Rect2i(96, 0, 32, 32): 29,
	Rect2i(96, 128, 32, 32): 41,
	Rect2i(96, 160, 16, 16): 28,
	Rect2i(112, 160, 16, 16): 24,
	Rect2i(128, 160, 16, 16): 38,
	Rect2i(144, 160, 16, 16): 37,
	Rect2i(160, 160, 16, 16): 28,
	Rect2i(192, 144, 16, 16): 54,
	Rect2i(208, 128, 32, 32): 12,
	Rect2i(240, 144, 16, 16): 23,
	Rect2i(256, 0, 32, 32): 25,
	Rect2i(256, 32, 64, 48): 72,
	Rect2i(256, 128, 32, 32): 7,
	Rect2i(288, 0, 32, 32): 27,
	Rect2i(288, 144, 16, 16): 23,
	Rect2i(320, 32, 64, 48): 66,
}

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_sheet()
	_test_ground()
	_test_nature_walk()
	_test_negative_control()
	_finish()


## The 3x premise itself: without this sheet size the grid means nothing.
func _test_sheet() -> void:
	var sheet: Texture2D = load(NATURE_PATH) as Texture2D
	_expect_true(sheet != null, "nature sheet loads")
	if sheet == null:
		return
	_expect_equal(
		Vector2i(sheet.get_size()), NATURE_SIZE, "nature sheet is 3x dense")


## The ground repeat path stays exactly as shipped: same floor sheet, same
## tiled region, same repeat mapping, unit scale. This patch must not move it.
func _test_ground() -> void:
	var forest: Node2D = NIGHT_FOREST.instantiate() as Node2D
	root.add_child(forest)
	var ground: Sprite2D = forest.get_node("Ground") as Sprite2D
	_expect_true(ground != null, "night forest Ground node")
	if ground == null:
		forest.queue_free()
		return
	_expect_true(ground.texture != null, "ground texture present")
	if ground.texture != null:
		_expect_equal(
			ground.texture.resource_path, GROUND_PATH, "ground floor sheet")
	_expect_equal(ground.region_rect, GROUND_REGION, "ground tiled region")
	_expect_equal(
		ground.texture_repeat,
		CanvasItem.TEXTURE_REPEAT_ENABLED,
		"ground repeat mapping")
	_expect_equal(ground.scale, Vector2.ONE, "ground unit scale")
	forest.queue_free()


## Every nature sprite: region on the 3x grid inside the sheet, reciprocal
## draw scale, node-local smoothing, top-left anchoring, and a logical draw
## size equal to the region over 3 within a hundredth of a pixel. Two
## framing anchors pin original placement; the family tally pins extent.
func _test_nature_walk() -> void:
	var forest: Node2D = NIGHT_FOREST.instantiate() as Node2D
	root.add_child(forest)
	var nature: Array[Sprite2D] = []
	for node in forest.find_children("*", "Sprite2D", true, false):
		var sprite: Sprite2D = node as Sprite2D
		if sprite != null and sprite.texture != null \
				and sprite.texture.resource_path == NATURE_PATH:
			nature.append(sprite)
	_expect_equal(nature.size(), NATURE_COUNT, "nature sprite count")
	var off_grid: Array[String] = []
	var out_of_bounds: Array[String] = []
	var bad_filter: Array[String] = []
	var bad_scale: Array[String] = []
	var bad_draw: Array[String] = []
	var anchored: Array[String] = []
	var unknown_family: Array[String] = []
	var tally: Dictionary = {}
	for sprite in nature:
		if not _on_zoom_grid(sprite.region_rect):
			off_grid.append(sprite.name)
		if not _inside_sheet(sprite.region_rect):
			out_of_bounds.append(sprite.name)
		if sprite.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR:
			bad_filter.append(sprite.name)
		if (sprite.scale - Vector2.ONE / ART_ZOOM).length() > SCALE_TOLERANCE:
			bad_scale.append(sprite.name)
		if (_drawn_size(sprite) - sprite.region_rect.size / ART_ZOOM).length() \
				> DRAW_TOLERANCE:
			bad_draw.append(sprite.name)
		if sprite.centered:
			anchored.append(sprite.name)
		var logical := Rect2i(
			Vector2i(sprite.region_rect.position / ART_ZOOM),
			Vector2i(sprite.region_rect.size / ART_ZOOM))
		if LOGICAL_FAMILIES.has(logical):
			tally[logical] = int(tally.get(logical, 0)) + 1
		else:
			unknown_family.append(sprite.name)
	_expect_equal(off_grid.size(), 0, "regions on the 3x grid" + _names(off_grid))
	_expect_equal(
		out_of_bounds.size(), 0, "regions inside the sheet" + _names(out_of_bounds))
	_expect_equal(
		bad_filter.size(), 0, "node-local smoothing" + _names(bad_filter))
	_expect_equal(
		bad_scale.size(), 0, "reciprocal draw scale" + _names(bad_scale))
	_expect_equal(
		bad_draw.size(), 0, "compensated logical bounds" + _names(bad_draw))
	_expect_equal(
		anchored.size(), 0, "top-left anchoring" + _names(anchored))
	_expect_equal(
		unknown_family.size(), 0, "known logical families" + _names(unknown_family))
	_expect_equal(tally, LOGICAL_FAMILIES, "logical families and counts")
	_expect_equal(
		(forest.get_node("Details/D000") as Sprite2D).position,
		Vector2(380, 112),
		"detail anchor placement")
	_expect_equal(
		(forest.get_node("Trees/T000") as Sprite2D).position,
		Vector2(388, -179),
		"tree anchor placement")
	forest.queue_free()


## The guard must catch the defect it guards: one old 1x region restored on
## a sprite trips the same predicate the walk uses, and restoring the 3x
## region returns it to green. In-memory only; the scene file is untouched.
func _test_negative_control() -> void:
	var forest: Node2D = NIGHT_FOREST.instantiate() as Node2D
	root.add_child(forest)
	var sprite: Sprite2D = null
	for node in forest.find_children("*", "Sprite2D", true, false):
		var candidate: Sprite2D = node as Sprite2D
		if candidate != null and candidate.texture != null \
				and candidate.texture.resource_path == NATURE_PATH:
			sprite = candidate
			break
	_expect_true(sprite != null, "negative control sprite found")
	if sprite == null:
		forest.queue_free()
		return
	_expect_true(_sprite_ok(sprite), "control sprite starts green")
	var shipped: Rect2 = sprite.region_rect
	sprite.region_rect = Rect2(256, 128, 32, 32)
	_expect_false(_sprite_ok(sprite), "old 1x region trips the guard")
	sprite.region_rect = shipped
	_expect_true(_sprite_ok(sprite), "restored 3x region returns to green")
	forest.queue_free()


## The single predicate the walk and the negative control share.
func _sprite_ok(sprite: Sprite2D) -> bool:
	if sprite.texture == null \
			or sprite.texture.resource_path != NATURE_PATH:
		return false
	if not sprite.region_enabled:
		return false
	if not _on_zoom_grid(sprite.region_rect):
		return false
	if not _inside_sheet(sprite.region_rect):
		return false
	if sprite.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR:
		return false
	if (sprite.scale - Vector2.ONE / ART_ZOOM).length() > SCALE_TOLERANCE:
		return false
	if (_drawn_size(sprite) - sprite.region_rect.size / ART_ZOOM).length() \
			> DRAW_TOLERANCE:
		return false
	if sprite.centered:
		return false
	var logical := Rect2i(
		Vector2i(sprite.region_rect.position / ART_ZOOM),
		Vector2i(sprite.region_rect.size / ART_ZOOM))
	return LOGICAL_FAMILIES.has(logical)


func _on_zoom_grid(region: Rect2) -> bool:
	for value in [
		region.position.x, region.position.y, region.size.x, region.size.y]:
		var whole: int = int(round(value))
		if absf(value - float(whole)) > GRID_TOLERANCE:
			return false
		if whole % int(ART_ZOOM) != 0:
			return false
	return true


func _inside_sheet(region: Rect2) -> bool:
	return Rect2i(Vector2i.ZERO, NATURE_SIZE).encloses(Rect2i(region))


func _drawn_size(sprite: Sprite2D) -> Vector2:
	return Vector2(
		sprite.region_rect.size.x * sprite.scale.x,
		sprite.region_rect.size.y * sprite.scale.y)


func _names(bad: Array[String]) -> String:
	if bad.is_empty():
		return ""
	var shown: Array[String] = bad.slice(0, 3)
	var suffix: String = "" if bad.size() <= 3 else "…"
	return " (first: %s%s, %d total)" % [", ".join(shown), suffix, bad.size()]


func _finish() -> void:
	if _failed > 0:
		printerr("night-forest-atlas test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("night-forest-atlas test passed — ", _checked, " case(s)")
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
