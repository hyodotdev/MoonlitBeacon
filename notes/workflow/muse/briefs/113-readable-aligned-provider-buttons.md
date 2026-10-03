# Brief 113: readable and aligned provider buttons

## The ask
“버튼 디자인도 좀 이상한데 로고도 정렬이 안맞고 가운데 글씨도 크기가 다르고... 구글 로그인은 잘 안보이고 애플로그인도 애플로그인 글씨는 하얗게 구글 로그인 글씨는 까맣게 해야할듯”. Fix the visible chooser the user rejected, retaining official assets and honest capability state.

## Confirmed state
Accepted 110/111 is now in the real tree. scripts/ui/gate_provider_buttons.gd uses Google14px versus Apple19px, and disabled text alpha0.38 for both. User supplied the actual Korean screen: Google text appears light gray on white, Apple gray on black, Google and Apple ink centers differ horizontally, type sizes differ. Director independently saw the same in the ordinary English window. Button.alignment=CENTER centers text, but icon_alignment defaults LEFT, so the source comment claiming a centered icon+text group is false. Original title/fire/six heroes and 111 light isolation are good and must stay.

Official sources (already supplied runtime assets; no download needed):
- https://developers.google.com/identity/branding-guidelines : white/#7477751px/#1f1f1f, Google Sans Medium14/20, untouched gradient Super G; preserve aspect, platform padding and equal prominence. Google must be at least as prominent as Apple.
- https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple : custom logo+text buttons may adjust typography/alignment; full padded official artwork height matches button height, no added vertical padding, surrounding clearspace>=button height/10. User has approved Apple EA1677 already.

## Do
- Disabled/unconfigured remains logically disabled and its separate ready/not-ready status remains honest, but label ink must stay fully opaque: Google#1f1f1f on white; Apple white on black. Never fake capabilities or turn an unconfigured provider on for a screenshot. Preserve official logo colors in every state.
- Match the two titles' actual visual size and baseline, including Korean. Default to Google14px Medium and Apple14px with a matching reading face/metrics, which preserves Google's explicit brand type; custom Apple typography is permitted. If a larger uniform size is necessary, justify from guideline and demonstrate equal prominence. Do not keep Apple19 against Google14. Guest retains its authored face.
- Deliberately align logo+title as a coherent CENTERED GROUP for each door (icon_alignment=CENTER is the likely small correction), with the group centered on the same button axis, matched type/baseline, equal44px height. Pin actual behavior instead of trusting the existing false comment. Preserve platform logo/text gaps, complete padded Apple file and intact G. If different official artwork widths cause a small glyph-center offset, compensate through layout while preserving artwork padding/aspect. Do not crop/reshape Apple or fabricate logo pixels. Keep text contained in all five locales and three framings. When centered group is used, compare group centroid and type baselines rather than requiring the different word lengths to place logo ink at identical x.
- Update meaningful existing brand/state/layout assertions to the new user-required typography, opaque ink and actual alignment. Keep prior mandatory consent/full-card/glyph/light/readiness guards. Render evidence for actual unconfigured Korean and English chooser plus ready TEST fixture, disabled/hover/pressed/focus. Director owns real window screenshots. Fix all stale source/docs claims about dimmed text/old sizes.

## Deliverables and limits
Only provider factory and necessary existing brand tests plus notes/plans/4-0-0-provider-branding-log.md and narrow manifest description if stale. No input/title scene changes: separate run112 fixes real pointer input. No auth/network/native/backend/version/story/art/store/protected/history changes. Donor PNG/SVG/font/license bytes unchanged. Do not run full verify; focused state/layout/loading/locale/assets checks and one genuinely executed negative then byte restore suffice.

## Acceptance
Actual disabled KO+EN text is dark Google and white Apple at alpha1; equal visual type and baseline; centers deliberate, official assets intact, no glare. All five locales/framing/capability states have visible full consent and labels within card and44px doors, Apple clearance>=4.4. Independent negative catches deliberate low-alpha or alignment regression. No ScriptErrors. Director repeats actual pixels and input after both packets are accepted.
