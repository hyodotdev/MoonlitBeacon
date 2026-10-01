# Correction brief 019: Preserve primary weapon sound on simultaneous clocks

Continue completed round 2 of tag `20260930-2321-kinetic-hero-weapons-and-audio`.
Retain brief 017 and 018 and all their completed corrections. The director rechecked
both sound-priority and growth-release probes against the completed round-2 source:
both still exit 1 (`builds/director-*-probe-final-r2.log`). None of this tag has
been accepted into the real tree. This is the complete confirmed correction bundle.

## Director evidence

The director ran the actual `Arena._process(1.0/30.0)` path with a Knight,
one durable target 37 world units to the right, both real attack clocks ready,
and normal combat logic enabled. The target received the melee hit and one cannon
projectile was created in that same tick. However, `WeaponSfx.stream` was
`weapon_sword.wav` at -15 dB. The earlier sidearm call armed the shared 70 ms gate;
the later primary cannon call was swallowed. The process exited 1 with the expected
primary cue absent. Evidence is `builds/director-primary-audio-probe.log` and its
ignored operational probe in this copy. The separate existing wiring test waits
0.1 s between clocks and therefore cannot catch the live simultaneous ordering.

## Required correction

Give the signature primary sound precedence over the quieter sidearm when both
real clocks fire in one tick or within the same gate. Keep bounded nodes/voices,
rate floors, settings, ducking, cleanup and real attack clocks. Do not disable the
sidearm or weaken its production damage to satisfy an audio assertion. A bounded
priority rule or separate capped primary/sidearm voices is acceptable; document
the retrigger behavior honestly. Ensure the melee heroes retain their primary cue
when a ranged backup follows, and the ranged heroes retain theirs when a melee
backup precedes. Cover all six through the real simultaneous arena process, not
just direct calls separated past the gate. Check evolved and ordinary volleys.

Re-run related audio, weapon and profile tests and the deterministic generator.
Keep the final audition, report, references and verification counts accurate.
No production edits by the director, no git/network/device/store/user-save work.

## Finish the user's requested musical rotation during a continuous encounter

The user asked for three tracks each to alternate randomly. The current draft draws
from three only at run/region/guardian/return events, then loops one short track
indefinitely within that mode. Complete that rotation at the end of a whole track
as well, so staying in one terrain or a longer guardian fight still hears the
three-song bag. Preserve full musical phrases and the no-immediate-repeat rule;
do not cut tracks every few seconds or on attack/hit. Retain stable encounter and
return switches, approved assets, independent music RNG, pitch escalation/cap,
pause/resume, mute and bounded scene release. A minimal implementation using the
actual playback lifecycle is enough; no new dependency or unbounded timers/nodes.

Add real playback coverage where the mode remains unchanged past a full track and
the next in-pool track starts, both arena and guardian. Check that a mode switch,
paused choice or release cannot leave a stale continuation selecting the wrong pool.
The playback boundary must follow audible playback, including at `Engine.time_scale=3`
used by existing smoke tools; a scaled gameplay countdown must not truncate the
music to one third of its phrase. Reset the time scale after the isolated check.
Keep the whole imported-sample endpoint tests and the generator's six distinct tracks.

## Actual round-2 display evidence to recheck against the final source

The director also ran the updated harness windowed with Dummy audio, Keeper/Knight/Sage,
early builds: 72 checks, 48 PNGs plus ten beacon PNGs, exit 0. Evidence in this copy:
`builds/director-r2-guns.log`, `builds/shots/weapons/director-r2-guns_*`, and the director's
inspection board `builds/director-r2-guns-four-directions.png` (copied here for judging).

The horizontal hand relocation now clears faces and makes the three guns distinct. However,
the actual up-shot Sage screenshot still draws the long rifle vertically through the nose/face.
Use a credible side-hand grip/aim offset that leaves the face readable for vertical as well as
horizontal aim, without floating the weapon far away. Also align the projectile/cast origin
with the actual held gun's muzzle: current `WEAPON_GRIP` is (0,-8), flashes sit at the gun tip,
but `moonlight_origin()` remains (0,-20). A rifle flash at hand+(16,0) and a projectile starting
at candle+(0,-20) do not describe one fired shot. The current comment claiming the candle
'bridges' the two is not the requested gun/cannon presentation. Preserve melee heroes' small
moonlight backup if appropriate; preserve damage, targeting and growth contracts while moving
visual/fire anchors coherently. Tests should compare actual world muzzle/launch positions and
flight directions on the real arena path, not only a constant or posed rig. Inspect all four
aim directions and recoil settling.

The harness's four `side` values currently alter target placement only. In the director's board,
all twelve bodies remain the front-facing sprite. Do not call this four-body-facing evidence.
Retain the four firing directions, and provide actual four body facings through the established
movement/facing contract as well. Keep screenshots and evidence labels accurate. Repair the
remaining header claims ('bare Lv1' and a '0.2s strip') to natural hero openings and 0.6s total
for four frames separated by 0.2s. Keep real terrain, hidden debug overlays and live attacks.

The director confirmed these items remain in the completed round-2 source.

## Keep final player-facing stat claims comparable

Round 2 has made the descriptions weapon-first but still says flat `dmg +25%`,
`dmg -16%`, etc. These are unqualified cross-hero comparisons even though the
weapon table now supplies different private bases, lanes and cooldowns; opening
relics can further change actual starting output. Complete brief 018's accuracy
requirement: remove that flat damage-percent comparison from player descriptions
(or make a genuinely meaningful, independently measured comparison). Prefer concise
weapon/play style plus hearts, shared-base move/dash tradeoffs and named opening
relics. Preserve the actual resource multipliers and ownership/prices; this is a
copy correction, not a balance change. Keep all five translations and independent
Keeper production/test/store capture literals synchronized without deriving
expected text from actual text or weakening ready/layout assertions. Reconcile
obsolete comments such as `HeroPreviewPanel._refresh_motion` claiming that all six
have the same damage/fire rate, while retaining the legacy projectile-profile
math-neutral boundary and honest labels for its preview.

One small confirmed reference correction: `_render_arena_watch` emits eight arpeggio
slots per four-beat bar, spaced half a beat apart, but its docstring/comment and
manifest call those sixteenth notes. Those are eighth notes at the stated 138 BPM.
Correct that wording to the implemented rhythm; keep the audio bytes and musical
arrangement. Guardian Storm already calls its identical eight-slot subdivision
'racing 8ths'. Do not rebake or change the approved motif just to repair prose.

## Confirmed bounded growth-voice release omission

The director started the real overcharge cue on `GrowthSfx`, awaited the real
`Arena._release_audio()`, and observed `growth_playing=true` and `stream_present=true`
afterward. Probe exit 1: `builds/director-growth-release-probe.log`. The new growth
player is missing from the explicit pre-transition release path. Include it and
check every arena combat player after release, while a long cue is actually active.
Keep the existing release-before-scene-swap contract and audio-thread settling;
waiting for a cue to end or asserting only that the eventual arena frees is not
proof of explicit release. The operational probe manually released the growth
player after measuring, so it did not leave a running sound/node behind.

## Confirmed description layout regression; remaining acceptance gaps

The director independently ran `pnpm godot:isolated --timeout 240
res://tests/test_shrine_portraits.tscn` on round 2: exit 1, eight failures out of
618, all four frame/title/close-button safe-margin checks in both English and
Japanese. Evidence is `builds/director-shrine-r2.log`. The implementer's own
fresh-import comparison establishes that the original HEAD descriptions pass,
and the new round-1 and round-2 descriptions both fail. This is a regression
introduced by this deliverable, not an unrelated baseline defect or a new task.
Keep concise five-language weapon descriptions within the actual shrine/preview
layout. Prefer the copy simplification already requested above; change layout
only if still necessary. Keep all existing margins, ellipsis/readiness checks,
and independent copy contracts meaningful. Inspect the real English/Japanese
screens after the complete copy change. Do not accept eight known failures or
weaken the checks. Also correct the report's statement that round 1 was accepted:
no round of this tag has been accepted into the director's production tree yet.
Use actual runner times for any timing claims: round 2 ended at
2026-09-30T19:03:32Z, so the current report's completion claim of ~19:55 UTC
cannot be an observed timestamp. Keep incomplete full-sweep results explicitly
incomplete; the director will run the original full runner after the final patch.

Brief 018 explicitly requires isolated-test-save enforcement before arena
instantiation. The two newly introduced tests (`test_hero_weapons` and
`test_combat_audio`) and the weapon capture harness currently rely solely on
the wrapper without an entry guard. Add the repository's established isolated
test-root guard to those entry points, before their first arena/save operation;
retain the safe documented wrapper commands. Confirm a missing isolation marker
is refused before changing user state.

The new cannon budget fixture creates one shell with forty fake targets and
reads `_frame_bodies.size()` before detonation. That proves one array's length,
not total actual cannon candidate work at the required late-game density. The
existing live Lv20/Lv40 samples still choose the default hero and collect only
MoonMissile diagnostics. Complete 018's measurement with the real Knight,
34/40 spirits, real growth and repeated actual volleys: include cannon sweep,
shared geometry-cache work and detonation visits in the total over measured
physics ticks, together with any missile work and node peaks. Preserve the
existing aggregate budget (256 visits per physics step on average), not an
invented instantaneous peak rule; wall-clock timing remains diagnostic only.
An ignored operational measurement plus a meaningful registered regression seam
is acceptable. Do not label a forty-element pre-call array as a complete live
performance proof, and optimize only if actual measurements establish a problem.
