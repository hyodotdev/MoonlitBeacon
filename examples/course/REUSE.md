# Reuse manifest — course practice sources

Every binary under `src/assets/` is stored exactly once and copied into
lesson outputs by `scripts/course-create.mjs` per the per-lesson map in
`src/manifest.json`. No ignored original packs, no caches, no ZIPs.

## Third-party: Ninja Adventure Asset Pack (CC0 1.0 Universal)

Author: Pixel-Boy, AAA. Source: https://pixel-boy.itch.io/ninja-adventure-asset-pack
License text: `licenses/CC0-1.0.txt` (copied from `apps/game/docs/licenses/`).
Credit not required; recorded here anyway.

| File | Upstream selection | First lesson | Output path |
| --- | --- | --- | --- |
| `art/tileset_camp.png` | camp tileset (23×9, beacon hearth at 192,80,32,30) | 1 | `assets/third_party/ninja_adventure/tilesets/tileset_camp.png` |
| `art/tileset_nature.png` | nature tileset (round/pine/dark trees at y 0) | 2 | `assets/third_party/ninja_adventure/tilesets/tileset_nature.png` |
| `art/raylight.png` | moonlight shafts (216×102, three shafts) | 1 | `assets/third_party/ninja_adventure/fx/raylight.png` |
| `art/ninja_walk.png` | NinjaBlue walk (64×64, 4 cols × 4 rows) | 5 | `assets/third_party/ninja_adventure/actor/ninja_walk.png` |
| `art/ninja_idle.png` | NinjaBlue idle (64×16, 4 cols × 1 row) | 5 | `assets/third_party/ninja_adventure/actor/ninja_idle.png` |
| `art/spirit.png` | spirit (64×64, 4 cols × 4 rows) | 8 | `assets/third_party/ninja_adventure/actor/spirit.png` |
| `art/spirit_bat.png` | night bat (64×64, 4 cols × 4 rows) | 13 | `assets/third_party/ninja_adventure/actor/spirit_bat.png` |
| `art/spirit_ember.png` | ember spirit (64×64, 4 cols × 4 rows) | 13 | `assets/third_party/ninja_adventure/actor/spirit_ember.png` |
| `art/guardian.png` | forest guardian (250×50, 5 cols × 1 row) | 13 | `assets/third_party/ninja_adventure/actor/guardian.png` |
| `audio/arena_theme.ogg` | `Audio/Musics/27 - Chill.ogg`, renamed, audio as-is | 3 | `assets/third_party/ninja_adventure/audio/music/arena_theme.ogg` |
| `audio/guardian_theme.ogg` | guardian music from the same CC0 pack, byte-identical to the shipping selection, audio as-is | 13 | `assets/third_party/ninja_adventure/audio/music/guardian_theme.ogg` |
| `audio/title_theme.ogg` | title music, renamed, audio as-is | 3 | `assets/third_party/ninja_adventure/audio/music/title_theme.ogg` |
| `audio/ui_confirm.ogg` | Kenney UI Audio `Audio/click1.ogg`, renamed, audio as-is | 1 | `assets/third_party/kenney/ui_audio/ui_confirm.ogg` |

Kenney UI Audio is a separate CC0 pack by Kenney (https://kenney.nl/assets/ui-audio),
covered by the same `CC0-1.0.txt`.

## Third-party: Nexon MapleStory Light (free use, attribution required)

Author: NEXON Korea. Source: https://maplestory.nexon.com/Media/Font
Terms (per `apps/docs/docs/assets/third-party.md`): free use, commercial and
embedding allowed; sale and modification forbidden; attribution required. No
license text ships upstream, so none is copied — this entry plus the output
`docs/licenses/THIRD_PARTY.txt` carry the attribution instead. The file is
used byte-identical; it is not modified.

| File | First lesson | Output path |
| --- | --- | --- |
| `fonts/MaplestoryLight.ttf` | 1 | `assets/third_party/fonts/MaplestoryLight.ttf` |

## Original derived work (MIT, same as the shipping game — see MIT-LICENSE.txt)

Reused byte-identical from `apps/game/assets/derived/ui/` (sticks, ring)
and `apps/game/assets/derived/objectives/` (moon gate):

| File | First lesson | Output path |
| --- | --- | --- |
| `art/stick_base.png` | 6 | `assets/derived/ui/stick_base.png` |
| `art/stick_knob.png` | 6 | `assets/derived/ui/stick_knob.png` |
| `art/charge_ring.png` | 7 | `assets/derived/ui/charge_ring.png` |
| `art/moon_gate.png` | 9 | `assets/derived/objectives/moon_gate.png` |

## Original practice work (MIT — see MIT-LICENSE.txt)

| File | Notes | First lesson | Output path |
| --- | --- | --- | --- |
| `art/spark.png` | 16×16 soft radial dot, generated deterministically (pure-stdlib script, 242 bytes), beacon-flame particle texture | 2 | `assets/course/spark.png` |

## License texts shipped into every lesson output

- `docs/licenses/MIT-LICENSE.txt` — byte-identical copy of the repository root
  `LICENSE` (MIT, Copyright (c) 2026 Hyo Dev); covers the derived and practice
  originals above.
- `docs/licenses/CC0-1.0.txt` — CC0 packs above.
- `docs/licenses/THIRD_PARTY.txt` — MapleStory attribution + derived/original note.
