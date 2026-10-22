"""
claim routes — create (Draft, with line items) and read.
Submission (Draft -> Submitted, entering the approval workflow) is a
separate slice — this file only covers claim origination, which is enough
to unblock the Flutter offline-draft -> sync path end to end.
"""
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.database import get_tenant_connection
from app.core.security import CurrentUser, get_current_user
from app.schemas.claim import ClaimCreate, ClaimLineItemOut, ClaimOut

router = APIRouter(prefix="/claims", tags=["claims"])


async def _load_line_items(conn: asyncpg.Connection, claim_id: UUID) -> list[ClaimLineItemOut]:
    rows = await conn.fetch(
        """
        SELECT id, claim_id, line_number, expense_date, category, description,
               amount, field_values, created_at
        FROM claim_line_item
        WHERE claim_id = $1
        ORDER BY line_number
        """,
        claim_id,
    )
    return [ClaimLineItemOut(**dict(row)) for row in rows]


@router.post("", response_model=ClaimOut, status_code=status.HTTP_201_CREATED)
async def create_claim(
    payload: ClaimCreate,
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> ClaimOut:
    total_amount = sum(item.amount for item in payload.line_items)

    claim_row = await conn.fetchrow(
        """
        INSERT INTO claim (
            id, company_id, claim_type_id, company_user_id, status,
            title, description, claim_currency_code, total_amount
        )
        VALUES (
            COALESCE($1, gen_random_uuid()), $2, $3, $4, 'DRAFT',
            $5, $6, $7, $8
        )
        RETURNING id, company_id, claim_type_id, company_user_id, status,
                  title, description, claim_currency_code, fx_rate_to_base,
                  base_currency_code, total_amount, current_level_id,
                  submitted_at, created_at
        """,
        payload.id,
        user.company_id,
        payload.claim_type_id,
        user.company_user_id,
        payload.title,
        payload.description,
        payload.claim_currency_code,
        total_amount,
    )
    claim_id = claim_row["id"]

    for item in payload.line_items:
        await conn.execute(
            """
            INSERT INTO claim_line_item (
                claim_id, line_number, expense_date, category, description,
                amount, field_values
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            """,
            claim_id,
            item.line_number,
            item.expense_date,
            item.category,
            item.description,
            item.amount,
            item.field_values,
        )

    # Every transition writes a claim_event row — no transition is silent
    # (BUSINESS_RULES.md §3). Origination has no from_status.
    await conn.execute(
        """
        INSERT INTO claim_event (claim_id, event_type, from_status, to_status, actor_company_user_id)
        VALUES ($1, 'CREATED', NULL, 'DRAFT', $2)
        """,
        claim_id,
        user.company_user_id,
    )

    line_items = await _load_line_items(conn, claim_id)
    return ClaimOut(**dict(claim_row), line_items=line_items)


@router.get("/{claim_id}", response_model=ClaimOut)
async def get_claim(
    claim_id: UUID,
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> ClaimOut:
    row = await conn.fetchrow(
        """
        SELECT id, company_id, claim_type_id, company_user_id, status,
               title, description, claim_currency_code, fx_rate_to_base,
               base_currency_code, total_amount, current_level_id,
               submitted_at, created_at
        FROM claim
        WHERE id = $1
        """,
        claim_id,
    )
    if row is None:
        # RLS means a cross-tenant id looks identical to a missing one —
        # both correctly surface as 404, never a leak of existence.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found.")

    line_items = await _load_line_items(conn, claim_id)
    return ClaimOut(**dict(row), line_items=line_items)


@router.get("", response_model=list[ClaimOut])
async def list_my_claims(
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> list[ClaimOut]:
    # Own claims only for v1 of this slice. Approver/Finance-wide visibility
    # (claims pending at a level this user can act on) is OPEN/PENDING —
    # belongs to the approval_workflow slice, not claim origination.
    rows = await conn.fetch(
        """
        SELECT id, company_id, claim_type_id, company_user_id, status,
               title, description, claim_currency_code, fx_rate_to_base,
               base_currency_code, total_amount, current_level_id,
               submitted_at, created_at
        FROM claim
        WHERE company_user_id = $1
        ORDER BY created_at DESC
        """,
        user.company_user_id,
    )
    results = []
    for row in rows:
        line_items = await _load_line_items(conn, row["id"])
        results.append(ClaimOut(**dict(row), line_items=line_items))
    return results
