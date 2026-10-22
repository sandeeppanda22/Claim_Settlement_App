"""
Database access layer. Owns the asyncpg connection pool and the one place
RLS tenant isolation gets wired in — every request-scoped connection sets
`app.current_company_id` for the duration of its transaction, matching the
RLS policies in database/ddl/08_rls_policies.sql. See ARCHITECTURE.md §4.

No ORM — hand-written SQL stays the source of truth (ARCHITECTURE.md §2).
"""
from collections.abc import AsyncIterator

import asyncpg
from fastapi import Depends

from app.core.config import settings
from app.core.security import CurrentUser, get_current_user

_pool: asyncpg.Pool | None = None


async def init_pool() -> None:
    global _pool
    _pool = await asyncpg.create_pool(
        dsn=settings.database_url,
        min_size=settings.db_pool_min_size,
        max_size=settings.db_pool_max_size,
    )


async def close_pool() -> None:
    if _pool is not None:
        await _pool.close()


def get_pool() -> asyncpg.Pool:
    if _pool is None:
        raise RuntimeError("Connection pool not initialized — call init_pool() at startup.")
    return _pool


async def get_tenant_connection(
    user: CurrentUser = Depends(get_current_user),
) -> AsyncIterator[asyncpg.Connection]:
    """
    Request-scoped connection, pinned to the caller's company via RLS.

    SET LOCAL scopes the session variable to the current transaction only —
    it never leaks across pooled connections reused by other requests.
    """
    pool = get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "SELECT set_config('app.current_company_id', $1, true)",
                str(user.company_id),
            )
            yield conn
