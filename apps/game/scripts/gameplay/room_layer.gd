class_name RoomLayer
extends Node2D

## A layer of the room that is drawn once and redrawn only when the camera moves on.
##
## The floor layers (shadows, colour patches, plants) hold about three thousand small
## draws for a 1900x1180 map, and the screen shows a tenth of it. A single canvas item
## cannot be culled in part, so drawing it whole would pay for the other nine tenths
## every frame, which on a phone is milliseconds. Splitting the map into a node per
## chunk would fix that with dozens of nodes the arena's budget does not have.
##
## So the layer stays one node and draws **only what the camera can see**, padded, and
## redraws when the padded view crosses into a new cell of the grid. Walking costs a
## redraw of a tenth of the layer roughly once a second, and standing still costs
## nothing.
##
## Subclasses draw in `_draw()` and ask `view_rect()` which records are worth drawing.

## Grid the redraw is quantised to. Larger means fewer redraws and more padding.
const CELL: float = 192.0
## How far beyond the screen a layer keeps drawing, so nothing pops in at the edge.
const MARGIN: float = 96.0

var _cells: Rect2i = Rect2i()


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	var cells: Rect2i = _view_cells()
	if cells != _cells:
		_cells = cells
		queue_redraw()


## The part of this layer the camera can see, in this node's own coordinates, with
## padding. Snapped to the cell grid, so it is the same for every draw in one cell.
func view_rect() -> Rect2:
	var cells: Rect2i = _view_cells()
	return Rect2(Vector2(cells.position) * CELL, Vector2(cells.size) * CELL)


func _view_cells() -> Rect2i:
	var screen: Rect2 = get_viewport_rect()
	var to_local: Transform2D = (get_canvas_transform() * get_global_transform()).affine_inverse()
	var seen: Rect2 = (to_local * screen).grow(MARGIN)
	var first: Vector2i = Vector2i((seen.position / CELL).floor())
	var last: Vector2i = Vector2i((seen.end / CELL).ceil())
	return Rect2i(first, last - first)
