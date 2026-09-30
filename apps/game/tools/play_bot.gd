extends Node

## A player that plays the real game, one to two loops a run, and writes down how it went.
##
## The soak (`soak_run.gd`) stands still and cannot die, so it can only say whether the night's growth
## keeps pace with the player's. This one **walks**: it goes for the beacon, waits inside its ring while
## it fills, runs for the gate, picks a card when one opens, holds a comfortable distance from a guardian
## and steps out of what a guardian marks on the floor. It is not superhuman and not clumsy: it looks about
## ten times a second (a decision every 0.1 s), it notices a warning `react=` seconds after it appears (a
## quarter of a second, a person's reaction), it tries every direction both as a run and as a short
## sidestep, and it dashes when a dash lands somewhere better than walking does. Everything it reads is
## something a player can see: positions, the bolts in flight, the circles and lanes on the floor, and the
## wedge, the rays of a ring and the ghost of an echo, which it takes from the same lists the telegraph is
## drawn from (`Spirit.volley_shape()`), so it can never read more than the picture shows.
##
## It is a proxy, not a person, and its deaths are a floor: it dies in the first loop of the 2.1.0 game too.
## What it is good for is telling two versions of the game apart and finding what a stand-still soak cannot.
## Arguments (`-- key=value`): runs seed speed loops tag shots verbose overcharge react trace echo farm heroes
## starts (the cycle each run begins at; above 1 it uses the debug boost) sturdy guardians (the place each
## run's guardian is fought in: 0 forest 1 field 2 camp 3 frost 4 marsh 5 ruins) gauntlet (one guardian fight
## a run) stand shield.
##
## What it writes down is what a person would feel: where the hits came from, how long a beacon took to
## light under pressure, whether it ever got stuck, how a guardian fight went, how the frame time held.
## A run ends after one or two loops (an endless game is judged by its loops, not by its end): the bot
## takes the next cycle for the first loop and cashes out on the last, so the result route runs too.
##
## Headless and fast, with a throwaway HOME:
##
##     HOME=$(mktemp -d) MOONLIT_VAULT_TEST_ROOT=$HOME node scripts/godot.mjs --headless --path apps/game \
##         res://tools/play_bot.tscn -- runs=10 seed=3 speed=3 loops=2 tag=first
##
## Windowed, real time, with screenshots at the moments that matter (run it in the foreground):
##
##     node scripts/godot.mjs --path apps/game res://tools/play_bot.tscn -- runs=2 speed=1 shots=1 tag=look
##
## Output: one `PLAY {...}` line per run on stdout, a table at the end, `builds/play/<tag>.json`, and
## with `shots=1` PNGs under `builds/play/<tag>/`. Lives in `tools/`, which `_runtime_fingerprint()`
## excludes.

const ARENA: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const OUT: String = "res://../../builds/play"
const HERO_IDS: Array[String] = ["warden", "dancer", "keeper", "knight", "eclipse", "sage"]
const PLACES: Array[String] = ["forest", "field", "camp", "frost", "marsh", "ruins"]
const VOLLEY_STYLES: Array[String] = ["forest", "field", "camp", "gale", "leap", "glyph"]

## A decision every tenth of a second: what a player's eyes and thumb manage without effort.
const DECISION_SECONDS: float = 0.1
## Seconds spent fighting before the bot heads for a zone's beacon. A player who rushes arrives at the
## guardian a few levels short; the soak's sixty seconds a zone is what a careful one does.
const FARM_SECONDS: float = 48.0
## Inside this distance of a beacon's centre the bot stands still and lets it fill.
const HOLD_RADIUS: float = 18.0
const SAMPLE_TIMES: Array[float] = [0.15, 0.35, 0.6, 0.9, 1.3]
const DIRECTIONS: int = 16
## How near a spirit may come before a player bothers to step aside, and how much it matters. A touch is at
## eleven pixels; the slash only reaches thirty-four, so a player who never lets one close in never kills.
const MOB_REACH: float = 26.0
const MOB_WEIGHT: float = 0.12
## A bolt's own radius and the body it would meet: what a person keeps clear of.
const BODY_DANGER: float = 14.0
## A small bullet's hit circle and the body it would meet, with a little room.
const BULLET_DANGER: float = 14.0
const BULLET_SOURCES: Array[String] = ["none", "caster", "weaver", "wisp", "aura", "stream"]
## How long before an echo repeats a volley its ghost is on the floor (the game's `ECHO_WARN`).
const ECHO_WARN: float = 0.7
## A run is given this long, in game seconds, before it is called a soft-lock.
const RUN_CAP_SECONDS: float = 2400.0
## No progress toward the goal for this long is a "stuck" event.
const STUCK_SECONDS: float = 7.0

var _runs: int = 10
var _seed: int = 3
var _speed: float = 3.0
var _loops_max: int = 2
var _tag: String = "play"
var _shots: bool = false
var _verbose: bool = false
var _heroes: Array[String] = HERO_IDS.duplicate()
var _overcharge_share: float = 0.3
## Seconds before the bot notices a warning on the floor: a person's reaction. A warning that lasts less than
## this cannot be answered, one that lasts a little more can only just be.
var _react: float = 0.25
## Print one line a decision while a guardian's warning is up: where the bot is, what it costs to stand there,
## which way it chose and whether it dashed.
var _trace: bool = false
## Whether the ghost of an echo is read as a warning (it is drawn, so a person sees it); off to measure what it is worth.
var _read_echoes: bool = true
## Shrink the farm time (a smoke test that only needs the flow).
var _farm_scale: float = 1.0
## Diagnostics: stand still, and/or be invulnerable, to tell what the bot's walking changes.
var _stand: bool = false
var _shield: bool = false
## Cycles the runs start at. 1 is a fresh run; a later one is built the way the debug presets build it:
## the level's relics granted up front and the night as tough as that cycle makes it. A run of one or two
## loops cannot reach the places that open at cycle 3, or Depth, any other way.
var _starts: Array[int] = [1]
var _start_cycle: int = 1
## A guardian fight made this many times longer, so a pattern can be watched being answered rather than
## ended by a strong build in half a minute; and, optionally, the places whose guardian the runs go to
## (the route is fixed, one gate, so the third zone is the one wanted).
var _sturdy: float = 1.0
## Go straight to the guardian: the arena's own debug route lights the three beacons and crosses the gates
## for the bot, so a run is nothing but the fight, and a dozen guardians can be watched in the time two
## zones take.
var _gauntlet: bool = false
var _guardian_places: Array[int] = []
var _goal_name: String = ""

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _arena: Node2D = null
var _player: CharacterBody2D = null
var _stick: Control = null
var _room: Room = null

var _run_index: int = 0
var _active: bool = false
var _results: Array[Dictionary] = []
var _places_seen: Dictionary = {}
var _run: Dictionary = {}
var _loops_target: int = 1
var _loops_done: int = 0
var _hero_id: String = ""

# The clock and the bot's own state, per run.
var _t: float = 0.0
var _decided: float = 0.0
var _last_dir: Vector2 = Vector2.ZERO
var _move: Vector2 = Vector2.ZERO
var _zone_started: float = 0.0
var _zone_key: String = ""
var _beacon_arrived: float = -1.0
var _gate_pick: int = -1
var _overcharge_now: bool = false
var _stuck_since: float = 0.0
var _stuck_anchor: Vector2 = Vector2.ZERO
var _stuck_goal_distance: float = 0.0
var _health_seen: int = -1
var _guardian_seen: bool = false
var _guardian_started: float = -1.0
var _guardian_hits: int = 0
var _guardian_hp_before: int = 0
var _last_progress_t: float = 0.0
var _progress_key: String = ""
var _dash_ready_seen: bool = true
var _shots_taken: int = 0
var _last_shot_t: float = -99.0
var _sample_left: float = 0.0
var _alive_total: int = 0
var _alive_samples: int = 0
var _bolt_peak: int = 0
## The small bullets of `BulletField`: everything, what was there a moment ago, and what is near enough to weave through.
var _field_pos: PackedVector2Array = PackedVector2Array()
var _field_vel: PackedVector2Array = PackedVector2Array()
var _prev_field_pos: PackedVector2Array = PackedVector2Array()
var _field_source: PackedInt32Array = PackedInt32Array()
var _prev_field_source: PackedInt32Array = PackedInt32Array()
var _near_pos: PackedVector2Array = PackedVector2Array()
var _near_vel: PackedVector2Array = PackedVector2Array()
var _bullet_peak: int = 0
var _bullet_total: int = 0
var _weave_samples: int = 0
var _spirit_peak: int = 0
var _idle_since: float = -1.0
var _frame_max_ms: float = 0.0
var _picks_made: int = 0
var _given_up: Dictionary = {}
var _boost_cleared: bool = false
var _talk_left: float = 0.0
var _goal_item: int = 0

# What is around the player this tick.
var _me: Vector2 = Vector2.ZERO
var _spirits: Array[Node2D] = []
var _bolts: Array[Node2D] = []
var _marks: Array[Node2D] = []
var _prev_spirits: Array[Dictionary] = []
var _prev_bolts: Array[Dictionary] = []
var _prev_marks: Array[Dictionary] = []
## The guardian's last volley: which one it was ("style.pattern") and when it left, so a hit by a bolt can
## say what fired it and how long the bolt had been in flight.
var _volley_winding: bool = false
var _volley_left: float = 0.0
var _volley_seen: String = ""
var _volley_label: String = ""
var _volley_fired_at: float = -99.0
var _echo_count: int = 0
## Where the volley left from, which way its lane pointed, and where the bot stood as it left.
var _volley_from: Vector2 = Vector2.ZERO
var _volley_lane: Vector2 = Vector2.ZERO
var _volley_seen_lane: Vector2 = Vector2.ZERO
var _volley_me: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for raw in OS.get_cmdline_user_args():
		var parts: PackedStringArray = raw.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"runs": _runs = int(parts[1])
			"seed": _seed = int(parts[1])
			"speed": _speed = float(parts[1])
			"loops": _loops_max = clampi(int(parts[1]), 1, 4)
			"tag": _tag = parts[1]
			"shots": _shots = parts[1] == "1"
			"verbose": _verbose = parts[1] == "1"
			"overcharge": _overcharge_share = float(parts[1])
			"react": _react = maxf(float(parts[1]), 0.0)
			"trace": _trace = parts[1] == "1"
			"echo": _read_echoes = parts[1] != "0"
			"farm": _farm_scale = float(parts[1])
			"starts":
				_starts.clear()
				for value in parts[1].split(","):
					_starts.append(maxi(int(value), 1))
			"sturdy": _sturdy = maxf(float(parts[1]), 1.0)
			"gauntlet": _gauntlet = parts[1] == "1"
			"guardians":
				_guardian_places.clear()
				for value in parts[1].split(","):
					_guardian_places.append(clampi(int(value), 0, 5))
			"stand": _stand = parts[1] == "1"
			"shield": _shield = parts[1] == "1"
			"heroes":
				_heroes.clear()
				for id in parts[1].split(","):
					_heroes.append(id)
	Engine.max_physics_steps_per_frame = 32
	get_window().size = Vector2i(808, 360)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
		DisplayServer.window_move_to_foreground()
	_start_run.call_deferred()


# --- Runs ---------------------------------------------------------------------------------------

func _start_run() -> void:
	_run_index += 1
	if _run_index > _runs:
		_finish_all()
		return
	Engine.time_scale = 1.0
	get_tree().paused = false
	var seed_value: int = _seed + _run_index * 101
	seed(seed_value)
	_rng.seed = seed_value
	_hero_id = _heroes[(_run_index - 1) % _heroes.size()]
	# The next run's hero, the way the device checks ask for one: a one-shot file the debug build reads.
	var request: FileAccess = FileAccess.open("user://test_hero.request", FileAccess.WRITE)
	request.store_string("res://resources/heroes/%s.tres" % _hero_id)
	request.close()
	# Started like a player starts one, from the title: forks and the opening story are on.
	RunEntry.mark_from_title()
	_start_cycle = _starts[(_run_index - 1) % _starts.size()]
	if _start_cycle > 1:
		# Six levels a cycle is about what a careful player reaches; the debug presets grant the build.
		var boost_level: int = clampi(4 + 6 * _start_cycle, 10, 90)
		get_tree().root.set_meta("moonlit_test_boost", [boost_level, _start_cycle])
	_arena = ARENA.instantiate() as Node2D
	add_child(_arena)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = _arena.get("_player") as CharacterBody2D
	_stick = _arena.get("_stick") as Control
	_room = _arena.get("_room") as Room
	if _shield:
		_arena.call("debug_shield")
	_loops_target = _rng.randi_range(1, _loops_max)
	_loops_done = 0
	_reset_run_state()
	_run = {
		"run": _run_index, "hero": _hero_id, "seed": seed_value, "loops": _loops_target,
		"start": _start_cycle,
		"events": [], "hits": [], "zones": [], "guardians": [], "picks": [], "stuck": [],
		"gates": [], "beacons": [],
	}
	Engine.time_scale = _speed
	_active = true
	print("PLAY start run %d/%d hero=%s seed=%d loops=%d" % [
		_run_index, _runs, _hero_id, seed_value, _loops_target])


func _reset_run_state() -> void:
	_t = 0.0
	_decided = 0.0
	_last_dir = Vector2.ZERO
	_move = Vector2.ZERO
	_zone_started = 0.0
	_zone_key = ""
	_beacon_arrived = -1.0
	_gate_pick = -1
	_overcharge_now = false
	_stuck_since = 0.0
	_boost_cleared = _start_cycle <= 1
	if _boost_cleared:
		_fix_route.call_deferred()
	_health_seen = int(_arena.get("_health"))
	_guardian_seen = false
	_guardian_started = -1.0
	_guardian_hits = 0
	_last_progress_t = 0.0
	_progress_key = ""
	_shots_taken = 0
	_last_shot_t = -99.0
	_sample_left = 0.0
	_alive_total = 0
	_alive_samples = 0
	_bolt_peak = 0
	_bullet_peak = 0
	_bullet_total = 0
	_weave_samples = 0
	_field_pos = PackedVector2Array()
	_field_vel = PackedVector2Array()
	_prev_field_pos = PackedVector2Array()
	_near_pos = PackedVector2Array()
	_near_vel = PackedVector2Array()
	_spirit_peak = 0
	_idle_since = -1.0
	_frame_max_ms = 0.0
	_picks_made = 0
	_prev_spirits.clear()
	_prev_bolts.clear()
	_prev_marks.clear()
	_volley_winding = false
	_volley_left = 0.0
	_volley_seen = ""
	_volley_label = ""
	_volley_fired_at = -99.0
	_echo_count = 0


func _end_run(reason: String) -> void:
	if not _active:
		return
	_active = false
	Engine.time_scale = 1.0
	# A fight that ended with the player's last heart still counts as a fight, and is the one that matters most.
	if _guardian_seen:
		(_run["guardians"] as Array).append({
			"cycle": int(_arena.get("_cycle")), "kind": str(_run.get("current_guardian", "")),
			"mutations": int(_run.get("current_mutations", 0)), "mutation_ids": _run.get("current_mutation_ids", []),
			"seconds": snappedf(_t - _guardian_started, 0.1), "hits": _guardian_hits,
			"hp_before": _guardian_hp_before, "hp_after": int(_arena.get("_health")),
			"level": int(_arena.get("_level")), "died": true,
		})
	if _stick != null and is_instance_valid(_stick):
		_stick.set("_value", Vector2.ZERO)
	var stats: Dictionary = {
		"reason": reason,
		"seconds": snappedf(_t, 0.1),
		"cycle": int(_arena.get("_cycle")),
		"loops_done": _loops_done,
		"level": int(_arena.get("_level")),
		"kills": int(_arena.get("_kills")),
		"hits": (_run["hits"] as Array).size(),
		"hp_left": int(_arena.get("_health")),
		"alive_avg": snappedf(float(_alive_total) / maxf(float(_alive_samples), 1.0), 0.1),
		"spirit_peak": _spirit_peak,
		"bolt_peak": _bolt_peak,
		"bullet_peak": _bullet_peak,
		"bullet_avg": snappedf(float(_bullet_total) / maxf(float(_alive_samples), 1.0), 0.1),
		"weave_share": snappedf(float(_weave_samples) / maxf(float(_alive_samples), 1.0), 0.01),
		"frame_max_ms": snappedf(_frame_max_ms, 0.1),
		"stuck": (_run["stuck"] as Array).size(),
		"picks": _picks_made,
		"dashes": int(_run.get("dashes", 0)),
		"spikes": int(_run.get("spikes", 0)),
	}
	_run["stats"] = stats
	_results.append(_run)
	print("PLAY ", JSON.stringify({"run": _run_index, "hero": _hero_id, "loops": _loops_target, "stats": stats,
		"zones": (_run["zones"] as Array).size(), "guardians": _run["guardians"], "gates": _run["gates"]}))
	if is_instance_valid(_arena):
		_arena.queue_free()
	_player = null
	_stick = null
	await get_tree().process_frame
	await get_tree().process_frame
	_start_run.call_deferred()


func _finish_all() -> void:
	Engine.time_scale = 1.0
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	var file: FileAccess = FileAccess.open("%s/%s.json" % [out, _tag], FileAccess.WRITE)
	file.store_string(JSON.stringify(_results, "\t"))
	file.close()
	print("PLAY table (run hero loops seconds cycle level kills hits hp_left stuck end):")
	for result in _results:
		var stats: Dictionary = result["stats"]
		print("PLAY   %2d %-8s %d %6.0fs c%d Lv%-3d kills %-4d hits %-3d hp %d stuck %d  %s" % [
			int(result["run"]), str(result["hero"]), int(result["loops"]), float(stats["seconds"]),
			int(stats["cycle"]), int(stats["level"]), int(stats["kills"]), int(stats["hits"]),
			int(stats["hp_left"]), int(stats["stuck"]), str(stats["reason"])])
	print("PLAY done")
	get_tree().quit(0)


# --- The clock ----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _active:
		return
	if not is_instance_valid(_arena):
		_end_run("arena_lost")
		return
	_serve_panels()
	if bool(_arena.get("_over")):
		_end_run("over")
		return
	if get_tree().paused:
		return
	_t += delta
	if _t > RUN_CAP_SECONDS:
		_record_event("soft_lock", {"cycle": int(_arena.get("_cycle")), "zone": int(_arena.get("_zone_index"))})
		_snap("soft_lock")
		_end_run("soft_lock")
		return
	var frame_ms: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	_frame_max_ms = maxf(_frame_max_ms, frame_ms)
	if frame_ms > 120.0:
		_run["spikes"] = int(_run.get("spikes", 0)) + 1
		_record_event("frame_spike", {"ms": snappedf(frame_ms, 1.0),
			"transitioning": bool(_arena.get("_transitioning")), "zone": int(_arena.get("_zone_index")),
			"cycle": int(_arena.get("_cycle"))})
	if not _boost_cleared and _t > 3.4:
		_clear_boost_raids()
	_watch_zone()
	_watch_health()
	_watch_guardian()
	_sample(delta)
	if _t - _decided >= DECISION_SECONDS:
		_decided = _t
		_decide()
	# The arena reads the stick every frame; set what a thumb would be holding.
	_stick.set("_value", _move)


## A boosted start drops three raids on the player at once, which is a stress test and not a night. Once
## they have all arrived, take them away and let the night begin the way one does.
func _clear_boost_raids() -> void:
	_boost_cleared = true
	(_arena.get("_raid_queue") as Array).clear()
	for spirit in (_arena.get("_spirits") as Array).duplicate():
		if is_instance_valid(spirit):
			spirit.free()
	_arena.call("_prune_spirits")
	for bolt in get_tree().get_nodes_in_group("hostile_projectiles"):
		if is_instance_valid(bolt):
			bolt.free()
	_arena.set("_health", int(_arena.get("_max_health")))
	_arena.set("_spawn_timer", 2.0)
	_arena.set("_raid_left", 30.0)
	_fix_route()


## Send the run to a chosen guardian: one gate at a time, no forks, the third zone the place wanted.
func _fix_route() -> void:
	if _guardian_places.is_empty():
		return
	var wanted: int = _guardian_places[(_run_index - 1) % _guardian_places.size()]
	_run["guardian_place"] = PLACES[wanted]
	_arena.set("_forks_enabled", false)
	_arena.set("_route", [(wanted + 1) % 6, (wanted + 2) % 6, wanted] as Array[int])
	_arena.call("_change_cycle_world")
	if _gauntlet:
		_arena.call("debug_complete_route")


# --- Panels: cards, choices, the story ---------------------------------------------------------

func _serve_panels() -> void:
	var dialogue: Control = _arena.get("_dialogue") as Control
	if dialogue != null and dialogue.has_method("is_open") and bool(dialogue.call("is_open")):
		dialogue.call("_close")
		return
	var card: Control = _arena.get_node_or_null("Ui/ActCard") as Control
	if card != null and card.has_method("is_open") and bool(card.call("is_open")):
		card.set("_armed", true)
		var tap: InputEventMouseButton = InputEventMouseButton.new()
		tap.button_index = MOUSE_BUTTON_LEFT
		tap.pressed = true
		card.call("_try_dismiss", tap)
		return
	var relic: Control = _arena.get("_relic") as Control
	if relic != null and relic.visible:
		relic.set("_choice_armed", true)
		var offer: Array = relic.get("_offer")
		if not offer.is_empty():
			var index: int = _choose_card(offer)
			var chosen: Relic = offer[index] as Relic
			(_run["picks"] as Array).append({
				"t": snappedf(_t, 0.1), "level": int(_arena.get("_level")),
				"relic": str(chosen.get_meta("path", "")).get_file().get_basename(),
				"new_skill": bool(chosen.get_meta("new_skill", false)),
			})
			_picks_made += 1
			relic.call("_on_card_pressed", index)
		return
	var choice: Control = _arena.get("_run_choice") as Control
	if choice != null and choice.visible:
		choice.set("_choice_armed", true)
		var mode: int = int(choice.get("_mode"))
		if mode == RunChoicePanel.Mode.BEACON:
			_overcharge_now = _rng.randf() < _overcharge_share
			choice.call("_choose", RunChoicePanel.Choice.RIGHT if _overcharge_now else RunChoicePanel.Choice.LEFT)
		else:
			_loops_done += 1
			var more: bool = _loops_done < _loops_target
			_record_event("loop_done", {"loops_done": _loops_done, "cycle": int(_arena.get("_cycle")),
				"continue": more})
			choice.call("_choose", RunChoicePanel.Choice.RIGHT if more else RunChoicePanel.Choice.LEFT)


## What a player who has been paying attention picks: a new skill, then more of what they already run.
func _choose_card(offer: Array) -> int:
	for index in offer.size():
		if bool((offer[index] as Relic).get_meta("new_skill", false)):
			return index
	var taken: Array = _arena.get("_taken")
	var best: int = 0
	var best_score: float = -1.0
	for index in offer.size():
		var relic: Relic = offer[index] as Relic
		var score: float = _rng.randf() * 0.5
		var family: int = Relic.family_of_relic(relic)
		if family != Relic.Family.NONE:
			score += float(Relic.family_total(taken, family))
		if score > best_score:
			best_score = score
			best = index
	return best


# --- What the bot watches for the record ------------------------------------------------------

func _watch_zone() -> void:
	var cycle: int = int(_arena.get("_cycle"))
	var zone: int = int(_arena.get("_zone_index"))
	var key: String = "%d.%d" % [cycle, zone]
	if key == _zone_key:
		return
	_zone_key = key
	_zone_started = _t
	_beacon_arrived = -1.0
	_gate_pick = -1
	_stuck_since = _t
	_stuck_anchor = _me
	var place: int = int(_arena.call("_terrain_at", zone))
	var omens: Array = _arena.get("_omens")
	(_run["zones"] as Array).append({
		"t": snappedf(_t, 0.1), "cycle": cycle, "zone": zone, "place": PLACES[place],
		"omens": omens.size(), "level": int(_arena.get("_level")), "hp": int(_arena.get("_health")),
	})
	_places_seen[place] = int(_places_seen.get(place, 0)) + 1
	_snap("zone_%s_%s" % [key, PLACES[place]])


func _watch_health() -> void:
	var health: int = int(_arena.get("_health"))
	if _health_seen < 0:
		_health_seen = health
	if health < _health_seen:
		var cause: String = _attribute_hit()
		var hit: Dictionary = {
			"t": snappedf(_t, 0.1), "cycle": int(_arena.get("_cycle")),
			"zone": int(_arena.get("_zone_index")), "hp": health, "cause": cause,
			"guardian": _guardian_seen,
		}
		hit["goal"] = _goal_name
		var hitter: Node2D = _arena.get("_guardian") as Node2D
		if _guardian_seen and hitter != null and is_instance_valid(hitter):
			# What the guardian was doing: 0 chase, 1 charge windup, 2 charge, 3 rest, 4 volley windup.
			hit["gmove"] = int(hitter.get("_guardian_move"))
		hit["moving"] = _move.length() > 0.1
		hit["dash_ready"] = _player.get_dash_ratio() >= 1.0
		var near_60: int = 0
		var near_120: int = 0
		for spirit in _spirits:
			if is_instance_valid(spirit):
				var gap: float = spirit.global_position.distance_to(_me)
				near_60 += 1 if gap < 60.0 else 0
				near_120 += 1 if gap < 120.0 else 0
		hit["near60"] = near_60
		hit["near120"] = near_120
		if _guardian_seen and cause == "bolt:guardian":
			hit["volley"] = _volley_label
			hit["age"] = snappedf(_t - _volley_fired_at, 0.1)
			# Was the bot inside the gap as the volley left, and where is it now? Degrees from the lane.
			hit["fire_off"] = snappedf(rad_to_deg(_off_lane(_volley_me)), 1.0)
			hit["fire_dist"] = snappedf(_volley_me.distance_to(_volley_from), 1.0)
			hit["hit_off"] = snappedf(rad_to_deg(_off_lane(_me)), 1.0)
			hit["hit_dist"] = snappedf(_me.distance_to(_volley_from), 1.0)
		(_run["hits"] as Array).append(hit)
		if _guardian_seen:
			_guardian_hits += 1
		if (_run["hits"] as Array).size() <= 3:
			_snap("hit_%d_%s" % [(_run["hits"] as Array).size(), cause.replace(":", "_")])
	_health_seen = health


## What was nearest to the player a moment ago: the last tick's picture, because the thing that hit is gone.
func _attribute_hit() -> String:
	var me: Vector2 = _player.global_position
	var best: String = "unknown"
	var best_distance: float = 9999.0
	for entry in _prev_spirits:
		var distance: float = (entry["at"] as Vector2).distance_to(me)
		if distance < 26.0 and distance < best_distance:
			best_distance = distance
			best = "%s:%s" % ["guardian" if bool(entry["boss"]) else "contact", str(entry["name"])]
			if bool(entry["boss"]) and int(entry["move"]) == 2:
				best = "charge:%s" % str(entry["name"])
	for entry in _prev_bolts:
		var distance: float = (entry["at"] as Vector2).distance_to(me)
		if distance < 26.0 and distance < best_distance - 4.0:
			best_distance = distance
			best = "bolt:%s" % str(entry["from"])
	for index in _field_pos.size():
		var gap: float = _field_pos[index].distance_to(me)
		if gap < 34.0 and gap < best_distance - 4.0:
			best_distance = gap
			best = "bullet:%s" % BULLET_SOURCES[clampi(_field_source[index] if index < _field_source.size() else 0, 0, BULLET_SOURCES.size() - 1)]
	for index in _prev_field_pos.size():
		var gap: float = _prev_field_pos[index].distance_to(me)
		if gap < 34.0 and gap < best_distance - 4.0:
			best_distance = gap
			best = "bullet:%s" % BULLET_SOURCES[clampi(_prev_field_source[index] if index < _prev_field_source.size() else 0, 0, BULLET_SOURCES.size() - 1)]
	for entry in _prev_marks:
		var offset: Vector2 = me - (entry["at"] as Vector2)
		offset.y /= GroundBurst.SQUASH
		if offset.length() <= float(entry["radius"]) + 8.0 and best_distance > 5.0:
			best_distance = 5.0
			best = "mark"
	return best


## The angle between where the bot is and the lane the last volley pointed down, seen from where it left.
func _off_lane(at: Vector2) -> float:
	return absf(wrapf((at - _volley_from).angle() - _volley_lane.angle(), -PI, PI))


## A volley leaves when its windup ends, or when the windup is wound back up for a second fan. The label is
## read while it winds, because the pattern flips the moment it fires.
func _track_volleys(guardian: Node2D) -> void:
	var move: int = int(guardian.get("_guardian_move"))
	var left: float = float(guardian.get("_guardian_left"))
	if _volley_winding and (move != 4 or left > _volley_left):
		_volley_label = _volley_seen
		_volley_fired_at = _t
		_volley_from = guardian.global_position
		_volley_lane = _volley_seen_lane
		_volley_me = _me
	if move == 4:
		_volley_seen_lane = guardian.get("_locked")
		_volley_seen = "%s.%d" % [
			VOLLEY_STYLES[int((guardian.get("kind") as SpiritKind).guardian_style)],
			int(guardian.get("_guardian_pattern"))]
	_volley_winding = move == 4
	_volley_left = left
	var echoes: Variant = guardian.get("_echoes")
	if echoes is Array:
		if (echoes as Array).size() < _echo_count:
			_volley_label = "echo"
			_volley_fired_at = _t
		_echo_count = (echoes as Array).size()


func _watch_guardian() -> void:
	var guardian: Node2D = _arena.get("_guardian") as Node2D
	var alive: bool = guardian != null and is_instance_valid(guardian)
	if alive:
		_track_volleys(guardian)
	if alive and not _guardian_seen:
		_guardian_seen = true
		_guardian_started = _t
		_guardian_hits = 0
		if _sturdy > 1.0:
			guardian.set("toughness", float(guardian.get("toughness")) * _sturdy)
			var full: int = maxi(int(round(float((guardian.get("kind") as SpiritKind).health) * float(guardian.get("toughness")))), 1)
			guardian.set("_health", full)
			guardian.set("_guardian_full_health", full)
		_guardian_hp_before = int(_arena.get("_health"))
		var path: String = str(guardian.get_meta(&"moonlit_guardian_kind_source_path", ""))
		_run["current_guardian"] = path.get_file().get_basename()
		var mutations: Array = guardian.get("mutations")
		_run["current_mutations"] = mutations.size()
		_run["current_mutation_ids"] = mutations.duplicate()
		_snap("guardian_%s" % path.get_file().get_basename())
	elif not alive and _guardian_seen:
		_guardian_seen = false
		(_run["guardians"] as Array).append({
			"cycle": int(_arena.get("_cycle")) - 1, "kind": str(_run.get("current_guardian", "")),
			"mutations": int(_run.get("current_mutations", 0)), "mutation_ids": _run.get("current_mutation_ids", []),
			"seconds": snappedf(_t - _guardian_started, 0.1), "hits": _guardian_hits,
			"hp_before": _guardian_hp_before, "hp_after": int(_arena.get("_health")),
			"level": int(_arena.get("_level")), "died": false,
		})


func _sample(delta: float) -> void:
	if _verbose:
		_talk_left -= delta
		if _talk_left <= 0.0:
			_talk_left = 5.0
			var near_count: int = 0
			for spirit in _spirits:
				if is_instance_valid(spirit) and spirit.global_position.distance_to(_me) < 150.0:
					near_count += 1
			print("PLAYTALK t=%.0f pos=(%d,%d) move=(%.1f,%.1f) kills=%d lvl=%d hp=%d alive=%d near=%d friendly=%d" % [
				_t, _me.x, _me.y, _move.x, _move.y, int(_arena.get("_kills")), int(_arena.get("_level")),
				int(_arena.get("_health")), _spirits.size(), near_count,
				get_tree().get_node_count_in_group("friendly_projectiles")])
	_sample_left -= delta
	if _sample_left > 0.0:
		return
	_sample_left = 0.5
	var count: int = 0
	for spirit in _arena.call("skill_targets"):
		if is_instance_valid(spirit):
			count += 1
	_alive_total += count
	_alive_samples += 1
	_spirit_peak = maxi(_spirit_peak, count)
	_bolt_peak = maxi(_bolt_peak, get_tree().get_node_count_in_group("hostile_projectiles"))
	_bullet_peak = maxi(_bullet_peak, _field_pos.size())
	_bullet_total += _field_pos.size()
	# Weaving: a bullet within eighty pixels is something being dodged, and a fight without it is not a shooter.
	for at in _field_pos:
		if at.distance_squared_to(_me) < 6400.0:
			_weave_samples += 1
			break
	# Dead time: nothing within reach for a long stretch is a lull, not a fight.
	var near: bool = false
	for spirit in _spirits:
		if is_instance_valid(spirit) and spirit.global_position.distance_to(_me) < 170.0:
			near = true
			break
	if near:
		_idle_since = -1.0
	elif _idle_since < 0.0:
		_idle_since = _t
	elif _t - _idle_since > 12.0 and not bool(_arena.get("_transitioning")):
		(_run["events"] as Array).append({"t": snappedf(_t, 0.1), "kind": "lull", "seconds": snappedf(_t - _idle_since, 0.1)})
		_idle_since = _t + 9999.0


func _record_event(kind: String, data: Dictionary) -> void:
	var entry: Dictionary = data.duplicate()
	entry["kind"] = kind
	entry["t"] = snappedf(_t, 0.1)
	(_run["events"] as Array).append(entry)


func _snap(name: String) -> void:
	if not _shots or DisplayServer.get_name() == "headless" or _shots_taken >= 14:
		return
	if _t - _last_shot_t < 1.2:
		return
	_last_shot_t = _t
	_shots_taken += 1
	var index: int = _shots_taken
	var dir: String = "%s/%s/run%02d" % [ProjectSettings.globalize_path(OUT), _tag, _run_index]
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [dir, index, name])


# --- Deciding where to go ---------------------------------------------------------------------

func _look() -> void:
	# The arena bakes a new room for every zone, so the old one is gone by the time it matters.
	_room = _arena.get("_room") as Room
	_me = _player.global_position
	_prev_spirits = _snapshot_spirits()
	_prev_bolts = _snapshot_bolts()
	_prev_marks = _snapshot_marks()
	_prev_field_pos = _field_pos
	_prev_field_source = _field_source
	var field: Node = _arena.get("_bullets") as Node
	if field != null and is_instance_valid(field):
		_field_pos = field.get("_pos") as PackedVector2Array
		_field_vel = field.get("_vel") as PackedVector2Array
		_field_source = field.get("_source") as PackedInt32Array
	else:
		_field_pos = PackedVector2Array()
		_field_vel = PackedVector2Array()
		_field_source = PackedInt32Array()
	_near_pos = PackedVector2Array()
	_near_vel = PackedVector2Array()
	for index in _field_pos.size():
		if _field_pos[index].distance_squared_to(_me) < 90000.0:
			_near_pos.append(_field_pos[index])
			_near_vel.append(_field_vel[index])
	_spirits.clear()
	for spirit in _arena.call("skill_targets"):
		if is_instance_valid(spirit) and bool(spirit.get("_materialized")) \
				and not bool(spirit.get("_perishing")):
			_spirits.append(spirit)
	_bolts.clear()
	for bolt in get_tree().get_nodes_in_group("hostile_projectiles"):
		if is_instance_valid(bolt):
			_bolts.append(bolt)
	_marks.clear()
	for mark in get_tree().get_nodes_in_group("ground_bursts"):
		if is_instance_valid(mark) and not bool(mark.get("_friendly")) and not bool(mark.get("_burst")):
			_marks.append(mark)


func _snapshot_spirits() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spirit in _spirits:
		if not is_instance_valid(spirit):
			continue
		var kind: SpiritKind = spirit.get("kind") as SpiritKind
		var boss: bool = kind != null and kind.behavior == SpiritKind.Behavior.GUARDIAN
		out.append({
			"at": spirit.global_position, "boss": boss,
			"name": kind.resource_path.get_file().get_basename() if kind != null else "?",
			"move": int(spirit.get("_guardian_move")) if boss else -1,
		})
	return out


func _snapshot_bolts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var from: String = "guardian" if _guardian_seen else "mob"
	for bolt in _bolts:
		if is_instance_valid(bolt):
			out.append({"at": bolt.global_position, "from": from})
	return out


func _snapshot_marks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mark in _marks:
		if is_instance_valid(mark):
			out.append({"at": mark.global_position, "radius": float(mark.get("radius"))})
	return out


func _decide() -> void:
	_look()
	if bool(_arena.get("_transitioning")):
		_move = Vector2.ZERO
		return
	var goal: Dictionary = _goal()
	_goal_name = String(goal["name"])
	var steer: Dictionary = _steer(goal)
	_move = steer["dir"] as Vector2
	if _trace and _guardian_seen:
		_trace_decision(goal, steer)
	if _stand:
		_move = Vector2.ZERO
	_last_dir = _move
	_watch_stuck(goal)
	if bool(steer["dash"]):
		_dash(_move if _move.length() > 0.1 else (_me - (steer["threat"] as Vector2)).normalized())


func _trace_decision(goal: Dictionary, steer: Dictionary) -> void:
	var guardian: Node2D = _arena.get("_guardian") as Node2D
	if guardian == null or not is_instance_valid(guardian):
		return
	var telegraph: int = int(guardian.get("_telegraph"))
	var near_bolts: int = 0
	for bolt in _bolts:
		if is_instance_valid(bolt) and bolt.global_position.distance_to(_me) < 260.0:
			near_bolts += 1
	var echo_count: int = (guardian.get("_echoes") as Array).size() if guardian.get("_echoes") is Array else 0
	if telegraph == 0 and near_bolts == 0 and echo_count == 0:
		return
	var offset: Vector2 = _me - guardian.global_position
	var lane: Vector2 = guardian.get("_telegraph_direction") as Vector2
	var echo_left: float = -1.0
	if echo_count > 0:
		echo_left = float(((guardian.get("_echoes") as Array)[0] as Dictionary)["left"])
	print("PLAYTRACE t=%.2f tel=%d seen=%.2f me=(%d,%d) off=%d reach=%d bolts=%d echo=%d/%.2f ecost=%d goal=%s dir=(%.1f,%.1f) cost=%d dash=%s ready=%s hp=%d" % [
		_t, telegraph, _seen_for(guardian), _me.x, _me.y,
		roundi(rad_to_deg(absf(wrapf(offset.angle() - lane.angle(), -PI, PI)))), roundi(offset.length()),
		near_bolts, echo_count, echo_left, roundi(_echo_cost(guardian, _me - (guardian.global_position + Vector2(0, -6)))),
		String(goal["name"]), (steer["dir"] as Vector2).x, (steer["dir"] as Vector2).y,
		roundi(float(steer["cost"])), str(bool(steer["dash"])), str(_player.get_dash_ratio() >= 1.0),
		int(_arena.get("_health"))])


func _dash(direction: Vector2) -> void:
	if direction.length() < 0.01 or _player.get_dash_ratio() < 1.0:
		return
	# The arena's button handler reads the stick: give it the direction the thumb is pushing.
	_stick.set("_value", direction.normalized())
	_arena.call("_on_dash_pressed")
	_run["dashes"] = int(_run.get("dashes", 0)) + 1


## Where the bot wants to be: {pos, has, hold}.
func _goal() -> Dictionary:
	var none: Dictionary = {"pos": _me, "has": false, "hold": false, "name": "farm"}
	# The gate first, once it is open.
	if bool(_arena.get("_escape_active")):
		var target: Dictionary = _gate_goal()
		if not target.is_empty():
			return target
	# A guardian is fought at a distance.
	var guardian: Node2D = _arena.get("_guardian") as Node2D
	if guardian != null and is_instance_valid(guardian):
		return _guardian_goal(guardian)
	# What lies on the floor is worth a few steps when nothing is close.
	var pickup: Dictionary = _pickup_goal()
	if not pickup.is_empty():
		return pickup
	# Then the beacon, once the bot has fought long enough.
	var beacons: Array = _arena.get("_beacons")
	var zone: int = int(_arena.get("_zone_index"))
	if zone >= beacons.size():
		return _fight_goal(none)
	var beacon: Node2D = beacons[zone] as Node2D
	var lit: bool = bool(beacon.get("lit"))
	if beacon == null or not beacon.visible or lit:
		return none
	var overcharge_active: bool = _arena.get("_overcharge_beacon") != null
	var ready: bool = _t - _zone_started >= FARM_SECONDS * _farm_scale or overcharge_active
	# Even a careful player goes at once when the field is empty of anything to fight.
	if not ready and _spirits.is_empty() and _t - _zone_started > 8.0:
		ready = true
	if not ready:
		return _fight_goal(none)
	var distance: float = _me.distance_to(beacon.global_position)
	if distance <= HOLD_RADIUS + 4.0 and _beacon_arrived < 0.0:
		_beacon_arrived = _t
	if overcharge_active and int(_arena.get("_health")) <= 2:
		# Too much: walk far off, which ends an overcharge as a plain kindle.
		return {"pos": _me + (_me - beacon.global_position).normalized() * 260.0, "has": true,
			"hold": false, "name": "abandon"}
	return {"pos": beacon.global_position, "has": true, "hold": distance <= HOLD_RADIUS + 10.0,
		"name": "beacon"}


## The slash reaches thirty-four pixels and does most of the killing in the first minutes: whatever comes
## within reach is cut down, so the pack is met where the player stands, stepping out of the way of a
## touch and of what is thrown, and not led round the map. With the hearts low the player runs a wide
## circle instead, looking for dew.
func _fight_goal(none: Dictionary) -> Dictionary:
	var nearest_distance: float = 9999.0
	for spirit in _spirits:
		if is_instance_valid(spirit):
			nearest_distance = minf(nearest_distance, spirit.global_position.distance_to(_me))
	if nearest_distance > 260.0:
		return none
	if int(_arena.get("_health")) > 2:
		return {"pos": _me, "has": true, "hold": true, "name": "fight"}
	var center: Vector2 = Room.MAP * 0.5
	var from_center: Vector2 = _me - center
	if from_center.length() < 30.0:
		from_center = Vector2.RIGHT * 300.0
	return {"pos": center + from_center.normalized().rotated(0.42) * 320.0, "has": true,
		"hold": false, "name": "fight"}


func _gate_goal() -> Dictionary:
	var gate_a: Node2D = _arena.get("_gate") as Node2D
	var gate_b: Node2D = _arena.get("_gate_b") as Node2D
	var options: Array = _arena.get("_fork_options")
	if _gate_pick < 0:
		_gate_pick = 0
		if options.size() == 2 and gate_b != null and is_instance_valid(gate_b):
			# The place the bot has seen least, so a handful of runs covers all six.
			var seen_a: int = int(_places_seen.get(int(options[0]), 0))
			var seen_b: int = int(_places_seen.get(int(options[1]), 0))
			_gate_pick = 0 if seen_a < seen_b or (seen_a == seen_b and _rng.randf() < 0.5) else 1
		(_run["gates"] as Array).append({
			"t": snappedf(_t, 0.1), "cycle": int(_arena.get("_cycle")), "zone": int(_arena.get("_zone_index")),
			"options": [PLACES[int(options[0])], PLACES[int(options[1])]] if options.size() == 2 else [],
			"picked": _gate_pick,
		})
		_snap("fork")
	var gate: Node2D = gate_a if _gate_pick == 0 else gate_b
	if gate == null or not is_instance_valid(gate) or not gate.visible:
		gate = gate_a
	if gate == null or not gate.visible:
		return {}
	return {"pos": gate.global_position, "has": true, "hold": false, "name": "gate"}


func _guardian_goal(guardian: Node2D) -> Dictionary:
	var away: Vector2 = _me - guardian.global_position
	var distance: float = away.length()
	if distance < 1.0:
		away = Vector2.RIGHT
		distance = 1.0
	# A comfortable distance is held, not circled: a person who stops moving is a person a ring's gap can be
	# aimed at, and the marks and the fans are stepped out of when they appear.
	if distance >= 105.0 and distance <= 215.0:
		return {"pos": _me, "has": true, "hold": true, "name": "guardian"}
	return {"pos": guardian.global_position + away / distance * 155.0, "has": true, "hold": false,
		"name": "guardian"}


func _pickup_goal() -> Dictionary:
	if _threat_near(60.0):
		return {}
	var hurt: bool = int(_arena.get("_health")) < int(_arena.get("_max_health"))
	var best: Node2D = null
	var best_distance: float = 9999.0
	for group in ["missile_cores", "moon_dews", "moon_embers", "power_orbs"]:
		var reach: float = 230.0 if group == "missile_cores" else (170.0 if group == "moon_dews" else 110.0)
		if group == "moon_dews" and not hurt:
			continue
		for item in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(item) or not item.is_visible_in_tree():
				continue
			if float(_given_up.get(item.get_instance_id(), -99.0)) > _t - 12.0:
				continue
			var distance: float = (item as Node2D).global_position.distance_to(_me)
			if distance < reach and distance < best_distance:
				best_distance = distance
				best = item as Node2D
	if best == null:
		return {}
	_goal_item = best.get_instance_id()
	return {"pos": best.global_position, "has": true, "hold": false, "name": "pickup"}


func _threat_near(reach: float) -> bool:
	for spirit in _spirits:
		if is_instance_valid(spirit) and spirit.global_position.distance_to(_me) < reach:
			return true
	return not _bolts.is_empty() and _bolts.any(func(bolt: Node2D) -> bool:
		return is_instance_valid(bolt) and bolt.global_position.distance_to(_me) < reach * 1.5)


# --- Steering ---------------------------------------------------------------------------------

## A person sidesteps as well as runs: every direction is tried both as a run that goes on and as a short step
## that stops, and a dash is one more way to move, with the place it lands judged like any other.
const WALK_STOPS: Array[float] = [0.25, 0.9]
const DASH_DISTANCE: float = 61.0
const DASH_SPEED: float = 320.0
## What a dash costs before anything else is counted: it is spent for a reason.
const DASH_PENALTY: float = 35.0

func _steer(goal: Dictionary) -> Dictionary:
	var speed: float = float(_player.get("speed"))
	var best_dir: Vector2 = Vector2.ZERO
	var best_cost: float = INF
	var stay_cost: float = 0.0
	var dash: bool = false
	for index in DIRECTIONS + 1:
		var direction: Vector2 = Vector2.ZERO if index == DIRECTIONS \
			else Vector2.RIGHT.rotated(TAU * float(index) / float(DIRECTIONS))
		for stop in ([0.9] if index == DIRECTIONS else WALK_STOPS):
			var positions: Array[Vector2] = []
			for sample in SAMPLE_TIMES:
				positions.append(_me + direction * speed * minf(sample, stop))
			var cost: float = _cost(positions, direction, goal, true)
			if index == DIRECTIONS:
				stay_cost = cost
			if cost < best_cost:
				best_cost = cost
				best_dir = direction
	var hold: bool = bool(goal["hold"])
	if hold and stay_cost <= best_cost + 6.0:
		best_dir = Vector2.ZERO
		best_cost = stay_cost
	if _player.get_dash_ratio() >= 1.0:
		var best_dash: Vector2 = Vector2.ZERO
		var best_dash_cost: float = INF
		for index in DIRECTIONS:
			var direction: Vector2 = Vector2.RIGHT.rotated(TAU * float(index) / float(DIRECTIONS))
			var positions: Array[Vector2] = []
			for sample in SAMPLE_TIMES:
				positions.append(_me + direction * minf(DASH_SPEED * sample, DASH_DISTANCE))
			var cost: float = _cost(positions, direction, goal, false) + DASH_PENALTY
			if cost < best_dash_cost:
				best_dash_cost = cost
				best_dash = direction
		# Only when standing or walking would cost something worth a dash.
		if best_dash_cost < best_cost and best_cost > 45.0:
			best_dir = best_dash
			best_cost = best_dash_cost
			dash = true
	return {"dir": best_dir, "dash": dash, "threat": _nearest_threat() if dash else _me, "cost": best_cost}


func _nearest_threat() -> Vector2:
	var best: Vector2 = _me + Vector2.RIGHT
	var best_distance: float = 9999.0
	for spirit in _spirits:
		if is_instance_valid(spirit):
			var distance: float = spirit.global_position.distance_to(_me)
			if distance < best_distance:
				best_distance = distance
				best = spirit.global_position
	for bolt in _bolts:
		if is_instance_valid(bolt):
			var distance: float = bolt.global_position.distance_to(_me)
			if distance < best_distance:
				best_distance = distance
				best = bolt.global_position
	return best


func _cost(positions: Array[Vector2], direction: Vector2, goal: Dictionary, walking: bool) -> float:
	var cost: float = 0.0
	for index in SAMPLE_TIMES.size():
		cost += _terrain_cost(positions[index])
		cost += _threat_cost(positions[index], SAMPLE_TIMES[index])
	if bool(goal["has"]):
		var target: Vector2 = goal["pos"] as Vector2
		var before: float = _me.distance_to(target)
		var after: float = positions[2].distance_to(target)
		if bool(goal["hold"]):
			cost += maxf(after - 8.0, 0.0) * 0.2
		else:
			cost += (after - before) * 0.16
	if walking:
		cost -= 2.5 * direction.dot(_last_dir)
	return cost


func _terrain_cost(at: Vector2) -> float:
	var cost: float = 0.0
	# A gate stands at the rim and a pickup may lie against the wall, so the bot may go right to them;
	# everywhere else it keeps off the wall.
	var inner: Rect2 = Room.PLAY.grow(-4.0 if _goal_name == "gate" or _goal_name == "pickup" else -26.0)
	if not inner.has_point(at):
		cost += 90.0 + 0.6 * _outside(inner, at)
	if not _room.is_clear(at, 7.0):
		cost += 80.0
	return cost


func _outside(rect: Rect2, at: Vector2) -> float:
	var dx: float = maxf(maxf(rect.position.x - at.x, at.x - rect.end.x), 0.0)
	var dy: float = maxf(maxf(rect.position.y - at.y, at.y - rect.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)


func _threat_cost(at: Vector2, sample: float) -> float:
	var cost: float = 0.0
	for spirit in _spirits:
		if not is_instance_valid(spirit):
			continue
		# A warning on the floor is read from wherever the player stands; only the touch of a body is near.
		cost += _telegraph_cost(spirit, at)
		var distance_now: float = spirit.global_position.distance_to(at)
		if distance_now > 110.0:
			continue
		var future: Vector2 = spirit.global_position + (spirit.get("velocity") as Vector2) * sample
		var distance: float = future.distance_to(at)
		var kind: SpiritKind = spirit.get("kind") as SpiritKind
		var boss: bool = kind != null and kind.behavior == SpiritKind.Behavior.GUARDIAN
		var reach: float = 42.0 if boss else MOB_REACH
		if distance < reach:
			cost += (reach - distance) * (reach - distance) * (0.05 if boss else MOB_WEIGHT)
	# The small bullets: where each will be, kept clear of by a body's width beyond their hit circle.
	for index in _near_pos.size():
		var future_at: Vector2 = _near_pos[index] + _near_vel[index] * sample
		var gap: float = future_at.distance_to(at)
		if gap < BULLET_DANGER:
			cost += (BULLET_DANGER - gap) * 9.0
	for bolt in _bolts:
		if not is_instance_valid(bolt):
			continue
		var direction: Vector2 = bolt.get("_direction") as Vector2
		var bolt_speed: float = 132.0 * float(bolt.get("_speed_scale"))
		var future_bolt: Vector2 = bolt.global_position + direction * bolt_speed * sample
		var distance: float = future_bolt.distance_to(at)
		if distance < BODY_DANGER + 8.0:
			cost += (BODY_DANGER + 8.0 - distance) * 8.0
	for mark in _marks:
		if not is_instance_valid(mark):
			continue
		var offset: Vector2 = at - mark.global_position
		offset.y /= GroundBurst.SQUASH
		var radius: float = float(mark.get("radius")) + 8.0
		if offset.length() < radius:
			if float(mark.get("_fuse")) - float(mark.get("_left")) < _react:
				continue
			var left: float = float(mark.get("_left")) - sample
			cost += 130.0 if left < 0.6 else 30.0
	return cost


## What a marking on the floor says to a person who can read it: a lane, a wedge, or a ring with a way through,
## and the ghost of an echo that is about to repeat a volley.
func _telegraph_cost(spirit: Node2D, at: Vector2) -> float:
	var origin: Vector2 = spirit.global_position + Vector2(0, -6)
	var offset: Vector2 = at - origin
	var cost: float = 0.0
	var telegraph: int = int(spirit.get("_telegraph"))
	# A person takes a moment to see a warning.
	if telegraph != 0 and _seen_for(spirit) >= _react:
		var direction: Vector2 = spirit.get("_telegraph_direction") as Vector2
		match telegraph:
			1:
				# A single shot does not stop where its line is drawn to: it goes on through whoever is on it. A
				# caster's fan is several lanes, each drawn.
				var aim: float = float(spirit.call("aim_reach")) if spirit.has_method("aim_reach") else 130.0
				var lanes: Array = spirit.call("aim_angles") if spirit.has_method("aim_angles") else [direction.angle()]
				for lane_angle in lanes:
					if _in_lane(offset, Vector2.RIGHT.rotated(float(lane_angle)), aim + 30.0, 14.0):
						cost += 60.0
						break
			2:
				cost += 110.0 if _in_lane(offset, direction, 330.0, 20.0) else 0.0
			3:
				cost += _shape_cost(spirit.call("volley_shape"), offset)
				# The repeat an Echo will bring is drawn beside the volley, so it is planned for while this winds up.
				if _read_echoes and spirit.has_method("echo_preview_shape"):
					var preview: Dictionary = spirit.call("echo_preview_shape")
					if not preview.is_empty():
						cost += _shape_cost(preview, offset)
	return cost + (_echo_cost(spirit, offset) if _read_echoes else 0.0)


## The ghost of a repeat, on the floor for the last half second before it fires.
func _echo_cost(spirit: Node2D, offset: Vector2) -> float:
	var echoes: Variant = spirit.get("_echoes")
	if not (echoes is Array) or not spirit.has_method("volley_shape_for"):
		return 0.0
	var cost: float = 0.0
	for echo in echoes:
		var left: float = float((echo as Dictionary)["left"])
		if left < ECHO_WARN and ECHO_WARN - left >= _react:
			cost += _shape_cost(spirit.call("volley_shape_for", int(echo["volley"]), float(echo["angle"]),
				int(echo["pattern"]), int(echo["fan"])), offset)
	return cost


## Seconds the warning has been on the floor.
func _seen_for(spirit: Node2D) -> float:
	var kind: SpiritKind = spirit.get("kind") as SpiritKind
	if kind != null and kind.behavior == SpiritKind.Behavior.GUARDIAN:
		var haste: float = maxf(float(spirit.get("_guardian_move_haste")), 0.01)
		return (float(spirit.get("_guardian_move_duration")) - float(spirit.get("_guardian_left"))) / haste
	return float(spirit.get("_telegraph_ratio")) * (kind.charge_windup if kind != null else 1.0)


## A volley is read from the picture the guardian draws: the wedge of a fan, or the bolts of a ring and the
## way through them. Inside a wedge the way out is the nearest edge and it is worth a run; on a ring the
## way through is the middle of the gap.
func _shape_cost(shape: Dictionary, offset: Vector2) -> float:
	var reach: float = offset.length()
	if reach < 20.0 or reach > 270.0:
		return 0.0
	var base: float = float(shape["base"])
	var off: float = wrapf(offset.angle() - base, -PI, PI)
	var margin: float = atan2(BODY_DANGER, reach)
	if StringName(shape["kind"]) == &"fan":
		var edge: float = float(shape["half"]) + margin
		if absf(off) >= edge:
			return 0.0
		return 70.0 + 0.9 * (edge - absf(off)) * reach
	var nearest: float = PI
	for group in [shape["angles"], shape["slow"]]:
		for angle in group:
			nearest = minf(nearest, absf(wrapf(offset.angle() - float(angle), -PI, PI)))
	if nearest < margin:
		return 70.0 + 0.9 * (margin - nearest) * reach
	return 0.06 * absf(off) * reach


func _in_lane(offset: Vector2, direction: Vector2, length: float, half_width: float) -> bool:
	var along: float = offset.dot(direction)
	if along < -10.0 or along > length:
		return false
	var across: float = absf(offset.cross(direction))
	return across < half_width


# --- Getting unstuck --------------------------------------------------------------------------

func _watch_stuck(goal: Dictionary) -> void:
	if not bool(goal["has"]) or bool(goal["hold"]) or String(goal["name"]) == "farm":
		_stuck_since = _t
		_stuck_anchor = _me
		return
	if _me.distance_to(_stuck_anchor) > 24.0:
		_stuck_since = _t
		_stuck_anchor = _me
		return
	if _t - _stuck_since > STUCK_SECONDS:
		(_run["stuck"] as Array).append({
			"t": snappedf(_t, 0.1), "at": [roundi(_me.x), roundi(_me.y)],
			"goal": String(goal["name"]), "to": [roundi((goal["pos"] as Vector2).x), roundi((goal["pos"] as Vector2).y)],
			"place": PLACES[int(_arena.call("_terrain_at", int(_arena.get("_zone_index"))))],
		})
		_snap("stuck")
		if String(goal["name"]) == "pickup":
			_given_up[_goal_item] = _t
		# Step off in a direction that is not the goal's, for a moment, like a player who has walked into a wall.
		_last_dir = Vector2.RIGHT.rotated(_rng.randf() * TAU)
		_stuck_since = _t
		_stuck_anchor = _me
