# Clip capture

Shoot screen clips to attach to a lesson. Every trap here is one we **actually
stepped in**. Start without reading and you spend the same time in the same
place.

## Usage

```text
/record editor      Godot editor work
/record game        Game screen (Movie Maker)
/record device      Phone device screen
/record browser     Browser (asset pages, docs)
```

Tools live in [`notes/tools/capture/`](../../notes/tools/capture/).

---

## Decide where the clip goes first

| | Directly in the repo | YouTube |
| --- | --- | --- |
| Sound | **Silent only** | Narrated |
| Size | **1MB or under** | No limit |
| Width | 1212 (game is 1212×540) | 1920×1080 |
| Use | Short screen under a section | Lesson master |

**Make both.** The 1920×1080 master lives in `builds/footage/` (not in git);
the repo copy is shrunk into `apps/docs/static/video/chapter-XX-*.mp4`.

Editor UI with lots of still frames compresses well — 74 seconds fit in 797KB.
Browser scrolling with lots of motion needs CRF up to 35 to come in under 1MB.
**Judge by size, not length.**

---

## Shared: how to grab the screen

### Capture the monitor, not the window

Grabbing **the window only** with `ffmpeg gdigrab -i "title=..."` keeps
personal data off camera, but **menu dropdowns and dialogs are not captured
at all.** Godot popups are separate OS windows.
Even with `interface/editor/display/single_window_mode` on, **menu dropdowns
are still separate popups**.

The fix is to **fill one monitor exactly with the window and capture that
monitor region**. Popups on top are all in frame; other monitors are outside
the capture.

```bash
ffmpeg -f gdigrab -framerate 30 -draw_mouse 1 \
  -offset_x 3840 -offset_y 0 -video_size 3840x2160 -i desktop \
  -t 90 -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p \
  builds/footage/chapter-XX-raw.mkv
```

### This PC's display layout

Two 4K monitors, Windows scaling 200%.

| | Value |
| --- | --- |
| One monitor | 3840 × 2160 (physical) |
| Virtual desktop | 7680 × 2160 |
| Right monitor | from x = 3840 |

**If you ignore DPI, clicks land at half the intended point.** Automation
scripts must call `SetProcessDPIAware()` first. Without it, coordinates are
interpreted as logical resolution (1920×1080).

### Do not shoot on the left monitor

A fullscreen game (Roblox and the like) **pins the cursor to the screen
center.** `SetCursorPos` is all undone and clicks go to that game.
**Shoot on the right monitor.** Keyboard input is not affected.

How to check if you are stuck:

```powershell
[void][W]::SetCursorPos(5000, 800)
# If GetCursorPos does not read 5000,800, another window is holding the cursor
# Use WindowFromPoint to see which window
```

### Do not mix coordinate bases

Window capture is **client area only**; monitor capture includes **the title
bar**. Measure with window capture and click with monitor capture, and
everything is off by the title-bar height (about 57px at 200%). The first
click actually landed on the title bar and the menu never opened.
**Measure and capture the same way.**

### Confirm with pixels instead of a fixed wait

Following UI with `Start-Sleep` alone falls over under load.
While ffmpeg encoded 4K30, a dialog appeared late, the next click went into
empty space, and we **shot one unusable 82-second take**.

Look at an easy-to-tell pixel color before moving on.

```powershell
Wait-Color $x $y @(86,158,255)   # until the Advanced Settings toggle is on
```

| What you are checking | Color |
| --- | --- |
| Project Settings is up | Dialog background `27,27,27` |
| Advanced Settings on | `86,158,255` (off is `71,71,71`) |

### Put a BOM on PowerShell scripts

PowerShell 5.1 reads a BOM-less `.ps1` as ANSI.
Hangul comments break and the parser dies.

```powershell
$b=[IO.File]::ReadAllBytes($p); if($b[0] -ne 0xEF){ [IO.File]::WriteAllBytes($p, ([byte[]](0xEF,0xBB,0xBF)+$b)) }
```

**Conversely, `project.godot` must not have a BOM.**
`Set-Content -Encoding utf8` writes a BOM, and Godot reads it as part of the
key name, producing junk like `"ï»¿config_version"=5`. The project opens
broken.

```powershell
[System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding $false))
```

---

## `/record editor` — Godot editor work

### Prep

1. **Back up editor settings.** Restore them when shooting is done. This is
   the user's personal environment.

   ```powershell
   Copy-Item "$env:APPDATA\Godot\editor_settings-4.7.tres" backup.tres
   ```

2. Change three things.

   | Key | Value | Why |
   | --- | --- | --- |
   | `interface/editor/localization/editor_language` | `"en"` | Lesson docs are written with English menu names |
   | `interface/editor/fonts/main_font_size` | `16` | Readable after shrinking to 1080p |
   | `interface/editor/display/single_window_mode` | `true` | Dialogs come inside the main window |

3. **Close Godot first**, then edit the settings file. It rewrites this file
   on quit.

### Make a separate project for capture

`apps/game` already has `project.godot`, so you cannot shoot "create a new
project" or "type the settings from scratch".

```powershell
# builds/take/ is not in git
notes/tools/capture/reset.ps1
```

### The result `project.godot` proves you shot the right thing

That is the upside of an editor-work clip. When shooting ends, compare the
result `project.godot` with `apps/game/project.godot`. If any value differs,
the operation was off, so **throw that take away**. Finding it after you have
edited is too late. `notes/tools/capture/record.ps1` runs this check
automatically.

### Afterward

Restore editor settings from the backup. **Close Godot first**, then restore.

---

## `/record game` — game screen

Do not record by hand. Movie Maker renders with no dropped frames.

```bash
mkdir -p builds/footage
godot --path apps/game --write-movie ../../builds/footage/chapter-XX-intro.avi --quit-after 600
```

- `--quit-after` is a **frame count**. At 60fps, 600 = 10 seconds.
- Relative paths are **relative to `apps/game`**. Drop `../../` and it points
  at `apps/game/builds/`; if the folder is missing you get **exit code 0 and
  no file**.
- Resolution cannot be changed with `--resolution`. The window grows but the
  file comes out at `window_width_override`. Reproduced 3 times.
  If you need a larger clip, edit `project.godot` yourself and put it back.
- **Black bars from `aspect=keep` are not captured.** Only the root viewport
  texture is.

Output is MJPEG AVI. Re-encode.

```bash
ffmpeg -i builds/footage/chapter-XX-intro.avi -c:v libx264 -crf 18 -pix_fmt yuv420p builds/footage/chapter-XX-intro.mp4
```

---

## `/record device` — phone device

See [`/device --record`](./device.md). The core is **launch the app first,
wait until it is landscape, then start recording.**

---

## `/record browser` — browser

**Open a new window with a temporary profile.** Using the user's real profile
leaves the bookmarks bar, account name, and open-tab titles on screen.

```powershell
chrome.exe --user-data-dir=<temp-folder> --no-first-run --no-default-browser-check `
  --window-position=3840,0 --force-device-scale-factor=2 <URL>
```

When shooting ends, delete the whole profile folder.

**Do not find the window by process name.** We once grabbed the user's
existing Chrome and moved that window to another monitor. Keep the PID of the
window you just launched.

**After an address-bar navigation, click the page body once.** Otherwise
focus stays on the omnibox and you shoot with the autocomplete dropdown open.

**Confirm navigation by window title.** A failed first navigation once
shifted the whole take.

```powershell
while ((Win-Title) -notlike "*$expect*") { Start-Sleep -Milliseconds 250 }
```

---

## Shrink for the repo

```bash
# Game screen (16:9 family)
ffmpeg -i in.mp4 -vf "scale=1212:540:flags=lanczos" -an \
  -c:v libx264 -crf 27 -preset slow -pix_fmt yuv420p -movflags +faststart out.mp4

# Editor / browser (lots of stills / lots of motion)
ffmpeg -i in.mkv -ss 5 -t 60 -vf "crop=W:H:X:Y,scale=1212:-2" -an \
  -c:v libx264 -crf 28 -preset veryslow -pix_fmt yuv420p -movflags +faststart out.mp4
```

Raise CRF and use the lowest value that still comes in under 1MB. Try
27 → 31 → 33 → 35, and **crop at original scale and check by eye that text
is readable.**

Extract a poster too.

```bash
ffmpeg -ss <good-spot> -i out.mp4 -frames:v 1 -q:v 4 apps/docs/static/img/chapter-XX-name-poster.jpg
```

## Embed

```mdx
{/* Silent short clip — autoplay + loop */}
<Video src="video/chapter-XX-name.mp4" poster="img/chapter-XX-name-poster.jpg"
       title="what this screen shows" silent />

{/* Clip over 30 seconds — controls only, no autoplay */}
<Video src="video/chapter-XX-name.mp4" poster="img/chapter-XX-name-poster.jpg"
       title="what this screen shows" />

{/* Not shot yet — a one-line card */}
<Video title="what to shoot" duration="90s" shows="what it will contain" />
```

After shooting, confirm it actually plays in the browser.

```js
[...document.querySelectorAll('video')].map(v => ({
  file: v.src.split('/').pop(), dur: Math.round(v.duration),
  size: v.videoWidth + 'x' + v.videoHeight, ready: v.readyState, err: v.error?.code
}))
```

You want `readyState: 4`, `err: null`.
