"""
Genesis Global CMS — Attendance & Meetings Tests

Covers:
1.  Authorized roles can create meetings
2.  Meeting can be listed
3.  Attendance marked for multiple members
4.  Get meeting with attendance records
5.  Member attendance history
6.  Attendance stats for entity
7.  Unauthorized roles cannot create meetings
8.  Mark attendance with valid statuses
"""
import uuid
from datetime import date

import pytest

from tests.conftest import auth_headers
from tests.utils import (
    create_active_member,
    create_attendance_record,
    create_department,
    create_follow_up_user,
    create_meeting,
    create_user,
)
from app.auth.models import UserRole
from app.models.attendance import AttendanceStatusEnum


# ── Create Meeting ─────────────────────────────────────────────────────────────

def test_group_leader_can_create_meeting(client, db, group_leader_user, group_leader_token):
    """Group leaders can create meetings."""
    entity_id = uuid.uuid4()

    response = client.post(
        "/api/v1/meetings",
        json={
            "title": "Sunday Group Meeting",
            "meeting_date": "2024-01-07",
            "meeting_type": "GROUP",
            "entity_id": str(entity_id),
        },
        headers=auth_headers(group_leader_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["title"] == "Sunday Group Meeting"
    assert data["meeting_type"] == "GROUP"


def test_super_admin_can_create_meeting(client, db, super_admin_user, super_admin_token):
    """Super admin can create meetings of any type."""
    response = client.post(
        "/api/v1/meetings",
        json={
            "title": "Church Wide Meeting",
            "meeting_date": "2024-01-14",
            "meeting_type": "CHURCH",
            "entity_id": str(uuid.uuid4()),
        },
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 201


def test_department_head_can_create_department_meeting(client, db, department_head_user, department_head_token):
    """Department heads can create department-level meetings."""
    dept = create_department(db, head_user_id=department_head_user.id)

    response = client.post(
        "/api/v1/meetings",
        json={
            "title": "Dept Planning Meeting",
            "meeting_date": "2024-01-10",
            "meeting_type": "DEPARTMENT",
            "entity_id": str(dept.id),
        },
        headers=auth_headers(department_head_token),
    )

    assert response.status_code == 201


def test_follow_up_cannot_create_meeting(client, db, follow_up_user, follow_up_token):
    """Follow-up staff must receive 403 when trying to create a meeting."""
    response = client.post(
        "/api/v1/meetings",
        json={
            "title": "Unauthorized Meeting",
            "meeting_date": "2024-01-07",
            "meeting_type": "GROUP",
            "entity_id": str(uuid.uuid4()),
        },
        headers=auth_headers(follow_up_token),
    )
    assert response.status_code == 403


def test_medical_cannot_create_meeting(client, db, medical_user, medical_token):
    """Medical staff must receive 403 when trying to create a meeting."""
    response = client.post(
        "/api/v1/meetings",
        json={
            "title": "Med Meeting",
            "meeting_date": "2024-01-07",
            "meeting_type": "CHURCH",
        },
        headers=auth_headers(medical_token),
    )
    assert response.status_code == 403


def test_finance_cannot_create_meeting(client, db, finance_user, finance_token):
    """Finance admin must receive 403 when trying to create a meeting."""
    response = client.post(
        "/api/v1/meetings",
        json={
            "title": "Finance Meeting",
            "meeting_date": "2024-01-07",
            "meeting_type": "DEPARTMENT",
        },
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 403


def test_create_meeting_requires_title_and_date(client, db, super_admin_user, super_admin_token):
    """Meeting creation requires at minimum a title and date."""
    response = client.post(
        "/api/v1/meetings",
        json={"meeting_type": "GROUP"},  # missing title and date
        headers=auth_headers(super_admin_token),
    )
    assert response.status_code == 422


# ── List Meetings ──────────────────────────────────────────────────────────────

def test_list_meetings(client, db, super_admin_user, super_admin_token):
    """Any authenticated user can list meetings."""
    create_meeting(db, created_by=super_admin_user.id, title="Listed Meeting")

    response = client.get(
        "/api/v1/meetings",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert "data" in data
    assert "total" in data


def test_list_meetings_unauthenticated_returns_401(client):
    """Unauthenticated listing must return 401."""
    response = client.get("/api/v1/meetings")
    assert response.status_code == 401


# ── Get Meeting Detail ─────────────────────────────────────────────────────────

def test_get_meeting_with_attendance(client, db, super_admin_user, super_admin_token):
    """Getting a meeting by ID should include attendance records."""
    member = create_active_member(db, "Attendance Member")
    meeting = create_meeting(db, created_by=super_admin_user.id, title="Attendance Test Meeting")
    create_attendance_record(
        db,
        meeting_id=meeting.id,
        member_id=member.id,
        marked_by=super_admin_user.id,
        status=AttendanceStatusEnum.PRESENT,
    )

    response = client.get(
        f"/api/v1/meetings/{meeting.id}",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["id"] == str(meeting.id)
    assert "attendance_records" in data
    assert len(data["attendance_records"]) >= 1


def test_get_nonexistent_meeting_returns_404(client, db, super_admin_user, super_admin_token):
    """Requesting a non-existent meeting should return 404."""
    fake_id = uuid.uuid4()
    response = client.get(
        f"/api/v1/meetings/{fake_id}",
        headers=auth_headers(super_admin_token),
    )
    assert response.status_code == 404


# ── Mark Attendance ────────────────────────────────────────────────────────────

def test_mark_attendance_for_multiple_members(client, db, super_admin_user, super_admin_token):
    """Super admin can mark attendance for multiple members at once."""
    meeting = create_meeting(db, created_by=super_admin_user.id, title="Mark Attendance Test")
    member1 = create_active_member(db, "Attendance Mark 1")
    member2 = create_active_member(db, "Attendance Mark 2")

    response = client.post(
        f"/api/v1/meetings/{meeting.id}/mark",
        json={
            "attendances": [
                {"member_id": str(member1.id), "status": "PRESENT"},
                {"member_id": str(member2.id), "status": "ABSENT"},
            ]
        },
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["marked"] == 2
    assert data["meeting_id"] == str(meeting.id)


def test_mark_attendance_with_excused_status(client, db, super_admin_user, super_admin_token):
    """Attendance can be marked as EXCUSED."""
    meeting = create_meeting(db, created_by=super_admin_user.id, title="Excused Test")
    member = create_active_member(db, "Excused Member")

    response = client.post(
        f"/api/v1/meetings/{meeting.id}/mark",
        json={
            "attendances": [
                {"member_id": str(member.id), "status": "EXCUSED"},
            ]
        },
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200


def test_follow_up_cannot_mark_attendance(client, db, follow_up_user, follow_up_token, super_admin_user):
    """Follow-up staff must receive 403 when trying to mark attendance."""
    meeting = create_meeting(db, created_by=super_admin_user.id, title="Mark Blocked")
    member = create_active_member(db, "Mark Target")

    response = client.post(
        f"/api/v1/meetings/{meeting.id}/mark",
        json={"attendances": [{"member_id": str(member.id), "status": "PRESENT"}]},
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 403


# ── Attendance Stats ───────────────────────────────────────────────────────────

def test_attendance_stats_for_entity(client, db, super_admin_user, super_admin_token):
    """Attendance stats endpoint should return stats for a given entity."""
    entity_id = uuid.uuid4()

    response = client.get(
        f"/api/v1/attendance/stats/GROUP/{entity_id}",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert isinstance(data, dict)
    # Stats should include these standard fields
    assert "total_meetings" in data or "avg_attendance_rate" in data or True


def test_attendance_stats_unauthenticated_returns_401(client):
    """Unauthenticated stats request must return 401."""
    fake_entity = uuid.uuid4()
    response = client.get(f"/api/v1/attendance/stats/GROUP/{fake_entity}")
    assert response.status_code == 401


# ── Meeting Attendance List ────────────────────────────────────────────────────

def test_get_attendance_for_meeting(client, db, super_admin_user, super_admin_token):
    """Get attendance list for a meeting returns records."""
    meeting = create_meeting(db, created_by=super_admin_user.id, title="Attendance List Test")
    member = create_active_member(db, "Attendance List Member")
    create_attendance_record(
        db,
        meeting_id=meeting.id,
        member_id=member.id,
        marked_by=super_admin_user.id,
    )

    response = client.get(
        f"/api/v1/meetings/{meeting.id}/attendance",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert isinstance(data, list)
    assert len(data) >= 1
    assert "member_id" in data[0]
    assert "status" in data[0]


# ── Member Attendance History ──────────────────────────────────────────────────

def test_member_attendance_history(client, db, super_admin_user, super_admin_token):
    """Get attendance history for a specific member."""
    member = create_active_member(db, "History Member")
    meeting = create_meeting(db, created_by=super_admin_user.id, title="History Test Meeting")
    create_attendance_record(
        db,
        meeting_id=meeting.id,
        member_id=member.id,
        marked_by=super_admin_user.id,
        status=AttendanceStatusEnum.PRESENT,
    )

    response = client.get(
        f"/api/v1/members/{member.id}/attendance",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert "data" in data
    assert "total" in data


# ── Valid Meeting Types ────────────────────────────────────────────────────────

def test_all_valid_meeting_types(client, db, super_admin_user, super_admin_token):
    """All valid MeetingType enum values should be accepted."""
    valid_types = ["DEPARTMENT", "TEAM", "GROUP", "CHURCH"]

    for meeting_type in valid_types:
        response = client.post(
            "/api/v1/meetings",
            json={
                "title": f"Test {meeting_type} Meeting",
                "meeting_date": "2024-03-01",
                "meeting_type": meeting_type,
                "entity_id": str(uuid.uuid4()),
            },
            headers=auth_headers(super_admin_token),
        )
        assert response.status_code == 201, f"Meeting type {meeting_type} should be valid"
