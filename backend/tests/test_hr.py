"""
Genesis Global CMS — HR & Workers Tests (Isolated Domain)

Covers:
1.  HR admin can list workers
2.  HR admin can create worker
3.  HR admin can get worker detail
4.  HR admin can update worker
5.  member_link_id never appears in worker responses
6.  HR admin can create performance review
7.  HR admin can list reviews for a worker
8.  HR admin can submit leave request
9.  HR admin can approve/reject leave
10. HR admin can award recognition
11. HR dashboard accessible to HR admin
12. Non-HR roles cannot access HR endpoints
"""
import uuid
from datetime import date, datetime, timezone

import pytest

from tests.conftest import auth_headers
from tests.utils import (
    create_department,
    create_user,
    create_worker,
)
from app.auth.models import UserRole
from app.models.hr import EmploymentTypeEnum, LeaveStatusEnum


# ── List Workers ───────────────────────────────────────────────────────────────

def test_hr_admin_can_list_workers(client, db, hr_user, hr_token):
    """HR admin can list all workers."""
    create_worker(db, created_by=hr_user.id, full_name="Listed Worker Alpha")

    response = client.get(
        "/api/v1/hr/workers",
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert "data" in data
    assert "total" in data


def test_super_admin_can_list_workers(client, db, super_admin_user, super_admin_token):
    """Super admin can also list workers."""
    response = client.get(
        "/api/v1/hr/workers",
        headers=auth_headers(super_admin_token),
    )
    assert response.status_code == 200


def test_list_workers_excludes_member_link_id(client, db, hr_user, hr_token):
    """Worker list must never include member_link_id."""
    worker = create_worker(db, created_by=hr_user.id)
    worker.member_link_id = uuid.uuid4()
    db.flush()

    response = client.get("/api/v1/hr/workers", headers=auth_headers(hr_token))

    assert response.status_code == 200
    assert "member_link_id" not in response.text


def test_finance_cannot_list_workers(client, db, finance_user, finance_token):
    """Finance admin must receive 403 when accessing workers."""
    response = client.get("/api/v1/hr/workers", headers=auth_headers(finance_token))
    assert response.status_code == 403


def test_medical_cannot_list_workers(client, db, medical_user, medical_token):
    """Medical staff must receive 403 when accessing workers."""
    response = client.get("/api/v1/hr/workers", headers=auth_headers(medical_token))
    assert response.status_code == 403


def test_follow_up_cannot_list_workers(client, db, follow_up_user, follow_up_token):
    """Follow-up staff must receive 403 when accessing workers."""
    response = client.get("/api/v1/hr/workers", headers=auth_headers(follow_up_token))
    assert response.status_code == 403


def test_pastor_cannot_list_workers(client, db, pastor_user, pastor_token):
    """Pastor must receive 403 when accessing workers."""
    response = client.get("/api/v1/hr/workers", headers=auth_headers(pastor_token))
    assert response.status_code == 403


# ── Create Worker ──────────────────────────────────────────────────────────────

def test_hr_admin_can_create_worker(client, db, hr_user, hr_token):
    """HR admin can create a new worker record."""
    dept = create_department(db, name="HR Worker Test Dept")

    response = client.post(
        "/api/v1/hr/workers",
        json={
            "full_name": "Sister Amaka Okonkwo",
            "phone": "08033334444",
            "email": "amaka@genesis.ng",
            "employment_type": "VOLUNTEER",
            "department_id": str(dept.id),
            "role_title": "Children's Ministry Lead",
            "start_date": "2024-01-01",
        },
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["full_name"] == "Sister Amaka Okonkwo"
    assert data["employment_type"] == "VOLUNTEER"
    assert "member_link_id" not in data


def test_create_worker_missing_required_fields(client, db, hr_user, hr_token):
    """Creating a worker without required fields must fail with 422."""
    response = client.post(
        "/api/v1/hr/workers",
        json={"phone": "08011112222"},  # missing full_name and employment_type
        headers=auth_headers(hr_token),
    )
    assert response.status_code == 422


def test_non_hr_cannot_create_worker(client, db, finance_user, finance_token):
    """Finance admin must receive 403 when trying to create a worker."""
    response = client.post(
        "/api/v1/hr/workers",
        json={"full_name": "Finance Worker", "employment_type": "VOLUNTEER"},
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 403


# ── Get Worker Detail ──────────────────────────────────────────────────────────

def test_hr_admin_can_get_worker_detail(client, db, hr_user, hr_token):
    """HR admin can retrieve a specific worker's details."""
    worker = create_worker(db, created_by=hr_user.id, full_name="Detail Worker")

    response = client.get(
        f"/api/v1/hr/workers/{worker.id}",
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["full_name"] == "Detail Worker"
    assert "member_link_id" not in data


def test_get_nonexistent_worker_returns_404(client, db, hr_user, hr_token):
    """Requesting a non-existent worker should return 404."""
    fake_id = uuid.uuid4()
    response = client.get(
        f"/api/v1/hr/workers/{fake_id}",
        headers=auth_headers(hr_token),
    )
    assert response.status_code == 404


# ── Update Worker ──────────────────────────────────────────────────────────────

def test_hr_admin_can_update_worker(client, db, hr_user, hr_token):
    """HR admin can update a worker's information."""
    worker = create_worker(db, created_by=hr_user.id, full_name="Update Worker")

    response = client.put(
        f"/api/v1/hr/workers/{worker.id}",
        json={"role_title": "Senior Volunteer", "status": "ACTIVE"},
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["role_title"] == "Senior Volunteer"
    assert "member_link_id" not in data


# ── Performance Reviews ────────────────────────────────────────────────────────

def test_hr_admin_can_create_performance_review(client, db, hr_user, hr_token):
    """HR admin can create a performance review for a worker."""
    worker = create_worker(db, created_by=hr_user.id, full_name="Review Worker")

    response = client.post(
        f"/api/v1/hr/workers/{worker.id}/reviews",
        json={
            "review_period_start": "2024-01-01",
            "review_period_end": "2024-03-31",
            "self_score": 4,
            "supervisor_score": 4,
            "overall_score": 4.0,
            "strengths": "Excellent communication and teamwork",
            "areas_for_growth": "Time management",
            "goals": "Lead a new ministry outreach",
        },
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["worker_id"] == str(worker.id)


def test_hr_admin_can_list_reviews(client, db, hr_user, hr_token):
    """HR admin can list performance reviews for a worker."""
    worker = create_worker(db, created_by=hr_user.id, full_name="Review List Worker")

    # Create a review directly in DB
    from app.models.hr import WorkerPerformanceReview
    review = WorkerPerformanceReview(
        id=uuid.uuid4(),
        worker_id=worker.id,
        review_period_start=date(2024, 1, 1),
        review_period_end=date(2024, 3, 31),
        reviewer_id=hr_user.id,
        overall_score=4.0,
    )
    db.add(review)
    db.flush()

    response = client.get(
        f"/api/v1/hr/workers/{worker.id}/reviews",
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1


# ── Leave Requests ─────────────────────────────────────────────────────────────

def test_hr_admin_can_create_leave_request(client, db, hr_user, hr_token):
    """HR admin can submit a leave request for a worker."""
    worker = create_worker(db, created_by=hr_user.id, full_name="Leave Worker")

    response = client.post(
        f"/api/v1/hr/workers/{worker.id}/leave",
        json={
            "leave_type": "ANNUAL",
            "start_date": "2024-04-01",
            "end_date": "2024-04-07",
            "reason": "Family vacation",
        },
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["worker_id"] == str(worker.id)
    assert data["leave_type"] == "ANNUAL"
    assert data["status"] == "PENDING"


def test_hr_admin_can_approve_leave_request(client, db, hr_user, hr_token):
    """HR admin can approve a pending leave request."""
    worker = create_worker(db, created_by=hr_user.id, full_name="Approve Leave Worker")

    # Create leave request in DB
    from app.models.hr import WorkerLeaveRequest
    leave = WorkerLeaveRequest(
        id=uuid.uuid4(),
        worker_id=worker.id,
        leave_type="SICK",
        start_date=date(2024, 5, 1),
        end_date=date(2024, 5, 3),
        status="PENDING",
    )
    db.add(leave)
    db.flush()

    response = client.put(
        f"/api/v1/hr/leave/{leave.id}/approve",
        json={"status": "APPROVED", "notes": "Approved as requested"},
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["status"] == "APPROVED"


def test_hr_admin_can_reject_leave_request(client, db, hr_user, hr_token):
    """HR admin can reject a pending leave request."""
    worker = create_worker(db, created_by=hr_user.id, full_name="Reject Leave Worker")

    from app.models.hr import WorkerLeaveRequest
    leave = WorkerLeaveRequest(
        id=uuid.uuid4(),
        worker_id=worker.id,
        leave_type="PERSONAL",
        start_date=date(2024, 6, 1),
        end_date=date(2024, 6, 2),
        status="PENDING",
    )
    db.add(leave)
    db.flush()

    response = client.put(
        f"/api/v1/hr/leave/{leave.id}/approve",
        json={"status": "REJECTED", "notes": "Rejected due to busy period"},
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["status"] == "REJECTED"


def test_hr_admin_can_list_leave_requests(client, db, hr_user, hr_token):
    """HR admin can list leave requests for a worker."""
    worker = create_worker(db, created_by=hr_user.id, full_name="Leave List Worker")

    from app.models.hr import WorkerLeaveRequest
    leave = WorkerLeaveRequest(
        id=uuid.uuid4(),
        worker_id=worker.id,
        leave_type="ANNUAL",
        start_date=date(2024, 7, 1),
        end_date=date(2024, 7, 5),
        status="PENDING",
    )
    db.add(leave)
    db.flush()

    response = client.get(
        f"/api/v1/hr/workers/{worker.id}/leave",
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1


# ── Recognitions ───────────────────────────────────────────────────────────────

def test_hr_admin_can_award_recognition(client, db, hr_user, hr_token):
    """HR admin can award a recognition to a worker."""
    worker = create_worker(db, created_by=hr_user.id, full_name="Recognition Worker")

    response = client.post(
        f"/api/v1/hr/workers/{worker.id}/recognitions",
        json={
            "recognition_type": "AWARD",
            "title": "Volunteer of the Month",
            "description": "Outstanding dedication to the children's ministry.",
        },
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["title"] == "Volunteer of the Month"
    assert data["recognition_type"] == "AWARD"
    assert data["worker_id"] == str(worker.id)


def test_hr_admin_can_list_recognitions(client, db, hr_user, hr_token):
    """HR admin can list recognitions for a worker."""
    worker = create_worker(db, created_by=hr_user.id, full_name="Recognitions List Worker")

    from app.models.hr import WorkerRecognition
    recognition = WorkerRecognition(
        id=uuid.uuid4(),
        worker_id=worker.id,
        recognition_type="COMMENDATION",
        title="Faithful Service",
        awarded_by=hr_user.id,
    )
    db.add(recognition)
    db.flush()

    response = client.get(
        f"/api/v1/hr/workers/{worker.id}/recognitions",
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1


# ── HR Dashboard ───────────────────────────────────────────────────────────────

def test_hr_dashboard_accessible_to_hr_admin(client, db, hr_user, hr_token):
    """HR admin can access the HR dashboard."""
    response = client.get(
        "/api/v1/hr/dashboard",
        headers=auth_headers(hr_token),
    )

    assert response.status_code == 200
    assert response.json()["success"] is True


def test_hr_dashboard_blocked_for_finance(client, db, finance_user, finance_token):
    """Finance admin must not access the HR dashboard."""
    response = client.get(
        "/api/v1/hr/dashboard",
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 403


def test_hr_dashboard_blocked_for_medical(client, db, medical_user, medical_token):
    """Medical staff must not access the HR dashboard."""
    response = client.get(
        "/api/v1/hr/dashboard",
        headers=auth_headers(medical_token),
    )
    assert response.status_code == 403


# ── Employment Type Values ─────────────────────────────────────────────────────

def test_all_valid_employment_types(client, db, hr_user, hr_token):
    """All valid employment type values must be accepted."""
    valid_types = ["VOLUNTEER", "PART_TIME", "FULL_TIME"]

    for emp_type in valid_types:
        response = client.post(
            "/api/v1/hr/workers",
            json={
                "full_name": f"Worker {emp_type}",
                "employment_type": emp_type,
            },
            headers=auth_headers(hr_token),
        )
        assert response.status_code == 201, (
            f"Employment type {emp_type} should be valid, got {response.status_code}"
        )
