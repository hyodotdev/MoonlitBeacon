# 4-0-0 left-icons consent log (Brief 117)

Left provider icons with independently centered titles, and the donor
exact inline-linked consent. Narrow factory/gate/localization change
plus the existing focused suites; no public docs.

## What was built

- Factory (`apps/game/scripts/ui/gate_provider_buttons.gd`): the
  full-rect HBox union is now a full-rect `Control` group with static
  anchors. Each `Logo` pins on the shared 32px left-column center
  (Apple padded 31x44 file at 16.5, Google intact 20px glyph at 22.1,
  both clearing the 16/12px platform edges); each `Title` insets 64px
  symmetric per edge with CENTER/CENTER type, so the glyph line sits
  on the whole door axis independent of word length. 44px, opaque
  14px inks/fonts, native press/disabled/focus, live
  `accessibility_labeled_by_nodes`, mouse-transparent decoration,
  and no native icon/text path are unchanged. `content_group()`
  now returns `Control`; `Group/Logo/Title` node paths are kept.
- Consent (`apps/game/scripts/ui/gate_entry.gd`): the paraphrased
  `Label` is a `RichTextLabel` with the donor sentence and `[url=tos]`
  / `[url=privacy]` inline links in amber with underline. Terms opens
  the existing Moonlit in-app sheet; privacy dispatches the existing
  Moonlit URL resolved at click time (locale-correct). Neither starts
  play or picks a door. A `{comma}` placeholder in the English cell
  keeps the locale table comma-free; the runtime restores the donor
  comma. Locale switches refresh text at once via
  `NOTIFICATION_TRANSLATION_CHANGED`. The footer keeps only Back;
  the redundant Privacy/Terms buttons are gone. `consent_link_center()`
  lands pointer taps from first-line prefix widths for tests.
- Localization (`apps/game/localization/gate_entry.csv`):
  `gate.auth.consent` is the donor template in five locales
  (ko/en/ja exact, en with `{comma}`), plus new `gate.auth.consent.tos`
  (약관/Terms/利用規約/条款/條款) and `gate.auth.consent.privacy`
  (개인정보 처리방침/Privacy Policy/プライバシーポリシー/隐私政策/
  隱私權政策). Unused `gate.auth.terms`/`gate.auth.privacy` rows stay
  (harmless; no unused-key failure for the gate table).
- Tests: state/layout suites assert the new contract from live rects
  (32px column, 64px symmetric reserves, glyph-line centers, 8px mark
  clearance, pair-shared centers); `_test_consent_links_exact` pins
  the donor sentences per locale, link routing, and locale URL
  retargeting; title-tap windowed routing clicks both inline links by
  real pointer; shot validate covers the consent node. No new suite.

## What bit

- RichTextLabel line metrics: with the Maple+Noto pair the label
  sized ko/en lines at 15px (Maple) and ja/zh at 18px (Noto), and the
  label clips, so Korean Hangul would lose 3px. Consent now uses Noto
  alone (all five scripts at one 18px line). Measured: Maple 12px = 15,
  Noto 12px = 18.
- The donor English comma collides with the no-ASCII-comma table rule.
  `{comma}` in the cell plus a one-line runtime replace keeps the CSV
  valid and the runtime byte-exact.
- The shorter one-line consent freed the unready shape from compact:
  the hint-hides expectation for unready at 360px height is now false
  (draining/all-down still compact; card-fit checks unchanged).

## Measurements

- Titles (14px): longest Google 122px (en), longest Apple 119px (en);
  64px insets leave 39px slack per side at the 328px door.
- Apple pads symmetric 31/31px: file center == glyph center exactly.
- Consent (Noto 12px): visible 312/283/268/192/204px, link span ends
  within 282px; all one line with both links on line one.
- ProductionEntry ko headless readback (808x360): Google door
  328x44, logo center 32.0, title center on axis, glyph 102px;
  Apple logo center 32.0, glyph 86px; consent 328x18 exact sentence;
  Back 328x36 enabled; footer has one child.
- Negative controls: baseline HBox factory fails the new state checks
  (150 cases); swapped tos/privacy order fails the 5 exactness cases.
  Both restored byte-exact and green again.

## Checks

- state 9408, layout 66732, title-tap headless 30 (routing needs a
  display), exported-locales 1899 (94 keys x locales), shot validate
  17200, gate-locale 5, hygiene ok, locale ok (moonlit + gate),
  check_scripts 163 compile, smoke quit ok.
- `pnpm test:game` and `pnpm check:store-screenshots` could not run
  green here: the former fails at its reimport step on baseline too
  (sandbox denies editor-settings/adb paths), the latter has no
  capture proofs in this copy. No recapture (forbidden). Windowed
  title-tap routing and the Korean screenshot need a real display.
