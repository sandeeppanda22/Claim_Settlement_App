# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Multi-tenant claim submission / multi-level approval / reimbursement product. Three independent parts: `database/` (hand-written PostgreSQL DDL), `api/` (FastAPI + asyncpg, no ORM), `app/` (single Flutter codebase). Design intent lives in `docs/ARCHITECTURE.md` and `docs/BUSINESS_RULES.md`; a fuller walkthrough is in `docs/PROJECT_DOCUMENTATION.md`. Dev sequence is Business Rules → Docs → DDL → API → UI.

## Commands

```bash
# Database — DROPS and recreates the public schema every run (local dev only)
./database/build.sh "postgresql://localhost:5432/claim_settlement_dev"

# API (run from api/; reads api/.env — DATABASE_URL, JWT_SECRET, JWT_ALGORITHM, DB_POOL_MIN_SIZE/MAX_SIZE)
cd api && pip install -r requirements.txt
uvicorn app.main:app --reload          # http://localhost:8000, docs at /docs

# Flutter (run from app/)
cd app && flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
flutter analyze
flutter test                           # single: flutter test test/widget_test.dart
```

There is no Python test suite, linter config, or Makefile. `app/test/widget_test.dart` is stale (expects "Dev sign-in"; the app now boots to `LoginScreen`) and will fail.

## Architecture (the parts that span files)

- **Tenant isolation is done by Postgres RLS, not app code.** `core/database.py:get_tenant_connection` opens a transaction and `set_config('app.current_company_id', …, true)` from the JWT's `company_id`; every policy in `database/ddl/08_rls_policies.sql` keys off `current_company_id()` (fail-closed when unset). Every authenticated route must take its connection from this dependency. The pre-auth routes (`/auth/register`, `/auth/login`) can't, so `routes/auth.py` sets the variable by hand after resolving the company (EMPLOYEE via `company_email_domain`, which is deliberately not RLS-protected; NON_EMPLOYEE via explicit `company_id`).
- **Approval engine** (`api/app/services/approval_engine.py`) is pure logic called by `routes/approvals.py`. Workflow resolution: dedicated per-`claim_type` workflow, else company fallback (`claim_type_id IS NULL`), else 422. Levels are strictly ordered; within a level `completion_rule` is `ANY`/`ALL`; amount ranges (`min_amount` inclusive, `max_amount` exclusive) decide which levels apply; skipped levels get a `SKIPPED` `approval_step` only if the workflow's `record_skipped_levels`. REJECTED and RETURNED_FOR_REVISION are single-approver decisive. Resubmit restarts at level 1.
- **Every claim status transition goes through `services/claim_transitions.py`** (`get_claim_for_update` → `require_status` → `transition`, or `record_event` alone for a decision that doesn't change status). That is the single place that enforces "no status change without a `claim_event`". `transition()`'s `current_level_id` uses an `_UNSET` sentinel so "leave alone" ≠ "set NULL". Used by `routes/approvals.py` and `routes/payments.py`; `mark-failed` returns the claim to `PENDING_FINANCE_REVIEW` for a retry.
- **Flutter** layering: `models/` mirror `api/app/schemas/*.py`, `services/` is one class per router (one method per endpoint), `core/api_client.dart` is the only HTTP caller and surfaces FastAPI's `detail` as `ApiException`. JWT is held by `core/auth_session.dart` (secure storage). Claims are created client-side with UUIDs so `NewClaimScreen` can fall back to `db/local_draft_db.dart` (sqflite) when offline.

## Gotchas

- Schema changes are **DDL edits only** — no ALTER migrations; edit the numbered file in `database/ddl/` and rebuild. Files run in filename order.
- IDs: UUID for claim/line item/attachment/claim_event/reimbursement_payment (client-originable), bigint identity for the rest, `currency.code` natural key.
- The DDL creates no `app_backend` role/grants and there is **no seed data** (companies, roles, currencies, workflows, email domains). Nothing in the API creates companies, roles, workflows/levels/approver members, or `claim_type_field` rows — insert them with SQL.
- No RBAC beyond `require_admin` (role name == `'Admin'`) on `/auth/pending-users*` and `GET /auth/roles`. `/auth/roles` exists but the Flutter `PendingUsersScreen` doesn't use it yet (still asks for a raw numeric role id). Approval, Finance/payment, and claim-type creation routes are only gated by RLS + (for decide) being a pending approver.
- Not built: offline draft re-sync (`unsyncedDrafts()` is never replayed), `PATCH /claims/{id}`, cancel, attachments endpoints, dynamic `claim_type_field` rendering in the UI, FX snapshot on submit (`fx_rate_to_base`/`base_currency_code` stay NULL), the `SUBMITTED` status is unused (DRAFT goes straight to PENDING_APPROVAL/APPROVED).
- `app/lib/screens/dev_login_screen.dart` is dead code (unreferenced); its and `AuthSession`'s comments claiming no login endpoint exists are stale.
- `JWT_SECRET` defaults to `CHANGE_ME_IN_ENV`; the repo has no commits yet.
