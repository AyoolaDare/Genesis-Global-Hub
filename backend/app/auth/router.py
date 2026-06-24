"""
Genesis Global CMS — Auth Router

Endpoints:
    POST   /api/v1/auth/login
    POST   /api/v1/auth/refresh
    POST   /api/v1/auth/logout
    POST   /api/v1/auth/forgot-password
    POST   /api/v1/auth/reset-password
    GET    /api/v1/auth/me
"""
import logging
from typing import Optional

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.auth.dependencies import get_current_user, oauth2_scheme
from app.auth.models import AppUser
from app.auth.schemas import (
    ForgotPasswordRequest,
    LoginRequest,
    RefreshTokenRequest,
    ResetPasswordRequest,
)
from app.auth.service import (
    get_user_profile,
    login,
    logout,
    refresh_access_token,
    request_password_reset,
    reset_password,
)
from app.core.responses import success_response
from app.database import get_db

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["Authentication"])


def _get_client_ip(request: Request) -> Optional[str]:
    """
    Extract the real client IP, honouring X-Forwarded-For from reverse proxies.
    Returns the first IP from the header if present, otherwise the direct connection IP.
    """
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    if request.client:
        return request.client.host
    return None


def _get_user_agent(request: Request) -> Optional[str]:
    return request.headers.get("User-Agent")


# ── POST /api/v1/auth/login ───────────────────────────────────────────────────

@router.post("/login", summary="Authenticate and obtain JWT tokens")
async def auth_login(
    body: LoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Authenticate with email + password.

    - Validates against Supabase Auth
    - Builds scope (departments/teams/groups)
    - Returns signed JWT access + refresh tokens
    - Rate-limited: 5 attempts per 15 minutes per IP
    """
    token_data = await login(
        email=body.email,
        password=body.password,
        db=db,
        ip_address=_get_client_ip(request),
        user_agent=_get_user_agent(request),
    )
    return success_response(data=token_data, message="Login successful.")


# ── POST /api/v1/auth/refresh ─────────────────────────────────────────────────

@router.post("/refresh", summary="Refresh access token")
async def auth_refresh(
    body: RefreshTokenRequest,
    db: Session = Depends(get_db),
):
    """
    Exchange a valid refresh token for a new access token.

    The refresh token must be a valid, non-expired, non-blacklisted JWT
    issued by this service.
    """
    token_data = await refresh_access_token(
        refresh_token=body.refresh_token,
        db=db,
    )
    return success_response(data=token_data, message="Token refreshed.")


# ── POST /api/v1/auth/logout ──────────────────────────────────────────────────

@router.post("/logout", summary="Invalidate current session")
async def auth_logout(
    request: Request,
    current_user: AppUser = Depends(get_current_user),
    token: Optional[str] = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
):
    """
    Blacklist the current access token in Redis.

    After logout, the token cannot be used even if it has not expired.
    """
    await logout(
        access_token=token or "",
        current_user=current_user,
        db=db,
        ip_address=_get_client_ip(request),
        user_agent=_get_user_agent(request),
    )
    return success_response(data=None, message="Logged out successfully.")


# ── POST /api/v1/auth/forgot-password ────────────────────────────────────────

@router.post("/forgot-password", summary="Request a password reset email")
async def auth_forgot_password(body: ForgotPasswordRequest):
    """
    Trigger a password reset email via Supabase.

    SECURITY: Always returns success regardless of whether the email exists
    to prevent user enumeration attacks.
    """
    await request_password_reset(email=body.email)
    return success_response(
        data=None,
        message="If an account with that email exists, a password reset link has been sent.",
    )


# ── POST /api/v1/auth/reset-password ─────────────────────────────────────────

@router.post("/reset-password", summary="Apply a new password using reset token")
async def auth_reset_password(body: ResetPasswordRequest):
    """
    Apply a new password using the token from the Supabase reset email.

    The ``token`` field is the Supabase recovery access token extracted
    from the reset link (e.g., ``/auth/callback?access_token=...``).
    """
    await reset_password(
        token=body.token,
        new_password=body.new_password,
    )
    return success_response(
        data=None,
        message="Password updated successfully. Please log in with your new password.",
    )


# ── GET /api/v1/auth/me ───────────────────────────────────────────────────────

@router.get("/me", summary="Get current user profile")
async def auth_me(
    request: Request,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Return the authenticated user's profile including scope information.

    The scope embedded in the JWT is returned directly (no DB re-query).
    """
    profile = await get_user_profile(
        user=current_user,
        db=db,
        request=request,
    )
    return success_response(data=profile, message="Profile retrieved.")
