class_name GateLodge
extends Node2D

## First-login refuge where Lumi registers the arriving traveller.
##
## Cloud-linked accounts whose durable cache holds no verified handle or
## no acknowledged lesson bit land here instead of the Arena (see
## ProductionHost.needs_lodge_lesson). Lumi greets the hero, the account
## claims one immutable adventurer name through the real atomic service,
## the player walks and dashes for real on the open floor, and the gate
## seals the account-owned lesson before departure. Completed accounts
## pass straight to the departure choice; local-only guests never enter.
##
## The lesson is not an expedition: nothing here arms a journey, spends
## a continue coin, spawns combat, or touches the saved run until the
## departure choice plans exactly like the title would. Name/move/dash
## gates complete only from actual performance, and the intro bit flips
## only from the server acknowledgement. The scene joins
## `moonlit_dialogue` for its whole visit, so attendance receipts wait
## for the lesson instead of covering the name keyboard or speeches.
##
## Harness hook: `host_override` substitutes the production host, and
## `layout_for` is pure so placement math is testable without a window.

enum State { BOOT, GREET, NAME, MOVE, DASH, GATE, SEALING, DEPART, EXITING, LOST, LINES }

## Room art this layout was measured against. The desk and gate centers
## come from a color probe of the raw plates: pale-blue gate mass at
## (0.826, 0.196) wide / (0.857, 0.163) tablet, warm desk mass at
## (0.261, 0.300) wide / (0.239, 0.263) tablet, open floor below ~0.34
## wide / ~0.30 tablet.
const WIDE_PLATE: Texture2D = preload(
	"res://assets/custom/world/lodge/room_wide.png")
const TABLET_PLATE: Texture2D = preload(
	"res://assets/custom/world/lodge/room_tablet.png")
const WIDE_PLATE_SIZE: Vector2 = Vector2(1881.0, 836.0)
const TABLET_PLATE_SIZE: Vector2 = Vector2(1448.0, 1086.0)
const WIDE_BASE: Vector2 = Vector2(808.0, 360.0)
const TABLET_BASE: Vector2 = Vector2(808.0, 606.0)
## Viewport aspect at/above this uses the wide plate, below the tablet.
const PLATE_ASPECT_SPLIT: float = 1.7

## Plate-fraction layout per plate: walk clamp, desk blocker, gate
## trigger, Lumi feet, hero start. Fractions keep collisions glued to
## the art at any window size.
const WIDE_WALK: Rect2 = Rect2(0.03, 0.34, 0.94, 0.62)
const WIDE_DESK: Rect2 = Rect2(0.06, 0.08, 0.26, 0.30)
const WIDE_GATE: Rect2 = Rect2(0.771, 0.35, 0.11, 0.10)
const WIDE_LUMI: Vector2 = Vector2(0.35, 0.46)
## Seated so the hero's opaque feet clear the tallest greeting card
## by 4px at both wide viewports (880x360 is the worst case: the card
## top sits at y231 while the spawn's plate fraction stretches with
## the wider room). Still deep inside the walk band, clear of the
## desk, Lumi's personal space, and the gate trigger.
const WIDE_HERO: Vector2 = Vector2(0.52, 0.634)
const TABLET_WALK: Rect2 = Rect2(0.03, 0.28, 0.94, 0.68)
const TABLET_DESK: Rect2 = Rect2(0.05, 0.06, 0.25, 0.26)
const TABLET_GATE: Rect2 = Rect2(0.802, 0.30, 0.11, 0.09)
const TABLET_LUMI: Vector2 = Vector2(0.33, 0.40)
const TABLET_HERO: Vector2 = Vector2(0.52, 0.62)

const TITLE_SCENE: String = "res://scenes/menus/production_entry.tscn"

## Desk-edge tie margin, in pixels: exits this close count as equally
## near, so the fixed edge order breaks the tie instead of float
## rounding picking a different edge at each framing.
const DESK_TIE_EPSILON: float = 0.001
## Cumulative walked distance that teaches the move gate, base units.
const MOVE_GATE_DISTANCE: float = 60.0
## Lumi's personal space: the hero slides around her, never through.
const LUMI_BODY_RADIUS: float = 26.0
## Name field headroom above the 12 visible characters for IME composition.
const NAME_FIELD_MAX: int = 24
## Viewport-space margin the confirm action keeps above the OS keyboard.
const KEYBOARD_ACTION_MARGIN: float = 8.0

## Substitute production host for the QA harness. Production leaves null.
var host_override: Node = null

## The harness embeds the lodge instead of swapping to it. Embedded, the
## lodge emits its exit intents instead of changing the scene itself.
var embedded: bool = false

## Emitted instead of a scene swap when embedded: return or depart.
signal request_title
signal request_arena(arena_path: String)

## Scripted movement for the harness clip. While active, the frame step
## feeds this to the player instead of the stick. Production never sets it.
var move_override_active: bool = false
var move_override: Vector2 = Vector2.ZERO

var _state: int = State.BOOT
var _host: Node = null
var _account_id: String = ""
var _display: String = ""
var _actor_scale: float = 1.0
var _walk_rect: Rect2 = Rect2()
var _desk_rect: Rect2 = Rect2()
var _gate_rect: Rect2 = Rect2()
var _move_accum: float = 0.0
var _gate_armed: bool = false
var _gate_cooldown: bool = false
var _fresh_armed: bool = false
var _exiting: bool = false
var _claim_busy: bool = false
var _claim_failed: bool = false
var _speech_lines: Array = []
var _speech_index: int = 0
var _speech_done: Callable = Callable()
var _speech_locked: bool = false
var _last_pos: Vector2 = Vector2.ZERO

@onready var _room: Sprite2D = $Room
@onready var _lumi: LumiGuide = $Lumi
@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Camera2D
@onready var _stick: Control = $Ui/MoveStick
@onready var _dash_button: Control = $Ui/Dash

var _ui: CanvasLayer = null
var _top_bar: HBoxContainer = null
var _speech_panel: PanelContainer = null
var _speech_speaker: Label = null
var _speech_body: Label = null
var _speech_hint: Label = null
var _speech_skip: Button = null
var _name_panel: PanelContainer = null
var _name_bust: TextureRect = null
var _name_head: HBoxContainer = null
var _name_hint: Label = null
var _name_field: LineEdit = null
var _name_status: Label = null
var _name_confirm: Button = null
## Keyboard-aware form seating: the unshifted panel top plus whether a
## visible OS keyboard currently lifts the form. Restored when the
## keyboard hides, so desktop framing never drifts.
var _name_base_y: float = 0.0
var _name_shifted: bool = false
## Tall-keyboard adaptation: the full card height while uncompacted
## (the mode decision measures against it even after compacting, so
## the compact rect cannot feed back and oscillate), whether the
## optional bust/header/copy currently hides, and which viewport
## occlusion already asked for one keyboard dismissal.
var _name_full_h: float = 0.0
var _name_compact: bool = false
var _dismissed_occlusion: float = -1.0
var _depart_panel: PanelContainer = null
var _depart_saved: Label = null
var _depart_status: Label = null
var _depart_resume: Button = null
var _depart_fresh: Button = null


## Placement for one viewport size, in viewport/world pixels. Pure, so
## tests judge every framing without opening a window. The room covers
## the viewport (never bands), actors scale with the room from their
## plate's base size, and every rect stays glued to the painted art.
static func layout_for(viewport_size: Vector2) -> Dictionary:
	var wide: bool = viewport_size.x / maxf(viewport_size.y, 1.0) \
		>= PLATE_ASPECT_SPLIT
	var plate: Vector2 = WIDE_PLATE_SIZE if wide else TABLET_PLATE_SIZE
	var base: Vector2 = WIDE_BASE if wide else TABLET_BASE
	var room_scale: float = maxf(
		viewport_size.x / plate.x, viewport_size.y / plate.y)
	var actor_scale: float = room_scale / (base.x / plate.x)
	var center: Vector2 = viewport_size * 0.5
	var origin: Vector2 = center - plate * room_scale * 0.5
	var point := func(frac: Vector2) -> Vector2:
		return origin + frac * plate * room_scale
	var rect := func(frac: Rect2) -> Rect2:
		return Rect2(point.call(frac.position),
			frac.size * plate * room_scale)
	var walk: Rect2 = WIDE_WALK if wide else TABLET_WALK
	var desk: Rect2 = WIDE_DESK if wide else TABLET_DESK
	var gate: Rect2 = WIDE_GATE if wide else TABLET_GATE
	return {
		"wide": wide,
		"room_scale": room_scale,
		"actor_scale": actor_scale,
		"room_center": center,
		"walk_rect": rect.call(walk),
		"desk_rect": rect.call(desk),
		"gate_rect": rect.call(gate),
		"lumi_pos": point.call(WIDE_LUMI if wide else TABLET_LUMI),
		"hero_pos": point.call(WIDE_HERO if wide else TABLET_HERO),
	}


func _ready() -> void:
	add_to_group(&"moonlit_dialogue")
	GateEntryStrings.ensure_loaded()
	_ui = $Ui
	_build_ui()
	var arena_cam: Camera2D = _player.get_node("Cam") as Camera2D
	if arena_cam != null:
		arena_cam.enabled = false
	_player.apply_hero_visual(Vault.hero())
	_player.set_move_input(Vector2.ZERO)
	_stick.set_active(false)
	_dash_button.visible = false
	_dash_button.pressed.connect(_on_dash_pressed)
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	var layout: Dictionary = layout_for(
		get_viewport().get_visible_rect().size)
	_player.position = layout["hero_pos"]
	_player.reset_physics_interpolation()
	_lumi.position = layout["lumi_pos"]
	_lumi.set_actor_scale(_actor_scale)
	_lumi.set_facing(LumiGuide.FACING_RIGHT)
	_boot.call_deferred()


## Production host, or the harness substitute when injected.
func _resolve_host() -> Node:
	if host_override != null:
		return host_override
	return get_node_or_null("/root/ProductionHost")


## Current flow state for tests and the harness.
func lodge_state() -> int:
	return _state


## Account this visit is bound to. Empty until boot reads the host.
func lodge_account() -> String:
	return _account_id


## Claimed handle driving the lesson. Empty until the name settles.
func lodge_display() -> String:
	return _display


func _build_ui() -> void:
	_top_bar = HBoxContainer.new()
	_top_bar.name = &"TopBar"
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_top_bar)
	var home: Button = GateEntryStyle.make_button(
		"gate.lodge.return_title")
	home.name = &"ToTitle"
	home.pressed.connect(_on_return_to_title)
	_top_bar.add_child(home)
	_build_speech()
	_build_name_form()
	_build_departure()


func _build_speech() -> void:
	_speech_panel = PanelContainer.new()
	_speech_panel.name = &"Speech"
	GateEntryStyle.apply_card(_speech_panel)
	_speech_panel.visible = false
	_speech_panel.gui_input.connect(_on_speech_input)
	_ui.add_child(_speech_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech_panel.add_child(box)
	_speech_speaker = GateEntryStyle.make_label(
		"gate.lodge.lumi_name", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.ACCENT_AMBER, true)
	_speech_speaker.name = &"Speaker"
	box.add_child(_speech_speaker)
	_speech_body = GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_BODY, GateEntryStyle.TEXT_MAIN)
	_speech_body.name = &"Body"
	_speech_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_speech_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	_speech_hint = GateEntryStyle.make_label(
		"gate.lodge.tap_next", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.TEXT_FAINT)
	_speech_hint.name = &"Hint"
	row.add_child(_speech_hint)
	_speech_skip = GateEntryStyle.make_button("gate.lodge.skip")
	_speech_skip.name = &"Skip"
	_speech_skip.pressed.connect(_on_speech_skip)
	row.add_child(_speech_skip)


func _build_name_form() -> void:
	_name_panel = PanelContainer.new()
	_name_panel.name = &"NameForm"
	GateEntryStyle.apply_card(_name_panel)
	_name_panel.visible = false
	_ui.add_child(_name_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_panel.add_child(box)
	_name_head = HBoxContainer.new()
	var head: HBoxContainer = _name_head
	head.add_theme_constant_override(&"separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	_name_bust = TextureRect.new()
	_name_bust.name = &"Bust"
	_name_bust.texture = preload(
		"res://assets/custom/actors/lumi/bust.png")
	_name_bust.custom_minimum_size = Vector2(52, 64)
	_name_bust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_name_bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_name_bust.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_name_bust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_name_bust)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", 2)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(titles)
	var title: Label = GateEntryStyle.make_label(
		"gate.lodge.name_title", GateEntryStyle.FONT_SUBTITLE,
		GateEntryStyle.TEXT_MAIN, true)
	titles.add_child(title)
	var public_note: Label = GateEntryStyle.make_label(
		"gate.lodge.name_public", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.TEXT_DIM)
	public_note.name = &"PublicNote"
	public_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(public_note)
	_name_field = LineEdit.new()
	_name_field.name = &"Field"
	_name_field.max_length = NAME_FIELD_MAX
	_name_field.clear_button_enabled = true
	_name_field.add_theme_font_override(
		&"font", GateEntryStyle.body_font())
	_name_field.add_theme_font_size_override(
		&"font_size", GateEntryStyle.FONT_BODY)
	_name_field.add_theme_color_override(
		&"font_color", GateEntryStyle.TEXT_MAIN)
	_name_field.add_theme_color_override(
		&"font_placeholder_color", GateEntryStyle.TEXT_FAINT)
	_name_field.custom_minimum_size = Vector2(
		240, GateEntryStyle.TOUCH_HEIGHT)
	_name_field.text_submitted.connect(_on_name_submitted)
	box.add_child(_name_field)
	_name_hint = GateEntryStyle.make_label(
		"gate.lodge.name_hint", GateEntryStyle.FONT_SMALL,
		GateEntryStyle.TEXT_FAINT)
	box.add_child(_name_hint)
	_name_status = GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_SMALL, GateEntryStyle.CORAL)
	_name_status.name = &"Status"
	_name_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_name_status)
	_name_confirm = GateEntryStyle.make_button(
		"gate.lodge.name_confirm", "primary")
	_name_confirm.name = &"Confirm"
	_name_confirm.pressed.connect(_on_name_confirm)
	box.add_child(_name_confirm)


func _build_departure() -> void:
	_depart_panel = PanelContainer.new()
	_depart_panel.name = &"Departure"
	GateEntryStyle.apply_card(_depart_panel)
	_depart_panel.visible = false
	_ui.add_child(_depart_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_depart_panel.add_child(box)
	var title: Label = GateEntryStyle.make_label(
		"gate.lodge.depart_title", GateEntryStyle.FONT_SUBTITLE,
		GateEntryStyle.TEXT_MAIN, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_depart_saved = GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_SMALL, GateEntryStyle.TEXT_DIM)
	_depart_saved.name = &"Saved"
	_depart_saved.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_depart_saved.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_depart_saved)
	_depart_resume = GateEntryStyle.make_button(
		"gate.lodge.depart_resume", "primary")
	_depart_resume.name = &"Resume"
	_depart_resume.pressed.connect(_on_depart_resume)
	box.add_child(_depart_resume)
	_depart_fresh = GateEntryStyle.make_button(
		"gate.lodge.depart_fresh")
	_depart_fresh.name = &"Fresh"
	_depart_fresh.pressed.connect(_on_depart_fresh)
	box.add_child(_depart_fresh)
	_depart_status = GateEntryStyle.make_label(
		"", GateEntryStyle.FONT_SMALL, GateEntryStyle.CORAL)
	_depart_status.name = &"Status"
	_depart_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_depart_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_depart_status)
	var back: Button = GateEntryStyle.make_button("gate.lodge.depart_back")
	back.name = &"Back"
	back.pressed.connect(_on_depart_back)
	box.add_child(back)


## Place room, actors, collisions, and UI for the current viewport.
## The player keeps its feet (clamped into the walk); Lumi re-seats on
## her desk fraction; the camera stays room-centered and fixed.
func _relayout() -> void:
	if not is_inside_tree() or _room == null:
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var layout: Dictionary = layout_for(view)
	_actor_scale = float(layout["actor_scale"])
	_room.texture = WIDE_PLATE if bool(layout["wide"]) else TABLET_PLATE
	_room.scale = Vector2.ONE * float(layout["room_scale"])
	_room.position = layout["room_center"]
	_camera.position = layout["room_center"]
	_camera.make_current()
	_walk_rect = layout["walk_rect"]
	_desk_rect = layout["desk_rect"]
	_gate_rect = layout["gate_rect"]
	_lumi.position = layout["lumi_pos"]
	_lumi.set_actor_scale(_actor_scale)
	if _player != null:
		_player.set_bounds(_walk_rect)
		_player.position.x = clampf(_player.position.x,
			_walk_rect.position.x, _walk_rect.end.x)
		_player.position.y = clampf(_player.position.y,
			_walk_rect.position.y, _walk_rect.end.y)
	_layout_ui(view)


## Seat the dialogue surfaces: speech low, name form high (clear of the
## native keyboard), departure centered, all inside the safe area.
func _layout_ui(view: Vector2) -> void:
	var full := Rect2(Vector2.ZERO, view)
	var safe: Rect2 = Screen.viewport_safe_rect(get_viewport())
	if not safe.has_area():
		safe = full
	_top_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_top_bar.position = safe.position + Vector2(12, 10)
	Screen.apply_safe_area(_stick, safe, full)
	Screen.apply_safe_area(_dash_button, safe, full)
	# Only visible panels report a real size; hidden ones seat on show.
	# A keyboard-shifted name form keeps its adapted seat until the
	# keyboard hides, which re-seats for the current view.
	if _speech_panel.visible:
		_seat_bottom(_speech_panel, safe)
	if _name_panel.visible and not _name_shifted:
		_seat_top(_name_panel, safe)
	if _depart_panel.visible:
		_seat_center(_depart_panel, safe)


func _panel_width(safe: Rect2) -> float:
	return minf(safe.size.x - 48.0, 560.0)


## Wrapped labels report their minimum as if wrapped at minimum
## width, which explodes panel heights. Pin each wrapped label to the
## card's content width first, so heights measure at the real width.
func _fit_labels(panel: PanelContainer, content: float) -> void:
	for label in panel.find_children("*", "Label", true, false):
		if (label as Label).autowrap_mode == TextServer.AUTOWRAP_OFF:
			continue
		var pinned: float = content
		if (label as Label).name == &"PublicNote":
			pinned = maxf(content - 62.0, 120.0)
		(label as Label).custom_minimum_size = Vector2(pinned, 0)


## Seat a panel from its fresh minimum: the width pins first, one frame
## lets wrapped minima recompute at that width, and only then does the
## size take. Sizing in the same breath reads the stale minimum and the
## panel never shrinks back.
func _seat_bottom(panel: PanelContainer, safe: Rect2) -> void:
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var width: float = _panel_width(safe)
	_fit_labels(panel, width - GateEntryStyle.CARD_MARGIN_H)
	panel.custom_minimum_size = Vector2(
		width, panel.custom_minimum_size.y)
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.size = panel.get_combined_minimum_size()
	panel.position = Vector2(
		safe.position.x + (safe.size.x - panel.size.x) * 0.5,
		safe.end.y - panel.size.y - 12.0)


func _seat_top(panel: PanelContainer, safe: Rect2) -> void:
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	var width: float = _panel_width(safe)
	_fit_labels(panel, width - GateEntryStyle.CARD_MARGIN_H)
	panel.custom_minimum_size = Vector2(
		width, panel.custom_minimum_size.y)
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.size = panel.get_combined_minimum_size()
	panel.position = Vector2(
		safe.position.x + (safe.size.x - panel.size.x) * 0.5,
		safe.position.y + 58.0)


func _seat_center(panel: PanelContainer, safe: Rect2) -> void:
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var width: float = minf(_panel_width(safe), 420.0)
	_fit_labels(panel, width - GateEntryStyle.CARD_MARGIN_H)
	panel.custom_minimum_size = Vector2(
		width, panel.custom_minimum_size.y)
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.size = panel.get_combined_minimum_size()
	panel.position = (safe.size - panel.size) * 0.5 + safe.position


## Keyboard visibility plus the real name-form bounds for entry QA.
## Rects are viewport-space `[x, y, w, h]` arrays; the report never
## carries the typed name or any provider personal data. The two
## keyboard figures keep their units apart: raw device pixels as the
## OS reports them, and the converted viewport occlusion the layout
## actually lifts against.
func name_form_keyboard_report() -> Dictionary:
	var height: int = 0
	if DisplayServer.has_feature(
			DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		height = DisplayServer.virtual_keyboard_get_height()
	var view: Rect2 = get_viewport().get_visible_rect()
	var report: Dictionary = {
		"form_visible": _name_panel != null \
			and _name_panel.visible,
		"keyboard_visible": height > 0,
		"keyboard_height_device": height,
		"keyboard_occlusion": keyboard_occlusion_for(view,
			Vector2(DisplayServer.window_get_size()),
			float(height),
			get_viewport().get_screen_transform()),
		"panel_rect": [],
		"field_rect": [],
		"confirm_rect": [],
		"shifted": _name_shifted,
	}
	if not bool(report["form_visible"]):
		return report
	report["panel_rect"] = _rect_array(
		_name_panel.get_global_rect())
	report["field_rect"] = _rect_array(
		_name_field.get_global_rect())
	report["confirm_rect"] = _rect_array(
		_name_confirm.get_global_rect())
	return report


func _rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x,
		rect.size.y]


## Viewport-space pixels the OS keyboard occludes, from its
## device-pixel height. The keyboard spans the bottom of the device
## screen, so its top edge converts through the inverse viewport
## screen transform (scale and letterbox offset honored, never an
## assumed factor). Clamped to the viewport; zero when hidden,
## absurd, or unmappable. Pure so headless regression can pin every
## density against the actual production conversion.
static func keyboard_occlusion_for(view: Rect2,
		screen_size: Vector2, keyboard_height: float,
		screen_xform: Transform2D) -> float:
	if keyboard_height <= 0.0 or screen_size.y <= 0.0:
		return 0.0
	if absf(screen_xform.determinant()) < 0.000001:
		return 0.0
	var inverse: Transform2D = screen_xform.affine_inverse()
	var top_screen: float = screen_size.y - keyboard_height
	var left: float = (inverse * Vector2(0.0, top_screen)).y
	var right: float = (inverse * Vector2(
		screen_size.x, top_screen)).y
	return clampf(view.end.y - minf(left, right),
		0.0, view.size.y)


## Pixels the confirm action needs to rise so the OS keyboard clears it
## (plus a small margin). `keyboard_height` is viewport-space
## occlusion from `keyboard_occlusion_for`, never raw device pixels:
## the live height only arrives on a real device keyboard, converted
## at the call site. Pure so headless regression can pin it.
static func keyboard_shift_for(confirm_bottom: float,
		view_height: float, keyboard_height: float) -> float:
	if keyboard_height <= 0.0:
		return 0.0
	return maxf(confirm_bottom + KEYBOARD_ACTION_MARGIN \
		- (view_height - keyboard_height), 0.0)


## The lift the name form actually takes: the needed shift, bounded so
## the panel never rises above the safe top. When little space
## remains the form parks at the safe top — field and confirm stay
## visible and tappable instead of sliding offscreen — and the lift
## is never negative. Pure so headless regression can pin it.
static func keyboard_lift_for(confirm_bottom: float,
		view_height: float, occlusion: float, base_y: float,
		safe_top: float) -> float:
	var shift: float = keyboard_shift_for(
		confirm_bottom, view_height, occlusion)
	return minf(shift, maxf(base_y - safe_top, 0.0))


## Lift the name form above a visible OS keyboard and adapt its chrome
## while covered; restore everything when the keyboard hides. Desktop
## reports height zero and never shifts. `height_device_px` overrides
## the live OS reading, and `window_override` the live window size,
## so headless regression and the QA harness run this same hook with
## synthetic keyboards; negatives mean live. Headless has no window
## at all, so the tests stage the window they resized to.
## A plain lift cannot fit the full card above a tall keyboard, so when
## the lift runs out the optional bust/header/explanatory copy hides,
## the card shrinks to its live minimum, and the short form (field,
## error feedback, confirm) lifts instead. An all-screen keyboard that
## still covers the short form is dismissed once per height instead of
## promising impossible UI; the focused field keeps its typed value
## and the keyboard's own submit still files the claim. Returns the
## measured outcome for QA. Idempotent: every frame assigns absolute
## geometry from the unshifted seat, never from last frame's rect.
func _apply_keyboard_shift(height_device_px := -1.0,
		window_override := Vector2(-1.0, -1.0)) -> Dictionary:
	if _name_panel == null or not _name_panel.visible:
		_set_name_compact(false)
		_name_shifted = false
		return {"mode": "hidden"}
	var height: float = height_device_px
	if height < 0.0:
		height = 0.0
		if DisplayServer.has_feature(
				DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			height = float(
				DisplayServer.virtual_keyboard_get_height())
	if height <= 0.0:
		if _name_shifted or _name_compact:
			_set_name_compact(false)
			_name_panel.position.y = _name_base_y
			_name_shifted = false
			_dismissed_occlusion = -1.0
			# Refresh the seat for the current view: a rotation
			# while shifted kept the old seat, and the hide
			# restores to it.
			_seat_visible(_name_panel, "top")
		return {"mode": "restored"}
	if not _name_shifted:
		_name_base_y = _name_panel.position.y
		_name_shifted = true
	var view: Rect2 = get_viewport().get_visible_rect()
	var safe: Rect2 = Screen.viewport_safe_rect(get_viewport())
	if not safe.has_area():
		safe = view
	# Device pixels in, viewport pixels out: the raw keyboard height
	# converts through the live screen transform before any layout.
	var window_size: Vector2 = window_override
	if window_size.x < 0.0:
		window_size = Vector2(DisplayServer.window_get_size())
	var occluded: float = keyboard_occlusion_for(view,
		window_size, height,
		get_viewport().get_screen_transform())
	var kb_top: float = view.size.y - occluded
	var avail: float = maxf(_name_base_y - safe.position.y, 0.0)
	# The mode decision always measures the full card: the compact
	# rect is shorter, and deciding from it would flip modes back.
	var base_bottom: float = 0.0
	if _name_compact:
		base_bottom = _name_base_y + maxf(_name_full_h,
			_name_panel.size.y) - _name_card_bottom_margin()
	else:
		# Measure from the unshifted seat: the live rect already
		# includes last frame's lift, and feeding it back would
		# oscillate.
		var lifted: float = \
			_name_base_y - _name_panel.position.y
		base_bottom = _name_confirm.get_global_rect().end.y \
			+ lifted
		_name_full_h = _name_panel.size.y
	var needed: float = keyboard_shift_for(base_bottom,
		view.size.y, occluded)
	if needed <= avail:
		_set_name_compact(false)
		var lift: float = maxf(needed, 0.0)
		_name_panel.position.y = _name_base_y - lift
		return {"mode": "lifted", "occlusion": occluded,
			"lift": lift}
	_set_name_compact(true)
	var compact_h: float = \
		_name_panel.get_combined_minimum_size().y
	_name_panel.size.y = compact_h
	var card_bottom: float = _name_card_bottom_margin()
	var need_c: float = _name_base_y + compact_h - card_bottom \
		+ KEYBOARD_ACTION_MARGIN - kb_top
	var lift_c: float = minf(maxf(need_c, 0.0), avail)
	_name_panel.position.y = _name_base_y - lift_c
	var clears: bool = _name_base_y - lift_c + compact_h \
		- card_bottom <= kb_top - KEYBOARD_ACTION_MARGIN
	var dismissed: bool = false
	if not clears and occluded != _dismissed_occlusion:
		if DisplayServer.has_feature(
				DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			DisplayServer.virtual_keyboard_hide()
		_dismissed_occlusion = occluded
		dismissed = true
	return {"mode": "compact", "occlusion": occluded,
		"lift": lift_c, "clears": clears, "dismissed": dismissed}


## Hide or restore the optional name-form chrome (bust, header, hint)
## and resize the card to its live minimum, full or short. The field
## keeps focus and its typed value; only siblings toggle.
func _set_name_compact(compact: bool) -> void:
	if _name_panel == null or compact == _name_compact:
		return
	_name_compact = compact
	_name_head.visible = not compact
	_name_hint.visible = not compact
	_name_panel.size.y = _name_panel.get_combined_minimum_size().y


## The card skin's bottom content margin, live: the compact layout
## parks the confirm action above it, never from a stale constant.
func _name_card_bottom_margin() -> float:
	var skin := _name_panel.get_theme_stylebox("panel") as StyleBox
	if skin == null:
		return 0.0
	return skin.content_margin_bottom


## Seat one panel now that it is visible and sized.
func _seat_visible(panel: PanelContainer, seat: String) -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var full := Rect2(Vector2.ZERO, view)
	var safe: Rect2 = Screen.viewport_safe_rect(get_viewport())
	if not safe.has_area():
		safe = full
	if seat == "bottom":
		_seat_bottom(panel, safe)
	elif seat == "top":
		_seat_top(panel, safe)
	else:
		_seat_center(panel, safe)


# --- boot ---------------------------------------------------------------

func _boot() -> void:
	_host = _resolve_host()
	if _host == null:
		_to_title_now()
		return
	_account_id = str((_host.account_state() as Dictionary).get(
		"public_id", ""))
	if _account_id.is_empty():
		_to_title_now()
		return
	_host.production_changed.connect(_on_production_changed)
	if not bool(_host.needs_lodge_lesson()):
		_enter_departure()
		return
	_display = str(_host.verified_display_name())
	if not _display.is_empty():
		_begin_practice()
		return
	_state = State.GREET
	_say([
		GateEntryStrings.text("gate.lodge.greet_1"),
		GateEntryStrings.text("gate.lodge.greet_2"),
		GateEntryStrings.text("gate.lodge.greet_3"),
	], Callable(self, "_recover_name"))


## Reload the account's claimed name: a restart, a fresh install, or a
## cold cache recovers the same handle instead of asking twice.
func _recover_name() -> void:
	if _state != State.GREET or not _ticket_same():
		return
	_show_busy(GateEntryStrings.text("gate.lodge.name_checking"))
	var reply: Dictionary = await _host.load_adventurer_name()
	if _state != State.GREET or not _ticket_same():
		return
	if str(reply.get("status", "")) == "ok":
		var display: String = str(reply.get("display", ""))
		if not display.is_empty():
			_display = display
			# A cold cache may recover an already completed account
			# (fresh install, evicted cache). Trust only the host's
			# cached readiness: a failed cache write keeps the lesson
			# open and re-seals at the gate instead.
			if not bool(_host.needs_lodge_lesson()):
				_enter_departure()
			else:
				_begin_practice()
			return
		_show_name_form("")
		return
	if _reply_lost(reply):
		_lost()
		return
	_show_name_form(str(reply.get("code", "")))


# --- speech ---------------------------------------------------------------

## Show tap-through lines, then run `done`. Skip jumps straight to
## `done`: it skips words, never the practiced gates behind them.
func _say(lines: Array, done: Callable) -> void:
	_speech_lines = lines.duplicate()
	_speech_index = 0
	_speech_done = done
	_speech_locked = false
	_speech_hint.visible = true
	_speech_skip.visible = true
	_speech_panel.visible = true
	_speech_body.text = str(_speech_lines[0])
	_seat_visible(_speech_panel, "bottom")


## One non-advancing line while an acknowledgement is in flight.
func _show_busy(line: String) -> void:
	_speech_lines = [line]
	_speech_index = 0
	_speech_done = Callable()
	_speech_locked = true
	_speech_hint.visible = false
	_speech_skip.visible = false
	_speech_panel.visible = true
	_speech_body.text = line
	_seat_visible(_speech_panel, "bottom")


## One non-advancing reminder that stays up during free practice.
func _show_hint(line: String) -> void:
	_show_busy(line)


func _hide_speech() -> void:
	_speech_panel.visible = false
	_speech_lines = []
	_speech_done = Callable()
	_speech_locked = false


func _on_speech_input(event: InputEvent) -> void:
	if _speech_locked or not _speech_panel.visible:
		return
	var tapped: bool = false
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		tapped = click.pressed \
			and click.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = (event as InputEventScreenTouch).pressed
	if tapped:
		_advance_speech()


func _advance_speech() -> void:
	if _speech_locked or _speech_lines.is_empty():
		return
	_speech_index += 1
	if _speech_index >= _speech_lines.size():
		var done: Callable = _speech_done
		_hide_speech()
		if done.is_valid():
			done.call()
		return
	_speech_body.text = str(_speech_lines[_speech_index])
	_seat_visible(_speech_panel, "bottom")


func _on_speech_skip() -> void:
	if _speech_locked or _speech_lines.is_empty():
		return
	var done: Callable = _speech_done
	_hide_speech()
	if done.is_valid():
		done.call()


# --- name -----------------------------------------------------------------

## The register form. `load_code` presets the offline status when entry
## arrived limping; the form stays fully usable either way.
func _show_name_form(load_code: String) -> void:
	_state = State.NAME
	_hide_speech()
	_claim_failed = false
	_name_field.text = ""
	_refresh_name_status(load_code)
	_name_panel.visible = true
	_seat_visible(_name_panel, "top")
	_name_field.grab_focus.call_deferred()


func _on_name_submitted(_text: String) -> void:
	_on_name_confirm()


func _on_name_confirm() -> void:
	if _state != State.NAME or _claim_busy or not _ticket_same():
		return
	_claim_busy = true
	_name_confirm.disabled = true
	_name_status.text = GateEntryStrings.text("gate.lodge.name_checking")
	var reply: Dictionary = await _host.claim_adventurer_name(
		_name_field.text)
	_claim_busy = false
	_name_confirm.disabled = false
	if _state != State.NAME or not _ticket_same():
		return
	if str(reply.get("status", "")) == "ok":
		var display: String = str(reply.get("display", ""))
		if display.is_empty():
			_refresh_name_status("empty-reply")
			return
		_display = display
		_name_panel.visible = false
		_say([GateEntryStrings.text("gate.lodge.named_ok") % display],
			Callable(self, "_begin_practice"))
		return
	if _reply_lost(reply):
		_lost()
		return
	_claim_failed = true
	_refresh_name_status(str(reply.get("code", "")))


## Map a claim/load failure onto the three honest form states. Unknown
## codes read as link trouble with a retry, never as taken: only the
## server's own collision word may say the name is gone.
func _refresh_name_status(code: String) -> void:
	if code.is_empty() or code == "adventurer-not-found":
		_name_status.text = ""
	elif code == "name-taken":
		_name_status.text = GateEntryStrings.text(
			"gate.lodge.name_taken")
	elif code == "invalid-name":
		_name_status.text = GateEntryStrings.text(
			"gate.lodge.name_invalid")
	else:
		_name_status.text = GateEntryStrings.text(
			"gate.lodge.name_offline")
	_name_confirm.text = GateEntryStrings.text(
		"gate.lodge.name_retry") if _claim_failed \
		else GateEntryStrings.text("gate.lodge.name_confirm")


# --- practice ---------------------------------------------------------------

## Greet a settled handle then teach only what this account has not
## actually performed yet. Sticky gates survive restarts; nothing here
## infers a lesson from a timer or a tap.
func _begin_practice() -> void:
	_hide_speech()
	_name_panel.visible = false
	if not _display.is_empty() and _state != State.NAME:
		_say([GateEntryStrings.text("gate.lodge.named_ok") % _display],
			Callable(self, "_practice_step"))
	else:
		_practice_step()


func _practice_step() -> void:
	if not _ticket_same():
		return
	var gates: Dictionary = Vault.lodge_progress_for_account(_account_id)
	if not bool(gates.get("move", false)):
		_say([GateEntryStrings.text("gate.lodge.move_lesson")],
			Callable(self, "_start_move"))
	else:
		_start_dash()


func _start_move() -> void:
	if not _ticket_same():
		return
	_state = State.MOVE
	_move_accum = 0.0
	_last_pos = _player.position
	_stick.set_active(true)
	_show_hint(GateEntryStrings.text("gate.lodge.move_lesson"))


func _on_move_learned() -> void:
	_state = State.LINES
	Vault.mark_lodge_gate(_account_id, "move")
	Onboarding.mark_done("move", true)
	_say([GateEntryStrings.text("gate.lodge.move_done")],
		Callable(self, "_start_dash"))


func _start_dash() -> void:
	if not _ticket_same():
		return
	var gates: Dictionary = Vault.lodge_progress_for_account(_account_id)
	if bool(gates.get("dash", false)):
		_start_gate_walk()
		return
	_state = State.DASH
	_stick.set_active(true)
	_dash_button.visible = true
	_say([GateEntryStrings.text("gate.lodge.dash_lesson")],
		Callable(self, "_dash_free"))


func _dash_free() -> void:
	if not _ticket_same():
		return
	_state = State.DASH
	_show_hint(GateEntryStrings.text("gate.lodge.dash_lesson"))


func _on_dash_learned() -> void:
	_state = State.LINES
	Vault.mark_lodge_gate(_account_id, "dash")
	Onboarding.mark_done("dash", true)
	_say([GateEntryStrings.text("gate.lodge.dash_done")],
		Callable(self, "_start_gate_walk"))


func _start_gate_walk() -> void:
	if not _ticket_same():
		return
	_state = State.GATE
	_stick.set_active(true)
	_dash_button.visible = true
	_gate_armed = true
	_gate_cooldown = _gate_rect.has_point(_player.position)
	_show_hint(GateEntryStrings.text("gate.lodge.gate_lesson") % _display)


func _on_dash_pressed() -> void:
	if _state != State.DASH and _state != State.GATE:
		return
	if not _ticket_same():
		return
	var direction: Vector2 = _stick.get_value()
	if move_override_active and move_override.length() >= 0.01:
		direction = move_override
	if direction.length() < 0.01:
		direction = _player.facing_vector()
	_player.dash(direction)


# --- seal and departure -------------------------------------------------------

## The gate seals the lesson. Only the server acknowledgement opens
## departure; a miss re-arms the gate for another explicit touch.
func _seal() -> void:
	if _state != State.GATE or not _ticket_same():
		return
	_state = State.SEALING
	_gate_armed = false
	_stick.set_active(false)
	_dash_button.visible = false
	_player.set_move_input(Vector2.ZERO)
	_show_busy(GateEntryStrings.text("gate.lodge.gate_wait"))
	var reply: Dictionary = await _host.mark_intro_complete()
	if _state != State.SEALING or not _ticket_same():
		return
	if str(reply.get("status", "")) == "ok":
		_enter_departure()
		return
	if _reply_lost(reply):
		_lost()
		return
	_say([GateEntryStrings.text("gate.lodge.gate_retry")],
		Callable(self, "_start_gate_walk"))


## Departure choice. A living journey offers Resume against a confirmed
## fresh start; a sealed one never offers its stage back. The plan call
## enforces it all again, so this panel cannot talk the host into a
## free continuation.
func _enter_departure() -> void:
	_state = State.DEPART
	_display = str(_host.verified_display_name())
	_gate_armed = false
	_stick.set_active(false)
	_dash_button.visible = false
	_player.set_move_input(Vector2.ZERO)
	_hide_speech()
	_name_panel.visible = false
	_fresh_armed = false
	var saved: Dictionary = _host.saved_gate_summary()
	var has_save: bool = bool(saved.get("has_save", false))
	_depart_resume.visible = has_save
	if has_save:
		var where: String = GateEntryStrings.text(
			"gate.lodge.depart_where") % [
				int(saved.get("cycle", 1)),
				int(saved.get("zone_index", 0))]
		_depart_saved.text = GateEntryStrings.text(
			"gate.lodge.depart_saved") % where
	else:
		_depart_saved.text = ""
	_depart_status.text = ""
	_depart_panel.visible = true
	_seat_visible(_depart_panel, "center")


func _on_depart_resume() -> void:
	_exit_to_arena(false, true)


func _on_depart_fresh() -> void:
	var saved: Dictionary = _host.saved_gate_summary()
	if (bool(saved.get("has_save", false))
		or bool(saved.get("revive_stuck", false))) \
		and not _fresh_armed:
		_fresh_armed = true
		_depart_status.text = GateEntryStrings.text(
			"gate.lodge.depart_fresh_confirm")
		_seat_visible(_depart_panel, "center")
		return
	_exit_to_arena(true, true)


func _on_depart_back() -> void:
	if _state != State.DEPART or _exiting:
		return
	_depart_panel.visible = false
	_start_gate_walk()


func _exit_to_arena(fresh: bool, confirmed: bool) -> void:
	if _state != State.DEPART or _exiting or not _ticket_same():
		return
	_exiting = true
	_depart_status.text = ""
	var plan: Dictionary = _host.plan_lodge_exit(fresh, confirmed)
	if str(plan.get("status", "")) != "ok":
		_exiting = false
		_fresh_armed = false
		_depart_panel.visible = false
		_say([GateEntryStrings.text("gate.lodge.gate_retry")],
			Callable(self, "_start_gate_walk"))
		return
	var account: String = str(plan.get("account_id", ""))
	if not bool(_host.confirm_entry_account(account)):
		_host.cancel_entry_plan()
		_exiting = false
		_lost()
		return
	_state = State.EXITING
	var arena_path: String = str(plan.get("arena", ""))
	if embedded:
		request_arena.emit(arena_path)
		return
	var packed: PackedScene = load(arena_path) as PackedScene
	if packed == null:
		_host.cancel_entry_plan()
		_exiting = false
		_depart_panel.visible = false
		_say([GateEntryStrings.text("gate.lodge.gate_retry")],
			Callable(self, "_start_gate_walk"))
		return
	get_tree().change_scene_to_packed(packed)


# --- account guard --------------------------------------------------------------

## The visit's account is still the live one, with no deletion running.
func _ticket_same() -> bool:
	if _host == null or _account_id.is_empty():
		return false
	var state: Dictionary = _host.account_state()
	if str(state.get("public_id", "")) != _account_id:
		return false
	return not bool(state.get("deletion_in_flight", false))


## Replies that retire the visit instead of retrying it: the call
## outlived its account, the host, or the session around them.
func _reply_lost(reply: Dictionary) -> bool:
	if str(reply.get("status", "")) == "cancelled":
		return true
	var code: String = str(reply.get("code", ""))
	return code in ["account-retired", "host-closed",
		"coordinator-closed", "local-guest", "deletion-in-flight",
		"account_moved", "account-moved"]


func _on_production_changed(state: Dictionary) -> void:
	if _state == State.EXITING or _state == State.LOST:
		return
	if str(state.get("public_id", "")) != _account_id:
		_lost()
		return
	if bool(state.get("deletion_in_flight", false)):
		_lost()


## Retire the visit and walk back to the title. The plan hold releases;
## the lesson waits for the account's next entry.
func _lost() -> void:
	if _state == State.LOST or _state == State.EXITING:
		return
	_state = State.LOST
	_gate_armed = false
	_stick.set_active(false)
	_dash_button.visible = false
	_player.set_move_input(Vector2.ZERO)
	_name_panel.visible = false
	_depart_panel.visible = false
	_say([GateEntryStrings.text("gate.lodge.account_lost")],
		Callable(self, "_to_title_now"))


func _on_return_to_title() -> void:
	if _exiting or _state == State.EXITING:
		return
	_to_title_now()


func _to_title_now() -> void:
	if _host != null:
		_host.cancel_entry_plan()
	if embedded:
		request_title.emit()
		return
	get_tree().change_scene_to_file(TITLE_SCENE)


# --- frame ----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _player == null or _lumi == null:
		return
	var practicing: bool = _state == State.MOVE \
		or _state == State.DASH or _state == State.GATE
	if practicing:
		if move_override_active:
			_player.set_move_input(move_override)
		else:
			_player.set_move_input(_stick.get_value())
	else:
		_player.set_move_input(Vector2.ZERO)
	if _dash_button.visible:
		_dash_button.set_ratio(_player.get_dash_ratio())
	_push_out_of_desk()
	_push_out_of_lumi()
	_apply_keyboard_shift()
	_lumi.face_toward(_player.position.x)
	if _state == State.MOVE:
		_move_accum += _player.position.distance_to(_last_pos)
		_last_pos = _player.position
		if _move_accum >= MOVE_GATE_DISTANCE * _actor_scale:
			_on_move_learned()
	elif _state == State.DASH:
		_last_pos = _player.position
		if _player.is_dashing():
			_on_dash_learned()
	elif _state == State.GATE:
		_last_pos = _player.position
		var inside: bool = _gate_rect.has_point(_player.position)
		if _gate_cooldown and not inside:
			_gate_cooldown = false
		elif _gate_armed and inside and not _gate_cooldown:
			_seal()


## The registry desk is furniture: slide along it, never through it. One
## pixel past the edge, so the hero never reports inside the rect again.
## The exit also stays on the walk floor: the desk's painted top hangs
## above the walk band, so a bare nearest-edge exit can strand the hero
## off the walk, where the player's own bounds clamp drags them back
## into the desk on the next physics tick.
func _push_out_of_desk() -> void:
	if not _desk_rect.has_point(_player.position):
		return
	_player.position = desk_exit_for(
		_player.position, _desk_rect, _walk_rect)


## Nearest point one pixel outside `desk` that stays inside `walk`.
## Pure, so collision math is testable without a window. Each exit
## keeps its untouched axis; the first edge in left/right/top/bottom
## order wins a near-tie, never float rounding.
static func desk_exit_for(point: Vector2, desk: Rect2,
		walk: Rect2) -> Vector2:
	var exits: Array[Vector2] = [
		Vector2(desk.position.x - 1.0, point.y),
		Vector2(desk.end.x + 1.0, point.y),
		Vector2(point.x, desk.position.y - 1.0),
		Vector2(point.x, desk.end.y + 1.0),
	]
	var spans: Array[float] = [
		absf(point.x - desk.position.x),
		absf(point.x - desk.end.x),
		absf(point.y - desk.position.y),
		absf(point.y - desk.end.y),
	]
	var best: int = -1
	for index in exits.size():
		if not _walk_holds(walk, exits[index]):
			continue
		if best < 0 \
				or spans[index] < spans[best] - DESK_TIE_EPSILON:
			best = index
	if best >= 0:
		return exits[best]
	# No real framing lands here: the desk's far side sits inside the
	# walk at every judged size, so the bottom exit always holds.
	# Clamp it into the walk rather than stranding the hero off-floor.
	return Vector2(
		clampf(point.x, walk.position.x, walk.end.x),
		clampf(desk.end.y + 1.0, walk.position.y, walk.end.y))


## The player's bounds clamp holds this point: inclusive on every side,
## matching Player._physics_process rather than Rect2.has_point, which
## drops the far edge.
static func _walk_holds(walk: Rect2, point: Vector2) -> bool:
	return point.x >= walk.position.x and point.x <= walk.end.x \
		and point.y >= walk.position.y and point.y <= walk.end.y


## Lumi holds her ground by the desk; the hero steps around her.
func _push_out_of_lumi() -> void:
	var offset: Vector2 = _player.position - _lumi.position
	var radius: float = LUMI_BODY_RADIUS * _actor_scale
	if offset.length() >= radius:
		return
	if offset.length() < 0.5:
		offset = Vector2.RIGHT * radius
	_player.position = _lumi.position \
		+ offset.normalized() * radius
