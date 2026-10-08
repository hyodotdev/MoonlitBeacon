extends Node

## Isolated reminder QA harness (director-run, native device only).
##
## Drives the production MoonlitIdentity bridge against a disposable
## account: short test delivery, real launch action, pending
## diagnostics, and cancellation. The debug schedule never touches the
## twelve-hour production rule or any wallet: it fires one short
## non-repeating delivery and the guards stay the same (OS permission,
## channel, foreground suppression all apply, so background the app
## before the fire time to see the notification).
##
## Usage (Android test device, isolated account):
##   <game> -- res://tools/reminder_review.tscn -- mode=ui delay=60
## Headless validate (no native side, asserts honest unsupported):
##   pnpm godot:isolated res://tools/reminder_review.tscn -- mode=validate

signal _outcome_arrived(outcome: Dictionary)

const BRIDGE_PATH: String = "/root/MoonlitIdentity"

var _outcome: Dictionary = {}
var _got_outcome: bool = false


func _ready() -> void:
	var args: Dictionary = _args()
	if str(args["mode"]) == "validate":
		_validate()
		return
	if DisplayServer.get_name() == "headless":
		printerr("reminder review: ui mode needs a display; "
			+ "use mode=validate headless")
		get_tree().quit(2)
		return
	_build_ui(float(args["delay"]))


func _args() -> Dictionary:
	var args: Dictionary = {"mode": "ui", "delay": 60.0}
	for arg in OS.get_cmdline_user_args():
		var text: String = str(arg)
		if "=" in text:
			var key: String = text.get_slice("=", 0)
			if args.has(key):
				args[key] = text.get_slice("=", 1)
	return args


func _bridge() -> Node:
	return get_node_or_null(BRIDGE_PATH)


func _validate() -> void:
	var failed: int = 0
	var bridge: Node = _bridge()
	if bridge == null:
		print("reminder review: no bridge autoload (bare tree)")
		get_tree().quit(0)
		return
	for method in ["reminder_status", "reminder_request_permission",
			"reminder_schedule", "reminder_cancel",
			"reminder_open_settings", "reminder_pending_diagnostics",
			"reminder_debug_schedule"]:
		if not bridge.has_method(method):
			printerr("reminder review: bridge lacks ", method)
			failed += 1
	var status: Dictionary = bridge.call("reminder_status")
	if str(status.get("status", "")) != "unsupported":
		printerr("reminder review: headless status must be "
			+ "unsupported, got ", status)
		failed += 1
	var debug: Dictionary = bridge.call(
		"reminder_debug_schedule", 30.0)
	if str(debug.get("status", "")) != "unsupported":
		printerr("reminder review: headless debug must be "
			+ "unsupported, got ", debug)
		failed += 1
	if failed > 0:
		get_tree().quit(1)
		return
	print("reminder review: validate ok (honest unsupported)")
	get_tree().quit(0)


func _build_ui(delay: float) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-160, -140)
	box.custom_minimum_size = Vector2(320, 280)
	box.add_theme_constant_override("separation", 8)
	layer.add_child(box)
	var log := Label.new()
	log.name = "Log"
	log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log.custom_minimum_size = Vector2(320, 120)
	box.add_child(log)
	_add_button(box, "Status", _on_status.bind(log))
	_add_button(box, "Request permission",
		_on_permission.bind(log))
	_add_button(box, "Schedule test (%ds)" % int(delay),
		_on_debug.bind(log, delay))
	_add_button(box, "Pending diagnostics",
		_on_pending.bind(log))
	_add_button(box, "Cancel all", _on_cancel.bind(log))
	_log(log, "reminder QA ready; use an isolated test account")


func _add_button(box: VBoxContainer, text: String,
		handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 28)
	button.pressed.connect(handler)
	box.add_child(button)


func _log(log: Label, text: String) -> void:
	log.text = text
	print("reminder review: ", text)


func _on_status(log: Label) -> void:
	var bridge: Node = _bridge()
	if bridge == null:
		_log(log, "no bridge")
		return
	_log(log, JSON.stringify(bridge.call("reminder_status")))


func _on_permission(log: Label) -> void:
	var bridge: Node = _bridge()
	if bridge == null:
		_log(log, "no bridge")
		return
	_log(log, "requesting; answer the OS sheet")
	var receipt: Dictionary = bridge.call(
		"reminder_request_permission")
	if str(receipt.get("status", "")) != "pending":
		_log(log, JSON.stringify(receipt))
		return
	var outcome: Dictionary = await _await_outcome(bridge,
		str(receipt.get("request_id", "")))
	_log(log, JSON.stringify(outcome))


func _on_debug(log: Label, delay: float) -> void:
	var bridge: Node = _bridge()
	if bridge == null:
		_log(log, "no bridge")
		return
	var receipt: Dictionary = bridge.call(
		"reminder_debug_schedule", delay)
	_log(log, JSON.stringify(receipt)
		+ " — background the app to see it")


func _on_pending(log: Label) -> void:
	var bridge: Node = _bridge()
	if bridge == null:
		_log(log, "no bridge")
		return
	var receipt: Dictionary = bridge.call(
		"reminder_pending_diagnostics")
	if str(receipt.get("status", "")) != "pending":
		_log(log, JSON.stringify(receipt))
		return
	var outcome: Dictionary = await _await_outcome(bridge,
		str(receipt.get("request_id", "")))
	_log(log, JSON.stringify(outcome))


func _on_cancel(log: Label) -> void:
	var bridge: Node = _bridge()
	if bridge == null:
		_log(log, "no bridge")
		return
	_log(log, JSON.stringify(bridge.call("reminder_cancel")))


func _await_outcome(bridge: Node,
		request_id: String) -> Dictionary:
	_got_outcome = false
	_outcome = {}
	var handler: Callable = func(outcome: Dictionary) -> void:
		if str(outcome.get("request_id", "")) == request_id:
			_outcome = outcome
			_got_outcome = true
	bridge.connect("request_completed", handler)
	var waited: float = 0.0
	while not _got_outcome and waited < 65.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if bridge.is_connected("request_completed", handler):
		bridge.disconnect("request_completed", handler)
	if not _got_outcome:
		return {"status": "error", "code": "qa_timeout",
			"request_id": request_id}
	return _outcome
