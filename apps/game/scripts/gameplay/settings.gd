extends Node

## Settings. Remembers language and volume.
##
## Same autoload slot as Chapter 14's `Records`, but **a separate file.**
## Records are play results; settings are taste. Wiping one must leave the other.
##
## Two autoloads that each do one thing beat one autoload that does two.
signal changed

const SAVE_PATH: String = "user://settings.cfg"
const TEMP_SAVE_PATH: String = "user://settings.cfg.tmp"
const ANALYTICS_REVOKED_PATH: String = "user://analytics_consent.revoked"
const SECTION: String = "settings"

## Languages that can be picked. Must match column names in `localization/moonlit.csv`.
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]

## Volume steps. 0 is mute.
const MAX_STEP: int = 5

## Value used at step 0. `linear_to_db(0)` is -inf, so it cannot be used as-is.
const MUTE_DB: float = -80.0

## Consent to send anonymous game metrics. UNKNOWN is before the first prompt
## and does not collect.
##
## Changing the numeric order would change the meaning of already-saved
## settings, so only append.
enum AnalyticsConsent { UNKNOWN, GRANTED, DENIED }

## Local bits so D1, D7, and D30 are sent once each. No user identifier.
const ANALYTICS_RETENTION_ALLOWED_MASK: int = 1 | 2 | 4

var locale: String = "ko"
var music: int = 4
var sfx: int = 4
var analytics_consent: int = AnalyticsConsent.UNKNOWN
var analytics_cohort_unix: int = 0
var analytics_cohort_version: String = ""
var analytics_retention_mask: int = 0
var _analytics_consent_persist_pending: bool = false


func _ready() -> void:
	locale = _default_locale()
	load_settings()
	apply()


## Language on first launch. Supported locales follow the device; others start in English.
##
## Chinese cannot tell Simplified from Traditional from the language code
## alone. `zh_TW`, `zh_HK`, `zh_MO`, and `Hant` go Traditional; other Chinese
## goes Simplified.
func _default_locale() -> String:
	return locale_for_system(OS.get_locale(), OS.get_locale_language())


## Normalize a device locale onto one of the game's five translation columns.
##
## Split out as a pure function so regression can run without the real device locale.
static func locale_for_system(system_locale: String, system_language: String) -> String:
	var normalized: String = system_locale.replace("-", "_")
	var language: String = system_language.replace("-", "_").get_slice("_", 0).to_lower()
	if language.is_empty():
		language = normalized.get_slice("_", 0).to_lower()
	if language == "zh":
		var upper: String = normalized.to_upper()
		if "HANT" in upper or "_TW" in upper or "_HK" in upper or "_MO" in upper:
			return "zh_TW"
		return "zh_CN"
	return language if language in LOCALES else "en"


func load_settings() -> void:
	_analytics_consent_persist_pending = false
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var saved: String = str(cfg.get_value(SECTION, "locale", locale))
		if saved in LOCALES:                       # a hand-edited file may arrive
			locale = saved
		music = clampi(int(cfg.get_value(SECTION, "music", music)), 0, MAX_STEP)
		sfx = clampi(int(cfg.get_value(SECTION, "sfx", sfx)), 0, MAX_STEP)
		var saved_consent: int = int(cfg.get_value(
			SECTION, "analytics_consent", AnalyticsConsent.UNKNOWN))
		analytics_consent = saved_consent if saved_consent in [
			AnalyticsConsent.GRANTED,
			AnalyticsConsent.DENIED,
		] else AnalyticsConsent.UNKNOWN
		analytics_cohort_unix = maxi(int(cfg.get_value(
			SECTION, "analytics_cohort_unix", 0)), 0)
		analytics_cohort_version = str(cfg.get_value(
			SECTION, "analytics_cohort_version", "")).strip_edges()
		analytics_retention_mask = int(cfg.get_value(
			SECTION, "analytics_retention_mask", 0)) & ANALYTICS_RETENTION_ALLOWED_MASK
	# A revocation mark outranks a prior GRANTED setting. Boundary so that if
	# the app dies the instant an atomic settings replace fails, the next
	# launch cannot turn collection back on.
	var revocation_absolute: String = ProjectSettings.globalize_path(
		ANALYTICS_REVOKED_PATH)
	if FileAccess.file_exists(ANALYTICS_REVOKED_PATH) \
			or DirAccess.dir_exists_absolute(revocation_absolute):
		analytics_consent = AnalyticsConsent.DENIED
	if analytics_consent != AnalyticsConsent.GRANTED \
			or analytics_cohort_unix <= 0 \
			or not _is_safe_cohort_version(analytics_cohort_version):
		_clear_analytics_cohort_memory()


func save_settings() -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "locale", locale)
	cfg.set_value(SECTION, "music", music)
	cfg.set_value(SECTION, "sfx", sfx)
	# Do not write UNKNOWN to the file. Keep old-version settings and store
	# capture's first-run file as-is, while still remembering a real GRANTED
	# or DENIED choice.
	if analytics_consent != AnalyticsConsent.UNKNOWN:
		cfg.set_value(SECTION, "analytics_consent", analytics_consent)
	if analytics_consent == AnalyticsConsent.GRANTED \
			and analytics_cohort_unix > 0 \
			and _is_safe_cohort_version(analytics_cohort_version):
		cfg.set_value(SECTION, "analytics_cohort_unix", analytics_cohort_unix)
		cfg.set_value(SECTION, "analytics_cohort_version", analytics_cohort_version)
		cfg.set_value(SECTION, "analytics_retention_mask", analytics_retention_mask)
	# Write a temp file fully first so a half-written file never overwrites
	# existing settings. Only a same-directory rename runs last, so a mid-quit
	# leaves either the old file or the new one.
	var error: Error = cfg.save(TEMP_SAVE_PATH)
	if error != OK:
		_discard_settings_temp_file()
		return error
	var verification: ConfigFile = ConfigFile.new()
	error = verification.load(TEMP_SAVE_PATH)
	if error != OK:
		_discard_settings_temp_file()
		return error
	error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_SAVE_PATH),
		ProjectSettings.globalize_path(SAVE_PATH))
	if error != OK:
		_discard_settings_temp_file()
	return error


## Apply the current values to the engine.
##
## Changing language makes the engine notify every `Control`.
## Places whose text lives in the scene update in place from that alone.
func apply() -> void:
	TranslationServer.set_locale(locale)
	_apply_bus(&"Music", music)
	_apply_bus(&"Sfx", sfx)


func _apply_bus(bus_name: StringName, step: int) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return                                   # do not die if the bus layout was removed
	AudioServer.set_bus_volume_db(index, step_to_db(step))
	AudioServer.set_bus_mute(index, step == 0)


## Steps to decibels. The ear hears loudness on a log.
##
## Map steps straight onto dB (e.g. -5, -4, -3 …) and only the top one or two
## cells are audible; the rest sound the same. **Take a ratio, then log it.**
func step_to_db(step: int) -> float:
	if step <= 0:
		return MUTE_DB
	return linear_to_db(float(step) / float(MAX_STEP))


func set_locale_to(value: String) -> void:
	if value == locale or value not in LOCALES:
		return
	locale = value
	apply()
	save_settings()
	changed.emit()


func set_music(step: int) -> void:
	step = clampi(step, 0, MAX_STEP)
	if step == music:
		return
	music = step
	apply()
	save_settings()
	changed.emit()


func set_sfx(step: int) -> void:
	step = clampi(step, 0, MAX_STEP)
	if step == sfx:
		return
	sfx = step
	apply()
	save_settings()
	changed.emit()


## Save anonymous-metrics consent. Opening or closing the prompt alone must not call this.
##
## Return value is whether the permanent write finished. Revoke still flips this
## run to DENIED first and emits changed so the send queue is cleared even if
## the storage write fails.
func set_analytics_consent(value: int) -> bool:
	if value not in [AnalyticsConsent.GRANTED, AnalyticsConsent.DENIED]:
		return false
	if value == analytics_consent and not _analytics_consent_persist_pending:
		return true

	var previous_consent: int = analytics_consent
	var previous_cohort_unix: int = analytics_cohort_unix
	var previous_cohort_version: String = analytics_cohort_version
	var previous_retention_mask: int = analytics_retention_mask
	analytics_consent = value
	var revocation_persisted: bool = true
	if value == AnalyticsConsent.DENIED:
		_clear_analytics_cohort_memory()
		revocation_persisted = _persist_analytics_revocation()
		# Notify before save so even if the existing GRANTED file cannot be
		# overwritten, this run's collection and unsent events stop immediately.
		if previous_consent != AnalyticsConsent.DENIED \
				or previous_cohort_unix > 0 \
				or not previous_cohort_version.is_empty() \
				or previous_retention_mask != 0:
			changed.emit()

	var error: Error = save_settings()
	if value == AnalyticsConsent.DENIED:
		# If either the settings.cfg replace or the revocation mark remains, relaunch is fail-closed.
		_analytics_consent_persist_pending = error != OK and not revocation_persisted
		return not _analytics_consent_persist_pending
	_analytics_consent_persist_pending = error != OK
	if error != OK:
		if value == AnalyticsConsent.GRANTED:
			# Sharing is enabled this run only after it remains on disk.
			analytics_consent = previous_consent
			analytics_cohort_unix = previous_cohort_unix
			analytics_cohort_version = previous_cohort_version
			analytics_retention_mask = previous_retention_mask
		return false
	if not _clear_analytics_revocation():
		# Even after writing a GRANTED file, a leftover revocation mark makes
		# the next launch DENIED. Roll this run back to the same fail-closed
		# state and require a retry.
		analytics_consent = AnalyticsConsent.DENIED
		_clear_analytics_cohort_memory()
		_analytics_consent_persist_pending = true
		return false
	if value == AnalyticsConsent.GRANTED and previous_consent != value:
		changed.emit()
	return true


## Remember only first-consent time and app version. No permanent user ID or device value.
func set_analytics_cohort(unix_time: int, version: String) -> bool:
	var normalized_version: String = version.strip_edges()
	if analytics_consent != AnalyticsConsent.GRANTED \
			or unix_time <= 0 \
			or not _is_safe_cohort_version(normalized_version):
		return false
	# Retention epoch is set once. Relaunch must not slide the epoch.
	if analytics_cohort_unix > 0:
		return analytics_cohort_unix == unix_time \
			and analytics_cohort_version == normalized_version
	analytics_cohort_unix = unix_time
	analytics_cohort_version = normalized_version
	analytics_retention_mask = 0
	if save_settings() == OK:
		return true
	_clear_analytics_cohort_memory()
	return false


## Add only one completed D1/D7/D30 bit. Other integers are not saved.
func mark_analytics_retention(bit: int) -> bool:
	if analytics_consent != AnalyticsConsent.GRANTED \
			or analytics_cohort_unix <= 0 \
			or bit not in [1, 2, 4] \
			or (analytics_retention_mask & bit) != 0:
		return (analytics_retention_mask & bit) != 0
	analytics_retention_mask |= bit
	if save_settings() == OK:
		return true
	analytics_retention_mask &= ~bit
	return false


## On consent revoke, wipe the local epoch too.
func clear_analytics_cohort() -> void:
	if analytics_cohort_unix == 0 \
			and analytics_cohort_version.is_empty() \
			and analytics_retention_mask == 0:
		return
	_clear_analytics_cohort_memory()
	save_settings()


func _clear_analytics_cohort_memory() -> void:
	analytics_cohort_unix = 0
	analytics_cohort_version = ""
	analytics_retention_mask = 0


func _is_safe_cohort_version(value: String) -> bool:
	if value.is_empty() or value.length() > 24:
		return false
	for character in value:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-":
			return false
	return true


func _persist_analytics_revocation() -> bool:
	var file: FileAccess = FileAccess.open(ANALYTICS_REVOKED_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("denied\n")
	file.flush()
	return FileAccess.file_exists(ANALYTICS_REVOKED_PATH) \
		and FileAccess.get_file_as_string(ANALYTICS_REVOKED_PATH).strip_edges() == "denied"


func _clear_analytics_revocation() -> bool:
	var absolute: String = ProjectSettings.globalize_path(ANALYTICS_REVOKED_PATH)
	if DirAccess.dir_exists_absolute(absolute):
		return false
	if not FileAccess.file_exists(ANALYTICS_REVOKED_PATH):
		return true
	return DirAccess.remove_absolute(absolute) == OK


func _discard_settings_temp_file() -> void:
	# Tests may occupy the same path as a directory to inject failure. Delete
	# only a regular file we created; do not recursively remove a directory.
	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
