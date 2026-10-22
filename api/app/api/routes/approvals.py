"""
approval routes — submit a claim into its workflow, and act on a pending
level (approve/reject). Level-progression rules live in
services/approval_engine.py; this file is the HTTP + claim_status layer.
"""
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.database import get_tenant_connection
from app.core.security import CurrentUser, get_current_user
from app.schemas.approval import ClaimApprovalStateOut, DecideRequest, PendingApprovalOut
from app.services import approval_engine as engine
from app.services.claim_transitions import get_claim_for_update, record_event, require_status, transition

router = APIRouter(prefix="/claims", tags=["approvals"])
queue_router = APIRouter(prefix="/approvals", tags=["approvals"])


@queue_router.get("/pending", response_model=list[PendingApprovalOut])
async def pending_approvals(
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> list[PendingApprovalOut]:
    """
    This user's approval queue — one row per claim currently sitting at a
    level where they have an un-acted PENDING approval_step. Scoped to
    'pending' only (approved/rejected claims aren't anyone's queue item
    anymore; a history view, if wanted, is a separate future slice).
    """
    rows = await conn.fetch(
        """
        SELECT
            s.id AS step_id,
            c.id AS claim_id,
            c.title AS claim_title,
            c.claim_type_id,
            c.total_amount,
            c.claim_currency_code,
            l.id AS level_id,
            l.level_number,
            c.submitted_at
        FROM approval_step s
        JOIN claim c ON c.id = s.claim_id
        JOIN approval_level l ON l.id = s.level_id
        WHERE s.approver_user_id = $1
          AND s.decision = 'PENDING'
          AND c.status = 'PENDING_APPROVAL'
          AND c.current_level_id = s.level_id
        ORDER BY c.submitted_at
        """,
        user.company_user_id,
    )
    return [PendingApprovalOut(**dict(row)) for row in rows]


@router.post("/{claim_id}/submit", response_model=ClaimApprovalStateOut)
async def submit_claim(
    claim_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> ClaimApprovalStateOut:
    claim = await get_claim_for_update(conn, claim_id)
    require_status(
        claim,
        "DRAFT",
        detail=f"Claim is '{claim['status']}', not DRAFT — only a Draft claim can be submitted.",
    )

    workflow_id, record_skipped_levels = await engine.resolve_workflow_id(
        conn, claim["company_id"], claim["claim_type_id"]
    )
    levels = await engine.get_ordered_levels(conn, workflow_id)
    opened = await engine.advance(
        conn, claim_id, float(claim["total_amount"]), levels, record_skipped_levels, 0
    )

    new_status = "PENDING_APPROVAL" if opened else "APPROVED"
    await transition(
        conn,
        claim_id,
        "DRAFT",
        new_status,
        "SUBMITTED",
        user.company_user_id,
        current_level_id=opened.id if opened else None,
        set_submitted_at=True,
    )

    return ClaimApprovalStateOut(
        claim_id=claim_id,
        status=new_status,
        current_level_id=opened.id if opened else None,
        current_level_number=opened.level_number if opened else None,
    )


@router.post("/{claim_id}/resubmit", response_model=ClaimApprovalStateOut)
async def resubmit_claim(
    claim_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> ClaimApprovalStateOut:
    """
    Re-enters a RETURNED_FOR_REVISION claim into its workflow. Restarts at
    level 1 rather than resuming where it was sent back from — the claimant
    may have changed amounts or line items while fixing it, so the amount-
    range routing is re-evaluated from scratch (BUSINESS_RULES.md §3: same
    claim ID, new events, not a new claim). Editing the claim's own fields
    before resubmitting is a separate PATCH /claims/{claim_id} slice, not
    yet built — this endpoint only re-opens the workflow on current data.
    """
    claim = await get_claim_for_update(conn, claim_id)
    require_status(
        claim,
        "RETURNED_FOR_REVISION",
        detail=f"Claim is '{claim['status']}', not RETURNED_FOR_REVISION — "
        "only a claim sent back for revision can be resubmitted.",
    )

    workflow_id, record_skipped_levels = await engine.resolve_workflow_id(
        conn, claim["company_id"], claim["claim_type_id"]
    )
    levels = await engine.get_ordered_levels(conn, workflow_id)
    opened = await engine.advance(
        conn, claim_id, float(claim["total_amount"]), levels, record_skipped_levels, 0
    )

    new_status = "PENDING_APPROVAL" if opened else "APPROVED"
    await transition(
        conn,
        claim_id,
        "RETURNED_FOR_REVISION",
        new_status,
        "RESUBMITTED",
        user.company_user_id,
        current_level_id=opened.id if opened else None,
        set_submitted_at=True,
    )

    return ClaimApprovalStateOut(
        claim_id=claim_id,
        status=new_status,
        current_level_id=opened.id if opened else None,
        current_level_number=opened.level_number if opened else None,
    )


@router.post("/{claim_id}/decide", response_model=ClaimApprovalStateOut)
async def decide(
    claim_id: UUID,
    payload: DecideRequest,
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> ClaimApprovalStateOut:
    claim = await get_claim_for_update(conn, claim_id)
    if claim["status"] != "PENDING_APPROVAL" or claim["current_level_id"] is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Claim is not currently awaiting an approval decision.",
        )
    level_id = claim["current_level_id"]

    step = await conn.fetchrow(
        """
        SELECT id FROM approval_step
        WHERE claim_id = $1 AND level_id = $2 AND approver_user_id = $3 AND decision = 'PENDING'
        """,
        claim_id,
        level_id,
        user.company_user_id,
    )
    if step is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not an eligible, still-pending approver for this claim's current level.",
        )

    await conn.execute(
        "UPDATE approval_step SET decision = $1, comment = $2, decided_at = now() WHERE id = $3",
        payload.decision.value,
        payload.comment,
        step["id"],
    )
    await record_event(
        conn,
        claim_id,
        f"LEVEL_{payload.decision.value}",
        "PENDING_APPROVAL",
        "PENDING_APPROVAL",
        user.company_user_id,
        comment=payload.comment,
    )

    level_row = await conn.fetchrow(
        "SELECT level_number, completion_rule FROM approval_level WHERE id = $1", level_id
    )
    outcome = await engine.level_outcome(conn, claim_id, level_id, level_row["completion_rule"])

    if outcome == "REJECTED":
        await transition(
            conn,
            claim_id,
            "PENDING_APPROVAL",
            "REJECTED",
            "REJECTED",
            user.company_user_id,
            current_level_id=None,
        )
        return ClaimApprovalStateOut(
            claim_id=claim_id, status="REJECTED", current_level_id=None, current_level_number=None
        )

    if outcome == "RETURNED_FOR_REVISION":
        # Decisive like a reject — the other still-pending approvers at this
        # level never got to act, same treatment as when a level clears.
        await engine.mark_remaining_pending_as_skipped(conn, claim_id, level_id)
        await transition(
            conn,
            claim_id,
            "PENDING_APPROVAL",
            "RETURNED_FOR_REVISION",
            "RETURNED_FOR_REVISION",
            user.company_user_id,
            current_level_id=None,
            comment=payload.comment,
        )
        return ClaimApprovalStateOut(
            claim_id=claim_id,
            status="RETURNED_FOR_REVISION",
            current_level_id=None,
            current_level_number=None,
        )

    if outcome == "PENDING":
        return ClaimApprovalStateOut(
            claim_id=claim_id,
            status="PENDING_APPROVAL",
            current_level_id=level_id,
            current_level_number=level_row["level_number"],
        )

    # outcome == "CLEARED" — advance to the next qualifying level, or finish.
    await engine.mark_remaining_pending_as_skipped(conn, claim_id, level_id)
    workflow_id, record_skipped_levels = await engine.resolve_workflow_id(
        conn, claim["company_id"], claim["claim_type_id"]
    )
    levels = await engine.get_ordered_levels(conn, workflow_id)
    start_index = next(i for i, lvl in enumerate(levels) if lvl.id == level_id) + 1
    opened = await engine.advance(
        conn, claim_id, float(claim["total_amount"]), levels, record_skipped_levels, start_index
    )

    new_status = "PENDING_APPROVAL" if opened else "APPROVED"
    await transition(
        conn,
        claim_id,
        "PENDING_APPROVAL",
        new_status,
        "LEVEL_CLEARED" if opened else "APPROVED",
        user.company_user_id,
        current_level_id=opened.id if opened else None,
    )

    return ClaimApprovalStateOut(
        claim_id=claim_id,
        status=new_status,
        current_level_id=opened.id if opened else None,
        current_level_number=opened.level_number if opened else None,
    )
