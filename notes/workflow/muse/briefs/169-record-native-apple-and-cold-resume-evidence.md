# Brief 169: record native Apple and cold-resume evidence

## The ask
“애플로그인 문서화등 다 완벽한거지?”
“이어서 플레이가 잘 되는지 겜 종료하고 나서도 체크해줘야해”

Make the author-only setup note accurately reflect new real-device evidence,
including the still-pending physical iPad Continue action.

## Why, and what good feels like
The reader must distinguish completed native authentication, durable save
preservation and observed resumed gameplay. Configuration READY is not a
successful sign-in. A successful first-gate return is not every later cycle.

## Where things stand
Read `notes/workflow/muse/apple-auth-and-cold-resume-validation.md`, which is
sanitized director evidence. iPad native Apple auth, original local guest ID
retention and exact cloud/local checkpoint equality now pass. Full iPad process
termination and new launch preserve save bytes; user Continue tap and automatic
SDK hydration after that launch are still pending. Galaxy Z Flip5 Android
Google-linked game cold resume reaches real combat twice. Android Apple is
still pending. Accepted brief168 fixes iOS delete proceeding after revoke
failure; no real account deletion and no new store package containing it yet.
`notes/release/player-identity-setup.md` currently says all iPad Apple auth and
return to gameplay are unverified, which is now outdated.

## Do
- Update the completed/unverified paragraphs near the provider checklist in
  `notes/release/player-identity-setup.md`, linking the new director record.
- Explain local guest public-ID migration versus Firebase-anonymous UID linking;
  the latter is not proven by this device baseline.
- Record Android first-gate cold resume twice, iPad cold-launch bytes preserved
  with actual Continue still pending, and the gate-start save contract.
- Keep the 15 standing device-check boxes unchecked: each combines many cases,
  and neither a basic successful sheet nor automated tests passes a whole row.

## Do not
- Do not modify code, dependency pins, UI, versions, scopes, screenshots,
  the director record, or any other file.
- Do not turn partially verified cases into complete native coverage.
- Do not claim the new revoke fix is in submitted build12 or perform any
  provider/cloud/store operation. No real account was deleted.

## Acceptance
The diff only changes the setup note; its new live-status language agrees with
the director record, the historical standalone baseline remains historical,
all 15 device-check requirements remain, and hygiene passes.

## Deliverables
`notes/release/player-identity-setup.md` only.

## Constraints specific to this task
No raw IDs, provider credentials, personal details or local private paths.
Notes remain author-only and do not enter the public course/docs site.

## Settle these yourself
Use a compact status paragraph or table, whatever makes the separate evidence
scopes easiest to assess. No additional testing or code change is needed.

## How the director will judge
Read every changed hunk against the director record, count all unchecked
standing requirements, run repository hygiene and inspect the diff scope.
