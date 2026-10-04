# Brief 167: align Apple setup status with verified release evidence

## The ask

"애플로그인 문서화등 다 완벽한거지?"

Check the Apple sign-in documentation and correct the confirmed stale setup status without claiming an unperformed native authentication test.

## Where things stand

The working tree is clean at the pushed 4.0.0 feature head. The director just read `notes/release/player-identity-setup.md`: its provider-setup introduction still says Android Apple Service ID/key completion is pending. That is obsolete.

Fresh director execution of `node scripts/build-player-identity.mjs --check --platform ios` reports both iOS Google and Apple READY. The Android check reports Google and Apple READY; its aggregate strict exit is 1 solely because the optional Play Games application ID is absent. This does not make ordinary Google or Apple unready.

The director's authenticated Firebase readback confirms Apple enabled with the Service ID and code-flow team/key/private-key configuration present. Independent inspection of the exact already-uploaded 4.0.0 build-12 IPA confirms its signed Apple sign-in entitlement. The current evidence is recorded in `notes/workflow/muse/director-four-zero-review-status.md` and the final portions of `notes/workflow/muse/four-zero-hosting-validation.md`.

Actual iPad Apple authentication, return to gameplay, guest linking and restart/resume are still unverified. Android Apple browser authentication is likewise unverified. Optional Play Games remains unconfigured. Preserve these distinctions.

## Do

- Update the setup-status introduction in `notes/release/player-identity-setup.md` to separate the historical no-provider baseline from current completed Apple server/provisioning setup.
- Link to the current director release/evidence record and explicitly distinguish provider preflight and signed entitlement checks from genuine native authentication completion.
- Clarify that the unchecked readiness list at the end is a device-check contract, not a live list claiming all previously built artifacts remain untested. Preserve every device-case requirement and leave unperformed native checks unclaimed.
- Explain the Android aggregate NOT READY result accurately: only optional Play Games is missing while ordinary Google and Apple readiness checks pass.

## Do not

- Touch any file outside `notes/release/player-identity-setup.md`.
- Change game code, native bridge code, build scripts, public sites, asset files, credentials, version values, tests, guard rules or Git history.
- Include credential values, private paths, account identifiers or provider key material.
- Claim Apple native sign-in, account recovery, cancellation, deletion, purchase or restore tests passed.
- Remove the existing official setup steps or pinned dependency/version evidence.

## Acceptance

- The sole changed deliverable is `notes/release/player-identity-setup.md`.
- No current-status prose says Android Apple Service ID/key setup is pending.
- Current Apple readiness and completed server/signed-capability configuration are documented separately from still-unverified native authentication.
- Optional Play Games is identified as the sole missing Android aggregate-readiness input; Google/Apple remain independently ready.
- All existing device-check requirements remain intact, and no unchecked native test is promoted to a passed test.
- `node .github/scripts/check-hygiene.mjs` passes in the implementer's copy.

## How the director will judge

Read the full diff against the current source and the saved director observations, compare all checklist entries and version pins before/after, run repository hygiene, and confirm no protected or runtime path changed.
