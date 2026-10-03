# Side-walk art inputs, 2026-10-03

These transparent originals were generated with the built-in ImageGen tool for brief131. They are inputs to the implementer's reproducible asset packer, not final runtime atlases. Original idle, portrait, down and up art remain separately sourced from the existing turnaround masters.

## Prompt set

First make a single opposite-contact pose from each existing portrait, avoiding the old atlas's repeated leading leg:

> Create one full-body left-facing side-view walking sprite from the portrait's character identity, costume and premium soft painted2.5D chibi RPG style. Transparent background; no words, scenery, shadows or weapons. The camera-near leg trails behind toward picture right, near boot planted right of hips with heel lifted. The camera-far leg reaches ahead toward picture left with heel contact and toe raised. Near leg is lighter and overlaps the far leg at their crossing; the far leg is darker. Near visible arm swings left. Two readable anatomically joined legs and boots, stable upright head and torso, full figure visible with generous gutters.

Then make each four-frame strip from that new opposite-contact pose, using the same character as the third pose:

> Create four evenly spaced horizontal left-facing walk cells on transparency. Preserve the same character, costume, head, chest, hips and proportions throughout. Track the lighter foreground near leg and darker far leg. Cell1: near boot far left ahead, far boot right behind. Cell2: near boot planted under hips, far knee bends and far foot recovers forward off the ground. Cell3: reference opposite-contact pose, near boot far right behind, far boot far left ahead. Cell4: far boot planted under hips, near knee bends and near boot recovers forward off ground. The same near leg must exchange ahead/behind roles between cells1 and3. Keep a stable upper-body outline and support sole line, no head growth or breathing/turning while walking. No weapons, cast shadows, scenery, labels or grid lines; generous transparent gutters.

Character references:

- Warden: silver-haired guardian, navy moon hood and pale trim, navy/gold armor, leggings and silver cuff boots.
- Dancer: lilac-silver tied hair, moon ornament, violet and silver dancer costume, purple leggings and silver cuff boots.
- Keeper: stocky ginger-bearded engineer, goggles, ochre coat, leather apron/backpack and brass-buckled brown work boots.
- Knight: short chestnut-haired knight, silver plate, royal blue cape and ivory/gold embroidered tabard.
- Eclipse: silver-haired witch, dark violet moon hood, black/violet dress and gold-trim dark boots.
- Sage: black-teal ponytail and glasses, green/ivory embroidered robe and brown buckled boots.

Keeper and sage needed additional targeted correction to distinguish the opposite contact:

> Preserve cells1,2,4 and cell3 head/torso/hip registration. Change only cell3 legs below the hips to the single opposite-contact reference: near leg and lighter buckled boot behind at picture right, darker far boot ahead at picture left. Keep the four-cell layout, transparency and painted character. Do not repeat the same near boot leading left in both contact cells.

Keeper's first contact additionally needs the reciprocal depth/shading: lighter near boot ahead left, dark far boot behind right; cell3 remains dark far ahead left and lighter near behind right. This is required to judge the actual alternating legs, not merely different file hashes.

## Review status

Director approved opposing near/far contact and recovery ordering for all six donors. Keeper's reciprocal first-contact correction is included: its cell1 near boot is lighter and ahead; cell3 near boot is lighter and behind. This source review does not establish final runtime size/registration, in-game mapping or device motion. The implementer must normalize and measure; the director judges all production cells and live cycles after packing.
