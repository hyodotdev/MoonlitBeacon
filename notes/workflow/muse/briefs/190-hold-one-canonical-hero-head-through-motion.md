# Brief 190: Hold one canonical hero head through motion

## The ask and decision
“캐릭터 일관성이 젤 중요해 크기 이런거 항상 잘 확인해 이것때문에 계속 배포를 못하고 취소하고 하자나”
The director is returning the current standing work as round three in the same copy. Keep the useful neutral-standing repair; finish identity without weakening accepted attacks. The director deliberately stopped round two before accepting it, based on the measurements below, not a permission refusal.

## Confirmed remaining defects
The newly baked 192 idle/walk cells were compared at fixed coordinates with full RGBA, counting only visible pixels. All 24 idle columns now share their own walk frame-0 head band, but **zero of the 24 walk columns keep that head across all four frames**. A shared `_fit_box` scale does not register the heads or remove differences between painted faces. Examples, alpha >= 64 above the existing neck cut:

- Knight up: head boxes `(44,84,86,120)`, `(49,82,92,120)`, `(46,81,91,120)`, `(47,82,91,120)`. The head translates five pixels and changes width.
- Keeper down: `(36,84,104,128)`, `(37,83,107,128)`, `(36,83,109,128)`, `(37,80,108,128)`. Width grows from 68 to 73 and the top moves four pixels.
- Warden down: frame 0 `(45,84,104,130)` versus frame 1 `(43,83,102,130)`; 2,094 visible head-band pixels differ. The change is not only transparent padding.

The current diff also lowers `SHOT_SLIDE_KNIGHT` from 7 to 5 and changes the motion test's expected 7 to 5. Brief 186 explicitly requires existing physical-motion checks without loosening thresholds. Restore the original recoil and its test. Recalibrate the painted arm joints/donor cuts or solve their reach correctly instead of weakening the accepted cannon motion.

## Finish the same character
- Establish a real canonical head/face per hero and facing through **all** four walk frames, all idle frames and the attack torso. Keep the skull, eyes, facial dimensions and baseline fixed. Register the central upper-body anchor too. Hair/cape, arms and alternating legs may move; do not stretch, smear or replace the face, freeze walking, or simply copy the whole idle body over the walk.
- Canonical head paint from walk frame 0 is already shared with idle in this copy. Use that useful result consistently in the deterministic packer, with clean neck/shoulder joins. Check front/back as well as side donors. Preserve the newly supported, relaxed neutral legs in all 24 idle facings and the actual near/far leg depth.
- Keep the forecourt's shared idle/walk bounds and transform. Refresh measured tables after the final bake, preserving grounding, head dimensions and weapon seating on arrival/departure. Re-bake and recalibrate attack rigs, preserving independent Dancer hands, first-target-turn fractional gait, Eclipse orbit suppression, original cut angles and **4/7/2.5 recoil**.
- Add meaningful coverage to already registered suites: final rendered head/anchor regions in every frame and state, front/back supported standing geometry, side neutral stance and actual forecourt/Player transitions. Restore the original motion thresholds. Negative controls must catch a mismatched/growing walk head, the old idle head, old front/back passing legs and old side split stance.
- Supply a timed real-Godot QA scene/movie showing repeated walk → stop → primary attack → recovery → walk for all six heroes and four facings, plus actual forecourt stops. It must be large enough to inspect face and feet at consecutive 60fps frames. Reuse/extend the existing attack and forecourt harnesses if helpful; do not call a static PNG contact sheet a moving-render proof.

## Acceptance and boundaries
One stable head identity, dimensions and baseline across all 192 production cells and all 24 attack-facing transitions; every idle stands naturally. Deterministic hero/rig `--check`, related registered suites and unchanged 1,200-node late-arena budget pass. All original motion assertions remain meaningful. Return exact harness commands, measurements and negative-control results, accurate public docs and the build-log entry. A report is not visual approval.

Do not touch title music, the already accepted unboosted inspection boot/launcher/clean-UI suite, the regression runner, login/save/IAP, versions, terrain/world art, stores, marketing/IAP PNGs or provenance. No device/network/git operations. No acceptance yet. This is the third round for this defect; report any genuine blocker or unavailable painted source rather than disguising an incomplete identity repair as success.
