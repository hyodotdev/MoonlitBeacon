# Brief 162: Correct the cloud-save privacy category

## The ask
The user asked to finish the 4.0.0 login/cloud-save release and manage its
public policy and store metadata accurately on moonlitbeacon.hyo.dev.

## Where things stand
The director read the source audit and Apple official definitions at
https://developer.apple.com/app-store/app-privacy-details/ . Product
Interaction explicitly includes saved place in a game. Gameplay Content
also explicitly includes saved games. Functional cloud checkpoints are
collected and retained, even though optional Firebase Analytics is absent
from the exported game. The current audit row 8 incorrectly concludes
that no Product Interaction label is needed solely because gameplay
analytics are off. This is a category omission, not an analytics toggle.

The director also accepted Brief 161's deletion-policy correction, built
and deployed it, and verified every hosted file. That audit's historical
wording concern now has a resolved source change; preserve its evidence.
Play draft selections include App Functionality and Account Management for
name, email and User IDs, and App Functionality for Other Actions; these
are saved for review. Apple types are being prepared, not yet published.

## Do
Edit only notes/release/privacy-four-zero-store-audit.md. Correct Apple
row 8 to Yes, linked, not tracking, App Functionality for retained cloud
checkpoint/place/progress data. Keep optional analytics-off facts, clearly
separate from functional collection. Cite the official Apple definitions
and precise existing source fields supporting the mapping. Retain Gameplay
Content. Update the deletion wording concern to resolved by Brief 161,
without claiming every deletion edge or native end-to-end test passed.
For Play name/email/User ID, clarify Account Management as well as App
Functionality where source and official Firebase purposes support it.
Keep the difference between proposals and director-observed drafts clear.

## Do not
Change game/capture/runtime files, published site content, scripts, tests,
credentials, store assets or unrelated docs. Do not use the network, touch
git history or claim store publication/review/native purchases completed.
Do not invent facts from hidden provider behavior or add speculative types.

## Acceptance
One document changed. Classification distinguishes automatic cloud saves
from analytics; row 8 no longer suppresses the functional data label.
Facts and recommendations remain source-cited. Existing hygiene check
passes. No new tests are needed for this evidence-only correction.

## Deliverable and judgment
The corrected audit and a report. The director will read the entire diff,
compare fields with the production upload path and the observed Apple UI,
and run hygiene independently before acceptance.
