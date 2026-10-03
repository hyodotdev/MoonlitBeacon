# 4.0.0 build and verification integration log

Author log for briefs 076 (integration) and 087 (Apple entitlement hook
correction). ProductionHost, its focused tests, and the Hall rank fixture
are owned by parallel 088; Gate/legacy UI by the visual jobs. This log
covers the shared runners, export/build and capture-persistence helpers,
vendor provenance, and product-image updates only.

## Runner and package registration

- `apps/game/tools/run_regression_tests.mjs`: registered the 12 reviewed
  suites — five cloud service scripts, the coordinator scene, the
  production-host scene, three Gate entry/loading scenes, player identity,
  and painted weapons — next to their related rows. No existing row
  touched; every old assertion and painted-world row retained.
- `package.json` `check:assets`: added `pack_painted_weapons.py --check`
  after the painted-world check. `pack_maple_heroes.py` stays retired: its
  `--check` delegates to the painted-world check already registered.
- `package.json` `test:android-build`: added
  `player-identity-build.test.mjs` and the new `identity-export.test.mjs`.
  That command already runs in CI's game job, so the native build-helper
  suites are covered locally and in CI with no CI file edits and no new
  dependencies. 122 tests pass.

## Vendor provenance (GodotIAP 3.6.1 + composer hunk)

- The tree held exactly official 3.6.1 + the old patch + the reviewed
  `ExtensionListComposer` hunk. Proven by splicing the composer hunk out
  and reversing the old patch: both files hashed to the pinned official
  SHAs (`2bf54b…`, `31500d…`).
- Regenerated `vendor/godot-iap/0001-moonlit-integration.patch` as
  official→current, updated the patch SHA and the plugin moonlit SHA in
  `vendor/godot-iap/README.md` (plus the third "Patches kept" bullet) and
  in `scripts/lib/godot-iap-vendor.test.mjs`. Official 3.6.1 source and
  binary pins unchanged; the suite's reverse-to-official check passes.

## Native SDK import exclusion

- Root failure: with real SDK products staged, project reimport tried to
  import Apple-optimized `GoogleSignIn.bundle` images. Fix: `--build-ios`
  staging now writes a `.gdignore` (repo comment + `*` convention) next
  to each variant's frameworks and resources — never inside a bundle —
  and `verifyIosExportInputs` requires both. The export plugin reads the
  same dirs through explicit `.framework`/`.bundle` suffix enumeration,
  which a dotfile cannot match, so composition is unchanged.
- `player-identity-build.test.mjs` (77 tests): staging-emits-exclusion
  with a byte-identical fake `google@2x.png`, verify-fails-without-it for
  both dirs, and a complete-contract test (fixture link tree → stage →
  verify ok + suffix enumeration lists the full sets).

## Persistent-file protection contract

- `ANDROID_CAPTURE_PERSISTENT_FILES` grew 20 → 32: `journey.json` (+ tmp,
  bak, bak.tmp), `onboarding.json` (+ tmp), `player_identity.cfg` and
  `player_bindings.cfg` (+ tmp, bak each). Same list in
  `IOS_CODE_PERSISTENT_FILES` and the Python consumer mirror.
- Account-partitioned names (`journey.<token>.json|rev.json|
  rejected-local|remote.json` + tmp/bak, `cloud_journey.<token>.json` +
  tmp) are covered by a validated full-match pattern, shared
  character-identical between the Node producer and the Python consumer
  and pinned by the boundary test. Tokens carry uppercase `MB-` IDs, so
  dynamic names validate by the pattern, not the lowercase fixed charset.
- Capture/restore take an optional `listFiles`; both Android capture
  scripts enumerate `files/` (fresh-install empty dir = empty universe)
  and their name guards accept pattern names. Snapshots require the fixed
  set and allow pattern extras; restore removes capture-created
  partitions and repairs mutated/deleted ones; evidence and both report
  validators carry a dynamic fragment (files, before/observed/restored
  maps, flags) beside the unchanged fixed contract. The top-level
  mutated flag is fixed-OR-dynamic.
- Inventory test: every `user://` literal in production scripts must be
  fixed-listed, an enumerated capture handshake (it caught the missed
  `store_capture_title_runtime.ready`), or a dynamic prefix; every fixed
  name must still be produced by the game. The iOS inventory test gained
  the same classifications.
- Native SDK preferences and Keychain are never captured; the lib and the
  iOS capture path document that container backups do not protect
  Keychain. No capture/reset ran here.
- `test:play-release-package`: 230 pass.

## Export-wrapper identity integration

- `scripts/lib/identity-export.mjs` (new): `prepareIdentityExport`
  (resolve, per-provider diagnostics, stage-when-any-present),
  `cleanupIdentityExport`, artifact presence, Apple readiness
  (flag + Firebase + preset plugin), and `assertAppleSignInProfileSupport`.
- Both wrappers print the redacted preflight, stage the public config for
  exactly one export, and clean up on success/failure, with stale recovery
  under the build lock. Missing or malformed provider setup never blocks
  the export: the runtime gates keep guest play honest.
- 087 correction: my first cut patched generated `.entitlements` after
  export, claiming 4.7.1 had no preset hook. That claim was false. The
  staged official 4.7.1-stable source
  (`builds/director-evidence/godot-4.7.1-apple-embedded.cpp`: option
  registration at line 321, verbatim append at line 506 in the staged
  extraction) proves `entitlements/additional` is a real multiline-string
  option whose value plus "\n" is appended as XML. The wrapper now stages the temporary
  `com.apple.developer.applesignin` `[Default]` array through that hook:
  one-line plist XML appended to the iOS preset's extras (pre-existing
  XML preserved byte for byte), exact previous bytes restored after the
  run, marker-based recovery for killed staging under lock, refusal when
  the key carries other values. Proven by fixtures (real locked presets
  as the fixture: single-line insert/rewrite, byte-exact restore, kill
  recovery, foreign-state refusal) and by Godot's own ConfigFile reading
  back the staged value (bare and escaped-multiline probes). The
  signing-profile gate is unchanged: a promised grant with an ungranting
  profile fails truthfully at build and distribution verify.

## Product graphics (deterministic, not capture)

- Regenerated the six hero product PNGs from the painted portraits with
  the deterministic builder. Exactly those six files changed; icon,
  feature graphic, supporter, and lantern bytes identical. Products are
  512×512 RGBA opaque; an independent PNG decode showed portrait regions
  updated (50k–70k pixels each) with border chrome pixel-identical.
- `check:store-graphics` passes. The stale "24x24 crop" comment now states
  the real `preview_crop` Rect2i(36, 96, 72, 72) contract. No marketing
  sets rebuilt, nothing uploaded.

## Small integration fixes

- `project.godot` display version 3.0.0 → 4.0.0 (the only line touched).
  This also restores metadata consistency: both presets already pinned
  4.0.0, and the Android/iOS release-metadata asserts require equality.
- Banned term fixed by rename in `shot_painted_weapons.gd` (31 lines) and
  this log's sibling `4-0-0-painted-weapons-log.md` (4 lines). Hygiene is
  green.
- The real Camera2D physics-interpolation warning reproduced in every
  arena suite; the responsible production scene (`player.tscn` Cam)
  now declares `process_callback = 0`, the physics callback the engine
  already forced. Warning gone, contract tests untouched.
- `apps/docs/docs/game.md` version row → 4.0.0 (iOS 12 / Android 17).
  No `res://` assets added, so the asset manifest is unchanged.

## What bit

- Engine evidence: a `strings` scan of the Godot binary missed the
  `entitlements/additional` option and I inferred absence. The staged
  official source overruled the scan. Lesson recorded: never infer engine
  absence from a string search.
- Sandbox keychain denial makes every Godot run log
  `get_system_ca_certificates ... ret != noErr`, which fails the
  error-strict regression runner here; suites were verified individually
  by pass line + exit code + no other errors. The director re-runs the
  whole tree.
- `test_production_host` rank cases fail on this tree (fixture sends the
  count reply where the owned path reads its row first). 088 owns that
  correction; host and its tests untouched here, registration retained.
