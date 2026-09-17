extends RefCounted

## Hide TestLauncher/ArenaTools only on the debug APK used to shoot store masters.
## Request and ready files are a one-way handshake with capture automation.
## Release never changes any UI or writes files, thanks to the
## `OS.is_debug_build()` guard.

const TITLE_REQUEST: String = "user://store_capture_clean_title.request"
const TITLE_READY: String = "user://store_capture_clean_title.ready"
const COMBAT_REQUEST: String = "user://store_capture_clean_combat.request"
const COMBAT_READY: String = "user://store_capture_clean_combat.ready"
const HIDDEN_DRAW_FRAME_META: StringName = &"store_capture_clean_ui_hidden_draw_frame"


static func hide_title(owner: CanvasItem) -> bool:
	return _hide_requested(owner, null, TITLE_REQUEST, TITLE_READY, "title-hidden")


static func hide_combat(owner: CanvasItem, frame_meter: CanvasItem) -> bool:
	return _hide_requested(
		owner,
		frame_meter,
		COMBAT_REQUEST,
		COMBAT_READY,
		"combat-hidden")


static func _hide_requested(
		owner: CanvasItem,
		extra: CanvasItem,
		request_path: String,
		ready_path: String,
		proof: String,
	) -> bool:
	if not OS.is_debug_build() or owner == null:
		return false
	# Official iOS CoreDevice appDataContainer transfer has no delete command.
	# If the host overwrites with `{}`, treat it as disarmed regardless of
	# whether the file exists. Existing Android `touch` requests (empty files)
	# and test strings stay allowed.
	var request_armed: bool = FileAccess.file_exists(request_path) \
		and FileAccess.get_file_as_string(request_path).strip_edges() != "{}"
	if not request_armed:
		if owner.has_meta(HIDDEN_DRAW_FRAME_META):
			owner.remove_meta(HIDDEN_DRAW_FRAME_META)
		return false
	var visibility_changed: bool = owner.visible \
		or (extra != null and extra.visible)
	# If debug UI reappears after ready exists, the old proof must not be reused.
	# Discard the stale ready and request together. Reissuing the same string
	# on the same request would hide a one-frame ABA from the host, where UI
	# flashes on a single screencap then vanishes. Never reissue proof until a
	# new arm.
	var ready_is_current: bool = FileAccess.file_exists(ready_path) \
		and FileAccess.get_file_as_string(ready_path).strip_edges() == proof
	if ready_is_current:
		if not visibility_changed:
			return true
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ready_path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(request_path))
		owner.visible = false
		if extra != null:
			extra.visible = false
		if owner.has_meta(HIDDEN_DRAW_FRAME_META):
			owner.remove_meta(HIDDEN_DRAW_FRAME_META)
		return true
	owner.visible = false
	if extra != null:
		extra.visible = false
	# On the same process frame as the hide request, the render server may still
	# have drawn the previous frame. Keep the draw counter from the hide moment
	# and publish the ready file only after a later draw has finished, so the
	# host can start screencap.
	if visibility_changed or not owner.has_meta(HIDDEN_DRAW_FRAME_META):
		owner.set_meta(HIDDEN_DRAW_FRAME_META, Engine.get_frames_drawn())
		return true
	var hidden_draw_frame: int = int(owner.get_meta(HIDDEN_DRAW_FRAME_META, -1))
	if Engine.get_frames_drawn() <= hidden_draw_frame:
		return true
	var ready: FileAccess = FileAccess.open(ready_path, FileAccess.WRITE)
	if ready == null:
		return false
	ready.store_string(proof + "\n")
	return true
