# Brief 118: fit the real account card and brand its provider links

## The ask
"아이콘은 왼쪽 정렬 텍스트는 중앙 정렬 이렇게"
"Google, Apple not ready하지말고 로그인 구현해줘 firebase로"
"ipad 안드로이드 실기기 다 연결되어 있으니까 제대로 테스트 해주면서 해"
Make account management usable at the actual landscape game height, including configured native provider actions.

## Why, and what good feels like
The director's newly built native Android APK visibly cuts the Account heading off the top and the Close/legal footer off the bottom. This was observed through ordinary Title -> saved identity -> Account taps at 2424x1080 (808x360 internal). The account Google link is also a fantasy button, whereas the accepted entry door already uses official marks and left icons/full-door centered titles. A user must be able to read identity/provider, reach link/sign-out/legal/close, and safely cancel delete without clipped controls.

## Where things stand
Root has the accepted 117 left-column official provider factory and donor-linked consent. The director ran full pnpm verify successfully. Existing test_gate_entry_layout.gd opens Account without link_providers/can_sign_out/can_delete, so it never exercises the production native local guest variant. Relevant files: gate_account_panel.gd, gate_panel_base.gd, gate_provider_buttons.gd, production_entry.gd _open_account, test_gate_entry_layout.gd and test_gate_entry_states.gd. The native snapshot shows the Account heading above viewport, a full-width Google link, sign-out/delete row, and the lower half of footer below viewport. Generic base recenter min(view.y - 16) cannot beat a child's larger minimum. No source changes have been made since 117 acceptance. Do not assume provider activation solves the layout.

## Do
- Fit the real Account panel at 808x360 and wide phone/tablet framings. Use a considered compact arrangement or bounded scrollable content with a reliably reachable footer, keeping honest provider/hero/save/public ID and working copy/privacy/support/metrics controls.
- Reuse the existing GateProviderButtons factory for Google/Apple account link doors, preserving brand marks, opaque text, left logo/full-button-centered title, accessibility and native signals. Unknown optional providers keep game controls. Do not weaken readiness.
- Cover actual production variants: local guest with ready and unready providers, linked cloud, sign-out/delete visibility, armed delete/cancel, absent hero/save, long localized text and both providers. Assert card/frame fit and real touch reachability; if scrolling is used, exercise actual scroll and focus/press of offscreen controls rather than falsely requiring all descendants inside the clip.
- Preserve data and two-step delete behavior, external-link routes, analytics default-off and UI input blocking outside the dialog. Add meaningful coverage registered in the current tests.

## Do not
- Change auth/cloud logic, secrets/provider configurations, version/presets, package/engine/renderer/stretch/global filtering, original Title/six-hero world, store captures, or protected files.
- Duplicate official assets or rebuild accepted entry button composition. No gray/default UI; no smaller touch targets just to squeeze rows.

## Acceptance
Director-owned checks will run candidate gate-entry-state and layout suites, windowed actual Account production data variants at 808x360 and 4:3, and inspect screenshots. Card and required header/footer must remain within viewport; all actions must be reachable by actual pointer/scroll at >=44 logical height (existing explicitly compact ID accessory exception may remain). Google/Apple account links resolve the live factory's logo/title and full-axis alignment/accessibility. A negative control reverting the corrected layout/brand line must fail a new meaningful regression. Account close/back, link request IDs and cancel-before-delete remain correct. Existing 117 state/layout contracts must stay green.

## Deliverables
Narrow UI source and relevant existing test files; an author-only account layout note under notes/plans. Do not modify production docs unless a player's behavior changed. Report tests actually executed and any limitation honestly.

## Settle these yourself
Prefer a balanced identity summary and action section to shrinking every font. If a scroll is necessary, keep Close visible and prevent hidden content from leaking outside the card. Reuse the exact existing official action labels in all five locales.
