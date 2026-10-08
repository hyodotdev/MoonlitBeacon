# Brief 217: Keep the actual name action above a tall keyboard

## Confirmed remaining defect in brief214
The device-to-viewport conversion is repaired. But clamping the form's
lift to its safe top cannot fit its existing228px panel into a shorter
visible area. Current real Japanese name controls at808x360: panel
(124,58,560,228), field(140,138,528,44), confirm(140,230,528,44).
With432devicepx at3x (144occlusion), keyboard top216, current capped
lift58 puts confirm bottom216 with no8px margin. With540devicepx at3x,
keyboard top180, the same cap leaves36px of confirm below the keyboard.
Moving a whole228px panel to the top does not shrink it or make its
lower action visible. Current math tests only pin the clamp, not actual
form/action clearance. Director actual-autoload window probe reports
this; initially missing fake.display empty was a fixture bug, corrected.

## Do
Adapt the actual visible name UI while the native keyboard is present:
compact/reflow optional portrait/header/explanatory copy or scroll only
nonessential content, keeping the actual focused field, error feedback
and confirm action visible and tappable above the keyboard. Preserve the
original skin, composition/IME, typed value, retry state, localized copy
and full layout restoration when the keyboard disappears. Do not merely
allow a negative panel top or assert clamp math. Support both standard
phone landscape and the tall iPad, native scale1/3/noninteger/letterbox.
Bound unreasonable all-screen keyboard cases honestly (hide keyboard or
an explicit usable escape), without promising impossible zero-height UI.
Actual keyboard conversion must keep device and viewport units separate.

## Acceptance
For realistic occlusions144/180 at360-high and tablet occlusions, actual
rendered field/confirm/error feedback bounds stay inside the available
safe rect with the requested margin, at all five locales, including
taken/offline/invalid feedback. The same production layout function/hook
must run in tests and live `_apply_keyboard_shift`; do not test only a
separately mirrored planner. Restore original panel/controls after hide,
no per-frame oscillation. Add registered regression based on actual
controls, plus an isolated render harness for the director to inspect
keyboard-adapted UI without claiming that is native keyboard delivery.
Preserve corrected hero placement and the settled contact/lesson clip.

The actual lodge Camera2D defaults to idle while project physics
interpolation forces physics, producing a warning when the packed scene
is instantiated. Set its intended callback before tree entry (scene
property) if this is the only cause; do not alter project interpolation.

## Boundaries
No native reminders/auth/wallet/rules/network, oldhero raster, SDK/privacy,
versions/store screenshots, git actions or tests-budget weakening. Affected
bounded Godot/locales/compile checks, true exits and raw diagnostics.
Director final round17 actual probe after implementer completion confirms
540devicepx ->180viewport occlusion; confirm stays216>keyboard180,36px
covered (clean assertion exit1). Rawgate-keyboard-tall-clearance-round17-final.log.
An earlier probe ran during a negative-control mutation and returned540
occlusion: discarded, not product evidence. Use the final restored run.
Stock round17 contact now captures four silhouettes42px with exit0 and
no ERROR, but its new Camera2D also defaults to idle and warns. Seat its
physics callback before tree entry while closing that warning too.
