extends Node

## Original combat audio: baked cues, real event wiring, bounded voices.
##
## Waveform checks read the baked bytes (peak headroom, no silence-only asset,
## click-free loop boundaries); wiring checks drive the live `Arena` so every
## weapon, impact, kill and reward cue is proven on the real path with capped
## polyphony, rate limits, bus mutes and scene cleanup.

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena.tscn")

const MUSIC: Dictionary = {
	"res://assets/custom/audio/music/arena_kinetic.wav": 14.55,
	"res://assets/custom/audio/music/arena_ember.wav": 15.24,
	"res://assets/custom/audio/music/arena_watch.wav": 13.91,
	"res://assets/custom/audio/music/guardian_assault.wav": 17.14,
	"res://assets/custom/audio/music/guardian_hunt.wav": 12.63,
	"res://assets/custom/audio/music/guardian_storm.wav": 15.00,
}
const ARENA_POOL: Array[String] = [
	"res://assets/custom/audio/music/arena_kinetic.wav",
	"res://assets/custom/audio/music/arena_ember.wav",
	"res://assets/custom/audio/music/arena_watch.wav",
]
const GUARDIAN_POOL: Array[String] = [
	"res://assets/custom/audio/music/guardian_assault.wav",
	"res://assets/custom/audio/music/guardian_hunt.wav",
	"res://assets/custom/audio/music/guardian_storm.wav",
]
const CUES: Array[String] = [
	"res://assets/custom/audio/sfx/weapon_sword.wav",
	"res://assets/custom/audio/sfx/weapon_twin.wav",
	"res://assets/custom/audio/sfx/weapon_rifle.wav",
	"res://assets/custom/audio/sfx/weapon_shotgun.wav",
	"res://assets/custom/audio/sfx/weapon_cannon.wav",
	"res://assets/custom/audio/sfx/weapon_scythe.wav",
	"res://assets/custom/audio/sfx/impact_hit.wav",
	"res://assets/custom/audio/sfx/kill_pop.wav",
	"res://assets/custom/audio/sfx/level_up.wav",
	"res://assets/custom/audio/sfx/core_pickup.wav",
	"res://assets/custom/audio/sfx/overcharge_win.wav",
]
const WEAPON_CUE: Dictionary = {
	"warden": "weapon_sword.wav",
	"dancer": "weapon_twin.wav",
	"sage": "weapon_rifle.wav",
	"keeper": "weapon_shotgun.wav",
	"knight": "weapon_cannon.wav",
	"eclipse": "weapon_scythe.wav",
}
const HERO_IDS: Array[String] = [
	"warden", "dancer", "keeper", "knight", "eclipse", "sage",
]
## Melee heroes swing their primary and shoot their sidearm; ranged heroes reverse it.
const MELEE_HEROES: Array[String] = ["warden", "dancer", "eclipse"]
const SIDEARM_CUE: Dictionary = {
	"warden": "weapon_twin.wav",
	"dancer": "weapon_twin.wav",
	"eclipse": "weapon_twin.wav",
	"sage": "weapon_sword.wav",
	"keeper": "weapon_sword.wav",
	"knight": "weapon_sword.wav",
}

var _failed: int = 0
var _checked: int = 0


class DurableTargetSpirit:
	extends Node2D

	var hits: int = 0

	func is_attackable() -> bool:
		return true

	func take_damage(_amount: int, _at: Vector2) -> void:
		hits += 1


func _ready() -> void:
	if not _is_isolated():
		get_tree().quit(2)
		return
	_run.call_deferred()


func _is_isolated() -> bool:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = not expected_root.is_empty() and user_root.begins_with(expected_root + "/")
	if not safe:
		printerr("combat-audio test aborted: user:// path is not isolated — ", user_root)
	return safe


func _run() -> void:
	_test_baked_waveforms()
	await _test_weapon_wiring()
	await _test_simultaneous_clocks()
	await _test_impact_and_kill()
	await _test_rewards()
	await _test_music_rotation()
	await _test_track_end_rotation()
	await _test_playback_runs_past_seconds()
	await _test_release_silences_all()
	await _test_bounds_and_mute()
	if _failed > 0:
		printerr("combat-audio test failed — ", _failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("combat-audio test passed — ", _checked, " case(s)")
	get_tree().quit(0)


## Read one baked cue: peak headroom, audible body, exact duration.
func _read_cue(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	_expect_true(bytes.size() > 44, path.get_file() + " baked bytes exist")
	if bytes.size() <= 44:
		return {}
	var count: int = int((bytes.size() - 44) / 2)
	var peak: int = 0
	var sum_squares: float = 0.0
	for index in count:
		var sample: int = bytes.decode_s16(44 + index * 2)
		peak = maxi(peak, absi(sample))
		sum_squares += float(sample * sample)
	var rms: float = sqrt(sum_squares / float(maxi(count, 1))) / 32767.0
	return {
		"peak": float(peak) / 32767.0,
		"rms": rms,
		"seconds": float(count) / 22050.0,
		"first": float(bytes.decode_s16(44)) / 32767.0,
		"last": float(bytes.decode_s16(44 + (count - 1) * 2)) / 32767.0,
	}


func _test_baked_waveforms() -> void:
	for path in MUSIC.keys():
		var cue: Dictionary = _read_cue(path)
		if cue.is_empty():
			continue
		_expect_true(float(cue["peak"]) < 0.95,
			path.get_file() + " leaves mix headroom")
		_expect_true(float(cue["rms"]) > 0.01,
			path.get_file() + " is not a silence-only asset")
		_expect_true(absf(float(cue["seconds"]) - float(MUSIC[path])) < 0.05,
			path.get_file() + " duration holds")
		_expect_true(absf(float(cue["last"]) - float(cue["first"])) < 0.02,
			path.get_file() + " loop boundary cannot click")
	for path in CUES:
		var cue: Dictionary = _read_cue(path)
		if cue.is_empty():
			continue
		_expect_true(float(cue["peak"]) < 0.95,
			path.get_file() + " leaves mix headroom")
		_expect_true(float(cue["rms"]) > 0.01,
			path.get_file() + " is not a silence-only asset")


func _fresh_arena(hero_id: String) -> Array:
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	for spirit in (arena.get("_spirits") as Array).duplicate():
		if is_instance_valid(spirit):
			spirit.queue_free()
	(arena.get("_spirits") as Array).clear()
	arena.set("_spawn_timer", 99999.0)
	arena.set("_raid_left", 99999.0)
	arena.set_process(false)
	# The cycle-opening hero line is still up: settle it so gain checks start
	# unducked. Voice-line ducking itself is asserted separately below.
	(arena.get("_voice_panel") as Control).call("clear")
	arena.call("_update_duck")
	var hero: Hero = load("res://resources/heroes/%s.tres" % hero_id) as Hero
	arena.set("_run_hero", hero)
	arena.set("_run_hero_path", "res://resources/heroes/%s.tres" % hero_id)
	var player: Node2D = arena.get_node("Player") as Node2D
	player.call("apply_hero_visual", hero)
	arena.call("_recompute")
	arena.call("_settle_rates")
	return [arena, player]


func _target(arena: Node2D, player: Node2D, offset: Vector2) -> DurableTargetSpirit:
	var double := DurableTargetSpirit.new()
	arena.add_child(double)
	double.global_position = (player as Node2D).global_position + offset
	(arena.get("_spirits") as Array).append(double)
	return double


func _free_arena(arena: Node2D) -> void:
	for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
		if is_instance_valid(projectile) and projectile.is_inside_tree() \
				and arena.is_ancestor_of(projectile):
			projectile.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## Every hero's primary speaks its own cue loud on its own voice; the sidearm
## answers quiet on the backup voice.
func _test_weapon_wiring() -> void:
	for hero_id in HERO_IDS:
		var setup: Array = await _fresh_arena(hero_id)
		var arena: Node2D = setup[0]
		var player: Node2D = setup[1]
		var melee_primary: bool = MELEE_HEROES.has(hero_id)
		var swing_want: String = "res://assets/custom/audio/sfx/%s" \
			% str(WEAPON_CUE[hero_id] if melee_primary else SIDEARM_CUE[hero_id])
		var volley_want: String = "res://assets/custom/audio/sfx/%s" \
			% str(SIDEARM_CUE[hero_id] if melee_primary else WEAPON_CUE[hero_id])
		var music_before: AudioStream = \
			(arena.get_node("Bgm") as AudioStreamPlayer).stream
		var primary: AudioStreamPlayer = arena.get_node("WeaponSfx") as AudioStreamPlayer
		var backup: AudioStreamPlayer = arena.get_node("SidearmSfx") as AudioStreamPlayer
		var close: DurableTargetSpirit = _target(arena, player, Vector2(37, 0))
		player.set("_attack_cooldown", 0.0)
		arena.call("_swing_at", close)
		if melee_primary:
			_expect_true(primary.stream == load(swing_want), hero_id + " swing voice")
			_expect_equal(primary.volume_db, -9.0,
				hero_id + " swing gain follows primary/sidearm")
		else:
			_expect_true(backup.stream == load(swing_want), hero_id + " swing voice")
			_expect_equal(backup.volume_db, -15.0,
				hero_id + " swing gain follows primary/sidearm")
		# Past the rate gap so the volley is heard as its own call.
		arena.call("_tick_combat_sfx", 0.1)
		arena.set("_arrow_timer", 0.0)
		arena.call("_fire_arrows", 1.0)
		if melee_primary:
			_expect_true(backup.stream == load(volley_want), hero_id + " volley voice")
			_expect_equal(backup.volume_db, -15.0,
				hero_id + " volley gain follows primary/sidearm")
		else:
			_expect_true(primary.stream == load(volley_want), hero_id + " volley voice")
			_expect_equal(primary.volume_db, -9.0,
				hero_id + " volley gain follows primary/sidearm")
		_expect_true(primary.max_polyphony == 3, "primary player caps its voices")
		_expect_true(backup.max_polyphony == 2, "sidearm player caps its voices")
		# Combat never swaps or restarts the music: the stream is untouched.
		_expect_true(
			(arena.get_node("Bgm") as AudioStreamPlayer).stream == music_before,
			hero_id + " hits leave the music stream alone")
		await _free_arena(arena)


## Both real clocks fire in one tick: the signature primary cue must survive
## on its own voice even though the sidearm call lands in the same gate.
## Driven through the real `Arena._process`, not staged direct calls.
func _test_simultaneous_clocks() -> void:
	for hero_id in HERO_IDS:
		var setup: Array = await _fresh_arena(hero_id)
		var arena: Node2D = setup[0]
		var player: Node2D = setup[1]
		# Keeper and Sage backup bashes bite shorter than 37px; seat their
		# target inside the bite so the live path genuinely swings.
		var pocket: float = 25.0 if hero_id in ["keeper", "sage"] else 37.0
		_target(arena, player, Vector2(pocket, 0))
		player.set("_attack_cooldown", 0.0)
		arena.set("_arrow_timer", 0.0)
		arena.set("_weapon_sfx_left", 0.0)
		arena.set("_sidearm_sfx_left", 0.0)
		var shots_before: int = _arena_shots(arena)
		arena.call("_process", 1.0 / 30.0)
		var primary: AudioStreamPlayer = arena.get_node("WeaponSfx") as AudioStreamPlayer
		var backup: AudioStreamPlayer = arena.get_node("SidearmSfx") as AudioStreamPlayer
		_expect_true(primary.stream
			== load("res://assets/custom/audio/sfx/%s" % str(WEAPON_CUE[hero_id])),
			hero_id + " keeps its primary cue when both clocks fire")
		_expect_equal(primary.volume_db, -9.0,
			hero_id + " primary cue stays loud on its own voice")
		_expect_true(backup.stream
			== load("res://assets/custom/audio/sfx/%s" % str(SIDEARM_CUE[hero_id])),
			hero_id + " sidearm answers on the backup voice")
		_expect_true(_arena_shots(arena) > shots_before,
			hero_id + " volley clock fired in the same tick")
		await _free_arena(arena)
	# Evolved builds keep the same signature cues on the same voices: a primed
	# full-moon swing for the Dancer, an evolved Starfall meteor volley for the Sage.
	var dancer: Array = await _fresh_arena("dancer")
	await _take_relics(dancer[0], [
		"res://resources/relics/long_blade.tres",
		"res://resources/relics/swift_hand.tres",
		"res://resources/relics/sharp_moon.tres",
		"res://resources/relics/wide_arc.tres",
		"res://resources/relics/long_blade.tres",
		"res://resources/relics/swift_hand.tres",
	])
	_expect_true(
		Relic.family_evolved(dancer[0].get("_taken"), Relic.Family.FULL_MOON),
		"dancer full-moon build is genuinely evolved")
	dancer[0].set("_full_moon_primed", true)
	_target(dancer[0], dancer[1], Vector2(37, 0))
	dancer[1].set("_attack_cooldown", 0.0)
	dancer[0].set("_arrow_timer", 0.0)
	dancer[0].set("_weapon_sfx_left", 0.0)
	dancer[0].set("_sidearm_sfx_left", 0.0)
	dancer[0].call("_process", 1.0 / 30.0)
	_expect_true(not bool(dancer[0].get("_full_moon_primed")),
		"evolved dancer swing consumed its full-moon prime")
	_expect_true((dancer[0].get_node("WeaponSfx") as AudioStreamPlayer).stream
		== load("res://assets/custom/audio/sfx/weapon_twin.wav"),
		"evolved dancer keeps its primary cue")
	_expect_true((dancer[0].get_node("SidearmSfx") as AudioStreamPlayer).stream
		== load("res://assets/custom/audio/sfx/weapon_twin.wav"),
		"evolved dancer backup answers on its own voice")
	await _free_arena(dancer[0])
	var sage: Array = await _fresh_arena("sage")
	await _take_relics(sage[0], [
		"res://resources/relics/twin_arrow.tres",
		"res://resources/relics/pierce_arrow.tres",
		"res://resources/relics/quick_arrow.tres",
		"res://resources/relics/heavy_arrow.tres",
		"res://resources/relics/twin_arrow.tres",
		"res://resources/relics/pierce_arrow.tres",
	])
	_expect_true(
		Relic.family_evolved(sage[0].get("_taken"), Relic.Family.STARFALL),
		"sage starfall build is genuinely evolved")
	_expect_true(bool(sage[0].call("_starfall_evolved")),
		"evolved sage volley rides the meteor path")
	_target(sage[0], sage[1], Vector2(25, 0))
	sage[1].set("_attack_cooldown", 0.0)
	sage[0].set("_arrow_timer", 0.0)
	sage[0].set("_weapon_sfx_left", 0.0)
	sage[0].set("_sidearm_sfx_left", 0.0)
	sage[0].call("_process", 1.0 / 30.0)
	_expect_true((sage[0].get_node("WeaponSfx") as AudioStreamPlayer).stream
		== load("res://assets/custom/audio/sfx/weapon_rifle.wav"),
		"evolved sage keeps its primary cue")
	_expect_true((sage[0].get_node("SidearmSfx") as AudioStreamPlayer).stream
		== load("res://assets/custom/audio/sfx/weapon_sword.wav"),
		"evolved sage backup answers on its own voice")
	await _free_arena(sage[0])


## Production card takes, one frame apart so HUD and rate settles land.
func _take_relics(arena: Node2D, paths: Array) -> void:
	for path in paths:
		arena.call("_on_relic_picked",
			arena.get("_relic").call("take_named", path), false, "stage")
		await get_tree().process_frame
	arena.call("_settle_rates")


func _arena_shots(arena: Node2D) -> int:
	var total: int = 0
	for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
		if is_instance_valid(projectile) and arena.is_ancestor_of(projectile):
			total += 1
	return total


## Hits report to the arena's impact voice; kills pop. No audio nodes on shots.
func _test_impact_and_kill() -> void:
	var setup: Array = await _fresh_arena("knight")
	var arena: Node2D = setup[0]
	var player: Node2D = setup[1]
	var direct: DurableTargetSpirit = _target(arena, player, Vector2(120, 0))
	arena.set("_arrow_timer", 0.0)
	arena.call("_fire_arrows", 1.0)
	for frame in 150:
		await get_tree().physics_frame
		if direct.hits > 0:
			break
	_expect_true(direct.hits > 0, "cannon shell lands for the impact check")
	_expect_true(
		(arena.get_node("ImpactSfx") as AudioStreamPlayer).stream
			== load("res://assets/custom/audio/sfx/impact_hit.wav"),
		"shell landing reports an impact")
	var audio_on_shots: int = 0
	for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
		audio_on_shots += _count_audio_players(projectile)
	_expect_equal(audio_on_shots, 0, "no projectile carries an audio node")
	var kind: SpiritKind = load("res://resources/wisp.tres") as SpiritKind
	arena.call("_on_spirit_perished", kind,
		(player as Node2D).global_position, false)
	_expect_true(
		(arena.get_node("RewardSfx") as AudioStreamPlayer).stream
			== load("res://assets/custom/audio/sfx/kill_pop.wav"),
		"kill pops its tick")
	# A second report inside the rate window is swallowed, not stacked.
	arena.call("combat_impact", Vector2.ZERO, false)
	arena.call("_tick_combat_sfx", 1.0)
	arena.call("combat_impact", Vector2.ZERO, false)
	_expect_equal(float(arena.get("_impact_sfx_left")), 0.09,
		"impact gate arms its floor")
	await _free_arena(arena)


func _count_audio_players(node: Node) -> int:
	var total: int = 0
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		total += 1
	for child in node.get_children():
		total += _count_audio_players(child)
	return total


## Level, core and overcharge each play their own cue on the growth voice while
## the kill tick keeps its own voice — the two overlap, never cut each other.
func _test_rewards() -> void:
	var setup: Array = await _fresh_arena("warden")
	var arena: Node2D = setup[0]
	var growth: AudioStreamPlayer = arena.get_node("GrowthSfx") as AudioStreamPlayer
	var reward: AudioStreamPlayer = arena.get_node("RewardSfx") as AudioStreamPlayer
	arena.set("_level_progress", int(arena.get("_to_next")) - 1)
	arena.call("_gain_progress", false)
	# The owed card would open (and pause) on the deferred boundary; run-end
	# input blocks it the same way the result screen does.
	arena.set("_over", true)
	_expect_true(growth.stream
		== load("res://assets/custom/audio/sfx/level_up.wav"),
		"level-up plays its surge")
	arena.set("_over", false)
	arena.call("_on_missile_core_collected", false)
	_expect_true(growth.stream
		== load("res://assets/custom/audio/sfx/core_pickup.wav"),
		"core pickup plays its chime")
	arena.set("_overcharge_beacon", (arena.get("_beacons") as Array)[0])
	arena.call("_finish_overcharge", true)
	_expect_true(growth.stream
		== load("res://assets/custom/audio/sfx/overcharge_win.wav"),
		"overcharge triumph plays its cue")
	_expect_true(growth.max_polyphony == 2, "growth player caps its voices")
	# Overlap: a kill pop during a growth surge keeps both streams intact.
	arena.call("_play_reward_sfx", load("res://assets/custom/audio/sfx/level_up.wav"))
	arena.set("_kill_sfx_left", 0.0)
	arena.call("_play_kill_sfx", false)
	_expect_true(growth.stream
		== load("res://assets/custom/audio/sfx/level_up.wav"),
		"kill never steals the growth voice")
	_expect_true(reward.stream
		== load("res://assets/custom/audio/sfx/kill_pop.wav"),
		"kill keeps its own voice during growth")
	# Latest growth call wins the growth voice.
	arena.call("_play_reward_sfx", load("res://assets/custom/audio/sfx/core_pickup.wav"))
	_expect_true(growth.stream
		== load("res://assets/custom/audio/sfx/core_pickup.wav"),
		"latest growth cue wins")
	await _free_arena(arena)


## The track bag tours each pool with no repeats; transitions stay in-pool and the
## guardian return comes home to an arena track.
func _test_music_rotation() -> void:
	var setup: Array = await _fresh_arena("sage")
	var arena: Node2D = setup[0]
	var bgm: AudioStreamPlayer = arena.get_node("Bgm") as AudioStreamPlayer
	_expect_true(ARENA_POOL.has(bgm.stream.resource_path),
		"run opens on an arena track")
	(arena.get("_music_rng") as RandomNumberGenerator).seed = 20260930
	# One full arena tour covers all three tracks exactly once.
	arena.set("_arena_bag", [] as Array[int])
	arena.set("_arena_track", -1)
	var tour: Array[int] = []
	for draw in 3:
		tour.append(int(arena.call("_draw_music_track", true)))
	tour.sort()
	_expect_equal(tour, [0, 1, 2] as Array[int], "arena bag tours all three")
	# Twenty draws, both pools: only pool indexes, never a repeat in a row.
	for pool in [true, false]:
		arena.set("_arena_bag" if pool else "_guardian_bag", [] as Array[int])
		arena.set("_arena_track" if pool else "_guardian_track", -1)
		var prev: int = -1
		var clean: bool = true
		for draw in 20:
			var track: int = int(arena.call("_draw_music_track", pool))
			if track < 0 or track > 2 or track == prev:
				clean = false
			prev = track
		_expect_true(clean,
			("arena" if pool else "guardian") + " bag never repeats in a row")
	# Transitions ride the real switch path, pool to pool and back home.
	arena.call("_select_guardian_theme")
	_expect_true(GUARDIAN_POOL.has(bgm.stream.resource_path),
		"encounter draws a guardian track")
	_expect_true(bgm.pitch_scale > float(arena.call("_arena_bgm_pitch")),
		"encounter pushes the tempo harder")
	arena.call("_select_arena_theme")
	_expect_true(ARENA_POOL.has(bgm.stream.resource_path),
		"guardian return comes home to an arena track")
	await _free_arena(arena)


## Staying in one mode rolls the bag at the end of a whole track: the wrap is
## read off the audio clock, so pause, time scale and release cannot strand it.
func _test_track_end_rotation() -> void:
	var setup: Array = await _fresh_arena("sage")
	var arena: Node2D = setup[0]
	var bgm: AudioStreamPlayer = arena.get_node("Bgm") as AudioStreamPlayer
	for pool in [true, false]:
		arena.call("_select_guardian_theme" if not pool else "_select_arena_theme")
		var first: AudioStream = bgm.stream
		var names: Array[String] = GUARDIAN_POOL if not pool else ARENA_POOL
		_expect_true(names.has(first.resource_path),
			("guardian" if not pool else "arena") + " roll starts in-pool")
		var length: float = (first as AudioStreamWAV).get_length()
		bgm.seek(length - 1.5)
		await get_tree().process_frame
		await get_tree().process_frame
		arena.call("_tick_music_rotation")
		var rolled: bool = false
		for poll in 60:
			await get_tree().create_timer(0.2, true, false, true).timeout
			arena.call("_tick_music_rotation")
			if bgm.stream != first:
				rolled = true
				break
		_expect_true(rolled,
			("guardian" if not pool else "arena") + " rolls to its next track")
		if bgm.stream != first:
			_expect_true(names.has(bgm.stream.resource_path),
				("guardian" if not pool else "arena") + " roll stays in-pool")
	# A mode switch right before the wrap wins: past the old track's end the
	# roll still draws the new pool, never a stale arena continuation.
	arena.call("_select_arena_theme")
	var arena_track: AudioStream = bgm.stream
	bgm.seek((arena_track as AudioStreamWAV).get_length() - 1.0)
	await get_tree().process_frame
	arena.call("_tick_music_rotation")
	arena.call("_select_guardian_theme")
	for poll in 12:
		await get_tree().create_timer(0.2, true, false, true).timeout
		arena.call("_tick_music_rotation")
	_expect_true(GUARDIAN_POOL.has(bgm.stream.resource_path),
		"switch before the wrap continues the guardian pool")
	# A paused choice freezes the audio clock: the roll waits for resume.
	bgm.seek((bgm.stream as AudioStreamWAV).get_length() - 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.call("_tick_music_rotation")
	var held: AudioStream = bgm.stream
	get_tree().paused = true
	await get_tree().process_frame
	for tick in 3:
		arena.call("_tick_music_rotation")
	_expect_true(bgm.stream == held, "pause holds the track past its end")
	get_tree().paused = false
	await get_tree().process_frame
	# At bot time scale the audible phrase still plays whole: no countdown cut.
	Engine.time_scale = 3.0
	bgm.seek(2.0)
	await get_tree().process_frame
	await get_tree().process_frame
	arena.call("_tick_music_rotation")
	var scaled: AudioStream = bgm.stream
	for tick in 10:
		await get_tree().create_timer(0.2, true, false, true).timeout
		arena.call("_tick_music_rotation")
	_expect_true(bgm.stream == scaled, "time scale 3 keeps the mid-track phrase")
	Engine.time_scale = 1.0
	await _free_arena(arena)


## Every pool track genuinely plays past every QOA-byte cutoff: all six sit
## under 100000 samples (4.54s), so with the bytes/2 endpoint the position
## would wrap before 4.5s; with decoded-sample endpoints it sails through.
func _test_playback_runs_past_seconds() -> void:
	var setup: Array = await _fresh_arena("warden")
	var arena: Node2D = setup[0]
	var bgm: AudioStreamPlayer = arena.get_node("Bgm") as AudioStreamPlayer
	for path in ARENA_POOL + GUARDIAN_POOL:
		bgm.stop()
		bgm.stream = load(path) as AudioStreamWAV
		arena.call("_loop_bgm", bgm.stream)
		bgm.pitch_scale = 1.0
		bgm.play()
		# Poll the audio clock, not the wall: a loaded machine mixes slower
		# than real time, but a wrapped loop never reaches 4.5s either way.
		var reached: bool = false
		for poll in 100:
			await get_tree().create_timer(0.2, true, false, true).timeout
			if bgm.get_playback_position() >= 4.5:
				reached = true
				break
		_expect_true(reached,
			path.get_file() + " plays past the old cutoff without wrapping")
		bgm.stop()
	await _free_arena(arena)


## Release silences every combat voice while a long cue is actually active —
## the growth surge included — and drops every stream, so no voice plays on
## past the scene swap.
func _test_release_silences_all() -> void:
	var setup: Array = await _fresh_arena("knight")
	var arena: Node2D = setup[0]
	arena.call("_play_weapon_sfx", Hero.AttackProfile.KNIGHT, false)
	arena.call("_play_weapon_sfx", Hero.AttackProfile.KNIGHT, true)
	arena.call("combat_impact", Vector2.ZERO, true)
	arena.set("_kill_sfx_left", 0.0)
	arena.call("_play_kill_sfx", false)
	arena.call("_play_reward_sfx",
		load("res://assets/custom/audio/sfx/overcharge_win.wav"))
	(arena.get_node("EventSfx") as AudioStreamPlayer).play()
	(arena.get_node("PickupSfx") as AudioStreamPlayer).play()
	_expect_true((arena.get_node("GrowthSfx") as AudioStreamPlayer).playing,
		"long growth cue is live before release")
	await arena.call("_release_audio")
	for voice_name in ["Bgm", "EventSfx", "PickupSfx", "WeaponSfx", "SidearmSfx",
		"ImpactSfx", "RewardSfx", "GrowthSfx"]:
		var voice: AudioStreamPlayer = arena.get_node(voice_name) as AudioStreamPlayer
		_expect_true(not voice.playing, voice_name + " stops on release")
		_expect_true(voice.stream == null, voice_name + " drops its stream")
	# A tick after release cannot resurrect a voice or roll a stopped track.
	arena.call("_tick_music_rotation")
	arena.call("_update_duck")
	_expect_true((arena.get_node("Bgm") as AudioStreamPlayer).stream == null,
		"released music stays stopped")
	await _free_arena(arena)


## Loops are configured, ducking answers dialogue, bus mutes hold, cleanup frees.
func _test_bounds_and_mute() -> void:
	var setup: Array = await _fresh_arena("sage")
	var arena: Node2D = setup[0]
	var bgm: AudioStreamPlayer = arena.get_node("Bgm") as AudioStreamPlayer
	_expect_true(bgm.stream is AudioStreamWAV, "bgm rides a baked wav")
	# Every pool track loops its whole decoded sample, not its QOA byte count.
	for path in ARENA_POOL + GUARDIAN_POOL:
		var loop: AudioStreamWAV = load(path) as AudioStreamWAV
		arena.call("_loop_bgm", loop)
		_expect_equal(loop.loop_mode, AudioStreamWAV.LOOP_FORWARD,
			path.get_file() + " loops")
		_expect_equal(loop.loop_begin, 0, path.get_file() + " loop starts at zero")
		var baked: int = int((FileAccess.get_file_as_bytes(path).size() - 44) / 2)
		_expect_true(loop.loop_end > 100000,
			path.get_file() + " endpoint is decoded samples, not QOA bytes")
		_expect_true(absi(loop.loop_end - baked) <= 20,
			path.get_file() + " loop spans the whole sample")
	# Mirror the production swap order: stop first or the looped playback orphans.
	var guardian: AudioStreamWAV = load(GUARDIAN_POOL[0]) as AudioStreamWAV
	bgm.stop()
	bgm.stream = guardian
	arena.call("_loop_bgm", guardian)
	bgm.play()
	_expect_equal(guardian.loop_mode, AudioStreamWAV.LOOP_FORWARD,
		"guardian music loops on swap")
	# Ducking: a visible choice drops combat voices until it closes.
	(arena.get("_relic") as Control).visible = true
	arena.call("_tick_combat_sfx", 0.1)
	_expect_equal(
		float((arena.get_node("WeaponSfx") as AudioStreamPlayer).volume_db),
		-22.0, "choice ducks the weapon voice")
	_expect_equal(
		float((arena.get_node("SidearmSfx") as AudioStreamPlayer).volume_db),
		-22.0, "choice ducks the sidearm voice")
	_expect_equal(
		float((arena.get_node("GrowthSfx") as AudioStreamPlayer).volume_db),
		-22.0, "choice ducks the growth voice")
	(arena.get("_relic") as Control).visible = false
	arena.call("_tick_combat_sfx", 0.1)
	_expect_equal(
		float((arena.get_node("WeaponSfx") as AudioStreamPlayer).volume_db),
		-9.0, "closing restores the weapon voice")
	_expect_equal(
		float((arena.get_node("SidearmSfx") as AudioStreamPlayer).volume_db),
		-15.0, "closing restores the sidearm voice")
	# A hero voice line ducks even though the game never pauses for it.
	(arena.get("_voice_panel") as Control).visible = true
	arena.call("_tick_combat_sfx", 0.1)
	_expect_equal(
		float((arena.get_node("WeaponSfx") as AudioStreamPlayer).volume_db),
		-22.0, "hero line ducks the weapon voice")
	(arena.get("_voice_panel") as Control).visible = false
	# A paused tree ducks through the notification path, not the frozen tick.
	get_tree().paused = true
	await get_tree().process_frame
	_expect_equal(
		float((arena.get_node("WeaponSfx") as AudioStreamPlayer).volume_db),
		-22.0, "pause ducks the weapon voice")
	get_tree().paused = false
	await get_tree().process_frame
	_expect_equal(
		float((arena.get_node("WeaponSfx") as AudioStreamPlayer).volume_db),
		-9.0, "unpause restores the weapon voice")
	# Settings buses mute for real and restore afterwards.
	var music_bus: int = AudioServer.get_bus_index("Music")
	var sfx_bus: int = AudioServer.get_bus_index("Sfx")
	Settings.set_music(0)
	Settings.set_sfx(0)
	_expect_true(AudioServer.is_bus_mute(music_bus), "music bus mutes")
	_expect_true(AudioServer.is_bus_mute(sfx_bus), "sfx bus mutes")
	Settings.set_music(4)
	Settings.set_sfx(4)
	_expect_true(not AudioServer.is_bus_mute(music_bus), "music bus restores")
	_expect_true(not AudioServer.is_bus_mute(sfx_bus), "sfx bus restores")
	# Await the release: the audio thread needs its mix before the free, and the
	# quit below must not race it the way `AudioFlush` documents.
	await arena.call("_release_audio")
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_true(not is_instance_valid(arena), "arena frees after release")
	await get_tree().create_timer(0.25, true).timeout


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)
