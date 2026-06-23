"""
Genesis Global CMS — Core Security Utilities

Handles:
  - JWT creation & verification (access + refresh tokens)
  - Password hashing (bcrypt via passlib)
  - Scope building (dept/team/group IDs embedded in JWT)
  - Redis token blacklist management
"""
import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import redis as redis_lib
from jose import ExpiredSignatureError, JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import settings
from app.core.exceptions import (
    AccountInactive,
    TokenBlacklisted,
    TokenExpired,
    TokenInvalid,
)

logger = logging.getLogger(__name__)

# ── Password Hashing ───────────────────────────────────────────────────────────
_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=12)


def get_password_hash(password: str) -> str:
    """Hash a plaintext password using bcrypt."""
    return _pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plaintext password against a bcrypt hash."""
    return _pwd_context.verify(plain_password, hashed_password)


# ── Redis Client (Upstash) ─────────────────────────────────────────────────────
def _get_redis_client() -> redis_lib.Redis:
    """Return a Redis client connected to Upstash via TLS."""
    return redis_lib.from_url(
        settings.UPSTASH_REDIS_URL,
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=5,
    )


# ── JWT Token Creation ─────────────────────────────────────────────────────────
def create_access_token(data: dict[str, Any]) -> str:
    """
    Create a signed JWT access token.

    The ``data`` dict MUST contain ``sub`` (user UUID string).
    It may contain ``email``, ``role``, and ``scope``.
    Expiry is appended automatically from settings.

    Returns:
        Signed JWT string.
    """
    to_encode = data.copy()
    now = datetime.now(timezone.utc)
    expire = now + timedelta(hours=settings.ACCESS_TOKEN_EXPIRE_HOURS)
    to_encode.update(
        {
            "iat": now,
            "exp": expire,
            "type": "access",
            "jti": str(uuid.uuid4()),  # unique token ID for blacklisting
        }
    )
    return jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token(user_id: str) -> str:
    """
    Create a long-lived refresh token containing only the user ID.

    Args:
        user_id: UUID string of the app_user.

    Returns:
        Signed JWT string.
    """
    now = datetime.now(timezone.utc)
    expire = now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    payload = {
        "sub": user_id,
        "iat": now,
        "exp": expire,
        "type": "refresh",
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


# ── JWT Token Verification ─────────────────────────────────────────────────────
def verify_token(token: str, expected_type: str = "access") -> dict[str, Any]:
    """
    Decode and validate a JWT token.

    Checks:
      1. Signature validity
      2. Expiry
      3. Token type (access vs refresh)
      4. Redis blacklist

    Args:
        token:         The raw JWT string.
        expected_type: "access" or "refresh".

    Returns:
        Decoded payload dict.

    Raises:
        TokenExpired:     Token has expired.
        TokenInvalid:     Signature invalid, malformed, or wrong type.
        TokenBlacklisted: Token has been revoked.
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
        )
    except ExpiredSignatureError:
        raise TokenExpired()
    except JWTError:
        raise TokenInvalid()

    # Validate token type
    if payload.get("type") != expected_type:
        raise TokenInvalid(
            message=f"Expected {expected_type} token but received {payload.get('type')} token."
        )

    # Check blacklist in Redis
    jti = payload.get("jti")
    if jti and _is_token_blacklisted(jti):
        raise TokenBlacklisted()

    return payload


def blacklist_token(token: str) -> None:
    """
    Add a token's JTI to the Redis blacklist, expiring at the token's exp time.

    This is called on logout. The blacklist entry automatically expires so
    Redis does not accumulate stale entries.
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
            options={"verify_exp": False},  # decode even if expired
        )
        jti = payload.get("jti")
        exp = payload.get("exp")
        if not jti:
            return

        now_ts = datetime.now(timezone.utc).timestamp()
        ttl = max(0, int((exp or now_ts) - now_ts))
        if ttl <= 0:
            return  # already expired; no need to blacklist

        r = _get_redis_client()
        r.setex(f"blacklist:{jti}", ttl, "1")
    except Exception as exc:
        logger.warning("Failed to blacklist token: %s", exc)


def _is_token_blacklisted(jti: str) -> bool:
    """Return True if the JTI is present in the Redis blacklist."""
    try:
        r = _get_redis_client()
        return r.exists(f"blacklist:{jti}") == 1
    except Exception as exc:
        logger.warning("Redis blacklist check failed (failing open): %s", exc)
        # Fail open to prevent complete outage if Redis is down;
        # monitor Redis availability separately.
        return False


# ── Scope Builder ──────────────────────────────────────────────────────────────
def build_user_scope(user_id: uuid.UUID, db: Session) -> dict[str, list[str]]:
    """
    Query the database to build the JWT scope dict for a given user.

    For SUPER_ADMIN, PASTOR, FINANCE_ADMIN, HR_ADMIN, FOLLOW_UP, MEDICAL,
    MEMBER the scope is empty (they either have global access or row-level
    access enforced by RLS).

    For DEPARTMENT_HEAD, TEAM_LEADER, GROUP_LEADER the scope contains the
    UUIDs of the departments/teams/groups they are responsible for.

    Args:
        user_id: UUID of the app_user.
        db:      Active SQLAlchemy session.

    Returns:
        Dict with keys "departments", "teams", "groups" (lists of UUID strings).
    """
    scope: dict[str, list[str]] = {
        "departments": [],
        "teams": [],
        "groups": [],
    }

    try:
        # Departments this user heads
        dept_rows = db.execute(
            text("SELECT id FROM departments WHERE head_user_id = :uid AND deleted_at IS NULL"),
            {"uid": str(user_id)},
        ).fetchall()
        scope["departments"] = [str(r[0]) for r in dept_rows]

        # Teams this user leads
        team_rows = db.execute(
            text("SELECT id FROM teams WHERE leader_user_id = :uid AND deleted_at IS NULL"),
            {"uid": str(user_id)},
        ).fetchall()
        scope["teams"] = [str(r[0]) for r in team_rows]

        # Groups this user leads
        group_rows = db.execute(
            text("SELECT id FROM groups WHERE leader_user_id = :uid AND deleted_at IS NULL"),
            {"uid": str(user_id)},
        ).fetchall()
        scope["groups"] = [str(r[0]) for r in group_rows]

    except Exception as exc:
        logger.error("Failed to build scope for user %s: %s", user_id, exc)

    return scope


# ── Rate Limiting Helpers ──────────────────────────────────────────────────────
def check_auth_rate_limit(ip_address: str) -> None:
    """
    Enforce authentication rate limit using a sliding window counter in Redis.

    Allows RATE_LIMIT_AUTH_ATTEMPTS attempts within RATE_LIMIT_AUTH_WINDOW_SECONDS.
    Raises RateLimitExceeded if the limit is breached.
    """
    from app.core.exceptions import RateLimitExceeded

    key = f"auth_attempts:{ip_address}"
    try:
        r = _get_redis_client()
        pipe = r.pipeline()
        pipe.incr(key)
        pipe.expire(key, settings.RATE_LIMIT_AUTH_WINDOW_SECONDS)
        results = pipe.execute()
        attempts = results[0]

        if attempts > settings.RATE_LIMIT_AUTH_ATTEMPTS:
            raise RateLimitExceeded(
                message=(
                    f"Too many login attempts. "
                    f"Please wait {settings.RATE_LIMIT_AUTH_WINDOW_SECONDS // 60} minutes."
                )
            )
    except RateLimitExceeded:
        raise
    except Exception as exc:
        logger.warning("Rate limit check failed (failing open): %s", exc)


def record_failed_auth(ip_address: str) -> None:
    """Increment failed auth counter in Redis (used for brute-force protection)."""
    key = f"auth_attempts:{ip_address}"
    try:
        r = _get_redis_client()
        pipe = r.pipeline()
        pipe.incr(key)
        pipe.expire(key, settings.RATE_LIMIT_AUTH_WINDOW_SECONDS)
        pipe.execute()
    except Exception as exc:
        logger.warning("Failed to record auth attempt: %s", exc)


def clear_auth_rate_limit(ip_address: str) -> None:
    """Clear rate limit counter after a successful login."""
    key = f"auth_attempts:{ip_address}"
    try:
        r = _get_redis_client()
        r.delete(key)
    except Exception as exc:
        logger.warning("Failed to clear rate limit: %s", exc)
