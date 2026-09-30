class_name RoomLights
extends RoomLayer

## Warm ground pools under the terrain art that is on fire.
##
## **One node for every light on the map, not one node per light.** The room
## already worries about node count on mobile — camp alone places 250 decor and
## 30 structures — so this draws every pool in a single `_draw()` instead of
## adding a `PointLight2D` per lantern.
##
## Additive blend, so a pool adds light to the floor rather than tinting it.
## Drawn above `Ground` and below `Decor`, so a crate standing in a pool is lit
## around its feet but never painted over.

## Radial falloff, built once in code. A PNG for a gradient would be one more
## asset to keep in the manifest for something the engine can generate exactly.
static var _falloff: GradientTexture2D = null

## `{at: Vector2, radius: float, color: Color}` per light.
var _pools: Array[Dictionary] = []
## Small glows under luminous plants: `{at, radius, color, lag}`. Each breathes with
## its own lag, so a patch of mushrooms twinkles instead of pulsing as one.
var _glows: Array[Dictionary] = []
## Patches of moonlight through the canopy: `{at, size, color, lag}`. They drift
## in and out very slowly.
var _dapples: Array[Dictionary] = []
## Pool alpha at rest. Breathing is applied on top of this.
var _base_alpha: float = 1.0
## Seconds since build, for the flame breathe.
var _age: float = 0.0


func _ready() -> void:
	super._ready()
	z_index = -1
	# Additive. Without this the pool darkens the floor it is supposed to light.
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	set_process(_animated())


## Replace the light set. The room calls this once per build.
func set_pools(pools: Array[Dictionary]) -> void:
	_pools = pools
	_refresh()


func set_glows(glows: Array[Dictionary]) -> void:
	_glows = glows
	_refresh()


func set_dapples(dapples: Array[Dictionary]) -> void:
	_dapples = dapples
	_refresh()


func dapple_count() -> int:
	return _dapples.size()


func glow_count() -> int:
	return _glows.size()


func _animated() -> bool:
	return not (_pools.is_empty() and _glows.is_empty() and _dapples.is_empty())


func _refresh() -> void:
	if is_inside_tree():
		set_process(_animated())
	queue_redraw()


## A flame is not a steady bulb. One slow shared breathe reads as firelight
## without giving every lantern its own tween.
func _process(delta: float) -> void:
	_age += delta
	_base_alpha = 0.92 + sin(_age * 1.7) * 0.08
	queue_redraw()


## Hold the breathe at full and stop animating.
##
## A store capture compares the frame before the shot with the frame after it.
## A pool caught on a different point of its sine would make those two differ
## and eject the capture, the same way a half-faded HUD line would.
func debug_settle_lights() -> void:
	_base_alpha = 1.0
	_age = 0.0
	set_process(false)
	queue_redraw()


func _draw() -> void:
	if not _animated():
		return
	var falloff: Texture2D = _falloff_texture()
	# Only what the camera can see: the map holds a few hundred lights and the
	# screen shows a tenth of them, and this node redraws every frame.
	var view: Rect2 = view_rect()
	# Moonlight first, so a lantern pool and a glow always add on top of it.
	for dapple: Dictionary in _dapples:
		var reach: Vector2 = (dapple["size"] as Vector2) * 1.6
		if view.intersects(Rect2((dapple["at"] as Vector2) - reach, reach * 2.0)):
			_draw_dapple(falloff, dapple)
	for glow: Dictionary in _glows:
		var radius: float = float(glow["radius"])
		var extent: Vector2 = Vector2(radius * 2.0, radius * 1.3)
		var at: Vector2 = glow["at"]
		if not view.intersects(Rect2(at - extent, extent * 2.0)):
			continue
		var twinkle: float = 0.72 + sin(_age * 1.5 + float(glow["lag"])) * 0.28
		var tint: Color = glow["color"]
		tint.a *= twinkle
		draw_texture_rect(falloff, Rect2(at - extent * 0.5, extent), false, tint)
	for pool: Dictionary in _pools:
		var at: Vector2 = pool.get("at", Vector2.ZERO)
		var radius: float = float(pool.get("radius", 96.0))
		var size: Vector2 = Vector2(radius * 2.0, radius * 1.3)
		if not view.intersects(Rect2(at - size, size * 2.0)):
			continue
		var color: Color = pool.get("color", Color(0.5, 0.3, 0.12, 1))
		color.a *= _base_alpha
		# Squash vertically. The camera looks down at an angle, so a circular
		# pool reads as a ball of light standing up off the floor.
		draw_texture_rect(falloff, Rect2(at - size * 0.5, size), false, color)


## One dapple is three overlapping lobes, so it reads as light through leaves and
## not as a perfect ellipse.
func _draw_dapple(falloff: Texture2D, dapple: Dictionary) -> void:
	var at: Vector2 = dapple["at"]
	var size: Vector2 = dapple["size"]
	var color: Color = dapple["color"]
	color.a *= 0.8 + sin(_age * 0.45 + float(dapple["lag"])) * 0.2
	draw_texture_rect(falloff, Rect2(at - size, size * 2.0), false, color)
	var second: Vector2 = size * 0.62
	draw_texture_rect(falloff, Rect2(
		at + Vector2(size.x * 0.5, -size.y * 0.25) - second, second * 2.0), false, color)
	var third: Vector2 = size * 0.5
	draw_texture_rect(falloff, Rect2(
		at + Vector2(-size.x * 0.42, size.y * 0.3) - third, third * 2.0), false, color)


static func _falloff_texture() -> GradientTexture2D:
	if _falloff == null:
		# Bright core, long tail. A linear ramp reads as a hard-edged disc.
		_falloff = SoftDisc.radial([
			Vector2(0.0, 1.0), Vector2(0.32, 0.46), Vector2(0.66, 0.12), Vector2(1.0, 0.0)],
			128)
	return _falloff
