"""
claim_type routes — list and create. Field (claim_type_field) management
is a separate, smaller slice to add once this lands; omitted here rather
than stubbed with guessed behavior.
"""
import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.database import get_tenant_connection
from app.core.security import CurrentUser, get_current_user
from app.schemas.claim_type import ClaimTypeCreate, ClaimTypeFieldOut, ClaimTypeOut

router = APIRouter(prefix="/claim-types", tags=["claim-types"])


async def _load_fields(conn: asyncpg.Connection, claim_type_id: int) -> list[ClaimTypeFieldOut]:
    rows = await conn.fetch(
        """
        SELECT id, field_key, label, data_type, is_required, display_order,
               validation_rule, policy_limit_amount
        FROM claim_type_field
        WHERE claim_type_id = $1 AND is_active
        ORDER BY display_order, id
        """,
        claim_type_id,
    )
    return [ClaimTypeFieldOut(**dict(row)) for row in rows]


@router.get("", response_model=list[ClaimTypeOut])
async def list_claim_types(
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> list[ClaimTypeOut]:
    rows = await conn.fetch(
        """
        SELECT id, company_id, name, code, description, is_active, created_at
        FROM claim_type
        WHERE is_active
        ORDER BY name
        """
    )
    results = []
    for row in rows:
        fields = await _load_fields(conn, row["id"])
        results.append(ClaimTypeOut(**dict(row), fields=fields))
    return results


@router.post("", response_model=ClaimTypeOut, status_code=status.HTTP_201_CREATED)
async def create_claim_type(
    payload: ClaimTypeCreate,
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> ClaimTypeOut:
    existing = await conn.fetchrow(
        "SELECT 1 FROM claim_type WHERE company_id = $1 AND code = $2",
        user.company_id,
        payload.code,
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"claim_type code '{payload.code}' already exists for this company.",
        )

    row = await conn.fetchrow(
        """
        INSERT INTO claim_type (company_id, name, code, description)
        VALUES ($1, $2, $3, $4)
        RETURNING id, company_id, name, code, description, is_active, created_at
        """,
        user.company_id,
        payload.name,
        payload.code,
        payload.description,
    )
    return ClaimTypeOut(**dict(row), fields=[])
