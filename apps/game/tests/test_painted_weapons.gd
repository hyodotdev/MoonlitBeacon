extends SceneTree

## Painted held weapons: art, seats, light, and flash behavior.
##
## The six original shaded sheets (`assets/custom/items/weapons/`) replace the
## old primitive strokes in `WeaponRig` without touching combat: same aim,
## depth, signals, muzzle seats, timing, and spawn points. Each sheet holds
## four texels per logical pixel and draws at 0.25 world scale through
## per-item Linear filtering, so fine lantern, ring, blade, and rifle detail
## survives at real 2x/3x output. This locks the art side (exact 4x sheets,
## clean alpha and margins, calibrated tips and grips, distinct silhouettes,
## hero-matched light) and the behavior side (seats, flashes, clear/pause/
## result paths) together, so moving a seat, a pivot, or a tint breaks loudly
## here instead of silently drifting the muzzle off the painted gun.
##
## Direct-callable, no scene:
##     pnpm godot:isolated --timeout 150 --script res://tests/test_painted_weapons.gd

const PLAYER_SCENE: PackedScene = preload("res://scenes/actors/player.tscn")
const WEAPON_DIR: String = "res://assets/custom/items/weapons"
const HERO_IDS: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage",
]
const PROFILES: Array[Hero.AttackProfile] = [
	Hero.AttackProfile.WARDEN, Hero.AttackProfile.DANCER,
	Hero.AttackProfile.KEEPER, Hero.AttackProfile.KNIGHT,
	Hero.AttackProfile.ECLIPSE, Hero.AttackProfile.SAGE,
]
## Frozen logical sheet sizes (content plus the 1px logical margin).
const LOGICAL_SIZE: Dictionary = {
	"warden": Vector2i(17, 5), "dancer": Vector2i(15, 9),
	"keeper": Vector2i(15, 9), "knight": Vector2i(15, 7),
	"eclipse": Vector2i(17, 8), "sage": Vector2i(22, 7),
}
## Opaque (alpha>=32) texel counts of the committed sheets.
const SHEET_OPAQUE: Dictionary = {
	"warden": 246, "dancer": 576, "keeper": 549,
	"knight": 627, "eclipse": 365, "sage": 422,
}
## Fine-detail floors. A 4x nearest upscale of the old tiny sheets would keep
## their counts (at most 53 colors, 36 alpha levels, ~32 gradient texels), so
## these prove the repack came from the full-resolution master.
const MIN_RGB_COLORS: int = 150
const MIN_ALPHA_LEVELS: int = 60
const MIN_GRADIENT_TEXELS: int = 60
## Independent muzzle seats. Must match `WeaponRig.muzzle_length`, never read it.
const SEATS: Dictionary = {"sage": 16.0, "keeper": 9.0, "knight": 9.0}
## Independent sheet-tint math: Player night tint from `player.tscn`.
const NIGHT_TINT: Color = Color(0.315, 0.35, 0.57, 1.0)
const DIAGONAL: float = 0.70710678
const AIMS: Array[Vector2] = [
	Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
	Vector2(DIAGONAL, DIAGONAL), Vector2(-DIAGONAL, DIAGONAL),
	Vector2(DIAGONAL, -DIAGONAL), Vector2(-DIAGONAL, -DIAGONAL),
]
const CARDINAL_AIMS: Array[Vector2] = [
	Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
]
## Paint threshold shared with the pack tool's core threshold.
const CORE: float = 32.0 / 255.0

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_sheets_bounded()
	_test_source_detail()
	_test_muzzle_consts_preserved()
	_test_tip_coincidence()
	await _test_spawn_coincidence()
	_test_silhouettes_distinct()
	_test_lighting_no_washout()
	_test_flash_behavior_preserved()
	await _test_player_seats_untouched()
	_finish()


## Six exact-4x files, clean alpha, exact margins, no matte, no strays.
func _test_sheets_bounded() -> void:
	var names: Array[String] = []
	var total_bytes: int = 0
	for hero_id in HERO_IDS:
		var profile: Hero.AttackProfile = PROFILES[HERO_IDS.find(hero_id)]
		_expect_equal(WeaponRig.painted_name(profile), hero_id,
			hero_id + " rig name maps to its sheet")
		var sheet: Texture2D = WeaponRig.painted_sheet(profile)
		_expect_true(sheet != null, hero_id + " sheet loads")
		if sheet == null:
			continue
		_expect_true(str(sheet.resource_path).ends_with("weapons/%s.png" % hero_id),
			hero_id + " sheet lives under weapons/")
		var logical: Vector2i = LOGICAL_SIZE[hero_id]
		_expect_equal(
			Vector2i(int(sheet.get_size().x), int(sheet.get_size().y)),
			Vector2i(logical.x * 4, logical.y * 4),
			hero_id + " sheet is exactly 4x logical")
		_expect_true(sheet.get_width() <= 96 and sheet.get_height() <= 40,
			hero_id + " sheet bounded")
		var path: String = "%s/%s.png" % [WEAPON_DIR, hero_id]
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		_expect_true(file != null, hero_id + " sheet file opens")
		if file != null:
			_expect_true(file.get_length() <= 6144,
				hero_id + " sheet file bounded (%d bytes)" % file.get_length())
			total_bytes += int(file.get_length())
		# File truth, not the imported texture: Godot's own alpha-border fix
		# bleeds neighbor RGB into transparent pixels at import, which is
		# correct for filtering and would read as matte here.
		var image: Image = _file_image(hero_id)
		_expect_true(image != null, hero_id + " sheet pixels readable")
		if image == null:
			continue
		var width: int = image.get_width()
		var height: int = image.get_height()
		_expect_true(_matte_clean(image), hero_id + " transparent pixels hold no matte")
		for x in width:
			for edge in 4:
				_expect_equal(image.get_pixel(x, edge).a, 0.0,
					hero_id + " top margin transparent")
				_expect_equal(image.get_pixel(x, height - 1 - edge).a, 0.0,
					hero_id + " bottom margin transparent")
		for y in height:
			for edge in 4:
				_expect_equal(image.get_pixel(edge, y).a, 0.0,
					hero_id + " left margin transparent")
				_expect_equal(image.get_pixel(width - 1 - edge, y).a, 0.0,
					hero_id + " right margin transparent")
		names.append(hero_id)
	_expect_equal(names.size(), 6, "six hero sheets")
	_expect_true(total_bytes <= 32768, "six sheets total bounded (%d)" % total_bytes)
	var dir: DirAccess = DirAccess.open(WEAPON_DIR)
	_expect_true(dir != null, "weapons dir opens")
	if dir != null:
		var stray: int = 0
		for entry in dir.get_files():
			if entry.ends_with(".png") and not HERO_IDS.has(entry.get_basename()):
				stray += 1
		_expect_equal(stray, 0, "no stray sheets beside the six")


## Fine master detail survives: color, gradient, and edge richness no upscale
## of the old tiny sheets could hold.
func _test_source_detail() -> void:
	for hero_id in HERO_IDS:
		var image: Image = _file_image(hero_id)
		_expect_true(image != null, hero_id + " art available for the detail check")
		if image == null:
			continue
		var colors: Dictionary = {}
		var levels: Dictionary = {}
		var opaque: int = 0
		var gradient: int = 0
		var dust: int = 0
		for y in image.get_height():
			for x in image.get_width():
				var pixel: Color = image.get_pixel(x, y)
				var alpha: int = int(round(pixel.a * 255.0))
				if alpha >= 32:
					opaque += 1
					levels[alpha] = true
					colors["%d,%d,%d" % [
						int(round(pixel.r * 255.0)),
						int(round(pixel.g * 255.0)),
						int(round(pixel.b * 255.0))]] = true
				if alpha >= 8 and alpha <= 250:
					gradient += 1
				elif alpha >= 1 and alpha <= 7:
					dust += 1
		_expect_equal(opaque, int(SHEET_OPAQUE[hero_id]),
			hero_id + " committed opaque count")
		_expect_true(colors.size() >= MIN_RGB_COLORS,
			hero_id + " keeps master color depth (%d)" % colors.size())
		_expect_true(levels.size() >= MIN_ALPHA_LEVELS,
			hero_id + " keeps master alpha depth (%d)" % levels.size())
		_expect_true(gradient >= MIN_GRADIENT_TEXELS,
			hero_id + " keeps soft edges (%d)" % gradient)
		_expect_true(dust <= 160, hero_id + " fringe dust bounded (%d)" % dust)


## Seats and spans are combat numbers: frozen, not recomputed.
func _test_muzzle_consts_preserved() -> void:
	_expect_equal(WeaponRig.muzzle_length(WeaponRig.MUZZLE_RIFLE), 16.0,
		"rifle seat stays 16")
	_expect_equal(WeaponRig.muzzle_length(WeaponRig.MUZZLE_SCATTER), 9.0,
		"scatter seat stays 9")
	_expect_equal(WeaponRig.muzzle_length(WeaponRig.MUZZLE_CANNON), 9.0,
		"cannon seat stays 9")
	_expect_equal(WeaponRig.muzzle_length(WeaponRig.MUZZLE_SPARK), 9.0,
		"spark seat stays 9")
	_expect_equal(WeaponRig.FLASH_SECONDS, 0.16, "flash span stays 0.16s")
	_expect_equal(WeaponRig.CANNON_FLASH_SECONDS, 0.22, "cannon span stays 0.22s")
	_expect_equal(WeaponRig.TEXTURE_SCALE, 4.0, "texture holds four texels per pixel")
	_expect_equal(WeaponRig.DRAW_SCALE, 0.25, "draw compensates at quarter scale")


## Painted tips and real spawn seats coincide in every direction.
func _test_tip_coincidence() -> void:
	for hero_id in HERO_IDS:
		var profile: Hero.AttackProfile = PROFILES[HERO_IDS.find(hero_id)]
		var sheet: Texture2D = WeaponRig.painted_sheet(profile)
		_expect_true(sheet != null, hero_id + " art available for the seat check")
		var image: Image = _file_image(hero_id)
		if sheet == null or image == null:
			continue
		var tip := Vector2(WeaponRig.logical_tip(profile))
		var pivot: Vector2 = WeaponRig.logical_pivot(profile)
		var logical: Vector2i = LOGICAL_SIZE[hero_id]
		_expect_true(_inside_logical(logical, tip), hero_id + " tip inside its sheet")
		_expect_true(_inside_logical(logical, pivot), hero_id + " pivot inside its sheet")
		# The two spaces cannot drift: texture pivots are exactly four times
		# logical, and the shared world transform seats them.
		_expect_equal(WeaponRig.texture_pivot(profile), pivot * 4.0,
			hero_id + " texture pivot is 4x logical")
		# Placement guard: the calibrated tip band holds the visual end of the
		# paint. A tip that slides off the end (or a sheet that grows past it)
		# puts the seat mid-barrel, so this fails on a single logical pixel.
		var rightmost: int = -1
		for x in image.get_width():
			for y in image.get_height():
				if image.get_pixel(x, y).a >= CORE:
					rightmost = x
					break
		_expect_true(rightmost >= int(tip.x) * 4 and rightmost <= int(tip.x) * 4 + 3,
			hero_id + " paint ends in its tip band")
		if HeroWeapons.primary_side(profile) == HeroWeapons.Side.RANGED:
			var seat: float = float(SEATS[hero_id])
			# Structural coincidence: the pivot sits one seat behind the tip
			# on the barrel row, so the drawn tip is the seat by construction.
			_expect_equal(tip - pivot, Vector2(seat, 0.0),
				hero_id + " pivot sits one seat behind its tip")
			_expect_true(_band_has_paint(image, tip, 0),
				hero_id + " tip band sits on paint")
			_expect_true(_band_has_paint(image, pivot, 0),
				hero_id + " pivot band sits on paint")
			for aim in AIMS:
				var drawn: Vector2 = WeaponRig.drawn_logical_point(profile, aim, tip)
				_expect_true(drawn.distance_to(aim.normalized() * seat) < 0.001,
					hero_id + " tip draws on its %s seat" % str(aim))
				_expect_equal(WeaponRig.painted_anchor(profile, aim), Vector2.ZERO,
					hero_id + " gun pivots on the rig origin")
		else:
			# Melee grips hang on the legacy hand point; blades keep their
			# drawn lengths.
			var grip: Vector2i = _melee_grip(profile)
			_expect_equal(pivot, Vector2(grip), hero_id + " pivot is its grip")
			var want_length: float = {"warden": 14.0, "dancer": 12.0, "eclipse": 14.0}[hero_id]
			_expect_true(absf((tip - pivot).length() - want_length) < 0.001,
				hero_id + " blade keeps its drawn length")
			for aim in AIMS:
				var flat: Vector2 = aim.normalized()
				_expect_true(
					WeaponRig.painted_anchor(profile, aim).distance_to(-flat * 2.0) < 0.001,
					hero_id + " grip hangs 2px toward the body")
				var drawn: Vector2 = WeaponRig.drawn_logical_point(profile, aim, tip)
				var along: Vector2 = (drawn - WeaponRig.painted_anchor(profile, aim)).normalized()
				_expect_true(along.distance_to(flat) < 0.001,
					hero_id + " blade follows its aim")
			if hero_id == "dancer":
				_test_twin_straddle(image)
			else:
				_expect_true(_band_has_paint(image, pivot, 1),
					hero_id + " grip band sits on paint")
				_expect_true(_band_has_paint(image, tip, 1),
					hero_id + " tip band sits on paint")


func _melee_grip(profile: Hero.AttackProfile) -> Vector2i:
	match profile:
		Hero.AttackProfile.DANCER:
			return WeaponRig.LOGICAL_GRIP_DANCER
		Hero.AttackProfile.ECLIPSE:
			return WeaponRig.LOGICAL_GRIP_ECLIPSE
	return WeaponRig.LOGICAL_GRIP_WARDEN


## Paint anywhere inside the 4x4 texel band of one logical pixel.
func _band_has_paint(image: Image, logical: Vector2, slack: int) -> bool:
	var x0: int = int(logical.x) * 4 - slack
	var y0: int = int(logical.y) * 4 - slack
	for y in range(y0, y0 + 4 + slack * 2):
		for x in range(x0, x0 + 4 + slack * 2):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if image.get_pixel(x, y).a >= CORE:
				return true
	return false


## Twin daggers straddle the hand the way twin tips straddle the tip row.
func _test_twin_straddle(image: Image) -> void:
	var grip: Vector2i = WeaponRig.LOGICAL_GRIP_DANCER
	var tip: Vector2i = WeaponRig.LOGICAL_TIP_DANCER
	_expect_equal(WeaponRig.LOGICAL_DANCER_UPPER_ROW, 2, "upper handle row")
	_expect_equal(WeaponRig.LOGICAL_DANCER_LOWER_ROW, 6, "lower handle row")
	var above: int = 0
	var below: int = 0
	for x in range(4, maxi(image.get_width() / 3, 8)):
		for y in image.get_height():
			if image.get_pixel(x, y).a < CORE:
				continue
			if y < grip.y * 4:
				above += 1
			elif y > grip.y * 4 + 3:
				below += 1
	_expect_true(above > 0 and below > 0, "twin handles straddle the grip band")
	var tips_above: int = 0
	var tips_below: int = 0
	for y in range(maxi(tip.y * 4 - 8, 0), mini(tip.y * 4 + 12, image.get_height())):
		if image.get_pixel(tip.x * 4 + 3, y).a < CORE:
			continue
		if y < tip.y * 4:
			tips_above += 1
		elif y > tip.y * 4 + 3:
			tips_below += 1
	_expect_true(tips_above > 0 and tips_below > 0, "twin tips straddle the tip band")


## A painted gun's tip and its real projectile spawn coincide on a live Player
## in all four aims: production seating, production cast, measured in world.
func _test_spawn_coincidence() -> void:
	var player: Player = _add_player()
	player.position = Vector2(400, 220)
	await process_frame
	for hero_id in ["sage", "keeper", "knight"]:
		var hero: Hero = load("res://resources/heroes/%s.tres" % hero_id) as Hero
		_expect_true(player.apply_hero_visual(hero), hero_id + " visual applies")
		var profile: Hero.AttackProfile = HeroWeapons.profile_of(hero_id)
		var tip := Vector2(WeaponRig.logical_tip(profile))
		for aim in CARDINAL_AIMS:
			player.call("face_toward", aim)
			player.call("play_moonlight_cast", aim, 1)
			var rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
			_expect_true((rig.aim() - aim).length() < 0.001,
				hero_id + " %s cast aims its rig" % str(aim))
			var drawn: Vector2 = rig.to_global(
				WeaponRig.drawn_logical_point(profile, rig.aim(), tip))
			var muzzle: Vector2 = player.call("muzzle_origin", rig.aim())
			_expect_true(drawn.distance_to(muzzle) < 0.01,
				hero_id + " painted tip meets its spawn %s" % str(aim))
			rig.clear()
	player.queue_free()
	await process_frame


func _inside_logical(logical: Vector2i, point: Vector2) -> bool:
	return point.x >= 0.0 and point.y >= 0.0 \
		and point.x < float(logical.x) and point.y < float(logical.y)


## Six visibly different weapons: sword, twin fangs, lantern gun, ring cannon,
## crescent reaper, needle rifle. Each family carries a shape no other does.
## Geometry is four times the frozen logical features.
func _test_silhouettes_distinct() -> void:
	var images: Dictionary = {}
	for hero_id in HERO_IDS:
		images[hero_id] = _file_image(hero_id)
	# Sword: one long blade span on its row band.
	var sword: Image = images["warden"]
	_expect_true(_row_span(sword, 8, 11) >= 48, "sword blade spans its sheet")
	# Twin fangs: two long blades with a near-empty gap band between.
	var fangs: Image = images["dancer"]
	_expect_true(_row_span(fangs, 8, 11) >= 36, "upper fang spans its sheet")
	_expect_true(_row_span(fangs, 24, 27) >= 36, "lower fang spans its sheet")
	var gap: int = _row_count(fangs, 16, 19)
	_expect_true(gap <= 64, "twin gap band stays near empty")
	_expect_true(gap * 4 < _row_count(fangs, 8, 11), "twin gap reads against the blades")
	# Lantern gun: lamp above the barrel band, stock below-left, flared bell right.
	var lantern: Image = images["keeper"]
	_expect_true(_block_count(lantern, 16, 51, 4, 7) >= 20, "lantern lamp rides above")
	_expect_true(_block_count(lantern, 4, 11, 12, 27) >= 32, "lantern stock hangs below")
	_expect_true(_block_count(lantern, 44, 55, 4, 15) >= 24, "lantern bell flares right")
	# Ring cannon: a tall aperture in the right columns on a stubby body.
	var cannon: Image = images["knight"]
	_expect_true(_column_span(cannon, 44, 55) >= 12, "cannon aperture stands tall")
	# Crescent reaper: a long haft with curls above and below at the right end.
	var reaper: Image = images["eclipse"]
	_expect_true(_row_span(reaper, 12, 15) >= 44, "reaper haft spans its sheet")
	_expect_true(_block_count(reaper, 40, 63, 4, 11) >= 16, "reaper upper curl shows")
	_expect_true(_block_count(reaper, 40, 63, 20, 27) >= 16, "reaper lower curl shows")
	# Needle rifle: the longest sheet, one barrel line, sight above, stock below.
	var rifle: Image = images["sage"]
	_expect_true(_row_span(rifle, 12, 15) >= 60, "rifle barrel runs its sheet")
	_expect_true(_block_count(rifle, 12, 43, 8, 11) >= 24, "rifle sight sits above")
	_expect_true(_block_count(rifle, 4, 15, 16, 23) >= 16, "rifle stock hangs below")


func _row_span(image: Image, y0: int, y1: int) -> int:
	var first: int = image.get_width()
	var last: int = -1
	for y in range(y0, y1 + 1):
		for x in image.get_width():
			if image.get_pixel(x, y).a >= CORE:
				first = mini(first, x)
				last = maxi(last, x)
	return maxi(last - first + 1, 0)


func _row_count(image: Image, y0: int, y1: int) -> int:
	var count: int = 0
	for y in range(y0, y1 + 1):
		for x in image.get_width():
			if image.get_pixel(x, y).a >= CORE:
				count += 1
	return count


func _block_count(image: Image, x0: int, x1: int, y0: int, y1: int) -> int:
	var count: int = 0
	for y in range(y0, mini(y1, image.get_height() - 1) + 1):
		for x in range(x0, mini(x1, image.get_width() - 1) + 1):
			if image.get_pixel(x, y).a >= CORE:
				count += 1
	return count


func _column_span(image: Image, x0: int, x1: int) -> int:
	var rows: Dictionary = {}
	for y in image.get_height():
		for x in range(x0, mini(x1, image.get_width() - 1) + 1):
			if image.get_pixel(x, y).a >= CORE:
				rows[y] = true
	return rows.size()


## Painted metal wears the hero's own light: no washout, no sink, no clip.
## The 4x sheets resolve through per-item Linear filtering.
func _test_lighting_no_washout() -> void:
	_expect_equal(WeaponRig.PAINT_TINT, Player.HERO_READABILITY_TINT,
		"sheets wear the hero readability tint")
	var player: Player = _add_player()
	_expect_equal(player.modulate, NIGHT_TINT, "Player night tint as measured")
	var effective := Color(
		WeaponRig.PAINT_TINT.r * player.modulate.r,
		WeaponRig.PAINT_TINT.g * player.modulate.g,
		WeaponRig.PAINT_TINT.b * player.modulate.b, 1.0)
	var channels: Array[float] = [effective.r, effective.g, effective.b]
	for channel in channels.size():
		_expect_true(absf(channels[channel] - 1.0) < 0.005,
			"sheet light lands on channel %d" % channel)
	# The legacy 2.4 boost would push blue to 1.425 and clip the paint.
	_expect_true(effective.b <= 1.01, "sheet blue never clips")
	_expect_equal(WeaponRig.FLASH_BOOST, Vector3(2.4, 2.4, 2.5),
		"flames keep the legacy boost explicitly")
	var rig: WeaponRig = WeaponRig.new()
	root.add_child(rig)
	_expect_equal(rig.self_modulate, Color.WHITE, "rig node carries no boost")
	_expect_equal(rig.z_index, 2, "rig depth stays above the body")
	_expect_equal(rig.get_child_count(), 0, "rig stays one node")
	_expect_equal(rig.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR,
		"rig sheets resolve through Linear")
	var body_rig: WeaponRig = player.get_node("WeaponRig") as WeaponRig
	_expect_equal(body_rig.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR,
		"held sheets resolve through Linear")
	rig.queue_free()
	player.queue_free()
	await process_frame


## Flash grammar unchanged: spans, seats, sidearm rule, and the idle rest pose.
func _test_flash_behavior_preserved() -> void:
	var rig: WeaponRig = WeaponRig.new()
	root.add_child(rig)
	_expect_equal(rig.process_mode, Node.PROCESS_MODE_INHERIT,
		"rig freezes with the tree")
	_expect_equal(rig.aim(), Vector2.RIGHT, "rig rests pointing right")
	rig.flash(Vector2.LEFT, WeaponRig.CUT)
	_expect_equal(rig.aim(), Vector2.LEFT, "flash turns the held weapon")
	_expect_equal(rig.get("_kind"), WeaponRig.CUT, "cut kind lights")
	_expect_equal(float(rig.get("_span")), 0.16, "cut span 0.16s")
	# A sidearm cue never cuts a live primary flash short.
	rig.flash(Vector2.UP, WeaponRig.MUZZLE_SPARK, true)
	_expect_equal(rig.get("_kind"), WeaponRig.CUT, "sidearm yields to a live primary")
	_expect_equal(rig.aim(), Vector2.LEFT, "sidearm never turns the held weapon")
	rig.clear()
	_expect_equal(rig.get("_kind"), &"", "clear drops the kind")
	_expect_equal(rig.is_processing(), false, "clear sleeps the timer")
	_expect_equal(rig.aim(), Vector2.LEFT, "clear keeps the last aim")
	rig.flash(Vector2.UP, WeaponRig.MUZZLE_SPARK, true)
	_expect_equal(rig.get("_kind"), WeaponRig.MUZZLE_SPARK, "idle sidearm lights")
	rig.flash(Vector2.ZERO, WeaponRig.MUZZLE_CANNON)
	_expect_equal(rig.aim(), Vector2.UP, "empty aim never turns the weapon")
	_expect_equal(float(rig.get("_span")), 0.22, "cannon span 0.22s")
	rig.call("_process", 0.3)
	_expect_equal(rig.get("_kind"), &"", "span expiry drops the kind")
	_expect_equal(rig.is_processing(), false, "expiry sleeps the timer")
	# No idle motion: processing a quiet rig never aims or lights anything.
	var quiet: WeaponRig = WeaponRig.new()
	root.add_child(quiet)
	for tick in 5:
		quiet.call("_process", 0.2)
	_expect_equal(quiet.aim(), Vector2.RIGHT, "quiet rig never turns")
	_expect_equal(quiet.get("_kind"), &"", "quiet rig never lights")
	rig.queue_free()
	quiet.queue_free()
	await process_frame


## Projectile seats and hand seating stay exactly where they were.
func _test_player_seats_untouched() -> void:
	var player: Player = _add_player()
	await process_frame
	for hero_id in ["sage", "keeper", "knight"]:
		var hero: Hero = load("res://resources/heroes/%s.tres" % hero_id) as Hero
		_expect_true(player.apply_hero_visual(hero), hero_id + " visual applies")
		for aim in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var flat: Vector2 = aim.normalized()
			var want: Vector2 = player.to_global(Player.WEAPON_GRIP + Player.side_shift(flat)) \
				+ flat * float(SEATS[hero_id])
			_expect_true(
				(player.call("muzzle_origin", aim) as Vector2).distance_to(want) < 0.01,
				hero_id + " muzzle helper matches its seat")
	# Melee backup still leaves from the candle, not the painted blade.
	var warden: Hero = load("res://resources/heroes/warden.tres") as Hero
	_expect_true(player.apply_hero_visual(warden), "warden visual applies")
	_expect_true(
		(player.call("muzzle_origin", Vector2.RIGHT) as Vector2)
			.distance_to(player.call("moonlight_origin") as Vector2) < 0.01,
		"melee muzzle stays on the candle")
	# Result path: a live flash dies with the run.
	player.call("attack", Vector2.RIGHT)
	_expect_equal(
		(player.get_node("WeaponRig") as Node).get("_kind"), WeaponRig.CUT,
		"real swing lights the rig")
	player.call("stop_for_result")
	_expect_equal(
		(player.get_node("WeaponRig") as Node).get("_kind"), &"",
		"result clears the rig")
	player.queue_free()
	await process_frame


## Player entering the tree with its camera on the physics callback the
## project's interpolation requires. Configured before add_child so entering
## never trips the override warning.
func _add_player() -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	(player.get_node("Cam") as Camera2D).process_callback = \
		Camera2D.CAMERA2D_PROCESS_PHYSICS
	root.add_child(player)
	_expect_equal((player.get_node("Cam") as Camera2D).process_callback,
		Camera2D.CAMERA2D_PROCESS_PHYSICS, "player camera rides physics")
	return player


## Committed PNG pixels, bypassing the importer's alpha-border fix.
static func _file_image(hero_id: String) -> Image:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(
		"%s/%s.png" % [WEAPON_DIR, hero_id])
	var image: Image = Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return image


func _matte_clean(image: Image) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a == 0.0 \
					and (pixel.r != 0.0 or pixel.g != 0.0 or pixel.b != 0.0):
				return false
	return true


func _finish() -> void:
	if _failed > 0:
		printerr("painted-weapon test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("painted-weapon test passed — ", _checked, " case(s)")
	quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)
