# Brief 185: Correct the painted fang documentation

## The ask
“캐릭터 다 점검해주면 좋겠다”
The public asset description must agree with the accepted independent hands.

## Confirmed defect
`apps/docs/docs/assets/manifest.md` describes the new attack rig and correctly says both Dancer fangs sit in independent hands. Its preceding painted-weapon paragraph still says the atlas holds both daggers straddling one hand point. The director read this contradiction in the real working tree. This paragraph should distinguish the existing atlas source from the current runtime seating.

## Do
Replace only the obsolete one-hand statement with concise accurate prose: the existing Dancer sheet supplies two fangs and the runtime seats each fang on its own grip in its own articulated hand. Preserve the fact that original weapon atlas inputs are unchanged.

## Do not
Change game files, tests, assets, versions, generator inputs, release machinery, or other documentation. Keep the accepted title-music correction from the preceding brief intact if continuing that copy.

## Acceptance and deliverable
Only `apps/docs/docs/assets/manifest.md` changes for this correction. The surrounding weapon description contains no one-hand claim, agrees with the accepted runtime, and `pnpm docs:build` passes. The director will independently read the diff and rebuild combined hosting output.
