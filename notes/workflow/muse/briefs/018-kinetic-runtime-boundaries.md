# Correction brief 018: Runtime boundaries and six-track combat rotation

Continue tag `20260930-2321-kinetic-hero-weapons-and-audio`; retain brief 017's scope and acceptance
criteria. Round 1 is complete and the director has read its report, all changed hunks and new source,
run both new tests, the original full runner and actual windowed pictures. Do not discard the weapon,
audio or visual work. Implement the new user music request and the confirmed corrections below.

## New user steering (2026-10-01)

The user listened to the director's audition and approved the musical direction:

> 오 음악 좋네 합격 그리고 수호자 나올떄는 좀 더 빠르고 박진감 넘치는 음악 나와도 좋겠어.
> 그리고 음악을 2개만 번갈아 쓰지말고 3개씩 랜덤으로 교차하게

Build **three arena tracks and three guardian tracks**, all original deterministic assets. Keep the approved
arena track/motif as one of the arena three; keep the approved guardian's musical identity while making guardian
playback clearly faster and more urgent. Add genuinely distinct compatible arrangements/rhythms, not three
copies or simple renamed exports. At a stable musical point (arena region/entry and guardian encounter), choose
from the corresponding three-track set with a randomized bag or equivalent no-immediate-repeat rule. The
normal return from a guardian must restore an arena track. Do not switch tracks on every attack or short
loop, and do not let story/title inherit frantic combat music. Avoid a gameplay-global RNG dependency for
purely musical track choice. Respect existing escalation/pitch cap and settings, release and mix headroom.

Update the generator/check/manifest/reference/tests and audition to **six full tracks plus the existing eleven
combat effects**. Tests must cover the actual six imported whole-loop endpoints, selecting only from the proper
pool, all three appearing over a controlled sequence, no immediate repeat, region/guardian/return transitions,
settings and cleanup. The user approved the audition, so do not claim the director heard audio through a tool.

## Confirmed in the completed round-1 source

The implementer already corrected the comparison to 180/120 frames at 1/30 s per tick. Retain that
repair; the director independently reproduced 182 weapon checks and the 132/100–102 same-target
output before the later Warden sidearm cadence repair (the report now gives 135). Keep that bare-kit
fixture distinct from actual opening-relic bot runs and measure final values again after these corrections.

1. `_loop_bgm()` uses `wav.data.size()/2` as its sample endpoint, but both music imports use QOA
   (`compress/mode=2`). The director read the actual RSRC files: arena QOA payload 129816 bytes has
   320727 decoded samples; guardian payload 152984 has 378000 samples, all at 22050 Hz. The current
   expression repeats after 2.943673 / 3.469025 seconds instead of 14.545442 / 17.142857 seconds.
   Set correct decoded-sample loop endpoints, or import the full loops correctly. Test the actual
   imported resource format, sample endpoint and playback beyond the first few seconds, including
   guardian escalation. Do not only compare source WAV endpoints or mirror the incorrect byte formula.
   The source WAV raised-cosine endpoint repair already measures zero discontinuity; retain it.

2. `_on_spirit_perished()` calls `_gain_progress()` before `_play_kill_sfx()`. Both replace
   `RewardSfx.stream`; Godot's setter stops prior playbacks, so the kill that causes a level can cut
   that same callback's growth cue immediately. Subsequent chain kills can similarly steal core and
   overcharge rewards. Preserve earned reward accents with an actual priority rule or bounded separate
   voices; do not solve this by suppressing all kill sounds or adding audio nodes per shot. Add live
   callback-order and overlapping reward/kill playback checks, Music/Sfx mute, scene release and
   measured mixed headroom at maximum settings. Remember inherited modal pause already pauses audio;
   separately check unpaused `VoicePanel` reading periods, where the current duck predicate never fires.
   Both clocks currently call `_play_weapon_sfx(profile)`: Knight's melee bash sounds like a cannon and
   Warden's small ranged sidearm sounds like a sword. Map the loud signature cue to the actual primary
   event, with an appropriate quieter sidearm accent. Assigning `stream` every attack/impact also stops
   previous voices even when it is the same resource; keep the intended bounded tails or document a
   deliberate retrigger policy. Measure the resulting real mix rather than summing source peaks alone.

3. `_missile_volley()` now takes the maximum of base hero lanes and the core volley. However,
   `guided_lane_damages()` still budgets only the core volley and `MoonMissile.launch_volley()` fills
   missing entries by repeating `damage`. Keeper's five lanes at core three can clone the center
   budget into two extra guided lanes. Dancer/Eclipse can also diverge at low-power Starfall evolution.
   Make actual guided lane count and budget agree without erasing primary identity or duplicating damage.
   Test all six heroes across powers 0–8, early Starfall evolution and awakening; verify whole-volley
   budget, nondecreasing center effective damage and no missing-lane fallback multiplication.

4. New beacon descriptions expose `88px`, an internal coordinate distance that is not the phone's
   displayed pixel distance. Use player-facing language such as staying inside the defense circle/glow
   for 6.5 seconds. Show the actual defense boundary if there is no corresponding visible circle;
   the current beacon only changes flame/glow colors during overcharge. Keep the exact radius/time,
   decay/abandon contract and rewards in source/reference/tests, and explain safe versus risky choices
   without engine units. Hero descriptions should lead with weapon and play style; a flat `dmg +25%`
   now means a multiplier on a private per-kit base rather than damage relative to Warden. Present
   comparisons accurately, keep meaningful health/movement/dash/opening information and revise obsolete
   display-copy assertions while retaining the resource stat/ownership checks. Also reconcile comments
   that call `Hero.AttackProfile` cosmetic-only while arena primary mechanics now select through it,
   either by an explicit primary selector or accurate scope wording; retain legacy projectile
   `configure_profile` damage neutrality.
   The director ran the real original `pnpm test:game` in the copy: it exited 1 at
   `test_shrine_portraits`, 31 failures out of 588 checks. You repaired the independent Keeper copy
   literals later in round 1; retain that gate and update both independent five-locale literal sets
   again with the final weapon-first copy. Keep the independent advertised-copy/render contract; do not derive expected text from the Label or translation
   CSV, or remove readiness assertions to get green. Diagnostic UI pictures remain separate from
   marketing captures, which must not be regenerated or uploaded.

5. Correct the capture harness's reproducible commands to use `pnpm godot:isolated --windowed` for
   actual pictures and the isolated headless wrapper for validation, with a pre-created output folder
   and `../../builds/...` movie path relative to the game root. The current header's movie destination
   `builds/shots/...` points into `apps/game/builds` and contradicts the repository's documented rule.
   Synchronize the first gameplay capture and beacon captures with completed draws, not only process
   frames. The beacon pictures should retain an actual arena/beacon background rather than freeing
   every arena and showing a panel over an empty viewport with a stub. Primary-hit/effect observation
   must distinguish the chosen kit from a generic sidearm flash. Record the true motion interval:
   four frames separated by 0.2 s span 0.6 s, not the comment's 0.2 s total. Provide enough attack
   motion to inspect the slower cannon's flight/impact and foot/recoil settling. The director can
   perform display capture when the sandbox cannot; do not claim headless validation produced PNGs.
   The director actually ran the current tool windowed with Dummy audio (28 checks, 24 hero PNGs plus
   ten beacon PNGs). `director-preview` pictures still show the bottom debug toolbar and the first-run
   movement banner; freeing FrameMeter alone does not hide those. Produce clean diagnostic combat
   pictures with the debug toolbar hidden, onboarding settled, Korean hero captions/default locale,
   and no temporary dialogue covering the action. Keep live gameplay attack logic enabled.
   The current screenshot tool's `test_hero.request` creates actual hero opening relics (e.g. Dancer
   HUD already shows Moon Dance 1/5, Sage Starfall 2/6), so the comment "bare Lv1 kits" is inaccurate.
   Keep natural Lv1 openings in gameplay pictures and label them accurately; the no-opening damage
   calibration is a separate fixture. Strong pictures add the documented fixed investment on top.

## Remaining acceptance work

Registered behavioral checks must be meaningful against these actual production paths. Enforce isolated
test saves before instantiating arenas. Re-run the related game checks, generator
determinism, locale/assets/docs and the required natural/guardian smoke after the final correction. The
director read round 1's full-suite error: the editor import writes real HOME editor settings and contacts
ADB, both unavailable in the implementer sandbox. Do not keep retrying those forbidden operations or
patch the runner to evade the sandbox. Run the game fixtures through `godot:isolated` and report that
import limitation explicitly; the director will run the original full suite and `/verify` outside that
sandbox after the source is stable. Show
real enemy/projectile density and measure late cannon splash candidate work; a cache scan not included in
the existing sweep counter does not establish the per-tick budget.

Keep early/stronger six-hero weapon pictures, short motion evidence, five beacon-choice locales and the
audition output current with the final implementation. Wait for settled UI and use real production hits,
not posed drawings. Update the game reference, manifest and dated build-log appendix to the actual measured
runtime behavior. Keep story, ownership, package, versions, controls and protected paths unchanged.

No git, network, user-save, device, store-capture or user-window operation. Report exact fixes, changed
paths, counts, measured intervals/output and artifact locations. The director will run its own checks,
production mutations and visual/audio measurements before accepting.

## Actual display finding

The director inspected the six live early pictures at full-frame and 4× nearest closeups:
`builds/director-held-weapons-closeup.png` in this copy (also the six-frame overview at
`builds/director-six-hero-preview.png`). All six held
weapons are currently anchored at `MOONLIGHT_ORIGIN` (-20), across the face/nose; Keeper, Knight and
Sage read as nearly the same blue stripe over their eyes. Move/shape the carried weapon to a credible
hand/chest grip that leaves the face readable, with distinct sword/twin/rifle/fan-gun/heavy barrel/scythe
silhouettes. Keep muzzle flashes aligned with the actual shot flight and the four-direction foot/recoil
contract. On the real arena tick both clocks may fire: `attack()` flashes a primary cut/ring, then
`play_moonlight_cast()` can replace that same rig `_kind` with the quiet ranged sidearm flash. Preserve
the readable primary accent in that simultaneous case (bounded separate strokes or a short priority
rule); do not make the screenshot pass by disabling the other production clock. This is a player-visible result, not a request for a wholesale sheet regeneration. Show all
four facings and several live fire frames at early and strong builds so the director can judge it.

The Knight table also currently gives a 9-damage/1.0s melee bash versus a 16-damage/2.3s cannon.
Its nominal single-target sidearm output exceeds its supposed primary (9/s versus about 7/s), and the
common-range calibration can pass by adding the stronger bash. Rebalance that actual kit if these final
values remain: the cannon should deliver the clearly heavy primary hit and the bash a modest backup;
retain the overall sidegrade corridor, delayed splash and bounded node/candidate costs. Record primary
and sidearm contributions separately so a total alone cannot hide that identity reversal. Check Keeper's
close-burst identity at real body geometry as well. Do not force every area/line shape to equal output.

Also keep public combat claims accurate: the current cannon projectile travels straight; game.md calls
it an arcing shell. Describe the implemented path honestly. Do not claim all six have equal grouped
output: the controlled group fixture has large shape tradeoffs, while only the common single-target
fixture is calibrated near Warden. Preserve bot logs including failed/dead runs; any play-bot policy
change must be justified separately from weapon tuning and must not erase evidence or manufacture wins.

Report accuracy: the old report's "no debug controls" claim is contradicted by the real PNGs; correct
it after the harness repair. Sage's two recovered pickup stalls were at different coordinates/regions,
not the "same spot". Shared evolved missiles already have a 26px damage splash, so "no blast" is also
inaccurate; distinguish that existing shared splash from Knight's 48px straight-shell blast. Separate
sandbox import limits, partial test results and the director's independent evidence instead of claiming
an unrun complete pass. Do not weaken safe-margin/readiness checks because a sandbox fixture fails.
