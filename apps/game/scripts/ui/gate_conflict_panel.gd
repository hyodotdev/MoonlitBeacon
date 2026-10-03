class_name GateConflictPanel
extends GatePanelBase

## An explicit local/cloud save fork, decided by the player.
##
## Both saves are shown with the host's own summaries; neither side is
## pre-picked and nothing resolves on a timer. The safe default owns the
## focus: "decide later" and the back button both take the `cancelled`
## branch, so a stray tap can never throw a save away.

signal resolved(which: StringName)
signal cancelled

var _local_title: Label
var _local_detail: Label
var _cloud_title: Label
var _cloud_detail: Label
var _keep_local: Button
var _keep_cloud: Button
var _decide_later: Button


func _ready() -> void:
	_build_base("gate.conflict.title", Vector2(CARD_MIN_WIDTH + 80.0, 0.0))
	_stack.add_theme_constant_override(&"separation", 6)
	var body := GateEntryStyle.make_label(
		"gate.conflict.body", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.TEXT_DIM)
	body.name = &"Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = _content_width()
	_stack.add_child(body)
	_local_title = _option_block("gate.conflict.local_tag", &"LocalTag")
	_local_detail = _option_detail(&"LocalDetail")
	_cloud_title = _option_block("gate.conflict.cloud_tag", &"CloudTag")
	_cloud_detail = _option_detail(&"CloudDetail")
	# All three choices share one row so the card fits 360px-tall
	# viewports; the safe default still owns the focus.
	var row := HBoxContainer.new()
	row.name = &"Choices"
	row.add_theme_constant_override(&"separation", 8)
	_stack.add_child(row)
	_keep_local = GateEntryStyle.make_button("gate.conflict.local")
	_keep_local.name = &"KeepLocal"
	_keep_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keep_local.pressed.connect(_on_keep_local)
	row.add_child(_keep_local)
	_keep_cloud = GateEntryStyle.make_button("gate.conflict.cloud")
	_keep_cloud.name = &"KeepCloud"
	_keep_cloud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keep_cloud.pressed.connect(_on_keep_cloud)
	row.add_child(_keep_cloud)
	_decide_later = GateEntryStyle.make_button("gate.conflict.cancel")
	_decide_later.name = &"DecideLater"
	_decide_later.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_decide_later.pressed.connect(_on_cancel)
	row.add_child(_decide_later)
	visible = false


## Show both saves. `local` and `cloud` hold host `title`/`detail` lines;
## empty strings keep their row but show nothing invented.
func show_conflict(local: Dictionary, cloud: Dictionary) -> void:
	_local_title.text = str(local.get("title", ""))
	_local_detail.text = _detail_text(local)
	_local_detail.visible = not _local_detail.text.is_empty()
	_cloud_title.text = str(cloud.get("title", ""))
	_cloud_detail.text = _detail_text(cloud)
	_cloud_detail.visible = not _cloud_detail.text.is_empty()
	open()


func _default_focus() -> Control:
	return _decide_later


func _on_background_cancel() -> void:
	_on_cancel()


func _on_keep_local() -> void:
	visible = false
	resolved.emit(&"local")


func _on_keep_cloud() -> void:
	visible = false
	resolved.emit(&"cloud")


func _on_cancel() -> void:
	visible = false
	cancelled.emit()


func _option_block(tag_key: String, tag_name: StringName) -> Label:
	var tag := GateEntryStyle.make_label(
		tag_key, GateEntryStyle.FONT_SMALL, GateEntryStyle.ACCENT_TEAL, true)
	tag.name = tag_name
	_stack.add_child(tag)
	var title := GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_BODY, GateEntryStyle.TEXT_MAIN)
	title.name = StringName(str(tag_name) + "Title")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = _content_width()
	title.max_lines_visible = 2
	title.clip_text = true
	_stack.add_child(title)
	return title


func _option_detail(detail_name: StringName) -> Label:
	var detail := GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_SMALL, GateEntryStyle.TEXT_FAINT)
	detail.name = detail_name
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = _content_width()
	detail.max_lines_visible = 2
	detail.clip_text = true
	_stack.add_child(detail)
	return detail


func _detail_text(option: Dictionary) -> String:
	var parts: Array[String] = []
	var detail: String = str(option.get("detail", ""))
	var updated: String = str(option.get("updated", ""))
	if not detail.is_empty():
		parts.append(detail)
	if not updated.is_empty():
		parts.append(updated)
	return "\n".join(parts)
