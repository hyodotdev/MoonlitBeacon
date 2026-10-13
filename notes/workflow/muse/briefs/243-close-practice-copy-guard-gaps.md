# Brief 243: close confirmed practice implementation gaps

## The ask
Finish the safe, reproducible reference projects and their real runtime checks.
Preserve all preceding practice and site changes.

## Evidence
During round4, the director created a fake temporary repository with a
Lesson1 layer containing only project.godot and synthetic files named
synthetic-signing.p8 and synthetic-certificate.pem. Both were copied into
the generated reference output. No actual key or certificate was used.
The current key extension filter omits these formats.

A second fake fixture used assets/art as a symlink to an external temporary
folder containing a synthetic marker.png. The final file itself was regular,
so lstat(step.from).isFile() accepted it and the external marker was copied.
The director observed sourceAliasRejected=false / externalSyntheticMarkerCopied=true.

The director also created a fresh current Lesson3 project, imported it, and
ran the actual configured main scene with official 4.7.2 and --quit-after 30.
It exited 0 with four leaked ObjectDB instances and two resources still in
use. The new boot_probe.gd instead manually creates the main scene, calls
release_audio(), and waits before quit; its comment claims that real window
closes follow this path, but the current source has no window-close handler.
The original probe did not set current_scene and manually sorted/created
autoloads; round4 later moved probes to scenes, so inspect the final form.
These source paths must not be described as equivalent without evidence.

A current Lesson11 physics probe placed the player near the west beacon,
applied movement, and triggered three production hit callbacks to lose.
After 184 further physics ticks, over=true and health=0, but beacon charge
advanced from 0.0167 to 1.0, lit_count became 1, and the player moved another
3.0667 pixels. Finishing the run currently stops the timer but not all run
state. The probe explicitly cleaned its own audio to isolate this defect.

The current output collector also returned zero defects for the synthetic
line `SCRIPT ERROR: Parse Error: Identifier noErr is not declared`, because
the environment exclusion matches the substring noErr anywhere. This is a
confirmed guard gap; no real source file was broken for this probe.

The current Lesson16 reference preset sets package/signed=false, and the
practice check asserts this as "preset stays a debug build". That conflates
unsigned with debug. Official Godot documentation says package/signed
controls signing, while Export With Debug selects debug. An installable
Android debug APK still needs signing. The official references are
https://docs.godotengine.org/en/stable/classes/class_editorexportplatformandroid.html#class-editorexportplatformandroid-property-package-signed
and https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html.
No device install or store export was attempted for this finding.

A later fresh Lesson16 probe used normal engine startup and its actual
configured main scene/autoloads. A test-only root observer waited 0.3 seconds,
opened the production QuitPrompt and emitted the production Yes button's
pressed signal. It confirmed current_scene=TitleMenu, then exited0 with four
ObjectDB leaks and two resources still in use. This is a normal UI close,
not --quit-after. The director's independent current course:verify --lesson16
passed, so its existing checks did not cover this real defect. Evidence is
in the ignored real-quit-yes-lesson16.log. The throwaway project/home were
removed and no actual save or key was accessed.

## Do
- Re-check the final helper and, if still present, exclude/refuse .p8 and
  .pem signing material consistently across source-copy paths. Use only
  synthetic markers in regression tests.
- Keep .godot/environment/signing exclusions, canonical output protection,
  fresh-folder behavior, and deterministic legitimate asset copying intact.
- Confirm exclusions before creating output, with no partial projects on a
  refused source. Verify source aliases cannot bypass source containment;
  cover the confirmed asset-parent alias above and layer-parent aliases,
  using fake folders/symlinks, never actual repository secrets. Legitimate
  platform /tmp aliases above the source root should remain usable.
- Describe the user-data snapshot accurately: current code records size and
  mtime, which does not prove byte identity. If retaining a byte-identical
  guarantee, compare content hashes; otherwise state the actual metadata
  observation without overstating it. Preserve existing isolated-HOME safety.
- Narrow environment-noise exclusions to the observed native CA-store
  error/context; a SCRIPT ERROR or parse error must never disappear merely
  because it mentions noErr or get_system_ca_certificates. Cover the
  synthetic line above while preserving strict second-import gating.
- Correct the reference debug preset and its check: enable package signing
  without embedding a keystore, password, or release credential. Distinguish
  Export With Debug from Signed. Explain the local debug-key/SDK/template
  prerequisites and exact output-directory creation step; keep learner,
  reference and shipping identities separate. Do not install, sign with a
  shipping key, upload, or claim an APK/device test you did not perform.
- Run creation tests and relevant practice checks. Report exactly what
  changed and which defects were reproduced; do not invent extra findings.
- Include the confirmed Lesson16 QuitPrompt Yes path and normal desktop
  window-close path in the production cleanup fix and automated checks.
  Use actual engine main-scene/autoload/current_scene startup; test-only
  observers should only observe/press, not pre-release the app's audio.
- Re-check final audio/runtime source. Fix actual application teardown or
  provide and exercise a real graceful close path, rather than cleaning up
  only from the test script. Distinguish a forced engine quit limitation
  from normal player closing if experiments prove that distinction. Keep
  error/leak detection strict and report remaining limitations honestly.
- Run the real configured main scene in normal SceneTree context. Use
  proper test-scene/controller setup for autoload/global-singleton and
  current_scene behavior, rather than assuming manually added root nodes
  reproduce engine startup. Exercise title -> arena, restart and real close
  through production methods/signals; clean up test-owned fixtures separately.
- Re-check every applicable final checkpoint's finish behavior and freeze
  player movement, beacon progress/count, enemies/spawns and gameplay state
  immediately after either win or loss. Keep results/restart UI usable and
  visual result animations free to run. Cover a partially charged beacon
  and nonzero player velocity at finish, not just health/timer assertions.

## Do not
No shipping game, stores, protected paths, network, installs, Git operations,
real user data or credentials. No broad refactor.

## Acceptance
Synthetic signing files and external source aliases do not reach generated
reference projects. The real app startup/transition/close behavior is tested
and the test does not silently substitute a clean surrogate. Existing
guard/determinism tests and relevant generated projects still pass.
The director re-measures before acceptance.
