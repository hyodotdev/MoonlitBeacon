extends SceneTree

## Pure check contract for two-effect resonance before final evolution.
##
## Stacking the same card is not resonance material, and losing a component
## on hit must turn resonance off immediately. Final evolution always includes the resonance that came before it.

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_test_duplicate_does_not_resonate()
	_test_two_distinct_effects_resonate()
	_test_moon_dance_requires_both_effects()
	_test_evolution_preserves_resonance()
	_test_loss_drops_resonance()
	_test_none_never_resonates()
	_finish()


func _test_duplicate_does_not_resonate() -> void:
	var relics: Array[Relic] = [
		_relic(Relic.Effect.ARROW_COUNT),
		_relic(Relic.Effect.ARROW_COUNT),
	]
	_expect_false(
		Relic.family_resonant(relics, Relic.Family.STARFALL),
		"two stacks of the same Starfall effect do not resonate")
	_expect_false(
		bool(Relic.family_state(relics, Relic.Family.STARFALL)["resonant"]),
		"state dict also exposes duplicate-effect resonance as false")


func _test_two_distinct_effects_resonate() -> void:
	var starfall: Array[Relic] = [
		_relic(Relic.Effect.ARROW_COUNT),
		_relic(Relic.Effect.ARROW_PIERCE),
	]
	var full_moon: Array[Relic] = [
		_relic(Relic.Effect.ATTACK_RANGE),
		_relic(Relic.Effect.ATTACK_SPEED),
	]
	_expect_true(
		Relic.family_resonant(starfall, Relic.Family.STARFALL),
		"Starfall resonates with two distinct effects")
	_expect_true(
		Relic.family_resonant(full_moon, Relic.Family.FULL_MOON),
		"Full Moon resonates with two distinct effects")


func _test_moon_dance_requires_both_effects() -> void:
	var duplicate_ring: Array[Relic] = [
		_relic(Relic.Effect.MOON_RING),
		_relic(Relic.Effect.MOON_RING),
	]
	_expect_false(
		Relic.family_resonant(duplicate_ring, Relic.Family.MOON_DANCE),
		"duplicate Moon Dance rings do not resonate")
	duplicate_ring[1] = _relic(Relic.Effect.MOON_RIPPLE)
	_expect_true(
		Relic.family_resonant(duplicate_ring, Relic.Family.MOON_DANCE),
		"Moon Dance resonates after learning both Ring and Ripple")


func _test_evolution_preserves_resonance() -> void:
	var relics: Array[Relic] = [
		_relic(Relic.Effect.ARROW_COUNT),
		_relic(Relic.Effect.ARROW_PIERCE),
		_relic(Relic.Effect.ARROW_SPEED),
		_relic(Relic.Effect.ARROW_DAMAGE),
		_relic(Relic.Effect.ARROW_COUNT),
		_relic(Relic.Effect.ARROW_PIERCE),
	]
	var state: Dictionary = Relic.family_state(relics, Relic.Family.STARFALL)
	_expect_true(bool(state["evolved"]), "Starfall final-evolution condition holds")
	_expect_true(bool(state["resonant"]), "final-evolution state also keeps resonance")


func _test_loss_drops_resonance() -> void:
	var relics: Array[Relic] = [
		_relic(Relic.Effect.ATTACK_DAMAGE),
		_relic(Relic.Effect.ATTACK_ARC),
	]
	_expect_true(
		Relic.family_resonant(relics, Relic.Family.FULL_MOON),
		"Full Moon resonates before loss")
	relics.pop_back()
	_expect_false(
		Relic.family_resonant(relics, Relic.Family.FULL_MOON),
		"losing one component clears Full Moon resonance")
	_expect_false(
		bool(Relic.family_state(relics, Relic.Family.FULL_MOON)["resonant"]),
		"state dict resonance is also false after loss")


func _test_none_never_resonates() -> void:
	var relics: Array[Relic] = [
		_relic(Relic.Effect.MOVE_SPEED),
		_relic(Relic.Effect.MAX_HEALTH),
		_relic(Relic.Effect.DASH_COOLDOWN),
	]
	_expect_false(
		Relic.family_resonant(relics, Relic.Family.NONE),
		"pathless support relics do not resonate")
	_expect_false(
		bool(Relic.family_state(relics, Relic.Family.NONE)["resonant"]),
		"NONE state dict resonance is also false")


func _relic(effect: Relic.Effect) -> Relic:
	var relic: Relic = Relic.new()
	relic.effect = effect
	return relic


func _finish() -> void:
	if _failed > 0:
		printerr("relic-resonance test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("relic-resonance test passed — ", _checked, " case(s)")
	quit(0)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  failed: ", label, " — expected ", expected, ", got ", actual)


func _expect_true(value: bool, label: String) -> void:
	_expect_equal(value, true, label)


func _expect_false(value: bool, label: String) -> void:
	_expect_equal(value, false, label)
