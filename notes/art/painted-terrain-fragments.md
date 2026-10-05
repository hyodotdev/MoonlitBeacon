# Painted-terrain neighbour fragments (brief 093, integrated by brief 103)

Author-only follow-up. The director saw little blue foliage rectangles
beside repeated pines: confirmed in the shipped bytes, where
`forest_props.png` kept a detached deciduous-tree fragment left of its
pine cell and `nature.png` repeated it in the pine's scatter rects.

Kept as a distinct note (not the shared build log) because the current
tree's shared log already ends with a separate accepted author note;
brief 103 integrated the brief-093 packet's packer, 9 terrain PNGs,
two colour contracts and focused checker unchanged.

## The bug

Two prop figures touch across a master gridline, and the contact split in
`pack_painted_world._exact_cells` gives each side its own half — but a
neighbour's crown lobe reaching more than 14px past the line grows a core
on the wrong side, so the split strands it there as a detached blob. The
old fragment pass only erased such blobs under 3% of the cell's ink, and
these four lobes hold 4.4-11%: forest prop1 (2284px), camp prop1
(2796px), frost prop3 (1227px), ruins prop3 (1615px). A full scan of all
24 prop cells showed these are the only non-main blobs above 25px, each
touching its left gridline with master ink directly across labelled to
the left neighbour — no other side or row has the pattern.

## The fix

- `_erase_severed_neighbours` (prop path only, behind `edge_strips`):
  a non-main blob that touches a gridline with a neighbour beyond, whose
  master ink component belongs to another cell by mass, is erased. The
  figure itself, interior floaters and the figure's own crossings are
  exempt by construction, not by size. Spirits, guardians and heroes take
  the same `_exact_cells` without `edge_strips` and rebake byte-identical.
- Re-baked 9 terrain sheets through the deterministic packer; the other
  80 bake outputs are pixel-identical, and the masters are byte-identical.
- `_check_prop_intrusions` in the packer's structural checks: any terrain
  cell whose figure keeps a detached blob fully beside it (x-ranges
  disjoint, 2%+ of cell ink) fails. It reads committed sheets only, so it
  runs with the masters absent. `test_painted_world_checks.py` (new, in
  `check:assets`) pins the guard, the exact original lobes via
  `sever_split=False`, and synthetic pass/fail geometry.

## What bit

- The refit resamples the same paint at a new scale, so `camp.png` and
  `camp_props.png` legitimately gained interpolated RGB triples
  (33295 to 34321, 38347 to 38507). The contract caps are exact
  recordings of shipped art, so they were updated to the new measured
  values after review — the check did its job by flagging the intended
  change.
- `pnpm test:game` cannot pass in the sandboxed copy: the reimport steps
  run with the real HOME and the sandbox blocks the editor-settings save,
  and every engine start logs the macOS `get_system_ca_certificates`
  error, which the runner counts. The full isolated-step list was run
  with only that environmental line filtered instead; see the report.
