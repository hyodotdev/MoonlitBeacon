---
slug: /
sidebar_position: 0
title: Course overview
---

# Making Moonlit Beacon

This course takes you from a blank Godot 4 project to **installing the game on a
phone and shipping it on itch.io**. There are 16 lessons in total.

The game you will make is **Moonlit Beacon**. It is a 2D top-down avoidance game:
you light three beacons in a night forest, dodge the spirits that chase you, and
escape through the moonlight gate. You hold the phone in landscape and play with
both thumbs.

:::info This course builds the original 90-second game, not the current expanded one
Following all sixteen lessons produces the first complete build (version 1.0.0):
three beacons, the three enemy kinds plus the guardian from Lesson 13, a
moonlight gate, and a 90-second run. The game this repository ships today
grew from there — more areas, weapons, and endless
cycles — and looks different from the lesson screenshots. The lessons teach the
foundation that game was built on.
:::

| | |
| --- | --- |
| Engine | Godot 4.7.1 minimum · 4.7.2 recommended · GDScript |
| Screen | Landscape lock, internal resolution 808 × 360 |
| Controls | Move with the left thumb, dash with the right thumb |
| Release | Android APK · itch.io |
| Assets | All free (CC0 · OFL · attributed NEXON font) |

## The promise of this course

**When each lesson ends, you can see a game on screen.**

Most game courses spend the first few lessons on setup and gray rectangles. This
one does not. After Lesson 1, a title screen is already running on the phone,
and that screen is good enough to use as a store screenshot. The same is true
for every lesson after that.

The last column of each lesson is **what will be on your screen when you finish
that lesson**. If that screen is not there, the lesson is not done.

## Syllabus

| | What you learn | What you see when this lesson is done |
| --- | --- | --- |
| [**Lesson 1**](./chapter-01.mdx) | Project setup · Assets and licenses · Title screen | A title screen on the phone: a beacon burning over a night forest, the title, and a blinking "Tap to start" |
| [**Lesson 2**](./chapter-02.mdx) | Nodes and scenes | In a night-forest clearing with moonlight and drifting mist, one beacon burns with flame, embers, and smoke |
| [**Lesson 3**](./chapter-03.mdx) | Instances | Tapping the title takes you into the arena, where three beacons in different spots burn at the same time |
| [**Lesson 4**](./chapter-04.mdx) | Your first script | Three unlit beacons catch fire one after another, and the forest moonlight brightens a step with each one |
| [**Lesson 5**](./chapter-05.mdx) | The player scene and animation | A ninja stands beside a beacon, casting a shadow and playing a breathing idle |
| [**Lesson 6**](./chapter-06.mdx) | Handling input | Pressing the lower left of the screen with a thumb brings up a joystick, and the ninja walks in that direction |
| [**Lesson 7**](./chapter-07.mdx) | Signals | Standing next to a beacon fills a light ring at your feet, and the beacon flares when the ring completes |
| [**Lesson 8**](./chapter-08.mdx) | Creating enemies | A spirit appears from the dark, chases the ninja, and the screen flashes red on contact |
| [**Lesson 9**](./chapter-09.mdx) | Start and end of a run | Lighting every beacon opens a moonlight gate at the far end of the forest; walking in shows the victory panel |
| [**Lesson 10**](./chapter-10.mdx) | On-screen information | Three hearts, remaining time, and Beacons 0/3 appear in wooden UI, and the timer counts down |
| [**Lesson 11**](./chapter-11.mdx) | Install and play on a phone | Tapping the home-screen icon launches the game in landscape, and you can play a full run |
| [**Lesson 12**](./chapter-12.mdx) | Dash | Flicking the stick with the right thumb sends the ninja through the spirits with an afterimage |
| [**Lesson 13**](./chapter-13.mdx) | Three enemy types and the final guardian | The moment the last beacon lights, the music changes and a huge guardian cuts through the forest |
| [**Lesson 14**](./chapter-14.mdx) | Score and saving records | On the results screen the score ticks up line by line, and an S-rank stamp lands at the end |
| [**Lesson 15**](./chapter-15.mdx) | Settings · Korean and English · Credits | Switching the language to English in the settings window changes every on-screen string in place |
| [**Lesson 16**](./chapter-16.mdx) | Wrap-up and release | A signed APK is installed and running on the phone, and the game is live on its itch.io page |

## Your learning path

Every lesson runs one loop: **build** the feature in your blank project,
**explain** to yourself why it works that way, **modify** it in the exercises
until it breaks, then **verify** it against the completion checklist. The
checklist is the exam; the exercises are where the learning happens.

After each group of lessons, concrete transferable skills stay with you:

| After | You can |
| --- | --- |
| Lessons 1–4 | Set up a 2D Godot project (resolution, stretch, filters); split a screen into reusable scenes; place one scene many times with per-instance values; drive visible state from a first script |
| Lessons 5–8 | Cut a sprite sheet into directional animation; read touch input with per-finger tracking; decouple nodes with signals; sort who-sees-who with collision layers |
| Lessons 9–12 | Open, end, and restart a run through one finish path; show run state on a HUD that decides nothing; pause without breaking input; add a second thumb of input with cooldowns |
| Lessons 13–16 | Grow content from data files instead of new scenes; persist records across restarts; translate a game without scattering `if` statements; sign, verify, and publish a phone build |

This path stays inside the 2D phone-game workflow, practiced end to end. It
does not claim every lesson is already fully self-contained — only some
excerpts are labeled yet, as
[How to read the code blocks](#how-to-read-the-code-blocks) says, so compare
with the runnable checkpoints whenever a block leaves you guessing.

### Capstone: the fourth beacon

No walkthrough — combine the sixteen lessons on your own:

1. Place a **fourth beacon** with its own position, scale, and flicker beat.
2. Add **one new enemy kind** as a `.tres` file only, no new code or scene.
3. Change **one rule**: a 60-second limit, a fourth heart, or your own idea.

Success criteria: `godot --headless --path . --import` finishes with
exit code 0 and no errors; all four
beacons light from play by standing near them, nothing lights on its own;
the new enemy spawns, chases, and cannot light a beacon; the changed rule
shows on the result screen; the whole run completes on your phone.

Checkpoints: every lesson has a runnable reference end state — see
[Practice checkpoints](/course/practice-foundation). Create one beside your
project and compare when stuck; never paste it over your work. Reference
projects are named **Moonlit Course Reference** so their saves and installs
stay separate from your own **Moonlit Course** project and from the shipping
Moonlit Beacon.

### Play the current game

The stores carry the expanded survivor this course grew into —
[play it on your phone](pathname:///#play-the-current-game) to see where the
foundation leads. Never played before? Up to five course readers are
invited to a [first-play session](/first-play).

## What to prepare

- Godot — see [Godot version](#godot-version): minimum 4.7.1 Standard,
  recommended 4.7.2 as of 2026-10-13
- Git
- [Five asset packs](/docs/assets/download-guide) — all free (six ZIP files;
  one is a reference-only demo project)
- **An Android device** — **you use it from Lesson 1.** At the end of every
  lesson you put the build on the phone and check it.
- `adb` (Android Platform Tools) — you will use it in Lesson 1, section 8.
- Node.js 20+ and `pnpm` — only if you also clone this repository to run the
  complete game or the docs site. The blank project you build in the lessons
  does not need them.

Without a phone you can follow along on a computer window through Lesson 10,
but **two-finger controls (Lesson 6) and interruption handling (Lesson 11) can
only be verified on a phone.** You will not be able to tick the "on the phone"
items in each lesson's completion checklist.

You do not need a gamepad. Controls are touch, and on a computer the same
controls are tested with the mouse.

## Two folders: your blank project and this repository

You work in **two separate places**. Do not mix them up.

- **Your blank project** is where you follow the lessons. It is an empty
  folder you create in Lesson 1, section 0 — for example
  `~/moonlit-course/my-game/`. Nobody else's files live there. In this folder
  you run plain `godot` commands.
- **This repository** is the complete, finished game plus this course site.
  Clone it only if you want to run the finished game, read its full source,
  or use its shortcut commands (`pnpm game:check`, `pnpm android:build`,
  …). Those shortcuts exist only inside a clone; they do not exist in your
  blank project.

Never create your blank project inside a clone, and never run `git init`
inside a folder you cloned. Lesson 1, section 0 shows the exact layout.

## How to read the code blocks

Some code blocks are **complete** — type them as they are. Others are
**excerpts**: they show the idea and leave out surrounding members, wiring,
or scenes. An excerpt never claims to run on its own. Only some excerpts are
labeled yet (Lessons 5 and 6 mark theirs); treat every other code block as an
excerpt too unless it is a complete settings table or a command. Where
a lesson needs declarations it does not have room to teach yet, it lists them
in a "required members" box — those are real declarations your project needs,
not optional reading.

## Godot version

| | |
| --- | --- |
| Minimum (course baseline) | Godot 4.7.1 Standard — the version the lessons were written against ([exact 4.7.1 archive](https://godotengine.org/download/archive/4.7.1-stable/)) |
| Recommended (latest stable as of 2026-10-13) | Godot 4.7.2 Standard ([exact 4.7.2 archive](https://godotengine.org/download/archive/4.7.2-stable/)) |
| Export templates | Must match the editor exactly — a 4.7.2 editor needs 4.7.2 templates, from the same archive page |

Read the [4.7.2 maintenance release notes](https://godotengine.org/article/maintenance-release-godot-4-7-2/)
for what changed since the baseline.

What was actually checked: both editors (`4.7.1.stable.official.a13da4feb`
and `4.7.2.stable.official.ed1daf0bf`) compiled the 174 shipping scripts and
booted the shipping title for 30 frames with clean post-import logs — and the
full practice run passes all 16 reference checkpoints on each editor
(desktop/headless, 2026-10-13). Those checks do not cover phone runs,
exports, sign-in, or newer engine versions: anything untested stays outside
the tested range until it is checked the same way.

Two rules follow from that. First, open/import the project in the editor
before any command-line launch: a first clean import prints
missing-generated-translation messages until the editor has imported once.
Second, a newer Godot release gets no verified claim until it is checked the
same way. The production engine lock stays 4.7.1 regardless.

## Good to know

**We follow the concept order of Godot's official intro course as-is.** Nodes
and scenes, instances, scripts, input, signals, the main scene, HUD — we skip
none of them. We do not, however, rebuild the official sample. The concepts are
the same; the game you make is different.

**We do not cover Windows or Web releases.** During development you run and
check the game on a computer, but the finished build ships as Android and
itch.io.
