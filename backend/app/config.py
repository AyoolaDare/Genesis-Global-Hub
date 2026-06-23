"""
Genesis Global CMS — Application Settings
Uses pydantic-settings for environment variable management.
All secrets must be provided via environment variables or .env file.
"""
from functools import lru_cache
from typing import List

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    # ── Application ────────────────────────────────────────────────────────────
    APP_NAME: str = "Genesis Global CMS"
    APP_VERSION: str = "1.0.0"
    ENVIRONMENT: str = Field(default="development", pattern="^(development|staging|production)$")

    # ── Database ───────────────────────────────────────────────────────────────
    DATABASE_URL: str = "postgresql+psycopg2://postgres:postgres@localhost:5432/genesis_global_dev"

    # ── Supabase ───────────────────────────────────────────────────────────────
    SUPABASE_URL: str = "http://localhost:54321"
    SUPABASE_SERVICE_KEY: str = ""   # service_role key — never exposed to frontend
    SUPABASE_ANON_KEY: str = ""      # anon key — safe for frontend

    # ── JWT ────────────────────────────────────────────────────────────────────
    JWT_SECRET_KEY: str = Field(
        default="development-only-jwt-secret-change-me",
        min_length=32,
    )
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_HOURS: int = 24
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # ── Redis (Upstash) ────────────────────────────────────────────────────────
    UPSTASH_REDIS_URL: str = "redis://localhost:6379/0"

    # ── Flutterwave ────────────────────────────────────────────────────────────
    FLUTTERWAVE_SECRET_KEY: str = ""
    FLUTTERWAVE_ENCRYPTION_KEY: str = ""

    # ── Termii (SMS) ──────────────────────────────────────────────────────────
    TERMII_API_KEY: str = ""
    TERMII_SENDER_ID: str = "GenesisGlobal"

    # ── SendGrid ──────────────────────────────────────────────────────────────
    SENDGRID_API_KEY: str = ""
    FROM_EMAIL: str = "noreply@genesisglob.al"

    # ── CORS ──────────────────────────────────────────────────────────────────
    # Comma-separated list of allowed origins
    ALLOWED_ORIGINS: str = ""

    # ── Render (internal service routing) ─────────────────────────────────────
    RENDER_INTERNAL_URL: str = ""

    # ── Rate Limiting ─────────────────────────────────────────────────────────
    RATE_LIMIT_AUTH_ATTEMPTS: int = 5
    RATE_LIMIT_AUTH_WINDOW_SECONDS: int = 900  # 15 minutes

    @field_validator("JWT_SECRET_KEY")
    @classmethod
    def validate_jwt_secret(cls, v: str) -> str:
        if len(v) < 32:
            raise ValueError("JWT_SECRET_KEY must be at least 32 characters")
        return v

    @model_validator(mode="after")
    def require_external_config_outside_development(self) -> "Settings":
        """Require real external service config for staging/production."""
        if self.is_development:
            return self

        required_fields = (
            "DATABASE_URL",
            "SUPABASE_URL",
            "SUPABASE_SERVICE_KEY",
            "SUPABASE_ANON_KEY",
            "JWT_SECRET_KEY",
            "UPSTASH_REDIS_URL",
            "FLUTTERWAVE_SECRET_KEY",
            "FLUTTERWAVE_ENCRYPTION_KEY",
            "TERMII_API_KEY",
            "SENDGRID_API_KEY",
        )
        missing = [
            field
            for field in required_fields
            if not str(getattr(self, field, "")).strip()
        ]
        if missing:
            raise ValueError(
                f"Missing required {self.ENVIRONMENT} setting(s): {', '.join(missing)}"
            )

        if self.JWT_SECRET_KEY == "development-only-jwt-secret-change-me":
            raise ValueError("JWT_SECRET_KEY must be changed outside development")

        return self

    @property
    def allowed_origins_list(self) -> List[str]:
        """Return ALLOWED_ORIGINS as a Python list."""
        if not self.ALLOWED_ORIGINS:
            return []
        return [origin.strip() for origin in self.ALLOWED_ORIGINS.split(",") if origin.strip()]

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT == "production"

    @property
    def is_development(self) -> bool:
        return self.ENVIRONMENT == "development"


@lru_cache()
def get_settings() -> Settings:
    """Return cached settings instance. Call once per process."""
    return Settings()


settings = get_settings()
