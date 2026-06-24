"""
Genesis Global CMS — Pydantic v2 Schemas for Auth Domain

All request/response bodies use strict validation.
Passwords are NEVER included in response schemas.
"""
import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.auth.models import UserRole


# ── Request Schemas ────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    """POST /api/v1/auth/login"""

    email: EmailStr
    password: str = Field(min_length=1, max_length=128)

    model_config = {"str_strip_whitespace": True}


class RefreshTokenRequest(BaseModel):
    """POST /api/v1/auth/refresh"""

    refresh_token: str = Field(min_length=10)


class ForgotPasswordRequest(BaseModel):
    """POST /api/v1/auth/forgot-password"""

    email: EmailStr

    model_config = {"str_strip_whitespace": True}


class ResetPasswordRequest(BaseModel):
    """POST /api/v1/auth/reset-password"""

    token: str = Field(min_length=10)
    new_password: str = Field(
        min_length=8,
        max_length=128,
        description="Must be at least 8 characters",
    )

    @field_validator("new_password")
    @classmethod
    def validate_password_strength(cls, v: str) -> str:
        """Enforce basic password strength rules."""
        if not any(c.isupper() for c in v):
            raise ValueError("Password must contain at least one uppercase letter.")
        if not any(c.islower() for c in v):
            raise ValueError("Password must contain at least one lowercase letter.")
        if not any(c.isdigit() for c in v):
            raise ValueError("Password must contain at least one digit.")
        return v


# ── Response Schemas ───────────────────────────────────────────────────────────

class ScopeSchema(BaseModel):
    """JWT scope payload — lists of entity UUIDs the user is authorised for."""

    departments: list[str] = Field(default_factory=list)
    teams: list[str] = Field(default_factory=list)
    groups: list[str] = Field(default_factory=list)


class UserSummary(BaseModel):
    """Minimal user info embedded in token response."""

    id: uuid.UUID
    email: EmailStr
    role: UserRole
    name: Optional[str] = None
    member_id: Optional[uuid.UUID] = None

    model_config = {"from_attributes": True}


class UserDetail(BaseModel):
    """Full user info returned from GET /api/v1/auth/me"""

    id: uuid.UUID
    email: EmailStr
    role: UserRole
    name: Optional[str] = None
    member_id: Optional[uuid.UUID] = None
    scope: ScopeSchema
    is_active: bool
    last_login_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class TokenResponse(BaseModel):
    """Login response payload (nested under success envelope)."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserSummary


class AccessTokenResponse(BaseModel):
    """Refresh response payload."""

    access_token: str
    token_type: str = "bearer"


# ── Internal (not exposed via API) ────────────────────────────────────────────

class JWTPayload(BaseModel):
    """Internal model for decoded JWT payload validation."""

    sub: str                                  # app_user UUID
    email: Optional[str] = None
    role: Optional[str] = None
    scope: Optional[ScopeSchema] = None
    iat: Optional[int] = None
    exp: Optional[int] = None
    type: Optional[str] = None
    jti: Optional[str] = None

    model_config = {"extra": "allow"}
