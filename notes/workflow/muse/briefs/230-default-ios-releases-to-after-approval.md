# Brief 230: default iOS releases to after approval

## The ask
“그리고 ios 배포할 때 앞으로 리뷰 승인되면 그냥 앞으 automatic release로 선택하고 배포해줘”

The next and future iOS submissions must select automatic release immediately
following approval, rather than manual release or a scheduled date.

## Why, and what good feels like
A successful review should lead to distribution without another manual
release operation. The director must be able to see the remote automatic
release policy before claiming that a submission uses it. The screenshot
shows the manual radio selected, with immediate automatic release as the
middle choice.

## Where things stand
- Local game and public-site work is already committed in two commits; the
  working tree also holds author-only briefs and original art, not yours to
  rewrite. The root full verify exited 0 before these two commits.
- `scripts/lib/app-store-release.mjs` reads appStoreVersions fields without
  releaseType, and builds version desired metadata without releaseType.
  `scripts/lib/app-store-connect-apply.mjs` sends the desired attributes.
  No AFTER_APPROVAL release setting was found in this path.
- Official Apple update attributes list MANUAL, AFTER_APPROVAL, SCHEDULED:
  https://developer.apple.com/documentation/appstoreconnectapi/appstoreversionupdaterequest/data-data.dictionary/attributes-data.dictionary
- Official selection instructions identify the immediate automatic option:
  https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option
- Existing review-version read-only, manifest/token, reuse-gallery, and
  mutation boundaries must keep their protection.

## Do
- Set AFTER_APPROVAL as the automatic policy for newly prepared iOS release
  metadata and the normal version create/update plan. Do not create a new
  CLI choice or depend on an App Store inherited/default manual value.
- Read and report the actual remote releaseType. Before a review submission,
  verify the applied version is AFTER_APPROVAL through the actual existing
  readback path. A mismatched/unconfirmed policy must not be reported as
  automatically released. Preserve read-only in-review/published boundaries.
- Omit scheduled dates for normal new releases. The governing policy must
  be AFTER_APPROVAL, never SCHEDULED; do not invent an unsupported nullable
  Apple API date mutation just to clear an irrelevant old date field.
- Add focused registered regression cases for version creation, an editable
  manual/scheduled version update, already-matching idempotence, bad readback,
  and refusal to mutate a read-only review/published version.
- Document the default in the existing author release procedure and add a
  short factual build-log entry. Keep this change small and reuse existing
  planning/apply/verification helpers.

## Do not
- No game, native SDK, asset, APK/IPA, version/build counter, screenshot,
  gallery, price, availability, Apple credential or product changes.
- No network, store operation, git history, PR or deployment from your copy.
- Do not submit/cancel a review, immediately release an old approved build,
  or patch an existing remote version. This brief is the future default.
- Do not alter AGENTS.md, .claude/, .agents/, the version lock, or earlier
  unrelated briefs, original artwork or validation evidence.
- Do not broadly weaken old manifest/token/readonly tests. If one assertion
  must include the new desired field, keep its other existing guarantees.

## Acceptance
- The director can inspect create and editable update payloads and see
  releaseType AFTER_APPROVAL, without a requested scheduled date.
- Remote field selection includes releaseType, and automatic-release
  readback failure blocks the existing submission path with evidence.
- Existing read-only review and gallery mutation protections still pass.
- `pnpm test:app-store-release` and related script/hygiene checks pass.
- Restoring the missing desired releaseType or removing the readback guard
  makes the new registered focused regression fail.
- No game bytes, existing canonical marketing image bytes, release counters
  or secret files appear in the patch.

## Deliverables
Minimal changes under scripts/lib/ and corresponding registered tests;
existing App Store author procedure under notes/release/;
notes/plans/3-0-0-build-log.md.

## Settle these yourself
Use the existing release policy and audit structures. Do not redesign the
entire release manifest format. Decide whether the desired policy lives in
release metadata or a shared default, but explicitly generate and verify it
for future releases. Old immutable historical receipts remain historical.

## How the director will judge
Read the complete diff; independently run the related Node suites and a
negative control; verify readonly and retained-gallery paths; compare game,
version and canonical store assets to the committed baseline; accept only
confirmed, narrow changes. The director handles remote operations separately.
