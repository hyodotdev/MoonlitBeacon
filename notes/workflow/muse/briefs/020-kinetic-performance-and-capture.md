# Correction brief 020: Keep the late cannon budget and capture claims

Continue tag `20260930-2321-kinetic-hero-weapons-and-audio` after completed round 3.
Retain briefs 017–019 and the approved music bytes. This is a narrow correction
of two newly confirmed final-review gaps, not another redesign.

## The ask

“오 음악 좋네 합격 그리고 수호자 나올떄는 좀 더 빠르고 박진감 넘치는 음악 나와도 좋겠어. 그리고 음악을 2개만 번갈아 쓰지말고 3개씩 랜덤으로 교차하게”

Keep the delivered six-song music and six primary weapons stable while finishing
performance and trustworthy visual evidence.

## Director evidence

- The director ran the real `test_late_game_performance.tscn` against round 3:
  `builds/director-late-performance-r3.log`, exit 0, 67 checks. The Knight Lv40
  sample keeps 40 live spirits, power 8, eight shells, 16 detonations and 1200
  total candidate visits over 90 physics steps; `node_peak=1202`. The source
  explicitly dropped the Knight <=1200 assertion. Brief 017's 1200-node budget
  was not withdrawn; reporting the excess is honest but does not satisfy it.
  The grouped default is 1141 nodes. This is a small measured excess, not a
  request for a speculative large refactor or a stricter candidate-work rule.
- The director's normal windowed `shot_weapons` run, tag `director-r3-guns`,
  passes 112 checks with 48 hero PNGs. Bodies face the four named sides, but
  some up-labelled strips show guns aimed downward because other moving
  enemies can become the actual aim. The header says all four aims are
  photographed. The check establishes body facing and any primary visibility,
  not alignment of the actual primary aim with `side`.
- The director's controlled live-spirit operational probe (natural openings,
  production shots, own fixture spawns suppressed and targets stationary)
  records true up aims: Keeper (-0.121,-0.993), Knight (-0.076,-0.997), Sage
  (-0.070,-0.998), targets at (0,-90), (0,-140), (0,-150). This confirms the
  round-3 vertical gun code works; do not redesign it or change game targeting
  to repair a capture fixture. `builds/director-r3-aim-observe.log` is the
  evidence. Four-body-facing coverage and four-firing-direction coverage are
  separate facts.

## Do

1. Preserve the Knight <=1200 node assertion on the real Lv20/Lv40 samples.
   Reduce the measured transient visual/node overhead minimally; do not raise
   the cap, lower 34/40 spirit density, weaken shell output/lanes/splash,
   change power/cards/cadence to avoid the worst sample, or remove impact
   feedback. Preserve the 256-visit average budget, floors and actual cannon
   attacks. Repeated samples must pass with the existing density and real
   attainable non-evolved cannon build. Keep warmup spikes diagnostic and
   distinguish the defined sample window from setup, as before.
2. Make `shot_weapons`'s four-direction evidence reproducible and honest.
   A clearly labelled controlled stationary-target staging is acceptable;
   retain real terrain, hero openings, actual production attacks/hits,
   strong build and recoil, draw-synced four frames over 0.6s, four bodies,
   hidden debug overlays and safe isolation. Assert actual primary aim points
   to the requested side when anchoring a strip; do not infer aim solely from
   body facing or existence of any projectile. Avoid unrelated enemies
   retargeting the strip. Keep existing natural bots as the gameplay evidence.
   Wait until beacon choice alpha is fully settled and choices are armed
   before photographing all five locales, instead of two fade-in frames.
3. Update the report/build log with measured corrected evidence and explicit
   host/controlled-capture limitations. Keep the earlier failures in history.
   Run related registered regressions; the director runs the original full
   suite and actual display captures. No new feature or approved audio rebake.

## Acceptance

Real Knight samples keep 34/40 spirits and repeated shell detonations,
node_peak <=1200 and aggregate visits <=256 per measured physics step.
The registered assertion catches reverting the overhead correction (negative
control). All six early/strong weapons photograph true requested primary
facings/aims; gun vertical origins still agree with their actual muzzle.
Five locale beacon captures have alpha >=0.999 and armed choices. Keep commands,
copy, report and source consistent; no test waiver or fake hit/VFX.

## Constraints

No git/network/device/store/user-save operations; no protected-path edits.
Do not touch approved audio arrangements, music bags, isolated-save guards,
IAP identity/ownership, hero price/HP or the legacy math-neutral profile seam.
Only implementation, related tests/harness and their existing docs/build log.

## Original-runner counterexample found after the report

The director ran the original shipped `pnpm test:game` after fresh imports, not
an isolated replica/partial command. It exits 1 at `test_missile_loop.gd`:
12/153 failures, every failure asserting straight/guided shots start and aim
from the candle. Copy log `builds/director-original-full-game-r3.log` records
all preceding steps. Your standalone missile-loop run passes 141 because its
fixture state differs; that does not establish the sequential runner passes.
The test instantiates Arena without pinning its hero and `_test_moonlight_projectile_origin`
assumes every equipped profile shares `moonlight_origin()`. Gun-primary profiles
now intentionally fire from the coherent gun muzzle, while melee backups retain
the candle. This new contract must remain correct in the sequential runner.

Repair the affected regression's fixture/expectations to distinguish the intended
gun-primary muzzle from the preserved melee candle, preserving straight AND
guided spawn/direction/inner-lane checks. Explicit profile staging is acceptable;
do not weaken or delete origin assertions, universally move guns back to the
candle, or restore the old false premise just to make a test green. Keep all six
profiles' real origins covered by registered meaningful checks and rerun the
original command if the sandbox permits; report any actual import limitation
honestly and let the director run it outside the sandbox. Check later tests for
the same shared fixture-state assumption, fixing only confirmed failures.

Round 3 actually ended at `2026-09-30T20:47:29Z`, not its report's future
~20:50 completion claim. Use the runner's actual observed time or omit a completion
clock claim; do not predict a timestamp and present it as measurement.
