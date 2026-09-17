# Asset replacement plan

Baseline date: 2026-08-02

## Goal and boundary

The goal is to remove the visual identity of the free asset pack in stages
and unify it into Moonlit Beacon's own `moon-blue ink line + beacon vermilion`
language.

The initial A0·A1 scope was an **asset-only replacement** that allowed only
PNG, Godot import, and connecting texture/atlas/frame specs on existing
resource fields. In that scope, do not change GDScript, game rules, AI, save,
input, combat collision, balance, Scene/Node structure and names, or
collision sizes.

A2 is a separate gameplay placement the user requested after real play.
Collision structures and safe movement in the three regions, kill-core missile
growth, hit eject/reclaim, HUD, and Hero-portrait consumption UI are the
explicitly approved exceptions. Those exceptions must keep existing
purchase/select meaning and pass focused regression plus Android device
verification. Current IAP integration and reinstall of the unified source on
iPad are not yet recorded as done.

## Two work lanes

### Lane A — no-code replacement possible now

- Walk/idle sheets and portraits on Hero resources
- Regular-enemy and boss sheets SpiritKind already provides
- Existing per-state sheet slots on bosses
- Region-compatible images that preserve the existing canvas and atlas coords
- Beacon, flame, sparks, smoke, gate, panel, heart already wired as Texture2D
  in scenes
- Slash and static projectiles that already have a texture slot

### Lane B — replacement that needs a minimal visual-wiring exception

The following have nowhere to consume a new PNG in the current structure.

- `_draw()`-based moon disc, moon ripple, moon-disc wave, moon embers, power
  gem, aura
- Extra player slash afterimages, full moon, starlight tells
- Procedural boss overlays and attack tell lines
- Arrow trails, beacon compass, moonfire gauge
- Shop/HUD nodes that actually show a Hero portrait
- Relic/Boon icon fields and icon nodes on cards
- Beacon off/on 2-frame transition
- New multi-frame playback on dew/enemy-shot static Sprites
- Wiring that consumes a new `256×256` terrain atlas by name

The initial Warden placement did not touch lane B. Dedicated sheets for
Dancer·Keeper·Knight·Eclipse·Sage that keep the same foot origin were
finished later. The shrine and shop actually consume the six Heroes'
`48×48` portraits, and locked paid heroes can preview full body plus dedicated
colors/effects before purchase.

## Priority

| Stage | Target | Why | Current status |
| --- | --- | --- | --- |
| P0-A0 | Warden walk/idle/portrait | First impression and the control subject; remove the old ninja | **Done** |
| P0-A1 | Player-only moonlight slash | The most-seen attack, split from Moon Arrow | **Done** |
| P0-A2 | Base enemy/spirit/bat, 7 kinds | Combat-silhouette variety | **Done** |
| P0-A3 | 3 bosses and state sheets | Remove the repeating-boss impression | **Done** |
| P0-A4 | Beacon body/flame/smoke | Identity of the game name and the objective | **Done** |
| P0-A5 | Compatible nature atlas | Free-pack look that fills most of the screen | **Done** — custom atlas preserving original coords |
| P0-A6 | Shared panel | Remove the orange wood that dominates all UI | **Done** — 5px·6px nine-patch |
| P1-B0 | 5 paid-hero sheets/portraits/dedicated FX | Visible value before and after purchase | **Done** — includes IAP preview/restore |
| P1-B1 | Per-region floors/props/collision structures | Reduce map repetition | **Done** — three-region atlases and structures |
| P1-B2 | Drops/shots/hit VFX | Immediate combat reward and danger | **Done** — cores/hearts and procedural per-hero VFX |
| P1-B3 | Title/app branding | Store first impression | **Done** — app icon, splash, subtitle |
| P2 | Button states, gate, projectile-core drawings | Style finish and danger reading | **Done** — 5-state UI, dedicated moon disc, enemy moon bolt |
| P2 | Joystick, font sizes | Style finish | Kept as original derived/procedural |
| P3 | Clean up 46 unused | Repo hygiene | After every reference is verified |

## P0 player placement

### Analysis

- Existing walk: `64×64`, `16×16` cells, 4 directions × 4 frames, 9fps
- Existing idle: `64×16`, `16×16` cells, 1 frame per direction
- Direction columns: down, up, left, right
- Root origin: bottom-center of the feet, world `y=0`
- Collision: root-relative `y=-4`, radius 4 — do not change
- Hero resources already have sheet, cell, frame count, FPS, and portrait fields.

### Design choices

1. A Moonlit Warden: straight hooded cloak — cloth hid the body too much in a small cell
2. B Crescent Wayfarer: long crescent sash — overlapped Dancer's dedicated silhouette
3. C Ember-Moon Scout: wide moon collar and short split coat — **chosen**

Option C was cleaned into short hair, closed boots, above-knee coat, and a
small ember bracer. Elements overlapping a ninja mask/headband were removed.

### Final outputs

| ID | Path | Spec | Wiring |
| --- | --- | --- | --- |
| `hero.warden.walk/idle` | `assets/custom/actors/heroes/warden/` | each `96×128`, `24×32`, 4×4, 9/4fps | Warden Hero |
| `hero.warden.portrait` | `assets/custom/actors/heroes/warden/portrait.png` | `48×48` | Warden Hero + shrine hero card |
| `hero.dancer.walk/idle` | `assets/custom/actors/heroes/dancer/` | each `96×128`, `24×32`, 4×4, 10/4fps | Dancer Hero |
| `hero.dancer.portrait` | `assets/custom/actors/heroes/dancer/portrait.png` | `48×48` | Dancer Hero + shrine hero card |
| `hero.keeper.walk/idle` | `assets/custom/actors/heroes/keeper/` | each `96×128`, `24×32`, 4×4, 8/3.5fps | Keeper Hero |
| `hero.keeper.portrait` | `assets/custom/actors/heroes/keeper/portrait.png` | `48×48` | Keeper Hero + shrine hero card |
| `hero.knight.walk/idle/portrait` | `assets/custom/actors/heroes/knight/` | two `96×128` + `48×48` | Knight Hero + shop/shrine |
| `hero.eclipse.walk/idle/portrait` | `assets/custom/actors/heroes/eclipse/` | two `96×128` + `48×48` | Eclipse Hero + shop/shrine |
| `hero.sage.walk/idle/portrait` | `assets/custom/actors/heroes/sage/` | two `96×128` + `48×48` | Sage Hero + shop/shrine |

Generated-model concept images were not used as final runtime files.
`build_warden_assets.py` and `build_companion_hero_assets.py` bake the final
PNGs deterministically from fixed integer coordinates and per-hero limited
palettes.

## Closed placements and later optional work

Each placement closes in this order: `analysis → 3 concept options → choice →
1x production → contract check → resource wiring → Godot check → Android
device capture → record`.

Production placements are closed for 7 regular enemies, 3 region Guardians
and state sheets, six heroes, three regions, beacon, hearts, shared panel and
5 button states, moonlight gate, dedicated moon disc/enemy moon bolt, and app
icon/splash. The final custom contract is `final 67 / planned 0`.
Active references to remaining Ninja Adventure PNGs and their title-derived
PNGs in game scenes/resources/scripts must be 0 in the automatic check.

Moon-disc core drawings and enemy moon bolts use dedicated custom textures;
trails, moon ripples, missiles, moon embers, and hit presentation are
self-rendered with `_draw()` and Hero color profiles. A separate raster sheet
is a future style option with no current consumer, not an unfinished release
item. If one is added later, go through
`consumer code → exact spec → generator → contract → device capture` again.

## Backup and rollback

Each placement preserves pre-replacement resources and directly replaced
sources in `backup_assets/YYYY-MM-DD-<batch>/`. Each batch README records
SHA-256, changed paths, and restore steps.

The P0 player backup is in `backup_assets/2026-07-29-p0-player/`.
The original Ninja PNGs themselves were not deleted, so restoring only the
Warden resource to the previous state rolls it back immediately.

## Risks and responses

| Risk | Response |
| --- | --- |
| New sprite looks larger than the hitbox | Lock the foot origin, do not change collision, compare 1x on device |
| Shake between frames | Deterministic coordinates, per-frame foot-position check |
| New PNG missing from the Godot import DB | One headless editor import, then game check |
| Generated-sheet proportion/alpha mismatch | Use generation results for concept only; rebuild final at 1x |
| New atlas mismatches existing coordinates | A0·A1 preserve original canvas/coords; A2 checks dedicated structure contracts |
| Icons made but never shown | Do not produce until consumer fields/nodes are confirmed |
| Mid-state mixed with the old pack | Share role colors and 1px outlines first; per-batch device capture |

## Placement approval criteria

- Custom-asset contract checks for size, frames, alpha, and color count pass
- 0px error on every frame's foot or rotation origin
- No adjacent-cell leak and no RGB halo on transparent edges
- Readable at `808×360` 1x, phone, iPad, Android 7-inch and 10-inch tablets
- Actors and danger do not sink into the background at night, day, and the
  three regions
- A0·A1: 0 changes to existing collision, overlap, balance, or scene structure
- A2 gameplay exceptions pass focused regression in the approved scope and
  Android device verification
- Manifest, generation prompts, work log, and backup records update together
- Godot headless and whole-repo verification pass
