# Claim Settlement App — Architecture

Status: DDL, API, and Flutter client are implemented (v0.1.0, uncommitted); the decisions below remain the design record. Items marked OPEN/PENDING are still undecided. See `PROJECT_DOCUMENTATION.md` for the current as-built description.

## 1. Platform Strategy — single Flutter codebase, every platform

**Decision (confirmed 2026-10-15 — supersedes the original web-wrapper plan): Flutter is
the only frontend.** One Dart codebase targets every platform directly; no wrapper layer.

| Target | How it's delivered |
|---|---|
| Browser | Flutter Web build, served over HTTPS; PWA manifest for installability. |
| Android / iOS | Flutter native build — compiles to native widgets, not a wrapped web view. |
| Windows / macOS | Flutter desktop build — same codebase, native binary. |

Backend is unaffected by this choice — FastAPI + PostgreSQL stays the system of record;
Flutter talks to the same JSON API any frontend would. Offline-first claim drafting is a
confirmed requirement (a claimant can draft a claim with no connectivity and sync later):
Flutter handles this with on-device local storage and a sync layer that reconciles to the
server once connectivity returns. The UUID primary keys on `claim`, `claim_line_item`,
`attachment`, `claim_event`, and `reimbursement_payment` (§8 below) were already designed
for exactly this and need no change.

**Two databases, two different jobs — not a choice between them:**
- **PostgreSQL (server)** — the system of record. Multi-tenant, multi-user, RLS-enforced,
  ACID, audit-trailed. Non-negotiable for the approval/payment workflow (§3, §4). SQLite
  cannot do this job: no concurrent multi-user writes, no RLS, no network access.
- **SQLite (on-device, via `sqflite` — `drift` was considered but is not a dependency)** — the client-side local cache. Holds
  claims drafted with no connectivity, each with its UUID already minted client-side,
  until a sync service pushes them to the FastAPI server. Once synced, Postgres is the
  only source of truth; whether the local copy is then cleared or kept as a read cache
  is **OPEN/PENDING** — not yet decided, flagged for later rather than assumed here.

Reasoning for the switch: Flutter compiles to native UI on every target instead of wrapping
a web view, giving genuinely native feel on mobile/desktop from one codebase — a stronger
version of the "write once" goal than the wrapper approach achieved. Tradeoff accepted
knowingly: Dart is a new language/toolchain with no reuse of the Alpine/Tailwind patterns
used on NSS ERP, and the web ecosystem's component/debugging convenience is traded for
Flutter's own tooling (hot reload, native-widget rendering).

Superseded: Capacitor (mobile wrapper) and Tauri (desktop wrapper) are retired — see
decision log in §9.

## 2. Backend

- **FastAPI** — API-first, thin backend, OpenAPI docs free, same reasoning as NSS ERP: no ORM-owned schema, SQL stays hand-controlled and auditable.
- **PostgreSQL** as the system of record — see Section 3 for the NoSQL question.
- Authentication: JWT-based, scoped per company (tenant), following your own RBAC design rather than a framework default.
- No DB-owner connections from the app — a dedicated least-privilege `app_backend` role, same pattern as `nss_db_backend`.

## 3. Database engine: PostgreSQL, not NoSQL

Decision (see chat for full comparison table): **PostgreSQL with JSONB for configurable parts.**

Reasoning in one line: this product moves money through a multi-step approval chain and needs
an audit trail — ACID transactions, foreign-key integrity, and relational reporting are
non-negotiable for that. JSONB columns absorb the one place NoSQL would have won
(per-company configurable claim fields and workflow definitions), so Postgres covers both
needs without taking on NoSQL's consistency tradeoffs.

## 4. Multi-Tenancy Model

**Decision (confirmed): shared database, `company_id` on every row, Postgres Row-Level Security.**

One schema, one DDL rebuild script. Every tenant-scoped table carries `company_id`, RLS policies
scope every query to `current_setting('app.current_company_id')` set from the logged-in user's
session, so isolation is enforced by Postgres itself, not application-code discipline. Fits the
DDL-direct-rebuild workflow used on NSS ERP — one set of scripts, not N per tenant.

## 5. Repository Layout

Following the NSS ERP precedent (no Django-style `backend/`):

```
Claim_Settlement_App/
  database/   PostgreSQL DDL — source of truth, hand-written, no ORM migrations
  api/        FastAPI application
  app/        Flutter application — single codebase for web, Android, iOS, Windows, macOS
  docs/       This file, business rules, module docs
```

## 6. Dev Sequence

Per your standard process: **Business Rules → Docs → Database (DDL) → API → UI.**
Flutter app development happens last, once the API is functional — building against a
real API from day one avoids re-wiring the data layer once the backend stabilizes.

## 7. Deployment (tentative, confirm later)

- Backend: Render (your usual preference), Postgres on Neon or Render-managed Postgres.
- You handle git push and review changes locally before committing, per your standing preference — no auto-commit.

## 8. Primary Key Strategy

**Decision (confirmed): mixed — UUID where offline/client-side creation is possible, bigint identity everywhere else.**

- **UUID** — `claim`, `claim_line_item`, `attachment`, `claim_event`, `reimbursement_payment`. These are the entities a claimant could originate without a live connection (e.g. drafting a claim on a phone with no signal); the client generates a final, collision-free ID with no server round-trip, and syncs later.
- **Bigint identity** — `company`, `role`, `company_user`, `claim_type`, `claim_type_field`, `approval_workflow`, `approval_level`, `approver_set_member`, `approval_step`, `fx_rate`. These only get created through a direct, online admin/server action, so leaner sequential keys apply.
- **Natural key** — `currency` uses its ISO 4217 code (char(3)) as primary key.

## 9. Open Decisions Before DDL Starts

1. ~~Shared DB + RLS vs schema-per-tenant~~ — **Resolved: shared DB + RLS.**
2. ~~Approval levels: sequential-only vs parallel~~ — **Resolved: approval engine supports both per level, per company (see BUSINESS_RULES.md §4).**
3. ~~Primary key strategy~~ — **Resolved: mixed UUID/bigint, see §8 above.**
4. ~~Frontend framework: web (wrapped) vs Flutter~~ — **Resolved 2026-10-15: full switch to Flutter, single codebase, all platforms. Reverses the original rejection recorded in an earlier draft of §1 — reopened because offline-first claim drafting (confirmed requirement) and native feel on mobile both favor Flutter over a wrapped web view. See §1.**
5. Project/repo name: using `Claim_Settlement_App` as working name — confirm or rename.
6. **OPEN/PENDING** — Approver escalation/delegation (auto-reassign on unavailability) is deferred to phase 2 per BUSINESS_RULES.md §8; DDL will not model it, but `approval_step` leaves room for a future `delegated_to` column.
7. **OPEN/PENDING** — Whether `fx_rate` is a global table or can be overridden per company (e.g. a company negotiates its own conversion rate with its bank) is not yet decided. DDL will model it as global for v1 and flag this for confirmation.
