# Brief 047: Compile the native SDK bridges and hold mutation locks

## The ask
The user wants real Google game / Apple / guest login for 4.0.0. Continue the native identity copy; identity readiness must be supported by actual SDK builds and safe asynchronous mutation behavior.

## Confirmed evidence
The director repeated your tests: 144 Godot cases and 25 Node tests pass. A real Android build using Gradle 8.7, JDK 17 and the Android SDK fails immediately: generated settings.gradle line 1 begins `# Rendered ...`; Groovy reports `Unexpected character: '#'`. Fix all rendered language syntax, then inspect the Kotlin against the actual pinned API; test existence checks alone are insufficient. The pinned Godot Android Maven artifact 4.7.1.stable exists (HTTP 200 from Maven Central). Do not substitute the engine.

The director queried official godot-cpp tags: `refs/tags/godot-4.7.1-stable` does not exist. The iOS recipe references that nonexistent pin, and its standalone Podfile has a target without an Xcode project. It expects an include/ layout that ordinary CocoaPods output does not automatically provide. Supply a concrete reproducible dependency/bootstrap/build recipe: actual official revision, compatible generated extension API when required, exact Firebase headers/frameworks and transitive link dependencies, arm64 physical-device archives. No simulator work. The director will fetch dependencies and run the commands; the implementer's network restriction remains.

PlayerAccount's draining timeout eventually releases its lock, while native Firebase work may still mutate auth. Native Kotlin begin() only prevents duplicate request IDs, so a new request ID can start a second mutation during the old Task. Enforce a global native mutation lock until SDK completion; a UI deadline must not pretend the underlying mutation was cancelled. Audit iOS for the same defect. Read-only token/session requests may be treated separately when safe. Regressions must exercise a never-yet-completed native mutation beyond the wrapper deadlines, then attempt a competing mutation.

runBridgeBuild inherits all of process.env after load-env has loaded release/server secrets. Native compilation only needs build-path/config allowlisted environment. Use the existing repo's environment sanitization pattern or an explicit allowlist, preserving SDK/tool paths and excluding unrelated ASC/IAP/service-account secrets. Test the exact child env passed to spawn. Avoid shell interpolation of JSON.stringify paths; use structured spawn arguments for zip/nm and other artifact probes.

## Do
Fix these confirmed defects. Check the Gradle version and usable wrapper/system build prerequisites instead of claiming any binary is the pinned tool. Supply meaningful syntax/native checks that do not falsely pass from canned manifest/header fixtures. Inspect manifest/plugin discovery, required Play Games app metadata/config and actual Firebase initialization. Correct docs to exact configuration/build prerequisites. Keep supported provider behavior truthful.

## Do not
Do not integrate gameplay/UI/cloud, change locked project/presets, download dependencies from the implementer, deploy providers, touch credentials/guards/workflows or weaken tests. Preserve the composed IAP extension export. This is round 3 overall, but the actual compile and native global-lock defects are newly measured, not three failed attempts at one defect.

## Acceptance and judgment
The director can run the generated standalone Android build and compile the iOS bridge with official dependencies without authoring missing build definitions. Produced artifacts contain plugin registration/classes/entry symbol and export composition preserves IAP. Standalone identity and build-tool regressions pass; child process environment excludes unrelated secret names; timed-out native mutations prevent competing mutations until settled. Report actual builds you could run separately from director-required network/device checks. Give exact dependency acquisition and build commands, not placeholder paths to nonexistent SDK layouts.
