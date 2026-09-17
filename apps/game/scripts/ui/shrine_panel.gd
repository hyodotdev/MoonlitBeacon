extends Control

## Moon shrine — a permanent-growth shop that shows what you get before spending shards.
##
## Heroes split `unlock` from `select`. If the current loadout changed in
## secret just because money was spent, the next run would not be what they
## expected. Boons put current rank, next effect, price, and shortfall on one
## card.

signal closed

const PURCHASE_LOCK_SECONDS: float = 0.28
const CAPTURE_DRAW_FRAME_UNSET: int = -2
const HERO_CARD_SIZE: Vector2 = Vector2(242, 72)
const HERO_PORTRAIT_SIZE: Vector2 = Vector2(48, 48)
const BOON_CARD_SIZE: Vector2 = Vector2(300, 46)
const NARROW_FRAME_WIDTH: float = 700.0

const FONT: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Multilingual.tres"
)
const FONT_BOLD: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres"
)
const WOOD: Texture2D = preload(
	"res://assets/custom/ui/panel_moonlit.png")

const TEXT: Color = Color(0.86, 0.9, 0.98, 1)
const MUTED: Color = Color(0.55, 0.6, 0.7, 1)
const SUCCESS: Color = Color(0.72, 1, 0.78, 1)
const ERROR: Color = Color(1, 0.58, 0.55, 1)

@onready var _shards: Label = $Frame/Margin/Rows/Header/Shards
@onready var _frame: PanelContainer = $Frame
@onready var _goal: Label = $Frame/Margin/Rows/Header/Goal
@onready var _heroes_scroll: ScrollContainer = $Frame/Margin/Rows/HeroesScroll
@onready var _heroes: HBoxContainer = $Frame/Margin/Rows/HeroesScroll/Heroes
@onready var _list: GridContainer = $Frame/Margin/Rows/List
@onready var _close: Button = $Frame/Margin/Rows/Footer/Close
@onready var _sfx: AudioStreamPlayer = $Sfx
@onready var _preview: HeroPreviewPanel = $HeroPreview

var _actions: Array[Button] = []
var _busy: bool = false
var _feedback_text: String = ""
var _feedback_error: bool = false
var _feedback_tween: Tween = null
var _recommended_path: String = ""
var _opened_draw_frame: int = CAPTURE_DRAW_FRAME_UNSET


func _ready() -> void:
	visible = false
	_frame.resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_close.pressed.connect(close)
	Vault.changed.connect(_on_vault_changed)
	IapStore.state_changed.connect(_on_iap_state_changed)
	IapStore.interaction_changed.connect(_on_iap_state_changed)
	IapStore.products_changed.connect(_on_iap_state_changed)
	IapStore.entitlement_changed.connect(_on_iap_entitlement_changed)
	IapStore.purchase_succeeded.connect(_on_iap_purchase_succeeded)
	IapStore.purchase_pending.connect(_on_iap_purchase_pending)
	IapStore.purchase_failed.connect(_on_iap_purchase_failed)
	IapStore.purchase_revoked.connect(_on_iap_purchase_revoked)


func open() -> void:
	_busy = false
	_feedback_text = ""
	_feedback_error = false
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = null
	_goal.modulate = Color.WHITE
	if _preview.is_open():
		_preview.close_preview()
	_rebuild()
	_apply_responsive_layout()
	_heroes_scroll.scroll_horizontal = 0
	visible = true
	modulate.a = 0.0
	_opened_draw_frame = Engine.get_frames_drawn()
	create_tween().tween_property(self, "modulate:a", 1.0, 0.22)


func _apply_responsive_layout() -> void:
	# Landscape iPhone with Dynamic Island has a usable width narrower than a
	# tablet. Forcing a 2-column min width makes the parent Frame punch
	# through the safe root again. On a narrow screen stack the three boons
	# in one column so copy and buy buttons both survive.
	_list.columns = 1 if _frame.size.x < NARROW_FRAME_WIDTH else 2


func close() -> void:
	# Title Android-back handling also calls this. During detail view, unwind
	# one step only — do not close the shrine too.
	if _preview.is_open():
		_preview.close_preview()
		return
	visible = false
	closed.emit()


## Redraw balance, next goal, and products in one pass. The purchase API emits
## a state-change signal, but during a buy this function also bundles the
## result message.
func _rebuild() -> void:
	_shards.text = tr("SHARDS") % Vault.shards
	_update_goal()
	_clear_cards(_heroes)
	_clear_cards(_list)
	_actions.clear()

	for path in Vault.HEROES:
		var hero: Hero = load(path) as Hero
		if hero != null:
			_heroes.add_child(_make_hero_card(hero, path))

	for path in Vault.POOL:
		var boon: Boon = load(path) as Boon
		if boon != null:
			_list.add_child(_make_boon_card(boon, path))


func _update_goal() -> void:
	var next: Dictionary = Vault.next_purchase()
	_recommended_path = "" if next.is_empty() else str(next.get("path", ""))
	if not _feedback_text.is_empty():
		_goal.text = _feedback_text
		_goal.add_theme_color_override(
			"font_color", ERROR if _feedback_error else SUCCESS)
		return
	if next.is_empty():
		_goal.text = tr("SHRINE_ALL_OWNED")
		_goal.add_theme_color_override("font_color", SUCCESS)
		return

	var cost: int = int(next.get("cost", 0))
	var name: String = str(next.get("name", ""))
	if cost <= Vault.shards:
		_goal.text = tr("SHRINE_NEXT_READY") % name
		_goal.add_theme_color_override("font_color", SUCCESS)
	else:
		_goal.text = tr("SHRINE_NEXT_GOAL") % [name, cost - Vault.shards]
		_goal.add_theme_color_override("font_color", Color(0.78, 0.84, 1, 1))


func _clear_cards(container: Container) -> void:
	for old in container.get_children():
		# `queue_free()` alone leaves the old card in this frame's layout and
		# input. Detach from the tree first so a double-tap cannot come in at
		# the old price.
		container.remove_child(old)
		old.queue_free()


func _make_hero_card(hero: Hero, path: String) -> PanelContainer:
	# This is where a card is "Unlocked" vs a price. Ask ownership —
	# `hero_open()` is all-true on debug, so store cuts and review images
	# would photograph "Unlocked" instead of a price. See `Vault.hero_earned()`.
	var opened: bool = Vault.hero_earned(path)
	var selected: bool = path == Vault.hero_path()
	var recommended: bool = path == _recommended_path
	var card: PanelContainer = _card(hero.accent, selected or recommended)
	card.name = StringName("Hero" + path.get_file().get_basename().to_pascal_case())
	card.custom_minimum_size = HERO_CARD_SIZE
	# If the body is STOP, a touch drag never reaches the parent
	# ScrollContainer, so heroes 4–6 are only visible by grabbing the
	# scrollbar exactly. Buttons stay STOP as children; only the card body
	# is PASS.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = tr("HERO_PREVIEW_VIEW") % tr(hero.display_name)
	card.gui_input.connect(_on_hero_card_input.bind(hero, path))

	var body: HBoxContainer = HBoxContainer.new()
	body.name = &"Body"
	body.add_theme_constant_override("separation", 5)
	card.add_child(body)

	var portrait: TextureButton = TextureButton.new()
	portrait.name = &"Portrait"
	portrait.custom_minimum_size = HERO_PORTRAIT_SIZE
	portrait.focus_mode = Control.FOCUS_NONE
	portrait.ignore_texture_size = true
	portrait.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# A 96×96 portrait in a 48 cell shrinks to 0.5× and smears. Hang a 24×24 crop at 2×.
	portrait.texture_normal = hero.idle_icon_texture()
	portrait.tooltip_text = tr("HERO_PREVIEW_VIEW") % tr(hero.display_name)
	portrait.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	portrait.pressed.connect(_open_hero_preview.bind(hero, path))
	body.add_child(portrait)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.name = &"Copy"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 1)
	body.add_child(rows)

	var head: HBoxContainer = HBoxContainer.new()
	var name: Label = _label(tr(hero.display_name), 11, hero.accent, true)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	if recommended:
		head.add_child(_label("★", 11, hero.accent, true))
	rows.add_child(head)

	# Pre-buy stats and opening relics are written with nothing hidden, so
	# two lines would hide a paid hero's core downside behind an ellipsis.
	# Keep three lines and shrink only the body one step.
	var description: Label = _label(tr(hero.description), 8, TEXT)
	description.name = &"Description"
	description.custom_minimum_size.y = 27
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 3
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.add_child(description)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.name = &"Footer"
	footer.add_theme_constant_override("separation", 4)
	var state: Label
	var action: Button
	if opened:
		state = _label(tr("SHRINE_OWNED"), 11, MUTED)
		action = _button(
			tr("SHRINE_SELECTED") if selected else tr("SHRINE_SELECT"), hero.accent)
		action.disabled = selected or _busy
		if not selected:
			action.pressed.connect(_choose_hero.bind(hero, path))
	elif path in Vault.PAID_HEROES:
		var product_id: String = IapStore.hero_product_for_path(path)
		var localized_price: String = IapStore.display_price(product_id)
		state = _label(
			localized_price if not localized_price.is_empty() \
			else _hero_iap_price_text(),
			11, hero.accent if not localized_price.is_empty() else MUTED)
		action = _button(tr("IAP_BUY"), hero.accent)
		action.disabled = _busy or not IapStore.can_purchase(product_id)
		action.pressed.connect(_purchase_hero_iap.bind(product_id))
	else:
		state = _price_label(hero.unlock_cost)
		action = _button(tr("SHRINE_UNLOCK"), hero.accent)
		action.disabled = _busy or Vault.shards < hero.unlock_cost
		action.pressed.connect(_purchase_hero.bind(hero, path))
	state.name = &"State"
	action.name = &"Action"
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(state)
	footer.add_child(action)
	rows.add_child(footer)
	_actions.append(action)
	return card


func _hero_iap_price_text() -> String:
	match IapStore.state:
		IapStore.StoreState.LOADING:
			return tr("IAP_CONNECTING")
		IapStore.StoreState.UNAVAILABLE:
			return tr("IAP_DEVICE_ONLY")
		_:
			return tr("IAP_PRODUCT_UNAVAILABLE")


func _on_hero_card_input(event: InputEvent, hero: Hero, path: String) -> void:
	# Android touch is exclusive to child Action Button or Portrait. Comparing
	# physical screen coords to stretched viewport coords as an exception
	# misses per device, so card-body preview is desktop mouse only. Mobile
	# also sends a synthetic MouseButton after ScreenTouch, so filtering by
	# event type alone would open preview on a swipe. Exclude mobile card
	# bodies entirely; only the Portrait button opens preview.
	if _should_open_card_preview(event, OS.has_feature("mobile")):
		_open_hero_preview(hero, path)


func _should_open_card_preview(event: InputEvent, mobile: bool) -> bool:
	if mobile or event is not InputEventMouseButton:
		return false
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	return mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT


func _open_hero_preview(hero: Hero, path: String) -> void:
	_preview.open_hero(hero, path)


func debug_prepare_store_capture(request: Dictionary) -> void:
	if not OS.is_debug_build() or not visible:
		return
	var kind: String = str(request.get("kind", ""))
	if kind == "shrine":
		if _preview.is_open():
			_preview.close_preview()
		_debug_prepare_all_hero_lineup()
		return
	if kind != "hero_preview":
		return
	var path: String = str(request.get("hero_path", ""))
	if path not in Vault.HEROES or _preview.current_hero_path() == path \
			and _preview.is_open():
		return
	var hero: Hero = load(path) as Hero
	if hero != null:
		_preview.open_hero(hero, path)


func debug_store_capture_state(request: Dictionary) -> Dictionary:
	if not OS.is_debug_build():
		return {}
	var kind: String = str(request.get("kind", ""))
	var frame_rect: Rect2 = _frame.get_global_rect()
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var safe_rect: Rect2 = Screen.viewport_safe_rect(get_viewport())
	var frame_end: Vector2 = frame_rect.position + frame_rect.size
	var viewport_end: Vector2 = viewport_rect.position + viewport_rect.size
	var frame_inside_viewport: bool = frame_rect.size.x > 0.0 \
		and frame_rect.size.y > 0.0 \
		and frame_rect.position.x >= viewport_rect.position.x - 0.5 \
		and frame_rect.position.y >= viewport_rect.position.y - 0.5 \
		and frame_end.x <= viewport_end.x + 0.5 \
		and frame_end.y <= viewport_end.y + 0.5
	var frame_inside_safe_area: bool = _debug_rect_fully_inside(
		frame_rect, safe_rect)
	var shrine_opaque: bool = modulate.a >= 0.99
	var drawn_after_open: bool = _opened_draw_frame != CAPTURE_DRAW_FRAME_UNSET \
		and Engine.get_frames_drawn() > _opened_draw_frame
	var hero_cards_visible_rect_count: int = 0
	var hero_clip_rect: Rect2 = _heroes_scroll.get_global_rect() \
		.intersection(frame_rect).intersection(safe_rect)
	for child in _heroes.get_children():
		var card: Control = child as Control
		if card != null and card.is_visible_in_tree() \
				and _debug_visible_fraction(card.get_global_rect(), hero_clip_rect) >= 0.9 \
				and _debug_effective_alpha(card) >= 0.99:
			hero_cards_visible_rect_count += 1
	var base: Dictionary = {
		"shrine_visible": visible and is_visible_in_tree(),
		"preview_visible": _preview.is_open() and _preview.is_visible_in_tree(),
		"hero_card_count": _heroes.get_child_count(),
		"hero_cards_visible_rect_count": hero_cards_visible_rect_count,
		"shrine_opaque": shrine_opaque,
		"shrine_frame_inside_viewport": frame_inside_viewport,
		"viewport_rect": _debug_rect_array(viewport_rect),
		"safe_rect": _debug_rect_array(safe_rect),
		"shrine_frame_rect": _debug_rect_array(frame_rect),
		"safe_area_inside_viewport": _debug_rect_fully_inside(
			safe_rect, viewport_rect),
		"shrine_frame_inside_safe_area": frame_inside_safe_area,
		"shrine_safe_ui_ready": frame_inside_safe_area \
			and _debug_rect_fully_inside(safe_rect, viewport_rect),
		"shrine_drawn_after_open": drawn_after_open,
	}
	if kind == "shrine":
		base["ready"] = bool(base["shrine_visible"]) \
			and not bool(base["preview_visible"]) \
			and int(base["hero_card_count"]) == Vault.HEROES.size() \
			and hero_cards_visible_rect_count == Vault.HEROES.size() \
			and shrine_opaque and frame_inside_viewport \
			and bool(base["shrine_safe_ui_ready"]) and drawn_after_open
		return base
	if kind == "hero_preview":
		var preview_state: Dictionary = _preview.debug_store_capture_state(
			str(request.get("hero_path", "")))
		base.merge(preview_state, true)
		base["ready"] = bool(base.get("shrine_visible", false)) \
			and shrine_opaque and frame_inside_viewport \
			and bool(base["shrine_safe_ui_ready"]) and drawn_after_open \
			and bool(preview_state.get("ready", false))
		return base
	return {}


func _debug_rect_fully_inside(inner: Rect2, outer: Rect2) -> bool:
	if not inner.has_area() or not outer.has_area():
		return false
	return inner.position.x >= outer.position.x - 0.5 \
		and inner.position.y >= outer.position.y - 0.5 \
		and inner.end.x <= outer.end.x + 0.5 \
		and inner.end.y <= outer.end.y + 0.5


func _debug_rect_array(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## Store screen 05 promises "six heroes." The shrine normally scrolls
## horizontally so detail copy and buy buttons can be read, but capture
## gathers the six real card portraits on one screen so the promised lineup
## shows as-is. Debug capture only.
func _debug_prepare_all_hero_lineup() -> void:
	_heroes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_heroes_scroll.scroll_horizontal = 0
	_heroes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for child in _heroes.get_children():
		var card: PanelContainer = child as PanelContainer
		if card == null:
			continue
		card.custom_minimum_size = Vector2(100, HERO_CARD_SIZE.y)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var body: HBoxContainer = card.get_node_or_null("Body") as HBoxContainer
		var copy: Control = card.get_node_or_null("Body/Copy") as Control
		if body != null:
			body.alignment = BoxContainer.ALIGNMENT_CENTER
		if copy != null:
			copy.visible = false


func _debug_visible_fraction(inner: Rect2, clip: Rect2) -> float:
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return 0.0
	return inner.intersection(clip).get_area() / inner.get_area()


func _debug_effective_alpha(item: CanvasItem) -> float:
	var alpha: float = 1.0
	var current: Node = item
	var own_item: bool = true
	while current != null:
		if current is CanvasItem:
			var canvas_item: CanvasItem = current as CanvasItem
			alpha *= canvas_item.modulate.a
			if own_item:
				alpha *= canvas_item.self_modulate.a
			own_item = false
		current = current.get_parent()
	return alpha


func _make_boon_card(boon: Boon, path: String) -> PanelContainer:
	var rank: int = Vault.rank_of(path)
	var maxed: bool = rank >= boon.max_rank
	var recommended: bool = path == _recommended_path
	var card: PanelContainer = _card(boon.accent, recommended)
	card.custom_minimum_size = BOON_CARD_SIZE

	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	card.add_child(body)

	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 0)
	body.add_child(copy)

	var head: HBoxContainer = HBoxContainer.new()
	var name: Label = _label(
		"%s  %d/%d" % [tr(boon.display_name), rank, boon.max_rank],
		11, boon.accent, true)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	if recommended:
		head.add_child(_label("★", 11, boon.accent, true))
	copy.add_child(head)

	var effect: Label
	if maxed:
		effect = _label(tr("BOON_MAXED"), 11, MUTED)
	else:
		effect = _label(tr("SHRINE_NEXT_EFFECT") % boon.describe(rank), 11, TEXT)
		effect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(effect)

	var action_rows: VBoxContainer = VBoxContainer.new()
	action_rows.custom_minimum_size.x = 86
	action_rows.add_theme_constant_override("separation", 0)
	body.add_child(action_rows)

	var action: Button
	if maxed:
		action_rows.add_child(_label(tr("SHRINE_OWNED"), 11, MUTED, false, true))
		action = _button(tr("BOON_MAXED"), boon.accent)
		action.disabled = true
	else:
		var cost: int = boon.cost_at(rank + 1)
		action_rows.add_child(_price_label(cost, true))
		action = _button(tr("SHRINE_BUY"), boon.accent)
		action.disabled = _busy or Vault.shards < cost
		action.pressed.connect(_purchase_boon.bind(boon, path, rank))
	action_rows.add_child(action)
	_actions.append(action)
	return card


func _price_label(cost: int, centered: bool = false) -> Label:
	var enough: bool = Vault.shards >= cost
	var text: String = tr("SHRINE_PRICE") % cost if enough \
		else tr("SHRINE_SHORT") % (cost - Vault.shards)
	return _label(text, 11, SUCCESS if enough else ERROR, false, centered)


func _card(accent: Color, highlighted: bool) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.085, 0.95)
	var border: int = 2 if highlighted else 1
	style.border_width_left = border
	style.border_width_top = border
	style.border_width_right = border
	style.border_width_bottom = border
	style.border_color = Color(accent.r, accent.g, accent.b, 0.9 if highlighted else 0.38)
	style.content_margin_left = 4.0
	style.content_margin_top = 3.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 3.0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(
		text: String, size: int, color: Color, bold: bool = false,
		centered: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT_BOLD if bold else FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _button(text: String, accent: Color) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(82, 19)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", FONT_BOLD)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_disabled_color", Color(
		accent.r, accent.g, accent.b, 0.38))
	button.add_theme_stylebox_override(
		"normal", _wood_style(Color(0.8, 0.83, 0.95, 0.82)))
	button.add_theme_stylebox_override(
		"hover", _wood_style(Color(1, 1, 1, 0.96)))
	button.add_theme_stylebox_override(
		"pressed", _wood_style(Color(0.58, 0.65, 0.82, 0.9)))
	button.add_theme_stylebox_override(
		"disabled", _wood_style(Color(0.38, 0.4, 0.48, 0.54)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


func _wood_style(tone: Color) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = WOOD
	style.texture_margin_left = 5.0
	style.texture_margin_top = 5.0
	style.texture_margin_right = 5.0
	style.texture_margin_bottom = 5.0
	style.modulate_color = tone
	return style


func _purchase_boon(boon: Boon, path: String, expected_rank: int) -> void:
	if _busy:
		return
	_busy = true
	_disable_actions()
	var paid: int = boon.cost_at(expected_rank + 1)
	var result: int = Vault.purchase_boon(boon, path, expected_rank)
	match result:
		Vault.PurchaseResult.OK:
			Analytics.track("boon_purchased", {
				"boon": path.get_file().get_basename().to_lower(),
				"rank": Vault.rank_of(path),
				"shards_spent": maxi(paid, 0),
			})
			_set_feedback(tr("SHRINE_BOON_BOUGHT") % [
				tr(boon.display_name), Vault.rank_of(path)], false, true)
		Vault.PurchaseResult.INSUFFICIENT:
			var cost: int = boon.cost_at(Vault.rank_of(path) + 1)
			_set_feedback(tr("SHRINE_NEED_MORE") % maxi(cost - Vault.shards, 0), true)
		Vault.PurchaseResult.SAVE_FAILED:
			_set_feedback(tr("SHRINE_SAVE_FAILED"), true)
		Vault.PurchaseResult.STALE:
			_set_feedback(tr("SHRINE_REFRESHED"), true)
		Vault.PurchaseResult.MAXED:
			_set_feedback(tr("BOON_MAXED"), true)
		_:
			_set_feedback(tr("SHRINE_INVALID"), true)
	await _unlock_actions()


func _purchase_hero(hero: Hero, path: String) -> void:
	if _busy:
		return
	_busy = true
	_disable_actions()
	var result: int = Vault.purchase_hero(path)
	match result:
		Vault.PurchaseResult.OK:
			# After unlock they still must `select`. Buy and equip are different decisions.
			_set_feedback(
				tr("SHRINE_HERO_UNLOCKED") % tr(hero.display_name), false, true)
		Vault.PurchaseResult.INSUFFICIENT:
			_set_feedback(
				tr("SHRINE_NEED_MORE") % maxi(hero.unlock_cost - Vault.shards, 0), true)
		Vault.PurchaseResult.SAVE_FAILED:
			_set_feedback(tr("SHRINE_SAVE_FAILED"), true)
		Vault.PurchaseResult.OWNED:
			_set_feedback(tr("SHRINE_REFRESHED"), true)
		_:
			_set_feedback(tr("SHRINE_INVALID"), true)
	await _unlock_actions()


func _purchase_hero_iap(product_id: String) -> void:
	if _busy or not IapStore.is_hero_product(product_id):
		return
	_busy = true
	_disable_actions()
	_feedback_text = tr("IAP_OPENING_STORE")
	_feedback_error = false
	_rebuild()
	if IapStore.purchase(product_id):
		return
	_busy = false
	_set_feedback(_hero_iap_price_text(), true)


func _choose_hero(hero: Hero, path: String) -> void:
	if _busy:
		return
	_busy = true
	_disable_actions()
	if Vault.choose_hero(path):
		Analytics.track("hero_selected", {
			"hero": path.get_file().get_basename().to_lower(),
		})
		_set_feedback(tr("SHRINE_HERO_SELECTED") % tr(hero.display_name), false, true)
	else:
		_set_feedback(tr("SHRINE_SAVE_FAILED"), true)
	await _unlock_actions()


func _set_feedback(message: String, is_error: bool, play_sound: bool = false) -> void:
	_feedback_text = message
	_feedback_error = is_error
	_rebuild()
	if play_sound:
		_sfx.pitch_scale = 1.08
		_sfx.play()
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_goal.modulate = Color(1.35, 1.35, 1.35, 1)
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(_goal, "modulate", Color.WHITE, 0.24)
	_feedback_tween.tween_interval(1.2)
	_feedback_tween.tween_callback(_clear_feedback)


func _clear_feedback() -> void:
	_feedback_text = ""
	_feedback_error = false
	_feedback_tween = null
	if is_inside_tree() and visible:
		_update_goal()


func _disable_actions() -> void:
	for action in _actions:
		if is_instance_valid(action):
			action.disabled = true


## Even an immediate redraw can let an old touch's release hit a new button.
## Allow the next buy only after a short input lock.
func _unlock_actions() -> void:
	await get_tree().create_timer(PURCHASE_LOCK_SECONDS, true).timeout
	if not is_inside_tree():
		return
	_busy = false
	if visible:
		_rebuild()


func _on_vault_changed() -> void:
	if visible and not _busy:
		_rebuild()


func _on_iap_state_changed() -> void:
	if visible and not _busy:
		_rebuild()


func _on_iap_entitlement_changed(_product_id: String) -> void:
	if visible and not _busy:
		_rebuild()


func _on_iap_purchase_succeeded(product_id: String) -> void:
	if not visible or not IapStore.is_hero_product(product_id):
		return
	_busy = false
	var hero: Hero = load(IapStore.hero_path_for_product(product_id)) as Hero
	var display_name: String = tr(hero.display_name) if hero != null \
		else tr(str(IapStore.catalog_entry(product_id).get("title", "")))
	_set_feedback(tr("IAP_PURCHASED") % display_name, false, true)


func _on_iap_purchase_pending(product_id: String) -> void:
	if not visible or not IapStore.is_hero_product(product_id):
		return
	_busy = false
	_set_feedback(tr("IAP_PENDING"), false)


func _on_iap_purchase_failed(product_id: String, code: String) -> void:
	if not visible or not IapStore.is_hero_product(product_id):
		return
	_busy = false
	# Do not show failure copy on a product already granted. Same reason as
	# the shop panel — Play's first purchase can deliver a late failure code
	# that disagrees with ownership.
	if IapStore.owns(product_id):
		_on_iap_purchase_succeeded(product_id)
		return
	if code in ["user-cancelled", "user-canceled", "cancelled", "canceled"]:
		_set_feedback(tr("IAP_CANCELLED"), false)
	elif code == "verification-unavailable":
		_set_feedback(tr("IAP_VERIFY_RETRY"), true)
	elif code in ["verification-configuration-error", "verification-rejected"]:
		_set_feedback(tr("IAP_VERIFY_SUPPORT"), true)
	else:
		_set_feedback(tr("IAP_FAILED"), true)


func _on_iap_purchase_revoked(product_id: String) -> void:
	if not visible or not IapStore.is_hero_product(product_id):
		return
	_busy = false
	_set_feedback(tr("IAP_REVOKED"), false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and visible:
		_rebuild.call_deferred()


## Close on back. Without this, Android is trapped.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		accept_event()
		if _preview.is_open():
			_preview.close_preview()
		else:
			close()
