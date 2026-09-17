# Asset download guide

:::tip Download and unzip are already done
If you are working in this repository you do not need to repeat the steps
below.
**The six asset packs are already downloaded into `_downloads/` and unzipped
into `_asset_sources/`.** Both folders are gitignored, so they are not on
a clone. Only people following from scratch need the steps below.

Files currently in `_downloads/`:

```text
_downloads/
  Ninja Adventure - Asset Pack.zip     # main graphics · music · SFX
  Godot Project V4.zip                 # author's demo project (reference only, do not copy code)
  kenney_input-prompts-pixel.zip
  kenney_ui-audio.zip
  kenney_impact-sounds.zip
  Galmuri-v2.40.4.zip
```
:::

This project **does not include full original asset packs in the repo.**
Download them yourself with the steps below, then copy only the files each
lesson actually uses into `apps/game/assets/third_party/`.

## Rules

1. **Always confirm the license on the page itself** and keep a copy in
   `apps/game/docs/licenses/`.
2. Original ZIPs go in `_downloads/`, unzipped trees in `_asset_sources/`.
   Both are gitignored.
3. Put **only files you actually use** inside the Godot project (`apps/game/`).
4. Record every copy in the [asset manifest](./manifest.md).
5. **Do not use the demo Godot project that ships with an asset pack as a
   base project.** Read it only as a reference for sprite-frame layout.

## Working folders

```text
MoonlitBeacon/
  apps/
    game/assets/third_party/   <- only files actually used
    docs/                      <- docs site
  _downloads/                  (gitignored)
    Ninja Adventure - Asset Pack.zip
    Godot Project V4.zip
    kenney_input-prompts-pixel.zip
    kenney_ui-audio.zip
    kenney_impact-sounds.zip
    Galmuri-v2.40.4.zip
  _asset_sources/              (gitignored)
    ninja_adventure/
    ninja_adventure_reference_project/
    kenney_input_prompts/
    kenney_ui_audio/
    kenney_impact_sounds/
    galmuri/
```

---

## A. Ninja Adventure – Asset Pack (main graphics · music · SFX)

- Source: itch.io — `pixel-boy / Ninja Adventure - Asset Pack`
- License: **CC0 1.0 Universal** (commercial use allowed, credit not required / recommended)
- Look: 16 × 16 top-down pixel art

### Download steps

1. Open itch.io.
2. Search for `Ninja Adventure Asset Pack pixel-boy`.
3. Confirm the page license is `Creative Commons Zero v1.0 Universal`.
4. Press `Download Now`.
5. You can proceed at $0 on the amount screen.
6. Download `Ninja Adventure - Asset Pack.zip` (about 89MB).
7. Also download `Godot Project V4.zip` (about 30MB) **for reference only**.
8. Keep the original ZIP in `_downloads/` and unzip into
   `_asset_sources/ninja_adventure/`.

### What we use

| Use | Content |
| --- | --- |
| Player | one fully animated character — Idle, Walk, Hit, Death, **Roll** (dash) |
| Enemies | 3 monster sprites |
| Boss | 1 final guardian |
| Map | forest tileset (16×16) |
| UI | wood UI theme, health display |
| VFX | beacon light, particles, hit effects |
| Audio | BGM, game SFX |

---

## B. Kenney – Input Prompts Pixel (control-guide icons)

- Source: kenney.nl → Assets → `Input Prompts Pixel`
- License: **CC0** (commercial use allowed, credit not required)
- About 800 16 × 16 pixel icons

### Download steps

1. Go to Assets on Kenney's official site.
2. Search for `Input Prompts Pixel`.
3. Confirm the CC0 license on the page.
4. Choose `Download`.
5. On the support screen you can pick `Continue without donating...`.
6. Unzip and copy **only the icons you need** into the project.

### Icons we use (these only)

This game's official controls are touch. **Touch/stick icons** come first
for the control-guide screen and the itch.io page.

- Analog stick (4 tilt directions)
- Finger tap / drag
- Back

Also grab **WASD, arrow keys, Space, Esc** for desktop test hints during
development, but the shipping control-guide screen only includes touch icons.

---

## C. Kenney – UI Audio (menu · button SFX)

- Source: kenney.nl → Assets → `UI Audio`
- License: **CC0**
- 50 sound effects

Use is limited to:

- Menu focus move
- Button confirm
- Settings change
- Pause
- Result screen appear

> Ninja Adventure has SFX too. We use Kenney UI Audio to show **an example
> of managing UI sound in a separate folder/bus.**

---

## D. Kenney – Impact Sounds (hit · collision SFX)

- Source: kenney.nl → Assets → `Impact Sounds`
- License: **CC0**
- 130 sound effects

Uses:

- Player hit
- Enemy / obstacle collision
- Guardian appear sting
- Impact just before a beacon activates

---

## E. Galmuri11 (Korean pixel font)

Shipping UI later swapped the pixel face for Nexon MapleStory (see the
[asset manifest](./manifest.md)). Lesson 1 still records the original Galmuri
intake because that is what the course built first. The `Galmuri11.ttf` files
are **not** in `res://` anymore; the `.tres` resources keep the old names and
point at MapleStory + Noto.

- Source: GitHub `quiple/galmuri` or the Galmuri official page
- License: **SIL Open Font License 1.1**
- Downloaded file: `Galmuri-v2.40.4.zip`
- Files originally copied: `Galmuri11.ttf`, `Galmuri11-Bold.ttf`

The distribution also includes `Galmuri9`, `Galmuri7`, `.bdf`, `.woff2`,
and Bitmap / Mono / Condensed variants. The original intake copied only the
two `.ttf` files.

### Usage rules

| Use | Font |
| --- | --- |
| Body, help, settings | `Galmuri11` |
| Titles, buttons, result score | `Galmuri11-Bold` |

- Galmuri11 is drawn on an 11px grid. **Use type sizes that are multiples
  of 11 only.**
  (Title screen: title 55, subtitle/hints 22, version 11)
- Include the OFL license file as `apps/game/docs/licenses/OFL-1.1.txt`.

---

## Asset we did not pick: Tiny Swords

Tiny Swords also allows commercial use and modification, but the license
**forbids redistributing or repackaging the assets.** That is awkward for
a public course repository that includes assets, so the first course uses
the much easier-to-manage CC0 pack (Ninja Adventure).

---

## License checklist

For each asset, confirm all of the following, then record it in
[Third-party assets and licenses](./third-party.md).

- [ ] Recorded the source URL
- [ ] Confirmed the license type on the page itself
- [ ] Commercial use is allowed
- [ ] Redistribution (including this repo) is allowed
- [ ] If credit is required, it is on the credits screen
- [ ] Saved a copy of the license text in `apps/game/docs/licenses/`
- [ ] Recorded the copied files in the
      [asset manifest](./manifest.md) (`apps/docs/docs/assets/manifest.md`)
- [ ] Copied files live under `apps/game/assets/third_party/`, and original
      ZIPs stay outside `res://` (`_downloads/` only)
