# Claim Settlement App — Project Documentation

A standalone walkthrough for humans. For design rationale see `ARCHITECTURE.md` and `BUSINESS_RULES.md` in this folder; for terse agent instructions see the root `CLAUDE.md`.

## Overview

A multi-tenant product that lets companies (tenants) collect expense/reimbursement claims from employees and external parties, route them through a configurable multi-level approval chain, and track the Finance-side payout to completion. Each company configures its own claim types, approval workflows, roles, users and currencies.

The repo holds three independently runnable parts: a PostgreSQL schema (`database/`), a FastAPI JSON API (`api/`), and a Flutter client (`app/`) targeting web, Android, iOS, Windows and macOS. The project has no git commits yet.

## Architecture

**Request flow.** The Flutter app calls the API through `app/lib/core/api_client.dart`, attaching the stored JWT as a bearer token. FastAPI's `core/security.py:get_current_user` decodes it into a `CurrentUser` (`company_user_id`, `company_id`, `role_id`, `email`). Routes then depend on `core/database.py:get_tenant_connection`, which acquires a pooled asyncpg connection, opens a transaction and calls `set_config('app.current_company_id', <company_id>, true)`. From that point Postgres row-level security (`database/ddl/08_rls_policies.sql`) filters every table to the caller's company, so a cross-tenant id looks identical to a missing row (404). All tables except `currency` and `fx_rate`, plus `company_email_domain`, are RLS-protected and `FORCE`d.

**Pre-auth exception.** `/auth/register` and `/auth/login` have no token yet, so `routes/auth.py:_resolve_company_id` resolves the company itself (EMPLOYEE: email domain via `company_email_domain`; NON_EMPLOYEE: explicit `company_id`), checks `company.is_active` and `allowed_claimant_types`, and sets the session variable by hand. All failure modes return one generic message so callers cannot probe which part was wrong.

**Approval engine.** `services/approval_engine.py` holds the logic; `routes/approvals.py` holds HTTP and claim status updates. A company has `approval_workflow` rows (per claim type, or one fallback with `claim_type_id IS NULL`), each with ordered `approval_level` rows; each level has `approver_set_member` rows (a specific USER or everyone holding a ROLE) and a `completion_rule` (`ANY` or `ALL`). Opening a level inserts one `PENDING` `approval_step` per eligible user.

**Client storage.** Postgres is the only system of record. The Flutter app keeps an on-device sqflite table (`draft_claim`) so a claim can be drafted offline with a client-minted UUID.

## Directory structure

| Path | Responsibility |
|---|---|
| `database/ddl/` | Numbered DDL files `00`–`08`, applied in filename order by `database/build.sh`. |
| `api/app/main.py` | App entrypoint, pool lifespan, router mounting. |
| `api/app/core/` | `config.py` (settings), `database.py` (pool + tenant connection), `security.py` (JWT, bcrypt, `CurrentUser`). |
| `api/app/api/routes/` | `health`, `auth` (+ `admin_router`), `claim_types`, `claims`, `approvals` (+ `queue_router`), `payments`. |
| `api/app/schemas/` | Pydantic request/response models (`auth`, `claim`, `claim_type`, `approval`, `payment`). |
| `api/app/services/approval_engine.py` | Workflow resolution and level progression. |
| `api/app/services/claim_transitions.py` | Shared status-change primitives (`get_claim_for_update`, `require_status`, `transition`, `record_event`) used by approvals and payments. |
| `app/lib/` | Flutter source: `core/`, `models/`, `services/`, `screens/`, `widgets/`, `db/`. See `app/README.md`. |
| `app/{android,ios,macos,windows,web}/` | Generated platform runners. |
| `docs/` | Design docs and this file. |

Schema tables: `company`, `company_email_domain`, `role`, `company_user`, `currency`, `fx_rate`, `claim_type`, `claim_type_field`, `approval_workflow`, `approval_level`, `approver_set_member`, `claim`, `claim_line_item`, `attachment`, `approval_step`, `claim_event`, `reimbursement_payment`.

## Setup & running

1. **Database.** Create an empty Postgres database, then `./database/build.sh "<database_url>"`. This **drops and recreates the `public` schema** each run. The script needs `psql` on the path.
2. **Seed data (manual).** The DDL contains no inserts and creates no `app_backend` role. You must insert at least: currencies, a company, its roles (one named exactly `Admin`), a `company_email_domain`, an Admin `company_user` with `approval_status = 'APPROVED'` and a bcrypt `password_hash`, claim types, and an `approval_workflow` with levels and approver members. No API endpoints exist for these.
3. **API.** In `api/`: `pip install -r requirements.txt`, create `.env` (see Configuration), run `uvicorn app.main:app --reload`. Interactive docs at `/docs`; liveness at `GET /health`.
4. **App.** In `app/`: `flutter pub get`, then `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000`. The README suggests `flutter create --platforms=web,android,ios,windows,macos .` if runner folders are missing (they are currently present).
5. **Tests.** There are no API tests. `flutter test` runs `app/test/widget_test.dart`, which is stale (see Gotchas).

## Configuration

`api/app/core/config.py` (pydantic-settings, reads `.env`):

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | `postgresql://app_backend@localhost:5432/claim_settlement_dev` | Should be a least-privilege role, never the DB owner. |
| `JWT_SECRET` | `CHANGE_ME_IN_ENV` | HS256 signing key; must be overridden. |
| `JWT_ALGORITHM` | `HS256` | |
| `DB_POOL_MIN_SIZE` / `DB_POOL_MAX_SIZE` | `2` / `10` | asyncpg pool sizing. |

Flutter: `--dart-define=API_BASE_URL=...` (default `http://localhost:8000`, `app/lib/core/api_config.dart`). Access tokens last 12 hours (`ACCESS_TOKEN_EXPIRE_MINUTES` in `security.py`).

## Key workflows

**1. Registration and login.** `POST /auth/register` inserts a `company_user` as `PENDING` with no role. An Admin lists them (`GET /auth/pending-users`; `GET /auth/roles` lists assignable roles), then `POST …/{id}/approve` (assigns `role_id`) or `…/reject` (sets `is_active = FALSE` and a reason). `POST /auth/login` returns a JWT only for active, `APPROVED` users; a pending user gets 403. In the app: `LoginScreen` → `AuthService.login` stores the token → `HomeShell`.

**2. Claim origination.** `POST /claims` inserts a `DRAFT` claim (optionally with a client-supplied UUID `id`), its line items, and a `CREATED` `claim_event`; `total_amount` is the sum of line items. If the network call fails, `NewClaimScreen` saves to `LocalDraftDb` instead. `GET /claims` returns only the caller's own claims.

**3. Submit and approve.** `POST /claims/{id}/submit` (DRAFT only) resolves the workflow, calls `engine.advance` from level 0 and sets `PENDING_APPROVAL` (or `APPROVED` if every level was skipped). `GET /approvals/pending` is each approver's queue. `POST /claims/{id}/decide` with `APPROVED` / `REJECTED` / `RETURNED_FOR_REVISION` updates the caller's step and then evaluates `engine.level_outcome`:
- `REJECTED` → claim `REJECTED`.
- `RETURNED_FOR_REVISION` → other pending steps become `SKIPPED`, claim returns to the claimant; `POST /claims/{id}/resubmit` re-enters at level 1.
- `CLEARED` → remaining pending steps `SKIPPED`, advance to the next qualifying level or finish `APPROVED`.
- `PENDING` (an `ALL` level still waiting) → no change.

**4. Finance and payout.** `finance-review` (APPROVED → PENDING_FINANCE_REVIEW), `POST /payments` (→ PAYMENT_INITIATED, inserts an `INITIATED` payment), `mark-paid` (→ REIMBURSED) or `mark-failed` (payment `FAILED`, claim back to PENDING_FINANCE_REVIEW for a new attempt), then `close` (→ CLOSED). Each step uses `FOR UPDATE` and writes a `claim_event`.

## Conventions & gotchas

- DDL-only schema changes; no migrations. IDs are UUID for client-originable entities, bigint identity otherwise.
- Raw SQL via asyncpg everywhere; no ORM.
- Transitions lock the claim row (`FOR UPDATE`) and write their `claim_event` through `services/claim_transitions.py`; don't inline `UPDATE claim SET status` in routes. `decide` uses `record_event` for the per-approver `LEVEL_*` event, which leaves the status unchanged.
- `require_admin` lives in `routes/auth.py`, not `security.py`, to avoid a circular import. It checks `role.name == 'Admin'`.
- `GET /claims/{id}`, `GET /claims/{id}/payments` and the payment/finance routes do not check ownership or role; RLS (same company) is the only gate. The Flutter shell shows all three tabs to everyone.
- Level amount ranges are `min_amount <= total < max_amount`.
- A new level with no resolvable approvers makes submit/decide fail with 422 mid-transaction.
- `fx_rate_to_base` and `base_currency_code` on `claim` are never populated by the API; the multi-currency snapshot in BUSINESS_RULES §5 is not implemented. `fx_rate` is global.
- Stale code comments/tests: `app/test/widget_test.dart` expects "Dev sign-in"; `screens/dev_login_screen.dart` is unreferenced; `core/auth_session.dart` comment says login isn't built.
- `ARCHITECTURE.md` mentions `sqflite/drift`; only `sqflite` is a dependency.

## Open questions / TODOs

- Offline sync: nothing replays `LocalDraftDb.unsyncedDrafts()`; whether synced rows are deleted or kept is OPEN/PENDING.
- `PATCH /claims/{id}` (edit before resubmit), cancel (`CANCELLED` status is defined but unreachable), attachment endpoints, and `claim_type_field` management are not built; the UI doesn't render per-type fields.
- RBAC enforcement for approval/Finance routes; approver delegation/escalation (phase 2).
- Per-company `fx_rate` override; project name confirmation (ARCHITECTURE §9).
- `PendingUsersScreen` should use the new `GET /auth/roles` instead of a typed role id (its doc comment still says no such endpoint exists).
- Admin APIs for creating roles, workflows and companies (only role listing exists); seed data; `app_backend` role DDL/grants.
- Deployment is tentative (Render + Neon/Render Postgres).
