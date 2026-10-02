class_name Acts
extends RefCounted

## The story's spine: three acts and an epilogue laid over the cycles.
##
## Until 3.0.0 the story was a run of good lines with no shape — every cycle
## said two things and nothing said where in the story you were. Acts give it
## boundaries a player can feel: a card the moment a new act begins, and a name
## for the stretch you are in.
##
## The canon lives in `notes/plans/world-story-pass.md`: Nari's promise, a hunger
## that is lost rather than hateful, and beacons that must remember one another
## to make a road home. Acts only say *when* each part of that is learned.
##
## | Act | Cycles | What is learned |
## | --- | --- | --- |
## | I · The Promise | 1–2 | Nari is gone; keep the road home lit |
## | II · The Lost | 3–5 | What pursues you is lost, not hateful |
## | III · The Road | 6–8 | Beacons must remember one another |
## | Epilogue · The Road Home | 9+ | The road burns; other lights wait past the map |
##
## Text lives in the translation table as `ACT_<n>_LABEL / _TITLE / _EPIGRAPH`.

const LIST: Array[Dictionary] = [
	{"id": "debt", "from": 1, "number": 1},
	{"id": "hunger", "from": 3, "number": 2},
	{"id": "line", "from": 6, "number": 3},
	{"id": "moonless", "from": 9, "number": 4},
]


## The act that **begins** on this cycle, or an empty dictionary.
##
## This is what decides when the title card plays: only on the cycle an act
## starts, never on the ones after it.
static func starting_at(cycle: int) -> Dictionary:
	for act in LIST:
		if int(act["from"]) == cycle:
			return _with_keys(act)
	return {}


## The act a cycle belongs to. Cycle 0 and below read as Act I.
static func of_cycle(cycle: int) -> Dictionary:
	var current: Dictionary = LIST[0]
	for act in LIST:
		if cycle >= int(act["from"]):
			current = act
	return _with_keys(current)


static func _with_keys(act: Dictionary) -> Dictionary:
	var number: int = int(act["number"])
	var result: Dictionary = act.duplicate()
	result["label"] = "ACT_%d_LABEL" % number
	result["title"] = "ACT_%d_TITLE" % number
	result["epigraph"] = "ACT_%d_EPIGRAPH" % number
	return result
