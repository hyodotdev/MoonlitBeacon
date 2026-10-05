# Brief 131: alternating side walk and intro cadence

## The ask
“인트로에 있는 캐릭터들 거든게 다들 이상한데? 다리를 교차하는게 아니라 앞다리 뒷다리만 꿈틀거리면서 걷네?”
“특히 좌우로 다닐 때”
Make the six intro heroes genuinely alternate their legs, especially while walking left and right.

## Why, and what good feels like
The party should stroll naturally around the beacon: each boot takes a turn leading, then recovers under the pelvis. The player must see a complete walk rather than one leading leg twitching. Preserve the premium painted characters and the original title composition.

## Where things stand
Accepted 4.0.0 work is uncommitted. Current gate_hero_forecourt.gd uses production hero sheets, four walk frames and hero.walk_fps=12. At 15–22.5 logical pixels/sec this plays three whole cycles each second regardless of travel. Director inspected all six original turnaround masters and the warden/dancer runtime sheets: side frame0 and frame2 keep the same near boot ahead; the source masters themselves are defective. The world-grounding and original title routes in packets119/122 are accepted and must remain.

Six newly generated four-pose LEFT-facing input strips will be provided in notes/workflow/muse/art/4-0-0/gait/<hero>-sidewalk-v2.png. These are art donors, not runtime-ready atlases. In each strip cell0 near boot leads left, cell1 far leg recovers, cell2 near boot trails right/far boot leads left, cell3 near leg recovers. Their upper bodies are intended to stay stable; inspect and normalize the actual pixels. Existing pack_painted_world.py independently fits each source cell to 108px height, which can cause body size changes when knee/foot height changes. Existing idle/portrait and vertical walk art remain sourced from the original masters.

## Do
- Integrate the six donors through the real reproducible painted asset pipeline. Replace left/right walk cells only; true right-facing reflection of the new left sequence is acceptable. Keep original idle, portraits and down/up walk bytes unchanged unless a demonstrated alignment defect makes a narrow change necessary. Do not replace the six heroes with one design.
- Normalize each side cycle with one scale and explicit torso/hip registration, keeping head size and torso position stable and planted sole baseline consistent. Preserve smooth alpha, clean gutters, 144x192 cells and 576x768 walk sheet layout. Do not independently enlarge each passing pose to contact-pose height. Include source provenance and actual crop/registration information, no hand-edited runtime PNGs.
- Make the intro cadence depend on actual distance traveled and visible body/stride size. A calm full cycle should be about0.8–1.5/sec at the current patrol speeds, with alternate contact/passing poses. Stopped actors use idle and planted feet, resuming and changing direction without rapid flicker or huge pose jumps. Do not slow automatic combat attacks or player movement to fix title animation.
- Refresh only measured walk paint-bound tables and relevant fixtures. Add a meaningful registered gait/stride regression: actual side PNG contact spreads versus passing widths/lift, stable head/torso geometry, no clipped cells; intro distance/cycle advancement and idle stops in both staging modes. Preserve previous route/grounding/reduced-motion assertions.
- Produce a deterministic director-runnable side-cycle showcase using real production PNGs for all six, left and right, plus an actual title-motion proof. Capture scripts/test paths may be operational helpers; keep debug labels out of production screens.

## Do not
Do not touch auth/cloud/production_host/production_entry/gate_entry.csv (another packet is working there), original title buttons, legal text, native plugins, version locks, project.godot, terrain or any unrelated art. Do not claim completion from changed hashes, FPS or four different images alone: the same physical leg must actually alternate ahead/behind. No network, device, credential, store, git or screenshot-upload work.

## Acceptance
All6 x both side directions have two opposing contact poses and two recovery poses, readable at native game size; no boot remains the leading foot throughout the loop. Stable head/torso registration and ground support, no torso/head growth or full-body duplicate afterimages. Walking animation advancement tracks measured travel in title/standalone layout and stops during dwell/reduced motion. Painted generator --check, relevant hero/painted/party/direction/entry checks and compile/hygiene checks pass; earlier assertions are preserved. Runtime shape remains four dirs x four frames, so the independent full production-PNG denominator remains192 cells.

## Deliverables
apps/game/tools/pack_painted_world.py or a narrow imported helper; six production walk.png assets; apps/game/scripts/ui/gate_hero_forecourt.gd; relevant registered tests and a showcase if useful; manifest source rows; notes/workflow/muse/gait-131-implementation.md (use this dedicated note, not the shared 4.0 build log). Donor originals stay in the repository under the input paths above.

## Constraints specific to this task
No secrets or private paths. No changes to protected values, hero statistics or game balance. Keep immutable idle/portrait/front/back artwork unless an evidenced exception is reported. Retain6 distinct characters and gameplay footprint.

## Settle these yourself
Choose a precise crop/hip alignment per donor and intro stride length from visual body size, rather than trusting equal-grid bounding boxes. If a donor has incorrect gait or visible anatomy flaws, report the exact frame/hero rather than silently accepting it. One failed donor is not grounds to redesign all other art.

## How the director will judge
Read complete diff/report; independently run generator and related checks, break one guarded behavior and demand a regression failure, then restore byte-exactly. Inspect all192 production cells at zoom and all12 side cycles at live size. Build/install Android first with preserved user data, view the real title video; then install iPad and observe its mirror. A representative device video does not establish physical Pixel10 coverage.
