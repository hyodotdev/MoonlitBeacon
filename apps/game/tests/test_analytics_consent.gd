extends Node

## Anonymous analytics-consent save, five-language layout, and in-flight touch-release safety contract.

const CONSENT_SCENE: PackedScene = preload(
	"res://scenes/ui/analytics_consent_panel.tscn")
const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_panel.tscn")
const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const EXTERNAL_LINKS: Script = preload("res://scripts/ui/external_links.gd")
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const CONSENT_BODY_BOUNDARY_TERMS: Dictionary = {
	"ko": ["공유 지표", "이름", "구매 내역", "기기 식별자", "앱 스토어", "별도로 처리"],
	"en": [
		"shared metrics", "name", "purchase history", "device id", "app store",
		"processed separately",
	],
	"ja": ["共有される指標", "名前", "購入履歴", "端末識別子", "アプリストア", "別途処理"],
	"zh_CN": ["分享的指标", "姓名", "购买记录", "设备标识符", "应用商店", "单独处理"],
	"zh_TW": ["分享的指標", "姓名", "購買紀錄", "裝置識別碼", "應用程式商店", "另行處理"],
}

var _failed: int = 0
var _checked: int = 0
var _decisions: Array[bool] = []
var _settings_changes: int = 0
var _original_file_present: bool = false
var _original_file_bytes: PackedByteArray = PackedByteArray()
var _original_revocation_present: bool = false
var _original_revocation_bytes: PackedByteArray = PackedByteArray()
var _original_privacy: Variant
var _original_locale: String
var _original_settings: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	if not _is_isolated():
		get_tree().quit(2)
		return
	get_tree().root.size = Vector2i(808, 360)
	get_tree().root.content_scale_size = Vector2i(808, 360)
	_backup_state()
	_remove_revocation_blocker()
	ProjectSettings.set_setting(
		EXTERNAL_LINKS.PRIVACY_SETTING,
		"https://example.com/{locale}/privacy")

	_test_old_save_defaults()
	_test_consent_and_cohort_persistence()
	_test_arena_run_start_persist_failure_is_fail_closed()
	_test_arena_run_end_persist_retry()
	_test_arena_consent_revocation_closes_active_run()
	await _test_denial_save_failure_is_fail_closed()
	await _test_unconfigured_release_gate()
	await _test_consent_modal()
	await _test_settings_integration()
	await _test_arena_result_prompt()
	_restore_state()

	get_tree().paused = false
	if _failed > 0:
		printerr("anonymous analytics-consent test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("anonymous analytics-consent test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() \
		and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("anonymous analytics-consent test aborted: user:// is not isolated — ", user_root)
	return safe


func _backup_state() -> void:
	_original_file_present = FileAccess.file_exists(Settings.SAVE_PATH)
	if _original_file_present:
		_original_file_bytes = FileAccess.get_file_as_bytes(Settings.SAVE_PATH)
	_original_revocation_present = FileAccess.file_exists(Settings.ANALYTICS_REVOKED_PATH)
	if _original_revocation_present:
		_original_revocation_bytes = FileAccess.get_file_as_bytes(
			Settings.ANALYTICS_REVOKED_PATH)
	_original_privacy = ProjectSettings.get_setting(EXTERNAL_LINKS.PRIVACY_SETTING, "")
	_original_locale = TranslationServer.get_locale()
	_original_settings = {
		"locale": Settings.locale,
		"music": Settings.music,
		"sfx": Settings.sfx,
		"consent": Settings.analytics_consent,
		"cohort_unix": Settings.analytics_cohort_unix,
		"cohort_version": Settings.analytics_cohort_version,
		"retention_mask": Settings.analytics_retention_mask,
	}


func _restore_state() -> void:
	_remove_settings_temp_blocker()
	_remove_revocation_blocker()
	ProjectSettings.set_setting(EXTERNAL_LINKS.PRIVACY_SETTING, _original_privacy)
	TranslationServer.set_locale(_original_locale)
	Settings.locale = str(_original_settings.get("locale", "ko"))
	Settings.music = int(_original_settings.get("music", 4))
	Settings.sfx = int(_original_settings.get("sfx", 4))
	Settings.analytics_consent = int(_original_settings.get("consent", 0))
	Settings.analytics_cohort_unix = int(_original_settings.get("cohort_unix", 0))
	Settings.analytics_cohort_version = str(_original_settings.get("cohort_version", ""))
	Settings.analytics_retention_mask = int(_original_settings.get("retention_mask", 0))
	if _original_file_present:
		var file: FileAccess = FileAccess.open(Settings.SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_original_file_bytes)
	else:
		var absolute: String = ProjectSettings.globalize_path(Settings.SAVE_PATH)
		if FileAccess.file_exists(Settings.SAVE_PATH):
			DirAccess.remove_absolute(absolute)
	if _original_revocation_present:
		var revocation: FileAccess = FileAccess.open(
			Settings.ANALYTICS_REVOKED_PATH, FileAccess.WRITE)
		if revocation != null:
			revocation.store_buffer(_original_revocation_bytes)
	else:
		_remove_revocation_blocker()


func _test_old_save_defaults() -> void:
	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value(Settings.SECTION, "locale", "en")
	legacy.set_value(Settings.SECTION, "music", 3)
	legacy.set_value(Settings.SECTION, "sfx", 2)
	_expect_equal(legacy.save(Settings.SAVE_PATH), OK, "prepares legacy settings")
	Settings.analytics_consent = Settings.AnalyticsConsent.GRANTED
	Settings.analytics_cohort_unix = 1700000000
	Settings.analytics_cohort_version = "2.0.0"
	Settings.analytics_retention_mask = 7
	Settings.load_settings()
	_expect_equal(
		Settings.analytics_consent,
		Settings.AnalyticsConsent.UNKNOWN,
		"legacy settings have analytics unchosen")
	_expect_equal(Settings.analytics_cohort_unix, 0, "legacy settings have no baseline date")
	_expect_equal(Settings.analytics_cohort_version, "", "legacy settings have no baseline version")
	_expect_equal(Settings.analytics_retention_mask, 0, "legacy settings have no retention bits")

	Settings.save_settings()
	var rewritten: ConfigFile = ConfigFile.new()
	_expect_equal(rewritten.load(Settings.SAVE_PATH), OK, "reread unchosen settings")
	_expect_false(
		rewritten.has_section_key(Settings.SECTION, "analytics_consent"),
		"unchosen does not write the consent key")
	_expect_false(
		rewritten.has_section_key(Settings.SECTION, "analytics_cohort_unix"),
		"unchosen does not write the baseline-date key")


func _test_consent_and_cohort_persistence() -> void:
	Settings.analytics_consent = Settings.AnalyticsConsent.UNKNOWN
	Settings.analytics_cohort_unix = 0
	Settings.analytics_cohort_version = ""
	Settings.analytics_retention_mask = 0
	_settings_changes = 0
	Settings.changed.connect(_on_settings_changed)

	Settings.set_analytics_consent(Settings.AnalyticsConsent.UNKNOWN)
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.UNKNOWN,
		"UNKNOWN is not saved as an explicit choice")
	Settings.set_analytics_consent(Settings.AnalyticsConsent.GRANTED)
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.GRANTED,
		"share consent applied")
	_expect_equal(_settings_changes, 1, "share-consent changed once")

	Settings.set_analytics_cohort(1700000000, "2.1.0")
	Settings.set_analytics_cohort(1800000000, "9.9.9")
	_expect_equal(Settings.analytics_cohort_unix, 1700000000, "original baseline date kept")
	_expect_equal(Settings.analytics_cohort_version, "2.1.0", "original baseline version kept")
	Settings.mark_analytics_retention(1)
	Settings.mark_analytics_retention(4)
	Settings.mark_analytics_retention(8)
	Settings.mark_analytics_retention(1)
	_expect_equal(Settings.analytics_retention_mask, 5, "saves only D1 and D30 completion bits")
	_expect_equal(_settings_changes, 1, "internal cohort save does not emit UI changed")

	var granted: ConfigFile = ConfigFile.new()
	_expect_equal(granted.load(Settings.SAVE_PATH), OK, "reread consent settings")
	_expect_equal(int(granted.get_value(Settings.SECTION, "analytics_consent", -1)),
		Settings.AnalyticsConsent.GRANTED, "share-consent file saved")
	_expect_equal(int(granted.get_value(Settings.SECTION, "analytics_cohort_unix", 0)),
		1700000000, "baseline date saved locally")
	_expect_equal(str(granted.get_value(Settings.SECTION, "analytics_cohort_version", "")),
		"2.1.0", "baseline version saved locally")
	_expect_equal(int(granted.get_value(Settings.SECTION, "analytics_retention_mask", 0)),
		5, "retention bits saved locally")

	Settings.set_analytics_consent(Settings.AnalyticsConsent.DENIED)
	_expect_equal(_settings_changes, 2, "deny changed once")
	_expect_equal(Settings.analytics_cohort_unix, 0, "baseline date deleted immediately on revoke")
	_expect_equal(Settings.analytics_cohort_version, "", "baseline version deleted immediately on revoke")
	_expect_equal(Settings.analytics_retention_mask, 0, "retention bits deleted immediately on revoke")
	Settings.set_analytics_cohort(1900000000, "2.1.0")
	_expect_equal(Settings.analytics_cohort_unix, 0, "denied state does not create a baseline date")

	var denied: ConfigFile = ConfigFile.new()
	_expect_equal(denied.load(Settings.SAVE_PATH), OK, "reread denied settings")
	_expect_equal(int(denied.get_value(Settings.SECTION, "analytics_consent", -1)),
		Settings.AnalyticsConsent.DENIED, "denied file saved")
	_expect_false(
		denied.has_section_key(Settings.SECTION, "analytics_cohort_unix"),
		"baseline date removed from the revoke file")
	_expect_false(
		denied.has_section_key(Settings.SECTION, "analytics_retention_mask"),
		"retention bits removed from the revoke file")
	Settings.changed.disconnect(_on_settings_changed)


func _test_denial_save_failure_is_fail_closed() -> void:
	_remove_revocation_blocker()
	var existing: ConfigFile = ConfigFile.new()
	existing.set_value(Settings.SECTION, "locale", "ko")
	existing.set_value(Settings.SECTION, "music", 4)
	existing.set_value(Settings.SECTION, "sfx", 4)
	existing.set_value(Settings.SECTION, "analytics_consent",
		Settings.AnalyticsConsent.GRANTED)
	existing.set_value(Settings.SECTION, "analytics_cohort_unix", 1700000000)
	existing.set_value(Settings.SECTION, "analytics_cohort_version", "2.1.0")
	existing.set_value(Settings.SECTION, "analytics_retention_mask", 1)
	_expect_equal(existing.save(Settings.SAVE_PATH), OK,
		"prepares the existing GRANTED file for a save-failure test")
	Settings.load_settings()

	# First set the test-mode consent source to false, but do not refresh.
	# Separately confirm Settings.changed actually opens the queue-delete boundary.
	Analytics.call("_test_configure", true, true, false)
	Analytics.call("_test_set_now", 1700000100)
	_expect_true(Analytics.track("app_opened"), "prepares the analytics queue before revoke")
	_expect_equal((Analytics.call("_test_pending_items") as Array).size(), 1,
		"one queued item before revoke")
	Analytics.call("_test_set_consent", false)

	_expect_true(_create_settings_temp_blocker(), "prepares a settings temp-file save failure")
	_expect_true(_create_revocation_blocker(), "prepares a revoke-mark save failure")
	var panel: AnalyticsConsentPanel = CONSENT_SCENE.instantiate() as AnalyticsConsentPanel
	add_child(panel)
	panel.decided.connect(_on_decided)
	panel.open()
	await _settle_layout()
	var decisions_before: int = _decisions.size()
	var not_now: Button = panel.get_node(
		"Center/Frame/Content/Rows/Actions/NotNow") as Button
	not_now.pressed.emit()

	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.DENIED,
		"current run is still immediately DENIED on save failure")
	_expect_false(Analytics.enabled(), "current analytics collection still stops on save failure")
	_expect_equal((Analytics.call("_test_pending_items") as Array).size(), 0,
		"existing analytics queue is still deleted immediately on save failure")
	_expect_true(panel.visible, "does not close the consent dialog if save fails")
	_expect_true(get_tree().paused, "stays on the choice screen if save fails")
	_expect_equal(_decisions.size(), decisions_before,
		"does not announce a save failure as a finished decision")
	var status: Label = panel.get_node(
		"Center/Frame/Content/Rows/LinkStatus") as Label
	_expect_true(status.visible, "shows the save failure to the player")
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		await _settle_layout()
		_expect_equal(status.text, tr("SETTINGS_SAVE_FAILED"),
			locale + " save-failed notice copy")
		_expect_true(status.get_line_count() <= status.get_visible_line_count(),
			locale + " save-failed copy not clipped")
	TranslationServer.set_locale("ko")
	await _settle_layout()

	var unchanged: ConfigFile = ConfigFile.new()
	_expect_equal(unchanged.load(Settings.SAVE_PATH), OK,
		"reads the existing settings file after failure")
	_expect_equal(int(unchanged.get_value(
		Settings.SECTION, "analytics_consent", -1)),
		Settings.AnalyticsConsent.GRANTED,
		"an atomic save failure does not corrupt the existing GRANTED file")

	# The directory blocking the revoke path is itself a fail-closed mark. Checking only the file
	# the next run after a failed mark-delete following re-consent save would revive previous GRANTED.
	Settings.analytics_consent = Settings.AnalyticsConsent.GRANTED
	Settings.analytics_cohort_unix = 1700000000
	Settings.analytics_cohort_version = "2.1.0"
	Settings.analytics_retention_mask = 1
	Settings.load_settings()
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.DENIED,
		"revoke-path directory also beats GRANTED on a rerun")
	_expect_equal(Settings.analytics_cohort_unix, 0,
		"revoke-path directory removes the previous analytics cohort")
	# The retry below verifies pressing NOT_NOW again from the previous run's GRANTED memory,
	# path, so restore the state from just before the rerun simulation.
	Settings.analytics_consent = Settings.AnalyticsConsent.GRANTED
	Settings.analytics_cohort_unix = 1700000000
	Settings.analytics_cohort_version = "2.1.0"
	Settings.analytics_retention_mask = 1

	# Keep blocking settings.cfg replace and only restore the revoke mark. If this one file
	# remains, it must still beat previous GRANTED after closing the panel and restarting the app.
	_remove_revocation_blocker()
	not_now.pressed.emit()
	_expect_false(panel.visible, "retrying the same choice succeeds after saving the revoke mark")
	_expect_false(get_tree().paused, "pause restored after saving the revoke mark")
	_expect_equal(_decisions.size(), decisions_before + 1,
		"decides once after a successful retry")
	_expect_false(_decisions.back(), "retried NOT_NOW is granted=false")
	_expect_true(FileAccess.file_exists(Settings.ANALYTICS_REVOKED_PATH),
		"revoke mark is still saved durably even if settings replace fails")
	Settings.analytics_consent = Settings.AnalyticsConsent.GRANTED
	Settings.analytics_cohort_unix = 1700000000
	Settings.analytics_cohort_version = "2.1.0"
	Settings.analytics_retention_mask = 1
	Settings.load_settings()
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.DENIED,
		"rerun load prefers the revoke mark over leftover GRANTED")
	_expect_equal(Settings.analytics_cohort_unix, 0,
		"loading the revoke mark removes the previous analytics cohort")
	_expect_false(Analytics.track("app_opened"),
		"current-run collection stays off even after a successful retry")
	_remove_settings_temp_blocker()
	_expect_true(Settings.set_analytics_consent(Settings.AnalyticsConsent.GRANTED),
		"sharing can be chosen again after save-path recovery")
	_expect_false(FileAccess.file_exists(Settings.ANALYTICS_REVOKED_PATH),
		"choosing share again removes the revoke mark after GRANTED is saved")
	_expect_true(Settings.set_analytics_consent(Settings.AnalyticsConsent.DENIED),
		"turns analytics off again before the test ends")
	panel.queue_free()
	await get_tree().process_frame
	Analytics.call("_test_configure", false, true, false)


func _test_arena_run_end_persist_retry() -> void:
	Analytics.call("_test_configure", true, true, false)
	Analytics.call("_test_set_now", 1700000050)
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	arena.set("_analytics_run_eligible", true)
	arena.set("_analytics_run_id", Analytics.new_run_id())
	Analytics.call("_test_fail_next_persist")
	_expect_false(bool(arena.call("_analytics_track_run_end", "quit", 1234)),
		"run-end queue save failure is propagated")
	_expect_false(bool(arena.get("_analytics_run_end_tracked")),
		"a run-end save failure does not close the dedupe guard")
	_expect_equal((Analytics.call("_test_pending_items") as Array).size(), 0,
		"a run-end save failure rolls back the atomic queue")
	_expect_true(bool(arena.call("_analytics_track_run_end", "quit", 1234)),
		"run-end save retry succeeds in the same Arena")
	_expect_true(bool(arena.get("_analytics_run_end_tracked")),
		"dedupe guard confirms only after run-end save succeeds")
	_expect_equal(_analytics_pending_event_count("run_ended"), 1,
		"a successful retry saves only one run end")
	_expect_false(bool(arena.call("_analytics_track_run_end", "quit", 1234)),
		"blocks duplicate run-end calls after the guard confirms")
	_expect_equal(_analytics_pending_event_count("run_ended"), 1,
		"duplicate run-end calls do not grow the queue")
	arena.free()
	Analytics.call("_test_configure", false, true, false)


func _test_arena_run_start_persist_failure_is_fail_closed() -> void:
	Analytics.call("_test_configure", true, true, false)
	Analytics.call("_test_set_now", 1700000040)
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	# Check only the run-start save boundary, independent of Vault or resource loads.
	arena.set("_run_hero_path", "res://resources/heroes/warden.tres")
	Analytics.call("_test_fail_next_persist")
	arena.call("_analytics_begin_run")
	_expect_false(bool(arena.get("_analytics_run_eligible")),
		"a run-start queue save failure disables analytics for that run")
	_expect_equal((Analytics.call("_test_pending_items") as Array).size(), 0,
		"a run-start save failure rolls back the atomic queue")
	arena.call("_analytics_track", "tutorial_step_completed", {
		"step": "move",
		"elapsed_ms": 1000,
	})
	_expect_equal((Analytics.call("_test_pending_items") as Array).size(), 0,
		"follow-up events are also not collected after a run-start save failure")
	arena.free()
	Analytics.call("_test_configure", false, true, false)


func _test_arena_consent_revocation_closes_active_run() -> void:
	Settings.analytics_consent = Settings.AnalyticsConsent.GRANTED
	Analytics.call("_test_configure", true, true, false)
	Analytics.call("_test_set_now", 1700000030)
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	arena.set("_run_hero_path", "res://resources/heroes/warden.tres")
	arena.call("_bind_analytics_consent_lifecycle")
	arena.call("_analytics_begin_run")
	var old_run_id: String = str(arena.get("_analytics_run_id"))
	_expect_true(bool(arena.get("_analytics_run_eligible")),
		"a run whose start saved during consent is analytics-eligible")
	_expect_equal(_analytics_pending_event_count("run_started"), 1,
		"saves one current-run start before revoke")

	Analytics.call("_test_set_consent", false)
	Settings.analytics_consent = Settings.AnalyticsConsent.DENIED
	Settings.changed.emit()
	_expect_false(bool(arena.get("_analytics_run_eligible")),
		"mid-run consent revoke immediately closes current-run analytics eligibility")
	_expect_equal(str(arena.get("_analytics_run_id")), "",
		"mid-run consent revoke discards the old run ID")
	_expect_equal((Analytics.call("_test_pending_items") as Array).size(), 0,
		"mid-run consent revoke deletes the unsent queue including the start")

	Analytics.call("_test_set_consent", true)
	Settings.analytics_consent = Settings.AnalyticsConsent.GRANTED
	Settings.changed.emit()
	_expect_false(bool(arena.get("_analytics_run_eligible")),
		"re-consenting in the same run does not retroactively reopen analytics eligibility")
	arena.call("_analytics_track", "tutorial_step_completed", {
		"step": "move",
		"elapsed_ms": 1000,
	})
	_expect_false(bool(arena.call("_analytics_track_run_end", "quit", 1234)),
		"also does not collect the old run's end after re-consent")
	_expect_equal(_analytics_pending_run_event_count(old_run_id), 0,
		"no follow-up events of the old run_id appear after re-consent")

	Analytics.call("_test_set_consent", false)
	Settings.analytics_consent = Settings.AnalyticsConsent.DENIED
	Settings.changed.emit()
	arena.free()
	Analytics.call("_test_configure", false, true, false)


func _analytics_pending_event_count(event_name: String) -> int:
	var count: int = 0
	for item in Analytics.call("_test_pending_items") as Array:
		var payload: Dictionary = (item as Dictionary).get("event", {}) as Dictionary
		if str(payload.get("event", "")) == event_name:
			count += 1
	return count


func _analytics_pending_run_event_count(run_id: String) -> int:
	var count: int = 0
	for item in Analytics.call("_test_pending_items") as Array:
		var payload: Dictionary = (item as Dictionary).get("event", {}) as Dictionary
		if str(payload.get("run_id", "")) == run_id:
			count += 1
	return count


func _create_settings_temp_blocker() -> bool:
	_remove_settings_temp_blocker()
	var absolute: String = ProjectSettings.globalize_path(Settings.TEMP_SAVE_PATH)
	if DirAccess.make_dir_absolute(absolute) != OK:
		return false
	var marker: FileAccess = FileAccess.open(absolute.path_join("keep"), FileAccess.WRITE)
	if marker == null:
		DirAccess.remove_absolute(absolute)
		return false
	marker.store_string("block")
	marker.close()
	return true


func _remove_settings_temp_blocker() -> void:
	var absolute: String = ProjectSettings.globalize_path(Settings.TEMP_SAVE_PATH)
	var marker_path: String = absolute.path_join("keep")
	if FileAccess.file_exists(marker_path):
		DirAccess.remove_absolute(marker_path)
	if FileAccess.file_exists(Settings.TEMP_SAVE_PATH):
		DirAccess.remove_absolute(absolute)
	if DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)


func _create_revocation_blocker() -> bool:
	_remove_revocation_blocker()
	var absolute: String = ProjectSettings.globalize_path(Settings.ANALYTICS_REVOKED_PATH)
	return DirAccess.make_dir_absolute(absolute) == OK


func _remove_revocation_blocker() -> void:
	var absolute: String = ProjectSettings.globalize_path(Settings.ANALYTICS_REVOKED_PATH)
	if FileAccess.file_exists(Settings.ANALYTICS_REVOKED_PATH):
		DirAccess.remove_absolute(absolute)
	if DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)


func _test_unconfigured_release_gate() -> void:
	_remove_settings_temp_blocker()
	_remove_revocation_blocker()
	Settings.analytics_consent = Settings.AnalyticsConsent.UNKNOWN
	Settings.analytics_cohort_unix = 0
	Settings.analytics_cohort_version = ""
	Settings.analytics_retention_mask = 0
	_expect_equal(Settings.save_settings(), OK, "initial settings saved at the unconfigured-ship boundary")
	Analytics.call("_test_configure", false, true, false)
	_expect_true(Settings.set_analytics_consent(Settings.AnalyticsConsent.GRANTED),
		"prepares a prior GRANTED sample from an older build")
	_expect_true(Settings.set_analytics_cohort(1700000000, "2.1.0"),
		"prepares a prior GRANTED cohort sample")

	# Inject the 2.1.0 production state with send Settings missing. Before UI starts,
	# Analytics' startup boundary turns that same state into permanent DENIED.
	Analytics.call("_test_configure", true, false, false)
	_expect_false(Analytics.configured(), "a ship with no send settings leaves analytics unconfigured")
	_expect_false(Analytics.enabled(), "unconfigured ship cannot collect even with prior GRANTED")

	var settings_panel: Control = SETTINGS_SCENE.instantiate() as Control
	add_child(settings_panel)
	settings_panel.call("open")
	await _settle_layout()
	var analytics_label: Label = settings_panel.get_node("AnalyticsLabel") as Label
	var analytics_button: Button = settings_panel.get_node("Analytics") as Button
	_expect_false(analytics_label.visible, "unconfigured ship hides the analytics settings label")
	_expect_false(analytics_button.visible, "unconfigured ship hides analytics settings entry")
	_expect_true(analytics_button.disabled, "unconfigured ship disables analytics settings entry")
	analytics_button.pressed.emit()
	await _settle_layout()
	_expect_false(bool(settings_panel.call("has_nested_overlay")),
		"sending a hidden analytics-button signal directly still does not show consent")
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.GRANTED,
		"hidden settings entry does not re-save the existing value")

	var direct_panel: AnalyticsConsentPanel = CONSENT_SCENE.instantiate() \
		as AnalyticsConsentPanel
	add_child(direct_panel)
	direct_panel.open()
	await _settle_layout()
	_expect_false(direct_panel.visible, "unconfigured ship also blocks opening the consent dialog directly")
	(direct_panel.get_node(
		"Center/Frame/Content/Rows/Actions/Share") as Button).pressed.emit()
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.GRANTED,
		"SHARE from a closed consent dialog does not save GRANTED again")

	_expect_false(bool(Analytics.call("_enforce_configuration_gate")),
		"unconfigured startup boundary applied")
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.DENIED,
		"unconfigured ship converts prior GRANTED to permanent DENIED")
	_expect_equal(Settings.analytics_cohort_unix, 0,
		"unconfigured ship deletes the prior analytics baseline date")
	_expect_equal(Settings.analytics_cohort_version, "",
		"unconfigured ship deletes the prior analytics baseline version")
	_expect_equal(Settings.analytics_retention_mask, 0,
		"unconfigured ship deletes prior retention bits")
	_expect_false(Analytics.enabled(), "cannot collect the current run after the startup boundary")
	_expect_false(Analytics.track("app_opened"),
		"cannot create an event queue after the startup boundary")
	var persisted: ConfigFile = ConfigFile.new()
	_expect_equal(persisted.load(Settings.SAVE_PATH), OK,
		"reread DENIED settings of an unconfigured ship")
	_expect_equal(int(persisted.get_value(
		Settings.SECTION, "analytics_consent", -1)),
		Settings.AnalyticsConsent.DENIED,
		"unconfigured ship also removes prior GRANTED from the file")
	_expect_false(persisted.has_section_key(
		Settings.SECTION, "analytics_cohort_unix"),
		"unconfigured-ship file does not leave a previous cohort")

	# Even if a later version gets valid config, do not auto-collect from the choice just invalidated.
	Analytics.call("_test_configure",
		Settings.analytics_consent == Settings.AnalyticsConsent.GRANTED, true, false)
	_expect_true(Analytics.configured(), "sample of valid send settings for a later ship")
	_expect_false(Analytics.enabled(), "adding later settings alone must not auto-enable previous consent")
	_expect_false(Analytics.track("app_opened"),
		"no events collected after adding later settings until new consent")

	# Also re-check the defense that vanishes after Settings opens, just before SHARE save.
	Settings.analytics_consent = Settings.AnalyticsConsent.UNKNOWN
	Analytics.call("_test_configure", false, true, false)
	direct_panel.open()
	await _settle_layout()
	_expect_true(direct_panel.visible, "consent dialog can be entered under valid settings")
	Analytics.call("_test_configure", false, false, false)
	(direct_panel.get_node(
		"Center/Frame/Content/Rows/Actions/Share") as Button).pressed.emit()
	_expect_false(direct_panel.visible, "consent dialog closes if settings are lost just before SHARE")
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.UNKNOWN,
		"does not save GRANTED if settings are lost just before SHARE")

	settings_panel.call("close")
	settings_panel.queue_free()
	direct_panel.queue_free()
	await get_tree().process_frame
	Analytics.call("_test_configure", false, true, false)


func _test_consent_modal() -> void:
	Settings.analytics_consent = Settings.AnalyticsConsent.UNKNOWN
	var panel: AnalyticsConsentPanel = CONSENT_SCENE.instantiate() as AnalyticsConsentPanel
	add_child(panel)
	panel.decided.connect(_on_decided)
	await _settle_layout()

	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		panel.open()
		await _settle_layout()
		_check_consent_layout(panel, locale)
		_expect_equal(
			(panel.get_node("Center/Frame/Content/Rows/Title") as Label).text,
			tr("ANALYTICS_CONSENT_TITLE"),
			locale + " consent title")
		var body_text: String = (
			panel.get_node("Center/Frame/Content/Rows/Body") as Label).text
		_expect_equal(body_text, tr("ANALYTICS_CONSENT_BODY"), locale + " consent body")
		for boundary_term: Variant in CONSENT_BODY_BOUNDARY_TERMS.get(locale, []):
			_expect_true(str(boundary_term).to_lower() in body_text.to_lower(),
				locale + " consent body bounds · " + str(boundary_term))
		_expect_true(
			(panel.get_node("Center/Frame/Content/Rows/Privacy") as Button).visible,
			locale + " privacy link shown")
		panel.close_without_choice()
		_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.UNKNOWN,
			locale + " close-only keeps unchosen")

	await _test_held_touch_release(panel)
	await _test_held_mouse_release(panel)
	var before: int = _decisions.size()
	panel.open()
	await _settle_layout()
	(panel.get_node("Center/Frame/Content/Rows/Actions/Share") as Button).pressed.emit()
	_expect_equal(_decisions.size(), before + 1, "SHARE decides once")
	_expect_true(_decisions.back(), "SHARE is granted=true")
	_expect_false(panel.visible, "closes after SHARE")
	_expect_false(get_tree().paused, "restores previous pause after SHARE")

	before = _decisions.size()
	panel.open()
	await _settle_layout()
	var not_now: Button = panel.get_node(
		"Center/Frame/Content/Rows/Actions/NotNow") as Button
	not_now.pressed.emit()
	not_now.pressed.emit()
	_expect_equal(_decisions.size(), before + 1, "duplicate NOT_NOW presses decide only once")
	_expect_false(_decisions.back(), "NOT_NOW is granted=false")

	get_tree().paused = true
	panel.open()
	await _settle_layout()
	panel.close_without_choice()
	_expect_true(get_tree().paused, "restores pause of an already-paused scene")
	get_tree().paused = false
	panel.queue_free()
	await get_tree().process_frame


func _test_held_touch_release(panel: AnalyticsConsentPanel) -> void:
	var share: Button = panel.get_node(
		"Center/Frame/Content/Rows/Actions/Share") as Button
	var not_now: Button = panel.get_node(
		"Center/Frame/Content/Rows/Actions/NotNow") as Button
	var center: Vector2 = share.get_global_rect().get_center()
	var before: int = _decisions.size()
	_push_touch(7, center, true)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	_expect_true(share.disabled, "SHARE locked during in-flight touch")
	_expect_true(not_now.disabled, "NOT_NOW locked during in-flight touch")
	_push_touch(7, center, false)
	await get_tree().process_frame
	_expect_equal(_decisions.size(), before, "an in-flight touch release does not decide")
	await get_tree().process_frame
	_expect_false(share.disabled, "SHARE enables the frame after touch release")
	_expect_false(not_now.disabled, "NOT_NOW enables the frame after touch release")
	panel.close_without_choice()


func _test_held_mouse_release(panel: AnalyticsConsentPanel) -> void:
	var share: Button = panel.get_node(
		"Center/Frame/Content/Rows/Actions/Share") as Button
	var not_now: Button = panel.get_node(
		"Center/Frame/Content/Rows/Actions/NotNow") as Button
	var center: Vector2 = not_now.get_global_rect().get_center()
	var before: int = _decisions.size()
	_push_mouse(center, true)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	_expect_true(share.disabled, "SHARE locked during in-flight mouse")
	_expect_true(not_now.disabled, "NOT_NOW locked during in-flight mouse")
	_push_mouse(center, false)
	await get_tree().process_frame
	_expect_equal(_decisions.size(), before, "an in-flight mouse release does not decide")
	await get_tree().process_frame
	_expect_false(share.disabled, "SHARE enables the frame after mouse release")
	_expect_false(not_now.disabled, "NOT_NOW enables the frame after mouse release")
	panel.close_without_choice()


func _check_consent_layout(panel: AnalyticsConsentPanel, locale: String) -> void:
	var full: Rect2 = panel.get_viewport_rect()
	var safe: Rect2 = full.grow(-12.0)
	var frame: Control = panel.get_node("Center/Frame") as Control
	var title: Label = panel.get_node("Center/Frame/Content/Rows/Title") as Label
	var body: Label = panel.get_node("Center/Frame/Content/Rows/Body") as Label
	var share: Button = panel.get_node(
		"Center/Frame/Content/Rows/Actions/Share") as Button
	var not_now: Button = panel.get_node(
		"Center/Frame/Content/Rows/Actions/NotNow") as Button
	_expect_true(_inside(frame.get_global_rect(), safe), locale + " consent frame safe area")
	_expect_true(title.get_line_count() <= title.get_visible_line_count(),
		locale + " consent title not clipped")
	_expect_true(body.get_line_count() <= body.get_visible_line_count(),
		locale + " consent body not clipped")
	_expect_true(is_equal_approx(share.size.x, not_now.size.x),
		locale + " SHARE and NOT_NOW same width")
	_expect_true(is_equal_approx(share.size.y, not_now.size.y),
		locale + " SHARE and NOT_NOW same height")
	_expect_true(share.size.y >= 44.0, locale + " SHARE tap height")
	_expect_true(not_now.size.y >= 44.0, locale + " NOT_NOW tap height")


func _test_settings_integration() -> void:
	Settings.analytics_consent = Settings.AnalyticsConsent.UNKNOWN
	Settings.analytics_cohort_unix = 0
	Settings.analytics_cohort_version = ""
	Settings.analytics_retention_mask = 0
	TranslationServer.set_locale("ko")
	var panel: Control = SETTINGS_SCENE.instantiate() as Control
	add_child(panel)
	panel.call("open")
	await _settle_layout()
	var analytics: Button = panel.get_node("Analytics") as Button
	var consent: AnalyticsConsentPanel = panel.get_node(
		"Dim/AnalyticsConsent") as AnalyticsConsentPanel
	var external_links: Control = panel.get_node("ExternalLinks") as Control
	var link_status: Label = panel.get_node("LinkStatus") as Label
	_expect_equal(analytics.text, tr("SETTINGS_ANALYTICS_UNKNOWN"),
		"Settings analytics unchosen state")
	_expect_true(_inside(analytics.get_global_rect(), panel.get_viewport_rect().grow(-12.0)),
		"Settings analytics-button safe area")
	_expect_false(
		analytics.get_global_rect().intersects(
			(panel.get_node("Credits") as Button).get_global_rect()),
		"analytics button does not overlap the credits button")
	_expect_false(external_links.get_global_rect().intersects(
		link_status.get_global_rect()), "external-link failure copy does not overlap the button")
	_expect_true(_inside(link_status.get_global_rect(),
		panel.get_viewport_rect().grow(-12.0)), "external-link failure copy safe area")

	analytics.pressed.emit()
	await _settle_layout()
	_expect_true(bool(panel.call("has_nested_overlay")),
		"Settings reports the inner consent dialog as the Android-back target")
	_expect_true(bool(panel.call("close_nested_overlay")),
		"Settings inner consent dialog closes one step")
	_expect_false(bool(panel.call("has_nested_overlay")),
		"no inner consent dialog after a one-step close")
	_expect_false(bool(panel.call("close_nested_overlay")),
		"Android back is not consumed when there is no inner consent dialog")
	_expect_true(panel.visible, "Settings stays open after closing the inner consent dialog")
	_expect_equal(get_viewport().gui_get_focus_owner(), analytics,
		"pad focus returns to the analytics button after inner-consent Back")
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.UNKNOWN,
		"just closing the settings consent dialog stays unchosen")
	analytics.pressed.emit()
	await _settle_layout()
	(consent.get_node("Center/Frame/Content/Rows/Actions/Share") as Button).pressed.emit()
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.GRANTED,
		"turn sharing on in Settings")
	_expect_equal(analytics.text, tr("SETTINGS_ANALYTICS_ON"),
		"Settings shows sharing on")
	_expect_equal(get_viewport().gui_get_focus_owner(), analytics,
		"pad focus returns to the analytics button after choosing share")

	analytics.pressed.emit()
	await _settle_layout()
	(consent.get_node("Center/Frame/Content/Rows/Actions/NotNow") as Button).pressed.emit()
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.DENIED,
		"turn sharing off in Settings")
	_expect_equal(analytics.text, tr("SETTINGS_ANALYTICS_OFF"),
		"Settings shows sharing off")
	_expect_equal(get_viewport().gui_get_focus_owner(), analytics,
		"pad focus returns to the analytics button after turning sharing off")
	panel.call("close")
	panel.queue_free()
	await get_tree().process_frame


func _test_arena_result_prompt() -> void:
	# Enable only ship Settings unrelated to consent. Test mode never creates a network.
	Analytics.call("_test_configure", false, true, false)
	Settings.analytics_consent = Settings.AnalyticsConsent.UNKNOWN
	Settings.analytics_cohort_unix = 0
	Settings.analytics_cohort_version = ""
	Settings.analytics_retention_mask = 0
	Settings.save_settings()

	# Defeat result: a press that finished revealing must not become the consent button's release.
	var defeat: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(defeat)
	defeat.call("debug_allow_analytics_consent_prompt_for_test")
	await _settle_layout()
	defeat.call("_finish", false)
	await get_tree().process_frame
	var defeat_result: Control = defeat.get_node("Ui/Result") as Control
	var defeat_consent: AnalyticsConsentPanel = defeat.get_node(
		"Ui/AnalyticsConsent") as AnalyticsConsentPanel
	var reveal_count: Array[int] = [0]
	defeat_result.reveal_finished.connect(func() -> void: reveal_count[0] += 1)
	var share: Button = defeat_consent.get_node(
		"Center/Frame/Content/Rows/Actions/Share") as Button
	var touch_at: Vector2 = share.get_global_rect().get_center()
	_push_touch(9, touch_at, true)
	await get_tree().process_frame
	defeat_result.call("_skip_reveal")
	await get_tree().process_frame
	_expect_equal(reveal_count[0], 1, "defeat-result reveal signal once")
	_expect_true(defeat_consent.visible, "UNKNOWN consent dialog after revealing a defeat result")
	_expect_true(get_tree().paused, "result consent dialog pauses combat and result behind it")
	_expect_true(share.disabled, "SHARE locked during held touch at result reveal")
	_expect_true(
		(defeat_result.get_node("Actions/Retry") as Button).disabled,
		"result buttons locked under the consent dialog")
	_push_touch(9, touch_at, false)
	await _settle_layout()
	_expect_false(share.disabled, "SHARE enables after touch release at result reveal")
	_expect_true(
		(defeat_result.get_node("Actions/Retry") as Button).disabled,
		"result buttons stay locked before a consent choice")

	# PC/pad cancel also tells Arena the panel closed so result unlock happens together.
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	get_viewport().push_input(cancel)
	await get_tree().process_frame
	_expect_false(defeat_consent.visible, "Esc/pad cancel closes only the consent dialog")
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.UNKNOWN,
		"Esc/pad cancel keeps UNKNOWN")
	_expect_false(get_tree().paused, "result scene pause restores after Esc/pad cancel")
	_expect_false(
		(defeat_result.get_node("Actions/Retry") as Button).disabled,
		"result buttons restore after Esc/pad cancel")

	# On a new Arena too, Android back makes no decision and only restores the result.
	defeat.queue_free()
	await _settle_layout()
	Settings.analytics_consent = Settings.AnalyticsConsent.UNKNOWN
	Settings.save_settings()
	defeat = ARENA_SCENE.instantiate() as Node2D
	add_child(defeat)
	defeat.call("debug_allow_analytics_consent_prompt_for_test")
	await _settle_layout()
	defeat.call("_finish", false)
	await get_tree().process_frame
	defeat_result = defeat.get_node("Ui/Result") as Control
	defeat_consent = defeat.get_node("Ui/AnalyticsConsent") as AnalyticsConsentPanel
	defeat_result.call("_skip_reveal")
	await _settle_layout()
	defeat.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	_expect_false(defeat_consent.visible, "Android back closes only the consent dialog")
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.UNKNOWN,
		"Android back keeps UNKNOWN")
	_expect_false(get_tree().paused, "result scene pause restores after Android back")
	_expect_false(
		(defeat_result.get_node("Actions/Retry") as Button).disabled,
		"result buttons restore after Android back")
	var android_reveal_count: Array[int] = [0]
	defeat_result.reveal_finished.connect(
		func() -> void: android_reveal_count[0] += 1)
	defeat_result.call("_finish_reveal")
	_expect_equal(android_reveal_count[0], 0, "result-reveal signal is not duplicated")
	_expect_false(defeat_consent.visible, "consent dialog is not shown again on the same result")
	defeat.queue_free()
	await _settle_layout()

	# A normal-settlement victory also asks at the same result-reveal boundary, and NOT_NOW is explicitly rejected.
	Settings.analytics_consent = Settings.AnalyticsConsent.UNKNOWN
	Settings.save_settings()
	var victory: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(victory)
	victory.call("debug_allow_analytics_consent_prompt_for_test")
	await _settle_layout()
	victory.call("_finish", true)
	await get_tree().process_frame
	var victory_result: Control = victory.get_node("Ui/Result") as Control
	var victory_consent: AnalyticsConsentPanel = victory.get_node(
		"Ui/AnalyticsConsent") as AnalyticsConsentPanel
	victory_result.call("_skip_reveal")
	await _settle_layout()
	_expect_true(victory_consent.visible, "UNKNOWN consent dialog after revealing a victory settlement")
	_expect_false(
		(victory_result.get_node("Actions/Continue") as Button).visible,
		"no paid continue under the victory consent dialog")
	(victory_consent.get_node(
		"Center/Frame/Content/Rows/Actions/NotNow") as Button).pressed.emit()
	_expect_equal(Settings.analytics_consent, Settings.AnalyticsConsent.DENIED,
		"victory-result NOT_NOW saves sharing as rejected")
	_expect_false(victory_consent.visible, "consent dialog closes after a victory-result decision")
	_expect_false(
		(victory_result.get_node("Actions/Retry") as Button).disabled,
		"result buttons restore after a victory-result decision")
	victory.queue_free()
	await _settle_layout()

	# Normal debug does not open even with send Settings, and capture outranks a test override.
	Settings.analytics_consent = Settings.AnalyticsConsent.UNKNOWN
	Settings.save_settings()
	var debug_arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(debug_arena)
	await _settle_layout()
	debug_arena.call("_finish", false)
	await get_tree().process_frame
	(debug_arena.get_node("Ui/Result") as Control).call("_skip_reveal")
	await _settle_layout()
	_expect_false(
		(debug_arena.get_node("Ui/AnalyticsConsent") as Control).visible,
		"a normal debug result suppresses the consent dialog")
	debug_arena.queue_free()
	await _settle_layout()

	var capture_arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(capture_arena)
	capture_arena.call("debug_allow_analytics_consent_prompt_for_test")
	capture_arena.set("_debug_guardian_capture_active", true)
	await _settle_layout()
	capture_arena.call("_finish", false)
	await get_tree().process_frame
	(capture_arena.get_node("Ui/Result") as Control).call("_skip_reveal")
	await _settle_layout()
	_expect_false(
		(capture_arena.get_node("Ui/AnalyticsConsent") as Control).visible,
		"store-capture result is suppressed ahead of a test override")
	capture_arena.queue_free()
	await _settle_layout()


func _settle_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _push_touch(index: int, position: Vector2, pressed: bool) -> void:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = index
	touch.position = position
	touch.pressed = pressed
	get_viewport().push_input(touch)


func _push_mouse(position: Vector2, pressed: bool) -> void:
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = position
	mouse.pressed = pressed
	get_viewport().push_input(mouse)


func _on_decided(granted: bool) -> void:
	_decisions.append(granted)


func _on_settings_changed() -> void:
	_settings_changes += 1


func _inside(rect: Rect2, boundary: Rect2) -> bool:
	const EPSILON: float = 0.01
	return rect.has_area() \
		and rect.position.x >= boundary.position.x - EPSILON \
		and rect.position.y >= boundary.position.y - EPSILON \
		and rect.end.x <= boundary.end.x + EPSILON \
		and rect.end.y <= boundary.end.y + EPSILON


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected=", expected, " actual=", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _expect_false(value: bool, label: String) -> void:
	_expect_equal(value, false, label)
