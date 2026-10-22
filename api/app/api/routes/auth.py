"""
auth routes — self-registration, login, and the admin-side pending-user
approval queue.

register/login are public (no CurrentUser yet, so they cannot use
get_tenant_connection — that dependency requires an already-decoded JWT).
Both resolve company_id themselves and set app.current_company_id by hand
on a connection acquired directly from the pool, matching the same RLS
session-variable contract get_tenant_connection uses (database/ddl/
08_rls_policies.sql). The pending-user admin endpoints ARE tenant-scoped
and use get_tenant_connection + require_admin normally.

Company resolution:
  EMPLOYEE     -> company_email_domain, keyed by the email's domain part.
                  (company_email_domain is deliberately NOT RLS-protected —
                  see its comment in 01_tenancy.sql — so this lookup works
                  pre-auth.)
  NON_EMPLOYEE -> caller must supply company_id explicitly; a personal
                  email has no company domain to resolve from.

Per-company policy gate: company.allowed_claimant_types must contain the
requested user_type, or registration/login is rejected (BUSINESS_RULES.md
companion note in 01_tenancy.sql's allowed_claimant_types comment).
"""
import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.database import get_pool, get_tenant_connection
from app.core.security import (
    CurrentUser,
    create_access_token,
    get_current_user,
    hash_password,
    verify_password,
)
from app.schemas.auth import (
    ApproveRequest,
    LoginRequest,
    PendingUserOut,
    RegisterRequest,
    RegisterResponse,
    RejectedUserOut,
    RejectRequest,
    RoleOut,
    TokenResponse,
    UserTypeIn,
)

router = APIRouter(prefix="/auth", tags=["auth"])
admin_router = APIRouter(prefix="/auth/pending-users", tags=["auth"])

_GENERIC_LOGIN_ERROR = "Invalid email, password, or company."
_GENERIC_REGISTER_ERROR = "Unable to register with the supplied details."


def _email_domain(email: str) -> str:
    return email.rsplit("@", 1)[-1].lower()


async def _resolve_company_id(
    conn: asyncpg.Connection, user_type: UserTypeIn, email: str, company_id: int | None
) -> int:
    """
    Resolves which company this registration/login belongs to, pre-auth.
    Raises the same generic HTTPException for every failure mode (unknown
    domain, missing company_id, inactive company) so a caller can't probe
    for which part was wrong.
    """
    if user_type == UserTypeIn.EMPLOYEE:
        row = await conn.fetchrow(
            "SELECT company_id FROM company_email_domain WHERE domain = $1",
            _email_domain(email),
        )
        if row is None:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=_GENERIC_REGISTER_ERROR)
        resolved_company_id = row["company_id"]
    else:
        if company_id is None:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=_GENERIC_REGISTER_ERROR)
        resolved_company_id = company_id

    # company itself IS RLS-protected, so this lookup must set the session
    # variable to the candidate id first — reading nothing until it matches.
    await conn.execute(
        "SELECT set_config('app.current_company_id', $1, true)", str(resolved_company_id)
    )
    company_row = await conn.fetchrow(
        "SELECT id, is_active, allowed_claimant_types FROM company WHERE id = $1",
        resolved_company_id,
    )
    if company_row is None or not company_row["is_active"]:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=_GENERIC_REGISTER_ERROR)
    if user_type.value not in company_row["allowed_claimant_types"]:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=_GENERIC_REGISTER_ERROR)

    return resolved_company_id


@router.post("/register", response_model=RegisterResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest) -> RegisterResponse:
    pool = get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            company_id = await _resolve_company_id(
                conn, payload.user_type, payload.email, payload.company_id
            )

            existing = await conn.fetchrow(
                "SELECT id FROM company_user WHERE company_id = $1 AND email = $2",
                company_id,
                payload.email,
            )
            if existing is not None:
                raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=_GENERIC_REGISTER_ERROR)

            row = await conn.fetchrow(
                """
                INSERT INTO company_user (
                    company_id, full_name, email, auth_identity, password_hash,
                    user_type, approval_status
                )
                VALUES ($1, $2, $3, $3, $4, $5, 'PENDING')
                RETURNING id, company_id, approval_status
                """,
                company_id,
                payload.full_name,
                payload.email,
                hash_password(payload.password),
                payload.user_type.value,
            )
            return RegisterResponse(
                company_user_id=row["id"],
                company_id=row["company_id"],
                approval_status=row["approval_status"],
            )


@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest) -> TokenResponse:
    pool = get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            company_id = await _resolve_company_id(
                conn, payload.user_type, payload.email, payload.company_id
            )

            user_row = await conn.fetchrow(
                """
                SELECT id, role_id, password_hash, approval_status, is_active
                FROM company_user
                WHERE company_id = $1 AND email = $2
                """,
                company_id,
                payload.email,
            )
            if user_row is None or not verify_password(payload.password, user_row["password_hash"]):
                raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=_GENERIC_LOGIN_ERROR)
            if not user_row["is_active"]:
                raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=_GENERIC_LOGIN_ERROR)
            if user_row["approval_status"] != "APPROVED" or user_row["role_id"] is None:
                raise HTTPException(
                    status.HTTP_403_FORBIDDEN,
                    detail="Account is pending company approval and cannot log in yet.",
                )

            token = create_access_token(
                company_user_id=user_row["id"],
                company_id=company_id,
                role_id=user_row["role_id"],
                email=payload.email,
            )
            return TokenResponse(access_token=token)


async def require_admin(
    user: CurrentUser = Depends(get_current_user),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> CurrentUser:
    """
    Admin-only gate. role.name == 'Admin' is a documented convention
    (BUSINESS_RULES.md §2), not a reserved/system value — there is no
    permission-bitmask system yet, so this is a by-name check.
    """
    row = await conn.fetchrow("SELECT name FROM role WHERE id = $1", user.role_id)
    if row is None or row["name"] != "Admin":
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Admin role required.")
    return user


@router.get("/roles", response_model=list[RoleOut])
async def list_roles(
    admin: CurrentUser = Depends(require_admin),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> list[RoleOut]:
    """
    The assignable roles in the admin's own company, for the approve-user
    role picker. RLS on `role` (role_isolation policy) scopes this to the
    caller's company — no company_id filter needed here. Inactive roles are
    hidden so an admin can't assign a retired role.
    """
    rows = await conn.fetch(
        """
        SELECT id, name, description
        FROM role
        WHERE is_active = TRUE
        ORDER BY name
        """
    )
    return [RoleOut(**dict(row)) for row in rows]


@admin_router.get("", response_model=list[PendingUserOut])
async def list_pending_users(
    admin: CurrentUser = Depends(require_admin),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> list[PendingUserOut]:
    rows = await conn.fetch(
        """
        SELECT id AS company_user_id, full_name, email, user_type, created_at
        FROM company_user
        WHERE approval_status = 'PENDING'
        ORDER BY created_at
        """
    )
    return [PendingUserOut(**dict(row)) for row in rows]


@admin_router.post("/{company_user_id}/approve", response_model=PendingUserOut)
async def approve_pending_user(
    company_user_id: int,
    payload: ApproveRequest,
    admin: CurrentUser = Depends(require_admin),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> PendingUserOut:
    # role_id must belong to this same company — RLS on `role` guarantees
    # that already (role_isolation policy), so no extra check is needed.
    role_row = await conn.fetchrow("SELECT id FROM role WHERE id = $1", payload.role_id)
    if role_row is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Role not found for this company.")

    row = await conn.fetchrow(
        """
        UPDATE company_user
        SET approval_status = 'APPROVED', role_id = $1, updated_at = now()
        WHERE id = $2 AND approval_status = 'PENDING'
        RETURNING id AS company_user_id, full_name, email, user_type, created_at
        """,
        payload.role_id,
        company_user_id,
    )
    if row is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="No pending registration found with that id."
        )
    return PendingUserOut(**dict(row))


@admin_router.post("/{company_user_id}/reject", response_model=RejectedUserOut)
async def reject_pending_user(
    company_user_id: int,
    payload: RejectRequest,
    admin: CurrentUser = Depends(require_admin),
    conn: asyncpg.Connection = Depends(get_tenant_connection),
) -> RejectedUserOut:
    row = await conn.fetchrow(
        """
        UPDATE company_user
        SET approval_status = 'REJECTED', is_active = FALSE,
            rejection_reason = $1, updated_at = now()
        WHERE id = $2 AND approval_status = 'PENDING'
        RETURNING id AS company_user_id, full_name, email, user_type, created_at, rejection_reason
        """,
        payload.reason,
        company_user_id,
    )
    if row is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="No pending registration found with that id."
        )
    return RejectedUserOut(**dict(row))
