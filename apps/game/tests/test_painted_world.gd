extends SceneTree

## Painted-world resource contract: every production sheet from pack_painted_world.py.
##
## The pack tool byte-verifies its own output, but nothing else pins the layout
## the game reads: cell grids, facing columns, state sheets, room rects, shader
## uniforms. This test loads the production resources and re-checks each rect
## against the real texture bounds, confirms every direction holds distinct
## true art (no mirrored front posing as a back), and confirms the world-space
## contract (art_zoom/visual_scale/filter) the rooms and actors render with.
##
## Direct-callable: `pnpm godot:isolated --script res://tests/test_painted_world.gd`.
## Registration in run_regression_tests.mjs belongs to another round.

const PLAYER_SCENE: PackedScene = preload("res://scenes/actors/player.tscn")
const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")
const ROOM_SCENE: PackedScene = preload("res://scenes/gameplay/room.tscn")
const BEACON_SCENE: PackedScene = preload("res://scenes/objectives/beacon.tscn")

const HERO_IDS: Array[String] = ["warden", "dancer", "keeper", "knight", "eclipse", "sage"]
const HERO_CELL: Vector2i = Vector2i(144, 192)
const HERO_SHEET_SIZE: Vector2i = Vector2i(576, 768)
const HERO_VISUAL_SCALE: float = 0.255
const PREVIEW_CROP: Rect2i = Rect2i(36, 96, 72, 72)

const SPIRIT_IDS: Array[String] = [
	"drifter", "ember", "caster", "weaver", "stalker", "swarm", "wisp",
]
const SPIRIT_SHEET_SIZE: Vector2i = Vector2i(576, 576)
const SPIRIT_CELL: int = 144
const SPIRIT_VISUAL_SCALE: float = 1.0 / 3.0

const GUARDIAN_BASES: Array[String] = ["forest", "field", "camp", "frost", "marsh", "ruins"]
const GUARDIAN_VARIANTS: Dictionary = {
	"forest": "forest_thorn",
	"field": "field_storm",
	"camp": "camp_siege",
	"frost": "frost_rime",
	"marsh": "marsh_glow",
	"ruins": "ruins_halo",
}
const GUARDIAN_CELL: int = 192
const GUARDIAN_IDLE_SIZE: Vector2i = Vector2i(1152, 192)
const GUARDIAN_STATE_SIZE: Vector2i = Vector2i(768, 192)

const ROOM_IDS: Array[String] = ["forest", "field", "camp", "frost", "marsh", "ruins"]
const NATURE_SIZE: Vector2i = Vector2i(1152, 1008)
const OBSTACLE_SIZE: Vector2i = Vector2i(768, 192)
const FLOOR_SIZE: Vector2i = Vector2i(512, 512)
const FIELD_PROP_SIZE: Vector2i = Vector2i(240, 720)
const CAMP_PROP_SIZE: Vector2i = Vector2i(1104, 432)
const ART_ZOOM: float = 3.0
const PIT_REGION: Rect2 = Rect2(576, 240, 96, 90)
const FLOOR_TILE: int = 512
const FRAME_AT: Vector2 = Vector2(950, 590)
const FRAME_SIZE: Vector2i = Vector2i(808, 360)

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_global_filter()
	_test_heroes()
	_test_spirits()
	_test_guardians()
	_test_rooms()
	_test_beacon_pit()
	_test_polish_materials()
	_test_floor_repeats()
	_finish()


## Legacy course content keeps sampling texels; only the painted nodes smooth.
func _test_global_filter() -> void:
	_expect_equal(
		ProjectSettings.get_setting(
			"rendering/textures/canvas_textures/default_texture_filter"),
		0,
		"global canvas filter stays Nearest")
	var player: Player = PLAYER_SCENE.instantiate() as Player
	# Physics interpolation is on project-wide, so Godot would override the
	# idle-fallback camera and warn. Match the override up front instead.
	(player.get_node("Cam") as Camera2D).process_callback = \
		Camera2D.CAMERA2D_PROCESS_PHYSICS
	root.add_child(player)
	var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	_expect_equal(
		sprite.texture_filter,
		CanvasItem.TEXTURE_FILTER_LINEAR,
		"player Sprite smooth filter")
	player.queue_free()
	var spirit: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	root.add_child(spirit)
	var body: AnimatedSprite2D = spirit.get_node("Sprite") as AnimatedSprite2D
	_expect_equal(
		body.texture_filter,
		CanvasItem.TEXTURE_FILTER_LINEAR,
		"spirit Sprite smooth filter")
	spirit.queue_free()
	var room: Room = ROOM_SCENE.instantiate() as Room
	root.add_child(room)
	var ground: Sprite2D = room.get_node("Ground") as Sprite2D
	_expect_equal(
		ground.texture_filter,
		CanvasItem.TEXTURE_FILTER_LINEAR,
		"room Ground smooth filter")
	room.queue_free()


func _test_heroes() -> void:
	for hero_id in HERO_IDS:
		var hero: Hero = load(
			"res://resources/heroes/%s.tres" % hero_id) as Hero
		_expect_true(hero != null, "%s Hero resource" % hero_id)
		if hero == null:
			continue
		_expect_equal(hero.sprite_cell, HERO_CELL, "%s cell" % hero_id)
		_expect_equal(
			hero.visual_scale, HERO_VISUAL_SCALE, "%s visual scale" % hero_id)
		_expect_equal(hero.preview_crop, PREVIEW_CROP, "%s preview crop" % hero_id)
		_expect_true(
			Rect2i(Vector2i.ZERO, HERO_CELL).encloses(PREVIEW_CROP),
			"%s preview crop inside its cell" % hero_id)
		for state in ["walk", "idle"]:
			var sheet: Texture2D = hero.get(state + "_sheet") as Texture2D
			_expect_true(sheet != null, "%s %s sheet" % [hero_id, state])
			if sheet == null:
				continue
			_expect_equal(
				Vector2i(sheet.get_size()),
				HERO_SHEET_SIZE,
				"%s %s sheet size" % [hero_id, state])
			_test_facing_columns(
				sheet, HERO_CELL, 4, 4, "%s %s" % [hero_id, state],
				true)


func _test_spirits() -> void:
	for spirit_id in SPIRIT_IDS:
		var kind: SpiritKind = load(
			"res://resources/%s.tres" % spirit_id) as SpiritKind
		_expect_true(kind != null, "%s SpiritKind" % spirit_id)
		if kind == null:
			continue
		_expect_equal(kind.cell, SPIRIT_CELL, "%s cell" % spirit_id)
		_expect_approx(
			kind.visual_scale, SPIRIT_VISUAL_SCALE, 0.000001,
			"%s visual scale" % spirit_id)
		_expect_equal(kind.facings, 4, "%s facing count" % spirit_id)
		_expect_equal(kind.frames, 4, "%s frame count" % spirit_id)
		_expect_true(kind.sheet != null, "%s sheet" % spirit_id)
		if kind.sheet == null:
			continue
		_expect_equal(
			Vector2i(kind.sheet.get_size()),
			SPIRIT_SHEET_SIZE,
			"%s sheet size" % spirit_id)
		_test_facing_columns(
			kind.sheet,
			Vector2i(SPIRIT_CELL, SPIRIT_CELL),
			4,
			4,
			spirit_id)


func _test_guardians() -> void:
	var ids: Array[String] = []
	ids.append_array(GUARDIAN_BASES)
	for base in GUARDIAN_BASES:
		ids.append(str(GUARDIAN_VARIANTS[base]))
	for guardian_id in ids:
		var kind: SpiritKind = load(
			"res://resources/guardian_%s.tres" % guardian_id) as SpiritKind
		_expect_true(kind != null, "%s guardian" % guardian_id)
		if kind == null:
			continue
		_expect_equal(kind.cell, GUARDIAN_CELL, "%s cell" % guardian_id)
		_expect_equal(kind.facings, 1, "%s facing-less" % guardian_id)
		_expect_equal(kind.frames, 6, "%s idle frames" % guardian_id)
		_expect_true(kind.sheet != null, "%s idle sheet" % guardian_id)
		if kind.sheet == null:
			continue
		_expect_equal(
			Vector2i(kind.sheet.get_size()),
			GUARDIAN_IDLE_SIZE,
			"%s idle size" % guardian_id)
		for slot in [
			"guardian_windup_sheet",
			"guardian_alt_windup_sheet",
			"guardian_charge_sheet",
			"guardian_recover_sheet",
		]:
			var state_sheet: Texture2D = kind.get(slot) as Texture2D
			_expect_true(
				state_sheet != null, "%s %s" % [guardian_id, slot])
			if state_sheet == null:
				continue
			_expect_equal(
				Vector2i(state_sheet.get_size()),
				GUARDIAN_STATE_SIZE,
				"%s %s size" % [guardian_id, slot])
		# The windup must read against the hover: its first frame differs.
		var idle_image: Image = kind.sheet.get_image()
		var windup_image: Image = kind.guardian_windup_sheet.get_image()
		if idle_image != null and idle_image.is_compressed():
			idle_image.decompress()
		if windup_image != null and windup_image.is_compressed():
			windup_image.decompress()
		if idle_image != null and windup_image != null:
			_expect_false(
				_regions_equal(
					idle_image, Rect2i(0, 0, GUARDIAN_CELL, GUARDIAN_CELL),
					windup_image, Rect2i(0, 0, GUARDIAN_CELL, GUARDIAN_CELL)),
				"%s windup reads against idle" % guardian_id)
	for base in GUARDIAN_BASES:
		var variant: String = str(GUARDIAN_VARIANTS[base])
		var base_kind: SpiritKind = load(
			"res://resources/guardian_%s.tres" % base) as SpiritKind
		var variant_kind: SpiritKind = load(
			"res://resources/guardian_%s.tres" % variant) as SpiritKind
		if base_kind == null or variant_kind == null:
			continue
		_expect_false(
			_images_equal(base_kind.sheet.get_image(), variant_kind.sheet.get_image()),
			"%s variant distinct from base" % variant)


## Every direction column holds ink and its own true art: the back is neither
## the front again nor the front flipped. Hero walk sides are the one
## exception: the left stride is registered donor art and the right
## column mirrors it exactly, so the same legs alternate on both sides
## (tests/test_hero_gait.gd proves the alternation row by row).
func _test_facing_columns(
	sheet: Texture2D,
	cell: Vector2i,
	columns: int,
	rows: int,
	label: String,
	mirrored_sides: bool = false,
) -> void:
	var image: Image = sheet.get_image()
	if image == null:
		_expect_true(false, "%s readable sheet" % label)
		return
	if image.is_compressed():
		image.decompress()
	var frames: Array[Rect2i] = []
	for column in columns:
		for row in rows:
			var frame := Rect2i(
				column * cell.x, row * cell.y, cell.x, cell.y)
			frames.append(frame)
			_expect_true(
				_has_ink(image, frame),
				"%s frame %d,%d holds ink" % [label, column, row])
	var first_frames: Array[Rect2i] = []
	for column in columns:
		first_frames.append(Rect2i(column * cell.x, 0, cell.x, cell.y))
	for first in columns:
		for second in range(first + 1, columns):
			_expect_false(
				_regions_equal(
					image, first_frames[first], image, first_frames[second]),
				"%s directions %d and %d distinct" % [label, first, second])
	# Columns are down, up, left, right. A mirrored front is not a back
	# view. Hero sides mirror by design in both states: the walk stride
	# and the standing idle share one painted side donor per hero, and
	# the right column is its exact mirror, so the character reads the
	# same facing left or right. Down/up stay true turnarounds.
	_expect_false(
		_regions_equal_flipped(
			image, first_frames[0], image, first_frames[1]),
		"%s back is not a mirrored front" % label)
	if mirrored_sides:
		_expect_true(
			_regions_mirror_matched(
				image, first_frames[2], image, first_frames[3]),
			"%s sides mirror exactly" % label)
	else:
		_expect_false(
			_regions_equal_flipped(
				image, first_frames[2], image, first_frames[3]),
			"%s sides are true turnarounds" % label)


func _test_rooms() -> void:
	for room_id in ROOM_IDS:
		var kind: RoomKind = load(
			"res://resources/rooms/%s.tres" % room_id) as RoomKind
		_expect_true(kind != null, "%s RoomKind" % room_id)
		if kind == null:
			continue
		_expect_equal(kind.art_zoom, ART_ZOOM, "%s art zoom" % room_id)
		_expect_equal(
			Vector2i(kind.tileset.get_size()),
			NATURE_SIZE,
			"%s nature size" % room_id)
		_expect_equal(
			Vector2i(kind.obstacle_tileset.get_size()),
			OBSTACLE_SIZE,
			"%s obstacle size" % room_id)
		_expect_equal(
			Vector2i(kind.floor_texture.get_size()),
			FLOOR_SIZE,
			"%s floor size" % room_id)
		if kind.floor_region.size.x > 0 and kind.floor_region.size.y > 0:
			_expect_true(
				Rect2i(Vector2i.ZERO, FLOOR_SIZE).encloses(kind.floor_region),
				"%s floor region inside its floor" % room_id)
		for tree_kind in kind.tree_kinds:
			_expect_rect_inside(
				Room.KIND.get(tree_kind, Rect2()),
				kind.tileset,
				"%s tree %s" % [room_id, tree_kind])
		for decor_kind in kind.decor_kinds:
			_expect_rect_inside(
				Room.KIND.get(decor_kind, Rect2()),
				kind.tileset,
				"%s decor %s" % [room_id, decor_kind])
		if kind.prop_tileset != null:
			var want_prop: Vector2i = (
				FIELD_PROP_SIZE if room_id == "field" else CAMP_PROP_SIZE)
			_expect_equal(
				Vector2i(kind.prop_tileset.get_size()),
				want_prop,
				"%s prop sheet size" % room_id)
			for prop_kind in kind.prop_kinds:
				_expect_rect_inside(
					Room.PROP_KIND.get(prop_kind, Rect2()),
					kind.prop_tileset,
					"%s prop %s" % [room_id, prop_kind])
		for region in Room.OBSTACLE_REGIONS:
			_expect_rect_inside(
				region, kind.obstacle_tileset, "%s obstacle" % room_id)
		_test_obstacle_feet(kind, room_id)


## World rects scale by art_zoom onto the sheet; the sheet must hold them.
func _expect_rect_inside(world: Rect2, sheet: Texture2D, label: String) -> void:
	_expect_true(world.size.x > 0.0 and world.size.y > 0.0, "%s known rect" % label)
	if sheet == null:
		_expect_true(false, "%s sheet present" % label)
		return
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(sheet.get_size()))
	var scaled := Rect2i(
		Vector2i(world.position * ART_ZOOM),
		Vector2i(world.size * ART_ZOOM))
	_expect_true(bounds.encloses(scaled), "%s rect inside its sheet" % label)


## Structures stand on the ground: soles near world y=50, ink at the contact,
## and clear side cell margins so the abutting neighbour never bleeds in. The
## top row needs no margin: obstacle sheets hold a single row, so sampling
## above it clamps to the sheet edge instead of a neighbour frame.
func _test_obstacle_feet(kind: RoomKind, room_id: String) -> void:
	var image: Image = kind.obstacle_tileset.get_image()
	if image == null:
		_expect_true(false, "%s obstacle sheet readable" % room_id)
		return
	if image.is_compressed():
		image.decompress()
	for variant in Room.OBSTACLE_REGIONS.size():
		var world: Rect2 = Room.OBSTACLE_REGIONS[variant]
		var cell := Rect2i(
			Vector2i(world.position * ART_ZOOM),
			Vector2i(world.size * ART_ZOOM))
		var lowest: int = -1
		var contact_ink: bool = false
		var dirty_margin: int = 0
		for y in cell.size.y:
			for x in cell.size.x:
				if image.get_pixel(cell.position.x + x, cell.position.y + y).a <= 0.0:
					continue
				lowest = cell.position.y + y
				var world_y: float = float(y) / ART_ZOOM
				if world_y >= 40.0 and world_y <= 60.0:
					contact_ink = true
				if x == 0 or x == cell.size.x - 1:
					dirty_margin += 1
		_expect_true(lowest >= 0, "%s obstacle %d holds ink" % [room_id, variant])
		_expect_true(
			lowest < 0 or float(lowest - cell.position.y) / ART_ZOOM >= 48.0,
			"%s obstacle %d feet planted" % [room_id, variant])
		_expect_true(
			contact_ink, "%s obstacle %d contact ink" % [room_id, variant])
		_expect_equal(
			dirty_margin, 0, "%s obstacle %d clear side margins" % [room_id, variant])


func _test_beacon_pit() -> void:
	var beacon: Node2D = BEACON_SCENE.instantiate() as Node2D
	root.add_child(beacon)
	var pit: Sprite2D = beacon.get_node("Pit") as Sprite2D
	_expect_true(pit != null, "beacon Pit node")
	if pit == null:
		beacon.queue_free()
		return
	_expect_true(pit.region_enabled, "beacon Pit region enabled")
	_expect_equal(pit.region_rect, PIT_REGION, "beacon Pit region")
	_expect_equal(
		pit.texture_filter,
		CanvasItem.TEXTURE_FILTER_LINEAR,
		"beacon Pit smooth filter")
	_expect_true(pit.texture != null, "beacon Pit texture")
	if pit.texture != null:
		_expect_equal(
			pit.texture.resource_path,
			"res://assets/custom/world/terrain/camp.png",
			"beacon Pit camp sheet")
		var bounds := Rect2i(Vector2i.ZERO, Vector2i(pit.texture.get_size()))
		_expect_true(
			bounds.encloses(Rect2i(pit.region_rect)),
			"beacon Pit region inside its sheet")
		var image: Image = pit.texture.get_image()
		if image != null:
			if image.is_compressed():
				image.decompress()
			_expect_true(
				_has_ink(image, Rect2i(pit.region_rect)),
				"beacon Pit holds ink")
	beacon.queue_free()


## The polish shaders sample neighbours in sheet pixels; the painted 3x sheets
## carry their zoom in the shared materials.
func _test_polish_materials() -> void:
	var actor_material: ShaderMaterial = load(
		"res://resources/fx/actor_polish.tres") as ShaderMaterial
	_expect_true(actor_material != null, "actor polish material")
	if actor_material != null:
		_expect_equal(
			float(actor_material.get_shader_parameter("tap_radius")),
			ART_ZOOM,
			"actor polish tap radius matches art zoom")
	var nature_material: ShaderMaterial = load(
		"res://resources/fx/world_nature.tres") as ShaderMaterial
	_expect_true(nature_material != null, "world nature material")
	if nature_material != null:
		_expect_equal(
			float(nature_material.get_shader_parameter("tree_rows_above")),
			384.0,
			"nature tree row matches painted sheets")
		_expect_equal(
			float(nature_material.get_shader_parameter("sway")),
			ART_ZOOM,
			"nature sway matches art zoom")


## Floor repeats must be invisible both as tiles and as rendered at the game
## camera. Edges meet within one quantum; the pairs beside the seam must not
## step harder than every interior pair (a coherent ridge fails); no
## four-edge smoothing (the blend signature). The rendered check simulates
## the production plain-repeat sampler 1:1 over the staged frame using the
## Ground node's own mapping values, which are pinned first so the
## simulation cannot drift from the sampler.
func _test_floor_repeats() -> void:
	for room_id in ROOM_IDS:
		var kind: RoomKind = load(
			"res://resources/rooms/%s.tres" % room_id) as RoomKind
		if kind == null or kind.floor_texture == null:
			continue
		var image: Image = kind.floor_texture.get_image()
		if image == null:
			_expect_true(false, "%s floor readable" % room_id)
			continue
		if image.is_compressed():
			image.decompress()
		_expect_floor_tile(image, room_id)
	_test_rendered_repeats()
	_test_repeat_negative_control()


func _expect_floor_tile(image: Image, label: String) -> void:
	var size: Vector2i = image.get_size()
	_expect_true(size.x == FLOOR_TILE and size.y == FLOOR_TILE, "%s floor 512" % label)
	var worst_edge: int = 0
	for y in size.y:
		var left: Color = image.get_pixel(0, y)
		var right: Color = image.get_pixel(size.x - 1, y)
		worst_edge = maxi(worst_edge, _channel_step(left, right))
	for x in size.x:
		var top: Color = image.get_pixel(x, 0)
		var bottom: Color = image.get_pixel(x, size.y - 1)
		worst_edge = maxi(worst_edge, _channel_step(top, bottom))
	_expect_true(worst_edge <= 1, "%s floor edges meet" % label)
	for horizontal in [true, false]:
		var axis: String = "column" if horizontal else "row"
		var means: Array[float] = _tile_pair_means(image, horizontal)
		var inside: float = 0.0
		for index in range(1, means.size() - 1):
			inside = maxf(inside, means[index])
		_expect_true(
			means[0] <= inside and means[means.size() - 1] <= inside,
			"%s floor seam %s pairs typical" % [label, axis])
	var smoothed: bool = true
	for horizontal in [true, false]:
		var strips: Array[float] = _tile_strip_energy(image, horizontal)
		var inner: float = strips[1]
		for index in range(2, 7):
			inner = minf(inner, strips[index])
		if not (strips[0] < inner and strips[7] < inner):
			smoothed = false
	_expect_false(smoothed, "%s floor no four-edge smoothing" % label)


func _test_rendered_repeats() -> void:
	var room: Room = ROOM_SCENE.instantiate() as Room
	root.add_child(room)
	var ground: Sprite2D = room.get_node("Ground") as Sprite2D
	_expect_equal(
		ground.texture_repeat,
		CanvasItem.TEXTURE_REPEAT_ENABLED,
		"ground plain-repeat sampler")
	_expect_equal(
		ground.texture_filter,
		CanvasItem.TEXTURE_FILTER_LINEAR,
		"ground smooth sampler")
	_expect_equal(ground.scale, Vector2.ONE, "ground unit scale")
	_expect_equal(
		ground.region_rect, Rect2(0, 0, 2100, 1380), "ground region")
	_expect_equal(ground.position, Vector2(-100, -100), "ground origin")
	_expect_false(ground.centered, "ground top-left origin")
	# At exact 1:1 the Linear sampler degenerates to nearest, so sampling
	# texel centers reproduces the rendered frame under this integer mapping.
	for room_id in ROOM_IDS:
		var kind: RoomKind = load(
			"res://resources/rooms/%s.tres" % room_id) as RoomKind
		if kind == null or kind.floor_texture == null:
			continue
		var image: Image = kind.floor_texture.get_image()
		if image == null:
			continue
		if image.is_compressed():
			image.decompress()
		_test_rendered_frame(image, ground.position, room_id)
	room.queue_free()


func _test_rendered_frame(image: Image, origin: Vector2, room_id: String) -> void:
	var gx0: int = int(FRAME_AT.x - FRAME_SIZE.x * 0.5 - origin.x)
	var gy0: int = int(FRAME_AT.y - FRAME_SIZE.y * 0.5 - origin.y)
	_expect_true(gx0 >= 0 and gy0 >= 0, "%s frame inside ground" % room_id)
	# Rendered columns: a pair straddling a tile multiple is a seam pair.
	var col_means: Array[float] = []
	var col_seams: Array[int] = []
	for sx in FRAME_SIZE.x - 1:
		var gx: int = gx0 + sx
		if gx % FLOOR_TILE == FLOOR_TILE - 1:
			col_seams.append(sx)
		var total: float = 0.0
		for sy in FRAME_SIZE.y:
			var gy: int = gy0 + sy
			var a: Color = image.get_pixel(gx % FLOOR_TILE, gy % FLOOR_TILE)
			var b: Color = image.get_pixel((gx + 1) % FLOOR_TILE, gy % FLOOR_TILE)
			total += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
		col_means.append(total / float(FRAME_SIZE.y))
	_expect_rendered_seams_typical(col_means, col_seams, "%s rendered columns" % room_id)
	var row_means: Array[float] = []
	var row_seams: Array[int] = []
	for sy in FRAME_SIZE.y - 1:
		var gy: int = gy0 + sy
		if gy % FLOOR_TILE == FLOOR_TILE - 1:
			row_seams.append(sy)
		var total: float = 0.0
		for sx in FRAME_SIZE.x:
			var gx: int = gx0 + sx
			var a: Color = image.get_pixel(gx % FLOOR_TILE, gy % FLOOR_TILE)
			var b: Color = image.get_pixel(gx % FLOOR_TILE, (gy + 1) % FLOOR_TILE)
			total += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
		row_means.append(total / float(FRAME_SIZE.x))
	_expect_rendered_seams_typical(row_means, row_seams, "%s rendered rows" % room_id)


func _expect_rendered_seams_typical(
	means: Array[float], seams: Array[int], label: String
) -> void:
	_expect_true(seams.size() > 0, "%s seam in frame" % label)
	var inside: float = 0.0
	for index in means.size():
		if index in seams:
			continue
		inside = maxf(inside, means[index])
	for seam in seams:
		_expect_true(means[seam] <= inside, "%s seam typical" % label)


## The metrics must catch the defect they guard: a midpoint-blended tile trips
## the ridge rank, and a four-edge-smoothed tile trips the band rule, while
## the production floors pass both.
func _test_repeat_negative_control() -> void:
	var ridged: Image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var tone: float = 100.0 + float(x) * 0.3
			ridged.set_pixel(x, y, Color(tone / 255.0, tone / 255.0, tone / 255.0))
	for y in 64:
		var left: float = ridged.get_pixel(0, y).r
		var right: float = ridged.get_pixel(63, y).r
		var middle: float = (left + right) * 0.5
		ridged.set_pixel(0, y, Color(middle, middle, middle))
		ridged.set_pixel(63, y, Color(middle, middle, middle))
	var means: Array[float] = _tile_pair_means(ridged, true)
	var inside: float = 0.0
	for index in range(1, means.size() - 1):
		inside = maxf(inside, means[index])
	_expect_true(means[0] > inside, "negative control ridge trips rank")
	var banded: Image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var tone: float = 100.0 + float((x * 7 + y * 13) % 40)
			banded.set_pixel(x, y, Color(tone / 255.0, tone / 255.0, tone / 255.0))
	for edge in 8:
		for k in 64:
			var flat := Color(110.0 / 255.0, 110.0 / 255.0, 110.0 / 255.0)
			banded.set_pixel(edge, k, flat)
			banded.set_pixel(63 - edge, k, flat)
			banded.set_pixel(k, edge, flat)
			banded.set_pixel(k, 63 - edge, flat)
	var smoothed: bool = true
	for horizontal in [true, false]:
		var strips: Array[float] = _tile_strip_energy_small(banded, horizontal)
		var inner: float = strips[1]
		for index in range(2, 7):
			inner = minf(inner, strips[index])
		if not (strips[0] < inner and strips[7] < inner):
			smoothed = false
	_expect_true(smoothed, "negative control bands trip rule")


func _tile_pair_means(image: Image, horizontal: bool) -> Array[float]:
	var size: Vector2i = image.get_size()
	var count: int = size.x - 1 if horizontal else size.y - 1
	var span: int = size.y if horizontal else size.x
	var means: Array[float] = []
	for index in count:
		var total: float = 0.0
		for k in span:
			var a: Color
			var b: Color
			if horizontal:
				a = image.get_pixel(index, k)
				b = image.get_pixel(index + 1, k)
			else:
				a = image.get_pixel(k, index)
				b = image.get_pixel(k, index + 1)
			total += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
		means.append(total / float(span))
	return means


func _tile_strip_energy(image: Image, horizontal: bool) -> Array[float]:
	return _tile_strip_energy_step(image, horizontal, 64, 4)


func _tile_strip_energy_small(image: Image, horizontal: bool) -> Array[float]:
	return _tile_strip_energy_step(image, horizontal, 8, 1)


func _tile_strip_energy_step(
	image: Image, horizontal: bool, width: int, stride: int
) -> Array[float]:
	var size: Vector2i = image.get_size()
	var span: int = size.y if horizontal else size.x
	var strips: Array[float] = []
	for strip in 8:
		var total: float = 0.0
		var samples: int = 0
		for i in range(strip * width, strip * width + width - 1):
			var k: int = 0
			while k < span:
				var a: Color
				var b: Color
				if horizontal:
					a = image.get_pixel(i, k)
					b = image.get_pixel(i + 1, k)
				else:
					a = image.get_pixel(k, i)
					b = image.get_pixel(k, i + 1)
				total += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
				samples += 1
				k += stride
		strips.append(total / float(maxi(samples, 1)))
	return strips


func _channel_step(a: Color, b: Color) -> int:
	return int(round(maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0))


func _has_ink(image: Image, region: Rect2i) -> bool:
	for y in region.size.y:
		for x in region.size.x:
			if image.get_pixel(region.position.x + x, region.position.y + y).a > 0.0:
				return true
	return false


func _regions_equal(a: Image, a_rect: Rect2i, b: Image, b_rect: Rect2i) -> bool:
	if a_rect.size != b_rect.size:
		return false
	for y in a_rect.size.y:
		for x in a_rect.size.x:
			if a.get_pixel(a_rect.position.x + x, a_rect.position.y + y) \
					!= b.get_pixel(b_rect.position.x + x, b_rect.position.y + y):
				return false
	return true


func _regions_equal_flipped(a: Image, a_rect: Rect2i, b: Image, b_rect: Rect2i) -> bool:
	if a_rect.size != b_rect.size:
		return false
	for y in a_rect.size.y:
		for x in a_rect.size.x:
			if a.get_pixel(a_rect.position.x + x, a_rect.position.y + y) \
					!= b.get_pixel(
						b_rect.position.x + b_rect.size.x - 1 - x,
						b_rect.position.y + y):
				return false
	return true


## Mirror match on imported textures: every visible pixel (alpha 32
## and up) must agree exactly. Fully transparent and faint-halo pixels
## are exempt: the importer's alpha-border fix fills their RGB from
## whichever opaque neighbour its scan meets first, a directional
## tie-break that reads differently at mirrored positions (a handful of
## pixels per sheet, all below alpha 20). The gait suite pins the
## byte-exact mirror on the source PNGs; here the visible art agrees.
func _regions_mirror_matched(
	a: Image, a_rect: Rect2i, b: Image, b_rect: Rect2i
) -> bool:
	if a_rect.size != b_rect.size:
		return false
	for y in a_rect.size.y:
		for x in a_rect.size.x:
			var left: Color = a.get_pixel(
				a_rect.position.x + x, a_rect.position.y + y)
			var right: Color = b.get_pixel(
				b_rect.position.x + b_rect.size.x - 1 - x,
				b_rect.position.y + y)
			if left.a < 32.0 / 255.0 and right.a < 32.0 / 255.0:
				continue
			if left != right:
				return false
	return true


func _images_equal(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	return a.get_data() == b.get_data()


func _finish() -> void:
	if _failed > 0:
		printerr("painted-world test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("painted-world test passed — ", _checked, " case(s)")
	quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	_checked += 1
	if absf(actual - expected) <= tolerance:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected~", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)


func _expect_false(actual: bool, label: String) -> void:
	_expect_equal(actual, false, label)
