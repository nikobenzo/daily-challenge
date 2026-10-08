# Interface and Animation

## Main surface

Native SwiftUI macOS menu-bar app. Normal use has no Dock icon or persistent main window. A compact popup contains:

1. Large stylized translucent 4-litre jug.
2. Minus and plus controls and a small actual-water-total readout.
3. Four compact workout, walk, diet, and Bible-reading indicators.
4. Current streak / 75 badge; continue to show the real streak beyond 75.
5. Secondary access to custom pours, calendar/history, settings, and sync state.

Settings and correction interfaces may use separate native surfaces where appropriate. All five requirements are part of the initial functional UI, not later feature additions.

## Native glass direction

Use platform-native glass/material APIs appropriate to the deployment target confirmed on both Macs. Treat the requested Liquid Glass appearance as a design direction, not an assumed API name or guaranteed OS capability. Keep jug content and controls legible; avoid excessive glass layers. Use supported material fallbacks if needed, with user-visible differences checked on both Macs.

## Motion

Procedural animation, not a fluid simulation. Animate a short rise and settling slosh after pouring, a falling level after undo, and droplets/spills for water beyond capacity. Stop brief effects after settling. Stop rendering when hidden; no expensive perpetual idle loop.

A brief daily-completion celebration and stronger 75-day celebration have no sound by default. Do not replay on every opening. With Reduce Motion, replace sloshing and particle effects with static state changes and a subtle completion highlight.

## Accessibility

All icons and controls have accessible names, values, and states. Provide keyboard operation, visible focus, sufficiently large targets, readable contrast, and tooltips where needed. Pending/complete/missed states must not depend on color alone. Respect Reduce Motion and relevant transparency/contrast preferences. Visual minimalism must not hide the actual amount or requirement definitions from assistive technology.

## Acceptance

Check the popup on both Macs, including screen scaling, menu-bar positioning, light/dark appearance, VoiceOver, keyboard-only use, and reduced motion. Measure CPU/energy while hidden, idle, and animating. Overflow must stay within the app surface and never intercept controls.
