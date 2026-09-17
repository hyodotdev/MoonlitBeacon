extends Node

## On a live Shrine card, even a locked hero's full body is readable, and preview input does not change Buy/select
## state.

const HERO_IDS: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage",
]
const HERO_PATHS: Array[String] = [
	"res://resources/heroes/warden.tres",
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/eclipse.tres",
	"res://resources/heroes/sage.tres",
]
const UI_LOCALES: Array[String] = ["en", "ko", "ja", "zh_CN", "zh_TW"]
const SAFE_INSET: float = 4.0
## Do not read the implementation's capture contract as-is; pin ship copy independently in the test too.
const KEEPER_EXPECTED_COPY: Dictionary = {
	"ko": {
		"name": "봉화지기",
		"state": "선택 중",
		"locked_state": "잠김 · 기기 스토어에서 구매",
		"description": "하트 6칸 · 이속 -15% · 피해 +25% · 대시 쿨 +30% · 달빛 파문·질긴 목숨",
	},
	"en": {
		"name": "Beacon Keeper",
		"state": "Selected",
		"locked_state": "Locked · purchase in device store",
		"description": "6 hearts · move -15% · dmg +25% · dash CD +30% · Moonlit Ripple/Tenacious Life",
	},
	"ja": {
		"name": "烽火の守り人",
		"state": "選択中",
		"locked_state": "未購入 · 端末ストアで購入",
		"description": "ハート6 · 移速 -15% · ダメージ +25% · ダッシュCD +30% · 月光の波紋・不屈の命",
	},
	"zh_CN": {
		"name": "烽火守护者",
		"state": "已选择",
		"locked_state": "未购买 · 在设备商店购买",
		"description": "6颗心 · 移速 -15% · 伤害 +25% · 冲刺冷却 +30% · 月光波纹·坚韧生命",
	},
	"zh_TW": {
		"name": "烽火守護者",
		"state": "已選擇",
		"locked_state": "未購買 · 在裝置商店購買",
		"description": "6顆心 · 移速 -15% · 傷害 +25% · 衝刺冷卻 +30% · 月光波紋·堅韌生命",
	},
}

@onready var _shrine: Control = $ShrinePanel

var _failed: int = 0
var _checked: int = 0


func _ready() -> void:
	# Headless runner can inherit a portrait-sized root window even though the game
	# contract is 808x360 landscape. Pin the test viewport before measuring controls.
	get_tree().root.size = Vector2i(808, 360)
	get_tree().root.content_scale_size = Vector2i(808, 360)
	_shrine.open()
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_layout_bounds()
	var heroes: HBoxContainer = _heroes()
	_expect_true(heroes != null, "shrine hero-card scroll row")
	if heroes != null:
		_expect_equal(heroes.get_child_count(), HERO_IDS.size(), "six shrine hero cards")
		for index in mini(heroes.get_child_count(), HERO_IDS.size()):
			_test_card_preview(
				heroes.get_child(index) as Control,
				HERO_IDS[index],
				HERO_PATHS[index])
		_test_whole_card_tap(heroes)
		await _test_purchase_then_separate_select()
		await _test_keeper_screen_touch_select()
		_test_back_closes_preview_first()
		await _test_capture_visual_guards()
	_finish()


func _test_layout_bounds() -> void:
	var original_locale: String = TranslationServer.get_locale()
	var viewport_height: float = _shrine.get_viewport_rect().size.y
	var frame: Control = _shrine.get_node("Frame") as Control
	var title: Label = _shrine.get_node("Frame/Margin/Rows/Header/Title") as Label
	var close: Button = _shrine.get_node("Frame/Margin/Rows/Footer/Close") as Button
	for locale in UI_LOCALES:
		TranslationServer.set_locale(locale)
		_shrine.call("_rebuild")
		await get_tree().process_frame
		await get_tree().process_frame
		var frame_rect: Rect2 = frame.get_global_rect()
		var title_rect: Rect2 = title.get_global_rect()
		var close_rect: Rect2 = close.get_global_rect()
		_expect_true(
			frame_rect.position.y >= SAFE_INSET,
			"%s shrine frame top safe margin" % locale)
		_expect_true(
			frame_rect.end.y <= viewport_height - SAFE_INSET,
			"%s shrine frame bottom safe margin" % locale)
		_expect_true(
			title_rect.position.y >= SAFE_INSET,
			"%s shrine title top safe margin" % locale)
		_expect_true(
			close_rect.end.y <= viewport_height - SAFE_INSET,
			"%s shrine close-button bottom safe margin" % locale)
		_expect_true(
			not tr(title.text).is_empty() and tr(title.text) != "SHRINE_TITLE",
			"%s shrine title translation" % locale)
		_expect_true(
			not tr(close.text).is_empty() and tr(close.text) != "SETTINGS_CLOSE",
			"%s shrine close translation" % locale)
		var heroes: HBoxContainer = _heroes()
		for card in heroes.get_children():
			var description: Label = card.get_node("Body/Copy/Description") as Label
			_expect_true(
				description.get_line_count() <= description.max_lines_visible,
				"%s %s hero description not ellipsized" % [locale, card.name])
	TranslationServer.set_locale(original_locale)
	_shrine.call("_rebuild")
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll: ScrollContainer = _shrine.get_node(
		"Frame/Margin/Rows/HeroesScroll") as ScrollContainer
	var heroes: HBoxContainer = _heroes()
	_expect_true(
		heroes.size.x > scroll.size.x,
		"six hero cards continue off viewport so they can scroll horizontally")
	scroll.scroll_horizontal = 100_000
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(scroll.scroll_horizontal > 0, "shrine actually scrolls to heroes 4–6")
	var last_card: Control = heroes.get_child(heroes.get_child_count() - 1) as Control
	_expect_true(
		scroll.get_global_rect().intersects(last_card.get_global_rect()),
		"6th hero visible at the end of shrine scroll")
	_shrine.close()
	_shrine.open()
	await get_tree().process_frame
	_expect_equal(scroll.scroll_horizontal, 0, "re-entering the shrine starts at Warden")


func _heroes() -> HBoxContainer:
	return _shrine.get_node(
		"Frame/Margin/Rows/HeroesScroll/Heroes") as HBoxContainer


func _test_card_preview(card: Control, hero_id: String, path: String) -> void:
	_expect_true(card != null, "%s shrine card" % hero_id)
	if card == null:
		return
	_expect_equal(
		card.mouse_filter,
		Control.MOUSE_FILTER_PASS,
		"%s card-body swipe reaches ScrollContainer" % hero_id)
	var hero: Hero = load(path) as Hero
	var portrait: TextureButton = card.get_node("Body/Portrait") as TextureButton
	_expect_true(portrait != null, "%s shrine portrait button" % hero_id)
	if portrait == null or hero == null:
		return
	_expect_equal(
		portrait.custom_minimum_size,
		Vector2(48, 48),
		"%s shrine portrait button 48x48" % hero_id)
	_expect_true(not portrait.disabled, "%s preview button independent of lock" % hero_id)
	_expect_true(portrait.texture_normal != null, "%s shrine portrait texture" % hero_id)
	# Hang a 24×24 crop at 2× in a 48 cell. A 96×96 portrait shrinks to 0.5× and smears.
	var card_icon: AtlasTexture = portrait.texture_normal as AtlasTexture
	_expect_true(card_icon != null, "%s shrine portrait AtlasTexture" % hero_id)
	if card_icon != null:
		_expect_equal(card_icon.region, Rect2(12, 32, 24, 24), "%s shrine portrait crop" % hero_id)
		if card_icon.atlas != null:
			_expect_equal(
				card_icon.atlas.resource_path,
				"res://assets/custom/actors/heroes/%s/idle.png" % hero_id,
				"%s shrine portrait path" % hero_id)

	var before_shards: int = Vault.shards
	var before_opened: Array[String] = Vault.opened.duplicate()
	var before_chosen: String = Vault.chosen
	portrait.emit_signal(&"pressed")
	var preview: HeroPreviewPanel = _shrine.get_node("HeroPreview") as HeroPreviewPanel
	_expect_true(preview.is_open(), "%s portrait tap opens detail" % hero_id)
	_expect_equal(preview.current_hero_path(), path, "%s detail hero path" % hero_id)
	_expect_equal(preview.icon_frame_count(), 4, "%s down idle four frames" % hero_id)
	_expect_equal(
		preview.mouse_filter,
		Control.MOUSE_FILTER_STOP,
		"%s detail blocks lower input" % hero_id)

	# Both pictures use an integer scale of their source size. In the large cell hang a 96×96 portrait
	# 1:1, and hang a 24×24 crop at 2× in the small cell. Shrinking to 0.5× or stretching to 4×
	# smears pixels only there.
	var body: TextureRect = preview.get_node(
		"Frame/Margin/Rows/Content/BodyStage/Center/Body") as TextureRect
	_expect_equal(body.custom_minimum_size, Vector2(96, 96), "%s full-body cell 96x96" % hero_id)
	_expect_equal(
		body.texture_filter,
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"%s full-body Nearest filter" % hero_id)
	_expect_true(body.texture != null, "%s full-body texture" % hero_id)
	if body.texture != null:
		_expect_equal(
			body.texture.resource_path,
			"res://assets/custom/actors/heroes/%s/portrait.png" % hero_id,
			"%s full-body portrait path" % hero_id)
		_expect_equal(
			Vector2i(body.texture.get_size()),
			Vector2i(96, 96),
			"%s full-body portrait 1:1" % hero_id)

	var icon: TextureRect = preview.get_node(
		"Frame/Margin/Rows/Header/Portrait") as TextureRect
	_expect_equal(icon.custom_minimum_size, Vector2(48, 48), "%s icon cell 48x48" % hero_id)
	_expect_equal(
		icon.texture_filter,
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"%s icon Nearest filter" % hero_id)
	var atlas: AtlasTexture = icon.texture as AtlasTexture
	_expect_true(atlas != null, "%s icon first-frame AtlasTexture" % hero_id)
	if atlas != null:
		_expect_true(atlas.atlas != null, "%s icon idle atlas" % hero_id)
		if atlas.atlas != null:
			_expect_equal(
				atlas.atlas.resource_path,
				"res://assets/custom/actors/heroes/%s/idle.png" % hero_id,
				"%s icon idle path" % hero_id)
		_expect_equal(atlas.region, Rect2(12, 32, 24, 24), "%s down first-frame 2-head crop" % hero_id)
	var timer: Timer = preview.get_node("AnimationTimer") as Timer
	_expect_true(not timer.is_stopped(), "%s icon idle animation playing" % hero_id)
	preview.call("_advance_icon_frame")
	atlas = icon.texture as AtlasTexture
	if atlas != null:
		_expect_equal(atlas.region, Rect2(12, 96, 24, 24), "%s down second-frame 2-head crop" % hero_id)
	var description: Label = preview.get_node(
		"Frame/Margin/Rows/Content/Description") as Label
	var state: Label = preview.get_node(
		"Frame/Margin/Rows/Header/Copy/State") as Label
	_expect_equal(description.text, tr(hero.description), "%s full description" % hero_id)
	_expect_equal(description.max_lines_visible, -1, "%s description has no line-count cap" % hero_id)
	if path in Vault.PAID_HEROES and not Vault.hero_open(path):
		_expect_equal(
			state.text,
			tr("HERO_PREVIEW_IAP_LOCKED"),
			"%s does not treat a paid hero as a shard unlock" % hero_id)
	_expect_equal(Vault.shards, before_shards, "%s shards unchanged after preview" % hero_id)
	_expect_equal(Vault.opened, before_opened, "%s unlock unchanged after preview" % hero_id)
	_expect_equal(Vault.chosen, before_chosen, "%s selection unchanged after preview" % hero_id)
	preview.get_node("Frame/Margin/Rows/Footer/Close").emit_signal(&"pressed")
	_expect_true(not preview.is_open(), "%s detail close" % hero_id)
	_expect_true(timer.is_stopped(), "%s animation stops after detail close" % hero_id)


func _test_whole_card_tap(heroes: HBoxContainer) -> void:
	var keeper_card: Control = heroes.get_child(2) as Control
	var tap: InputEventMouseButton = InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	_expect_true(
		not _shrine.call("_should_open_card_preview", tap, true),
		"synthetic mobile mouse press does not open card preview")
	_expect_true(
		_shrine.call("_should_open_card_preview", tap, false),
		"desktop real mouse press opens card preview")
	keeper_card.emit_signal(&"gui_input", tap)
	var preview: HeroPreviewPanel = _shrine.get_node("HeroPreview") as HeroPreviewPanel
	_expect_true(preview.is_open(), "tapping card body opens detail")
	_expect_equal(preview.current_hero_path(), HERO_PATHS[2], "card-tap hero matches")
	preview.close_preview()


func _test_purchase_then_separate_select() -> void:
	var heroes: HBoxContainer = _heroes()
	var goal: Label = _shrine.get_node("Frame/Margin/Rows/Header/Goal") as Label
	var warden_action: Button = heroes.get_child(0).get_node(
		"Body/Copy/Footer/Action") as Button
	var dancer_action: Button = heroes.get_child(1).get_node(
		"Body/Copy/Footer/Action") as Button
	var keeper_action: Button = heroes.get_child(2).get_node(
		"Body/Copy/Footer/Action") as Button
	_expect_true(warden_action.disabled, "button disabled while default Warden is selected")
	_expect_equal(warden_action.text, tr("SHRINE_SELECTED"), "shown while default Warden is selected")
	_expect_true(dancer_action.disabled, "Dancer IAP disabled when the store is disconnected")
	_expect_true(keeper_action.disabled, "Keeper IAP disabled when the store is disconnected")
	_expect_equal(dancer_action.text, tr("IAP_BUY"), "Dancer individual IAP CTA")
	_expect_equal(keeper_action.text, tr("IAP_BUY"), "Keeper individual IAP CTA")

	var dancer: Hero = load(HERO_PATHS[1]) as Hero
	Vault.shards = dancer.unlock_cost * 10
	_shrine.call("_rebuild")
	heroes = _heroes()
	dancer_action = heroes.get_child(1).get_node("Body/Copy/Footer/Action") as Button
	_expect_true(dancer_action.disabled, "even with many shards only Dancer IAP is allowed")
	_expect_true(not Vault.hero_open(HERO_PATHS[1]), "shards alone do not unlock Dancer")
	var dancer_only: Array[String] = [HERO_PATHS[1]]
	_expect_true(
		Vault.grant_heroes(dancer_only, Vault.HERO_SOURCE_SHARDS),
		"previous-version Dancer shard unlock is kept")
	_expect_equal(Vault.hero_path(), HERO_PATHS[0], "grandfather unlock alone does not change the current hero")

	_shrine.call("_rebuild")
	heroes = _heroes()
	dancer_action = heroes.get_child(1).get_node("Body/Copy/Footer/Action") as Button
	_expect_equal(dancer_action.text, tr("SHRINE_SELECT"), "separate select button after grandfather")
	_expect_true(not dancer_action.disabled, "grandfather Dancer select enabled")
	dancer_action.emit_signal(&"pressed")
	_expect_equal(Vault.hero_path(), HERO_PATHS[1], "Dancer equipped after a separate select")
	var selected_feedback: String = tr("SHRINE_HERO_SELECTED") % tr(dancer.display_name)
	_expect_equal(goal.text, selected_feedback, "shows the select result on the goal line")
	await get_tree().create_timer(0.32, true).timeout
	await get_tree().create_timer(1.2, true).timeout
	_expect_true(goal.text != selected_feedback, "buy goal restored after a temporary result")


## A real Android tap is ScreenTouch press/release. If the card takes press first and opens detail,
## the child Button never gets release and cannot select Keeper.
func _test_keeper_screen_touch_select() -> void:
	var paid_heroes: Array[String] = [HERO_PATHS[1], HERO_PATHS[2]]
	_expect_true(
		Vault.grant_heroes(paid_heroes, Vault.HERO_SOURCE_IAP_BUNDLE),
		"grants a paid hero for the ScreenTouch regression")
	_shrine.call("_rebuild")
	await get_tree().process_frame
	await get_tree().process_frame

	var heroes: HBoxContainer = _heroes()
	var keeper_action: Button = heroes.get_child(2).get_node(
		"Body/Copy/Footer/Action") as Button
	_expect_true(not keeper_action.disabled, "Keeper select-button ScreenTouch active")
	var preview: HeroPreviewPanel = _shrine.get_node("HeroPreview") as HeroPreviewPanel
	_expect_true(not preview.is_open(), "detail closes before Keeper ScreenTouch")

	var center: Vector2 = keeper_action.get_global_rect().get_center()
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = 0
	touch.position = center
	touch.pressed = true
	# Also pin the Android input path where a child Button's touch press is forwarded to the card.
	# If this one press opens detail, the later release never reaches the button.
	var keeper_card: Control = heroes.get_child(2) as Control
	keeper_card.emit_signal(&"gui_input", touch)
	_expect_true(not preview.is_open(), "Keeper button touch press does not open card detail")
	if preview.is_open():
		preview.close_preview()

	get_viewport().push_input(touch)
	await get_tree().process_frame
	touch = touch.duplicate() as InputEventScreenTouch
	touch.pressed = false
	get_viewport().push_input(touch)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect_equal(Vault.hero_path(), HERO_PATHS[2], "Keeper button actual ScreenTouch select")
	_expect_true(not preview.is_open(), "Keeper select ScreenTouch does not open detail")
	await get_tree().create_timer(0.32, true).timeout
	await get_tree().create_timer(1.2, true).timeout


func _test_back_closes_preview_first() -> void:
	var heroes: HBoxContainer = _heroes()
	var dancer_portrait: TextureButton = heroes.get_child(1).get_node(
		"Body/Portrait") as TextureButton
	dancer_portrait.emit_signal(&"pressed")
	var preview: HeroPreviewPanel = _shrine.get_node("HeroPreview") as HeroPreviewPanel
	var close_count: Array[int] = [0]
	_shrine.closed.connect(func() -> void: close_count[0] += 1)
	_shrine.close()
	_expect_true(not preview.is_open(), "Android back closes detail first")
	_expect_true(_shrine.visible, "shrine kept after detail back")
	_expect_equal(close_count[0], 0, "detail back does not emit shrine closed")
	_shrine.close()
	_expect_true(not _shrine.visible, "next back closes the shrine")
	_expect_equal(close_count[0], 1, "shrine close emitted once")


func _test_capture_visual_guards() -> void:
	_shrine.open()
	await get_tree().create_timer(0.28).timeout
	var shrine_request: Dictionary = {"kind": "shrine"}
	_shrine.call("debug_prepare_store_capture", shrine_request)
	await get_tree().process_frame
	await get_tree().process_frame
	# The dummy headless renderer has no draw counter, so model the previous draw serial.
	_shrine.set("_opened_draw_frame", -1)
	var state: Dictionary = _shrine.call(
		"debug_store_capture_state", shrine_request)
	_expect_equal(
		state.get("hero_cards_visible_rect_count"),
		HERO_PATHS.size(),
		"05 capture six hero cards actually intersect viewport")
	_expect_true(bool(state.get("ready", false)), "05 shrine capture ready")

	var first_card: Control = _heroes().get_child(0) as Control
	var original_position: Vector2 = first_card.position
	first_card.position += Vector2(3000.0, 0.0)
	state = _shrine.call("debug_store_capture_state", shrine_request)
	_expect_equal(
		state.get("hero_cards_visible_rect_count"),
		HERO_PATHS.size() - 1,
		"off-screen shrine cards are not counted among the visible six")
	_expect_true(not bool(state.get("ready", true)), "rejects off-screen shrine-card ready")
	first_card.position = original_position
	var original_card_modulate: Color = first_card.modulate
	first_card.modulate.a = 0.0
	state = _shrine.call("debug_store_capture_state", shrine_request)
	_expect_equal(
		state.get("hero_cards_visible_rect_count"),
		HERO_PATHS.size() - 1,
		"transparent shrine cards are not counted among the visible six")
	_expect_true(not bool(state.get("ready", true)), "rejects ready for a transparent shrine card")
	first_card.modulate = original_card_modulate

	var preview_request: Dictionary = {
		"kind": "hero_preview",
		"hero_path": HERO_PATHS[2],
	}
	_shrine.call("debug_prepare_store_capture", preview_request)
	await get_tree().create_timer(0.2).timeout
	await get_tree().process_frame
	var preview_for_draw: HeroPreviewPanel = _shrine.get_node(
		"HeroPreview") as HeroPreviewPanel
	preview_for_draw.set("_opened_draw_frame", -1)
	state = _shrine.call("debug_store_capture_state", preview_request)
	for field in [
		"portrait_texture_ready", "portrait_visible_rect_ready", "portrait_opaque",
		"body_texture_ready", "body_visible_rect_ready", "body_opaque",
		"close_inside_viewport", "close_opaque",
	]:
		_expect_true(bool(state.get(field, false)), "06 hero detail " + field)
	_expect_equal(
		state.get("portrait_resource_path"),
		"res://assets/custom/actors/heroes/keeper/idle.png",
		"06 Keeper actual portrait resource")
	_expect_equal(
		state.get("portrait_expected_resource_path"),
		"res://assets/custom/actors/heroes/keeper/idle.png",
		"06 Keeper independent expected portrait resource")
	_expect_equal(
		state.get("body_resource_path"),
		"res://assets/custom/actors/heroes/keeper/portrait.png",
		"06 Keeper actual full-body resource")
	_expect_equal(
		state.get("body_expected_resource_path"),
		"res://assets/custom/actors/heroes/keeper/portrait.png",
		"06 Keeper independent expected full-body resource")
	for field in [
		"name_source_matches", "name_copy_valid", "name_text_nonempty",
		"name_characters_visible", "name_font_size_positive",
		"name_font_alpha_readable", "name_visible_rect_ready", "name_opaque",
		"name_rendered_text_ready",
		"state_source_matches", "state_copy_valid", "state_text_nonempty",
		"state_characters_visible", "state_font_size_positive",
		"state_font_alpha_readable", "state_visible_rect_ready", "state_opaque",
		"state_rendered_text_ready",
		"description_source_matches", "description_copy_valid",
		"description_text_nonempty", "description_characters_visible",
		"description_font_size_positive", "description_font_alpha_readable",
		"description_visible_rect_ready", "description_opaque",
		"description_rendered_text_ready",
	]:
		_expect_true(bool(state.get(field, false)), "06 hero detail " + field)
	_expect_true(bool(state.get("ready", false)), "06 hero-detail capture ready")

	var preview: HeroPreviewPanel = _shrine.get_node("HeroPreview") as HeroPreviewPanel
	var original_locale: String = TranslationServer.get_locale()
	for locale in UI_LOCALES:
		TranslationServer.set_locale(locale)
		preview.call("_refresh_copy")
		await get_tree().process_frame
		await get_tree().process_frame
		state = preview.debug_store_capture_state(HERO_PATHS[2])
		var expected_copy: Dictionary = KEEPER_EXPECTED_COPY[locale] as Dictionary
		_expect_equal(state.get("copy_locale"), locale, locale + " Keeper capture locale")
		_expect_equal(
			state.get("name_source_key"),
			"HERO_KEEPER_NAME",
			locale + " Keeper name original key")
		_expect_equal(
			state.get("name_expected_source_key"),
			"HERO_KEEPER_NAME",
			locale + " Keeper name independent expected key")
		_expect_equal(
			state.get("name_text"),
			expected_copy["name"],
			locale + " Keeper actual name")
		_expect_equal(
			state.get("name_expected_text"),
			expected_copy["name"],
			locale + " Keeper independent expected name")
		_expect_equal(
			state.get("state_source_key"),
			"SHRINE_SELECTED",
			locale + " Keeper select-state original key")
		_expect_equal(
			state.get("state_expected_source_key"),
			"SHRINE_SELECTED",
			locale + " Keeper select-state independent expected key")
		_expect_equal(
			state.get("state_text"),
			expected_copy["state"],
			locale + " Keeper actual select state")
		_expect_equal(
			state.get("state_expected_text"),
			expected_copy["state"],
			locale + " Keeper independent expected select state")
		_expect_equal(
			state.get("description_source_key"),
			"HERO_KEEPER_DESC",
			locale + " Keeper description original key")
		_expect_equal(
			state.get("description_expected_source_key"),
			"HERO_KEEPER_DESC",
			locale + " Keeper description independent expected key")
		_expect_equal(
			state.get("description_text"),
			expected_copy["description"],
			locale + " Keeper actual description")
		_expect_equal(
			state.get("description_expected_text"),
			expected_copy["description"],
			locale + " Keeper independent expected description")
		for field in [
			"name_rendered_text_ready", "state_rendered_text_ready",
			"description_rendered_text_ready",
			"preview_visible", "portrait_visible",
			"portrait_texture_ready", "portrait_visible_rect_ready", "portrait_opaque",
			"body_visible", "body_texture_ready", "body_visible_rect_ready", "body_opaque",
			"close_visible", "close_inside_viewport", "close_opaque", "preview_opaque",
			"preview_frame_inside_viewport", "preview_drawn_after_open", "ready",
		]:
			_expect_true(bool(state.get(field, false)), locale + " Keeper " + field)
	var opened_before_locked_copy: Array[String] = Vault.opened.duplicate()
	var chosen_before_locked_copy: String = Vault.chosen
	Vault.opened.erase(HERO_PATHS[2])
	Vault.chosen = ""
	for locale in UI_LOCALES:
		TranslationServer.set_locale(locale)
		preview.call("_refresh_copy")
		await get_tree().process_frame
		await get_tree().process_frame
		state = preview.debug_store_capture_state(HERO_PATHS[2])
		var expected_copy: Dictionary = KEEPER_EXPECTED_COPY[locale] as Dictionary
		_expect_equal(
			state.get("state_source_key"),
			"HERO_PREVIEW_IAP_LOCKED",
			locale + " fresh-install Keeper lock original key")
		_expect_equal(
			state.get("state_expected_source_key"),
			"HERO_PREVIEW_IAP_LOCKED",
			locale + " fresh-install Keeper lock independent expected key")
		_expect_equal(
			state.get("state_text"),
			expected_copy["locked_state"],
			locale + " fresh-install Keeper lock actual copy")
		_expect_equal(
			state.get("state_expected_text"),
			expected_copy["locked_state"],
			locale + " fresh-install Keeper lock independent expected copy")
		_expect_true(
			bool(state.get("state_rendered_text_ready", false)),
			locale + " fresh-install Keeper lock render")
		_expect_true(bool(state.get("ready", false)), locale + " fresh-install Keeper capture ready")
	Vault.opened = opened_before_locked_copy
	Vault.chosen = chosen_before_locked_copy
	TranslationServer.set_locale(original_locale)
	preview.call("_refresh_copy")
	await get_tree().process_frame
	await get_tree().process_frame

	var portrait: TextureRect = preview.get_node(
		"Frame/Margin/Rows/Header/Portrait") as TextureRect
	var original_portrait_texture: Texture2D = portrait.texture
	portrait.texture = load(
		"res://assets/custom/actors/heroes/warden/portrait.png") as Texture2D
	state = _shrine.call("debug_store_capture_state", preview_request)
	_expect_equal(
		state.get("portrait_resource_path"),
		"res://assets/custom/actors/heroes/warden/portrait.png",
		"reproduces the counterexample of swapping another hero's live portrait")
	_expect_equal(
		state.get("portrait_expected_resource_path"),
		"res://assets/custom/actors/heroes/keeper/idle.png",
		"Keeper expected values stay unchanged after a portrait swap")
	_expect_true(
		not bool(state.get("portrait_resource_matches", true)),
		"rejects swapping in another hero's live portrait resource")
	_expect_true(not bool(state.get("ready", true)), "rejects ready after swapping a portrait resource")
	portrait.texture = original_portrait_texture

	var original_portrait_modulate: Color = portrait.modulate
	portrait.modulate.a = 0.0
	state = _shrine.call("debug_store_capture_state", preview_request)
	_expect_true(not bool(state.get("portrait_opaque", true)), "rejects a transparent detail portrait")
	_expect_true(not bool(state.get("ready", true)), "rejects ready for a transparent detail portrait")
	portrait.modulate = original_portrait_modulate

	var frame: Control = preview.get_node("Frame") as Control
	var original_frame_position: Vector2 = frame.position
	frame.position += Vector2(3000.0, 0.0)
	state = _shrine.call("debug_store_capture_state", preview_request)
	_expect_true(
		not bool(state.get("portrait_visible_rect_ready", true)),
		"rejects an off-screen detail-portrait visible region")
	_expect_true(not bool(state.get("ready", true)), "rejects off-screen detail ready")
	frame.position = original_frame_position

	var body: TextureRect = preview.get_node(
		"Frame/Margin/Rows/Content/BodyStage/Center/Body") as TextureRect
	var original_body_texture: Texture2D = body.texture
	var swapped_body: AtlasTexture = AtlasTexture.new()
	swapped_body.atlas = load(
		"res://assets/custom/actors/heroes/dancer/idle.png") as Texture2D
	swapped_body.region = Rect2(12, 32, 24, 24)
	body.texture = swapped_body
	state = _shrine.call("debug_store_capture_state", preview_request)
	_expect_equal(
		state.get("body_resource_path"),
		"res://assets/custom/actors/heroes/dancer/idle.png",
		"reproduces the counterexample of swapping another hero's live full-body")
	_expect_equal(
		state.get("body_expected_resource_path"),
		"res://assets/custom/actors/heroes/keeper/portrait.png",
		"Keeper expected values stay unchanged after a full-body swap")
	_expect_true(
		not bool(state.get("body_resource_matches", true)),
		"rejects swapping in another hero's live full-body resource")
	_expect_true(not bool(state.get("ready", true)), "rejects ready after swapping a full-body resource")
	body.texture = original_body_texture

	body.texture = null
	state = _shrine.call("debug_store_capture_state", preview_request)
	_expect_true(not bool(state.get("body_texture_ready", true)), "rejects an empty detail full-body texture")
	_expect_true(not bool(state.get("ready", true)), "rejects ready for an empty detail full-body")
	body.texture = original_body_texture

	var name_label: Label = preview.get_node(
		"Frame/Margin/Rows/Header/Copy/Name") as Label
	var state_label: Label = preview.get_node(
		"Frame/Margin/Rows/Header/Copy/State") as Label
	var description_label: Label = preview.get_node(
		"Frame/Margin/Rows/Content/Description") as Label
	var text_labels: Array[Label] = [name_label, state_label, description_label]
	var text_prefixes: Array[String] = ["name", "state", "description"]
	for index in text_labels.size():
		var label: Label = text_labels[index]
		var prefix: String = text_prefixes[index]
		var original_text: String = label.text
		label.text = "wrong detail copy"
		state = _shrine.call("debug_store_capture_state", preview_request)
		_expect_true(
			not bool(state.get(prefix + "_copy_valid", true)),
			prefix + " rejects wrong detail copy")
		_expect_true(
			not bool(state.get(prefix + "_rendered_text_ready", true)),
			prefix + " rejects ready for wrong rendered detail copy")
		_expect_true(not bool(state.get("ready", true)), prefix + " rejects ready for wrong copy")
		label.text = ""
		state = _shrine.call("debug_store_capture_state", preview_request)
		_expect_true(
			not bool(state.get(prefix + "_text_nonempty", true)),
			prefix + " rejects empty detail copy")
		_expect_true(not bool(state.get("ready", true)), prefix + " rejects ready for empty copy")
		label.text = original_text

		var original_ratio: float = label.visible_ratio
		label.visible_ratio = 0.0
		state = _shrine.call("debug_store_capture_state", preview_request)
		_expect_true(
			not bool(state.get(prefix + "_characters_visible", true)),
			prefix + " rejects hidden detail glyphs")
		_expect_true(not bool(state.get("ready", true)), prefix + " rejects ready for hidden glyphs")
		label.visible_ratio = original_ratio

		var original_font_color: Color = label.get_theme_color("font_color")
		label.add_theme_color_override(
			"font_color",
			Color(original_font_color.r, original_font_color.g, original_font_color.b, 0.0))
		state = _shrine.call("debug_store_capture_state", preview_request)
		_expect_true(
			not bool(state.get(prefix + "_font_alpha_readable", true)),
			prefix + " rejects transparent detail glyphs")
		_expect_true(not bool(state.get("ready", true)), prefix + " rejects ready for transparent glyphs")
		label.add_theme_color_override("font_color", original_font_color)

		var label_original_position: Vector2 = label.position
		label.position += Vector2(3000.0, 0.0)
		state = _shrine.call("debug_store_capture_state", preview_request)
		_expect_true(
			not bool(state.get(prefix + "_visible_rect_ready", true)),
			prefix + " rejects off-screen detail glyphs")
		_expect_true(not bool(state.get("ready", true)), prefix + " rejects ready for off-screen glyphs")
		label.position = label_original_position

	var keeper: Hero = load(HERO_PATHS[2]) as Hero
	var original_name_source: String = keeper.display_name
	keeper.display_name = "HERO_WARDEN_NAME"
	state = _shrine.call("debug_store_capture_state", preview_request)
	_expect_true(not bool(state.get("name_source_matches", true)), "rejects swapped Keeper name original key")
	_expect_true(not bool(state.get("ready", true)), "rejects ready after swapping Keeper name original key")
	keeper.display_name = original_name_source
	var original_description_source: String = keeper.description
	keeper.description = "HERO_WARDEN_DESC"
	state = _shrine.call("debug_store_capture_state", preview_request)
	_expect_true(
		not bool(state.get("description_source_matches", true)),
		"rejects swapped Keeper description original key")
	_expect_true(not bool(state.get("ready", true)), "rejects ready after swapping Keeper description original key")
	keeper.description = original_description_source
	var original_state_source: String = str(preview.get("_state_source_key"))
	preview.set("_state_source_key", "SHRINE_OWNED")
	state = _shrine.call("debug_store_capture_state", preview_request)
	_expect_true(not bool(state.get("state_source_matches", true)), "rejects swapped Keeper state original key")
	_expect_true(not bool(state.get("ready", true)), "rejects ready after swapping Keeper state original key")
	preview.set("_state_source_key", original_state_source)


func _finish() -> void:
	if _failed > 0:
		printerr("shrine hero-preview test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("shrine hero-preview test passed — ", _checked, " case(s)")
	get_tree().quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)
