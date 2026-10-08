# Project agent memory

- Read `HANDOFF.md` for current acceptance and roadmap boundaries; `CONTEXT.md` defines challenge terminology.
- Real records exist. Tests must inject temporary directories/accounts and avoid production Keychain; see fixture initializers and `Tests/TrackerInterfaceTests/`. Preserve the legacy identity identifiers documented in `HANDOFF.md`.
- For sync/storage work, read `docs/production-sync.md` for migration and conflict policies. Hosted migrations are owner-only; verify RLS with `scripts/test-sync-security.sh` on disposable local PostgreSQL.
- For appearance work, read `docs/appearance-verification.md`: isolated renders with a test-added backing can hide defects in the real MenuBarExtra. Use the production root regression and distinguish in-process renders from real-popup acceptance.
- `scripts/build-proof.sh` needs local public configuration. A placeholder configuration validates packaging only, not a usable authenticated app. Never replace a running user app as part of automated testing.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
