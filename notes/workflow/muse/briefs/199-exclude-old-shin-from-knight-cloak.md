# Brief 199: Exclude old shin paint from the Knight cloak

## Confirmed findings in the brief197 candidate
The director compared the original contact, previous standing and current standing at the same full-body crop (cell x0..144, y72..192, 4x nearest). The useful three-hero face correction is retained. The cloak tear has closed, but the current Knight side idle now keeps a diagonal gray segment of the original rear shin hanging below the blue/gold garment, between the new planted legs and the cloak tip. This is visible in all three full-body comparisons; the original walk donor proves that segment was leg paint, not trailing cloth. Inspect the current idle left around cell x78..100, y158..180 against original walk row0. The staircase `HERO_STANCE_KEEP` currently preserves some of that leg paint as garment.

The director also tested `_cloak_bands_match`: setting alpha to zero on all330 currently opaque kept pixels in left idle row0, while preserving their RGB, still returns true. The check only reads RGB drift. Thus the check can approve completely transparent cloth. This is a confirmed negative-control failure, independent of cosmetic judgment.

Two read-only director evidence artifacts are already copied into this run at `builds/verify/director-199/`: `hero-facing-cloak-current-contact.png` (original contact / previous standing / current standing) and `hero-facing-cloak-alpha-negative.json`. Inspect the image before editing. Claims about exact donor bytes must match the actual tolerance used by the guard.

## One correction
Keep the connected blue/gold cloak, exact approved heads, neutral planted feet and current gait. Separate the actual cloak paint from the old articulated rear shin before keeping it static. Remove the stale shin remnant through the deterministic segmentation, not by removing the cloak tip or making a broad eraser patch over the new legs. Mirror the same correction and retain every other hero byte-exact. Tighten the focused continuity guard so removed opaque cloak interiors fail, including when their hidden RGB remains unchanged.

## Acceptance
- All four Knight left idle frames and mirrored right frames have one continuous attached cloak, two supported neutral legs and no extra gray rear-shin fragment below the cloth. Full-body crops must show the donor and final idle at equal scale.
- The original slit with the corrected head fails the registered continuity regression. A separate transparent-interior control preserving RGB also fails. All current approved frames pass. Do not relax existing face, head, gait, standing or rig guards.
- Related generator/rig, head, standing, attack and forecourt checks pass. No edits to master sources, other heroes, versions, gameplay, saves/auth, store gallery or network/git work. Re-bake only intentionally affected outputs and re-pin only their existing asset contracts.
- Report garment preservation and old-leg exclusion separately. The director will run final full verify, native renders and store work; do not repeat unrelated auth/IAP suites or try sandbox/environment workarounds.

## Deliverables
The deterministic generator correction, focused registered negatives, affected Knight idle/derived production assets if needed, legitimate contract re-pins, and an exact changed-file report. Preserve the face-proportion work from brief196.
