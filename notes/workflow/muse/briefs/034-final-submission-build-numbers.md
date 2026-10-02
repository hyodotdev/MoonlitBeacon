# Brief 034: final submission build numbers

## The ask
“심사 제출해줘 최종본으로 다 빌드해서”

Build the final corrected 3.0.0 source for both stores and submit for review.
The director owns all build, signing, upload and store operations.

## Where things stand
The corrected source at 99a4da5 has passed the complete local verification
and four required GitHub checks. Android 3.0.0 (15) is already on the internal
track and iOS 3.0.0 (10) is already in TestFlight. Those binaries predate
the final circular melee correction, so their build numbers cannot be reused.
`apps/game/export_presets.cfg` currently has Android version/code=15 twice
and iOS application/version="10". Every display version is already 3.0.0.

## Do
- Change only the two Android version/code values from 15 to 16 and iOS
  application/version from "10" to "11" in export_presets.cfg.
- Read the diff and confirm all other bytes and the display versions are
  unchanged. Report that signing and store submissions were not performed.

## Authorization and constraints specific to this task
The user's latest explicit final-build submission request authorizes the
necessary unique build numbers for this exact release. This brief is the
narrow release exception described by `.claude/commands/release.md`: the
implementer changes version keys and the director reviews and accepts with
`--allow apps/game/export_presets.cfg`. It overrides the standing-order
version lock only for these three assignments; every other lock remains.
Do not edit guides, standing orders, guards, code, assets, tests or images.
Do not run builds, capture tools, network, git publication or device tools.

## Acceptance
Exactly one changed file and exactly three old/new assignment pairs.
Android presets both 3.0.0 (16); iOS 3.0.0 (11); package identity unchanged.
The director will independently inspect the patch and compare all bytes
after substituting the three old assignments back.

## Deliverables
Only `apps/game/export_presets.cfg` and the ignored IMPLEMENTER_REPORT.md.
