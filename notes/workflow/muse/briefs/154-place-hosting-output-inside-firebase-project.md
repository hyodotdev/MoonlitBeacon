# Brief 154: Put combined output inside the Firebase CLI project

## The ask and confirmed failure
"vercel도 로그인해놨어 너가 hosting moonlitbeacon.hyo.dev로 연결해줘"
The director's actual combined deploy with the documented command failed before uploading: Firebase CLI says "../../builds/hosting is outside of project directory". The care-only release is already live; the final combined docs/Terms release is not. The CLI confines hosting.public to the directory containing the selected firebase.hosting.json. This is a confirmed deployment defect, not a DNS or TLS failure.

## Do
- Keep the reviewed bytes and hosting-only app config, but generate the combined directory INSIDE apps/player-care/, e.g. hosting-dist/. Update both composer/checker output constants and public path accordingly. Keep exact care-at-root plus /MoonlitBeacon/ docs mounting and all existing tests/guards.
- Add hosting-dist/ to the existing app-local .gitignore alongside .firebase/, so generated output and deploy caches stay out of Git. Do not change the protected root .gitignore or root Firestore firebase.json.
- Update README/publication handoff and any real output-path references to the exact supported build/check/deploy commands. Explain that the earlier combined attempt was refused before upload, while the verified care-only site remains live. The implementer does not deploy or claim final live success.
- Add a meaningful hosting-config boundary regression requiring public to stay inside the Firebase config's project directory. Existing temp fixtures already put out inside their temporary project root; keep them valid. A config that points outside its project must fail even if that path matches a requested output argument.

## Do not
No game/CSV/versions/native/auth/Firestore/DNS/store/workflow change. No guard weakening, new dependencies, copies of source notes or credentials, network or actual deploy. Do not edit existing legal copy or generated HTML design; the location fix should preserve all 49 care and 142 docs file bytes for unchanged inputs.

## Acceptance and judgment
Real combined build/check plus site/hosting suites pass. All 26 docs pages and 15 localized care pages remain present, with the same canonical origin, paragraphs, links and 404 behavior. Outside-project config is rejected, normal in-project config passes, generated output/cache is ignored. Director reads the complete diff, runs the documented commands and a negative boundary, accepts normally, then reruns the real authorized Firebase deploy.
