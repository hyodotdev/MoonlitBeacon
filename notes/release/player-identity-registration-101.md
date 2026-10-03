# Player identity registration (brief 101) — author-only note

The ordinary game never reached the native bridge: `project.godot`
registered no `MoonlitIdentity` autoload and enabled only the godot-iap
editor plugin, so `/root/MoonlitIdentity` did not exist at runtime and the
MoonlitIdentity export plugin never ran on ordinary exports. This round
adds the smallest durable project registration and proves it with the
real boot. Companion to `player-identity-setup.md`; that file keeps the
provider checklist and build commands.

## What changed

- `apps/game/project.godot` (two lines, the only unlocked settings
  touched):
  - Autoload `MoonlitIdentity="*res://addons/moonlit-identity/moonlit_identity.gd"`,
    placed immediately before `ProductionHost`. Every existing autoload
    keeps its relative order; main scene, version, package name, and the
    ten locked display/input/rendering values are untouched.
  - Editor plugins enabled gains
    `"res://addons/moonlit-identity/plugin.cfg"` after the godot-iap
    entry. godot-iap stays enabled.
- `apps/game/addons/moonlit-identity/moonlit_identity_plugin.gd`:
  idempotent autoload lifecycle. `_enter_tree` adds the autoload only
  when `autoload/MoonlitIdentity` is absent and remembers that it did;
  `_exit_tree` removes only what that enable added, and only creates the
  export plugin once. An explicit project registration is never removed
  by disabling the addon or closing the editor. Export hooks are
  untouched, including the 092 config `add_file`.
- `apps/game/tests/test_identity_registration.gd` + `.tscn` (+ `.gd.uid`),
  registered in `apps/game/tools/run_regression_tests.mjs` after the
  player-identity entry. Scene-based, real boot, no injected doubles
  (see below).

Nothing else: no preset, SDK, wrapper, provider, rules, UI, title,
NightForest, IAP, vendor, version, renderer, or signing change.

## Startup ordering (exact)

Autoload `_ready` order is the `project.godot` order:
`GodotIapPlugin, Records, Settings, Analytics, Vault, Ladder,
GlobalLadder, Shop, MoonlitIdentity, ProductionHost`.
`MoonlitIdentity` sits immediately before `ProductionHost` so the bridge
node exists before any host work. The wrapper itself has no `_ready` or
`_init` side effects; native lookup (`Engine.has_singleton` on Android,
`ClassDB` on iOS) is lazy per call, so desktop/CI boots gain one inert
node.

Resolution timeline on the real path:

1. Autoloads ready (bridge present, host services built, host not
   started).
2. Main scene (`production_entry.tscn`) `_ready` calls `host.startup()`.
3. `startup` mints the durable ID, then `refresh_session` is the first
   adapter call that resolves `/root/MoonlitIdentity` and wires
   `request_completed`.
4. Every later adapter call reuses the wired bridge.

The new test pins each step: bridge present while the host is not
started, sibling order before/after boot, the real main booting the
real host, and the adapter holding the exact live bridge node.

## Lifecycle evidence (measured in-copy)

- Two editor `--import` round-trips with the fix: `project.godot` stays
  byte-identical (only the two intended lines differ from baseline).
- Control run with the old unconditional `remove_autoload_singleton`
  restored: `project.godot` also stayed identical, proving headless
  `--import`/`--quit` never persists project settings either way. The
  fix protects the interactive path instead: toggling the addon off in
  the editor UI saves `project.godot`, and that save would carry the
  stripped autoload under the old code.
- Editor log shows `[MoonlitIdentity] Plugin enabled` at boot and the
  matching disable line at shutdown, with no errors from absent native
  artifacts (there are no AARs, static libs, or staged config in the
  repo, by design).

## Export reachability

Enabling the editor plugin makes the export hooks run on every
ordinary Android and iOS export: config staging, Android AAR list /
remote dependencies / Play APP_ID manifest stamp, and the iOS static
entry, frameworks, privacy bundles, linker flags, URL-scheme plist,
descriptor, and composed extension list. No preset flag gates these
hooks — the direct-APK wrapper physically moves the godot-iap
descriptor aside precisely because `plugins/GodotIap=false` does not
stop that export plugin, and the iOS GDExtension side has no `.gdap`
mechanism at all.

Single-emission inventory (each artifact has exactly one emission
site; no new staging path was added):

- `moonlit_identity.cfg`: one `add_file` in `_export_begin`.
- Android AAR: one path per variant in `_get_android_libraries`,
  returned only when the file exists (missing artifacts warn and yield
  an empty list, so missing-native exports stay usable).
- Android remote deps: parsed once from `MoonlitIdentity.gdap`.
- Android manifest APP_ID: one stamp from the staged config.
- iOS static lib / frameworks / bundles / flags / plist / descriptor /
  extension list: one hook call each, all warn-and-skip when unstaged.

The `.gdap` + export-plugin coexistence mirrors the godot-iap layout
the Play presets already carry (`.gdap` plus an export plugin that
reads it for remote dependencies); this round adds no second channel
that could duplicate it.

## Preset opt-in (brief 105; one line, iOS only)

Under a one-line authorization, the iOS preset now carries
`plugins/MoonlitIdentity=true` immediately below `plugins/GodotIap=true`
in `[preset.1.options]` — the only preset edit, with every
version/build/package/signing value and both Android presets
byte-identical. This connects the existing `shouldStageAppleEntitlement`
gate: with the flag present, a legitimately configured Apple sign-in
grant can stage through the temporary preset hook, while any genuinely
incomplete Apple config still refuses (pinned by the identity-export
Node suite against the real preset bytes). No provider readiness flag
was set, no credential added, no grant staged unconditionally, and no
signing changed. There is no remaining missing preset: the 092 config
staging and all export hooks need no flag, and the entitlement gate's
flag requirement is satisfied on iOS.

Remaining engine-side read-off for the director's real export (not a
missing preset): the engine default for a `plugins/` key absent from a
preset could not be settled headless in the sandbox, since the Android
platform exposes no script-visible plugin-discovery API and export
templates/SDK are absent. The Android presets intentionally carry no
flag; the director reads the behavior off the APK:
  - If the APK contains the AAR's DEX classes and one APP_ID
    `meta-data` with no Android flag, the missing key defaults to
    enabled and nothing further is needed.
  - If the Kotlin singleton is absent (`Engine.has_singleton` false on
    device while the AAR ships), that is a new finding to bring back
    with the export log — do not hand-edit presets around it.
  - Suggested reads: `unzip -l` for `moonlit_identity.cfg` and the AAR
    marker, `aapt dump badging` / manifest dump for a single
    `com.google.android.gms.games.APP_ID` entry, and one DEX class
    listing for `dev/moonlitbeacon/identity`.

## Desktop/CI degradation (no fabricated readiness)

With no native singleton or GDExtension class, `get_capabilities`
answers `unsupported` naming `native_bridge_unavailable`, guests stay
local, no provider is listed, and no registration is attempted. The new
test proves this on the real host, plus a durable ID on disk and a
live unpaused Arena (real scene, hero processing, 30 frames, no host
errors). Native Google/Apple sign-in and global rank stay unready
until external credentials, providers, and rules are configured;
nothing here claims them.

## Checks run (finite focused set)

- New `test_identity_registration.tscn`: 61 cases green.
- `test_player_identity.gd`: 305 cases green, no assertion touched.
- `test_production_host.tscn`: 468 cases green, no assertion touched.
- `check_scripts` scene: 156 scripts compile.
- `check:hygiene`: green, 10 locked values intact.
- Mutation: autoload line removed → new suite fails 6/20 (bridge,
  adapter, main, removal, guest, entry plan); restored → 61 green.
  Lifecycle control run described above.
- `check:store-screenshots`: red as expected after touching
  `apps/game/` (proof files absent in this copy); no recapture.
- Full `test:game` deliberately not repeated: the brief scopes this
  round to finite focused checks, and the sandbox macOS keychain error
  pollutes every Godot run's log here.
