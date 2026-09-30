class_name Acts
extends RefCounted

## The story's spine: three acts and an epilogue laid over the cycles.
##
## Until 3.0.0 the story was a run of good lines with no shape — every cycle
## said two things and nothing said where in the story you were. Acts give it
## boundaries a player can feel: a card the moment a new act begins, and a name
## for the stretch you are in.
##
## The canon does not change (`notes/plans/world-story-pass.md`): the dark is a
## hunger, spirits follow light like moths, guardians are swallowed light, and
## the Wardens kept beacon lines that failed. Acts only say *when* each part of
## that is learned.
##
## | Act | Cycles | What is learned |
## | --- | --- | --- |
## | I · The Debt | 1–2 | The Wardens fell, one remains, and the dark eats light |
## | II · The Hunger | 3–5 | The spirits are not hunting you. They are lost |
## | III · The Line | 6–8 | A beacon is not a fire. It is a line the dark cannot cross |
## | Epilogue · The Moonless | 9+ | Past the map. The dark gets a name |
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
