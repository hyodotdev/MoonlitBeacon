---
sidebar_position: 14
title: Lesson 15 recording script
---

# Lesson 15 — Recording script

[Lesson text](../../apps/docs/course/chapter-15.mdx) · [Plan](../plans/chapter-15-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 16 min |
| Segments | 9 |
| Shot | Editor · game window · device |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:50)

**On screen** — `chapter-15-language.mp4`, `chapter-15-credits.mp4`

**Narration** — Until now all on-screen text was hardcoded in Korean.
Today we make a settings window, change language in place, and put credits in.

## 2. Translation is not the job of swapping letters (0:50 ~ 3:00)

**On screen** — Find places that contain Korean strings one by one (10 scenes, 12 in code)

**Narration** — You cannot put `if locale == "en"` in twenty-two places.
Write a key in the letter's seat and keep a table separately.

**On screen** — Write `moonlit.csv`. Change to `text = "RESULT_WIN"` and run

**Watch-outs** — Put a comma inside a translation and show the columns shifting.

## 3. Check the official docs (3:00 ~ 3:40)

**On screen** — Godot official `Internationalizing games` · `Importing translations`

## 4. The file import makes (3:40 ~ 5:30)

**On screen** — `localization/` folder. One CSV becoming two `.translation` files

**Watch-outs** — Add one more key to the CSV and run with only `--headless --quit` and show
**the key appearing as-is**. Run `--import` and it comes out.

**Narration** — We actually wandered on this once. Only the newly added key would not appear, so
you start suspecting a typo. The table was fine.

**On screen** — Run the two checks

**Narration** — A check that only looks at the table, and a check that asks the engine — you need both.
The table can be perfect and if import did not run the key still shows as-is.

## 5. Implement (5:30 ~ 13:00)

### 5-1. Letters written in a scene change on their own

**On screen** — One line `TranslationServer.set_locale("en")` and the title changes wholesale

### 5-2. Letters the code made, we change

**On screen** — Change language in pause and only HUD stays in Korean → add `_notification`

**Watch-outs** — Drop the `@onready` check, run, and show the error of putting `text` on `Nil`.

### 5-3. What we do not translate

**On screen** — Point at the logo, the language names in their own scripts / `English`, `Pixel-Boy`

**Narration** — Write "Korean" on the English screen and someone looking for the Korean-script name cannot find it.
Language names are written in their own language.

### 5-4. Split sound with buses

**On screen** — On the Audio tab, add `Music` · `Sfx` buses, set each player's `bus`

**Watch-outs** — Write steps straight into decibels and play step 1 and step 2 in turn.
There is no difference. Change to `linear_to_db()` and they spread.

**Watch-outs** — Print `linear_to_db(0)` and show `-inf`.

### 5-5. One more autoload

**On screen** — Register `Settings`. Open `records.cfg` and `settings.cfg` side by side

**Narration** — Lesson 14 said do not spam them, and we attach one more.
Settings really do have to survive across scenes. But we do not pile them onto records.
Wipe records and language should still remain.

### 5-6. Language on a first-run device

**On screen** — Run after `pm clear`. It is a Korean-language device, so it starts in Korean

**Watch-outs** — Hand-edit `locale` in `settings.cfg` to `de` and run.

### 5-7. The same scene in two places

**On screen** — The same panel appearing on the title and in pause

**Narration** — Same idea as growing enemies with one `.tres` in Lesson 13.

### 5-8. When the window opens, hide what is behind it

**On screen** — Two renders before hiding. The logo showing through and pause buttons overlapping

**Narration** — 0.78 means 22% of the back remains. Bright letters show through as-is.

### 5-9. Credits are an obligation

**On screen** — The license table in `third-party.md`. Marks on MIT and OFL

**Narration** — The two CC0s have no obligation, but we still list them.
Leaving out the names of people who let you use it for free is not a law problem, it is a manners problem.

**Watch-outs** — Leave `grow_vertical = 2` and the label grows upward too and overlaps the intro line.

## 6. Confirm (13:00 ~ 14:30)

**On screen** — Device. Settings → English → Credits → Close → quit the app → relaunch (English kept)
→ start the game → pause → settings → HUD is English

## 7. Get it wrong on purpose (14:30 ~ 15:30)

Seven things in turn. What section 5 already showed, mark briefly.

## 8~9. Completion criteria and homework (15:30 ~ 16:00)

**Narration** — Homework 1, try adding one more Japanese column. You do not change a single line of code.
That is why we pulled it into a table.
