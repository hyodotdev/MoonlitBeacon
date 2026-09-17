# Visual E2E evidence contract

Use this when you look at characters, monsters, items, VFX, or terrain and
judge quality, or when a request asks you to confirm "every direction",
"all of them", or "E2E". The most important rule is **do not mix a
representative device sample with a full-frame exhaustive review**.

## Keep the three evidences separate

| Evidence | What it proves | What it does not prove |
| --- | --- | --- |
| Physical Pixel 10 | Real composite, input, camera, HUD, and combat feel of the final APK | Heroes, directions, and animation frames you did not shoot |
| Full zoom of final production PNGs | Silhouette, direction, frame, clipping, and glyphs of every cell | That the APK actually ships that file and maps it correctly |
| Generator and Godot automated checks | Determinism, atlas regions, direction mapping, shape contracts | Misreads, readability, and play feel a human notices |

Write the three rows separately in the result report. Do not look at one
representative fight and write "all characters, all directions, device E2E
done". If a cell is empty, write **incomplete** and list the exact empties.

## Pin that the evidence is the current build first

1. Record `git rev-parse HEAD` and working-tree state.
2. Build the APK with the repo's Android command. The default preset uses the
   same package ID as production, so install **only on a dedicated test
   Pixel**, and do not uninstall the existing store app or wipe user data.
3. To report that you used an isolated `.dev` build, verify before install
   that the real application ID is separate. Do not conclude isolation from a
   temporary build name alone.
4. Compare the local APK SHA-256 with the installed `base.apk` SHA-256
   re-read from the Pixel 10.
5. Confirm capture time is after the last related source/PNG generation and
   install time.
6. Confirm with generator `--check` that production PNGs are byte-identical
   to the current generator code.

Old captures whose hash or time does not match are comparison material only,
not pass evidence for the current build. A capture where a modal, VFX, or
off-screen placement hides the direction does not count as evidence either.

## Hero direction matrix

The current contract requires the following for each of 6 heroes. If the
hero count or frame count changes, recount from resources and generators and
update the report denominator too.

- Directions: `down`, `up`, `left`, `right`
- States: `idle`, `walk`
- Source cells: 4 frames per state and direction — currently 192 cells total
- Physical device: confirm **6 heroes × 4 directions = 24 cells** identifiably
  in the final APK
- Motion: do not stop at stills; watch one walk cycle plus dash and camera follow

In each cell, look at face direction, front/back distinction, narrow side
profile, hands and unique props, foot plant, frame jumps, empty frames, cell
bleed, and bright marks that look like letters. For heroes whose left/right
is a mirror contract, also check pixel inversion. Check that silhouette and
contrast still hold over the real forest tint.

Shoot the direction matrix in a quiet real gameplay state, separate from
dense-combat evidence. Before accepting each cell, confirm all of the
following.

- No result, pause, level-up, tutorial, or combo copy, and pickups,
  projectiles, and VFX do not cover the body.
- Inspection overlays such as ArenaTools, FrameMeter, and system
  notifications must not be on screen.
- The hero's full body is in frame and direction is identifiable from a
  character-centered crop.
- Leave at least 1 original-world pixel of empty background between the hero
  outline and trees, brush, rocks, or props. If the outline touches or
  overlaps terrain, that cell fails even if the direction is visible.
- The four direction crops of the same hero actually differ. A different
  full-screen SHA alone is not a direction proof; identical bytes or the
  same crop across the four files is an immediate fail.
- Confirm health is the same before and after shooting, and that capture
  stability devices such as invincibility actually held.
- This repo's debug hero matrix first disarms `store_capture_boot.request.json`
  (which creates boost), opens a fresh Lv1 run per hero with
  `test_hero.request`, then waits for `combat-hidden` proof on a new
  `store_capture_clean_combat.ready`.
- For the 24 still cells, wipe previous runtime state per cell and re-arm a
  `hero_direction` request with a new nonce, bound to `hero_resource_path`
  and `direction`. Screenshot only after that nonce's state has proven
  `ready = true`, `clean_frame_streak >= 2`, requested hero and direction
  match, actual `hero_sprite_animation = idle_<direction>`, Lv1 · 0 kills ·
  full health · invincible, enemies · guardians · both-side bullets ·
  pickups · afterimages · extra VFX · pending drop · raid queue all 0,
  banner · combo · missile recovery · modal all hidden, and the real Sprite,
  physics, and Camera2D are ready. After capture, confirm that nonce's
  `observation` increased versus pre-capture and the state is still
  `ready = true`. Never reuse proof from a previous hero, direction, or nonce.
- Walk and dash video applies the same no-occlusion conditions. Play the
  full length yourself and hunt mid-clip popups again with a 1–2fps contact
  sheet. The video must re-prove the same `hero_direction` clean hold with a
  new nonce and `direction = any`; even when you cut it, leftover evidence
  must still contain one full four-direction walk cycle plus dash start/end
  and camera follow, complete.
- Motion is also watched on consecutive frames of the 60fps original plus a
  character-centered dense contact sheet. If the head/torso baseline during
  walk oscillates between two positions 1 original pixel apart, Pixel 10
  reads it as a 4px double outline, so it fails. Foot, arm, and cloak pose
  may change, but the upper-body outer line must stay in one place. Dash
  fails if even one full-body Sprite copy overlaps in the same frame.
  Short lines and spark effects are allowed, but they must not remain as a
  character outline after the dash ends.
- Do not name probes or failures `final`. Put only review-passed files on
  the contact sheet, and reopen overwritten files for re-review.

### `hero_direction` request format

A `new nonce` is not a UUID or a time string. Use only a `^[0-9a-f]{64}$`
value from Node `randomBytes(32).toString("hex")`. For each still cell and
each hero video, create the request below freshly and write it to the
verified debug application ID's private
`files/store_capture_runtime.request.json`.

```json
{
  "nonce": "64-character lowercase hex",
  "kind": "hero_direction",
  "hero_resource_path": "res://resources/heroes/warden.tres",
  "direction": "down"
}
```

Before writing, delete all three files for that package: request, state, and
temp. ADB private-file writes and atomic state reads follow the
`clearStoreCaptureRuntimeHandshake()`, `writePrivateFile()`,
`waitForStoreCaptureRuntimeObservation()` patterns in
`scripts/capture-store-screenshots.mjs` as they are. `direction` allows only
`down|up|left|right` for still cells and `any` for motion video. After
placing input, do not guess with a fixed sleep; poll until the new state
emits the exact `idle_<direction>` and an increased `observation`.

If you viewed all 192 source cells at 4× nearest and the final APK's 24-direction
device matrix is still empty, report "source exhaustive pass, device
partially unconfirmed".

## Enemies, guardians, items, world

- Regular spirits: exhaustive-zoom the current 7 kinds × 4 directions × 4
  frames = 112 cells, and on device watch real combat with kinds, directions,
  and barrages mixed.
- Guardians: exhaustive-zoom the current 3 kinds' 11 sheets and 50 frames.
  Front-locked presentation with `facings = 1` is an intended contract; do
  not write that you confirmed 4 directions.
- Items, projectiles, VFX: confirm empty frames, edge contact, clipping, and
  alpha flicker on every atlas cell, and in dense device play check that the
  player silhouette and telegraph lines remain.
- Terrain: composite with the real biome tint and look at repeating grids,
  long straight lines, tile seams, excessive blue bias, structure occlusion,
  and movement corridors across several RNG runs.
- UI: confirm safe area, clipped text, and banners/VFX showing through
  pause/result/modal.

## How to inspect by eye

Do not skim images as thumbnails; open them at original resolution. Dots are
viewed at 4× nearest, the same as Pixel 10's real world scale; UI defaults
to 3×. Use still contact sheets together with real motion video.

Look explicitly for these defects.

- Unintended glyphs that look like `L`, `I`, `C`, `G`, `6`, or a face
- Missing left/right flip, wrong direction, frames where a prop teleports
  to the other hand
- Cell-edge bleed, clipping, isolated 1-pixel, discontinuous alpha flicker
- Animation where feet bounce off the floor or the frame center jumps sideways
- Outlines that merge with the background, characters that vanish into VFX,
  unreadable attack telegraphs
- Repeating tile grids, ruler-straight lines, concentric bands, empty bands
  at the screen edge

After a fix, confirm that a negative probe with the same defect is caught by
the check, then re-run production PNG `--check`, related Godot tests, and
Pixel 10 device.

## Done-report format

Write at least the following with numbers and file evidence.

1. **Pixel 10 final APK:** APK hash, whether the installed hash matches, the
   matrix actually confirmed, and empty cells
2. **Production-asset exhaustive:** confirmed cell counts per hero/spirit/
   guardian/item and zoom factor
3. **Automated checks:** commands run, assertion count, exit code
4. **Verdict:** confirmed defects, what was fixed, intended exceptions, and
   the range not yet physically device-tested

Write "looks fine" only when those four rows have evidence. If you did not
actually confirm all 4 directions of every hero in the final APK, do not hide
that fact even if the source is clean.
