extends Control

## On-screen info. Health, beacon count, time survived.
##
## HUD **decides nothing.** It only draws values the arena reports.
## Whether health 0 ends the run is the arena's call.

## Below this remaining time it turns red.
const URGENT_SECONDS: float = 15.0

const CALM_COLOR: Color = Color(0.87, 0.91, 1, 1)
const URGENT_COLOR: Color = Color(1, 0.62, 0.55, 1)

## Heart cells. One lives in the scene; the rest are clones of it.
##
## Chapter 18 raised health from 3 to 5. Hand-adding cells in the scene
## writes max health in **two places, the scene and `arena.gd`**, and they
## drift. H0–H2 were baked in, so raising `MAX_HEALTH` to 5 still showed
## three hearts.
@onready var _heart_row: HBoxContainer = $LeftPanel/Stack/Hearts
var _hearts: Array[TextureRect] = []
@onready var _beacons: Label = $RightPanel/Row/Beacons
@onready var _time: Label = $RightPanel/Row/Time
@onready var _kills: Label = $RightPanel/Row/Kills
@onready var _level: Label = $RightPanel/Row/Level
@onready var _beacons_label: Label = $RightPanel/Row/Beacons
@onready var _relics: HBoxContainer = $LeftPanel/Stack/Relics
@onready var _banner: Label = $Banner
@onready var _boss: Control = $Boss
@onready var _boss_fill: ColorRect = $Boss/Fill
@onready var _boss_name: Label = $Boss/Name
@onready var _combo: Label = $Combo
@onready var _moonfire_label: Label = $LeftPanel/Stack/MoonfireRow/Label
@onready var _moonfire_gauge: Control = $LeftPanel/Stack/MoonfireRow/Gauge
@onready var _world: Label = $World
@onready var _evolution: Label = $LeftPanel/Stack/Evolution
@onready var _missile_power: Label = $LeftPanel/Stack/MissilePower
@onready var _missile_recovery: Label = $LeftPanel/Stack/MissileRecovery

## Language changes need a redraw, so the last values are kept.
var _lit: int = 0
var _total: int = 0
var _kill_count: int = 0
var _cycle: int = 1
var _moonfire_ratio: float = 0.0
var _moonfire_active: bool = false
var _moonfire_locked: bool = false
var _moonfire_initialized: bool = false
var _moonfire_fill_step: int = -1
var _world_key: String = "WORLD_FOREST"
var _time_key: String = "TIME_NIGHT"
var _evolution_family: Relic.Family = Relic.Family.NONE
var _evolution_progress: int = 0
var _evolution_tier: int = 0
var _evolution_at: int = Relic.DEFAULT_EVOLVE_AT
var _missile_level: int = 0
var _missile_max: int = 8
var _missile_progress: int = 0
var _missile_needed: int = 2
var _missile_waiting: bool = false
var _recovery_active: bool = false
var _recovery_seconds: float = 0.0
var _recovery_whole: int = -1
var _recovery_direction: Vector2 = Vector2.UP
var _combo_count: int = 0
var _whole_seconds: int = -1
## Source list so already-picked relic chips retranslate on a language change.
var _relic_items: Array = []
## One current tween so a new banner is not killed by the previous one's exit tween.
var _banner_tween: Tween = null
var _banner_suppressed: bool = false
var _banner_visible_before_suppression: bool = false
## Freeze the banner only while store device capture reads a verified frame.
## Only an Arena on a debug APK that consumed an explicit request file can turn this on.
var _debug_capture_banner_locked: bool = false


## Language can change while paused. The engine only auto-updates text written
## in the scene. **Code-filled spots listen to this and redraw themselves.**
func _notification(what: int) -> void:
	# This notification can arrive before `_ready()`. `@onready` may still be empty.
	if what == NOTIFICATION_TRANSLATION_CHANGED and _beacons != null:
		set_beacons(_lit, _total)
		set_kills(_kill_count)
		_moonfire_initialized = false
		set_moonfire(_moonfire_ratio, _moonfire_active, _moonfire_locked)
		set_world(_world_key, _time_key)
		set_evolution(_evolution_family, _evolution_progress,
			_evolution_tier, _evolution_at)
		set_missile_power(
			_missile_level, _missile_max, _missile_progress,
			_missile_needed, _missile_waiting)
		set_missile_recovery(
			_recovery_seconds, _recovery_direction, _recovery_active)
		set_relics(_relic_items)
		set_combo(_combo_count, _combo_tier)


## How many heart cells. The arena passes `MAX_HEALTH`.
##
## Clone the first cell in the scene as the template. Art, size, and alignment
## do not have to be written again.
func set_max_health(count: int) -> void:
	var template: TextureRect = _heart_row.get_child(0) as TextureRect
	_hearts = [template]
	# Delete leftover cells in the scene besides the template.
	for extra in _heart_row.get_children().slice(1):
		extra.queue_free()
	for i in maxi(count - 1, 0):
		var heart: TextureRect = template.duplicate() as TextureRect
		_heart_row.add_child(heart)
		_hearts.append(heart)


## Empty hearts do not swap art — **only alpha drops.**
## The sheet has an empty heart, but swapping two frames makes the cell jitter.
func set_health(value: int) -> void:
	for i in _hearts.size():
		_hearts[i].modulate.a = 1.0 if i < value else 0.24


func set_beacons(lit: int, total: int) -> void:
	_lit = lit
	_total = total
	# From cycle 2, show which cycle it is. Cycle 1 does not need the extra.
	if _cycle > 1:
		_beacons.text = tr("HUD_BEACONS_CYCLE") % [lit, total, _cycle]
	else:
		_beacons.text = tr("HUD_BEACONS") % [lit, total]


## Spirits scattered. Arrived in Chapter 17.
##
## Even at 0, do not vacate the slot. A first-kill cell would shove neighbors.
func set_kills(value: int) -> void:
	_kill_count = value
	_kills.text = tr("HUD_KILLS") % value




## Time survived. **It counts up, not down.**
##
## The countdown is gone. Put an ending clock on an endlessly growing game
## and the run ends before growth starts. This number is now the record.
func set_survived(seconds: float) -> void:
	var whole: int = int(seconds)
	if whole == _whole_seconds:
		return
	_whole_seconds = whole
	_time.text = "%d:%02d" % [whole / 60, whole % 60]
	_time.add_theme_color_override("font_color", CALM_COLOR)


## Current level.
func set_level(value: int) -> void:
	_level.text = tr("HUD_LEVEL") % value


## How far to the next level. 0–1.
##
## No numbers. Making people read "7/13" is noisy, and all they need is
## "is it about to rise." Show it as the type getting brighter.
func set_level_progress(ratio: float) -> void:
	_level.modulate.a = 0.45 + 0.55 * clampf(ratio, 0.0, 1.0)


## Draw moon-ember charge and awakening duration on the same gauge.
func set_moonfire(ratio: float, active: bool, locked: bool) -> void:
	var next_ratio: float = clampf(ratio, 0.0, 1.0)
	var fill_step: int = roundi(next_ratio * 60.0)
	var state_changed: bool = not _moonfire_initialized \
		or _moonfire_active != active or _moonfire_locked != locked
	_moonfire_ratio = next_ratio
	_moonfire_active = active
	_moonfire_locked = locked
	if not state_changed and fill_step == _moonfire_fill_step:
		return
	_moonfire_initialized = true
	_moonfire_fill_step = fill_step
	if locked:
		_moonfire_label.text = tr("HUD_MOONFIRE_LOCKED")
	elif active:
		_moonfire_label.text = tr("HUD_MOONFIRE_ACTIVE")
	else:
		# Write the target count so blue embers are not read as XP or currency.
		_moonfire_label.text = tr("HUD_EMBERS") % mini(roundi(next_ratio * 10.0), 10)
	_moonfire_label.add_theme_color_override("font_color",
		Color(1, 0.82, 0.4, 1) if active else Color(0.66, 0.88, 1, 1))
	_moonfire_gauge.set_state(_moonfire_ratio, active, locked)


## Current terrain and time of day. Killing a guardian changes terrain and
## lighting beacons brings day; keep that flow on one small line. Art-only
## change is easy to misread as a color grade.
func set_world(world_key: String, time_key: String) -> void:
	_world_key = world_key
	_time_key = time_key
	_world.text = tr("HUD_WORLD") % [tr(world_key), tr(time_key)]


## Briefly show only the evolution currently being pushed.
##
## All three paths on one line is longer than the moonlight gauge in English
## and invades screen center. Cards show all three; combat HUD keeps only the
## last-changed main.
func set_evolution(family: Relic.Family, progress: int, tier: int,
		evolve_at: int = 0) -> void:
	_evolution_family = family
	_evolution_progress = maxi(progress, 0)
	_evolution_tier = maxi(tier, 0)
	_evolution_at = Relic.family_evolve_at(family) if evolve_at <= 0 \
		else maxi(evolve_at, 1)

	if family == Relic.Family.NONE:
		_evolution.text = tr("HUD_EVOLUTION_PICK")
		_evolution.add_theme_color_override("font_color",
			Relic.family_accent(Relic.Family.NONE))
		return

	var family_name: String = tr(Relic.family_name_key(family))
	if _evolution_progress >= _evolution_at:
		_evolution.text = tr("HUD_EVOLUTION_LEVEL") % [
			family_name, maxi(_evolution_tier, 1)]
	else:
		_evolution.text = tr("HUD_EVOLUTION_PROGRESS") % [
			family_name, _evolution_progress, _evolution_at]
	_evolution.add_theme_color_override("font_color", Relic.family_accent(family))


## Compat path while existing Arena and debug tools move onto the new state API.
func set_disc(invest: int, evolve_at: int) -> void:
	var safe_at: int = maxi(evolve_at, 1)
	set_evolution(Relic.Family.STARFALL, mini(maxi(invest, 0), safe_at),
		1 + maxi(invest - safe_at, 0) if invest >= safe_at else 0, safe_at)


## Missile rank grown from kill cores, and progress to the next core.
func set_missile_power(
		level: int,
		max_level: int,
		progress: int,
		needed: int,
		waiting: bool = false) -> void:
	_missile_max = maxi(max_level, 1)
	_missile_level = clampi(level, 0, _missile_max)
	_missile_needed = maxi(needed, 1)
	_missile_progress = clampi(progress, 0, _missile_needed)
	_missile_waiting = waiting
	if _missile_waiting:
		_missile_power.text = tr("HUD_MISSILE_CORE_WAITING") % [
			_missile_level, _missile_max]
	elif _missile_level >= _missile_max:
		_missile_power.text = tr("HUD_MISSILE_MAX") % [
			_missile_level, _missile_max]
	else:
		_missile_power.text = tr("HUD_MISSILE_POWER") % [
			_missile_level, _missile_max, _missile_progress, _missile_needed]
	_missile_power.add_theme_color_override(
		"font_color",
		Color(1.0, 0.82, 0.42, 1)
			if _missile_level >= MissileProgression.HOMING_AT
			else Color(0.58, 0.86, 1.0, 1))


## Lifetime and direction of a core dropped by a hit.
##
## Even if the core flings off camera, an edge arrow keeps pointing. Type and
## marks stay orange-red so it does not mix with ordinary blue kill cores.
func set_missile_recovery(
		seconds_left: float,
		direction: Vector2,
		active: bool = true) -> void:
	_recovery_active = active
	_recovery_seconds = maxf(seconds_left, 0.0)
	if direction.length_squared() > 0.001:
		_recovery_direction = direction.normalized()
	var whole: int = ceili(_recovery_seconds)
	if _recovery_whole != whole or _missile_recovery.visible != active:
		_recovery_whole = whole
		_missile_recovery.visible = active
		if active:
			_missile_recovery.text = tr("HUD_MISSILE_RECOVERY") % whole
	queue_redraw()


func clear_missile_recovery() -> void:
	if not _recovery_active:
		return
	set_missile_recovery(0.0, _recovery_direction, false)


func _draw() -> void:
	if not _recovery_active:
		return
	var direction: Vector2 = _recovery_direction
	if direction.length_squared() <= 0.001:
		direction = Vector2.UP
	var center: Vector2 = size * 0.5
	var half: Vector2 = Vector2(
		maxf(size.x * 0.5 - 28.0, 1.0),
		maxf(size.y * 0.5 - 28.0, 1.0))
	var edge_scale: float = minf(
		half.x / maxf(absf(direction.x), 0.001),
		half.y / maxf(absf(direction.y), 0.001))
	var at: Vector2 = center + direction * edge_scale
	var side: Vector2 = direction.orthogonal()
	var pulse: float = 0.5 + 0.5 * sin(
		float(Time.get_ticks_msec()) * 0.012)
	draw_circle(at, 11.0 + 2.0 * pulse, Color(1.0, 0.22, 0.06, 0.2))
	draw_arc(
		at, 10.0 + 2.0 * pulse, 0.0, TAU, 24,
		Color(1.0, 0.42, 0.12, 0.9), 2.0, true)
	draw_colored_polygon(
		PackedVector2Array([
			at + direction * 11.0,
			at - direction * 5.0 + side * 6.0,
			at - direction * 5.0 - side * 6.0,
		]),
		Color(1.0, 0.74, 0.24, 0.98))


## Stack picked relics on the left.
##
## Seeing what you gathered is the taste of building a loadout. Invisible and
## they forget after picking, then the next pick is thoughtless.
## Redraw the held relic list whole.
##
## Needed **when a relic is dropped.** `add_relic` only knows how to add, so
## there is no way to erase a loss. Recreating a few chips is cheap — call
## only on a hit.
## Unfold at most three so long English names do not invade locale/time.
const CHIP_LIMIT: int = 3


func set_relics(taken: Array) -> void:
	_relic_items = taken.duplicate()
	for chip in _relics.get_children():
		chip.queue_free()

	var count: Dictionary = {}
	var tone: Dictionary = {}
	for relic in taken:
		var label: String = relic.display_name
		count[label] = int(count.get(label, 0)) + 1
		tone[label] = relic.accent

	# **Most stacked first.** At level 40 all fourteen kinds gather and names
	# alone fill two rows across the screen and cover the HUD. Only saw it
	# after actually shooting that screen. Reading a build needs **a few
	# mains**, not everything.
	var names: Array = count.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		return int(count[a]) > int(count[b]))

	for i in mini(names.size(), CHIP_LIMIT):
		var label: String = str(names[i])
		var chip: Label = Label.new()
		chip.set_meta("relic", label)
		var many: int = int(count[label])
		var display_name: String = tr(label)
		chip.text = display_name if many <= 1 else "%s ×%d" % [display_name, many]
		chip.add_theme_color_override("font_color", tone[label])
		chip.add_theme_font_override("font", _evolution.get_theme_font("font"))
		chip.add_theme_font_size_override("font_size", 9)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_relics.add_child(chip)

	if names.size() > CHIP_LIMIT:
		var more: Label = Label.new()
		more.text = "+%d" % (names.size() - CHIP_LIMIT)
		more.add_theme_color_override("font_color", Color(0.78, 0.8, 0.86, 1))
		more.add_theme_font_override("font", _evolution.get_theme_font("font"))
		more.add_theme_font_size_override("font_size", 9)
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_relics.add_child(more)


func add_relic(relic: Relic) -> void:
	_relic_items.append(relic)
	var stack: int = 0
	for item in _relic_items:
		if item.display_name == relic.display_name:
			stack += 1

	# From the fourth kind, re-sort everything and fold to the top three plus
	# `+N`. The live pick path once moved onto this function and bypassed
	# `set_relics()`'s cap.
	var unique: Dictionary = {}
	for item in _relic_items:
		unique[item.display_name] = true
	if unique.size() > CHIP_LIMIT:
		set_relics(_relic_items)
		return

	# If it already exists, raise rank only — no new chip.
	# Chips that keep growing fill the left of the screen with names.
	for existing in _relics.get_children():
		if str(existing.get_meta("relic", "")) != relic.display_name:
			continue
		existing.text = "%s ×%d" % [tr(relic.display_name), stack]
		existing.scale = Vector2(1.4, 1.4)
		existing.create_tween().tween_property(existing, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return

	var chip: Label = Label.new()
	chip.set_meta("relic", relic.display_name)
	chip.text = tr(relic.display_name)
	chip.add_theme_color_override("font_color", relic.accent)
	chip.add_theme_font_override("font", _evolution.get_theme_font("font"))
	chip.add_theme_font_size_override("font_size", 9)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relics.add_child(chip)

	# Pop when it attaches. Appear quietly and they miss it.
	chip.modulate.a = 0.0
	chip.scale = Vector2(1.6, 1.6)
	var pop: Tween = chip.create_tween()
	pop.set_parallel(true)
	pop.tween_property(chip, "modulate:a", 1.0, 0.3)
	pop.tween_property(chip, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Which cycle. Lighting three beacons and downing the guardian raises it by one.
func set_cycle(value: int) -> void:
	_cycle = value
	set_beacons(_lit, _total)


## Brief banner in screen center.
##
## Lighting three beacons spawns a guardian off-screen, and **tell them
## nothing and they do not know what happened.** "After lighting all three,
## where do I go" was asked twice. An arrow is not enough — they must
## **know** first, then look.
## Guide banner. `hold` can lengthen the stay.
##
## Default 1.5s is tuned for in-combat notices. A first-learn sentence needs
## time to read; on device people said "the tutorial never shows" — it did,
## then vanished as soon as they started moving.
func announce(text: String, tone: Color, hold: float = 1.5) -> void:
	if _debug_capture_banner_locked:
		return
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.text = text
	_banner.add_theme_color_override("font_color", tone)
	# Even a long English weaken line's intro pop must not clip off-screen.
	# Short copy keeps the existing 1.3× pop; only long copy shrinks type
	# and start scale as needed.
	var font: Font = _banner.get_theme_font("font")
	var font_size: int = 20
	var safe_width: float = get_viewport_rect().size.x - 48.0
	while font_size > 14 and font.get_string_size(text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > safe_width:
		font_size -= 1
	_banner.add_theme_font_size_override("font_size", font_size)
	var text_width: float = font.get_string_size(text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var pop_scale: float = minf(1.3, safe_width / maxf(text_width, 1.0))
	pop_scale = maxf(pop_scale, 1.0)
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(pop_scale, pop_scale)
	if _banner_suppressed:
		_banner_visible_before_suppression = true
	_banner.visible = not _banner_suppressed

	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(hold)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.5)
	_banner_tween.chain().tween_callback(func() -> void: _banner.visible = false)


## Hide the center banner briefly so it does not show through the pause title.
## Tree and Tween are paused too, so keep visibility instead of deleting, and
## resume from remaining time.
func set_banner_suppressed(value: bool) -> void:
	if _banner_suppressed == value:
		return
	_banner_suppressed = value
	if value:
		_banner_visible_before_suppression = _banner.visible
		_banner.visible = false
	else:
		_banner.visible = _banner_visible_before_suppression
		_banner_visible_before_suppression = false


## Debug-APK store device capture only. Pin the translated live banner fully
## opaque so a scheduled raid, moon-ember notice, or exit Tween cannot cover
## the capture frame.
func debug_lock_capture_banner(text: String, tone: Color) -> void:
	if not OS.is_debug_build():
		return
	_debug_capture_banner_locked = false
	announce(text, tone)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = null
	_banner.modulate.a = 1.0
	_banner.scale = Vector2.ONE
	_banner.visible = not _banner_suppressed
	if _banner_suppressed:
		_banner_visible_before_suppression = true
	_debug_capture_banner_locked = true


## JSON used by capture automation holds HUD's actual display state, not intended copy.
func debug_capture_banner_snapshot() -> Dictionary:
	if not OS.is_debug_build():
		return {}
	return {
		"locked": _debug_capture_banner_locked,
		"visible": _banner.visible and _banner.modulate.a >= 0.999,
		"text": _banner.text,
	}


func debug_unlock_capture_banner() -> void:
	if not OS.is_debug_build():
		return
	_debug_capture_banner_locked = false
	clear_banner()


## Clear the banner immediately.
##
## Called when the relic panel opens. **A leftover notice behind a paused
## screen overlaps the title** — "spirits are swarming" and "moonlight offers
## a gift" actually stacked on one line. The game is paused anyway, so there
## is no reason to read it.
func clear_banner() -> void:
	if _debug_capture_banner_locked:
		return
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	if _banner_suppressed:
		_banner_visible_before_suppression = false
	_banner.visible = false
	_banner.modulate.a = 0.0


## Guardian health bar. On screen only while it is alive.
##
## **No HP on a boss and you cannot tell if hitting is doing anything.**
## People actually asked "I keep hitting this, is the health even going down?"
## A guardian takes thirty hits to fall (~16s); with no display those 16s
## feel like forever.
func set_boss(
		alive: bool,
		ratio: float = 1.0,
		boss_name: String = "",
		accent: Color = Color(0.86, 0.42, 0.5, 1)) -> void:
	if _boss.visible != alive:
		_boss.visible = alive
		if alive:
			_boss.modulate.a = 0.0
			create_tween().tween_property(_boss, "modulate:a", 1.0, 0.3)
	if not alive:
		return
	_boss_name.text = boss_name
	_boss_name.add_theme_color_override("font_color", accent)
	_boss_fill.anchor_right = clampf(ratio, 0.0, 1.0)
	# Low remaining glows red. The finish is visible.
	_boss_fill.color = Color(1, 0.35, 0.32, 1) if ratio < 0.3 else accent


func debug_boss_visible() -> bool:
	return OS.is_debug_build() and _boss.visible and _boss.is_visible_in_tree() \
		and not _boss_name.text.strip_edges().is_empty()


## Kill streak. Hotter and larger as it climbs.
##
## A number alone is "so what." **Grow and flush color when the rank rises**
## so chaining kills being worth it arrives in the eye, not only the hand.
const COMBO_TONES: Array[Color] = [
	Color(0.85, 0.9, 1, 1), Color(1, 0.92, 0.7, 1), Color(1, 0.82, 0.5, 1),
	Color(1, 0.68, 0.4, 1), Color(1, 0.52, 0.36, 1), Color(1, 0.38, 0.34, 1),
]

var _combo_tier: int = 0


func set_combo(count: int, tier: int) -> void:
	_combo_count = count
	if count <= 0:
		_combo.visible = false
		_combo_tier = 0
		return

	_combo.visible = true
	_combo.text = tr("HUD_COMBO") % count
	_combo.add_theme_color_override("font_color", COMBO_TONES[mini(tier, COMBO_TONES.size() - 1)])
	_combo.add_theme_font_size_override("font_size", 13 + 3 * tier)

	# Pop only the instant rank rises. Every kill would be noisy.
	if tier <= _combo_tier:
		return
	_combo_tier = tier
	_combo.scale = Vector2(1.5, 1.5)
	create_tween().tween_property(_combo, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
