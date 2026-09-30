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
		# Said once the Moonless has a name (cycle 10+), so the endless stretch
		# keeps talking about the thing it is now walking into.
		"VOICE_CYCLE_7", "VOICE_CYCLE_8",
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
	"meet_guardian_frost": ["VOICE_MEET_GUARDIAN_FROST_1"],
	"meet_guardian_marsh": ["VOICE_MEET_GUARDIAN_MARSH_1"],
	"meet_guardian_ruins": ["VOICE_MEET_GUARDIAN_RUINS_1"],
	"meet_guardian_frost_rime": ["VOICE_MEET_GUARDIAN_FROST_RIME_1"],
	"meet_guardian_marsh_glow": ["VOICE_MEET_GUARDIAN_MARSH_GLOW_1"],
	"meet_guardian_ruins_halo": ["VOICE_MEET_GUARDIAN_RUINS_HALO_1"],
	"call_dark": ["VOICE_CALL_DARK_1", "VOICE_CALL_DARK_2"],
	# The first fork of a run, and the first night that keeps a rule of its own (an omen).
	"fork": ["VOICE_FORK_1", "VOICE_FORK_2"],
	"omen": ["VOICE_OMEN_1", "VOICE_OMEN_2"],
}

## Per-hero lines. A hero's own line for a moment is offered **first**; once it
## is spent the generic pool above takes over, so a long run never goes quiet
## and a first run always sounds like the hero you picked.
##
## Only the moments where character shows most are voiced. The Moonlit Warden
## has no entry: the generic lines above *are* the Warden.
const HERO_LINES: Dictionary = {
	"dancer": {
		"beacon_first": ["HVOICE_DANCER_BEACON_FIRST"],
		"guardian_down": ["HVOICE_DANCER_GUARDIAN_DOWN"],
		"low_health": ["HVOICE_DANCER_LOW"],
	},
	"keeper": {
		"beacon_first": ["HVOICE_KEEPER_BEACON_FIRST"],
		"guardian_down": ["HVOICE_KEEPER_GUARDIAN_DOWN"],
		"low_health": ["HVOICE_KEEPER_LOW"],
	},
	"knight": {
		"beacon_first": ["HVOICE_KNIGHT_BEACON_FIRST"],
		"guardian_down": ["HVOICE_KNIGHT_GUARDIAN_DOWN"],
		"low_health": ["HVOICE_KNIGHT_LOW"],
	},
	"eclipse": {
		"beacon_first": ["HVOICE_ECLIPSE_BEACON_FIRST"],
		"guardian_down": ["HVOICE_ECLIPSE_GUARDIAN_DOWN"],
		"low_health": ["HVOICE_ECLIPSE_LOW"],
	},
	"sage": {
		"beacon_first": ["HVOICE_SAGE_BEACON_FIRST"],
		"guardian_down": ["HVOICE_SAGE_GUARDIAN_DOWN"],
		"low_health": ["HVOICE_SAGE_LOW"],
	},
}

## The two lines that open a run, per hero. The Warden opens with the shared
## `STORY_OPEN_A / B`, which stay the canonical text in the chronicle.
const HERO_OPEN: Dictionary = {
	"dancer": ["HVOICE_DANCER_OPEN_A", "HVOICE_DANCER_OPEN_B"],
	"keeper": ["HVOICE_KEEPER_OPEN_A", "HVOICE_KEEPER_OPEN_B"],
	"knight": ["HVOICE_KNIGHT_OPEN_A", "HVOICE_KNIGHT_OPEN_B"],
	"eclipse": ["HVOICE_ECLIPSE_OPEN_A", "HVOICE_ECLIPSE_OPEN_B"],
	"sage": ["HVOICE_SAGE_OPEN_A", "HVOICE_SAGE_OPEN_B"],
}

## Translation keys already used this run.
var _spent: Dictionary = {}


## Clear at the start of a new run. The next run should hear the lines from scratch.
func reset() -> void:
	_spent.clear()


## The keys that open a run for this hero. Empty means "use `STORY_OPEN_A / B`".
static func open_keys(hero_id: String) -> Array[String]:
	var keys: Array[String] = []
	for key in HERO_OPEN.get(hero_id, []):
		keys.append(str(key))
	return keys


## Line for this situation. Empty string if none remain.
##
## `hero_id` is the hero resource's file name (`dancer`, `keeper`, ...). An empty
## or unknown id, or the Warden, gets the generic lines only.
func take(moment: String, hero_id: String = "") -> String:
	var fresh: Array[String] = []
	# The hero's own line goes first and is never mixed into the random draw, so
	# it is what you hear the first time and the generic pool fills in after.
	for key in (HERO_LINES.get(hero_id, {}) as Dictionary).get(moment, []):
		if not _spent.has(key):
			fresh.append(str(key))
	if fresh.is_empty():
		for key in LINES.get(moment, []):
			if not _spent.has(key):
				fresh.append(str(key))
	if fresh.is_empty():
		return ""
	var picked: String = fresh[randi() % fresh.size()]
	_spent[picked] = true
	return tr(picked)
