class_name AttendanceReminders
extends Node

## Local attendance-reminder controller. One per install, owned by the
## production host.
##
## After an acknowledged attendance reward the server-confirmed deadline
## (`next_eligible_utc` + bounded `remaining_seconds` from the host's
## attendance view) is the single scheduling authority: there is no
## second reward timer, and a notification never grants coins by itself.
## The controller schedules one first fire at eligibility plus the
## native twelve-hour cadence. Every refresh re-checks the live OS
## permission before skipping unchanged inputs (a revocation on the
## same deadline surfaces instead of hiding), and refills a bounded
## native horizon from the same anchor when its held window runs low;
## a title refresh never shifts the deadline or stacks requests. It
## retires the schedule on disable, sign-out, account switch, or
## deletion.
##
## Scheduling decisions always query the live native permission; the
## `reminder_os_state` in Settings is display cache only. Desktop and
## other builds without a native side stay playable with an honest
## `unsupported` status and no fake scheduled success.

const SCHEMA_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_schema.gd")

## Twelve-hour repeat, matching the server's rolling cooldown.
const REPEAT_SECONDS: int = 43200
## Native window shape, mirroring the iOS planner exactly: 48 slots on
## the anchor grid, adequate while 8 are still future. Millisecond
## math so the equal-time boundary agrees bit-for-bit, like the
## native side.
const REPEAT_MILLIS: int = 43200000
const HORIZON_SLOTS: int = 48
const MIN_FUTURE_SLOTS: int = 8

var _host: Node = null
var _bridge: Node = null
var _generation: int = 0
var _pending_permission_id: String = ""
var _pending_generation: int = -1
var _pending_status_id: String = ""
var _status_generation: int = -1
## Reentrancy guard: reconciling writes `reminder_os_state`, which emits
## `Settings.changed`, which calls back into `refresh`. Nested passes
## are redundant (the outer pass already sees the latest view), and on
## the never-recorded refusal path they would oscillate forever.
var _reconciling: bool = false


func _ready() -> void:
	if _host == null and has_node("/root/ProductionHost"):
		configure(get_node("/root/ProductionHost"),
			get_node_or_null("/root/MoonlitIdentity"))


## Tests and the host inject fakes here. Production passes the real
## host plus the MoonlitIdentity autoload (or null on desktop builds
## without the bridge, which stays honestly unsupported).
func configure(host: Node, bridge: Node) -> void:
	if _host != null and is_instance_valid(_host):
		if _host.is_connected("production_attendance",
				_on_attendance_snapshot):
			_host.disconnect("production_attendance",
				_on_attendance_snapshot)
		if _host.is_connected("production_changed",
				_on_production_changed):
			_host.disconnect("production_changed",
				_on_production_changed)
	if _bridge != null and is_instance_valid(_bridge):
		if _bridge.is_connected("request_completed",
				_on_bridge_outcome):
			_bridge.disconnect("request_completed",
				_on_bridge_outcome)
	_generation += 1
	_pending_permission_id = ""
	_pending_generation = -1
	_pending_status_id = ""
	_status_generation = -1
	_host = host
	_bridge = bridge
	if _host != null and is_instance_valid(_host):
		if _host.has_signal("production_attendance"):
			_host.connect("production_attendance",
				_on_attendance_snapshot)
		if _host.has_signal("production_changed"):
			_host.connect("production_changed",
				_on_production_changed)
	if _bridge != null and is_instance_valid(_bridge):
		if _bridge.has_signal("request_completed"):
			_bridge.connect("request_completed", _on_bridge_outcome)
	if Settings.is_connected("changed", _on_settings_changed):
		Settings.disconnect("changed", _on_settings_changed)
	Settings.connect("changed", _on_settings_changed)


## Re-evaluate the schedule from the live view. Called on every
## attendance snapshot, settings change, and explicit refresh.
func refresh() -> void:
	if _reconciling:
		return
	if _host == null or not is_instance_valid(_host):
		return
	if not _host.has_method("attendance_view"):
		return
	_reconciling = true
	_reconcile(_host.call("attendance_view"))
	_reconciling = false


## Settings-row tap: off enables (or opens OS settings when denied),
## on disables and cancels immediately.
func user_toggle() -> void:
	if not Settings.reminders_enabled:
		if Settings.reminder_os_state == "denied":
			_open_os_settings()
			return
		user_enable()
		return
	user_disable()


## Persist the intent, ask the OS for permission, and schedule on
## grant. The receipt offer's accept path calls this too. Never
## auto-requests: only explicit taps arrive here.
func user_enable() -> void:
	if _bridge == null or not is_instance_valid(_bridge):
		Settings.set_reminder_os_state("unsupported")
		return
	if not _bridge.has_method("reminder_request_permission"):
		Settings.set_reminder_os_state("unsupported")
		return
	if not Settings.set_reminders_enabled(true):
		return
	var receipt: Dictionary = _bridge.call(
		"reminder_request_permission")
	if str(receipt.get("status", "")) == "pending":
		_pending_permission_id = str(
			receipt.get("request_id", ""))
		_pending_generation = _generation
		return
	_apply_permission_receipt(receipt, _generation)


## Persist off, cancel any native delivery, and forget the schedule.
## The Settings sentinel lands first, so a crash cannot resurrect it.
func user_disable() -> void:
	_cancel_native()
	Settings.clear_reminder_schedule()
	Settings.set_reminders_enabled(false)


## Refresh the display-cache OS state without scheduling. When the
## native side answers pending (iOS reads the OS asynchronously), the
## cached state stands until the bounded outcome lands and corrects
## the open panel through Settings.changed: no second reopen, no
## prompt, and never a flash of ignorance on every open.
func refresh_permission() -> void:
	var status: Dictionary = _native_status()
	if status.is_empty():
		Settings.set_reminder_os_state("unsupported")
		return
	if str(status.get("status", "")) == "error":
		# Transient native outage: leave the cached display state
		# alone rather than overwriting it with ignorance.
		return
	if str(status.get("status", "")) == "pending":
		_pending_status_id = str(status.get("request_id", ""))
		_status_generation = _generation
		return
	Settings.set_reminder_os_state(str(
		status.get("permission", "unknown")))


## The first receipt's offer text, or "" when no offer applies. Marks
## the offer shown when it returns text, so repeat receipts never nag.
## Offered only where a native side exists: desktop never dangles one.
func offer_for_receipt() -> String:
	if Settings.reminder_receipt_offered:
		return ""
	if Settings.reminders_enabled:
		return ""
	if _bridge == null or not is_instance_valid(_bridge):
		return ""
	if not _bridge.has_method("reminder_status"):
		return ""
	var status: Dictionary = _bridge.call("reminder_status")
	var code: String = str(status.get("status", ""))
	if code == "pending":
		_pending_status_id = str(status.get("request_id", ""))
		_status_generation = _generation
	elif code != "ok":
		return ""
	Settings.mark_reminder_receipt_offered()
	return tr("REMINDER_OFFER")


func _on_attendance_snapshot(_snapshot: Dictionary) -> void:
	refresh()


func _on_production_changed(_state: Dictionary) -> void:
	# Account, deletion, and restore transitions all publish here; the
	# live view below retires a schedule whose owner is gone.
	refresh()


func _on_settings_changed() -> void:
	refresh()


func _on_bridge_outcome(outcome: Dictionary) -> void:
	var request_id: String = str(outcome.get("request_id", ""))
	if request_id == _pending_permission_id \
			and _pending_generation == _generation \
			and not _pending_permission_id.is_empty():
		_pending_permission_id = ""
		_pending_generation = -1
		_apply_permission_receipt(outcome, _generation)
		return
	if request_id == _pending_status_id \
			and _status_generation == _generation \
			and not _pending_status_id.is_empty():
		_pending_status_id = ""
		_status_generation = -1
		_apply_status_outcome(outcome, _generation)


func _apply_permission_receipt(receipt: Dictionary,
		generation: int) -> void:
	if generation != _generation:
		return
	var status: String = str(receipt.get("status", ""))
	if status == "unsupported" or status == "not_configured":
		Settings.set_reminder_os_state("unsupported")
		return
	var permission: String = str(
		receipt.get("permission", "unknown"))
	if permission == "granted":
		Settings.set_reminder_os_state("granted")
		refresh()
	elif permission == "denied":
		# Denial is not enabled: the intent stays on so the settings
		# row can offer OS settings, but nothing schedules.
		Settings.set_reminder_os_state("denied")
	else:
		Settings.set_reminder_os_state("unknown")


## Settle one asynchronous native status read. A fresh grant may
## unblock a schedule this pass skipped for lack of a verdict, so a
## granted outcome runs the schedule tail once against a fresh view.
## Bounded: the tail never queries status, failed outcomes schedule
## nothing and refresh nothing, and a state change converges through
## the normal Settings.changed refresh instead of a loop here.
func _apply_status_outcome(outcome: Dictionary,
		generation: int) -> void:
	if generation != _generation:
		return
	if str(outcome.get("status", "")) != "ok":
		return
	var permission: String = str(
		outcome.get("permission", "unknown"))
	Settings.set_reminder_os_state(permission)
	if permission != "granted":
		return
	if _host == null or not is_instance_valid(_host):
		return
	if not _host.has_method("attendance_view"):
		return
	var view: Variant = _host.call("attendance_view")
	if typeof(view) != TYPE_DICTIONARY:
		return
	_schedule_for_view(view)


## Whether the recorded native horizon still holds its deliveries.
## Negative means an unbounded repeating native (Android): always
## held. Zero means a legacy schedule that never reported a window
## (or none at all): only iOS absolute slots must replan once, since
## a repeating native still holds without any window. A real window
## holds under the exact native duplicate rule: the first
## not-yet-elapsed slot derives from the recorded anchor in integer
## milliseconds, and the window holds while 8 of its 48 ordinals are
## still future. A base the native side never reported derives from
## the recorded end once; an underivable one replans once and then
## carries full metadata. Whole-second fixtures agree with the native
## planner bit-for-bit (see the shared agreement vectors); live
## sub-second sampling can differ for under a second and self-heals.
static func _horizon_holds(horizon_end: float, base_slot: int,
		eligible_unix: int, now_unix: float,
		platform: String) -> bool:
	if horizon_end < 0.0:
		return true
	if horizon_end == 0.0:
		return platform != "iOS"
	var base: int = base_slot
	if base < 0:
		base = _legacy_base_slot(horizon_end, eligible_unix)
		if base < 0:
			return false
	var anchor_ms: int = eligible_unix * 1000
	var now_ms: int = int(now_unix * 1000.0)
	var first_future: int = 0
	if now_ms > anchor_ms:
		first_future = int((now_ms - anchor_ms + REPEAT_MILLIS \
			- 1) / REPEAT_MILLIS)
	if first_future < base:
		return false
	return (first_future - base) + MIN_FUTURE_SLOTS \
		<= HORIZON_SLOTS


## First ordinal of a window the old native receipts never named: the
## recorded end is the last fire, 47 repeats past the base. -1 when
## the end is not on the anchor grid or names no window at all.
static func _legacy_base_slot(horizon_end: float,
		eligible_unix: int) -> int:
	if eligible_unix <= 0:
		return -1
	var end_sec: int = int(floor(horizon_end + 0.5))
	var span: int = end_sec - eligible_unix
	if span < (HORIZON_SLOTS - 1) * REPEAT_SECONDS:
		return -1
	if span % REPEAT_SECONDS != 0:
		return -1
	return span / REPEAT_SECONDS - (HORIZON_SLOTS - 1)


func _reconcile(view: Dictionary) -> void:
	if typeof(view) != TYPE_DICTIONARY:
		return
	var account: String = str(view.get("public_id", ""))
	if not Settings.reminder_sched_account.is_empty() \
			and account != Settings.reminder_sched_account:
		# Sign-out, switch, or deletion retired this owner: cancel the
		# stale delivery and forget it. Never reschedules here; the new
		# account's own snapshot drives its own schedule below.
		_cancel_native()
		Settings.clear_reminder_schedule()
	if not Settings.reminders_enabled:
		return
	if typeof(view) != TYPE_DICTIONARY or view.is_empty():
		return
	var source: String = str(view.get("source", "none"))
	if source != "live" and source != "cache":
		# No deadline known: leave any existing delivery alone rather
		# than churning on ignorance. Cached deadlines may schedule
		# (reminder only, never a grant); absence schedules nothing.
		return
	var eligible_utc: String = str(
		view.get("next_eligible_utc", ""))
	if eligible_utc.is_empty():
		return
	var eligible_unix: int = SCHEMA_SCRIPT.unix_from_rfc3339(
		eligible_utc)
	if eligible_unix <= 0:
		return
	# Live permission first, identical-input skipping after: an OS
	# revocation on the same deadline must surface as denied instead
	# of hiding behind the skip. Denial keeps the intent and the
	# record (a re-grant resumes delivery with no reschedule) but
	# schedules nothing; only a lost native clears defensively.
	var status: Dictionary = _native_status()
	if status.is_empty():
		Settings.set_reminder_os_state("unsupported")
		_cancel_native()
		Settings.clear_reminder_schedule()
		return
	if str(status.get("status", "")) == "error":
		# Transient native outage (for example the activity is
		# between lifecycles): keep the owned delivery and its
		# record, and let the next refresh converge. Never cancel
		# or clear on ignorance.
		return
	if str(status.get("status", "")) == "pending":
		# Asynchronous read (iOS): the bounded outcome converges
		# this pass through _apply_status_outcome.
		_pending_status_id = str(status.get("request_id", ""))
		_status_generation = _generation
		return
	var permission: String = str(status.get("permission", "unknown"))
	if permission != "granted":
		Settings.set_reminder_os_state(permission)
		return
	Settings.set_reminder_os_state("granted")
	_schedule_for_view(view)


## Schedule the view's deadline unless it is already held. Pure of
## status reads: both the synchronous reconcile path and the granted
## async-status outcome share it, so neither can stack deliveries or
## loop back into a status wait. The user-intent and ownership gates
## live here (not only in the reconcile head) because a late async
## verdict arrives after taps and scope changes: a grant may update
## the OS cache while off, but it must never re-enable intent or arm
## a delivery the current settings and source do not own. Never moves
## the deadline: a refill re-asks the native side for the same anchor,
## and the native side keeps its absolute times. An expired known
## anchor still schedules: the native side plans future-only slots
## from it (never a burst), so an offline return that never claims
## still re-arms instead of starving on an exhausted horizon.
## Scheduling grants no coins.
func _schedule_for_view(view: Dictionary) -> void:
	if not Settings.reminders_enabled:
		return
	var source: String = str(view.get("source", "none"))
	if source != "live" and source != "cache":
		# No owned deadline: stale fields a dead scope retains must
		# not arm anything, however parseable they still are.
		return
	var account: String = str(view.get("public_id", ""))
	var eligible_utc: String = str(
		view.get("next_eligible_utc", ""))
	var eligible_unix: int = SCHEMA_SCRIPT.unix_from_rfc3339(
		eligible_utc)
	if eligible_unix <= 0:
		return
	if account == Settings.reminder_sched_account \
			and eligible_utc == Settings.reminder_sched_eligible_utc \
			and Settings.locale == Settings.reminder_sched_locale \
			and _horizon_holds(
				Settings.reminder_sched_horizon_end,
				Settings.reminder_sched_base_slot,
				eligible_unix,
				Time.get_unix_time_from_system(),
				OS.get_name()):
		return
	var scheduled: Dictionary = _bridge.call("reminder_schedule", {
		"eligible_utc_millis": eligible_unix * 1000,
		"title": tr("REMINDER_TITLE"),
		"body": tr("REMINDER_BODY"),
		"locale": Settings.locale,
		"account": account,
	})
	if str(scheduled.get("status", "")) != "ok":
		# Not recorded: the next refresh converges instead of
		# claiming a delivery the OS refused.
		if str(scheduled.get("status", "")) == "denied" \
				or str(scheduled.get("permission", "")) == "denied":
			Settings.set_reminder_os_state("denied")
		return
	var end: float = float(
		scheduled.get("horizon_end_unix", 0.0))
	var base: int = int(scheduled.get("base_slot", -1))
	if end == 0.0 and bool(scheduled.get("duplicate", false)) \
			and account == Settings.reminder_sched_account \
			and eligible_utc \
				== Settings.reminder_sched_eligible_utc \
			and Settings.locale == Settings.reminder_sched_locale:
		# A duplicate that names no window must not wipe the known
		# one: keep the recorded metadata so the next refresh
		# skips instead of re-asking forever.
		end = Settings.reminder_sched_horizon_end
		base = Settings.reminder_sched_base_slot
	if not Settings.record_reminder_schedule(account, eligible_utc,
			Settings.locale, end, base):
		# The OS holds a delivery this install can no longer name:
		# cancel it rather than orphan it, and converge next time.
		_cancel_native()


func _native_status() -> Dictionary:
	if _bridge == null or not is_instance_valid(_bridge):
		return {}
	if not _bridge.has_method("reminder_status"):
		return {}
	var status: Variant = _bridge.call("reminder_status")
	if typeof(status) != TYPE_DICTIONARY:
		return {}
	var code: String = str(status.get("status", ""))
	if code == "ok" or code == "error" or code == "pending":
		return status
	return {}


func _cancel_native() -> void:
	if _bridge == null or not is_instance_valid(_bridge):
		return
	if not _bridge.has_method("reminder_cancel"):
		return
	_bridge.call("reminder_cancel")


func _open_os_settings() -> void:
	if _bridge == null or not is_instance_valid(_bridge):
		return
	if not _bridge.has_method("reminder_open_settings"):
		return
	_bridge.call("reminder_open_settings")
