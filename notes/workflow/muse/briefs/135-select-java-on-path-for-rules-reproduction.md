# Brief 135: select Java on PATH for rules reproduction

## The ask
"/loop-review돌리고 메인 다 클린한상태로 둔 다음 할까"
Make the documented reproduction actually work before accepting the review fixes.

## Where things stand
Keep the six-file diff from briefs 132–134. The director independently executed the new temporary-workspace README command, including a fresh npm install. It installed firebase-tools 15.32.1. The explicit Java-home binary reported version 26.0.1, but the subsequent local Firebase CLI still failed with its Java-before-21 error. The CLI spawns `java` from PATH, and this machine's PATH selects an older installed Java. An earlier global-CLI experiment is not proof for this newly installed local CLI.

## Do
- Correct only `tests/cloud-rules/README.md`: prepend the selected Java home's `bin` directory to PATH for this shell before checking `java -version` and running the local CLI. Explain that JAVA_HOME alone does not select the executable spawned from PATH.
- Pin firebase-tools to the actually measured 15.32.1 in the install command and measured-version sentence, alongside the existing measured Firebase and rules-unit-testing versions.
- Keep the temporary workspace, unchanged repo lock and emulator-only boundary. Do not add network packages to the real repo.

## Do not
Change any other file from the current six-file diff, code, tests, dependency manifests, versions, assets, external settings or runners. Do not claim the implementer ran the emulator; the director supplies and independently executes dependencies.

## Acceptance
The only new hunk is the executable Java selection and measured CLI pin in the README. The director executes the corrected command against the prepared temporary workspace with the pinned packages, and requires 38 tests, 9 suites, zero failures. Keep prior Hall changes byte-identical.
