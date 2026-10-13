# Course followability — director judgment, round 5

Decision: continue to publication readiness; not accepted yet.

Director ran test:course (22/22) and the entire 16-checkpoint verifier on
official 4.7.1 and 4.7.2 (16/16 on each, both exit 0). Checks include real
main-scene/autoload/current_scene startup, production title entry, restart,
window close, Lesson 16 Yes close, fresh-process saves and isolated data.

An independent temporary mutation changed QuitPrompt Yes back to direct
SceneTree.quit. Lesson 16 correctly failed with the original four ObjectDB
leaks and two resources still in use. The original file was restored byte
for byte (SHA-256 5944b832c1f5de70e83aca0d2e8a43504a9ea385e3b8ec0bbd5c4ac1c4bc560b).
The verifier now detects this source defect instead of cleaning it away.

Two remaining creator probes used only synthetic external markers. A
symlink of src/assets itself and a symlink of src itself were both accepted,
and the outside marker reached the output. Root containment must be checked
against the repository/source boundary, not just against the alias root.

A valid normal-engine Lesson 12 observer found ghost offset (0,0), while
the captured sprite offset was (0,-8.12963). The full-body trail is shifted
about half a frame downward. A prior measurement used a nonexistent
AnimatedSprite2D.get_rect method; that attempt is invalid and kept separately.
Only the corrected observer is evidence of the source mismatch.

Brief 242 includes these confirmed findings plus concrete student steps,
version/learning copy, standalone MIT notices, and qualitative growth-state
reconciliation. It preserves private counts and historical snapshots.
No phone, APK, sign-in, future engine, public launch or volunteer proof is
claimed. Evidence is in ignored builds/verify/course-20261013 logs.
