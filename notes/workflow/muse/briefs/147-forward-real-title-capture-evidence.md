# Brief 147: Forward real production-title capture evidence

## The ask
“물어보지말고 끝까지 진행해줘 배포까지”
Finish truthful screenshot evidence for the actual 4.0.0 production entry.

## Where things stand
The physical iPad producer builds/installs the isolated capture bundle and
then rejects the first title state: `Title app version string is invalid.`
The state has `expected_version: v4.0.0` and host/startup flags but no
`version_text`, layout, live copy, renderer, or other title proofs.
`ProductionEntry.debug_store_capture_state()` returns a small host dictionary
for `kind == title`, whereas the visible original Title child already has
the comprehensive `TitleMenu.debug_store_capture_state()` implementation.
The entry's preparation also omits the Title child's prompt-blink capture
hold. Panel requests already forward to the original child.

## Do
- Use the real visible Title child's capture preparation and full state for
  production-entry title captures; retain useful gate context without
  overwriting title fields with unrelated host-ready semantics.
- Reject an open selection, loader or gate panel instead of claiming a clean
  title underneath it. Keep actual-version and actual rendered-node evidence.
- Add a regression using the real production-entry scene and visible widgets,
  with full title state accepted by the existing Node capture validator. Cover
  title prompt freeze across observations, locale, actual version mismatch and
  an occluding gate panel. Register meaningful Godot checks in the runner.

## Do not
Do not weaken Node/Python consumers, fake proof flags, use expected version as
actual version, change player-facing art/layout/copy, contact URLs, auth,
save ownership or purchases. Do not use a hand-authored passing state fixture
as the only integration proof. Avoid unrelated cleanup or comments. Do not
write deployment/evidence files as claims of a real-device run.

## Acceptance and director judgement
Read the whole diff; run the new real-scene regression plus related title,
production entry and capture tests. Independently restore the old forwarding
behavior and observe the new integration fail, then restore exact bytes and
pass. The actual iPad and phone producers must progress through the existing
title consumer without altered validation. Preserve current published-screen
behavior and existing account/save tests.

## Deliverables
The narrow production entry capture bridge, relevant regression source/scene
and test registration only. Prefer extending existing tests where meaningful.
