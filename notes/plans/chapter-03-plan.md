# Lesson 3 — Plan

## Official tutorial mapping

`Step by step / Instancing` · `Editing instances` · `Editable children`

## Goal

**Instance `beacon.tscn` three times** from Lesson 2 and give each a different value.
Then wire title to arena so **the game has two screens.**

When Lesson 3 ends, tapping the title on a phone goes to the arena, three beacons in different
spots burn on their own beats, and the music switches to the arena track.

## Work order is lesson order

Drop three beacons as-is and **two of them burn in the middle of the grass.** There is only
one clearing baked into the forest. So the order is this.

| Step | What to do | Why this order |
| --- | --- | --- |
| 1 | Move `Clearing` · `Scorch` from forest to beacon scene | Three beacons need three clearings |
| 2 | Spell out floor layers with `z_index` | Skip this and the clearing covers grass and trees |
| 3 | Instance `beacon.tscn` three times · position and scale | The main point of this lesson |
| 4 | `Flicker.speed_scale` via `Editable Children` | Skip this and all three flicker on one beat |
| 5 | Arena BGM | A silent screen looks unfinished |
| 6 | Center the view in `arena.gd` | `expand` means width differs per device. The title had this; the arena did not |
| 7 | `start_requested` → scene change in `title_menu.gd` | Wire it last so you can check earlier steps on their own |

## Changes

### 1. Move the clearing into the beacon scene

Move `Clearing` · `Scorch` from `night_forest.tscn` in front of `Pit` in `beacon.tscn`.

| Node | In the forest | Inside the beacon |
| --- | --- | --- |
| `Clearing` | `(404, 250)`, `modulate (1.2, 1, 0.7)` | `(0, 0)`, `modulate (0.378, 0.35, 0.399)` |
| `Scorch` | `(404, 253)`, white | `(0, 3)`, `modulate (0.315, 0.35, 0.57)` |

Night tint is the same treatment as the Lesson 2 pit (write the multiplied result directly).

**Follow nested resources recursively.** `Scorch`'s `GradientTexture2D_scorch` itself
references `Gradient_scorch`. Move only what you can see and it dies like this.

```text
ERROR: res://scenes/objectives/beacon.tscn:168 - Parse Error: .
WARNING: Node './Beacon' was modified from inside an instance, but it has vanished.
```

**We actually hit this during the work.** The Lesson 2 plan already recorded the same trap
and we hit it again, so the lesson text gets a warning too.

### 2. Draw order

The beacon is a sibling of the forest and later in the tree, so a naive move makes the
clearing cover the whole forest.

| Node | `z_index` |
| --- | --- |
| `NightForest/Ground` | `-1` |
| `Beacon/Clearing` | `-1` |
| `Beacon/Scorch` | `-1` |
| Everything else | `0` (default) |

Inside the same `z_index`, tree order wins. The forest is earlier than the beacon, so draw
order is ground → clearing.

### 3. Three instances

| Name | `position` | `scale` | `Flicker.speed_scale` |
| --- | --- | --- | --- |
| `BeaconWest` | `(258, 286)` | `0.78` | `0.87` |
| `BeaconNorth` | `(414, 196)` | `0.62` | `1.24` |
| `BeaconEast` | `(566, 272)` | `0.86` | `1.03` |

Positions were chosen by measuring open spots in the forest. Brightness variance on a 32×28
grid is high in dense trees and low in open ground. The lowest region was
`x 296~482, y 192~288`; we spread around that.

Different sizes are for depth. In top-down, up is farther.

**Do not name them `Beacon2`, `Beacon3`.** Scripts attach in Lesson 4 and ignition order
is Lesson 7; you need to know which is which.

### 4. Offset the flicker

All three start the same animation at the same instant, so they **flicker in perfect unison.**
`Flicker` is a node inside the instance, so you must turn on `Editable Children` to touch it.

Check: sample the R channel in a 60×60 around each beacon at 10fps and compute correlation.

| | Correlation |
| --- | --- |
| West vs north | +0.01 |
| West vs east | +0.06 |
| North vs east | −0.19 |

Near 1.0 means one beat. Near 0 means they run independently.

**`Editable Children` is debt.** The instance now depends on inner structure, so renaming
`Flicker` in `beacon.tscn` later silently breaks the arena.
Lesson 4 attaches a script to the beacon, switches this to `@export`, and turns the setting off.
The lesson text should preview that.

### 5. Arena BGM

`27 - Chill.ogg` → `arena_theme.ogg`. `volume_db = -11`, `autoplay`,
`loop=true` in `.import`.

We measured eight candidates. Values are tabulated in the [manifest](../../apps/docs/docs/assets/manifest.md).

Filter order: **① loops that break** (last 3s / body < 0.7) → drop `11 - Clearing` (0.36)
`29 - Lament` (0.57). **② length · size** → drop `26 - Lost Village` (36s)
`37 - Dark Forest` (153.6s 4.3MB). **③ of the remaining three, the smallest swing**
→ `27 - Chill` (coefficient of variation 0.281, max−min 10.6dB).

**Picking by name would have been wrong.** The stage is a forest clearing, so `11 - Clearing`
looks like the answer, but measurement shows a fade-out at the end. Leave this beat in the lesson text.

:::danger The first measurements were wrong
A rough 32-band Goertzel sum inflated the spectral centroid to something like 1773Hz, and
even the conclusion "`27 - Chill` is the lowest" **was wrong** (done properly it is 579Hz,
and the lowest is `37 - Dark Forest` at 176Hz).

The problem was measuring the Lesson 1 table and the Lesson 3 table **two different ways
and then writing "same criteria".** The same track `37 - Dark Forest` showing different
values in the two tables gave it away. Both were remeasured with a 4096-sample Hann-window FFT.

**If one document has two sets of numbers for the same subject, one of them is wrong.**
:::

Asset count goes 66 files 9.0MB → **67 files 10.1MB**. Update the numbers in the manifest,
`AGENTS.md`, and `docs/intro.md` together.

### 6. Scene change

```gdscript
const ARENA_SCENE: String = "res://scenes/gameplay/arena.tscn"

func _ready() -> void:
	...
	start_requested.connect(_enter_arena)

func _enter_arena() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)
```

`start_requested` has existed since Lesson 1, but nobody was listening.
It is the same file so you could call directly, but we go through the signal — in Lesson 9 a
scene that manages the whole game will receive this signal, and then only one line changes.

**The transition frame froze for 181ms.** When `AudioStreamPlayer` leaves the tree it waits
150ms on the audio thread, and that wait lands on the scene-swap frame.
A comment in `title_menu.gd` `_exit_tree()` already previewed "when we later hand off to the
game scene, stop audio before swapping scenes" and we did not follow it.

Fade the music down over 0.55s from the tap. By the time the beacon flourish (0.85s) ends,
the sound is already gone. Measured: **181ms → 27ms.**

Flush logic moved to `scripts/audio/music_player.gd`. Arena `Bgm` uses the same script —
otherwise Ogg leaks come back when leaving the arena
(`4 ObjectDB instances were leaked at exit`, confirmed by measurement).

**One transition frame shows Godot's default clear color gray (`#4C4C4C`).**
Change `rendering/environment/defaults/default_clear_color` to the night color.
The headline clip was breaking the repo rule "do not leave a gray rectangle on screen."

## Recording

| Clip | Content | Length |
| --- | --- | --- |
| `chapter-03-transition.mp4` | Device — tap goes to arena | 9s |
| `chapter-03-arena.mp4` | Three beacons on their own beats | 9s |
| `chapter-03-instances.mp4` | Change light color once, all three change | 8s |

The third temporarily changes `Light.color` on `beacon.tscn`, re-renders the arena once,
then **reverts.** Confirm the revert with `grep`.

## Completion criteria

- [ ] Tap on the title switches to the arena
- [ ] Three beacons each have their own position · size · beat
- [ ] Each of the three sits on its own clearing
- [ ] Clearings do not cover grass or trees
- [ ] Arena music plays and does not cut off after 48s
- [ ] Changing `beacon.tscn` once changes all three (proved by clip)
- [ ] Title screen matches Lesson 2 as-is (PSNR compare)
- [ ] `pnpm game:check` 0 · manifest check 0
- [ ] Device confirms the transition; no logcat errors
- [ ] Three silent clips · each under 1MB
- [ ] Transition frame under 30ms · no gray frame
- [ ] 0 leak warnings when quitting the arena alone
- [ ] `arena.tscn` has three `[editable path=...]` lines
- [ ] Lesson-text section numbers 1:1 with the recording script

## Pitfalls that must stay in the lesson text

| Pitfall | Why |
| --- | --- |
| Skip recursive nested resources and the scene will not open | Hit again after Lesson 2 |
| Moved clearing covers grass and trees | You must spell out `z_index` |
| All three flicker on one beat | Instances start the same animation at the same instant |
| `Editable Children` is debt | You now depend on inner structure. Pay it in Lesson 4 |
| `.ogg` import default is `loop=false` | It goes quiet after 48s |
| Picking a track by name is wrong | `Clearing` looks like the answer but it fades out |
| The transition frame freezes | Audio teardown wait lands on that frame |
| One transition frame flashes gray | Default clear color is gray |
| `expand` but only the arena lacks centering | It does not show on a Pixel 10 |

## Deferred to Lesson 4

- Beacon lit state and script (pay `Editable Children` with `@export`)
- Forest brightening when a beacon lights
- A path from arena back to title

## Not this lesson

- Player — Lesson 5
- Camera — everything still fits on one screen
- Beacon interaction — Lesson 7
