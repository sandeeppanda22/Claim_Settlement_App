"""
Pydantic schemas for claim / claim_line_item.
Mirrors database/ddl/05_claim.sql. The `id` fields are UUIDs per
ARCHITECTURE.md §8 — client-originable, offline-draftable entities.
"""
from datetime import date, datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field

ClaimStatus = str  # mirrors the claim_status enum in 00_extensions.sql


class ClaimLineItemCreate(BaseModel):
    line_number: int = Field(gt=0)
    expense_date: date
    category: str = Field(min_length=1, max_length=200)
    description: str | None = None
    amount: float = Field(gt=0)
    field_values: dict[str, Any] | None = None


class ClaimLineItemOut(ClaimLineItemCreate):
    id: UUID
    claim_id: UUID
    created_at: datetime


class ClaimCreate(BaseModel):
    """
    Creates a Draft claim. Matches both the online path (server mints the
    UUID) and the offline-sync path (client already minted the UUID while
    drafting with no connectivity — see ARCHITECTURE.md §1). When `id` is
    omitted, the server generates one.
    """

    id: UUID | None = None
    claim_type_id: int
    title: str = Field(min_length=1, max_length=300)
    description: str | None = None
    claim_currency_code: str = Field(min_length=3, max_length=3)
    line_items: list[ClaimLineItemCreate] = Field(default_factory=list)


class ClaimOut(BaseModel):
    id: UUID
    company_id: int
    claim_type_id: int
    company_user_id: int
    status: ClaimStatus
    title: str
    description: str | None
    claim_currency_code: str
    fx_rate_to_base: float | None
    base_currency_code: str | None
    total_amount: float
    current_level_id: int | None
    submitted_at: datetime | None
    created_at: datetime
    line_items: list[ClaimLineItemOut] = []
