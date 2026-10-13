## Shared viewport math for centering the fixed 808x360 stage.
class_name Screen
extends RefCounted

const BASE_SIZE: Vector2 = Vector2(808, 360)


static func center_offset(viewport_size: Vector2) -> Vector2:
	return ((viewport_size - BASE_SIZE) * 0.5).floor()
