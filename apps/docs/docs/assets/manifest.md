# Asset manifest

**Only files actually copied into the project** are recorded here.
This is not a full asset-pack listing. It is a source record of files
inside `res://assets/`.

Each entry follows this format as-is.

```text
## <use>
Source:         <asset pack name>
Creator:        <author>
License:        <license>
Original path:  <path inside the original pack>
Project path:   <res:// path>
Used:           <what is actually used>
Modification:   <rename / dropped frames / crop, etc.>
```

---

## Icon (project · iOS app icon)

```text
Source:         painted art generated and edited from an original character
Creator:        Moonlit Beacon · OpenAI image generation
License:        follows the project license
Project path:   res://assets/custom/ui/app_icon_master.png
Used:           Godot editor and window icon, iOS AppIcon generation source
Modification:   the approved 1254×1254 of the final Moonlit Warden holding
                a glowing beacon flame in both hands, scaled to 1024×1024,
                with Android background and figure separated
```

Generation and edit sources are kept in `notes/release/store-assets/source/`.
The approved art is `app-icon-approved.png`. Android splits are
`app-icon-night-crescent.png` and `app-icon-warden-moonlight.png`. Face,
gold crescent, and beacon flame are meant to read large. Type, weapons,
and platform rounded corners are not in the source.

## Icon (docs favicon · logo)

The docs site shows the painted launcher art: `static/img/logo.png` is
`app_icon_main.png` bytes and `static/img/favicon.png` its exact 6x
nearest decimation to 32×32, both written deterministically by
`tools/build_app_icon_assets.py`. The archive copy `apps/game/icon.svg`
still comes from the 108×108 fixed-shape definition. None of these are
used for the app launcher or store icon.

## Icon (Android launcher icon)

```text
Source:         original
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/ui/
Used:           app_icon_main.png (192, opaque legacy)
                app_icon_foreground.png (432, graded-alpha adaptive foreground)
                app_icon_background.png (432, opaque adaptive background)
                boot_splash.png (2048×1152, opaque splash)
Modification:   the new launcher icon uses the same Moonlit Warden · beacon
                flame composition as app_icon_master.png. Foreground is
                figure and flame only, fitted to a center-radius 132px
                safe circle; farthest visible pixel is 128.55px. Background
                is crescent and navy-violet night sky; main composites both
                and scales to 192. The splash keeps the existing 2048×1152
                production art. Size, alpha, and safe circle are contract-
                enforced.
                docs favicon.png · logo.png are derived from
                app_icon_main.png in tools/build_app_icon_assets.py —
                only the editor icon.svg still comes from the 108×108
                shape definition
```

:::note Where the art moved from pixels to a painting
Before 2.0.0 these files were drawn at fixed integer coordinates. The new
app icon is painted art so the character's face, crescent ornament, and
beacon flame still read together at 48–60px.

**The three vectors stayed.** Favicon and logo are used by the docs site
at mixed sizes, so coming from one definition deterministically is better.
That is why the docs favicon and the app icon have different looks —
intentional.
:::

:::warning Android still keeps separate foreground and background paths
An Android adaptive icon has the launcher apply a mask (circle, squircle,
and so on), and **only the center 66dp safe area is uncropped under any
OEM mask.** On the 432px production files that is diameter 264px, radius
132px. Center 72dp (radius 144px) is the actual mask viewport; the outer
18dp of the 108dp canvas is for parallax and masking.

If `launcher_icons/*` is empty in `export_presets.cfg`, Godot can use
`icon.svg` as the foreground as-is. Then the opaque background is merged
into the foreground layer and adaptive mask and parallax break. Both the
Android and Android Play presets name the custom foreground and background
above, and the generator's `--check` inspects both preset paths and the
safe circle together.
:::

---

## Fonts (UI body / titles)

```text
Source:         Nexon MapleStory Font
Creator:        Nexon Korea Co., Ltd.
License:        free use (commercial use allowed, embedding allowed, sale and modification forbidden)
Original path:  Maplestory Light.ttf, Maplestory Bold.ttf
Project path:   res://assets/third_party/fonts/MaplestoryLight.ttf
                res://assets/third_party/fonts/MaplestoryBold.ttf
Used:           Light = body, Bold = titles/buttons
Modification:   none. distribution as-is (spaces stripped from filenames only)
Download:       https://maplestory.nexon.com/Media/Font
```

The license **forbids modifying or editing**, so we do not touch the font
files themselves. We no longer use the old synthetic bold that thickened
Noto with `variation_embolden` — MapleStory ships Bold separately, so we
layer the real Bold.

The two `.tres` files **keep the old filenames** —
`res://assets/third_party/fonts/Galmuri11-Multilingual.tres` and
`res://assets/third_party/fonts/Galmuri11-Bold-Multilingual.tres`.
The original Galmuri `.ttf` files are no longer used, so they were
removed from the repo. About 40 scenes reference these paths; renaming
would mean fixing every reference, and all you gain is a name. Only the
face they point at inside changed.

### Font file list

Every font resource the game actually loads.

The manifest checker only reads `Project path:` lines. Declaring the
whole fonts folder in one line means new files are not missed.

```text
Project path:   res://assets/third_party/fonts/
```

| File | What |
| --- | --- |
| `MaplestoryLight.ttf` | body face · (c) NEXON Korea |
| `MaplestoryBold.ttf` | title and button face · (c) NEXON Korea |
| `NotoSansCJKsc-Regular.otf` | Japanese, Chinese, and player-name fallback · SIL OFL 1.1 |
| `Galmuri11-Multilingual.tres` | body = MapleStory Light + CJK fallback (old name kept) |
| `Galmuri11-Bold-Multilingual.tres` | titles and buttons = MapleStory Bold + CJK fallback |
| `NotoSansCJKsc-SyntheticBold.tres` | CJK bold fallback (Noto synthetic bold) |
| `GoogleSans[GRAD,opsz,wght].ttf` | Google door title face, used at weight 500 · SIL OFL 1.1 |
| `OFL.txt` | license text accompanying the Google Sans face |

### Why we left the pixel font

Galmuri11 is an 11px-grid font, so it is **sharp only at multiples of
11.** UI used non-multiple sizes at 53 places, including 9, 10, 12, 13,
14, 15, 16, and those glyphs were all resampled and mushy. Matching every
size to a multiple would mean redoing layout per panel.

The 2026-08 graphics renewal moved characters and spirits to soft cell
shading, and the pixel font started to clash with the paintings too. An
outline font does not care about size, so the 53 places stay and get sharp.

Import settings:

| Item | Value | Why |
| --- | --- | --- |
| `antialiasing` | 1 (grayscale) | outline fonts are easier to read with the stairs removed |
| `subpixel_positioning` | 0 (disabled) | half-pixel placement jitters glyphs at low resolution (808×360) |

### CJK fallback

```text
Source:         Noto Sans CJK SC
Creator:        Google, Adobe and Noto CJK contributors
License:        SIL Open Font License 1.1
Original path:  Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf
Project path:   res://assets/third_party/fonts/NotoSansCJKsc-Regular.otf
Used:           Japanese, simplified, and traditional glyphs Galmuri lacks, plus ladder player names
Modification:   none. original SHA-256 2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b
```

We include one original OTF from the official `notofonts/noto-cjk` repo
as-is. A partial subset is small when you only display fixed translations,
but it cannot guarantee Korean, Chinese, and Japanese characters a player
types on the ladder, so we do not use one. Bold UI shows the same original
with synthetic bold from
`res://assets/third_party/fonts/NotoSansCJKsc-SyntheticBold.tres`
(Noto is OFL so synthetic bold is allowed — MapleStory uses the Bold
original).
`res://assets/third_party/fonts/MaplestoryBold.ttf` owns Korean and English
bold faces; this fallback only fills Japanese and Chinese bold glyphs.
The license text is kept as `apps/game/docs/licenses/NOTO-OFL-1.1.txt`.

MapleStory's system fallback is off, so Noto is always hit first. The
Noto original draws Korean, Chinese, and Japanese UI and player names
directly; OS fallback after Noto is allowed only for emoji or extra
characters a player can type. Fixed UI glyph checks do not count system
fallback; they only check `has_char()` on Galmuri and the Noto original.

The original's GSUB/GPOS `hani` script has `JAN`, `ZHS`, and `ZHT`
language systems. We also confirmed that shaping `骨直返令` with HarfBuzz
picks different regional glyph IDs for `ja`, `zh-cn`, and `zh-tw`. The
game passes the `TranslationServer` locale as each Control's language, so
even one SC original uses `locl` substitutions for Japanese and Taiwan
forms.

---

## Player (Ninja Green)

```text
Source:         Ninja Adventure Asset Pack
Creator:        Pixel-Boy and AAA
License:        CC0
Original path:  Actor/CharacterAnimated/NinjaGreen/Separate/
Project path:   res://assets/third_party/ninja_adventure/actors/player/
Used:           currently unused at runtime. kept to compare with pre-course versions
Modification:   filenames changed to lowercase snake_case. pixels untouched
```

The current six heroes all use the dedicated custom sheets below.
These five frames remain to compare frame specs with earlier lessons.
`Attack` / `Jump` / `Swim` / `Climb` / `Push` / `Item` / `Pickup` in the
same folder were not copied.

The frame spec is a **32x32 cell**. A 16x16 character sits in the middle
of the cell.
The whole pack is unified at 32x32 so it matches sheets whose attack
effects leave the cell.

| File | Image size | hframes x vframes | Frames per facing |
| --- | --- | --- | --- |
| `idle.png` | 128x128 | 4 x 4 | 4 |
| `walk.png` | 128x128 | 4 x 4 | 4 |
| `roll.png` | 128x96 | 4 x 3 | 3 |
| `hit.png` | 128x64 | 4 x 2 | 2 |
| `dead.png` | 32x64 | 1 x 2 | 2 (no facing) |

**Columns are facing, rows are animation frames.** In
`Sprite2D.frame_coords` that is `frame_coords.x` = facing,
`frame_coords.y` = frame number.

| Column (x) | Facing |
| --- | --- |
| 0 | Down |
| 1 | Up |
| 2 | Left |
| 3 | Right |

---

## Tileset (night-forest arena)

```text
Source:         Ninja Adventure Asset Pack
Creator:        Pixel-Boy and AAA
License:        CC0
Original path:  Backgrounds/Tilesets/
Project path:   res://assets/third_party/ninja_adventure/tilesets/
Used:           tileset_nature.png, tileset_field.png, tileset_floor.png, tileset_camp.png
Modification:   filenames changed to lowercase snake_case
```

Tile size is 16x16.

| File | Image size | 16px grid | Tile count | Use |
| --- | --- | --- | --- | --- |
| `tileset_nature.png` | 384x336 | 24 x 21 | 504 | trees, brush, rocks |
| `tileset_field.png` | 80x240 | 5 x 15 | 75 | grass, flowers, floor decoration |
| `tileset_floor.png` | 352x417 | 22 x 26 | 572 | dirt/grass floor |
| `tileset_camp.png` | 368x144 | 23 x 9 | 207 | camp props. beacon hearth |

Only `tileset_floor.png` is 417px tall, not a multiple of 16. The last
1px row is leftover margin, so a TileSet uses 26 rows only.

A tile boundary is not a sprite boundary. Large objects span several
tiles with no empty cell between, so without looking you crop the
neighboring tree. `region_rect` values actually used on the title screen
are below. (units: px, relative to `tileset_nature.png`)

| Name | region_rect | Notes |
| --- | --- | --- |
| Round tree | `0,0,32,32` / `256,0,32,32` / `288,0,32,32` | 32x32 broadleaf |
| Conifer | `32,0,32,32` | 32x32. night-forest mainstay |
| Dead tree | `64,0,32,32` | 32x32. cursed-forest mood |
| Root tree | `96,0,32,32` | 32x32 |
| Large conifer | `0,32,48,48` | 48x48 |
| Large broadleaf | `64,32,48,48` / `256,32,48,48` / `320,32,48,48` | 48x48 |
| Tall dead tree | `0,80,32,48` / `32,80,32,48` | 32x48 |
| Small tree | `96,128,32,32` | 32x32 |
| Stump | `0,128,32,32` | 32x32 |
| Rock | `208,128,32,32` (brown) / `256,128,32,32` (gray) | 32x32 |
| Brush, grass, fern | `0..176,160,16,16` | row 10 is brush and grass |
| Pebbles | `240,144,16,16` / `288,144,16,16` | 16x16 |

The beacon hearth in `tileset_camp.png` is `192,80,32,30`.
Grab 32x32 and 1px of the neighboring tile comes in at the bottom.

---

## Combat terrain structures (Night Forest · Moonlit Field · Abandoned Camp)

```text
Source:         original painted masters (built-in image generation, 4.0.0),
                packed deterministically
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/world/terrain/
Used:           nature.png, field_nature.png, camp_nature.png,
                forest_floor.png, ground_field.png, ground_camp.png,
                field.png, camp.png, floor.png,
                forest_props.png, field_props.png, camp_props.png
Modification:   tools/pack_painted_world.py packs the biome atlases into 3x
                runtime sheets (--check keeps them current; source mapping in
                notes/plans/4-0-0-art-build-log.md). World rects are unchanged:
                Room scales regions by RoomKind.art_zoom and draws at 1/3 with
                a smooth filter, so pivots, feet and collision never move.
                floor.png stays with tools/build_world_assets.py
```

Floors are seamless painted `512×512` panels that repeat across the
1720x1000 play area; the pack check fails on any visible edge step. Scatter
sheets are `1152×1008` (`Room.KIND` world rects times three): the shared
`nature.png` plus one sheet per place, with every tree above sheet row 384
and rocks, logs and stumps below it so the sway shader only moves crowns.
Prop sheets keep their logical coords times three — `field.png` `240×720`,
`camp.png` `1104×432` — including the beacon-hearth canvas at world
`192,80,32,30`. Each `*_props` sheet holds four `192×192` blocking
structures with feet at world y=50; collision still comes from
`Room.OBSTACLE_RADII`, never from the art. Forest is birch, standing stone,
thorn brush, moonstone; field is wind standing-stone, cairn, silver grass,
observation ring; camp is palisade, crate, cart, lantern stone. The same
seed makes the same coordinates and variants, and player, spirits, beacons,
and loot all compute safe positions from the same structure list.

---

## Later terrain (Frost Pass · Mirewood Marsh · Moonlit Ruins)

```text
Source:         original painted masters (built-in image generation, 4.0.0),
                packed deterministically
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/world/terrain/
Used:           frost_props.png, marsh_props.png, ruins_props.png,
                ground_frost.png, ground_marsh.png, ground_ruins.png,
                frost_nature.png, marsh_nature.png, ruins_nature.png
Modification:   tools/pack_painted_world.py packs the biome atlases into 3x
                runtime sheets (--check keeps them current; source mapping in
                notes/plans/4-0-0-art-build-log.md). World rects are unchanged:
                Room scales regions by RoomKind.art_zoom and draws at 1/3 with
                a smooth filter, so pivots, feet and collision never move
```

| Place | Floor | Trees and stones | The four structures |
| --- | --- | --- | --- |
| Frost Pass | windblown snow with all its streaks leaning one way, snow-capped pebbles, six ice glints | icy-blue pines with a near-white tip | ice-crystal cluster, scarfed snowman, snow-capped stone lantern with a warm glow, frozen log with icicles |
| Mirewood Marsh | dark bog water with moss banks, lily pads and broken ripples | olive and moss pines, bare willows, wet dark wood | glowing mushroom cluster, mossy log with reeds, wisp jar on a post, mossy frog statue |
| Moonlit Ruins | weathered flagstones in running bond, cracked, mossed at the joints | dusk-indigo growth and violet-grey rubble | broken pillar, moon altar, crumbling arch, glowing menhir |

Floors are seamless painted `512×512` panels; scatter sheets are `1152×1008`
per place. The four structures of each place keep the world shape `Room`
already reads: four `192×192` cells on one row, feet at world y=50, collision
from `Room.OBSTACLE_RADII`. Each drawing keeps its baked contact shadow, like
the structures it stands beside.

---

## Place memories (Lantern Hollow motifs + settlement window)

```text
Source:         original (deterministic pixel production)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/world/places/
Used:           motifs.png, window.png
Modification:   tools/build_place_motifs.py draws both sheets from integer
                coords and a fixed palette (--check keeps them current)
```

| Sheet | Size | Cells |
| --- | --- | --- |
| motifs.png | 192x64 | six 32x32 terrain columns (forest, field, camp, frost, marsh, ruins), dim row then lit row |
| window.png | 64x32 | two 32x32 cells, dim then lit |

The six motifs stand beside their beacon clearings: trail ribbons, wind
chimes, the camp kettle, a signal bell, a paper boat, a signal lens. The
window answers Nari's opening message on the result screen: lit on an
official win, dim on an early return, hidden on defeat.

---

## UI theme (Theme Wood)

```text
Source:         Ninja Adventure Asset Pack
Creator:        Pixel-Boy and AAA
License:        CC0
Original path:  Ui/Theme/Theme Wood/
Project path:   res://assets/third_party/ninja_adventure/ui/
Used:           panel_wood.png, nine_path_panel.png
                currently unused at runtime, kept only to compare theme specs
Modification:   copied flat, no folder hierarchy. ThemePreview.gif excluded
```

`ThemePreview.gif` is a preview document image and Godot cannot import it
as a texture.
The 12 unfinished themes under `Ui/Theme/Wip/` are not copied either.

The current screen does not reference Theme Wood. The table below is a
spec record for when the course-compatibility files are reused, not a
claim that they are used now.

These are margin values for stretching as 9-slice. They were taken at
the point where border decoration ends and pixels become fully uniform.
Smaller than this and the border mush when stretched; larger is still
safe.

| File | Size | left | top | right | bottom |
| --- | --- | --- | --- | --- | --- |
| `nine_path_bg.png`, `nine_path_bg_2.png` | 16x16 | 2 | 2 | 2 | 2 |
| `nine_path_panel*.png` | 16x16 | 6 | 6 | 6 | 6 |
| `nine_path_panel_interior.png` | 16x16 | 3 | 3 | 2 | 2 |
| `nine_path_focus.png` | 8x8 | 3 | 3 | 3 | 3 |
| `button_normal/hover/disabled.png` | 16x8 | 2 | 2 | 2 | 2 |
| `button_pressed.png` | 16x8 | 2 | 3 | 2 | 1 |
| `inventory_cell.png` | 16x16 | 3 | 3 | 1 | 1 |
| `slider_progress*.png` | 16x16 | 3 | 3 | 4 | 3 |
| `tab*.png` | 16x12 | 4 | 4 | 6 | 0 |

`nine_path_panel` family has a thick decorative border, so margin needs
to go to 6.
On a 16px original the stretchable center is only 4px, so use this panel
at 12x12 or larger.

`button_pressed` and `tab` families are asymmetric top to bottom. A
pressed button is a picture sunk 1px; tabs are open at the bottom so
bottom is 0. Lump them into symmetric values and the shape goes wrong.

---

## Music (title screen)

```text
Source:         Ninja Adventure Asset Pack
Creator:        Pixel-Boy and AAA
License:        CC0
Original path:  Audio/Musics/13 - Mystical.ogg
Project path:   res://assets/third_party/ninja_adventure/audio/music/title_theme.ogg
Used:           title-screen BGM
Modification:   renamed to title_theme.ogg. audio not re-encoded
```

Length 60.000s, 1.19MB, 44.1kHz stereo.

Grounds for comparing candidates:

| Track | Length | Spectral centroid | 4kHz+ | last 3s / body | Size | Call |
| --- | --- | --- | --- | --- | --- | --- |
| **13 - Mystical** | 60.0s | 531Hz | 0.1% | 1.05 | 1.16MB | **chosen** |
| 22 - Dream | 96.0s | 389Hz | 0.6% | 0.68 | 2.23MB | 96s is long for a title |
| 30 - Ruins | 48.0s | 356Hz | 0.3% | **0.37** | 1.11MB | fade-out at the end, cannot loop |
| 37 - Dark Forest | 153.6s | 176Hz | 0.2% | 0.77 | 4.31MB | 4.3MB, too much for a title |

Three reasons we picked `13 - Mystical`.

1. Length is exactly 60.000s. That means it was written to the bar, so
   the loop does not drift.
   `30 - Ruins` drops to 37% of the body in the last 3 seconds, a fade-out
   you cannot loop (last 8s −35.6dB, body −25.7dB).
2. Highs are only 0.1%. No cymbals or hi-hat, so it sounds low and warm.
   Spectral centroid itself is lower on `37 - Dark Forest`, but that
   track is 4.3MB, too much for a title.
3. The first 12 seconds sit quiet at −22.1dB then rise to the body
   (−15.4dB). You can use that as-is for entering the title, and the
   loop coming back also sounds like taking a breath.

Import default is `loop=false`, so we changed `.import` to `loop=true`.

---

## Music (arena)

```text
Source:         Ninja Adventure Asset Pack
Creator:        Pixel-Boy and AAA
License:        CC0
Original path:  Audio/Musics/27 - Chill.ogg
Project path:   res://assets/third_party/ninja_adventure/audio/music/arena_theme.ogg
Used:           formerly arena BGM; combat now runs the original arena_kinetic.wav loop.
                kept because course lessons reference this track
Modification:   renamed to arena_theme.ogg. audio not re-encoded
```

Length 48.000s, 1.11MB. **Measured again the same way as the title
track** to make the table below.

| Track | Length | Spectral centroid | 4kHz+ | last 3s / body | Size | Call |
| --- | --- | --- | --- | --- | --- | --- |
| **27 - Chill** | 48.0s | 579Hz | 0.4% | 0.72 | 1.11MB | **chosen** |
| 11 - Clearing | 69.1s | 570Hz | 0.0% | **0.36** | 1.32MB | fade-out at the end |
| 29 - Lament | 48.0s | 473Hz | 0.2% | **0.57** | 1.12MB | fade-out hint |
| 26 - Lost Village | 36.0s | 367Hz | 0.3% | 1.43 | 0.84MB | 36s makes the repeat obvious |
| 2 - The Cave | 44.0s | 356Hz | 1.1% | 0.82 | 0.85MB | see below |
| 16 - Melancholia | 40.0s | 682Hz | 1.7% | 0.79 | 0.93MB | most highs |
| 37 - Dark Forest | 153.6s | 176Hz | 0.2% | 0.77 | 4.31MB | 4.3MB, too much |
| 13 - Mystical | 60.0s | 531Hz | 0.1% | 1.05 | 1.16MB | already used on the title |

Filter order:

1. **Throw out broken loops first.** If the last 3 seconds drop below 70%
   of the body, splicing makes the sound die then pop back every time.
   `11 - Clearing` (0.36) and `29 - Lament` (0.57) leave here.
2. **Length and size.** 36s makes the repeat obvious; 153.6s 4.3MB is too
   much. `26 - Lost Village` and `37 - Dark Forest` leave.
3. Of the remaining three, pick **the one with the smallest swings.**
   Arena music has to sit under play, so a big wave is in the way.
   1-second-window RMS:

| Track | Coefficient of variation | loudest / quietest |
| --- | --- | --- |
| **27 - Chill** | **0.281** | **10.6dB** |
| 16 - Melancholia | 0.298 | 18.4dB |
| 2 - The Cave | 0.323 | 13.3dB |

:::note Picking by name is wrong
By name alone `11 - Clearing` looks like the answer. The stage we are
making is a forest clearing.
Measure it and **the last 3 seconds drop to 36% of the body, a fade-out.**
Loop it and the sound dies then pops back every time.
:::

:::warning Do not pick on spectral centroid alone
`2 - The Cave` is 356Hz, lower than `27 - Chill` (579Hz). Lower does
sink into the background, but that track also has **the most highs at
1.1% and large swings.**
Decide on one column and you miss that.
:::

Same as the title track, `.import` was changed to `loop=true`.
Default is `loop=false`.

:::info How we measured
Both tables use the same method. Decode to 44.1kHz mono, walk the whole
track with a 4096-sample Hann window at 50% overlap, compute each
window's power-spectrum centroid, and energy-weighted average.
Near-silent windows (under 1/10000 of max power) have a meaningless
centroid, so they were dropped.

**We once measured the two tables with different methods and wrote
"same criterion."** The same track `37 - Dark Forest` came out with
different values in the two tables and we were caught. We measured again.
:::

---

## Enemy (spirit)

```text
Source:         Ninja Adventure Asset Pack
Creator:        Pixel-Boy and AAA
License:        CC0
Original path:  Actor/Monster/Spirit/SpriteSheet.png
Project path:   res://assets/third_party/ninja_adventure/actor/spirit.png
Used:           currently unused at runtime. kept to compare pre-course versions and frame specs
Modification:   filename lowercased. pixels untouched
```

64×64, **columns = facing, rows = frames** (16px cells 4×4). Same layout
as the ninja sheet.

Early lessons picked `Spirit` over `Spirit2`. `Spirit2` is an orange flame
shape, so **it collides with the beacon.** In the night forest, orange is
the beacon's color.
`Spirit` is pale blue, so it matches the night tint and separates from
the beacon.
Current combat uses the seven original spirits below.

---

## Enemy (three spirit kinds + guardian)

```text
Source:         Ninja Adventure Asset Pack
Creator:        Pixel-Boy and AAA
License:        CC0
Original path:  Actor/Monster/Spirit2/SpriteSheet.png, Actor/Monster/BlueBat/SpriteSheet.png,
                Actor/Boss/GiantSpirit/Idle.png, Audio/Musics/17 - Fight.ogg
Project path:   res://assets/third_party/ninja_adventure/actor/, res://assets/third_party/ninja_adventure/audio/music/guardian_theme.ogg
Used:           guardian_theme.ogg was boss music; combat now runs the original
                guardian_assault.wav loop. kept because course lessons reference this track.
                spirit_ember.png, spirit_bat.png, guardian.png are currently unused at runtime
Modification:   filenames lowercased. audio not re-encoded
```

| File | Size | Cell | Layout |
| --- | --- | --- | --- |
| `spirit_ember.png` | 64×64 | 16 | columns=facing 4, rows=frames 4 |
| `spirit_bat.png` | 64×64 | 16 | columns=facing 4, rows=frames 4 |
| `guardian.png` | 250×50 | **50** | **columns=frames 5, no facing** |

Only the old guardian sheet had a different layout. No facing, so the
picture is the same from every side.
To absorb that spec difference, `SpiritKind` got separate `cell` ·
`facings` · `frames`, and the current original 64px guardians use the
same data structure.

`guardian_theme.ogg` is `17 - Fight`. Opposite of the arena track
(`27 - Chill`): big swings and fast — the ear has to know first that
this is the last stretch.
`loop=true` in `.import`.

---

## SFX (beacon ignite)

```text
Source:         Ninja Adventure Asset Pack
Creator:        Pixel-Boy and AAA
License:        CC0
Original path:  Audio/Sounds/Elemental/Fire2.wav
Project path:   res://assets/third_party/ninja_adventure/audio/sfx/beacon_ignite.ogg
Used:           the instant a beacon lights
Modification:   wav -> ogg (q4). 216KB -> 20KB
```

Of `Fire` (0.89s) · `Fire2` (1.25s) · `Fire3` (0.65s) we picked `Fire2`.
A beacon takes 0.45s to light (`Beacon.IGNITE_SECONDS`), so the sound
has to last longer than that and continue while the fire settles.
`Fire3` is too short and ends before it lights.

**The original is a 216KB wav.** No reason to put that in the APK, so we
changed it to ogg — 20KB.
Unlike music it is a short one-shot, so lowering quality does not show.

---

## UI (moonlit hearts · Moon Lantern kit)

```text
Source:         original (deterministic pixel production) · relic emblems drawn as
                ChatGPT grid drops
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/ui/
Used:           heart.png, kit/*.png (36 files), icons/*.png (22 relic emblems)
Modification:   tools/build_world_assets.py builds the 5-step moonlight heart;
                tools/build_ui_kit.py generates the whole nine-patch kit, the two
                beacon icons, the shared style resources under
                resources/ui/, and their asset-contract entries;
                the first sixteen icons/*.png are ChatGPT grid drops (batch 3 of the
                abandoned 2.5D re-art pass), cut into 48x48 cells on branch
                feat/guardian-presentation (closed PR #6); only these emblems
                were carried over, and the cutting tools were not.
                The nine skill emblems (lantern_familiar, moon_ward, comet_call,
                star_magnet, thorn_bloom, second_light, moon_burst, winter_bell,
                comet_trail) were drawn with ChatGPT's image generator on 2026-09-29,
                the first six as one 3 x 2 grid and the last three as one row, each
                shown the existing emblems for style, cut apart with
                tools/cut_lineup.py (tools/skill_icons/), and fitted to 48x48 by
                tools/build_skill_icons.py
```

3.0.0 replaced the old ink-navy, moon-silver panels and their teal-edged
buttons. Those were flat rectangles with cut corners, drawn a little
differently in every scene, and read as a prototype. The new kit is **one set
of chunky, rounded "sticker" nine-patches**: a cream border on deep indigo,
lantern-gold and lavender accents, and a berry for danger. Every button label
in the game was authored as light text on a dark box, so buttons keep a dark
face and say primary, secondary or danger with the colour of the rim.

| File | Size | Use |
| --- | --- | --- |
| `heart.png` | 80×16 | five 16px cells. empty heart (0) through full heart (4) |
| `kit/panel.png` | 24×24 | modal and large-surface frame. 8px margin |
| `kit/chip.png` · `chip_gold.png` | 16×16 | small readout pill and list row. 6px margin. gold marks the row to look at |
| `kit/button_<variant>_<state>.png` | 16×16 ×20 | `gold` · `lav` · `berry` · `ghost`, each in normal / hover / pressed / disabled / focus. 6px margin |
| `kit/card_<state>.png` | 32×32 ×5 | relic card frame. 12px margin |
| `kit/bar_back.png` · `bar_fill_<tone>.png` | 12×10 | progress track and fills (`mint` · `gold` · `berry` · `white`). `white` is tinted at runtime, as the boss bar is |
| `kit/banner.png` | 40×24 | title ribbon. 14px horizontal, 9px vertical margin |
| `kit/icon_beacon_on.png` · `icon_beacon_off.png` | 16×16 | the objective on the HUD: a lit and a cold brazier |
| `icons/<relic>.png` | 48×48 ×25 | one emblem per relic, named by relic id (sixteen at the start, nine skills that unlock as cycles pass) |

Every nine-patch keeps its stretched centre **one solid colour**, and every
stretched edge strip uniform along its axis, so a panel of any size never
shows a stripe or a seam. `tools/build_ui_kit.py` refuses to write a sheet that
breaks that rule, and it keeps each nine-patch's margin next to its art:
`--styles` writes the shared `resources/ui/**/*.tres` that scenes point at, and
`--sync-contract` rewrites the `ui.kit.*` entries in the asset contract.

Why textures and not rounded `StyleBoxFlat`: with `canvas_items` stretch a
`StyleBoxFlat` is tessellated at the device resolution, so its corners come out
smooth-vector next to pixel-art sprites. A `StyleBoxTexture` is scaled with
nearest filtering and stays chunky.

The heart has 5 steps but **we only use the one full frame.** Empty slots
lower that one frame's opacity to 0.24. Swapping two pictures makes the
slot jitter a little.

The relic emblems are 48px art. The relic picker shows them at 48; the HUD
strip shows them at 22 with a filtered downscale, because the project's
default nearest filter would drop every other pixel into noise at that ratio.

---

## UI (world kit · cut-bronze vector frames)

```text
Source:         original hand-authored SVG (no generator, no pack)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/ui/world/
Used:           34 .svg sources (22 nine-patch faces, 12 ornaments)
Modification:   edited directly as vector originals; tools/build_world_ui_kit.py
                validates sizes and determinism (--check) but generates no art
```

4.0.0 replaces the 3.x sticker kit on the production screens with **one set of
cut-corner bronze frames**: beveled octagon silhouettes, narrow polished rims,
a dark groove, deep-ink inset faces, etched moon diamonds at the bevels, and
three button roads — ember (primary), steel (quiet), coral (painful). Every
source keeps **4 texels per logical unit** (a 36-unit frame is 144px of vector
art) and every control samples it with an explicit Linear filter; the locked
global Nearest never touches this kit.

Godot 4.7 `StyleBoxTexture` passes its margins through as destination fixed
edges, so a 48px margin corner would draw 48 logical pixels wide. The kit is
therefore painted by four tiny classes — `WorldPanel`, `WorldFrame`,
`WorldButton`, `WorldLabel` — whose `_draw` maps source texels to logical
units explicitly through `WorldChrome.slices`: 48 → 12, 32 → 8, 56 → 14,
16 → 4. Native text, icons, focus, signals and hitboxes stay native; invisible
margin styles preserve the old kit's content margins, so no layout moves.

| File | Size | Use |
| --- | --- | --- |
| `frame_panel.svg` | 144×144 | modal frame. 48px src → 12u corners |
| `frame_chip.svg` · `frame_chip_lit.svg` | 80×80 ×2 | pills and list rows. 32px → 8u. lit marks owned/found |
| `frame_card.svg` · `card_focus.svg` | 176×176 ×2 | relic/hero card + focus halo. 56px → 14u |
| `btn_<ember·steel·coral>_<state>.svg` | 80×80 ×15 | three roads × normal/hover/pressed/disabled/focus. 32px → 8u |
| `bar_back.svg` · `bar_fill.svg` | 48×48 ×2 | progress slot + neutral-white fill the HUD tints. 16px → 4u |
| `bead_moon.svg` | 48×48 | divider bead and title flanks |
| `seal_win.svg` · `seal_lose.svg` | 256×256 ×2 | journey stamps: unbroken gold / broken ash + fallen ember |
| `crest_<motif>.svg` | 80×80 ×6 | header/tab glyphs: moon · beacon · relic · book · coin · gate |
| `dash_base.svg` · `dash_fill.svg` | 208 · 104 | dash dial ring + crescent bolt |
| `dais.svg` | 384×96 | hero stage ellipse |

Stretched edges carry only smooth axial gradients and full-width bands, so a
panel of any size stretches them without a seam; all ornament sits inside the
fixed corners. `test_run_choice_panel` proves the 48 → 12 / 32 → 8 mapping
and that labels, focus and hitboxes are unaffected.

---

## Objectives · projectiles (moonlight gate · Moon Disc · enemy moonshot)

```text
Source:         original (deterministic pixel production)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/world/gate/
Project path:   res://assets/custom/items/projectiles/
Used:           moonlight gate that opens when every beacon is lit, player Moon Disc, enemy moonshot
Modification:   tools/build_gate_projectile_assets.py generates with a limited
                palette and integer coordinates while preserving existing
                runtime cell size and frame consumption
```

The gate is a 34×52 single image: teal threshold and vermilion runes
between ink-navy stone pillars.
Moon Disc is a 128×32 sheet of four 32×32 frames; each rotation changes
crescent direction and star shards. Enemy moonshot is a 40×40 single
image with a magenta eclipse core and vermilion thorns so it separates
immediately from the cyan-white player attack.

The hand-generated gate picture from earlier lessons is not referenced
at runtime, but is kept for comparison.

```text
Source:         past original derivative
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/derived/objectives/moon_gate.png
Used:           currently unused at runtime, kept for course compatibility
Modification:   34×52 arch and vertical light pillar
```

---

## FX (moonlight slash)

```text
Source:         derived (generated)
License:        n/a (we made it)
Project path:   res://assets/derived/fx/moon_slash.png
Used:           crescent mark that appears when swinging the moonlight blade
Modification:   128x32 (four 32x32 cells). tools/build_slash.py bakes it
```

**Make only one frame facing right (+x) and rotate it in the game.** Draw
all four facings and you have four places to fix.

The fan angle must be **the same value** as `ATTACK_ARC` in `player.gd`.
If visible range and actual hit range differ you get "I clearly hit it
and it did not die."
So we do not draw by hand. Code bakes it — change the angle and the
picture follows.

---

## UI (filling ring)

```text
Source:         derived (generated)
License:        n/a (we made it)
Project path:   res://assets/derived/ui/charge_ring.png
Used:           ring that fills at your feet when you stand by a beacon
Modification:   40x40. ellipse ring squashed to 0.45 vertically
```

**Top-down, so a foot ring has to be flat.** Draw a true circle and it
looks stood in front of the character, not lying on the floor.

---

## UI (virtual stick)

```text
Source:         derived (generated)
License:        n/a (we made it)
Project path:   res://assets/derived/ui/
Used:           stick_base.png, stick_knob.png
Modification:   white circles with numpy alpha only. color is given in the scene with modulate
```

| File | Size | Shape |
| --- | --- | --- |
| `stick_base.png` | 48×48 | thin ring of diameter 46 (3px border) |
| `stick_knob.png` | 22×22 | slightly filled circle + border |

**Draw white only and give color in the scene.** Then a later dash stick
is the same picture with a different color. No reason to make two files.

---

## Player (six heroes)

```text
Source:         original painted masters (built-in image generation, 4.0.0),
                packed deterministically
Creator:        Moonlit Beacon
License:        follows the project license
Original path:  notes/workflow/muse/art/4-0-0/<hero>-turnaround.png,
                notes/workflow/muse/art/4-0-0/gait/<hero>-sidewalk-v2.png
                (side-walk donors, kept)
Project path:   res://assets/custom/actors/heroes/warden/, res://assets/custom/actors/heroes/dancer/, res://assets/custom/actors/heroes/keeper/, res://assets/custom/actors/heroes/knight/, res://assets/custom/actors/heroes/eclipse/, res://assets/custom/actors/heroes/sage/
Used:           each hero's walk.png, idle.png, portrait.png
Modification:   tools/pack_painted_world.py fits each turnaround's four true
                facings into 144×192 cells as graded-alpha RGBA (--check keeps
                them current; source mapping in
                notes/plans/4-0-0-art-build-log.md). Walk side columns instead
                come from the registered gait donors: the left column holds
                the donor's contact / recover / opposite-contact / recover
                stride at one scale with the torso registered, and the right
                column mirrors it exactly (crop and registration table in
                notes/workflow/muse/gait-131-implementation.md). Down/up walk
                columns fit all four frames at their row-0 scale, and every
                walk frame wears its fitted row-0 head pixel-fixed, so one
                face holds through motion. Idle columns rebuild the lower
                body into a supported standing pose from the walk parts while
                sharing the walk frame-0 head per facing. Hero.visual_scale
                (0.255) renders the legacy world body with a smooth filter
```

| Hero | Design |
| --- | --- |
| Moonlit Warden | violet hood with a crescent pin, a lit beacon candle held in front |
| Shadow Dancer | pink bob with a mint ribbon, crescent blades at both hands |
| Beacon Keeper | green hooded cloak, a glowing lantern held in front |
| Silver Moon Knight | silver helmet with a crescent crest, white cape, sword |
| Eclipse Mage | black hood with a red rim, a red orb held in front |
| Constellation Sage | teal star-hood, gold staff and two floating orbs |

| File | Size | Layout | Playback |
| --- | --- | --- | --- |
| `walk.png` | 576×768 | 144×192 cells, columns=down·up·left·right, rows=4 frames | 12fps |
| `idle.png` | 576×768 | 144×192 cells, columns=4 facings, rows=4 breath frames | 4fps |
| `portrait.png` | 96×96 | single full-body portrait | static |

All three files use graded alpha and put the feet on the bottom of the cell. A hero's
opaque painted body is about 28 world px tall at the existing 0.255 scale, drawn as
a shaded chibi with a big head and a bold silhouette, and every facing keeps that
height and foot origin, so turning does not change the size. The walk is four source
poses per facing with one fixed head per facing; the idle stands on both feet and
breathes with the torso band only, scaling vertically about the hips while the head
and planted feet stay fixed. Down and up keep their turnaround bodies; both
side columns derive from the one donor stride on the left with its exact
mirror on the right, so the same legs alternate on both sides and the same
character faces left or right.

Each hero also carries an attack rig under `rig/`: 80 torso and arm PNGs
cut deterministically from each hero's own first idle frame per facing, plus
the two Eclipse profile off-hand nubs, which are authored fixed templates
painted in colors sampled from that hero's near arm rather than literal
atlas cuts, and the joints in `rig.json`. `tools/pack_attack_rig.py` bakes
all 82 PNGs plus 6 JSON files (`--check` byte-verifies all 88 outputs), so
the articulated arm is the same painted character. A `0.16s` casting cue
still plays after each shot.

Shrine buy/select cards and the five individual-hero IAP cards press each Hero's `48×48`
icon, the `72×72` `preview_crop` of the idle sheet scaled smooth, to open a full-body
detail even before purchase. The detail shows the hero's `96×96` portrait 1:1, and
looking does not change buy, unlock, or equip state. All six hero resources and the
Player safety fallback use these custom sheets.

---

## Player (six held weapons)

```text
Source:         built-in image generation (one transparent 2×3 weapon atlas,
                1536×1024, right-facing, generous alpha padding), separated
                and packed deterministically
Creator:        Moonlit Beacon
License:        follows the project license
Original path:  notes/workflow/muse/art/4-0-0/painted-weapons.png (master, kept)
Project path:   res://assets/custom/items/weapons/
Used:           warden.png, dancer.png, keeper.png, knight.png, eclipse.png, sage.png
Modification:   tools/pack_painted_weapons.py separates the atlas by alpha
                components (the grid is approximate: two blades cross the
                middle column and the reaper curl crosses the row line),
                floors dust alpha, scrubs matte RGB, crops each core exactly,
                downscales to four texels per logical pixel, and expands a 4px
                transparent margin. No repainting: the tool never draws.
```

Author note: these are the original shaded equipment for the 4.0.0 painted
heroes — the bright primitive bars `WeaponRig` used to draw are gone, and the
seats were deliberately recalibrated from centered hand constants to painted
wrists, with each spawn agreeing with its new painted muzzle. Combat timing,
damage, range, and counts are unchanged. Each sheet holds
four texels per logical pixel and draws at quarter scale through per-item
Linear filtering, so the paint stays smooth at real device output. Guns align
by barrel axis so each painted tip lands exactly on its muzzle seat; melee
weapons align by grip with the blade following the aim. The existing Dancer
sheet supplies both fang daggers, and the runtime seats each fang on its own
grip in its own articulated hand. Calibration (tips, grips,
axis rows) is measured from the master alpha by the pack tool and frozen in
`WeaponRig` logical constants, guarded by `tests/test_painted_weapons.gd`.

Author note (attack motion): the painted arm chains from each hero's `rig/`
bake carry the weapon — no drawn glove. The Dancer always draws both fangs
from its existing sheet, each half seated on its own handle in its own hand.
No pack-tool input changed.

| Atlas cell | Runtime file | Size | Paint |
| --- | --- | --- | --- |
| row 1 left, Warden sword | `warden.png` | 68×20 | curved moon-silver blade, blue guard, navy grip |
| row 1 right, Dancer fangs | `dancer.png` | 60×36 | matched pair, parallel, violet guard accents |
| row 2 left, Keeper pistol | `keeper.png` | 60×36 | brass lantern pistol, bell barrel, glass chamber |
| row 2 right, Knight cannon | `knight.png` | 60×28 | stout ring cannon, circular aperture, blue accent |
| row 3 left, Eclipse reaper | `eclipse.png` | 68×32 | haft with silver crescent curling around the tip |
| row 3 right, Sage rifle | `sage.png` | 88×28 | slim needle rifle, star sight, teal stock |

---

## Enemies · bosses (Moonlit spirit bestiary)

```text
Source:         original painted masters (built-in image generation, 4.0.0),
                packed deterministically
Creator:        Moonlit Beacon
License:        follows the project license
Original path:  notes/workflow/muse/art/4-0-0/spirit-turnarounds.png,
                notes/workflow/muse/art/4-0-0/guardian-states.png
Project path:   res://assets/custom/actors/spirits/, res://assets/custom/actors/guardians/
Used:           4-facing float motion for 7 normal enemies
                idle, wind-up, charge, recover motion for all 12 guardians
Modification:   tools/pack_painted_world.py packs the turnaround atlases into
                3x runtime sheets as graded-alpha RGBA (--check keeps them
                current; source mapping in notes/plans/4-0-0-art-build-log.md).
                Every facing is true turnaround art. SpiritKind.visual_scale
                (1/3) renders the legacy world body with a smooth filter
```

| Normal enemy | Design | Behavior cue |
| --- | --- | --- |
| Wisp | cloud puff with a curl on top | default chase |
| Drifter | sleepy leaf moth with folded wings | high-inertia float |
| Ember | round flame spirit | fast chase |
| Caster | mushroom-cap mage with a lantern staff | keep-distance fire |
| Weaver | jellyfish trailing glowing threads | orbit around the player |
| Stalker | shy cat-bat with big ears | straight charge |
| Swarm | fluffy dandelion-puff pup | weak and fast cluster |

Normal-enemy sheets are all `576×576` with `144×144` cells in four columns
down·up·left·right and four frame rows. They are not recolors: each creature has its
own silhouette, and asset regression checks that all 7 alpha silhouettes and all 7
full-image hashes differ. Every column is a true turnaround view; the four frames
breathe feet-planted with a small bob.

| Guardian | Idle | State sheets | Design |
| --- | --- | --- | --- |
| Forest | `forest.png` 6 frames | wind-up, charge, recover 4 frames each | mossy golem with leaf wings and a glowing core; the thorn form is cracked with red veins and horned |
| Field | `field.png` 6 frames | cross wind-up, radial wind-up, recover 4 frames each | blue moth sprite with big wings holding a glowing orb; the storm form is purple with lightning wings |
| Camp | `camp.png` 6 frames | wind-up, recover 4 frames each | stone furnace golem with a lit hatch; the siege form is riveted iron with cannons on its flanks |
| Frost (owl) | `frost.png` 6 frames | wind-up, charge, recover 4 frames each | snowy owl with crystal crown and big blue wings holding an ice gem; the Rimecrown form has antlers of ice and icicle feathers |
| Marsh (toad) | `marsh.png` 6 frames | wind-up, charge, recover 4 frames each | round toad with a lily-pad hat holding a glowing orb; the Glowcap form wears a crown of glowing mushrooms and cattails |
| Ruins (sentinel) | `ruins.png` 6 frames | wind-up, recover 4 frames each | stone cat with a gold crescent on its brow and floating stones round it; the Halo form has a ring of stones and gold plating |

Guardian cells are `192×192`. Idle is `1152×192` (6 frames), state sheets
`768×192` (4 frames), horizontal layout with no facing. Variant forms keep
the base silhouette with restrained channel grades and shifted breathing so
they stay distinct. Every `SpiritKind` state slot is filled with a custom
sheet so mid-states do not fall back to the old free boss picture.

---

## Player VFX (dedicated moonlight slash)

```text
Source:         original (deterministic pixel production)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/items/fx/moon_slash.png
Used:           default slash and Full Moon front/back blades in player.tscn
Modification:   tools/build_moon_slash_asset.py generates four 48×48 frames.
                3,640 runtime states combining center 13px, hand-height
                pivot (0, -6), pixel four-corners, and upgrade scale
                independently were checked.
                default visible tip 28.023/34px, upgrade-combo min radius
                slack 0.323px, fan min slack 0.768°, fitting inside the
                actual hit
```

The sheet is `192×48`, four frames across; a right-facing picture is
rotated at runtime.
A small thick cyan-white S-ribbon curves the other way into a crescent
trail and fades as shard afterglow. Range, fan, and damage can upgrade
separately without crossing the screen, and alpha uses at most 5 steps
including transparent.

The existing `res://assets/derived/fx/moon_slash.png` remains for course
compatibility only.
Moon Arrow was also replaced with a dedicated
`assets/custom/items/projectiles/moon_arrow.png`, so player slash,
ranged Moon Disc, and enemy moonshot use different textures and
silhouettes.

---

## Combat loot (Moonfire core)

```text
Source:         original (deterministic pixel production)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/items/pickups/power_gem.png
Used:           spirit-kill missile upgrade, pop-out and reclaim core on hit
Modification:   tools/build_missile_core_asset.py generates four 24×24
                frames directly with fixed integer coordinates and a
                10-color palette
```

The sheet is `96×24`, four frames across. A small ember inside a
cyan-white octagon crystal and four clockwise vanes are separated so it
reads as a weapon part, not moon-embers or currency. Idle cores last
12 seconds; cores popped by a hit last 9.

---

## Player (ninja compatibility sheet)

```text
Source:         Ninja Adventure Asset Pack
Creator:        Pixel-Boy and AAA
License:        CC0
Original path:  Actor/Character/NinjaBlue/SeparateAnim/Walk.png, Idle.png
Project path:   res://assets/third_party/ninja_adventure/actor/
Used:           ninja_walk.png, ninja_idle.png
                currently unused at runtime. kept for course compatibility and frame-spec comparison
Modification:   filenames lowercased. pixels untouched
```

| File | Size | Layout | Use |
| --- | --- | --- | --- |
| `ninja_walk.png` | 64x64 | **columns = facing, rows = frames** (16px cells 4x4) | walk 4 facings × 4 frames |
| `ninja_idle.png` | 64x16 | columns = facing (16px cells 4x1) | idle 4 facings × 1 frame |

Column order is `down` · `up` · `left` · `right`. Confirmed by enlarging
the sprite sheet — column 0 shows the face, column 1 the back of the
head, columns 2 and 3 left and right profiles.

:::note Idle is only one frame
`Idle.png` has one frame per facing. Leave it and you get a fully frozen
picture.
`AnimationPlayer` lifts the sprite 1px and drops it so it looks like
breathing (1.8s period). Solved without making more frames.
:::

```text
Source:         derived (generated)
License:        n/a (we made it)
Project path:   res://assets/derived/player/shadow.png
Used:           shadow at the player's feet
Modification:   24x10 soft ellipse. numpy drew alpha only
```

The shadow has `light_mask = 0`. **Light hitting a shadow brightens it**,
so beside a beacon the shadow thins. A shadow is not something that
receives light. It is something that blocks light.

---

## FX (custom beacon flame / smoke / moonlight shafts)

```text
Source:         original (deterministic pixel production)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/world/beacon/
Project path:   res://assets/custom/world/atmosphere/
Used:           flame.png, spark.png, smoke.png, raylight.png
Modification:   tools/build_world_assets.py preserves existing frame and
                region specs and generates new RGBA sheets with a limited
                palette and fixed integer coordinates
```

The first three are frame sheets laid out horizontally.
`CanvasItemMaterial` `particles_animation` plays them once over a
particle lifetime.

| File | Design | Size | Frames | Frame size | Use |
| --- | --- | --- | --- | --- | --- |
| `flame.png` | vermilion wick and moon-white core | 96x12 | 8 | 12x12 | beacon flame body |
| `spark.png` | moon-white cross sparks | 70x8 | 7 | 10x8 | sparks, forest-spirit light |
| `smoke.png` | blue-gray stacked clouds | 192x32 | 6 | 32x32 | beacon smoke column |
| `raylight.png` | cyan-white shafts of different thickness | 216x102 | - | 72x102 x 3 | moonlight falling between canopies |

`flame.png` is drawn to shrink as frames advance. Lay that on particle
lifetime and you get a flame that rises then dies. `raylight.png` is not
an animation; three shafts of different thickness, so we crop one at a
time with `region_rect`.

Existing Ninja Adventure FX files are kept for course compatibility and
license records but are not referenced at runtime now.

```text
Source:         Ninja Adventure Asset Pack
Creator:        Pixel-Boy and AAA
License:        CC0
Project path:   res://assets/third_party/ninja_adventure/fx/
Used:           currently unused at runtime, kept for course compatibility and frame comparison
```

---

## Custom textures (title · beacon background)

```text
Source:         original (deterministic pixel production)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/world/terrain/forest_floor.png
                res://assets/custom/world/beacon/clearing.png
                res://assets/custom/world/atmosphere/night_mist.png
Used:           forest_floor.png, clearing.png, night_mist.png
Modification:   tools/build_world_assets.py generates with a fixed palette and integer coordinates
```

| File | Size | Source tile | How it was made |
| --- | --- | --- | --- |
| `forest_floor.png` | 256x256 | none | low-contrast moon-teal clusters on a tileable opaque floor |
| `clearing.png` | 288x160 | none | oval clearing with moonstone rim and beacon-vermilion traces |
| `night_mist.png` | 1024x420 | none (procedural) | low-frequency noise dithered to 4 alpha steps. tiles on a 1024px horizontal period |

The forest floor hides repeat seams with opaque low-contrast clusters;
the clearing keeps combat readability with a binary-alpha moonstone rim.
Only mist uses large four-step-alpha cloud masses so it does not cover
actors and projectiles while drifting slowly.

The floor is one `Sprite2D` with `region_rect` larger than the screen and
`texture_repeat = 2`. You do not need a node per tile, and you do not
need a `TileSet` resource.

`night_mist.png` tiles horizontally, so shifting position by exactly
1024px hides the loop point. We drift it that way over 48 seconds.

Existing CC0 derivatives also stay in the repo to reproduce the course-
era screen, but are not referenced at runtime.

```text
Source:         past derivative of Ninja Adventure Asset Pack tiles
Creator:        Pixel-Boy and AAA (original), Moonlit Beacon (layout)
License:        CC0
Project path:   res://assets/derived/title/
Used:           currently unused at runtime, kept for course compatibility
```

---

## UI SFX

```text
Source:         Kenney UI Audio
Creator:        Kenney
License:        CC0
Original path:  Audio/click1.ogg, Audio/rollover2.ogg
Project path:   res://assets/third_party/kenney/ui_audio/
Used:           ui_confirm.ogg = button confirm, ui_focus.ogg = focus move
Modification:   rename only. audio as-is
```

We picked two of 51. Length and pitch were spread so the two sounds do
not overlap.

| File | Original | Length | Fundamental | Role |
| --- | --- | --- | --- | --- |
| `ui_confirm.ogg` | click1.ogg | 0.091s | 88Hz | low and thick, so it reads as "decide" |
| `ui_focus.ogg` | rollover2.ogg | 0.054s | 1396Hz | short and high, so fast scrolling does not mush |

`rollover1.ogg` is 0.224s, long enough that fast menu scrolling overlaps
the sound. So we excluded it.

---

## Original combat music loops

```text
Source:         original (deterministic synthesis)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/audio/music/
Used:           arena_kinetic/ember/watch.wav = three night-motif arena loops;
                guardian_assault/hunt/storm.wav = three faster guardian loops
Modification:   n/a. apps/game/tools/build_combat_audio.py bakes them
```

Same rule as the dialogue blip below: bake, do not fetch. All six share
one A-minor lantern motif over driving drums and bass, so the guardian
escalation sounds like the same night turning dangerous. The arena draws one
of three tracks per region and each guardian entrance draws one of three
faster tracks; defeating the guardian returns to a fresh arena draw, and a
shuffled no-repeat bag tours each pool without restarting a track mid-fight.
Musically exact whole bars with short raised-cosine edge fades, so each loop
starts and ends at exact zero and the boundary cannot click.

| File | Length | Peak | Role |
| --- | --- | --- | --- |
| `arena_kinetic.wav` | 14.55s | 0.620 | kinetic arena ground, 132 BPM × 8, motif lead |
| `arena_ember.wav` | 15.24s | 0.620 | shuffling triplets, 126 BPM × 8, motif in thirds |
| `arena_watch.wav` | 13.91s | 0.620 | half-time watch, 138 BPM × 8, eighth-note arps |
| `guardian_assault.wav` | 17.14s | 0.620 | same motif doubling as the loop heats, 140 BPM × 10 |
| `guardian_hunt.wav` | 12.63s | 0.620 | four-on-the-floor pursuit, 152 BPM × 8, motif stabs |
| `guardian_storm.wav` | 15.00s | 0.620 | double-kick storm, 160 BPM × 10, racing 8ths |

## Dialogue-window letter sound

```text
Source:         original (deterministic synthesis)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/audio/sfx/
Used:           dialogue_blip.wav = the sound of letters printing in a visual-novel dialogue window;
                weapon_sword/twin/rifle/shotgun/cannon/scythe.wav = the six heroes' attack voices;
                impact_hit.wav = crisp contact knock; kill_pop.wav = kill tick;
                level_up.wav = growth surge; core_pickup.wav = core chime;
                overcharge_win.wav = overcharge triumph
Modification:   n/a. apps/game/tools/build_dialogue_sfx.py bakes the blip,
                apps/game/tools/build_combat_audio.py bakes the combat cues
```

We do not download it. We bake it. Pictures are all made with
`build_*_assets.py`; this sound follows the same rule, so the license-
notice set does not grow. 40ms · 1,808 bytes.

| Value | Why |
| --- | --- |
| 40ms | letter speed is 42 per second. longer than this overlaps the next sound and mushes |
| 1180Hz + 2nd harmonic | a pure tone is a grating "beep." add a harmonic and it is closer to a wooden xylophone |
| 2ms attack | a sudden start clicks |

`dialogue_scene.gd` plays once every three letters and wobbles pitch
±14% each play. The same sound on every character sounds like a machine
talking.

---

## Title (moon gate entry background)

```text
Source:         original title master approved for the 4.0.0 entry surface
Creator:        Moonlit Beacon
License:        follows the project license
Original path:  notes/workflow/muse/art/4-0-0/moon-gate-title.png
Project path:   res://assets/gate/moon_gate_title.png
Used:           full-screen background of the new moon gate entry surface
                (GateEntry); the shaded navy/teal/amber moon gate sits right,
                the traveler lower left, control space stays quiet left
Modification:   byte copy of the approved master, no repaint and no resize;
                runtime framing crops with TextureRect cover at 808x360,
                wide-phone and tablet viewports
```

Author note: the runtime file is the approved master copied byte for byte
(1672x941 RGB, about 2.5MB). Nothing here is generated or repainted, so a
later art refresh replaces one file and this row. The entry scene draws it
with a per-item linear filter while the project keeps its global nearest
filter, and all light, mist and dust above it are small procedural layers
so the painting stays the single art source on this screen.

---

## UI (moon gate entry frames · forecourt lineup — drawn from code)

```text
Source:         original (vector geometry drawn at runtime, no image files)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://scripts/ui/gate_frame_style.gd
                res://scripts/ui/gate_beacon_mark.gd
                res://scripts/ui/gate_hero_forecourt.gd
Used:           every button face, dialog card, ID field, progress bar and
                Hall row on the moon gate entry/account/Hall/conflict/exit/
                loading surfaces; the crescent-and-beacon title mark; the
                six-hero forecourt lineup behind the interaction layer
Modification:   none — these scripts are the editable source. No PNG, SVG or
                .tres was added for this look. The lineup reuses the shipped
                144x192 hero idle sheets and the six painted weapon sheets
                already recorded under the Player rows; no new hero,
                weapon or bitmap art was introduced.
```

Author note: the entry screen is the smooth-shaded surface — painting, hero
sheets and MapleStory type all render linear — so its frames are drawn as
smooth vector chamfers at runtime instead of chunky nine-patch pixels. That
keeps one look per surface: the pixel UI kit stays the in-game voice, these
frames stay the gate voice. `gate_frame_style.gd` also pins the entry
minimum-size rule (content margins only): any extra floor clamps the 420px
Hall card wider and off-center, and the layout suite guards that width.

Round 082 hardened both pieces. The lineup grounds on measured opaque
bounds (alpha >= 32): every down/left idle cell carries 110px of paint
tall (cell y 82..191, feet at the cell bottom), 57-82px wide depending on
hero and facing. Those numbers live as constants in
`gate_hero_forecourt.gd` and the state suite re-measures them from the
source sheets, so an art refresh fails loudly instead of drifting the
footing. The gate-mouth keep-clear rect is read off the committed master
(painting pixels 1140,220-1450,500) and mapped through aspect-cover
framing per viewport. The accent language is fixed: gold for the one
gate-entry action, mint for provider/guest passage, coral for destructive
choices, steel blue for navigation.

---

## UI (official Google sign-in tiles)

```text
Source:         Google Identity branding kit (gradient Super G tiles)
Creator:        Google LLC
License:        Google brand use as permitted by the sign-in branding
                guidelines; the mark itself is unmodified
Original path:  signin-assets.zip from
                https://developers.google.com/identity/branding-guidelines
                (kit updated 2026-07-07)
Project path:   res://assets/third_party/signin/
Used:           the Google door's mark on the moon gate entry chooser;
                the Android tile on Android/desktop, the iOS tile on iOS
Modification:   none to the bytes. SHA-256 android
                2bc2ae8e4c67de66d74bf1deed12cd8f22981270266a487576b671b0b4df361c
                ios
                085692d68716db0e621635128407cb0f0a8db058b1dbfebe3f57a2c9d625d145
                (donor record notes/workflow/muse/donors/official-signin-110/
                donor-sha256.json). Runtime draws an AtlasTexture crop of
                the measured 79x80 glyph alone (android x40-118 y40-119,
                iOS x48-126 y48-127); every colorful pixel is kept and no
                stroke, corner, or baked padding pixel reaches the button.
```

Author note: both tiles hold the same 79x80 gradient G with platform
padding baked in (40px Android, 48px iOS) on a white rounded tile with
the 1px #747775 stroke. An earlier ring-only crop kept the tiles'
rounded-corner stroke pixels and is not used: the button draws its own
spec face (white fill, inside 1px stroke) with the glyph alone at an
explicit 20px logical height and exact spec edge/gap padding, so no
tile edge can double-draw or leave corner dirt. Import keeps the pixels
lossless with mipmaps on, minified with a mipmapped linear filter. The
reference's older four-solid-color G was measured and not shipped.

---

## UI (official Apple sign-in artwork)

```text
Source:         Apple Design Resources, Logo Sign in with Apple
Creator:        Apple Inc.
License:        Apple Design Resources license EA1677, approved by the
                user before extraction; artwork unmodified
Original path:  Logo-Sign-in-with-Apple.dmg from
                https://developer.apple.com/design/resources/
Project path:   res://assets/third_party/signin/apple-left-white-medium.svg
Used:           the Apple door's mark on the moon gate entry chooser,
                drawn whole at button height on the black brand face
Modification:   none to the bytes. SHA-256
                f43d1ed5be59bcffdf4c20b5e29f8de041858678f549515377d0ba4f5ebd115e
                (donor record notes/workflow/muse/donors/official-signin-110/
                donor-sha256.json). Import rasterizes the 31x44 file at
                4x with mipmaps for the 3x device scale; the file's own
                padding is preserved and the glyph is never cropped out.
```

Author note: the shipped file is the padded medium white-on-black
artwork (31x44, glyph about 15x19), so its apparent size balances the
Google G at the shared 44px door height. The license RTF stays with
the donor record and is not shipped at runtime. The square logo-only
variant was kept as reference only and not shipped.

---

## Fonts (Google Sans for the Google door)

```text
Source:         Google Sans official font repo (ofl/googlesans)
Creator:        Google LLC
License:        SIL Open Font License 1.1
Original path:  GoogleSans[GRAD,opsz,wght].ttf + OFL.txt from
                https://github.com/google/fonts/tree/main/ofl/googlesans
Project path:   res://assets/third_party/fonts/GoogleSans[GRAD,opsz,wght].ttf
                res://assets/third_party/fonts/OFL.txt
Used:           Google door titles through a FontVariation at weight 500
                with the bundled Noto Sans CJK fallback for localized
                glyphs; no other surface uses this face
Modification:   none to the bytes. SHA-256 font
                d0a87d835a944b8b40d0e82a5651bb59ab97b936a2aeed5946eb57e7b2a3a90a
                license
                2b75ef20f13d83a7514aee452c4782c20cdc9ff2dee17600f44d37a06d4fb958
                (donor record notes/workflow/muse/donors/official-signin-110/
                donor-sha256.json)
```

Author note: the variable face keeps its original bracketed filename so
the shipped bytes map to the donor record with no renaming step.
