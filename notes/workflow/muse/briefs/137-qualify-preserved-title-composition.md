# Brief 137: qualify preserved title composition

## The ask
"/loop-review돌리고 메인 다 클린한상태로 둔 다음 할까"
Keep the public description precise before the final clean rounds.

## Where things stand
The documentation in `apps/docs/docs/game.md`, opening of the 4.0.0 moon-gate subsection, says the original title's diorama and doors are "exactly as they shipped". Its composition and small-door layout are preserved, but its forest atlas now uses the new painted runtime sheets and the six-hero moving forecourt is new. The current asset manifest and the measured title-atlas/forecourt checks establish that the pixels are not exactly the shipped 3.0.0 art. The Hall door also now routes to the owned Hall.

## Do
Correct only the first two sentences of that subsection: describe the preserved original title composition and small-door layout, alongside the updated painted art and moving six-hero forecourt. Remove the absolute unchanged-art implication. Keep the durable-ID, tap-first, account/checking/error and provider paragraphs unchanged.

## Do not
Change other prose, assets, runtime, versions, dependencies, commands or any other file. Do not imply that all original menu behavior is unchanged; current Hall routing is already described below.

## Acceptance
One small prose hunk in `apps/docs/docs/game.md` only; preserved layout and changed art are both accurate from current source. The director reads the exact diff and runs the normal docs build/anchor checks after acceptance.
