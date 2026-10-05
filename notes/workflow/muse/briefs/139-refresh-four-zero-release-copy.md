# Brief 139: Refresh 4.0.0 release copy against shipped behavior

## The ask
“로그인이랑 스토어 검증하고 메인까지 다 머지하고 확실하게 커밋한거 없게 된 상태에서 배포까지 진행해줘 리뷰 제출해”
Prepare accurate final store copy and a reviewable privacy disclosure draft for the 4.0.0 account/journey/art update.

## Why, and what good feels like
Players and reviewers must receive a truthful description of this update. Existing store copy still calls the art pixel art, describes the public ladder as local only, and mentions no accounts. Those claims are stale. Do not claim that a native or remote release gate has passed just because source code exists.

## Where things stand
The current root is committed 4.0.0: Android version code 17 and iOS build 12. All source implementation has seven review rounds, complete integrated verification and real Android current-build guest/Google cache restore evidence. The in-game ID is immutable, guest entry creates an anonymous Firebase identity, Google can link the original guest without changing its checkpoint ownership. Cloud save belongs to the account; Hall shows hero and score. Firebase Google sign-in is distinct from the optional Play Games integration, which is unconfigured. Android Apple Services ID/key setup and iPad terminal authentication tests remain pending. Actual store purchases on this final build are pending. Remote stores currently contain 3.0.0 only; no 4.0 upload, PR or remote merge has occurred. Marketing screenshot recapture permission is pending. Optional gameplay analytics remain disabled in the submit configuration. Read production code and existing public/reference prose for facts, rather than inventing them.

Relevant source input: notes/release/store-page.md; notes/release/store-localizations.csv; scripts/check-store-metadata.mjs; scripts/lib/play-release-package.mjs; scripts/lib/app-store-release.mjs; apps/game/scripts/cloud/; apps/game/scripts/gameplay/journey.gd; apps/game/scripts/net/; apps/game/addons/moonlit-identity/. The public privacy site still describes a launch build with no accounts and a disabled global ladder; its source is outside this repo.

## Do
- Refresh the existing five-language app listing and release notes to accurately describe the painted art, distinct heroes/weapons, guest/account entry, journey resume and Hall. Remove obsolete pixel/offline-only/local-only claims where they contradict mandatory anonymous auth or cloud behavior. Preserve any actual offline fallback distinction supported by source.
- Update stale hero product descriptions/reviewer navigation only where source confirms the mismatch. Keep every product ID, type, price and permanent-versus-consumable behavior unchanged.
- Add a five-language privacy change draft with source citations for Firebase auth/provider profile processing, public immutable player ID and hero/score Hall records, account-owned checkpoint storage, deletion/reauth, anonymous guest caveats, disabled optional analytics, and unchanged purchase-verification processing. Distinguish native Firebase SDK data handling from fields the gameplay layer reads. Do not claim no email is processed merely because the adapter omits it. Do not invent retention deadlines, operator details, legal conclusions or third-party guarantees.
- Record the real remaining release gates in a short distinct note. Existing historical notes can remain historical. Keep current confirmations and completed code evidence separate from pending real-device/provider/purchase/store evidence.

## Do not
No game/runtime/scripts implementation, image bytes, screenshots, manifest fingerprints, credentials, network, stores, git operations, version changes or protected files. Do not weaken tests or make guards green by skipping evidence. Do not mark purchases/providers/store upload/review/main merge complete.

## Acceptance
- pnpm check:store-metadata passes with existing schema, all five languages and ten active product identities preserved.
- Related existing store metadata/package tests pass with unchanged contracts.
- No unsupported simultaneous Play Games claim, no obsolete account-free/public-local-only copy presented as current 4.0.0.
- Director can map each privacy draft statement to production source; missing information is explicitly a release audit item, not an invented promise.
- Diff touches only existing store copy plus a distinct privacy draft and release-copy work note; all asset bytes remain unchanged.

## Deliverables
notes/release/store-page.md; notes/release/store-localizations.csv; notes/release/privacy-four-zero-draft.md; notes/release/four-zero-copy-review.md. Edit any of these only when necessary; use no other deliverable paths without reporting why.

## Constraints specific to this task
Do not write the forbidden lesson term. Keep public contact values already sourced in the repo unchanged. Do not name implementer model IDs. Source locks, signing identities and native capability configuration remain untouched.

## Settle these yourself
Prefer concise factual copy over hype. Keep existing CSV localization keys exactly stable. If current source leaves an offline/native/provider claim ambiguous, flag it in the review note and phrase marketing conservatively.

## How the director will judge
Read the entire diff, compare copy with current production behavior, rerun store metadata tests and verify no asset/runtime/protected path changes. The privacy draft will be reviewed before any external website edit.
