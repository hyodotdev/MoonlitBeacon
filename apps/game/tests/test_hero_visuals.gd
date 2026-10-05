extends SceneTree

## Confirm runtime sheet assembly for all six player heroes, plus the Player safety fallback.

const PLAYER_SCENE: PackedScene = preload("res://scenes/actors/player.tscn")
const CELL: Vector2i = Vector2i(144, 192)
## Painted cells are 3x at 1/3 the legacy 0.765 body factor, so the sprite sits
## lower to render the same world feet. See Player.apply_hero_visual.
const APPLIED_POSITION_Y: float = -28.08
## World foot of the rendered body: unchanged from the legacy sheets.
const WORLD_FOOT_Y: float = -5.64
const DIRECTIONS: Array[StringName] = [&"down", &"up", &"left", &"right"]
const HERO_CASES: Array[Dictionary] = [
	{
		"id": "warden",
		"resource": "res://resources/heroes/warden.tres",
		"accent": Color(0.56, 0.85, 1.0, 1.0),
	},
	{
		"id": "dancer",
		"resource": "res://resources/heroes/dancer.tres",
		"accent": Color(0.95, 0.6, 0.73, 1.0),
	},
	{
		"id": "keeper",
		"resource": "res://resources/heroes/keeper.tres",
		"accent": Color(0.96, 0.71, 0.36, 1.0),
	},
	{
		"id": "knight",
		"resource": "res://resources/heroes/knight.tres",
		"accent": Color(1.0, 1.0, 1.0, 1.0),
	},
	{
		"id": "eclipse",
		"resource": "res://resources/heroes/eclipse.tres",
		"accent": Color(1.0, 0.3, 0.3, 1.0),
	},
	{
		"id": "sage",
		"resource": "res://resources/heroes/sage.tres",
		"accent": Color(0.18, 0.92, 0.82, 1.0),
	},
]
const MIN_ACCENT_DISTANCE_SQUARED: float = 0.14
const PAID_HEROES: Array[String] = [
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/eclipse.tres",
	"res://resources/heroes/sage.tres",
]
const UI_LOCALES: Array[String] = ["en", "ko", "ja", "zh_CN", "zh_TW"]
const MAX_HEALTH_LIMIT: int = 8
## Canonical-head boundary per hero, in cell rows. Restates the packer's
## HERO_IDLE_NECK; rows [0, neck) stay pixel-fixed through walk, idle
## and the attack torso.
const HERO_NECK: Dictionary = {
	"warden": 130, "dancer": 130, "keeper": 128,
	"knight": 120, "eclipse": 126, "sage": 118,
}
## Alpha floor for the head-identity box, 0-1. Matches the bake audit.
const HEAD_INK: float = 64.0 / 255.0
## Alpha floor for sole runs, 0-1. Matches the packer's stance audit.
const SOLE_INK: float = 8.0 / 255.0
## Head-band rows dropped from the attack-torso comparison: the torso
## bake cuts the arms out of the shoulder rows, so the torso guards
## the face, skull and crown while walk/idle guard the chin baseline.
const TORSO_FACE_DROP: int = 10
## Side-stance sole extent bounds, cell px. Gathered profile feet span
## 26-38 while the old contact stride spans 56-68; a single narrow
## boot spans under 20.
const STANCE_EXTENT_MIN: int = 20
const STANCE_EXTENT_MAX: int = 46
## Front/back stance: two sole runs with at most this gap between the
## inner edges, centered on the stance middle within FRONT_MID_TOL.
const FRONT_BOOT_GAP: int = 8
const FRONT_MID_TOL: float = 6.0
const FRONT_CENTER_DEFAULT: int = 72
const FRONT_CENTER: Dictionary = {
	"warden_up": 67, "knight_up": 66,
}
const FACING_NAMES: Array[String] = ["down", "up", "left", "right"]
const FACING_AIMS: Array[Vector2] = [
	Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]
## Heroes whose primary attack is the melee swing (the split shows
## straight from attack()); ranged primaries fire through the cast.
const MELEE_IDS: Array[String] = ["warden", "dancer", "eclipse"]

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	_expect_true(player != null, "Player scene instance")
	if player == null:
		_finish()
		return
	root.add_child(player)
	player.process_mode = Node.PROCESS_MODE_DISABLED

	var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	_expect_true(sprite != null, "Player Sprite node")
	if sprite == null:
		player.queue_free()
		await process_frame
		_finish()
		return

	_test_fallback(sprite)
	for hero_case in HERO_CASES:
		_test_applied_hero(player, sprite, hero_case)
	_test_distinct_accents()
	_test_paid_hero_descriptions()
	_test_moonlight_cast(player)
	_test_weapon_rig(player)
	_test_canonical_heads(player, sprite)
	_test_standing_stances()

	player.queue_free()
	await process_frame
	_finish()


func _test_fallback(sprite: AnimatedSprite2D) -> void:
	_expect_equal(sprite.position.y, -8.0, "Player fallback foot-origin position.y")
	var frames: SpriteFrames = sprite.sprite_frames
	_expect_true(frames != null, "Player fallback SpriteFrames")
	if frames == null:
		return
	_expect_equal(frames.get_animation_names().size(), 8, "Player fallback 8 animations")

	for state in [&"walk", &"idle"]:
		var expected_path: String = (
			"res://assets/custom/actors/heroes/warden/%s.png" % state)
		var expected_count: int = 4 if state == &"walk" else 1
		for direction in DIRECTIONS:
			var animation := StringName("%s_%s" % [state, direction])
			_expect_true(
				frames.has_animation(animation),
				"Player fallback %s exists" % animation)
			if not frames.has_animation(animation):
				continue
			_expect_equal(
				frames.get_frame_count(animation),
				expected_count,
				"Player fallback %s frame count" % animation)
			for frame_index in frames.get_frame_count(animation):
				_expect_atlas(
					frames.get_frame_texture(animation, frame_index),
					expected_path,
					CELL,
					"Player fallback %s[%d]" % [animation, frame_index])


func _test_applied_hero(
		player: Player,
		sprite: AnimatedSprite2D,
		hero_case: Dictionary,
	) -> void:
	var hero_id: String = str(hero_case["id"])
	var hero: Hero = load(str(hero_case["resource"])) as Hero
	_expect_true(hero != null, "%s Hero resource" % hero_id)
	if hero == null:
		return
	_expect_true(player.apply_hero_visual(hero), "%s sheet applied" % hero_id)
	_expect_approx(
		sprite.position.y, APPLIED_POSITION_Y, 0.001,
		"%s foot-origin position.y" % hero_id)
	# The world foot must not move: sprite base plus the un-breathed cell
	# bottom lands where the legacy 48x64 sheets landed.
	var base_foot: float = sprite.position.y \
		+ (float(hero.sprite_cell.y) * 0.5 + Player.HERO_BASE_OFFSET_Y) \
		* hero.visual_scale
	_expect_approx(base_foot, WORLD_FOOT_Y, 0.01, "%s world foot y" % hero_id)
	_expect_equal(
		hero.preview_crop,
		Rect2i(36, 96, 72, 72),
		"%s detail view 2-head crop" % hero_id)
	_expect_equal(hero.accent, hero_case["accent"], "%s role accent color" % hero_id)
	_expect_equal(
		sprite.self_modulate,
		Player.HERO_READABILITY_TINT,
		"%s night-readability tint" % hero_id)

	var frames: SpriteFrames = sprite.sprite_frames
	_expect_true(frames != null, "%s SpriteFrames" % hero_id)
	if frames == null:
		return
	_expect_equal(frames.get_animation_names().size(), 8, "%s 8 animations" % hero_id)

	for state in [&"walk", &"idle"]:
		var expected_path: String = (
			"res://assets/custom/actors/heroes/%s/%s.png" % [hero_id, state])
		for direction_index in DIRECTIONS.size():
			var direction: StringName = DIRECTIONS[direction_index]
			var animation := StringName("%s_%s" % [state, direction])
			_expect_true(
				frames.has_animation(animation),
				"%s %s exists" % [hero_id, animation])
			if not frames.has_animation(animation):
				continue
			_expect_equal(
				frames.get_frame_count(animation),
				4,
				"%s %s frame count" % [hero_id, animation])
			for frame_index in 4:
				_expect_atlas(
					frames.get_frame_texture(animation, frame_index),
					expected_path,
					Rect2(
						direction_index * CELL.x,
						frame_index * CELL.y,
						CELL.x,
						CELL.y),
					"%s %s[%d]" % [hero_id, animation, frame_index])


## One canonical head per hero and facing through every walk frame,
## every idle frame and the attack torso: the skull, face and baseline
## never move while the legs work. Reads the production PNGs and the
## runtime atlas assemblies alike, so a sheet swap or a mis-seated
## torso fails here, not silently.
func _test_canonical_heads(player: Player, sprite: AnimatedSprite2D) -> void:
	for hero_case in HERO_CASES:
		var hero_id: String = str(hero_case["id"])
		var neck: int = int(HERO_NECK[hero_id])
		var walk: Image = Image.load_from_file(
			"res://assets/custom/actors/heroes/%s/walk.png" % hero_id)
		var idle: Image = Image.load_from_file(
			"res://assets/custom/actors/heroes/%s/idle.png" % hero_id)
		_expect_true(walk != null and idle != null,
			"%s stance sheets load" % hero_id)
		if walk == null or idle == null:
			continue
		for facing in 4:
			var tag: String = "%s %s" % [hero_id, FACING_NAMES[facing]]
			var canon: PackedByteArray = _band_bytes(
				walk, facing, 0, neck)
			var canon_box: Rect2i = _head_box(walk, facing, 0, neck)
			for frame in range(1, 4):
				_expect_bands_equal(
					_band_bytes(walk, facing, frame, neck), canon,
					"%s walk frame %d keeps its head" % [tag, frame])
				_expect_equal(
					_head_box(walk, facing, frame, neck), canon_box,
					"%s walk frame %d holds its head box" % [tag, frame])
			for frame in 4:
				_expect_bands_equal(
					_band_bytes(idle, facing, frame, neck), canon,
					"%s idle frame %d shares the walk head" % [tag, frame])
				_expect_equal(
					_head_box(idle, facing, frame, neck), canon_box,
					"%s idle frame %d holds its head box" % [tag, frame])
			var torso: Image = Image.load_from_file(
				"res://assets/custom/actors/heroes/%s/rig/torso_%s.png"
				% [hero_id, FACING_NAMES[facing]])
			_expect_true(torso != null,
				"%s attack torso loads" % tag)
			if torso != null:
				var face: int = neck - TORSO_FACE_DROP
				_expect_bands_equal(
					torso.get_region(
						Rect2i(0, 0, CELL.x, face)).get_data(),
					_band_bytes(walk, facing, 0, face),
					"%s attack torso wears the walk face" % tag)
	_test_runtime_heads(player, sprite)


## The runtime assemblies share heads too: walk frame 0 and idle frame
## 0 draw the same head bytes per facing, and the live attack torso
## wears them while the split shows.
func _test_runtime_heads(player: Player, sprite: AnimatedSprite2D) -> void:
	for hero_case in HERO_CASES:
		var hero_id: String = str(hero_case["id"])
		var hero: Hero = load(str(hero_case["resource"])) as Hero
		if hero == null:
			continue
		player.apply_hero_visual(hero)
		var neck: int = int(HERO_NECK[hero_id])
		var frames: SpriteFrames = sprite.sprite_frames
		if frames == null:
			continue
		for facing in 4:
			var direction: StringName = DIRECTIONS[facing]
			var walk_tex: AtlasTexture = frames.get_frame_texture(
				StringName("walk_%s" % direction), 0) as AtlasTexture
			var idle_tex: AtlasTexture = frames.get_frame_texture(
				StringName("idle_%s" % direction), 0) as AtlasTexture
			_expect_true(walk_tex != null and idle_tex != null,
				"%s %s runtime frames hang" % [hero_id, direction])
			if walk_tex == null or idle_tex == null:
				continue
			_expect_bands_equal(
				_atlas_band(walk_tex, neck), _atlas_band(idle_tex, neck),
				"%s %s stop keeps the moving head" % [hero_id, direction])
		_test_attack_heads(player, hero_id, neck)


func _test_attack_heads(
	player: Player, hero_id: String, neck: int
) -> void:
	var torso_node: Sprite2D = player.get_node("AttackTorso") as Sprite2D
	_expect_true(torso_node != null, "%s attack torso node" % hero_id)
	if torso_node == null:
		return
	for facing in 4:
		if hero_id in MELEE_IDS:
			player.set("_attack_cooldown", 0.0)
			player.attack(FACING_AIMS[facing])
		else:
			player.play_moonlight_cast(FACING_AIMS[facing], 1)
		player.call("_update_attack_pose", 1.0 / 120.0)
		var tag: String = "%s %s" % [hero_id, FACING_NAMES[facing]]
		_expect_true(torso_node.visible, "%s torso shows" % tag)
		var worn: Texture2D = torso_node.texture
		_expect_true(worn != null, "%s torso wears paint" % tag)
		if worn == null:
			continue
		var paint: Image = worn.get_image()
		_expect_true(paint != null, "%s torso paint reads" % tag)
		if paint == null:
			continue
		# Geometry, not bytes: the import pipeline owns the texture
		# encoding, while the file check above locks the exact face.
		var file_torso: Image = Image.load_from_file(
			"res://assets/custom/actors/heroes/%s/rig/torso_%s.png"
			% [hero_id, FACING_NAMES[facing]])
		_expect_true(file_torso != null, "%s torso file reads" % tag)
		if file_torso == null:
			continue
		_expect_equal(_flat_head_box(paint, neck),
			_flat_head_box(file_torso, neck),
			"%s attack keeps the walk face box" % tag)


## Every idle facing stands: front/back plant two boots with a small
## gap under the garment middle, sides gather overlapped profile feet
## in a narrow extent. Reads idle row 0, the pose stops land on.
func _test_standing_stances() -> void:
	for hero_case in HERO_CASES:
		var hero_id: String = str(hero_case["id"])
		var idle: Image = Image.load_from_file(
			"res://assets/custom/actors/heroes/%s/idle.png" % hero_id)
		_expect_true(idle != null, "%s idle loads" % hero_id)
		if idle == null:
			continue
		for facing in [0, 1]:
			var tag: String = "%s %s" % [hero_id, FACING_NAMES[facing]]
			var feet: Array = _sole_runs(idle, facing)
			_expect_equal(feet.size(), 2,
				"%s stands on two boots (%d)" % [tag, feet.size()])
			if feet.size() != 2:
				continue
			var gap: int = int((feet[1] as Vector2i).x) \
				- int((feet[0] as Vector2i).y)
			_expect_true(gap <= FRONT_BOOT_GAP,
				"%s boots stand together (%dpx)" % [tag, gap])
			var middle: float = (
				float((feet[0] as Vector2i).x) \
				+ float((feet[1] as Vector2i).y)) * 0.5
			var want: float = float(FRONT_CENTER.get(
				"%s_%s" % [hero_id, FACING_NAMES[facing]],
				FRONT_CENTER_DEFAULT))
			_expect_true(absf(middle - want) <= FRONT_MID_TOL,
				"%s boots plant under the middle (%.1f)" % [tag, middle])
		for facing in [2, 3]:
			var tag: String = "%s %s" % [hero_id, FACING_NAMES[facing]]
			var feet: Array = _sole_runs(idle, facing)
			_expect_true(feet.size() >= 1,
				"%s plants its feet" % tag)
			if feet.is_empty():
				continue
			var extent: int = int((feet[feet.size() - 1] as Vector2i).y) \
				- int((feet[0] as Vector2i).x) + 1
			_expect_true(extent >= STANCE_EXTENT_MIN \
				and extent <= STANCE_EXTENT_MAX,
				"%s stance gathers (%dpx)" % [tag, extent])


## Two head bands match when no byte differs; the failure names the
## count, not the arrays, so a mismatch stays one readable line.
func _expect_bands_equal(
	actual: PackedByteArray, expected: PackedByteArray, label: String
) -> void:
	_checked += 1
	if actual.size() != expected.size():
		_failed += 1
		printerr("  FAIL ", label, " — size ", actual.size(),
			" vs ", expected.size())
		return
	var differ: int = 0
	for index in actual.size():
		if actual[index] != expected[index]:
			differ += 1
	if differ > 0:
		_failed += 1
		printerr("  FAIL ", label, " — ", differ, " bytes differ")


## Raw bytes of one cell's head band, rows [0, neck).
func _band_bytes(image: Image, column: int, row: int, neck: int) -> PackedByteArray:
	return image.get_region(Rect2i(
		column * CELL.x, row * CELL.y, CELL.x, neck)).get_data()


## Head-ink box above the neck at the audit alpha: position and size
## both fixed when the head never moves.
func _head_box(image: Image, column: int, row: int, neck: int) -> Rect2i:
	var origin := Vector2i(column * CELL.x, row * CELL.y)
	var lo := Vector2i(CELL.x, neck)
	var hi := Vector2i(-1, -1)
	for y in neck:
		for x in CELL.x:
			if image.get_pixel(origin.x + x, origin.y + y).a >= HEAD_INK:
				lo.x = mini(lo.x, x)
				lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x)
				hi.y = maxi(hi.y, y)
	return Rect2i(lo, hi - lo + Vector2i(1, 1))


## Head-ink box over a single flat image (a torso strip), rows
## [0, neck): the runtime import owns encodings, geometry must hold.
func _flat_head_box(image: Image, neck: int) -> Rect2i:
	var lo := Vector2i(image.get_width(), neck)
	var hi := Vector2i(-1, -1)
	for y in mini(neck, image.get_height()):
		for x in image.get_width():
			if image.get_pixel(x, y).a >= HEAD_INK:
				lo.x = mini(lo.x, x)
				lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x)
				hi.y = maxi(hi.y, y)
	return Rect2i(lo, hi - lo + Vector2i(1, 1))


## Head band through a runtime atlas frame: the full sheet image cut
## to the frame's own region, head rows only.
func _atlas_band(atlas_texture: AtlasTexture, neck: int) -> PackedByteArray:
	var sheet: Image = atlas_texture.atlas.get_image()
	var region: Rect2 = atlas_texture.region
	return sheet.get_region(Rect2i(
		int(region.position.x), int(region.position.y),
		CELL.x, neck)).get_data()


## Planted feet as x-runs: columns inked in at least two of the
## bottom eight rows group into runs; runs under 4px wide are fringe.
func _sole_runs(image: Image, column: int) -> Array:
	var origin := Vector2i(column * CELL.x, 0)
	var covered: Array[int] = []
	covered.resize(CELL.x)
	covered.fill(0)
	for y in range(CELL.y - 8, CELL.y):
		for x in CELL.x:
			if image.get_pixel(origin.x + x, y).a >= SOLE_INK:
				covered[x] += 1
	var feet: Array = []
	var start: int = -1
	for x in CELL.x:
		if covered[x] >= 2 and start < 0:
			start = x
		elif covered[x] < 2 and start >= 0:
			if x - start >= 4:
				feet.append(Vector2i(start, x - 1))
			start = -1
	if start >= 0 and CELL.x - start >= 4:
		feet.append(Vector2i(start, CELL.x - 1))
	return feet


func _test_distinct_accents() -> void:
	for first_index in HERO_CASES.size():
		var first: Color = HERO_CASES[first_index]["accent"]
		for second_index in range(first_index + 1, HERO_CASES.size()):
			var second: Color = HERO_CASES[second_index]["accent"]
			var distance_squared := Vector3(first.r, first.g, first.b).distance_squared_to(
				Vector3(second.r, second.g, second.b))
			_expect_true(
				distance_squared >= MIN_ACCENT_DISTANCE_SQUARED,
				"%s·%s accent colors distinct" % [
					HERO_CASES[first_index]["id"],
					HERO_CASES[second_index]["id"],
				])


## Paid-hero copy does not only list base multipliers; it states the real start values including starting relics.
## All five languages must include the same numbers and both starting relic names so the checkout preview is accurate.
func _test_paid_hero_descriptions() -> void:
	var original_locale: String = TranslationServer.get_locale()
	for hero_path in PAID_HEROES:
		var hero: Hero = load(hero_path) as Hero
		_expect_true(hero != null, hero_path.get_file() + " Hero for description")
		if hero == null:
			continue

		var effective_health: int = mini(hero.health, MAX_HEALTH_LIMIT)
		var effective_speed: float = Player.DEFAULT_SPEED * hero.speed_scale
		var effective_damage: float = hero.damage_scale
		var effective_dash: float = hero.dash_scale
		var opening_relics: Array[Relic] = []
		for relic_path in hero.opening:
			var relic: Relic = load(relic_path) as Relic
			_expect_true(relic != null, hero_path.get_file() + " starting relic " + relic_path)
			if relic == null:
				continue
			opening_relics.append(relic)
			match relic.effect:
				Relic.Effect.MOVE_SPEED:
					effective_speed += relic.amount
				Relic.Effect.MAX_HEALTH:
					effective_health = mini(
						effective_health + int(relic.amount), MAX_HEALTH_LIMIT)
				Relic.Effect.ATTACK_DAMAGE:
					effective_damage *= relic.amount
				Relic.Effect.DASH_COOLDOWN:
					effective_dash *= relic.amount

		var speed_marker: String = _signed_percent(
			(effective_speed / Player.DEFAULT_SPEED - 1.0) * 100.0)
		var dash_marker: String = _signed_percent((effective_dash - 1.0) * 100.0)
		# Damage multipliers stay on the resource: the weapon table gives each
		# hero private bases, lanes and cooldowns, so no flat cross-hero
		# percent is shown. Hearts, move, dash and openings still match live.
		_expect_true(effective_damage > 0.0,
			hero_path.get_file() + " damage multiplier stays on the resource")
		for locale in UI_LOCALES:
			TranslationServer.set_locale(locale)
			var label: String = "%s %s" % [hero_path.get_file(), locale]
			var description: String = tr(hero.description)
			_expect_true(
				description.contains(_health_marker(locale, effective_health)),
				label + " actual starting hearts")
			_expect_true(
				description.contains(speed_marker),
				label + " actual starting move speed " + speed_marker)
			_expect_true(
				description.contains(dash_marker),
				label + " actual dash " + dash_marker)
			for relic in opening_relics:
				_expect_true(
					description.contains(tr(relic.display_name)),
					label + " starting relic " + tr(relic.display_name))
	TranslationServer.set_locale(original_locale)


func _signed_percent(value: float) -> String:
	var magnitude: float = absf(snappedf(value, 0.01))
	var amount: String = str(int(round(magnitude))) \
		if is_equal_approx(magnitude, round(magnitude)) \
		else String.num(magnitude, 2)
	return ("+" if value >= 0.0 else "-") + amount + "%"


func _health_marker(locale: String, health: int) -> String:
	match locale:
		"ko":
			return "하트 %d칸" % health
		"ja":
			return "ハート%d" % health
		"zh_CN":
			return "%d颗心" % health
		"zh_TW":
			return "%d顆心" % health
		_:
			return "%d hearts" % health


## Moonlight shots start at the two-handed beacon candle, not character center, and
## still leaves a short cast cue with no separate attack sheet.
func _test_moonlight_cast(player: Player) -> void:
	player.position = Vector2(180.0, 100.0)
	var sprite: AnimatedSprite2D = player.get_node("Sprite") as AnimatedSprite2D
	var cast: MoonlightCast = player.get_node("MoonlightCast") as MoonlightCast
	_expect_true(cast != null, "moonlight-cast dedicated node")
	if cast == null:
		return
	_expect_true(
		sprite.get_index() < cast.get_index() and not cast.show_behind_parent,
		"moonlight cast node renders in front of the character")
	_expect_equal(cast.position, Player.MOONLIGHT_ORIGIN, "moonlight cast node at chest position")
	_expect_equal(
		player.moonlight_origin(),
		Vector2(180.0, 80.0),
		"beacon-candle world muzzle point")
	player.play_moonlight_cast(Vector2.RIGHT, 4)
	_expect_true(
		cast.remaining_seconds() >= 0.15,
		"moonlight cast cue starts at 0.16s")
	_expect_equal(
		cast.cast_direction(),
		Vector2.RIGHT,
		"moonlight cast facing")
	_expect_equal(
		cast.cast_count(),
		4,
		"volley count is reflected on the cast glow")
	cast.call("_process", 0.08)
	_expect_true(
		cast.remaining_seconds() > 0.07 and cast.remaining_seconds() < 0.09,
		"moonlight cast cue time decreases")
	cast.call("_process", 0.09)
	_expect_equal(cast.remaining_seconds(), 0.0, "moonlight cast cue expires after 0.16s")
	_expect_false(cast.is_processing(), "processing stops after the moonlight cast cue expires")
	player.play_moonlight_cast(Vector2.RIGHT, 4)
	player.stop_for_result()
	_expect_equal(
		cast.remaining_seconds(),
		0.0,
		"cast cue cleared on the result screen")


## The held weapon sits at hand height below the face, aims where the last shot
## went, and speaks each hero's own cue. A sidearm cue never cuts a live
## primary flash short.
func _test_weapon_rig(player: Player) -> void:
	var rig: Node2D = player.get_node("WeaponRig") as Node2D
	_expect_true(rig != null, "weapon-rig node rides the player")
	if rig == null:
		return
	_expect_equal(rig.position, player.rest_rig_seat(Vector2.RIGHT),
		"rig grip sits in the painted wrist")
	# Calibrated wrists across the roster: below the candle so the face stays
	# readable, and inside the slash blade's reach on every aim.
	for hero_case in HERO_CASES:
		var hero: Hero = load(hero_case["resource"]) as Hero
		player.call("apply_hero_visual", hero)
		for aim in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var seat: Vector2 = player.rest_rig_seat(aim)
			_expect_true(seat.y > Player.MOONLIGHT_ORIGIN.y,
				"%s %s grip hangs below the candle" % [hero_case["id"], str(aim)])
			_expect_true(seat.distance_to(Player.SLASH_PIVOT) <= 16.0,
				"%s %s grip stays inside the slash reach" % [hero_case["id"], str(aim)])
	var muzzle_want: Dictionary = {
		Hero.AttackProfile.SAGE: WeaponRig.MUZZLE_RIFLE,
		Hero.AttackProfile.KEEPER: WeaponRig.MUZZLE_SCATTER,
		Hero.AttackProfile.KNIGHT: WeaponRig.MUZZLE_CANNON,
	}
	for hero_case in HERO_CASES:
		var hero: Hero = load(hero_case["resource"]) as Hero
		player.call("apply_hero_visual", hero)
		_expect_equal(int(rig.get("_profile")), int(hero.attack_profile),
			str(hero_case["id"]) + " rig draws its own hero")
		var want: StringName = muzzle_want.get(
			hero.attack_profile, WeaponRig.MUZZLE_SPARK) as StringName
		_expect_equal(player.call("_muzzle_kind"), want,
			str(hero_case["id"]) + " speaks its own muzzle cue")
	# Priority on the live path: the Warden's cut owns the flash while it burns,
	# and the sidearm spark waits its turn instead of cutting in.
	var warden: Hero = load("res://resources/heroes/warden.tres") as Hero
	player.call("apply_hero_visual", warden)
	player.set("_attack_cooldown", 0.0)
	player.call("attack", Vector2.RIGHT)
	_expect_equal(rig.get("_kind"), WeaponRig.CUT, "primary cut lights the flash")
	_expect_equal(rig.call("aim"), Vector2.RIGHT, "held blade points at the cut")
	player.call("play_moonlight_cast", Vector2.UP, 1)
	_expect_equal(rig.get("_kind"), WeaponRig.CUT,
		"sidearm spark yields to the live cut")
	_expect_equal(rig.call("aim"), Vector2.RIGHT,
		"held blade keeps its aim while yielding")
	rig.call("_process", 0.2)
	player.call("play_moonlight_cast", Vector2.UP, 1)
	_expect_equal(rig.get("_kind"), WeaponRig.MUZZLE_SPARK,
		"sidearm spark shows once the cut fades")
	# Brief 171: a sidearm cue never relocates the held primary. The spark
	# burns at its own direction while the blade keeps its last primary aim.
	_expect_equal(rig.call("aim"), Vector2.RIGHT,
		"held blade keeps its aim past an idle sidearm cue")
	player.set("_attack_cooldown", 0.0)
	player.call("attack", Vector2.LEFT)
	_expect_equal(rig.get("_kind"), WeaponRig.CUT,
		"primary cut retakes a live sidearm flash")
	# Melee grammar per hero: twins cut twice, the scythe pulses its ring.
	var dancer: Hero = load("res://resources/heroes/dancer.tres") as Hero
	player.call("apply_hero_visual", dancer)
	rig.call("clear")
	player.set("_attack_cooldown", 0.0)
	player.call("attack", Vector2.RIGHT)
	_expect_equal(rig.get("_kind"), WeaponRig.TWIN_CUT, "twin blades cut twice")
	var eclipse: Hero = load("res://resources/heroes/eclipse.tres") as Hero
	player.call("apply_hero_visual", eclipse)
	rig.call("clear")
	player.set("_attack_cooldown", 0.0)
	player.call("attack", Vector2.RIGHT)
	_expect_equal(rig.get("_kind"), WeaponRig.RING_PULSE, "scythe pulses its ring")
	# The Sage mirrors it: rifle owns, bash waits.
	var sage: Hero = load("res://resources/heroes/sage.tres") as Hero
	player.call("apply_hero_visual", sage)
	rig.call("clear")
	player.call("play_moonlight_cast", Vector2.RIGHT, 1)
	player.set("_attack_cooldown", 0.0)
	player.call("attack", Vector2.UP)
	_expect_equal(rig.get("_kind"), WeaponRig.MUZZLE_RIFLE,
		"sidearm bash yields to the live rifle flash")
	# A vertical primary aim re-seats to the up-facing wrist; a sidearm cue
	# never moves the held primary.
	var side_seat: Vector2 = rig.position
	player.call("play_moonlight_cast", Vector2.UP, 1)
	_expect_true(rig.position.distance_to(player.rest_rig_seat(Vector2.UP)) < 0.01,
		"vertical rifle aim seats the up-facing wrist")
	_expect_true(rig.position.distance_to(side_seat) > 2.0,
		"vertical rifle aim leaves the side seat")
	player.call("apply_hero_visual", warden)
	player.set("_attack_cooldown", 0.0)
	player.call("attack", Vector2.UP)
	_expect_true(rig.position.distance_to(player.rest_rig_seat(Vector2.UP)) < 0.01,
		"vertical sword swing seats the up-facing wrist")
	player.call("apply_hero_visual", sage)
	rig.position = Vector2(7.0, -11.0)
	player.set("_attack_cooldown", 0.0)
	player.call("attack", Vector2.UP)
	_expect_equal(rig.position, Vector2(7.0, -11.0),
		"sidearm bash never moves the held rifle")


## Open a live Shrine card and confirm Hero.portrait is consumed by Buy/select UI.
func _expect_atlas(
		texture: Texture2D,
		expected_path: String,
		expected_region: Variant,
		label: String,
	) -> void:
	var atlas_texture: AtlasTexture = texture as AtlasTexture
	_expect_true(atlas_texture != null, label + " AtlasTexture")
	if atlas_texture == null:
		return
	_expect_true(atlas_texture.atlas != null, label + " atlas")
	if atlas_texture.atlas == null:
		return
	_expect_equal(atlas_texture.atlas.resource_path, expected_path, label + " path")
	if expected_region is Rect2:
		_expect_equal(atlas_texture.region, expected_region, label + " region")
	else:
		_expect_equal(
			Vector2i(atlas_texture.region.size),
			expected_region,
			label + " 144x192 region")


func _finish() -> void:
	if _failed > 0:
		printerr("hero-sheet test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("hero-sheet test passed — ", _checked, " case(s)")
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


func _expect_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	_checked += 1
	if absf(actual - expected) <= tolerance:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected~", expected, " actual=", actual)
