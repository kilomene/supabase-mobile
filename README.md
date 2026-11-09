# Supabase Mobile — v1 (Flutter, Android + iOS)

Native mobile manager for Supabase Cloud. Public app for all Supabase
developers. **Native Flutter — NOT a WebView of supabase.com.**

Visual direction (approved 2026-11-09): dark theme, Supabase green
`#3ECF8E`. Screens match the 11 previews in `../previews/`.

## What is wired live

| Area | Endpoint |
|---|---|
| Orgs / projects | Management API `https://api.supabase.com/v1` — `GET /v1/organizations`, `GET/POST /v1/projects`, pause/restore/restart/delete, health, regions |
| API keys | `GET /v1/projects/{ref}/api-keys` |
| SQL Editor | `POST /v1/projects/{ref}/database/query` (Beta) + read-only variant — also DDL, RLS, extensions, pgvector/pgmq/pg_cron (SQL-only, labelled in-app) |
| Table Editor | PostgREST `GET/POST/PATCH/DELETE /rest/v1/{table}` |
| Auth users | GoTrue Admin `GET/POST/DELETE /auth/v1/admin/users`, invite, MFA factors — secret key only |
| Storage | Storage API `/storage/v1/bucket`, `/storage/v1/object/list|sign|…` |
| Edge Functions | Management list/delete + project-host invoke `POST /functions/v1/<slug>` |
| Realtime | Live WebSocket via supabase_flutter channel (`wss://<ref>.supabase.co/realtime/v1/websocket`) |
| Logs | `GET .../analytics/endpoints/logs` (ClickHouse, ≤24h). Legacy `logs.all` removed 2026-09-23 — NOT used. Log drains (ingestion sinks): `GET .../analytics/log-drains` — list only; logs older than 24h cannot be fetched retroactively |
| Usage / egress | `usage.api-counts` (by interval) + `usage.api-requests-count` (total). Billing/invoices/spend have NO endpoint — dashboard-only, deep-linked |
| Billing addons | `GET/PATCH .../billing/addons` (compute/add-ons only) |
| Branches, backups, advisors, config (v2) | Management API as in `lib/services/management_api_client.dart` |

Full endpoint-to-feature plan: `../../research_notes/supabase-endpoints-full-map-20261109-1748/report.md`
(Management API v1: 115 paths / 170 ops, plus v2.)

## Auth — read this first

There is **no public Cloud signup/login API**. Signup/login happen in the
**system browser** at supabase.com, then the app connects via:

1. **OAuth 2.0 (primary, for a public app)** — `GET api.supabase.com/v1/oauth/authorize`
   with PKCE. The code exchange needs `client_secret` as Basic auth, which
   **must live on your backend/proxy, never in this app**. `AuthService`
   builds the authorize URL and PKCE challenge; `exchangeAuthorizationCode()`
   is intentionally NOT implemented here — deploy a tiny backend that holds
   the secret and returns only scoped access/refresh tokens.
2. **PAT-paste (fallback)** — user creates a scoped token at
   `supabase.com/dashboard/account/tokens` (`sbp_fc_…`, ≤1y) and pastes it
   in the app. Stored only in flutter_secure_storage (Keychain/Keystore).

Per-project publishable/secret keys are also user-pasted and stored only
in secure storage. **Never hard-code any secret/service_role key.**
The secret key bypasses RLS — the UI warns before saving it.

## NO_ENDPOINT (dashboard-only — deep-linked, never faked)

Create Cloud account, Cloud password/OAuth login via API, create/rotate a
PAT, create an OAuth app, billing/invoices/spend/plan, install third-party
integrations, disk-autoscale write, support/docs. See
`lib/services/dashboard_links.dart` and report §4.

## Disputed — flagged, not silently shipped

- Native backup download / physical restore: PAT table lists it, a
  third-party guide says dashboard-only. `listBackups`/`restoreBackup`
  call the PAT-table endpoints; test on a throwaway **Pro** project — if
  they 404/402, surface as dashboard-only.
- DB password update: PAT table lists it; the Platforms guide says it
  cannot be changed programmatically. Verify live before shipping.
- HTTP broadcast `POST /realtime/v1/api/broadcast`: to-verify; the
  supported live path is the WebSocket.
- TUS resumable upload path: verify at build (report §3.4).

## Build

```sh
cd supabase-mobile/app
flutter pub get
flutter analyze
flutter test
flutter build apk --release   # CI: .github/workflows/build-apk.yml
```

No local Flutter on the scaffold host — CI builds the APK (Flutter stable).
No `.env` / secrets are committed; see `.gitignore`.
