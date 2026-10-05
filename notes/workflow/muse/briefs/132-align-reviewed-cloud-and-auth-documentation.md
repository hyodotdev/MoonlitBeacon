# Brief 132: align cloud and authentication documentation

## The ask
"/loop-review돌리고 메인 다 클린한상태로 둔 다음 할까"
Review the complete uncommitted 4.0.0 work and fix confirmed discrepancies before preparing it for main.

## Where things stand
The game and native bridges are implemented and the normal root verification passed. This is a documentation correction; runtime behavior must remain byte-identical.

The director independently confirmed:
- `moonlit_identity.gd` uses a 30-second ordinary window and a 300-second interactive window for `moonlitSignInProvider` / `moonlitLinkProvider`. The addon README wrongly says every request times out after 30 seconds. Read both test setters and the captured draining windows before documenting them.
- The literal Firestore README command failed before emulator startup: current firebase-tools refuses Java below 21. The default Java was 17. With an installed Java 26 selected for that process and the existing isolated dependency workspace (`firebase` 12.19.0, rules-unit-testing 5.0.2), the byte-current suite passed 38 tests, 9 suites, zero failures. The README says Java 17+ and 37 cases.
- `notes/release/player-identity-setup.md` is a historical standalone-bridge note but its checklist opens with "Firebase Authentication currently has no enabled providers". That statement is now false. Anonymous, Google, and Apple Firebase providers have been enabled during the integration. Android Google and guest flows have actual native evidence; Apple Android Service ID/key completion and actual iPad provider completion remain pending. Optional Play Games readiness is pending. Describe the old statement as the initial baseline and link the director status note for current evidence rather than claiming all providers are operational.

## Do
- Correct the addon README's ordinary/interactive timeout policy, setters, and bounded draining behavior from the actual implementation.
- Correct cloud-rules README Java requirement and case count. Provide a reproducible dependency/setup/run path that does not silently modify the repository dependency lock; either an explicitly temporary workspace with source copies or an honest clearly labeled optional installation. Preserve the exact distinction between source-only splicing and real emulator enforcement. Use local emulator configuration, never a production deployment.
- Mark the identity setup note's no-provider statement as an initial baseline; point to the current integration evidence and preserve the pending Apple / Play Games boundaries.

## Do not
- Change game code, test behavior, native sources, rule enforcement, root dependencies or lockfiles, assets, presets, or Git configuration.
- Claim an Apple device login, release-signing Google login, or Play Games test passed.
- Include any credentials, user identifiers, personal paths, or model name.
- Change the hero manifest's 12fps gameplay walk table: that describes gameplay; the introductory party has its separate distance-driven cadence.

## Acceptance
- Diff contains only `apps/game/addons/moonlit-identity/README.md`, `tests/cloud-rules/README.md`, and `notes/release/player-identity-setup.md`.
- The timeout explanation agrees with `_timeout_for_method`, both setters, and the captured request windows.
- The Firestore instructions require Java 21+ and state the measured 38 cases. Commands can be independently reproduced without modifying tracked dependencies or the legacy rules.
- No report misrepresents pending provider setup as a successful device test.
- Run source-only splice check and relevant documentation/hygiene checks available in the sandbox; clearly distinguish unavailable network/emulator checks.

## How the director will judge
Read the complete diff and source comparison. Re-run the documented emulator workflow with supplied dependencies and a suitable Java process environment, inspect its exit code and case count, then run normal root verification after acceptance.
