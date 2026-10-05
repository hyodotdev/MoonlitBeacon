# Repair four observed render defects before release

The user wants all six heroes to physically swing or fire their held weapon,
then finish the replacement release. They explicitly retain every existing
store screenshot. Read the accumulated diff; do not rebuild settled features.

The director rejected the current rendering. Round 3 spent 31 minutes on
pending arena tests and the previous joint-math checklist, but the following
four defects remained unchanged. The director stopped that unfinished run;
it left no final report. They are the assignment, not optional polish. The
director has informed the user of the third-round state and is continuing
the already authorized repair. This invocation uses a new conversation in
the same copy, with the same safety settings, so the correction is read in
full instead of resuming the unfinished earlier checklist.

1. `scripts/actors/arm_rig.gd` maps positions through `cell_scale=0.255`,
   but `_upper` and `_fore` Sprites still render at scale 1. Correct the
   actual texture scale/pivot transforms. Their painted elbow and wrist
   endpoints must meet adjacent segments and the grip after transformation.
2. `scripts/actors/player.gd` gives `_sprite` `HERO_READABILITY_TINT` but
   AttackTorso/Legs/Nub and the ArmRig sprite descendants have no equivalent
   tint. The bright idle body visibly blinks dark on every attack. Preserve
   actual rendered brightness and relevant layer/light properties.
3. `_begin_attack_pose()` calls `_sprite.pause()` and freezes the leg strip;
   `_play_current()` returns during the attack. Repeated moving autoattacks
   slide with frozen feet. Continue the real gait and update the drawn leg
   atlas while attacking, including opposite aim, dash, pause and recovery.
   Judge thighs/knees as well as boots; a static upper leg plus moving boot
   is insufficient. Stationary feet stay planted. Original walk/idle sheets
   must remain byte-identical.
4. `tools/shot_hero_attack_motion.gd` still declares BOARD_SIZE 1280x720, but
   the actual movie output is 1616x720. The rightmost Warden row is cropped.
   Match the locked project's actual physical output without editing
   project.godot. Show all six full weapons/bodies at peak; all four close
   facings, normal and no-VFX cycles, and a repeated moving-attack segment.

Evidence already in `builds/hero-attack-review/`: round2-framed-motion-only.avi,
round2-framed-board.png, round2-knight-cycle/cycle.png. They are internal QA
artifacts, never marketing screenshots. Read director-factual-correction.txt:
Player.facing_vector() exists, so do not add a duplicate API.

Make regression checks observe actual drawn Sprite scale, transforms,
transformed painted endpoints, tint and live leg AtlasTexture regions.
The director's isolated probe passes even after replacing ONLY
ArmRig._layout() with an immediate return, while joint getters, weapon
timeline and VFX keep running. That exact negative control must fail after
your correction; restore exact source bytes afterward. Freezing Player's
joint target is a different probe and does not satisfy this criterion.
Preserve earlier assertions and combat damage/cadence/projectile behavior.

Run the focused motion and related arena/missile/painted weapon/gait suites
with clean completion, then assets/hygiene and harness validation. Keep
technical docs and the build log accurate about the actual observed scope.
Report changed files and commands. No auth/store/UI changes, counters,
network, git operations, device operations, marketing capture or provenance
edits. Do not claim final acceptance: the director will render both modes
and run the drawn-arm negative probe independently.
