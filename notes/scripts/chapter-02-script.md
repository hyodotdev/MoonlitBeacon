---
sidebar_position: 1
title: Lesson 2 recording script
---

# Lesson 2 — Recording script

[Lesson text](../../apps/docs/course/chapter-02.mdx) · [Plan](../plans/chapter-02-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 16 min |
| Segments | 9 (section 5 has 11 subsections) |
| Shot | Editor · game window |
| Render sources | `builds/footage/c2_*.avi` (Movie Maker) |

**Section numbers are 1:1 with the [lesson text](../../apps/docs/course/chapter-02.mdx).**
The Lesson 1 script drifted because the lesson text grew later. From Lesson 2 on, when the
lesson text is edited, this script's numbers are edited with it.

## Already shot

Two silent screen clips are already rendered and in the repo.
When you shoot the narrated episode, do not reshoot the same screens.

| Section | Repo clip (silent · captions) | Render source |
| --- | --- | --- |
| 1. Finished screen | `apps/docs/static/video/chapter-02-arena.mp4` | `builds/footage/chapter-02-arena.avi` |
| 5. Implement | `apps/docs/static/video/chapter-02-compose.mp4` | `builds/footage/c2_forest_only.avi` · `c2_beacon_only.avi` · `c2_arena.avi` |

## 1. Finished screen (0:00 ~ 0:50)

**On screen** — `chapter-02-arena.mp4`

**Narration** — This is the screen we will make this session. Moonlight comes down, mist flows,
and a beacon burns in the middle of the clearing. It looks almost the same as last session's
title screen. That is correct. This lesson is not a lesson that changes appearance; it is a
lesson that changes the same screen into a shape you can reuse.

**Watch-outs** — Admit "it looks almost the same" first, then go in.
Do not give the viewer time to think "what even changed."

## 2. Nodes and scenes (0:50 ~ 2:30)

**On screen** — Editor Scene dock. Open `beacon.tscn` and click nodes one by one
(the flicker `AnimationPlayer` is attached in 5-7, so leave it out of the explanation at this point)

**Narration** — Godot has only two big concepts. Nodes and scenes.
A node is a part that does one job. A Sprite2D that draws one picture,
a PointLight2D that emits light, a GPUParticles2D that throws sparks. Each does only one thing.
A scene is those nodes bundled and saved as a file. And here is the important part:
a saved scene can be used like a node again.

**Narration (continued)** — Why bother splitting. Next session we place three beacons.
If the beacon stays buried inside the title screen like now, the only option is copy and paste three copies.
Then every time you change flame color once you have to fix three places, and you will definitely skip one.

**Watch-outs** — When you click a node, show the inspector changing.
"Each part has different knobs" must be visible by eye.

## 3. Check the official docs (2:30 ~ 3:00)

**On screen** — Browser. Godot official `Nodes and scenes` page

**Narration** — The official docs explain with a one-label scene.
We do the opposite: we tear apart a 1,296-node screen we already made, backwards.
Splitting scenes in a real project is usually closer to this side.
Nobody starts with a perfect split from the beginning.

## 4. The beacon is split across two places (3:00 ~ 5:30)

**On screen** — Fully expand the Scene dock of Lesson 1's `title_menu.tscn`. Click
`Forest/Beacon` and `Fire/Flames` in turn

**Narration** — Before we start work, let's open last session's scene once.
Where is the beacon. The pit and the light are inside the forest.
But the flames and smoke are here, inside a separate CanvasLayer called Fire.
One beacon is split across two places.

**Watch-outs** — Here **fail on purpose once.**
Right-click `Beacon`, press Save Branch as Scene, save, open that file, and show
a pile of stones with no fire. Then undo (Ctrl+Z).
Say it without this shot and the viewer just moves on.

### 4-1. The culprit is CanvasModulate

**On screen** — Click `Forest/NightTint`. Briefly turn the inspector Color to white

**Narration** — NightTint inside the forest is a CanvasModulate node.
It is a node that tints one whole canvas. Turn this to white and the forest becomes noon.
Convenient. So convenient it is a problem.
Everything on the same canvas gets tinted. Put the flames in the forest and the flames go blue too.
A blue flame is not a beacon. That is why last session we parked only the flames on a separate layer.

### 4-2. But that method dies in Lesson 3

**On screen** — Dragging the `position` slider on `Fire/Flames` does not move the on-screen
flames in arena coordinates

**Narration** — A CanvasLayer is a separate draw layer fixed to the screen.
It is a node for things that must stay put even if the camera moves, like HUD or captions.
So the flames you put in it are outside arena space.
Change the beacon position and the flames do not follow.
Next session we have to put three beacons in different spots, and this structure cannot do that.

**Watch-outs** — Say this and they will not believe it. You must show on screen that
dragging the slider still leaves the flames in place.

### 4-3. What we use instead

**On screen** — The comparison table in the lesson text

**Narration** — CanvasModulate is a node, modulate is a property.
CanvasModulate tints everything on the same canvas,
modulate tints only itself and its children.
Make the beacon a sibling of the forest and only the forest goes blue; the beacon stays itself.
No CanvasLayer needed, so the beacon remains an ordinary Node2D and position works.

**Narration (continued)** — Nobody knows this in advance.
When we made this course we built with CanvasModulate first,
then got stuck trying to move the beacon and came back.
Fixing structure after the problem blows up is the normal order.

## 5. Implement (5:30 ~ 14:20)

**On screen** — Show `chapter-02-compose.mp4` first, then cut to the editor

**Narration** — The three screens you just saw are each a different file.
A file with only the forest, a file with only the beacon, and a file that combines those two.
The combined file has not a single picture. It only points.

**Narration (continued)** — Order matters.
Change the night tint first, gather the beacon, then extract scenes.
Change the order and the screen goes blue in the middle, and you cannot tell what you did wrong.

### 5-1. Move the night tint

**On screen** — Delete `NightTint` → forest brightens → type values into `Forest` Modulate → dark again

**Narration** — Delete NightTint. The forest becomes noon.
Select Forest, find Modulate in the inspector, and put 0.315, 0.35, 0.57.
Night again. It should look the same as what we just deleted.
If the color looks different here, you typed the values wrong.

### 5-2. Gather the beacon

**On screen** — Drag the four `Smoke` `Embers` `Flame` `Glow` under `Forest/Beacon`

**Narration** — Move the four flame nodes under the beacon.
The flames went blue. Do not be surprised. They are children of the forest now, so of course.
Next step we pull them out.

**Watch-outs** — You must show **coordinates jumping** at the moment of the move.
Inside a CanvasLayer they were screen coordinates, so Godot does not correct them.
Leave the shot of lining the flames back up over the pit.

### 5-3. Pull it out of the forest

**On screen** — Drag `Beacon` out of `Forest`. Flames return to orange

**Narration** — Now we pull the beacon out of the forest. Making it a sibling.
The flames came back to orange.
Because modulate only descends to children.
What we just saw in the table just happened in front of you.
Position 404, 250. Internal resolution is 808 times 360, so horizontally it is exactly center.
Delete the Fire layer that is now an empty shell.

**Watch-outs** — The moment the color returns is this lesson's climax.
Leave the screen still 1–2 seconds right after the drag.

### 5-4. Catch the pit color

**On screen** — Type 0.258 / 0.28 / 0.45 into `Pit` Modulate

**Narration** — Only the pit is left as bright as noon.
It used to pass through CanvasModulate too, and now it is outside it.
Do the multiply by hand and put it in directly. 0.82 times 0.315 is 0.258.
The forest is right and the pit is right. Looks done. One more left.

### 5-5. The clearing died

**On screen** — Lesson 1 frame and the current frame side by side. Zoom only the clearing

**Narration** — We matched the forest and the pit, but put it next to Lesson 1 and the clearing
has died to ash-gray. That warm glow around the campfire is gone.
Not because we typed the color wrong. The two methods handle light in a different order.
CanvasModulate draws the original color, puts light on, then multiplies night tint on the whole result.
modulate first multiplies night tint and puts light on the darkened picture.
Light is shining on a darkened floor, so no matter how much you brighten it, it does not get as bright as before.

**On screen** — Measured table (forest outside the light matches; only the clearing drops)

**Narration** — Measure and the unlit forest is identical. Only the clearing drops.
Give the light that much more energy. 3.2 times.
It is not a number that falls out of a calculation; we put a few in and matched.
If your night tint is different, the multiplier is different too. Do not memorize it.

**Watch-outs** — "Change structure and you must recapture the light" is this subsection's one line.
Unlit areas match on their own, so it is easy to look only at the forest and move on as done.

### 5-6. Beacon as a scene

**On screen** — Right-click `Beacon` → `Save Branch as Scene`. The moment it folds into a slate icon

**Narration** — Only now can we extract it as a scene. It is gathered in one place.
Press Save Branch as Scene and save as scenes/objectives/beacon.tscn.
After you save, that seat folds into one movie-slate icon.
The child nodes are gone. They were not deleted; they moved to another file.

**Watch-outs** — You must leave the fold on screen.
This is where the most people go "wait, where did my nodes go."

**Narration (continued)** — The root is Node2D. You will want the pit Sprite2D as the root,
but then touching the pit drags flame and light with it.
Keep a Node2D that draws nothing as the root.

### 5-7. Move flicker into the beacon

**On screen** — Putting `energy` 3.2× in the inspector does not change the screen

**Narration** — Now we should raise energy. Let's put it in. 3.2 times is 4.64.
Nothing happens.
Because BeaconFx overwrites Light energy with an animation every frame.
The value written in the scene becomes a dead setting the instant the animation starts.

**Watch-outs** — You must leave this shot. Put the value in, run, show it does not change.
Said in words it slides by; lived once it is never forgotten.

**Narration (continued)** — Then should we fix the keyframes. Then there are two places to touch.
The title's keyframes, and energy on beacon.tscn that the arena will use.
Exactly what this lesson teaches you not to do.
Flicker is part of why a beacon is a beacon. The beacon scene should hold it.

**On screen** — Cut `flicker` and attach it as a `Flicker` AnimationPlayer on `beacon.tscn`.
The path shortens one step. Keyframes 3.2×. Autoplay on.
Title `BeaconFx` keeps only `flare` and Autoplay off

**Narration** — What stays on the title is only flare, the big burn when you tap.
That flourish exists only on the title, so it belongs there.
Give flare energy the same 3.2 times. Skip it and a tap actually darkens it.

**On screen** — Delete the one `queue(&"flicker")` line in `title_menu.gd`

**Narration** — Delete one line in the script. flicker is no longer on BeaconFx.
Leave it and it looks for a missing animation and errors at runtime.
The beacon keeps running its own flicker, so when flare ends it comes back on its own.
The later one in the tree wins.

**On screen** — Run the arena and the beacon flickers

**Narration** — There is a bonus. The arena beacon now flickers too.
It was still a moment ago. The beacon scene holds it, so it follows wherever it is used.

### 5-8. The flames washed out

**On screen** — Lesson 1 flames and current flames zoomed side by side (beacon-only 3× crop)

**Narration** — We raised the light and this time flame color blew out.
In Lesson 1 you could see deep orange, a red wick, and smoke clearly,
and now the whole thing is a pale yellow blob.
Because the beacon's light is shining on its own flames too.
In Lesson 1 the flames sat on a separate CanvasLayer, so 2D lights never reached them at all.
This came along when we merged onto one canvas.

**On screen** — Changing `light_mask` to 0 on `Smoke` `Embers` `Flame` `Glow`.
Then show that mist and moonlight shafts in `night_forest.tscn` are already 0

**Narration** — We cannot go back to a CanvasLayer, so we use a light mask.
Everything drawn has a light_mask, and a light has a range item cull mask.
At least one bit has to overlap for light to hit. Set 0 and no bits are on, so it does not hit.
Change the four flame nodes' light_mask to 0.
Leave the pit as-is. In Lesson 1 the pit was inside the forest too, so it received light.
Firelight lingering on stone is the right picture.

**Narration (continued)** — This is not actually a new rule.
Open the night-forest scene and mist, moonlight shafts, motes, and the vignette are all light_mask 0.
They glow on their own too. We apply the same rule to the beacon.

**Watch-outs** — You must show the zoomed comparison. On a shrunk screen the difference is hard to see.

**Narration (continued)** — The flame picture is already drawn as "bright fire."
Add more light on top and it does not get brighter; the color washes out.
Do not shine light on something that already glows — a rule used often in 2D lighting.

### 5-9. Night forest as a scene

**On screen** — Save `Forest` the same way. Rename the root `NightForest`. Show file size

**Narration** — This side is 1,296 nodes. Every tree and every blade of grass is a node.
The file is over ten thousand lines. It is not a file you open to read, and you will not need to.
This is exactly the kind of thing you should extract as a scene. Copy it into two copies and
nobody knows which one is real.

### 5-10. Make the arena

**On screen** — `Scene ▸ New Scene` → `Node2D` → name `Arena` → chain icon twice

**Narration** — Make a new scene, root Node2D, name Arena.
The chain-shaped icon at the top of the Scene dock is Instantiate Child Scene.
Press it, pick the night forest, press it once more, pick the beacon. Position 404, 250.

**On screen** — Open `arena.tscn` in a text editor

**Narration** — Open the saved file and it is 11 lines. That is all.
Two lines point at other files, one line decides where to put the beacon.
There is not a single line of actual content.

**Watch-outs** — This 11-line screen is the most important single shot in this whole lesson.
Show it long enough.

### 5-11. Rebuild the title

**On screen** — In `title_menu.tscn`, delete forest · beacon and replace with instances. Compare line counts

**Narration** — Do not stop here. Right now the title has its own forest and
the arena uses another forest. Two copies of the forest.
Delete on the title too and attach instances, and an eleven-thousand-line file shrinks to 201 lines.

**On screen** — Open `BeaconFx` and two tracks show red → fix paths

**Narration** — Animations remember their target nodes as path strings.
We moved nodes, so two of them are wrong. The ones shown in red.
The scary part is there is no error. The game runs fine and only the flame does not sway.

**Watch-outs** — Run once **without** fixing the paths and show **the flame not swaying**, then fix.
That contrast is how you deliver why a quiet failure is scary.

**On screen** — Fix the three `@onready` lines in `title_menu.gd`

**Narration** — Change the paths the script uses to find nodes too.
This side errors the instant you run if it is wrong. So it is actually safer.
The dangerous side is the animation that fails quietly.

## 6. Confirm (14:20 ~ 15:00)

**On screen** — `pnpm game:check` in a terminal

**Narration** — The line-count orders of magnitude of the four files just have to match.
If the title is still in the ten-thousands, you skipped 5-11.
Finally confirm it opens with no errors from the command line. Exit code 0.

## 7. Get it wrong on purpose (15:00 ~ 15:40)

**On screen** — Run three things in turn

**Narration** — First, move the beacon to a child of the forest and modulate descends and it goes blue.
Second, turn modulate white and put a CanvasModulate in, and even the sibling beacon goes blue.
Because it is the same canvas. Where it sits in the scene tree
is how far the color spreads.
Third, change the pit picture in beacon.tscn and both the arena and the title change.
That one line is what we gained this lesson.
Fourth, revert Flicker's energy keyframes to the pre-3.2× values and
the clearing goes ash-gray again. The forest stays.
You can see by eye that only where light hits is off.
Fifth, change Flame's light_mask to 1 and the flame goes pale.
Zoom and you see the red wick and smoke are gone.

## 8~9. Completion criteria and homework (15:40 ~ 16:00)

**On screen** — Lesson-text checklist

**Narration** — Confirm the checklist one by one.
Homework 1 is confirming once more what you lived in 5-7.
Change the light's color and both sides change, but energy changes on neither.
Because Flicker overwrites it. To change it you have to fix the keyframes.
Homework 2 is prep for next session.
Attach one more beacon and if two burn on their own, Lesson 3 prep is done.
