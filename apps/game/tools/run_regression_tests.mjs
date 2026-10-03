// Run save and result-route regression tests isolated from real user data.
//
// Vault always uses `user://vault.cfg`. Running the Godot project as usual
// would overwrite shards the developer earned in play, so this runner builds
// a temporary HOME/XDG_DATA_HOME/APPDATA and passes them only to the test
// process.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { reportGodotNotFound, resolveGodot } from '../../../scripts/godot.mjs';
import { isExpectedTranslationBootstrap } from './godot_error_filter.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repository = resolve(here, '../../..');
const temporaryHome = mkdtempSync(join(tmpdir(), 'moonlit-vault-test-'));

const commonArguments = [
  '--headless',
  '--path',
  resolve(repository, 'apps/game'),
];
const translationOutputs = [
  resolve(repository, 'apps/game/localization/moonlit.en.translation'),
  resolve(repository, 'apps/game/localization/moonlit.ja.translation'),
  resolve(repository, 'apps/game/localization/moonlit.ko.translation'),
  resolve(repository, 'apps/game/localization/moonlit.zh_CN.translation'),
  resolve(repository, 'apps/game/localization/moonlit.zh_TW.translation'),
];
const checks = [
  ['Reimport resources', ['--editor', '--quit'], false, true],
  ['Confirm resource import', ['--editor', '--quit'], false, false],
  ['Privacy and support external links', ['res://tests/test_external_links.tscn'], true, false],
  ['Anonymous analytics consent and settings save', ['res://tests/test_analytics_consent.tscn'], true, false],
  ['Credits localization and supporter layout', ['res://tests/test_credits_layout.tscn'], true, false],
  ['Quit five-language title fit and Cancel default', ['res://tests/test_quit_layout.tscn'], true, false],
  ['Expedition rules: curve, forks, mutations, omens', ['--script', 'res://tests/test_expedition.gd'], true, false],
  ['Fork travel: one gate on cycle 1, two from cycle 2', ['res://tests/test_fork_travel.tscn'], true, false],
  ['Fork-gate captions readable at every rim', ['res://tests/test_gate_captions.tscn'], true, false],
  ['Omens: the endless stretch changes one rule at a time', ['res://tests/test_omens.tscn'], true, false],
  ['Raid formations: a wall, three pods, two beats', ['res://tests/test_raid_formations.tscn'], true, false],
  ['Guardian mutations: echo, spiral, summoner, frenzy, aegis, meteors', ['--script', 'res://tests/test_guardian_mutations.gd'], true, false],
  ['Guardian staging: numeral, mutation banner, called pack, trial', ['res://tests/test_guardian_staging.tscn'], true, false],
  ['Skills: cards unlock by cycle, each skill does what it says', ['res://tests/test_skills.tscn'], true, false],
  ['Hero custom sheets and fallback', ['--script', 'res://tests/test_hero_visuals.gd'], true, false],
  ['Six-hero sidegrade combat profiles', ['--script', 'res://tests/test_hero_combat_profiles.gd'], true, false],
  ['Six real primary weapons on the arena path', ['res://tests/test_hero_weapons.tscn'], true, false],
  ['Original combat audio wiring and bounds', ['res://tests/test_combat_audio.tscn'], true, false],
  ['Shrine hero full-body previews', ['res://tests/test_shrine_portraits.tscn'], true, false],
  ['IAP hero full-body previews', ['res://tests/test_iap_hero_previews.tscn'], true, false],
  ['Spirit and guardian custom sheets', ['--script', 'res://tests/test_spirit_visuals.gd'], true, false],
  ['Painted-world resource contract', ['--script', 'res://tests/test_painted_world.gd'], true, false],
  ['Six-hero side-walk gait and preserved bytes', ['--script', 'res://tests/test_hero_gait.gd'], true, false],
  ['Painted held weapons: art, seats, light, and flash', ['--script', 'res://tests/test_painted_weapons.gd'], true, false],
  ['Night-forest painted atlas addressing', ['--script', 'res://tests/test_night_forest_atlas.gd'], true, false],
  ['Guardian burst vs normal-hit balance', ['--script', 'res://tests/test_guardian_balance.gd'], true, false],
  ['Guardian second-answer moves', ['--script', 'res://tests/test_guardian_moves.gd'], true, false],
  ['Guardian new styles: owl dive, toad leap, sentinel glyphs', ['--script', 'res://tests/test_guardian_new_styles.gd'], true, false],
  ['Telegraph floors: no warning is shorter than a person can answer', ['--script', 'res://tests/test_telegraph_floors.gd'], true, false],
  ['Volley fairness: what is fired is what is drawn, and there is a way through', ['--script', 'res://tests/test_volley_fairness.gd'], true, false],
  ['Small bullets: one field of 150, and the emitters that shoot them', ['--script', 'res://tests/test_bullet_field.gd'], true, false],
  ['Barrage fairness: slow, gappy, turning bullets, never a flood', ['--script', 'res://tests/test_barrages.gd'], true, false],
  ['Play bot modes: gauntlet fights once, natural draws its loops', ['--script', 'res://tests/test_play_bot_modes.gd'], true, false],
  ['Relic dual-effect resonance and loss clear', ['--script', 'res://tests/test_relic_resonance.gd'], true, false],
  ['Missile growth curve', ['--script', 'res://tests/test_missile_progression.gd'], true, false],
  ['Missile combat loop', ['res://tests/test_missile_loop.tscn'], true, false],
  ['Late-game combat performance and space checks', ['res://tests/test_late_game_performance.tscn'], true, false],
  ['Vault purchases and migration', ['--script', 'res://tests/test_vault.gd'], true, false],
  ['IAP purchase, restore, and duplicate blocking', ['--script', 'res://tests/test_iap_store.gd'], true, false],
  ['Player identity: durable public ID, guest/cloud, conflicts', ['--script', 'res://tests/test_player_identity.gd'], true, false],
  ['Identity registration: real bridge before host, durable guest, live arena', ['res://tests/test_identity_registration.tscn'], true, false],
  ['Terrain structures and safe movement', ['--script', 'res://tests/test_room_terrain.gd'], true, false],
  ['Room depth: shadows, floor life, mist and actor lighting', ['--script', 'res://tests/test_room_depth.gd'], true, false],
  ['Terrain cycling and loot wiring', ['res://tests/test_terrain_integration.tscn'], true, false],
  ['Beacon and cycle two-way choice modal', ['res://tests/test_run_choice_panel.tscn'], true, false],
  ['Story acts, chronicle, and per-hero voice', ['res://tests/test_story_structure.tscn'], true, false],
  ['Journey checkpoints, gate retry, and story episodes', ['res://tests/test_journey.tscn'], true, false],
  ['Cloud transport bounds and statuses', ['--script', 'res://tests/test_cloud_transport.gd'], true, false],
  ['Cloud identity registration and restore', ['--script', 'res://tests/test_cloud_identity.gd'], true, false],
  ['Cloud checkpoint queue, guards, and conflicts', ['--script', 'res://tests/test_cloud_checkpoint.gd'], true, false],
  ['Cloud Hall best score, board, and rank', ['--script', 'res://tests/test_cloud_hall.gd'], true, false],
  ['Cloud account deletion order and local store', ['--script', 'res://tests/test_cloud_account.gd'], true, false],
  ['Cloud coordinator owned-journey orchestration', ['res://tests/test_cloud_coordinator.tscn'], true, false],
  ['Production host entry, accounts, and HUD rank', ['res://tests/test_production_host.tscn'], true, false],
  ['Moon gate entry layout in every locale', ['res://tests/test_gate_entry_layout.tscn'], true, false],
  ['Moon gate entry states, panels, and motion', ['res://tests/test_gate_entry_state.tscn'], true, false],
  ['Forecourt party walks its ground routes, sheets, and clearance', ['res://tests/test_forecourt_party.tscn'], true, false],
  ['Forecourt stride follows measured travel', ['res://tests/test_forecourt_cadence.tscn'], true, false],
  ['Moon gate loading: first paint, cancel, honest errors', ['res://tests/test_gate_loading.tscn'], true, false],
  ['Moon gate exported translations in every locale', ['--script', 'res://tests/test_gate_entry_exported_locales.gd'], true, false],
  ['Place memories, fork clues, and the road home', ['res://tests/test_place_memories.tscn'], true, false],
  ['Beacon choice and overcharge state transitions', ['res://tests/test_beacon_choice.tscn'], true, false],
  ['Compass off-screen checks and blink suppression', ['res://tests/test_beacon_compass.tscn'], true, false],
  ['Anonymous analytics consent, queue, and allowlist', ['--script', 'res://tests/test_analytics.gd'], true, false],
  ['Title localized version label', ['res://tests/test_title_version.tscn'], true, false],
  ['Title transition veil and worker load', ['res://tests/test_title_transition.tscn'], true, false],
  ['Title tap opens the login chooser over the original title', ['res://tests/test_title_tap.tscn'], true, false],
  ['Production title capture forwards real title proof', ['res://tests/test_production_title_capture.tscn'], true, false],
  ['Store capture title-ready boot marker', ['res://tests/test_store_capture_title_ready.tscn'], true, false],
  ['Direct-distribution probe resolves the embedded title', ['res://tests/test_direct_distribution_title.tscn'], true, false],
  ['Store capture hides debug UI', ['--script', 'res://tests/test_store_capture_clean_ui.gd'], true, false],
  ['Pixel 10 hero-direction capture board', ['res://tests/test_hero_direction_capture.tscn'], true, false],
  ['Result screen five-language layout', ['res://tests/test_result_layout.tscn'], true, false],
  ['Result depth line past the win', ['res://tests/test_result_depth.tscn'], true, false],
  ['Result, ladder, and shrine route', ['res://tests/test_result_route.tscn'], true, false],
  ['Versioned ladder save, sort, and display', ['res://tests/test_ladder.tscn'], true, false],
];

let status = 1;
try {
  // Resolve the binary with the shared finder before overwriting HOME for
  // isolation, so both Windows winget and Linux ~/.local installs are found.
  const search = resolveGodot();
  if (!search.bin) {
    reportGodotNotFound(search);
    process.exitCode = 127;
  } else {
    status = 0;
    for (const [
      label,
      argumentsForCheck,
      isolated,
      allowTranslationBootstrap,
    ] of checks) {
      console.log(`\n[${label}]`);
      const translationsMissingBefore = translationOutputs.some(
        (path) => !existsSync(path),
      );
      const run = spawnSync(search.bin, [...commonArguments, ...argumentsForCheck], {
        cwd: repository,
        encoding: 'utf8',
        maxBuffer: 10 * 1024 * 1024,
        shell: false,
        // Import does not run the game, so it uses the usual editor settings
        // with the SDK registered. Only the real test process is fully
        // isolated into the temporary user directory.
        env: isolated
          ? {
              ...process.env,
              HOME: temporaryHome,
              XDG_DATA_HOME: join(temporaryHome, '.local', 'share'),
              APPDATA: join(temporaryHome, 'AppData', 'Roaming'),
              MOONLIT_VAULT_TEST_ROOT: temporaryHome,
            }
          : process.env,
      });
      if (run.stdout) process.stdout.write(run.stdout);
      if (run.stderr) process.stderr.write(run.stderr);
      status = run.status ?? 1;
      // Godot can print a runtime ERROR and still exit 0. Even if the state
      // transition is right, an error while opening a screen fails the
      // regression.
      const engineOutput = `${run.stdout ?? ''}\n${run.stderr ?? ''}`;
      if (status === 0 && engineOutput.includes('ERROR:')) {
        const expectedBootstrap = allowTranslationBootstrap
          && isExpectedTranslationBootstrap({
            engineOutput,
            translationsMissingBefore,
            translationsPresentAfter: translationOutputs.every(
              (path) => existsSync(path),
            ),
          });
        if (expectedBootstrap) {
          console.log(
            `[${label}] First import created translation resources. `
            + 'Checking that the next import has no errors.',
          );
        } else {
          console.error(`[${label}] Found Godot ERROR logs.`);
          status = 1;
        }
      }
      if (status !== 0) break;
    }
    process.exitCode = status;
  }
} finally {
  // Delete only the exact subdirectory mkdtempSync created.
  if (temporaryHome.startsWith(join(tmpdir(), 'moonlit-vault-test-'))) {
    rmSync(temporaryHome, { recursive: true, force: true });
  }
}
