"""
Genesis Global CMS — Role-Based Access Control Matrix Tests

Tests every (role, endpoint) combination from the access matrix.
Uses pytest.mark.parametrize for comprehensive coverage without duplication.

Access matrix under test:
  SUPER_ADMIN  → /members (200), /medical/patients (200), /sponsors (200), /hr/workers (200)
  PASTOR       → /members (200), /medical/patients (403), /sponsors (403), /hr/workers (403)
  MEDICAL      → /members (403), /medical/patients (200), /sponsors (403), /hr/workers (403)
  FINANCE_ADMIN→ /members (403), /medical/patients (403), /sponsors (200), /hr/workers (403)
  HR_ADMIN     → /members (403), /medical/patients (403), /sponsors (403), /hr/workers (200)
  FOLLOW_UP    → /follow-up/tasks (200), /medical/patients (403), /sponsors (403)
  DEPARTMENT_HEAD → /members (200), /medical/patients (403)
  TEAM_LEADER  → /members (200), /medical/patients (403)
  GROUP_LEADER → /members (200), /medical/patients (403)
  MEMBER       → /members (403), /medical/patients (403), /sponsors (403)
"""
import uuid
from typing import Tuple

import pytest

from tests.conftest import auth_headers, make_token
from tests.utils import create_user
from app.auth.models import UserRole


# ── Token Factory ──────────────────────────────────────────────────────────────

def _token_for_role(db, role_str: str) -> str:
    """Create a DB user + JWT for a given role string."""
    role_map = {
        "SUPER_ADMIN": UserRole.SUPER_ADMIN,
        "PASTOR": UserRole.PASTOR,
        "FINANCE_ADMIN": UserRole.FINANCE_ADMIN,
        "HR_ADMIN": UserRole.HR_ADMIN,
        "DEPARTMENT_HEAD": UserRole.DEPARTMENT_HEAD,
        "TEAM_LEADER": UserRole.TEAM_LEADER,
        "GROUP_LEADER": UserRole.GROUP_LEADER,
        "FOLLOW_UP": UserRole.FOLLOW_UP,
        "MEDICAL": UserRole.MEDICAL,
        "MEMBER": UserRole.MEMBER,
    }
    uid = str(uuid.uuid4())
    user = create_user(db, f"{uid[:8]}@matrix.test", role_map[role_str])
    return make_token(str(user.id), user.email, role_str)


# ── Parametrized Access Matrix ─────────────────────────────────────────────────

ROLE_ACCESS_MATRIX: list[Tuple[str, str, int]] = [
    # (role, endpoint, expected_status_code)

    # SUPER_ADMIN — global access
    ("SUPER_ADMIN", "/api/v1/members", 200),
    ("SUPER_ADMIN", "/api/v1/medical/patients", 200),
    ("SUPER_ADMIN", "/api/v1/sponsors", 200),
    ("SUPER_ADMIN", "/api/v1/hr/workers", 200),
    ("SUPER_ADMIN", "/api/v1/follow-up/tasks", 200),

    # PASTOR — members OK, everything else restricted
    ("PASTOR", "/api/v1/members", 200),
    ("PASTOR", "/api/v1/medical/patients", 403),
    ("PASTOR", "/api/v1/sponsors", 403),
    ("PASTOR", "/api/v1/hr/workers", 403),

    # MEDICAL — own patients only, no member directory
    ("MEDICAL", "/api/v1/members", 403),
    ("MEDICAL", "/api/v1/medical/patients", 200),
    ("MEDICAL", "/api/v1/sponsors", 403),
    ("MEDICAL", "/api/v1/hr/workers", 403),

    # FINANCE_ADMIN — sponsors only
    ("FINANCE_ADMIN", "/api/v1/members", 403),
    ("FINANCE_ADMIN", "/api/v1/medical/patients", 403),
    ("FINANCE_ADMIN", "/api/v1/sponsors", 200),
    ("FINANCE_ADMIN", "/api/v1/hr/workers", 403),

    # HR_ADMIN — workers only
    ("HR_ADMIN", "/api/v1/members", 403),
    ("HR_ADMIN", "/api/v1/medical/patients", 403),
    ("HR_ADMIN", "/api/v1/sponsors", 403),
    ("HR_ADMIN", "/api/v1/hr/workers", 200),

    # FOLLOW_UP — follow-up tasks, cannot access medical/sponsors/hr
    ("FOLLOW_UP", "/api/v1/follow-up/tasks", 200),
    ("FOLLOW_UP", "/api/v1/medical/patients", 403),
    ("FOLLOW_UP", "/api/v1/sponsors", 403),
    ("FOLLOW_UP", "/api/v1/hr/workers", 403),

    # DEPARTMENT_HEAD — scoped members, no medical/sponsors/hr
    ("DEPARTMENT_HEAD", "/api/v1/members", 200),
    ("DEPARTMENT_HEAD", "/api/v1/medical/patients", 403),
    ("DEPARTMENT_HEAD", "/api/v1/sponsors", 403),
    ("DEPARTMENT_HEAD", "/api/v1/hr/workers", 403),

    # TEAM_LEADER — scoped members, no medical/sponsors/hr
    ("TEAM_LEADER", "/api/v1/members", 200),
    ("TEAM_LEADER", "/api/v1/medical/patients", 403),
    ("TEAM_LEADER", "/api/v1/sponsors", 403),
    ("TEAM_LEADER", "/api/v1/hr/workers", 403),

    # GROUP_LEADER — scoped members, no medical/sponsors/hr
    ("GROUP_LEADER", "/api/v1/members", 200),
    ("GROUP_LEADER", "/api/v1/medical/patients", 403),
    ("GROUP_LEADER", "/api/v1/sponsors", 403),
    ("GROUP_LEADER", "/api/v1/hr/workers", 403),

    # MEMBER — very limited access
    ("MEMBER", "/api/v1/members", 403),
    ("MEMBER", "/api/v1/medical/patients", 403),
    ("MEMBER", "/api/v1/sponsors", 403),
    ("MEMBER", "/api/v1/hr/workers", 403),
]


@pytest.mark.parametrize("role,endpoint,expected_status", ROLE_ACCESS_MATRIX)
def test_role_access_matrix(client, db, role, endpoint, expected_status):
    """
    Parametrized test covering every role/endpoint combination in the access matrix.
    Tests that the HTTP response status code matches expectations.
    """
    token = _token_for_role(db, role)
    response = client.get(endpoint, headers=auth_headers(token))
    assert response.status_code == expected_status, (
        f"Role={role} endpoint={endpoint}: "
        f"expected {expected_status}, got {response.status_code}. "
        f"Body: {response.text[:200]}"
    )


# ── Targeted Descriptive Tests ─────────────────────────────────────────────────
# These exist alongside the parametrized matrix to provide clearer failure messages.

def test_super_admin_can_access_members(client, db):
    token = _token_for_role(db, "SUPER_ADMIN")
    assert client.get("/api/v1/members", headers=auth_headers(token)).status_code == 200


def test_super_admin_can_access_medical(client, db):
    token = _token_for_role(db, "SUPER_ADMIN")
    assert client.get("/api/v1/medical/patients", headers=auth_headers(token)).status_code == 200


def test_super_admin_can_access_sponsors(client, db):
    token = _token_for_role(db, "SUPER_ADMIN")
    assert client.get("/api/v1/sponsors", headers=auth_headers(token)).status_code == 200


def test_super_admin_can_access_hr_workers(client, db):
    token = _token_for_role(db, "SUPER_ADMIN")
    assert client.get("/api/v1/hr/workers", headers=auth_headers(token)).status_code == 200


def test_medical_cannot_access_member_directory(client, db):
    token = _token_for_role(db, "MEDICAL")
    response = client.get("/api/v1/members", headers=auth_headers(token))
    assert response.status_code == 403
    assert response.json()["success"] is False


def test_medical_can_access_own_patients(client, db):
    token = _token_for_role(db, "MEDICAL")
    assert client.get("/api/v1/medical/patients", headers=auth_headers(token)).status_code == 200


def test_finance_cannot_access_members(client, db):
    token = _token_for_role(db, "FINANCE_ADMIN")
    assert client.get("/api/v1/members", headers=auth_headers(token)).status_code == 403


def test_finance_cannot_access_medical(client, db):
    token = _token_for_role(db, "FINANCE_ADMIN")
    assert client.get("/api/v1/medical/patients", headers=auth_headers(token)).status_code == 403


def test_finance_can_access_sponsors(client, db):
    token = _token_for_role(db, "FINANCE_ADMIN")
    assert client.get("/api/v1/sponsors", headers=auth_headers(token)).status_code == 200


def test_hr_cannot_access_medical(client, db):
    token = _token_for_role(db, "HR_ADMIN")
    assert client.get("/api/v1/medical/patients", headers=auth_headers(token)).status_code == 403


def test_hr_cannot_access_sponsors(client, db):
    token = _token_for_role(db, "HR_ADMIN")
    assert client.get("/api/v1/sponsors", headers=auth_headers(token)).status_code == 403


def test_hr_can_access_workers(client, db):
    token = _token_for_role(db, "HR_ADMIN")
    assert client.get("/api/v1/hr/workers", headers=auth_headers(token)).status_code == 200


def test_follow_up_can_access_tasks(client, db):
    token = _token_for_role(db, "FOLLOW_UP")
    assert client.get("/api/v1/follow-up/tasks", headers=auth_headers(token)).status_code == 200


def test_follow_up_cannot_access_sponsors(client, db):
    token = _token_for_role(db, "FOLLOW_UP")
    assert client.get("/api/v1/sponsors", headers=auth_headers(token)).status_code == 403


def test_member_role_cannot_access_any_admin_endpoint(client, db):
    token = _token_for_role(db, "MEMBER")
    assert client.get("/api/v1/members", headers=auth_headers(token)).status_code == 403
    assert client.get("/api/v1/medical/patients", headers=auth_headers(token)).status_code == 403
    assert client.get("/api/v1/sponsors", headers=auth_headers(token)).status_code == 403
    assert client.get("/api/v1/hr/workers", headers=auth_headers(token)).status_code == 403


def test_unauthenticated_cannot_access_any_endpoint(client):
    """No token at all must result in 401 on all protected endpoints."""
    endpoints = [
        "/api/v1/members",
        "/api/v1/medical/patients",
        "/api/v1/sponsors",
        "/api/v1/hr/workers",
        "/api/v1/follow-up/tasks",
    ]
    for endpoint in endpoints:
        r = client.get(endpoint)
        assert r.status_code == 401, f"Expected 401 for unauthenticated {endpoint}, got {r.status_code}"


# ── Permission System Unit Tests ───────────────────────────────────────────────

def test_has_permission_super_admin_wildcard():
    """Super admin's wildcard must grant any permission."""
    from app.auth.permissions import has_permission

    assert has_permission("SUPER_ADMIN", "members:read") is True
    assert has_permission("SUPER_ADMIN", "medical:read:own") is True
    assert has_permission("SUPER_ADMIN", "anything:at:all") is True


def test_has_permission_medical_own_only():
    """Medical role should have medical permissions but NOT member permissions."""
    from app.auth.permissions import has_permission

    assert has_permission("MEDICAL", "medical:read:own") is True
    assert has_permission("MEDICAL", "medical:create:own") is True
    assert has_permission("MEDICAL", "members:read") is False
    assert has_permission("MEDICAL", "sponsors:read") is False


def test_has_permission_finance_admin_scope():
    """Finance admin should have sponsor/payment permissions but not members/medical."""
    from app.auth.permissions import has_permission

    assert has_permission("FINANCE_ADMIN", "sponsors:read") is True
    assert has_permission("FINANCE_ADMIN", "payments:create") is True
    assert has_permission("FINANCE_ADMIN", "members:read") is False
    assert has_permission("FINANCE_ADMIN", "medical:read") is False


def test_has_permission_hr_admin_scope():
    """HR admin should have worker/leave permissions but not members/medical/sponsors."""
    from app.auth.permissions import has_permission

    assert has_permission("HR_ADMIN", "workers:read") is True
    assert has_permission("HR_ADMIN", "leave:create") is True
    assert has_permission("HR_ADMIN", "members:read") is False
    assert has_permission("HR_ADMIN", "medical:read") is False
    assert has_permission("HR_ADMIN", "sponsors:read") is False


def test_has_permission_follow_up_pending_creates():
    """Follow-up should be able to create members but only as PENDING."""
    from app.auth.permissions import has_permission

    assert has_permission("FOLLOW_UP", "members:create:pending") is True
    assert has_permission("FOLLOW_UP", "follow_up:read") is True
    assert has_permission("FOLLOW_UP", "medical:read") is False


def test_permission_qualifier_returns_scoped_for_dept_head():
    """Department head's members permission should have 'scoped' qualifier."""
    from app.auth.permissions import get_permission_qualifier

    qualifier = get_permission_qualifier("DEPARTMENT_HEAD", "members:read")
    assert qualifier == "scoped"


def test_permission_qualifier_returns_none_for_super_admin():
    """Super admin should have no qualifier (unrestricted)."""
    from app.auth.permissions import get_permission_qualifier

    qualifier = get_permission_qualifier("SUPER_ADMIN", "members:read")
    assert qualifier is None
