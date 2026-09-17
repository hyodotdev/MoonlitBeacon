# Custom-asset production runbook

As of 2026-07-29. This document is not how to make one concept image. It
defines **how to put a new drawing into the real game and verify it all the
way through**.

## Conclusion

The art direction is **top-down pixel woodblock: moon-blue ink lines + beacon
vermilion**.

The first production target is not the whole map. Finish a one-screen
vertical slice with these eight pieces first.

1. Default hero `Moonlit Warden`
2. A drifting spirit
3. Thornwood Pursuer
4. Beacon
5. Night-forest floor and one prop set
6. Full Moon slash
7. Moon disc
8. Moonlight gate for region transitions

Pass that slice at native `808×360` and on a real device (UI 3x, world 4x),
then widen to three heroes, three bosses, regular enemies, terrain, UI.
Use image generation only at the concept stage of finding large form and
mood. Final dot sheets are aligned for frames and hit sizes by a person, or
baked with a deterministic tool.

## Why replace now

The asset-audit baseline had 83 files.

- 71 third-party
- 12 original-derived
- 37 live resource references before replacement, 46 archive files
- 14 `custom/` added so far —
  9 walk/idle/portrait for three heroes, dedicated moonlight slash, moonlight
  core, 3 collision-structure sheets for forest/field/camp

Licenses are mostly CC0 and OFL, so distribution risk is low. The problem is
**visual independence**.

- The three heroes were the same ninja; they now have separate custom sheets.
- Seven regular-enemy kinds are essentially recolors/resizes of three sheets.
- The three region bosses share the same `guardian.png`.
- After user feedback, Warden was remade as an unarmed guardian with a round
  hood, a visible face, and a beacon candle at the chest. The default slash
  is a dedicated sheet, but Moon Arrow still uses the previous slash-compat
  sheet as a projectile-core drawing.
- One wood panel dominates combat HUD, results, shrine, and shop.
- The beacon body and flame — the game's name and objective — still depend on
  a shared pack.

So separate **hero/boss/beacon/weapon silhouettes** before the whole
background, so play and purchase value change at the same time.

## Art north star

### One sentence

A small woodblock where only blue-white moonlight and vermilion beacon fire
stay alive inside deep night ink lines.

### Form language

- Every combat sprite reads as a 1px deep ink line and large color masses.
- Prefer outline differences such as hood, sleeve, horn, wing, plate over
  extra small face detail. Still keep a friendly face plane on playable
  heroes so eyes/cheeks/mouth are not mistaken for a mask or empty glowing
  eyes.
- Player is a stable downward triangle, regular enemies floating
  circles/diamonds, bosses wide asymmetric masses.
- A beacon is recognized by a wide brazier and three-legged stand even when
  the color changes.
- Make exits a vertical open door, heals a droplet, moon embers a swaying
  flame, and permanent currency a hard shard, different from the form first.
- Do not use soft vector gradients or translucent outlines. Only glow FX may
  use limited stepped alpha.

### Meaning palette

| Role | Base color | Use |
| --- | --- | --- |
| Deep night | `#0B0E1C` | Off-screen, deepest shadow |
| Shared ink line | `#141B1B` | 1px outline of characters and props |
| Violet shadow | `#3B3643`, `#4A5270` | Mid night values |
| Mid moonlight | `#79B8CE` | Player skills, moonlit faces |
| Moonlight core | `#CDE1FF`, `#DEF0FF`, `#F2EAF1` | Projectile cores, speculars |
| Danger | `#E0394C`, `#9B3F76` | Enemy attacks, charge/barrage tells |
| Beacon | `#EF914F`, `#F1C471`, `#FFE18D` | Objective, flame, confirm actions |
| Awakening | `#F5C84B`, `#FFF0A6` | Weapons after 10 moon embers |

Color is combat grammar, not decoration.

- Blue-white: a safe attack the player made
- Gold: awakening or a large reward
- Red/magenta: danger that is about to deal damage
- Vermilion: beacon and confirm actions
- Green: heal and safe states

They must still separate by silhouette without color vision. Do not reuse the
same drawing in another role by changing only the palette.

### Three heroes

| Hero | Outline | Held | Motion grain |
| --- | --- | --- | --- |
| Warden | Round head, short hood cape narrowing downward | Beacon candle between both hands | Four beats where only the candle and feet change inside a fixed torso |
| Dancer | Crescent sleeves, ribbon flowing to one side | Ring-shaped moon disc | Large curve change between frames |
| Keeper | Broad shoulders, lantern on the back | Lantern shield | Slow but heavy up-down sway |

A paid hero must show who they are on the play screen before anyone reads an
ability description. Each hero has a dedicated walk/idle sheet and a `48×48`
portrait.

Keep Warden's 2026-07-29 moon-blade/bracer design as a production record from
that time, but do not import it into the current sheet. After user feedback,
leave only a visible face inside a round hood, a short purple bob, a crescent
pin, and the beacon candle at the chest. Weapon grips, bracers, glowing eyes,
and a horizontally extended aiming arm are forbidden.

### Three bosses

| Region | Name | Silhouette | Animation tied to the pattern |
| --- | --- | --- | --- |
| Forest | Thornwood Pursuer | Forward thorn antlers, low four-legged beast | Antlers gather and the body drops before a charge |
| Field | Wings of the Blue Field | Wide left-right crescent wings | Wings open into a cross or circle before a barrage |
| Camp | Ember Ironclad | Square plate and a heavy shield | Closes while defending; the heart is exposed in recover |

Do not distinguish boss kinds with only procedural crown/wing/armor lines.
The three bosses must differ from the sheet onward.

## Runtime lock-ins

| Item | Value |
| --- | --- |
| Internal resolution | `808×360` |
| Reference Android screen | `2424×1080`, UI 3x, game-world pixels 4x |
| Scale | Nearest, no mipmaps |
| Base tile | `16×16` |
| Map / play area | `1900×1180` / `1720×1000` |
| Camera | Game world `4/3` scale, smoothing 6 |
| Aspect | Keep height 360, left-right view grows with `expand` |
| Character origin | Foot position at bottom-center of the cell |

Opaque pixel sprites use only alpha `0/255`. Only glow FX may use about four
alpha steps or ordered dither. Every animation frame must lock foot position
at 0px error.

Exact per-file values treat
`apps/game/tools/custom_asset_contracts.json` as the single source.
If the document and JSON differ, fix the JSON first and sync this table.

### Core final specs

| Asset group | Spec | Layout |
| --- | --- | --- |
| Hero walk | `192×256`, cell `48×64` | columns=down·up·left·right, rows=4 frames |
| Hero idle | `192×256`, cell `48×64` | columns=4 directions, rows=4 frames |
| Hero portrait | `96×96` | transparent, large eyes and blush |
| Regular enemy | `192×192`, cell `48×48` | columns=4 directions, rows=4 frames |
| Boss idle | `384×64`, cell `64×64` | no direction, 6 frames horizontal |
| Boss states | each `256×64`, cell `64×64` | windup/charge/recover, 4 frames horizontal |
| Terrain floor | per-region seamless `256×256` | opaque, 16px tiles 16×16 |
| Terrain props | per-region `256×256` | transparent, 16px grid |
| Beacon stand | `64×48` | 2×`32×48`, off/on |
| Beacon flame | `128×24` | 8×`16×24` |
| Beacon sparks | `96×12` | 8×`12×12` |
| Moonlight gate | `48×64` | transparent, vertical open-exit silhouette |
| Slash | `192×48` | 4×`48×48`, facing right, 110° |
| Moon disc | `128×32` | 4×`32×32`, do not reuse the slash |
| Meteor impact | `384×64` | 6×`64×64`, stepped alpha |
| Moon ember/dew/drop | each `96×24` | 4×`24×24`, per-role silhouette |
| Core icons | `128×128` | 8×8 `16×16` cells |
| UI panel pieces | `96×96` | 3×3 `32×32` cells |
| App icon | one `192×192`, two `432×432` | finished, adaptive foreground/background |

Bosses and regular enemies that change size from today only need
`SpiritKind.cell`, `frames`, and `lift` changed. Terrain atlases have prop
coordinates in `room.gd` hard-coded to the current pack, so do not force a
new drawing that clones those coordinates. First do a small code job: make
one forest set, then switch to name-based region resources.

Final sheets for Warden·Dancer·Keeper are all cell `48×64`, walk/idle each
4 directions × 4 frames. Each hero `.tres` and the Player safety fallback are
wired to custom sheets, and `player.gd` assembles eight animations from this
spec. New heroes keep the same foot origin and
`sprite_cell=Vector2i(48, 64)`, `walk_frames=4`, `idle_frames=4`.
Do not fill the whole cell. The actual silhouette is 50–60px bottom-aligned,
and the height difference between hood-head and body/feet is locked at 2px or
less. Every frame has feet touching y=31, and max torso width is Warden 15px,
Dancer 17px, Keeper 18px.
Warden side views are stricter: hood 12px, face 5px, cloak 9px or less.

The visual origin of Warden's ranged attack is the beacon candle between both
hands at Player-local `(0, -10)`. On fire, overlay a `0.16s` blue-white
casting ring and both-hand embers, and match arrow/missile start and aim math
to the same origin. A homing-missile head is a small candle, diamond
star-core, and short halo, not fighter wings or a long warhead. This
presentation is a runtime contract so "shoot the moonlight from the chest"
connects in one frame without adding an attack pose to the walk/idle sheets.

Wire the boss idle sheet to `sheet`, pattern windup to `guardian_windup_sheet`,
forest charge to `guardian_charge_sheet`, and recover/armor-open to
`guardian_recover_sheet`. Field cross windup is `guardian_windup_sheet`,
radial windup is `guardian_alt_windup_sheet`. State sheets use
`guardian_state_frames=4`.
Runtime adjusts playback speed to actual windup/charge/recover time and
haste below 30% HP, so danger moves do not leak out of the idle loop.

## Folder and source management

### Working sources

Put anything that is not a final file here.

```text
_asset_sources/custom/<batch>/<asset>/
```

This folder is gitignored. Keep:

- Generated-model originals and large concepts
- Aseprite or editor originals
- Palette experiments
- Images before chroma-key removal
- Rejected variants
- Reference captures

Leave prompts and decision reasons in this document or a tracked Markdown
file. If only the source folder exists and the prompt is not in Git, someone
else cannot repeat the same production.

### Review candidates

Put candidate captures and enlarged images before they enter the game here.

```text
builds/art-review/<batch>/
```

This folder is not a shipping asset either.

### Final runtime files

Copy only approved files here.

```text
apps/game/assets/custom/
├── actors/
│   ├── heroes/
│   ├── spirits/
│   └── guardians/
├── world/
│   ├── beacon/
│   ├── gate/
│   └── terrain/
├── items/
│   ├── fx/
│   ├── weapons/
│   ├── projectiles/
│   └── pickups/
└── ui/
```

Do not put master files, prompts, enlarged previews, or unused variants in
the final folder. Compare drafts as `*_v01.png` so they do not overwrite
existing files, and move to the contract filename only after the choice is
done.

## Production pipeline

### 1. Brief

Write these first for every asset.

- Role on screen
- Silhouette that separates it from other roles
- Exact file size and frame layout
- Foot or rotation origin
- Allowed palette and alpha method
- Actual hit size
- Regions/times of day to check

### 2. Concept

Use image generation only to compare large form.

- Do not request an artist name or a specific work's style.
- Make one design decision per call.
- Request background and figures with no letters, UI copy, or watermark.
- Even if a transparent final is needed, lock form on a solid chroma
  background first.
- Do not use a generated sheet as the final pixel animation as-is.

Generated models easily drift body proportion, foot position, pixel size, and
alpha edges per frame. So look at the large concept, then redesign the final
dots at 1x.

### 3. Pixel production

- Draw on a native 1x canvas.
- Remove translucent pixels created after rotate/scale/palette quantization.
- Leave 1px empty at character cell edges to stop adjacent-frame leak.
- Even frames that only need a left-right flip, check that hands and gear
  positions are not wrong.
- Seamless floors match top/bottom and left/right and all four corners
  together.
- Fit slash/telegraph drawings to the hitbox. Do not widen the hitbox to fit
  the drawing.

### 4. Automatic checks

Check candidate files before copying them into the final folder.

```bash
python3 apps/game/tools/check_custom_assets.py \
  --id hero.warden.walk \
  --candidate /absolute/path/to/candidate.png
```

Check every in-repo final with:

```bash
pnpm check:assets
```

The checker confirms size, RGBA, alpha method, frame count, empty frames,
cell-edge leak, RGB color count of every non-transparent pixel, alpha-step
count, and unregistered custom PNGs. Making thousands of colors with only
translucent pixels does not bypass the color budget either. Form and frame
timing still need a person even after automatic checks pass.

See the contract list with `python3 apps/game/tools/check_custom_assets.py --list`.
`planned` passes even if the file is not there yet. Files the game has started
to reference raise the contract state to `final` or `required` so CI must fail
when they are deleted or missing.

### 5. Game wiring

- Copy the new file into `apps/game/assets/custom/`.
- Record source and production method in `apps/docs/docs/assets/manifest.md`.
- Confirm Godot import is Nearest, no mipmaps.
- Do not delete the old asset immediately; retarget references to the new
  path.
- After every reference and capture passes, clean unused files separately.

Write original-made items in the manifest like this.

```text
Source:         Original (AI-assisted concept, manual pixel production)
Creator:        Moonlit Beacon
License:        Follows the project license
Original path:  _asset_sources/custom/<batch>/<asset>/ (not shipped)
Project path:   res://assets/custom/<category>/<file>.png
Used:           <scenes/resources and role>
Modification:   <1x pixel redesign, palette, frame layout, review notes>
```

Distinguish cases that used a generated-model result as-is from cases a
person redrew.

### 6. Visual review

Capture the same scene at these two sizes.

- `808×360` internal render (UI 1x, game world 4/3x)
- Real device `2424×1080` (UI 3x, game world 4x)

Do not approve from an enlarged preview only. In real play the character
moves, and HUD, 40 enemies, and projectiles overlap at once.

## Placement order

### A0 — style vertical slice

Done when:

- Warden, a spirit, the forest boss, the beacon, some forest, slash, and moon
  disc share one screen.
- Mixed with old-pack drawings, the new drawings neither pop nor go muddy.
- Role colors hold in night/day and normal/awakened.
- Player, enemy, boss, beacon, and gate still separate in a 1x grayscale
  capture.

### A1 — heroes and purchase value

- **Done:** three-hero walk/idle sheets
- **Done:** three-hero `48×48` portraits wired to Hero resources
- **Done:** three hero portraits used on shrine purchase/select cards
- **Left:** portraits used in the IAP hero bundle
- **Left:** selected hero visible on combat HUD or pause

Paid heroes used to be the same ninja. Combat silhouettes and shrine
purchase/select portrait wiring are done. Focused regression that opens the
real `ShrinePanel` protects the three cards' `Body/Portrait` `TextureRect`,
`48×48` size, and custom texture paths. Wiring remaining portrait consumption
in the IAP bundle and HUD makes the hero bundle a visible product, not a
feature description.

### A2 — combat silhouettes

- **Done:** moonlight cores that drop on kill and eject on hit
- **Done:** combat loop and HUD where picking up cores raises missile output
  `0…8`
- **Left:** seven regular-enemy kinds
- **Left:** three region bosses
- **Left:** beacon body/flame/sparks/smoke and the moonlight gate
- **Left:** dedicated drawings for Full Moon slash, moon disc, meteor, enemy
  shots
- **Left:** dedicated drawings for moon embers and dew

The moon disc no longer uses the slash sheet. Regular enemies are not split
by color alone either.

### A3 — terrain

1. Night forest
2. Moonlit field
3. Abandoned camp

Collision-structure sheets for the three regions and real placement/collision
wiring are done. Player and spirits follow the same structure bounds, and
start/beacon/drop/exit move lines keep a safe area.
Remaining floors and non-colliding decor expand as per-region `256×256`
repeat floors and `256×256` prop atlases. Finish one, lock the room-generator
contract, then make the rest.

### A4 — UI and title

- Navy/ink shared panels and buttons
- Heart, shard, beacon, exit, boss-compass icons
- 16 relic and 6 permanent-upgrade icons
- Title lockup and app-icon cleanup

Reduce orange wood area so beacon vermilion reads as the objective color
again.

Lock UI atlas order before production.

- `ui.panel_frame`: 3×3, row-major TL·T·TR / L·C·R / BL·B·BR
- `ui.button_states`: left to right normal, focus/hover, pressed, disabled
- `ui.boon_card`: left to right normal, focused, locked
- `ui.hud_symbols`: left to right heart, beacon, gate, guardian, shard,
  timer, defeated, cycle
- `ui.core_icons`
  - row 0: heart_full, heart_empty, shard, moon_ember, moon_dew, beacon,
    gate, guardian
  - row 1: long_blade, wide_arc, swift_hand, sharp_moon, twin_arrow,
    quick_arrow, pierce_arrow, heavy_arrow
  - row 2: moon_dash, shadow_veil, tough_life, warm_beacon, dew_hunter,
    light_step, moon_ring, moon_ripple
  - row 3: steady_heart, keen_edge, light_foot, first_gift, dew_sense,
    shard_sense, locked, purchased
  - rows 4–7: reserved. Transparent empty cells allowed
  - The contract's `required_rows=4` forces every cell in rows 0–3 and allows
    only reserved rows to be empty.
- App icon: `app_icon_master.png` 1024 opaque iOS source,
  `app_icon_main.png` 192 opaque Android legacy, adaptive
  `app_icon_foreground.png`·`app_icon_background.png` 432. Close-up of
  Warden's round lavender-blue hood, warm face, gold crescent ornament, and
  both hands cupping a glowing beacon flame; no gun or letters. Foreground
  visible pixels sit inside the official 66dp safe area, center radius 132px.

Keep the painted art-approved original and Android split sources in
`notes/release/store-assets/source/` and make per-platform production from the
same composition. `tools/build_app_icon_assets.py --check` inspects the real
PNG size/alpha/Android safe circle and iOS/Android paths. The 108×108 locked
shape remains only for determinism of the docs favicon/logo and older
marketing graphics.

## First concept prompts

The prompts below are not for generating a final sheet. Each is a separate
call that decides large form.

### Style vertical slice

```text
Create a text-free 16:9 visual development painting for an original top-down
pixel-fantasy game called Moonlit Beacon. Show a tiny moon warden protecting a
three-legged brazier in a dark forest, one floating spirit, a low thorn-antlered
guardian, a pale crescent slash, and a distinct returning moon disc. Visual
language: bold one-pixel-like ink outlines, woodblock-print silhouettes,
restrained block shading, deep indigo night, cold blue-white moonlight, warm
vermilion beacon fire, small gold awakening accents. Keep the environment
low-saturation and all combat actors high-contrast. Original designs only, no
logos, no readable text, no UI, no watermark, no existing game characters.
This is a high-resolution concept reference, not a sprite sheet.
```

### Three-hero silhouettes

```text
Create a text-free character lineup concept for three original top-down moonlit
guardians on a plain neutral background. Character one is a balanced warden
with a straight short cloak and crescent blade. Character two is a swift dancer
with asymmetrical crescent sleeves, a long ribbon, and a ring-shaped moon disc.
Character three is a broad beacon keeper with a lantern shield and heavy
shoulders. They must remain distinguishable as tiny silhouettes, including
front, back, and side shape notes. Use deep ink outlines, indigo cloth,
blue-white moon highlights, restrained vermilion and gold accents. No text,
logos, watermark, photorealism, or references to existing franchises.
```

### Three-boss silhouettes

```text
Create a text-free boss silhouette exploration for three original top-down
pixel-fantasy guardians. A low thorn-antlered forest pursuer built for chained
charges; a wide crescent-winged field spirit whose wings open into cross and
radial projectile patterns; and a square, ember-lit siege warden whose armor
closes defensively and opens to expose a bright core. Show neutral and attack
silhouettes on a plain background. Bold ink contours, block shading, indigo
shadows, green-blue forest accent, cyan field accent, vermilion camp accent.
No UI, text, logos, watermark, or existing game characters.
```

## Approval gate

One asset set is done only when all of the following pass.

- [ ] Contract JSON size/frame/alpha/color-count checks pass
- [ ] Hero actual height 50–60px, large-head chibi, torso-width cap checks pass
- [ ] 0px error on every frame's foot or rotation origin
- [ ] No adjacent-cell pixel leak and no RGB halo on transparent edges
- [ ] Form reads at `808×360` internal render (UI 1x, game world 4/3x)
- [ ] Pixel 10 UI 3x / game world 4x nearest pixels look even
- [ ] Checked in four times of day: night, blue dawn, sunrise, day
- [ ] Player and danger do not sink into the background in the 12 lighting
      combinations of three regions
- [ ] Player / regular enemy / boss / beacon / gate still separate in grayscale
- [ ] IAP beacon 4 colors still recognize the objective by brazier form
- [ ] Full Moon slash 110° and range 34 match the drawing
- [ ] Moon-disc hit radius 7, beacon approach 34, gate enter 28 are not
      exaggerated
- [ ] Frame budget holds with 40 enemies and projectile flights
- [ ] Manifest records source, production method, and use
- [ ] `rg` shows 0 leftover references before deleting old assets
- [ ] Store-level capture with debug tools hidden

## Next execution units

Exact custom-complete counts are judged by `pnpm check:assets`. Walk/idle/
portrait 9 for three heroes, dedicated moonlight slash and moonlight core,
per-region collision structures, spirits/bosses, and the app-icon family were
produced and wired. Three-hero 24×32 runtime assembly, shrine/IAP-bundle
portraits and full-body detail, core-based missile growth, and terrain-
structure collision are protected by focused regression.

Current A2 integration was verified directly on Android. Kill-core
drop/pickup, hit eject/reclaim, three-region cycling, beacon and boss
progress, max 8-shot flights, and pre-purchase hero detail were confirmed.
IAPKit verify/restore/revoke bounds and the iOS install path are also
integrated, and the latest build is installed on iPad. The iPad is locked and
only refuses Mac auto-launch, so on-device screen judgment remains after
unlock. Do not touch procedural player VFX with no wiring until a separate
approval, and next custom production follows the user-specified order.

1. Make Wisp's single facing in the Warden palette.
2. Review Warden·Wisp together in `808×360` night/day captures.
3. Finish Wisp's 4-direction walk sheet and check it with the contract.
4. Split spirit/bat families into per-role silhouettes.
5. Make the forest boss idle/charge-windup/charge/recover sheets.
6. Integrate beacon body/flame/sparks/smoke on the same screen.
7. Make a forest-prop compatible draft that preserves existing atlas coords.
8. Re-verify the whole A0 vertical slice at 1x and Pixel 10 (UI 3x, game
   world 4x).

Do not mass-produce animation and whole terrains until the first frame reads
on a real screen.
