# Brief 062: Keep native build products out of the source patch

## Director evidence
The new large-archive verifier fixes the confirmed overflow. However the harvested patch now adds the director-built Android Debug/Release AARs, a 56 MB iOS archive, all nine staged Firebase frameworks including their compiled binaries, generated Swift modules/headers, and six built privacy bundles: 163 changed files instead of the intended source files. These are products of the reproducible build/dependency pipeline, not deliverables authored in the brief. They must remain available locally for tests/exports without being checked in or copied into later implementer briefs as source.

## Do and scope
Add narrow ignore rules for this addon’s generated Android AARs and its generated `bin/` tree. Remove these generated entries from the candidate index/patch while retaining their on-disk bytes; never delete the director's verified artifacts. Keep every source template, SDK pin, original SDK-resource discovery/staging/export behavior, tests and documentation. Place ignores inside the new addon if practical. Confirm the final patch contains only source and intended notes, and future Debug/Release builds remain ignored. Do not touch existing vendored IAP outputs or their policy, global guides/guards, project/presets, gameplay/UI/cloud/art/secrets/network/device/store/git history.

The director is independently testing a disposable full-game iOS export with both plugins; a separate concrete correction will follow only if that measured export fails. This task is patch hygiene, not a reason to rework native source.
