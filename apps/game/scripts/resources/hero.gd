class_name Hero
extends Resource

## One character to pick.
##
## **Each run starts differently.** Relics are random, so runs converge; a
## character is different from the first second. Which weapon you hold going
## in sets the run's direction.
##
## Same pattern as `SpiritKind`, `Relic`, and `Boon` — one `.tres` is one
## character, and adding one does not grow the code. This repo uses that shape
## for the fourth time.
##
## Power is **kept close in total.** If one is clearly stronger the rest become
## decoration and picking stops being fun. What differs is not strength, it is
## **texture.**

## Ranged-attack motion and hit VFX. Damage, shot count, and hit radius are
## not changed by this. A paid hero's price gap should be felt only as richer
## shape and afterglow; if a higher price means higher DPS, character pick
## becomes a payment.
enum AttackProfile {
	WARDEN,  ## A blue round moon wheel turns wide and rewinds.
	DANCER,  ## Twin violet arcs coil into each other as they go.
	KEEPER,  ## A green-gold lantern core travels heavy and leaves a hit ripple.
	KNIGHT,  ## Silver-white crescent fans and star shards.
	ECLIPSE, ## Red-black eclipse ring and embers.
	SAGE,    ## Teal-gold constellation chains and a nebula burst.
}

@export var display_name: String = "Name"

## One-line intro. Say what is different **in numbers.**
@export var description: String = ""

## Shard cost to unlock. 0 means available from the start.
##
## Unlocking a character with shards is a different kind of goal from a boon.
## A boon nudges a number; a character **changes the whole run**, which is a
## reason to save for a long time.
@export var unlock_cost: int = 0

## Starting heart cells.
@export var health: int = 5
## Walk-speed multiplier.
@export var speed_scale: float = 1.0
## Starting damage multiplier. Applies to melee and ranged.
@export var damage_scale: float = 1.0
## Dash-cooldown multiplier. Lower means more often.
@export var dash_scale: float = 1.0

## Relics held when the run opens. `.tres` paths.
##
## This is what splits characters the most. Same map, same spirits, but starting
## with orbiting orbs versus a spreading ripple is a different game.
@export var opening: Array[String] = []

@export var accent: Color = Color(0.86, 0.92, 1, 1)

@export_group("Combat Profile")
@export var attack_profile: AttackProfile = AttackProfile.WARDEN
## 0–5 follows price order but only changes decoration density. Projectile
## regression tests lock the contract that combat math never reads this.
@export_range(0, 5, 1) var vfx_tier: int = 0
@export var projectile_primary: Color = Color(0.42, 0.72, 1.0, 1.0)
@export var projectile_secondary: Color = Color(0.88, 0.96, 1.0, 1.0)

## Character art. Facing is four columns `down · up · left · right`, and
## animation frames run top to bottom. The six custom heroes are 48×64, four
## rows each for walk and idle. Default 16×16 is a compatibility value so older
## course resources still load.
##
## Keep the sheet and layout on the character resource so adding custom art
## does not require cloning the Player scene per character. Portrait is one
## card image, separate from combat animation.
@export_group("Visuals")
@export var walk_sheet: Texture2D = null
@export var idle_sheet: Texture2D = null
@export var portrait: Texture2D = null
@export var sprite_cell: Vector2i = Vector2i(16, 16)
## Region that drops transparent padding in the detail view. Size 0 uses the
## whole cell. Combat keeps the original cell; only the detail view scales up
## by an integer.
@export var preview_crop: Rect2i = Rect2i()
@export_range(1, 12, 1) var walk_frames: int = 4
@export_range(1, 12, 1) var idle_frames: int = 1
@export_range(1.0, 24.0, 0.5) var walk_fps: float = 9.0
@export_range(1.0, 24.0, 0.5) var idle_fps: float = 1.0


## First idle frame for a 48×48 icon cell. A 24×24 crop, so it scales exactly 2×.
##
## The shrine card and the detail header must share the same picture or "tap
## the small one to see the large one" fails. Drop a 96×96 portrait in that
## cell and it shrinks to 0.5×, throwing away three of every four pixels —
## so portraits hang only in the 96×96 cell.
func idle_icon_texture() -> Texture2D:
	if idle_sheet == null or sprite_cell.x <= 0 or sprite_cell.y <= 0:
		return portrait
	var crop: Rect2i = preview_crop
	if crop.size.x <= 0 or crop.size.y <= 0:
		crop = Rect2i(Vector2i.ZERO, sprite_cell)
	var atlas := AtlasTexture.new()
	atlas.atlas = idle_sheet
	atlas.region = Rect2(crop.position, crop.size)
	return atlas
