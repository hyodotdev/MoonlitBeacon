class_name PlaceMemory
extends RefCounted

## What each place remembers when its beacon burns again.
##
## Six terrains, six small concrete memories: the ribbons Nari tied, the chimes
## in the grass, her kettle, a bell under the snow, a paper boat, a lens in the
## stones. Each one is a crafted motif in the world (dim until its beacon is
## lit), one nonblocking discovery line, and one chronicle entry the player can
## reopen. The motif frames live in `PlaceMotif`; this file only names the
## terrains, their translation keys and their chronicle ids, in
## `Expedition.TERRAINS` order.
##
## A memory is discovered once per run per terrain (the arena keeps that set),
## but restoring is visible every run: the motif still dims and lights whether
## the chronicle already holds the entry or not. The main story never depends
## on these — an official win needs no particular terrain.

## Terrain ids in `Expedition.TERRAINS` order. Append, never reorder.
const TERRAIN_IDS: Array[String] = [
	"forest", "field", "camp", "frost", "marsh", "ruins",
]


## Terrain id for a terrain index, or "" when out of range.
static func terrain_id(terrain: int) -> String:
	if terrain < 0 or terrain >= TERRAIN_IDS.size():
		return ""
	return TERRAIN_IDS[terrain]


## Chronicle entry id for a terrain, e.g. `place_forest`.
static func chronicle_id(terrain: int) -> String:
	var id: String = terrain_id(terrain)
	return "place_" + id if not id.is_empty() else ""


## Voice moment for a terrain. The same string as the chronicle id, so showing
## the discovery line and recording it are one call through `_say`.
static func moment(terrain: int) -> String:
	return chronicle_id(terrain)


## Short motif name shown in the chronicle, e.g. `PLACE_NAME_FOREST`.
static func name_key(terrain: int) -> String:
	var id: String = terrain_id(terrain)
	return "PLACE_NAME_" + id.to_upper() if not id.is_empty() else ""


## Route hint shown on fork gates, e.g. `PLACE_CLUE_FOREST`.
static func clue_key(terrain: int) -> String:
	var id: String = terrain_id(terrain)
	return "PLACE_CLUE_" + id.to_upper() if not id.is_empty() else ""


## The discovery line, e.g. `PLACE_MEMORY_FOREST`.
static func memory_key(terrain: int) -> String:
	var id: String = terrain_id(terrain)
	return "PLACE_MEMORY_" + id.to_upper() if not id.is_empty() else ""
