extends Node

## The new-sale screen hides the legacy bundle, and the five individual hero cards let you check full-body and
## live description before checkout. Also checks unique artwork and capture proof on supporter and beacon-color cards,
## and that preview touch and the buy CTA do not overlap.

const SUPPORTER_ICON: Texture2D = preload(
	"res://assets/custom/ui/app_icon_main.png")
const BEACON_FLAME: Texture2D = preload(
	"res://assets/custom/world/beacon/flame.png")
const FLAME_FIRST_FRAME: Rect2 = Rect2(0, 0, 12, 12)
const LANTERN_PALETTES: Array[String] = ["ember", "moon", "violet", "jade"]
const BUTTON_FONT_COLOR_NAMES: Array[StringName] = [
	&"font_color",
	&"font_pressed_color",
	&"font_hover_color",
	&"font_disabled_color",
	&"font_hover_pressed_color",
	&"font_focus_color",
]
const HERO_CAPTURE_VISUALS: Dictionary = {
	"com.crossplatformkorea.moonlitbeacon.hero_dancer": [
		"res://resources/heroes/dancer.tres",
		"res://assets/custom/actors/heroes/dancer/portrait.png",
	],
	"com.crossplatformkorea.moonlitbeacon.hero_keeper": [
		"res://resources/heroes/keeper.tres",
		"res://assets/custom/actors/heroes/keeper/portrait.png",
	],
	"com.crossplatformkorea.moonlitbeacon.hero_knight": [
		"res://resources/heroes/knight.tres",
		"res://assets/custom/actors/heroes/knight/portrait.png",
	],
	"com.crossplatformkorea.moonlitbeacon.hero_eclipse": [
		"res://resources/heroes/eclipse.tres",
		"res://assets/custom/actors/heroes/eclipse/portrait.png",
	],
	"com.crossplatformkorea.moonlitbeacon.hero_sage": [
		"res://resources/heroes/sage.tres",
		"res://assets/custom/actors/heroes/sage/portrait.png",
	],
}
const COIN_CAPTURE_TITLES: Dictionary = {
	"com.crossplatformkorea.moonlitbeacon.continue_coin": "이어하기 코인",
	"com.crossplatformkorea.moonlitbeacon.continue_coin_5": "이어하기 코인 5개",
	"com.crossplatformkorea.moonlitbeacon.continue_coin_10": "이어하기 코인 10개",
}

@onready var _shop: Control = $IapShopPanel

var _failed: int = 0
var _checked: int = 0
var _opened_before: Array[String] = []
var _chosen_before: String = ""
var _entitlements_before: Array[String] = []


func _ready() -> void:
	# The IAP review source and independent product-name contract is a Korean capture.
	TranslationServer.set_locale("ko")
	# IapStore's desktop no-plugin init signal can redraw the card grid once more.
	await get_tree().process_frame
	await get_tree().process_frame
	_prepare_unavailable_store_fixture()
	_test_status_retranslated_on_open()
	_shop.open()
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_phone_safe_area_layout()
	var bundle: Control = _product_card(IapStore.HERO_BUNDLE)
	_expect_true(bundle == null, "hides the legacy hero_bundle from new sale cards")
	_test_coin_row_above_characters()
	var cards: HBoxContainer = _cards()
	_expect_equal(
		cards.get_child_count() + _coins().get_child_count(),
		IapStore.SALE_PRODUCT_IDS.size(),
		"new-sale product count")
	var first_preview: TextureButton = null
	for index in IapStore.HERO_PRODUCT_IDS.size():
		var product_id: String = IapStore.HERO_PRODUCT_IDS[index]
		var card: Control = _product_card(product_id)
		_expect_true(card != null, "%s individual hero card" % product_id)
		if card == null:
			continue
		_expect_equal(
			str(cards.get_child(index).get_meta(&"product_id", "")),
			str(IapStore.PERMANENT_SALE_PRODUCT_IDS[index]),
			"the first five cards of the character row are heroes")
		var previews: HBoxContainer = card.get_node(
			"Rows/Content/HeroPreviews") as HBoxContainer
		_expect_true(previews != null, "%s preview button row" % product_id)
		if previews == null:
			continue
		_expect_equal(previews.get_child_count(), 1, "%s one face" % product_id)
		if previews.get_child_count() == 1:
			var button: TextureButton = previews.get_child(0) as TextureButton
			_test_preview_button(button, IapStore.hero_path_for_product(product_id))
			_test_preview_cta_separation(card, button)
			if first_preview == null:
				first_preview = button
	if first_preview != null:
		_test_parent_back_priority(first_preview)
	await _test_scroll_range()
	await get_tree().create_timer(0.30).timeout
	await get_tree().process_frame
	# The dummy headless renderer has no draw counter, so model the previous draw serial.
	_shop.set("_open_draw_frame", -1)
	await _test_hero_capture_states()
	await _test_coin_capture_states()
	await _test_product_artworks()
	await _test_target_visual_mutations()
	await _test_offscreen_capture_rejected()
	_finish()


func _test_phone_safe_area_layout() -> void:
	# In a Pixel 10 landscape capture, the 34px gesture inset is about 11.33 internal px.
	# Even if content min height exceeds the anchor offset, the whole Shop frame
	# stays inside that bound, using the actual Container layout result.
	var full_rect: Rect2 = get_viewport().get_visible_rect()
	var edge_inset: float = 34.0 / 3.0
	var phone_safe_size: Vector2 = Vector2(
		808.0 - edge_inset * 2.0,
		360.0 - edge_inset * 2.0)
	var safe_rect: Rect2 = Rect2(
		full_rect.get_center() - phone_safe_size * 0.5,
		phone_safe_size)
	Screen.apply_safe_content(_shop, safe_rect, full_rect)
	await get_tree().process_frame
	await get_tree().process_frame
	var frame: Control = _shop.get_node("Frame") as Control
	var frame_rect: Rect2 = frame.get_global_rect()
	_expect_true(
		_rect_fully_inside(frame_rect, safe_rect),
		"Pixel 10 shop frame inside safe area %s / %s" % [
			frame_rect, safe_rect])
	Screen.apply_safe_content(_shop, full_rect, full_rect)
	await get_tree().process_frame
	await get_tree().process_frame


func _rect_fully_inside(inner: Rect2, outer: Rect2) -> bool:
	var inner_end: Vector2 = inner.position + inner.size
	var outer_end: Vector2 = outer.position + outer.size
	return inner.has_area() \
		and inner.position.x >= outer.position.x - 0.5 \
		and inner.position.y >= outer.position.y - 0.5 \
		and inner_end.x <= outer_end.x + 0.5 \
		and inner_end.y <= outer_end.y + 0.5


func _prepare_unavailable_store_fixture() -> void:
	_opened_before.assign(Vault.opened)
	_chosen_before = Vault.chosen
	_entitlements_before.assign(IapStore.entitlements)
	var paid_hero_paths: Array[String] = []
	for product_id in IapStore.HERO_PRODUCT_IDS:
		paid_hero_paths.append(IapStore.hero_path_for_product(product_id))
	for hero_path in paid_hero_paths:
		Vault.opened.erase(hero_path)
	if Vault.chosen in paid_hero_paths:
		Vault.chosen = ""
	IapStore.entitlements.clear()
	_expect_equal(
		IapStore.state,
		IapStore.StoreState.UNAVAILABLE,
		"actual unavailable state in debug with no native store")
	_shop.call("_rebuild")


func _test_status_retranslated_on_open() -> void:
	var original_locale: String = TranslationServer.get_locale()
	var status: Label = _shop.get_node("Frame/Margin/Rows/Status") as Label
	TranslationServer.set_locale("zh_TW")
	status.text = tr("IAP_DEVICE_STORE_NOTE")
	var stale_traditional: String = status.text
	TranslationServer.set_locale("ko")
	_shop.open()
	_expect_equal(status.text, _expected_status(), "IAP state refreshes to the current language after a language switch")
	_expect_true(status.text != stale_traditional, "does not leave previous Traditional-Chinese IAP status copy")
	_shop.close()
	TranslationServer.set_locale(original_locale)


func _expected_status() -> String:
	match IapStore.state:
		IapStore.StoreState.LOADING:
			return tr("IAP_CONNECTING_LONG")
		IapStore.StoreState.UNAVAILABLE:
			return tr("IAP_DEVICE_STORE_NOTE")
		IapStore.StoreState.ERROR:
			return tr("IAP_PRODUCT_LOAD_FAILED")
		IapStore.StoreState.PURCHASING:
			return tr("IAP_OPENING_STORE")
		IapStore.StoreState.PENDING:
			return tr("IAP_PENDING")
		IapStore.StoreState.RESTORING:
			return tr("IAP_RESTORING")
		_:
			return tr("IAP_STORE_READY")


func _product_card(product_id: String) -> Control:
	for row in [_coins(), _cards()]:
		for candidate in row.get_children():
			if str(candidate.get_meta(&"product_id", "")) == product_id:
				return candidate as Control
	return null


func _cards() -> HBoxContainer:
	return _shop.get_node("Frame/Margin/Rows/CardsScroll/Cards") as HBoxContainer


func _coins() -> HBoxContainer:
	return _shop.get_node("Frame/Margin/Rows/CoinsScroll/Coins") as HBoxContainer


## Someone who died into Shop should meet Continue coins first.
## Order is checked from live child positions inside Rows, so reverting the scene fails here.
func _test_coin_row_above_characters() -> void:
	var rows: VBoxContainer = _shop.get_node("Frame/Margin/Rows") as VBoxContainer
	var coins_scroll: Control = _shop.get_node(
		"Frame/Margin/Rows/CoinsScroll") as Control
	var cards_scroll: Control = _shop.get_node(
		"Frame/Margin/Rows/CardsScroll") as Control
	_expect_true(
		rows.get_children().find(coins_scroll)
			< rows.get_children().find(cards_scroll),
		"coin row is above the character row")
	var coins: HBoxContainer = _coins()
	_expect_equal(
		coins.get_child_count(),
		IapStore.COIN_SALE_PRODUCT_IDS.size(),
		"coin-bundle card count")
	# 1 → 5 → 12. Per-unit value must fall in screen order so the bundle
	# looks cheaper by eye.
	var last_grant: int = 0
	for index in mini(coins.get_child_count(), IapStore.COIN_SALE_PRODUCT_IDS.size()):
		var product_id: String = str(IapStore.COIN_SALE_PRODUCT_IDS[index])
		_expect_equal(
			str(coins.get_child(index).get_meta(&"product_id", "")),
			product_id,
			"coin-row card %d" % index)
		var grant: int = int(IapStore.CONSUMABLE_GRANTS.get(product_id, 0))
		_expect_true(grant > last_grant, "%s grant larger than the previous bundle" % product_id)
		_expect_true(
			IapStore.is_consumable(product_id), "%s consumable classification" % product_id)
		last_grant = grant


func _test_preview_button(button: TextureButton, path: String) -> void:
	var hero: Hero = load(path) as Hero
	_expect_true(button != null, "%s IAP face button" % path.get_file())
	if button == null or hero == null:
		return
	_expect_true(not button.disabled, "%s face button independent of purchase state" % path.get_file())
	_expect_equal(button.custom_minimum_size, Vector2(40, 40), "%s face-button size" % path.get_file())
	_expect_true(button.texture_normal != null, "%s face-button texture" % path.get_file())
	if button.texture_normal != null:
		_expect_equal(
			button.texture_normal.resource_path,
			hero.portrait.resource_path,
			"%s face-button portrait path" % path.get_file())

	var before_product: String = IapStore.current_product_id
	var before_entitlements: Array[String] = IapStore.entitlements.duplicate()
	var before_shards: int = Vault.shards
	var before_opened: Array[String] = Vault.opened.duplicate()
	var before_chosen: String = Vault.chosen
	button.emit_signal(&"pressed")
	var preview: HeroPreviewPanel = _shop.get_node("HeroPreview") as HeroPreviewPanel
	_expect_true(preview.is_open(), "%s IAP detail open" % path.get_file())
	_expect_equal(preview.current_hero_path(), path, "%s IAP detail hero" % path.get_file())
	_expect_equal(preview.icon_frame_count(), 4, "%s IAP full-body four frames" % path.get_file())
	var body: TextureRect = preview.get_node(
		"Frame/Margin/Rows/Content/BodyStage/Center/Body") as TextureRect
	_expect_equal(
		body.custom_minimum_size,
		Vector2(96, 96),
		"%s IAP full-body cell 96x96" % path.get_file())
	# Hang a 96×96 portrait 1:1 in a 96×96 cell. No scale, so it stays sharp.
	_expect_true(body.texture != null, "%s IAP full-body texture" % path.get_file())
	if body.texture != null:
		_expect_equal(
			body.texture.resource_path,
			hero.portrait.resource_path,
			"%s IAP full-body portrait path" % path.get_file())
		_expect_equal(
			Vector2i(body.texture.get_size()),
			Vector2i(96, 96),
			"%s IAP full-body portrait 1:1" % path.get_file())
	var icon: TextureRect = preview.get_node(
		"Frame/Margin/Rows/Header/Portrait") as TextureRect
	var atlas: AtlasTexture = icon.texture as AtlasTexture
	_expect_true(atlas != null, "%s IAP icon crop AtlasTexture" % path.get_file())
	if atlas != null:
		_expect_equal(
			atlas.region,
			Rect2(12, 32, 24, 24),
			"%s IAP first frame excluding transparent padding" % path.get_file())
	var state: Label = preview.get_node("Frame/Margin/Rows/Header/Copy/State") as Label
	var description: Label = preview.get_node(
		"Frame/Margin/Rows/Content/Description") as Label
	_expect_true(not state.text.is_empty(), "%s IAP lock/owned state" % path.get_file())
	_expect_equal(description.text, tr(hero.description), "%s IAP full description" % path.get_file())
	_expect_equal(
		IapStore.current_product_id,
		before_product,
		"%s preview does not start checkout" % path.get_file())
	_expect_equal(
		IapStore.entitlements,
		before_entitlements,
		"%s IAP entitlement unchanged by preview" % path.get_file())
	_expect_equal(Vault.shards, before_shards, "%s shards unchanged by preview" % path.get_file())
	_expect_equal(Vault.opened, before_opened, "%s unlock unchanged by preview" % path.get_file())
	_expect_equal(Vault.chosen, before_chosen, "%s selection unchanged by preview" % path.get_file())
	preview.get_node("Frame/Margin/Rows/Footer/Close").emit_signal(&"pressed")
	_expect_true(not preview.is_open(), "%s IAP detail close" % path.get_file())


func _test_preview_cta_separation(card: Control, button: TextureButton) -> void:
	var content: Control = card.get_node("Rows/Content") as Control
	var action: Button = card.get_node("Rows").get_child(-1).get_child(-1) as Button
	_expect_equal(
		card.mouse_filter,
		Control.MOUSE_FILTER_PASS,
		"IAP card-body drag reaches the scroller")
	_expect_equal(
		content.mouse_filter,
		Control.MOUSE_FILTER_PASS,
		"IAP hero-body drag reaches the scroller")
	_expect_true(
		not content.get_global_rect().intersects(action.get_global_rect()),
		"hero-preview region and buy CTA do not overlap %s / %s" % [
			content.get_global_rect(), action.get_global_rect()])
	var preview: HeroPreviewPanel = _shop.get_node("HeroPreview") as HeroPreviewPanel
	var synthetic_mouse: InputEventMouseButton = InputEventMouseButton.new()
	synthetic_mouse.button_index = MOUSE_BUTTON_LEFT
	synthetic_mouse.pressed = true
	_expect_true(
		not _shop.call("_should_open_product_preview", synthetic_mouse, true),
		"synthetic mobile mouse press does not open product preview")
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = action.get_global_rect().get_center()
	action.emit_signal(&"gui_input", touch)
	_expect_true(not preview.is_open(), "buy CTA touch does not open hero detail")
	content.emit_signal(&"gui_input", touch)
	_expect_true(not preview.is_open(), "product content touch does not block horizontal swipe")
	button.emit_signal(&"pressed")
	_expect_true(preview.is_open(), "face button opens detail separately from the CTA")
	preview.close_preview()


func _test_scroll_range() -> void:
	if not _shop.visible:
		_shop.open()
		await get_tree().process_frame
	var scroll: ScrollContainer = _shop.get_node(
		"Frame/Margin/Rows/CardsScroll") as ScrollContainer
	var cards: HBoxContainer = _cards()
	_expect_true(cards.size.x > scroll.size.x, "IAP 7-product horizontal scroll range")
	scroll.scroll_horizontal = 100_000
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(scroll.scroll_horizontal > 0, "IAP actually scrolls to later misc products")
	var last_card: Control = cards.get_child(cards.get_child_count() - 1) as Control
	_expect_true(
		scroll.get_global_rect().intersects(last_card.get_global_rect()),
		"Lantern card visible at the end of IAP scroll")
	_shop.close()
	_shop.open()
	await get_tree().process_frame
	_expect_equal(scroll.scroll_horizontal, 0, "re-entering the IAP shop starts at the first hero")


func _test_product_artworks() -> void:
	var supporter: Control = _product_card(IapStore.SUPPORTER)
	var lantern: Control = _product_card(IapStore.LANTERN_COLORS)
	_expect_true(supporter != null, "supporter product card")
	_expect_true(lantern != null, "beacon-color product card")
	if supporter != null:
		var supporter_artwork: Control = supporter.get_node_or_null(
			"Rows/Content/Artwork") as Control
		_expect_true(supporter_artwork != null, "supporter-card Artwork node")
		if supporter_artwork != null:
			var supporter_items: Array[TextureRect] = _artwork_items(
				supporter_artwork)
			_expect_equal(supporter_items.size(), 1, "supporter card has one live texture")
			if supporter_items.size() == 1:
				_expect_equal(
					supporter_items[0].texture,
					SUPPORTER_ICON,
					"supporter card uses the original app icon")
	if lantern != null:
		var lantern_artwork: Control = lantern.get_node_or_null(
			"Rows/Content/Artwork") as Control
		_expect_true(lantern_artwork != null, "beacon-color card Artwork node")
		if lantern_artwork != null:
			var lantern_items: Array[TextureRect] = _artwork_items(lantern_artwork)
			_expect_equal(
				lantern_items.size(), LANTERN_PALETTES.size(),
				"beacon-color card has four palette flames")
			for index in mini(lantern_items.size(), LANTERN_PALETTES.size()):
				var palette_id: String = LANTERN_PALETTES[index]
				var item: TextureRect = lantern_items[index]
				var atlas: AtlasTexture = item.texture as AtlasTexture
				_expect_true(atlas != null, "%s beacon first-frame AtlasTexture" % palette_id)
				if atlas != null:
					_expect_equal(atlas.atlas, BEACON_FLAME, "%s beacon flame sheet" % palette_id)
					_expect_equal(atlas.region, FLAME_FIRST_FRAME, "%s beacon first frame" % palette_id)
				_expect_equal(
					str(item.get_meta(&"artwork_palette_id", "")),
					palette_id,
					"%s beacon palette id" % palette_id)
				_expect_equal(
					item.self_modulate,
					IapStore.PALETTES[palette_id]["light"],
					"%s beacon palette color" % palette_id)
	await _test_artwork_capture_state(
		IapStore.SUPPORTER, "supporter_app_icon", 1)
	await _test_artwork_capture_state(
		IapStore.LANTERN_COLORS, "lantern_palette_flames", 4)


func _test_artwork_capture_state(
		product_id: String, expected_kind: String, expected_count: int) -> void:
	var request: Dictionary = {
		"kind": "iap_review",
		"product_id": product_id,
	}
	_shop.call("debug_prepare_store_capture", request)
	await get_tree().process_frame
	await get_tree().process_frame
	var state: Dictionary = _shop.call("debug_store_capture_state", request)
	_expect_true(not state.is_empty(), "%s capture state" % product_id)
	if state.is_empty():
		return
	_expect_true(bool(state.get("ready", false)), "%s capture prep done" % product_id)
	_expect_rendered_text_fields(state, product_id)
	_expect_true(bool(state.get("shop_opaque", false)), "%s shop fade finished" % product_id)
	_expect_true(bool(state.get("shop_drawn_after_open", false)), "%s draw after open" % product_id)
	_expect_true(not str(state.get("title_text", "")).strip_edges().is_empty(), "%s actual product name" % product_id)
	_expect_true(bool(state.get("shop_frame_inside_viewport", false)), "%s shop frame on screen" % product_id)
	_expect_true(bool(state.get("card_inside_screen", false)), "%s card on screen" % product_id)
	_expect_true(bool(state.get("artwork_node_present", false)), "%s Artwork exists" % product_id)
	_expect_equal(str(state.get("artwork_kind", "")), expected_kind, "%s art kind" % product_id)
	_expect_equal(int(state.get("artwork_item_count", -1)), expected_count, "%s art count" % product_id)
	_expect_true(bool(state.get("artwork_textures_ready", false)), "%s non-empty texture" % product_id)
	_expect_true(bool(state.get("artwork_visible_rect_ready", false)), "%s actual visible region" % product_id)
	_expect_true(bool(state.get("artwork_opaque", false)), "%s actual art opaque" % product_id)
	_expect_true(bool(state.get("artwork_product_specific", false)), "%s product-specific art" % product_id)
	var visible_rects: Array = state.get("artwork_visible_rects", [])
	_expect_equal(visible_rects.size(), expected_count, "%s visible-region count" % product_id)
	for rect_values in visible_rects:
		_expect_true(
			rect_values is Array and rect_values.size() == 4 \
				and float(rect_values[2]) > 0.0 and float(rect_values[3]) > 0.0,
			"%s positive visible region" % product_id)


func _test_hero_capture_states() -> void:
	for product_id in HERO_CAPTURE_VISUALS:
		var request: Dictionary = {
			"kind": "iap_review",
			"product_id": product_id,
		}
		_shop.call("debug_prepare_store_capture", request)
		await get_tree().process_frame
		await get_tree().process_frame
		var state: Dictionary = _shop.call("debug_store_capture_state", request)
		var expected: Array = HERO_CAPTURE_VISUALS[product_id]
		var expected_hero: String = str(expected[0])
		var expected_portrait: String = str(expected[1])
		_expect_true(bool(state.get("ready", false)), "%s hero capture ready" % product_id)
		_expect_rendered_text_fields(state, product_id)
		_expect_equal(str(state.get("hero_resource_path", "")), expected_hero, "%s hero resource" % product_id)
		_expect_equal(str(state.get("portrait_resource_path", "")), expected_portrait, "%s portrait resource" % product_id)
		_expect_true(bool(state.get("portrait_product_specific", false)), "%s SKU-specific portrait" % product_id)
		_expect_true(bool(state.get("portrait_visible_rect_ready", false)), "%s portrait actual visible region" % product_id)
		_expect_true(bool(state.get("portrait_opaque", false)), "%s portrait opaque" % product_id)


func _test_coin_capture_states() -> void:
	for product_id in COIN_CAPTURE_TITLES:
		var request: Dictionary = {
			"kind": "iap_review",
			"product_id": product_id,
		}
		_shop.call("debug_prepare_store_capture", request)
		await get_tree().process_frame
		await get_tree().process_frame
		var state: Dictionary = _shop.call("debug_store_capture_state", request)
		_expect_true(bool(state.get("ready", false)), "%s coin capture ready" % product_id)
		_expect_equal(
			str(state.get("title_expected_text", "")),
			str(COIN_CAPTURE_TITLES[product_id]),
			"%s coin capture independent product name" % product_id)
		_expect_equal(
			str(state.get("price_expected_text", "")),
			"기기 스토어 전용",
			"%s coin capture fallback price" % product_id)
		_expect_equal(
			str(state.get("action_expected_text", "")),
			"구매",
			"%s coin capture buy copy" % product_id)
		_expect_true(
			bool(state.get("card_fully_inside_viewport", false)),
			"%s coin card inside coin scroll" % product_id)
		_expect_rendered_text_fields(state, product_id)


func _test_target_visual_mutations() -> void:
	var request: Dictionary = {
		"kind": "iap_review",
		"product_id": IapStore.HERO_DANCER,
	}
	var card: Control = _product_card(IapStore.HERO_DANCER)
	var title: Label = card.get_node("Rows/Title") as Label
	var portrait: TextureButton = card.get_node(
		"Rows/Content/HeroPreviews").get_child(0) as TextureButton
	var action: Button = card.get_node("Rows/Footer/Action") as Button
	var price: Label = card.get_node("Rows/Footer/Price") as Label
	var restore: Button = _shop.get_node("Frame/Margin/Rows/Footer/Restore") as Button
	var status: Label = _shop.get_node("Frame/Margin/Rows/Status") as Label
	var state: Dictionary
	var honest_price: String = price.text
	var honest_action: String = action.text
	var honest_restore: String = restore.text
	var honest_status: String = status.text
	_shop.call("debug_prepare_store_capture", request)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(price.text, honest_price, "IAP capture prep leaves live price state unchanged")
	_expect_equal(action.text, honest_action, "IAP capture prep leaves buy copy unchanged")
	_expect_equal(restore.text, honest_restore, "IAP capture prep leaves restore copy unchanged")
	_expect_equal(status.text, honest_status, "IAP capture prep leaves shop state unchanged")
	_expect_equal(price.text, "기기 스토어 전용", "actual price fallback in debug with no native store")
	_expect_equal(
		status.text,
		"실제 가격과 구매는 App Store·Google Play에서 확인할 수 있습니다",
		"actual help copy in debug with no native store")
	_expect_equal(action.text, "구매", "buy copy in debug with no native store")
	_expect_equal(restore.text, "구매 복원", "restore copy in debug with no native store")
	_expect_true(action.disabled, "buy button disabled in debug with no native store")
	_expect_true(restore.disabled, "restore button disabled in debug with no native store")
	state = _shop.call("debug_store_capture_state", request)
	_expect_true(bool(state.get("review_fallback_verified", false)), "no-native fallback proof")
	_expect_true(bool(state.get("ready", false)), "honest unavailable capture ready")

	var original_price_text: String = price.text
	price.text = "$4.99"
	_shop.call("debug_prepare_store_capture", request)
	_expect_equal(price.text, "$4.99", "capture prep also does not overwrite a synthetic price")
	state = _shop.call("debug_store_capture_state", request)
	_expect_true(not bool(state.get("price_copy_valid", true)), "rejects a synthetic IAP price")
	_expect_true(not bool(state.get("ready", true)), "rejects ready for a synthetic IAP price")
	price.text = original_price_text
	var original_status_text: String = status.text
	status.text = "Prices are shown in local currency by the device store"
	_shop.call("debug_prepare_store_capture", request)
	_expect_equal(
		status.text,
		"Prices are shown in local currency by the device store",
		"capture prep does not overwrite a fake ready state")
	state = _shop.call("debug_store_capture_state", request)
	_expect_true(
		not bool(state.get("review_status_copy_valid", true)),
		"rejects fake IAP ready-state copy")
	_expect_true(not bool(state.get("ready", true)), "rejects ready for a fake IAP ready state")
	status.text = original_status_text
	action.disabled = false
	_shop.call("debug_prepare_store_capture", request)
	_expect_true(not action.disabled, "capture prep does not force-change the Buy button")
	state = _shop.call("debug_store_capture_state", request)
	_expect_true(bool(state.get("action_enabled", false)), "reproduces the active-buy counterexample")
	_expect_true(not bool(state.get("ready", true)), "rejects ready during an active buy")
	action.disabled = true
	restore.disabled = false
	_shop.call("debug_prepare_store_capture", request)
	_expect_true(not restore.disabled, "capture prep does not force-change the Restore button")
	state = _shop.call("debug_store_capture_state", request)
	_expect_true(bool(state.get("restore_enabled", false)), "reproduces the active-restore counterexample")
	_expect_true(not bool(state.get("ready", true)), "rejects ready during an active restore")
	restore.disabled = true

	var original_title_text: String = title.text
	title.text = "wrongly wired product name"
	state = _shop.call("debug_store_capture_state", request)
	_expect_equal(
		str(state.get("title_expected_text", "")),
		"그림자 무희",
		"expected IAP product name is a Korean literal independent of the live card")
	_expect_true(
		not bool(state.get("title_copy_valid", true)),
		"rejects a mismatch between actual and expected IAP product names")
	_expect_true(not bool(state.get("ready", true)), "rejects ready for a wrong IAP product name")
	title.text = original_title_text

	for target in [card, title, portrait, action, restore]:
		var original_modulate: Color = target.modulate
		target.modulate.a = 0.0
		state = _shop.call("debug_store_capture_state", request)
		_expect_true(not bool(state.get("ready", true)), "%s rejects alpha-0 IAP ready" % target.name)
		target.modulate = original_modulate

	var original_title_characters: int = title.visible_characters
	var original_title_ratio: float = title.visible_ratio
	title.visible_ratio = 0.0
	state = _shop.call("debug_store_capture_state", request)
	_expect_true(
		not bool(state.get("title_characters_visible", true)),
		"rejects IAP product name with visible_ratio=0")
	_expect_true(
		not bool(state.get("title_rendered_text_ready", true)),
		"rejects unrendered IAP product name")
	_expect_true(not bool(state.get("ready", true)), "rejects ready when IAP product name is not rendered")
	_restore_label_visibility(title, original_title_characters, original_title_ratio)

	for pair in [
		[action, "action_font_alpha_readable", "buy CTA"],
		[restore, "restore_font_alpha_readable", "Restore button"],
	]:
		var text_button: Button = pair[0] as Button
		var snapshots: Array[Dictionary] = _make_font_transparent(
			text_button, BUTTON_FONT_COLOR_NAMES)
		state = _shop.call("debug_store_capture_state", request)
		_expect_true(
			not bool(state.get(str(pair[1]), true)),
			"rejects font alpha=0 %s" % str(pair[2]))
		_expect_true(
			not bool(state.get("ready", true)),
			"rejects ready for transparent glyphs %s" % str(pair[2]))
		_restore_font_colors(text_button, snapshots)

	state = _shop.call("debug_store_capture_state", request)
	_expect_rendered_text_fields(state, "text counterexample restored")
	_expect_true(bool(state.get("ready", false)), "restores ready after IAP text counterexample")

	var original_hero_path: String = str(
		portrait.get_meta(&"hero_resource_path", ""))
	portrait.set_meta(
		&"hero_resource_path",
		"res://resources/heroes/keeper.tres")
	state = _shop.call("debug_store_capture_state", request)
	_expect_true(
		not bool(state.get("portrait_product_specific", true)),
		"rejects swapping hero SKU metadata")
	_expect_true(not bool(state.get("ready", true)), "rejects ready after swapping hero SKU metadata")
	portrait.set_meta(&"hero_resource_path", original_hero_path)

	var original_texture: Texture2D = portrait.texture_normal
	portrait.texture_normal = load(
		"res://assets/custom/actors/heroes/keeper/portrait.png") as Texture2D
	state = _shop.call("debug_store_capture_state", request)
	_expect_true(
		not bool(state.get("portrait_product_specific", true)),
		"rejects swapping a hero SKU portrait resource")
	_expect_true(not bool(state.get("ready", true)), "rejects ready after swapping a hero portrait")
	portrait.texture_normal = original_texture

	request["product_id"] = IapStore.SUPPORTER
	_shop.call("debug_prepare_store_capture", request)
	await get_tree().process_frame
	await get_tree().process_frame
	card = _product_card(IapStore.SUPPORTER)
	var artwork: Control = card.get_node("Rows/Content/Artwork") as Control
	var original_artwork_modulate: Color = artwork.modulate
	artwork.modulate.a = 0.0
	state = _shop.call("debug_store_capture_state", request)
	_expect_true(not bool(state.get("artwork_opaque", true)), "rejects transparent supporter art")
	_expect_true(not bool(state.get("ready", true)), "rejects ready for transparent supporter art")
	artwork.modulate = original_artwork_modulate
	var artwork_items: Array[TextureRect] = _artwork_items(artwork)
	var first_item: TextureRect = artwork_items[0]
	first_item.visible = false
	state = _shop.call("debug_store_capture_state", request)
	_expect_true(
		not bool(state.get("artwork_visible_rect_ready", true)),
		"rejects a hidden supporter-art texture")
	_expect_true(not bool(state.get("ready", true)), "rejects ready for hidden supporter art")
	first_item.visible = true


func _test_offscreen_capture_rejected() -> void:
	var request: Dictionary = {
		"kind": "iap_review",
		"product_id": IapStore.HERO_DANCER,
	}
	_shop.call("debug_prepare_store_capture", request)
	await get_tree().process_frame
	await get_tree().process_frame
	var frame: Control = _shop.get_node("Frame") as Control
	var original_position: Vector2 = frame.position
	frame.position += Vector2(3000.0, 0.0)
	await get_tree().process_frame
	var offscreen: Dictionary = _shop.call("debug_store_capture_state", request)
	_expect_true(bool(offscreen.get("card_fully_inside_viewport", false)), "looking only inside the scroll reproduces the off-screen counterexample")
	_expect_true(not bool(offscreen.get("shop_frame_inside_viewport", true)), "rejects an off-screen shop frame")
	_expect_true(not bool(offscreen.get("card_inside_screen", true)), "rejects an off-screen card")
	_expect_true(not bool(offscreen.get("ready", true)), "rejects off-screen IAP ready")
	frame.position = original_position
	await get_tree().process_frame


func _artwork_items(node: Node) -> Array[TextureRect]:
	var items: Array[TextureRect] = []
	_collect_artwork_items(node, items)
	return items


func _expect_rendered_text_fields(state: Dictionary, label: String) -> void:
	for field in [
		"title_text_nonempty",
		"title_copy_valid",
		"title_characters_visible",
		"title_font_size_positive",
		"title_font_alpha_readable",
		"title_rendered_text_ready",
		"review_fallback_verified",
		"review_status_copy_valid",
		"review_status_rendered_text_ready",
		"price_copy_valid",
		"price_rendered_text_ready",
		"action_text_nonempty",
		"action_copy_valid",
		"action_font_size_positive",
		"action_font_alpha_readable",
		"action_rendered_text_ready",
		"restore_text_nonempty",
		"restore_copy_valid",
		"restore_font_size_positive",
		"restore_font_alpha_readable",
		"restore_rendered_text_ready",
	]:
		_expect_true(bool(state.get(field, false)), label + " " + field)
	_expect_true(
		not bool(state.get("action_enabled", true)), label + " buy button disabled")
	_expect_true(
		not bool(state.get("restore_enabled", true)), label + " restore button disabled")


func _restore_label_visibility(
		label: Label, characters: int, ratio: float) -> void:
	label.visible_characters = characters
	if characters >= 0:
		label.visible_ratio = ratio


func _make_font_transparent(
		control: Control, color_names: Array[StringName]) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for color_name in color_names:
		var color: Color = control.get_theme_color(color_name)
		snapshots.append({
			"name": color_name,
			"overridden": control.has_theme_color_override(color_name),
			"color": color,
		})
		color.a = 0.0
		control.add_theme_color_override(color_name, color)
	return snapshots


func _restore_font_colors(
		control: Control, snapshots: Array[Dictionary]) -> void:
	for snapshot in snapshots:
		var color_name: StringName = snapshot["name"]
		var color: Color = snapshot["color"]
		if bool(snapshot["overridden"]):
			control.add_theme_color_override(color_name, color)
		else:
			control.remove_theme_color_override(color_name)


func _collect_artwork_items(node: Node, items: Array[TextureRect]) -> void:
	for child in node.get_children():
		if child is TextureRect:
			items.append(child as TextureRect)
		_collect_artwork_items(child, items)


func _test_parent_back_priority(button: TextureButton) -> void:
	button.emit_signal(&"pressed")
	var preview: HeroPreviewPanel = _shop.get_node("HeroPreview") as HeroPreviewPanel
	var close_count: Array[int] = [0]
	_shop.closed.connect(func() -> void: close_count[0] += 1)
	_shop.close()
	_expect_true(not preview.is_open(), "IAP Android back closes detail first")
	_expect_true(_shop.visible, "IAP shop kept after detail back")
	_expect_equal(close_count[0], 0, "detail back does not emit IAP closed")
	_shop.close()
	_expect_true(not _shop.visible, "next back closes the IAP shop")
	_expect_equal(close_count[0], 1, "IAP shop close emitted once")


func _finish() -> void:
	Vault.opened.assign(_opened_before)
	Vault.chosen = _chosen_before
	IapStore.entitlements.assign(_entitlements_before)
	if _failed > 0:
		printerr("IAP hero-preview test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("IAP hero-preview test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
