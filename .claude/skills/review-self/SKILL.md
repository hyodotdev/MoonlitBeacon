---
name: review-self
description: Independently review the work just done, working-tree changes, or a PR; fix only defects whose evidence is confirmed; re-run related verification; repeat rounds until it is stable or truly blocked. Use when the user says "review-self", "self review", "look at what you did again", "there's no review bot so you look", or asks you to keep watching whether new problems appear after an implementation.
---

# Review it yourself

There is no review bot. I look again at what I made.
**Every round, actually re-read files, actually run commands, and leave
evidence.**

## Keep permission and scope

- Being called means **you may read, fix inside scope, and run verification**.
- **Do not exceed the original request's permission.** Unless the user already
  allowed it, do not commit, push, create/edit a PR, merge, deploy, or
  release. This repo **requires user confirmation to push**.
- Fix only what is attached to the original goal. Do not inflate self-review
  into a broad audit, a taste refactor, or unrelated cleanup.
- Do not sweep in changes the user was touching. Stage only files this round
  touched.
- If a fix needs a product call, is irreversible, or grows scope a lot,
  **stop and ask**.

## Decide what to look at

1. From the conversation and the repo, restore "what were we trying to do"
   and its pass criteria.
2. If a PR, branch, commit range, or path was given, look at that.
   Otherwise look at the current branch + staged + unstaged + untracked
   changes.
3. If it is a PR, take the real base and head from PR metadata.
4. **First read** `AGENTS.md` and `.claude/commands/*.md` that apply to the
   paths you touched.
5. If there is nothing to look at, report briefly and stop.

## One round

1. **Re-read from disk.** Do not trust the previous round's memory.
   Do not look only at the last commit; look at the whole base…head.
2. Confirm the following with evidence. Do not write guesses.
   - Was everything asked for actually done, end to end
   - Correctness, error paths, boundary values, state transitions, data safety
   - Docs and reality do not disagree —
     **actually run the commands written in the docs**
   - Repo-rule violations (`AGENTS.md`)
3. Verify findings **against the current code**. Drop taste, cosmetics,
   duplication, and side branches.
4. Fix only the verified set as one bundle.
5. After the fix, re-run `/verify` and checks for the paths you touched.
6. If there is a PR, look at CI results as evidence too.

## Defects this repo is especially good at

These have actually come up. Start here every round.

| Defect | How to confirm |
| --- | --- |
| **A bulk replace mashed different values together** | Scan for adjacent identical lines. Changing `phase-00`/`phase-01` to `chapter-01` once made both the same |
| **Numbering system only half-changed** | There was a table whose heading said "Lesson" while values were still 0-based |
| **A command written in the docs does not run** | Copy the written command as-is and run it. `pnpm verify` once failed because it could not find `godot` |
| **Dead anchors** | `onBrokenAnchors` defaults to `warn`, so the build passes. Look with `node .github/scripts/check-anchors.mjs` |
| **Hardcoded absolute paths** | `grep -rnE "[A-Za-z]:[\\\\/](Users|Github)" notes .claude scripts` — dies on someone else's PC |
| **Placeholders left on screen** | Look at a device screenshot. Gray rectangles, debug strings, default fonts |
| **Exaggerating a representative device run as all-direction E2E** | On a visual change, split the three rows in the [visual E2E evidence contract](../moonlit-workflows/references/visual-e2e.md) — physical device, production-PNG exhaustive, automated checks — and write empty cells in the direction matrix |
| **Clip budget exceeded** | Silent? Under 1MB? |

## Repeat rounds — until nothing more comes out

When a round ends, report **what you looked at, what you fixed, and what is
left**. Do not write only "nothing wrong"; write **how you confirmed it was
nothing wrong**. Leave the method (commands run, values compared) so the next
round does not repeat the same work.

### The next round starts from what you have not looked at yet

Do not rescan the same place and repeat the same conclusion.
**Accumulate a seen-list every round**, and pick from what remains.

When you have finished an area, change the angle. If you read docs, measure
the numbers those docs claim; if you read a command, actually run that
command.
**"It looked fine when I read it" is not confirmation.** Confirmation is
running it or counting it.

### Stop conditions

**Stop when two consecutive rounds find nothing to fix.**
One clean round is not enough — change the viewing angle and usually more
comes out.

When you stop, report this.

- Every area looked at so far, and how each was confirmed
- Everything that was fixed
- **What you intentionally left unfixed, and why**
  (needs a product call, needs a user decision)

If there is truly nothing left to look at, say clearly "nothing to look at".
Do not promote a taste issue to a defect just to fill a round.

### Automatic repeat

If the user sets a period like "every 5 minutes", hang it with
`/loop <period> /review-self`.
**Do not fake a wait loop with `sleep` or `while true`.**
Do not run it as an abandoned background process either.

Right after hanging it, **write the job ID in the report.** You need it later
to turn it off.

### Breaking the loop is CronDelete, not words

While the loop is running, the stop conditions above still apply.
If two consecutive rounds are clean, **that round must run the following**.

1. Confirm the job ID with `CronList`
2. Delete it with `CronDelete`
3. Call `CronList` again and **confirm it is empty**
4. Write that fact in the report

**Do not write "ending the loop" and move on.** Cron cannot hear that.
Leave it and it keeps waking every 5 minutes with nothing to fix, until the
automatic expiry (7 days). Automatic expiry is a backstop, not a stop
mechanism.

Do not resume until the user says to keep going again.

### Round log

What has come out of this repo per round so far (the next round refers to
this).

| Round | Looked at | Came out |
| --- | --- | --- |
| 1–2 | Doc contents, build output | Lesson-number tables, mashed tags, dead anchors, `pnpm verify` not working |
| 3 | Capture tools, GDScript | Absolute paths, missing guard after `await` |
| 4 | Assets, scenes, generator scripts | Wrong asset count, unverified manifest |
| 5 | git config, recording scripts | `.mp4` not declared binary, master filenames, script/prose section mismatch |
| 6 | Numbers the docs claim, license notices | Direct `godot` calls vs pnpm shortcuts disagreed |
| 7 | Page transfer size, Pages settings | First transfer 2.9MB, deploy would fail because Pages was not set up |
| 8 | Editor tasks, `known_issues.md` | Three VS Code tasks could not find `godot` |
| 9 | CSS, command-doc references | Dead CSS, broken paths, Phase check missed lowercase |
| 10 | `.gitignore`, release procedure | Release export path missing `../../` |
| 11 | APK launcher icon, render output | Adaptive icon clipped by the mask (waiting on an art call) |
| 12 | This skill itself, `/record` snippets, sidebars | CI check added in round 10 was a false positive; path-omission being allowed was not in the docs |
| 13 | **Reverse exhaustive check of fixes**, manifest licenses, device tab | **None (first clean round)** |
| 14 | CI-step exit codes, commit conventions | **None (second clean round → loop ended)** |
| 15 | Full audit after finishing Lesson 16 (six angles in parallel + per-finding disproof) | 38 of 50 confirmed. **Blocked 1** — results screen not tappable on device |
| 15 | Commits after round 14 (this skill itself) | This doc's closing sentence was already untrue |

**PR #2 (Lesson 2)**

| Round | Looked at | Came out |
| --- | --- | --- |
| 1 | Following the lesson procedure, docs build | **The procedure could not be followed** (beacon split across two places) · homework covered by animation and not working · NUL bytes were an upstream bug and the CI check was broken |
| 2 | **Actually render and compare the screen the docs asserted** | It was not the same as Lesson 1. Clearing light died (PSNR 28.2) and the flame washed out. Light 3.2× · flicker into the beacon scene · `light_mask` |
| 3 | Idioms the repo already used | The same meaning was newly expressed as `light_mask = 2` (existing was `0`) |
| 4 | README, on-screen copy quotes | README marked Lesson 2 incomplete · three docs quoted copy that is not on screen |
| 5 | CI rules themselves, new scripts | No `_tmp_*` commit-prevention check · comment paths used Windows separators |
| 6 | Numbers the docs claim, **reverse exhaustive of fixes** | 1 line-count item. 0 regressions |
| 7 | Reference docs, tag conventions, full clip playback | None of the tags the docs wrote existed · `-start` convention differed per doc |
| 8 | **The procedure docs themselves** | `/chapter` asked for a tag **before merge** (squash, so it floats) · no README-update step · script format differed per lesson |
| 9 | PR body | 8 rounds of work were missing and numbers were still wrong |
| 10 | Editor tasks, `project.godot`, `VideoEmbed`, section cross-refs | **None (first clean round)** |
| 11 | **Machine-exhaustive of the done criteria the lesson posted** | **None (second clean round → ended)** |

**Physics interpolation + Warden redesign branch**

| Round | Looked at | Came out |
| --- | --- | --- |
| 1 | Interpolation-reset exhaustive · tscn properties · duplicate semantics, full generator · validator run · measured color, docs grep, hygiene · store-fingerprint | Generator comment scale 5→4 in two places · palette comment 19→20 colors · visual-e2e 5px leftover · intro.md missing physics-key explanation · manifest color-count error. 13 red store-fingerprint items reported only, per the rule |
| 2 | **Reverse exhaustive of fixes**, measured numbers the lesson asserts, fresh-eye screen review | All 4 findings disproved — **none (first clean round)** |
| 3 | **Reproduce the patched teleport path on device** — beacon-3 cycle transition · boss spawn · slash · walk, emulator recording frame measurement | **None (second clean round → ended)**. Could not recapture dash (continuous physics motion, same path as walk) — recorded as a boundary |

### What this PR taught

**Assertions like "the screen is the same as the previous lesson" must be
rendered and compared.**
Round 2 caught the biggest item in this PR. Change the structure and it is
not color that drifts but **light**, and places light does not reach match
on their own, so a visual skim passes. You have to measure mean RGB and
PSNR.

**When you write a new checker, also run it the other way.**
Round 11 looked too broadly at "is a CanvasLayer left" and failed the
legitimate `Ui` layer. Had it been round 12, we would have deleted something
fine.

---

**This table is the only evidence of progress.** Do not write a timestamp
sentence outside the table like "stopped at round N". The moment rounds run
again that sentence is immediately false.
The round-14 closing sentence actually became false in round 15.
Judge whether you stopped by **whether the last two rows are both "none"**.

### Know this

**Meta usage is not a violation.** `Phase` in a sentence that explains the
ban itself is normal (`AGENTS.md`'s `### Do not write "Phase"`, a commit
title like "Phase check used to miss lowercase").
If the checker catches that, the checker is wrong.

**If the user calls again after a stop, then it runs.** If there are new
commits, look at those first.
If there are no new commits and nothing to look at, **say briefly "nothing
to look at" and stop.** Do not promote a taste issue to a defect.

### Already confirmed fine (do not look again)

- `.gitignore` — `git check-ignore` confirmed 9 blocked · 4 passing
- Unrendered traces in build HTML — `<Video` `:::` `[object Object]` `{/*` 0 across all pages
- 3 license sources — confirmed CC0 / OFL / MIT key phrases
- `_downloads` ZIP sizes 6, `_asset_sources` file counts 6 — match the docs table
- Plan vs prose done criteria 9 — same items
- `build_title_forest.py` — ran twice, md5 identical (1,280 nodes)
- `title_menu.tscn` — node names and 3-layer canvas split are sound
- `known_issues.md` — contents accurate
- `index.tsx`, `custom.css` — links valid, every `mb-` class defined and used
- git blob vs working-file byte compare — all 85 match
- `MDXComponents.tsx` — 8 lines that only map `<Video />`, sound
- 8 license items in the manifest — all match `third-party.md`
- Reverse check of 22 fixes — 0 regressions
- Device tab behavior — beacon presentation sound after `title_menu.gd` edit, no script errors
