# Brief 211: Keep Lumi's idle feet planted

## The ask
The user's repeated character requirement is consistency when moving and
stopping. Finish the new lodge guide without a floating idle pose.

## Confirmed evidence
Round 11 fixes the source-to-world size: the actual loaded room now draws
the guide frame at **42.104 world pixels** in 808×360, with common node
scale `(0.048451,0.048451)`. Preserve that correction and the repaired
cloud-completed recovery.

The director's actual instantiated-guide probe then advances its real
idle `_process` to quarter- and three-quarter-period phases and measures
the drawn sprite's bottom through its actual transform. The body foot
line moves **4.0 world pixels peak to peak**, while the shadow/root remain
planted. This is not a source-size hypothesis or a node-origin check:
`IDLE_BOB_WORLD_PX=2` translates the entire visible body, including boots.
The source-local motion was converted to a larger floating world bob.
`foot_local()==ZERO` and an unchanged guide node position cannot prove
that the painted feet stay on the floor.

## Do
- Keep the painted boots planted during idle. Preserve the common facing
  scale, foot line and all existing rasters. Use a restrained lantern,
  tint or shadow pulse if that is simpler than moving only the upper
  body; a simple idle is acceptable. Do not resize or distort the face,
  wiggle the feet, translate the whole body, or generate another art set.
- Register an actual rendered-body foot stability measurement across
  idle phases. It must fail on the previous 4-pixel motion, rather than
  asserting only the guide root is stationary. Inspect the actual sprite
  transform/opaque bounds for each facing under the production scale.
- Keep the current correct guide height, world shadow size, collision,
  speech seating, account guards and cold-cache completion recovery.

## Acceptance
The actual guide's painted foot line remains fixed (at most 0.5 internal
pixel peak-to-peak, including rounding) across idle phases and facings.
No face/height resize occurs. The lodge suite and asset freshness stay
green. The director will inspect the actual windowed contact/room/motion.

## Do not
No native reminders, network, credentials, deployment, git operations,
version/store changes, marketing capture, old hero repack or broad cleanup.

## Verification
Only the affected lodge regression and small source checks are needed;
do not rerun every asset generator or the unrelated full suite for this
bounded correction. Use a 45-second Godot bound, true exit status and full
diagnostics. Update the exact idle behavior in the report/protocol.
