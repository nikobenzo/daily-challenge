# Repository presentation notes

How the public face of this repository was put together, and why. Written 11 October 2026 after reading the READMEs of several well-regarded open-source Mac and iOS apps. No wording or assets were copied from them.

## What was reviewed

| Project | What it does well |
| --- | --- |
| [Ice](https://github.com/jordanbaird/Ice) | Centered icon and name, then a wide banner and a compact row of flat badges (download, platform, minimum macOS). Install comes before the feature list. |
| [Loop](https://github.com/MrKai77/Loop) | A one-line tagline and a direct download link inside the centered hero, so a visitor can act without scrolling. Features are shown, not described. |
| [MonitorControl](https://github.com/MonitorControl/MonitorControl) | A short pitch beside the icon, one large real screenshot, then a "major features" list written as user benefits. |
| [Stats](https://github.com/exelban/stats) | Screenshots first, a one-line description, then several install routes (manual, package manager, script) and an uninstall note. FAQ for recurring support questions. |
| [Maccy](https://github.com/p0deje/Maccy) | Very short feature bullets, the minimum macOS stated in one sentence, and a clear official-website warning. |
| [Rectangle](https://github.com/rxhanson/Rectangle) | System requirements stated before installation. Long reference material lives lower down so the top stays short. |
| [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire) | Honest expectations about contributions and support, and building instructions kept separate from the product pitch. |
| [CodeEdit](https://github.com/CodeEditApp/CodeEdit) | A banner image that sells the product at a glance, with badges directly underneath and a notice block for the project's status. |

## Common patterns

1. **Hero first.** Icon or banner, product name, a single sentence pitch, then badges. The visitor knows what it is within one screen.
2. **Real screenshots early.** The strongest pages let the product speak before any prose.
3. **Install is short and copyable.** One command or one download link, with a manual alternative and the minimum OS nearby.
4. **Benefits, not internals.** Feature lists talk about what the user gets. Architecture and build steps go lower down or into a separate document.
5. **Few, meaningful badges.** Release, platform and minimum OS help. Long badge walls add noise.
6. **Honest scope.** Personal projects that say so up front set better expectations than a generic contribution guide.

## What this repository adopted

- A full-width hero built from the existing App Store header art (`docs/assets/hero.jpg`, resized from `docs/screenshots/app-store/marketing/header/header-3840x1646.png`), followed by the name, a one-line pitch, five flat badges in the app's accent blue and quick section links.
- A two-column feature grid written as benefits, with the five daily goals called out in the opening paragraph.
- Real iPhone marketing frames in a four-up row that scales on narrow screens, with the rest tucked into a collapsible section. Real Mac menu-bar captures use `<picture>` so they follow the viewer's GitHub light or dark theme.
- Install near the top: the signed and notarized cURL installer as the main route, a collapsible manual zip route, and the minimum macOS and Apple silicon requirement in one line. The iPhone app is marked as coming soon with no store link.
- A plain privacy summary that links to the full policy, a support section with the contact email, and the build details pushed to the bottom, with the full developer and status notes in [DEVELOPMENT.md](DEVELOPMENT.md).
- A short, honest [CONTRIBUTING.md](../CONTRIBUTING.md) and a bug report form that asks for the details the support page already requests.

## Images

Derived images live in `docs/assets/`. Each was resized with Pillow from a committed source, with no pixels repainted:

| File | Source | Notes |
| --- | --- | --- |
| `hero.jpg` | header 3840 × 1646 | 1600 px wide JPEG |
| `iphone/*.jpg` | `marketing/iphone-6.9/*.png` | 600 px wide JPEG |
| `mac/*.png` | `screenshots/real-popup/*.png` | 720 px wide PNG, transparency kept |
| `social-preview.png` | header 3840 × 1646 | 1280 × 640 PNG for GitHub's social preview; sides trimmed, top and bottom padded with the background edge |

GitHub only accepts the social preview through the repository's web settings (Settings, General, Social preview), so `social-preview.png` must be uploaded there by hand.
