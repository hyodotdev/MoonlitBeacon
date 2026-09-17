extends Control

## 3-pick-1 relics that appear when a beacon lights.
##
## **This is the answer to "do it once and done."** Lighting a beacon used to
## raise one number; now it is a fork. Three picks per run, so each run is a
## different character.
##
## `process_mode = ALWAYS`. The game must pause while picking or spirits keep
## charging from behind. Same approach as the pause overlay (`pause_panel`).

signal picked(relic: Relic)
## Panel opened. HUD should clear its banner.
signal banner_cleared

## Everything that can be picked. One `.tres` is one relic.
const POOL: Array[String] = [
	"res://resources/relics/moon_ring.tres",
	"res://resources/relics/moon_ripple.tres",
	"res://resources/relics/long_blade.tres",
	"res://resources/relics/swift_hand.tres",
	"res://resources/relics/sharp_moon.tres",
	"res://resources/relics/wide_arc.tres",
	"res://resources/relics/light_step.tres",
	"res://resources/relics/tough_life.tres",
	"res://resources/relics/moon_dash.tres",
	"res://resources/relics/shadow_veil.tres",
	"res://resources/relics/dew_hunter.tres",
	"res://resources/relics/warm_beacon.tres",
	"res://resources/relics/twin_arrow.tres",
	"res://resources/relics/pierce_arrow.tres",
	"res://resources/relics/quick_arrow.tres",
	"res://resources/relics/heavy_arrow.tres",
]

## Permanent-boon opening gifts are survival and move relics only.
##
## Start holding up to two attack-evolution stacks and long-time players skip
## the basic slash and the 1→2→3-shot growth window whole. Meta growth should
## widen choices, not erase the game's early game.
const SUPPORT_POOL: Array[String] = [
	"res://resources/relics/light_step.tres",
	"res://resources/relics/tough_life.tres",
	"res://resources/relics/moon_dash.tres",
	"res://resources/relics/shadow_veil.tres",
	"res://resources/relics/dew_hunter.tres",
	"res://resources/relics/warm_beacon.tres",
]

## Three evolution paths. Effect-to-path lives in one place,
## `Relic.family_of_effect()`; this only decides card order.
const STARFALL_ROUTE: Array[String] = [
	"res://resources/relics/twin_arrow.tres",
	"res://resources/relics/quick_arrow.tres",
	"res://resources/relics/pierce_arrow.tres",
	"res://resources/relics/heavy_arrow.tres",
]
const FULL_MOON_ROUTE: Array[String] = [
	"res://resources/relics/long_blade.tres",
	"res://resources/relics/swift_hand.tres",
	"res://resources/relics/sharp_moon.tres",
	"res://resources/relics/wide_arc.tres",
]
const MOON_DANCE_ROUTE: Array[String] = [
	"res://resources/relics/moon_ring.tres",
	"res://resources/relics/moon_ripple.tres",
]
const FAMILY_ORDER: Array[Relic.Family] = [
	Relic.Family.STARFALL,
	Relic.Family.FULL_MOON,
	Relic.Family.MOON_DANCE,
]
const ROUTES: Dictionary = {
	Relic.Family.STARFALL: STARFALL_ROUTE,
	Relic.Family.FULL_MOON: FULL_MOON_ROUTE,
	Relic.Family.MOON_DANCE: MOON_DANCE_ROUTE,
}

## Survival relics whose controls, HUD, or chance hit a ceiling first.
##
## Attack relics dump leftover past the cap into damage; dew chance and heart
## cells have no such path. Pull them from the live pool so a "Lv20 and nothing
## happens" card cannot appear.
const MAX_STACKS: Dictionary = {
	"res://resources/relics/dew_hunter.tres": 1,
	"res://resources/relics/shadow_veil.tres": 2,
	"res://resources/relics/warm_beacon.tres": 1,
	"res://resources/relics/light_step.tres": 3,
	"res://resources/relics/tough_life.tres": 1,
	"res://resources/relics/moon_dash.tres": 3,
}

## Keep the name the old debug path uses.
const DISC_ROUTE: Array[String] = STARFALL_ROUTE
const DISC_EVOLVE_AT: int = 3

const CARD_COUNT: int = 3
const NAME_FONT_MAX: int = 14
const NAME_FONT_MIN: int = 9
const NAME_AVAILABLE_WIDTH: float = 156.0
const ROUTE_FONT_MAX: int = 9
const ROUTE_FONT_MIN: int = 7
const ROUTE_AVAILABLE_WIDTH: float = 152.0

@onready var _cards: Array[Button] = [$Center/Rows/Cards/C0, $Center/Rows/Cards/C1, $Center/Rows/Cards/C2]
@onready var _title: Label = $Center/Rows/Title
@onready var _names: Array[Label] = [
	$Center/Rows/Cards/C0/Name, $Center/Rows/Cards/C1/Name, $Center/Rows/Cards/C2/Name]
@onready var _descs: Array[Label] = [
	$Center/Rows/Cards/C0/Desc, $Center/Rows/Cards/C1/Desc, $Center/Rows/Cards/C2/Desc]
@onready var _routes: Array[Label] = [
	$Center/Rows/Cards/C0/Route, $Center/Rows/Cards/C1/Route, $Center/Rows/Cards/C2/Route]

var _offer: Array[Relic] = []
## First pick shows the three paths one card each at equal weight. Shuffle
## the live array every time so no slot looks like the right answer.
var _first_offer_done: bool = false
## Attack path last picked from a card. Picking a survival relic does not change the main.
var _focus: Relic.Family = Relic.Family.NONE
## How many times each relic has been stacked.
##
## At first a picked relic was never offered again. **Then growth stops** —
## eat `Sharp Moonlight` (damage +1) once and it is over; eat all fourteen and
## a level-up gives nothing. People actually said "the weapon never gets
## stronger."
##
## Survivors are the opposite. **Keep stacking the same thing** and damage
## goes from 1 to 6. Stacking is allowed now, and the count sits beside the name.
var _stacks: Dictionary = {}
## A movement finger releasing over a card is not a pick.
##
## On mobile a level-up can open in the middle of a move touch. If the new
## card takes that release, an unseen relic is chosen. After the panel opens,
## lock briefly until every existing pointer is up so **only a fresh press**
## reaches a card.
var _active_touches: Dictionary = {}
var _mouse_left_down: bool = false
var _choice_armed: bool = false
var _offer_generation: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	visible = false
	for i in _cards.size():
		_cards[i].pressed.connect(_on_card_pressed.bind(i))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_active_touches[touch.index] = true
		else:
			_active_touches.erase(touch.index)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_mouse_left_down = mouse.pressed


## Draw three relics and show them. The game pauses.
func open(title: String = "") -> void:
	var offer: Array[Relic] = _draw_offer()
	_first_offer_done = true
	_open_offer(offer, tr("RELIC_PICK") if title.is_empty() else title)


## Guardian rewards differ from a normal level-up. The three attack paths
## show one card each.
##
## Usually one rank; if every beacon in the cycle was overcharged, two.
## `grant_count` rides on card meta so the existing multi-stack grant path is used as-is.
func open_guardian(title: String = "", grant_count: int = 1) -> void:
	_open_offer(_draw_guardian_offer(maxi(grant_count, 1)),
		tr("GUARDIAN_REWARD") if title.is_empty() else title)


func _open_offer(offer: Array[Relic], title: String) -> void:
	_offer = offer
	if _offer.is_empty():
		# Took them all. Nothing to draw: skip — do not show empty cards.
		picked.emit(null)
		return

	_title.text = title
	for i in _cards.size():
		var has: bool = i < _offer.size()
		_cards[i].visible = has
		if not has:
			continue
		var stack: int = int(_offer[i].get_meta("stack", 1))
		var display_name: String = tr(_offer[i].display_name)
		_names[i].text = display_name if stack <= 1 \
			else "%s  Lv %d" % [display_name, stack]
		_fit_name(_names[i])
		_names[i].add_theme_color_override("font_color", _offer[i].accent)
		_descs[i].text = tr(_offer[i].description)
		_set_route_label(i, _offer[i])

	banner_cleared.emit()
	_offer_generation += 1
	var generation: int = _offer_generation
	_choice_armed = false
	for card in _cards:
		card.disabled = true
	visible = true
	modulate.a = 0.0
	get_tree().paused = true
	create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) \
		.tween_property(self, "modulate:a", 1.0, 0.25)
	_arm_choices_after_release(generation)


func _arm_choices_after_release(generation: int) -> void:
	# Observe even the input that opened the panel this frame, then wait for pointers up.
	await get_tree().process_frame
	while visible and generation == _offer_generation \
			and (not _active_touches.is_empty() or _mouse_left_down):
		await get_tree().process_frame
	if not visible or generation != _offer_generation:
		return
	var first_card: Button = null
	for card in _cards:
		card.disabled = false
		if first_card == null and card.visible:
			first_card = card
	_choice_armed = true
	if first_card != null:
		first_card.grab_focus()


## Shrink type only within one line so a long English name does not spill onto a neighbor card.
func _fit_name(label: Label) -> void:
	var font: Font = label.get_theme_font("font")
	var font_size: int = NAME_FONT_MAX
	while font_size > NAME_FONT_MIN \
			and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, font_size).x > NAME_AVAILABLE_WIDTH:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


## The guardian card's `evolution + path + rank` sentence also fits fully on one card line.
func _fit_route(label: Label) -> void:
	var font: Font = label.get_theme_font("font")
	var font_size: int = ROUTE_FONT_MAX
	while font_size > ROUTE_FONT_MIN \
			and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, font_size).x > ROUTE_AVAILABLE_WIDTH:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


## Draw three. **Main, other path, and free pick, one card each.**
##
## Guaranteeing moon wheel every time made every hero converge on Starfall even
## if they started with ring or ripple. First pick is one card per path; after
## that the last-picked path's **still-missing component** is guaranteed. The
## second slot keeps another evolution path so they can switch anytime.
func _draw_offer() -> Array[Relic]:
	var picks: Array[String] = []
	if not _first_offer_done:
		for family in FAMILY_ORDER:
			_append_unique(picks, _next_path(family))
		picks.shuffle()
		return _make_offer(picks, 1)

	var focus: Relic.Family = _focus
	if focus == Relic.Family.NONE or _family_total(focus) <= 0:
		focus = _strongest_family()
	if focus == Relic.Family.NONE:
		focus = FAMILY_ORDER[randi() % FAMILY_ORDER.size()]

	# Slot 1: a missing effect of the main. If complete, push the most-raised axis further.
	_append_unique(picks, _next_path(focus))

	# Slot 2: the less-complete other path. There is always an exit to change mains.
	var alternatives: Array[Relic.Family] = []
	for family in FAMILY_ORDER:
		if family != focus:
			alternatives.append(family)
	alternatives.shuffle()
	alternatives.sort_custom(func(a: Relic.Family, b: Relic.Family) -> bool:
		return _family_distinct(a) < _family_distinct(b))
	if not alternatives.is_empty():
		_append_unique(picks, _next_path(alternatives[0]))

	# Slot 3: free pick that can grow what you have or bring a new survival relic.
	var rest: Array[String] = []
	for path in POOL:
		if not _is_capped(path):
			rest.append(path)
	for path in picks:
		rest.erase(path)
	rest.shuffle()
	rest.sort_custom(func(a: String, b: String) -> bool:
		return int(_stacks.get(a, 0)) > int(_stacks.get(b, 0)))
	if not rest.is_empty():
		var top: int = mini(rest.size(), 4)
		_append_unique(picks, rest[randi() % top])

	# Fill three cards even if resources grow or paths change.
	for path in rest:
		if picks.size() >= CARD_COUNT:
			break
		_append_unique(picks, path)
	picks.shuffle()
	return _make_offer(picks, 1)


## Guardian loot. Three attack paths, exactly one card each, instead of survival stats.
func _draw_guardian_offer(grant_count: int = 1) -> Array[Relic]:
	var picks: Array[String] = []
	for family in FAMILY_ORDER:
		_append_unique(picks, _next_path(family))
	picks.shuffle()
	return _make_offer(picks, maxi(grant_count, 1))


func _make_offer(paths: Array[String], grant_count: int) -> Array[Relic]:
	var out: Array[Relic] = []
	for path in paths.slice(0, CARD_COUNT):
		var loaded: Relic = load(path) as Relic
		if loaded == null:
			continue
		var relic: Relic = loaded.duplicate()
		relic.set_meta("path", path)
		relic.set_meta("grant_count", grant_count)
		relic.set_meta("stack", int(_stacks.get(path, 0)) + grant_count)
		out.append(relic)
	return out


func _append_unique(paths: Array[String], path: String) -> void:
	if not path.is_empty() and not paths.has(path):
		paths.append(path)


func _is_capped(path: String) -> bool:
	if not MAX_STACKS.has(path):
		return false
	return int(_stacks.get(path, 0)) >= int(MAX_STACKS[path])


## Grant a still-missing component first. If complete, fill the least-stacked axis.
##
## Always pushing the most-stacked axis forever picked `Twin Moon Wheel` on
## the first tie, shot count jumped 2→8, and other stats froze at rank 1.
## Raise the four axes evenly one lap at a time so each rank changes shot
## count, speed, pierce, then damage in turn.
func _next_path(family: Relic.Family) -> String:
	var route: Array = ROUTES.get(family, [])
	for entry in route:
		var path: String = str(entry)
		if int(_stacks.get(path, 0)) <= 0:
			return path
	if route.is_empty():
		return ""

	var weakest: String = str(route[0])
	for entry in route:
		var path: String = str(entry)
		if int(_stacks.get(path, 0)) < int(_stacks.get(weakest, 0)):
			weakest = path
	return weakest


func _family_distinct(family: Relic.Family) -> int:
	var distinct: int = 0
	for entry in ROUTES.get(family, []):
		if int(_stacks.get(str(entry), 0)) > 0:
			distinct += 1
	return distinct


func _family_total(family: Relic.Family) -> int:
	var total: int = 0
	for entry in ROUTES.get(family, []):
		total += int(_stacks.get(str(entry), 0))
	return total


func _strongest_family() -> Relic.Family:
	var best: Relic.Family = Relic.Family.NONE
	var best_distinct: int = 0
	var best_total: int = 0
	for family in FAMILY_ORDER:
		var distinct: int = _family_distinct(family)
		var total: int = _family_total(family)
		if distinct > best_distinct or (distinct == best_distinct and total > best_total):
			best = family
			best_distinct = distinct
			best_total = total
	return best


## The card footer previews the state **after** the pick.
func _set_route_label(index: int, relic: Relic) -> void:
	var family: Relic.Family = Relic.family_of_relic(relic)
	if family == Relic.Family.NONE:
		_routes[index].visible = false
		_routes[index].text = ""
		return

	var path: String = str(relic.get_meta("path", ""))
	var grant_count: int = maxi(int(relic.get_meta("grant_count", 1)), 1)
	var distinct: int = _family_distinct(family)
	var preview_distinct: int = distinct + (1 if int(_stacks.get(path, 0)) <= 0 else 0)
	var total: int = _family_total(family)
	var preview_total: int = total + grant_count
	var evolve_at: int = Relic.family_evolve_at(family)
	var required_distinct: int = Relic.family_required_distinct(family)
	var was_evolved: bool = distinct >= required_distinct and total >= evolve_at
	var preview_evolved: bool = preview_distinct >= required_distinct \
		and preview_total >= evolve_at
	var was_resonant: bool = distinct >= Relic.RESONANCE_DISTINCT
	var preview_resonant: bool = preview_distinct >= Relic.RESONANCE_DISTINCT
	var preview_progress: int = mini(preview_total, evolve_at)
	if preview_distinct < required_distinct:
		preview_progress = mini(preview_progress, maxi(evolve_at - 1, 0))
	var family_name: String = tr(Relic.family_name_key(family))

	if not was_evolved and preview_evolved:
		_routes[index].text = tr("CARD_EVOLUTION_NOW") % family_name
	elif not was_resonant and preview_resonant:
		_routes[index].text = tr("CARD_RESONANCE_NOW") % family_name
	elif not preview_evolved:
		_routes[index].text = tr("CARD_EVOLUTION_PROGRESS") % [
			family_name, preview_progress, evolve_at]
	else:
		var preview_tier: int = 1 + maxi(preview_total - evolve_at, 0)
		_routes[index].text = tr("CARD_EVOLUTION_TIER") % [family_name, preview_tier]
	if grant_count > 1:
		_routes[index].text += tr("CARD_DOUBLE_SUFFIX")
	_fit_route(_routes[index])
	_routes[index].visible = true
	_routes[index].add_theme_color_override("font_color", Relic.family_accent(family))


## Grant any one without showing cards. **Tests only.**
##
## Arena uses this to build a late-game state. `_stacks` is raised normally
## so later cards still show the stack count correctly.
## Grant one named relic. Used for a character's opening relic.
##
## Paths not in `POOL` are accepted — character-only relics can be added later.
func take_named(path: String) -> Relic:
	var loaded: Resource = load(path)
	if loaded == null or not (loaded is Relic):
		return null
	var relic: Relic = (loaded as Relic).duplicate()
	relic.set_meta("path", path)
	_stacks[path] = int(_stacks.get(path, 0)) + 1
	relic.set_meta("stack", _stacks[path])
	return relic


func take_random() -> Relic:
	var path: String = POOL[randi() % POOL.size()]
	var relic: Relic = (load(path) as Relic).duplicate()
	relic.set_meta("path", path)
	_stacks[path] = int(_stacks.get(path, 0)) + 1
	relic.set_meta("stack", _stacks[path])
	return relic


func take_random_support() -> Relic:
	var choices: Array[String] = []
	for path in SUPPORT_POOL:
		if not _is_capped(path):
			choices.append(path)
	if choices.is_empty():
		return null
	return take_named(choices[randi() % choices.size()])


## Build each moon-wheel rank in order for debug device checks.
func take_next_disc() -> Relic:
	return take_next_family(Relic.Family.STARFALL)


## Debug and integration tests take the next component of a given evolution immediately.
func take_next_family(family: Relic.Family) -> Relic:
	var path: String = _next_path(family)
	return null if path.is_empty() else take_named(path)


## After a hit drops a relic or an orb is reclaimed, match rank to the live held list.
##
## Leave pick-count as-is and a card after losing one relic looks one rank
## higher than reality. Offer weights and the `Lv` label must match current power.
func sync_owned(taken: Array) -> void:
	_stacks.clear()
	for relic in taken:
		var path: String = str(relic.get_meta("path", ""))
		if path.is_empty():
			continue
		_stacks[path] = int(_stacks.get(path, 0)) + 1
	if _focus != Relic.Family.NONE and _family_total(_focus) <= 0:
		_focus = _strongest_family()


func _on_card_pressed(index: int) -> void:
	if not _choice_armed or index >= _offer.size():
		return
	_choice_armed = false
	var chosen: Relic = _offer[index]
	var path: String = str(chosen.get_meta("path", ""))
	var grant_count: int = maxi(int(chosen.get_meta("grant_count", 1)), 1)
	_stacks[path] = int(_stacks.get(path, 0)) + grant_count
	chosen.set_meta("stack", _stacks[path])
	var family: Relic.Family = Relic.family_of_relic(chosen)
	if family != Relic.Family.NONE:
		_focus = family

	visible = false
	get_tree().paused = false
	picked.emit(chosen)
