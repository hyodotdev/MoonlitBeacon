class_name GateHeroForecourt
extends Control

## Six painted heroes walking the gate forecourt, as decoration.
##
## Lightweight presentation actors only: one body sprite showing real
## walk frames from the hero's own walk sheet while moving and real
## idle frames from the idle sheet while stopped, one sprite showing
## the hero's real painted weapon sheet, and a soft contact shadow
## each. No Arena, no Player, no physics, no ownership reads: locked
## heroes appear here as marketing presentation, never as an unlock or
## ownership change, so this module never touches the Vault.
##
## Two stagings, one patrol engine. Over the production forest the
## party walks the real clearing in world coordinates through the same
## center offset the title places its diorama with: small bodies
## 24-34 logical pixels tall, tinted by the forest's own depth tier,
## feet on open ground around the beacon. Over the standalone painted
## backdrop it keeps the side-corridor formation instead. Feet plant
## on measured opaque bounds rather than the mostly transparent
## 144x192 atlas cells. Each actor patrols its own route at its own
## pace with its own stops, faces the direction it really moves (the
## Player dominant-axis rule), and sorts by ground position so nearer
## feet draw over farther ones. The layer sits behind the interaction
## layer and never takes input. The host may conceal the party while
## modal content covers the clearing; the patrol keeps simulating
## underneath, so the return never teleports. Reduced motion freezes
## every actor mid-pose; there are no tweens or timers here, so
## nothing lingers after close.

## Display order: back row first so the front row draws over it.
const HERO_PATHS: Array[String] = [
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/sage.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/warden.tres",
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/eclipse.tres",
]
## Sheet columns, shared with the Player: down, up, left, right.
const FACING_DOWN: int = 0
const FACING_UP: int = 1
const FACING_LEFT: int = 2
const FACING_RIGHT: int = 3
## Body sheet in use: the idle sheet while stopped, the walk sheet
## while moving.
const SHEET_IDLE: int = 0
const SHEET_WALK: int = 1
## Normalized feet waypoints per actor for the standalone painted
## backdrop, looped in order (two points read as a back-and-forth
## patrol). Both corridors hug the sides of the ground: clear of the
## centered card, the badge and the gate mouth, inside every framing.
const ROUTES: Array = [
	[Vector2(0.080, 0.800), Vector2(0.170, 0.800)],
	[Vector2(0.130, 0.775), Vector2(0.130, 0.865)],
	[Vector2(0.830, 0.795), Vector2(0.920, 0.795)],
	[Vector2(0.070, 0.850), Vector2(0.150, 0.775),
		Vector2(0.200, 0.865)],
	[Vector2(0.870, 0.775), Vector2(0.870, 0.865)],
	[Vector2(0.800, 0.865), Vector2(0.850, 0.775),
		Vector2(0.930, 0.860)],
]
## Feet waypoints in forest-world pixels for the production title,
## looped in order. Six short lanes inside the tree-free clearing,
## three a side, flanking the beacon fire: verticals at x312/x338 and
## x470/x496, horizontals at y284. No lane crosses another, the fire
## column, the painted campsite solids, or the foreground tree tops;
## feet stay on open ground and below the tap prompt glyphs.
const WORLD_ROUTES: Array = [
	[Vector2(312, 246), Vector2(312, 274)],
	[Vector2(338, 250), Vector2(338, 278)],
	[Vector2(496, 246), Vector2(496, 274)],
	[Vector2(310, 284), Vector2(365, 284)],
	[Vector2(450, 284), Vector2(528, 284)],
	[Vector2(470, 250), Vector2(470, 278)],
]
## Ground speed per actor, logical pixels per second. Calm but
## unmistakable: the slowest still covers 30px in two seconds.
const SPEEDS: Array[float] = [15.0, 16.5, 18.0, 19.5, 21.0, 22.5]
## Walk stride: one full four-frame cycle per half body height of
## measured travel, so the cadence follows the feet instead of a clock.
## At the patrol speeds above and the 25-48px walk paint below, the
## party turns 0.8-1.5 cycles a second at base framings; the tablet
## presence boost lengthens the stride with the body, never past a
## calm amble. Combat and the Player keep their own Hero.walk_fps pace.
const WALK_CYCLE_HEIGHTS: float = 0.5
## Paint-height target per actor, in logical pixels at the base 360p
## framing: back row small, front row near, all near the in-game body.
const TARGETS: Array[float] = [34.0, 33.0, 35.0, 47.0, 48.0, 46.0]
## Paint-height target per actor over the real forest, in world
## pixels: near the in-game body against trees and beacon.
const WORLD_TARGETS: Array[float] = [26.0, 25.0, 27.0, 31.0, 32.0, 30.0]
## Visible-paint height band over the real forest, in world pixels.
const WORLD_PAINT_MIN: float = 24.0
const WORLD_PAINT_MAX: float = 34.0
## The forest's aerial-perspective tier, restated from
## `tools/build_title_forest.py`: far ground is darker and bluer.
## World-staged actors wear their feet row's tier like every tree.
const TIER_FAR: float = -130.0
const TIER_NEAR: float = 360.0
const TIER_MIN: float = 0.42
const TIER_STEPS: float = 20.0
## Facing held through the opening stop, viewer or gate side only.
const SPAWN_FACING: Array[int] = [
	FACING_LEFT, FACING_DOWN, FACING_LEFT,
	FACING_DOWN, FACING_DOWN, FACING_DOWN,
]
## Visible-paint height bands the formation keeps, in logical pixels.
const FRONT_PAINT_MIN: float = 42.0
const FRONT_PAINT_MAX: float = 54.0
const BACK_PAINT_MIN: float = 30.0
const BACK_PAINT_MAX: float = 40.0
## Tablets gain a little presence, capped so the front row never passes
## its band: 48 x 1.10 = 52.8 still fits under the 54 ceiling.
const TABLET_BOOST_MAX: float = 1.10
## Opening stop per actor, seconds: the first walk steps off
## promptly while the departures stay staggered.
const FIRST_DWELL_BASE: float = 0.8
const FIRST_DWELL_STEP: float = 0.3
## Union opaque bounds (alpha >= 32) across the four frames of one
## facing column, in cell-local sheet pixels. Measured from the
## committed sheets; the state suite re-measures the idle down/left
## tables and the party suite re-measures the rest.
const PAINT_DOWN: Dictionary = {
	"warden": Rect2i(32, 82, 80, 110),
	"dancer": Rect2i(34, 82, 75, 110),
	"keeper": Rect2i(33, 82, 78, 110),
	"knight": Rect2i(44, 82, 57, 110),
	"eclipse": Rect2i(31, 82, 82, 110),
	"sage": Rect2i(39, 82, 65, 110),
}
const PAINT_LEFT: Dictionary = {
	"warden": Rect2i(34, 82, 77, 110),
	"dancer": Rect2i(32, 82, 80, 110),
	"keeper": Rect2i(37, 82, 70, 110),
	"knight": Rect2i(36, 82, 71, 110),
	"eclipse": Rect2i(32, 82, 79, 110),
	"sage": Rect2i(37, 82, 69, 110),
}
const PAINT_IDLE_UP: Dictionary = {
	"warden": Rect2i(30, 82, 84, 110),
	"dancer": Rect2i(29, 82, 84, 110),
	"keeper": Rect2i(34, 82, 76, 110),
	"knight": Rect2i(38, 82, 67, 110),
	"eclipse": Rect2i(29, 82, 86, 110),
	"sage": Rect2i(37, 82, 69, 110),
}
const PAINT_IDLE_RIGHT: Dictionary = {
	"warden": Rect2i(31, 81, 82, 111),
	"dancer": Rect2i(32, 82, 79, 110),
	"keeper": Rect2i(36, 82, 72, 110),
	"knight": Rect2i(37, 82, 70, 110),
	"eclipse": Rect2i(32, 82, 80, 110),
	"sage": Rect2i(38, 82, 68, 110),
}
const PAINT_WALK_DOWN: Dictionary = {
	"warden": Rect2i(32, 83, 80, 109),
	"dancer": Rect2i(33, 84, 77, 108),
	"keeper": Rect2i(33, 84, 78, 108),
	"knight": Rect2i(44, 84, 56, 108),
	"eclipse": Rect2i(30, 84, 83, 108),
	"sage": Rect2i(40, 84, 63, 108),
}
const PAINT_WALK_UP: Dictionary = {
	"warden": Rect2i(30, 84, 83, 108),
	"dancer": Rect2i(30, 83, 84, 109),
	"keeper": Rect2i(35, 84, 74, 108),
	"knight": Rect2i(39, 84, 65, 108),
	"eclipse": Rect2i(30, 84, 84, 108),
	"sage": Rect2i(38, 83, 67, 109),
}
const PAINT_WALK_LEFT: Dictionary = {
	"warden": Rect2i(41, 84, 81, 108),
	"dancer": Rect2i(34, 84, 79, 108),
	"keeper": Rect2i(29, 84, 81, 108),
	"knight": Rect2i(38, 84, 86, 108),
	"eclipse": Rect2i(38, 84, 90, 108),
	"sage": Rect2i(36, 84, 73, 108),
}
const PAINT_WALK_RIGHT: Dictionary = {
	"warden": Rect2i(22, 84, 81, 108),
	"dancer": Rect2i(31, 84, 79, 108),
	"keeper": Rect2i(34, 84, 81, 108),
	"knight": Rect2i(20, 84, 86, 108),
	"eclipse": Rect2i(16, 84, 90, 108),
	"sage": Rect2i(35, 84, 73, 108),
}
## The gate mouth in painting pixels, read off the committed master: the
## portal glow the party must never cover. Mapped through the same
## aspect-cover framing the art rect uses, so every viewport agrees.
const GATE_PAINT_SIZE: Vector2 = Vector2(1672.0, 941.0)
const PORTAL_PAINT: Rect2 = Rect2(1140.0, 220.0, 310.0, 280.0)
## Melee blades rest tipped up, guns rest near level.
const BLADE_REST_ANGLE: float = -0.6
const GUN_REST_ANGLE: float = -0.12
## Held-weapon seat as fractions of the paint size, so the hold stays
## correct at any scale: a fifth of the width out, just under half
## the height up from the feet.
const WEAPON_SIDE_FRACTION: float = 0.20
const WEAPON_LIFT_FRACTION: float = 0.45

var _reduced_motion: bool = false
var _world_mode: bool = false
var _actors: Array = []
var _shadow_texture: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow_texture = GateEntryStyle.radial_glow(
		64, Color(0.0, 0.0, 0.0, 0.55), Color(0.0, 0.0, 0.0, 0.0))
	_build_actors()
	_relayout()
	resized.connect(_relayout)


func _process(delta: float) -> void:
	if _reduced_motion:
		return
	for actor in _actors:
		_tick_actor(actor as Dictionary, delta)


## Freeze every actor mid-pose: no travel, no frame advance. The party
## stays complete and grounded; re-enabling resumes from the same pose.
func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


## Narrow presentation context from the host: world staging walks the
## forest clearing through the title's center offset, formation
## staging walks the standalone corridors. A staging switch restarts
## every actor at its new route head; concealment only hides the
## layer while the patrol keeps simulating, so the return never
## teleports.
func set_presentation(world_mode: bool, concealed: bool) -> void:
	if world_mode != _world_mode:
		_world_mode = world_mode
		_reset_to_route_heads()
	visible = not concealed


## True while the party walks forest-world coordinates. Tests read this.
func is_world_mode() -> bool:
	return _world_mode


## True while the patrol clocks are allowed to move. Tests read this.
func is_motion_active() -> bool:
	return not _reduced_motion


func actor_count() -> int:
	return _actors.size()


## Presentation facts for one actor: hero and weapon sources, facing,
## current sheet and frame, paint size, feet and paint rect. Tests pin
## identity and the height bands through this.
func actor_info(index: int) -> Dictionary:
	if index < 0 or index >= _actors.size():
		return {}
	var data: Dictionary = _actors[index]
	var hero: Hero = data["hero"]
	var root: Node2D = data["root"]
	return {
		"hero_path": hero.resource_path,
		"profile": hero.attack_profile,
		"facing": int(data["facing"]),
		"sheet": int(data["sheet"]),
		"moving": bool(data["moving"]),
		"world": _world_mode,
		"frame": int(data["frame"]),
		"frame_count": int((data["frames"] as Array).size()),
		"weapon_path": (WeaponRig.painted_sheet(hero.attack_profile) as Texture2D).resource_path,
		"paint_size": data["paint_size"],
		"feet": root.position,
		"paint_rect": paint_global_rect(index),
	}


## Global rect of one actor's visible paint: body opaque bounds plus the
## held weapon's rotated extent. For viewport-fit and clearance checks.
func paint_global_rect(index: int) -> Rect2:
	if index < 0 or index >= _actors.size():
		return Rect2()
	var data: Dictionary = _actors[index]
	var body: Sprite2D = data["body"]
	var unit: float = body.scale.x
	var bounds: Rect2i = data["paint"]
	var paint_size := Vector2(bounds.size) * unit
	var cell_center := Vector2(
		float((data["hero"] as Hero).sprite_cell.x) * 0.5,
		float((data["hero"] as Hero).sprite_cell.y) * 0.5)
	var paint_center := Vector2(bounds.get_center())
	var body_at: Vector2 = body.get_global_transform_with_canvas().origin \
		+ (paint_center - cell_center) * unit
	var rect := Rect2(body_at - paint_size * 0.5, paint_size)
	var weapon: Sprite2D = data["weapon"]
	var sheet: Texture2D = weapon.texture
	if sheet != null:
		var half: Vector2 = sheet.get_size() * absf(weapon.scale.x) * 0.5
		var angle: float = weapon.rotation
		var extent := Vector2(
			half.x * absf(cos(angle)) + half.y * absf(sin(angle)),
			half.x * absf(sin(angle)) + half.y * absf(cos(angle)))
		var weapon_at: Vector2 = \
			weapon.get_global_transform_with_canvas().origin
		rect = rect.merge(Rect2(weapon_at - extent, extent * 2.0))
	return rect


## Screen rect of the gate mouth under the current viewport, mapped from
## the painting through aspect-cover framing. The party keeps clear of it.
func gate_mouth_rect() -> Rect2:
	var view: Vector2 = get_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return Rect2()
	var cover: float = maxf(
		view.x / GATE_PAINT_SIZE.x, view.y / GATE_PAINT_SIZE.y)
	var shown := Vector2(view.x / cover, view.y / cover)
	var crop: Vector2 = (GATE_PAINT_SIZE - shown) * 0.5
	var shown_rect := Rect2(crop, shown)
	var mouth: Rect2 = PORTAL_PAINT.intersection(shown_rect)
	if not mouth.has_area():
		return Rect2()
	return Rect2((mouth.position - crop) * cover, mouth.size * cover)


func _build_actors() -> void:
	for index in HERO_PATHS.size():
		var hero: Hero = load(HERO_PATHS[index]) as Hero
		if hero == null or hero.idle_sheet == null \
				or hero.walk_sheet == null:
			continue
		var root := Node2D.new()
		root.name = &"HeroActor%d" % index
		add_child(root)
		var shadow := Sprite2D.new()
		shadow.name = &"Shadow"
		shadow.texture = _shadow_texture
		root.add_child(shadow)
		var body := Sprite2D.new()
		body.name = &"Body"
		body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		root.add_child(body)
		var weapon := Sprite2D.new()
		weapon.name = &"Weapon"
		weapon.texture = WeaponRig.painted_sheet(hero.attack_profile)
		weapon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		root.add_child(weapon)
		var facing: int = int(SPAWN_FACING[index])
		var route: Array = _routes_for(index)
		var data: Dictionary = {
			"hero": hero,
			"slot": index,
			"facing": facing,
			"sheet": SHEET_IDLE,
			"paint": _paint_bounds(hero, SHEET_IDLE, facing),
			"target": _target_for(index),
			"root": root,
			"shadow": shadow,
			"body": body,
			"weapon": weapon,
			"frames": [],
			"frame": 0,
			"clock": 0.0,
			"walk_cycle": 0.0,
			"feet": route[0] as Vector2,
			"waypoint": 1 % route.size(),
			"dwell_left": FIRST_DWELL_BASE + FIRST_DWELL_STEP * index,
			"moving": false,
			"visits": 0,
			"paint_size": Vector2.ZERO,
			"frame_cache": {},
		}
		data["frames"] = _frames_for(data, SHEET_IDLE, facing)
		_actors.append(data)
	for actor in _actors:
		_fit_actor(actor as Dictionary)
		_show_frame(actor as Dictionary, 0)


func _paint_bounds(hero: Hero, sheet: int, facing: int) -> Rect2i:
	var hero_id: String = WeaponRig.painted_name(hero.attack_profile)
	var table: Dictionary
	if sheet == SHEET_WALK:
		match facing:
			FACING_UP:
				table = PAINT_WALK_UP
			FACING_LEFT:
				table = PAINT_WALK_LEFT
			FACING_RIGHT:
				table = PAINT_WALK_RIGHT
			_:
				table = PAINT_WALK_DOWN
	else:
		match facing:
			FACING_UP:
				table = PAINT_IDLE_UP
			FACING_LEFT:
				table = PAINT_LEFT
			FACING_RIGHT:
				table = PAINT_IDLE_RIGHT
			_:
				table = PAINT_DOWN
	if table.has(hero_id):
		return table[hero_id] as Rect2i
	return Rect2i(Vector2i.ZERO, hero.sprite_cell)


## One atlas region per animation frame from the hero's own sheet:
## column is the facing, rows are the animation frames, cells are
## 144x192 paint. Cached per actor, so a patrol loop builds each
## column once.
func _frames_for(data: Dictionary, sheet: int, facing: int) -> Array:
	var cache: Dictionary = data["frame_cache"]
	var key: int = sheet * 4 + facing
	if cache.has(key):
		return cache[key] as Array
	var hero: Hero = data["hero"]
	var atlas_sheet: Texture2D = hero.idle_sheet \
		if sheet == SHEET_IDLE else hero.walk_sheet
	var count: int = maxi(hero.idle_frames, 1) \
		if sheet == SHEET_IDLE else maxi(hero.walk_frames, 1)
	var frames: Array = []
	for frame_index in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = atlas_sheet
		atlas.region = Rect2(
			float(facing * hero.sprite_cell.x),
			float(frame_index * hero.sprite_cell.y),
			float(hero.sprite_cell.x),
			float(hero.sprite_cell.y))
		frames.append(atlas)
	cache[key] = frames
	return frames


## Facing from a ground-travel direction, the Player rule: the dominant
## axis wins, ties read vertical.
func _face_for(travel: Vector2) -> int:
	if absf(travel.x) > absf(travel.y):
		return FACING_RIGHT if travel.x > 0.0 else FACING_LEFT
	return FACING_DOWN if travel.y > 0.0 else FACING_UP


## Stop length after one arrival, seconds. A short deterministic cycle
## per actor, staggered across the party so stops never line up.
func _dwell_for(slot: int, visits: int) -> float:
	return 1.2 + 0.4 * float((slot + visits) % 4)


## Route table and paint-height target for one actor under the current
## staging: forest-world lanes and world scale, or normalized
## standalone corridors and formation scale.
func _routes_for(slot: int) -> Array:
	return (WORLD_ROUTES[slot] if _world_mode else ROUTES[slot]) as Array


func _target_for(slot: int) -> float:
	return float(WORLD_TARGETS[slot]) \
		if _world_mode else float(TARGETS[slot])


## Restart every actor at its new route head after a staging switch:
## opening stop, spawn facing, idle sheet, refitted hold and shadow.
func _reset_to_route_heads() -> void:
	for actor in _actors:
		var data: Dictionary = actor
		var route: Array = _routes_for(int(data["slot"]))
		data["feet"] = route[0] as Vector2
		data["waypoint"] = 1 % route.size()
		data["dwell_left"] = FIRST_DWELL_BASE \
			+ FIRST_DWELL_STEP * int(data["slot"])
		data["moving"] = false
		data["visits"] = 0
		data["clock"] = 0.0
		data["walk_cycle"] = 0.0
		data["facing"] = int(SPAWN_FACING[int(data["slot"])])
		data["sheet"] = SHEET_IDLE
		data["paint"] = _paint_bounds(
			data["hero"] as Hero, SHEET_IDLE, int(data["facing"]))
		data["frames"] = _frames_for(
			data, SHEET_IDLE, int(data["facing"]))
		data["target"] = _target_for(int(data["slot"]))
		_fit_actor(data)
		_show_frame(data, 0)
	_relayout()


## The forest's depth tier at one world row, the same curve the trees
## wear: darker and bluer with distance, quantised to shared steps.
func _night_tint(world_y: float) -> Color:
	var span: float = TIER_NEAR - TIER_FAR
	var t: float = clampf((world_y - TIER_FAR) / span, 0.0, 1.0)
	var b: float = TIER_MIN + (1.0 - TIER_MIN) * pow(t, 0.85)
	b = round(b * TIER_STEPS) / TIER_STEPS
	var f: float = 1.0 - t
	return Color(
		minf(b * (1.0 - 0.10 * f), 1.0),
		minf(b * (1.0 - 0.05 * f), 1.0),
		minf(b * (1.0 + 0.06 * f), 1.0))


## Body scale from the paint-height target, weapon at the same unit so
## the hold matches the game's own body-to-weapon proportion, shadow
## spanned to the paint width. Tablets gain a little presence within
## the bands.
func _fit_actor(data: Dictionary) -> void:
	var hero: Hero = data["hero"]
	# World staging keeps true world scale at every framing; only the
	# standalone formation gains tablet presence.
	var boost: float = 1.0
	if not _world_mode and size.y > 0.0:
		boost = clampf(size.y / 360.0, 1.0, TABLET_BOOST_MAX)
	var bounds: Rect2i = data["paint"]
	var unit: float = float(data["target"]) * boost / float(bounds.size.y)
	var body: Sprite2D = data["body"]
	body.scale = Vector2(unit, unit)
	var paint_size := Vector2(bounds.size) * unit
	data["paint_size"] = paint_size
	var weapon: Sprite2D = data["weapon"]
	var sheet: Texture2D = weapon.texture
	var mirror: float = -1.0 if int(data["facing"]) == FACING_LEFT else 1.0
	weapon.scale = Vector2(unit * mirror, unit)
	if sheet != null:
		var pivot: Vector2 = WeaponRig.texture_pivot(hero.attack_profile)
		weapon.offset = (sheet.get_size() * 0.5 - pivot) * unit
	weapon.position = Vector2(
		mirror * paint_size.x * WEAPON_SIDE_FRACTION,
		-paint_size.y * WEAPON_LIFT_FRACTION)
	if HeroWeapons.primary_side(hero.attack_profile) == HeroWeapons.Side.MELEE:
		weapon.rotation = BLADE_REST_ANGLE * mirror
	else:
		weapon.rotation = GUN_REST_ANGLE * mirror
	var shadow: Sprite2D = data["shadow"]
	shadow.scale = Vector2(
		paint_size.x * 0.95 / 64.0,
		paint_size.y * 0.12 / 64.0)
	shadow.position = Vector2(_paint_offset(data).x, 3.0)


func _relayout() -> void:
	if _actors.is_empty():
		return
	var view: Vector2 = get_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	for actor in _actors:
		var data: Dictionary = actor
		_fit_actor(data)
		_place_root(data, view)


## Feet stay where the patrol left them: normalized standalone feet
## reframe with the viewport, world feet ride the title's center
## offset, so a resize never teleports the actor. Nearer feet draw
## over farther ones; world feet wear their ground row's night tier.
func _place_root(data: Dictionary, view: Vector2) -> void:
	var root: Node2D = data["root"]
	var feet: Vector2 = data["feet"]
	if _world_mode:
		root.position = feet + Screen.center_offset(view)
		var tint: Color = _night_tint(feet.y)
		(data["body"] as Sprite2D).modulate = tint
		(data["weapon"] as Sprite2D).modulate = tint
	else:
		root.position = feet * view
		(data["body"] as Sprite2D).modulate = Color.WHITE
		(data["weapon"] as Sprite2D).modulate = Color.WHITE
	root.z_index = int(root.position.y)
	_place_body(data)


## Paint anchor in cell space, scaled: how far the paint's horizontal
## center and the paint's feet sit from the cell's center. The body takes
## the negative, so the feet plant on the root and the paint centers over
## it. No bob: standing feet stay pixel-fixed.
func _paint_offset(data: Dictionary) -> Vector2:
	var hero: Hero = data["hero"]
	var bounds: Rect2i = data["paint"]
	var unit: float = (data["body"] as Sprite2D).scale.x
	var cell := Vector2(hero.sprite_cell)
	return Vector2(
		float(bounds.get_center().x) - cell.x * 0.5,
		float(bounds.end.y) - cell.y * 0.5) * unit


## Body center above the planted feet.
func _place_body(data: Dictionary) -> void:
	(data["body"] as Sprite2D).position = -_paint_offset(data)


func _tick_actor(data: Dictionary, delta: float) -> void:
	var view: Vector2 = get_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	if bool(data["moving"]):
		_walk_leg(data, delta, view)
	else:
		_rest_stop(data, delta)
	var frames: Array = data["frames"]
	if int(data["sheet"]) == SHEET_IDLE:
		var hero: Hero = data["hero"]
		data["clock"] = float(data["clock"]) \
			+ delta * maxf(hero.idle_fps, 1.0)
		_show_frame(data,
			int(floor(float(data["clock"]))) % frames.size())
	else:
		_show_frame(data,
			int(floor(float(data["walk_cycle"]) * 4.0)) % frames.size())
	_place_root(data, view)


## Feet delta to screen pixels under the current staging: world feet
## already are pixels, normalized feet scale with the viewport.
func _travel_px(goal: Vector2, feet: Vector2, view: Vector2) -> Vector2:
	if _world_mode:
		return goal - feet
	return Vector2(
		(goal.x - feet.x) * view.x, (goal.y - feet.y) * view.y)


## A screen-pixel step back to feet units under the current staging.
func _advance_feet(
	feet: Vector2, unit_px: Vector2, step: float, view: Vector2
) -> Vector2:
	if _world_mode:
		return feet + unit_px * step
	return feet + Vector2(
		unit_px.x * step / view.x, unit_px.y * step / view.y)


## One patrol leg toward the next waypoint at the actor's own pace.
## Arrival plants the feet, keeps the facing, and starts the idle stop.
## Every step advances the walk cycle by the distance honestly moved,
## so the stride matches the feet in both stagings at every framing.
func _walk_leg(data: Dictionary, delta: float, view: Vector2) -> void:
	var route: Array = _routes_for(int(data["slot"]))
	var goal: Vector2 = route[int(data["waypoint"])] as Vector2
	var feet: Vector2 = data["feet"]
	var travel: Vector2 = _travel_px(goal, feet, view)
	var distance: float = travel.length()
	var step: float = float(SPEEDS[int(data["slot"])]) * delta
	if step >= distance or distance < 0.001:
		_advance_cycle(data, distance)
		data["feet"] = goal
		data["waypoint"] = (int(data["waypoint"]) + 1) % route.size()
		data["visits"] = int(data["visits"]) + 1
		data["moving"] = false
		data["dwell_left"] = _dwell_for(
			int(data["slot"]), int(data["visits"]))
		_set_pose(data, SHEET_IDLE, int(data["facing"]))
		return
	data["feet"] = _advance_feet(
		feet, travel / distance, step, view)
	_advance_cycle(data, step)


## Walk cycle in whole cycles from measured screen travel: one cycle
## per WALK_CYCLE_HEIGHTS of the actor's own visible paint height.
func _advance_cycle(data: Dictionary, step_px: float) -> void:
	var cycle: float = (data["paint_size"] as Vector2).y \
		* WALK_CYCLE_HEIGHTS
	if cycle > 0.0 and step_px > 0.0:
		data["walk_cycle"] = float(data["walk_cycle"]) + step_px / cycle


## One idle stop: the feet stay planted while the dwell runs out, then
## the actor faces the next waypoint for real and steps off on the
## walk sheet.
func _rest_stop(data: Dictionary, delta: float) -> void:
	data["dwell_left"] = float(data["dwell_left"]) - delta
	if float(data["dwell_left"]) > 0.0:
		return
	var route: Array = _routes_for(int(data["slot"]))
	var goal: Vector2 = route[int(data["waypoint"])] as Vector2
	var feet: Vector2 = data["feet"]
	var travel: Vector2 = _travel_px(goal, feet, get_rect().size)
	if travel.length() < 0.001:
		data["waypoint"] = (int(data["waypoint"]) + 1) % route.size()
		data["dwell_left"] = _dwell_for(
			int(data["slot"]), int(data["visits"]))
		return
	_set_pose(data, SHEET_WALK, _face_for(travel))
	data["moving"] = true


## Swap the animation sheet and facing together: new atlas column,
## new grounding bounds, refitted hold and shadow. The walk cycle and
## the idle clock both run on without a restart, so a departure
## resumes its stride row and an arrival keeps its breath. A no-op
## when nothing changes, so a stop never rebuilds mid-dwell.
func _set_pose(data: Dictionary, sheet: int, facing: int) -> void:
	if int(data["sheet"]) == sheet and int(data["facing"]) == facing:
		return
	data["sheet"] = sheet
	data["facing"] = facing
	data["paint"] = _paint_bounds(
		data["hero"] as Hero, sheet, facing)
	data["frames"] = _frames_for(data, sheet, facing)
	_fit_actor(data)


func _show_frame(data: Dictionary, frame: int) -> void:
	data["frame"] = frame
	(data["body"] as Sprite2D).texture = (data["frames"] as Array)[frame]
