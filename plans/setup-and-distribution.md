# Setup and Distribution

## Installation and backend gate

Before polished development:

1. Check both Macs' OS versions against SwiftUI/material APIs and choose a deployment target.
2. Confirm work policy permits a locally built personal app and access to Supabase over the network.
3. Verify local build/signing options with the current inactive Apple Developer membership. Paid Developer ID signing/notarization is a separate concern; Supabase does not remove installation restrictions.
4. Create a Supabase project, review current free-tier limitations, and configure authentication plus row-level security.
5. Install a minimal native sync proof on both Macs using the same app login; test private access and offline reconciliation.

Do not change system iCloud accounts, buy memberships/subscriptions without approval, disable security controls, bypass company restrictions, or silently drop two-Mac support. If blocked, discuss alternatives.

## Manual setup stages

These require user action; a setup wizard can be generated after the stages are confirmed:

1. Check work-device permission and OS version. Public/non-secret result: compatibility and installation constraints; document in a setup note, not credentials.
2. Sign into the Supabase dashboard and create a project. Choose an available nearby region and review the offered plan. Keep the database password private; the app does not need it.
3. Obtain project URL and publishable client key from the project's connection/API settings. These are public client configuration, not admin credentials; store in a local configuration file that will be defined with the proof app.
4. Provision a confirmed Supabase Auth user with an app-specific strong password, preserving an existing user ID if the earlier OTP attempt already created it. Test password login; no SMTP/template changes are required. Credentials are private and must be entered only in the app, legitimate dashboard, or a locally run, explicitly approved admin helper. Never send them in chat or persist admin keys in project configuration.
5. Apply version-controlled schema and RLS migrations supplied during implementation. No real activity uploads before access-control tests pass.

No service-role key, database password, or session token should be requested in chat. Current dashboard labels and SDK APIs must be checked against official docs before writing precise automation.

## App setup flow

- Sign into the same personal app account on each Mac using email and password. This is a Supabase Auth user, separate from the dashboard login; sessions remain in Keychain. No app self-signup or email-code flow is provided in the proof.
- Create or retrieve that account's challenge; a second device must not silently create a separate challenge.
- Select the start date; Europe/Jersey is the shared day boundary.
- Explain all five requirements and the 75-day rule.
- Diet-rule text is optional and can be added later.
- Offer launch at login without assuming consent.
- Offer water reminders on the chosen Mac; request notification permission when enabled.
- Show sync readiness, pending work, and authentication errors.
- Historical days must be entered explicitly, never assumed successful.

## Distribution proposal

A personal native macOS app, not an App Store launch. Test locally built installations before settling the distribution process. Paid signing/notarization may be needed for a seamless or policy-compliant work installation; discuss that separately if it becomes a blocker. Document reproducible build and installation steps during implementation.

## Acceptance

Fresh setup on both Macs with the same app account, existing-data relaunch, expired authentication, offline operation, denied notification permission, and launch-at-login enabled/disabled. Verify no disabled security controls are required and both Macs run data-compatible versions.

## Deferred

An iPhone client, automated updates, and wider distribution are not initial deliverables. Version the shared schema and sync protocol for future clients.
