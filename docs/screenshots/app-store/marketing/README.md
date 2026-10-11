# App Store marketing screenshots

Six English (UK) frames, in upload order. Use the numbered PNGs inside
`iphone-6.9/` (1320 × 2868) and `iphone-medium/` (1206 × 2622).
Contact sheets are for review only; do not upload them as screenshots.

| Frame | Benefit | Product evidence |
| --- | --- | --- |
| 01 | One day. Five clear goals. | Today: five rings, jug and current streak |
| 02 | Check in. Keep moving. | Actual Home Screen widgets, with water and checklist controls |
| 03 | Every pour adds up. | Today water jug and + 450 ml button, with enlarged crop |
| 04 | Small extras. Less to forget. | Today's extras with the amber Late labels, with enlarged crop |
| 05 | See your streak grow. | History calendar and streak information |
| 06 | Your routine. Your look. | Today in Dark appearance |

The generic 75-day wording refers to this app's five fixed requirements. Extras
are personal to-dos and do not count towards complete days or streaks. Captions
make no user-count, testimonial, ranking, medical-result or award claim. The
optional cross-device/sign-in frame is omitted: the six frames focus on the
phone's daily experience. The app is iPhone-only according to `iOS/project.yml`.

## Rebuild

On macOS with Chrome and `chrome-devtools-axi` available:

```sh
python3 -m venv .build/app-store-venv
.build/app-store-venv/bin/pip install Pillow==12.3.0
.build/app-store-venv/bin/python scripts/render-app-store-marketing.py
```

Optional: `--size iphone-6.9`, `--size iphone-medium`, or `--frame 04-extras`.
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
The medium-size composition uses the same UI with uniform scaling and a tiny
background-height extension for its slightly different aspect ratio.

## Capture provenance and visual review

All inputs now come from `docs/screenshots/app-store/raw/` on `main` at
`24fb3e5`: real iPhone 17 Pro Max simulator captures on iOS 26.4, synthetic
fixture data, fixed 9:41 status bar and full signal/battery. The raw capture
commands and caveats are in `docs/app-store-listing.md` and
`iOS/scripts/capture-app-store-screenshots.sh`. No account, Keychain, network
or notification permission was used for these captures. The placed widget
capture comes from SpringBoard, not an in-process widget render.

Each frame is an independent feature example. The app examples use Day 12,
while the widget example uses Day 1; their dates differ because the app fixture
clock is fixed and WidgetKit uses the simulator's date. The gallery makes no
claim that these examples are one continuous session or a synchronised account.
The offline fixture's Local only label remains visible and is not relabelled as
Synced. See [research](../../../app-store-visuals-research.md) for references
and the design rationale.

Final checks passed on 11 October 2026:

- All twelve PNGs were inspected individually and in both contact sheets at
  thumbnail size. Headlines, rings, jug, controls and Late labels are legible;
  the water and extras crops preserve their complete focal content. The native
  History activity list continues behind its tab bar, as in the raw capture.
- DOM checks passed for caption overflow and canvas bounds. Export checks passed
  for the exact dimensions, opaque RGB pixels, six frames per size and all input
  hashes recorded in `render-manifest.json`.
- Caption wording and punctuation checks passed. The renderer's Python syntax
  and `git diff --check` passed. No application code changes are part of this
  delivery.

The final set has six frames. It covers all required features with the raw
captures now available on main. Re-render and repeat the visual review whenever
captions, inputs or layout change.
