# Brief 119: grounded living sprite party on the original title

## The ask
"캐릭터가 그리고 첨 화면에서 너무 이상하게 떠있는데??? 이세카티 게이트처럼 sprite로 막 움직이는것도 아니고 뭔지 몰겠네..."
Earlier: "그냥 ㅇ원래에서 tab to start 누르면 게스트, 구글, 애플 로그인으로 시작하게 하면 안돼?" and a premium dimensional sprite style, not pixel-art reduction.
The original title should show a living party actually walking on the ground, not large characters hovering in fixed slots.

## Why, and what good feels like
A player sees six characters inhabit the forest and beacon: believable feet contact, walking and stopping, different directions and a readable silhouette. The title/logo/Tap prompt and original small menu remain the familiar focal points. This is a corrective art-direction request from the human after viewing the current native screen, not permission to replace the title with a dashboard or static illustration.

## Where things stand
Current GateHeroForecourt uses real idle AtlasTexture frames, but every root stays fixed at normalized SLOTS. Body alone bobs +/-1.5 logical pixels above its fixed shadow, and entry arrival moves the whole root vertically. Front characters are 65-85px tall, disproportionately large against the original forest. Native 4.0.0 title makes them look like floating pictures at both corners. All six heroes already have directional idle/walk sheets, sprite_cell144x192, four columns (down/up/left/right) and four rows. Warden walk sheet is 576x768; use the actual Hero resource and real atlas layout. Hero weapons are separate painted rigs and must stay held properly, not drift or flip independently. Root after 117 is stable; another implementer copy is independently correcting Account panel only. Do not touch its files/tests to avoid overlapping changes.

## Do
- Rework GateHeroForecourt into six lightweight presentation sprite actors walking purposeful short ground routes around the beacon sides. Use actual walk sheets while moving and idle sheets while stopped, face the real direction, and stagger pacing/stops so this feels like a party rather than synchronized screensavers.
- Make world scale and grounding coherent with the existing forest title: smaller appropriate party bodies, anchored visible foot contact and attached contact shadows, depth ordering from ground position. Remove the floating idle body bob/vertical arrival. Do not merely translate a static portrait back and forth.
- Preserve the original title, Tap-to-start behavior, menu/shop/Hall/settings, six hero identities/premium art and clear title/modal/legal/interaction regions in narrow/wide landscape and 4:3. Actors never take input or affect ownership/gameplay. Freeze stable grounded poses and stop all motion under reduced-motion.
- Validate actual time evolution: ground/root positions change during walking, correct walk/idle atlas and facing, feet/shadow stay coherent, body/held weapon bounds remain on screen, safe paths avoid title menus/prompt/modal zones, no timers/tweens left after close. Use a dedicated meaningful motion test/tool rather than changing Account test files.

## Do not
- Change auth/cloud, GateAccountPanel or gate-entry-layout/states suites, secrets/config/version/presets, original title source/menu resources, logo/background lighting, core combat, locked engine/stretch/filter controls, or store images.
- Add Player/Arena/physics to the intro, unlock heroes, introduce captions/debug rectangles/default UI, or use portrait PNGs as actors. Do not name a model outside its config.

## Acceptance
Director will render and review a 10-14 second actual title clip and stills in native-sized framing, inspect all six actual sheet/direction changes, and run motion/layout tests. Root travel during an active walking segment must be visibly meaningful (e.g. >=20 logical px in two seconds at chosen pace), standing feet remain fixed with no body bob, and reduced-motion state remains position/frame stable across time. Actor pixels never occlude interaction labels/card; source scale is appropriate to the forest. Tests must fail under a negative restoring the old fixed-root idle-only behavior. Performance stays lightweight with six presentation actors and no ownership or game-state changes. Confirm no lingering extra UI nodes after repeated title/chooser use.

## Deliverables
Narrow forecourt source changes and a dedicated registered motion regression/render tool, plus author-only note. If assets prove unusable for true locomotion, state the exact defect with measured frames rather than pretending sprite cycling is walking. Do not author a substitute unrelated character set.

## Settle these yourself
Choose routes, speed and stop timing for calm but unmistakable life, respecting the human's Isekai Gate reference without copying its pixels. Smaller footsteps and varying direction matter more than exaggerated bouncing. Prefer existing legitimate six-hero directional sheets and a clear coherent path.
