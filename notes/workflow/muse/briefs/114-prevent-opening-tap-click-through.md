# Brief 114: opening tap must stop at the chooser

## Continue 112, whose root IGNORE fix is correct
The user's actual tap must open only the chooser, then Guest must answer the next tap. A touch is not permission to open an unrelated legal sheet or activate a provider underneath it.

## Independent evidence
Director windowed real-ProductionEntry all-pointer probe confirms the original menu clicks and mouse title→chooser→Back path work after the root fix. But after actual mouse Hall/Terms/Back/Settings/Shop navigation, a ScreenTouch press/release at the actual title prompt (404,310) opens the chooser AND Terms. director-input112-own-flow-diagnostic.log prints PRE_GUEST terms=true selection=true hovered=Terms. The next real Guest click at404,63 is intercepted by that modal; Start remains hidden and the full journey fails exit1. The captured input112-review-guest-ready.png is actually the unintended Terms sheet, not Ready. The fresh touch-only probe without previous mouse navigation does not reproduce, so preserve the realistic mixed/history sequence in the regression.

Your in-progress test_title_tap.gd has a branch which closes Terms after a title touch: “The touch's emulated mouse counterpart landed on the Terms door after the card opened”. This acknowledges the real bug and works around it in a test. That branch must not count as a passing title-tap result. Never auto-close unintended Terms just to proceed.

## Correction
- Retain ProductionEntry root IGNORE. Prevent the opening pointer gesture and its emulated counterpart from reaching controls which just appeared. Use a restrained input-ownership/release/deferred-open solution. Preserve ordinary button clicks and keyboard/gamepad start, the original title presentation, title feedback, explicit legal links and state transitions. No global input emulation/project-setting changes. Never globally swallow every future tap, disable real menus, or gate keyboard behind a held pointer indefinitely.
- The windowed test must assert Terms/Privacy/Ready/loader are NOT opened by the initial or second title tap; only the chooser opens, provider calls stay0, the next Guest click is usable. Cover ordinary mouse, native touch, and the mixed mouse→chooser→Terms→Back→Settings→Back→Shop→Back→touch prompt→Guest sequence. Touch the natural prompt, not an artificially safe coordinate away from the new card's buttons. Prove exactly one intended transition per opening gesture. Replace the accidental-Terms cleanup branch with an assertion that fails on the current candidate.
- Run focused structural headless regression and report its boundaries; director owns actual windowed tests and pixels. Preserve the negative STOP check, add a meaningful negative for the click-through fix and byte-restore. No full verify repeat or unrelated changes.

## Acceptance
Director's existing all-pointer real-host flow reaches actual Ready with a valid durable ID, then actual Arena, movement, saved return and resume. No unintended Terms on any title tap or disabled-provider click. Real menu/legal/footer clicks still work. No ScriptErrors. No provider branding changes (113 is concurrent). No test workaround for the actual player defect.
