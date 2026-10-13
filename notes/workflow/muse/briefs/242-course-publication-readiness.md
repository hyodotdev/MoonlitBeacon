# Brief 242: reconcile course and first-play publication readiness

## The ask
"강좌 독자 자원 참여" and a practical Godot mastery-style course, minimum4.7.1/recommended latest4.7.2. Reconcile the complete practice work and recruitment copy before the director publishes anything.

## Where things stand
Continue previous briefs in this copy. No real site launch or human sessions exist yet. Original E01/E02 deadlines and E03 history must remain, and no fresh private dashboard counts belong in this public change. Existing care pages stay byte-identical.

## Additional public-source verification
The director checked public store sources on October13. Apple's official
lookup API returned version4.0.1 for both KR and US (released
2026-10-08T18:35:39Z); Google Play's public package page displayed
"Moonlit Beacon 4.0.1" update notes and an Oct8 update date. This proves
public listing information, not a moderator install or volunteer session.
Source URLs: https://itunes.apple.com/lookup?id=6796293839&country=kr,
https://itunes.apple.com/lookup?id=6796293839&country=us,
https://play.google.com/store/apps/details?id=com.crossplatformkorea.moonlitbeacon.
If discussing the current public game, keep this scope/date accurate and
retain recording the actually installed version during each agreed session.
Do not change store metadata or expand into a native release task.

The director also SHA-256 compared all reused binary course assets with
tracked shipping assets: all18 matched byte-for-byte, INCLUDING
apps/game/assets/third_party/ninja_adventure/audio/music/guardian_theme.ogg.
Only the documented original spark.png has no shipping twin. Round4's
report claim that guardian_theme has no shipping twin is wrong; correct any
corresponding audit/source-provenance statement, without modifying assets.

## Independent round5 verification and remaining findings
Director-ran Node tests:22/22. Full course:verify on official4.7.1 and4.7.2:
16/16 on EACH, clean output gating including real startup/transitions/restart/
window-close and L16 Yes close, fresh-process records/settings, isolated
user data. These are desktop/headless reference checks, not phone, export,
sign-in, volunteer or future-version proofs. You may accurately cite the
actual scope/date, not an untested broader guarantee.

A valid normal-engine Lesson12 observer captured the first full-body dash
ghost: expected Sprite offset=(0,-8.12963), actual ghost offset=(0,0);
ghost top=-8 vs expected=-16.12963. Exit0, no errors. The source does not
copy the AnimatedSprite2D offset. The historical Chapter12 snippet already
does. Align reference full-body ghosts with the captured sprite offset and
transform where needed, preserve the intended trail/timing, and add a
focused creation-alignment contract. Re-check affected checkpoints. No
shipping-game edit or store capture. The first director measurement attempt
used a nonexistent AnimatedSprite2D.get_rect method and was discarded;
only the corrected observer above is source-defect evidence.

Two final fake-repo creator probes also still escaped source boundaries:
(1) src/assets itself symlinked to an external folder with marker.png;
(2) src itself symlinked to an external tree with lesson-01/marker.txt.
BOTH planCreation+executePlan accepted and copied the synthetic outside
marker. Existing checks compare against the canonical alias-root itself,
so they miss this. No actual key or real folder was accessed. Validate
source-root/assets-root containment against the real repository/source
boundary BEFORE output creation. Cover BOTH root-alias fixtures and keep
all previous aliases/secret exclusions/determinism tests; legitimate /tmp
aliases above repoRoot still work. Report any unresolved defect rather than
claiming all path protection is complete.

## Do
- Make the homepage lead with the Godot 2D learning benefit, link directly to the runnable practice path and show minimum vs recommended versions clearly. Fix stale three-area-only/current-game copy and "CC0 assets only" when font licensing differs. Use accurate readable copy, not internal engine-lock/editorial policy in published prose. Keep actual verification scopes honest; the director supplies practice results after independent tests.
- Use a confident mastery-style promise scoped to the concrete skill, for example "Build a mobile game. Master Godot's 2D workflow." Develop it positively through build -> explain -> modify -> verify and the capstone. Avoid leading students through repeated disclaimers or a list of unrelated features this course does not teach. State minimum, recommended latest stable with date, matching export templates, and which full practice runs actually passed; future untested versions are simply outside the tested range.
- The director's desktop browser shows the reused hero image visibly stamped v2.1.0. Caption it as an early survivor reference, not a current-store screenshot or exact new practice output; do not recapture it. The official minimum archive was also verified at https://godotengine.org/download/archive/4.7.1-stable/ and can be linked alongside 4.7.2. The first preview passed 1280px and 380px layout (no horizontal overflow, hero loaded 1616px); final content still needs a fresh browser check.
- Make standalone practice projects carry the repository's own MIT notice
  as well as the CC0 text and NEXON attribution. Director inspection found
  only CC0-1.0.txt and THIRD_PARTY.txt in the Lesson1 layer; root LICENSE is
  MIT, Copyright(c)2026 Hyo Dev, and requires its notice to accompany copies.
  Copy the existing notice byte-identically into the generated projects,
  identify MIT by name rather than unexplained "project license", include
  the reused moon_gate among derived credits, and retain relevant notice
  text files in the reference export. Do not alter root LICENSE or assets.
  Verify the new output and update file-count claims if necessary.
- Correct first-play invitation/protocol: install is fine, but wait to FIRST OPEN until the agreed session; record app version during it. No presumed seats/fullness from a late response; bookings/availability confirmed separately. Social login is optional; guest entry exists, so "no account needed" must not imply no guest identity. Keep enquiry/observation/quote consent distinct and contact PII out of Git. Nobody is counted without actual session evidence.
- Anchor manual timing explicitly: observe from the agreed first app open, distinguish time to actual run start from time to first beacon during play, and count deaths in the first 60 seconds of the run (not 60 seconds spent signing in/onboarding). Record the quit screen/step and unavailable observations as unknown; neither a store click nor moderator QA is a volunteer completion.
- Fix the measurement contract: Play reports expose UTM source+campaign, not utm_medium. Match source=moonlit_course/campaign=course_first_play_20261013; medium is only URL annotation. Attributed listing visitors/install clicks are primary; global Grow acquisitions/first opens are context unless matching campaign attribution is independently exposed. Keep unavailable/suppressed rows null, timezone/window explicit, completed days only, no causal verdict or activation division. Preserve old E02 not_run history; use a new distinct experiment identity, still prepared with null launch proof.
- The weekly first-open outage warning was observed September21, not freshly verified October13; do not present it as a current outage. Preserve exact observation scope/date. Use one coordinated new course experiment for this single channel and its manual sessions, rather than starting two independent concurrent exposures.
- Reconcile public growth strategy/state/ledger qualitatively: E03's Oct2 deadline was missed and its late Oct13 verdict is inconclusive; E02's original Oct9 deadline had no verified launch. Keep historical metric snapshots/attempts byte-identical, publish no new private counts or console URLs. Record the user-selected course channel and prepared five-session protocol, with no launch/participant/scheduled-run claim. Original deadlines stay preserved; next planned review Oct15 is a plan, not a saved automation. Existing tracker stays GitHub#1. An English concise issue-update draft may be written under notes/workflow/muse/ for the director, but do not publish it yourself.
- Review all public entry/version/clone instructions against the real creator/source paths. No repository-only command is presented as a blank-project command. A clone already contains selected assets. Root Control anchoring, advanced built-in signal connection, spaced executable paths and proper Conventional Commit examples must be correct. No duplicated enums in the new Lesson5 full-file instructions.
- Make the runnable practice path the primary route, with concrete next actions for a beginner. A list saying "wire the scene" is insufficient when the old prose omits node properties or surrounding code: link the complete matching scene/script and explain exactly where to add/replace it and which step to run next. Keep an independent modification/check in every lesson so generating a checkpoint is not mistaken for learning. In Lesson3, `_bgm.release()` / `_sfx.release()` requires custom music_player/sfx_player wrappers; shipping has those, but a built-in AudioStreamPlayer does not. Supply the full wrapper/helper setup or align the excerpt with the actual complete practice source. Do not falsely call the shipping wrapper API nonexistent.
- The original Lesson3 prose also attributes a 150 ms teardown wait to the built-in player. That wait belongs to the project's custom cleanup helper/wrappers; explain that accurately. Label the historical 181/27 ms measurements as the original build's measurements, not new checkpoint or 4.7.2 measurements. Reconcile the overview's top engine/assets table too: it still says only 4.7.1 and CC0/OFL while the selected practice font uses the attributed NEXON license.
- Correct Lesson1's factual stretch explanation: canvas_items + expand does not always lock height at 360 and grow width only. It grows virtual width on wider aspect ratios and virtual height on taller/narrower ones. Explain both, edge anchors and background coverage accurately, using the official multiple-resolutions documentation (https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html). Keep the locked project values intact; do not turn this into a native/tablet redesign.
- Director build after round2 succeeded (27 HTML pages), and check:docs passed actual built anchors, but Docusaurus warned about /MoonlitBeacon/#play-the-current-game from the course guide. The SSR homepage does contain the section ID; reconcile the base/canonical link form and its checker representation without weakening/ignoring checks. The director's dependency shims are now available for builds; do not repeat a stale missing-dependencies claim without running the command.

## Acceptance
Public code/notes contain no fresh private metrics/PII/secrets/false deployment or observer results; old history is preserved. The new practice path and all16 links are concrete and internally consistent, current hero media uses base-aware paths, and the canonical-route regression test catches the observed live broken-image case. Docs/hosting/growth/skills/hygiene/diff checks pass. Final launch proof is supplied only AFTER actual authorized publication.
