# Brief 033: validate terrain artwork across PNG encoders

## The ask
The user said “/loop-review 돌아서 확실하게 해줘 pr 만들어 이번에는 내가 승인”,
“스토어에 새로 다 제출도 해줘 스샷이랑”, and “했어 다 해줘”. Make the renewal
PR pass its actual Linux validation while preserving the approved artwork.

## Confirmed defect
The corrected PR head passed every game regression on Ubuntu, including the
404 hero-weapon assertions. CI then failed the `check:assets` step because
`pack_terrain_structures.py --check` byte-compares the Pillow PNG output with
the three committed later-terrain sheets.

The director reproduced this with the unchanged generator and its unchanged
twelve input drawings in Linux x86_64: Python 3.12.14, Pillow 12.3.0, Pillow
zlib 1.3.1. All three generated PNG byte hashes differ, but direct comparison
of all 65,536 decoded RGBA pixels per sheet found **zero differences**, including
alpha. Mac checks pass using Python 3.9.6 / Pillow 11.3.0 / zlib 1.2.12.
This is an encoding portability failure; changing or regenerating the art
would be unnecessary. Do not guess which dependency caused the byte change.

## Do
- Make this generator's check compare the complete decoded RGBA artwork and
  dimensions with its actual `_bake` result, while still rejecting missing,
  unreadable, corrupt, non-PNG, wrongly shaped or wrongly formatted outputs.
  Preserve the existing RGBA PNG and binary-alpha contract. Validate/decode
  the whole stored file rather than just a header or selected pixels.
- Keep bake, palette, resize, positioning and write behavior unchanged. Keep
  all twelve source drawings and all committed asset PNG bytes unchanged.
- Add focused regressions registered in the existing asset-check path. Show
  that a valid alternative PNG compression of identical RGBA pixels passes,
  and changes to one opaque RGB pixel, one alpha value, a transparent pixel's
  RGB value, dimensions, invalid/missing PNG or non-RGBA format fail. Report
  genuine failure exit codes. No substitute suite or test suppression.
- Keep the implementation small and specific to this proven defect. A
  comparison error should explain the affected sheet and return failure,
  rather than crashing without useful context.

## Scope
The terrain packer, focused tests, and their registration in `check:assets`
only. No changes to other generators/checks, CI, game runtime, art, store
screenshots/proofs, manifests, product IDs/prices, build/version numbers or
any protected paths. No network, Docker, package installation or machine
actions in your copy. The director will perform Linux validation separately.
All scratch files and measurement output must stay inside your copy, in an
ignored directory. Existing assertions and the rest of `check:assets` stay.

## Acceptance and judgment
- `pnpm check:assets` passes on the copy and on the real tree.
- Every focused regression passes. A negative control restoring the original
  byte comparison makes the alternative-compression regression fail, and a
  comparison that ignores an altered pixel must fail its regression. Restore
  the exact final source after each negative control.
- The director will independently run the packer and focused tests on Linux
  against the three existing committed sheets and inspect the actual diff.
- Hashes of all asset PNGs and terrain input drawings remain byte-identical.
  Do not edit store capture proofs or claim screenshot freshness was fixed.
