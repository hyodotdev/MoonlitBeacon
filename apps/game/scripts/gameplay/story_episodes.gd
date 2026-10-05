class_name StoryEpisodes
extends RefCounted

## The story as data: episodes, their cycle ranges, and their dialogue beats.
##
## Until 3.0.0 the story's shape lived in three places at once: `Acts` knew
## which cycle opens which act, `Chronicle` listed the same beats again for
## rereading, and the arena derived translation keys from cycle numbers by
## string formatting. Adding one more chapter meant editing all three and
## hoping they agreed.
##
## This catalog is the one place instead. Each episode has a stable id, the
## act it belongs to, the cycles it spans, and the cycles that carry dialogue.
## Acts, the chronicle and the arena all read from here:
##
## - `Acts.starting_at()` / `Acts.of_cycle()` resolve act boundaries here.
## - `Chronicle.sections()` builds its story entries from `story_beats()`.
## - The arena's `_story_lines()` asks `story_keys()` for a cycle's keys.
##
## Cycles past the last authored beat fall into the endless episode, which
## carries no dialogue: the run continues with short voice-strip asides while
## combat never pauses for story it does not have. That fallback is the
## default for future content, not a missing chapter.
##
## To add a future episode, append one entry to `EPISODES` with a new stable
## id, its `from` cycle, a finite `to`, and its beat cycles, add the
## `STORY_CYCLE_<n>_A/B` rows to `localization/moonlit.csv` in all five
## languages, and extend the catalog test below. The new row overlaps the
## endless fallback's open range on purpose: a finite range always wins over
## it (see `episode_for_cycle()`), so the fallback row is never moved or
## edited. No arena progression edit is needed. See `test_journey.gd`'s
## extension example, which appends a hypothetical episode through these same
## functions without shipping it.
##
## | Episode | Act | Cycles | Beats |
## | --- | --- | --- | --- |
## | promise | I · The Promise | 1–2 | 1, 2 |
## | lost | II · The Lost | 3–5 | 3, 4, 5 |
## | road | III · The Road | 6–8 | 6, 7, 8 |
## | home | Epilogue · The Road Home | 9–12 | 9, 10, 12 |
## | endless | Epilogue · The Road Home | 13+ | none |
##
## Cycle 11 has no authored lines: the Moonless is named in 10 and answered
## in 12, and the gap between them is deliberate silence on a long run.

## One episode per row. `to` is inclusive; `0` means the run never outgrows
## it. `beats` lists the cycles with authored `STORY_CYCLE_<n>_A/B` lines, in
## reading order. Append, never reorder: chronicle entry ids derive from beat
## cycles and old saves outlive this file.
const EPISODES: Array[Dictionary] = [
	{
		"id": "promise", "act_id": "debt", "act_number": 1,
		"from": 1, "to": 2, "beats": [1, 2],
	},
	{
		"id": "lost", "act_id": "hunger", "act_number": 2,
		"from": 3, "to": 5, "beats": [3, 4, 5],
	},
	{
		"id": "road", "act_id": "line", "act_number": 3,
		"from": 6, "to": 8, "beats": [6, 7, 8],
	},
	{
		"id": "home", "act_id": "moonless", "act_number": 4,
		"from": 9, "to": 12, "beats": [9, 10, 12],
	},
	{
		"id": "endless", "act_id": "moonless", "act_number": 4,
		"from": 13, "to": 0, "beats": [],
	},
]


## Every episode, oldest first. A fresh array each call.
static func episodes(catalog: Array = EPISODES) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in catalog:
		out.append((entry as Dictionary).duplicate())
	return out


## Act boundaries in `Acts.LIST` shape: `{id, from, number}`.
##
## Episodes that share an act (the epilogue and the endless stretch) report
## only the act's first cycle, so the title card plays once.
static func act_boundaries(catalog: Array = EPISODES) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for entry: Dictionary in catalog:
		var act_id: String = str(entry.get("act_id", ""))
		if act_id.is_empty() or seen.has(act_id):
			continue
		seen[act_id] = true
		out.append({
			"id": act_id,
			"from": int(entry.get("from", 1)),
			"number": int(entry.get("act_number", 1)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["from"]) < int(b["from"]))
	return out


## The act that **begins** on this cycle, with its translation keys, or `{}`.
static func act_starting_at(
	cycle: int, catalog: Array = EPISODES
) -> Dictionary:
	for act: Dictionary in act_boundaries(catalog):
		if int(act["from"]) == cycle:
			return _with_keys(act)
	return {}


## The act a cycle belongs to. Cycle 0 and below read as the first act.
static func act_of_cycle(cycle: int, catalog: Array = EPISODES) -> Dictionary:
	var bounds: Array[Dictionary] = act_boundaries(catalog)
	if bounds.is_empty():
		return {}
	var current: Dictionary = bounds[0]
	for act: Dictionary in bounds:
		if cycle >= int(act["from"]):
			current = act
	return _with_keys(current)


## The episode a cycle belongs to. Never empty: past the last authored row
## the endless episode answers, so future cycles always resolve.
##
## Precedence is by range kind, then catalog order. A finite range (`to` > 0)
## containing the cycle wins over the open-ended fallback, so a future
## episode appended after `endless` still owns its cycles even though the
## fallback's open range covers them too. Within one kind the first row in
## catalog order wins; an open-ended row answers only cycles at or past its
## `from`, and below every `from` the last open-ended row answers.
static func episode_for_cycle(
	cycle: int, catalog: Array = EPISODES
) -> Dictionary:
	for entry: Dictionary in catalog:
		var from: int = int(entry.get("from", 1))
		var to: int = int(entry.get("to", 0))
		if to > 0 and cycle >= from and cycle <= to:
			return (entry as Dictionary).duplicate()
	var fallback: Dictionary = {}
	for entry: Dictionary in catalog:
		if int(entry.get("to", 0)) > 0:
			continue
		fallback = (entry as Dictionary).duplicate()
		if cycle >= int(entry.get("from", 1)):
			return (entry as Dictionary).duplicate()
	if not fallback.is_empty():
		return fallback
	var rows: Array[Dictionary] = episodes(catalog)
	return rows[rows.size() - 1] if not rows.is_empty() else {}


## Every cycle with authored dialogue, in reading order.
static func story_beats(catalog: Array = EPISODES) -> Array[int]:
	var beats: Array[int] = []
	for entry: Dictionary in catalog:
		for beat: Variant in entry.get("beats", []):
			beats.append(int(beat))
	beats.sort()
	return beats


## The translation keys of one cycle's dialogue, or empty past authored beats.
##
## The opening voice (cycle 1's hero lines) stays with the arena: it depends
## on the picked hero, not on the catalog.
static func story_keys(cycle: int, catalog: Array = EPISODES) -> Array[String]:
	for entry: Dictionary in catalog:
		var beats: Array = entry.get("beats", [])
		if beats.has(cycle):
			return [
				"STORY_CYCLE_%d_A" % cycle,
				"STORY_CYCLE_%d_B" % cycle,
			]
	return []


## True once the run has outgrown every authored beat.
static func is_endless(cycle: int, catalog: Array = EPISODES) -> bool:
	return str(episode_for_cycle(cycle, catalog).get("id", "")) == "endless"


static func _with_keys(act: Dictionary) -> Dictionary:
	var number: int = int(act["number"])
	var result: Dictionary = act.duplicate()
	result["label"] = "ACT_%d_LABEL" % number
	result["title"] = "ACT_%d_TITLE" % number
	result["epigraph"] = "ACT_%d_EPIGRAPH" % number
	return result
