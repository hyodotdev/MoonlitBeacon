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
Source:         original (deterministic pixel production)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/world/terrain/
Used:           nature.png, forest_floor.png, floor.png, field.png, camp.png,
                forest_props.png, field_props.png, camp_props.png
Modification:   tools/build_world_assets.py builds original terrain that
                preserves existing atlas coordinates and canvas size;
                tools/build_terrain_obstacles.py generates structure sheets
                paired with Room's foot-based circular collision
```

`nature` · `floor` · `field` · `camp` only keep AtlasTexture coordinates
compatible; pixels were redrawn in an ink-navy, moon-teal, beacon-vermilion
palette. The first four cells of the first row of each `*_props` sheet are
real blocking structures;
the rest stay transparent for later 16px-grid expansion. Forest is birch,
standing stone, thorn brush, moonstone; field is wind standing-stone,
cairn, silver grass, observation ring; camp is palisade, crate, cart,
lantern stone. The same seed makes the same coordinates and variants, and
player, spirits, beacons, and loot all compute safe positions from the
same structure list.

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
Used:           arena BGM
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
Used:           guardian_theme.ogg is used as boss music.
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

## UI (moonlit hearts · moon-silver panels)

```text
Source:         original (deterministic pixel production)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/ui/
Used:           heart.png, panel_moonlit.png, nine_path_panel_moonlit.png,
                button_normal_moonlit.png, button_hover_moonlit.png,
                button_pressed_moonlit.png, button_disabled_moonlit.png,
                button_focus_moonlit.png
Modification:   tools/build_world_assets.py builds the 5-step moonlight heart;
                tools/build_custom_ui_panels.py generates ink-navy, moon-silver,
                teal, vermilion panels and button states that keep the existing
                5px and 6px nine-patch margins
```

| File | Size | Use |
| --- | --- | --- |
| `heart.png` | 80×16 | five 16px cells. empty heart (0) through full heart (4) |
| `panel_moonlit.png` | 16×16 | 9-patch moon-silver panel. 5px margin |
| `nine_path_panel_moonlit.png` | 16×16 | 9-patch for relic-pick cards. 6/6/6/6px margin |
| `button_normal_moonlit.png` | 16×16 | default button. ink-navy face and teal border |
| `button_hover_moonlit.png` | 16×16 | moon-white top face and bright teal border |
| `button_pressed_moonlit.png` | 16×16 | darkened face and lower vermilion rivets |
| `button_disabled_moonlit.png` | 16×16 | desaturated disabled state |
| `button_focus_moonlit.png` | 16×16 | transparent focus ring stacked on the default state |

The heart has 5 steps but **we only use the one full frame.** Empty slots
lower that one frame's opacity to 0.24. Swapping two pictures makes the
slot jitter a little.

9-patch sets `StyleBoxTexture` `texture_margin` to 5. On a 16px original
the stretchable center is only 6px, so use this panel at 12×12 or larger.

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

## Player (Moonlit Warden)

```text
Source:         original (AI-assisted concept, deterministic pixel production)
Creator:        Moonlit Beacon
License:        follows the project license
Original path:  _asset_sources/custom/a0-player/concepts/ (not distributed · gitignored)
Project path:   res://assets/custom/actors/heroes/warden/
Used:           walk.png = Warden 4-facing walk
                idle.png = Warden 4-facing idle
                portrait.png = Hero resource and ShrinePanel hero card
Modification:   the generation model's three concepts were used only for
                form comparison.
                after user feedback we revisited a cute beacon-candle
                guardian concept, and tools/build_warden_assets.py
                regenerated final RGBA PNGs at 1x with fixed integer
                coordinates and a 17-color visible palette
```

| File | Size | Layout | Playback |
| --- | --- | --- | --- |
| `walk.png` | 192×256 | 48×64 cells, columns=down·up·left·right, rows=4 frames | 9fps |
| `idle.png` | 192×256 | 48×64 cells, columns=4 facings, rows=4 frames | 4fps |
| `portrait.png` | 96×96 | single portrait | static |

All three files use binary alpha and lock a foot origin at the bottom
center of the cell. The 48×64 cell is kept for runtime compatibility,
but the actual Warden only uses 22–23px of height per frame.
Head and body-foot heights are each about 11px, a 2-head proportion:
round cyan-white hood, short cloak that narrows downward, a friendly
face, short violet bob, a small crescent pin, and empty both hands in
front holding a beacon candle. Side views show direction with a narrow
profile (full hood 12px · face 5px · cloak 9px or less), a small one-line
eye, and a reduced beacon candle in one hand. Front and back height and
foot origin stay, so changing facing does not suddenly change character
size.
After user feedback we removed the long torso, short moon blade, ember
bracers, and a face that only showed bright eyes, and we also did not
put horizontal protrusions that look like a muzzle or aiming arm.

Ranged arrows and missiles start from the beacon candle between both
hands at Player-local `(0, -10)`, and for `0.16s` after fire a cyan-white
casting ring and both-hand embers overlap. Homing-missile heads are a
small candle, diamond star-core, and short halo instead of fighter-style
wings.

Exact generation prompts and candidate-choice grounds are in
`docs/generation_prompts.md` at the repo root; runtime wiring and
device-verification notes are in `docs/work_log.md`.

---

## Player (five companion heroes)

```text
Source:         original (deterministic pixel production)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/actors/heroes/dancer/, res://assets/custom/actors/heroes/keeper/, res://assets/custom/actors/heroes/knight/, res://assets/custom/actors/heroes/eclipse/, res://assets/custom/actors/heroes/sage/
Used:           each hero's walk.png, idle.png, portrait.png
Modification:   tools/build_companion_hero_assets.py generates final RGBA
                PNGs at 1x with fixed integer coordinates and a per-hero
                limited palette
```

| Hero | Combat silhouette | Signature gear | Walk |
| --- | --- | --- | --- |
| Moon Dancer | lilac petal hood and short A-line body, small teal ribbon | open crescents around both hands | 10fps |
| Ember Keeper | round charcoal hood and short quilted coat | lantern heart held in both hands | 8fps |
| Silver Moon Knight | silver-white armor hood and short cloak | crescent shield and star shards | 8.5fps |
| Eclipse Mage | vivid red-black hood and split cloak | black eclipse core in front of the chest | 10fps |
| Constellation Sage | teal hood and gold constellation ornaments | gold star-core between both hands | 8fps |

For all five heroes, `walk.png` and `idle.png` are 192×256 with 48×64
cells in four columns down·up·left·right and four frame rows.
`portrait.png` is a 48×48 single portrait. Actual combat silhouettes are
22–24px tall per frame, with head vs body-foot height difference capped
at 2px. Foot origin matches Warden, but petals and ribbon, quilt lines
and lantern heart, silver armor, red-black eclipse, and teal
constellations plus color masses separate them.
All six hero resources and the Player safety fallback use custom sheets.
Shrine buy/select cards and the five individual-hero IAP cards press each
Hero's `48×48` portrait to open a full-body detail even before purchase.
The detail body shows the cell minus top padding as `24×24` Nearest 4×,
and looking does not change buy, unlock, or equip state.

---

## Enemies · bosses (Moonlit spirit bestiary)

```text
Source:         original (AI-assisted concept, deterministic pixel production)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/actors/spirits/, res://assets/custom/actors/guardians/
Used:           4-facing float motion for 7 normal enemies
                idle, wind-up, charge, recover motion for forest, field, and camp guardians
Modification:   generation-model concepts used only for material and silhouette comparison.
                tools/build_spirit_guardian_assets.py regenerated 18 final
                binary-alpha RGBA PNGs at 1x with integer coordinates and a
                limited palette; batch G re-cut all 22 guardian sheets to
                6-frame ChatGPT grid drops via tools/slice_gpt_grid.py
```

| Normal enemy | Silhouette that reads in combat | Behavior cue |
| --- | --- | --- |
| Wisp | crescent core and long smoke tail | default chase |
| Stalker | low four-legged body and backward spike horns | straight charge |
| Swarm | three moon-embers swapping places | weak and fast cluster |
| Ember | charcoal body and a large swaying flame crown | fast chase |
| Drifter | wide asymmetric moon-moth wings and a thin tail | high-inertia float |
| Weaver | broken orbit ring and four tentacles | orbit around the player |
| Caster | moon mask, long robe, and a forward staff | keep-distance fire |

Normal-enemy sheets are all `96×96` with `24×24` cells in four columns
down·up·left·right and four frame rows. They are not recolors. Asset
regression checks that all 7 alpha silhouettes and all 7 full-image
hashes differ.

| Guardian | Idle | State sheets | Combat silhouette |
| --- | --- | --- | --- |
| Forest | `forest.png` 6 frames | wind-up, charge, recover 6 frames each | horns, long tree-arms, roots in the ground |
| Forest Thorn | `forest_thorn.png` 6 frames | wind-up, charge, recover 6 frames each | thorn crown, deeper bark, heavier arms |
| Field | `field.png` 6 frames | cross wind-up, radial wind-up, recover 6 frames each | wide crescent wings, mask, cloud tentacles |
| Field Storm | `field_storm.png` 6 frames | cross wind-up, radial wind-up, recover 6 frames each | lightning veins, torn wings, crackling tips |
| Camp | `camp.png` 6 frames | wind-up, recover 6 frames each | brazier helm, hammer, gate shield |
| Camp Siege | `camp_siege.png` 6 frames | wind-up, recover 6 frames each | siege plates, siege hammer, cracked shield |

Guardian cells are `64×64`. Idle and state sheets are all `384×64`,
horizontal layout with no facing. Every `SpiritKind` state slot is filled
with a custom sheet so mid-states do not fall back to the old free boss
picture. State sheets were re-cut to 6 frames (batch G) because 4-frame
combat motion reads choppy; the runtime stretches each sheet over its
state duration, so frame count only changes smoothness.

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

## Dialogue-window letter sound

```text
Source:         original (deterministic synthesis)
Creator:        Moonlit Beacon
License:        follows the project license
Project path:   res://assets/custom/audio/sfx/
Used:           dialogue_blip.wav = the sound of letters printing in a visual-novel dialogue window
Modification:   n/a. apps/game/tools/build_dialogue_sfx.py bakes it
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
