# AI agent guide

This repo holds a 2D top-down dodge game built in Godot 4.7.1 and a **16-lesson
course** that follows its making. These rules apply in every agent tool.

Workflows live in [`.claude/commands/`](.claude/commands/).
If your tool has no slash commands, read the matching `.md` file and follow it.
Natural-language requests are routed by
`.claude/skills/moonlit-workflows/SKILL.md`. Project skills are authored in
`.claude/skills/`; `.agents/skills/` is the Codex mirror.
After editing a skill, run `pnpm skills:sync` and confirm the two trees are
byte-identical with `pnpm check:skills`. Never edit `.agents/skills/` directly.

| What you want | File to read |
| --- | --- |
| Commit · push · PR | `.claude/commands/commit.md` |
| Full check | `.claude/commands/verify.md` |
| Confirm on a phone | `.claude/commands/device.md` |
| Capture a course clip | `.claude/commands/record.md` |
| Start a new lesson | `.claude/commands/chapter.md` |
| Release | `.claude/commands/release.md` |
| Review a change | `.claude/commands/review.md` |

| Command | What it does |
| --- | --- |
| `/commit` | Branch → commit → confirm, then push → PR |
| `/verify` | Full check of game, docs, clips, and terminology |
| `/device` | Build APK → install on Pixel 10 → run → confirm |
| `/record` | Capture course clips |
| `/chapter` | Start a new lesson's documents |
| `/release` | Signed APK + itch.io release |
| `/review` | Review in-progress changes |

## Short summary

- This repo is a **Godot 4.7.1 game + a 16-lesson course**.
- **Do not write "Phase."** Lessons are numbered `Lesson 1`, `Lesson 2`; files are `chapter-01`.
- **`notes/` is not published on the docs site.** Authors only.
- **Do not push without user confirmation.**
- **Do not commit `.godot/`.** It holds the signing keystore password.
- **The screen at the end of every lesson must be usable as a store screenshot.**
  Do not leave gray rectangles or debug text.

---

## Layout

```text
apps/game/      Godot project (res:// root)
apps/docs/      Docusaurus
  docs/           Reference — what students read
  course/         Lessons — Lesson 1, Lesson 2, …
notes/          Author-only. Not published on the docs site
  plans/          Per-lesson plans
  scripts/        Recording scripts
  workflow/       Capture pipeline, AI prompts
  release/        Release checklist
  tools/capture/  Screen-capture automation
_downloads/     Original asset ZIPs    (not in git)
_asset_sources/ Unpacked sources       (not in git)
builds/         Build and footage output (not in git)
```

## Locked values — do not change these

| Item | Value |
| --- | --- |
| Engine | Godot 4.7.1 Standard, GDScript, Compatibility renderer |
| Target | Android first. Pixel 10 (2424 × 1080, arm64-v8a) |
| Screen | Landscape locked (`window/handheld/orientation=4`) |
| Internal resolution | 808 × 360 — exactly 1/3 of Pixel 10 landscape, integer 3× scale |
| Stretch | `canvas_items` + `expand` |
| Texture filter | Nearest (`default_texture_filter=0`) |
| Controls | One floating joystick (full screen) — move. Attack is automatic; dash is a bottom-right button |
| Package name | `com.crossplatformkorea.moonlitbeacon` — **do not change** even after the repo moved to `hyodotdev` (see below) |
| Release | Direct-distribution Android APK + itch.io; Google Play and App Store after store review |
| Docs | Docusaurus 3.10.2, `hyodotdev.github.io/MoonlitBeacon/` |
| Credits | Author credited as `Hyo Dev` |

---

## Rules

### `crossplatformkorea` in the package name is not a typo

The repo moved from `crossplatformkorea/MoonlitBeacon` to
**`hyodotdev/MoonlitBeacon`**, and the GitHub URL, docs site, and credits all
follow the new name. **The package name `com.crossplatformkorea.moonlitbeacon`
stays as it is.**

On Google Play and the App Store the package name is **the app's identity**.
Once published it cannot change; a renamed build is not an update, it is a
**completely different app**. Existing installs, ratings, reviews, and IAP
products do not follow it. Do not "fix" it just because it no longer matches
the repository name.

### Do not write "Phase"

Number lessons **Lesson 1, Lesson 2**. File names stay `chapter-01`,
`chapter-02`. That applies to docs, commit messages, code comments, and
branch names.

### The docs site is what students see

Plans, recording scripts, capture pipelines, and other production notes live
in `notes/` and stay off the site.

Do **not** put editorial policy or presenter directions in lesson prose.
Sentences like "this page is text-first and video is secondary", "you must
emphasize this", or "show this for at least 3 seconds" are for us.
Leave only what helps a student.

### Every lesson is a store screenshot

**Whatever lesson you stop on, that screen must be usable as a store
screenshot as-is.** No gray rectangles, debug text, default fonts, or
placeholders on screen. Do not prototype logic as gray boxes and skin it
later. Ship feature, art, sound, and UI together in the same lesson.

### Do not push without user confirmation

Commits are fine. A commit is local and can be undone.

### Do not recapture store screenshots without an explicit instruction

**The default is to reuse existing screenshots. Recapture only when the
screen has actually changed. With no explicit instruction, do not recapture
and do not upload to the stores.**

The only recapture justification is that store-visible layout, art, copy, or
framing is clearly different from the existing image. Version/build number
changes, non-visual code changes, IAP wiring/purchase verification, price or
product registration, release-metadata changes, and capture fingerprint or
provenance check failures are **not** recapture justifications. A failed
check is only a signal to decide whether the existing image's screen actually
differs from the current one.

When only a new review image is needed (for example a new IAP), add that new
product image only. Keep already-uploaded marketing screenshots and existing
product review images byte-identical, and do not run the full capture
pipeline that rebuilds existing files. Even if the user broadly authorized
capture, this minimum-change rule still applies.

The capture report pins SHA-256 of about 40 source files, so changing any
one of them invalidates **all four sets** — phone, 7-inch, 10-inch, and
iPad. Each set takes tens of minutes; iPad also needs a sudo RSD tunnel.
Starting a recapture just because `pnpm check:store-screenshots` went red
burns a day.

- If a check fails, **report it and ask first.** Do not capture automatically.
- Before recapturing, list which screens changed how, and the exact files to
  recapture.
- Leave screenshots already on the store as they are. An update that only
  uploads a new build does not need screenshot re-upload.
- If you must recapture, **lock version and build numbers first.**
  `export_presets.cfg` has two Android presets and one iOS preset, and
  **iOS uses `application/version`, not `version/code`.** We once changed
  that after capture and had to recapture all four sets.

### A one-line comment in `apps/game/` invalidates capture

`pnpm verify` does **not** call `check:store-screenshots`. Verify and CI can
both be green while store captures are stale — that has already happened.

`_runtime_fingerprint()` hashes **all of `apps/game/` as bytes**, excluding
`.godot`, `android`, `docs`, `ios`, `tests`, and `tools`. `scripts/` is
included. Changing one GDScript doc comment changes `runtime_sha256` and
invalidates the phone, 7-inch, 10-inch, and iPad sets, even if the pixels
did not move.

**`export_presets.cfg` and `iapkit.cfg` are excluded.** Bumping version and
build numbers does not break the fingerprint. That is a fingerprint fact;
the recapture rule above ("lock the version before capture") is separate
and still applies.

**If you touched `apps/game/`, run this separately:**

```bash
pnpm check:store-screenshots
```

Do not recapture just because it went red — the recapture ban above still
applies. If the change is non-visual (comments, docs, dead code), **reverting
that change is cheaper.** Put leftover notes in `notes/` or an issue.

This check cannot go in CI. The capture proofs (`builds/shots/store-localized/`)
are gitignored, so the runner has no files.

### If capture keeps failing, the game is too busy

Capture passes only when state before and after the screenshot matches. Dense
spawns let kills and hits land between the two observations, HUD width
shifts, and you get two ejected cores.
`debug_freeze_capture_progress()` freezes level, missile progress, and
embers; `debug_take_hit()` keeps invincibility for the capture window.
If you changed tempo, start there.

### Do not commit `.godot/`

It contains `export_credentials.cfg`, which holds the **Android signing
keystore password**. `export_presets.cfg` has no secrets, so it is committed.
**Credentials stay out; presets go in.**

### Do not put original asset packs in `res://`

The Ninja Adventure pack alone is 89MB. **Copy only files the project
actually uses** into `apps/game/assets/third_party/` and record them in
`apps/docs/docs/assets/manifest.md`.
What currently lives in `apps/game/assets/` is the third-party selection plus
originals: 119 files, about 26.5MB (excluding `.import`). About 15MB of that
is one Noto Sans CJK original so Korean, Chinese, and Japanese player names
render without depending on the device font. Current numbers are whatever
`pnpm check:assets` and the asset manifest say.

Do **not** copy code or scenes from Ninja Adventure's Godot demo project.
Read it only as a reference for sprite-frame layout.

### Clips in the repo are silent and under 1MB

Narrated masters live in `builds/footage/` (not in git) and go to YouTube.
Do not check in a whole lesson. Attach a short clip only where you have to
see it to understand the section.

### Do not put comments in `project.godot`

**If the editor opens and saves the file, it strips every comment and
reorders keys.** Explain "why this value" in `apps/docs/docs/intro.md` and
in the lesson prose.

---

## This development machine — macOS (Apple Silicon)

The working machine moved from a Windows PC to a Mac. The section
`## Things that often bite in this environment` was written on Windows, so
**parts of it do not apply here.** Each subsection says which.

### Export templates are downloaded separately from the editor

`Godot_v4.7.1-stable_macos.universal.zip` is **only the editor**.
Export needs `Godot_v4.7.1-stable_export_templates.tpz` (1,221 MiB), unpacked
into `~/Library/Application Support/Godot/export_templates/4.7.1.stable/`.

**Engine and template versions must match exactly.** A 4.6.2 template will
not satisfy a 4.7.1 editor. That was the first blocker after moving to Mac.

```bash
ls ~/Library/Application\ Support/Godot/export_templates/   # 4.7.1.stable must be listed
```

### Verify Android emulator first, then iOS

**Get it solid on the Android emulator before looking at iOS.** Keep that
order.

This is about **observability**, not preference. The emulator can dump the
screen with `adb exec-out screencap` for a visual check. A physical iOS
device **cannot be screenshotted from here** — since iOS 17+ the
`screenshotr` service sits behind a RemoteXPC tunnel that libimobiledevice
cannot reach, and `devicectl` has no screenshot command. Until a human looks
at the screen, there is no way to confirm iOS rendering.

To see the iOS screen, mirror with **QuickTime Player**.
File → New Movie Recording → chevron next to the record button → choose the
iPad as camera. You do not have to press Record.

**Do not read "the process is alive" as "it works."** On the simulator the
process stays healthy while the screen never comes up. Judge by whether
audio plays and whether a picture appears.

### The Android emulator is the daily loop

Keep a single AVD: `Pixel_10`. It matches the course target at
**1080 × 2424 @ 420dpi**. The `avdmanager` catalog has no `pixel_10`, so it
was created from the same-screen `pixel_9` profile.

```bash
pnpm emu          # boot Pixel_10 and wait until it is ready
pnpm emu:dev      # build APK → install → run
pnpm android:shot # product screenshot with debug UI hidden
```

**Always pass `-gpu host`.** `scripts/android.mjs` always adds it.
Without it you fall back to software rendering and people conclude
"Godot is slow on the emulator."

The system image is `android-34;google_apis_playstore;arm64-v8a`.
`system-images/` may show android-35 and android-36 folders, but they are
**shells without `system.img`, so `avdmanager` rejects them.** Being listed
does not mean they are usable.

### The iOS simulator cannot run the game — use a physical device

This is what we tried and what blocked us. **Do not spend time retrying.**
There are three walls, all upstream.

| | |
| --- | --- |
| Godot | The iOS template has **no arm64 simulator slice.** 4.7.1's `libgodot.a` has 2,292 x86_64 members and 0 arm64 (`ar t` confirmed). godotengine/godot#118161 is open |
| Apple | OpenGL ES on Apple Silicon simulators is broken in runtimes after iOS 15.4. The 18.5 / 26.x runtimes installed here are all affected |
| Godot | PR #102179 (4.4+) **strips Metal and Vulkan at compile time** for simulator builds. There is no renderer to pick besides gl_compatibility |

x86_64 + Rosetta clears the first wall — the iOS 18.5 runtime accepts
x86_64, so build, install, and launch succeed. Then it stops at
`Setting up an OpenGL ES 3.0 context.` The process stays alive; the screen
never appears.

**There is no reason to switch the renderer to Mobile.** The simulator has
no Vulkan, so you gain nothing. Pinning Compatibility is not a compromise;
it is the only correct answer.

Physical devices work. The arm64 slice is fine and signing passes.

```bash
pnpm ios:devices  # list attached devices
pnpm ios:run      # export → build/sign → install → run
pnpm ios:archive  # App Store Release export → xcarchive
pnpm ios:export-appstore   # archive → distribution-signed IPA
pnpm ios:validate:dry-run  # pre-submit checks with no network
```

If the device is `unavailable`, **turn on Developer Mode on the device.**
Settings > Privacy & Security > Developer Mode → enable and reboot. You
cannot enable it from the Mac.

### The capture tools do not run on Mac

`notes/tools/capture/` is all PowerShell + `user32.dll` P/Invoke + `gdigrab`.
This Mac does not even have `pwsh`. **Treat it as frozen Windows-only.**
Lesson 1 clips were shot with it, and the coordinate / discriminator-color
constants are the only recapture reference, so do not delete it.

---

## Things that often bite in this environment

The next five subsections — `godot` PATH, relative paths, `monkey`, NUL
bytes, and needing a commit — apply **wherever you work.** The BOM,
PowerShell `>`, and capture-monitor subsections apply **only on Windows.**
They stay because many students use Windows.

### `godot` is not on PATH

A winget install names the binary `Godot_v4.7.1-stable_win64.exe`, so
`godot` does not resolve.

**You do not have to care if you use the `pnpm` scripts.** `scripts/godot.mjs`
searches `GODOT_BIN` → PATH → per-platform install locations.
For headless it prefers the `_console.exe` that actually emits stdout.

```bash
pnpm game          # run the game
pnpm game:editor   # open the editor
pnpm game:check    # smoke-check (must be clean)
pnpm verify        # game + locale + repo rules + assets + docs (same as CI)
```

If it cannot find Godot it prints every place it looked. Set `GODOT_BIN` to
the full path. You only need the full path when you invoke `godot` yourself.

### Relative paths are relative to the `--path` folder

That is true for `--write-movie`. From the repo root you must write
`../../builds/...`. `builds/...` points at `apps/game/builds/`.
In that case `--write-movie` **exits 0 and never creates the file.**
Godot will not create missing folders, so `mkdir -p` first.

Always export Android through the wrapper. The wrapper installs the build
template, cleans Gradle output, and temporarily isolates the Play Billing
plugin from the direct-distribution APK.

```bash
pnpm android:build
```

Do not call `godot --export-debug "Android"` yourself; that bypasses channel
isolation.

### Launch the app with `monkey`

```bash
adb shell monkey -p com.crossplatformkorea.moonlitbeacon -c android.intent.category.LAUNCHER 1
```

`am start -n .../com.godot.game.GodotApp` fails with
`SecurityException: not exported`. The real launcher is `GodotAppLauncher`.

### Docs-build HTML mixes in NUL bytes (upstream bug, stripped at build)

Docusaurus builds HTML with React's `renderToPipeableStream`.
On multibyte characters (Hangul is the case we hit), **encoding-buffer
padding leaks into the output**, so a syllable can come out as
`glyph\0\0glyph`.

Measured:

| | |
| --- | --- |
| Source `.mdx` | clean |
| webpack JS chunks | clean |
| `--no-minify` | still present (not the minifier) |
| Two builds | same locations and counts (not a race) |
| **Linux CI** | **same leak** |

Docusaurus's `client/renderToHtml.js` comments link the React issue.

**We once wrote here that this was "only this PC." That was wrong.**
It happens on CI too. CI passed then because the check itself was broken
(see below).

The `apps/docs` `build` script now strips them with `node scripts/strip-nul.mjs`.
NUL has no legitimate place in HTML, so removing it restores the original
characters. CI uses `--check` and only asks whether any remain.

:::danger Do not hunt NULs with `grep -P '\x00'`
The runner's grep cannot handle a NUL inside the pattern, so it **passed
silently while NULs were present.** `|| true` hid that failure for almost
two months. Use `node scripts/strip-nul.mjs --check`.
:::

The symptom shows up in TOC links. Heading ids are fine, but a NUL inside a
TOC `href` makes that item go nowhere. `node .github/scripts/check-anchors.mjs`
catches it.

### Docs build requires at least one commit

`showLastUpdateTime` is on, so the build reads git log. Zero commits and
`pnpm docs:build` fails. The dev server is unaffected.

The dev server's SPA fallback returns `200` for missing paths.
**Dead links are caught only by `pnpm docs:build`** (`onBrokenLinks: 'throw'`).

### BOM direction is opposite (Windows)

- PowerShell `.ps1` **must have a BOM**. Without one, 5.1 reads the file as
  ANSI and the parser dies on Hangul comments.
- `project.godot` **must not have a BOM**. Godot treats the BOM as part of
  the key name, so you get `"ï»¿config_version"=5`.

`Set-Content -Encoding utf8` writes a BOM. To write without one:
`[System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding $false))`.

### PowerShell `>` corrupts binaries (Windows only)

`adb exec-out screencap -p > x.png` is ruined.
Write with `adb shell screencap -p /sdcard/x.png`, then `adb pull`.

### Capture on the right-hand monitor (Windows only)

A fullscreen game on the left monitor pins the cursor to the screen center,
so `SetCursorPos` does nothing. This PC is two 4K displays at 200% scaling,
so the virtual desktop is 7680 × 2160 and the right monitor starts at
x = 3840.

---

## CI

| Workflow | When | What |
| --- | --- | --- |
| `ci.yml` | PR and push to main | Docs build · game/IAP regressions · headless game · 10 `project.godot` values · repo rules |
| `android.yml` | PRs that touch `apps/game/**` | Direct-distribution APK and Play debug AAB builds, channel isolation, then artifact upload |
| `deploy-docs.yml` | Push to main touching `apps/docs/**`, or manual run | GitHub Pages deploy |

The **repo rules** job in `ci.yml` calls `.github/scripts/check-hygiene.mjs` —
the "Phase" term, the do-not-commit list, clip budget (silent · 1MB), Godot
output paths, hardcoded absolute paths, BOM, locked `project.godot` values,
and music `loop=true`.

**`pnpm verify` calls the same file.** Local and CI used to have separate
checks, so they drifted — lowercase `phase` passed locally and died only in
CI.

:::info Pages is live — keep it that way
The repo is public and the Pages site exists with Source = **GitHub Actions**,
so `deploy-docs.yml` auto-deploys on docs changes. Do not revert it to
manual-only without a reason.

History: while the repo was private in the hyodotdev Free org, Pages was not
a target and the workflow was manual-only. Creating the site is a repo-admin
action — the default `GITHUB_TOKEN` cannot do it (`Resource not accessible
by integration`), so an admin creates it once via API or Settings. If the
site is ever deleted, recreate it before expecting deploys to work.
:::

## Commands used often

```bash
godot --path apps/game                                    # run the game
godot --headless --path apps/game --quit                  # smoke-check (exit 0)
pnpm docs:dev                                             # docs site (localhost:3000/MoonlitBeacon/)
pnpm docs:build                                           # static build — dead links are caught only here

pnpm android:build
pnpm android:run
```

On Mac those last three are wrapped in `pnpm`. Even if `adb` and `emulator`
are not on PATH, `scripts/android.mjs` finds the SDK.

```bash
pnpm emu            # boot Pixel_10 emulator → wait for boot
pnpm emu:dev        # build APK → install → run
pnpm android:shot   # clean-UI proof, then screenshot → builds/shots/android.png

pnpm ios:devices    # list attached iOS devices
pnpm ios:run        # export → build/sign → install/run on device (simulator cannot)
pnpm ios:archive    # App Store Release xcarchive
pnpm ios:export-appstore   # latest archive → distribution-signed IPA
pnpm ios:validate:dry-run  # local IPA/signing/version/key checks, no network
pnpm ios:validate          # remote App Store Connect Validate
pnpm ios:upload:dry-run    # same local checks immediately before upload, no network
pnpm ios:upload            # explicit TestFlight upload
```

`ios:build` and `ios:run` first try a normal Debug build that includes
AppIcon. Only when Apple libraries are blocked by system policy on this
Mac's Xcode/CoreSimulator runtime and `AssetCatalogSimulatorAgent` dies do
they make a **dev build without an asset catalog** in a separate DerivedData.
That output puts the AppIcon PNG from export into legacy `CFBundleIconFiles`
and re-signs while keeping the existing Apple Development entitlements, so
the home screen still uses the project icon. This workaround is for attached
device play only. It is **never** applied to `ios:archive`, so before an
App Store submission the runtime must be restored and an archive with a
normal `Assets.car` and AppIcon must succeed.

### Credentials come from `.env`

`scripts/lib/load-env.mjs` loads the repo-root `.env` into `process.env` at
the top of 14 entry scripts. You do not have to `source scripts/secrets.sh`
in every shell; `pnpm android:build` alone picks up signing, IAP, and
App Store values.

Priority is **real environment variables > `.env` > each script's Keychain /
default-path fallback**. That order keeps CI safe. CI has no `.env`; secrets
arrive as environment variables. If the file overrode the environment, a
stale local value would quietly change CI results.

```bash
./scripts/secrets-materialize.sh
```

Writes `.env` with mode 600 from Keychain values. Values never appear on
screen or in shell history. If Keychain is empty, fill it first with
`scripts/secrets-bootstrap.sh`.

:::danger Do not put values in `.env.example`
`.env` is gitignored, but **`.env.example` is committed.** It is a template
of names and where to get them. Once committed, deleting the file does not
remove it from git history, and a leaked Android keystore password cannot be
rotated — Play treats the signing key as the app's identity.
Check 11 in `check-hygiene.mjs` rejects anything to the right of `NAME=`.
:::

Follow-on App Store commands require `MOONLIT_ASC_KEY_ID`,
`MOONLIT_ASC_ISSUER_ID`, and `MOONLIT_ASC_PRIVATE_KEY`. Point at the `.p8`
with an absolute path and keep it outside the repo at mode `600`. Scripts
never print the key material and never pass it into ordinary Godot or device
tool environments. Only `ios:upload` actually sends a binary;
`ios:upload:dry-run` uses no network.

`pnpm android:bundle` and iOS export need an IAPKit publishable key for
purchase verification. They look at `IAPKIT_API_KEY` first, and on macOS
fall back to the Keychain service `dev.openiap.kit.moonlitbeacon`, account
`MoonlitBeacon Mobile`. The generated `apps/game/iapkit.cfg` is deleted
after export and is not in Git. Never put an `openiap-kit_sk_…`
secret/admin key in an app build.
