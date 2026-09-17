# Review a change

Scan in-progress changes before commit. Focus on places that have actually
gone wrong in this repo.

## Usage

```text
/review              staging + everything in progress
/review --staged     staged only
/review apps/game    that path only
```

---

## 0. What changed

```bash
git status --short
git diff --stat
git diff --cached --stat
```

---

## 1. Accident prevention (first)

```bash
# Signing password did not sneak in
git diff --cached --name-only | grep "\.godot/" && echo "!!! stop"

# Original assets did not sneak in
git diff --cached --name-only | grep -E "_downloads/|_asset_sources/|\.zip$"

# Clips over 1MB
find apps/docs/static/video -name "*.mp4" -size +1M

# Clips with audio (repo clips are silent)
for f in apps/docs/static/video/*.mp4; do
  a=$(ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 "$f")
  [ -n "$a" ] && echo "has audio: $f"
done
```

## 2. Terminology

```bash
grep -rn "Phase\|phase-0" apps/ notes/ README.md AGENTS.md 2>/dev/null \
  | grep -v node_modules | grep -v "\.docusaurus"
```

**Must be 0 hits.**

## 3. Game (`apps/game/`)

### `project.godot`

- [ ] No comments (except the first 7 lines). The editor strips them
- [ ] The 10 locked values are unchanged — table in [`/verify`](./verify.md) section 1
- [ ] `stretch/aspect` is `expand`, `default_texture_filter` is `0`
      (did we forget to restore after shooting an error demo)

### GDScript

- [ ] `##` doc comments explain the node's **role**. Do not transcribe the code
- [ ] Constants have names instead of magic numbers (like `FLARE_SECONDS`)
- [ ] `@onready` paths match real node names
- [ ] Types are attached (`var x: float = 0.0`, `func f() -> void`)
- [ ] Values that leave the screen are not hardcoded.
      `expand` means viewport width differs per device — UI uses anchors,
      backgrounds are center-aligned
- [ ] Sound stops when leaving the scene. Otherwise you get
      `ObjectDB instances were leaked` on quit

### Scenes

- [ ] New nodes have meaningful names (no default names like `Node2D`, `Sprite2D3`)
- [ ] Repeated things were extracted as scenes and placed as instances
- [ ] Canvas layers are not mixed — the layer that takes night tint, the
      self-lit layer, and the UI layer

### Screen

- [ ] **No gray rectangles, debug text, default fonts, or placeholders**
- [ ] Type size is a multiple of 11 (Galmuri11 is an 11px grid)
- [ ] Pixels are not half-pixel off — positions floored to integers
- [ ] Character, monster, item, VFX, and terrain changes were checked with
      Pixel 10 device, full production-PNG, and automated checks kept separate
      per the [visual E2E evidence contract](../skills/moonlit-workflows/references/visual-e2e.md)

## 4. Docs (`apps/docs/`)

- [ ] No editorial policy or presenter directions in lesson prose
      ("video is secondary", "you must emphasize this", "show this for at least 3 seconds")
- [ ] Production docs that belong in `notes/` did not leak onto the site
- [ ] Lesson numbers are correct (from Lesson 1, `chapter-01`)
- [ ] New clips came with a poster
- [ ] Clips over 30 seconds do not have `silent` (that autoplays and loops)

```bash
# Dead links are caught only by the build. The dev server returns 200 for missing paths
pnpm docs:build
```

## 5. Capture tools (`notes/tools/capture/`)

- [ ] `.ps1` has a BOM (without one, 5.1 reads as ANSI and dies on Hangul comments)

```bash
for f in notes/tools/capture/*.ps1; do
  [ "$(head -c 3 "$f" | xxd -p)" = "efbbbf" ] || echo "no BOM: $f"
done
```

## 6. Last

```bash
/verify
```

If the game screen changed, go through [`/device`](./device.md) before
committing.

---

## How to report

List what to fix, most serious first. Attach **file:line** and **why it is a
problem** to each item. Do not write taste-level "this might be nicer".
Write only things that actually break, break a rule, or will cause an
accident later.
