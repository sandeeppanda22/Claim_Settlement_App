"""
Shared claim status-transition primitives.

Every claim status change in this API follows the same shape: lock the claim
row (SELECT ... FOR UPDATE), check it is in the status the action expects,
UPDATE it, and write a claim_event row recording the move. That shape used to
be implemented twice — privately in routes/payments.py and hand-inlined five
times in routes/approvals.py. It lives here now, so the invariant
"no status change without a claim_event" has exactly one implementation.

The approvals side needs three things the Finance side doesn't, hence the
extra keyword arguments on transition():
  - current_level_id is tri-state: leave the column alone (every Finance
    transition), set it to NULL (Rejected / Returned For Revision), or set it
    to the newly-opened level — which is itself legitimately None when the
    workflow ran out of levels and the claim is now Approved. A plain
    `current_level_id=None` default would collapse "leave alone" into "set
    NULL", so an _UNSET sentinel distinguishes them.
  - submitted_at is stamped on submit/resubmit only.
  - claim_event.comment carries the approver's note.

record_event() is exposed separately because decide() also writes an event
that records a decision WITHOUT changing claim.status (the level isn't
complete yet), and that must not go through transition().
"""
from uuid import UUID

import asyncpg
from fastapi import HTTPException, status

# Sentinel for "don't touch this column" — distinct from None, which means
# "set this column to NULL".
_UNSET: object = object()


async def get_claim_for_update(conn: asyncpg.Connection, claim_id: UUID) -> asyncpg.Record:
    """Locks the claim row for the rest of the transaction, or 404s."""
    row = await conn.fetchrow("SELECT * FROM claim WHERE id = $1 FOR UPDATE", claim_id)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found.")
    return row


def require_status(claim: asyncpg.Record, expected: str, detail: str | None = None) -> None:
    """
    409s unless the claim is in `expected`. Call sites that have a more
    specific sentence for the claimant pass their own `detail`; the default is
    the generic Finance-side wording.
    """
    if claim["status"] != expected:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=detail
            or f"Claim is '{claim['status']}', not {expected} — this action isn't valid here.",
        )


async def record_event(
    conn: asyncpg.Connection,
    claim_id: UUID,
    event_type: str,
    from_status: str,
    to_status: str,
    actor_id: int,
    comment: str | None = None,
) -> None:
    """
    Appends one claim_event row. `comment` is a nullable column, so passing
    None is identical to omitting it.
    """
    await conn.execute(
        """
        INSERT INTO claim_event
            (claim_id, event_type, from_status, to_status, actor_company_user_id, comment)
        VALUES ($1, $2, $3, $4, $5, $6)
        """,
        claim_id,
        event_type,
        from_status,
        to_status,
        actor_id,
        comment,
    )


async def transition(
    conn: asyncpg.Connection,
    claim_id: UUID,
    from_status: str,
    to_status: str,
    event_type: str,
    actor_id: int,
    current_level_id: object = _UNSET,
    set_submitted_at: bool = False,
    comment: str | None = None,
) -> None:
    """
    Moves the claim to `to_status` and records the move. The caller is
    expected to have locked the claim already (via get_claim_for_update).
    """
    set_clauses = ["status = $1", "updated_at = now()"]
    params: list[object] = [to_status]

    if current_level_id is not _UNSET:
        params.append(current_level_id)
        set_clauses.append(f"current_level_id = ${len(params)}")

    if set_submitted_at:
        set_clauses.append("submitted_at = now()")

    params.append(claim_id)
    await conn.execute(
        f"UPDATE claim SET {', '.join(set_clauses)} WHERE id = ${len(params)}",
        *params,
    )
    await record_event(conn, claim_id, event_type, from_status, to_status, actor_id, comment)
