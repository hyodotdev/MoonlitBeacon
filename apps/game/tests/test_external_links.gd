extends Node

## Settings privacy-policy and support link contract.

const EXTERNAL_LINKS: Script = preload("res://scripts/ui/external_links.gd")
const SETTINGS_PANEL: PackedScene = preload("res://scenes/ui/settings_panel.tscn")

var _failed: int = 0
var _checked: int = 0
var _original_privacy: Variant
var _original_support: Variant


func _ready() -> void:
	_original_privacy = ProjectSettings.get_setting(EXTERNAL_LINKS.PRIVACY_SETTING, "")
	_original_support = ProjectSettings.get_setting(EXTERNAL_LINKS.SUPPORT_SETTING, "")
	_test_normalization()
	_test_empty_configuration()
	_test_configured_buttons()
	_test_invalid_configuration()
	_restore_settings()

	if _failed > 0:
		printerr("external-link test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("external-link test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _test_normalization() -> void:
	_expect_equal(
		EXTERNAL_LINKS.normalize_privacy_url("https://example.com/privacy"),
		"https://example.com/privacy",
		"allows HTTPS privacy policy")
	_expect_equal(
		EXTERNAL_LINKS.normalize_privacy_url("http://example.com/privacy"),
		"",
		"rejects unencrypted privacy policy")
	_expect_equal(
		EXTERNAL_LINKS.normalize_privacy_url("javascript:alert(1)"),
		"",
		"rejects arbitrary schemes")
	_expect_equal(
		EXTERNAL_LINKS.normalize_privacy_url(
			"https://example.com/{locale}/privacy"),
		"",
		"rejects unsubstituted locale templates")
	_expect_equal(
		EXTERNAL_LINKS.localized_https_url(
			"https://example.com/{locale}/privacy", "ko_KR"),
		"https://example.com/ko/privacy",
		"Korean support path")
	_expect_equal(
		EXTERNAL_LINKS.localized_https_url(
			"https://example.com/{locale}/privacy", "ja-JP"),
		"https://example.com/ja/privacy",
		"Japanese support path")
	_expect_equal(
		EXTERNAL_LINKS.localized_https_url(
			"https://example.com/{locale}/privacy", "zh_CN"),
		"https://example.com/zh-Hans/privacy",
		"Simplified Chinese support path")
	_expect_equal(
		EXTERNAL_LINKS.localized_https_url(
			"https://example.com/{locale}/privacy", "zh-TW"),
		"https://example.com/zh-Hant/privacy",
		"Traditional Chinese support path")
	_expect_equal(
		EXTERNAL_LINKS.localized_https_url(
			"https://example.com/{locale}/privacy", "fr_FR"),
		"https://example.com/en/privacy",
		"unsupported languages use English x-default path")
	_expect_equal(
		EXTERNAL_LINKS.normalize_support_contact("support@example.com"),
		"mailto:support@example.com",
		"converts support email to mailto link")
	_expect_equal(
		EXTERNAL_LINKS.normalize_support_contact("mailto:help@example.com"),
		"mailto:help@example.com",
		"allows explicit mailto support")
	_expect_equal(
		EXTERNAL_LINKS.normalize_support_contact("https://example.com/support"),
		"https://example.com/support",
		"allows HTTPS support page")
	_expect_equal(
		EXTERNAL_LINKS.normalize_support_contact("mailto:help@example.com?subject=x"),
		"",
		"rejects support values mixed with mail headers")
	_expect_equal(
		EXTERNAL_LINKS.open_external_url("javascript:alert(1)"),
		ERR_INVALID_PARAMETER,
		"does not pass unverified addresses to the OS")
	_expect_equal(
		EXTERNAL_LINKS.open_external_url(
			"https://example.com/{unknown}/privacy"),
		ERR_INVALID_PARAMETER,
		"does not pass unknown URL templates to the OS")


func _test_empty_configuration() -> void:
	ProjectSettings.set_setting(EXTERNAL_LINKS.PRIVACY_SETTING, "")
	ProjectSettings.set_setting(EXTERNAL_LINKS.SUPPORT_SETTING, "")
	var panel: Control = _new_panel()
	_expect_false(panel.get_node("ExternalLinks").visible, "hides unconfigured link row")
	_expect_false(panel.get_node("ExternalLinks/Privacy").visible, "hides unconfigured privacy button")
	_expect_false(panel.get_node("ExternalLinks/Support").visible, "hides unconfigured support button")
	panel.free()


func _test_configured_buttons() -> void:
	var original_locale: String = TranslationServer.get_locale()
	ProjectSettings.set_setting(
		EXTERNAL_LINKS.PRIVACY_SETTING,
		"https://example.com/{locale}/privacy")
	ProjectSettings.set_setting(
		EXTERNAL_LINKS.SUPPORT_SETTING,
		"https://example.com/{locale}/support")
	TranslationServer.set_locale("en")
	var panel: Control = _new_panel()
	var privacy: Button = panel.get_node("ExternalLinks/Privacy") as Button
	var support: Button = panel.get_node("ExternalLinks/Support") as Button
	_expect_true(panel.get_node("ExternalLinks").visible, "shows configured link row")
	_expect_true(privacy.visible, "shows configured privacy button")
	_expect_true(support.visible, "shows configured support button")
	_expect_true(privacy.custom_minimum_size.y >= 36.0, "privacy button tap height")
	_expect_true(support.custom_minimum_size.y >= 36.0, "support button tap height")
	_expect_equal(
		panel.get("_privacy_url"),
		"https://example.com/en/privacy",
		"uses current locale links when opening the panel")
	TranslationServer.set_locale("ja")
	Settings.changed.emit()
	_expect_equal(
		panel.get("_privacy_url"),
		"https://example.com/ja/privacy",
		"refreshes privacy link when language changes on an open panel")
	_expect_equal(
		panel.get("_support_url"),
		"https://example.com/ja/support",
		"refreshes support link when language changes on an open panel")
	panel.free()
	TranslationServer.set_locale(original_locale)


func _test_invalid_configuration() -> void:
	ProjectSettings.set_setting(EXTERNAL_LINKS.PRIVACY_SETTING, "javascript:alert(1)")
	ProjectSettings.set_setting(EXTERNAL_LINKS.SUPPORT_SETTING, "not an email")
	var panel: Control = _new_panel()
	_expect_false(panel.get_node("ExternalLinks").visible, "hides invalid link row")
	_expect_false(panel.get_node("ExternalLinks/Privacy").visible, "hides invalid privacy button")
	_expect_false(panel.get_node("ExternalLinks/Support").visible, "hides invalid support button")
	panel.free()


func _new_panel() -> Control:
	var panel: Control = SETTINGS_PANEL.instantiate() as Control
	add_child(panel)
	return panel


func _restore_settings() -> void:
	ProjectSettings.set_setting(EXTERNAL_LINKS.PRIVACY_SETTING, _original_privacy)
	ProjectSettings.set_setting(EXTERNAL_LINKS.SUPPORT_SETTING, _original_support)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _expect_false(value: bool, label: String) -> void:
	_expect_equal(value, false, label)
