# Security policy

Please report vulnerabilities privately through GitHub's "Report a vulnerability"
(Security tab → Advisories), not in public issues. Include steps to reproduce.
Expect an acknowledgement within a week. This is a hobby project without a bounty.

In scope: the macOS app in this repository, its Supabase schema and row-level
security (`supabase/`), and the release and Sparkle update pipeline
(`scripts/build-proof.sh`, `scripts/release.sh`).
The Supabase project URL and publishable key inside the app are public by design;
reports that only show those values are not vulnerabilities.
Please do not run load tests, create bulk accounts, or send email through the
sign-up flow against the hosted project.
