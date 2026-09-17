extends Node2D

## Light ring that fills at the player's feet.
##
## It fills while standing by a beacon, and the beacon lights when it is full.
## Leave and it drains back — not a punishment, a signal to stay here.
##
## A circular gauge without a shader. Two copies of the same ring overlap, and
## **only the top copy's `region` grows from the bottom up.** It looks like a fill.

@onready var _track: Sprite2D = $Track
@onready var _fill: Sprite2D = $Fill

var _size: Vector2 = Vector2.ZERO
var _overcharge: bool = false

const NORMAL_TRACK: Color = Color(1.0, 0.86, 0.55, 0.18)
const NORMAL_FILL: Color = Color(1.0, 0.78, 0.36, 0.95)
const OVERCHARGE_TRACK: Color = Color(0.72, 0.48, 1.0, 0.24)
const OVERCHARGE_FILL: Color = Color(0.9, 0.7, 1.0, 1.0)


func _ready() -> void:
	_size = _fill.texture.get_size()
	_fill.region_enabled = true
	set_progress(0.0)


## 0 ~ 1.
func set_progress(value: float) -> void:
	var p: float = clampf(value, 0.0, 1.0)
	visible = p > 0.001

	var h: float = _size.y * p
	# Fills from the bottom up. Crop the region and shift it down by the crop.
	_fill.region_rect = Rect2(0.0, _size.y - h, _size.x, h)
	_fill.offset = Vector2(0.0, (_size.y - h) * 0.5)


## Same ring for normal beacon charge and overcharge defense; color tells them apart.
func set_overcharge(value: bool) -> void:
	if _overcharge == value:
		return
	_overcharge = value
	_track.modulate = OVERCHARGE_TRACK if value else NORMAL_TRACK
	_fill.modulate = OVERCHARGE_FILL if value else NORMAL_FILL
