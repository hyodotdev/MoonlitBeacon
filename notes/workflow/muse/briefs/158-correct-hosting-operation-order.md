# Brief 158: Correct the hosting operation order

## Confirmed findings in brief 157
The new README and publication-note header put the refused combined attempt before the first care-only release. Actual director evidence has the first care-only release at 19:11 UTC, live verified at 19:14 UTC; the later combined attempt was refused before upload, leaving that care-only release live; the successful combined release followed the fix. The deploy-section paragraph already correctly says the refusal left care-only live. Align the header and README with that actual order.
Also scope the sentence “the game is not submitted, approved, or live” explicitly to native version 4.0.0. Earlier game versions are already on the stores; do not imply the whole game has never shipped.

## Do and do not
Change only apps/player-care/README.md and notes/release/player-care-publication.md. Preserve all verified counts, proof filenames, commands/config/path/terms/source/security statements and attribution. No code, generated output, network or native operations. Use the corrected chronology: first care-only success → refused combined attempt leaves first release live → fixed combined 191-file success. Be concise.

## Acceptance
Both docs have one consistent factual chronology and the native 4.0.0 limitation is clear. No new tests; hygiene and director hunk inspection. This is a correction to the unaccepted task, not another deploy.
