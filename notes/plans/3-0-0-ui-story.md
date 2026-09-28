# 3.0.0 — new UI + story structure (plan)

Author-only. Design authority for 3.0.0. The canon in
[`world-story-pass.md`](./world-story-pass.md) stays true; this plan gives it
structure and replaces the screens that carry it.

**Status:** plan only. Nothing here is built yet.

---

## Why 3.0.0 exists

2.1.0 shipped as the final release of the tutorial course
(`release-2.1.0`). The course is pinned there, so 3.0.0 is free to change
screens the 16 lessons describe. That is the whole reason for the version jump.

The first attempt at an art upgrade (PR #6, closed unmerged) failed because it
treated "better graphics" as "more detailed graphics." It is recorded in
[`checklist.md`](../release/checklist.md); the defect list below exists so the
same failures cannot land twice.

## The one rule that outranks everything

**Moonlit Beacon is a cute little mini-game. It stays one.**

아기자기하고 귀여운 미니게임. Richer art is the goal; *fancier* is not. When a
candidate asset looks impressive but not cute, it is the wrong asset.

Concretely, an asset is rejected if it is:

- dark enough to lose its silhouette against the night ground
- detailed enough that you cannot name the creature at 48px
- proportioned realistically instead of chibi — heads stay large, bodies short
- gritty, gothic, armored, or "epic" in read

A dodge game is unplayable when you cannot instantly see what is about to touch
you. Cuteness and readability point the same direction here, so there is no
trade to make.

---

## Asset contract

Every one of these would have caught a real PR #6 defect. A batch that fails any
line does not land.

| Rule | The defect it prevents |
| --- | --- |
| Spirits keep **4 facings**. `facings = 4`, sheet `cell*4` wide x `cell*frames` tall | All 7 spirits silently went `facings = 4 → 1`; mobs stopped turning toward the player |
| Art must match the kind's `display_name` | `drifter` (밤 박쥐, night bat) got jellyfish art; `swarm` (작은 불티, little spark) got the bat art — the two sheets were swapped |
| Zero alpha in the outermost 1px ring of every cell | `caster.png` frame 1 was clipped at the sheet edge; frames bled across 48px cell borders |
| Every frame shares one baseline and one anchor; bbox drift ≤ 2px between frames | Frame-to-frame size and position jitter, which reads as vibration |
| Adjacent frames must differ by ≥ 3% of opaque pixels | The 6 "animation" frames were near-identical renders, so playback shimmered instead of cycling |
| Stretchable UI art ships as **9-slice** with declared margins | The 168x112 relic card was a fixed bitmap behind an unchanged text layout — title above the frame, footer below, description overflowing both sides in en/ko/ja |
| Min luminance contrast 3:1 against the darkest ground tile | Near-black sprites vanished on the night ground |

Extend `tools/check_custom_assets.py` with these as hard checks so `pnpm
check:assets` fails on them, rather than trusting a render review to notice.

### Salvage from PR #6

`feat/guardian-presentation` is kept, not deleted.

- **Take:** 16 relic emblems (48x48) and the 4 card-frame states (168x112) — they
  are the one genuinely good output. Only behind a real 9-slice layout.
- **Take, with fixes:** `tools/slice_gpt_grid.py`, `tools/slice_gpt_cells.py`,
  once they enforce a shared anchor and reject cell bleed instead of silently
  scaling each cell to its own bbox.
- **Revisit separately:** the guardian combat presentation (spawn slam ring,
  camera kick, speed lines, wider death burst) is art-independent and may well
  be worth keeping on its own.
- **Drop:** all 22 guardian sheets and all 7 spirit sheets from that branch.

---

## UI: what "completely new" covers

17 scenes, ~7,300 lines of UI script today. Rewriting all of it at once
guarantees a broken middle. So the UI pass is **one design system, then screens
in dependency order**, and the game is playable and screenshot-clean at every
stop.

### Step 1 — the design system (nothing visual ships yet)

A single theme resource plus 9-slice panel art, so screens stop hand-rolling
their own boxes. This is the step that makes the other steps cheap.

- One Godot `Theme` with named type variations: panel, card, primary button,
  ghost button, stat readout, banner
- 9-slice frames with declared margins for every box on screen
- A type scale of exactly three sizes; Galmuri11 stays the pixel face, Noto Sans
  CJK stays the CJK fallback
- Spacing on a 4px grid, since the internal resolution is 808x360 and integer
  3x — half-pixels are visible

### Step 2 — the HUD, because it is what the screen actually looks like

The current gameplay screen is the real complaint. A capture of it shows, at
once: a five-line stat block, a wave/level/defeated/timer bar, a region-and-time
caption, a floating `BEACON` label, a centered objective line, a centered
"volley complete" line, and a dialogue balloon — all at similar visual weight,
over a flat brown ground with props that cast no shadow.

- Cut the permanent text to hearts, beacons, and timer. Everything else becomes
  transient or diegetic
- One message channel, not three competing centered lines
- Ground the props with shadows and give the night actual moonlight — a cool
  top-light tint, a warm pool at each lit beacon, and a vignette. This is the
  single biggest visual win available and it costs no new sprites
- Re-tone the ground away from flat maroon-brown

### Step 3 — the relic picker

Rebuild the layout around the card art instead of behind it: an icon slot, a
title line, a description box that wraps inside the frame, and a footer, all
inside 9-slice margins. Selection is a state of the card, not a second rectangle
drawn over it. Verify at the longest string in all five locales.

### Step 4 — title, results, shrine, shop, settings

In that order. `settings_panel.tscn` (514 lines) and `iap_shop_panel.gd` (1,150
lines) are the largest and go last, when the design system is proven.

---

## Story: structure over the existing canon

The canon is good and stays. What is missing is **shape** — today the story is
delivered almost entirely as balloon lines during play, so it reads as flavor
rather than as a story.

Already in place and kept: the dark as hunger, spirits as what the dark spat
out, guardians as clotted swallowed light, the Warden order, the debt arc that
opens each run and closes on an epitaph.

What 3.0.0 adds:

- **Acts with a visible boundary.** The debt arc has an opening and a closing but
  no middle. Cycles 1-8 become three acts with a named turn between them, so
  progress reads as a story beat and not only as a difficulty step.
- **A place to read it.** A lore screen where first-sight lines, guardian
  meetings, and deep-night asides accumulate as they are seen. The writing
  already exists per-kind; right now it is said once and gone.
- **Per-hero voice.** The voice table is hero-agnostic today, listed as a
  follow-up in the bible. Distinct heroes are already purchasable, so they
  should not narrate identically.
- **A named thing past cycle 9.** The Warden currently mutters because nothing
  down there has a name. Naming it turns the endless stretch into a destination.

Locked: five languages stay in sync (en/ko/ja/zh-Hans/zh-Hant), and no new
string lands without all five. `pnpm check:locale` enforces it.

---

## Course impact

The 16 lessons describe the 2.1.0 screens and are pinned to `release-2.1.0`.
3.0.0 diverges from them on purpose.

- The course keeps teaching the 2.1.0 build. Lesson prose does not chase 3.0.0
- `apps/docs/docs/` reference pages *do* track the current game and get updated
- Lesson clips are not reshot for 3.0.0

## Verification per step

Every step ends green, not just the last one.

```bash
pnpm verify              # game + locale + repo rules + assets + docs
pnpm check:assets        # plus the new asset-contract checks
pnpm check:store-screenshots   # run separately — pnpm verify does NOT call it
```

Because `_runtime_fingerprint()` hashes all of `apps/game/` as bytes, every step
here invalidates the store-capture fingerprint. **That is expected and is not a
reason to recapture.** Recapture only on an explicit instruction, and only after
listing which screens actually changed. Each of the four sets takes tens of
minutes and iPad needs a sudo RSD tunnel.

Store screenshots get recaptured **once**, at the end, when the UI is final —
not per step.
