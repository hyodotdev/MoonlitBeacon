# Brief 233: align current release prose

## The ask
“제대로 검증하고 /loop-review 돌리고 메인 클린하게 다 머지되고 배포까지마무리해줘 ios android 리뷰 받아”
Finish the authorized 4.0.1 release without misleading public guidance.

## Confirmed evidence
Round 2 correctly conditions the generated Apple and Play reviewer paths
on a verified name AND completed guide lesson. The ten newly rewritten
What's New blocks in `notes/release/store-page.md` still unconditionally
say returning accounts skip the lodge. `needs_lodge_lesson()` requires
both conditions, so interrupted first practice returns to Lumi.

`apps/docs/docs/game.md` line 22 still describes the current project as
4.0.0 / iOS 12 / Android 17 while the selected project is 4.0.1 / 15 / 20.
The beginning of its run flow omits the new first-entry room despite the
later account section already documenting it. Its dated 3.0.0 shipping
history at the end is historical and must stay historical.

`scripts/app-store-release.mjs` help labels the retained-gallery sequence
“same 4.0.0 display version”, although this release uses the same retained
gallery with a new display version. It is guidance for the operator and
must not imply the sequence is limited to the old counter/version.

## Do
Correct the returning-account sentence in all ten new What's New blocks
to refer to completed guides; mention interrupted practice where concise.
Keep five paired translations consistent and each Play block below 500
characters. Preserve every title, description, promo, product and image.
Align only the public reference's current version row and first-entry
run flow with the implemented lodge. Keep historical release facts dated;
do not claim 4.0.1 is published or reviewed yet. Make the CLI help sequence
version-neutral without changing its command arguments or implementation.
Add a short correction entry to the author build log.

## Do not
No runtime/native/art, counters, gallery, credentials, network, store,
signing, permissions or product changes. No broad reference rewrite or
historical evidence rewrite. Keep the existing cumulative patch intact.

## Acceptance
The ten changed release blocks and current reference agree with the actual
guide-completion condition and 4.0.1 / 15 / 20 source identity. Metadata
validation and the existing App Store/Play suites pass. CLI help describes
the actual retained-gallery path. Report these corrections separately.

## Deliverables
`notes/release/store-page.md`, `apps/docs/docs/game.md`,
`scripts/app-store-release.mjs`, `notes/plans/3-0-0-build-log.md`.
