"""
Application configuration. Values come from environment variables —
no secrets hard-coded here. See docs/ARCHITECTURE.md §2/§7.
"""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # extra="ignore": .env carries informational vars (e.g. APP_ENV) that
    # this model doesn't declare as fields — pydantic-settings v2 defaults
    # to rejecting those as unrecognized instead of skipping them.
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    # Postgres connection string for the least-privilege app_backend role —
    # never a DB-owner connection (ARCHITECTURE.md §2).
    database_url: str = "postgresql://app_backend@localhost:5432/claim_settlement_dev"

    # JWT verification. In production this is set per deployment; never commit
    # a real secret here.
    jwt_secret: str = "CHANGE_ME_IN_ENV"
    jwt_algorithm: str = "HS256"

    # Connection pool sizing — kept modest for local dev, tune per deployment.
    db_pool_min_size: int = 2
    db_pool_max_size: int = 10


settings = Settings()
