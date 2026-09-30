class_name PlaceMotif
extends Node2D

## The small crafted memory that stands beside this zone's beacon.
##
## One node with one sprite, drawn from the shared `places/motifs.png` sheet:
## six terrain columns in `Expedition.TERRAINS` order, a dim row and a lit row.
## The arena moves it to each new beacon clearing dim, and lights it when the
## beacon burns. It adds no combat power and no collision — it only shows that
## restoring the beacon restored something that was already there.
##
## Two nodes total (this plus the sprite), reused across zones, so the
## late-game node budget barely notices it.

## Six 32px columns by terrain, dim row above the lit row.
const SHEET: Texture2D = preload("res://assets/custom/world/places/motifs.png")
const CELL: float = 32.0

var _sprite: Sprite2D = null
var _terrain: int = -1
var _lit: bool = false


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = &"Motif"
	_sprite.texture = SHEET
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(0, 0, CELL, CELL)
	_sprite.centered = true
	add_child(_sprite)


## Point at this terrain's motif, dim. The arena calls this when the beacon
## for a new zone is placed.
func show_terrain(terrain: int) -> void:
	_terrain = terrain
	set_lit(false)


## Which terrain's motif is showing, or -1 before the first zone.
func terrain() -> int:
	return _terrain


func is_lit() -> bool:
	return _lit


## Light the motif (or dim it again). Lighting pops once so the restoration
## reads even if the player is already looking at the beacon.
func set_lit(lit: bool) -> void:
	_lit = lit
	if _sprite == null:
		return
	var column: float = float(maxi(_terrain, 0)) * CELL
	_sprite.region_rect = Rect2(
		column, CELL if lit else 0.0, CELL, CELL)
	if lit and is_inside_tree():
		_sprite.scale = Vector2(1.3, 1.3)
		var pop: Tween = create_tween()
		pop.tween_property(_sprite, "scale", Vector2.ONE, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
