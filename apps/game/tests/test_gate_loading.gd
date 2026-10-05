extends Node

## Moon gate loading: first paint, cancel guards, honest errors.
##
## The overlay paints before it asks the ResourceLoader for anything
## expensive, a cancelled load can never finish late, and failures surface
## with retry and return instead of a hang. The loader itself never enters
## a scene: the current scene is the same before and after every case.

const LOADER_SCENE: PackedScene = preload("res://scenes/ui/gate_loading_overlay.tscn")
const ARENA_PATH: String = "res://scenes/gameplay/arena.tscn"
const SMALL_SCENE_PATH: String = "res://scenes/ui/quit_panel.tscn"
## A real resource that is not a scene. The worker round-trips cleanly and
## the overlay still fails honestly, with no engine error spam. (A missing
## path also fails through the same branch, but the worker logs ERROR lines
## the suite forbids, so that variant is verified by hand, not here.)
const NON_SCENE_PATH: String = "res://icon.svg"
## A valid scene this suite never loads except as the stale side of the
## rapid re-begin: while it stays untouched, its worker status proves the
## superseded request never went out.
const STALE_PATH: String = "res://scenes/ui/result_panel.tscn"
## Wall-time budget per load below. Headless frames run without vsync, so a
## frame count is not a deadline; thirty seconds is far past a normal load
## yet still fails a real hang fast enough for the suite.
const LOAD_DEADLINE_MSEC: int = 30000
const LOAD_POLL_SECONDS: float = 0.05

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	get_tree().root.size = Vector2i(808, 360)
	_warm_worker_paths()
	var home: Node = get_tree().current_scene
	await _test_paint_before_request()
	await _test_cancel_before_request()
	await _test_cancel_after_request()
	await _test_stale_completion_guard()
	await _test_rapid_rebegin()
	await _test_cancel_drains_orphan()
	await _test_rebegin_drains_orphan()
	await _test_unusable_path_error()
	await _test_wrapped_glyph_heights()
	_expect_true(get_tree().current_scene == home,
		"loader never enters a scene on its own")
	if _failed > 0:
		printerr("gate-loading test failed — ",
			_failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("gate-loading test passed — ", _checked, " case(s)")
	get_tree().quit(0)


## Sync-load every path the suite worker-loads. Cold worker loads leak a
## few engine-side temporaries per script (34 for the arena, 2-4 for small
## scenes, proven with raw `load_threaded_request` and no overlay code),
## while sync loads and warm worker round-trips are silent. Warming keeps
## this suite's output free of engine warnings without changing any guard
## under test: ordering, tokens, and draining behave the same warm or cold.
## STALE_PATH stays cold on purpose: the rapid test asserts the worker
## never hears it, which a warm cache would mask.
func _warm_worker_paths() -> void:
	for path in [ARENA_PATH, SMALL_SCENE_PATH, NON_SCENE_PATH]:
		var warmed: Resource = load(path) as Resource
		if warmed == null:
			printerr("gate-loading warmup failed for ", path)


func _make_loader() -> GateLoadingOverlay:
	var loader: GateLoadingOverlay = LOADER_SCENE.instantiate() \
		as GateLoadingOverlay
	add_child(loader)
	return loader


func _free_loader(loader: GateLoadingOverlay) -> void:
	loader.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_paint_before_request() -> void:
	var loader: GateLoadingOverlay = _make_loader()
	await get_tree().process_frame
	var finished: Array = []
	loader.finished.connect(
		func(path: String, packed: PackedScene, _token: int) -> void:
			finished.append([path, packed]))
	var token: int = loader.begin(ARENA_PATH, "TEST entering the arena")
	_expect_true(token > 0, "paint-first: begin takes a token")
	# One frame in, the veil is up but the worker has nothing: the first
	# paint provably lands before the expensive request goes out.
	await get_tree().process_frame
	_expect_true(loader.visible, "paint-first: overlay visible at once")
	_expect_true(not loader.is_request_issued(),
		"paint-first: no request before the first paint")
	_expect_true((loader.get_node("LoadingCard/Stack/Progress") as ProgressBar) \
		.value == 0.0, "paint-first: bar starts at a true zero")
	_expect_loader_layout(loader, "paint-first/first")
	# No worker-status assert here: the warmup above touched the worker
	# cache on purpose (to keep engine warnings out), so only the
	# overlay's own `is_request_issued` flag proves the ordering — and it
	# proves it exactly, since nothing else in this process can ask.
	var done: bool = await _settle(loader)
	_expect_true(done, "paint-first: arena load settles")
	_expect_true(finished.size() == 1 \
		and finished[0][0] == ARENA_PATH \
		and finished[0][1] != null,
		"paint-first: finished hands over the packed scene")
	_expect_true(not loader.visible,
		"paint-first: overlay hides once the host takes over")
	await _free_loader(loader)


func _test_cancel_before_request() -> void:
	var loader: GateLoadingOverlay = _make_loader()
	await get_tree().process_frame
	# Arrays, not ints: lambdas capture primitives by value, so an int
	# counter would never move. Every count below appends.
	var finished: Array = []
	var cancelled: Array = []
	loader.finished.connect(
		func(_path: String, _packed: PackedScene, _token: int) -> void:
			finished.append(true))
	loader.cancelled.connect(
		func(path: String, _token: int) -> void: cancelled.append(path))
	var token: int = loader.begin(ARENA_PATH, "TEST entering the arena")
	loader.cancel()
	_expect_true(token > 0, "early-cancel: begin takes a token")
	_expect_true(cancelled == [ARENA_PATH],
		"early-cancel: cancel signals once")
	_expect_true(not loader.is_request_issued(),
		"early-cancel: request never goes out")
	_expect_true(loader.is_showing_cancelled(),
		"early-cancel: cancelled card shows")
	for _index in 10:
		await get_tree().process_frame
	_expect_loader_layout(loader, "early-cancel/card")
	_expect_true(finished.is_empty(),
		"early-cancel: nothing finishes after the cancel")
	await _free_loader(loader)


func _test_cancel_after_request() -> void:
	var loader: GateLoadingOverlay = _make_loader()
	await get_tree().process_frame
	var finished: Array = []
	var cancelled: Array = []
	loader.finished.connect(
		func(_path: String, _packed: PackedScene, _token: int) -> void:
			finished.append(true))
	loader.cancelled.connect(
		func(path: String, _token: int) -> void: cancelled.append(path))
	loader.begin(ARENA_PATH, "TEST entering the arena")
	# Wait until the request really went out, then cancel mid-flight. On a
	# warm cache the worker may genuinely finish first; what the guard owns
	# is narrower and exact: after `cancel()` returns, no `finished` may
	# ever arrive for the cancelled token.
	var start: int = Time.get_ticks_msec()
	while not loader.is_request_issued() \
			and Time.get_ticks_msec() - start < LOAD_DEADLINE_MSEC:
		await get_tree().create_timer(LOAD_POLL_SECONDS).timeout
	_expect_true(loader.is_request_issued(),
		"mid-cancel: request went out before the cancel")
	var was_loading: bool = loader.is_loading()
	var at_cancel: int = finished.size()
	loader.cancel()
	if was_loading:
		_expect_true(cancelled == [ARENA_PATH],
			"mid-cancel: mid-flight cancel signals once")
		_expect_true(at_cancel == 0,
			"mid-cancel: live token had not finished")
	else:
		_expect_true(at_cancel == 1 and cancelled.is_empty(),
			"mid-cancel: genuine early finish stands, cancel no-ops")
	var settled: bool = await _settle_background(ARENA_PATH)
	_expect_true(settled, "mid-cancel: background load settles")
	for _index in 5:
		await get_tree().process_frame
	if loader.is_showing_cancelled():
		_expect_loader_layout(loader, "mid-cancel/card")
	_expect_true(finished.size() == at_cancel,
		"mid-cancel: cancelled load never finishes late")
	_expect_true(await _settle_drain(loader),
		"mid-cancel: orphan drain completes")
	await _free_loader(loader)


func _test_stale_completion_guard() -> void:
	var loader: GateLoadingOverlay = _make_loader()
	await get_tree().process_frame
	var finished: Array = []
	loader.finished.connect(
		func(path: String, _packed: PackedScene, token: int) -> void:
			finished.append([path, token]))
	var first_token: int = loader.begin(ARENA_PATH, "TEST first")
	loader.cancel()
	var second_token: int = loader.begin(SMALL_SCENE_PATH, "TEST second")
	_expect_true(second_token != first_token,
		"stale-guard: each begin takes a fresh token")
	var done: bool = await _settle(loader)
	_expect_true(done, "stale-guard: second load settles")
	_expect_true(finished.size() == 1 \
		and finished[0][0] == SMALL_SCENE_PATH \
		and finished[0][1] == second_token,
		"stale-guard: only the live token finishes")
	await _free_loader(loader)


func _test_rapid_rebegin() -> void:
	var loader: GateLoadingOverlay = _make_loader()
	await get_tree().process_frame
	var finished: Array = []
	loader.finished.connect(
		func(path: String, _packed: PackedScene, token: int) -> void:
			finished.append([path, token]))
	# Two begins in one frame: the first request is still behind its
	# paint gate when the second supersedes it, so the first path must
	# never reach the worker at all.
	var first_token: int = loader.begin(STALE_PATH, "TEST stale")
	var second_token: int = loader.begin(SMALL_SCENE_PATH, "TEST live")
	_expect_true(second_token != first_token,
		"rebegin: superseding begin takes a fresh token")
	var done: bool = await _settle(loader)
	_expect_true(done, "rebegin: live load settles")
	_expect_true(finished.size() == 1 \
		and finished[0][0] == SMALL_SCENE_PATH \
		and finished[0][1] == second_token,
		"rebegin: only the live token finishes")
	_expect_true(
		ResourceLoader.load_threaded_get_status(STALE_PATH) \
			== ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"rebegin: superseded path never reached the worker")
	await _free_loader(loader)


func _test_cancel_drains_orphan() -> void:
	var loader: GateLoadingOverlay = _make_loader()
	await get_tree().process_frame
	var finished: Array = []
	var failed: Array = []
	var cancelled: Array = []
	loader.finished.connect(
		func(_path: String, _packed: PackedScene, _token: int) -> void:
			finished.append(true))
	loader.failed.connect(
		func(path: String, _message: String, _token: int) -> void:
			failed.append(path))
	loader.cancelled.connect(
		func(path: String, _token: int) -> void: cancelled.append(path))
	# A worker load completed but left unclaimed, exactly the shape a
	# mid-flight cancel leaves behind. Warm round-trips are silent.
	_expect_true(await _request_unclaimed(SMALL_SCENE_PATH),
		"drain-cancel: setup load completes unclaimed")
	# White-box issued state: `begin` sets loading synchronously, and the
	# direct request above stands in for the paint gate's own request.
	loader.begin(SMALL_SCENE_PATH, "TEST doomed")
	loader.set("_request_issued", true)
	loader.cancel()
	_expect_true(cancelled == [SMALL_SCENE_PATH],
		"drain-cancel: cancel signals once")
	_expect_true(loader.has_pending_drain(),
		"drain-cancel: issued load is orphaned, not dropped")
	_expect_true(await _settle_drain(loader),
		"drain-cancel: orphan drain completes")
	# Fault injection: the stale token's flags are raised again behind the
	# overlay's back. The retired generation must still contain it: no
	# late `finished` AND no spurious `failed` for the cancelled path.
	loader.set("_loading", true)
	loader.set("_request_issued", true)
	for _index in 5:
		await get_tree().process_frame
	_expect_true(finished.is_empty() and failed.is_empty(),
		"drain-cancel: retired token stays silent")
	loader.set("_loading", false)
	loader.set("_request_issued", false)
	await _free_loader(loader)


func _test_rebegin_drains_orphan() -> void:
	var loader: GateLoadingOverlay = _make_loader()
	await get_tree().process_frame
	var finished: Array = []
	var failed: Array = []
	loader.finished.connect(
		func(path: String, _packed: PackedScene, token: int) -> void:
			finished.append([path, token]))
	loader.failed.connect(
		func(path: String, _message: String, _token: int) -> void:
			failed.append(path))
	_expect_true(await _request_unclaimed(SMALL_SCENE_PATH),
		"drain-rebegin: setup load completes unclaimed")
	loader.begin(SMALL_SCENE_PATH, "TEST doomed")
	loader.set("_request_issued", true)
	var live_token: int = loader.begin(ARENA_PATH, "TEST live")
	_expect_true(loader.has_pending_drain(),
		"drain-rebegin: superseded load is orphaned, not dropped")
	var done: bool = await _settle(loader)
	_expect_true(done, "drain-rebegin: live load settles")
	_expect_true(finished.size() == 1 \
		and finished[0][0] == ARENA_PATH \
		and finished[0][1] == live_token,
		"drain-rebegin: only the live token finishes")
	_expect_true(await _settle_drain(loader),
		"drain-rebegin: orphan drain completes")
	_expect_true(finished.size() == 1 and failed.is_empty(),
		"drain-rebegin: drained orphan never surfaces")
	await _free_loader(loader)


## Worker-request a path and wait until it completes, without claiming it.
## Returns false on timeout. Warm paths keep this silent.
func _request_unclaimed(path: String) -> bool:
	if ResourceLoader.load_threaded_request(path) != OK:
		return ResourceLoader.load_threaded_get_status(path) \
			== ResourceLoader.THREAD_LOAD_LOADED
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < LOAD_DEADLINE_MSEC:
		if ResourceLoader.load_threaded_get_status(path) \
				== ResourceLoader.THREAD_LOAD_LOADED:
			return true
		await get_tree().create_timer(LOAD_POLL_SECONDS).timeout
	return false


func _test_unusable_path_error() -> void:
	var loader: GateLoadingOverlay = _make_loader()
	await get_tree().process_frame
	var failed: Array = []
	var retried: Array = []
	var returned: Array = []
	loader.failed.connect(
		func(path: String, _message: String, _token: int) -> void:
			failed.append(path))
	loader.retry_requested.connect(
		func(path: String) -> void: retried.append(path))
	loader.return_requested.connect(
		func() -> void: returned.append(true))
	loader.begin(NON_SCENE_PATH, "TEST entering nowhere")
	var done: bool = await _settle(loader)
	_expect_true(done, "error: unusable path settles")
	_expect_true(failed == [NON_SCENE_PATH],
		"error: failure reported honestly")
	_expect_true(loader.is_showing_error(),
		"error: error card shows")
	_expect_true(loader.get_node("LoadingCard/Stack/Buttons/Retry").visible,
		"error: retry offered")
	_expect_true(loader.get_node("LoadingCard/Stack/Buttons/Back").visible,
		"error: return offered")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_loader_layout(loader, "error/card")
	(loader.get_node("LoadingCard/Stack/Buttons/Retry") as Button).pressed.emit()
	_expect_true(retried == [NON_SCENE_PATH],
		"error: retry signals the path")
	done = await _settle(loader)
	_expect_true(done and failed == [NON_SCENE_PATH, NON_SCENE_PATH],
		"error: retry re-runs the same honest load")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_loader_layout(loader, "error/retry-card")
	(loader.get_node("LoadingCard/Stack/Buttons/Back") as Button).pressed.emit()
	_expect_true(returned == [true], "error: return signals the host")
	_expect_true(not loader.visible, "error: return rests the overlay")
	await _free_loader(loader)


## Wait until this loader stops, bounded by wall time.
func _settle(loader: GateLoadingOverlay) -> bool:
	var start: int = Time.get_ticks_msec()
	while loader.is_loading() \
			and Time.get_ticks_msec() - start < LOAD_DEADLINE_MSEC:
		await get_tree().create_timer(LOAD_POLL_SECONDS).timeout
	return not loader.is_loading()


## Wait until the worker drops this path, bounded by wall time, then claim
## the result: a completed load left unclaimed would be replaced (and
## leaked) by the next request for the same path. Claiming twice is safe —
## the cache serves the second claim — so this also covers loads the
## overlay's own orphan drain already claimed.
func _settle_background(path: String) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < LOAD_DEADLINE_MSEC:
		var status: ResourceLoader.ThreadLoadStatus = \
			ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
			return true
		if status == ResourceLoader.THREAD_LOAD_FAILED \
				or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return true
		await get_tree().create_timer(LOAD_POLL_SECONDS).timeout
	return false


## Wait until the overlay reports its orphan drain empty, bounded by time.
func _settle_drain(loader: GateLoadingOverlay) -> bool:
	var start: int = Time.get_ticks_msec()
	while loader.has_pending_drain() \
			and Time.get_ticks_msec() - start < LOAD_DEADLINE_MSEC:
		await get_tree().create_timer(LOAD_POLL_SECONDS).timeout
	return not loader.has_pending_drain()


## First paint in every locale, long wrapping stage/detail through the real
## text-change and fail cards, capped to the existing two-line maximum.
func _test_wrapped_glyph_heights() -> void:
	var original_locale: String = TranslationServer.get_locale()
	for locale in ["ko", "en", "ja", "zh_CN", "zh_TW"]:
		TranslationServer.set_locale(locale)
		var staged: GateLoadingOverlay = _make_loader()
		await get_tree().process_frame
		var stage_text: String = GateEntryStrings.text(
			"gate.loading.preparing")
		staged.begin(SMALL_SCENE_PATH, stage_text)
		await get_tree().process_frame
		_expect_true(not staged.is_request_issued(),
			"glyph/%s: no request before first paint" % locale)
		_expect_loader_layout(staged, "glyph/%s/first" % locale)
		staged.cancel()
		await _free_loader(staged)
	TranslationServer.set_locale(original_locale)
	# Long wrapping stage via the public text-change path, on a stable
	# cancelled card so no worker race can hide the overlay mid-check.
	var loader: GateLoadingOverlay = _make_loader()
	await get_tree().process_frame
	loader.begin(SMALL_SCENE_PATH, "TEST entering somewhere")
	await get_tree().process_frame
	loader.cancel()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_loader_layout(loader, "glyph/cancelled")
	var long_stage: String = "TEST entering somewhere with a very long stage line " \
		+ "that must wrap past two lines at card width for sure and more words"
	loader.set_stage_text(long_stage)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_loader_layout(loader, "glyph/long-stage")
	var stage: Label = loader.get_node(
		"LoadingCard/Stack/Stage") as Label
	_expect_true(stage.get_line_count() >= 3,
		"glyph: long stage wraps past max (%d)" % stage.get_line_count())
	_expect_true(stage.get_visible_line_count() == 2,
		"glyph: long stage capped to two")
	loader.set_stage_text("TEST entering somewhere")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_loader_layout(loader, "glyph/short-again")
	await _free_loader(loader)
	# Long detail through the honest fail card: white-box message, real
	# reserve and refit, failed before the paint gate so no worker runs.
	var failed_loader: GateLoadingOverlay = _make_loader()
	await get_tree().process_frame
	failed_loader.begin(SMALL_SCENE_PATH, "TEST entering somewhere")
	await get_tree().process_frame
	var long_detail: String = "TEST very long error detail that must wrap past " \
		+ "two lines at card width for sure and more detail text to push it " \
		+ "over the edge for testing wrapped glyph heights here"
	failed_loader._fail_if_current(
		failed_loader.current_token(), SMALL_SCENE_PATH, long_detail)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(failed_loader.is_showing_error(),
		"glyph: long-detail error shows")
	_expect_loader_layout(failed_loader, "glyph/long-detail")
	var detail: Label = failed_loader.get_node(
		"LoadingCard/Stack/Detail") as Label
	_expect_true(detail.get_line_count() >= 3,
		"glyph: long detail wraps past max (%d)" % detail.get_line_count())
	_expect_true(detail.get_visible_line_count() == 2,
		"glyph: long detail capped to two")
	await _free_loader(failed_loader)


## Wrapped need for a clipped label: capped lines times font height plus
## spacing, from the label's own line count (which stays correct even when
## its rect collapsed to 1px). Independent of the overlay's reserve path.
func _wrapped_need(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var line: float = float(font.get_height(font_size))
	var spacing: float = float(label.get_theme_constant("line_spacing"))
	var lines: int = label.get_line_count()
	var max_lines: int = label.max_lines_visible
	var capped: int = mini(lines, max_lines) if max_lines > 0 else lines
	capped = maxi(capped, 1)
	return float(capped) * line + float(capped - 1) * spacing


## Actual rect vs rendered need for one wrapped label.
func _expect_readable_wrapped(
		loader: GateLoadingOverlay, label_path: String, tag: String) -> void:
	var label: Label = loader.get_node(label_path) as Label
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var line: float = float(font.get_height(font_size))
	var need: float = _wrapped_need(label)
	var rect: Rect2 = label.get_global_rect()
	var max_lines: int = label.max_lines_visible
	var capped: int = mini(label.get_line_count(), max_lines) \
		if max_lines > 0 else label.get_line_count()
	capped = maxi(capped, 1)
	_expect_true(label.visible and label.is_visible_in_tree(),
		"%s: %s visible" % [tag, label.name])
	_expect_true(not label.text.is_empty(),
		"%s: %s has text" % [tag, label.name])
	_expect_true(rect.size.x > 64.0,
		"%s: %s readable width %s" % [tag, label.name, rect.size])
	_expect_true(rect.size.y >= line - 0.5,
		"%s: %s at least one line %s >= %s" % [
			tag, label.name, rect.size.y, line])
	_expect_true(rect.size.y >= need - 0.5,
		"%s: %s wrapped need %s >= %s" % [
			tag, label.name, rect.size.y, need])
	_expect_true(rect.size.y > 1.5,
		"%s: %s not 1px %s" % [tag, label.name, rect.size.y])
	_expect_true(label.custom_minimum_size.y >= need - 0.5,
		"%s: %s reserved %s >= %s" % [
			tag, label.name, label.custom_minimum_size.y, need])
	_expect_true(label.get_visible_line_count() >= capped,
		"%s: %s glyphs visible %d >= %d" % [
			tag, label.name, label.get_visible_line_count(), capped])


## Card inside, wrapped labels readable, stack children disjoint, buttons
## inside card and viewport. Call only while the loader card is visible.
func _expect_loader_layout(loader: GateLoadingOverlay, tag: String) -> void:
	var viewport: Rect2 = Rect2(Vector2.ZERO, get_tree().root.size)
	var card: PanelContainer = loader.get_node("LoadingCard") as PanelContainer
	var card_rect: Rect2 = card.get_global_rect()
	_expect_true(viewport.encloses(card_rect.grow(-0.5)),
		"%s: card inside %s" % [tag, card_rect])
	if (loader.get_node("LoadingCard/Stack/Stage") as Label) \
			.is_visible_in_tree():
		_expect_readable_wrapped(loader, "LoadingCard/Stack/Stage", tag)
	if (loader.get_node("LoadingCard/Stack/Detail") as Label) \
			.is_visible_in_tree():
		_expect_readable_wrapped(loader, "LoadingCard/Stack/Detail", tag)
	var parts: Array = []
	for path in ["LoadingCard/Stack/Stage", "LoadingCard/Stack/Progress",
			"LoadingCard/Stack/Status", "LoadingCard/Stack/Detail",
			"LoadingCard/Stack/Buttons"]:
		var child: Control = loader.get_node(path) as Control
		if child.is_visible_in_tree():
			parts.append(child)
	for index in parts.size():
		var first: Control = parts[index] as Control
		for other in range(index + 1, parts.size()):
			var second: Control = parts[other] as Control
			var overlap: bool = first.get_global_rect().grow(-1.0) \
				.intersects(second.get_global_rect().grow(-1.0))
			_expect_true(not overlap, "%s: %s and %s do not overlap" % [
				tag, first.name, second.name])
	for button_path in ["LoadingCard/Stack/Buttons/Cancel",
			"LoadingCard/Stack/Buttons/Retry",
			"LoadingCard/Stack/Buttons/Back"]:
		var button: Button = loader.get_node(button_path) as Button
		if not button.is_visible_in_tree():
			continue
		var rect: Rect2 = button.get_global_rect()
		_expect_true(viewport.encloses(rect.grow(-0.5)),
			"%s: %s inside %s" % [tag, button.name, rect])
		_expect_true(card_rect.grow(-1.0).encloses(rect.grow(-0.5)),
			"%s: %s inside its card" % [tag, button.name])


func _expect_true(value: bool, message: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("  FAIL ", message)
