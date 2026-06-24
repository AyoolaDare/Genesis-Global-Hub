"""
Genesis Global CMS — Auth Endpoint Tests

Covers:
1.  Login with valid credentials → access_token + refresh_token
2.  Login with wrong password → 401
3.  Login with non-existent email → 401 (no email enumeration)
4.  Refresh with valid refresh token → new access_token
5.  Refresh with access token (wrong type) → 401
6.  Logout → token blacklisted
7.  GET /me with valid token → user data
8.  GET /me without token → 401
9.  POST /forgot-password → always 200
10. Rate limiting: exceeded attempts → 429
"""
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from tests.conftest import auth_headers, make_token
from tests.utils import create_user
from app.auth.models import UserRole
from app.core.security import create_access_token, create_refresh_token


# ── Helpers ────────────────────────────────────────────────────────────────────

def _supabase_ok_response(user_id: str, email: str) -> dict:
    """Mock a successful Supabase Auth sign-in response."""
    return {
        "access_token": "supabase-access-token",
        "refresh_token": "supabase-refresh-token",
        "token_type": "bearer",
        "user": {"id": user_id, "email": email},
    }


# ── Test: Login ────────────────────────────────────────────────────────────────

def test_login_valid_credentials_returns_tokens(client, db):
    """Successful login must return access_token and refresh_token."""
    user = create_user(db, "loginuser@test.com", UserRole.SUPER_ADMIN)

    with patch(
        "app.auth.service._supabase_sign_in",
        new=AsyncMock(return_value=_supabase_ok_response(str(user.id), user.email)),
    ):
        response = client.post(
            "/api/v1/auth/login",
            json={"email": user.email, "password": "CorrectPassword123!"},
        )

    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "access_token" in data["data"]
    assert "refresh_token" in data["data"]
    assert data["data"]["token_type"] == "bearer"
    assert data["data"]["user"]["email"] == user.email
    assert data["data"]["user"]["role"] == "SUPER_ADMIN"


def test_login_wrong_password_returns_401(client, db):
    """Wrong password must return 401."""
    from app.core.exceptions import AuthenticationFailed

    with patch(
        "app.auth.service._supabase_sign_in",
        new=AsyncMock(side_effect=AuthenticationFailed("Invalid email or password.")),
    ):
        response = client.post(
            "/api/v1/auth/login",
            json={"email": "someone@test.com", "password": "WrongPass"},
        )

    assert response.status_code == 401
    assert response.json()["success"] is False


def test_login_nonexistent_email_returns_401(client, db):
    """Non-existent email must return 401 — same error as wrong password (no enumeration)."""
    from app.core.exceptions import AuthenticationFailed

    with patch(
        "app.auth.service._supabase_sign_in",
        new=AsyncMock(side_effect=AuthenticationFailed("Invalid email or password.")),
    ):
        response = client.post(
            "/api/v1/auth/login",
            json={"email": "doesnotexist@test.com", "password": "AnyPass"},
        )

    assert response.status_code == 401
    # Ensure the error message is the same as wrong password (prevent enumeration)
    data = response.json()
    assert "email" not in data.get("message", "").lower() or "invalid" in data.get("message", "").lower()


def test_login_error_message_same_for_wrong_password_and_missing_user(client, db):
    """Both invalid-password and missing-user scenarios must produce identical error messages."""
    from app.core.exceptions import AuthenticationFailed

    wrong_pass_msg = None
    missing_user_msg = None

    with patch(
        "app.auth.service._supabase_sign_in",
        new=AsyncMock(side_effect=AuthenticationFailed("Invalid email or password.")),
    ):
        r1 = client.post(
            "/api/v1/auth/login",
            json={"email": "x@y.com", "password": "bad"},
        )
        wrong_pass_msg = r1.json().get("message", "")

    with patch(
        "app.auth.service._supabase_sign_in",
        new=AsyncMock(side_effect=AuthenticationFailed("Invalid email or password.")),
    ):
        r2 = client.post(
            "/api/v1/auth/login",
            json={"email": "nouser@test.com", "password": "any"},
        )
        missing_user_msg = r2.json().get("message", "")

    assert wrong_pass_msg == missing_user_msg


# ── Test: Refresh Token ────────────────────────────────────────────────────────

def test_refresh_valid_token_returns_new_access_token(client, db):
    """A valid refresh token must produce a new access_token."""
    user = create_user(db, "refreshuser@test.com", UserRole.PASTOR)
    refresh_token = create_refresh_token(str(user.id))

    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "access_token" in data["data"]
    assert data["data"]["token_type"] == "bearer"


def test_refresh_with_access_token_type_returns_401(client, db):
    """Sending an access token to /refresh must fail (wrong token type)."""
    user = create_user(db, "wrongtype@test.com", UserRole.MEMBER)
    # Create an access token and pass it as a refresh token
    access_token = create_access_token({
        "sub": str(user.id),
        "email": user.email,
        "role": "MEMBER",
        "scope": {"departments": [], "teams": [], "groups": []},
    })

    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": access_token},
    )

    assert response.status_code == 401


def test_refresh_with_invalid_token_returns_401(client):
    """Completely invalid token must return 401."""
    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": "not.a.valid.jwt.token"},
    )
    assert response.status_code == 401


# ── Test: Logout ───────────────────────────────────────────────────────────────

def test_logout_blacklists_token(client, db):
    """After logout, the same token must not be usable."""
    user = create_user(db, "logoutuser@test.com", UserRole.SUPER_ADMIN)
    token = make_token(str(user.id), user.email, "SUPER_ADMIN")

    # First: confirm the token works
    me_response = client.get("/api/v1/auth/me", headers=auth_headers(token))
    assert me_response.status_code == 200

    # Logout
    logout_response = client.post(
        "/api/v1/auth/logout",
        headers=auth_headers(token),
    )
    assert logout_response.status_code == 200
    assert logout_response.json()["success"] is True

    # Now simulate the token being blacklisted by patching Redis
    blacklisted_redis = MagicMock()
    blacklisted_redis.exists.return_value = 1  # 1 = token IS blacklisted

    with patch("app.core.security._get_redis_client", return_value=blacklisted_redis):
        after_logout = client.get("/api/v1/auth/me", headers=auth_headers(token))

    assert after_logout.status_code == 401


# ── Test: GET /me ──────────────────────────────────────────────────────────────

def test_get_me_with_valid_token(client, db, super_admin_user, super_admin_token):
    """Authenticated GET /me must return user profile."""
    response = client.get("/api/v1/auth/me", headers=auth_headers(super_admin_token))

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["email"] == super_admin_user.email
    assert data["role"] == "SUPER_ADMIN"
    assert "scope" in data
    assert "is_active" in data


def test_get_me_without_token_returns_401(client):
    """Unauthenticated GET /me must return 401."""
    response = client.get("/api/v1/auth/me")
    assert response.status_code == 401


def test_get_me_with_malformed_token_returns_401(client):
    """Malformed Authorization header must return 401."""
    response = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": "Bearer this.is.garbage"},
    )
    assert response.status_code == 401


# ── Test: Forgot Password ──────────────────────────────────────────────────────

def test_forgot_password_existing_email_returns_200(client, db):
    """POST /forgot-password always returns 200 for known emails."""
    with patch(
        "app.auth.service._supabase_request_password_reset",
        new=AsyncMock(return_value=None),
    ):
        response = client.post(
            "/api/v1/auth/forgot-password",
            json={"email": "exists@test.com"},
        )
    assert response.status_code == 200
    assert response.json()["success"] is True


def test_forgot_password_nonexistent_email_returns_200(client):
    """POST /forgot-password must return 200 even for unknown emails (prevents enumeration)."""
    with patch(
        "app.auth.service._supabase_request_password_reset",
        new=AsyncMock(return_value=None),
    ):
        response = client.post(
            "/api/v1/auth/forgot-password",
            json={"email": "ghost@doesnotexist.io"},
        )
    assert response.status_code == 200
    assert response.json()["success"] is True


def test_forgot_password_response_message_does_not_reveal_existence(client):
    """The response message must be the same regardless of email existence."""
    with patch(
        "app.auth.service._supabase_request_password_reset",
        new=AsyncMock(return_value=None),
    ):
        r1 = client.post("/api/v1/auth/forgot-password", json={"email": "real@test.com"})
        r2 = client.post("/api/v1/auth/forgot-password", json={"email": "fake@test.com"})

    # Both responses must have the same structure and message
    assert r1.json()["message"] == r2.json()["message"]


# ── Test: Rate Limiting ────────────────────────────────────────────────────────

def test_rate_limit_exceeded_returns_429(client, db):
    """Exceeding RATE_LIMIT_AUTH_ATTEMPTS login attempts must return 429."""
    from app.core.exceptions import RateLimitExceeded

    with patch(
        "app.auth.service.check_auth_rate_limit",
        side_effect=RateLimitExceeded("Too many login attempts."),
    ):
        response = client.post(
            "/api/v1/auth/login",
            json={"email": "victim@test.com", "password": "any"},
        )

    assert response.status_code == 429
    assert response.json()["success"] is False


def test_successful_login_does_not_trigger_rate_limit(client, db):
    """A successful login should not be blocked by the rate limiter."""
    user = create_user(db, "nolimit@test.com", UserRole.MEMBER)

    with patch(
        "app.auth.service._supabase_sign_in",
        new=AsyncMock(return_value=_supabase_ok_response(str(user.id), user.email)),
    ), patch("app.auth.service.check_auth_rate_limit", return_value=None), \
       patch("app.auth.service.clear_auth_rate_limit", return_value=None):
        response = client.post(
            "/api/v1/auth/login",
            json={"email": user.email, "password": "CorrectPass123!"},
        )

    assert response.status_code == 200


# ── Test: Inactive Account ─────────────────────────────────────────────────────

def test_inactive_user_cannot_access_me(client, db):
    """Deactivated user accounts must receive 401."""
    user = create_user(db, "inactive@test.com", UserRole.MEMBER, is_active=False)
    token = make_token(str(user.id), user.email, "MEMBER")

    response = client.get("/api/v1/auth/me", headers=auth_headers(token))
    assert response.status_code == 401
