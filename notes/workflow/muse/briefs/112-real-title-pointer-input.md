# Brief 112: restore real title taps

## The ask
“탭해도 아무런 반응을 안하네 내가 하면”. The original title must open the existing centered login chooser when the player actually clicks or touches it.

## Evidence and current tree
All accepted 4.0.0 work is in the uncommitted tree. Ordinary production main is scenes/menus/production_entry.tscn. It contains the original Title and decorative six-hero Gate; title_menu.gd handles start in _unhandled_input. ProductionEntry's root Control currently has implicit mouse_filter=STOP. The original Title and Screen explicitly IGNORE.

The director reproduced a native mouse click on the ordinary desktop window: no change. Return opened the chooser. An independent windowed probe booting the actual ProductionEntry and using Input.parse_input_event for mouse press/release at (404,310), window808x360, printed baseline_selection=false and hovered=ProductionEntry. Setting only the probe instance's root mouse_filter=IGNORE printed ignore_root_selection=true. The same probe under headless falsely passed baseline_selection=true: headless pointer GUI routing does not exercise this failure. Existing tests call title.request_start or emit pressed, so cannot guard this bug.

## Do
- Apply the smallest durable fix to the real scene/input ownership, preserving menu/modal hit testing and original visuals. Prefer explicit mouse_filter=IGNORE on decorative full-screen host root over moving start to _input (which would preempt real menus/modal controls).
- Add a focused regression to existing appropriate title/production tests or a small new registered test. Exercise actual mouse press/release and touch press/release through Input/Viewport routing in a WINDOWED real ProductionEntry test, with real title chrome and Gate present. No direct request_start, _unhandled_input call, or pressed.emit as proof of this criterion. Include title-background tap, original menu click (must open its menu without opening login), modal/footer Back click, and second title tap after returning. Do not consume disabled provider taps into a new game.
- A meaningful negative must restore STOP and fail in the windowed test, then byte-restore the candidate. Explain explicitly why a headless-only test cannot guard this native pointer regression. No claim of physical input coverage from direct signals.

## Deliverables and limits
Scene/source fix, narrow real-input regression (registered in appropriate runner if new), notes/plans/4-0-0-title-tap-login-log.md entry, report. No broad game/docs/art/auth/native changes. Preserve all accepted provider branding, light masks, consent, loading, original menus and six heroes. A separate provider-button presentation run may operate concurrently; do not modify gate_provider_buttons.gd or brand assertions in gate-entry state/layout tests. No network, history, release/store/config/protected paths. Run focused tests only; director owns full verify and native deployment.

## Acceptance
Windowed actual pointer test fails before the fix and with a deliberate STOP negative, passes after. Actual title→chooser→Back→title→chooser works, original menus still take clicks, no ScriptErrors, no visual change. Director will repeat physical native clicks, actual touch events and returning saved-game entry before accepting.
