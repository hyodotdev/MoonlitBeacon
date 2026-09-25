# Asset-redesign work log

Baseline date: 2026-07-29 KST

## Scope

This work unit is: finish a full asset audit, then actually replace P0's
first target — Warden — and the player default slash that can be split
without code. GDScript, combat hits, collision, AI, save, input, and
balance were not changed. `player.tscn` changed only the existing `Slash`
node's texture path; Scene/Node structure and names stayed.

## Chronological record

### 1. Rules and tools

- Confirmed the repo's `AGENTS.md`, verification/device procedures, and
  Moonlit workflows.
- Surveyed connected tools.
  - Codex built-in image generate/edit
  - Figma-related MCP
  - GitHub, Google Drive, Gmail, Slack, Sites MCP
  - Browser/Chrome/macOS UI control tools
- There was no dedicated pixel-art, spritesheet, or background-removal MCP.
- Surveyed the local run environment.
  - Available: Python 3, Node.js 24, pnpm, ffmpeg/ffprobe, sips,
    Swift/xcrun, adb, `/Applications/Godot.app`
  - Codex-bundled Python: Pillow, NumPy
  - Codex-bundled Node: sharp, pngjs, canvas, Playwright
  - Background removal: Codex imagegen `remove_chroma_key.py`
  - Not installed: Aseprite, LibreSprite, Pixelorama, ImageMagick, pngquant,
    optipng, Blender, Inkscape, Krita, Audacity, SoX
- Godot could be driven with the repo's `scripts/godot.mjs`, and Android
  Pixel 10 emulator `emulator-5554` was connected.

Decision: actually use image generation for concept comparison, and make
final exact sheets with a deterministic pixel generator that has no install
dependency. Final PNGs were already transparent RGBA, so background removal
was not run.

### 2. Full project audit

- Inspected 30 `.tscn`, 53 main `.gd`, 40 `.tres`.
- Confirmed 83 source assets.
  - Ninja Adventure 67
  - Kenney 2
  - Galmuri 2
  - original-derived 12
  - live references 37, unused archives 46
- Confirmed there is no `TileMap`, `TileMapLayer`, `TileSet`, custom Theme,
  shader, or `AnimationTree`.
- Confirmed three heroes share the same ninja, five regular enemies share
  the same spirit, three bosses share the same guardian, and slash and
  arrow share the same texture.
- Confirmed terrain is not a TileMap but 34 atlas coords in `room.gd` and
  1,288 Sprite2Ds baked in the title scene.
- Confirmed weapons/drops/HUD drawn only with `_draw()` have no new texture
  hook.

Detail is in `docs/asset_audit.md`.

### 3. Warden spec lock

- Existing walk `64×64`, cell `16×16`, 4 dir × 4 frames, 9fps
- Existing idle `64×16`, 1 frame per direction
- Direction order down·up·left·right
- Foot bottom-center is world `y=0`
- Collision center `y=-4`, radius 4 — not changed
- Using existing Hero-resource fields `walk_sheet`, `idle_sheet`,
  `portrait`, `sprite_cell`, frame count, and FPS, a `24×32` wire is
  possible without code changes

### 4. Three concept options and choice

Codex image generation actually produced these three.

1. A Moonlit Warden — straight hooded cloak
2. B Crescent Wayfarer — asymmetric crescent sash
3. C Ember-Moon Scout — wide moon collar and short split coat

C was chosen because legs and gear read best in a small cell. A hid the
walk under the cloak; B overlapped Dancer's curve silhouette.

One more edit replaced topknot/bare feet with short hair/closed boots and
shortened coat tails and bracer. Actual prompts and output files are in
`docs/generation_prompts.md`.

### 5. Backup

Before replacement, copied the following to
`backup_assets/2026-07-29-p0-player/`.

- previous `warden.tres`
- existing `ninja_walk.png`
- existing `ninja_idle.png`

Original Ninja PNGs were not deleted from runtime third-party paths either.
Backup SHA-256 and restore steps are in the batch README.

### 6. Final 1x pixel production

Made `apps/game/tools/build_warden_assets.py`.

- RGBA canvas and PNG encoder with no external image library
- Locked integer coordinates and a 17-color production palette; 15 visible
  colors in the final PNG
- Binary alpha
- `walk.png` `96×128`, 4 dir × 4 frames
- `idle.png` `96×128`, 4 dir × 4 frames
- Foot bottoms and cell padding locked on every frame

The first enlarged preview made the side moon collar look like a mask and
front boots read large. The collar was lowered and reduced, side-facing
front boots narrowed, then regenerated.

### 7. Contract check and wiring

Turned Warden's three files to `final` in the custom-asset contract.

- `hero.warden.walk`: pass
- `hero.warden.idle`: pass
- `hero.warden.portrait`: pass

Changed only existing fields on
`apps/game/resources/heroes/warden.tres`.

- 3 new custom textures
- walk and idle 4 frames each
- walk 9fps, idle 4fps

The Warden replacement stage did not change GDScript or Scene files.
Portrait texture is wired on the Hero resource, but current UI does not
read `Hero.portrait`, so it is not on screen yet.

### 8. Godot import and headless verification

First `pnpm game:check` failed with a texture-loader error because the new
PNGs were not yet in the Godot import DB. This was not a file-spec problem.

Imported the 3 new files with:

```bash
node scripts/godot.mjs --headless --editor --path apps/game --quit
```

Then these checks passed.

```text
pnpm game:check       PASS
pnpm check:scripts    PASS (55)
```

Generated `.png.import` is lossless, no mipmaps, following the project's
Nearest filter.

### 9. Android device loop

Used the repo's safe wrappers on the Pixel 10 emulator.

- APK build, install, run succeeded
- Screen `2424×1080`, internal `808×360` exact 3x
- Captured title, arena idle, and facing frames while moving
- New Warden displayed with a clearer moon-collar and split-coat silhouette
  than the old ninja
- Foot origin matched shadow and world; collision center unchanged
- Transient load on the first tutorial frame, then stable 59–60fps, CPU
  about 5–9ms
- On an `808×360` native-pixel screen scaled exactly 1/3 Nearest from the
  `2424×1080` capture, moon collar, both legs, and shadow contact still
  separated

Review captures are in non-shipping `builds/art-review/a0-player/`.

### 10. Final integration verification

Regenerated, then confirmed the three PNGs' SHA-256 matched the
immediately-after-production values.
The bottom-most visible pixel of all 32 walk/idle cells was `y=31`, and
walk's 4 frames per facing were all different. Idle is a 4-beat loop of 3
unique drawings: ember `weak-strong-strongest-strong`.

Whole `pnpm verify` passed.

```text
Android build-tool tests     6/6
IAPKit config tests          9/9
export pre-check             2/2
iOS build-tool tests        15/15
game regression            790
GDScript compile            55
custom-asset contracts       3 pass, planned 54
locale · repo hygiene · docs build · internal anchors pass
```

At this point `git diff --name-only` separately confirmed 0 `.gd` and
`.tscn` changes.

### 11. Player VFX in the user-specified order

Applied the user-specified order `player → player VFX → base enemies`.
Moon disc, moon embers, and extra afterimages drawn only with procedural
`_draw()` have no texture hook, so they were left; only the default slash
with an existing Sprite2D texture slot was split safely.

Made `apps/game/tools/build_moon_slash_asset.py`.

- `moon_slash.png` `192×48`, `48×48` 4 frames
- A 110° blue-white crescent fills, splits into a lattice afterglow, then
  vanishes
- At most 5 alpha steps including transparency
- At first judged to be inside the 34px base range by adding only the
  runtime center distance 13px and local radius, but a later independent
  review found the missing hand-height pivot `(0, -6)`
- Did not overwrite the existing `32×32` derived sheet for Moon Arrow

Changed only the existing `Slash` texture path in `player.tscn`. Node
add/delete, names, hframes, animation timing, scale formula, hits, and
balance were not changed.
The pre-replace scene and existing shared PNG are in
`backup_assets/2026-07-29-p1-player-vfx/`.

Godot editor import, `game:check`, and 55 GDScript compiles passed.
First `check:assets` correctly caught that the new PNG was not yet in the
manifest; source, use, and production method were added to the manifest.

### 12. First slash-alignment correction and Android verification

Final self-review found a few decorative ember pixels on 2 frames might
read farther than the production radius cap. Decorative coordinates were
moved inward and the generator now measures actual center distance of every
non-transparent pixel. The hand-height pivot was still missing then; the
products and incomplete figures at that time were:

```text
local max visible radius       20.112px / cap 20.5px
distance with pivot omitted    33.112px / base hit 34px
```

Re-imported the fixed PNG in Godot, then rebuilt and reinstalled the APK on
the Pixel 10 emulator.

- `android:build`, `android:run` passed
- Confirmed on `2424×1080` and exact `808×360` 1x
- Reviewed the default slash without choosing Long Blade range upgrade
- Four frames of start wedge → wide blue-white arc → broken afterglow →
  vanish displayed in order on real auto-attack
- Attack-direction rotation and enemy-contact position confirmed by eye,
  but the pivot error was not identified
- Stable 60fps, CPU about 5–8ms, physics about 1–3ms

Representative full screens, 1x screens, and 60fps frame sequences are in
gitignored `builds/art-review/a1-player-vfx/`.

### 13. First integration verification

Ran the slash generator twice in a row and confirmed identical SHA-256.
After `fdae8a8`, GDScript changes 0, Scene changes 1 (`player.tscn`), and
that diff is only replacing the existing `Slash` texture path.
`git diff --check` also passed.

First `pnpm verify`:

```text
Android build-tool tests     6/6
IAPKit config tests          9/9
export pre-check             2/2
iOS build-tool tests        15/15
game regression            790
GDScript compile            55
custom-asset contracts       4 pass, planned 53
locale · repo hygiene · docs build · internal anchors pass
```

These all passed, but automatic checks only confirmed the generator's local
radius contract then. The following independent review found the missing
non-rotating hand-height pivot and reopened the geometry contract.

### 14. Independent-review pivot defect fix and final Android device

`review-self` found `player.gd`'s `SLASH_PIVOT = (0, -6)` was missing from
the first generator math. Runtime places the slash in this order.

The `33.112px` from local radius alone was therefore not the real worst
distance. The generator was changed as follows.

- Shrink production local-radius cap to `14.5px`
- Include worst radius of the rotating pivot for every non-transparent pixel
- Include worst distance as the pivot sweeps both 110° cone edges
- Fail before writing the PNG if range or angle contracts are exceeded

Final contract:

```text
local max visible radius           14.300px / cap 14.5px
worst distance with pivot+rotation 32.879px / base hit 34px
cone-edge min slack                 4.770px
```

Separately from the analysis, 327 visible pixels were applied to 3,600
attack directions. Across 1,177,200 combinations, range/angle violations
were 0 and max relative angle was `42.387° / 55°`.

Re-imported the fixed PNG into Godot and rebuilt/reinstalled the APK on
Pixel 10 emulator.
On real auto-attack, wedge, blue-white arc, lattice afterglow, and vanish
read in order, and Warden silhouette and effect stayed separate in enemy-
contact scenes. Stable screen 60fps, CPU about 5ms, physics about 1ms.
Final video and frame sequences are in `builds/art-review/a1-player-vfx/`.

### 15. Final integration verification and re-review

After the pivot fix the slash generator was run twice in a row and SHA-256
was `8d4f0b5b56105ee2a19a5d99540c1721471598dcfe80664794d77d8c467ccfc9`
both times. Final `pnpm verify` passed again.

```text
Android build-tool tests     6/6
IAPKit config tests          9/9
export pre-check             2/2
iOS build-tool tests        15/15
game regression            790
GDScript compile            55
custom-asset contracts       4 pass, planned 53
locale · repo hygiene · docs build · internal anchors pass
```

Independent re-review also recompared runtime coordinate formulas, radius
formulas, cone-edge formulas, 1,177,200 samples, document figures, SHA-256,
and backup originals, and ended with no P0/P1 defects.
GDScript changes 0; Scene change is only the texture path in `player.tscn`.

## Before / after

| Item | Before | After |
| --- | --- | --- |
| Warden look | same 16px Ninja as other heroes | dedicated 24×32 Moonlit Warden |
| Idle/walk | 1 static frame per facing + breathe | idle and walk 4 frames each, no extra whole-body offset |
| Color | generic blue ninja | ink, navy, blue-white moonlight, tiny vermilion ember |
| Portrait | none | 48×48 generated and resource-wired, waiting on UI consume |
| Default slash | same 32×32 sheet as Moon Arrow | dedicated 48×48 4 frames, base 28.023/34px, independent-upgrade combo min slack 0.323px |
| Logic/hits | existing | unchanged |

## Currently done and remaining

Done:

- tool inventory
- full asset audit
- art bible
- replacement plan
- 3 player options and choice
- Warden final sheets and portrait generation
- player-dedicated moonlight slash generation and split
- backup, contract check, resource wiring
- Godot and Android device verification

Next batch:

1. Base enemy Wisp
2. Per-role silhouettes for spirit/bat families
3. 3 bosses and state sheets
4. Beacon body/flame/sparks/smoke
5. Compatible nature atlas and navy/ink UI panels
6. Dancer·Keeper dedicated sheets and portraits

Moon disc, power gem, moon embers, icons, portrait display, and a new
terrain atlas cannot be no-code replaced with the current wiring. A narrow
visual-wiring-only exception must be approved before production.

### 16. Direct-play re-verification and high-upgrade slash correction

Even after writing "final," a new run was opened on Android and default
move, four-direction attack, dash, high-upgrade rapid fire, death, result,
and restart were walked again in order. The connected target is not a real
iPad or Android phone but `sdk_gphone64_arm64` Android emulator; landscape
captures are `2424×1080`, internal game screen `808×360`.

The first recording that wrongly used the right half as a move stick was
discarded. Four-direction move and dash were re-recorded on the left half
the real stick receives, and the new Warden's per-facing walk frames and
dash afterimage kept the same foot contact. Unrecorded stable screens were
60fps, and Android logcat GDScript errors were 0.

This loop reproduced a P1 defect the previous review missed. The existing
wide slash PNG, when Full Moon family is stacked 24+ times, independently
composes range, angle, and damage scale, and a white bar crossed the
screen. The visible attack was up to about 42px farther than the real hit
and occupied about 62.5% of screen height. So sections 14–15's "no P0/P1
defects" was an incomplete conclusion for the default state only; this
section corrects it.

Without changing game scripts, the slash source was remade as a small S-
shaped moonlight ribbon.
The generator now inspects all 3,640 states that independently combine the
real runtime's range stack, cone stack, and damage-based thickness, plus
376 visible-pixel corners.
`--check` also confirms byte identity of generation result and saved PNG,
and is wired into `check:assets`.

```text
base visible tip                 28.023px / hit 34px
regular-attack worst min slack    0.323px
Full Moon worst min slack         4.728px
cone worst min slack              0.768°
extra pixel safety padding        0.5px
checked states/corners            3,640 / 376
SHA-256                           f6ef17bce31fb0ed7dae33535a78e8f53551652509d742567e7386c83f2b7cf2
```

A new APK was rebuilt/installed and the same conditions reproduced through
Full Moon tiers 25–27.
Two-way moonlight ended inside the real attack range around the character,
and the pre-fix screen-crossing bar was gone. After death, a new run with
high upgrade numbers reset, and Warden plus the new default slash
reconnected, was also confirmed.

Direct play also revealed two existing defects outside no-code asset scope.

- Full Moon's procedural `_full_wave` ring is drawn to 1.3× attack range in
  script, but the 360° hit is 1.15×, so PNG replacement alone cannot match
  them.
- Death right after a high-upgrade attack makes `stop_for_result()` reset
  procedural afterimages and immediately turn off Player processing. The
  reserved redraw is not consumed, so gray afterimages and rings freeze
  behind result stats — reproduced on device.

Those two cannot be fixed with generated PNG or resource paths. They were
not changed arbitrarily, to keep this work's absolute condition "no GDScript,
game-logic, or scene-structure changes," and are recorded as remaining
defects until a visual-handling-only GDScript exception is approved.

### 17. A2 play loop — re-audit of install path, combat, terrain causes

Per user device feedback, this work lifts the previous batch's "assets
only" limit and also fixes combat, collision, and HUD. First, the product
actually installed on iPad was compared with ancestors of the two local
work trees.

- The iPad install was built from the `fix/iap-verification-gates` work
  tree.
- That tree includes IAP/CI fixes but not `codex/custom-art-production`
  Warden custom assets and runtime wiring.
- The installed PCK had Ninja walk/idle sheets and no `assets/custom/`
  files.
- The main work tree still pointed Dancer·Keeper and the Player-scene
  safety fallback at Ninja.

So "custom characters don't show on iPad" was not an art-quality problem
but overlapping unfinished two heroes plus a build path that never unified
the two work trees. This batch set as done conditions: switch all three
heroes and the safety fallback to original sheets, and reinstall iPad from
one source state that also includes IAP fixes.

Map and missile loops were also retraced in code.

- Interior props of all three regions were non-colliding `Sprite2D`.
- Player and spirits only clipped the map rectangle and passed through
  every interior object.
- Kill embers made only a 6.5s temporary awakening, unrelated to permanent
  missile output.
- Homing flights opened suddenly after a long relic finish; on hit, a last
  random relic dropped, not a missile.
- Shot-count upgrades cloned existing damage per shot, so early firepower
  doubled.

The fix goal is to make these three state transitions read on one screen.

```text
spirit kill → moonlight-core drop → pick up → missile output 0…8 rises
hit → one output step ejects onto the field → reclaim in 9s or permanent loss
enter region → unique structure placement → player and spirits move along the same bounds
```

### 18. A2 concept generation and final production method

Codex image generation made original concepts for Moon Dancer, Ember
Keeper, and four terrain-structure kinds. Originals were kept on the
tool's generation path and in
`_asset_sources/custom/a2-gameplay/concepts/`. Review-transparent copies
were also made with `remove_chroma_key.py` auto-sampling key color at
corners.

Final runtime PNGs are not downscaled large generated images. Like existing
Warden, a deterministic 1x pixel generator with locked coordinates and
palette redraws them. That lets foot position, direction columns, frame
rows, alpha, and atlas bounds of 24×32 frames be checked automatically.
Actual generation prompts are in `docs/generation_prompts.md` with only
line breaks cleaned.

### 19. A2 combat/terrain integration and verification

Current custom finals are 14.

- Warden·Dancer·Keeper walk/idle/portrait 9
- player-dedicated moonlight slash 1
- moonlight core used in the kill/hit loop 1
- forest/field/camp collision-structure sheets 3

All three Hero resources and the Player safety fallback were wired to
custom sheets. Shrine cards also show each Hero's `portrait` as a real
`48×48` `TextureRect`. Existing unlock, balance check, select, recommend,
translation keys, and button-callback meaning were kept.

Terrain places 14 forest, 9 field, and 12 camp structures. A shared
collision interpreter is used by player and spirits, with safe areas around
start, beacon, drops, and exit.
Non-colliding decor sits behind actors; real structures sit on a y-sort
layer so visible bounds match collision bounds.

Missile output is a `0…8` growth state split from relic cards. Regular
enemies are kill-value 1, elites 3, bosses 10; the first core drops at
cumulative 3, then every 5. Per-output shot counts are
`1, 2, 2, 3, 4, 5, 6, 7, 8`, and homing starts at output 4. Regular cores
can be reclaimed for 12s, ejected cores for 9s. Damage is not cloned per
shot; a total budget is split, blocking both early firepower explosion and
single-target reverse-upgrade.

APK was built/installed/run on the Pixel 10 Android emulator and the
following were confirmed directly.

- After the third kill a core and HUD appear; pickup raises output.
- A hit ejects one output step; reclaim restores it.
- Moving forest → field → camp collides with structures and continues
  three-beacon/boss progress.
- At max output 8, several homing missiles read on the real screen at about
  59fps.
- Normal progress was 60fps with no GDScript errors in Android logs.

Device evidence is in gitignored `builds/art-review/a2-gameplay/` as
`core-visible.png`, `hit-drop-clear.png`, `route-normal-t10_3.png`,
`route-normal-t11_5.png`, `max-precheck.png`, `route-normal.mp4`.

Automatic verification passed 1,621 game regressions. Detail: hero visuals
548, shrine portraits 17, missile growth 91, missile combat 27, vault 141,
IAP 650, terrain structures 95, terrain integration 23, result flow 29.
57 GDScript files and 97 asset-manifest entries also passed, distinguishing
custom final 14 and planned 43.
Python for the asset checker uses `-B` and ignores `__pycache__/` and
`*.py[cod]` so verification itself does not dirty the work tree.

Two items are still not recorded as done.

- Final integration of the IAP/CI work tree with current A2 source
- iPad install and on-device confirmation of a build from that unified
  source

### 20. A3 original spirits/Guardians and kill-core growth lock

After section 19, IAP/CI changes were integrated into current game source,
and three leftover user-feedback problems were closed again. This section
does not erase earlier figures; it corrects them to the current
implementation.

First, all 7 active-runtime regular spirits and 3 region Guardians were
replaced with original sheets. Regular spirits have per-facing move frames
and per-role silhouettes; forest/field/camp Guardians read default/tell/
attack/recover on different sheets. A contract that active spirit/Guardian
resources do not reference third-party character sheets was also added to
automatic checks.

Terrain structures grew to forest 32, field 28, camp 30. The 1900×1180 map
was divided into 6×4 anchors with extra center/side anchors. Then, with
world camera at 5/3x (visible about 485×216), anchors and jitter were
adjusted so each of 9 representative points shows two large collision
structures as real opaque pixels. Center start safe radius 140px and the
exit path stay. Each structure's drawing and collision circle correspond
1:1. Player and spirits go around the same bounds; enemy projectiles
vanish at the first structure they meet even if they cross between frames.
Paths between beacon, exit, and start are reconfirmed with deterministic
pathfinding.

Missile output is locked as `0…8` kill-loot growth fully split from relic
cards.

```text
current output                 0  1  2  3  4  5  6  7  8
kill-value to next core        2  3  4  4  5  5  6  6  -
flight shot count              1  2  3  3  4  5  6  7  8
homing                         -  -  -  Y  Y  Y  Y  Y  Y
```

Regular spirits are kill-value 1, elites 3, Guardians 10. Filling a
threshold drops a core at the latest kill position; output rises one step
only when actually picked up. Missing the first core restarts from the
first `2` threshold. When the flight grows, existing one-shot damage is
not cloned; a per-step total damage budget is split, blocking both early
firepower explosion and single-target reverse-upgrade.

Hits no longer drop the latest relic. Only one output step ejects as an
orange core; auto-reclaim is locked for 0.75s right after, then 9s to
reclaim. HUD keeps showing remaining seconds and off-screen core direction.
Reclaim restores the step; expiry confirms the lowered output.

Current automatic regression totals:

```text
game regression              2,886
  hero visuals                 548
  shrine portraits              17
  spirit/Guardian visuals    1,154
  missile growth               108
  missile combat loop           48
  vault                        141
  IAP                          654
  terrain structures           161
  terrain integration           26
  result flow                   29
GDScript                        57
locales                        262
asset manifest                 115
custom status              final 32 / planned 25
```

IAPKit transaction verify, purchase restore, revoke reclaim, and a GitHub
Pages workflow for manual runs only were also integrated into the same
source. On the Android emulator, kill→core→output rise, hit→core
eject→reclaim, forest→camp→field switch, custom Guardian kill, and next-
cycle entry were confirmed directly. Stable stretches were 60fps with no
GDScript errors.

The same source was re-exported for iOS and checked for arm64, bundle ID,
code signing, and IAPKit publishable-key-only conditions. Xcode 26's
`AssetCatalogSimulatorAgent` did not respond on this Mac, so only the
connected-device Debug build omitted the asset catalog; the App Store
archive path stayed. The finished app was installed on the connected iPad
with USBMux `upgrade`, preserving the existing install and save, then the
`com.crossplatformkorea.moonlitbeacon` bundle was re-queried after install.
The developer disk image was not mounted so Mac could not auto-launch; the
device app icon can be pressed to play immediately.

### 21. Warden redesign from user feedback

2026-07-30 play feedback confirmed Warden looked creepy more than cute, and
more like a character that would hold a pistol than one that shoots
moonlight from the chest. 2026-07-29 candidates A–C and the first choice
are kept as the decision record from then; only the current production-
sheet form was re-locked to:

- Remove the short moon blade and rectangular ember bracer.
- Use a widely visible skin-tone face, purple bob, small eyes/cheeks/mouth
  instead of a face with only blue-white glowing eyes.
- Emphasize a large round hood cape and short boots over an angular split
  coat.
- Bring both empty hands to chest center to cup a small moonlight seed.
- Even in side views, arms or light must not extend out of the body like a
  horizontal muzzle.
- Redraw the portrait in the same face/hood/empty-hands/moonlight-seed
  grammar.

Codex built-in image generation was used only at the concept stage of
comparing the new cute form.
The review result is in gitignored
`builds/art-review/a0-player/cute-warden-concept.png`; actual `24×32`
walk/idle sheets and `48×48` portrait are still generated by
`tools/build_warden_assets.py` with locked integer coordinates, 18 visible
colors, and binary alpha. Hood ornaments that could read as horns on the
concept were not put on the runtime sheet.

A ranged-moonlight presentation contract was also set so character and
auto-attack tell the same story.

```text
both-hands moonlight origin   Player-local (0, -10)
cast display time             0.16s
cast form                     small blue-white ring + both-hand embers
arrow/missile start           same chest origin
missile head                  moonlight seed · diamond star-core · short halo
forbidden                     fire from the feet, long warhead, fighter left-right wings
```

The new face and seed sinking under the Player root's locked night tint was
fixed with Sprite readability correction `Color(1.85, 1.72, 1.3, 1)`.
Later 5x device zoom showed paid heroes' dark cloaks/props sinking for the
same reason, so this correction is applied to every hero Sprite. Player
root and attack-effect night tint stay.

When the game world showed 5px per source 1px on Pixel 10, left/right
frames that reused the front wide face and both-hand prop also looked
unnatural. Warden and the 5 paid heroes' sides were redrawn as a narrow
profile with one eye in the travel direction, one hand, and a small
dedicated prop in front of the body. All 112 frames of 7 regular enemies
were checked at the same size; Swarm's inner light/tail differing left vs
right, and isolated 1px direction dots, were fixed with exact final-frame
flips and 2px speed lines. The generator directly checks exact left/right
flips, profile width, one-hand poses of 6 heroes, and Swarm inner flips.

A separate `com.crossplatformkorea.moonlitbeacon.dev` APK was installed on
real Pixel 10 `57051FDCR000HW` and six heroes' left/right stills plus
Warden's `2424×1080`, 60fps move recording were reconfirmed. All kept
nearest 5px blocks with no facing-switch or walk-outline shake of face,
hands, or props. Shipping package and user save data were not changed.

The same device build walked title, new run, move/dash, Lv20 dense combat,
field Guardian, result, and pause. A defect was found: while the new-run
first-move guide is alive, pausing lets the HUD-center Banner show through
behind the `Paused` title. Pause open/resume now stores only whether Banner
is currently shown, hides it, and on resume restores from the remaining
Tween time. The guide is not cleared, so a first-time player can keep
reading after resume, and regression checks hide and restore together.

A new APK was installed on `emulator-5554`, Warden chosen at the shrine,
and `2424×1080` native screen plus 6–8s combat recordings confirmed. Round
hood, eyes, cheeks, mouth, empty hands, and center seed still read on the
night screen, and multi-shot moon discs spread from the chest seed.
Enlarged frames showed no muzzle/grip-like horizontal protrusion.
First self-review found Player-parent casting `_draw()` hidden behind the
child Sprite. Cast light was moved to a dedicated `MoonlightCast` Node2D
after the Sprite, then re-recorded, confirming round core, blue-white ring,
and both-hand embers appear in front of the body and moon discs leave that
center.
ADB runtime-log consecutive samples were `59~60fps`, draw calls `197`,
primitives `2503~2505`, with no `SCRIPT ERROR`, `FATAL`, or `ANR`.

Deterministic asset contracts, focused regression on hero sheets, shrine
portraits, and missile origin, and full `pnpm verify` all passed. Missile
focused regression also checks that both straight moon-disc and homing-
flight node/inner-shot positions match Player `moonlight_origin()`.

### 22. Warden app-icon family integration

The previous app icon was a separate mark combining crescent and beacon
stand, so first impression did not continue the post-feedback locked "cute
moon-seed guardian in a round hood."
The new icon close-ups only Warden's face, hood, empty hands, and chest
moonlight seed, and excludes gun, beacon stand, and letters.

No generation model was used. `tools/build_app_icon_assets.py` makes the
following production files together from locked integer coordinates and
palette on a 108×108 logical grid.

```text
Godot · iOS             apps/game/icon.svg
docs                    favicon.svg, logo.svg
Android legacy          app_icon_main.png 192×192 opaque
Android adaptive fg     app_icon_foreground.png 432×432 graded alpha
Android adaptive bg     app_icon_background.png 432×432 opaque
review copies           builds/art-review/a4-ui/app-icon-preview.png
```

The three SVGs are byte-identical, and Android / Android Play presets all
point at the three PNGs in `assets/custom/ui/`. Previous hand-derived PNGs
and import sidecars in `assets/derived/logo/` had no consumer and were
deleted.

Adaptive foreground computes all four-corner distances of every visible
pixel. The official guaranteed area of a 108dp layer is 66dp diameter, so
the 432px production file's pass radius was locked at `132px`. Current
outermost is `128.25px`. Review copies do not put a loose mask on the whole
layer; they first crop the real 72dp viewport at center radius `144px`,
enlarge, then apply circle/squircle/rounded-square masks. All three masks
keep the center silhouette of face, hands, and seed.

`check:assets` added generator `--check` so production files, SVG sync,
both Android preset paths, Godot/docs refs, and the safe-circle contract
fail if later changes drift.

### 23. Three-hero 2-head-tall redesign

Existing free player sheets and production heroes were compared on real
alpha bounds. Ninja Adventure players are 14–16px per frame; Warden·
Dancer·Keeper were 30–31px and almost filled the cell. Play feedback that
they read as 3-head-tall penguins more than small guardians, especially
from long torsos and hanging arms, was also confirmed in numbers.

The 24×32 sheet, direction, and frame contract were kept; only the drawing
was remade as follows.

```text
Warden silhouette     22–23px, max width 16px
Moon Dancer           22–23px, max width 17px
Ember Keeper          23–24px, max width 18px
head vs body/feet     max 2px
foot bottom           every facing/frame y=31
detail view           24×24 crop from y=8, Nearest 4x
moonlight-fire origin Player-local (0, -10)
```

Head and face were kept; coat/skirt/legs were shortened. Hands attach to
the moonlight seed, open crescents, or lantern-heart in front of the body,
and Keeper's long wide egg-shaped coat became a short quilted torso.
`build_warden_assets.py` shared body checks inspect 64 hero frames'
height, width, opaque area, head/body balance, and foot plant; the
companion generator calls the same checks.

Combat keeps the small size, but so pre-purchase detail is not too small
and bottom-heavy, each Hero has `preview_crop=Rect2i(0, 8, 24, 24)`.
Shrine and IAP hero bundle play the same four frames at 96×96; view does
not change Vault/IAP entitlements.
No test-only hero unlock was added. TestFlight confirms the real lock,
purchase, and equip flow with Apple Sandbox transactions.

### 24. Remaining free visual assets removed

A 2026-08-02 independent audit found characters, enemies, and Guardians
had already changed, but terrain atlases, beacon, hearts, and shared panel
still directly referenced Ninja Adventure PNGs, and title floor, clearing,
and mist were derivatives of those tiles — a regression. Scene, Node,
AtlasTexture region, collision, and game rules were not touched; they were
replaced on the following production paths.

```text
build_world_assets.py
  nature 384×336       forest_floor 256×256
  floor 352×417        field 80×240        camp 368×144
  raylight 216×102     night_mist 1024×420 clearing 288×160
  spark 70×8           flame 96×12         smoke 192×32
  heart 80×16

build_custom_ui_panels.py
  panel_moonlit 16×16, margin 5
  nine_path_panel_moonlit 16×16, margin 6
  button normal/hover/pressed/disabled/focus 16×16, margin 5

build_gate_projectile_assets.py
  moon_gate 34×52
  moon_arrow 128×32, 32×32 4 frames
  hostile_moon_bolt 40×40
```

Existing coordinates were preserved so only atlas pixels change and
placement/animation/hit regression risk is closed. All final PNGs are
generated deterministically with limited palettes and integer coordinates;
generated concept boards were color/density/silhouette references only.
A real OpenGL title render confirmed new evergreens, floor, moonstone
clearing, beacon flame, and navy panels; `game:check`, full game
regression, terrain 161, and custom-asset contracts passed.

`check_custom_assets.py` now inspects active Ninja Adventure PNGs and old
title-derived PNGs in `resources` · `scenes` · `scripts`. If any reconnect,
`check:assets` fails. Music, SFX, and lesson-compat archives are separate
from this visual-regression check.

A further audit found the moonlight gate still used an old derived PNG,
Moon Arrow the old shared slash, enemy moon bolts the charge UI ring, and
static buttons one panel for every state. Existing size, hframes, scale,
modulate, and scene structure were kept; three dedicated images were wired,
and 35 static buttons got 5 StyleBox states.
The custom-asset contract is `final 67 / planned 0`, and each generator's
`--check` plus forbidden-path fail fixtures are included in full
`check:assets`.

### 25. godot-iap 3.0.1 supply-chain verification

Android AAR and iOS GodotIap/SwiftGodotRuntime frameworks were replaced
with godot-iap 3.0.1, and the app's typed request, pending purchase,
restore, and revoke/refund-reclaim contracts were re-verified. iOS
`.gdextension.ios` is an iOS-only variant of the official descriptor with
macOS declarations removed, so the README does not call it original; it
records the variant process and both SHAs separately.

`godot-iap-vendor.test.mjs` compares `plugin.cfg` 3.0.1, both Android AARs,
the iOS descriptor, and both frameworks' SHA-256 against the README and
locked expected values together. Changing only docs or only binaries fails
whole verification. Existing iOS archives are 1.0.0 development-signed and
must not be submitted; after final source merge, a new 1.0.1(3) App Store
archive is made and embedded frameworks, version, and distribution signing
are reconfirmed.

### 26. Result-screen and purchase-complete regressions blocked from real play

On 2026-08-02 the Android emulator was played without moving and reached
the result screen in about 36s. That also confirmed on real runtime that
the previous loop of infinitely stacking heal hearts had ended. The same
pass found a visual regression of long multilingual titles overlapping
score rows; title, stats, rank, objectives, and button regions were
re-laid. `test_result_layout.gd` puts large scores and long copy into
Korean, English, Japanese, Simplified Chinese, and Traditional Chinese and
checks 60 layout conditions. The fixed APK was reinstalled and played
through death and the result screen; every item read separately.

Independent payment review found a path where a leftover Google Play
purchase `finish()` failing synchronously after relaunch could leave the
processing lock and wrongly return the shop to READY.
In that case an unapproved purchase could be refunded, so the processing
lock is released immediately on failure, pending finish is kept, and
connect/restore flow ends with a `finish-failed` error.
New regression tests reproduce restart, synchronous complete-fail,
maintenance-retry fail, and final success in sequence, and 757 IAP checks
passed.

After this change, full `pnpm verify` was run again. Android/iOS release
contracts, IAPKit, godot-iap 3.0.1 supply chain, 5 languages, 6 heroes,
combat/terrain/score table/result screen, `final 67 / planned 0` custom
assets, and docs build all passed. Existing AAB/IPA and store screenshots
are older than this final source, so they are not submitted; after source
freeze, 1.0.1(3) products and phone/tablet evidence are newly made.

Final multilingual-UI independent review checked 50 real 808×360 renders
of 10 main screens × 5 languages and 1,800 region/glyph conditions. That
found a P2: after shared-button StyleBox min height grew, the credits back
button's bottom was clipped by 3.5px. Title, intro, role, name, and
buttons were moved up 8px together keeping region spacing, and credits
regression was strengthened to 25 conditions including 5 languages, an
extra supporter row, and 4px screen-safe spacing. Fixed renders and 25/25
checks no longer clip; full `pnpm verify` passed again after that.

### 27. Store-capture regression cause removed and final recapture

The cause of final source and store images diverging was traced into the
capture pipeline. The first automation used PNG size, fixed waits, and
screen coordinates as success conditions. After that run reported 37 shots
complete, independent visual audit found these false positives.

- Simplified Chinese Guardian scene was beacon 1/3 and an escape gate;
  Traditional Chinese was a beacon 2/3 region transition.
- All five languages' shrine list and hero detail were essentially the
  same screen.
- Eclipse IAP review card was almost clipped; the target card was not
  fully visible.
- Hashes of 157 new sources, 90 existing Play-upload copies, and 67 App
  Store manifest inputs all differed.

So that first result was not submitted and was voided. Instead of
coordinates/size, a nonce handshake was made where the debug game publishes
the current scene's meaning as JSON. A different 256-bit nonce is issued
before and after each capture, and the image is kept in memory only when
all of the following are true.

```text
arena_ready       current scene arena, player/HUD ready, combat not over
shrine            shrine shown, 6 hero cards exist, detail panel closed
hero_preview      exact Keeper resource, portrait and close button shown
field_guardian    beacons 3/3, transition/escape-gate ended, living on-screen boss and boss HUD
iap_review        exact product ID, full card, name, portrait/art, buy, restore shown
```

Guardian recapture actually caught a race where a slow frame consumed a
position-place request before beacon transition ended. Placement was fixed
to start from the frame a boss exists while the request is alive, putting
it on-screen, and pre-ready state is also recorded with the same nonce so
later failures immediately report the missing meaning condition. A case
where after a long restart the real title was up but only
`RenderingServer.frame_post_draw` await stalled was also caught. That was
replaced with proof that directly confirms current title UI and the
`v1.0.1` string four game-loop frames later.

The host side rechecks that meaning state matches on both sides of the
screenshot, foreground is the real app, and installed `base.apk` is
byte-identical to the capture APK. Automatic device selection allows only
the specified `Pixel_10` AVD and does not touch other projects' emulators.
Ignored Gradle template, manifest, and launcher produced by Android export
were also included in the capture input hash. This bound is locked with 33
normal/error counterexamples.

To avoid losing earlier successes on failure, five-language 6-packs and
IAP 7-packs are each stored as atomic partial proofs and merged last. All
six proofs share installed APK SHA-256
`e2c88058c89170651ebbdc2734062ef41d538020495a4e80dea4084dbe9a7fe9` and
runtime SHA-256
`df42e6f69e7e448035cfc30392e4d76560fbff495d801c2a20026a431554e220`.
Final `capture-report.json` proves 30 main scenes in Korean, English,
Japanese, Simplified Chinese, and Traditional Chinese plus 7 Korean IAP
shots, 37 sources total. After directly recomparing Simplified/Traditional
Guardians, five shrine/detail pairs, 7 products, and Eclipse, the following
were generated from these sources.

```text
Google Play phone            5 languages × 6 = 30, 1920×1080
Google Play 7-inch tablet    5 languages × 6 = 30, 1920×1080
Google Play 10-inch tablet   5 languages × 6 = 30, 2560×1440
App Store iPhone 6.5         5 languages × 6 = 30, 2778×1284
App Store iPad 13            5 languages × 6 = 30, 2732×2048
App Store IAP review         7, 2778×1284
total                        157
```

`store:screenshots` safely removes the old shared `ko-KR/iap-review.png`
and generates only the 7 per-product shots. `check:store-screenshots`
passed count, size, RGB24 of all 157, that images are newer than current
capture evidence, input/output bounds, and tablet ratios.
Play 7/10-inch and App Store iPad 13 derivatives were also opened directly
to confirm HUD, boss, and shrine are not clipped. Previous-build screens,
other emulators, wrong panels, clipped product cards, or stale derivatives
now fail at verification.

### 2026-09-26 — docs site moves to painted launcher art

`apps/docs/static/img/favicon.svg` and `logo.svg` (old fixed-shape art)
are replaced by `favicon.png` (32×32) and `logo.png` (192×192) derived
deterministically from `app_icon_main.png` in
`tools/build_app_icon_assets.py`. Only `apps/game/icon.svg` still comes
from the 108×108 shape definition. Docusaurus config and the path
contract now pin the `.png` files.
