# Full 2.5D re-art pass (bible)

Author-only design authority for the graphics upgrade. Decided 2026-09-26:
full re-art, not a lighting pass. Style decisions below are Recommended
calls; drops still come from the user's ChatGPT project.

## Style: 2.5D pixel art, same camera, same layout

- Camera stays top-down. "2.5D" is a height read, not a perspective change:
  actors gain material volume (lit top faces, shaded lower faces, rim light
  from the moon at top-left), and the engine keeps drawing the ellipse
  foot shadows (spirit.tscn `Shadow` already exists — no painted shadows).
- Pixel grid stays. Nearest filter and the Compatibility renderer are
  locked, so smooth prerenders would fight the fonts and UI. New pixels,
  same grid: per-material 3-tone volume ramps on the night palette
  (deep navy base, moonlit tops, amber bounce near beacons).
- **Layout locked.** Cell sizes, frame counts, row/column conventions, and
  facing rules do not change — only the pixels inside. Code, animation
  assembly, and hitboxes keep working untouched:
  - Spirits: 96×96, 24px cells, 4 columns (down·up·left·right) × 4 frame rows.
  - Guardians: 64px cells, idle 384×64 (6f), state sheets 256×64 (4f),
    single horizontal row, no facing.
  - Heroes: portrait + idle + walk per hero (same canvas each).
- Silhouette families stay readable: a redrawn stalker must still read as
  the low four-legged charger at 24px. New detail must survive the 3×
  phone scale, not the zoomed-in review.
- This supersedes the `gpt-assets.md` house spec ("no gradients, flat")
  for re-art batches only. Batch 1-3 decor keeps the old spec until its
  own redraw batch.

## Inventory (85 sheets + optional)

| Group | Sheets | Spec | Batch |
| --- | --- | --- | --- |
| Guardians ×6 | 22 | 64px, idle 6f + states 4f | G (first) |
| Heroes ×6 | 18 | portrait/idle/walk | H |
| Spirits ×7 | 7 | 96×96, 4×4 | S |
| World (terrain/beacon/gate/atmosphere) | 15 | atlas + singles | W |
| Items (slash/arrow/bolt/gem) | 4 | singles | U |
| Custom UI (buttons/panels/hearts/busts/icons) | 19 | mixed | U |
| Ninja Adventure third-party | 63 | keep (see below) | N? |

- Ninja pack: Recommended keep. It is the course's Lesson 1-2 starting
  point; redrawing it rewrites the course's beginning. Revisit only if
  the new style clashes on screen.
- Fonts, music, SFX: not visual, out of scope.
- `derived/`: build-time generated, regenerates from sources. No redraw.
- Deterministic pixel generators (`tools/build_*_assets.py`) retire for
  redrawn groups. Drops become final art after cleanup; a new slicing
  validator replaces generation.

## Batch order and why

G → H → S → W → U. Bosses first (the ask), then the heroes the player
stares at, then fodder, then ground, then chrome. One batch fully
landed (intake + manifest + verify + device look) before the next
starts — mixed styles on one screen read as a bug.

## Intake (per batch)

1. Drop into `_asset_sources/gpt/<batch>/`, filenames kept.
2. View every file: palette, silhouette family, frame count, cell grid,
   transparent background, no JPG.
3. Slice/convert to the layout spec; validator checks canvas size,
   frame count, and alpha (replaces the retired generators).
4. Wire only used files into `apps/game/assets/`, manifest rows with
   batch + "custom, generated 2026-09".
5. `pnpm verify` + `pnpm check:assets` + device/emulator look.
6. Store recapture: the full set goes red the moment art lands. Capture
   worry is waived for now, but the store sets must be reshot before
   any release that ships new art. That needs its own explicit go.

## Course impact (must not forget)

- Lesson clips showing old sprites must be reshot (audit per lesson
  once Batch G lands; guardians appear from the boss lesson on).
- Prose referencing the deterministic pixel pipeline
  (`build_spirit_guardian_assets.py` and siblings) must be rewritten
  for redrawn groups — the pipeline no longer produces those files.
- `notes/` plans that pin palette/production stay as history; this
  file is the authority from here on.

## Prompt packs

Guardian pack lives in `notes/workflow/gpt-assets.md` (Batch G) with
the style addendum. H/S/W/U packs follow the same template once G
lands and the style is proven on screen.
