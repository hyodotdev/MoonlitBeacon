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

| | |
| --- | --- |
| Engine | Godot 4.7.1 · GDScript |
| Screen | Landscape lock, internal resolution 808 × 360 |
| Controls | Move with the left thumb, dash with the right thumb |
| Release | Android APK · itch.io |
| Assets | All free (CC0 · OFL) |

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

## What to prepare

- [Godot 4.7.1 Standard](https://godotengine.org/download/windows/)
- Git
- [Five asset packs](/docs/assets/download-guide) — all free
- **An Android device** — **you use it from Lesson 1.** At the end of every
  lesson you put the build on the phone and check it.
- `adb` (Android Platform Tools) — you will use it in Lesson 1, section 8.

Without a phone you can follow along on a computer window through Lesson 10,
but **two-finger controls (Lesson 6) and interruption handling (Lesson 11) can
only be verified on a phone.** You will not be able to tick the "on the phone"
items in each lesson's completion checklist.

You do not need a gamepad. Controls are touch, and on a computer the same
controls are tested with the mouse.

## Good to know

**We follow the concept order of Godot's official intro course as-is.** Nodes
and scenes, instances, scripts, input, signals, the main scene, HUD — we skip
none of them. We do not, however, rebuild the official sample. The concepts are
the same; the game you make is different.

**We do not cover Windows or Web releases.** During development you run and
check the game on a computer, but the finished build ships as Android and
itch.io.
