# Brief 153: Repair the production title boot marker

## The ask
"로그인이랑 스토어 검증하고 메인까지 다 머지하고 확실하게 커밋한거 없게 된 상태에서 배포까지 진행해줘 리뷰 제출해"
Repair the confirmed debug capture boot readiness defect so the real 4.0.0 intro can be captured without weakening proof.

## Where things stand
The director ran the current canonical phone producer on the Pixel_10 emulator. Its final build and install succeeded, but restartTitle() in scripts/capture-store-screenshots.mjs failed after 90 seconds: "did not confirm debug title-ready proof and real title foreground within 90s". The private store_capture_title_runtime.ready file was absent. Existing persistent account/save files were preserved by the producer.

The marker writer is TestLauncher._signal_store_capture_title_ready() in apps/game/scripts/dev/test_launcher.gd. After four frames it looks for current_scene/Ui/Screen and Ui/Screen/Version. The actual production current scene is scenes/menus/production_entry.tscn, and the original title is its Title child. Thus the old writer returns without publishing. The accepted production_entry capture-state bridge forwards the correct full Title state (218 real-scene checks), but the separate initial boot marker was not covered or repaired.

## Do
- Resolve the actual original title under the production entry for the debug readiness marker, while retaining standalone title readiness behavior. Confirm real current scene identity, visible title screen chrome and current version. An open/occluding gate card, panel or loader must not emit clean-title proof. Keep the four-frame startup wait and release/debug boundaries.
- Add meaningful scene-level regression coverage for the marker itself under a real production current_scene and under the standalone title. Include a wrong-version or occluded-title negative case and non-title scene rejection. Use isolated temporary user data; do not touch a real player's identity/save/settings. Register the test if a new one is required, but prefer minimal related coverage.
- Leave the accepted rich capture-state bridge and its 218 checks intact. Document the exact cause and measured limits only in an appropriate existing release/capture handoff note if necessary.

## Do not
- Do not increase timeouts, remove the required marker, write it unconditionally, fall back to process-alive/PNG-size evidence, or relax foreground/resolution/current-version proof.
- Do not change gameplay, auth, IAP, save schemas, visible art/layout, native callbacks, package/version/build, project.godot, export presets, capture persistence restore, or any website/hosting files.
- No actual emulator/device/export/network/store operation. The director reruns the producer after judging and acceptance.

## Acceptance
- Real production and standalone title marker tests pass; occluded/wrong-version/non-title cases refuse a marker. Replacing the new resolver with the old current_scene/Ui/Screen assumption must fail the production marker test before restoring exact bytes.
- Existing production-title-capture and related dev/capture suites remain green. No unguarded release hook or unrelated source change.
- The director can rerun the final phone capture using the current attested build and pass the boot readiness step. That external operation is not claimed by the implementer.

## Deliverables and judgment
Minimal TestLauncher readiness change plus focused regression test/runner registration. The director reads every changed source/test, independently runs them, breaks the guarded production resolution to see failure, restores exact bytes, accepts normally, then rebuilds and captures the real device screen.
