class_name RoomFlora
extends RoomLayer

## Tiny plants on the floor: mushrooms, flowers and grass tufts.
##
## A floor with a few rocks on it is empty however well it is lit. Small living
## things scattered through it are what make a clearing look like somewhere, and
## the game is meant to be a cute one, so they are small and round and bright.
##
## Each plant is a few `draw_rect` pixels, snapped to the pixel grid, so they sit
## in the sprite art's resolution with no sheet to maintain. **One node draws all
## of them** and is static after the build. Their glow is not drawn here: the
## light belongs to `RoomLights`, which is additive and breathes.

enum Plant {
	MUSHROOM,
	FLOWER,
	TUFT,
}

const STEM: Color = Color(0.72, 0.9, 0.96, 1.0)
const LEAF: Color = Color(0.3, 0.62, 0.42, 1.0)
const LEAF_LIGHT: Color = Color(0.5, 0.82, 0.55, 1.0)
const CENTER: Color = Color(1.0, 0.93, 0.55, 1.0)

## `{at, plant, size, color}` per plant. `at` is where it meets the ground.
var _plants: Array[Dictionary] = []


func _ready() -> void:
	super._ready()
	z_index = -1
	light_mask = 0


func add_plant(at: Vector2, plant: Plant, size: int, color: Color) -> void:
	_plants.append({"at": at.round(), "plant": plant, "size": size, "color": color})


func clear() -> void:
	_plants.clear()
	queue_redraw()


func plant_count() -> int:
	return _plants.size()


## Where each plant stands, in placement order. For tests.
func plant_positions() -> PackedVector2Array:
	var positions := PackedVector2Array()
	for entry: Dictionary in _plants:
		positions.append(entry["at"])
	return positions


func finish() -> void:
	queue_redraw()


func _draw() -> void:
	var view: Rect2 = view_rect()
	for entry: Dictionary in _plants:
		var at: Vector2 = entry["at"]
		if not view.has_point(at):
			continue
		var color: Color = entry["color"]
		var size: int = int(entry["size"])
		match int(entry["plant"]):
			Plant.MUSHROOM:
				_mushroom(at, size, color)
			Plant.FLOWER:
				_flower(at, color)
			_:
				_tuft(at, size)


func _px(at: Vector2, x: int, y: int, w: int, h: int, color: Color) -> void:
	draw_rect(Rect2(at + Vector2(x, y), Vector2(w, h)), color)


## A round cap on a thin stem. The cap is the glowing part.
func _mushroom(at: Vector2, size: int, color: Color) -> void:
	var light: Color = color.lightened(0.45)
	if size <= 1:
		_px(at, 0, -2, 1, 2, STEM)
		_px(at, -1, -3, 3, 1, color)
		_px(at, -1, -3, 1, 1, light)
		return
	_px(at, 0, -3, 1, 3, STEM)
	_px(at, -1, -5, 3, 1, color)
	_px(at, -2, -4, 5, 1, color)
	_px(at, -1, -5, 1, 1, light)
	_px(at, 1, -4, 1, 1, light)


## Four petals round a bright centre, on a green stem.
func _flower(at: Vector2, color: Color) -> void:
	_px(at, 0, -3, 1, 3, LEAF)
	_px(at, 0, -5, 1, 1, color)
	_px(at, -1, -4, 1, 1, color)
	_px(at, 1, -4, 1, 1, color)
	_px(at, 0, -3, 1, 1, color)
	_px(at, 0, -4, 1, 1, CENTER)


## Three blades leaning a little apart.
func _tuft(at: Vector2, size: int) -> void:
	var tall: int = 3 + clampi(size, 0, 2)
	_px(at, -1, -tall + 1, 1, tall - 1, LEAF)
	_px(at, 0, -tall, 1, tall, LEAF_LIGHT)
	_px(at, 1, -tall + 2, 1, tall - 2, LEAF)
