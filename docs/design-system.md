# Daily Challenge design system

The app's visual language, implemented 9 October 2026 from the captain-approved Paper
file **"Daily Challenge · Design System"**
(<https://app.paper.design/file/01M4F3ESNYB6KERQPN1A0XZKYS/p-1-0>; its design tokens are saved
in that file too). The code is the source of truth for values:

| What | Where |
| --- | --- |
| Tokens: dark/light palette, type scale, spacing, radii, sizes, motion | `Sources/DailyChallengeProof/Theme.swift` |
| Shared components | `Sources/DailyChallengeProof/Components.swift` |
| The status item, the popup panel and the animated height | `Sources/DailyChallengeProof/PopupWindow.swift` |
| Screens | `TrackerView.swift` (root, header, footer, setup), `TodayView.swift`, `HistoryTrackerView.swift`, `AccountView.swift`, `AuthView.swift` |

## Principles

- **One glass sheet.** A 420 pt sheet with 28 pt corners: an `NSVisualEffectView` (`.hudWindow` in
  Dark, `.popover` in Light) under a tint (`Theme.glass`), 1 pt border and inner top highlight.
  Sections are separated by hairlines, never boxed cards. A detached 420 × 56 footer capsule sits
  12 pt below it: sync state on the left, power + Quit on the right. Both cast the boards' soft
  shadows (`0 24 60` `sheetShadow`, `0 18 40` `footerShadow`) through `OuterShadow`.
- **Icons first.** When a glyph is unambiguous it stands alone with a tooltip (`.help`) and an
  accessibility label. Words remain only where an action is destructive or irreversible
  ("Sign out on this Mac", "Start challenge") or where a value is shown. Long helper sentences
  live in tooltips or a help popover, never inline.
- **Every state has a shape.** Rings and pills show a dash, percentage, check or ×; calendar days
  are a filled disc, a ring, a ring with a halo, an ink disc or a faint numeral. Colour is never
  the only signal.
- **Appearance.** Every colour is one dynamic token that resolves against the drawing appearance,
  so the device-local System / Light / Dark setting, popovers and renders all follow it.
  Reduce Transparency draws the tint opaque; Increase Contrast strengthens borders.
- **Motion.** Section changes cross-fade (0.2 s) while the glass height animates (ease-in-out
  0.28 s) and the switcher's glass capsule slides to the new cell (ease-in-out 0.28 s); rings ease 0.35 s and pop 1.06 when done; the completion band slides in 0.4 s. Reduce
  Motion uses opacity only and a short linear resize. The jug keeps its bounded, finite motion
  engine (`TrackerMotion.swift`), whose energy behaviour is measured in `motion-verification.md`.

## Components

Buttons (`PrimaryPillStyle`, `TintedPillStyle`, `RoundIconStyle`, `LinkStyle`) draw the focus
ring + halo themselves (`focusHalo`); the popup root disables the system focus effect, which on
custom shapes renders as a stray rectangle. Toggles use `GlassToggleStyle` (52 × 30, knob 26).
`IconSegmented` is the section switcher (36 pt track, 44 × 30 cells) and the Appearance control
(34 pt track, 40 × 28 cells). On macOS 26 and later its selected cell is one Liquid Glass capsule
(`.regular` glass in a `GlassEffectContainer`, tinted with `segmentGlassTint`) over the translucent
`controlFill` track, and it slides to the new cell; Reduce Transparency draws the opaque
`segmentSelected` pill, Reduce Motion cross-fades, and earlier systems slide the opaque pill.
In-process renders draw it as a flat translucent capsule (`trackerLiquidGlassOverride`), since
cacheDisplay cannot draw Liquid Glass and drops everything the glass samples. `PillStepper`, `Badge`, `AppMark`, `HeroIcon`, `SettingRow`,
`Eyebrow`, `GlassField` (46 pt, focus / error / valid / password reveal), `FieldError`,
`RingGauge` (64 pt, stroke 6), `RuleChips` and `CodeBoxes` complete the set.

Use `Capsule(style: .circular)` and circular corners whenever the radius is half the height: on
macOS 27, continuous corners at that radius draw flattened ends and stray stroke segments.

## Window height

History and Account share one content height (`Theme.Size.wideSectionHeight`, 600 pt): History's
Activity list fills the remainder and scrolls inside, and Account scrolls if a form or the
Advanced diagnostics make it longer. Today is shorter; setup and the auth steps size to their
content. `AnimatedPopupStack` animates the visible glass to each new height; the transparent
window grows before an animation and shrinks only after it, its top edge fixed under the menu bar.

## Popup window

The popup is the app's own status item (`drop.circle`, filled and highlighted while open)
toggling `PopupPanel`, a borderless, non-activating, transparent `NSPanel` hosting `TrackerPopup`
(`PopupController` in `PopupWindow.swift`). The window starts at the menu bar; the sheet sits
8 pt below it (Menu bar presence board) with its left edge under the item, kept 8 pt inside the
screen, and with a menu bar on several displays it opens under the copy that was clicked. It
closes on Escape, the status item, a click outside the glass or in another app, another app
activating, or a Space change; clicks in its own popovers keep it open. The window has no shadow
of its own: 60 pt of transparent margin at the sides and bottom hold the sheet's and footer's
shadows, which are pre-rendered images (`OuterShadow`) so they move with the animating glass and
look the same on screen, in renders and in popup captures (cacheDisplay draws Core Animation
shadow offsets upside down).

**Decision (9 October 2026), not SwiftUI's `MenuBarExtra(.window)`.** Measured on the real popup
on macOS 27.0.1 with the developer probe ([evidence](appearance-verification.md#real-popup-probe)),
macOS 27 presents `MenuBarExtra(.window)` through a system scene session (`NSSceneStatusItem`
with an expanded-interface delegate), which:

1. sizes the window from the root's *minimum* size, clamped to 298 × 10 pt, so a root without a
   minimum width (`.frame(minWidth: 0, …)`) got a 298 pt window that cut the 420 pt sheet on both
   sides; with the minimum restored it still jumps to each new height in one frame and never
   shrinks, centring shorter content in the retained height (the band above the sheet);
2. fills the window with its own Liquid Glass backdrop (`CABackdropLayer` and `CAChameleonLayer`
   inside the hosting view, not an `NSVisualEffectView`), which `.containerBackground(.clear,
   for: .window)` does not remove and which shows in the 12 pt gap and outside the 28 pt corners;
3. opens only on a click relayed by the system, so nothing in-process could open it to verify it.

Owning the window removes all three. `TrackerPopup` still reports the sheet's 420 pt minimum
width (`popupRootReportsTheSheetWidth`), so no host can squeeze it again.

## Decisions where the boards were ambiguous

- Selected segmented cell, Day badge, Today pill, best-streak badge, jug outline and the numerals on
  a green day disc use board-derived pairings (`dayBadgeFill`, `bestBadgeFill`, `segmentSelected`,
  `jugOutline`, `onDone`, `accentTint`) rather than tokens from the report's table.
- **Switcher glass (9 October 2026), measured on screen on macOS 27.0.1** with the real-popup
  probe's switch videos: handing a `glassEffectID` from cell to cell made the glass jump instead
  of moving, so the capsule is one view offset to the selected cell; `.interactive()` lifted the
  glass over the icons while moving (and the buttons above take the clicks), so it is off; glass
  inside the cells' own container covered the selected icon, so the glass row sits under the
  icons. While it moves the glass still covers the glyph it passes for a few frames (about 4 of
  16 at 60 Hz); at rest every icon is above it.
- Setup keeps the section switcher so Account (and Sign out) stays reachable before a challenge
  exists; the Setup board omits it.
- The calendar's "past open" disc maps to a selectable day that is neither complete nor missed;
  days before the start date use the future style.
- Today shows overflow with droplets under the jug, as on the Today complete board; the amber
  "+N" chip from the Components board is not shown.
- The jug keeps the existing finite fill/slosh motion instead of the spring in the Components
  note, so the measured idle-energy behaviour is unchanged.
- The update row shows "Up to date" only implicitly (a check-for-updates icon): the app does not
  know it is current until a check runs. An available update shows the amber version chip and
  Install; development builds show "Updates off".
- Account's day line keeps the existing wording ("Day 12 of 75 · started Sun 27 Sep") rather than
  the board's "Day 12 / 75 · since 27 Sep".
- The code screens show one navigation link each, as drawn: "Different email" on the sign-up code
  screen (its next screen has "Back to sign in") and "Back to sign in" on the reset screen (from
  which "Forgot password?" takes a different email). Each former link is one click further away.
