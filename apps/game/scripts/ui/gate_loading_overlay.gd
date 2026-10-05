class_name GateLoadingOverlay
extends Control

## Honest loading veil for the moon gate entry surface.
##
## The host calls `begin(scene_path, stage_text)` and this overlay paints
## itself first, then asks the ResourceLoader for the scene on a worker
## thread, then reports only what the loader really says: indeterminate
## "preparing" until the first progress sample, real 0..1 progress after,
## and true failure when the load fails. There is no timed fake progress and
## no forced wait.
##
## Every `begin()` takes a token from a generation counter. `cancel()` moves
## the counter, so a load that finishes after its cancel is stale and can
## only be ignored: it never emits `finished` and this overlay never enters
## any scene itself. Entering stays the host's job; the `packed` scene in
## `finished` is handed over for the host to place.
##
## Cancelled and superseded loads are drained, not dropped. A requested
## path that stops being current becomes an orphan, and every frame claims
## whatever orphans completed — claimed and discarded, never surfaced — so
## the worker never holds an unclaimed result that a later request would
## replace (and leak). Draining never blocks and never emits.
##
## The overlay owns no arena paths. The scene path arrives as a plain string
## per call, so nothing here preloads expensive resources.

signal finished(scene_path: String, packed: PackedScene, token: int)
signal failed(scene_path: String, message: String, token: int)
signal cancelled(scene_path: String, token: int)
signal retry_requested(scene_path: String)
signal return_requested

## Frames that must pass before the loader is even asked. Every frame ends
## in a draw, so after two process frames the veil and its stage text have
## provably painted at least once. (`frame_post_draw` would be the purer
## signal, but headless runs never emit it and the load would hang.)
const FIRST_PAINT_FRAMES: int = 2
const CARD_MIN_WIDTH: float = 360.0

var _generation: int = 0
var _active_token: int = 0
var _loading: bool = false
var _request_issued: bool = false
var _path: String = ""
var _orphans: Array[String] = []
var _stage: String = ""
var _showing_error: bool = false
var _showing_cancelled: bool = false

var _dim: ColorRect
var _card: PanelContainer
var _stack: VBoxContainer
var _stage_label: Label
var _status_label: Label
var _bar: ProgressBar
var _detail_label: Label
var _cancel_button: Button
var _retry_button: Button
var _back_button: Button
var _button_row: HBoxContainer


func _ready() -> void:
	GateEntryStrings.ensure_loaded()
	_build()
	_to_idle()


## Start loading `scene_path`, showing `stage_text` while it loads.
## Returns the token that `finished`/`failed`/`cancelled` will carry.
## Returns 0 when the overlay is not in the tree yet.
func begin(scene_path: String, stage_text: String) -> int:
	if not is_inside_tree():
		push_error("GateLoadingOverlay.begin needs the overlay in the tree")
		return 0
	if _path != scene_path:
		_orphan_current()
	# A path that becomes current again leaves the orphan list; the paint
	# gate below adopts its in-flight or cached worker state.
	_orphans.erase(scene_path)
	_generation += 1
	var token: int = _generation
	_active_token = token
	_loading = true
	_request_issued = false
	_path = scene_path
	_stage = stage_text
	_showing_error = false
	_showing_cancelled = false
	_stage_label.text = stage_text
	_status_label.text = "gate.loading.preparing"
	_bar.value = 0.0
	_detail_label.visible = false
	_cancel_button.visible = true
	_retry_button.visible = false
	_back_button.visible = false
	_button_row.visible = true
	visible = true
	_recenter_card()
	_request_after_first_paint(token, scene_path)
	return token


## Drop the current load. A late completion for it is stale and ignored,
## so `finished` can never fire for a cancelled path afterwards.
func cancel() -> void:
	if not _loading:
		return
	_generation += 1
	_orphan_current()
	var token: int = _active_token
	var path: String = _path
	_loading = false
	_request_issued = false
	_showing_error = false
	_showing_cancelled = true
	_status_label.text = "gate.loading.cancelled"
	_detail_label.visible = false
	_cancel_button.visible = false
	_retry_button.visible = true
	_back_button.visible = true
	_button_row.visible = true
	visible = true
	_recenter_card()
	cancelled.emit(path, token)


## Host supplies a truer stage line mid-load; it is shown as given.
## The card is refitted so a longer line keeps its wrapped glyph height.
func set_stage_text(stage_text: String) -> void:
	_stage = stage_text
	if _stage_label != null:
		_stage_label.text = stage_text
		_recenter_card()


func is_loading() -> bool:
	return _loading


## True once the worker request really went out. False while the overlay is
## still painting its first frames. Tests read this for the paint-first rule.
func is_request_issued() -> bool:
	return _request_issued


func current_token() -> int:
	return _active_token


func current_path() -> String:
	return _path


func is_showing_error() -> bool:
	return _showing_error and visible


func is_showing_cancelled() -> bool:
	return _showing_cancelled and visible


## True while cancelled or superseded worker loads still await their claim.
## Hosts tearing down mid-load wait on this first; it never blocks.
func has_pending_drain() -> bool:
	return not _orphans.is_empty()


func _exit_tree() -> void:
	# One non-blocking pass: claim whatever already completed. Anything
	# still in flight belongs to the worker past our lifetime.
	_drain_orphans()


func _process(_delta: float) -> void:
	_poll_current()
	_drain_orphans()


func _poll_current() -> void:
	if not _loading or not _request_issued or _path.is_empty():
		return
	if _active_token != _generation:
		return
	var progress: Array = []
	var status: ResourceLoader.ThreadLoadStatus = \
		ResourceLoader.load_threaded_get_status(_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not progress.is_empty():
				var fraction: float = clampf(float(progress[0]), 0.0, 1.0)
				_bar.value = fraction
				_status_label.text = "%d%%" % int(round(fraction * 100.0))
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed: PackedScene = \
				ResourceLoader.load_threaded_get(_path) as PackedScene
			_finish_if_current(_active_token, _path, packed)
		ResourceLoader.THREAD_LOAD_FAILED:
			_fail_if_current(_active_token, _path, _path)
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			# The path was never a loadable scene. Same contract as the
			# title's arena poll: report the true failure, never hang.
			_fail_if_current(_active_token, _path, _path)


func _request_after_first_paint(token: int, path: String) -> void:
	for _index in FIRST_PAINT_FRAMES:
		await get_tree().process_frame
		if token != _generation or not _loading:
			return
	if token != _generation or not _loading:
		return
	_request_issued = true
	var already: ResourceLoader.ThreadLoadStatus = \
		ResourceLoader.load_threaded_get_status(path)
	if already == ResourceLoader.THREAD_LOAD_IN_PROGRESS \
			or already == ResourceLoader.THREAD_LOAD_LOADED:
		# The worker already flies or holds this path (a re-begin, a
		# retry, a warm cache): adopt that state instead of asking twice.
		# The current poll below reports it under the live token.
		return
	var err: Error = ResourceLoader.load_threaded_request(path)
	if err != OK:
		_fail_if_current(token, path, error_string(err))


## The current request stopped being current while issued: the worker keeps
## flying it, and the drain below claims it once it lands.
func _orphan_current() -> void:
	if not _request_issued or _path.is_empty():
		return
	if not _path in _orphans:
		_orphans.append(_path)


## Claim completed orphans and drop dead ones. No signals, no waiting: one
## status poll per orphan per frame, and the claimed result is discarded.
func _drain_orphans() -> void:
	if _orphans.is_empty():
		return
	for orphan in _orphans.duplicate():
		if orphan == _path and _loading:
			continue
		var status: ResourceLoader.ThreadLoadStatus = \
			ResourceLoader.load_threaded_get_status(orphan)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(orphan)
			_orphans.erase(orphan)
		elif status == ResourceLoader.THREAD_LOAD_FAILED \
				or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_orphans.erase(orphan)


func _finish_if_current(token: int, path: String, packed: PackedScene) -> void:
	if token != _generation or not _loading:
		return
	if packed == null:
		# A worker round-trip that hands back no scene is an honest
		# failure. Delegate before clearing flags: the fail branch owns
		# the guard and the error card from here.
		_fail_if_current(token, path, path)
		return
	_loading = false
	_request_issued = false
	_to_idle()
	finished.emit(path, packed, token)


func _fail_if_current(token: int, path: String, message: String) -> void:
	if token != _generation or not _loading:
		return
	_loading = false
	_request_issued = false
	_showing_error = true
	_showing_cancelled = false
	_status_label.text = "gate.loading.failed"
	_detail_label.text = message
	_detail_label.visible = true
	_cancel_button.visible = false
	_retry_button.visible = true
	_back_button.visible = true
	_button_row.visible = true
	visible = true
	_recenter_card()
	_retry_button.grab_focus()
	failed.emit(path, message, token)


func _to_idle() -> void:
	_loading = false
	_request_issued = false
	_showing_error = false
	_showing_cancelled = false
	visible = false


func _on_retry() -> void:
	var path: String = _path
	var stage: String = _stage
	retry_requested.emit(path)
	begin(path, stage)


func _on_back() -> void:
	return_requested.emit()
	_to_idle()


func _on_cancel() -> void:
	cancel()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.name = &"Dim"
	_dim.color = GateEntryStyle.DIM_BG
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_card = PanelContainer.new()
	_card.name = &"LoadingCard"
	GateEntryStyle.apply_card(_card)
	_card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 0.0)
	add_child(_card)
	_stack = VBoxContainer.new()
	_stack.name = &"Stack"
	_stack.add_theme_constant_override(&"separation", 8)
	_card.add_child(_stack)
	_stage_label = GateEntryStyle.make_label(
		"gate.loading.preparing", GateEntryStyle.FONT_BODY,
		GateEntryStyle.TEXT_MAIN, true)
	_stage_label.name = &"Stage"
	_stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stage_label.custom_minimum_size.x = _content_width()
	_stage_label.max_lines_visible = 2
	_stage_label.clip_text = true
	_stack.add_child(_stage_label)
	_bar = ProgressBar.new()
	_bar.name = &"Progress"
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.value = 0.0
	GateEntryStyle.apply_progress(_bar)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_child(_bar)
	_status_label = GateEntryStyle.make_label(
		"gate.loading.preparing", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.TEXT_DIM)
	_status_label.name = &"Status"
	_stack.add_child(_status_label)
	_detail_label = GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_SMALL, GateEntryStyle.TEXT_FAINT)
	_detail_label.name = &"Detail"
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.custom_minimum_size.x = _content_width()
	_detail_label.max_lines_visible = 2
	_detail_label.clip_text = true
	_stack.add_child(_detail_label)
	_button_row = HBoxContainer.new()
	_button_row.name = &"Buttons"
	_button_row.alignment = BoxContainer.ALIGNMENT_END
	_button_row.add_theme_constant_override(&"separation", 8)
	_stack.add_child(_button_row)
	_cancel_button = GateEntryStyle.make_button("gate.loading.cancel")
	_cancel_button.name = &"Cancel"
	_cancel_button.pressed.connect(_on_cancel)
	_button_row.add_child(_cancel_button)
	_retry_button = GateEntryStyle.make_button(
		"gate.loading.retry", "primary")
	_retry_button.name = &"Retry"
	_retry_button.pressed.connect(_on_retry)
	_button_row.add_child(_retry_button)
	_back_button = GateEntryStyle.make_button("gate.loading.back")
	_back_button.name = &"Back"
	_back_button.pressed.connect(_on_back)
	_button_row.add_child(_back_button)
	_recenter_card()
	resized.connect(_recenter_card)
	visibility_changed.connect(_recenter_card)


## Usable content width inside the card. Wrapped labels are bound to it
## so minimum sizes stay sane from birth.
func _content_width() -> float:
	return CARD_MIN_WIDTH - GateEntryStyle.CARD_MARGIN_H


## Reserve wrapped heights for the clipped stage/detail labels.
##
## A wrapped Label with `clip_text` reports a 1px minimum height, so the
## card's fitted height alone never gives it a readable rect. Reading its
## combined minimum with the clip briefly off yields its true wrapped need
## (font lines plus spacing, capped to `max_lines_visible`), which is kept
## as `custom_minimum_size.y` so first paint already shows glyphs.
func _reserve_wrapped_heights(content_width: float) -> void:
	if _stage_label == null or _detail_label == null:
		return
	var content: float = maxf(content_width, 64.0)
	for candidate in [_stage_label, _detail_label]:
		var wrapped: Label = candidate as Label
		wrapped.custom_minimum_size.x = content
		var was_clip: bool = wrapped.clip_text
		wrapped.clip_text = false
		var need: float = wrapped.get_combined_minimum_size().y
		wrapped.clip_text = was_clip
		var font: Font = wrapped.get_theme_font("font")
		var font_size: int = wrapped.get_theme_font_size("font_size")
		var line: float = float(font.get_height(font_size))
		wrapped.custom_minimum_size.y = maxf(need, line)


## Fitted stack height using the reserved wrapped minima.
##
## The shared fitted helper measures wrapped text through the font alone,
## which misses the label's line spacing on multi-line stages. The reserved
## `custom_minimum_size.y` already holds the true need, so the card is
## fitted from it for the two wrapped labels and from combined minima for
## everything else.
func _fitted_height_reserved() -> float:
	var total: float = 0.0
	var shown: int = 0
	for child in _stack.get_children():
		var control: Control = child as Control
		if control == null or not control.visible:
			continue
		shown += 1
		if control == _stage_label or control == _detail_label:
			total += (control as Label).custom_minimum_size.y
		else:
			total += control.get_combined_minimum_size().y
	if shown > 1:
		total += float(shown - 1) \
			* float(_stack.get_theme_constant("separation"))
	return total


## Fixed width, fitted height: the stage line wraps, so it is measured
## at the real content width instead of its exploding minimum size.
## Wrapped minima are reserved first so the clipped labels own readable
## rects before the first paint, on every text change and every resize.
func _recenter_card() -> void:
	if _card == null:
		return
	var view: Vector2 = get_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		_reserve_wrapped_heights(_content_width())
		return
	var width: float = minf(CARD_MIN_WIDTH, view.x - 32.0)
	var content: float = maxf(width - GateEntryStyle.CARD_MARGIN_H, 64.0)
	_reserve_wrapped_heights(content)
	var height: float = _fitted_height_reserved() \
		+ GateEntryStyle.CARD_MARGIN_V
	height = minf(height, view.y - 16.0)
	# Size first, then center from the read-back rect: assigning below a
	# child's minimum clamps the size up, and centering from the request
	# would leave a clamped card off-center.
	_card.size = Vector2(width, height).ceil()
	_card.position = ((view - _card.size) * 0.5).floor()
