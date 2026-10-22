# api/ — FastAPI backend

JSON API over PostgreSQL via asyncpg (hand-written SQL, no ORM). Tenant isolation comes from Postgres RLS; see `core/database.py:get_tenant_connection`. Overview and workflows: `../docs/PROJECT_DOCUMENTATION.md`.

## Contents

```
app/main.py                    app + lifespan (pool init/close), mounts all routers
app/core/config.py             Settings from env/.env (DATABASE_URL, JWT_SECRET, JWT_ALGORITHM, pool sizes)
app/core/database.py           asyncpg pool; get_tenant_connection sets app.current_company_id per request
app/core/security.py           JWT create/decode, bcrypt hashing, CurrentUser, get_current_user
app/api/routes/health.py       GET /health
app/api/routes/auth.py         /auth/register, /auth/login, GET /auth/roles, /auth/pending-users[/{id}/approve|reject]; require_admin
app/api/routes/claim_types.py  GET/POST /claim-types
app/api/routes/claims.py       POST/GET /claims, GET /claims/{id}
app/api/routes/approvals.py    /claims/{id}/submit|resubmit|decide, GET /approvals/pending
app/api/routes/payments.py     /claims/{id}/finance-review|payments|close, payments/{pid}/mark-paid|mark-failed
app/schemas/                   Pydantic models, one file per router
app/services/approval_engine.py  workflow resolution, level progression, ANY/ALL outcome
app/services/claim_transitions.py  shared lock/check/update/claim_event primitives for every status change
```

## Run

```bash
pip install -r requirements.txt
uvicorn app.main:app --reload     # run from api/, needs .env
```

No tests or lint config exist. Role gating is only `require_admin` on the pending-user routes.
