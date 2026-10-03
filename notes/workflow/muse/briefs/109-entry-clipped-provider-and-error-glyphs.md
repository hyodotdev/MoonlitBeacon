# Brief 109: visible provider and error notes in the existing entry card

## The ask
“그냥 ㅇ원래에서 tab to start 누르면 게스트, 구글, 애플 로그인으로 시작하게 하면 안돼?”
“화면들은 다 창의적으로 해달라고 부탁했었엉”
Preserve the accepted original title and chooser; fix two explanatory notes hidden by the same measured wrapped-label sizing issue as the loading overlay.

## Evidence and state
The latest accepted root includes title round 5. The director rendered `res://tools/shot_gate_entry.tscn -- state=error locale=ko shot=...` windowed. After the harness's normal 0.6s settle the card shows the red failure title and three buttons but NO actual error detail, even though the fixture supplies `TEST sign-in failed: network unreachable`. GateEntry `_error_detail` is autowrap WORD_SMART, max_lines_visible=3, clip_text=true. `_provider_note` has the same configuration; platform-listed unready providers must show their honest notes instead of silently disappearing. Director separately measured the equivalent loader stage at actual rect height 1px across every loading frame. Brief 108 owns ONLY gate_loading_overlay.gd and its loading/layout tests in another copy; do not touch those files or GateEntryStyle.

## Do
- Narrow fix in gate_entry.gd: reserve accurate wrapped rendered line height for every visible clipped wrapped entry label at actual content width before card layout. ErrorDetail and ProviderNote must actually paint. Keep max-lines cap, fixed card width, all auth truth/flow and original title/buttons unchanged. Clearing/shortening notes or locale/resize must shrink/adjust correctly, not leave giant empty gaps.
- Add actual glyph-height / no-overlap checks only in test_gate_entry_state.gd (all prior cases retained) for provider-ready/unready/empty and error note states, error→clear→error changes, five locales and 808x360 / 840x360 / 808x606. This test is already registered. No separate runner changes. Confirm guard fails with only the sizing behavior removed, restore and report.
- Finite focused state suite and compile check only. Director renders pixels, integrates both disjoint packets and runs final verification.

## Do not
- No edits to gate_loading_overlay.gd, test_gate_loading.gd, test_gate_entry_layout.gd, GateEntryStyle, original title/buttons, Host/Journey/cloud, native SDK/config, assets, public docs, manifests, project/version/export values or protected files. No full suite, screenshots, network, devices, stores or git history.
- No readiness invention, authentication bypass, placeholder records, shortened error content, line-count budget relaxation, skipped tests or layout redesign.

## Acceptance
- Director's settled error capture visibly reads the actual supplied detail. Listed-unready provider notes visibly explain unavailable/draining state. Actual Label rect height >= required wrapped font height capped at the existing 3-line budget, not just visible/text-nonempty flags. Labels and buttons inside the centered card without overlaps on all framings/locales.
- Ordinary provider ordering and honest disabled state, guest escape, persistent error hold, Terms/Back, original title chrome mutual exclusion, full unique ID semantics and all previous assertions unchanged.
- Exact file scope gate_entry.gd + test_gate_entry_state.gd + distinct notes/plans/4-0-0-entry-note-glyph-log.md. Existing focused suite passes with zero SCRIPT ERROR; new assertion demonstrated to fail under a narrow negative control.
