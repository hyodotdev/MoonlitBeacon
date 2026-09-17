extends SceneTree

## Confirm runtime sheet assembly for all six player heroes, plus the Player safety fallback.

const PLAYER_SCENE: PackedScene = preload("res://scenes/actors/player.tscn")
const CELL: Vector2i = Vector2i(48, 64)
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
	_expect_equal(sprite.position.y, -24.0, "%s foot-origin position.y" % hero_id)
	_expect_equal(
		hero.preview_crop,
		Rect2i(12, 32, 24, 24),
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
		var damage_marker: String = _signed_percent((effective_damage - 1.0) * 100.0)
		var dash_marker: String = _signed_percent((effective_dash - 1.0) * 100.0)
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
				description.contains(damage_marker),
				label + " actual damage " + damage_marker)
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
			label + " 48x64 region")


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
