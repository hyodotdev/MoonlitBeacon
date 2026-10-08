extends Node

## Gate lodge scene tests: layout math, Lumi rig, first-login flow.
##
## Scene-based because the lodge binds the player rig, the room plates,
## and the host account in one tree. The production host behind it is a
## fake that speaks the same ten-method contract; the player, the stick,
## the dash button, and the Vault/Onboarding writes are all real.

const LODGE_SCENE: PackedScene = preload(
	"res://scenes/gameplay/gate_lodge.tscn")
const REVIEW_SCRIPT: Script = preload("res://tools/lodge_review.gd")
const FRAMINGS: Array[Vector2] = [
	Vector2(808, 360), Vector2(840, 360), Vector2(808, 606),
	Vector2(808, 532)]
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const FAKE_ID: String = "MB-lodgetest0000000000000000000001"

## Thirty-three dialogue keys the lodge reads through GateEntryStrings.
const LODGE_KEYS: Array[String] = [
	"gate.lodge.lumi_name", "gate.lodge.greet_1", "gate.lodge.greet_2",
	"gate.lodge.greet_3", "gate.lodge.ask_name", "gate.lodge.name_title",
	"gate.lodge.name_hint", "gate.lodge.name_public",
	"gate.lodge.name_confirm", "gate.lodge.name_retry",
	"gate.lodge.name_checking", "gate.lodge.name_invalid",
	"gate.lodge.name_taken", "gate.lodge.name_offline",
	"gate.lodge.named_ok", "gate.lodge.move_lesson",
	"gate.lodge.move_done", "gate.lodge.dash_lesson",
	"gate.lodge.dash_done", "gate.lodge.gate_lesson",
	"gate.lodge.gate_wait", "gate.lodge.gate_retry", "gate.lodge.skip",
	"gate.lodge.tap_next", "gate.lodge.depart_title",
	"gate.lodge.depart_saved", "gate.lodge.depart_where",
	"gate.lodge.depart_resume", "gate.lodge.depart_fresh",
	"gate.lodge.depart_fresh_confirm", "gate.lodge.depart_back",
	"gate.lodge.account_lost", "gate.lodge.return_title",
]

var _failed: int = 0
var _checked: int = 0


## The ten lodge-facing host methods plus the account signal. Claim and
## seal replies come from queues so each test scripts its own network.
class LodgeFakeHost extends Node:
	signal production_changed(state: Dictionary)

	var public_id: String = FAKE_ID
	var display: String = ""
	var intro: bool = false
	var load_reply: Dictionary = {}
	var cache_on_load: bool = false
	var claim_queue: Array = []
	var seal_queue: Array = []
	var saved: Dictionary = {"has_save": false}
	var exit_plan: Dictionary = {}
	var exit_calls: Array = []
	var cancels: int = 0
	var deleted: bool = false

	func account_state() -> Dictionary:
		return {"public_id": public_id, "deletion_in_flight": deleted}

	func needs_lodge_lesson() -> bool:
		return display.is_empty() or not intro

	func verified_display_name() -> String:
		return display

	func load_adventurer_name() -> Dictionary:
		await get_tree().process_frame
		if not load_reply.is_empty():
			# An acknowledging coordinator caches the verified row, so
			# the host's cached readiness flips with the reply.
			if cache_on_load \
				and str(load_reply.get("status", "")) == "ok":
				display = str(load_reply.get("display", display))
				intro = bool(load_reply.get("intro_complete", intro))
			return load_reply.duplicate(true)
		if display.is_empty():
			return {"status": "failure", "code": "adventurer-not-found",
				"retryable": false}
		return {"status": "ok", "display": display, "key": "key",
			"intro_complete": intro, "source": "cloud"}

	func claim_adventurer_name(_text: String) -> Dictionary:
		await get_tree().process_frame
		if claim_queue.is_empty():
			return {"status": "failure", "code": "offline",
				"retryable": true}
		return (claim_queue.pop_front() as Dictionary).duplicate(true)

	func mark_intro_complete() -> Dictionary:
		await get_tree().process_frame
		if seal_queue.is_empty():
			intro = true
			return {"status": "ok"}
		var reply: Dictionary = (
			seal_queue.pop_front() as Dictionary).duplicate(true)
		if str(reply.get("status", "")) == "ok":
			intro = true
		return reply

	func saved_gate_summary() -> Dictionary:
		return saved.duplicate(true)

	func plan_lodge_exit(fresh: bool, confirmed: bool) -> Dictionary:
		exit_calls.append({"fresh": fresh, "confirmed": confirmed})
		if not exit_plan.is_empty():
			return exit_plan.duplicate(true)
		return {"status": "ok",
			"arena": "res://scenes/gameplay/arena.tscn",
			"fresh": fresh, "account_id": public_id}

	func confirm_entry_account(account_id: String) -> bool:
		return account_id == public_id

	func cancel_entry_plan() -> void:
		cancels += 1


func _ready() -> void:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path(
		"user://").simplify_path()
	if expected_root.is_empty() or not user_root.begins_with(
		expected_root + "/"):
		printerr("lodge tests aborted: user:// path is not isolated — ",
			user_root)
		get_tree().quit(2)
		return
	GateEntryStrings.ensure_loaded()
	Onboarding.path = "user://lodge_onboarding_test.json"
	_run.call_deferred()


func _run() -> void:
	_wipe()
	_test_layout_framings()
	_test_lumi_rig()
	_test_lumi_world_bounds()
	_test_lumi_idle_feet_planted()
	_test_csv_keys()
	_test_strings_resolve()
	_test_name_keyboard_math()
	await _test_name_keyboard_compact()
	await _test_name_keyboard_dismiss()
	await _test_greeting_keeps_hero_visible()
	await _test_contact_board_audit()
	await _test_boot_completed_departs()
	await _test_boot_cold_completed_departs()
	await _test_boot_recovers_claimed_name()
	await _test_boot_form_states()
	await _test_claim_buckets()
	await _test_full_lesson_to_departure()
	await _test_seal_retry_and_departure_choice()
	await _test_account_loss_retires()
	await _test_guards_and_push_out()
	await _test_desk_projection_stays_on_walk()
	await _test_desk_negative_control()
	_test_desk_exit_fallback()
	_report()


func _wipe() -> void:
	for path in ["user://vault.cfg", "user://vault.cfg.tmp",
		"user://lodge_onboarding_test.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path))
	Vault.load_vault()
	Onboarding.forget_cache()
	Journey.disarm()


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("FAIL lodge: ", label)


func _expect_false(value: bool, label: String) -> void:
	_expect_true(not value, label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		_failed += 1
		printerr("FAIL lodge: ", label, " (got ", actual,
			", want ", expected, ")")


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _make_lodge(fake: LodgeFakeHost) -> Node:
	add_child(fake)
	var lodge: Node = LODGE_SCENE.instantiate()
	lodge.host_override = fake
	lodge.embedded = true
	add_child(lodge)
	return lodge


func _free_lodge(lodge: Node, fake: LodgeFakeHost) -> void:
	lodge.queue_free()
	fake.queue_free()
	await get_tree().process_frame


func _tap_speech(lodge: Node) -> void:
	lodge._advance_speech()


## Keyboard-aware name form: the device-pixel keyboard height
## converts through the live screen transform before any layout, the
## shift math clears the confirm action above it, the lift parks at
## the safe top when space runs out, and the QA report carries
## bounds only with device and viewport figures kept apart.
func _test_name_keyboard_math() -> void:
	# Director's 808x360 desktop geometry: confirm ends at y275, a
	# 144px keyboard covers y216-360, so the form rises 67px.
	_expect_equal(GateLodge.keyboard_shift_for(275.0, 360.0,
		144.0), 67.0, "keyboard lifts the covered confirm")
	_expect_equal(GateLodge.keyboard_shift_for(200.0, 606.0,
		200.0), 0.0, "tall viewport needs no lift")
	_expect_equal(GateLodge.keyboard_shift_for(275.0, 360.0,
		0.0), 0.0, "hidden keyboard never shifts")
	_expect_equal(GateLodge.keyboard_shift_for(275.0, 360.0,
		-5.0), 0.0, "absurd height never shifts")
	var view := Rect2(Vector2.ZERO, Vector2(808, 360))
	# Director's measured case: 432 device px at 3x over a 360
	# viewport occludes 144 viewport px. Raw pixels fed straight
	# into the shift wrongly returned 354; converted, the confirm
	# at 274 rises exactly 66.
	var x3 := Transform2D(Vector2(3, 0), Vector2(0, 3),
		Vector2.ZERO)
	_expect_equal(GateLodge.keyboard_occlusion_for(view,
		Vector2(2424, 1080), 432.0, x3), 144.0,
		"keyboard converts 3x device px to viewport px")
	_expect_equal(GateLodge.keyboard_shift_for(274.0, 360.0,
		GateLodge.keyboard_occlusion_for(view,
			Vector2(2424, 1080), 432.0, x3)), 66.0,
		"keyboard converts, then lifts 66px, never 354")
	var x1 := Transform2D(Vector2(1, 0), Vector2(0, 1),
		Vector2.ZERO)
	_expect_equal(GateLodge.keyboard_occlusion_for(view,
		Vector2(808, 360), 100.0, x1), 100.0,
		"keyboard passes scale-1 heights through")
	var x25 := Transform2D(Vector2(2.5, 0), Vector2(0, 2.5),
		Vector2.ZERO)
	_expect_true(absf(GateLodge.keyboard_occlusion_for(view,
		Vector2(2020, 900), 250.0, x25) - 100.0) < 0.001,
		"keyboard converts a non-integer density")
	var boxed := Transform2D(Vector2(2, 0), Vector2(0, 2),
		Vector2(0, 40))
	_expect_true(absf(GateLodge.keyboard_occlusion_for(view,
		Vector2(1616, 800), 200.0, boxed) - 80.0) < 0.001,
		"keyboard honors the letterbox offset, not just scale")
	_expect_equal(GateLodge.keyboard_occlusion_for(view,
		Vector2(2424, 1080), 2000.0, x3), 360.0,
		"keyboard taller than the screen clamps to the viewport")
	_expect_equal(GateLodge.keyboard_occlusion_for(view,
		Vector2(2424, 1080), 0.0, x3), 0.0,
		"hidden keyboard occludes nothing")
	_expect_equal(GateLodge.keyboard_occlusion_for(view,
		Vector2(2424, 1080), -50.0, x3), 0.0,
		"absurd keyboard occludes nothing")
	var flat := Transform2D(Vector2.ZERO, Vector2.ZERO,
		Vector2.ZERO)
	_expect_equal(GateLodge.keyboard_occlusion_for(view,
		Vector2(2424, 1080), 432.0, flat), 0.0,
		"degenerate transform occludes nothing")
	_expect_equal(GateLodge.keyboard_lift_for(274.0, 360.0,
		144.0, 120.0, 0.0), 66.0,
		"lift takes the full shift with headroom")
	_expect_equal(GateLodge.keyboard_lift_for(274.0, 360.0,
		144.0, 40.0, 0.0), 40.0,
		"lift parks at the safe top when cramped")
	_expect_equal(GateLodge.keyboard_lift_for(274.0, 360.0,
		144.0, 0.0, 0.0), 0.0,
		"lift never displaces negatively")
	_expect_equal(GateLodge.keyboard_lift_for(200.0, 606.0,
		200.0, 120.0, 0.0), 0.0,
		"lift rests when nothing is covered")
	var fake := LodgeFakeHost.new()
	var lodge: Node = _make_lodge(fake)
	var report: Dictionary = lodge.call(
		"name_form_keyboard_report")
	var keys: Array = report.keys()
	keys.sort()
	# The old single keyboard_height mixed device pixels with
	# viewport layout; the report now names each figure's units.
	_expect_equal(keys, ["confirm_rect", "field_rect",
		"form_visible", "keyboard_height_device",
		"keyboard_occlusion", "keyboard_visible", "panel_rect",
		"shifted"], "keyboard report carries bounds only")
	_expect_false(bool(report["keyboard_visible"]),
		"headless reports no keyboard")
	_expect_equal(int(report["keyboard_height_device"]), 0,
		"headless reports zero device height")
	_expect_equal(float(report["keyboard_occlusion"]), 0.0,
		"headless reports zero occlusion")
	_free_lodge(lodge, fake)


## Tall-keyboard name form: the same production `_apply_keyboard_shift`
## hook that runs every live frame adapts the actual form — a short
## lift while it fits, the compact short card when it does not — and
## restores the full card on hide. The real field, error feedback, and
## confirm bounds (never the clamp math alone) stay inside the
## available safe rect with the margin, at phone and tablet framings,
## in every locale, under every feedback text. Headless stages device
## pixels 1:1 with viewport pixels; the math test pins the 3x density.
func _test_name_keyboard_compact() -> void:
	var original_size: Vector2i = get_tree().root.size
	var original_scale: Vector2i = (
		get_tree().root.content_scale_size)
	var original_locale: String = TranslationServer.get_locale()
	for framing in [Vector2(808, 360), Vector2(808, 606)]:
		var tag: String = "%dx%d" % [
			int(framing.x), int(framing.y)]
		get_tree().root.size = Vector2i(
			int(framing.x), int(framing.y))
		get_tree().root.content_scale_size = Vector2i(
			int(framing.x), int(framing.y))
		await _frames(2)
		for locale in LOCALES:
			TranslationServer.set_locale(locale)
			await _frames(1)
			await _check_keyboard_form(tag, locale)
	TranslationServer.set_locale(original_locale)
	get_tree().root.size = original_size
	get_tree().root.content_scale_size = original_scale
	await _frames(2)


func _check_keyboard_form(tag: String, locale: String) -> void:
	var label: String = "%s %s" % [tag, locale]
	_wipe()
	var fake := LodgeFakeHost.new()
	var lodge: Node = _make_lodge(fake)
	await _frames(5)
	_tap_speech(lodge)
	_tap_speech(lodge)
	_tap_speech(lodge)
	await _frames(5)
	_expect_equal(lodge.lodge_state(), GateLodge.State.NAME,
		label + ": reaches the register")
	_expect_equal(lodge._camera.process_callback,
		Camera2D.CAMERA2D_PROCESS_PHYSICS,
		label + ": the lodge camera rides physics")
	# Freeze the live hook (headless reads no keyboard and would
	# restore); every case below drives the same hook by hand.
	lodge.set_process(false)
	lodge._name_field.text = "Wanderer"
	var view: Rect2 = get_viewport().get_visible_rect()
	var xform: Transform2D = (
		get_viewport().get_screen_transform())
	# Headless owns no window (live size reads 0,0), so the tests
	# stage the window they resized the viewport to.
	var window: Vector2 = view.size
	for height in [40.0, 144.0, 180.0, 200.0, 400.0]:
		_expect_equal(GateLodge.keyboard_occlusion_for(
			view, window, height, xform),
			minf(height, view.size.y),
			label + ": stages device px 1:1")
	var small: float = 40.0
	var mids: Array = [200.0] if tag == "808x606" else []
	var talls: Array = [400.0] if tag == "808x606" \
		else [144.0, 180.0]
	for key in ["", "gate.lodge.name_taken",
		"gate.lodge.name_offline", "gate.lodge.name_invalid"]:
		var feedback: String = "clean" if key.is_empty() else key
		lodge._name_status.text = "" if key.is_empty() else \
			GateEntryStrings.text(key)
		lodge._seat_visible(lodge._name_panel, "top")
		await _frames(3)
		var full_rect: Rect2 = (
			lodge._name_panel.get_global_rect())
		var case: String = "%s %s" % [label, feedback]
		await _check_keyboard_lifted(lodge, case, view, small)
		for mid in mids:
			await _check_keyboard_lifted(lodge, case, view, mid)
		for tall in talls:
			await _check_keyboard_compact_case(
				lodge, case, view, tall, full_rect)
		var out: Dictionary = lodge._apply_keyboard_shift(
			0.0, view.size)
		await _frames(3)
		_expect_equal(str(out.get("mode", "")), "restored",
			case + ": hiding restores")
		var back: Rect2 = lodge._name_panel.get_global_rect()
		_expect_true(is_equal_approx(back.position.x,
			full_rect.position.x) and is_equal_approx(
			back.position.y, full_rect.position.y)
			and is_equal_approx(back.size.x, full_rect.size.x)
			and is_equal_approx(back.size.y, full_rect.size.y),
			case + ": hiding restores the full card "
			+ "(%s)" % str(back))
		_expect_true(lodge._name_head.visible
			and lodge._name_hint.visible,
			case + ": hiding restores the chrome")
		_expect_equal(lodge._name_field.text, "Wanderer",
			case + ": hiding keeps the typed value")
	lodge.set_process(true)
	await _free_lodge(lodge, fake)


## A keyboard the plain lift still clears: full chrome stays, the
## real confirm bottom lands on the margin line, and repeats hold.
func _check_keyboard_lifted(lodge: Node, case: String, view: Rect2,
		height: float) -> void:
	var staged: Vector2 = view.size
	var out: Dictionary = lodge._apply_keyboard_shift(
		height, staged)
	await _frames(3)
	_expect_equal(str(out.get("mode", "")), "lifted",
		"%s lift %.0f: lifts, never compacts" % [case, height])
	_expect_true(lodge._name_head.visible
		and lodge._name_hint.visible,
		"%s lift %.0f: keeps the full chrome" % [case, height])
	var kb_top: float = view.size.y - height
	var bottom: float = lodge._name_confirm.get_global_rect().end.y
	_expect_true(bottom <= kb_top - 8.0 + 0.5,
		"%s lift %.0f: the confirm clears (%.1f)" % [
			case, height, bottom])
	var settled: float = lodge._name_panel.position.y
	lodge._apply_keyboard_shift(height, staged)
	lodge._apply_keyboard_shift(height, staged)
	_expect_equal(lodge._name_panel.position.y, settled,
		"%s lift %.0f: the layout holds still" % [case, height])


## A keyboard the plain lift cannot clear: the short card takes over
## and the real field, feedback, and confirm all stay visible above
## it with the margin, holding still across repeats.
func _check_keyboard_compact_case(lodge: Node, case: String,
		view: Rect2, height: float, full_rect: Rect2) -> void:
	var staged: Vector2 = view.size
	var out: Dictionary = lodge._apply_keyboard_shift(
		height, staged)
	await _frames(3)
	_expect_equal(str(out.get("mode", "")), "compact",
		"%s tall %.0f: compacts the card" % [case, height])
	_expect_false(lodge._name_head.visible
		or lodge._name_hint.visible,
		"%s tall %.0f: hides the optional chrome" % [case, height])
	_expect_true(bool(out.get("clears", false)),
		"%s tall %.0f: the short card clears" % [case, height])
	_expect_true(lodge._name_panel.size.y < full_rect.size.y,
		"%s tall %.0f: the card shrinks" % [case, height])
	var kb_top: float = view.size.y - height
	var top: float = lodge._name_panel.position.y
	_expect_true(top >= -0.5,
		"%s tall %.0f: the card stays onscreen" % [case, height])
	for path in ["_name_field", "_name_status", "_name_confirm"]:
		var rect: Rect2 = (lodge.get(path) as Control
			).get_global_rect()
		_expect_true(rect.position.y >= top - 0.5
			and rect.end.y <= kb_top - 8.0 + 0.5,
			"%s tall %.0f: %s stays usable (%.1f-%.1f)" % [
				case, height, path, rect.position.y,
				rect.end.y])
	_expect_equal(lodge._name_field.text, "Wanderer",
		"%s tall %.0f: keeps the typed value" % [case, height])
	var settled: float = lodge._name_panel.position.y
	lodge._apply_keyboard_shift(height, staged)
	lodge._apply_keyboard_shift(height, staged)
	_expect_equal(lodge._name_panel.position.y, settled,
		"%s tall %.0f: the layout holds still" % [case, height])


## An all-screen keyboard cannot fit even the short card: production
## asks for one dismissal per height (never a repeat storm), a new
## height re-arms, and hiding resets the bound honestly.
func _test_name_keyboard_dismiss() -> void:
	var original_size: Vector2i = get_tree().root.size
	var original_scale: Vector2i = (
		get_tree().root.content_scale_size)
	get_tree().root.size = Vector2i(808, 360)
	get_tree().root.content_scale_size = Vector2i(808, 360)
	await _frames(2)
	_wipe()
	var fake := LodgeFakeHost.new()
	var lodge: Node = _make_lodge(fake)
	await _frames(5)
	_tap_speech(lodge)
	_tap_speech(lodge)
	_tap_speech(lodge)
	await _frames(5)
	lodge.set_process(false)
	var staged: Vector2 = get_viewport().get_visible_rect().size
	var out: Dictionary = lodge._apply_keyboard_shift(330.0, staged)
	_expect_equal(str(out.get("mode", "")), "compact",
		"dismiss: an all-screen keyboard compacts")
	_expect_false(bool(out.get("clears", true)),
		"dismiss: the short card cannot clear it")
	_expect_true(bool(out.get("dismissed", false)),
		"dismiss: production asks once")
	out = lodge._apply_keyboard_shift(330.0, staged)
	_expect_false(bool(out.get("dismissed", true)),
		"dismiss: the same height never re-asks")
	out = lodge._apply_keyboard_shift(335.0, staged)
	_expect_true(bool(out.get("dismissed", false)),
		"dismiss: a new height re-arms")
	out = lodge._apply_keyboard_shift(0.0, staged)
	_expect_equal(str(out.get("mode", "")), "restored",
		"dismiss: hiding restores")
	out = lodge._apply_keyboard_shift(330.0, staged)
	_expect_true(bool(out.get("dismissed", false)),
		"dismiss: hiding resets the bound")
	lodge.set_process(true)
	await _free_lodge(lodge, fake)
	get_tree().root.size = original_size
	get_tree().root.content_scale_size = original_scale
	await _frames(2)


## The greeting must not cover the actors: the hero's and Lumi's live
## opaque silhouettes (real frames through the real canvas transform)
## stay a small gap above every greeting/name-recovery card, at both
## wide viewports and in every locale, and fully inside the viewport.
func _test_greeting_keeps_hero_visible() -> void:
	var original_size: Vector2i = get_tree().root.size
	var original_scale: Vector2i = (
		get_tree().root.content_scale_size)
	var original_locale: String = TranslationServer.get_locale()
	for framing in [Vector2(808, 360), Vector2(880, 360)]:
		var tag: String = "%dx%d" % [
			int(framing.x), int(framing.y)]
		get_tree().root.size = Vector2i(
			int(framing.x), int(framing.y))
		get_tree().root.content_scale_size = Vector2i(
			int(framing.x), int(framing.y))
		await _frames(2)
		var view := Rect2(Vector2.ZERO,
			get_viewport().get_visible_rect().size)
		_expect_equal(view.size, framing,
			"greet: %s stages its viewport" % tag)
		for locale in LOCALES:
			TranslationServer.set_locale(locale)
			await _frames(1)
			_wipe()
			var fake := LodgeFakeHost.new()
			var lodge: Node = _make_lodge(fake)
			await _frames(5)
			# Settle the rendered transform before judging pixels:
			# a fresh lodge under physics interpolation reports a
			# lagging canvas transform until it is reset, exactly
			# what production converges to on its own.
			lodge._camera.reset_physics_interpolation()
			lodge._player.reset_physics_interpolation()
			lodge._lumi.reset_physics_interpolation()
			await _frames(1)
			await _check_greeting_card(lodge, view,
				"%s %s greet_1" % [tag, locale])
			_tap_speech(lodge)
			await _frames(2)
			await _check_greeting_card(lodge, view,
				"%s %s greet_2" % [tag, locale])
			_tap_speech(lodge)
			await _frames(2)
			await _check_greeting_card(lodge, view,
				"%s %s greet_3" % [tag, locale])
			_tap_speech(lodge)
			await _frames(3)
			lodge._show_busy(GateEntryStrings.text(
				"gate.lodge.name_checking"))
			await _frames(2)
			await _check_greeting_card(lodge, view,
				"%s %s name_checking" % [tag, locale])
			await _free_lodge(lodge, fake)
	TranslationServer.set_locale(original_locale)
	get_tree().root.size = original_size
	get_tree().root.content_scale_size = original_scale
	await _frames(2)


## The contact board's pixel audit reads what was rendered: a sane
## four-silhouette board passes, while a huge actor or a missing
## silhouette fails its slot. Boards are synthetic (headless draws
## nothing); geometry per board still runs through the real canvas
## transform of live actors under a real current camera.
func _test_contact_board_audit() -> void:
	var original_size: Vector2i = get_tree().root.size
	var original_scale: Vector2i = (
		get_tree().root.content_scale_size)
	get_tree().root.size = Vector2i(808, 360)
	get_tree().root.content_scale_size = Vector2i(808, 360)
	await _frames(2)
	var root := Node2D.new()
	add_child(root)
	var actors: Array = []
	var index: int = 0
	for facing in ["front", "rear", "left", "right"]:
		var lumi := LumiGuide.new()
		lumi.position = Vector2(
			215.0 + index * 126.0, 290.0)
		root.add_child(lumi)
		lumi.set_facing(facing)
		lumi.reset_physics_interpolation()
		actors.append(lumi)
		index += 1
	var camera := Camera2D.new()
	camera.position = Vector2(404, 265)
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	root.add_child(camera)
	camera.make_current()
	camera.reset_physics_interpolation()
	await get_tree().physics_frame
	await _frames(2)
	var bg: Color = RenderingServer.get_default_clear_color()
	var ink := Color(0.02, 0.02, 0.05) \
		if bg.get_luminance() > 0.5 else Color(0.98, 0.97, 0.94)
	var review: Node = REVIEW_SCRIPT.new()
	var sane: String = "/tmp/lodge-contact-sane-%d.png" % randi()
	_paint_board(sane, actors, bg, ink, -1)
	(review as Object).set("_failed", 0)
	(review as Object).set("_checked", 0)
	(review as Object).call(
		"_audit_contact_board", sane, actors,
		get_viewport().get_canvas_transform())
	_expect_equal(int((review as Object).get("_failed")), 0,
		"contact: four sane silhouettes pass")
	var huge: String = "/tmp/lodge-contact-huge-%d.png" % randi()
	_paint_board(huge, actors, bg, ink, 3)
	(review as Object).set("_failed", 0)
	(review as Object).set("_checked", 0)
	(review as Object).call(
		"_audit_contact_board", huge, actors,
		get_viewport().get_canvas_transform())
	_expect_true(int((review as Object).get("_failed")) > 0,
		"contact: a huge fourth actor fails its slot")
	var gone: String = "/tmp/lodge-contact-gone-%d.png" % randi()
	_paint_blank_slot(gone, actors, bg, ink, 1)
	(review as Object).set("_failed", 0)
	(review as Object).set("_checked", 0)
	(review as Object).call(
		"_audit_contact_board", gone, actors,
		get_viewport().get_canvas_transform())
	_expect_true(int((review as Object).get("_failed")) > 0,
		"contact: a missing silhouette fails its slot")
	(review as Object).free()
	for path in [sane, huge, gone]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	root.queue_free()
	await get_tree().process_frame
	get_tree().root.size = original_size
	get_tree().root.content_scale_size = original_scale
	await _frames(2)


## Paint one synthetic board: every slot gets a 21x44 body plus a
## 16x5 shadow at its actor's live screen feet, except `special`,
## which draws a 120x170 oversized actor instead (or nothing when
## `special` is -1, meaning a fully sane board).
func _paint_board(path: String, actors: Array, bg: Color,
		ink: Color, special: int) -> void:
	var image := Image.create(808, 360, false, Image.FORMAT_RGBA8)
	image.fill(bg)
	var index: int = 0
	for actor in actors:
		var xf: Transform2D = (
			actor as Node2D).get_global_transform_with_canvas()
		var feet: Vector2 = xf * Vector2.ZERO
		if index == special:
			image.fill_rect(Rect2i(int(feet.x) - 60,
				int(feet.y) - 160, 120, 170), ink)
		else:
			image.fill_rect(Rect2i(int(feet.x) - 10,
				int(feet.y) - 44, 21, 44), ink)
			image.fill_rect(Rect2i(int(feet.x) - 8,
				int(feet.y), 16, 5), ink)
		index += 1
	image.save_png(path)


## Paint one synthetic board with `blank` left empty.
func _paint_blank_slot(path: String, actors: Array, bg: Color,
		ink: Color, blank: int) -> void:
	var image := Image.create(808, 360, false, Image.FORMAT_RGBA8)
	image.fill(bg)
	var index: int = 0
	for actor in actors:
		var xf: Transform2D = (
			actor as Node2D).get_global_transform_with_canvas()
		var feet: Vector2 = xf * Vector2.ZERO
		if index != blank:
			image.fill_rect(Rect2i(int(feet.x) - 10,
				int(feet.y) - 44, 21, 44), ink)
			image.fill_rect(Rect2i(int(feet.x) - 8,
				int(feet.y), 16, 5), ink)
		index += 1
	image.save_png(path)


func _check_greeting_card(lodge: Node, view: Rect2,
		tag: String) -> void:
	var card: Rect2 = (
		lodge._speech_panel as Control).get_global_rect()
	_expect_true((lodge._speech_panel as Control).visible,
		"greet: %s shows its card" % tag)
	# Every idle frame clears: the hero animates while Lumi talks,
	# so the worst frame, not a lucky one, must clear the card.
	var animated: AnimatedSprite2D = (
		lodge._player as Node).get_node("Sprite")
	var count: int = animated.sprite_frames.get_frame_count(
		animated.animation)
	_expect_true(count > 0,
		"greet: %s animates its hero" % tag)
	for index in count:
		animated.frame = index
		var hero: Rect2 = _drawn_opaque_rect(lodge._player)
		_expect_true(hero.has_area(),
			"greet: %s draws hero frame %d" % [tag, index])
		_expect_true(view.encloses(hero),
			"greet: %s keeps hero frame %d onscreen "
			% [tag, index] + "(%s in %s)" % [
				str(hero), str(view)])
		_expect_false(card.intersects(hero.grow(4.0)),
			"greet: %s clears hero frame %d by 4px "
			% [tag, index] + "(hero %s card %s)" % [
				str(hero), str(card)])
	var lumi: Rect2 = _drawn_opaque_rect(lodge._lumi)
	_expect_true(lumi.has_area(),
		"greet: %s draws its guide" % tag)
	_expect_true(view.encloses(lumi),
		"greet: %s keeps the whole guide onscreen "
		% tag + "(%s in %s)" % [str(lumi), str(view)])
	_expect_false(card.intersects(lumi.grow(4.0)),
		"greet: %s clears the guide by 4px "
		% tag + "(lumi %s card %s)" % [
			str(lumi), str(card)])


## Live opaque silhouette of a lodge actor: the current frame's
## opaque pixels through the sprite's real canvas transform, honoring
## centering, offsets, and mirroring. Empty when nothing is opaque.
func _drawn_opaque_rect(actor: Node) -> Rect2:
	var sprite: Node2D = actor.get_node("Sprite") as Node2D
	var tex: Texture2D = null
	var centered: bool = true
	var offset := Vector2.ZERO
	var flip := Vector2.ZERO
	if sprite is AnimatedSprite2D:
		var animated := sprite as AnimatedSprite2D
		tex = animated.sprite_frames.get_frame_texture(
			animated.animation, animated.frame)
		offset = animated.offset
		flip = Vector2(
			1.0 if animated.flip_h else 0.0,
			1.0 if animated.flip_v else 0.0)
	else:
		tex = (sprite as Sprite2D).texture
		centered = (sprite as Sprite2D).centered
		offset = (sprite as Sprite2D).offset
	if tex == null:
		return Rect2()
	var image: Image = tex.get_image()
	var box := Rect2i(0, 0, 0, 0)
	var found: bool = false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a < 0.5:
				continue
			if not found:
				box = Rect2i(x, y, 1, 1)
				found = true
			else:
				box = box.expand(Vector2i(x, y))
	if not found:
		return Rect2()
	var size := Vector2(image.get_width(), image.get_height())
	if flip.x > 0.5:
		box.position.x = int(size.x) - box.end.x
	if flip.y > 0.5:
		box.position.y = int(size.y) - box.end.y
	var origin: Vector2 = -size * 0.5 if centered \
		else Vector2.ZERO
	var xf: Transform2D = sprite.get_global_transform_with_canvas()
	var scale: Vector2 = xf.get_scale()
	return Rect2(
		xf * (origin + offset + Vector2(box.position)),
		Vector2(box.size) * Vector2(
			absf(scale.x), absf(scale.y)))


# --- layout -------------------------------------------------------------------

## Opaque pixel bounds of a texture at the director's alpha probe
## threshold. Pure image math, no window needed.
func _opaque_box(texture: Texture2D) -> Rect2i:
	var image: Image = texture.get_image()
	var box := Rect2i(0, 0, 0, 0)
	var found: bool = false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a < 0.5:
				continue
			if not found:
				box = Rect2i(x, y, 1, 1)
				found = true
			else:
				box = box.expand(Vector2i(x, y))
	return box


## The guide's actual drawn body: opaque bounds through the real
## source-to-world conversion and room zoom, feet on her ground point,
## fully inside every judged viewport with the room camera centered.
## Painted boots stay planted: the opaque foot line through the real
## sprite transform moves at most half a world pixel across idle
## phases and facings. The old whole-body bob moved it four.
func _test_lumi_idle_feet_planted() -> void:
	var guide := LumiGuide.new()
	add_child(guide)
	await get_tree().process_frame
	guide.set_actor_scale(1.002475)
	var total: float = guide.total_scale()
	guide.position = Vector2(300, 200)
	var feet: Vector2 = guide.position
	for facing in ["front", "rear", "left", "right"]:
		guide.set_facing(facing)
		var sprite: Sprite2D = guide.get_node("Sprite") as Sprite2D
		var box: Rect2i = _opaque_box(sprite.texture)
		var lows: Array = []
		for quarter in [0.0, 0.25, 0.5, 0.75, 1.0]:
			guide._idle_time = LumiGuide.IDLE_PERIOD * quarter
			guide._process(0.0)
			var foot: Vector2 = guide.position \
				+ (sprite.offset + sprite.position
					+ Vector2(box.get_center().x,
						box.position.y + box.size.y)) * total
			lows.append(foot.y)
			_expect_equal(sprite.position, Vector2.ZERO,
				"planted: %s never translates its sprite" % facing)
		var spread: float = float(lows.max()) - float(lows.min())
		_expect_true(spread <= 0.5,
			"planted: %s foot line holds (%.2f peak to peak)" % [
				facing, spread])
		_expect_equal(guide.position, feet,
			"planted: %s keeps its ground anchor" % facing)
	guide.queue_free()
	await get_tree().process_frame


func _test_lumi_world_bounds() -> void:
	var hero: Hero = Vault.hero()
	var sheet: Image = (hero.idle_sheet as Texture2D).get_image()
	var cell: Vector2i = hero.sprite_cell
	var top: int = cell.y
	var bottom: int = -1
	for y in sheet.get_height():
		for x in sheet.get_width():
			if sheet.get_pixel(x, y).a < 0.5:
				continue
			top = mini(top, y % cell.y)
			bottom = maxi(bottom, y % cell.y)
	var hero_body: float = float(bottom - top + 1) * hero.visual_scale
	var ratio: float = LumiGuide.WORLD_HEIGHT / hero_body
	_expect_true(ratio > 1.4 and ratio < 1.6,
		"lumi: %.1f world px stands ~1.5x the %.1f hero body" % [
			LumiGuide.WORLD_HEIGHT, hero_body])
	var guide := LumiGuide.new()
	add_child(guide)
	await get_tree().process_frame
	_expect_true(is_equal_approx(guide.total_scale(),
		LumiGuide.WORLD_HEIGHT / LumiGuide.FRAME_HEIGHT),
		"lumi: the default scale converts source to world")
	var opaque_h: Dictionary = {}
	for facing in ["front", "rear", "left", "right"]:
		guide.set_facing(facing)
		var sprite: Sprite2D = guide.get_node("Sprite") as Sprite2D
		var box: Rect2i = _opaque_box(sprite.texture)
		opaque_h[facing] = box.size.y
		_expect_true(box.size.y > 800,
			"lumi: %s keeps its painted height" % facing)
	var heights: Array = opaque_h.values()
	_expect_true(float(heights.max()) / float(heights.min()) < 1.05,
		"lumi: opaque heights agree within 5% across facings")
	var boxes: Dictionary = {}
	for facing in ["front", "rear", "left", "right"]:
		guide.set_facing(facing)
		var sheet_sprite: Sprite2D = guide.get_node("Sprite") as Sprite2D
		boxes[facing] = _opaque_box(sheet_sprite.texture)
	for framing in FRAMINGS:
		var tag: String = "%dx%d" % [int(framing.x), int(framing.y)]
		var layout: Dictionary = GateLodge.layout_for(framing)
		var actor: float = float(layout["actor_scale"])
		guide.set_actor_scale(actor)
		var total: float = guide.total_scale()
		_expect_true(is_equal_approx(total,
			LumiGuide.WORLD_HEIGHT / LumiGuide.FRAME_HEIGHT * actor),
			"lumi: %s composes conversion with room zoom" % tag)
		_expect_equal(guide.scale, Vector2.ONE * total,
			"lumi: %s node scale is uniform" % tag)
		guide.position = layout["lumi_pos"]
		var view := Rect2(Vector2.ZERO, framing)
		for facing in ["front", "rear", "left", "right"]:
			guide.set_facing(facing)
			var sprite: Sprite2D = guide.get_node("Sprite") as Sprite2D
			var size: Vector2 = (
				sprite.texture as Texture2D).get_size()
			var feet: Vector2 = guide.position \
				+ (sprite.offset + sprite.position
					+ Vector2(size.x * 0.5, size.y)) * total
			_expect_true(feet.distance_to(guide.position) <= 0.5,
				"lumi: %s %s plants its feet on the anchor" % [
					tag, facing])
			var drawn := Rect2(
				guide.position + sprite.offset * total,
				size * total)
			_expect_true(view.encloses(drawn),
				"lumi: %s %s draws fully inside the room" % [
					tag, facing])
			var box: Rect2i = boxes[facing]
			var world_h: float = float(box.size.y) * total
			_expect_true(world_h > 38.0 * actor \
				and world_h < 44.0 * actor,
				"lumi: %s %s opaque body is %.1f world px" % [
					tag, facing, world_h])
	var shadow: Sprite2D = guide.get_node("Shadow") as Sprite2D
	var last_actor: float = float(GateLodge.layout_for(
		FRAMINGS[FRAMINGS.size() - 1])["actor_scale"])
	var shadow_world: Vector2 = Vector2(
		shadow.texture.get_size().x * shadow.scale.x,
		shadow.texture.get_size().y * shadow.scale.y) * guide.scale.x
	_expect_true(shadow_world.x > 17.0 * last_actor 		and shadow_world.x < 21.0 * last_actor,
		"lumi: the shadow spans the body (%.1f)" % shadow_world.x)
	guide.queue_free()
	await get_tree().process_frame


func _test_layout_framings() -> void:
	_expect_equal(FRAMINGS.size(), 4, "layout: four framings judged")
	for framing in FRAMINGS:
		var layout: Dictionary = GateLodge.layout_for(framing)
		var tag: String = "%dx%d" % [int(framing.x), int(framing.y)]
		var wide: bool = bool(layout["wide"])
		_expect_equal(wide, framing.x / framing.y >= 1.7,
			"layout: %s picks its plate" % tag)
		var plate: Vector2 = Vector2(1881, 836) if wide \
			else Vector2(1448, 1086)
		var room: Vector2 = plate * float(layout["room_scale"])
		_expect_true(room.x >= framing.x - 0.5 and room.y >= framing.y - 0.5,
			"layout: %s room covers, never bands" % tag)
		var walk: Rect2 = layout["walk_rect"]
		var desk: Rect2 = layout["desk_rect"]
		var gate: Rect2 = layout["gate_rect"]
		_expect_true(walk.has_point(layout["hero_pos"]),
			"layout: %s hero starts on the walk" % tag)
		_expect_true(walk.has_point(layout["lumi_pos"]),
			"layout: %s lumi stands on the walk" % tag)
		_expect_true(walk.has_point(gate.get_center()),
			"layout: %s gate trigger stays reachable" % tag)
		_expect_false(desk.has_point(layout["hero_pos"]),
			"layout: %s hero starts clear of the desk" % tag)
		_expect_false(desk.has_point(layout["lumi_pos"]),
			"layout: %s lumi stands clear of the desk" % tag)
		var view := Rect2(Vector2.ZERO, framing)
		# The desk is an obstacle: it must be present, and may touch
		# the cover-crop edge. The gate interaction stays fully shown.
		_expect_true(view.intersects(desk),
			"layout: %s desk stays onscreen" % tag)
		_expect_true(view.encloses(gate),
			"layout: %s gate stays onscreen" % tag)
		_expect_true(view.has_point(layout["lumi_pos"]),
			"layout: %s lumi stays onscreen" % tag)
	var wide_base: Dictionary = GateLodge.layout_for(Vector2(808, 360))
	var tablet_base: Dictionary = GateLodge.layout_for(Vector2(808, 606))
	# Cover math: the 2.25:1 plate stands 0.25% proud of 808x360, so
	# wide actors run a hair above 1.0 rather than banding the room.
	_expect_true(absf(float(wide_base["actor_scale"]) - 1.0) < 0.005,
		"layout: wide base runs actors at ~1.0")
	_expect_true(absf(float(tablet_base["actor_scale"]) - 1.0) < 0.005,
		"layout: tablet base keeps the same world scale")


# --- lumi ---------------------------------------------------------------------

func _test_lumi_rig() -> void:
	var lumi: Node = LumiGuide.new()
	add_child(lumi)
	await get_tree().process_frame
	var feet: Vector2 = lumi.position
	for facing in ["front", "rear", "left", "right"]:
		lumi.set_facing(facing)
		_expect_equal(lumi.facing(), facing,
			"lumi: facing reads %s" % facing)
		var sprite: Sprite2D = lumi.get_node("Sprite") as Sprite2D
		var size: Vector2 = (sprite.texture as Texture2D).get_size()
		_expect_equal(int(size.y), 869,
			"lumi: %s shares the 869px foot line" % facing)
		_expect_equal(sprite.offset, Vector2(-size.x * 0.5, -size.y),
			"lumi: %s anchors bottom-center" % facing)
		_expect_equal(lumi.position, feet,
			"lumi: %s swaps without moving her feet" % facing)
	lumi.set_facing("sideways")
	_expect_equal(lumi.facing(), "right",
		"lumi: a bogus facing keeps the last real one")
	lumi.position = Vector2(300, 200)
	lumi.face_toward(100.0)
	_expect_equal(lumi.facing(), "left", "lumi: turns to the left guest")
	lumi.face_toward(500.0)
	_expect_equal(lumi.facing(), "right", "lumi: turns to the right guest")
	lumi.face_toward(305.0)
	_expect_equal(lumi.facing(), "front", "lumi: fronts the near guest")
	var shadow: Sprite2D = lumi.get_node("Shadow") as Sprite2D
	_expect_true(shadow.texture != null, "lumi: the feet cast a shadow")
	for _index in 30:
		await get_tree().process_frame
	_expect_equal(lumi.position, Vector2(300, 200),
		"lumi: idle breath never walks her feet")
	lumi.queue_free()
	await get_tree().process_frame


# --- strings --------------------------------------------------------------------

func _test_csv_keys() -> void:
	_expect_equal(LODGE_KEYS.size(), 33, "csv: thirty-three lodge keys")
	var path: String = ProjectSettings.globalize_path(
		"res://localization/gate_entry.csv")
	var rows: PackedStringArray = FileAccess.get_file_as_string(
		path).split("\n")
	var found: Dictionary = {}
	for row in rows:
		if row.is_empty() or row.begins_with("keys,"):
			continue
		var cells: PackedStringArray = row.split(",")
		if not str(cells[0]).begins_with("gate.lodge."):
			continue
		found[cells[0]] = cells
	for key in LODGE_KEYS:
		_expect_true(found.has(key), "csv: %s ships" % key)
		if not found.has(key):
			continue
		var cells: PackedStringArray = found[key]
		_expect_equal(cells.size(), 6, "csv: %s spans five locales" % key)
		if cells.size() != 6:
			continue
		var marks: int = -1
		for index in range(1, 6):
			_expect_false(str(cells[index]).is_empty(),
				"csv: %s locale %d filled" % [key, index])
			var count: int = str(cells[index]).count("%s")
			if marks < 0:
				marks = count
			_expect_equal(count, marks,
				"csv: %s locale %d keeps its placeholders" % [key, index])


func _test_strings_resolve() -> void:
	for key in LODGE_KEYS:
		_expect_true(GateEntryStrings.text(key) != key,
			"lodge: %s resolves" % key)


# --- flow ---------------------------------------------------------------------

func _test_boot_completed_departs() -> void:
	_wipe()
	var fake := LodgeFakeHost.new()
	fake.display = "Luna"
	fake.intro = true
	var lodge: Node = _make_lodge(fake)
	await _frames(5)
	_expect_equal(lodge.lodge_state(), GateLodge.State.DEPART,
		"boot: a completed account departs at once")
	_expect_equal(lodge.lodge_account(), FAKE_ID,
		"boot: the visit binds its account")
	_expect_true(lodge._depart_panel.visible,
		"boot: the departure panel shows")
	_expect_false(lodge._depart_resume.visible,
		"boot: no save means no resume")
	_expect_false(Journey.armed, "boot: the lodge arms nothing")
	await _free_lodge(lodge, fake)


func _test_boot_cold_completed_departs() -> void:
	_wipe()
	var fake := LodgeFakeHost.new()
	fake.cache_on_load = true
	fake.load_reply = {"status": "ok", "display": "Luna", "key": "luna",
		"intro_complete": true, "source": "cloud"}
	fake.saved = {"has_save": true, "cycle": 3, "zone_index": 1,
		"hero_path": "res://resources/heroes/warden.tres"}
	var lodge: Node = _make_lodge(fake)
	await _frames(5)
	_tap_speech(lodge)
	_tap_speech(lodge)
	_tap_speech(lodge)
	await _frames(5)
	_expect_equal(lodge.lodge_state(), GateLodge.State.DEPART,
		"cold: an acked completed row departs, never practices")
	_expect_equal(lodge.lodge_display(), "Luna",
		"cold: the recovered handle drives departure")
	_expect_false(lodge._speech_panel.visible,
		"cold: no practice speech repeats")
	_expect_false(lodge._name_panel.visible,
		"cold: no second registration asks")
	_expect_true(lodge._depart_panel.visible,
		"cold: the departure choice shows")
	_expect_true(lodge._depart_resume.visible,
		"cold: the living save offers resume")
	_expect_true(str(lodge._depart_saved.text).contains("3"),
		"cold: the saved line survives recovery")
	_expect_false(Journey.armed, "cold: recovery arms nothing")
	await _free_lodge(lodge, fake)


func _test_boot_recovers_claimed_name() -> void:
	_wipe()
	var fake := LodgeFakeHost.new()
	fake.display = "Luna"
	fake.intro = false
	var lodge: Node = _make_lodge(fake)
	await _frames(5)
	_expect_true(lodge._speech_panel.visible,
		"recover: the greeting shows")
	_expect_equal(lodge._speech_body.text,
		GateEntryStrings.text("gate.lodge.named_ok") % "Luna",
		"recover: the claimed handle greets by name")
	await _free_lodge(lodge, fake)


func _test_boot_form_states() -> void:
	_wipe()
	var fake := LodgeFakeHost.new()
	var lodge: Node = _make_lodge(fake)
	await _frames(5)
	_tap_speech(lodge)
	_tap_speech(lodge)
	_tap_speech(lodge)
	await _frames(5)
	_expect_equal(lodge.lodge_state(), GateLodge.State.NAME,
		"form: an unclaimed account reaches the register")
	_expect_true(lodge._name_panel.visible, "form: the form shows")
	_expect_equal(lodge._name_field.text, "",
		"form: nothing is prefilled, ever")
	_expect_equal(lodge._name_status.text, "",
		"form: a clean load leaves no status")
	await _free_lodge(lodge, fake)
	_wipe()
	var offline := LodgeFakeHost.new()
	offline.load_reply = {"status": "failure", "code": "offline",
		"retryable": true}
	var limp: Node = _make_lodge(offline)
	await _frames(5)
	_tap_speech(limp)
	_tap_speech(limp)
	_tap_speech(limp)
	await _frames(5)
	_expect_equal(limp.lodge_state(), GateLodge.State.NAME,
		"form: a limping load still reaches the register")
	_expect_equal(limp._name_status.text,
		GateEntryStrings.text("gate.lodge.name_offline"),
		"form: the limping load names the outage")
	_expect_false(limp._name_confirm.disabled,
		"form: the outage never traps the form")
	await _free_lodge(limp, offline)


func _claim_status(lodge: Node) -> String:
	lodge._name_field.text = "Luna"
	lodge._on_name_confirm()
	await _frames(5)
	return lodge._name_status.text


func _test_claim_buckets() -> void:
	_wipe()
	var fake := LodgeFakeHost.new()
	fake.claim_queue = [
		{"status": "conflict", "code": "name-taken"},
		{"status": "failure", "code": "invalid-name"},
		{"status": "failure", "code": "timeout", "retryable": true},
		{"status": "ok", "display": "Luna", "key": "luna"},
	]
	var lodge: Node = _make_lodge(fake)
	await _frames(5)
	_tap_speech(lodge)
	_tap_speech(lodge)
	_tap_speech(lodge)
	await _frames(5)
	_expect_equal(await _claim_status(lodge),
		GateEntryStrings.text("gate.lodge.name_taken"),
		"claim: a taken name says taken")
	_expect_equal(await _claim_status(lodge),
		GateEntryStrings.text("gate.lodge.name_invalid"),
		"claim: an invalid name says invalid")
	_expect_equal(await _claim_status(lodge),
		GateEntryStrings.text("gate.lodge.name_offline"),
		"claim: a timeout reads as link trouble")
	lodge._name_field.text = "Luna"
	lodge._on_name_confirm()
	await _frames(5)
	_expect_equal(lodge.lodge_display(), "Luna",
		"claim: the win keeps its handle")
	_expect_false(lodge._name_panel.visible,
		"claim: the win closes the form")
	_expect_false(Journey.armed, "claim: the win arms nothing")
	await _free_lodge(lodge, fake)


func _wait_state(lodge: Node, state: int, frames: int) -> bool:
	for _index in frames:
		if lodge.lodge_state() == state:
			return true
		await get_tree().process_frame
	return lodge.lodge_state() == state


func _test_full_lesson_to_departure() -> void:
	_wipe()
	var fake := LodgeFakeHost.new()
	fake.display = "Luna"
	var lodge: Node = _make_lodge(fake)
	await _frames(5)
	_tap_speech(lodge)
	await _frames(3)
	_expect_equal(lodge._speech_body.text,
		GateEntryStrings.text("gate.lodge.move_lesson"),
		"lesson: the move lesson reads first")
	_tap_speech(lodge)
	_expect_true(await _wait_state(lodge, GateLodge.State.MOVE, 10),
		"lesson: practice opens the stick step")
	_expect_true(lodge._stick.mouse_filter == Control.MOUSE_FILTER_STOP,
		"lesson: the stick takes touches while practicing")
	lodge.move_override_active = true
	lodge.move_override = Vector2.RIGHT
	_expect_true(await _wait_state(lodge, GateLodge.State.LINES, 240),
		"lesson: real walking teaches the move gate")
	lodge.move_override_active = false
	_expect_true(bool(Vault.lodge_progress_for_account(FAKE_ID).get(
		"move", false)), "lesson: the move gate lands in the vault")
	_expect_true(Onboarding.is_done("move"),
		"lesson: the practiced move quiets the arena tip")
	var onboard_text: String = FileAccess.get_file_as_string(
		ProjectSettings.globalize_path("user://lodge_onboarding_test.json"))
	_expect_true(onboard_text.contains("move"),
		"lesson: the practiced move persists with no armed journey")
	_tap_speech(lodge)
	_expect_true(await _wait_state(lodge, GateLodge.State.DASH, 10),
		"lesson: the dash lesson follows")
	_expect_true(lodge._dash_button.visible,
		"lesson: the dash button joins for its lesson")
	_tap_speech(lodge)
	await _frames(3)
	lodge._dash_button.emit_signal("pressed")
	_expect_true(await _wait_state(lodge, GateLodge.State.LINES, 120),
		"lesson: a real dash teaches the dash gate")
	_expect_true(bool(Vault.lodge_progress_for_account(FAKE_ID).get(
		"dash", false)), "lesson: the dash gate lands in the vault")
	_tap_speech(lodge)
	_expect_true(await _wait_state(lodge, GateLodge.State.GATE, 10),
		"lesson: the gate walk follows")
	lodge._player.position = lodge._gate_rect.get_center()
	_expect_true(await _wait_state(lodge, GateLodge.State.DEPART, 30),
		"lesson: the gate seals into departure")
	_expect_true(fake.intro, "lesson: the seal flips the intro bit")
	_expect_true(lodge._depart_panel.visible,
		"lesson: departure shows after the seal")
	_expect_false(Journey.armed, "lesson: the lesson arms nothing")
	await _free_lodge(lodge, fake)


func _test_seal_retry_and_departure_choice() -> void:
	_wipe()
	var fake := LodgeFakeHost.new()
	fake.display = "Luna"
	fake.seal_queue = [{"status": "failure", "code": "timeout",
		"retryable": true}]
	fake.saved = {"has_save": true, "cycle": 3, "zone_index": 1,
		"hero_path": "res://resources/heroes/warden.tres"}
	var lodge: Node = _make_lodge(fake)
	var arenas: Array = []
	lodge.request_arena.connect(func(path: String) -> void: arenas.append(path))
	await _frames(5)
	_tap_speech(lodge)
	await _frames(3)
	_tap_speech(lodge)
	await _wait_state(lodge, GateLodge.State.MOVE, 10)
	lodge.move_override_active = true
	lodge.move_override = Vector2.RIGHT
	await _wait_state(lodge, GateLodge.State.LINES, 240)
	lodge.move_override_active = false
	_tap_speech(lodge)
	await _wait_state(lodge, GateLodge.State.DASH, 10)
	_tap_speech(lodge)
	await _frames(3)
	lodge._dash_button.emit_signal("pressed")
	await _wait_state(lodge, GateLodge.State.LINES, 120)
	_tap_speech(lodge)
	await _wait_state(lodge, GateLodge.State.GATE, 10)
	lodge._player.position = lodge._gate_rect.get_center()
	await _frames(10)
	_expect_equal(lodge._speech_body.text,
		GateEntryStrings.text("gate.lodge.gate_retry"),
		"seal: the miss explains itself at the gate")
	_tap_speech(lodge)
	await _wait_state(lodge, GateLodge.State.GATE, 10)
	_expect_true(lodge._gate_armed, "seal: the retry re-arms the gate")
	lodge._player.position = lodge._walk_rect.get_center()
	await _frames(3)
	lodge._player.position = lodge._gate_rect.get_center()
	_expect_true(await _wait_state(lodge, GateLodge.State.DEPART, 30),
		"seal: the retry seals on re-entry")
	_expect_true(lodge._depart_resume.visible,
		"depart: a living journey offers resume")
	_expect_true(str(lodge._depart_saved.text).contains("3"),
		"depart: the saved line names the cycle")
	lodge._on_depart_fresh()
	_expect_equal(lodge._depart_status.text,
		GateEntryStrings.text("gate.lodge.depart_fresh_confirm"),
		"depart: fresh over a save asks first")
	_expect_true(fake.exit_calls.is_empty(),
		"depart: the question plans nothing")
	lodge._on_depart_resume()
	await _frames(3)
	_expect_equal(fake.exit_calls.size(), 1,
		"depart: resume exits once")
	_expect_equal(bool(fake.exit_calls[0].get("fresh", true)), false,
		"depart: resume exits as a resume")
	_expect_equal(arenas,
		["res://scenes/gameplay/arena.tscn"],
		"depart: the exit names the arena")
	await _free_lodge(lodge, fake)


func _test_account_loss_retires() -> void:
	_wipe()
	var fake := LodgeFakeHost.new()
	fake.display = "Luna"
	var lodge: Node = _make_lodge(fake)
	var titles: Array = []
	lodge.request_title.connect(func() -> void: titles.append(true))
	await _frames(5)
	fake.public_id = "MB-lodgetest0000000000000000000002"
	fake.production_changed.emit(fake.account_state())
	await _frames(3)
	_expect_equal(lodge.lodge_state(), GateLodge.State.LOST,
		"lost: a moved account retires the visit")
	_tap_speech(lodge)
	await _frames(3)
	_expect_equal(titles.size(), 1,
		"lost: the tap walks back to the title")
	_expect_equal(fake.cancels, 1, "lost: the visit releases its plan")
	await _free_lodge(lodge, fake)


func _test_guards_and_push_out() -> void:
	_wipe()
	Vault.mark_lodge_gate(FAKE_ID, "move")
	var fake := LodgeFakeHost.new()
	fake.display = "Luna"
	var lodge: Node = _make_lodge(fake)
	await _frames(5)
	_expect_true(lodge.is_in_group("moonlit_dialogue"),
		"guard: the visit holds the dialogue line")
	var arena_cam: Camera2D = lodge._player.get_node("Cam") as Camera2D
	_expect_false(arena_cam.enabled, "guard: the arena camera sleeps")
	_expect_equal(get_viewport().get_camera_2d(), lodge._camera,
		"guard: the room camera owns the frame")
	_expect_true(lodge.find_child("Bullets", true, false) == null,
		"guard: the refuge spawns no volleys")
	_expect_true(lodge.find_child("Hud", true, false) == null,
		"guard: the refuge runs no combat counters")
	_tap_speech(lodge)
	await _frames(3)
	_expect_equal(lodge._speech_body.text,
		GateEntryStrings.text("gate.lodge.dash_lesson"),
		"guard: a sticky move gate skips its lesson")
	_tap_speech(lodge)
	await _wait_state(lodge, GateLodge.State.DASH, 10)
	_tap_speech(lodge)
	await _frames(3)
	lodge._player.position = lodge._desk_rect.get_center()
	await _frames(3)
	_expect_false(lodge._desk_rect.has_point(lodge._player.position),
		"guard: the desk slides the hero out")
	lodge._player.position = lodge._lumi.position + Vector2(2, 0)
	await _frames(3)
	_expect_true(lodge._player.position.distance_to(
		lodge._lumi.position) >= 20.0,
		"guard: lumi holds her ground")
	await _free_lodge(lodge, fake)


## The desk projection lands on walkable floor: at every judged framing
## plus the wide 880x360 that caught the suite, the desk's center, edge
## midpoints, and corners all exit outside the desk AND inside the walk
## through the real method, and real physics settling holds both. Strip
## samples keep their sliding side; anything above the walk band exits
## below the desk, never off the floor.
func _test_desk_projection_stays_on_walk() -> void:
	var original_size: Vector2i = get_tree().root.size
	var original_scale: Vector2i = (
		get_tree().root.content_scale_size)
	var framings: Array[Vector2] = FRAMINGS.duplicate()
	framings.append(Vector2(880, 360))
	for framing in framings:
		var tag: String = "%dx%d" % [
			int(framing.x), int(framing.y)]
		get_tree().root.size = Vector2i(
			int(framing.x), int(framing.y))
		get_tree().root.content_scale_size = Vector2i(
			int(framing.x), int(framing.y))
		await _frames(2)
		_wipe()
		var fake := LodgeFakeHost.new()
		var lodge: Node = _make_lodge(fake)
		await _frames(5)
		# Freeze the live loop: each sample drives the real method by
		# hand, then real physics ticks settle it without a re-push.
		lodge.set_process(false)
		var walk: Rect2 = lodge._walk_rect
		var desk: Rect2 = lodge._desk_rect
		var live: Vector2 = get_viewport().get_visible_rect().size
		_expect_equal(live, framing,
			"walk: %s stages its viewport" % tag)
		var layout: Dictionary = GateLodge.layout_for(live)
		_expect_equal(walk, layout["walk_rect"],
			"walk: %s seats its live walk" % tag)
		_expect_equal(desk, layout["desk_rect"],
			"walk: %s seats its live desk" % tag)
		var mid: Vector2 = desk.get_center()
		var strip_y: float = (
			maxf(walk.position.y, desk.position.y) + desk.end.y
			) * 0.5
		var samples: Array = [
			["center", mid, "bottom"],
			["top-mid", Vector2(mid.x, desk.position.y + 2.0),
				"bottom"],
			["left-mid", Vector2(desk.position.x + 2.0, mid.y),
				"bottom"],
			["right-mid", Vector2(desk.end.x - 2.0, mid.y),
				"bottom"],
			["bottom-mid", Vector2(mid.x, desk.end.y - 2.0),
				"bottom"],
			["left-strip",
				Vector2(desk.position.x + 2.0, strip_y), "left"],
			["right-strip",
				Vector2(desk.end.x - 2.0, strip_y), "right"],
			["corner-tl", desk.position + Vector2(2, 2),
				"bottom"],
			["corner-tr",
				Vector2(desk.end.x - 2.0, desk.position.y + 2.0),
				"bottom"],
			["corner-bl",
				Vector2(desk.position.x + 2.0, desk.end.y - 2.0),
				"left"],
			["corner-br", desk.end - Vector2(2, 2), "right"],
		]
		for sample in samples:
			await _check_desk_sample(
				lodge, walk, desk, sample[1], sample[0],
				sample[2], tag)
		# The live loop holds too: push and clamp agree every frame.
		lodge.set_process(true)
		lodge._player.position = desk.get_center()
		await _frames(3)
		_expect_false(desk.has_point(lodge._player.position),
			"walk: %s live loop leaves the desk" % tag)
		_expect_true(_on_walk(walk, lodge._player.position),
			"walk: %s live loop stays on the walk" % tag)
		await _free_lodge(lodge, fake)
	get_tree().root.size = original_size
	get_tree().root.content_scale_size = original_scale
	await _frames(2)


## One desk interior point through the real push-out: the method agrees
## with the pure projection, lands outside the desk on the walk through
## the expected side, and real physics ticks hold both constraints.
func _check_desk_sample(lodge: Node, walk: Rect2, desk: Rect2,
		point: Vector2, sample_name: String, side: String,
		tag: String) -> void:
	var label: String = "%s %s" % [tag, sample_name]
	_expect_true(desk.has_point(point),
		"walk: %s starts inside the desk" % label)
	lodge._player.set_move_input(Vector2.ZERO)
	lodge._player.velocity = Vector2.ZERO
	lodge._player.position = point
	lodge._push_out_of_desk()
	var pure: Vector2 = GateLodge.desk_exit_for(point, desk, walk)
	_expect_equal(lodge._player.position, pure,
		"walk: %s follows the pure projection" % label)
	_expect_false(desk.has_point(lodge._player.position),
		"walk: %s exits the desk" % label)
	_expect_true(_on_walk(walk, lodge._player.position),
		"walk: %s lands on the walk" % label)
	match side:
		"left":
			_expect_true(is_equal_approx(
				lodge._player.position.x,
				desk.position.x - 1.0) and is_equal_approx(
				lodge._player.position.y, point.y),
				"walk: %s slides out the left side" % label)
		"right":
			_expect_true(is_equal_approx(
				lodge._player.position.x, desk.end.x + 1.0)
				and is_equal_approx(
				lodge._player.position.y, point.y),
				"walk: %s slides out the right side" % label)
		_:
			_expect_true(is_equal_approx(
				lodge._player.position.y, desk.end.y + 1.0)
				and is_equal_approx(
				lodge._player.position.x, point.x),
				"walk: %s drops below the desk" % label)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_false(desk.has_point(lodge._player.position),
		"walk: %s settling stays out of the desk" % label)
	_expect_true(_on_walk(walk, lodge._player.position),
		"walk: %s settling stays on the walk" % label)


## Negative control for the desk projection: the pre-fix rule (nearest
## edge, float-equality ties, no walk check) strands the desk center
## off the walk at 880x360, and the real physics clamp then drags it
## back into the desk. The suite PASSES by catching the old rule in
## the act; the `negative-control` labels and print below are the
## deliberate diagnostics, never suite failures.
func _test_desk_negative_control() -> void:
	var original_size: Vector2i = get_tree().root.size
	var original_scale: Vector2i = (
		get_tree().root.content_scale_size)
	get_tree().root.size = Vector2i(880, 360)
	get_tree().root.content_scale_size = Vector2i(880, 360)
	await _frames(2)
	_wipe()
	var fake := LodgeFakeHost.new()
	var lodge: Node = _make_lodge(fake)
	await _frames(5)
	lodge.set_process(false)
	var walk: Rect2 = lodge._walk_rect
	var desk: Rect2 = lodge._desk_rect
	_expect_equal(get_viewport().get_visible_rect().size,
		Vector2(880, 360),
		"negative-control: stages its 880x360 viewport")
	lodge._player.set_move_input(Vector2.ZERO)
	lodge._player.velocity = Vector2.ZERO
	lodge._player.position = _old_desk_exit(
		desk.get_center(), desk)
	print("negative-control (deliberate, not a suite failure): ",
		"880x360 old rule exits desk center ",
		str(desk.get_center()), " to ",
		str(lodge._player.position), " (on walk: ",
		str(_on_walk(walk, lodge._player.position)), ")")
	_expect_false(_on_walk(walk, lodge._player.position),
		"negative-control: the old rule strands 880x360 off the walk")
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("negative-control (deliberate, not a suite failure): ",
		"real clamp settles to ", str(lodge._player.position),
		" (back in desk: ",
		str(desk.has_point(lodge._player.position)), ")")
	_expect_true(desk.has_point(lodge._player.position),
		"negative-control: the clamp drags the old exit back inside")
	await _free_lodge(lodge, fake)
	get_tree().root.size = original_size
	get_tree().root.content_scale_size = original_scale
	await _frames(2)


## The pre-fix projection: nearest desk edge with float-equality ties
## and no walk check. Kept only as the negative control.
func _old_desk_exit(point: Vector2, desk: Rect2) -> Vector2:
	var left: float = absf(point.x - desk.position.x)
	var right: float = absf(point.x - desk.end.x)
	var top: float = absf(point.y - desk.position.y)
	var bottom: float = absf(point.y - desk.end.y)
	var least: float = minf(minf(left, right), minf(top, bottom))
	if least == left:
		return Vector2(desk.position.x - 1.0, point.y)
	if least == right:
		return Vector2(desk.end.x + 1.0, point.y)
	if least == top:
		return Vector2(point.x, desk.position.y - 1.0)
	return Vector2(point.x, desk.end.y + 1.0)


## The projection's unreachable branch still holds its contract: with a
## desk nowhere near the walk (no real framing does this), the clamped
## fallback lands on the walk outside the desk instead of stranding.
func _test_desk_exit_fallback() -> void:
	var desk := Rect2(0, 0, 10, 10)
	var walk := Rect2(100, 100, 50, 50)
	var exit: Vector2 = GateLodge.desk_exit_for(
		Vector2(5, 5), desk, walk)
	_expect_false(desk.has_point(exit),
		"walk: the fallback clears a far desk")
	_expect_true(_on_walk(walk, exit),
		"walk: the fallback lands on a far walk")


## The walk-floor constraint both the projection and the settling must
## hold: inclusive on every side, matching the Player bounds clamp
## rather than Rect2.has_point, which drops the far edge.
func _on_walk(walk: Rect2, point: Vector2) -> bool:
	return point.x >= walk.position.x and point.x <= walk.end.x \
		and point.y >= walk.position.y and point.y <= walk.end.y


func _report() -> void:
	print("gate lodge: %d checks, %d failed" % [_checked, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
