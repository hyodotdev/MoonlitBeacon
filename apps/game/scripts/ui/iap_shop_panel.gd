extends Control

## Moon shop. One screen that shows exactly what permanent products and continue coins grant.

signal closed

const CAPTURE_DRAW_FRAME_UNSET: int = -2
const CAPTURE_TEXT_READABLE_ALPHA: float = 0.35

const FONT: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Multilingual.tres"
)
const FONT_BOLD: Font = preload(
	"res://assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres"
)
const WOOD: Texture2D = preload(
	"res://assets/custom/ui/panel_moonlit.png")
const SUPPORTER_ICON: Texture2D = preload(
	"res://assets/custom/ui/app_icon_main.png")
const BEACON_FLAME: Texture2D = preload(
	"res://assets/custom/world/beacon/flame.png")

const TEXT: Color = Color(0.90, 0.93, 1.0, 1.0)
const MUTED: Color = Color(0.58, 0.64, 0.76, 1.0)
const SUCCESS: Color = Color(0.55, 1.0, 0.70, 1.0)
const ERROR: Color = Color(1.0, 0.55, 0.52, 1.0)
const SUPPORTER_ARTWORK_KIND: String = "supporter_app_icon"
const LANTERN_ARTWORK_KIND: String = "lantern_palette_flames"
const FLAME_FIRST_FRAME: Rect2 = Rect2(0, 0, 12, 12)
const LANTERN_ARTWORK_PALETTES: Array[String] = [
	"ember",
	"moon",
	"violet",
	"jade",
]
## If a live sell card reuses IapStore's own returned value as expected, a
## miswired SKU still passes. Capture proof compares five hero resources and
## portraits against a literal contract independent of the mapping that
## builds sell cards.
const CAPTURE_HERO_RESOURCE_BY_PRODUCT: Dictionary = {
	"com.crossplatformkorea.moonlitbeacon.hero_dancer":
		"res://resources/heroes/dancer.tres",
	"com.crossplatformkorea.moonlitbeacon.hero_keeper":
		"res://resources/heroes/keeper.tres",
	"com.crossplatformkorea.moonlitbeacon.hero_knight":
		"res://resources/heroes/knight.tres",
	"com.crossplatformkorea.moonlitbeacon.hero_eclipse":
		"res://resources/heroes/eclipse.tres",
	"com.crossplatformkorea.moonlitbeacon.hero_sage":
		"res://resources/heroes/sage.tres",
}
const CAPTURE_HERO_PORTRAIT_BY_PRODUCT: Dictionary = {
	"com.crossplatformkorea.moonlitbeacon.hero_dancer":
		"res://assets/custom/actors/heroes/dancer/portrait.png",
	"com.crossplatformkorea.moonlitbeacon.hero_keeper":
		"res://assets/custom/actors/heroes/keeper/portrait.png",
	"com.crossplatformkorea.moonlitbeacon.hero_knight":
		"res://assets/custom/actors/heroes/knight/portrait.png",
	"com.crossplatformkorea.moonlitbeacon.hero_eclipse":
		"res://assets/custom/actors/heroes/eclipse/portrait.png",
	"com.crossplatformkorea.moonlitbeacon.hero_sage":
		"res://assets/custom/actors/heroes/sage/portrait.png",
}
## IAP review masters are shot in Korean. If live cards and expected values
## both read the same StoreKit/catalog result, a wrong product name moves
## together, so pin the shipping CSV's sell SKU→Korean display name as an
## independent literal.
const CAPTURE_REVIEW_TITLE_BY_PRODUCT: Dictionary = {
	"com.crossplatformkorea.moonlitbeacon.supporter": "달빛 후원자",
	"com.crossplatformkorea.moonlitbeacon.hero_dancer": "그림자 무희",
	"com.crossplatformkorea.moonlitbeacon.hero_keeper": "봉화지기",
	"com.crossplatformkorea.moonlitbeacon.hero_knight": "백월 기사",
	"com.crossplatformkorea.moonlitbeacon.hero_eclipse": "월식 마도사",
	"com.crossplatformkorea.moonlitbeacon.hero_sage": "성좌 현자",
	"com.crossplatformkorea.moonlitbeacon.lantern_colors": "봉화 색상 꾸러미",
	"com.crossplatformkorea.moonlitbeacon.continue_coin": "이어하기 코인",
	"com.crossplatformkorea.moonlitbeacon.continue_coin_5": "이어하기 코인 5개",
	"com.crossplatformkorea.moonlitbeacon.continue_coin_10": "이어하기 코인 10개",
}
const CAPTURE_FALLBACK_PRICE_TEXT: String = "기기 스토어 전용"
const CAPTURE_FALLBACK_STATUS_TEXT: String = \
	"실제 가격과 구매는 App Store·Google Play에서 확인할 수 있습니다"
const CAPTURE_FALLBACK_BUY_TEXT: String = "구매"
const CAPTURE_FALLBACK_RESTORE_TEXT: String = "구매 복원"

@onready var _coin_balance: Label = $Frame/Margin/Rows/Header/CoinBalance
@onready var _status: Label = $Frame/Margin/Rows/Status
@onready var _coins_scroll: ScrollContainer = $Frame/Margin/Rows/CoinsScroll
@onready var _coins: HBoxContainer = $Frame/Margin/Rows/CoinsScroll/Coins
@onready var _cards_scroll: ScrollContainer = $Frame/Margin/Rows/CardsScroll
@onready var _cards: HBoxContainer = $Frame/Margin/Rows/CardsScroll/Cards
@onready var _palette_title: Label = $Frame/Margin/Rows/PaletteHeader/PaletteTitle
@onready var _palette_buttons: HBoxContainer = \
	$Frame/Margin/Rows/PaletteHeader/PaletteButtons
@onready var _restore: Button = $Frame/Margin/Rows/Footer/Restore
@onready var _close: Button = $Frame/Margin/Rows/Footer/Close
@onready var _preview: HeroPreviewPanel = $HeroPreview

var _open_draw_frame: int = CAPTURE_DRAW_FRAME_UNSET
var _capture_selected_product_id: String = ""


func _ready() -> void:
	_close.pressed.connect(close)
	_restore.pressed.connect(_restore_or_retry)
	IapStore.state_changed.connect(_on_store_state_changed)
	IapStore.interaction_changed.connect(_rebuild)
	IapStore.products_changed.connect(_rebuild)
	IapStore.entitlement_changed.connect(_on_entitlement_changed)
	# Coins are consumable so they do not ride the entitlement signal. Balance
	# only changes in Vault, so listen there directly — the number rises
	# right after a buy.
	Vault.changed.connect(_refresh_coin_balance)
	IapStore.purchase_succeeded.connect(_on_purchase_succeeded)
	IapStore.purchase_pending.connect(_on_purchase_pending)
	IapStore.purchase_failed.connect(_on_purchase_failed)
	IapStore.purchase_revoked.connect(_on_purchase_revoked)
	IapStore.restore_finished.connect(_on_restore_finished)
	IapStore.lantern_changed.connect(_on_lantern_changed)
	_rebuild()


func open() -> void:
	if _preview.is_open():
		_preview.close_preview()
	_open_draw_frame = Engine.get_frames_drawn()
	visible = true
	# This panel is initialized hidden with the title scene. Open after a
	# language change in settings and Godot retranslates static scene copy,
	# but code-built status copy stays on the old locale. Rebuild from the
	# current StoreState on open so purchase results are not arbitrarily
	# cleared and it always shows in the current language.
	_set_store_status()
	_refresh_coin_balance()
	_rebuild()
	_coins_scroll.scroll_horizontal = 0
	_cards_scroll.scroll_horizontal = 0
	_close.grab_focus()
	create_tween().tween_property(self, "modulate:a", 1.0, 0.22)


## Always show how many continue coins they hold.
##
## At first the number only appeared on the result-screen button after death.
## People said they could not tell where it went after buying — **if what
## you bought is not visible, it is the same as not buying.**
func _refresh_coin_balance() -> void:
	var coins: int = Vault.continue_coins
	_coin_balance.text = tr("IAP_COIN_BALANCE") % coins
	_coin_balance.visible = IapStore.storefront_enabled()


func close() -> void:
	# Android back in TitleMenu calls the parent panel's close() directly.
	# If hero detail is up, close only that first — not the shop too.
	if _preview.is_open():
		_preview.close_preview()
		return
	visible = false
	_open_draw_frame = CAPTURE_DRAW_FRAME_UNSET
	_capture_selected_product_id = ""
	closed.emit()


func _rebuild() -> void:
	if _cards == null or _coins == null:
		return
	_capture_selected_product_id = ""
	# Coins on top, characters below. Someone who died into the shop is
	# looking for continue coins first, not a new hero.
	_clear(_coins)
	for product_id in IapStore.COIN_SALE_PRODUCT_IDS:
		_coins.add_child(_make_product_card(product_id))
	_clear(_cards)
	for product_id in IapStore.PERMANENT_SALE_PRODUCT_IDS:
		_cards.add_child(_make_product_card(product_id))
	_rebuild_palettes()
	var can_retry: bool = IapStore.can_retry_connection()
	_restore.text = tr("IAP_RETRY") if can_retry else tr("IAP_RESTORE")
	_restore.disabled = not can_retry and IapStore.state != IapStore.StoreState.READY
	if _status.text.is_empty():
		_set_store_status()


func _on_store_state_changed() -> void:
	if IapStore.state in [
			IapStore.StoreState.LOADING,
			IapStore.StoreState.UNAVAILABLE,
			IapStore.StoreState.READY,
			IapStore.StoreState.ERROR,
	]:
		_set_store_status()
	_rebuild()


func _make_product_card(product_id: String) -> PanelContainer:
	var catalog: Dictionary = IapStore.catalog_entry(product_id)
	var details: Dictionary = IapStore.product_details(product_id)
	var accent: Color = catalog.get("accent", Color.WHITE)
	var owned: bool = IapStore.owns(product_id)
	var earned: bool = IapStore.benefit_already_earned(product_id)
	var card: PanelContainer = PanelContainer.new()
	var product_key: String = product_id.get_slice(
		".", product_id.get_slice_count(".") - 1)
	card.name = StringName("Product" + product_key.to_pascal_case())
	card.set_meta(&"product_id", product_id)
	# Coin cards have no art, so they are that much shorter. The two-row shop
	# still fitting Pixel 10's 337px safe area is because of that gap.
	var coin: bool = IapStore.is_consumable(product_id)
	card.custom_minimum_size = Vector2(200, 68) if coin else Vector2(246, 98)
	if coin:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Horizontal drag on the parent ScrollContainer still works over product
	# cards. Only portrait and buy buttons are child STOP for their own taps.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.085, 0.96)
	style.border_width_left = 2 if owned else 1
	style.border_width_top = 2 if owned else 1
	style.border_width_right = 2 if owned else 1
	style.border_width_bottom = 2 if owned else 1
	style.border_color = Color(accent.r, accent.g, accent.b, 0.90 if owned else 0.46)
	style.content_margin_left = 7.0
	style.content_margin_top = 3.0 if coin else 5.0
	style.content_margin_right = 7.0
	style.content_margin_bottom = 3.0 if coin else 5.0
	card.add_theme_stylebox_override("panel", style)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.name = &"Rows"
	rows.add_theme_constant_override("separation", 1 if coin else 2)
	card.add_child(rows)
	var title: String = str(details.get(
		"displayName", details.get("title", ""))).strip_edges()
	if title.is_empty():
		title = tr(str(catalog.get("title", "")))
	var title_label: Label = _label(title, 12 if coin else 13, accent, true)
	title_label.name = &"Title"
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.add_child(title_label)

	var content: HBoxContainer = HBoxContainer.new()
	content.name = &"Content"
	content.add_theme_constant_override("separation", 6)
	rows.add_child(content)

	if product_id == IapStore.HERO_BUNDLE or IapStore.is_hero_product(product_id):
		var hero_previews: HBoxContainer = HBoxContainer.new()
		hero_previews.name = &"HeroPreviews"
		hero_previews.add_theme_constant_override("separation", 3)
		var hero_paths: Array[String] = []
		if product_id == IapStore.HERO_BUNDLE:
			hero_paths.assign(IapStore.HERO_BUNDLE_PATHS)
		else:
			hero_paths.append(IapStore.hero_path_for_product(product_id))
		for path in hero_paths:
			var hero: Hero = load(path) as Hero
			if hero != null:
				hero_previews.add_child(_make_hero_preview_button(hero, path))
				if product_id != IapStore.HERO_BUNDLE:
					content.mouse_filter = Control.MOUSE_FILTER_PASS
					content.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
					content.tooltip_text = tr("HERO_PREVIEW_VIEW") % tr(hero.display_name)
					content.gui_input.connect(
						_on_hero_product_content_input.bind(hero, path))
		content.add_child(hero_previews)
	else:
		var artwork: PanelContainer = _make_product_artwork(product_id, accent)
		if artwork != null:
			content.add_child(artwork)

	var description: Label = _label(
		tr(str(catalog.get("description", ""))), 10 if coin else 11, TEXT)
	description.name = &"Description"
	# Character blurb is two lines max. A third line repeats in the detail
	# opened by tapping the face anyway, and that line is room for the coin row.
	description.custom_minimum_size.y = 13 if coin else 38
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 1 if coin else 2
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(description)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.name = &"Footer"
	footer.add_theme_constant_override("separation", 4)
	rows.add_child(footer)
	var price: Label
	var price_size: int = 10 if coin else 11
	if owned:
		price = _label("✓ " + tr("IAP_OWNED"), price_size, SUCCESS, true)
	elif earned:
		price = _label("✓ " + tr("IAP_ALREADY_EARNED"), price_size, SUCCESS, true)
	else:
		var localized_price: String = IapStore.display_price(product_id)
		price = _label(
			localized_price if not localized_price.is_empty() else _unavailable_price_text(),
			price_size, accent if not localized_price.is_empty() else MUTED, true)
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price.name = &"Price"
	footer.add_child(price)
	var action: Button = _button(
		tr("IAP_OWNED") if owned else tr("IAP_ALREADY_EARNED") if earned \
		else tr("IAP_BUY"), accent, coin)
	action.disabled = owned or earned or not IapStore.can_purchase(product_id)
	if not owned and not earned:
		action.pressed.connect(_buy.bind(product_id))
	action.name = &"Action"
	footer.add_child(action)
	return card


func _on_hero_product_content_input(
		event: InputEvent, hero: Hero, path: String) -> void:
	# Android/iOS touch also emits a synthetic MouseButton, so dragging the
	# body would open preview. On mobile only the Portrait button owns preview.
	if _should_open_product_preview(event, OS.has_feature("mobile")):
		_open_hero_preview(hero, path)


func _should_open_product_preview(event: InputEvent, mobile: bool) -> bool:
	if mobile or event is not InputEventMouseButton:
		return false
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	return mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT


func _make_hero_preview_button(hero: Hero, path: String) -> TextureButton:
	var button: TextureButton = TextureButton.new()
	button.name = StringName("Preview" + path.get_file().get_basename().to_pascal_case())
	button.custom_minimum_size = Vector2(40, 40)
	button.focus_mode = Control.FOCUS_NONE
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.texture_normal = hero.portrait
	button.set_meta(&"hero_resource_path", path)
	button.tooltip_text = tr("HERO_PREVIEW_VIEW") % tr(hero.display_name)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_open_hero_preview.bind(hero, path))
	return button


func _open_hero_preview(hero: Hero, path: String) -> void:
	_preview.open_hero(hero, path)


func _make_product_artwork(
		product_id: String, accent: Color) -> PanelContainer:
	if product_id == IapStore.SUPPORTER:
		return _make_supporter_artwork(accent)
	if product_id == IapStore.LANTERN_COLORS:
		return _make_lantern_artwork(accent)
	return null


func _make_supporter_artwork(accent: Color) -> PanelContainer:
	var stage: PanelContainer = _make_artwork_stage(
		SUPPORTER_ARTWORK_KIND, Vector2(46, 44), accent)
	var center: CenterContainer = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(center)
	var icon: TextureRect = _artwork_texture_rect(
		&"SupporterIcon", SUPPORTER_ICON, Vector2(38, 38))
	icon.set_meta(&"artwork_item_kind", SUPPORTER_ARTWORK_KIND)
	center.add_child(icon)
	return stage


func _make_lantern_artwork(accent: Color) -> PanelContainer:
	var stage: PanelContainer = _make_artwork_stage(
		LANTERN_ARTWORK_KIND, Vector2(92, 44), accent)
	var flames: HBoxContainer = HBoxContainer.new()
	flames.name = &"PaletteFlames"
	flames.alignment = BoxContainer.ALIGNMENT_CENTER
	flames.add_theme_constant_override("separation", 1)
	flames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(flames)
	for palette_id in LANTERN_ARTWORK_PALETTES:
		var frame: AtlasTexture = AtlasTexture.new()
		frame.atlas = BEACON_FLAME
		frame.region = FLAME_FIRST_FRAME
		var flame: TextureRect = _artwork_texture_rect(
			StringName("Flame" + palette_id.to_pascal_case()),
			frame,
			Vector2(20, 38))
		var palette: Dictionary = IapStore.PALETTES[palette_id]
		flame.self_modulate = palette.get("light", Color.WHITE)
		flame.set_meta(&"artwork_item_kind", LANTERN_ARTWORK_KIND)
		flame.set_meta(&"artwork_palette_id", palette_id)
		flames.add_child(flame)
	return stage


func _make_artwork_stage(
		kind: String, minimum_size: Vector2, accent: Color) -> PanelContainer:
	var stage: PanelContainer = PanelContainer.new()
	stage.name = &"Artwork"
	stage.custom_minimum_size = minimum_size
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.set_meta(&"artwork_kind", kind)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(accent.r * 0.10, accent.g * 0.10, accent.b * 0.14, 0.94)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(accent.r, accent.g, accent.b, 0.52)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	style.content_margin_left = 2.0
	style.content_margin_top = 2.0
	style.content_margin_right = 2.0
	style.content_margin_bottom = 2.0
	stage.add_theme_stylebox_override("panel", style)
	return stage


func _artwork_texture_rect(
		item_name: StringName, texture: Texture2D,
		minimum_size: Vector2) -> TextureRect:
	var item: TextureRect = TextureRect.new()
	item.name = item_name
	item.custom_minimum_size = minimum_size
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item.texture = texture
	return item


func debug_prepare_store_capture(request: Dictionary) -> void:
	if not OS.is_debug_build() or not visible \
			or str(request.get("kind", "")) != "iap_review":
		return
	if _preview.is_open():
		_preview.close_preview()
	var product_id: String = str(request.get("product_id", ""))
	var card: Control = _debug_product_card(product_id)
	var scroll: ScrollContainer = _coins_scroll \
		if IapStore.is_consumable(product_id) else _cards_scroll
	if card == null or card.size.x <= 0.0 or scroll.size.x <= 0.0:
		return
	# Capture prep only selects a product card and moves it to screen center.
	# Price, state, and buttons keep the values this build actually computed,
	# so direct-distribution fallback is not dressed up.
	_capture_selected_product_id = product_id
	var target: int = roundi(
		card.position.x - maxf((scroll.size.x - card.size.x) * 0.5, 0.0))
	var bar: HScrollBar = scroll.get_h_scroll_bar()
	var maximum: int = maxi(ceili(bar.max_value - bar.page), 0)
	scroll.scroll_horizontal = clampi(target, 0, maximum)


func debug_store_capture_state(request: Dictionary) -> Dictionary:
	if not OS.is_debug_build() \
			or str(request.get("kind", "")) != "iap_review":
		return {}
	var expected_product_id: String = str(request.get("product_id", ""))
	var card: Control = _debug_product_card(expected_product_id)
	if card == null:
		return {}
	var scroll: ScrollContainer = _coins_scroll \
		if IapStore.is_consumable(expected_product_id) else _cards_scroll
	var viewport_rect: Rect2 = scroll.get_global_rect()
	var card_rect: Rect2 = card.get_global_rect()
	var screen_rect: Rect2 = get_viewport().get_visible_rect()
	var safe_rect: Rect2 = Screen.viewport_safe_rect(get_viewport())
	var frame: Control = $Frame
	var frame_rect: Rect2 = frame.get_global_rect()
	var card_end: Vector2 = card_rect.position + card_rect.size
	var viewport_end: Vector2 = viewport_rect.position + viewport_rect.size
	var fully_inside: bool = card_rect.size.x > 0.0 and card_rect.size.y > 0.0 \
		and card_rect.position.x >= viewport_rect.position.x - 0.5 \
		and card_rect.position.y >= viewport_rect.position.y - 0.5 \
		and card_end.x <= viewport_end.x + 0.5 \
		and card_end.y <= viewport_end.y + 0.5
	var shop_frame_inside_viewport: bool = frame.is_visible_in_tree() \
		and _debug_rect_fully_inside(frame_rect, screen_rect)
	var shop_frame_inside_safe_area: bool = frame.is_visible_in_tree() \
		and _debug_rect_fully_inside(frame_rect, safe_rect)
	var card_inside_screen: bool = _debug_rect_fully_inside(card_rect, screen_rect)
	var card_inside_safe_area: bool = _debug_rect_fully_inside(card_rect, safe_rect)
	var card_visible_rect_ready: bool = card.is_visible_in_tree() \
		and card_rect.intersection(viewport_rect).intersection(screen_rect).has_area()
	var card_opaque: bool = _debug_effective_alpha(card) >= 0.99
	var title: Label = card.get_node_or_null("Rows/Title") as Label
	var portrait_row: Control = card.get_node_or_null(
		"Rows/Content/HeroPreviews") as Control
	var artwork: Control = card.get_node_or_null("Rows/Content/Artwork") as Control
	var action: Button = card.get_node_or_null("Rows/Footer/Action") as Button
	var price: Label = card.get_node_or_null("Rows/Footer/Price") as Label
	var portrait_button: TextureButton = null
	if portrait_row != null and portrait_row.get_child_count() == 1:
		portrait_button = portrait_row.get_child(0) as TextureButton
	var hero_resource_path: String = "" if portrait_button == null \
		else str(portrait_button.get_meta(&"hero_resource_path", ""))
	var portrait_resource_path: String = ""
	if portrait_button != null and portrait_button.texture_normal != null:
		portrait_resource_path = portrait_button.texture_normal.resource_path
	var expected_hero_resource_path: String = str(
		CAPTURE_HERO_RESOURCE_BY_PRODUCT.get(expected_product_id, ""))
	var expected_portrait_resource_path: String = str(
		CAPTURE_HERO_PORTRAIT_BY_PRODUCT.get(expected_product_id, ""))
	var portrait_product_specific: bool = not expected_hero_resource_path.is_empty() \
		and not expected_portrait_resource_path.is_empty() \
		and hero_resource_path == expected_hero_resource_path \
		and portrait_resource_path == expected_portrait_resource_path
	var portrait_visible: bool = portrait_row != null \
		and portrait_row.is_visible_in_tree() and portrait_button != null \
		and portrait_button.is_visible_in_tree() \
		and portrait_button.get_global_rect().intersection(card_rect).intersection(
			viewport_rect).has_area() and portrait_product_specific
	var portrait_opaque: bool = portrait_button != null \
		and _debug_effective_alpha(portrait_button) >= 0.99
	var portrait_visible_rect_ready: bool = portrait_button != null \
		and portrait_button.get_global_rect().intersection(card_rect).intersection(
			viewport_rect).intersection(screen_rect).has_area()
	var expected_artwork_kind: String = _debug_expected_artwork_kind(
		expected_product_id)
	var expected_artwork_count: int = _debug_expected_artwork_count(
		expected_product_id)
	var artwork_kind: String = "" if artwork == null \
		else str(artwork.get_meta(&"artwork_kind", ""))
	var artwork_items: Array[TextureRect] = _debug_artwork_texture_rects(artwork)
	var artwork_item_rects: Array[Array] = []
	var artwork_visible_rects: Array[Array] = []
	var artwork_textures_ready: bool = not artwork_items.is_empty()
	var artwork_visible_rect_ready: bool = not artwork_items.is_empty()
	var artwork_opaque: bool = artwork != null \
		and _debug_effective_alpha(artwork) >= 0.99
	var artwork_product_specific: bool = not expected_artwork_kind.is_empty() \
		and artwork_kind == expected_artwork_kind \
		and artwork_items.size() == expected_artwork_count
	for index in artwork_items.size():
		var item: TextureRect = artwork_items[index]
		var draw_rect: Rect2 = _debug_texture_draw_rect(item)
		var visible_rect: Rect2 = draw_rect.intersection(card_rect).intersection(
			viewport_rect)
		artwork_item_rects.append(_debug_rect_array(draw_rect))
		artwork_visible_rects.append(_debug_rect_array(visible_rect))
		artwork_textures_ready = artwork_textures_ready \
			and item.texture != null \
			and _debug_artwork_item_matches(item, expected_product_id, index)
		artwork_visible_rect_ready = artwork_visible_rect_ready \
			and item.is_visible_in_tree() and visible_rect.has_area()
		artwork_opaque = artwork_opaque and _debug_effective_alpha(item) >= 0.99
	var artwork_node_present: bool = artwork != null
	var artwork_visible: bool = artwork_node_present \
		and artwork.is_visible_in_tree() \
		and artwork.get_global_rect().intersection(card_rect).intersection(
			viewport_rect).has_area() \
		and artwork_textures_ready and artwork_visible_rect_ready \
		and artwork_product_specific
	var title_text: String = "" if title == null else title.text.strip_edges()
	var expected_title_text: String = _debug_expected_product_title(
		expected_product_id)
	var title_text_nonempty: bool = not title_text.is_empty()
	var title_copy_valid: bool = title_text_nonempty \
		and not expected_title_text.is_empty() and title_text == expected_title_text
	var title_characters_visible: bool = title != null \
		and _debug_label_characters_visible(title)
	var title_font_size_positive: bool = title != null \
		and _debug_font_size_positive(title)
	var title_font_alpha_readable: bool = title != null \
		and _debug_label_effective_font_alpha(title) \
			>= CAPTURE_TEXT_READABLE_ALPHA
	var title_rendered_text_ready: bool = title_copy_valid \
		and title_characters_visible and title_font_size_positive \
		and title_font_alpha_readable
	var title_visible_rect_ready: bool = title != null \
		and title.get_global_rect().intersection(card_rect).intersection(
			viewport_rect).intersection(screen_rect).has_area()
	var title_opaque: bool = title != null and _debug_effective_alpha(title) >= 0.99
	var expected_price_text: String = CAPTURE_FALLBACK_PRICE_TEXT \
		if TranslationServer.get_locale() == "ko" \
			and CAPTURE_REVIEW_TITLE_BY_PRODUCT.has(expected_product_id) else ""
	var price_text: String = "" if price == null else price.text.strip_edges()
	var price_copy_valid: bool = not expected_price_text.is_empty() \
		and price_text == expected_price_text
	var price_rendered_text_ready: bool = price != null and price_copy_valid \
		and _debug_label_characters_visible(price) \
		and _debug_font_size_positive(price) \
		and _debug_label_effective_font_alpha(price) >= CAPTURE_TEXT_READABLE_ALPHA
	var price_visible_rect_ready: bool = price != null \
		and price.get_global_rect().intersection(card_rect).intersection(
			viewport_rect).intersection(screen_rect).has_area()
	var price_opaque: bool = price != null and _debug_effective_alpha(price) >= 0.99
	var review_status_text: String = _status.text.strip_edges()
	var review_status_copy_valid: bool = \
		review_status_text == CAPTURE_FALLBACK_STATUS_TEXT
	var review_status_rendered_text_ready: bool = review_status_copy_valid \
		and _debug_label_characters_visible(_status) \
		and _debug_font_size_positive(_status) \
		and _debug_label_effective_font_alpha(_status) >= CAPTURE_TEXT_READABLE_ALPHA
	var review_status_visible_rect_ready: bool = _status.get_global_rect().intersection(
		frame_rect).intersection(screen_rect).has_area()
	var review_status_opaque: bool = _debug_effective_alpha(_status) >= 0.99
	var action_visible_rect_ready: bool = action != null \
		and action.get_global_rect().intersection(card_rect).intersection(
			viewport_rect).intersection(screen_rect).has_area()
	var action_opaque: bool = action != null and _debug_effective_alpha(action) >= 0.99
	var action_text: String = "" if action == null else action.text.strip_edges()
	var expected_action_text: String = _debug_expected_action_text(
		expected_product_id)
	var action_text_nonempty: bool = not action_text.is_empty()
	var action_copy_valid: bool = action_text_nonempty \
		and not expected_action_text.is_empty() and action_text == expected_action_text
	var action_font_size_positive: bool = action != null \
		and _debug_font_size_positive(action)
	var action_font_alpha_readable: bool = action != null \
		and _debug_button_effective_font_alpha(action) \
			>= CAPTURE_TEXT_READABLE_ALPHA
	var action_rendered_text_ready: bool = action_copy_valid \
		and action_font_size_positive and action_font_alpha_readable
	var restore_visible_rect_ready: bool = _restore.get_global_rect().intersection(
		frame_rect).intersection(screen_rect).has_area()
	var restore_opaque: bool = _debug_effective_alpha(_restore) >= 0.99
	var restore_text: String = _restore.text.strip_edges()
	var expected_restore_text: String = CAPTURE_FALLBACK_RESTORE_TEXT \
		if TranslationServer.get_locale() == "ko" else ""
	var restore_text_nonempty: bool = not restore_text.is_empty()
	var restore_copy_valid: bool = restore_text_nonempty \
		and not expected_restore_text.is_empty() \
		and restore_text == expected_restore_text
	var restore_font_size_positive: bool = _debug_font_size_positive(_restore)
	var restore_font_alpha_readable: bool = _debug_button_effective_font_alpha(
		_restore) >= CAPTURE_TEXT_READABLE_ALPHA
	var restore_rendered_text_ready: bool = restore_copy_valid \
		and restore_font_size_positive and restore_font_alpha_readable
	var review_fallback_verified: bool = TranslationServer.get_locale() == "ko" \
		and _capture_selected_product_id == expected_product_id \
		and IapStore.state == IapStore.StoreState.UNAVAILABLE \
		and price_copy_valid and review_status_copy_valid \
		and action != null and action.disabled and action_copy_valid \
		and _restore.disabled and restore_copy_valid
	var shop_opaque: bool = _debug_effective_alpha(self) >= 0.99
	var shop_drawn_after_open: bool = _open_draw_frame != CAPTURE_DRAW_FRAME_UNSET \
		and Engine.get_frames_drawn() > _open_draw_frame
	var state: Dictionary = {
		"shop_visible": visible and is_visible_in_tree(),
		"shop_opaque": shop_opaque,
		"shop_drawn_after_open": shop_drawn_after_open,
		"shop_frame_inside_viewport": shop_frame_inside_viewport,
		"shop_frame_inside_safe_area": shop_frame_inside_safe_area,
		"safe_area_inside_viewport": _debug_rect_fully_inside(
			safe_rect, screen_rect),
		"iap_safe_ui_ready": shop_frame_inside_safe_area \
			and card_inside_safe_area \
			and _debug_rect_fully_inside(safe_rect, screen_rect),
		"preview_visible": _preview.is_open() and _preview.is_visible_in_tree(),
		"product_id": str(card.get_meta(&"product_id", "")),
		"card_visible": card.is_visible_in_tree(),
		"card_visible_rect_ready": card_visible_rect_ready,
		"card_opaque": card_opaque,
		"title_visible": title != null and title.is_visible_in_tree() \
			and not title_text.is_empty(),
		"title_text": title_text,
		"title_expected_text": expected_title_text,
		"title_text_nonempty": title_text_nonempty,
		"title_copy_valid": title_copy_valid,
		"title_characters_visible": title_characters_visible,
		"title_font_size_positive": title_font_size_positive,
		"title_font_alpha_readable": title_font_alpha_readable,
		"title_rendered_text_ready": title_rendered_text_ready,
		"title_visible_rect_ready": title_visible_rect_ready,
		"title_opaque": title_opaque,
		"review_fallback_verified": review_fallback_verified,
		"review_status_visible": _status.is_visible_in_tree(),
		"review_status_text": review_status_text,
		"review_status_expected_text": CAPTURE_FALLBACK_STATUS_TEXT,
		"review_status_copy_valid": review_status_copy_valid,
		"review_status_rendered_text_ready": review_status_rendered_text_ready,
		"review_status_visible_rect_ready": review_status_visible_rect_ready,
		"review_status_opaque": review_status_opaque,
		"price_visible": price != null and price.is_visible_in_tree(),
		"price_text": price_text,
		"price_expected_text": expected_price_text,
		"price_copy_valid": price_copy_valid,
		"price_rendered_text_ready": price_rendered_text_ready,
		"price_visible_rect_ready": price_visible_rect_ready,
		"price_opaque": price_opaque,
		"portrait_visible": portrait_visible,
		"portrait_visible_rect_ready": portrait_visible_rect_ready,
		"portrait_opaque": portrait_opaque,
		"hero_resource_path": hero_resource_path,
		"hero_expected_resource_path": expected_hero_resource_path,
		"portrait_resource_path": portrait_resource_path,
		"portrait_expected_resource_path": expected_portrait_resource_path,
		"portrait_product_specific": portrait_product_specific,
		"artwork_visible": artwork_visible,
		"artwork_node_present": artwork_node_present,
		"artwork_kind": artwork_kind,
		"artwork_expected_kind": expected_artwork_kind,
		"artwork_item_count": artwork_items.size(),
		"artwork_expected_item_count": expected_artwork_count,
		"artwork_textures_ready": artwork_textures_ready,
		"artwork_visible_rect_ready": artwork_visible_rect_ready,
		"artwork_opaque": artwork_opaque,
		"artwork_product_specific": artwork_product_specific,
		"artwork_item_rects": artwork_item_rects,
		"artwork_visible_rects": artwork_visible_rects,
		"action_visible": action != null and action.is_visible_in_tree(),
		"action_enabled": action != null and not action.disabled,
		"action_text": action_text,
		"action_expected_text": expected_action_text,
		"action_text_nonempty": action_text_nonempty,
		"action_copy_valid": action_copy_valid,
		"action_font_size_positive": action_font_size_positive,
		"action_font_alpha_readable": action_font_alpha_readable,
		"action_rendered_text_ready": action_rendered_text_ready,
		"action_visible_rect_ready": action_visible_rect_ready,
		"action_opaque": action_opaque,
		"restore_visible": _restore.is_visible_in_tree(),
		"restore_enabled": not _restore.disabled,
		"restore_text": restore_text,
		"restore_expected_text": expected_restore_text,
		"restore_text_nonempty": restore_text_nonempty,
		"restore_copy_valid": restore_copy_valid,
		"restore_font_size_positive": restore_font_size_positive,
		"restore_font_alpha_readable": restore_font_alpha_readable,
		"restore_rendered_text_ready": restore_rendered_text_ready,
		"restore_visible_rect_ready": restore_visible_rect_ready,
		"restore_opaque": restore_opaque,
		"card_fully_inside_viewport": fully_inside,
		"card_inside_screen": card_inside_screen,
		"card_inside_safe_area": card_inside_safe_area,
		"card_rect": [card_rect.position.x, card_rect.position.y,
			card_rect.size.x, card_rect.size.y],
		"screen_rect": _debug_rect_array(screen_rect),
		"safe_rect": _debug_rect_array(safe_rect),
		"shop_frame_rect": _debug_rect_array(frame_rect),
		"viewport_rect": [viewport_rect.position.x, viewport_rect.position.y,
			viewport_rect.size.x, viewport_rect.size.y],
	}
	var expects_portrait: bool = expected_product_id == IapStore.HERO_BUNDLE \
		or IapStore.is_hero_product(expected_product_id)
	var expects_text_only_card: bool = IapStore.is_consumable(expected_product_id)
	var product_visual_ready: bool = true if expects_text_only_card \
		else portrait_visible if expects_portrait else artwork_visible
	state["ready"] = bool(state["shop_visible"]) \
		and bool(state["shop_opaque"]) and bool(state["shop_drawn_after_open"]) \
		and bool(state["shop_frame_inside_viewport"]) \
		and bool(state["iap_safe_ui_ready"]) \
		and not bool(state["preview_visible"]) \
		and str(state["product_id"]) == expected_product_id \
		and bool(state["card_visible"]) \
		and bool(state["card_visible_rect_ready"]) and bool(state["card_opaque"]) \
		and bool(state["title_visible"]) \
		and title_rendered_text_ready \
		and bool(state["title_visible_rect_ready"]) and bool(state["title_opaque"]) \
		and review_fallback_verified \
		and bool(state["review_status_visible"]) \
		and review_status_rendered_text_ready \
		and review_status_visible_rect_ready and review_status_opaque \
		and bool(state["price_visible"]) and price_rendered_text_ready \
		and price_visible_rect_ready and price_opaque \
		and product_visual_ready \
		and (not expects_portrait or bool(state["portrait_visible_rect_ready"]) \
			and bool(state["portrait_opaque"])) \
		and (expects_portrait or expects_text_only_card \
			or bool(state["artwork_opaque"])) \
		and bool(state["action_visible"]) \
		and not bool(state["action_enabled"]) \
		and action_rendered_text_ready \
		and bool(state["action_visible_rect_ready"]) and bool(state["action_opaque"]) \
		and bool(state["restore_visible"]) \
		and not bool(state["restore_enabled"]) \
		and restore_rendered_text_ready \
		and bool(state["restore_visible_rect_ready"]) and bool(state["restore_opaque"]) \
		and bool(state["card_fully_inside_viewport"]) \
		and bool(state["card_inside_screen"]) \
		and bool(state["card_inside_safe_area"])
	return state


func _debug_rect_fully_inside(inner: Rect2, outer: Rect2) -> bool:
	var inner_end: Vector2 = inner.position + inner.size
	var outer_end: Vector2 = outer.position + outer.size
	return inner.size.x > 0.0 and inner.size.y > 0.0 \
		and inner.position.x >= outer.position.x - 0.5 \
		and inner.position.y >= outer.position.y - 0.5 \
		and inner_end.x <= outer_end.x + 0.5 \
		and inner_end.y <= outer_end.y + 0.5


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


func _debug_label_characters_visible(label: Label) -> bool:
	return label.visible_characters != 0 and label.visible_ratio >= 0.999


func _debug_font_size_positive(control: Control) -> bool:
	return control.get_theme_font_size(&"font_size") > 0


func _debug_label_effective_font_alpha(label: Label) -> float:
	return _debug_effective_alpha(label) \
		* label.get_theme_color(&"font_color").a


func _debug_button_effective_font_alpha(button: Button) -> float:
	var color_name: StringName = &"font_color"
	var draw_mode: int = button.get_draw_mode()
	match draw_mode:
		BaseButton.DRAW_PRESSED:
			color_name = &"font_pressed_color"
		BaseButton.DRAW_HOVER:
			color_name = &"font_hover_color"
		BaseButton.DRAW_DISABLED:
			color_name = &"font_disabled_color"
		BaseButton.DRAW_HOVER_PRESSED:
			color_name = &"font_hover_pressed_color"
	if draw_mode == BaseButton.DRAW_NORMAL and button.has_focus():
		color_name = &"font_focus_color"
	return _debug_effective_alpha(button) \
		* button.get_theme_color(color_name).a


func _debug_expected_product_title(product_id: String) -> String:
	if TranslationServer.get_locale() != "ko":
		return ""
	return str(CAPTURE_REVIEW_TITLE_BY_PRODUCT.get(product_id, ""))


func _debug_expected_action_text(product_id: String) -> String:
	if TranslationServer.get_locale() != "ko" \
			or not CAPTURE_REVIEW_TITLE_BY_PRODUCT.has(product_id):
		return ""
	return CAPTURE_FALLBACK_BUY_TEXT


func _debug_expected_artwork_kind(product_id: String) -> String:
	if product_id == IapStore.SUPPORTER:
		return SUPPORTER_ARTWORK_KIND
	if product_id == IapStore.LANTERN_COLORS:
		return LANTERN_ARTWORK_KIND
	return ""


func _debug_expected_artwork_count(product_id: String) -> int:
	if product_id == IapStore.SUPPORTER:
		return 1
	if product_id == IapStore.LANTERN_COLORS:
		return LANTERN_ARTWORK_PALETTES.size()
	return 0


func _debug_artwork_texture_rects(artwork: Control) -> Array[TextureRect]:
	var items: Array[TextureRect] = []
	if artwork != null:
		_debug_collect_artwork_textures(artwork, items)
	return items


func _debug_collect_artwork_textures(
		node: Node, items: Array[TextureRect]) -> void:
	for child in node.get_children():
		if child is TextureRect:
			items.append(child as TextureRect)
		_debug_collect_artwork_textures(child, items)


func _debug_artwork_item_matches(
		item: TextureRect, product_id: String, index: int) -> bool:
	if product_id == IapStore.SUPPORTER:
		return index == 0 \
			and str(item.get_meta(&"artwork_item_kind", "")) \
				== SUPPORTER_ARTWORK_KIND \
			and item.texture == SUPPORTER_ICON
	if product_id != IapStore.LANTERN_COLORS \
			or index < 0 or index >= LANTERN_ARTWORK_PALETTES.size():
		return false
	var palette_id: String = LANTERN_ARTWORK_PALETTES[index]
	var atlas: AtlasTexture = item.texture as AtlasTexture
	if atlas == null:
		return false
	var palette: Dictionary = IapStore.PALETTES[palette_id]
	return str(item.get_meta(&"artwork_item_kind", "")) \
			== LANTERN_ARTWORK_KIND \
		and str(item.get_meta(&"artwork_palette_id", "")) == palette_id \
		and atlas.atlas == BEACON_FLAME \
		and atlas.region == FLAME_FIRST_FRAME \
		and item.self_modulate.is_equal_approx(
			palette.get("light", Color.WHITE))


func _debug_texture_draw_rect(item: TextureRect) -> Rect2:
	var control_rect: Rect2 = item.get_global_rect()
	if item.texture == null or control_rect.size.x <= 0.0 \
			or control_rect.size.y <= 0.0:
		return Rect2()
	if item.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		return control_rect
	var texture_size: Vector2 = item.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Rect2()
	var scale_factor: float = minf(
		control_rect.size.x / texture_size.x,
		control_rect.size.y / texture_size.y)
	var draw_size: Vector2 = texture_size * scale_factor
	return Rect2(
		control_rect.position + (control_rect.size - draw_size) * 0.5,
		draw_size)


func _debug_rect_array(rect: Rect2) -> Array[float]:
	return [
		rect.position.x,
		rect.position.y,
		rect.size.x,
		rect.size.y,
	]


func _debug_product_card(product_id: String) -> Control:
	if not OS.is_debug_build() or product_id.is_empty():
		return null
	for row in [_cards, _coins]:
		for child in row.get_children():
			if child is Control \
					and str(child.get_meta(&"product_id", "")) == product_id:
				return child as Control
	return null


func _unavailable_price_text() -> String:
	match IapStore.state:
		IapStore.StoreState.LOADING:
			return tr("IAP_CONNECTING")
		IapStore.StoreState.UNAVAILABLE:
			return tr("IAP_DEVICE_ONLY")
		_:
			return tr("IAP_PRODUCT_UNAVAILABLE")


func _rebuild_palettes() -> void:
	_clear(_palette_buttons)
	var unlocked: bool = IapStore.owns(IapStore.LANTERN_COLORS)
	_palette_title.text = tr(
		"IAP_PALETTE_READY" if unlocked else "IAP_PALETTE_LOCKED")
	_palette_title.add_theme_color_override(
		"font_color", SUCCESS if unlocked else MUTED)
	for palette_id in IapStore.PALETTES:
		var data: Dictionary = IapStore.PALETTES[palette_id]
		var selected: bool = palette_id == IapStore.selected_palette
		var available: bool = palette_id in IapStore.available_palettes()
		var button: Button = _button(
			("◆ " if selected else "") + tr(str(data.get("name", ""))),
			data.get("light", Color.WHITE), true)
		button.custom_minimum_size = Vector2(112, 20)
		button.disabled = not available or selected
		if available and not selected:
			button.pressed.connect(_select_palette.bind(str(palette_id)))
		_palette_buttons.add_child(button)


func _buy(product_id: String) -> void:
	_status.text = tr("IAP_OPENING_STORE")
	_status.add_theme_color_override("font_color", TEXT)
	IapStore.purchase(product_id)
	_rebuild()


func _restore_or_retry() -> void:
	if IapStore.can_retry_connection():
		_status.text = tr("IAP_RETRYING")
		_status.add_theme_color_override("font_color", TEXT)
		_rebuild()
		await IapStore.retry_connection()
		return
	_status.text = tr("IAP_RESTORING")
	_status.add_theme_color_override("font_color", TEXT)
	_rebuild()
	await IapStore.restore_purchases()


func _select_palette(palette_id: String) -> void:
	if IapStore.select_palette(palette_id):
		_status.text = tr("IAP_PALETTE_SELECTED") % IapStore.palette_name()
		_status.add_theme_color_override("font_color", SUCCESS)
		$Sfx.play()
	_rebuild()


func _on_entitlement_changed(_product_id: String) -> void:
	_rebuild()


func _on_purchase_succeeded(product_id: String) -> void:
	var catalog: Dictionary = IapStore.catalog_entry(product_id)
	_status.text = tr("IAP_PURCHASED") % tr(str(catalog.get("title", "")))
	_status.add_theme_color_override("font_color", SUCCESS)
	$Sfx.play()
	_rebuild()


func _on_purchase_pending(_product_id: String) -> void:
	_status.text = tr("IAP_PENDING")
	_status.add_theme_color_override("font_color", Color(1.0, 0.82, 0.46, 1.0))
	_rebuild()


func _on_purchase_failed(product_id: String, code: String) -> void:
	# Do not show failure copy on a product already granted. On Play's first
	# purchase, auth-setup and points prompts stack behind the buy sheet, and
	# in that gap entitlement can grant while a late failure code still
	# arrives. First buy on a physical Pixel 10 did exactly that — product
	# "owned" and "payment could not complete" together. Ownership is the
	# truth, so follow that.
	if not product_id.is_empty() and IapStore.owns(product_id):
		var owned_catalog: Dictionary = IapStore.catalog_entry(product_id)
		_status.text = tr("IAP_PURCHASED") % tr(str(owned_catalog.get("title", "")))
		_status.add_theme_color_override("font_color", SUCCESS)
		_rebuild()
		return
	if code in ["user-cancelled", "user-canceled", "cancelled", "canceled"]:
		_status.text = tr("IAP_CANCELLED")
		_status.add_theme_color_override("font_color", MUTED)
	elif code == "verification-unavailable":
		_status.text = tr("IAP_VERIFY_RETRY")
		_status.add_theme_color_override(
			"font_color", Color(1.0, 0.82, 0.46, 1.0))
	elif code in ["verification-configuration-error", "verification-rejected"]:
		_status.text = tr("IAP_VERIFY_SUPPORT")
		_status.add_theme_color_override("font_color", ERROR)
	else:
		_status.text = tr("IAP_FAILED")
		_status.add_theme_color_override("font_color", ERROR)
	_rebuild()


func _on_purchase_revoked(_product_id: String) -> void:
	_status.text = tr("IAP_REVOKED")
	_status.add_theme_color_override("font_color", MUTED)
	_rebuild()


func _on_restore_finished(count: int) -> void:
	_status.text = tr("IAP_RESTORE_FOUND") % count if count > 0 \
		else tr("IAP_RESTORE_EMPTY")
	_status.add_theme_color_override("font_color", SUCCESS if count > 0 else MUTED)
	_rebuild()


func _on_lantern_changed(_palette_id: String) -> void:
	_rebuild_palettes()


func _set_store_status() -> void:
	match IapStore.state:
		IapStore.StoreState.LOADING:
			_status.text = tr("IAP_CONNECTING_LONG")
			_status.add_theme_color_override("font_color", TEXT)
		IapStore.StoreState.UNAVAILABLE:
			_status.text = tr("IAP_DEVICE_STORE_NOTE")
			_status.add_theme_color_override("font_color", MUTED)
		IapStore.StoreState.ERROR:
			_status.text = tr("IAP_PRODUCT_LOAD_FAILED")
			_status.add_theme_color_override("font_color", ERROR)
		IapStore.StoreState.PURCHASING:
			_status.text = tr("IAP_OPENING_STORE")
			_status.add_theme_color_override("font_color", TEXT)
		IapStore.StoreState.PENDING:
			_status.text = tr("IAP_PENDING")
			_status.add_theme_color_override(
				"font_color", Color(1.0, 0.82, 0.46, 1.0))
		IapStore.StoreState.RESTORING:
			_status.text = tr("IAP_RESTORING")
			_status.add_theme_color_override("font_color", TEXT)
		_:
			_status.text = tr("IAP_STORE_READY")
			_status.add_theme_color_override("font_color", TEXT)


func _clear(container: Container) -> void:
	for old in container.get_children():
		container.remove_child(old)
		old.queue_free()


func _label(text: String, size: int, color: Color, bold: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT_BOLD if bold else FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, accent: Color, compact: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(72, 20) if compact else Vector2(82, 22)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", FONT_BOLD)
	button.add_theme_font_size_override("font_size", 10 if compact else 11)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override(
		"font_disabled_color", Color(accent.r, accent.g, accent.b, 0.42))
	var margin: float = 3.0 if compact else 5.0
	button.add_theme_stylebox_override(
		"normal", _wood_style(Color(0.84, 0.88, 1.0, 0.88), margin))
	button.add_theme_stylebox_override(
		"hover", _wood_style(Color(1.0, 1.0, 1.0, 0.98), margin))
	button.add_theme_stylebox_override(
		"pressed", _wood_style(Color(0.58, 0.66, 0.84, 0.92), margin))
	button.add_theme_stylebox_override(
		"disabled", _wood_style(Color(0.38, 0.42, 0.52, 0.56), margin))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


func _wood_style(tone: Color, margin: float = 5.0) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = WOOD
	style.texture_margin_left = margin
	style.texture_margin_top = margin
	style.texture_margin_right = margin
	style.texture_margin_bottom = margin
	style.modulate_color = tone
	return style


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _preview.is_open():
			_preview.close_preview()
		else:
			close()
