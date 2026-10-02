# Brief 040: align the public game reference with the final release

## The ask
"그 문서사이트 업데이트는 됐나"
"이제 머지해도 되지 않아"
The human now authorizes merging the existing renewal PR and publishing the documentation site. Finish the confirmed stale public reference text before that operation.

## Where things stand
The branch is verified and published, with all four latest PR checks successful. Final real-tree pnpm verify already passed 500 Node cases, 52 game steps, 122 scripts and 67 App Store tests. No game changes are needed.

The real release is Android 3.0.0 versionCode 16 (official production state PUBLISHED) and iOS 3.0.0 build 11 (actual App Store submission WAITING_FOR_REVIEW, app plus ten IAP versions, manual release after approval), observed on 2026-10-02. App Store final sixty marketing screenshots and ten IAP review images are uploaded. Play keeps its already renewed 3.0.0 gallery from the earlier capture. Native purchase verification for this exact final release is explicitly unfinished and skipped by human authorization; do not claim native purchase E2E passed.

Actual apps/docs/docs/game.md problems:
- Project version table still says iOS build 10 / Android versionCode 15.
- Paragraph after Hero voices still says 3.0.0 screenshots were not recaptured.
- Product paragraph claims all ten purchase/verify/grant/restart/consume paths checked on physical Pixel and iPad, without separating historic evidence from this final release.
- Version tags section calls 2.1.0 the last recorded store release, although Android 3.0.0 is now published. The course's release-2.1.0 snapshots and chronology must stay intact.

## Do
- Make the public game reference accurately state final 3.0.0 identifiers (iOS 11 / Android 16).
- Correct the outdated screenshot statement in plain student-facing language; omit author policy about when recapture is allowed.
- Remove or clearly scope the unsupported current-release native-purchase completion claim. Keep the ten product identities and behavior contracts intact. No human waiver/approval workflow prose on the student site.
- Distinguish the historical final tutorial release 2.1.0 from the current 3.0.0 renewal. A dated short status should accurately distinguish Android published from iOS submitted for review / manual release. Do not claim Apple approval or a new release tag.

## Do not
- Change game, versions, stores, screenshots, captures, manifest, assets, prices, signing, workflows or course lesson snapshots. No network/git/device work. Do not rebuild game binaries or recapture.
- Do not add production notes, presenter instructions, secrets, local paths or user approval text to the public documentation.
- Do not write tests for this small prose correction or rewrite unrelated sections.

## Acceptance and deliverables
Only apps/docs/docs/game.md may change. Read the whole affected sections and make the smallest clear correction. pnpm docs:build and pnpm check:docs pass; pnpm check:hygiene passes. Final status is dated 2026-10-02 and does not promise iOS is live. The director independently reads the diff, reruns documentation checks on the real tree, verifies runtime/image bytes unchanged and waits for latest-head CI before merging.
