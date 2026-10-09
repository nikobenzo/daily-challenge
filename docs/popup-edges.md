# Popup edge fill — 8 October 2026 follow-up

> **Superseded by the glass redesign (9 October 2026).** The window is now transparent outside the
> glass sheet and footer, so retained window space is invisible rather than a band, and
> `PopupWindowAdapter` fits the MenuBarExtra panel to the content with its top edge anchored; see
> [design system](design-system.md#window-height). The diagnosis below still explains why both
> matter. The `account-dark-oversized-host` and `setup-light-oversized-host` renders are refreshed
> with the new look; `account-before`/`account-after` remain the original evidence.

## Confirmed cause

The captain's post-appearance-fix screenshot shows **Account**, with exposed bands above the header and below the footer. The earlier backing already ignored safe areas. Adding that modifier again would not help.

An isolated offline fixture of the production `MenuBarExtra` confirmed a **retained window height plus content-sized, vertically centred backing**, not a title-bar inset:

| Sequence, Light appearance | Native window / host | Content and backing | Top/bottom backing alpha |
| --- | --- | --- | --- |
| Today | 420 × 629 pt | 420 × 629, y=0 | 1 / 1 |
| Today → Account | 420 × 629 pt | 420 × 623, y=3 | 0 / 0 |
| History | 420 × 653 pt | 420 × 653, y=0 | 1 / 1 |
| History → Account | 420 × 653 pt | 420 × 623, y=15 | 0 / 0 |

All measured safe-area insets were zero. The native window background was clear. Thus the 15 pt bands exposed whatever was behind the window. The earlier test always resized its borderless host to the content's fitting size, hiding this exact defect. `.fixedSize(vertical: true)` alone did not correct the real MenuBarExtra's retained size.

## Fix and sizing policy

`TrackerPopup` top-aligns its section content and applies the opaque semantic backing **after a full-width/full-height frame**. It imposes no fixed height or outer scroll container. Content supplies its natural sizing; native MenuBarExtra may retain a taller window after a section change, and the backing fills all of that area, including space below shorter content.

The existing History/Account scroll areas remain unchanged. No native resize adapter, private window API, negative padding, or replacement corner mask is used. The native window still owns rounded-corner clipping. The appearance palette, cards, controls, auth/storage and legacy identifiers are unchanged.

## Regression coverage

- `productionPopupSurfacesHaveOpaqueAdaptiveBacking` checks every top/bottom edge pixel and both full-height side edges, all sections/setup/sign-in, Light/Dark/System, and a deliberately oversized host. It does not require a fixed ideal height.
- Retained-window regression: History → Account → Today → Account in the same 653 pt host, including a verified scrolled History viewport. The test does not fit the window to each section. Native host sizing options exclude automatic maximum-size clamping, which would otherwise hide the failure again.

### Prior fixed-height implementation evidence

The following results and committed renders predate removal of the 653 pt fixed viewport and outer scroll container. They establish the original diagnosis and earlier implementation behavior, not verification of the final sizing policy:

- `swift test`: all **45 test definitions passed**.
- Mutation: removing only the full-window expanding frame produced transparent-edge failures; restoring it passed.
- Reopened the distinct offline fixture directly on Account and ran its in-process Today → Account → History → Account cycler. Every window/backing in that earlier fixture measured **420 × 653 pt, backing y=0**; top/bottom sampled pixels had alpha **1**. Account content remained 623 pt, now top-aligned inside the filled viewport. The initial popup was visible; later retained-host captures were taken after dismissal. These establish layout/backing coverage, **not WindowServer compositing acceptance**.

### Supporting in-process renders, not screen captures

- [Account before, after History](screenshots/popup-edges/account-before.png): transparent 15 pt edge bands.
- [Account after, after History](screenshots/popup-edges/account-after.png): filled edges and top-aligned content.
- [Dark Account in an oversized test host](screenshots/popup-edges/account-dark-oversized-host.png).
- [Light setup in an oversized test host](screenshots/popup-edges/setup-light-oversized-host.png).

The fixture used a distinct test bundle ID, offline auth initializer and disposable challenge directory. Only its own status item received synthetic clicks. All fixture-only compile/env hooks and the experimental native resize adapter were removed from shipped sources. The fixture was stopped; the captain's running app, real data, Keychain and OS settings were not touched. No screen-recording permission was requested or used.

To regenerate test renders in an isolated checkout:

```bash
DAILY_CHALLENGE_SNAPSHOT_DIR="$PWD/.build/popup-edge-renders" \
  swift test --filter AppearanceTests
```

Reduce Transparency and Increase Contrast were **not changed**. Their SwiftUI environment values are read-only, and requested high-contrast NSAppearance names can alias ordinary Aqua while the OS setting is off. These remain captain acceptance checks; no simulated accessibility-mode render is claimed.

## Captain's rebuilt-popup checklist (include in the PR)

Use a correctly configured rebuilt app when personally ready to replace the running version; no agent replaced it.

1. In **Light**, switch Today → Account → History → Account. Inspect the very top, very bottom, side edges and rounded corners against a contrasting window behind it. No underlying tabs/desktop should show through and no differently coloured footer strip should remain. Content should remain top-aligned; the native popup may retain its height, but all retained space must be filled.
2. Repeat in **Dark** and **System**. Change the app appearance while open, then close/reopen on Account and History. The whole background, including the space below short content, must change together.
3. Scroll History to the audit and back, and Account through its contents. Neither scrolling nor section changes should expose an unfilled band. Existing controls and footer remain reachable.
4. When convenient, check **Reduce Transparency** and **Increase Contrast**, separately and together, in Light/Dark/System. No transparent edge bands; solid cards, readable labels and clear control boundaries. These system settings were left untouched by the agent.
5. Check setup/sign-in only with an isolated fixture account; **do not reset the real challenge or sign out just to test**. Verify the existing account, water and audit remain unchanged.

Real-popup corner/compositor and accessibility acceptance remains pending these checks. There is no cloud CI configured for this project.
