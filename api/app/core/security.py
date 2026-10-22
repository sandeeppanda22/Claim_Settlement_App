"""
JWT issuance/verification, password hashing, and the CurrentUser/admin
dependencies every route depends on. See ARCHITECTURE.md §2: JWT-based,
scoped per company. Registration/login business logic itself lives in
app/api/routes/auth.py — this module only owns the shared primitives.
"""
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.config import settings

_bearer_scheme = HTTPBearer()

# bcrypt — never store or log a plaintext password (01_tenancy.sql comment
# on company_user.password_hash).
_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# A role_id of NULL means "approved but not yet role-assigned" is impossible
# by the company_user_approved_has_role CHECK constraint, but a PENDING
# self-registered user legitimately has role_id = NULL — the token for such
# a user is never issued (auth.py only issues a token on successful login,
# which requires approval_status = APPROVED). This sentinel documents that
# invariant rather than enforcing it here.
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 12


def hash_password(plain_password: str) -> str:
    return _pwd_context.hash(plain_password)


def verify_password(plain_password: str, password_hash: str) -> bool:
    return _pwd_context.verify(plain_password, password_hash)


def create_access_token(*, company_user_id: int, company_id: int, role_id: int, email: str) -> str:
    """
    Issues a JWT for an already-APPROVED company_user. Claim names (sub,
    company_id, role_id, email) must match what get_current_user() decodes.
    """
    expire_at = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": str(company_user_id),
        "company_id": str(company_id),
        "role_id": str(role_id),
        "email": email,
        "exp": expire_at,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


@dataclass(frozen=True)
class CurrentUser:
    company_user_id: int
    company_id: int
    role_id: int
    email: str


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
) -> CurrentUser:
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
        )
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token.",
        ) from exc

    try:
        return CurrentUser(
            company_user_id=int(payload["sub"]),
            company_id=int(payload["company_id"]),
            role_id=int(payload["role_id"]),
            email=payload["email"],
        )
    except (KeyError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token payload missing required claims (sub, company_id, role_id, email).",
        ) from exc


# The admin-only dependency (checks role.name == 'Admin' for the caller)
# lives in app/api/routes/auth.py as `require_admin` — it needs the
# RLS-scoped tenant connection (get_tenant_connection), which itself depends
# on get_current_user, so defining it here would create a circular import
# between security.py and database.py. Not duplicated; import from auth.py.
