extends Control

## On-screen info. Health, beacon count, time survived.
##
## HUD **decides nothing.** It only draws values the arena reports.
## Whether health 0 ends the run is the arena's call.

## Below this remaining time it turns red.
const URGENT_SECONDS: float = 15.0
## The objective, drawn: a cold brazier per beacon, a lit one once it burns.
## Three glyphs read at a glance in a fight where "Beacons 2/3" needs a read.
const BEACON_ON: Texture2D = preload("res://assets/custom/ui/kit/icon_beacon_on.png")
const BEACON_OFF: Texture2D = preload("res://assets/custom/ui/kit/icon_beacon_off.png")
## Pop played on a brazier the moment it lights.
const BEACON_POP_SECONDS: float = 0.32

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
@onready var _rank: Label = $RightPanel/Row/Rank
@onready var _beacons_label: Label = $RightPanel/Row/Beacons
@onready var _beacon_row: HBoxContainer = $RightPanel/Row/BeaconIcons
var _beacon_icons: Array[TextureRect] = []
@onready var _relics: HBoxContainer = $LeftPanel/Stack/Relics
@onready var _banner: Label = $Banner
@onready var _boss: Control = $Boss
@onready var _boss_fill: Control = $Boss/Fill
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
## False until the arena has sent its first beacon count, so the initial
## "0 lit" state does not play a pop.
var _beacons_ready: bool = false
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
var _omen_keys: Array[String] = []
var _boss_detail: Label = null
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

## Secondary stat lines rest dim and pop to full only when their value changes.
##
## The combat screen used to hold nine bright text elements at once — hearts,
## relic chips, evolution, missile power, missile recovery, moonfire, the
## region caption, the wave/level/kills/timer row, plus a centred banner and a
## combo counter. Everything shouted at the same weight, so nothing read.
##
## Information is not removed. It settles out of the way until it changes, then
## announces itself. Hearts, beacons and the timer never dim — those are the
## three things a dodge game must always show.
const QUIET_HOLD_SECONDS: float = 2.4
const QUIET_REST_ALPHA: float = 0.4
const QUIET_FADE_SPEED: float = 2.6

## `Label -> seconds of full brightness left`.
var _quiet_hold: Dictionary = {}
## `Label -> the text it last showed`, so a setter called every frame with the
## same value does not read as a change.
var _quiet_text: Dictionary = {}


## Start the secondary lines at rest so the first frame is already calm.
func _ready() -> void:
	add_to_group("moonlit_hud")
	for label in _quiet_labels():
		_quiet_text[label] = label.text
		_quiet_hold[label] = 0.0
		label.modulate.a = QUIET_REST_ALPHA


## The lines allowed to dim. Hearts, beacons and the timer are deliberately out.
func _quiet_labels() -> Array[Label]:
	return [_evolution, _missile_power, _missile_recovery, _world,
		_moonfire_label, _kills, _level] as Array[Label]


## Pop a line to full if its rendered text actually changed.
##
## Compare the text, not the call. `set_missile_recovery()` runs every frame
## while a recovery ticks, and `_notification()` replays every setter on a
## language change; neither is news on its own.
func _mark_quiet(label: Label) -> void:
	if label == null:
		return
	if _quiet_text.get(label, "") == label.text:
		return
	_quiet_text[label] = label.text
	_quiet_hold[label] = QUIET_HOLD_SECONDS
	label.modulate.a = 1.0


func _process(delta: float) -> void:
	for label: Label in _quiet_labels():
		if label == null:
			continue
		var hold: float = float(_quiet_hold.get(label, 0.0))
		if hold > 0.0:
			_quiet_hold[label] = maxf(hold - delta, 0.0)
			continue
		if label.modulate.a > QUIET_REST_ALPHA:
			label.modulate.a = maxf(
				label.modulate.a - delta * QUIET_FADE_SPEED, QUIET_REST_ALPHA)


## Snap every secondary line to rest and stop mid-fade.
##
## A store capture compares the state before and after the shot; a line caught
## halfway through fading would make those two frames differ and eject the
## capture. The arena calls this alongside its other capture freezes.
func debug_settle_quiet_labels() -> void:
	for label: Label in _quiet_labels():
		if label == null:
			continue
		_quiet_hold[label] = 0.0
		_quiet_text[label] = label.text
		label.modulate.a = QUIET_REST_ALPHA


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


## Compact cloud-rank chip, pushed by the production host from actual
## coordinator snapshots. The text arrives preformatted with its honest
## source label ("#12 · live"); an empty rank hides the chip instead of
## showing a fake one. Never in the quiet set: the rank stays readable.
func set_cloud_rank(display: String) -> void:
	_rank.text = display
	_rank.visible = not display.strip_edges().is_empty()


## Hide the rank chip: no rank, no cloud, or signed out.
func clear_cloud_rank() -> void:
	_rank.text = ""
	_rank.visible = false


func set_beacons(lit: int, total: int) -> void:
	var previous_lit: int = _lit
	_lit = lit
	_total = total
	_ensure_beacon_icons(total)
	for index in _beacon_icons.size():
		var icon: TextureRect = _beacon_icons[index]
		icon.texture = BEACON_ON if index < lit else BEACON_OFF
		# Only a brazier that just lit gets the pop; a language change or a
		# cycle reset re-runs this with the same count and must stay still.
		if index >= previous_lit and index < lit and _beacons_ready:
			_pop(icon)
	# The label now carries only what the braziers cannot: which wave this is.
	# Cycle 1 does not need it, so the label hides and gives its width back.
	_beacons.visible = _cycle > 1
	if _cycle > Expedition.OFFICIAL_WIN_CYCLE:
		# Past the official win the count is how deep you are, not which wave.
		_beacons.text = tr("HUD_DEPTH") % Expedition.depth(_cycle)
	else:
		_beacons.text = tr("HUD_WAVE") % _cycle if _cycle > 1 else ""
	_beacons_ready = true


## Grow or shrink the brazier strip to `total`, cloning the first cell like the
## hearts do so art and alignment live in the scene and not in code.
func _ensure_beacon_icons(total: int) -> void:
	if _beacon_icons.is_empty():
		_beacon_icons.append(_beacon_row.get_child(0) as TextureRect)
	while _beacon_icons.size() < total:
		var clone: TextureRect = _beacon_icons[0].duplicate() as TextureRect
		_beacon_row.add_child(clone)
		_beacon_icons.append(clone)
	while _beacon_icons.size() > maxi(total, 1):
		_beacon_icons.pop_back().queue_free()


func _pop(icon: TextureRect) -> void:
	icon.pivot_offset = icon.size * 0.5
	icon.scale = Vector2(1.7, 1.7)
	var tween: Tween = create_tween()
	tween.tween_property(icon, "scale", Vector2.ONE, BEACON_POP_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Spirits scattered. Arrived in Chapter 17.
##
## Even at 0, do not vacate the slot. A first-kill cell would shove neighbors.
func set_kills(value: int) -> void:
	_kill_count = value
	_kills.text = tr("HUD_KILLS") % value
	_mark_quiet(_kills)




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
	_mark_quiet(_level)


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
		_mark_quiet(_moonfire_label)
	elif active:
		_moonfire_label.text = tr("HUD_MOONFIRE_ACTIVE")
		_mark_quiet(_moonfire_label)
	else:
		# Write the target count so blue embers are not read as XP or currency.
		_moonfire_label.text = tr("HUD_EMBERS") % mini(roundi(next_ratio * 10.0), 10)
		_mark_quiet(_moonfire_label)
	_moonfire_label.add_theme_color_override("font_color",
		Color(1, 0.82, 0.4, 1) if active else Color(0.66, 0.88, 1, 1))
	_moonfire_gauge.set_state(_moonfire_ratio, active, locked)


## Current terrain and time of day. Killing a guardian changes terrain and
## lighting beacons brings day; keep that flow on one small line. Art-only
## change is easy to misread as a color grade.
func set_world(world_key: String, time_key: String) -> void:
	_world_key = world_key
	_time_key = time_key
	var line: String = tr("HUD_WORLD") % [tr(world_key), tr(time_key)]
	# The rule this place carries rides on the same line: no new node, and it reads as part of
	# where you are.
	for key in _omen_keys:
		line += " · " + tr(key)
	_world.text = line
	_mark_quiet(_world)


## The omens of the zone you are in (translation keys). Empty clears them.
func set_omens(keys: Array[String]) -> void:
	_omen_keys = keys.duplicate()
	set_world(_world_key, _time_key)


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
		_mark_quiet(_evolution)
		return

	var family_name: String = tr(Relic.family_name_key(family))
	if _evolution_progress >= _evolution_at:
		_evolution.text = tr("HUD_EVOLUTION_LEVEL") % [
			family_name, maxi(_evolution_tier, 1)]
	else:
		_evolution.text = tr("HUD_EVOLUTION_PROGRESS") % [
			family_name, _evolution_progress, _evolution_at]
	_evolution.add_theme_color_override("font_color", Relic.family_accent(family))
	_mark_quiet(_evolution)


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
	_mark_quiet(_missile_power)


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
			_mark_quiet(_missile_recovery)
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
## Relic emblem size in the strip.
const RELIC_ICON_SIZE: int = 22


func set_relics(taken: Array) -> void:
	_relic_items = taken.duplicate()
	for chip in _relics.get_children():
		chip.queue_free()

	var count: Dictionary = {}
	var first: Dictionary = {}
	for relic in taken:
		var label: String = relic.display_name
		count[label] = int(count.get(label, 0)) + 1
		if not first.has(label):
			first[label] = relic

	# **Most stacked first.** At level 40 all fourteen kinds gather and names
	# alone fill two rows across the screen and cover the HUD. Only saw it
	# after actually shooting that screen. Reading a build needs **a few
	# mains**, not everything.
	var names: Array = count.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		return int(count[a]) > int(count[b]))

	for i in mini(names.size(), CHIP_LIMIT):
		var label: String = str(names[i])
		_relics.add_child(_make_chip(first[label] as Relic, int(count[label])))

	if names.size() > CHIP_LIMIT:
		var more: Label = Label.new()
		more.text = "+%d" % (names.size() - CHIP_LIMIT)
		more.add_theme_color_override("font_color", Color(0.78, 0.8, 0.86, 1))
		more.add_theme_font_override("font", _evolution.get_theme_font("font"))
		more.add_theme_font_size_override("font_size", 9)
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_relics.add_child(more)


## One relic in the strip: its emblem, and a `×N` corner badge once it has stacked.
##
## Emblems read at a glance and take a third of the width the names did. A relic
## with no emblem yet falls back to the old text chip, so a new `.tres` never
## renders as a blank gap while its art is still on the way.
func _make_chip(relic: Relic, stack: int) -> Control:
	if relic.icon == null:
		var text_chip: Label = Label.new()
		text_chip.set_meta("relic", relic.display_name)
		text_chip.text = tr(relic.display_name) if stack <= 1 \
			else "%s ×%d" % [tr(relic.display_name), stack]
		text_chip.add_theme_color_override("font_color", relic.accent)
		text_chip.add_theme_font_override("font", _evolution.get_theme_font("font"))
		text_chip.add_theme_font_size_override("font_size", 9)
		text_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return text_chip

	# Two nodes per relic, not three: the emblem itself, and its `×N` pinned to the
	# emblem's bottom-right corner like a stack count on an inventory slot. A
	# side-by-side icon and label needs a container node on top, and every node in
	# the arena counts against the late-game budget.
	var chip: TextureRect = TextureRect.new()
	chip.set_meta("relic", relic.display_name)
	chip.texture = relic.icon
	chip.custom_minimum_size = Vector2(RELIC_ICON_SIZE, RELIC_ICON_SIZE)
	chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# The emblems are 48px art shown at 22: a filtered downscale, where the
	# project's default nearest filter would drop every other pixel into noise.
	chip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge: Label = Label.new()
	badge.name = &"Count"
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	badge.offset_right = 4.0
	badge.offset_bottom = 3.0
	badge.add_theme_color_override("font_color", Color(1, 0.95, 0.8, 1))
	badge.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.14, 1))
	badge.add_theme_constant_override("outline_size", 4)
	badge.add_theme_font_override("font", _evolution.get_theme_font("font"))
	badge.add_theme_font_size_override("font_size", 9)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(badge)
	_set_chip_count(chip, relic, stack)
	return chip


func _set_chip_count(chip: Control, relic: Relic, stack: int) -> void:
	if chip is Label:
		(chip as Label).text = "%s ×%d" % [tr(relic.display_name), stack] \
			if stack > 1 else tr(relic.display_name)
		return
	var badge: Label = chip.get_node_or_null("Count") as Label
	if badge != null:
		badge.text = "×%d" % stack
		badge.visible = stack > 1


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
	# Chips that keep growing fill the left of the screen.
	for existing in _relics.get_children():
		if str(existing.get_meta("relic", "")) != relic.display_name:
			continue
		_set_chip_count(existing as Control, relic, stack)
		existing.scale = Vector2(1.4, 1.4)
		existing.create_tween().tween_property(existing, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return

	var chip: Control = _make_chip(relic, stack)
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
		accent: Color = Color(0.86, 0.42, 0.5, 1),
		detail: String = "") -> void:
	if _boss.visible != alive:
		_boss.visible = alive
		if alive:
			_boss.modulate.a = 0.0
			create_tween().tween_property(_boss, "modulate:a", 1.0, 0.3)
	if not alive:
		return
	_boss_name.text = boss_name
	_boss_name.add_theme_color_override("font_color", accent)
	_set_boss_detail(detail, accent)
	_boss_fill.anchor_right = clampf(ratio, 0.0, 1.0)
	# The rounded fill cannot draw below its own two end caps, so a nearly empty
	# bar hides instead of turning into a smear.
	_boss_fill.visible = ratio > 0.02
	# Low remaining glows red. The finish is visible. The fill texture is neutral
	# white, so tinting it is the whole colour.
	_boss_fill.self_modulate = Color(1, 0.35, 0.32, 1) if ratio < 0.3 else accent


## A small line under the bar naming what this guardian has gained. Built the first time a
## mutated guardian appears, so a plain fight adds no node.
func _set_boss_detail(detail: String, accent: Color) -> void:
	if detail.is_empty() and _boss_detail == null:
		return
	if _boss_detail == null:
		_boss_detail = Label.new()
		_boss_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_boss_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Hangs just under the bar, as wide as the bar.
		_boss_detail.anchor_left = 0.0
		_boss_detail.anchor_right = 1.0
		_boss_detail.anchor_top = 1.0
		_boss_detail.anchor_bottom = 1.0
		_boss_detail.offset_top = 2.0
		_boss_detail.offset_bottom = 14.0
		_boss_detail.add_theme_font_override("font", _boss_name.get_theme_font("font"))
		_boss_detail.add_theme_font_size_override("font_size", 9)
		_boss_detail.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.9))
		_boss_detail.add_theme_constant_override("outline_size", 3)
		_boss.add_child(_boss_detail)
	_boss_detail.text = detail
	_boss_detail.visible = not detail.is_empty()
	_boss_detail.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.35))


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
