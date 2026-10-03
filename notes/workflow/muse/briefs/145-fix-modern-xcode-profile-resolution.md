# Brief 145: Resolve the installed profile used by modern Xcode

## The ask
“로그인이랑 스토어 검증하고 메인까지 다 머지하고 확실하게 커밋한거 없게 된 상태에서 배포까지 진행해줘 리뷰 제출해”

## Confirmed defects in 142
The new resolver searches only the legacy MobileDevice/Provisioning Profiles directory. This machine's Xcode uses Library/Developer/Xcode/UserData/Provisioning Profiles, where the independently checked fresh App Store profile is installed. Therefore this result cannot resolve the actual profile and would fail before export. Support both standard directories without moving or deleting user profiles, scan UUID filenames case-insensitively and keep name lookup behavior deterministic. Reject ambiguous different profiles under one name instead of taking an arbitrary first match.

The optional signing identity currently rejects a 40-character SHA-1 certificate fingerprint. The owned keychain has more than one certificate with the same Apple Distribution common name, including an older revoked one. Accept a SHA-1 fingerprint, match it to a currently valid distribution certificate in the validated profile (using certificate raw bytes / normal X509 fingerprint), and pass that exact fingerprint to ExportOptions. Preserve name mode for existing callers; reject invalid hash length/shape and non-matching/expired/development certificates before xcodebuild. Prefer the verified profile UUID in the manual bundle mapping to avoid a name collision.

## Acceptance
Keep the prior four-file scope and all release validations. Add meaningful resolver tests with temporary directory fixtures for the modern path, legacy fallback, mixed-case UUID and ambiguous names; isolate pure directory resolution in the existing distribution module if needed to test without reading private local profiles. Add valid fingerprint and wrong/expired fingerprint tests. Director runs tests and exports the actual existing archive using the known modern installed profile and existing valid certificate. No network, cert/profile creation, machine operations, credentials, game changes or git history.
