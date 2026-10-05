# 4.0.0 account panel log

Author-only. Why the Account card missed the 360px landscape height
with production data, and what the Brief 118 pass changed: a pinned
header/footer shell with a bounded middle scroll, official
Google/Apple link doors from the accepted entry factory, and a real
two-line save detail.

## What changed

### The production card never fit

`gate_account_panel.gd` stacked every row — title, ID field, ID
accessories, hero, save title, save detail, metrics toggle, link
title, link row, sign-out/delete, footer — in one VBox. The base
recenter caps the card at `view.y - 16`, but a child's larger minimum
clamps the size back up, so the production local-guest shape (two
link doors plus sign-out and delete) centered a 422px card in a
360px viewport: the Account heading sat at y=-19 and the
Close/legal footer ran to y=379. The existing layout suite never saw
it: it opens Account without `link_providers`/`can_sign_out`/
`can_delete`.

### Pinned shell with a bounded scroll

The panel now keeps the title row and the Close footer pinned and
moves everything between them into one `ScrollContainer` (`Scroll` /
`ScrollBox`), sized in an overridden `_recenter_card`: short content
keeps its fitted height, overflowing content stops at the viewport
budget minus the pinned rows, and the rest stays reachable through
the scroll. Horizontal scroll is disabled, focus follows into view,
the scroll clips to its own rect inside the card, and the wrapped
labels subtract the live scrollbar gutter so the card keeps its
380px width with the bar showing. No touch target moved: actions
keep 44px, the two ID accessories keep their 36px exception.

### Official link doors, full width

`_rebuild_link_row` is now a vertical stack of full-width doors.
Google/Apple go through `GateProviderButtons.make_provider_button`
with the exact entry action keys (`gate.auth.signin.google`,
`gate.auth.signin.apple`); extra providers keep the game's own
buttons. Disabled still means unready-or-draining; no new strings.
The old side-by-side pair could never hold the factory's 64px title
reserves at card width, so the row direction is part of the brand
fix, not taste.

### The save detail painted 1px

`SavedDetail` combines `clip_text` with a two-line budget but never
reserved a height, so it rendered one pixel tall. It now reserves
its rendered line block from the live shaped count every recenter,
like the entry notes.

## Measurements (ko, production local-guest data)

- Before, 808x360: card `(214, -31, 380x422)`, title y=-19,
  Close row y=335..379, detail height 1px.
- After, 808x360: card `(214, 8, 380x344)`, header/footer inside,
  vbar showing, every control reachable by `ensure_control_visible`
  or focus. First-open, settled, and reopened geometries identical.
- After, 808x606: card `(214, 57, 380x491)`, vbar hidden, nothing
  scrolls that does not need to.

## Tests

- `test_gate_entry_layout.gd`: three production variants (ready
  guest, unready guest with a draining extra, linked cloud with no
  hero/save) at every framing and locale — generic tree checks with
  scrolled controls exempted from static rects, pinned card/header/
  footer fit, per-door brand faces plus the link pair, real scroll
  reachability of every button and the ID field at 44px (36px ID
  accessories), a two-line detail glyph check, and an armed
  delete/cancel round trip.
- `test_gate_entry_state.gd`: link doors as official factory faces
  with the entry's own action label, honest readiness, per-door link
  ids, game controls for extras; sign-out, two-step delete with
  cancel-before-delete, Close and back, reveal/copy, and the legal
  footer including `show_links=false`.
- Negative controls: baseline source fails the new layout checks
  (825 assertion failures: brand faces, card fit, missing scroll)
  and the new state checks (7 structural failures); reverting only
  the factory branch fails the state brand faces.

## What bit us

- A 480x360 "4:3" window does not lay out at 480 wide: with
  `canvas_items`+`expand` stretch the canvas is window/min-ratio, so
  it renders 808x606 — the same canvas every real 4:3 window shows.
  The suite's existing 808x606 framing already is the 4:3 coverage;
  a sub-base narrow loop tested a fiction and was removed.
- New scroll-path lookups initially used hard `get_node`: on
  reverted source the test functions aborted with engine errors and
  the scene run still reported "passed". Every new structural
  lookup is now `get_node_or_null` with an explicit failure, so
  reverts fail as assertions under direct runs and under the
  ERROR-failing regression runner alike.
- `ERROR: 2 resources still in use at exit` appeared once and never
  reproduced across reruns; the only steady suite noise is the
  pre-existing macOS keychain `get_system_ca_certificates` error,
  identical on baseline.
