## Player preferences: locale plus music/sfx volume steps. An autoload so
## every panel reads and writes one holder. No class_name on purpose: the
## autoload singleton already owns the name.
extends Node

signal changed

const LOCALES: Array[String] = ["en", "ko"]
const MAX_STEP: int = 10
const MUTE_DB: float = -80.0
const SAVE_PATH: String = "user://settings.cfg"
const SECTION: String = "settings"

var locale: String = "en"
var music_step: int = 8
var sfx_step: int = 8


func _ready() -> void:
	_ensure_buses()
	load_all()
	_apply()


func step_to_db(step: int) -> float:
	if step <= 0:
		return MUTE_DB
	return linear_to_db(float(step) / float(MAX_STEP))


func set_locale(value: String) -> void:
	if not LOCALES.has(value):
		return
	locale = value
	_save_and_apply()


func set_music_step(value: int) -> void:
	music_step = clampi(value, 0, MAX_STEP)
	_save_and_apply()


func set_sfx_step(value: int) -> void:
	sfx_step = clampi(value, 0, MAX_STEP)
	_save_and_apply()


func load_all() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var saved_locale: String = String(cfg.get_value(SECTION, "locale", locale))
	if LOCALES.has(saved_locale):
		locale = saved_locale
	music_step = clampi(int(cfg.get_value(SECTION, "music_step", music_step)), 0, MAX_STEP)
	sfx_step = clampi(int(cfg.get_value(SECTION, "sfx_step", sfx_step)), 0, MAX_STEP)


func _save_and_apply() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "locale", locale)
	cfg.set_value(SECTION, "music_step", music_step)
	cfg.set_value(SECTION, "sfx_step", sfx_step)
	if cfg.save(SAVE_PATH) != OK:
		push_error("settings cannot save " + SAVE_PATH)
	_apply()


func _apply() -> void:
	TranslationServer.set_locale(locale)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), step_to_db(music_step))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Sfx"), step_to_db(sfx_step))
	changed.emit()


func _ensure_buses() -> void:
	for bus in ["Music", "Sfx"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
