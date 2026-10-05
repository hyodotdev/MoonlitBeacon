extends Node

## Forecourt party: six heroes really walk the title ground.
##
## Boots the real production entry (original title plus gate) and the
## standalone gate across framings, then watches wall time. Over the
## production forest every actor walks forest-world lanes inside the
## tree-free clearing through the title's center offset, at world
## scale and the night tier; modal content conceals the party and the
## return never teleports. Over the standalone backdrop the formation
## corridors and card/badge/mouth clearance hold. Every actor travels
## its route at its own pace, shows the walk sheet while moving and
## the idle sheet while stopped, faces the direction it really moves,
## plants its feet on measured bounds with its shadow attached, sorts
## by ground position, and never covers the prompt glyphs, the title
## doors, the version tag, the card, the badge, the beacon fire, or
## the gate mouth. Reduced motion freezes every pose; repeated
## chooser use leaves no extra nodes, timers, or game-state changes.
##
## Fails under the old fixed-root idle-only behavior (no travel, no
## walk sheet, no facing changes) and under viewport-corner routes in
## production (feet outside the clearing). Run headless through the
## isolated runner; no window needed.

const ENTRY_SCENE: PackedScene = preload("res://scenes/ui/gate_entry.tscn")
const PRODUCTION_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")
const FRAMINGS: Array[Vector2i] = [
	Vector2i(808, 360), Vector2i(840, 360), Vector2i(808, 606)]
const HERO_IDS: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage"]
## The tree-free clearing from `tools/build_title_forest.py`: center
## (404, 258), radii (196, 90). World feet must read deep inside it,
## past the wobbled edge (edge wobble peaks near 0.175 of radius).
const OPEN_CENTER: Vector2 = Vector2(404.0, 258.0)
const OPEN_RADII: Vector2 = Vector2(196.0, 90.0)
const OPEN_LIMIT: float = 0.80
## The beacon fire column in world pixels: the painted fire opaque
## bounds (x405..427, y250..270) plus the particle flame and smoke
## rising above it. Feet and paint stay out of it.
const FIRE_BOX: Rect2 = Rect2(388, 200, 42, 72)
## Nearest solid forest props to the lanes, live node paths under the
## title's NightForest: the foreground tree, the rim stump and rock,
## and the left-edge tree. Paint never touches them.
const SOLID_PROPS: Array[String] = [
	"NightForest/Trees/T925",
	"NightForest/Details/D025",
	"NightForest/Details/D018",
	"NightForest/Trees/T901",
]
## Minimum honest walking pace, logical pixels per second. The slowest
## route runs at 15, so this is a 1.5x margin, never a fit.
const MIN_PACE: float = 10.0
## Minimum single-actor travel across the observation, logical pixels.
## The shortest lane is 28, so this is a real walk, not jitter.
const MIN_TRAVEL: float = 25.0
const PRODUCTION_SECONDS: float = 10.5
const PRODUCTION_INTERVAL: float = 0.2
const FRAMING_SECONDS: float = 3.0
const FRAMING_INTERVAL: float = 0.3
## Canonical-head boundary per hero, in cell rows: the walk/idle bake
## holds rows [0, neck) pixel-fixed across every frame, so locomotion
## is measured below it, where the legs work. Restates the packer's
## HERO_IDLE_NECK; the head suite guards the fixed band itself.
const HERO_NECK: Dictionary = {
	"warden": 130, "dancer": 130, "keeper": 128,
	"knight": 120, "eclipse": 126, "sage": 118,
}
## Minimum below-neck pixels changing between consecutive walk frames.
## Measured 2339-4210 across the roster; a frozen walk changes none.
const MIN_STEP_MOTION: int = 1000

var _failed: int = 0
var _checked: int = 0
var _vault_taps: int = 0


## Logged-out choice with no providers behind the booted production
## entry. Records guest/provider begins so a stray dispatch fails
## loudly instead of erroring on a missing method.
class StubPartyHost extends Node:
	signal production_changed(state: Dictionary)
	signal production_conflict(local: Dictionary, cloud: Dictionary)
	signal production_error(error: Dictionary)

	var begin_calls: Array = []

	func startup() -> void:
		pass

	func providers_for_entry() -> Array:
		return []

	func identity_for_entry() -> Dictionary:
		return {"stable_id": ""}

	func account_state() -> Dictionary:
		return {"offline": false}

	func saved_gate_summary() -> Dictionary:
		return {"has_save": false}

	func provider_label(provider_id: String) -> String:
		return provider_id

	func begin_provider(provider_id: String) -> Dictionary:
		begin_calls.append({"kind": "provider", "id": provider_id})
		return {}

	func begin_guest(_local_only: bool = false) -> Dictionary:
		begin_calls.append({"kind": "guest"})
		return {}

	func is_login_pending() -> bool:
		return false

	func note_first_paint() -> void:
		pass


func _ready() -> void:
	var original_locale: String = TranslationServer.get_locale()
	var original_size: Vector2i = get_tree().root.size
	TranslationServer.set_locale("en")
	_test_paint_tables()
	await _test_production_walk()
	await _test_world_framings()
	await _test_hide_restore()
	await _test_card_framings()
	await _test_reduced_motion()
	await _test_quiet_close()
	TranslationServer.set_locale(original_locale)
	get_tree().root.size = original_size
	if _failed > 0:
		printerr("forecourt-party test failed — ",
			_failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("forecourt-party test passed — ", _checked, " case(s)")
	get_tree().quit(0)


## The hardcoded paint bounds match the committed sheets, re-measured
## here from the source files: union opaque bounds (alpha >= 32) across
## the four frames of every facing column, idle and walk. The state
## suite pins idle down/left; this pins idle up/right and all four
## walk columns, plus the sheet contract the atlas math stands on.
func _test_paint_tables() -> void:
	for hero_id in HERO_IDS:
		var hero: Hero = load(
			"res://resources/heroes/%s.tres" % hero_id) as Hero
		_expect_true(hero != null, "paint: %s resource loads" % hero_id)
		if hero == null:
			continue
		_expect_true(hero.sprite_cell == Vector2i(144, 192),
			"paint: %s keeps the 144x192 cell" % hero_id)
		_expect_true(hero.idle_frames == 4 and hero.walk_frames == 4,
			"paint: %s carries four idle and four walk frames" % hero_id)
		_expect_true(hero.idle_sheet != null and hero.walk_sheet != null,
			"paint: %s carries both sheets" % hero_id)
		_expect_true(hero.idle_sheet.get_size() == Vector2(576, 768),
			"paint: %s idle sheet is 576x768" % hero_id)
		_expect_true(hero.walk_sheet.get_size() == Vector2(576, 768),
			"paint: %s walk sheet is 576x768" % hero_id)
		var idle: Image = Image.load_from_file(
			"res://assets/custom/actors/heroes/%s/idle.png" % hero_id)
		var walk: Image = Image.load_from_file(
			"res://assets/custom/actors/heroes/%s/walk.png" % hero_id)
		_expect_true(idle != null and walk != null,
			"paint: %s sources load" % hero_id)
		if idle == null or walk == null:
			continue
		_expect_true(_measure_column(idle, 1) \
			== GateHeroForecourt.PAINT_IDLE_UP[hero_id],
			"paint: %s idle up is %s" % [
				hero_id, _measure_column(idle, 1)])
		_expect_true(_measure_column(idle, 3) \
			== GateHeroForecourt.PAINT_IDLE_RIGHT[hero_id],
			"paint: %s idle right is %s" % [
				hero_id, _measure_column(idle, 3)])
		var walk_tables: Array = [
			GateHeroForecourt.PAINT_WALK_DOWN,
			GateHeroForecourt.PAINT_WALK_UP,
			GateHeroForecourt.PAINT_WALK_LEFT,
			GateHeroForecourt.PAINT_WALK_RIGHT]
		for facing in 4:
			var measured: Rect2i = _measure_column(walk, facing)
			_expect_true((walk_tables[facing] as Dictionary)[hero_id] \
				== measured,
				"paint: %s walk column %d is %s" % [
					hero_id, facing, measured])
			# Walk frames must read as locomotion: the body below the
			# canonical head repaints every step, and every foot lands
			# on the same ground line the grounding math plants.
			# Bounds alone cannot see it: the fixed head dominates the
			# extremes while the stride works inside them.
			var neck: int = int(HERO_NECK[hero_id])
			for frame in 4:
				var moved: int = _step_motion(
					walk, facing, frame, (frame + 1) % 4, neck)
				_expect_true(moved >= MIN_STEP_MOTION,
					"paint: %s walk column %d step %d strides (%dpx)" % [
						hero_id, facing, frame, moved])
				_expect_true(
					_measure_frame(walk, facing, frame).end.y == 192,
					"paint: %s walk lands its feet" % hero_id)


func _measure_column(image: Image, column: int) -> Rect2i:
	var lo := Vector2i(144, 192)
	var hi := Vector2i(-1, -1)
	for frame in 4:
		var origin := Vector2i(column * 144, frame * 192)
		for y in 192:
			for x in 144:
				if image.get_pixel(origin.x + x, origin.y + y).a \
						>= 32.0 / 255.0:
					lo.x = mini(lo.x, x)
					lo.y = mini(lo.y, y)
					hi.x = maxi(hi.x, x)
					hi.y = maxi(hi.y, y)
	return Rect2i(lo, hi - lo + Vector2i(1, 1))


func _measure_frame(image: Image, column: int, frame: int) -> Rect2i:
	var lo := Vector2i(144, 192)
	var hi := Vector2i(-1, -1)
	var origin := Vector2i(column * 144, frame * 192)
	for y in 192:
		for x in 144:
			if image.get_pixel(origin.x + x, origin.y + y).a \
					>= 32.0 / 255.0:
				lo.x = mini(lo.x, x)
				lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x)
				hi.y = maxi(hi.y, y)
	return Rect2i(lo, hi - lo + Vector2i(1, 1))


## Pixels repainted below the canonical head between two walk frames
## of one column: the stride's own motion, head excluded.
func _step_motion(
	image: Image, column: int, first: int, second: int, neck: int
) -> int:
	var a := Vector2i(column * 144, first * 192)
	var b := Vector2i(column * 144, second * 192)
	var moved: int = 0
	for y in range(neck, 192):
		for x in 144:
			if image.get_pixel(a.x + x, a.y + y) \
					!= image.get_pixel(b.x + x, b.y + y):
				moved += 1
	return moved


## One long watch of the real title at rest: travel, pace, sheet and
## facing truth, grounding, depth order, scale, clearance, and quiet.
func _test_production_walk() -> void:
	get_tree().root.size = Vector2i(808, 360)
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubPartyHost.new()
	add_child(stub)
	production.set_host_override(stub)
	add_child(production)
	await _frames(4)
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var forecourt: GateHeroForecourt = gate.get_forecourt()
	_expect_true(forecourt.actor_count() == 6,
		"walk: six heroes over the title")
	_expect_true(gate.is_title_rest(),
		"walk: card parked while the party walks")
	_expect_true(forecourt.is_world_mode(),
		"walk: production stages the forest world")
	_expect_true(forecourt.visible,
		"walk: the party shows at title rest")
	_check_opening_stand(forecourt, "walk")
	_vault_taps = 0
	Vault.changed.connect(_on_vault_changed)
	var samples: Array = await _observe(
		forecourt, PRODUCTION_SECONDS, PRODUCTION_INTERVAL)
	_expect_true(samples.size() >= 40,
		"walk: the watch kept its samples (%d)" % samples.size())
	_check_travel(samples, "walk")
	_check_sheet_and_facing(forecourt, samples, "walk")
	_check_grounding(forecourt, samples, "walk")
	_check_depth(samples, forecourt, "walk")
	_check_scale(forecourt, samples, "walk")
	_check_world_grounding(production, samples, "walk")
	_check_title_clear(production, gate, forecourt, samples, "walk")
	_expect_true(stub.begin_calls.is_empty(),
		"walk: the stroll starts no login")
	_expect_true(production.find_children(
		"*", "Player", true, false).is_empty(),
		"walk: no Player behind the stroll")
	_expect_true(gate.find_children(
		"*", "CharacterBody2D", true, false).is_empty(),
		"walk: no physics bodies behind the stroll")
	Vault.changed.disconnect(_on_vault_changed)
	_expect_true(_vault_taps == 0,
		"walk: the stroll changes no game state")
	production.queue_free()
	stub.queue_free()
	await _frames(2)


func _on_vault_changed() -> void:
	_vault_taps += 1


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


## Every actor still stands on its route head when the first paint
## settles: idle sheet, spawn facing, feet planted — through the
## title's center offset in world staging, normalized in formation.
func _check_opening_stand(forecourt: GateHeroForecourt, tag: String) -> void:
	var view: Vector2 = Vector2(get_tree().root.size)
	var world: bool = forecourt.is_world_mode()
	for index in forecourt.actor_count():
		var info: Dictionary = forecourt.actor_info(index)
		_expect_true(bool(info["world"]) == world,
			"%s: hero %d reports its staging" % [tag, index])
		var route: Array = GateHeroForecourt.WORLD_ROUTES[index] \
			if world else GateHeroForecourt.ROUTES[index]
		var head: Vector2 = route[0]
		var expected: Vector2 = head + Screen.center_offset(view) \
			if world else head * view
		var feet: Vector2 = info["feet"]
		_expect_true(absf(feet.x - expected.x) <= 1.0 \
			and absf(feet.y - expected.y) <= 1.0,
			"%s: hero %d stands on its route head" % [tag, index])
		_expect_true(not bool(info["moving"]) \
			and int(info["sheet"]) == GateHeroForecourt.SHEET_IDLE,
			"%s: hero %d opens stopped on idle" % [tag, index])
		_expect_true(int(info["facing"]) \
			== int(GateHeroForecourt.SPAWN_FACING[index]),
			"%s: hero %d opens on its spawn facing" % [tag, index])


## Wall-time watch: one snapshot per interval, each stamped with real
## elapsed milliseconds so pace math never trusts the timer.
func _observe(
	forecourt: GateHeroForecourt, seconds: float, interval: float
) -> Array:
	var samples: Array = []
	var start: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start) / 1000.0 < seconds:
		await get_tree().create_timer(interval).timeout
		samples.append(_snapshot(forecourt))
	return samples


func _snapshot(forecourt: GateHeroForecourt) -> Dictionary:
	var actors: Array = []
	for index in forecourt.actor_count():
		var info: Dictionary = forecourt.actor_info(index)
		var hero: Hero = load(str(info["hero_path"])) as Hero
		var body: Sprite2D = forecourt.get_node(
			"HeroActor%d/Body" % index) as Sprite2D
		var atlas: AtlasTexture = body.texture as AtlasTexture
		var weapon: Sprite2D = forecourt.get_node(
			"HeroActor%d/Weapon" % index) as Sprite2D
		var shadow: Sprite2D = forecourt.get_node(
			"HeroActor%d/Shadow" % index) as Sprite2D
		var root: Node2D = forecourt.get_node(
			"HeroActor%d" % index) as Node2D
		actors.append({
			"feet": info["feet"],
			"facing": int(info["facing"]),
			"sheet": int(info["sheet"]),
			"moving": bool(info["moving"]),
			"world": bool(info["world"]),
			"frame": int(info["frame"]),
			"paint_size": info["paint_size"],
			"paint_rect": info["paint_rect"],
			"walk_atlas": atlas != null and atlas.atlas == hero.walk_sheet,
			"idle_atlas": atlas != null and atlas.atlas == hero.idle_sheet,
			"region": atlas.region if atlas != null else Rect2(),
			"body_pos": body.position,
			"body_scale": body.scale.x,
			"body_mod": body.modulate,
			"weapon_pos": weapon.position,
			"weapon_rot": weapon.rotation,
			"weapon_scale": weapon.scale,
			"shadow_pos": shadow.position,
			"shadow_texture": shadow.texture != null,
			"z": root.z_index,
			"profile": hero.attack_profile,
			"hero_id": WeaponRig.painted_name(hero.attack_profile),
		})
	return {"at": Time.get_ticks_msec(), "actors": actors}


## Every actor walks and stops: meaningful travel per actor at an
## honest pace, measured against real elapsed time. Fixed roots fail
## every line here.
func _check_travel(samples: Array, tag: String) -> void:
	for index in 6:
		var walked: bool = false
		var stopped: bool = false
		var walk_disp: float = 0.0
		var walk_time: float = 0.0
		var far: float = 0.0
		var points: Array = []
		for sample in samples:
			var actor: Dictionary = (sample["actors"] as Array)[index]
			points.append(actor["feet"])
			if bool(actor["moving"]):
				walked = true
			else:
				stopped = true
		for a in points.size():
			for b in range(a + 1, points.size()):
				far = maxf(far,
					((points[a] as Vector2) - (points[b] as Vector2)
						).length())
		for s in range(1, samples.size()):
			var before: Dictionary = (
				samples[s - 1]["actors"] as Array)[index]
			var after: Dictionary = (samples[s]["actors"] as Array)[index]
			if bool(before["moving"]) and bool(after["moving"]):
				walk_disp += ((after["feet"] as Vector2) \
					- (before["feet"] as Vector2)).length()
				walk_time += (float(samples[s]["at"]) \
					- float(samples[s - 1]["at"])) / 1000.0
		_expect_true(walked and stopped,
			"%s: hero %d both walks and stops" % [tag, index])
		_expect_true(far >= MIN_TRAVEL,
			"%s: hero %d travels %dpx" % [tag, index, int(far)])
		_expect_true(walk_time > 1.0,
			"%s: hero %d walks over a second" % [tag, index])
		if walk_time > 0.0:
			_expect_true(walk_disp / walk_time >= MIN_PACE,
				"%s: hero %d paces %dpx/s" % [
					tag, index, int(walk_disp / walk_time)])


## The shown sheet always matches the motion: walk atlas while moving,
## idle atlas while stopped, faced column at the real cell, facing
## equal to the Player rule on the real travel. Every actor turns at
## least once and the party covers all four facings.
func _check_sheet_and_facing(
	forecourt: GateHeroForecourt, samples: Array, tag: String
) -> void:
	var party_facings: Dictionary = {}
	for index in forecourt.actor_count():
		var hero: Hero = load(str(
			forecourt.actor_info(index)["hero_path"])) as Hero
		var seen: Dictionary = {}
		var previous: Dictionary = {}
		for sample in samples:
			var actor: Dictionary = (sample["actors"] as Array)[index]
			seen[int(actor["facing"])] = true
			party_facings[int(actor["facing"])] = true
			var region: Rect2 = actor["region"]
			_expect_true(region.size == Vector2(hero.sprite_cell),
				"%s: hero %d keeps the 144x192 cell" % [tag, index])
			_expect_true(int(region.position.x) \
				== int(actor["facing"]) * hero.sprite_cell.x,
				"%s: hero %d frames the faced column" % [tag, index])
			_expect_true(int(region.position.y) \
				== int(actor["frame"]) * hero.sprite_cell.y,
				"%s: hero %d frames its row" % [tag, index])
			if bool(actor["moving"]):
				_expect_true(bool(actor["walk_atlas"]),
					"%s: hero %d walks its walk sheet" % [tag, index])
				var sheet := Rect2(
					Vector2.ZERO, hero.walk_sheet.get_size())
				_expect_true(sheet.encloses(region),
					"%s: hero %d region sits inside" % [tag, index])
			else:
				_expect_true(bool(actor["idle_atlas"]),
					"%s: hero %d rests its idle sheet" % [tag, index])
				var sheet := Rect2(
					Vector2.ZERO, hero.idle_sheet.get_size())
				_expect_true(sheet.encloses(region),
					"%s: hero %d region sits inside" % [tag, index])
			if not previous.is_empty() and bool(previous["moving"]) \
					and bool(actor["moving"]):
				var step: Vector2 = (actor["feet"] as Vector2) \
					- (previous["feet"] as Vector2)
				if step.length() > 1.0:
					_expect_true(int(actor["facing"]) \
						== _rule_facing(step),
						"%s: hero %d faces its travel" % [tag, index])
			previous = actor
		_expect_true(seen.size() >= 2,
			"%s: hero %d turns, not a screensaver" % [tag, index])
	_expect_true(party_facings.size() == 4,
		"%s: the party covers all four facings" % tag)


## The Player dominant-axis rule, restated literally: the dominant
## axis wins, ties read vertical.
func _rule_facing(travel: Vector2) -> int:
	if absf(travel.x) > absf(travel.y):
		return GateHeroForecourt.FACING_RIGHT if travel.x > 0.0 \
			else GateHeroForecourt.FACING_LEFT
	return GateHeroForecourt.FACING_DOWN if travel.y > 0.0 \
		else GateHeroForecourt.FACING_UP


## Grounding: stopped feet and bodies hold pixel-fixed (no bob), the
## body anchors on the measured paint center and feet line, the shadow
## stays attached at the feet, and the held weapon never drifts or
## flips on its own inside a pose.
func _check_grounding(
	forecourt: GateHeroForecourt, samples: Array, tag: String
) -> void:
	for index in forecourt.actor_count():
		var previous: Dictionary = {}
		for sample in samples:
			var actor: Dictionary = (sample["actors"] as Array)[index]
			_expect_true(bool(actor["shadow_texture"]),
				"%s: hero %d keeps its shadow" % [tag, index])
			var unit: float = float(actor["body_scale"])
			var bounds: Rect2i = _pose_bounds(
				str(actor["hero_id"]), int(actor["sheet"]),
				int(actor["facing"]))
			var anchor := Vector2(
				(float(bounds.get_center().x) - 72.0) * unit,
				(float(bounds.end.y) - 96.0) * unit)
			var body_pos: Vector2 = actor["body_pos"]
			_expect_true(absf(body_pos.x + anchor.x) <= 0.01 \
				and absf(body_pos.y + anchor.y) <= 0.01,
				"%s: hero %d anchors on its paint" % [tag, index])
			var shadow_pos: Vector2 = actor["shadow_pos"]
			_expect_true(absf(shadow_pos.x - anchor.x) <= 0.01 \
				and shadow_pos.y == 3.0,
				"%s: hero %d shadow stays at its feet" % [tag, index])
			if previous.is_empty():
				previous = actor
				continue
			if not bool(previous["moving"]) \
					and not bool(actor["moving"]):
				_expect_true((actor["feet"] as Vector2) \
					== (previous["feet"] as Vector2),
					"%s: hero %d stopped feet stay fixed" % [tag, index])
				_expect_true((actor["body_pos"] as Vector2) \
					== (previous["body_pos"] as Vector2),
					"%s: hero %d stands with no bob" % [tag, index])
			if int(previous["facing"]) == int(actor["facing"]) \
					and int(previous["sheet"]) == int(actor["sheet"]):
				_expect_true((actor["weapon_pos"] as Vector2) \
					== (previous["weapon_pos"] as Vector2) \
					and float(actor["weapon_rot"]) \
						== float(previous["weapon_rot"]) \
					and (actor["weapon_scale"] as Vector2) \
						== (previous["weapon_scale"] as Vector2),
					"%s: hero %d weapon never drifts" % [tag, index])
			previous = actor
		var last: Dictionary = (
			samples[samples.size() - 1]["actors"] as Array)[index]
		var mirror: float = -1.0 \
			if int(last["facing"]) == GateHeroForecourt.FACING_LEFT \
			else 1.0
		_expect_true(signf((last["weapon_scale"] as Vector2).x) \
			== mirror,
			"%s: hero %d weapon mirrors its facing" % [tag, index])
		var rest: float = GateHeroForecourt.BLADE_REST_ANGLE \
			if HeroWeapons.primary_side(
				int(last["profile"])) == HeroWeapons.Side.MELEE \
			else GateHeroForecourt.GUN_REST_ANGLE
		_expect_true(absf(float(last["weapon_rot"]) - rest * mirror) \
			<= 0.001,
			"%s: hero %d weapon keeps its rest angle" % [tag, index])


## The pinned paint table for one pose, the same lookup the forecourt
## grounds itself on.
## Expected grounding bounds: the idle|walk union per facing,
## recomputed from the tables. Stops and same-facing departures share
## one bounds, so the actor never rescales or lifts mid-transition.
func _pose_bounds(hero_id: String, _sheet: int, facing: int) -> Rect2i:
	var idle_table: Dictionary = GateHeroForecourt.PAINT_DOWN
	var walk_table: Dictionary = GateHeroForecourt.PAINT_WALK_DOWN
	match facing:
		GateHeroForecourt.FACING_UP:
			idle_table = GateHeroForecourt.PAINT_IDLE_UP
			walk_table = GateHeroForecourt.PAINT_WALK_UP
		GateHeroForecourt.FACING_LEFT:
			idle_table = GateHeroForecourt.PAINT_LEFT
			walk_table = GateHeroForecourt.PAINT_WALK_LEFT
		GateHeroForecourt.FACING_RIGHT:
			idle_table = GateHeroForecourt.PAINT_IDLE_RIGHT
			walk_table = GateHeroForecourt.PAINT_WALK_RIGHT
	var merged := Rect2(idle_table[hero_id] as Rect2i).merge(
		Rect2(walk_table[hero_id] as Rect2i))
	# Both sheets ground on the union: the sheet selects the texture
	# column elsewhere, never the bounds.
	return Rect2i(Vector2i(merged.position), Vector2i(merged.size))


## Nearer feet draw over farther ones: the sort key is the ground
## position itself.
func _check_depth(
	samples: Array, forecourt: GateHeroForecourt, tag: String
) -> void:
	for sample in samples:
		var actors: Array = sample["actors"]
		for index in forecourt.actor_count():
			var actor: Dictionary = actors[index]
			_expect_true(int(actor["z"]) \
				== int((actor["feet"] as Vector2).y),
				"%s: hero %d sorts by its ground" % [tag, index])
		var order: Array = []
		for index in forecourt.actor_count():
			order.append(index)
		for a in order.size():
			for b in range(a + 1, order.size()):
				var ya: float = ((actors[order[a]] as Dictionary)["feet"] \
					as Vector2).y
				var yb: float = ((actors[order[b]] as Dictionary)["feet"] \
					as Vector2).y
				if ya > yb:
					var swap: int = order[a]
					order[a] = order[b]
					order[b] = swap
		for s in range(1, order.size()):
			var low: int = int((actors[order[s - 1]] as Dictionary)["z"])
			var high: int = int((actors[order[s]] as Dictionary)["z"])
			_expect_true(low <= high,
				"%s: nearer feet draw over farther" % tag)


## Game-coherent scale per staging: 24-34 world pixels over the
## forest, the formation's own row bands over the standalone art.
func _check_scale(
	forecourt: GateHeroForecourt, samples: Array, tag: String
) -> void:
	var world: bool = forecourt.is_world_mode()
	for sample in samples:
		var actors: Array = sample["actors"]
		for index in actors.size():
			var paint: Vector2 = (actors[index] as Dictionary)[
				"paint_size"]
			var low: float = GateHeroForecourt.WORLD_PAINT_MIN
			var high: float = GateHeroForecourt.WORLD_PAINT_MAX
			if not world:
				var back_row: bool = index < 3
				low = GateHeroForecourt.BACK_PAINT_MIN \
					if back_row else GateHeroForecourt.FRONT_PAINT_MIN
				high = GateHeroForecourt.BACK_PAINT_MAX \
					if back_row else GateHeroForecourt.FRONT_PAINT_MAX
			_expect_true(paint.y >= low and paint.y <= high,
				"%s: hero %d paint height %d in %d-%d" % [
					tag, index, int(paint.y), int(low), int(high)])


## Actual ground placement in world staging: feet map into the
## tree-free clearing through the title's center offset, clear of the
## beacon fire column; paint clears the fire and the nearest solid
## props read back from the live forest; bodies wear their ground
## row's night tier, never near-white cutouts.
func _check_world_grounding(
	production: ProductionEntry, samples: Array, tag: String
) -> void:
	var view: Vector2 = Vector2(get_tree().root.size)
	var offset: Vector2 = Screen.center_offset(view)
	var title: Variant = production.get_node("Title")
	var solids: Array[Rect2] = []
	for path in SOLID_PROPS:
		var prop: Node2D = title.get_node_or_null(path) as Node2D
		_expect_true(prop != null,
			"%s: solid prop %s stands" % [tag, path])
		if prop == null:
			continue
		var sprite: Sprite2D = prop as Sprite2D
		var region: Rect2 = sprite.region_rect \
			if sprite.region_enabled else Rect2(
				Vector2.ZERO, sprite.texture.get_size())
		var top_left: Vector2 = prop.position
		if sprite.centered:
			top_left -= region.size * sprite.scale * 0.5
		var world_rect := Rect2(
			top_left, region.size * sprite.scale)
		solids.append(Rect2(
			world_rect.position + offset, world_rect.size))
	var fire := Rect2(
		FIRE_BOX.position + offset, FIRE_BOX.size)
	for sample in samples:
		var actors: Array = sample["actors"]
		for index in actors.size():
			var actor: Dictionary = actors[index]
			_expect_true(bool(actor["world"]),
				"%s: hero %d walks the world" % [tag, index])
			var ground: Vector2 = \
				(actor["feet"] as Vector2) - offset
			var r: float = Vector2(
				(ground.x - OPEN_CENTER.x) / OPEN_RADII.x,
				(ground.y - OPEN_CENTER.y) / OPEN_RADII.y).length()
			_expect_true(r <= OPEN_LIMIT,
				"%s: hero %d feet read ground %.2f" % [tag, index, r])
			_expect_true(not FIRE_BOX.has_point(ground),
				"%s: hero %d feet clear the fire" % [tag, index])
			var rect: Rect2 = actor["paint_rect"]
			_expect_true(
				not rect.grow(-1.0).intersects(fire.grow(-1.0)),
				"%s: hero %d paint clears the fire" % [tag, index])
			for zone in solids:
				_expect_true(
					not rect.grow(-1.0).intersects(zone.grow(-1.0)),
					"%s: hero %d paint clears %s" % [tag, index, zone])
			_expect_true((actor["body_mod"] as Color).is_equal_approx(
				_tier_expect(ground.y)),
				"%s: hero %d wears its night tier" % [tag, index])


## The forest's depth tier restated from `build_title_forest.py`:
## tier_of(world_y), the same curve the trees wear.
func _tier_expect(world_y: float) -> Color:
	var t: float = clampf(
		(world_y + 130.0) / 490.0, 0.0, 1.0)
	var b: float = 0.42 + 0.58 * pow(t, 0.85)
	b = round(b * 20.0) / 20.0
	var f: float = 1.0 - t
	return Color(
		minf(b * (1.0 - 0.10 * f), 1.0),
		minf(b * (1.0 - 0.05 * f), 1.0),
		minf(b * (1.0 + 0.06 * f), 1.0))


## Title clearance at every sampled pose: inside the viewport, clear
## of the live prompt glyphs, the version tag, and the visible doors.
func _check_title_clear(
	production: ProductionEntry, gate: GateEntry,
	forecourt: GateHeroForecourt, samples: Array, tag: String
) -> void:
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	var title: Variant = production.get_node("Title")
	var prompt: Label = title.get_node("Ui/Screen/TapPrompt") as Label
	var font: Font = prompt.get_theme_font("font")
	var ink: float = font.get_string_size(tr(prompt.text),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		float(prompt.get_theme_font_size("font_size"))).x
	var prompt_rect: Rect2 = prompt.get_global_rect()
	var clear: Array[Rect2] = [Rect2(
		prompt_rect.get_center().x - ink * 0.5,
		prompt_rect.position.y, ink, prompt_rect.size.y),
		(title.get_node("Ui/Screen/Version") as Control).get_global_rect()]
	for door_name in ["SettingsButton", "ShrineButton", "LadderButton",
			"ChronicleButton", "StoreButton"]:
		var door: Button = title.get_node(
			"Ui/Screen/" + door_name) as Button
		if door.is_visible_in_tree():
			clear.append(door.get_global_rect())
	for sample in samples:
		var actors: Array = sample["actors"]
		for index in forecourt.actor_count():
			var rect: Rect2 = (actors[index] as Dictionary)["paint_rect"]
			_expect_true(viewport.encloses(rect.grow(-0.5)),
				"%s: hero %d inside %s" % [tag, index, rect])
			for zone in clear:
				_expect_true(
					not rect.grow(-1.0).intersects(zone.grow(-1.0)),
					"%s: hero %d clears %s" % [tag, index, zone])


## World staging at the wide and 4:3 framings: the clearing mapping
## rides the center offset, so feet stay on open ground, clear of the
## fire, the solid props and the title chrome, at world scale.
func _test_world_framings() -> void:
	for framing in [Vector2i(840, 360), Vector2i(808, 606)]:
		var tag: String = "world/%dx%d" % [framing.x, framing.y]
		get_tree().root.size = framing
		var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
			as ProductionEntry
		var stub := StubPartyHost.new()
		add_child(stub)
		production.set_host_override(stub)
		add_child(production)
		await _frames(4)
		var forecourt: GateHeroForecourt = (
			production.get_node("Gate") as GateEntry).get_forecourt()
		_expect_true(forecourt.is_world_mode(),
			"%s: production stages the forest world" % tag)
		_expect_true(forecourt.visible,
			"%s: the party shows at title rest" % tag)
		_check_opening_stand(forecourt, tag)
		var samples: Array = await _observe(
			forecourt, FRAMING_SECONDS, FRAMING_INTERVAL)
		_check_scale(forecourt, samples, tag)
		_check_world_grounding(production, samples, tag)
		_check_title_clear(production,
			production.get_node("Gate") as GateEntry,
			forecourt, samples, tag)
		production.queue_free()
		stub.queue_free()
		await _frames(2)


## Modal concealment over the clearing: the login selection and a
## title modal quietly hide the decorative party while the patrol
## keeps simulating; back at Tap the party returns on its routes,
## never teleported through the trees, with no nodes grown.
func _test_hide_restore() -> void:
	get_tree().root.size = Vector2i(808, 360)
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubPartyHost.new()
	add_child(stub)
	production.set_host_override(stub)
	add_child(production)
	await _frames(4)
	var title: Variant = production.get_node("Title")
	var gate: GateEntry = production.get_node("Gate") as GateEntry
	var forecourt: GateHeroForecourt = gate.get_forecourt()
	_expect_true(forecourt.visible,
		"hide: the party shows at title rest")
	_expect_true(_count_descendants(forecourt) == 24,
		"hide: six roots with three sprites each")
	await get_tree().create_timer(2.0).timeout
	var before: Dictionary = _snapshot(forecourt)
	var hidden_at: int = Time.get_ticks_msec()
	title.request_start()
	await _frames(4)
	_expect_true(gate.is_selection_open(),
		"hide: tap opens the selection")
	_expect_true(not forecourt.visible,
		"hide: the selection conceals the party")
	_expect_true(forecourt.actor_count() == 6,
		"hide: concealment keeps all six actors")
	await get_tree().create_timer(1.5).timeout
	var gate_back: Button = gate.get_node(
		"Content/StatusCard/LoggedOut/Footer/Back") as Button
	(gate_back as Button).pressed.emit()
	await _frames(4)
	_expect_true(not gate.is_selection_open(),
		"hide: back parks the selection")
	_expect_true(forecourt.visible,
		"hide: Tap restores the party")
	var restored: Dictionary = _snapshot(forecourt)
	var elapsed: float = float(
		Time.get_ticks_msec() - hidden_at) / 1000.0
	for index in forecourt.actor_count():
		var was: Vector2 = (
			before["actors"] as Array)[index]["feet"]
		var now: Vector2 = (
			restored["actors"] as Array)[index]["feet"]
		var speed: float = float(
			GateHeroForecourt.SPEEDS[index])
		_expect_true((now - was).length() \
			<= speed * elapsed + 2.0,
			"hide: hero %d returns without teleport" % index)
		_expect_true(_on_world_lane(index, now),
			"hide: hero %d returns on its lane" % index)
	_expect_true(_count_descendants(forecourt) == 24,
		"hide: no extra nodes after the cycle")
	var settings: Button = title.get_node(
		"Ui/Screen/SettingsButton") as Button
	(settings as Button).pressed.emit()
	await _frames(4)
	_expect_true(not forecourt.visible,
		"hide: a title modal conceals the party")
	var settings_close: Button = title.get_node(
		"Ui/Settings/Close") as Button
	(settings_close as Button).pressed.emit()
	await _frames(4)
	_expect_true(forecourt.visible,
		"hide: closing the modal restores the party")
	production.queue_free()
	stub.queue_free()
	await _frames(2)


## True while screen feet sit on one of the actor's world lanes
## through the current center offset, within a pixel.
func _on_world_lane(index: int, screen_feet: Vector2) -> bool:
	var view: Vector2 = Vector2(get_tree().root.size)
	var ground: Vector2 = screen_feet - Screen.center_offset(view)
	var route: Array = GateHeroForecourt.WORLD_ROUTES[index]
	for leg in route.size():
		var a: Vector2 = route[leg]
		var b: Vector2 = route[(leg + 1) % route.size()]
		var along: Vector2 = b - a
		var span: float = along.length()
		if span < 0.001:
			continue
		var t: float = clampf(
			(ground - a).dot(along) / (span * span), 0.0, 1.0)
		if (a + along * t - ground).length() <= 1.0:
			return true
	return false


## The walking party under the gate card itself, every framing: inside
## the viewport, clear of the card, the badge and the gate mouth while
## the identity card stands, the selection stands, and the card parks.
func _test_card_framings() -> void:
	for framing in FRAMINGS:
		var tag: String = "card/%dx%d" % [framing.x, framing.y]
		get_tree().root.size = framing
		var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
		add_child(entry)
		await _frames(4)
		var forecourt: GateHeroForecourt = entry.get_forecourt()
		_expect_true(forecourt.actor_count() == 6,
			"%s: six heroes walk" % tag)
		_expect_true(not forecourt.is_world_mode(),
			"%s: standalone keeps its formation" % tag)
		entry.set_providers([
			{"id": "google", "label": "Google", "ready": true},
			{"id": "apple", "label": "Apple", "ready": true},
		])
		entry.show_identity(
			{"stable_id": "TEST-PARTY-ID",
				"hero": load("res://resources/heroes/knight.tres")},
			{"has_save": true, "title": "TEST Gate 1", "detail": ""})
		await _frames(2)
		var samples: Array = await _observe(
			forecourt, FRAMING_SECONDS, FRAMING_INTERVAL)
		_check_scale(forecourt, samples, tag + "/ready")
		_check_gate_clear(entry, forecourt, samples, tag + "/ready")
		entry.show_logged_out()
		await _frames(2)
		var picking: Array = await _observe(
			forecourt, FRAMING_INTERVAL * 2.0, FRAMING_INTERVAL)
		_check_gate_clear(entry, forecourt, picking, tag + "/picking")
		entry.show_title_rest()
		await _frames(2)
		var parked: Array = await _observe(
			forecourt, FRAMING_INTERVAL * 2.0, FRAMING_INTERVAL)
		_check_gate_clear(entry, forecourt, parked, tag + "/parked")
		entry.queue_free()
		await _frames(2)


## Gate clearance at every sampled pose: inside the viewport, clear of
## the visible card, the badge and the gate mouth.
func _check_gate_clear(
	entry: GateEntry, forecourt: GateHeroForecourt,
	samples: Array, tag: String
) -> void:
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	var clear: Array[Rect2] = [
		(entry.get_node("Content/OfflineBadge") as Control
			).get_global_rect(),
		forecourt.gate_mouth_rect(),
	]
	if (entry.get_node("Content/StatusCard") as Control
			).is_visible_in_tree():
		clear.append((entry.get_node("Content/StatusCard") as Control
			).get_global_rect())
	for sample in samples:
		var actors: Array = sample["actors"]
		for index in forecourt.actor_count():
			var rect: Rect2 = (actors[index] as Dictionary)["paint_rect"]
			_expect_true(viewport.encloses(rect.grow(-0.5)),
				"%s: hero %d inside %s" % [tag, index, rect])
			for zone in clear:
				_expect_true(
					not rect.grow(-1.0).intersects(zone.grow(-1.0)),
					"%s: hero %d clears %s" % [tag, index, zone])


## Reduced motion freezes the walk mid-pose: feet, facing, sheet,
## frame and body hold across time, the lineup stays complete, and
## re-enabling resumes the walk.
func _test_reduced_motion() -> void:
	get_tree().root.size = Vector2i(808, 360)
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	await _frames(4)
	var forecourt: GateHeroForecourt = entry.get_forecourt()
	_expect_true(forecourt.is_motion_active(),
		"calm: the patrol runs by default")
	await get_tree().create_timer(2.5).timeout
	entry.set_reduced_motion(true)
	await _frames(2)
	_expect_true(not forecourt.is_motion_active(),
		"calm: reduced motion stops the patrol")
	_expect_true(not entry.is_motion_active(),
		"calm: the entry reports the frozen party")
	var frozen: Dictionary = _snapshot(forecourt)
	for _tick in 5:
		await get_tree().create_timer(0.2).timeout
		var held: Dictionary = _snapshot(forecourt)
		for index in forecourt.actor_count():
			var was: Dictionary = (frozen["actors"] as Array)[index]
			var now: Dictionary = (held["actors"] as Array)[index]
			_expect_true((now["feet"] as Vector2) \
				== (was["feet"] as Vector2),
				"calm: hero %d feet hold still" % index)
			_expect_true(int(now["frame"]) == int(was["frame"]) \
				and int(now["facing"]) == int(was["facing"]) \
				and int(now["sheet"]) == int(was["sheet"]),
				"calm: hero %d pose holds still" % index)
			_expect_true((now["body_pos"] as Vector2) \
				== (was["body_pos"] as Vector2),
				"calm: hero %d body holds still" % index)
	_expect_true(forecourt.actor_count() == 6,
		"calm: the frozen party stays complete")
	entry.set_reduced_motion(false)
	await _frames(2)
	_expect_true(forecourt.is_motion_active(),
		"calm: the patrol resumes when re-enabled")
	await get_tree().create_timer(1.0).timeout
	var later: Dictionary = _snapshot(forecourt)
	var changed: bool = false
	for index in forecourt.actor_count():
		var was: Dictionary = (frozen["actors"] as Array)[index]
		var now: Dictionary = (later["actors"] as Array)[index]
		if (now["feet"] as Vector2) != (was["feet"] as Vector2) \
				or int(now["frame"]) != int(was["frame"]):
			changed = true
	_expect_true(changed, "calm: the walk moves again after resume")
	entry.queue_free()
	await _frames(2)


## Repeated title and chooser use grows nothing: six roots with their
## three sprites each, no timers, no extra controls, no actor change.
func _test_quiet_close() -> void:
	get_tree().root.size = Vector2i(808, 360)
	var entry: GateEntry = ENTRY_SCENE.instantiate() as GateEntry
	add_child(entry)
	await _frames(4)
	var forecourt: GateHeroForecourt = entry.get_forecourt()
	_expect_true(_count_descendants(forecourt) == 24,
		"quiet: six roots with three sprites each")
	_expect_true(forecourt.find_children(
		"*", "Timer", true, false).is_empty(),
		"quiet: the party owns no timers")
	for _cycle in 3:
		entry.show_logged_out()
		await _frames(2)
		entry.open_terms()
		await _frames(2)
		entry.close_panels()
		entry.show_title_rest()
		await _frames(2)
		_expect_true(forecourt.actor_count() == 6,
			"quiet: six heroes after the cycle")
		_expect_true(_count_descendants(forecourt) == 24,
			"quiet: no extra nodes after the cycle")
		_expect_true(forecourt.find_children(
			"*", "Timer", true, false).is_empty(),
			"quiet: no timers after the cycle")
	entry.queue_free()
	await _frames(2)


func _count_descendants(node: Node) -> int:
	var count: int = 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var next: Node = stack.pop_back()
		for child in next.get_children():
			count += 1
			stack.append(child)
	return count


func _expect_true(value: bool, message: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("  FAIL ", message)