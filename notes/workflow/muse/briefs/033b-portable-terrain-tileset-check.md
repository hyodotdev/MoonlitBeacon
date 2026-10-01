# Brief 033b: cover the second confirmed terrain encoder boundary

## Amendment to brief 033
Keep the accepted intent and all constraints of brief 033. The director
independently ran the asset checks that CI did not reach after its first
failure. `build_terrain_tilesets.py --check` has the identical byte-comparison
defect in `frost_nature.png`, `marsh_nature.png` and `ruins_nature.png`.

Linux x86_64, Python 3.12.14 / Pillow 12.3.0 / zlib 1.3.1: all three
PNG encodings differ, while every decoded RGBA pixel and the dimensions
match the stored images exactly. All alpha comparisons also have zero
differences. Six terrain PNGs total now have this confirmed boundary.
The remaining generators pass Linux, including UI-kit styles when their
required resource directory is present. Do not change those generators.

## Do
Apply the same strict decoded-artwork comparison to this second generator.
Keep palette recoloring, output write behavior, source drawings, and every
committed asset byte unchanged. Share a small validation helper between the
two generators if that is clearer than duplicating format/integrity rules;
keep the helper specific and do not refactor other tools.

Extend the focused tests to exercise both actual generators' check paths,
including alternative compression success and pixel/alpha/format/dimension/
missing/corrupt failures from brief 033. Real CLI success/failure matters;
testing a helper alone does not prove the generators call it. Register tests
once in `check:assets`. Preserve every other asset check.
Include complete-PNG CRC corruption and trailing-byte cases so integrity
coverage is not limited to a visibly truncated file.

Run the narrow registered tests and `pnpm check:assets`; the director will
independently perform Linux checks, negative controls, hash comparison and
the real-tree full verification. All scratch output stays inside your copy.
Run checks directly with their genuine exit status. Redirect a verbose log
to an ignored file inside the copy, then inspect it separately; do not pipe
the check to `tail` or replace its exit with an echoed `PIPESTATUS` value.
The first round's full-game import was blocked by the sandbox; its changed-
HOME retry then made Corepack try the network and failed. Stop that path.
Do not retry blocked commands by changing HOME, package-manager paths,
sandbox or approvals. No full-game run is needed for this tools-only patch
inside your copy; the director runs full verification on the actual tree.
No runtime, artwork, store proof, build number, protected path, network,
package install, Docker or device actions are added to scope.
