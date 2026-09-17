class_name RoomKind
extends Resource

## Settings for one room. One `.tres` file is one map.
##
## Same idea as `SpiritKind` — **one scene, many settings.**
## Growing the map set needs neither code nor scenes.
##
## There is a reason the room background is not a whole scene file. The title
## forest (`night_forest.tscn`) is 1,294 nodes and 295KB. Do a map set that way
## and the repo gains 30,000 lines, and moving one tree means editing those
## lines. **Bake from a seed.** The same seed always yields the same room.

## Raid formation used on this terrain.
##
## Combat reads only this value to pick terrain rules. It never compares room
## resource paths or display names, so renaming cannot quietly swap the fight
## onto a different rule.
enum Encounter {
	ENCIRCLE,  ## Forest — surround, but leave a gap to flee
	CROSSFIRE, ## Field — crossfire from both sides
	CARAVAN,   ## Camp — ember carriers and escorts arrive together
}

@export var display_name: String = "Forest"

@export var encounter: Encounter = Encounter.ENCIRCLE

## Sheet to crop trees and grass from.
@export var tileset: Texture2D = null

## Picture laid on the floor. Repeats like a tile.
@export var floor_texture: Texture2D = null

## If `floor_texture` is an atlas, crop and repeat only this region.
##
## Size 0 uses the whole texture. Repeating the full field/camp sheet would
## tile tents and border tiles onto the floor, so this value picks a clean
## interior tile.
@export var floor_region: Rect2i = Rect2i()

## Tint over the whole room. It must differ per map so "we arrived somewhere else" reads.
@export var tint: Color = Color(0.315, 0.35, 0.57, 1)

## Floor color. Multiplied with the tint.
@export var floor_tint: Color = Color(1, 1, 1, 1)

## Tree count for the edge. Ring the room so it reads as a wall.
@export var border_count: int = 90

## Small decorations scattered inside.
@export var decor_count: int = 26

## Inner tree-clump count. One clump is 2–5 trees.
## Arrived as the map grew — an edge ring alone makes the screen look like prairie.
@export var clump_count: int = 40

## Terrain-only prop sheet and placement count.
##
## `prop_count` is taken out of `decor_count`. Adding props must not grow the
## total node count, or one terrain becomes unusually heavy on mobile.
@export var prop_tileset: Texture2D = null
@export var prop_count: int = 0
@export var prop_kinds: PackedStringArray = PackedStringArray()

## Sheet and count for this project's own structures that actually block the path.
##
## Keep them apart from decor so collision is not glued to every visible tree;
## only large-silhouette structures become clear combat terrain. `Room` picks
## the four 64×64 cells on the first row.
@export var obstacle_tileset: Texture2D = null
@export_range(0, 40, 1) var obstacle_count: int = 0

## Pieces used as large trees. Names come from the KIND table in
## `tools/build_title_forest.py`, each confirmed as "one intact frame" by
## alpha bounding box.
@export var tree_kinds: PackedStringArray = PackedStringArray(
	["bigA", "bigB", "bigC", "bigD", "sm0", "sm1", "sm2", "sm3"])

## Pieces used as inner decoration.
@export var decor_kinds: PackedStringArray = PackedStringArray(
	["bush", "twig", "stump2", "rockS", "rockS2", "branch"])
