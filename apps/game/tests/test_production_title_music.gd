extends Node

## Production title music lifecycle: detached starts stay silent-safe.
##
## Boots the real production entry behind a logged-out stub host and pins
## the title BGM lifecycle the native combat boot tripped: starting title
## music while its initialized node is detached must be a silent no-op
## instead of erroring on a tree timer, a stop during the start delay must
## retire the pending play, and a stale stop must not release a newer
## start. The normal path is pinned too: an audible delayed fade to the
## configured target, and a transition stop that releases the players.

const PRODUCTION_SCENE: PackedScene = preload(
	"res://scenes/menus/production_entry.tscn")
## Real-time waits: headless frames run without vsync, so the 0.15s start
## delay and the 0.55s/0.9s fades are wall-clock waits, not frame counts.
const AFTER_DELAY_SECONDS: float = 0.4
const AFTER_FADE_OUT_SECONDS: float = 0.9
const AFTER_FADE_IN_SECONDS: float = 1.6
const SETTLE_SECONDS: float = 0.7
const VOLUME_TOLERANCE_DB: float = 0.5

var _failed: int = 0
var _checked: int = 0


## Logged-out stub: the gate stays parked for the title behind it.
class StubMusicHost extends Node:
	signal production_changed(state: Dictionary)
	signal production_conflict(local: Dictionary, cloud: Dictionary)
	signal production_error(error: Dictionary)

	func startup() -> void:
		pass

	func providers_for_entry() -> Array:
		return []

	func identity_for_entry() -> Dictionary:
		return {"stable_id": ""}

	func account_state() -> Dictionary:
		return {"offline": false}

	func saved_gate_summary() -> Dictionary:
		return {"has_save": false}

	func provider_label(provider_id: String) -> String:
		return provider_id

	func note_first_paint() -> void:
		pass

	func release_entry_hold() -> void:
		pass

	func cancel_entry_plan() -> void:
		pass


func _ready() -> void:
	get_tree().root.size = Vector2i(808, 360)
	_run.call_deferred()


func _run() -> void:
	await _test_detached_start_is_noop()
	await _test_stop_during_delay_stays_stopped()
	await _test_stale_stop_keeps_newer_start()
	await _test_normal_start_and_release()
	if _failed > 0:
		printerr("production-title-music test failed — ",
			_failed, "/", _checked, " case(s)")
		get_tree().quit(1)
		return
	print("production-title-music test passed — ", _checked, " case(s)")
	get_tree().quit(0)


## Detached-before-start: the initialized node leaves the tree, then a
## start and a stop arrive. Both must be silent no-ops: no tree timer,
## no tween, and the player untouched. The volume pin fails on the
## original implementation, which sets silence before erroring.
func _test_detached_start_is_noop() -> void:
	var production: ProductionEntry = await _booted_entry()
	var bgm: AudioStreamPlayer = production.get_node("Bgm") as AudioStreamPlayer
	get_tree().root.remove_child(production)
	_expect_true(not production.is_inside_tree(),
		"detached: entry leaves the tree")
	bgm.volume_db = ProductionEntry.BGM_VOLUME_DB
	production.call("_fade_in_music")
	await _frames(2)
	_expect_true(is_equal_approx(bgm.volume_db,
		ProductionEntry.BGM_VOLUME_DB),
		"detached: start touches nothing while detached")
	production.call("_fade_out_music")
	await _frames(2)
	_expect_true(is_equal_approx(bgm.volume_db,
		ProductionEntry.BGM_VOLUME_DB),
		"detached: stop touches nothing while detached")
	production.queue_free()
	await _frames(2)


## Stop during the start delay: the pending play must never land. The
## boot itself leaves starts pending, so stopping at once then waiting
## past the delay proves the retire. Fails on the original: the delay
## resumes into a play with no knowledge of the stop.
func _test_stop_during_delay_stays_stopped() -> void:
	var production: ProductionEntry = await _booted_entry()
	var bgm: AudioStreamPlayer = production.get_node("Bgm") as AudioStreamPlayer
	production.call("_fade_out_music")
	await get_tree().create_timer(AFTER_DELAY_SECONDS).timeout
	_expect_true(not bgm.playing,
		"stop-during-delay: pending start never plays")
	_expect_true(bgm.volume_db < ProductionEntry.BGM_VOLUME_DB,
		"stop-during-delay: player stays at rest gain")
	production.queue_free()
	await _frames(2)


## A stop superseded by a newer start must not release it when the old
## fade lands. Fails on the original: the stale fade completion
## releases the music the newer start just made audible.
func _test_stale_stop_keeps_newer_start() -> void:
	var production: ProductionEntry = await _booted_entry()
	var bgm: AudioStreamPlayer = production.get_node("Bgm") as AudioStreamPlayer
	production.call("_fade_out_music")
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	_expect_true(not bgm.playing,
		"stale-stop: baseline rests silent")
	production.call("_fade_out_music")
	production.call("_fade_in_music")
	await get_tree().create_timer(AFTER_FADE_OUT_SECONDS).timeout
	_expect_true(bgm.playing,
		"stale-stop: newer start survives the old fade")
	production.queue_free()
	await _frames(2)


## The normal path is unchanged: a delayed fade to the configured
## target, audible through the gate intents, and a transition stop
## that releases the players.
func _test_normal_start_and_release() -> void:
	var production: ProductionEntry = await _booted_entry()
	var bgm: AudioStreamPlayer = production.get_node("Bgm") as AudioStreamPlayer
	await get_tree().create_timer(AFTER_FADE_IN_SECONDS).timeout
	_expect_true(bgm.playing, "normal: title music audible after its delay")
	_expect_true(absf(bgm.volume_db - ProductionEntry.BGM_VOLUME_DB)
		< VOLUME_TOLERANCE_DB,
		"normal: fade reaches the configured target")
	production.call("_on_music_intent", &"stop")
	await get_tree().create_timer(AFTER_FADE_OUT_SECONDS).timeout
	_expect_true(not bgm.playing,
		"normal: transition stop releases title music")
	production.call("_on_music_intent", &"play")
	await get_tree().create_timer(AFTER_FADE_IN_SECONDS).timeout
	_expect_true(bgm.playing,
		"normal: play intent restores title music")
	production.queue_free()
	await _frames(2)


## A live production entry with its ready-time music intents still
## pending: two frames in, before the 0.15s start delay can elapse.
func _booted_entry() -> ProductionEntry:
	var production: ProductionEntry = PRODUCTION_SCENE.instantiate() \
		as ProductionEntry
	var stub := StubMusicHost.new()
	# Ride along as a child so the override outlives every frame the
	# entry paints: freeing it first would leave _host pointing freed.
	production.add_child(stub)
	production.set_host_override(stub)
	get_tree().root.add_child(production)
	await _frames(2)
	return production


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _expect_true(actual: bool, label: String) -> void:
	_checked += 1
	if actual:
		return
	_failed += 1
	printerr("  FAIL ", label)
