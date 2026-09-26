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
As built 2026-09-26: every kind is 6 frames as a 2x3 grid on a
square canvas (4-frame strips read choppy and come back portrait),
sliced to `288x48` with `slice_gpt_grid.py --cell 48`.

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
As built 2026-09-26: the 4 card states came as ONE 2x2 grid (keeps
states pixel-aligned) via `slice_gpt_cells.py` full-cell mode; the
16 icons came as ONE 4x4 grid via `--fit` bbox mode.

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

## Style addendum for re-art batches (G/H/S/W/U)

Supersedes the house spec above for re-art only. Same top-down camera
and layout; new pixels with volume: lit top faces, shaded lower faces,
moon rim light from top-left, 3-tone ramps on the night palette
(navy/moonlight/amber). Keep the pixel grid and silhouette families.
No painted shadows (the engine draws foot shadows), no JPG.

## Batch G — guardian re-art, all six bosses (prompt pack)

Drop into `_asset_sources/gpt/batch-g/`. One generation per sheet
(22 total). Proven 2026-09-26: request grids, never strips — every
sheet is 6 frames as a 2x3 grid on a square canvas (4-frame states
look choppy; minimum 6 connected frames everywhere). Direct
strip requests come back portrait and cannot fill square
cells. Slice with `apps/game/tools/slice_gpt_grid.py`, which validates
frames (empty/bleed/size warnings). Always add: "high contrast",
"keep every creature smaller with wide transparent margins on all
sides including the outer canvas edges, nothing may touch any
edge", "no floating debris".

Common suffix for every prompt: "top-down 2.5D pixel art game sprite
sheet, single horizontal row of animation frames on transparent
background, chunky visible pixels, lit top faces with shaded lower
faces, moon rim light from top-left, deep navy and amber night
palette, same creature and silhouette in every frame, no shadow, no
background, no text".

Layout: every sheet is 384×64 (six 64×64 frames). Same strip size
for idle and states, so `guardian_state_frames = 6` everywhere.

Forest Thornwood Pursuer (horns, long tree-arms, rooted feet):

1. `forest`: idle breathing, arms swaying, 6 frames.
2. `forest_windup`: rearing back, arms raised, about to rush, 6 frames.
3. `forest_charge`: full rushing lunge forward, motion lean, 6 frames.
4. `forest_recover`: skidding to a stop, arms dropping, 6 frames.

Thorn King Pursuer (older, thorn-crowned, deeper bark):

5. `forest_thorn`: idle, heavier sway, thorns glinting, 6 frames.
6. `forest_thorn_windup`: rearing with thorns flared, 6 frames.
7. `forest_thorn_charge`: crushing lunge, thorns first, 6 frames.
8. `forest_thorn_recover`: grinding halt, thorns settling, 6 frames.

Azure Fieldwing (wide crescent wings, mask, cloud tentacles):

9. `field`: idle hover, wings beating slowly, 6 frames.
10. `field_windup_cross`: wings folding into a cross pose, 6 frames.
11. `field_windup_radial`: wings spreading into a full ring pose, 6 frames.
12. `field_recover`: wings drooping, sinking lower, 6 frames.

Storm Fieldwing (charged feathers, lightning veins, torn wing edges):

13. `field_storm`: idle hover in rising wind, sparks, 6 frames.
14. `field_storm_windup_cross`: cross pose crackling, 6 frames.
15. `field_storm_windup_radial`: ring pose crackling, 6 frames.
16. `field_storm_recover`: discharged droop, last sparks fading, 6 frames.

Emberclad Warden (brazier helm, hammer, gate shield):

17. `camp`: idle guard stance, brazier breathing, 6 frames.
18. `camp_windup`: hammer raised, shield braced, aiming, 6 frames.
19. `camp_recover`: armor open, hammer lowered, exposed core, 6 frames.

Siegeclad Warden (heavier plates, siege hammer, cracked shield):

20. `camp_siege`: idle siege stance, embers leaking, 6 frames.
21. `camp_siege_windup`: siege hammer raised high, 6 frames.
22. `camp_siege_recover`: plates parted, core glowing, 6 frames.

Intake: validate canvas + frame counts, wire into
`assets/custom/actors/guardians/`, manifest rows with batch G,
`pnpm verify` + `check:assets`, render-verify idle + all mid-states
(no fallback to old art), emulator screenshot, PR. H/S/W/U packs
follow once G proves the style on screen.
