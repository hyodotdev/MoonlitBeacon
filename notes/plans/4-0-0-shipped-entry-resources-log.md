# 4.0.0 shipped entry resources log — gate translations and identity config

## Round 092 — shipped Gate translations and identity public config

Assignment 20261003-0517-exported-gate-localization-and-config, round 1.
The director's ordinary 4.0.0 APK showed raw `gate.*` keys on the Pixel_10
emulator while desktop resolved Korean: `GateEntryStrings` parsed the
source CSV through FileAccess, and the source CSV never ships. Same round
also wires the staged `res://moonlit_identity.cfg` into the export.

### What changed

- `scripts/ui/gate_entry_strings.gd`: the loader now reads the imported
  `gate_entry.{locale}.translation` resources instead of the CSV. The
  engine auto-loads the registered tables at startup; `ensure_loaded()`
  stays idempotent, builds the English fallback from the English
  resource's own message list, and adds its copies to the
  TranslationServer only when a saved-locale probe finds a locale the
  server does not resolve yet. `text()`, `key_count()`, `is_loaded()` and
  all 77 translated strings are unchanged.
- `project.godot`: `locale/translations` gains the five gate resources
  (the only line touched; the ten locked values are exact).
- `localization/gate_entry.csv.import`: `compress=false`. Compressed
  translations answer `get_message_list()` with nothing, which is what
  the loader, the locale check, and the new suite enumerate. Five files,
  ~6KB each.
- `tests/test_gate_entry_exported_locales.gd` (new, registered in
  `run_regression_tests.mjs`): loads the five resources, proves the key
  sets match, and proves all 77 keys resolve in all five locales through
  both `tr()` and `GateEntryStrings.text()`. Never opens the CSV.
- `tools/check_locale.gd`: new `_check_gate_table()` enumerates the
  shipped English resource and fails on any key unresolved in any
  locale, plus loader-count parity.
- `scripts/lib/gate-locale.test.mjs` (new, `pnpm test:gate-locale`, in
  the `verify` chain): gate CSV shape (columns, cells, key shape, no
  commas/empties/dupes), every `gate.*` literal used in code/scenes
  exists in the table, `project.godot` registration, uncompressed
  import, and loader + new suite never touch the CSV or FileAccess.
- `addons/moonlit-identity/moonlit_identity_plugin.gd`: `_export_begin`
  now calls `_export_identity_config()`, which stages
  `res://moonlit_identity.cfg` via `add_file` when the wrapper
  installed it and skips silently otherwise. Presence-only reporting is
  unchanged; values never print. (The add_file wiring was missing: only
  the iOS descriptor and extension list used it.)
- `scripts/lib/identity-export.test.mjs`: three export-contract
  regressions — the plugin stages the config from a `_export_begin`
  -reachable method guarded by `file_exists` and read as bytes; no
  config-touching method prints or stringifies values; the staged path
  agrees across installer, exporter, and runtime.

### What bit me

- `TranslationServer.translate(key, locale)` does not take a locale:
  the second parameter is a message context, so it returns the key even
  when the table is loaded. The first probe read that as "auto-load
  failed". A one-arg `tr()` probe before any loader call proved the
  engine does auto-load registered translations (also in `--script`
  mode). The skip probe therefore flips through the five locales with
  save/restore instead.
- The copy had `gate_entry.csv` + `.import` but no imported outputs:
  nothing had run an import since the table landed. `--import` generated
  all five; the `.import` itself was sound.
- `pnpm test:game` cannot pass in the implementer sandbox: the reimport
  gate fails on macOS CA-cert and editor-settings HOME-write ERRORs
  (round 085 saw the same on the untouched baseline). Every suite was
  run individually through the isolated runner instead and judged by
  its own verdict line; see the round report.
