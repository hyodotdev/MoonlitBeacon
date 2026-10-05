# Brief 172: Preserve the gallery when replacing the reviewed build

## The ask
“근데 이미 심사 제출했는데 빠르게 취소하고 이거는 중요한거니까 업데이트 해주면 좋겠어”
“스샷은 새로 안찍어도 돼”

Support this explicitly authorized replacement release without recapturing or reuploading store images. The director operates the stores after all animation checks pass; you implement a narrow release-tool mode and advance the prescribed build counters.

## Where things stand
- The director canceled the iOS 4.0.0 review. Its exact version now has `DEVELOPER_REJECTED`; all existing metadata and uploaded images must remain.
- Current display version remains **4.0.0** on both stores. Android has published versionCode **17** and iOS last uploaded build **12**. The next artifacts must be Android **18**, iOS **13**. Change only both `version/code` values 17 → 18 and `application/version` 12 → 13 in `apps/game/export_presets.cfg`. Leave display versions, package names, all other preset keys, project settings and art alone. This is the user's requested replacement release, not a new display-version decision. The director will explicitly review and allow this single protected preset path during acceptance; report it as protected, do not disguise it.
- Another isolated implementer round owns all actor/game animation and gameplay documentation. Do not touch its files. This round owns only export counters and App Store release-tool/gallery-preservation behavior, its Node tests and the relevant release procedure documentation.
- `scripts/app-store-release.mjs` always calls `runAppStoreScreenshotValidation` before creating a payload. That strict capture freshness check fails after any game source change, even when an operator deliberately retains an already uploaded gallery. The ordinary full release behavior must stay strict.
- `buildAppStoreReleasePayload`, manifest verification and `scripts/lib/app-store-connect-apply.mjs` already verify PNG byte integrity, remote image/readiness and submission target/build readback. Reuse those contracts; do not invent new hash claims.
- Android already has `scripts/apply-play-binary-only-update.mjs`, preserving exactly the committed gallery and comparing remote ordered hashes before/after. No new Android publishing path is needed.

## Do
1. Add an explicit App Store **reuse committed gallery** operator mode (for example `--reuse-committed-gallery`) that supports local manifest check, GET remote audit, replacement-build apply and review submission. Normal releases retain strict screenshot freshness. Reuse mode must mark capture evidence as **retained existing uploads, not fresh capture** in output/receipt and must never rewrite capture reports or provenance to pretend old captures are current.
2. Preserve local PNG/provenance/file integrity checks. Before any remote mutation require that all existing App Store marketing sets and IAP review images match the pinned retained manifest by existing remote comparison contracts, in their order/count/completed state. Refuse any create/replace/reorder/delete/missing/unresolved image plan. Confirm all related image targets unchanged again in preflight. Ensure this mode cannot invoke any image or screenshot mutation endpoint even if remote state changes between preflight and apply. Keep the existing auth, version/build readiness, validation, 11 review targets and exact linked-build GET readback checks.
3. Write focused tests that prove normal freshness remains enforced; reuse is explicit and honestly reported; stale capture evidence is not relabeled; missing/changed/reordered images abort before the first remote mutation; a race to a new image mutation is refused; identical retained gallery permits only the required metadata/build/review calls; wrong confirmation or artifact hash fails before authentication/network. Run the related Node tests and revert a negative probe where image mutation protection is removed.
4. Advance only the exact build counters specified above and document the exact reuse-mode commands in the existing App Store release procedure. No store copy or screenshot files change.

## Do not
- No network, credentials, stores, uploads, device actions or git operations.
- No actor/game/asset/documentation changes owned by the other round.
- No screenshot generation, PNG writes, provenance/fingerprint updates, test/check weakening, new bypass environment variables or broad skip-validation option.
- Do not allow gallery reuse when the remote gallery does not exactly match the retained evidence.

## Acceptance
- New mode is explicit at each CLI invocation, and mode/report accurately say there is no fresh capture proof.
- Normal mode still rejects stale captures. Reuse mode checks byte integrity and all remote image targets, and sends **zero image mutation requests** in successful and failing/racing test cases.
- The actual release path still checks new artifact/signing/version/build processing and verifies the expected app plus ten IAP review targets and linked build after submit.
- Related App Store release/apply Node tests pass with a demonstrated reverted negative probe.
- `git diff` for `export_presets.cfg` contains exactly three numeric counter edits, Android18 twice and iOS13 once. Project/display version stays 4.0.0.
- Documented CLI commands parse and run in local-check fixtures; the director will use them against actual retained evidence and store GET state.

## Deliverables
The three preset counter edits, small App Store CLI/library changes and focused tests, a concise update to the existing release procedure, and `IMPLEMENTER_REPORT.md` with evidence and the exact protected path requested for director acceptance.
