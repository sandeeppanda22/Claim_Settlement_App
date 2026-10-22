"""
Payment routes — the Finance-side lifecycle: Approved -> Pending Finance
Review -> Payment Initiated -> Reimbursed -> Closed (BUSINESS_RULES.md §3).
reimbursement_payment is Finance's own table (the "money side"); it does not
own workflow state (that's claim + approval_step, in approvals.py).

Role/permission gating (who may call these — e.g. a Finance role) is not
yet enforced anywhere in this API, approvals.py included; RLS + ownership
are the only gates today. Flagged here rather than silently assumed —
a company_user.role_id check is a future slice once RBAC enforcement is
designed, not invented ad hoc for this one router.
"""
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.database import get_tenant_connection
from app.core.security import CurrentUser, get_current_user
from app.schemas.payment import ClaimStatusOut, PaymentCreate, PaymentOut
from app.services.claim_transitions import get_claim_for_update, require_status, transition

router = APIRouter(prefix="/claims", tags=["payments"])


@router.post("/{claim_id}/finance-review", response_model=ClaimStatusOut)
async def start_finance_review(
    claim_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> ClaimStatusOut:
    claim = await get_claim_for_update(conn, claim_id)
    require_status(claim, "APPROVED")
    await transition(
        conn, claim_id, "APPROVED", "PENDING_FINANCE_REVIEW",
        "FINANCE_REVIEW_STARTED", user.company_user_id,
    )
    return ClaimStatusOut(claim_id=claim_id, status="PENDING_FINANCE_REVIEW")


@router.post("/{claim_id}/payments", response_model=PaymentOut, status_code=status.HTTP_201_CREATED)
async def initiate_payment(
    claim_id: UUID,
    payload: PaymentCreate,
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> PaymentOut:
    claim = await get_claim_for_update(conn, claim_id)
    require_status(claim, "PENDING_FINANCE_REVIEW")

    payment_row = await conn.fetchrow(
        """
        INSERT INTO reimbursement_payment (
            claim_id, status, payout_currency_code, payout_amount,
            payout_fx_rate, method, reference_number, initiated_by_user_id
        )
        VALUES ($1, 'INITIATED', $2, $3, $4, $5, $6, $7)
        RETURNING id, claim_id, status, payout_currency_code, payout_amount,
                  payout_fx_rate, method, reference_number,
                  initiated_by_user_id, initiated_at, paid_at, created_at
        """,
        claim_id,
        payload.payout_currency_code,
        payload.payout_amount,
        payload.payout_fx_rate,
        payload.method,
        payload.reference_number,
        user.company_user_id,
    )
    await transition(
        conn, claim_id, "PENDING_FINANCE_REVIEW", "PAYMENT_INITIATED",
        "PAYMENT_INITIATED", user.company_user_id,
    )
    return PaymentOut(**dict(payment_row))


@router.get("/{claim_id}/payments", response_model=list[PaymentOut])
async def list_payments(
    claim_id: UUID,
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> list[PaymentOut]:
    rows = await conn.fetch(
        """
        SELECT id, claim_id, status, payout_currency_code, payout_amount,
               payout_fx_rate, method, reference_number,
               initiated_by_user_id, initiated_at, paid_at, created_at
        FROM reimbursement_payment
        WHERE claim_id = $1
        ORDER BY initiated_at
        """,
        claim_id,
    )
    return [PaymentOut(**dict(row)) for row in rows]


async def _get_payment_for_update(
    conn: asyncpg.Connection, claim_id: UUID, payment_id: UUID
) -> asyncpg.Record:
    row = await conn.fetchrow(
        "SELECT * FROM reimbursement_payment WHERE id = $1 AND claim_id = $2 FOR UPDATE",
        payment_id,
        claim_id,
    )
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Payment not found.")
    if row["status"] != "INITIATED":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Payment is '{row['status']}', not INITIATED — already settled one way or another.",
        )
    return row


@router.post("/{claim_id}/payments/{payment_id}/mark-paid", response_model=PaymentOut)
async def mark_payment_paid(
    claim_id: UUID,
    payment_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> PaymentOut:
    await _get_payment_for_update(conn, claim_id, payment_id)
    claim = await get_claim_for_update(conn, claim_id)
    require_status(claim, "PAYMENT_INITIATED")

    payment_row = await conn.fetchrow(
        """
        UPDATE reimbursement_payment SET status = 'PAID', paid_at = now()
        WHERE id = $1
        RETURNING id, claim_id, status, payout_currency_code, payout_amount,
                  payout_fx_rate, method, reference_number,
                  initiated_by_user_id, initiated_at, paid_at, created_at
        """,
        payment_id,
    )
    await transition(
        conn, claim_id, "PAYMENT_INITIATED", "REIMBURSED",
        "REIMBURSED", user.company_user_id,
    )
    return PaymentOut(**dict(payment_row))


@router.post("/{claim_id}/payments/{payment_id}/mark-failed", response_model=PaymentOut)
async def mark_payment_failed(
    claim_id: UUID,
    payment_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> PaymentOut:
    await _get_payment_for_update(conn, claim_id, payment_id)
    claim = await get_claim_for_update(conn, claim_id)
    require_status(claim, "PAYMENT_INITIATED")

    payment_row = await conn.fetchrow(
        """
        UPDATE reimbursement_payment SET status = 'FAILED'
        WHERE id = $1
        RETURNING id, claim_id, status, payout_currency_code, payout_amount,
                  payout_fx_rate, method, reference_number,
                  initiated_by_user_id, initiated_at, paid_at, created_at
        """,
        payment_id,
    )
    # Back to Pending Finance Review, not stuck — reimbursement_payment's own
    # comment documents "a failed attempt followed by a retry"; a fresh
    # POST /payments on this claim opens the retry attempt.
    await transition(
        conn, claim_id, "PAYMENT_INITIATED", "PENDING_FINANCE_REVIEW",
        "PAYMENT_FAILED", user.company_user_id,
    )
    return PaymentOut(**dict(payment_row))


@router.post("/{claim_id}/close", response_model=ClaimStatusOut)
async def close_claim(
    claim_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> ClaimStatusOut:
    claim = await get_claim_for_update(conn, claim_id)
    require_status(claim, "REIMBURSED")
    await transition(
        conn, claim_id, "REIMBURSED", "CLOSED", "CLOSED", user.company_user_id
    )
    return ClaimStatusOut(claim_id=claim_id, status="CLOSED")
