class_name RoomAtmosphere
extends Node2D

## The air of a room: drifting mist, shafts of moonlight and floating motes.
##
## The title screen has all three and the arena had none, so the place you spend
## the whole game in was the flat one. This gives the arena the same depth, and
## unlike the title it moves with a camera that follows the player:
##
##   * two layers of mist on `Parallax2D`, one behind the trees that slides slower
##     than the ground and one in front that slides faster, so walking through the
##     room shows the scene's depth without a single 3D asset;
##   * a few slanted shafts of light through the canopy, drawn here once;
##   * motes, as one particle system that follows the camera.
##
## Everything is faint on purpose. A dodge game must keep reading its enemies, so
## the front layer is the faintest and none of it ever covers the play area's
## edge tint or a telegraph.

## The fog is one small seamless noise tile, generated once and stretched. A
## painted cloud sheet has hard tone steps that read as stacked discs once the
## fog is bright enough to see, and noise has none.
const FOG_SIZE: Vector2i = Vector2i(256, 128)
const FOG_SCALE: float = 4.0
## How far a shaft leans: pixels to the right per pixel of length. The moon is on the
## upper left, so light falls down and to the right.
const LEAN: float = 0.38

static var _fog: ImageTexture = null
## Shaft profile, baked once: soft sides, wider toward the ground, fading in from the
## canopy. One textured quad per shaft, and none of it redrawn while it is on screen.
const SHAFT_SIZE: Vector2i = Vector2i(32, 64)
static var _shaft: ImageTexture = null

## The twinkling sparks the beacon's embers and the title's motes use: seven frames,
## ten pixels wide, on one strip.
const SPARK: Texture2D = preload("res://assets/custom/world/beacon/spark.png")
const SPARK_FRAME: Vector2 = Vector2(10.0, 8.0)
const SPARK_FRAMES: int = 7

@onready var _mist_far: Parallax2D = $MistFar
@onready var _mist_near: Parallax2D = $MistNear
@onready var _beams: Node2D = $Beams
@onready var _motes: Node2D = $Motes

## `{at, length, width, alpha}` per shaft.
var _shafts: Array[Dictionary] = []
var _beam_tint: Color = Color(0.72, 0.83, 1.0, 1.0)
var _age: float = 0.0

## The motes, as parallel arrays: position, drift, age, life, size. Drawn by this
## script and not by a particle system, which cost about as much as everything else
## in this node together for a few dozen sparks.
var _mote_at: PackedVector2Array = PackedVector2Array()
var _mote_drift: PackedVector2Array = PackedVector2Array()
var _mote_age: PackedFloat32Array = PackedFloat32Array()
var _mote_life: PackedFloat32Array = PackedFloat32Array()
var _mote_size: PackedFloat32Array = PackedFloat32Array()
var _mote_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_beams.material = additive
	_beams.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_beams.draw.connect(_draw_shafts)
	_motes.material = additive
	_motes.draw.connect(_draw_motes)
	for layer: Parallax2D in [_mist_far, _mist_near]:
		var sprite: Sprite2D = layer.get_node("Sprite") as Sprite2D
		sprite.texture = _fog_texture()
		sprite.scale = Vector2.ONE * FOG_SCALE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		layer.repeat_size = Vector2(FOG_SIZE) * FOG_SCALE


## Lay the atmosphere out for one room. Deterministic in `seed_value`.
func configure(kind: RoomKind, seed_value: int, play: Rect2) -> void:
	_mist_far.modulate = kind.mist_color
	var near: Color = kind.mist_color
	near.a *= 0.5
	_mist_near.modulate = near
	_beam_tint = kind.beam_color
	_motes.modulate = kind.mote_color
	_mote_rng.seed = hash([seed_value, "motes", int(kind.encounter)])
	_fill_motes(kind.mote_count, _view_rect(play))

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "shafts", int(kind.encounter)])
	_shafts.clear()
	for i in kind.beam_count:
		_shafts.append({
			"at": Vector2(
				rng.randf_range(play.position.x, play.end.x),
				rng.randf_range(play.position.y - 60.0, play.end.y - 160.0)),
			"length": rng.randf_range(130.0, 210.0),
			"width": rng.randf_range(64.0, 112.0),
			"alpha": rng.randf_range(0.55, 1.0),
		})
	# The shafts are drawn once, here. Redrawing polygons every frame cost more than
	# the rest of the atmosphere together; they breathe through their node instead.
	_beams.queue_redraw()
	set_process(true)


func shaft_count() -> int:
	return _shafts.size()


func mote_count() -> int:
	return _mote_at.size()


func _process(delta: float) -> void:
	_age += delta
	# The shafts breathe and drift as one: two properties, no redraw.
	_beams.modulate.a = 0.84 + sin(_age * 0.45) * 0.16
	_beams.position.x = sin(_age * 0.21) * 4.0
	_step_motes(delta)


## The part of the world the camera shows, in this node's coordinates. Before there is
## a camera (a room built ahead of the frame that shows it) the fallback is used.
func _view_rect(fallback: Rect2 = Rect2()) -> Rect2:
	var to_local: Transform2D = (get_canvas_transform() * get_global_transform()).affine_inverse()
	var seen: Rect2 = to_local * get_viewport_rect()
	return seen if seen.has_area() else fallback


func _fill_motes(count: int, view: Rect2) -> void:
	_mote_at.resize(count)
	_mote_drift.resize(count)
	_mote_age.resize(count)
	_mote_life.resize(count)
	_mote_size.resize(count)
	for index in count:
		_respawn_mote(index, view)
		# Start mid-life, so a fresh room is not a screen of sparks all beginning at once.
		_mote_age[index] = _mote_rng.randf() * _mote_life[index]


func _respawn_mote(index: int, view: Rect2) -> void:
	_mote_at[index] = view.position + Vector2(
		_mote_rng.randf() * view.size.x, _mote_rng.randf() * view.size.y)
	_mote_drift[index] = Vector2(_mote_rng.randf_range(-3.0, 6.0), _mote_rng.randf_range(-9.0, -2.0))
	_mote_age[index] = 0.0
	_mote_life[index] = _mote_rng.randf_range(3.5, 7.0)
	_mote_size[index] = _mote_rng.randf_range(0.5, 0.9)


## Drift each mote, and bring it back inside the view when its life ends or the camera
## has left it behind. The motes live around the camera, not across the whole map:
## the tenth of the map that is on screen is the only part anyone sees.
func _step_motes(delta: float) -> void:
	var count: int = _mote_at.size()
	if count == 0:
		return
	var view: Rect2 = _view_rect().grow(20.0)
	for index in count:
		_mote_age[index] += delta
		var expired: bool = _mote_age[index] >= _mote_life[index]
		if expired or not view.has_point(_mote_at[index]):
			_respawn_mote(index, view)
			if not expired:
				# Brought back because the camera moved on, not because it ended: start
				# it partway through, so the screen is not full of sparks all beginning
				# at once.
				_mote_age[index] = _mote_rng.randf() * _mote_life[index]
			continue
		_mote_at[index] += _mote_drift[index] * delta
	_motes.queue_redraw()


func _draw_motes() -> void:
	for index in _mote_at.size():
		var progress: float = _mote_age[index] / _mote_life[index]
		# Fade in, hold, fade out; the sheet's frames run small, big, small.
		var glow: float = sin(progress * PI)
		var frame: int = clampi(int(sin(progress * PI) * float(SPARK_FRAMES)), 0, SPARK_FRAMES - 1)
		var size: Vector2 = SPARK_FRAME * _mote_size[index]
		var at: Vector2 = (_mote_at[index] - size * 0.5).round()
		_motes.draw_texture_rect_region(SPARK, Rect2(at, size),
			Rect2(SPARK_FRAME.x * float(frame), 0.0, SPARK_FRAME.x, SPARK_FRAME.y),
			Color(1.0, 1.0, 1.0, minf(glow * 1.6, 1.0)))


## Hold the shafts, the mist and the motes still, for a store capture that compares
## two frames.
func debug_settle() -> void:
	_age = 0.0
	set_process(false)
	_beams.modulate.a = 1.0
	_beams.position.x = 0.0
	_mist_far.autoscroll = Vector2.ZERO
	_mist_near.autoscroll = Vector2.ZERO


## One shaft is a soft, slanted strip that fades in from the canopy and thins out on
## the ground. Its profile is baked into a small texture, and each shaft is that
## texture sheared to lean away from the moon: one textured quad apiece, drawn once.
func _draw_shafts() -> void:
	var texture: ImageTexture = _shaft_texture()
	for shaft: Dictionary in _shafts:
		var length: float = float(shaft["length"])
		var width: float = float(shaft["width"])
		var tint: Color = _beam_tint
		tint.a *= float(shaft["alpha"])
		# Shear: the bottom edge sits `lean` pixels to the right of the top.
		_beams.draw_set_transform_matrix(Transform2D(
			Vector2(1.0, 0.0), Vector2(LEAN, 1.0), shaft["at"]))
		_beams.draw_texture_rect(texture, Rect2(-width * 0.5, 0.0, width, length), false, tint)
	_beams.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _shaft_texture() -> ImageTexture:
	if _shaft != null:
		return _shaft
	var pixels := PackedByteArray()
	pixels.resize(SHAFT_SIZE.x * SHAFT_SIZE.y * 4)
	for y in SHAFT_SIZE.y:
		var along: float = float(y) / float(SHAFT_SIZE.y - 1)
		# In from the canopy, full through the middle, thinner where it lands.
		var fade: float = smoothstep(0.0, 0.42, along) * (1.0 - 0.62 * smoothstep(0.55, 1.0, along))
		# Narrow at the canopy, wide on the ground.
		var half_width: float = 0.3 + 0.7 * along
		for x in SHAFT_SIZE.x:
			var across: float = absf(float(x) / float(SHAFT_SIZE.x - 1) * 2.0 - 1.0)
			var edge: float = 1.0 - smoothstep(0.0, 1.0, across / half_width)
			var index: int = (y * SHAFT_SIZE.x + x) * 4
			pixels[index] = 255
			pixels[index + 1] = 255
			pixels[index + 2] = 255
			pixels[index + 3] = int(clampf(edge * fade, 0.0, 1.0) * 255.0)
	_shaft = ImageTexture.create_from_image(
		Image.create_from_data(SHAFT_SIZE.x, SHAFT_SIZE.y, false, Image.FORMAT_RGBA8, pixels))
	return _shaft


static func _fog_texture() -> ImageTexture:
	if _fog != null:
		return _fog
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.014
	noise.fractal_octaves = 3
	noise.seed = 4471
	var height: PackedByteArray = noise.get_seamless_image(
		FOG_SIZE.x, FOG_SIZE.y, false, false, 0.1, true).get_data()
	var pixels := PackedByteArray()
	pixels.resize(FOG_SIZE.x * FOG_SIZE.y * 4)
	for index in FOG_SIZE.x * FOG_SIZE.y:
		# Only the upper part of the noise becomes fog, so the fog comes in banks with
		# clear air between them instead of a uniform haze that washes the night out.
		var density: float = smoothstep(0.46, 0.86, float(height[index]) / 255.0)
		pixels[index * 4] = 255
		pixels[index * 4 + 1] = 255
		pixels[index * 4 + 2] = 255
		pixels[index * 4 + 3] = int(density * 255.0)
	_fog = ImageTexture.create_from_image(
		Image.create_from_data(FOG_SIZE.x, FOG_SIZE.y, false, Image.FORMAT_RGBA8, pixels))
	return _fog
