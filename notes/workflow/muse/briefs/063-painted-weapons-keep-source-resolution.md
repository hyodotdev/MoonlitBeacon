# Brief 063: Preserve premium weapon detail at device resolution

## Director evidence
The director rendered `shot_painted_weapons` on a real display. All six packed textures are only 15–22 pixels wide and 5–9 high, and WeaponRig draws them 1:1 while inheriting global Nearest. The 4× review rigs visibly display blurry/pixel blocks; the fine lantern, ring, blade and rifle details from the original master are destroyed. The user specifically requested a premium dimensional sprite appearance instead of pixel art. Smooth flash vectors do not repair a tiny nearest-filtered bitmap.

## Do
Repack from the original full-resolution master (never upscale the already packed tiny images). Preserve roughly four source texels per logical weapon pixel and draw at compensated world scale, using appropriate per-item Linear filtering. Keep the exact logical grip, muzzle seats, projectile origins, silhouette span and all gameplay timings/sidearm priorities. Express texture-space metadata and world-space transforms explicitly so they cannot drift; tests prove both fine source detail and exact projectile-to-painted muzzle coincidence in four aims. The same production renderer must look clean at a real 2×/3× output and in the enlarged review rig. Keep twin daggers readable and the crescent handle attached.

Remove the shared regression runner edit; brief 056 explicitly reserved that file for integration, and the root now has independently accepted Journey registration. Asset-contract sidecars are required and may remain. Update their actual dimensions/statistics, the pack checks and build note without lowering coverage. No package/project/hero/player/scene/body art/cloud/native/title edits. Director renders and independently verifies before acceptance.
