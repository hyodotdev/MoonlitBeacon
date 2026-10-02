# Brief 027: preserve the entire clean phone combat viewport

## The ask
"너가봤을 때 어때 훨씬 쎄련되고 재밌어? 꼼꼼히 2~3번 점검해주고 괜찮으면 머지하고 스토어 스크린샷 등다 새로 올리고 직접 배포도 해줘"
The director is examining the actual final submission images before uploading the renewed game.

## Confirmed visual issue
Current phone originals are clean 2424×1080. Final Play screenshots use notes/release/store-assets/screenshots.json's `crop_bottom: 180` for the three combat entries (01 barrage,02 guardian,03 core). At 3× scale this cuts the lower 60 internal pixels, deleting the new hero/story dialogue ribbon and clipping the bottom-right dash control. The director viewed all three real Korean composite images and the original captures; the crop dimensions confirm the defect. _render_play_screenshot in apps/game/tools/build_store_graphics.py crops height to900 before fitting1920×1080. The current renderer can already fit the entire original viewport, leaving space for captions/brand. Tablet screenshots already preserve the whole screen. This is storefront framing, not game runtime.

## Do
- Preserve the full clean viewport in the three phone combat marketing images by removing the obsolete crop or setting its contract to zero. Update existing crop-contract checks/fixtures only if needed; prefer the smallest actual fix, and retain strict current screenshot/source/provenance checks.
- Verify full-source dimensions reach the real Play compositor and relevant existing boundary/package tests pass. Add a meaningful guard only if existing tests do not cover full-viewport cropping; avoid a test that merely repeats the new literal.
- Record the observed clipped dialogue/control, exact fix and measured checks in notes/plans/3-0-0-build-log.md. Existing game/UI/hero-preview sources remain unchanged. Correct final screenshot-status wording only to match the director checkpoint: source captures done but phone proofs become stale when their pinned screenshot config/generator changes; tablet source/build maps exclude the screenshot JSON and generator, so they can remain current after unchanged strict validation.

## Do not
No game code, art, audio, locale, IAP, prices, version/export preset, capture producer/signature or fingerprint-exclusion change. No device/capture/store/network/git operations. No forged capture proofs, updating report hashes or weakening readiness. Keep captions, app branding and final dimensions; do not redesign the storefront during this task. Do not change director workflow records.

## Acceptance and delivery
- The generated phone compositor preserves all2424×1080 pixels of the three combat originals; dialogue and the complete dash circle are within the output frame. Current raw title/shrine/preview and tablet/iPad policies remain correct and unmodified.
- Existing related Node boundary/package suites pass; any adjusted guard must fail an intentionally restored180-pixel combat crop. Report exact source/config changes and commands.
- Deliver only the screenshot config, narrowly necessary generator/test changes and truthful build-log entry. Production runtime stays byte-identical.

## Director judgment
Review the actual diff; independently check affected tests and full viewport composition, accept through Muse, then rebuild only the invalidated phone capture proof and regenerate the authorized current submission set. Preserve the already validated tablet reports if the unchanged strict checker passes. No remote action is claimed.
