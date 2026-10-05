# Brief 120: Android JNI identity dispatch and honest settlement

## The ask
"Google, Apple not ready하지말고 로그인 구현해줘 firebase로" and "ipad 안드로이드 실기기 다 연결되어 있으니까 제대로 테스트 해주면서 해".
Configured native identity must reach the real SDK and settle every attempt, including anonymous guests and synchronous refusals.

## Why, and what good feels like
A player tapping Google sees the actual provider sheet or a truthful recoverable result. A guest obtains a Firebase anonymous session while retaining the established public ID and can subsequently link a provider. A button must never remain busy after a synchronous terminal response.

## Where things stand
The director provisioned the project's native public configs, enabled Google/Apple/anonymous in Firebase, registered Android signing fingerprints, and deployed the separately verified game-scoped Firestore rules. These credentials and network operations are outside the implementer's copy. A properly wrapped 4.0.0 debug APK with configured Google and anonymous auth was installed preserving data on both Android emulator and physical device. Actual Guest resulted only in a local guest; owner readback showed zero Firebase auth users and zero new profiles. Tapping Account's Google link showed indefinite Signing in without a native provider sheet. Cancel returned to the same public ID. These are observed failures, not completed login proofs.

Confirmed dispatch defect: `addons/moonlit-identity/moonlit_identity.gd` `_native_call` and `_native_reports_draining` use `Object.has_method` on the Android engine singleton. Godot Android plugins are `JNISingleton`: their Java method registry is separate from Object's bound-method registry. `has_java_method` is the documented API for checking these methods. Actual locked Android template shared library contains JNISingleton and has_java_method; compiled plugin annotations and method names are intact. Primary reference https://docs.godotengine.org/en/4.6/classes/class_jnisingleton.html and current official source https://raw.githubusercontent.com/godotengine/godot/master/platform/android/api/jni_singleton.h (has_java_method checks method_map) and jni_singleton.cpp (only binds has_java_method; callp falls back to method_map after Object::callp fails). These concise facts are provided because your copy has no network.

Two adjacent confirmed logic gaps: `scripts/net/player_account.gd` `_fold_sync_receipt` ignores terminal `unsupported` and `not_configured` receipts, so ProductionEntry that already shows busy receives no terminal UI signal. `scripts/ui/production_entry.gd` `_linkable_providers` hides every link when any cloud_uid exists, including an anonymous Firebase guest that should be linkable. Other copies are independently changing GateAccountPanel and GateHeroForecourt; do not touch those files or gate-entry-layout/states tests.

## Do
- Correct native method discovery using the Java registry when exposed by the actual native object, while preserving ordinary iOS GDExtension and existing normal fake behavior. Use the same reliable discovery for dispatch and cancellation/draining. Do not blindly invoke absent methods or merely force readiness to true. Inspect all nearby native method guards for the same confirmed error.
- Fold synchronous terminal unsupported/not-configured attempts into the existing honest, recoverable production outcome path. Keep busy/request locks, late callbacks, mutation-draining semantics, cancellation, timeout and ID ownership intact. A terminal answer must unblock the actual UI without inventing a successful login.
- Allow configured providers to link an existing anonymous Firebase guest without changing its public ID/UID or hiding the Account link. Preserve existing authenticated-account behavior and conflict/switch/deletion protections; never merge unrelated accounts.
- Add meaningful registered regressions for Java-registry authority and cancellation, synchronous refusal settlement through ProductionHost/Entry, anonymous link availability versus authenticated accounts, and no ID/binding mutation on refusals. Prefer extending existing identity/host suites, not the UI suites owned by other packets.

## Do not
Change provider logos/layout/consent, Account panel, title/forecourt, source configs/secrets/backend rules/native SDK versions/version lock/presets, package identity, stores or release artifacts. Do not add personal data or tokens to logs, tests, briefs or notes. Do not weaken existing callback or privacy guarantees. Do not author backend credentials or declare physical SDK success from a fake.

## Acceptance
Director independently runs affected identity/host tests, smoke/hygiene, negative controls that restore the old Java-method guard and ignored synchronous refusal and must fail, then accepts only the narrow diff. The actual rebuilt Android APK must create a Firebase anonymous user/profile via real Guest and show the real Google provider UI instead of indefinite busy. That native test is the director's job and may require a correction round. Test fixtures must model Java discovery meaningfully, with Java oracle false refusing an otherwise exposed stand-in method, rather than only using ordinary GDScript fake methods that already made the defective guard pass. Reduced or absent SDK/config is still a terminal honest unsupported/not-configured path.

## Deliverables
Narrow bridge/account/production-entry source changes, registered affected tests/support and an author-only evidence note. Preserve the runner's existing suite registration if extending current tests. Do not edit GateAccountPanel, GateHeroForecourt, gate-entry-layout or gate-entry-states files; other packets own them.

## How the director will judge
Read the complete changed hunks; rerun test_player_identity, test_cloud_account, test_identity_registration and test_production_host as appropriate; prove the tests reject the original defect; build through the wrapper and repeat actual native Guest/provider/Cancel with server readback and stable public ID. No new native credential may be printed or sent to the model.
