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
  ['Hero custom sheets and fallback', ['--script', 'res://tests/test_hero_visuals.gd'], true, false],
  ['Six-hero sidegrade combat profiles', ['--script', 'res://tests/test_hero_combat_profiles.gd'], true, false],
  ['Shrine hero full-body previews', ['res://tests/test_shrine_portraits.tscn'], true, false],
  ['IAP hero full-body previews', ['res://tests/test_iap_hero_previews.tscn'], true, false],
  ['Spirit and guardian custom sheets', ['--script', 'res://tests/test_spirit_visuals.gd'], true, false],
  ['Guardian burst vs normal-hit balance', ['--script', 'res://tests/test_guardian_balance.gd'], true, false],
  ['Guardian second-answer moves', ['--script', 'res://tests/test_guardian_moves.gd'], true, false],
  ['Relic dual-effect resonance and loss clear', ['--script', 'res://tests/test_relic_resonance.gd'], true, false],
  ['Missile growth curve', ['--script', 'res://tests/test_missile_progression.gd'], true, false],
  ['Missile combat loop', ['res://tests/test_missile_loop.tscn'], true, false],
  ['Late-game combat performance and space checks', ['res://tests/test_late_game_performance.tscn'], true, false],
  ['Vault purchases and migration', ['--script', 'res://tests/test_vault.gd'], true, false],
  ['IAP purchase, restore, and duplicate blocking', ['--script', 'res://tests/test_iap_store.gd'], true, false],
  ['Terrain structures and safe movement', ['--script', 'res://tests/test_room_terrain.gd'], true, false],
  ['Terrain cycling and loot wiring', ['res://tests/test_terrain_integration.tscn'], true, false],
  ['Beacon and cycle two-way choice modal', ['res://tests/test_run_choice_panel.tscn'], true, false],
  ['Beacon choice and overcharge state transitions', ['res://tests/test_beacon_choice.tscn'], true, false],
  ['Compass off-screen checks and blink suppression', ['res://tests/test_beacon_compass.tscn'], true, false],
  ['Anonymous analytics consent, queue, and allowlist', ['--script', 'res://tests/test_analytics.gd'], true, false],
  ['Title localized version label', ['res://tests/test_title_version.tscn'], true, false],
  ['Title transition veil and worker load', ['res://tests/test_title_transition.tscn'], true, false],
  ['Store capture hides debug UI', ['--script', 'res://tests/test_store_capture_clean_ui.gd'], true, false],
  ['Pixel 10 hero-direction capture board', ['res://tests/test_hero_direction_capture.tscn'], true, false],
  ['Result screen five-language layout', ['res://tests/test_result_layout.tscn'], true, false],
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
