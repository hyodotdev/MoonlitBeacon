## Settings and credits in one shared card: locale, volume steps, sources.
extends Control

@onready var _title: Label = $Panel/Title
@onready var _language_label: Label = $Panel/LanguageLabel
@onready var _lang_en: Button = $Panel/LangEn
@onready var _lang_ko: Button = $Panel/LangKo
@onready var _music_label: Label = $Panel/MusicLabel
@onready var _music_down: Button = $Panel/MusicDown
@onready var _music_value: Label = $Panel/MusicValue
@onready var _music_up: Button = $Panel/MusicUp
@onready var _sfx_label: Label = $Panel/SfxLabel
@onready var _sfx_down: Button = $Panel/SfxDown
@onready var _sfx_value: Label = $Panel/SfxValue
@onready var _sfx_up: Button = $Panel/SfxUp
@onready var _credits_title: Label = $Panel/CreditsTitle
@onready var _credits_body: Label = $Panel/CreditsBody
@onready var _close: Button = $Panel/Close


func _ready() -> void:
	_lang_en.pressed.connect(_on_lang_pressed.bind("en"))
	_lang_ko.pressed.connect(_on_lang_pressed.bind("ko"))
	_music_down.pressed.connect(_on_music_step.bind(-1))
	_music_up.pressed.connect(_on_music_step.bind(1))
	_sfx_down.pressed.connect(_on_sfx_step.bind(-1))
	_sfx_up.pressed.connect(_on_sfx_step.bind(1))
	_close.pressed.connect(close)
	Settings.changed.connect(_redraw)
	_redraw()


func open() -> void:
	visible = true
	_redraw()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _redraw() -> void:
	_title.text = tr("SETTINGS")
	_language_label.text = tr("LANGUAGE_LABEL")
	_lang_en.disabled = Settings.locale == "en"
	_lang_ko.disabled = Settings.locale == "ko"
	_music_label.text = tr("MUSIC_LABEL")
	_music_value.text = str(Settings.music_step)
	_sfx_label.text = tr("SFX_LABEL")
	_sfx_value.text = str(Settings.sfx_step)
	_credits_title.text = tr("CREDITS")
	_credits_body.text = tr("CREDITS_BODY")
	_close.text = tr("CLOSE")


func _on_lang_pressed(locale: String) -> void:
	Settings.set_locale(locale)


func _on_music_step(delta: int) -> void:
	Settings.set_music_step(Settings.music_step + delta)


func _on_sfx_step(delta: int) -> void:
	Settings.set_sfx_step(Settings.sfx_step + delta)
