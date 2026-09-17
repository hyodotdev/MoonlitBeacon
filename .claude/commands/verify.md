# Full check

Confirm the repo is sound before a commit or PR. Stop and fix on the first
failure.

## Usage

```text
/verify           everything
/verify game      game only
/verify docs      docs site only
```

---

## 0. How to invoke `godot`

`godot` **does not have to be on PATH.** The `pnpm` scripts go through
`scripts/godot.mjs` and find the binary — `GODOT_BIN` → PATH → per-platform
install locations. For headless it prefers the `_console.exe` that actually
emits stdout.

If it cannot find Godot it prints every place it looked. Then put the full
path in `GODOT_BIN`. You only need the full path where you invoke `godot`
yourself (editor-operation automation and the like).

## 1. Game

```bash
pnpm game:check
echo "exit code: $?"
```

**Exit code 0, and not a single error or warning.**
`ObjectDB instances were leaked` is an audio-node teardown problem.
Read the `_exit_tree()` comment in `apps/game/scripts/ui/title_menu.gd` and
`apps/game/docs/known_issues.md` first.

### Compare `project.godot` values

The editor has actually reverted values. Confirm all of the following.

```bash
grep -E "viewport_width|viewport_height|window_width_override|window_height_override|stretch/mode|stretch/aspect|handheld/orientation|emulate_touch_from_mouse|default_texture_filter|rendering_method" apps/game/project.godot
```

| Key | Value |
| --- | --- |
| `window/size/viewport_width` | `808` |
| `window/size/viewport_height` | `360` |
| `window/size/window_width_override` | `1616` |
| `window/size/window_height_override` | `720` |
| `window/stretch/mode` | `"canvas_items"` |
| `window/stretch/aspect` | `"expand"` |
| `window/handheld/orientation` | `4` |
| `pointing/emulate_touch_from_mouse` | `true` |
| `textures/canvas_textures/default_texture_filter` | `0` |
| `renderer/rendering_method` | `"gl_compatibility"` |

If `aspect` is `keep`, you forgot to restore after shooting an error demo.
Same if `default_texture_filter` is `1`.

### No comments in `project.godot`

```bash
grep -n "^;" apps/game/project.godot | grep -v "^[1-7]:"
```

If there are comments besides the first 7 lines (the engine writes those),
delete them.
**The editor strips every comment when it saves the project.** Keep this
file values-only. Explain "why this value" in `apps/docs/docs/intro.md` and
in the lesson prose.

### Assets in the right place

```bash
# No ZIP inside res://
find apps/game -name "*.zip" | head

# Only files actually used (currently 119 / about 26.5MB — same count as check-manifest.mjs)
find apps/game/assets -type f -not -name "*.import" -not -name ".gitkeep" | wc -l
du -sh apps/game/assets
```

## 2. Docs site

```bash
pnpm docs:build
```

:::danger Fails if there is not a single commit
`showLastUpdateTime` is on, so the last-updated time at the bottom of a page
is **read from git log**. Zero commits means there is nothing to read and
the build fails. The dev server (`pnpm docs:dev`) is unaffected.
:::

`onBrokenLinks: 'throw'`, so a dead link stops the build.
The dev server returns 200 for missing paths because of SPA fallback, so
**link checking is build-only.**

### Clip budget

```bash
# Clips going into the repo are silent and under 1MB
for f in apps/docs/static/video/*.mp4; do
  size=$(du -k "$f" | cut -f1)
  audio=$(ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 "$f")
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  printf "%-34s %5s KB  %6.1fs  audio:%s\n" "$(basename $f)" "$size" "$dur" "${audio:-none}"
done
```

If there is audio or it exceeds 1MB, do not put it in the repo.
Narrated masters live in `builds/footage/` (not in git) and go to YouTube.

### Terminology check

```bash
node .github/scripts/check-hygiene.mjs
```

This looks at more than terms: the do-not-commit list, clip budget, BOM, and
`project.godot` locked values in one pass. **It is the same file CI's
"repo rules" job calls.** Do not write your own grep — we once made local
case-sensitive, so lowercase `phase` passed locally and died only in CI.

### Author-only docs did not leak onto the site

```bash
ls apps/docs/docs apps/docs/course
```

If something that belongs in `notes/` (plans, recording scripts, capture
pipeline, AI prompts, release checklist) is inside `apps/docs/`, move it.
Students see only **Course** and **Docs**.

## 3. Device (if applicable)

If the game screen changed, confirm on the phone with [`/device`](./device.md).
Skip if you only edited docs.

---

## Run it in one shot

```bash
pnpm verify
```

That one line runs everything CI's three jobs look at.

| Step | What |
| --- | --- |
| `test:android-build` | Android lock conflicts · invalidate failed artifacts |
| `test:iapkit-config` | Publishable-key checks · export inject/cleanup · direct-distribution isolation |
| `test:export-preflight` | Game start and full script compile gate before Android/iOS export |
| `test:ios-build` | iOS signing · IAP framework · asset fallback · device-install regression |
| `test:game` | Vault · IAP verify/restore/revoke · results-flow regression |
| `game:check` | Game opens without errors |
| `check:scripts` | Even GDScript the title never reaches all compiles |
| `check:locale` | Translation table vs keys in use, both languages actually load |
| `check:store-metadata` | App/IAP localization gaps, platform character limits, public copy vs source CSV |
| `check:hygiene` | Terms · do-not-commit · clip budget · BOM · `project.godot` locked values |
| `check:assets` | Asset manifest, media referenced by the body |
| `check:store-graphics` | Size, opacity, deterministic generation of tracked app/IAP graphics |
| `docs:build` | Dead links (`onBrokenLinks: throw`) |
| `check:docs` | NUL bytes, dead anchors |

**Do not hand-assemble grep.** Keeping two copies is how they drifted.
