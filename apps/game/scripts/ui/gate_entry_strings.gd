class_name GateEntryStrings
extends RefCounted

## Runtime loader for the moon gate entry locale table.
##
## The entry surface keeps its own keys in `res://localization/gate_entry.csv`;
## the editor imports that table into one Translation resource per locale and
## `project.godot` registers them, so the engine ships and loads them at
## startup on desktop and in exports alike. The keys use a lowercase `gate.*`
## namespace on purpose: the repo's static locale check governs
## SCREAMING_SNAKE literals against the shared table, and these keys resolve
## through this loader instead, so the two tables never collide.
##
## Call `ensure_loaded()` once before showing entry UI. Every entry module
## calls it in `_ready()`, so the host normally does nothing. `text()` never
## returns a raw key while the table ships: it falls back to the English cell.

const TRANSLATION_PATH: String = \
	"res://localization/gate_entry.%s.translation"
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const ENGLISH_LOCALE: String = "en"

static var _loaded: bool = false
static var _english: Dictionary = {}


## Load the imported Translation resources once and hand them to the
## TranslationServer when the engine has not already done so.
## Safe to call twice; the second call does nothing.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var tables: Dictionary = {}
	for locale in LOCALES:
		var path: String = TRANSLATION_PATH % locale
		if not ResourceLoader.exists(path):
			continue
		var table: Translation = load(path) as Translation
		if table != null:
			tables[locale] = table
	if not tables.has(ENGLISH_LOCALE):
		return
	var english: Translation = tables[ENGLISH_LOCALE]
	for key in english.get_message_list():
		_english[key] = english.get_message(key)
	if _english.is_empty():
		return
	if _server_has_gate_table(str(_english.keys()[0])):
		return
	for locale in LOCALES:
		if tables.has(locale):
			TranslationServer.add_translation(tables[locale])


## Best text for a key: current locale, else the English cell, else the key.
## The last branch only runs when the table itself is missing.
static func text(key: String) -> String:
	ensure_loaded()
	var translated: String = TranslationServer.translate(key)
	if translated != key:
		return translated
	return str(_english.get(key, key))


## How many keys the table supplied. Tests use this to prove the table loaded.
static func key_count() -> int:
	ensure_loaded()
	return _english.size()


static func is_loaded() -> bool:
	return _loaded


## True when every locale already resolves the table through the server, so
## this loader must not add its copies a second time. Any shipped key probes
## the whole table: a locale either has the resource or it has nothing. The
## current locale is restored before returning.
static func _server_has_gate_table(probe_key: String) -> bool:
	var current: String = TranslationServer.get_locale()
	var complete: bool = true
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		if TranslationServer.translate(probe_key) == probe_key:
			complete = false
			break
	TranslationServer.set_locale(current)
	return complete
