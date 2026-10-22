# database/ — PostgreSQL schema

Source of truth for the schema: hand-written DDL, no ORM migrations, no ALTERs. Change a file in `ddl/` and rebuild. Context: `../docs/ARCHITECTURE.md` §3, §4, §8.

## Rebuild

```bash
./build.sh "postgresql://localhost:5432/claim_settlement_dev"
```

Drops and recreates the `public` schema, then applies `ddl/*.sql` in filename order with `ON_ERROR_STOP`. Local dev only. Requires `psql`.

## ddl/

| File | Contents |
|---|---|
| `00_extensions.sql` | `pgcrypto`; enums (`claim_status`, `approval_decision`, `approval_completion_rule`, `approver_member_type`, `payment_status`, `company_user_type`, `user_approval_status`) |
| `01_tenancy.sql` | `company`, `company_email_domain`, `role`, `company_user` |
| `02_reference.sql` | `currency`, `fx_rate` (global, not RLS) |
| `03_claim_type.sql` | `claim_type`, `claim_type_field` |
| `04_approval_workflow.sql` | `approval_workflow`, `approval_level`, `approver_set_member` |
| `05_claim.sql` | `claim`, `claim_line_item`, `attachment` |
| `06_approval_step_and_events.sql` | `approval_step`, `claim_event` |
| `07_payment.sql` | `reimbursement_payment` |
| `08_rls_policies.sql` | `current_company_id()` and an RLS policy (ENABLE + FORCE) per tenant table |

## Not included

No seed data and no `app_backend` role or grants, even though the API expects to connect as a least-privilege `app_backend`. Create these separately.
