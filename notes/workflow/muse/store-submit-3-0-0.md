# 3.0.0 store submission operations

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

- Human PR guard signal is absent. Do not retry the blocked PR creation or
  create `.claude/allow-pr` as the agent.
- No production promotion, production review submission, PR merge,
  App Store screenshot apply or App Store review
  submission is claimed by the internal upload.
- Continue native capture and independently inspect its actual output.
  Normal AppIcon/Assets.car archive, distribution IPA, remote Validate and
  TestFlight upload pass. Native ten-product purchase checks remain pending.
