# 3.0.0 continuation: director evidence and remaining work

The current user asks to continue `feat/3-0-0-ui-story`, use the ignored draft body in
`builds/release-notes/pr-3-0-0-draft-body.md`, improve the game by looking at it, repeat reviews until stable,
and create a merge-ready PR without merging. A later message explicitly asks for a more immersive world/story
and permits restructuring the game and all assets. The director writes briefs and operations; the implementer
writes deliverables. No PR has been merged, and nothing has been pushed, submitted or uploaded in this continuation.
Current main was integrated into the local feature branch in `2cda1b3`; this does not merge the feature PR.

## State at start

- HEAD `9e5411f`, current branch `feat/3-0-0-ui-story`, nine commits after the shared base.
- Only pre-existing untracked path: `.playwright-mcp/`; preserve and do not stage it.
- `git fetch origin` found ten main-side commits through `17761af` (PR #7, IAP 3.6.1 / Shop).
  Integrated locally without conflicts in `2cda1b3`, before final narrative and verification.
- No PR currently exists for the branch. PR creation was explicitly requested, merging was explicitly prohibited.
  The commit workflow separately requires push confirmation, and the PR guard requires the user's own allow file.
  Complete all local work and prepare exact commits/body before that final approval step; never create the allow file.
- Muse doctor passes. Old bullet runs `20260930-1022-bullet-weaving` and `20260930-1057-bullet-weaving`
  timed out; neither was accepted. Preserve the former as comparison, continue the latter.

## Runs started by the director

| Run | Brief | State / next action |
| --- | --- | --- |
| `20260930-1057-bullet-weaving` | `001b-wrap-up.md`, then `001c-gauntlet-one-fight.md` | Judged and accepted in c0f17aa / 05b71a6 / 8a3abad. Director rate-cap and mode mutations fail, restoration passes; corrected real gauntlet loops=2 settles all four after one fight |
| `20260930-1700-store-text-3-0-0` | `004-store-text-3-0-0.md` | Judged, accepted, locally committed `a85ad8a`; three changed paths including a fixture anchor. Director reproduced metadata (10 app / 100 IAP rows) and 8 tests on both copy and root. Reconcile narrative copy after brief 006 |
| `20260930-1701-release-record-3-0-0` | `005-release-record-3-0-0.md`, then `005b-release-record-accuracy.md` | Round 2 corrected stale counts, snapshot labels, committed Firestore wording and tagging authorization. Judged, accepted, locally committed `c1443a8`. Reconcile final verification/narrative after 006 |
| `20260930-1728-result-depth-and-wording` | `002-result-depth-and-wording.md` | Judged and accepted. Local commits `efcf6e7`, `83bed89`, `07d3155`; director full game suite/locale passed, Depth guard mutation failed 10 cases then restored 55 pass, layout 135 pass, all twenty four-screen/five-language renders inspected |
| `20260930-1740-lantern-hollow-story` | `006-lantern-hollow-story.md` | Round 1 done but not accepted: real-path discovery overwrite and result score/Road overlap confirmed, and Nari ending needs explicit resolution. Stale patch after UI polish requires fresh integration, brief 008 |
| `20260930-1838-road-home-integration` | `008-road-home-integration.md` | Fresh integration running; preserves accepted UI and frozen combat while correcting discovery priority, Road geometry and explicit Nari resolution |
| `20260930-1847-title-load-test-deadline` | `009-title-load-test-deadline.md`, then `009b-title-warm-cache.md` | Round 1 fixes frame-spin deadline but new IN_PROGRESS-only assertion fails on a genuine warmed arena; round 2 corrects that confirmed false failure |

Brief `006-lantern-hollow-story.md`: named home Lantern Hollow / 등불마을, Nari / 나리 and a road-home promise;
six first-beacon place memories with crafted before/after motifs and Chronicle records; concrete official ending
and voluntary Depth motivation; hero relationships, actionable route clues, safe nonblocking discovery presentation,
five-language copy, persistence/integration/layout/budget tests and real screenshot harness. Story and UI use
isolated implementer copies; inspect and reconcile their shared CSV/result/doc/test-registration hunks when
accepting. Do not hand-resolve implementer deliverables if a patch no longer applies: use a fresh integration brief.
Fresh run `20260930-1838-road-home-integration` implements brief 008 on the UI+bullet baseline, using the mechanical reference patch in `notes/workflow/muse/inputs/story-006.patch`. Remove the temporary root input after the copy is established; do not commit it. Brief 003 docs audit and 007 store/record reconciliation follow the final accepted game, with disjoint deliverables.
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
  a physical-device matrix. All 12 guardian forms / 200 cells were then reviewed at 4× nearest (front-locked,
  no four-direction claim), and all 13 cells in the four custom pickup/projectile/slash PNGs were reviewed at 4×.
- UI contact sheets were generated but not all inspected. Already inspected individually: ko title, hero, shop,
  HUD and Chronicle. Shop wrapping is awkward and is in brief 002; other language clipping was in the earlier draft.
- A real windowed bot run `director-before-story`, one Warden, seed 21, speed 1, shots=1, loops=1 finished:
  exit 0, 132.1 simulated seconds, 21 kills, 4 hits, peak 34 bullets, 25% weaving, no soft lock. The first
  weaver-hit screen was inspected; no claim of human manual play or stable performance while other runs were active.
- After main integration, the director's full `pnpm test:game`, `check:assets` and `check:skills` passed.
- Bullet copy: director full game tests, isolated startup and all 115 script compilation passed. Hygiene found a
  new banned-word reference in the build log (line 331); the final implementer output removed it and FILL slots,
  and the director's repeated hygiene check passed.
  All eight barrage stages were rendered and visually inspected. Director repeat natural/gauntlet batches started
  with unique `director_nat` / `director_gaunt` tags; accept only after evaluating their outputs.
- Director natural confirmation: 12 runs, 46.89 simulated minutes, 1.173 hits/min, 23.12 scattered/min,
  33.08% mean weaving, bullet peak 52, no pickup stuck or soft lock. These satisfy the frozen brief's bands;
  guardian confirmation remains separate. No claim that a bot supplies a human difficulty or fun verdict.
- The first guardian repeat had omitted `loops=1`, so the harness sometimes continued exploring after its fight.
  Run 10 won its frost fight, then reached the bot's 2400-second cap. The director stopped that partial batch;
  it is not a green 18-run batch or proof of a production soft lock. Brief 001c corrects the documented gauntlet
  mode to one fight, while preserving natural mode and frozen balance.
- Explicit one-fight repeat `director_gaunt_one`: 18 runs / 18 fights, 16 won (88.9%), mean 1.17 hits/fight,
  bullet peak 62, zero stuck or soft lock. Cycles 2/6/12 and six places are paired cyclically, not a full
  Cartesian matrix. The machine recorded 98 setup spikes, all before 3.4 seconds, and none after that boundary.
- Correct scene invocation of the late-game performance check passed 18 cases: Lv20/Lv40 node peaks 1073/1129,
  frame p95 22.7/23.9 ms in this desktop headless run. An earlier `--script` invocation of this Node-based test
  was a director command error, timed out and is not a game defect.
- All thirty map corner/center views (five per terrain, seed 20260929) were inspected at original resolution.
  No seam, edge band or missing terrain layer was confirmed. These are still harness views, not movement/device proof.
- CUA selected a separately launched Godot Project Manager instead of the CLI game. That extra manager was quit
  through CUA. Use harness images unless a real game app is identifiable; do not claim CUA controlled the game.

- Story round 1: director full game suite and 533 place cases passed; all 90 diagnostic renders generated. Six terrain before/after boards, fourteen motif cells, five ending boards and five fork/Chronicle boards inspected. Real-path probe then failed 2/536: first fork and classic third beacon overwrite discovery. Road rectangle probe failed 1/535 with a 6.5 px score overlap. Temporary probes restored byte-identically. Brief 008 resolves these and gives Nari an explicit official ending.
- Manual desktop diagnostic now selected the actual Moonlit Beacon DEBUG window through CUA. Title tap, act card, dialogue skip, joystick drag, auto-attack, relic choice, defeat and completed score animation were observed. This was the pre-story root with disposable isolated saves, not a human difficulty or device verdict. Closing produced 16 leaked objects; a later title-transition check passed but leaked 17. The earlier root game suite failed at the worker-load completion check under concurrent live play; sequential verification/verbose diagnosis is pending.
- Sequential title repeat passed 11 cases; verbose teardown showed 17 RefCounted objects with zero references. Consuming the request alone did not eliminate them, so no guessed audio or production leak fix is authorized by the evidence. Round 009's 22-case test passed normally, but a director runtime warm-cache diagnostic failed only the new first-status assertion (expected IN_PROGRESS, observed LOADED). Correction 009b preserves final completion and all eleven original assertions.
- All forty baseline settings/relic/shrine/consent/ladder/pause/quit/credits stages in five languages were inspected on ten boards. Japanese quit title measures 266 px at the production font size 26 against a 260 px panel; other four are 196/177/181/181 px. Brief 010 fixes the title fitting.
- A production fork gate at the valid top candidate (950,124), with player (950,220), projects its label to y=-64..-12 while the visible gate suppresses its compass. Director diagnostic image and geometry agree; this is forced valid placement, not a natural route capture. Brief 010 will check all four edges after story acceptance. Temporary probe files were removed exactly from the old story copy.
- Fresh fetch still points main at 17761af; no PR exists for the feature head. Existing appropriate labels were read. No push or PR creation occurred.

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
