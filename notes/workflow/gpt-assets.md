# ChatGPT asset intake

Source art comes from the user's ChatGPT project. This repo never
generates art itself; it reviews, converts, and wires drops in.

## Drop point

`_asset_sources/gpt/<batch>/` (gitignored, matches the unpacked-sources
convention). One folder per batch, original filenames kept. Never edit
drops in place — converted files go to their project path, and the drop
stays as provenance.

## Intake checklist (every batch)

1. View every file. Reject off-palette, off-style, or wrong-size pieces
   before touching the project.
2. Convert: trim/endoce to the spec below, PNG-8 or PNG-24, no JPG in
   `res://` (import bloat + artifacts on pixel edges).
3. Wire only used files into `apps/game/assets/`, record each in
   `apps/docs/docs/assets/manifest.md` (third-party section stays for
   packs; GPT art gets its own rows with batch + license note).
4. Run `pnpm verify` + `pnpm check:assets`. Game-visual changes also need
   `pnpm check:store-screenshots` reported (never auto-recapture) and a
   device/emulator look.
5. License: user-generated via their ChatGPT project. Keep the batch
   folder out of git; record "custom, generated 2026-09" per file.

## House specs for prompts

- Camera: top-down, straight-on, no perspective tilt, no shadow blobs.
- Style: chunky pixel art, visible pixels, 16-color-ish night palette.
  Deep navy ground (`#141b2e`-ish), amber light (`#ffb347`-ish),
  bone-white UI text. No gradients, no glow, no anti-aliased edges.
- Format: single object per file, transparent background, power-of-two
  canvas (64×64 for props, 32×32 for small decor), object fills 70-90%.
- Obstacles are decor-only today: forest has no collision. Blocking
  needs a gameplay decision first — art first, collision later.

## Batch 1 — map obstacles and decor (prompt pack)

Paste one block per object into the ChatGPT project. Ask for PNG with
transparency, then drop everything into `_asset_sources/gpt/batch-1/`.

Common suffix for every prompt: "top-down pixel art game sprite, single
object centered on transparent background, chunky visible pixels, dark
night palette with deep navy and amber accents, no shadow, no gradient,
no background, no text".

1. `rock-moss`: a mossy round boulder with a few pale moonflowers.
2. `rock-jagged`: a jagged dark standing stone with faint carved rings.
3. `tree-dead`: a leafless dead tree, twisted branches, crow perched.
4. `tree-lantern`: a pine with a small hanging beacon lantern, lit amber.
5. `shrine-stone`: a small stacked-stone altar with an unlit candle.
6. `bones`: a small pile of old bones half-buried in dark grass.
7. `fence-broken`: two posts and one sagging rail of a broken wooden fence.
8. `well`: a small stone well with a wooden roof, top-down readable.
9. `flowers-moon`: a tuft of night grass with glowing white moonflowers.
10. `stump`: a cut tree stump with a tiny mushroom ring.

After the drop lands: intake review, convert to the `nature.png` atlas
cells or standalone 32/64px sprites, place a test scatter in
`night_forest.tscn` on a branch, screenshot-verify on the emulator,
then PR.

## Batch 2 — spirit redesigns (prompt pack)

Engine side is ready: spirits run facing-less like guardians
(`facings=1`, one horizontal strip, `float_down` always). Do NOT ask
for 4-facings grids — image gen cannot keep 16 cells consistent.

Drop into `_asset_sources/gpt/batch-2/`, one PNG per kind.

Common suffix for every prompt: "pixel art sprite sheet, exactly 4
frames in ONE horizontal row, each frame 48x48 pixels, transparent
background, same character same size same center in all 4 frames, only
subtle hover bob differences between frames, chunky visible pixels,
dark night palette with amber glow accents, no background, no shadow,
no text, no grid lines, no frame numbers".

1. `drifter`: tattered moon-moth bat, glowing pale eyes, wings mid-flap.
2. `ember`: living cracked coal cinder leaking amber light from cracks.
3. `caster`: small hooded wisp-mage, staff orb pulsing, chanting pose.
4. `weaver`: spider-like stitcher with needle legs, weaving gesture.
5. `stalker`: gaunt keeper-ghost in a broken helm, low lunge crouch.
6. `swarm`: one tiny ember gnat, big wings blurred, hungry eyes.
7. `wisp`: curious droplet flame with eyes, bouncing happily.

Intake validation per strip: 192×48 canvas, 4 non-empty 48px cells,
alpha-mask overlap between frames ≥80% (pose may bob, design must not
drift). Failures are rejected back to the ChatGPT project, not fixed
by hand. Wire: replace sheet in each `.tres`, set `facings=1
frames=4`, render-verify every kind, emulator screenshot, PR.

## Batch 3 — choice card art (prompt pack)

Relic cards are 168×112 Buttons with Name+Desc labels. Art replaces
the flat 9-patch style only — text stays rendered (localization).
No Godot-drawn boxes; all states are art.

Drop into `_asset_sources/gpt/batch-3/`.

Frames (ask at 336×224, downscaled to 168×112 on intake):

Common suffix: "game UI card art, single card, top-down flat front
view, transparent outside the card, chunky pixel style, deep navy
card with amber border and small carved corner moons, no text, no
letters, no numbers".

1. `card-normal`: calm resting card.
2. `card-hover`: same card, border brightened, faint amber shimmer.
3. `card-pressed`: same card pressed in, darker, border dimmed.

Relic icons (ask at 96×96, downscaled to 48×48, transparent):

Common suffix: "pixel art game item icon, single centered icon,
transparent background, chunky visible pixels, amber and bone-white
on dark navy, no text".

`dew_hunter` crescent arrow dripping dew · `heavy_arrow` thick
broadhead arrow · `light_step` winged boot · `long_blade` long
curved moonblade · `moon_dash` crescent with speed lines ·
`moon_ring` full ring halo · `moon_ripple` expanding ripple rings ·
`pierce_arrow` needle arrow through a disc · `quick_arrow` three
small swift arrows · `shadow_veil` dark veil with eyes ·
`sharp_moon` crescent blade edge · `swift_hand` quick open hand ·
`tough_life` heart with bark skin · `twin_arrow` two crossed arrows ·
`warm_beacon` tiny lit brazier · `wide_arc` wide bow arc.

Intake: swap card StyleBoxTexture set, add icon TextureRect per card,
map relic id → icon in `relic_panel.gd`, render-verify the 3-pick
panel in all states, emulator screenshot, PR.
