class_name GroundBurst
extends Node2D

## A circle marked on the floor that bursts after a moment.
##
## The whole fairness of it is the mark: the ring says **where**, the filling disc says **when**, and
## nothing hurts until it is full. One `_draw()` node, no child nodes, freed a moment after the
## burst, and never more than `LIMIT` alive, so a guardian's meteors cost the mobile budget almost
## nothing.
##
## The floor is seen at a slant, so the circle is drawn squashed to match the ground shadows and is
## judged the same way: an ellipse, not a disc.

const GROUP: StringName = &"ground_bursts"
## Alive at once, across every guardian and skill.
const LIMIT: int = 8
## How long the flash of the burst lingers.
const FLASH_SECONDS: float = 0.22
## Vertical squash of a ground circle. Matches the actors' foot shadows.
const SQUASH: float = 0.72
## The player's body sits a little above their feet.
const BODY_OFFSET: Vector2 = Vector2(0, -4)
## Half the player's body width, added to the radius so a graze counts.
const BODY_REACH: float = 3.0

var radius: float = 24.0
var color: Color = Color(1.0, 0.62, 0.36, 1.0)

var _fuse: float = 1.0
var _left: float = 1.0
var _burst: bool = false
var _target: Node2D = null
var _hit_handler: Callable = Callable()
## A friendly mark (the Comet Call skill) never hurts the player: on bursting it simply calls the
## handler with where it burst, and the caller decides what that hurts.
var _friendly: bool = false


## Mark a circle at `at`. Returns null when the floor already holds `LIMIT` marks.
static func mark(
		parent: Node, at: Vector2, circle_radius: float, fuse: float, tint: Color,
		target: Node2D, hit_handler: Callable, friendly: bool = false) -> GroundBurst:
	if parent == null or not parent.is_inside_tree():
		return null
	if parent.get_tree().get_node_count_in_group(GROUP) >= LIMIT:
		return null
	var burst: GroundBurst = GroundBurst.new()
	burst.radius = circle_radius
	burst.color = tint
	burst._fuse = maxf(fuse, 0.05)
	burst._left = burst._fuse
	burst._target = target
	burst._hit_handler = hit_handler
	burst._friendly = friendly
	burst.z_index = -1
	parent.add_child(burst)
	burst.global_position = at
	return burst


func _ready() -> void:
	add_to_group(GROUP)


func _physics_process(delta: float) -> void:
	_left -= delta
	if not _burst and _left <= 0.0:
		_detonate()
	elif _burst and _left <= -FLASH_SECONDS:
		queue_free()
		return
	queue_redraw()


## Whether the target's body is inside the marked ellipse.
func covers(point: Vector2) -> bool:
	var offset: Vector2 = point - global_position
	offset.y /= SQUASH
	var reach: float = radius + BODY_REACH
	return offset.length_squared() <= reach * reach


func _detonate() -> void:
	_burst = true
	if _friendly:
		if _hit_handler.is_valid():
			_hit_handler.call(global_position)
		return
	if _target == null or not is_instance_valid(_target):
		return
	if covers(_target.to_global(BODY_OFFSET)) and _hit_handler.is_valid():
		_hit_handler.call(global_position)


func _draw() -> void:
	if _burst:
		# The burst: a bright disc that fades as it opens, and a ring that runs outward.
		var flash: float = clampf(1.0 + _left / FLASH_SECONDS, 0.0, 1.0)
		TelegraphArt.soft_disc(self, Vector2.ZERO, radius * (1.0 + 0.25 * (1.0 - flash)),
			TelegraphArt.HOT, 0.85 * flash, SQUASH)
		TelegraphArt.glow_ring(self, Vector2.ZERO, radius * (1.0 + 0.5 * (1.0 - flash)),
			color.lerp(Color.WHITE, 0.5), flash, 1.6, SQUASH)
		return
	var progress: float = clampf(1.0 - _left / _fuse, 0.0, 1.0)
	# The last stretch blinks faster: the eye reads "now".
	var pulse: float = 0.5 + 0.5 * sin(progress * TAU * (2.0 + 4.0 * progress))
	# The whole circle is faintly lit from the start, so the reach is honest; the bright disc
	# inside grows to fill it, and that is the time left.
	TelegraphArt.soft_disc(self, Vector2.ZERO, radius, color, 0.16, SQUASH)
	TelegraphArt.soft_disc(self, Vector2.ZERO, radius * progress, color.lerp(TelegraphArt.HOT, 0.4),
		0.22 + 0.34 * progress, SQUASH)
	TelegraphArt.glow_ring(self, Vector2.ZERO, radius, color.lerp(Color.WHITE, 0.25),
		0.5 + 0.4 * pulse, 1.3, SQUASH)
