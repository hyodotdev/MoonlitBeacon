# Lesson 1 — Plan

## Official tutorial mapping

`First 2D game / Setting up the project`

## Goal

Build a foundation that will not shift for the next 15 lessons, and **stand a finished title screen on that foundation**. Lock resolution, orientation, renderer, pixel filter, folder layout, license records, and Git rules here.

The Lesson 1 deliverable is not an empty project. **Run it on a phone and you get a title screen you could use as a store screenshot.** Every lesson in this course ends that way.

## Changes

### 1. Create the Godot project

| Setting | Value | Why |
| --- | --- | --- |
| Godot version | 4.7.1 Standard | Current stable. Do not record with a development build |
| Language | GDScript | A C# toolchain is too heavy for a first lesson |
| Renderer | Compatibility | Best Android low-end GPU compatibility |
| Internal resolution | 808 × 360 | Exactly 1/3 of Pixel 10 landscape (2424 × 1080). Integer 3× scale |
| Window size (desktop test) | 1616 × 720 | Integer 2× of the internal resolution |
| Stretch mode | `canvas_items` | Scale pixel art while keeping UI sharp |
| Stretch aspect | `expand` | Device aspect ratios differ, so `keep` makes letterbox thickness vary |
| Orientation | `4` (Sensor Landscape) | Landscape lock. Both landscape directions allowed |
| Texture filter | `Nearest` | Keeps pixel art from blurring |
| Mouse → touch | `true` | Lets you test the virtual stick without a phone |

Items written into `project.godot`:

```ini
[display]
window/size/viewport_width=808
window/size/viewport_height=360
window/size/window_width_override=1616
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=4

[input_devices]
pointing/emulate_touch_from_mouse=true

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/canvas_textures/default_texture_filter=0
textures/vram_compression/import_etc2_astc=true
```

**Why `expand` instead of `keep`.**
For a desktop game, `keep` with black bars is clean. Android mixes 20:9, 19.5:9, 16:9, and tablet 4:3. With `keep`, letterbox thickness changes per device and the game looks cheap. `expand` fills the screen with no bars, and leftover width **widens the view.** Because width is no longer fixed, UI must pin to edge anchors, and the background art shifts by leftover width to stay centered.

### 2. Folder layout

```text
MoonlitBeacon/
  apps/
    game/              # Godot project (res://)
      assets/
        third_party/   #   only external files we actually use
        derived/       #   files we made or processed
      scenes/
      scripts/
      resources/
      localization/
      docs/licenses/   #   copies of license texts
    docs/              # docs site (Docusaurus, GitHub Pages)
      docs/            #   project docs
      course/          #   lesson notes and recording scripts
  _downloads/          # original asset ZIPs     (gitignored)
  _asset_sources/      # unzipped originals      (gitignored)
  builds/              # build output            (gitignored)
```

**Key decision: keep original assets outside `res://`.**
Dumping the whole Ninja Adventure pack (about 89MB) into the project makes Godot import unused images and audio, and beginners cannot find the files they need.
Keep the game and the docs in one repository, but drop them side by side under `apps/`.

### 3. Title screen

This is the visible Lesson 1 result. The only script we write is this one
(`res://scripts/ui/title_menu.gd`).

| Element | Content |
| --- | --- |
| Background | Forest floor · clearing · night mist baked as derived textures (`assets/derived/title/`) |
| Forest | Trees cut from `tileset_nature.png` and placed as a border |
| Beacon | `tileset_camp.png` fire pit + `fx/fire.png` `spark.png` `smoke.png` particles |
| Moonlight | `fx/raylight.png` shafts |
| Type | Galmuri11 / Galmuri11-Bold. Title 55, prompt 22, version 11 (multiples of 11) |
| Music | `13 - Mystical.ogg` → `title_theme.ogg`. Fade in from silence over 2.4s |
| SFX | Kenney UI Audio `ui_confirm.ogg` |
| Input | Touch anywhere → the beacon flares and `start_requested` fires |

`_recenter_diorama()` shifts the background by the extra width from `expand` so it stays centered.
When shifting, **floor to integer pixels.** A leftover half-pixel misaligns dots under nearest-neighbor scale.

The version string is read from `ProjectSettings`. Manage it in one place: `project.godot`.

### 4. Docs

| File | Role |
| --- | --- |
| `README.md` | Repository intro, course outline |
| `apps/docs/docs/intro.md` | Project overview and how to run it |
| `apps/docs/docs/design/game-design.md` | Game design document |
| `apps/docs/docs/assets/download-guide.md` | Asset download steps + license checklist |
| `apps/docs/docs/assets/third-party.md` | Third-party assets and licenses |
| `apps/docs/docs/assets/manifest.md` | Record of files actually copied |
| `apps/docs/docs/release/checklist.md` | QA / build / release checklist |
| `apps/docs/docs/workflow/ai-prompt.md` | Shared prompt for implementing a lesson |
| `apps/docs/docs/workflow/recording.md` | Script → record → edit → embed pipeline |
| `apps/game/docs/licenses/` | Copies of license texts |

### 5. Git

- Initialize on the `main` branch
- `.gitignore` excludes `.godot/`, `_downloads/`, `_asset_sources/`, `builds/`
  - `.godot/` stores `export_credentials.cfg` (Android signing password), so it must be excluded
  - `export_presets.cfg` has no secrets, so **commit it**
- `.gitattributes` marks text vs binary handling

:::warning Git commit comes before the docs site
Docusaurus has `showLastUpdateTime` on, so each docs page reads its last-updated time **from the git log**. Running `pnpm docs:build` with zero commits fails. Keep the order `git init` → first commit → then start the docs site.
:::

### 6. Android export prep

In Lesson 1 we create a preset and **install a debug APK once to confirm the title screen looks right on a phone**. Signing, version codes, and back-button handling wait for Lesson 11 and Lesson 16.

| Item | Value |
| --- | --- |
| preset name | `Android` |
| package name | `com.crossplatformkorea.moonlitbeacon` |
| app name | Moonlit Beacon |
| architecture | arm64-v8a only |
| `version/code` | 1 |
| `version/name` | 0.0.1 |
| export path | `../../builds/android/MoonlitBeacon.apk` |

```bash
pnpm android:build
pnpm android:run
```

## Not this lesson

- Gameplay scene (from Lesson 2)
- Player and movement (Lesson 5)
- Virtual joystick (Lesson 6, 11)
- InputMap setup (Lesson 6)

## Completion criteria

- [x] Project runs with no errors
- [x] Title screen fills the phone landscape view and can be used as a screenshot
- [x] Changing window width keeps the background centered and UI pinned to the edges
- [x] Pixel images stay sharp (`Nearest` filter)
- [x] Tapping the screen flares the beacon and plays a confirm sound
- [x] Five asset packs downloaded into `_downloads/`, unzipped copies in `_asset_sources/`
- [x] Asset sources and licenses recorded in the docs
- [x] Asset ZIPs are not inside `res://`
- [x] `godot --headless --path apps/game --quit` exits 0

## Recommended commit message

```text
chore: Lesson 1 — project setup, asset licenses, title screen

- Godot 4.7.1 Compatibility renderer, 808x360 landscape lock (Pixel 10 integer 3x)
- stretch canvas_items + expand, texture filter Nearest
- Keep original assets (_downloads, _asset_sources) outside res://
- Finish the title screen with Ninja Adventure / Kenney / Galmuri
- Write the design doc / asset guide / licenses / release checklist
```
