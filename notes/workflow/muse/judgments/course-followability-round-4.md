# Course followability — director judgment, round 4

Decision: return for correction, not accepted.

The implementer's report and full change inventory were read. The report
claims 16/16 verification on 4.7.2 and 18 Node tests; those are claims pending
final independent full-run verification. The director independently ran
current Lesson 14 and 16 verification on 4.7.2, both exit 0. Neither is proof
of a clean normal user close.

A normal-engine-startup Lesson 16 observer confirmed current_scene=TitleMenu
and pressed the production QuitPrompt Yes button. Exit was 0, but the log
contained four ObjectDB leaks and two resources in use. This directly
contradicts treating the probe's pre-release cleanup as production closing.
The earlier Lesson 11 loss probe also observed continuing beacon charge and
player coasting after the run ended. Final Lesson 11 finish source still
only clears movement input and the spirit target.

Final inspection also confirmed the omitted .p8/.pem exclusions, asset
parent-alias gap, broad noErr output exclusion, and unsigned Android preset
incorrectly asserted to be a debug-build setting. Correction brief 243
records reproductions and acceptance criteria, with only synthetic files.

SHA-256 comparisons found all 18 reused binary assets byte-identical to
tracked shipping assets, including guardian_theme.ogg. The report's claim
that this track has no shipping twin is incorrect. Only the documented
original spark.png has no shipping twin.

Evidence is kept in ignored builds/verify/course-20261013 logs. No actual
user save, credential, device install, store submission, Git push, public
site deployment or volunteer session was performed. Main remains clean.
