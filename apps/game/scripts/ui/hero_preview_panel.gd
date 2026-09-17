class_name HeroPreviewPanel
extends Control

## Read-only full-body preview, separate from hero buy/select.
##
## Reads only the current Hero resource and writes nothing to Vault or
## IapStore. Shrine shard unlocks and shop device purchases happen only on
## each parent panel's existing buttons.

signal closed

const MUTED: Color = Color(0.62, 0.69, 0.82, 1.0)
const SUCCESS: Color = Color(0.64, 1.0, 0.75, 1.0)
const LOCKED: Color = Color(1.0, 0.72, 0.5, 1.0)
const CAPTURE_TEXT_READABLE_ALPHA: float = 0.35
const CAPTURE_DRAW_FRAME_UNSET: int = -2
## Pin the 06 store shot's advertised subject and real assets independently of
## the Hero resource. Re-read `_hero.portrait` as expected and a resource swap
## moves actual and expected together, so the capture gate false-passes.
const CAPTURE_HERO_VISUAL_BY_PATH: Dictionary = {
	"res://resources/heroes/keeper.tres": {
		"portrait": "res://assets/custom/actors/heroes/keeper/idle.png",
		"body": "res://assets/custom/actors/heroes/keeper/portrait.png",
	},
}
## Do not re-read the translation CSV or current Label.text as expected. Pin
## the Keeper copy advertised in the 06 capture as a shipping contract, so a
## change in key, translation, or render fails before the real shot.
const CAPTURE_KEEPER_COPY_BY_LOCALE: Dictionary = {
	"ko": {
		"name": "봉화지기",
		"description": "하트 6칸 · 이속 -15% · 피해 +25% · 대시 쿨 +30% · 달빛 파문·질긴 목숨",
		"SHRINE_SELECTED": "선택 중",
		"SHRINE_OWNED": "해금됨",
		"HERO_PREVIEW_IAP_LOCKED": "잠김 · 기기 스토어에서 구매",
	},
	"en": {
		"name": "Beacon Keeper",
		"description": "6 hearts · move -15% · dmg +25% · dash CD +30% · Moonlit Ripple/Tenacious Life",
		"SHRINE_SELECTED": "Selected",
		"SHRINE_OWNED": "Unlocked",
		"HERO_PREVIEW_IAP_LOCKED": "Locked · purchase in device store",
	},
	"ja": {
		"name": "烽火の守り人",
		"description": "ハート6 · 移速 -15% · ダメージ +25% · ダッシュCD +30% · 月光の波紋・不屈の命",
		"SHRINE_SELECTED": "選択中",
		"SHRINE_OWNED": "解放済み",
		"HERO_PREVIEW_IAP_LOCKED": "未購入 · 端末ストアで購入",
	},
	"zh_CN": {
		"name": "烽火守护者",
		"description": "6颗心 · 移速 -15% · 伤害 +25% · 冲刺冷却 +30% · 月光波纹·坚韧生命",
		"SHRINE_SELECTED": "已选择",
		"SHRINE_OWNED": "已解锁",
		"HERO_PREVIEW_IAP_LOCKED": "未购买 · 在设备商店购买",
	},
	"zh_TW": {
		"name": "烽火守護者",
		"description": "6顆心 · 移速 -15% · 傷害 +25% · 衝刺冷卻 +30% · 月光波紋·堅韌生命",
		"SHRINE_SELECTED": "已選擇",
		"SHRINE_OWNED": "已解鎖",
		"HERO_PREVIEW_IAP_LOCKED": "未購買 · 在裝置商店購買",
	},
}
## Name of how each profile's shot flies. Read with the trail drawing.
const MOTION_NAME_KEYS: Dictionary = {
	Hero.AttackProfile.WARDEN: "HERO_MOTION_ROUND",
	Hero.AttackProfile.DANCER: "HERO_MOTION_WEAVE",
	Hero.AttackProfile.KEEPER: "HERO_MOTION_HEAVY",
	Hero.AttackProfile.KNIGHT: "HERO_MOTION_STRAIGHT",
	Hero.AttackProfile.ECLIPSE: "HERO_MOTION_ORBIT",
	Hero.AttackProfile.SAGE: "HERO_MOTION_STEP",
}

const CAPTURE_KEEPER_PATH: String = "res://resources/heroes/keeper.tres"
const CAPTURE_KEEPER_NAME_KEY: String = "HERO_KEEPER_NAME"
const CAPTURE_KEEPER_DESCRIPTION_KEY: String = "HERO_KEEPER_DESC"

@onready var _frame: PanelContainer = $Frame
@onready var _portrait: TextureRect = $Frame/Margin/Rows/Header/Portrait
@onready var _name: Label = $Frame/Margin/Rows/Header/Copy/Name
@onready var _state: Label = $Frame/Margin/Rows/Header/Copy/State
@onready var _body: TextureRect = $Frame/Margin/Rows/Content/BodyStage/Center/Body
@onready var _description: Label = $Frame/Margin/Rows/Content/Description
@onready var _close: Button = $Frame/Margin/Rows/Footer/Close
@onready var _motion_name: Label = $Frame/Margin/Rows/MotionStage/MotionRows/MotionName
@onready var _motion_track: Control = \
	$Frame/Margin/Rows/MotionStage/MotionRows/MotionTrack
@onready var _timer: Timer = $AnimationTimer

var _hero: Hero = null
var _hero_path: String = ""
var _icon_frames: Array[Texture2D] = []
var _icon_frame: int = 0
var _fade: Tween = null
var _opened_draw_frame: int = CAPTURE_DRAW_FRAME_UNSET
var _state_source_key: String = ""


func _ready() -> void:
	visible = false
	_close.pressed.connect(close_preview)
	_timer.timeout.connect(_advance_icon_frame)
	Vault.changed.connect(_on_vault_changed)


func open_hero(hero: Hero, path: String) -> void:
	if hero == null or path not in Vault.HEROES:
		return
	_hero = hero
	_hero_path = path
	_build_icon_frames()
	_refresh_copy()
	_refresh_motion()
	visible = true
	modulate.a = 0.0
	_opened_draw_frame = Engine.get_frames_drawn()
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.14)
	if _icon_frames.size() > 1:
		_timer.wait_time = 1.0 / maxf(hero.idle_fps, 1.0)
		_timer.start()
	else:
		_timer.stop()
	_close.grab_focus()


func close_preview() -> void:
	if not visible:
		return
	_timer.stop()
	_motion_track.stop()
	visible = false
	closed.emit()


## How this hero's shot flies. The only evidence you see before buying.
##
## The six heroes are a sidegrade with the same damage and fire rate, so the
## only reason to pick is feel, and a portrait cannot tell a pistol-straight
## shot from one that draws a wide circle. Show the name and the real trail
## together.
func _refresh_motion() -> void:
	if _hero == null:
		return
	_motion_name.text = tr(MOTION_NAME_KEYS.get(
		_hero.attack_profile, "HERO_MOTION_ROUND"))
	_motion_name.add_theme_color_override("font_color", _hero.accent)
	_motion_track.show_hero(_hero)


func is_open() -> bool:
	return visible


func current_hero_path() -> String:
	return _hero_path


func icon_frame_count() -> int:
	return _icon_frames.size()


func debug_store_capture_state(expected_path: String) -> Dictionary:
	if not OS.is_debug_build():
		return {}
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
	var preview_opaque: bool = modulate.a >= 0.99
	var drawn_after_open: bool = _opened_draw_frame != CAPTURE_DRAW_FRAME_UNSET \
		and Engine.get_frames_drawn() > _opened_draw_frame
	var portrait_path: String = _debug_source_path(_portrait.texture)
	var body_path: String = _debug_source_path(_body.texture)
	var expected_visual: Dictionary = CAPTURE_HERO_VISUAL_BY_PATH.get(
		expected_path, {}) as Dictionary
	var expected_portrait_path: String = str(expected_visual.get("portrait", ""))
	var expected_body_path: String = str(expected_visual.get("body", ""))
	var portrait_visible_rect_ready: bool = _debug_visible_rect_ready(
		_portrait, frame_rect, safe_rect)
	var body_visible_rect_ready: bool = _debug_visible_rect_ready(
		_body, frame_rect, safe_rect)
	var close_inside_viewport: bool = _debug_rect_fully_inside(
		_close.get_global_rect(), viewport_rect) and _close.is_visible_in_tree()
	var close_inside_safe_area: bool = _debug_rect_fully_inside(
		_close.get_global_rect(), safe_rect) and _close.is_visible_in_tree()
	var portrait_opaque: bool = _debug_effective_alpha(_portrait) >= 0.99
	var body_opaque: bool = _debug_effective_alpha(_body) >= 0.99
	var close_opaque: bool = _debug_effective_alpha(_close) >= 0.99
	var portrait_texture_ready: bool = not portrait_path.is_empty() \
		and not expected_portrait_path.is_empty() \
		and portrait_path == expected_portrait_path
	var body_texture_ready: bool = not body_path.is_empty() \
		and not expected_body_path.is_empty() \
		and body_path == expected_body_path
	var copy_locale: String = _debug_capture_locale()
	var expected_copy: Dictionary = CAPTURE_KEEPER_COPY_BY_LOCALE.get(
		copy_locale, {}) as Dictionary if expected_path == CAPTURE_KEEPER_PATH else {}
	var expected_state_source_key: String = _debug_expected_state_source_key(
		expected_path)
	var name_source_key: String = _hero.display_name if _hero != null else ""
	var description_source_key: String = _hero.description if _hero != null else ""
	var expected_name_text: String = str(expected_copy.get("name", ""))
	var expected_state_text: String = str(expected_copy.get(
		expected_state_source_key, ""))
	var expected_description_text: String = str(expected_copy.get(
		"description", ""))
	var name_copy_valid: bool = name_source_key == CAPTURE_KEEPER_NAME_KEY \
		and not expected_name_text.is_empty() and _name.text == expected_name_text
	var state_copy_valid: bool = _state_source_key == expected_state_source_key \
		and not expected_state_text.is_empty() and _state.text == expected_state_text
	var description_copy_valid: bool = description_source_key \
		== CAPTURE_KEEPER_DESCRIPTION_KEY \
		and not expected_description_text.is_empty() \
		and _description.text == expected_description_text
	var name_text_nonempty: bool = not _name.text.strip_edges().is_empty()
	var state_text_nonempty: bool = not _state.text.strip_edges().is_empty()
	var description_text_nonempty: bool = not _description.text.strip_edges().is_empty()
	var name_characters_visible: bool = _debug_label_characters_visible(_name)
	var state_characters_visible: bool = _debug_label_characters_visible(_state)
	var description_characters_visible: bool = _debug_label_characters_visible(
		_description)
	var name_font_size_positive: bool = _debug_font_size_positive(_name)
	var state_font_size_positive: bool = _debug_font_size_positive(_state)
	var description_font_size_positive: bool = _debug_font_size_positive(_description)
	var name_font_alpha_readable: bool = _debug_label_effective_font_alpha(
		_name) >= CAPTURE_TEXT_READABLE_ALPHA
	var state_font_alpha_readable: bool = _debug_label_effective_font_alpha(
		_state) >= CAPTURE_TEXT_READABLE_ALPHA
	var description_font_alpha_readable: bool = _debug_label_effective_font_alpha(
		_description) >= CAPTURE_TEXT_READABLE_ALPHA
	var name_visible_rect_ready: bool = _debug_label_visible_rect_ready(
		_name, frame_rect, safe_rect)
	var state_visible_rect_ready: bool = _debug_label_visible_rect_ready(
		_state, frame_rect, safe_rect)
	var description_visible_rect_ready: bool = _debug_label_visible_rect_ready(
		_description, frame_rect, safe_rect)
	var name_opaque: bool = _debug_effective_alpha(_name) >= 0.99
	var state_opaque: bool = _debug_effective_alpha(_state) >= 0.99
	var description_opaque: bool = _debug_effective_alpha(_description) >= 0.99
	var name_rendered_text_ready: bool = name_copy_valid and name_text_nonempty \
		and name_characters_visible and name_font_size_positive \
		and name_font_alpha_readable and name_visible_rect_ready and name_opaque
	var state_rendered_text_ready: bool = state_copy_valid and state_text_nonempty \
		and state_characters_visible and state_font_size_positive \
		and state_font_alpha_readable and state_visible_rect_ready and state_opaque
	var description_rendered_text_ready: bool = description_copy_valid \
		and description_text_nonempty and description_characters_visible \
		and description_font_size_positive and description_font_alpha_readable \
		and description_visible_rect_ready and description_opaque
	return {
		"preview_visible": visible and is_visible_in_tree(),
		"hero_path": _hero_path,
		"portrait_visible": _portrait.texture != null and _portrait.is_visible_in_tree(),
		"portrait_texture_ready": portrait_texture_ready,
		"portrait_resource_path": portrait_path,
		"portrait_expected_resource_path": expected_portrait_path,
		"portrait_resource_matches": portrait_texture_ready,
		"portrait_visible_rect_ready": portrait_visible_rect_ready,
		"portrait_opaque": portrait_opaque,
		"body_visible": _body.texture != null and _body.is_visible_in_tree(),
		"body_texture_ready": body_texture_ready,
		"body_resource_path": body_path,
		"body_expected_resource_path": expected_body_path,
		"body_resource_matches": body_texture_ready,
		"body_visible_rect_ready": body_visible_rect_ready,
		"body_opaque": body_opaque,
		"copy_locale": copy_locale,
		"name_source_key": name_source_key,
		"name_expected_source_key": CAPTURE_KEEPER_NAME_KEY,
		"name_source_matches": name_source_key == CAPTURE_KEEPER_NAME_KEY,
		"name_text": _name.text,
		"name_expected_text": expected_name_text,
		"name_copy_valid": name_copy_valid,
		"name_text_nonempty": name_text_nonempty,
		"name_characters_visible": name_characters_visible,
		"name_font_size_positive": name_font_size_positive,
		"name_font_alpha_readable": name_font_alpha_readable,
		"name_visible_rect_ready": name_visible_rect_ready,
		"name_opaque": name_opaque,
		"name_rendered_text_ready": name_rendered_text_ready,
		"state_source_key": _state_source_key,
		"state_expected_source_key": expected_state_source_key,
		"state_source_matches": _state_source_key == expected_state_source_key,
		"state_text": _state.text,
		"state_expected_text": expected_state_text,
		"state_copy_valid": state_copy_valid,
		"state_text_nonempty": state_text_nonempty,
		"state_characters_visible": state_characters_visible,
		"state_font_size_positive": state_font_size_positive,
		"state_font_alpha_readable": state_font_alpha_readable,
		"state_visible_rect_ready": state_visible_rect_ready,
		"state_opaque": state_opaque,
		"state_rendered_text_ready": state_rendered_text_ready,
		"description_source_key": description_source_key,
		"description_expected_source_key": CAPTURE_KEEPER_DESCRIPTION_KEY,
		"description_source_matches": description_source_key \
			== CAPTURE_KEEPER_DESCRIPTION_KEY,
		"description_text": _description.text,
		"description_expected_text": expected_description_text,
		"description_copy_valid": description_copy_valid,
		"description_text_nonempty": description_text_nonempty,
		"description_characters_visible": description_characters_visible,
		"description_font_size_positive": description_font_size_positive,
		"description_font_alpha_readable": description_font_alpha_readable,
		"description_visible_rect_ready": description_visible_rect_ready,
		"description_opaque": description_opaque,
		"description_rendered_text_ready": description_rendered_text_ready,
		"close_visible": _close.is_visible_in_tree(),
		"close_inside_viewport": close_inside_viewport,
		"close_inside_safe_area": close_inside_safe_area,
		"close_rect": _debug_rect_array(_close.get_global_rect()),
		"viewport_rect": _debug_rect_array(viewport_rect),
		"safe_rect": _debug_rect_array(safe_rect),
		"preview_frame_rect": _debug_rect_array(frame_rect),
		"safe_area_inside_viewport": _debug_rect_fully_inside(
			safe_rect, viewport_rect),
		"preview_frame_inside_safe_area": frame_inside_safe_area,
		"preview_safe_ui_ready": frame_inside_safe_area \
			and close_inside_safe_area \
			and _debug_rect_fully_inside(safe_rect, viewport_rect),
		"close_opaque": close_opaque,
		"preview_opaque": preview_opaque,
		"preview_frame_inside_viewport": frame_inside_viewport,
		"preview_drawn_after_open": drawn_after_open,
		"ready": visible and is_visible_in_tree() \
			and _hero_path == expected_path \
			and _portrait.texture != null and portrait_texture_ready \
			and portrait_visible_rect_ready and portrait_opaque \
			and _body.texture != null and _body.is_visible_in_tree() \
			and body_texture_ready and body_visible_rect_ready and body_opaque \
			and name_rendered_text_ready and state_rendered_text_ready \
			and description_rendered_text_ready \
			and _close.is_visible_in_tree() and close_inside_viewport \
			and close_inside_safe_area \
			and close_opaque and preview_opaque \
			and frame_inside_viewport and frame_inside_safe_area \
			and drawn_after_open,
	}


func _debug_visible_rect_ready(
		control: Control, frame_rect: Rect2, viewport_rect: Rect2) -> bool:
	if not control.is_visible_in_tree():
		return false
	var visible_rect: Rect2 = control.get_global_rect().intersection(frame_rect) \
		.intersection(viewport_rect)
	return visible_rect.size.x > 0.0 and visible_rect.size.y > 0.0


func _debug_label_visible_rect_ready(
		label: Label, frame_rect: Rect2, viewport_rect: Rect2) -> bool:
	if not label.is_visible_in_tree():
		return false
	var label_rect: Rect2 = label.get_global_rect()
	return _debug_rect_fully_inside(label_rect, frame_rect) \
		and _debug_rect_fully_inside(label_rect, viewport_rect)


func _debug_rect_fully_inside(inner: Rect2, outer: Rect2) -> bool:
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return false
	return inner.position.x >= outer.position.x - 0.5 \
		and inner.position.y >= outer.position.y - 0.5 \
		and inner.end.x <= outer.end.x + 0.5 \
		and inner.end.y <= outer.end.y + 0.5


func _debug_rect_array(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


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


func _debug_capture_locale() -> String:
	var locale: String = TranslationServer.get_locale()
	if locale.begins_with("zh_TW") or locale.begins_with("zh-Hant"):
		return "zh_TW"
	if locale.begins_with("zh_CN") or locale.begins_with("zh-Hans"):
		return "zh_CN"
	if locale.begins_with("ko"):
		return "ko"
	if locale.begins_with("ja"):
		return "ja"
	if locale.begins_with("en"):
		return "en"
	return locale


func _debug_expected_state_source_key(expected_path: String) -> String:
	if expected_path != CAPTURE_KEEPER_PATH:
		return ""
	if Vault.hero_earned(expected_path) and expected_path == Vault.hero_path():
		return "SHRINE_SELECTED"
	if Vault.hero_earned(expected_path):
		return "SHRINE_OWNED"
	if expected_path in Vault.PAID_HEROES:
		return "HERO_PREVIEW_IAP_LOCKED"
	return ""


## Build the idle frame for the header icon.
##
## A 24×24 crop in a 48×48 cell is exactly 2×. Pixels land on a 4-cell grid
## with no blur.
func _build_icon_frames() -> void:
	_icon_frames.clear()
	_icon_frame = 0
	if _hero.idle_sheet != null \
			and _hero.sprite_cell.x > 0 \
			and _hero.sprite_cell.y > 0:
		var frame_count: int = maxi(_hero.idle_frames, 1)
		var crop: Rect2i = _resolved_preview_crop()
		for frame_index in frame_count:
			# idle_sheet columns = down · up · left · right, rows = animation frames.
			# Drop transparent padding on the first column so the two-head figure fills the cell.
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = _hero.idle_sheet
			atlas.region = Rect2(
				float(crop.position.x),
				float(frame_index * _hero.sprite_cell.y + crop.position.y),
				float(crop.size.x),
				float(crop.size.y),
			)
			_icon_frames.append(atlas)
	elif _hero.portrait != null:
		# Heroes without idle_sheet, like old course resources, must not look like an empty square.
		_icon_frames.append(_hero.portrait)
	_portrait.texture = _icon_frames[0] if not _icon_frames.is_empty() else null


## Which file the on-screen texture came from. An atlas returns the source sheet.
func _debug_source_path(texture: Texture2D) -> String:
	var source: Texture2D = texture
	if source is AtlasTexture:
		source = (source as AtlasTexture).atlas
	return source.resource_path if source != null else ""


func _resolved_preview_crop() -> Rect2i:
	var full := Rect2i(Vector2i.ZERO, _hero.sprite_cell)
	var crop: Rect2i = _hero.preview_crop
	if crop.size.x <= 0 or crop.size.y <= 0:
		return full
	var clipped: Rect2i = crop.intersection(full)
	return clipped if clipped.size.x > 0 and clipped.size.y > 0 else full


func _advance_icon_frame() -> void:
	if _icon_frames.size() <= 1:
		return
	_icon_frame = (_icon_frame + 1) % _icon_frames.size()
	_portrait.texture = _icon_frames[_icon_frame]


func _refresh_copy() -> void:
	if _hero == null:
		return
	# Hang a 96×96 portrait in a 96×96 cell 1:1. No scale, so every source pixel shows.
	_body.texture = _hero.portrait
	_name.text = tr(_hero.display_name)
	_description.text = tr(_hero.description)
	# This is the ownership question — `hero_open()` is all-true on debug, so
	# an unbought hero would photograph as "Unlocked" in a store cut. See
	# `Vault.hero_earned()`.
	var opened: bool = Vault.hero_earned(_hero_path)
	var selected: bool = opened and _hero_path == Vault.hero_path()
	if selected:
		_state_source_key = "SHRINE_SELECTED"
		_state.text = tr(_state_source_key)
		_state.add_theme_color_override("font_color", SUCCESS)
	elif opened:
		_state_source_key = "SHRINE_OWNED"
		_state.text = tr(_state_source_key)
		_state.add_theme_color_override("font_color", MUTED)
	elif _hero_path in Vault.PAID_HEROES:
		_state_source_key = "HERO_PREVIEW_IAP_LOCKED"
		_state.text = tr(_state_source_key)
		_state.add_theme_color_override("font_color", LOCKED)
	else:
		_state_source_key = "HERO_PREVIEW_LOCKED"
		_state.text = tr("HERO_PREVIEW_LOCKED") % _hero.unlock_cost
		_state.add_theme_color_override("font_color", LOCKED)
	_apply_accent(_hero.accent)


func _apply_accent(accent: Color) -> void:
	_name.add_theme_color_override("font_color", accent)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.022, 0.035, 0.082, 0.99)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(accent.r, accent.g, accent.b, 0.94)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_right = 5
	style.corner_radius_bottom_left = 5
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	style.shadow_size = 7
	_frame.add_theme_stylebox_override("panel", style)


func _on_vault_changed() -> void:
	if visible:
		_refresh_copy()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and visible:
		_refresh_copy()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		accept_event()
		close_preview()
