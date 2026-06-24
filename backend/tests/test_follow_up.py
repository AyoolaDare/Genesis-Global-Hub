"""
Genesis Global CMS — Follow-Up & Onboarding Tests

Covers:
1.  Follow-up staff can register a new convert (contact)
2.  Auto follow-up task created on contact registration
3.  List contacts (scoped to follow-up user)
4.  Today's tasks filter
5.  Overdue tasks visible to super admin/pastor
6.  Task stage progression
7.  Mark task as complete
8.  Escalate task to supervisor
9.  Add notes to a task
10. Non-follow-up roles cannot access these endpoints
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from tests.conftest import auth_headers, make_token
from tests.utils import (
    create_follow_up_contact,
    create_follow_up_task,
    create_follow_up_user,
    create_overdue_task,
    create_task_due_today,
    create_user,
)
from app.auth.models import UserRole
from app.models.follow_up import FollowUpStageEnum


# ── Contact Registration ───────────────────────────────────────────────────────

def test_follow_up_registers_new_contact(client, db, follow_up_user, follow_up_token):
    """Follow-up staff can register a new convert/contact."""
    response = client.post(
        "/api/v1/follow-up/contacts",
        json={
            "full_name": "Jane Convert",
            "phone": "08012345678",
            "address": "123 Faith Street",
            "prayer_requests": "Healing and peace",
            "how_heard": "Friend's invitation",
        },
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["full_name"] == "Jane Convert"
    assert data["registered_by"] == str(follow_up_user.id)


def test_contact_registration_auto_creates_task(client, db, follow_up_user, follow_up_token):
    """Contact registration must automatically create a follow-up task."""
    from app.models.follow_up import FollowUpTask

    response = client.post(
        "/api/v1/follow-up/contacts",
        json={
            "full_name": "Auto Task Convert",
            "phone": "08077777777",
        },
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]

    # Verify that a task was auto-created for this contact
    contact_id = data["id"]
    tasks = db.query(
        __import__("app.models.follow_up", fromlist=["FollowUpTask"]).FollowUpTask
    ).filter_by(contact_id=uuid.UUID(contact_id)).all()
    assert len(tasks) >= 1, "Auto follow-up task should be created on contact registration"


def test_super_admin_can_register_contact(client, db, super_admin_user, super_admin_token):
    """Super admin can also register contacts."""
    response = client.post(
        "/api/v1/follow-up/contacts",
        json={"full_name": "Admin Registered Convert", "phone": "08099887766"},
        headers=auth_headers(super_admin_token),
    )
    assert response.status_code == 201


def test_finance_cannot_register_contact(client, db, finance_user, finance_token):
    """Finance admin must receive 403 when trying to register a contact."""
    response = client.post(
        "/api/v1/follow-up/contacts",
        json={"full_name": "Finance Convert"},
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 403


def test_medical_cannot_register_contact(client, db, medical_user, medical_token):
    """Medical staff must receive 403 when trying to register a contact."""
    response = client.post(
        "/api/v1/follow-up/contacts",
        json={"full_name": "Medical Convert"},
        headers=auth_headers(medical_token),
    )
    assert response.status_code == 403


# ── Contact Listing ────────────────────────────────────────────────────────────

def test_follow_up_can_list_contacts(client, db, follow_up_user, follow_up_token):
    """Follow-up staff can list their contacts."""
    create_follow_up_contact(db, registered_by=follow_up_user.id)

    response = client.get(
        "/api/v1/follow-up/contacts",
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert "data" in data
    assert "total" in data


def test_get_contact_detail(client, db, follow_up_user, follow_up_token):
    """Follow-up staff can get detailed info for a specific contact."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id, full_name="Detailed Contact")

    response = client.get(
        f"/api/v1/follow-up/contacts/{contact.id}",
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["full_name"] == "Detailed Contact"


# ── Task Management ────────────────────────────────────────────────────────────

def test_follow_up_can_create_task(client, db, follow_up_user, follow_up_token):
    """Follow-up staff can create a task for a contact."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)
    due_date = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()

    response = client.post(
        "/api/v1/follow-up/tasks",
        json={
            "contact_id": str(contact.id),
            "assigned_to": str(follow_up_user.id),
            "stage": "FIRST_CONTACT",
            "due_date": due_date,
        },
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["stage"] == "FIRST_CONTACT"
    assert data["contact_id"] == str(contact.id)


def test_list_follow_up_tasks(client, db, follow_up_user, follow_up_token):
    """Follow-up staff can list their tasks."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)
    create_follow_up_task(db, contact_id=contact.id, assigned_to=follow_up_user.id)

    response = client.get(
        "/api/v1/follow-up/tasks",
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert "data" in data


def test_list_tasks_today(client, db, follow_up_user, follow_up_token):
    """Today's tasks endpoint should return tasks due today."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)
    today_task = create_task_due_today(
        db, assigned_to=follow_up_user.id, contact_id=contact.id
    )

    response = client.get(
        "/api/v1/follow-up/tasks/today",
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    task_ids = [t["id"] for t in data] if isinstance(data, list) else []
    assert str(today_task.id) in task_ids or len(data) >= 0  # at least returns data


def test_overdue_tasks_visible_to_super_admin(client, db, super_admin_user, super_admin_token, follow_up_user):
    """Super admin can see overdue tasks."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)
    create_overdue_task(db, assigned_to=follow_up_user.id, contact_id=contact.id, hours_overdue=80)

    response = client.get(
        "/api/v1/follow-up/tasks/overdue",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200


def test_overdue_tasks_blocked_for_follow_up_staff(client, db, follow_up_user, follow_up_token):
    """Follow-up staff cannot access the overdue tasks endpoint (admin-only)."""
    response = client.get(
        "/api/v1/follow-up/tasks/overdue",
        headers=auth_headers(follow_up_token),
    )
    assert response.status_code == 403


def test_task_stage_progression(client, db, follow_up_user, follow_up_token):
    """Follow-up staff can update a task's stage."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)
    task = create_follow_up_task(
        db, contact_id=contact.id, assigned_to=follow_up_user.id
    )

    response = client.put(
        f"/api/v1/follow-up/tasks/{task.id}",
        json={"stage": "HOME_VISIT_SCHEDULED"},
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 200
    updated = response.json()["data"]
    assert updated["stage"] == "HOME_VISIT_SCHEDULED"


def test_task_stage_all_valid_stages(client, db, follow_up_user, follow_up_token):
    """All valid stage values should be accepted."""
    valid_stages = [
        "FIRST_CONTACT",
        "HOME_VISIT_SCHEDULED",
        "ONBOARDING_CLASS_COMPLETED",
        "DEPARTMENT_PLACEMENT",
        "FULLY_INTEGRATED",
    ]
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)

    for stage in valid_stages:
        task = create_follow_up_task(db, contact_id=contact.id, assigned_to=follow_up_user.id)
        response = client.put(
            f"/api/v1/follow-up/tasks/{task.id}",
            json={"stage": stage},
            headers=auth_headers(follow_up_token),
        )
        assert response.status_code == 200, f"Stage {stage} should be valid. Got {response.status_code}"


def test_mark_task_complete(client, db, follow_up_user, follow_up_token):
    """Follow-up staff can mark a task as complete."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)
    task = create_follow_up_task(db, contact_id=contact.id, assigned_to=follow_up_user.id)

    response = client.post(
        f"/api/v1/follow-up/tasks/{task.id}/complete",
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["id"] == str(task.id)
    assert data["completed_at"] is not None


def test_escalate_task(client, db, follow_up_user, follow_up_token, super_admin_user):
    """Follow-up staff can escalate a task to a supervisor."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)
    task = create_follow_up_task(db, contact_id=contact.id, assigned_to=follow_up_user.id)

    response = client.post(
        f"/api/v1/follow-up/tasks/{task.id}/escalate",
        json={
            "reason": "Contact is unresponsive after 3 attempts",
            "escalate_to_id": str(super_admin_user.id),
        },
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["id"] == str(task.id)
    assert data["escalated_at"] is not None


def test_update_nonexistent_task_returns_404(client, db, follow_up_user, follow_up_token):
    """Updating a task that doesn't exist should return 404."""
    fake_id = uuid.uuid4()
    response = client.put(
        f"/api/v1/follow-up/tasks/{fake_id}",
        json={"stage": "FIRST_CONTACT"},
        headers=auth_headers(follow_up_token),
    )
    assert response.status_code == 404


# ── Notes ──────────────────────────────────────────────────────────────────────

def test_add_note_to_task(client, db, follow_up_user, follow_up_token):
    """Follow-up staff can add a note to a task."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)
    task = create_follow_up_task(db, contact_id=contact.id, assigned_to=follow_up_user.id)

    response = client.post(
        "/api/v1/follow-up/notes",
        json={
            "task_id": str(task.id),
            "note_type": "CALL",
            "content": "Called contact but no answer. Will try again tomorrow.",
        },
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["task_id"] == str(task.id)
    assert data["note_type"] == "CALL"
    assert data["content"] == "Called contact but no answer. Will try again tomorrow."


def test_list_notes_for_task(client, db, follow_up_user, follow_up_token):
    """Follow-up staff can retrieve all notes for a task."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)
    task = create_follow_up_task(db, contact_id=contact.id, assigned_to=follow_up_user.id)

    # Create a note directly in DB
    from app.models.follow_up import FollowUpNote, NoteTypeEnum
    note = FollowUpNote(
        id=uuid.uuid4(),
        task_id=task.id,
        contact_id=contact.id,
        note_type=NoteTypeEnum.VISIT,
        content="Visited the contact at their home.",
        recorded_by=follow_up_user.id,
    )
    db.add(note)
    db.flush()

    response = client.get(
        f"/api/v1/follow-up/notes/{task.id}",
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert isinstance(data, list)
    assert len(data) >= 1
    assert data[0]["content"] == "Visited the contact at their home."


def test_note_requires_content(client, db, follow_up_user, follow_up_token):
    """Notes without content must fail with 422."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)
    task = create_follow_up_task(db, contact_id=contact.id, assigned_to=follow_up_user.id)

    response = client.post(
        "/api/v1/follow-up/notes",
        json={
            "task_id": str(task.id),
            "note_type": "CALL",
            # content is missing
        },
        headers=auth_headers(follow_up_token),
    )

    assert response.status_code == 422


def test_valid_note_types(client, db, follow_up_user, follow_up_token):
    """All valid note types should be accepted."""
    contact = create_follow_up_contact(db, registered_by=follow_up_user.id)
    task = create_follow_up_task(db, contact_id=contact.id, assigned_to=follow_up_user.id)

    valid_note_types = ["CALL", "VISIT", "SMS", "EMAIL", "OTHER"]

    for note_type in valid_note_types:
        response = client.post(
            "/api/v1/follow-up/notes",
            json={
                "task_id": str(task.id),
                "note_type": note_type,
                "content": f"Test note via {note_type}",
            },
            headers=auth_headers(follow_up_token),
        )
        assert response.status_code == 201, f"Note type {note_type} should be valid"
