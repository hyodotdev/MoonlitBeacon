extends Node

## Attendance-reminder controller tests: intent, permission, schedule.
##
## The controller, Settings persistence, the settings row, and the HUD
## offer are real; the production host and the native bridge are fakes
## speaking the same contracts. Native delivery itself runs on devices
## the director drives; these tests prove the game side asks for exactly
## the right deliveries and never invents one.

const REMINDERS_SCRIPT: Script = preload(
	"res://scripts/gameplay/attendance_reminders.gd")
const PANEL_SCENE: PackedScene = preload(
	"res://scenes/ui/settings_panel.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const FAKE_ID: String = "MB-remindertest00000000000000001"
const OTHER_ID: String = "MB-remindertest00000000000000002"

var _failed: int = 0
var _checked: int = 0


class ReminderFakeHost extends Node:
	signal production_attendance(snapshot: Dictionary)
	signal production_changed(state: Dictionary)

	var view: Dictionary = {"state": "unregistered", "source": "none",
		"public_id": "", "receipt": "", "last_claim_utc": "",
		"next_eligible_utc": "", "remaining_seconds": -1}

	func attendance_view() -> Dictionary:
		return view.duplicate()

	func publish() -> void:
		production_attendance.emit(attendance_view())

	func live(public_id: String, eligible_utc: String,
			remaining: int) -> void:
		view = {"state": "cooldown", "source": "live",
			"public_id": public_id, "receipt": "r",
			"last_claim_utc": "2026-10-07T00:00:00Z",
			"next_eligible_utc": eligible_utc,
			"remaining_seconds": remaining}


class ReminderFakeBridge extends Node:
	signal request_completed(outcome: Dictionary)

	var permission: String = "unknown"
	var permission_behavior: String = "pending"
	var status_behavior: String = "sync"
	var status_receipt: Dictionary = {}
	var schedule_receipt: Dictionary = {}
	var permission_ids: Array = []
	var status_ids: Array = []
	var schedule_log: Array = []
	var cancels: int = 0
	var opens: int = 0
	var _counter: int = 0

	func reminder_status() -> Dictionary:
		if not status_receipt.is_empty():
			return status_receipt.duplicate()
		if status_behavior == "pending":
			_counter += 1
			var request_id: String = "stat-%d" % _counter
			status_ids.append(request_id)
			return {"status": "pending", "request_id": request_id}
		return {"status": "ok", "permission": permission,
			"scheduled": not schedule_log.is_empty()}

	func answer_status(outcome: Dictionary) -> void:
		var answered: Dictionary = outcome.duplicate()
		answered["request_id"] = str(status_ids.back())
		if str(answered.get("status", "")) == "ok":
			permission = str(answered.get("permission", permission))
		request_completed.emit(answered)

	func reminder_request_permission() -> Dictionary:
		if permission_behavior == "sync-granted":
			return {"status": "ok", "permission": "granted"}
		if permission_behavior == "sync-denied":
			return {"status": "ok", "permission": "denied"}
		if permission_behavior == "sync-unsupported":
			return {"status": "unsupported",
				"code": "native_bridge_unavailable"}
		_counter += 1
		var request_id: String = "perm-%d" % _counter
		permission_ids.append(request_id)
		return {"status": "pending", "request_id": request_id}

	func answer_permission(granted: bool) -> void:
		var request_id: String = str(permission_ids.back())
		permission = "granted" if granted else "denied"
		request_completed.emit({"status": "ok",
			"permission": permission, "request_id": request_id})

	func answer_stale() -> void:
		request_completed.emit({"status": "ok",
			"permission": "granted", "request_id": "perm-stale"})

	func reminder_schedule(args: Dictionary) -> Dictionary:
		schedule_log.append(args.duplicate())
		if not schedule_receipt.is_empty():
			return schedule_receipt.duplicate()
		return {"status": "ok",
			"eligible_millis": args.get("eligible_utc_millis", 0),
			"horizon_end_unix": -1.0}

	func reminder_cancel() -> Dictionary:
		cancels += 1
		schedule_log.clear()
		return {"status": "ok"}

	func reminder_open_settings() -> Dictionary:
		opens += 1
		return {"status": "ok"}


var _host: ReminderFakeHost
var _bridge: ReminderFakeBridge
var _controller: Node
var _original_settings: Dictionary = {}
var _original_file_bytes: PackedByteArray = PackedByteArray()
var _original_file_present: bool = false
var _original_sentinel_bytes: PackedByteArray = PackedByteArray()
var _original_sentinel_present: bool = false
var _host_owned_reminders: Node = null
var _host_owned_host: Node = null
var _host_owned_bridge: Node = null


func _ready() -> void:
	_snapshot_settings()
	_host = ReminderFakeHost.new()
	_bridge = ReminderFakeBridge.new()
	_controller = REMINDERS_SCRIPT.new()
	add_child(_host)
	add_child(_bridge)
	add_child(_controller)
	_controller.configure(_host, _bridge)
	_mute_host_reminders()
	await get_tree().process_frame
	_clean_reminder_state()
	_test_defaults_idle()
	_test_enable_grant_schedules()
	_test_reschedule_skips_when_unchanged()
	_test_locale_change_reschedules()
	_test_new_reward_reschedules()
	_test_eligible_now_schedules_same_anchor()
	_test_short_window_schedules_first_delay()
	_test_bad_deadline_schedules_nothing()
	_test_unknown_source_keeps_existing()
	_test_cached_deadline_schedules()
	_test_live_denial_blocks_schedule()
	_test_toggle_from_denied_opens_settings()
	_test_disable_cancels_and_seals()
	_test_save_failure_stays_off()
	_test_stale_permission_dropped()
	_test_account_switch_retires()
	_test_sign_out_retires()
	_test_unsupported_bridge_honest()
	_test_receipt_offer_once()
	_test_permission_denial_not_enabled()
	_test_native_schedule_denial_not_recorded()
	_test_native_status_unsupported_clears()
	_test_transient_native_error_keeps_schedule()
	_test_revocation_surfaces_on_same_deadline()
	_test_async_status_converges()
	_test_async_denial_schedules_nothing()
	_test_pending_status_still_offers()
	_test_async_timeout_keeps_cache()
	_test_pending_status_then_off_ignores_late_grant()
	_test_pending_status_then_source_none_schedules_nothing()
	_test_reenable_after_late_grant_schedules_once()
	_test_horizon_window_matrix()
	_test_refill_window_reschedules_same_anchor()
	_test_expired_cache_schedules_once()
	_test_duplicate_receipt_keeps_known_end()
	await _test_panel_without_analytics()
	await _test_panel_builds_reminder_row_on_open()
	await _test_unknown_row_never_shows_on()
	await _test_panel_fits_locales()
	await _test_reminder_label_recomputes()
	await _test_hud_offer()
	_restore_host_reminders()
	_restore_settings()
	if _failed > 0:
		printerr("reminders test failed — ", _failed, "/",
			_checked, " case(s)")
		get_tree().quit(1)
		return
	print("reminders: ", _checked, " checks, 0 failed")
	get_tree().quit(0)


## The ProductionHost autoload owns a second reminder controller in
## this scene, and both reconcile the same shared Settings record: an
## emit under test lets the host's controller retire the planted
## record through the real bridge before the test controller's own
## verdict is asserted. Production runs exactly one controller, so the
## suite unhosts the spare (keeping its bridge for the panel taps)
## and restores it at the end.
func _mute_host_reminders() -> void:
	var host: Node = get_node_or_null("/root/ProductionHost")
	if host == null or not host.has_method("reminder_controller"):
		return
	var owned: Variant = host.call("reminder_controller")
	if not (owned is Node and is_instance_valid(owned)):
		return
	_host_owned_reminders = owned
	_host_owned_host = owned.get("_host")
	_host_owned_bridge = owned.get("_bridge")
	owned.call("configure", null, _host_owned_bridge)


func _restore_host_reminders() -> void:
	if _host_owned_reminders == null \
			or not is_instance_valid(_host_owned_reminders):
		return
	_host_owned_reminders.call("configure", _host_owned_host,
		_host_owned_bridge)
	_host_owned_reminders = null
	_host_owned_host = null
	_host_owned_bridge = null


func _snapshot_settings() -> void:
	_original_settings = {
		"locale": Settings.locale,
		"enabled": Settings.reminders_enabled,
		"offered": Settings.reminder_receipt_offered,
		"os": Settings.reminder_os_state,
		"account": Settings.reminder_sched_account,
		"eligible": Settings.reminder_sched_eligible_utc,
		"sched_locale": Settings.reminder_sched_locale,
	}
	_original_file_present = FileAccess.file_exists(
		Settings.SAVE_PATH)
	if _original_file_present:
		_original_file_bytes = FileAccess.get_file_as_bytes(
			Settings.SAVE_PATH)
	_original_sentinel_present = FileAccess.file_exists(
		Settings.REMINDER_DISABLED_PATH)
	if _original_sentinel_present:
		_original_sentinel_bytes = FileAccess.get_file_as_bytes(
			Settings.REMINDER_DISABLED_PATH)


func _restore_settings() -> void:
	_remove_temp_blocker()
	Settings.locale = str(_original_settings["locale"])
	Settings.reminders_enabled = bool(_original_settings["enabled"])
	Settings.reminder_receipt_offered = bool(
		_original_settings["offered"])
	Settings.reminder_os_state = str(_original_settings["os"])
	Settings.reminder_sched_account = str(
		_original_settings["account"])
	Settings.reminder_sched_eligible_utc = str(
		_original_settings["eligible"])
	Settings.reminder_sched_locale = str(
		_original_settings["sched_locale"])
	Analytics._test_mode = false
	if _original_file_present:
		var file: FileAccess = FileAccess.open(
			Settings.SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_original_file_bytes)
	else:
		var absolute: String = ProjectSettings.globalize_path(
			Settings.SAVE_PATH)
		if FileAccess.file_exists(Settings.SAVE_PATH):
			DirAccess.remove_absolute(absolute)
	if _original_sentinel_present:
		var mark: FileAccess = FileAccess.open(
			Settings.REMINDER_DISABLED_PATH, FileAccess.WRITE)
		if mark != null:
			mark.store_buffer(_original_sentinel_bytes)
	else:
		var mark_path: String = ProjectSettings.globalize_path(
			Settings.REMINDER_DISABLED_PATH)
		if FileAccess.file_exists(Settings.REMINDER_DISABLED_PATH):
			DirAccess.remove_absolute(mark_path)
		elif DirAccess.dir_exists_absolute(mark_path):
			DirAccess.remove_absolute(mark_path)


func _clean_reminder_state() -> void:
	Settings.reminders_enabled = false
	Settings.reminder_receipt_offered = false
	Settings.reminder_os_state = "unknown"
	Settings.reminder_sched_account = ""
	Settings.reminder_sched_eligible_utc = ""
	Settings.reminder_sched_locale = ""
	Settings.reminder_sched_horizon_end = 0.0
	Settings.reminder_sched_base_slot = -1
	Settings.save_settings()
	var mark_path: String = ProjectSettings.globalize_path(
		Settings.REMINDER_DISABLED_PATH)
	if FileAccess.file_exists(Settings.REMINDER_DISABLED_PATH):
		DirAccess.remove_absolute(mark_path)
	_host.view = {"state": "unregistered", "source": "none",
		"public_id": "", "receipt": "", "last_claim_utc": "",
		"next_eligible_utc": "", "remaining_seconds": -1}
	_bridge.permission = "unknown"
	_bridge.permission_behavior = "pending"
	_bridge.status_behavior = "sync"
	_bridge.status_receipt = {}
	_bridge.schedule_receipt = {}
	_bridge.permission_ids.clear()
	_bridge.status_ids.clear()
	_bridge.schedule_log.clear()
	_bridge.cancels = 0
	_bridge.opens = 0
	_controller.configure(_host, _bridge)


func _future_utc(seconds_out: int) -> String:
	var unix: int = int(Time.get_unix_time_from_system()) \
		+ seconds_out
	return Time.get_datetime_string_from_unix_time(unix, true) + "Z"


func _past_utc(seconds_ago: int) -> String:
	var unix: int = int(Time.get_unix_time_from_system()) \
		- seconds_ago
	return Time.get_datetime_string_from_unix_time(unix, true) + "Z"


## Last fire of a 48-slot window on its anchor: base plus 47 repeats.
func _window_end(anchor_unix: int, base: int) -> float:
	return float(anchor_unix + (base + 47) * 43200)


func _test_defaults_idle() -> void:
	_expect_false(Settings.reminders_enabled,
		"reminders default off")
	_expect_equal(Settings.reminder_os_state, "unknown",
		"os state defaults unknown")
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 0,
		"nothing schedules while off")
	_expect_equal(_bridge.cancels, 0, "nothing cancels while off")


func _test_enable_grant_schedules() -> void:
	_clean_reminder_state()
	var eligible: String = _future_utc(10800)
	_host.live(FAKE_ID, eligible, 10800)
	_controller.user_enable()
	_expect_true(Settings.reminders_enabled,
		"enable persists the intent")
	_expect_equal(_bridge.permission_ids.size(), 1,
		"enable asks the OS once")
	_expect_equal(_bridge.schedule_log.size(), 0,
		"nothing schedules before the grant")
	_bridge.answer_permission(true)
	_expect_equal(_bridge.schedule_log.size(), 1,
		"grant schedules one delivery")
	var args: Dictionary = _bridge.schedule_log[0]
	var unix: int = int(
		Time.get_unix_time_from_datetime_string(
			eligible.left(eligible.length() - 1)))
	_expect_equal(int(args["eligible_utc_millis"]), unix * 1000,
		"first fire targets the server deadline")
	_expect_equal(str(args["account"]), FAKE_ID,
		"schedule names the owning account")
	_expect_equal(str(args["locale"]), Settings.locale,
		"schedule names the text locale")
	_expect_false(str(args["title"]).is_empty(),
		"schedule carries a title")
	_expect_false(str(args["body"]).is_empty(),
		"schedule carries a body")
	_expect_false(args.has("repeat_seconds"),
		"no short repeat leaks into the native call")
	_expect_equal(Settings.reminder_sched_account, FAKE_ID,
		"scheduled account recorded")
	_expect_equal(Settings.reminder_sched_eligible_utc, eligible,
		"scheduled deadline recorded")
	_expect_equal(Settings.reminder_os_state, "granted",
		"os state cached granted")


func _test_reschedule_skips_when_unchanged() -> void:
	_controller.refresh()
	_host.publish()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"identical refresh never reschedules")


func _test_locale_change_reschedules() -> void:
	# The suite default follows the device (en here), so a hardcoded
	# "en" change is a no-op: the old pass secretly relied on the
	# host controller's interference clearing the record first. Pick
	# a genuinely different locale and restore the original after.
	var before: String = Settings.locale
	var other: String = "ko" if before != "ko" else "en"
	Settings.locale = other
	Settings.save_settings()
	Settings.changed.emit()
	_expect_equal(_bridge.schedule_log.size(), 2,
		"locale change reschedules the text")
	_expect_equal(str(_bridge.schedule_log[1]["locale"]), other,
		"reschedule names the new locale")
	_expect_equal(Settings.reminder_sched_locale, other,
		"recorded locale follows")
	Settings.locale = before
	Settings.save_settings()


func _test_new_reward_reschedules() -> void:
	var eligible: String = _future_utc(21600)
	_host.live(FAKE_ID, eligible, 21600)
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 3,
		"new reward reschedules")
	_expect_equal(Settings.reminder_sched_eligible_utc, eligible,
		"recorded deadline follows the reward")


func _test_eligible_now_schedules_same_anchor() -> void:
	# An expired known anchor still schedules: the foreground claim
	# may never come (an offline return that leaves again), so the
	# native side plans future-only slots from the same deadline
	# instead of starving on an exhausted horizon.
	var eligible: String = _future_utc(10800)
	_host.live(FAKE_ID, eligible, 0)
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 4,
		"expired anchor schedules once")
	var args: Dictionary = _bridge.schedule_log[3]
	var unix: int = int(
		Time.get_unix_time_from_datetime_string(
			eligible.left(eligible.length() - 1)))
	_expect_equal(int(args["eligible_utc_millis"]), unix * 1000,
		"expired anchor keeps its deadline")
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 4,
		"expired anchor skips while held")


func _test_short_window_schedules_first_delay() -> void:
	# The director's thirty-second probe: newly enabled, permission
	# granted, eligibility half a minute out. This must send one
	# schedule with the confirmed future deadline; the native side
	# carries it as the first delay under twelve-hour repeats.
	var eligible: String = _future_utc(30)
	_host.live(FAKE_ID, eligible, 30)
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 5,
		"thirty-second window schedules one delivery")
	var args: Dictionary = _bridge.schedule_log[4]
	var unix: int = int(
		Time.get_unix_time_from_datetime_string(
			eligible.left(eligible.length() - 1)))
	_expect_equal(int(args["eligible_utc_millis"]), unix * 1000,
		"short window targets the confirmed deadline")
	_expect_false(args.has("repeat_seconds"),
		"short window never becomes a short repeat")


func _test_bad_deadline_schedules_nothing() -> void:
	_host.live(FAKE_ID, "not-a-time", 10800)
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 5,
		"unparseable deadline arms nothing")


func _test_unknown_source_keeps_existing() -> void:
	_host.view = {"state": "unregistered", "source": "none",
		"public_id": FAKE_ID, "receipt": "", "last_claim_utc": "",
		"next_eligible_utc": "", "remaining_seconds": -1}
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 5,
		"unknown source schedules nothing new")
	_expect_equal(_bridge.cancels, 0,
		"unknown source cancels nothing known")


func _test_cached_deadline_schedules() -> void:
	_clean_reminder_state()
	_bridge.permission = "granted"
	Settings.set_reminders_enabled(true)
	var eligible: String = _future_utc(7200)
	_host.view = {"state": "cooldown", "source": "cache",
		"public_id": FAKE_ID, "receipt": "", "last_claim_utc": "",
		"next_eligible_utc": eligible, "remaining_seconds": 7200}
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"cached deadline schedules a reminder")
	_expect_equal(Settings.reminder_sched_account, FAKE_ID,
		"cached schedule records its owner")


func _test_live_denial_blocks_schedule() -> void:
	_clean_reminder_state()
	_bridge.permission = "denied"
	Settings.set_reminders_enabled(true)
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 0,
		"live denial schedules nothing")
	_expect_equal(Settings.reminder_os_state, "denied",
		"live denial cached for display")


func _test_toggle_from_denied_opens_settings() -> void:
	_clean_reminder_state()
	Settings.set_reminder_os_state("denied")
	_controller.user_toggle()
	_expect_equal(_bridge.opens, 1,
		"off plus denied opens OS settings")
	_expect_false(Settings.reminders_enabled,
		"opening settings enables nothing")
	_expect_equal(_bridge.schedule_log.size(), 0,
		"opening settings schedules nothing")


func _test_disable_cancels_and_seals() -> void:
	_clean_reminder_state()
	_bridge.permission = "granted"
	Settings.set_reminders_enabled(true)
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"disable test schedules first")
	_controller.user_disable()
	_expect_equal(_bridge.cancels, 1,
		"disable cancels the native delivery")
	_expect_true(Settings.reminder_sched_account.is_empty(),
		"disable forgets the schedule")
	_expect_false(Settings.reminders_enabled,
		"disable persists off")
	_expect_true(FileAccess.file_exists(
		Settings.REMINDER_DISABLED_PATH),
		"disable writes its own mark")
	# A stale enabled file under the mark still boots off.
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(Settings.SECTION, "reminders_enabled", true)
	cfg.save(Settings.SAVE_PATH)
	Settings.reminders_enabled = true
	Settings.load_settings()
	_expect_false(Settings.reminders_enabled,
		"the mark outranks a stale enabled file")


func _remove_temp_blocker() -> void:
	var absolute: String = ProjectSettings.globalize_path(
		Settings.TEMP_SAVE_PATH)
	if DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)
	elif FileAccess.file_exists(Settings.TEMP_SAVE_PATH):
		DirAccess.remove_absolute(absolute)


func _test_save_failure_stays_off() -> void:
	_clean_reminder_state()
	_remove_temp_blocker()
	var absolute: String = ProjectSettings.globalize_path(
		Settings.TEMP_SAVE_PATH)
	_expect_equal(DirAccess.make_dir_absolute(absolute), OK,
		"temp path blocked with a directory")
	_expect_false(Settings.set_reminders_enabled(true),
		"enable reports its failed save")
	_expect_false(Settings.reminders_enabled,
		"failed enable stays off")
	_expect_false(Settings.record_reminder_schedule(
		FAKE_ID, _future_utc(10800), "ko"),
		"failed schedule record reports false")
	_remove_temp_blocker()
	_expect_true(Settings.set_reminders_enabled(true),
		"retry after the fault persists")
	_expect_true(Settings.reminders_enabled,
		"retry after the fault sticks")


func _test_stale_permission_dropped() -> void:
	_clean_reminder_state()
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.user_enable()
	_expect_equal(_bridge.permission_ids.size(), 1,
		"stale test asks once")
	_controller.configure(_host, _bridge)
	_bridge.answer_permission(true)
	_expect_equal(_bridge.schedule_log.size(), 0,
		"answer past a rewire schedules nothing")
	_bridge.answer_stale()
	_expect_equal(_bridge.schedule_log.size(), 0,
		"answer for an unknown id schedules nothing")
	_controller.user_enable()
	_bridge.answer_permission(true)
	_expect_equal(_bridge.schedule_log.size(), 1,
		"fresh enable after the stale answer schedules")


func _test_account_switch_retires() -> void:
	_clean_reminder_state()
	_bridge.permission = "granted"
	Settings.set_reminders_enabled(true)
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"switch test schedules first")
	var eligible: String = _future_utc(9000)
	_host.live(OTHER_ID, eligible, 9000)
	_controller.refresh()
	_expect_equal(_bridge.cancels, 1,
		"switch cancels the old owner's delivery")
	_expect_equal(_bridge.schedule_log.size(), 1,
		"switch schedules the new owner")
	_expect_equal(str(_bridge.schedule_log[0]["account"]),
		OTHER_ID, "new schedule names the new owner")
	_expect_equal(Settings.reminder_sched_account, OTHER_ID,
		"recorded owner follows the switch")


func _test_sign_out_retires() -> void:
	_host.view = {"state": "unregistered", "source": "none",
		"public_id": "", "receipt": "", "last_claim_utc": "",
		"next_eligible_utc": "", "remaining_seconds": -1}
	_controller.refresh()
	_expect_equal(_bridge.cancels, 2,
		"sign-out cancels the delivery")
	_expect_true(Settings.reminder_sched_account.is_empty(),
		"sign-out forgets the schedule")


func _test_unsupported_bridge_honest() -> void:
	_clean_reminder_state()
	_controller.configure(_host, null)
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.user_enable()
	_expect_false(Settings.reminders_enabled,
		"unsupported enable persists nothing")
	_expect_equal(Settings.reminder_os_state, "unsupported",
		"unsupported cached for display")
	_controller.refresh()
	_expect_equal(Settings.reminder_os_state, "unsupported",
		"refresh stays honestly unsupported")
	_expect_equal(_controller.offer_for_receipt(), "",
		"no offer where no bridge exists")
	_controller.configure(_host, _bridge)


func _test_receipt_offer_once() -> void:
	_clean_reminder_state()
	_expect_equal(_controller.offer_for_receipt(),
		tr("REMINDER_OFFER"), "first receipt offers once")
	_expect_true(Settings.reminder_receipt_offered,
		"offer marks itself shown")
	_expect_equal(_controller.offer_for_receipt(), "",
		"second receipt offers nothing")
	Settings.set_reminders_enabled(true)
	Settings.reminder_receipt_offered = false
	_expect_equal(_controller.offer_for_receipt(), "",
		"enabled accounts are never offered")


func _test_permission_denial_not_enabled() -> void:
	_clean_reminder_state()
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.user_enable()
	_bridge.answer_permission(false)
	_expect_equal(Settings.reminder_os_state, "denied",
		"denial cached for display")
	_expect_equal(_bridge.schedule_log.size(), 0,
		"denial schedules nothing")
	_controller.user_toggle()
	_expect_false(Settings.reminders_enabled,
		"tap from denied disables")
	_expect_equal(_bridge.cancels, 1,
		"tap from denied cancels")


func _test_native_schedule_denial_not_recorded() -> void:
	_clean_reminder_state()
	_bridge.permission = "granted"
	_bridge.schedule_receipt = {"status": "denied",
		"permission": "denied", "code": "permission_denied"}
	Settings.set_reminders_enabled(true)
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.refresh()
	_expect_true(Settings.reminder_sched_account.is_empty(),
		"refused schedule records nothing")
	_expect_equal(Settings.reminder_os_state, "denied",
		"refused schedule caches the denial")


func _test_native_status_unsupported_clears() -> void:
	_clean_reminder_state()
	Settings.set_reminders_enabled(true)
	Settings.record_reminder_schedule(
		FAKE_ID, _future_utc(7200), "ko")
	_bridge.status_receipt = {"status": "unsupported",
		"code": "native_bridge_unavailable"}
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.refresh()
	_expect_equal(Settings.reminder_os_state, "unsupported",
		"lost native cached for display")
	_expect_true(Settings.reminder_sched_account.is_empty(),
		"lost native clears the stale record")
	_expect_equal(_bridge.cancels, 1,
		"lost native cancels defensively")


func _test_transient_native_error_keeps_schedule() -> void:
	_clean_reminder_state()
	Settings.set_reminders_enabled(true)
	var kept: String = _future_utc(7200)
	Settings.record_reminder_schedule(FAKE_ID, kept, "ko")
	# Direct display-cache set, no emit: the host autoload owns a
	# second controller in this scene, and an emit between plant and
	# assert would let it retire the shared record through the real
	# bridge before the error path under test runs.
	Settings.reminder_os_state = "granted"
	_bridge.status_receipt = {"status": "error",
		"code": "no_activity", "retryable": true}
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.refresh()
	_expect_equal(Settings.reminder_sched_account, FAKE_ID,
		"transient error keeps the owned record")
	_expect_equal(Settings.reminder_sched_eligible_utc, kept,
		"transient error keeps the owned deadline")
	_expect_equal(Settings.reminder_os_state, "granted",
		"transient error keeps the cached display state")
	_expect_equal(_bridge.cancels, 0,
		"transient error cancels nothing")
	_expect_equal(_bridge.schedule_log.size(), 0,
		"transient error schedules nothing")
	_bridge.status_receipt = {}
	_bridge.permission = "granted"
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"recovery after the outage converges")


func _test_revocation_surfaces_on_same_deadline() -> void:
	_clean_reminder_state()
	_bridge.permission = "granted"
	Settings.set_reminders_enabled(true)
	var eligible: String = _future_utc(10800)
	_host.live(FAKE_ID, eligible, 10800)
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"revocation: the grant schedules once")
	_expect_equal(Settings.reminder_os_state, "granted",
		"revocation: the grant caches granted")
	_bridge.permission = "denied"
	_controller.refresh()
	_expect_equal(Settings.reminder_os_state, "denied",
		"revocation: the same deadline surfaces denied")
	_expect_equal(Settings.reminder_sched_account, FAKE_ID,
		"revocation: denial keeps the owned record")
	_expect_equal(_bridge.cancels, 0,
		"revocation: denial cancels nothing native")
	_expect_equal(_bridge.schedule_log.size(), 1,
		"revocation: denial schedules nothing new")
	_bridge.permission = "granted"
	_controller.refresh()
	_expect_equal(Settings.reminder_os_state, "granted",
		"revocation: a re-grant caches granted again")
	_expect_equal(_bridge.schedule_log.size(), 1,
		"revocation: the re-grant reschedules nothing held")


func _test_async_status_converges() -> void:
	_clean_reminder_state()
	_bridge.status_behavior = "pending"
	Settings.set_reminders_enabled(true)
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 0,
		"async: nothing schedules before the verdict")
	_expect_equal(Settings.reminder_os_state, "unknown",
		"async: the cache stands while pending")
	_bridge.answer_status({"status": "ok", "permission": "granted"})
	_expect_equal(Settings.reminder_os_state, "granted",
		"async: the granted outcome caches granted")
	_expect_equal(_bridge.schedule_log.size(), 1,
		"async: the granted outcome schedules once")
	_controller.refresh()
	_bridge.answer_status({"status": "ok", "permission": "granted"})
	_expect_equal(_bridge.schedule_log.size(), 1,
		"async: the held schedule never duplicates")
	_bridge.answer_status({"status": "ok", "permission": "denied"})
	_expect_equal(Settings.reminder_os_state, "granted",
		"async: a spent id settles nothing twice")
	_expect_equal(_bridge.schedule_log.size(), 1,
		"async: a spent id schedules nothing")
	_bridge.request_completed.emit({"status": "ok",
		"permission": "denied", "request_id": "stat-stale"})
	_expect_equal(Settings.reminder_os_state, "granted",
		"async: a stale id settles nothing")
	_controller._apply_status_outcome({"status": "ok",
		"permission": "denied"}, 999)
	_expect_equal(Settings.reminder_os_state, "granted",
		"async: a foreign generation settles nothing")


func _test_async_denial_schedules_nothing() -> void:
	_clean_reminder_state()
	_bridge.status_behavior = "pending"
	Settings.set_reminders_enabled(true)
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.refresh()
	_bridge.answer_status({"status": "ok", "permission": "denied"})
	_expect_equal(Settings.reminder_os_state, "denied",
		"async denial: the outcome caches denied")
	_expect_equal(_bridge.schedule_log.size(), 0,
		"async denial: nothing schedules")
	_expect_true(Settings.reminder_sched_account.is_empty(),
		"async denial: nothing records")
	_bridge.status_behavior = "sync"
	_bridge.permission = "granted"
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"async denial: a later grant still schedules")


func _test_pending_status_still_offers() -> void:
	_clean_reminder_state()
	_bridge.status_behavior = "pending"
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	var offer: String = _controller.offer_for_receipt()
	_expect_equal(offer, tr("REMINDER_OFFER"),
		"pending: the unknown verdict still offers once")
	_expect_true(Settings.reminder_receipt_offered,
		"pending: the offer marks itself shown")
	_expect_equal(_bridge.status_ids.size(), 1,
		"pending: the offer waits on the verdict")
	_bridge.answer_status({"status": "ok", "permission": "granted"})
	_expect_equal(Settings.reminder_os_state, "granted",
		"pending: the verdict still converges")


func _test_async_timeout_keeps_cache() -> void:
	_clean_reminder_state()
	_bridge.status_behavior = "pending"
	Settings.set_reminders_enabled(true)
	Settings.reminder_os_state = "granted"
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.refresh()
	_bridge.answer_status({"status": "error", "code": "request_timeout",
		"retryable": true})
	_expect_equal(Settings.reminder_os_state, "granted",
		"async timeout: the cache stands")
	_expect_equal(_bridge.schedule_log.size(), 0,
		"async timeout: nothing schedules")
	_expect_equal(_bridge.cancels, 0,
		"async timeout: nothing cancels")


func _test_horizon_window_matrix() -> void:
	# Shared agreement vectors with the native planner test
	# (scripts/lib/reminder-planner.test.mjs): whole-second stamps so
	# both integer-millisecond sides agree bit-for-bit.
	var anchor: int = 1700000000
	var interval: int = AttendanceReminders.REPEAT_SECONDS
	var now: float = Time.get_unix_time_from_system()
	_expect_true(AttendanceReminders._horizon_holds(
		-1.0, -1, anchor, now, "iOS"),
		"window: unbounded holds on iOS")
	_expect_true(AttendanceReminders._horizon_holds(
		-1.0, -1, anchor, now, "Android"),
		"window: unbounded holds anywhere")
	_expect_true(AttendanceReminders._horizon_holds(
		0.0, -1, anchor, now, "Android"),
		"window: legacy holds repeating")
	_expect_false(AttendanceReminders._horizon_holds(
		0.0, -1, anchor, now, "iOS"),
		"window: legacy iOS replans once")
	_expect_true(AttendanceReminders._horizon_holds(
		_window_end(anchor, 0), 0, anchor, float(anchor),
		"iOS"), "window: exact eligibility holds")
	_expect_true(AttendanceReminders._horizon_holds(
		_window_end(anchor, 0), 0, anchor,
		float(anchor + 39 * interval), "iOS"),
		"window: nine future slots hold")
	_expect_true(AttendanceReminders._horizon_holds(
		_window_end(anchor, 0), 0, anchor,
		float(anchor + 40 * interval), "iOS"),
		"window: eight future slots hold")
	_expect_true(AttendanceReminders._horizon_holds(
		_window_end(anchor, 0), 0, anchor,
		float(anchor + 39 * interval + 21600), "iOS"),
		"window: eight future slots hold mid-slot")
	_expect_false(AttendanceReminders._horizon_holds(
		_window_end(anchor, 0), 0, anchor,
		float(anchor + 41 * interval), "iOS"),
		"window: seven future slots refill")
	_expect_false(AttendanceReminders._horizon_holds(
		_window_end(anchor, 0), 0, anchor,
		float(anchor + 40 * interval + 21600), "iOS"),
		"window: seven future slots refill mid-slot")
	_expect_false(AttendanceReminders._horizon_holds(
		_window_end(anchor, 0), 0, anchor,
		float(anchor + 50 * interval), "iOS"),
		"window: day twenty-five exhausts the old window")
	_expect_true(AttendanceReminders._horizon_holds(
		_window_end(anchor, 50), 50, anchor,
		float(anchor + 50 * interval), "iOS"),
		"window: day twenty-five holds its refilled window")
	_expect_false(AttendanceReminders._horizon_holds(
		_window_end(anchor, 40), 40, anchor, float(anchor),
		"iOS"), "window: a base ahead of now refills")
	_expect_true(AttendanceReminders._horizon_holds(
		_window_end(anchor, 0), -1, anchor,
		float(anchor + 40 * interval), "iOS"),
		"window: a legacy end derives its base and holds")
	_expect_false(AttendanceReminders._horizon_holds(
		_window_end(anchor, 0) + 1.0, -1, anchor,
		float(anchor + 40 * interval), "iOS"),
		"window: an off-grid legacy end replans once")
	_expect_false(AttendanceReminders._horizon_holds(
		float(anchor + 10 * interval), -1, anchor,
		float(anchor + 40 * interval), "iOS"),
		"window: a short legacy end replans once")


func _test_refill_window_reschedules_same_anchor() -> void:
	_clean_reminder_state()
	_bridge.permission = "granted"
	var now: int = int(Time.get_unix_time_from_system())
	# Expired 21 days and an hour: first future is slot 43, one hour
	# from either grid edge so the live clock cannot flake it.
	var anchor_unix: int = now - 21 * 86400 - 3600
	var eligible: String = Time.get_datetime_string_from_unix_time(
		anchor_unix, true) + "Z"
	var first_end: float = _window_end(anchor_unix, 0)
	_bridge.schedule_receipt = {"status": "ok",
		"eligible_millis": anchor_unix * 1000,
		"base_slot": 0, "scheduled_slots": 5,
		"horizon_end_unix": first_end}
	Settings.set_reminders_enabled(true)
	_host.live(FAKE_ID, eligible, 0)
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"refill: the expired anchor schedules")
	_expect_equal(Settings.reminder_sched_horizon_end, first_end,
		"refill: the receipt end records")
	_expect_equal(Settings.reminder_sched_base_slot, 0,
		"refill: the receipt base records")
	var second_end: float = _window_end(anchor_unix, 43)
	_bridge.schedule_receipt = {"status": "ok",
		"eligible_millis": anchor_unix * 1000,
		"base_slot": 43, "scheduled_slots": 48,
		"horizon_end_unix": second_end}
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 2,
		"refill: the consumed window re-asks the native side")
	var first: Dictionary = _bridge.schedule_log[0]
	var second: Dictionary = _bridge.schedule_log[1]
	_expect_equal(int(second["eligible_utc_millis"]),
		int(first["eligible_utc_millis"]),
		"refill: the re-ask keeps the same anchor")
	_expect_equal(Settings.reminder_sched_eligible_utc, eligible,
		"refill: the recorded deadline never moves")
	_expect_equal(Settings.reminder_sched_horizon_end, second_end,
		"refill: the new end records")
	_expect_equal(Settings.reminder_sched_base_slot, 43,
		"refill: the new base records")
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 2,
		"refill: the full window skips again")


func _test_pending_status_then_off_ignores_late_grant() -> void:
	_clean_reminder_state()
	_bridge.status_behavior = "pending"
	Settings.set_reminders_enabled(true)
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 0,
		"late grant: nothing schedules before the verdict")
	_controller.user_disable()
	_expect_false(Settings.reminders_enabled,
		"late grant: the tap turns intent off")
	_bridge.answer_status({"status": "ok", "permission": "granted"})
	_expect_equal(Settings.reminder_os_state, "granted",
		"late grant: the OS cache still updates while off")
	_expect_equal(_bridge.schedule_log.size(), 0,
		"late grant: no delivery after off")
	_expect_true(Settings.reminder_sched_account.is_empty(),
		"late grant: the record stays cleared")


func _test_pending_status_then_source_none_schedules_nothing() -> void:
	_clean_reminder_state()
	_bridge.status_behavior = "pending"
	Settings.set_reminders_enabled(true)
	var eligible: String = _future_utc(10800)
	_host.live(FAKE_ID, eligible, 10800)
	_controller.refresh()
	# The account scope drops out but the dict retains its stale
	# deadline fields: a schedule must read the source, not them.
	_host.view = {"state": "unregistered", "source": "none",
		"public_id": FAKE_ID, "receipt": "r",
		"last_claim_utc": "2026-10-07T00:00:00Z",
		"next_eligible_utc": eligible, "remaining_seconds": 10800}
	_bridge.answer_status({"status": "ok", "permission": "granted"})
	_expect_equal(_bridge.schedule_log.size(), 0,
		"source none: retained fields schedule nothing")
	_expect_true(Settings.reminder_sched_account.is_empty(),
		"source none: nothing records")


func _test_reenable_after_late_grant_schedules_once() -> void:
	_clean_reminder_state()
	_bridge.status_behavior = "pending"
	Settings.set_reminders_enabled(true)
	_host.live(FAKE_ID, _future_utc(10800), 10800)
	_controller.refresh()
	_controller.user_disable()
	_bridge.answer_status({"status": "ok", "permission": "granted"})
	_expect_equal(_bridge.schedule_log.size(), 0,
		"re-enable: the late grant schedules nothing while off")
	_controller.user_enable()
	_expect_equal(_bridge.schedule_log.size(), 0,
		"re-enable: nothing schedules before the re-grant")
	_bridge.answer_permission(true)
	_bridge.answer_status({"status": "ok", "permission": "granted"})
	_expect_equal(_bridge.schedule_log.size(), 1,
		"re-enable: a genuine view schedules once")
	_controller.refresh()
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"re-enable: held refreshes never duplicate")


func _test_expired_cache_schedules_once() -> void:
	_clean_reminder_state()
	_bridge.permission = "granted"
	Settings.set_reminders_enabled(true)
	var now: int = int(Time.get_unix_time_from_system())
	# Offline return 25 days out: the cached deadline is long past
	# (first future slot 51), but the native side still plans 48
	# future slots from it instead of starving.
	var anchor_unix: int = now - 25 * 86400 - 3600
	var eligible: String = Time.get_datetime_string_from_unix_time(
		anchor_unix, true) + "Z"
	var coins: int = Vault.continue_coins
	_host.view = {"state": "cooldown", "source": "cache",
		"public_id": FAKE_ID, "receipt": "r",
		"last_claim_utc": "2026-10-07T00:00:00Z",
		"next_eligible_utc": eligible, "remaining_seconds": 0}
	_bridge.schedule_receipt = {"status": "ok",
		"eligible_millis": anchor_unix * 1000,
		"base_slot": 51, "scheduled_slots": 48,
		"horizon_end_unix": _window_end(anchor_unix, 51)}
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"expired cache schedules once")
	var args: Dictionary = _bridge.schedule_log[0]
	_expect_equal(int(args["eligible_utc_millis"]),
		anchor_unix * 1000,
		"expired cache keeps its anchor")
	_expect_equal(Vault.continue_coins, coins,
		"expired cache grants no coins")
	_controller.refresh()
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"expired cache skips while held")
	_expect_equal(Vault.continue_coins, coins,
		"held refreshes grant no coins")
	_expect_equal(Settings.reminder_sched_base_slot, 51,
		"expired cache records its base")


func _test_duplicate_receipt_keeps_known_end() -> void:
	_clean_reminder_state()
	_bridge.permission = "granted"
	Settings.set_reminders_enabled(true)
	var now: int = int(Time.get_unix_time_from_system())
	var anchor_unix: int = now - 21 * 86400 - 3600
	var eligible: String = Time.get_datetime_string_from_unix_time(
		anchor_unix, true) + "Z"
	var end: float = _window_end(anchor_unix, 0)
	# A consumed window answered by a metadata-less duplicate keeps
	# its known metadata instead of recording an unknown zero.
	_bridge.schedule_receipt = {"status": "ok",
		"eligible_millis": anchor_unix * 1000,
		"base_slot": 0, "scheduled_slots": 5,
		"horizon_end_unix": end}
	_host.live(FAKE_ID, eligible, 0)
	_controller.refresh()
	_bridge.schedule_receipt = {"status": "ok", "duplicate": true,
		"eligible_millis": anchor_unix * 1000}
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 2,
		"duplicate: the consumed window re-asks once")
	_expect_equal(Settings.reminder_sched_horizon_end, end,
		"duplicate: the known end survives a bare duplicate")
	_expect_equal(Settings.reminder_sched_base_slot, 0,
		"duplicate: the known base survives a bare duplicate")
	# And a truthful duplicate on a held window never re-asks: four
	# refreshes, one schedule, no self-sustaining loop.
	_clean_reminder_state()
	_bridge.permission = "granted"
	Settings.set_reminders_enabled(true)
	var fresh_unix: int = now + 7200
	var fresh: String = Time.get_datetime_string_from_unix_time(
		fresh_unix, true) + "Z"
	var fresh_end: float = _window_end(fresh_unix, 0)
	_bridge.schedule_receipt = {"status": "ok", "duplicate": true,
		"eligible_millis": fresh_unix * 1000,
		"base_slot": 0, "scheduled_slots": 48,
		"horizon_end_unix": fresh_end}
	_host.live(FAKE_ID, fresh, 7200)
	_controller.refresh()
	_controller.refresh()
	_controller.refresh()
	_controller.refresh()
	_expect_equal(_bridge.schedule_log.size(), 1,
		"duplicate: a held window never re-asks")
	_expect_equal(Settings.reminder_sched_horizon_end, fresh_end,
		"duplicate: the held end records")
	_expect_equal(Settings.reminder_sched_base_slot, 0,
		"duplicate: the held base records")


func _test_panel_without_analytics() -> void:
	_clean_reminder_state()
	Analytics._test_configure(false, false)
	var panel: Control = PANEL_SCENE.instantiate() as Control
	add_child(panel)
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var reminder: Button = panel.get_node("Reminder") as Button
	var label: Label = panel.get_node("ReminderLabel") as Label
	_expect_false(
		(panel.get_node("Analytics") as Button).visible,
		"analytics stays hidden while unconfigured")
	_expect_true(label.visible,
		"reminder label renders without analytics")
	_expect_true(reminder.visible,
		"reminder row renders without analytics")
	# Opening refreshes the live permission: headless has no native
	# side, so the row must land on an honest unsupported instead of a
	# fake scheduled success.
	_expect_equal(Settings.reminder_os_state, "unsupported",
		"open without a native stays honestly unsupported")
	_expect_equal(reminder.text,
		tr("SETTINGS_REMINDERS_UNSUPPORTED"),
		"row labels the unsupported state")
	_expect_true(reminder.disabled,
		"unsupported row takes no taps")
	# Reset to off, then press through the real autoload controller:
	# the enable attempt must converge back to unsupported.
	Settings.reminders_enabled = false
	Settings.reminder_os_state = "unknown"
	Settings.changed.emit()
	await get_tree().process_frame
	_expect_false(reminder.disabled,
		"off row stays tappable without analytics")
	reminder.pressed.emit()
	await get_tree().process_frame
	_expect_equal(Settings.reminder_os_state, "unsupported",
		"press without a native converges to unsupported")
	panel.queue_free()
	await get_tree().process_frame
	Settings.set_reminders_enabled(false)
	Analytics._test_mode = false


func _test_panel_builds_reminder_row_on_open() -> void:
	_clean_reminder_state()
	var panel: Control = PANEL_SCENE.instantiate() as Control
	add_child(panel)
	await get_tree().process_frame
	_expect_true(panel.get_node_or_null("Reminder") == null,
		"lazy: a closed panel carries no Reminder button")
	_expect_true(panel.get_node_or_null("ReminderLabel") == null,
		"lazy: a closed panel carries no Reminder label")
	panel.open()
	await get_tree().process_frame
	var reminder: Button = panel.get_node("Reminder") as Button
	var label: Label = panel.get_node("ReminderLabel") as Label
	_expect_true(reminder is WorldButton,
		"lazy: the opened row is a steel world button")
	_expect_equal((reminder as WorldButton).kind, "steel",
		"lazy: the opened row keeps its kind")
	_expect_equal(reminder.offset_left, -36.0,
		"lazy: the button keeps its scene seat")
	_expect_equal(reminder.offset_top, 49.0,
		"lazy: the button keeps its scene row")
	_expect_equal(reminder.offset_right, 172.0,
		"lazy: the button keeps its scene width")
	_expect_equal(reminder.offset_bottom, 83.0,
		"lazy: the button keeps its scene height")
	_expect_equal(label.offset_left, -172.0,
		"lazy: the label keeps its scene seat")
	_expect_equal(label.offset_right, -44.0,
		"lazy: the label keeps its scene width")
	_expect_equal(reminder.get_theme_font_size("font_size"), 13,
		"lazy: the button keeps its scene font size")
	var lazy_fs: int = label.get_theme_font_size("font_size")
	_expect_true(lazy_fs >= 11 and lazy_fs <= 15,
		"lazy: the label fits within readable sizes (got %d)" % lazy_fs)
	var lazy_font: Font = label.get_theme_font("font")
	var lazy_width: float = lazy_font.get_string_size(
		label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		float(lazy_fs)).x
	_expect_true(lazy_width <= 128.0 + 0.5,
		"lazy: the label text fits its column (%s)" % lazy_width)
	_expect_true(label.get_combined_minimum_size().x <= 128.0 + 0.5,
		"lazy: the label minimum fits its column")
	_expect_equal(label.text, tr("SETTINGS_REMINDERS"),
		"lazy: the label names reminders")
	var lazy_label_rect: Rect2 = label.get_global_rect()
	var lazy_button_rect: Rect2 = reminder.get_global_rect()
	_expect_true(
		lazy_label_rect.end.x <= lazy_button_rect.position.x + 0.5,
		"lazy: the label rect stays clear of the button (%s / %s)" % [
			lazy_label_rect, lazy_button_rect])
	panel.open()
	await get_tree().process_frame
	var copies: int = 0
	var label_copies: int = 0
	for child in panel.get_children():
		if (child as Node).name == &"Reminder":
			copies += 1
		if (child as Node).name == &"ReminderLabel":
			label_copies += 1
	_expect_equal(copies, 1,
		"lazy: a second open builds no second row")
	_expect_equal(label_copies, 1,
		"lazy: a second open builds no second label")
	panel.queue_free()
	await get_tree().process_frame


func _test_unknown_row_never_shows_on() -> void:
	_clean_reminder_state()
	var panel: Control = PANEL_SCENE.instantiate() as Control
	add_child(panel)
	panel.open()
	await get_tree().process_frame
	Settings.reminders_enabled = true
	Settings.reminder_os_state = "unknown"
	Settings.changed.emit()
	await get_tree().process_frame
	var reminder: Button = panel.get_node("Reminder") as Button
	_expect_equal(reminder.text, tr("SETTINGS_REMINDERS_UNKNOWN"),
		"unknown: an undetermined state never shows as on")
	_expect_false(reminder.disabled,
		"unknown: the row stays tappable")
	reminder.pressed.emit()
	await get_tree().process_frame
	_expect_false(Settings.reminders_enabled,
		"unknown: a tap disables like a denial")
	panel.queue_free()
	await get_tree().process_frame
	Settings.set_reminders_enabled(false)


func _test_panel_fits_locales() -> void:
	_clean_reminder_state()
	var original_locale: String = TranslationServer.get_locale()
	var original_size: Vector2i = get_tree().root.size
	var framings: Array[Vector2i] = [
		Vector2i(808, 360), Vector2i(808, 532),
		Vector2i(808, 606)]
	for framing in framings:
		get_tree().root.size = framing
		get_tree().root.content_scale_size = framing
		await get_tree().process_frame
		for locale in LOCALES:
			TranslationServer.set_locale(locale)
			Settings.locale = locale
			await _check_panel_framing(framing, locale)
	TranslationServer.set_locale(original_locale)
	Settings.locale = str(_original_settings["locale"])
	get_tree().root.size = original_size
	get_tree().root.content_scale_size = original_size
	await get_tree().process_frame


func _check_panel_framing(framing: Vector2i,
		locale: String) -> void:
	var states: Array = [
		{"enabled": false, "os": "unknown"},
		{"enabled": true, "os": "granted"},
		{"enabled": true, "os": "denied"},
		{"enabled": true, "os": "unknown"},
		{"enabled": false, "os": "unsupported"},
	]
	var panel: Control = PANEL_SCENE.instantiate() as Control
	add_child(panel)
	panel.open()
	await get_tree().process_frame
	for state in states:
		Settings.reminders_enabled = bool(state["enabled"])
		Settings.reminder_os_state = str(state["os"])
		Settings.changed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(framing))
		var safe: Rect2 = bounds.grow(-12.0)
		for path in ["Reminder", "ReminderLabel", "Credits",
				"Close", "ExternalLinks", "LinkStatus"]:
			var node: Control = panel.get_node(path) as Control
			_expect_true(safe.encloses(node.get_global_rect()),
				"%s %s keeps %s in the safe area" % [
					framing, locale, path])
		var card: Control = panel.get_node("Card") as Control
		_expect_true(bounds.encloses(card.get_global_rect()),
			"%s %s keeps the card on screen" % [
				framing, locale])
		var reminder: Button = panel.get_node("Reminder")
		var font: Font = reminder.get_theme_font("font")
		var font_size: int = reminder.get_theme_font_size(
			"font_size")
		var text_width: float = font.get_string_size(
			reminder.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			float(font_size)).x
		_expect_true(text_width <= 196.0 + 0.5,
			"%s %s reminder text fits its button (%s)" % [
				framing, locale, state["os"]])
		_expect_true(font_size >= 9 and font_size <= 13,
			"%s %s reminder button stays readable (%s)" % [
				framing, locale, state["os"]])
		var expected_key: String = "SETTINGS_REMINDERS_OFF"
		if str(state["os"]) == "unsupported":
			expected_key = "SETTINGS_REMINDERS_UNSUPPORTED"
		elif bool(state["enabled"]) \
				and str(state["os"]) == "denied":
			expected_key = "SETTINGS_REMINDERS_DENIED"
		elif bool(state["enabled"]) \
				and str(state["os"]) == "unknown":
			expected_key = "SETTINGS_REMINDERS_UNKNOWN"
		elif bool(state["enabled"]):
			expected_key = "SETTINGS_REMINDERS_ON"
		_expect_equal(reminder.text, tr(expected_key),
			"%s %s reminder names its state (%s)" % [
				framing, locale, state["os"]])
		var row_label: Label = panel.get_node("ReminderLabel")
		_expect_equal(row_label.text, tr("SETTINGS_REMINDERS"),
			"%s %s label keeps its full copy (%s)" % [
				framing, locale, state["os"]])
		var label_fs: int = row_label.get_theme_font_size(
			"font_size")
		_expect_true(label_fs >= 11 and label_fs <= 15,
			"%s %s label stays readable (%s)" % [
				framing, locale, state["os"]])
		var label_font: Font = row_label.get_theme_font("font")
		var label_width: float = label_font.get_string_size(
			row_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			float(label_fs)).x
		_expect_true(label_width <= 128.0 + 0.5,
			"%s %s label text fits its column (%s)" % [
				framing, locale, state["os"]])
		_expect_true(
			row_label.get_combined_minimum_size().x <= 128.0 + 0.5,
			"%s %s label minimum fits its column (%s)" % [
				framing, locale, state["os"]])
		var label_rect: Rect2 = row_label.get_global_rect()
		var button_rect: Rect2 = reminder.get_global_rect()
		_expect_true(
			label_rect.end.x <= button_rect.position.x + 0.5,
			"%s %s label rect stays clear of the button (%s)" % [
				framing, locale, state["os"]])
		var text_right: float = label_rect.position.x + label_width
		if row_label.horizontal_alignment \
				== HORIZONTAL_ALIGNMENT_CENTER:
			text_right = label_rect.position.x \
				+ (label_rect.size.x + label_width) * 0.5
		elif row_label.horizontal_alignment \
				== HORIZONTAL_ALIGNMENT_RIGHT:
			text_right = label_rect.end.x
		var gap: float = button_rect.position.x - text_right
		_expect_true(gap + 0.5 >= 6.0,
			"%s %s keeps 6px text-to-button gap (%s: %s)" % [
				framing, locale, state["os"], gap])
	panel.queue_free()
	await get_tree().process_frame
	_clean_reminder_state()


## Translation changes and repeated opens must recompute the fit
## from the max: en shrinks, ko regrows, and a second open keeps
## the separation without duplicating the lazy row.
func _test_reminder_label_recomputes() -> void:
	_clean_reminder_state()
	var original_locale: String = TranslationServer.get_locale()
	var original_size: Vector2i = get_tree().root.size
	get_tree().root.size = Vector2i(808, 360)
	get_tree().root.content_scale_size = Vector2i(808, 360)
	await get_tree().process_frame
	var panel: Control = PANEL_SCENE.instantiate() as Control
	add_child(panel)
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var label: Label = panel.get_node("ReminderLabel") as Label
	var ko_size: int = -1
	var en_size: int = -1
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		Settings.locale = locale
		Settings.changed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_expect_equal(label.text, tr("SETTINGS_REMINDERS"),
			"recompute %s keeps its full copy" % locale)
		var current: int = label.get_theme_font_size("font_size")
		if locale == "ko":
			ko_size = current
		if locale == "en":
			en_size = current
		_check_row_gap(panel, locale, "recompute")
	_expect_equal(ko_size, 15, "recompute ko keeps the max")
	_expect_true(en_size >= 11 and en_size < 15,
		"recompute en shrinks but stays readable (got %d)" % en_size)
	TranslationServer.set_locale("ko")
	Settings.locale = "ko"
	Settings.changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(label.get_theme_font_size("font_size"), 15,
		"recompute ko regrows after en")
	_check_row_gap(panel, "ko", "recompute-regrow")
	panel.close()
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	TranslationServer.set_locale("en")
	Settings.locale = "en"
	Settings.changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var reopened: int = label.get_theme_font_size("font_size")
	_expect_true(reopened >= 11 and reopened < 15,
		"reopen en keeps its fit (got %d)" % reopened)
	_check_row_gap(panel, "en", "reopen")
	var copies: int = 0
	var label_copies: int = 0
	for child in panel.get_children():
		if (child as Node).name == &"Reminder":
			copies += 1
		if (child as Node).name == &"ReminderLabel":
			label_copies += 1
	_expect_equal(copies, 1, "reopen builds no second row")
	_expect_equal(label_copies, 1, "reopen builds no second label")
	panel.queue_free()
	await get_tree().process_frame
	TranslationServer.set_locale(original_locale)
	Settings.locale = str(_original_settings["locale"])
	get_tree().root.size = original_size
	get_tree().root.content_scale_size = original_size
	await get_tree().process_frame
	_clean_reminder_state()


func _check_row_gap(panel: Control, locale: String,
		context: String) -> void:
	var row_label: Label = panel.get_node("ReminderLabel") as Label
	var row_button: Button = panel.get_node("Reminder") as Button
	var label_fs: int = row_label.get_theme_font_size("font_size")
	_expect_true(label_fs >= 11 and label_fs <= 15,
		"%s %s label stays readable" % [context, locale])
	var label_font: Font = row_label.get_theme_font("font")
	var label_width: float = label_font.get_string_size(
		row_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		float(label_fs)).x
	_expect_true(label_width <= 128.0 + 0.5,
		"%s %s label text fits (%s)" % [context, locale, label_width])
	_expect_true(
		row_label.get_combined_minimum_size().x <= 128.0 + 0.5,
		"%s %s label minimum fits" % [context, locale])
	var label_rect: Rect2 = row_label.get_global_rect()
	var button_rect: Rect2 = row_button.get_global_rect()
	_expect_true(label_rect.end.x <= button_rect.position.x + 0.5,
		"%s %s rects separate (%s / %s)" % [
			context, locale, label_rect, button_rect])
	var text_right: float = label_rect.position.x + label_width
	if row_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		text_right = label_rect.position.x \
			+ (label_rect.size.x + label_width) * 0.5
	elif row_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		text_right = label_rect.end.x
	var gap: float = button_rect.position.x - text_right
	_expect_true(gap + 0.5 >= 6.0,
		"%s %s keeps 6px gap (%s)" % [context, locale, gap])


var _offer_accepted: int = 0


func _test_hud_offer() -> void:
	_offer_accepted = 0
	var hud: Control = HUD_SCENE.instantiate() as Control
	add_child(hud)
	await get_tree().process_frame
	hud.call("announce_offer", "receipt", "offer",
		_on_test_offer_accepted)
	await get_tree().process_frame
	var chip: Button = null
	for child in hud.get_children():
		if child is WorldButton \
				and (child as Control).visible:
			chip = child
	_expect_true(chip != null, "offer shows its chip")
	if chip != null:
		_expect_equal(chip.text, "offer", "chip carries the text")
		chip.pressed.emit()
		await get_tree().process_frame
		_expect_equal(_offer_accepted, 1,
			"accept runs the callback once")
		_expect_false(chip.visible, "accept hides the chip")
	hud.call("announce_offer", "receipt", "offer",
		_on_test_offer_accepted)
	await get_tree().process_frame
	hud.call("announce", "plain", Color.WHITE)
	await get_tree().process_frame
	var visible_chips: int = 0
	for child in hud.get_children():
		if child is WorldButton \
				and (child as Control).visible:
			visible_chips += 1
	_expect_equal(visible_chips, 0,
		"plain banner clears the chip")
	hud.queue_free()
	await get_tree().process_frame


func _on_test_offer_accepted() -> void:
	_offer_accepted += 1


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("FAIL reminders: ", label)


func _expect_false(value: bool, label: String) -> void:
	_expect_true(not value, label)


func _expect_equal(actual: Variant, expected: Variant,
		label: String) -> void:
	_checked += 1
	if actual != expected:
		_failed += 1
		printerr("FAIL reminders: ", label, " (got ", actual,
			", want ", expected, ")")
