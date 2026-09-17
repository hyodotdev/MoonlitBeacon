extends RefCounted

## Read and validate the external links store review and purchase support need.
##
## Real URLs live in two `project.godot` settings. Values with a bad scheme or
## whitespace never go to the browser.

const PRIVACY_SETTING: String = "application/config/privacy_policy_url"
const SUPPORT_SETTING: String = "application/config/support_contact"
const LOCALE_PLACEHOLDER: String = "{locale}"


static func privacy_policy_url() -> String:
	return localized_https_url(
		_setting_text(PRIVACY_SETTING), TranslationServer.get_locale())


static func support_url() -> String:
	var configured: String = _setting_text(SUPPORT_SETTING)
	if configured.contains(LOCALE_PLACEHOLDER):
		return localized_https_url(configured, TranslationServer.get_locale())
	return normalize_support_contact(configured)


## Open the support site's public path in the app language.
##
## Godot's Chinese locales (`zh_CN`, `zh_TW`) and the site's BCP 47 paths
## (`zh-Hans`, `zh-Hant`) are mapped only at this boundary. Unknown locales
## go to English, matching the site's x-default.
static func localized_https_url(raw_value: String, locale: String) -> String:
	var expanded: String = raw_value.replace(
		LOCALE_PLACEHOLDER, site_locale(locale))
	return normalize_privacy_url(expanded)


static func site_locale(locale: String) -> String:
	var normalized: String = locale.strip_edges().replace("-", "_").to_lower()
	if normalized.begins_with("ko"):
		return "ko"
	if normalized.begins_with("ja"):
		return "ja"
	if (
		normalized.begins_with("zh_tw")
		or normalized.begins_with("zh_hk")
		or normalized.begins_with("zh_mo")
		or normalized.contains("hant")
	):
		return "zh-Hant"
	if normalized.begins_with("zh"):
		return "zh-Hans"
	return "en"


static func normalize_privacy_url(raw_value: String) -> String:
	var value: String = raw_value.strip_edges()
	if not _is_safe_https(value):
		return ""
	return value


## Support accepts an HTTPS page or an email address.
##
## A bare email gets `mailto:` prefixed. While the address is unset, an empty
## string hides the button on the settings screen.
static func normalize_support_contact(raw_value: String) -> String:
	var value: String = raw_value.strip_edges()
	if _is_safe_https(value):
		return value
	if value.to_lower().begins_with("mailto:"):
		value = value.substr("mailto:".length())
	if not _is_safe_email(value):
		return ""
	return "mailto:" + value


static func open_external_url(url: String) -> Error:
	var expanded: String = url
	if expanded.contains(LOCALE_PLACEHOLDER):
		expanded = expanded.replace(
			LOCALE_PLACEHOLDER, site_locale(TranslationServer.get_locale()))
	var safe_url: String = normalize_support_contact(expanded)
	if safe_url.is_empty():
		return ERR_INVALID_PARAMETER
	return OS.shell_open(safe_url)


static func _setting_text(key: String) -> String:
	var value: Variant = ProjectSettings.get_setting(key, "")
	return "" if value == null else str(value)


static func _is_safe_https(value: String) -> bool:
	if not value.to_lower().begins_with("https://") or _has_unsafe_characters(value):
		return false
	var remainder: String = value.substr("https://".length())
	var authority_end: int = remainder.length()
	for separator in ["/", "?", "#"]:
		var found: int = remainder.find(separator)
		if found >= 0:
			authority_end = mini(authority_end, found)
	var authority: String = remainder.substr(0, authority_end)
	return (
		not authority.is_empty()
		and not authority.contains("@")
		and not authority.begins_with(".")
		and not authority.ends_with(".")
	)


static func _is_safe_email(value: String) -> bool:
	if value.count("@") != 1 or _has_unsafe_characters(value):
		return false
	for forbidden in ["/", "\\", "?", "#", "&", ":"]:
		if value.contains(forbidden):
			return false
	var local_part: String = value.get_slice("@", 0)
	var domain: String = value.get_slice("@", 1)
	return (
		not local_part.is_empty()
		and not domain.is_empty()
		and not local_part.begins_with(".")
		and not local_part.ends_with(".")
		and not domain.begins_with(".")
		and not domain.ends_with(".")
	)


static func _has_unsafe_characters(value: String) -> bool:
	for character in [" ", "\t", "\r", "\n", "{", "}"]:
		if value.contains(character):
			return true
	return false
