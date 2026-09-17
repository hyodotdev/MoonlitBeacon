# Moonlit Beacon art bible

First baseline: 2026-07-29 · Last update: 2026-07-30

## One sentence

**A cute top-down chibi fantasy where only blue-white moonlight and vermilion
beacon fire stay alive inside deep night ink lines.**

This document is the visual standard for new Moonlit Beacon assets. Do not
copy the look of a specific game or artist. The goal is modern commercial
indie pixel art whose roles read first even on a small screen, and whose
whole frame looks like one art team made it.

## World and mood

Moonlight is the order of the night and the player's power. The beacon is
warm life that means safety, progress, and return. Forest and spirits are not
purely evil so much as shapes of nature unsettled by moonlight, and the
player reconnects beacons inside that to find the path again.

Core keywords:

- moonlit, beacon fire, mystical night forest
- cool blue moonlight, warm vermilion fire
- Korean woodblock sensibility, restrained fantasy
- elegant pixel art, modern indie polish
- readable silhouettes, layered depth, subtle VFX

Korean sensibility comes quietly from layered garments, knots, eaves, and
woodblock plane splits. Do not glue a specific era's costume or traditional
motifs on as decoration.

## Meaning palette

| Role | Base color | Use rule |
| --- | --- | --- |
| Deep night | `#0B0E1C` | Off-screen and the deepest shadows |
| Shared ink line | `#141B1B` | 1px outline of characters and props |
| Mid night values | `#3B3643`, `#4A5270` | Cloth, stone, tree shadows |
| Mid moonlight | `#79B8CE` | Player skills and moonlit faces |
| Moonlight core | `#CDE1FF`, `#DEF0FF`, `#F2EAF1` | Attack cores and speculars |
| Danger | `#E0394C`, `#9B3F76` | Enemy attacks and charge/barrage tells |
| Beacon | `#EF914F`, `#F1C471`, `#FFE18D` | Objectives, flame, confirm actions |
| Awakening | `#F5C84B`, `#FFF0A6` | Large rewards and weapon awakening |
| Heal | low-chroma teal/green | Restricted to heal and safe states |

Color is combat grammar, not decoration.

- Blue-white is a safe attack the player made.
- Gold is awakening or a large reward.
- Red/magenta is danger that is about to deal damage.
- Vermilion is the beacon and a confirm action.
- Heal color must also differ in silhouette from other drops.

Do not rely on color vision. Even in grayscale, player, enemy, boss, beacon,
exit, heal, and currency must separate by outline alone.

## Character design

### Shared

- Heroes read as a soft chibi illustration, not counted pixel grains.
- Prioritize cute with a large head, clear eyes, and a short body, but give
  each hero a different hood/prop silhouette.
- Leave at least 1px of transparent padding at the cell edge.
- The bottom-center of the feet is the world origin. Foot-position error
  between frames is 0px.
- Inside a 48×64 hero cell, the actual silhouette uses only 50–60px
  bottom-aligned.
- Keep the head as large as or larger than the body, and do not let the torso
  become a wide, long egg larger than the head.
- Separate gear from the body by at least one value step.
- Allow only 1–2 small ornaments per character.

### Hero silhouettes

| Hero | Form | Gear | Motion |
| --- | --- | --- | --- |
| Warden | 2-head-tall round hood and large face | Empty hands cupping a moonlight seed | Four-beat seed glow that breathes |
| Dancer | 2-head-tall petal hood and short teal ribbon | Open crescents in both hands | Light, small left-right rhythm |
| Keeper | 2-head-tall charcoal hood and short quilted coat | Lantern-heart in both hands | Slow, small up-down rhythm |

Warden's current locked design is a round blue-white hood cape wrapping the
face, a wide friendly face and short purple bob, closed boots, a tiny crescent
pin, and a moonlight seed at chest center. Both hands are empty palms holding
the seed. The short moon blade, ember bracer, and face that shows only glowing
eyes were removed after user feedback. Do not use a mask, headband, topknot,
or bare feet, nor a horizontal protrusion that reads as a muzzle, grip, or
aiming arm.

Ranged attacks start from the moonlight seed between the hands at Player-local
`(0, -10)`. Right after firing, a small blue-white ring and both-hand embers
must appear for `0.16s`, and arrows and missiles share that origin. A homing
missile head should read as a moonlight seed, diamond star-core, and short
halo, not a long warhead and fighter wings.

### Enemy factions

- Regular enemies are floating circle/diamond families, but change protrusion
  count and center of mass per kind.
- Pursuers are pointed in front, projectile enemies open left-right, swarm
  enemies read as several cores.
- A same sheet with only a recolor is not a separate enemy.
- A danger-tell pose must change silhouette before the attack frames.

### Bosses

| Region | Silhouette | State expression |
| --- | --- | --- |
| Night forest | Low four-legged body and forward thorn antlers | Antlers gather and the body drops before a charge |
| Moonlit field | Wide left-right crescent wings | Wing angle changes before cross/radial barrages |
| Abandoned camp | Square plate and a heavy shield | Closes on defense; ember core shows in recover |

Do not distinguish the three bosses by putting a crown or a recolor on the
same body. They must be different masses from the idle sheet onward.

## Outline, value, pixel density

- Opaque sprites use alpha `0` or `255` in principle.
- Outer outlines of characters and key props are `#141B1B` 1px.
- Inner lines are one step brighter than the outer line so they do not clump
  on a small screen.
- Base value is four steps: outline, shadow, body, highlight.
- Only moonlight/beacon cores may have a fifth point-light.
- Draw at native 1x. Remove translucent pixels created by rotate/scale.
- One combat sprite is usually 16–36 colors excluding transparency; heroes
  max out at 48.
- Do not use soft vector gradients, blurry outlines, or high-res brush marks.
- Only glow FX may use about four alpha steps or ordered dither.

## Runtime baseline

| Item | Value |
| --- | --- |
| Internal resolution | `808×360` |
| Reference Android screen | `2424×1080`, exact 3x |
| Filter | Nearest, no mipmaps |
| Base tile | `16×16` |
| Character origin | Feet at bottom-center of the cell |
| Hero cell | `48×64` |
| Hero sheet | `192×256`, columns=down·up·left·right, rows=4 frames |
| Hero portrait | `96×96` |

Exact per-file contracts use
`apps/game/tools/custom_asset_contracts.json` as the single source.

## Backgrounds and tilesets

Split backgrounds into three depths.

1. Floor: low-contrast planes and small variation that do not interfere with play
2. Combat props: mid-contrast trees, rocks, grass that do not affect pathfinding
3. Far/atmosphere: lowest contrast and slow motion — canopy, mist, moon shafts

Rules:

- Floor repeats should not read immediately as 16px; combine large stains and
  fine variation.
- Forest, field, and camp do not only change hue; they also change the shape
  language of trees, rocks, and grass.
- Moonlight highlights sit on some top faces, not the whole screen.
- Around the beacon, keep vermilion value contrast but separate it from
  danger red.
- Mist and dust must have lower value contrast than actors and projectiles.
- Inspect tile borders, all four corners, and the repeat canvas together.

This project is not a `TileMap`; atlas coordinates are fixed in code and
scenes. Strict no-code replacement only connects a compatible atlas that
preserves the existing `tileset_nature.png` `384×336` canvas and used
coordinates. A new `256×256` atlas design does not enter runtime until a
separate visual-wiring exception is approved.

## UI

- Reduce bright orange wood area and default to navy/ink panels.
- Use beacon vermilion only at meaningful points: select, confirm, progress.
- Borders are 1px ink; the inner line is one step brighter.
- Button states differ not only by color but by 1px press, corner marks, and
  value.
- Icons must read their role at `16×16` and must not rely on text abbreviations.
- Use panel ornaments in only one place: four corners or top center.
- Keep Galmuri11 and prefer integer multiples of 11px.
- UI may share the character palette, but must not spend combat danger colors
  as decoration.

## VFX

- Moonlight attacks read as a thin blue-white outline, a bright core, then a
  short afterglow.
- Beacons are a vermilion outline, gold center, and sparks narrowing upward.
- Enemy attacks show a magenta/red tell first and make the actual shot
  brighter.
- Hits expand then vanish quickly inside 4–6 frames.
- Effects do not exaggerate the real hit volume.
- Do not reuse the same drawing for slash, arrow, UI ring, and enemy shot.
- Prefer a clear first-frame shape over particle count and screen occupancy.

Some weapons, drops, and HUD are currently drawn with GDScript `_draw()` and
have no texture hook. The Warden redesign also changed the runtime look of
ranged casting and homing-missile heads so character and attack share a shape
language. Casting is a dedicated Node2D in front of the Sprite so the chest
core, ring, and both-hand embers are not hidden behind the body.

## Forbidden

- Copying existing game characters, logos, or an artist's look
- Player elements that recall the current free assets, such as a ninja mask
  or headband
- Distinguishing heroes, enemies, or bosses by recoloring the same body
- Reusing sprites between attacks, drops, and UI that have different roles
- Downscaling a high-res generated image and using it as the final pixel sheet
- Generated sheets whose foot position, body proportion, or pixel size change
  per frame
- Heavy bloom, blurry gradients, thin translucent lines
- Player and danger tells with lower contrast than the floor
- Unreadable ornamental letters, watermarks, debug marks
- Runtime assets with no record of spec, source, or generation process
