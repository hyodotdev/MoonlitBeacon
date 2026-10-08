# Brief 223: merge app-owned iOS privacy declarations

## The ask
"코인은 그리고 반나절마다 출석하면 2코인씩 주고 반나절마다 알림을 보내면좋아 지금 출석하면 코인 받는다고. 그리고 알림은 설정에서 안받게 할 수도 있게 해야하고"
Finish the native iOS integration of the accepted attendance reminders.

## Where things stand
Round 1's scanner correction is present and must be preserved. The director stopped its idle CLI after it produced no new events for over twenty minutes; no approval rejection was reported. The root Android release/debug native builds, wrapped debug APK and actual emulator opt-in/alarm/cancel tests pass. The director's real `node scripts/ios.mjs capture-build-isolated` export succeeds but Xcode fails with `Multiple commands produce .../MoonlitBeacon.app/PrivacyInfo.xcprivacy`: Godot exports its own app-root manifest and the new identity plugin registers another root file of the same basename.

Godot's generated root manifest contains FileTimestamp reasons DDA9.1/C617.1, SystemBootTime 35F9.1 and DiskSpace E174.1/85F4.1, plus tracking=false. The new app-owned reminder manifest adds UserDefaults CA92.1. Both declarations must survive in one app-root resource. SDK privacy bundles must remain byte-identical and independent.

## Do
- Resolve the real duplicate app-root resource by merging the app-owned UserDefaults declaration with the Godot-generated app manifest through the owned export pipeline. Preserve all engine entries and any unrelated future entries; retain tracking state. Choose an explicit, fail-closed implementation, not a blanket filename filter.
- Register meaningful tests for the resulting generated manifest and single Xcode resource registration, including loss-of-reason and duplicate-resource regressions. Keep existing required SDK bundle tests and static framework inputs intact.
- Run the focused tests and `pnpm verify`; report concrete failures and exact commands. If the copy lacks generated imports or native dependencies, distinguish that environment limitation from a source defect. Do not spend a long run repairing an unrelated copied cache.
- Briefly update the identity README to explain the app manifest merge where useful.

## Do not
- Do not edit SDK manifests, privacy bundles, credentials, signing, locked project values, release counters, existing marketing screenshots, art or game behavior. Do not delete required privacy declarations to make Xcode pass.
- Do not edit the director's notes or briefs. Do not access the user's devices, network or stores.

## Acceptance
- One generated app-root PrivacyInfo.xcprivacy includes all measured Godot reasons and app-owned UserDefaults CA92.1. Xcode has exactly one root output for it.
- Every existing staged SDK privacy bundle remains unchanged.
- Focused registered tests pass and still fail meaningful negative controls; the director will repeat the actual root isolated iOS export and Xcode build.
- Preserve the complete-key scanner fix and its typo detection. Full verification is green or failures are reported accurately.

## Deliverables
Narrow export integration, registered regression tests, identity README clarification and a concise report. No assets or gameplay changes.
