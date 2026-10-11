# Optional App Store product-page header

Static English (UK) creative asset for **Daily Challenge Tracker**, checked
11 October 2026. These files belong in the Header creative-asset placement,
separate from the portrait screenshot gallery. Nothing was uploaded.

| Export | Format | Intended use |
| --- | --- | --- |
| [header-3840x1646.png](header-3840x1646.png) | Opaque RGB PNG, 3840 × 1646 | Dedicated wide header; preferred starting point for owner Preview |
| [header-5244x2950.png](header-5244x2950.png) | Opaque RGB PNG, 5244 × 2950 | Alternative accepted universal-size header |

The universal-size file is supplied only for the requested header. Selecting it
for search results is outside this task. Apple requires PNG for this larger size.
See [Apple requirements and template measurements](../../../../app-store-visuals-research.md#optional-product-page-header-11-october-2026)
for source links, format details, file-limit research and safe-area coordinates.

## Rebuild with the existing renderer

Use the same macOS/system SF, Chrome axi and Pillow 12.3.0 environment as the
landed screenshots. From the repository root:

```sh
.build/app-store-venv/bin/python scripts/render-app-store-marketing.py --header
```

If needed, create that virtual environment and install Pillow using the parent
[README](../README.md#rebuild). `--header` renders both header sizes and their
review images only. The existing screenshot command and filters retain their
behaviour. It cannot be combined with screenshot `--size` or `--frame` filters.

`header.json` owns copy, source paths, crop coordinates, export dimensions and
Apple-template safe areas. `template.html` owns the composition. The existing
renderer substitutes paths, waits for fonts/images, checks all primary elements
and headline glyph ranges inside the safe rectangle, captures through the
dedicated Chrome axi session, verifies dimensions and flattens each PNG to RGB.
Generated HTML stays in ignored `.build/app-store-marketing/header/`.
`render-manifest.json` records source and output hashes, byte sizes and bounds.

## Design and capture provenance

“Make every day count.” is the central daily benefit, supported by a real Today
panel. Palette, system SF type, drop icon and restrained glass styling follow
the landed marketing gallery. The public name is Daily Challenge Tracker;
the challenge tag is generic. Public copy contains no em or en dashes.
There are no pricing, rankings, testimonials, awards or transformation claims.

The Today panel uniformly scales `[48, 492, 1224, 1030]` (x, y, width, height)
from `raw/01-today-light.png`. All five rings, the jug, actual water amount,
undo, + 450 ml and more control are retained. Its cropped detail is explicitly
presented as “Your day, at a glance.”, rather than a reconstructed phone screen.
The tilted peripheral phone contains the entire real SpringBoard capture
`raw/04-widgets-home-light.png`. The surround and Island are decorative.
No screenshot pixels or labels were repainted.

Both captures were already committed: iPhone 17 Pro Max / iOS 26.4 simulator,
1320 × 2868, synthetic fixture data, 9:41 status bar. Today is Day 12; the
widgets are Day 1. They are separate product examples, not a claim of one
synchronised session. Full capture provenance is in the parent README.
No app, account, production data, Keychain or notification setting was touched.

## Crop previews and visual review

Only the two unsuffixed PNGs above are deliverables for the Header box. For each
size, the renderer also produces three **review-only** images:

- `*-safe-area-preview.png`: full composition reduced to fit 1311 × 738,
  with an orange outline of the Apple-template safe rectangle.
- `*-safe-area-crop.png`: the exact safe rectangle at native pixel size.
- `*-iphone-crop-preview.png`: that rectangle reduced to 402 px wide, a
  conservative portrait iPhone header readability check.

These crops deliberately show the smallest template-safe composition, including
the disappearance of the peripheral large icon and Home Screen phone. They are
not an exact App Store rendering or an assertion that every device uses those
crop boundaries. Apple's published guidance supplies no per-device crop matrix.
The owner must still use App Store Connect's Preview for the actual iPhone
product-page appearance before submission.

Visual review on 11 October 2026 covered both complete exports, native-resolution
safe crops, full-resolution peripheral artwork and both 402 px crop previews.
The headline and water amount remain readable at phone width; small requirement
labels are supporting UI detail. Nothing central is cut, and no key message
depends on the outer phone or large drop. The extra negative space in the
universal format protects the higher, smaller safe area rather than filling it
with fragile text. The dedicated wide version gives the central content more
space in a shallow crop.

Verification: exact pixel sizes, RGB/no alpha, source hashes, safe bounds,
headline glyph bounds, punctuation, deterministic rerender, Python syntax and
`git diff --check`. This is an asset-only change; app builds/tests and native
App Store Connect previews were not part of this verification.
