extends Node2D

## Moonlight gate.
##
## It opens only after every beacon is lit. Until then it is fully hidden —
## a closed door on screen makes people wander, thinking they should go there.

## Fired when the player walks in.
signal entered

## Time it takes to open.
const OPEN_SECONDS: float = 1.2

## Destination caption geometry. It sits above the gate; `_process` nudges it
## the smallest distance that lands it fully inside the usable screen.
const LABEL_SIZE: Vector2 = Vector2(150, 39)
const LABEL_ABOVE: Vector2 = Vector2(-75, -95)
## Screen margin kept between the caption and the safe rect while nudging.
const LABEL_EDGE_MARGIN: float = 6.0
## Screen margin cleared around the hero before the caption may touch them.
const HERO_CLEAR_MARGIN: float = 6.0
## Extra pixel past that margin. The placed caption would otherwise merely
## touch the cleared rect, and float dust in the screen round-trip turns
## edge-touching into overlap.
const HERO_SEPARATION_PX: float = 1.0

const LABEL_FONT: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres"
)

@onready var _enter: Area2D = $Enter
@onready var _sprite: Sprite2D = $Sprite
@onready var _halo: Sprite2D = $Halo
@onready var _light: PointLight2D = $Light

## Built the first time this gate names a destination. A plain gate never has one.
var _label: Label = null

## The hero the caption keeps clear of, wired from the arena's gate-naming path.
var _player: Node2D = null

var _open: bool = false
var _fade: Tween = null
var _generation: int = 0


func _ready() -> void:
	modulate.a = 0.0
	visible = false
	# A plain gate has no caption to keep readable; naming one turns this on.
	set_process(false)
	# While closed, walking in must do nothing.
	_enter.monitoring = false
	_enter.body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	_keep_label_readable()


## Keep the destination caption inside the usable screen.
##
## A gate on the top rim puts the above-gate caption off-screen, and the
## compass hides exactly then because the gate itself is visible — the choice
## would be unreadable with no arrow either. So while the gate is on screen,
## nudge the caption the smallest distance that lands it fully inside the
## usable screen (the safe rect, below the top HUD the compass also avoids),
## and it stays with its gate. A gate off-screen keeps the plain above spot:
## the caption leaves with it and the compass carries the choice instead.
## Tap-through is untouched: the label never takes input.
func _keep_label_readable() -> void:
	if _label == null or not _label.visible:
		return
	var viewport: Viewport = get_viewport()
	if viewport == null or not is_inside_tree():
		return
	var safe: Rect2 = Screen.viewport_safe_rect(viewport)
	if not safe.has_area():
		safe = viewport.get_visible_rect()
	if not safe.has_area():
		return
	var xform: Transform2D = viewport.get_canvas_transform()
	var scale: float = maxf(xform.x.length(), xform.y.length())
	if scale <= 0.001:
		return
	if not safe.has_point(xform * global_position):
		_label.position = LABEL_ABOVE
		return
	var usable := Rect2(
		safe.position + Vector2(0.0, BeaconCompass.TOP_HUD_SAFE_Y),
		safe.size - Vector2(0.0, BeaconCompass.TOP_HUD_SAFE_Y))
	usable = usable.grow(-LABEL_EDGE_MARGIN)
	if usable.size.x <= _label.size.x * scale \
			or usable.size.y <= _label.size.y * scale:
		_label.position = LABEL_ABOVE
		return
	_label.position = LABEL_ABOVE
	var rect := Rect2(
		xform * (global_position + _label.position), _label.size * scale)
	var shift := Vector2.ZERO
	if rect.position.x < usable.position.x:
		shift.x = usable.position.x - rect.position.x
	elif rect.end.x > usable.end.x:
		shift.x = usable.end.x - rect.end.x
	if rect.position.y < usable.position.y:
		shift.y = usable.position.y - rect.position.y
	elif rect.end.y > usable.end.y:
		shift.y = usable.end.y - rect.end.y
	_label.position += shift / scale
	_clear_hero(xform, scale, usable)


## Move the caption to the nearest usable spot that clears the hero.
##
## The usable shift above can still land the caption on the hero standing
## beside a top-rim gate. When the caption would touch the hero's real sprite
## bounds (plus a small margin), move it to the nearest of the four
## axis-cleared spots that stays fully inside the usable screen. With no hero
## wired, or no valid spot, the usable-shifted caption stands.
func _clear_hero(xform: Transform2D, scale: float, usable: Rect2) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var sprite: AnimatedSprite2D = _player.get_node_or_null("Sprite") \
		as AnimatedSprite2D
	if sprite == null:
		return
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null or not frames.has_animation(sprite.animation):
		return
	if sprite.frame < 0 \
			or sprite.frame >= frames.get_frame_count(sprite.animation):
		return
	var texture: Texture2D = frames.get_frame_texture(
		sprite.animation, sprite.frame)
	if texture == null:
		return
	var unit: Vector2 = sprite.global_scale.abs()
	if unit.x <= 0.0 or unit.y <= 0.0:
		return
	var size: Vector2 = Vector2(texture.get_size()) * unit * scale
	var center: Vector2 = xform * sprite.to_global(sprite.offset)
	var grown: Rect2 = Rect2(center - size * 0.5, size).grow(
		HERO_CLEAR_MARGIN + HERO_SEPARATION_PX)
	var rect := Rect2(
		xform * (global_position + _label.position), _label.size * scale)
	if not rect.intersects(grown):
		return
	var spots: Array[Vector2] = [
		Vector2(grown.position.x - rect.size.x, rect.position.y),
		Vector2(grown.end.x, rect.position.y),
		Vector2(rect.position.x, grown.position.y - rect.size.y),
		Vector2(rect.position.x, grown.end.y),
	]
	var best: Vector2 = rect.position
	var best_distance: float = INF
	for spot in spots:
		if not usable.encloses(Rect2(spot, rect.size)):
			continue
		var distance: float = spot.distance_to(rect.position)
		if distance < best_distance:
			best_distance = distance
			best = spot
	if best_distance == INF:
		return
	_label.position = xform.affine_inverse() * best - global_position


func open() -> void:
	if _open:
		return
	_open = true
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_generation += 1
	var generation: int = _generation
	visible = true
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, OPEN_SECONDS)
	_fade.finished.connect(_finish_open.bind(generation))


func _finish_open(generation: int) -> void:
	if not is_inside_tree() or not _open or generation != _generation:
		return
	# Turn it on only after it is fully open. Brushing past mid-open would end the run for nothing.
	_enter.monitoring = true


## Watch this hero's sprite bounds when placing the caption. Wired from the
## arena's gate-naming path, next to the destination itself, so the caption
## a fork names also clears the player reading it.
func track_player(player: Node2D) -> void:
	_player = player


## Say where this gate leads. A fork has two, so each carries the place's name in its own colour,
## a second line for what waits there (an omen, or the guardian), and a third
## for the memory waiting in that place. An empty line is skipped, so a plain
## gate keeps its old two-line shape.
func set_destination(
		title: String, detail: String, accent: Color, clue: String = "") -> void:
	if _label == null:
		_label = Label.new()
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.size = LABEL_SIZE
		_label.position = LABEL_ABOVE
		_label.add_theme_font_override("font", LABEL_FONT)
		_label.add_theme_font_size_override("font_size", 9)
		_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.95))
		_label.add_theme_constant_override("outline_size", 4)
		add_child(_label)
	var lines: PackedStringArray = PackedStringArray([title])
	if not detail.is_empty():
		lines.append(detail)
	if not clue.is_empty():
		lines.append(clue)
	_label.text = "\n".join(lines)
	_label.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.25))
	_label.visible = true
	set_process(true)
	_sprite.modulate = accent.lerp(Color.WHITE, 0.45)
	_halo.modulate = accent
	_light.color = accent


## Put the gate back to a plain, unnamed one.
func clear_destination() -> void:
	set_process(false)
	if _label != null:
		_label.visible = false
	_sprite.modulate = Color.WHITE
	_halo.modulate = Color.WHITE
	_light.color = Color(0.62, 0.78, 1, 1)


## Close it fully so the same gate can be reused on the next terrain.
func close() -> void:
	_open = false
	_generation += 1
	_enter.set_deferred("monitoring", false)
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 0.0
	visible = false
	clear_destination()


func _on_body_entered(_body: Node2D) -> void:
	if not _open:
		return
	entered.emit()
