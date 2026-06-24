"""
Genesis Global CMS — Auth Business Logic Service

Handles all authentication operations:
  - Login (Supabase Auth + local DB lookup + JWT creation)
  - Token refresh
  - Logout (Redis blacklist)
  - Password reset (Supabase reset email)
  - Audit log writes
"""
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

import httpx
from sqlalchemy import update
from sqlalchemy.orm import Session

from app.auth.models import AppUser, AuditLog, AuditAction
from app.config import settings
from app.core.exceptions import (
    AuthenticationFailed,
    ServiceUnavailable,
)
from app.core.security import (
    blacklist_token,
    build_user_scope,
    check_auth_rate_limit,
    clear_auth_rate_limit,
    create_access_token,
    create_refresh_token,
    record_failed_auth,
    verify_token,
)

logger = logging.getLogger(__name__)


# ── Supabase Auth Helpers ──────────────────────────────────────────────────────

async def _supabase_sign_in(email: str, password: str) -> dict:
    """
    Authenticate against Supabase Auth REST API.

    Returns:
        Supabase session dict containing ``access_token``, ``refresh_token``,
        and nested ``user`` object.

    Raises:
        AuthenticationFailed: Invalid credentials.
        ServiceUnavailable:   Supabase is unreachable.
    """
    url = f"{settings.SUPABASE_URL}/auth/v1/token?grant_type=password"
    headers = {
        "apikey": settings.SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
    }
    payload = {"email": email, "password": password}

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(url, json=payload, headers=headers)
    except httpx.RequestError as exc:
        logger.error("Supabase Auth request failed: %s", exc)
        raise ServiceUnavailable(message="Authentication service is temporarily unavailable.")

    if response.status_code == 400:
        # Supabase returns 400 for invalid credentials
        raise AuthenticationFailed(message="Invalid email or password.")

    if response.status_code != 200:
        logger.error(
            "Supabase Auth returned unexpected status %d: %s",
            response.status_code,
            response.text,
        )
        raise ServiceUnavailable(message="Authentication service returned an unexpected error.")

    return response.json()


async def _supabase_refresh_token(refresh_token: str) -> dict:
    """Exchange a Supabase refresh token for a new session."""
    url = f"{settings.SUPABASE_URL}/auth/v1/token?grant_type=refresh_token"
    headers = {
        "apikey": settings.SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
    }
    payload = {"refresh_token": refresh_token}

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(url, json=payload, headers=headers)
    except httpx.RequestError as exc:
        logger.error("Supabase refresh request failed: %s", exc)
        raise ServiceUnavailable(message="Authentication service is temporarily unavailable.")

    if response.status_code != 200:
        raise AuthenticationFailed(message="Refresh token is invalid or expired.")

    return response.json()


async def _supabase_request_password_reset(email: str) -> None:
    """Trigger Supabase to send a password reset email."""
    url = f"{settings.SUPABASE_URL}/auth/v1/recover"
    headers = {
        "apikey": settings.SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
    }
    payload = {"email": email}

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            # Fire-and-forget: we always return 200 to caller regardless
            await client.post(url, json=payload, headers=headers)
    except httpx.RequestError as exc:
        logger.warning("Supabase password reset request failed silently: %s", exc)


async def _supabase_update_password(access_token: str, new_password: str) -> None:
    """
    Update a user's password using a Supabase recovery access token.

    Args:
        access_token:  The token from the password reset link.
        new_password:  The new plaintext password.
    """
    url = f"{settings.SUPABASE_URL}/auth/v1/user"
    headers = {
        "apikey": settings.SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    payload = {"password": new_password}

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.put(url, json=payload, headers=headers)
    except httpx.RequestError as exc:
        logger.error("Supabase update password request failed: %s", exc)
        raise ServiceUnavailable(message="Password update service is temporarily unavailable.")

    if response.status_code != 200:
        raise AuthenticationFailed(
            message="Password reset token is invalid or expired. Please request a new one."
        )


# ── Audit Log Helper ───────────────────────────────────────────────────────────

def write_audit_log(
    db: Session,
    *,
    user_id: Optional[uuid.UUID],
    action: AuditAction,
    resource_type: Optional[str] = None,
    resource_id: Optional[str] = None,
    old_values: Optional[dict] = None,
    new_values: Optional[dict] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> None:
    """
    Write an entry to the immutable audit_logs table.

    This is a synchronous write — the DB trigger ensures immutability.
    For non-blocking audit logging in middleware, use an async task queue.
    """
    try:
        log = AuditLog(
            user_id=user_id,
            action=action,
            resource_type=resource_type,
            resource_id=str(resource_id) if resource_id else None,
            old_values=old_values,
            new_values=new_values,
            ip_address=ip_address,
            user_agent=user_agent,
        )
        db.add(log)
        db.flush()  # flush immediately so it's in the transaction
    except Exception as exc:
        # Never let audit log failures break the main request
        logger.error("Failed to write audit log: %s", exc)


# ── Auth Service Functions ─────────────────────────────────────────────────────

async def login(
    email: str,
    password: str,
    db: Session,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> dict:
    """
    Authenticate a user and issue JWT tokens.

    Flow:
      1. Check rate limit for IP
      2. Authenticate against Supabase Auth
      3. Load AppUser from local DB
      4. Build scope (dept/team/group IDs)
      5. Create access + refresh JWTs with scope embedded
      6. Update last_login_at
      7. Write audit log

    Returns:
        TokenResponse-compatible dict.
    """
    # Step 1: Rate limit check
    if ip_address:
        check_auth_rate_limit(ip_address)

    # Step 2: Supabase authentication
    try:
        _supabase_session = await _supabase_sign_in(email, password)
    except AuthenticationFailed:
        if ip_address:
            record_failed_auth(ip_address)
        raise

    supabase_user = _supabase_session.get("user", {})
    supabase_user_id = supabase_user.get("id")

    if not supabase_user_id:
        logger.error("Supabase returned session without user.id for email=%s", email)
        raise AuthenticationFailed(message="Authentication failed.")

    # Step 3: Load local AppUser
    user_uuid = uuid.UUID(supabase_user_id)
    user: Optional[AppUser] = db.get(AppUser, user_uuid)

    if user is None:
        logger.error(
            "Supabase user %s authenticated but has no app_users record", supabase_user_id
        )
        raise AuthenticationFailed(
            message="Your account has not been fully set up. Please contact an administrator."
        )

    if not user.is_active:
        raise AuthenticationFailed(
            message="Your account has been deactivated. Contact an administrator."
        )

    # Step 4: Build scope
    scope = build_user_scope(user.id, db)

    # Step 5: Create JWT tokens
    token_data = {
        "sub": str(user.id),
        "email": user.email,
        "role": user.role.value,
        "scope": scope,
    }
    access_token = create_access_token(token_data)
    refresh_token = create_refresh_token(str(user.id))

    # Step 6: Update last_login_at
    try:
        db.execute(
            update(AppUser)
            .where(AppUser.id == user.id)
            .values(last_login_at=datetime.now(timezone.utc))
        )
    except Exception as exc:
        logger.warning("Failed to update last_login_at for user %s: %s", user.id, exc)

    # Step 7: Audit log
    write_audit_log(
        db,
        user_id=user.id,
        action=AuditAction.LOGIN,
        resource_type="AUTH",
        ip_address=ip_address,
        user_agent=user_agent,
    )

    # Clear rate limit counter on success
    if ip_address:
        clear_auth_rate_limit(ip_address)

    member_name: Optional[str] = user.member.full_name if user.member else None

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user": {
            "id": str(user.id),
            "email": user.email,
            "role": user.role.value,
            "name": member_name,
            "member_id": str(user.member_id) if user.member_id else None,
        },
    }


async def refresh_access_token(refresh_token: str, db: Session) -> dict:
    """
    Validate a refresh token and issue a new access token.

    The refresh token is our internal JWT (not the Supabase token).
    We verify its signature and expiry, then re-build the scope.

    Returns:
        Dict with new ``access_token`` and ``token_type``.
    """
    # Verify our internal refresh JWT
    payload = verify_token(refresh_token, expected_type="refresh")
    user_id_str = payload.get("sub")

    if not user_id_str:
        raise AuthenticationFailed(message="Invalid refresh token.")

    user_id = uuid.UUID(user_id_str)
    user: Optional[AppUser] = db.get(AppUser, user_id)

    if user is None or not user.is_active:
        raise AuthenticationFailed(message="User account is unavailable.")

    # Rebuild scope in case assignments changed since last login
    scope = build_user_scope(user.id, db)

    token_data = {
        "sub": str(user.id),
        "email": user.email,
        "role": user.role.value,
        "scope": scope,
    }
    new_access_token = create_access_token(token_data)

    return {
        "access_token": new_access_token,
        "token_type": "bearer",
    }


async def logout(
    access_token: str,
    current_user: AppUser,
    db: Session,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> None:
    """
    Blacklist the current access token and write an audit log entry.

    Args:
        access_token:  The raw JWT string from the Authorization header.
        current_user:  The authenticated AppUser instance.
        db:            Active database session.
        ip_address:    Client IP for audit.
        user_agent:    Client User-Agent for audit.
    """
    # Blacklist in Redis
    blacklist_token(access_token)

    # Audit log
    write_audit_log(
        db,
        user_id=current_user.id,
        action=AuditAction.LOGOUT,
        resource_type="AUTH",
        ip_address=ip_address,
        user_agent=user_agent,
    )


async def request_password_reset(email: str) -> None:
    """
    Trigger a Supabase password reset email.

    SECURITY: Never reveal whether the email exists in the system.
    Always return success to the caller.
    """
    # Fire-and-forget — failure is logged but never surfaced to user
    await _supabase_request_password_reset(email)
    logger.info("Password reset requested for email: %s", email)


async def reset_password(token: str, new_password: str) -> None:
    """
    Apply a new password using the Supabase recovery token.

    Args:
        token:        The recovery token from the email link (Supabase access token).
        new_password: Validated new password.

    Raises:
        AuthenticationFailed: Token is invalid or expired.
        ServiceUnavailable:   Supabase is unreachable.
    """
    await _supabase_update_password(token, new_password)


async def get_user_profile(
    user: AppUser,
    db: Session,
    request,
) -> dict:
    """
    Build the full user profile response for GET /api/v1/auth/me.

    Extracts scope from the request state (already decoded by get_current_user).
    """
    payload = getattr(request.state, "token_payload", {})
    scope = payload.get("scope", {"departments": [], "teams": [], "groups": []})
    member_name: Optional[str] = user.member.full_name if user.member else None

    return {
        "id": str(user.id),
        "email": user.email,
        "role": user.role.value,
        "name": member_name,
        "member_id": str(user.member_id) if user.member_id else None,
        "scope": scope,
        "is_active": user.is_active,
        "last_login_at": user.last_login_at.isoformat() if user.last_login_at else None,
    }
