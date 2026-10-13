# Course followability audit — 2026-10-13

Question: can a novice follow all sixteen lessons in sequence from a blank
project and make a runnable game?

Short answer: no. The concept order is complete and the prose is strong, but
the course as written is **excerpt/reference-dependent from Lesson 1 section 5
onward**: a novice cannot build the Lesson 1 title scene from the text, so
every later lesson that assumes it (2–16, by transitivity) has no reproducible
entry. On top of that, no lesson from 5 onward gives a complete script or a
complete scene tree — every code block is an excerpt with undeclared members,
and most scenes/scripts are never created step by step.

This note is author-only (under `notes/`, not published). Line citations are
against the pre-repair files (`git diff baseline` shows the repair hunks).

## Method

- Read the full body of all sixteen lessons (`apps/docs/course/chapter-01.mdx`
  through `chapter-16.mdx`), `apps/docs/course/intro.md`,
  `apps/docs/docs/intro.md`, `apps/docs/docs/assets/download-guide.md`, plus
  the homepage hero (`apps/docs/src/pages/index.tsx`) and the scope statement
  in `apps/docs/docs/game.md`.
- Checked every command, script name, file path, and asset path cited in the
  lessons against the repo: root `package.json` scripts, `.github/scripts/`,
  `apps/game/assets/` tracked files, `apps/game/scenes/`, and the asset
  manifest.
- Ran one headless engine probe for the Lesson 6 anchor claim
  (see Lesson 6). No other engine runs: the brief forbids captures and
  run/phone verification, and most findings are checkable by file inspection.
- Severity: **Blocker** = a novice following the text cannot proceed past this
  point. **Major** = likely multi-hour stall or silently wrong result; needs
  inference a novice does not have. **Minor** = inconsistency or cosmetic
  defect, inferable in minutes.

## Entry path (before Lesson 1)

### E1. No prerequisites route — Blocker

`apps/docs/course/intro.md` ("What to prepare", lines 58–70) lists Godot,
Git, five asset packs, an Android device, and adb. It never mentions
**Node.js / pnpm**, yet Lesson 1 alone calls `pnpm game:check` (chapter-01
lines 256–261), `pnpm install` (line 397), `pnpm docs:dev` (line 398), and
`pnpm android:build` / `pnpm android:run` (lines 424–427). There is no clone
step anywhere in the course intro: no repo URL, no `git clone` command, no
directory to run commands from. A novice arriving at Lesson 1 section 3-7
with only a Godot install cannot run a single command on the page.

`apps/docs/docs/intro.md` (reference intro) is little better: "Clone the
repository" (line 23) gives no URL; `pnpm game` (line 30) is given with no
`pnpm install` first and no Node.js prerequisite; the Godot link (line 15)
points at the **Windows-only** download page (`godotengine.org/download/windows/`),
as does the course intro link (course `intro.md` line 60).

### E2. Blank learner project vs complete clone is never separated — Blocker

Lesson 1 section 3-1 (chapter-01 lines 80–83) says the new project path is
`apps/game` **"inside the repository"**, section 3-6 (lines 181–191)
describes the full monorepo layout as if the learner already has it, and
section 6 (lines 372–377) says `git init -b main` — a fresh repository that
would contain none of the `pnpm` scripts the lesson invokes. These three
cannot all be true at once:

- If the learner cloned this repo, `git init` is wrong (the real defect is
  mixing a complete clone with a blank project: a nested repo whose lesson
  files collide with the shipping game), and the `apps/game` folder already
  holds the complete 4.0.1 game, not a blank project.
- If the learner started blank, every `pnpm` command on the page fails
  (`game:check`, `docs:dev`, `android:build`, `android:run` are repo scripts
  defined in root `package.json`), and `.github/scripts/check-locale.mjs`
  (Lesson 15, lines 98/288) does not exist.

There is no "two folders" explanation anywhere: one clone for running the
complete game, one separate blank folder for following the lessons, with
plain `godot`/`adb`/`keytool` commands in the blank folder.

### E3. Asset guide contradicts itself about ignored packs — Major

`apps/docs/docs/assets/download-guide.md` lines 3–21 carry a tip box titled
"Download and unzip are already done", stating the six packs "are already
downloaded into `_downloads/` and unzipped into `_asset_sources/`", while the
same box admits "Both folders are gitignored, so they are not on a clone."
A public clone therefore never includes them; the title promise is false for
exactly the reader who needs the guide. The factual sentence inside the box
is correct, but the heading and bold promise say the opposite.

### E4. Top-level promise implies current-main equivalence — Major

The homepage hero (`apps/docs/src/pages/index.tsx`, subtitle block) describes
the expanded shipping game ("forest, field, and camp", "three weapon paths",
"deeper cycles") and says "Sixteen lessons build this game from a blank
Godot project". The lessons build the original 90-second dodge game
(three beacons, three enemy kinds plus guardian, moonlight gate, v1.0.0). `game.md` lines
30–35 does scope itself honestly ("This page's shipping scope is the expanded
current complete build"), and Lessons 12/15/16 carry honest "arrived in later
updates" notes (chapter-12 lines 163–169, chapter-15 lines 29–34, chapter-16
lines 104–108 and 216–221) — but the first promise a fresh reader meets still
says the sixteen lessons produce the current game.

## Lesson-by-lesson audit

Legend: **S** = self-contained (a novice can complete it from the page plus
previously built state), **X** = excerpt/reference-dependent (needs inference
or sources outside the page). No lesson is fully S; the tag marks the
dominant character of its build section.

### Lesson 1 · Project setup and the title screen — X

- Entry prerequisite: Godot 4.7.1, Git, Node.js 20+ with pnpm, asset
  downloads, adb, a phone. None of the Node/pnpm/clone route is given (E1,
  E2); the Godot link a learner meets first is Windows-only.
- Changed files/nodes: `project.godot` settings (sections 3-2–3-5, exact
  values, verifiable against the 3-7 block at lines 208–229 — this part is
  genuinely followable), folder skeleton (3-6), `_downloads/`/`_asset_sources/`
  intake (section 4), `res://scenes/menus/title_menu.tscn` (section 5).
- Missing definitions/wiring/assets:
  - **Section 5 gives no construction steps (Blocker).** Lines 351–360 name
    the result file and list six layers in a table (forest floor, forest
    edge, beacon, moonlight, mist, UI with sizes 55/22/11). No node tree, no
    asset paths, no inspector values, no scene-creation steps. The section 5
    clip (`chapter-01-layers.mp4`, lines 344–349) is an eight-step layer
    breakdown video, not steps. A novice cannot produce any `title_menu.tscn`
    from this.
  - Section 4 never says **which** files to copy into `res://` (Major). Line
    332 says "only 66 files (9.0MB) actually go into the game" without listing
    one path; the learner must reverse-engineer the manifest.
  - The six-ZIP table (lines 311–318) vs "Five asset packs" in the course
    intro (Minor inconsistency; the sixth ZIP is the reference-only demo).
  - `config/version` is never set, yet section 5 (lines 367–368) says the
    version string "is managed in one place: `project.godot`" and Lesson 11
    (chapter-11 lines 144–152) reads `application/config/version` (Minor;
    value defaults to "0.0.0" nowhere handled in Lesson 1).
  - `pnpm install` appears only in section 7 (line 397), after `pnpm
    game:check` was already needed in 3-7 (Major ordering defect, part of E1).
- Exit checkpoint: a runnable title screen good enough for a store
  screenshot, plus the 9-item checklist (lines 471–481). **Not attainable
  from the text**: checklist items 2–5 (title fills phone screen, centering,
  no blur, tap flares beacon + confirm sound) depend on the unbuilt scene.
- Classification: **X**. Sections 3-2–3-5 and 3-7 are the only S parts.

### Lesson 2 · Nodes and scenes — X

- Entry prerequisite: the Lesson 1 `title_menu.tscn` with the exact tree at
  lines 102–116 (`Forest/NightTint`, `Forest/Beacon` with `Pit`+`Light`,
  `BeaconFx`, `Fire` CanvasLayer with `Flames/Smoke/Embers/Flame/Glow`,
  `Ui/Bgm/Sfx`). **This tree is never constructed in Lesson 1** (see Lesson 1
  section 5), so the lesson has no reproducible entry (Blocker by
  transitivity). The lesson also asserts a "1,296-node screen" (line 92) no
  learner can have built.
- Changed files/nodes: `title_menu.tscn` restructured; new
  `res://scenes/objectives/beacon.tscn` (8 nodes, via Save Branch as Scene,
  lines 312–340), new `res://scenes/gameplay/night_forest.tscn` (1,296
  nodes, lines 453–471), new `res://scenes/gameplay/arena.tscn` (~11 lines,
  lines 473–503); title rebuilt on instances (5-11, lines 505–561).
- Missing definitions/wiring/assets:
  - No source for any node in the entry tree: night tint color origin,
    `Clearing`/`Scorch`/`Ground`/`Details`/`Trees` contents, particle
    settings for Smoke/Embers/Flame, `BeaconFx` flicker/flare keyframes
    (only two energy values `1.45`/`1.58` leak at line 380), `Ui/Bgm/Sfx`
    nodes (Major; each is a multi-value gap).
  - Section 5-11 edits `title_menu.gd` (`@onready` vars at lines 543–545,
    tap handler at lines 554–557) but **never names the file, never creates
    it, never shows `_ready()` or the `flare` trigger** (Major). `title_menu.gd`
    is first named only in Lesson 3 (chapter-03 line 316).
  - The 5-7 keyframe table (lines 527–532) renames paths into `Flicker` /
    `BeaconFx` animations the learner never created (Major, same root cause).
- Exit checkpoint: four files with the line/node counts at lines 567–576 and
  the 13-item checklist (lines 618–629). Counts are checkable **if** the entry
  tree existed; item "tapping flares then returns to flicker" needs the
  undeclared tap wiring.
- Classification: **X** — reference-dependent on the undescribed Lesson 1
  scene. The *operations* (move tint, gather, extract, re-path) are clearly
  sequenced and would be S given the entry tree.

### Lesson 3 · Instances — X

- Entry prerequisite: Lesson 2 exit state (three-placeable `beacon.tscn`,
  `night_forest.tscn` with `Clearing`/`Scorch`, `arena.tscn`).
- Changed files/nodes: `Clearing`+`Scorch` moved into `beacon.tscn` with
  positions (lines 99–107) and multiplies (lines 113–116); `z_index`
  pinning (lines 140–152); three instances placed with positions/scales
  (lines 163–178); per-instance `Flicker` speed scales via Editable Children
  (lines 203–216); arena `AudioStreamPlayer` + `arena_theme.ogg` with loop
  import (lines 236–248); `scripts/util/screen.gd` (lines 281–292);
  title→arena transition in `title_menu.gd` (lines 311–375).
- Missing definitions/wiring/assets:
  - `screen.gd` shows the class (lines 284–292) but **no caller**: which
    `_ready()`/`_process()` calls `center_offset()`, on which nodes, in
    title vs arena (Major). The offset table (lines 299–304) gives values
    with no wiring.
  - "The title screen already emits a `start_requested` signal" (line 313):
    the signal, `request_start()`, `_bgm`, `_sfx`, `BGM_SILENCE_DB`, and
    `_fade_out_music()`'s call site are all undeclared anywhere in Lessons
    1–3 (Major). The `_fade_out_music()` excerpt (lines 350–362) uses
    `BGM_SILENCE_DB`, `BGM_FADE_OUT_SECONDS` (declared, line 351), `_bgm`,
    `_sfx` — three of four undefined.
  - The arena music path `assets/third_party/ninja_adventure/audio/music/arena_theme.ogg`
    (line 241) **is** a real tracked file (verified), and the loop-import
    warning is concrete — this sub-step is S.
  - `Editable Children` + `Speed Scale` values (lines 209–216) are exact and
    followable (S).
- Exit checkpoint: checklist lines 426–436. Arena-side items are attainable;
  transition items ("no freeze/flash", line 432) need the undeclared audio
  wiring.
- Classification: **X** (transition + centering excerpts), with S sub-steps
  (instances, clearing move, music hookup).

### Lesson 4 · Your first script — X

- Entry prerequisite: Lesson 3 exit state.
- Changed files/nodes: `res://scripts/objectives/beacon.gd` attached to
  `beacon.tscn` (Attach Script step at lines 98–99 — one of the few explicit
  file-creation steps in the course); `lit`/`flicker_speed` exports; arena
  brightening + ignition sequence in `arena.gd`.
- Missing definitions/wiring/assets:
  - `arena.gd` is **never created**: no Attach Script step, no file path, and
    `_beacons`, `_forest`, `_player` (lines 310/324, `_player` unused here but
    assumed later) are never declared (Major). `_run_ignition_sequence()`
    (lines 357–365) is never called from any `_ready()` (Major).
  - `FIRST_IGNITE_DELAY` / `IGNITE_INTERVAL` values never given (lines
    358/363 use them; only the prose "2.6 seconds" at line 333 hints the
    interval) (Minor-Major).
  - The `lit_changed` signal (line 283) is declared, but its `emit` call
    appears only inside the `@tool` warning guard (lines 233–236), never in
    the `ignite()` flow (lines 191–205) — a novice wiring only the main
    excerpts gets a beacon that never notifies (Major).
  - `_set_flicker_speed` must be re-applied in `_ready()` (lines 166–170):
    shown correctly (S).
- Exit checkpoint: brightness table (lines 386–392) and checklist (lines
  429–438). The beacon-side behavior is reproducible; the arena-side sequence
  is not, for the missing wiring above.
- Classification: **X** — beacon.gd is near-complete (S-leaning); arena.gd is
  excerpt-only.

### Lesson 5 · The player scene and animation — X

- Entry prerequisite: Lesson 4 exit state.
- Changed files/nodes: `player.tscn` with the 5-node tree (lines 37–45);
  8 `SpriteFrames` animations (lines 90–95); `Breathe` animation (lines
  115–121); shadow (5-2); night-tint modulate (5-3); arena instance at
  `(330, 300)` (lines 214–217).
- Missing definitions/wiring/assets:
  - **No script file is ever created.** `face_toward()` (lines 177–189) and
    `_play_current()` (lines 203–210) use `facing`, `_sprite`, `_walking`
    with no declarations anywhere in the lesson (verified by grep: no `var
    facing`, no `@onready var _sprite`, no `var _walking`, no `set_walking`,
    no `player.gd` mention) (Major). Exercise 2 (line 267) says "change
    `Facing` in the inspector", implying an `@export` that was never
    declared (Major contradiction of the same gap).
  - Sprite-sheet paths: `ninja_walk.png` / `ninja_idle.png` named (lines
    69–72) without `res://` paths (Minor; resolvable via manifest:
    `res://assets/third_party/ninja_adventure/actor/ninja_walk.png`, verified
    tracked). Column→direction table (lines 77–82) is concrete (S).
  - "In Lesson 5 we put the player on layer 2" is claimed by Lesson 7
    (chapter-07 lines 76–77), but **Lesson 5 never sets any collision
    layer** (Major false back-reference; breaks Lesson 7's entry).
  - Shadow construction ("one soft 24×10 ellipse", line 138) gives no source:
    drawn asset? GradientTexture2D? (Minor-Major).
- Exit checkpoint: checklist lines 252–259. Scene/art items attainable;
  facing items ("match animation", exercise 2) need the missing script.
- Classification: **X** — art/scene steps near-S; script excerpt-only.

### Lesson 6 · Handling input — X

- Entry prerequisite: Lesson 5 exit state (player with `face_toward` /
  `set_walking`, which Lesson 5 never declared — transitive Major).
- Changed files/nodes: `VirtualStick` Control (5-1); `_gui_input`/`_input`
  handlers (5-2/5-3); dead zone (5-4); arena→player movement (5-5); bounds
  (5-6); walk-animation hookup (5-7).
- Missing definitions/wiring/assets:
  - **Anchor contradiction (Blocker, repaired this round).** The excerpt
    (lines 91–96) sets `anchors_preset = 9`, `anchor_bottom = 1.0`,
    `offset_right = 404.0` with **no `anchor_right`**, while the prose
    (lines 98–100) claims "even a wide phone keeps the left half." With
    `anchor_right` defaulting to 0, the right edge sits at fixed x=404 on
    every viewport. Engine probe (headless, host 1200×360): lesson excerpt
    → `size = (404, 360)`; with `anchor_right = 0.5` → `(600, 360)`.
    The current shipping `apps/game/scenes/ui/virtual_stick.tscn` (lines
    9–11) carries the same three lines — the game itself has this defect,
    out of scope for this docs-only round (left for the director).
  - `virtual_stick.tscn` / `virtual_stick.gd` are never created step by step;
    `_touch_index` (line 69) and `dead_zone` (line 152) are declared but
    `_origin`, `_value`, `_show_at()`, `_move_to()`, `_release()`,
    `get_value()`, and the `length`/`radius`/`direction` locals (lines
    111/135/154–155) have no declarations or bodies (Major).
  - Movement uses `speed`, `_wish`, `ACCELERATION`, `FRICTION`,
    `set_move_input()`, `WALK_THRESHOLD`, `set_walking()` (lines 171–183,
    222–225) — none declared in Lesson 5 or 6 (Major).
  - `BOUNDS` rect (line 200) and the accel/friction values (lines 193–195)
    are exact (S).
- Exit checkpoint: checklist lines 271–278. None of the stick items are
  buildable from declared code alone.
- Classification: **X**.

### Lesson 7 · Signals — X

- Entry prerequisite: Lesson 6 exit state **plus** "the player on layer 2",
  which Lesson 5 never sets (Major false back-reference from lines 76–77;
  a novice has `collision_layer = 1` default and the `Reach` area with
  `mask = 2` detects nothing — silent failure).
- Changed files/nodes: `Reach` Area2D + `ReachShape` (lines 70–77);
  charge/decay (5-1); visitor counting (5-2); ring gauge via `region_rect`
  (5-3); player-side ring + arena relay (5-4); `AudioStreamPlayer2D` +
  `AudioFlush` (5-5).
- Missing definitions/wiring/assets:
  - The `charge_changed` signal is **never declared**: only the handler
    `_on_beacon_charge_changed` (line 207), `beacon.get_charge()` (line 210),
    and `_player.set_charge(top)` (line 211) appear; the `emit` surfaces only
    in Lesson 14's `freeze()` (chapter-14 lines 256–259) (Major).
  - Ring node tree (bottom/top sprites, `_size`, `_fill`) never constructed;
    `set_progress()` (lines 173–181) has no scene (Major).
  - `_normalize_reach()` (lines 94–101) is complete and correct (S);
    `REACH_RADIUS` value (34, from line 73) must be inferred (Minor).
  - `AudioFlush` extract: problem stated (lines 230–241), no file path, no
    code, no attach steps (Major).
  - `_process` on/off wiring (`set_process(true)` on enter) never shown
    (Minor).
- Exit checkpoint: checklist lines 293–300. Charge/ring/sound items need the
  missing declarations.
- Classification: **X**.

### Lesson 8 · Creating enemies — X

- Entry prerequisite: Lesson 7 exit state.
- Changed files/nodes: `spirit.tscn` (6-node tree, lines 27–35); layer 4/0
  (lines 72–76); chase (5-1); `set_target()` (5-2); contact cooldown (5-3);
  red flash (5-4); knockback (5-5).
- Missing definitions/wiring/assets:
  - No creation steps for `spirit.tscn` or its script: no file paths, no
    sprite-sheet path for the 4×4 frames, no `Hitbox` shape, no `Hover`
    keyframes (Major). (Track candidates exist in the manifest but the lesson
    names none.)
  - `touched_player` is never declared, and its emit signature **changes
    silently**: `touched_player.emit()` (line 146) vs
    `touched_player.emit(global_position)` in Lesson 9 (chapter-09 line 172)
    (Major inconsistency).
  - `_target`, `_cooldown`, `HIT_COOLDOWN` (declared line 140),
    `TURN_RATE`, `speed`, `KNOCKBACK_SPEED`, `KNOCKBACK_SECONDS`,
    `_knock_left`, `_hit_flash`, `_flash`, `HIT_FLASH_SECONDS` — all but one
    undeclared; the flash ColorRect has no scene parent named beyond "the
    `Ui` layer" (line 159) (Major).
  - Layer table (lines 99–102) and the mask rule are exact (S).
- Exit checkpoint: checklist lines 243–249. Chase/contact/flash items need
  the missing script + scenes.
- Classification: **X**.

### Lesson 9 · Start and end of a run — X

- Entry prerequisite: Lesson 8 exit state.
- Changed files/nodes: run state + `_finish()` (section 2); moon gate scene
  (section 4); bounds widening (5-1); overlap hit polling (5-2); result
  panel (5-3); restart (5-4).
- Missing definitions/wiring/assets:
  - `_over`, `_health`, `MAX_HEALTH`, `_result`, `_gate`, `_spirit`,
    `_player`, `show_result()` — none declared; the result panel scene is
    never constructed (no file, no tree) (Major). `MAX_HEALTH` first appears
    in homework (line 285).
  - Gate position `(404, 336)` (line 119) vs Lesson 6 bounds `y ≤ 322` is a
    genuine, checkable contradiction-with-resolution (S); `merge()` fix
    (lines 124–138) is exact (S).
  - `_try_hit()`/`_physics_process()` (lines 165–179) complete (S-leaning);
    hit-flash/tween-kill pattern correctly reused.
  - The 0.6s input gate (lines 203–209) and `monitoring=false`-until-open
    (lines 95–102) are exact (S).
- Exit checkpoint: checklist lines 275–281. Gate/bounds/hit-polling items
  reproducible; health/panel/restart items need the missing scene + members.
- Classification: **X**.

### Lesson 10 · On-screen information — X

- Entry prerequisite: Lesson 9 exit state.
- Changed files/nodes: HUD (hearts, beacon count, timer); 9-patch wood panel
  (section 4); `TIME_LIMIT` countdown (5-3); urgent color (5-4); initial draw
  (5-5).
- Missing definitions/wiring/assets:
  - **The HUD scene is never constructed**: no file name, no tree (CanvasLayer?
    Control? `HBoxContainer`? label names?), no script file (Major). Every
    excerpt (`_hearts`, `_time`, `set_health`, `set_beacons`, `set_time_left`,
    `URGENT_COLOR`/`CALM_COLOR`) dangles.
  - `panel_wood.png` named (line 64) without a `res://` path (Minor; manifest
    has the wood UI theme but the lesson cites nothing).
  - `ceilf`/`maxf` rationale (lines 140–143), `mouse_filter = 2` on all HUD
    nodes (lines 102–115), and the margin-8 breakage (lines 79–84) are exact
    and checkable (S).
- Exit checkpoint: checklist lines 204–210. Nothing drawable without the scene.
- Classification: **X** — concept+rules S, construction entirely absent.

### Lesson 11 · Install and play on a phone — X

- Entry prerequisite: Lesson 10 exit state; a phone + adb + export templates
  (templates never mentioned in the course; reference intro's "set up the
  Android build template" at docs/intro.md line 51 has no steps either)
  (Major).
- Changed files/nodes: pause panel + button; `process_mode` (section 4);
  background auto-pause (5-2); button hide (5-3); version 0.1.0 (5-4);
  `android:build`/`android:run` (5-5).
- Missing definitions/wiring/assets:
  - Pause scene/script never constructed: no file names (retroactively named
    `pause_panel.gd` only in Lesson 16, chapter-16 line 46), no tree, no
    `$Button`/`Overlay` structure, no `request_pause()` body (Major).
  - The anchor bug story (5-1, lines 78–107): preset-14 failure → preset-8
    fix with all four 0.5 anchors is exact and reproducible **as a fragment**
    (S), but the button it belongs to was never built.
  - `NOTIFICATION_APPLICATION_PAUSED` guard (lines 115–119) exact (S).
  - Version bump (lines 144–152) exact (S).
  - `pnpm android:build` / `pnpm android:run` are repo scripts that do not
    exist in a blank learner project (Blocker in a blank project; part of E2).
- Exit checkpoint: checklist lines 200–206. Pause items need the missing
  scene; "play a run to the end on a phone" additionally needs the export
  route E2/E-prereqs.
- Classification: **X**.

### Lesson 12 · Dash — X

- Entry prerequisite: Lesson 11 exit state.
- Changed files/nodes: right stick instance (section 2); `flicked` on release
  (section 4); dash guard (5-1); cooldown (5-2); afterimages (5-3); HUD dash
  readiness (5-4).
- Missing definitions/wiring/assets:
  - Right-stick excerpt (lines 34–41): `anchor_left = 1.0`,
    `anchor_right = 1.0`, `offset_left = -404.0` — fixed 404px wide, **not**
    the right half on wide viewports (same defect class as Lesson 6; the
    prose here only claims "flipped to the right", so no direct
    contradiction, but the geometry is still wrong under `expand`) (Major;
    repaired alongside Lesson 6 this round).
  - `dash()`, `DASH_SPEED`, `DASH_SECONDS`, `DASH_COOLDOWN` (declared line
    112), `_dash_cooldown`, `_dash_left`, `_leave_afterimages()` call site,
    `AFTERIMAGE_COUNT`, `AFTERIMAGE_FADE`, the `Dash` HUD label node — none
    declared or constructed (Major).
  - `_leave_afterimages()` (lines 126–144) is a complete body (S-leaning);
    the 0.85-alpha/5-copy/0.42-fade finding (lines 153–161) is measured and
    honest (S). The "final game trims into speed lines" note (lines 163–169)
    correctly scopes history vs now (S).
- Exit checkpoint: checklist lines 214–218. Needs the missing members.
- Classification: **X**.

### Lesson 13 · Three enemy types and the final guardian — X

- Entry prerequisite: Lesson 12 exit state.
- Changed files/nodes: `SpiritKind` resource (section 2); code-sliced
  `SpriteFrames` (section 4); farthest spawn (5-1); `materialize()` (5-2);
  kind-by-progress (5-3); guardian + retreat (5-4); music swap (5-5);
  `_prune_spirits()` (5-6).
- Missing definitions/wiring/assets:
  - No `.tres` creation steps: how to make a `SpiritKind` resource in the
    editor, file names for the four kinds, sheet paths for any of them
    (Major). `class_name SpiritKind` needs an editor import pass that is
    never mentioned (Minor).
  - `_apply_kind()` (lines 75–93) is complete (S-leaning) but its call site,
    `kind`, `_sprite`, and the facing-index selection are undeclared (Major).
  - Guardian 50px/single-row layout (lines 100–117) is exact (S); the
    `mini()` clamp fix is exact (S).
  - Spawn/retreat/prune excerpts use `SPAWN_POINTS` (declared line 124),
    `_player`, `_spirits`, `_spawn_timer`, `_lit_count` (declared Lesson 4),
    `MATERIALIZE_SECONDS`, `MAX_SPIRITS`, `GUARDIAN_THEME`, `retreat()` —
    mostly undeclared, no spawn-timer wiring (Major).
  - `17 - Fight` / `27 - Chill` named (lines 212–215) without `res://` paths
    (Minor; tracked as `guardian_theme.ogg` / `arena_theme.ogg` under
    `res://assets/third_party/ninja_adventure/audio/music/`, verified).
- Exit checkpoint: checklist lines 259–263. "One more `.tres` makes a new
  enemy" is not demonstrable without the creation steps.
- Classification: **X**.

### Lesson 14 · Score and saving records — X

- Entry prerequisite: Lesson 13 exit state.
- Changed files/nodes: score formula (section 2); `Records` autoload
  (section 4); `Score` type (5-1); `ConfigFile` save (5-2); tick-up reveal
  (5-3); rank stamp (5-4); skip (5-5); layout slots (5-6); `beacon.freeze()`
  (5-7).
- Missing definitions/wiring/assets:
  - `Score.total()`/`rank()`/`lines()` bodies are literally `...` (lines
    100–102); only the `not escaped → D` rule (lines 34–39) is given. No
    thresholds table (`RANKS` appears only in homework, line 325),
    `PER_SECOND` only in homework (line 323) (Major).
  - Result-panel layout slots (lines 224–230) reference rows/stamp/hint nodes
    of a scene never constructed in Lesson 9 or here (Major, transitive).
  - `_reveal`/`_rows`/`_shown`/`_sum_shown`/`_score`/`_stamp`/`_set_sum`/
    `ROW_SECONDS`/`ROW_GAP`/`SUM_SECONDS` undeclared (Major).
  - `Records` autoload path given (line 73) but `best_score`, load/save
    bodies partial (5-2 shows load only) (Major).
  - `beacon.freeze()` (lines 250–260) + arena hook (lines 261–265) complete
    (S); the 0-vs-1/3 checksum story is the course's best debugging lesson
    (S). Skip-vs-restart separation (lines 187–212) exact (S).
- Exit checkpoint: checklist lines 312–318. Reveal/stamp/skip/persist items
  need the missing scene + members.
- Classification: **X**.

### Lesson 15 · Settings · Korean and English · Credits — X

- Entry prerequisite: Lesson 14 exit state.
- Changed files/nodes: `localization/moonlit.csv` (ko/en); import flow
  (section 4); scene-string auto-translation (5-1); code-built string redraw
  (5-2); untranslated list (5-3); audio buses (5-4); `Settings` autoload
  (5-5); locale default (5-6); shared settings scene (5-7); behind-window
  hiding (5-8); credits (5-9).
- Missing definitions/wiring/assets:
  - CSV creation never stepped: file creation, full key list (22 strings
    asserted at lines 44–48, only `RESULT_WIN` shown at line 56),
    `locale/translations` project setting, import-tab steps (Major).
  - The two check commands (lines 97–100) do not exist in a blank learner
    project: `.github/scripts/check-locale.mjs` is repo tooling and
    `res://tools/check_locale.gd` is the shipping game's tool (Major; part
    of E2). Checklist's `pnpm verify` (line 330) likewise repo-only.
  - Settings/credits scenes never constructed; `Settings` autoload members
    (`LOCALES`, `step_to_db`'s `MAX_STEP`/`MUTE_DB`, `_redraw`, `changed`
    signal) partially shown, never assembled (Major).
  - `--headless --quit` does-not-import warning + `--import` fix (lines
    82–92) is exact and verified against repo behavior (S). Bus tree (lines
    171–177) + `linear_to_db` steps (lines 184–193) exact (S). The
    five-language clip vs two-language build note (lines 29–34) is honest
    scoping (S).
- Exit checkpoint: checklist lines 324–330. All items need the missing table
  + scenes.
- Classification: **X**.

### Lesson 16 · Wrap-up and release — X (procedural parts S)

- Entry prerequisite: Lesson 15 exit state; release keystore; store accounts.
- Changed files/nodes: Back handling (section 4); dual version bump (5-1);
  keystore (5-2); `android:release` (5-3); cert/permission checks (5-4);
  wiped-device install (5-5); store page (5-6/5-7).
- Missing definitions/wiring/assets:
  - Back-handler excerpt (lines 79–94) uses `_credits`, `_settings`,
    `_over`, `_pause`, `TITLE_SCENE`, `request_pause()` — none declared;
    quit prompt (`_no`, `open()`, lines 115–122) has no scene (Major, same
    class as Lessons 9/11/15 scenes).
  - `quit_on_go_back=false` (lines 61–65), the Back table (lines 70–77),
    version/code rules (lines 126–141), keystore dangers (lines 162–175),
    `apksigner`/`aapt`/`adb` commands (lines 201–231) are all exact,
    tool-verifiable procedure (S). `pnpm android:release` is repo-only
    (blank-project gap, part of E2) but the surrounding no-bypass rationale
    is correct for the clone (S).
  - `pnpm verify` checklist (line 325) repo-only (same as Lesson 15).
- Exit checkpoint: checklist lines 318–325. Release-procedure items S;
  Back-behavior items need the missing scenes.
- Classification: **X overall, S for release procedure**.

## Cross-cutting findings

1. **No lesson/checkpoint tags exist.** The working copy has a single
   `baseline` commit and no tags; there is no per-lesson snapshot a learner
   (or auditor) can diff against. The brief notes an upstream `release-2.1.0`
   reference that postdates the course scope; it could not be verified from
   this offline copy and is in any case not the Lesson 16 dodge game. Every
   "changed files" claim above is therefore reconstructed from prose, not
   diffed — the audit compensates with exact line citations.
2. **Code blocks are excerpts but never say so.** Of the 90 GDScript blocks
   across the sixteen lessons (93 after this round's three added boxes),
   none is labeled excerpt vs complete; 8 blocks use literal `...`
   (ch3:325 title `_ready`; ch4:309 arena `_ready`; ch9:99 `open()`, ch9:156
   `_on_body_entered`, ch9:178 `_physics_process`; ch12:79 `_release`;
   ch14:38 `rank()`; ch14:100–102 `Score` methods), and dozens more silently
   omit members. Novices cannot tell "type this" from "this is the idea".
3. **Signals change signature without notice**: `touched_player.emit()` (ch8
   line 146) → `emit(global_position)` (ch9 line 172); `lit_changed` emit
   shown only in a warning box (ch4 lines 233–236); `charge_changed` /
   `flicked` declared late or never.
4. **Back-references to steps that never happened**: "In Lesson 5 we put the
   player on layer 2" (ch7 lines 76–77); "The title screen already emits
   `start_requested`" (ch3 line 313); "Making `title_menu.tscn` in Lesson 1
   was already making a scene" (ch2 line 65) for a scene with no build steps.
5. **Repo-only commands in blank-project context**: `pnpm game:check`
   (ch1–ch14 checklists), `pnpm verify` (ch15 line 330, ch16 line 325),
   `node .github/scripts/check-locale.mjs` (ch15 lines 98/288),
   `pnpm android:*` (ch1/ch11/ch16). In a blank learner project none exist;
   the course never gives the plain-`godot` equivalents.
6. **Terminology drift** (Minor): "Build it yourself" (ch1–ch8) vs "Implement
   it yourself" (ch9–ch13) vs mixed; "Exercises" (ch1–ch8) vs "Homework"
   (ch9–ch15); "Completion checklist" vs "Check that this much is working".
   Harmless but noticeable in sequence.
7. **Stale counts** (Minor): course intro "Five asset packs" vs six ZIPs
   (ch1 lines 311–318); ch1 "66 files (9.0MB)" (line 332) vs current manifest
   counts; docs intro asset totals vs `check:assets` (left for a counts pass,
   not verified here).

## Ordered backlog (remaining substantive work)

Ordered by dependency: each item unblocks the items below it. Severity is the
stall it removes. "Repaired this round" items are listed in the implementer
report, not here.

1. **B1 — Lesson 1 full title-scene construction steps (Blocker).** The repair
   this round adds a *minimal* title scene with a distinct file/tree so the
   course has an entry; the 1,296-node forest scene Lesson 2 assumes (ch2
   lines 92/458, tree at 102–116) still has no construction steps. Required:
   node-by-node build (or a checked-in `lesson-01` snapshot tag) covering
   Ground/Clearing/Scorch/Details/Trees, CanopyShade, Motes/Beams,
   MistFar/MistNear + `Mist` AnimationPlayer, Vignette, Beacon (Pit/Light),
   Fire CanvasLayer particle settings, BeaconFx flicker/flare keyframes,
   Ui/Bgm/Sfx nodes, and `title_menu.gd` (`start_requested`, tap handling,
   BGM fade). Until this exists, Lessons 2–16 have no verified entry.
2. **B2 — Per-lesson snapshot tags (Blocker-adjacent).** `lesson-01` …
   `lesson-16` tags (or a snapshots doc) with the exact file set after each
   lesson, so "changed files" and "exit checkpoint" become diffable. Without
   these, every future lesson edit re-risks silent drift.
3. **B3 — Complete the five never-constructed scenes + scripts (Blocker
   class, one item per scene):** `virtual_stick.tscn/gd` (L6),
   charge ring + beacon `Reach` wiring (L7), `spirit.tscn/gd` (L8), result
   panel (L9/L14), HUD (L10), pause panel (L11), dash members (L12), `.tres`
   creation + spawner wiring (L13), `Score`/`Records` completion (L14),
   settings/credits scenes + CSV key table (L15), Back/quit-prompt wiring
   (L16). Each needs: file path, creation steps, full node tree, full script
   (or exact diff), and asset paths.
4. **B4 — Arena/player/beacon/title script completion (Major).** Fill the
   undeclared members in the four scripts the course touches earliest:
   `title_menu.gd` (L1–L3), `arena.gd` (L3–L4: `_beacons`, `_forest`,
   `_run_ignition_sequence` call), `player.gd` (L5–L6: `facing`, `_sprite`,
   `_walking`, `speed`, `_wish`, `set_move_input`, `set_walking`,
   `WALK_THRESHOLD`, knockback/dash fields), beacon charge members (L7).
   Prefer small "required members" boxes in each lesson over full rewrites.
5. **B5 — Excerpt labeling pass (Major).** Mark every code block as
   complete-type-this vs excerpt, per the convention note added this round;
   reconcile the `...` blocks and the silent-signature changes
   (`touched_player`, `lit_changed`/`charge_changed` emits).
6. **B6 — Blank-project command variants (Major).** For each repo-only command,
   give the blank-folder equivalent: `godot --headless --path <folder>
   --quit`, plain `godot --export-debug` + `adb install` + `monkey`, manual
   locale CSV check, `keytool`/`apksigner`/`aapt` (already plain). Lesson 1
   repaired this round is the template.
7. **B7 — Export-template + debug-keystore setup steps (Major).** Neither the
   course nor the reference intro steps through installing Godot export
   templates or the Android debug keystore; Lesson 11 assumes both.
8. **B8 — Homepage hero scope sentence (Minor).** Repaired this round if the
   director accepts the one-line hunk; otherwise still open.
9. **B9 — Terminology + counts pass (Minor).** Unify Build/Exercises/checklist
   headings; reconcile pack/file counts with the manifest and `check:assets`.

## Correction (2026-10-13, round 3) — the shipping joystick finding was false

The Lesson 6 entry above claims the shipping game carries the fixed-404
anchor defect because `apps/game/scenes/ui/virtual_stick.tscn` holds the
same three lines. That reading was wrong: `apps/game/scenes/gameplay/
arena.tscn` lines 126–131 override the `MoveStick` instance to full-screen
(`anchors_preset = 15`, `anchor_right = 1.0`, `anchor_bottom = 1.0`,
`offset_right = 0.0`), so the shipped stick covers the whole screen and the
fixed width never binds. The historical lesson snippet (preset 9 +
`offset_right = 404` with no `anchor_right`) was still wrong as a
half-width recipe, and the Lesson 6 prose fix stands — but no shipping-game
defect follows, and no native fix is needed. The original paragraph is left
in place above so the correction stays visible.

## What was actually checked (engine/file evidence)

- Anchor probe: `/tmp/anchor_probe.gd` via
  `pnpm godot:isolated --timeout 120 --headless --script /tmp/anchor_probe.gd`
  → host 1200×360: lesson excerpt `(404, 360)`; fixed `(600, 360)`.
- Tracked-asset existence: `tileset_camp.png`, `tileset_nature.png`,
  `fx/raylight.png`, `actor/ninja_walk.png`, `actor/ninja_idle.png`,
  `audio/music/arena_theme.ogg`, `guardian_theme.ogg`, `title_theme.ogg`,
  `kenney/ui_audio/ui_confirm.ogg` all present under
  `apps/game/assets/third_party/`; `Galmuri11.ttf` absent (only
  `.tres` pointers to MapleStory+Noto remain).
- Fire-pit AtlasTexture region `(160, 48, 32, 32)` on `tileset_camp.png`
  (368×144): cropped and visually confirmed via ffmpeg (stone ring + fire,
  no neighbor bleed).
- Script-existence grep: no `title_menu.gd`/`arena.gd`/`player.gd`/
  `spirit.gd`/HUD/pause/result/settings creation steps in their lessons; no
  `var facing` / `@onready var _sprite` / `var _walking` in chapter-05;
  `charge_changed`/`touched_player` never declared; `start_requested` first
  appears chapter-03 line 313.
- No engine scene runs, no captures, no device runs (per brief constraints).
  The repaired Lesson 1 minimal-scene steps and Lesson 6 anchor values are
  file-verified (paths exist, region visually confirmed, anchor math probed)
  but not play-verified; the director reproduces the title steps.

## Practice track (rounds 3–4) — what the new checkpoints close, and what they do not

Rounds 3 (Lessons 1–8) and 4 (Lessons 9–16) added a complete runnable
reconstruction under `examples/course/`: per-lesson source layers, a
deterministic creator (`scripts/course-create.mjs` → standalone projects in
`builds/course/` or a NEW/empty folder), an error-gated verifier
(`scripts/course-verify.mjs`), and a practice guide
(`apps/docs/course/practice-foundation.mdx`) linked from the course overview
and every lesson page. The track closes its *own* entry/dependency gaps: each
checkpoint is a full project with exact node paths, full-file source, music
looping through portable `loop_stream` setup, clean audio teardown via
`AudioFlush`, a separate `Moonlit Course Reference` /
`com.example.moonlitcourse.ref` identity (learner stays `Moonlit Course` /
`com.example.moonlitcourse`; shipping untouched), and one exercise plus an
observable success criterion per lesson.

It does not rewrite the historical prose, so the lesson-body findings above
still describe the original text where they differ: the minimal nine-node
title vs the 1,296-node forest (B1 stays open for the historical build),
twenty-node Lesson 2 forest, practice-chosen values (`BGM_SILENCE_DB` −80,
`WALK_THRESHOLD` 8.0, `CHARGE_SECONDS` 2.0, spirit speed 52), MapleStory Light
instead of Galmuri, `AudioFlush` instead of the nonexistent
`AudioStreamPlayer.release()`, explicit `tr()` + `Settings.changed` redraws,
buses created in `Settings._ready`, and a debug-only `.ref` export preset.
Per-lesson reconstruction diffs take the place B2 wanted for snapshots, but
no historical tags were invented. Corrected in round 4: Lesson 9's
`Rect2.merge` wording (bounding rectangle, not a narrowed path) and Lesson
13's guardian layout (explicit single-facing five-frame row, tested beside
ordinary spirits).

Sizes (2026-10-13): `examples/course/src` 4.9M in 123 files, each binary
stored once with licenses in `examples/course/REUSE.md`; generated outputs
Lesson 1 2.1M/8 files, Lesson 8 6.4M/32 files, Lesson 16 7.3M/60 files
(round 6: 9/33/61 files with the MIT notice; sizes unchanged at this
precision; `src` 124 files).
Engine used here: 4.7.2.stable.official.ed1daf0bf only; the 4.7.1 pass and all
rendered-stage inspection are the director's.

Executed in this round (all pass): `node scripts/course-verify.mjs` 16/16
`import/compile/boot/checks ok` with ERROR/SCRIPT ERROR/parse/leak rejection
at any exit code; `pnpm test:course` 18/18; break-it loop-flag flip fails L3
with both music contracts then restored byte-identical (md5
2a3bf15d6cbf01cc2f09a13757ed030e); `pnpm docs:build`, `check:docs`,
`hosting:build`, `hosting:check`, `test:hosting` 26/26, `growth:check`,
`test:growth` 7/7, `check:skills`, `check:hygiene` (2859 tracked),
`git diff --check` clean.

Explicitly NOT verified: phone multitouch, Android export/signing/device
install, future engine versions, and browser rendering (director inspects).
B5 (excerpt labeling of the 90 historical blocks), B6 (blank-project command
variants beyond Lesson 1), B7 (template/keystore setup steps), B8/B9 (minor
wording/counts) remain open against the historical prose.

## Practice track (round 5) — confirmed gaps closed

The director's round-4 probes confirmed seven findings; all are fixed
and covered by automated checks. No new findings were invented.

1. **Signing-material filter** (creator): `.p8`/`.pem` were copied into
   outputs. `KEY_FILE_PATTERN` now covers them on the layer path, and the
   asset path refuses excluded names instead of copying. Synthetic
   `synthetic-signing.p8` / `synthetic-certificate.pem` markers in tests;
   no real key material exists anywhere in the tree.
2. **Source-alias containment** (creator): `assets/art` → external passed
   because `lstat` saw the final file as regular. Every source now resolves
   through `realpath` and must land inside its root (layer in sources,
   asset in assets, file in layer); both sides canonicalized so legitimate
   `/tmp` aliases keep working. Fake-repo + fake-external regression tests
   for the asset-parent alias, the layer-parent alias, and excluded asset
   names; every refusal leaves no partial output (asserted `ENOENT`).
3. **User-data snapshot wording** (verifier): size+mtime entries are now
   size+sha256 content hashes, so "untouched" means byte-identical; a bare
   timestamp touch is no longer flagged. A same-size edit
   (`best=10` → `best=11`) is the regression test.
4. **Environment-noise overmatch** (verifier): the `noErr` substring match
   swallowed `SCRIPT ERROR: Parse Error: Identifier noErr is not declared`.
   The exclusion is now the observed native condition text
   (`Condition "ret != noErr" is true`) only; the synthetic parse-error
   line is a pinned fixture, and the genuine CA-store noise still passes.
5. **Finish freeze** (checkpoints 9–16): the Lesson 11 probe showed charge
   0.0167→1.0, `lit_count` 1, and 3.07px drift after a loss. `beacon.freeze`
   moved from Lesson 14 to Lesson 9 (byte-identical file; the Lesson 14
   overlay is deleted), new `player.freeze()` drops velocity/wish/knock/dash
   at once, every `_finish` calls both, and `_on_beacon_lit_changed`
   returns early once over. Spawns were already `_over`-guarded; spirits
   already stop without a target. Lesson 9's loss contract now lands on a
   partial charge with live knockback velocity and asserts the frozen
   charge, position, count, and spirit; Lesson 14 asserts the held player
   position too. Result/restart UI and visual animations are untouched.
6. **Real teardown** (checkpoints 3–16 + verifier): the Lesson 3
   `--quit-after` probe and the Lesson 16 Yes-button probe both exited 0
   with 4 ObjectDB leaks + 2 resources in use. Every sounding scene now
   arms a production graceful close (`set_auto_accept_quit(false)` +
   root `close_requested` → release, one mix wait, quit); QuitPrompt Yes
   emits `quit_confirmed` to the title instead of quitting mid-music. The
   surrogate `boot_probe` (manual instantiate + test-side release) is
   deleted; `close_probe` runs as a scaffold-only autoload under normal
   engine startup with real autoloads and `current_scene`, drives
   title → arena → production restart, then triggers the production close
   (window path lessons 3–16, Yes path lesson 16, plain quit lessons 1–2
   which have no script and no looping voice). Clean exits with music
   playing are the proof, gated on `BOOT RESULT` + `CLOSE SENT` + zero
   defects. Reverting Yes to a direct quit reproduces the exact
   director finding (exit 0, 4 leaks, 2 in use) and fails the gate.
   `--quit-after` on the fixed Lesson 3 still leaks: the engine never
   delivers `close_requested` on a forced quit, so no handler can run —
   a harness limitation, documented in the guide, distinct from the
   player's verified close path.
7. **Debug-preset correction** (checkpoint 16): `package/signed=false` is
   now `true` with no keystore/password material in the file; the check
   asserts both. Signing vs Export With Debug, the local debug key, SDK /
   template / JDK prerequisites, and the create-the-output-folder step are
   in the Lesson 16 guide section. No APK was built and no device test was
   run; the learner's own export remains theirs to perform.

Sizes (2026-10-13): `examples/course/src` 4.9M in 123 files, unchanged
count (beacon moved 14→9; close probe replaces boot probe 1-for-1 in
`tests/`). Engine used here: 4.7.2.stable.official.ed1daf0bf only.

Executed in this round (all pass): `node scripts/course-verify.mjs` 16/16
with real-startup close runs; `pnpm test:course` 22/22; break-it player
freeze (L9 fails 2 freeze checks, restored green); break-it Yes revert
(L16 `close yes` fails with the exact 4-leak/2-in-use signature, restored
green, L16 re-verified); forced-quit experiment above; `pnpm docs:build`,
`check:docs`, `hosting:build`, `hosting:check`, `test:hosting` 26/26,
`growth:check`, `test:growth` 7/7, `check:skills`, `check:hygiene`,
`git diff --check` clean.

## Practice track (rounds 6–7) — publication-readiness reconciliation

Round 6 was interrupted by provider quota; round 7 finished the same brief
without redoing settled work. Director independently verified the round-6
tree: `test:course` 24/24 and full `course:verify` 16/16 on EACH of
official 4.7.1 and 4.7.2 (desktop/headless: real startup, production
transitions/restarts/close, fresh-process records/settings, isolated data),
plus a clean MovieMaker L16 arena/dash render. Citable scope stays
desktop/reference only — not phone, APK, native sign-in, human sessions,
public launch, or future engines.

Round-6 fixes (verified, kept): dash-ghost sprite-offset copy with a
creation-alignment contract (breathe animation forced pinning the offset at
dash time; break-it fails the offset check); creator `src`/`src/assets`
root-alias boundaries with both fake-repo fixtures (24/24); MIT notice
shipped byte-identical in every output with named credits and export
include filter; guardian_theme provenance corrected (independent 18/18
byte-match re-confirmed); homepage reworked (mastery lead, practice link,
4.7.1/4.7.2 versions, v2.1.0 hero caption); first-play page/protocol/
measurement corrected (install-now-open-later, app version at session,
guest/sign-in, source+campaign matching, Sep-21 outage scope); E04 single
coordinated program superseding E01b/E02-course; Docusaurus anchor warning
reconciled via `pathname://` plus built-HTML fragment validation in the
hosting checker (27/27); Lesson 3 `AudioFlush` excerpt aligned with the
practice source (shipping `music_player`/`sfx_player_2d` wrappers
acknowledged as real); Lesson 1 stretch corrected both directions with the
official doc link.

Round-7 completions: the practice guide is now the primary route — a First
actions section (engine, fresh clone, clone-only create command, separate
learner project) plus Start-from / Settings / Open-and-check lines in all
16 lessons (16/16/16, with 4 inherited-path Compare notes and 16/16
Modify/Verify kept). Guide diffs reconciled against final source:
AudioFlush L3, freeze L9, `BOUNDS Rect2(24, 120, 760, 202)` L6 with the
L9 `DEFAULT_BOUNDS` rename, offset-aligned ghosts L12, MIT from L1,
license include filter L16; the L7 `audio_flush.gd` "added" claim fixed to
inherited-from-lesson-03. B6 closed: all 30 repo-only `pnpm` sites in
chapters 2–16 now show blank-project commands first with clone shortcuts
labeled (checklists, verify fences, L11/L16 export blocks and danger
notes). Homepage "three areas" corrected to the current survivor's six
places; practice game stays three beacons/90 seconds. E03 corrected to
late-inconclusive on a matched Oct-13 after-week read (no verified verdict
by the missed Oct 2 deadline; no claim about Sep 24/28 reads); E02 set to
not_run with its Oct 9 deadline retained; G15 evidence aligned to E04;
earlier history byte-identical. Removed one redundant file (L16
`moonlit.csv.import`, byte-identical to L15's; generated L16 output
verified identical); `src` is 123 files. `examples/course/README.md`
updated from 1–8 to 1–16. Tracker-update draft written (unposted); round 8
moved it to `notes/growth/course-tracker-update-draft.md` after the diff
guard flagged the brief-ordered `notes/workflow/muse/` path as protected —
nothing remains under that path.

Executed in round 7 (exit codes quoted, none hidden): `pnpm docs:build` 0
(zero broken-anchor warnings), `check:docs` 0, `hosting:build` 0,
`hosting:check` 0 (2179 local links, 316 outbound),
`test:hosting` 27/27, `test:course` 24/24, `course-verify` 16/16,
`check:skills` 0, `check:hygiene` 0 (2859 tracked), `git diff --check` 0,
`growth:check` 0, `test:growth` 7/7. `test:game` not run (no `apps/game`
change). Remaining open: B1 (historical forest steps), B2 (historical
tags), B5 (90-block excerpt labels), B7 (template/keystore setup detail),
B8/B9 (minor wording/counts); phone/export/signing/device/browser-render
verification stays the director's.

## Round 8 (Brief 246): source links, executable route, honest gate

Practice guide now links every add/replace file through Lesson 16 to its
complete published source: 131 `blob/main` links under
`examples/course/src/` (lesson layers plus the shared `assets/` single
copy), each verified to exist on disk with its label matching its URL
path, and all 131 present in the built guide HTML. Inherited files in
Compare notes resolve to their actual earlier layers (title scene/scripts
to lesson-01/03, audio helper to lesson-03, result card to lesson-09,
stick/HUD/player to lesson-11/10/09). Each lesson with assets names the
clone source (`examples/course/src/assets/…`) and the exact project
destination (19 assets, destinations from the manifest). The whole-file
rule is now a parts-shelf rule: build from the lesson first; where the
lesson leaves construction details out (the Lesson 2 forest is the named
case), creating the NEW file from the linked complete source is allowed;
replacing a file you built requires a backup/commit plus only the named
changes; then open, read, Modify, verify. Build/explain/modify/verify and
the capstone are preserved; clips stay labeled historical.

The round-7 blank-project `--quit` gate is replaced in all 16 lessons plus
the capstone criteria: a forced quit bypasses `close_requested` while
music plays, so it could not meet its own no-error criterion from Lesson
3 on. The gate is now `godot --headless --path . --import` with an honest
scope note (validates editor open + resource import; does not compile
scripts — proven: a broken script imports with exit 0 and no errors — or
run gameplay; Play plus window close is the runtime proof; the reference
verifier keeps headless compile/boot/gameplay proof). Lesson 15's
checklist notes the run-twice first-import translation notice. The
chapter-15 `--import` danger note already agreed and is unchanged.
`examples/course/README.md` now links the Firebase course URL
(`https://moonlitbeacon.hyo.dev/MoonlitBeacon/course/practice-foundation`)
instead of a site-root path that resolves to the wrong host on GitHub.
The tracker draft moved to `notes/growth/course-tracker-update-draft.md`
(content preserved); nothing remains under `notes/workflow/muse/`.

Executed in round 8 (exit codes quoted, none hidden): `pnpm docs:build` 0
(only the known untracked-files notice), `check:docs` 0,
`hosting:build` 0, `hosting:check` 0 (2179 local links, 447 outbound —
+131, exactly the new source links), `test:hosting` 27/27,
`test:course` 24/24, `course-verify` 16/16, `check:skills` 0,
`check:hygiene` 0 (2859 tracked, 10 locked values), `git diff --check` 0,
`growth:check` 0, `test:growth` 7/7. `test:game` not run (no `apps/game`
change). No runtime/source change under `examples/` this round; the
verifier re-run confirms the published checkpoints still pass. Remaining
open items are unchanged from round 7.
