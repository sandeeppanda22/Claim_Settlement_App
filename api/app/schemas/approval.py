"""
Pydantic schemas for the approval engine — the claim-facing side
(approval_step) rather than the workflow-configuration side (that's
claim_type.py's sibling, a future admin-config slice).
"""
from datetime import datetime
from enum import Enum
from uuid import UUID

from pydantic import BaseModel, Field


class ApprovalDecisionIn(str, Enum):
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"
    RETURNED_FOR_REVISION = "RETURNED_FOR_REVISION"


class DecideRequest(BaseModel):
    decision: ApprovalDecisionIn
    comment: str | None = Field(default=None, max_length=2000)


class ApprovalStepOut(BaseModel):
    id: int
    claim_id: UUID
    level_id: int
    level_number: int
    approver_user_id: int | None
    decision: str
    comment: str | None
    decided_at: datetime | None
    created_at: datetime


class ClaimApprovalStateOut(BaseModel):
    """Returned after submit/decide — the claim's resulting workflow state."""

    claim_id: UUID
    status: str
    current_level_id: int | None
    current_level_number: int | None


class PendingApprovalOut(BaseModel):
    """One row in the current user's approval queue — a claim sitting at a
    level where this user has an un-acted PENDING approval_step."""

    step_id: int
    claim_id: UUID
    claim_title: str
    claim_type_id: int
    total_amount: float
    claim_currency_code: str
    level_id: int
    level_number: int
    submitted_at: datetime | None
