# Brief 125: place guest below Google and Apple

## The ask
"게스트로 들어가기가 젤 아래 있어야하고 구글로 로그인 하면 구글 게임즈랑 연동되는건가? 내가 이렇게는 안해봐서"
The login choices must read Google, Apple, then Guest at the bottom. The director answered the authentication question separately; this is a UI ordering edit only.

## Why, and what good feels like
The official sign-in doors should be the first choices. The local Guest alternative remains an equally usable final choice before the provider status notes, consent sentence and Back footer.

## Where things stand
apps/game/scripts/ui/gate_entry.gd builds _logged_out_box with the Guest button before the Providers VBox in _build_card. ORDINARY_PROVIDER_IDS already fixes Google then Apple. Official logos, full-door-centered titles, exact linked consent sentence, clearspace and touch heights were already accepted. Another copy is editing the hero forecourt context elsewhere in gate_entry.gd; preserve it and keep this diff confined to the logged-out button construction.

## Do
- Put the Providers VBox before Guest in the visible login card so Google -> Apple -> Guest is the actual geometric order, preserving all button names, signals, states, labels, sizes and provider readiness.
- Correct the nearby Guest-first comment. Keep status notes and linked consent below the last choice, with Back as the footer.
- Run the existing gate-entry state/layout regressions. If an old assertion explicitly pins Guest-first, update only that intentional ordering expectation and explain it; do not weaken fit, touch, contrast or pointer checks. No new tests are necessary for this reversible ordering change.

## Do not
Change authentication/native/backend/configs, official button art or typography, login readiness, account panel, title/forest/forecourt context, modal handling, loading, package/version/presets, project.godot, SDKs, protected paths or store files. No new UI wording about Play Games, no new fourth choice, no extra refactor or author note.

## Acceptance
Existing layout and state suites pass. The director will render actual Google/Apple/Guest choices in Korean at 808x360 and tablet framing and test a real Guest tap. Guest's top edge is below both official buttons, consent remains readable with live links, and full button touch targets still fit.

## Deliverables
Narrow change to apps/game/scripts/ui/gate_entry.gd; existing test expectation only if it actually pins the superseded ordering.

## Constraints specific to this task
One ordering edit, preserve all names so native/input routing keeps working. Do not touch the other packet's tests or forecourt placement. Run the store fingerprint and report expected stale, no capture.

## Settle these yourself
Keep current focus behavior unless the existing navigation explicitly becomes invalid; focus does not authorize a separate UX redesign.

## How the director will judge
Read the small diff, run existing state/layout checks, capture real card pixels and complete the physical Guest login at the new bottom position.
