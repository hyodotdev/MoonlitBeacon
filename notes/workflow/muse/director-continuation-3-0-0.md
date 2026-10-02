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

## New player feedback: kinetic combat and audio

- After the reviewed build was opened for desktop play, the user requested faster traversal and combat,
  six distinctly feeling weapon kits, clearer beacon choices, energetic survival-game sound/music and
  changed gameplay screenshots. This continues the renewal and PR objective; no merge is authorized.
  The earlier final verification/review applies to the preceding baseline only, not this new implementation.
- Brief 017 chooses sword / twin blades / rifle / lantern shotgun / heavy cannon / orbiting scythe,
  roughly 17% faster common traversal and dash recovery, separate weapon mechanics from legacy cosmetic
  profiles, original deterministic combat audio and bounded scene-local playback. The full story, free
  cycle-eight ending, ownership/save identities and all locked engine/package/control values remain required.
- Fresh director baseline hero-profile check: 840 pass, exit zero, 9.1 s;
  `builds/verify/director-weapon-baseline.log`. This is baseline evidence only.
- Implementer started successfully: `20260930-2321-kinetic-hero-weapons-and-audio`, round 1.
  Director launch log: `builds/verify/director-kinetic-muse.log`. Judgment, own checks, mutation sensitivity,
  actual weapon screenshots/motion/audio inspection, real-tree verification and two fresh review rounds
  are pending. The user's running game window is preserved while the isolated copy is developed.
- Diagnostic desktop capture is explicitly requested. Store screenshot recapture/upload and device
  installation are outside this work. Publishing still needs the required immediate human push confirmation
  and the human-created PR guard file; neither has been received.
- Director's initial independent PCM inspection of the first audio draft measured full-scale loop
  boundary steps 0.166870 (arena) / 0.220184 (guardian), despite the proposed tail-to-head blend.
  These are work-in-progress findings, not accepted output. The implementer's own subsequent loop
  probe also failed during round 1; remeasure the eventual loop endpoints and waveform before acceptance.
- The round-1 loop generator was revised to short raised-cosine fades at both edges. Director remeasurement
  now finds exact zero boundary steps in both WAVs, peak 0.619965, lengths 14.545 / 17.143 seconds.
  Preview emission was attempted, but the available model interface reports unsupported audio input;
  no personal listening verdict is claimed. Actual event wiring/mix and final files still need review.
- Follow-up targets from the unfinished arena draft: the kill event follows `_gain_progress`, while both
  level and kill cues replace `RewardSfx.stream`; confirm earned growth cannot be cut by the next kill.
  Confirm ducking is reachable when modal panels pause the inherited arena and covers audible music,
  not only already-paused effect players. Measure real six-kit single/group output and late cannon
  splash candidate work rather than accepting the table's prospective balance/budget claims.
- Native audio semantics independently checked against Godot's official `AudioStreamPlayer` reference:
  assigning `stream` stops current playbacks; inherited node pause also pauses playback. Thus the actual
  growth-then-kill callback ordering matters even with `max_polyphony=2`; automatic modal pause itself
  must not be misreported as an audible ducking failure. Examine the unpaused `VoicePanel` separately.
  Source: https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer.html
- Another unfinished-draft boundary to recheck: `_missile_volley()` now respects the hero base lane count,
  but `guided_lane_damages()` still returns the old core-only count, and `MoonMissile.launch_volley()`
  falls back to repeating `damage` for missing lanes. Keeper's five-lane base can duplicate total damage
  when early Starfall evolution / core-three awakening guides only three budgeted lanes. Require
  actual six-hero guided growth coverage and monotonic effective damage, not only legacy resource tests.
- The imported-music draft also needs correction unless changed before report: `.wav.import` uses
  `compress/mode=2` (QOA), while `_loop_bgm` computes sample endpoint as `wav.data.size()/2`.
  Director read the actual RSRC imports' QOA headers: decoded frame counts 320727 / 378000 at 22050 Hz,
  so byte count divided by two is not the intended 14.545 / 17.143 s endpoint. Check actual imported
  `AudioStreamWAV` loop bounds/format/decoded sample count, not only uncompressed source WAV endpoints.
  Official reference: https://docs.godotengine.org/en/stable/classes/class_audiostreamwav.html
- The implementer independently noticed the 30 Hz comparison mismatch and repaired the draft fixture
  before the prepared correction was sent. Director then ran both new suites itself in isolated saves:
  182 weapon cases pass in 74.6 s, and 88 audio cases pass in 6.5 s (only the known fixture camera override).
  Copy logs: `builds/director-hero-weapons-r1.log`, `builds/director-combat-audio-r1.log`.
  Same-target six-second totals: Warden 132, Dancer 100, Keeper 102, Knight 102, Eclipse 102, Sage 100.
  Grouped four-second totals: 9 / 6 / 36 / 128 / 9 / 240 in that same hero order. These are controlled
  no-opening fixtures, not the user's play, natural runs, a final balance verdict or physical-device proof.
- Reading the entire new audio test found `loop_end > 1000` labeled as whole-sample proof, separate
  `_gain_progress`/kill calls and a manually visible panel standing in for real modal/voice-strip timing.
  Thus its 88 passes do not refute the current loop endpoint and earned-reward ordering defects.
  Brief 018 is prepared but not dispatched; omit the already-repaired clock item after final source check.

### Kinetic draft: actual display and sound evidence (2026-10-01)

- Independently ran `shot_weapons` windowed through `godot:isolated`, Dummy audio, six early heroes:
  exit 0, 28 observations, 24 live hero PNGs plus ten beacon PNGs; log in the copy at
  `builds/director-weapons-preview.log`. Root contact boards are
  `builds/art-review/director-3-0-0/kinetic/six-hero-preview.png` and `held-weapons-closeup.png`.
  Both were actually inspected. This is draft diagnostic evidence, not marketing/device capture.
- Display finding: the -20 held-weapon anchor crosses faces; rifle/shotgun/cannon look like blue
  face stripes. Captures retain the bottom debug toolbar, movement onboarding banner and temporary
  voice. Correction 018 now includes credible hand silhouettes, clean staging and live primary proof.
- Reproduced the generator audition operation: `builds/audio/director-kinetic/audition.wav`, 37.1s,
  13 cues; music peaks 0.620, effect peaks 0.800/reward 0.720. The UI opening is queued. Audio input
  is unsupported here, so no personal listening claim is made. Native playback/mix still needs checks.
- Original user game session 17860 has exited 0; its pre-existing 18-instance teardown warning was
  printed. No director input or termination occurred. A fresh accepted build can be opened afterward.
- Initial implementer natural smoke is not a six-hero success: Warden/Dancer/Eclipse died; Dancer
  made only three kills, Sage recorded one stuck interval. The initial paired gauntlet has five wins
  and one Dancer death. The implementer is investigating bot engagement and rerunning; preserve both
  raw reports and distinguish policy changes from production balance. Do not convert these into a
  no-stuck or all-win claim.

### User audio approval and additional steering (2026-10-01)

The user listened to the 37.1s audition and said the music passed. They requested faster, more exciting
guardian music and random rotation among three tracks per type. Correction brief 018 now includes
three arena plus three guardian tracks, the approved motif retained, distinct deterministic arrangements,
no immediate repeats and real imported-resource/transition coverage. This is authorized additional work
inside the same combat/audio task, not permission to push, install, upload or merge. Round 1 is still
running its baseline comparison, so 018 has not been dispatched concurrently.

### Own original full game runner on the draft

The director ran the original `pnpm test:game` in the kinetic copy (session 55073, exit 1). Unlike
the implementer sandbox, reimport completed. The suite stopped at `test_shrine_portraits` with 31/588
failures: both production preview capture literals and test literals retain the old Keeper description.
Log: copy `builds/director-full-game-r1.log`. Correction 018 explicitly requires reconciling those
independent five-locale literals with the new copy, preserving the render/readiness contract. This is
a confirmed draft failure, not a full verification pass. The new music-rotation work and all other
018 defects remain unaccepted.

### Round 1 judged; correction 018 started

Round 1 completed at 2026-09-30T16:41:09Z, 42 added + 16 modified paths; no protected paths.
The director read the final source/hunks, scene/import metadata and report. New deliberate adjustments
are Warden's quiet ranged cooldown 1.15 (for the existing late-game stage), terrain stat expectations,
and independent Keeper preview/test copy literals. These do not resolve the confirmed QOA loop endpoint,
growth/kill cue ordering, guided lane cloning, internal-pixel beacon copy or face-covering rig findings.
The report additionally overstates clean screenshots and misdescribes existing evolved missile splash.

Started round 2 with brief 018 via the required continuation command (session 69490), log
`builds/verify/director-kinetic-correction.log`. It includes the user's approved musical direction and
three tracks per arena/guardian pool, plus the bundled runtime, readable-kit and real-capture corrections.
Actual preview boards were copied into the implementer copy as ignored build artifacts for inspection.
No implementation was accepted into the real tree. The director will perform full original verification
when the new source is stable; the implementer was told not to evade sandbox import restrictions.

### Round 2 in progress: independent actual audio probes

- Six source WAVs are now present and distinct. The approved arena and guardian assets remain
  byte-identical to the user's audition (SHA-256 `0ed62a6709a800b0dd2f3d965ffa0a926e54cca48e036cc2c65cc2e52b55bbc4`
  and `1a87daf965241ef81aecdf0445b6b9ad030767cc23af42901550f7f47f441e12`). All six endpoints are exact zero;
  source peaks are 0.619965. This is source inspection, not a final native playback verdict.
- Actual `Arena._process(1/30)` with Knight and a close durable target drove both clocks: one melee hit
  and one cannon projectile, but `WeaponSfx` retained `weapon_sword.wav` at -15 dB. The sidearm armed
  the shared 70 ms gate before the primary cue. Probe exit 1, copy `builds/director-primary-audio-probe.log`.
  Existing audio wiring checks wait 0.1 s between calls and miss this. Draft brief 019 is prepared;
  do not dispatch concurrently, and drop this finding if final round 2 already repairs it.
- Captured the real master-bus mix with `AudioEffectRecord`, Music/Sfx setting 5 (actual maximum),
  BGM plus rapid bounded primary/impact/kill/growth calls and a guardian music switch: 6.5016 s,
  stereo 44100 Hz, peak 0.741302 (-2.6001 dBFS), zero clipped samples. Probe exit 0, only the known
  Camera2D fixture warning, copy `builds/director-mix-probe.log` and `director-max-mix.wav`.
  This is a deliberate overlap stress measurement, not a natural playthrough or subjective listening.
  Recheck after final corrections. No source was patched by the director; these are ignored operations.
- Read every imported QOA resource and played all six for six seconds. Actual loop endpoints equal
  source decoded sample counts exactly (320727, 336000, 306782, 378000, 278526, 330750), not compressed
  bytes. Positions advanced beyond four seconds; guardian playback at the 1.18 cap advanced to
  6.577–6.687 s. Corrected probe exit 0, `builds/director-whole-music-probe-r2.log`.
  Initial operational probe used an unnecessarily tight >5.5s clock threshold and one dummy-driver
  observation was 5.486s; all imported endpoints were already correct. Retain its failed log rather
  than misreport it as a production loop failure. The >4s bound still disproves the old 2.94/3.47s loops.
- Ran the generator's audition operation again: root `builds/audio/director-kinetic/audition-six-tracks.wav`,
  94.5s, six music tracks plus eleven effects. Source montage is unaccelerated; arena runtime adds
  guardian tempo and cycle escalation. Shared the file with the user; opening in Codex returned queued.
  No personal listening or accepted-production claim is made.
- Independently exercised 3000 draws per pool: exactly 1000 per track, every three-draw tour includes
  all three, no adjacent repeat across bag boundaries, and the gameplay-global RNG sentinel stayed
  unchanged. Corrected operational probe exit 0, `builds/director-music-bags-probe-r2.log`.
  Initial probe had a GDScript cast-precedence error and did not execute; its log is not pass evidence.
- Reading all BGM selection call sites finds rotation only on run/region/encounter/return, with one
  short track looping indefinitely within a mode. Draft 019 now also completes the user's requested
  three-track alternation at whole-track endings during a continuous terrain/fight; retain the approved
  event switches and no-repeat bag. This is a musical completion refinement within the user's request,
  not a speculative runtime defect or a request for a new dependency. Still do not dispatch concurrently.
- Independently ran the revised capture harness windowed for the three ranged heroes, natural early
  builds, four firing directions: exit 0, 72 observations, 48 PNGs plus ten beacon PNGs, copy
  `builds/director-r2-guns.log`. Actually inspected the 4× closeup board at root
  `builds/art-review/director-3-0-0/kinetic/r2-guns-four-directions.png` and copied it into the work copy.
  Horizontal faces now clear and gun silhouettes differ. The up-shot rifle still crosses the Sage face;
  gun flashes are at hand height while actual projectiles retain the -20 candle origin. All bodies in
  this board face front: these are four firing directions, not four body facings. Draft 019 records
  these concrete remaining presentation contracts, subject to dropping anything final round 2 fixes.
  This remains unaccepted diagnostic capture, not marketing or physical-device proof.
- Expanded the actual master-bus overlap probe to include the existing pickup (four voices), confirm
  and beacon SFX in addition to all new combat voices and arena→guardian music. At Music/Sfx step 5:
  stereo 44100 Hz, 6.5016 s, peak 0.891602 (-0.9966 dBFS), zero clipped samples, exit 0; only known
  Camera2D fixture warning. Copy `builds/director-full-mix-probe.log` / `director-max-full-mix.wav`.
  Beacon audio retains its actual 2D attenuation; this is a bounded overlap stress pattern, not a
  universal no-clipping theorem or subjective listening verdict. Final production remains unaccepted.
- Started the actual overcharge cue, then awaited production `_release_audio()`: `GrowthSfx` still
  playing with a non-null stream. Probe exit 1 (`builds/director-growth-release-probe.log`); manual
  operational cleanup released it afterward. The new growth voice is absent from explicit scene-swap
  release. Draft 019 adds this confirmed omission and requires active-cue/all-player release assertions.
  Recheck final round 2 before dispatching; no production edit made by the director.
- Read the actual round-2 bot JSONs (not `loops` request limits): `round2natural.json` has six runs,
  no stuck intervals, only Keeper and Sage completed one loop; Warden/Dancer/Knight/Eclipse died.
  Kills 91/12/676/127/93/357; simulated seconds 178.7/499.1/440.0/174.5/153.6/286.2.
  Dancer's low-level camp guardian lasted 310.5s before defeat, so this does not establish fun or
  human fight pacing. No policy change or production-tuning claim is inferred from these RNG cohorts.
- `round2gauntlet6.json` pairs six heroes with guardian forms at cycles 2/6: five wins, Dancer field-storm
  defeat; no stuck intervals. Fight seconds 23.5/36.4/28.3/43.4/21.8/42.3, hits 0/2/0/2/0/1,
  hostile-bullet peaks 20/51/20/76/18/66. Host-scheduler timings are logged, not mobile FPS evidence.
  Final source remains in progress; require fresh independent smoke after remaining corrections.
- Independently reran round-2 shrine portraits through the isolated wrapper: exit 1, eight of 618
  checks fail, four safe margins in English and Japanese (`builds/director-shrine-r2.log` in copy).
  The implementer's fresh-import original-HEAD comparison reports zero margin failures, unlike its
  earlier stale-translation baseline claim. This is the new description regression and belongs in
  this deliverable. Draft 019 requests concise accurate copy with preserved layout/readiness assertions,
  not waiving the failures as unrelated work. None of this tag has been accepted into the real tree.
- Draft 019 also records two remaining explicit acceptance gaps: the new arena tests/capture harness
  lack their own pre-save isolation guard, and the new single-shell forty-element fixture does not
  measure actual repeated late-game Knight sweep/cache/detonation work. Existing average aggregate
  256-visits/tick and 1200-node budgets must be measured without inventing a peak-time failure.
- Independent copy `pnpm check:assets` exits zero (`builds/director-assets-r2.log`), including all
  seventeen deterministic combat audio files. This does not waive the unfinished runtime/display
  corrections. Whole-track musical rotation must follow audio playback rather than accelerated
  gameplay countdowns; draft 019 includes the existing smoke tool's time-scale-three boundary.
- Round 2 completed, exit zero, 2026-09-30T16:46:43Z–19:03:32Z, 50 added/23 modified paths.
  Report explicitly retains eight shrine failures, pending untouched-area full sweep, actual display
  and device limitations. Its later 19:55 completion claim is not an observed timestamp. Full diff
  snapshot saved to copy `builds/director-final-hunks-r2.txt`; watched package change only adds audio
  determinism to check:assets, two new tests registered. No protected path or production acceptance.
- Repeated actual simultaneous-Knight and active-growth-release operational probes on completed
  round 2, both exit one with the same defects (`builds/director-*-probe-final-r2.log`). All other 019
  source/display/copy/performance/isolation gaps remain, so finalized the correction brief and started
  required `pnpm muse run …019-primary-audio-priority.md --continue …` successfully. Round 3 is running,
  shell session 48706, root log `builds/verify/director-kinetic-final-correction.log`. No alternate launch,
  production hand edit, push/PR/device/store operation. Keep waiting through judged acceptance.
- Personally opened the round-2 Korean beacon PNG. It is an early opening-animation frame: the
  choice panel still translucent. Source `RunChoicePanel._open()` fades for 0.18s, whereas the tool
  waits two process frames then a draw. This is not evidence of a broken eventual player modal.
  Final user-facing diagnostic beacon captures must wait for complete opacity/arming before draw;
  do not present these earlier PNGs as the fully settled modal or marketing/device evidence.
- Recounted the copy assets independently: 276 files (excluding .import/.gitkeep), 30,771,043 bytes.
  The earlier guide/verification-command 259/26.5MB counts must be refreshed after acceptance;
  original source packs and signing data remain outside tracked assets.
- Round-3 audio correction is independently exercised while the other fixes are still running:
  actual simultaneous Knight now hears cannon at -9 dB (one melee hit + one real projectile),
  and an active overcharge GrowthSfx explicitly stops/clears after `_release_audio()`. Both probes
  exit zero (`builds/director-primary-audio-r3.log`, `director-growth-release-r3.log` in copy).
- Extended actual max-step-five master mix to include the new separate sidearm voice simultaneously
  with primary, impacts, kills, growth, pickup bursts, confirms and beacon cues. Exit zero, stereo
  44100 Hz, 6.4087s, peak 0.901978 (-0.8961 dBFS), zero clipped samples
  (`builds/director-full-mix-r3-probe.log` / `director-max-full-mix-r3.wav`). This remains a bounded
  overlap fixture, not a universal no-clipping theorem. Known fixture Camera2D warning retained.
- Actual playlist boundary operation independently passes arena/guardian at time scales 1 and 3:
  complete phrases survive six audible seconds, two-second pause holds position/track, next track
  comes from the same pool after the complete phrase, and release clears playback/stream. Exit zero
  in 76.1s (`builds/director-playlist-boundary-r3.log`). Observed arena kinetic→ember and guardian
  assault→storm, guardian pitch 1.10. Four cases measured; not a claim that every random song was
  played in this particular probe. Repeat if the final audio lifecycle changes.
- Independent windowed beacon capture waited for the natural charge to open the actual choice,
  then staged five locales × core-available/max with real beacon context, completed fade and armed
  buttons before `frame_post_draw`. Ten PNGs, exit zero in 6.4s, opacity at least 0.99957 and all
  armed=true (`builds/director-settled-beacon-capture.log` in copy). Personally viewed all ten in the
  root board `builds/art-review/director-3-0-0/kinetic/beacon-five-locales-settled.png` and full Korean
  core PNG, shared in conversation. Copy is readable, contained, correct risk/reward/max-core change;
  terrain and defense ring are actual arena output. These are staged isolated desktop diagnostics,
  not a physical-device or marketing proof, and the main tree still awaits complete acceptance.
- Rechecked English IAP rows using the actual en-US locale: existing descriptions refer to the
  retained hero color/effect styles and balanced sidegrades, with no now-invalid flat damage
  percentage claim. Leave all 100 raw IAP rows unchanged as required. `rebuild.md` movement/interval
  values are explicitly the historical 2.0 rebuild, so no speculative rewrite of that history.
- Independently reran completed round-3 shrine margins: isolated production scene,
  exit zero, 648 checks in 6.0s (`builds/director-shrine-r3.log` in copy). This repairs
  the actual EN/JA regression; no margin/readiness assertions were waived.
- Independently measured real late-game Knight in round 3: 34/40 spirit caps,
  eight shells at Lv40, 16 detonations, sweep/cache total 1200 visits /90 physics
  steps (13.33 vs the 256 average budget), node_peak 1202; original sample 1141.
  `builds/director-late-performance-r3.log`, exit zero, 67 checks in 29.0s. Source
  removed the Knight node cap assertion and explicitly reports 1202–1203 instead.
  This does not satisfy brief 017's unchanged 1200 budget. Draft 020 requests a
  minimal measured overhead fix and restored assertion without reducing enemies,
  shell damage/lanes or changing the real non-evolved max-power sample.
- Normal windowed round-3 three-gun harness passes 112 checks /48 hero PNGs plus
  ten beacon PNGs (`builds/director-r3-guns.log`), and genuinely uses four bodies.
  Some up-labelled strips aim down at other enemies. Body-facing coverage is not
  actual firing-direction coverage; the header still claims both. Draft 020
  requests explicit controlled-target staging and actual primary-aim assertions,
  retaining production attacks. It also repairs the already observed fade-frame
  capture by waiting for choice opacity/arming, without changing the player modal.
- A separate controlled operational live-spirit run suppresses only its own fixture
  spawns and freezes targets, retaining natural openings and production shots.
  Recorded actual true-UP aims Keeper (-0.121,-0.993), Knight (-0.076,-0.997),
  Sage (-0.070,-0.998), with targets at (0,-90)/(0,-140)/(0,-150); exit zero,
  37 checks in 13.3s (`builds/director-r3-aim-observe.log`). Personally viewed
  full-size UP PNGs and verified side-hand placement; round-3 vertical gun code
  is corrected. Do not redesign targeting to repair the harness's coverage.
- Started the original shipped `pnpm test:game` in the copy outside implementer
  sandbox (`builds/director-original-full-game-r3.log`, session 34001), including
  fresh imports, not a replica runner or a partial-sweep pass claim. It is still
  running. Draft 020 has not been dispatched while round 3 remains active.
- Round 3 completed successfully at 2026-09-30T20:47:29Z (started 19:05:42Z),
  50 added/24 modified paths, no protected paths. Its ~20:50 completion estimate
  is not an observed finish time. No part of this tag is accepted yet.
- Original shipped full runner exits one at missile combat-loop: 12/153 failures,
  all old candle-origin assertions on straight/guided shots. Source creates Arena
  without pinning an equipped hero and assumes a shared candle for every profile;
  the standalone fixture passed 141, which did not establish the sequential path.
  Earlier registered hero-weapons passes 327 with actual same-target totals
  135/100/102/102/102/100 and grouped 4s totals 9/6/36/176/9/180 (host/fixture
  scheduling and new muzzle geometry; do not retain 240 as a current universal
  Sage-output claim). Full runner stopped at its first failure as designed.
- Finalized 020 with the fresh original-runner counterexample: preserve all
  straight/guided spawn/direction/inner-lane checks, distinguish gun muzzle from
  the retained melee candle and cover all six profiles. Successfully started
  the required continued run, round 4, session 54087, root log
  `builds/verify/director-kinetic-budget-capture-correction.log`. This corrects
  newly measured node-budget/capture/full-suite gaps; the round-3 sound, musical
  rotation, release, shrine fit and vertical gun fixes passed their own probes.
  No fourth round is being requested on the earlier same sound/face defect.
- Independently ran the original shipped full game runner against round 4 outside
  the implementer sandbox: exit zero through all 52 steps (two fresh imports and
  50 game scenes), including missile-loop 244, hero-weapons 327 and late-game 71.
  `builds/director-original-full-game-r4.log` is the copy log. The run started
  during round 4; the subsequently edited capture harness still needs its own
  final check. This is not yet a final accepted-root verification claim.
- Three subsequent normal late-game runs each passed 71 checks, with real Knight
  Lv40 node peaks 1187/1187/1186, 40 spirits, nine friendly projectiles and sixteen
  detonations. Actual sweep/cache/missile work totals 1189/1988/4952 over ninety
  physics ticks, below the unchanged aggregate average budget of 256 per tick.
  Headless host timing is logged, not interpreted as physical-device performance.
- A custom SceneTree diagnostic that selected Keeper but never set current_scene
  produced a 1202-node failure. Matching the scene lifecycle of the shipped runner
  (set current_scene to the test) passes with Keeper selected and node_peak 1186;
  a default-hero custom launcher also passes at 1186. Preserve the failed diagnostic
  and this distinction: the failure is not reproduced by the original runner or
  its three direct-scene repeats. No budget waiver or speculative production fix
  is justified by that incomplete custom scene lifecycle alone.
- Started independent fresh six-hero natural and six paired guardian bot cohorts
  against the corrected runtime. Both are still running in isolated storage.
  Draft 021 separately reconciles the rewritten combat reference with actual
  awakening/Starfall homing and native lane floors; it is not dispatched yet.
- Fresh independent cohorts completed on unchanged runtime bytes. Natural six
  heroes: 1460.2 simulated seconds, 1432 kills, 21 hits (0.863/min), no stuck;
  Keeper/Knight/Sage finish the first cycle, Warden/Dancer/Eclipse are defeated.
  Per-hero seconds 159.4/124.0/429.4/303.4/204.4/239.6, kills
  27/7/647/287/169/295. This is one automated policy/seed cohort, not an
  all-hero human balance approval. The paired six-guardian cohort completes
  all six, 248.7 simulated seconds, six hits, bullet peak 72, no stuck. Actual
  guardian durations 23.2/58.7/28.9/43.0/19.2/42.0 seconds. Logs and JSON in
  the copy: `builds/director-kinetic-*-final.log` and
  `builds/play/director_kinetic_{nat,gaunt}.json`.
- The independent real-windowed all-hero capture produced Warden strips then
  failed Dancer direction/primary observations and cascaded into silent arenas.
  Deliberately stopped only that tagged capture engine (exit 137 after 465.3s),
  preserving `builds/director-final-weapons.log`; no full capture pass claimed.
  A separate isolated Dancer-strong observer confirms tree_paused becomes true
  before its second arena and remains true after `_settle_arena`; `_to_next=5`.
  It deliberately exits 123 (`builds/director-capture-pause-observer.log`). Raw
  capture-progress flag does not freeze XP thresholds; the actual debug helper
  does. This is a diagnostic staging/lifecycle fault, not a defect in the
  production level-choice pause. Draft 021 includes this measured correction
  if round 4 does not already resolve it.
- The capture's every-arrow dominant-axis assertion also covers melee backups:
  Dancer's candle is 20px above the feet, target 34px right, center about 30.5°
  plus its legal 16° extra lane exceeds 45°. Thus the primary can genuinely
  point right while that backup lane has a downward dominant component. Do not
  narrow production fire to satisfy a false secondary-direction assertion;
  distinguish real primary-aim coverage and secondary fan contracts.

- Operational positive control uses only the existing debug progress-freeze
  method plus a per-arena pause reset in an ignored subclass. It produces all
  192 hero frames and ten beacons in the actual windowed renderer; 715/718
  assertions pass, the only three failures are the independently disproved
  Dancer backup-axis assumption (early right, strong right/left). All primary
  aims/body facings/gun lanes/hits/mark/recoil observations pass; no current
  shipped-harness pass is claimed. Personally inspected all six 32-cell motion
  boards, the six combat screens and 24 enlarged facing cells; shared the
  diagnostics. Body anchors, side hands and weapon motion are readable; crops
  emphasize the body and do not establish complete far-flight/AoE coverage.
  Root diagnostic boards are in `builds/art-review/director-3-0-0/kinetic/`,
  raw 202 PNGs in `op-freeze/`. Production witness remains byte-identical.
- Prepared an operational three-guardian-track audition at the actual first
  guardian pitch ratio 1.10: PCM mono 44100 Hz, 40.704 seconds, root
  `builds/audio/director-kinetic/guardian-three-tracks-preview.wav`. Shared its
  local link; the app panel request is queued, so no automatic playback or
  personal listening claim. Product audio source bytes are unchanged.
- Extra bounded performance angle: an ignored operational variant keeps all
  staged Starfall cards except one effect (pierce), retaining a real non-evolved
  cannon build with faster cadence. The unchanged 71 checks pass: Lv40 cooldown
  0.62836, node_peak 1187, forty spirits, nine friendly projectiles and forty
  detonations; aggregate 2645 visits/91 physics ticks. Log
  `builds/director-hot-cannon-performance.log`. This disproves the concern that
  the dedup only survives the three-card slow sample; it is still one measured
  faster build, not a maximum-over-all-possible-builds theorem. No extra fix.

- Kinetic round 4 completed at 2026-09-30T22:55:38Z, with 75 changed paths.
  The normal windowed all-six/early+strong/four-side harness completed in
  140.2 seconds with 202 PNGs, but failed one of 639 checks: Dancer early-right
  average-of-surviving-backup-arrows direction. Every primary/body/hit/recoil
  and settled beacon observation passes. A partial surviving fan need not
  be symmetric; the false average check is returned with the independently
  confirmed homing/native-lane documentation correction in brief 021.
- Director negative controls in the stable copy: removing same-tick dedup
  fails 3/71 checks including node_peak 1202; forcing muzzle to candle fails
  independent origin contracts. Exact byte restoration passes 71 and 244.
  SHA-256s recorded in builds/director-negative-controls-r4.json; no mutant
  left active. Successfully started round 5 after these operations finished.
  Production is held unchanged; only combat reference/capture evidence/log.
- Started the normal new game from the implementer copy for authorized user
  play while its documentation/capture-tool correction runs. This is not yet
  acceptance into the real tree or a claim of a visible window.
- CUA confirmed the new copy game is visibly open at Moonlit Beacon (DEBUG)
  title, version 3.0.0, with six Shrine entries. Closed only the intermediate
  project-manager window created during UI discovery; the game remains open.
  No gameplay input, device install, purchase or setting change was made.
- Fresh independent inventory: 276 assets / 30,771,043 bytes (import/gitkeep
  excluded), 188 UID files, zero duplicate identifiers. All 667 production
  runtime witness hashes remain unchanged. Director updated only permitted
  guide/verify-command inventory references to 276 / about 30.8 MB.
- Round 5 finished at 2026-09-30T23:25:35Z. Normal windowed all-six
  capture now passes every lane-direction check but fails 1/718: Dancer
  strong-left currently visible primary anchor. Its strip is correctly
  withheld (188 hero frames + ten beacons), so no full capture pass claim.
  Tool SHA-256 f4db55a737d6854c626164a4be7ca98e34a4911060bc21d6386091105962ed9e.
- Independent six-stage range observer passes 113; per-frame observer
  reproduces 1/119 while counting 333 real visible primary frames in the
  failing stage between the 0.25s queries. Actual target distance 34,
  attack range 44.84, tree_paused=false; this disproves a range/pause/game
  failure and establishes timer-sampling aliasing. Logs in the copy:
  builds/director-dancer-{pocket,frame}-observer-r5.log. Brief 022 requests
  current-frame primary observation within the same six-second bound.
- Staging all new paths exposes a separate merge-check failure: the audio
  generator's oscillator-variable name violates the repo numbering-token
  rule, as does its new build-log quotation. Earlier hygiene checks skipped
  untracked new files. No rule exception or checker change is authorized.
  Brief 022 bundles a purely local variable rename, truthful log wording and
  this new sampling correction. All approved WAVs/runtime must stay identical.
  Successfully started round 6; no part of this tag has been accepted.
- All one hundred IAP CSV rows are independently byte-compared with the real
  origin/main base and unchanged. No catalog or purchase behavior edit.
- A separate ignored project snapshot was copied for possible operational
  negative controls while the user's normal game remains open. Its 667
  production hashes match; it was not launched as a second user game.
- Mandatory accepted-root verify stops in the 208-case Play-package
  Node group: 207 pass, the five-language independent Keeper-preview copy
  pin still has the old flat-damage description. No full verify pass claim.
  Brief 023 requests only the literal regression update and factual log,
  retaining every guard and both-wrong/source-swap negative case; started
  fresh tag 20261001-0852-keeper-copy-regression after kinetic acceptance.
- Accepted root initially differed from the 667-file copy witness only in
  five ignored generated localization binaries. Ran the standard isolated
  editor import successfully (5.8s) before subsequent runtime verification.
  Final source/asset comparison and locale verification are still pending.
- The separate root store-screenshot check again fails because physical
  capture proof is missing. Reported only; no marketing recapture/upload.
- After the real-tree editor import, all 667 measured production
  runtime file hashes match exactly, including the regenerated five locale
  binaries. Started the direct-distribution Android build against this
  accepted runtime while the isolated literal-only regression fix runs.

## Final kinetic acceptance and review evidence (2026-10-01)

- Kinetic round 6 is accepted: 75 paths, after the original windowed
  `shot_weapons.tscn` passes 729 observations and writes 192 hero motion
  frames plus ten settled beacon panels. An independent actual-flight
  reversal in a separate ignored project fails; exact restoration passes.
  The user's normal game is not mutated. The report is implementation
  evidence; the director's original harness and pictures are judgment.
- Brief 023 is accepted: exactly the five independent Keeper-description
  literal updates and a factual build-log entry. Director-focused boundary
  suite passes 21/21; source-key swaps, corrupted fields and both-wrong
  comparisons remain intact. Production, catalog and capture generator
  are untouched. The complete accepted-root `pnpm verify` now exits 0.
  Log: `builds/verify/director-kinetic-final-verify-2.log`; the earlier
  failed root log is retained. Final counts: 467 Node tests in 16 groups,
  all 52 original game steps, and 122 compiled scripts. Locale, metadata,
  mirrored skills, hygiene, deterministic assets/store graphics, docs
  build, NUL checks and internal anchors pass. Ordinary game smoke has
  no warning or error.
- Original root `pnpm android:build` exits 0. APK signature verification
  passes; manifest is the unchanged package, 3.0.0 / 15, arm64-v8a.
  ZIP/dex checks contain no tests/tools, signing credentials, IAPKit config
  or BillingClient. Artifact: `builds/android/MoonlitBeacon.apk`,
  109,914,217 bytes, SHA-256
  `22e9a4e9a49d186095bb12c76c169f975404740eae66d0297b4c069b60a33f76`.
  This is a direct-distribution debug build, not a store submission.
- Fresh source/data comparisons: all 667 production witness hashes equal
  the measured copy after root import. Approved arena and guardian WAVs
  retain their recorded SHA-256s. Five Keeper literals equal the generator
  and CSV independently. All 100 IAP rows equal the real main base as
  bytes. Inventory is 276 assets / 30,771,043 bytes and 188 tracked UIDs,
  with no duplicate. Five extra local UIDs belong to ignored Android
  template instrumentation; they are not staged or counted as game scripts.
- The title-transition fixture passes 30 but now prints 33 teardown
  objects. A separate original verbose isolated run also passes and lists
  only zero-reference `RefCounted` instances, no audio node/resource leak.
  Cause remains unestablished; recorded in the PR body, without a
  speculative production change. Its log is
  `builds/verify/director-final-title-verbose.log`.
- CUA freshly confirms the user's normal game at the visible 3.0.0 title.
  No gameplay input or setting/save change is made. Existing diagnostic
  screenshots and the three-track guardian audition remain available;
  no marketing or physical-device capture/install/upload is performed.

The final reviews include the whole `origin/main` change inventory, not
only the latest local changes. Existing exhaustive art/story measurements
are retained when their runtime bytes match; empty physical-device and
human-eight-cycle evidence cells remain empty.

| Review | Angle and actual evidence | Confirmed fixes still needed |
| --- | --- | --- |
| Final 1 | Re-read runtime story/Chronicle/place restoration, beacon risk/reward transitions, six weapon tables and growth/aim/damage paths, audio pools/loop/release/ducking, and performance caps. Original accepted-root full verification passes; reverse direction/muzzle/dedup controls fail when broken and pass after exact restoration. The 667-file witness binds earlier live audio, bots and exhaustive motion images to the accepted runtime. | None — first clean round. The known teardown warning and bounded Echo-ring cap remain explicitly recorded. |
| Final 2 | Change the angle to independent literals and all negative guards, 100 byte-identical IAP rows, deterministic manifest/audio generation, five-locale descriptions, UID inventory, APK signature/manifest/ZIP/dex, docs build/anchors, CI command wiring, locked values, staged-path safety and PR claims versus actual logs. Fresh fetch confirms main remains an ancestor; no PR exists. | None — second clean round. Device/human play, store proofs/submission and GitHub CI/mergeability remain separate pending evidence, not claimed passes. |

The user requested a PR and forbade merging. Local commits are authorized;
push still needs the explicit immediate user confirmation required by
`.claude/commands/commit.md`, and PR creation needs the human-created
`.claude/allow-pr` signal. Neither signal has been received. No push,
PR creation, merge, store upload or recurring automation has occurred.
