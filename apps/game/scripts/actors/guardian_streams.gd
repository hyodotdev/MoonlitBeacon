class_name GuardianStreams
extends RefCounted

## What a guardian shoots between its big volleys, so a fight is never a wait for the next telegraph.
##
## Each guardian has two layers. The **aura** never stops (a slow, thin thing it sheds all the time: thorns turning,
## feathers falling, runes) and the player is always weaving through something. The **stream** is heavier and comes
## only while the guardian is chasing, gliding, strafing or resting, never while it winds up a volley or a charge, so
## the coral wedge and the coral lane are still read on their own. Both go into the `BulletField`, are slower than
## the player and leave wide gaps: see `tests/test_barrages.gd` for the numbers that keep them so.
##
## The first meeting is gentle and the night thickens: `intensity()` is 0.6 at cycle 1, 1.0 by cycle 4, and reaches
## 2.0 by cycle 17 and stays there.

const MAX_INTENSITY: float = 2.0


static func intensity(cycle: int) -> float:
	var safe_cycle: int = maxi(cycle, 1)
	if safe_cycle <= 4:
		return 0.6 + 0.4 * float(safe_cycle - 1) / 3.0
	return minf(1.0 + 0.075 * float(safe_cycle - 4), MAX_INTENSITY)


## A little faster each cycle, up to a third faster: still slower than a player at every cycle.
static func speed_scale(cycle: int) -> float:
	return 1.0 + 0.03 * float(mini(maxi(cycle, 1) - 1, 11))


static func tint_for(style: int) -> int:
	match style:
		SpiritKind.GuardianStyle.FOREST:
			return BulletField.Tint.MINT
		SpiritKind.GuardianStyle.FIELD:
			return BulletField.Tint.SKY
		SpiritKind.GuardianStyle.CAMP:
			return BulletField.Tint.GOLD
		SpiritKind.GuardianStyle.GALE:
			return BulletField.Tint.SKY
		SpiritKind.GuardianStyle.LEAP:
			return BulletField.Tint.MINT
		_:
			return BulletField.Tint.LILAC


## The thin layer that never stops.
static func aura(style: int, cycle: int) -> Array[BulletEmitter]:
	var fast: float = speed_scale(cycle)
	var tint: int = tint_for(style)
	var made: Array[BulletEmitter] = []
	match style:
		SpiritKind.GuardianStyle.FOREST:
			# Thorns turning: two arms, three from cycle 6, each a slow line of bullets.
			made.append(_shaped(BulletEmitter.spiral(2 + (1 if cycle >= 6 else 0), 0.34, 58.0 * fast, 0.7, tint), 250.0))
		SpiritKind.GuardianStyle.FIELD:
			# Petals: a ring of eight that turns a little each time, so its gaps are never where they were.
			made.append(_shaped(BulletEmitter.ring(8 + (2 if cycle >= 6 else 0), 2.0, 50.0 * fast, 0.41, tint), 250.0))
		SpiritKind.GuardianStyle.CAMP:
			# A lantern's smoke: one stream that sways across the aim.
			made.append(_shaped(BulletEmitter.wave(0.55, 1.3, 0.36, 66.0 * fast, tint), 260.0))
		SpiritKind.GuardianStyle.GALE:
			# Feathers falling behind it, turning the other way from the thorns.
			made.append(_shaped(BulletEmitter.spiral(2 + (1 if cycle >= 6 else 0), 0.36, 56.0 * fast, -0.85, tint), 250.0))
		SpiritKind.GuardianStyle.LEAP:
			# Bubbles rising: a ring of six, slow, that also turns.
			made.append(_shaped(BulletEmitter.ring(6 + (2 if cycle >= 6 else 0), 2.2, 44.0 * fast, 0.52, tint), 240.0))
		_:
			# Runes: three arms turning slowly, the slowest thing on the field.
			made.append(_shaped(BulletEmitter.spiral(3, 0.4, 52.0 * fast, 0.55, tint), 250.0))
	return made


## The heavier layer, for while the guardian is not winding anything up.
static func stream(style: int, cycle: int) -> Array[BulletEmitter]:
	var fast: float = speed_scale(cycle)
	var made: Array[BulletEmitter] = []
	match style:
		SpiritKind.GuardianStyle.FOREST:
			made.append(_shaped(BulletEmitter.aimed(3, 0.5, 1.15, 92.0 * fast, BulletField.Tint.LILAC), 300.0))
		SpiritKind.GuardianStyle.FIELD:
			made.append(_shaped(BulletEmitter.aimed(3, 0.44, 1.5, 98.0 * fast, BulletField.Tint.PINK), 300.0))
		SpiritKind.GuardianStyle.CAMP:
			made.append(_shaped(BulletEmitter.aimed(5, 0.95, 1.7, 84.0 * fast, BulletField.Tint.GOLD), 300.0))
		SpiritKind.GuardianStyle.GALE:
			made.append(_shaped(BulletEmitter.ring(6, 1.7, 46.0 * fast, 0.52, BulletField.Tint.SKY), 260.0))
		SpiritKind.GuardianStyle.LEAP:
			made.append(_shaped(BulletEmitter.aimed(3, 0.5, 1.4, 88.0 * fast, BulletField.Tint.MINT), 300.0))
		_:
			made.append(_shaped(BulletEmitter.aimed(2, 0.3, 1.25, 94.0 * fast, BulletField.Tint.GOLD), 300.0))
	return made


static func _shaped(emitter: BulletEmitter, range_px: float) -> BulletEmitter:
	emitter.range_px = range_px
	return emitter
