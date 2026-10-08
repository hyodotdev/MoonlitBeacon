# Brief 232: correct verified release review boundaries

## The ask
Continue the user's authorized review loop and both-store 4.0.1 release.
This corrects the evidence-confirmed boundaries in brief 231.

## Confirmed evidence
- The actual lodge name form offers confirmation/retry, not a normal
  unnamed opt-out. A successful online first entry requires a unique
  nickname before movement practice and departure.
- The local-only unnamed guest is an error/unconfigured escape. It does
  not make name collection optional for every user in a configured build.
- Official Play guidance says optional requires all users to be able to
  opt in/out or provide data optionally; primary functionality requiring
  a type must declare it required. Nicknames are Play Name.
  https://support.google.com/googleplay/android-developer/answer/10787469
- The director read the actual Play form: User IDs already required;
  Name previously optional; email optional; Name/User IDs purposes App
  functionality and Account management, collected, non-ephemeral, not
  shared. The director saved Name as required for the coming review.
  The preview shows Name/User IDs without Optional, email with Optional.
  The console says the change is saved and ready in Publishing overview;
  it has not yet been sent for review.
- Apple currently declares Name, Email Address, User ID, Gameplay Content
  and Product Interaction linked to identity for App Functionality. The
  nickname/handle fits the existing identifier declaration. No Apple
  declaration edit has been made.
- `ProductionHost.needs_lodge_lesson()` requires BOTH a verified display
  name and `intro_complete`. A returning named account that stopped midway
  through practice still visits the lodge. The new Apple/Play instructions
  currently say a settled name / returning account skips the lodge without
  this condition; that is false for an interrupted first lesson.
- The actual new display parser accepts `04.0.1` and `4.0.01` as `[4,0,1]`;
  comparing `04.0.1` with `4.0.0` returns newer. Normal semantic versions
  must not contain leading zeroes (https://semver.org/, specification 2).
  These aliases are malformed under the promised semantic-version guard.
- The real Play Console Sign in details form caps “Any other information
  required to access your app” at 500 characters. The current new Play
  paste paragraph is 673 bytes/characters of ASCII and cannot fit. The
  prior remote paragraph shows 407/500. This is a measured destination
  constraint, not a suggested shorter writing style.

## Do
Review your version-scoped privacy append and release guidance against
those facts. Correct only any new wording that treats the error escape as
ordinary optional nickname collection or describes the saved Play change
as already reviewed/published. Keep old 4.0.0 evidence clearly historical.
Use exact source citations for the current lodge and local-only escape.
Make the returning-account instructions conditional on a verified name AND
completed guide lesson, for both generated Apple guidance and the Play
paste paragraph. State that interrupted practice returns to the lodge.
Keep the Play paragraph within 500 characters, preserving the concrete
guest/name/Lumi/practice/departure path, optional providers and Store/restore
locations. A short conditional returning path is enough; no credentials.
Reject leading-zero normal versions in the new binary-only parser, with
focused current/retained-version regressions. Keep valid zero components,
same-version replacements, numeric ordering, and the selected 4.0.1 intact.

## Do not
No game, native, UI, art, privacy collection logic, form, network,
counter, listing or gallery changes. Only tighten the newly added semantic
parser; do not weaken existing remote or release guards. Do not rewrite
historical facts.
Do not claim permission taps, purchases or timed notification delivery.

## Acceptance
The new 4.0.1 inventory truthfully separates required online naming from
the local-only failure escape, and records the director's saved-for-review
Play correction without claiming completed review. Existing release-path
work from brief 231 stays intact. Review instructions distinguish a completed
lesson from a merely registered name; malformed leading-zero versions fail
in both proposed and retained identities; the actual Play paste text fits
the 500-character destination field. Related suites pass, and restoring
the old parser makes the new malformed-version regression fail. Report this
correction separately from the cumulative patch.
