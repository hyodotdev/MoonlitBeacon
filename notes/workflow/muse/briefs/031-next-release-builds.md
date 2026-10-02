# Brief 031: prepare the next 3.0.0 store build numbers

## The ask
The user explicitly requested new submissions to both stores, including screenshots, then “했어 다 해줘”.
The director is correcting a confirmed game CI defect before that submission.

## Where things stand
The prior 3.0.0 binaries were already uploaded to Play internal as code 15 and TestFlight as build 10. Store upload identifiers cannot be reused for a newly corrected binary.
`apps/game/export_presets.cfg` has two Android `version/code=15` entries and one iOS `application/version="10"`; both display versions are already 3.0.0.

## Do
- As this specific release configuration task, change exactly the two Android version/code values to 16 and the iOS application/version string to 11.
- Preserve Android version/name and iOS application/short_version as 3.0.0.
- Check that the diff contains only those three lines, the locked package and all other export values stay identical, and `pnpm check:hygiene` passes.

## Do not
- Change display version, app identity, engine/renderer, resources, code, presets besides the three named values, credentials, signing, git or remote stores.
- Make any other protected-file change.

## Authorization and protected-file handling
Version values remain locked for ordinary implementation tasks. This brief explicitly names the necessary next upload identifiers for the user's authorized release. If your standing orders prevent even this specific configuration task, report that and leave the file unchanged; do not work around the refusal. The director will read the exact three-line diff and, if appropriate, use the existing `muse accept --allow apps/game/export_presets.cfg` path. The director does not weaken the protection policy.

## Acceptance and deliverables
Only `apps/game/export_presets.cfg` changes, exactly three lines: Android 16 twice, iOS 11 once. All 3.0.0 display versions and other bytes remain intact. Include the hygiene result and any protected-file limitation in the implementer report.
