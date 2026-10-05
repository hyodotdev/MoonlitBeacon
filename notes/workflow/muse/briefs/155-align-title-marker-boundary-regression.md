# Brief 155: Align the host boundary test with the repaired marker

## The ask and confirmed failure
"/loop-review돌리고 메인 다 클린한상태로 둔 다음 할까"
The root final pnpm verify fails at scripts/lib/capture-run-state.test.mjs test 63, "title ready is judged by live UI runtime proof, not PNG size", with "must confirm live title UI and version after four game-loop frames". The recently accepted TestLauncher marker is proven by 45 scene checks (old production resolution fails 9 cases), but this Node boundary test still expects screen/version checks inline after the frame loop and the old inequality spelling. Those checks moved to is_clean_title_boot() and use version equality; the writer now calls that predicate after the same four-frame guard, before writing the marker. The behavior remains strict, but the static test contract is stale.

## Do
Repair only the stale host-side assertion to reflect the new real control flow: four-frame wait with tree lifetime checks, followed by the clean-title predicate, then file write. Also retain explicit assertions that the predicate validates real title-root resolution, visible screen, current version, debug boundary and production occlusion rejection. Keep all host foreground/PNG-dimension/no-byte-size requirements. The registered 45-case real scene test is the behavioral evidence; do not replace it with weaker text matching or remove it.

## Do not
No TestLauncher/game/scene/asset/native/auth/IAP/save/capture-producer/website/config/version change. Do not remove a guard assertion just to get green. No actual device/export/network/git operations.

## Acceptance
The failing Node suite (test:android-build, including capture-run-state) passes, with no other test changes. Deliberately replace the writer's post-wait clean-title predicate guard with an unconditional branch in the copy: the updated assertion must fail, then restore exact bytes. Director reads the changed test and runs that boundary plus the existing 45-case marker test on the accepted tree, then full verify.

## Deliverables
Only scripts/lib/capture-run-state.test.mjs changes needed for the current writer/helper contract. Report the measured pass/fail counts and explicitly leave actual phone capture to the director.
