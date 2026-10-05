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
	SQUALL,    ## Frost Pass — a wall of spirits with a gap in it
	TIDE,      ## Mirewood Marsh — three pods rise round you with wide gaps between
	VIGIL,     ## Moonlit Ruins — a group ahead, then a second one from behind
}

@export var display_name: String = "Forest"

@export var encounter: Encounter = Encounter.ENCIRCLE

## Sheet to crop trees and grass from.
@export var tileset: Texture2D = null
## Sheet pixels per world pixel. Painted terrain is 3× the legacy pixels, so
## Room scales KIND/PROP_KIND/OBSTACLE regions by this and draws sprites at
## 1/art_zoom for the same world footprint. Default 1.0 keeps legacy sheets.
@export var art_zoom: float = 1.0

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
## the four obstacle cells on the first row (64×64 world, times art_zoom).
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

## Which art on this terrain is actually on fire, and what its light looks like.
##
## The camp lantern and the lit barrel were drawn with a flame inside and then
## lit nothing — the ground under them stayed as dark as the ground ten tiles
## away. In a game named after a beacon that is the wrong default, so each
## terrain declares its own light sources here instead of `Room` hardcoding a
## name.
##
## Indexes into the four 64×64 obstacle cells. Empty means this terrain's
## structures are all unlit.
@export var light_obstacle_variants: PackedInt32Array = PackedInt32Array()

## Names from `Room.PROP_KIND` that carry a flame.
@export var light_prop_kinds: PackedStringArray = PackedStringArray()

## Ground pool radius and colour for one of those lights.
##
## Additive, so the colour is light added to the floor and not a tint over it.
## Keep it dim: a pool bright enough to wash out a spirit standing in it trades
## atmosphere for a dodge the player cannot read.
@export_range(16.0, 220.0, 1.0) var light_radius: float = 96.0
@export var light_color: Color = Color(0.5, 0.3, 0.12, 1)

## Life on the floor: colour patches, dappled moonlight and tiny plants.
##
## A floor that is only a repeated tile and a few rocks reads as empty however
## well it is lit. These three break it up. All of it is drawn by code from these
## numbers (`RoomTone`, `RoomLights`, `RoomFlora`), so a new terrain is described
## here and needs no new art.

## Soft colour patches over the floor tile, and the colours they are picked from.
## Alpha is the strength: keep it faint, they should tint the ground and not paint it.
@export_range(0, 120, 1) var tone_count: int = 0
@export var tone_colors: PackedColorArray = PackedColorArray()

## Patches of moonlight that filter through the canopy. Additive, and they breathe.
@export_range(0, 60, 1) var dapple_count: int = 0
@export var dapple_color: Color = Color(0.16, 0.3, 0.52, 0.22)

## Clusters of tiny plants. `flora_plants` are `RoomFlora.Plant` values and
## `flora_colors` the colours they are picked from; mushrooms glow with
## `flora_glow` strength (0 turns every glow off).
@export_range(0, 240, 1) var flora_count: int = 0
@export var flora_plants: PackedInt32Array = PackedInt32Array()
@export var flora_colors: PackedColorArray = PackedColorArray()
@export_range(0.0, 1.0, 0.01) var flora_glow: float = 0.8

## The air: mist, shafts of light and floating motes. See `RoomAtmosphere`.
##
## Colours carry their own opacity. Keep them faint: a dodge game has to keep
## reading its enemies through all of this.
@export var mist_color: Color = Color(0.62, 0.74, 1.0, 0.2)
@export_range(0, 16, 1) var beam_count: int = 0
@export var beam_color: Color = Color(0.72, 0.83, 1.0, 0.09)
## Motes alive around the camera at once. The system follows the view, so this is the
## number a player sees, not the number on the map.
@export_range(0, 200, 1) var mote_count: int = 0
@export var mote_color: Color = Color(0.62, 0.9, 1.0, 1.0)
