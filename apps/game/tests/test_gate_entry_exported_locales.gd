extends SceneTree

## Gate entry translations ship as imported resources, not as source CSV.
##
## The native export packs the imported `.translation` resources; the source
## CSV never leaves the desktop. This suite therefore never opens the CSV:
## it loads each locale's Translation resource, enumerates the shipped keys
## from the English table, and proves every key resolves in every locale
## through both the draw-time path and `GateEntryStrings.text()`, with the
## English fallback intact and loading idempotent.

const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const PATH_TEMPLATE: String = "res://localization/gate_entry.%s.translation"

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	var original_locale: String = TranslationServer.get_locale()
	var tables: Dictionary = _load_tables()
	if _failed == 0:
		_check_key_sets(tables)
	if _failed == 0:
		_check_loader(tables)
	if _failed == 0:
		_check_resolution(tables)
	TranslationServer.set_locale(original_locale)
	if _failed > 0:
		printerr("gate-entry-exported-locales test failed — ",
			_failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("gate-entry-exported-locales test passed — ", _checked, " case(s)")
	quit()


## Every locale's imported resource exists and loads. A missing import
## output fails here, exactly as it would fail to ship.
func _load_tables() -> Dictionary:
	var tables: Dictionary = {}
	for locale in LOCALES:
		var path: String = PATH_TEMPLATE % locale
		_expect_true(ResourceLoader.exists(path),
			"resource ships: " + path)
		var table: Translation = load(path) as Translation
		_expect_true(table != null, "resource loads: " + path)
		if table != null:
			tables[locale] = table
	return tables


## All five resources carry the same non-empty key set: no locale is
## missing a key the English table ships.
func _check_key_sets(tables: Dictionary) -> void:
	var english: Translation = tables.get("en")
	var keys: PackedStringArray = english.get_message_list()
	_expect_true(keys.size() > 0, "english table ships keys")
	for locale in LOCALES:
		var table: Translation = tables[locale]
		_expect_true(table.get_message_list().size() == keys.size(),
			"%s ships every key (%d)" % [locale, keys.size()])
		for key in keys:
			_expect_true(not table.get_message(key).is_empty(),
				"%s translates %s" % [locale, key])


## The loader reports the shipped table exactly once, however often it runs.
func _check_loader(tables: Dictionary) -> void:
	var english: Translation = tables.get("en")
	GateEntryStrings.ensure_loaded()
	_expect_true(GateEntryStrings.is_loaded(), "loader reports loaded")
	_expect_true(GateEntryStrings.key_count() == english.get_message_count(),
		"loader counts the shipped keys")
	GateEntryStrings.ensure_loaded()
	_expect_true(GateEntryStrings.key_count() == english.get_message_count(),
		"second load changes nothing")


## Every shipped key resolves in every locale through the draw-time path
## and through the loader's text call, which must agree while the table
## ships. The current locale is restored by the caller.
func _check_resolution(tables: Dictionary) -> void:
	var english: Translation = tables.get("en")
	var keys: PackedStringArray = english.get_message_list()
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		for key in keys:
			var drawn: String = tr(key)
			_expect_true(drawn != key,
				"%s draws %s" % [locale, key])
			var loaded: String = GateEntryStrings.text(key)
			_expect_true(loaded == drawn,
				"%s loader matches the draw (%s)" % [locale, key])
			_expect_true(not loaded.is_empty() and loaded != key,
				"%s falls back past the key (%s)" % [locale, key])


func _expect_true(value: bool, message: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("  FAIL ", message)
