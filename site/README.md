# Public site (privacy policy and support)

Static pages for the App Store listing: `privacy.html`, `support.html` and a small `index.html`.
No build step, scripts, cookies or third-party requests.

## Before publishing

Replace the placeholders in `privacy.html` and `support.html`: `[CONTACT EMAIL]`,
`[OWNER NAME OR BUSINESS NAME]`, `[DATE, filled in when published]`, and the bracketed `[OWNER: …]`
notes (check the account-deletion menu path against the released build and add any regulator wording you need).
`grep -rn '\[' site/*.html` must show none.

## Publish with GitHub Pages (owner steps; nothing here enables it)

GitHub Pages can serve a branch only from `/` or `/docs`, not from `site/`, so use a GitHub Actions deployment:

1. Repository **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. Add a workflow (for example `.github/workflows/pages.yml`) from GitHub's “Static HTML” starter and change the
   uploaded `path` from `.` to `site`. Commit it to `main`. (This repository has no workflow yet; none was added
   because that is a repository-settings decision for the owner.)
3. After the deployment finishes the pages are at `https://<owner>.github.io/<repository>/`, for example
   `https://nikobenzo.github.io/daily-challenge/privacy.html` and `…/support.html`.
4. Put those two URLs into App Store Connect (Privacy Policy URL, Support URL) and open both in a private
   window to confirm they load without signing in.

The repository must be public (or the plan must allow private Pages) for the site to be reachable.
