# Brief 156: Resolve the embedded title in the distribution probe

## The ask and measured failure
"로그인이랑 스토어 검증하고 메인까지 다 머지하고 확실하게 커밋한거 없게 된 상태에서 배포까지 진행해줘 리뷰 제출해"
The final phone producer retry passed its repaired boot marker and reached the direct-distribution installed-binary probe, then failed after 30 seconds. Actual state proved direct_distribution_feature=true, storefront_enabled=false, store_state_unavailable=true, cached_paid_entitlement_fixture_present=true, owned=false, ignored=true, restored=true. But title_screen_visible=false and title_store_button_present=false, so ready=false. No new canonical screenshots were published; persistent files were restored.

The confirmed cause is apps/game/scripts/dev/store_capture_probe.gd _direct_distribution_state(): it still resolves Ui/Screen and Ui/Screen/StoreButton directly on current_scene. Production current_scene is ProductionEntry with its original title under Title, exactly the embedding repaired for the separate marker. The richer debug_prepare/store_capture_state forwarding already works and must remain intact.

## Do
- Resolve the real original title for the direct-distribution UI checks under production and standalone roots, with explicit real-scene identity and fail-closed behavior for non-title/missing/occluded titles. Reuse a suitable existing title resolver if it does not introduce a circular preload; otherwise keep the minimal resolver properly scoped and tested.
- Keep the actual live Shop singleton, direct export feature, unavailable state, paid SKU memory fixture, owns() denial, immediate byte-equivalent entitlement-array restore, and every existing exported field/host assertion. Do not touch the disk ledger or invent success from a missing button.
- Add a focused real-scene regression covering production and standalone title UI fields, non-title rejection, and an occluded production title. A headless engine without the export feature need not claim the final direct-export readiness; the director's real installed binary proves that. Verify title button presence/visibility/disabled state from the actual embedded nodes and preserve the Shop restoration boundary. Register new coverage if needed.
- Inspect other debug capture helper current_scene UI lookups for this same embedding mistake and report any confirmed remaining one; fix only directly attached proven cases. Generic rich capture forwarding stays unchanged.

## Do not
No timeout extension, unconditional ready, weakened feature/entitlement/store/button proofs, persistence changes, game art/layout/gameplay/auth/IAP logic, website/config, package/version/build changes, actual device/export/network/store operation. Do not alter the native Shop or real store-account data.

## Acceptance and judgment
New related scene tests and the existing marker (45), rich title (218), clean-UI (64) and host capture-boundary suites pass. Reverting embedded-title resolution to the old root lookup must fail the new production UI regression, then restore exact bytes. The director reads all source/tests, repeats that mutation and related checks, accepts normally, and rebuilds/runs the real phone producer to prove the full direct-distribution boundary on the installed APK. Do not claim that external proof from the copy.
