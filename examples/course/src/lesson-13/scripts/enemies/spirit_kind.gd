## One enemy type as data: sheet layout, gait, and temperament.
## A new enemy needs a new file, not new code or a new scene.
class_name SpiritKind
extends Resource

@export var display_name: String = "Spirit"
@export var sheet: Texture2D = null
@export var cell: int = 16
@export var rows: int = 4
@export var columns: int = 4
@export var speed: float = 62.0
@export var turn_rate: float = 5.0
@export var body_scale: float = 1.0
@export var tint: Color = Color(1, 1, 1, 1)
@export var anim_fps: float = 5.0
