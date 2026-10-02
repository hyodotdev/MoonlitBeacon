# 3.0.0 release plan (the director's working plan)

Written 2026-09-30. The user asked for three things at once: take 3.0.0 all the way to a final release state; shoot
every store screenshot that the update changes, in advance, **without uploading anything to a store**; and have the
implementer build it while the director supervises. This file is the director's map. It changes as work lands; the
implementer's own records are `notes/plans/3-0-0-build-log.md` and `apps/docs/docs/game.md`.

## What "final release state" means here

Everything below is done and checked, on a branch, locally. Nothing is pushed, opened as a pull request, merged,
tagged, uploaded or submitted: each of those is the user's decision and none is implied by this plan.

- The game is finished for 3.0.0 and green: `pnpm verify` passes on the real tree, apart from the store-image checks,
  which are green again once the images are recaptured (see "Store screenshots").
- Version numbers are locked at 3.0.0 (Android code 15, iOS build 10) in `project.godot` and `export_presets.cfg`.
- Docs are true to the game: `apps/docs/docs/game.md`, the asset manifest, `README.md`, the build log.
- Store text is ready in five languages (what is new, description changes) and `pnpm check:store-metadata` passes.
- Builds exist locally and pass their checks: signed release APK, Play AAB, iOS archive and App Store IPA (validated with
  the dry-run commands; the real upload commands are not run).
- Store screenshots, IAP images and store graphics for everything the update changes are captured and staged, with the
  capture report, and not uploaded.
- The work is committed in coherent commits on `feat/3-0-0-ui-story` (commit only; the user says when to push).

## Work packages

| # | Package | Written by | Depends on | Status |
| --- | --- | --- | --- | --- |
| 1 | Bullet weaving: enemies and guardians shoot many slow missiles, the player weaves (brief 001) | implementer | none | **round 1 running** (started by the user from their terminal) |
| 2 | Result screen depth past the win, one English word for a cycle, shop lines no longer clipped (brief 002) | implementer | 1 | brief ready |
| 3 | Docs true to 3.0.0: README, version passage, audit of `game.md` against the code (brief 003) | implementer | 1, 2 (both edit `game.md`) | brief ready |
| 4 | Store text for 3.0.0 in five languages, `check:store-metadata` green (brief 004) | implementer | none (can run beside 1 and 2) | brief ready |
| 5 | Release record: checklist section and `release-3.0.0.md` (brief 005) | implementer | none (can run beside 1 and 2) | brief ready |
| 6 | Game freeze: full `pnpm verify`, budgets, bot play-through of every hero and place | director | 1 to 5 | |
| 7 | Store screenshots, IAP hero images and store graphics recaptured for what changed (not uploaded) | director runs the pipeline; the implementer fixes it if it breaks | 6 | |
| 8 | Builds: signed APK, AAB, iOS archive and IPA validated, no upload | director | 6 | |
| 9 | Commits on the branch | director | 6 to 8 | |

1 and 2 touch `apps/game/`, and 1 and 3 both touch `game.md`, so they run one after the other; each run starts from a
copy of the tree as it is after the previous `accept`. 4 and 5 touch only `notes/release/` and
`notes/plans/release-3.0.0.md` and can run beside 1.

**Starting a run** is refused for the director's agent tool (permission classifier, "Create Unsafe Agents"), and the
director did not work around it. The user starts each run from their terminal with `pnpm muse run <brief>`, or adds
the permission rule `Bash(pnpm muse:*)` themselves; `pnpm muse status|log|report|diff|accept|revert|discard` are not
blocked and stay with the director.

## Baselines the director measured on the untouched tree (2026-09-30)

- `pnpm test:game`: passes (41 checks).
- Natural first loops, 12 runs (`nat_base`, `seed=5 speed=3 loops=1`, same command as brief 001): 44 hits in 43.5 minutes
  = 1.01 a minute; by cause caster 20, stalker 10, ember 5, weaver 4, wisp 1; bullets peak 50, average in the air 6.1,
  weaving share 26%; nothing stuck; no guardian fight in a first loop.
- Guardian gauntlet, 18 runs (`base-gauntlet`, `gauntlet=1 guardians=0,1,2,3,4,5 starts=2,6,12 runs=18 seed=11 speed=3`):
  42 hits in guardian fights over 22 fights = 1.9 a fight (camp siege 3.0, ruins 2.7, marsh 1.7, storm 1.3, frost 1.0,
  forest thorn 0.3); causes aura 13, stream 12, caster 10, guardian bolts 8; bullets peak 103, average 17.3, weaving
  share 34%; nothing lost to a soft lock.
- Reading: the guardian fights already sit inside brief 001's band; the first loop's weaving share (26%) is the gap
  (the band asks for 35%), and none of it is tested, documented or looked at yet.
- Measurement note: batches run detached with `nohup` in the background ran about seven times slower than the same
  batch in a foreground terminal (12 runs took 8 minutes for the implementer, 55 minutes and unfinished for the
  director). Run measurement batches in the foreground or with the tool's background mode, never `nohup ... &`.

## Director's UI audit (2026-09-30)

All 22 screens in all five languages, photographed with `tools/shot_ui.tscn` on the working tree (`builds/shots/ui/`).
No blocking defect: text fits, every language is present, no placeholder or gray box. Findings, all minor, are in
brief 002: the result screen says "Cycles" past the win where the HUD says "Depth"; English calls the loop Wave, Cycles
and Depth in different places; the shop's hero cards clip the stat line with an ellipsis. Not defects (the harness
passes raw English strings or shoots while a fade is running): the HUD's boss name and banner, the settings language
highlight, the dim consent buttons, the pale act-card title. The title screen's dev chips (Shards+500, Lv10, ...) are
debug-build only.

## Gates for every accepted round

`pnpm muse accept` only after: the report is read against the diff; no protected path changed (or each was reviewed and
allowed); `pnpm test:game`, `pnpm game:check`, `pnpm check:hygiene` pass in the copy; the numbers named in the brief are
reproduced by the director; for anything a player sees, the pictures were looked at. After accept: `/verify` on the
real tree.

## Store screenshots (package 7)

The user's instruction (2026-09-30): shoot everything the update changes in advance, do not upload.

- `AGENTS.md` still governs: recapture only what actually changed, list which screens changed how and the exact files
  before capturing, lock version and build numbers first (they are locked), and never upload.
- The capture report pins the hashes of the source files. Any change under `apps/game/` invalidates all four sets, so
  capturing happens **once, after the game freeze**, never in between.
- Sets: phone (Pixel_10 AVD, five locales), 7-inch, 10-inch, iPad. The iPad set needs the user: a physical iPad and the
  RSD tunnel started with `sudo` (`scripts/ios-tunnel.sh`). The director prepares everything else and tells the user
  exactly what to run.
- The IAP hero images and the hero bundle image show redrawn characters and are rebuilt with the store graphics.
- Emulators are used for capture; no phone is touched without the user's word.

## Operations runbook (packages 6 to 9, the director's)

Nothing here uploads. Run measurement batches in the foreground (or the Bash tool's background mode), never `nohup`.

**6. Freeze** (after briefs 001 to 005 are accepted; from here no change under `apps/game/`)
1. `pnpm verify` on the real tree.
2. Bot: natural first loops (12 runs), guardian gauntlet (18 fights), one boosted run per place at cycles 3 to 16
   (commands in `notes/plans/3-0-0-build-log.md`), each compared with the baselines above.
3. Budgets: `test_late_game_performance` (1200 nodes), bullets peak, frame max.
4. Look: `pnpm godot:isolated --windowed --timeout 900 res://tools/shot_ui.tscn -- en,ko,ja,zh_CN,zh_TW`, the bullet and arena
   harnesses, and read the pictures.
5. `pnpm check:store-screenshots` is red (expected) until step 7 below.

**7. Store images** (only after the freeze; a change under `apps/game/` afterwards invalidates all four sets)
1. Done already (2026-09-30): `pnpm store:graphics` regenerated the six IAP hero images from the redrawn heroes;
   `pnpm check:store-graphics` passes. The feature graphic, icon, supporter and lantern-colors images did not change.
2. List which of the six screens changed and how, and the exact files to recapture (AGENTS.md asks for it): all six
   (`01-moonlight-barrage` to `06-hero-preview`) show the new UI kit, lighting or redrawn art, in five locales, so the
   whole set is recaptured. The capture automation's fixed taps (Settings at 764,25; language buttons at y 122, x 292,
   348, 404, 460, 516) were checked against the new title and settings screens and still land on their buttons.
3. Phone: AVD `Pixel_10`; tablets: `Moonlit_7_API36` and `Moonlit_10_API36` (all three exist). `pnpm store:capture-screenshots`,
   the tablet evidence script, then `pnpm store:screenshots:play`, `pnpm store:screenshots:app-store:android-pixel-avd`,
   `pnpm check:store-screenshots:play`, `pnpm check:store-screenshots:app-store`.
4. iPad 13": needs the user (`sudo ./scripts/ios-tunnel.sh`, a trusted unlocked iPad) and
   `pnpm store:capture-ios-device -- --target ipad-13 --all-locales`.
5. Outputs land in `builds/release/` (untracked). Copy into the tracked `stores/` submission folders only with
   `pnpm store:sync-play` / `store:sync-app-store` after reading what those scripts do (they must not upload).

**8. Builds** (local only): `pnpm android:build`, `pnpm android:release`, `pnpm android:bundle`, `pnpm ios:archive`,
`pnpm ios:export-appstore`, `pnpm ios:validate:dry-run`. Not run: `ios:upload`, `ios:validate` (network), any Play or
App Store Connect apply script.

**9. Commits** on `feat/3-0-0-ui-story`, by path as `.claude/commands/commit.md` says (game, docs, notes, process files
separately; art assets apart from code), each with the tool's attribution line and an `Implemented-by:` trailer. No push.

## What only the user can do

- Start the iPad RSD tunnel with `sudo` for the iPad set, and keep the iPad awake and trusted.
- Say when to push, open a pull request, merge, tag, upload builds or screenshots, or touch a store console.
- Deploy `firestore.rules` (changed in the working tree, not deployed).
- Judge how the game feels to play; the bot is a proxy.

## Not doing

Push, pull request, merge, tag, store upload, store console changes, telemetry activation, recapturing before the freeze.
