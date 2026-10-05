# Brief 193: Describe torso-only idle breathing accurately

## The ask
“캐릭터 일관성이 젤 중요해 크기 이런거 항상 잘 확인해”
Keep the published asset description aligned with the accepted identity repair.

## Where things stand
The standing repair is accepted and the complete current-root verification passed. Final native checks and deployment are director operations still in progress. In apps/docs/docs/assets/manifest.md the hero paragraph still says “the idle stands on both feet and breathes feet-planted about the soles.” The generator's _idle_breath changes only the torso band vertically about the hips; the canonical head and below-hips feet bytes never change. The older about-the-soles description suggests the removed whole-body scaling mechanism.

## Do
Correct that short published sentence to describe torso-only breathing with fixed head and planted feet. Keep all neighboring dimensions, denominators, attribution, assets and paths intact. Add a brief historical record in notes/plans/4-0-0-build-log.md referring to the director validation journal for current release status.

## Do not
No code, generators, tests, assets, thresholds, versions, configuration, gallery or provenance changes. No network, devices, credentials or git operations. Do not claim native E2E, PR, merge, uploads or review submission completed. This is a distinct documentation correction, not another standing-art round.

## Acceptance
Exactly two files change: the published asset manifest and the 4.0.0 build log. The prose states the actual torso-only mechanism; no claim of whole-body scaling about the soles remains in the hero paragraph. No other prose rewrite. git diff --check passes.

## Deliverables
apps/docs/docs/assets/manifest.md, notes/plans/4-0-0-build-log.md, and an accurate report.

## How the director will judge
Read the complete diff and compare the sentence to the accepted generator. Run the docs build and manifest/hygiene checks in the real tree after acceptance.
