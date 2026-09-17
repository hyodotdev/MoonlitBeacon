extends SceneTree

## Ask the engine whether translations were actually imported and loaded.
##
## `.translation` is not in git. It is produced by importing
## `localization/moonlit.csv`. If that import is skipped, the game still
## **quietly** launches with neither language loaded. The screen shows keys
## like `RESULT_WIN` as-is.
##
## Autoloads are missing in `--script` mode. This only looks at
## `TranslationServer`.

const EXPECTED: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const SETTINGS_SCRIPT: Script = preload("res://scripts/gameplay/settings.gd")
const UI_FONT: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Multilingual.tres"
)
const UI_FONT_BOLD: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres"
)
## Body face. The 2026-08 refresh swapped the pixel font (Galmuri) for
## Maplestory. This check asks "does every fixed UI glyph draw?", so the
## rule stays the same if the face changes — this font covers Korean and
## English, Noto covers Japanese and Chinese.
const BODY_REGULAR: FontFile = preload(
	"res://assets/third_party/fonts/MaplestoryLight.ttf"
)
const BODY_BOLD: FontFile = preload(
	"res://assets/third_party/fonts/MaplestoryBold.ttf"
)
const NOTO_CJK: FontFile = preload(
	"res://assets/third_party/fonts/NotoSansCJKsc-Regular.otf"
)

## One representative key that must exist in every language. Full table
## compare is `check-locale.mjs`.
const PROBE: String = "RESULT_WIN"


func _init() -> void:
	var loaded: PackedStringArray = TranslationServer.get_loaded_locales()
	var failed: int = 0
	if UI_FONT.get_fallbacks().is_empty() or UI_FONT_BOLD.get_fallbacks().is_empty():
		printerr("  bundled CJK fallback is not wired on the multilingual UI fonts")
		failed += 1
	var settings_locales: Array = SETTINGS_SCRIPT.get_script_constant_map().get("LOCALES", [])
	if settings_locales != EXPECTED:
		printerr("  Settings.LOCALES does not match translation columns: ", settings_locales)
		failed += 1

	var locale_cases: Array[Array] = [
		["ko_KR", "ko", "ko"],
		["en_US", "en", "en"],
		["ja_JP", "ja", "ja"],
		["ja_JP", "ja-JP", "ja"],
		["zh_CN", "zh", "zh_CN"],
		["zh_Hans_CN", "zh", "zh_CN"],
		["zh_Hans_CN", "zh-Hans", "zh_CN"],
		["zh_TW", "zh", "zh_TW"],
		["zh_Hant_TW", "zh", "zh_TW"],
		["zh_Hant_TW", "zh-Hant", "zh_TW"],
		["zh_HK", "zh", "zh_TW"],
		["fr_FR", "fr", "en"],
	]
	for locale_case: Array in locale_cases:
		var actual: String = SETTINGS_SCRIPT.locale_for_system(
			str(locale_case[0]),
			str(locale_case[1]),
		)
		if actual != str(locale_case[2]):
			printerr("  device locale normalize failed: ", locale_case, " → ", actual)
			failed += 1

	for locale in EXPECTED:
		if locale not in loaded:
			printerr("  ", locale, " translation was not loaded")
			failed += 1
			continue
		TranslationServer.set_locale(locale)
		var text: String = tr(PROBE)
		if text == PROBE:
			printerr("  ", locale, ": ", PROBE, " is not translated")
			failed += 1
		else:
			print("  ", locale, ": ", PROBE, " → ", text)
	failed += _check_bundled_font_glyphs()

	if failed > 0:
		printerr("translation load failed — ", failed, " case(s)")
		quit(1)
		return
	print("translation load confirmed — ", loaded)
	quit()


## Read the real CSV translations and confirm body and bold font pairs have
## every character.
##
## Compressed `.translation` files do not return a key list, so the source
## CSV is read. Both pairs disable system-font fallback so a lucky device
## font cannot pass the check.
func _check_bundled_font_glyphs() -> int:
	var csv: FileAccess = FileAccess.open("res://localization/moonlit.csv", FileAccess.READ)
	if csv == null:
		printerr("  could not open the translation CSV for glyph checks")
		return 1
	var header: PackedStringArray = csv.get_csv_line()
	var failed: int = 0
	while csv.get_position() < csv.get_length():
		var row: PackedStringArray = csv.get_csv_line()
		if row.size() != header.size():
			continue
		for column: int in range(1, row.size()):
			var message: String = row[column]
			for index: int in message.length():
				var codepoint: int = message.unicode_at(index)
				var regular_has: bool = (
					BODY_REGULAR.has_char(codepoint) or NOTO_CJK.has_char(codepoint)
				)
				var bold_has: bool = (
					BODY_BOLD.has_char(codepoint) or NOTO_CJK.has_char(codepoint)
				)
				if regular_has and bold_has:
					continue
				printerr(
					"  ",
					header[column],
					": ",
					row[0],
					" glyph missing from bundled fonts: U+",
					"%04X" % codepoint,
				)
				failed += 1
	return failed
