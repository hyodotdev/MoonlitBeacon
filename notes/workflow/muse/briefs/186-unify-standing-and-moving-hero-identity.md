# Brief 186: Unify standing and moving hero identity

## The ask
“그리고 캐릭터가 멈춰있을 땐 다리를 벌리고 있지말고 서있게 해줘 인트로 화면에서도 달리다 멈추는데 다리를 벌리고 있네 그리고 달릴떄랑 멈출때랑 캐릭터가 달라져... 얼굴이 기본적으로 커지네”
A stop must settle into a natural upright stance, with the same face, head proportions and outfit as the moving hero, both in the intro and combat.

## Confirmed starting point
The director inspected the committed Warden idle/walk PNGs and the real packer. `pack_painted_world.py:bake_heroes` uses turnaround row 0 as idle, but separate sidewalk donors for left/right walk. The idle profile is a spread-leg stepping pose with a visibly larger head than the side-walk donor. Idle also scales the whole figure through `HERO_IDLE_SCALES`; forecourt `_set_pose` refits the actor using state-specific opaque bounds. This compounds the identity/size pop at patrol stops. The accepted attack rig is cut from idle row 0 and overlays its torso while walking attacks, so inspect that handoff too; changing only the intro would leave the same mismatch in gameplay.

## Existing work and overlap boundaries
All six heroes now have accepted articulated painted arms, primary cuts/recoil, continuous fractional stride and a lazy-node repair keeping Knight late-arena peak at 1,198 against an unchanged 1,200 limit. A separate narrow title-music lifecycle repair is being judged. Do not edit `production_entry.gd`, the music regression or `tools/run_regression_tests.mjs` in this task. Reuse appropriate existing hero/forecourt/painted-generator test suites for registered coverage. Previous briefs forbidding idle/walk-sheet changes are superseded by this user's explicit request.

## Do
- Establish a single canonical painted head/upper-body identity per hero and facing, shared through idle, walk and attack presentation. Inspect all six heroes and all four facings. Keep genuine alternating side strides and the existing smooth premium art.
- Give every idle direction a believable upright resting lower body: both feet supported, legs relaxed together rather than a frozen contact pose. A passing walk frame with one lifted foot is not a standing pose. Derive the correction through the established deterministic packer from existing painted source parts when possible; do not merely shrink or narrow the whole idle figure.
- Keep facial dimensions and baseline stable at walk→stop→walk and attack→recovery. Do not use whole-body breathing rescale to enlarge the head. Preserve calm body/cloak breathing if it can be done without changing the face or planted feet.
- Keep intro actor grounding, sizing and weapon seating stable at patrol arrivals/departures. Refresh measured paint bounds honestly when art changes.
- Re-bake and recalibrate the physical attack rig if its canonical torso/arms change. Keep held-weapon grips attached, both Dancer hands independent, the scythe sweep and distinct gun recoil readable. Preserve damage, cadence, range, projectile counts and sidearms.
- Add regressions that actually see the changed rendered textures/regions and head/stance identity, plus transition checks for all 24 hero/facing combinations. Negative controls must catch the old mismatched idle profile and frozen spread stance. Keep existing gait, attack and node-budget checks meaningful.
- Provide a timed Godot QA harness/movie route demonstrating repeated move→stop→move transitions, close enough for the director to inspect face, legs, hands and ground contact. Include intro and actual Player attack transitions. Do not run a store capture pipeline.

## Do not
Change login/save/IAP, music, version counters, engine/renderer/resolution/filter locks, store galleries/provenance, or unrelated world art. No new nodes that break the unchanged 1,200-node late-arena limit. No generic silhouette, drawn placeholder legs, smeared/warped faces, erased feet, walk freeze, or tests weakened to bless the output. No network, device, store or git operations.

## Acceptance
- All 24 idle facing cells show supported neutral standing feet, not a contact/passing stride. The director will view the production PNGs at 4× and repeated actual Godot transitions in dense frame strips.
- A fixed view shows the same face/head size and position while walking, stopped, attacking and recovering; normal direction changes preserve the character's identity. Head scale jumps must be measured and eliminated, not hidden by camera zoom.
- Real alternating left/right stride and continuous walking attacks survive; all existing physical-motion and late-arena budgets pass without loosening thresholds.
- Deterministic world/hero bake and rig `--check` pass. Relevant hero, forecourt and attack regressions pass. Document which atlas/calibration values intentionally changed and why.
- Existing marketing and IAP PNG bytes remain unchanged; no recapture or provenance regeneration.

## Deliverables
Minimal source/generator/actor/forecourt changes needed for the above, regenerated production hero/rig art, meaningful coverage in existing registered suites, an internal QA harness if needed, accurate public asset/game documentation and a build-log entry. Keep raw sources in the existing author-only art tree and record runtime assets in the manifest. The director will judge source, production pixels, geometry, motion, negative controls and final native builds before accepting.
