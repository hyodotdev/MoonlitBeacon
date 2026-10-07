extends Node

## Gate lodge QA harness: validate headless, render windowed.
##
## The director renders on a real display; this sandbox cannot. Modes:
## - validate (headless): layout math plus panel seating, safe-area, and
##   clipping audits for every framing x locale x dialogue state. This
##   mode runs here and exits nonzero on any violation.
## - room (windowed): one PNG of the lodge in a framing/locale/state.
## - contact (windowed): one PNG with the four Lumi facings side by side,
##   plus a pixel audit of the four captured silhouettes.
## - clip (windowed): scripted real-time lesson (walk, dash, neutral
##   stop, gate seal), up to 600 sim frames with at most 120 saved PNGs.
##   Prints the observed phases and exits nonzero unless all complete.
##
## Run: `pnpm godot:isolated [--windowed] res://tools/lodge_review.tscn --
##   mode=room framing=808x360 locale=en state=depart out=builds/lodge-qa`
## Windowed modes need `--resolution WxH` matching the framing. All modes
## use isolated user files, so the human record stays untouched.
##
## The fake host and scripted inputs below are harness-only: normal
## production never sees a test nickname, fake rows, or driven movement.

const LODGE_SCENE: PackedScene = preload(
	"res://scenes/gameplay/gate_lodge.tscn")
const FRAMINGS: Dictionary = {
	"808x360": Vector2(808, 360),
	"840x360": Vector2(840, 360),
	"808x606": Vector2(808, 606),
}
const LOCALES: Array[String] = ["ko", "en", "ja", "zh_CN", "zh_TW"]
const STATES: Array[String] = ["greet", "name", "move", "gate", "depart"]
## Real-time lesson budget with a bounded saved selection: at most 120
## output frames no matter how long the lesson runs.
const CLIP_SIM_FRAMES: int = 600
const CLIP_EVERY: int = 5
const CLIP_OUTPUT_BUDGET: int = 120
const FAKE_ID: String = "MB-lodgereview00000000000000000001"

var _failed: int = 0
var _checked: int = 0


class ReviewHost extends Node:
	signal production_changed(state: Dictionary)

	var display: String = "Luna"
	var intro: bool = false
	var claim_ok: bool = true
	var seal_ok: bool = true
	var saved: Dictionary = {"has_save": false}

	func account_state() -> Dictionary:
		return {"public_id": FAKE_ID,
			"deletion_in_flight": false}

	func needs_lodge_lesson() -> bool:
		return display.is_empty() or not intro

	func verified_display_name() -> String:
		return display

	func load_adventurer_name() -> Dictionary:
		await get_tree().process_frame
		if display.is_empty():
			return {"status": "failure", "code": "adventurer-not-found",
				"retryable": false}
		return {"status": "ok", "display": display, "key": "luna",
			"intro_complete": intro, "source": "cloud"}

	func claim_adventurer_name(text: String) -> Dictionary:
		await get_tree().process_frame
		if not claim_ok:
			return {"status": "failure", "code": "offline",
				"retryable": true}
		display = text
		return {"status": "ok", "display": text, "key": "key"}

	func mark_intro_complete() -> Dictionary:
		await get_tree().process_frame
		if not seal_ok:
			return {"status": "failure", "code": "timeout",
				"retryable": true}
		intro = true
		return {"status": "ok"}

	func saved_gate_summary() -> Dictionary:
		return saved.duplicate(true)

	func plan_lodge_exit(fresh: bool, _confirmed: bool) -> Dictionary:
		return {"status": "ok",
			"arena": "res://scenes/gameplay/arena.tscn",
			"fresh": fresh, "account_id": FAKE_ID}

	func confirm_entry_account(account_id: String) -> bool:
		return account_id == FAKE_ID

	func cancel_entry_plan() -> void:
		pass


func _ready() -> void:
	GateEntryStrings.ensure_loaded()
	_run.call_deferred()


func _args() -> Dictionary:
	var out: Dictionary = {"mode": "validate", "framing": "808x360",
		"locale": "en", "state": "depart", "out": "builds/lodge-qa",
		"kb": "0"}
	for arg in OS.get_cmdline_user_args():
		var pair: PackedStringArray = str(arg).split("=", true, 1)
		if pair.size() == 2 and out.has(pair[0]):
			out[pair[0]] = pair[1]
	return out


func _run() -> void:
	var args: Dictionary = _args()
	match str(args["mode"]):
		"validate":
			await _run_validate()
		"room":
			await _run_room(args)
		"contact":
			await _run_contact(args)
		"clip":
			await _run_clip(args)
		_:
			printerr("lodge review: unknown mode ", args["mode"])
			get_tree().quit(2)


# --- validate (headless) ------------------------------------------------------

## Every framing x locale x state: panels seat inside the safe area, the
## keyboard-clear form stays high, and no label clips its text.
func _run_validate() -> void:
	for framing in FRAMINGS:
		_audit_framing(str(framing), FRAMINGS[framing])
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		for state in STATES:
			await _audit_state(locale, state)
	print("lodge review: %d checks, %d failed" % [_checked, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _audit_framing(tag: String, size: Vector2) -> void:
	var layout: Dictionary = GateLodge.layout_for(size)
	var view := Rect2(Vector2.ZERO, size)
	_check(view.encloses(layout["gate_rect"] as Rect2),
		"%s: the gate stays reachable" % tag)
	_check(view.has_point(layout["lumi_pos"]),
		"%s: lumi stays onscreen" % tag)
	_check(view.has_point(layout["hero_pos"]),
		"%s: the hero starts onscreen" % tag)
	var walk: Rect2 = layout["walk_rect"]
	_check(walk.has_point(layout["hero_pos"])
		and walk.has_point(layout["lumi_pos"])
		and walk.has_point((layout["gate_rect"] as Rect2).get_center()),
		"%s: hero, lumi, and gate share the walk" % tag)


func _audit_state(locale: String, state: String) -> void:
	var tag: String = "%s/%s" % [locale, state]
	Vault.load_vault()
	Vault.clear_lodge_for_owner(FAKE_ID)
	var fake := ReviewHost.new()
	fake.display = "" if state == "greet" or state == "name" else "Luna"
	fake.saved = {"has_save": true, "cycle": 12, "zone_index": 7,
		"hero_path": "res://resources/heroes/keeper.tres"}
	if state == "gate":
		Vault.mark_lodge_gate(FAKE_ID, "move")
		Vault.mark_lodge_gate(FAKE_ID, "dash")
	add_child(fake)
	var lodge: Node = LODGE_SCENE.instantiate()
	lodge.host_override = fake
	lodge.embedded = true
	add_child(lodge)
	await _drive_to(lodge, fake, state)
	await get_tree().process_frame
	await get_tree().process_frame
	_audit_panels(lodge, tag)
	_audit_guide(lodge, tag)
	if state == "name" and lodge.lodge_state() == GateLodge.State.NAME:
		for key in ["gate.lodge.name_taken", "gate.lodge.name_invalid",
			"gate.lodge.name_offline", "gate.lodge.name_checking"]:
			lodge._name_status.text = GateEntryStrings.text(key)
			await get_tree().process_frame
			await get_tree().process_frame
			_audit_panels(lodge, "%s/%s" % [tag, key.get_slice(".", 2)])
	lodge.queue_free()
	fake.queue_free()
	await get_tree().process_frame


## Walk the real flow to a state: taps are the same calls a finger makes.
func _drive_to(lodge: Node, fake: ReviewHost, state: String) -> void:
	for _index in 8:
		await get_tree().process_frame
	if state == "greet":
		return
	for _tap in 3:
		lodge._advance_speech()
		await get_tree().process_frame
	for _index in 6:
		await get_tree().process_frame
	if state == "name":
		return
	if lodge.lodge_state() == GateLodge.State.NAME:
		lodge._name_field.text = "Luna"
		lodge._on_name_confirm()
		for _index in 6:
			await get_tree().process_frame
	lodge._advance_speech()
	await get_tree().process_frame
	if state == "move":
		lodge._advance_speech()
		await get_tree().process_frame
		return
	for _index in 4:
		await get_tree().process_frame
	if state == "gate":
		lodge._advance_speech()
		for _index in 4:
			await get_tree().process_frame
		return
	if state == "depart":
		fake.intro = true
		lodge._enter_departure()
		for _index in 4:
			await get_tree().process_frame


## Shortest-viewport height budgets: the name form seats at y 58 on a
## 360-tall screen, speech floats low, departure centers. Real laid-out
## heights must fit the 808x360 framing every locale reaches.
const HEIGHT_BUDGETS: Dictionary = {
	"Ui/Speech": 240.0,
	"Ui/NameForm": 296.0,
	"Ui/Departure": 320.0,
}


func _audit_panels(lodge: Node, tag: String) -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var full := Rect2(Vector2.ZERO, view)
	var safe: Rect2 = Screen.viewport_safe_rect(get_viewport())
	if not safe.has_area():
		safe = full
	for path in ["Ui/TopBar", "Ui/Speech", "Ui/NameForm", "Ui/Departure"]:
		var panel: Control = lodge.get_node_or_null(path) as Control
		if panel == null or not panel.visible:
			continue
		var inside: bool = safe.encloses(panel.get_global_rect())
		if not inside:
			print("RECT ", tag, " ", path, " panel=",
				panel.get_global_rect(), " safe=", safe,
				" view=", full, " min=",
				panel.get_combined_minimum_size())
			for kid in panel.find_children("*", "Control", true, false):
				var c: Control = kid as Control
				print("   kid ", c.name, " ", c.get_class(),
					" min=", c.get_combined_minimum_size(),
					" rect=", c.get_rect(),
					" text=", str(c.get("text")).left(40))
		_check(inside, "%s: %s sits inside the safe area" % [tag, path])
		if HEIGHT_BUDGETS.has(path):
			_check(panel.size.y <= float(HEIGHT_BUDGETS[path]),
				"%s: %s fits the 360-tall budget (%.0f)" % [
					tag, path, panel.size.y])
		for label in panel.find_children("*", "Label", true, false):
			_audit_label(label, tag, path)


## The guide draws through the source-to-world conversion times the
## room zoom: catch a raw unscaled sprite even without rendering.
func _audit_guide(lodge: Node, tag: String) -> void:
	var want: float = LumiGuide.WORLD_HEIGHT / LumiGuide.FRAME_HEIGHT \
		* lodge._actor_scale
	var got: Vector2 = lodge._lumi.scale
	_check(is_equal_approx(got.x, want) and is_equal_approx(got.y, want),
		"%s: lumi converts source px to world (%.4f)" % [tag, got.x])
	var sprite: Sprite2D = lodge._lumi.get_node("Sprite") as Sprite2D
	var size: Vector2 = (sprite.texture as Texture2D).get_size()
	_check(is_equal_approx(size.y * got.y,
		LumiGuide.WORLD_HEIGHT * lodge._actor_scale),
		"%s: lumi stands %.0f world px tall" % [tag, size.y * got.y])


func _audit_label(label: Label, tag: String, path: String) -> void:
	if str(label.text).is_empty():
		return
	_check(label.size.x > 0.0 and label.size.y > 0.0,
		"%s: %s lays its label out" % [tag, path])
	if label.clip_text and label.max_lines_visible > 0:
		_check(label.get_line_count() <= label.max_lines_visible,
			"%s: %s keeps every line" % [tag, path])


func _check(value: bool, label: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("FAIL lodge review: ", label)


# --- windowed capture (director) -----------------------------------------------

func _swap_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)
	await get_tree().process_frame


func _capture(viewport: Viewport, path: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var file: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	if image.save_png(file) != OK:
		printerr("lodge review: could not write ", file)
		get_tree().quit(2)


func _run_room(args: Dictionary) -> void:
	await _swap_locale(str(args["locale"]))
	Vault.load_vault()
	var fake := ReviewHost.new()
	fake.display = "" if str(args["state"]) in ["greet", "name"] else "Luna"
	add_child(fake)
	var lodge: Node = LODGE_SCENE.instantiate()
	lodge.host_override = fake
	lodge.embedded = true
	add_child(lodge)
	await _drive_to(lodge, fake, str(args["state"]))
	await get_tree().process_frame
	await get_tree().process_frame
	# A synthetic keyboard stages the adapted form for inspection
	# through the same production hook the tests drive: device
	# pixels in, live window and transform converting. This is a
	# staged occlusion, never a native keyboard delivery. The live
	# hook freezes first, or its zero-height frames would restore.
	var kb: float = maxf(float(str(args["kb"])), 0.0)
	var suffix: String = ""
	if kb > 0.0:
		lodge.set_process(false)
		var outcome: Dictionary = lodge._apply_keyboard_shift(kb)
		await get_tree().process_frame
		await get_tree().process_frame
		print("lodge review: synthetic keyboard ",
			JSON.stringify(outcome))
		suffix = "-kb%d" % int(kb)
	await _capture(get_viewport(), "%s/room-%s-%s-%s%s.png" % [
		str(args["out"]), str(args["framing"]), str(args["locale"]),
		str(args["state"]), suffix])
	if lodge.has_method("name_form_keyboard_report"):
		print("lodge review: keyboard ",
			JSON.stringify(lodge.call(
				"name_form_keyboard_report")))
	print("lodge review: room captured")
	get_tree().quit(0)


func _run_contact(args: Dictionary) -> void:
	var root := Node2D.new()
	add_child(root)
	var actors: Array = []
	var index: int = 0
	for facing in ["front", "rear", "left", "right"]:
		var lumi := LumiGuide.new()
		lumi.position = Vector2(215.0 + index * 126.0, 290.0)
		root.add_child(lumi)
		lumi.set_facing(facing)
		lumi.reset_physics_interpolation()
		actors.append(lumi)
		index += 1
	var camera := Camera2D.new()
	camera.position = Vector2(404, 265)
	# Physics callback before tree entry: the project interpolates
	# physics, and the idle default warns on every capture.
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	# Seat first, then make current: the reverse order errors, and
	# the capture must render the settled interpolation, not the
	# first tick's lagging transform that once drew the last actor
	# huge and half outside the board.
	root.add_child(camera)
	camera.make_current()
	camera.reset_physics_interpolation()
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var path: String = "%s/contact-lumi.png" % str(args["out"])
	await _capture(get_viewport(), path)
	_audit_contact_board(path, actors,
		get_viewport().get_canvas_transform())
	print("lodge review: contact captured")
	get_tree().quit(1 if _failed > 0 else 0)


## Judge the captured board's pixels, not the pre-draw transforms:
## each of the four slots must show one sanely-sized silhouette near
## its actor's feet. The board background is the opaque clear color,
## so silhouettes read as pixels far from the corner color.
func _audit_contact_board(path: String, actors: Array,
		canvas: Transform2D) -> void:
	var file: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path):
		_check(false, "contact: the board was written")
		return
	var image: Image = Image.load_from_file(file) as Image
	if image == null or image.is_empty():
		_check(false, "contact: the board holds pixels")
		return
	var corners: Array = [
		image.get_pixel(4, 4),
		image.get_pixel(image.get_width() - 5, 4),
		image.get_pixel(4, image.get_height() - 5),
		image.get_pixel(
			image.get_width() - 5, image.get_height() - 5),
	]
	# The background is whatever most corners agree on, so one stray
	# oversized actor cannot elect itself the background.
	corners.sort_custom(func(a: Color, b: Color) -> bool:
		return a.to_html() < b.to_html())
	var bg: Color = corners[1]
	var names: Array = ["front", "rear", "left", "right"]
	var index: int = 0
	for actor in actors:
		var feet: Vector2 = (
			actor as Node2D).get_global_transform_with_canvas() \
			* Vector2.ZERO
		# The canvas unit is the camera/viewport scale, never the
		# actor's own node scale (a Lumi stands 0.048 of her own
		# source pixels tall; that is not the board's ruler).
		var unit: float = absf(canvas.get_scale().y)
		if unit <= 0.001:
			unit = 1.0
		var slot := Rect2(
			feet + Vector2(-63, -64) * unit,
			Vector2(126, 76) * unit)
		var clip: Rect2 = slot.intersection(Rect2(
			Vector2.ZERO, image.get_size()))
		var found := Rect2(Vector2.ZERO, Vector2.ZERO)
		var drew: bool = false
		for y in range(int(clip.position.y), int(clip.end.y)):
			for x in range(int(clip.position.x), int(clip.end.x)):
				var c: Color = image.get_pixel(x, y)
				var drift: float = (c.r - bg.r) * (c.r - bg.r) \
					+ (c.g - bg.g) * (c.g - bg.g) \
					+ (c.b - bg.b) * (c.b - bg.b)
				if drift < 0.02:
					continue
				var at := Rect2(Vector2(x, y), Vector2.ONE)
				found = at if not drew else found.merge(at)
				drew = true
		var tag: String = "contact: %s" % str(names[index])
		_check(drew, "%s draws a silhouette" % tag)
		if not drew:
			index += 1
			continue
		var tall: float = found.size.y / unit
		var wide: float = found.size.x / unit
		var low: float = (found.end.y - feet.y) / unit
		print("contact: %s at %s size %s (%.1f x %.1f world)" % [
			str(names[index]), str(found.position),
			str(found.size), wide, tall])
		_check(tall >= 30.0 and tall <= 60.0,
			"%s stands a sane height (%.1f)" % [tag, tall])
		_check(wide >= 6.0 and wide <= 60.0,
			"%s spans a sane width (%.1f)" % [tag, wide])
		_check(low >= -4.0 and low <= 12.0,
			"%s plants its feet near the anchor (%.1f)" % [
				tag, low])
		index += 1


func _run_clip(args: Dictionary) -> void:
	await _swap_locale(str(args["locale"]))
	Vault.load_vault()
	Vault.clear_lodge_for_owner(FAKE_ID)
	var fake := ReviewHost.new()
	add_child(fake)
	var lodge: Node = LODGE_SCENE.instantiate()
	lodge.host_override = fake
	lodge.embedded = true
	add_child(lodge)
	var phases: Dictionary = {"moved": 0.0, "dashed": false,
		"stopped": false, "depart": false, "dash_sent": false,
		"stop_frames": 0, "depart_frames": 0,
		"last_pos": Vector2.ZERO, "begun": false}
	var saved_pngs: int = 0
	var frame: int = 0
	var done: bool = false
	while frame < CLIP_SIM_FRAMES and not done:
		await get_tree().process_frame
		done = _clip_drive(lodge, frame, phases)
		if frame % CLIP_EVERY == 0 \
			and saved_pngs < CLIP_OUTPUT_BUDGET:
			await _capture(get_viewport(), "%s/clip-%03d.png" % [
				str(args["out"]), saved_pngs])
			saved_pngs += 1
		frame += 1
	phases["depart"] = lodge.lodge_state() == GateLodge.State.DEPART
	print("lodge review: clip moved=%.1f dashed=%s stopped=%s " % [
		float(phases["moved"]), str(phases["dashed"]),
		str(phases["stopped"])] + "depart=%s sim=%d saved=%d" % [
		str(phases["depart"]), frame, saved_pngs])
	var complete: bool = float(phases["moved"]) >= 60.0 \
		and bool(phases["dashed"]) and bool(phases["stopped"]) \
		and bool(phases["depart"])
	get_tree().quit(0 if complete else 1)


## Script the real lesson: tap words through, walk right, dash, stop
## neutral, then steer to the gate until the seal lands. Returns true a
## few frames after departure so the choice is on film.
func _clip_drive(lodge: Node, frame: int, phases: Dictionary) -> bool:
	if lodge._speech_panel.visible and not lodge._speech_locked:
		lodge._advance_speech()
	var player: Node = lodge._player
	if not bool(phases["begun"]):
		phases["begun"] = frame >= 6
		phases["last_pos"] = player.position
		if frame == 6:
			lodge.move_override_active = true
			lodge.move_override = Vector2.RIGHT
		return false
	phases["moved"] = float(phases["moved"]) \
		+ player.position.distance_to(phases["last_pos"])
	phases["last_pos"] = player.position
	if player.is_dashing():
		phases["dashed"] = true
	var state: int = lodge.lodge_state()
	if state == GateLodge.State.DASH \
		and lodge._speech_locked and not bool(phases["dash_sent"]):
		phases["dash_sent"] = true
		lodge._dash_button.emit_signal("pressed")
	elif state == GateLodge.State.GATE and not bool(phases["stopped"]):
		lodge.move_override = Vector2.ZERO
		if player.velocity.length() < 8.0 and not player.is_dashing():
			phases["stop_frames"] = int(phases["stop_frames"]) + 1
			if int(phases["stop_frames"]) >= 10:
				phases["stopped"] = true
	elif state == GateLodge.State.GATE:
		var gate: Rect2 = lodge._gate_rect
		var to_gate: Vector2 = gate.get_center() - player.position
		if to_gate.length() > 1.0:
			lodge.move_override = to_gate.normalized()
	elif state == GateLodge.State.DEPART:
		lodge.move_override_active = false
		phases["depart_frames"] = int(phases["depart_frames"]) + 1
		return int(phases["depart_frames"]) >= 6
	return false
