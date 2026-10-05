# Brief 194: Report the measured painted hero height

## The ask
“캐릭터 일관성이 젤 중요해 크기 이런거 항상 잘 확인해”
Keep the published dimensions tied to the actual standing artwork.

## Where things stand
Brief 193 corrected torso-only breathing and is accepted. The director measured all 192 current idle/walk cells at alpha >= 32: opaque source heights range from 107 to 109 pixels; every hero resource uses visual_scale 0.255, giving 27.285–27.795 world pixels. Player applies that scale directly, without a parent body multiplier. The manifest's nearby legacy statement “A hero is about 36 world px tall” is inaccurate for the current painted sheets. This is a documentation-only defect, not a character-size change. Current native and store validation remain director operations.

## Do
Change only that short asset-manifest height description to approximately 28 world pixels, clearly the opaque painted body at the existing scale. Keep cell dimensions, scaling behavior and all neighboring claims intact. Add a brief historical correction record to notes/plans/4-0-0-build-log.md with the measured 107–109 source pixels and scale 0.255. Verify those values yourself from current resources and sheets.

## Do not
No game, generator, test, art, threshold, version, configuration, gallery or provenance change. No network, devices, credentials or git operations. Do not claim native E2E, PR, merge, uploads or review submission completed. Do not normalize or resize any character.

## Acceptance
Exactly two files change: apps/docs/docs/assets/manifest.md and notes/plans/4-0-0-build-log.md. The published height matches the actual alpha-bound measurements and Player scale. git diff --check, manifest/hygiene and docs build pass.

## Deliverables
The two narrowly corrected documents and an accurate report.

## How the director will judge
Read the complete diff, independently remeasure the figures and run the real-tree docs/manifest/hygiene checks. Native artifacts must remain byte-identical.
