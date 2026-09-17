---
sidebar_position: 2
title: Lesson 3 recording script
---

# Lesson 3 — Recording script

[Lesson text](../../apps/docs/course/chapter-03.mdx) · [Plan](../plans/chapter-03-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 18 min |
| Segments | 9 |
| Shot | Editor · game window · **phone device** |
| Render sources | `builds/footage/chapter-03-*.avi` · `chapter-03-device-transition.mp4` |

**Section numbers are 1:1 with the [lesson text](../../apps/docs/course/chapter-03.mdx).**

## Already shot

| Section | Repo clip (silent · captions) | Render source |
| --- | --- | --- |
| 1. Finished screen | `chapter-03-transition.mp4` | `builds/footage/chapter-03-device-transition.mp4` (device source) |
| 2. What an instance is | `chapter-03-instances.mp4` | `builds/take/c3_blue.avi` (temporary variant render) |
| 5. Implement | `chapter-03-arena.mp4` | `builds/footage/chapter-03-arena.avi` |

## 1. Finished screen (0:00 ~ 0:50)

**On screen** — `chapter-03-transition.mp4`

**Narration** — This is what we will make this session. Tap the title screen and the beacon flares
once, then we go to the night-forest arena. Three beacons in different spots burn on their own beats.
Until now there was one screen; from today there are two.

**Watch-outs** — This is a device clip. Show it actually running on a phone first.

## 2. What an instance is (0:50 ~ 2:50)

**On screen** — Scene dock of `arena.tscn`. Click the three slate icons one by one

**Narration** — An instance is a saved scene slotted into another scene.
We already used it twice last session. The arena held the night forest and the beacon as instances.
What we learn new today is placing one several times, differently at each spot.

**On screen** — `chapter-03-instances.mp4`

**Narration** — The three point at the same file. What you are looking at
is the result of opening beacon.tscn and changing the light color exactly once.
We did not touch the arena. All three follow.
This is why we split scenes last session.
If we had copied three copies, we would have to fix three places now, and we would definitely skip one.

**Watch-outs** — At the moment the color changes, put all three on one screen. Close-up on one and
"all three" does not show.

## 3. Check the official docs (2:50 ~ 3:20)

**On screen** — Browser. Godot official `Instancing` page

**Narration** — The official docs drop several balls to show it. The concept is the same.
One original, several placed, each with different values.
Today we look at Editing instances and Editable children together with that.

## 4. What has to follow when there are three beacons (3:20 ~ 6:00)

**On screen** — Place three beacons with no other action. Two of them burning in the grass

**Narration** — Let's just put three down. Awkward, right.
Two are burning in the middle of the grass. There is still only one clearing in the center.
Because one clearing is baked into the night-forest scene.

**Watch-outs** — **Show the wrong state on purpose first.** Skip that shot and
why we move the clearing will not land.

**Narration (continued)** — A clearing follows if there is a beacon.
So the beacon scene should hold it.
Same judgment as last session gathering the pit and flames into the beacon scene.
Ask "is this part of the beacon?" and if yes, put it inside.

### 4-1. Move the clearing

**On screen** — Cut `Clearing` `Scorch` and paste in front of `Pit` in `beacon.tscn`.
Positions to (0,0) and (0,3). Type the multiplied result into Modulate

**Narration** — The beacon was at 404, 250, so subtract that and it is 0, 0.
Night tint is the same as last session's pit: write the multiplied result directly.

**Watch-outs** — You must include the nested-resource warning.
The scorch uses a GradientTexture2D and that in turn references a Gradient.
Edit the `.tscn` by hand, miss this, and the scene will not even open.
**We actually hit this while making this course.** Put the error message on screen.

### 4-2. Draw order

**On screen** — Right after the move, the clearing covering grass and trees → `z_index` to -1 → correct

**Narration** — Move and run and the clearing covers grass and trees.
Because the beacon is a sibling of the forest and later in the tree. Later draws on top.
Lock the floor layer with z_index. Forest Ground and beacon Clearing, Scorch to -1.
Same z_index uses tree order, so the forest is earlier, ground draws first, clearing sits on top.

## 5. Implement (6:00 ~ 14:30)

### 5-1. Place three beacons

**On screen** — Chain icon twice more to instance. Rename West/North/East.
Type position and scale in the inspector

**Narration** — Attach twice more with the chain icon.
Change the names to BeaconWest, BeaconNorth, BeaconEast.
Leave them Beacon2, Beacon3 and later in scripts you will not know which is which.
Different sizes are not for looks. In top-down, up is farther.
Make the north beacon smaller and the screen gets depth.

**On screen** — Zoom the revert arrow that appears next to a property whose value you changed

**Narration** — Change a value and a revert arrow attaches next to the property.
That mark means you overwrote it differently from the original. Press it and you can revert to the original.
Only properties with this mark are stored on the instance. Everything else follows the original.
That is why fixing beacon.tscn changes all three together.

**Watch-outs** — Zoom this arrow and show it at least 3 seconds. It is the core of instancing.

### 5-2. The one-beat flicker problem

**On screen** — Three beacons flickering in perfect unison (run as-is on purpose)

**Narration** — Run at this point and something feels off.
All three flicker in perfectly the same beat. Of course.
They all started the same animation at the same instant.
Three real campfires do not sway on the same beat.

**On screen** — Right-click `BeaconWest` → `Editable Children` → insides unfold →
turn it on for each of the three instances and give `Flicker` different Speed Scale

**Narration** — Flicker is a node inside the beacon scene, so it does not show in the inspector.
Right-click, turn on Editable Children, and the insides unfold.
You have to turn it on per instance, so three times.
Give 0.87, 1.24, 1.03. Same animation at different speeds, so
they offset from the start and drift further apart.

**Watch-outs** — You must say Editable Children is debt.
The instant you turn it on, that instance depends on inner structure. Rename Flicker later and
the arena silently breaks. When a script attaches in Lesson 4, we revert this.

### 5-3. Arena music

**On screen** — Add `AudioStreamPlayer` → `arena_theme.ogg` → check Loop on the Import tab

**Narration** — Go to the arena and title music cuts. A silent screen looks unfinished.
We put one track in. Volume -11, autoplay on.
The important part is the import setting. The default is loop off, so
leave it off and 48 seconds later the music ends and it goes quiet.

**On screen** — Measurement table of eight candidate tracks

**Narration** — Pick a track by name and you will be wrong.
Among the candidates there is a track called Clearing. We are making a forest clearing, so
by name it looks like the answer. Measure it and the last 3 seconds drop to 36% of the body —
a fade-out. Loop it and it dies down and pops back every time.
What we picked is Chill. The end is not cut, and among the eight it has the smallest swing in loudness.
Arena music has to sit under play, so the side without big waves is right.

**Watch-outs** — Also mark that you must not pick by looking at one column.
Look only at spectral centroid and The Cave is lower, but that track has the most highs and a large swing.

### 5-4. Center the arena on screen too

**On screen** — Narrow the window width and the arena lists to one side → attach `arena.gd` and fix

**Narration** — In Lesson 1 we locked stretch aspect to expand.
Height 360 is fixed and only width widens to the device ratio.
So we have to push the stage to screen center, and the title has that and the arena does not.
A Pixel 10 lines up exactly so it does not show, but on a 16:9 phone it lists.

**Watch-outs** — You must change window width and show the listing. Look only at a Pixel 10 screen and
it looks like there is no problem.

**Narration (continued)** — The math is the same as the title.
Use the same formula in two places and later you will fix only one, so we pull it into screen.gd.
The arena root is Node2D, so pushing only itself moves the forest and all three beacons together.
The title root is Control, so you have to push forest and beacon separately.

### 5-5. Title to arena

**On screen** — Add three places in `title_menu.gd`. Run and confirm the transition

**Narration** — The title already emits a start_requested signal when you tap the screen.
It has been there since Lesson 1 and nobody was listening. Now we listen.
change_scene_to_file tears the current scene down wholesale and puts the new scene up.
The title's forest and beacon disappear, and the arena makes its own new.

**On screen** — The screen freezing on the pre-fix transition → measured frame time →
put in a music fade-out and measure again

**Narration** — Leave it like this and at the moment of the switch the screen stops for 181 milliseconds. That is 11 frames.
When AudioStreamPlayer leaves the tree, the audio thread waits 150 milliseconds for teardown,
and that lands as-is on the scene-swap frame.
Turn the sound off first. Fade the music down over 0.55 seconds from the tap and
by the time the beacon flourish ends, the sound is already gone. Measure again and it is 27 milliseconds.

**Watch-outs** — Put the measured values on screen. 181 → 27 is better than the words "it got smoother."

**On screen** — One transition frame flashing gray → Default Clear Color to night color

**Narration** — One more. On the one frame where the scene changes, Godot's default background color,
gray, is visible. A gray flash in a night-forest game jumps out.
Change Default Clear Color to the night color in Project Settings and
the transition happens in the dark and you do not see it.

**Narration (continued)** — It is the same file, so you could call directly without a signal.
But in Lesson 9, when a scene that manages the whole game appears, that scene will receive this signal,
read the save, set difficulty, then bring the arena up.
The title screen should only say "I want to start," and not know what comes next.
Write one more line now and what you have to change then is one line.

## 6. Confirm (14:30 ~ 15:10)

**On screen** — Terminal `pnpm game:check` · check the checklist against the Scene dock

**Narration** — Confirm there are three instances, each with different values,
and that no clearing remains in the forest. Exit code 0.

## 7. Get it wrong on purpose (15:10 ~ 16:40)

**On screen** — Four things in turn

**Narration** — First, revert all Speed Scale to 1.0 and all three are one beat. Mechanical.
Second, set Clearing's z_index to 0 and the clearing covers grass and trees.
You can see that the beacon is later than the forest.
Third, double the pit size in beacon.tscn and all three get bigger.
We did not even touch the arena.
Fourth, press the revert arrow next to BeaconNorth's Scale and it goes back to original 1.0.
Look only at the arrows and you know which values were overwritten.

## 8~9. Completion criteria and homework (16:40 ~ 18:00)

**On screen** — Lesson-text checklist

**Narration** — Please do homework 1. How many seconds to place a fourth beacon.
Think how many minutes it would have taken if we had not extracted the scene last session, and
you will know why Lessons 2 and 3 are in this order.
3 is a method used often during development. Change the main scene to the arena and
you can look at that screen directly without going through the title every time.
