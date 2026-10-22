"""
FastAPI application entrypoint. Wires up the connection pool lifecycle and
mounts each vertical slice's router. See docs/ARCHITECTURE.md §2, §6.
"""
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.routes import approvals, auth, claim_types, claims, health, payments
from app.core.database import close_pool, init_pool


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_pool()
    yield
    await close_pool()


app = FastAPI(title="Claim Settlement App API", version="0.1.0", lifespan=lifespan)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(auth.admin_router)
app.include_router(claim_types.router)
app.include_router(claims.router)
app.include_router(approvals.router)
app.include_router(approvals.queue_router)
app.include_router(payments.router)
