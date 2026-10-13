## Owns the arena stage: centering, ignition, brightness, stick input, the run.
extends Node2D

const BRIGHTEN_SECONDS: float = 1.2
const UNLIT_FOREST: Color = Color(0.315, 0.35, 0.57)
const MAX_HEALTH: int = 3
const TIME_LIMIT: float = 90.0
const SPAWN_INTERVAL: float = 4.0
const MAX_SPIRITS: int = 4
const GUARDIAN_THEME: String = "res://assets/third_party/ninja_adventure/audio/music/guardian_theme.ogg"
const SPIRIT_SCENE: PackedScene = preload("res://scenes/spirit.tscn")
const DRIFTER: SpiritKind = preload("res://resources/kinds/drifter.tres")
const NIGHT_BAT: SpiritKind = preload("res://resources/kinds/night_bat.tres")
const EMBER: SpiritKind = preload("res://resources/kinds/ember.tres")
const GUARDIAN: SpiritKind = preload("res://resources/kinds/guardian.tres")
const SPAWN_POINTS: Array[Vector2] = [
	Vector2(120, 170), Vector2(690, 170), Vector2(120, 310), Vector2(690, 310),
]
const GATE_BOUNDS_MARGIN: float = 24.0
const GATE_BOUNDS_HEIGHT: float = 18.0

@onready var _forest: Node2D = $NightForest
@onready var _player: CharacterBody2D = $Player
@onready var _stick: Control = $Ui/MoveStick
@onready var _dash_stick: Control = $Ui/DashStick
@onready var _spirit: CharacterBody2D = $Spirit
@onready var _flash: ColorRect = $Ui/HitFlash
@onready var _music: AudioStreamPlayer = $Music
@onready var _gate: Node2D = $Gate
@onready var _result: Control = $Ui/ResultPanel
@onready var _hud: Control = $Ui/Hud
@onready var _pause_button: Button = $Ui/PauseButton
@onready var _pause_panel: Control = $Ui/PausePanel
@onready var _settings_panel: Control = $Ui/SettingsPanel

var _beacons: Array = []
var _lit_count: int = 0
var _brighten: Tween
var _spirits: Array = []
var _guardian_out: bool = false
var _health: int = MAX_HEALTH
var _time_left: float = TIME_LIMIT
var _over: bool = false
var _won: bool = false


func _ready() -> void:
	_apply_centering()
	get_tree().root.size_changed.connect(_apply_centering)
	get_tree().set_auto_accept_quit(false)
	get_tree().root.close_requested.connect(_quit_gracefully)
	_beacons = [$BeaconWest, $BeaconNorth, $BeaconEast]
	for beacon in _beacons:
		beacon.lit_changed.connect(_on_beacon_lit_changed)
		beacon.charge_changed.connect(_on_beacon_charge_changed)
	_spirit.set_target(_player)
	_spirit.touched_player.connect(_on_spirit_touched_player)
	_spirits = [_spirit]
	var spawner: Timer = Timer.new()
	spawner.name = "Spawner"
	spawner.wait_time = SPAWN_INTERVAL
	spawner.timeout.connect(_on_spawn_timeout)
	add_child(spawner)
	spawner.start()
	_gate.entered.connect(_on_gate_entered)
	_result.restart_requested.connect(_restart)
	_pause_button.pressed.connect(request_pause)
	_dash_stick.flicked.connect(_on_dash_flicked)
	_pause_panel.resume_requested.connect(resume_play)
	_pause_panel.settings_requested.connect(_settings_panel.open)
	_update_brightness(false)
	_hud.set_health(_health)
	_hud.set_beacons(0, _beacons.size())
	_hud.set_time_left(_time_left)
	AudioFlush.loop_stream(_music)


func get_time_left() -> float:
	return _time_left


func _process(delta: float) -> void:
	if _over:
		_player.set_move_input(Vector2.ZERO)
		return
	_player.set_move_input(_stick.get_value())
	_hud.set_dash_ready(_player.is_dash_ready())
	_time_left -= delta
	_hud.set_time_left(_time_left)
	if _time_left <= 0.0:
		_finish(false)


func _physics_process(_delta: float) -> void:
	if _over:
		return
	_prune_spirits()
	for spirit in _spirits:
		spirit.poll_hits()


func get_health() -> int:
	return _health


func is_over() -> bool:
	return _over


func did_win() -> bool:
	return _won


func request_pause() -> void:
	if _over or get_tree().paused:
		return
	_stick.reset()
	_pause_panel.open()
	get_tree().paused = true


func resume_play() -> void:
	if not get_tree().paused:
		return
	get_tree().paused = false
	_pause_panel.close()


func _notification(what: int) -> void:
	## The OS backgrounds the app mid-run: halt before the player returns
	## to a lost run they never saw end.
	if what == NOTIFICATION_APPLICATION_PAUSED and not _over:
		request_pause()


func release_audio() -> void:
	## Call before leaving the arena (restart, quit to title) so the exit
	## finds silence and pays no mix-wait. Process quits skip this call and
	## pay one wait in _exit_tree instead.
	for beacon in _beacons:
		beacon.stop_audio()
	AudioFlush.stop_player(_music)


func _exit_tree() -> void:
	var active: bool = AudioFlush.is_playing(_music)
	for beacon in _beacons:
		active = beacon.is_audio_playing() or active
	release_audio()
	if active:
		AudioFlush.wait_for_mix()


func _apply_centering() -> void:
	position = Screen.center_offset(get_viewport_rect().size)


func _on_beacon_lit_changed(_beacon: Node2D, lit: bool) -> void:
	if _over:
		return
	_lit_count = clampi(_lit_count + (1 if lit else -1), 0, _beacons.size())
	_update_brightness(true)
	_hud.set_beacons(_lit_count, _beacons.size())
	if lit and _lit_count >= _beacons.size() and not _over:
		_gate.open()
		_spawn_guardian()
		## merge() is a bounding rectangle, not a narrow path: the new
		## bounds span the whole union of the old box and the gate box.
		_player.set_bounds(_player.bounds.merge(Rect2(
			_gate.position - Vector2(GATE_BOUNDS_MARGIN, 0.0),
			Vector2(GATE_BOUNDS_MARGIN * 2.0, GATE_BOUNDS_HEIGHT)
		)))


func _update_brightness(animated: bool) -> void:
	var target: Color = UNLIT_FOREST.lerp(Color.WHITE, float(_lit_count) / float(_beacons.size()))
	if _brighten and _brighten.is_valid():
		_brighten.kill()
	if not animated:
		_forest.modulate = target
		return
	_brighten = create_tween()
	_brighten.tween_property(_forest, "modulate", target, BRIGHTEN_SECONDS)


func _on_beacon_charge_changed(_beacon: Node2D, _ratio: float) -> void:
	var top: float = 0.0
	for beacon in _beacons:
		top = maxf(top, beacon.get_charge())
	_player.set_charge(top)


func _on_dash_flicked(direction: Vector2) -> void:
	if not _over:
		_player.dash(direction)


func _on_spirit_touched_player() -> void:
	_flash.modulate.a = 0.45
	var fade: Tween = create_tween()
	fade.tween_property(_flash, "modulate:a", 0.0, 0.25)
	if _over:
		return
	_health -= 1
	_hud.set_health(_health)
	if _health <= 0:
		_finish(false)


func _on_gate_entered() -> void:
	if _over:
		return
	_finish(true)


func _finish(won: bool) -> void:
	_over = true
	_won = won
	_player.freeze()
	for spirit in _spirits:
		if won:
			spirit.retreat()
		else:
			spirit.set_target(null)
	for beacon in _beacons:
		beacon.freeze()
	_gate.disarm()
	var score: Score = Score.build(_lit_count, _beacons.size(), _time_left, won)
	Records.save_best(score.total())
	_result.show_result(score)


func _kind_for_progress() -> SpiritKind:
	match _lit_count:
		0:
			return DRIFTER
		1:
			return NIGHT_BAT
		_:
			return EMBER


func _on_spawn_timeout() -> void:
	if _over or _guardian_out:
		return
	_prune_spirits()
	if _spirits.size() >= MAX_SPIRITS:
		return
	_spawn_spirit(_kind_for_progress())


func _spawn_spirit(kind: SpiritKind) -> CharacterBody2D:
	var spirit: CharacterBody2D = SPIRIT_SCENE.instantiate()
	spirit.kind = kind
	spirit.position = _farthest_spawn()
	add_child(spirit)
	spirit.set_target(_player)
	spirit.touched_player.connect(_on_spirit_touched_player)
	spirit.materialize()
	_spirits.append(spirit)
	return spirit


func _spawn_guardian() -> void:
	_guardian_out = true
	for spirit in _spirits:
		if is_instance_valid(spirit):
			spirit.retreat()
	_spirits.clear()
	_swap_music(GUARDIAN_THEME)
	_spawn_spirit(GUARDIAN)


func _swap_music(path: String) -> void:
	AudioFlush.stop_player(_music)
	_music.stream = load(path)
	AudioFlush.loop_stream(_music)
	_music.play()


func _farthest_spawn() -> Vector2:
	var best: Vector2 = SPAWN_POINTS[0]
	for point in SPAWN_POINTS:
		if _player.position.distance_to(point) > _player.position.distance_to(best):
			best = point
	return best


func _prune_spirits() -> void:
	_spirits = _spirits.filter(func(entry: Variant) -> bool: return is_instance_valid(entry))


func _restart() -> void:
	release_audio()
	get_tree().reload_current_scene()


func _quit_gracefully() -> void:
	## The player closed the window: release our own audio while the loop
	## still runs, let the mix drain, then quit. Quitting with voices
	## playing leaks under the headless driver.
	release_audio()
	AudioFlush.wait_for_mix()
	get_tree().quit()
