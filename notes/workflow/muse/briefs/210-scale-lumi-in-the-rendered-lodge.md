# Brief 210: Scale Lumi in the rendered lodge

## The ask
The user asked for a real first-login tutorial room with a grounded guide
sprite, preserving character consistency and the existing playable heroes.
Finish that scene's actual rendering before native reminder work.

## Confirmed evidence
The director instantiated the actual `gate_lodge.tscn` with its loaded
controller, an isolated vault and an injected unnamed host at 808×360.
The post-seat-fix run has no script error. The speech card now sits at
`(124,231)` with size `(560,117)` and its Korean text is visible; do not
reintroduce that repaired wrapped-label seating defect.

Lumi's actual rendered frame height remains **871.151 pixels** in that
360-pixel-tall viewport. Her node scale is `(1.002475,1.002475)` and
the sprite scale is `(1,1)`: the 869-pixel packed source is being drawn
without the source-to-world conversion. The screenshot shows an enormous
boot dropping from outside the top of the room. The selected playable
hero is correctly small and grounded; do not enlarge or repack the old
hero to conceal the guide bug. `WORLD_HEIGHT` currently never reaches
the sprite scale.

The windowed contact harness also creates raw unscaled `LumiGuide`
instances. Its headless audit checks only the node origin, so it passes
while almost all of the actual guide is outside the screen.

One actual scene recovery boundary also fails: an initially empty local
name cache enters the greeting, then `load_adventurer_name` returns a
verified cloud handle with `intro_complete:true` and acknowledges caching
it. The real controller calls `_begin_practice` anyway. The director's
isolated `cold-completed` scene probe exits 1, with host `needs_lodge_lesson`
false but actual scene state 1/GREET and the named-practice speech, instead
of state 7/DEPART. Existing boot-completed tests start with the name already
in memory and miss this genuine fresh-install/cache-eviction recovery.

## Do
- Apply one common packed-source-to-world scale for every Lumi facing,
  then the scene's layout transform. Pick a grounded, readable guide size
  relative to the existing playable hero's actual opaque rendered body,
  rather than a source-pixel size or an assumed 64-pixel hero. Keep adult
  proportions but avoid an enormous guide beside the arrival. Preserve
  the four source dimensions, original proportions and common foot line.
- Ensure the source-local idle motion converts to a restrained world
  motion and does not shift the planted ground anchor. Keep the floor
  shadow coherent with the resulting body size and adjust guide personal
  space if needed. Preserve the already fixed speech seating.
- Register a real instantiated-guide transform/body-bounds assertion,
  not only `foot_local()==ZERO` or a layout-origin check. Audit the actual
  sprite rectangle and its opaque bounds under the real room camera at
  808×360, wider landscape, 808×606 and iPad mini's ~1.52 landscape ratio.
- Make the windowed QA harness render correct initial unnamed greeting
  as well as name/move/gate/departure states, with the same actual guide
  scale as the production room. The current room mode supplies a known
  name for `state=greet`, unlike its validate mode. Fix that fixture
  mismatch so the captured greeting proves the requested state.
- For the compact motion harness, print actual observed movement, dash,
  neutral stop and gate/departure state, and exit nonzero if the intended
  phases were not reached. Do not call a 120-frame recording complete
  merely because PNGs were written. A bounded selection of frames from
  a longer real-time lesson may stay within the 120-output-frame budget.
- After loading the verified account row from a cold cache, respect its
  acknowledged intro-complete bit and the host's actual cached readiness.
  A completed account proceeds to the ordinary Resume/confirmed fresh
  departure choice, without repeating name, movement or dash registration.
  Preserve incomplete claimed-name recovery and uncertain/offline cases.
  Register this actual scene boundary, including an existing living save;
  do not weaken the verified host plan guard or replace a failed cache
  write with an unverified completion. Completion must remain account-bound.

## Acceptance
The director's actual windowed room no longer shows the giant boot. Both
guide and selected hero remain visibly grounded and proportionate, with
the guide completely inside the room at rest. All four guide facings have
the same world scale and stable foot anchor. Existing 100 hero rasters
remain byte-identical. Five-language dialogue/name controls remain inside
the safe area at each real viewport; the director will render and inspect
them. Scene/entry/host and asset checks stay green.

## Do not
Do not write native reminders in this correction, touch credentials or
the network, change release counters, alter the original title/login
buttons, repack existing heroes, change locked settings, deploy, perform
git operations or recapture marketing screenshots.

## Verification
Run only the affected registered lodge/entry/host/asset checks with true
exit statuses and complete diagnostics. Small Godot checks have a
45-second bound. Do not repeat a sandbox-blocked old full suite. Update
the durable protocol/report with what the checks actually measure; the
director supplies real windowed rendering.
