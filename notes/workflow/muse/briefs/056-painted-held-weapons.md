# Brief 056: Make the held weapons match the painted heroes

## The ask
“칼로 베기 총으로 쏘기 대포로 쏘기 ... 멋지게 잘 구성”, then “고급 이미지 느낌 ... 입체감”. In the director's actual new-art actor render, the bodies are shaded sprites while the held weapons remain bright un-antialiased primitive bars. Replace the carried silhouettes with original shaded equipment while keeping every existing attack mechanic and real muzzle seat.

## Where things stand
`scripts/actors/weapon_rig.gd` draws all six held weapons and brief real-shot flashes; `Player.muzzle_origin` shares its named muzzle constants. A separate art copy is changing actor/resources/terrain only; do not import or edit its files. New original built-in-generated master is `notes/workflow/muse/art/4-0-0/painted-weapons.png`, 1536×1024 RGBA, 2 columns by 3 rows, right-facing weapons. Row 1 Warden sword / Dancer twin daggers; row 2 Keeper lantern pistol / Knight ring cannon; row 3 Eclipse crescent reaper / Sage needle rifle. Source has generous alpha padding and material shading. Current rig self_modulate 2.4 can wash the paint out; measure against actual hero lighting.

## Do
Deterministically extract/pack the six source weapons into bounded runtime textures with clean alpha and calibrated grip/muzzle metadata. Engineering crop/scale is allowed; no repainting or invented bitmap art through code. Integrate in WeaponRig using the same aim, depth, attack-profile signals and muzzle constants. Account for double dagger grips and crescent silhouette, natural hand attachment in four hero directions, bounded recoil/flash motion and reduced-motion compatibility. No weapon animation may imply a shot that did not happen. Keep the existing brief combat flashes readable and smooth their primitive edges where appropriate. Preserve exact projectile spawn seats and attack timing/damage/controls.

Add a new direct-callable test and windowed production rig harness showing all six weapons at camera scale and close scale, four aim directions, normal/fire/clear states. Check alignment and silhouette distinctions, alpha/margins, no matte box or washout, no flash stuck after pause/result/clear, and bounded asset/node/draw costs. Update the manifest with the six original runtime textures and author note/source mapping. Use a separate new packing tool; do not change the other round's `pack_painted_world.py`.

## Do not
No player.gd/scenes/hero resources/room/terrain, existing title/UI/arena/story/native/cloud, existing shared runner/package/project/presets, stores/credentials/guards/workflows, network/device/git-history operations. No new combat roles or rebalancing, no commercial art, no marketing recapture. Changes own WeaponRig plus new textures/tool/test/harness/manifest row and `notes/plans/4-0-0-painted-weapons-log.md` only.

## Judgment
Director runs focused and existing weapon/combat tests, disables a placement/flash guard to prove a meaningful regression, checks deterministic packing, and inspects real held poses and firing in the arena. A painted gun's tip and real projectile spawn remain visually coincident; silhouettes are visibly sword/twin daggers/lantern gun/ring cannon/crescent/rifle. Actor compatibility is judged after the independent body-art integration. Report exact geometry and no provider/device claims.
