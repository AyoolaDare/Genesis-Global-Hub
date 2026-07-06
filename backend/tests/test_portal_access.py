import uuid
from unittest.mock import patch

from tests.conftest import auth_headers
from tests.utils import create_active_member, create_department, create_user
from app.auth.models import AppUser, UserRole
from app.core.security import build_user_scope
from app.models.structure import MemberAssignment


def test_super_admin_grants_member_portal_access(client, db, super_admin_token):
    member = create_active_member(db, "Follow Up Worker")
    auth_user_id = uuid.uuid4()

    with patch(
        "app.services.structure_service._supabase_create_or_get_user",
        return_value=auth_user_id,
    ):
        response = client.post(
            f"/api/v1/members/{member.id}/portal-access",
            json={"email": "worker@test.com", "role": "FOLLOW_UP"},
            headers=auth_headers(super_admin_token),
        )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["user"]["email"] == "worker@test.com"
    assert data["user"]["role"] == "FOLLOW_UP"
    assert data["user"]["member_id"] == str(member.id)
    assert data["temporary_password"]

    user = db.get(AppUser, auth_user_id)
    assert user is not None
    assert user.member_id == member.id
    assert user.role == UserRole.FOLLOW_UP
    assert user.is_active is True


def test_super_admin_changes_existing_member_portal_role(client, db, super_admin_token):
    member = create_active_member(db, "Medical Worker")
    user = create_user(
        db,
        "worker@test.com",
        UserRole.FOLLOW_UP,
        member_id=member.id,
    )

    response = client.post(
        f"/api/v1/members/{member.id}/portal-access",
        json={"email": "worker@test.com", "role": "MEDICAL"},
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    db.refresh(user)
    assert user.role == UserRole.MEDICAL
    assert user.is_active is True
    assert "temporary_password" not in response.json()["data"]


def test_super_admin_revokes_member_portal_access(client, db, super_admin_token):
    member = create_active_member(db, "Portal User")
    user = create_user(
        db,
        "portal@test.com",
        UserRole.FINANCE_ADMIN,
        member_id=member.id,
    )

    response = client.delete(
        f"/api/v1/members/{member.id}/portal-access",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    db.refresh(user)
    assert user.is_active is False


def test_non_super_admin_cannot_grant_portal_access(client, db, pastor_token):
    member = create_active_member(db, "Protected Portal")

    response = client.post(
        f"/api/v1/members/{member.id}/portal-access",
        json={"email": "protected@test.com", "role": "FOLLOW_UP"},
        headers=auth_headers(pastor_token),
    )

    assert response.status_code == 403


def test_user_scope_includes_linked_member_assignments(db):
    dept = create_department(db, "Assigned Portal Dept")
    member = create_active_member(db, "Assigned Portal User")
    user = create_user(
        db,
        "assigned@test.com",
        UserRole.FOLLOW_UP,
        member_id=member.id,
    )
    db.add(
        MemberAssignment(
            member_id=member.id,
            assignment_type="DEPARTMENT",
            assignment_id=dept.id,
        )
    )
    db.flush()

    scope = build_user_scope(user.id, db)

    assert str(dept.id) in scope["departments"]
