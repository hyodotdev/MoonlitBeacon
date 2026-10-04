# Apple authentication and cold-resume validation

Director observations on 2026-10-05 KST. Evidence files below are local,
ignored operation output under `builds/verify/`; no raw Firebase UID, email,
provider credential, public player ID or private backup is published here.

## iPad: native Apple authentication completed

The user completed the native Apple sheet on the connected iPad mini A17 Pro.
The installed game reports 4.0.0, build12. Official CoreDevice Documents reads
and authenticated read-only Firebase inspection establish:

- The original local guest public ID remains the same after Apple sign-in.
- The stored binding names Apple and matches the real non-anonymous Firebase
  user whose provider is `apple.com`.
- The private profile and reservation belong to that UID and original ID.
- The cloud checkpoint payload equals the parsed local checkpoint exactly;
  the public Hall entry carries the same original ID.
- The actual game picture shows Warden gameplay, level2, five defeats,
  18 seconds, and a relic choice after the sign-in return.

This proves migration of the original local guest identity. The baseline had
no Firebase anonymous binding, so it does not prove linking an already-created
anonymous Firebase UID without a UID change.

Evidence: `complete-apple-server-auth-after.json`,
`complete-apple-ipad-local-after.json`, `complete-apple-ipad-cloud-proof.json`,
and `complete-apple-ipad-app-version.json`.

## iPad: full process exit and durable preservation verified

CoreDevice successfully terminated process8912, an official subsequent process
list contained no Moonlit Beacon executable, and a fresh launch created
process8956. QuickTime displayed the actual rendered title after launch.
Local Documents before and after the launch retain byte-identical identity,
Apple binding and checkpoint. The save remains checkpoint1, cycle1, zone0,
Warden at level1, with the same journey and seed.

The user has been asked to tap the title and Continue on the physical iPad.
**The continued gameplay after this cold launch and automatic native SDK session
hydration are still unverified.** QuickTime mirrors the picture and cannot send
an iPad tap. No process-alive observation substitutes for that player action.

Evidence: `complete-apple-ipad-processes-connected.json`,
`complete-apple-ipad-terminated.json`,
`complete-apple-ipad-processes-terminated.json`,
`complete-apple-ipad-cold-launch.json`,
`complete-apple-ipad-cold-baseline.json`,
`complete-apple-ipad-cold-launch-proof.json`.

## Android: cold resume reaches real gameplay twice

The connected physical Android is a Galaxy Z Flip5, not a physical Pixel10.
The installed game is 4.0.0 build17 with the existing Google-linked player.
The first complete restart restored its ID and Resume menu; selecting Resume
returned to actual Night Forest combat (level2, five defeats, 14 seconds).

The repeat was independently recorded: force-stop removed process2425,
`pidof` then reported no game process, and the normal launcher created
process21045. Before/after-launch identity, binding and save bytes matched.
The director operated the actual Resume button through the Android mirror,
observed preparation, then real Night Forest gameplay (cycle1, level2,
six defeats, 15 seconds, 60fps with observed minimum59). New expedition
was never selected. The checkpoint bytes, revision and binding remain equal
also after the resumed arena runs. Journey, route, seed, hero, cycle, zone
and growth match exactly. The identity file's `created_utc` is rewritten by
`PlayerAccount._save_id`; the public ID itself remains unchanged.

These are repeat checks of the existing first-gate checkpoint; this does not
claim a physical-device round trip of every later cycle/fork, another account,
an offline session, or a destructively deleted account. Android Apple browser
authentication remains pending user completion.

Evidence: `complete-apple-android-before-repeat.json` and
`complete-apple-android-repeat-proof.json`.

## What Continue restores

`Journey` and the arena save a segment-entry checkpoint on crossing a moon gate
or entering the next cycle after a guardian reward. Continue restores the saved
hero, level, relic stacks, missile growth, score bookkeeping, deterministic
route and seed at that gate. The exact last mid-combat position, live enemies,
projectiles, cooldowns, combo and floor loot are transient. Backgrounding does
not replace the last valid gate checkpoint. This is the current production
contract, not exact-frame suspension.

The real-tree regression suite separately reports journey499 cases,
cloud-checkpoint63, cloud-coordinator1104, and production-host798 cases passing
in `complete-apple-postfix-verify.log`. Their simulated later fork/reward cases
are automated evidence, separate from the physical first-gate observations.

## Apple account-deletion failure fix

A confirmed iOS defect allowed Firebase user deletion to proceed after missing
fresh Apple authorization code or a token-revocation SDK error. Muse brief168
now stops both paths with one retryable failure and preserves the native
session/local binding. Only successful revocation can proceed to Auth deletion.
The cloud rows are already removed earlier by the existing coordinator; failure
must be retried rather than described as an all-or-nothing deletion rollback.

The director compiled the extracted actual Objective-C methods with controlled
Firebase stubs: all seven behavioral scenarios pass. Replacing only the revoke
method with the previous revision makes the missing-nil, missing-empty and
SDK-error cases fail because all three incorrectly delete the user. Evidence:
`complete-apple-revoke-independent-probe.json`.

No real user account was deleted. Installed build12 and the previously submitted
store IPA do not contain this new source fix. New SDK build/package and store
replacement status must be recorded separately when they actually complete.

`check:store-screenshots` reports stale runtime provenance after the nonvisual
native-source change. No layout, art or player-facing copy changed, and no
marketing recapture or re-upload was performed just to satisfy that fingerprint.

## Final checks in this director pass

A further full Android restart created process24121. Without opening a new
Google picker, the actual Account screen reports `Signed in · Continue with
Google`, with the original public ID, Warden and wave1. This is observed native
session hydration, separately from local binding-file preservation. Evidence:
`complete-apple-android-session-hydration-proof.json`.

Stock real-tree `pnpm verify` finished with exit0 in
`complete-apple-postfix-verify.log`, including the actual journey/cloud/host
regressions, native source/probe contracts, Godot compile/start, assets, locale,
repo rules, mirrored skills and docs build/anchors. The existing-cache official
SDK builds also finished with exit0 for both iOS arm64 variants in
`complete-apple-ios-bridge-debug-build.log` and
`complete-apple-ios-bridge-release-build.log`: static entry-symbol verification,
12 staged frameworks and nine staged privacy resources pass. These are bridge
builds, not a new signed store IPA, device installation or submission.

Muse169's first documentation draft incorrectly generalized identity-byte
preservation to after Resume. The director rejected that sentence and brief170
corrected it: the public ID is unchanged, while `created_utc` is rewritten.
The corrected setup-note diff was inspected, hygiene passed independently in
its copy, and it was accepted. All15 multi-case standing device requirements
remain unchecked. No new marketing images were captured or uploaded.

## Self-review rounds

| Round | Angle and evidence | Confirmed result |
| --- | --- | --- |
| 1 | Actual iOS revoke/delete chain and official Firebase iOS Apple documentation | Missing-code and revoke-error branches wrongly advanced to deletion; fixed by brief168 |
| 2 | Extracted production-method behavioral execution and old-method negative control | Seven scenarios pass; the old method fails three destructive cases |
| 3 | New live-status draft versus per-file physical-device comparisons | Identity timestamp rewrite was incorrectly generalized as byte equality; corrected by brief170 |
| 4 | Re-read corrected note, actual source callback/liveness/error branches, unchanged15 standing requirements and real-tree diff check | No further confirmed defect in the changed source/doc scope |
| 5 | Execute documented checks: stock verify exit0, official iOS Debug/Release SDK builds exit0, local evidence-link existence, final real-tree hygiene exit0 | No further confirmed defect; iPad cold-Continue and Android Apple human authentication remain explicit device boundaries |

The final two review rounds needed no correction. The separate nonvisual
store-fingerprint failure remains disclosed above; no capture permission was
inferred from it. These rounds do not certify unperformed device cases.
