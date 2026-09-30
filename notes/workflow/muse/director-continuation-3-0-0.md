# 3.0.0 continuation: director evidence and remaining work

The current user asks to continue `feat/3-0-0-ui-story`, use the ignored draft body in
`builds/release-notes/pr-3-0-0-draft-body.md`, improve the game by looking at it, repeat reviews until stable,
and create a merge-ready PR without merging. A later message explicitly asks for a more immersive world/story
and permits restructuring the game and all assets. The director writes briefs and operations; the implementer
writes deliverables. Nothing is pushed, merged, submitted or uploaded in this continuation so far.

## State at start

- HEAD `9e5411f`, current branch `feat/3-0-0-ui-story`, nine commits after the shared base.
- Only pre-existing untracked path: `.playwright-mcp/`; preserve and do not stage it.
- `git fetch origin` found ten main-side commits through `17761af` (PR #7, IAP 3.6.1 / Shop).
  Integrate main locally after accepting the existing bullet run, before the final narrative run and verification.
- No PR currently exists for the branch. PR creation was explicitly requested, merging was explicitly prohibited.
  The commit workflow separately requires push confirmation, and the PR guard requires the user's own allow file.
  Complete all local work and prepare exact commits/body before that final approval step; never create the allow file.
- Muse doctor passes. Old bullet runs `20260930-1022-bullet-weaving` and `20260930-1057-bullet-weaving`
  timed out; neither was accepted. Preserve the former as comparison, continue the latter.

## Runs started by the director

| Run | Brief | State / next action |
| --- | --- | --- |
| `20260930-1057-bullet-weaving` | `001b-wrap-up.md`, round 2 | Running confirmation batches; read final report, code/diff, reproduce tests and bot metrics, render barrages, mutation-check; accept only when judged |
| `20260930-1700-store-text-3-0-0` | `004-store-text-3-0-0.md` | Done; three changed paths including a fixture anchor in the existing store metadata test; director must read diff and reproduce 8 tests/metadata check. Reconcile narrative copy after brief 006 |
| `20260930-1701-release-record-3-0-0` | `005-release-record-3-0-0.md`, then `005b-release-record-accuracy.md` | Round 1 copied stale 28-entry/458-row claims. Round 2 corrects them, snapshot labels, committed Firestore wording and tagging authorization. Reconcile final verification/narrative after 006 |

Prepared `006-lantern-hollow-story.md`: named home Lantern Hollow / 등불마을, Nari / 나리 and a road-home promise;
six first-beacon place memories with crafted before/after motifs and Chronicle records; concrete official ending
and voluntary Depth motivation; hero relationships, actionable route clues, safe nonblocking discovery presentation,
five-language copy, persistence/integration/layout/budget tests and real screenshot harness. Run after the game
baseline is accepted and main is integrated. Brief 002 (Depth / Wave / shop wrapping) is still pending and should
follow or precede narrative without concurrent edits to the same game files. Brief 003 docs audit follows final game.
Do not recapture marketing screenshots; no current user instruction authorizes recapture or store operations.

## Director measurements and visual review

- `pnpm test:game` on the starting tree: exit 0, log `builds/verify/director-3-0-0-baseline-game.log`.
  41 registered checks; the two bullet tests were not registered yet.
- `pnpm check:hygiene`: six confirmed failures, only the banned parameter name in bullet emitter/field.
  The bullet implementation renames those parameters.
- Starting tree `shot_ui.tscn` all five languages / all 22 screens: rendered successfully, exit 0, 153.8 s.
  Outputs `builds/shots/ui/<locale>/`. They are debug harnesses, not store screenshots.
- `shot_rooms.tscn -- director-baseline`: exit 0; all six composites inspected at original resolution.
  Places are distinct and readable. The room harness does not configure its player; absence there is a harness artifact.
- `shot_actors.tscn -- director-baseline all`: exit 0; game composite, heroes and spirits inspected.
- `shot_expedition.tscn -- director-baseline`: exit 0; fork, omen, boss inspected. Debug widgets and stale sample HUD
  values in that harness are not proof of production defects. A gate's title can touch the HUD in this staging;
  brief 006 requires retaining readable actionable route clues.
- Diagnostic production-PNG sheets in `builds/art-review/director-3-0-0/`: all **192 hero cells** (6 × 2 states ×
  4 directions × 4 frames) and **112 spirit cells** (7 × 4 × 4) inspected at 4× nearest. Hero silhouettes stable,
  direction/props readable; spirits often use a round front-facing presentation. These are asset evidence, not
  a physical-device matrix. Guardians' full source sheets still need a current count and review.
- UI contact sheets were generated but not all inspected. Already inspected individually: ko title, hero, shop,
  HUD and Chronicle. Shop wrapping is awkward and is in brief 002; other language clipping was in the earlier draft.
- A real windowed bot run `director-before-story`, one Warden, seed 21, speed 1, shots=1, loops=1 was started;
  inspect its result/screens when finished. No claim of human manual play.
- CUA selected a separately launched Godot Project Manager instead of the CLI game. That extra manager was quit
  through CUA. Use harness images unless a real game app is identifiable; do not claim CUA controlled the game.

## Device choice pending

An asynchronous question asks whether to install/play on the dedicated Pixel_10 emulator, connected test Pixel,
or use desktop only. No response has arrived as of this note. Do not treat elapsed time or a preselected option as
permission to install on a device. Continue independent desktop/source/test work.

## Finish sequence

Judge and accept bullet work; integrate current main locally; implement and judge narrative and UI polish;
audit README/reference docs and reconcile release/store text; run full `pnpm verify` on the real final tree;
run `pnpm check:store-screenshots` separately and report failures without recapture; Android build and authorized
device validation; review the full origin/main…HEAD range from two different angles until two consecutive clean
rounds; commit coherently with Angular messages and the `Implemented-by:` line from `pnpm muse who --line`;
prepare an accurate non-draft PR body with later store release gates separated from merge requirements;
request only the required final push/PR-guard authorization after that concrete result exists; create/attach PR,
apply verified labels and watch CI to merge readiness. Never merge.
