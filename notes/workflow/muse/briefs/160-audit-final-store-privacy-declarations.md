# Brief 160: Audit final store privacy declarations

## The ask
“로그인이랑 스토어 검증하고 메인까지 다 머지하고 확실하게 커밋한거 없게 된 상태에서 배포까지 진행해줘 리뷰 제출해”
Prepare an evidence-grounded store privacy declaration inventory for the final account/cloud-save release.

## Why, and what good feels like
The store descriptions must match the actual shipped data flows, including native Firebase/provider handling. The old Play declaration says no account creation and currently lists optional purchase history and diagnostics only. A source-backed, explicit inventory will let the director complete both stores accurately.

## Where things stand
- Read `apps/player-care/content/en.mjs`, `notes/release/privacy-four-zero-draft.md`, native identity source for Android/iOS, cloud coordinator/schema/transport, analytics config/sender and IAP verification code.
- Current final exports configure ordinary Google and Apple; Play Games is unconfigured and not offered. `apps/game/firebase.cfg` is absent; optional gameplay analytics therefore remains export-disabled. Verify the default/read logic rather than guessing.
- The director saved a reversible Play draft for OAuth + Other (anonymous guest), deletion URLs `https://moonlitbeacon.hyo.dev/privacy#deletion`, and email requests for deletion of data without closing an account. Data types/purposes are not yet updated; no final privacy submission is claimed.
- Root stock verification passed 652 Node tests, 76 registered Godot checks and 165 compiled scripts. Android source/signature/state captures have all passed. Capture/export source is frozen; do not change it.
- Official references reviewed by the director: https://firebase.google.com/docs/android/play-data-disclosure ; https://firebase.google.com/docs/ios/app-store-data-collection ; https://firebase.google.com/support/privacy ; https://support.google.com/googleplay/android-developer/answer/10787469 ; https://support.google.com/googleplay/android-developer/answer/13327111 ; https://developer.apple.com/app-store/app-privacy-details/ . You have no network; use these URLs as references, never claim to have fetched them.
- The director's official-source reading: Firebase Auth collects UID and security IP/user-agent data; federated email/profile depends on selected provider. Play collection includes SDK off-device processing, service-provider transfers may be exempt from sharing, location inferred from IP would require location disclosure, and gameplay belongs under App activity/Other actions. Apple saved games/leaderboards belong under Gameplay Content; assigned account IDs under User ID. Firebase platform/version user agent is not linked to user/device identifiers.

## Do
- Produce one concise audit document with separate Play and Apple tables: data type, purpose, required/optional or linked/unlinked, tracking/sharing, exact production source evidence and any uncertainty that remains.
- Account for default Google profile scopes even though the GDScript bridge does not expose email/name. Distinguish profile-URL handling from uploading photo bytes. Trace guest auto-registration and checkpoint upload before deciding required vs optional.
- Distinguish the game's export-disabled analytics from IAPKit's verification/service statistics and Firebase's own diagnostics. Identify actual included native SDKs; do not infer an installations/device-ID SDK from Firebase branding alone.
- Include the deletion route and reviewer guest/provider access implications. Name genuinely unproven device branches separately; do not claim Apple deletion or store purchases have passed.

## Do not
- Change any game code, project/export config, scripts, tests, generated assets, legal site, existing privacy draft, or store metadata.
- Call the network, stores, credentials or device tools. Do not contain account identifiers or personal data.
- Invent a collection, legal conclusion, retention promise or test success.

## Acceptance
Only `notes/release/privacy-four-zero-store-audit.md` may change. Every recommendation cites production lines/paths, clearly separates source facts from category interpretation, and names unresolved evidence. No release-ready or submitted claim. The director will read every line and independently inspect the cited code; hygiene must pass.

## Deliverables
`notes/release/privacy-four-zero-store-audit.md` only.

## Constraints specific to this task
The director is performing captures from the frozen source concurrently. No game/runtime/capture dependency changes are allowed. No model identifiers in prose.

## Settle these yourself
If a category is ambiguous, explain the source fact and give a reasoned proposed category rather than an unsupported certainty. Exact UI choices will be made and verified by the director.

## How the director will judge
Read the complete diff; inspect source citations and compare current exported config and the official reference definitions. Run repository hygiene in the copy and root. No implementation test that merely mirrors the document is wanted.
