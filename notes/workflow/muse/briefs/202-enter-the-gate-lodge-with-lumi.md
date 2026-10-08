# Brief 202: Enter the gate lodge with Lumi

## The ask
“로그인했을 때 이세카이 게이트처럼 처음 어떤 방에서 튜토리얼 같이 다른 캐릭터가 플레이어한테 안내하면서 이름부터 정하게 하고 (중복없이 이게 바로 스코어 저장할 때 쓰여야해) 플레이가 진행될 수 있게 해줘. 안내해주는 애도 스프라이트 잘 만들어주고”

Build the playable first-login room using the reviewed name service, a new guide sprite and the supplied room art.

## Why, and what good feels like
The player steps into a warm refuge after login. The lantern keeper greets them as an arriving traveller, asks what the register and Hall should call them, then offers a short hands-on movement and dash lesson before opening the gate. This is a small real game room with characters grounded on its floor. It must look as finished as the existing painted game, with no generic forms covering the whole scene or floating portraits masquerading as sprites.

## Where things stand
- This continues the same isolated copy after briefs 200 and 201. Preserve their independently reviewed defeat rules, permanent rewards, cloud name protocol and registered tests. Do not reset the existing immutable MB identity, wallet, best scores, living journey or account linkage.
- The user added a two-coin attendance reward every rolling twelve hours. Brief 204 supplies its server-owned service before this scene run. Preserve that service and defer its receipt presentation while the lodge's name keyboard or guide dialogue is active; first-time attendance can settle after the account-owned lesson completes. Native reminder controls belong to the following brief 205, not this scene task.
- Brief 209 closes replay, expired-wallet recovery and actual account
  deletion. One director-confirmed integration boundary remains: ten
  owners claim on one install in the same window, the first owner's mark
  and receipt prune, and that owner returns after twelve hours. The real
  Coordinator returns terminal `attendance-replay-ambiguous` and refuses
  to commit ANY future period, permanently disabling that account's
  attendance. The isolated director probe `attendance-pruned-return`
  reports balance 22→22 rather than 22→24. Preserve refusal to repay an
  ambiguous forgotten OLD receipt, but allow a genuinely new eligible
  server-conditional claim to progress. Never guess or repay old history;
  do not freeze future rewards because bounded history was retired.
  Register this actual Coordinator case while integrating entry, keep
  purchased keys intact, and state the old recovery bound honestly.
- The director's actual `test_cloud_attendance.gd` run has 86 passing
  assertions but emits an engine ERROR for `_test_prev_carry_parses`:
  malformed `prev_claim_at` reaches `Time.get_unix_time_from_datetime_string`
  through `CloudSchema.unix_from_rfc3339`. Keep rejecting malformed
  server data without an engine error; the normal full runner rejects
  this diagnostic even though the script exits zero. Repair this bounded
  parser boundary and verify the full raw log is clean.
- `production_entry.gd` preserves the original title and handles login, cloud restore, entry plans and generation-guarded loading. `production_host.gd` and the new name service provide load/claim/intro-complete operations. Read the reviewed callable contract in `notes/plans/gate-account-protocol.md`; the continuation runner replaces the previous report. Reuse this verified protocol rather than inventing a second nickname store.
- `scenes/actors/player.tscn`, `scripts/actors/player.gd`, existing hero resources and painted animation atlases already handle the selected playable hero. Reuse them, keeping every existing hero raster byte-identical.
- `scripts/gameplay/onboarding.gd` tracks old combat tips. New lodge completion is per canonical account, separately durable. A lodge lesson can mark move/dash as learned only after the actual player performs them.
- Raw original sources are supplied in `notes/workflow/muse/art/gate-chamber/`: `gate-chamber-room.png` (landscape environment only), `lumi-turnaround.png` (transparent front/back/left/right, equal ground baseline), and their prompts. Pack runtime assets reproducibly; do not use the raw turnaround as a portrait billboard.
- Director alpha measurements of the four raw Lumi columns (threshold
  128) give visible heights 853, 850, 851 and 852 source pixels; bottom
  anchors are 867, 866, 866 and 867. This source is already consistent.
  Preserve its proportions with one common runtime scale and ground
  anchor instead of independently filling each facing's bounding box.
- `gate-chamber-room-tablet.png` (1448×1086 RGB, 4:3) and `room-tablet-prompt.md` supply the taller tablet plate with the same desk/window/gate and extended open stone floor. Use this faithful tablet source at taller landscape ratios rather than stretching the wide plate or cropping either interaction. Keep character world scale unchanged; adapt actual room collisions and interaction coordinates to the selected plate. Pack both plates reproducibly and record both originals in the manifest/provenance.
- Nari is missing in the opening story. The new guide is a different person: **등불지기 루미 / Lumi, the Lantern Keeper**. Lumi tends the refuge registry and helps arrivals find the beacon road.

## Do
- Integrate a real lodge scene into first guest/Google/Apple entry. Load and verify the account's name/intro state before arena entry; completed accounts skip the lodge, incomplete accounts recover their already claimed name after restart. Name confirmation is the first lesson and uses the real atomic service. Show that it is a public adventurer handle, not a real name, and provide localized invalid/taken/offline/retry states without trapping a spinner. Handle Unicode IME, Android/iPad native keyboards and safe areas. A cached verified completed account can still enter offline; a new offline account must not be falsely certified unique.
- Build a warm, restrained diegetic name/dialogue presentation over the supplied room. Lumi stands near the registry desk and faces the approaching hero; the selected actual hero stands on the open floor. After the name is confirmed, let the player move with the existing controls and dash, then walk to the right-hand gate. Use brief readable speech with a consistent speaker label and a skip/return option where appropriate. Do not resume stop-start combat tutorials after this lesson, and do not infer a lesson from a timer or an unrelated tap.
- Keep the refuge free of combat spawns, automatic weapon swings/shots,
  damage flashes, wave counters and arena progression. Reuse the selected
  hero's actual idle/walk/dash visual and input behavior locally; learning
  movement in the lodge must not spend a continue coin or advance an
  existing saved expedition. The gate is the explicit transition to play.
- Pack a four-facing grounded Lumi sprite with a reproducible generator, bounded idle breath/lantern gesture, neutral planted feet, stable head/body dimensions and a fixed common foot anchor. Lumi may remain by the desk; if she walks, use a genuine alternating planted-leg cycle, never the earlier foot wiggle. Keep floor shadows and Y ordering coherent with the scene. Map walls, desk, floor and gate collision to the actual art, responsive at 808×360 and expanded landscape aspect ratios. Reuse existing world-skinned controls and font/localization conventions, avoiding default Godot buttons, rectangles, unreadable small text, portal glare and blinking debug overlays.
- Complete the durable account-owned lesson only after actual name/move/dash gates. A new account then starts a fresh expedition. An existing living journey must still offer Resume versus confirmed fresh departure without silently discarding it; a defeated journey must never offer free same-stage resumption. Guard scene transitions, repeated taps, pending claims, token refresh and account changes. Register meaningful scene/entry/service regressions, asset contracts and manifest rows, update the player guide and provide a bounded production-style QA harness to render/name/move/dash/door/Hall states with an injected host and isolated saves.

## Do not
- Do not change the original title, official Google/Apple buttons, login consent links, menus, existing heroes, native auth SDKs, IAP, release counters, locked renderer/resolution/filter settings or stores.
- Do not name Nari as the guide, preload the arena behind every title, create a new player ID on naming, delete a returning save on lodge entry or treat fixture replies as verified production claims.
- Never prefill or publish a Google/Apple real name, email or native profile label as the adventurer nickname. The player chooses this public game handle explicitly; an existing acknowledged game handle is the only account value to restore into the form.
- Do not deploy, access the network, touch credentials, perform git actions or recapture marketing screenshots. The director supplies emulator/live operations and captures only isolated development QA.

## Acceptance
- Automated production-entry tests cover guest and provider first entry, returning complete accounts, incomplete claimed accounts, timeout/offline errors, cancellation, stale account callbacks and repeated scene loads. Runtime host plans cannot enter the arena before the required verified name/lesson state, including direct calls rather than only disabled UI.
- A restart during name registration or midway through the lesson keeps the same canonical ID/name and safely resumes setup. An existing saved run survives migration and lodge completion byte-for-byte until an explicit fresh confirmation or legitimate resume. Claiming an existing account's name preserves its best score and Hall hero, and new score writes show the same chosen name.
- The result screen's record action never asks a verified named player to choose a second name. Inspect that actual scene route, not only the cloud payload, and make its chosen-name/hero/score presentation coherent with the Hall.
- The QA harness renders the actual room and Lumi at both 808×360 and a wider native landscape viewport, with no overlapping clipped text at each of five locales. Provide front/back/left/right idle contact sheets and a short scene clip showing the selected hero moving, dashing, stopping with neutral feet and entering the gate. Foot anchors remain aligned and all Lumi head heights remain within 5% across facings; idle frames do not resize the face. Old hero raster hashes are unchanged.
- Also render iPad's taller 4:3 landscape (an expanded 808×606 logical viewport). Keep both registry and gate accessible and character scale consistent; do not crop either interaction offscreen or leave plain black/gray unused bands. Keyboard-visible naming layout must remain readable and tappable in this aspect as well.
- Supply actionable automated checks for the new asset dimensions/alpha/frame layout and generator freshness. Test the real scene collision, movement, dash and door conditions, including a failed/uncertain intro-complete acknowledgement. Normal production has no test nickname, fake ranking rows or tutorial debug state.
- Related cloud/name/host/production-entry/onboarding/locale/asset/hygiene/docs checks pass. Reports are claims: the director reruns tests and sees the rendered game independently before accepting.

## Deliverables
Lodge scene/controller and production-entry/host integration, Lumi packed runtime art and generator/contracts/manifest, localized dialogue and nickname form, account-specific completion integration, registered regressions, player guide and a compact isolated development harness. Update the author-only protocol note with the exact route and recovery behavior.

## Constraints specific to this task
Disk space is limited: keep QA recordings short and small. No full marketing capture, redundant movie copies or new dependency install. Keep existing hero PNG files byte-identical. Five player languages: Korean, English, Japanese, Simplified Chinese and Traditional Chinese. Preserve original Tap to start → official login selection → account restore sequence.

Use a room-owned fixed camera and disable the instantiated player's arena camera locally, so walking does not pan off the environment plate. Keep player animation/root tint conventions intact. Limit the raw development movie to 120 frames at internal resolution; wider/native states can be PNGs. Raw art source sizes are 1774×887 RGBA (Lumi) and 1881×836 RGB (room).

## Settle these yourself
Lumi stays by the registry desk and turns naturally toward the player; an escort walk is optional and should be omitted if its gait is not consistent. Keep her taller adult proportions readable but scale her world size to the playable hero's grounded presence. A short calm refuge ambience may reuse the existing title music at an appropriate level. Returning old accounts without a chosen name enter setup once, keeping their saved journey and choosing resume afterward. The initial verified nickname is immutable; nickname renaming is outside this task.

Tie the greeting to the existing “road remembers itself” and Nari's warm-kettle story in `STORY_OPEN_A/B`, rather than explaining databases. The registry gives arrivals a name by which the refuge and Hall remember them. Lumi can briefly point toward the missing beacon keeper's road when the gate opens. Keep Nari missing at this point and avoid inventing a new amnesia plot. The player's chosen public handle should be used naturally in Lumi's subsequent line.

## How the director will judge
Read the production routing and every account generation guard, independently run registered regressions and rule enforcement, inspect the exact saved files around interrupted lessons, compare existing hero raster SHA-256 values, and watch screenshots and motion in the real room. The director will then exercise the Android emulator with an actual landscape touch flow before accepting the cumulative change.

Run affected registered suites and asset/static/locale/docs checks. If `pnpm test:game` is blocked by the sandbox editor-settings failure, report it and stop that check instead of manually sweeping all old suites. The director runs the normal full suite on the cumulative copy and `/verify` on the accepted tree.

Keep the true exit status and complete diagnostics of each check. Use a
45-second timeout for small Godot checks; do not hide a parser/settings
error with a successful `tail` or `grep`, and do not repeat a sandbox-blocked
command. Report it for the director's normal environment.
