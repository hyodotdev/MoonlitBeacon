# Brief 195: preserve painted grades across CPU architectures

## The ask
The user said "loop-review해서 메인 머지하고 배포해야지" and
"빨리 다하고 리뷰 심사해줘 아까 취소한거 재개해야지". Make the actual
renewal PR pass Linux validation without changing the approved game art.

## Confirmed defect
PR 11 head passes all 80 game regressions on Mac and Linux. Docs, repo rules
and Android APK/AAB CI pass. Linux CI run 37291603423 then fails the fresh
painted-world comparison for only `marsh_glow.png`, `_windup`, `_charge`,
and `_recover` in `apps/game/assets/custom/actors/guardians/`.

The director independently baked all 44 guardian sheets in a read-only,
offline Linux x86_64 container using Python 3.12.14 / Pillow 12.3.0. Those
four sheets have 88, 79, 67 and 30 differing RGBA channels, respectively,
with maximum differences 2, 2, 2 and 1. The other 40 match exactly. Both
Mac Python 3.9.6 / Pillow 11.3.0 and Mac Python 3.12.14 / Pillow 12.3.0
match all 44. Changing the Pillow version alone does not explain this.

A synthetic native Pillow blend with factor 1.22 over all 65,536 byte-value
pairs matches fused binary32 multiply-add on Mac exactly. Linux native
matches separate binary32 multiply and add exactly. The two differ at 179
pairs. For example `(a,b)=(63,13)` gives 1 fused and 2 separate. Pillow's
official `src/libImaging/Blend.c` uses `a + alpha * (b - a)` with float
alpha; `ImageEnhance` delegates to this blend. `_grade` uses Color,
Brightness and Contrast on the variant figure. This is real decoded-pixel
arithmetic variation, not PNG compression variation.

## Do
- Make variant grading deterministic across the two arithmetic paths while
  preserving every currently committed PNG byte. Keep the approved Mac
  grading pixels exactly. Investigate which enhancement steps actually need
  a stable blend; prefer a small explicit, portable rounding contract over
  compiler flags or dependency pinning. The director's fused model rounds
  the factor to binary32, computes the exact product-plus-integer using
  Python double, then rounds once to binary32 before clamping/truncating.
- Preserve dimensions, alpha, geometry, gait, heads, material curves and
  all exact RGBA freshness checks. No tolerance, exception list, skipped
  variant, platform-conditional bypass or replacement of production art.
- Add focused regressions to the normal asset-check path. They must catch
  an accidental return to native/separately rounded blending on Linux,
  cover the measured boundary cases and real variant bake, and retain
  strict rejection of an altered RGBA channel. The director will restore
  a native blend in your copy as a negative control and then restore your
  final source exactly.

## Scope and constraints
Only the painted-world generator, a focused registered regression file and
its package-script registration if needed. Every asset, source master,
runtime GDScript, scene, resource, store image/proof, version/build counter,
CI workflow and protected file stays untouched. No network, containers,
package installation, native-device operation or sandbox change in your
copy. All scratch measurements stay in ignored output. Do not run a bake
that overwrites the production PNGs. No broad generator refactor.

## Acceptance and judgment
- All existing Mac generator/asset checks still pass; all 89 painted-world
  outputs match their committed RGBA pixels exactly. All 44 guardian
  outputs also match on Linux x86_64. The director performs Linux checks.
- Focused tests pass and fail on the deliberately restored native or
  separately rounded path, then pass after exact restoration. Existing
  canonical-head, stance and exact asset validation stays enforced.
- Source/input/asset/store PNG hashes are unchanged. The director will
  compare the diff, independently run the focused and full asset checks,
  and re-run final verification and actual PR CI before acceptance/merge.
- Report which enhancement step caused the measured difference and how
  the solution preserves the approved pixels. Do not claim Linux or
  native checks that you could not run in your isolated copy.
