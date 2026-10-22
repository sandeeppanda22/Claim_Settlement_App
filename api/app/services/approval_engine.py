"""
Approval engine — workflow resolution and level progression.
Pure logic over an existing asyncpg connection/transaction; no HTTP concerns
here (those live in api/routes/approvals.py). See BUSINESS_RULES.md §4.
"""
from dataclasses import dataclass
from uuid import UUID

import asyncpg
from fastapi import HTTPException, status


@dataclass(frozen=True)
class Level:
    id: int
    level_number: int
    completion_rule: str  # 'ANY' | 'ALL'
    min_amount: float | None
    max_amount: float | None


async def resolve_workflow_id(
    conn: asyncpg.Connection, company_id: int, claim_type_id: int
) -> tuple[int, bool]:
    """
    Dedicated workflow for this claim_type, else the company-wide fallback
    (claim_type_id IS NULL). Returns (workflow_id, record_skipped_levels).
    Raises 422 if neither exists — a configuration gap, not a silent default
    (BUSINESS_RULES.md §4).
    """
    row = await conn.fetchrow(
        """
        SELECT id, record_skipped_levels
        FROM approval_workflow
        WHERE company_id = $1 AND is_active
          AND (claim_type_id = $2 OR claim_type_id IS NULL)
        ORDER BY claim_type_id NULLS LAST
        LIMIT 1
        """,
        company_id,
        claim_type_id,
    )
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                "No approval_workflow configured for this claim_type and no "
                "company-wide fallback exists. Admin must configure one before "
                "claims of this type can be submitted."
            ),
        )
    return row["id"], row["record_skipped_levels"]


async def get_ordered_levels(conn: asyncpg.Connection, workflow_id: int) -> list[Level]:
    rows = await conn.fetch(
        """
        SELECT id, level_number, completion_rule, min_amount, max_amount
        FROM approval_level
        WHERE workflow_id = $1
        ORDER BY level_number
        """,
        workflow_id,
    )
    return [Level(**dict(row)) for row in rows]


def level_applies(level: Level, claim_total: float) -> bool:
    if level.min_amount is not None and claim_total < float(level.min_amount):
        return False
    if level.max_amount is not None and claim_total >= float(level.max_amount):
        return False
    return True


async def eligible_user_ids(conn: asyncpg.Connection, level_id: int) -> list[int]:
    """Expand ROLE members to every active user holding that role; USER members as-is."""
    rows = await conn.fetch(
        """
        SELECT DISTINCT cu.id
        FROM approver_set_member m
        LEFT JOIN company_user cu
            ON (m.member_type = 'USER' AND cu.id = m.company_user_id)
            OR (m.member_type = 'ROLE' AND cu.role_id = m.role_id AND cu.is_active)
        WHERE m.level_id = $1 AND cu.id IS NOT NULL
        """,
        level_id,
    )
    return [row["id"] for row in rows]


async def record_skip(conn: asyncpg.Connection, claim_id: UUID, level_id: int) -> None:
    await conn.execute(
        """
        INSERT INTO approval_step (claim_id, level_id, approver_user_id, decision, decided_at)
        VALUES ($1, $2, NULL, 'SKIPPED', now())
        """,
        claim_id,
        level_id,
    )


async def open_level(
    conn: asyncpg.Connection, claim_id: UUID, level_id: int, approver_ids: list[int]
) -> None:
    for user_id in approver_ids:
        await conn.execute(
            """
            INSERT INTO approval_step (claim_id, level_id, approver_user_id, decision)
            VALUES ($1, $2, $3, 'PENDING')
            """,
            claim_id,
            level_id,
            user_id,
        )


async def level_outcome(
    conn: asyncpg.Connection, claim_id: UUID, level_id: int, completion_rule: str
) -> str:
    """
    'REJECTED' if any approver at this level rejected; 'RETURNED_FOR_REVISION'
    if any approver sent it back (checked after REJECTED — a reject is more
    decisive than a return if, oddly, both happened); 'CLEARED' if the
    completion_rule is satisfied; otherwise 'PENDING' (still waiting).
    Both REJECTED and RETURNED_FOR_REVISION are single-approver decisive
    outcomes regardless of ANY/ALL — one approver sending a claim back ends
    that level immediately, the same way one rejection does.
    ANY clears on the first APPROVED; ALL needs every row APPROVED.
    """
    rows = await conn.fetch(
        "SELECT decision FROM approval_step WHERE claim_id = $1 AND level_id = $2",
        claim_id,
        level_id,
    )
    decisions = [row["decision"] for row in rows]
    if "REJECTED" in decisions:
        return "REJECTED"
    if "RETURNED_FOR_REVISION" in decisions:
        return "RETURNED_FOR_REVISION"
    if completion_rule == "ANY" and "APPROVED" in decisions:
        return "CLEARED"
    if completion_rule == "ALL" and decisions and all(d == "APPROVED" for d in decisions):
        return "CLEARED"
    return "PENDING"


async def mark_remaining_pending_as_skipped(
    conn: asyncpg.Connection, claim_id: UUID, level_id: int
) -> None:
    """Once ANY clears a level, the other approvers never got to act — not a
    decision they made, so PENDING (not APPROVED/REJECTED) would misrepresent
    it; SKIPPED is reused here for "the level closed before this row mattered"."""
    await conn.execute(
        """
        UPDATE approval_step
        SET decision = 'SKIPPED', decided_at = now()
        WHERE claim_id = $1 AND level_id = $2 AND decision = 'PENDING'
        """,
        claim_id,
        level_id,
    )


async def advance(
    conn: asyncpg.Connection,
    claim_id: UUID,
    claim_total: float,
    levels: list[Level],
    record_skipped_levels: bool,
    start_index: int,
) -> Level | None:
    """
    Walks levels[start_index:], skipping (recorded or silent, per policy) any
    level the claim's amount doesn't qualify for, and opens the first one
    that does. Returns the opened Level, or None if every remaining level
    was skipped (claim is fully approved).
    """
    for level in levels[start_index:]:
        if level_applies(level, claim_total):
            approver_ids = await eligible_user_ids(conn, level.id)
            if not approver_ids:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"approval_level {level.id} has no resolvable approvers "
                    "(role has no active members, or approver_set_member is empty).",
                )
            await open_level(conn, claim_id, level.id, approver_ids)
            return level
        if record_skipped_levels:
            await record_skip(conn, claim_id, level.id)
    return None
