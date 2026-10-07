# Brief 214: Keep the player visible during lodge dialogue

## Confirmed evidence and task
The director rendered the actual lodge at 880x360 (the attached Android's
ratio) in Korean greeting state. Opaque bounds from the current real
Player/Sprite frame and actual canvas transform are x447.4 y209.1428,
20.145x27.795. The actual bottom dialogue card starts y231, height117:
5.938px of the player's legs/body are covered. Source WIDE_HERO is (.52,.66).
The full raw director log is gate-hero-occlusion-fixed-probe-round13.log.
The player should remain clearly visible while Lumi introduces the room.

Adjust only the room's initial wide spawn/placement to keep the opaque
player silhouette above all localized greeting/name-recovery dialogue,
with a small visual gap. Keep the spawn on the painted traversable floor,
away from Lumi's desk/personal space. Do not scale, regenerate or change
any old hero raster; do not move every dialogue to cover another actor.
Tablet compositions and walk/dash/gate lesson must still be usable.

## Acceptance
Actual player opaque rect and visible greeting dialogue do not intersect
for all five languages at808x360 and880x360; the complete player and guide
are visible. Existing tablet views, actual movement/dash completion and
living-save departure stay correct. Add a meaningful bounds regression;
do not weaken existing safe-area or sprite-consistency tests.

## Constraints
No network, stores, versions, auth/reward changes, SDK bundles, original
hero image changes, git actions or marketing capture. Use the existing
lodge art and Lumi. Bounded affected checks only, full diagnostics.

## Also close the measured keyboard coordinate boundary
Godot's DisplayServer keyboard height is in DEVICE pixels (official
DisplayServer docs and pinned Android get_vk_height delegation); lodge
controls and get_visible_rect() are in stretched VIEWPORT coordinates.
The current `_apply_keyboard_shift` passes the raw pixel height directly
into `keyboard_shift_for` without the inverse screen transform. Existing
Screen.viewport_safe_rect already uses that inverse for display-safe-area.

Director actual GateLodge static method, autoload-equipped isolated scene:
physical keyboard432px at3x, viewport360px, confirm bottom274 returns
shift354px, field top -216 and confirm top -124. Normalized144 viewport
pixels should produce66px. Full raw log gate-keyboard-units-scene-round14.log
clean exit1; an earlier bare-script invocation lacked Vault and is not
accepted evidence.

Convert the keyboard's occupied screen rectangle through the actual
viewport screen transform (handling letterbox/translation rather than
assuming a fixed3x). Bound/adapt the form when little space remains so the
name field and confirm stay visible and usable above the keyboard; avoid
negative top displacement. Keep measured-from-original-seat behavior and
restore exactly when hidden. Diagnostics must clearly distinguish device
height from viewport occlusion; preserve no-typed-name/no-provider-data.

Register scale1/3/noninteger and tall/short keyboard regressions against
the actual production conversion/layout. Director will inspect actual
Android/iPad keyboard screenshots/bounds; desktop height0 never claims
native keyboard verification. No old hero raster changes.

## Keep the director visual harness clean
Actual `lodge_review mode=contact` currently calls camera.make_current()
BEFORE adding Camera2D to the tree, generating an engine ERROR even though
it captures and exits0. Seat/enable the camera first, then make it current;
keep the four-facing board and source consistency audit usable. Actual
lesson clip completed moved266.9/dashedtrue/stoppedtrue/departtrue in126
simframes/26PNGs, so preserve that working actual-input path.
Director viewed the actual contact PNG: first three actors are expected
~42px, but the last/right actor is huge and partly outside the image.
Do not conclude its source art is inconsistent: all frame-height contracts
already match. The harness captures immediately after adding the final
actor and Camera2D under physics interpolation. Ensure all initial actor
scales/poses and camera interpolation settle/reset before capture; check
what was actually rendered, not only global transforms before draw.
Audit four visible silhouettes in the captured board. No raster resize.
