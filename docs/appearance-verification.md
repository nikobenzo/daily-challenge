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
from the popup window's `contentView` (`bitmapImageRepForCachingDisplay` and `cacheDisplay`) and a
`.json` report: window and status-item frames, sheet and footer frames, opacity, window shadow, key
state, any system material behind the glass, and pixel coverage. Each step switches section the way
the header control does and records the window height and top edge and the sheet height about
every 8 ms while the height animates. Escape then closes the popup and the copy quits. It never
touches the installed app, a real account or the Keychain.

A capture is the popup window's own drawing, not the WindowServer composite: the behind-window blur
renders as its flat fallback, and cacheDisplay draws Core Animation shadows upside down, which
affects only small control glows (the sheet and footer shadows are images). Window position, size,
transparency, clipping, corners, shadows and the resize are the real ones. The isolated copy is an
unregistered bundle, so its Launch at login row reports "Login item not found".

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
