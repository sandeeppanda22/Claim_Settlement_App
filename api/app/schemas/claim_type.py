"""
Pydantic schemas for claim_type / claim_type_field.
Mirrors database/ddl/03_claim_type.sql — field names match column names
1:1 so the DB row -> model mapping stays mechanical and auditable.
"""
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

FieldDataType = Literal["text", "number", "date", "boolean", "select"]


class ClaimTypeFieldOut(BaseModel):
    id: int
    field_key: str
    label: str
    data_type: FieldDataType
    is_required: bool
    display_order: int
    validation_rule: dict[str, Any] | None = None
    policy_limit_amount: float | None = None


class ClaimTypeFieldCreate(BaseModel):
    field_key: str = Field(min_length=1, max_length=100)
    label: str = Field(min_length=1, max_length=200)
    data_type: FieldDataType
    is_required: bool = False
    display_order: int = 0
    validation_rule: dict[str, Any] | None = None
    policy_limit_amount: float | None = Field(default=None, ge=0)


class ClaimTypeOut(BaseModel):
    id: int
    company_id: int
    name: str
    code: str
    description: str | None
    is_active: bool
    created_at: datetime
    fields: list[ClaimTypeFieldOut] = []


class ClaimTypeCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    code: str = Field(min_length=1, max_length=50)
    description: str | None = None
