# Daily Challenge design system

The app's visual language, implemented 9 October 2026 from the captain-approved Paper
file **"Daily Challenge · Design System"**
(<https://app.paper.design/file/01M4F3ESNYB6KERQPN1A0XZKYS/p-1-0>; its design tokens are saved
in that file too). The code is the source of truth for values:

| What | Where |
| --- | --- |
| Tokens: dark/light palette, type scale, spacing, radii, sizes, motion | `Sources/DailyChallengeProof/Theme.swift` |
| Shared components | `Sources/DailyChallengeProof/Components.swift` |
| Window transparency and the animated height | `Sources/DailyChallengeProof/PopupWindow.swift` |
| Screens | `TrackerView.swift` (root, header, footer, setup), `TodayView.swift`, `HistoryTrackerView.swift`, `AccountView.swift`, `AuthView.swift` |

## Principles

- **One glass sheet.** A 420 pt sheet with 28 pt corners: an `NSVisualEffectView` (`.hudWindow` in
  Dark, `.popover` in Light) under a tint (`Theme.glass`), 1 pt border and inner top highlight.
  Sections are separated by hairlines, never boxed cards. A detached 420 × 56 footer capsule sits
  12 pt below it: sync state on the left, power + Quit on the right.
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
  0.28 s); rings ease 0.35 s and pop 1.06 when done; the completion band slides in 0.4 s. Reduce
  Motion uses opacity only and a short linear resize. The jug keeps its bounded, finite motion
  engine (`TrackerMotion.swift`), whose energy behaviour is measured in `motion-verification.md`.

## Components

Buttons (`PrimaryPillStyle`, `TintedPillStyle`, `RoundIconStyle`, `LinkStyle`) draw the focus
ring + halo themselves (`focusHalo`); the popup root disables the system focus effect, which on
custom shapes renders as a stray rectangle. Toggles use `GlassToggleStyle` (52 × 30, knob 26).
`IconSegmented` is the section switcher (36 pt track, 44 × 30 cells) and the Appearance control
(34 pt track, 40 × 28 cells). `PillStepper`, `Badge`, `AppMark`, `HeroIcon`, `SettingRow`,
`Eyebrow`, `GlassField` (46 pt, focus / error / valid / password reveal), `FieldError`,
`RingGauge` (64 pt, stroke 6), `RuleChips` and `CodeBoxes` complete the set.

Use `Capsule(style: .circular)` and circular corners whenever the radius is half the height: on
macOS 27, continuous corners at that radius draw flattened ends and stray stroke segments.

## Window height

History and Account share one content height (`Theme.Size.wideSectionHeight`, 600 pt): History's
Activity list fills the remainder and scrolls inside, and Account scrolls if a form or the
Advanced diagnostics make it longer. Today is shorter; setup and the auth steps size to their
content. `AnimatedPopupStack` animates the visible glass to each new height; the window grows
before an animation and shrinks only after it, and `PopupWindowAdapter` keeps the MenuBarExtra
panel transparent outside the glass, top-anchored under the menu bar.

## Decisions where the boards were ambiguous

- Selected segmented cell, Day badge, Today pill, best-streak badge, jug outline and the numerals on
  a green day disc use board-derived pairings (`dayBadgeFill`, `bestBadgeFill`, `segmentSelected`,
  `jugOutline`, `onDone`, `accentTint`) rather than tokens from the report's table.
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
