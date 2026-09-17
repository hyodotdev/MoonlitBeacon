# Moonlit Beacon visual-asset audit

> Baseline date: 2026-07-29
> Scope: `apps/game/assets/derived`, `apps/game/assets/third_party` real source files under
> Exclude: Godot-generated `*.import`, folder-keeping `.gitkeep`, planned contracts with no file yet
> Principle: This document is a status audit and does not change game rules, GDScript, or Scene/Node structure.

## 2026-08-02 completion update

The 83-row tables below preserve the pre-replacement baseline audit. Current production runtime uses
six heroes, 7 regular spirits, 3 region Guardians and state sheets, three-region atlases and collision structures,
beacon, mist, hearts, shared panel, and app branding as deterministic production files in `assets/custom`.
Active references to Ninja Adventure PNGs and the three title
derived PNGs in the game's `resources` · `scenes` · `scripts` are 0. BGM/SFX and lesson-compat archive files are outside visual replacement
scope and keep their license records.

The final production contract is `final 67 / planned 0`. The moonlight gate, shared Moon Arrow, and
charge-ring-reused enemy shots from the old tables were each replaced with dedicated custom images, and 35 static buttons
consume shared StyleBox resources for the five states normal, hover, pressed, disabled, and focus.
Remaining path and issue wording in the tables below is a baseline record for reproducing replacement decisions.

This 0-count contract is checked automatically by `check_custom_assets.py`. Each row's “current path” and
“needs replace” are 2026-07-29 discovery evidence; actual completion status prefers
`custom_asset_contracts.json`, `asset_replacement_plan.md`, and the runtime manifest
over this table.

## 1. Conclusion

Baseline assets total **83**; of those, live file references confirmed are **35**,
and unused archives are **48**. License risk is low, but on-screen identity depends heavily on the Ninja Adventure
Asset Pack.

| Group | Total | Referenced | Unused | Main source |
| --- | ---: | ---: | ---: | --- |
| Project-derived / original | 12 | 12 | 0 | original 9, Ninja CC0 derived 3 |
| Fonts | 2 | 2 | 0 | Galmuri, OFL 1.1 |
| Kenney UI audio | 2 | 2 | 0 | Kenney, CC0 |
| Ninja Adventure | 67 | 19 | 48 | Pixel-Boy and AAA, CC0 |
| **Total** | **83** | **35** | **48** |  |

Additional products in the current work tree are recorded separately in the custom-asset contract and
runtime manifest so they are not confused with the baseline 83.

### Current state of the P0 player replacement

| Asset ID | Current path | Current status | Actual wiring | Remaining issue |
| --- | --- | --- | --- | --- |
| `hero.warden.walk` | `res://assets/custom/actors/heroes/warden/walk.png` | `final`, 96×128, actual 2-head-tall 22–23px, 4 dir × 4 frames, 9fps | `resources/heroes/warden.tres` wired | none |
| `hero.warden.idle` | `res://assets/custom/actors/heroes/warden/idle.png` | `final`, 96×128, actual 2-head-tall 22px, 4 dir × 4 frames, 4fps | `resources/heroes/warden.tres` wired | none |
| `hero.warden.portrait` | `res://assets/custom/actors/heroes/warden/portrait.png` | `final`, 48×48 | `warden.tres`, wired to shrine cards and full-body detail | HUD shows the full-body hero directly so no extra portrait consumer |
| `hero.dancer.walk/idle` | `res://assets/custom/actors/heroes/dancer/` | `final`, 96×128 each, actual 2-head-tall 22–23px | `dancer.tres` wired, walk 10fps · idle 4fps | none |
| `hero.dancer.portrait` | `res://assets/custom/actors/heroes/dancer/portrait.png` | `final`, 48×48 | `dancer.tres`, wired to shrine, IAP bundle, and full-body detail | none |
| `hero.keeper.walk/idle` | `res://assets/custom/actors/heroes/keeper/` | `final`, 96×128 each, actual 2-head-tall 23–24px | `keeper.tres` wired, walk 8fps · idle 3.5fps | none |
| `hero.keeper.portrait` | `res://assets/custom/actors/heroes/keeper/portrait.png` | `final`, 48×48 | `keeper.tres`, wired to shrine, IAP bundle, and full-body detail | none |
| `hero.knight.*` | `res://assets/custom/actors/heroes/knight/` | `final`, 96×128 two files + 48×48 portrait | `knight.tres`, wired to shrine, individual IAP, and full-body detail | none |
| `hero.eclipse.*` | `res://assets/custom/actors/heroes/eclipse/` | `final`, 96×128 two files + 48×48 portrait | `eclipse.tres`, wired to shrine, individual IAP, and full-body detail | none |
| `hero.sage.*` | `res://assets/custom/actors/heroes/sage/` | `final`, 96×128 two files + 48×48 portrait | `sage.tres`, wired to shrine, individual IAP, and full-body detail | none |
| `fx.moon_slash` | `res://assets/custom/items/fx/moon_slash.png` | `final`, 192×48, 48×48 4 frames | wired to existing `Slash` texture in `player.tscn` | procedural extra afterimages have no code hook and stay |

So hero replacement is **done for all six by combat sprites and pre/post-purchase detail**.
Each uses a 2-head-tall sheet bottom-aligned in a different 24×32 cell, and the `player.tscn` safety
fallback is also the Warden custom sheet. Portraits are wired to shrine purchase/select cards and the IAP hero bundle
view buttons, and detail plays 24×24 excluding transparent padding at Nearest 4x.
The default slash is a dedicated sheet and no longer shares a texture with Moon Arrow.


## 2. Sources and licenses

| Tag | Source | Creator | License | Audit judgment |
| --- | --- | --- | --- | --- |
| `MB` | original-made or original-generated | Moonlit Beacon | project license | no external-rights risk |
| `NA-derived` | generated from Ninja Adventure tiles | Pixel-Boy and AAA + Moonlit Beacon | original CC0, derivatives project-managed | source record must be kept |
| `NA` | Ninja Adventure Asset Pack | Pixel-Boy and AAA | CC0 | legal risk low, visual-identity risk high |
| `KENNEY` | Kenney UI Audio | Kenney | CC0 | legal risk low |
| `GALMURI` | Galmuri | Lee Minseo | SIL OFL 1.1 | keep OFL text and font name |

Detailed original paths and conversion history use
`apps/docs/docs/assets/manifest.md` and `apps/game/docs/licenses/` as the source.

## 3. Full list of 83 baseline assets

Priorities:

- `P0`: directly damages first impression, core combat, or core-objective identity
- `P1`: large effect on repetition, information, or region/enemy differentiation
- `P2`: style unity, polish, audio identity
- `P3`: unused archives, cleanup, or long-term improvement

### 3.1 Project-derived / original 12

| Asset ID | Current path | Source/license | Used scenes/resources | Role | Issue | Needs replace | Priority | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `fx.moon_slash.legacy` | `res://assets/derived/fx/moon_slash.png` | MB | `moon_arrow.tscn` | Moon Arrow-compat core drawing, previous shared slash | player slash split is done but weak as the projectile's own silhouette | yes, dedicate to Moon Arrow | P1 | 128×32, 32×32 4 frames. Player uses the custom 48px sheet |
| `brand.launcher.background` | `res://assets/custom/ui/app_icon_background.png` | MB | `export_presets.cfg` | Android adaptive icon background | replaced with the same 4-color night sky as the Warden icon | no, done | P1 | 432×432, opaque |
| `brand.launcher.foreground` | `res://assets/custom/ui/app_icon_foreground.png` | MB | `export_presets.cfg` | Android adaptive icon foreground | replaced with round hood, face, and moonlight seed in both hands | no, done | P1 | 432×432, graded alpha, visible pixels inside radius 132px |
| `brand.launcher.main` | `res://assets/custom/ui/app_icon_main.png` | MB | `export_presets.cfg` | legacy Android launcher icon | replaced to match the new Warden production look | no, done | P1 | 192×192, opaque |
| `objective.moon_gate` | `res://assets/derived/objectives/moon_gate.png` | MB | `moon_gate.tscn` | region-transition gate | smooth multi-step alpha clashes with binary-alpha pixel characters | yes | P1 | 34×52, Sprite origin y=-26 |
| `actor.shared_shadow` | `res://assets/derived/player/shadow.png` | MB | `player.tscn`, `spirit.tscn` | shared player/enemy shadow | every body type uses the same soft ellipse; pixel-style mismatch | recommended | P2 | 24×10 |
| `objective.beacon_clearing` | `res://assets/derived/title/beacon_clearing.png` | NA-derived / CC0 | `beacon.tscn` | bright floor around the beacon | around the core objective it reads as a static 4-color ellipse | yes | P1 | 288×160 |
| `terrain.forest_floor` | `res://assets/derived/title/forest_floor.png` | NA-derived / CC0 | `night_forest.tscn`, `rooms/forest.tres` | title and forest-room repeating floor | 128px repeat reads easily and structural difference vs other regions is small | yes | P1 | 128×128, opaque 4-color |
| `title.night_mist` | `res://assets/derived/title/night_mist.png` | NA-derived / CC0 | `night_forest.tscn` | title mist | smooth alpha band is somewhat foreign to pixel outlines | recommended | P2 | 1024×420, 48s drift animation |
| `ui.charge_ring` | `res://assets/derived/ui/charge_ring.png` | MB | `charge_ring.tscn`, `moon_bolt.tscn`, `room.gd` | charge display, enemy shot, gate glow | a UI ring also serves as enemy shot and gate FX so meaning is ambiguous | yes, split by use | P1 | 40×40, vertical crop progress display |
| `ui.stick_base` | `res://assets/derived/ui/stick_base.png` | MB | `virtual_stick.tscn`, `dash_button.tscn` | mobile stick/dash outline | soft alpha circle mismatches pixel UI | recommended | P2 | 48×48 |
| `ui.stick_knob` | `res://assets/derived/ui/stick_knob.png` | MB | `virtual_stick.tscn`, `dash_button.tscn` | mobile stick/dash knob | same style issue as base | recommended | P2 | 22×22 |

Subtotal: **12, referenced 12 / unused 0**

### 3.2 Fonts and Kenney UI audio 4

| Asset ID | Current path | Source/license | Used scenes/resources | Role | Issue | Needs replace | Priority | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `font.galmuri.regular` | `res://assets/third_party/fonts/Galmuri11.ttf` | GALMURI / OFL 1.1 | title, shrine, IAP, and dynamic body | Korean pixel body type | the mix of non-multiple sizes 9–55px is the issue more than the font itself | no, tidy size rules | P2 | AA, hinting, subpixel off |
| `font.galmuri.bold` | `res://assets/third_party/fonts/Galmuri11-Bold.ttf` | GALMURI / OFL 1.1 | essentially all UI including compass | titles, buttons, HUD | no global Theme; per-scene overrides duplicate | no, recommend unifying Theme | P2 | Galmuri11 should use 11px multiples |
| `audio.ui.confirm` | `res://assets/third_party/kenney/ui_audio/ui_confirm.ogg` | KENNEY / CC0 | title, arena, shrine, IAP | confirm/purchase/select sound | several meanings pile onto one sound | optional replace | P2 | 0.093832s, 44.1kHz stereo |
| `audio.ui.focus` | `res://assets/third_party/kenney/ui_audio/ui_focus.ogg` | KENNEY / CC0 | `arena.tscn` | focus/acquire feedback | very short and generic so combat-reward impression is weak | optional replace | P2 | 0.057324s, 44.1kHz stereo |

Subtotal: **4, referenced 4 / unused 0**

### 3.3 Characters, enemies, bosses, and comparison player 11

| Asset ID | Current path | Source/license | Used scenes/resources | Role | Issue | Needs replace | Priority | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `legacy.hero.walk` | `res://assets/third_party/ninja_adventure/actor/ninja_walk.png` | NA / CC0 | currently unused at runtime | walk sheet for comparing earlier lessons and specs | three-hero and Player-fallback replacement done | no, keep for comparison | P3 | 64×64, 16×16, 4 dir × 4 frames, 9fps |
| `legacy.hero.idle` | `res://assets/third_party/ninja_adventure/actor/ninja_idle.png` | NA / CC0 | currently unused at runtime | idle sheet for comparing earlier lessons and specs | three-hero and Player-fallback replacement done | no, keep for comparison | P3 | 64×16, 16×16, 4 dir × 1 frame, 1fps |
| `enemy.spirit.shared` | `res://assets/third_party/ninja_adventure/actor/spirit.png` | NA / CC0 | `spirit.tscn`, `wisp/weaver/stalker/caster/swarm.tres` | shared body for 5 spirits | same silhouette despite different behavior, so combat readability is low | yes, split into 5 | P0 | 64×64, 16×16, 4 dir × 4 frames, 5–6fps |
| `enemy.drifter.bat` | `res://assets/third_party/ninja_adventure/actor/spirit_bat.png` | NA / CC0 | `drifter.tres` | floating enemy | part of the problem that all 7 kinds share only 3 sheets | yes | P1 | 64×64, 4 dir × 4 frames, 9fps |
| `enemy.ember.body` | `res://assets/third_party/ninja_adventure/actor/spirit_ember.png` | NA / CC0 | `ember.tres` | ember-type enemy | per-region enemy difference relies too much on color and behavior | yes | P1 | 64×64, 4 dir × 4 frames, 7fps |
| `boss.guardian.shared` | `res://assets/third_party/ninja_adventure/actor/guardian.png` | NA / CC0 | `guardian*.tres` | shared body for forest/field/camp bosses | 3 bosses share one sheet and all per-state custom sheets are null | yes, split per boss and state | P0 | 250×50, 50×50 5 frames, no direction |
| `archive.hero.dead` | `res://assets/third_party/ninja_adventure/actors/player/dead.png` | NA / CC0 | none | death sheet for comparing earlier lessons | runtime-unused archive | no replace needed; delete candidate after backup | P3 | 32×64, 32×32 2 frames |
| `archive.hero.hit` | `res://assets/third_party/ninja_adventure/actors/player/hit.png` | NA / CC0 | none | hit sheet for comparing earlier lessons | runtime-unused archive | no replace needed; delete candidate after backup | P3 | 128×64, 32×32 4×2 |
| `archive.hero.idle` | `res://assets/third_party/ninja_adventure/actors/player/idle.png` | NA / CC0 | none | idle sheet for comparing earlier lessons | runtime-unused archive | no replace needed; delete candidate after backup | P3 | 128×128, 32×32 4×4 |
| `archive.hero.roll` | `res://assets/third_party/ninja_adventure/actors/player/roll.png` | NA / CC0 | none | roll sheet for comparing earlier lessons | runtime-unused archive | no replace needed; delete candidate after backup | P3 | 128×96, 32×32 4×3 |
| `archive.hero.walk` | `res://assets/third_party/ninja_adventure/actors/player/walk.png` | NA / CC0 | none | walk sheet for comparing earlier lessons | runtime-unused archive | no replace needed; delete candidate after backup | P3 | 128×128, 32×32 4×4 |

Subtotal: **11, referenced 4 / unused 7**

### 3.4 Music, combat FX, terrain atlases 12

| Asset ID | Current path | Source/license | Used scenes/resources | Role | Issue | Needs replace | Priority | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `audio.music.arena` | `res://assets/third_party/ninja_adventure/audio/music/arena_theme.ogg` | NA / CC0 | `arena.tscn`, `arena.gd` | regular combat BGM | external-pack music so final brand uniqueness is weak | recommended | P2 | 48s, loop, Bgm -11dB |
| `audio.music.guardian` | `res://assets/third_party/ninja_adventure/audio/music/guardian_theme.ogg` | NA / CC0 | `arena.gd` | boss BGM | three bosses even share the same music | recommended | P2 | 32s, loop |
| `audio.music.title` | `res://assets/third_party/ninja_adventure/audio/music/title_theme.ogg` | NA / CC0 | `title_menu.tscn` | title BGM | recheck mood match after visual rebrand | recommended | P2 | 60s, loop |
| `audio.sfx.beacon_ignite` | `res://assets/third_party/ninja_adventure/audio/sfx/beacon_ignite.ogg` | NA / CC0 | `beacon.tscn` | beacon ignite SFX | core-objective complete feedback is one generic SFX | yes | P1 | 1.251859s, -6dB |
| `fx.beacon.fire` | `res://assets/third_party/ninja_adventure/fx/fire.png` | NA / CC0 | `beacon.tscn` | beacon flame particle | the game's core symbol is stock FX | yes | P0 | 96×12, 12×12 8 frames |
| `fx.raylight` | `res://assets/third_party/ninja_adventure/fx/raylight.png` | NA / CC0 | `night_forest.tscn` | title moonlight shafts | generic ray; multi-step alpha differs from pixel outlines | recommended | P2 | 216×102, 72×102 3 frames |
| `fx.beacon.smoke` | `res://assets/third_party/ninja_adventure/fx/smoke.png` | NA / CC0 | `beacon.tscn` | beacon smoke particle | core-objective presentation lacks identity | yes | P1 | 192×32, 32×32 6 frames |
| `fx.spark.shared` | `res://assets/third_party/ninja_adventure/fx/spark.png` | NA / CC0 | `beacon.tscn`, `night_forest.tscn` | beacon sparks and title motes | the same 7-frame FX is shared by different meanings | yes | P1 | 70×8, 10×8 7 frames |
| `terrain.camp.atlas` | `res://assets/third_party/ninja_adventure/tilesets/tileset_camp.png` | NA / CC0 | `rooms/camp.tres`, `beacon.tscn` | camp props and beacon brazier | even the beacon body is bound to a stock atlas | yes, coordinate-compat needed | P0 | 368×144, brazier `192,80,32,30` |
| `terrain.field.atlas` | `res://assets/third_party/ninja_adventure/tilesets/tileset_field.png` | NA / CC0 | `rooms/field.tres`, `room.gd` | field floor and decor | region difference is only a few props and tint | yes, coordinate-compat needed | P1 | 80×240, 16px grid |
| `terrain.floor.atlas` | `res://assets/third_party/ninja_adventure/tilesets/tileset_floor.png` | NA / CC0 | `rooms/camp.tres`, `room.gd` | camp floor | shared stock floor; last vertical 1px is off-grid padding | yes, coordinate-compat needed | P1 | 352×417, valid 22×26 grid |
| `terrain.nature.atlas` | `res://assets/third_party/ninja_adventure/tilesets/tileset_nature.png` | NA / CC0 | every Room, `night_forest.tscn` | trees, bushes, rocks, and title forest | dominates 1,288 title Sprites and the main silhouette of every region | yes, highest-priority compatible atlas | P0 | 384×336, 16px grid, hard-coded coords |

Subtotal: **12, referenced 12 / unused 0**

### 3.5 Ninja Theme Wood UI 44

In this group the actually referenced files are only `heart.png`, `nine_path_panel.png`,
and `panel_wood.png` — three. The other 41 are Theme-spec comparison archives.

| Asset ID | Current path | Source/license | Used scenes/resources | Role | Issue | Needs replace | Priority | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `archive.ui.arrow_left` | `res://assets/third_party/ninja_adventure/ui/arrow_left.png` | NA / CC0 | none | left-arrow archive | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.arrow_left_hover` | `res://assets/third_party/ninja_adventure/ui/arrow_left_hover.png` | NA / CC0 | none | left hover archive | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.arrow_right` | `res://assets/third_party/ninja_adventure/ui/arrow_right.png` | NA / CC0 | none | right-arrow archive | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.arrow_right_hover` | `res://assets/third_party/ninja_adventure/ui/arrow_right_hover.png` | NA / CC0 | none | right hover archive | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.button_checked` | `res://assets/third_party/ninja_adventure/ui/button_checked.png` | NA / CC0 | none | checked-button archive | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.button_checked_disabled` | `res://assets/third_party/ninja_adventure/ui/button_checked_disabled.png` | NA / CC0 | none | disabled checked button | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.button_disabled` | `res://assets/third_party/ninja_adventure/ui/button_disabled.png` | NA / CC0 | none | disabled button | unused stock UI | no, delete candidate | P3 | 16×8, 9-slice margin 2 |
| `archive.ui.button_hover` | `res://assets/third_party/ninja_adventure/ui/button_hover.png` | NA / CC0 | none | hover button | unused and also not wired to current real button-state presentation | recommend making separately for new UI states | P3 | 16×8 |
| `archive.ui.button_normal` | `res://assets/third_party/ninja_adventure/ui/button_normal.png` | NA / CC0 | none | normal button | unused; current UI mostly reuses `panel_wood` | recommend making separately for new UI states | P3 | 16×8 |
| `archive.ui.button_pressed` | `res://assets/third_party/ninja_adventure/ui/button_pressed.png` | NA / CC0 | none | pressed button | unused stock UI | recommend making separately for new UI states | P3 | 16×8, margin top 3/bottom 1 |
| `archive.ui.button_unchecked` | `res://assets/third_party/ninja_adventure/ui/button_unchecked.png` | NA / CC0 | none | unchecked button | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.button_unchecked_disabled` | `res://assets/third_party/ninja_adventure/ui/button_unchecked_disabled.png` | NA / CC0 | none | disabled unchecked button | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.checked` | `res://assets/third_party/ninja_adventure/ui/checked.png` | NA / CC0 | none | checked icon | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.checked_disabled` | `res://assets/third_party/ninja_adventure/ui/checked_disabled.png` | NA / CC0 | none | disabled checked icon | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.h_slider_grabber` | `res://assets/third_party/ninja_adventure/ui/h_slidder_grabber.png` | NA / CC0 | none | horizontal slider grabber | unused archive including a filename typo | no, delete candidate | P3 | keep original filename |
| `archive.ui.h_slider_grabber_disabled` | `res://assets/third_party/ninja_adventure/ui/h_slidder_grabber_disabled.png` | NA / CC0 | none | disabled horizontal grabber | unused archive | no, delete candidate | P3 | keep original filename |
| `archive.ui.h_slider_grabber_hover` | `res://assets/third_party/ninja_adventure/ui/h_slidder_grabber_hover.png` | NA / CC0 | none | hover horizontal grabber | unused archive | no, delete candidate | P3 | keep original filename |
| `ui.health_heart` | `res://assets/third_party/ninja_adventure/ui/heart.png` | NA / CC0 | `hud.tscn`, `moon_dew.tscn` | HP pips and field dew pickup | UI HP and world drop share the same heart so meaning is ambiguous | yes, split HUD and drop | P1 | 80×16, 16×16 5 frames |
| `archive.ui.inventory_cell` | `res://assets/third_party/ninja_adventure/ui/inventory_cell.png` | NA / CC0 | none | inventory cell | unused stock UI | no, delete candidate | P3 | 16×16 |
| `archive.ui.nine_path_bg` | `res://assets/third_party/ninja_adventure/ui/nine_path_bg.png` | NA / CC0 | none | 9-slice background | unused stock UI | no, delete candidate | P3 | 16×16, margin 2 |
| `archive.ui.nine_path_bg_2` | `res://assets/third_party/ninja_adventure/ui/nine_path_bg_2.png` | NA / CC0 | none | 9-slice background variant | unused stock UI | no, delete candidate | P3 | 16×16, margin 2 |
| `archive.ui.nine_path_focus` | `res://assets/third_party/ninja_adventure/ui/nine_path_focus.png` | NA / CC0 | none | focus border | unused stock UI | no, delete candidate | P3 | 8×8, margin 3 |
| `ui.relic_panel` | `res://assets/third_party/ninja_adventure/ui/nine_path_panel.png` | NA / CC0 | `relic_panel.tscn` | relic-card background | the core relic-choice screen is a stock wood panel | yes | P1 | 16×16, margin 6 |
| `archive.ui.nine_path_panel_2` | `res://assets/third_party/ninja_adventure/ui/nine_path_panel_2.png` | NA / CC0 | none | panel variant | unused stock UI | no, delete candidate | P3 | 16×16, margin 6 |
| `archive.ui.nine_path_panel_3` | `res://assets/third_party/ninja_adventure/ui/nine_path_panel_3.png` | NA / CC0 | none | panel variant | unused stock UI | no, delete candidate | P3 | 16×16, margin 6 |
| `archive.ui.nine_path_panel_disabled` | `res://assets/third_party/ninja_adventure/ui/nine_path_panel_disabled.png` | NA / CC0 | none | disabled panel | unused stock UI | no, delete candidate | P3 | 16×16, margin 6 |
| `archive.ui.nine_path_panel_interior` | `res://assets/third_party/ninja_adventure/ui/nine_path_panel_interior.png` | NA / CC0 | none | panel interior | unused stock UI | no, delete candidate | P3 | 16×16, margin 3/3/2/2 |
| `ui.panel_wood` | `res://assets/third_party/ninja_adventure/ui/panel_wood.png` | NA / CC0 | title, HUD, results, settings, pause, quit, credits, ranking, shrine, IAP | shared panel/button background | one bright orange wood sheet dominates almost every screen and per-state look is often identical | yes, highest-priority UI-theme replace | P0 | 16×16, margin 5 |
| `archive.ui.radio_checked` | `res://assets/third_party/ninja_adventure/ui/radio_checked.png` | NA / CC0 | none | selected radio | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.radio_checked_disabled` | `res://assets/third_party/ninja_adventure/ui/radio_checked_disabled.png` | NA / CC0 | none | disabled selected radio | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.radio_unchecked` | `res://assets/third_party/ninja_adventure/ui/radio_unchecked.png` | NA / CC0 | none | unselected radio | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.radio_unchecked_disabled` | `res://assets/third_party/ninja_adventure/ui/radio_unchecked_disabled.png` | NA / CC0 | none | disabled unselected radio | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.slider_progress` | `res://assets/third_party/ninja_adventure/ui/slider_progress.png` | NA / CC0 | none | slider progress bar | unused stock UI | no, delete candidate | P3 | 16×16, margin 3/3/4/3 |
| `archive.ui.slider_progress_hover` | `res://assets/third_party/ninja_adventure/ui/slider_progress_hover.png` | NA / CC0 | none | hover progress bar | unused stock UI | no, delete candidate | P3 | 16×16 |
| `archive.ui.tab` | `res://assets/third_party/ninja_adventure/ui/tab.png` | NA / CC0 | none | tab | unused stock UI | no, delete candidate | P3 | 16×12, bottom margin 0 |
| `archive.ui.tab_disabled` | `res://assets/third_party/ninja_adventure/ui/tab_disabled.png` | NA / CC0 | none | disabled tab | unused stock UI | no, delete candidate | P3 | 16×12 |
| `archive.ui.tab_hover` | `res://assets/third_party/ninja_adventure/ui/tab_hover.png` | NA / CC0 | none | hover tab | unused stock UI | no, delete candidate | P3 | 16×12 |
| `archive.ui.tab_selected` | `res://assets/third_party/ninja_adventure/ui/tab_selected.png` | NA / CC0 | none | selected tab | unused stock UI | no, delete candidate | P3 | 16×12 |
| `archive.ui.tab_unselected` | `res://assets/third_party/ninja_adventure/ui/tab_unselected.png` | NA / CC0 | none | unselected tab | unused stock UI | no, delete candidate | P3 | 16×12 |
| `archive.ui.unchecked` | `res://assets/third_party/ninja_adventure/ui/unchecked.png` | NA / CC0 | none | unchecked icon | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.unchecked_disabled` | `res://assets/third_party/ninja_adventure/ui/unchecked_disabled.png` | NA / CC0 | none | disabled unchecked icon | unused stock UI | no, delete candidate | P3 | comparison |
| `archive.ui.v_slider_grabber` | `res://assets/third_party/ninja_adventure/ui/v_slidder_grabber.png` | NA / CC0 | none | vertical slider grabber | unused archive including a filename typo | no, delete candidate | P3 | keep original filename |
| `archive.ui.v_slider_grabber_disabled` | `res://assets/third_party/ninja_adventure/ui/v_slidder_grabber_disabled.png` | NA / CC0 | none | disabled vertical grabber | unused archive | no, delete candidate | P3 | keep original filename |
| `archive.ui.v_slider_grabber_hover` | `res://assets/third_party/ninja_adventure/ui/v_slidder_grabber_hover.png` | NA / CC0 | none | hover vertical grabber | unused archive | no, delete candidate | P3 | keep original filename |

Subtotal: **44, referenced 3 / unused 41**

### 3.6 Count check

| Group | Count | Referenced | Unused |
| --- | ---: | ---: | ---: |
| Derived / original | 12 | 12 | 0 |
| Fonts · Kenney audio | 4 | 4 | 0 |
| Characters · comparison player | 11 | 6 | 5 |
| Music · FX · terrain | 12 | 12 | 0 |
| Theme Wood UI | 44 | 3 | 41 |
| **Total** | **83** | **37** | **46** |

`res://icon.svg` is used as the project/window/iOS icon source but was not
included in the 83 under `apps/game/assets`. Currently
`tools/build_app_icon_assets.py` makes this SVG, the docs favicon/logo, and
the three launchers from the same shape definition, and also checks the
Android adaptive safe circle.

## 4. SpriteFrames and animation contracts

### Player

- Sheet column order is 4 directions: `down, up, left, right`.
- Rows are animation frames.
- The old Ninja is 16×16 cells, walk 4 rows 9fps, idle 1 row 1fps.
- New Warden·Dancer·Keeper are all 24×32 cells, walk and idle 4 rows each.
  Walk/idle speeds are Warden 9/4fps, Dancer 10/4fps, Keeper 8/3.5fps.
- The cell is a compat spec; actual visible height is Warden·Dancer 22–23px,
  Keeper 23–24px. The generator checks head/body height difference 2px or
  less, feet y=31, and per-hero torso-width caps in every direction and
  frame.
- The Player root is the foot origin. Old 16px cells use `offset.y=-8`
  around to put the floor line at world `y=0`.
- `player.gd` applies a vertical correction of
  `-(sprite_cell.y - 16) × 0.5` for Heroes taller than 16px. All three
  heroes and the Player safety fallback are wired to this 24×32 path.
- Body collision is root-relative center `y=-4`, radius 4. Even if a larger
  drawing is made, feet and torso must not drift from this hitbox.
- Lesson 5's `breathe` AnimationPlayer stays in the scene but is stopped on
  the final 4-frame heroes.
  Both idle and walk lock Sprite offset and only move face/feet/arms/cloak
  frames to stop double outlines and state-switch jumps on an enlarged
  screen.

### Regular enemies

- Currently 16×16, 4 directions × 4 frames, and `SpiritKind.anim_fps` is
  5–9fps per kind.
- `spirit.tscn` hover is about a 2.2s loop.
- Manual contact-hit center is root-relative `y=-6`, radius 4.
- When applying the planned 24×24 sheet, start from `SpiritKind.lift≈-4`
  and adjust on device to keep the existing visual floor line.

### Bosses

- The current guardian sheet is 50×50 cells, 5 frames, with no direction.
- `SpiritKind` already has these visual slots:
  - `guardian_windup_sheet`
  - `guardian_alt_windup_sheet`
  - `guardian_charge_sheet`
  - `guardian_recover_sheet`
- All three current boss resources have these slots empty.
- A new 64×64 sheet needs adjustment from `lift≈-27` relative to the
  existing body floor line.
- State-animation playback time is computed to runtime AI state length and
  haste.

### Attacks, objectives, title

- `moon_slash.png`: 32×32 4 frames. Real melee hit is range 34px, cone 110°.
  Even a new 48px cell must keep effective blade pixels inside that hit.
- Beacon flame 8 frames, spark 7 frames, smoke 6 frames.
- The planned spark 8-frame contract is not immediately compatible with the
  current particle material's 7 hframes.
- Beacon flicker is a 3.7s loop.
- Title mist drift is a 48s loop.
- Title-menu blink is a 2.2s loop; flare is a 0.85s one-shot.

## 5. Terrain structure and atlas constraints

The current game has no `TileMap`, `TileMapLayer`, `TileSet`, or
`TileSetAtlasSource`.

- `room.tscn` uses an about 2100×1380 repeating Ground Sprite and runtime-
  created Decor Sprite2Ds.
- `room.gd` `KIND` and `PROP_KIND` hard-code source coordinates on the
  nature/field/camp atlases.
- Forest, field, and camp all share `tileset_nature.png`.
- Region difference is mainly tint, repeating floor, and some field/camp
  props.
- Title `night_forest.tscn` has 1,288 Sprite2Ds and 39 unique `region_rect`s
  baked, tightly bound to nature-atlas coordinates.

So the planned new 256×256 prop atlas cannot be dropped into the current
structure as-is.
If GDScript and scene structure are not changed, keep:

1. Existing atlas canvas size.
2. Position and size of every currently referenced `Rect2`.
3. Transparent padding and floor contact of large trees, rocks, and bushes.
4. Beacon brazier `Rect2(192,80,32,30)` on `tileset_camp.png`.
5. Nature atlas's 39 baked regions unless the title scene is regenerated.

Using a new atlas with different coordinates needs at least a `room.gd`
coordinate-table change and `night_forest.tscn` regeneration, which is
outside a pure PNG replacement.

## 6. Visual items that cannot be wired without code

The following visuals are generated with GDScript `_draw()`, not Texture2D.

| Script | Procedural visual | Current constraint |
| --- | --- | --- |
| `scripts/actors/moon_missile.gd` | missile head/wings/trail/impact explosion | no `projectile.moon_missile`, `weapon.starfall_impact` PNG hook |
| `scripts/items/moon_ring.gd` | orbiting arcs and cross orbs | no `weapon.moon_ring` PNG hook |
| `scripts/items/moon_ripple.gd` | wave arc | no dedicated wave-sprite hook |
| `scripts/items/moon_ember.gd` | flame-shaped drop polygon | no `pickup.moon_ember` PNG hook |
| `scripts/items/power_orb.gd` | power drop drawn as circle/arc | no `pickup.power_gem` PNG hook |
| `scripts/items/moonfire_aura.gd` | aura arcs and diamond embers | no dedicated aura-sprite hook |
| `scripts/actors/player.gd` | upgraded-slash afterimages, full moon, starlight tells | most high-tier attack assets cannot be wired directly |
| `scripts/actors/spirit.gd` | boss silhouette overlay, charge/volley/fan tells | no dedicated boss-telegraph PNG hook |
| `scripts/actors/moon_arrow.gd` | projectile trail | trail besides the core Sprite cannot be PNG-replaced |
| `scripts/ui/beacon_compass.gd` | beacon direction display | no icon Texture2D hook |
| `scripts/ui/moonfire_gauge.gd` | gauge shapes | no UI texture hook |

More wiring constraints:

- `Hero.portrait` is consumed by shrine cards and the IAP hero-bundle
  preview buttons.
- Relic and Boon resources have no icon field.
- Shrine hero cards use `48×48` portrait nodes. The IAP hero bundle also
  provides Dancer and Keeper portrait buttons and opens the same full-body
  detail panel.
- `moon_dew.tscn` is a static Sprite, so it cannot play a 4-frame pickup
  sheet.
- `moon_bolt.tscn` is also a static Sprite, so it cannot play a 4-frame
  enemy-shot sheet.
- Putting off/on 2 frames on the beacon base still has no current frame-
  switch logic.
- There is no dedicated hit spark; moon-arrow impact spark also currently
  reuses the projectile texture.

So the items above need an explicit choice of one of:

- Keep the strict no-code rule and leave the current procedural visuals.
- Approve a minimal **visual-wiring-only exception** that allows Texture2D
  export, Sprite2D/AnimatedSprite2D wiring, and icon/portrait consumption.

## 7. UI Theme and icon-structure constraints

- There is no global Godot `Theme` resource.
- Each UI scene repeatedly defines `StyleBoxTexture`, font, and color
  overrides.
- Several static Buttons reuse the same `panel_wood` StyleBox for
  normal/hover/pressed/focus, so pointer/touch state change does not show
  in the drawing.
- Relic, Boon, Hero, and IAP cards mostly rely on text and accent color.
- The current title logo is a Label, not a TextureRect.

So many of the planned `ui.panel_frame`, `ui.button_states`,
`ui.core_icons`, `ui.hud_symbols`, `ui.boon_card`, and `title.logo` will not
wire from files alone. Design a pure-replacement plan that keeps existing
nodes, and a minimal UI-wiring exception, separately.

## 8. Hard-coded visual and audio paths

| Location | Path or contract | Risk |
| --- | --- | --- |
| `scripts/gameplay/arena.gd:186-187` | arena/guardian BGM preload | code refs break if files move |
| `scripts/gameplay/room.gd:74` | `charge_ring.png` preload | change needed when splitting gate glow from enemy shot/UI |
| `scripts/gameplay/room.gd` | nature/field/camp atlas `Rect2` table | new atlas layout cannot change |
| `scripts/ui/beacon_compass.gd:41` | Bold font preload | code refs break if the font moves |
| `scripts/ui/iap_shop_panel.gd` | regular/bold font, wood panel preload | must sync separately with a new UI-theme path |
| `scripts/ui/shrine_panel.gd` | regular/bold font, wood panel preload | must sync separately with a new UI-theme path |

Prefer overwriting a compatible file on the existing path to avoid code
changes, and allow a minimal wiring change only when uses must split.

## 9. Replacement order

1. `P0` Warden and dedicated default slash, device-verified — done
2. `P0` Split base enemies through spirits and bats into per-role sheets
3. `P0` Split 3 boss bodies and per-state sheets
4. `P0` Coordinate-compat nature/camp atlases and beacon body/flame
5. `P0` Replace `panel_wood`-centric UI with a moonlit teal/navy-violet theme
6. `P1` Keeper·Dancer dedicated sheets — done; purchase-UI portrait
   consumption path follows
7. `P1` Per-region floors/props, drops/shots/hit/death FX
8. `P1` Wire portrait/icon consumption paths inside the approved scope
9. `P2` Font-size rules, joystick/gate alpha style, music/SFX unity
10. After every reference is verified, clean unused baseline 48 under the
    backup policy

## 10. Done criteria

- Baseline 83 and new custom assets are all recorded in the manifest or
  contract
- P0 three heroes have different walk/idle silhouettes
- Three bosses distinguish not only in idle but in windup/charge/recover
- Three regions distinguish by terrain silhouette and floor pattern even
  without tint
- Beacon, main attack, and shared panel no longer expose Ninja original
  pixels
- New sheets' directions, frame counts, FPS, and foot origins match the
  contracts above
- Portrait/icon/projectile contracts that are only planned and have no
  consumer are clearly classified as `wired`, `waiting on exception
  approval`, or `keep procedural`
- No blur or atlas bleed at 808×360 internal resolution, nearest filter,
  Pixel 10 3x scale
- Unused 46 have reference checks and backups done before deletion
