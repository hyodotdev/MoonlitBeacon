# Device check

Bake an APK, put it on a Pixel 10, and confirm the screen that actually runs.
A commit that changes the game screen is not done until this.

## Usage

```text
/device            build → install → run → screenshot
/device --shot     launch the already-installed app and screenshot
/device --record   also record 14 seconds of screen
```

---

## 0. Check the device

```bash
adb devices -l
```

You should see `57051FDCR000HW  device  model:Pixel_10`.
If it is `unauthorized`, check the USB-debugging allow dialog on the phone.

## 1. Build

```bash
pnpm android:build
```

:::danger Do not call Godot export yourself
`android:build` prepares the build template, cleans Gradle output, and
temporarily isolates the Play Billing plugin out of the project for the
direct-distribution APK. Calling `godot --export-debug "Android"` yourself
bypasses that channel split.
:::

If Godot is not found, put the full path in `GODOT_BIN`. See [`/verify`](./verify.md)
section 0.

On success Godot export ends with `DONE` and exit code 0.
The APK must be larger than 20MB. Smaller than that, suspect missing assets.

## 2. Install and run

The default Android preset uses the same package ID as the store app. Use this
procedure on a dedicated test Pixel. Do not wipe a differently signed existing
app or `adb uninstall` user data. If you made a separate `.dev` package, confirm
the real application ID before installing.

```bash
adb install -r builds/android/MoonlitBeacon.apk
adb shell am force-stop com.crossplatformkorea.moonlitbeacon
adb shell monkey -p com.crossplatformkorea.moonlitbeacon -c android.intent.category.LAUNCHER 1
```

:::danger `am start` will not launch it
```bash
adb shell am start -n com.crossplatformkorea.moonlitbeacon/com.godot.game.GodotApp
# SecurityException: not exported
```
`GodotApp` is an internal activity with `exported=false`.
The real launcher is `com.godot.game.GodotAppLauncher`, but throwing a launcher
intent with `monkey` is more reliable than memorizing the name.
:::

Confirm it is running:

```bash
adb shell pidof com.crossplatformkorea.moonlitbeacon
```

## 3. Screenshot

`android:build` is a debug APK for the device-dev loop, so title `TestLauncher`,
under-run `ArenaTools`, and the right-side `FrameMeter` are on by default.
Release strips those nodes entirely, but shooting them as-is breaks the
"no debug strings" visual bar below. Everyday `pnpm android:shot` arms both
title and combat requests, waits for the current screen's clean-UI proof, then
shoots and cleans up. Use
`node scripts/android.mjs shot builds/footage/device-debug.png --raw`
only when you are diagnosing the performance overlay itself.

When shooting by hand, arm **both** title and combat requests. That way you do
not guess the current screen wrong, and a scene change right before capture
cannot sneak debug UI in.

```bash
adb shell run-as com.crossplatformkorea.moonlitbeacon rm -f \
  files/store_capture_clean_title.request files/store_capture_clean_title.ready \
  files/store_capture_clean_combat.request files/store_capture_clean_combat.ready
adb shell run-as com.crossplatformkorea.moonlitbeacon touch \
  files/store_capture_clean_title.request \
  files/store_capture_clean_combat.request

# Recheck briefly until title-hidden or combat-hidden matching the current
# screen appears. Proof means the post-hide draw actually finished.
adb shell run-as com.crossplatformkorea.moonlitbeacon cat \
  files/store_capture_clean_title.ready
adb shell run-as com.crossplatformkorea.moonlitbeacon cat \
  files/store_capture_clean_combat.ready
```

```bash
adb shell screencap -p /sdcard/mb_shot.png
adb pull /sdcard/mb_shot.png builds/footage/device-shot.png
adb shell rm /sdcard/mb_shot.png

# After capture, clear only the handshake this run created.
adb shell run-as com.crossplatformkorea.moonlitbeacon rm -f \
  files/store_capture_clean_title.request files/store_capture_clean_title.ready \
  files/store_capture_clean_combat.request files/store_capture_clean_combat.ready
```

:::warning Do not use `adb exec-out ... > file.png` in PowerShell
PowerShell `>` applies a text encoding to the binary and corrupts the PNG.
You get `Invalid PNG signature 0xEFBBBFEFBFBD504E`.
Receive it with `screencap` → `pull` as above.
:::

Confirm it came out landscape. It must be **2424 × 1080**.

```bash
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x builds/footage/device-shot.png
```

## 4. Screen recording (`--record`)

```bash
mkdir -p builds/footage

# Keep both requests so debug UI cannot appear on a title↔combat switch during recording.
node scripts/android.mjs clean-ui arm

# Launch the app first and wait until it is landscape, then start recording.
adb shell monkey -p com.crossplatformkorea.moonlitbeacon -c android.intent.category.LAUNCHER 1
sleep 3
# Fail here and do not start recording if there is no title-hidden or combat-hidden proof.
node scripts/android.mjs clean-ui wait
adb shell screenrecord --time-limit 14 --bit-rate 16000000 /sdcard/clip.mp4
adb pull /sdcard/clip.mp4 builds/footage/chapter-XX-device.mp4
adb shell rm /sdcard/clip.mp4
node scripts/android.mjs clean-ui clear
```

:::danger If you do not launch the app first, it records lying on its side at 90°
`screenrecord` **freezes the display orientation at start.**
Start while the screen is portrait and the result is `1080 × 2424` with the
game on its side. Both cases were reproduced.

| Order | Result |
| --- | --- |
| Start recording → launch app | **1080 × 2424** (on its side) |
| Launch app → wait for landscape rotation → start recording | **2424 × 1080** (correct) |
:::

Know the limits too. **180 seconds max**, **no audio**.

`scrcpy 4.0` in this environment dies with an access violation (`0xC0000005`)
every time `--record` is attached. All five combinations failed. Use it for
mirroring only.

## 5. What to check by eye

Open the screenshot. If any of the following fails, that lesson is not done.

If the work is checking character, monster, item, VFX, or terrain quality, or
"every direction", first read the whole
[visual E2E evidence contract](../skills/moonlit-workflows/references/visual-e2e.md).
Report representative device, full production-PNG zoom, and automated checks
as separate evidence.

- [ ] Landscape 2424 × 1080
- [ ] Pixels are not mushy (mushy means `default_texture_filter` is `Linear`)
- [ ] No black bars left or right (bars mean `stretch/aspect` is `keep`)
- [ ] No debug strings, gray rectangles, default fonts, or placeholders
- [ ] No personal notifications in the status bar (Do Not Disturb if this is for recording)

## 6. If this is for capture

If a device clip is going into a lesson, tidy the phone first.

- Do Not Disturb (a notification means you recapture)
- Lengthen auto-sleep
- Turn on Developer Options "Show taps" — thumb position is visible, so
  control explanations are easier
- Do not leave the `adb` device serial on screen for long

How to shrink to repo size is in [`/record`](./record.md).
