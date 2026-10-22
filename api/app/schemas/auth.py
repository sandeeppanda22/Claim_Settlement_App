"""
Pydantic schemas for the auth slice — self-registration, login, and the
admin-side pending-user approval queue. See api/app/api/routes/auth.py.
"""
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, EmailStr, Field


class UserTypeIn(str, Enum):
    EMPLOYEE = "EMPLOYEE"
    NON_EMPLOYEE = "NON_EMPLOYEE"


class RegisterRequest(BaseModel):
    user_type: UserTypeIn
    full_name: str = Field(min_length=1, max_length=200)
    email: EmailStr
    password: str = Field(min_length=8, max_length=200)
    # Required for NON_EMPLOYEE (personal email has no company domain to
    # resolve from); ignored for EMPLOYEE, whose company is always resolved
    # from the email domain via company_email_domain.
    company_id: int | None = None


class RegisterResponse(BaseModel):
    """Confirms the account was created PENDING — no token issued yet."""

    company_user_id: int
    company_id: int
    approval_status: str


class LoginRequest(BaseModel):
    user_type: UserTypeIn
    email: EmailStr
    password: str
    # Same role as in RegisterRequest — required for NON_EMPLOYEE only.
    company_id: int | None = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class PendingUserOut(BaseModel):
    """One row in a company Admin's pending-registration queue."""

    company_user_id: int
    full_name: str
    email: str
    user_type: str
    created_at: datetime


class RoleOut(BaseModel):
    """One assignable role in the caller's company — for the approve dialog's
    role picker. RLS on `role` scopes this to the caller's company already."""

    id: int
    name: str
    description: str | None


class ApproveRequest(BaseModel):
    # Required: approval_status = APPROVED implies role_id IS NOT NULL
    # (company_user_approved_has_role CHECK constraint, 01_tenancy.sql).
    role_id: int


class RejectRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=2000)


class RejectedUserOut(BaseModel):
    """Returned after a reject — same shape as PendingUserOut plus the reason."""

    company_user_id: int
    full_name: str
    email: str
    user_type: str
    created_at: datetime
    rejection_reason: str | None
