# Claim Settlement App — Business Rules

Status: partially implemented. Built: claim create/read, submit, multi-level approve/reject/return/resubmit, Finance review → payment → close. Not yet built: cancel, `PATCH /claims/{id}`, attachments, FX snapshot at submission (§5), claim-type field management. The `SUBMITTED` status exists in the enum but the API goes directly from `DRAFT` to `PENDING_APPROVAL` (or `APPROVED`).

## 1. Product Summary

A multi-tenant SaaS product sold to companies for managing employee/external-party
claim submission, configurable multi-level approval, and reimbursement tracking —
across web, mobile (Android/iOS), and desktop (Windows/macOS).

Each purchasing company ("tenant") configures its own:
- Claim types and the fields each type captures
- Approval workflow (who approves, how many levels, amount-based routing)
- Currencies in use
- Users and roles

## 2. Core Entities (conceptual — not yet DDL)

| Entity | Purpose |
|---|---|
| `company` (tenant) | A purchasing organization. Root of all tenant-scoped data. |
| `company_user` | A person who can log in under a company — employee or external claimant. |
| `role` | Permission set within a company (Claimant, Approver, Finance, Admin). |
| `claim_type` | Company-defined category (Travel, Medical, Expense, Advance, ...). Company-specific. |
| `claim_type_field` | JSONB-driven field definition for a claim_type (label, data type, required, validation, policy limit). |
| `claim` | A single claim submitted by a user, of one claim_type. |
| `claim_line_item` | Individual expense lines within a claim (date, category, amount, currency, description). |
| `attachment` | Receipt/file linked to a claim or line item. Manual-entry claims may have none. |
| `approval_workflow` | Company-defined chain: ordered levels, approver role/person per level, amount thresholds that trigger/skip levels. |
| `approval_step` | One level's outcome for one claim (approver, decision, timestamp, comment). |
| `claim_event` | Immutable audit log — every state transition, every actor, every timestamp. This is the traceability layer. |
| `currency` / `fx_rate` | Supported currencies and exchange rates (for multi-currency claims vs. company base currency). |
| `reimbursement_payment` | The actual payout record — method, reference, amount, date, status. |

This mirrors the NSS ERP boundary principle already in use: **claim + approval_step = the
"communication" side (who said yes/no, when); reimbursement_payment = the "money" side;
claim_event = the traceability linking them.** Administration doesn't own money movement;
Finance doesn't own workflow state — each stays in its lane and the event log ties them together.

## 3. Claim Lifecycle (state machine)

```
Draft → Submitted → Pending Approval (Level 1..N) → Approved
                                   ↘ Rejected
                                   ↘ Returned for Revision → (back to Draft, resubmit)
Approved → Pending Finance Review → Payment Initiated → Reimbursed → Closed
Any state → Cancelled (claimant withdraws, before Payment Initiated)
```

Rules:
- Every transition writes a `claim_event` row — actor, from-state, to-state, comment, timestamp. No transition is silent.
- "Returned for Revision" is not "Rejected" — it preserves the claim for resubmission rather than killing it (same spirit as NSS ERP's registration_claim pattern: a separate claim record that supports reject/resubmit without destroying history).
- A resubmitted claim keeps its original claim ID and appends new events — it does not become a new claim.

> **Resubmission design (2026-10-15):** `RETURNED_FOR_REVISION` is a single-approver decisive outcome on `POST /claims/{id}/decide` — one approver sending a claim back ends that level immediately (same as a reject; the other still-pending approvers at that level never got to act, so their steps are marked SKIPPED, not left dangling as PENDING). `POST /claims/{id}/resubmit` re-enters the claim into its workflow restarting at level 1 — not resuming from the level it was returned at — because the claimant may have changed the amount or line items while fixing it, and amount-range routing has to be re-evaluated against current data. Same claim ID throughout; `claim_event` rows (`RETURNED_FOR_REVISION`, then `RESUBMITTED`) narrate the round-trip. Editing the claim's own fields before resubmitting (title/description/line items) is a separate `PATCH /claims/{id}` slice — not yet built; `resubmit` only re-opens the workflow against whatever the claim's current row already holds.

## 4. Approval Engine

- **Decision (confirmed): `approval_workflow` is keyed per `claim_type`, not company-wide.** A company may define a different chain for Travel vs. Procurement vs. Medical. A company MAY also define one company-wide fallback workflow (claim_type = NULL) for claim types that don't need a custom chain — if a claim_type has no dedicated workflow, the fallback applies. A claim_type with neither a dedicated workflow nor a fallback available is a configuration error (surfaced to the admin at claim_type setup, not discovered at submission time).
- A level can route by **role** (e.g. "Direct Manager"), by **named person**, or by **amount threshold** (e.g. claims over $5,000 require a second level).
- **Decision (confirmed): the engine supports both sequential and parallel-at-a-level, configured per level, per company** — since requirements will vary by customer and we don't yet know the full range. Design:
  - A level has one or more **eligible approvers** (an "approver set" — could be size 1, which is the simple single-approver case).
  - A level has a **completion rule**: `ANY` (first eligible approver to act clears the level; the claim disappears from the others' queues) or `ALL` (every eligible approver must approve before the level clears).
  - Levels themselves remain **strictly ordered** — Level 2 never opens until Level 1 clears. "Parallel" refers only to multiple approvers *within* one level, not levels running concurrently.
  - Single-approver-per-level (the simple case) is just an approver set of size 1 with rule `ANY` — no special-casing needed, it falls out of the general model.
- Escalation/delegation (auto-reassign if an approver is unavailable) is **not yet designed** — flag if needed for v1 or can be deferred to phase 2.
- **Decision (confirmed): whether a skipped level (excluded by amount-range routing) leaves an audit trace is a per-workflow org policy, not a hard-coded behavior.** Each `approval_workflow` carries `record_skipped_levels` (default `TRUE`). When `TRUE`, a level the claim's amount doesn't qualify for still gets an `approval_step` row with `decision = 'SKIPPED'` — a complete record of every level the claim passed through, including the ones that didn't apply. When `FALSE`, the claim moves straight to the next qualifying level with no row for the skipped one. Nothing in the engine assumes one behavior universally — each company's workflow configuration decides.

## 5. Multi-Currency Rules

- Each claim is submitted in a currency chosen by the claimant (e.g. traveler paid in EUR).
- Each company has a **base/reporting currency**.
- At submission time, the claim snapshots the FX rate used to convert to company base currency — so later rate changes never retroactively alter an already-submitted claim's reported value.
- Reimbursement can be paid out in a third currency (e.g. employee's home currency) — payment record tracks claim currency, company base currency, and payout currency separately.

## 6. Attachments

- Both manual entry (no receipt) and file upload are supported.
- OCR/auto-extraction from receipts is explicitly **phase 2**, not v1 — v1 stores the file and lets the user key in the amount/date manually.

## 7. Multi-Tenancy

- Multi-tenant from day one, confirmed. Data model and DB-level isolation details are covered in `ARCHITECTURE.md`.
- Claim types, fields, approval workflows, currencies, and roles are all **per-company configuration**, not global constants.

## 8. Out of Scope for v1 (explicitly deferred)

- OCR/receipt auto-extraction
- Approver delegation/escalation automation
- Integration with external HR/Finance systems (confirmed standalone product)
