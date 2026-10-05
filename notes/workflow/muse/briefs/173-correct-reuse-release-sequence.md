# Brief 173: Correct the replacement release sequence

Continue brief 172 in its same copy. The director independently ran the release-library tests: 69 passed, zero failed. The retained-gallery gate and counter diff look sound. Correct only these confirmed documentation/CLI issues before acceptance:

1. The documented replacement sequence starts with `--check`, but changing iOS build 12 to 13 necessarily makes the retained old manifest differ from current export inputs. Put the explicit **local-only preparation** invocation first, without `--check`, to write the new manifest while retaining the same PNG bytes: `node scripts/app-store-release.mjs --reuse-committed-gallery`. Then show check, GET audit, apply and submit. Make this consistent in CLI help and your build-log entry/report. Add a small meaningful argv/report assertion for the local-only reuse preparation shape if existing coverage does not already prove it.
2. CLI help/build log/report say no image endpoint is called, although the safety audit intentionally performs GETs for image resources. Say **no image mutation request**; retain the image GET verification. Do not change the working gate or its contract.

No other product changes. Keep the exact three counter edits and all previous tests. No screenshots or provenance changes. Re-run the App Store Node suites, hygiene and help rendering. Update your report rather than claiming the original check-only sequence works after a counter bump.
