# Claim Settlement App — Flutter client

Single Dart codebase for web, Android, iOS, Windows, macOS. See
`docs/ARCHITECTURE.md` §1 for the platform decision and
`docs/BUSINESS_RULES.md` for the claim lifecycle this UI drives through.

## Structure

```
lib/
  core/       api_config.dart, auth_session.dart, api_client.dart — HTTP + auth plumbing
  models/     plain Dart classes mirroring api/app/schemas/*.py 1:1
  services/   one class per router in api/app/api/routes/, one method per endpoint
  db/         local_draft_db.dart — sqflite offline-draft cache
  screens/    login_screen.dart, register_screen.dart, home_shell.dart, claims_list_screen.dart,
              new_claim_screen.dart, claim_detail_screen.dart, approvals_queue_screen.dart,
              pending_users_screen.dart (admin), dev_login_screen.dart (unused)
  widgets/    status_badge.dart, payment_section.dart
main.dart     _StartupGate: LoginScreen if no stored token, else HomeShell
```

## Running it (once Flutter is installed — `flutter doctor` should be clean)

```bash
cd app
flutter create --platforms=web,android,ios,windows,macos .   # fills in platform runner folders only
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

Point `API_BASE_URL` at wherever `uvicorn app.main:app` is actually listening.

## Signing in

`POST /auth/login` exists. `LoginScreen` calls `AuthService.login`, which
stores the JWT via `AuthSession` (secure storage). New users register via
`RegisterScreen` and stay `PENDING` until an Admin approves them in the
"Pending Approvals" tab (`PendingUsersScreen`), assigning a `role_id`.
The database has no seed data, so create the first company and Admin user
with SQL (see `../docs/PROJECT_DOCUMENTATION.md`).

`DevLoginScreen` (paste-a-JWT) is no longer referenced anywhere and can be
deleted; `test/widget_test.dart` still expects its "Dev sign-in" text and
fails against the current `LoginScreen` start.

## Known gaps (flagged, not silently assumed)

- `PendingUsersScreen` still prompts for a numeric role id; the backend now
  has `GET /auth/roles` (Admin) that it should call for a picker.
- No role-gating in the UI — `HomeShell` shows all three tabs to everyone.
  The backend only enforces Admin on the pending-users routes; the
  Finance/approval routes have no role check.
- Offline sync is one-directional today: `NewClaimScreen` falls back to
  `LocalDraftDb` when `ClaimService.createClaim` can't reach the server,
  but nothing yet re-plays `unsyncedDrafts()` once connectivity returns —
  that's the next piece to build, not forgotten.
- Whether a synced local draft row is deleted or kept as a read cache is
  still **OPEN/PENDING** per `ARCHITECTURE.md` §1.
- Claim-type field (`claim_type_field`) rendering — the dynamic
  per-claim-type JSONB fields aren't surfaced in `NewClaimScreen` yet;
  only the fixed columns (title, description, currency, line items) are.
