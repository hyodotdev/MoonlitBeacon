# Brief 117: Left provider icons, independently centered text and linked consent

## The ask
“아이콘은 왼쪽 정렬 텍스트는 중앙 정렬 이렇게”
“그리고 아까 공유해준 SecondRound_Takedown 처럼 다음으로 이동하면 이용약간 및 개인정보 어쩌고 이 문구 그대로 해서 링크도 넣어줘”
Make the official Google/Apple logo a stable left column and center each action title independently on the whole button axis. Replace the paraphrased acknowledgment with the pinned donor exact inline-linked consent.

## Where things stand
Current Root includes accepted114 pointer ownership and116 provider composition. Full Root verify exited0 before this new direction. Actual Root Korean chooser screenshot was reviewed: button rect about328x44, dark Google/white Apple opaque14px, but logos move with centered mark/title union. Factory apps/game/scripts/ui/gate_provider_buttons.gd uses fullrect HBox Group and labeled-by Group/Title. Existing state10472/layout73800 tests enforce previous union center; those assertions need changing to the user's NEW independent icon/text contract, with all unrelated semantics retained. All Root4 work is uncommitted. Original Title, six heroes, calm UI light mask, native provider dispatch and originals must stay intact.
Pinned read-only reference31d2754197974b6e6ea51e90edf3fc6fb2dc0364 extracted under notes/workflow/muse/donors/left-icons-consent-117. Exact Korean: “계속하면 %s·%s에 동의한 것으로 간주합니다.” with terms label“약관”, privacy label“개인정보 처리방침”. English/Japanese exact donor translations exist in JSON; add matching Chinese variants in existing five-locale table. Donor inline urls=tos/privacy invoke their own legal surfaces. Do NOT copy another game's legal body or link users to another game's policy. Moonlit existing Terms sheet and published privacy URL are the appropriate targets.

## Do
- Use static anchored/declarative responsive composition: visible Google/Apple marks align on a common left-column center, default32logical px from door left (or equally safe measured position); stable across locale/text length. Keep full official Apple padded31x44 artwork and intact20pxGoogle glyph. Actual visible glyph centers should align within1px. Respect platform minimum edge padding/clearspace; no altered art bytes.
- Text glyph line center must match whole button center within1px independent of logo/word length. Use symmetric reserved edge space or equivalent, avoid overlap in all current locales/widths. Retain44px, opaque14px colors/fonts, native disabled/press/focus semantics, live translated accessible action label, mouse-transparent decoration. Do not use native icon/text centering (known overlap bug).
- Consent becomes small readable inline-linked text, exact donor ko/en/ja template and term labels. Both named phrases must be visibly links (clear accent and underline acceptable). Terms opens existing Moonlit in-app sheet; privacy dispatches safe existing Moonlit URL. Neither link starts play or selects Guest/provider; locale changes update text and urls correctly, selection/error/busy layouts retain full consent.
- Retain original footer Back; remove redundant separate Terms/Privacy footer buttons if inline targets fully replace them, avoiding duplicate navigation. Preserve test/harness helper APIs or adjust all related production callers/test paths intentionally. Update existing focused state/layout/input suites for NEW contract, preserving unrelated checks. No extra test suite just to mirror UI properties; live geometry and real-link/press regressions are meaningful.

## Do not
No Firebase/native credentials, network, provider enabling, readiness fabrication or unsupported desktop fake login. Director configures auth externally in parallel. No title/shop/world/assets/version/project lock/build runner rewrite or broad docs edits. Never touch secrets/protected paths, marketing/store captures, git history. Do not change provider bytes/font/opacity/accessibility or relax unrelated tests.

## Acceptance
Candidate state/layout and existing real windowed Title pointer suites pass. Five locales and compact/wide/tablet existing framings show both logos fixed left, both title glyphs centered on door axis, no overlap/clipping, all consent visible/clickable, Back usable. Full44px equal buttons, all capability states honest. Real pointer consent-link taps route correctly without Terms click-through from openingTitle gesture and without Guest selection. Existing accessible bindings remain live. Provide actual real ProductionEntry Korean window screenshot and geometry readback, not just property flags. A guarded negative re-centering logo/title union must fail actual alignment checks; unrelated masks/native semantics tests unchanged.

## Deliverables
Narrow factory/gate/localization changes, associated existing state/layout/input tests and capture helper updates only as required, distinct notes/plans/4-0-0-left-icons-consent-log.md. No public docs publication.

## How the director will judge
Read complete diff; run focused suites, render actual production chooser, read glyph widths/rects and click links using isolated native input. Negative control on candidate then byte-exact restore. Normal accept only, integrated Root checks afterward.
