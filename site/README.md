# Public site (privacy policy and support)

Static pages for the App Store and Google Play listings: `privacy.html`, `support.html`, `delete-account.html` (the account deletion link Google Play requires) and a small `index.html`.
No build step, scripts, cookies or third-party requests.

## Published

The pages are published with GitHub Pages by `.github/workflows/pages.yml` on every push to `main` that changes `site/`:

- https://nikobenzo.github.io/daily-challenge/privacy.html
- https://nikobenzo.github.io/daily-challenge/support.html
- https://nikobenzo.github.io/daily-challenge/delete-account.html (live once this page reaches `main` and the workflow runs)

Contact address: yakovetskyi@icloud.com. Keep the pages free of placeholders (`grep -rn '\[' site/*.html` shows none) and update the privacy policy's "Last updated" date with any change.
