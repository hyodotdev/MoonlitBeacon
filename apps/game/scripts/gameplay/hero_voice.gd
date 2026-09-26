class_name HeroVoice
extends RefCounted

## Picks what to say in a given moment.
##
## Three rules:
##   1. **Never the same line twice in one run.** Hear it again and the line
##      becomes background noise.
##   2. Several lines per situation, picked at random. The second run must
##      differ from the first or "this character is speaking" dies.
##   3. When the lines run out, that situation stays quiet. Do not force a repeat.
##
## Copy lives in the translation table (`VOICE_<moment>_<n>`). All five languages
## travel together.

## Situation key → translation keys available for that situation.
const LINES: Dictionary = {
	"beacon_first": ["VOICE_BEACON_FIRST_1", "VOICE_BEACON_FIRST_2"],
	"beacon_mid": ["VOICE_BEACON_MID_1", "VOICE_BEACON_MID_2"],
	"beacon_last": ["VOICE_BEACON_LAST_1", "VOICE_BEACON_LAST_2"],
	"swarm": ["VOICE_SWARM_1", "VOICE_SWARM_2", "VOICE_SWARM_3"],
	"guardian": ["VOICE_GUARDIAN_1", "VOICE_GUARDIAN_2"],
	"guardian_down": ["VOICE_GUARDIAN_DOWN_1", "VOICE_GUARDIAN_DOWN_2"],
	"low_health": ["VOICE_LOW_1", "VOICE_LOW_2"],
	"moonfire": ["VOICE_MOONFIRE_1", "VOICE_MOONFIRE_2"],
	"cycle": [
		"VOICE_CYCLE_1", "VOICE_CYCLE_2", "VOICE_CYCLE_3",
		"VOICE_CYCLE_4", "VOICE_CYCLE_5", "VOICE_CYCLE_6",
	],
	"meet_drifter": ["VOICE_MEET_DRIFTER_1"],
	"meet_ember": ["VOICE_MEET_EMBER_1"],
	"meet_caster": ["VOICE_MEET_CASTER_1"],
	"meet_weaver": ["VOICE_MEET_WEAVER_1"],
	"meet_stalker": ["VOICE_MEET_STALKER_1"],
	"meet_swarm": ["VOICE_MEET_SWARM_1"],
	"meet_wisp": ["VOICE_MEET_WISP_1"],
	"meet_guardian_forest": ["VOICE_MEET_GUARDIAN_FOREST_1"],
	"meet_guardian_field": ["VOICE_MEET_GUARDIAN_FIELD_1"],
	"meet_guardian_camp": ["VOICE_MEET_GUARDIAN_CAMP_1"],
	"meet_guardian_forest_thorn": ["VOICE_MEET_GUARDIAN_FOREST_THORN_1"],
	"meet_guardian_field_storm": ["VOICE_MEET_GUARDIAN_FIELD_STORM_1"],
	"meet_guardian_camp_siege": ["VOICE_MEET_GUARDIAN_CAMP_SIEGE_1"],
	"call_dark": ["VOICE_CALL_DARK_1", "VOICE_CALL_DARK_2"],
}

## Translation keys already used this run.
var _spent: Dictionary = {}


## Clear at the start of a new run. The next run should hear the lines from scratch.
func reset() -> void:
	_spent.clear()


## Line for this situation. Empty string if none remain.
func take(moment: String) -> String:
	var keys: Array = LINES.get(moment, [])
	var fresh: Array[String] = []
	for key in keys:
		if not _spent.has(key):
			fresh.append(str(key))
	if fresh.is_empty():
		return ""
	var picked: String = fresh[randi() % fresh.size()]
	_spent[picked] = true
	return tr(picked)
