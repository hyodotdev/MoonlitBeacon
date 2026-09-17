---
sidebar_position: 0
title: Lesson 1 recording script
---

# Lesson 1 — Recording script

[Lesson text](../../apps/docs/course/chapter-01.mdx) · [Plan](../plans/chapter-01-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 16 min 20 s |
| Segments | 18 |
| Shot | Editor · game window · **phone device screen (adb screenrecord)** · browser · terminal |
| Raw recording | `builds/footage/chapter-01-raw.mkv` |

Each segment keeps three lines: **On screen / Narration / Watch-outs**.
Narration is a sentence you can read as-is, so do not summarize or improvise — read it.
If you stumble, go back to the start of that segment and read again. You can cut in edit.

:::warning This script's section layout differs from the lesson text
The script was written against 7 sections (16 min 20 s), then the [lesson text](../../apps/docs/course/chapter-01.mdx)
grew to 11 sections. Section numbers do not match, so **treat the lesson text as the source of truth
and this script as narration copy only**. Whether to re-split the script into 11 sections is decided before recording.
:::

### Already shot

The two below are **already recorded as silent screen clips and committed to the repo.**
When you shoot the narrated episode, do not reshoot the same screens — use these masters.

| Segment | Repo clip (silent) | Narration master (1920×1080) |
| --- | --- | --- |
| 3. Editor settings | `apps/docs/static/video/chapter-01-editor.mp4` | `builds/footage/chapter-01-editor.mp4` |
| 4. Asset licenses | `apps/docs/static/video/chapter-01-assets.mp4` | `builds/footage/chapter-01-assets.mp4` |

There is already a device clip too — `builds/footage/chapter-01-title-device.mp4`.
The repo-sized cut is `apps/docs/static/video/chapter-01-title.mp4`.

:::info This episode's result is not an empty project
When Lesson 1 ends, **a finished title screen** runs on a phone.
It is not a "boring Lesson 1 that only does settings" — the course principle is that a game
is visible on screen from episode one. The whole script is written on that premise.
:::

---

## 1. Finished screen

### 00:00 – 00:55 · Title screen running on a phone

**On screen**: Pixel 10 device screen. Tap the app icon with the phone in landscape. A title screen appears with a beacon burning over a night forest and mist flowing, and the music fades up. Show the blinking "Tap to start" line for at least 3 seconds, then tap once and capture the beacon flaring.

**Narration**: "Hello. This is the first session of making Moonlit Beacon. The screen you are looking at is today's result. It is a phone screen, locked to landscape, a beacon burning over a night forest with mist flowing. Tap the screen and the beacon flares once. There is a reason we make this much in the first session. A typical game course Lesson 1 only does settings and ends. They put up one gray square, talk about resolution, and stop. Build it that way and ten episodes later there is still no game on screen. This course ends every episode in a state where that screen could be used as a store screenshot as-is. Starting today. So today's work is two things. Lock a project foundation you will not have to touch again for the next fifteen lessons, and stand one title screen on top of it."

**Watch-outs**: Recording must **start after the app is already up and the screen has rotated to landscape**. Start `adb shell screenrecord` in portrait and it locks at 1080 x 2424, so the game comes in lying on its side. Turn on Do Not Disturb so the phone status bar's notifications and carrier name do not stay on screen. Do not move to the next segment before the music fade-in finishes.

---

## 2. Check the official docs

### 00:55 – 03:00 · Compare with Godot's official docs

**On screen**: Browser on Godot's official `First 2D game / Setting up the project` page. Scroll to the paragraphs on window size and stretch and zoom. Then show the outline that splits Player / Mob / HUD into separate scenes.

**Narration**: "Before we touch settings, we will look at the official docs first. This is the first 2D game in Godot's official tutorial, specifically the project setup page. Two things we want to confirm here. First, the official example also locks window size and stretch before game logic. Starting with resolution today is not a strange order. Second, the official example splits player, mobs, and HUD into separate scenes. We use the same structure. Split scenes small and each file stays short, and fixing one later does not break another. We will also mark a difference. The official example is a keyboard game in a desktop window, surviving mobs for a long time. The Moonlit Beacon we will make is a game you hold landscape in both thumbs, lighting three beacons and escaping. We follow the official docs' concept order as-is. Nodes and scenes, instances, first script, input, signals, main scene, HUD. We skip none of them. Instead we put those concepts onto an Android game. Then we will actually make it."

**Watch-outs**: Confirm the version badge at the top of the docs is a 4.x stable, not a `latest` (dev) page. Check that the browser bookmark bar and other open tab titles have no personal info. Do not read the docs out loud as-is; summarize as in the narration above.

---

## 3. Implement in the editor

### 03:00 – 04:00 · Create the project and pick a renderer

**On screen**: Godot 4.7.1 Project Manager → `+ New`. Type `Moonlit Beacon` as the project name, set the path to `D:\...\MoonlitBeacon\apps\game`. Hover the three Renderer options (Forward+ / Mobile / Compatibility) in turn, then click **Compatibility** and `Create & Edit`.

**Narration**: "We create a new project in the Godot 4.7.1 project manager. The name is Moonlit Beacon, and the path is apps slash game inside the repository. We put it under apps because this repository is a monorepo. The game lives at apps slash game, the course docs site at apps slash docs, side by side. Here comes today's first important choice. The renderer. The default is Forward plus, which has the strongest 3D features but weaker mobile-device compatibility. There is also Mobile, but that renderer assumes a recent mobile GPU. We are making a 16-pixel 2D pixel-art game, and we want it to run on older phones if possible. So we pick Compatibility. As the name says, it has the widest compatibility, and a 2D pixel-art game needs none of Forward plus's features. Changing this later rewrites shader and lighting behavior wholesale, so locking it now is the right start. I will press Create and Edit."

**Watch-outs**: The Renderer default is Forward+, so **you must click and change it to Compatibility**. Before recording, clean the project manager recent-project list so private folder paths are not visible. Zoom the path field so `apps/game` is readable.

---

### 04:00 – 05:10 · Internal resolution 808 × 360 and landscape lock

**On screen**: `Project → Project Settings → Display → Window`. Turn on the top-right `Advanced Settings` toggle and enter 808 / 360 in Viewport Width / Height, 1616 / 720 in Window Width Override / Height Override. Then scroll down and set `Handheld → Orientation` to `Sensor Landscape`. Zoom the input fields.

**Narration**: "Go into Project Settings, Display, Window. You have to turn on Advanced Settings at the top right or the items you need will not all show. Put Viewport Width 808, Height 360. This is the internal resolution the game actually draws at. 808 is an unfamiliar number. It comes from my reference device. A Pixel 10 screen is 1080 by 2424 in portrait, and laid on its side it is 2424 by 1080. 2424 divided by 3 is 808, 1080 divided by 3 is 360. Exactly one third. It scales by an integer, so 16-pixel dots do not drift even half a pixel. And on a 16-pixel tile, 50 cells across and 22 down fill the screen with half a cell left over. That is a size that fits one whole arena on one screen. Below that, put 1616 in Window Width Override and 720 in Height Override. Exactly twice the internal resolution. This is the window size that appears when I test on my computer, not on a phone. Our game is an Android game, but during development it is much faster to run with F5 in the editor. Finally scroll down and change Handheld, Orientation to Sensor Landscape. As a value that is 4. However you hold the phone, the screen stays landscape, and both landscape directions are allowed. Stand it portrait and the game still does not stand up."

**Watch-outs**: Without `Advanced Settings` on, Override and Handheld items are not visible at all, so leave the toggle-on hand motion on screen. After typing numbers you must **press Enter to commit** or the values do not apply. `Orientation` has both Landscape and Sensor Landscape. Pick **Sensor Landscape** — plain Landscape allows only one direction. Put the 2424 divided by 3 = 808 calculation on screen as a caption.

---

### 05:10 – 06:05 · Stretch mode canvas_items and aspect expand

**On screen**: Same screen, `Stretch` below. Open the Mode dropdown, show `disabled / canvas_items / viewport`, then pick `canvas_items`. Open the Aspect dropdown, glance over the options, then pick `expand`.

**Narration**: "Right below is Stretch. Change Mode to canvas_items. viewport mode scales the whole screen as one, so even UI text breaks into stairs, not just the game view. canvas_items scales the game view while drawing UI at its original resolution, sharp. If you are putting UI on a pixel-art game, this is the right side. Next is today's most important decision. Change Aspect to expand. If this were a desktop game we would have picked keep. keep holds the aspect ratio and fills leftover space with black bars. Clean. But Android aspect ratios differ per device. 20 by 9, 19.5 by 9, 16 by 9, tablets even 4 by 3. Use keep and the black-bar thickness is different on every device. Then the game looks cheap. expand is different. Height 360 stays fixed, and width widens to that device's ratio. No bars at all, and on a wide phone the view is a little wider. A condition comes with it. Screen width is no longer fixed, so UI must always pin to edge anchors, and things the game truly needs must sit only inside a center safe area. This rule follows from today's title screen through the last episode."

**Watch-outs**: Leave a shot of the dropdown open showing the other options. Do not mix up `canvas_items` and `viewport` when speaking. **It is `expand`, not `keep`.** Following a desktop course, people habitually pick keep. These two values are used again in the error-demo segment, so remember where they are.

---

### 06:05 – 06:40 · Default Texture Filter = Nearest

**On screen**: `Project Settings → Rendering → Textures → Canvas Textures` → open the `Default Texture Filter` dropdown and pick `Nearest`.

**Narration**: "Next is rendering. Go to Rendering, Textures, Canvas Textures and change Default Texture Filter to Nearest. The default is Linear, which softly blends neighboring pixel colors when scaling up. Fine for a photo, but scale 16 by 16 pixel art three times and every edge smears. Nearest copies the nearest pixel color as-is, so square pixels stay square as they grow. This is the first setting to confirm in a pixel-art game, and in a moment we will deliberately revert it and show the difference ourselves."

**Watch-outs**: This item is also invisible unless `Advanced Settings` is on. Do not skip the phrase "the nearest pixel" — that is the reason for the name Nearest.

---

### 06:40 – 07:10 · Emulating touch with the mouse

**On screen**: `Project Settings → Input Devices → Pointing` → check `Emulate Touch From Mouse`. Close the settings window.

**Narration**: "One more setting. Emulate Touch From Mouse, under Input Devices, Pointing. Turn this on and mouse clicks and drags are also delivered as touch events. This game's real controls are virtual joysticks pushed with both thumbs, and baking an APK and putting it on a phone every time you develop takes a whole day. With this one setting you run F5 in the editor and drag with the mouse, and the virtual stick works as-is. But this is only a development convenience. Final confirmation is always on device. A mouse cannot press two fingers at once. Two-hand controls can only be tested properly on a phone."

**Watch-outs**: Do not omit the sentence "a mouse cannot press two fingers at once." If you do not mark that limit, viewers will think desktop testing is enough. Close the settings window so it saves to `project.godot`.

---

### 07:10 – 08:00 · Folder layout

**On screen**: In the FileSystem dock, right-click → `New Folder` and create `assets/third_party`, `assets/derived`, `scenes`, `scripts`, `resources`, `localization`, `docs`. Then switch to a file explorer and show the repository root. Point at `apps/game`, `apps/docs`, and outside those `_downloads/`, `_asset_sources/`, `builds/` in turn.

**Narration**: "We will make folders. Inside the project, assets slash third_party for files other people made, assets slash derived for files we make or process, then scenes, scripts, resources, localization, docs. Now look at the whole repository in a file explorer. Under apps, game and docs sit side by side. game is the Godot project, that is the root of res colon slash slash, and docs is this course site you are looking at. And outside apps there are three folders, underscore downloads, underscore asset_sources, builds. Why split them. The Ninja Adventure pack we will use is about 89 megabytes unzipped. Put that in the project as-is and Godot imports thousands of images and tracks we will never use. Opening the project gets slow every time, and the files you actually need are hard to find in the FileSystem dock. The habit of copying only the files you need is used as-is in real work. These three folders are not committed to git either."

**Watch-outs**: Showing every folder being created one by one is boring. Actually create two or three and show the rest already made. Make it visually clear that `_downloads/` and `_asset_sources/` are **outside** `res://` by showing the explorer address bar too. When you point at `apps/docs` and say "this course site," viewers connect it to the document they are watching.

---

### 08:00 – 09:20 · Download assets and confirm licenses

**On screen**: With the [Get assets](../../apps/docs/docs/assets/download-guide.md) page open in a browser, go to the Ninja Adventure page on itch.io and **point at the license text with the mouse and zoom**. Then zoom the CC0 mark on kenney.nl's Input Prompts Pixel page. Finally show the OFL license file in the Galmuri repository. Finish on an explorer view of six ZIPs sitting in `_downloads/`.

**Narration**: "Now we will get assets. We will use five things. The Ninja Adventure asset pack that covers graphics, music, and sound effects, Kenney Input Prompts Pixel for control-prompt icons, Kenney UI Audio for menu sounds, Kenney Impact Sounds for hit sounds, and Galmuri11, a Korean pixel font. The first four are CC0, the font is Open Font License 1.1. You must build one habit here. Do not trust a table someone else compiled for licenses — confirm with your own eyes on the distribution page. Like this. We confirmed this page says Creative Commons Zero, and we looked at whether commercial use is allowed, whether we may redistribute in a repository, and whether attribution is required. We record what we confirmed in the third-party assets doc, and copies of the license texts go in apps slash game slash docs slash licenses. All three are saved today. Postpone it until the credits screen and you will have to hunt which file had which license again. And one more. The Ninja Adventure page also hosts a Godot demo project. You may download it, but we do not use that project as the base of ours. If we start by editing someone else's project, this course becomes a course analyzing someone else's project, not making one ourselves. We use it only as a reference for how many sprite frames sit in what order. The ZIPs we got stay in underscore downloads as-is."

**Watch-outs**: If an itch.io checkout or Kenney donation screen appears, **immediately scroll or cut so amount fields and card-info fields do not stay on screen**. Confirm a logged-in account name and email are not exposed at the top. The sentence "we do not use the demo project as a base" is a core principle of this course, so read it clearly. The explorer shows six files (including the demo project) but **say there are five asset packs** — if the numbers do not match, viewers get confused.

---

### 09:20 – 10:50 · Assemble the title screen

**On screen**: With `res://scenes/menus/title_menu.tscn` open, walk the node tree top to bottom. Forest background → beacon pit → flame · spark · smoke particles → moonlight shafts → UI layer (title / prompt / version), toggling each off and on to show what each layer does. Finally run F5.

**Narration**: "Now we assemble today's result, the title screen. Look at the node tree from the top. The bottom layer is the forest floor. This is a texture baked as one sheet from tileset cuts, and one Sprite2D with texture repeat on fills the whole screen. You do not need a node per tile. On top of that we ring trees to make a clearing, and put a beacon pit in the middle. On the pit we stack three particles, flame, sparks, smoke. All of them run the frame sheets from the asset pack as particle animations. On top of that we put moonlight shafts, and at the very top we drift mist very slowly. That is the picture, and a UI layer sits separately on top. Title, a prompt to tap the screen, and a version number. The typeface is Galmuri11. This font is drawn on an 11-pixel grid, so we only use type sizes that are multiples of 11. Title 55, prompt 22, version 11. Use an awkward size like 12 or 20 and the dots smear. And the expand rule I mentioned earlier actually applies here. The picture shifts by leftover width when the screen is wider, to stay centered, and the letters are pinned to the screen edges with anchors. When you shift you must floor to integer pixels. A leftover half-pixel misaligns dots under nearest-neighbor scale. Let's run it."

**Watch-outs**: Toggling nodes off and on one by one is the core of this segment. Pause at least 1 second on each layer. Toggle while particles are running or the difference will not show. When you say Galmuri type sizes are "multiples of 11," put the three numbers 55 / 22 / 11 on screen as a caption. After running, drag the window a little wider with the mouse to show the background staying centered.

---

### 10:50 – 11:35 · Git init and .gitignore

**On screen**: In a terminal, run `git init -b main`, `git status`, `git add .`, `git commit -m "chore: Lesson 1"` in that order. In the middle, open `.gitignore` in the editor and zoom the `.godot/` line. Show that `_downloads/` and `builds/` are absent from `git status`.

**Narration**: "Next is Git. Initialize on the main branch, and look at git status before you commit. We will look at the gitignore file here for sure. The most important line is dot godot slash. This folder does not only hold import caches; it stores a file called export_credentials.cfg. The Android signing keystore password goes in there. We are making an Android game, so this is not someone else's problem. If it goes up to a public repository, it is a leak as-is. Conversely, export_presets.cfg only records which platforms and settings you export with, and has no sensitive values, so we commit that. The names are similar and easy to mix up, so remember credentials excluded, presets committed. The underscore downloads, underscore asset_sources, builds we made earlier are all on the exclude list too. Those folders do not show up in status at all. We confirmed, so we will add everything and commit."

**Watch-outs**: Shorten the terminal prompt so a username or personal path is not exposed at length. **Keep the order `git status` → confirm `.gitignore` → `git add` → `git commit`.** Commit first and you cannot stop an accident. Do not swap `credentials` and `presets` when speaking. **This segment must come before the next docs-site segment** — the next one depends on a commit.

---

### 11:35 – 12:20 · First run of the docs site

**On screen**: In a terminal, run `pnpm install`, `pnpm docs:dev`. A local docs site coming up in a browser. Zoom the "Last updated on ..." mark at the bottom of the page.

**Narration**: "This repository does not only hold the game; it also holds this course site you are looking at. That is apps slash docs, built with Docusaurus. pnpm install then pnpm docs dev and it comes up locally. I have to mention one order here. We just committed git first, then ran this. That order must not flip. Look at the bottom of the page and you will see a last-updated date; Docusaurus reads that value from the git log. Run a build with zero commits and there is no git history to read, so it fails. If you make a repository and try to bring the docs up first, this error is fairly hard to diagnose. Commit first, docs site next. Just remember the order."

**Watch-outs**: If `pnpm install` takes a long time, cut it in edit. You must include the shot zooming "Last updated on" — without it, why git is needed stays only in words. If there is time, shoot `pnpm docs:build` failing in a pre-commit state separately and insert it; it is much more convincing.

---

### 12:20 – 13:20 · Bake an APK and put it on a phone

**On screen**: In a terminal, run the commands below in order. Then cut to the phone device screen and show the app running landscape.

```bash
pnpm android:build
pnpm android:run
```

**Narration**: "Finally we will put it on a phone. Today we will not cover release steps like signing or version management. That gets its own episode later. Today just one thing: confirm that the title screen I made actually looks right on a real phone. First `android:build` exports the Android preset. That command also prepares the output folder and the build template. Then `android:run` installs and launches. There is one trap here. If you launch the app with adb shell am start and call the GodotApp activity directly, it fails. SecurityException, not exported. That activity is internal, so it is blocked from being called from outside. The real launcher activity name is GodotAppLauncher, but rather than memorizing the name it is easier to have the script throw a launcher intent with the monkey command. It is running. However you hold the phone it stays landscape, and it is the same screen we saw on the computer. This is today's result."

**Watch-outs**: Export fails if the build template and debug keystore are not set up. **Succeed once before recording, then shoot.** Actually run the `am start` failure once and show the error message — saying it is not enough. Hold the phone portrait for at least 3 seconds and show the screen staying landscape. If adb output exposes a long device serial, cover it in edit.

---

## 4. Show an error once and fix it

### 13:20 – 14:00 · Error demo 1 · Revert Nearest to Linear

**On screen**: Set `Project Settings → Rendering → Textures → Canvas Textures → Default Texture Filter` back to `Linear`. Run and zoom the scaled beacon pit and trees in the center of the frame. Go back to settings, change to `Nearest`, rerun, and show the same spot at the same zoom.

**Narration**: "Settings are done, so this time we will get it wrong on purpose. You have to see once what happens if you skip this setting, so later you can find the cause from the symptom alone. First we put Default Texture Filter back to Linear and run. Do you see. The tree edges and the beacon pit all smear and go blurry. You drew pixel art and it comes out like wet paint. This is the symptom beginners hit most, and the cause is almost always this one setting. Back to Nearest and run. Same image, same zoom, and the edges snap. This is correct."

**Watch-outs**: Linear and Nearest screens must be framed **at the same position, same zoom** or the difference will not show. Decide the zoom point before shooting and hit that point both times. Leave at least 3 seconds of still on each so edit can put them side by side. After reverting the setting, **restore Nearest before going to the next segment.**

---

### 14:00 – 14:45 · Error demo 2 · Stretch Aspect to keep

**On screen**: Change `Display → Window → Stretch → Aspect` to `keep`. Run and drag the window wide to show black bars on the left and right for at least 3 seconds. Then widen further until the bars thicken. Restore `expand` and repeat the same drag to confirm the view widens with no bars.

**Narration**: "Second error. This time we change Stretch Aspect to keep. Follow a desktop course and almost everyone picks this. Run and widen the window. Black bars appear left and right. Widen more and they get thicker. The game view does not squash, so this is not a wrong setting either. For a desktop game this side is actually right. The problem is Android. Phones have different aspect ratios, so on some phones the bar is thin and on others it is thick. From a user's view it just looks like the game cannot fill the screen. Back to expand and widen the same way. No bars. Instead the forest you see left and right got a little wider. The background art is shifting by leftover width to stay centered, and the letters are pinned to the edges with anchors, so their seats do not scatter at any width. This is the result we want."

**Watch-outs**: Hold the keep-state black bars at least 3 seconds. Pass too fast and viewers miss it. You must stretch the window extremely (more than 2× wide) for the difference to be certain. When the demo ends, **restore Aspect to `expand` and close the settings window to save** — forget to restore and shoot the next lesson, and you have to reshoot the previous episode. Do not drop the sentence "keep is not a wrong setting." The point of this demo is that the answer depends on the situation.

---

## 5. Use AI to confirm docs and licenses

### 14:45 – 15:20 · Check docs and license records

**On screen**: In the editor, open `apps/docs/docs/assets/manifest.md` and `apps/docs/docs/assets/third-party.md` side by side, and ask an AI assistant "Confirm that the distribution sites and licenses of the five asset packs we received are recorded in both docs with nothing missing." In the reply, find a missing line and fill it in.

**Narration**: "Usually this slot is an AI code review. But the only script we wrote today is the title screen, so there is not much to review. Instead we will check today's other result, the docs. With the asset manifest and the third-party assets doc open, we ask it to confirm that the five packs' distribution sites and license types are recorded with nothing missing. This kind of check, a person always skips a line. Look, it just pointed out that the path to the font license text copy is empty. I will fill it in. One principle here: do not write down a license type the AI told you and trust it as-is. Let it find whether a record is missing, but what the license is is always confirmed by a person on the distribution page."

**Watch-outs**: When showing file paths, make the whole `apps/docs/docs/assets/` visible — it is a monorepo, so `docs` twice is easy to mix up. Confirm the AI reply screen does not show other-project chat history or account info. Do not read the whole reply out loud; show fixing only the one item it flagged. Do not omit the sentence "license judgment is a person's job."

---

## 6. Manual test of completion criteria

### 15:20 – 16:00 · Confirm completion criteria

**On screen**: Put the lesson-note completion checklist on one side of the screen, and for each item confirm on the real screen and check the box. The last item is running `godot --headless --path apps/game --quit` in a terminal and showing exit code 0.

**Narration**: "To wrap up we will confirm the completion criteria one by one ourselves. First, the project runs with no errors. Look for no red lines in the output window. Second, the title screen comes out as the phone landscape screen as-is. We just confirmed that on device. Third, changing window width keeps the background centered and letters pinned to the edges. Fourth, pixel images do not blur. Fifth, tap the screen and the beacon flares and a confirm sound plays. Sixth, we downloaded assets into underscore downloads and the unzipped copies are in underscore asset_sources. Seventh, we confirmed all licenses and recorded them. Eighth, there is no asset ZIP inside res colon. Open apps slash game and there is not a single ZIP. Finally we open and close headless and check the exit code is 0. 0 means there is no structural problem in the project. All passed. From now on this project will not have to come back because of settings for the next fifteen lessons."

**Watch-outs**: You must include the screen of checking boxes (an edit-checklist item). If even one warning is in the output window when you run, stop shooting and fix it first. Reading items tends to speed up, so show the real screen at least 1 second per item. Show the exit code on screen with `echo $LASTEXITCODE`.

---

## 7. Homework

### 16:00 – 16:20 · This episode's homework and a preview of the next

**On screen**: Hold a still of the three homework items (at least 5 seconds). At the end put the next lesson's title on one line.

**Narration**: "Three homework items and we will wrap. First, change Stretch Aspect to keep, keep_width, keep_height each, and observe what changes when you adjust window width. After you confirm, you must put it back to expand. Second, change the window-size override to 2424 times 1080 and confirm that 808 times 360 scales up by exactly three. That is the real phone resolution. Third, inside the underscore asset_sources slash ninja_adventure folder, find where the monster sprites are and note the path. We use it when we make enemies in Lesson 8. Next time we cover nodes and scenes properly. We will pull today's beacon out as its own scene, and make the night-forest arena where the game actually happens. Thank you for your work."

**Watch-outs**: Hold the homework screen still at least 5 seconds. You must read the sentence "after you confirm, put it back to expand" — skip it and viewer projects enter the next episode still on keep. Leave about 2 seconds of space after the last greeting so edit can fade out naturally.

---

## Recording checklist

### Before recording starts

- [ ] Notifications off — turn on Focus / Do Not Disturb, quit messenger and mail clients
- [ ] **The phone too** Do Not Disturb — a personal notification on a device clip means you have to reshoot
- [ ] Lengthen the phone auto-sleep timeout generously
- [ ] Turn on "Show taps" in phone developer options (thumb position is visible)
- [ ] Confirm the device is attached with `adb devices`
- [ ] Launch the app first, rotate to landscape, then start `adb shell screenrecord`
- [ ] Succeed at Android export once (build template + debug keystore)
- [ ] `mkdir -p builds/footage builds/android`
- [ ] Confirm the browser bookmark bar has no personal info or internal links
- [ ] Open the browser in a new profile or guest window to block account name · email exposure
- [ ] Confirm the Godot project manager recent-project list has no private paths
- [ ] Shorten the terminal prompt (block username · full-path exposure)
- [ ] Clean desktop icons and the taskbar
- [ ] Mic gain test 30 seconds — play back and check noise and clipping
- [ ] Godot editor theme Dark, font size default + 2 ~ 3
- [ ] Show mouse cursor + click highlight on
- [ ] Confirm recording settings 1920 × 1080 / 60fps / mkv

### During recording

- [ ] 1 second still before each segment starts — an edit cut point
- [ ] Show the hand motion of pressing Enter to commit after typing a setting
- [ ] Error-demo segments hold the wrong screen and the correct screen at least 3 seconds each
- [ ] The `git init` → commit segment is **before** the docs-site segment
- [ ] Block amount · payment-info exposure on itch.io / Kenney checkout · donation screens
- [ ] Device serial in adb output is not exposed at length
- [ ] If speech tangles, start that segment over — do not try to splice

### After recording ends

- [ ] Confirm `Default Texture Filter` is restored to `Nearest`
- [ ] Confirm `Stretch Aspect` is restored to **`expand`**
- [ ] Open `project.godot` and confirm the settings are still there
      (808 × 360 / expand / orientation=4 / emulate_touch_from_mouse)
- [ ] Confirm the raw file saved as `builds/footage/chapter-01-raw.mkv`
- [ ] Confirm the device clip is **landscape 2424 × 1080** (1080 × 2424 means you started recording before launching the app)
- [ ] Open the file and play the first and last 10 seconds to confirm video and audio both landed
- [ ] Confirm editor settings were restored to the pre-shoot backup
      (`editor_language`, `main_font_size`, `single_window_mode`)
      You must **close Godot first** then restore. On quit it writes this file again.

---

## This episode's homework

1. Change `Stretch Aspect` to `keep`, `keep_width`, `keep_height` and
   observe what changes when you adjust window width.
   **After you confirm, you must put it back to `expand`.**
2. Change the window-size override to `2424 × 1080` and confirm that 808 × 360
   scales up by exactly 3. This value is a Pixel 10's real landscape resolution.
   After confirming, put it back to `1616 × 720`.
3. Inside `_asset_sources/ninja_adventure/`, find where the **monster sprites** are and
   note the path. (We use it when we make enemies in Lesson 8.)
