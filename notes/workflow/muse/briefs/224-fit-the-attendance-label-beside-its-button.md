# Brief 224: fit the attendance label beside its button

## The ask
"그리고 알림은 설정에서 안받게 할 수도 있게 해야하고"
Keep the new attendance setting readable in every supported language.

## Confirmed defect
The actual Android emulator settings screenshot at 2424x1080 shows English `Attendance reminders` clipped underneath its adjacent button. The director's existing actual-window evidence confirms the label grows to rect (214,229,164,34) while the button begins at x368: ten pixels overlap. The previous visual probe checked viewport containment only, so it missed this sibling overlap. The source is `_ensure_reminder_row` in `apps/game/scripts/ui/settings_panel.gd`: a 128px label allocation with fixed 15px font, but Godot's minimum width expands it.

## Do
- Fit the reminder label's localized text into its allocated column with a comfortable visible gap before the button. Preserve the established panel skin and settings locations. A measured font fit or careful bounded wrapping is acceptable; avoid unreadably tiny type.
- Add a meaningful regression checking both actual label minimum/text bounds and sibling separation for all five locales, with on/off/denied/unknown/unsupported states. Make sure translation updates and repeated opening recompute correctly.
- Keep lazy node creation and the late-game node ceiling. Run focused tests and report exact commands.

## Do not
Do not change rewards, scheduling, native permissions, privacy export, existing marketing screenshots or other menus. Do not simply clip the text or hide the label. Do not relax viewport/node budgets.

## Acceptance
Actual rendered label and button do not overlap at 808x360, 808x532 and 808x606 in every locale. At least 6 internal pixels separate visible text from the button chrome. The complete reminder label remains readable and the status text fits its own button. No extra dormant combat nodes. The director will independently render the settings and inspect the English screen.

## Deliverables
Narrow settings fix and registered regression evidence. No new assets.
