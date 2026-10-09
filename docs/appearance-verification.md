# Appearance fix — 8 October 2026

> **Superseded by the glass redesign (9 October 2026).** The popup is no longer an opaque
> `windowBackgroundColor` surface: it is a glass sheet (system material under an adaptive tint)
> plus a detached footer in a transparent window; see [design system](design-system.md). The tint
> alone keeps text legible over any desktop, Reduce Transparency draws it opaque, and space outside
> the glass is fully transparent. The regressions are now `productionPopupSurfacesHaveAdaptiveGlass`,
> `signedOutAuthScreensHaveAdaptiveGlass` and `PopupResizeTests`. Committed fixture renders show the
> new look; they are never-shown windows, so the material renders as its flat fallback rather than a
> blur. Since the popup fix the window is the app's own panel, not `MenuBarExtra`
> ([design system](design-system.md#popup-window)), and the [real-popup probe](#real-popup-probe)
> captures the real popup. The history below records the earlier defect and fix.

## Real-popup probe

`scripts/capture-real-popup.sh` opens the **real** popup of an isolated copy of the built app and
writes the popup window's own rendering and geometry, with no human click and no screen-recording
or accessibility permission:

```bash
scripts/build-proof.sh --adhoc --skip-notarize   # a placeholder .env.local is enough
scripts/capture-real-popup.sh                    # --docs also refreshes docs/screenshots/real-popup
```

The script copies `build/Daily Challenge.app` to `.build/real-popup-probe/` with its own bundle ID
(`app.daily-challenge.popup-probe`), without `Configuration.json` or an update feed, and launches
the copy once per screen and appearance through a developer-only launch path (`PopupProbe.swift`):

| Environment variable | Meaning |
| --- | --- |
| `DAILY_CHALLENGE_POPUP_PROBE` | Directory for fixture data and output. Required: unset, the app behaves normally; the production bundle (`app.daily-challenge.proof`) ignores it. |
| `DAILY_CHALLENGE_POPUP_PROBE_SCREEN` | `sign-in`, `setup`, `today` (default), `history` or `account` |
| `DAILY_CHALLENGE_POPUP_PROBE_APPEARANCE` | `light` (default) or `dark` |
| `DAILY_CHALLENGE_POPUP_PROBE_STEPS` | Sections to switch to after the first capture, such as `history,account,today` |

In probe mode the app runs on the committed renders' offline fixtures (8 October 2026 at noon, Day 1,
900 ml) inside that directory: no Supabase client, Keychain, Sparkle, reminders or production data
paths. It clicks its own status item (the item's own action), then writes `<screen>-<appearance>.png`
and a `.json` report: window and status-item frames, sheet and footer frames, opacity, window
shadow, key state, any system material behind the glass, pixel coverage and which capture was used
(`capture`). Each step switches section the way the header control does, records the window height
and top edge and the sheet height about every 8 ms while the height animates, and writes the
after-switch capture as `<screen>-<appearance>-<from>-to-<to>.png`. Escape then closes the popup and
the copy quits. It never touches the installed app, a real account or the Keychain.

When the terminal that runs the script may record the screen (Privacy & Security > Screen
Recording), a capture is `screencapture -l`: the WindowServer's composite of the popup window alone,
without the desktop, which draws the switcher's Liquid Glass (`"capture": "window-server"`). Each
step then also records a two-second `.mov` of only the header switcher (4 pt around its track, on
the glass) while the selection moves, and with ffmpeg installed the script stacks its changing
frames, top to bottom, into `<…>-frames.png`. Without that permission the probe falls back to the
window's own drawing (`cacheDisplay`, `"capture": "cacheDisplay"`), which cannot draw Liquid Glass
and drops everything the glass samples, so the header is blank there; it also draws the
behind-window blur as its flat fallback and Core Animation shadows upside down. Window position,
size, transparency, clipping, corners, shadows and the resize are the real ones either way. The
isolated copy is an unregistered bundle, so its Launch at login row reports "Login item not
found".

### Evidence (macOS 27.0.1, 26A434)

[`screenshots/real-popup/`](screenshots/real-popup/) holds Setup, Today, History, Account and Sign in
in Light and Dark with their reports, and Today → History → Account → Today traces in both
appearances, all from the real popup window on this Mac. In every capture the window is 540 pt wide
(the 420 pt sheet plus 60 pt of shadow margin each side), starts at the menu bar with the sheet
8 pt below it and its left edge at the status item, the footer floats 12 pt below the sheet, the
window is non-opaque and clear with no window shadow and no foreign material, and the popup is key
(Sign in shows the focused email field). In the traces the top edge never moves: Today → History
grows the transparent window first, then the glass eases 406 → 661 pt over about 0.28 s; History →
Account changes nothing; Account → Today eases the glass down and shrinks the window afterwards.
Since the switcher glass (9 October) every capture is a WindowServer composite of the real window,
and the `*-to-*-frames.png` sheets (from the `.mov` recordings) show the glass capsule sliding
cell to cell over about 0.28 s in both appearances: a slide, not a jump, with the glyph it passes
covered for a few mid-slide frames.

[`screenshots/real-popup/before/`](screenshots/real-popup/before/) is the same popup in the
`MenuBarExtra` build the captain reported (main at dadb0f6), captured by a temporary probe build
that requested the system's popup session directly (that private call was never committed), with
the measured geometry and every counterfactual tested on it (`menubarextra-geometry.json`).

Captain checks a capture cannot make: the glass blur over the real desktop; clicking outside, the
status item and Escape closing it; typing in the sign-in fields; the start-date and rules popovers;
placement with a menu bar on a second display; Reduce Transparency and Increase Contrast.

**Edge-fill follow-up:** [confirmed retained-window-height diagnosis, full-host backing, regression and captain checks](popup-edges.md). The original evidence below predates that follow-up.

## Evidence and diagnosis

The captain's [original popup screenshot](screenshots/appearance-report-2026-10-08.png) is the **before** evidence, in plain macOS Light mode, with Reduce Transparency and Increase Contrast off. It shows 900 ml and pending habits over a green/grey/purple-tinted surface. Expected: neutral, readable Light surfaces, not desktop-dependent label/control contrast.

Confirmed code defect: the production `MenuBarExtra(.window)` content had no backing fill at all. Its labels and translucent cards relied on the menu-bar window's material. In contrast, `nativeTrackerSurfacesRenderAtPopupWidth` supplied its own opaque `windowBackgroundColor`, and forced both SwiftUI and native appearance. That test therefore hid the missing production background. The screenshot is consistent with the unbacked content exposing desktop-blended material; we did not independently capture or instrument the WindowServer compositor, and do not claim a proven OS-specific vibrancy defect. The text was already semantic, so a global hard-coded dark-text fix was not warranted.

The captain authorized use of that screenshot as the real-environment failing reproduction and in-process fixture renders for this delivery. No screen-recording permission was requested, no system appearance/accessibility settings were changed, and no running app was replaced or stopped.

## Changes

- `AppAppearance.swift`: shared production `TrackerPopup` root supplies an opaque semantic `windowBackgroundColor`, independent of the desktop. Cards retain system materials over that backing; Reduce Transparency or Increased Contrast selects solid semantic cards, with an explicit border for Increased Contrast.
- The [appearance selector](../README.md#current-state-functional-tracker-with-production-sync) uses the device-local `appearancePreference` UserDefaults key; missing or invalid values fall back to System. `NSApplication.appearance` applies overrides to native windows, controls and popovers immediately; System clears the override to inherit macOS rather than caching the current mode. Accessibility display changes reapply the appropriate native appearance.
- Custom-pour content has the same backing. Jug graduation labels have neutral semantic backing even when the water rises behind them; the vessel uses semantic colour and stronger outlines.
- Challenge schema, storage, auth keys, shipped bundle ID and target are unchanged. No captain files, accounts or Keychain entries were accessed. Test auth has no SDK client and uses a temporary fixture directory.

## Automated verification

- `swift test`: **45 test definitions passed** (the existing 43 plus two appearance tests).
- `bash scripts/test-sync-security.sh`: passed using local PostgreSQL, including owner isolation, anonymous denial, append-only grants and retry behaviour.
- `bash scripts/build-proof.sh`: release compilation, bundle assembly and ad-hoc signature verification passed **with a disposable nonfunctional public-configuration fixture**. This isolated checkout lacked `.env.local`; the initial invocation correctly failed for that reason. The fixture configuration and bundle were removed after verification. A distributable authenticated build still needs the existing real public configuration; no configuration was fetched from the captain's checkout.

The new regression test renders the **same `TrackerPopup` root used by the app**, not a test-added backing, and drives the same preference model as the setting. It retains each native window while selecting Light, Dark and System, checking inherited native appearance, opaque background pixels and Light/Dark background luminance. It checks that appearance changes leave fixture challenge contents unchanged. It does not force `colorScheme` or assign appearance to the host/window. Preference tests cover default, persistence, invalid stored values, resetting System and requested high-contrast mappings.

Mutation check: removing only `TrackerPopup`'s `.trackerSurface()` caused `swift test --filter productionPopupSurfacesHaveOpaqueAdaptiveBacking` to exit 1 with `setup/today/...: root must obscure the desktop, not rely on the window material`. Restoring it passed. This catches the original code defect rather than only checking image dimensions.

### Render artifacts (not compositor screenshots)

[Fixture directory](screenshots/appearance-fixtures/) contains Light/Dark captures for setup, Today at 900 ml, overflowing jug, History locked/editing, Account, sign-in and custom-pour enabled/disabled. These are never-shown native windows, so native controls appear inactive (notably prominent buttons). They prove adaptive backing/layout, not active-popup compositing or interaction. History remains scrollable; its first viewport is captured.

These captures predate the oversized-host regression. For current renders without live data or Keychain, use the [edge-fill render command](popup-edges.md#supporting-in-process-renders-not-screen-captures); it exercises the current sizing policy rather than reproducing these historical dimensions.

macOS 27 aliases requested high-contrast NSAppearance names to ordinary Aqua/Dark Aqua while the system accessibility option is off. Consequently no high-contrast rendering claim is made from those names alone. Reduce Transparency and Increased Contrast remain real-system acceptance checks, not simulated screenshots.

## Captain's post-delivery real-popup checks

Use a correctly configured rebuilt app when ready to replace the running version; no agent has done that replacement.

1. Confirm the same account, existing challenge, water amount (900 ml unless subsequently changed), and correction history remain. Do not reset setup, delete data, sign out or log extra water to test appearance.
2. Account → Appearance → **Light**, then **Dark**, while the popup stays open. Header, navigation, Today labels, cards, jug graduations and buttons should switch immediately with no green/purple desktop tint. Close/reopen the popup; the choice should persist. Relaunch when convenient to confirm persistence.
3. In each mode inspect History, both its locked controls and **Edit this day** state, then scroll to the audit without changing records. Inspect Account, text fields and disabled diagnostics controls.
4. Open Custom pour in each mode: empty input has a visibly disabled Add; enter a positive amount to see enabled Add, then **Cancel**. Its background and labels must match the app, not remain in the previous mode.
5. Choose **System**. It should match the Mac's current Light mode. When convenient, personally change macOS appearance while the popup is open to confirm live System following, then restore the preferred setting. This system-level switch was not performed by the agent.
6. When convenient, personally check Reduce Transparency and Increase Contrast separately and together in both app modes: solid cards, distinct boundaries, legible labels and disabled controls. The agent left these settings untouched.
7. Setup/sign-in were checked with fixtures; do not reset the real challenge just to revisit setup. Check those surfaces only with an isolated fixture account.

Real-popup acceptance is explicitly pending these captain checks; passing the renders is not represented as completing it.
