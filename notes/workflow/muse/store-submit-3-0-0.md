# 3.0.0 store submission operations

## Final-build request on 2026-10-02

- The user explicitly requests final builds and review submission on both
  stores. Brief 034 narrowly authorizes the necessary unique build numbers.
  Its three-line preset diff is independently byte-compared, then accepted
  with the existing protected-path `--allow` mechanism. Android is now
  3.0.0 (16), iOS 3.0.0 (11); every other preset byte is preserved.
- The director independently confirms all 667 corrected-runtime witness
  hashes match the reviewed game. The signed AAB is 60,357,666 bytes with
  SHA-256 `46c6e65220a3cad736b07d3249585989c609ff6a4c5598e6e3ab0d66396ae781`.
  Actual manifest, configured signer pin, localized names, IAP/Billing and
  release resource boundaries pass. Android and iOS build-test groups pass
  34 and 58 checks, respectively, and hygiene passes.
- Normal iOS archive and manual distribution export succeed for build 11.
  The unchanged verified local certificate/profile are reused. Both
  operations restore the original keychain search list. Local IPA validation
  passes AppIcon/Assets.car, arm64, signature/profile, identity, exact versions,
  IAPKit public-key-only and resource checks. No public review is claimed.
- Existing store PNGs remain byte-identical to the reviewed head: 90 Play
  and 70 App Store files. The final App Store canonical provenance remains
  incomplete; the strict Android capture source check remains stale after
  the non-visual circle correction. No proof is rebound or forged. A preset
  bump is excluded from the runtime fingerprint but is still included in the
  separate capture-input maps; the implementer's report conflates these.
- Native ten-product purchases and final device direction evidence remain
  unestablished. The connected Android is a sideload with installer null;
  Pixel 10 is not connected. Human answers about using the Galaxy, test
  accounts and new five-language iPad captures are pending. General submission
  authorization is not a substitute for those observations.

The user explicitly requested new submissions to both stores, including
screenshots. This extends the previously approved release work. It does not
create the human-owned PR guard signal or replace native purchase evidence.

## Google Play

- Local manifest gates pass with digest
  `49a36ba1dfe649f221615d716d66de56a0d3ec1af6bd640da46e7e6ec24eb073`.
  Package is `com.crossplatformkorea.moonlitbeacon`, version 3.0.0 (15).
- First apply failed before commit at the Korean listing with HTTP 503.
  The tool discarded its edit. Remote readback still showed 2.1.0 (14)
  on internal and production before retry.
- Retry committed edit `17502425653562649571`. The official release readback
  at 2026-10-01 16:06 UTC shows 3.0.0 (15) published on internal;
  production remains 2.1.0 (14).
- A separate readback-only edit confirms ordered SHA-256 equality for all
  90 new screenshots and 10 unchanged icon/feature-graphic payloads, plus
  exact five-language listing copy. That readback edit was discarded.
  No product synchronization or production promotion was executed.
- Evidence: `builds/verify/director-store-submit-play-apply-retry.json`,
  `director-store-submit-play-after-apply.json`, and
  `director-store-submit-play-media-readback.json` in the same directory.
- Native purchase and physical direction checks remain incomplete. The
  attached Galaxy currently has a sideloaded 3.0.0 (15) with installer null.
  It has not been uninstalled, replaced or wiped. Tester email lists and
  license-tester membership are not established by the Publisher API GET.

## App Store preparation

- Initial remote GET shows 2.1.0 and 2.0.0 ready for sale, with latest build 9.
- The old Moonlit App Store profiles are invalid. Created and GET-verified
  a fresh App Store profile `Q32ZP4UU3K`, UUID
  `77c2621a-a0d6-4ce4-9d2d-753a5ce62fe8`, bound only to Moonlit's existing
  bundle and valid certificate `ZXVA44MC99`. Decoded profile confirms the
  locked app identity, correct team, no debug entitlement and no devices.
- Access to that existing distribution private key was blocked. A
  harmless signing probe timed out, then restored the original keychain
  search list. No unrelated password or private key was read or exported.
- Created a Mac-owned development key and Apple Development certificate
  `F5A9VW29BH` for capture/build preparation. Imported it only into the
  Moonlit-owned keychain using its already configured password; a real
  codesign probe and strict verification pass. No existing certificate was
  revoked, deleted or replaced. Private material stays outside the repo
  with restricted permissions and is not printed.
- Created the Mac-owned modern Apple Distribution certificate
  `L3D739X77B` after the legacy private-key access remained blocked.
  Its import, actual signing and strict signature probe pass in the
  Moonlit-owned keychain. Created and GET-verified matching App Store
  profile `CS89Q4Q9ZN`, UUID `2b2009b0-5e3e-4b7d-8508-834ea7cf2b28`.
  No existing certificate was revoked. Neither the old key's password nor
  its private material is needed by this local signing path.
- Normal `pnpm ios:archive` now passes for 3.0.0 (10), including normal
  AppIcon/Assets.car, arm64, signing, IAPKit publishable-key boundary,
  resources and source freshness. Automatic distribution export selected
  a stale team-store profile and failed with certificate mismatch and
  cloud-signing permission errors. Prepared Xcode's supported manual
  export with the verified local distribution certificate and its exact
  App Store profile; no cloud permission or trust protection is changed.
- Manual local distribution export succeeds. IPA is 64,889,357 bytes,
  SHA-256 `69e3b81168e90bfd074a33ef93667b668780d45b72441c86d859a848e505d215`.
  Both built-in validate/upload dry runs pass all archive and IPA gates.
  Apple remote Validate reports no errors. Actual TestFlight upload
  succeeds with delivery UUID `506e796c-b7fa-482d-a609-76adcadc1315` at
  2026-10-01 16:36 UTC. The first immediate build GET is still empty;
  processing completion is not yet claimed. No public version/review or
  App Store screenshot apply has been executed.
- Official build-upload GET at 16:44 UTC confirms the same delivery UUID,
  version 3.0.0 (10), state `PROCESSING`, and zero errors/warnings. This
  confirms receipt by Apple, not a tester-ready build or review submission.
  Evidence: `builds/verify/director-store-submit-asc-upload-state.json`.
- Final official GET at 20:23 UTC confirms `COMPLETE`, linked build 10
  `VALID` and not expired, with zero errors/warnings. Apple processing is
  complete. Evidence: `director-store-submit-asc-upload-final-readback.json`
  under the same verification directory. Public review remains unsubmitted.
- Physical iPad mini (A17 Pro) is paired and has Developer Mode enabled.
  Started the existing nonce-bound Xcode screenshot handoff producer for
  all five locales in the isolated `.storecapture` bundle. This is native
  iPad evidence, and does not claim a physical 13-inch iPad. The Xcode path
  does not require the separately requested sudo RSD daemon.
- The first native screenshot is a genuine current 3.0.0 title, but its
  physical framebuffer is portrait (1488 x 2266), with the game letterboxed.
  The untouched handoff publisher rejects it because native landscape
  evidence must be 2266 x 1488. No image transformation, weakened proof or
  canonical publication occurred. Canceled the producer normally; its
  failure record has zero restoration errors, the production app identity
  is unchanged, and the disposable capture bundle is removed. Human
  physical rotation is requested before a fresh capture run.
- Evidence: `director-store-submit-asc-preflight.json`,
  `director-store-submit-asc-new-profile.json`,
  `director-store-submit-ios-development-certificate.json`,
  `director-store-submit-ios-development-signing.json`, and
  `director-store-submit-ipad-capture-xcode.log` under `builds/verify/`.

## Remaining release boundaries

- The user created the human PR guard signal and asked to finish everything.
  The original guard consumed that signal; PR 10 now exists at
  https://github.com/hyodotdev/MoonlitBeacon/pull/10 and is attached to the chat.
- No production promotion, production review submission, PR merge,
  App Store screenshot apply or App Store review
  submission is claimed by the internal upload.
- Continue native capture and independently inspect its actual output.
  Normal AppIcon/Assets.car archive, distribution IPA, remote Validate and
  TestFlight upload pass. Native ten-product purchase checks remain pending.

## Continued release review after user setup

- Native Xcode capture now returns true landscape 2266 x 1488. Six English
  title, shrine, hero-preview, barrage, missile-core and guardian screenshots
  were individually inspected and accepted by the unchanged handoff publisher.
  This is not a complete five-language canonical set. The producer was canceled
  normally before continuing after a newly discovered game CI failure; its
  record has six completed captures and zero restoration errors, and the
  original keychain search list is restored.
- Exact valid TestFlight build 10 is assigned to the existing Moonlit Beacon
  Internal group. Fresh GET-only audit confirms that assignment; no new tester
  or external group was created. Evidence is
  `builds/verify/director-testflight-internal-group-receipt.json`.
- PR docs, repo rules and signed Android package checks pass. The Linux game
  job fails the original `orbit sweep is a full circle` assertion (expected
  one hit, observed zero). The configured implementer is handling the narrow
  confirmed full-circle defect under brief 030; no CI waiver or merge occurs.
- A separate official App Store GET returned released-only 2.1.0/2.0.0 history.
  The old local version-create predicate incorrectly demanded exactly one
  released entry. Brief 029's two-file correction was read and accepted after
  56 independent App Store tests, zero skipped tests, a negative control with
  two failures under the original predicate, exact restoration, and replay of
  the real response in both list orders. Runtime and capture code are unchanged
  by this store-tool correction. Final root verification follows the game fix.
- Revised production binaries will require new upload identifiers because
  Android 15 and iOS 10 have already been uploaded. Brief 031 names only the
  necessary next Android 16 / iOS 11 configuration values for review. The
  implementer correctly refused the protected version file and made no change.
  Specific authorization for the director's three-line edit is pending.
- Native purchase evidence remains unestablished. The last connected Galaxy
  still reported installer null, and it subsequently disconnected. The user
  was asked whether all ten-product native test checks are already complete;
  no answer is counted as proof.

## CI correction, second review

- Brief 030 round 1 adds full-circle bearing handling and portable precision
  regressions. Independent director runs in the copy pass the actual standard
  52-step game suite and all 388 weapon assertions. The director's negative
  control restores the old predicate and produces the two intended precision
  failures, exit 1. Its wrapper initially treated the result as unexpected
  because it looked for the failure summary in stdout; the summary is in
  stderr. Inspection of the saved combined log confirms the test failures,
  and the finally clause restored the candidate source bytes.
- The next review finds the same defect in the reachable Wide Arc 360-degree
  cap: five genuine Warden card takes reach that cap. Round 1 is not accepted.
  Correction brief 030b requires this path, a partial-arc control and a portable
  negative control against round 1's logic. Only the existing arena and weapon
  test files may change. The final diff will be regenerated after the correction;
  a transient diff taken during the negative control is not an acceptance patch.
- Round 1's implementer wrote 53 identified scratch files outside its copy.
  The director byte-verified archival into the ignored run's
  `director-preserved-scratch/` folder and removed only those identified files.
  Round 030b explicitly forbids further outside-copy writes and substitute
  suite runners. The implementer's claims are not counted as director evidence.
- Android reconnected at 21:53 UTC; a fresh package GET still shows 3.0.0 (15)
  with installer null. Native Play purchase verification is therefore not
  established. The iPad's actual QuickTime mirror is landscape and shows the
  TestFlight app; this observation does not establish a Moonlit TestFlight
  installation, a purchase or restore. No recording was started.
- Round 030b's final two-file diff is independently read. The director repeats
  the round-1 negative control and confirms precisely two new failures out of
  404, exit 1; restores the candidate byte-for-byte; then independently reruns
  the actual weapon scene: all 404 pass, exit 0, in 170.5 seconds. The final
  patch is regenerated after restoration, check-applies cleanly, and is accepted
  into the real tree. Radial bounds, damage, cadence and attack visuals remain
  unchanged; the original 355 assertions are untouched.
- Real-tree `pnpm check:store-screenshots` now fails at its source-fingerprint
  comparison. Existing uploaded image bytes and framing are unchanged; no
  automatic Android recapture or image re-upload is performed. Per AGENTS.md's
  failed-check rule, a question about final-build recapture is pending.
- A different deployment-path review confirms the App Store authorization
  function still hardcodes 2.1.0 (9), rejecting current 3.0.0 manifests. Brief
  032 requests the narrow current-payload authorization correction while
  preserving identity, manifest, token-purpose and provenance boundaries.
  The director reads its two-file patch, independently passes all 58 App Store
  tests with zero skips, and proves the new 3.0.0 fixture fails when the original
  pin is restored. The apply module is byte-restored; the patch is regenerated,
  check-applies cleanly and is accepted. No remote apply is performed. The
  corrected real tree's full `pnpm verify` finishes successfully: 477 Node
  tests across 16 groups, 52 game steps, 122 script compilations, locale/store
  metadata, deterministic assets/graphics, hygiene, docs and internal anchors.
  Evidence: `builds/verify/director-pr10-corrected-root-verify.log`.
- The director re-hashes all 667 files of the previous runtime witness. Only
  `apps/game/scripts/gameplay/arena.gd` differs. Existing art, audio, UI copy and
  other runtime resources remain byte-identical. This comparison records the
  source difference; it does not rebind or repair old device capture proofs.

## Corrected-head Linux validation

Head `c4f876c` passes Linux's actual 404 weapon checks and every other game
regression, plus the independent Android build, docs and repository-rule
jobs. CI run `36935891634` fails later at the three terrain structure PNG
byte comparisons. Director Linux reproduction confirms that all pixels
are equal despite different PNG encodings. The subsequent terrain-tileset
generator has the same three-file encoding boundary; every decoded pixel
also matches. Briefs 033/033b address these checks while preserving all
art bytes. Latest-head full CI success, merge and public review submission
are not claimed before that correction is independently verified.

The final five-file tools correction is independently judged and accepted.
Mac's registered regression passes 24 groups, full asset checks exit 0,
and the director's Linux x86_64 runs pass those 24 groups plus all twenty
Python asset checks. The initial broad container omits icon config/docs
mounts; that missing-file failure is preserved, and the correctly mounted
icon rerun exits 0. All 258 PNGs and the real tree's 304 source-asset files
remain byte-identical; all 667 runtime files match the circle-corrected
witness. Independent original-byte-comparison controls fail one real
generator check group each; ignoring pixel changes fails eight groups.
Exact source restoration passes again. Evidence is under
`builds/verify/terrain-linux/`, including the reconciled Linux receipt and
`negative-probe/receipt.json`. Full final real-tree verification is running.

Fresh device readbacks at 23:25 UTC still show Android 3.0.0 (15) with
installer null and iPad 2.0.0 (8). No user purchase/restore action is inferred.
Both uploaded internal builds are from before the circle correction. Public
submission remains pending the final binary identifiers, native purchase
verification, capture boundary and human PR approval.

Final real-tree `pnpm verify` exits 0 after the terrain correction: 477
Node tests, 52 game steps, 122 scripts and 24 terrain regression groups,
plus locale/store metadata, assets/graphics, hygiene, docs and anchors.
The separate screenshot check remains red at the existing capture-source
fingerprint; no recapture or re-upload occurs. Public release status is
unchanged by these passing code checks.
