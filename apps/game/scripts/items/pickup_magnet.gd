class_name PickupMagnet
extends RefCounted

## How far pickups reach for the player, as a multiple of their own reach.
##
## Embers, dew and cores each pull toward the player from a short range. The Star Magnet skill
## widens all of them at once, so the number lives in one place they all read. The arena sets it when
## a run starts and whenever the skill changes, and puts it back to 1 when it leaves.

static var scale: float = 1.0
