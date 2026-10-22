"""
Pydantic schemas for the Finance/payment side — reimbursement_payment and
the claim-level finance-review/close transitions. Mirrors
database/ddl/07_payment.sql. See BUSINESS_RULES.md §3, §5.
"""
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class PaymentCreate(BaseModel):
    payout_currency_code: str = Field(min_length=3, max_length=3)
    payout_amount: float = Field(gt=0)
    payout_fx_rate: float | None = None
    method: str = Field(min_length=1, max_length=50)
    reference_number: str | None = None


class PaymentOut(BaseModel):
    id: UUID
    claim_id: UUID
    status: str
    payout_currency_code: str
    payout_amount: float
    payout_fx_rate: float | None
    method: str
    reference_number: str | None
    initiated_by_user_id: int
    initiated_at: datetime
    paid_at: datetime | None
    created_at: datetime


class ClaimStatusOut(BaseModel):
    """A plain claim-status response for transitions that don't involve an
    approval level (finance-review start, close) — ClaimApprovalStateOut's
    current_level_id/number fields don't apply on the Finance side."""

    claim_id: UUID
    status: str
