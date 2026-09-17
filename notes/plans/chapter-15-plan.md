# Lesson 15 — Plan

## Official tutorial mapping

Outside the official intro course. See `Internationalizing games` · `Importing translations` ·
`TranslationServer` · `AudioServer`.

## Goal

Build a settings window and change language **in place**. Control music and SFX separately.
Add credits.

## Changes

### 1. Keys and a translation table — the core of this lesson

On-screen text is scattered across twenty-two places (10 scenes, 12 in code).
You cannot put `if locale == "en"` in twenty-two places.

One sheet: `localization/moonlit.csv`. In scenes, `text = "RESULT_WIN"`.

| | Does it change automatically? |
| --- | --- |
| `text` written in a scene | **Yes** — the engine notifies `Control` |
| Strings built in code | **No** — receive `NOTIFICATION_TRANSLATION_CHANGED` and redraw |

### 2. Import

:::danger `--headless --quit` does not import
We edited the CSV and ran, and `CREDITS_SOUND` showed as-is on screen.
You must run `--import` for `.translation` to be rebuilt.

Confirmed on a clean clone too. `--quit` alone **cannot even open the main scene.**
CI already runs a `--quit --editor` warmup, so it passes.
:::

Do not put `.translation` in git. Put two checks instead.

| Check | What |
| --- | --- |
| `check-locale.mjs` | Empty cells · dupes · column count, used keys in the table, project.godot refs |
| `tools/check_locale.gd` | Whether both languages **actually load** |

The first alone cannot catch a missed import. The table can be perfect and the key still shows as-is.

### 3. What we do not translate

The logo (the Korean title), language names in their own scripts (Korean written in Korean / `English`), proper nouns `Pixel-Boy`/`Galmuri`,
symbols `+`/`-`. Turn them off with `auto_translate_mode = 2`.

Write "Korean" on the English screen and **someone looking for the Korean-script name cannot find it.**

### 4. Audio buses

It was one `Master`. Make `Music` and `Sfx` and set each player's `bus`.

:::warning Do not write steps straight into decibels
The ear hears on a log. Hold a ratio and `linear_to_db()`.
5→0.0 · 4→−1.9 · 3→−4.4 · 2→−8.0 · 1→−14.0 dB.
0 is `linear_to_db(0) = -inf`, so handle it separately with `MUTE_DB` and `set_bus_mute()`.
:::

### 5. One more autoload — `Settings`

Lesson 14 wrote "do not spam autoloads." Settings really do have to survive across scenes.

Do not pile them onto `Records`; use a separate file. Records are play results; settings are taste.
**Two autoloads that each do one thing** beat one that does two.

A first-run device looks at `OS.get_locale_language()`. Once chosen, that value stays.
A save file can be hand-edited, so filter with `if saved in LOCALES`.

### 6. The same scene in two places

The settings window is on the title and in pause. **One scene.**
Possible because the panel holds no values and listens to `Settings.changed`.

### 7. When the window opens, hide what is behind it

:::danger Translucent does not mean "overlap is fine"
Covering at 0.78 still let the `Moonlit Beacon` logo and the three `Paused` buttons
show through between the settings rows. Learned by rendering.

`$Ui/Screen.visible = false` · `_pause.set_overlay_visible(false)`.
Leave the paused state as-is; just do not show it.
:::

### 8. Credits

MIT (Godot) and OFL (Galmuri) have a **credit obligation**. The two CC0s do not, but we still list them.
The copy matches "text to show on the credits screen" in `third-party.md`.

First layout used `grow_vertical = 2` and the label grew past its min size
**upward too**, overlapping the intro line. `grow_vertical = 1` so it only grows down.

## Verification

| | |
| --- | --- |
| Translation | 32 keys, two languages, 0 unused keys |
| Voice check | a missing key exits 1 |
| Volume | 5→0.0 · 1→−14.0 · 0→−80.0 dB + mute |
| Save | locale·music·sfx in `user://settings.cfg` |
| Device title | Settings → English → Credits → Close, all correct |
| Device relaunch | English kept after `am force-stop` |
| Device in-game | Pause → Settings → English, HUD becomes `Beacons 0/3 Dash` |

## Completion criteria

- [ ] Language changes in place
- [ ] Proper nouns do not change
- [ ] Music and SFX separately
- [ ] Survives off and on
- [ ] Title and pause share the same settings scene
- [ ] Credits include MIT and OFL
- [ ] `pnpm verify` 0

## Deferred to Lesson 16

- Android back (`NOTIFICATION_WM_GO_BACK_REQUEST`) — currently it quits the app
- Signed APK, store page, itch.io

## Not this lesson

- Three or more languages — stop at making it work if you add a CSV column
- Key remapping · resolution settings — it is a touch-only, portrait-locked game, so there is nothing to pick
