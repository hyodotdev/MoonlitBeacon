class_name GateAccountPanel
extends GatePanelBase

## Who is signed in, on one card.
##
## The host supplies everything shown: stable ID, hero portrait and name,
## provider label, saved-gate summary. Nothing here invents an identity. The
## full ID stays readable in a scrollable field with a copy affordance, and
## the anonymous-metrics toggle is the host's opt-in, always defaulting off.
##
## Privacy and support buttons appear only when the project settings hold
## valid links, and they emit `external_link_requested` instead of opening
## a browser themselves: the host owns OS calls, this panel stays testable.
##
## The host may also enable provider link buttons, sign-out, and a two-tap
## delete. All stay hidden unless the host data asks for them.
##
## The title row and the Close footer stay pinned; everything between
## them scrolls inside a bounded ScrollContainer, so the production
## local-guest shape (link doors plus sign-out and delete) fits the
## 360px landscape height with its header and footer always on screen.
## Google and Apple link doors are the entry's own official factory
## faces; extra providers keep the game's own buttons.

signal analytics_opt_in_changed(enabled: bool)
signal external_link_requested(url: String)
signal id_copied(stable_id: String)
signal link_requested(provider_id: String)
signal sign_out_requested
signal delete_requested

const ExternalLinks := preload("res://scripts/ui/external_links.gd")
const PORTRAIT_SIZE: float = 40.0
const DETAIL_MAX_LINES: int = 2
## Scroll floor: about two rows stay readable even if a future framing
## starves the middle. The 360px base height budgets far more.
const SCROLL_MIN_HEIGHT: float = 96.0

var _stable_id: String = ""
var _status_label: Label
var _id_field: LineEdit
var _secret_button: Button
var _copied_note: Label
var _portrait: TextureRect
var _hero_label: Label
var _saved_title: Label
var _saved_detail: Label
var _analytics_button: Button
var _privacy_button: Button
var _support_button: Button
var _links_row: HBoxContainer
var _close_button: Button
var _link_title: Label
var _link_row: VBoxContainer
var _scroll: ScrollContainer
var _scroll_box: VBoxContainer
var _actions_row: HBoxContainer
var _sign_out_button: Button
var _delete_button: Button
var _delete_row: HBoxContainer


func _ready() -> void:
	_build_base("gate.account.title", Vector2(CARD_MIN_WIDTH + 40.0, 0.0))
	_stack.add_theme_constant_override(&"separation", 6)
	# Title and sign-in status share one row so the card fits 360px-tall
	# viewports in every locale.
	var title_row := HBoxContainer.new()
	title_row.name = &"TitleRow"
	title_row.add_theme_constant_override(&"separation", 8)
	_stack.remove_child(_title_label)
	_stack.add_child(title_row)
	_stack.move_child(title_row, 0)
	title_row.add_child(_title_label)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label = GateEntryStyle.make_label(
		"gate.account.signed_out", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.TEXT_DIM)
	_status_label.name = &"Status"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(_status_label)
	_id_field = LineEdit.new()
	_id_field.name = &"StableId"
	GateEntryStyle.apply_id_field(_id_field)
	_stack.add_child(_id_field)
	var id_row := HBoxContainer.new()
	id_row.name = &"IdRow"
	id_row.alignment = BoxContainer.ALIGNMENT_END
	id_row.add_theme_constant_override(&"separation", 8)
	_stack.add_child(id_row)
	_copied_note = GateEntryStyle.make_label(
		"gate.auth.copied", GateEntryStyle.FONT_SMALL, GateEntryStyle.MINT)
	_copied_note.name = &"CopiedNote"
	_copied_note.visible = false
	id_row.add_child(_copied_note)
	_secret_button = GateEntryStyle.make_button("gate.auth.hide_id")
	_secret_button.name = &"RevealToggle"
	_secret_button.custom_minimum_size = Vector2(64.0, 36.0)
	_secret_button.pressed.connect(_on_reveal_toggle)
	id_row.add_child(_secret_button)
	var copy_button := GateEntryStyle.make_button("gate.auth.copy")
	copy_button.name = &"CopyId"
	copy_button.custom_minimum_size = Vector2(64.0, 36.0)
	copy_button.pressed.connect(_on_copy_id)
	id_row.add_child(copy_button)
	var hero_row := HBoxContainer.new()
	hero_row.name = &"HeroRow"
	hero_row.add_theme_constant_override(&"separation", 10)
	_stack.add_child(hero_row)
	_portrait = TextureRect.new()
	_portrait.name = &"Portrait"
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_row.add_child(_portrait)
	_hero_label = GateEntryStyle.make_label(
		"gate.auth.no_hero", GateEntryStyle.FONT_BODY,
		GateEntryStyle.TEXT_MAIN)
	_hero_label.name = &"HeroName"
	_hero_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hero_row.add_child(_hero_label)
	_saved_title = GateEntryStyle.make_label(
		"gate.auth.no_save", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.TEXT_DIM)
	_saved_title.name = &"SavedTitle"
	_saved_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_saved_title.custom_minimum_size.x = _content_width()
	_stack.add_child(_saved_title)
	_saved_detail = GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_SMALL, GateEntryStyle.TEXT_FAINT)
	_saved_detail.name = &"SavedDetail"
	_saved_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_saved_detail.custom_minimum_size.x = _content_width()
	_saved_detail.max_lines_visible = DETAIL_MAX_LINES
	_saved_detail.clip_text = true
	_stack.add_child(_saved_detail)
	_analytics_button = GateEntryStyle.make_button("gate.account.analytics")
	_analytics_button.name = &"AnalyticsOptIn"
	_analytics_button.toggle_mode = true
	_analytics_button.toggled.connect(_on_analytics_toggled)
	_stack.add_child(_analytics_button)
	_link_title = GateEntryStyle.make_label(
		"gate.account.link_title", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.TEXT_DIM, true)
	_link_title.name = &"LinkTitle"
	_stack.add_child(_link_title)
	# One full-width door per row, like the entry selection: the
	# official factory centers each title on its own door axis, which a
	# side-by-side pair could never hold at card width.
	_link_row = VBoxContainer.new()
	_link_row.name = &"LinkRow"
	_link_row.add_theme_constant_override(&"separation", 8)
	_stack.add_child(_link_row)
	_actions_row = HBoxContainer.new()
	_actions_row.name = &"AccountActions"
	_actions_row.add_theme_constant_override(&"separation", 8)
	_stack.add_child(_actions_row)
	_sign_out_button = GateEntryStyle.make_button("gate.account.sign_out")
	_sign_out_button.name = &"SignOut"
	_sign_out_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sign_out_button.pressed.connect(_on_sign_out)
	_actions_row.add_child(_sign_out_button)
	_delete_button = GateEntryStyle.make_button(
		"gate.account.delete", "danger")
	_delete_button.name = &"DeleteAccount"
	_delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_button.pressed.connect(_on_delete_armed)
	_actions_row.add_child(_delete_button)
	_delete_row = HBoxContainer.new()
	_delete_row.name = &"DeleteConfirm"
	_delete_row.add_theme_constant_override(&"separation", 8)
	_stack.add_child(_delete_row)
	var delete_now := GateEntryStyle.make_button(
		"gate.account.delete_confirm", "danger")
	delete_now.name = &"DeleteNow"
	delete_now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_now.pressed.connect(_on_delete_confirmed)
	_delete_row.add_child(delete_now)
	var delete_keep := GateEntryStyle.make_button("gate.account.delete_cancel")
	delete_keep.name = &"DeleteKeep"
	delete_keep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_keep.pressed.connect(_on_delete_cancelled)
	_delete_row.add_child(delete_keep)
	_links_row = HBoxContainer.new()
	_links_row.name = &"Links"
	_links_row.add_theme_constant_override(&"separation", 8)
	_stack.add_child(_links_row)
	_privacy_button = GateEntryStyle.make_button("gate.account.privacy")
	_privacy_button.name = &"Privacy"
	_privacy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_privacy_button.pressed.connect(_on_privacy)
	_links_row.add_child(_privacy_button)
	_support_button = GateEntryStyle.make_button("gate.account.support")
	_support_button.name = &"Support"
	_support_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_support_button.pressed.connect(_on_support)
	_links_row.add_child(_support_button)
	_close_button = GateEntryStyle.make_button("gate.account.close")
	_close_button.name = &"Close"
	_close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_button.pressed.connect(close)
	_links_row.add_child(_close_button)
	# The pinned shell: title row first, Close footer last, everything
	# between them inside one bounded scroll. The scroll's own height
	# is fitted in `_recenter_card`; hidden content clips at the
	# scroll rect and keyboard focus pulls it into view.
	_scroll = ScrollContainer.new()
	_scroll.name = &"Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	_scroll_box = VBoxContainer.new()
	_scroll_box.name = &"ScrollBox"
	_scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_box.add_theme_constant_override(&"separation", 6)
	_scroll_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_scroll_box)
	var header: Control = _stack.get_child(0) as Control
	for child in _stack.get_children():
		if child == header or child == _links_row:
			continue
		_stack.remove_child(child)
		_scroll_box.add_child(child)
	_stack.add_child(_scroll)
	_stack.move_child(_scroll, 1)
	visible = false


## Fill the card from host data and show it. Omitted portrait, hero name,
## provider or save each fall back to their honest empty line.
func show_account(data: Dictionary) -> void:
	_stable_id = str(data.get("stable_id", ""))
	_id_field.text = _stable_id
	_id_field.secret = false
	_id_field.editable = false
	_secret_button.text = "gate.auth.hide_id"
	_copied_note.visible = false
	var provider: String = str(data.get("provider_label", ""))
	if _stable_id.is_empty():
		_status_label.text = "gate.account.signed_out"
	else:
		_status_label.text = "gate.account.signed_in"
		if not provider.is_empty():
			_status_label.text = "%s · %s" % [
				GateEntryStrings.text("gate.account.signed_in"), provider]
	var portrait: Texture2D = data.get("portrait") as Texture2D
	var hero: Hero = data.get("hero") as Hero
	if portrait == null and hero != null:
		portrait = hero.portrait
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	var hero_name: String = str(data.get("hero_name", ""))
	if hero_name.is_empty() and hero != null:
		hero_name = hero.display_name
		if not hero_name.is_empty():
			hero_name = tr(hero_name)
	_hero_label.text = hero_name \
		if not hero_name.is_empty() else "gate.auth.no_hero"
	var saved_title: String = str(data.get("saved_title", ""))
	_saved_title.text = saved_title \
		if not saved_title.is_empty() else "gate.auth.no_save"
	var saved_detail: String = str(data.get("saved_detail", ""))
	_saved_detail.text = saved_detail
	_saved_detail.visible = not saved_detail.is_empty()
	_analytics_button.set_pressed_no_signal(
		bool(data.get("analytics_opt_in", false)))
	_rebuild_link_row(data.get("link_providers", []))
	var can_sign_out: bool = bool(data.get("can_sign_out", false))
	_sign_out_button.visible = can_sign_out
	var can_delete: bool = bool(data.get("can_delete", false))
	_delete_button.visible = can_delete
	_actions_row.visible = can_sign_out or can_delete
	# Every opening starts unarmed: a stray tap can never confirm a delete.
	_delete_row.visible = false
	var show_links: bool = bool(data.get("show_links", true))
	_privacy_button.visible = show_links \
		and not ExternalLinks.privacy_policy_url().is_empty()
	_support_button.visible = show_links \
		and not ExternalLinks.support_url().is_empty()
	# Close shares the links row, so the row itself never hides.
	_links_row.visible = true
	open()


## Fit the card to the real viewport: the title row and the Close
## footer keep their heights, the middle scroll takes the honest
## remainder, and the base centers the bounded card.
func _recenter_card() -> void:
	_fit_scroll_to_viewport()
	super._recenter_card()


func _default_focus() -> Control:
	return _close_button


## Bound the middle scroll before the base measures the card. Short
## content keeps its fitted height (no dead scroll room); overflowing
## content stops at the viewport budget minus the pinned header and
## footer, and the rest stays reachable through the scroll.
func _fit_scroll_to_viewport() -> void:
	if _card == null or _scroll == null:
		return
	var view: Vector2 = get_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var width: float = minf(
		_card.custom_minimum_size.x, view.x - 32.0)
	var content: float = maxf(
		width - GateEntryStyle.CARD_MARGIN_H, 64.0)
	# The vertical scrollbar reserves its width inside the scroll once
	# the middle overflows; without this gutter the card stretches by
	# exactly that width past its fitted size.
	var gutter: float = _scroll.get_v_scroll_bar() \
		.get_combined_minimum_size().x
	_saved_title.custom_minimum_size.x = maxf(content - gutter, 64.0)
	_saved_detail.custom_minimum_size.x = maxf(content - gutter, 64.0)
	_reserve_detail_height()
	var want: float = GateEntryStyle.fitted_stack_height(
		_scroll_box, content)
	var header: float = (_stack.get_child(0) as Control) \
		.get_combined_minimum_size().y
	var footer: float = _links_row.get_combined_minimum_size().y
	var gaps: float = 2.0 * float(
		_stack.get_theme_constant("separation"))
	var avail: float = view.y - 16.0 \
		- GateEntryStyle.CARD_MARGIN_V - header - footer - gaps
	_scroll.custom_minimum_size = Vector2(
		0.0, minf(want, maxf(avail, SCROLL_MIN_HEIGHT)))


## The clipped save detail paints nothing until a real height is
## reserved: `clip_text` collapses the minimum no matter how many
## lines the text wraps to. Reserve the rendered line block from the
## live shaped count, capped at the label's own two-line budget, so
## clearing and locale switches shrink honestly with no stale gaps.
func _reserve_detail_height() -> void:
	var font: Font = _saved_detail.get_theme_font("font")
	var font_size: int = _saved_detail.get_theme_font_size("font_size")
	var line: float = float(font.get_height(font_size))
	var spacing: float = float(
		_saved_detail.get_theme_constant("line_spacing"))
	var lines: int = mini(
		maxi(_saved_detail.get_line_count(), 1), DETAIL_MAX_LINES)
	_saved_detail.custom_minimum_size.y = float(lines) * line \
		+ float(lines - 1) * spacing


func _on_copy_id() -> void:
	if _stable_id.is_empty():
		return
	DisplayServer.clipboard_set(_stable_id)
	_copied_note.visible = true
	id_copied.emit(_stable_id)


func _on_reveal_toggle() -> void:
	_id_field.secret = not _id_field.secret
	_secret_button.text = "gate.auth.show_id" \
		if _id_field.secret else "gate.auth.hide_id"


func _rebuild_link_row(providers: Variant) -> void:
	for child in _link_row.get_children():
		_link_row.remove_child(child)
		child.queue_free()
	var rows: Array = providers if typeof(providers) == TYPE_ARRAY else []
	for entry in rows:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = entry
		var provider_id: String = str(data.get("id", ""))
		if provider_id.is_empty():
			continue
		var button: Button
		if GateProviderButtons.is_official_provider(provider_id):
			button = GateProviderButtons.make_provider_button(
				provider_id, "gate.auth.signin.%s" % provider_id)
		else:
			button = GateEntryStyle.make_button(
				str(data.get("label", provider_id)))
		button.name = &"Link%s" % provider_id.capitalize()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not bool(data.get("ready", true)) \
			or bool(data.get("draining", false))
		button.pressed.connect(_on_link_provider.bind(provider_id))
		_link_row.add_child(button)
	_link_title.visible = not rows.is_empty()
	_link_row.visible = not rows.is_empty()


func _on_link_provider(provider_id: String) -> void:
	link_requested.emit(provider_id)


func _on_sign_out() -> void:
	sign_out_requested.emit()


func _on_delete_armed() -> void:
	_actions_row.visible = false
	_delete_row.visible = true


func _on_delete_confirmed() -> void:
	_delete_row.visible = false
	delete_requested.emit()


func _on_delete_cancelled() -> void:
	_delete_row.visible = false
	_actions_row.visible = true


func _on_analytics_toggled(enabled: bool) -> void:
	analytics_opt_in_changed.emit(enabled)


func _on_privacy() -> void:
	var url: String = ExternalLinks.privacy_policy_url()
	if not url.is_empty():
		external_link_requested.emit(url)


func _on_support() -> void:
	var url: String = ExternalLinks.support_url()
	if not url.is_empty():
		external_link_requested.emit(url)
