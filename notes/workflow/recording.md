# Lesson-video production pipeline

A way of working so game code and lesson videos are made **in the same
repository at the same pace**. Each time a lesson ends, repeat
`plan → body → script → shoot → edit → upload → site embed` as-is.

## Roles

| Stage | Owner | Output |
| --- | --- | --- |
| Lesson implementation | person + AI | `apps/game/` code and scenes |
| Plan / lesson notes | AI | `notes/plans/chapter-XX-plan.md`, `apps/docs/course/chapter-XX.mdx` |
| Recording script | AI | `notes/scripts/chapter-XX-script.md` |
| Gameplay clip auto-render | Godot Movie Maker | `builds/footage/*.avi` |
| Device screen record | adb screenrecord | `builds/footage/chapter-XX-device.mp4` |
| Screen record · narration | **person** | `builds/footage/chapter-XX-raw.mkv` |
| Edit · upload | person | YouTube video ID |
| Site embed | AI | `<Video youtube="..." />` in `apps/docs/course/chapter-XX.mdx` |

:::info Narration voice and actual operation are done by a person
AI cannot record the screen or narrate with a voice.
Instead it prepares **scripts, capture settings, auto-render scripts, an
edit checklist, and site embeds** so shooting itself is only "read the
script and follow along."
:::

## 1. Recording script

Each lesson script lives at `apps/docs/course/scripts/chapter-XX-script.md`.
Use this format as-is.

```text
### 00:00 – 00:45 · Finished screen

**Screen**: run the Lesson 1 finished project, drag the window size
**Narration**: "This session we will not write a single line of game code. Instead ..."
**Watch-out**: stretch the window tall and definitely show the black margins
```

- Always keep the three lines **Screen** / **Narration** / **Watch-out**.
- Write narration as **complete spoken sentences** that are not awkward when
  read aloud.
- Put easy-to-miss spots in **Watch-out** in advance to cut reshoots.

## 2. Screen-record settings

### Shared rules

| Item | Value | Why |
| --- | --- | --- |
| Resolution | 1920 × 1080 | Minimum where Godot editor UI type is readable |
| Frame rate | 60fps | Avoid afterimages in gameplay stretches |
| Encoder | hardware (NVENC/QSV) | Load that can play back immediately without an edit |
| Container | `mkv` | The file survives if recording crashes |
| Editor theme | Godot default **Dark** | Matches the site dark theme |
| Editor font size | default + 2 ~ 3 | Code readable at 1080p |
| Mouse cursor | shown + click highlight | Follow node-add positions with the eye |

:::warning Pre-shoot check
- Turn notifications off (Focus / Do Not Disturb)
- Confirm the browser bookmark bar has no personal information
- Confirm Godot recent-project list has no private paths
- 30-second mic-gain test
:::

### OBS Studio (recommended)

- Scene 1 **Editor**: one display capture
- Scene 2 **Game**: window capture (`Moonlit Beacon`) + a shrunk editor
- Scene 3 **Docs**: browser-window capture
- Assign a shortcut per scene and edit cuts drop a lot.

### One-line ffmpeg record (without OBS)

**Make the output folder first.** ffmpeg does not create missing directories
and dies immediately with `No such file or directory`.

```bash
ffmpeg -f gdigrab -framerate 60 -i desktop \
  -c:v h264_nvenc -preset p4 -cq 18 -pix_fmt yuv420p \
  builds/footage/chapter-XX-raw.mkv
```

Press `q` to stop. To include audio too, add
`-f dshow -i audio="microphone name"`.
Confirm device names with:

```bash
ffmpeg -list_devices true -f dshow -i dummy
```

## 3. Gameplay clips are pulled automatically

The **finished-screen clip** used in the intro is not recorded by hand.
Godot Movie Maker mode renders at a constant speed with no frame drops.

```bash
mkdir -p builds/footage
godot --path apps/game --write-movie ../../builds/footage/chapter-01-intro.avi \
  --quit-after 600
```

:::danger `--write-movie` relative paths are relative to the project folder
The folder given with `--path` (`apps/game`) is the base, not the current
folder where the command ran.
From the repo root, `--write-movie builds/footage/chapter-01-intro.avi`
points at `apps/game/builds/footage/`. If that folder is missing the file is
not created, and **exit code is 0 so it looks like success.** If it exists,
a video file is created inside the Godot project and becomes an import
target.

From the repo root use a path that climbs two steps from `apps/game`, like
`../../builds/footage/...`. And **create `builds/footage/` in advance.**
Godot does not create missing directories either.
:::

- `--quit-after` is a **frame count**. At 60fps, 600 = 10 seconds.
- Rendering is slower than realtime, but the result is exactly 60fps.
- **Render resolution follows window size, not internal resolution
  (808 × 360).** `project.godot` `window_width_override` is 1616 × 720, so
  that is the size you get.

:::danger `--resolution` cannot change clip size
`--resolution 2424x1080` changes the log `WINDOW=` value, but **the recorded
file still comes out at `window_width_override` size.** Reproduced 3 times.

| Condition | Log | Actual file |
| --- | --- | --- |
| no `--resolution` | `WINDOW=(1616,720)` | 1616 × 720 |
| `--resolution 2424x1080` | `WINDOW=(2424,1080)` | still 1616 × 720 |
:::

If a larger clip is needed, change `project.godot`
`window_width_override` / `window_height_override` yourself, render, then
revert. Use only integer multiples of 808 × 360
(1616 × 720 / 2424 × 1080 / 3232 × 1440) so pixels do not misalign.

- Output is **MJPEG-compressed AVI** (audio is uncompressed PCM). It is not
  uncompressed video, but each frame is independently compressed so size is
  large and it must be re-encoded after editing.

## 3.5. Recording Godot editor operations

Editor-operation clips found a method after failing twice. Failed reasons
and the fix are left together.

### Use "monitor capture", not window capture

At first `ffmpeg gdigrab -i "title=Moonlit Beacon - Godot Engine"` captured
**only the window**.
Personal information did not leak, but **menu dropdowns and dialogs were
missed entirely.**
Godot popups are separate OS windows, so they fall out of window-capture
targets.
Turning on `interface/editor/display/single_window_mode` pulls
**dialogs** such as Project Settings into the main window, but **menu
dropdowns are still separate popups**.

The fix is **fill one monitor exactly with the editor window and capture
that monitor region**.
Popups on top of it are all included, and other monitors are outside the
capture range to begin with.

```powershell
# Whole right monitor (virtual desktop from x=3840). Fill the window there first.
ffmpeg -f gdigrab -offset_x 3840 -offset_y 0 -video_size 3840x2160 -i desktop ...
```

:::danger Window capture and monitor capture have different coordinate bases
Window capture holds **only the client area**; monitor capture holds
**including the title bar**.
Measure coordinates with window capture and click with monitor capture, and
everything is off by title-bar height (about 57px at 4K 200%). The first
click actually landed on the title bar and the menu did not open.
**Measure coordinates and capture for real with the same method.**
:::

### Clicks do not go through if another window holds the mouse

If a program that traps the mouse (`ClipCursor` / cursor recentering) is
running, like a fullscreen game, `SetCursorPos` is thrown back to screen
center. Close those programs before shooting, or **on a dual monitor shoot
on the monitor that does not have that program**.
Keyboard input is unaffected, so to check whether the mouse is blocked, move
the cursor and see which window `WindowFromPoint` points at.

### Confirm screen state with pixels instead of a fixed wait

Chasing UI with only `Start-Sleep` collapses under load.
While ffmpeg encoded 4K30, the Project Settings dialog opened late, the
`Advanced Settings` toggle click sent next flew into empty air, and 82
seconds were recorded with every later coordinate wrong.

**Confirm "it was drawn" with pixel color, then continue.** Pick one easy
probe point.

| Check | Point | Color |
| --- | --- | --- |
| Project Settings is up | dialog background | `27,27,27` (if not up, the 3D viewport color behind) |
| `Advanced Settings` is on | toggle | `86,158,255` (off is `71,71,71`) |

### Whether the recorded screen is correct is proven by `project.godot`

The advantage of an editor-operation clip is that **it can be verified from
the result file**.
When shooting ends, compare that project's `project.godot` with
`apps/game/project.godot`.
If any value differs, operations drifted, so discard that take.
Finding it after the edit is finished is too late.

:::warning Make a separate capture project
`apps/game` already has `project.godot`, so you cannot shoot "create a new
project", and you cannot shoot entering settings from scratch either.
Make an empty project under `builds/take/` (gitignored) and shoot there.

Write `project.godot` **without a BOM**. PowerShell
`Set-Content -Encoding utf8` attaches a BOM, and Godot reads it as part of
the key name, producing junk like `"ï»¿config_version"=5`. The project opens
broken. Use
`[System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding $false))`.
:::

### Editor language and type size

Lesson docs write **English menu names** such as
`Project → Project Settings → Display → Window`, so before shooting set
`interface/editor/localization/editor_language` to `en`.
Default `auto` opens Korean UI on Korean Windows.
Raise `main_font_size` from default 14 to 16 and it reads when scaled down to
1080p.

**Restore original values when shooting ends.** Editor settings are the
user's personal environment.
Copy `%APPDATA%\Godot\editor_settings-4.7.tres` before shooting and restore
it when done.
Godot rewrites this file on quit, so **close the editor first** then restore.

## 4. Android device screen record

From Lesson 11 onward, **the real screen running on a phone** is the core of
the video.
Capture the device screen as-is, not a window inside the editor.

### Use `adb shell screenrecord` — order matters

```bash
# 1. Launch the app first and wait until the screen turns landscape
adb shell monkey -p com.crossplatformkorea.moonlitbeacon -c android.intent.category.LAUNCHER 1

# 2. Then start recording
adb shell screenrecord /sdcard/chapter-XX.mp4
```

:::danger If you do not launch the app first, it records lying on its side 90°
`screenrecord` **freezes the display orientation at start**.
Start recording while the screen is still portrait and the result is
`1080 × 2424`, with the landscape game lying inside it. Both cases were
reproduced.

| Order | Result file |
| --- | --- |
| start record → launch app | **1080 × 2424** (lying down) |
| launch app → wait for landscape → start record | **2424 × 1080** (correct) |
:::

If you must salvage an already-lying clip,
`ffmpeg -i in.mp4 -vf "transpose=1" out.mp4` can rotate it, but reshooting is
better for quality.

Know the limits too.

- **180 seconds max.** Split long play into several clips.
- **Audio is not included.** If game sound is needed, add it in the edit.
  Lesson video records narration on a PC mic anyway, so this is not a large
  limit.

After recording, re-encode for editing.

```bash
adb pull /sdcard/chapter-XX.mp4 builds/footage/chapter-XX-device.mp4
```

### scrcpy 4.0 dies on record in this environment

It is installed.

Mirroring and device recognition (`Pixel 10 (Android 16)`,
`Texture: 2424x1080`) are fine, but **`--record` always exits with access
violation (`0xC0000005`)**.
The file is left at 48 bytes and the container is not closed, so
`moov atom not found`.

Every combination below was tried with the same result.

| Attempt | Result |
| --- | --- |
| default (`--record` + mp4 + audio) | crash |
| `--no-audio-playback` | crash |
| `--no-playback --no-window --no-control` | crash |
| `--no-audio` + `--record-format=mkv` | crash |
| `--video-codec=h264` explicit | crash |

So it is not audio, container, or renderer; it is this build's record path
itself.
Changing scrcpy version might fix it, but the `screenrecord` path above is
enough for the lessons, so we keep going. **Use scrcpy only to watch and
operate the device screen large on the PC** (without recording).

Godot 4.7 editor settings also have an scrcpy item
(`export/android/scrcpy/screen_size`).
That is for showing the device screen from the editor, unrelated to
recording.

### APK build and install before device shooting

```bash
pnpm android:build
adb install -r builds/android/MoonlitBeacon.apk
adb shell monkey -p com.crossplatformkorea.moonlitbeacon -c android.intent.category.LAUNCHER 1
```

:::warning `am start` fails
```
SecurityException: ... not exported
```
`GodotApp` is an internal activity with `exported=false`.
The real launcher activity is `com.godot.game.GodotAppLauncher`, and
throwing a launcher intent with `monkey` as above is the most reliable.
:::

:::caution Device cleanup before shooting
- Turn notifications off (Do Not Disturb) — a personal notification in the
  status bar during record means a reshoot
- Confirm carrier name, time, and battery in the status bar have no personal
  information
- Stretch screen auto-off time
- Turning on developer-option "Show taps" puts thumb position on screen and
  makes control explanation much easier
:::

## 5. Edit checklist

- [ ] Trim lead/trail padding
- [ ] Remove silences longer than 3 seconds
- [ ] Keep scenes that fix typos, but cut repeats of the same mistake
- [ ] Confirm type is readable at 1080p in code-zoom stretches
- [ ] Match chapter markers to the script's 7 stages
- [ ] Always include the done-condition check scene
- [ ] Hold the homework screen 5 seconds or more at the end
- [ ] Loudness-normalize to -14 LUFS
- [ ] Confirm device clips are **landscape 2424 × 1080** (1080 × 2424 means
      recording started before the app launched)
- [ ] Confirm no personal notification or contact flashes through a device
      clip

## 6. Upload and site embed

### Do not upload a whole lesson as one video

Lesson notes treat **writing as the body** and video as support.
A long one-piece video at the top of the page lets a placeholder eat the
screen before shooting, and the writing that should be read is pushed down.
After shooting, viewers still scrub to find "which stretch to watch."

**Cut short and attach only under the section that needs to be seen.**

| Where to attach a clip | Where not to |
| --- | --- |
| Editor operations — which menu item, which number | Concept explanation |
| Assembling a scene | Full code listing |
| A screen that actually runs (game · phone) | Command lists |
| A demo that is broken on purpose then restored | Tables · checklists |
| Procedures where on-screen location matters, such as download/license | Homework |

One clip is best at **40 seconds to 4 minutes**. If longer, split the
section further.

### How to embed

```mdx
{/* Before shooting — a one-line card. It does not eat the page */}
<Video
  title="Every project setting in the Godot editor"
  duration="3 min"
  shows="pick renderer → enter resolution, orientation, stretch, filter → create folders"
/>

{/* After uploading to YouTube */}
<Video youtube="VIDEO_ID" title="Every project setting in the Godot editor" />

{/* Short silent screen clips live in the repo */}
<Video
  src="video/chapter-01-title.mp4"
  poster="img/chapter-01-title-poster.jpg"
  title="Pixel 10 device screen"
  silent
/>
```

`shows` is a shooting brief. It is shown as-is on the placeholder, so later
you can tell what to capture from the page alone.
`silent` is muted autoplay + loop. Use it for short clips that show a result
screen.

:::caution Narrated video goes to YouTube
What goes in the repo is **silent screen clips of 30 seconds or less**.
Scaled to 720p · CRF 27, 15 seconds is around 500KB, so it is not a burden.

```bash
ffmpeg -i builds/footage/chapter-01-title-device.mp4 -vf "scale=1212:540:flags=lanczos" \
  -an -c:v libx264 -crf 27 -preset slow -pix_fmt yuv420p -movflags +faststart \
  apps/docs/static/video/chapter-01-title.mp4
```

Narrated masters go up as **YouTube Unlisted**, and the repo keeps only the
ID.
Recording originals live in `builds/footage/` (gitignored).
:::

## 7. Full sequence of one lesson

```text
1. Implement the lesson + pass done conditions
2. Write notes/plans/chapter-XX-plan.md
3. Write apps/docs/course/chapter-XX.mdx (lesson notes)
4. Write notes/scripts/chapter-XX-script.md (recording script)
5. mkdir -p builds/footage
6. Render the intro clip with Movie Maker (--write-movie ../../builds/footage/...)
7. From Lesson 11 on: APK build → adb install → launch app → record a device clip with adb screenrecord
8. Screen record (person)
9. Edit → YouTube upload
10. Insert the video ID in the .mdx
11. PR → /review-self → squash merge → git pull on main
12. git tag -a chapter-XX-complete on the merged main commit, then git push origin <tag>
    (squash merge, so branch commits do not stay on main. Tag before merge and it floats.)
13. When needed, run Deploy Docs by hand from Actions
```
