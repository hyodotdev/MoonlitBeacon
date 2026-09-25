# Asset-generation prompt log

First recorded: 2026-07-29 · Last update: 2026-08-02

## How they were used

- Generation tool: Codex built-in image generation
- Purpose: concept anchors comparing Warden's large form and color splits
- Final runtime files: not the generated images;
  rebuilt at 1x with `apps/game/tools/build_warden_assets.py`
- Source archive: `_asset_sources/custom/a0-player/concepts/` (gitignored)

Candidates A–C and the first selected option are the prompts actually sent,
with only line breaks cleaned. The post-feedback redesign restates the core
requirements of the same edit call as a production brief without duplication.
No specific artist or existing-game style was requested.

Candidates A–C and the first selected option are the 2026-07-29 decision
record. After play-screen feedback that “the face looks scary and it looks
like it will fire a pistol,” the **redesign after user feedback** below
replaces the current production baseline.

## Candidate A — Moonlit Warden

Output:
`candidate-a-moonlit-warden.png`

```text
Use case: stylized-concept
Asset type: original game character concept reference, candidate A for
Moonlit Beacon.

Primary request: Design an agile Moonlit Warden for a top-down pixel-fantasy
action game. The subject is a compact young guardian with a straight indigo
hooded mantle, a low stable triangular silhouette, a short moon blade, a
crescent clasp, and one tiny warm ember charm. Moonlight and beacon fire must
both be present in the design without making it ornate.

Style and finish: modern commercial indie pixel-art visual development,
enlarged for concept review, crisp ink-like outline, restrained 12–16 color
logic, block shading, a subtle Korean woodblock-print sensibility, readable at
very small sprite scale. Original design only.

Composition: show front, back, and side turnaround views at the same scale on
a plain neutral background. Keep feet, cloak hem, blade, and silhouette fully
visible. No action pose, no UI, no scenery, no labels, no readable text.

Palette: deepest night #0B0E1C, ink #141B1B, indigo shadow #4A5270, moon blue
#79B8CE, moon core #CDE1FF, beacon accent #EF914F. Warm color must be a small
accent, not the main garment.

Animation intent: simple separated legs and short cloak panels suitable for a
24×32 four-direction walk cycle. Keep accessories close to the body and avoid
thin one-pixel dangling details.

Avoid: ninja mask, ninja headband, generic ninja costume, large cape hiding the
legs, photorealism, painterly blur, gradients, anti-aliased edges, excessive
ornament, chibi mascot proportions, watermark, logo, text, existing franchise
characters, or a finished sprite sheet.
```

Verdict: the straight-cloak direction is good, but it risks hiding the legs
and walk timing at 24×32, so it was dropped.

## Candidate B — Crescent Wayfarer

Output:
`candidate-b-crescent-wayfarer.png`

```text
Use case: stylized-concept
Asset type: original game character concept reference, candidate B for
Moonlit Beacon.

Primary request: Design a nimble Crescent Wayfarer, a young top-down fantasy
guardian who fights with a compact crescent blade. Use an asymmetrical short
indigo jacket, one pale moonlit shoulder panel, a narrow crescent sash that
curves to one side, tied hair, closed travel boots, and a tiny ember-colored
knot. The silhouette should feel fast and diagonal while remaining readable
as a 24×32 game sprite.

Style and finish: elegant modern commercial indie pixel-art concept,
high-resolution but with deliberate pixel clusters, dark ink contour,
restrained block shading, subtle Korean woodblock and folded-cloth influence,
12–16 color logic, original character design.

Composition: three equal turnaround views, front, back, and side, on a simple
neutral background. Show the entire silhouette, both feet, weapon, garment hem,
and the attachment point of the sash. No action scene, no UI or labels.

Palette: #0B0E1C, #141B1B, #3B3643, #4A5270, #79B8CE, #CDE1FF, with a very
small #EF914F accent.

Animation intent: short separated jacket panels, visible knees and boots,
accessories kept close enough for a clean four-direction four-frame walk.

Avoid: ninja mask or headband, floor-length scarf, huge ribbon, wide flowing
cape, ornate armor, photorealism, smooth vector gradients, anti-aliasing,
watermark, logo, readable text, existing game characters, finished sprite
sheet.
```

Verdict: the long crescent sash and curved motion overlap the later hero
Dancer's identity, so it was dropped.

## Candidate C — Ember-Moon Scout

Output:
`candidate-c-ember-moon-scout.png`

```text
Use case: stylized-concept
Asset type: original game character concept reference, candidate C for
Moonlit Beacon.

Primary request: Design an Ember-Moon Scout for a top-down pixel-fantasy action
game: a compact agile guardian with a broad pale crescent collar, a short split
indigo coat, a small moon blade held close to the body, and one compact
ember-lit bracer. The lower silhouette must clearly expose two legs for
walking. Balance cold moonlight with one tiny warm beacon accent.

Style and finish: modern premium indie pixel-art visual development, enlarged
concept pixels, bold dark ink outline, clean block shading, restrained
12–16-color construction, subtle Korean woodblock-print shape language,
original design, memorable at tiny scale.

Composition: front, back, and side turnaround views at equal scale on a plain
neutral background. Show full head, collar, split coat, hands, blade, and feet.
No environment, action pose, UI, labels, or readable text.

Palette: deep night #0B0E1C, ink #141B1B, violet shadow #3B3643, indigo
#4A5270, moon blue #79B8CE, moon white #CDE1FF and #DEF0FF, ember #EF914F,
with a pinprick #FFE18D core.

Animation intent: simple compact shapes that can be redrawn at 24×32 with four
direction columns and four walk frames; short coat tails, separate boots, no
loose accessory extending past the cell.

Avoid: ninja hood, mask, headband, oversized cape, long ribbon, generic samurai
armor, photorealism, painterly blur, smooth gradients, anti-aliasing, too many
tiny ornaments, watermark, logo, text, existing franchise characters, or a
final sprite sheet.
```

Verdict: the wide moon collar, small bracer, and split coat separate best at
24×32, so it was chosen.

## Selected-option refine

Input:
`candidate-c-ember-moon-scout.png`

Output:
`selected-moonlit-warden.png`

```text
Use case: precise-object-edit
Asset type: selected Moonlit Beacon player-character concept anchor.
Input image: candidate C, Ember-Moon Scout turnaround.

Primary request: Refine only the selected character while preserving the same
three-view turnaround, body proportions, broad pale crescent collar, short
split indigo coat, compact moon blade, dark ink outline, block-shaded pixel-art
language, neutral background, and cool moonlight / tiny warm beacon palette.

Change only:
1. Replace the topknot and red hair cord with a compact short layered haircut.
2. Replace bare feet and ankle wraps with closed dark travel boots.
3. Shorten both split coat tails so they end above the knees and never hide
   the feet.
4. Reduce the ember bracer by roughly twenty percent and make its flame a tiny
   two-step accent.

Preserve exactly: front/back/side view order and scale, visible separated legs,
wide moon collar, weapon size, face simplicity, indigo body mass, crisp
pixel-cluster edges, restrained color count, and original character identity.

Do not add: hood, mask, ninja headband, topknot, ponytail, bare feet, sandals,
long scarf, huge cape, extra weapons, scenery, UI, text, logo, watermark,
anti-aliased edges, gradients, or references to existing characters.
```

## Redesign after user feedback — Cute Moon-Seed Guardian

Input:
existing `idle.png`, `portrait.png`

Review output:
`builds/art-review/a0-player/cute-warden-concept.png` (gitignored)

```text
Use case: character style transfer and production concept reference.
Keep the same Moonlit Warden identity and top-down game readability, but make
the guardian much cuter, younger, and warmer. Use a large round head, a soft
rounded pale-blue hood cape, a clearly visible friendly face with a short
midnight-purple bob, closed short boots, and one tiny crescent brooch.

Remove every weapon-like object. Both empty open palms cup a small moonlight
seed at the center of the chest. The character should look like they gather
and release moonlight, never like they aim a handgun, wand, staff, or blade.
Use deep navy, powder blue, moon white, a restrained gold accent, warm skin,
and a small coral blush. Preserve crisp pixel clusters and a silhouette that
can be rebuilt as a 24x32 four-direction sprite plus a 48x48 portrait.

Avoid: gun silhouette, weapon grip, finger gun, extended aiming arm, blade,
bracer, visor, mask, glowing eyeless face, horror expression, military coat,
tie, horns, watermark, logo, text, anti-aliased edges, or an existing
franchise character.
```

Only the large form of the generation result was referenced. Ornaments on the
concept that could read as horns outside the head become a demon silhouette
in a small runtime cell, so they were not imported. The current locked option
is a round hood cape, a widely visible friendly face, a short purple bob, a
tiny crescent pin, and empty hands cupping a moonlight seed at chest center.
The previous locked option's short moon blade, ember bracer, and face that
showed only glowing eyes were all removed.

## Redesign after user feedback — small 2-head-tall hero family

Input:
existing Warden·Dancer·Keeper review copies and the original Ninja Adventure
player sheet

Review output:
`builds/art-review/a0-player/moonlit-two-head-chibi-concept.png` (gitignored)

```text
Use case: stylized-concept
Asset type: Moonlit Beacon game character proportion redesign sheet
Primary request: Redesign the three existing Moonlit Beacon heroes from their
current tall roughly three-head proportions into tiny, lovable two-head chibi
pixel-art characters, using the compact rhythm of the original small Ninja
Adventure character reference while keeping the new heroes fully original and
preserving their moonlight identities.
Input images: Image 1 is the current Warden and must preserve its lavender hood,
warm visible face, crescent detail, and moon seed; Image 2 contains the current
Moon Dancer and Ember Keeper and must preserve their identities and palettes
but correct their proportions; Image 3 is proportion and compactness reference
only, never copy its costume or face.
Scene/backdrop: clean dark navy character design board, no environment.
Subject: three separate full-body heroes, each shown front-facing at game-sprite
scale and as a larger nearest-neighbor pixel zoom. Warden: round lavender hooded
child holding a glowing moon seed. Moon Dancer: lilac petal hood, small teal
ribbon, tiny crescent light in hands. Ember Keeper: charcoal-blue hood, warm
lantern-heart held in front.
Style/medium: crisp handcrafted original pixel art, limited palette, hard edges,
small indie game sprite language.
Composition/framing: clear lineup; exact two-head-tall silhouette for every
hero. Head and hood occupy about 48-52% of visible height. Torso is only about
one head tall including tiny feet. No long neck, long coat, skirt tail, or
extended legs. Arms tuck forward around the light object instead of hanging at
the sides. Feet sit immediately below the rounded torso and are visibly
separate.
Lighting/mood: cozy moon glow, affectionate, playful, child-friendly.
Color palette: preserve current lavender/cyan Warden, lilac/teal Dancer,
charcoal/amber Keeper.
Constraints: all three belong to one cute moonlit child-guardian family;
visible warm faces; expressive large eyes; readable at 24x32 source-cell scale;
original designs only; no text; no watermark; no scenery.
Avoid: penguin silhouette, egg-shaped long torso, three-head-tall anatomy,
dangling side arms, long robe, long legs, adult proportions, guns, swords,
armor, masks, faceless hood, realistic rendering, smooth anti-aliasing, copying
the Ninja Adventure costume.
```

The image-generation result was used only for proportion and hand-position
reference. Final sheets were redrawn in two deterministic generators, and
actual silhouette height inside the 24×32 cell was capped at 22–24px.
Head vs body/feet height difference is 2px or less, foot bottoms are y=31 on
every frame, and torso width including Keeper is 18px or less, all checked
automatically.

## Final sprite production

Final `walk.png`, `idle.png`, and `portrait.png` have no generation prompt.
Form rules were read from the redesign concept and redrawn to these locked
specs.

- Tool: `apps/game/tools/build_warden_assets.py`
- Canvas: RGBA PNG, own PNG encoder
- Palette: 1 transparent value + 18 visible colors defined, used inside the
  contract's 32-color cap
- Alpha: `0/255`
- Walk: `24×32` cells, 4 directions × 4 frames, foot bottoms locked
- Idle: same spec, moonlight-seed brightness and blink change in four beats
- Actual silhouette: bottom-aligned `22–24px`, head vs body/feet height
  difference `2px` or less
- Portrait: `48×48`
- Correction: widen face area on front and side so the inside of the hood
  does not look like a mask
- Correction: keep both hands and the moonlight seed against body center so
  no gun-muzzle-like horizontal protrusion appears from any facing

This keeps common generated-model drift — per-frame body proportion, foot
position, pixel size, translucent edges — out of runtime.

## Ranged moonlight-fire presentation contract

The character pose and the actual projectile origin must tell the same story.
Ranged attacks do not spawn from the feet or waist; they start from the
moonlight seed between both hands at Player-local
`MOONLIGHT_ORIGIN = Vector2(0, -10)`.

- For `0.16s` at fire, show a small blue-white casting ring at the chest and
  both-hand embers.
- Arrows and homing missiles start from the same origin, and aim direction is
  recomputed from that origin.
- A homing-missile head reads as a small moonlight seed, diamond star-core,
  and short halo instead of a long warhead and left-right fighter wings.
- Do not add a gun-firing pose to the move-animation sheets. Short casting
  VFX connects auto-attack and walking.

## App icon — Cute Moon-Seed Guardian close-up

This item was not sent to an image-generation model. Only the review
`builds/art-review/a0-player/moonlit-hero-family-concept.png` and the form
language of the post-feedback final Warden sheet were referenced, and the
following brief was produced directly as locked integer coordinates in
`apps/game/tools/build_app_icon_assets.py`.

```text
Asset type: Moonlit Beacon application icon family.
Subject: a close-up of the cute Moonlit Warden inside a round lavender-blue
hood, with a clearly visible warm face and two empty hands cupping one small
moonlight seed at the chest.
Palette: deep navy, lavender-blue, cold moon white, warm skin, tiny gold accent.
Readability: strong pixel silhouette at launcher and favicon size; face, hands,
and seed remain distinct under circle, squircle, and rounded-square masks.
Avoid: gun, weapon grip, aiming arm, beacon stand, flame, text, logo lettering,
mask, glowing eyeless face, watermark, or an existing character.
```

Production contract:

- Generate 1 SVG and 5 PNGs together: the SVG from one 108×108 logical
  grid and a locked palette, the docs PNGs from the painted launcher art
- `icon.svg` stays vector; docs `favicon.png` (32) and `logo.png` (192)
  derive from `app_icon_main.png`
- Android legacy `192×192` is opaque
- Android adaptive foreground `432×432` is graded alpha; background is 5
  opaque colors
- Every visible foreground pixel must sit inside the official guaranteed
  radius `132px` (66dp diameter) at canvas center; `--check` inspects all
  four pixel corners
- Circle/squircle review copies first crop the real 72dp mask viewport at
  center radius `144px`, enlarge to screen size, then apply the mask
- Circle/squircle/rounded-square review copies are generated at
  `builds/art-review/a4-ui/app-icon-preview.png` and not put in Git

## Player VFX — moonlight-slash production brief

This item was not sent to an image-generation model. The brief below was the
actual production input, and final pixels were generated directly with
`apps/game/tools/build_moon_slash_asset.py`.

```text
Asset type: player melee slash VFX sprite sheet for Moonlit Beacon.
Role: the Warden's most frequent auto-attack and the front/back blades of the
Full Moon attack. It must no longer share a texture with Moon Arrow.

Silhouette and motion: a right-facing crescent cut that ignites as a compact
wedge, reaches a broad 110-degree arc, breaks into a lattice-like moonlit echo,
then disappears as sparse arc fragments. Four frames in one horizontal row.

Exact sheet contract: 192×48 RGBA PNG, four 48×48 cells, one-pixel transparent
edge padding, no blank frame. The game rotates the right-facing sheet for every
attack direction.

Collision alignment: runtime center offset is 13px, the fixed hand-height pivot
is (0, -6), base range is 34px, and the hit cone is 110 degrees. Keep visible
pixels inside the compact row mask implemented by the deterministic generator.
For every visible pixel corner, include the fixed pivot as the attack rotates
through every direction. Independently combine every discrete range and arc
stack with 65 samples over the full damage-bulk interval, including unbalanced
post-drop states; require regular radial, Full Moon back radial, and cone
boundaries to retain a 0.5px safety margin. Do not change collision, range,
damage, timing, or game code.

Palette and material: deep indigo ink-glow, moon blue, blue-white blade,
white-hot core, with only one or two tiny beacon-orange pixels. Use crisp pixel
clusters and at most five alpha levels including transparency. No smooth
gradient, blur, anti-aliased vector edge, bloom baked into the image, or
high-resolution downscaling.

Readability: frame 1 must read as anticipation, frame 2 as the strongest hit,
frame 3 as a broken echo, frame 4 as decay. Keep the player and enemy shapes
visible through the effect. Original visual design only, no text, logo,
watermark, or reference to an existing game's effect.
```

Final result:

- `moon_slash.png`: `192×48`, `48×48` 4 frames
- Production local-radius cap: `9.0px`, final measured `8.515px`
- Visible tip including the base rotation pivot: `28.023px / 34px`
- Minimum radius slack across 3,640 independent-upgrade states: `0.323px`
- Full Moon back-side minimum radius slack: `4.728px`
- Cone minimum angle slack: `0.768°`
- Extra `0.5px` safety padding on all four corners of every visible pixel
- Alpha: at most 5 steps including transparency
- Existing `32×32` derived slash kept for Moon Arrow compatibility

## A2 play loop — terrain-obstacle concept

Output:
`_asset_sources/custom/a2-gameplay/concepts/terrain-obstacles.png`

```text
Use case: stylized-concept
Asset type: game terrain sprite concept sheet for a top-down 2D pixel-art action game
Primary request: design four distinct original collidable terrain obstacles for Moonlit Beacon: (1) a low cluster of moon-inscribed standing stones, (2) a fallen pale moon-birch trunk with roots, (3) a dense thorn-root thicket, and (4) a broken beacon barricade made from dark wood and small warm ember-metal brackets
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background for later removal; no floor plane
Subject: four separate obstacles arranged in a clean 2x2 grid, each fully isolated with generous padding and a clearly readable footprint for collision
Style/medium: elegant modern indie pixel art, true hard-edged pixels, top-down three-quarter view, subtle Korean-fantasy shape language without copying any existing game or asset pack
Composition/framing: square sheet, equal visual scale, no overlap, each obstacle centered in its quadrant
Lighting/mood: cool blue moonlight with very restrained warm orange beacon accents
Color palette: deep ink #141B1B, violet shadow #3B3643, moon blue #79B8CE, pale moon core #CDE1FF, ember #EF914F
Constraints: strong silhouettes at small size; opaque subjects with crisp hard edges; the background must be one uniform #ff00ff with no shadow, gradient, texture, reflection, lighting variation, or floor; do not use #ff00ff in any subject; no cast shadow; no contact shadow; no text; no UI; no watermark; no logos or trademarks
Avoid: free asset-pack look, soft painterly rendering, anti-aliased blur, realistic materials, tiny noisy details, isometric camera
```

## A2 play loop — Moon Dancer concept

Output:
`_asset_sources/custom/a2-gameplay/concepts/moon-dancer.png`

```text
Use case: stylized-concept
Asset type: original game character concept for a top-down 2D pixel-art action game
Primary request: create Moon Dancer, a fast playable heroine for Moonlit Beacon whose silhouette is unmistakably different from the Warden and from generic ninja asset packs
Subject: compact agile moon guardian with crescent-shaped wide sleeves, one flowing asymmetrical ribbon, a small ring-shaped moon weapon at her hip, short practical boots, and a subtle Korean-fantasy layered jacket; no hood, no ninja mask, no exposed midriff
Style/medium: elegant modern commercial indie pixel art, hard-edged pixels, readable at roughly 24x32 sprite scale, original design not based on any existing game
Composition/framing: one enlarged full-body top-down three-quarter character concept, neutral standing pose, full silhouette visible, generous padding
Lighting/mood: cool moonlit blue and pale lavender with a tiny warm beacon clasp
Color palette: deep ink #141B1B, violet #3B3643, moon blue #79B8CE, pale moon #CDE1FF, restrained lavender #9B7FD1, tiny ember #EF914F
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background for removal
Constraints: the background must be one uniform #ff00ff with no shadow, gradient, texture, floor, reflection, or lighting variation; do not use #ff00ff in the character; opaque crisp silhouette; no cast shadow; no contact shadow; no text; no UI; no watermark; no logos; clearly animation-friendly limbs; no free asset-pack look
Avoid: ninja costume, face mask, oversized head, ornate realism, painterly blur, anti-aliased edges, excessive accessories
```

## A2 play loop — Ember Keeper concept

Output:
`_asset_sources/custom/a2-gameplay/concepts/ember-keeper.png`

```text
Use case: stylized-concept
Asset type: original game character concept for a top-down 2D pixel-art action game
Primary request: create Ember Keeper, a slow durable playable hero for Moonlit Beacon whose silhouette is unmistakably different from the Warden, Moon Dancer, and generic ninja asset packs
Subject: compact broad-shouldered beacon guardian with a rectangular lantern-shield strapped behind one shoulder, layered dark lamellar-inspired coat, thick closed boots, short cropped hair, one heavy gauntlet, and a small warm ember core visible in the shield; no hood, no ninja mask, no cape
Style/medium: elegant modern commercial indie pixel art, hard-edged pixels, readable at roughly 24x32 sprite scale, original design not based on any existing game
Composition/framing: one enlarged full-body top-down three-quarter character concept, stable guarded stance, full silhouette visible, generous padding
Lighting/mood: cool moonlit rim light against restrained warm beacon-orange core
Color palette: deep ink #141B1B, charcoal #3B3643, slate #4A5270, moon blue #79B8CE, ember #EF914F, ember core #FFE18D
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background for removal
Constraints: the background must be one uniform #ff00ff with no shadow, gradient, texture, floor, reflection, or lighting variation; do not use #ff00ff in the character; opaque crisp silhouette; no cast shadow; no contact shadow; no text; no UI; no watermark; no logos; clearly animation-friendly limbs; no free asset-pack look
Avoid: ninja costume, face mask, oversized armor, medieval knight cliché, ornate realism, painterly blur, anti-aliased edges, excessive accessories
```

The three originals were also kept on the image generator's source path and
copied into the project's non-shipping
`_asset_sources/custom/a2-gameplay/concepts/`. `*-alpha.png` in the same
folder are review-transparent copies from Codex imagegen's
`remove_chroma_key.py` with automatic corner sampling, soft matte, and spill
cleanup. These large concept images are not put into runtime directly; they
are form references for the deterministic 1x pixel producer only.

## A3 full integration — terrain/UI/beacon visual board

Review output was archived under `_asset_sources/custom/` (gitignored). It is
a form reference only, not a runtime file.

```text
Use case: stylized-concept
Asset type: cohesive game environment, UI and VFX art-direction board for
Moonlit Beacon.

Show three clearly different top-down biomes: a moon-pine forest with pale
standing stones and root thickets, a windswept moonlit field with grass islands
and observatory fragments, and an abandoned beacon camp with dark tents,
barricades and ember metal. Add a premium dark-indigo UI strip containing a
crescent health symbol, moon projectile language and a beacon-flame emblem.

Style: original hard-edged commercial indie pixel art, dark ink outlines,
restrained Korean-fantasy shape language, readable silhouettes, limited palette.
Palette: ink navy, moon silver, teal, muted violet and a small ember-vermilion
accent. Keep each biome distinct while making the whole board feel authored by
one game.

Avoid: Ninja Adventure resemblance, generic free asset-pack shapes, copied tile
layouts, painterly blur, smooth gradients, photorealism, readable text, logo,
watermark or existing franchise characters.
```

This board was used only as a color/density/silhouette reference. The real
`nature`·`field`·`camp` compatible atlases, beacon VFX, mist, hearts, and
nine-patch panels were newly generated at 1x integer coordinates by
`build_world_assets.py` and `build_custom_ui_panels.py` so each keeps existing
consumer coordinates and frames. No generated image was cropped into runtime.
