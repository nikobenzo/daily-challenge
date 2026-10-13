# App Store marketing screenshots

Seven English (UK) frames, in upload order. Use the numbered PNGs inside
`iphone-6.9/` (1320 × 2868) and `iphone-medium/` (1206 × 2622).
Contact sheets are for review only; do not upload them as screenshots.

The optional product-page header is a separate creative asset. Its two exports,
safe-area previews and rebuild instructions are in [header/README.md](header/README.md).

| Frame | Benefit | Product evidence |
| --- | --- | --- |
| 01 | One day. Five clear goals. | Today with personalised goals (Gym, Yoga, No sugar, Audiobook), jug and streak |
| 02 | Check in. Keep moving. | Actual Home Screen widgets, with water and checklist controls (standard five) |
| 03 | Every pour adds up. | Today water jug toward a 3,000 ml goal and the + 330 ml glass button, with enlarged crop |
| 04 | Small extras. Less to forget. | Extras repeating every day, on weekdays and on Fridays beside a Late to-do, with enlarged crop |
| 05 | See your streak grow. | History calendar, today's card with the personalised goals, and the goal changes in Activity |
| 06 | Your routine. Your look. | Today in Dark appearance, with repeating extras |
| 07 | Five goals. One good day. | All five requirements complete (standard five) |

The generic 75-day wording refers to this app's five daily goals: the standard
five by default, or the user's own names and amounts from 1.1. Extras are
personal to-dos and do not count towards complete days or streaks. Captions
make no user-count, testimonial, ranking, medical-result or award claim. The
optional cross-device/sign-in frame is omitted: the seven frames focus on the
phone's daily experience. The app is iPhone-only according to `iOS/project.yml`.

## Rebuild

On macOS with Chrome and `chrome-devtools-axi` available:

```sh
python3 -m venv .build/app-store-venv
.build/app-store-venv/bin/pip install Pillow==12.3.0
.build/app-store-venv/bin/python scripts/render-app-store-marketing.py
```

Optional: `--size iphone-6.9`, `--size iphone-medium`, or `--frame 04-extras`.
A frame may set `zoom_top` (fraction of the capture's height) and `zoom_height`
(pixels) when its enlarged detail sits elsewhere in the capture; 04 uses them
for the four-row repeating list.
A single-frame run updates that PNG only; run the full command before delivery to
refresh both contact sheets and the complete provenance manifest.

`frames.json` owns the captions, order, image paths and layout/theme choices.
`template.html` owns typography, backgrounds, margins, phone surround and crops.
The script substitutes the template and renders via a dedicated
`dc-appstore-marketing` Chrome axi session. Generated HTML containing local file
URLs stays in ignored `.build/app-store-marketing/`; the committed template has
no checkout-specific paths. It converts every output to opaque RGB and verifies
the exact export dimensions. The render manifest records input sizes, hashes
and DOM bounds; it contains no real account or credential data.

System SF typography follows the application's design system. Colour values
come from `Sources/DailyChallengeProof/Shared/Theme.swift`; the drop mark is the
repository's `Resources/AppIcon/icon_1024.png`. The phone surround and Island
are decorative framing. UI pixels are real captures, uniformly scaled. The
water and extras detail panels enlarge the same source image without replacing
labels, controls or logged values. Labels identify those enlarged details.
Frames 01-06 use the same UI with uniform scaling at the medium size. Frame 07
uses its native medium capture. The canvas has a tiny background-height
extension for the medium display's slightly different aspect ratio.

## Capture provenance and visual review

1.1 refresh (13 October 2026, branch `fm/dc-iphone-110` on `1183ebe`): frames
01, 03, 04, 05 and 06 now use the 1.1 fixtures `todayGoals` (`01-today-goals-*`),
`historyGoals` (`02-history-goals-*`) and `todayRecurring` (`07-today-recurring-*`),
and frame 07 uses a fresh `todayComplete` capture. All were captured with
`iOS/scripts/capture-app-store-screenshots.sh` on dedicated iPhone 17 Pro Max and
iPhone 17 simulators on iOS 26.4 (synthetic fixture data, fixed 9:41 status bar,
full signal and battery; no account, Keychain, network or notification
permission). Frame 02 still uses the SpringBoard widget capture
`04-widgets-home-light.png` from `24fb3e5`, which shows the standard five; no
widget fixture with personalised goals exists. The header's Today crop now uses
`01-today-goals-light.png`. Frame 07 reads the native medium capture through
`source_by_size` in `frames.json`; frames 01 to 06 are uniformly scaled at the
medium size.

Each frame is an independent feature example. The app examples use Day 12,
while the widget example uses Day 1; the personalised and standard examples are
separate fixtures. The gallery makes no claim that these examples are one
continuous session or a synchronised account. The offline fixture's Local only
label remains visible and is not relabelled as Synced. See
[research](../../../app-store-visuals-research.md) for references and the
design rationale.

Checks on 13 October 2026:

- All fourteen frames were reviewed in both contact sheets, and frames 01, 03
  and 04 individually at full size; the extras close-up shows the heading and
  all four rows with their repeat captions and the Late label.
- The renderer's DOM checks passed for caption overflow and canvas bounds;
  export checks passed for the exact dimensions, opaque RGB and seven frames per
  size; `render-manifest.json` records every input hash. Both header exports
  re-rendered with their safe-area previews.
- Captions contain no em or en dashes. No application code changed.

Re-render and repeat the visual review whenever captions, inputs or layout change.
