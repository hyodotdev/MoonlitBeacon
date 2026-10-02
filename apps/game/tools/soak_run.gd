extends Node

## Play the real game through many cycles with a stand-still bot, and write down what happened.
##
## The bot never moves. It fights from the middle of the map, lights each beacon by the debug hook,
## runs for a gate, picks a card at random when one opens, and heals to full twice a second so it
## cannot die. What it measures is therefore not skill but **the economy between the player's growth
## and the night's**: how many spirits it clears a minute, how long a spirit lives, how often the
## field is full, how long a guardian takes to fall, and what it costs (nodes, frame time).
##
## A curve that is too soft shows as spirits living a fraction of a second and a guardian that dies
## in seconds. A wall shows as the field pinned at the cap and a guardian that never falls. Both are
## numbers here, so a cliff between two cycles cannot hide.
##
## Run it headless, with a throwaway HOME:
##
##     HOME=$(mktemp -d) node scripts/godot.mjs --headless --path apps/game \
##         res://tools/soak_run.tscn -- cycles=14 seed=7 speed=4 zone=60 tag=new
##
## Keep `speed` at 4 or below. At 8 the game's own catch-up loops (a frame that runs long gets a
## bigger step, which makes the next frame longer) spiral into single frames that take a minute,
## and the run looks hung. It is the accelerated clock, not the game: at 4 and at 2 the same run
## advances in a straight line.
##
## `curve=shipped` replays the 2.1.0 curve (x1.58 a cycle past cycle 8) next to the new one.
## Output: one `SOAK {...}` JSON line per cycle on stdout, a table at the end, and
## `builds/soak/<tag>_<seed>.json`. Lives in `tools/`, which `_runtime_fingerprint()` excludes.

const ARENA: PackedScene = preload("res://scenes/gameplay/arena.tscn")
const OUT: String = "res://../../builds/soak"

var _arena: Node2D = null
var _cycles: int = 14
var _seed: int = 7
var _speed: float = 4.0
var _zone_seconds: float = 60.0
var _guardian_cap: float = 240.0
var _tag: String = "run"
var _shipped: bool = false

var _rows: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Per-cycle accumulators.
var _game_time: float = 0.0
var _cycle_start_time: float = 0.0
var _kills_at_start: int = 0
var _alive_samples: int = 0
var _alive_total: int = 0
var _capped_samples: int = 0
var _sample_left: float = 0.0
var _born: Dictionary = {}
var _lifetimes: Array[float] = []
var _node_peak: int = 0
var _fps_min: float = 9999.0
var _heal_left: float = 0.0
var _guardian_started: float = -1.0
var _guardian_ttk: float = -1.0
var _guardian_timed_out: bool = false
## What the guardian of this cycle was and where it stood, read while it is alive: once it falls the arena
## has already rolled into the next cycle and its route is gone.
var _guardian_place: int = -1
var _guardian_kind: String = ""
var _route_seen: Array = []
var _picks_at_start: int = 0

# The bot's state.
enum Step { FIGHT, GATE, TRAVEL, GUARDIAN, LOOT }
var _step: Step = Step.FIGHT
var _zone_time: float = 0.0
var _gate_wait: float = 0.0
var _zone: int = 0
var _last_cycle: int = 1
var _done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for raw in OS.get_cmdline_user_args():
		var parts: PackedStringArray = raw.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"cycles": _cycles = int(parts[1])
			"seed": _seed = int(parts[1])
			"speed": _speed = float(parts[1])
			"zone": _zone_seconds = float(parts[1])
			"tag": _tag = parts[1]
			"curve": _shipped = parts[1] == "shipped"
	Expedition.shipped_curve = _shipped
	_rng.seed = _seed
	seed(_seed)
	get_window().size = Vector2i(808, 360)
	_arena = ARENA.instantiate() as Node2D
	add_child(_arena)
	await get_tree().process_frame
	await get_tree().process_frame
	_arena.set("_run_seed", _seed)
	_arena.set("_forks_enabled", true)
	_arena.set("_survived", 0.0)
	Engine.time_scale = _speed
	Engine.max_physics_steps_per_frame = 32
	_begin_cycle()
	print("SOAK start cycles=%d seed=%d speed=%.1f zone=%.0fs curve=%s"
		% [_cycles, _seed, _speed, _zone_seconds, "shipped" if _shipped else "new"])


func _begin_cycle() -> void:
	_cycle_start_time = _game_time
	_kills_at_start = int(_arena.get("_kills"))
	_alive_samples = 0
	_alive_total = 0
	_capped_samples = 0
	_lifetimes.clear()
	_node_peak = 0
	_fps_min = 9999.0
	_guardian_started = -1.0
	_guardian_ttk = -1.0
	_guardian_timed_out = false
	_guardian_place = -1
	_guardian_kind = ""
	_route_seen = []
	_picks_at_start = (_arena.get("_taken") as Array).size()
	_zone = 0
	_zone_time = 0.0
	_step = Step.FIGHT


var _progress_left: float = 30.0
var _wall_report: int = 0


## Frame-based heartbeat: shows what the bot sees even when the game is paused or slow.
func _process(_delta: float) -> void:
	var wall: int = int(Time.get_ticks_msec() / 30000)
	if wall == _wall_report or _arena == null:
		return
	_wall_report = wall
	if not is_instance_valid(_arena):
		print("SOAK !! arena is gone")
		return
	var relic: Control = _arena.get("_relic") as Control
	var choice: Control = _arena.get("_run_choice") as Control
	print("SOAK hb wall=%ds game=%ds paused=%s scale=%.1f relic=%s choice=%s step=%s cycle=%d over=%s trans=%s nodes=%d proc=%.0fms phys=%.0fms objs=%d" % [
		wall * 30, int(_game_time), get_tree().paused, Engine.time_scale,
		relic.visible if relic != null else "-", choice.visible if choice != null else "-",
		Step.keys()[_step], int(_arena.get("_cycle")), _arena.get("_over"),
		_arena.get("_transitioning"),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_COUNT))])


func _physics_process(delta: float) -> void:
	if _done or _arena == null or not is_instance_valid(_arena):
		return
	var frame_start: int = Time.get_ticks_msec()
	_physics_body(delta)
	var spent: int = Time.get_ticks_msec() - frame_start
	if spent > 500:
		print("SOAK slow bot step %d ms in %s" % [spent, Step.keys()[_step]])


func _physics_body(delta: float) -> void:
	_game_time += delta
	_progress_left -= delta
	if _progress_left <= 0.0:
		_progress_left = 30.0
		print("SOAK ..  game %ds  wall %ds  cycle %d zone %d step %s  kills %d  alive %d" % [
			int(_game_time), int(Time.get_ticks_msec() / 1000), int(_arena.get("_cycle")), _zone,
			Step.keys()[_step], int(_arena.get("_kills")),
			(_arena.get("_spirits") as Array).size()])
	_serve_panels()
	if get_tree().paused:
		return
	# Nothing the story wants to say matters to a bot.
	_arena.set("_pending_story_cycle", 0)
	_keep_alive(delta)
	_sample(delta)
	match _step:
		Step.FIGHT: _tick_fight(delta)
		Step.GATE: _tick_gate(delta)
		Step.TRAVEL: _tick_travel()
		Step.GUARDIAN: _tick_guardian(delta)
		Step.LOOT: pass


## Cards and choices that pause the game: pick at random, always continue.
func _serve_panels() -> void:
	var relic: Control = _arena.get("_relic") as Control
	if relic != null and relic.visible:
		relic.set("_choice_armed", true)
		var offer: Array = relic.get("_offer")
		if not offer.is_empty():
			relic.call("_on_card_pressed", _rng.randi_range(0, offer.size() - 1))
		return
	var choice: Control = _arena.get("_run_choice") as Control
	if choice != null and choice.visible:
		choice.set("_choice_armed", true)
		choice.call("_choose", RunChoicePanel.Choice.RIGHT)
		return
	var dialogue: Control = _arena.get("_dialogue") as Control
	if dialogue != null and dialogue.visible and dialogue.has_method("finish"):
		dialogue.call("finish")


## The bot is not the point; keep it standing.
func _keep_alive(delta: float) -> void:
	_heal_left -= delta
	if _heal_left <= 0.0:
		_heal_left = 0.4
		_arena.call("debug_heal")


func _sample(delta: float) -> void:
	_sample_left -= delta
	if _sample_left > 0.0:
		return
	_sample_left = 0.25
	var spirits: Array = _arena.call("skill_targets")
	var alive: int = 0
	var seen: Dictionary = {}
	for spirit in spirits:
		if not is_instance_valid(spirit):
			continue
		var kind: SpiritKind = spirit.get("kind") as SpiritKind
		if kind != null and kind.behavior == SpiritKind.Behavior.GUARDIAN:
			continue
		alive += 1
		var id: int = spirit.get_instance_id()
		seen[id] = true
		if not _born.has(id):
			_born[id] = _game_time
	for id in _born.keys():
		if not seen.has(id):
			_lifetimes.append(_game_time - float(_born[id]))
			_born.erase(id)
	_alive_samples += 1
	_alive_total += alive
	if alive >= int(_arena.call("spirit_cap")) - 1:
		_capped_samples += 1
	_node_peak = maxi(_node_peak, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_fps_min = minf(_fps_min, float(Engine.get_frames_per_second()) / maxf(_speed, 1.0))


func _tick_fight(delta: float) -> void:
	_zone_time += delta
	if _zone_time < _zone_seconds:
		return
	var started: int = Time.get_ticks_msec()
	_arena.call("debug_light_next_beacon")
	print("SOAK lit beacon in %d ms" % (Time.get_ticks_msec() - started))
	_step = Step.GATE if _zone < 2 else Step.GUARDIAN
	_gate_wait = 0.0
	if _step == Step.GUARDIAN:
		_guardian_started = -1.0


func _tick_gate(delta: float) -> void:
	_gate_wait += delta
	if not bool(_arena.get("_escape_active")):
		if _gate_wait > 6.0:
			# The beacon did not open a gate; try the next one.
			_arena.call("debug_light_next_beacon")
			_gate_wait = 0.0
		return
	var pick: int = _rng.randi_range(0, 1)
	_arena.call("_on_gate_entered", pick)
	_step = Step.TRAVEL


func _tick_travel() -> void:
	if bool(_arena.get("_transitioning")):
		return
	_zone += 1
	_zone_time = 0.0
	_step = Step.FIGHT


func _tick_guardian(delta: float) -> void:
	var guardian: Node2D = _arena.get("_guardian") as Node2D
	if guardian != null and is_instance_valid(guardian):
		if _guardian_started < 0.0 and int(guardian.get("_health")) > 0:
			_guardian_started = _game_time
			_guardian_place = int(_arena.call("_terrain_at", 2))
			_guardian_kind = str(guardian.get_meta(
				&"moonlit_guardian_kind_source_path", "")).get_file().get_basename()
			_route_seen = (_arena.get("_route") as Array).duplicate()
		if _guardian_started >= 0.0 and _game_time - _guardian_started > _guardian_cap:
			_guardian_timed_out = true
			guardian.call("debug_slay")
		return
	if _guardian_started >= 0.0 and _guardian_ttk < 0.0:
		_guardian_ttk = _game_time - _guardian_started
	# The guardian is gone: `_finish_cycle` has run and the loot panel is open or about to.
	if int(_arena.get("_cycle")) > _last_cycle:
		_finish_cycle_row()


func _finish_cycle_row() -> void:
	var cycle: int = _last_cycle
	var minutes: float = maxf((_game_time - _cycle_start_time) / 60.0, 0.001)
	var kills: int = int(_arena.get("_kills")) - _kills_at_start
	var lifetime: float = 0.0
	if not _lifetimes.is_empty():
		for value in _lifetimes:
			lifetime += value
		lifetime /= float(_lifetimes.size())
	var row: Dictionary = {
		"cycle": cycle,
		"minutes": snappedf(minutes, 0.01),
		"kills": kills,
		"kills_per_min": snappedf(float(kills) / minutes, 0.1),
		"alive_avg": snappedf(float(_alive_total) / maxf(float(_alive_samples), 1.0), 0.1),
		"at_cap_pct": snappedf(100.0 * float(_capped_samples) / maxf(float(_alive_samples), 1.0), 1.0),
		"spirit_life_s": snappedf(lifetime, 0.01),
		"guardian_ttk_s": snappedf(_guardian_ttk, 0.1),
		"guardian_timeout": _guardian_timed_out,
		"mutations": (Expedition.mutations_for(_seed, cycle, maxi(_guardian_place, 0))).size(),
		"toughness": snappedf(Expedition.toughness(cycle), 0.1),
		"level": int(_arena.get("_level")),
		"picks": (_arena.get("_taken") as Array).size(),
		"picks_this_cycle": (_arena.get("_taken") as Array).size() - _picks_at_start,
		"damage_mult": snappedf(float(_arena.get("_damage_mult")), 0.01),
		"arrow_mult": snappedf(float(_arena.get("_arrow_mult")), 0.01),
		"haste": snappedf(float(_arena.get("_relic_haste")), 0.01),
		"missile_power": int(_arena.get("_missile_power")),
		"nodes_peak": _node_peak,
		"fps_min": snappedf(_fps_min, 1.0),
		"guardian_terrain": _guardian_place,
		"guardian": _guardian_kind,
		"route": _route_seen,
	}
	_rows.append(row)
	print("SOAK ", JSON.stringify(row))
	_last_cycle = int(_arena.get("_cycle"))
	if cycle >= _cycles:
		_finish()
		return
	_begin_cycle()


func _finish() -> void:
	_done = true
	Engine.time_scale = 1.0
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	var file: FileAccess = FileAccess.open("%s/%s_%d.json" % [out, _tag, _seed], FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_rows, "  "))
		file.close()
	print("SOAK table")
	print("cycle  min  kills  k/min  alive  cap%  life_s  g_ttk  tough  lvl  picks  dmg   arrow  nodes  fps")
	for row in _rows:
		print("%5d %4.1f %6d %6.1f %6.1f %5.0f %7.2f %6.1f %6.1f %4d %6d %5.1f %6.1f %6d %4.0f%s" % [
			row["cycle"], row["minutes"], row["kills"], row["kills_per_min"], row["alive_avg"],
			row["at_cap_pct"], row["spirit_life_s"], row["guardian_ttk_s"], row["toughness"],
			row["level"], row["picks"], row["damage_mult"], row["arrow_mult"], row["nodes_peak"],
			row["fps_min"], "  TIMEOUT" if row["guardian_timeout"] else ""])
	print("SOAK done")
	Expedition.shipped_curve = false
	get_tree().quit(0)
