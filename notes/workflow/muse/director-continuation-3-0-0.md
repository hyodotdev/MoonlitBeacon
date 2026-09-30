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
| `20260930-1838-road-home-integration` | `008-road-home-integration.md` | Judged and accepted after collateral-only brief 013; commits be497a9 / 6a83f01 / b87fd23 / 08771ab preserve UI and combat, protect discoveries, separate Road geometry and explicitly bring Nari home |
| `20260930-1847-title-load-test-deadline` | `009-title-load-test-deadline.md`, then `009b-title-warm-cache.md` | Round 2 judged and accepted in 2920ba8; director normal/warm 30 pass, zero-deadline mutation fails 4 cases then restores 30 pass |
| `20260930-1924-deterministic-spatial-performance` | `011-deterministic-spatial-performance.md` | Judged and accepted in 9595752; fixed fixture visits 4/80, actual full-scan mutation fails 80/80, restoration and real density/node/tick budgets pass (18 cases) |
| `20260930-1951-skill-discovery-history` | `012-skill-discovery-history.md` | Judged and accepted in b252d6d; cumulative real NEW history across gates replaces random rediscovery requirement, 126 pass, disabling production unseen guarantee fails 14 cases then restores 126 pass |
| `20260930-1959-route-and-quit-captions` | `010-route-and-quit-captions.md`, then `010b-caption-player-clearance.md` | Round 2 judged and accepted in 7ecc8c2 / 0f6e617; director 71/248/951/50 pass, clearance mutation fails nine assertions then exact restoration passes; all 50 final rim/outcome/discovery/quit stages inspected in five languages |
| `20260930-1959-docs-true-to-3-0-0` | `003-docs-true-to-3-0-0.md` | Judged and accepted in 6c632a4 / 509e7f2; director source spot-checks plus docs build, anchors, assets and hygiene pass; historical course unchanged |
| `20260930-2007-continuation-refusal-classification` | `014-continuation-refusal-classification.md` | Judged and accepted in 5f1733b; director 39 runner tests pass, restoring quick-failure retry makes refusal negative fail, restored 39 pass; only the two reviewed runner paths explicitly allowed at accept |
| `20260930-2042-reconcile-renewal-records` | `007-reconcile-renewal-records.md`, then `007b-release-gates-and-dates.md` | Round 2 judged and accepted in bac5534 / c548085; all five descriptions inspected, director metadata 10/100 and 33 boundary cases pass, all 100 IAP rows byte-identical |
| `20260930-2113-final-build-record` | `015-final-build-record.md` | Judged and accepted in e8af6ce; full one-file report/diff checked against actual logs, independent hygiene passes, historical bot and capture boundaries preserved |
| `20260930-2128-chronicle-record-timing` | `016-chronicle-record-timing.md`, then 016b / 016c | Round 3 judged and accepted; one public-doc paragraph accurately separates event recording from deferred presentation. Director final docs build, anchors and hygiene pass; no game bytes changed |

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
- Title round 2 is accepted, test-only and 30 cases; director normal/warm repeats and deadline mutation completed as recorded above. Its separate full suite found an untouched live-clustering ratio flake. Two director root repeats independently passed then failed only spatial candidates <25%: passing 3798/18720 (91 ticks, 1129 nodes), failing 4672/18200 (90 ticks, 1130 nodes); all other 17 cases passed. This is a verified regression-check defect, not evidence of a production index bug. Brief 011 preserves damage/density/node/per-tick limits and requests a deterministic real-index selectivity check.

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

## Accepted narrative evidence and current review boundaries

- Director post-integration checks independently passed: place memories 951, layout 135, Depth 55, run choice 331,
  story structure 695 and scene staging 221. Disabling the actual discovery guard failed four same-frame/one-second
  fork and third-guardian preservation cases; restoring the exact production bytes returned 951 pass.
- All new story stages were generated in five languages. Personally inspected opening, both real-path discovery
  collision stages, official continue/cash-out choice and win/early-exit/defeat for each language, plus all six
  dim/lit terrain composites. Fast desktop rendering exposed frame-count-only capture before result fade finished;
  brief 010 requires an elapsed-time settle and final-alpha assertions. Do not call those fading images final cards.
- A twelve-run seed-11/two-loop diagnostic measured 61.05 simulated minutes, 0.753 hits/min, 46.47 scattered/min,
  26.08 percent mean weaving, peak 73 bullets, six guardian fights, zero stuck/soft lock. Arena's deferred-strip
  cleanup changed after this bot launched; combat did not. This is not the exact-final-source calibration or a
  human difficulty verdict; the frozen seed-5 measurement remains the comparison.
- An isolated-save desktop diagnostic observed The Promise act, kettle/road dialogue, actual first-beacon ribbon
  discovery, joystick movement and the road-home pause objective. Debug shield and beacon controls were used.
  No mobile install/play or full human eight-cycle ending is claimed. Ending/choice branches have separate tests.
- The root game registry after story/title/spatial/skill acceptance passed all 46 game checks plus two import steps; log
  `builds/verify/director-story-accepted-game.log`. Import, all 118 scripts and startup passed independently.
  Final full verification remains after the caption/docs/store-record rounds.
- Whole-branch state boundary Node checks passed 122 cases (analytics, Firestore index, capture run state,
  Android capture persistence and iOS device evidence). Read the shaders, ground bursts, guardian streams and
  all six room resources from disk against the already-inspected production art and terrain boards.
- Current runner continuation retried all failures under ninety seconds, including approval/classifier refusals.
  This confirmed branch defect is fixed by 014; a fake refusal that would succeed with its session removed now
  launches once, records failure and cannot be accepted. The old condition makes the independent negative fail.
- Echo ring repeats remain constrained by the documented hostile-projectile cap and can have a fuller warning
  picture than their actual repeat. Keep this known limitation visible; no evidence justifies uncapping the mobile
  budget. Marketing proofs remain stale; no recapture or store operation is authorized.

- Docs audit accepted after independent source checks of nine skill gates/timings, score constants, early/Depth
  curve, ejected recovery, terrain entry gates, warning floors, hidden defeat window, map guarantee, version locks,
  absence of a release-3.0.0 tag and asset inventory. Copy docs build/anchors/assets/hygiene passed. Actual inventory
  is 259 files excluding import/gitkeep, 75 third-party, 26,713,937 bytes. Director corrected only this stale count
  in AGENTS.md and the verify command; no game bytes or locked values changed in that guide correction.

- Director recounted guardian production PNG headers: 12 forms, 44 sheets, 200 cells. Corrected the old three-kind/50-frame denominator in the source visual evidence reference, synchronized the mirror, and passed `pnpm check:skills` before committing 61c1292.

- Caption round 1 is not accepted: the upper-rim real-camera caption at y=132..184 crosses the hero at x=404,
  obscuring its second line. Director inspected all four Korean rim renders and all five quit renders; Japanese
  fits. Korean all-story rendering completed, the next English render was intentionally stopped after this
  confirmed defect so its interrupted exit 137 is not a production failure or a green batch. Correction 010b
  requires real sprite clearance across all six heroes plus a quiet diagnostic (initial tutorial overlays the
  bottom stage; forced early placement is not natural-route proof).
- Store/record brief 007 now runs independently as `20260930-2042-reconcile-renewal-records`: excludes the build
  log owned by the pending caption correction. Brief 015 will finish only that log after caption acceptance.
  This avoids simultaneous authoring of a shared deliverable; no hand merge or forced patch is allowed.

- Caption correction 010b is accepted after director independent gate 71, staging 248, place memories 951 and
  fork travel 50 passed; disabling only actual hero clearance failed nine assertions and exact restoration
  passed 71 (SHA-256 14785feb443ed804629c32efb1b86c4f615e10e2f1c7360fdfbaebbfad6a40a0).
  Personally inspected all twenty rim captures, fifteen fully settled win/escape/defeat cards, ten discovery
  collisions and five quit cards across five locales at original resolution. These are diagnostic desktop
  stages; debug controls were visible on rim/discovery stages, not marketing images or device proof.
- Personally inspected all nine skill icons at four-times nearest scale and the fifty remaining UI renders
  (title/hero/four acts/two choices/dialogue/Chronicle in five locales). All twenty act renders were before
  their staggered fade completed; inspect settled cards separately before calling those final pictures.
  Other thirty new renders were readable without a confirmed clipping defect.

- Store/records 007 round 2 accepted after full five-description/release-note diff inspection, independent
  metadata check (10 app/100 IAP), thirty-three metadata/contact/graphics-boundary tests and hygiene passed.
  Director byte comparison preserved all 100 IAP rows (SHA-256
  d4332526d70d7d613550dae7be566504ce8863448f9ea14b2c1863b051c66f00); only five promotional fields
  changed in the CSV. Full descriptions count 2388/3695/1961/1494/1496 and Play notes 323/163/139/125/125.
  Only six intended paths changed; no game or marketing artwork changed. Correction removed device proof from
  code-merge steps and dated the last recorded store version/uncommitted planning snapshot.
- All twenty act cards personally inspected after a two-second diagnostic settle in the caption copy.
  Temporary shutter timing adjustment was restored byte-identically (SHA-256
  5828e01ed2d18dd2a16fe67444f2e0550c935e00080dbdbe58b9b1892563986b). The Promise/Lost/Road/Home
  headings, epigraphs and tap prompts are readable in all five locales. No production card change was needed.

- Final direct-distribution Android debug APK built successfully with `pnpm android:build` after caption
  acceptance. Godot startup and all 118 scripts passed export preflight. APK manifest reports the locked
  package, 3.0.0, versionCode 15 and arm64-v8a only; apksigner verify exits zero. ZIP/dex checks confirm
  no tests/tools, no BillingClient and no IAPKit publishable config. 109,169,625 bytes; SHA-256
  c765d96e1390330f15aed346dc157e79e9e7078a662ab5f6c51b156c8b9c21e6. No install or upload performed.
- Separate real-tree `pnpm check:store-screenshots` exits one: device capture proof file is missing.
  Existing marketing proofs cannot establish this changed game's captures. Reported only, no recapture or
  upload; the check's suggestion to capture is diagnostic text, not authorization.

- Build-log-only 015 accepted after full one-file diff/report inspection against the director's logs and
  source; independent copy hygiene passed. Removed unsupported bot-vs-human/floor and average-contrast
  certainty claims, retained historical values and real partial-batch boundaries, and recorded accepted
  story/caption work plus the still-uncompleted release/device gates. Final root commands are below.

## Final root verification and review

- `pnpm verify` completed with exit zero on e8af6ce, log `builds/verify/director-final-verify.log`.
  Summed TAP totals: 467 Node tests, 467 pass, zero fail. All fifty registered Godot steps executed:
  forty-eight game checks plus two imports. All 118 scripts compiled, five locales loaded, 557 keys checked
  (478 statically used), metadata 10 app / 100 IAP rows, 259 manifested assets, 174 custom asset contracts,
  generated-art/store-graphics determinism, mirrored skills, hygiene, docs build and anchors passed.
  Title-transition teardown prints eighteen ObjectDB leaks; source of these has not been established.
  The hero-direction harness also reports the engine's camera physics-interpolation override. Neither is
  hidden as a clean log or represented as a fixed defect; startup and export preflight pass.
- Final source/doc comparison found Chronicle prose still tied every record to display time. Place records
  happen at restoration and first-meet records can precede their strips; act story records can precede the
  dialogue while its card opens. The director sent two narrow corrections after the first answer. Round 3
  was accepted with simple event-time wording, only one paragraph in `apps/docs/docs/game.md` changed.
  Director `pnpm docs:build`, `pnpm check:docs`, `pnpm check:hygiene` all exit zero on the accepted root,
  log `builds/verify/director-final-doc-timing.log`. All game/art/tooling bytes remain identical to e8af6ce,
  so the full suite and APK evidence remain applicable; no unnecessary program-suite repeat is claimed.

| Final review | Angle and evidence | Finding / action |
| --- | --- | --- |
| A | Whole origin/main…HEAD inventory plus accepted root narrative, choices, persistence, gate/hero geometry, bullet field/emitter bounds, current regression sources and full-suite log. Recounted Chronicle 1 opening + 11 cycles + 6 places + 19 meets + 3 endings = 40; 182 tracked script UID files have zero duplicates. Accepted arena/gate/result bytes match the director-judged caption copy. Root final docs build/anchors/hygiene and diff whitespace checks pass. | None requiring another correction; first clean round after 016. Retain the explicit device/capture/performance boundaries and documented projectile cap. |
| B | Reverse-check public/store/release claims against actual source, final evidence and package. Re-read the full release plan, dated checklist snapshots, current PR body, cold/warm/refusal test sources, skill-history assertions, deterministic real-sweep performance fixture and CI exit/channel gates. Current metadata check passes 10/100; raw CSV comparison with bac5534's parent preserves all 100 IAP rows exactly (SHA-256 d4332526d70d7d613550dae7be566504ce8863448f9ea14b2c1863b051c66f00). Recomputed APK hash, reverified signature/manifest/arm64 and no test/tool/Billing/IAPKit config leakage. Whole branch whitespace check passes, main is an ancestor and changed-path inventory contains zero forbidden secret/export/source-pack paths. No claim of GitHub CI, device play or store publication before those operations. | None requiring another correction; second consecutive clean round, stop the development/review loop. Corrected the director record's earlier row-hash transcription and brief filename before publishing the evidence. No automatic recurring job was created, so there is no scheduler job to delete. |

The complete seen-list is accumulated above: game state/combat/persistence and failure paths; exhaustive production
sprite cells and selected in-game harness stages; all UI stages/locales and settled cards; room/corner views;
manual desktop diagnostic; test mutation sensitivity; generated assets and manifests; narrative/reference/store
copy; release snapshots and privacy/deployment boundaries; isolated runner and refusal handling; branch safety,
locked identity/version values and Android package contents. Physical-device all-direction cells remain empty.
Intentionally uncompleted: authorized device confirmation, marketing proof/capture, Echo-ring budget tradeoff,
unconfirmed title teardown cause, and separately authorized store/deploy/tag operations. These boundaries are
visible in the prepared PR body rather than being represented as completed work.
