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
