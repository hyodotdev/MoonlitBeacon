# Brief 108: make real loading stage text visible from first paint

## The ask
“이런느낌으로 로딩도 깔끔하게 보완해주라 시작 로딩에니메이션 연출도 봐주고”
“그냥 ㅇ원래에서 tab to start 누르면 게스트, 구글, 애플 로그인으로 시작하게 하면 안돼?”
Keep the now accepted original title and tap-to-login. Fix one newly measured loading defect.

## Evidence and state
All foundations and title round 5 are accepted in the current working tree. Do not change them. The director ran a windowed isolated probe with the real ProductionHost, actual guest choice, actual Start, cold Arena worker load. On all four visible loading frames the real `GateLoadingOverlay/LoadingCard/Stack/Stage` holds `준비하는 중…`, visible=true, but its actual rect is `(240,118,328,1)`: one pixel high, so no stage text paints. FIRST_PAINT_FRAMES=2 works; first two frames issued=false, later issued=true. Arena enters correctly. A separate actual image confirms bar/status/cancel visible but stage missing. The card's measured height does not force this wrapped clipped Label's actual minimum height. This is a real glyph clipping issue, not fake loading and not a slow load request.

## Do
- In gate_loading_overlay.gd reserve the stage label's actual wrapped font height at the current content width before layout/first paint; ensure proper layout when changing stage text, error/cancel/retry and resizing. Check any similarly wrapped detail label in this same overlay, without modifying unrelated gate components.
- Add meaningful actual label rect vs rendered line-height assertions to the existing loading/layout test suites for first paint, real text changes, loading and error/cancel states, all five languages and normal/wide/tablet framing. Existing pass counts and all generation/cancel/drain assertions remain intact.
- Run only affected loading/state/layout suites and compile check once. Break only the new sizing behavior and confirm the new actual glyph assertion fails, restore it. Report exact results/counts. The director renders pixels and handles final full verification.

## Do not
- No changes to original intro/menu buttons, login provider readiness, Host/Journey/cloud, native SDKs, public config, scenes other than necessary loader, assets, version, package, protected files, global texture settings or unrelated tests.
- No fake time-based progress, no artificial hold/delay, no synchronous Arena preload, no worker waits, no test budget relaxation or skipped assertions. No broad full-suite reruns, screenshots, network, devices, stores or git history.

## Acceptance
- Before request_issued at first paint, actual Stage rect height >= needed font line height (and >= needed wrapped height capped to existing max_lines_visible for longer stages), with actual glyphs visible. All displayed wrapped detail lines likewise have actual readable height.
- Loading card/buttons remain inside 808x360, 840x360 and 808x606, every locale. Labels do not overlap the progress/status/buttons. Real progress and all current generation, cancel, stale-result, drain contracts unchanged.
- Existing focused suites pass without SCRIPT ERROR and added assertion has a demonstrated negative control. Director's real cold ProductionEntry frame capture visibly reads the stage and still enters actual Arena.

## Deliverables
apps/game/scripts/ui/gate_loading_overlay.gd; existing relevant loader/layout test files only; distinct notes/plans/4-0-0-loading-glyph-log.md. No other author notes or docs edits.
