extends SceneTree

## Confirm live-combat regular enemies and bosses consume only original sheets.

const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")
const CUSTOM_PREFIX: String = "res://assets/custom/actors/"
const ENEMY_CELL: int = 48
const GUARDIAN_CELL: int = 64
const DIRECTIONS: Array[StringName] = [&"down", &"up", &"left", &"right"]
const GUARDIAN_ANIMATIONS: Array[StringName] = [
	&"guardian_windup",
	&"guardian_alt_windup",
	&"guardian_charge",
	&"guardian_recover",
]

const ENEMY_CASES: Array[Dictionary] = [
	{"id": "wisp", "resource": "res://resources/wisp.tres"},
	{"id": "stalker", "resource": "res://resources/stalker.tres"},
	{"id": "swarm", "resource": "res://resources/swarm.tres"},
	{"id": "ember", "resource": "res://resources/ember.tres"},
	{"id": "drifter", "resource": "res://resources/drifter.tres"},
	{"id": "weaver", "resource": "res://resources/weaver.tres"},
	{"id": "caster", "resource": "res://resources/caster.tres"},
]

const GUARDIAN_CASES: Array[Dictionary] = [
	{
		"id": "forest",
		"resource": "res://resources/guardian_forest.tres",
		"sheet": "res://assets/custom/actors/guardians/forest.png",
		"windup": "res://assets/custom/actors/guardians/forest_windup.png",
		"alt": "res://assets/custom/actors/guardians/forest_windup.png",
		"charge": "res://assets/custom/actors/guardians/forest_charge.png",
		"recover": "res://assets/custom/actors/guardians/forest_recover.png",
	},
	{
		"id": "field",
		"resource": "res://resources/guardian_field.tres",
		"sheet": "res://assets/custom/actors/guardians/field.png",
		"windup":
			"res://assets/custom/actors/guardians/field_windup_cross.png",
		"alt":
			"res://assets/custom/actors/guardians/field_windup_radial.png",
		"charge":
			"res://assets/custom/actors/guardians/field_windup_cross.png",
		"recover": "res://assets/custom/actors/guardians/field_recover.png",
	},
	{
		"id": "camp",
		"resource": "res://resources/guardian_camp.tres",
		"sheet": "res://assets/custom/actors/guardians/camp.png",
		"windup": "res://assets/custom/actors/guardians/camp_windup.png",
		"alt": "res://assets/custom/actors/guardians/camp_windup.png",
		"charge": "res://assets/custom/actors/guardians/camp_windup.png",
		"recover": "res://assets/custom/actors/guardians/camp_recover.png",
	},
	{
		"id": "forest_thorn",
		"resource": "res://resources/guardian_forest_thorn.tres",
		"sheet": "res://assets/custom/actors/guardians/forest_thorn.png",
		"windup": "res://assets/custom/actors/guardians/forest_thorn_windup.png",
		"alt": "res://assets/custom/actors/guardians/forest_thorn_windup.png",
		"charge": "res://assets/custom/actors/guardians/forest_thorn_charge.png",
		"recover": "res://assets/custom/actors/guardians/forest_thorn_recover.png",
	},
	{
		"id": "field_storm",
		"resource": "res://resources/guardian_field_storm.tres",
		"sheet": "res://assets/custom/actors/guardians/field_storm.png",
		"windup":
			"res://assets/custom/actors/guardians/field_storm_windup_cross.png",
		"alt":
			"res://assets/custom/actors/guardians/field_storm_windup_radial.png",
		"charge":
			"res://assets/custom/actors/guardians/field_storm_windup_cross.png",
		"recover": "res://assets/custom/actors/guardians/field_storm_recover.png",
	},
	{
		"id": "camp_siege",
		"resource": "res://resources/guardian_camp_siege.tres",
		"sheet": "res://assets/custom/actors/guardians/camp_siege.png",
		"windup": "res://assets/custom/actors/guardians/camp_siege_windup.png",
		"alt": "res://assets/custom/actors/guardians/camp_siege_windup.png",
		"charge": "res://assets/custom/actors/guardians/camp_siege_windup.png",
		"recover": "res://assets/custom/actors/guardians/camp_siege_recover.png",
	},
]

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_scene_fallback()
	_test_enemies()
	_test_guardians()
	_test_legacy_guardian_resource()
	_finish()


func _test_scene_fallback() -> void:
	var spirit: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	_expect_true(spirit != null, "Spirit scene instance")
	if spirit == null:
		return
	var sprite: AnimatedSprite2D = spirit.get_node("Sprite") as AnimatedSprite2D
	_expect_true(sprite != null, "Spirit fallback Sprite")
	if sprite == null:
		spirit.free()
		return

	var frames: SpriteFrames = sprite.sprite_frames
	_expect_true(frames != null, "Spirit fallback SpriteFrames")
	if frames != null:
		for facing_index in DIRECTIONS.size():
			var animation := StringName("float_" + DIRECTIONS[facing_index])
			_expect_true(
				frames.has_animation(animation),
				"Spirit fallback %s exists" % animation)
			if not frames.has_animation(animation):
				continue
			_expect_equal(
				frames.get_frame_count(animation),
				4,
				"Spirit fallback %s frame count" % animation)
			for frame_index in 4:
				_expect_atlas(
					frames.get_frame_texture(animation, frame_index),
					"res://assets/custom/actors/spirits/wisp.png",
					Rect2(
						facing_index * ENEMY_CELL,
						frame_index * ENEMY_CELL,
						ENEMY_CELL,
						ENEMY_CELL),
					"Spirit fallback %s[%d]" % [animation, frame_index])
	spirit.free()


func _test_enemies() -> void:
	var sheet_paths: Dictionary = {}
	var alpha_masks: Dictionary = {}
	var full_images: Dictionary = {}
	for enemy_case in ENEMY_CASES:
		var enemy_id: String = str(enemy_case["id"])
		var resource_path: String = str(enemy_case["resource"])
		var kind: SpiritKind = load(resource_path) as SpiritKind
		_expect_true(kind != null, "%s SpiritKind loaded" % enemy_id)
		if kind == null:
			continue

		var expected_sheet: String = (
			"res://assets/custom/actors/spirits/%s.png" % enemy_id)
		_expect_texture_path(kind.sheet, expected_sheet, "%s default sheet" % enemy_id)
		_expect_false(
			kind.sheet.resource_path.contains("/third_party/"),
			"%s does not use free-pack assets" % enemy_id)
		_expect_equal(kind.sheet.get_size(), Vector2(192, 192), "%s sheet size" % enemy_id)
		_expect_equal(kind.cell, ENEMY_CELL, "%s cell size" % enemy_id)
		_expect_equal(kind.facings, 4, "%s facing count" % enemy_id)
		_expect_equal(kind.frames, 4, "%s frame count" % enemy_id)
		_expect_equal(kind.lift, -8.0, "%s shadow foot origin" % enemy_id)
		_expect_equal(kind.tint, Color.WHITE, "%s original palette preserved" % enemy_id)

		_expect_false(
			sheet_paths.has(kind.sheet.resource_path),
			"%s dedicated sheet path" % enemy_id)
		sheet_paths[kind.sheet.resource_path] = true
		var image: Image = kind.sheet.get_image()
		_expect_true(image != null, "%s runtime image" % enemy_id)
		if image != null:
			var alpha_digest: String = _image_digest(image, true)
			var full_digest: String = _image_digest(image, false)
			_expect_false(
				alpha_masks.has(alpha_digest),
				"%s silhouette distinct from other regular enemies" % enemy_id)
			_expect_false(
				full_images.has(full_digest),
				"%s palette and frames distinct from other regular enemies" % enemy_id)
			alpha_masks[alpha_digest] = true
			full_images[full_digest] = true

		_test_runtime_kind(enemy_id, kind, expected_sheet, 4, 4, ENEMY_CELL)

	_expect_equal(sheet_paths.size(), 7, "7 dedicated regular-enemy sheets")
	_expect_equal(alpha_masks.size(), 7, "7 regular-enemy silhouettes")


func _test_guardians() -> void:
	var base_masks: Dictionary = {}
	var base_images: Dictionary = {}
	for guardian_case in GUARDIAN_CASES:
		var guardian_id: String = str(guardian_case["id"])
		var kind: SpiritKind = load(str(guardian_case["resource"])) as SpiritKind
		_expect_true(kind != null, "%s guardian loaded" % guardian_id)
		if kind == null:
			continue

		_expect_texture_path(
			kind.sheet, str(guardian_case["sheet"]), "%s idle sheet" % guardian_id)
		_expect_texture_path(
			kind.guardian_windup_sheet,
			str(guardian_case["windup"]),
			"%s windup sheet" % guardian_id)
		_expect_texture_path(
			kind.guardian_alt_windup_sheet,
			str(guardian_case["alt"]),
			"%s alt windup sheet" % guardian_id)
		_expect_texture_path(
			kind.guardian_charge_sheet,
			str(guardian_case["charge"]),
			"%s charge slot" % guardian_id)
		_expect_texture_path(
			kind.guardian_recover_sheet,
			str(guardian_case["recover"]),
			"%s recover sheet" % guardian_id)

		for texture: Texture2D in [
			kind.sheet,
			kind.guardian_windup_sheet,
			kind.guardian_alt_windup_sheet,
			kind.guardian_charge_sheet,
			kind.guardian_recover_sheet,
		]:
			_expect_true(texture != null, "%s guardian state slot" % guardian_id)
			if texture != null:
				_expect_true(
					texture.resource_path.begins_with(CUSTOM_PREFIX),
					"%s state-slot custom path" % guardian_id)
				_expect_false(
					texture.resource_path.contains("/third_party/"),
					"%s does not use free-pack assets" % guardian_id)

		_expect_equal(
			kind.sheet.get_size(),
			Vector2(384, 64),
			"%s idle 6-frame size" % guardian_id)
		for state_texture: Texture2D in [
			kind.guardian_windup_sheet,
			kind.guardian_alt_windup_sheet,
			kind.guardian_charge_sheet,
			kind.guardian_recover_sheet,
		]:
			_expect_true(
				state_texture.get_size().x >= 384
					and state_texture.get_size().y == 64,
				"%s state sheet at least 6 frames" % guardian_id)
		_expect_equal(kind.cell, GUARDIAN_CELL, "%s cell size" % guardian_id)
		_expect_equal(kind.facings, 1, "%s facing count" % guardian_id)
		_expect_equal(kind.frames, 6, "%s idle frame count" % guardian_id)
		_expect_equal(
			kind.guardian_state_frames,
			6,
			"%s state frame count" % guardian_id)
		_expect_equal(kind.lift, -24.0, "%s shadow foot origin" % guardian_id)
		_expect_equal(kind.tint, Color.WHITE, "%s original palette preserved" % guardian_id)

		var image: Image = kind.sheet.get_image()
		_expect_true(image != null, "%s runtime image" % guardian_id)
		if image != null:
			var alpha_digest: String = _image_digest(image, true)
			var full_digest: String = _image_digest(image, false)
			_expect_false(
				base_masks.has(alpha_digest),
				"%s boss silhouette distinct" % guardian_id)
			_expect_false(
				base_images.has(full_digest),
				"%s boss palette and motion distinct" % guardian_id)
			base_masks[alpha_digest] = true
			base_images[full_digest] = true

		_test_runtime_kind(
			guardian_id, kind, str(guardian_case["sheet"]), 1, 6, GUARDIAN_CELL)

	_expect_equal(base_masks.size(), 6, "6 terrain-specific boss silhouettes")
	_expect_equal(base_images.size(), 6, "6 terrain-specific boss palettes and motions")


func _test_runtime_kind(
		actor_id: String,
		kind: SpiritKind,
		expected_sheet: String,
		facings: int,
		frame_count: int,
		cell: int,
	) -> void:
	var spirit: Node2D = SPIRIT_SCENE.instantiate() as Node2D
	_expect_true(spirit != null, "%s runtime instance" % actor_id)
	if spirit == null:
		return
	spirit.set("kind", kind)
	spirit.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(spirit)
	var sprite: AnimatedSprite2D = spirit.get_node("Sprite") as AnimatedSprite2D
	_expect_true(sprite != null, "%s runtime Sprite" % actor_id)
	var hit_flash: Color = spirit.call("_white_flash_modulate")
	_expect_true(
		hit_flash.r >= 1.64
			and hit_flash.g >= 1.64
			and hit_flash.b >= 1.64,
		"%s custom-palette hit flash" % actor_id)
	if sprite != null:
		var frames: SpriteFrames = sprite.sprite_frames
		_expect_true(frames != null, "%s runtime SpriteFrames" % actor_id)
		if frames != null:
			for facing_index in facings:
				var animation := StringName(
					"float_" + DIRECTIONS[min(facing_index, DIRECTIONS.size() - 1)])
				_expect_true(
					frames.has_animation(animation),
					"%s %s exists" % [actor_id, animation])
				if not frames.has_animation(animation):
					continue
				_expect_equal(
					frames.get_frame_count(animation),
					frame_count,
					"%s %s frame count" % [actor_id, animation])
				for frame_index in frame_count:
					var region := Rect2(
						frame_index * cell if facings == 1 else facing_index * cell,
						0 if facings == 1 else frame_index * cell,
						cell,
						cell)
					_expect_atlas(
						frames.get_frame_texture(animation, frame_index),
						expected_sheet,
						region,
						"%s %s[%d]" % [actor_id, animation, frame_index])

			if kind.behavior == SpiritKind.Behavior.GUARDIAN:
				for animation_index in GUARDIAN_ANIMATIONS.size():
					var state_animation: StringName = (
						GUARDIAN_ANIMATIONS[animation_index])
					_expect_true(
						frames.has_animation(state_animation),
						"%s %s state animation" % [actor_id, state_animation])
					if not frames.has_animation(state_animation):
						continue
					_expect_equal(
						frames.get_frame_count(state_animation),
						6,
						"%s %s frame count" % [actor_id, state_animation])
					var expected_texture: Texture2D = [
						kind.guardian_windup_sheet,
						kind.guardian_alt_windup_sheet,
						kind.guardian_charge_sheet,
						kind.guardian_recover_sheet,
					][animation_index]
					for frame_index in 6:
						_expect_atlas(
							frames.get_frame_texture(
								state_animation, frame_index),
							expected_texture.resource_path,
							Rect2(frame_index * GUARDIAN_CELL, 0, 64, 64),
							"%s %s[%d]"
								% [actor_id, state_animation, frame_index])
	spirit.free()


func _test_legacy_guardian_resource() -> void:
	# No longer used directly in Arena, but a compat resource the course/editor can still open
	# must not fall back to the free guardian.png.
	var kind: SpiritKind = load("res://resources/guardian.tres") as SpiritKind
	_expect_true(kind != null, "compat guardian resource")
	if kind == null:
		return
	for texture: Texture2D in [
		kind.sheet,
		kind.guardian_windup_sheet,
		kind.guardian_alt_windup_sheet,
		kind.guardian_charge_sheet,
		kind.guardian_recover_sheet,
	]:
		_expect_true(texture != null, "compat guardian state slot")
		if texture != null:
			_expect_true(
				texture.resource_path.begins_with(CUSTOM_PREFIX),
				"compat guardian custom path")
			_expect_false(
				texture.resource_path.contains("/third_party/"),
				"compat guardian does not use free-pack assets")
	_expect_equal(kind.cell, GUARDIAN_CELL, "compat guardian cell size")
	_expect_equal(kind.frames, 6, "compat guardian frame count")
	_expect_equal(kind.lift, -24.0, "compat guardian foot origin")


func _image_digest(image: Image, alpha_only: bool) -> String:
	var bytes := PackedByteArray()
	if alpha_only:
		bytes.resize(image.get_width() * image.get_height())
		var offset: int = 0
		for y in image.get_height():
			for x in image.get_width():
				bytes[offset] = 255 if image.get_pixel(x, y).a > 0.0 else 0
				offset += 1
	else:
		bytes = image.get_data()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _expect_texture_path(
		texture: Texture2D,
		expected_path: String,
		label: String,
	) -> void:
	_expect_true(texture != null, label + " Texture2D")
	if texture == null:
		return
	_expect_equal(texture.resource_path, expected_path, label + " path")


func _expect_atlas(
		texture: Texture2D,
		expected_path: String,
		expected_region: Rect2,
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
	_expect_equal(atlas_texture.region, expected_region, label + " region")


func _finish() -> void:
	if _failed > 0:
		printerr("spirit/guardian sheet test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("spirit/guardian sheet test passed — ", _checked, " case(s)")
	quit(0)


func _expect_false(actual: bool, label: String) -> void:
	_expect_equal(actual, false, label)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)
