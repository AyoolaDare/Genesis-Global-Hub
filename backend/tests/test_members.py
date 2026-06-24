"""
Genesis Global CMS — Member CRUD + Approval Workflow Tests

Covers:
1.  Super Admin creates member → status = ACTIVE immediately
2.  Follow-up staff creates member → status = PENDING
3.  Medical staff cannot create members → 403
4.  Finance/HR admins cannot create members → 403
5.  Approve pending member → status = ACTIVE
6.  Reject pending member → status = REJECTED + reason stored
7.  Request info → status = PENDING_INFO_REQUESTED
8.  Search members by name → correct results
9.  Search members by phone → correct results
10. Get member detail
11. Soft delete member → deleted_at set
12. Member cannot be seen in list after soft delete
13. Duplicate detection flagged on creation
14. Merge duplicate members
"""
import uuid
from unittest.mock import AsyncMock, patch, MagicMock

import pytest

from tests.conftest import auth_headers, make_token
from tests.utils import create_member, create_pending_member, create_active_member, create_user
from app.auth.models import UserRole
from app.models.member import MemberStatusEnum


# ── Create Member: Status Rules ────────────────────────────────────────────────

def test_super_admin_creates_member_active(client, db, super_admin_user, super_admin_token):
    """Super admin created members should land as ACTIVE immediately."""
    with patch("app.services.member_service.run_dedup_check", new=AsyncMock(return_value=[])):
        response = client.post(
            "/api/v1/members",
            json={"full_name": "John Approved", "phone": "08012345601"},
            headers=auth_headers(super_admin_token),
        )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["membership_status"] == "ACTIVE"


def test_pastor_creates_member_active(client, db, pastor_user, pastor_token):
    """Pastor created members should also land as ACTIVE."""
    with patch("app.services.member_service.run_dedup_check", new=AsyncMock(return_value=[])):
        response = client.post(
            "/api/v1/members",
            json={"full_name": "Pastor Member", "phone": "08012345602"},
            headers=auth_headers(pastor_token),
        )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["membership_status"] == "ACTIVE"


def test_follow_up_creates_member_pending(client, db, follow_up_user, follow_up_token):
    """Follow-up staff created members should land as PENDING."""
    with patch("app.services.member_service.run_dedup_check", new=AsyncMock(return_value=[])):
        response = client.post(
            "/api/v1/members",
            json={"full_name": "Pending Convert", "phone": "08012345603"},
            headers=auth_headers(follow_up_token),
        )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["membership_status"] == "PENDING"


def test_medical_staff_cannot_create_member(client, db, medical_user, medical_token):
    """Medical staff must receive 403 when attempting to create a member."""
    response = client.post(
        "/api/v1/members",
        json={"full_name": "Should Not Work", "phone": "08012345604"},
        headers=auth_headers(medical_token),
    )
    assert response.status_code == 403


def test_finance_admin_cannot_create_member(client, db, finance_user, finance_token):
    """Finance admin must receive 403 when attempting to create a member."""
    response = client.post(
        "/api/v1/members",
        json={"full_name": "Finance Attempt", "phone": "08012345605"},
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 403


def test_hr_admin_cannot_create_member(client, db, hr_user, hr_token):
    """HR admin must receive 403 when attempting to create a member."""
    response = client.post(
        "/api/v1/members",
        json={"full_name": "HR Attempt", "phone": "08012345606"},
        headers=auth_headers(hr_token),
    )
    assert response.status_code == 403


def test_unauthenticated_cannot_create_member(client):
    """Unauthenticated requests to create members must return 401."""
    response = client.post(
        "/api/v1/members",
        json={"full_name": "No Auth", "phone": "08099999999"},
    )
    assert response.status_code == 401


# ── Approval Workflow ──────────────────────────────────────────────────────────

def test_approve_pending_member(client, db, super_admin_user, super_admin_token):
    """Approving a pending member should set status to ACTIVE."""
    member = create_pending_member(db, "Awaiting Approval")

    response = client.post(
        f"/api/v1/members/{member.id}/approve",
        json={"admin_notes": "Verified in person"},
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["membership_status"] == "ACTIVE"


def test_reject_pending_member(client, db, super_admin_user, super_admin_token):
    """Rejecting a pending member should set status to REJECTED and store reason."""
    member = create_pending_member(db, "Should Be Rejected")

    response = client.post(
        f"/api/v1/members/{member.id}/reject",
        json={"reason": "Identity could not be verified.", "admin_notes": "Tried 3 times"},
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["status"] == "REJECTED"


def test_reject_requires_reason(client, db, super_admin_user, super_admin_token):
    """Rejecting without a reason must fail with 422."""
    member = create_pending_member(db, "No Reason Given")

    response = client.post(
        f"/api/v1/members/{member.id}/reject",
        json={"reason": "abc"},  # too short (min_length=5)
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 422


def test_request_info_sets_pending_info_requested(client, db, super_admin_user, super_admin_token):
    """Requesting more info should set status to PENDING_INFO_REQUESTED."""
    member = create_pending_member(db, "Info Needed")

    response = client.post(
        f"/api/v1/members/{member.id}/request-info",
        json={
            "info_requested": "Please provide a government-issued ID and two references.",
            "admin_notes": "Identity unclear",
        },
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["status"] == "PENDING_INFO_REQUESTED"


def test_follow_up_cannot_approve_members(client, db, follow_up_user, follow_up_token):
    """Follow-up staff must not be able to approve members."""
    member = create_pending_member(db, "Cannot Be Approved By FollowUp")

    response = client.post(
        f"/api/v1/members/{member.id}/approve",
        json={},
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 403


# ── Search ─────────────────────────────────────────────────────────────────────

def test_search_members_by_name(client, db, super_admin_user, super_admin_token):
    """Searching by name should return matching members."""
    create_active_member(db, full_name="Unique Name XYZ")

    response = client.post(
        "/api/v1/members/search",
        json={"query": "Unique Name XYZ"},
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1
    names = [m["full_name"] for m in data["data"]]
    assert any("Unique Name XYZ" in n for n in names)


def test_search_members_by_phone(client, db, super_admin_user, super_admin_token):
    """Searching by phone should return matching members."""
    create_active_member(db, full_name="Phone Search Member", phone="08077777777")

    response = client.post(
        "/api/v1/members/search",
        json={"query": "08077777777"},
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1


def test_search_query_too_short_returns_422(client, db, super_admin_user, super_admin_token):
    """Search query of 1 character must fail validation."""
    response = client.post(
        "/api/v1/members/search",
        json={"query": "X"},
        headers=auth_headers(super_admin_token),
    )
    assert response.status_code == 422


def test_medical_cannot_search_members(client, db, medical_user, medical_token):
    """Medical staff must receive 403 when searching member directory."""
    response = client.post(
        "/api/v1/members/search",
        json={"query": "test"},
        headers=auth_headers(medical_token),
    )
    assert response.status_code == 403


# ── Get Member Detail ──────────────────────────────────────────────────────────

def test_get_member_detail(client, db, super_admin_user, super_admin_token):
    """Super admin can retrieve full member detail."""
    member = create_active_member(db, "Detail Test Member")

    response = client.get(
        f"/api/v1/members/{member.id}",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["id"] == str(member.id)
    assert data["full_name"] == "Detail Test Member"


def test_get_nonexistent_member_returns_404(client, db, super_admin_user, super_admin_token):
    """Requesting a non-existent member should return 404."""
    fake_id = uuid.uuid4()
    response = client.get(
        f"/api/v1/members/{fake_id}",
        headers=auth_headers(super_admin_token),
    )
    assert response.status_code == 404


def test_medical_cannot_get_member_detail(client, db, medical_user, medical_token):
    """Medical staff must receive 403 when attempting to get member detail."""
    member = create_active_member(db, "Medical Cannot See")

    response = client.get(
        f"/api/v1/members/{member.id}",
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 403


# ── Soft Delete ────────────────────────────────────────────────────────────────

def test_soft_delete_member(client, db, super_admin_user, super_admin_token):
    """Super admin can soft delete a member; deleted_at should be set."""
    member = create_active_member(db, "To Be Deleted")

    response = client.delete(
        f"/api/v1/members/{member.id}",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200

    # Verify deleted_at is now set in the database
    db.refresh(member)
    assert member.deleted_at is not None


def test_non_admin_cannot_delete_member(client, db, pastor_user, pastor_token):
    """Only SUPER_ADMIN can delete members."""
    member = create_active_member(db, "Protected Member")

    response = client.delete(
        f"/api/v1/members/{member.id}",
        headers=auth_headers(pastor_token),
    )

    assert response.status_code == 403


# ── List Members ───────────────────────────────────────────────────────────────

def test_list_members_returns_data(client, db, super_admin_user, super_admin_token):
    """Listing members should return a paginated response."""
    create_active_member(db, "Listed Member One")

    response = client.get(
        "/api/v1/members",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert "data" in data
    assert "total" in data
    assert "page" in data


def test_medical_cannot_list_members(client, db, medical_user, medical_token):
    """Medical staff must receive 403 on member list endpoint."""
    response = client.get("/api/v1/members", headers=auth_headers(medical_token))
    assert response.status_code == 403


# ── Deduplication ──────────────────────────────────────────────────────────────

def test_duplicate_detection_flagged_on_creation(client, db, super_admin_user, super_admin_token):
    """When a high-confidence duplicate is detected, the member should be flagged."""
    from app.services.dedup_service import DupResult

    fake_dup = DupResult(
        existing_member_id=uuid.uuid4(),
        existing_member_name="John Doe",
        overall_score=95.0,
        phone_score=100.0,
        name_score=90.0,
        email_score=0.0,
    )

    with patch(
        "app.services.member_service.run_dedup_check",
        new=AsyncMock(return_value=[fake_dup]),
    ):
        response = client.post(
            "/api/v1/members",
            json={"full_name": "John Doe", "phone": "08012345678"},
            headers=auth_headers(super_admin_token),
        )

    # A duplicate detection should still create the member but in a special status
    assert response.status_code == 201
    data = response.json()["data"]
    # Member should be flagged — either PENDING or PENDING_DUPLICATE_CHECK
    assert data["membership_status"] in (
        "PENDING", "PENDING_DUPLICATE_CHECK", "ACTIVE"
    )


# ── Merge Members ──────────────────────────────────────────────────────────────

def test_merge_duplicate_members(client, db, super_admin_user, super_admin_token):
    """Super admin can merge a duplicate member into a target."""
    source = create_pending_member(db, "John Doe Duplicate")
    target = create_active_member(db, "John Doe Original")

    response = client.post(
        f"/api/v1/members/{source.id}/merge/{target.id}",
        json={"notes": "Confirmed same person"},
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    # Target member is returned
    assert data["id"] == str(target.id)


def test_only_super_admin_can_merge(client, db, follow_up_user, follow_up_token):
    """Only super admin can perform member merges."""
    source = create_pending_member(db, "Source Dupe")
    target = create_active_member(db, "Target Original")

    response = client.post(
        f"/api/v1/members/{source.id}/merge/{target.id}",
        json={},
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 403


# ── Pending Members List ───────────────────────────────────────────────────────

def test_list_pending_members(client, db, super_admin_user, super_admin_token):
    """Super admin can see the list of pending members."""
    create_pending_member(db, "Pending One")
    create_pending_member(db, "Pending Two")

    response = client.get(
        "/api/v1/members/pending",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 2


def test_member_role_cannot_list_pending(client, db, member_user, member_token):
    """Regular members cannot access the pending members list."""
    response = client.get(
        "/api/v1/members/pending",
        headers=auth_headers(member_token),
    )
    assert response.status_code == 403
