# Brief 142: Export an IPA with a validated existing distribution profile

## The ask
“로그인이랑 스토어 검증하고 메인까지 다 머지하고 확실하게 커밋한거 없게 된 상태에서 배포까지 진행해줘 리뷰 제출해”
Fix a confirmed IPA export blocker without weakening release signing checks.

## Confirmed evidence
The current 4.0.0 (12) Release archive succeeds, including a normal Assets.car and native Apple sign-in. `pnpm ios:export-appstore` fails because automatic export chooses a cached App Store profile that lacks Apple sign-in and the valid installed distribution certificate. The director has created and installed a fresh IOS_APP_STORE profile for the existing app and existing distribution certificate, independently checked its team, app identifier, expiry, distribution-only flags, certificate and Apple sign-in entitlement. Do not create keys, certificates or profiles yourself.

## Do
Add a narrowly scoped optional manual profile path to `scripts/ios.mjs` and `scripts/lib/ios-distribution.mjs`. Keep automatic signing as the default when no explicit manual configuration is supplied. Accept a caller-supplied installed profile and existing certificate identifier using clearly named environment variables. Read and validate the profile before any export: expected bundle/team, current validity, no provisioned devices, get-task-allow false, valid distribution type, matching certificate, and the archive's required Apple sign-in entitlement. Reject partial/malformed/mismatched or expired configuration with a useful redacted error. Reuse existing profile/signature parsing and assertions where possible. Generate manual ExportOptions with exactly the expected bundle mapping and existing certificate; avoid automatic cloud provisioning updates in manual mode. Keep normal archive, IPA validation, version/bundle/team checks, sensitive-value redaction and failure cleanup intact.

Add meaningful existing-suite tests for default automatic behavior, valid manual generation, invalid configuration, profile mismatch and missing required Apple entitlement. Explain the two public environment-variable names and local usage in a short distinct note. No real private paths or personal details.

## Deliverables and boundaries
Only scripts/ios.mjs, scripts/lib/ios-distribution.mjs, related existing tests and notes/release/four-zero-ios-profile-export.md. No game, version, asset, store image, credential, guard, guide or network changes. No Xcode/device operations or git history. Other release-copy changes are being judged separately.

## Acceptance
The director reads the complete diff and runs the distribution suite plus related script tests. Existing automatic mode stays byte equivalent where practical. Invalid manual data fails before invoking xcodebuild. The director then exports the existing Release archive with the independently verified fresh profile and installed distribution certificate, and all normal IPA/dry-run checks must pass.
