class_name KillSparks
extends Node2D

## A little burst of moon dust where a spirit dies.
##
## A kill used to be a fade and a 35% swell over a quarter of a second, which
## reads as the sprite going away rather than being beaten. A burst of sparks in
## the spirit's own colour gives the kill somewhere to land.
##
## **One node draws every burst.** The late game already sits close to the arena's
## node budget and a chain kill can end a dozen spirits in a frame, so a particle
## node per kill would spend exactly what the budget lacks. Here a burst is a row
## in a list and the whole pool is one `_draw()`, which costs a few dozen small
## rectangles for as long as anything is sparkling and nothing otherwise.
##
## The spirit does not know about this node. It calls the group, so a spirit in a
## test with no arena still dies quietly.

const GROUP: StringName = &"moonlit_sparks"

const LIFE: float = 0.5
## Older bursts are dropped first, so a screen-clearing chain never grows the list.
const MAX_BURSTS: int = 28
## Where a spirit's body is, above the point it stands on.
const BODY_LIFT: Vector2 = Vector2(0.0, -8.0)
## Ground-plane shapes are squashed by this much, the same squash the lantern pools
## and cast shadows use, so a burst agrees with the camera angle.
const SQUASH: float = 0.62

## The flash where a spirit died, a soft glow and not a hard disc.
static var _glow: GradientTexture2D = null

## `{at, color, age, big, spin}` per burst.
var _bursts: Array[Dictionary] = []


func _ready() -> void:
	z_index = 3
	light_mask = 0
	add_to_group(GROUP)
	# Additive: a spark is light. Over a dark floor it glows, over a bright one it
	# stays out of the way.
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_process(false)


## Start a burst at a spirit's feet. `big` is for elites and guardians.
func burst(at: Vector2, color: Color, big: bool = false) -> void:
	if _bursts.size() >= MAX_BURSTS:
		_bursts.remove_at(0)
	_bursts.append({
		"at": at + BODY_LIFT,
		"color": color,
		"age": 0.0,
		"big": big,
		"spin": randf() * TAU,
	})
	set_process(true)


func active_count() -> int:
	return _bursts.size()


func _process(delta: float) -> void:
	for index in range(_bursts.size() - 1, -1, -1):
		_bursts[index]["age"] = float(_bursts[index]["age"]) + delta
		if float(_bursts[index]["age"]) >= LIFE:
			_bursts.remove_at(index)
	if _bursts.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for entry: Dictionary in _bursts:
		_draw_burst(entry)


func _draw_burst(entry: Dictionary) -> void:
	var progress: float = float(entry["age"]) / LIFE
	# Fast out of the gate and slowing, so the burst pops and then floats.
	var eased: float = 1.0 - pow(1.0 - progress, 3.0)
	var fade: float = 1.0 - progress
	var big: bool = bool(entry["big"])
	var origin: Vector2 = entry["at"]
	var color: Color = entry["color"]
	var count: int = 14 if big else 8
	var reach: float = 30.0 if big else 18.0
	var spin: float = float(entry["spin"])

	for k in count:
		var angle: float = spin + TAU * float(k) / float(count) + float(k % 2) * 0.35
		# Alternate near and far sparks so the ring is not a perfect circle.
		var travel: float = reach * eased * (0.62 + 0.38 * float((k * 7) % 5) / 4.0)
		var at: Vector2 = origin + Vector2(
			cos(angle) * travel, sin(angle) * travel * SQUASH - eased * 5.0)
		# Snap to the pixel grid so the dust matches the pixel art around it.
		var pixel: Vector2 = at.round()
		var size: float = roundf((3.0 if k % 2 == 0 else 2.0) * (1.0 - progress * 0.45))
		var spark := Color(color.r, color.g, color.b, fade)
		if size >= 3.0:
			# The big sparks are four-point stars.
			draw_rect(Rect2(pixel + Vector2(-1.0, -0.5), Vector2(3.0, 1.0)), spark)
			draw_rect(Rect2(pixel + Vector2(-0.5, -1.0), Vector2(1.0, 3.0)), spark)
		else:
			draw_rect(Rect2(pixel, Vector2(maxf(size, 1.0), maxf(size, 1.0))), spark)

	# A flash where it died, brightest at the start.
	var flash: float = (22.0 if big else 13.0) * (0.55 + 0.45 * eased)
	var glow := Color(color.r, color.g, color.b, fade * fade * 0.85)
	draw_texture_rect(_glow_texture(), Rect2(
		origin - Vector2(flash, flash * SQUASH), Vector2(flash, flash * SQUASH) * 2.0), false, glow)
	if big:
		draw_set_transform(origin, 0.0, Vector2(1.0, SQUASH))
		draw_arc(Vector2.ZERO, reach * 1.15 * eased, 0.0, TAU, 28,
			Color(color.r, color.g, color.b, fade * 0.7), 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _glow_texture() -> GradientTexture2D:
	if _glow == null:
		_glow = SoftDisc.radial([
			Vector2(0.0, 1.0), Vector2(0.3, 0.5), Vector2(0.7, 0.12), Vector2(1.0, 0.0)])
	return _glow
